# Feature: doc-structure-static-analyzer

## Summary
This processor analyzes document structure line by line and outputs corrected structure labels. 'static' means
it does not use LLMs to do the analysis.

- Language: Go
- Implementation target: `ChenWeb/server/api/doc-processing/structure-static-analyzer.go`
- Main inputs: `record_id`, `input_filename`, and `input_file` buffer
- This analyzer is independent from the LLM-based structure analyzer.

The processor preserves the original input line type and adds `corrected_line_type` right after the original 
line type. The original line-file has 7 fields; this analyzer outputs 8 fields by inserting `corrected_line_type`
as the 4th field (right after `line-type`). If no correction is made for a line, `corrected_line_type` is `unchanged`.

**UI reading order:** The Document Structure viewer (`/home3/knowledge` → "Document Structure") reads the `.txt`
file as its primary source. If a `.corrected` file also exists it is shown as supplementary context but the
line list is always populated from `.txt`. Manual corrections entered through the UI are written to a separate
`.manual` file (see "Manual Override File" section below).

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
- `ARTIFACT_DIR` (required): artifact output root directory
- `EXTRACT_DOCMETA_PROMPT` (optional): controls output destination.
  - If not defined or any value other than `false`: write corrected output back to the original input file (override origin).
  - If set to `false`: write to a separate `.corrected` artifact file instead.

Validation:
- Missing `ARTIFACT_DIR` when writing `.corrected` artifact => fail before processing.
- `ARTIFACT_DIR` is not required when `EXTRACT_DOCMETA_PROMPT != false` (origin override mode).

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
- `num-list-item`
- `s-sym-list-item`
- `m-sym-list-item`
- `table`
- `formula`
- `toc`
- `footer`
- `other`
- `unchanged`

Notes:
- Heading labels are encoded as `heading-N` (not `heading` + separate level).
- This analyzer does not detect cover pages and therefore does not emit `cover` as a corrected label.

## Processing Rules

The program will scan and detect in two rounds.

### Detecting Headings

#### Numerical Headings
This should be run in the first round.

Starting from the beginning of the input, numerical headings should form a continuous sequence of lines of
the following pattern:
```
1 <non-empty string>
1.1 <heading-title>
1.1.1 <heading-title>
1.1.2 <heading-title>
...
1.2 <heading-title>
...
2 <non-empty string>
...
```
If '<heading-title>' is empty and its next line is not empty and the next line type is 'paragraph', use it as 
its '<heading-title>'.

**Predict the Next Heading**

The program keeps the current heading: '[level1, level2, ...]', where 'level1' is the current level 1 heading
value, 'level2' is the current level 2 heading value, and so on. 

If the current heading is '[level1, level2, level3]', the next valid heading should be one of the following:
- '[level1, level2, level3 + 1]'
- '[level1, level2 + 1]'
- '[level11 + 1]'

#### Table of Content

This should be run in the first round.

*Pattern*
- A line with content: "Table of Content", "目录"
- Followed by at least two TOC lines (see below)

**TOC Line Definition**
- A line whose 'content' contains at least two '.' characters or at least one '…' character (Line 53, 55, 59 in the example below)
- Mix of '.' and '…' is allowed, such as Line 53 in the example below
- If there are up to three non-TOC lines between two TOC lines, these non-TOC lines are treated as TOC lines, such as Line 54 in the example below
- Heading numbers may contain spaces, such as '4. 1' in Line 58 in the example below
- One line may contain multiple, such as Line 58 in the example below 

Example:
```
53	6	list-item	Times-Roman	11	[51.53,413.008,348.96,425.508]	2 术语……..…………………………………………………… .2
54	6	list-item	Times-Roman	10	[51.96,395.183,120,406.789]	3 基本规定·
55	6	paragraph	HiddenHorzOCR	8	[67.8,378.23,155.28,389.39]	3. 1 一般规定…..
56	6	list-item	Times-Roman	10	[67.78,359.915,197.28,371.409]	3.2 评价与等级划分……
57	6	paragraph	HiddenHorzOCR	9	[51.57,342.445,349.479,353.774]	4 安全耐久…·………………………………………………….. 7
58	6	list-item	Times-Roman	10	[67.63,308.555,348.73,335.86]	4. 1 控制项…………………………………………………… 7 4.2 评分项…….........
59	6	list-item	Times-Roman	10	[51.7,255.045,118.56,266.539]	5 健康舒适..
```

