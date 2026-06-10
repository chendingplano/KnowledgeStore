# Background
The table `kb.inputs` stores all the input documents. A document is processed by a Doc Process
pipeline (refer to [1]). Doc processor status is currently managed by a JSON doc stored in
`kb.inputs.status`.

One major problem with the current implementation is that querying records by status can be
slow. `kb.inputs` may hold millions, even tens of millions, of rows.

# Problem

`kb.inputs.status` is a JSON **array** holding one entry per processor:

```json
[
  { "operation": "parsed",          "proc_status": "success", "start_time": "...", "ms_used": 12 },
  { "operation": "static_analyzer", "proc_status": "success", "start_time": "...", "ms_used": 40 },
  { "operation": "extract_metrics", "proc_status": "failed",  "error": "...",      "ms_used": 91 },
  { "operation": "doc_processing",  "proc_status": "running" }
]
```

Every "find records by status" query (the doc-processor dashboard, the ingestion list, the
Dev-Mode `all: parsed | failed-procs` selectors) had to evaluate a predicate *inside* this array,
e.g.

```sql
EXISTS (SELECT 1 FROM jsonb_array_elements(i.status) st WHERE ...)
-- or jsonb_path_exists(status, '$[*] ? (@.proc_status == "failed")')
```

A JSON array predicate cannot use a normal index, so each of these is a **sequential scan that
parses every row's JSON**. At tens of millions of rows that is seconds-to-minutes per query and
degrades linearly. The single status blob is also a write-contention point: every processor does a
read-modify-write of the whole array under a per-record mutex (see [1] §7.3).

# Solution

Keep `kb.inputs.status` as the source of truth, but maintain two **indexed projections** of it:

1. **Rollup columns on `kb.inputs`** — for the whole-table dashboard / list filters:
   - `parse_state`    — `pending | parsing | parsed_success | parsed_failed` (from the PDF parser's
     `parsed` entry; `parsing` = an in-progress claim, `proc_status = active`)
   - `pipeline_state` — `pending | running | success | failed | stopped` (from the aggregate
     `doc_processing` entry)
   - `has_failed_proc` — boolean; true only for *real* doc-processor failures (parse / convert
     failures are captured by `parse_state`, matching the existing `failed-procs` selector)
2. **Child table `kb.input_proc_status`** — one row per `(record_id, processor)` for per-processor
   queries ("which records failed on `extract_metrics`"). Includes every processor: parsing,
   converting, static_analyzer, extract_*, generate_*, etc.

Both projections are maintained by **database triggers** on `kb.inputs`, *not* by application code.

## Why a trigger, not application code

`kb.inputs.status` is written from **7+ call sites across 4 separate binaries** (pdf-parser,
service-pdf-parser, file-converters, doc-processor — plus the stop handler). Maintaining the
projections in Go would mean patching every writer and remembering to patch every future one — the
"I may miss some" trap. A trigger is evaluated by the database on *every* write, so:

- **No doc processor changes.** Processors keep appending to `status` exactly as before.
- **No missed writers**, now or in the future, regardless of which service writes the status.
- The projections can never drift from `status`, because they are derived from it on every write.

## Schema (migration)

`ChenWeb/project_migrations/20260609000002_add_kb_inputs_status_rollups.sql`:

- Immutable SQL helpers `kb.canonical_op(text)`, `kb.input_status_parse_state(jsonb)`,
  `kb.input_status_pipeline_state(jsonb)`, `kb.input_status_has_failed_proc(jsonb)` — the single
  source of derivation logic, used by both the triggers and the backfill. `canonical_op` mirrors
  `canonicalOperationName` in `ChenWeb/server/api/doc-processing/event.go`.
- `ALTER TABLE kb.inputs ADD parse_state, pipeline_state, has_failed_proc` (constant defaults →
  fast metadata-only change even on a huge table).
- `CREATE TABLE kb.input_proc_status (record_id, processor, proc_status, start_time, ms_used,
  error, modify_time)`, PK `(record_id, processor)`, FK to `kb.inputs(id) ON DELETE CASCADE`.
