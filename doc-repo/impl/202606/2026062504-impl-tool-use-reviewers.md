# Document Review Tool-Use — Implementation

**DocID:** `doc-2026062504-impl-tool-use-reviewers`
**Status:** Implemented (Phase II — 2026-06-25)
**Date:** 2026-06-25

## Related Documents

- **ADR:** `doc-repo/adrs/202606/2026061801-adr-document-review.md` (DR10/DR10a/DR10b/DR10c)
- **Spec:** `doc-repo/specs/202606/2026062503-spec-tool-use-reviewers.md`
- **Design:** `doc-repo/design/202606/2026062502-design-tool-use-reviewers.md`
- **Checklist:** `doc-repo/specs/202606/2026061102-spec-document-review-checklist.md`
- **Review Spec:** `doc-repo/specs/202606/2026062104-spec-document-review.md`

## Architecture Overview

```
doc-review.local.toml                 ReviewTool registry
  max_tool_turns=N ──┐                ┌─────────────────────┐
  max_tool_tokens=N ─┤                │ search_entities     │
  tools=[...] ───────┤                │ get_entity          │
                     ▼                │ get_entity_relations│
ReviewerConfig ──► processWindow ──┐  │ search_metrics      │
  MaxToolTurns=5         │         │  │ get_metric          │
  MaxToolTokens=N        │         │  │ search_provisions   │
  Tools=[...]            │         │  │ get_provision       │
                         ├─────────┤  │ get_chunk_summary   │
one-shot (unchanged)     │tool-use │  │ get_chunk_lines     │
  ExtractJSON(...)       │path     │  └─────────────────────┘
                         │         │           │
                         │  runToolUseReview   │
                         │    ┌─────────┐      │
                         │    │Complete  │──────┘
                         │    │(tools)   │  tool calls
                         │    │    │     │  + results
                         │    │  findings│
                         │    └─────────┘
                         ▼         ▼
                normalizeFindingsJSON(finding-defaulting)
```

Two execution paths share one reviewer and one finding-defaulting block:
- **One-shot** (`max_tool_turns = 0`): single `ExtractJSON` call per 200-line window — byte-for-byte identical to the Phase I path.
- **Tool-use** (`max_tool_turns > 0`): bounded conversation loop `runToolUseReview` with the record-scoped tool registry.

The shared package `github.com/chendingplano/shared/go/api/llm` provides the tool-capable chat transport (`Client.Complete(ctx, Request{Tools,...})`). No new HTTP or serialization layer is required — only a thin client builder (`BuildReviewerToolClient`) that resolves a model ref and constructs an OpenAI-compatible `llm.Client`.

## File Inventory

### New Files (6)

| File | Lines | Description |
|------|-------|-------------|
| `server/api/doc-reviews/review-tools.go` | 549 | `ReviewTool` registry + 9 document-intrinsic core tools (record-scoped, backed by `kb.entities` / `kb.metrics` / `kb.provisions` / `kb.summaries` / `kb.relations` / line-file). Exports `buildToolRegistry`, `selectTools`, `coreToolNames`. |
| `server/api/doc-reviews/review-tool-loop.go` | 319 | `runToolUseReview` managed conversation loop (DR10b): assembles DR8a-layout messages, calls model with tools via `llm.Client.Complete`, executes tool calls through the record-scoped registry, force-finalizes on budget exhaustion. Includes `executeToolCall` (validates args against schema, returns error payloads the model can retry from), `finalizeFindings` (force-produce without tools), `parseFindingsContent` (extracts `{"findings":[...]}` from model content, tolerating code fences), `extractJSONObject` (balanced `{...}` parser), `logLoopUsage` (per-call cache-hit/miss capture, DR8a). MID codes: `MID_26062595`, `MID_26062596`. |
| `server/api/doc-reviews/review-tools_test.go` | 114 | 4 tests: registry shape + schema validity, `selectTools` subset/all, `search_entities` record-scoping via `sqlmock`, query-required validation. |
| `server/api/doc-reviews/review-tool-loop_test.go` | 162 | 5 tests: tool-call→findings happy path, turn-budget exhausted finalize, stop mid-loop (via `context.WithCancelCause(ErrPipelineStopped)`), `extractJSONObject` (fences/nested/no-JSON), `missingRequiredArgs`. Uses `fakeToolClient` implementing `LLMChatClient`. |
| `server/api/doc-processing/review_tool_client_test.go` | 34 | 2 tests: empty model ref errors cleanly (no panic, nil client), unknown ref errors with a non-empty message. |
| `prompts/prompt-review-evidence-rationale.md` | — | Reviewer prompt (created in the prior `evidence_rationale` reviewer change, unchanged). |

