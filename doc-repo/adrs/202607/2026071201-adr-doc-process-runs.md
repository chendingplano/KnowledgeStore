# ADR 2026071201 — Doc Processing Pipeline: `kb.doc_process_runs` — First-Class Run Table

**Date:** 2026-07-12 \
**Status:** Accepted \
**Component:** ChenWeb — `server/api/doc-processing`, `project_migrations` \
**Authors:** Chen Ding \
**Tags:** doc processor, database, schema, run tracking, logging

---

## Change Logs

* 2026/07/12, ADR Created. Identifies the missing run-identity problem in
  `kb.doc_proc_logs` and proposes a `kb.doc_process_runs` table, modeled on
  `kb.doc_review_runs` (ADR 2026062804 [1]), plus a `run_id` column on
  `kb.doc_proc_logs`.

* 2026/07/12, Added DP7 (`parameters` column): pipelines are kicked off both
  automatically (`ChenWeb/server/cmd/doc-processor`'s JetStream subscription)
  and manually (dashboard → `POST /api/v1/jetstream/events` → `PublishEvent`,
  `jetstreamhandler/handler.go:650` [11]), and either path can set per-run
  execution knobs (`force`, `force_clear`, `operation`/`operations`,
  `filename`). Today those values are parsed fresh into `LineFileGeneratedEvent`
  (`event.go:17` [12]) on every invocation and never persisted anywhere.
  `kb.doc_process_runs` now records the *effective* (post-default) values.

* 2026/07/12, Implemented via TDD (migration `20260712000001_create_kb_doc_process_runs.sql`;
  `doc_process_run_store.go` (`CreateDocProcessRun`/`CloseDocProcessRun`);
  `withRunID`/`runIDFromContext` in `control.go`; `handleEvent` wiring;
  `run_id` added to `insertDocProcLog`/`DocProcLogRow`/`DocProcLogFilter`/`ListDocProcLogs`).
  **Divergences from plan:**
  - The run is closed **only** in `handleEvent`'s existing deferred outcome
    block (not also in `logPipelineFinish` as DP4 suggested) — the deferred
    block already runs on every return path (success/failed/stopped) and
    already computes the single authoritative status classification, so a
    second close site in `logPipelineFinish` would only risk a double-write.
  - `mode` is not threaded into `handleEvent` as an explicit parameter from
    `handleDefaultSubjectEvent`/`HandleStartDocProcessingEvent`. Instead
    `handleEvent` calls `s.docProcessorMode()` directly at the run-creation
    point, which already returns the correct effective mode for both call
    paths (env-var-derived), avoiding a signature change to `handleEvent`.
  - `ControlService.RunStore` is a new nil-tolerant field (mirrors
    `EventStore`/`StopStore`): unset in existing tests/call sites, so no
    pre-existing test construction had to change.
  **Deferred to follow-on work (unchanged from the original plan):**
  - New REST endpoints, dashboard run-history UI.
  - Extending `run_id` to `kb.input_proc_status` or `kb.chunks`.
  - `table-kb-doc-proc-logs.md` / `table-kb-doc-process-runs.md` schema docs
    under `KnowledgeStore/table-schemas/`.
  - Stamping requester identity into `PublishEvent` (DP7's manual/automatic
    provenance gap).

---

## Context

### The problem: `kb.doc_proc_logs` has no invocation-grouping key

`kb.doc_proc_logs` (migration `20260527000020_create_kb_doc_proc_logs.sql` [2])
records one row per LLM call and one summary row per processor, tagged with
`record_id`, `doc_proc_name`, `entry_type`, and `create_time`. It has **no
column that identifies which pipeline invocation a row belongs to**.

This is not a problem the first time a record is processed. It becomes one
the moment a record is processed more than once, which is routine:

- Auto Mode reprocesses a record whenever a new `kb.pdf.start-doc-processing`
  event names it (`force` defaults to `true` — see `+CAPSULE.md` §2 [3]).
- Dev Mode explicitly targets records for reprocessing via `record_ids` /
  `all: "failed-procs"`, optionally restricted to `failed-proc-only` (§2.1
  [3]).
- ADR 2026071002 [4] (`force_clear`) and ADR 2026071101 [5] (looping a
  processor N times per invocation) both assume repeated, deliberate re-runs
  of the same processor over the same record are normal operational
  behavior, not an edge case.

Concretely: debugging `extract_metrics` on record 4821 by force-reprocessing
it three times while iterating on a prompt produces three interleaved sets of
`llm_call` rows (one per chunk, per attempt) plus three `doc_proc_summary`
rows, all sharing `record_id = 4821` and `doc_proc_name = 'extract_metrics'`,
distinguishable — if at all — only by eyeballing gaps in `create_time`.
`ListDocProcLogs` (`doc_proc_log_store.go` [6]) can filter by `record_id` and
`doc_proc_name`, but there is no filter for "just this one invocation."

Phase B concurrency (`+CAPSULE.md` §7.3 [3]) compounds this along a second
axis: within a *single* invocation, multiple configurable processors log
concurrently, so `doc_proc_name` is needed just to separate processors
running at the same moment. Reprocessing adds a third axis — the same
processor, same record, different point in time — that today has **no**
column to separate on at all.

### Why this matters more now

- Per-run cost/latency and DeepSeek cache-hit analysis
  (`prompt_cache_hit_tokens` / `prompt_cache_miss_tokens`, migration
  `20260627000001_add_doc_proc_logs_cache_tokens.sql`, ADR 2026062501 /
  2026062701 [7]) is currently only aggregable per `(record_id,
  doc_proc_name)`, not per invocation — you cannot ask "did the change I just
  shipped improve cache hits on *this* run" without manually bounding
  `create_time`.
- ADR 2026071101's proposed N-times-per-processor loop [5] would multiply the
  number of `llm_call` rows per invocation, making manual timestamp-gap
  disambiguation materially harder.
- ADR 2026071002's merge logic [4] makes each individual run's *contribution*
  meaningful (what did *this* merge run add vs. absorb), which is exactly the
  kind of question a run-scoped log view answers and a flat log does not.

### What already exists, and why it doesn't solve this

- `kb.events` [8] records the JetStream message lifecycle
  (`received`/`consumed`), not a per-record pipeline execution. In Auto Mode
  one event maps to one record, but in Dev Mode `HandleStartDocProcessingEvent`
  (`control.go:150` [9]) fans one event out into **N** concurrent
  `handleEvent` calls, one per matched record — so `kb.events` is coarser
  than the thing we need to identify.
- `kb.inputs.status` [10] is a JSON array mutated **in place** per operation
  — it holds the *latest* status for each processor, not a history of
  invocations. A record reprocessed five times has the same `status` shape
  as one processed once; the prior four attempts leave no trace there.
- Unlike the document-review pipeline (ADR 2026062804 [1]), doc processing
  has no separate "request" object representing user intent distinct from
  an execution — the JetStream event payload *is* the intent, consumed
  once. So this ADR only needs one level (record → runs), not two
  (request → runs).

The upshot: **the pipeline invocation is a real, well-defined unit in code
(one call to `handleEvent`, `control.go:478` [9]) but has no corresponding
database row.** This ADR gives it one and threads its identity into
`kb.doc_proc_logs`.

---

## Decision

### DP1 — Introduce `kb.doc_process_runs` as a first-class table

Each call to `handleEvent` — one pipeline execution (Phase A + Phase B +
Phase C) for one `record_id` — becomes one row in `kb.doc_process_runs`. This
covers both invocation shapes:

- **Auto Mode:** one JetStream message → one record → one `handleEvent` call
  → one run.
- **Dev Mode:** one JetStream message → `HandleStartDocProcessingEvent`
  resolves N records → N concurrent `handleEvent` calls → N runs, all
  optionally traceable back to the same triggering event via `event_id`
  (DP2).

```
kb.events (event_id)               — the JetStream message (may fan out)
    └── kb.doc_process_runs (id)   — one handleEvent invocation, one record
            └── kb.doc_proc_logs (run_id FK)  — every log row this invocation wrote
```

### DP2 — A run records its trigger context and resolved processor set

`kb.doc_process_runs` captures:

- `record_id` — the record this invocation processed.
- `event_id` — FK to `kb.events.event_id` (the triggering JetStream
  message), nullable for invocation paths that don't originate from a
  JetStream message (e.g. direct test harness calls to `handleEvent`).
- `mode` — `'auto'` or `'dev'`, taken from `docProcessorMode()`
  (`control.go:117` [9]).
- `processors` — JSONB array of the *resolved* processor names this
  invocation actually ran (after `selectProcessors` / dependency expansion /
  `skipSatisfiedAutoDependencies`, `control.go:528-546` [9]) — the analog of
  `doc_review_runs.aspects` (RR2 [1]). This is what was actually invoked,
  which may differ from a bare `operation` list in the event payload.

### DP3 — `kb.doc_proc_logs` gains `run_id`, populated via context — not per call site

`kb.doc_proc_logs.run_id BIGINT` (FK → `kb.doc_process_runs.id`) is added.
Every log row an invocation writes — across all ~20 processors and however
many Phase B goroutines run concurrently — carries that invocation's
`run_id`.

Populating this **without** touching every one of the dozens of `Log*` call
sites across `doc-processing/*.go` follows the pattern already established
for `event_id`: `control.go:1246-1254` [9] defines
`withEventID(ctx, id) context.Context` / `eventIDFromContext(ctx) string` so
that any code holding the pipeline's `ctx` can recover the triggering
event's ID without threading it through every function signature. This ADR
adds the same pair for the run: `withRunID(ctx, runID) context.Context` /
`runIDFromContext(ctx) (int64, bool)`. `handleEvent` sets it once, right
after the run row is created (DP4); `insertDocProcLog`
(`doc_proc_log_store.go:321` [6]) — the single choke point every `Log*`
method already funnels through — reads it and stamps it into the `INSERT`.
No change is needed to `DocProcLogRecord`, to any of the ~30 `Log*` wrapper
methods, or to any processor file.

### DP4 — Run lifecycle and creation point

**Created:** in `handleEvent`, immediately after the processor set is
finalized (`control.go`, right before `resetProcessorStatuses` at line 548
[9]) — i.e. after the skip/preflight checks have already returned, so a run
row is only created for an invocation that will actually execute at least
one processor. `status = 'running'`, `start_time = requestStart`.

**Closed:** in the existing deferred block that already computes the
three-way outcome (`success` / `failed` / `stopped`, `control.go:578-589`
[9]) and in `logPipelineFinish` (`control.go:960` [9]) — both already have
everything needed (`firstErr`, `requestStopped`, elapsed time); this ADR
reuses that classification rather than inventing a second one. `end_time`
and `error_message` are set at close.

**Not created:** if `handleEvent` returns early — parse failure, skip
reason, preflight failure, or an empty resolved processor set
(`control.go:481-546` [9]) — no run row is written. This mirrors "no
`doc_review_runs` row for a request that was never accepted" (RR9 [1]).

### DP5 — `run_number` is a per-record sequential counter

`kb.doc_process_runs.run_number INT`, assigned at insert time via
`SELECT COALESCE(MAX(run_number), 0) + 1 FROM kb.doc_process_runs WHERE record_id = $1`
— identical mechanism to `doc_review_runs.run_number` (RR9 [1]). Enables
"this is the 4th time this record's pipeline has run" without a separate
counter table.

### DP6 — `kb.events` and `kb.inputs.status` are unchanged

This ADR is additive. `kb.events` continues to record JetStream message
lifecycle; `kb.inputs.status` continues to be the mutable, latest-state
source of truth the dashboard and `ListActiveJobs`-equivalent queries read
today (`+CAPSULE.md` §9 [3]). `kb.doc_process_runs` is a new history layer
underneath, purpose-built for log correlation — it does not replace either
existing mechanism.

### DP7 — A run records the effective pipeline parameters it executed with

A pipeline invocation can be triggered two ways — automatically, by
`ChenWeb/server/cmd/doc-processor`'s JetStream subscription reacting to an
ingest event, or manually, via the dashboard's "Manual Launch and Restart"
dialogs (`+CAPSULE.md` §12.4 [3]) which `POST /api/v1/jetstream/events` →
`PublishEvent` (`jetstreamhandler/handler.go:650` [11]) → the same JetStream
subject the service already listens on. Either path controls the same set of
per-invocation execution parameters, parsed into `LineFileGeneratedEvent`
(`event.go:17` [12]) on every `handleEvent` call:

- `force` (bool, defaults to `true` when omitted) — re-run even if the
  processor already succeeded.
- `force_clear` (bool, defaults to `false`) — wipe-and-reinsert vs.
  merge-into-existing (ADR 2026071002 DR1 [4]).
- `operation` / `operations` ([]string, optional) — the requested processor
  filter for this invocation (distinct from `processors` in DP2, which is
  the *resolved* set after dependency expansion — `parameters.operations`
  is what was asked for, `processors` is what actually ran).
- `filename` (string, optional) — overrides the input file resolved from
  `kb.inputs.result_filename`.

None of these are persisted today — `PublishEvent` forwards the dashboard's
JSON payload to JetStream unmodified (it does not stamp requester identity
or any other metadata), and `ParseLineFileGeneratedEvent` re-derives
defaulted values fresh on every call, in memory only. Two consequences
follow from this:

- `kb.events.event_payload` is not a substitute: it holds the *literal*
  JSON as sent, which may omit `force`/`force_clear` entirely and rely on
  `ParseLineFileGeneratedEvent`'s defaults — so "was `force_clear` actually
  true for this run" cannot be answered by reading `kb.events` alone.
- `kb.doc_process_runs.parameters JSONB` stores the *effective*,
  post-default values `handleEvent` actually acted on, captured at the same
  point `processors` is finalized (DP4's creation point, `control.go:546`
  [9]).

This does not attempt to distinguish *automatic* from *manual* triggering
directly — `PublishEvent` has no requester-identity field to draw on today,
so that distinction isn't recoverable from the payload alone. `mode`
(`'auto'`/`'dev'`, DP2) is a related but different axis: it reflects the
service's `DOC_PROCESSOR_MODE` interpretation, not who or what published the
event. If true manual/automatic provenance is wanted later, it would need
`PublishEvent` to stamp a requester field (e.g. `rc.IsAuthenticated()`'s
email, already used elsewhere in the same file at line 471 [11]) into the
payload — out of scope here, noted under Documentation Impact as a deferred
item.

---

## Data Model

### `kb.doc_process_runs` (new)

```sql
CREATE TABLE IF NOT EXISTS kb.doc_process_runs (
    id              BIGSERIAL    PRIMARY KEY,
    record_id       BIGINT       NOT NULL,   -- kb.inputs.id
    event_id        VARCHAR(128),            -- kb.events.event_id (triggering JetStream message)
    mode            TEXT         NOT NULL CHECK (mode IN ('auto', 'dev')),
    run_number      INT          NOT NULL,   -- sequential per record_id: 1, 2, 3...
    processors      JSONB        NOT NULL,   -- resolved processor names actually invoked this run
    parameters      JSONB        NOT NULL DEFAULT '{}'::jsonb,
                                  -- effective (post-default) execution knobs: force, force_clear,
                                  -- operation/operations (requested filter), filename (input override)
    status          TEXT         NOT NULL DEFAULT 'running'
                                  CHECK (status IN ('running', 'success', 'failed', 'stopped')),
    error_message   TEXT,
    create_time     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    start_time      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    end_time        TIMESTAMPTZ,
    CONSTRAINT fk_doc_process_runs_event
        FOREIGN KEY (event_id) REFERENCES kb.events (event_id)
);

CREATE INDEX IF NOT EXISTS idx_kb_doc_process_runs_record
    ON kb.doc_process_runs (record_id);
CREATE INDEX IF NOT EXISTS idx_kb_doc_process_runs_event
    ON kb.doc_process_runs (event_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_kb_doc_process_runs_record_run_number
    ON kb.doc_process_runs (record_id, run_number);
```

`event_id` is nullable (not every invocation is guaranteed to trace back to a
`kb.events` row — e.g. direct test-harness calls to `handleEvent`), but when
present it is a real FK: `kb.events.event_id` already carries a `UNIQUE`
constraint (`20260422000002_create_kb_events_table.sql` [8]), so this is
enforceable, unlike `doc_review_runs`'s original `review_run_id` problem
(the whole motivation for RR1 [1]).

### `kb.doc_proc_logs` (modified)

```sql
ALTER TABLE kb.doc_proc_logs
    ADD COLUMN run_id BIGINT REFERENCES kb.doc_process_runs (id);

CREATE INDEX IF NOT EXISTS idx_kb_doc_proc_logs_run_id
    ON kb.doc_proc_logs (run_id);
```

`run_id` is nullable. Unlike the document-review refactor (ADR 2026062804
[1]), which rebuilt five interdependent tables from a broken TEXT
coordination key, `kb.doc_proc_logs` is a single flat append-only log table
with a working, if coarse, `record_id`/`doc_proc_name` grouping today — a
plain `ADD COLUMN` is sufficient. Historical rows simply have `run_id =
NULL` (they predate run tracking); this is consistent with how `record_id`
itself is already nullable on some entries and requires no backfill or
drop/recreate.

---

## Migration Plan

Single goose migration, additive only (no data loss, no table drops):

```sql
-- +goose Up
CREATE TABLE IF NOT EXISTS kb.doc_process_runs ( ... );  -- full DDL above
CREATE INDEX ...;
CREATE UNIQUE INDEX ...;

ALTER TABLE kb.doc_proc_logs ADD COLUMN run_id BIGINT REFERENCES kb.doc_process_runs (id);
CREATE INDEX IF NOT EXISTS idx_kb_doc_proc_logs_run_id ON kb.doc_proc_logs (run_id);

-- +goose Down
ALTER TABLE kb.doc_proc_logs DROP COLUMN IF EXISTS run_id;
DROP TABLE IF EXISTS kb.doc_process_runs;
```

Suggested filename: `project_migrations/20260712000001_create_kb_doc_process_runs.sql`.

**No backfill.** Every `kb.doc_proc_logs` row that exists before this
migration runs keeps `run_id = NULL` permanently — there is no follow-up
step that retroactively assigns run IDs to historical rows, and none is
planned. There is no reliable way to reconstruct one after the fact: the
old rows carry only `record_id` + `doc_proc_name` + `create_time`, which is
exactly the ambiguity this ADR exists to fix (§Context) — a heuristic
backfill (e.g. grouping by time-gaps per `record_id`/`doc_proc_name`) would
just encode a guess as if it were fact. `run_id IS NULL` after this
migration ships means "logged before run tracking existed," not "run
unknown due to an error"; any query or dashboard view built on `run_id`
should treat pre-migration history as out of scope rather than trying to
recover it.

---

## Code Changes

### `server/api/doc-processing/control.go`

| Location | Change |
|---|---|
| `withEventID` / `eventIDFromContext` (~line 1246) | Add sibling `withRunID(ctx, runID int64) context.Context` and `runIDFromContext(ctx) (int64, bool)`, same unexported-context-key pattern. |
| `handleEvent` (~line 546, right before `resetProcessorStatuses`) | After the resolved `processors` list is finalized: build a `parameters` map from `evt.Force`, `evt.ForceClear`, `evt.Operations`, `evt.Filename` (DP7); create the run row (`CreateDocProcessRun(ctx, evt.RecordID, eventIDFromContext(ctx), mode, processorNames(processors), parameters)`), set `ctx = withRunID(ctx, runID)`. Run creation failure is logged and non-fatal — the pipeline proceeds with `run_id = NULL` logging, mirroring `insertReceivedEvent`'s existing nil-tolerant pattern (`control.go:1194-1196`). |
| Deferred outcome block (~lines 578-589) and `logPipelineFinish` (~line 960) | After the existing `success`/`failed`/`stopped` classification, call `CloseDocProcessRun(ctx, runID, status, firstErr)` to set `end_time`, `status`, `error_message`. |
| `handleDefaultSubjectEvent` / `HandleStartDocProcessingEvent` (~lines 124, 150) | Thread `mode` ("auto" vs "dev") into the run-creation call. |

### `server/api/doc-processing/doc_proc_log_store.go`

| Function | Change |
|---|---|
| `insertDocProcLog` (~line 321) | Read `runID, ok := runIDFromContext(ctx)`; include `run_id` (nil if `!ok`) in the `INSERT`. No change to `DocProcLogRecord` or any `Log*` wrapper method. |
| `DocProcLogRow` / `ListDocProcLogs` | Add `RunID *int64` to the row struct and `SELECT`/`Scan`. |
| `DocProcLogFilter` | Add `RunID *int64` (nil = all), mirroring the existing `RecordID *int64` filter — needed to actually query "logs for this run." |

### New: `server/api/doc-processing/doc_process_run_store.go` (naming indicative)

- `CreateDocProcessRun(ctx, recordID int64, eventID string, mode string, processors []string, parameters map[string]any) (runID int64, err error)` — computes `run_number` via `SELECT COALESCE(MAX(run_number),0)+1 ... WHERE record_id = $1`, inserts the row (`parameters` marshaled to JSONB; empty map if the event carried none).
- `CloseDocProcessRun(ctx, runID int64, status string, procErr error) error` — sets `end_time = NOW()`, `status`, `error_message`.

### Deferred (not required for this ADR's scope)

- `doc-processor-dashboard-view.svelte`: a "Run N of M" header / run-history
  panel scoped to `kb.doc_process_runs`, analogous to the doc-review
  frontend deferrals in ADR 2026062804 [1].
- Extending `run_id` to `kb.input_proc_status` or `kb.chunks` — those remain
  latest-state / per-chunking-invocation tables respectively and are out of
  scope here; revisit only if a concrete query need emerges.

---

## Operational Behaviors

**"What did a specific pipeline invocation actually log?"**

```sql
SELECT * FROM kb.doc_proc_logs WHERE run_id = $1 ORDER BY create_time;
```

**"How many times has this record been processed?"**

```sql
SELECT COUNT(*) FROM kb.doc_process_runs WHERE record_id = $1;
```

**"What did the most recent run execute, and did it succeed?"**

```sql
SELECT processors, status, error_message
FROM kb.doc_process_runs
WHERE record_id = $1
ORDER BY run_number DESC LIMIT 1;
```

**"Correlate a run back to the JetStream message that triggered it"**

```sql
SELECT r.*, e.event_payload, e.event_time
FROM kb.doc_process_runs r
JOIN kb.events e ON e.event_id = r.event_id
WHERE r.id = $1;
```

**"Did the run that produced this output use `force_clear`?"**

```sql
SELECT parameters->>'force_clear' AS force_clear, parameters->>'force' AS force
FROM kb.doc_process_runs
WHERE id = $1;
```

---

## Consequences

**Positive:**

- Log rows from concurrent or successive invocations of the same
  processor/record become disambiguable by a real key instead of eyeballed
  timestamp gaps.
- Per-run cost/latency/cache-hit rollups (`prompt_cache_hit_tokens` /
  `prompt_cache_miss_tokens`) become a plain `GROUP BY run_id` instead of a
  manually-bounded time window.
- Low blast radius: the context-threading approach (mirroring
  `withEventID`/`eventIDFromContext`) means only two choke points change
  (`handleEvent`'s run creation/close, `insertDocProcLog`'s read) — no
  signature changes across the ~20 processor files or their `Log*` call
  sites.
- Lays groundwork for a future run-history dashboard view, the doc-processor
  analog of the doc-review run picker deferred in ADR 2026062804 [1].
- `force`/`force_clear`/`operations`/`filename` — previously transient,
  in-memory-only per invocation — become queryable history. Answers "was
  `force_clear=true` set on the run that appears to have wiped these
  metrics" without needing to reconstruct it from raw JetStream payloads or
  guess from timing.

**Negative / cost:**

- Two additional writes per pipeline invocation (run create, run close) —
  negligible next to existing per-chunk LLM call logging volume.
- `run_id` is nullable: any code path that logs without flowing through
  `handleEvent`'s `ctx` (direct test-harness use of `DocProcLogger`, or a
  future entry point that bypasses `handleEvent`) silently writes `run_id =
  NULL`. Acceptable — consistent with `record_id` already being optional on
  some entries.
