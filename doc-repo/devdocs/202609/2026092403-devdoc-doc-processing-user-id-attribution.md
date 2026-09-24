# Doc-Processing user_id Attribution — every LLM call gets billed to someone

**Date:** 2026-09-24
**Scope:** Why `llm_usage_event` rows kept showing up with no owner, and the fix that
makes ChenWeb refuse to run a document-processing pipeline rather than run it
unattributed.
**Code root:** `ChenWeb/server/api/doc-processing/` (enforcement),
`ChenWeb/server/api/file-converters/` (automatic-trigger fix),
`ChenWeb/server/api/jetstreamhandler/` (manual-trigger fix)

## Summary

Every time ChenWeb extracts metrics, products, or anything else from a document
using an LLM, it's supposed to record *who* asked for that work, so the cost can
eventually be billed to the right customer. That record was routinely missing:
whole categories of processing runs — anything kicked off automatically after a
file upload, and even some manually-triggered runs — went through without ever
attaching an owner, so their LLM spend was logged but effectively untraceable.

This was found while chasing an unrelated bug and turned out to be a real gap, not
a one-off: the code path responsible for tagging a run with its owner had never
actually been wired up for the automatic case, and the manual case only logged a
warning instead of stopping the run. Since ChenWeb is moving toward billing
customers for usage, an unattributed run is a real problem, not just noise in the
logs.

The fix makes this a hard rule everywhere a document-processing run can start: if
there's no identifiable owner, the run does not happen. Instead, an alarm is raised
so an operator can see and fix the underlying cause (usually: a document was never
assigned to a customer/tenant in the first place).

## Details

### The concept: `user_id` on every doc-processing event

Every event that starts a document-processing pipeline run (`kb.pdf.start-doc-processing`,
`kb.line-file-generated`) carries a `user_id` string field. `ControlService.handleEvent`
(`server/api/doc-processing/control.go`) tags the run's `context.Context` with it via
`withLLMUserID`, and every LLM call made during that run threads it through to
`llm_usage_event.user_id` (see `shared/go/api/llm/usage_capture.go`). That's the only
identity LLM usage gets attributed to — there's no other mechanism.

Two kinds of trigger populate `user_id` differently:

- **Manual** (a person clicks something in the UI, or an admin calls the trigger API
  directly): `user_id` is the Kratos-authenticated caller's user id.
- **Automatic** (a PDF finishes OCR and processing starts on its own, no human in
  the loop at that moment): there is no session to pull an identity from. `user_id`
  is instead the **tenant** that owns the document (`kb.inputs.tenant_id`) — for
  billing purposes, attributing an automatic run's cost to the owning
  customer/tenant is the correct behavior, not a workaround.

### What was actually broken

1. **Automatic trigger never set it.** `fileconverters.Service.emitLineFileGeneratedEvent`
   (`server/api/file-converters/service.go`) — the function `parser-result-converter`
   calls right after OCR to kick off the real extraction pipeline — built its event
   payload with no `user_id` field at all. It also never read `kb.inputs.tenant_id`,
   so even if it had wanted to use it, the value was never fetched.
2. **`kb.inputs.tenant_id` itself was frequently unset.** Documents uploaded through
   the real upload API (`kbhandler.UploadInputs`) do get a real `tenant_id`, sourced
   from the active knowledge store on the frontend. But any document that entered
   `kb.inputs` some other way (a raw file dropped into the staging directory,
   an old/seeded test record) got the column's DB default, the literal string `"-"` —
   which is not NULL, so a naive "is it set" check would miss it.
3. **Manual trigger alarmed but still ran.** `jetstreamhandler.PublishEvent`
   (`server/api/jetstreamhandler/handler.go`) — the endpoint behind the UI's
   "reprocess" / "run doc processor" actions — already had code to raise an alarm
   when about to publish a trigger event with no `user_id`. But the alarm fired
   *after* the event was already published to JetStream, as a warning, and the run
   proceeded regardless. In practice this path is not expected to fire (a manual
   trigger should always have an authenticated caller), but nothing stopped it if it
   ever did.
4. **No backstop.** `ControlService.handleEvent`, the single place every trigger
   (however generated) ultimately passes through, did not check for a missing
   `user_id` at all — it just extracted whatever it was given and moved on.

### The fix

