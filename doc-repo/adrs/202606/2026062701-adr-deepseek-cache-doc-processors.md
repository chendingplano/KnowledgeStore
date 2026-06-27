# ADR: DeepSeek Prompt Cache for Doc Processors

Date: 2026-06-27

Status: **Phase 4 complete; Phase 5 in progress (two-phase per-chunk batching;
parallel document launch)**

Extends: [2026062501-adr-deepseek-cache](2026062501-adr-deepseek-cache.md) (DeepSeek Prompt Cache for Document Reviewers)

## Context

ADR 2026062501 optimized the **document reviewers** for DeepSeek prompt caching
(document-first prompt layout, cache-locality scheduling, and cache-token telemetry in
`llm_usage_event`). The **doc processors** (the doc-processing pipeline in
`ChenWeb/server/api/doc-processing/`) were not covered, even though they are all configured
with DeepSeek and six of them consume the *same* chunks of a document.

Three gaps:

1. Doc-processor LLM prompts were **task-first**: `newLLMJSONInput` never set the shared
   client's `DocumentFirst` flag, so the repeated chunk text was a suffix, not a cacheable
   prefix.
2. Doc-processor logs (`kb.doc_proc_logs`) did not record provider prompt-cache counters
   (`prompt_cache_hit_tokens` / `prompt_cache_miss_tokens`), so cache effectiveness could not
   be measured.
3. Phase B runs one goroutine per processor, each looping its own chunks concurrently, so
   identical chunk prefixes from different processors are scattered in time (the anti-pattern
   ADR 2026062501 warns against).

## Decision

Apply the same cache principles to the doc processors, delivered in four phases.

---

### Phase 1 — Cache-token telemetry (landed)

> **Files:**
> - `ChenWeb/server/api/doc-processing/doc_proc_log_store.go` — `DocProcLogRecord` / `DocProcLogRow` fields, INSERT, `ListDocProcLogs` SELECT/scan.
> - `ChenWeb/server/api/doc-processing/cache_log.go` — `extractorCacheTokens` / `cacheTokenCounts` helpers.
> - `ChenWeb/project_migrations/20260627000001_add_doc_proc_logs_cache_tokens.sql` — goose migration.
> - Populated at every `llm_call` log site: `extract-metrics.go`, `extract-semantic-projections.go`, `extract-structured-knowledge.go`, `extract-entity-relation.go`, `extract-inventory-items.go`, `extract-products.go`, `extract-doc-metadata.go`, `doc-structure-analyzer.go`, `fix-size-chunking.go` (summaries/topics), `artifact_category_wiring.go`, `extract-provisions.go`, `generate-scene-blocks-processor.go`, `relation-extraction-freeform.go`.

- Added nullable `prompt_cache_hit_tokens` / `prompt_cache_miss_tokens` columns to
  `kb.doc_proc_logs` (migration `20260627000001`).
- `DocProcLogRecord` / `DocProcLogRow` carry the two counts; the INSERT and `ListDocProcLogs`
  SELECT/scan handle them.
- `extractorCacheTokens(extractor)` reads the LLM client's `LastJSONUsage()` and returns
  `(*int64, *int64)`. Stamped onto every `llm_call`-type log entry across all processors.
- `cacheTokenCounts(extractor)` is the plain-`int64` variant for structured-logger output on
  per-goroutine "end" log lines.
- Limitation: counters are read from per-client last-call state immediately after the call in
  the same goroutine; under concurrent chunk fan-out this is best-effort attribution (same
  approximation the doc reviewers accept). Aggregate per-record sums remain meaningful.

### Phase 2 — Document-first prompt layout (landed)

> **Files:**
> - `shared/go/api/llm/openai_client.go` — `buildMessages` envelope generalised.
> - `ChenWeb/server/api/doc-processing/llm_capture_input.go` — `DocumentFirst = true`.
> - `ChenWeb/server/api/doc-processing/artifact_category_wiring.go` — `DocumentFirst = false` for category creation (see below).

- `newLLMJSONInput` sets `DocumentFirst = true`, so every doc-processor LLM call uses the
  document-first envelope.
- The shared `buildMessages` document-first branch was generalized to workload-neutral
  wording (system: "You are a document processing engine. Return strict JSON only."; tags
  `<DOCUMENT_INPUT>` / `<TASK>`) so one envelope serves both reviewers and processors. This
  causes a one-time prompt-cache reset for the document reviewers, then a stable prefix again.
