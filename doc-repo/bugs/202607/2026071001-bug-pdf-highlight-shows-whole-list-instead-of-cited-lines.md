# Bug: PDF grounding highlight shows an entire list block instead of the cited line(s)

Date: 2026-07-10\
Status: fixed-verified\
System: `ChenWeb` Knowledge System PDF viewer (`/home3/knowledge` and sibling
`home3` views: metrics, provisions, inventory items, object manager, chunk
management, scene blocks, artifact categories)\
Component: `web/src/lib/components/home3` (PDF highlight overlay rendering),
`server/api/file-converters` (MinerU→line-file converter),
`python/pdf-parser` (MinerU parser backend)

## Summary

A metric's "Grounding" panel cites specific source line(s) in the PDF (e.g.
metric id `29826`, `source_line_spans = ["114", "117"]`), but the PDF viewer
highlighted far more than those lines — entire multi-item lists, sometimes
spanning unrelated section headings between the two cited lines. The fix
required correcting two independent bugs whose symptoms overlapped (both
manifested as "too much text highlighted"), plus a data backfill for already
processed documents, plus one follow-on cosmetic fix discovered while
verifying the backfilled data.

## Symptom

Record 244 (`stdGk_3016049.pdf`), metric id `29826` ("手动测量血压次数"),
cites line 114 (`6.2.1.4 手动测量血压1~2次。`) and line 117
(`6.2.2.1 卸下时建议手动测量1-2次...`) as grounding. Instead of highlighting
only those two lines, the PDF viewer highlighted:

- One box covering all of `6.2.1.1`–`6.2.1.5` (5 list items, only one of
  which — `6.2.1.4` — was actually cited).
- One box covering all of `6.2.2.1`–`6.2.2.2` (both items, only one of
  which — `6.2.2.1` — was actually cited).

The same pattern applied broadly across mineru-parsed documents, not just
this one metric.

## Root Cause

Two independent bugs, both contributing to the same visible symptom.

### Cause 1 — frontend: highlight boxes bridged non-adjacent lines

In `renderMetricHighlights` (and 5 duplicate copies of the same PDF-highlight
function across other `home3` views), each highlighted line's box was
stretched down to the top of the *next* highlighted line's box,
unconditionally:

```js
const bottom = nextRect ? nextRect.top : rect.rawBottom;
```

For metric `29826` (grounding lines 114 and 117 — not adjacent), this
stretched line 114's box all the way down to line 117's top, visually
swallowing every list item in between, regardless of whether the two lines
were actually adjacent in the document.

### Cause 2 — data: MinerU's list blocks have no per-item bbox

MinerU's `content_list.json` (the parsed-PDF JSON stored as
`kb.inputs.result_filename`) represents a list as one shared `bbox` plus a
`list_items` string array — it does not give each list item its own
bounding box. `ChenWeb/server/api/file-converters/mineru.go`
(`extractMineruLineItems`, `"list"` case) explodes each `list_items[i]` into
its own row in the canonical line file (`<record>_mineru.txt`), but reused
that single shared bbox for every exploded row. So even with Cause 1 fixed,
highlighting "line 114" would still highlight the bbox of the entire
5-item list, because that literally is what was stored as line 114's
coordinate.

MinerU's own `*_middle.json` sibling output (already read by
`parser_mineru.py` for equation-image annotation) retains a bbox per
physical text line, verified against record 244 page 6: all 6 list blocks
in `content_list.json` line up 1:1, in order, with the 6 list blocks in
`_middle.json`, both by item count and by first-item text — so this data
existed upstream and was simply discarded.

### Cause 2b — coordinate-scale mismatch (found while fixing Cause 2)

`content_list.json` and `_middle.json` use *different coordinate scales* for
the same page (e.g. for one list block, `content_list.json` gives
`bbox=[112,741,905,854]` while `_middle.json` gives `bbox=[67,624,539,719]`
for the same visual region). The first fix attempt copied `_middle.json`'s
raw per-line coordinates directly into the field the frontend expects to be
in `content_list.json`'s coordinate space, producing boxes that were
correctly *sized* but visibly *misplaced*.

