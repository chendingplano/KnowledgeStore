# ADR 2026062804 — Document Review: `kb.doc_review_runs` — First-Class Run Table

**Date:** 2026-06-28 \
**Status:** Accepted \
**Component:** ChenWeb — `server/api/doc-reviews`, `project_migrations` \
**Authors:** Chen Ding \
**Tags:** doc review, database, schema, review run, refactor

---

## Change Logs

* 2026/06/28, ADR Created. Identifies the structural flaw in the `review_run_id` TEXT
  coordination key and proposes replacing it with a dedicated `kb.doc_review_runs` table.
  Supersedes the DR7 idempotency rule in ADR 2026061801.

* 2026/06/28, Core schema and backend implemented (migration
  `20260628000002_rebuild_doc_review_tables.sql`). All five doc-review tables rebuilt
  with `run_id BIGINT` FK. `AcceptRequest` creates the first run row; `RunReview` and
  `RunReviewAndReport` accept `(requestID, runID int64)`. JetStream event carries both
  IDs. All tests updated to new schema.

  **Divergences from plan:**

  - `RestartRequest` creates a **new** `doc_review_runs` row (same as `StartNewRun` in
    the ADR) rather than resetting an existing run row. This simplifies the crash-recovery
    invariant: a run row, once created, is never reset in place.
  - `RecoverStalledReviews` re-queues stalled runs via `RunReviewAndReport` without
    pre-deleting partial findings for that run. Findings written before the crash are
    overwritten by `DeleteFindings` at the start of the new run's `PostProcessIndex`.
  - `RequestStatus.LatestRunID int64` (not a `LatestRun *RunSummary` sub-struct and no
    `RunCount`). Full run sub-object and run-count are deferred.

  **Deferred to follow-on work:**

  - New REST endpoints: `POST /requests/<id>/runs`, `GET /requests/<id>/runs`,
    `POST /runs/<run_id>/restart`.
  - `StartNewRun` / `RestartRun` as distinct public controller methods.
  - Frontend: run picker, run history panel, "Run N of M" header, per-run findings view.
  - ADR 2026061801 change-log annotation (DR7 superseded by RR3).

---

## Context

### The `review_run_id` problem

ADR 2026061801 introduced `review_run_id`, a TEXT string generated at accept time
(format `"<record_id>_review_<timestamp>"`), used to coordinate across five tables:

| Table | Column | Role |
|-------|--------|------|
| `kb.doc_review_requests` | `review_run_id TEXT` | Source of truth for the string |
| `kb.doc_review_findings` | `review_run_id TEXT NOT NULL` | Join key back to the request |
| `kb.doc_review_activities` | `review_run_id TEXT` (nullable) | Join key back to the request |
| `kb.doc_review_status` | `review_run_id TEXT NOT NULL` | UNIQUE with `aspect` |
| `kb.doc_review_reports` | `review_run_id TEXT NOT NULL` | Join key back to the request |

The fundamental flaw: **`review_run_id` is not a primary key, not declared UNIQUE, and
carries no FK constraint on any of the child tables.** The join
`findings.review_run_id = requests.review_run_id` is TEXT string equality on a
non-indexed, non-unique column. There is no DB-enforced referential integrity between
the finding/activity rows and the request that generated them.

Additionally, `review_run_id` is a surrogate for something that already exists — the
request's primary key `id`. It was introduced to give a stable identifier before a run
starts, but an integer PK from a `doc_review_runs` row inserted at accept time achieves
the same purpose with proper relational integrity.

### The single-run constraint

The current implementation creates exactly one `review_run_id` per `doc_review_requests`
row. `RestartRequest` re-uses the same string. DR7 (from ADR 2026061801) states:
"re-running replaces all findings for that document." The system has no way to:

- Preserve findings from a previous run while re-running with updated prompts.
- Run a *different* set of aspects than the original request specified (add new
  reviewers, skip some, re-run only the ones that failed).
- Track the history of multiple executions of the same review request.
- Distinguish "the job crashed and was restarted" from "the user deliberately re-ran
  with different parameters."

These capabilities are required as the document review pipeline matures to ~40 aspects.

---

## Decision

### RR1 — Introduce `kb.doc_review_runs` as a first-class table

Each execution of a review is a **run** — an independently addressable row in
`kb.doc_review_runs`. A `doc_review_requests` row is the user's *intent and
configuration*; a `doc_review_runs` row is one *execution* of that intent.

The relationship is one-to-many: a single request can produce multiple runs over time.
Every run has its own integer PK (`run_id`), which replaces the `review_run_id` TEXT
string as the coordination key across all child tables.

