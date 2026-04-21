---
title: Prompt Optimizer — Implementation Plan (Slice 1: MVP)
project: ChenWeb
component: prompt-optimizer
created: 2026-04-20
author: Chen Ding (with AI assistance)
status: ready to execute
parent_design: ./design-prompt-optimizer.md
---

# Prompt Optimizer — Slice 1 (MVP) Implementation Plan

This plan covers **Slice 1 (MVP)** only, as defined in the parent design
doc §3.3. Slices 2 and 3 will be planned separately once Slice 1 is
merged and verified.

## Slice 1 definition of done

A signed-in ChenWeb user can:

1. Click **Prompts → Prompt Optimizer** in the `home3` nav-rail.
2. Land on `/home3/prompt-optimizer` (new tab, full viewport).
3. Add at least one Model (OpenAI or OpenAI-compatible) with an API key
   that is AES-GCM-encrypted at rest and never echoed in responses.
4. See at least one seeded **general-optimize** Template.
5. Paste a prompt, press **Optimize**, and watch tokens stream into the
   Workspace pane.
6. Paste a test input, press **Run** on a single column, and watch the
   model's answer stream back.
7. See every optimize / test run in **History**, scoped to their user.

Out of Slice 1: iterate modal, analyze, favorites, variables, multi-column
compare, import/export, Context tab, Image tab, Anthropic/Gemini
adapters.

---

## Execution order (chunks)

Four chunks, in strict order. Each chunk ends with a working `go build`,
`go test ./...`, and (for chunk 3+) a running frontend.

| Chunk | Scope | Commit boundary |
|---|---|---|
| A | Shared foundations: `shared/go/api/security/aesgcm.go` + `shared/go/api/llm/` | One PR in `shared/go` repo |
| B | ChenWeb backend: migration, handler package, routes | One PR in `ChenWeb` |
| C | ChenWeb frontend: route, Studio, modals (Models/Templates/History) | Same PR as B, or follow-up |
| D | Nav-rail wiring + end-to-end verification | Same PR as C |

---

## Chunk A — Shared foundations (`shared/go`)

### A.1 — AES-GCM utility

**File:** `shared/go/api/security/aesgcm.go` (new)

**API:**
```go
package security

func EncryptString(plaintext string, key []byte) (string, error)
func DecryptString(ciphertextB64 string, key []byte) (string, error)
func LoadKeyFromEnv(varName string) ([]byte, error) // returns 32-byte key
```

**Constraints:**
- Panics only on programmer error (nil key to low-level helpers); public
  funcs return errors for all runtime failures.
- Output format: `base64(nonce || ciphertext || tag)`, 12-byte nonce
  from `crypto/rand`.
- `LoadKeyFromEnv` accepts base64 input, validates decoded length == 32,
  returns a typed error otherwise.

**TDD:**

1. Write `shared/go/api/security/aesgcm_test.go` first with:
   - Round-trip: `Decrypt(Encrypt(x, k), k) == x` for empty, short,
     Unicode, and 1 MiB inputs.
   - Tampered ciphertext → decrypt returns error.
   - Wrong key → decrypt returns error.
   - `LoadKeyFromEnv` rejects missing, wrong-length, and non-base64.
2. Implement until green.
3. `go test ./api/security/...` from `shared/go`.

### A.2 — LLM module scaffolding

**Files (all new under `shared/go/api/llm/`):**
- `types.go` — `Role`, `Message`, `ContentPart`, `Request`, `Response`,
  `StreamChunk`, `Usage`, `ToolCall`, `ToolDef`, `ProviderID`,
  `ProviderConfig`.
- `client.go` — `Client` interface and `NewClient(cfg) (Client, error)`
  factory that dispatches on `cfg.ID`.
- `errors.go` — `ProviderError{Provider, Model, HTTPStatus, Body, Err}`.
- `redact.go` — `redactAPIKey(s string) string` (keeps last 4 chars).

**TDD:**

1. Write `shared/go/api/llm/client_test.go` with a table-driven test
   asserting `NewClient` returns `ErrUnsupportedProvider` for an unknown
   `ProviderID` and succeeds for each supported one (stub adapters OK).
