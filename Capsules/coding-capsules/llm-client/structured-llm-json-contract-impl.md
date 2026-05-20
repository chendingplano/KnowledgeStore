# Structured LLM JSON Contract Implementation

Date: 2026-05-23

## Scope

Implemented against the design for a shared strict JSON contract in:

- `shared/go/api/llm`
- `ChenWeb/server/api/doc-processing`
- `ChenWeb/server/api/kbhandler`

This capsule records what actually shipped, how it behaves, and what compatibility choices were made during rollout.

## Shared Client Changes

Primary shared files:

- `shared/go/api/llm/openai_client.go`
- `shared/go/api/llm/types.go`
- `shared/go/api/llm/structured_output.go`
- `shared/go/api/llm/structured_output_schema.go`
- `shared/go/api/llm/structured_output_errors.go`
- `shared/go/api/llm/json_repair.go`

Primary shared tests:

- `shared/go/api/llm/openai_client_test.go`
- `shared/go/api/llm/structured_output_test.go`
- `shared/go/api/llm/structured_output_schema_test.go`
- `shared/go/api/llm/structured_output_errors_test.go`
- `shared/go/api/llm/json_repair_test.go`

### New Behavior

The shared client now exposes:

- `ExtractStructuredJSON(ctx, input, contract)`

This path:

- validates the contract
- parses provider output
- validates against JSON Schema
- performs bounded repair/retry
- returns typed failure classes

### Legacy Bridge

`ExtractJSON(...)` still exists, but now routes through the structured engine with a permissive legacy object contract.

This means even non-migrated callers gain:

- more resilient parsing
- better invalid-JSON handling
- a shared repair/retry path

It also means new code should not treat `ExtractJSON` as the preferred API.

## Schema Validation

The implementation uses JSON Schema validation in-process.

Behavior covered:

- missing required field
- wrong type
- nested object/array mismatches
- optional rejection of unexpected keys

This moved JSON shape enforcement from prompt text into code.

## Repair and Retry

The implementation includes a narrow repair layer for malformed-but-recoverable JSON.

It handles cases like:

- Markdown fences
- wrapper prose
- narrow serialization damage

It does not guess missing semantics.

If repair does not produce a valid contract-conforming payload, the client retries with feedback and then fails closed if retries are exhausted.

## ChenWeb Adoption

### Doc-Processing

Structured contracts were added and adopted in:

- topic extraction
- scene block extraction
- doc metadata extraction
- metrics extraction
- product extraction
- provision extraction
- fixed-size chunk summary generation
- doc-structure analyzer JSON fallback

Relevant helper file:

- `ChenWeb/server/api/doc-processing/llm_contracts.go`

Contract validation test:

- `ChenWeb/server/api/doc-processing/llm_contracts_test.go`

### KB Handlers

Structured contracts were added and adopted in:

- metric extraction handler
- provision extraction handler

Relevant helper file:

- `ChenWeb/server/api/kbhandler/llm_contracts.go`

Contract validation test:

- `ChenWeb/server/api/kbhandler/llm_contracts_test.go`

## Compatibility Choices Made During Rollout

### Prompt Env Alias

`TOPIC_CHUNK_PROMPT` was restored as an accepted topic-chunk prompt override alias.

Current lookup order in semantic topic chunking:

1. `TOPIC_CHUNK_PROMPT`
2. `EXTRACT_TOPIC_PROMPT`
3. `SEMANTIC_CHUNKING_PROMPT`

This was done to preserve older config and test expectations while keeping newer names working.

### Summary Graph Env Fallback

`ListSummaryGraph` now accepts:

- `ARTIFACT_WEB_DIR`
- fallback: `SUMMARY_TREE_DIR`

This keeps existing summary-graph behavior compatible with older summary-tree-based tests and setups.

### Handler Artifact Naming

The doc-structure handler now resolves corrected structure artifacts using the `.corrected` filename form instead of looking only for `.txt`.

That aligns handler behavior with the corrected-line artifact naming used elsewhere in ChenWeb.

## Static Analyzer Cleanup During Rollout

While restoring package-wide green tests, static-analyzer behavior was aligned with the existing test contract.

Key fixes:

- TOC detection became less overly conservative for short valid TOC sequences
- heading detection no longer seeds numeric heading state from image-path content
- OCR heading normalization works for legacy `heading-*` line types
- watermark removal preserves embedded watermark text inside larger content
- pages with multiple watermark-like lines no longer trigger destructive cleanup
- watermark-like paragraph lines are excluded from paragraph-merging heuristics

Files:

- `ChenWeb/server/api/doc-processing/structure-static-analyzer.go`

## Verification

The implementation was verified with:

- `cd shared/go && go test ./api/llm`
- `cd ChenWeb && go test ./server/api/doc-processing`
- `cd ChenWeb && go test ./server/api/kbhandler`

Those package-wide runs are green after the rollout and cleanup.

## What Did Not Change

No new required environment variables were introduced.

Callers still need to provide:

- prompt/model config as before
- artifact directories as before

The structured contract changes are internal API and behavior changes, not deployment-time config expansion.

## Recommended Usage Going Forward

For any new JSON-returning LLM call:

1. define a local machine-readable schema contract
2. call `ExtractStructuredJSON(...)`
3. validate behavior with a focused contract-adoption test

Do not add new prompt-only `ExtractJSON` call sites unless there is a short-lived compatibility reason.

## Takeaway

The workspace now has a real JSON contract boundary for LLM output.

The practical outcome is not "LLMs never return bad JSON."
The practical outcome is:

- malformed output is handled in one place
- schema mismatches are caught before business logic
- retries and repairs are bounded and intentional
- migrations can continue incrementally without re-solving the same problem at every call site
