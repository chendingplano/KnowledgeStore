# Off-Peak-Only Auto Processing — defer LLM document processing out of peak hours

**Date:** 2026-09-28 \
**Scope:** What the "Auto - off-peak only" upload option does, how the document processor
holds and resumes work around peak hours, where the code lives, and what it does not do.
**Code root:** `ChenWeb/server/api/doc-processing/offpeak_gate.go`

**Traceability — openspec:**
- `ChenWeb/openspec/changes/offpeak-only-auto-processing/proposal.md` — why this exists
  (moves to `changes/archive/` once archived)
- `ChenWeb/openspec/changes/offpeak-only-auto-processing/design.md` — rationale,
  alternatives considered, risks/trade-offs
- `ChenWeb/openspec/changes/offpeak-only-auto-processing/tasks.md` — implementation log
- `ChenWeb/openspec/specs/offpeak-doc-processing/spec.md` (after archive; until then
  `changes/offpeak-only-auto-processing/specs/offpeak-doc-processing/spec.md`) — the
  canonical requirements. **Update this spec file, not just this doc, if behavior
  changes** — this doc explains the feature for humans and points at code; the spec is the
  contract for agents.

## Summary

Most of the work done on an uploaded document — summaries, topics, metrics, entities and so
on — is done by an AI language model, mainly DeepSeek. DeepSeek is more expensive and less
available during its peak hours (Beijing time 9:00–12:00 and 14:00–18:00 on Chinese working
days).

Uploads now have a processing option called **"Auto - off-peak only"**, and it is the
default. A document uploaded this way is stored and parsed right away, exactly as with plain
"Auto". But whenever the processor is about to start a step that uses an AI model, it first
checks the clock. If peak hours are on, or will start within the next 10 minutes, the
document waits. It picks up again, on its own, once peak hours are over. Nobody has to come
back and restart it.

While a document waits, its current step shows as *active* with the note "held: waiting for
off-peak hours (deepseek peak hours)". The usual Stop button still works on a waiting
document. A waiting document also gives up its place in the processing queue, so a document
uploaded with plain "Auto" (meaning "process now, whatever the time") is not stuck behind
it.

Which hours count as "peak" is not hard-coded. It is the **Peak Hours** record named
`deepseek peak hours`, edited under *System Admin → System → Peak Hours*, together with the
holiday calendar (*System Admin → System → Calendar*). Edits take effect within about 30
seconds, without a restart.

This change also fixed a mistake in how peak hours were worked out. "Adjusted working days"
(for example Sunday 2026-01-04, a CN working day that makes up for the New Year holiday)
had been treated as holidays, so they counted as off-peak. They now count as ordinary
working days.

## Where things live

- **Upload page:** `/home3` → Knowledge → File Management → Upload Files, the "Auto Process"
  dropdown next to the refresh selector. The Pending Files dialog has the same dropdown.
  Code: `ChenWeb/web/src/lib/components/home3/kb-import-view.svelte`,
  `ChenWeb/web/src/lib/services/kbService.ts`.
- **Stored value:** `kb.inputs.processing_mode = 'auto_offpeak'`. Migration
  `ChenWeb/project_migrations/20260928000005_add_auto_offpeak_processing_mode.sql`. The
  upload API accepts it in `server/api/kbhandler/upload_handler.go`. A zip's files inherit
  the mode.
- **Hold/resume logic:** `server/api/doc-processing/offpeak_gate.go` (`OffPeakGate`, the
  pipeline-slot lease, `holdForOffPeak`). It is called from `runSingleProcessorCollect`
  and before Phase C in `control.go`, and at the start of the chunk-batch path in
  `chunk_batch_coordinator.go`. It is wired up in `runtime.go`.
- **Peak evaluation:** `server/api/peakhourshandler/evaluate.go`, see
  `2026092402-devdoc-peak-hours-admin.md`.
- **Settings** (doc-processor environment, all optional):

  | Variable | Default | Meaning |
  |---|---|---|
  | `DOC_PROCESS_OFFPEAK_PEAK_HOURS_NAME` | `deepseek peak hours` | Which Peak Hours record defines "peak" |
  | `DOC_PROCESS_OFFPEAK_LEAD_MINUTES` | `10` | How early before peak to stop starting new steps |
  | `DOC_PROCESS_OFFPEAK_POLL_SEC` | `30` | How often a waiting document re-checks |

## Known limitations

- **A step that already started is not paused.** Holding happens *between* steps. A long
  step that starts just before the 10-minute margin can run into peak hours. Raise
  `DOC_PROCESS_OFFPEAK_LEAD_MINUTES` if that happens too often.
- **Almost every step counts as AI work.** Only the first, purely mechanical "blocking"
  step runs during peak. Even structure analysis and chunking make AI calls, so they wait
  too.
- **It holds for one window, whatever model a step uses.** A step configured with a model
  that has no peak pricing still waits.
- **A missing or broken Peak Hours record means no holding.** If the named record doesn't
  exist or can't be evaluated, documents run immediately and a warning is logged. This
  avoids silently stalling every upload over a misconfiguration.
- **Waiting lives in memory.** If the doc-processor restarts while documents are waiting,
  they are recovered the same way as documents that were mid-run, not by this feature.
- **Uploads without a mode are still plain "Auto".** Only the web page's default changed.
  An API call that leaves `processing_mode` empty still gets `auto`.

## Verification status (2026-09-28)

`go build`/`go vet` pass. New unit tests in `offpeak_gate_test.go` cover: caching,
fail-open, waiting and resuming, stop while held, slot release and re-acquire, and no hold
for plain `auto` or the blocking step. New peak-hours tests cover adjusted working days.
`go test` passes for `doc-processing` and `peakhourshandler`. `kbhandler` has 11 failing
tests (auth-related). They fail the same way without this change. The migration was applied
to `miner` by the live server, and Down→Up was checked in a rolled-back transaction.
`svelte-check` reports no errors in the touched files.

**Not yet verified:** an end-to-end run with a real upload during peak hours, and a
click-through of the dropdown in a logged-in browser.