2. Implement types and factory.

### A.3 — OpenAI adapter (Slice 1 target)

**Files:**
- `shared/go/api/llm/adapters/openai/client.go`
- `shared/go/api/llm/adapters/openai/stream.go` (SSE parser)
- `shared/go/api/llm/adapters/openai/client_test.go`

**Behavior:**
- `Complete` POSTs `{base}/v1/chat/completions` with `stream:false`.
- `Stream` POSTs the same with `stream:true`, reads `text/event-stream`,
  parses `data: {…}` frames, calls `on(StreamChunk{Delta: …})` per
  `choices[0].delta.content`, and terminates on `data: [DONE]`.
- Errors wrap to `ProviderError`; response `Raw` is the final non-stream
  body (nil for stream).
- Auth header: `Authorization: Bearer <key>`. Key redacted from any log
  line.

**TDD using `httptest.Server`:**

- Non-streaming happy path: server returns a fixture JSON, adapter
  returns matching `Response`.
- Stream happy path: server writes 3 SSE frames then `[DONE]`;
  callback receives deltas in order, then `Done: true`.
- 401 path: server returns `{"error":{"message":"bad key"}}`; adapter
  returns `ProviderError` with `HTTPStatus == 401`.
- Context cancel: canceled `ctx` aborts stream reader, `Stream` returns
  `ctx.Err()`.

### A.4 — OpenAI-compatible adapter

Same code path as `openai` but accepts a required `BaseURL`. Re-export
via `NewClient(ProviderOpenAICompatible)` — internally it instantiates
the openai client with the supplied base URL. No separate test suite;
one smoke test that the factory routes correctly.

### A.5 — Stubs for future adapters

For Slice 1, create placeholder files for `anthropic` and `gemini` that
return `ErrAdapterNotYetImplemented` from both `Complete` and `Stream`.
This keeps the factory exhaustive and Slice 2 trivially additive.

### A.6 — Commit A

Commit message:
```
feat(shared): add api/security AES-GCM helpers and api/llm module

- api/security: EncryptString/DecryptString/LoadKeyFromEnv with tests
- api/llm: Client interface, provider factory, OpenAI + OpenAI-compatible
  adapters with streaming, tests via httptest
- Anthropic/Gemini adapter stubs reserved for Slice 2

No workspace consumers wired yet; consumed by ChenWeb in next PR.
```

Run `go test ./...` from `shared/go` before commit. Then from workspace
root: `go work sync`.

---

## Chunk B — ChenWeb backend

### B.1 — Migration

**File:** `ChenWeb/project_migrations/20260420000003_create_prompt_optimizer_tables.sql`
(timestamp after the latest existing migration `20260401000002`)

Body: the exact DDL from the parent design doc §8. `+goose Up` creates
the five tables and indexes; `+goose Down` drops them in reverse order.

**Verification:**
- `cd ChenWeb && goose -dir project_migrations postgres "<DSN>" up`
  applies cleanly on a scratch DB.
- `goose down` rolls back cleanly.

### B.2 — Handler package scaffolding

**New directory:** `ChenWeb/server/api/promptoptimizerhandler/`

Files:
- `handler.go` — `Handler` struct with `DB *sql.DB`, `EncKey []byte`,
  `LLMFactory func(llm.ProviderConfig) (llm.Client, error)`.
- `models.go` — DB struct types (`ModelRow`, `TemplateRow`, `HistoryRow`)
  and JSON request/response types (with masked-key output).
- `models_handler.go` — CRUD handlers for `/models`.
- `templates_handler.go` — CRUD handlers for `/templates` (with
  first-read seeding of built-in templates if `user_id IS NULL` rows
  missing).
- `history_handler.go` — list/get/delete for `/history`.
- `optimize_handler.go` — SSE handler for `POST /optimize`.
- `test_handler.go` — SSE handler for `POST /test`.
- `seed_templates.go` — `var SeedTemplates = []SeedTemplate{…}` with
  clean-room English content for one `optimize` and one `test` template
  minimum. No copying from upstream.
