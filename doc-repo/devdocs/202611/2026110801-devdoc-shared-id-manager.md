# Shared ID Manager — Allocate unique IDs with cached database reservations

**Date:** 2026-11-08 \
**Status:** Proposed design; not implemented \
**Scope:** Reusable ID allocation, concurrency, caching, and integration with LLM task run IDs. \
**Proposed code root:** `shared/go/api/idmanager/`

## Summary

The proposed ID manager gives applications one place to obtain numeric IDs. Each named sequence has its own counter in `shared.id_manager`. An application can reserve several IDs at once and serve later requests from memory, reducing database traffic. Applications using the same sequence in the same database receive distinct IDs when reuse is disabled.

For LLM usage logging, every task type will use one sequence, `llm_task_run`. Each task execution obtains an ID once and carries it through all of its LLM calls. This addresses collisions between independent task counters. Task entry points and workers must also propagate the ID consistently to address missing run IDs.

Caching permits gaps and IDs can be returned out of numerical order across processes. Restarting a process abandons its unused reservations; those IDs are never reclaimed when reuse is disabled.

This document records the reviewed proposal, including recommended amendments. No allocator API, migration, or application integration described here has shipped. It should be reconciled with the implementation when that work is completed. There is no dedicated OpenSpec contract for this module at the time of writing.

## Details

### Motivation and existing behavior

Search currently allocates usage-log run IDs from `kb.search_run_id_seq` in `ChenWeb/server/api/kbhandler/search_run.go`. Document processing uses `kb.doc_process_runs.id` through `withRunID` in `ChenWeb/server/api/doc-processing/control.go`. Independent sources can issue the same number, even though both numbers are written to `public.llm_usage_event.run_id`.

Search continues with zero if allocation fails. Document processing also continues if its run record cannot be created. `ChenWeb/server/api/llmusage/sink.go` stores nonpositive run IDs as NULL. A reusable allocator alone does not change these behaviors; application integration is a separate part of the fix.

### Database model

All reads and updates target **`shared.id_manager`**. The reference to `public.id_manager` in the original allocation algorithm is a naming error.

| Column | Proposed type and default | Meaning |
|---|---|---|
| `id_name` | `TEXT PRIMARY KEY` | Nonempty sequence name; identifies the namespace. |
| `id_desc` | `TEXT NOT NULL DEFAULT ''` | Description of what the sequence identifies. |
| `next_id` | `BIGINT NOT NULL DEFAULT 1` | First ID not yet reserved, except when exhausted. |
| `start_id` | `BIGINT NOT NULL DEFAULT 1` | Inclusive lower bound. |
| `max_id` | `BIGINT NOT NULL DEFAULT 9223372036854775807` | Inclusive upper bound. |
| `allocate_size` | `INTEGER NOT NULL DEFAULT 1` | Preferred number of IDs reserved on a cache refill. |
| `allow_reuse` | `BOOLEAN NOT NULL DEFAULT FALSE` | Whether allocation may cycle back to `start_id`. |
| `creator` | `TEXT NOT NULL` | Identity that provisioned the sequence. |
| `last_requester` | `TEXT NULL` | Identity that most recently reserved a database block. |
| `exhausted` | `BOOLEAN NOT NULL DEFAULT FALSE` | Whether the final ID has been reserved without reuse. |
| `created_at` | `TIMESTAMPTZ NOT NULL DEFAULT now()` | Creation time. |
| `last_allocated_at` | `TIMESTAMPTZ NULL` | Time of the latest database reservation. |

The last three fields are recommended additions to the requested schema. `exhausted` allows issuing `int64_max` without storing the unrepresentable value `int64_max + 1`.

Enforce `start_id >= 1`, `max_id >= start_id`, `allocate_size >= 1`, and `start_id <= next_id <= max_id`. IDs are positive. Sequence provisioning initializes `next_id` to `start_id` explicitly; the independent column defaults do not do this for a custom start value.

