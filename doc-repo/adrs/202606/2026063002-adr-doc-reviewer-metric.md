# ADR 2026063002 — Metric Document Reviewer

**Date:** 2026-06-30 \
**Status:** Accepted \
**Component:** ChenWeb — `server/api/doc-reviews`, `server/api/doc-processing` (metric indexing, object graph), `prompts` \
**Authors**: Chen Ding\
**Tags**: Document Reviewer, Metric, Cross-Document Consistency

## Change Logs
* 2026/06/30, ADR Created
* 2026/06/30, Fleshed out after codebase review: resolved the initial DR1
  "hybrid search" mechanism as precomputed `hybrid_search` edges (historical;
  superseded on 2026/07/01), added Data Formats, Migrations (none), Environment
  Variables, Code Changes, Operational Behaviors, Consequences, Tests, and
  Documentation Impact. Status moved Proposal -> Accepted.
* 2026/06/30, Branch A correctness fix: `hybrid_search` edges are directional (written
  source→target at index time, never refreshed retroactively), so the doc metric is on
  the `target` side of any edge created by a document indexed later. Branch A now unions
  **outbound** (M=source) and **inbound** (M=target) edges, resolving the opposite
  endpoint as the match and excluding any endpoint with `record_id = record_id`. Added a
  `LoadConnectionsByTarget` loader and inbound/cross-direction-dedup tests.
* 2026/07/01, Branch A migrated to **on-the-fly** (supersedes the precomputed-edge reading
  of DR1 and the 2026/06/30 correctness fix): semantic metric↔metric similarity is no
  longer materialized as `hybrid_search` / `semantically_related` edges. Indexing
  (`metric_indexing.go`) stops writing them; Branch A calls
  `docprocessing.FindSimilarArtifactsOnTheFly` (same lexical + pgvector RRF acceptance
  policy) per doc metric at review time. Live search is always fresh and direction-free, so
  the A1/A2 inbound/outbound union and `LoadConnectionsByTarget` are no longer used by this
  reviewer. Rationale: any artifact is already discoverable by hybrid search over
  `kb.search_artifacts`; a stored snapshot only duplicates that computation and goes stale
  as the corpus grows.
* 2026/07/03, ADR 2026070201 (AR2/AR3/AR5) implemented for this reviewer: prompt v2
  (`prompt-review-metrics-v2.md` — recall stance, broadened checks, source authority,
  rank instead of raw RRF confidence, insufficient-information outlet, structured
  `related_artifact_id`/`related_record_id` cross-references), window-first input
  layout (canonical scheduler window as cacheable prefix), window-grouped
  seed/stagger execution, and tool-use with `get_artifact_context`.
* 2026/07/03, ADR 2026070201 AR6 (Stage 5) implemented: object-anchored
  missing-metric detection runs as a separate sibling aspect
  (`metrics_completeness`). It resolves a document metric to canonical objects through
  `kb.artifact_objects` -> `kb.object_nodes`, then loads all metrics connected to those
  object nodes through `kb.artifact_connections` `relation_method='object_id'` /
  `relation_name='belong_to'` edges to build per-object metric rosters.
* 2026/07/05, synced with implemented object-centric design (ADR 2026070101):
  metrics, provisions, and inventory-item extraction now all produce and reconcile
  shared `kb.artifact_objects` / `kb.object_nodes` records; this ADR consumes that
  implemented object-reconciliation contract.
* 2026/07/18, prompt v4 redesigned classification-first: the earlier prompts framed the
  task as conflict-hunting, implicitly assuming a retrieved candidate is either the same
  metric (consistent) or a conflict. v4 makes classification the primary task: each
  candidate is classified `same_consistent` / `same_conflict` / `related_distinct` /
  `unrelated` / `undetermined` (emitted in `analyses[].relationship`), with measurement
  conditions derived from both source contexts (same-name metrics under different
  conditions, e.g. at-rest vs running, are `related_distinct`, not conflicts; candidates
  sharing only an object/category/semantic context are expected, healthy non-matches).
  Only `same_conflict` produces a conflict finding; outlier/currency/pattern checks apply
  only within the same-metric roster. Also fixed the stale `match_via` vocabulary
  (`entity` -> `object_anchor`) and resolved the v4 draft's English-vs-Chinese output
  contradiction in favor of Chinese.
