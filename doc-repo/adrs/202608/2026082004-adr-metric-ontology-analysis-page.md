# ADR 2026082004 — Metric Ontology Analysis Page

**Date:** 2026-08-20 \
**Status:** Proposed \
**Component:** ChenWeb — Home3 frontend, metric semantic-analysis read API, ontology diagnostics, and source-evidence navigation \
**Authors:** Chen Ding (with Codex) \
**Related:** ADR `2026081701` (ontology object classes, metric instances, and semantic relations), ADR `2026081801` (lossless semantic processing), ADR `2026082003` (dashboard mapping-triage navigation), handoff `2026082003` (current implementation and verification status) \
**Tags:** frontend, metrics, ontology, semantic assertions, findings, evidence, analysis, diagnostics

## 1. Change Log

* 2026/08/20 — Initial decision. Defines a read-only frontend page for viewing, checking, and
  analyzing metric occurrences together with their ontology-related objects and processing history.

## 2. Decision Summary

ChenWeb will add a Home3 **Metric Ontology Analysis** page that presents each raw metric occurrence
and its current semantic graph as one explainable unit.

The page starts from `kb.metrics`, not from an assertion or ontology term. For each occurrence it
shows the active supporting evidence link, current semantic assertion and canonical claim, ontology
class and current contract, independent semantic state axes, class-resolution decision, processing
outcomes and findings, related and same-class assertions, and source provenance. Missing links are
shown as explicit integrity-check results rather than causing the metric to disappear.

A server-side read model composes this graph. The browser must not reconstruct it by issuing an
unbounded set of per-row requests or by inferring current state from append-only history. List and
summary responses remain bounded; expensive peer, history, and relation data load only when a user
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

### 3.2 Current implementation status constrains the first release

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

### 3.3 “View,” “check,” and “analyze” are different user jobs

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

Add a nav-gated Home3 page named **Metric Ontology Analysis**. Its stable navigation identifier is:

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
  inputRecordId?: number;
  metricId?: string;
  assertionId?: number;
  classTermId?: string;
};
```

Context preselects or filters the page but never bypasses authorization. The page also works without
context as a corpus-level explorer.

Every summary, list, detail, history, and peer query is restricted to source records the caller may
view before aggregation. Counts, peer totals, and class distributions must not reveal unauthorized
records.

### 4.2 DR2 — Use a server-composed read model

Add a read-only API namespace:

```text
GET /api/v1/kb/metric-ontology-analysis/summary
GET /api/v1/kb/metric-ontology-analysis/metrics
GET /api/v1/kb/metric-ontology-analysis/metrics/:input_record_id/:metric_id
GET /api/v1/kb/metric-ontology-analysis/metrics/:input_record_id/:metric_id/history
GET /api/v1/kb/metric-ontology-analysis/metrics/:input_record_id/:metric_id/peers
```

The composite `(input_record_id, metric_id)` identifies one metric occurrence. No endpoint may
select an occurrence using `metric_id` alone unless a later decision proves and documents global
uniqueness. The server returns a conflict/integrity error if the composite unexpectedly resolves to
multiple raw metric rows; it never silently selects the first row.

The API composes existing authoritative tables and projections; it does not create a second
persistent source of truth. The metric detail response is organized into typed sections:

```text
source_metric
coverage
checks[]
current_evidence
current_assertion
canonical_claim
ontology_class
current_contract
class_resolution
processing_outcomes[]
processing_findings[]
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

### 4.3 DR3 — Define the canonical current traversal explicitly

For a metric occurrence, the API resolves current state in this order:

```text
kb.metrics (input_record_id, metric_id)
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

The diagnostic branches are:

```text
metric -> kb.semantic_processing_outcomes (active, artifact/stage scoped)
       -> kb.semantic_processing_findings (active children)

metric -> latest applicable kb.ontology_class_resolution_decisions
       -> kb.ontology_class_resolution_alternatives