- `handler_test.go` + per-file `_test.go` where applicable.

**Every handler follows the established ChenWeb pattern** (see
`kbhandler/handler.go`): `logger := EchoFactory.NewFromEcho(c, "CWB_PO_XXX")`,
JSON response envelopes with `status` + `error_msg`, user id pulled
from session via `authmiddleware`.

### B.3 — Error codes

Add to `ChenWeb/server/api/EchoFactory` registry (or wherever module
codes live — grep for `CWB_KB_` to locate):
```
CWB_PO_MODELS, CWB_PO_TEMPLATES, CWB_PO_HISTORY,
CWB_PO_OPTIMIZE, CWB_PO_TEST
```

### B.4 — Route wiring

**File:** `ChenWeb/server/api/routes.go`

Add, grouped together:
```go
po := apiGroup.Group("/prompt-optimizer")
po.GET("/models",    poHandler.ListModels)
po.POST("/models",   poHandler.CreateModel)
po.PUT("/models/:id", poHandler.UpdateModel)
po.DELETE("/models/:id", poHandler.DeleteModel)

po.GET("/templates",  poHandler.ListTemplates)
po.POST("/templates", poHandler.CreateTemplate)
po.PUT("/templates/:id", poHandler.UpdateTemplate)
po.DELETE("/templates/:id", poHandler.DeleteTemplate)

po.GET("/history",    poHandler.ListHistory)
po.GET("/history/:id", poHandler.GetHistory)
po.DELETE("/history/:id", poHandler.DeleteHistory)

po.POST("/optimize", poHandler.Optimize) // SSE
po.POST("/test",     poHandler.Test)     // SSE
```

Construction in `main.go` (or wherever `aiassistanthandler` is wired):
```go
encKey, err := security.LoadKeyFromEnv("PROMPT_OPTIMIZER_ENCRYPTION_KEY")
if err != nil {
    log.Fatalf("prompt optimizer cannot start: %v", err)
}
poHandler := promptoptimizerhandler.New(db, encKey, llm.NewClient)
```

### B.5 — SSE streaming shape

All `/optimize` and `/test` handlers:
1. Validate request, look up model (decrypt key), look up template.
2. Set headers `Content-Type: text/event-stream`,
   `Cache-Control: no-cache`, `X-Accel-Buffering: no`.
3. Call `llm.Client.Stream(ctx, req, on)`; `on` writes
   `event: delta\ndata: {"text": "..."}\n\n` and flushes.
4. On completion write `event: done\ndata: {…}\n\n`.
5. On completion, insert a row into `prompt_optimizer_history` with the
   collected output.
6. On error mid-stream: write `event: error\ndata: {"message":"..."}\n\n`
   and return (status already sent as 200).

### B.6 — TDD for handlers

Tests in `ChenWeb/server/api/promptoptimizerhandler/*_test.go` using
Echo's `httptest` helpers + an in-process mock LLM client injected via
`Handler.LLMFactory`. Cover:
- `POST /models` encrypts key, response returns masked preview only.
- `GET /models` never returns plaintext key.
- `DELETE /models` requires ownership (other-user id → 404).
- `POST /optimize` streams expected SSE frames and persists a history row.
- `POST /test` with bad `modelId` returns JSON error before opening the
  stream.

Use a test Postgres via the existing ChenWeb test harness (grep
`kbhandler/*_test.go` for the pattern) or `sqlmock` if no harness exists
for this package yet.

### B.7 — Commit B

```
feat(chenweb): prompt optimizer backend (models, templates, history,
  optimize/test SSE)

- goose migration 20260420000003 creates prompt_optimizer_* tables
- new package server/api/promptoptimizerhandler with CRUD + SSE handlers
- API keys encrypted at rest via shared/go security; never returned to
  client in plaintext
- routes mounted under /api/v1/prompt-optimizer
- requires new env: PROMPT_OPTIMIZER_ENCRYPTION_KEY (32-byte b64)
```

---