- **Exception — `create_artifact_category`:** category creation is intentionally
  **task-first** (`DocumentFirst = false`) because its stable repeated content is the prompt
  template, not the per-call category key (which varies).

### Phase 2.3 — Canonical chunk InputText (landed)

> **Files:**
> - `ChenWeb/server/api/doc-processing/input_lines.go` — `canonicalChunkInputText` helper.
> - Converged processors: `extract-metrics.go` (pass 1), `extract-semantic-projections.go`
>   (pass 1 + pass 2), `extract-entity-relation.go` (entities), `relation-extraction-freeform.go`
>   (relations), `extract-inventory-items.go`, `extract-provisions.go` (chunk mode only).

Each of the six chunk-consuming processors now builds `InputText` via the single helper
`canonicalChunkInputText(chunk.Lines, docCtx)` = `wrapLinesWithDocContext(markedLinesToJSON,
docCtx)`, with all schema/label/index text moved into the prompt (`<TASK>` section). Since
every chunk processor loads the same `.chunks` artifact and the same record, the same chunk
yields a byte-identical `InputText` across all processors → DeepSeek can reuse the cached
prefix.

Converged processors:

| Processor | Passes converged | Notes |
|---|---|---|
| `extract_metrics` | Pass 1 candidate | `chunksToBlocks` is 1:1; `Block` kept internally for output mapping only |
| `extract_semantic_projections` | Pass 1 candidate + Pass 2 enrich | Pass 2 reuses pass 1's chunk prefix |
| `extract_entity_relation` | Entities (Phase 1) + freeform relations | Both now use canonical helper |
| `extract_inventory_items` | Single pass | `docCtx` threaded through |
| `extract_provisions` | Chunk mode (`EXTRACT_PROVISIONS_INPUT` unset or `chunks`) | Schema + chunk index moved to prompt |

Not converged (intentionally):
- `extract_provisions` **blocks mode** (`EXTRACT_PROVISIONS_INPUT=blocks`): uses `Block`s
  with a different serialization. The blocks-mode path keeps its self-contained prompt.
- `create_artifact_category`: task-first (see Phase 2).

### Phase 3 — InputText sequencer for cache-locality adjacency (reverted)

> **Files:**
> - `shared/go/api/llm/openai_sequencer.go` — **Deleted** (reverted).
> - `shared/go/api/llm/openai_client.go` — `inputTextSequencer` acquire/release removed.

**What Phase 3 did:** The original Phase 3 added an `inputTextSequencer` (`shared/go/api/llm/openai_sequencer.go`,
keyed binary semaphore) and wired it into `extractTextWithFormat` before `httpClient.Do`.
This serialised all LLM calls sharing the same `InputText` at the HTTP-client layer,
regardless of which processor or document made the call — guaranteeing back-to-back cache
hits for the 2nd through 6th processor to touch a given chunk.

**Why it was reverted:** Real-world testing on record_id=416 showed two problems:

1. **4× slowdown in `extract_provisions`** — The sequencer at the shared-client layer is a
   blind serialisation mechanism that doesn't understand application context. When six
   processors all hit the same chunk simultaneously, they queue at the sequencer, turning
   previously concurrent LLM calls into a serial pipeline. Provisions (which has the largest
   task prompt and processes chunks sequentially with maxTasks=1) bore the brunt: per-chunk
   time went from ~95s to ~355s.

2. **Wrong abstraction layer** — Sequencing LLM calls by InputText is an **application-level
   concern** (the orchestrator knows which processors share the same chunk prefix), not a
   transport-level concern. The sequencer belongs in the doc-processing orchestration layer,
   not in the shared LLM client.

**Replaced by:** Phase 4 (per-chunk batching coordinator at the application layer).

---

### Phase 4 — Per-chunk batching coordinator (completed)

> **Files:**
> - `ChenWeb/server/api/doc-processing/chunk_batch.go` — New: `ChunkBatchProcessor` interface + `llmCallStagger()`.
> - `ChenWeb/server/api/doc-processing/chunk_batch_coordinator.go` — New: per-chunk batching coordinator.
> - `ChenWeb/server/api/doc-processing/control.go` — `runPhaseBProcessors` gateway wires the coordinator.
> - `ChenWeb/server/api/doc-processing/extract-provisions.go` — `ChunkBatchProcessor` implemented.
> - `ChenWeb/server/api/doc-processing/extract-entity-relation.go` — `ChunkBatchProcessor` implemented.
> - `ChenWeb/server/api/doc-processing/extract-inventory-items.go` — `ChunkBatchProcessor` implemented.

