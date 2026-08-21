# ADR 2026082003 — Document Processor Dashboard Mapping-Triage Navigation

**Date:** 2026-08-20 \
**Status:** Proposed \
**Component:** ChenWeb — `web/src/lib/components/home3/{dashboard.svelte,content-panel.svelte,doc-processor-dashboard-view.svelte}` \
**Authors:** Chen Ding (with Codex) \
**Related:** ADR `2026081401` (governed metric vocabulary and Phase D failure reporting), ADR
`2026081501` (Resolve Metric Range Types admin page), ADR `2026081801` (lossless semantic
processing), handoff `2026082002` (task 5.8 dashboard distinction) \
**Tags:** frontend, document processor dashboard, mapping triage, navigation, operations

## 1. Change Logs

* 2026/08/20, ADR created from the dashboard follow-up explicitly deferred in handoff `2026082002`.
  It records the next small frontend decision after task 5.8: make a mapping-triage-only failed
  pipeline actionable by navigating to the existing resolution page.

## 2. Context

Task 5.8 of ADR `2026081801` corrected a misleading dashboard behavior. A document whose only
failed processor steps are `extract_metrics` failures caused by an unreviewed
`value_range_type` mapping is not broken: restarting reproduces the same useful, intentional
failure. The Document Processor Dashboard now marks those steps amber as `(mapping triage)` and
replaces the row's Restart action with the text “Needs mapping triage, not restart.” Its tooltip
names the correct operational destination:

> System Admin → Database Maintenance → Resolve Metric Range Types

That destination is already a complete, nav-gated Home3 page. ADR `2026081501` established it as
the place where an operator reviews and applies a governed `value_range_type` mapping. It is
selected by the existing client-side navigation id
`sysadmin-db-resolve-metric-range-types`; Home3 pages do not require a new URL route for this
transition.

Static guidance was the deliberate narrow scope of task 5.8. The dashboard view receives only
`darkMode`, however, even though `dashboard.svelte` owns the `activeMenu` state and
`content-panel.svelte` chooses which child view to render. Consequently the dashboard cannot make
the already-known navigation selection itself.

The handoff identifies three plausible meanings for future “frontend page for the dashboard” work:
live mapping-triage navigation, authenticated browser verification, or a broader findings summary.
This ADR resolves only the first because it is the direct completion of the UI path task 5.8
already exposed. It does not imply that every dashboard finding needs a destination page.

## 3. Decision

**DR1 — Make mapping-triage-only rows navigate to the existing Resolve Metric Range Types page.**

Replace the non-interactive “Needs mapping triage, not restart” action in the Failed Pipelines
table with an accessible button or link-styled button. Activating it selects:

```ts
{
  itemId: 'system-admin',
  itemTitle: 'System Admin',
  childId: 'sysadmin-db-resolve-metric-range-types',
  childTitle: 'Resolve Metric Range Types'
}
```

The action is shown only when every failed step for that record satisfies the existing
`isMappingTriageOnly` predicate. Mixed failures retain Restart because rerunning may still be the
correct response to their genuine operational failure.

**DR2 — Propagate a typed navigation callback through the existing component ownership chain.**

`dashboard.svelte` remains the sole owner of `activeMenu` and passes a navigation callback to
`content-panel.svelte`; `content-panel.svelte` forwards it only to
`doc-processor-dashboard-view.svelte`. The dashboard view calls that callback with the target
selection when the user activates the mapping-triage action.

The callback uses the same `ActiveSelection` shape already exchanged by `NavRail` and
`dashboard.svelte`. The type may be extracted to a shared Home3 module if needed to avoid copying
it between components, but no general event bus or global navigation store is introduced for this
single upward interaction.

**Alternative considered:** have `doc-processor-dashboard-view.svelte` mutate global state or use
`window.location` directly. Rejected because navigation is already owned by `dashboard.svelte` and
Home3 has no route corresponding to this page; either shortcut would create a second navigation
path that can drift from the nav rail's labels, access behavior, and selected-state handling.

