# ADR 2026062801 — Doc Processor Manual Launch: Run Mode Controls

**Date:** 2026-06-28  
**Status:** Accepted  
**Component:** ChenWeb — Doc Processor Dashboard (`doc-processor-dashboard-view.svelte`)  
**Tags:** doc-processor, manual-launch, run-mode, UX

---

## Change Logs

* 2026-06-28-01, ADR Created
* 2026-06-28-02, The run mode has four values. Three of them: `Run Unfinished Only`, `Run Failed Only`, and `Run Unfinished & Failed` does not have to go through the search. Do the following changes:
    - Move the toggle buttons and the input field, then a 'Launch' button in front of the 'Search' buttonn
    - The 'Force' button should be disabled unless one or more records are selected
    - The radio group defaults to `Run Failed Only`
    - The input field defaults to 5
    - Search is mainly used to manually search records.
    - If records are selected, it enables the `Force` option. 
    - Users can click 'Launch' without going through the Search. If no records are selected when pressing 'Launch', it will search records based on the selected value in the radio group, up to the max records. If no records are found, it should open a dialog to inform users. Otherwise, confirm the launch (the same as the existing code does) because actually launching it. If the selected records are not empty, the radio group selection applies to the selected records only and the input field update its value to the number of records selected. 

---

## Context

The Doc Processor Manual Launch panel (`/home3` → Doc Processor → Manual Launch) lets operators search for `kb.inputs` records, select which processing stages to run, and dispatch them via a `kb.line-file-generated` NATS JetStream event.

Before this change, clicking **Launch** dispatched **every selected record unconditionally** with `force: true`, causing two operational problems:

1. **Redundant reprocessing.** Records that had already completed all selected stages were re-queued unnecessarily — wasting compute and risking data inconsistency from duplicate writes.
2. **No throughput cap.** Selecting 50 records and clicking Launch dispatched all 50 simultaneously with no way to throttle the batch.

The existing "Select Failed" and "Select Incompleted" buttons only control *which processor checkboxes are ticked* — they don't filter *which records* are actually dispatched. There was no mechanism to filter records by their processing state at launch time.

---

## Decision

Add two new controls to the Manual Launch panel, placed in a dedicated row above the existing processor-selection footer buttons:

### 1. Run Mode — radio button group

Four mutually exclusive modes that determine which records from the current selection are eligible for dispatch:

| Label | Value | Default | Qualifying stage statuses |
|---|---|---|---|
| Run Unfinished Only | `unfinished` | — | `pending` or `in-progress` |
| Run Failed Only | `failed` | — | `failed` |
| Run Unfinished & Failed | `unfinished_failed` | ✓ | `pending`, `in-progress`, or `failed` |
| Force Run | `force` | — | (no filter — all records dispatched) |

A record qualifies if **at least one** of its relevant stages matches the condition. "Relevant stages" means only the stages corresponding to the currently-checked processor checkboxes — not all pipeline stages.

### 2. Max Records to Run — numeric input

Caps how many eligible records are dispatched in a single launch session. Default: **5**. The Launch button is disabled when the value is not a positive integer.

### 3. No-Eligible-Records dialog

When the run-mode filter produces zero eligible records, a modal dialog replaces the silent no-op. The dialog explains why nothing was launched and suggests switching to Force Run.

### force flag in event payload

The `force` field in the dispatched `kb.line-file-generated` payload is now tied to run mode:
- `force: true` only when mode is `force`
- `force: false` for all other modes (backend skips already-succeeded operations naturally)

---

## Implementation

**File:** `ChenWeb/web/src/lib/components/home3/doc-processor-dashboard-view.svelte`

### New state variables

```typescript
type RunMode = 'unfinished' | 'failed' | 'unfinished_failed' | 'force';
let runMode = $state<RunMode>('unfinished_failed');
let maxRecords = $state<number>(5);
let noEligibleDialog = $state<{ recordCount: number; modeLabel: string } | null>(null);
```

### filterByRunMode helper

```typescript
function filterByRunMode(
    records: KbInputRecord[],
    mode: RunMode,
    selectedStageIds: Set<string>
): KbInputRecord[] {
    if (mode === 'force') return records;
    return records.filter((rec) => {
        const relevantStages = computeStages(rec).filter((s) => selectedStageIds.has(s.id));
        return relevantStages.some((s) => {
            if (mode === 'unfinished') return s.status === 'pending' || s.status === 'in-progress';
            if (mode === 'failed') return s.status === 'failed';
            return s.status === 'pending' || s.status === 'in-progress' || s.status === 'failed';
        });
    });
}
```

