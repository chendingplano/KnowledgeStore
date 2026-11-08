# Shared ID Manager — Allocate unique IDs with cached database reservations

**Date:** 2026-11-08 \
**Status:** Proposed design; not implemented \
**Scope:** Reusable ID allocation: sequences, provisioning, concurrency, caching, failure handling, conversion of the existing `shared.id_mgr` table, and an example integration for LLM task run IDs. PostgreSQL only. \
**Proposed code root:** `shared/go/api/idmanager/`

## 1. Summary

The ID manager is a reusable shared-library module that hands out numeric IDs. IDs come from named counters, called sequences, stored in the database table `shared.id_mgr`. That table already exists. Today it only supplies activity-log IDs, through a simpler mechanism that this module replaces (section 2.9).

An application chooses which sequence to draw from:

- **The global sequence** (`global`) is set up by the module itself. Any application or module using the same database can draw from it, and every ID it issues is unique across all of them. IDs are issued one at a time, in increasing order.
- **An application's own sequence** is set up by that application, with its own number range, batch size and reuse setting. Its IDs are unique only within that sequence.

To save database work, a sequence can reserve a block of IDs at once and hand them out from memory. The cost is that IDs left in a block are skipped when a process restarts, so numbers can have gaps and, across processes, can be handed out slightly out of order.

When allocation fails, the manager returns 0, which is never a valid ID, together with an error. The caller decides what to do: carry on with 0, retry, or stop.

The first new user is LLM usage logging. Today, tasks record their LLM calls under run IDs borrowed from their own tables, so different tasks can record the same run ID. With this module, every task takes its run ID from one sequence instead (section 2.8).

Nothing described here has been built. Reconcile this document with the implementation when that work is done. There is no OpenSpec contract for the module yet.

## 2. Details

### 2.1 Motivation

Several ChenWeb tasks write their LLM calls to `public.llm_usage_event` with a `run_id`, but each task takes that number from its own source:

| Task | Source of `run_id` | Where |
|---|---|---|
| Search | sequence `kb.search_run_id_seq` | `ChenWeb/server/api/kbhandler/search_run.go` |
| Document processing | `kb.doc_process_runs.id`, via `withRunID` | `ChenWeb/server/api/doc-processing/control.go` |
| Document review | `kb.doc_review_runs.id`, via `withLLMRunID` | `ChenWeb/server/api/doc-reviews/review-document.go` |

These counters are independent, so two tasks can record the same run ID. Using a table's own ID as a run ID is a historical shortcut. The tables' IDs should keep serving their own tables, and run IDs should come from one allocator. More generally, applications need one place to obtain IDs with explicit ranges and batching, rather than each creating its own counter.

The shared library already has an ID table, `shared.id_mgr`, but it offers only a bare counter. It has no bounds, reuse setting, provisioning API or audit fields, and its stored value is not the next free ID (section 2.9). This module extends that table instead of adding a second one.

### 2.2 Database model

The table is **`shared.id_mgr`**. Like other shared-library tables, it lives in the `shared` schema of each application's own database and is reached through `ApiTypes.SharedDBHandle`, so ChenWeb and tax have separate counters. The design keeps the existing table and the types of its existing columns, renames two columns, and adds the rest:

| Column | Type and default | Origin | Meaning |
|---|---|---|---|
| `id_name` | `VARCHAR(128) PRIMARY KEY` | existing | Nonempty sequence name of at most 128 characters; identifies the namespace. |
| `id_desc` | `TEXT NOT NULL` | existing | Description of what the sequence identifies. |
| `next_id` | `BIGINT NOT NULL` | renamed from `crt_value` | First ID not yet reserved. `max_id + 1` means a non-reusing sequence is exhausted. |
| `start_id` | `BIGINT NOT NULL DEFAULT 1` | new | Inclusive lower bound. |
| `max_id` | `BIGINT NOT NULL DEFAULT 9223372036854775806` | new | Inclusive upper bound; at most one below the largest 64-bit value. |
| `allocate_size` | `INTEGER NOT NULL DEFAULT 1` | new | Preferred number of IDs reserved on a cache refill. |
| `allow_reuse` | `BOOLEAN NOT NULL DEFAULT FALSE` | new | Whether allocation may cycle back to `start_id`. |
| `creator` | `TEXT NOT NULL` | renamed from `caller_loc`, widened from `VARCHAR(20)` | Identity that provisioned the sequence: the manager's requester or the migration that inserted the row. Old rows hold the code location that created them. |
| `last_requester` | `TEXT NULL` | new | Identity that most recently reserved a database block. |
| `created_at` | `TIMESTAMP DEFAULT CURRENT_TIMESTAMP` | existing | Creation time. |
| `updated_at` | `TIMESTAMP DEFAULT CURRENT_TIMESTAMP` | existing | Time of the latest database reservation. The old code never set it, so on old rows it equals `created_at` until the first new reservation. |

