# Extract Metrics Concurrency Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve `extract_metrics` throughput by running Pass 1 (candidate extraction) and Pass 2 (enrichment batches) concurrently, capped by `EXTRACT_METRICS_MAX_TASKS`, while preserving the existing multi-pass pipeline semantics: Pass 1 completes fully before the deterministic merge, the merge completes before Pass 2, and the final dedup runs after all Pass 2 batches finish.

**Architecture:** Keep the current four-stage shape: Pass 1 → merge → Pass 2 → dedup. Add bounded per-pass concurrency with deterministic result ordering, synchronized progress tracking, and fail-fast cancellation so output order, combined progress tracking, and status/logging behavior stay compatible with the current implementation.

**Tech Stack:** Go, goroutines, `sync`, `context`, existing doc-processing status/logging helpers, Go test

---

## File Structure

- Modify: `server/api/doc-processing/extract-metrics.go`
  Responsibility: add `MaxTasks int` field, load `EXTRACT_METRICS_MAX_TASKS`, replace sequential loops in `extractMetricsFromChunksWithLLM` with bounded concurrent workers, guard shared state, and preserve existing success/failure/status persistence behavior.

- Modify: `server/api/doc-processing/extract-metrics_test.go`
  Responsibility: verify concurrent Pass 1 and Pass 2 execution, deterministic result ordering, bounded worker usage, and fail-fast behavior.

- Optional Modify: `../KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-metrics-spec.md`
  Responsibility: document that Pass 1 chunks and Pass 2 batches may run concurrently up to `EXTRACT_METRICS_MAX_TASKS`.

## Chunk 1: Add Config And Thread-Safe Progress Tracking

### Task 1: Add the concurrency config field to the processor

**Files:**
- Modify: `server/api/doc-processing/extract-metrics.go`

- [ ] **Step 1: Add a `MaxTasks int` field to `MetricsProcessor`**

Add the field near `MetricEnrichGroupSize` so extraction-related configuration stays grouped together.

- [ ] **Step 2: Load `EXTRACT_METRICS_MAX_TASKS` in `NewMetricsProcessor`**

Use the same pattern as `METRIC_ENRICH_GROUP_SIZE`:

```go
maxTasks := envInt("EXTRACT_METRICS_MAX_TASKS", 1, 1)
```

This keeps the current sequential behavior as the default.

- [ ] **Step 3: Keep any direct test construction compatible**

Review tests that instantiate `MetricsProcessor{...}` directly and set `MaxTasks` explicitly in new concurrency-focused tests instead of relying on implicit zero-values (zero should behave as 1).

- [ ] **Step 4: Run the focused processor construction tests**

Run:

```bash
go test ./server/api/doc-processing -run 'TestNewMetricsProcessor|TestMetricsProcessor' -count=1
```

Expected: PASS

### Task 2: Add a thread-safe combined progress tracker

**Files:**
- Modify: `server/api/doc-processing/extract-metrics.go`

- [ ] **Step 1: Add a `metricsProgressTracker` struct**

Introduce a tracker that holds:
- `mu sync.Mutex`
- `Completed int`
- `Total int` (set once before workers start: `totalChunks + totalBatches`)
- `LastProgress string`

- [ ] **Step 2: Implement an `advance()` method**

Keep the combined progress formula from the spec:

```
percent = floor(completed * 100 / total)
progress = "<percent>% (<completed>/<total>)"
```

Implementation:

```go
func (t *metricsProgressTracker) advance() string {
    t.mu.Lock()
    defer t.mu.Unlock()
    t.Completed++
    pct := t.Completed * 100 / t.Total
    t.LastProgress = fmt.Sprintf("%d%% (%d/%d)", pct, t.Completed, t.Total)
    return t.LastProgress
}
```

- [ ] **Step 3: Decide lock scope for persistence**

Compute and return the progress string under lock. Let the caller persist it after the lock is released to avoid holding the lock during DB writes.

- [ ] **Step 4: Thread the tracker into the logging helpers**

Update `logExtractMetricsChunk` and `logEnrichMetricsChunk` to accept the progress string directly (instead of computing `percent` from `chunkIdx/totalChunks` internally). This decouples progress computation from per-pass indexing and allows the combined formula to drive both logging functions.

- [ ] **Step 5: Run focused progress tests**

Run:

```bash
go test ./server/api/doc-processing -run 'TestMetricsProcessor' -count=1
```

Expected: PASS

## Chunk 2: Parallelize Pass 1 (Candidate Extraction)

### Task 3: Add a bounded concurrent worker helper

**Files:**
- Modify: `server/api/doc-processing/extract-metrics.go`

- [ ] **Step 1: Add a helper that runs Pass 1 jobs with bounded concurrency**

