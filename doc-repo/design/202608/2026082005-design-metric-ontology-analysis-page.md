# Metric Ontology Analysis — Page Design

**Date:** 2026-08-20  
**Status:** Draft  
**Component:** ChenWeb / Home3  
**Source decision:** [ADR 2026082004](../../adrs/202608/2026082004-adr-metric-ontology-analysis-page.md)  
**Audience:** ChenWeb frontend and API implementers, ontology operators, QA

## 1. Purpose and boundaries

This document turns ADR 2026082004 into independently implementable Home3 surfaces. The product is a read-only diagnostic experience: it explains how a raw metric occurrence relates to its governed metric definition, semantic assertion, class, evidence, processing outcomes, findings, checks, and projections. It does not edit, retry, reprocess, or adjudicate anything.

The UI must make these distinctions visible rather than reduce them to a single health state:

* ontology-born vocabulary, corpus-level identity, and record-born data;
* an occurrence, a distinct current metric instance, an ontology metric definition, and a metric class;
* successful processing with findings, blocked claims, execution failures, historical non-processing, incomplete graphs, and unknown coverage; and
* persisted findings versus derived silent-gap/authority warnings.

All aggregates and current-state decisions come from the composed read API. The browser never joins paginated metric, assertion, evidence, and ontology endpoints to recreate these meanings.

## 2. Information architecture

The Home3 navigation entry is **Ontology → Metrics**, with stable identifier `ontology-metric-analysis`. It opens the analysis shell in one of three peer modes:

| Route state | Page | Row grain | Primary question |
|---|---|---|---|
| `view=dashboard` | Metric Dashboard | authorized filter scope | What is the current shape and diagnostic coverage of the metric corpus? |
| `view=document` | Document Metrics | one `kb.metrics` occurrence | What did a source document state, and what semantic graph was built from that occurrence? |
| `view=ontology` | Ontology Metrics | one current `metric_definition` term | What reusable metrics does the governed ontology define, and where are they used? |

The shell accepts the ADR context fields (`inputRecordId`, `metricId`, `assertionId`, `classTermId`, and `ontologyMetricTermId`). Context selects or filters a view after authorization; it never grants access. Each mode preserves its own filters, sorting, cursor, and selected item so cross-view navigation is reversible.

```text
Ontology → Metrics
  ├─ Metric Dashboard
  │   └─ card/chart drill-down → Document Metrics or Ontology Metrics
  ├─ Document Metrics
  │   └─ occurrence detail workspace (8 tabs)
  │        ├─ ontology-metric link → Ontology Metrics detail
  │        └─ governed-workflow links → existing pages
  └─ Ontology Metrics
      └─ ontology-metric detail workspace (6 tabs)
           └─ occurrence/instance rows → Document Metrics detail
```

## 3. Shared shell and visual language

### 3.1 Analysis shell — implement first

This shell is the shared page frame used by every mode.

