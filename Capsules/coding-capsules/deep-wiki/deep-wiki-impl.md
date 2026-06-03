# Deep Wiki Implementation

Implementation notes for the SemOS Deep Wiki entrance page specified in
[+deep-wiki-rqmt.md](+deep-wiki-rqmt.md). This document records what was built,
where it lives, and the contracts between the pieces.

## Summary

The Deep Wiki is the main entrance to SemOS. It is a standalone SvelteKit route
in ChenWeb that renders three panels (A: corpus overview, B: portal directory,
C: recent activity) backed by a single aggregation endpoint in the Go server.

```text
Browser ──GET /api/v1/kb/wiki-overview──► Echo (kbhandler.WikiOverview)
   ▲                                          │
   │  WikiOverviewResponse (JSON)             ├─ counts: 10 COUNT(*) queries
   └──────────────────────────────────────────┤  (kb.inputs, chunks, topics,
   render Panels A / B / C                     │   semantic_projections, metrics,
                                               │   provisions, products, scene_objects,
                                               │   entities, relations)
                                               └─ recent: adds / edits / processed / errors
```

## Files

| Layer | Path | Role |
|---|---|---|
| Route (page) | `ChenWeb/web/src/routes/deep-wiki/+page.svelte` | The entire entrance page: Panels A, B, C, search, language, states |
| Service | `ChenWeb/web/src/lib/services/kbService.ts` | `getWikiOverview()` + `Wiki*` types |
| Handler | `ChenWeb/server/api/kbhandler/wiki_overview_handler.go` | `WikiOverview` aggregation handler |
| Route reg. | `ChenWeb/server/api/routes.go` | `apiGroup.GET("/kb/wiki-overview", kbhandler.WikiOverview)` |
| Nav entry | `ChenWeb/web/src/routes/home3/knowledge/+page.svelte` | "Wiki ⇒ LLM Wiki" menu item that routes to `/deep-wiki` |

## Backend: `GET /api/v1/kb/wiki-overview`

Defined in `kbhandler.WikiOverview`. Sits behind the same auth middleware as the
rest of `/api/v1/kb`. Uses `ApiTypes.ProjectDBHandle` and `EchoFactory`
(reason code prefix `CWB_KB_WIKI_*`).

### Design principle: degrade, never fail

Each count and each list is computed by an isolated helper. Any single query
error is logged at `Warn` and degrades to its zero value (`0` / `[]`) rather
than failing the whole response, so the entrance always renders. The only hard
errors are a nil DB handle (`CWB_KB_WIKI_010`) and failure to resolve the input
table (`CWB_KB_WIKI_011`).

The `kb.inputs` table name is resolved through the existing
`resolveInputTable(db)` helper (handles the `kb.input` / `kb.inputs` singular /
plural ambiguity).

### Response shape

```json
{
  "status": true,
  "counts": {
    "documents": 0,
    "content_segments": 0,
    "topics": 0,
    "semantic_projections": 0,
    "metrics": 0,
    "provisions": 0,
    "parts_components": 0,
    "scenes": 0,
    "entities": 0,
    "relations": 0
  },
  "recent_adds":      [{ "id": 1, "title": "…", "type": "pdf", "time": "RFC3339|null" }],
  "recent_edits":     [{ "id": 1, "title": "…", "type": "pdf", "time": "RFC3339|null" }],
  "recent_processed": [{ "record_id": 1|null, "title": "…", "processor": "chunking", "time": "RFC3339" }],
  "errors":           [{ "record_id": 1|null, "title": "…", "processor": "extract_metrics", "message": "…", "time": "RFC3339" }]
}
```

### Count sources

| Count field | Query | Table |
|---|---|---|
| `documents` | `COUNT(*)` | resolved `kb.inputs` |
| `content_segments` | `COUNT(*)` | `kb.chunks` |
| `topics` | `COUNT(*)` | `kb.topics` |
| `semantic_projections` | `COUNT(*)` | `kb.semantic_projections` |
| `metrics` | `COUNT(*)` | `kb.metrics` |
| `provisions` | `COUNT(*)` | `kb.provisions` |
| `parts_components` | `COUNT(*)` | `kb.products` |
| `scenes` | `COUNT(*)` | `kb.scene_objects` |
| `entities` | `COUNT(*)` | `kb.entities` |
| `relations` | `COUNT(*)` | `kb.relations` |

### Recent activity (each capped at `recentLimit = 8`)

- **recent_adds** — `kb.inputs` ordered by `create_time DESC`.
- **recent_edits** — `kb.inputs` ordered by `modify_time DESC`.
- **recent_processed** — `kb.doc_proc_logs` where `entry_type = 'doc_proc_summary'`
  and `errors` is null/empty, ordered by `create_time DESC`, LEFT JOINed to the
  input table on `record_id` for the title.
- **errors** — `kb.doc_proc_logs` where `errors` is non-empty, ordered by
  `create_time DESC`, LEFT JOINed to the input table for the title.

Titles use `COALESCE(NULLIF(TRIM(title),''), NULLIF(TRIM(file_name),''), '<fallback>')`.
`record_id` is nullable in the log tables, so it is scanned into
`sql.NullInt64` and emitted as `number | null`; the frontend only links rows
that carry a record id.

