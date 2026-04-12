# PDF Pipeline Status State Machine (Normalized)

## Purpose
Define one canonical status model for PDF records in table `kb.inputs` so all services and UI filters interpret status the same way.

## Canonical Scope
- Table name: `kb.inputs`
- Record scope: rows where `type = 'pdf'`
- Status field: `status` (JSON array)

## Canonical Status Entry Schema
Each element in `status` MUST follow:

```json
{
  "operation": "parsing|parsed|converted|semantic|summarized",
  "proc_status": "in_progress|success|failed",
  "time": "YYYYMMDD HH:MM:SS",
  "ms_used": 12345,
  "progress": 0.0,
  "error": "error message or empty"
}
```

Notes:
- `progress` is only for in-progress operations (typically `parsing`).
- `error` is required when `proc_status = failed`.
- Keep old fields (`proc-status`, `time-used`, `start_time`, `ms-used`) for backward compatibility during migration, but new writes should use canonical names above.

## State Machine (PDF)

### States
- `PENDING`: no `parsed` success/failed entry exists
- `PARSING`: latest parsing-related entry is `operation=parsing` + `proc_status=in_progress`
- `PARSED_SUCCESS`: latest parse result is `operation=parsed` + `proc_status=success`
- `PARSED_FAILED`: latest parse result is `operation=parsed` + `proc_status=failed`
- `CONVERTED_SUCCESS`: latest convert result is `operation=converted` + `proc_status=success`
- `CONVERTED_FAILED`: latest convert result is `operation=converted` + `proc_status=failed`

### Allowed Transitions
1. `PENDING -> PARSING`
2. `PARSING -> PARSED_SUCCESS`
3. `PARSING -> PARSED_FAILED`
4. `PARSED_SUCCESS -> CONVERTED_SUCCESS`
5. `PARSED_SUCCESS -> CONVERTED_FAILED`
6. `PARSED_FAILED -> PARSING` (retry parse)
7. `CONVERTED_FAILED -> CONVERTED_SUCCESS` (retry conversion)
8. `CONVERTED_FAILED -> PARSING` (full reprocess)

### Guard Rules
- Converter MUST only run when `PARSED_SUCCESS`.
- If `parser_name` is empty or `opendata`, use opendata converter.
- If `parser_name = paddleocr`, use paddleocr converter.
- Unknown parser name -> write `converted/failed` with error.

## Write Rules by Service

### Parse Service
1. Start: append or upsert `{"operation":"parsing","proc_status":"in_progress",...,"progress":0.0}`
2. Progress update: update `progress` (or append periodic progress events if append-only model is preferred)
3. Finish success: replace active parsing marker with `{"operation":"parsed","proc_status":"success",...}`
4. Finish failure: replace active parsing marker with `{"operation":"parsed","proc_status":"failed","error":"..."}`

### Convert Service
1. Validate `PARSED_SUCCESS` exists as latest parse result
2. Run converter by parser type
3. Append `{"operation":"converted","proc_status":"success",...}` or
4. Append `{"operation":"converted","proc_status":"failed","error":"..."}`

## UI Filter Semantics (Import Page)

Use these normalized definitions:
- `Pending`: no `operation="parsing"` in progress AND no `operation="parsed"` result yet
- `Parsing`: latest parse-related state is `PARSING`
- `Parsed Success`: latest parse-related state is `PARSED_SUCCESS`
- `Parsed Failed`: latest parse-related state is `PARSED_FAILED`
- `Converted Success`: latest convert-related state is `CONVERTED_SUCCESS`
- `Converted Failed`: latest convert-related state is `CONVERTED_FAILED`

Important:
- Evaluate by latest event time for each operation family (parse/convert), not by mere existence of any historical success/failure entry.

## Compatibility Mapping (Current Docs -> Canonical)

| Legacy key/value | Canonical |
|---|---|
| `proc-status` | `proc_status` |
| `time-used` / `ms-used` | `ms_used` |
| `status` (inside entry) | `proc_status` |
| `operation=parse` | `operation=parsed` (final parse result) |
| table `kb.input` | table `kb.inputs` |

## Minimal Example Timeline

```json
[
  {"operation":"parsing","proc_status":"in_progress","time":"20260411 10:00:00","ms_used":0,"progress":0.25},
  {"operation":"parsed","proc_status":"success","time":"20260411 10:02:10","ms_used":130000},
  {"operation":"converted","proc_status":"success","time":"20260411 10:02:20","ms_used":9000}
]
```

## Recommendation
Update all related docs and code to this canonical model first, then regenerate Graphify. Graph queries will become significantly more precise once terminology is consistent.
