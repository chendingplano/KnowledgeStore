# Bug: PDF Parser Handle Images

- DocID: `doc-2026061110`
- **Status:** Implemented
- **Date:** 2026-06-11
- **Deciders:** Chen Ding
- **Tags:** pdf parser, mineru, extract images

## Change Logs
- Created by Chen Ding on 2026/06/11
- Implemented by Claude on 2026/06/11

# Context
The `mineru` PDF parser (refer to [1] and [2]) needs to detect and extract images and save them to files.

# Decision

## Implementation

### Modified Files

- `ChenWeb/python/pdf-parser/parser_mineru.py` — after locating `*_content_list.json`, copy MinerU's `images/` subdirectory from the nested output path to `output_dir/images/` so `img_path` values in content items resolve correctly relative to the aggregated result JSON.

### New File

None.

### Key Design Decisions

MinerU writes images to `<output_dir>/<pdf_stem>/<backend>_auto/images/`, but the aggregated result JSON is written by `pdf_parser.py` to `<output_dir>/<pdf_stem>_mineru.json`. Content list items reference images as `"images/filename.png"` (relative to the content_list dir). Without copying, downstream consumers reading the result JSON cannot resolve those relative paths.

The fix copies all files from the MinerU-produced `images/` dir to `output_dir/images/` using `shutil.copy2` (preserving metadata). The `img_path` values in content items require no rewriting — they are already `"images/filename.png"` which is correct relative to `output_dir`.

The `parse()` return dict gains two new optional keys: `images_dir` (absolute path to the copied images dir, empty string if no images) and `image_count`.

### Environment Variables

None added.

## Operational Behavior

After a successful MinerU parse, `<record_dir>/images/` will contain all page images extracted by MinerU. If the PDF contains no images MinerU emits no `images/` directory, the copy step is skipped silently, and `image_count` is 0.

## Consequences

### Positive

- Downstream document processors reading `<pdf_stem>_mineru.json` can now resolve `img_path` values without knowing MinerU's internal output layout.
- `image_count` in the result dict gives callers a quick signal that images were extracted.

### Trade-offs

- Duplicate disk usage: images exist in both MinerU's nested output dir and `record_dir/images/`. MinerU's nested dir (`<record_dir>/<pdf_stem>/<backend>_auto/`) can be cleaned up separately if needed.

## Verification

Run a MinerU parse against a PDF known to contain images and verify:
1. `<record_dir>/images/` exists and contains the expected image files.
2. The `image_count` field in `<pdf_stem>_mineru.json` is non-zero.
3. Service log shows `mineru: copied N image(s) to <path>`.

## Documentation Impact

- `KnowledgeStore/Capsules/coding-capsules/pdf-parser/+pdf-parser.md` — Section 4.2 (mineru backend) should note that images are copied to `<record_dir>/images/` and that the result dict now includes `images_dir` and `image_count` keys.

# References
[1] ThirdParty/mineru/USER_MANUAL.md

[2] KnowledgeStore/Capsules/coding-capsules/pdf-parser/+pdf-parser.md