- **`file-converters/service.go`**: `InputRecord` (and `GetInputRecord`'s query) now
  carries `tenant_id`. `emitLineFileGeneratedEvent` stamps it onto the event's new
  `user_id` field. If `tenant_id` is empty or the default sentinel `"-"`, it does
  **not** publish the event — it raises an alarm and returns an error instead, which
  surfaces on the record's status as a failed "doc processing kickoff" and stops the
  automatic pipeline from ever starting.
- **`jetstreamhandler/handler.go`**: the missing-`user_id` check in `PublishEvent`
  now runs *before* `js.Publish`, and refuses with HTTP `403` instead of publishing.
  The alarm severity was raised from `warning` to `error` — reaching this now
  represents a bug (an authenticated request with no derivable user id), not an
  expected condition.
- **`doc-processing/control.go`**: `ControlService.handleEvent` now refuses to run
  (no processors invoked) if the event's `user_id` is still empty at the point a run
  would start. This is the backstop for anything that reaches processing without
  going through either of the two paths above — e.g. a raw NATS message published
  directly (bypassing every API-level guard), or any future trigger path that
  forgets to set `user_id`.

All three refusals raise the same alarm kind, `docprocessing.RoutingAlarmKindMissingUserID`
(constant `"missing_user_id"`), written to the shared `alarms_errors` table (the one
behind `/semos/admin/alarms`), with `severity = "error"`. Deduplication follows the
existing `RoutingAlarmSQLWriter` rules: keyed by `run_id` when a run row already
exists, otherwise by `record_id` — so a redelivered/retried event for the same
record doesn't spam duplicate alarm rows.

### Where to look

| Concern | Location |
|---|---|
| Context tagging / LLM call attribution | `withLLMUserID`, `llmUserIDFromContext` — `server/api/doc-processing/llm_capture_input.go` |
| Automatic-trigger fix + tenant lookup | `emitLineFileGeneratedEvent`, `InputRecord.TenantID` — `server/api/file-converters/service.go` |
| Manual-trigger fix | `PublishEvent`, `alarmForMissingUserID` — `server/api/jetstreamhandler/handler.go` |
| Universal backstop | `ControlService.handleEvent` — `server/api/doc-processing/control.go` |
| Alarm kind / dedup rules | `RoutingAlarmKindMissingUserID`, `RoutingAlarmSQLWriter.WriteAlarm` — `server/api/doc-processing/routing_alarm.go` |
| `kb.inputs.tenant_id` real source (manual upload) | `UploadInputs` — `server/api/kbhandler/upload_handler.go`; frontend sends the active knowledge store's `tenant_id`, not the uploading user's own id |

### Verified behavior (onto.bzton.cn, 2026-09-24)

Triggering `kb.pdf.start-doc-processing` directly via NATS (bypassing every API
guard) for a record whose `kb.inputs.tenant_id` is `"-"` produces:

```
ERROR doc processor refusing to run: event carries no user_id record_id="1"
INFO  finish processing request record_id="1" proc_status="failed"
```

and a persisted `alarms_errors` row (`kind=missing_user_id`, `severity=error`,
`record_id=1`). No processor ran, no LLM calls were made, no unattributed spend was
logged.

## Known limitations

- **`kb.inputs.tenant_id` is a knowledge-store-level identifier, not a person.** It
  is set from the active knowledge store's `tenant_id` at upload time (a
  organizational/customer concept), not from the uploading user's own identity. For
  automatic runs this is the intended design (bill the owning tenant), but it means
  `llm_usage_event.user_id` for an automatic run is not literally a Kratos user id —
  readers of that table should not assume it always identifies a person.
- **No backfill.** Historical `llm_usage_event` rows already written with an empty
  `user_id` are not touched by this change — they remain unattributed. This only
  prevents new unattributed rows going forward.
- **No repair tooling for `kb.inputs.tenant_id = '-'`.** Existing input records that
  predate this fix (seeded test data, documents dropped directly into staging
  outside the upload API) will keep failing automatic processing with the new alarm
  until someone manually sets a real `tenant_id` on them. There is currently no
  admin UI or script to bulk-fix these.
- **The manual-trigger and automatic-trigger refusal paths were verified via unit
  tests and code review, not a live reproduction on the box** (the manual path
  requires an authenticated-but-userless session, which isn't reachable through
  normal use; the automatic path requires a full real OCR run). Only the
  `ControlService.handleEvent` backstop was exercised live, described above.