Prefer a small helper (inline or package-level) that accepts:
- `ctx context.Context`
- `maxTasks int`
- job count
- a per-index worker function returning a typed result or an error

The helper should:
- cap parallelism to `maxTasks`
- preserve output ordering by writing results into a pre-sized slice at `results[index]`
- cancel sibling work on first error using a derived context
- return the first non-nil error

- [ ] **Step 2: Use standard library synchronization only**

Use `sync.WaitGroup` with a semaphore-style buffered channel. Avoid adding new dependencies.

- [ ] **Step 3: Keep workers pass-scoped, not pipeline-scoped**

Do not mix Pass 1 and Pass 2 work in the same worker pool. Pass 2 cannot start until all Pass 1 workers have finished and the deterministic merge is complete.

### Task 4: Replace the sequential Pass 1 loop with bounded concurrency

**Files:**
- Modify: `server/api/doc-processing/extract-metrics.go`
- Test: `server/api/doc-processing/extract-metrics_test.go`

- [ ] **Step 1: Define a per-chunk result type for Pass 1**

```go
type pass1ChunkResult struct {
    mentions      []metricCandidateMention
    language      string
    modelName     string
    didFallback   bool
}
```

- [ ] **Step 2: Refactor the Pass 1 loop inside `extractMetricsFromChunksWithLLM`**

Replace:

```go
for _, chunk := range chunks {
    ...
    mentions = append(mentions, ...)
}
```

with a bounded concurrent execution block that:
- assigns one job per `chunks[i]`
- stores each completed `pass1ChunkResult` into `results[i]`
- on success, calls `tracker.advance()` and logs via `logExtractMetricsChunk`

- [ ] **Step 3: Merge pass 1 results in order after all workers finish**

After the concurrent block completes successfully, iterate `results` in index order to:
- collect `detectedLanguage` (first non-empty wins)
- accumulate `mentions` in deterministic chunk order
- accumulate `usedMentionModel`, `fallbackCount`, `llmCallCount`

This keeps deterministic ordering for the subsequent merge step.

- [ ] **Step 4: Keep stop behavior compatible**

If `isCtxStopped(ctx)` before scheduling a job or in the worker, return `ErrPipelineStopped` and trigger the existing `stopAndPersistMetrics(...)` path.

- [ ] **Step 5: Keep first-error failure behavior**

On the first non-stop error from any Pass 1 worker:
- cancel remaining sibling jobs via the derived context
- return the error immediately from `extractMetricsFromChunksWithLLM`
- let the caller persist the failed `extract_metrics` status via the existing failure path

- [ ] **Step 6: Add a concurrency test for Pass 1**

Write a test that:
- sets `p.MaxTasks = 2`
- provides at least 3 chunks with distinct candidate results
- blocks worker completion so two goroutines must overlap
- records maximum in-flight calls
- asserts `maxInFlight == 2`

- [ ] **Step 7: Add a deterministic ordering test for Pass 1 output**

Force out-of-order completion, then assert:
- `mentions` are collected in chunk-index order
- `detectedLanguage` is taken from the lowest-index non-empty result
- final `llmCallCount` equals the number of chunks

- [ ] **Step 8: Run the Pass 1 tests**

Run:

```bash
go test ./server/api/doc-processing -run 'TestMetricsProcessor_Pass1' -count=1
```

Expected: PASS

## Chunk 3: Parallelize Pass 2 (Enrichment Batches)

### Task 5: Replace the sequential Pass 2 loop with bounded concurrency

**Files:**
- Modify: `server/api/doc-processing/extract-metrics.go`
- Test: `server/api/doc-processing/extract-metrics_test.go`

- [ ] **Step 1: Define a per-batch result type for Pass 2**

```go
type pass2BatchResult struct {
    metrics   []map[string]any
    uncertain []map[string]any
    language  string
}
```

- [ ] **Step 2: Refactor the Pass 2 loop inside `extractMetricsFromChunksWithLLM`**

Replace:

```go
for batchIdx, batch := range batches {
    ...
    metrics = append(metrics, ...)
}
```

with a bounded concurrent execution block using the same helper pattern as Pass 1, assigning one job per `batches[i]`.

- [ ] **Step 3: Merge pass 2 results in order after all workers finish**

After the concurrent block completes successfully, iterate `results` in index order to:
- collect `detectedLanguage` (first non-empty wins, picking up from Pass 1 value)
- accumulate `metrics` and `uncertain` in deterministic batch order
- accumulate `usedRelationModel`

This preserves the first-seen order required by `dedupeFinalMetricRows`.

- [ ] **Step 4: Keep stop behavior compatible for Pass 2**

Apply the same stop-check pattern as Pass 1: check `isCtxStopped(ctx)` before scheduling a job and propagate `ErrPipelineStopped` to trigger `stopAndPersistMetrics(...)`.

