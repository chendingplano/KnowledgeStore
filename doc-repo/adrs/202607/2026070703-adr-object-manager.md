# ADR Object Manager

**Date:** 2026-07-07 \
**Status:** Proposal \
**Component:** ChenWeb (Object Manager UI + kbhandler API) \
**Authors**: Chen Ding \

## Change Logs
* 2026/07/07, ADR Created
* 2026/07/07, Filled Decision/Implementation/Env Vars/Tests; fixed statistics
  and relation-traversal definitions; added resolution workflow.
* 2026/07/07, Corrected routes to real `/api/v1/kb/objects/...` prefix; noted
  existing reused endpoints (ambiguous list/detail/create-node, edit, audit log).
  Implemented backend relation-graph traversal (`POST /kb/objects/graph`,
  bounded BFS) with unit tests. Remaining: stats, connectivity, merge, PDF
  locator, general search, and the frontend page.
* 2026/07/07, Implemented statistics + connectivity endpoints
  (`/kb/objects/stats/artifact-objects`, `/kb/objects/stats/object-nodes`,
  `/kb/objects/connectivity`) with sqlmock tests. Remaining: merge, PDF locator,
  general search, and the frontend page.
* 2026/07/07, Implemented object-node merge (`POST /kb/objects/merge`) and PDF
  locator (`GET /kb/objects/pdf-locator`). Corrected DR4: backend returns
  document + line spans only; the reused Provisions viewer derives page/highlight
  client-side. Remaining: general search over both tables, and the frontend page.
* 2026/07/07, Implemented general search (`POST /kb/objects/search`) over both
  tables by query or `record_id`. **All Object Manager backend endpoints are now
  complete with tests.** Remaining: the frontend 3-panel page.
* 2026/07/07, Implemented the frontend: `objectManagerService.ts`,
  `object-manager-view.svelte` (three panels; draggable/resizable localStorage-
  persisted widget grid; ECharts relation chart, stats, connectivity; search;
  merge control; iframe PDF panel), and the `kb-object-manager` nav section.
  Typechecks clean. **Object Manager ADR is functionally complete.** Follow-ups:
  full PDF highlight overlay, and the fuller link/create/reject resolution flow.
* 2026/07/08, Frontend refinements: connectivity histogram is now a vertical-
  column chart (categories on x, counts on y); widget resize snaps to a row grid
  (heights) with column-snapped widths; added draggable Left|Middle and
  Middle|Right panel-width splitters (localStorage-persisted); the Left panel
  Search button now opens a conditions dialog (table/name/record-id → search →
  pick), matching the Provisions pattern; and scrollbars in the middle/right
  panels now match the Provisions styling.
* 2026/07/08, Object Resolution widget: link a mention to a candidate node,
  create a new node (or link an existing same-name node), or reject — reusing
  `resolve-ambiguous-objects-client.ts`; refreshes graph/PDF after changes.
  **All planned Object Manager work (backend + frontend) is complete.**
* 2026/07/08, Right panel PDF highlight overlay: replaced the iframe with the
  Provisions `pdf-view-window` viewer for PDFs — loads raw lines, parses the
  locator's line spans, opens to the first span's page, and highlights the
  located lines (read-only; iframe fallback for non-PDF). Typechecks clean.
* 2026/07/08, More frontend refinements: the Left panel now lists all
  `kb.object_nodes` by default on open, with Prev/Next paging (50/page) and a
  table pulldown; selecting a `kb.object_nodes` row now also populates Artifact
  Object Info (representative mention from the loaded graph); the Middle panel
  min width is halved via a dynamic container-width clamp (MIDDLE_MIN=140) so
  Left/Right can grow further; and the Search dialog is now Search &amp; Select —
  each result has a checkbox and a Select button commits the checked rows as the
  Left panel's working set.

## Purposes
Create an Object Manager page to let users:
- Search objects from `kb.artifact_objects`
- Search objects from `kb.object_nodes`
- A chart that shows the relations between a selected object and its related objects (see below)
- Edit records in `kb.artifact_objects` and `kb.object_nodes`
- Resolve ambiguous `kb.artifact_objects` (see below)