**Desktop layout**

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│ Breadcrumb: Ontology / Metrics                         [Inspect data]        │
│ Metric Ontology Analysis                 last updated • read-model vN         │
│ [Dashboard] [Document Metrics] [Ontology Metrics]                             │
│ Coverage notice: writer • scope • current-writer coverage • check-rule vN     │
├──────────────────────────────────────────────────────────────────────────────┤
│ Mode-specific controls and content                                             │
└──────────────────────────────────────────────────────────────────────────────┘
```

* The header holds the title, active-mode tabs, response timestamp, and version metadata.
* The compact coverage notice expands into a definition popover. It reports runtime facts, not hard-coded pilot numbers: writer/adapter version, conformance result, scope grain, coverage, governance, contract, resolution, projection, and rules versions.
* `Inspect data` is progressively enabled only for API shapes that expose safe raw JSON. It supplements, never replaces, labelled UI fields.
* On narrow screens, the mode tabs become a select/menu; the coverage notice becomes an expandable panel; tables remain horizontally scrollable with their first identity column pinned.

### 3.2 Shared state presentation

Use text labels, icons, tooltips, and a non-color cue together. Semantic meaning must not depend on color.

| UI treatment | Applies to | Required wording |
|---|---|---|
| neutral identity chip | IDs, term/module/version, entity population | stable label plus raw ID on demand |
| positive status badge | pass, complete, represented, current | never implies governance acceptance |
| warning badge | silent gap, historical non-processing, unresolved unit, auto-promoted term, stale projection | `Warning` plus the explicit reason |
| error badge | failed check, execution failure, policy-defined error | `Error` or `Failed`; never used for findings alone |
| blocked badge | deferred/rejected candidate | `Blocked claim` plus disposition |
| unavailable marker | no workflow/action exists | `No governed action available` |

Every entity summary shows one population/authority chip: **Ontology vocabulary**, **Corpus identity**, **Record data**, **Governed configuration (not a term)**, **Observed evidence (not authoritative)**, or **Rebuildable projection**. A missing relationship renders `Not present` plus its check/coverage explanation, never a fabricated label or placeholder ID.

### 3.3 Reusable components

Build these once and reuse them across all surfaces:

* **ScopeBar** — active authorization-safe scope, applied-filter count, reset, and shareable URL state.
* **CoverageStrip** — disjoint coverage counts and definitions supplied by the server.
* **StateBadgeGroup** — independent lifecycle, resolution, execution, finding, and check badges; it may wrap but never collapse them into one status.
* **PopulationLabel** — authority/lifecycle explanation for an object.
* **MetricDataTable** — server filtering, sorting, cursor pagination, loading skeletons, and column chooser.
* **DefinitionTooltip** — server-provided measure/check definitions and denominator applicability.
* **CheckList** — pass/warning/fail/not-applicable check rows with stable references.
* **EmptyPartialError** — consistent empty, partial graph, forbidden, and request-error states.
* **ContextualActionList** — links to existing governed workflows only; it does not execute a mutation.

## 4. Page 1 — Metric Dashboard

### Job and entry points

The dashboard is the default corpus explorer. It answers “what needs investigation?” and drills into one of the two list views using the exact server-provided filter. It must not imply that occurrence, instance, ontology-metric, and class counts are additive.

### Layout

```text
┌ ScopeBar ────────────────────────────────────────────────────────────────────┐
│ [document] [class] [status …]                              [Reset filters]   │
├ CoverageStrip ───────────────────────────────────────────────────────────────┤
├ KPI row ─────────────────────────────────────────────────────────────────────┤
│ Occurrences │ Instances │ Ontology metrics │ Metric classes │ Errors │ No-error│
├───────────────────────────┬──────────────────────────────────────────────────┤
│ Error presence            │ Coverage state                                   │
│ chart + exact table       │ chart + exact table                              │
├───────────────────────────┼──────────────────────────────────────────────────┤
│ Mapping status            │ Errors by type and severity                      │
│ global / in-scope switch  │ horizontal bars + contributing-source table      │
└───────────────────────────┴──────────────────────────────────────────────────┘
```

**Implementation details**

1. **ScopeBar and coverage strip.** Fetch from `GET .../dashboard`. Show the filter scope in plain language and disclose filters that are `not_applicable` to a measure; do not silently alter its denominator.
2. **KPI row.** Show total occurrences, distinct current instances, ontology metrics, instantiated metric classes, occurrences with errors, without detected errors, and the no-error-with-warnings/silent-gaps subset. Each card includes a grain tooltip, exact count, and keyboard-operable drill-down where a stable filter exists.
3. **Error presence.** Use a stacked bar or donut, but always pair it with an exact-value table. “Without detected errors” carries a tooltip stating that it is not equivalent to complete or warning-free.
4. **Coverage.** Use a labelled bar chart for complete, completed-with-findings, historical/not-processed-current-writer, blocked deferred, blocked rejected, incomplete, execution failed, and unknown. These are disjoint status categories.
5. **Mapping status.** Default to **Global mapping inventory**. A clearly labelled control switches to in-scope distinct mapping rows or affected occurrences; the three denominators are never mixed. Document/class filters are labelled inapplicable in global mode.
6. **Errors by type.** Horizontal bars group canonical error type by policy-derived highest severity. The adjacent table exposes affected occurrences, occurrence/error-type facts, raw-signal count, and contributing sources as distinct fields.

For mobile, KPI cards become a two-column grid, and each chart/table pair stacks with the exact table directly below its chart.

### States and acceptance

* Zero is shown as `0`, not `Unavailable`; unavailable uses an explicit unavailable label.
* A partial chart response keeps valid cards/charts visible and annotates unavailable measures.
* Drill-down must produce the same count in the destination table for filters applicable to that measure.
* Charts have table alternatives and textual labels for assistive technology.

## 5. Page 2 — Document Metrics

### Job and layout

This occurrence-first view includes every authorized raw `kb.metrics` row, including rows with no governed definition or assertion.

```text
┌ ScopeBar ────────────────────────────────────────────────────────────────────┐
├ CoverageStrip ───────────────────────────────────────────────────────────────┤
├ Filter drawer / applied filters                                                 │
├ Document Metrics                               1,245 occurrences • page 1    │
│ [Columns] [Clear filters]                                                        │
├──────────────────────────────────────────────────────────────────────────────┤
│ Document + metric │ Value │ Definition │ Subject │ Assertion/class │ Health   │
│ ─ row identity — detail opens on row activation —                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