- Does not by itself change ADR 2026071002's [4] content-based dedup
  (Rule-1..4) — that logic stays independent of `run_id`. A future ADR could
  add `run_id` to `kb.metrics.ext_info`'s merge log for "which run added
  this metric," but that is not proposed here.

---

## Tests

- `CreateDocProcessRun` assigns `run_number = 1` for a record's first run,
  and increments correctly across subsequent runs for the same
  `record_id`.
- Two reprocessing invocations for the same `record_id` (e.g. one Auto Mode
  ingest followed by one Dev Mode force-reprocess) produce two distinct
  `kb.doc_process_runs` rows, and their `kb.doc_proc_logs` rows partition
  cleanly by `run_id` with no cross-run interleaving, including under Phase B
  concurrency (the run is created once, before Phase A begins, and the same
  `run_id` flows through every concurrent Phase B goroutine via `ctx`).
- An event that hits a skip path (empty processor set, skip reason, preflight
  failure) creates no `kb.doc_process_runs` row.
- `runIDFromContext` returns `(0, false)` for a context that never passed
  through `handleEvent`; `insertDocProcLog` in that case writes `run_id =
  NULL` without error.
- `CloseDocProcessRun` sets `status = 'failed'` + `error_message` when
  `firstErr != nil`, `'stopped'` when the pipeline was user-stopped, and
  `'success'` otherwise — mirroring the existing three-way branch in the
  deferred block at `control.go:578-589`.
