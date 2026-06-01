# Concurrent Doc Processors Design

**Date:** 2026-06-01  
**Project:** `ChenWeb`  
**Subsystem:** Doc Processor (`ChenWeb/server/cmd/doc-processor`, `ChenWeb/server/api/doc-processing`)  
**Capsule:** `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md`  
**Scope:** Run the configurable doc processors concurrently within a single record's pipeline, gated by a feature flag, with a concurrency-safe `kb.inputs.status` write.

## Goal

Reduce the wall-clock time to process one document. Today the controller runs every processor sequentially. The configurable, LLM-bound processors each take tens of seconds (assume ~50s), so 7 configured processors cost ~350s per document. They are independent and depend only on already-completed mandatory stages, so running them concurrently should bring total time down to roughly `max(processor) + overhead` (~50s) — a ~7× improvement on the dominant cost.

## Problem

The pipeline is **latency-bound, not rate-limit-bound.** Each processor blocks on slow LLM responses. With DeepSeek-V4-Flash the provider concurrency limit is 2,500 and each processor is internally capped at 30 concurrent requests, so 7 processors running at once peak at ~210 concurrent requests — well within budget. There is no rate-limit reason to keep them serial.

The blocker is correctness, not capacity. Every processor records its progress and terminal state into `kb.inputs.status`, a single JSONB column on the shared `kb.inputs` row, using a read-modify-write sequence:

```
rec        = GetInputRecord(record_id)          // read whole status array
statusRaw  = appendXxxStatus(rec.StatusRaw, …)  // append this processor's entry in Go
UpdateInputMetadata(record_id, {StatusRaw})     // UPDATE kb.inputs SET status = $::jsonb  (whole-column overwrite)
```

This pattern appears in every processor (`extract-provisions.go`, `generate-scene-blocks-processor.go`, `extract-inventory-items.go`, `fix-size-chunking.go`, `extract-doc-metadata.go`, …) and in the controller's `persistPipelineStatus` (`control.go`). Run two of them concurrently and the later writer overwrites the earlier writer's entry — a classic lost update:

```
extract_metrics : read status=[A]
scene_blocks    : read status=[A]
extract_metrics : write status=[A, metrics]
scene_blocks    : write status=[A, scene]      ← "metrics" entry is gone
```