* 2026/07/18, match ordering + LLM cap configuration: matches are now ordered by
  match-source priority — `object_anchor` first, then `metric_category`, then
  `hybrid_search` — with confidence (RRF score) as the tie-break within a source;
  a metric reachable from several branches keeps the highest-priority `via`.
  `MaxMatchesPerMetric` and the per-call LLM cap both truncate this order, so the
  strongest sources reach the LLM first and `match_rank` reflects the priority.
  The per-call LLM cap (previously env `MAX_MATCHES_TO_LLM` only, default 3) is
  now configured via `[doc-reviewer].max_artifacts_passed_to_llm` in
  `ChenWeb/config.local.toml` (config > env > default 3); it is shared by the
  metrics, provisions, inventory-items, and entities artifact reviewers.
* 2026/07/05, clarified the review goal and corrected DR1: for each
  metric-under-review, the reviewer first retrieves relevant cross-document metrics, then
  asks the LLM to review the metric with that context. Object-anchored retrieval is part
  of the `metrics` match search, not only the separate missing-metric reviewer. The old
  document-level entity branch is removed from the reviewer design because it retrieves
  metrics related to entities in the document-under-review, not necessarily metrics
  relevant to the metric-under-review.

## Context
When a document is added to the knowledge base, the system extracts metrics,
entities, relations and other artifacts from the document via the doc processors
(refer to [1]).

These document reviewers assume the document-under-review, identified by `record_id`
(`kb.inputs.id`), has already been processed by the relevant doc processors. The metric
conflict reviewer is configured as `reviewers.metrics` (group P5) in [2]; the
object-anchored missing-metric reviewer is configured as `reviewers.metrics_completeness`
(also group P5).

The object graph consumed by `metrics` and `metrics_completeness` is an implemented
dependency. ADR 2026070101 [8] defines the shared contract: metrics [7], provisions [9],
and inventory items [10] extract artifact objects, reconcile them to canonical
`kb.object_nodes`, and index `object_id` / `belong_to` graph edges.

### How this reviewer differs from every existing reviewer

All ~40 existing review aspects (e.g. `grammar_spelling`, `completeness`,
`standards_compliance`) read the **document's own text**: the prompt-cache scheduler
splits the line file into `per-chunk` or `per-block` units and fans out one LLM call
per unit ([3], `review_cache_scheduler.go`).

The metric reviewers are fundamentally different. They do **not** read the document text
linearly. They consume **already-extracted artifacts** — the document's `kb.metrics`
rows, live search index rows, object graph edges, and object-node rosters — and
cross-reference them against metrics in other documents. They are therefore
**cross-document consistency and completeness** checks, not single-document text reviews.

### Resolving "hybrid search `kb.artifact_connections` by the metric" (DR1)

`kb.artifact_connections` is a graph **edge** table ([4], `connections.go`), not a
searchable index, so it cannot be "hybrid searched" directly. Early versions of this ADR
expected the `extract_metrics` artifact-indexing step to compute, for every metric, its
top semantically-related artifacts across the **entire corpus** and persist them as
edges:

```
source_type = 'metric', source_record_id = <doc>, source_id = <metric artifact id>
relation_method = 'hybrid_search'
relation_name   = 'semantically_related'
target_type     = 'metric' (and other families)
target_record_id / target_id = the matched artifact (often a different document)
confidence      = RRF score, provenance = {cosine_sim, lexical_score, ...}
```

