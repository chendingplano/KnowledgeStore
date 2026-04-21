---
title: Prompt Optimizer Feature — Design Document
project: ChenWeb
component: prompt-optimizer
created: 2026-04-20
author: Chen Ding (with AI assistance)
status: approved (ready to plan)
related:
  - /Users/cding/Workspace/ThirdParty/prompt-optimizer/ (upstream OSS reference)
  - /Users/cding/Workspace/KnowledgeStore/AI/Prompt-Optimizer.md (upstream summary)
  - /Users/cding/Workspace/ChenWeb/web/src/routes/home3/+page.svelte (host UI)
  - /Users/cding/Workspace/shared/go/ (shared libraries)
---

# Prompt Optimizer — Design Document

## 1. Goal

Deliver a first-class **Prompt Optimizer** inside ChenWeb that lets a
signed-in user:

1. Paste a raw prompt and have an LLM rewrite it into a clearer, more
   structured, more effective prompt.
2. Iterate on the optimization with additional guidance.
3. Run both the original and optimized prompts side-by-side against a test
   input to compare LLM outputs (2/3/4-column compare).
4. Manage the full supporting surface: optimization templates, history,
   favorites, named variables, model configurations, and JSON
   import/export.
5. Access all of this through a new menu item at
   **`Prompts → Prompt Optimizer`** in ChenWeb `home3`.

