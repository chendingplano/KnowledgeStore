# Peak-Hour Control for Document Processing — run AI work in peak or off-peak hours

**Date:** 2026-09-28 (rewritten 2026-11-02 for engine-wide peak-hour control) \
**Scope:** When the document processor does its AI work relative to DeepSeek's peak hours: the
processor-wide setting, the per-document "Auto - off-peak only" upload option, what happens to
work that is running when peak hours start or end, and where the code lives.
**Code root:** `ChenWeb/server/api/doc-processing/task_engine_policy.go`
**Status:** Implemented 2026-11-02. Automated tests pass; a live run across a real peak boundary
has not been observed yet (see "Verification").

**Traceability — openspec:**
- `ChenWeb/openspec/changes/doc-processor-peak-controls/proposal.md`, `design.md`, `tasks.md` —
  the processor-wide control, why it replaced the old per-step hold, alternatives and risks
  (moves to `changes/archive/` once archived)
- `ChenWeb/openspec/changes/archive/2026-11-02-offpeak-only-auto-processing/` — the original
  "Auto - off-peak only" upload option
- `ChenWeb/openspec/changes/doc-processor-peak-controls/specs/doc-processor-peak-controls/spec.md`
  (after archive: `ChenWeb/openspec/specs/doc-processor-peak-controls/spec.md`) and
  `ChenWeb/openspec/specs/offpeak-doc-processing/spec.md` — the canonical requirements.
  **Update these spec files, not just this doc, if behavior changes** — this doc explains the
  feature for humans and points at code; the specs are the contract for agents.
- Requirements and hand-off: `KnowledgeStore/doc-repo/hand-offs/202611/2026110201-hand-offs-doc-processor-peak-controls.md`

## Summary

Most of the work done on an uploaded document — summaries, topics, metrics, entities and so on —
is done by an AI language model, mainly DeepSeek. DeepSeek costs more and is less available
during its peak hours (Beijing time 9:00–12:00 and 14:00–18:00 on Chinese working days).

The document processor can now be told **when** to work. There are three settings:

- **none** — work at any time. This is the default.
- **off-peak only** — work only outside peak hours.
- **peak only** — work only during peak hours.

One setting applies to the whole document processor. A document can also carry its own setting,
and when it does, that wins. Today the only way a document gets its own setting is the upload
option **"Auto - off-peak only"** (still the default choice on the upload page): such a document
is always treated as off-peak only, even if the processor-wide setting is "none". A document
uploaded as plain **"Auto"** follows the processor-wide setting.

**A document that arrives at the wrong time waits** before doing anything at all. While it waits
it shows as running with the note "waiting for off-peak hours (deepseek peak hours)" (or "waiting
for peak hours …"). It gives up its place in the processing queue so other documents are not stuck
behind it. The Stop button still works. It starts on its own when its allowed time comes.

**A second setting decides what happens to a document that is already being processed when the
time changes** (for example, an off-peak-only document still running at 9:00):

- **continue** (the default) — it simply finishes.
- **pause AI calls** — it keeps going until its next request to an AI model, then waits until its
  allowed time returns. A request already sent to the model is allowed to finish. Each pause and
  each resume is written to the processor's log and appears in the LLM usage lists as "LLM call
  held (peak-hour control)" and "Held LLM call resumed" (or "Held LLM call cancelled" if the
  document was stopped while paused). These entries are bookkeeping only: they are not counted as
  requests, tokens or cost in any usage report.
- **abort** — the document's processing is stopped. It shows as stopped with "aborted at
  peak-hour boundary" and does not restart by itself; someone has to run it again.

Which hours count as "peak" is not hard-coded. It is the **Peak Hours** record named
`deepseek peak hours`, edited under *System Admin → System → Peak Hours*, together with the holiday
calendar (*System Admin → System → Calendar*). Edits take effect within about 30 seconds without a
restart. "Adjusted working days" (for example Sunday 2026-01-04, a Chinese working day that makes
up for the New Year holiday) count as ordinary working days.

## How to configure

The settings live in `ChenWeb/config.toml`, and can be overridden for one machine in the
uncommitted `config.local.toml` beside it:

```toml
[[task-engines.doc-processor]]
default_mode = "none"        # none | auto_peak | auto_offpeak
cross_peak_mode = "ignore"   # ignore | pause-llm | abort
```

`ignore`, `pause-llm` and `abort` are the "continue", "pause AI calls" and "abort" choices above.
There may be only one such entry; an unknown value (including `pause-exec`, which is not
supported) stops the document processor from starting, with the error in its log. Restart the
document processor after changing these settings.

Optional environment settings of the document processor:

