# ChenWeb Development dashboard's manual "Launch" discards checked processor boxes whenever the package selector is on "Default"

Date: 2026-09-21

Status: fixed in the working tree, unit-tested, not committed, not verified against a live
manual run.

Scope: `ChenWeb/web/src/lib/components/home3/doc-processor-dashboard-state.ts`
(`buildManualLaunchPayload`) and its test file
`doc-processor-dashboard-state.test.ts`. Backend
`ChenWeb/server/api/doc-processing/control.go` (`resolveProductionPlanFacts`,
`defaultProcessorNames`) was read but not changed — it behaved correctly given the payload
it received.

Code read: `doc-processor-dashboard-view.svelte` (`selectedProcessorPackage` state,
`processorSelectionForPackage` call on package-dropdown change, the `Launch` button handler
building `chosen`/`payload` around line 477), `doc-processor-dashboard-state.ts`
(`buildManualLaunchOperations`, `processorSelectionForPackage`, `buildManualLaunchPayload`),
`control.go` lines ~1600-1653 (`resolveProductionPlanFacts`, `defaultProcessorNames`),
`runtime.go`/`config.go` (`DefaultProcessors` sourced from `config.local.toml`'s
`[doc-processing] default_processors = ["extract_metrics", "extract_products"]`).

Evidence: user manually launched doc-processing on record #416 with only the
`extract_doc_metadata` checkbox checked (plus the always-on mandatory ones) and Force Run
mode. The backend ran `extract_metrics` and `extract_products` in addition to
`extract_doc_metadata`, per the screenshot of the record's processing history — those two
were never checked in the UI.

Related: none yet — first doc on this topic.

---

## 1. Summary

The "Processors to Run" checkboxes on the Development → Doc Processor manual launch panel
have no effect whenever the "Select Processors" package dropdown is left on its default
value, "Default". In that state the frontend sends no `operation` field at all, so the
backend falls back to its own configured default processor set
(`default_processors = ["extract_metrics", "extract_products"]` in `config.local.toml`,
plus `extract_doc_metadata` appended unconditionally) — silently overriding whatever the
user actually checked.

## 2. Root cause

Two things compound:

1. **UI state disconnect**: `selectedProcessorPackage` (the package dropdown) and
   `processors` (the per-checkbox map) are independent Svelte state. Changing the package
   dropdown resets `processors` via `processorSelectionForPackage`, but toggling an
   individual checkbox does **not** move `selectedProcessorPackage` off `'Default'`. So a
   user can check/uncheck boxes freely while the dropdown silently stays on "Default".
2. **Payload gating on the dropdown, not the checkboxes**: `buildManualLaunchPayload`
   (`doc-processor-dashboard-state.ts:181-195`) only attached the computed `operation` list
   to the payload when `packageName.trim().toLowerCase() !== 'default'`:
   ```ts
   if (packageName.trim().toLowerCase() !== 'default') payload.operation = operations;
   ```
   This was a deliberate sentinel — confirmed by a pre-existing unit test asserting
   `'Default'` launches omit `operation` "to exercise automatic processing" — meant to let a
   user pick "Default" and defer entirely to the backend's own default processor set. But
   because checkbox edits never changed `selectedProcessorPackage` away from `'Default'`,
   this sentinel fired even when the user had explicitly customized the checkbox
   selection, discarding it with no UI feedback.
3. **Backend's default-fallback then filled in unrelated processors**:
   `control.go`'s `resolveProductionPlanFacts` treats an empty/absent `operation` list as
   "use configured defaults":
   ```go
   requested := append([]string(nil), evt.Operations...)
   if len(requested) == 0 && s != nil {
       requested = s.defaultProcessorNames()
   }
   ```
   and `defaultProcessorNames()` reads `config.local.toml`'s
   `default_processors = ["extract_metrics", "extract_products"]`, appending
   `extract_doc_metadata` if absent — producing exactly
   `["extract_metrics", "extract_products", "extract_doc_metadata"]`, matching the
   symptom.

## 3. Blast radius

Any manual launch from the Development dashboard performed while the package dropdown is
on "Default" (its state on every page load) silently ignored the user's checkbox
selections and ran `extract_metrics` + `extract_products` instead — regardless of what, if
anything, was checked. This affects every manual/force-run launch through this UI to date;
scope is limited to this one admin/dev panel, not the automated doc-processing pipeline
(NATS/JetStream triggers go through a different path unaffected by this bug).

## 4. Fix implemented (uncommitted)

Removed the package-name gate entirely — `buildManualLaunchPayload` now always sends the
explicit `operation` list computed from the checked boxes, for every package including
"Default":

```ts
const payload: Record<string, unknown> = {
	record_id: String(recordId),
	force,
	force_clear: forceClear,
	operation: operations
};
return payload;
```

This was a deliberate choice among two options discussed with the user: (a) always send
checked boxes — chosen, since it makes the UI's visible checkbox state authoritative in
every case, or (b) keep the "Default = let backend auto-pick" sentinel and instead fix the
UI so toggling a checkbox flips the dropdown to a synthetic "Custom" package. The simpler,
more predictable option (a) was selected; it removes the "defer entirely to backend
defaults via the Default dropdown" capability, which was judged not worth preserving
against the cost of the silent-discard footgun.

The now-contradicted unit test (`'Default package launch omits operation to exercise
automatic processing'`) was updated to assert the new behavior — a "Default" launch with
`extract_metrics` checked now sends `operation: ['extract_metrics']` — rather than removed,
since it documents this exact payload-shape contract.

Verification done this session: `bun test
src/lib/components/home3/doc-processor-dashboard-state.test.ts` — 27/27 pass, no
regressions.

## 5. Tasks

- [x] Root-cause the discrepancy between checked boxes and processors actually run
- [x] Implement fix in `buildManualLaunchPayload`
- [x] Update the unit test that had encoded the old (buggy) behavior
- [x] `bun test` clean for the touched test file
- [ ] Commit the change via `jj`
- [ ] Live verification: re-run a manual launch on a record with only
      `extract_doc_metadata` checked and confirm `extract_metrics`/`extract_products` do
      not run
- [ ] Consider whether `packageName` — now unused for gating logic inside
      `buildManualLaunchPayload` but still passed by its one caller
      (`doc-processor-dashboard-view.svelte:478`) — should be dropped from the function
      signature; left alone this session per the "surgical changes" convention, since
      removing it wasn't necessary to fix the bug

## 6. Open questions / future related activities

- The "Default" package dropdown option and its associated `processorSelectionForPackage`
  package-config lookup (`config.local.toml`'s per-package processor lists, if any beyond
  "Default") still exist and still drive the initial checkbox state on page load — only the
  launch-time payload behavior changed. Worth confirming with the user whether the package
  dropdown's remaining purpose (pre-populating checkboxes) is still desired, now that it no
  longer gates what actually launches.
- No investigation was done into whether other callers or admin flows (e.g. any
  programmatic/API trigger of a manual launch outside this Svelte component) rely on the
  old "omit operation for Default" contract.
