# Reference graph — compare source and target PDFs

**Date:** 2026-10-14 \
**Scope:** Document selection and PDF viewing on `/home3/reference-graph`. \
**Code root:** `ChenWeb/web/src/routes/home3/reference-graph/`

## Summary

The reference graph page has a record browser on the left, the graph in the center, and two PDF viewers stacked on the right. The upper viewer displays the selected source document. Clicking a reference node navigates the source PDF to its citation and highlights it. If the reference has a resolved target passage, the lower viewer also navigates and highlights that passage, so readers can compare both documents while exploring the graph. The former metrics and references list panel has been removed; those records remain visible as graph nodes.

## Details

- `reference-pdf-viewer.svelte` loads each document’s raw lines, maps stored line spans to actual PDF pages, and paints normalized-coordinate highlights. The existing shared viewer scrolls the first highlight into view. Selection changes, including repeated clicks on the same reference, navigate again without reloading a PDF whose document ID has not changed. Pending raw-line requests are ignored when their viewer is replaced.
- Both viewers reuse `pdf-view-window.svelte`, with independent page and zoom controls, no metadata sidebar, and no line-selection dialog.
- The source PDF uses `/api/v1/kb/inputs/{record.id}/file`. The target PDF uses `/api/v1/kb/inputs/{reference.target_input_id}/file`.
- Source locations come from `source_line_spans` and `source_table_rows`. Table rows use the shared viewer’s table geometry and row hash validation.
- `GET /api/v1/kb/references` additionally returns `target_locations`: an array of `{source_line_spans, source_table_rows}` for target artifacts in `kb.reference_artifact_links` with status `resolved` or `confirmed`. The query supports `kb.metrics` and `kb.metrics_dropped`, checks the linked document ID and artifact identifier, and excludes candidates, rejected links, stale links, and missing target rows.
- Click selection is registered on the ECharts instance, covering force graph and all four tree orientations. Only reference leaf nodes select targets; metrics, branch nodes, the source node, and edges do not change the target selection.
- A reference without `target_input_id` clears the previous target viewer and displays a message. Changing the source record also clears target selection immediately. View mode changes preserve target selection.
- Each PDF is recreated when its document ID changes to reset page navigation and prevent showing pages from the previous document.
- The outer dividers resize the record and PDF panels with pointer dragging or arrow keys. Widths are stored in `reference-graph:left-width` and `reference-graph:right-width`; the obsolete middle-panel width is ignored. The graph has a zero-width floor, and the PDF panel may expand up to 1220px (400px more than its original 820px maximum).
- English and Chinese labels are in `web/messages/en.json` and `web/messages/zh-cn.json`. The page root explicitly permits text selection.
- The reference list endpoint has an additive response field; no database schema or shared library change is needed.

## Known limitations

- A target needs a resolved `target_input_id` and a PDF accessible through the existing file endpoint. Unresolved references cannot display a target PDF; file failures use the viewer’s existing error state.
- A document-level citation without passage locations highlights a raw line matching the complete target document title (preferring an exact title over a line containing the title), ignoring whitespace and punctuation. If the title cannot be located, it opens at page 1 without inventing a passage highlight. Explicit passage or table locations always take priority. Raw-line load failures leave the PDF available and display a localized notice that highlighting is unavailable.
- Narrow screens allow horizontal scrolling to retain usable panel widths.