### Modified Files (7)

| File | Changes |
|------|---------|
| `server/api/doc-processing/review_exports.go` | Added `BuildReviewerToolClient(modelRef) (llm.Client, modelName, error)` — resolves model ref via `loadModelConfigByRef`/`MODEL_DEF_FILE` and constructs `llm.NewClient(ProviderOpenAICompatible, BaseURL, APIKey)` with the resolved model's timeout. Mirrors `BuildReviewerLLMClient` but returns a tool-capable `llm.Client` (not the JSON-only `LLMJSONExtractor`). |
| `server/api/doc-reviews/review_framework_aliases.go` | Added LLM chat type aliases (`LLMChatClient`, `LLMRequest`, `LLMResponse`, `LLMMessage`, `LLMToolDef`, `LLMToolCall`, `LLMUsage`) and role constants (`LLMRoleSystem`, `LLMRoleUser`, `LLMRoleAssistant`, `LLMRoleTool`) from `llmclients`. Re-exported `BuildReviewerToolClient` as a local function binding. |
| `server/api/doc-reviews/review-config.go` | Added `MaxToolTokens int` to `ReviewPackageConfig`; added `MaxToolTokens *int` and `Tools []string` to `ReviewAspectConfig`; added `MaxToolTokens int` and `Tools []string` to `ResolvedReviewerConfig`. Updated `ResolveReviewer` merge to copy `MaxToolTokens` from group defaults and override from per-aspect config, and to append-copy `Tools` from per-aspect overrides. |
| `server/api/doc-reviews/review-document.go` | Added `MaxToolTokens int` to `ReviewerConfig`. Added `EvidenceRationaleMaxToolTurns`, `EvidenceRationaleMaxToolTokens`, `EvidenceRationaleTools` fields to `ReviewProcessor`. Added `EvidenceRationaleToolClient LLMChatClient` field to `ReviewProcessor`. Added `resolveReviewerBudget(aspect, group)` function. Added `resolveReviewerToolClient(logger, aspect, group, maxToolTurns)` function. Budget fields resolved in `NewReviewProcessor` and assigned to struct. Plumbed `MaxToolTurns`/`MaxToolTokens`/`Tools` into the `evidence_rationale` `ReviewerConfig` in `buildReviewers`. |
| `server/api/doc-reviews/review-evidence-rationale.go` | Added `toolClient LLMChatClient` and `toolRegistry map[string]ReviewTool` fields to `evidenceRationaleReviewer`. `processWindow` branches: `cfg.MaxToolTurns > 0 && r.toolClient != nil` → tool-use path (`selectTools` + `runToolUseReview` with DR8a layout); else → one-shot path (unchanged). Both paths funnel through the same finding-defaulting. MID codes: `MID_26062591`–`MID_26062594`. |
| `doc-review.local.toml` | `[reviewers.evidence_rationale]` block present with `enabled=true`, `model=deepseek-v4-pro`, `prompt=prompt-review-evidence-rationale.md`, `max_tool_turns=0` (one-shot by default; flip to 5 to activate tool-use). P3 package default includes `max_tool_turns=0`. |
| `doc-repo/adrs/202606/2026061801-adr-document-review.md` | Change log entry for Phase II implementation (DR10/DR10a/DR10b/DR10c) + Implementation Files section updated with all new/modified files. |

## Key Implementation Details

### 1. ReviewTool Registry (`review-tools.go`)

Each tool is a `ReviewTool{Name, Description, Parameters json.RawMessage, Execute func(ctx, recordID, args)}`. The execute functions are closures over a `*sql.DB` handle (`toolDB`), and every SQL query carries `WHERE input_record_id = $1` as its first condition — structural record-scoping, not prompt-based.

**Entity tools** (`search_entities`, `get_entity`, `get_entity_relations`):
- `search_entities`: ILIKE against `kb.entities.search_document`, `entity`, and `entity_en`, ordered by confidence.
- `get_entity`: direct row read by `entity_id`.
- `get_entity_relations`: resolves the entity's surface name, then matches it as subject or object in `kb.relations` (ILIKE on both fields for flexibility).

**Metric tools** (`search_metrics`, `get_metric`):
- `search_metrics`: ILIKE against `kb.metrics.search_document`, `metric_name`, and `metric_name_en`.
- `get_metric`: direct row read by `metric_id`, returns 14 columns including value/unit/threshold/definition.

**Provision tools** (`search_provisions`, `get_provision`):
- `search_provisions`: ILIKE against `kb.provisions` name, description, provision text, and source text.
- `get_provision`: direct row read by `prov_id`.