## Chunk C — ChenWeb frontend

### C.1 — Route

**New file:** `ChenWeb/web/src/routes/home3/prompt-optimizer/+page.svelte`

Minimal shell that:
- Reads `?dark=1` query param and toggles a `dark` class on `<html>`.
- Renders `<PromptOptimizerStudio />`.

### C.2 — Component tree (Slice 1 subset)

Under `ChenWeb/web/src/lib/components/prompt-optimizer/`:

```
PromptOptimizerStudio.svelte
TopBar.svelte
OriginalPromptPanel.svelte
WorkspacePanel.svelte
TestPanel.svelte               (single column in Slice 1)
modals/
  ModelManagerModal.svelte
  TemplatesModal.svelte
  HistoryModal.svelte
shared/
  api.ts
  state.svelte.ts
  types.ts
```

Slice 1 behavior:
- TopBar shows only the **Basic** tab (Context / Image are disabled
  stubs with "Coming soon" tooltip).
- Target switcher shows System / User (both work the same in Slice 1 —
  they just change which seeded template is the default).
- OriginalPromptPanel has a Model dropdown (from `/models`), Template
  dropdown (from `/templates`), **Optimize** button. No Analyze in Slice 1.
- WorkspacePanel renders streamed text; a **Favorite** icon is present
  but disabled in Slice 1.
- TestPanel has one column, a content textarea, and a Run button.
- Three modals only (Models, Templates, History). Favorites / Data /
  Variables modals are stubs that render "Coming in Slice 2".

### C.3 — API wrapper (`shared/api.ts`)

Typed thin wrapper around `fetch`, all calls go to
`/api/v1/prompt-optimizer/*`, credentials included.

Streaming helpers:
```ts
export async function streamOptimize(
  req: { modelId: string; templateId: string; prompt: string },
  onDelta: (s: string) => void,
  onDone: (meta?: { usage?: Usage }) => void,
  signal?: AbortSignal,
): Promise<void>

export async function streamTest(
  req: { modelId: string; systemPrompt: string; userPrompt: string },
  onDelta, onDone, signal?
): Promise<void>
```

Uses `fetch` + `response.body.getReader()` + `TextDecoder`, splits SSE
frames. One small helper `parseSSEStream(reader, handlers)` keeps the
parser out of the two call sites.

### C.4 — State (`shared/state.svelte.ts`)

Svelte 5 `$state` stores:
```ts
export const ui = $state({
  mode: 'basic',
  target: 'system',
  selectedModelId: '',
  selectedTemplateId: '',
  theme: 'dark',
});

export const data = $state({
  models: [] as Model[],
  templates: [] as Template[],
  history: [] as HistoryItem[],
});

export const workspace = $state({
  originalPrompt: '',
  optimizedPrompt: '',
  testInput: '',
  testOutput: '',
  optimizing: false,
  testing: false,
});
```

On mount, Studio fetches `/models`, `/templates`, `/history?limit=50` in
parallel.

### C.5 — Styling

Reuse `home3` design tokens. No new global CSS — use Tailwind utility
classes consistent with `home3/+page.svelte`. Dark mode works via the
`dark:` prefix already set up in ChenWeb.

### C.6 — TDD / verification for frontend

Svelte component tests are not the ChenWeb norm. Instead:
- Build passes: `cd ChenWeb/web && pnpm run build` (or the mise task
  used in this repo — check).
- Manual flow is verified in Chunk D.

### C.7 — Commit C

```
feat(chenweb-web): Prompt Optimizer Studio (Slice 1 MVP)

- new route /home3/prompt-optimizer with full-viewport studio
- Model Manager, Templates, History modals
- streaming Optimize + Test against /api/v1/prompt-optimizer SSE
- dark/light theme synced from ?dark query param and localStorage
- Context/Image tabs stubbed; Slice 2 features marked "Coming soon"
```

---

## Chunk D — Nav-rail + end-to-end verification

### D.1 — Nav-rail change

**File:** `ChenWeb/web/src/lib/components/home3/nav-rail.svelte`

