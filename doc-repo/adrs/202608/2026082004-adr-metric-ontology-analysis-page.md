# ADR 2026082004 — Metric Ontology Analysis Page

**Date:** 2026-08-20 \
**Status:** Proposed \
**Component:** ChenWeb — Home3 frontend, metric semantic-analysis read API, ontology diagnostics, and source-evidence navigation \
**Authors:** Chen Ding (with Codex) \
**Related:** ADR `2026081701` (ontology object classes, metric instances, and semantic relations), ADR `2026081801` (lossless semantic processing), ADR `2026082003` (dashboard mapping-triage navigation), handoff `2026082003` (current implementation and verification status), user manual `metric-ontology-v1.0-en.md` v1.2 (Metric Ontology model, lifecycle, errors, and current limitations) \
**Tags:** frontend, metrics, ontology, semantic assertions, findings, evidence, analysis, diagnostics

## 1. Change Log

* 2026/08/20 — Initial decision. Defines a read-only frontend page for viewing, checking, and
  analyzing metric occurrences together with their ontology-related objects and processing history.
* 2026/08/20 — Refined from the Metric Ontology user manual v1.2: distinguishes ontology-born,
  corpus-level, and record-born entities; adds naming, object, measurement-frame, candidate,
  vocabulary-governance, projection, blocked-claim, and silent-gap behavior; and records current
  class-contract, unit-resolution, and vocabulary-quality limitations.
* 2026/08/20 — Added two complementary metric views and a chart-based metric dashboard. Defined
  occurrence, instance, ontology-metric, mapping-status, error-presence, and error-type counting
  semantics so dashboard totals remain reproducible rather than depending on UI joins.

## 2. Decision Summary

ChenWeb will add a Home3 **Metric Ontology Analysis** page that presents each raw metric occurrence
and its current semantic graph as one explainable unit.

The page starts from `kb.metrics`, not from an assertion or ontology term. For each occurrence it
shows the name's keyword concept and governed metric definition, subject object, measurement frame,
decision candidate, active supporting evidence link, current semantic assertion and canonical
claim, ontology class and current contract, independent semantic state axes, class-resolution
decision, processing outcomes and findings, projections, related and same-class assertions, and
source provenance. Missing links and silent enrichment gaps are shown as explicit check results
rather than causing the metric to disappear.

The page visually separates the three populations described by the Metric Ontology manual:
ontology-born vocabulary, corpus-level identities, and record-born data. It never labels an
extracted value, keyword concept, object node, assertion, or evidence row as governed ontology
vocabulary merely because it participates in the graph.

A server-side read model composes this graph. The browser must not reconstruct it by issuing an
unbounded set of per-row requests or by inferring current state from append-only history. Dashboard
and list responses remain bounded; expensive peer, history, and relation data load only when a user
opens one metric.

The first version is read-only. It diagnoses and explains; it does not edit raw metrics, ontology
classes, claim identities, resolution history, outcomes, or findings. When action is appropriate,
it navigates to an existing governed workflow such as Resolve Metric Range Types, Semantic
Assertions, or source-document review.

## 3. Context

### 3.1 The metric semantic graph now exists, but no page exposes it as one object

ADR `2026081701` defines the required traversal:

```text
metric occurrence
  -> current supporting evidence
  -> current semantic assertion / canonical claim
  -> ontology class and contract
  -> same-class instances and governed relations
  -> source evidence
```

ADR `2026081801` adds the diagnostic side of that graph:

```text
metric occurrence
  -> required semantic-stage outcomes
  -> zero or more typed findings
  -> independent class, mapping, value, and conformance states
```

The current frontend exposes fragments of this information:

* the metric-management and metric-wiki views expose raw metric-oriented data;
* Semantic Assertions and Assertion Evidence are separate administration pages;
* Review Document's Semantic Diagnostics tab shows assertion lifecycle and the four cached state
  axes with active evidence for one document; and
* Resolve Metric Range Types handles the governed mapping workflow.

No current page starts from a metric occurrence and explains all of its ontology-related objects.
In particular, the existing Semantic Diagnostics tab does not directly expose
`kb.semantic_processing_outcomes` or individual `kb.semantic_processing_findings`, and the current
API has no joined metric-ontology graph response. An operator must correlate raw metrics,
assertions, evidence, and database state manually.

### 3.2 Metric Ontology and metric data are related but not interchangeable

The Metric Ontology is the governed vocabulary for measurement, chiefly the `measurement` and
`quantity` modules. It is not a component, a table, or a store of observed values. It supplies
reusable meanings such as metric definitions, quantity kinds, dimensions, units, measurement-frame
classes and properties, assertion kinds, semantic-processing concepts, labels, module releases, and
class contracts.

A metric occurrence touches three populations with different identity and lifecycle rules:

| Population | Examples | Lifecycle rule |
|---|---|---|
| Ontology-born vocabulary | module/release, governed term, metric definition, quantity kind, dimension, unit, class, assertion kind, contract | Global, versioned, governed, and superseded rather than replaced by document reprocessing. |
| Corpus-level identity | keyword concept, object node, canonical claim identity | Reused across documents; reconciled, merged, or deprecated independently of one record. |
| Record-born data | input, metric row, object mention, decision candidate, assertion/evidence occurrence, processing outcome/finding, class decision, projection state | Created for one input record and re-derived or superseded when that record is processed again. |

`kb.metric_value_range_type_map` is governed configuration but not an ontology term. Observed class
profiles are evidence, not authoritative contracts, and search/projection tables are rebuildable
views, not sources of truth. The UI groups each object by population and authority so proximity in
the graph is never mistaken for equal governance.

The governed-term lifecycle and one metric occurrence's processor lifecycle run on separate clocks.
A term may be `auto-promoted` and usable without being reviewed; an assertion may be `represented`
without being accepted. Neither status implies the other.

### 3.3 Current implementation status constrains the first release

This section describes prerequisite semantic-writer and corpus status only. As of handoff
`2026082003`, this ADR does not claim implementation of the analysis page, composed API, check
rules, history expansion, or peer read model.

The status recorded by ADR `2026081801` and handoff `2026082003` is:

* the metric lossless writer's Phase 3 tasks are complete and
  `LOSSLESS_SEMANTIC_WRITES_METRIC` defaults on;
* the provision writer and generic fallback also default on, but this page is metric-scoped;
* the lossless-processing OpenSpec change remains at 70/72 tasks because additional artifact
  families and the final ADR status transition remain open;
* only one pilot document, record 416, had been live-validated through the current metric writer at
  the time of the handoff; the historical corpus was deliberately not backfilled; and
* the user's broader clean-and-reprocess verification plan had not yet been executed when the
  handoff was written.

The later Metric Ontology manual records a different point-in-time `miner` snapshot in which
`kb.metrics` and `kb.semantic_assertions` were empty. These snapshots describe changing database
contents, not contradictory architecture. The page must report live scope and processing coverage
and must not hard-code either snapshot.

The manual also records current limitations that materially affect honest presentation:

* class-contract tables are deployed but no observed contract revisions existed, so metric classes
  were identity-only and comparison/validation capability was undeclared;
* most metric definitions were `auto-promoted`, which means usable but not reviewed;
* term-level `value_type` and `range_type` contain uncontrolled variants and are descriptive hints,
  not safe grouping keys;
* a raw unit may fail to resolve to a governed unit and quantity kind without producing any finding;
  and
* an empty or ungoverned source claim type may fall back to `mea:observed_value`; when that fallback
  accompanies an unparsed or missing value, the displayed assertion kind requires an explicit
  warning rather than blind trust.

Therefore the page must distinguish all of the following without treating any as equivalent:

1. a metric has a complete current semantic graph;
2. a metric was processed and has semantic findings;
3. a metric predates the writer and has not been processed by it;
4. a required graph edge or stage outcome is unexpectedly missing; and
5. a genuine processor execution failure prevented safe completion; or
6. available provenance cannot establish which of those cases applies.