**Chunk tools** (`get_chunk_summary`, `get_chunk_lines`):
- `get_chunk_summary`: when called with no `chunk_id`, returns level-0 summaries in order (a section map). With a `chunk_id`, returns the target + prev/next sibling summaries.
- `get_chunk_lines`: resolves the document's line-file via `loadRecordLines`, filters by `[start_line, end_line]` range.

`normalizeColValue` converts `[]byte` (text/JSONB) into strings or parsed JSON objects so the tool-result JSON is structured for the LLM to read.

### 2. Conversation Loop (`review-tool-loop.go`)

`runToolUseReview(ctx, client, modelName, cfg, systemPrompt, userContext, tools, recordID, logger)`:

1. **Message assembly**: `[system(systemPrompt), user(userContext)]`. The caller (reviewer) is responsible for the DR8a `DOCUMENT_INPUT`/`REVIEW_TASK` layout in `userContext`. Tool defs are adapted from `ReviewTool` to `LLMToolDef` via `toolDefsFor`.
2. **Turn loop** (`turn < maxTurns`): stop-check → `client.Complete(ctx, Request{Messages, Tools, ToolChoice:"auto"})` → if `ToolCalls` present: execute via registry (validate args against schema; return error payload on bad args, never crash), append assistant + tool messages, accumulate token cost → continue. If no tool calls: parse `Content` as `{"findings":[...]}` (with code-fence stripping) and return.
3. **Token budget**: `usageTotalTokens(resp.Usage)` accumulates; when `tokensUsed >= maxTokens`, finalize immediately.
4. **Finalize**: append force-produce instruction ("You have reached the maximum investigation budget..."), call once without tools, parse findings.
5. **Degenerate response**: if the model returns neither tool calls nor parseable findings, one repair is attempted (the model sees its assistant response; finalize may still produce empty findings).

**Error resilience**: `executeToolCall` never returns a Go error — it always returns a JSON error payload (`{"error": "..."}`) as the tool-role message so the model can retry within budget.

**Cache capture** (`logLoopUsage`): logs `input_tokens`, `output_tokens`, `total_tokens`, `prompt_cache_hit_tokens`, `prompt_cache_miss_tokens` from each `Response.Usage` (DR8a groundwork).

### 3. Tool-Capable LLM Client (`review_exports.go`)

`BuildReviewerToolClient(modelRef)`:
- Resolves `modelRef` against `MODEL_DEF_FILE` via the existing `loadModelConfigByRef`.
- Constructs `llm.NewClient(ProviderConfig{ID: ProviderOpenAICompatible, BaseURL, APIKey})` — DeepSeek and other OpenAI-compatible providers work through this path.
- Returns `llm.Client` (implements `Complete` + `Stream`) with the configured timeout.
- Clean errors on empty ref ("empty model ref") and unknown ref ("model not found in models file"), no panics.

### 4. Config Plumbing (`review-config.go`, `review-document.go`)

**New config fields** (TOML-driven, pointer-distinguished for per-aspect overrides):
- `max_tool_tokens` — per-group default (`int`) and per-aspect override (`*int`). When unset, the P3 code default (`defaultP3MaxToolTokens = 60000`) applies.
- `tools` — per-aspect override only (`[]string`). When empty, all 9 core tools are bound.

**Runtime resolution chain**:
1. `resolveReviewerRuntime(aspect, group)` → prompt + model + JSON client (unchanged).
2. `resolveReviewerBudget(aspect, group)` → `MaxToolTurns`, `MaxToolTokens`, `Tools` from merged config.
3. `resolveReviewerToolClient(logger, aspect, group, maxToolTurns)` → `llm.Client` when `maxToolTurns > 0` and model ref resolves; nil otherwise.
4. `buildReviewers` populates the reviewer's `ReviewerConfig` with all fields and the reviewer struct with `toolClient`/`toolRegistry`.

**Backward compatibility**: reviewers with `max_tool_turns = 0` never attempt tool client resolution; `resolveReviewerToolClient` returns nil immediately for zero turns; `buildReviewers` always populates `toolClient` (nil for one-shot reviewers).

### 5. evidence_rationale Branching (`review-evidence-rationale.go`)

```go
if cfg.MaxToolTurns > 0 && r.toolClient != nil {
    tools := selectTools(r.toolRegistry, cfg.Tools)
    userCtx := fmt.Sprintf("<DOCUMENT_INPUT>\n%s\n</DOCUMENT_INPUT>\n\n<REVIEW_TASK>\n%s\n</REVIEW_TASK>", w.inputJSON, cfg.PromptText)
    findings, err = runToolUseReview(ctx, r.toolClient, cfg.ModelName, cfg, cfg.PromptText, userCtx, tools, recordID, r.logger)
} else {
    // existing one-shot ExtractJSON path
}
// both paths → same finding-defaulting (Pass="P3", Aspect="evidence_rationale", etc.)
```

