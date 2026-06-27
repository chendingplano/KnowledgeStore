# ADR 2026062802 — Database Maintenance: Consistency Check UI and kb.inputs.status Deduplication

**Date:** 2026-06-28  
**Status:** Accepted  
**Component:** ChenWeb — System Admin / Database Maintenance  
**Tags:** database, consistency, kb.inputs, doc-processor, system-admin

---

## Change Logs

* 2026-06-28-01, ADR Created
* 2026-06-28-02, Added `kb.db_maintenance_logs` table, `ListMaintenanceLogs` API endpoint, and Maintenance Log UI page

---

## Context

### The inconsistency discovered

During investigation of a "Run Unfinished Only" search returning no results, record 398 was found to have conflicting state across two representations of the same data:

- **`kb.inputs.status`** (JSONB array, source of truth): contained an `extract_relation` entry with `proc_status: "in_progress"`
- **`kb.input_proc_status`** (trigger-maintained child table): contained a row with `proc_status: "success"` for the same record and processor

The dashboard was showing the record as in-progress; the server-side filter was treating it as succeeded. The two representations had diverged.

### Architecture: two representations, one source of truth

`kb.inputs.status` is the authoritative record of all pipeline activity for a given input. It is a JSONB array where each element records one processor's activity at a point in time (operation name, proc_status, timestamps, progress, errors).

`kb.input_proc_status` is a denormalised child table maintained by the PostgreSQL trigger `trg_sync_input_proc_status` (AFTER INSERT OR UPDATE OF status on `kb.inputs`). It holds one row per `(record_id, processor)` and is used for efficient server-side filtering (`WHERE EXISTS ...`). The trigger uses `DISTINCT ON (proc) ORDER BY proc, ord DESC`, which means it keeps the **last** entry per processor by array ordinality.

A third set of rollup columns on `kb.inputs` (`parse_state`, `pipeline_state`, `has_failed_proc`) is maintained by a companion trigger and also derived from `kb.inputs.status`.

The frontend function `computeStages` (in `doc-processor-dashboard-state.ts`) reads `kb.inputs.status` returned by the API and derives per-stage status client-side. Before this fix it took the **first** matching entry per processor, while the trigger took the **last**.

### Root cause: bug in appendEntityRelationStatus

`appendEntityRelationStatus` (in `extract-entity-relation.go`) is responsible for writing or updating a status entry in the `kb.inputs.status` array. Its replacement loop had a hardcoded comparison:

```go
if op != "extract_entity_relation" {
    out = append(out, e)   // keep existing entry unchanged
    continue
}
// replace
```

This was written when entity and relation extraction were a single combined processor (`extract_entity_relation`). ADR 2026061702 split this into two independent processors (`extract_entity` and `extract_relation`) each with their own `StatusOperation` value. After the split, the processors write entries with operation names `"extract_entity"` and `"extract_relation"`, but the replacement check still looked only for the old combined name.

Consequence: when `persistEntityRelationStatus` was called to write the final `success` entry for `extract_relation`, the loop found no entry with `operation == "extract_entity_relation"` to replace, so `replaced` stayed false and the success entry was **appended** as a second element alongside the earlier `in_progress` entry:

```
kb.inputs.status = [
  { "operation": "extract_relation", "proc_status": "in_progress", ... },  ← ord 1
  { "operation": "extract_relation", "proc_status": "success",     ... }   ← ord 2
]
```

`computeStages` took the first → showed `in_progress`.  
The trigger took the last (ord 2) → stored `success` in `kb.input_proc_status`.

### Why no existing check caught it

- The two representations are derived independently (trigger on write; frontend on read), so no single query reveals the divergence.
- The duplicate entries are valid JSON and pass all column constraints.
- Existing tests for `computeStages` used single-entry status arrays.

---

## Decision

### 1. Fix the write bug

Changed line 1494 of `extract-entity-relation.go` from:

```go
if op != "extract_entity_relation" {
```

to:

```go
if op != operation {
```

