# ADR: Static Analyzer - Detect `\dots`

- DocID: `doc-2026061109`
- **Status:** Accepted
- **Date:** 2026-06-11
- **Deciders:** Chen Ding
- **Tags:** static_analyzer, doc processor, detect `\dots`

## Change Logs
- Created by Chen Ding on 2026/06/11
- Implemented and spec updated on 2026/06/11

# Context
PDF parser sometimes generate long sequence of `\dots`. Below is an example:
```text
115	7	paragraph	unknown-font	12	[214, 364, 385, 378]	单体蓄电池数.
116	7	equation	unknown-font	12	[407, 401, 914, 453]	$$\n\eta = (1 - \frac {\gamma}{6 8 4}) \times 1 0 0 \% \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots \dots ...$$
```

# Decision
Add the function: replace long (more than 5) `\dots` sequences with 5 `\dots` to the
`static_analyzer` doc processor (refer to [1] and [2])

## Implementation

### Modified Files
- `ChenWeb/server/api/doc-processing/structure-static-analyzer.go`
  - Added `staticDotsSeqRE` regex: `\\dots(?:[ \t]*\\dots){5,}` — matches 6 or more `\dots` separated by optional spaces/tabs
  - Added `applyStaticTruncateDots(lines, logger)` function
  - Called in `analyzeStaticStructureCtx` after `applyStaticRemoveWeBoosWatermarkLines` and before `applyStaticCorrectHeadings`
- `ChenWeb/server/api/doc-processing/structure-static-analyzer_test.go`
  - Added `TestApplyStaticTruncateDots` with 6 cases covering: exactly 6, long sequence, exactly 5 (unchanged), 4 (unchanged), no dots, and dots without spaces
- `KnowledgeStore/Capsules/coding-capsules/doc-processor/structure-analyzer-static-spec.md`
  - Added §1.6.3 Truncate Long `\dots` Sequences
  - Renumbered §1.6.3–§1.6.7 → §1.6.4–§1.6.8

### New File
None.

### Key Design Decisions
- The regex `\\dots(?:[ \t]*\\dots){5,}` matches the first `\dots` plus 5+ more, so the threshold is ≥6 occurrences. The trailing whitespace after the last `\dots` is not consumed, preserving surrounding context.
- Replacement is `\dots \dots \dots \dots \dots` (5 occurrences, space-separated) regardless of original spacing.
- The fast path `strings.Contains(line.Content, \`\dots\`)` skips lines that cannot match, avoiding regex overhead on the majority of lines.

### Environment Variables
None.

## Operational Behavior
For every line in the input file, if its content contains a run of 6 or more `\dots` macros (space-separated or adjacent), the entire run is replaced with exactly 5 `\dots`. Lines with 5 or fewer are untouched.

## Consequences

### Positive
- Prevents downstream chunkers and LLM processors from receiving equations bloated with hundreds of `\dots` tokens.

### Trade-offs
- Any run of exactly 6+ `\dots` is reduced to 5 without regard for original spacing style; the replacement always uses single spaces.

## Verification
`TestApplyStaticTruncateDots` — 6 unit cases, all passing.

## Documentation Impact
- `structure-analyzer-static-spec.md` updated: added §1.6.3 and renumbered subsequent sections.

# References
[1] KnowledgeStore/Capsules/coding-capsules/doc-processor/structure-analyzer-static-spec.md

[2] KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md