- `ListDocProcLogs` with `DocProcLogFilter.RunID` set returns only rows for
  that run.
- `parameters` on a created run reflects `LineFileGeneratedEvent`'s
  *defaulted* values, not the raw payload — e.g. an event payload that omits
  `force` entirely still produces `parameters->>'force' = 'true'` (the
  documented default, `event.go:38-45`), not a missing/null key.
- A manually-launched run (via `PublishEvent`) and an automatically-launched
  run (via the JetStream subscription) with identical payloads produce
  identical `parameters`; `mode` alone does not vary by trigger origin,
  confirming DP7's note that origin isn't distinguishable from the payload
  today.

---

## Documentation Impact

- **What knowledge changed?** `kb.doc_proc_logs` rows are now attributable to
  a specific pipeline invocation via `run_id`; `kb.doc_process_runs` becomes
  the canonical history of pipeline invocations per record.
- **Which docs/specs/ADRs/tests are affected?**
  `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md` §2
  ("JetStream Subscription") and §3 ("Handle JetStream Events") [3] describe
  the invocation flow this ADR adds a step to; they should reference this
  ADR once implemented. No `KnowledgeStore/table-schemas/` entry currently
  exists for `kb.doc_proc_logs` (unlike `kb.events`/`kb.inputs`, which have
  `table-kb-events.md`/`table-kb-inputs.md` [8][10]) — this is a pre-existing
  gap, not introduced by this ADR, but implementation is a natural time to
  add `table-kb-doc-proc-logs.md` and `table-kb-doc-process-runs.md` in that
  same format.
