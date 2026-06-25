# ADR: DeepSeek Prompt Cache for Document Reviewers

Date: 2026-06-25

Status: Implemented

## Context

Document reviewers are either per-chunk or window-level reviewers. Window-level reviewers cut document inputs into blocks before calling the LLM. When fully implemented, there will be 40+ reviewers, and they largely consume the same document/window input.

All document reviewers are configured to use `deepseek-v4-flash`. DeepSeek prompt caching is most effective when repeated requests share a stable, identical prompt prefix. Therefore, doc-review calls should put the document/window input before reviewer-specific task instructions, and the scheduler should run reviewers with the same input close together.

## Decision

The core DeepSeek cache optimization task is complete.

Implemented changes:

- Shared LLM telemetry captures provider prompt-cache counters:
  - `prompt_cache_hit_tokens`
  - `prompt_cache_miss_tokens`
- ChenWeb persists and reports those cache counters in `llm_usage_event`.
- Doc-review LLM prompts use a document-first layout so the repeated document/window text is the stable prefix.
- Doc-review execution is cache-locality aware: tasks are ordered by identical serialized input window/block before moving to the next input.

This means reviewers sharing the same 200-line window or the same document page block now run adjacent to one another, maximizing the chance that DeepSeek reuses the prompt cache.

## Verification

Focused tests passed:

- `shared/go`: `go test -count=1 ./api/llm`
- `ChenWeb`: `go test -count=1 ./server/api/llmusage ./server/api/llmreporthandler ./server/api/doc-reviews`

Broad suite status:

- `shared/go: go test -count=1 ./...` still fails in unrelated `api/parsers/pdf-parser` scan-mismatch tests.
- `ChenWeb: go test -count=1 ./server/api/...` still fails in unrelated `doc-processing` and `kbhandler` test expectation drift.

## Remaining Work

Required operational follow-through:

- Apply the `llm_usage_event` cache-token migration in the target environment.
- Run real document-review jobs against DeepSeek.
- Inspect `prompt_cache_hit_tokens` and `prompt_cache_miss_tokens` in the LLM usage logs/reports.

Non-blocking follow-ups:

- Tune reviewer window sizes using telemetry. Most reviewers share 200-line windows, grammar currently uses 100-line windows, and document-level reviewers share page blocks.
- If grammar review is a meaningful cost center, consider aligning its windowing with the other chunk reviewers to improve cache locality.
- Fix unrelated broad-test failures in `doc-processing`, `kbhandler`, and shared pdf-parser when full-suite green is needed.

## Consequences

The implementation is done, but cache effectiveness still needs production validation with real DeepSeek calls. The telemetry is now in place to measure hit rate and guide further tuning.