1. Import a new icon (suggest `WandSparklesIcon` from lucide if already
   in use; otherwise pick any existing in-repo icon to avoid adding a
   dep).
2. Insert a new top-level item in `mainNav` under the Workspace group:
```ts
{
  id: 'prompts',
  label: 'Prompts',
  icon: WandSparklesIcon,
  group: 'Workspace',
  children: [
    { id: 'prompts-optimizer', label: 'Prompt Optimizer' },
  ],
},
```
3. In `selectItem`, before the existing `kb-metrics` branch:
```ts
if (child?.id === 'prompts-optimizer') {
  window.open(
    `/home3/prompt-optimizer?dark=${darkMode ? '1' : '0'}`,
    '_blank',
    'noopener',
  );
  return;
}
```

### D.2 — End-to-end manual verification

With `mise dev` running and a real (dev-tier) OpenAI key:

1. Sign in to ChenWeb, land on `home3`.
2. Click **Prompts → Prompt Optimizer**. Verify new tab opens at
   `/home3/prompt-optimizer` with dark mode preserved.
3. Open **Model Manager** → Add a model (OpenAI, `gpt-4o-mini`, paste
   key). Verify after save: response shows `api_key_preview: "sk-…XXXX"`
   and `api_key_encrypted` is not returned.
4. Open DB, confirm `prompt_optimizer_models.api_key_encrypted` is
   base64 ciphertext, not the plaintext key.
5. Open **Templates** → confirm seeded `general-optimize` is visible.
6. Paste a prompt ("explain transformers to a ten year old"), press
   **Optimize**. Watch tokens stream into Workspace.
7. Paste test input ("what is attention?"), press **Run**. Watch tokens
   stream into the test column.
8. Open **History**, confirm both runs are listed with timestamps and
   correct kinds (`optimize`, `test`).
9. Hard refresh the page, confirm: Models + Templates + History all
   persist and rehydrate on load.
10. In a private window signed in as a different user, confirm that
    user sees none of the first user's Models / History.

### D.3 — Commit D

```
feat(chenweb-web): add Prompts → Prompt Optimizer to home3 nav-rail

- new top-level Workspace item with Prompt Optimizer child
- opens /home3/prompt-optimizer in a new tab, matching kb-metrics pattern
```

---

## Environment & ops

- New required env var: `PROMPT_OPTIMIZER_ENCRYPTION_KEY` — 32 random
  bytes, base64-encoded. Add an example line to `ChenWeb/.env.example`
  (or the equivalent) showing how to generate it:
  `openssl rand -base64 32`.
- Server startup must fail loudly if the var is missing or malformed.
- No new provider keys required in env — users supply their own via the
  Model Manager UI.

---

## Risks & open items for Slice 1

| Risk | Mitigation |
|---|---|
| Echo's default middleware may buffer SSE | Explicit `c.Response().Flush()` after each frame; also set `X-Accel-Buffering: no`. |
| Long-running SSE plus request timeout middleware | Verify current ChenWeb middleware stack does not impose a short deadline on `/api/v1/prompt-optimizer/optimize`. If it does, add a per-route exclusion. |
| Existing `users` table column name | The migration references `users(id)`. If the ChenWeb users table uses a different PK name, adjust FK references in the migration before applying. Verify in chunk B.1 before writing DDL. |
| Seed template refresh | First-read seeding reads `kind='optimize' AND user_id IS NULL`; if future versions update text, add a `version` column or a deliberate `UPDATE` path. Not a Slice 1 problem, but noted. |

---

## Ready-to-execute checklist

- [ ] Chunk A (shared/go): AES-GCM + LLM module, tests green
- [ ] Chunk B (ChenWeb server): migration applies, handlers + routes,
      tests green, server boots with new env var
- [ ] Chunk C (ChenWeb web): `/home3/prompt-optimizer` route renders and
      streams against live backend
- [ ] Chunk D: nav-rail entry works, full E2E verified in browser

Plan complete and saved to
`KnowledgeStore/DevDocuments/DesignDocs/plan-prompt-optimizer.md`. Ready
to execute?
