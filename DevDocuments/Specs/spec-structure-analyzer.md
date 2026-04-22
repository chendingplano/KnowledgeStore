# Feature: doc-structure-analyzer

## Summary
This processor analyzes document structure line by line and outputs corrected structure labels.

- Language: Go
- Implementation target: `ChenWeb/server/api/doc-processing/doc-structure-analyzer.go`
- Main inputs: `record_id`, `input_filename`, and `input_file` buffer

The processor preserves the original input line type and adds:
- `corrected_line_type`
- `confidence`
- `reason`

## Inputs
- `record_id`: value of `kb.inputs.id`
- `input_filename`: source file name
- `input_file`: buffer containing line-file content

Input format requirement:
- Input MUST conform to the canonical Line File spec:
  `KnowledgeStore/DevDocuments/Specs/spec-line-file.md`.

Related context:
- metadata extraction spec:
  `KnowledgeStore/DevDocuments/Specs/spec-extract-metadata.md`.

## Environment Variables
- `STRUCTURE_DIR` (required): artifact output root directory
- `STRUCTURE_MODEL_NAME` (required): logical LLM model name, defined in `.models.toml` (see `KnowledgeStore/DevDocuments/Specs/spec-model-def.md`)
- `STRUCTURE_LLM_MAX_RETRIES` (optional, default 2): retries for invalid LLM output
- `STRUCTURE_PROMPT` (required): prompt file or prompt reference

Validation:
- Missing required env var => fail before processing.
- `STRUCTURE_MODEL_NAME` not found in `.models.toml` => fail before processing.

## Retrieve Record
Load source record from `kb.inputs` where `kb.inputs.id = record_id`.

Failure:
- database access error => fail
- record not found => fail

## Classification Taxonomy
Allowed `corrected_line_type` values:
- `heading-1`, `heading-2`, `heading-3`, ... (no fixed upper bound)
- `paragraph`
- `list-item`
- `table`
- `formula`
- `toc`
- `footer`
- `cover`
- `other`

Notes:
- Heading labels are encoded as `heading-N` (not `heading` + separate level).
- List subtype detection may be used internally for decision quality, but output label remains `list-item`.

## Processing Rules
1. Validate input strictly against line-file schema.
2. Fail fast on malformed lines.
3. Build structural context using neighboring lines/pages and numbering continuity.
4. Disambiguate headings vs list items using hybrid signals:
   - deterministic pre-signals (numbering pattern, punctuation, coordinate, font/font_size, original line_type)
   - local and cross-page context
   - LLM semantic decision
5. Detect cover pages at page level and output `cover_pages`.
6. Apply line-level labels for all lines, including `cover` where appropriate.
7. Best-effort uncertainty handling:
   - uncertain lines still receive valid labels
   - uncertainty lowers `confidence`
   - uncertainty alone MUST NOT fail a run

### Heading vs List Disambiguation
Heading candidate indicators:
- hierarchical numbering (`N`, `N.M`, `N.M.K`)
- numbering continuity with nearby section lines
- short/title-like content
- followed by body text or deeper subsection

List-item candidate indicators:
- enumerators (`1`, `1)`, `a`, `b`, symbols)
- sibling sequence nearby
- parent intro text such as "按下列", "如下:", "following:"
- sentence-like requirement content

Mandatory tie-break:
- if single-number prefix is ambiguous, prefer `list-item` when sibling sequence exists
- otherwise prefer `heading-1` only when section-boundary behavior is clear

Heading level assignment:
- `3 xxx` -> `heading-1`
- `3.1 xxx` -> `heading-2`
- `3.1.1 xxx` -> `heading-3`
- spaced numbering like `3. 1. 2` must be normalized before level inference

## Prompt Contract (LLM I/O)
LLM input includes ordered line objects:
```json
{
  "line_number": 109,
  "page_number": 10,
  "line_type": "paragraph",
  "font": "HiddenHorzOCR",
  "font_size": "11",
  "coordinate": "[160.76,484.42,238.69,499.932]",
  "content": "3 基本规定"
}
```

LLM output must be strict JSON:
```json
{
  "cover_pages": [1],
  "labels": [
    {
      "line_number": 109,
      "corrected_line_type": "heading-1",
      "confidence": 0.94,
      "reason": "Top-level section marker followed by subsection."
    }
  ]
}
```

