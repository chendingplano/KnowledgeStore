# Document Review Tool-Use Design

**DocID:** `doc-2026062502-design-tool-use-reviewers`
**Status:** Implemented (Phase II — 2026-06-25)
**Date:** 2026-06-25

## Related Documents

- **Spec:** `doc-repo/specs/202606/2026062503-spec-tool-use-reviewers.md`
- **Implementation:** `doc-repo/impl/202606/2026062504-impl-tool-use-reviewers.md`
- **ADR:** `doc-repo/adrs/202606/2026061801-adr-document-review.md`

## Context

The doc-review framework (`server/api/doc-reviews`, package `docreviews`) runs each reviewer as a goroutine and collects `[]ReviewFinding`. P3 reviewers today are one-shot: `processWindow` makes a single `r.client.ExtractJSON(ctx, newDocReviewLLMJSONInput(...))` call per 200-line window and normalizes the JSON response. `ReviewerConfig` already carries `MaxToolTurns int` and `Tools []string`, and `review-config.go` resolves both from `doc-review.local.toml`, but `buildReviewers` does not copy them into the runtime `ReviewerConfig`, and no reviewer reads them — so they are inert (confirmed: `MaxToolTurns` is referenced only in a log line at `review-document.go:426`).

Key enabling fact: the shared package `github.com/chendingplano/shared/go/api/llm` **already implements tool-calling**. `llm.NewClient(ProviderConfig{ID: ProviderOpenAICompatible, BaseURL, APIKey})` returns a `Client` whose `Complete(ctx, Request)` accepts `Request.Tools []ToolDef` + `Request.ToolChoice` and returns `Response{Content, ToolCalls []ToolCall, Usage{PromptCacheHit/MissTokens}}`. DeepSeek is OpenAI-compatible, so `deepseek-v4-pro` function-calling works through this path with no new transport code. The current reviewer client (`BuildReviewerLLMClient` → `llmclients.NewOpenAIJSONClient...`) only exposes the JSON-only `ExtractJSON` interface, which has no tool support — hence a separate tool-capable client builder is required.

The KB artifacts that back the tools already exist for each `input_record_id`: `kb.entities`, relations (via `kb.artifact_connections` / the entity store), `kb.metrics`, `kb.provisions`, `kb.summaries`, and chunk lines (the line-file / chunk stores). The `ReviewProcessor` already receives an `EntityStore EntityRelationStore` injected "for tool-using reviewers (Phase II+)".

ADR references: DR10 (LLM-as-investigator), DR10a (tool catalog — the 9 core tools), DR10b (managed conversation loop), DR10c (budget management), DR8a (DeepSeek prefix-cache prompt layout + usage capture).

## Goals / Non-Goals

**Goals:**
- A `ReviewTool` registry exposing the 9 document-intrinsic core tools (DR10a), each scoped to one `input_record_id`, with valid JSON-Schema parameters and a typed `Execute`.
- A reusable, bounded `runToolUseReview` loop (DR10b/DR10c) that any reviewer can call: turn cap = `MaxToolTurns`, token cap = `MaxToolTokens`, stop-aware at each LLM boundary, force-finalize on budget exhaustion (no findings lost).
- A tool-capable reviewer LLM client builder over `shared/go/api/llm`.
- `MaxToolTurns` + `Tools` plumbed from config into the runtime `ReviewerConfig`; reviewers branch one-shot vs tool-use on `MaxToolTurns`.
- `evidence_rationale` runs end-to-end through the tool-use path when configured with `max_tool_turns > 0`, validating the framework on a real reviewer.
- DeepSeek `prompt_cache_hit_tokens`/`prompt_cache_miss_tokens` logged per call (DR8a measurement groundwork).

**Non-Goals:**
- Cross-document P5 tools (`search_reference_docs`, `get_reference_roster`, `search_reference_provisions`, `check_entity_in_reference`) and DR4 reference retrieval.
- Converting `completeness`, `correctness`, or any reviewer other than `evidence_rationale` to tool-use in this change (framework stays reusable; conversions are follow-ups).
- Per-review-run TOML overrides and applying request-level `model_overrides` JSONB.
- Streaming, parallel tool execution within a single turn, or persistent cross-window investigation state.
- Schema migrations (none needed).

## Decisions

**D1 — Build on `shared/go/api/llm.Client.Complete`, not a new transport.**
The shared package already serializes `tools`/`tool_calls` for the OpenAI-compatible `/v1/chat/completions` endpoint and parses tool calls + cache usage back. We add a thin `BuildReviewerToolClient(modelRef) (llm.Client, modelName, error)` that resolves the model ref the same way `BuildReviewerLLMClient` does (via `loadModelConfigByRef`/`MODEL_DEF_FILE`) and constructs `llm.NewClient(ProviderOpenAICompatible, ...)`. *Alternative considered:* extend `LLMJSONExtractor` with a tool method — rejected, it would entangle the JSON-only client and every existing one-shot caller.

