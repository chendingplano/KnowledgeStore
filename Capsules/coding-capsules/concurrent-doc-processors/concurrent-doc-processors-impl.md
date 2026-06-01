# Concurrent Doc Processors — Implementation Notes

**Date:** 2026-06-01
**Branches:** `feature/concurrent-doc-processors` (merged to `main` at `c7c0bb5`)
**Design:** `concurrent-doc-processors-design.md`
**Plan:** `concurrent-doc-processors-plan.md`
**Capsule:** [../doc-processor/+CAPSULE.md](../doc-processor/+CAPSULE.md) (updated with Pipeline Execution Model section)

## Summary

The doc pipeline controller now fans out all configurable (Phase B) processors as concurrent goroutines under a `sync.WaitGroup`, with a per-record sharded mutex protecting every `kb.inputs.status` read-modify-write. Controlled by `RUN_DOC_PROCESSOR_CONCURRENT` (default `true`). The expected speedup is ~7× for the dominant LLM-bound phase (~350s → ~50s for 7 configured processors at ~50s each).

## Architecture

### Two primitives power the change

Because Phase B processors write status via two different store interfaces (`DocMetadataStore.UpdateInputMetadata` and `Store.UpdateInputStatus`), two complementary primitives were introduced in `status_lock.go`:

| Primitive | Interface | When to use |
|---|---|---|
| `updateInputStatusAtomic(ctx, store, id, mutate)` | `DocMetadataStore` | Most Phase B processors (metrics, provisions, scene-blocks, inventory, entity-relation, knowledge, semantic-projections). `mutate` receives the freshest `StatusRaw` re-read inside the lock. |
| `(*FixedSizeChunkingService).updateInputStatusLocked(ctx, id, errMsg, build)` | `Store` (fix-size-chunking) | `generate_summaries` and `generate_topics` (Phase B inside `fix-size-chunking.go`). Re-reads via `Store.GetInputRecord`, builds via callback, writes via `Store.UpdateInputStatus`. |

Both use the same sharded lock: `lockRecordStatus(id)` → returns `unlock()`.

**Key design point:** the `mutate`/`build` callback receives the **just-now-read** status inside the lock — not a stale local `rec.StatusRaw`. This is the whole fix. Every call site was retrofitted to pass `current` to its `append*Status` function rather than using a pre-read value.

### Sharded per-record lock (`status_lock.go`)

```go
const recordStatusLockShards = 256
var recordStatusLocks [recordStatusLockShards]sync.Mutex

func lockRecordStatus(id int64) func() {
    shard := uint64(id) % recordStatusLockShards
    m := &recordStatusLocks[shard]
    m.Lock()
    return m.Unlock
}
```

256 shards, fixed-size array (no allocation, no leak). Two records hashing to the same shard serialize their status writes — this is fine because status writes are sub-millisecond.

**Constraint (single-instance only):** this lock coordinates goroutines within one process. If doc-processor scales to multiple replicas, replace with a DB row lock (`SELECT ... FOR UPDATE`) + `jsonb_set` or a shared coordinator (Redis / dedicated primary). Documented in the capsule and at the lock site.

### Two-phase pipeline

`ControlService.handleEvent` dispatches to one of two methods based on `RunDocProcessorConcurrentFromEnv()`:

**`runProcessorsSequential`** — verbatim copy of the original loop (Phase A + Phase B in order, block-buffer clear after `static_analyzer`, stop reconciliation). Used when `RUN_DOC_PROCESSOR_CONCURRENT=false`.

**`runProcessorsTwoPhase`** — new:

1. **Phase A (sequential loop):** iterates `processors`; skips Phase B (non-mandatory) processors into a `phaseB` slice. Mandatory processors (`static_analyzer`, `chunking`, `extract_doc_metadata`) run in order via the existing `runSingleProcessor` (shared-state path). Block-buffer clear and stop checks preserved exactly.
2. **Phase B (concurrent fan-out):** launches each `phaseB` processor in a goroutine via `runSingleProcessorCollect` (returns `procResult`, never touches shared state). Panic recovery per goroutine records a failure. `WaitGroup.Wait()`, then reduce results. A stop during Phase B reclassifies the run as `stopped`.

`isPhaseAProcessor` mirrors `cmd/doc-processor/main.go` `filterConfiguredProcessors` mandatory set: `static_analyzer`, `chunking`, `extract_doc_metadata`.

### Result-collecting runner

