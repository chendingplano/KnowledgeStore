# ADR 2026070501 LLM Call Logging

**Date:** 2026-07-05 \
**Status:** Accepted \
**Component:** shared/go/api/llm \
**Authors**: Chen Ding\

## Change Logs
* 2026/07/05, ADR Created
* 2026/07/05, Admin UI added — "Add a Model" button, Model Profiles page, LLM Models page
* 2026/07/05, LLM Usage Logs admin page added — paginated `llm_usage_event` viewer with body archive decompression
* 2026/07/06, `call_loc` and `call_reason` made mandatory (warning, not a hard error); `metadata_json` gained a generic caller-supplied passthrough; provisions reviewer updated as the reference implementation

## Context

ChenWeb makes LLM calls throughout its document processing pipeline — metric extraction, entity reconciliation, prompt optimization, and doc review. Without a systematic logging facility it is impossible to:

- track actual token usage and cost per document, account, or prompt
- diagnose latency outliers or provider errors after the fact
- validate that prompt cache hits are occurring as expected

A facility is needed that captures every LLM call — request payload, response payload, token counts, latency, and error state — automatically, without requiring each call site to add its own logging.

The facility must be optional and project-neutral so that `tax` and future projects can adopt it without coupling to ChenWeb's database schema.

## Decision

Implement a sink-based capture interface in `shared/go/api/llm`. Every call made through the shared client automatically calls the sink at every exit point — including transport errors, HTTP errors, stream cancellation, handler errors, and success. No call site changes are required.

ChenWeb registers its own sink at startup that writes to PostgreSQL and archives compressed request/response bodies to disk.

### Coverage after this ADR

| Provider / Path | Captured |
|---|---|
| OpenAI (`ProviderOpenAI`) | ✅ |
| OpenAI-compatible — DeepSeek, Qwen, Ollama, Groq, etc. (`ProviderOpenAICompatible`) | ✅ |
| Anthropic Claude (`ProviderAnthropic`) | ✅ Added 2026-07-05 |
| `OpenAIJSONClient` (legacy higher-level client, used by doc processors) | ✅ |
| Gemini (`ProviderGemini`) | ❌ Adapter not yet implemented |
| `agentrun` Docker runners (Claude Code CLI, Codex CLI) | ❌ External process; captured separately via `proxytracehandler` OTEL spans |

### Architecture

```text
Call site
  ↓
llm.Client.Complete() / Stream()        (shared/go/api/llm/)
  ↓ at every exit point
captureUsageRecord()
  ↓
DefaultUsageCaptureSink  ←  set at startup by the project
  ↓                     (or per-request via Request.Capture.Sink)
llmusage.Sink                           (ChenWeb/server/api/llmusage/)
  ├── INSERT INTO llm_usage_event       (PostgreSQL)
  └── WriteGzipFile(input/output body) (filesystem archive)
```

**`UsageCaptureSink` interface** (`shared/go/api/llm/usage_capture.go`):
```go
type UsageCaptureSink interface {
    Capture(ctx context.Context, record UsageCaptureRecord) error
}
var DefaultUsageCaptureSink UsageCaptureSink
```

The sink receives a `UsageCaptureRecord` containing: account/profile IDs, provider, model, prompt name, start/finish timestamps, input/output token counts, prompt cache hit/miss tokens, latency, error message, provider request ID, compressed body references, record ID, call reason, and call location.

**Anthropic adapter** (`shared/go/api/llm/anthropic.go`), added this ADR:
- Speaks the Anthropic Messages API (`POST /v1/messages`)
- Translates `system` role messages to Anthropic's top-level `system` field
- Translates tool calls and tool results to `tool_use` / `tool_result` content blocks
- Accumulates streaming `input_json_delta` fragments per block index before emitting a single `StreamChunk{ToolCall: ...}`
- Maps Anthropic usage fields: `cache_read_input_tokens` → `PromptCacheHitTokens`, `cache_creation_input_tokens` → `PromptCacheMissTokens`
- Default endpoint: `https://api.anthropic.com`; default API version: `2023-06-01`; both are overridable via `ProviderConfig`

**ChenWeb sink** (`ChenWeb/server/api/llmusage/`):
- `InstallDefaultSink()` is called at startup in both `deepdoc` and `doc-processor` binaries
- If `account_id` or `profile_id` is missing from the record, the sink resolves them by matching provider + base URL + API key ref + profile name against `llm_account` / `llm_account_model_profile`
- If the database handle or account/profile are unavailable, the sink silently skips the DB write (gzip archives are still written when bodies are present)