The page is similar to `ChenWeb/home3/knowledge`, "Wiki => Provisions".
The page has three panels:
- Left Panel
- Middle Panel
- Right Panel

### Left Panel

It is very similar to the Provisions' 'Record' list. There are, however, two tables: `kb.artifact_objects` and `kb.object_nodes` (refer to [1]). There should be a pulldown menu to let users select the table to list. The default is `kb.object_nodes`. The 'Search' button should adapt to the selected list. The 'RECORD ID' field is an integer. It fetches the `kb.artifact_objects` record by its `id` field or the `kb.object_nodes` record by its `id` field.

### Middle Panel
The entire panel is divided into a grid of four columns of equal width and height, and
multiple rows, and a number of components (see the section 'Components').
A component can occupy one or more columns.

Users can do the following with components:
- drag-and-move a component to a new location
- resize a component by dragging

The grid layout is persisted per user (see 'Layout Persistence' under Decision).

### Components

#### Component: Object Node Info
It shows the selected `kb.object_nodes`.

#### Component: Artifact Object Info
It shows the selected `kb.artifact_objects`.

#### Component: Object Relation Chart
It shows a chart (here is an example of the chart: https://echarts.apache.org/examples/en/editor.html?c=graph-label-overlap) that shows the selected object and the related artifacts (see 'Object Relations' below).

#### Component: Object Viewer
When a user clicks a node in the Object Relation Chart, it shows the selected
object in the form of name-value manner. Users can use it to view and/or edit
the object.

#### Component: Object Resolution
For a selected `kb.artifact_objects` row that is unresolved (`object_id IS NULL`)
or `reconcile_status IN ('pending','ambiguous')`, this component drives the
"resolve ambiguous objects" workflow (see 'Object Resolution' under Decision).

#### Component: Log
It lists the log entries `kb.object_audit_log` for the selected object.

#### Component: Artifact Object Statistics

It shows the statistics of the table `kb.artifact_objects`:

| Name | Explanation |
|------|-------------|
| Total | the total count of `kb.artifact_objects` |
| Provisions | the count of records with `artifact_type = 'provision'` |
| Metrics | the count of records with `artifact_type = 'metric'` |
| Inventory Items | the count of records with `artifact_type = 'inventory_item'` |
| Unresolved | the count of records whose `kb.artifact_objects.object_id IS NULL` |

`Provisions`, `Metrics`, and `Inventory Items` partition by `artifact_type` and are
mutually exclusive; show them (plus an `Other` slice for any remaining
`artifact_type`) in a donut chart with `Total` as the center label.

`Unresolved` is orthogonal to `artifact_type` (an unresolved row still has a type),
so it MUST NOT be a slice of the same donut. Show resolved-vs-unresolved as a
separate two-value indicator (KPI pair or small stacked bar).

#### Component: Object Nodes Statistics

It shows the statistics of the table `kb.object_nodes`:

| Name | Explanation |
|------|-------------|
| Total | the total count of `kb.object_nodes` |
| Provisions | the count of nodes connected to at least one `provision` artifact object |
| Metrics | the count of nodes connected to at least one `metric` artifact object |
| Inventory Items | the count of nodes connected to at least one `inventory_item` artifact object |

A single `kb.object_nodes` row can connect to artifact objects of multiple types,
so these counts overlap and do NOT sum to `Total`. Show them as a bar chart (not a
pie) labelled with `Total`, to avoid implying a partition.

#### Component: Object Node Connectivity
A `kb.object_nodes` record may connect to multiple `kb.artifact_objects`. The more
`kb.artifact_objects` records a `kb.object_nodes` connects, the 'hotter'
the `kb.object_nodes` is.

Use a histogram to show the Top N most connected `kb.object_nodes` in descending
order, where N can be selected by a pulldown menu with [20, 50, 100, 200, 300],
default to 50.

### Object Relations

The relation graph feeding the Object Relation Chart is built by a backend
traversal. Because a canonical object aggregates many mentions, the traversal is
keyed on `object_id` but MUST also be reachable from a single unresolved mention
row (whose `object_id` is `NULL`).

Two entry points:

- `GetConnectedNodesByObjectId(object_id string)` — seeds from a canonical
  `kb.object_nodes` identity.
- `GetConnectedNodesByArtifactObjectId(id int64)` — seeds from a single
  `kb.artifact_objects` mention row, used when the mention is unresolved so the
  user can still reach and resolve it.

If the selected object is a `kb.artifact_objects` row with a non-null
`object_id`, the two entry points are equivalent (seed from that `object_id`).

#### Graph model
- Node types: `object_node` (canonical), `artifact_object` (mention),
  `artifact` (metric / provision / inventory_item).
- Edge types: `mentions` (object → artifact_object), `about`
  (artifact_object → artifact), `similar` (artifact → artifact, from hybrid
  search), `same_object` (artifact_object → object_node).

#### Traversal (breadth-first, bounded)
Starting from the seed object(s), for each level up to
`OBJECT_CHART_RECURSIVE_LEVEL` (default 3):

1. From the current `object_id`, collect its `kb.object_nodes` row and all
   `kb.artifact_objects` rows where `kb.artifact_objects.object_id = object_id`
   (Node Set A).
2. For each mention in A, resolve its artifact via `artifact_type` + `artifact_id`
   (provisions, metrics, inventory items) — Node Set B.
3. For each artifact in B, run hybrid search for the top
   `SIMILAR_ARTIFACT_TOP_N` (default 10) similar artifacts — Node Set C.
4. For each similar artifact in C, look up `kb.artifact_objects` by matching
   `artifact_id`, and read its `object_id` — Node Set D. Enqueue each new
   `object_id` for the next level.

Guards (required — the original definition had none and would explode/cycle):

- Maintain a **visited set** keyed on `object_id`; never expand the same object
  twice.
- Enforce a global node cap `OBJECT_CHART_MAX_NODES` (default 300); stop
  expanding when reached and mark the result `truncated`.
- Deduplicate nodes and edges across all sets before returning.
- Rows with `object_id IS NULL` are rendered as terminal `artifact_object` nodes
  (so they are visible and resolvable) but are not used as recursion seeds.

## Decision

### DR1: Reuse the Provisions page shell
The Object Manager reuses the `ChenWeb/home3/knowledge` "Wiki => Provisions"
three-panel layout, its Record list, and its PDF viewer, parameterized over the
selected table (`kb.object_nodes` default, `kb.artifact_objects`).

### DR2: Bounded, deduplicated relation traversal
The relation graph is built by the bounded BFS in 'Object Relations' with a
visited set, `OBJECT_CHART_MAX_NODES` cap, and cross-set dedup. Unresolved
mentions are terminal nodes, not recursion seeds.

### DR3: Object Resolution workflow
The "resolve ambiguous objects" purpose is implemented by the Object Resolution
component. For a selected unresolved/ambiguous `kb.artifact_objects` row it:

- lists candidate `kb.object_nodes` (from the same reconciliation logic in ADR
  2026070101: exact/alias/acronym/name-bundle, lexical, optional vector), each
  with a match score;
- lets the user **Link** the mention to a candidate (sets `object_id`,
  `reconcile_status='matched'`, `reconcile_confidence`);
- lets the user **Create** a new `kb.object_nodes` row from the mention;
- lets the user **Reject** (`reconcile_status='rejected'`); and
- lets the user **Merge** two `kb.object_nodes` (sets the loser's
  `canonical_object_id`, `reconcile_status='merged'`), preserving all
  `kb.artifact_objects` evidence rows per ADR 2026070101 DR3.

All actions write a log entry (Log component) and are auditable.

### DR4: PDF locator resolves a canonical node to one mention
Because a `kb.object_nodes` node aggregates mentions across documents, clicking a
node does not by itself identify a PDF location. The Right Panel opens the PDF for
a specific `kb.artifact_objects` mention. When a canonical node is clicked
(`object_id`), the backend picks a representative mention (highest `confidence`,
tie-broken by most recent `modify_time`) and returns its document and
`source_line_spans`. When a mention node is clicked directly
(`artifact_object_id`), its own spans are used.

The backend does **not** return a page number. `kb.artifact_objects` stores only
line spans, and the reused Provisions PDF viewer already maps line spans to pages
client-side (its `lineNumToPage`, built from the loaded document lines). The
locator therefore returns `document` + `source_line_spans` + `input_record_id`,
and the viewer derives page and highlight exactly as it does for provisions. If a
canonical node has mentions in multiple documents, the Object Viewer shows a
mention picker.

### DR5: Layout Persistence
The Middle Panel grid layout (component positions/sizes) is persisted per user so
it survives reloads. Store as a JSON blob in the existing user-preferences store
(no new table required); key by `page='object-manager'`.

### Alternative Decisions

#### AD1: Include unresolved mentions as recursion seeds
Rejected. Unresolved mentions have no `object_id`, so they cannot anchor a stable
canonical traversal and would fan out ambiguously. They are rendered as terminal
nodes and resolved via the Object Resolution component instead.

#### AD2: Single pie mixing artifact types and `Unresolved`
Rejected. `Unresolved` is orthogonal to `artifact_type`; mixing them double-counts
and the slices do not sum to `Total`. Split into a type donut plus a separate
resolved/unresolved indicator (see Artifact Object Statistics).

#### AD3: Pie chart for Object Nodes Statistics
Rejected. A node can connect to multiple artifact types, so the categories overlap
and a pie misrepresents them; use a bar chart.

### Database Migrations
None. This ADR adds a read/edit UI over the tables created by ADR 2026070101
(`kb.artifact_objects`, `kb.object_nodes`) and reuses their existing indexes.
Grid layout persistence reuses the existing user-preferences store.

### Data Formats
Graph response (from both `GetConnectedNodes*` entry points):

```json
{
  "seed_object_id": "string|null",
  "truncated": false,
  "nodes": [
    {
      "key": "object:<object_id> | ao:<id> | artifact:<type>:<artifact_id>",
      "type": "object_node|artifact_object|artifact",
      "label": "string",
      "object_id": "string|null",
      "artifact_type": "metric|provision|inventory_item|null",
      "reconcile_status": "string|null"
    }
  ],
  "edges": [
    { "from": "key", "to": "key", "type": "mentions|about|similar|same_object" }
  ]
}
```

PDF locator response (no `page` — the viewer derives it from spans, see DR4):

```json
{
  "artifact_object_id": 0,
  "input_record_id": 0,
  "document": "string",
  "source_line_spans": ["12", "13:15"]
}
```

### Environment Variables

| Env var | Default | Purpose |
|---|---|---|
| `SIMILAR_ARTIFACT_TOP_N` | `10` | Similar artifacts fetched per artifact during traversal |
| `OBJECT_CHART_RECURSIVE_LEVEL` | `3` | Max BFS depth for the relation graph |
| `OBJECT_CHART_MAX_NODES` | `300` | Global node cap; traversal stops and sets `truncated` |

## Implementation

The real route prefix is `/api/v1/kb/objects/...` (Echo `apiGroup` in
`ChenWeb/server/api/routes.go`), not `/api/v1/object-manager/...`. Much of the
Object Resolution / edit / audit surface already exists and is reused.

### API

**Already implemented (reused as-is):**

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/v1/kb/objects/ambiguous` | Left-panel list of ambiguous artifact objects |
| GET | `/api/v1/kb/objects/ambiguous/:id` | Artifact object + ranked candidate object nodes |
| POST | `/api/v1/kb/objects/ambiguous/:id/create-node` | Create-New object node from a mention |
| POST | `/api/v1/kb/objects/resolve-ambiguous` | Batch reconciliation pass |
| PATCH | `/api/v1/kb/objects/artifact-objects/:id` | Edit `kb.artifact_objects` (audit-logged) |
| PATCH | `/api/v1/kb/object-nodes/:object_id` | Edit `kb.object_nodes` (audit-logged) |

**Implemented in this ADR:**

| Method | Path | Purpose |
|---|---|---|
| POST | `/api/v1/kb/objects/graph` | Build relation graph from `object_id` or `artifact_object_id` (bounded BFS) |
| GET | `/api/v1/kb/objects/stats/artifact-objects` | Artifact Object Statistics (type partition + `other` + `unresolved`) |
| GET | `/api/v1/kb/objects/stats/object-nodes` | Object Nodes Statistics (overlapping per-type node counts) |
| GET | `/api/v1/kb/objects/connectivity?top_n=50` | Object Node Connectivity histogram (top_n clamped to [20,50,100,200,300]) |
| POST | `/api/v1/kb/objects/merge` | Merge two object nodes: repoint evidence mentions to survivor, mark loser `merged` |
| GET | `/api/v1/kb/objects/pdf-locator?artifact_object_id=` or `?object_id=` | Resolve node → document + line spans (DR4) |
| POST | `/api/v1/kb/objects/search` | General list/search over either table by query or `record_id` (Left Panel) |

**Backend and the frontend page are complete.** Remaining items are non-blocking
follow-ups (full PDF highlight overlay; fuller link/create/reject resolution
flow) — see Code Changes.

### Code Changes

Backend — done in this ADR:
- `ChenWeb/server/api/kbhandler/object_graph.go` — `BuildObjectGraph` bounded BFS
  (visited set, `MaxNodes` cap, cross-set dedup), graph node/edge types, and the
  `objectGraphSource` interface for testability.
- `ChenWeb/server/api/kbhandler/object_graph_handler.go` —
  `sqlObjectGraphSource` (backed by `ArtifactObjectSQLStore.LoadByID` +
  `FindSimilarArtifactsOnTheFly`), `GetConnectedNodesByObjectId`,
  `GetConnectedNodesByArtifactObjectId`, env option parsing, and
  `BuildObjectGraphHandler`.
- `ChenWeb/server/api/kbhandler/object_graph_test.go` — BFS unit tests.
- `ChenWeb/server/api/kbhandler/object_stats.go` — `GetArtifactObjectStats`,
  `GetObjectNodeStats`, `GetObjectConnectivity`, and `clampConnectivityTopN`.
- `ChenWeb/server/api/kbhandler/object_stats_test.go` — stats/connectivity tests
  (sqlmock) + top_n clamping unit test.
- `ChenWeb/server/api/routes.go` — registers `POST /kb/objects/graph`,
  `GET /kb/objects/stats/artifact-objects`, `GET /kb/objects/stats/object-nodes`,
  `GET /kb/objects/connectivity`.

- `ChenWeb/server/api/kbhandler/object_merge.go` — `MergeObjectNodes` +
  `validateMergeObjectNodes`; `object_merge_test.go` (sqlmock + validation).
- `ChenWeb/server/api/kbhandler/object_pdf_locator.go` — `GetObjectPDFLocator` +
  `resolveLocatorMention`; `object_pdf_locator_test.go` (sqlmock).
- `ChenWeb/server/api/kbhandler/object_search.go` — `SearchObjects`,
  `normalizeSearchTable`, `clampObjectSearchPageSize`, per-table search;
  `object_search_test.go` (sqlmock + validation).
- `ChenWeb/server/api/routes.go` — registers graph/stats/connectivity/merge/
  pdf-locator/search routes.

Backend is complete. Remaining: the frontend page.

Backend — already present (reused): `ambiguous_objects_handler.go`,
`resolve_ambiguous_objects_handler.go`, `object_audit_log.go`,
`object_ambiguous_resolution.go`, `object_nodes.go`, `artifact_objects.go`.

Frontend (`ChenWeb/web/src`) — done in this ADR:
- `lib/services/objectManagerService.ts` — typed client for all six endpoints.
- `lib/components/home3/object-manager-view.svelte` — three-panel page. Left:
  table pulldown (`kb.object_nodes` default) + search + RECORD ID, wired to
  `POST /kb/objects/search`. Middle: draggable/resizable widget grid (HTML5 drag
  to reorder, native `resize` for height, colspan stepper; layout persisted to
  `localStorage['object-manager:layout:v1']` per DR5 — no backend table).
  Widgets: Object Node Info (+ merge control), Artifact Object Info, Object
  Relation Chart (ECharts force graph, node-click loads locator), Artifact Object
  Statistics (donut + unresolved), Object Nodes Statistics (bar), Connectivity
  (Top-N bar), Log. Right: PDF panel driven by `GET /kb/objects/pdf-locator`.
- `routes/home3/knowledge/+page.svelte` — registers the `kb-object-manager`
  nav section and mounts the view. Typechecks clean (`svelte-check`).

Frontend — Right panel PDF (done):
- The Right panel now embeds the full `pdf-view-window` viewer for PDF documents
  (falling back to an `<iframe>` for non-PDF). It loads the located document's raw
  lines (`getRawLines`), parses the locator's `source_line_spans` into
  page/line pairs, opens to the first span's page, and draws `.pdf-highlight`
  overlay boxes for the located lines (`renderLocatorHighlights`), mirroring the
  Provisions highlight machinery. Selection/sidebar are disabled (read-only).

Frontend — Object Resolution (done):
- New "Object Resolution" widget: for the selected artifact object (mention) it
  loads ranked candidate nodes (`getAmbiguousObjectDetail`) and offers **Link**
  (to a candidate → `object_id` + `reconcile_status='ambiguous_resolved'`),
  **Create New** (`createObjectNode`; if the name already exists it returns those
  nodes to link instead), and **Reject** (`reconcile_status='rejected'`), all via
  the existing `resolve-ambiguous-objects-client.ts`. After a change it refreshes
  candidates and reloads the graph/PDF. The merge control on Object Node Info
  remains for node-to-node merges.

All planned Object Manager work (backend + frontend) is now complete; no
outstanding follow-ups remain in this ADR.

## Operational Behaviors
- Read/search/stats endpoints are read-only.
- Edit and resolve endpoints mutate `kb.artifact_objects` / `kb.object_nodes`;
  every mutation writes a Log entry and never deletes evidence mention rows
  (ADR 2026070101 DR3).
- Graph builds are bounded by `OBJECT_CHART_RECURSIVE_LEVEL` and
  `OBJECT_CHART_MAX_NODES`; large graphs return `truncated: true` rather than
  timing out.

## Consequences

Positive:
- Gives operators a single page to search, inspect, edit, and reconcile objects.
- Bounded traversal keeps the relation chart responsive and cycle-safe.
- No schema migrations; builds entirely on ADR 2026070101 tables.

Tradeoffs:
- Draggable/resizable grid plus per-user layout is non-trivial frontend work.
- Truncated graphs may hide relations beyond the node cap; the cap is tunable.
- Representative-mention selection (DR4) is a heuristic; a canonical node with
  many documents needs the mention picker to be unambiguous.

## Tests
- Search returns rows from each table and honors the table pulldown + RECORD ID.
- `stats/artifact-objects`: type counts are mutually exclusive; `Unresolved`
  counts `object_id IS NULL`; type slices + `Other` sum to `Total`.
- `stats/object-nodes`: type counts may overlap; not asserted to sum to `Total`.
- Connectivity returns Top N nodes in descending connection count for each N.
- Graph traversal: respects `OBJECT_CHART_RECURSIVE_LEVEL`, never revisits an
  `object_id`, dedups nodes/edges, and sets `truncated` at `OBJECT_CHART_MAX_NODES`.
- Graph traversal terminates on a cyclic `similar` graph.
- Unresolved mentions appear as terminal nodes and are reachable via
  `GetConnectedNodesByArtifactObjectId`.
- Resolve: Link/Create/Reject/Merge update the correct fields, preserve evidence
  rows, and write Log entries.
- PDF locator returns a document/page/spans for a mention, and picks a
  representative mention for a canonical node.

## Documentation Impact
- Add an Object Manager section to the ChenWeb knowledge/UI docs.
- Cross-reference ADR 2026070101 for the underlying object model and
  reconciliation semantics reused by the Object Resolution workflow.

## References
- [1] KnowledgeStore/doc-repo/adrs/202607/2026070101-adr-object-centric-design.md