### confirmLaunch changes

```typescript
const selectedStageIds = new Set<string>([
    ...(parseFileChecked ? ['parsing'] : []),
    ...(convertChecked ? ['converting'] : []),
    ...selectableProcessorIds.filter((p) => processors[p])
]);
const eligible = filterByRunMode(selectedRecords, runMode, selectedStageIds).slice(0, maxRecords);
showConfirm = false;
if (eligible.length === 0) {
    noEligibleDialog = { recordCount: selectedRecords.length, modeLabel };
    return;
}
// ... dispatch eligible records
```

### doLaunch change

```typescript
// was: force: true
const payload = { record_id: String(record.id), force: runMode === 'force' };
```

### UI placement

The run-mode radio group and Max Records input occupy a new `flex flex-wrap` row inserted **above** the existing "Select all / Select Failed / Select Incompleted / Launch" row. The Max Records input is right-aligned within the same row.

---

## Key Technical Decision: Scope of stage filtering

**Problem encountered during implementation:** An initial version of `filterByRunMode` called `computeStages(rec).some(...)` across all pipeline stages. `computeStages()` returns `status: 'pending'` for any stage that has no history entry — including optional processors the server has never run (e.g. `generate_summaries`, `generate_topics`). This meant every record always had at least one "pending" stage, and the filter never excluded anything.

**Fix:** The filter is scoped to `selectedStageIds` — the set of stage IDs corresponding to the checkboxes the operator has actually ticked. A fully-processed record whose checked processors are all at `success` now correctly produces zero qualifying stages and is excluded from the dispatch.

**Implication:** Run mode operates on the intersection of "what the operator selected to run" and "what the record still needs" — not on the record's global pipeline state. This is the intended behaviour: run mode and the processor checkboxes are independent axes that compose.

---

## Alternatives Considered

| Alternative | Reason rejected |
|---|---|
| Filter records on the server (a new API endpoint) | All status data is already loaded in `selectedRecords`; a round-trip adds latency with no benefit. Frontend-only is sufficient. |
| Show the "nothing to launch" result as a toast | Toasts are easy to overlook. In validation scenarios where the operator needs to take a corrective action (switch mode or add records), a blocking modal dialog ensures they see the message. |
| Put run-mode filtering inside `doLaunch()` | `doLaunch()` handles one record at a time and is reused by the per-record Restart flow. Keeping run-mode logic in `confirmLaunch()` leaves Restart unaffected and keeps the single-record helper clean. |
| Persist run mode and max-records in localStorage | The defaults (`unfinished_failed`, 5) are safe for all use cases. Persisting adds complexity and the risk of surprising an operator who forgot what they set previously. |

---

## Operational Behaviors

- Default mode (`Run Unfinished & Failed`) is the safe automatic choice: it skips fully-completed records and re-runs anything that didn't finish or failed.
- `Force Run` is equivalent to the previous unconditional behaviour, but now requires an explicit selection to avoid accidents.
- Max Records = 5 default prevents accidental bulk dispatches. Operators processing large backlogs must explicitly raise the cap.
- The "nothing to launch" dialog tells the operator exactly which mode is active and suggests Force Run as the escape hatch, avoiding confusion when all selected records are already complete.

---

## Consequences

- Operators can safely click Launch on a large selection without risk of re-running already-completed records.
- The `force: true` payload field, previously hardcoded, now accurately reflects operator intent. Backend processors that respect `force: false` will skip already-succeeded operations, reducing redundant writes.
- `computeStages()` is now relied on in four places (active-pipeline visualisation, `getDefaultRestartProcessors`, `selectFailedProcessors` / `selectIncompletedProcessors`, and `filterByRunMode`). Future changes to `StageStatus` values or `computeStages` semantics will affect all of them.
- No backend, API, or database changes.

---

## References

- [ADR 2026061202](2026061202-adr-manual-start-ui.md) — Manual Launch: Select Failed & Select Incompleted Processor Buttons (predecessor feature)
- `ChenWeb/web/src/lib/components/home3/doc-processor-dashboard-view.svelte` — all changes in this file
- `ChenWeb/web/src/lib/components/home3/doc-processor-dashboard-state.ts` — `computeStages()`, `StageStatus`, `StageInfo` types
- `ChenWeb/openspec/changes/doc-processor-run-mode-controls/` — proposal, design, specs, and tasks for this change
