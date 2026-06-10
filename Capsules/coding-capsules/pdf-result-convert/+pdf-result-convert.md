# Parser Result Converter Specification

This document describes the current behavior of the parser-result-converter service implemented in:

- `ChenWeb/server/cmd/parser-result-converter`
- `ChenWeb/server/api/file-converters`

Its job is to convert parser outputs for PDF inputs into a canonical **Line File**, which is the internal standard input consumed by the downstream document-processing pipeline.

The produced Line File MUST conform to:
`KnowledgeStore/Capsules/coding-capsules/input-management/spec-line-file.md`

## Service Role

- Subscribe to JetStream subject `kb.pdf.parsed`
- Load the corresponding `kb.inputs` record by `record_id`
- Validate that the record is eligible for conversion
- Convert the parser result into a canonical Line File
- Update `kb.inputs.status` with operation `converted`
- Publish a completion event to `kb.line-file-generated` only when
  `DOC_PROCESSOR_MODE=auto` or `DOC_PROCESSOR_MODE` is unset/empty

## Incoming Message

The service accepts JSON payloads with:

- `record_id` required
- `result_filename` optional override for the parser result file path
- `file_format` optional metadata passthrough
- `type` optional filter
- `status` optional filter
- `force` optional reprocess flag

### Message Filtering

Messages are ignored unless:

- `type` is empty or `pdf`
- `status` is empty or `success`

### Force/Reprocess

- If `force` is omitted, the service defaults to reprocessing.
- If `force=false` and the record already has a successful `converted` status entry, the service skips conversion.

## Record Preconditions

After loading `kb.inputs`, the service requires:

- `type = pdf`
- `status` contains `{"operation":"parsed","proc-status":"success"}`

If these checks fail, the service writes a failed `converted` status entry.

## Supported Parser Names

Current behavior:

- empty parser name or `opendata`: supported
- `mineru`: supported
- `paddleocr`: recognized but not implemented
- `docline`: recognized but not implemented
- any other parser name: unsupported

## Output File

For `opendata`, the converter resolves the parser JSON and writes:

- output directory: same directory as the input JSON
- primary working line file: `<input-root>_<parser_name>.txt`
- immutable backup copy of the same converted content: `<input-root>_<parser_name>.origin`
- set `<input-root>_<parser_name>.origin` read-only
- downstream processors that modify line files MUST treat `.txt` as the writable working file and MUST NOT modify `.origin`

where `<input-root>` is the root of 'kb.inputs.staging_filename' and `<parser_name>` is 'kb.inputs.parser_name'.

Example:

- input: `stdGk_3032172.json`
- output: `stdGk_3032172_opendata.txt` and `stdGk_3032172_opendata.origin`

## Line File Format

Each output record is one TAB-separated line with the canonical 7 fields:

1. line number
2. page number
3. type
4. font
5. font size
6. bbox
7. content

The converter uses:

- source font and font size when available
- fallback font `unknown-font`
- fallback font size `12`

## opendata Conversion Rules

### Basic Node Conversion

For each extracted node:

- `page number` becomes the line page
- `type` becomes the line type
- `heading level`, when present, is appended as `type(heading-level)`
- `content` becomes the line content
- if `content` is empty and `source` exists, `source` is used instead
- `bounding box` becomes the line bbox

### Containers Ignored or Expanded

- `header` containers are ignored completely
- `footer` containers are ignored completely
- `list` containers are not emitted directly; their `list item` children are emitted instead

### Table Conversion

`table` nodes are converted into one output line per rendered row:

- output type: `table-row`
- content: a Markdown row such as `|col1|col2|col3|`
- any literal `|` inside a cell is escaped as `\|`
- row bbox is the union of all participating cell bounding boxes
- if row cell bboxes are missing, the table bbox is used

### Split Table Merge

Two consecutive tables are merged across pages when either:

- `previous table id` / `next table id` link them, or
- their first rendered rows have the same header row content

When merged by matching headers, the duplicate header row from the later table is removed.

### Page Number Cleanup

The converter removes trailing page-number-only lines when the last non-footer line on a page is a single Arabic or Roman numeral token.

### Repeated Line Cleanup

The converter can remove repeated page-furniture text that survives parser extraction.

