# Design: DeepSeek Cache Algorithm Change

Date: 2026-06-27

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

### 2.2 Two-phase per-chunk batching

The per-chunk batching loop splits into three phases:

```
Phase 1:  for each chunk:
              batchProcessors[0].ProcessChunk(chunk)    // seeds cache

Phase 2:  wait LLM_CALL_STAGGER seconds                  // persist cache

Phase 3:  for each chunk, for each processor[1..N]:
              go batchProcessors[pi].ProcessChunk(chunk) // all benefit from cache
          WaitGroup.Wait()
```

Concurrency in Phase 3 is bounded by the LLM client's internal rate limiter
and the OS goroutine scheduler — no additional cap is needed.

When only 1 processor is in the batch, Phase 2 and 3 are skipped (no stagger,
no concurrency).

## 3. Files changed

| File | Change |
|---|---|
| `server/api/doc-processing/control.go` | `HandleStartDocProcessingEvent`: concurrent goroutine launch |
| `server/api/doc-processing/chunk_batch_coordinator.go` | `runProcessorsChunkBatched`: two-phase batching |

## 4. Edge cases

| Case | Behavior |
|---|---|
| 1 processor in batch | Phase 1 runs (sequential), Phases 2–3 skipped |
| 1 chunk | Phase 1 runs processor[0] on chunk 0; Phase 3 runs processors[1..N] on chunk 0 concurrently |
| 0 chunks | Early return (existing guard) |
| Context cancelled during Phase 3 | Goroutines check ctx.Done() and exit; WaitGroup collects them |
| Stagger=0 (env var) | No wait in Phase 2; processors[1..N] fire immediately |
| 50 docs queued, 5 slots | First 5 acquire slots immediately; remaining 45 block via semaphore until slots free |

## 5. Verification

1. `go build ./server/api/doc-processing/` — compiles clean
2. `go test ./server/api/doc-processing/` — no regressions
3. Manual: schedule 10 documents via dev mode, observe concurrent execution
4. Manual: check `LLM_CALL_STAGGER=0` vs `LLM_CALL_STAGGER=5` cache hit rates
