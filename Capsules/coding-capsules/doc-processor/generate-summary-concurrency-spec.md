# Generate Summary Concurrency Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve `generate_summaries` throughput by generating sibling summaries concurrently, capped by `GENERATE_SUMMARY_MAX_TASKS`, while preserving the existing level-by-level summary tree semantics.

**Architecture:** Keep the current summary pipeline shape: generate all leaf summaries, then build each parent level only after the previous level is complete. Add bounded per-level concurrency with deterministic result ordering, synchronized progress tracking, and fail-fast cancellation so artifact names, tree structure, and status/logging behavior stay compatible with the current implementation.

**Tech Stack:** Go, goroutines, `sync`, `context`, existing doc-processing status/logging helpers, Go test

---

## File Structure

- Modify: `server/api/doc-processing/fix-size-chunking.go`
  Responsibility: load `GENERATE_SUMMARY_MAX_TASKS`, orchestrate concurrent leaf generation, guard shared progress state, and preserve existing success/failure/status persistence behavior.

- Modify: `server/api/doc-processing/chunk_summary_shared.go`
  Responsibility: provide a reusable helper for bounded concurrent per-level summary tree generation with deterministic ordering.

- Modify: `server/api/doc-processing/chunking_test.go`
  Responsibility: verify concurrent leaf and parent generation, deterministic artifact ordering, bounded worker usage, and fail-fast behavior.

- Modify: `server/api/doc-processing/generate_summary_logging_test.go`
  Responsibility: verify generate-summary logging/progress remains correct when progress tracking is synchronized for concurrent execution.

- Optional Modify: `../KnowledgeStore/Capsules/coding-capsules/doc-processor/generate-summary-spec.md`
  Responsibility: document that sibling summaries may be generated concurrently up to `GENERATE_SUMMARY_MAX_TASKS` while levels remain sequential.

## Chunk 1: Add Config And Thread-Safe Progress Tracking

### Task 1: Add the concurrency config field to the service

**Files:**
- Modify: `server/api/doc-processing/fix-size-chunking.go`

- [ ] **Step 1: Add a `GenerateSummaryMaxTasks int` field to `FixedSizeChunkingService`**

Add the field near `SummaryGroupSize` so summary-generation configuration stays grouped together.

- [ ] **Step 2: Load `GENERATE_SUMMARY_MAX_TASKS` in `NewFixedSizeChunkingService`**

Use:

```go
GenerateSummaryMaxTasks: envInt("GENERATE_SUMMARY_MAX_TASKS", 1, 1),
```

This keeps the current sequential behavior as the default.

- [ ] **Step 3: Keep any direct test construction compatible**

Review tests that instantiate `FixedSizeChunkingService{...}` directly and set `GenerateSummaryMaxTasks` explicitly in new concurrency-focused tests instead of relying on implicit zero-values.

- [ ] **Step 4: Run the focused service construction tests**

Run:

```bash
go test ./server/api/doc-processing -run 'TestNewFixedSizeChunkingService|TestService_HandleGenerateSummariesInput' -count=1
```

Expected: PASS

### Task 2: Make summary progress tracking safe for concurrent completion

**Files:**
- Modify: `server/api/doc-processing/fix-size-chunking.go`
- Test: `server/api/doc-processing/generate_summary_logging_test.go`

- [ ] **Step 1: Add synchronization to `summaryProgressTracker`**

Introduce a `sync.Mutex` in the tracker and guard `Completed`, `LastProgress`, and any progress persistence sequencing.

- [ ] **Step 2: Refactor `advance()` to stay monotonic under concurrency**

Keep the current semantics:
- increment only on successful summary generation
- compute `"<percent>% (<completed>/<total>)"`
- return the new current progress string

Implementation should look conceptually like:

```go
func (t *summaryProgressTracker) advance() string {
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

- [ ] **Step 4: Add or extend a test that exercises repeated `generateSummary` progress updates**

Use a fake store/logger and multiple successful summary calls to verify the final progress still reaches the expected value without data races.

- [ ] **Step 5: Run focused logging/progress tests**

Run:

```bash
go test ./server/api/doc-processing -run 'TestFixedSizeChunkingServiceGenerateSummary|TestService_HandleGenerateSummariesInput_WritesSummariesTree' -count=1
```

Expected: PASS

## Chunk 2: Parallelize Leaf Summary Generation

### Task 3: Add a bounded concurrent worker helper for sibling summaries

**Files:**
- Modify: `server/api/doc-processing/fix-size-chunking.go`
- Modify: `server/api/doc-processing/chunk_summary_shared.go`

- [ ] **Step 1: Add a helper that runs sibling summary jobs with bounded concurrency**

Prefer a small helper that accepts:
- `ctx context.Context`
- `maxTasks int`
- job count
- a per-index worker function returning one `SummaryItem` or one `summaryGenerateResult`

The helper should:
- cap parallelism to `maxTasks`
- preserve output ordering by writing results into a pre-sized slice by index
- cancel sibling work on first error
- return the first error

- [ ] **Step 2: Keep the helper level-scoped, not whole-tree scoped**

Do not schedule parent-level work before all children for that level are complete. The helper should only parallelize independent siblings.

- [ ] **Step 3: Use standard library synchronization only**

Use `sync.WaitGroup`, buffered work channels, or a semaphore-style channel. Avoid adding new dependencies for this change.

- [ ] **Step 4: Add a small unit-style test for helper ordering if needed**

If the helper lives in `chunk_summary_shared.go`, add a focused test near existing summary-tree tests to prove out-of-order completion still returns deterministically ordered outputs.

- [ ] **Step 5: Run the helper-focused tests**

Run:

```bash
go test ./server/api/doc-processing -run 'TestBuildSummary|TestService_HandleGenerateSummariesInput' -count=1
```

Expected: PASS

### Task 4: Replace the sequential leaf loop with bounded concurrency

**Files:**
- Modify: `server/api/doc-processing/fix-size-chunking.go`
- Test: `server/api/doc-processing/chunking_test.go`

- [ ] **Step 1: Refactor the current leaf loop inside `handleGenerateSummariesLines`**

Replace:

```go
for _, chunk := range chunks {
    res, err := s.generateSummary(...)
    ...
}
```

with a bounded concurrent execution block that:
- assigns one job per chunk
- preserves `SeqNo`
- stores each completed `SummaryItem` into `leafSummaries[index]`

- [ ] **Step 2: Keep file writes deterministic**

After concurrent generation completes successfully, either:
- write summary files in a separate ordered loop over `leafSummaries`, or
- prove that concurrent writes are safe and still deterministic for later validation

Recommended: generate concurrently, write files sequentially by `SeqNo`.

- [ ] **Step 3: Keep stop behavior compatible**

If `ctx` is cancelled or a worker returns `ErrPipelineStopped`, stop scheduling/processing remaining jobs and preserve the existing `stopAndPersistSummaries(...)` path.

- [ ] **Step 4: Keep first-error failure behavior**

On the first non-stop error:
- cancel sibling jobs
- return the error
- persist the failed `generate_summaries` status exactly once via the existing failure path

- [ ] **Step 5: Add a concurrency test for leaf summaries**

Write a test that:
- sets `svc.GenerateSummaryMaxTasks = 2`
- creates at least 3 chunks
- blocks worker completion so two goroutines must overlap
- records maximum in-flight calls
- asserts `maxInFlight == 2`

- [ ] **Step 6: Add a deterministic artifact-order test for leaf output**

Force out-of-order completion, then assert that:
- `summary_0_0001.txt`, `summary_0_0002.txt`, ... still exist
- contents map to the correct chunk `SeqNo`
- final status progress is still `100% (...)`

- [ ] **Step 7: Run the leaf-summary tests**

Run:

```bash
go test ./server/api/doc-processing -run 'TestService_HandleGenerateSummariesInput_WritesSummariesTree|TestService_HandleGenerateSummariesInput_SummaryGenerationFailure' -count=1
```

Expected: PASS

## Chunk 3: Parallelize Parent-Level Summary Tree Generation

### Task 5: Refactor summary tree building to parallelize siblings within each parent level

**Files:**
- Modify: `server/api/doc-processing/chunk_summary_shared.go`
- Test: `server/api/doc-processing/chunking_test.go`

- [ ] **Step 1: Refactor `buildSummaryTree` to use the bounded concurrency helper per level**

Keep this outer structure:

```go
for len(current) > 1 {
    // build one parent level from current
    current = next
    level++
}
```

Only the sibling group work inside the level should run concurrently.

- [ ] **Step 2: Preserve existing parent numbering**

Each parent summary must still use:

```go
seqNo := groupIndex + 1
SummaryID: buildSummaryID(recordID, level, seqNo)
```

so tree artifacts remain stable.

- [ ] **Step 3: Preserve result order for `allSummaries`**

Append parents to `allSummaries` in deterministic `seqNo` order after the concurrent level finishes, not in completion order.

- [ ] **Step 4: Thread `maxTasks` into `buildSummaryTree`**

Update the function signature to accept the concurrency cap, for example:

```go
func buildSummaryTree(
    recordID int64,
    leafs []SummaryItem,
    groupSize int,
    maxTasks int,
    summarize func(level int, seqNo int, children []SummaryItem) (summaryGenerateResult, error),
) ([]SummaryItem, SummaryItem, error)
```

Then pass `s.GenerateSummaryMaxTasks` from `handleGenerateSummariesLines`.

- [ ] **Step 5: Add a parent-level concurrency test**

Use enough leaves and a small `SummaryGroupSize` so at least one parent level has multiple sibling groups. Verify:
- more than one parent summary runs concurrently
- `maxInFlight` never exceeds `GenerateSummaryMaxTasks`
- root summary output still references the correct child summary IDs

- [ ] **Step 6: Run the parent-level tests**

Run:

```bash
go test ./server/api/doc-processing -run 'TestService_HandleGenerateSummariesInput_WritesSummariesTree|TestTotalPlannedSummaries' -count=1
```

Expected: PASS

## Chunk 4: Harden Failure, Stop, And Logging Behavior

### Task 6: Verify fail-fast cancellation and status persistence

**Files:**
- Modify: `server/api/doc-processing/chunking_test.go`
- Modify: `server/api/doc-processing/generate_summary_logging_test.go`

- [ ] **Step 1: Add a failure test with multiple in-flight jobs**

Create a test where:
- one worker blocks
- a second worker returns `errors.New("summary generator boom")`
- remaining jobs should be cancelled or never started

Assert:
- returned error contains `"summary generator boom"`
- failed status is persisted
- no duplicate final success status is written

- [ ] **Step 2: Verify stop propagation still works**

If there is an existing stop/cancel test fixture, extend it for `generate_summaries` concurrency. Otherwise add a focused test using a cancellable context and blocked summary jobs.

- [ ] **Step 3: Ensure logging stays one-successful-call-per-summary**

Concurrent execution should still emit one `generate_summary` log entry per completed call, with progress moving monotonically to the final total.

- [ ] **Step 4: Run the failure/stop/logging tests**

Run:

```bash
go test ./server/api/doc-processing -run 'TestFixedSizeChunkingServiceGenerateSummary|TestService_HandleGenerateSummariesInput_SummaryGenerationFailure' -count=1
```

Expected: PASS

## Chunk 5: Verify End-To-End Behavior And Document Config

### Task 7: Run the full doc-processing test package

**Files:**
- Modify: `server/api/doc-processing/fix-size-chunking.go`
- Modify: `server/api/doc-processing/chunk_summary_shared.go`
- Modify: `server/api/doc-processing/chunking_test.go`
- Modify: `server/api/doc-processing/generate_summary_logging_test.go`

- [ ] **Step 1: Run gofmt on touched Go files**

Run:

```bash
gofmt -w server/api/doc-processing/fix-size-chunking.go server/api/doc-processing/chunk_summary_shared.go server/api/doc-processing/chunking_test.go server/api/doc-processing/generate_summary_logging_test.go
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
go test ./server/api/doc-processing -race -run 'TestService_HandleGenerateSummariesInput|TestFixedSizeChunkingServiceGenerateSummary' -count=1
```

Expected: PASS

### Task 8: Update the written spec for the new concurrency cap

**Files:**
- Modify: `../KnowledgeStore/Capsules/coding-capsules/doc-processor/generate-summary-spec.md`

- [ ] **Step 1: Add a short note to the summary workflow section**

Document:
- sibling summaries at the same level may be generated concurrently
- concurrency is capped by `GENERATE_SUMMARY_MAX_TASKS`
- higher levels still wait for the previous level to finish

- [ ] **Step 2: Keep the spec wording behavioral, not implementation-heavy**

Do not describe goroutine internals. Focus on observable processing semantics.

- [ ] **Step 3: Re-run any targeted tests only if the code changed during doc follow-up**

Run:

```bash
go test ./server/api/doc-processing -run 'TestService_HandleGenerateSummariesInput_WritesSummariesTree' -count=1
```

Expected: PASS

### Task 9: Commit in focused slices

**Files:**
- Commit 1: service + helper changes
- Commit 2: tests
- Commit 3: spec update

- [ ] **Step 1: Commit the concurrency implementation**

```bash
git add server/api/doc-processing/fix-size-chunking.go server/api/doc-processing/chunk_summary_shared.go
git commit -m "feat: parallelize summary generation by level"
```

- [ ] **Step 2: Commit the test coverage**

```bash
git add server/api/doc-processing/chunking_test.go server/api/doc-processing/generate_summary_logging_test.go
git commit -m "test: cover concurrent summary generation"
```

- [ ] **Step 3: Commit the spec update**

```bash
git add ../KnowledgeStore/Capsules/coding-capsules/doc-processor/generate-summary-spec.md
git commit -m "docs: document summary generation concurrency"
```

## Implementations
Refer to KnowledgeStore/Capsules/coding-capsules/doc-processor/generate-summary-concurrency-impl.md