An empty ontology panel is not automatically a semantic failure. For historical data it may mean
“not processed by the current writer.” The UI must use explicit coverage and check states rather
than infer failure from absence alone.

### 3.4 “View,” “check,” and “analyze” are different user jobs

The page serves three related but distinct jobs:

* **View:** inspect the source metric, normalized assertion, class, states, findings, relations, and
  provenance without knowing table names or IDs in advance.
* **Check:** verify the lossless-processing cardinality and consistency invariants for each metric
  and clearly distinguish expected incompleteness from a violated invariant.
* **Analyze:** filter and aggregate metrics by document, class, lifecycle, semantic states,
  disposition, finding, severity, execution status, and coverage; then compare one metric with
  bounded same-class peers.

The page is not a replacement for Review Document. Review Document asks whether requirements and
claims apply to a review scope. Metric Ontology Analysis asks what semantic object was built from a
metric, why it has its current state, and whether the graph is complete and internally consistent.

## 4. Decision

### 4.1 DR1 — Add one metric-first analysis page to Home3

Add a nav-gated Home3 page named **Metric Ontology Analysis**
(`ChenWeb/home3/knowledge, Ontology => Metrics`). Its stable navigation identifier is:

```text
ontology-metric-analysis
```

It belongs under the existing **Ontology** section because its primary job is to explain the
relationship between extracted metrics and ontology objects. It is available only to users who can
view both the source metric and the semantic diagnostic data. Existing Home3 page configuration and
access-control behavior remain authoritative; this ADR does not create a parallel permission model.

The page accepts optional navigation context:

```ts
type MetricOntologyAnalysisContext = {
  view?: 'dashboard' | 'document' | 'ontology';
  inputRecordId?: number;
  metricId?: string;
  assertionId?: number;
  classTermId?: string;
  ontologyMetricTermId?: string;
};
```

Context preselects or filters the page but never bypasses authorization. The page also works without
context as a corpus-level explorer.

Every dashboard, list, detail, history, and peer query is restricted to source records the caller may
view before aggregation. Counts, peer totals, and class distributions must not reveal unauthorized
records.

### 4.2 DR2 — Use a server-composed read model

Add a read-only API namespace:

```text
GET /api/v1/kb/metric-ontology-analysis/dashboard
GET /api/v1/kb/metric-ontology-analysis/document-metrics
GET /api/v1/kb/metric-ontology-analysis/document-metrics/:input_record_id/:metric_id
GET /api/v1/kb/metric-ontology-analysis/document-metrics/:input_record_id/:metric_id/history
GET /api/v1/kb/metric-ontology-analysis/document-metrics/:input_record_id/:metric_id/peers
GET /api/v1/kb/metric-ontology-analysis/ontology-metrics
GET /api/v1/kb/metric-ontology-analysis/ontology-metrics/:term_id
GET /api/v1/kb/metric-ontology-analysis/ontology-metrics/:term_id/occurrences
GET /api/v1/kb/metric-ontology-analysis/ontology-metrics/:term_id/instances
GET /api/v1/kb/metric-ontology-analysis/ontology-metrics/:term_id/history
```

The composite `(input_record_id, metric_id)` identifies one metric occurrence. No endpoint may
select an occurrence using `metric_id` alone unless a later decision proves and documents global
uniqueness. The server returns a conflict/integrity error if the composite unexpectedly resolves to
multiple raw metric rows; it never silently selects the first row.

The API composes existing authoritative tables and projections; it does not create a second
persistent source of truth. `document-metrics` is occurrence-first, while `ontology-metrics` is
governed-term-first. The document-metric detail response is organized into typed sections:

```text
source_metric
coverage
checks[]
name_resolution
metric_definition
governance_context
subject_resolution
measurement_frame
governed_value_mapping
decision_candidate
current_evidence
current_assertion
canonical_claim
ontology_class
current_contract
class_resolution
processing_outcomes[]
processing_findings[]
observed_class_profile
projection_state
relations[]
peer_summary
provenance
```

The browser may reuse existing APIs for navigation destinations, but the analysis page reads its
core list and detail from this composed contract. This avoids per-row client joins, contradictory
definitions of “current,” and accidental display of stale append-only records as current state.

The history endpoint accepts a `sections` parameter selecting one or more bounded history
collections. Each collection is independently cursor-paginated and reports returned count,
truncation, and supersession links.

### 4.3 DR3 — Provide Document Metric and Ontology Metric views

The page provides two peer views over the same domain. Neither is a filtered imitation of the
other; each starts from its own authoritative population and answers a different question.

#### Document Metric View

**Document Metric View** starts from `kb.metrics`. One row is one metric occurrence extracted from
one input record. It answers:

> What metrics did this document state, and what semantic and ontology objects were built from each
> occurrence?

It supports one-document and authorized corpus scopes. The default document-scoped order follows
source position and then stable metric row ID; corpus scope uses an explicit server sort. It exposes
the full occurrence-first graph defined by DR5, including raw wording/value, source spans, keyword
concept, governed metric definition, subject object, decision candidate, assertion/evidence,
canonical claim, class/contract, processing outcomes/findings, checks, relations, and projections.

Metrics without a governed definition or semantic assertion remain rows in this view. Missing
downstream objects are coverage/check results, not reasons to omit the occurrence.

#### Ontology Metric View

**Ontology Metric View** starts from the current governed ontology-term population. One row is one
stable metric-definition identity, with its current term version and labels. It answers:

> What metrics does the governed ontology know, and which document occurrences and semantic
> instances use each one?

The deployed schema calls this term kind `metric_definition`; it does not define a generic
`type = 'metric'` value. Therefore the normative source predicate is the current
`kb.ontology_terms` version whose `kind = 'metric_definition'`, resolved through
`kb.ontology_term_headers`. The UI label may say “Ontology Metric,” but the API returns the exact
stored kind. It never substitutes term kind `class` or infers a metric solely from a label.

Each ontology-metric row shows stable term ID, preferred/alternate labels, module, version,
governance status, active-release membership, auto-promotion provenance, description/scope, raw
`value_type` and `range_type` hints, permitted units, linked quantity information, keyword-concept
alignments, linked ontology candidates, occurrence count, distinct current instance count, subject
and unit coverage, finding/check summaries, and current class-contract/capability information when
available. The uncontrolled `value_type` and `range_type` fields remain raw descriptive values and
are not silently normalized for grouping.

An ontology metric with zero document occurrences remains visible. Conversely, a document metric
with no governed definition remains visible only in Document Metric View and appears in dashboard
coverage as unresolved; Ontology Metric View never fabricates a term row for it.

#### Cross-view navigation and state

The two views are linked by stable identities:

* a document occurrence with `metric_definition_term_id` opens that term in Ontology Metric View;
* an ontology metric opens its authorized document occurrences and distinct current semantic
  instances; and
* returning to the prior view preserves filters, sort, cursor, and selected row for that view.

The occurrence count and instance count are not expected to match. Several occurrences may converge
on one canonical assertion, while an ontology metric may have no occurrence or instance. The UI
explains this relationship instead of presenting count differences as data loss.

Per-ontology-metric instance membership is a versioned derived relation keyed by
`(ontology_metric_term_id, current_assertion_id)`. Its authoritative path is:

```text
current kb.metrics.metric_definition_term_id
  -> current active supporting kb.assertion_evidence for that occurrence
  -> redirect/claim-registry-resolved current kb.semantic_assertions.id
```

The relation deduplicates converged occurrences by that pair. It never infers the ontology metric
from `instance_of_term_id`, because metric-definition identity and metric-class identity are separate
roles even when they reuse one identifier string. If one assertion is supported by occurrences
assigned to different metric-definition terms, it appears once under each supported term and the
read model emits a cross-definition convergence warning rather than selecting one owner. A metric
instance found through the class/claim classifier whose authorized source evidence carries no metric
definition contributes to the corpus-wide instance total but to no per-term instance count; the
dashboard reports it as unassigned. A source-unanchored assertion contributes to neither total.

