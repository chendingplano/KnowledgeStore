# ADR: Indexed status projections for `kb.inputs`

- DocID: `doc-2026061001`
- **Status:** Accepted
- **Date:** 2026-06-10
- **Deciders:** ChenWeb / KnowledgeStore maintainers
- **Tags:** database, performance, doc-processing, pdf-parser

## Change Logs
- Created by Claude Code on 2026/06/10

## Context

`kb.inputs` stores every input document (PDF, etc.). Doc-processing status is recorded in a single
JSONB column, `kb.inputs.status`, holding an **array** with one entry per processor plus an
aggregate `doc_processing` control entry:

```json
[
  { "operation": "parsed",          "proc_status": "success" },
  { "operation": "static_analyzer", "proc_status": "success" },
  { "operation": "extract_metrics", "proc_status": "failed", "error": "..." },
  { "operation": "doc_processing",  "proc_status": "running" }
]
```

Many features filter records *by status*: the doc-processor dashboard, the ingestion list, the PDF
parser's claim/duplicate queries, and the Dev-Mode `all: parsed | failed-procs` reprocessing
selectors. Each filter evaluated a predicate **inside** the JSON array, e.g.

```sql
EXISTS (SELECT 1 FROM jsonb_array_elements(i.status) st WHERE ...)
-- or: jsonb_path_exists(status, '$[*] ? (@.proc_status == "failed")')
```

A predicate over a JSON array cannot use a normal index, so every such query is a **sequential
scan that parses each row's JSON**. `kb.inputs` is expected to reach tens of millions of rows;
these queries degrade linearly and were already the dominant cost on the dashboard and ingestion
views. The single status blob is also a write-contention point — each processor does a
read-modify-write of the whole array under a per-record lock.

### Problem statement

Make "query records by status" scale to tens of millions of rows without:

- rewriting the status-writing logic of every processor, and
- introducing a way for the projection to silently drift from the source of truth.

The second constraint is sharp: `kb.inputs.status` is written from **7+ call sites across 4
separate binaries** — `pdf-parser` (Python), `service-pdf-parser`, `file-converters`,
`doc-processor`, plus the stop handler. Any approach that maintains derived state in application
code must patch every writer and every future one.

## Decision drivers

- Query latency on status filters at 10M–50M rows.
- Correctness: derived state must never diverge from `kb.inputs.status`.
- Robustness against missed writers, now and for future code.
- Minimal blast radius: avoid touching the ~12 processors' status logic.
- Keep the existing API contract (no forced frontend changes).

## Considered options

### Option A — One status column per processor on `kb.inputs`

Add `parsing_status`, `static_analyzer_status`, … columns.

- Schema churn as processors are added (a growing project plan).
- The common "any processor failed" query becomes `col1='failed' OR col2='failed' OR …`, which is
  unindexable as a single predicate — so a rollup column is needed anyway.
- Rejected.

### Option B — Child table only, maintained in application code

Normalize into `kb.input_proc_status`, write rows from each processor.

- Good query shape, but requires patching all 7+ writers across 4 binaries and remembering every
  future one — the "I may miss some" risk. Rejected as the sole mechanism.

### Option C — Trigger-maintained projections (chosen)

Keep `kb.inputs.status` as the source of truth and maintain two **indexed projections** of it via
**database triggers**:

1. Rollup columns on `kb.inputs` for whole-table filters.
2. A child table `kb.input_proc_status` for per-processor queries.

Because the projections are derived by the database on every write, no application writer changes,
and no writer can be missed.

## Decision

Adopt **Option C**.

### Schema

Migration: `ChenWeb/project_migrations/20260609000002_add_kb_inputs_status_rollups.sql`.

**Rollup columns on `kb.inputs`:**

| Column | Values | Source |
|---|---|---|
| `parse_state` | `pending` / `parsing` / `parsed_success` / `parsed_failed` | the PDF parser's single `parsed` entry (`parsing` = in-progress claim, `proc_status = active`) |
| `pipeline_state` | `pending` / `running` / `success` / `failed` / `stopped` | the aggregate `doc_processing` entry |
| `has_failed_proc` | boolean | true only for real doc-processor failures (parse/convert excluded, matching the `failed-procs` selector) |

**Child table** `kb.input_proc_status (record_id, processor, proc_status, start_time, ms_used,
error, modify_time)`, PK `(record_id, processor)`, FK to `kb.inputs(id) ON DELETE CASCADE`. One row
per processor (including parsing and converting).

**Derivation logic** lives in immutable SQL functions — `kb.canonical_op`,
`kb.input_status_parse_state`, `kb.input_status_pipeline_state`, `kb.input_status_has_failed_proc`
— used by both the triggers and the one-time backfill, so there is a single source of truth for the
mapping. `kb.canonical_op` mirrors `canonicalOperationName` in
`server/api/doc-processing/event.go`.

**Triggers on `kb.inputs`:**