- [ ] **Step 5: Keep first-error failure behavior for Pass 2**

On the first non-stop error from any Pass 2 batch worker, cancel sibling batch workers and return the error immediately.

- [ ] **Step 6: Add a concurrency test for Pass 2**

Write a test that:
- sets `p.MaxTasks = 2`
- provides at least 3 enrichment batches (enough candidates with `MetricEnrichGroupSize = 1`)
- blocks worker completion so two goroutines must overlap
- asserts `maxInFlight == 2`

- [ ] **Step 7: Add a deterministic ordering test for Pass 2 output**

Force out-of-order batch completion, then assert:
- `metrics` are collected in batch-index order
- final metric count and order match a sequential run with the same input

- [ ] **Step 8: Run the Pass 2 tests**

Run:

```bash
go test ./server/api/doc-processing -run 'TestMetricsProcessor_Pass2' -count=1
```

Expected: PASS

## Chunk 4: Harden Failure, Stop, And Logging Behavior

### Task 6: Verify fail-fast cancellation and status persistence

**Files:**
- Modify: `server/api/doc-processing/extract-metrics_test.go`

- [ ] **Step 1: Add a Pass 1 failure test with multiple in-flight jobs**

Create a test where:
- one worker blocks
- a second worker returns `errors.New("candidate extraction boom")`
- remaining jobs should be cancelled or never started

Assert:
- returned error wraps `"candidate extraction boom"`
- failed status is persisted via the existing path
- no duplicate final success status is written

- [ ] **Step 2: Add a Pass 2 failure test with multiple in-flight batches**

Same structure as Step 1, but the error originates in a Pass 2 enrichment worker. Assert that Pass 1 ran to completion and the failure path is triggered at Pass 2.

- [ ] **Step 3: Verify stop propagation works for both passes**

Use a cancellable context that is cancelled while workers are blocked. Assert that:
- `ErrPipelineStopped` is returned (not a context error)
- `stopAndPersistMetrics` is called exactly once

- [ ] **Step 4: Ensure logging stays one-call-per-block**

Concurrent execution should still emit exactly one `extract_metric_candidates` log entry per completed Pass 1 chunk and one `enrich_metrics` log entry per completed Pass 2 batch.

- [ ] **Step 5: Run the failure/stop/logging tests**

Run:

```bash
go test ./server/api/doc-processing -run 'TestMetricsProcessor_Failure|TestMetricsProcessor_Stop' -count=1
```

Expected: PASS

## Chunk 5: Verify End-To-End Behavior And Document Config

### Task 7: Run the full doc-processing test package

**Files:**
- Modify: `server/api/doc-processing/extract-metrics.go`
- Modify: `server/api/doc-processing/extract-metrics_test.go`

- [ ] **Step 1: Run gofmt on touched Go files**

Run:

```bash
gofmt -w server/api/doc-processing/extract-metrics.go server/api/doc-processing/extract-metrics_test.go
```

- [ ] **Step 2: Run the full package tests**

Run:

```bash
go test ./server/api/doc-processing -count=1
```

Expected: PASS

- [ ] **Step 3: Check for race conditions**

Run:

```bash
go test ./server/api/doc-processing -race -run 'TestMetricsProcessor' -count=1
```

Expected: PASS (no data race reports)

### Task 8: Update the written spec for the new concurrency cap

**Files:**
- Modify: `../KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-metrics-spec.md`

- [ ] **Step 1: Add a short note to the workflow section**

Document:
- Pass 1 chunks may be extracted concurrently up to `EXTRACT_METRICS_MAX_TASKS`
- Pass 2 enrichment batches may run concurrently up to `EXTRACT_METRICS_MAX_TASKS`
- The deterministic merge (Step A) and final dedup (Step B) remain sequential
- Pass 2 only begins after all Pass 1 workers have finished and the merge is complete

- [ ] **Step 2: Keep the spec wording behavioral, not implementation-heavy**

Do not describe goroutine internals. Focus on observable processing semantics and output ordering guarantees.

- [ ] **Step 3: Re-run any targeted tests only if the code changed during doc follow-up**

Run:

```bash
go test ./server/api/doc-processing -run 'TestMetricsProcessor' -count=1
```

Expected: PASS

### Task 9: Commit in focused slices

- [ ] **Step 1: Commit the concurrency implementation**

```bash
git add server/api/doc-processing/extract-metrics.go
git commit -m "feat: parallelize metrics extraction by pass"
```

- [ ] **Step 2: Commit the test coverage**

```bash
git add server/api/doc-processing/extract-metrics_test.go
git commit -m "test: cover concurrent metrics extraction"
```

- [ ] **Step 3: Commit the spec update**

```bash
git add ../KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-metrics-spec.md
git commit -m "docs: document metrics extraction concurrency"
```