Authorization is applied to the supporting occurrence before this relation is aggregated. A caller
sees an assertion under an ontology metric only when at least one authorized current occurrence
establishes that exact pair; counts never reveal unauthorized supporting occurrences.

### 4.4 DR4 — Add a filter-aware Metric Dashboard

The page includes a **Metric Dashboard** as a third primary mode alongside the two metric views. It
shows metric-related statistics using KPI cards and charts over one explicit, authorized filter
scope. Dashboard cards are navigation controls: selecting a segment opens the corresponding view
with the equivalent server-side filter when that filter has a stable contract.

The initial dashboard includes these required statistics:

| Statistic | Normative definition |
|---|---|
| **Total metric occurrences** | Count of authorized current rows in `kb.metrics`. One extracted metric in one input record contributes one. |
| **Total metric instances** | Count of distinct current `kb.semantic_assertions.id` values classified by the shared read model as metric instances and source-anchored to at least one authorized in-scope input record. An assertion is metric-scoped when it resolves through the current metric claim/class path or metric evidence with `artifact_type = 'metric'`; several occurrences supporting the same current assertion count once. Assertion revisions and redirected predecessors do not count again. |
| **Total ontology metrics (metric definitions)** | Count of distinct stable current ontology term IDs whose current `kb.ontology_terms.kind = 'metric_definition'`. This is the requested `kb.ontology_terms` metric population. It is not labeled “metric classes,” because terms whose stored kind is literally `class` and distinct `instance_of_term_id` values are separate populations. |
| **Total instantiated metric classes** | Count of distinct current `instance_of_term_id` values among the metric instances selected by the shared classifier. This separate secondary measure supplies the literal class angle without conflating it with ontology metric definitions. |
| **Metric occurrences with errors / without detected errors** | A disjoint occurrence-level partition produced by the versioned error-presence policy below. “Without detected errors” does not mean warning-free or semantically complete. |
| **Value-range mappings by status** | Global count of rows in `kb.metric_value_range_type_map`, grouped by stored governed status. It is configuration inventory, explicitly labeled **Global**, and document/occurrence/class filters do not apply. A separate in-scope series counts distinct mapping rows referenced by at least one authorized filtered occurrence, each row once; affected occurrence counts are a third, separately labeled measure. |
| **Errors by type** | Count of canonical, deduplicated occurrence/error-type facts grouped by stable `error_type`, with severity and source available for drill-down. |

The deployed assertion schema likewise has no generic `type = 'metric'` column. “Metric instance”
is therefore a versioned server classification, not a frontend predicate on a nonexistent field.
Phase 0 must prove its class/claim and evidence branches select the same intended population and
record any legacy-only exceptions before the count is enabled. Every classifier-selected assertion
must also resolve through authoritative active evidence or retained evidence history to at least one
authorized in-scope source record before entering user-visible totals. A mixed-authority assertion
counts once when at least one authorized in-scope source anchors it, but unauthorized evidence and
its counts remain hidden. A source-unanchored class/claim-only assertion is excluded from metric
totals and reported only through a separately authorized integrity measure.

`unassigned_metric_instances` means source-anchored metric instances with no derived
`ontology_metric_term_id` membership; it never means assertions with no source ownership.

The dashboard also shows no-error occurrences with warnings or silent gaps so “without detected
errors” is not mistaken for “healthy.” Additional initial charts may include coverage state, assertion
lifecycle, metric-definition governance status, subject resolution, unit/quantity resolution,
class-definition state, and projection freshness. Every chart is backed by a visible data table and
uses text/pattern labels in addition to color.

#### Dashboard counting rules

The server owns all aggregation rules. The browser never derives totals by loading table pages.

`has_error` is true for a metric occurrence when at least one current diagnostic is a genuine
execution failure, rejected/deferred blocked claim designated error by policy, non-empty
`kb.metrics.value_range_type_error`, active semantic finding with error severity, or failed integrity
check. Warning/info findings and derived silent-gap warnings do not set `has_error` unless the
versioned policy explicitly promotes that type. Thus
`with_errors + without_detected_errors = total_metric_occurrences` for the same scope and snapshot.

`occurrences_without_errors_with_warnings_or_silent_gaps` counts distinct authorized in-scope
occurrences for which `has_error = false` and at least one current warning/info finding, warning
check, or derived silent-gap/authority warning exists. It excludes every `has_error = true` row and
deduplicates once per occurrence. Therefore it is a subset of `without_detected_errors`; the
remaining no-error occurrences have no detected warning under the current policy.

Errors-by-type uses a canonical `error_type` vocabulary and deduplicates by
`(input_record_id, metric_id, error_type)` within the current snapshot. The resolver maps equivalent
signals—such as a raw range-type error flag and its corresponding semantic mapping finding—to one
type rather than double-counting the same cause. One occurrence may still contribute to several
different types. When equivalent contributing signals disagree on severity, the versioned policy
selects the highest governed severity using `error > warning > info`; all contributing sources and
their original severities remain provenance. The dashboard returns distinct affected-occurrence
count, deduplicated occurrence/error-type fact count, and contributing raw-signal count so the three
measures are never conflated.

All dashboard responses include applied filters, per-measure filter applicability, `generated_at`, read-model version,
error-policy version, check-rule version, source row counts, and definitions/tooltips for every
measure. Document authorization is applied before aggregation. Dashboard comparisons across time
require persisted historical snapshots or an explicitly selected time basis; version 1 does not
manufacture trends from append-only table timestamps with different semantics.

#### Required dashboard visualizations

* KPI cards: total occurrences, total instances, total ontology metrics, instantiated metric classes,
  with errors, without detected errors, and no-error occurrences with warnings/silent gaps;
* a donut or stacked bar for occurrence error presence, with an adjacent exact-value table;
* a bar or donut chart for value-range mapping rows grouped by stored status;
* a horizontal bar chart for errors grouped by canonical error type and severity; and
* a coverage-state chart showing processed, finding-bearing, blocked, incomplete, failed,
  historical-unprocessed, and unknown occurrences.

No chart may imply that occurrences, instances, and ontology metrics are additive populations. They
are different grains and appear as separate measures with explanatory tooltips.

### 4.5 DR5 — Define the canonical current traversal explicitly

For a metric occurrence, the API resolves current state in this order:

```text
kb.metrics (input_record_id, metric_id)
  -> kb.keyword_concepts / kb.keyword_surfaces
       metric.keyword_concept_id
  -> accepted core:aligns_to_term assertion
  -> metric_definition term/header, labels, owning module, and active release

kb.metrics
  -> kb.artifact_objects (metric object mention)
  -> kb.object_nodes (reconciled feature of interest)

kb.metrics
  -> governed kb.metric_value_range_type_map decision
  -> kb.semantic_decision_candidates (normalization/adjudication state)
  -> kb.assertion_evidence
       artifact_type = 'metric'
       matching input_record_id and artifact_id
       evidence_role = 'supports'
       deleted = false
  -> kb.semantic_assertions
       resolve an active assertion redirect when present
       resolve the claim registry's current assertion when claim-backed
  -> kb.semantic_claim_identities
       claim_id = assertion.logical_identity_key when registry-backed
  -> kb.ontology_term_headers / kb.ontology_terms
       stable instance_of_term_id and current display label/version
  -> kb.ontology_class_contract_revisions
       ontology_term_headers.current_contract_revision_id
  -> contract capabilities and their latest validation results
```

The assertion's measurement frame resolves `subject_object_id`, `predicate_term_id`,
`assertion_kind_term_id`, `unit_term_id`, and `quantity_kind_term_id` to their governed terms and
labels. When available, quantity-kind metadata resolves the compatible dimension. Procedure,
condition, and aggregation-window relationships are returned only when an authoritative stored edge
exists; the read model never manufactures the complete frame from labels or free text.

Metric-definition identity and metric-class identity are shown as separate roles even when the
deployed registries reuse the same identifier string. The former says which reusable metric the raw
name denotes; `instance_of_term_id` says which class the stored claim instantiates. The UI must not
collapse those roles into one unlabeled “ontology term.”