### Cause 2c — line-number instability in the initial backfill design

An initial backfill approach matched "duplicate bbox" runs in the live
`.txt` file, or matched by `line_number` against the pristine `.origin`
backup. Both were unreliable: `structure_analyzer`'s static-analysis pass
can merge or remove lines upstream (image-artifact removal, watermark
removal, paragraph merging — see
`KnowledgeStore/Capsules/coding-capsules/doc-processor/structure-analyzer-static-spec.md`
§1.6.1, §1.6.2, §1.6.7), which permanently shifts every later `line_number`,
so `.origin` and `.txt` are not guaranteed to agree on which `line_number`
corresponds to which physical line. Content, however, is never altered by
those stages, so matching lists into `.txt` by their text content (not line
number, not bbox equality) is the robust approach.

### Cause 3 — cosmetic: fixed top-padding bled into the previous line

`HIGHLIGHT_EXPAND_TOP_PX = 10` (present in all 8 highlight-rendering
functions) pushes a highlight box's top edge upward by a fixed number of
already-zoomed screen pixels, as visual padding. This was invisible when
boxes were the old, oversized merged ones, but once per-line boxes became
tight and accurate (per the Cause 2/2b fix), adjacent list items can sit
flush against each other with zero gap (confirmed: one list's item 3 bbox
ends at `y=821.88` and item 4's bbox begins at exactly `y=821.88`), so a
10px expansion visibly bled into the line above.

## Fix

**Cause 1** — only merge a highlight box into the next one when the two
lines are truly contiguous (`nextRect.lineNumber === rect.lineNumber + 1`),
matching the pattern `chunk-mgmt-view.svelte` already used correctly:

- `web/src/lib/components/home3/metric-mgmt-view.svelte`
- `web/src/lib/components/home3/inventory-items-view.svelte`
- `web/src/lib/components/home3/object-manager-view.svelte`
- `web/src/lib/components/home3/provision-mgmt-view.svelte`
- `web/src/lib/components/home3/kb-extraction-view.svelte`
- `web/src/lib/components/home3/artifact-category-panel.svelte`

**Cause 2 / 2b** — `python/pdf-parser/parser_mineru.py`: new
`annotate_list_item_bboxes(content_list, middle_json)`, called alongside the
existing `annotate_equation_image_paths` at parse time. Pairs each
`content_list.json` "list" item with the corresponding `_middle.json` "list"
para_block per page (ordinal position + first-item-text verification, so a
mismatch is skipped rather than mis-assigned), and — critically — derives a
per-axis affine transform (scale + offset) from the two coordinate systems
using each list's own bbox in both spaces, applying it to every sub-item's
unioned line bbox before storing it as `list_item_bboxes` on the
consolidated JSON.

`server/api/file-converters/mineru.go`: the `"list"` case in
`extractMineruLineItems` now uses `item.ListItemBBoxes[i]` per exploded item
when present and length-matched to `list_items`, falling back to the shared
bbox otherwise (old/non-list-typed data).

**Cause 2c / backfill** — two one-off tools, designed to be idempotent
(safe to re-run):

- `python/pdf-parser/backfill_list_item_bboxes.py`: re-runs
  `annotate_list_item_bboxes` against each already-parsed record's stored
  consolidated JSON, so a record whose doc-processing pipeline hasn't
  converted it to `.txt` yet will get correct boxes automatically once it
  does.
- `server/cmd/backfill-mineru-list-bboxes/main.go`: reads each record's
  already-annotated consolidated JSON and matches each list's
  `list_items` content sequence against the current `.txt`
  (content-based matching, not line-number or bbox-duplication based, per
  Cause 2c), patching only the bbox field of matched lines in place. Leaves
  line numbers, types, content, `.origin`, and `.manual` files untouched.

**Cause 3** — reduced `HIGHLIGHT_EXPAND_TOP_PX` / `HIGHLIGHT_EXPAND_TOP` from
`10` to `2` in all 8 highlight-rendering functions (the 6 above, plus
`chunk-mgmt-view.svelte` and `pdf-view-window.svelte`, which didn't need the
Cause 1 fix but share the same padding constant).

## Backfill Results

Run against all 193 `kb.inputs` records with `parser_name = 'mineru'`:

- Python JSON-level backfill: 190/193 records annotated, 33,979 list items
  given correct per-item `list_item_bboxes`.
- Go `.txt`-level backfill: 131/193 records patched, 21,748 lines corrected
  in place. The remaining 48 skipped records have no `.txt` yet (their
  doc-processing pipeline hasn't converted them) — the JSON backfill above
  means they'll get correct boxes the first time that pipeline runs, no
  further action needed for them.
- A small number of list items in math-heavy documents were conservatively
  left unpatched: `content_list.json` wraps inline LaTeX in `$...$` while
  `_middle.json`'s raw spans don't, which breaks the text-verification
  safety check. Logged per-line, not silently wrong.

## Verification

- `cd server && go build ./... && go vet ./...` — clean.
- `go test ./api/file-converters/...` — includes new tests
  `TestConvertMineruFile_ListUsesPerItemBBoxesWhenPresent` and
  `TestConvertMineruFile_ListFallsBackToSharedBBoxWhenCountMismatch`.
- `cd python/pdf-parser && ./.venv/bin/python -m pytest tests/` — 85 passed,
  including new `annotate_list_item_bboxes` tests that specifically exercise
  the affine coordinate transform (content-space and middle-space
  deliberately given different scale/offset per test, to catch a regression
  of Cause 2b).
- `cd web && npm run check` — same pre-existing baseline (41 errors / 52
  warnings) as before this change; no new errors in any touched file.
- Manually verified against real production data: record 244 / metric
  `29826`, before and after each fix stage, confirmed line 114's bbox
  (`[115.36, 821.88, 374.09, 836.16]`) and line 117's bbox
  (`[115.36, 885, 753.68, 900.5]`) both fall correctly within their
  respective original list's bounds and are visually tight/distinct in the
  browser after rebuild.

## Change Record

Implementation changes committed in `ChenWeb` at:

- `0fef07c` `(1) report bugs, (2) metric viewer improvements` — Cause 1, 2,
  2b, 2c, 3 fixes and both backfill tools.

Two new files added, kept for future re-runs against newly discovered
mineru-parsed records if needed:

- `python/pdf-parser/backfill_list_item_bboxes.py`
- `server/cmd/backfill-mineru-list-bboxes/main.go`

## Documentation Impact

What knowledge changed:
- `content_list.json` (MinerU's own output) does not carry per-list-item
  bboxes; `_middle.json` does, but in a different coordinate space that
  must be rescaled via each list's own bbox before use.
- Line numbers in the canonical line file are not guaranteed stable
  relative to `.origin` once `structure_analyzer` has run — merges/removals
  shift everything downstream. Any future tooling that needs to correlate
  `.origin` and `.txt` must match on content, not `line_number`.

Which docs/specs/tests are affected:
- `KnowledgeStore/Capsules/coding-capsules/doc-processor/structure-analyzer-static-spec.md`
  already documents the line-merge/removal behavior (§1.6.1, §1.6.2, §1.6.7)
  that caused Cause 2c; no spec change needed, but this bug record is the
  first place that calls out its downstream implication for tooling that
  reads `.origin` and `.txt` together.
- New regression tests: `server/api/file-converters/service_test.go`,
  `python/pdf-parser/tests/test_parser_mineru.py`.

Which docs were updated:
- This bug record.

Which docs may still be stale:
- None identified; no other doc described the old (broken) list-bbox
  behavior as correct.

What was intentionally left undocumented:
- No ADR was added — this was root-caused and fixed as a bug, not an
  architectural change. The coordinate-transform approach and the
  content-matching backfill approach are documented in code comments at
  their definition sites (`parser_mineru.py::annotate_list_item_bboxes`,
  `server/cmd/backfill-mineru-list-bboxes/main.go` package doc comment)
  rather than duplicated here.
