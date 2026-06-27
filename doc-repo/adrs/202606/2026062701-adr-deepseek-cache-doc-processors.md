# ADR: DeepSeek Prompt Cache for Doc Processors

Date: 2026-06-27

Status: Implemented (Phases 1–3 landed)

Extends: 2026062501-adr-deepseek-cache (DeepSeek Prompt Cache for Document Reviewers)

## Context

ADR 2026062501 optimized the **document reviewers** for DeepSeek prompt caching
(document-first prompt layout, cache-locality scheduling, and cache-token telemetry in
`llm_usage_event`). The **doc processors** (the doc-processing pipeline in
`ChenWeb/server/api/doc-processing/`) were not covered, even though they are all configured
with DeepSeek and many of them consume the *same* chunk/block input of a document.

Two gaps:

1. Doc-processor LLM prompts were **task-first**: `newLLMJSONInput` never set the shared
   client's `DocumentFirst` flag, so the repeated chunk text was a suffix, not a cacheable
   prefix.
2. Doc-processor logs (`kb.doc_proc_logs`) did not record provider prompt-cache counters, so
   cache effectiveness could not be measured.

A third, larger gap is scheduling: Phase B runs one goroutine per processor, each looping
its own chunks, so identical chunk prefixes from different processors are scattered in time
(the anti-pattern ADR 2026062501 warns against).

## Decision

Apply the same cache principles to the doc processors, delivered in phases.

### Phase 1 — Cache-token telemetry (landed)

- Added nullable columns `prompt_cache_hit_tokens` / `prompt_cache_miss_tokens` to
  `kb.doc_proc_logs` (migration `20260627000001_add_doc_proc_logs_cache_tokens.sql`).
- `DocProcLogRecord` / `DocProcLogRow` carry the two counts; the INSERT and
  `ListDocProcLogs` SELECT/scan handle them.
- `extractorCacheTokens` (`cache_log.go`) reads the LLM client's `LastJSONUsage()`
  (`PromptCacheHitTokens` / `PromptCacheMissTokens`) and is stamped onto each `llm_call`-type
  log entry across the processors (metrics, semantic projections, structured knowledge,
  entity-relation, inventory items, products, doc metadata, scene blocks, provisions,
  summaries/topics, category enrichment).
- Limitation: counters are read from per-client last-call state immediately after the call in
  the same goroutine; under concurrent chunk fan-out this is best-effort attribution (same
  approximation the doc reviewers accept). Aggregate per-record sums remain meaningful.

### Phase 2 — Document-first prompt layout (landed)

- `newLLMJSONInput` sets `DocumentFirst = true`, so every doc-processor LLM call uses the
  document-first envelope.
- The shared `buildMessages` document-first branch was generalized to workload-neutral
  wording (system: "You are a document processing engine. Return strict JSON only."; tags
  `<DOCUMENT_INPUT>` / `<TASK>`) so one envelope serves both reviewers and processors. This
  causes a one-time prompt-cache reset for the document reviewers, then a stable prefix again.

### Phase 2.3 — Canonical chunk InputText (landed)

Each chunk-based processor now builds `InputText` via the single helper
`canonicalChunkInputText(chunk.Lines, docCtx)` = `wrapLinesWithDocContext(markedLinesToJSON,
docCtx)` (`input_lines.go`), with all schema/label/index text moved to the prompt (`<TASK>`).
Since every chunk processor loads the same `.chunks` artifact and record, the same chunk now
yields a byte-identical `InputText` across processors, so DeepSeek can reuse the prefix.

Converged: `extract_semantic_projections` (pass 1 + pass 2 — pass 2 reuses pass 1's chunk
prefix), `extract_entity_relation` (entities + freeform relations), `extract_inventory_items`,
`extract_provisions` chunk mode. Removed the divergent per-processor serializers
(`buildChunkRelationInputJSON`, inline schema builders) at these sites.

**Structural finding (key):** the input *unit* differs by processor. `extract_metrics`
re-buckets chunks into `Block`s (`chunksToBlocks` → `blockLinesToJSON`) and `extract_provisions`
blocks mode uses `Block`s, so they cannot share a prefix with the chunk processors until their
unit is unified — a separate, extraction-affecting change, intentionally deferred. Also,
`create_artifact_category` was switched to task-first (its prompt template is the stable
prefix, not the per-call key).

### Phase 3 — InputText sequencer for cache-locality adjacency (landed)

With Phase 2.3 the chunk processors share a byte-identical prefix, but they fan out
concurrently from Phase B, so identical prefixes are not guaranteed to be temporally adjacent.
Phase 3 forces adjacency with a low-cost approach that requires no per-processor refactoring:

A shared `inputTextSequencer` (`shared/go/api/llm/openai_sequencer.go`, patterned on
`llmCallController`) serialises LLM calls that share the same `InputText` key (i.e. the same
canonical chunk). When `DocumentFirst=true`, right before the HTTP call in
`extractTextWithFormat`, the call acquires a per-InputText binary semaphore and releases it
after the response. Calls with different InputText values proceed concurrently; calls with
the same value queue, so the same chunk prefix arrives at DeepSeek back-to-back → cache hit.

Controlled by env `LLM_INPUT_TEXT_SEQUENCER` (default `"true"`; set to `"false"` to disable).
Zero per-processor refactoring — the sequencer is transparent to each processor's multi-pass
logic, status writes, stop handling, and indexing.

## Consequences

- Phases 1–2 give immediate document-first prompts for all processors and the telemetry to
  measure cache hit rate before investing in Phase 3.
- Phase 3 is a per-processor refactor of bespoke multi-pass flows; the opt-in interface +
  env flag keep it reversible and let non-participants ship unchanged.

## Verification

- `shared/go`: `go test -count=1 ./api/llm`.
- `ChenWeb`: `go build ./server/api/doc-processing/`; `go test ./server/api/doc-processing/`
  shows no regressions vs the pre-change baseline (the package has known pre-existing
  expectation-drift failures, see ADR 2026062501 "Verification").
- Operational: apply the migration, run a real doc-processing job against DeepSeek, and
  inspect `prompt_cache_hit_tokens` / `prompt_cache_miss_tokens` in `kb.doc_proc_logs`.