As of 2026/07/01 (see change log), that design is no longer current: the reviewer does
**not** read precomputed edges for Branch A. Semantic metric↔metric similarity is
computed **live** at review time via
`docprocessing.FindSimilarArtifactsOnTheFly`, which runs the same lexical + pgvector RRF
search and acceptance policy the indexing step used to persist, but returns matches
instead of writing edges. A single search per doc metric finds every semantically related
metric across the corpus regardless of index order, so there is no edge direction to
union and no staleness: `LoadConnectionsByTarget` and the outbound/inbound split are no
longer used by this reviewer. Indexing still hydrates each metric's `search_document` and
embedding into `kb.search_artifacts` so the live search has its inputs.

(Historical note: DR1 originally read precomputed `hybrid_search` / `semantically_related`
edges from `kb.artifact_connections`, and a 2026/06/30 fix unioned outbound + inbound
edges to handle their directionality. Both are superseded by the on-the-fly approach
above.)

Object-anchored matching is a first-class match source for the `metrics` reviewer. For a
metric-under-review, the reviewer resolves the metric's artifact objects through
`kb.artifact_objects` -> `kb.object_nodes`, then loads peer metrics connected to the
same or comparable object nodes through `kb.artifact_connections` object-id edges. This
retrieves metrics that are relevant to the metric-under-review through the object being
measured, rather than through broad document-level co-occurrence.

The old document-entity branch is intentionally removed from this design. It loaded
metrics connected to any entity extracted from the document-under-review and then used
category overlap as a weak attachment heuristic. That path can retrieve metrics that are
document-related but not metric-relevant. If entity-based recall is reconsidered later,
it must be anchored to the metric-under-review's spans, artifact object, or another
artifact-local signal rather than all entities in the document.

The object-anchored missing-metric check remains a separate reviewer aspect,
`metrics_completeness`. It answers a different question: not "does this metric conflict
with matching metrics?", but "does this document omit metrics that peer documents
consistently attach to the same object?".

## Decision
### DR1 — Reviewer logic

The `metrics` reviewer builds, for each metric extracted from the document-under-review,
a list of **matching metrics** from cross-document search sources, then issues one LLM
call per metric that has at least one match. The goal is simple: given a
metric-under-review, find the relevant metrics already in the database, then ask the LLM
to review the metric-under-review with the document context and those related metrics.
Pseudocode:

```text
matches := map[metric] -> []matchingMetric   // keyed by the doc's own metric

# Branch A: metric <-> semantically related metrics, computed LIVE (no materialized edges).
# A single hybrid search per doc metric finds close metrics across the whole corpus regardless
# of when the other document was indexed, so there is no inbound/outbound direction to union.
for each metric M extracted from the document-under-review (kb.metrics WHERE input_record_id = record_id):
   hits := FindSimilarArtifactsOnTheFly(
              selfType='metric', selfID=M.metric_id,
              candidateType='metric', maxLinks=METRIC_REVIEW_MAX_MATCHES)
   resolve each hit -> a kb.metrics row (the matching metric)

   append resolved matches to matches[M]   (deduped by matching metric_id;
                                            same-document hits excluded)

   # Branch B: metric -> metrics sharing a metric category
   for each category key C in M.metric_categories:
      sibling metrics := kb.metrics WHERE metric_categories @> C AND id <> M.id   (corpus-wide)
      append sibling metrics to matches[M]   (deduped, capped)

   # Branch C: object-anchored metrics for the metric-under-review
   objectLinks := kb.artifact_objects ao
      JOIN kb.object_nodes onode ON onode.object_id = ao.object_id
      WHERE ao.source_record_id = record_id
        AND ao.artifact_type = 'metric'
        AND ao.artifact_id = M.metric_id
        AND ao.object_id IS NOT NULL

   for each object node O linked to M:
      peerObjectIDs := O.object_id plus comparable object nodes
                       (same object_type, overlapping normalized_names,
                        reconcile_status <> 'rejected')

      peerEdges := kb.artifact_connections WHERE
         relation_method = 'object_id'
         AND relation_name = 'belong_to'
         AND source_type = 'metric'
         AND target_type = 'object_node'
         AND target_id IN peerObjectIDs

      resolve peerEdges.extra_info.artifact_ids -> kb.metrics rows
      append resolved metrics to matches[M]   (deduped by metric_id;
                                               same-document hits excluded)

# LLM comparison (parallel)
for each metric M in matches where len(matches[M]) > 0:
   launch one LLM call (configured model + prompt) with:
       - the metric under review (M)
       - all matching metrics (deduped, capped at MaxMatchesPerMetric)
   parse findings; tag Pass="P5", Aspect="metrics"
```

