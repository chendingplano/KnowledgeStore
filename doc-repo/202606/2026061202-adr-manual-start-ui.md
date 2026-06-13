# ADR 2026061202 — Manual Launch: Select Failed & Select Incompleted Processor Buttons

**Date:** 2026-06-12  
**Status:** Accepted  
**Component:** ChenWeb — Doc Processor Dashboard (`doc-processor-dashboard-view.svelte`)

---

## Context

The Manual Launch section of the Doc Processor Dashboard allows operators to select one or more `kb.inputs` records and re-run specific processing stages. Previously, after selecting records, the operator had to manually inspect each record's stage statuses and then tick the relevant processor checkboxes — a multi-step, error-prone workflow when recovering from batch failures or partial pipeline runs.

Two common recovery patterns repeat frequently:

1. **Re-run only the failed stages** — After a batch failure, operators want to retry only the stages that reported `failed` status, not re-run the entire pipeline.
2. **Re-run all incomplete stages** — When a record stalled mid-pipeline (e.g. due to a transient error that was then resolved), operators want to resume from the first incomplete stage rather than the first failed one.

There was no shortcut for either pattern; the processor checklist had to be configured manually each time.

---

## Decision

Add two new buttons to the processor selection footer in the Manual Launch section, placed alongside the existing **Select all / Deselect all** toggle:

### "Select Failed"
Iterates over all currently selected records, calls `computeStages(rec)` for each, and collects every processor `id` whose `StageStatus` is `'failed'`. Sets `processors` to `true` for exactly those IDs and `false` for all others.

### "Select Incompleted"
Same traversal but collects every processor whose `StageStatus` is **not** `'success'` (covers `'failed'`, `'in-progress'`, and `'pending'`). This selects every stage that has not yet finished successfully, enabling a clean resume from any point in the pipeline.

For both buttons, the union across all selected records is used — if _any_ selected record has a matching stage, the corresponding processor is enabled. This ensures that in a multi-record batch, no record's partially complete state is silently skipped.

If no qualifying stages are found (e.g. all stages succeeded), the button is a no-op, leaving the current checkbox state unchanged.

---

## Implementation

**File:** `ChenWeb/web/src/lib/components/home3/doc-processor-dashboard-view.svelte`

Two pure synchronous functions added to the script block:

```typescript
function selectFailedProcessors() {
    const failedIds = new Set<string>();
    for (const rec of selectedRecords) {
        for (const stage of computeStages(rec)) {
            if (stage.status === 'failed' && ALL_PROCESSOR_IDS.includes(stage.id)) {
                failedIds.add(stage.id);
            }
        }
    }
    if (failedIds.size === 0) return;
    processors = Object.fromEntries(ALL_PROCESSOR_IDS.map((p) => [p, failedIds.has(p)]));
}

function selectIncompletedProcessors() {
    const incompleteIds = new Set<string>();
    for (const rec of selectedRecords) {
        for (const stage of computeStages(rec)) {
            if (stage.status !== 'success' && ALL_PROCESSOR_IDS.includes(stage.id)) {
                incompleteIds.add(stage.id);
            }
        }
    }
    if (incompleteIds.size === 0) return;
    processors = Object.fromEntries(ALL_PROCESSOR_IDS.map((p) => [p, incompleteIds.has(p)]));
}
```

The `computeStages` function (imported from `doc-processor-dashboard-state`) is already used in the active-pipelines visualisation and in `getDefaultRestartProcessors`; reusing it here keeps the stage-status derivation consistent across the whole dashboard.

The "Select all / Deselect all" button, "Select Failed", and "Select Incompleted" are grouped in a `flex gap-2` container on the left side of the processor footer row, keeping the **Launch** button anchored to the right.

Visual treatment:
- **Select Failed** — error tint background (`colorErrorTint`) with error-colour border and text, to signal it targets fault states.
- **Select Incompleted** — accent tint background (`accentTint`) with accent border and text, matching the pipeline's in-progress colour palette.

---

## Alternatives Considered

| Alternative | Reason rejected |
|---|---|
| Fetch failed/incomplete records from the API and add them to `selectedRecords` | The buttons are in the _processor_ selection panel, not the _record_ selection panel. Mixing concerns would confuse the UX model. |
| Disable buttons when no records are selected | Simpler to make them no-ops; disabling would require derived state and adds visual noise before any record is chosen. |
| Separate "Select Failed" per record (in the chip list) | Too granular; the existing Restart dialog already provides per-record selective processor re-runs. The new buttons serve the _batch_ workflow. |

---

## Consequences

- Operators can recover failed batch runs in two clicks (select records → Select Failed → Launch) instead of manually inspecting each record's stage grid.
- The "Select Incompleted" button doubles as a safe "resume" action: it skips already-succeeded stages and re-queues everything else, reducing the risk of redundant reprocessing.
- No API changes required; the feature is entirely client-side, derived from status data already present in `KbInputRecord.status`.
- The `computeStages` function is now relied on in three places; any future changes to its return type or `StageStatus` values will affect this feature.
