# Metrics Page Feature Implementation Analysis

## Scope
This document analyzes how **File1** (`metric-mgmt-view.svelte`) currently implements the feature described in **File2** (`metric-mgmt-page.md`):

- User clicks a metric entry in the **Metrics** list (left panel)
- Right panel PDF moves to the corresponding page(s)
- Referenced lines are highlighted using coordinates derived from `page_number + line_number`

---

## 1) Design Intent (from File2)
The design doc specifies this flow:

1. Retrieve metrics from `kb.metrics` using `input_record_id`
2. For selected metric, read `source_line_spans` (page/line references)
3. Retrieve raw-line data (`<filename_root>.txt`) associated with the input record
4. Resolve each `(page_number, line_number)` to line coordinates
5. Move document view to target page and highlight the referenced content

The raw-line format in the design doc is:

```text
<line_number> <page_number> <line_type> <content> <coordinate>
```

where `<coordinate>` is `[x1,y1,x2,y2]`.

---

## 2) High-Level Architecture in File1
`metric-mgmt-view.svelte` implements this in three layers:

1. **Data acquisition layer**
- `doRetrieve()` loads:
  - metrics (`listKbMetrics(id)`)
  - input record (`getKbInput(id)`)
  - raw lines (`getRawLines(id)`) via `loadRawLines()`

2. **Selection + mapping layer**
- `selectMetric(m)` handles card click
- `normalizeMetricSpans()` normalizes span shape variants into `{ page_number, line_number }`
- `rawLineByKey` maps `${page}:${line}` -> `RawLine`
- `selectedLinesByPage` groups resolved lines (with coords) by page

3. **Rendering + interaction layer**
- For PDF type: pdf.js-based multi-page canvas rendering (`renderPdfPages()`)
- For each page: an overlay layer (`pdf-overlay-<pageNo>`) draws highlight rectangles
- Page jump uses `scrollPdfToPage(pageNo)` and page controls (`goToPage`)

---

## 3) Detailed Flow: Click Metric -> Jump + Highlight

### A. Click event entrypoint
Left list item click calls:

- `onclick={() => selectMetric(m)}`

`selectMetric(m)` performs:

1. `selectedMetricId = m.id`
2. `first = normalizeMetricSpans(m)[0]`
3. `docPage = first.page_number`
4. If in document mode and PDF: `scrollPdfToPage(docPage, 'smooth')`

This is the **jump trigger**.

### B. Span normalization
`normalizeMetricSpans(m)` accepts multiple source shapes:

- Object forms:
  - `{ page_number, line_number }`
  - `{ page, line }`
  - `{ page_no, line_no }`, etc.
- String forms:
  - e.g. `"4:29"`, `"4-29"`

This normalization reduces schema fragility from backend payload variance.

### C. Line-to-coordinate resolution
After `getRawLines(...)`, each raw line includes `coords: number[]`.

Resolution path:

1. `rawLineByKey`: `Map<"page:line", RawLine>`
2. `selectedLinesByPage`: for current metric spans, lookup each key in `rawLineByKey`
3. Keep only lines with valid coordinate tuples (`coords.length >= 4`)
4. Group resolved lines by page number

### D. Coordinate highlight rendering
`drawPdfHighlights()` iterates rendered pages:

1. Find page overlay element (`pdf-overlay-<pageNo>`)
2. Load page viewport (`pdfViewportByPage.get(pageNo)`)
3. For each selected line on page:
   - Convert PDF coords -> viewport coords via `viewport.convertToViewportRectangle(...)`
   - Compute normalized box:
     - `left = min(x1, x2)`
     - `top = min(y1, y2)`
     - `width = abs(x2 - x1)`
     - `height = abs(y2 - y1)`
   - Append `<div class="pdf-highlight">` to overlay

This is the core mechanism that converts raw-line coordinates into visual highlights.

---

## 4) PDF Rendering Model Used
For PDF inputs, File1 uses pdf.js directly:

1. `ensurePdfLib()` lazy-loads `pdfjs-dist`
2. `ensurePdfDoc()` opens `/api/v1/kb/inputs/${id}/file`
3. `pdfRenderedPages = [1..numPages]`
4. `renderPdfPages()` renders every page to canvas:
   - computes scale from available width and `pdfZoom`
   - gets per-page viewport
   - stores viewport in `pdfViewportByPage` for coordinate conversion

This multi-page model supports:

- cross-page metrics
- adjacent-page reading
- page-by-page overlays

---

## 5) Reactive Triggers That Keep Feature Synced
Svelte effects in File1 coordinate updates:

1. **Initial/zoom/page-set rendering trigger**
- when in document mode + PDF + stage exists
- ensures doc loaded then calls `renderPdfPages()`

2. **Jump trigger**
- watches `docPage`, then scrolls to `pdf-page-<docPage>`

3. **Highlight refresh trigger**
- when selected lines / viewports are available, runs `drawPdfHighlights()`

4. **Resize trigger**
- `ResizeObserver` on PDF stage
- rerenders only when width changes (guarded by `pdfLastRenderWidth`)

---

## 6) How Implementation Matches File2 Requirements

### Implemented
- Retrieve metrics by input record id
- Retrieve raw-line data and use coordinates
- Click metric entry to set target page
- Highlight line regions via coordinate overlays
- Multi-page PDF rendering in the right panel

### Implementation choices beyond File2
- Supports non-PDF documents with iframe fallback
- Supports `Source Lines` tab rendering parsed text lines
- Adds robust span-shape normalization for varied backend payloads
- Adds zoom + page navigation controls in PDF mode

---

## 7) Key Internal Data Structures

- `metrics: KbMetricRecord[]`
- `selectedMetricId: number | null`
- `rawLines: RawLine[]`
- `rawLineByKey: Map<string, RawLine>` (`"page:line"`)
- `selectedLinesByPage: Map<number, RawLine[]>`
- `pdfViewportByPage: Map<number, PdfPageViewport>`

These structures are the backbone of span -> coordinate -> highlight transformation.

---

## 8) End-to-End Sequence Summary

1. User enters Record ID and clicks **Retrieve**
2. UI loads metrics + input + raw lines
3. User clicks a metric card
4. Card click sets selected metric and target page (`docPage`)
5. PDF panel scrolls to that page
6. Selected spans resolve to raw lines
7. Raw line coordinates convert to viewport rectangles
8. Overlay boxes are drawn on referenced lines

This is the implemented realization of the feature described in `metric-mgmt-page.md`.