Once a 'Table of Content' is detected:
- Change all its line-type to 'toc'
- Do not detect 'Table of Content' anymore.

#### Appendix Headings

This should be run in the first round.

Appendix headings are in the following pattern
```
<appendix-symbol>.1 <non-empty string>
<appendix-symbol>.1.1 <heading-title>
<appendix-symbol>.1.1.1 <heading-title>
<appendix-symbol>.1.1.2 <heading-title>
...
<appendix-symbol>.1.2 <heading-title>
...
<appendix-symbol>.2 <non-empty string>
...
```
Where '<appendix-symbol>' is a single letter, such as 'A', 'B'.

Predicting the next heading is similar to that of the numerical headings.

#### Detect Item Lists

This should be run in the second round.

A 'Item List' has the following pattern:
```
<list-symbol> <content>
<list-symbol> <content>
...
```
where `<list-symbol>` can be numbers ('1', '2', ...), single symbol ('*', '-', ...), others ('1)', '2)', 'a)', etc.) and the original list type is 'list-item'.

Example:
```
221	15	list-item	Times-Roman	11	[84.06,200.837,359.41,212.779]	2 门窗玻璃意外脱
263	17	list-item	HiddenHorzOCR	9	[70.32,191.47,312.732,202.57]	2) 采用耐候结构钢及耐候型防腐涂料;
```

**Detection Logic**
- For the pattern `1 xxx` or `1) xxx`, change line type to 'num-list-item'
- For single symbol list item, such as `* xxx`, `- xxx`, change line type to 's-sym-list-item'
- For multiple symbol list item, such as `a) xxx`, `ii) xxx`, change line type to 'm-sym-list-item'

### Corner Cases

- Heading numbers may be followed by a '.'
- Normalize numbering, remove spaces, if any, in heading numbers. Example: convert the original headings "3. 1. 1" to "3.1.1"
- Discontinued heading numbering pattern: Some document heading may be in the pattern:
```
1 <title>
1.0.1 <title>
1.0.2 <title>
...
2 <title>
2.0.1 <title>
...
```
The extra '0' happens at heading2 only.

## Output Artifacts
### Output Destination
Controlled by `EXTRACT_DOCMETA_PROMPT`:

**Override-origin mode** (default — `EXTRACT_DOCMETA_PROMPT` is not set or not `false`):
- If no corrections were made, skip writing entirely.
- If at least one correction was made:
  1. Back up the original input file to the same path with a `.origin` extension (e.g. `foo_parser.txt` → `foo_parser.origin`).
  2. Overwrite the original input `.txt` file in place.
- Output format: the original 7-field line-file, with `line-type` (field 3) replaced by the corrected type where a correction was made. Lines with no correction keep their original `line-type` unchanged.
- Do not produce a `.corrected` artifact.

**Corrected-artifact mode** (`EXTRACT_DOCMETA_PROMPT=false`):
- Output format: 8-field line-file — the original 7 fields with `corrected_line_type` inserted as the 4th field (right after `line-type`). If no correction is made for a line, `corrected_line_type` is `unchanged`; the original `line-type` is always preserved.
- Save the results to:
  `ARTIFACT_DIR + "/" + floor(record_id/1000) + "/" + record_id + "/" + filename-root + ".corrected"`
  where `filename-root` is the root of `kb.inputs.staging_filename + "_" + kb.inputs.parser_name`.

## Manual Override File (`.manual`)

The `.manual` file is **not produced by the static analyzer**. It is created and maintained by the Document
Structure UI (`PATCH /api/v1/kb/doc-structure` and `DELETE /api/v1/kb/doc-structure`). It is documented here
because it lives alongside the analyzer output files and shares their format.

### Purpose
Records every line that a user has manually edited or deleted through the UI. Provides an audit trail of
human corrections that can be replayed or diffed against the analyzer output.

### Path
```
ARTIFACT_DIR/{floor(id/1000)}/{id}/{filename-root}_{parser}.manual
```
Same directory and naming convention as `.txt` and `.corrected`, with extension `.manual`.