LLM calls run through the artifact-review window-grouped executor (bounded by
`REVIEW_MAX_TASKS`); stop requests are honored at each call boundary (refer to [3] and
the doc-processor stop contract).

All Branch A/B/C retrieval happens before the LLM call and before any tool-use loop. The
LLM receives the metric-under-review plus the already-retrieved matching metrics in its
input payload. If `max_tool_turns > 0`, tools are only an optional follow-up mechanism for
additional context; they are not responsible for discovering the Branch C object-anchored
matches.

Dedup/cap/order rules:
- A matching metric is identified by its `metric_id`; duplicates across live hybrid search,
  category siblings, and object-anchored metrics are collapsed. A duplicate keeps the
  highest-priority `match_via` (see next rule).
- `matches[M]` is ordered by match-source priority — `object_anchor` (shares the measured
  object) first, then `metric_category`, then `hybrid_search` — with confidence (RRF
  score) as the tie-break within a source. `match_rank` reflects this order.
- A metric's own record is never a match: matches with `record_id = record_id` are excluded
  so the reviewer is strictly cross-document; same-document near-duplicates are handled by
  the metric deduplication pipeline, not this reviewer. (Intra-document shared-line
  `line-overlapped-artifact` edges are therefore not a match source: line overlap only
  exists within one document.)
- `matches[M]` is capped at `MaxMatchesPerMetric` (default 20) in the priority order above.
- The per-LLM-call cap is `[doc-reviewer].max_artifacts_passed_to_llm`
  (`ChenWeb/config.local.toml`), falling back to env `MAX_MATCHES_TO_LLM`, then 3; it
  truncates the same order.

### DR2 — Separate missing-metric reviewer

The `metrics_completeness` reviewer runs as a sibling P5 aspect. It builds one review
unit per canonical object that the document's metrics attach to, then asks whether the
document appears to be missing metrics that peer documents attach to the same or clearly
comparable object. Pseudocode:

```text
docMetrics := kb.metrics WHERE input_record_id = record_id

# Resolve each doc metric to canonical object nodes.
objectLinks := kb.artifact_objects ao
   LEFT JOIN kb.object_nodes onode ON onode.object_id = ao.object_id
   WHERE ao.source_record_id = record_id
     AND ao.artifact_type = 'metric'
     AND ao.artifact_id IN docMetrics.metric_id
     AND ao.object_id IS NOT NULL

group docMetrics by objectLinks.object_id

for each object node O:
   peerEdges := kb.artifact_connections WHERE
      relation_method = 'object_id'
      AND relation_name = 'belong_to'
      AND source_type = 'metric'
      AND target_type = 'object_node'
      AND target_id = O.object_id

   comparableObjects := kb.object_nodes WHERE
      object_type = O.object_type
      AND object_id <> O.object_id
      AND normalized_names overlap O.normalized_names
      AND reconcile_status <> 'rejected'

   also load peerEdges for comparableObjects
   resolve peerEdges.extra_info.artifact_ids -> kb.metrics rows
   group resolved peer metrics by source document

   if at least one peer document has metrics:
      launch one LLM call with:
         - the object node metadata
         - doc metrics attached to this object
         - peer documents and their metrics for the same/comparable object
      parse findings; tag Pass="P5", Aspect="metrics_completeness"
```

This branch depends on the implemented ADR 2026070101 object contract: metric extraction
persists metric objects with `MetricsProcessor.persistMetricObjects`, object
reconciliation creates or matches `kb.object_nodes`, and metric indexing writes object
edges with `indexArtifactObjectConnections`. Provision and inventory-item processors use
the same shared object model, so peer object nodes are not processor-specific silos.