Enforce `start_id >= 1`, `max_id >= start_id`, `max_id <= 9223372036854775806`, `allocate_size >= 1`, `start_id <= next_id <= max_id + 1`, and `next_id <= max_id` when `allow_reuse` is true. Capping `max_id` one below the largest 64-bit value lets `max_id + 1` be stored, so no separate exhausted flag is needed and no addition in the algorithm can overflow. IDs are positive, which leaves 0 free to signal failure.

Provisioning sets `next_id` to `start_id`. Exhaustion describes database reservations only; a process may still hand out IDs from a block it reserved earlier.

Requests for unknown names return an error rather than silently creating a new namespace after a spelling mistake. Changing `id_desc` or `allocate_size` is safe at any time; a new size applies from the next refill. Changing `start_id`, `max_id` or `allow_reuse`, resetting `next_id`, or deleting a sequence is unsafe while any process may hold a reserved block, and is outside the API.

### 2.3 Choosing a sequence

| Choice | Use when | What you get |
|---|---|---|
| `global` | IDs must be unique across the modules and applications sharing the database, and no special range is needed. | Provisioned by the module's migration with `start_id=1`, `allocate_size=1` and `allow_reuse=false`. IDs are issued one at a time in increasing order, with gaps only after failures. Each ID costs one database transaction. |
| Application sequence | The application wants its own numbering: a start value, an upper bound, batching to reduce database writes, or reuse within a finite range. | Provisioned by the application through `Provision` (section 2.4). IDs are unique only within that sequence. Examples: `activity_log_id` (section 2.9) and `llm_task_run` (section 2.8). |

A native PostgreSQL sequence also produces unique numbers. The ID manager adds named provisioning with descriptions and audit fields, contiguous batches (`Generate`), application-side caching, an explicit failure value, and one Go API across applications.

### 2.4 Proposed Go interface

The following signatures describe the intended interface, not existing symbols:

```go
const GlobalSequence = "global"

type Range struct {
    FirstID int64
    NumIDs  int64
}

type Sequence struct {
    Name         string // id_name
    Desc         string // id_desc
    StartID      int64  // 0 means 1
    MaxID        int64  // 0 means the column default
    AllocateSize int    // 0 means 1
    AllowReuse   bool
}

func New(db *sql.DB, requester string) (*Manager, error)
func (m *Manager) Provision(ctx context.Context, seq Sequence) error
func (m *Manager) Next(ctx context.Context, idName string) (int64, error)
func (m *Manager) Generate(ctx context.Context, idName string, numIDs int64) (Range, error)
```

`New` takes an existing centralized pool, normally `ApiTypes.SharedDBHandle`, and does not open its own. Create one manager per process and share it: each manager keeps its own cache, so extra managers abandon more IDs on restart. `requester` identifies the application or worker reserving blocks, for example `chenweb-api@<host>:<pid>`. It is recorded in `last_requester`, and in `creator` for sequences this manager provisions. End-user attribution belongs on task and usage records, not here.

`Provision` creates a sequence if it does not exist, with `next_id` set to its start and `creator` set to the requester. If the sequence exists with the same `StartID`, `MaxID` and `AllowReuse`, it changes nothing and returns nil, so an application can call it at every startup. If those settings differ, it returns an error and changes nothing. It never alters `id_desc` or `allocate_size` of an existing sequence.

`Next` returns one ID; Go has no default arguments, so it is the convenience form of `Generate` with a count of one. `Generate` requires a positive count and returns exactly that many contiguous IDs. For example, `{FirstID: 101, NumIDs: 3}` represents 101, 102 and 103. It never returns a partial result.

**Failure.** On any failure, `Next` returns `0` and `Generate` returns `Range{}` (first ID 0, count 0), each with a non-nil error. Zero is never a valid ID. The manager logs the failure; the caller decides whether to continue with 0, retry, or stop. Errors distinguish invalid input, unknown sequence, provisioning conflict, exhausted or insufficient range, cancellation, and database failure, and can be tested with `errors.Is`.

### 2.5 Reservation and cache algorithm

For each sequence, a manager keeps a next cached ID and a remaining count, guarded by a per-sequence lock that covers both handing out cached IDs and refilling. Different sequences proceed independently. A caller waiting for the lock must be able to give up when its context is cancelled. Go's `sync.Mutex` cannot do this, so use a cancellable lock such as a one-slot channel.

