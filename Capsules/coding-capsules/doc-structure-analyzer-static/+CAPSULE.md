# Feature: doc-structure-static-analyzer

## 1.1 Summary
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

## 1.2 Inputs
- `record_id`: value of `kb.inputs.id`
- `input_filename`: source file name
- `input_file`: buffer containing line-file content

Input format requirement:
- Input MUST conform to the canonical Line File spec:
  `KnowledgeStore/DevDocuments/Specs/spec-line-file.md`.

Related context:
- metadata extraction spec:
  `KnowledgeStore/DevDocuments/Specs/spec-extract-metadata.md`.

## 1.3 Environment Variables
- `ARTIFACT_DIR` (required): artifact output root directory
- `EXTRACT_DOCMETA_PROMPT` (optional): controls output destination.
  - If not defined or any value other than `false`: write corrected output back to the original input file (override origin).
  - If set to `false`: write to a separate `.corrected` artifact file instead.

Validation:
- Missing `ARTIFACT_DIR` when writing `.corrected` artifact => fail before processing.
- `ARTIFACT_DIR` is not required when `EXTRACT_DOCMETA_PROMPT != false` (origin override mode).

## 1.4 Retrieve Record
Load source record from `kb.inputs` where `kb.inputs.id = record_id`.

Failure:
- database access error => fail
- record not found => fail

## 1.5 Classification Taxonomy
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

## 1.6 Processing Rules

IMPORTANT: processing must be done in the following order.

IMPORTANT: save the original line file to ".origin" first.

### 1.6.1 Remove Full-Page Image Artifact Lines

This should be run before TOC, heading, and list detection.

Remove lines that match all of the following:
- the original `line-type` is `image`
- the coordinate is in the form `[0,0,x,y]`
- the content exactly matches `<prefix>/imageFile<page-number>.png`
- all matching lines in the same file share the same `<prefix>`
- the `<page-number>` in the file name matches the line `page_number`

Example:
```
1	1	image	unknown-font	12	[0,0,624,879.12]	std_20039_images/imageFile1.png
10	2	image	unknown-font	12	[0,0,624,879.12]	std_20039_images/imageFile2.png
25	3	image	unknown-font	12	[0,0,624,879.12]	std_20039_images/imageFile3.png
33	4	image	unknown-font	12	[0,0,624,879.12]	std_20039_images/imageFile4.png
52	5	image	unknown-font	12	[0,0,624,879.12]	std_20039_images/imageFile5.png
87	6	image	unknown-font	12	[0,0,624,879.12]	std_20039_images/imageFile6.png
124	7	image	unknown-font	12	[0,0,624,879.12]	std_20039_images/imageFile7.png
```

Once detected, these lines are removed from the analyzer output entirely and are not passed to later analysis rounds.

### 1.6.2 Remove `www.weboos.com` Watermark Lines

This should be run before TOC, heading, and list detection.

Check for lines that match all of the following:
- the original `line-type` is `paragraph`
- the coordinate is in the form `[x1,y1,x2,y2]` and `x1` MUST be `0`
- the content starts with `www`, its length is no longer than the length of `www.weboos.com`
- there is only one such line per page

Apply this removal rule when the above condition is met.

Once this condition is met:
- remove all such matching lines from the entire file
- remove any occurrence of `www.weboos.com` from the content of any remaining line

Example:
```
7	1	paragraph	SimSun	89	[0,389.462,623.999,478.248]	www.weboos.com
26	2	paragraph	SimSun	89	[0,389.462,623.999,478.248]	www.weboos.com
35	3	paragraph	SimSun	89	[0,389.462,623.999,478.248]	www.weboos.com
45	4	paragraph	SimSun	89	[0,389.462,623.999,478.248]	www.weboos.com
272	10	paragraph	SimSun	89	[0,389.462,623.999,478.248]	www om
683	24	table-row	unknown-font	12	[99.42,376.32,541.08,422.82]	|注2 1高毒...<br>www.weboos.com|||
684	24	paragraph	SimSun	89	[0,389.462,623.999,478.248]	www m
```

The results:
- Line 7, 26, 35, 45, 272 and 684 should be removed
- Line 683 becomes "683	24	table-row	unknown-font	12	[99.42,376.32,541.08,422.82]	|注2 1高毒...<br>www.weboos.com|||"

### 1.6.3 Detect Table of Content

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

### 1.6.4 Correct Headings

#### 1.6.4.1 Rule 1
If line type is `heading`, change it to `heading-1`. 

Example:

  - `heading` => `heading-1`

#### 1.6.4.2 Rule 2
If line type is `heading(n)`, where n is a number, change to `heading-n`.

Examples:
  - `heading(1)` => `heading-1`
  - `heading(2)` => `heading-2`
  - `heading(3)` => `heading-3`

#### 1.6.4.3 Rule 3