When `exhausted=true`, `next_id` remains at `max_id` and cannot be allocated again from the database. An exhausted sequence must have `allow_reuse=false`. Exhaustion describes database reservations; a process may still return IDs from an earlier reservation.

Provision sequences explicitly. Requests for unknown names return an error rather than silently creating a new namespace after a spelling mistake. Sequence deletion, counter resets, and allocation-setting changes after first use are outside the normal API. In particular, live processes may retain reservations that make a reset unsafe.

### Proposed Go interface

The following signatures describe the intended interface, not existing symbols:

```go
type Range struct {
    FirstID int64
    NumIDs  int64
}

func New(db *sql.DB, requester string) (*Manager, error)
func (m *Manager) Next(ctx context.Context, idName string) (int64, error)
func (m *Manager) Generate(ctx context.Context, idName string, numIDs int64) (Range, error)
```

`Next` is the convenience API for the default count of one; Go has no default arguments. `Generate` requires a positive count and returns exactly that many contiguous IDs. For example, `{FirstID: 101, NumIDs: 3}` represents 101, 102, and 103. It never returns partial results.

The manager receives an existing centralized database pool and does not open its own connection pool. The trusted requester identity identifies the application or worker reserving blocks. End-user attribution belongs on task and usage records. `creator` is supplied when provisioning the sequence and is not overwritten by allocation.

Errors distinguish invalid input, unknown sequence, exhausted or insufficient range, and database failures. No allocation failure returns zero as a successful ID.

### Reservation and cache algorithm

Each manager owns a cache scoped to its database. Each sequence entry stores a next cached ID and remaining count, protected by a mutex. The mutex covers both consumption and refill. Different sequence names can proceed independently.

For a request of `N` IDs:

1. Validate the name and positive count, then acquire the sequence mutex. Respect cancellation while waiting or performing database work.
2. If at least `N` cached IDs remain, return that contiguous range and reduce the remaining count. Advance the cached cursor only if IDs remain, avoiding overflow when consuming the final possible ID.
3. Otherwise begin a database transaction and read the sequence row with `SELECT ... FOR UPDATE`. A transaction without a row lock is insufficient: concurrent processes could otherwise read the same counter.
4. Let `V` be the row's `next_id`. Check exhaustion and available capacity before computing any potentially overflowing addition. For a non-reusing sequence, fewer than `N` available IDs produces an error and no counter update.
5. Set the reservation size to `M = min(max(allocate_size, N), available capacity)`. Reserve the inclusive range beginning at `V` with length `M`.
6. If the reservation ends below `max_id`, store the following ID as `next_id`. If it ends at `max_id`, set `exhausted=true` for a non-reusing sequence. A reusing sequence instead sets its next counter to `start_id`.
7. Update `last_requester` and `last_allocated_at` in the same transaction, then commit.
8. Only after successful commit, replace any old insufficient cached remainder. Return the first `N` reserved IDs and cache the remaining `M-N` IDs. An abandoned old remainder is never reclaimed for a non-reusing sequence.
9. Release the mutex on every exit path.

If refill fails, no IDs from that attempted reservation are returned or cached. An existing insufficient cache can remain available for a later smaller request. If commit success is uncertain, discard the attempted reservation; allowing a gap is safer than issuing IDs whose reservation is unconfirmed.

Example with `allocate_size=5`:

```text
Database next_id: 1
Next()          -> reserves 1–5; returns 1; caches 2–5; database next_id=6
Generate(...,3)  -> returns 2–4; caches 5; database unchanged
Generate(...,2)  -> reserves 6–10; returns 6–7; caches 8–10
                   old cached ID 5 is abandoned
```

The database lock prevents overlapping reservations across processes. The local mutex prevents duplicate consumption within a manager. Multiple managers using the same database remain safe because each obtains its own committed, disjoint blocks.

### Reuse policy

`allow_reuse=true` means cycling through a finite range. It deliberately permits returning numbers that were issued previously. It does not establish that old references have been deleted or that other processes have finished consuming older blocks.