Rule:

- If the same non-empty content appears on every page of the document, all such lines are removed from the Line File.

Configuration:

- env var: `LINE_FILE_REMOVE_REPEAT_LINES`
- default behavior: repeated lines are removed
- disable only when `LINE_FILE_REMOVE_REPEAT_LINES=false`
- env var: `LINE_FILE_REMOVE_REPEAT_PERCENT`
- default threshold: `85`
- if the same non-empty content appears on at least `LINE_FILE_REMOVE_REPEAT_PERCENT` percent of pages, those lines are removed

This cleanup runs after page-number cleanup and before final line rendering.

## mineru Conversion Rules

### Input Format

The mineru parser produces a tab-separated text file. Each record is a single line with 7 fields, but the raw output may contain multi-line values in the `bbox` field. Specifically, the bounding box is emitted as a JSON array spanning multiple lines:

```text
1	1	heading(1)	unknown-font	12	[
            176,
            384,
            865,
            462
          ]	健康信息学 健康体检基本内容与格式规范
```

### Coordinate Normalization

The converter MUST collapse multi-line JSON array coordinates into a single line with space-separated numbers:

- strip the surrounding `[` and `]`
- strip commas and surrounding whitespace from each number
- join the numbers with a single space

Example: `[\n  176,\n  384,\n  865,\n  462\n]` → `176 384 865 462`

The normalized output line for the example above is:

```text
1	1	heading(1)	unknown-font	12	176 384 865 462	健康信息学 健康体检基本内容与格式规范
```

### Other Fields

All other fields (line number, page number, type, font, font size, content) are taken from the mineru record as-is, following the same fallback rules as opendata: `unknown-font` and `12` when font or font size are absent.

## Content Escaping

Before writing the Line File:

- CRLF, LF, and CR are converted to the literal sequence `\n`
- TAB is converted to the literal sequence `\t`

## Status Management

The converter appends or replaces the `converted` status entry in `kb.inputs.status`.

Success shape:

```json
{
  "operation": "converted",
  "start_time": "20260409 17:00:30",
  "ms-used": 12345,
  "proc-status": "success"
}
```

Failure shape:

```json
{
  "operation": "converted",
  "start_time": "20260409 17:00:30",
  "ms-used": 12345,
  "proc-status": "failed",
  "error": "error message"
}
```

## Completion Event

After status update, the service may publish to `kb.line-file-generated`.

Publishing is controlled by `DOC_PROCESSOR_MODE`:

| `DOC_PROCESSOR_MODE` value | Completion event behavior |
|---|---|
| unset or empty | Publish to `kb.line-file-generated` |
| `auto` | Publish to `kb.line-file-generated` |
| any other value, including `dev` | Do not publish any event |

Conversion and `kb.inputs.status` updates still run regardless of
`DOC_PROCESSOR_MODE`; only the downstream completion event is suppressed.

Current payload:

```json
{
  "record_id": 123,
  "type": "pdf",
  "status": "success",
  "file_format": "json",
  "result_filename": "/path/to/parser-result.json",
  "line_file_filename": "/path/to/parser-result_opendata.txt"
}
```

On conversion failure, `status` is `failed` and `error` is populated.

## Environment Variables

Important runtime variables:

- `NATS_URL`
- `NATS_USER`
- `NATS_PASS`
- `NATS_TOKEN`
- `DOC_PROCESSOR_MODE`: defaults to `auto`. When unset, empty, or `auto`, the
  converter publishes `kb.line-file-generated` after successful conversion.
  For any other value, including `dev`, the converter does not publish any
  completion event.
- `PARSER_RESULT_CONVERTER_DURABLE`
- `PARSER_RESULT_CONVERTER_STREAM`
- `PARSER_RESULT_CONVERTER_AUTO_RECREATE_STREAM`
- `PARSER_RESULT_CONVERTER_CONFIG`
- `LINE_FILE_REMOVE_REPEAT_LINES`
- `LINE_FILE_REMOVE_REPEAT_PERCENT`

## Notes

- The subscription subject is fixed to `kb.pdf.parsed`.
- The completion publish subject defaults to `kb.line-file-generated`.
- This spec reflects the current implementation, not planned future parser support.