**Design principle:** DeepSeek's context caching is implicit (no API, no cache_id). Cache
entries are persisted on disk and reused when available; eviction is at DeepSeek's discretion.
The coordinator's job is to ensure that LLM calls with the same chunk prefix arrive **back-to-back**
at DeepSeek so the first call's cached prefix is still warm for subsequent calls.

**Execution order per document:**

```
Phase A: static_analyzer → chunking → extract_doc_metadata  (unchanged, sequential)

Phase B (coordinator, Phase 4 → Phase 5 — see below):
  1. Load shared chunks once from context buffer or artifact file.
  2. InitChunkBatch() on each processor.
  3. Phase 4 (replaced):
       For each chunk, iterate processors sequentially with stagger between every call.
     Phase 5 (current — two-phase batching):
       Phase 5.1: processor[0].ProcessChunk(chunk 0..N-1)  — sequential, seeds cache
       Phase 5.2: wait LLM_CALL_STAGGER                     — time for cache to persist
       Phase 5.3: processors[1..M].ProcessChunk(all chunks) — CONCURRENT, cache hits
  4. FinalizeChunkBatch() on each processor (save to DB, write artifacts, etc.)
```

**Stagger:** Controlled by `LLM_CALL_STAGGER` env var (seconds, default 1). The stagger
gives DeepSeek time to persist the cached prefix from one call before the next arrives.
If all six calls arrived at exactly the same instant, none would benefit from caching.

**`ChunkBatchProcessor` interface:**

```go
type ChunkBatchProcessor interface {
    Name() string
    InitChunkBatch(ctx, recordID, chunks, docCtx) error
    ProcessChunk(ctx, chunkIdx) error
    FinalizeChunkBatch(ctx) error
}
```

**Gateway:** `runPhaseBProcessors()` in `control.go` checks whether ALL Phase B processors
implement `ChunkBatchProcessor`. If yes, it uses the coordinator; if any processor doesn't,
it falls back to the legacy `runProcessorsTwoPhase` (concurrent goroutine mode).

**Env var:**

| Var | Default | Effect |
|---|---|---|
| `LLM_CALL_STAGGER` | `1` | Seconds to wait between Phase 5.1 (seed) and Phase 5.3 (concurrent remainder) |

---

### Phase 5 — Two-phase per-chunk batching & parallel document launch (in progress)

> **Files:**
> - `ChenWeb/server/api/doc-processing/chunk_batch_coordinator.go` — Two-phase batching loop.
> - `ChenWeb/server/api/doc-processing/control.go` — `HandleStartDocProcessingEvent` parallel launch + `runPhaseBProcessors` gateway wired.

**Rationale:** Phase 4's coordinate‑then‑stagger‑everywhere approach applies the
stagger between every pair of processor calls per chunk. This is conservative but
wasteful: only the first processor per chunk needs the stagger to seed the DeepSeek
cache. All subsequent processors for the same chunk share the same cached prefix
and can run concurrently.

The old per‑chunk batching algorithm (Phase 4) was:

```
for each chunk 0..N-1:
    for each processor 0..M-1:
        P.ProcessChunk(chunk)  →  stagger →  ...
```

Replaced by the **two‑phase** algorithm:

```
Phase 5.1:  processor[0].ProcessChunk(chunk 0..N-1)   // sequential, seeds cache
Phase 5.2:  wait LLM_CALL_STAGGER                        // time for cache to persist
Phase 5.3:  processors[1..M].ProcessChunk(all chunks)   // CONCURRENT, cache hits
```

**Stagger semantics:** The `LLM_CALL_STAGGER` env var now controls the single
delay between Phase 5.1 (seed) and Phase 5.3 (concurrent remainder), not between
every pair of calls. When only one processor is in the batch, Phases 5.2–5.3 are
skipped entirely.

**Parallel document launch:** `HandleStartDocProcessingEvent` previously processed
records sequentially — document N waited for document N‑1's full pipeline to complete.
It now launches each document's pipeline as a goroutine, limited by the existing
`MaxDocProcessPipelines` semaphore (default 10). Slot acquisition uses
`context.WithoutCancel` so goroutines waiting for a slot don't time out when the
caller context has a short deadline.

**Env var update:**