- One-time **backfill** of existing rows (set-based; does not touch `status`, so it does not
  re-fire the triggers).
- Indexes (created after backfill):
  - `idx_kb_inputs_pipeline_active` — **partial** `WHERE pipeline_state IN ('pending','running')`.
    Only a tiny fraction of rows are ever active, so this stays small regardless of table size —
    the key win for the live dashboard.
  - `idx_kb_inputs_has_failed_proc` — partial `WHERE has_failed_proc`.
  - `idx_kb_inputs_parse_state`, `idx_kb_inputs_pipeline_state` — btree.
  - `idx_kb_input_proc_status_processor_status (processor, proc_status)` and partial
    `idx_kb_input_proc_status_failed`.
- Triggers:
  - `trg_refresh_input_status_rollups` — `BEFORE INSERT OR UPDATE OF status`, sets the three
    rollup columns on `NEW`.
  - `trg_sync_input_proc_status` — `AFTER INSERT OR UPDATE OF status`, re-derives the child rows
    for that record (`DELETE` + `INSERT … DISTINCT ON (processor)`).

## Query changes (read side)

The slow `jsonb_array_elements` / `jsonb_path_exists` predicates were replaced with indexed
column / child-table lookups:

| Site | Before | After |
|---|---|---|
| `handler.go` `buildWhereClause` `parse_state` filter | `EXISTS(jsonb_array_elements …)` | `i.parse_state = …` |
| `handler.go` `pipeline_filter` (`parsed_not_started`, `all_processors_success`, `failed_processors`) | nested `EXISTS`/`NOT EXISTS` over the array | `i.parse_state` / `i.pipeline_state` equality |
| `handler.go` `operation` + `proc_status` filter | `EXISTS(jsonb_array_elements …)` | `EXISTS(SELECT 1 FROM kb.input_proc_status ps WHERE ps.processor = kb.canonical_op($n) AND ps.proc_status = …)`; the aggregate `doc_processing` operation maps to `i.pipeline_state` |
| `extract-doc-metadata-store.go` `ListParsedInputRecords` | `jsonb_path_exists(… parsed == success)` | `parse_state = 'parsed_success'` |
| `extract-doc-metadata-store.go` `ListRecordsWithFailedDocProcessors` | `jsonb_path_exists(… proc_status == failed)` | `has_failed_proc` (Go post-filter kept for exact per-processor list) |

## Impact on the three call sites called out

1. **Doc processors** (`[1]`) — **no code change**. They keep writing `kb.inputs.status`; the
   trigger maintains the projections. The capsule documents the new model.
2. **Dashboard → Doc Processor** (`ChenWeb /home3`) — **no frontend change**. It calls
   `GET /api/v1/kb/inputs` with the same query params and gets the same response shape; only the
   server-side `WHERE` clause changed, so it is simply faster.
3. **Ingestion → Upload Files** (`ChenWeb /home3/knowledge`) — **no frontend change** for the same
   reason. New uploads insert into `kb.inputs` with `status = '[]'`; the `BEFORE INSERT` trigger
   initializes the rollups to `pending`.
4. **PDF Parser** (`ChenWeb/python/pdf-parser`, see
   `KnowledgeStore/Capsules/coding-capsules/pdf-parser/+pdf-parser.md`) — status **writes** need no
   change (the trigger maintains `parse_state`). Its two status **reads** were migrated off
   `jsonb_path_exists` to the indexed `parse_state` column: `claim_candidates` (`parse_state =
   'pending'` or stale `'parsing'`) and `find_duplicate_processed_record` (`parse_state =
   'parsed_success'`). This is why `parse_state` distinguishes `parsing` (in-progress claim,
   `proc_status = active`) from `pending` (never parsed).

## Adding a future doc processor

Because the child table is keyed by processor *value*, a new processor needs **no schema change**:
it just writes its status entry into `kb.inputs.status` as today, and the trigger creates its
`kb.input_proc_status` row automatically. (Only update `kb.canonical_op` if the new processor
introduces a legacy operation-name alias.)

# References
[1] KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md
