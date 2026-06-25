# Document Review Tool-Use Specification

**DocID:** `doc-2026062503-spec-tool-use-reviewers`
**Status:** Implemented (Phase II — 2026-06-25)
**Date:** 2026-06-25

## Related Documents

- **Design:** `doc-repo/design/202606/2026062502-design-tool-use-reviewers.md`
- **Implementation:** `doc-repo/impl/202606/2026062504-impl-tool-use-reviewers.md`
- **ADR:** `doc-repo/adrs/202606/2026061801-adr-document-review.md`
- **Checklist:** `doc-repo/specs/202606/2026061102-spec-document-review-checklist.md`

## Scope

This document specifies the **Phase II tool-use execution path** for P3 (Content Quality) doc reviewers — the `ReviewTool` registry of 9 document-intrinsic core tools, the bounded `runToolUseReview` conversation loop with budget and stop handling, the tool-capable reviewer LLM client, and the config-driven one-shot-vs-tool-use branch. `evidence_rationale` is the proving-ground reviewer.

## Why

P3 (Content Quality) doc reviewers (refer to [1]) such as `evidence_rationale`, `completeness`, and `correctness` are described in ADR 2026061801 (DR10) as *investigators*: they should form hypotheses about a passage and chase them down by querying the document's extracted artifacts (entities, relations, metrics, provisions, chunk summaries) before producing findings. The current implementation is one-shot only — every reviewer makes a single `LLMJSONExtractor.ExtractJSON` call over a 200-line window. The `max_tool_turns` config field is parsed and logged but **never read at execution time**, and no tool registry, tool-execution path, or tool-capable LLM call exists in the `doc-reviews` package. Setting `max_tool_turns = 5` in `doc-review.local.toml` therefore has no effect. This change implements ADR Phase II so that P3 reviewers can investigate within the document under review.

## What Changes

- **New document-intrinsic tool registry** (`ReviewTool` per DR10a): the 9 core tools — `search_entities`, `get_entity`, `get_entity_relations`, `search_metrics`, `get_metric`, `search_provisions`, `get_provision`, `get_chunk_summary`, `get_chunk_lines` — each scoped to a single `input_record_id` (the document under review). No cross-document/P5 tools in this change.
- **New managed conversation loop** `runToolUseReview` (DR10b): assemble system + user + tool defs → call the model with tools → execute requested tool calls → append results → repeat until findings or `MaxToolTurns` is exhausted (then force-finalize). Bounded by `MaxToolTurns` and a token budget (DR10c); honors the existing stop signal at each LLM-call boundary.
- **New tool-capable reviewer LLM client builder** that resolves a model ref to a `github.com/chendingplano/shared/go/api/llm` `Client` (the existing `Complete(ctx, Request{Tools,...})` path). The shared package already supports OpenAI-compatible function calling, so no HTTP/serialization layer is built here.
- **Plumb `MaxToolTurns` + `Tools`** from the resolved reviewer config (`doc-review.local.toml`) into each reviewer's runtime `ReviewerConfig`, and branch in the reviewer: `MaxToolTurns == 0` → existing one-shot path (unchanged); `> 0` → tool-use loop.
- **Wire `evidence_rationale` (P3) as the proving-ground reviewer** for the tool-use path; the framework remains reusable by the other P3/P4/P5 reviewers without per-reviewer changes to the loop.
- **Capture DeepSeek prompt-cache usage** (`prompt_cache_hit_tokens`/`prompt_cache_miss_tokens`) already surfaced by the shared client's `Usage`, logged per call (DR8a measurement groundwork).

Non-goals (unchanged, out of scope): cross-document P5 tools (`search_reference_docs`, etc.), reference-document retrieval (DR4), per-review-run TOML overrides, and the request-level `model_overrides` JSONB application.

## ADDED Requirements

### Requirement: Document-intrinsic review tool registry

