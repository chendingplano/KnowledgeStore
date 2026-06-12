# ADR: Detect TOC Lines

- DocID: `doc-2026061108`
- **Status:** Accepted
- **Date:** 2026-06-11
- **Deciders:** Chen Ding
- **Tags:** TOC Lines, static_analyzer, doc processor

## Change Logs
- Created by Chen Ding on 2026/06/11
- Implemented by Claude Code on 2026/06/11

# Context
`static_analyzer` (refer to [1]) is a doc processor (refer to [2]). One of the functions
is to detect "Table of Contents". If detected, it sets the line types of the "Table of 
Contents" lines to 'toc' so that subsequent doc processors avoid extracting artifacts
from "Table of Contents".

This is currently implemented in `func applyStaticTOCLabels(...)` in [3]:
```go
func applyStaticTOCLabels(lines []staticInputLine, corrected map[int]string, logger ApiTypes.JimoLogger) int {
	// Find the TOC title line.
	start := -1
	tocPage := 0
	for i, line := range lines {
		n := normalizeStaticTitle(line.Content)
		if n == "tableofcontent" || n == "tableofcontents" || n == "目录" || n == "目次" {
			start = i
			tocPage = line.PageNo
			break
		}
	}
	if start < 0 {
		return -1
	}

	// Find the first actual TOC entry on the title page.
	firstTOC := -1
	for i := start + 1; i < len(lines); i++ {
		if lines[i].PageNo != tocPage {
			break
		}
		if isStaticTOCLine(lines[i]) {
			firstTOC = i
			break
		}
	}
	if firstTOC < 0 {
		return -1
	}

    ...
    if tocCount < 2 {
		logger.Warn("TOC detected but too few entries, likely a false positive",
			"FirstTOCLineNo", lines[firstTOC].LineNo,
			"Start", start,
			"EndIdx", endIdx,
			"TOCCount", tocCount)
		return -1
	}
    ...
}
```

Detecting TOC lines by statically analyzing lines is unreliable. Below is an example:
```text
48	6	list-item-num	unknown-font	12	[106, 247, 856, 322]	1 总 则 ………………………………………… (1)
49	6	list-item-num	unknown-font	12	[106, 247, 856, 322]	2 术语 (2)
50	6	list-item-num	unknown-font	12	[106, 247, 856, 322]	3 基本规定 (3)
51	6	list-item	unknown-font	12	[133, 329, 853, 374]	3.1 一般规定 (3)
52	6	list-item	unknown-font	12	[133, 329, 853, 374]	3.2 评价方法与等级划分 (3)
53	6	paragraph	unknown-font	12	[108, 381, 853, 401]	4 基础设施 (5)
54	6	list-item	unknown-font	12	[133, 408, 853, 505]	4.1 信息基础设施· （5）
55	6	list-item	unknown-font	12	[133, 408, 853, 505]	4.2 公共安全设施· （5）
56	6	list-item	unknown-font	12	[133, 408, 853, 505]	4.3 信息服务平台 (6)
57	6	list-item	unknown-font	12	[133, 408, 853, 505]	4.4 公共服务设施· （7）
58	6	paragraph	unknown-font	12	[108, 512, 853, 532]	5 生态与宜居 (8)
59	6	list-item	unknown-font	12	[133, 541, 853, 638]	5.1 节能环保 (8)
60	6	list-item	unknown-font	12	[133, 541, 853, 638]	5.2 住区环境 (8)
61	6	list-item	unknown-font	12	[133, 541, 853, 638]	5.3 物流交通 (9)
62	6	list-item	unknown-font	12	[133, 541, 853, 638]	5.4 智能家居 (10)
63	6	paragraph	unknown-font	12	[108, 645, 853, 665]	6 管理与服务 (12)
64	6	list-item	unknown-font	12	[133, 673, 853, 769]	6.1 系统管理 (12)
65	6	list-item	unknown-font	12	[133, 673, 853, 769]	6.2 物业管理 (15)
66	6	list-item	unknown-font	12	[133, 673, 853, 769]	6.3安全管理 (15）
```

The function reports a warning:
```text
2026-06-11 13:23:50 WARN [req=e-cf4681fc] TOC detected but too few entries, likely a false positive
call_flow=[
    control.go:83
    control.go:475
    control.go:741
    control.go:651
    control.go:614
    structure-static-analyzer.go:136
    structure-static-analyzer.go:393
    structure-static-analyzer.go:521
    structure-static-analyzer.go:968
] FirstTOCLineNo="49" Start="47" EndIdx="68" TOCCount="1"
```

# Decision
Instead of using static string patterns to determine TOC lines, do the following changes:
- Call the function `applyStaticTOCLabels(...)`, but change it to detect only `firstTOC`.
- If `firstTOC` > 0, fetch the lines of N pages, starting from the page of `firstTOC`.
  Otherwise, fetch the first M pages.
- Use EXTRACT_DOCMETA_MODEL_NAME with EXTRACT_DOCMETA_FALLBACK LLM using DETECT_TOC_LINES_PROMPT
  (this env var is currently set to "prompt-detect-toc-lines.md") to detect TOC lines.
- Create the prompt

## Implementation

