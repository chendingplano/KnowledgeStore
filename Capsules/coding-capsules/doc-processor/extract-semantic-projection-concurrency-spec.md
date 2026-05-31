# Extract Semantic Projections Concurrency Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve `extract_semantic_projections` throughput by processing chunks concurrently, capped by `EXTRACT_SEMANTIC_PROJECTIONS_MAX_TASKS`, while preserving the existing per-chunk two-pass (candidate + enrichment) semantics and status/logging behavior.

**Architecture:** Each chunk's two passes (Pass 1 candidate extraction → Pass 2 enrichment) remain sequential within that chunk. Chunks are independent of each other, so all chunks may be processed concurrently up to the cap. Add bounded concurrency with deterministic result ordering (by chunk `SeqNo`), synchronized progress tracking, and fail-fast cancellation so artifact names, row insertion order, and status/logging behavior stay compatible with the current sequential implementation.

**Tech Stack:** Go, goroutines, `sync`, `context`, existing doc-processing status/logging helpers, Go test

---

## File Structure

- Modify: `server/api/doc-processing/extract_semantic_projection.go`
  Responsibility: load `EXTRACT_SEMANTIC_PROJECTIONS_MAX_TASKS`, orchestrate concurrent chunk processing, guard shared progress state, and preserve existing success/failure/status persistence behavior.

- Modify: `server/api/doc-processing/extract_semantic_projection_test.go`
  Responsibility: verify concurrent chunk processing, deterministic artifact and row ordering, bounded worker usage, and fail-fast behavior.

- Optional Modify: `../KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-semantic-projection-spec.md`
  Responsibility: document that chunks may be processed concurrently up to `EXTRACT_SEMANTIC_PROJECTIONS_MAX_TASKS` while the two passes within each chunk remain sequential.

## Chunk 1: Add Config And Thread-Safe Progress Tracking

### Task 1: Add the concurrency config field to the service

**Files:**
- Modify: `server/api/doc-processing/extract_semantic_projection.go`

- [ ] **Step 1: Add an `ExtractSemanticProjectionsMaxTasks int` field to the semantic projection service struct**

Add the field near other model/prompt configuration so extraction-related config stays grouped together.

- [ ] **Step 2: Load `EXTRACT_SEMANTIC_PROJECTIONS_MAX_TASKS` in the service constructor**

Use:

```go
ExtractSemanticProjectionsMaxTasks: envInt("EXTRACT_SEMANTIC_PROJECTIONS_MAX_TASKS", 1, 1),
```

This keeps the current sequential behavior as the default.

- [ ] **Step 3: Keep any direct test construction compatible**

Review tests that instantiate the service struct directly and set `ExtractSemanticProjectionsMaxTasks` explicitly in new concurrency-focused tests instead of relying on implicit zero-values.

- [ ] **Step 4: Run the focused service construction tests**

Run:

```bash
go test ./server/api/doc-processing -run 'TestNewSemanticProjectionService|TestService_HandleExtractSemanticProjectionsInput' -count=1
```

Expected: PASS

### Task 2: Make semantic projection progress tracking safe for concurrent completion

**Files:**
- Modify: `server/api/doc-processing/extract_semantic_projection.go`
- Test: `server/api/doc-processing/extract_semantic_projection_test.go`

- [ ] **Step 1: Add synchronization to the progress tracker used by `extract_semantic_projections`**

Introduce a `sync.Mutex` in the tracker and guard `Completed`, `LastProgress`, and any progress persistence sequencing.

- [ ] **Step 2: Refactor `advance()` (or equivalent) to stay monotonic under concurrency**

Keep the current semantics:
- increment only on successful chunk processing
- compute `"<percent>% (<completed>/<total>)"`
- return the new current progress string

Implementation should look conceptually like:

```go
func (t *semanticProjectionProgressTracker) advance() string {
    t.mu.Lock()
    defer t.mu.Unlock()
    ...
}
```

- [ ] **Step 3: Decide lock scope for persistence**

Keep progress values monotonic and avoid data races. The simplest safe approach is:
- update `Completed` and `LastProgress` under lock
- return the progress string
- let the caller perform persistence after the lock is released

If that creates duplicate persisted progress under races, move persistence behind a dedicated serialized helper instead.

- [ ] **Step 4: Add or extend a test that exercises repeated chunk-processing progress updates**

Use a fake store/logger and multiple successful chunk calls to verify the final progress still reaches the expected value without data races.

- [ ] **Step 5: Run focused logging/progress tests**

Run:

```bash
go test ./server/api/doc-processing -run 'TestSemanticProjectionProgress|TestService_HandleExtractSemanticProjectionsInput' -count=1
```

Expected: PASS

## Chunk 2: Parallelize Chunk Processing

### Task 3: Replace the sequential chunk loop with bounded concurrency

**Files:**
- Modify: `server/api/doc-processing/extract_semantic_projection.go`
- Test: `server/api/doc-processing/extract_semantic_projection_test.go`

- [ ] **Step 1: Refactor the current chunk loop inside the extraction handler**

Replace:

```go
for _, chunk := range chunks {
    candidate, err := s.extractCandidate(ctx, chunk, ...)
    ...
    projection, err := s.enrichProjection(ctx, candidate, ...)
    ...
}
```

with a bounded concurrent execution block that:
- assigns one job per chunk (both passes run sequentially within the job)
- preserves `SeqNo` assignment per chunk
- stores each completed projection into `projections[index]` (pre-sized slice)

- [ ] **Step 2: Keep both passes sequential within each goroutine**

Each worker goroutine must complete Pass 1 (candidate extraction with optional fallback) before starting Pass 2 (enrichment) for its chunk. Do not split passes across separate worker pools.