The diagnostic branches are:

```text
metric -> kb.semantic_processing_outcomes (active, artifact/stage scoped)
       -> kb.semantic_processing_findings (active children)

metric -> latest applicable kb.ontology_class_resolution_decisions
       -> kb.ontology_class_resolution_alternatives

assertion -> kb.assertion_relations -> related current assertions
class     -> bounded current same-class assertions -> their active evidence
class     -> current observed profile and profile attributes (evidence only)
metric/assertion -> kb.projection_state and rebuildable metric search projection
input record -> stage status and bounded kb.doc_proc_logs diagnostics
```

Ontology candidates are returned only when stable provenance or fingerprint data links them to the
metric occurrence or its extraction run. Similar text alone is not a join. Likewise, a projection
is displayed as derived state and freshness information; it is never used to override the raw
metric, governed term, assertion, or evidence source of truth.

“Latest applicable class-resolution decision” is selected through the decision supersession chain,
not by timestamp alone. Class-resolution decisions, alternatives, and semantic claim identities are
append-only and database-immutable; the analysis API treats them as history and never offers update
or delete actions.

A semantic claim identity is an immutable identity anchor, not a mutable current-state row.
“Current claim assertion” means the assertion selected by the claim registry's authoritative
projection; prior assertion targets are assertion history.

For every joined object type, implementation must name and test the authoritative current-state
column, projection, active flag, or supersession rule. Timestamps are never a tie-breaker unless the
table's governing decision explicitly makes them authoritative. Zero or multiple current candidates
produce a partial section and failed integrity check; the resolver never selects the first row.

Assertion lifecycle is returned as its authoritative stable machine value and governed display
label, separately from class, mapping, value, and conformance states. The API never synthesizes
lifecycle from those axes.

### 4.6 DR6 — Return explicit coverage and integrity checks

Every list row and detail response carries a versioned, machine-readable coverage state:

```text
complete
completed_with_findings
not_processed_current_writer
blocked_deferred
blocked_rejected
incomplete
execution_failed
coverage_unknown
```

This is a read-model classification, not a new persisted execution or assertion status. It must be
derived from source presence, writer-era/version evidence where available, execution status,
adapter-declared required stages, and the checks below. It must never convert ADR `2026081801`'s
binary execution status into a third stored status.

Coverage states are mutually exclusive and evaluated in this order:

1. `execution_failed` when either the current applicable semantic outcome records genuine failed
   execution, or the authoritative document-stage status and logs establish genuine processor
   failure. A legacy stage `failed` value caused solely by mapping triage is not genuine execution
   failure;
2. `not_processed_current_writer` when provenance proves the occurrence predates the current
   writer or its cutover promise and the absent graph elements are expected;
3. `blocked_rejected` when the current decision candidate was rejected and no current assertion was
   materialized;
4. `blocked_deferred` when the current decision candidate is waiting on a named dependency and no
   current assertion was materialized;
5. `incomplete` when one or more invariant checks fail and no earlier state explains the missing
   graph;
6. `completed_with_findings` when required processing completed, no required check has status
   `fail`, and active findings exist;
7. `complete` when required processing completed, no required check has status `fail`, and no active
   findings exist. `warning` and `not_applicable` do not prevent either state, but the UI labels
   `complete` as **processed without findings**, never “semantically complete,” and displays any
   warning count alongside it; or
8. `coverage_unknown` when absence cannot be classified because required writer/cutover provenance
   is unavailable.

Warnings may accompany any state but do not independently determine coverage. A failed check takes
precedence over findings, while a proven current execution failure takes precedence over missing
downstream graph elements caused by that failure. A blocked state explains why no assertion exists;
it does not by itself declare the metric compliant with ADR `2026081801`'s lossless-instance target.
The separate checks still report whether the current adapter/cutover contract requires an assertion.

The record's document-processor stage status and a semantic outcome's binary execution status remain
separate inputs. A dashboard row labeled mapping triage is not classified as `execution_failed`
merely because a legacy stage status says `failed`; the resolver must establish a genuine system
failure rather than a semantic mapping condition.

Initial checks are:

| Check | Pass condition | Failure meaning |
|---|---|---|
| `metric_name_resolution` | The metric's keyword concept resolves through a current accepted alignment to the displayed metric-definition term, or the response explicitly records that no governed term exists. | Lexical identity, alignment, and governed metric identity disagree or are silently absent. |
| `metric_term_governance` | The metric-definition term resolves to a current usable version, labels, module, and release/auto-promotion state. | A stale, superseded, rejected, or untraceable term is presented as current. |
| `subject_object_resolution` | The metric object mention resolves to exactly one current object node, or its ambiguous/unresolved candidate state is explicit. | The feature of interest is missing or was guessed without preserved alternatives. |
| `decision_candidate_continuity` | The current metric has one traceable candidate path to an assertion or an explicit deferred/rejected terminal state. | Normalization/adjudication history cannot explain materialization. |
| `metric_support_link_count` | Exactly one current supporting evidence link for the metric occurrence. | Lossless metric cardinality is incomplete or duplicated. |
| `assertion_current_resolution` | The link resolves to one current assertion after redirects/claim projection. | The semantic object is missing or points to stale identity. |
| `required_stage_outcomes` | Exactly one active outcome exists for every metric-adapter required stage. | Processing coverage is incomplete. |
| `outcome_finding_summary` | Active child count and highest severity agree with the outcome summary. | The diagnostic projection is inconsistent. |
| `active_finding_parent` | Every active finding belongs to an active outcome. | Persistence invariant is violated. |
| `class_reference` | Class-bearing states have a stable `instance_of_term_id`. | Class state and class identity disagree. |
| `claim_class_alignment` | Assertion class and canonical claim class agree when both are present. | Claim or assertion identity is inconsistent. |
| `raw_snapshot_alignment` | The assertion snapshot fingerprint matches its referenced source occurrence revision when the required revision data exists. | Raw history may not describe the occurrence used for normalization. |
| `contract_reference` | A required non-null normalization contract reference resolves and belongs to the assertion's class. Return `not_applicable` when the applicable writer contract does not require it, and `warning` for a documented identity-only/no-contract phase limitation. | Fail only when a required reference is missing, dangling, or belongs to the wrong class. |
| `contract_capability` | Validation/comparison is claimed only when the current contract enables and validates that capability. | An identity-only or indeterminate class is being presented as safely comparable or validatable. |
| `assertion_kind_resolution` | The assertion kind resolves to a governed term; whether it was directly resolved or substituted as a fallback is explicit; and fallback caused by empty or ungoverned claim-type input is disclosed independently of value state. | A fallback observation could be mistaken for the source's requirement, target, or capability. |
| `unit_quantity_resolution` | Raw unit, governed unit, quantity kind, and dimension resolve consistently, or the missing enrichment is explicit. | Unit-aware analysis may be silently incomplete or dimensionally unsafe. |
| `value_range_mapping` | Proposed, approved, ambiguous, and absent mapping states are displayed with their actual decision meaning. | An unresolved backlog or an intentional ambiguous decision is misrepresented. |
| `projection_freshness` | Derived projection state is current for its declared source revision, or is explicitly stale/missing. | A rebuildable view could be mistaken for current source-of-truth data. |
| `relation_targets` | Relation endpoints resolve through current redirects and are not self-relations. | Relation history or projection is invalid. |

Each result contains `check_id`, `status`, `severity`, `summary`, and stable object references. Check
status is one of `pass`, `warning`, `fail`, or `not_applicable`. A check uses `warning`, not `fail`,
when the system can prove the occurrence predates the current writer and no cutover promise covered
it. If the system cannot prove whether absence is historical or erroneous, it reports `warning`
with an explicit reason and classifies coverage as `coverage_unknown`; it does not guess.