For a request of `N` IDs:

1. Validate the name and that `N` is positive, then acquire the sequence lock, giving up if the context is cancelled.
2. If at least `N` cached IDs remain, return them as one contiguous range, advance the cursor by `N`, and reduce the remaining count.
3. Otherwise begin a database transaction and read the sequence row with `SELECT ... FOR UPDATE`. A transaction without the row lock is insufficient: concurrent processes could otherwise read the same counter.
4. Let `V` be the row's `next_id` and `C = max_id − V + 1` the IDs left before the upper bound (0 when exhausted). If `C < N`:
   - For a non-reusing sequence, return an insufficient-range error without updating the row.
   - For a reusing sequence, return an error without updating the row if `N` exceeds the whole range (`max_id − start_id + 1`). Otherwise wrap (section 2.6): set `V = start_id` and `C` to the whole range.
5. Reserve `M = min(max(allocate_size, N), C)` IDs, from `V` through `V + M − 1`.
6. Set `next_id` to `V + M`. For a reusing sequence whose block ends at `max_id`, set it to `start_id` instead. For a non-reusing sequence, `V + M = max_id + 1` marks exhaustion.
7. Update `last_requester` and `updated_at` in the same transaction, then commit.
8. Only after a successful commit, replace any old insufficient cache: return the first `N` reserved IDs and cache the remaining `M − N`. The old remainder is abandoned and, for a non-reusing sequence, never reclaimed.
9. Release the lock on every exit path.

If a refill fails, nothing from the attempted reservation is returned or cached, and the call returns `0` or `Range{}` with an error. An existing insufficient cache stays available for a later, smaller request. If it is uncertain whether the commit succeeded, discard the reservation; a gap is safer than issuing IDs whose reservation is unconfirmed.

Example with `allocate_size=5`:

```text
Database next_id: 1
Next()          -> reserves 1–5; returns 1; caches 2–5; database next_id=6
Generate(...,3)  -> returns 2–4; caches 5; database unchanged
Generate(...,2)  -> reserves 6–10; returns 6–7; caches 8–10
                   old cached ID 5 is abandoned
```

The row lock prevents overlapping reservations across processes. The per-sequence lock prevents a manager from handing out the same cached ID twice. Separate managers on the same database are safe because each obtains its own committed, disjoint blocks.

### 2.6 Reuse policy

`allow_reuse=true` means cycling through a finite range. It deliberately permits returning numbers that were issued previously. It does not establish that old references have been deleted or that other processes have finished consuming older blocks.

If reuse is enabled and fewer than `N` IDs remain before the upper bound, allocation wraps to `start_id` under the row lock and abandons that tail. A batch never crosses the wrap boundary. A request larger than the whole configured range returns an error without changing the counter. Reuse therefore provides neither historical uniqueness nor uniqueness among outstanding IDs.

The `global`, `activity_log_id` and `llm_task_run` sequences must always have `allow_reuse=false`.

### 2.7 Guarantees and limits

| Property | Contract |
|---|---|
| Uniqueness | Within one sequence in one database, with reuse disabled and no counter reset. `global` is one sequence, so its IDs are unique across all its users. |
| Batch result | Exactly the requested number of contiguous IDs, or a failure. |
| Failure result | `0` from `Next`, `Range{}` from `Generate`, always with an error. Zero is never a valid ID. |
| Restart behavior | Unused cached reservations are lost and never reclaimed when reuse is disabled. |
| Ordering | Numbers increase within each reserved block. With `allocate_size=1`, as for `global`, IDs increase in reservation order. The order in which callers in different processes receive IDs is not guaranteed. |
| Numbering gaps | Expected after crashes, abandoned remainders, failed delivery, and uncertain commits. |
| Cross-sequence uniqueness | Not provided. Two names can both issue ID 1. |
| Cross-database uniqueness | Not provided. Each application database has its own `shared.id_mgr`. |
| Audit precision | `last_requester` tracks database reservations, not every cache-served request. |

Uniqueness also depends on preserving counter history during database administration. Restoring an older database snapshot while newer IDs remain in external records requires recovery coordination before allocation resumes.

### 2.8 Example: LLM task run IDs

Every LLM call is logged in `public.llm_usage_event`. Its `run_id` groups the calls of one task execution: calls from the same execution share a run ID, and different executions have different run IDs. Under this design every task takes its run ID from one sequence, `llm_task_run`, instead of from its own table. The tables' own IDs (`kb.doc_process_runs.id`, `kb.doc_review_runs.id`) keep their meaning in those tables but are no longer written as run IDs.