```
kb.doc_review_requests (request_id)  — user's intent
    └── kb.doc_review_runs (run_id)  — one execution
            ├── kb.doc_review_findings   (run_id FK)
            ├── kb.doc_review_activities (run_id FK, nullable)
            ├── kb.doc_review_status     (run_id FK)
            └── kb.doc_review_reports    (run_id FK)
```

### RR2 — Each run carries its own aspect list

`doc_review_runs.aspects JSONB` records *exactly which aspects were requested for this
run*. This is independent of the request's original `aspects` field. This enables:

- **Incremental runs:** run aspects A–E first; run aspects F–J in a later run.
- **Re-runs of a subset:** only re-run the two aspects whose prompts were updated.
- **Additive runs:** the original request selected 10 aspects; run additional new
  reviewers (added to the codebase after the original submission) without resubmitting.
- **Targeted re-runs after failure:** if three aspects failed, re-run only those three.

The request's `aspects` field reflects the *original intent*. Each run's `aspects`
field is what was actually executed.

### RR3 — Findings are run-scoped; previous runs are preserved

`kb.doc_review_findings` gains `run_id BIGINT NOT NULL` (FK → `doc_review_runs.id`).
Each run's findings are tagged to its `run_id`. Re-running does **not** delete prior
findings — rows from each run coexist in the table. Queries default to the most recent
completed run for a request; cross-run comparison is possible by filtering on `run_id`.

This supersedes DR7's "re-running replaces all findings" rule. DR7 was correct given the
single-run model; with first-class runs it is unnecessary.

### RR4 — Activities are run-scoped (nullable for structure edits)

`kb.doc_review_activities` gains `run_id BIGINT` (nullable FK → `doc_review_runs.id`).
Finding-based activities (`auto_fix`, `edit_tool`, `finding_delete`) carry the run that
produced the finding they correct. Structure edits (`structure_modify`, `structure_split`,
`structure_delete`) remain run-agnostic (`run_id = NULL`), as today.

### RR5 — Per-aspect status is scoped to a run

`kb.doc_review_status` gains `run_id BIGINT NOT NULL` (FK → `doc_review_runs.id`).
The UNIQUE constraint changes from `(review_run_id, aspect)` to `(run_id, aspect)`.
Each run seeds its own `pending` status rows at creation time. The live monitor
(`GET /api/v1/doc-review/active`) queries `doc_review_status` where
`run_id IN (latest run per active request)` and `status NOT IN ('success','failed')`.

### RR6 — Reports are per-run

`kb.doc_review_reports` gains `run_id BIGINT NOT NULL` (FK → `doc_review_runs.id`).
One report per run; regenerating a report replaces the row in place (same as today,
but scoped to the run rather than the request). The `request_id` column is retained as
a denormalized shortcut for queries like "all reports for this request."

### RR7 — `review_run_id` TEXT retired from all tables

The `review_run_id` column is removed from:
- `kb.doc_review_requests`
- `kb.doc_review_findings`
- `kb.doc_review_activities`
- `kb.doc_review_status`
- `kb.doc_review_reports`

The timing fields that belonged to an execution move from `doc_review_requests` to
`doc_review_runs`: `start_time`, `end_time`, `error_message`. The request retains
`create_time`.

### RR8 — Request `status` is a denormalized summary of the latest run

`kb.doc_review_requests.status` is retained but now mirrors the latest run's outcome
(updated by the controller when a run transitions). This avoids always joining to
`doc_review_runs` for list views and status polling. The mapping is:

| Latest run status | Request status |
|-------------------|----------------|
| (no runs yet) | `accepted` |
| `pending` / `running` | `running` |
| `completed` | `completed` |
| `failed` | `failed` |
| `stopped` | `stopped` |

### RR9 — Run lifecycle and creation points

**First run:** Created immediately after the `doc_review_requests` row is inserted in
`AcceptRequest`. The first run's `aspects` matches the request's `aspects`.

**Subsequent runs:** Created via a new controller method `StartNewRun(requestID, aspects)`.
The caller supplies which aspects to run (which may differ from the request's original
list or from any prior run). The new run is seeded with `pending` status rows.

**Crash recovery / restart:** If a run ends in `failed` or `stopped` due to a crash or
cancellation and the user wants to re-execute the *same* aspect set, `RestartRun(runID)`
resets that run's rows to `pending` and re-executes. No new run row is created; prior
findings for that `run_id` are deleted before re-execution. This is distinct from a
deliberate re-run (which creates a new run row).

