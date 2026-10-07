# Reusable PDF table references and companion geometry

The PDF viewer accepts `tableReferences`, an array of `{line, rows?, cells?, row_hash?}`.
Rows use canonical TableGrid IDs (`r1`, `h0`); cells use `r3:c4`, with one-based expanded
column numbers. Both SharedPdfViewer and PdfViewWindow support the same interface.
The viewer loads `/api/v1/kb/inputs/:id/table-geometry`, resolves references, paints
boxes in its overlay, and navigates to the first resolved page. Callers supply IDs,
not text or geometry. Existing renderHighlights callbacks remain supported.

PyMuPDF extracts physical table cell borders after PDF parsing and saves
`<pdf-stem>.pdf-table-geometry.json` beside the PDF. Each physical row has its page,
row band and cells (text and boxes). Rowspan cells retain their complete physical
cell box, while row bands are clipped to the individual logical row. Coordinates
are normalized to 0–1000 in the rotated, displayed page coordinate space.

The Go canonicalizer uses the existing ParseTableGrid to assign IDs and row hashes.
It matches physical rows conservatively by normalized column text, ignores header
repetition, and permits multiple physical fragments per logical row. It saves
`<line-stem>.table-geometry.json` beside the canonical line file. It never changes
line numbers. PDF and line SHA-256 hashes invalidate stale companions. Row hashes
allow the viewer to reject stale artifact citations. Missing/ambiguous matches are
omitted, never replaced with the first table box.

Parser geometry extraction failure is logged and does not fail successful text
parsing. Existing documents can extract the physical companion with the Python
module's CLI; the API can construct/refresh the canonical companion from it.
The converter builds the canonical companion before emitting its line-file event.
Record 416 will be backfilled and verified against its original PDF.

Metrics management passes source_table_rows into the viewer and retains its plain
line and drag-preview highlights. Its metric-specific PDF text matcher is removed.
The viewer owns table highlight styling, asynchronous record-switch protection,
reference changes, page navigation and repainting at zoom/resize.

Tests cover real generated PDF tables, spans, canonical row alignment, continuation
pages, cell selection, hash mismatches, missing geometry and asynchronous loading.
Validate with Python tests, affected Go package tests and frontend/i18n checks.

## Reference and coordinate contract

Pages are one-based. Boxes use displayed CropBox coordinates normalized to 0–1000.
Each box carries intrinsic PDF rotation; the viewer converts boxes back when
`respectPageRotation=false`. A rowspan cell keeps its whole physical cell box;
a row highlight uses only that row's band. Colspan aliases resolve to the same
physical box. Rows take precedence over their cells only after successful hash
and geometry validation. A reference with neither rows nor cells selects nothing.
Legacy references without row_hash use current canonical IDs; they cannot detect
whether an older artifact cited a different row. Hashes validate expanded row text,
not historical span ownership.

The original-page physical table is anchored by canonical page and box proximity.
Continuations must occur on adjacent pages before the next canonical table anchor,
with exactly one matching table per page. Headers may repeat; sufficiently long
column text may match a fragment of the canonical cell when a row splits across
pages. Competing canonical rows, competing continuation tables, and repeated data
fragments are omitted. Numeric signs, decimal points and percent signs remain
significant during matching. No fuzzy numeric or OCR correction is attempted.

## Companion files and cache

Physical schema: version, extractor (`pymupdf-tables-v1`), pdf_sha256, and tables
containing page, rotation, coords and rows (coords, cells with text and coords).
Canonical schema: version 1, algorithm (`canonical-table-geometry-v2`),
coordinate_space (`page-normalized-1000`), line_sha256, pdf_sha256,
physical_sha256, and tables containing line and rows (id, hash, boxes, cells).
Each cell has id (`r3:c4`) and boxes; boxes contain page, coords and rotation.
Both companions are atomically replaced. The canonical cache also includes the
physical companion digest, so regenerated extraction invalidates it even when
PDF and line bytes did not change. Update algorithm/extractor versions when the
mapping or coordinate contract changes.

The API resolves paths from kb.inputs, under the existing authenticated API group.
Responses use Cache-Control: no-store. The viewer fetches on input/reference/
highlightVersion changes, cancels obsolete fetches and clears obsolete boxes.
Increment highlightVersion to refresh an open selection after regeneration.
Navigation happens when a selection resolves; zoom/resize preserves the scroll
position instead of returning to the selected row.

## Caller examples

```svelte
<PdfViewWindow
  inputId={recordId}
  {fileUrl}
  tableReferences={[{ line: 121, rows: ['r3'], row_hash: { r3: '5364693c56e5' } }]}
/>

<SharedPdfViewer
  inputId={recordId}
  {fileUrl}
  tableReferences={[{ line: 121, cells: ['r3:c4'] }]}
/>
```

Custom renderHighlights callbacks still draw other highlights. Exclude the table
lines cited by tableReferences from whole-line boxes to avoid overlapping the
precise table highlight. Metrics management, metric review and the ontology source
pane follow this rule.

## Existing documents and verification

New parses extract physical companions automatically. For existing PDFs:

```sh
cd ChenWeb/python/pdf-parser
.venv/bin/python table_geometry.py /path/to/document.pdf
```

The next geometry API request builds the canonical companion without re-numbering
or re-extracting metrics. Record 416 was backfilled: line 121, r3, hash
5364693c56e5 maps to page 7; r3:c4 maps to its technical-requirements cell.
Documents without detectable table geometry remain unhighlighted until suitable
geometry is supplied; there is no text-box or first-fragment fallback.

Python tests cover real PDF borders, rowspan/colspan, CropBox and rotation, and
parser success when geometry fails. Go tests cover continuation and split rows,
ambiguous tables, operators/decimals, invalidation and conversion-before-publish.
Frontend tests cover reference/hash resolution, cells, precedence and rotation.
The viewer's cancellation and navigation paths were reviewed; a live browser smoke
test was unavailable because the Chrome CDP connection timed out.