### Modified Files
- `ChenWeb/server/api/doc-processing/structure-static-analyzer.go` — core changes
- `ChenWeb/server/api/doc-processing/llm_contracts.go` — added `tocDetectionContract()`
- `ChenWeb/server/cmd/doc-processor/main.go` — wired LLM client into constructor
- `ChenWeb/server/cmd/doc-processor/.env` — added `DETECT_TOC_LINES_PROMPT`

### New File
- `ChenWeb/prompts/prompt-detect-toc-lines.md`

### Key Design Decisions

**`applyStaticTOCLabels` restructured into two phases:**
1. `findStaticTOCHint(lines)` — finds `(start, firstTOC)` indices using existing static patterns; no labeling.
2. `applyLLMTOCLabels(ctx, lines, corrected, toc)` — calls the LLM with a targeted page window and writes the `corrected` map.

**LLM page window selection:**
- If `firstTOC >= 0`: send lines from `firstTOC.PageNo` through the next `DETECT_TOC_NUM_PAGES` pages (default 3).
- Otherwise (no dotted TOC line found): send the first `DETECT_TOC_FALLBACK_PAGES` pages (default 5).

**Fallback chain:**  Static detection is preserved at two levels:
1. `applyLLMTOCLabels` falls back to `applyStaticTOCLabels` if the LLM call fails.
2. When `NewStaticAnalyzerProcessor` is called with `client == nil` (e.g., in tests), `TOCDetector` is nil and `analyzeStaticStructureCtx` routes directly to `applyStaticTOCLabels`.

**Constructor signature change:**
```go
// Before
func NewStaticAnalyzerProcessor(store DocMetadataStore, logger ApiTypes.JimoLogger) *StaticAnalyzerProcessor

// After
func NewStaticAnalyzerProcessor(store DocMetadataStore, client LLMJSONExtractor, logger ApiTypes.JimoLogger) *StaticAnalyzerProcessor
```

**LLM output contract (`tocDetectionContract`):**
```json
{
  "toc_line_numbers": [47, 48, 49, 50, ...]
}
```

**Bug fixed alongside:** The existing code returned an error on malformed lines, violating spec §1.11 ("Ignore malformed lines and continue processing valid lines"). Changed to `logger.Warn` + `continue`.

### Environment Variables

| Variable | Description | Default |
|---|---|---|
| `DETECT_TOC_LINES_PROMPT` | Prompt file name | (required) |
| `EXTRACT_DOCMETA_MODEL_NAME` | Primary LLM model (shared with extract_metadata) | (required) |
| `EXTRACT_DOCMETA_MODEL_FALLBACK` | Fallback LLM model (shared with extract_metadata) | (optional) |
| `DETECT_TOC_NUM_PAGES` | Pages to send when TOC hint found | 3 |
| `DETECT_TOC_FALLBACK_PAGES` | Pages to send when no TOC hint found | 5 |

## Operational Behavior

- When `DETECT_TOC_LINES_PROMPT` is set and `EXTRACT_DOCMETA_MODEL_NAME` resolves successfully, the static analyzer makes one LLM call per document to detect TOC lines.
- If `DETECT_TOC_LINES_PROMPT` is not set, or the model config fails to load, `TOCDetector.isReady()` returns false and the processor silently falls back to the original static pattern matching — no error, no behavior change for documents with dot-leader TOCs.
- If the LLM call fails at runtime, the processor logs a warning and falls back to static detection for that document.
- A fallback model (`EXTRACT_DOCMETA_MODEL_FALLBACK`) is tried before falling back to static detection.

## Consequences

### Positive
- Correctly identifies TOC lines in documents where entries use page numbers in parentheses (`(1)`, `（5）`) instead of dot leaders, eliminating the false-negative that triggered this ADR.
- LLM-based detection is language-agnostic and handles mixed formats within a single TOC.
- Static detection is preserved as a layered fallback, so reliability does not decrease.
- Reuses existing `EXTRACT_DOCMETA_MODEL_NAME` infrastructure — no new model configuration is required.

### Trade-offs
- Adds one LLM call per document processed, increasing latency and cost for every document (not just those with unusual TOCs).
- TOC detection accuracy becomes dependent on prompt quality and model behavior.

## Verification

- All 22 existing `TestStatic*` tests pass with the new implementation.
- `TestStaticAnalyzer_SuccessWritesCorrectedAndStatus` now also validates the pre-existing malformed-line bug fix (skip instead of abort).
- The failing case from the ADR (page-number-in-parens TOC entries such as `2 术语 (2)`) is handled by the LLM prompt which explicitly covers this pattern.

## Documentation Impact

- `structure-analyzer-static-spec.md` §1.6.3 — the "Detect Table of Content" section describes the static pattern rules that are now used only as a hint; the LLM performs the actual classification. The spec should be updated to describe the two-phase approach.
- `+CAPSULE.md` §7 (Doc Processing Pipeline) — no structural change; `structure_analyzer` remains mandatory and in the same position. No pipeline table update needed.
- `+CAPSULE.md` §6.1 (LLM Input Format) — `staticInputLinesToJSON` follows the established JSON array format.

# References
[1] KnowledgeStore/Capsules/coding-capsules/doc-processor/structure-analyzer-static-spec.md

[2] KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md

[3] ChenWeb/server/api/doc-processing/structure-static-analyzer.go