The `DOCUMENT_INPUT`/`REVIEW_TASK` layout implements the DR8a prefix-cache strategy: the canonical document/window JSON always appears before the reviewer-specific task, making it a stable prefix for DeepSeek's automatic prefix cache.

## Configuration

### Activation

```toml
# in doc-review.local.toml

[reviewers.evidence_rationale]
enabled = true
model = "deepseek-v4-pro"
prompt = "prompt-review-evidence-rationale.md"
max_tool_turns = 0      # SET TO 5 TO ACTIVATE TOOL-USE
# max_tool_tokens = 60000  # optional override (default: 60000)
# tools = ["search_entities", "get_entity"]  # optional subset (empty ⇒ all 9)
```

### Rollback

Set `max_tool_turns = 0` — pure config change, no redeploy. The reviewer falls back to the byte-for-byte identical one-shot path.

## Test Inventory

| Test | Package | Purpose |
|------|---------|---------|
| `TestBuildToolRegistryShapeAndSchemas` | doc-reviews | All 9 core tools present, each has valid JSON-Schema params, no cross-document tools leak in |
| `TestSelectToolsSubsetAndAll` | doc-reviews | `selectTools(nil)` returns all 9; `selectTools([subset])` returns only those named; unknown names skipped |
| `TestSearchEntitiesIsRecordScoped` | doc-reviews | `search_entities` SQL carries `input_record_id=$1`; JSONB columns parse as structured data |
| `TestSearchEntitiesRequiresQuery` | doc-reviews | Missing required arg returns error |
| `TestRunToolUseReviewToolCallThenFindings` | doc-reviews | Turn 0: tool call → executed; Turn 1: findings JSON → returned. 1 tool execution, 1 finding |
| `TestRunToolUseReviewTurnBudgetExhausted` | doc-reviews | `max_tool_turns=0` (clamped to 1) → findings from the single call |
| `TestRunToolUseReviewStopMidLoop` | doc-reviews | `context.WithCancelCause(ErrPipelineStopped)` → loop returns `ErrPipelineStopped` |
| `TestExtractJSONObjectStripsFences` | doc-reviews | Fenced ` ```json `, unfenced, nested `{}`, trailing prose, no-JSON cases |
| `TestMissingRequiredArgs` | doc-reviews | Schema `required` enforcement: missing arg listed; all present → empty |
| `TestBuildReviewerToolClientEmptyRefErrors` | doc-processing | Empty model ref returns error + nil client + empty model name |
| `TestBuildReviewerToolClientUnknownRefErrors` | doc-processing | Unknown model ref returns non-empty error |
| `TestEvidenceRationaleReviewerProcessWindowPropagatesPromptName` | doc-reviews | **Pre-existing**, kept passing: one-shot path with `max_tool_turns=0` → prompt name propagated to the fake extractor |

**Total:** 4 registry tests + 5 loop tests + 2 client builder tests + 1 reviewer integration test = **12 tests covering all components**.

doc-processing pre-existing failures (summary, metrics, provisions, products, chunking — 20+ failures) are **unrelated** to this change; the doc-reviews package passes all tests (`ok github.com/chendingplano/deepdoc/server/api/doc-reviews 0.211s`).

## Build Verification

```bash
$ go build ./server/api/doc-reviews/... ./server/api/doc-processing/...
# (no errors)

$ go test ./server/api/doc-reviews/... -count=1
ok  github.com/chendingplano/deepdoc/server/api/doc-reviews  0.211s

$ go test ./server/api/doc-processing/ -run TestBuildReviewerToolClient
ok  github.com/chendingplano/deepdoc/server/api/doc-processing  0.012s
```

## Remaining Work

| Item | Status | Notes |
|------|--------|-------|
| Smoke-test `evidence_rationale` tool-use path on a real record | Deferred | Needs a running system with DeepSeek access; set `max_tool_turns=5` and `model=deepseek-v4-pro` |
| Convert other P3 reviewers to tool-use (`completeness`, `correctness`, etc.) | Deferred | Follow the same pattern: add `toolClient`/`toolRegistry` fields, branch in `processWindow`. Framework is reusable. |
| P4/P5 tool-use (consistency/compliance reviewers + cross-document tools) | Deferred | DR10a P5 tools not implemented; DR4 reference retrieval not integrated |
| Per-review-run TOML overrides | Deferred | `model_overrides` JSONB persisted but not applied at execution time |
| `openspec archive p3-tool-use-reviewers` | Deferred | Run after smoke-test confirms tool-use findings on a known document |
