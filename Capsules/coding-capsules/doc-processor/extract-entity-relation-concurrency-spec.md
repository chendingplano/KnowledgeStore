# Extract Entity & Relation — Concurrency Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve `extract_entity_relation` throughput by processing chunks concurrently, capped by `EXTRACT_ENTITY_RELATION_MAX_TASKS`, while preserving the existing per-chunk skip-on-LLM-error semantics and fail-fast-on-stop behavior.

**Architecture:** Reuse the existing `runConcurrent[T any]` helper from `chunk_summary_shared.go`. Introduce a per-chunk result struct so LLM errors are captured as "skipped" (not propagated as Go errors) and only `ErrPipelineStopped` causes sibling cancellation. After all workers finish, aggregate results in original chunk-index order for deterministic `entity_id` / `relation_id` assignment.

**Tech Stack:** Go, goroutines, `sync`, `context`, existing `runConcurrent` helper, Go test

---

## File Structure

- Modify: `server/api/doc-processing/extract-entity-relation.go`
  Responsibility: load `EXTRACT_ENTITY_RELATION_MAX_TASKS`, define `entityRelationChunkResult`, rewrite `extractEntityRelationFromChunks` to use bounded concurrency, aggregate results in index order.

- Modify: `server/api/doc-processing/extract-entity-relation_test.go`
  Responsibility: verify concurrent chunk processing, deterministic result ordering, bounded worker usage, and stop propagation.

- Optional Modify: `../KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-entity-relation-spec.md`
  Responsibility: document that chunks may be processed concurrently up to `EXTRACT_ENTITY_RELATION_MAX_TASKS`.

## Chunk 1: Add Config And Per-Chunk Result Type

### Task 1: Add the concurrency config field to the processor

**Files:**
- Modify: `server/api/doc-processing/extract-entity-relation.go`

- [ ] **Step 1: Add an `ExtractEntityRelationMaxTasks int` field to `EntityRelationProcessor`**

Add the field after `ArtifactDir` so processor configuration stays grouped together.

- [ ] **Step 2: Load `EXTRACT_ENTITY_RELATION_MAX_TASKS` in `NewEntityRelationProcessor`**

Use:

```go
ExtractEntityRelationMaxTasks: envInt("EXTRACT_ENTITY_RELATION_MAX_TASKS", 1, 1),
```

This keeps the current sequential behavior as the default.

- [ ] **Step 3: Run the focused processor construction test**

Run:

```bash
go test ./server/api/doc-processing -run 'TestEntityRelationProcessor' -count=1
```

Expected: PASS (no behavioral change yet, just a new field).

### Task 2: Define the per-chunk result type

**Files:**
- Modify: `server/api/doc-processing/extract-entity-relation.go`

- [ ] **Step 1: Define `entityRelationChunkResult`**

Add a private struct that carries all per-chunk outputs:

```go
type entityRelationChunkResult struct {
    Entities      []map[string]any
    Relations     []map[string]any
    Language      string
    ModelName     string
    LLMCallCount  int
    FallbackCount int
    Failed        bool // true if LLM call failed (chunk skipped, not aborted)
}
```

- [ ] **Step 2: Extract the single-chunk logic into a helper method**

Extract the body of the existing `for idx, chunk := range chunks` loop into:

```go
func (p *EntityRelationProcessor) processChunk(
    ctx context.Context,
    recordID int64,
    idx int,
    totalChunks int,
    chunk Chunk,
) entityRelationChunkResult
```

The helper should:
- Check `isCtxStopped(ctx)` and return a zero `entityRelationChunkResult` with `Failed: true` if stopped (the caller will propagate `ErrPipelineStopped` separately)
- Call `extractEntityRelationWithFallback`, increment `LLMCallCount`, detect fallback usage
- On LLM error: log the warning, set `Failed: true`, still call `logLLMCall`, return
- On success: normalize entities and relations, detect language, call `logLLMCall`

Note: `logLLMCall` receives `chunkEntityCount`, `totalEntityCount`, `chunkRelationCount`, `totalRelationCount`. Under concurrency the running global totals are unknown during per-chunk execution. Pass `0` for the two global totals in per-chunk calls; the accurate final totals are logged by `logEntityRelationSummary` at the end.