Output validation rules:
- parseable JSON
- required fields present
- exactly one label per input line
- no duplicate/missing `line_number`
- valid `corrected_line_type`
- `confidence` in `[0,1]`
- non-empty `reason`

Retry policy:
- retry up to `STRUCTURE_LLM_MAX_RETRIES` on invalid output
- include compact feedback about schema issues in retry prompt
- if still invalid => fail

## Output Artifacts
Run directory:
- `run_dir = STRUCTURE_DIR + "/" + floor(record_id/1000) + "/" + record_id`

Files:
- `run_dir/structure_labels.jsonl`
- `run_dir/structure_summary.json`

Overwrite policy:
- each run overwrites both files for the same `record_id`

### `structure_labels.jsonl`
One JSON object per input line, preserving order:
```json
{
  "line_number": 109,
  "page_number": 10,
  "original_line_type": "paragraph",
  "corrected_line_type": "heading-1",
  "confidence": 0.94,
  "reason": "Top-level section marker followed by subsection numbering."
}
```

Rules:
- 1:1 mapping with valid input lines
- all fields required
- `reason` must be non-empty

### `structure_summary.json`
```json
{
  "record_id": 7523,
  "cover_pages": [1],
  "num_pages": 59,
  "num_lines": 267,
  "num_labeled_lines": 267,
  "model": "..."
}
```

Rules:
- `cover_pages` sorted unique positive integers
- `num_labeled_lines` SHOULD equal `num_lines` for valid inputs

## Update `kb.inputs.status`
Persist operation status using canonical name:
- `operation = "structure_analyzer"`

Status payload (underscore fields only):
```json
{
  "operation": "structure_analyzer",
  "input_filename": "...",
  "num_pages": 59,
  "num_lines": 267,
  "num_labeled_lines": 267,
  "num_cover_pages": 1,
  "start_time": "20260421 11:08:20",
  "ms_used": 245,
  "proc_status": "success"
}
```

Failure example:
```json
{
  "operation": "structure_analyzer",
  "input_filename": "...",
  "num_pages": 59,
  "num_lines": 267,
  "num_labeled_lines": 120,
  "num_cover_pages": 0,
  "start_time": "20260421 11:08:20",
  "ms_used": 245,
  "proc_status": "failed",
  "error": "line 43 malformed: invalid field count"
}
```

Rules:
- attribute names MUST use underscores only
- `error` MUST be omitted on success
- replace existing `structure_analyzer` status entry each run (no duplicates)

## Workflow
1. Validate required env vars.
2. Retrieve source record from `kb.inputs`.
3. Validate and parse input line file strictly.
4. Build model input and run LLM classification with retries on invalid output.
5. Validate output schema and enforce 1:1 line mapping.
6. Write `structure_labels.jsonl` and `structure_summary.json`.
7. Upsert `kb.inputs.status` with `operation = "structure_analyzer"` and run metrics.

## Failure Semantics
Fail-fast conditions:
- malformed input line file
- database read/write failure
- LLM hard failure (timeout/transport)
- LLM output remains invalid after retries

Non-fail condition:
- model uncertainty, as long as output schema is valid (best effort)

## Acceptance Tests (Golden Cases)
The following behaviors are mandatory:
1. Hierarchical numbered headings:
   - `3` => `heading-1`
   - `3.1` => `heading-2`
   - `3.1.1` => `heading-3`
2. Numeric list under intro sentence remains `list-item`.
3. `1)`/`2)` list lines => `list-item`.
4. `a`/`b` list lines => `list-item`.
5. Spaced numbering `3. 1. 2` normalized and classified correctly.
6. Single-page cover detection => `cover_pages = [1]` where applicable.
7. Multi-page cover detection supported.
8. TOC-like pages are not forced as cover without evidence.
9. OCR-noisy but valid schema input still runs successfully (best effort).
10. Malformed input fails immediately with failed status and error.
11. Invalid LLM schema retries then fails when still invalid.
12. Same input/model/settings should produce stable labels and `cover_pages`.

## Reference-only Backup
`spec-doc-structure-analyzer-bak.md` is non-canonical reference material.