Some checks intentionally produce warnings without persisted findings. An unresolved unit/quantity
chain, an `auto-promoted` but unreviewed metric definition, uncontrolled term `value_type` or
`range_type`, an identity-only class contract, and an assertion-kind fallback are **silent-gap or
authority warnings**. They remain visible even when `finding_count = 0`; absence of findings or of
`semantic:severity_error` is not evidence that the metric is semantically complete.

Checks are deterministic server rules with a version returned in the API. They are diagnostic and
must not mutate, repair, retry, or reprocess data as a side effect of a GET request.

### 4.7 DR7 — Use view-specific tables and detail workspaces

Metric Dashboard owns the full aggregate presentation defined by DR4. Each metric view has a compact
context strip, a server-driven table, and a detail workspace. The strip may repeat a small subset of
dashboard measures for the active view/filter, but it uses the same server definitions and links to
the dashboard rather than implementing a second aggregation policy.

**View context strip**

Shows disjoint totals using the exact coverage identifiers: processed without findings (`complete`),
completed with findings, not processed by the current writer, blocked deferred, blocked rejected,
incomplete, execution failed, and coverage unknown. Secondary distributions show the three entity
populations, metric-definition governance status, subject resolution, class identity, mapping,
value, conformance, unit/quantity resolution, assertion-kind fallback, finding severity, and top
classes. Every number is computed over the current filter scope, and the response identifies that
scope.

**Document Metric table**

One row represents one raw metric occurrence. Columns are:

* document and metric name;
* raw value and normalized value;
* keyword concept, governed metric definition, and term status;
* subject object and reconciliation status;
* assertion kind, unit, quantity kind, and dimension resolution;
* ontology class label and stable term ID;
* decision-candidate/materialization state;
* assertion lifecycle;
* class, mapping, value, and conformance states;
* processing disposition, finding count, and highest severity;
* contract capability and projection-freshness summary;
* coverage/check state; and
* last semantic processing time.

The table supports server-side filtering, sorting, and cursor pagination. Initial filters cover
document, metric text/ID, keyword concept, metric definition, module, governed-term status, object,
class, candidate/materialization state, lifecycle, assertion kind, unit/quantity resolution, four
state axes, disposition, finding term, severity, execution status, coverage state, projection
freshness, “has failed check,” and “has silent-gap warning.” Filters use stable machine identifiers
in API requests and human-readable governed labels in the UI. Uncontrolled term `value_type` and
`range_type` are not offered as authoritative facets; if exposed for inspection, their raw variants
remain visibly unnormalized.

**Ontology Metric table**

One row represents one stable current ontology metric-definition identity. Columns include preferred
label and term ID, module/version/governance status, release or auto-promotion status, description,
raw value/range hints, permitted units/quantity information, aligned keyword-concept count, document
occurrence count, distinct current instance count, error/finding/check-affected occurrence counts,
contract definition/capability state, and last governed modification time. Filters and sorting are
server-side and use the term-oriented fields defined in DR3.

**Document Metric detail workspace**

Opening a row shows eight tabs:

1. **Metric & Source** — complete raw metric fields, document identity, evidence quote, line spans,
   extraction run, model/prompt, and a link to the source/review context.
2. **Vocabulary & Naming** — keyword concept and surfaces, accepted term alignment, governed metric
   definition, labels, kind, module, version, lifecycle, active release, auto-promotion provenance,
   and any stably linked ontology candidate. It labels governed value-range mapping separately from
   ontology terms.
3. **Object & Measurement Frame** — object mention and reconciliation alternatives, canonical object
   node/feature of interest, observable property, procedure, condition, aggregation window,
   assertion kind, unit, quantity kind, and dimension. Missing stored relationships remain empty;
   labels are not used to invent them.
4. **Candidate, Assertion & Value** — decision-candidate status/reason, canonical claim, assertion
   revision/lifecycle, raw snapshot, normalized literal, four state axes, confidence, and processing
   error summary.
5. **Class & Contract** — stable class identity, label/version, definition state, current immutable
   contract revision, capabilities, validation results, and class-resolution method/alternatives.
   It also shows the observed class profile as non-authoritative evidence and never enables
   comparison merely because two assertions share a class label.
6. **Processing & Projection** — document-stage status, bounded diagnostic logs, required stages,
   active outcomes, all active typed findings, execution status, disposition, severity, retry state,
   dependency/input fingerprints, projection freshness, and superseded-history access. Run failure,
   blocked claim, recorded degradation, and silent gap are labeled separately.
7. **Relations & Peers** — governed assertion relations and bounded same-class peers with their
   source metrics and warning states. Canonical-class results are separated from structural,
   similarity, or LLM fallback channels.
8. **Checks & Provenance** — all integrity checks, entity population/authority, object IDs,
   timestamps, actors, versions, and an
   inspectable graph path explaining how the displayed object was resolved.

Raw JSON may be available behind an “Inspect data” affordance, but it is supplemental. The primary
presentation uses labels, field definitions, and explicit missing-state messages.

**Ontology Metric detail workspace**

Opening an ontology metric uses the same visual vocabulary but a term-first arrangement:

1. **Definition & Governance** — term identity/version, labels, description/scope, module, active
   release, lifecycle, and auto-promotion/candidate provenance.
2. **Measurement Model** — quantity kind, dimension, permitted units, assertion kinds, measurement
   frame, and raw uncontrolled hints with warnings.
3. **Class & Contract** — class identity linkage, contract revisions, capabilities, validation
   results, and observed profile clearly separated from authority.
4. **Occurrences & Instances** — bounded authorized document occurrences and distinct current
   assertions, with separate totals, coverage summaries, and continuation cursors.
5. **Diagnostics** — errors/findings/checks grouped by stable type, severity, source, and affected
   occurrence, including silent gaps.
6. **History & Provenance** — superseded term versions, releases, labels, candidates, actors, and
   stable cross-view links.

### 4.8 DR8 — Preserve independent meanings in presentation

The page must not compress independent states into one red/green judgment.

At minimum it displays separately:

* document-stage execution status and semantic-outcome execution status;
* coverage/check status;
* candidate/materialization state (`not_processed`, `deferred`, `rejected`, or `asserted`);
* assertion lifecycle;
* governed-term lifecycle and module-release status;
* keyword-concept status and object-reconciliation status;
* class identity and class-definition state;
* mapping resolution;
* value state;
* conformance state;
* unit, quantity-kind, dimension, and assertion-kind resolution;
* processing disposition and findings;
* silent-gap/authority warnings that have no persisted finding;
* projection freshness;
* evidence role; and
* relation/comparison result.

“Completed with findings” means successful execution with one or more semantic findings. It must
not be labeled “failed.” A represented assertion must not be presented as accepted, and a warning
must not hide the source metric. A missing metric value must remain distinguishable from an absent
metric occurrence.

The four user-facing error classes from the Metric Ontology manual remain explicit:

| Class | Page representation |
|---|---|
| Run failure | Failed document stage or genuine failed semantic outcome, with logs and downstream-not-run state. |
| Blocked claim | Current deferred/rejected decision candidate and reason, with no claim silently fabricated. |
| Recorded degradation | Stored assertion plus its state axes, outcome, and findings. |
| Silent gap | Deterministic warning derived from absent or weak enrichment even when no finding exists. |

The page also keeps the governed-term lifecycle separate from the metric processor lifecycle and the
assertion governance lifecycle. `auto-promoted` means usable but unreviewed; `represented` means
stored but unendorsed; neither may be rendered as `accepted` or `included_in_release`.

Colors supplement text and icons; they never carry meaning alone. Every badge has a stable label and
tooltip/description. Unknown governed terms render using a safe fallback label plus the raw term ID
rather than disappearing.

### 4.9 DR9 — Bound analysis and peer expansion

Dashboard and list queries run entirely on the server and are filter-aware. The initial list page
size is 50 and the maximum is 200. Detail loads only for the selected metric or ontology term.

Same-class peer retrieval follows ADR `2026081701` DR13:

1. canonical same-class instances;
2. governed mapped-class instances;
3. structurally compatible candidates;
4. lexical/vector candidates; and
5. already-persisted bounded LLM adjudication results.