**Run number:** `doc_review_runs.run_number INT` is a per-request sequential counter
(1, 2, 3…) assigned at insert time via
`SELECT COALESCE(MAX(run_number), 0) + 1 FROM kb.doc_review_runs WHERE request_id = $1`.
Displayed in the UI as "Run 1", "Run 2", etc.

---

## Data Model

### `kb.doc_review_runs` (new)

```sql
CREATE TABLE IF NOT EXISTS kb.doc_review_runs (
    id              BIGSERIAL    PRIMARY KEY,
    request_id      BIGINT       NOT NULL,   -- kb.doc_review_requests.id
    input_record_id BIGINT       NOT NULL,   -- denormalized from request; avoids join for common queries
    run_number      INT          NOT NULL,   -- sequential per request: 1, 2, 3...
    aspects         JSONB        NOT NULL,   -- the aspects executed in THIS run
    model_overrides JSONB,                   -- per-run model overrides (may differ from request)
    notes           TEXT,                    -- optional per-run notes
    status          TEXT         NOT NULL DEFAULT 'pending',
    created_by      TEXT,
    create_time     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    start_time      TIMESTAMPTZ,
    end_time        TIMESTAMPTZ,
    error_message   TEXT
);

CREATE INDEX IF NOT EXISTS idx_doc_review_runs_request ON kb.doc_review_runs (request_id);
CREATE INDEX IF NOT EXISTS idx_doc_review_runs_record  ON kb.doc_review_runs (input_record_id);
CREATE INDEX IF NOT EXISTS idx_doc_review_runs_status  ON kb.doc_review_runs (request_id, status);
```

### `kb.doc_review_requests` (modified)

Remove columns: `review_run_id`, `start_time`, `end_time`, `error_message`.

```sql
-- Resulting shape (columns retained / added):
--   id, input_record_id, tier, aspects, reference_docs, notes, model_overrides,
--   requester_name, requester_id, report_template, doc_template,
--   status,    -- denormalized summary of latest run's status
--   create_time
```

### `kb.doc_review_findings` (modified)

Replace `review_run_id TEXT NOT NULL` with `run_id BIGINT NOT NULL`.

```sql
ALTER TABLE kb.doc_review_findings
    DROP COLUMN review_run_id,
    ADD COLUMN run_id BIGINT NOT NULL;

CREATE INDEX IF NOT EXISTS idx_doc_review_findings_run ON kb.doc_review_findings (run_id);
-- Existing indexes on (input_record_id, pass/aspect/severity) are retained.
```

### `kb.doc_review_activities` (modified)

Replace `review_run_id TEXT` (nullable) with `run_id BIGINT` (nullable).

```sql
ALTER TABLE kb.doc_review_activities
    DROP COLUMN review_run_id,
    ADD COLUMN run_id BIGINT;   -- NULL for structure edits (run-agnostic)

CREATE INDEX IF NOT EXISTS idx_doc_review_activities_run ON kb.doc_review_activities (run_id);
```

### `kb.doc_review_status` (modified)

Replace `review_run_id TEXT NOT NULL` with `run_id BIGINT NOT NULL`. Update the UNIQUE
constraint.

```sql
ALTER TABLE kb.doc_review_status
    DROP CONSTRAINT doc_review_status_review_run_id_aspect_key,
    DROP COLUMN review_run_id,
    ADD COLUMN run_id BIGINT NOT NULL,
    ADD CONSTRAINT doc_review_status_run_id_aspect_key UNIQUE (run_id, aspect);

DROP INDEX IF EXISTS idx_doc_review_status_run;
CREATE INDEX IF NOT EXISTS idx_doc_review_status_run ON kb.doc_review_status (run_id);

-- Partial index for the live monitor (update predicate -- column name unchanged):
DROP INDEX IF EXISTS idx_doc_review_status_active;
CREATE INDEX IF NOT EXISTS idx_doc_review_status_active ON kb.doc_review_status (run_id)
    WHERE status NOT IN ('success', 'failed');
```

### `kb.doc_review_reports` (modified)

Replace `review_run_id TEXT NOT NULL` with `run_id BIGINT NOT NULL`.

```sql
ALTER TABLE kb.doc_review_reports
    DROP COLUMN review_run_id,
    ADD COLUMN run_id BIGINT NOT NULL;

CREATE INDEX IF NOT EXISTS idx_doc_review_reports_run ON kb.doc_review_reports (run_id);
```

---

## Migration Plan

Since this is a staging server, the migration uses a clean-slate approach: drop and
recreate all doc-review tables in the correct order. No data is preserved (existing
review results are discarded).