**DR3 — Do not automatically reprocess the selected document after navigation or after a mapping
is applied.**

The navigation is an operator handoff, not an execution command. Approving a mapping updates the
governed map, clears matching raw metric error flags, and best-effort schedules targeted semantic
retry-queue entries. Applying an approved mapping also rewrites matching raw `value_range_type`
values to the canonical bucket. Neither action calls `associate_semantics` or restarts a pipeline.
Because the retry queue has no production worker claiming its entries, a corrected record is still
picked up only by its next ordinary reprocess, consistent with the operating model recorded in ADR
`2026081801` Appendix C and handoff `2026082002`.

**Alternative considered:** preserve the document id in a cross-page payload and automatically
restart it after a map update. Rejected because it would silently change the established mapping
workflow, conflate vocabulary governance with processor execution, and still would not solve the
known absence of a retry-queue drain.

**DR4 — Keep the destination page unfiltered for this first increment.**

The target page continues to open in its normal state. It need not receive the dashboard record id
or raw `value_range_type` as a pre-applied filter. A triage-only pipeline can have multiple failed
metrics, and the dashboard's status entry carries the generated error text rather than a reliable
single map-entry identity. The existing page already lists every unresolved mapping and supplies
the source-PDF context needed for an operator to make the governing decision.

**Alternative considered:** add cross-page query state and a preselected map entry. Rejected as
premature coupling: it would require defining a stable error-to-map-entry contract and handling
multiple mappings per document. It can be reconsidered after evidence shows that the unfiltered
page materially slows the actual triage workflow.

**DR5 — Broader dashboard aggregation and browser-auth test infrastructure remain separate work.**

This ADR does not add a semantic-findings summary, new dashboard cards, backend aggregation APIs,
or alerting. It also does not create a login bypass or test credentials. The latter remains a
verification-environment gap, not a feature requirement for navigation.

## 4. Consequences

**Positive:**

* The dashboard gives the operator one direct, correct action for a routine mapping backlog instead
  of making them manually follow tooltip text.
* The distinction task 5.8 introduced becomes operationally useful without turning a semantic
  governance issue back into a processor restart.
* The change reuses the existing nav-gated page and client-side selection model; it requires no
  backend API, schema, route, or permission-model change.

**Negative / accepted costs:**

* The callback crosses two component boundaries for one interaction. This is accepted because those
  boundaries already separate state ownership (`dashboard.svelte`), page dispatch
  (`content-panel.svelte`), and page behavior (`doc-processor-dashboard-view.svelte`).
* Operators still choose the relevant mapping manually on the target page. DR4 deliberately avoids
  adding fragile cross-page selection semantics.
* This does not address genuine pipeline failures, findings that lack a dedicated resolution page,
  or the retry queue's missing consumer.

## 5. Implementation and Verification Criteria

1. A mapping-triage-only failed-pipeline row exposes a keyboard-accessible action labeled for
   resolving metric range types; it is not rendered as Restart.
2. Activating the action makes the existing Resolve Metric Range Types view visible and updates the
   Home3 breadcrumb/nav selection to System Admin → Resolve Metric Range Types.
3. A row with one or more non-triage failed steps still exposes Restart and does not navigate.
4. The existing `isMappingTriageFailure` and `isMappingTriageOnly` tests remain green; add focused
   component-level coverage for target selection and mixed-failure behavior.
5. Run `svelte-check` and the relevant frontend test command. A live browser assertion requires an
   authenticated test session; until credentials or a documented dev-auth path exist, record that
   limitation rather than treating it as a failure of the navigation design.

## 6. Deferred Questions

* Whether a dashboard-level aggregate findings/diagnostics view is needed across semantic families.
* Whether the Resolve Metric Range Types page should later accept a document or mapping filter.
* Whether resolving a mapping should explicitly schedule safe reprocessing rather than waiting for
  the next ordinary document run.
* How authenticated browser verification should be supported in development and CI.