| Var | Default | Effect (updated) |
|---|---|---|
| `LLM_CALL_STAGGER` | `1` | Seconds between Phase 5.1 (cache seed) and Phase 5.3 (concurrent remainder of the same chunk batch) |

---

## ChunkBatchProcessor implementation status

| Processor | Status | Notes |
|---|---|---|
| `extract_provisions` | ✅ Done | `ProcessChunk` = LLM call + normalise; `FinalizeBatch` = save, index tree, write artifact, reindex search |
| `extract_entity_relation` | ✅ Done | `ProcessChunk` = Phase 1 entity extraction; `FinalizeBatch` = consolidate + Phase 2 relation windows + save all |
| `extract_inventory_items` | ✅ Done | `ProcessChunk` = LLM call; `FinalizeBatch` = save |
| `extract_metrics` | ❌ Pending | Has local `pass1Result`/`pass2Result` types inside `extractMetricsFromChunksWithLLM` that need to be moved to package level before the batch methods can reference them. Also has PostProcessIndex (Phase C). |
| `extract_semantic_projections` | ❌ Pending | 2-pass architecture (candidates + enrich). Both passes share the same chunk prefix. The batch path needs to call both passes within `ProcessChunk` for each chunk index. |
| `extract_products` | ❌ Pending | Not yet assessed for chunk-based batching. |

Until all processors implement `ChunkBatchProcessor`, the `runPhaseBProcessors` gateway falls
back to legacy concurrent mode for the entire Phase B batch. Implementing the remaining
processors activates the coordinator.

---

## Known issues from record_id=416

From a side-by-side comparison of Phase 2 (no sequencer, old prompt format) vs Phase 3
(with sequencer + all cache changes) on the same 10-chunk document:

1. **Provisions slowdown confirmed.** Phase 3 per-chunk times range from 149–355s vs Phase 2
   at 9–95s. The delta grows roughly linearly — signature of cross-processor sequencer queuing.

2. **Cache hit rate varies by processor prompt size.** Entities show ~96% hit rate (task prompt
   ~96 tokens), while provisions show ~33% (task prompt ~1500 tokens with large JSON schema).
   The shared prefix (~2400 tokens) is identically cached for all processors; the difference
   is in the uncacheable task-specific suffix.

