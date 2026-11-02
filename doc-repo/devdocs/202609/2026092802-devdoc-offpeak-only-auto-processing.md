# Off-Peak-Only Auto Processing — defer LLM document processing out of peak hours

**Date:** 2026-09-28 \
**Scope:** What the "Auto - off-peak only" upload option does, how the document processor
holds and resumes work around peak hours, where the code lives, and what it does not do.
**Code root:** `ChenWeb/server/api/doc-processing/offpeak_gate.go`  
**Review date:** 2026-11-02  
**Status:** The existing off-peak gate is implemented in part; the broader task-engine requirements below are not fully implemented.

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

## Tasks, engines and requested behavior

A **task** is a unit of work; a **task engine** executes tasks of its supported kind.
The currently identified task and engine are:

| Task | Purpose | Task engine |
|---|---|---|
| `doc-processor` | Process documents, including artifact extraction | `ChenWeb/server/cmd/doc-processor` |

The following is the **requested target behavior**, not a description of functionality
already shipped. It extends beyond the original OpenSpec change linked above. That change
remains the contract for its existing scope; a new or updated OpenSpec contract is needed
before the broader behavior can be considered specified and implemented.

### Peak-hour mode

The `doc-processor` task engine must support `peak-hour-mode` with these values:

| Value | Required behavior |
|---|---|
| `none` | Disable peak-hour control; this is the default. |
| `auto_peak` | Work only during peak hours. |
| `auto_offpeak` | Work only during off-peak hours. |

A task waiting because its engine's mode does not allow execution must start or resume
when its permitted time span returns. The existing upload `processing_mode = auto_offpeak`
is a per-document setting and must not be confused with the requested engine mode.
The requested default `none` disables peak-hour control, including the existing gate.

### Crossing a peak boundary

The doc-processor must support a `cross-peak-boundary` rule governing active tasks as time
changes between peak and off-peak. Its values are:

| Value | Required behavior |
|---|---|
| `ignore` | Continue all active tasks; this is the default. |
| `pause-exec` | Pause execution of all active tasks. |
| `pause-llm` | Continue each active task until it issues an LLM call; hold that call until the time span changes. |
| `abort` | Abort all active tasks. |

The mode determines the permitted span; these rules govern active work crossing a
boundary, and held work resumes when its permitted span returns. An LLM call already in
flight when a boundary is crossed is not explicitly covered by the request. The exact
pause mechanism, persistence and recovery, configuration scope, and how boundary rules
interact with `none` and existing per-document modes require a formal design. In
particular, the existing ten-minute lead time is not the same as a boundary transition.

### Required activity logging

- The doc-processor task engine has its own log.
- Log when a task waits due to peak-hour controls and when a held task starts or resumes.
- When an LLM call is held, write an entry to both the task engine log and
  `public.llm_usage_event`; write an entry to both again when that call resumes.

The event representation, correlation identifiers, and behavior if either log write fails
are not yet specified. The current usage sink records LLM usage; it does not establish
these hold/resume events.

## Implementation review (2026-11-02)

The broader requirements are **not fully implemented**. This is a source review, not an
end-to-end execution or deployment audit.

| Requirement | Current evidence and gap |
|---|---|
| Task and engine | `doc-processor` is the only task engine in scope. |
| Engine peak-hour modes | `doc-processor` has a per-input `auto_offpeak` gate for selected processing steps. No engine-wide `none` / `auto_peak` / `auto_offpeak` control was found in the document-processing gate. |
| Boundary rules | No `cross-peak-boundary` configuration or `pause-exec`, `pause-llm`, or `abort` boundary handling was found. An already-started processor continues; this resembles `ignore` for that step, but is not the requested configurable engine-wide rule. |
| Task wait/resume logging | The existing doc-processor gate logs hold and resume and records held progress. Engine-wide coverage for all tasks is not established. |
| Engine logs | The doc-processor initializes a named logger; its log destination and isolation were not verified. |
| LLM hold/resume events | The gate holds before selected processors, not at each LLM call, and its hold/resume path does not write events to `public.llm_usage_event`. Both required paired events remain unimplemented. |

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
- **The gate operates at processor boundaries.** It uses its own classification of which
  processors need a hold, rather than intercepting individual LLM calls; some local work
  can run without waiting.
- **It holds for one window, whatever model a step uses.** A step configured with a model
  that has no peak pricing still waits.
- **A missing or broken Peak Hours record means no holding.** If the named record doesn't
  exist or can't be evaluated, documents run immediately and a warning is logged. This
  avoids silently stalling every upload over a misconfiguration.
- **Waiting lives in memory.** If the doc-processor restarts while documents are waiting,
  they are recovered the same way as documents that were mid-run, not by this feature.
- **Uploads without a mode are still plain "Auto".** Only the web page's default changed.
  An API call that leaves `processing_mode` empty still gets `auto`.

## Original verification status (2026-09-28)

`go build`/`go vet` pass. New unit tests in `offpeak_gate_test.go` cover: caching,
fail-open, waiting and resuming, stop while held, slot release and re-acquire, and no hold
for plain `auto` or the blocking step. New peak-hours tests cover adjusted working days.
`go test` passes for `doc-processing` and `peakhourshandler`. `kbhandler` has 11 failing
tests (auth-related). They fail the same way without this change. The migration was applied
to `miner` by the live server, and Down→Up was checked in a rolled-back transaction.
`svelte-check` reports no errors in the touched files.

**Not yet verified:** an end-to-end run with a real upload during peak hours, and a
click-through of the dropdown in a logged-in browser.