The desktop table has a sticky header and pinned first column. The default visible columns are deliberately compact: document/metric, raw and normalized value, metric definition, subject, assertion/class, coverage/check state, and last processed time. The remaining ADR-required fields are available through the column chooser and detail, preventing an unreadable default grid.

### Filters and interactions

The filter drawer uses server-recognized machine identifiers and human labels. It groups filters by:

* **Source:** document, metric text/ID, keyword concept, object.
* **Vocabulary:** metric definition, module, governed-term status, assertion kind, unit/quantity resolution.
* **Semantic graph:** candidate/materialization, assertion lifecycle, class, four state axes, disposition.
* **Diagnostics:** finding type/severity, execution, coverage, projection freshness, failed check, silent gap.

Submitting filters, sort, or a cursor reloads `GET .../document-metrics`; filtering is never performed over only the loaded page. The initial page size is 50, with a maximum selection of 200. Each row exposes its stable composite occurrence identity, and the detail request always uses `(input_record_id, metric_id)`.

### Row anatomy

The health cell is a short, independent badge group: coverage, finding severity/count, failed/warning checks, and blocked/execution state. It must not label a finding-bearing completed metric as failed. Definition and class cells show their roles separately, even where their string IDs happen to match. A row with a missing assertion still opens normally and leads the operator to its coverage/check explanation.

## 6. Page 3 — Document Metric detail workspace

### Job and shell

Open from a Document Metrics row as a full content-panel detail route (not a transient modal) so history, peer cursors, and source links are shareable and browser navigation works. The header includes document title, raw metric name/value, stable occurrence identity, coverage/check summary, and `Back to results` preserving list state.

```text
┌ Back to Document Metrics   [document] › metric name                         │
│ raw value • occurrence ID • independent state badges • [Source] [Inspect]   │
├────────────────────────────────────────────────────────────────────────────┤
│ Metric & Source | Vocabulary | Object & Frame | Candidate & Value | ...     │
├────────────────────────────────────────────────────────────────────────────┤
│ Selected tab content                                                         │
└────────────────────────────────────────────────────────────────────────────┘
```

Load the current graph from `GET .../document-metrics/:input_record_id/:metric_id`. History and peers are lazy-loaded only when their tab is selected. A missing child is a partial detail response and visible check result; only a missing/unauthorized focal occurrence is a page-level error.

### Individually implementable tabs

