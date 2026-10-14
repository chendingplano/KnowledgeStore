# Reference graph — compare source and target PDFs

**Date:** 2026-10-14 \
**Scope:** Document selection and PDF viewing on `/home3/reference-graph`. \
**Code root:** `ChenWeb/web/src/routes/home3/reference-graph/`

## Summary

The reference graph page has a record browser on the left, the graph in the center, and two PDF viewers stacked on the right. The upper viewer displays the selected source document. Clicking a reference node opens its linked target document in the lower viewer, so readers can compare both documents while exploring the graph. The former metrics and references list panel has been removed; those records remain visible as graph nodes.

## Details

- Both viewers reuse `pdf-view-window.svelte`, with independent page and zoom controls, no metadata sidebar, and no line-selection dialog.
- The source PDF uses `/api/v1/kb/inputs/{record.id}/file`. The target PDF uses `/api/v1/kb/inputs/{reference.target_input_id}/file`.
- Click selection is registered on the ECharts instance, covering force graph and all four tree orientations. Only reference leaf nodes select targets; metrics, branch nodes, the source node, and edges do not change the target selection.
- A reference without `target_input_id` clears the previous target viewer and displays a message. Changing the source record also clears target selection immediately. View mode changes preserve target selection.
- Each PDF is recreated when its document ID changes to reset page navigation and prevent showing pages from the previous document.
- The outer dividers resize the record and PDF panels with pointer dragging or arrow keys. Widths are stored in `reference-graph:left-width` and `reference-graph:right-width`; the obsolete middle-panel width is ignored.
- English and Chinese labels are in `web/messages/en.json` and `web/messages/zh-cn.json`. The page root explicitly permits text selection.
- No database schema, backend endpoint, or shared library changes are required.

## Known limitations

- A target needs a resolved `target_input_id` and a PDF accessible through the existing file endpoint. Unresolved references cannot display a target PDF; file failures use the viewer’s existing error state.
- Narrow screens allow horizontal scrolling to retain usable panel widths.
