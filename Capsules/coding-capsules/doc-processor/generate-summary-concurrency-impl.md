# Generate Summary Concurrency Implementation

## Goal

Improve `generate_summaries` throughput by running independent summary-generation work concurrently, while preserving the existing summary tree semantics and output shape.

The implementation keeps the original high-level contract:

- leaf summaries are generated first
- parent summaries are generated only after the full previous level is complete
- artifact names and summary IDs remain deterministic
- status and logging remain compatible with the existing pipeline

## Core Design

The change introduces bounded sibling concurrency controlled by:

```text
GENERATE_SUMMARY_MAX_TASKS
```

This value caps how many summary-generation jobs may run at the same time. The intended default is `1`, which preserves the original sequential behavior when the env var is not set.

Concurrency is applied only to independent siblings:

- leaf chunk summaries may run in parallel
- summaries within the same parent level may run in parallel
- levels themselves still run sequentially

That gives better throughput without changing the tree-building model.

## Execution Model

### 1. Leaf summaries

The old implementation generated chunk summaries one by one. The new implementation turns each leaf chunk into a job and runs those jobs with bounded concurrency.

Important properties:

- each chunk keeps its original `SeqNo`
- results are written back into a pre-sized result slice by index
- later file writes still happen in deterministic order
- sibling work is cancelled on the first failure

This means leaf completion order may vary internally, but the produced artifact set stays stable.

### 2. Parent summary levels

`buildSummaryTree` keeps the existing outer loop:

- take the current level
- group children
- build the next level
- repeat until one root remains

The change only parallelizes sibling groups within a single level. Parent levels are still strictly ordered, so no parent summary is created before all of its children are available.

This preserves:

- `SummaryID` numbering
- `summary_<level>_<seq>.txt` ordering
- final category-tree layout
- root selection semantics

## Determinism

The implementation is intentionally parallel but not nondeterministic from the outside.

Determinism is preserved by:

- assigning one logical output slot per summary job
- reconstructing ordered slices after concurrent work completes
- writing artifacts in stable sequence order
- keeping parent `seqNo := groupIndex + 1`

As a result, two runs with the same inputs still produce the same tree layout and file naming, even if goroutine scheduling differs.

## Progress And Logging

Parallel completion introduced a race risk around summary progress updates, so progress tracking was made synchronization-safe.

Key behaviors:

- progress only advances on successful summary generation
- progress remains monotonic
- the final progress still reaches `100%`
- progress persistence is serialized relative to tracker state updates

The implementation also keeps summary logging working even when the doc-proc log DB is unavailable. Progress/status persistence is no longer skipped just because DB-backed logging cannot run.

Failure status logging now also preserves the `error` field consistently for failed summary operations.

## Failure Handling

The concurrency model is fail-fast:

- the first non-stop error cancels sibling work
- the pipeline returns that error
- failure status is persisted once through the existing error path

Stop/cancel behavior remains compatible with the existing pipeline control flow, including the paths that persist stopped or failed `generate_summaries` status.

## Main Files

- `ChenWeb/server/api/doc-processing/fix-size-chunking.go`
  - loads `GENERATE_SUMMARY_MAX_TASKS`
  - orchestrates concurrent leaf summary generation
  - protects shared progress state
  - keeps progress/status persistence compatible

- `ChenWeb/server/api/doc-processing/chunk_summary_shared.go`
  - provides bounded per-level concurrent summary-tree generation
  - preserves ordered output while allowing out-of-order completion internally

- `ChenWeb/server/api/doc-processing/chunking_test.go`
  - covers bounded leaf concurrency
  - covers bounded parent-level concurrency
  - verifies deterministic artifact ordering
  - verifies fail-fast cancellation

- `ChenWeb/server/api/doc-processing/generate_summary_logging_test.go`
  - verifies generate-summary logging/progress behavior under synchronized progress tracking

## Validation

The implementation was validated with focused concurrency and logging tests, and the broader package test suite was cleaned so that:

```bash
go test ./server/api/doc-processing -count=1
```

passes in the main `ChenWeb` checkout.

## Net Result

The final behavior is:

- faster summary generation when `GENERATE_SUMMARY_MAX_TASKS > 1`
- no change to external artifact layout or tree semantics
- stable ordering despite concurrent execution
- safer progress tracking and clearer failure persistence

This gives a throughput win without changing the shape of the generated summary tree.