| Tab | Layout and contents | API/dependencies |
|---|---|---|
| 3A. Metric & Source | Two-column facts panel; left: raw metric fields and normalized summary; right: document, evidence quote, spans, extraction run/model/prompt. Source/review link sits at top right. | current detail |
| 3B. Vocabulary & Naming | Top identity card for keyword concept; governed definition card beneath it with labels, term kind, module/release, lifecycle, auto-promotion provenance, and candidate. A separate mapping card identifies governed configuration as **not an ontology term**. | current detail |
| 3C. Object & Measurement Frame | Horizontal path: object mention → reconciled object node → property/frame. Beneath it, a definition grid for procedure, condition, window, assertion kind, unit, quantity kind, and dimension. Missing stored edges show `Not present`; alternatives remain inspectable. | current detail |
| 3D. Candidate, Assertion & Value | Candidate disposition/reason first; then canonical claim and current assertion cards; raw snapshot/normalized literal side by side; the four state axes, lifecycle, confidence, and error summary shown as separate rows. | current detail |
| 3E. Class & Contract | Class identity card, immutable contract revision/capabilities, validation results, and class-resolution method/alternatives. Observed profile sits in a visually separate “Evidence, not authority” panel. | current detail |
| 3F. Processing & Projection | Timeline-like current stage/outcome list above a finding table. Keep run failure, blocked claim, recorded degradation, and silent gap in separate labelled groups. Projection freshness and retry inspection links follow. History control loads bounded superseded data. | current detail + `/history?sections=...` |
| 3G. Relations & Peers | Relations table first. Peer channels appear in ranked sections: canonical, governed mapped, structural, lexical/vector, persisted LLM. Each says eligibility, returned/total, cap, ranking version, truncation, and cursor. Never initiate LLM work. | current detail + `/peers` |
| 3H. Checks & Provenance | CheckList grouped by pass/warning/fail/not applicable; provenance fact grid; expandable graph path from metric to evidence/assertion/class; actors, timestamps, object IDs and versions. | current detail + optional history |

The tab bar becomes a select/menu on narrow screens. Long fact grids become definition lists; peer and finding tables retain horizontal scroll and accessible captions.

### Contextual actions

Display actions only where their preconditions are actually present: range mapping → Resolve Metric Range Types; ambiguous object → Resolve Ambiguous Objects; raw-value issue → Metrics/reprocessing; candidate → Semantic Decision Candidates; run failure → Doc Processor logs; lifecycle → Semantic Assertions; evidence → Review Document/source; retry inspection → Semantic Retry Queue. All other recognised gaps receive `No governed action available`; no tab may provide an inline mutation.

## 7. Page 4 — Ontology Metrics

### Job and layout

This term-first view starts from current governed `metric_definition` terms and retains zero-occurrence terms. It is not a differently filtered occurrence list.

```text
┌ ScopeBar ────────────────────────────────────────────────────────────────────┐
├ CoverageStrip (term-oriented summaries) ─────────────────────────────────────┤
├ Filter drawer / applied filters                                                 │
├ Ontology Metrics                              182 current metric definitions  │
│ Definition │ Governance │ Measurement model │ Usage │ Diagnostics │ Contract │
└──────────────────────────────────────────────────────────────────────────────┘
```

The default columns are preferred label/term ID, module and governance/release, permitted unit/quantity summary, authorized occurrence count, distinct current instance count, diagnostic summary, contract capability, and last modification time. Raw `value_type` and `range_type` appear only as clearly unnormalised descriptive hints, never primary grouping/filter facets.

### Filters and interactions

Term-oriented filters include term text/ID, module, governance/release status, lifecycle, contract definition/capability, permitted units/quantity/dimension, occurrence/instance presence, error/finding/check effects, and last modification window. A zero occurrence count remains a visible, legitimate result. Selecting a row opens the term workspace; clicking its occurrence count opens Document Metrics scoped to that exact term while preserving the Ontology Metrics state for return.

## 8. Page 5 — Ontology Metric detail workspace

Open from an ontology term as a route-level detail panel. The header includes preferred label, term ID/version, module/release, governance/lifecycle, and authorized occurrence/instance totals shown as different grains.