`runSingleProcessorCollect` runs one processor and returns a `procResult{failed, stopped, err}` value — no shared-state mutation. This is the callable-from-goroutines counterpart to the existing `runSingleProcessor` (which mutates `*requestFailed`/`*firstErr`). `runSingleProcessor` is now a thin wrapper around it.

## Status write retrofit (Chunk 2)

23 call sites across 8 files were retrofitted. Every site follows the same before/after pattern:

**Before (racy under concurrency):**
```go
rec, _ := p.InputStore.GetInputRecord(ctx, id)  // stale read
statusRaw, _ := appendXxxStatus(rec.StatusRaw, params)
p.InputStore.UpdateInputMetadata(ctx, id, DocMetadataUpdate{StatusRaw: statusRaw})
```

**After (atomic):**
```go
updateInputStatusAtomic(ctx, p.InputStore, id, func(current string) (DocMetadataUpdate, error) {
    statusRaw, _ := appendXxxStatus(current, params)  // re-read inside lock
    return DocMetadataUpdate{StatusRaw: statusRaw}, nil
})
```

### Processors retrofitted (UpdateInputMetadata path)

| File | Sites | Notes |
|---|---|---|
| `extract-metrics.go` | 2 (`persistMetricsStatus`, `stopAndPersistMetrics`) | |
| `extract-provisions.go` | 3 (`persistProvisionsStatus`, `persistProvisionsRunningStatus`, `stopAndPersistProvisions`) | |
| `generate-scene-blocks-processor.go` | 3 (`persistSceneBlocksStatus`, `persistSceneBlocksInProgressStatus`, `stopAndPersistSceneBlocks`) | In-progress status included |
| `extract-inventory-items.go` | 2 (`persistInventoryItemsStatus`, `stopAndPersistInventoryItems`) | `stop` discards error return |
| `extract-entity-relation.go` | 2 (`persistEntityRelationStatus`, `stopAndPersistEntityRelation`) | |
| `extract-structured-knowledge.go` | 2 (`persistStructuredKnowledgeStatus`, `stopAndPersistStructuredKnowledge`) | |
| `extract-semantic-projections.go` | 2 (`persistSemanticProjectionsStatus`, `stopAndPersistSemanticProjections`) | |
| `control.go` | 1 (`persistPipelineStatus`) | Controller's own `doc_processing` entry |

### Processors retrofitted (UpdateInputStatus path — fix-size-chunking.go)

| Function | Sites | Notes |
|---|---|---|
| `handleGenerateTopicsLines` | 3 (initial progress, per-chunk progress, final success) | Dropped local `rec.StatusRaw` accumulation |
| `handleGenerateSummariesLines` | 2 (progress tracker Persist closure, final success) | Dropped local `rec.StatusRaw` accumulation |
| `failAndPersistTopics` | 1 | |
| `stopAndPersistTopics` | 1 | |
| `failAndPersistSummaries` | 1 | |
| `stopAndPersistSummaries` | 1 | |

A new helper method `(*FixedSizeChunkingService).updateInputStatusLocked` was added to `fix-size-chunking.go` that re-reads the record via `Store.GetInputRecord`, calls the user's `build(current)` closure, and persists via `Store.UpdateInputStatus` — all under the per-record lock.

**Not retrofitted:** Phase A processors (`structure_analyzer`, `doc-structure-analyzer`, `extract_doc_metadata`, and the `chunking` portions of `fix-size-chunking.go`). These run sequentially before Phase B and cannot race. 

## Buffer lifecycle (no change needed)

- **Block buffer:** still cleared after `static_analyzer` (unchanged). This is intentional — `static_analyzer` re-labels lines, making pre-analysis blocks stale (enforced by `TestControlService_StaticAnalyzerClearsStaleBlockBuffer`). Phase B block-consumers (`extract_metrics`, `extract_products`) re-block from the input file via their own fallback (`resolveProductBlocks` → `buildBlocks`), producing goroutine-local `[]Block`. Already concurrency-safe; no change.
- **Chunk buffer:** populated by `chunking` (Phase A), read-only by Phase B consumers (`extract_provisions` via `resolveChunks` → `ChunkBufferFromContext`). The holder already has a mutex. Audit confirmed no Phase B consumer mutates `buf.Chunks`. Verified with `TestChunkBufferConcurrentReads_NoRace`.

## Flag

`RUN_DOC_PROCESSOR_CONCURRENT` env var, read by `RunDocProcessorConcurrentFromEnv()` in `control.go`:

- `"false"` → `runProcessorsSequential` (original, verbatim)
- absent or anything else → `runProcessorsTwoPhase` (new concurrent path)
- Defaults to `true`; logged at startup in `main.go`

