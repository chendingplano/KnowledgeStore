# Design: DeepSeek Cache Algorithm Change

Date: 2026-06-27; updated 2026-07-02

Status: **Implemented.** The algorithm described in §2.2 was superseded during
implementation; the as-built algorithm is documented in §2.3 (and cross-referenced
from [ADR 2026062701](KnowledgeStore/doc-repo/adrs/202606/2026062701-adr-deepseek-cache-doc-processors.md) §"Implemented algorithm").

Extends: [ADR 2026062701 — DeepSeek Prompt Cache for Doc Processors](../../KnowledgeStore/doc-repo/adrs/202606/2026062701-adr-deepseek-cache-doc-processors.md)

## 1. Problem

Two issues with the current doc-processing pipeline:

### 1.1 Documents launched sequentially

`HandleStartDocProcessingEvent` calls `handleEvent` synchronously for each record.
When scheduling N documents, document N waits for documents 1..N-1 to complete
their full pipelines before starting — no concurrency at the document level.

### 1.2 Stagger applied between every LLM call

The per-chunk batching coordinator (`runProcessorsChunkBatched`) applies
`LLM_CALL_STAGGER` between every pair of processor calls:

```
chunk 0: proc[0] → stagger → proc[1] → stagger → proc[2]
chunk 1: proc[0] → stagger → proc[1] → stagger → proc[2]
...
```

This is conservative but wasteful: only the first processor per chunk needs the
stagger to seed the cache. All subsequent processors for the same chunk benefit
from the same cached prefix and can run concurrently.

## 2. Changes

### 2.1 Parallel document launch in HandleStartDocProcessingEvent

Launch each record's processing as a goroutine, respecting
`MaxDocProcessPipelines` via the existing semaphore mechanism.

- Each goroutine acquires a pipeline slot before calling `handleEvent`
- Slot acquisition uses `context.WithoutCancel` so waiting goroutines don't
  time out — they wait as long as needed for a slot to free up
- First error is collected via mutex; subsequent errors are logged but only
  the first is returned
- All goroutines are joined via WaitGroup before returning

### 2.2 Two-phase per-chunk batching (original design — superseded)

The original design split the per-chunk batching loop into three phases:

```
Phase 1:  for each chunk:
              batchProcessors[0].ProcessChunk(chunk)    // seeds cache, SEQUENTIAL

Phase 2:  wait LLM_CALL_STAGGER seconds                  // persist cache

Phase 3:  for each chunk, for each processor[1..N]:
              go batchProcessors[pi].ProcessChunk(chunk) // all benefit from cache
          WaitGroup.Wait()
```

This had two weaknesses discovered during implementation:

1. **Sequential seed phase:** Phase 1 processed the seed processor's chunks
   one-at-a-time in a `for` loop — an unnecessary N× serial bottleneck (chunks
   have distinct prefixes, so there is no cross-chunk cache benefit to serializing
   them).
2. **Processor-major goroutine spawn in Phase 3:** spawning goroutines with the
   processor loop as the outer loop lets the first non-seed processor's goroutines
   consume all semaphore slots, starving later processors and serializing the
   effective execution per-processor.

These were both corrected in §2.3 below.

### 2.3 As-built three-phase algorithm (implemented 2026-07-02)

> **File:** `ChenWeb/server/api/doc-processing/chunk_batch_coordinator.go` —
> `scheduleChunkBatch()`.

The doc-processing coordinator uses the **same three-phase, task-based schedule as
the doc reviewers** (`review_cache_scheduler.go`::`runReviewTasksForPromptCache`).

```
Phase 1 (seed, CONCURRENT):  for each chunk:
                              go batchProcessors[0].ProcessChunk(chunk)
                             // do NOT wait — seeds keep running

Phase 2 (stagger):           wait LLM_CALL_STAGGER seconds (single wait; skipped
                             when only one batch processor)

Phase 3 (remainder, CONCURRENT):
                             // Chunk-major spawn order (chunks outer, processors
                             // inner) so goroutines from different processors
                             // interleave:
                             for each chunk:
                               for each processor[1..N]:
                                 go batchProcessors[pi].ProcessChunk(chunk)
                             bounded by MAX_DOC_PROCESSOR_TASKS semaphore

[join all goroutines] → FinalizeChunkBatch on every batch processor (save/index)
```

Key design decisions in this algorithm:

- **Seed selection:** the seed is ordered first by `orderBatchProcessorsSeedFirst`,
  which picks a **single-pass** processor (not a 2-pass processor — a 2-pass
  seed would plant the prefix with two LLM calls, defeating cache reuse). The
  set `multiPassProcessors = {extract_metrics, extract_semantic_projections}`
  drives selection.
- **Seed is concurrent, not sequential:** chunks have distinct prefixes, so
  serializing the seed's calls provides no cache benefit and is pure latency cost.
- **Chunk-major Phase 3 spawn order:** spawning goroutines with the chunk loop
  as the outer loop distributes semaphore slots across processors, so calls from
  different processors that share the same chunk prefix arrive at DeepSeek close
  together. A processor-major order would let one processor hog all slots,
  serializing execution per-processor and evicting cached prefixes before later
  processors use them.