- [ ] **Step 3: Use standard library synchronization only**

Use `sync.WaitGroup`, buffered work channels, or a semaphore-style channel. Avoid adding new dependencies for this change.

- [ ] **Step 4: Keep writes and inserts deterministic**

After concurrent generation completes successfully:
- write semantic projection rows to `kb.semantic_projections` in `SeqNo` order
- write the `.semantic_projections` artifact file in `SeqNo` order

Recommended: process concurrently, then collect results in a sequential ordered loop.

- [ ] **Step 5: Keep stop behavior compatible**

If `ctx` is cancelled or a worker returns `ErrPipelineStopped`, stop scheduling/processing remaining jobs and preserve the existing `stopAndPersist` / failure status path.

- [ ] **Step 6: Keep first-error failure behavior**

On the first non-stop error:
- cancel sibling jobs via context cancellation
- return the error
- persist the failed `extract_semantic_projections` status exactly once via the existing failure path

- [ ] **Step 7: Add a concurrency test for chunk processing**

Write a test that:
- sets `svc.ExtractSemanticProjectionsMaxTasks = 2`
- creates at least 3 chunks
- blocks worker completion so two goroutines must overlap
- records maximum in-flight calls
- asserts `maxInFlight == 2`

- [ ] **Step 8: Add a deterministic output-order test**

Force out-of-order completion, then assert that:
- semantic projection IDs (`<record_id>_<level>_<seqno>`) are assigned in ascending `SeqNo` order
- the `.semantic_projections` artifact rows appear in `SeqNo` order
- final status progress is still `100% (...)`

- [ ] **Step 9: Run the chunk-processing tests**

Run:

```bash
go test ./server/api/doc-processing -run 'TestService_HandleExtractSemanticProjectionsInput' -count=1
```

Expected: PASS

## Chunk 3: Harden Failure, Stop, And Logging Behavior

### Task 4: Verify fail-fast cancellation and status persistence

**Files:**
- Modify: `server/api/doc-processing/extract_semantic_projection_test.go`

- [ ] **Step 1: Add a failure test with multiple in-flight jobs**

Create a test where:
- one worker blocks
- a second worker returns `errors.New("extraction boom")`
- remaining jobs should be cancelled or never started

Assert:
- returned error contains `"extraction boom"`
- failed status is persisted
- no duplicate final success status is written

- [ ] **Step 2: Verify stop propagation still works**

If there is an existing stop/cancel test fixture, extend it for `extract_semantic_projections` concurrency. Otherwise add a focused test using a cancellable context and blocked extraction jobs.

- [ ] **Step 3: Ensure logging stays one-pass-per-chunk**

Concurrent execution should still emit the expected log entries per chunk (candidate-pass start, enrichment-pass start, final results), with progress moving monotonically to the final total. No duplicate or out-of-order log entries for the same chunk.

- [ ] **Step 4: Run the failure/stop/logging tests**

Run:

```bash
go test ./server/api/doc-processing -run 'TestSemanticProjectionProgress|TestService_HandleExtractSemanticProjectionsInput_Failure' -count=1
```

Expected: PASS

## Chunk 4: Verify End-To-End Behavior And Document Config

### Task 5: Run the full doc-processing test package

**Files:**
- Modify: `server/api/doc-processing/extract_semantic_projection.go`
- Modify: `server/api/doc-processing/extract_semantic_projection_test.go`

- [ ] **Step 1: Run gofmt on touched Go files**

Run:

```bash
gofmt -w server/api/doc-processing/extract_semantic_projection.go server/api/doc-processing/extract_semantic_projection_test.go
```

- [ ] **Step 2: Run the full package tests**

Run:

```bash
go test ./server/api/doc-processing -count=1
```

Expected: PASS

- [ ] **Step 3: Check for race-sensitive issues if practical**

If the package/runtime allows it, run:

```bash
go test ./server/api/doc-processing -race -run 'TestService_HandleExtractSemanticProjectionsInput|TestSemanticProjectionProgress' -count=1
```

Expected: PASS

### Task 6: Update the written spec for the new concurrency cap

**Files:**
- Modify: `../KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-semantic-projection-spec.md`

- [ ] **Step 1: Add a short note to the workflow section**

Document:
- chunks may be processed concurrently up to `EXTRACT_SEMANTIC_PROJECTIONS_MAX_TASKS`
- Pass 1 and Pass 2 within a single chunk remain sequential
- output ordering (semantic projection IDs, artifact rows, table inserts) is by chunk `SeqNo` regardless of completion order

- [ ] **Step 2: Keep the spec wording behavioral, not implementation-heavy**

Do not describe goroutine internals. Focus on observable processing semantics.

- [ ] **Step 3: Re-run any targeted tests only if the code changed during doc follow-up**

Run:

```bash
go test ./server/api/doc-processing -run 'TestService_HandleExtractSemanticProjectionsInput' -count=1
```

Expected: PASS

### Task 7: Commit in focused slices

- [ ] **Step 1: Commit the concurrency implementation**

```bash
git add server/api/doc-processing/extract_semantic_projection.go
git commit -m "feat: parallelize semantic projection extraction by chunk"
```

- [ ] **Step 2: Commit the test coverage**

```bash
git add server/api/doc-processing/extract_semantic_projection_test.go
git commit -m "test: cover concurrent semantic projection extraction"
```

- [ ] **Step 3: Commit the spec update**

```bash
git add ../KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-semantic-projection-spec.md
git commit -m "docs: document semantic projection extraction concurrency"
```

## Implementations
Refer to KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-semantic-projection-impl.md