## Frontend: `/deep-wiki`

Svelte 5 (runes) + Tailwind 4 project. The page owns its own full-screen chrome
(the root layout only renders children). Data is fetched client-side in
`onMount` via `getWikiOverview()`; the page handles `loading` (skeletons),
`loadError` (retry banner), and empty states per feed.

### Panel A — corpus overview (the SemOS KB diagram)

Mirrors the system diagram: a central **SemOS KB monitor** (inline SVG: bezel,
screen with an on-screen cloud + database cylinder + linked nodes, "SemOS KB"
label, and stand) with **dashed connectors** radiating to nine numbered nodes.
Each node is an icon badge + numbered label + live count, and is a link into the
matching browse surface.

| # | Node | Count key(s) | Icon (lucide) | Link |
|---|---|---|---|---|
| 1 | Documents | `documents` | `files` | `/home3/knowledge?section=kb-input-details` |
| 2 | Content Segments | `content_segments` | `file-search` | `?section=kb-chunks` |
| 3 | Topics | `topics` | `presentation` | `?section=kb-topic-tree` |
| 4 | Semantic Projections | `semantic_projections` | `globe` | `?section=kb-semantic-projections` |
| 5 | Entities & Relations | `entities` + `relations` | `network` | `/knowledge-graph` |
| 6 | Metrics | `metrics` | `chart-bar` | `?section=kb-metrics` |
| 7 | Parts & Components | `parts_components` | `boxes` | `?section=kb-products` |
| 8 | Provisions | `provisions` | `scale` | `?section=kb-provision-tree` |
| 9 | Scenes | `scenes` | `clapperboard` | `?section=kb-scene-blocks` |

Node 5 is a single node (the graph), so its displayed value is the **sum** of
`entities` and `relations`. Node positions are computed with trigonometry
(`RING_RADIUS = 248`, nodes spaced `360° / 9` starting at the top).

Below the diagram: a keyword search (submits to
`/home3/knowledge?section=kb-search&q=<query>`) and a language selector wired to
paraglide `getLocale` / `setLocale` (`en`, `zh-cn`).

### Panel B — portal directory

A divided list of eight portals (Documents, Content Segments, Topics, Metrics,
Parts & Components, Scenes, Provisions, Graphs) linking into the same
`/home3/knowledge?section=…` surfaces. (Not yet updated to include a Semantic
Projections entry; Panel A is the source of truth for the nine-dimension model.)

### Panel C — recent activity

Four feeds rendered from the overview response: **Recent Adds**, **Recent
Edits**, **Recent Processed**, **Errors**. Each has skeleton loading, a teaching
empty state, relative timestamps (absolute on hover), and links to the source
document when a record id is present. The Errors feed is visually distinct
(danger accent) and shows the processor tag plus a clamped message.

### Responsive behaviour

`heroWidth` is bound to Panel A's `clientWidth`. When it drops below `680px`
the constellation collapses: the connectors are dropped and the nine nodes
reflow into a `repeat(3, minmax(0, 1fr))` grid under the monitor (`stat-grid`
uses `display: contents` in radial mode so the absolute positioning resolves
against `.hero-ring`, and becomes a real grid when compact). The search bar
wraps below `540px`. Panel C goes 4 → 2 → 1 columns. `overflow-x: clip` on the
root is a safety net against transient sub-pixel overflow.

## Design system (page-scoped)

Light "encyclopedic paper" theme. Tokens are declared on `.wiki` and not shared
globally:

- **Palette** — warm paper (`--paper`/`--surface`), ink text (`--ink`,
  `--ink-soft`, `--ink-faint`), one deep-teal accent (`--accent`,
  `--accent-strong`, `--accent-tint`), and a danger pair for the Errors feed.
  All OKLCH; no pure black/white.
- **Type** — serif (Georgia stack) for the wordmark, the "SemOS KB" label,
  counts, and section headings; system sans for everything else.
- **Motion** — 150–250 ms ease-out transitions; respects
  `prefers-reduced-motion`.

## Navigation entry

The page is reachable from `/home3/knowledge` via the existing **Wiki** menu
group, which has a first child **LLM Wiki** ("The Deep Wiki entrance to SemOS").
Because the Deep Wiki is a standalone route (not an inline section),
`selectSection('kb-llm-wiki')` calls `goto('/deep-wiki')` rather than swapping
an inline component.

## Verification

- `go build ./server/...` passes.
- `svelte-check` is clean for the changed files; prettier-formatted.
- Rendered and screenshotted across desktop, tablet, and mobile widths.
- The live endpoint sits behind auth and requires a rebuilt/restarted server to
  return real data; with no session the page shows the error banner, `—` count
  placeholders, and empty feeds (all correct degraded states).

## Notes / follow-ups

- Panel B does not yet list Semantic Projections, and still uses a combined
  "Graphs" portal. Align it with the Panel A nine-dimension model if a single
  consistent taxonomy across both panels is desired.
- `recent_processed` / `errors` depend on `kb.doc_proc_logs.record_id` being
  populated for titles and document links; rows without a record id render as
  plain (unlinked) text.