**D2 — `ReviewTool` as a value struct, registry keyed by name.**
```go
type ReviewTool struct {
    Name        string
    Description string
    Parameters  json.RawMessage // JSON Schema
    Execute     func(ctx context.Context, recordID int64, args map[string]any) (any, error)
}
```
`buildToolRegistry(recordID, stores) map[string]ReviewTool` constructs the 9 tools bound to a single record's stores; `selectTools(registry, cfg.Tools)` returns the subset a reviewer requested (empty `cfg.Tools` ⇒ all core tools). *Alternative considered:* a Go `interface` per tool — rejected as heavier than needed for stateless, schema-described functions (matches the ADR's struct sketch in DR10a).

**D3 — Record-scoped tools.** Every tool takes `recordID` and queries only that document's artifacts; this enforces the "document-intrinsic" guarantee structurally rather than by prompt convention. Backing stores reuse the already-injected `EntityStore` plus read helpers over `kb.metrics`/`kb.provisions`/`kb.summaries`/chunk lines; where a needed read method is missing, add a focused `SQLStore` query method in the doc-reviews package.

**D4 — Loop contract mirrors DR10b exactly, with a structured-output finalizer.**
`runToolUseReview(ctx, client, modelName, cfg, systemPrompt, userContext, tools, onProgress) ([]ReviewFinding, error)`:
1. messages = [system, user(`<DOCUMENT_INPUT>…</DOCUMENT_INPUT>` + task)] per DR8a layout (canonical doc input first for prefix-cache reuse).
2. For `turn < MaxToolTurns`: check stop; `client.Complete(ctx, Request{Messages, Tools, ToolChoice:"auto"})`; if `Response.ToolCalls` present → execute via registry, append assistant + tool messages, accumulate tool-token cost; else parse `Response.Content` as findings JSON and return.
3. On budget exhaustion (turns or `MaxToolTokens`) → append the DR10b force-produce user message, call once more **without** tools, parse findings.
The loop never emits both findings and tool calls in one step — findings are taken only when no tool calls are returned (or at finalize). *Alternative considered:* a separate `findingsSchema` tool the model "calls" to finish — deferred; plain JSON content + a strict prompt is simpler for DeepSeek and matches the existing `normalizeFindingsJSON` path.

**D5 — Reviewer branch is local and additive.**
`evidenceRationaleReviewer.processWindow` branches: `cfg.MaxToolTurns <= 0 || r.toolClient == nil` → existing `ExtractJSON` one-shot (unchanged); else `runToolUseReview(... r.toolClient ...)`. The reviewer gains a `toolClient llm.Client` field and a `registry`/store handle; `buildReviewers` populates them only when a tool client resolved. This keeps one-shot behavior byte-for-byte identical when `max_tool_turns = 0`.

**D6 — Config plumbing.** In `buildReviewers`, set `ReviewerConfig.MaxToolTurns` and `ReviewerConfig.Tools` from the resolved config (currently dropped). Add a tool-client resolution alongside the existing `resolveReviewerRuntime` (or extend it to also return a tool client when `MaxToolTurns > 0`). `MaxToolTokens` default lives in code (DR10c P3 budget) with an optional config override.

**D7 — Budgets (DR10c), config-overridable.** P3 defaults: `MaxToolTurns = 5`, core tools, and a code-level default `MaxToolTokens` cap on cumulative tool-result tokens. Both `max_tool_turns` and `max_tool_tokens` are overridable per reviewer (and per group default) in `doc-review.local.toml`; the code default applies only when the config leaves the field unset (pointer-distinguished, matching the existing config-merge style). Turn and token caps are independent; either triggers finalize.

**D8 — The 9 core tools require new record-scoped read methods (no reuse available).** An audit of the existing stores shows the framework has *no* reusable read path for the tools: `EntityRelationStore` exposes only `*Exist` / `Delete*` / `Save*` (no reads), and the doc-reviews `SQLStore` reads only `kb.inputs`/events/status. The record-scoped `SELECT`s that do exist are private inline queries inside extraction code (`extract-entity-relation.go`) and HTTP handlers (`kbhandler/metrics_handler.go`, `kbhandler/provision_handlers.go`), and hybrid search lives in `kbhandler` (`kb.search_artifacts` + `queryHybridSearchResultsParadeDB`). Therefore each tool's backing read is a **new** focused query method added in the doc-reviews package, adapting those existing SQL patterns. `search_*` tools back onto `kb.search_artifacts` filtered by `input_record_id`; `get_*` tools onto direct row reads of `kb.entities` / `kb.metrics` / `kb.provisions` / `kb.summaries` / chunk lines; `get_entity_relations` onto `kb.relations` / `kb.artifact_connections` for the record. *Alternative considered:* call into `kbhandler` to reuse hybrid search — rejected to avoid a `doc-reviews → kbhandler` dependency; the SQL is small enough to own locally.