Version 1 never initiates LLM adjudication. Doing so requires a separate future decision and
governed workflow. Each channel returns its total eligible count, returned count, truncation flag,
ranking policy version, configured cap, and continuation cursor. The canonical/mapped-class channel
is capped at 200 peers per focal occurrence. Every fallback channel has an explicit, versioned cap
lower than 200 and cannot displace canonical results.

The API must avoid one-query-per-row behavior. It uses set-based queries and appropriate indexes,
and exposes timing plus check-rule/read-model versions in diagnostic metadata.

### 4.10 DR10 — Keep correction in existing governed workflows

Version 1 is read-only. It may offer contextual navigation actions:

| Condition | Destination |
|---|---|
| Unresolved or ambiguous metric range mapping | Resolve Metric Range Types |
| Ambiguous or unresolved subject object | Resolve Ambiguous Objects |
| Raw extraction or value parsing needs correction | Knowledge System → Metrics, then explicit record reprocessing |
| Candidate is deferred, rejected, malformed, or orphaned in `in_review` | Semantic Decision Candidates |
| Genuine processor run failure | Doc Processor Logs and the Doc Processor dashboard |
| Suspected duplicate subject identity | Object Manager |
| Assertion lifecycle requires governed review | Semantic Assertions |
| Evidence or source text needs inspection | Review Document/source viewer |
| Retry state needs inspection | Semantic Retry Queue |
| Orphaned ontology term labels | Resolve Orphaned Labels |
| Duplicate input-status operation entries | Consistency Check |
| Leftover artifact data for a deleted/re-imported record | Clean Artifact Data, with an explicit destructive-action warning |

Navigation passes only stable context supported by the destination. If a destination cannot safely
accept a filter, it opens unfiltered and explains what the operator should locate, following the
same conservative rule as ADR `2026082003`.

The page does not provide “repair all,” automatic reprocessing, direct SQL-like editing, or hidden
mutation after navigation. The manual describes dependency-triggered candidate re-normalization as
a backlog drain. Handoff `2026082003` separately reports that `kb.semantic_retry_queue` has no
production caller of `Claim`. Phase 0 must verify which mechanism is currently callable and name
them separately. The page must not imply that merely scheduling a retry executes it or that
unchanged curation dependencies will progress.

For ontology-candidate triage, auto-promoted-term review, keyword-concept alignment conflicts,
class-contract definition/capability governance, class ambiguity/conflict, uncontrolled term-field
normalization, unresolved units or quantity kinds, assertion-kind fallback, direct findings triage,
corpus completeness/integrity findings, and unrecognized source-artifact resolver configuration,
the current manual records no dedicated page. The analysis page labels the condition and action as
unavailable; it does not invent a destination or imply that retrying unchanged inputs will resolve
a curation dependency. The candidate backlog drain and the semantic retry queue are shown as
distinct mechanisms.

### 4.11 DR11 — Make implementation status visible in the page

The page header includes a compact data-coverage notice derived from runtime facts:

* enabled metric writer mode and adapter version;
* adapter conformance-suite version and last verified result;
* selected scope's occurrence, distinct current instance, and ontology-metric counts, each labeled
  with its grain, plus current-writer processed-occurrence count;
* governed metric-definition counts by released/auto-promoted/other status;
* blocked-candidate, recorded-finding, and silent-gap counts;
* class-contract counts by definition state and capability availability;
* unit/quantity resolution and assertion-kind fallback counts;
* projection-current/stale/missing counts;
* the check-rule/read-model version; and
* whether results include historical metrics not processed by the current writer.

This notice prevents a clean pilot document from being misread as proof of full-corpus completeness.
It is not hard-coded to record 416 or to the handoff's counts; those facts are historical context,
while the page reports live state. It likewise does not infer health from an empty database, a large
seeded vocabulary, or a zero error-severity finding count.

## 5. API Contract Requirements

### 5.1 Dashboard response

The dashboard response contains one snapshot envelope:

```text
scope and applied_filters
generated_at
read_model_version, error_policy_version, check_rule_version
totals {
  metric_occurrences
  metric_instances
  ontology_metrics
  instantiated_metric_classes
  unassigned_metric_instances
  occurrences_with_errors
  occurrences_without_detected_errors
  occurrences_without_errors_with_warnings_or_silent_gaps
}
distributions {
  global_value_range_mapping_rows_by_status[]
  in_scope_distinct_mapping_rows_by_status[]
  affected_occurrences_by_mapping_status[]
  errors_by_type_and_severity[] {
    error_type, canonical_severity
    affected_occurrence_count
    occurrence_error_type_fact_count
    contributing_signal_count
    contributing_sources[]
    drill_down_filter
  }
  coverage_states[]
}
error_summary {
  affected_occurrence_count
  occurrence_error_type_fact_count
  contributing_signal_count
}
restricted_integrity {             # present only with separate integrity permission
  source_unanchored_metric_assertion_count
}
measure_definitions[]
filter_applicability_by_measure
source_row_counts
```

Every single-measure distribution item contains stable machine key, display label, `count`,
drill-down filter, and whether its buckets are mutually exclusive. Error distribution items instead
use the three named counts in their declared schema. Every measure declares which known filters apply. An
inapplicable filter is reported as `not_applicable` for that measure rather than silently changing
its denominator; an unknown or invalid filter rejects the request. Global mapping inventory remains
available when document/class filters are inapplicable, while its in-scope companion measures apply
those filters.

### 5.2 Document Metric list row

Each list row contains identifiers sufficient to request detail and explain missing coverage without
including unbounded child collections:

```text
input_record_id, metric_id, metric_row_id
document title/number
metric name, raw value, normalized-value summary
keyword_concept_id, metric_definition_term_id, term label/module/status
keyword_concept_label, keyword_concept_status
metric_definition_module_id, module_release_id, module_release_status
object_mention_id, subject object_id, reconciliation status
raw_value_range_type, governed_range_mapping_status, canonical_range_type
assertion kind, unit_term_id, quantity_kind_term_id, dimension summary
assertion_kind_resolution_status, assertion_kind_fallback
decision_candidate_id and materialization state
assertion_id, claim_id, class_term_id, class label
lifecycle and four semantic state term IDs
execution/disposition summary
finding_count, highest_severity_term_id
contract capability and projection freshness summaries
silent_gap_warning_count
coverage_state, failed_check_count, warning_check_count
last_processed_at
```

Nullable related identifiers mean “not present” and are accompanied by coverage/check reasons. They
must not be filled with placeholder IDs.

### 5.3 Ontology Metric list row

Each ontology-metric list row contains:

```text
term_id, current_version, term_kind
preferred_label, alternate_label_summary
module_id, governance_status
module_release_id, module_release_status
auto_promotion_provenance_summary
description, scope
raw_value_type, raw_range_type
permitted_unit_term_ids, quantity_kind_summary, dimension_summary
aligned_keyword_concept_count, linked_candidate_count
authorized_occurrence_count, distinct_current_instance_count
occurrences_with_errors, occurrences_with_findings
failed_check_affected_occurrence_count, silent_gap_affected_occurrence_count
contract_definition_state, enabled_capability_summary
last_governed_modify_time
```

The row's occurrence-derived counts apply source authorization before aggregation. Zero is a real
count; unavailable is represented separately and never coerced to zero.

### 5.4 Detail and history

The default detail response returns only current graph objects plus check results. Superseded
outcomes, findings, assertions, evidence, class-resolution decisions, contract revisions, and
relations are fetched through explicitly requested history expansion with their supersession links.

History is ordered by semantic revision/supersession relationships where defined, with timestamps
as presentation metadata rather than the sole definition of current state.

Ontology-metric detail returns its current term/governance graph plus independently paginated
occurrence and instance collections through the named `/occurrences` and `/instances` endpoints.
The `/history` endpoint returns bounded term, label, release, candidate, and contract history.
Term-version history follows governed term/version and release rules; it is not ordered as if it
were semantic assertion history.