| Tab | Layout and contents | API/dependencies |
|---|---|---|
| 5A. Definition & Governance | Definition hero card; term/version/lifecycle/module/release grid; alternate labels, scope, auto-promotion and candidate provenance. | current term detail |
| 5B. Measurement Model | Quantity kind/dimension/permitted units and assertion kinds in structured cards; raw value/range hints placed in a warning-styled “Uncontrolled descriptive fields” section. | current term detail |
| 5C. Class & Contract | Linked class and contract cards, revision history entry point, capabilities/validation, and observed profile isolated as non-authoritative evidence. | current term detail + history |
| 5D. Occurrences & Instances | Two independently paginated tables under a segmented control: occurrences and distinct current assertions. Each explains its grain, total, cursor, authorization basis, coverage, and cross-definition convergence warning. | `/occurrences`, `/instances` |
| 5E. Diagnostics | Summary cards followed by filters/tables grouped by canonical error type, severity, source, affected occurrence, failed checks, and silent gaps. | current term detail + bounded expansions |
| 5F. History & Provenance | Version/release/label/candidate/contract timeline ordered by their governed supersession rules; facts and cross-view links. | `/history` |

The Occurrences & Instances tab must never infer term membership from `instance_of_term_id`; it uses the server-provided occurrence-derived relation. It shows cross-definition convergence rather than selecting a single owner for a shared assertion.

## 9. Shared non-happy-path behavior

| Situation | Required presentation |
|---|---|
| no authorized rows/terms | Empty state names the active scope and offers only `Clear filters` or a permitted parent navigation action. |
| historical occurrence unprocessed by current writer | Row/detail remains visible; coverage warning explains known historical status rather than failure. |
| missing graph edge/stage | Partial graph remains visible; relevant check is failed or warning according to server policy. |
| completed with findings | Show successful processing plus finding count/severity; do not render as execution failure. |
| deferred/rejected candidate | Show `Blocked claim`, disposition, and reason; do not fabricate assertion/class values. |
| unresolved unit/quantity, fallback kind, auto-promoted term, identity-only contract, uncontrolled field, stale projection | Derived warning remains visible even with zero persisted findings. |
| unknown governed term | Safe fallback label + raw ID; never hide the field. |
| API/authorization error for focal resource | Full-page error with retry, then return link; do not reclassify it as a semantic finding. |

## 10. Delivery order and test seams

The following slices can be built and tested without waiting for later surfaces:

1. **Shell and shared status components** — route state, ScopeBar, CoverageStrip, StateBadgeGroup, entity-population labels, empty/error states.
2. **Dashboard** — API contract rendering, exact-value tables, charts, measure applicability, and drill-down URLs.
3. **Document Metrics list** — server table, filters, cursor, column chooser, unresolved-row visibility.
4. **Document detail core (3A–3E, 3H)** — current detail and checks/provenance; no history or peers required.
5. **Document detail diagnostics (3F–3G)** — lazy history, bounded peers, channel/cursor metadata.
6. **Ontology Metrics list** — term table, zero-occurrence terms, term filters, cross-navigation.
7. **Ontology detail (5A–5F)** — term facts, independent occurrence/instance pagination, governance history.
8. **Hardening** — accessibility, responsive layouts, raw JSON gating, performance instrumentation, and authenticated browser verification.

Frontend tests should assert independent badges rather than a composite “health” value, route-state preservation across cross-links, zero versus unavailable handling, drill-down equivalence, lazy detail expansion, and keyboard access to tables, tabs, filters, actions, and chart data tables. Backend/API tests remain the authority for counts, classification, checks, authorization-before-aggregation, and pagination as defined by the ADR.

## 11. Out of scope

Version 1 excludes editing of metrics, terms, claims, contracts, evidence, outcomes, findings, checks, or projections; automatic repair/reprocessing/retry; LLM peer adjudication; saved views/export; and a generic ontology graph browser. Those work items require their own governed decision rather than being implied by a diagnostic page.
