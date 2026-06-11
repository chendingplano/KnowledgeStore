# ADR: PDF Parser Status Management

- DocID: `doc-2026061002`
- **Status:** Accepted
- **Date:** 2026-06-10
- **Deciders:** Chen Ding
- **Tags:** doc-processing, pdf-parser, status management

## Change Log
- Created by Chen Ding on 2026/06/10
- Implemented by Claude Code on 2026/06/10: `record_parse_active` now carries `parser_name`/`num_pages`; `record_parsed_failure` writes `proc_status: "failed"`; throttle callback passes `total_pages` through.

## Context
PDF parser, currently implemented in ChenWeb/python/pdf-parser, is a service in Python
(refer to `doc-2026042401`).

## Changes
`kb.inputs.status` status management is changed (refer to `doc-2026061001`).
PDF parser status management is changed accordingly as follows:

- When the PDF parser starts processing a record, upsert a `kb.input_proc_status` record:
```text
record_id: <record_id>
processor: 'parsed'
status: 'active'
```

Upsert `kb.inputs.status` element:
```json
  {
    "ms-used": 129734,
    "num_pages": 15,
    "operation": "parsed",
    "start_time": "20260609 18:05:05",
    "parser_name": "mineru",
    "proc_status": "active",
    "progress": "15%"
  },
```

- When it finishes, upsert `kb.input_proc_status` record:
```text
record_id: <record_id>
processor: 'parsed'
status: 'success | failed'
```

Upsert `kb.inputs.status` element:
```json
  {
    "ms-used": 129734,
    "num_pages": 15,
    "operation": "parsed",
    "start_time": "20260609 18:05:05",
    "parser_name": "mineru",
    "progress": "%",
    "proc_status": "success | failed",
    "error":"the error message if it fails"
  },
```

## Implementation Record

### What knowledge changed

- The `"parsed"` status entry in `kb.inputs.status` now carries `parser_name` and `num_pages` during the **active** phase (not only on success).
- Parse failures write `proc_status: "failed"` (was `"fail"`). The DB trigger's `input_status_parse_state` and `idx_kb_input_proc_status_failed` already expected `"failed"`.
- The progress throttle callback now forwards `total_pages` to `record_parse_active` so `num_pages` is updated on every throttled write, not just at parse completion.

### Which docs/specs/ADRs/tests were affected

- This ADR (`doc-2026061002`) — the spec being implemented.
- `KnowledgeStore/Capsules/coding-capsules/pdf-parser/+pdf-parser.md` §7 — active-entry JSON example (missing `parser_name`/`num_pages`) and failure-entry JSON (`"fail"` → `"failed"`); parse_state derivation table.
- `ChenWeb/python/pdf-parser/tests/test_shared.py` — `proc_status` assertion updated.
- `ChenWeb/python/pdf-parser/tests/test_pdf_parser.py` — throttle callback signatures updated.

### Which docs were updated

- This ADR: `Draft` → `Accepted`; implementation note added to Change Log.
- `+pdf-parser.md` §7: active entry now shows `parser_name`/`num_pages`; failure entry uses `"failed"`; parse_state table updated.

### Which docs are now stale

None. `doc-processor-dashboard-spec.md` and `doc-processor-dashboard-impl.md` already accepted both `"fail"` and `"failed"` — no update needed.

### What was intentionally left undocumented

Existing DB rows with `proc_status: "fail"` are still mapped correctly to `parsed_failed` by the trigger (backward compatibility is in the SQL `CASE` expression, not application policy — no documentation change needed).