Condition:
- It is a heading line
- Its section number matches one of the following pattern:
  * `<number1>.` + [`<space>`] + `<number2>` + [`<space>`] + `<number3>`, where `<number1>`, `<number2>`, and `<number3>` can be a number, the letter 'o', 'O', 's', 'S', 'l', and `<space>` is a space, which may or may not be present.

Action:
- Convert 'o' or 'O' to '0'
- Convert 's' or 'S' to '5'
- Convert 'l' to '1'
- Remove the spaces, if present

Examples
- '2.o.1' => '2.0.1' (no spaces)
- '3. o.2' => '3.0.2' (with only one space)
- '3.O. 2' => '3.0.2' (with only one space)
- '3. o. 2' => '3.0.2' (with both spaces)
- '3.0. 2' => '3.0.2' (with only one space)
- '3. 0. 2' => '3.0.2' (with both spaces)
- 's.2' => '5.1'
- 'S.3' => '5.3'

### 1.6.5 Detect Headings

#### 1.6.5.1 Detect Normal Headings
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

### 1.6.5.2 Detect Appendix Headings

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

### 1.6.5.3 Corner Cases for Detecting Headings

This applies to both normal headings and appendix headings.

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

### 1.6.6 Merge Lines

Purpose: lines that belong to the same natural paragraphs are often in separate lines.

#### 1.6.6.1 Merge Chinese-Style Lines

The first line of paragraphs in Chinese normally indent with two Chinese characters.

Rules:
- The first line starts with certain amount of indent. This starts a paragraph. Append the first line to the paragraph,
- The last character of the paragraph ends near line-end
- There is a subsequent line and the subsequent line starts at line-start
- When the above is met, merge the subsequent line to the paragraph and repeat. Otherwise, it finishes the current paragraph.

Note: It is important to detect line-start and line-end!

Examples
```text
74	5	paragraph	HiddenHorzOCR	9	[104.88,496.943,339.001,508.549]	职业健康监护 occupational health survei Ilance
75	5	paragraph	HiddenHorzOCR	9	[83.28,451.33,546.241,493.45]	以预防为目的，根预措施，保护
77	5	paragraph	HiddenHorzOCR	9	[83.76,436.27,140.4,447.37]	消防员健康。
78	5	heading-2	Times-Roman	11	[83.86,421.006,99.898,433.058]	3.9
79	5	paragraph	Times-Roman	10	[105.6,405.503,427.022,417.109]	职业危害防护装备 protective faci lities for occupational hazard
80	5	paragraph	HiddenHorzOCR	9	[105.36,390.37,546.721,401.77]	用于消除或者减少职业危害因素对消防员健康的损害或影响，达到保护消防员健康目的的装备，主
81	5	paragraph	HiddenHorzOCR	9	[84,375.3,297.121,386.4]	要包括侦检装备、个人防护装备、洗消装备等。
```
In this example, Line 80 starts at 105 and ends at 546 and Line 81 starts at 84. Looking at other lines in the
above example, it is not difficult to tell line-starts is around 83 and line-end is around 546 (need more lines 
to detect line-start and line end reliably).

Since Line 80 starts a paragraph, ends at line-and and its next line (Line 81) starts at line-start, they should
be merged.

#### 1.6.6.2 Merge English-Style Lines
English-Style lines will start paragraphs without indenting. Otherwise, the merge logic is the same as the Chinese-style merging.

### 1.6.7 Detect Item Lists

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

## 1.7 Output Artifacts
### 1.7.1 Output Destination

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

## 1.8 Manual Override File (`.manual`)

The `.manual` file is **not produced by the static analyzer**. It is created and maintained by the Document
Structure UI (`PATCH /api/v1/kb/doc-structure` and `DELETE /api/v1/kb/doc-structure`). It is documented here
because it lives alongside the analyzer output files and shares their format.

### 1.8.1 Purpose
Records every line that a user has manually edited or deleted through the UI. Provides an audit trail of
human corrections that can be replayed or diffed against the analyzer output.

### 1.8.2 Path
```
ARTIFACT_DIR/{floor(id/1000)}/{id}/{filename-root}_{parser}.manual
```
Same directory and naming convention as `.txt` and `.corrected`, with extension `.manual`.

### 1.8.3 Format
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

### 1.8.4 Semantics
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

## 1.9 Update `kb.inputs.status`
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

## 1.10 Workflow
1. Validate required env vars.
2. Retrieve source record from `kb.inputs`.
3. Run the detection and correction defined in the "Processing Rules" section.
4. Write output per the "Output Destination" rules:
   - Override-origin mode: overwrite the original input `.txt` file.
   - Corrected-artifact mode: write `filename-root.corrected` under `ARTIFACT_DIR`.
5. Upsert `kb.inputs.status` with `operation = "static_analyzer"`.

## 1.11 Failure Semantics
Failure handling:
- Ignore malformed lines and continue processing valid lines.
- database read/write failure => fail

## 1.12 Acceptance Tests (Golden Cases)
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

## 1.13 Reference-only Backup
`spec-doc-structure-analyzer-bak.md` is non-canonical reference material.
