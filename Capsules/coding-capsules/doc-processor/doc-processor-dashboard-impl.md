# Doc Processor Dashboard — Implementation Notes

## Location

| Artifact | Path |
|---|---|
| View component | `ChenWeb/web/src/lib/components/home3/doc-processor-dashboard-view.svelte` |
| Nav rail (wiring) | `ChenWeb/web/src/lib/components/home3/nav-rail.svelte` |
| Content panel (wiring) | `ChenWeb/web/src/lib/components/home3/content-panel.svelte` |

**Route:** Home3 → Dashboard → Doc Processor (`childId: 'doc-processor-dashboard'`)

## Component Overview

Single Svelte 5 component (`$props`, `$state`, `$derived`) with two sections:

### Section 1 — Active Pipelines

Polls `GET /api/v1/kb/inputs` (page 1, page size 20) every 5 s via `setInterval` in `onMount` with cleanup. Results are filtered client-side: `.zip` records are excluded first (by `file_name` suffix), then `isActiveRecord()` is applied, capped at 10.

**Active record detection (`isActiveRecord`):**
- No status entries → considered staged/active
- Any entry has a non-final `proc_status` → active
- Blocking has succeeded but any downstream processor (`structure_analyzer`, `chunking`, `extract_doc_metadata`, `extract_metrics`, `extract_provisions`, `generate_summaries`, `generate_topics`) lacks a final status → active (prevents premature dismissal when blocking finishes before leaf processors start)
- Finalized values: `success`, `fail`, `failed`

Each record renders a pipeline card with a horizontal node chain:

```
[Staged] ── [PDF Parser] ── [Result Converter] ── [Blocking] ── [Leaf processors (vertical)]
```

Node state mapping from `kb.inputs.status` array:

| `operation` value | Stage |
|---|---|
| `parsing`, `parsed` | PDF Parser |
| `converting`, `line-file-generated` | Result Converter |
| `blocking` | Blocking |
| `structure_analyzer`, `chunking`, `extract_doc_metadata`, `extract_metrics`, `extract_provisions`, `generate_summaries`, `generate_topics` | Leaf processors |

Node visual states: pending (dimmed clock), in-progress (pulsing dot + ring animation), success (green check), failed (red X).

Hovering any node shows a fixed-position tooltip with: stage name, status, progress %, timestamp, and error message if present.

Card footer: Stop button (disabled — no server API exists yet) and Restart button (opens processor-picker dialog).

### Section 3 — Failed Pipelines

Collapsed by default. A chevron toggle in the section header expands/collapses the panel. Section header also shows the total failed-record count (loaded on first expand or after a manual refresh).

**Data fetch:** Calls `GET /api/v1/kb/inputs` with query params `has_failed=true`, `order_by=create_time`, `order=desc`, `page=N`, `page_size=30`. The backend filters rows where the `status` JSONB array contains at least one element with `"status": "failed"`.

**Refresh:** A **Refresh** button in the section header re-fetches the current page. No auto-polling.

**Pagination:** Standard page controls (Previous / page indicator / Next) rendered below the table. `pageSize` fixed at 30 (not user-configurable). Maintains current page across refresh; resets to page 1 on collapse–expand cycle.

**Table columns:**

| Column | Source |
|---|---|
| ID | `record.id` |
| Title | `record.title` (falls back to `record.doc_no`, then `record.staging_filename`) |
| Failed Steps | Comma-separated list of `entry.operation` values where `entry.status === 'failed'` in `record.status` |
| Created | `record.create_time` formatted as `yyyy-MM-dd HH:mm` |
| Actions | **Restart** button — opens the same processor-picker dialog used by Active Pipelines |

**Failed-step detection:** Mirrors Active Pipelines logic — checks `entry.status`, `entry.proc_status`, and `entry['proc-status']` against the value `'failed'` (or `'fail'`) to accommodate both schema variants.

### Section 2 — Manual Launch

Search by record ID (numeric) or title substring → `listKbInputs` from `$lib/services/kbService`. Results render in a table; clicking a row selects it.