A lost status entry corrupts the **Record Completion Criteria** (the record never reaches "finished" because an expected processor's terminal state vanished) and stalls the dashboard's `PIPELINE_FINAL_OPS` logic.

## Recommendation

Two changes, shipped together:

1. **Split the pipeline into a sequential Phase A and a concurrent Phase B**, fanning out the configurable processors in Phase B under a `sync.WaitGroup`.
2. **Serialize only the `kb.inputs.status` read-modify-write** behind a per-record in-process mutex, so concurrent processors keep doing their LLM work in parallel while their sub-millisecond status writes never collide.

The status fix is deliberately the *smallest* correct one. It keeps the frontend, the status schema, durability, and SQL-visible live progress exactly as they are today — no new API, no in-memory status store, no crash-recovery redesign. An in-memory-state alternative was considered and rejected as the most code and the most new risk for the same bug (see Alternatives Considered).

## Non-Goals

- Do **not** change the four mandatory processors (`blocking`, `structure_analyzer`, `chunking`, `extract_metadata`); they keep running sequentially in dependency order.
- Do **not** change the frontend, the status JSON schema, or how the frontend reads progress. It continues to read `kb.inputs.status` from the database.
- Do **not** introduce Redis, a primary-instance status owner, or any multi-instance coordination in this change (see Known Constraints).
- Do **not** add a global LLM concurrency limiter; the provider budget has ample headroom for the configured fan-out.
- Do **not** reorder or merge output tables; each processor keeps writing its own artifacts to its own tables and files.

## Design

### Two-phase pipeline

The controller loop in `control.go` (`handleEvent`) is restructured:

- **Phase A — sequential (unchanged behavior):** `blocking → structure_analyzer → chunking → extract_metadata`. These have a real dependency chain (`chunking` needs `structure_analyzer`, etc.), so they stay serial. The existing stop-check between processors is preserved.
- **Phase B — concurrent:** every configured configurable processor (#5–#14 from the capsule pipeline table) is launched as a goroutine. A `sync.WaitGroup` waits for all of them. Each depends only on blocks (#1) or chunks (#3), both produced in Phase A, so all dependencies are satisfied before Phase B starts. There are no inter-dependencies among them.

When the requested `operation` list (or the default configured set) contains only mandatory processors, Phase B is empty and behavior is identical to today.

### Status write concurrency safety

Each doc processor writes its own status entry into the shared `kb.inputs.status` JSONB column. The status entry records:

- **Start time** — when the processor began (`start_time`)
- **Active/running state** — whether it is still in progress, succeeded, failed, or was stopped by the user (`proc_status`: `"running"`, `"success"`, `"failed"`, `"stopped"`)
- **Current progress** — optional; e.g. `"75% (30/40)"` for chunk-based processors, or absent for single-shot processors
- **Error message** — if failed (`error`)

The controller also writes a `doc_processing` status entry tracking the overall pipeline state (which processor is currently running, overall success/failure). These entries are not separate; they all live in the same JSON array in `kb.inputs.status`.

When run concurrently, Phase B processors all append their entries to this shared array. The naive read-modify-write (read the whole array into Go, append the local entry, write the whole array back) loses writes from sibling processors because each goroutine reads a snapshot that may be stale before it writes.

#### Fix: re-read inside a per-record lock

A sharded in-process mutex striped by `record_id` (256 shards, fixed-size array, no allocation) serializes the status read-modify-write. The critical design rule is: **re-read the database status inside the lock**, never use a locally cached `rec.StatusRaw` that was loaded outside the lock.

Two complementary primitives cover the two store interfaces used by Phase B processors:

| Primitive | Store interface | Pattern |
|---|---|---|
| `updateInputStatusAtomic(ctx, store, id, mutate)` | `DocMetadataStore.UpdateInputMetadata` | `mutate` receives `current` (the DB status just re-read inside the lock) and returns a `DocMetadataUpdate` |
| `(*FixedSizeChunkingService).updateInputStatusLocked(ctx, id, errMsg, build)` | `Store.UpdateInputStatus` | `build` receives `current` and returns the new status JSON string |

Both use the same sharded lock. The LLM calls and artifact writes happen **outside** the lock, so the ~50s of work stays fully concurrent; only the brief status mutation (sub-millisecond) serializes.

**Before (racy):**
```go
rec, _ := store.GetInputRecord(ctx, id)        // stale — read outside the lock
statusRaw, _ := appendXxxStatus(rec.StatusRaw, …) // appends onto potentially-outdated array
store.UpdateInputMetadata(ctx, id, DocMetadataUpdate{StatusRaw: statusRaw}) // clobbers siblings
```

**After (atomic):**
```go
updateInputStatusAtomic(ctx, store, id, func(current string) (DocMetadataUpdate, error) {
    statusRaw, _ := appendXxxStatus(current, …) // current = freshest DB value, re-read inside lock
    return DocMetadataUpdate{StatusRaw: statusRaw}, nil
})
```

This applies to all 23 status-write call sites across Phase B processors (metrics, provisions, scene-blocks, inventory, entity-relation, structured-knowledge, semantic-projections, generate_summaries, generate_topics), and to the controller's own `persistPipelineStatus`.

The lock is correct for a single process only (see Known Constraints). The lock site carries a comment documenting the constraint and the future scale-out path.

### Controller shared-state fixes

Fanning out Phase B breaks assumptions in the current serial loop:

1. **`requestFailed` / `firstErr`** are mutated through shared pointers in `runSingleProcessor`. Replace with per-processor results collected into a slice (or a mutex-guarded accumulator), reduced **after** the `WaitGroup` completes. Do not mutate shared variables from goroutines.
2. **Stop reconciliation** (`control.go` "stop detected after processor" logic) assumes serial order. After the `WaitGroup`, inspect whether the context was stopped (`isCtxStopped`) and classify the run as `stopped` vs `failed` from the collected results. Stop still cancels all Phase B goroutines via the existing shared cancellable context — that mechanism is unchanged.
3. **Do not use `errgroup` with cancel-on-first-error.** A processor that fails must **not** cancel its siblings; each Phase B processor runs to completion independently. (User stop is the only thing that cancels everyone, via context.)

### Buffer lifecycle

The shared block/chunk buffers turn out to need **no production change** — but for non-obvious reasons that must be preserved:

- **Block buffer:** `control.go` clears it immediately after `static_analyzer` (`clearBlockBufferInContext`). This is **intentional and must stay** — `static_analyzer` re-labels lines, so blocks built before it are stale (enforced by `TestControlService_StaticAnalyzerClearsStaleBlockBuffer`). During Phase B the buffer is therefore already `nil`, and each block-consumer (`extract_metrics`, `extract_products`) independently re-blocks from the input file via its own fallback (e.g. `resolveProductBlocks` → `buildBlocks`). That fallback builds a goroutine-local `[]Block`, so concurrent Phase B re-blocking is already safe. The only cost is redundant re-blocking per consumer, which is negligible against LLM latency (possible future optimization: re-block once after `static_analyzer` and repopulate the holder — out of scope).
- **Chunk buffer:** populated by `chunking` (Phase A) via `storeChunksInContext`; never cleared. Phase B chunk-consumers read it via `ChunkBufferFromContext`, which returns the shared `*ChunkBuffer` under the holder's mutex. Concurrent reads are safe **only if no Phase B consumer mutates `buf.Chunks`**. The implementation must verify every chunk-consumer treats the slice as read-only, and a `-race` test must cover concurrent chunk-buffer reads.

### Feature flag

`RUN_DOC_PROCESSOR_CONCURRENT` (`"true"` | `"false"`), read from the environment, default `"true"`.

- `"true"` → Phase B fans out concurrently.
- `"false"` → Phase B runs in the existing sequential loop (kept intact as a fallback).

Defaulting to `"true"` is safe because the per-record status mutex ships in the same change. The flag then serves as a production kill-switch: if an unforeseen concurrency bug appears, set it to `"false"` to fall back to serial without a redeploy.

### Thread-safety audit

`extract_products` (#10) and `extract_structured_knowledge` (#12) are **not** in the set already known to run in parallel. Audit both for package-level mutable state or shared non-reentrant resources before enabling them in Phase B. The other configured processors (`extract_metrics`, `extract_provisions`, `generate_summaries`, `generate_topics`, `generate_scene_blocks`, `extract_semantic_projections`, `extract_entity_relation`, `extract_inventory_items`) already support individual parallel execution.

## Known Constraints

- **Single-instance only.** The per-record mutex coordinates goroutines within one process. If doc-processor is ever scaled to multiple replicas, concurrent status writes across processes are no longer serialized and the lost-update race returns. This is an accepted constraint for now. The future scale-out fix (a DB row lock with `SELECT … FOR UPDATE` + `jsonb_set`, a dedicated primary status-owner instance, or Redis) is out of scope here. The constraint is recorded both at the lock site (code comment) and in the capsule.

## Idempotency / Reprocessing

The `force` flag and any retry path re-run processors on an existing record. Each processor must **replace** its output by `record_id` (upsert or delete-then-insert), not append, so re-runs do not produce duplicate artifacts. `extract-provisions` already upserts (`status = EXCLUDED.status`). Confirm the same for the remaining configured processors as part of implementation; fix any that append.

## Testing Strategy

- **Status race regression test:** drive `persistPipelineStatus` / the processor status writers from many goroutines for one `record_id` and assert every expected entry survives in the final `kb.inputs.status`. This test must fail without the mutex and pass with it.
- **Two-phase ordering test:** assert Phase A runs strictly before any Phase B processor starts, and that Phase B processors overlap (e.g. via injected fakes that record start/finish timestamps).
- **Failure isolation test:** one Phase B processor returns an error; assert the others still complete and the run is classified `failed` with the first error preserved.
- **Stop test:** signal a stop mid-Phase-B; assert all goroutines observe cancellation, the run is classified `stopped`, and the stop flag is cleared.
- **Flag test:** `RUN_DOC_PROCESSOR_CONCURRENT="false"` reproduces today's sequential behavior.
- **Completion-criteria test:** after a concurrent run, every expected processor has a terminal status entry and the record is reported finished.
- Run `go test ./...` from `ChenWeb/server/api/doc-processing` with `-race`.

## Rollout

1. Land the per-record status mutex, the two-phase controller, the shared-state fixes, the buffer-lifecycle change, and the flag in one change, default `"true"`.
2. Verify on staging with representative documents; compare per-record wall-clock against the sequential baseline and confirm no missing status entries.
3. If a concurrency issue surfaces in production, set `RUN_DOC_PROCESSOR_CONCURRENT="false"` as an immediate mitigation while it is diagnosed.

## Spec / Doc Updates

- Update `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md`:
  - Describe the two-phase model (Phase A sequential, Phase B concurrent).
  - Note that the "multiple processors are applied in the order in which they are listed" guarantee applies only to mandatory ordering and Phase A; Phase B order is unspecified.
  - Document `RUN_DOC_PROCESSOR_CONCURRENT` and the single-instance status-lock constraint.

## Alternatives Considered

- **DB-side atomic merge** (`jsonb_set` under `SELECT … FOR UPDATE`): robust regardless of instance count and needs no frontend changes. Slightly more SQL work. Deferred — it is the natural choice when the service scales beyond one instance, at which point it supersedes the in-process mutex.
- **In-memory status, flushed once at pipeline end:** eliminates per-progress DB writes but requires a new status API on doc-processor, a frontend rewrite to read in-memory progress, durable start-markers, startup crash reconciliation, and per-record dedup — the most code and the most new risk, and it introduces multi-instance fragility immediately. Rejected: it solves the same race as the mutex at far higher cost, and progress-write volume is not a bottleneck in a latency-bound, LLM-dominated pipeline.

## Plan
Refer to [1] for the plan document.

## Implementations
Refer to [2] for the implementations.

## References
[1] KnowledgeStore/Capsules/coding-capsules/concurrent-doc-processors/concurrent-doc-processors-plan.md

[2] KnowledgeStore/Capsules/coding-capsules/concurrent-doc-processors/concurrent-doc-processors-impl.md