How a task uses the module:

- Call `Next(ctx, "llm_task_run")` once when an execution starts. Carry the ID in the context and in queued messages, and use it for every LLM call in the execution, including parallel calls, embeddings, model fallbacks, provider retries and tool loops.
- Store the ID on the execution's own record, for example in a new column on `kb.doc_process_runs`. Queue redelivery and pause/resume then reuse it, and pages can find an execution's LLM calls. A new execution, including a user-requested rerun, gets a new ID.
- If allocation fails, log it and continue with run ID 0; `ChenWeb/server/api/llmusage/sink.go` stores a run ID of 0 as NULL. The LLM call itself is not failed. Do not retry allocation partway through an execution, because calls before and after the retry would carry different run IDs.

`llm_task_run` is an application sequence. ChenWeb provisions it in a migration so that it can start above the largest historical `llm_usage_event.run_id`.

Switching ChenWeb over touches more than the three writers listed in section 2.1:

- Peak-hours hold events take their run ID from the document-processing context (`ChenWeb/server/api/doc-processing/task_engine_policy.go`) and must take the new run ID.
- The "peak waiting" filter in `ChenWeb/server/api/kbhandler/handler.go` matches hold events to `kb.doc_process_runs.id` through `run_id`. It must match through the stored run ID instead.
- `alarms_errors` de-duplicates on `(run_id, kind)`. Routing alarms write `kb.doc_process_runs.id` and the usage sink writes the usage run ID, both with kind `missing_user_id`. After the switch these are different ID spaces in one index, so the two alarm sources must use the same run ID or distinct kinds.
- The LLM usage logs page filters by `run_id`. Operators who paste a document-processing run ID there will need the stored run ID instead.

At cutover, stop the old writers, provision `llm_task_run` above the highest historical run ID, and switch every writer before traffic resumes. Keep ambiguous historical run IDs as legacy data; this module cannot tell which task an old collided or missing value belonged to.

### 2.9 Moving from the current `shared.id_mgr`

**Current users.** All code that uses the table is in the shared library; ChenWeb and tax never reference it directly.

| Code | Callers | Status |
|---|---|---|
| `sysdatastores.NextActivityLogID`, which reserves blocks of 1000 under `activity_log_id` through `NextIDBlock` (`shared/go/api/sysdatastores/table-idmgr.go`) | 38 call sites in `auth/email.go`, `auth/github.go`, `RequestHandlers` and `EchoFactory`. Started by `libmanager.InitLib`, which only ChenWeb `deepdoc` and tax `mirai` call. | The only live user |
| `InMemStore.NextManagedID`, with keys from `[system_ids]` in `shared/libconfig.toml` (`shared/go/api/stores/mem-store.go`) | None | Unused. Its `prompt_store_id` row does not exist in either database, and `InMemStore` does nothing else. |
| `sysdatastores.AddOneID` | None | Unused |
| `sysdatastores.UpsertActivityLogIDDef` | `libmanager.InitLib` | Creates the `activity_log_id` row |

Current rows, as of 2026-11-08:

| Database | `activity_log_id` `crt_value` | Highest activity-log ID issued |
|---|---|---|
| ChenWeb (`miner`) | 43000 | 42999 |
| tax | 14000 | 14001 |

**The stored value is not the next free ID.** The old code reserves a block with `UPDATE ... SET crt_value = crt_value + n RETURNING crt_value`, which returns the counter after adding `n`. The activity log then issues IDs from that value minus 1 through that value plus 998, and `InMemStore` would have issued that value through that value plus 999. tax already holds ID 14001, above its stored 14000. Converting the column must therefore set `next_id = crt_value + 1000`; using `crt_value` unchanged would issue duplicate IDs. Both old code paths reserve 1000 at a time, and only `activity_log_id` rows exist today.

**Migration.** One shared Goose migration in `shared/go/api/goose/shared_migrations/` converts the table. It must work whichever runs first, the migration or `CreateSysTables`, because both orders happen today: several ChenWeb programs (doc-service, doc-processor and others) run shared migrations without calling `CreateSysTables`, and `deepdoc` and `mirai` call `CreateSysTables` only when `NeedCreateTables()` is true. The migration:

1. Creates `shared.id_mgr` in the new shape if it does not exist.
2. If the table still has the old shape (a `crt_value` column), converts it in a conditional `DO` block:
   - rename `crt_value` to `next_id` and add 1000 to every row;
   - rename `caller_loc` to `creator` and widen it to `TEXT`;
   - add the new columns;
   - set `allocate_size = 1000` for `activity_log_id`.