### Format
10-field tab-separated:
```
{operation}\t{line_number}\t{page_number}\t{line_type}\t{font}\t{font_size}\t[x1,y1,x2,y2]\t{timestamp}\t|$|{old-content}|$|\t|$|{new-content}|$|
```

Fields:
- `operation`: one of `modify`, `delete`
- `line_number`, `page_number`: identity of the line
- `line_type`: the current (post-operation) line type; for `delete` this is the original type before deletion
- `font`, `font_size`, `[x1,y1,x2,y2]`: unchanged from the source line
- `timestamp`: wall-clock time of the operation, formatted `yyyymmdd-hhmmss`
- `|$|{old-content}|$|`: original text content from the **first** edit of this line; never overwritten by subsequent edits
- `|$|{new-content}|$|`: text content after the operation; empty (`|$||$|`) for `delete`

The `|$|...|$|` delimiters allow content that itself contains `|$|` to be parsed unambiguously.

### Semantics
- **Modify:** when a user changes a line's type or content, the entry is written with `operation=modify`,
  `old-content` = the text before the change, `new-content` = the text after the change, and `line_type` =
  the updated type. The `.txt` file is also updated in place.
- **Delete:** when a user deletes a line, it is removed from `.txt` and upserted into `.manual` with
  `operation=delete`, `old-content` = the original text, `new-content` empty, and `line_type` = the
  original type. Coordinates are preserved so the deletion can be identified and potentially reversed.
- **Upsert key:** `(page_number, line_number)`. An existing entry for the same key is replaced, but
  `old-content` is **always preserved from the first entry** — subsequent upserts do not overwrite it.
- **Sort order:** lines are stored sorted ascending by `line_number` (then `page_number` as tiebreaker).
- The `.manual` file may be absent if no manual edits have been made.

## Update `kb.inputs.status`
Persist operation status using canonical name:
- `operation = "static_analyzer"`

Status payload (underscore fields only):
```json
{
  "operation": "static_analyzer",
  "input_filename": "...",
  "num_pages": 59,
  "num_lines": 267,
  "num_labeled_lines": 267,
  "start_time": "20260421 11:08:20",
  "ms_used": 245,
  "proc_status": "success"
}
```

Failure example:
```json
{
  "operation": "static_analyzer",
  "input_filename": "...",
  "num_pages": 59,
  "num_lines": 267,
  "num_labeled_lines": 120,
  "start_time": "20260421 11:08:20",
  "ms_used": 245,
  "proc_status": "failed",
  "error": "line 43 malformed: invalid field count"
}
```

Rules:
- attribute names MUST use underscores only
- `error` MUST be omitted on success
- replace existing `static_analyzer` status entry each run (no duplicates)

## Workflow
1. Validate required env vars.
2. Retrieve source record from `kb.inputs`.
3. Run the detection and correction defined in the "Processing Rules" section.
4. Write output per the "Output Destination" rules:
   - Override-origin mode: overwrite the original input `.txt` file.
   - Corrected-artifact mode: write `filename-root.corrected` under `ARTIFACT_DIR`.
5. Upsert `kb.inputs.status` with `operation = "static_analyzer"`.

## Failure Semantics
Failure handling:
- Ignore malformed lines and continue processing valid lines.
- database read/write failure => fail

## Acceptance Tests (Golden Cases)
The following behaviors are mandatory:
1. Hierarchical numbered headings:
   - `3` => `heading-1`
   - `3.` => `heading-1`
   - `3.1` => `heading-2`
   - `3. 1` => normalize to `3.1`, `heading-2`
   - `3.1.1` => `heading-3`
   - `3. 1. 1` => normalize to `3.1.1`, `heading-3`
2. Numeric list under intro sentence remains `list-item`.
3. `1)`/`2)` list lines => `num-list-item`.
4. `a)`/`b)` list lines => `m-sym-list-item`.
5. TOC-like pages are labeled `toc` only when TOC evidence matches rules.
6. OCR-noisy but valid schema input still runs successfully (best effort).
7. Malformed lines are ignored; processing continues for valid lines.

## Reference-only Backup
`spec-doc-structure-analyzer-bak.md` is non-canonical reference material.