## Risks / Trade-offs

- **DeepSeek tool-calling fidelity / malformed tool args** → the loop validates each tool call's args against the tool's schema; invalid calls return a tool-role error message back to the model (which can retry within budget) rather than aborting the window.
- **Model returns neither tool calls nor valid findings JSON** → treat as an empty-findings finalize after one repair attempt; never crash the window (matches one-shot's "skip window on error" resilience).
- **Cost blow-up from multi-turn × many windows** → bounded by `MaxToolTurns` × `MaxToolTokens` per window; one-shot reviewers unaffected; `evidence_rationale` is the only tool-use reviewer enabled by this change, so blast radius is contained.
- **Tool latency adds wall-clock time per window** → tools are simple indexed KB reads on one record; per-call latency is small relative to the LLM round-trip. Existing per-window concurrency still applies.
- **Stop responsiveness** → `CheckAndHandleStop`-equivalent check at each LLM-call boundary (DR10b) returns partial findings + `ErrPipelineStopped`, consistent with the rest of the pipeline.
- **Drift from the JSON-only path** → both paths funnel through `normalizeFindingsJSON` and the same finding-defaulting (`pass=P3`, `aspect=evidence_rationale`, etc.), so findings are shape-identical regardless of path.

## Migration Plan

1. Land the tool registry, loop, and client builder behind the `MaxToolTurns > 0` branch with `evidence_rationale` still effectively one-shot (config `max_tool_turns = 0`) — no behavior change.
2. Flip `[reviewers.evidence_rationale] max_tool_turns = 5` (and `model = deepseek-v4-pro`) in `doc-review.local.toml` to activate the tool path; validate findings + logged cache/turn usage on a known record.
3. Rollback = set `max_tool_turns = 0` (pure config), which reverts to the one-shot path with no redeploy of logic.

## Open Questions

- ~~Should `MaxToolTokens` be configurable per reviewer?~~ **Resolved (D7):** yes — config-overridable per reviewer and per group default, with a code default when unset.
- ~~Do the 9 core tools need new SQL read methods?~~ **Resolved (D8):** yes — all 9 need new record-scoped read methods in the doc-reviews package; no reusable read path exists today.
- ~~Should tool-result token accounting use the model's reported usage or a local tokenizer estimate?~~ **Resolved during implementation:** sum `Response.Usage.TotalTokens` (with `InputTokens+OutputTokens` fallback when `TotalTokens` is zero), which the shared client already returns. This is implemented in `usageTotalTokens` in `review-tool-loop.go`.

## Tasks
### 1. Tool-capable LLM client

- [x] 1.1 Audit `shared/go/api/llm` to confirm `NewClient(ProviderConfig{ID: ProviderOpenAICompatible,...})`, `Client.Complete(ctx, Request{Messages, Tools, ToolChoice})`, `Response{Content, ToolCalls, Usage}` are sufficient for review tool-calling (no shared-package changes expected).
- [x] 1.2 Add `BuildReviewerToolClient(modelRef string) (llm.Client, modelName string, err error)` in `server/api/doc-processing/review_exports.go`, resolving the model ref via the existing `loadModelConfigByRef`/`MODEL_DEF_FILE` path and constructing an OpenAI-compatible `llm.Client`.
- [x] 1.3 Re-export the builder (and the needed `llm` types: `ToolDef`, `ToolCall`, `Message`, `Request`, `Response`, `Role*`) through `server/api/doc-reviews/review_framework_aliases.go`.
- [x] 1.4 Unit-test `BuildReviewerToolClient` with a stub model config (resolves a client; errors cleanly on unknown ref).

### 2. Tool registry and core tools

- [x] 2.1 Add `server/api/doc-reviews/review-tools.go` defining `ReviewTool{Name, Description, Parameters json.RawMessage, Execute func(ctx, recordID int64, args map[string]any)(any,error)}`.
- [x] 2.2 Add new record-scoped read methods backing each tool (D8 — no reusable read path exists today). Adapt existing SQL patterns: `search_*` over `kb.search_artifacts` filtered by `input_record_id`; `get_*` direct row reads of `kb.entities` / `kb.metrics` / `kb.provisions` / `kb.summaries` / chunk lines; `get_entity_relations` over `kb.relations` / `kb.artifact_connections`. Keep the queries local to the doc-reviews package (no `kbhandler` dependency). Confirm per-tool during implementation, but expect all 9 to need new methods.
- [x] 2.3 Implement the entity tools: `search_entities`, `get_entity`, `get_entity_relations` (record-scoped, valid JSON-Schema params).
- [x] 2.4 Implement the metric/provision tools: `search_metrics`, `get_metric`, `search_provisions`, `get_provision`.
- [x] 2.5 Implement the chunk tools: `get_chunk_summary`, `get_chunk_lines`.
- [x] 2.6 Add `buildToolRegistry(recordID int64, stores ...) map[string]ReviewTool` and `selectTools(registry, names []string) []ReviewTool` (empty names ⇒ all nine).
- [x] 2.7 Tests: each tool's JSON Schema is valid; `Execute` returns correctly typed results; a query is scoped to its `recordID` (record A query never returns record B rows); `selectTools` subset/all behavior.

### 3. Managed conversation loop

- [x] 3.1 Add `server/api/doc-reviews/review-tool-loop.go` with `runToolUseReview(ctx, client llm.Client, modelName string, cfg ReviewerConfig, systemPrompt, userContext string, tools []ReviewTool, onProgress ReviewerProgressFunc) ([]ReviewFinding, error)`.
- [x] 3.2 Build initial messages with the DR8a layout: canonical `<DOCUMENT_INPUT>…</DOCUMENT_INPUT>` first, reviewer task after; small common system message.
- [x] 3.3 Implement the turn loop (DR10b): stop-check → `Complete` with tools → if `ToolCalls` execute via registry, validate args against schema, append assistant + tool messages, accumulate tool-token cost → else parse `Content` via `normalizeFindingsJSON` and return.
- [x] 3.4 Implement budget finalize (DR10c): on `MaxToolTurns` or `MaxToolTokens` exhaustion, append force-produce message, call once without tools, parse findings (no partial findings lost).
- [x] 3.5 Handle the degenerate response (neither valid tool call nor parseable findings): one repair attempt, else return empty findings for the window.
- [x] 3.6 Stop handling: at each LLM-call boundary return collected findings + `ErrPipelineStopped`.
- [x] 3.7 Log per-call usage including `prompt_cache_hit_tokens` / `prompt_cache_miss_tokens` from `Response.Usage`.
- [x] 3.8 Tests with a fake `llm.Client`: tool-call-then-findings happy path; turn-budget finalize; token-budget finalize; malformed-args → tool-error → retry; both-in-one-response rejected; stop mid-loop.

### 4. Config plumbing

- [x] 4.1 In `buildReviewers` (`review-document.go`), copy resolved `MaxToolTurns` and `Tools` into each reviewer's runtime `ReviewerConfig` (currently dropped).
- [x] 4.2 Resolve a tool client per tool-use reviewer (extend `resolveReviewerRuntime` or add a sibling) when `MaxToolTurns > 0`; leave one-shot reviewers untouched.
- [x] 4.3 Add `max_tool_tokens` to the config schema (per-reviewer and per-group default) as a pointer field; resolve it in the config merge alongside `max_tool_turns`. Define a code-level P3 default `MaxToolTokens` (DR10c) applied only when the config leaves it unset; plumb the resolved value into `ReviewerConfig`. Document the field.

### 5. Wire evidence_rationale as proving ground

- [x] 5.1 Add `toolClient llm.Client` (+ registry/store handle) fields to `evidenceRationaleReviewer`; populate in `buildReviewers` only when a tool client resolved.
- [x] 5.2 Branch in `processWindow`: `cfg.MaxToolTurns <= 0 || toolClient == nil` → existing `ExtractJSON` one-shot (unchanged); else `runToolUseReview(...)` with `selectTools` over the record registry.
- [x] 5.3 Ensure both paths funnel through the same finding-defaulting (`pass=P3`, `aspect=evidence_rationale`, `finding_type`, `severity`, `location`).
- [x] 5.4 Tests: `max_tool_turns=0` yields the existing one-shot result; `max_tool_turns=5` with a fake tool client drives the loop and tags findings `P3`/`evidence_rationale`; unresolved tool client falls back to one-shot.

### 6. Verification and docs

- [x] 6.1 `go build ./server/api/doc-reviews/... ./server/api/doc-processing/...` and `go test ./server/api/doc-reviews/...` pass.
- [ ] 6.2 Set `[reviewers.evidence_rationale] max_tool_turns = 5`, `model = "deepseek-v4-pro"` in `doc-review.local.toml`; smoke-run a known record and confirm findings + logged turn/cache usage.
- [x] 6.3 Update ADR 2026061801 (change log + Implementation Files): mark DR10/DR10a/DR10b/DR10c Phase II implemented for P3 core tools + `evidence_rationale`.
- [x] 6.4 Update doc-review spec 2026062104 to note the tool-use execution path and that `max_tool_turns` is now operative for `evidence_rationale`.
- [ ] 6.5 Run `openspec archive p3-tool-use-reviewers` after implementation is verified.
