# ADR: Restart PDF parsing is a forced reparse

- DocID: `doc-2026061106`
- **Status:** Accepted
- **Date:** 2026-06-11
- **Deciders:** ChenWeb / KnowledgeStore maintainers
- **Tags:** pdf-parser, jetstream, doc-processing, restart, force

## Change Logs

- Created by Codex on 2026/06/11

## Context

The KnowledgeStore ingestion UI exposes a `Restart` action for each `kb.inputs`
record. For PDF records, selecting `parse_file` publishes a JetStream event on
`kb.pdf.staged` with:

```json
{
  "record_id": "203",
  "type": "pdf",
  "status": "success",
  "force": true
}
```

The user expectation is that clicking `Restart` means "run this stage again."
For PDF parsing, that must mean a real reparse even if the record already has:

```json
{
  "operation": "parsed",
  "proc_status": "success"
}
```

Two related bugs were found while debugging record `203`:

1. A failed parsed entry was treated as "already parsed" because the Python PDF
   parser checked only for the existence of `operation = "parsed"`.
2. The UI and Go JetStream event endpoint already carried `force: true`, but
   the Python PDF parser ignored the `force` field and still skipped records
   whose parse had succeeded.

Example symptom for the first bug:

```text
20260611 09:57:30 [INFO] (MID_2026040716) record id=203 already parsed - acking redelivered message
```

At the same time, `kb.inputs.status` showed the parse had failed:

```json
[
  {
    "operation": "parsed",
    "proc-status": "failed",
    "error": "mineru exited 1: ... Aborted!"
  }
]
```

The converter then correctly failed with:

```text
kb.inputs record missing parsed success status
```

This exposed a mismatch between stages: the converter required parsed success,
but the parser redelivery guard treated any parsed entry as terminal.

## Decision

Treat PDF parser `Restart` as a forced parse request.

For JetStream events consumed from `kb.pdf.staged`:

- `force: true` bypasses the "already parsed successfully" skip.
- `force: true` still respects an active parse claim, so double-clicks or
  repeated events do not start concurrent parses for the same record.
- `force: true` also bypasses duplicate-MD5 shortcutting, so the requested
  record itself is parsed again instead of being marked `duplicated`.
- A failed parse entry is retryable and must not count as "already parsed."

Non-forced events keep the existing idempotency behavior:

- records with `parsed` + `proc_status = "success"` are acked and skipped;
- records with `parsed` + `proc_status = "active"` are acked and skipped;
- records with `parsed` + `proc_status = "failed"` can be retried.

## Implementation

Changed Python PDF parser behavior in `ChenWeb/python/pdf-parser`:

- `shared.py`
  - Added `has_parse_success_or_active(raw_status)`.
  - This returns true only when the `parsed` entry has `proc_status` or
    legacy `proc-status` equal to `success` or `active`.
  - It does not treat `failed` as terminal success.

- `pdf_parser.py`
  - Added `should_skip_existing_parse(raw_status, force=False)`.
  - The JetStream `kb.pdf.staged` consumer now reads `force` from the payload.
  - The redelivery guard now uses `should_skip_existing_parse`.
  - `_process_record(..., force=True)` skips duplicate-MD5 detection so forced
    restart actually reparses the selected record.

- Tests
  - Added regression tests for failed parse retryability.
  - Added regression tests for force behavior:
    - force does not skip a successful parse;
    - non-force still skips a successful parse;
    - force still skips active parse;
    - force bypasses duplicate shortcut and invokes parser backend.

## Operational Behavior

### Restart with parse_file selected

1. UI publishes `kb.pdf.staged` with `force: true`.
2. Python PDF parser receives the event.
3. If the record is currently `active`, the event is acked and skipped.
4. If the record is `success` or `failed`, the parser runs again.
5. On success, the existing single `parsed` status entry is updated to
   `proc_status = "success"` with fresh timing/result metadata.
6. On failure, the same `parsed` status entry is updated to
   `proc_status = "failed"`.

### Redelivered normal parser event

1. Event has no `force: true`.
2. If parse already succeeded or is active, event is acked and skipped.
3. If parse failed, event is allowed to retry.

## Consequences

### Positive

- The UI `Restart` button now matches user expectation: a forced PDF parse
  reruns the parser even after a previous success.
- Failed parses are no longer trapped behind a false "already parsed" guard.
- Active parses remain protected against accidental concurrent duplicate work.
- The converter's success-only requirement is now consistent with parser
  retry/skip semantics.

### Trade-offs

- A forced reparse can overwrite an existing successful parse result and status
  metadata. This is intentional for `Restart`.
- Forced reparse bypasses duplicate-MD5 optimization. This may do extra work,
  but it is the correct interpretation of a user-requested force operation.
- The behavior depends on callers sending `force: true`. The current ingestion
  and doc-processor dashboard Restart flows already do this.

## Verification

Ran the full Python PDF parser test suite:

```bash
cd /Users/cding/Workspace/ChenWeb/python/pdf-parser
uv run pytest -q
```

Result:

```text
72 passed
```

## Documentation Impact

What knowledge changed:

- `Restart` for PDF parsing is explicitly a forced reparse.
- Parser idempotency is now conditional on `force`.
- `proc_status = "failed"` is retryable and must not be treated as parsed.

Docs/specs/ADRs/tests affected:

- This ADR documents the behavior.
- Parser regression tests were updated in `python/pdf-parser/tests`.

Docs updated:

- `doc-2026061106` created.

Docs now stale:

- Any document that says a `parsed` operation exists means parsing is complete
  is stale. The lifecycle state must be read from `proc_status`.

Intentionally left undocumented:

- Exact UI component details for the Restart dialog, because the UI already
  sends `force: true`; the behavior change is in the parser consumer.
