# Bug: PDF Parser Handles Formula Incorrect

- DocID: `doc-2026061113`
- **Status:** Implemented
- **Date:** 2026-06-11
- **Deciders:** Chen Ding
- **Tags:** pdf parser, formula, parser result converter, formula image, reference images

## Change Logs
- Created by Chen Ding on 2026/06/11
- Updated implementation notes and verification on 2026/06/11

# Context
The PDF parser (`mineru`) generated image files for formulas, but the aggregated
parser JSON did not include corresponding `img_path` references on `equation`
items. As a result, the downstream line-file converter emitted only the LaTeX
equation text and did not emit a line for the formula image.

Example: record `416` recognized the formula on page 11 (zero-based
`page_idx=10`) and generated formula/image assets under:

```text
/Users/cding/Apps/SemOS/Artifacts/0/416/images/
```

The JSON around the formula contained an `equation` block with LaTeX and `bbox`,
but no image-path entry. Tables and pictures worked because their MinerU
`content_list.json` entries already carried `img_path`.

# Decision
Treat formula crops as first-class parser artifacts, parallel to picture and
table crops.

The parser should annotate `equation` items with `img_path` when MinerU exposes
the crop path in intermediate output. The converter should then emit a separate
`equation-image` line in addition to the textual `equation` line.

## Implementation
Root cause:

- MinerU's canonical `*_content_list.json` includes equation LaTeX but, for this
  case, does not include the formula crop path.
- MinerU's `*_middle.json` does include the missing association on the equation
  span as `image_path`.
- `ChenWeb/python/pdf-parser/parser_mineru.py` copied all generated images to the
  artifact-level `images/` directory, but did not propagate equation crop paths
  into the aggregated parser JSON.
- `ChenWeb/server/api/file-converters/mineru.go` only emitted equation text for
  `equation` blocks.

Fix:

- Read MinerU `*_middle.json` alongside `*_content_list.json`.
- Extract equation spans with `image_path`.
- Match them back to `content_list` equation items by normalized equation text.
- Add `img_path: "images/<file>"` to matching equation items unless they already
  have an image path.
- Emit a downstream `equation-image` line when an equation item has `img_path`.

For record `416`, the resolved formula crop is:

```text
images/97c19fc8593421acfd51faaa584b281db7158ff1e911602fb44dce1edf2532d8.jpg
```

Note: `images/9700a3bff965ded104a25c0390b823a0ba7cf9add1948605b82f42e992c654cf.jpg`
exists in the artifact folder, but MinerU `middle.json` maps the formula span to
`97c19f...jpg`; `9700a3...jpg` is a page-sized crop, not the narrow equation
crop.

### Modified Files
- `ChenWeb/python/pdf-parser/parser_mineru.py`
- `ChenWeb/python/pdf-parser/tests/test_parser_mineru.py`
- `ChenWeb/server/api/file-converters/mineru.go`
- `ChenWeb/server/api/file-converters/service_test.go`
- Existing artifact repaired in place:
  `/Users/cding/Apps/SemOS/Artifacts/0/416/std_1503937_mineru.json`

### Key Design Decisions
- Use MinerU `middle.json` as the source of truth for formula crop paths because
  `content_list.json` can omit equation `img_path`.
- Match equations by normalized LaTeX content rather than filename order.
- Preserve existing `img_path` values if MinerU or a future parser already
  provides them.
- Emit `equation-image` as a separate line type so downstream consumers can
  index or reference the rendered formula image without losing the LaTeX
  equation text.

## Operational Behavior
- Future MinerU parses will include `img_path` on equation items when
  `middle.json` contains a matching equation span with `image_path`.
- Converted line files will contain both:
  - `equation` line with LaTeX content
  - `equation-image` line with the formula crop path
- Existing records need reprocessing or one-time repair to gain the new JSON
  field. Record `416` was repaired manually as part of this bug fix.

## Consequences

### Positive
- Formula images are now available in parser JSON and line files.
- Behavior is consistent with picture and table image handling.
- LaTeX text remains available; the image is additive, not a replacement.
- Record `416` now has the missing formula image reference.

### Trade-offs
- The parser now depends on MinerU `middle.json` for formula image association.
- Matching by normalized equation text is robust for common cases but can be
  ambiguous if the same equation appears multiple times. The implementation
  consumes matches in order to handle repeated equations deterministically.

## Verification
- Added Python parser tests for equation-image annotation from MinerU
  `middle.json`.
- Added Go converter test for emitting `equation-image` from an equation
  `img_path`.
- Ran:

```bash
cd /Users/cding/Workspace/ChenWeb
go test ./server/api/file-converters -count=1

cd /Users/cding/Workspace/ChenWeb/python/pdf-parser
./.venv/bin/pytest tests -q
```

Results:

- Go converter tests passed.
- Python parser tests passed: `74 passed`.

Record `416` was checked after repair:

```json
{
  "type": "equation",
  "text_format": "latex",
  "img_path": "images/97c19fc8593421acfd51faaa584b281db7158ff1e911602fb44dce1edf2532d8.jpg",
  "bbox": [159, 487, 897, 521],
  "page_idx": 10
}
```

## Documentation Impact
- Knowledge changed: MinerU formula crop paths may be present in `middle.json`
  even when absent from `content_list.json`.
- Docs/specs/ADRs/tests affected: this bug note and the parser/converter tests.
- Docs updated: this document.
- Docs now stale: none identified.
- Intentionally left undocumented: no full parser schema update was made; this
  note records the behavior because the change is specific to MinerU formula
  image propagation.

# References
[1] KnowledgeStore/Capsules/coding-capsules/pdf-result-convert/+pdf-result-convert.md