| Variable | Default | Meaning |
|---|---|---|
| `DOC_PROCESS_OFFPEAK_PEAK_HOURS_NAME` | `deepseek peak hours` | Which Peak Hours record defines "peak" |
| `DOC_PROCESS_OFFPEAK_POLL_SEC` | `30` | How often waiting or running work re-checks the clock |

## Where things live

- **Upload option:** `/home3` → Knowledge → File Management → Upload Files, the "Auto Process"
  dropdown (also in the Pending Files dialog). Code: `ChenWeb/web/src/lib/components/home3/kb-import-view.svelte`,
  `ChenWeb/web/src/lib/services/kbService.ts`. Stored as `kb.inputs.processing_mode = 'auto_offpeak'`.
- **Settings:** `ChenWeb/server/cmd/config/task_engine.go`.
- **The control itself** — choosing a document's setting, waiting, abort, pausing AI calls, the
  pause/resume records: `ChenWeb/server/api/doc-processing/task_engine_policy.go`, called from
  `handleEvent` in `control.go` and set up in `runtime.go`.
- **Peak-hours check and queue-place handling:** `ChenWeb/server/api/doc-processing/peak_window.go`;
  the peak rules themselves are in `ChenWeb/server/api/peakhourshandler/evaluate.go` (see
  `2026092402-devdoc-peak-hours-admin.md`).
- **Pausing AI requests:** the shared library's request gate, `shared/go/api/llm/request_gate.go`.
  Every request the shared AI clients send — text, structured output, embeddings, each retry —
  passes through it.
- **Pause/resume records:** `public.llm_usage_event.event_kind` (`request`, `llm_hold`,
  `llm_resume`, `llm_hold_cancelled`; migration `ChenWeb/project_migrations/20261102000001_add_llm_usage_event_kind.sql`).
  A pair shares `metadata_json.hold_id`; the closing row has `held_ms`. Usage reports count only
  `request` rows (`ChenWeb/server/api/llmreporthandler/store.go`).
- **Log:** the document processor's own log (logger `CWB_DOCPROC_001`). Look for "task waiting
  for its permitted peak-hour span", "task starts after peak-hour wait", "aborting task at
  peak-hour boundary", "llm call held …", "held llm call resumed" / "cancelled".

## Known limitations

- **Waiting and paused work lives in memory.** If the document processor restarts, that work is
  lost and the document keeps showing "running" with its waiting note. Stop it and run it again.
- **No early stop before peak.** With "continue", a document that starts at 8:59 runs into peak
  hours. (The old 10-minute look-ahead was removed; use "pause AI calls" or "abort" instead.)
- **One peak window for every model.** Pausing holds every AI request, including local embedding
  models that have no peak pricing.
- **A request already sent is not interrupted by a pause.** "Abort" does cancel it, and the
  provider may still charge for it.
- **Abort and resume are not instant.** They are noticed at the next check, up to 30 seconds by
  default.
- **A pause can outlast a caller's own time limit.** No document-processing step puts its own
  time limit around an AI request today; one added later would give up when paused too long.
- **Only document processing is controlled.** Document reviews, search and other features that
  call AI models are not held, even when they run in the same program.
- **A missing or broken Peak Hours record means no holding at all.** Every document runs at once
  and a warning is logged, rather than silently stalling everything.
- **Time spent paused counts towards a processor's run time** in its status and logs.
- **Automatically launched work cannot yet carry its own setting**; only the upload option can.
  An API upload that leaves the processing mode empty is plain "Auto" and follows the
  processor-wide setting.

## Verification (2026-11-02)

- Automated tests: shared `go test ./...` passes; ChenWeb `doc-processing`, `llmusage`,
  `llmreporthandler` and `cmd/config` pass, with the new peak-control tests also clean under the
  race detector. They cover both directions, mode `none`, stop while waiting, slot release and
  re-check, abort during a processor and during post-processing, and pausing a real
  `OpenAIJSONClient` request against a test server (paired rows, stop while paused, failed row
  write). The one failing `doc-processing` test, `TestKBMetricsReadersExcludeResolvedRows`,
  flags `kbhandler/question_generator_worker.go`, which this work does not touch.
- Settings read through the real start-up path: `config.toml` defaults overridden by the local
  file gave `auto_offpeak` / `ignore`.
- The `event_kind` migration was applied to `miner` by the running server; undo/redo was checked in
  a rolled-back transaction; the database rejects unknown kinds.
- The real `deepseek peak hours` record evaluated as expected (Tuesday 10:00 Beijing: peak;
  13:00, 20:00 and Saturday: not peak).
- **Not yet verified:** a live document processed across a real peak boundary, pause/resume rows
  written by a live run, and the new labels viewed in a logged-in browser.