### Alternative Decisions

**Per-call-site logging:** Each function that calls an LLM writes its own log entry. Rejected — brittle, easy to miss, duplicates code, and produces inconsistent record shapes.

**HTTP middleware / MITM proxy:** Intercept all outgoing LLM traffic at the transport layer. Used by `proxytracehandler` for `agentrun` external processes where in-process capture is not possible. Not appropriate for in-process calls because it requires either a test-double HTTP server or routing all traffic through a local proxy, which complicates deployment.

**OpenTelemetry spans only:** Emit LLM calls as OTEL spans to HyperDX/ClickStack. Complementary, not a replacement — OTEL spans are good for latency profiling and correlation; the sink approach writes structured rows that support SQL cost queries and body archiving. Both can coexist (Phase 2 of observability design adds OTEL spans around LLM calls).

### Database Migrations

No new migrations in this ADR. The `llm_usage_event` table and its supporting tables were created by earlier migrations:

| Migration | Change |
|---|---|
| `20260619000001_create_llm_activity_tables.sql` | Creates `llm_account`, `llm_account_model_profile`, `llm_usage_event`, `llm_daily_account_report`, `llm_balance_snapshot` |
| `20260620000003_add_llm_usage_event_call_metadata.sql` | Adds `record_id`, `call_reason`, `call_loc` columns to `llm_usage_event` |
| `20260625000002_add_llm_usage_prompt_cache_tokens.sql` | Adds `prompt_cache_hit_tokens`, `prompt_cache_miss_tokens` columns to `llm_usage_event` |

The Anthropic adapter's prompt cache fields map directly onto the existing `prompt_cache_hit_tokens` / `prompt_cache_miss_tokens` columns.

### Data Formats

**`llm_usage_event` key columns:**

| Column | Source |
|---|---|
| `provider` | `ProviderConfig.ID` — `"openai"`, `"anthropic"`, `"openai_compatible"`, etc. |
| `model_name` | `Request.Model` |
| `prompt_name` | `Request.PromptName`; falls back to `"missing_prompt_name@<call_loc>"` |
| `input_tokens` | Provider usage response |
| `output_tokens` | Provider usage response |
| `prompt_cache_hit_tokens` | OpenAI: `prompt_cache_hit_tokens`; Anthropic: `cache_read_input_tokens` |
| `prompt_cache_miss_tokens` | OpenAI: `prompt_cache_miss_tokens`; Anthropic: `cache_creation_input_tokens` |
| `latency_ms` | `request_finished_at − request_started_at` |
| `input_body_ref` / `output_body_ref` | Relative path to gzip archive under `LLM_ARCHIVE_ROOT` |
| `record_id` | Optional document record ID passed via `Request.RecordID` |
| `call_loc` | Static `"MID-YYYYMMDD-SSSS"` string in the calling source file (mandatory since 2026-07-06; a `WARN` is logged if empty) |

**Request/response body archive:** Written as gzip files under `<LLM_ARCHIVE_ROOT>/<YYYY>/<MM>/<DD>/<account_id>/<event_id>-{input,output}.json.gz`. The archive root is set by `LLM_ARCHIVE_ROOT` (ChenWeb config).

### Mandatory `call_loc` / `call_reason` and generic `metadata_json` (2026-07-06)

`call_loc` and `call_reason` were previously optional (a missing value just fell back to `"missing_prompt_name@..."` in `prompt_name`). They are now **mandatory**: `captureUsageRecord` (`shared/go/api/llm/usage_capture.go`) logs a `WARN` — not a hard error, so calls are never blocked — whenever either is empty after fallback resolution from `Request`.

**`call_loc` format going forward:** `MID-YYYYMMDD-SSSS` — a static identifier hand-picked once when the call site is written (4-digit year, 2-digit month/day, 4-digit daily sequence), analogous to the existing `LOC_MMDDHHMMSS` convention used for `loggerutil` locations but scoped to LLM call sites. Existing call sites using the older `MID-CWB-REVIEW-<ASPECT>` / `MID_YYMMDDSS` styles are not being retroactively renamed; new call sites should use the new format.