- [ ] **Step 3: Run the existing extraction tests against the refactored helper**

Run:

```bash
go test ./server/api/doc-processing -run 'TestExtractEntityRelation|TestNormalize' -count=1
```

Expected: PASS

## Chunk 2: Parallelize Chunk Processing

### Task 3: Replace the sequential chunk loop with bounded concurrency

**Files:**
- Modify: `server/api/doc-processing/extract-entity-relation.go`

- [ ] **Step 1: Rewrite `extractEntityRelationFromChunks` to use `runConcurrent`**

Replace:

```go
for idx, chunk := range chunks {
    if isCtxStopped(ctx) { ... }
    ...
}
```

with:

```go
chunkResults, runErr := runConcurrent(ctx, p.ExtractEntityRelationMaxTasks, len(chunks),
    func(workerCtx context.Context, i int) (entityRelationChunkResult, error) {
        if isCtxStopped(workerCtx) {
            return entityRelationChunkResult{}, ErrPipelineStopped
        }
        return p.processChunk(workerCtx, recordID, i, len(chunks), chunks[i]), nil
    },
)
if runErr != nil {
    return entityRelationExtractionResult{}, runErr
}
```

Key invariant: the worker function only returns a non-nil error for `ErrPipelineStopped`. LLM errors are absorbed into `entityRelationChunkResult.Failed = true` so sibling chunks continue.

- [ ] **Step 2: Aggregate results in chunk-index order**

After `runConcurrent` returns, iterate `chunkResults` in order (index 0, 1, 2, …) to build the final `entityRelationExtractionResult`:

```go
for _, r := range chunkResults {
    llmCallCount  += r.LLMCallCount
    fallbackCount += r.FallbackCount
    if r.Failed {
        failedChunks++
        continue
    }
    if r.Language != "" && detectedLanguage == "unknown" {
        detectedLanguage = r.Language
    }
    if strings.TrimSpace(r.ModelName) != "" {
        usedModel = strings.TrimSpace(r.ModelName)
    }
    entities  = append(entities, r.Entities...)
    relations = append(relations, r.Relations...)
}
```

Iterating in index order preserves chunk ordering so that the `entity_id = <record_id>_e_<seqno>` and `relation_id = <record_id>_r_<seqno>` assignments (applied after this function returns) remain deterministic and stable.

- [ ] **Step 3: Remove the now-redundant `isCtxStopped` check at the top of the old loop**

The worker function already checks `isCtxStopped`; the outer sequential loop check is gone.

- [ ] **Step 4: Verify stop behavior threads through correctly**

`runConcurrent` propagates the first error (here `ErrPipelineStopped`) from any worker and cancels siblings. The caller in `HandleEvent` already handles `ErrPipelineStopped`:

```go
if errors.Is(err, ErrPipelineStopped) {
    p.stopAndPersistEntityRelation(context.Background(), rec, start)
    return ErrPipelineStopped
}
```

No change needed there.

- [ ] **Step 5: Run the core extraction tests**

Run:

```bash
go test ./server/api/doc-processing -run 'TestExtractEntityRelation|TestEntityRelationProcessor' -count=1
```

Expected: PASS

## Chunk 3: Test Coverage

### Task 4: Add concurrency and ordering tests

**Files:**
- Modify: `server/api/doc-processing/extract-entity-relation_test.go`

- [ ] **Step 1: Add a concurrency test for bounded parallelism**

Write a test that:
- Sets `p.ExtractEntityRelationMaxTasks = 2`
- Creates at least 3 chunks
- Uses a fake `LLMJSONExtractor` that blocks until a signal, tracks in-flight count
- Asserts `maxInFlight == 2`

- [ ] **Step 2: Add a deterministic ordering test**

Use an extractor where chunk 2 completes before chunk 0 (via delay/ordering). After extraction, assert that entities appear in chunk-index order (chunk 0 entities first, then chunk 1, then chunk 2) so `entity_id` assignment is stable.