- **Which docs were updated?** This ADR (new).
- **Which docs are now stale?** `+CAPSULE.md` §3's description of event
  handling will be stale once implemented (it does not currently mention run
  creation) — update at implementation time, not before, per this
  workspace's convention of documenting what was actually built.
- **What was intentionally left undocumented?** Dashboard run-history UI;
  extending `run_id` to `kb.input_proc_status` or `kb.chunks` (deferred,
  no concrete query need yet); stamping requester identity into
  `PublishEvent` so manual vs. automatic trigger origin becomes recoverable
  (DP7 — no concrete need identified yet, would require its own small ADR
  touching the auth-aware handler pattern already used in
  `CreateStoredSubject`, `jetstreamhandler/handler.go:471` [11]).

---

## References

[1] ADR 2026062804 — Document Review: `kb.doc_review_runs` — First-Class Run
Table: `KnowledgeStore/doc-repo/adrs/202606/2026062804-adr-doc-review-run.md`

[2] `ChenWeb/project_migrations/20260527000020_create_kb_doc_proc_logs.sql`

[3] Doc Processor Capsule:
`KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md`

[4] ADR 2026071002 — Incremental Update Artifacts in Doc Processors:
`KnowledgeStore/doc-repo/adrs/202607/2026071002-adr-doc-processor-incremental.md`

[5] ADR 2026071101 — Looping over a Doc Processor:
`KnowledgeStore/doc-repo/adrs/202607/2026071101-adr-doc-processor-loop.md`

[6] `ChenWeb/server/api/doc-processing/doc_proc_log_store.go`

[7] ADR 2026062501 (DeepSeek cache) / ADR 2026062701 (doc-processor cache
extension), referenced from `+CAPSULE.md` §6.2

[8] `kb.events` schema: `KnowledgeStore/table-schemas/table-kb-events.md`;
migration `ChenWeb/project_migrations/20260422000002_create_kb_events_table.sql`

[9] `ChenWeb/server/api/doc-processing/control.go`

[10] `kb.inputs` schema: `KnowledgeStore/table-schemas/table-kb-inputs.md`

[11] `ChenWeb/server/api/jetstreamhandler/handler.go` (`PublishEvent`, the
manual-launch publish endpoint; `CreateStoredSubject` for the
`rc.IsAuthenticated()` requester-identity pattern referenced in DP7)

[12] `ChenWeb/server/api/doc-processing/event.go`
(`LineFileGeneratedEvent`, `ParseLineFileGeneratedEvent`)