With a record selected, a processor checkbox group appears:
- `blocking` — always on, shown disabled
- `structure_analyzer`, `chunking`, `extract_doc_metadata`, `extract_metrics`, `extract_provisions`, `generate_summaries`, `generate_topics` — individually togglable, toggle-all available

Launch flow:
1. User clicks **Launch** → confirmation dialog lists the record and chosen processors
2. On confirm → `POST /api/v1/jetstream/events` with body:
   ```json
   { "subject": "kb.line-file-generated", "data": { "record_id": "N", "force": true } }
   ```
   If fewer than all processors selected, `"operation": ["chunking", ...]` is added; if all selected, `operation` is omitted (pipeline runs all).
3. Success/error toast auto-dismisses after 4 s.

Restart dialog (from Active Pipelines) follows the same payload logic.

## Key Local Types

```typescript
type StageStatus = 'pending' | 'in-progress' | 'success' | 'failed';

type StatusEntry = {
    operation?: string; time?: string; start_time?: string;
    status?: string; proc_status?: string; 'proc-status'?: string;
    error?: string; progress?: string;   // progress not in KbInputRecord base type — cast required
};
```

`StatusEntry` extends the `KbInputRecord['status'][number]` shape with `progress`. Entries from `record.status` are cast to `StatusEntry` when read into the internal `statusMap`.

`PIPELINE_FINAL_OPS` — the complete set of doc-processor operations that must reach a final state: `blocking`, `structure_analyzer`, `chunking`, `extract_doc_metadata`, `extract_metrics`, `extract_provisions`, `generate_summaries`, `extract_entity_relation`.

`ALL_PROCESSOR_IDS` — the subset of processors that can be explicitly requested in launch/restart payloads: `structure_analyzer`, `chunking`, `extract_doc_metadata`, `extract_metrics`, `extract_provisions`, `generate_summaries`, `generate_topics`, `extract_entity_relation`.

## Wiring

`nav-rail.svelte` — `dashboard` nav item now has a `children` array:
```typescript
{ id: 'dashboard', label: 'Dashboard', icon: LayoutDashboardIcon, group: 'Workspace',
  children: [{ id: 'doc-processor-dashboard', label: 'Doc Processor' }] }
```

`content-panel.svelte` — first branch in the content router:
```svelte
{#if activeMenu?.childId === 'doc-processor-dashboard'}
    <DocProcessorDashboardView {darkMode} />
{:else if ...}
```

## Known Limitations

- **Active detection is heuristic.** There is no dedicated server endpoint that returns in-progress records. The dashboard fetches the 20 most recently modified records and infers status client-side. Records that have stalled with an incomplete status entry will appear active indefinitely until their status is updated.
- **Stop is not implemented.** No server API exists to interrupt a running pipeline thread. The Stop button is rendered disabled with a tooltip.
- **Poll scope.** Only the 20 most recently modified records are fetched per poll cycle. Long-running pipelines that haven't been modified recently may not appear.
- **`has_failed` filter requires backend support.** The Failed Pipelines section depends on the server accepting `has_failed=true` as a query parameter and filtering on the `status` JSONB column. Until this is implemented server-side, the section cannot paginate correctly and a client-side fallback (fetching a large page and filtering in-browser) will miss older records.

## Extension Points

- **Stop API:** When a stop endpoint exists, wire it to the disabled Stop button (remove `disabled`, call the endpoint, then refresh pipelines).
- **Server-side active filter:** If the backend adds a `parse_state=in_progress` or similar filter that reliably returns only active records, replace the client-side `isActiveRecord` filter with `parseState: 'in_progress'` in the `listKbInputs` call.
- **WebSocket / SSE:** Replace `setInterval` polling with a server-sent event stream for real-time updates without repeated HTTP overhead.
- **Progress bar:** If `progress` values follow a consistent format (e.g. `"42%"`), parse the numeric value and render a thin progress bar under each in-progress node.
- **Failed Pipelines — backend filter:** Add `has_failed=true` query-param support to `GET /api/v1/kb/inputs` (PostgreSQL: `WHERE status @> '[{"status":"failed"}]'` or equivalent `jsonb_array_elements` check). Once available, remove the known limitation note above.