### 5.5 Error and partial-data behavior

Failure to load the selected metric or its authorization scope fails the request normally. A missing
semantic child object does not fail the entire detail response; it returns a partial graph and an
explicit check result. Database/query failure must not be reclassified as a semantic finding.

Responses include a `generated_at` timestamp and read-model version. Dashboard and list requests using
the same filter can state that their snapshots differ if concurrent processing changes current rows;
version 1 does not require a long-lived database snapshot across separate HTTP requests.

## 6. Alternatives Considered

### 6.1 Extend the existing Semantic Assertions administration page

Rejected. That page is assertion-first and lifecycle-editing-oriented. It cannot naturally show
metrics with missing assertions, and adding the full metric graph would mix operational diagnosis
with governance mutation.

### 6.2 Add all data to Review Document's Semantic Diagnostics tab

Rejected as the primary solution. That tab is document-scoped and supports review context well, but
it cannot provide corpus-wide coverage analysis, class distributions, or metrics that lack current
assertions. It may later deep-link to this page with document/metric context.

### 6.3 Have the browser join existing metrics, assertions, and evidence endpoints

Rejected. Current endpoints do not expose every required object, and client-side fan-out would
create N+1 requests, inconsistent current-state rules, and poor behavior for incomplete graphs.

### 6.4 Build a generic ontology graph explorer first

Rejected for this increment. The metric vertical slice has concrete cardinality, identity,
comparison, and lossless-processing rules. A generic graph browser would either erase those
semantics or require speculative abstractions before other artifact families are implemented. This
metric-scoped page still labels ontology-born, corpus-level, and record-born entities explicitly so
its terminology can be evaluated before any later generalization.

### 6.5 Persist a denormalized analysis table

Rejected initially. Current tables and projections are authoritative, while a new stored copy would
introduce refresh and invalidation semantics. A materialized projection may be proposed later only
if measured query performance cannot meet the page's bounded latency targets.

### 6.6 Use one metric table with a Document/Ontology filter

Rejected. An occurrence and a governed metric definition have different identities, lifecycles,
columns, zero-row meanings, and cardinalities. One polymorphic table would either hide ontology
metrics with no occurrences or fabricate document columns for terms. Separate peer views make the
angle and row grain explicit while preserving cross-navigation.

### 6.7 Compute dashboard totals from rows loaded in the browser

Rejected. Pagination would make totals incomplete, authorization could be applied inconsistently,
and assertion convergence would cause occurrence/instance double counting. Dashboard measures are
server-side, versioned read-model outputs.

## 7. Implementation Sequence

### Phase 0 — Verify data contracts and establish a baseline

1. Run the user's clean-and-reprocess verification plan or use its completed report when available.
2. Record live counts for metric occurrences, current support links, assertions, required outcomes,
   findings, keyword concepts/alignments, metric definitions by governance status, subject objects,
   decision candidates by status, class decisions, claims, contracts/capabilities, unresolved
   unit/quantity chains, projections, and relations by input record.
3. Confirm metric identifier uniqueness and the authoritative assertion redirect/current-claim
   traversal in shipped code.
4. Define the metric adapter's required stage set as a reusable server contract; do not duplicate a
   frontend list of stages.
5. Document expected historical `not_processed_current_writer` cases separately from invariant
   failures.
6. Establish numeric p95 latency and maximum-query-count budgets for dashboard, both lists, both
   detail shapes, history, occurrence/instance expansion, and peer requests against a recorded
   representative corpus size. This ADR cannot move to Accepted until Phase 3 reports results
   against those budgets.
7. Reconcile observed behavior with the manual's run-failure, blocked-claim, recorded-degradation,
   and silent-gap catalog, including any disagreement between document-stage status and semantic
   outcome status. Record the current behavior rather than choosing one source silently.
8. Verify the deployed current-term selector and confirm `metric_definition` is the authoritative
   stored kind for Ontology Metric View; record any legacy aliases as migration exceptions rather
   than widening the predicate silently.
9. Define the dashboard error-presence policy, canonical error-type vocabulary, equivalent-signal
   deduplication map, filter denominators, and expected arithmetic identities before UI work.

### Phase 1 — Add the read API and deterministic checks

1. Implement typed dashboard, document-list/detail, ontology-list/detail, history-expansion,
   occurrence/instance-expansion, and peer response models.
2. Implement set-based dashboard/list queries and the current-graph resolver, including the shared
   metric-instance classifier and current ontology-metric selector.
3. Implement and version the checks in DR6, including checks that derive silent gaps where the
   processing pipeline currently writes no finding.
4. Implement and version canonical error-presence and error-type normalization/deduplication from
   DR4.
5. Add required indexes only when query plans on representative data demonstrate a need.
6. Enforce existing authentication and page/API authorization before every aggregation.

### Phase 2 — Add the Home3 page

1. Add the `ontology-metric-analysis` navigation entry and content-panel rendering.
2. Implement the three primary modes: Metric Dashboard, Document Metric View, and Ontology Metric
   View, with independent preserved view state and stable cross-view navigation.
3. Implement the dashboard KPI cards, required charts, exact-value tables, drill-down filters, and
   measure-definition tooltips from DR4.
4. Implement both filterable tables, the eight-tab document detail workspace, and the six-tab
   ontology detail workspace.
5. Reuse governed semantic-state labels and severity presentation from the existing Semantic
   Diagnostics view; centralize shared label definitions rather than copying them.
6. Add explicit population/authority labels for ontology-born, corpus-level, record-born, governed
   non-term, observed-profile, and projection objects.
7. Add contextual navigation to existing correction/review pages without mutation side effects.
8. Add accessible loading, empty, partial, error, unknown-term, blocked-claim, and silent-gap states.
9. Initially enable dashboard, both lists, current detail, checks, canonical peers, and governed
   navigation. Gate fallback peer channels, raw JSON inspection, and superseded-history UI
   independently until their bounded behavior and access controls pass verification.

### Phase 3 — Add bounded peer analysis and verify at scale

1. Implement class-first peer retrieval with separate, labeled fallback channels.
2. Verify pagination, truncation metadata, stable ordering, and continuation cursors.
3. Test representative complete, finding-bearing, historical-unprocessed, incomplete, and failed
   metric graphs.
4. Measure dashboard, both list/detail shapes, drill-down, history, and peer latency against the
   available corpus and the ADR `2026081701` caps before enabling the page broadly.

## 8. Verification and Acceptance Criteria

### 8.1 Correctness

* A metric with a complete lossless graph resolves through evidence to its current assertion,
  canonical claim, ontology class, current contract, active outcomes/findings, and source evidence;
  its name also resolves through keyword concept/alignment to the governed metric definition, and
  its subject resolves through an object mention to an object node.
* A metric with semantic findings remains visible and is labeled completed with findings, not
  failed.
* Deferred and rejected candidates remain visible as blocked claims and are not misclassified as
  historical unprocessed rows or silently fabricated assertions.
* A historical metric not processed by the current writer is distinguishable from a current-writer
  invariant failure.
* A deliberately removed support link or required stage outcome produces the expected failed check
  without hiding the raw metric.
* A metric with no value is distinguishable from an absent metric.
* Ambiguous/provisional class decisions expose alternatives and do not present a candidate as an
  authoritative resolved class.
* An auto-promoted metric definition is labeled usable but unreviewed; it is not presented as
  released or human-approved.
* An unresolved unit/quantity chain, assertion-kind fallback, identity-only contract, uncontrolled
  term field, or stale projection produces a visible warning even when no persisted finding exists.
* Governed vocabulary, corpus-level identity, record-born data, observed profiles, and projections
  are visibly distinguished and retain their different authority/lifecycle semantics.
* Same-class peers precede and remain visually separate from fallback candidates.
* Superseded history never appears as current unless explicitly requested as history.
* Document Metric View returns every authorized `kb.metrics` occurrence, including occurrences with
  no governed term or assertion; Ontology Metric View returns every current authorized
  `metric_definition` term, including terms with zero occurrences.