assertion -> kb.assertion_relations -> related current assertions
class     -> bounded current same-class assertions -> their active evidence
```

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

### 4.4 DR4 — Return explicit coverage and integrity checks

Every list row and detail response carries a versioned, machine-readable coverage state:

```text
complete
completed_with_findings
not_processed_current_writer
incomplete
execution_failed
coverage_unknown
```

This is a read-model classification, not a new persisted execution or assertion status. It must be
derived from source presence, writer-era/version evidence where available, execution status,
adapter-declared required stages, and the checks below. It must never convert ADR `2026081801`'s
binary execution status into a third stored status.

Coverage states are mutually exclusive and evaluated in this order:

1. `execution_failed` when the current applicable outcome records a genuine failed execution;
2. `not_processed_current_writer` when provenance proves the occurrence predates the current
   writer or its cutover promise and the absent graph elements are expected;
3. `incomplete` when one or more invariant checks fail;
4. `completed_with_findings` when required processing completed, required checks pass, and active
   findings exist;
5. `complete` when required processing completed, required checks pass, and no active findings
   exist; or
6. `coverage_unknown` when absence cannot be classified because required writer/cutover provenance
   is unavailable.

Warnings may accompany any state but do not independently determine coverage. A failed check takes
precedence over findings, while a proven current execution failure takes precedence over missing
downstream graph elements caused by that failure.

Initial checks are:

| Check | Pass condition | Failure meaning |
|---|---|---|
| `metric_support_link_count` | Exactly one current supporting evidence link for the metric occurrence. | Lossless metric cardinality is incomplete or duplicated. |
| `assertion_current_resolution` | The link resolves to one current assertion after redirects/claim projection. | The semantic object is missing or points to stale identity. |
| `required_stage_outcomes` | Exactly one active outcome exists for every metric-adapter required stage. | Processing coverage is incomplete. |
| `outcome_finding_summary` | Active child count and highest severity agree with the outcome summary. | The diagnostic projection is inconsistent. |
| `active_finding_parent` | Every active finding belongs to an active outcome. | Persistence invariant is violated. |
| `class_reference` | Class-bearing states have a stable `instance_of_term_id`. | Class state and class identity disagree. |
| `claim_class_alignment` | Assertion class and canonical claim class agree when both are present. | Claim or assertion identity is inconsistent. |
| `raw_snapshot_alignment` | The assertion snapshot fingerprint matches its referenced source occurrence revision when the required revision data exists. | Raw history may not describe the occurrence used for normalization. |
| `contract_reference` | A normalization contract reference resolves and belongs to the assertion's class. | Audit provenance is invalid. |
| `relation_targets` | Relation endpoints resolve through current redirects and are not self-relations. | Relation history or projection is invalid. |

Each result contains `check_id`, `status`, `severity`, `summary`, and stable object references. Check
status is one of `pass`, `warning`, `fail`, or `not_applicable`. A check uses `warning`, not `fail`,
when the system can prove the occurrence predates the current writer and no cutover promise covered
it. If the system cannot prove whether absence is historical or erroneous, it reports `warning`
with an explicit reason and classifies coverage as `coverage_unknown`; it does not guess.

Checks are deterministic server rules with a version returned in the API. They are diagnostic and
must not mutate, repair, retry, or reprocess data as a side effect of a GET request.

### 4.5 DR5 — Use a summary, a metric table, and a detail workspace

The page has three levels.

**Summary strip**

Shows disjoint totals using the exact coverage identifiers: complete without findings, completed
with findings, not processed by the current writer, incomplete, execution failed, and coverage
unknown. Secondary distributions show class identity, mapping, value, conformance, finding
severity, and top classes. Every number is computed over the current filter scope, and the response
identifies that scope.

**Metric table**

One row represents one raw metric occurrence. Columns are:

* document and metric name;
* raw value and normalized value;
* ontology class label and stable term ID;
* assertion lifecycle;
* class, mapping, value, and conformance states;
* processing disposition, finding count, and highest severity;
* coverage/check state; and
* last semantic processing time.

The table supports server-side filtering, sorting, and cursor pagination. Initial filters cover
document, metric text/ID, class, lifecycle, four state axes, disposition, finding term, severity,
execution status, coverage state, and “has failed check.” Filters use stable machine identifiers in
API requests and human-readable governed labels in the UI.

**Detail workspace**

Opening a row shows six tabs:

1. **Metric & Source** — complete raw metric fields, document identity, evidence quote, line spans,
   extraction run, model/prompt, and a link to the source/review context.
2. **Assertion & Value** — canonical claim, assertion revision/lifecycle, raw snapshot, normalized
   literal, units/quantity kind, four state axes, confidence, and processing error summary.
3. **Class & Contract** — stable class identity, label/version, definition state, current immutable
   contract revision, capabilities, validation results, and class-resolution method/alternatives.
4. **Processing** — required stages, active outcomes, all active typed findings, execution status,
   disposition, severity, retry state, dependency/input fingerprints, and superseded-history access.
5. **Relations & Peers** — governed assertion relations and bounded same-class peers with their
   source metrics and warning states. Canonical-class results are separated from structural,
   similarity, or LLM fallback channels.
6. **Checks & Provenance** — all integrity checks, object IDs, timestamps, actors, versions, and an
   inspectable graph path explaining how the displayed object was resolved.

Raw JSON may be available behind an “Inspect data” affordance, but it is supplemental. The primary
presentation uses labels, field definitions, and explicit missing-state messages.

### 4.6 DR6 — Preserve independent meanings in presentation

The page must not compress independent states into one red/green judgment.

At minimum it displays separately:

* execution status;
* coverage/check status;
* assertion lifecycle;
* class identity and class-definition state;
* mapping resolution;
* value state;
* conformance state;
* processing disposition and findings;
* evidence role; and
* relation/comparison result.

“Completed with findings” means successful execution with one or more semantic findings. It must
not be labeled “failed.” A represented assertion must not be presented as accepted, and a warning
must not hide the source metric. A missing metric value must remain distinguishable from an absent
metric occurrence.

Colors supplement text and icons; they never carry meaning alone. Every badge has a stable label and
tooltip/description. Unknown governed terms render using a safe fallback label plus the raw term ID
rather than disappearing.

### 4.7 DR7 — Bound analysis and peer expansion

Summary and list queries run entirely on the server and are filter-aware. The initial list page size
is 50 and the maximum is 200. Detail loads only for the selected metric.

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

### 4.8 DR8 — Keep correction in existing governed workflows

Version 1 is read-only. It may offer contextual navigation actions:

| Condition | Destination |
|---|---|
| Unresolved or ambiguous metric range mapping | Resolve Metric Range Types |
| Assertion lifecycle requires governed review | Semantic Assertions |
| Evidence or source text needs inspection | Review Document/source viewer |
| Retry state needs inspection | Semantic Retry Queue |

Navigation passes only stable context supported by the destination. If a destination cannot safely
accept a filter, it opens unfiltered and explains what the operator should locate, following the
same conservative rule as ADR `2026082003`.

The page does not provide “repair all,” automatic reprocessing, direct SQL-like editing, or hidden
mutation after navigation. In particular, it does not claim that scheduling a semantic retry will
execute it: handoff `2026082003` confirms the retry queue currently has no production caller of
`Claim` and therefore no drain.

### 4.9 DR9 — Make implementation status visible in the page

The page header includes a compact data-coverage notice derived from runtime facts:

* enabled metric writer mode and adapter version;
* adapter conformance-suite version and last verified result;
* selected scope's total metric count and current-writer processed count;
* the check-rule/read-model version; and
* whether results include historical metrics not processed by the current writer.

This notice prevents a clean pilot document from being misread as proof of full-corpus completeness.
It is not hard-coded to record 416 or to the handoff's counts; those facts are historical context,
while the page reports live state.

## 5. API Contract Requirements

### 5.1 List row

Each list row contains identifiers sufficient to request detail and explain missing coverage without
including unbounded child collections:

```text
input_record_id, metric_id, metric_row_id
document title/number
metric name, raw value, normalized-value summary
assertion_id, claim_id, class_term_id, class label
lifecycle and four semantic state term IDs
execution/disposition summary
finding_count, highest_severity_term_id
coverage_state, failed_check_count, warning_check_count
last_processed_at
```

Nullable related identifiers mean “not present” and are accompanied by coverage/check reasons. They
must not be filled with placeholder IDs.

### 5.2 Detail and history

The default detail response returns only current graph objects plus check results. Superseded
outcomes, findings, assertions, evidence, class-resolution decisions, contract revisions, and
relations are fetched through explicitly requested history expansion with their supersession links.

History is ordered by semantic revision/supersession relationships where defined, with timestamps
as presentation metadata rather than the sole definition of current state.

### 5.3 Error and partial-data behavior

Failure to load the selected metric or its authorization scope fails the request normally. A missing
semantic child object does not fail the entire detail response; it returns a partial graph and an
explicit check result. Database/query failure must not be reclassified as a semantic finding.

Responses include a `generated_at` timestamp and read-model version. Summary and list requests using
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
semantics or require speculative abstractions before other artifact families are implemented.

### 6.5 Persist a denormalized analysis table

Rejected initially. Current tables and projections are authoritative, while a new stored copy would
introduce refresh and invalidation semantics. A materialized projection may be proposed later only
if measured query performance cannot meet the page's bounded latency targets.

## 7. Implementation Sequence

### Phase 0 — Verify data contracts and establish a baseline

1. Run the user's clean-and-reprocess verification plan or use its completed report when available.
2. Record live counts for metric occurrences, current support links, assertions, required outcomes,
   findings, class decisions, claims, contracts, and relations by input record.
3. Confirm metric identifier uniqueness and the authoritative assertion redirect/current-claim
   traversal in shipped code.
4. Define the metric adapter's required stage set as a reusable server contract; do not duplicate a
   frontend list of stages.
5. Document expected historical `not_processed_current_writer` cases separately from invariant
   failures.
6. Establish numeric p95 latency and maximum-query-count budgets for summary, list, detail, history,
   and peer requests against a recorded representative corpus size. This ADR cannot move to
   Accepted until Phase 3 reports results against those budgets.

### Phase 1 — Add the read API and deterministic checks

1. Implement typed list, summary, detail, history-expansion, and peer response models.
2. Implement set-based list/summary queries and the current-graph resolver.
3. Implement and version the checks in DR4.
4. Add required indexes only when query plans on representative data demonstrate a need.
5. Enforce existing authentication and page/API authorization.

### Phase 2 — Add the Home3 page

1. Add the `ontology-metric-analysis` navigation entry and content-panel rendering.
2. Implement the summary strip, filterable metric table, and six-tab detail workspace.
3. Reuse governed semantic-state labels and severity presentation from the existing Semantic
   Diagnostics view; centralize shared label definitions rather than copying them.
4. Add contextual navigation to existing correction/review pages without mutation side effects.
5. Add accessible loading, empty, partial, error, and unknown-term states.
6. Initially enable summary, list, current detail, checks, canonical peers, and governed navigation.
   Gate fallback peer channels, raw JSON inspection, and superseded-history UI independently until
   their bounded behavior and access controls pass verification.

### Phase 3 — Add bounded peer analysis and verify at scale

1. Implement class-first peer retrieval with separate, labeled fallback channels.
2. Verify pagination, truncation metadata, stable ordering, and continuation cursors.
3. Test representative complete, finding-bearing, historical-unprocessed, incomplete, and failed
   metric graphs.
4. Measure summary, list, detail, and peer latency against the available corpus and the ADR
   `2026081701` caps before enabling the page broadly.

## 8. Verification and Acceptance Criteria

### 8.1 Correctness

* A metric with a complete lossless graph resolves through evidence to its current assertion,
  canonical claim, ontology class, current contract, active outcomes/findings, and source evidence.
* A metric with semantic findings remains visible and is labeled completed with findings, not
  failed.
* A historical metric not processed by the current writer is distinguishable from a current-writer
  invariant failure.
* A deliberately removed support link or required stage outcome produces the expected failed check
  without hiding the raw metric.
* A metric with no value is distinguishable from an absent metric.
* Ambiguous/provisional class decisions expose alternatives and do not present a candidate as an
  authoritative resolved class.
* Same-class peers precede and remain visually separate from fallback candidates.
* Superseded history never appears as current unless explicitly requested as history.

### 8.2 Security and safety

* Unauthorized users cannot load the page or its analysis API.
* GET requests perform no writes, retries, reprocessing, or LLM calls.
* Immutable claim identity and class-resolution tables are never offered edit/delete controls.
* Raw payloads, evidence quotes, and processing details follow the same access policy as their
  source documents.

### 8.3 Performance and accessibility

* List and summary queries are server-paginated/filter-aware and do not issue per-row queries.
* Detail and peer collections respect the caps in DR7 and report truncation.
* Filters, table rows, tabs, drawers, badges, and navigation actions are keyboard accessible.
* State meaning remains understandable without color, and unknown governed terms remain visible.

### 8.4 Tests

Implementation includes:

* Go unit tests for coverage classification and every integrity check;
* database integration tests for current traversal, supersession, missing/duplicate links, outcome
  cardinality, active finding consistency, class/claim alignment, and bounded peers;
* API authorization, filtering, sorting, cursor, partial-data, and error tests;
* Svelte tests for filters, summary/table selection, all six detail tabs, warnings, missing states,
  contextual navigation, and accessibility semantics;
* `svelte-check` and relevant frontend test suites; and
* authenticated browser verification when a supported development/CI authentication path exists,
  with any current authentication limitation recorded rather than bypassed.

## 9. Consequences

### 9.1 Positive

* Operators can understand one metric's complete semantic lifecycle without manual SQL or
  cross-page ID correlation.
* Lossless-processing invariants become observable at the same object boundary users investigate.
* Historical lack of processing is separated from actual corruption or execution failure.
* Ontology classes, contracts, findings, relations, and evidence become explainable from the source
  occurrence that created them.
* Existing governance pages remain focused and reusable.

### 9.2 Costs and risks

* The composed read model joins several large and append-only tables and requires disciplined query
  planning, pagination, and current-state resolution.
* Coverage classification can mislead if writer-version or required-stage metadata is incomplete;
  conservative warning states and versioned rules mitigate this.
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

## 11. Deferred Questions

* Whether measured scale requires a materialized analysis projection after the set-based API is
  profiled.
* Whether the page should later support saved filter sets or export of a filtered diagnostic report.
* Whether a future generic ontology explorer can reuse the metric read-model patterns after another
  artifact family has validated them.
* Whether contextual destinations should accept stable pre-applied filters once those contracts are
  defined.
* Whether and how the semantic retry queue will gain a production drain; this page must not imply
  one exists before that separate decision is made.