**Migration sequence (one goose file):**

```sql
-- +goose Up
-- Drop child tables first (FK order), then parent tables.
DROP TABLE IF EXISTS kb.doc_review_activities;
DROP TABLE IF EXISTS kb.doc_review_findings;
DROP TABLE IF EXISTS kb.doc_review_status;
DROP TABLE IF EXISTS kb.doc_review_reports;
DROP TABLE IF EXISTS kb.doc_review_runs;
DROP TABLE IF EXISTS kb.doc_review_requests;

-- Recreate in dependency order.
-- (Full CREATE TABLE statements as defined in this ADR.)
```

A single goose migration file covers all drops and re-creates. The Down section
re-drops everything.

---

## Code Changes

### `server/api/doc-reviews/controller.go`

| Method | Change |
|--------|--------|
| `AcceptRequest` | After inserting `doc_review_requests`, immediately insert the first `doc_review_runs` row (same `aspects` as the request). Return `RunID int64` alongside `RequestID` in `SubmitResult`. Seed `doc_review_status` using `run_id` (integer), not a string. Remove `review_run_id` generation. |
| `RunReview` | Accept `runID int64` instead of looking up `review_run_id`. Update `doc_review_runs` status rather than `doc_review_requests`. Pass `RunID` to `ReviewProcessor`. |
| `RunReviewAndReport` | Pass `runID` through the chain. |
| `StartNewRun` | New method. Inserts a `doc_review_runs` row with a caller-supplied `aspects` list and an incremented `run_number`. Seeds status rows. Returns the new `runID`. |
| `RestartRun` | Resets the given `run_id` (not the request) to `pending`; deletes findings for that run; re-seeds status rows. |
| `RecoverStalledReviews` | Finds runs (not requests) in `pending`/`running` status and re-arms them via `RestartRun`. |
| `StopRequest` | Stops the active run for a request (the run in `pending`/`running`). |
| `loadRequest` | Joins to `doc_review_runs` to populate `LatestRunID`, run timing, and run status for the response. |
| `GetRequestWithFindings` | Queries findings by `run_id` (defaulting to the latest completed run for the request). Accepts optional `run_id` query param to view a specific run. |
| `ListActiveJobs` | Queries `doc_review_status` by `run_id`; joins `doc_review_runs` to `doc_review_requests` for display fields. |
| `seedAspectStatuses` | Takes `runID int64` instead of `reviewRunID string`. |
| `markAspectsRunning` / `finalizeAspectsSuccess` / `failOpenAspects` | Take `runID int64`. |

### `server/api/doc-reviews/models.go`

- `SubmitResult`: add `RunID int64`.
- `RequestStatus`: remove `ReviewRunID string`; add `LatestRunID int64`, `RunCount int`, and a `LatestRun *RunSummary` sub-struct (id, run_number, status, start_time, end_time).
- New struct `RunSummary` and `RunListItem`.
- `ActiveJob`: replace `ReviewRunID string` with `RunID int64`.

### `server/api/doc-reviews/review-document.go` (`ReviewProcessor`)

Replace `ReviewRunID string` field with `RunID int64`. Update `ReviewFindingsSQLStore`
and `ReviewStatusSQLStore` to write `run_id` (integer) columns.

### `server/api/docactivity/activity.go`

Replace `ReviewRunID string` field in `Activity` with `RunID int64`. Update `Log` and
`List` SQL accordingly.

### `server/api/doc-reviews/handler.go` and `routes.go`

| Endpoint | Change |
|----------|--------|
| `POST /api/v1/doc-review/requests` | Response now includes `run_id` of the first run. |
| `GET /api/v1/doc-review/requests/<id>` | Response includes `latest_run` sub-object and `run_count`. |
| `POST /api/v1/doc-review/requests/<id>/runs` | **New endpoint.** Body: `{aspects[], model_overrides{}, notes}`. Creates and starts a new run. Returns `{run_id, run_number}`. |
| `GET /api/v1/doc-review/requests/<id>/findings?run_id=<n>` | Optional `run_id` param to retrieve findings for a specific run (defaults to latest completed). |
| `GET /api/v1/doc-review/requests/<id>/runs` | **New endpoint.** Returns the list of runs for a request (id, run_number, status, aspects, timing). |
| `POST /api/v1/doc-review/runs/<run_id>/restart` | **New endpoint.** Restarts a crashed/failed run in-place (same run row, same aspects). |

### Frontend (`doc-review-results-view.svelte`, `docReviewService.ts`)