**Generic metadata passthrough:** `Request.Metadata`, `JSONExtractionInput.Metadata`, `UsageCaptureInput.Metadata`, and `UsageCaptureRecord.Metadata` (all `map[string]any`) let a call site attach arbitrary call-specific data (e.g. `run_id`, `provision_id`). `captureUsageRecord` falls back to `Request.Metadata` when the input's `Metadata` is nil, the same pattern already used for `CallReason`/`CallLoc`/`RecordID`. The ChenWeb sink (`ChenWeb/server/api/llmusage/sink.go`) merges `record.Metadata` into the `metadata_json` map alongside the existing `capture_source` / `prompt_name_missing` keys.

**Reference implementation — provisions reviewer** (`ChenWeb/server/api/doc-reviews/review-provisions.go`): each per-provision LLM call now sets `call_reason = "review-provision"`, `call_loc = "MID-20260706-0001"`, and `metadata_json` carrying `provision_id` (always) and `run_id` (when available). The review run ID reaches the call site via a new context helper — `docprocessing.WithLLMRunID`/`LLMRunIDFromContext`, aliased in `docreviews` as `withLLMRunID`/`llmRunIDFromContext` — set once in `ReviewProcessor.PostProcessIndex` (mirrors the existing `WithLLMRecordID` pattern) rather than threaded through `ReviewerConfig` at every one of the ~40 reviewer call sites.

**Rollout scope:** only the provisions reviewer was migrated to the new call_loc/call_reason/metadata convention in this change. The other ~40 reviewers in `review-document.go` still use their original `newDocReviewLLMJSONInput` call_loc strings (e.g. `MID-CWB-REVIEW-METRICS`); migrating them to the new format and attaching per-reviewer metadata (e.g. `metric_id`, `entity_id`) is follow-up work, not yet scheduled.

### Environment Variables

No new environment variables introduced by this ADR. Relevant existing variables:

| Variable | Purpose |
|---|---|
| `LLM_WORKSPACE_TIMEZONE` | Timezone used to compute `workspace_day` for daily partitioning |
| `ANTHROPIC_API_KEY` | API key for direct Anthropic calls (passed via `ProviderConfig.APIKey`) |

## Operations Runbook

### Data model and relationship to `.models.toml`

```
.models.toml                    llm_account                 llm_account_model_profile
────────────────────            ──────────────────────────  ─────────────────────────────
[deepseek-v4-flash]             provider   = "deepseek"     profile_name = "deepseek-v4-flash"
base_url = "https://..."    ──► base_url   = "https://..."  model_name   = "deepseek-v4-flash"
api_key  = "sk-..."         ──► api_key_ref = "sk-..."  ◄── account_id  (FK)
model_name = "deepseek-v4-flash"                        ──► model_name (informational)

[deepseek-v4-pro]                                           profile_name = "deepseek-v4-pro"
base_url = "https://..."    ──► (same llm_account row)      model_name   = "deepseek-v4-pro"
api_key  = "sk-..."                                     ◄── account_id  (FK)
model_name = "deepseek-v4-pro"
```

**`llm_account`** — one row per billing credential. Identifies who pays for the calls.
- `provider`: normalized provider name (`"deepseek"`, `"openai"`, `"anthropic"`, …)
- `base_url`: the API endpoint root
- `api_key_ref`: the raw API key value — used as a lookup key, never displayed

**`llm_account_model_profile`** — one row per named model configuration. Multiple profiles can share one account as long as they use the same `base_url` and `api_key`.
- `profile_name`: must equal the TOML section key (e.g. `[deepseek-v4-flash]` → `"deepseek-v4-flash"`)
- `model_name`: the model identifier sent in API requests (e.g. `"deepseek-v4-flash"`)

**`.models.toml`** — the runtime configuration the app reads. Each `[section]` maps to exactly one `llm_account_model_profile` row via `profile_name`. The `api_key` and `base_url` fields identify which `llm_account` row that profile belongs to.

**The lookup performed at call time:**

```sql
SELECT a.id, p.id
FROM llm_account a
JOIN llm_account_model_profile p ON p.account_id = a.id
WHERE LOWER(a.provider)  = LOWER(<provider>)
  AND LOWER(TRIM(TRAILING '/' FROM a.base_url)) = LOWER(TRIM(TRAILING '/' FROM <base_url>))
  AND a.api_key_ref       = <api_key>          -- case-sensitive exact match
  AND LOWER(p.profile_name) = LOWER(<profile_name>)
```

If the lookup fails, the event is still written to `llm_usage_event` with `account_id = NULL` and `profile_id = NULL`, and a `WARN` is emitted. Cost-rollup queries should filter `WHERE account_id IS NOT NULL`.