3. Adds the constraints from section 2.2.
4. Inserts the `global` row if it is missing.

The migration names `shared.id_mgr` directly; the table name is no longer configurable.

**Shared-library code changes**, made in the same change as the module:

- `CreateSysTables` stops creating `id_mgr`, so the migration is the only definition of the table.
- `NextActivityLogID` keeps its signature, so its 38 call sites do not change, but takes IDs from the module's `activity_log_id` sequence. `libmanager.InitLib` provisions that sequence with `Provision` (`AllocateSize` 1000) instead of calling `UpsertActivityLogIDDef`.
- Code with no remaining callers in shared, ChenWeb or tax is removed:
  - `sysdatastores`: `NextIDBlock`, `AddOneID`, `UpsertActivityLogIDDef`, `CreateIDMgrTable` and `IDMgrDef`;
  - `InMemStore` as a whole (`shared/go/api/stores/mem-store.go`), with its start and stop calls in `InitSharedStores` and `libmanager`;
  - `ApiTypes`: `IDMgrDef`, `IDRecordDef`, `SystemIDs`, `IDStartValue`, `IDIncValue`, `TableNameIDMgr` and `GetIDMgrTableName`;
  - the `id_start_value`, `id_inc_value`, `table_name_id_mgr` and `[system_ids]` settings in `shared/libconfig.toml`.
- The old code's MySQL branches go with it. Both applications use PostgreSQL.

**Deployment.** Once the migration has run, a `deepdoc` or `mirai` built before the change can no longer get activity-log IDs, because it still queries `crt_value`. In each environment, deploy the new builds of those two programs at the same time as the migration. Any of the application's programs may be the one that runs it at startup.

**Leftovers in tax.** The tax database also has `public.id_mgr` (counter 67000) and `public.activity_log`, left from before the `shared` schema existed. No code reads them, and the last write was on 2026-03-23. The migration does not touch them. Because `shared.activity_log` restarted at 10999, activity-log IDs overlap between the two tables. Dropping the old tables is a separate decision.

### 2.10 Implementation and validation work

Create and convert the table in the shared migration described in section 2.9; applications apply shared migrations at startup through `goose.RunSharedMigrations`. Use the centralized database pool and `loggerutil.CreateDefaultLogger` with a unique location. Log provisioning, reservations, exhaustion and failures with sequence and requester identities; do not log every cache hit.

Validation should include actual PostgreSQL transactions with independent connections and managers, as well as Go race checks. Cover:

- concurrent allocation, cache refill and consumption, and different names;
- batches larger than the allocation size, insufficient cache tails, and restart gaps;
- cancellation while waiting for the lock and during database work;
- transaction rollback and uncertain commit handling;
- final-ID exhaustion and cycling behavior;
- provisioning that is repeated with the same settings, or conflicts with existing settings;
- the failure values `0` and `Range{}`, always with an error;
- the migration on a fresh database, on the old shape (`next_id = crt_value + 1000`), and after `CreateSysTables` created the old shape;
- activity-log IDs after the switch, which must be above every ID issued before it.

Verify that a failed refill does not publish a new block. LLM integration tests must separately cover:

- a shared run ID across an execution's calls;
- a new ID on rerun, and the same ID after queue redelivery and resume;
- continuing with run ID 0 when allocation fails;
- the peak-waiting filter and alarm de-duplication after the switch.

After implementation, document and catalogue the reusable module under `KnowledgeStore/doc-repo/modules/` and `kb.reusable_modules`. Update the affected document-processing run-ID documentation, shared LLM API documentation, and task propagation tests. Update `shared/CLAUDE.md`, which documents the removed `libconfig.toml` settings. Run shared-library tests, synchronize the Go workspace if dependencies change, and verify that ChenWeb and tax build. This design document adds no implementation or test results.

## 3. Known limitations

- Allocation does not provide a task registry, execution status tracking, or automatic run-ID propagation.
- IDs are unique only within one sequence in one database; the caller chooses the sequence.
- Cached reservations trade gapless numbering and overall hand-out order for fewer database writes.
- The `global` sequence costs one database transaction per ID.
- A failed allocation returns 0. Callers that continue with it accept records without a usable ID.
- Reuse intentionally allows duplicates and is unsuitable for trace-like identifiers.
- `last_requester` cannot identify every consumer when IDs are served from cache.
- The module is PostgreSQL only; the old ID code's MySQL support is removed.
- Historical LLM run-ID collisions and missing values need a separate evidence-based migration.