- Surface `run_count` and `latest_run.run_number` in the results view header ("Run 2 of 3").
- Add a "Run History" collapsible section listing all runs with their status and timing.
- "Re-Run" button opens a dialog to select which aspects to include (defaulting to the
  original request's aspects or the latest run's aspects). Submits to
  `POST /requests/<id>/runs`.
- Findings view: show which run the current findings come from; allow switching runs via
  a run selector.

---

## Operational Behaviors

### "What findings are shown for a request?"

Default: findings from the most recent **completed** run for that request, ordered by
`run_id DESC`. This is a single query:

```sql
SELECT f.*
FROM kb.doc_review_findings f
JOIN kb.doc_review_runs r ON r.id = f.run_id
WHERE r.request_id = $1 AND r.status = 'completed'
ORDER BY r.id DESC, f.id ASC
```

To scope to one specific run: `WHERE f.run_id = $2`.

### "What aspects were covered across all runs?"

Union the `aspects` JSONB arrays across all runs for a request, deduplicated:

```sql
SELECT DISTINCT jsonb_array_elements_text(r.aspects) AS aspect
FROM kb.doc_review_runs r
WHERE r.request_id = $1 AND r.status = 'completed'
```

### "What does the live monitor show?"

A request is "active" if it has a run in `pending` or `running` status. The query
becomes:

```sql
SELECT DISTINCT r.request_id
FROM kb.doc_review_runs r
WHERE EXISTS (
    SELECT 1 FROM kb.doc_review_status s
    WHERE s.run_id = r.id AND s.status NOT IN ('success', 'failed')
)
```

### "How does crash recovery work?"

On startup, `RecoverStalledReviews` finds all `doc_review_runs` rows with
`status IN ('pending','running')` and calls `RestartRun(runID)` for each. `RestartRun`
resets the run's status, clears its aspect statuses back to `pending`, and deletes its
partially-written findings. The run is then re-queued for execution.

---

## Consequences

**Positive:**

- Referential integrity is enforced at the DB level. Every finding, activity, status
  row, and report has a proper integer FK to the run that owns it.
- Multiple runs per request are first-class, enabling incremental reviews, re-runs of
  individual aspects, and historical comparison.
- The `review_run_id` string — a fragile text equality join on a non-unique column — is
  retired from all tables.
- Run history is preserved. Old findings are not silently deleted when a new run starts.
- Adding new reviewers to the codebase does not require creating a new request; a new
  run can include them.

**Negative / cost:**

- Schema migration discards all existing staging doc-review data (acceptable per
  workspace guidelines).
- Controller, processor, and API surface changes are broad but mechanical: rename
  `ReviewRunID string` → `RunID int64` throughout.
- The frontend needs a run-picker UI for requests that have multiple runs.
- DR7's "one review per document version" rule is superseded; the new invariant is "one
  request per document version, multiple runs per request."

---

## Tests

- `AcceptRequest` creates a `doc_review_requests` row and a `doc_review_runs` row in the
  same transaction; both have consistent `input_record_id` and `aspects`.
- `seedAspectStatuses` seeds status rows referencing `run_id`, with `UNIQUE (run_id, aspect)` enforced.
- `StartNewRun` increments `run_number`; the new run's `aspects` may differ from the
  original request's `aspects`.
- Findings for run 1 are not deleted when run 2 executes; both coexist in
  `doc_review_findings`, distinguishable by `run_id`.
- `RestartRun` resets status rows and deletes findings for the given `run_id` only;
  findings from other runs for the same request are unaffected.
- `GetRequestWithFindings` without a `run_id` param returns findings from the latest
  completed run; with a `run_id` param returns findings for that specific run.
- `ListActiveJobs` excludes requests whose latest run has all aspects in terminal status.
- Activities log `run_id` (integer, not null) for finding-based actions;
  structure-edit activities log `run_id = NULL`.

---

## Documentation Impact

- Update ADR 2026061801 Change Log: DR7 (idempotency / replace-on-rerun) superseded by
  RR3 (run-scoped findings, preserve across runs).
- Update ADR 2026061801 Data Model section: mark all `review_run_id` entries as retired;
  reference this ADR.
- Update `shared/Documents/` or `ChenWeb/docs/` with the new run lifecycle diagram.

---

## References

[1] ADR 2026061801 — Document Review: LLM-Powered Multi-Aspect Review Pipeline \
[2] ADR 2026062203 — Generate Document Review Report \
[3] ADR 2026061801 §DR15 — Per-Aspect Review Status & Live Job Monitor \
[4] ADR 2026061801 §DR17 — Correction Activity Log