- [ ] **Step 3: Add a failed-chunk-skip test under concurrency**

Set `ExtractEntityRelationMaxTasks = 2`. One chunk's LLM call returns an error; the others succeed. Assert:
- `result.FailedChunks == 1`
- successful chunks' entities and relations are still present
- no error is returned from `extractEntityRelationFromChunks`

- [ ] **Step 4: Add a stop propagation test**

Cancel the context mid-extraction (or use an extractor that checks `isCtxStopped`). Assert `ErrPipelineStopped` is returned from `extractEntityRelationFromChunks`.

- [ ] **Step 5: Run all extraction tests**

Run:

```bash
go test ./server/api/doc-processing -run 'TestExtractEntityRelation|TestNormalize|TestEntityRelationProcessor' -count=1
```

Expected: PASS

## Chunk 4: Harden And Verify

### Task 5: Run full package tests and race detector

**Files:**
- Modify: `server/api/doc-processing/extract-entity-relation.go`
- Modify: `server/api/doc-processing/extract-entity-relation_test.go`

- [ ] **Step 1: Run gofmt on touched Go files**

Run:

```bash
gofmt -w server/api/doc-processing/extract-entity-relation.go server/api/doc-processing/extract-entity-relation_test.go
```

- [ ] **Step 2: Run the full package tests**

Run:

```bash
go test ./server/api/doc-processing -count=1
```

Expected: PASS

- [ ] **Step 3: Run with race detector**

Run:

```bash
go test ./server/api/doc-processing -race -run 'TestExtractEntityRelation|TestEntityRelationProcessor' -count=1
```

Expected: PASS (no data races)

### Task 6: Update the written spec

**Files:**
- Modify: `../KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-entity-relation-spec.md`

- [ ] **Step 1: Add a note to the Workflow section**

Under step 8, document:

- Chunks may be processed concurrently up to `EXTRACT_ENTITY_RELATION_MAX_TASKS` workers
- An LLM error on one chunk still skips that chunk; it does not cancel siblings
- Only a pipeline-stop signal cancels all in-flight chunk workers
- Results are aggregated in original chunk-index order so `entity_id` and `relation_id` assignment remains deterministic

- [ ] **Step 2: Add `EXTRACT_ENTITY_RELATION_MAX_TASKS` to the Environment Variables table**

| Name | Required | Purpose |
|---|---|---|
| `EXTRACT_ENTITY_RELATION_MAX_TASKS` | optional | Max concurrent chunk-processing goroutines. Default `1` (sequential). |

- [ ] **Step 3: Re-run targeted tests if code changed during doc follow-up**

Run:

```bash
go test ./server/api/doc-processing -run 'TestExtractEntityRelation' -count=1
```

Expected: PASS

### Task 7: Commit

- [ ] **Step 1: Commit the concurrency implementation**

```bash
git add server/api/doc-processing/extract-entity-relation.go
git commit -m "feat: parallelize entity-relation extraction by chunk"
```

- [ ] **Step 2: Commit the test coverage**

```bash
git add server/api/doc-processing/extract-entity-relation_test.go
git commit -m "test: cover concurrent entity-relation chunk extraction"
```

- [ ] **Step 3: Commit the spec update**

```bash
git add ../KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-entity-relation-spec.md
git commit -m "docs: document entity-relation extraction concurrency"
```

## Key Differences From Generate-Summary Concurrency

| Concern | generate_summaries | extract_entity_relation |
|---|---|---|
| Structure | Tree (levels → parents) | Flat chunk list |
| LLM error behavior | Fail-fast: cancel siblings | Skip chunk: siblings continue |
| Stop behavior | Cancel all, persist stopped | Cancel all, persist stopped |
| Progress tracking | `summaryProgressTracker` (mutex) | Per-chunk `logLLMCall` (concurrent-safe via goroutine-local counts) |
| Result ordering | Level-by-level, seqNo-stable | Chunk-index order, stable entity/relation seqno |
| Existing helper | `runConcurrent` (same package) | Reuse `runConcurrent` (same package) |
| New helper needed | `buildSummaryTree` with maxTasks | None — flat map over `runConcurrent` |