The system SHALL provide a `ReviewTool` registry exposing the nine document-intrinsic core tools — `search_entities`, `get_entity`, `get_entity_relations`, `search_metrics`, `get_metric`, `search_provisions`, `get_provision`, `get_chunk_summary`, and `get_chunk_lines` — and every tool SHALL query only artifacts belonging to the `input_record_id` of the document under review. Each tool SHALL declare a valid JSON-Schema parameter definition and a typed execute function. The registry MUST NOT expose any cross-document or reference-standard (P5) tool.

#### Scenario: Registry built for a record exposes the nine core tools

- **WHEN** the tool registry is built for a given `input_record_id`
- **THEN** exactly the nine named core tools are available, each with a valid JSON-Schema parameter definition, and no cross-document tool is present

#### Scenario: A tool only returns artifacts from the document under review

- **WHEN** `search_entities` (or any core tool) is executed for record A with a query that also matches artifacts in record B
- **THEN** only artifacts whose `input_record_id` equals record A are returned

#### Scenario: Reviewer requests a subset of tools

- **WHEN** a reviewer's config lists a subset of tool names in `Tools`
- **THEN** only that subset is bound for the run, and an empty `Tools` list binds all nine core tools

### Requirement: Managed tool-use conversation loop

The system SHALL provide a bounded `runToolUseReview` conversation loop that assembles a system message and a user message (with the canonical document input placed before the reviewer task per the DeepSeek prefix-cache layout), calls the model with the bound tool definitions, executes any tool calls the model requests, appends their results to the conversation, and repeats until the model returns findings or the turn budget is exhausted. The loop SHALL be driven by a tool-capable LLM client built over the shared `llm.Client.Complete` path. A single model response SHALL be treated as either findings or tool calls, never both.

#### Scenario: Model investigates then returns findings within budget

- **WHEN** the model responds with one or more tool calls and then, on a later turn, responds with findings JSON and no tool calls
- **THEN** the loop executes each tool call, feeds the results back, and returns the normalized findings from the final response

#### Scenario: Turn budget exhausted

- **WHEN** the model has not produced findings after `MaxToolTurns` turns
- **THEN** the loop appends a force-produce instruction, makes one final call without tools, and returns the findings produced from the evidence collected so far without losing partial findings

#### Scenario: Token budget exhausted

- **WHEN** cumulative tool-result token cost reaches `MaxToolTokens` before the turn cap
- **THEN** the loop stops issuing tool calls and force-finalizes findings

#### Scenario: Malformed tool call

- **WHEN** the model emits a tool call whose arguments do not satisfy the tool's JSON Schema
- **THEN** the loop returns a tool-role error result for that call to the model instead of aborting the window, allowing a retry within the remaining budget

#### Scenario: Stop requested mid-investigation

- **WHEN** a pipeline stop is signalled at an LLM-call boundary during the loop
- **THEN** the loop returns the findings collected so far together with the pipeline-stopped error

### Requirement: Config-driven one-shot versus tool-use execution

The system SHALL plumb `MaxToolTurns` and `Tools` from the reviewer's resolved `doc-review.local.toml` configuration into the runtime reviewer configuration, and each tool-capable reviewer SHALL select its execution path from `MaxToolTurns`: a value of `0` runs the existing one-shot path unchanged, and a value greater than `0` runs the tool-use loop. When `MaxToolTurns` is `0` the reviewer's behavior and output SHALL be identical to the prior one-shot implementation.

#### Scenario: max_tool_turns set to zero preserves one-shot behavior

- **WHEN** a reviewer is configured with `max_tool_turns = 0`
- **THEN** it makes a single one-shot extraction call per window and produces the same findings shape as before this change

#### Scenario: max_tool_turns greater than zero activates tool use

- **WHEN** a reviewer is configured with `max_tool_turns = 5` and a tool-capable client resolves
- **THEN** the reviewer runs the tool-use loop with the bound core tools for that window

#### Scenario: Tool path unavailable falls back to one-shot

