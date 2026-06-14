# Bug: Parser Result Converter Misses Images

- DocID: `doc-2026061111`
- **Status:** Implemented
- **Date:** 2026-06-11
- **Deciders:** Chen Ding
- **Tags:** parser result converter, extract images, reference images

## Change Logs
- Created by Chen Ding on 2026/06/11

# Context
The parser result converter (refer to [1]) did not convert images to the line files.

Below is from the '.json' file:
```json
    {
      "page_number": 8,
      "items": [
        {
          "type": "image",
          "img_path": "images/1f20c6a54e8f2d389236e2118718db01c162d40a40952dbcd2902841c0706bc8.jpg",
          "image_caption": [
            "图1 室内家庭场景"
          ],
          "image_footnote": [],
          "bbox": [
            227,
            96,
            801,
            352
          ],
          "page_idx": 7
        },
        {
          "type": "text",
          "text": "业务用户可以在居室内通过定点存放的心电监测仪、血压计、血糖仪等设备测出个人采样数据，然后，收集、整理这些监测数据，将其通过有线网关或无线网关发送到医疗健康监测业务服务器。",
          "bbox": [
            79,
            395,
            931,
            429
          ],
          "page_idx": 7
        },
        ...
    }
```
But its line file does not have the corresponding line.

# Decision

## Implementation

### Modified Files

- `ChenWeb/server/api/file-converters/mineru.go` — Added `ImgPath`, `ImageCaption`, `ImageFootnote` fields to `mineruItem`; added `case "image":` handler in `extractMineruLineItems` that emits `image-caption`, `image`, and `image-footnote` lines (mirroring the table pattern).
- `ChenWeb/server/api/file-converters/service_test.go` — Added `TestConvertMineruFile_ImageWithCaptionAndFootnote` covering image with caption, image path, footnote, and a following paragraph.

### Key Design Decisions

- Image lines follow the same caption → body → footnote ordering as `table` (caption first, then the image path line, then footnotes).
- `img_path` is used as the line content for the `image` type, consistent with how `source` is used for opendata images.
- An image with no `img_path` emits only caption/footnote lines (if any), matching how an empty-body table behaves.

## Operational Behavior

For each mineru `image` item the converter now emits:
1. One `image-caption` line per non-empty entry in `image_caption`
2. One `image` line with `img_path` as content (if non-empty)
3. One `image-footnote` line per non-empty entry in `image_footnote`

## Consequences

### Positive

- Images are no longer silently dropped from the line file.
- Downstream processors that index or display images can now locate them via the `image` line.

### Trade-offs

- None. The change is purely additive.

## Verification

All existing tests pass. `TestConvertMineruFile_ImageWithCaptionAndFootnote` verifies the new behavior end-to-end.

## Documentation Impact

`KnowledgeStore/Capsules/coding-capsules/pdf-result-convert/+pdf-result-convert.md` should be updated to document `image`, `image-caption`, and `image-footnote` as new line types produced by the mineru converter (not done here — tracked separately).

# References
[1] KnowledgeStore/Capsules/coding-capsules/pdf-result-convert/+pdf-result-convert.md
