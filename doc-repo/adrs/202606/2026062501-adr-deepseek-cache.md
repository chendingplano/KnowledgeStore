# ADR: DeepSeek Prompt Cache for Document Reviewers

Date: 2026-06-25

Status: Implemented

## Context

Document reviewers are either per-chunk or window-level reviewers. Window-level reviewers cut document inputs into blocks before calling the LLM. When fully implemented, there will be 40+ reviewers, and they largely consume the same document/window input.

Document reviewers are configured in `ChenWeb/doc-review.local.toml`, including the model to use and the max number of turns, among others, for each reviewer.  In the current implementation, most are configured with DeepSeek.

DeepSeek prompt caching is most effective when repeated requests share a stable, identical prompt prefix. Therefore, doc-review calls should put the document/window input before reviewer-specific task instructions, and the scheduler should run reviewers with the same input close together.

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

## Prompt Shape for Document Reviewers

The document-review prompt shape was changed from a task-first layout to a document-first layout.

Previous shape:

```text
system:
  {reviewer-specific instructions}

user:
  {document/window input}
```

That layout makes each reviewer start with a different prompt prefix, even when all reviewers are reading the same document/window. For prompt-cache purposes, this is poor locality: the repeated content appears after the reviewer-specific text.

New shape:

```text
system:
  You are a document review engine. Return strict JSON only.

user:
  <DOCUMENT_INPUT>
  {document/window input}
  </DOCUMENT_INPUT>

  <REVIEW_TASK>
  {reviewer-specific instructions}
  </REVIEW_TASK>
```

The important property is that the large repeated document/window input now appears before the reviewer-specific task. When many reviewers inspect the same window, DeepSeek can see the same stable prefix repeatedly.

This is paired with scheduler locality:

```text
window 1 + reviewer A
window 1 + reviewer B
window 1 + reviewer C
window 2 + reviewer A
window 2 + reviewer B
window 2 + reviewer C
```

Instead of:

```text
reviewer A + window 1
reviewer A + window 2
reviewer B + window 1
reviewer B + window 2
reviewer C + window 1
reviewer C + window 2
```

The first ordering keeps identical document/window prefixes adjacent in time. The second ordering lets each reviewer walk the document independently, which spreads identical prefixes apart and lowers cache hit probability.

## General Prompt Cache Principles

The same principles should be used for other LLM-bound traffic, not only document reviewers.

1. Put stable, repeated input first.

   If many calls share a large object, place that object near the beginning of the prompt. Examples include document text, extracted tables, schema definitions, ontology definitions, policy text, tool contracts, or shared context bundles.

2. Put variable task instructions after the shared prefix.

   Task-specific questions, reviewer rubrics, output preferences, and small per-call variations should come after the repeated input. This preserves the longest identical prefix.

3. Keep byte-for-byte serialization stable.

   Prompt cache effectiveness depends on exact prompt identity, not just semantic similarity. Avoid non-deterministic map ordering, changing whitespace, timestamps, random IDs, request IDs, and incidental debug text inside the cacheable prefix.

4. Use explicit tags around stable and variable regions.

   Tags such as `<DOCUMENT_INPUT>` and `<REVIEW_TASK>` make the boundary clear and reduce accidental prompt reshaping. They also make it easier to audit what is intended to be cacheable.

5. Batch and schedule by shared input.

   When many calls share the same input, run those calls close together. Prefer:

   ```text
   input A -> task 1, task 2, task 3
   input B -> task 1, task 2, task 3
   ```

   over:

   ```text
   task 1 -> input A, input B
   task 2 -> input A, input B
   task 3 -> input A, input B
   ```

6. Align windowing across related jobs when quality allows.

   Calls can only share a cache prefix when they share the same serialized input. If related jobs use different chunk sizes or different envelope formats, their prompts will not share the same prefix even if they cover similar document text.

7. Separate cacheable context from per-request telemetry.

   Metadata such as account IDs, request IDs, trace IDs, timestamps, retry counters, and logging context should not be placed in the prompt prefix. Keep those in API metadata or logs instead.

8. Measure cache results.

   Use provider-reported cache counters, especially `prompt_cache_hit_tokens` and `prompt_cache_miss_tokens`, to validate assumptions. If hit tokens remain low, inspect prompt serialization and scheduling before changing model configuration.

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