- **WHEN** `max_tool_turns > 0` but no tool-capable LLM client could be resolved for the reviewer
- **THEN** the reviewer falls back to the one-shot path rather than failing the review

#### Scenario: Token budget is config-overridable

- **WHEN** a reviewer (or its group default) sets `max_tool_tokens` in configuration
- **THEN** the loop enforces that configured cap, and when the field is unset the code-level default for the group applies

### Requirement: evidence_rationale reviewer runs through the tool-use path

The `evidence_rationale` (P3) reviewer SHALL support the tool-use execution path as the proving-ground reviewer, producing findings with `pass = "P3"` and `aspect = "evidence_rationale"` regardless of which execution path is taken.

#### Scenario: evidence_rationale produces correctly tagged findings via tool use

- **WHEN** `evidence_rationale` runs with `max_tool_turns > 0` and the loop finalizes findings
- **THEN** each returned finding is tagged `pass = "P3"` and `aspect = "evidence_rationale"`, matching the one-shot path's tagging

### Requirement: Prompt-cache usage capture

The tool-use loop SHALL record the DeepSeek prompt-cache usage fields (`prompt_cache_hit_tokens` and `prompt_cache_miss_tokens`) reported by the shared client for each model call.

#### Scenario: Cache usage logged per call

- **WHEN** a model call in the loop returns usage including prompt-cache hit and miss token counts
- **THEN** those counts are logged for that call

## Capabilities

### New Capabilities
- `doc-review-tool-use`: the P3 tool-use execution path — the `ReviewTool` registry of document-intrinsic core tools, the bounded `runToolUseReview` conversation loop with budget and stop handling, the tool-capable reviewer LLM client, and the config-driven one-shot-vs-tool-use branch applied to `evidence_rationale`.

### Modified Capabilities
<!-- None: no prior OpenSpec specs exist for the doc-review framework. -->

## Impact

- **Code (new):** `server/api/doc-reviews/review-tools.go` (registry + 9 core tools), `server/api/doc-reviews/review-tool-loop.go` (`runToolUseReview`), tool-capable client builder (in `review_exports.go` / `review_framework_aliases.go` or a new `review-tool-client.go`).
- **Code (modified):** `server/api/doc-reviews/review-document.go` (plumb `MaxToolTurns`/`Tools` into `ReviewerConfig`, branch in `evidenceRationaleReviewer`), `server/api/doc-processing/review_exports.go` (export a tool-capable client builder over `shared/go/api/llm`).
- **Config:** `doc-review.local.toml` — `[reviewers.evidence_rationale]` (and P3 package default) `max_tool_turns` becomes operative; a new config-overridable `max_tool_tokens` (per reviewer and per group default, code default when unset); an optional `tools` list per reviewer.
- **Dependencies:** reuses `github.com/chendingplano/shared/go/api/llm` (`NewClient`, `Client.Complete`, `Request.Tools`, `Response.ToolCalls`, `Usage.PromptCacheHit/MissTokens`) and the existing `kb.entities` / `kb.metrics` / `kb.provisions` / `kb.summaries` / chunk stores for tool backing. No schema migrations.
- **Cost/behavior:** P3 reviewers with `max_tool_turns > 0` make multiple model calls per window (bounded by the turn/token budget) on a stronger model (`deepseek-v4-pro`), increasing per-review cost; one-shot reviewers are unaffected.
- **Docs:** ADR 2026061801 change log + Implementation Files; doc-review spec 2026062104.

## Design
Refer to [2]

## Implementation
Refer to [3] — full implementation file listing, architecture overview, key source highlights, and test inventory.

## References
[1] `doc-repo/adrs/202606/2026061801-adr-document-review.md` — ADR (DR10/DR10a/DR10b/DR10c)

[2] `doc-repo/design/202606/2026062502-design-tool-use-reviewers.md` — Design with 8 decisions (D1–D8)

[3] `doc-repo/impl/202606/2026062504-impl-tool-use-reviewers.md` — Implementation document