If reuse is enabled and fewer than `N` IDs remain before the upper bound, allocation wraps to `start_id` under the row lock and abandons that tail. A batch never crosses the wrap boundary. A request larger than the whole configured range returns an error without changing the counter. Reuse therefore provides neither historical uniqueness nor uniqueness among outstanding IDs.

The `llm_task_run` sequence must always have `allow_reuse=false`.

### Guarantees and limits

| Property | Contract |
|---|---|
| Uniqueness | Within one sequence in one backing database, with reuse disabled and no counter reset. |
| Batch result | Exactly the requested number of contiguous IDs, or an error. |
| Restart behavior | Unused cached reservations are lost and never reclaimed when reuse is disabled. |
| Ordering | Numbers increase within each reserved block; return-time ordering across managers is not guaranteed. |
| Numbering gaps | Expected after crashes, abandoned remainders, failed delivery, and uncertain commits. |
| Cross-sequence uniqueness | Not provided. Two names can both issue ID 1. |
| Cross-database uniqueness | Not provided. Installing the same module in separate databases does not share counters. |
| Audit precision | `last_requester` tracks database reservations, not every cache-served request. |

Uniqueness also depends on preserving counter history during database administration. Restoring an older database snapshot while newer IDs remain in external records requires recovery coordination before allocation resumes.

### LLM task integration

All LLM-producing task types sharing the usage-event namespace must request `llm_task_run` from the same backing database. Names such as separate search and document-processing sequences would preserve the existing collision problem.

Allocate once when creating an execution, persist the ID with that execution, and carry it through contexts and queued messages. Parallel calls, embeddings, model fallbacks, provider retries, and tool loops within the execution retain the ID. Queue redelivery and pause/resume recover the persisted ID. A new execution, including a user-requested rerun, receives a new ID.

Keep existing domain IDs, such as `kb.doc_process_runs.id`, for their existing relationships. Map them explicitly to the canonical usage run ID rather than silently changing the meaning of existing foreign keys and context values.

Task startup must fail with a logged error when allocation fails. Shared LLM entry points must validate that a canonical run ID exists before making a provider request and reject conflicting identities. These integration requirements are separate from implementing the generic allocator.

At cutover, quiesce old writers and initialize the new sequence above the highest historical usage-event run ID. All writers must switch to the canonical allocator before traffic resumes. Preserve ambiguous historical IDs as legacy data; this module cannot infer which task an old collided or missing value belonged to.

### Implementation and validation work

Implement the schema through the shared Goose migration track and the workspace's startup migration path. Use the existing centralized database pool and `loggerutil.CreateDefaultLogger` with a unique location. Log provisioning, reservations, exhaustion, and database failures with sequence and requester identities; do not add a log entry for every cache hit.

Validation should include actual PostgreSQL transactions with independent connections and managers, as well as Go race checks. Cover concurrent allocation, cache refill and consumption, different names, batches larger than the allocation size, insufficient cache tails, restart gaps, cancellation, transaction rollback, uncertain commit handling, final-ID exhaustion, and cycling behavior. Verify that a failed refill does not publish a new block. LLM integration tests must separately cover shared identity across calls, reruns, queue redelivery, and prevention of calls with missing IDs.

After implementation, document and catalogue the reusable module under `KnowledgeStore/doc-repo/modules/` and `kb.reusable_modules`. Update the affected document-processing run-ID documentation, shared LLM API documentation, and task propagation tests. Run shared-library tests, synchronize the Go workspace if dependencies change, and verify dependent applications build. This design document adds no implementation or test results.

## Known limitations

- Allocation does not provide a task registry, execution status tracking, or automatic run-ID propagation.
- IDs are unique within a named sequence and database; the caller chooses the correct namespace.
- Cached reservations trade gapless numbering and global return-time ordering for fewer database writes.
- Reuse intentionally allows duplicates and is unsuitable for trace-like task identifiers.
- `last_requester` cannot identify every consumer when requests are served from cache.
- Historical LLM run-ID collisions and missing values need a separate evidence-based migration.