### DR3 — Prompts
The original prompt was `ChenWeb/prompts/prompt-review-metrics-v1.md`; current
configuration uses `prompt-review-metrics-v4.md` for the `metrics` aspect and
`prompt-review-metrics-missing-v1.md` for `metrics_completeness`. The metric prompt is
classification-first (see 2026/07/18 change log): for every retrieved candidate the model
first classifies the relationship (`same_consistent`, `same_conflict`, `related_distinct`,
`unrelated`, `undetermined`), deriving measurement conditions from both source contexts,
and only `same_conflict` — same metric, same conditions, incompatible
values/units/definitions — produces a conflict finding. All candidates are recorded in the
mandatory `analyses` array regardless of classification. The missing-metric prompt asks
whether the document omits expected metrics for an object compared with peer-document
rosters. Both prompts emit the standard review-finding JSON contract (see Data Formats).

### Alternative Decisions
- **Live hybrid search at review time** (call the metric search path per metric):
  originally rejected, then accepted on 2026/07/01 after precomputed
  `hybrid_search` edges proved stale and directional. This is now Branch A.
- **Pure structural graph walk only** (no use of `hybrid_search` edges): rejected — the
  live hybrid-search result is the semantic match signal; ignoring it would reduce the
  reviewer to category/object co-membership and miss cross-document value conflicts that
  are textually dissimilar.
- **Document-level entity branch:** removed from the reviewer design. It used
  entity->metric edges for all entities extracted from the document-under-review, then
  attached targets by category overlap. That is a weak metric-under-review relevance
  signal compared with live hybrid search, metric category siblings, and object-anchored
  retrieval.
- **New `ReviewStrategy` enum value + scheduler branch**: rejected as unnecessary. A
  reviewer whose `Input` is neither `per-chunk` nor `per-block` is already routed to
  `runReviewersLegacy`, which calls `ReviewDocument` directly. The metric reviewer uses
  that path with `Input = "artifact"`.

### Database Migrations
**None for the reviewer.** The implemented reviewers read existing tables:
`kb.metrics`, `kb.search_artifacts`, `kb.artifact_connections`,
`kb.artifact_objects`, and `kb.object_nodes`; they write findings to the existing
`kb.doc_review_findings` (run-scoped via `run_id`, per ADR 2026062804 [5]). No new
reviewer-owned table, column, or `kb.search_artifacts` partition is required.

The object path consumes the implemented doc-processing object contract: artifact
processors populate `kb.artifact_objects` and `kb.object_nodes`, and indexing writes
`object_id` / `belong_to` edges into `kb.artifact_connections`. The relevant migrations
are owned by ADR 2026070101, not by this reviewer ADR.

### Data Formats

**Doc metric (loaded from `kb.metrics`)** — fields passed to the LLM as the
"metric under review":

```json
{
  "id": 12345,
  "metric_id": "1001_m_7",
  "artifact_id": "1001_m_7",
  "metric_name": "最大工作压力",
  "metric_subject": "管道系统",
  "metric_value": "1.6",
  "metric_unit": "MPa",
  "value_class": "maximum",
  "metric_categories": ["pressure", "pipe-spec"],
  "source_line_spans": ["120:124"]
}
```

**Matching metric** — same shape plus provenance of the match:

```json
{
  "metric": { ... same fields as above ... },
  "source_record_id": 2002,
  "source_filename": "GB_50316_pipe_design.pdf",
  "match_via": "hybrid_search | metric_category | object_anchor",
  "match_rank": 1,
  "source_doc_authority": "standard"
}
```

**Finding output (LLM → `ReviewFinding`)** — the standard review-finding JSON already
used by every reviewer:

```json
{
  "severity": "low|medium|high|critical",
  "finding_type": "issue|observation",
  "title": "Conflicting maximum pressure for pipe system",
  "description": "This document states 1.6 MPa; doc 2002 states 2.5 MPa for the same subject/category.",
  "evidence": "doc 1001 line 120-124 vs doc 2002 metric 2002_m_3",
  "location": "120:124",
  "suggestion": "Reconcile the maximum working pressure or qualify the operating condition.",
  "confidence": 0.0
}
```