- **Phase 3 is semaphore-bounded** by `MAX_DOC_PROCESSOR_TASKS` (new env var,
  default 10 — mirrors the reviewers' `MAX_DOC_REVIEWER_TASKS`). Without a cap,
  `(M-1)×N` concurrent LLM calls could overwhelm rate limits.
- **Per-unit fallback:** `partitionBatchProcessors()` splits Phase B into
  batch-capable (`ChunkBatchProcessor`) and unsupported processors. The latter
  run legacy-concurrent alongside the batch via `runProcessorsPhaseBOnly` —
  the all-or-nothing gate from the original design is removed. When ≤1 batch-
  capable processors are present, everything runs legacy (batching yields no
  cross-processor benefit).
- **Concurrent accumulation safety:** Phase 3 calls a single processor's
  `ProcessChunk` concurrently for different chunk indices. Each processor
  guards its batch-state accumulators (slice appends, string fields) with a
  per-processor `sync.Mutex` (`batchMu`).
- **`ChunkBatchProcessor` interface** is unchanged:
  `Name() / InitChunkBatch(ctx, recordID, chunks, docCtx) / ProcessChunk(ctx, chunkIdx) / FinalizeChunkBatch(ctx)`.

Concurrency in Phase 3 is bounded by the `MAX_DOC_PROCESSOR_TASKS` semaphore,
not by the LLM client's internal rate limiter.

## 3. Files changed

| File | Change |
|---|---|
| `server/api/doc-processing/chunk_batch_coordinator.go` | `scheduleChunkBatch()` — three-phase concurrent-seed schedule; `partitionBatchProcessors()` / `runProcessorsPhaseBOnly()` — per-unit fallback |
| `server/api/doc-processing/chunk_batch.go` | `maxDocProcessorTasks()`, `multiPassProcessors`, `orderBatchProcessorsSeedFirst()` |
| `server/api/doc-processing/control.go` | `HandleStartDocProcessingEvent`: concurrent goroutine launch |
| `server/api/doc-processing/extract-provisions.go` | `ChunkBatchProcessor` implemented (1-pass) |
| `server/api/doc-processing/extract-inventory-items.go` | `ChunkBatchProcessor` implemented (1-pass) |
| `server/api/doc-processing/extract-entity-relation.go` | Core batch methods renamed (`initEntityBatch`/`processEntityChunk`/`finalizeEntityBatch`); `batchMu` mutex added |
| `server/api/doc-processing/entity-relation-split.go` | Entity-only + relation-only batch methods on the split wrappers; relation batch accumulates free-form per chunk |
| `server/api/doc-processing/extract-metrics.go` | `ChunkBatchProcessor` implemented (2-pass); `enrichMetricCandidates` extracted as shared method; `metricsPass1Result` promoted to package level |
| `server/api/doc-processing/extract-semantic-projections.go` | `ChunkBatchProcessor` implemented (2-pass); `projectChunk` extracted as shared method |

**Env vars added or changed:**

| Var | Default | Effect |
|---|---|---|
| `LLM_CALL_STAGGER` | `1` | Seconds between Phase 1 (concurrent seed) and Phase 3 (concurrent remainder). Skipped when ≤1 batch processor. |
| `MAX_DOC_PROCESSOR_TASKS` | `10` | Caps concurrent LLM calls in Phase 3 (mirrors the reviewers' `MAX_DOC_REVIEWER_TASKS`). |

## 4. Edge cases

| Case | Behavior |
|---|---|
| ≤1 processor in batch | Phase 1 runs (concurrent), Phases 2–3 skipped; no stagger, no remainder |
| 1 chunk | Phase 1 runs the seed processor on chunk 0 concurrently (one goroutine); Phase 3 runs all remainder processors on chunk 0 interleaved |
| 0 chunks | Early return (existing guard in `scheduleChunkBatch`) |
| Context cancelled during Phase 1 | Seed goroutines check `isCtxStopped` and record `ErrPipelineStopped`; `wg.Wait()` joins them |
| Context cancelled during Phase 2 (stagger) | `ctx.Done()` branch fires `wg.Wait()` for in-flight seed goroutines, then returns `ErrPipelineStopped` |
| Context cancelled during Phase 3 | Goroutines check `ctx.Done()` in `select` before semaphore acquire and in `runOne`; `wg.Wait()` collects them |
| Stagger=0 (env var) | No wait in Phase 2; Phase 3 fires immediately |
| 50 docs queued, 5 slots (`MaxDocProcessPipelines=5`) | First 5 acquire slots immediately; remaining 45 block via semaphore until slots free |

## 5. Verification

1. `go build ./server/api/doc-processing/` — compiles clean
2. `go test ./server/api/doc-processing/` — no regressions
3. Manual: schedule 10 documents via dev mode, observe concurrent execution
4. Manual: check `LLM_CALL_STAGGER=0` vs `LLM_CALL_STAGGER=5` cache hit rates