where `operation` is the local variable holding the actual operation name being written (`"extract_entity"`, `"extract_relation"`, or the legacy `"extract_entity_relation"` for backward compatibility). This ensures the replacement loop matches existing entries by the same operation that is being updated, regardless of which processor produced them.

### 2. Align computeStages with the trigger's ordering

Changed `computeStages` in `doc-processor-dashboard-state.ts` to always update `matchedStageEntry` (removing the `!matchedStageEntry` early-exit guard), so the function takes the **last** matching entry per processor, consistent with the trigger's `ORDER BY ord DESC` behaviour. This makes the frontend agree with `kb.input_proc_status` and correctly handles any existing records that already have duplicate entries from past runs.

### 3. Database Maintenance UI for existing stale records

Past pipeline runs have already written duplicate entries to `kb.inputs.status` for some records. These are not corrected by fixing the write path alone; they persist until the record is reprocessed.

A new **Database Maintenance → Consistency Check** panel is added under System Admin in the `/home3` navigation. It provides:

- A **Check** button that counts records with duplicate operation entries in `kb.inputs.status`.
- A **Fix** button (shown only when stale records are found) that runs the deduplication UPDATE, keeping the last entry per operation to match the trigger's ordering. The trigger fires automatically for each updated row, syncing `kb.input_proc_status` and the rollup columns without any additional intervention.

The UI is designed as an extensible list of check cards so future consistency checks can be added without structural changes.

### 4. Maintenance operation audit log

Every check or fix operation is recorded in `kb.db_maintenance_logs`. A new **Database Maintenance → Maintenance Log** page under System Admin displays the log with search (filter by operation and date range) and a paginated record list. Expanding a row shows the full JSON result payload.

---

## Implementation

### Backend

**New package:** `ChenWeb/server/api/dbmainthandler/handler.go`

| Endpoint | Method | Description |
|---|---|---|
| `/api/v1/admin/db/kb-inputs-status/check` | GET | Returns `{ stale_count: N }` |
| `/api/v1/admin/db/kb-inputs-status/fix` | POST | Deduplicates stale rows; returns `{ fixed_count: N }` |
| `/api/v1/admin/db/maintenance-logs` | GET | Returns paginated log rows from `kb.db_maintenance_logs`; supports `operation`, `date_from`, `date_to`, `page`, `page_size` filters |

**New migration:** `ChenWeb/project_migrations/20260628000001_create_kb_db_maintenance_logs.sql`

Creates `kb.db_maintenance_logs` (`id BIGSERIAL`, `operation TEXT`, `result_data JSONB`, `performed_at TIMESTAMPTZ`). Both check and fix handlers insert a row on completion.

The check query groups `jsonb_array_elements` by `lower(elem->>'operation')` and counts groups with more than one entry:

```sql
SELECT count(*)
FROM (
    SELECT i.id
    FROM kb.inputs i,
    LATERAL jsonb_array_elements(coalesce(i.status, '[]'::jsonb)) AS t(elem)
    WHERE i.status IS NOT NULL AND jsonb_array_length(i.status) > 0
    GROUP BY i.id, lower(elem->>'operation')
    HAVING count(*) > 1
) sub
```

The fix query uses `DISTINCT ON (lower(operation)) ORDER BY lower(operation), ord DESC` inside a `LATERAL` to select the last entry per operation, then `jsonb_agg(elem ORDER BY ord)` to reassemble the array in ascending ordinality order:

```sql
WITH deduped AS (
    SELECT i.id, jsonb_agg(d.elem ORDER BY d.ord) AS new_status
    FROM kb.inputs i,
    LATERAL (
        SELECT DISTINCT ON (lower(elem->>'operation')) elem, ord
        FROM jsonb_array_elements(coalesce(i.status, '[]'::jsonb)) WITH ORDINALITY AS t(elem, ord)
        ORDER BY lower(elem->>'operation'), ord DESC
    ) d
    WHERE i.status IS NOT NULL AND jsonb_array_length(i.status) > 1
    GROUP BY i.id
)
UPDATE kb.inputs
SET status = deduped.new_status
FROM deduped
WHERE kb.inputs.id = deduped.id
  AND kb.inputs.status IS DISTINCT FROM deduped.new_status
```

