# Line File Specification

A **Line File** is a UTF-8 text file where each non-empty record line encodes exactly one document line in a strict 7-field TAB-separated schema.

## 1. Canonical Record Format

Each record line MUST be:

```text
<line_number>\t<page_number>\t<line_type>\t<font>\t<font_size>\t<coordinate>\t<content>
```

- Delimiter is **TAB (`\t`) only**.
- Each record line MUST contain **exactly 6 TAB delimiters** (7 fields).
- Space-separated variants are invalid.
- Additional fields are invalid.
- Missing fields are invalid.

## 2. Field Definitions

1. `line_number`
- Integer, base-10, `>= 1`.
- SHOULD be strictly increasing by 1 within a file.
- Duplicate or non-increasing values SHOULD be treated as malformed input by consumers that require ordered lines.

2. `page_number`
- Integer, base-10, `>= 1`.

3. `line_type`
- Non-empty string token describing line category.
- Examples: `heading`, `paragraph`, `list-item`, `table`, `formula`, `toc`, `footer`.
- Unknown values are allowed unless a downstream processor explicitly restricts them.

4. `font`
- Non-empty string.
- Font family or parser-provided font identifier.

5. `font_size`
- Numeric value encoded as text (integer or decimal).
- Must parse to a number `> 0`.

6. `coordinate`
- Bounding box text in the exact shape: `[x1, y1, x2, y2]`.
- `x1`, `y1`, `x2`, `y2` are numeric values.
- Optional spaces after commas are allowed.

7. `content`
- Text content for the line.
- May contain spaces and punctuation.
- Literal newline characters are not allowed inside a physical record line.
- If logical newlines are needed, they MUST be escaped in content (for example `\n`).

## 3. File-Level Rules

- Encoding: UTF-8.
- Line ending: LF (`\n`) recommended; CRLF tolerated.
- Empty/whitespace-only lines MAY be ignored by readers unless a processor defines stricter behavior.
- Producers MUST emit canonical 7-field TAB-separated records only.

## 4. Validation and Failure Semantics

A record is **malformed** if any of the following is true:
- Field count is not exactly 7.
- Delimiter is not TAB.
- `line_number` or `page_number` is missing/invalid.
- `font` is empty.
- `font_size` is missing or not a positive number.
- `coordinate` is missing or not parseable as `[x1, y1, x2, y2]`.

For strict processors, malformed input MUST cause fail-fast behavior with clear error context (at minimum: record index/line number and reason).

## 5. Compatibility Policy

This spec is the single canonical contract for line files.
- Legacy 5-field formats are not supported.
- Consumers and producers MUST NOT implement automatic fallback to legacy parsing.

## 6. Example

```text
1\t1\theading\tTimesNewRoman-Bold\t16\t[72.0, 88.5, 540.2, 112.9]\tProject Overview
2\t1\tparagraph\tTimesNewRoman\t11\t[72.0, 124.0, 540.1, 140.4]\tThis document defines requirements for the release.
3\t1\tlist-item\tCalibri\t11\t[90.0, 152.2, 530.4, 168.7]\t1) Enable strict line-file parsing across all services.
```

## 7. Reference Usage

All specs and components that consume or produce line files MUST reference this specification instead of redefining line-file schema inline.