The reviewer sets `Pass="P5"` and `Aspect="metrics"` on every finding (defaulting
`finding_type="issue"`, `severity="low"`, and `location` to the doc metric's
`source_line_spans` when the model leaves them empty), mirroring
`grammarSpellingReviewer`.

**Object metric roster (`metrics_completeness`)** — fields passed to the LLM for one
object:

```json
{
  "object": {
    "object_id": "obj_1001_abcd1234",
    "object_name": "pipe system",
    "object_type": "system",
    "description": "..."
  },
  "doc_metrics": [{ "...": "metricView" }],
  "peer_docs": [{
    "source_record_id": 2002,
    "source_filename": "GB_50316_pipe_design.pdf",
    "source_doc_authority": "standard",
    "metrics": [{ "...": "metricView" }]
  }],
  "total_peer_docs": 3,
  "total_peer_metrics": 12,
  "artifact_line_spans": ["120:124"]
}
```

`metrics_completeness` sets `Pass="P5"` and `Aspect="metrics_completeness"` on every
finding, defaulting `finding_type="missing_metric"` and `severity="medium"` when the
model leaves them empty.

### Environment Variables
- `REVIEW_MAX_TASKS` (existing) — bounds reviewer-internal parallelism; reused for the
  per-metric LLM fan-out.
- `METRIC_REVIEW_MAX_MATCHES` (new, optional, default `20`) — cap on matching metrics
  per doc metric.
- `MAX_MATCHES_TO_LLM` (existing, optional, default `3`) — cap on matches included in
  each LLM call payload, shared by all artifact reviewers. Overridden by
  `[doc-reviewer].max_artifacts_passed_to_llm` in `ChenWeb/config.local.toml` when set.
- `METRIC_REVIEW_MAX_METRICS` (new, optional, default `0` = no cap) — cap on the number
  of doc metrics reviewed (safety valve for very metric-heavy documents).
- `METRIC_COMPLETENESS_REVIEW_MAX_OBJECTS` (new, optional, default `0` = no cap) — cap
  on object rosters reviewed by `metrics_completeness`.
- No new model/prompt env vars: model and prompt come from `reviewers.metrics` in [2]
  and `reviewers.metrics_completeness` in [2] via the existing
  `resolveReviewerRuntime` path.

## Implementation

### Code Changes

