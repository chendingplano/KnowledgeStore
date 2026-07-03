# ADR 2026063002 — Metric Document Reviewer

**Date:** 2026-06-30 \
**Status:** Accepted \
**Component:** ChenWeb — `server/api/doc-reviews`, `server/api/doc-processing` (connection loader), `prompts` \
**Authors**: Chen Ding\
**Tags**: Document Reviewer, Metric, Cross-Document Consistency

## Change Logs
* 2026/06/30, ADR Created
* 2026/06/30, Fleshed out after codebase review: resolved the DR1 "hybrid search"
  mechanism (read precomputed `hybrid_search` edges, do **not** re-run live search),
  added Data Formats, Migrations (none), Environment Variables, Code Changes,
  Operational Behaviors, Consequences, Tests, and Documentation Impact. Status
  moved Proposal → Accepted.
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

## Context
When a document is added to the knowledge base, the system extracts metrics,
entities, relations and other artifacts from the document via the doc processors
(refer to [1]).

This document reviewer assumes the document-under-review, identified by `record_id`
(`kb.inputs.id`), has already been processed by all doc processors. The reviewer is
configured as `reviewers.metrics` (group P5) in [2].

### How this reviewer differs from every existing reviewer

All ~40 existing review aspects (e.g. `grammar_spelling`, `completeness`,
`standards_compliance`) read the **document's own text**: the prompt-cache scheduler
splits the line file into `per-chunk` or `per-block` units and fans out one LLM call
per unit ([3], `review_cache_scheduler.go`).

The metric reviewer is fundamentally different. It does **not** read the document
text. It consumes **already-extracted artifacts** — the document's `kb.metrics` rows
and its entities — and cross-references each metric against *semantically related
metrics in other documents*. It is therefore a **cross-document consistency** check,
not a single-document text review.

### Resolving "hybrid search `kb.artifact_connections` by the metric" (DR1)

`kb.artifact_connections` is a graph **edge** table ([4], `connections.go`), not a
searchable index, so it cannot be "hybrid searched" directly. The codebase already
runs hybrid search (RRF over ParadeDB BM25 + pgvector) **at index time**: when the
`extract_metrics` doc processor finishes, its artifact-indexing step
(`artifact_indexing.go`) computes, for every metric, its top semantically-related
artifacts across the **entire corpus** and persists them as edges:

```
source_type = 'metric', source_record_id = <doc>, source_id = <metric artifact id>
relation_method = 'hybrid_search'
relation_name   = 'semantically_related'
target_type     = 'metric' (and other families)
target_record_id / target_id = the matched artifact (often a different document)
confidence      = RRF score, provenance = {cosine_sim, lexical_score, ...}
```

As of 2026/07/01 (see change log) the reviewer does **not** read precomputed edges for
Branch A. Semantic metric↔metric similarity is computed **live** at review time via
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

The entity branch likewise reads precomputed edges: a metric reachable from one of
the document's entities through `kb.artifact_connections` is a candidate match.

## Decision
### DR1 — Reviewer logic

The reviewer builds, for each metric extracted from the document-under-review, a list
of **matching metrics** drawn from the precomputed artifact graph, then issues one LLM
call per metric that has at least one match. Pseudocode:

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

   append resolved matches to matches[M]   (deduped by the matching metric's (record_id, id);
                                            same-document hits excluded)

   # Branch B: metric -> metrics sharing a metric category
   for each category key C in M.metric_categories:
      sibling metrics := kb.metrics WHERE metric_categories @> C AND id <> M.id   (corpus-wide)
      append sibling metrics to matches[M]   (deduped, capped)

# Branch C: entity -> metrics related to that entity
for each entity E extracted from the document-under-review:
   edges := load kb.artifact_connections WHERE
              source_type='entity' AND source_record_id=record_id AND source_id=E.artifact_id
              AND target_type='metric'
   for each resolved target metric MT:
      attach MT to the doc metric(s) it most plausibly corroborates
      (default: add MT to every doc metric that shares a category with MT;
       if none shares a category, MT is recorded as an unattached entity-metric and skipped)