The feature is inspired by the OSS project
[`linshenkx/prompt-optimizer`](https://github.com/linshenkx/prompt-optimizer)
but is implemented natively in ChenWeb's stack (Svelte 5 + Go/PostgreSQL)
rather than embedding the upstream Vue 3 client.

## 2. Why re-implement instead of reuse

The upstream project was investigated as a potential drop-in. It is not
cleanly reusable, for three independent reasons:

| Reason | Detail |
|---|---|
| Framework mismatch | Upstream UI is Vue 3. ChenWeb web is Svelte 5. No direct component reuse. |
| License contamination | Upstream is **AGPL-3.0 (copyleft)**. Bundling the TS core or UI would force ChenWeb (and anything that links to it) to also distribute under AGPL-3.0. Not desired. |
| Storage assumptions | The core library assumes client-side storage (Dexie/IndexedDB, `localStorage`). ChenWeb is a server-backed app with PostgreSQL; ports of the core would fight the host architecture. |

The *essence* of the feature — send the user's raw prompt plus an
optimization-template system prompt to an LLM and stream the result back
— is small. We re-implement natively, using upstream only as **functional
reference** for which templates to seed, which UX flows to mirror, and
which models to support.

No upstream code is copied. Default optimization templates will be
authored clean-room in plain English, even though the *idea* of a
"general-optimize" template is not novel.

## 3. Scope

### 3.1 In scope (tier C — full)

- System-prompt optimization
- User-prompt optimization
- Basic tab, Context tab (variables), Image tab (text2image /
  image2image / multi-image)
- Templates CRUD (seeded defaults + user-owned)
- History (every optimize / iterate / test run persisted)
- Model Manager (per-user provider configs with encrypted API keys)
- Favorites library
- Variable Manager
- Data import/export (JSON)
- Analyze (LLM explains why a prompt is weak and what to improve)
- A/B/C/D side-by-side test compare (2 / 3 / 4 column modes)
- Dark / light theme that matches `home3`
- Multi-language not required for v1 (English only). Structure stays
  i18n-ready (no hard-coded strings in template records).

### 3.2 Out of scope (v1)

- MCP server integration (upstream has one; we defer)
- Desktop / Chrome-extension packaging (upstream has these; we defer)
- Realtime multi-user collaboration
- Prompt evaluation harness / scoring beyond single-shot A/B compare
- Automatic variable extraction service (upstream has one; can be added
  in a later slice)

### 3.3 Phased rollout inside tier C

Because tier C is wide, it ships in three slices so each is independently
usable:

| Slice | Delivers | "Done when" |
|---|---|---|
| 1 — MVP | LLM Go module, migrations, models + templates + history endpoints, Studio with single-column test, Models/Templates/History modals, nav-rail entry | User can paste a prompt, pick a model + template, get an optimized version, and test it against content. |
| 2 — Full Basic+Context | Variables, Variable Manager, Favorites, Favorite Library, Analyze, 2/3/4-column compare, Data import/export | Full reference-image functionality for text optimization. |
| 3 — Image | Image tab (text2image / image2image / multiimage), image adapters for providers that support them | Image-prompt optimization parity. |

Each slice ends with a working end-to-end path; nothing in an earlier
slice blocks on a later one.

## 4. Success criteria

- A signed-in user at `home3` sees `Prompts → Prompt Optimizer` in the
  nav-rail.
- Clicking the child opens `/home3/prompt-optimizer` (new tab) and the
  Studio loads in < 500 ms on a warm reload.
- With at least one Model and one Template configured, an "Optimize"
  action streams tokens into the Workspace pane within 2 s of button
  press (assuming provider responds in typical time).
- "Run All" in the test panel streams outputs into all active columns
  concurrently.
- API keys never appear in network responses, frontend bundles, or
  browser storage.
- All optimize / iterate / test runs appear in History, scoped to the
  user.
- Full browser refresh preserves: Models, Templates, History,
  Favorites, Variables. UI-only state (theme, column count, last
  template selected) persists via `localStorage`.

## 5. Architecture overview

```
┌──────────────────────────────────────────────────────────┐
│ Browser — ChenWeb Web (Svelte 5)                         │
│                                                          │
│  routes/home3/+page.svelte          (host, nav-rail)     │
│    └─ Prompts ▸ Prompt Optimizer  → window.open(...)     │
│                                                          │
│  routes/home3/prompt-optimizer/+page.svelte              │
│    └─ PromptOptimizerStudio.svelte                       │
│         ├─ TopBar                                        │
│         ├─ OriginalPromptPanel                           │
│         ├─ WorkspacePanel                                │
│         ├─ TestPanel  ─ TestColumn × N                   │
│         └─ Modals: Templates, History, ModelManager,     │
│                     FavoriteLibrary, DataManager,        │
│                     VariableManager                      │
└──────────────────────────────────────────────────────────┘
                 │  JSON / SSE over cookie-based session auth
                 ▼
┌──────────────────────────────────────────────────────────┐
│ ChenWeb Server (Go / Echo)                               │
│  server/api/promptoptimizerhandler/                      │
│    handlers: templates, history, models, favorites,      │
│              variables, optimize, iterate, test,         │
│              analyze, data (export/import)               │
└──────────────────────────────────────────────────────────┘
         │                                  │
         ▼                                  ▼
┌──────────────────────────────┐   ┌──────────────────────┐
│ shared/go/api/llm/           │   │ PostgreSQL           │
│   - Client interface          │   │  prompt_optimizer_*  │
│   - adapters/openai           │   │  tables              │
│   - adapters/anthropic        │   │  (goose-migrated)    │
│   - adapters/gemini           │   └──────────────────────┘
│   - adapters/openai_compat    │
│   - types, factory            │
└──────────────────────────────┘
```

## 6. Reusable Go LLM module — `shared/go/api/llm/`

### 6.1 Purpose

Centralize all "talk to an LLM provider" logic in one place, so ChenWeb,
tax, and any other workspace project can reuse it without re-implementing
per-provider wire formats.

### 6.2 Public surface (draft)

```go
package llm

// ProviderID enumerates supported providers.
type ProviderID string

const (
    ProviderOpenAI           ProviderID = "openai"
    ProviderAnthropic        ProviderID = "anthropic"
    ProviderGemini           ProviderID = "gemini"
    ProviderOpenAICompatible ProviderID = "openai_compatible" // Ollama, DeepSeek, etc.
)

type ProviderConfig struct {
    ID         ProviderID
    BaseURL    string            // empty → adapter default
    APIKey     string
    HTTPClient *http.Client      // optional
    Extra      map[string]string // provider-specific
}

type Role string

const (
    RoleSystem    Role = "system"
    RoleUser      Role = "user"
    RoleAssistant Role = "assistant"
    RoleTool      Role = "tool"
)

type Message struct {
    Role       Role
    Content    string
    Parts      []ContentPart // optional multimodal parts
    ToolCalls  []ToolCall
    ToolCallID string
}

type ContentPart struct {
    Type     string // "text" | "image_url" | "image_b64"
    Text     string
    ImageURL string
    ImageB64 string
    MIME     string
}

type Request struct {
    Model       string
    Messages    []Message
    Temperature *float64
    MaxTokens   *int
    TopP        *float64
    Stream      bool
    Tools       []ToolDef
    ToolChoice  string
}

type Response struct {
    Content   string
    ToolCalls []ToolCall
    Raw       json.RawMessage // adapter-specific for debugging
    Usage     *Usage
}

type StreamChunk struct {
    Delta        string
    ToolCall     *ToolCall
    Done         bool
    FinishReason string
    Usage        *Usage
}

type Client interface {
    Complete(ctx context.Context, req Request) (*Response, error)
    Stream(ctx context.Context, req Request, on func(StreamChunk) error) error
}

// NewClient returns an adapter-backed client for the given provider.
func NewClient(cfg ProviderConfig) (Client, error)
```

### 6.3 Design principles

- **No heavy SDKs.** Each adapter uses `net/http` + `encoding/json` to
  speak the provider's REST API directly. Keeps `shared/go` dependency
  footprint small; makes the module easy to audit.
- **Streaming is a first-class verb.** `Stream()` takes a callback so
  adapters can back-pressure from SSE parsing into the caller.
- **Context-cancelable.** Passing a canceled `ctx` aborts the in-flight
  HTTP request and closes the stream reader.
- **No global state.** No package-level clients, no `init()` side
  effects. Every call site passes explicit config.
- **Tests use `httptest.Server`.** Adapter-level tests record
  request/response fixtures; no live network calls in CI.

### 6.4 Logging & errors

- Uses `shared/go/api/loggerutil` with module code `LLM_xxx`.
- Errors carry provider + model + HTTP-status context.
- API keys are never logged (redaction at `Request` level before logging).

## 7. Encryption of API keys at rest

Per decision in brainstorming:

- New utility `shared/go/api/security/aesgcm.go` exposes
  `EncryptString(plaintext, key) (ciphertextBase64, error)` and
  `DecryptString(ciphertextBase64, key) (plaintext, error)`.
- Key source: env var `PROMPT_OPTIMIZER_ENCRYPTION_KEY`, base64-encoded
  32-byte random.
- Helper: `security.LoadKeyFromEnv(varName)` returns the bytes and
  validates length.
- If the env var is missing at startup, the server refuses to start
  rather than silently storing plaintext keys.
- `prompt_optimizer_models.api_key_encrypted` stores the ciphertext.
- Plaintext keys are **never** returned in any API response. The
  frontend gets a masked preview (`sk-…abcd`) for display.

## 8. PostgreSQL schema (goose migration)

One new goose migration file in
`ChenWeb/project_migrations/NNN_prompt_optimizer.sql`:

```sql
-- +goose Up
CREATE TABLE prompt_optimizer_models (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name              TEXT NOT NULL,
    provider          TEXT NOT NULL,
    base_url          TEXT,
    model             TEXT NOT NULL,
    api_key_encrypted TEXT NOT NULL,
    default_params    JSONB NOT NULL DEFAULT '{}'::jsonb,
    enabled           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX prompt_optimizer_models_user_idx ON prompt_optimizer_models(user_id);

CREATE TABLE prompt_optimizer_templates (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID REFERENCES users(id) ON DELETE CASCADE, -- NULL = built-in seed
    kind        TEXT NOT NULL CHECK (kind IN ('optimize','iterate','test','analyze','user_optimize','image_optimize')),
    name        TEXT NOT NULL,
    description TEXT,
    content     TEXT NOT NULL,
    language    TEXT NOT NULL DEFAULT 'en',
    variables   JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX prompt_optimizer_templates_user_idx ON prompt_optimizer_templates(user_id);
CREATE INDEX prompt_optimizer_templates_kind_idx ON prompt_optimizer_templates(kind);

CREATE TABLE prompt_optimizer_history (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id          UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind             TEXT NOT NULL CHECK (kind IN ('optimize','iterate','test','analyze')),
    original_prompt  TEXT,
    optimized_prompt TEXT,
    test_input       TEXT,
    test_output      TEXT,
    template_id      UUID REFERENCES prompt_optimizer_templates(id) ON DELETE SET NULL,
    model_id         UUID REFERENCES prompt_optimizer_models(id) ON DELETE SET NULL,
    params           JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX prompt_optimizer_history_user_idx    ON prompt_optimizer_history(user_id);
CREATE INDEX prompt_optimizer_history_created_idx ON prompt_optimizer_history(created_at DESC);

CREATE TABLE prompt_optimizer_favorites (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    ref_kind   TEXT NOT NULL CHECK (ref_kind IN ('history','template')),
    ref_id     UUID NOT NULL,
    note       TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, ref_kind, ref_id)
);

CREATE TABLE prompt_optimizer_variables (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name       TEXT NOT NULL,
    value      TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, name)
);

-- +goose Down
DROP TABLE IF EXISTS prompt_optimizer_variables;
DROP TABLE IF EXISTS prompt_optimizer_favorites;
DROP TABLE IF EXISTS prompt_optimizer_history;
DROP TABLE IF EXISTS prompt_optimizer_templates;
DROP TABLE IF EXISTS prompt_optimizer_models;
```

Notes:

- `user_id = NULL` in `prompt_optimizer_templates` marks seed rows.
  Seeding is done by the handler on first-read rather than in the
  migration, so we can refresh seeds without an ALTER.
- `ON DELETE CASCADE` for user data means a deleted ChenWeb user removes
  their prompt-optimizer data cleanly.
- Reserved-keyword caution per CLAUDE.md: no column named `user`,
  `role`, `content` in non-text contexts, etc. We use `kind`, `name`,
  `value`.

## 9. Backend API surface

All endpoints live under `/api/v1/prompt-optimizer/`, gated by
ChenWeb's existing JWT/session auth middleware. User id is always taken
from the session — never from a request field.

| Method | Path | Purpose |
|---|---|---|
| GET    | `/models`                   | List user's model configs (masked key) |
| POST   | `/models`                   | Create model config |
| PUT    | `/models/:id`               | Update model config |
| DELETE | `/models/:id`               | Delete model config |
| POST   | `/models/:id/test`          | One-shot ping: does the config work? |
| GET    | `/templates`                | List templates (built-in + user's) |
| POST   | `/templates`                | Create a user template |
| PUT    | `/templates/:id`            | Update a user template |
| DELETE | `/templates/:id`            | Delete a user template |
| GET    | `/history`                  | Paginated history list |
| GET    | `/history/:id`              | Single history record |
| DELETE | `/history/:id`              | Delete a history record |
| POST   | `/optimize` *(SSE)*         | Optimize a prompt (stream) |
| POST   | `/iterate`  *(SSE)*         | Iterate on an existing optimization (stream) |
| POST   | `/test`     *(SSE)*         | Run a prompt against a test input (stream) |
| POST   | `/analyze`  *(SSE)*         | Explain weaknesses in a prompt (stream) |
| GET    | `/favorites`                | List favorites |
| POST   | `/favorites`                | Add favorite |
| DELETE | `/favorites/:id`            | Remove favorite |
| GET    | `/variables`                | List variables |
| POST   | `/variables`                | Create variable |
| PUT    | `/variables/:id`            | Update variable |
| DELETE | `/variables/:id`            | Delete variable |
| POST   | `/data/export`              | Export everything to JSON |
| POST   | `/data/import`              | Import from JSON (replace or merge flag) |

Streaming endpoints emit Server-Sent Events shaped as:

```
event: delta
data: {"text":"partial"}

event: done
data: {"usage":{"in":123,"out":456}}
```

The frontend consumes with `fetch` + `ReadableStream` — no extra SSE
library needed.

## 10. Frontend architecture (Svelte 5)

### 10.1 Route

- New: `ChenWeb/web/src/routes/home3/prompt-optimizer/+page.svelte`
- The `home3` nav-rail adds a new item (see §11) which calls
  `window.open('/home3/prompt-optimizer?dark=…')`, matching the existing
  pattern used by `kb-metrics` and `kb-input-details`.
- The route is a full-viewport studio; no context shelf, no
  home3 rail — it owns the screen.

### 10.2 Component layout

```
components/prompt-optimizer/
├── PromptOptimizerStudio.svelte     (page shell, top-level state)
├── TopBar.svelte                    (Basic|Context|Image + System|User + right buttons)
├── OriginalPromptPanel.svelte       (textarea + Model/Template + Analyze/Optimize)
├── WorkspacePanel.svelte            (optimized output, Render|Source, favorite)
├── TestPanel.svelte                 (test content + column count + Run All)
├── TestColumn.svelte                (one test lane: source dropdown, output, play)
├── modals/
│   ├── TemplatesModal.svelte
│   ├── HistoryModal.svelte
│   ├── ModelManagerModal.svelte
│   ├── FavoriteLibraryModal.svelte
│   ├── DataManagerModal.svelte
│   └── VariableManagerModal.svelte
└── shared/
    ├── api.ts                       (typed fetch wrappers + SSE helpers)
    ├── state.svelte.ts              ($state stores)
    ├── types.ts                     (Model, Template, History, Variable, …)
    └── render-prompt.ts             (variable interpolation — {{var}})
```

Each file targets < 300 lines. If `PromptOptimizerStudio.svelte` grows
past that, split the modal wiring into a `ModalHost.svelte`.

### 10.3 State model

Studio-level `$state`:

- `mode: 'basic' | 'context' | 'image'`
- `target: 'system' | 'user'`
- `originalPrompt: string`
- `workspacePrompt: string` (streamed into)
- `testInput: string`
- `columns: TestColumn[]` (each: `{id, source, running, output}`)
- `selectedModelId: string`, `selectedTemplateId: string`
- `modals: Record<ModalKey, boolean>`
- `theme: 'light'|'dark'` (synced to `localStorage`)

Server-backed resources (models, templates, history, favorites,
variables) are loaded on mount via the typed `api.ts` and kept in
separate `$state` stores that modals mutate.

### 10.4 Streaming in the browser

`api.ts` exposes e.g.:

```ts
export async function streamOptimize(
  req: OptimizeReq,
  onDelta: (s: string) => void,
  onDone: (u?: Usage) => void,
  signal?: AbortSignal,
): Promise<void>
```

Implementation uses `fetch` + `response.body!.getReader()` +
`TextDecoder`, splits on the SSE `event:`/`data:` grammar. One tiny
helper, no extra dependency. `AbortController` hooks into the "Stop"
button on the Workspace pane and on each test column.

### 10.5 Dark/light theme

The Studio inherits dark/light from the `?dark=1|0` query param (same as
`kb-metrics` / `kb-input-details`), then persists user toggles in
`localStorage('chenweb:prompt-optimizer:theme')`.

## 11. Nav-rail change

In `ChenWeb/web/src/lib/components/home3/nav-rail.svelte`, insert a new
`mainNav` item between `skills` and `applications`:

```ts
{
  id: 'prompts',
  label: 'Prompts',
  icon: WandSparklesIcon,
  group: 'Workspace',
  children: [
    { id: 'prompts-optimizer', label: 'Prompt Optimizer' }
    // future: { id: 'prompts-library',  label: 'Prompt Library' }
  ]
}
```

Extend `selectItem(item, child)` with:

```ts
if (child?.id === 'prompts-optimizer') {
  window.open(`/home3/prompt-optimizer?dark=${darkMode ? '1' : '0'}`,
              '_blank', 'noopener');
  return;
}
```

Lucide icon: `@lucide/svelte/icons/wand-sparkles`.

## 12. Default seed templates (clean-room English)

The Templates table is seeded on first read with the following built-ins
(authored fresh; no copy from upstream):

| kind | id | purpose |
|---|---|---|
| optimize       | builtin:general-optimize     | Rewrite a system prompt into a cleaner, more structured version. |
| user_optimize  | builtin:user-prompt-optimize | Rewrite a user-facing ask into a clearer, more specific prompt. |
| iterate        | builtin:iterate              | Given an existing optimized prompt + user feedback, produce a next revision. |
| test           | builtin:test-prompt          | Run a prompt (system + user test input) and return just the assistant output. |
| analyze        | builtin:analyze-prompt       | Explain a prompt's weaknesses and propose concrete improvements. |
| image_optimize | builtin:image-optimize       | Rewrite an image-generation prompt for clarity, composition, style. |

Each built-in is a Go string constant; tests lock the exact content so a
diff review is required to change it.

## 13. Security & privacy

- **API keys:** encrypted at rest (AES-GCM, env-derived key). Never
  returned to client after creation — only a masked preview.
- **Session auth:** all endpoints use ChenWeb's existing auth middleware
  (`shared/go/authmiddleware`). `userID` is always read from session
  context, never trusted from the request body.
- **No server-side logging of prompt bodies** by default. A per-user
  "diagnostic logging" flag (future slice) can opt in.
- **Row isolation:** every query filters by `user_id = session.user`.
  No cross-user access paths.
- **Import/export:** export sets `api_key_encrypted` to `null` and
  requires the user to re-enter keys on import. Prevents accidental key
  leakage through file sharing.
- **Rate limiting:** reuse ChenWeb's existing request rate limiter if
  present; otherwise a TODO tracked for Slice 2. LLM calls are the
  expensive surface — we add a per-user-per-minute cap there first.

## 14. Testing strategy

### 14.1 Go

- `shared/go/api/llm/` — table-driven adapter tests using
  `httptest.Server`. Cover: streaming delta parsing, error mapping,
  context cancellation, tool-call decoding.
- `server/api/promptoptimizerhandler/` — handler tests per endpoint
  with an ephemeral Postgres (using the same pattern as other handlers
  in the repo), covering auth scoping, validation, and happy path.
  LLM calls are replaced by a fake `llm.Client` implementation.

### 14.2 Svelte

- Component tests for `TopBar`, `OriginalPromptPanel`, `WorkspacePanel`,
  `TestColumn` with mocked `api.ts`.
- A minimal E2E (Playwright via existing `webapp-testing` skill) that
  walks: add model → add template → optimize → history shows entry.

### 14.3 Regression locks

- Snapshot the built-in templates (exact string match).
- Snapshot one optimize SSE response parsed into chunks.

## 15. Rollout & migration impact

- No existing ChenWeb data is modified. Only new tables are added. The
  goose migration is additive and idempotently reversible.
- Feature is behind a simple flag (`PROMPT_OPTIMIZER_ENABLED` env, or
  always-on — decided at implementation time). When disabled, the
  nav-rail item and the route are hidden, the API returns 404.
- No downtime required.

## 16. Open questions / deferred

These are called out so they don't silently become v1 scope:

- **Upload / attach images** for the Image tab: where do images live?
  S3? local disk? Deferred to Slice 3 design note.
- **Usage accounting / billing** per user per provider: out of scope;
  add a counter column later if needed.
- **Shared templates across users:** v1 treats all user rows as private.
  A future `is_shared BOOLEAN` + a reader role can add org-wide shares.
- **Streaming cancellation semantics** mid-iterate: we cancel via
  `AbortController`; server-side we rely on `ctx.Done()` in the adapter.
  Verified in tests.
- **MCP / desktop parity:** deferred; see §3.2.

## 17. References

- Upstream project: <https://github.com/linshenkx/prompt-optimizer>
- Upstream summary (local):
  `KnowledgeStore/AI/Prompt-Optimizer.md`
- ChenWeb `home3` host:
  `ChenWeb/web/src/routes/home3/+page.svelte`
- ChenWeb `home3` nav:
  `ChenWeb/web/src/lib/components/home3/nav-rail.svelte`
- Workspace conventions: `Workspace/CLAUDE.md`
- Goose migration conventions:
  `Workspace/shared/go/api/goose/goose.md`
- Logging conventions: `Workspace/shared/Documents/Logs.md`