| File | Change |
|---|---|
| `ChenWeb/server/api/doc-reviews/review-metrics.go` | `metricsReviewer` implements `Reviewer` (`Name()="metrics"`, `Group()="P5"`, `Strategy()=StrategyDocument`). `ReviewDocument` loads the doc's metrics, builds matches from live `FindSimilarArtifactsOnTheFly`, category siblings, and object-anchored metric rosters, hydrates source context, and fans out one LLM call per matched doc metric with window-grouped artifact execution. Tool-use is enabled when configured. |
| `ChenWeb/server/api/doc-reviews/review-metrics-completeness.go` | `metricsCompletenessReviewer` implements the object-anchored missing-metric pass. It resolves doc metric -> `kb.artifact_objects` -> `kb.object_nodes`, loads exact and comparable object metric rosters via `kb.artifact_connections` `object_id`/`belong_to` edges, and fans out one LLM call per object. |
| `ChenWeb/server/api/doc-reviews/review-document.go` | In `NewReviewProcessor`, resolves both `metrics` and `metrics_completeness` P5 runtime/budget/tool config. In `buildReviewers`, appends both artifact reviewers with `cfg.Input="artifact"` so the scheduler routes them to `runReviewersLegacy` -> `ReviewDocument`. |
| `ChenWeb/server/api/doc-processing/extract-metrics.go` | Persists metric object annotations through `MetricsProcessor.persistMetricObjects`, synthesizing a measured object from metric subject fields when the LLM did not return explicit `objects`. |
| `ChenWeb/server/api/doc-processing/artifact_objects.go`, `object_nodes.go`, `object_reconciliation.go` | Normalize artifact objects, reconcile them to existing/new object nodes, and store `kb.artifact_objects` rows with object ids, roles, names, aliases, normalized names, source spans, and reconciliation metadata. |
| `ChenWeb/server/api/doc-processing/metric_indexing.go`, `artifact_object_connection_indexing.go` | Metric indexing writes category edges, shared-line artifact edges, and object-node `belong_to` edges. It no longer writes semantic metric<->metric `hybrid_search` edges; live search uses hydrated `kb.search_artifacts`. |
| `ChenWeb/server/api/doc-processing/extract-provisions.go`, `extract-inventory-items.go` | Provisions and inventory items also persist/reconcile artifact objects under the shared ADR 2026070101 contract, keeping object-node identity reusable across artifact families. |
| `ChenWeb/project_migrations/20260702000002_create_kb_artifact_objects.sql`, `20260702000003_create_kb_object_nodes.sql`, `20260703000001_add_source_record_id_to_kb_artifact_objects.sql`, `20260703000002_add_object_id_connection_partition.sql` | Implement the shared object tables and object-id connection partition consumed by `metrics_completeness`. |
| `ChenWeb/doc-review.local.toml` | `reviewers.metrics` uses `input="artifact"`, `prompt-review-metrics-v2.md`, tool-use with `get_artifact_context`; `reviewers.metrics_completeness` uses `prompt-review-metrics-missing-v1.md`, tool-use with `search_metrics` and `get_artifact_context`. |
| `ChenWeb/prompts/prompt-review-metrics-v2.md` | Metric conflict prompt (DR2, superseding v1). |
| `ChenWeb/prompts/prompt-review-metrics-missing-v1.md` | Object-anchored missing-metric prompt for `metrics_completeness`. |
| `ChenWeb/server/api/doc-reviews/review-metrics_test.go`, `review-metrics-completeness_test.go`; `ChenWeb/server/api/doc-processing/*object*_test.go`, `metric_indexing_test.go` | Tests covering match assembly, completeness rosters, object persistence/reconciliation, object-edge indexing, and live hybrid search. |

The metric reviewers reuse the shared `newDocReviewLLMJSONInput`, `LLMJSONExtractor`,
tool-use loop, artifact-window layout, review logs, and finding normalization used by
the other artifact reviewers.

## Operational Behaviors

- **No metrics / no matches:** if the document has no `kb.metrics` rows, or no metric
  has any cross-document match, `metrics` returns zero findings (logged, not an error).
  If no object has peer metrics, `metrics_completeness` likewise returns zero findings.
- **Dependency:** `metrics` is meaningful after `extract_metrics` has populated
  `kb.metrics`, `kb.search_artifacts`, and the implemented ADR 2026070101 object
  pipeline: metric/provision/inventory object extraction, artifact-object persistence,
  object-node reconciliation, and object `belong_to` indexing. `metrics_completeness`
  consumes the same object graph for missing-metric rosters.
- **Parallelism & stop:** per-metric and per-object LLM calls run under
  `REVIEW_MAX_TASKS`; a user stop request cancels remaining calls at the next boundary
  (`ErrPipelineStopped`).
- **Idempotency:** findings are written under the current `run_id`; a re-run deletes the
  run's prior findings first (existing `PostProcessIndex` behavior, [5]).

## Consequences

**Positive**
- Adds genuine cross-document consistency checking — conflicting values/units/thresholds
  for the same quantity across the corpus — which no text-based reviewer can detect.
- Live hybrid search avoids stale/directional semantic edges while still using the shared
  `kb.search_artifacts` lexical/vector index.
- Object-anchored matching retrieves metrics tied to the same canonical object as the
  metric-under-review, improving relevance over document-level entity co-occurrence.
- Object-anchored completeness catches omissions that conflict checking cannot see:
  missing metrics for the same canonical object when peer documents consistently include
  them.
- Integrates through the existing `runReviewersLegacy`/`ReviewDocument` path with no
  scheduler or schema changes.