# Branch D: entity-by-shared-lines -> metrics related to that entity
for each metric:
  find all the entities that share the same line(s) with the metric:
      the remain part is the same as that of Branch C

# Branch D: inventory-items -> metrics related to that entity
for each inventory item extracted from the document-under-review:
   edges := load kb.artifact_connections WHERE
              source_type='inventory_item' AND source_record_id=record_id AND source_id=E.artifact_id
              AND target_type='metric'
   for each resolved target metric MT:
      attach MT to the doc metric(s) it most plausibly corroborates
      (default: add MT to every doc metric that shares a category with MT;
       if none shares a category, MT is recorded as an unattached entity-metric and skipped)

# Branch D: entity-by-shared-lines -> metrics related to that entity
for each metric:
  find all the entities that share the same line(s) with the metric:
      the remain part is the same as that of Branch C

# Branch E: inventory-

# LLM comparison (parallel)
for each metric M in matches where len(matches[M]) > 0:
   launch one LLM call (configured model + prompt) with:
       - the metric under review (M)
       - all matching metrics (deduped, capped at MaxMatchesPerMetric)
   parse findings; tag Pass="P5", Aspect="metrics"
```

LLM calls run in parallel via the shared reviewer concurrency helper
(`runReviewerConcurrent`, bounded by `REVIEW_MAX_TASKS`); stop requests are honored at
each call boundary (refer to [3] and the doc-processor stop contract).

Dedup/cap rules:
- A matching metric is identified by the matching metric's own `(record_id, id)` — the
  `target` endpoint for outbound edges, the `source` endpoint for inbound edges; duplicates
  across branches **and across both edge directions** are collapsed.
- A metric's own record is never a match: the matching endpoint's `record_id = record_id`
  is excluded (`target_record_id <> record_id` for outbound, `source_record_id <> record_id`
  for inbound) so the reviewer is strictly cross-document; same-document near-duplicates are
  handled by the metric deduplication pipeline, not this reviewer.
- `matches[M]` is capped at `MaxMatchesPerMetric` (default 20), highest-confidence first.

### DR2 — Prompt
Create `ChenWeb/prompts/prompt-review-metrics-v1.md` and reference it from
`reviewers.metrics.prompt` in [2]. The prompt instructs the model to compare one
"metric under review" against a set of matching metrics drawn from other documents and
to emit findings only for genuine cross-document discrepancies (conflicting values,
units, thresholds, or definitions for what is plausibly the same quantity), not mere
restatements. Output conforms to the standard review-finding JSON contract (see
Data Formats).

### Alternative Decisions
- **Live hybrid search at review time** (call the metric search path per metric):
  rejected — duplicates work already done at index time, is non-deterministic w.r.t.
  index state, and is markedly more expensive. The precomputed-edge approach can be
  upgraded to a live fallback later without changing the finding contract.
- **Pure structural graph walk only** (no use of `hybrid_search` edges): rejected — the
  `hybrid_search` edges *are* the semantic match signal; ignoring them would reduce the
  reviewer to category/entity co-membership and miss cross-document value conflicts that
  are textually dissimilar.
- **New `ReviewStrategy` enum value + scheduler branch**: rejected as unnecessary. A
  reviewer whose `Input` is neither `per-chunk` nor `per-block` is already routed to
  `runReviewersLegacy`, which calls `ReviewDocument` directly. The metric reviewer uses
  that path with `Input = "artifact"`.

### Database Migrations
**None.** The reviewer reads existing tables (`kb.metrics`, `kb.artifact_connections`,
entities) and writes findings to the existing `kb.doc_review_findings` (run-scoped via
`run_id`, per ADR 2026062804 [5]). No new table, column, or `kb.search_artifacts`
partition is required (reviewers persist findings; they do not create searchable
artifacts).

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
  "match_via": "hybrid_search | metric_category | entity",
  "confidence": 0.0123
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

### Environment Variables
- `REVIEW_MAX_TASKS` (existing) — bounds reviewer-internal parallelism; reused for the
  per-metric LLM fan-out.
- `METRIC_REVIEW_MAX_MATCHES` (new, optional, default `20`) — cap on matching metrics
  per doc metric.
- `METRIC_REVIEW_MAX_METRICS` (new, optional, default `0` = no cap) — cap on the number
  of doc metrics reviewed (safety valve for very metric-heavy documents).
- No new model/prompt env vars: model and prompt come from `reviewers.metrics` in [2]
  via the existing `resolveReviewerRuntime` path.

## Implementation

### Code Changes

| File | Change |
|---|---|
| `ChenWeb/server/api/doc-reviews/review-metrics.go` | **New.** `metricsReviewer` implementing `Reviewer` (`Name()="metrics"`, `Group()="P5"`, `Strategy()=StrategyDocument`). `ReviewDocument` loads the doc's metrics + entities, builds the match map via the connection loader + category/entity branches, resolves target metrics, and fans out one LLM call per matched doc metric with `runReviewerConcurrent`. Stop-aware. |
| `ChenWeb/server/api/doc-reviews/review-document.go` | In `NewReviewProcessor`, resolve `metrics`/P5 runtime (`resolveReviewerRuntime`) and store client/model/prompt fields on `ReviewProcessor`. In `buildReviewers`, append the `metricsReviewer` runner with `cfg.Input="artifact"` so the scheduler routes it to `runReviewersLegacy` → `ReviewDocument`. |
| `ChenWeb/server/api/doc-processing/connections_store.go` | `LoadConnectionsBySource(ctx, sourceRecordID, sourceType, relationMethod, targetType)` (outbound; already present) **plus a new** `LoadConnectionsByTarget(ctx, targetRecordID, targetType, relationMethod, sourceType)` mirror (inbound) returning `[]Connection`. Branch A reads both so it captures edges written by documents indexed after the document-under-review. Exported for use by `doc-reviews`. |
| `ChenWeb/server/api/doc-reviews/review-metrics.go` (metric resolution) | Helper to resolve an edge endpoint back to a `kb.metrics` row — the `target` endpoint for outbound edges, the `source` endpoint for inbound edges: parse the trailing sequence from the artifact id (`BuildArtifactID` format `<rec>_m_<seq>`) and match `kb.metrics WHERE input_record_id = <endpoint record_id> AND (metric_id LIKE '%\_'||seq OR id::text = seq)`. Batch by record to avoid N+1. |
| `ChenWeb/doc-review.local.toml` | Change `reviewers.metrics.input` from `"per-chunk"` to `"artifact"`; set `max_tool_turns = 0` (the reviewer is not tool-using). Model stays `deepseek-v4-pro`, prompt `prompt-review-metrics-v1.md`. |
| `ChenWeb/prompts/prompt-review-metrics-v1.md` | **New** prompt (DR2). |
| `ChenWeb/server/api/doc-reviews/review-metrics_test.go` | **New** tests (see Tests). |

The metric reviewer reuses the existing entity store (`ReviewProcessor.EntityStore`,
`EntityRelationSQLStore.LoadEntitiesForRecord`) for branch C and the shared
`newDocReviewLLMJSONInput` + `LLMJSONExtractor` for LLM calls, so cache telemetry and
finding normalization are identical to other reviewers.

## Operational Behaviors

- **No metrics / no matches:** if the document has no `kb.metrics` rows, or no metric
  has any cross-document match, the reviewer returns zero findings (logged, not an
  error). This is the common case for documents that are the sole source of their
  metrics.
- **Dependency:** the reviewer is meaningful only after `extract_metrics` and (for
  branch C) `extract_entity_relation` have run and the artifact-indexing step has
  written `hybrid_search` edges. If those edges are absent (indexing not yet run),
  branches A/C contribute nothing and only category co-membership (branch B) applies.
- **Parallelism & stop:** per-metric LLM calls run concurrently under `REVIEW_MAX_TASKS`;
  a user stop request cancels remaining calls at the next boundary (`ErrPipelineStopped`).
- **Idempotency:** findings are written under the current `run_id`; a re-run deletes the
  run's prior findings first (existing `PostProcessIndex` behavior, [5]).

## Consequences

**Positive**
- Adds genuine cross-document consistency checking — conflicting values/units/thresholds
  for the same quantity across the corpus — which no text-based reviewer can detect.
- Reuses precomputed `hybrid_search` edges: no extra search cost at review time, fully
  consistent with the artifact graph.
- Integrates through the existing `runReviewersLegacy`/`ReviewDocument` path with no
  scheduler or schema changes.

**Negative / cost**
- Match quality is bounded by the freshness and quality of the precomputed
  `hybrid_search` edges; a stale index yields stale matches.
- Per-metric LLM fan-out can be large for metric-heavy documents; bounded by
  `METRIC_REVIEW_MAX_METRICS` and `MaxMatchesPerMetric`.
- The artifact-id → `kb.metrics` reverse resolution depends on the `BuildArtifactID`
  sequence convention; covered by a unit test so a format change is caught.

## Tests
- `ReviewDocument` with a doc metric that has one **outbound** `hybrid_search` edge to a
  cross-document metric → one LLM call, finding tagged `P5`/`metrics`.
- Branch A inbound direction: a doc metric that has no outbound edge but is the `target`
  of a `hybrid_search` edge from a later-indexed document's metric is still matched
  (resolved from the edge `source` endpoint).
- Branch A dedup across directions: a cross-document metric linked to the doc metric by
  both an outbound and an inbound `hybrid_search` edge appears as a single match.
- Metric with no matches (no edges, no category siblings, no entity metrics) → no LLM
  call, no findings.
- Branch B: two metrics sharing a `metric_categories` key in different documents are
  matched; same-document siblings excluded.
- Branch C: an entity-connected metric in another document is attached to the
  category-sharing doc metric.
- Dedup: a target reachable via both `hybrid_search` and entity branches appears once.
- Cap: `MaxMatchesPerMetric` truncates to the highest-confidence matches.
- Artifact-id → metric resolution helper: `1001_m_7` resolves to the right
  `kb.metrics` row; unresolvable ids are skipped without error.
- `LoadConnectionsBySource` returns only edges matching the source/method/target filter;
  `LoadConnectionsByTarget` returns only edges matching the target/method/source filter.
- Stop request mid-fan-out returns `ErrPipelineStopped`.

## Documentation Impact
- `doc-processor/+CAPSULE.md` [1]: the `review_document` row already covers the review
  pipeline; no pipeline-table change (metrics is a review *aspect*, not a doc processor).
- This ADR is the design record for the reviewer; `prompt-review-metrics-v1.md` is the
  behavior record. A standalone document-review spec (referenced as [6]) does not yet
  exist; when it is written it should note that `metrics` is the first artifact-based
  (cross-document) reviewer and uses `Input="artifact"` (direct `ReviewDocument` path).
- Intentionally left undocumented: the exact RRF weighting of `hybrid_search` edges
  (owned by `artifact_indexing.go` / the metric-indexing spec), and live-search fallback
  (not built).

## References
- [1] `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md`
- [2] `ChenWeb/doc-review.local.toml`
- [3] `KnowledgeStore/doc-repo/adrs/202606/2026062804-adr-doc-review-run.md` (run model) and `ChenWeb/server/api/doc-reviews/review_cache_scheduler.go` (dispatch)
- [4] `ChenWeb/server/api/doc-processing/connections.go`, `connections_store.go`, `artifact_indexing.go` (artifact graph + hybrid_search edges)
- [5] ADR 2026062804 — `kb.doc_review_runs` run model (run-scoped findings)
- [6] `KnowledgeStore/Capsules/coding-capsules/doc-processor/document-review-spec.md`
- [7] `KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-metrics-spec.md`