**Routes registered in** `routes.go` alongside other admin endpoints.

### Frontend

**New component:** `ChenWeb/web/src/lib/components/home3/db-consistency-view.svelte`

State machine per check card: `idle → checking → ok | stale | error`. Fix transitions `stale → ok` and reports the number of rows repaired.

**New component:** `ChenWeb/web/src/lib/components/home3/db-maint-log-view.svelte`

Search section with operation and date-range filters, paginated result table with expandable JSON detail rows. Fetches from `GET /api/v1/admin/db/maintenance-logs`.

**Nav rail** (`nav-rail.svelte`): added `Database Maintenance` as a foldable sub-group under `system-admin`, with `Consistency Check` (`id: sysadmin-db-consistency`) and `Maintenance Log` (`id: sysadmin-db-maint-log`) as grandchild items.

**Content panel** (`content-panel.svelte`): added imports and routing branches for `sysadmin-db-consistency` and `sysadmin-db-maint-log`.

### Bug fixes in existing files

| File | Change |
|---|---|
| `server/api/doc-processing/extract-entity-relation.go:1494` | `op != "extract_entity_relation"` → `op != operation` |
| `web/src/lib/components/home3/doc-processor-dashboard-state.ts:171` | Removed `!matchedStageEntry` guard; now takes last match per stage |

---

## Alternatives Considered

| Alternative | Reason rejected |
|---|---|
| One-shot SQL migration to fix existing data at deploy time | Correct for a production system, but this is a staging server. An operator-triggered fix button gives visibility into how many records are affected and lets the team confirm the count before committing the repair. |
| Fix computeStages only (always take last entry) | Treats the symptom (frontend display) without fixing the write bug, and leaves `kb.inputs.status` permanently carrying stale entries that accumulate with every future run. |
| Fix the write bug only (no UI, no computeStages change) | New runs would be correct, but existing stale records would continue to show wrong status on the dashboard until each record is manually reprocessed. The `computeStages` alignment fix is necessary for those records. |
| Add a scheduled background job to detect and repair divergence | Adds operational complexity (another goroutine, logging, scheduling). The divergence is deterministic and caused by a single known bug; one-time operator-triggered repair is appropriate. |
| Make `kb.input_proc_status` the frontend source of truth (expose it via API) | Would require a new API field and frontend changes across all status-reading code. `kb.inputs.status` already carries the full history needed for pipeline visualisation; using it directly is correct. The child table is a read-optimised projection for server-side filtering, not the canonical state. |

---

## Consequences

- `appendEntityRelationStatus` now correctly replaces existing entries for any operation name, preventing duplicate accumulation for all future pipeline runs.
- `computeStages` and `kb.input_proc_status` now agree: both take the last entry per processor in the array.
- Operators can check and repair existing stale records on demand without reprocessing them.
- The Database Maintenance section is extensible: future consistency checks (e.g., orphaned `kb.input_proc_status` rows, rollup column drift) can be added as additional check cards without structural changes to the UI or handler.
- No schema changes. `kb.inputs.status` remains the source of truth; `kb.input_proc_status` remains a trigger-maintained projection.

---

## References

- [ADR 2026061702](../202606/2026061702-adr-entity-relation-split.md) — Entity/Relation processor split that introduced the operation name change
- [ADR 2026062801](../202606/2026062801-adr-docprocessor-run-mode.md) — Run Mode Controls (predecessor; "Run Unfinished Only" misbehaviour was the symptom that surfaced this bug)
- `ChenWeb/server/api/doc-processing/extract-entity-relation.go` — `appendEntityRelationStatus` (write bug fix)
- `ChenWeb/web/src/lib/components/home3/doc-processor-dashboard-state.ts` — `computeStages` (ordering fix)
- `ChenWeb/server/api/dbmainthandler/handler.go` — check and fix endpoints
- `ChenWeb/web/src/lib/components/home3/db-consistency-view.svelte` — consistency check UI
- `ChenWeb/project_migrations/20260609000002_add_kb_inputs_status_rollups.sql` — trigger definitions
