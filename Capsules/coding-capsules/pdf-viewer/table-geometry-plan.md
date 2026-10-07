# PDF Table Geometry Implementation Plan

**Goal:** reusable row/cell highlighting backed by companion geometry, including 416 line 121 r3 on page 7.
**Architecture:** Python extracts physical tables; Go maps them through canonical TableGrid IDs; shared viewer retrieves and paints referenced boxes.
**Tech stack:** existing PyMuPDF, Go/Echo, TypeScript/Svelte, pdf.js.

- [x] Add Python physical table extraction and tests (generated PDFs, rowspan bands, atomic companion output); integrate after parser result writing.
- [x] Add Go documentgeometry types, canonical mapping and hash-validated sidecar storage with tests; invoke from file converters before publishing.
- [x] Add authenticated geometry retrieval route and handler tests, including missing artifacts and invalid IDs.
- [x] Add generic frontend geometry reference resolver and tests; wire tableReferences into both reusable viewers with fetch cancellation, row hash checks, repaint and navigation.
- [x] Migrate metrics management from its text matcher to tableReferences; remove obsolete matcher and text callback plumbing.
- [x] Backfill record 416, verify r3 page 7 and c4 physical boxes, run Python/Go/frontend checks, update design and implementation docs, commit through jj keeping unrelated work separate.

Validation: 108 Python tests, 29 frontend tests, Go documentgeometry/file-converters/kbhandler tests, both Go service builds, and Svelte/i18n checks passed (two existing CSS warnings). Record 416 was backfilled and its line 121 r3 hash verified on page 7. Live browser verification was unavailable because the browser connection timed out; running services were not restarted.