Defaulting to `true` is safe because the per-record status mutex ships in the same change. The flag serves as a production kill-switch — if an unforeseen concurrency bug surfaces, toggle it to `"false"` without a redeploy.

## Tests

All tests run with `-race`. New tests:

| Test | What it guards |
|---|---|
| `TestLockRecordStatus_SerializesSameRecord` | Lock serialises same-record access |
| `TestLockRecordStatus_DifferentRecordsDoNotDeadlock` | Different records don't contend |
| `TestUpdateInputStatusAtomic_NoLostUpdates` | 20 concurrent writers, all 20 entries survive |
| `TestPersistPipelineStatus_ConcurrentNoLostUpdates` | Controller status write is race-free |
| `TestIsPhaseAProcessor` | Phase A/B classification matches mandatory set |
| `TestTwoPhase_PhaseABeforePhaseB` | Phase A completes before any Phase B starts |
| `TestTwoPhase_PhaseBOverlaps` | Phase B goroutines truly run concurrently |
| `TestTwoPhase_FlagOffIsSequential` | `RUN_DOC_PROCESSOR_CONCURRENT=false` restores sequential order |
| `TestTwoPhase_FailureIsolation` | One Phase B failure doesn't stop siblings |
| `TestTwoPhase_NoLostStatusEntries` | 8 concurrent `statusWritingProcessor`s, all 8 entries survive |
| `TestChunkBufferConcurrentReads_NoRace` | Concurrent chunk-buffer reads are clean under `-race` |

Existing tests that assert deterministic sequential ordering use `t.Setenv("RUN_DOC_PROCESSOR_CONCURRENT", "false")` to force the sequential path.

**Pre-existing bug fix:** `fakeDocMetadataStore` in `extract-doc-metadata_test.go` had unsynchronized fields read by `waitForStatusUpdate` while the pipeline goroutine wrote them. Added a `sync.Mutex` to the fake and a `statusUpdates()` snapshot accessor. 

## Thread-safety audit results

| Processor | Result |
|---|---|
| `extract_structured_knowledge` | Safe — package-level vars are read-only (`var knowledgeTypeOrder`, `var knowledgeTypeArrayKeys`, `var knowledgeTypePrimaryFields`); all mutation uses goroutine-local variables. |
| `extract_products` | Safe — commented out in `main.go:203` (not enabled). When re-enabled, it needs the same audit. |

## Files changed

```
server/api/doc-processing/status_lock.go              (+70, new)   Sharded lock + updateInputStatusAtomic + withRecordStatusLock
server/api/doc-processing/status_lock_test.go         (+90, new)   Lock + atomic-helper tests
server/api/doc-processing/control.go                  (±242)       Two-phase dispatch, Phase A/B classification, result-collecting runner, flag
server/api/doc-processing/control_test.go             (±281)       Two-phase tests, lost-entry integration test, helpers
server/api/doc-processing/extract-doc-metadata_test.go(±19)        Mutex on fakeDocMetadataStore (pre-existing race fix)
server/api/doc-processing/extract-entity-relation.go  (±55)        2 sites to updateInputStatusAtomic
server/api/doc-processing/extract-inventory-items.go  (±55)        2 sites to updateInputStatusAtomic
server/api/doc-processing/extract-metrics.go          (±55)        2 sites to updateInputStatusAtomic
server/api/doc-processing/extract-provisions.go       (±80)        3 sites to updateInputStatusAtomic
server/api/doc-processing/extract-semantic-projections.go(±55)    2 sites to updateInputStatusAtomic
server/api/doc-processing/extract-structured-knowledge.go(±55)    2 sites to updateInputStatusAtomic
server/api/doc-processing/generate-scene-blocks-processor.go(±96) 3 sites to updateInputStatusAtomic
server/api/doc-processing/fix-size-chunking.go        (±226)      9 sites via updateInputStatusLocked, dropped rec.StatusRaw accumulation
server/cmd/doc-processor/main.go                      (+1)        Log RUN_DOC_PROCESSOR_CONCURRENT at startup
```

## Rollout notes

1. The flag defaults to `true` — Phase B processors will fan out on the first deploy.
2. Monitor per-record wall-clock time: should drop from ~Σ(processor) toward ~max(processor).
3. If any concurrency issue surfaces, set `RUN_DOC_PROCESSOR_CONCURRENT=false` as immediate mitigation.
4. All status writes are atomic under the per-record lock; lost entries should no longer occur.
5. The feature does not change output tables, output files, or the frontend.