3. **`ExtractStructuredJSON` retries modify InputText.** On schema validation failure the
   retry appends instructions to `InputText` ([structured_output.go:30](shared/go/api/llm/structured_output.go#L30)),
   which changes the sequencer key. This means retries get zero cache benefit from the original
   call's prefix. With the sequencer removed this is no longer a concern.

4. **Minor bug: entity-relation cache counter always reads from primary extractor.**
   `cacheTokenCounts(p.Extractor)` at [extract-entity-relation.go:588](ChenWeb/server/api/doc-processing/extract-entity-relation.go#L588)
   doesn't account for fallback model usage, unlike provisions which correctly uses
   `p.callExtractor(usedFallback)` ([extract-provisions.go:285](ChenWeb/server/api/doc-processing/extract-provisions.go#L285)).

---

## Remaining work (hand-off notes)

### Phase 4 — Still pending ChunkBatchProcessor implementations

### 1. Implement `ChunkBatchProcessor` on `extract_metrics`

File: `ChenWeb/server/api/doc-processing/extract-metrics.go`

**Challenge:** `pass1Result` and `pass2Result` types are defined locally inside
`extractMetricsFromChunksWithLLM` (lines 690 and 813). The batch methods need to accumulate
per-chunk results and pass them to the enrichment pass, but cannot reference these local types.

**Approach:**
- Move `pass1Result` and `pass2Result` to package-level types (or define equivalent batch
  accumulator types).
- `ProcessChunk` runs Pass 1 (candidate extraction) for one chunk.
- `FinalizeBatch` runs Pass 2 (enrichment) on accumulated candidates, then saves.
- Note: metrics indexing runs in Phase C via `PostProcessIndex` — `FinalizeBatch` only needs
  to save to `kb.metrics` and write the `.metrics` artifact file.

### 2. Implement `ChunkBatchProcessor` on `extract_semantic_projections`

File: `ChenWeb/server/api/doc-processing/extract-semantic-projections.go`

**Challenge:** 2-pass architecture (candidates + enrich). Both passes use
`canonicalChunkInputText` (shared prefix). Pass 2 processes candidates from Pass 1.

**Approach:**
- `ProcessChunk` runs Pass 1 (candidate extraction) and immediately runs Pass 2 (enrich)
  on the same chunk's candidates — both within a single `ProcessChunk` call. The user noted:
  "for doc processors with two phases, we cross our fingers for the caches not being evicted"
  between the two calls within the same chunk-processor pairing.
- `FinalizeBatch` saves all accumulated projection results.

### 3. Implement `ChunkBatchProcessor` on `extract_products`

File: `ChenWeb/server/api/doc-processing/extract-products.go`

**Challenge:** Needs assessment — may not be chunk-based (no `canonicalChunkInputText` usage).

### 4. Adding more processors to the batch

When adding a new processor that works on chunks, have it implement `ChunkBatchProcessor`.
The coordinator will pick it up automatically.

### Phase 5 — Algorithm change related

### 5. Consider removing the `RunDocProcessorConcurrentFromEnv` env var

The per-chunk batching coordinator replaces the two-phase concurrent goroutine approach.
The `RUN_DOC_PROCESSOR_CONCURRENT` env var and the sequential fallback
(`runProcessorsSequential`) can eventually be removed once the migration is complete.

### 6. Verify Phase 5.3 concurrency does not overwhelm rate limits

Phase 5.3 launches `(M-1) × N` concurrent LLM calls (remaining processors × chunks).
Monitor the LLM client's rate limiter and add a semaphore within Phase 5.3 if
necessary to cap concurrent calls.

### 7. Update the ADR execution-order diagram

The pseudo-code at the top of this ADR shows the Phase 4 algorithm. Once Phase 5
is stable, replace it with the two-phase diagram.

---

## Operational checklist

1. **Apply migration** `20260627000001_add_doc_proc_logs_cache_tokens.sql` to the target
   database (adds `prompt_cache_hit_tokens` / `prompt_cache_miss_tokens` to `kb.doc_proc_logs`).

2. **Run a doc-processing job** against real DeepSeek. Publish to
   `kb.pdf.start-doc-processing` with `{ "record_id": "<id>", "force": true }` on a record
   that is already parsed and chunked. Use the full configured pipeline (omit `operation` so
   all processors run).

3. **Inspect cache counters** in `kb.doc_proc_logs`:
   ```sql
   SELECT doc_proc_name, activity_name,
          prompt_cache_hit_tokens, prompt_cache_miss_tokens, ms_used, create_time
   FROM kb.doc_proc_logs
   WHERE record_id = <id>
     AND prompt_cache_hit_tokens IS NOT NULL
   ORDER BY create_time;
   ```
   Expected: first pass on a chunk shows mostly `miss` tokens; subsequent passes/processors on
   the same chunk show climbing `hit` tokens.

4. **To A/B test the coordinator:** run the same record with `LLM_CALL_STAGGER=0`
   (no stagger) vs `LLM_CALL_STAGGER=5` and compare cache hit rates and wall-clock time.

## File index (updated)

| Repo | File | Phase | Change |
|---|---|---|---|
| shared | `go/api/llm/openai_client.go` | 2, 3 (reverted) | Generalised `buildMessages` envelope; **removed** `inputTextSequencer` |
| shared | `go/api/llm/openai_sequencer.go` | 3 | **Deleted** (reverted) |
| ChenWeb | `project_migrations/20260627000001_add_doc_proc_logs_cache_tokens.sql` | 1 | New migration |
| ChenWeb | `server/api/doc-processing/cache_log.go` | 1 | New: `extractorCacheTokens` / `cacheTokenCounts` |
| ChenWeb | `server/api/doc-processing/doc_proc_log_store.go` | 1 | Added cache columns to structs + INSERT + scan |
| ChenWeb | `server/api/doc-processing/llm_capture_input.go` | 2 | `DocumentFirst = true` |
| ChenWeb | `server/api/doc-processing/input_lines.go` | 2.3 | New: `canonicalChunkInputText` |
| ChenWeb | `server/api/doc-processing/artifact_category_wiring.go` | 2 | `DocumentFirst = false` (task-first for categories) |
| ChenWeb | `server/api/doc-processing/chunk_batch.go` | 4 | **New:** `ChunkBatchProcessor` interface + `llmCallStagger()` |
| ChenWeb | `server/api/doc-processing/chunk_batch_coordinator.go` | 4, 5 | **New:** per-chunk batching coordinator (Phase 4); two-phase batching (Phase 5) |
| ChenWeb | `server/api/doc-processing/control.go` | 4, 5 | `runPhaseBProcessors` gateway; `HandleStartDocProcessingEvent` parallel launch (Phase 5) |
| ChenWeb | `server/api/doc-processing/extract-provisions.go` | 4 | `ChunkBatchProcessor` | |
| ChenWeb | `server/api/doc-processing/extract-entity-relation.go` | 4 | `ChunkBatchProcessor` (incl. Phase 2 relations in FinalizeBatch) |
| ChenWeb | `server/api/doc-processing/extract-inventory-items.go` | 4 | `ChunkBatchProcessor` |
| ChenWeb | `server/api/doc-processing/extract-metrics.go` | 1, 2.3 | Cache log; canonical InputText + `metricCandidateTask` |
| ChenWeb | `server/api/doc-processing/extract-semantic-projections.go` | 1, 2.3 | Cache log; canonical InputText; `semanticProjectionCandidateTask` / `semanticProjectionEnrichTask` |
| ChenWeb | `server/api/doc-processing/extract-entity-relation.go` | 1, 2.3 | Cache log; canonical helper |
| ChenWeb | `server/api/doc-processing/relation-extraction-freeform.go` | 1, 2.3 | Cache log; canonical helper |
| ChenWeb | `server/api/doc-processing/extract-inventory-items.go` | 1, 2.3 | Cache log; canonical InputText + docCtx |
| ChenWeb | `server/api/doc-processing/extract-provisions.go` | 1, 2.3 | Cache log; canonical InputText (chunk mode) + `provisionChunkTask` |
| ChenWeb | `server/api/doc-processing/extract-structured-knowledge.go` | 1 | Cache log |
| ChenWeb | `server/api/doc-processing/extract-products.go` | 1 | Cache log |
| ChenWeb | `server/api/doc-processing/extract-doc-metadata.go` | 1 | Cache log |
| ChenWeb | `server/api/doc-processing/doc-structure-analyzer.go` | 1 | Cache log |
| ChenWeb | `server/api/doc-processing/fix-size-chunking.go` | 1 | Cache log + `callExtractor` |
| ChenWeb | `server/api/doc-processing/generate-scene-blocks-processor.go` | 1 | Cache log |
| ChenWeb | `server/api/doc-processing/generate_summary_logging_test.go` | 1 | Updated sqlmock expectations |
| ChenWeb | `server/api/doc-processing/semantic-chunking_test.go` | 1 | Updated sqlmock expectations |
| ChenWeb | `server/api/doc-processing/*_test.go` | 1, 2.3 | Updated test call sites |
| KnowledgeStore | `doc-repo/adrs/202606/2026062701-adr-deepseek-cache-doc-processors.md` | — | This document |
| KnowledgeStore | `Capsules/coding-capsules/doc-processor/+CAPSULE.md` | — | Updated §6.2 |

## Verification

- `shared/go: go test -count=1 ./api/llm` — passes.
- `ChenWeb: go build ./server/api/doc-processing/` — clean; `go test ./server/api/doc-processing/`
  shows zero net-new failures vs the pre-change baseline (the package has known pre-existing
  expectation-drift failures, see ADR 2026062501 "Verification").
- `go vet ./...` clean on both packages.

## Consequences

- All six chunk-consuming doc processors share a byte-identical, cacheable DeepSeek prefix.
- The old Phase 3 `inputTextSequencer` (at the shared HTTP-client layer) has been removed
  and replaced by the Phase 4 per-chunk batching coordinator at the application layer.
- Phase 5 changes the coordinator to a **two-phase** algorithm: the first processor seeds
  the cache sequentially across all chunks, then all remaining processors run concurrently
  after a single `LLM_CALL_STAGGER` delay. This replaces the previous per-call stagger.
- Phase 5 also launches document pipelines concurrently via goroutines, limited by
  `MaxDocProcessPipelines` (default 10), replacing the previous sequential loop in
  `HandleStartDocProcessingEvent`.
- The coordinator is not yet fully active: it only kicks in when ALL Phase B processors
  implement `ChunkBatchProcessor`. Three processors are now implemented
  (provisions, entity_relation, inventory_items); three remain (metrics,
  semantic_projections, products).
- `LLM_CALL_STAGGER` controls the single delay between Phase 5.1 (cache seed) and
  Phase 5.3 (concurrent remainder) — formerly it controlled the delay between every
  pair of processor calls (default 1s).
- The `LLM_INPUT_TEXT_SEQUENCER` env var is now unused (the old sequencer is gone).