- `trg_refresh_input_status_rollups` — `BEFORE INSERT OR UPDATE OF status`, sets the three rollup
  columns on `NEW`.
- `trg_sync_input_proc_status` — `AFTER INSERT OR UPDATE OF status`, re-derives the record's child
  rows (`DELETE` + `INSERT … DISTINCT ON (processor)`).

**Indexes:**

- `idx_kb_inputs_pipeline_active` — partial `WHERE pipeline_state IN ('pending','running')` (the
  active set is a tiny fraction of all rows, so this stays small regardless of table size).
- `idx_kb_inputs_has_failed_proc` — partial `WHERE has_failed_proc`.
- `idx_kb_inputs_parse_state`, `idx_kb_inputs_pipeline_state` — btree.
- `idx_kb_input_proc_status_processor_status (processor, proc_status)` and partial
  `idx_kb_input_proc_status_failed`.

**Backfill:** one-time, set-based, run inside the migration. It writes the rollup columns and child
rows directly (not via `status`), so it does not re-fire the triggers. Runs once; goose never
re-applies it.

### Read-path changes

| Site | Before | After |
|---|---|---|
| `server/api/kbhandler/handler.go` `buildWhereClause` — `parse_state` / `pipeline_filter` | nested `EXISTS`/`NOT EXISTS` over `jsonb_array_elements` | `i.parse_state` / `i.pipeline_state` equality |
| same — `operation` + `proc_status` | `EXISTS(jsonb_array_elements …)` | `EXISTS(kb.input_proc_status …)`; aggregate `doc_processing` maps to `i.pipeline_state` |
| `server/api/doc-processing/extract-doc-metadata-store.go` `ListParsedInputRecords` | `jsonb_path_exists(… parsed==success)` | `parse_state = 'parsed_success'` |
| same — `ListRecordsWithFailedDocProcessors` | `jsonb_path_exists(… ==failed)` | `has_failed_proc` (Go post-filter kept for exact per-processor list) |
| `python/pdf-parser/shared.py` `claim_candidates` | `jsonb_path_exists(… parsed / active)` | `parse_state = 'pending' OR (parse_state = 'parsing' AND modify_time` stale`)` |
| same — `find_duplicate_processed_record` | `jsonb_path_exists(… parsed==success)` | `parse_state = 'parsed_success'` |

### Write path

Unchanged. Every status write (`UPDATE kb.inputs SET status = …`, or `INSERT … status`) from any
binary fires the triggers. Processors and the parser keep writing `kb.inputs.status` exactly as
before.

## Consequences

### Positive

- Status filters become indexed lookups instead of full scans — the core goal.
- **No processor changes** and **no missed writers**: the projection is a database-guaranteed
  function of `status`, across all 4 binaries and any future writer.
- **No frontend changes**: `GET /api/v1/kb/inputs` keeps the same params and response shape; only
  the server `WHERE` clause changed. Dashboard and ingestion views are simply faster.
- Adding a future doc processor needs **no schema change** — its `kb.input_proc_status` row appears
  automatically once it writes a status entry. (Only extend `kb.canonical_op` for a legacy alias.)
- Side benefit: the child table is a foundation for relieving the single-blob write-contention if
  the doc-processor is ever scaled to multiple replicas.

### Negative / trade-offs

- A trigger runs on every status write (iterates a ~12-element array + a small child re-sync). This
  is negligible relative to LLM/parse work, but it is non-zero.
- Derivation logic now lives in PL/pgSQL + SQL functions, which are less unit-testable than Go.
  Mitigated by keeping the logic in small, single-purpose immutable functions shared with the
  backfill.
- Changing the derivation later only affects *future* writes; existing rows must be re-backfilled
  via a follow-up migration.
- The one-time backfill rewrites every row (a heavy operation on a very large table). Acceptable
  here because there is no production data yet; on a large table it would warrant batching.
- `parse_state = 'parsing'` is a fourth value the dashboard's three parse filters do not select, so
  in-progress parses simply don't appear under `pending`/`parsed_success`/`parsed_failed` — an
  improvement over the previous behavior, where in-progress was conflated.

## Operational notes

- The first restart of the migration-running Go server applies the schema, runs the backfill, and
  installs the triggers — in one transaction-managed sequence. Deploy the rebuilt Go binaries
  (server + doc-processor) so their queries find the new columns.
- Start the `pdf-parser` and converter services **after** the migration (the parser's queries
  reference `parse_state`).
- The backfill is one-time; the triggers keep the projections live thereafter.

## References

- Design doc: `KnowledgeStore/Capsules/coding-capsules/input-management/input-status-mgmt.md`
- Doc-processor capsule: `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md` §9
- PDF parser capsule: `KnowledgeStore/Capsules/coding-capsules/pdf-parser/+pdf-parser.md` §7
- Migration: `ChenWeb/project_migrations/20260609000002_add_kb_inputs_status_rollups.sql`