**Key invariant:** `llm_account` is keyed on `(provider, base_url, api_key_ref)`. There must be exactly **one** `llm_account` row per unique credential. Adding a second row for the same credential with a different `account_name` is wrong — it creates an orphaned row that will never match because the profiles live under the original row.

### Changing an API key

1. Update `.models.toml` with the new API key value.
2. Update the matching `llm_account` row — find it by `provider` + `base_url`, not by `account_name`:
   ```sql
   UPDATE llm_account
   SET api_key_ref = '<new_api_key>'
   WHERE provider = '<provider>'
     AND LOWER(TRIM(TRAILING '/' FROM base_url)) = LOWER('<base_url>');
   ```
3. Restart the `deepdoc` and `doc-processor` binaries so they pick up the new key from the TOML.
4. Verify: run a test LLM call and confirm a new row appears in `llm_usage_event` with a non-NULL `account_id`.

> **Common mistake:** inserting a new `llm_account` row with the new key instead of updating the existing one. The new row will have no `llm_account_model_profile` children and will never match. Always update the existing row — the profiles stay in place.

### Adding a new model

> **Preferred path — use the Admin UI.** The "LLM Accounts" page (System Admin → LLM → LLM Accounts) has an **"+ Add a Model"** button that performs steps 1–3 atomically through a single form. It writes `.models.toml`, upserts `llm_account`, and upserts `llm_account_model_profile` in one request. See [Admin UI (2026-07-05)](#admin-ui-2026-07-05) for navigation and endpoint details.

**Manual steps (use when the UI is unavailable or when batch-adding multiple models):**

1. Add the model entry to `.models.toml`. The section key becomes the `profile_name` — do not add a `profile_name` field inside the section:
   ```toml
   [my-new-model]
   model_name   = "deepseek-chat"
   api_key      = "<api_key>"
   base_url     = "https://api.deepseek.com"
   timeout_sec  = 120
   max_inflight = 16
   max_requests_per_minute = 500
   max_tokens_per_minute   = 200000
   token_reserve_per_call  = 256
   ```
2. Create or reuse an `llm_account` row for the provider (same `provider` + `base_url` + `api_key_ref`):
   ```sql
   -- Only needed if this is a new provider/key combination:
   INSERT INTO llm_account (account_name, provider, base_url, api_key_ref)
   VALUES ('DeepSeek', 'deepseek', 'https://api.deepseek.com', '<api_key>');
   ```
3. Add a matching `llm_account_model_profile` row. `profile_name` must equal the TOML section key (e.g. `"my-new-model"`):
   ```sql
   INSERT INTO llm_account_model_profile (account_id, profile_name, model_name)
   VALUES (
       (SELECT id FROM llm_account WHERE account_name = 'DeepSeek'),
       'my-new-model',
       'deepseek-chat'
   );
   ```
4. Verify logging after the first call:
   ```sql
   SELECT prompt_name, model_name, input_tokens, output_tokens, created_at
   FROM llm_usage_event
   WHERE created_at > NOW() - INTERVAL '10 minutes'
   ORDER BY created_at DESC
   LIMIT 10;
   ```

### Diagnosing unlinked events (`account_id IS NULL`)

Events are always written since 2026-07-05. If `account_id` is NULL and the WARN fires:

1. Check which `llm_account` row has the right `(provider, base_url)` pair:
   ```sql
   SELECT account_name, provider, base_url, LEFT(api_key_ref, 12) AS key_prefix
   FROM llm_account
   WHERE provider = '<provider>';
   ```
2. Compare `key_prefix` with the first 12 characters of `api_key` in `.models.toml`. If they differ, the key was rotated without updating the DB — see "Changing an API key".
3. Confirm the profile row exists **under the same account** that has the matching key:
   ```sql
   SELECT a.account_name, a.provider, LEFT(a.api_key_ref, 12) AS key_prefix,
          p.profile_name, p.model_name
   FROM llm_account_model_profile p
   JOIN llm_account a ON a.id = p.account_id
   WHERE a.provider = '<provider>';
   ```
   If the profile exists but is under a different `account_name` than the one with the matching key, you have a split-account situation (see below).
4. Check for trailing slashes or whitespace in `base_url`:
   ```sql
   SELECT account_name, base_url FROM llm_account WHERE provider = '<provider>';
   ```

**Split-account situation** (e.g., key was rotated by inserting a new `llm_account` row instead of updating):
```sql
-- Move the profiles from the old account to the one with the current key,
-- then delete the orphaned row.
UPDATE llm_account_model_profile
SET account_id = (SELECT id FROM llm_account WHERE account_name = '<account_with_current_key>')
WHERE account_id = (SELECT id FROM llm_account WHERE account_name = '<old_account_name>');

DELETE FROM llm_account WHERE account_name = '<old_account_name>';
```

## Implementation

### Code Changes — Anthropic adapter (original)

**`shared/go/api/llm/anthropic.go`** — New file. Implements `Client` interface for `ProviderAnthropic`:
- `anthropicClient.Complete()` — non-streaming; calls `captureUsageRecord` at all 4 exit points
- `anthropicClient.Stream()` — SSE streaming; calls `captureUsageRecord` at 6 exit points (transport error, HTTP error, context cancel, stream read error, handler error, success)
- `newAnthropicClient(cfg ProviderConfig)` — constructor

**`shared/go/api/llm/client.go`** — Updated `ProviderAnthropic` case in `NewClient` from `notImplementedClient` stub to `newAnthropicClient`.

No changes to call sites, ChenWeb sink, or database schema.

### Admin UI (2026-07-05)

Added a System Admin UI for managing LLM accounts, model profiles, and `.models.toml` entries. Entry point: **System Admin → LLM** in the navigation rail at `home3` (`ChenWeb/web/src/routes/home3`).

#### Navigation

| Label | `childId` | Component |
|---|---|---|
| LLM Accounts | `sysadmin-llm-accounts` | `llm-accounts-view.svelte` (existing, updated) |
| Model Profiles | `sysadmin-llm-model-profiles` | `llm-model-profiles-view.svelte` |
| LLM Models | `sysadmin-llm-models` | `llm-models-view.svelte` |

Navigation is defined in `ChenWeb/web/src/lib/components/home3/nav-rail.svelte` under the `sysadmin-llm` sub-group. Routing is in `ChenWeb/web/src/lib/components/home3/content-panel.svelte`.

#### API Endpoints (all under `/api/v1`, all auth-guarded)

| Method | Path | Handler | Purpose |
|---|---|---|---|
| `GET` | `/llm/profiles` | `ListProfiles` | List all `llm_account_model_profile` rows joined with `llm_account.account_name` |
| `POST` | `/llm/profiles` | `CreateProfile` | Insert one profile row (DB only, does not touch `.models.toml`) |
| `PUT` | `/llm/profiles/:id` | `UpdateProfile` | Update one profile row |
| `POST` | `/llm/models` | `AddModel` | **Combined: write `.models.toml` + upsert account + upsert profile** |
| `GET` | `/llm/models-toml` | `GetModelsTOML` | Parse and return all entries from `.models.toml` as JSON |
| `PUT` | `/llm/models-toml/:key` | `UpsertModelTOML` | Add or update a single TOML entry (does not touch the DB) |
| `DELETE` | `/llm/models-toml/:key` | `DeleteModelTOML` | Remove a single TOML entry (does not touch the DB) |

The existing account endpoints (`/llm/accounts`, `/llm/accounts/:id`, `/llm/accounts/import-models-toml`) are unchanged.

#### Backend files

All in `ChenWeb/server/api/llmadminhandler/`:

| File | Contents |
|---|---|
| `profile_store.go` | `ModelProfile` type; `CreateProfileInput` type; `Store.ListProfiles`, `Store.CreateProfile`, `Store.UpdateProfile`, `Store.UpsertAccountAndProfile` |
| `profile_handler.go` | `ListProfiles`, `CreateProfile`, `UpdateProfile` HTTP handlers |
| `model_handler.go` | `AddModel` HTTP handler — implements the "Adding a new model" runbook steps 1–3 |
| `toml_handler.go` | `GetModelsTOML`, `UpsertModelTOML`, `DeleteModelTOML` handlers; `UpsertModelsTOMLEntry` and `readModelsTOML`/`writeModelsTOML` helpers (also called by `AddModel`) |
| `handler.go` | Updated: `accountAdminStore` interface extended with `ListProfiles`, `CreateProfile`, `UpdateProfile`, `UpsertAccountAndProfile` |

Routes are registered in `ChenWeb/server/api/routes.go`.

#### Frontend files

All in `ChenWeb/web/src/lib/components/home3/`:

| File | Purpose |
|---|---|
| `llm-model-profiles-client.ts` | Typed fetch wrappers for `/llm/profiles` |
| `llm-model-profiles-view.svelte` | Model Profiles page — table of all profiles with inline edit; account dropdown populated from `listLLMAccounts()` |
| `llm-models-client.ts` | Typed fetch wrappers for `/llm/models-toml` and `/llm/models` |
| `llm-models-view.svelte` | LLM Models page — table of all TOML entries with inline edit and delete (confirm step) |
| `llm-accounts-view.svelte` | Updated: "Add a Model" button (calls `addModel()` from `llm-models-client.ts`) and inline form |

#### AddModel flow (step-by-step)

`POST /api/v1/llm/models` → `model_handler.go:AddModel`:

1. **Write `.models.toml`** — calls `UpsertModelsTOMLEntry(path, profileName, LLMModelDef{...})`. Reads the current file, sets `models[profileName] = entry`, marshals and overwrites. If the file does not exist it is created.
2. **Upsert DB (single transaction)** — calls `store.UpsertAccountAndProfile`:
   - Upserts `llm_account` keyed on `LOWER(account_name)`. If `account_name` is blank in the request, defaults to `"<provider>:<base_url>"`.
   - Upserts `llm_account_model_profile` keyed on `(account_id, LOWER(profile_name))`.
3. Returns the resulting `ModelProfile` JSON.

**Key invariant preserved:** the upsert conflict key is `LOWER(account_name)`, matching the import-from-TOML flow, so AddModel never creates duplicate `llm_account` rows for an existing account name.

#### `.models.toml` write behaviour

`UpsertModelsTOMLEntry`, `UpsertModelTOML`, and `DeleteModelTOML` all use a read-modify-write pattern via `go-toml/v2`. After the first write through the UI:

- **Comments are lost** — `go-toml/v2` does not preserve comments on marshal.
- **Key order changes** — keys are emitted in go map iteration order (non-deterministic), not in the original file order.

The file remains semantically valid TOML. If comment preservation matters, use manual editing. The Admin UI is intended for operational convenience, not for maintaining a human-readable config file.

**Restart required:** changes to `.models.toml` are not applied until the `deepdoc` and `doc-processor` binaries are restarted (same as manual edits). The DB rows created by AddModel are active immediately for logging linkage.

### LLM Usage Logs Admin UI (2026-07-05)

Added a paginated log viewer for `public.llm_usage_event` under **System Admin → Logs → LLM Usage Logs** in the `home3` navigation rail.

#### Navigation

| Label | `childId` | Component |
|---|---|---|
| LLM Usage Logs | `sysadmin-llm-usage-logs` | `llm-usage-logs-view.svelte` |

Navigation is under the `sysadmin-logs` sub-group, alongside "Doc Processor Logs".

#### API Endpoints (both under `/api/v1`, both auth-guarded)

| Method | Path | Handler | Purpose |
|---|---|---|---|
| `GET` | `/llm/usage-events-admin` | `ListUsageEventsAdmin` | Paginated list of all `llm_usage_event` rows (LEFT JOIN — includes events with NULL `account_id`), with `input_body_ref` and `output_body_ref` |
| `GET` | `/llm/usage-events/:id/body` | `GetUsageEventBody` | Read, decompress, and return the gzip-archived request or response body for one event (`?type=input\|output`) |

The existing `GET /llm/usage-events` endpoint (used by the LLM Activities view) is unchanged — it still returns only events linked to a non-NULL `account_id` and does not include body refs.

#### Query parameters — `GET /llm/usage-events-admin`

| Parameter | Default | Description |
|---|---|---|
| `page` | `1` | 1-based page number |
| `page_size` | `50` | Rows per page |

Response shape: `{ events: UsageEventAdmin[], total: number, page: number, page_size: number }`.

#### Body fetch — `GET /llm/usage-events/:id/body`

- Fetches `input_body_ref` or `output_body_ref` from `llm_usage_event` for the given `id`.
- Resolves the full path as `<archive_root>/<ref>` where `archive_root` comes from `config.GetLLMConfig().ArchiveRoot`.
- Calls `sharedllm.ReadGzipFile` to decompress and returns the raw JSON bytes with `Content-Type: application/json`.
- Returns 404 if the event is not found or if the body was not archived (empty ref).

> **`LLM_ARCHIVE_ROOT` note:** The ADR's "Environment Variables" table lists `LLM_ARCHIVE_ROOT` as an env var, but the actual implementation reads `archive_root` from `config.toml` via viper/mapstructure. There is no `LLM_ARCHIVE_ROOT` environment variable in the code. The current value is `archive_root = "/Users/cding/Apps/llm-logs"` in `ChenWeb/config.toml`, with a default of `"Data/llm-logs"` if unset.

#### Backend files

| File | Contents |
|---|---|
| `ChenWeb/server/api/llmreporthandler/store.go` | `UsageEventAdmin` type; `Store.ListUsageEventsAdmin` (paginated, LEFT JOIN); `Store.GetUsageEventBodyRefs` |
| `ChenWeb/server/api/llmreporthandler/handler.go` | `ListUsageEventsAdmin` and `GetUsageEventBody` HTTP handlers; `reportStore` interface extended |
| `ChenWeb/server/api/routes.go` | Route registration (search `/llm/usage-events-admin` and `/llm/usage-events/:id/body`) |

#### Frontend files

| File | Purpose |
|---|---|
| `ChenWeb/web/src/lib/components/home3/llm-usage-logs-view.svelte` | Paginated table of all `llm_usage_event` rows; double-click on a body-ref cell fetches the archive and shows the JSON in a modal |
| `ChenWeb/web/src/lib/components/home3/nav-rail.svelte` | Navigation item added under `sysadmin-logs` |
| `ChenWeb/web/src/lib/components/home3/content-panel.svelte` | Route `sysadmin-llm-usage-logs` wired to `LLMUsageLogsView` |

#### UI behaviour

- **Table columns:** Started At · Provider · Model · Prompt · In Tok · Out Tok · Latency · Input Body · Output Body · Error.
- Events are ordered `request_started_at DESC`. No client-side sort or filter controls (all events, all providers).
- A NULL `account_id` row (unlinked event) is shown normally; the Account column simply renders empty.
- **Input Body / Output Body cells:** show the filename portion of the archive path (e.g. `llm-18b32c8f-input.json.gz`). The cell is clickable only if the ref is non-empty. A **double-click** triggers `GET /llm/usage-events/:id/body?type=input|output`, decompresses on the server, and displays the pretty-printed JSON in a modal overlay.
- A single-click on the body cell does nothing — double-click is required to avoid accidental fetches while scrolling.

## Operational Behaviors

- If `DefaultUsageCaptureSink` is `nil` (e.g., a project that has not installed a sink), `captureUsageRecord` is a no-op. LLM calls proceed normally; no capture occurs.
- Sink errors do not propagate to the caller — a failed DB write does not abort the LLM call or the handler.
- Body archiving is skipped when the body is empty or when `ArchiveRoot` is not configured.
- The Anthropic adapter defaults `max_tokens` to 8096 when `Request.MaxTokens` is nil or zero, matching common Anthropic model limits.
- `anthropic-version` defaults to `2023-06-01`; can be overridden via `ProviderConfig.Extra["anthropic-version"]`.

## Consequences

**Benefits:**
- Every in-process LLM call through the shared client is now captured with zero call-site changes.
- Cost and token usage are queryable per account, model, prompt, and document record.
- Prompt cache effectiveness (hit vs. miss tokens) is tracked for both OpenAI and Anthropic.
- The Anthropic adapter is a proper implementation — it handles tool use, multimodal parts, streaming tool call accumulation, and prompt caching.

**Limitations:**
- Gemini (`ProviderGemini`) remains a stub; calls return `ErrAdapterNotImplemented`.
- LLM calls made by `agentrun` Docker runners run as external processes and are not captured by this mechanism. They are captured separately as OTEL spans by `proxytracehandler` when the MITM proxy is active.
- Body archiving writes to local disk; in a multi-process or distributed deployment the archive root must be a shared volume.

## Tests

The existing `shared/go/api/llm` test suite (`go test ./api/llm/...`) covers the `UsageCaptureSink` interface and `openaiClient` capture paths. The Anthropic adapter follows the same structure and is covered by the compile-time interface assertion (`var _ Client = (*anthropicClient)(nil)`).

Integration tests against the live Anthropic API are not part of the automated suite; manual verification with `ANTHROPIC_API_KEY` is required before enabling in production.

**2026-07-06 additions (TDD):** `shared/go/api/llm/usage_capture_test.go` covers the `call_reason`/`call_loc` warning and the `Metadata` fallback/passthrough in `captureUsageRecord`; `shared/go/api/llm/openai_client_test.go` covers `JSONExtractionInput.Metadata` flowing into the captured record; `ChenWeb/server/api/llmusage/sink_test.go` covers `metadata_json` merging caller-supplied keys; `ChenWeb/server/api/doc-reviews/review-provisions_test.go` covers the provisions reviewer setting `call_reason`, `call_loc`, and `provision_id`/`run_id` metadata.

## Documentation Impact

- `shared/go/api/llm/` package doc in `types.go` lists supported providers; Anthropic is now fully supported.
- The observability design (`KnowledgeStore/Capsules/coding-capsules/observability/observability-design.md`) lists LLM call spans as Phase 2 work. This ADR covers DB-level capture (complementary path), not OTEL spans.

## References

**Sink / capture layer:**
- `shared/go/api/llm/usage_capture.go` — `UsageCaptureSink` interface, `UsageCaptureRecord` type, mandatory call_reason/call_loc warning, `Metadata` fallback (2026-07-06)
- `shared/go/api/llm/openai_client.go` — `JSONExtractionInput.Metadata` (2026-07-06)
- `shared/go/api/llm/anthropic.go` — Anthropic adapter (this ADR)
- `shared/go/api/llm/openai.go` — OpenAI/compatible adapter (reference implementation)
- `shared/go/api/llm/client.go` — provider dispatch (`NewClient`)
- `ChenWeb/server/api/llmusage/sink.go` — ChenWeb PostgreSQL + gzip-archive sink; `InstallDefaultSink()`; merges `record.Metadata` into `metadata_json` (2026-07-06)
- `ChenWeb/server/api/doc-processing/llm_capture_input.go` — `withLLMRunID`/`llmRunIDFromContext` context helpers (2026-07-06)
- `ChenWeb/server/api/doc-reviews/review-provisions.go` — reference implementation of the new call_reason/call_loc/metadata convention (2026-07-06)

**Admin handler (account + profile + TOML management):**
- `ChenWeb/server/api/llmadminhandler/handler.go` — `accountAdminStore` interface, `adminStoreFactory`
- `ChenWeb/server/api/llmadminhandler/store.go` — account CRUD + `ImportParsedModels`
- `ChenWeb/server/api/llmadminhandler/profile_store.go` — profile CRUD + `UpsertAccountAndProfile`
- `ChenWeb/server/api/llmadminhandler/profile_handler.go` — profile HTTP handlers
- `ChenWeb/server/api/llmadminhandler/model_handler.go` — `AddModel` (TOML + DB combined)
- `ChenWeb/server/api/llmadminhandler/toml_handler.go` — `.models.toml` read/write handlers
- `ChenWeb/server/api/llmimport/models_toml.go` — TOML parser used by import-from-file flow
- `ChenWeb/server/api/routes.go` — route registration (search for `/llm/`)

**Frontend (home3 UI):**
- `ChenWeb/web/src/lib/components/home3/nav-rail.svelte` — navigation items (search `sysadmin-llm`, `sysadmin-logs`)
- `ChenWeb/web/src/lib/components/home3/content-panel.svelte` — view routing (search `sysadmin-llm`, `sysadmin-llm-usage-logs`)
- `ChenWeb/web/src/lib/components/home3/llm-accounts-view.svelte` — LLM Accounts page + "Add a Model" form
- `ChenWeb/web/src/lib/components/home3/llm-accounts-client.ts` — fetch wrappers for account endpoints
- `ChenWeb/web/src/lib/components/home3/llm-model-profiles-view.svelte` — Model Profiles page
- `ChenWeb/web/src/lib/components/home3/llm-model-profiles-client.ts` — fetch wrappers for profile endpoints
- `ChenWeb/web/src/lib/components/home3/llm-models-view.svelte` — LLM Models page (`.models.toml` editor)
- `ChenWeb/web/src/lib/components/home3/llm-models-client.ts` — fetch wrappers for TOML + AddModel endpoints
- `ChenWeb/web/src/lib/components/home3/llm-usage-logs-view.svelte` — LLM Usage Logs page (paginated `llm_usage_event` table + body viewer modal)

**Database:**
- `ChenWeb/project_migrations/20260619000001_create_llm_activity_tables.sql` — creates `llm_account`, `llm_account_model_profile`, `llm_usage_event`, `llm_daily_account_report`, `llm_balance_snapshot`
- `ChenWeb/project_migrations/20260620000003_add_llm_usage_event_call_metadata.sql`
- `ChenWeb/project_migrations/20260625000002_add_llm_usage_prompt_cache_tokens.sql`

**Shared types:**
- `shared/go/api/ApiTypes/ApiTypes.go` — `LLMModelsFile`, `LLMModelDef` (TOML struct)

**Design:**
- `KnowledgeStore/Capsules/coding-capsules/observability/observability-design.md` — OTEL span plan (Phase 2, not yet implemented)