* Cross-view navigation resolves the same `metric_definition_term_id` in both directions and
  preserves each view's independent filter/sort/cursor state.
* Per-ontology-metric instance counts use the occurrence-derived
  `(ontology_metric_term_id, current_assertion_id)` relation, deduplicate convergence, never infer
  membership from `instance_of_term_id`, expose cross-definition convergence, and exclude
  unauthorized supporting occurrences.
* Total occurrence count equals the authorized current `kb.metrics` population for the filter;
  total instance count deduplicates converged occurrences and excludes superseded/redirected
  assertion revisions and source-unanchored assertions; mixed-authority assertions count once when
  authorized evidence anchors them without revealing unauthorized evidence; total ontology-metric
  count uses distinct current `metric_definition` term IDs.
* With-errors plus without-detected-errors equals total occurrences for one dashboard snapshot, and
  no-error occurrences with warnings/silent gaps remain a deduplicated, explicitly defined subset
  of without-detected-errors.
* Global mapping-status charts count every mapping-table row and declare occurrence filters
  inapplicable; in-scope mapping charts count each referenced mapping row once; affected-occurrence
  series use a third, separately labeled denominator.
* Error-type totals deduplicate equivalent raw flags, findings, candidate reasons, failed outcomes,
  and failed checks by occurrence/type while allowing one occurrence to contribute to different
  error types; conflicting source severities resolve to the policy-defined highest severity while
  all source signals remain inspectable.

### 8.2 Security and safety

* Unauthorized users cannot load the page or its analysis API.
* GET requests perform no writes, retries, reprocessing, or LLM calls.
* Immutable claim identity and class-resolution tables are never offered edit/delete controls.
* Raw payloads, evidence quotes, and processing details follow the same access policy as their
  source documents.

### 8.3 Performance and accessibility

* Dashboard and list queries are server-paginated/filter-aware where applicable and do not issue
  per-row queries.
* Detail and peer collections respect the caps in DR9 and report truncation.
* Filters, table rows, tabs, drawers, badges, and navigation actions are keyboard accessible.
* State meaning remains understandable without color, and unknown governed terms remain visible.

### 8.4 Tests

Implementation includes:

* Go unit tests for coverage classification, blocked-claim precedence, every integrity check,
  metric-instance classification, ontology-metric current-term selection, error-presence policy,
  error-type normalization/deduplication, and dashboard arithmetic identities;
* database integration tests for current traversal, supersession, missing/duplicate links, outcome
  cardinality, active finding consistency, name/concept/term alignment, subject reconciliation,
  candidate continuity, class/claim alignment, unit/quantity/dimension resolution, term governance,
  contract capability, projection freshness, bounded peers, per-term instance membership,
  converged occurrences, differing metric-definition/class IDs, cross-definition convergence, and
  authorization-filtered supporting evidence, including unauthorized-only, mixed-authority,
  filtered, and source-unanchored class/claim-only assertions;
* API authorization-before-aggregation, dashboard filter/denominator, both-list filtering/sorting,
  cursor, zero-occurrence ontology term, unresolved document metric, drill-down equivalence,
  global/in-scope/affected mapping counts, ontology occurrence/instance/history pagination,
  equivalent error signals with differing severity/source, one occurrence with multiple error
  types, no-error warning membership, partial-data, and error tests;
* Svelte tests for dashboard cards/charts/tables/drill-down, both metric views, independent view
  state, cross-view navigation, all document and ontology detail tabs, population/authority labels,
  warnings, blocked claims, silent gaps, missing states,
  contextual navigation, and accessibility semantics;
* `svelte-check` and relevant frontend test suites; and
* authenticated browser verification when a supported development/CI authentication path exists,
  with any current authentication limitation recorded rather than bypassed.

## 9. Consequences

### 9.1 Positive

* Operators can understand one metric's complete semantic lifecycle without manual SQL or
  cross-page ID correlation.
* Document Metric View answers what documents stated, while Ontology Metric View answers what the
  governed vocabulary knows; zero-occurrence terms and unresolved occurrences are visible without
  forcing unlike entities into one table.
* The dashboard makes corpus shape and error/mapping distributions visible while retaining exact,
  drillable counts and measure definitions.
* Lossless-processing invariants become observable at the same object boundary users investigate.
* Historical lack of processing is separated from actual corruption or execution failure.
* Ontology classes, contracts, findings, relations, and evidence become explainable from the source
  occurrence that created them.
* Users can distinguish reusable Metric Ontology vocabulary from document values, lexical/object
  identities, processing records, observed profiles, and rebuildable projections.
* Blocked claims and silent gaps become visible alongside persisted findings instead of being
  mistaken for clean processing or missing data.
* Existing governance pages remain focused and reusable.

### 9.2 Costs and risks

* The composed read model joins several large and append-only tables and requires disciplined query
  planning, pagination, and current-state resolution.
* Maintaining two list grains and several dashboard measures adds API/test surface. Shared
  classifiers, versioned measure definitions, and arithmetic invariants are required to prevent
  the views and charts from drifting.
* Error deduplication is policy-bearing: changing equivalence between raw flags, findings,
  candidate reasons, outcomes, and failed checks can change chart totals even when source rows do
  not. The dashboard therefore exposes its error-policy version.
* Coverage classification can mislead if writer-version or required-stage metadata is incomplete;
  conservative warning states and versioned rules mitigate this.
* Some diagnostics are derived because the current pipeline writes no finding for them. Versioned
  check rules and explicit “derived warning” labels prevent them from masquerading as persisted
  processing facts.
* A dense detail workspace can overwhelm users; progressive disclosure and metric-first labeling
  mitigate this without hiding diagnostics.
* The page may expose gaps in current APIs or projections that require backend work before the UI can
  be complete. It must show partial truth explicitly rather than filling gaps with client inference.

## 10. Relationship to Earlier Decisions

### ADR `2026081701`

This ADR implements the metric-first class/instance traversal and bounded class-first peer behavior
required by DR13. It does not change metric class identity, canonical claim identity, contracts,
relations, redirect semantics, or comparison rules.

### ADR `2026081801`

This ADR exposes the lossless raw occurrence, represented assertion, independent state axes,
processing outcomes/findings, evidence, and completeness behavior required by DR6, DR8, and DR11.
Its coverage label is a read-model classification and does not alter binary execution status.

### ADR `2026082003`

Dashboard mapping-triage navigation remains the shortest operational path from a failed-pipeline
row to Resolve Metric Range Types. Metric Ontology Analysis is the deeper diagnostic destination for
understanding a metric's semantic graph. Neither page automatically reprocesses a document.

### Metric Ontology user manual v1.2

The manual is authoritative for the user-facing boundary and terminology adopted here: Metric
Ontology means governed measurement vocabulary rather than a measurement store; surrounding
objects belong to ontology-born, corpus-level, or record-born populations; governed-term and metric
processor lifecycles are distinct; and run failures, blocked claims, recorded degradations, and
silent gaps require different presentation. This ADR turns those concepts into page, API, check,
and navigation decisions. When live implementation evidence contradicts a point-in-time manual
observation, the API reports the live fact and the documentation must be reconciled rather than
hard-coding the observation.

## 11. Deferred Questions

* Whether measured scale requires a materialized analysis projection after the set-based API is
  profiled.
* Whether the page should later support saved filter sets or export of a filtered diagnostic report.
* Whether a future generic ontology explorer can reuse the metric read-model patterns after another
  artifact family has validated them.
* Whether contextual destinations should accept stable pre-applied filters once those contracts are
  defined.
* Whether and how the semantic retry queue will gain a production consumer, and how that mechanism
  will coexist with candidate backlog re-normalization; this page must not conflate them.
* Whether `value_type` and `range_type` on governed terms will gain controlled vocabularies; until
  then this page treats them as unnormalized descriptive fields.
* Which governed workflow will own auto-promoted-term review, class ambiguity/conflict, unresolved
  unit/quantity links, assertion-kind fallback, and direct semantic-finding triage.