**Negative / cost**
- Per-metric live search adds read-time search cost; bounded by `METRIC_REVIEW_MAX_METRICS`
  and `MaxMatchesPerMetric`.
- Per-object completeness fan-out can be large for object-heavy documents; bounded by
  `METRIC_COMPLETENESS_REVIEW_MAX_OBJECTS`.
- Object-anchored recall is bounded by the implemented object extraction/reconciliation
  quality. Metrics without a reconciled `object_id` cannot contribute to object-anchored
  matches or completeness rosters; duplicate object nodes can reduce recall until
  reconciliation links or merges them.

## Tests
- `ReviewDocument` with a doc metric that has one live hybrid-search hit to a
  cross-document metric -> one LLM call, finding tagged `P5`/`metrics`.
- Metric with no matches (no hybrid hits, no category siblings, no object-anchored peer
  metrics) → no LLM
  call, no findings.
- Branch B: two metrics sharing a `metric_categories` key in different documents are
  matched; same-document siblings excluded.
- Branch C: an object-anchored metric in another document is attached to the
  metric-under-review through `kb.artifact_objects` -> `kb.object_nodes` ->
  `kb.artifact_connections`.
- Dedup: a target reachable via both `hybrid_search` and object-anchored branches appears
  once, tagged with the higher-priority `object_anchor` provenance.
- Ordering: matches sort by source priority (`object_anchor` > `metric_category` >
  `hybrid_search`), then confidence within a source.
- Cap: `MaxMatchesPerMetric` truncates in that priority order.
- Live search uses stored query embeddings from `kb.search_artifacts`.
- Metric object persistence writes `kb.artifact_objects` rows and reconciles them to
  `kb.object_nodes`.
- Object-edge indexing writes `object_id` / `belong_to` rows whose `extra_info` carries
  the metric artifact ids attached to the object.
- `metrics_completeness` builds rosters from `kb.artifact_objects` ->
  `kb.object_nodes` -> `kb.artifact_connections` -> `kb.metrics`, excludes the document
  under review from peer docs, and includes comparable object nodes with overlapping
  normalized names.
- Stop request mid-fan-out returns `ErrPipelineStopped`.

## Documentation Impact
- `doc-processor/+CAPSULE.md` [1]: the `review_document` row already covers the review
  pipeline; no pipeline-table change (metrics is a review *aspect*, not a doc processor).
- This ADR is the design record for the reviewer; `prompt-review-metrics-v1.md`–`v3` are
  historical behavior records. Current behavior is split between
  `prompt-review-metrics-v4.md` (`metrics`) and `prompt-review-metrics-missing-v1.md`
  (`metrics_completeness`). The document-review spec [6] should describe these as
  artifact-based cross-document reviewers that use `Input="artifact"` (direct
  `ReviewDocument` path).
- Intentionally left undocumented here: the exact RRF weighting of live hybrid search
  (owned by `metric_indexing.go` / the metric-indexing spec). Object extraction,
  reconciliation, and embedding/lexical matching policy are documented by ADR
  2026070101 and the processor specs referenced below.

## References
- [1] `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md`
- [2] `ChenWeb/doc-review.local.toml`
- [3] `KnowledgeStore/doc-repo/adrs/202606/2026062804-adr-doc-review-run.md` (run model) and `ChenWeb/server/api/doc-reviews/review_cache_scheduler.go` (dispatch)
- [4] `ChenWeb/server/api/doc-processing/connections.go`, `connections_store.go`, `metric_indexing.go`, `artifact_object_connection_indexing.go` (artifact graph, live-search hydration, object edges)
- [5] ADR 2026062804 — `kb.doc_review_runs` run model (run-scoped findings)
- [6] `KnowledgeStore/Capsules/coding-capsules/doc-processor/document-review-spec.md`
- [7] `KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-metrics-spec.md`
- [8] `KnowledgeStore/doc-repo/adrs/202607/2026070101-adr-object-centric-design.md`
- [9] `KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-provisions-spec.md`
- [10] `KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-inventory-items-spec.md`
