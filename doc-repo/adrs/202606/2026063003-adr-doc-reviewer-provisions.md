# ADR 2026063003 — Provisions Document Reviewer

**Date:** 2026-06-30 \
**Status:** Accepted \
**Component:** ChenWeb — `server/api/doc-reviews`, `server/api/doc-processing` (connection loader), `prompts` \
**Authors**: Chen Ding\
**Tags**: Document Reviewer, Provisions, Cross-Document Consistency

## Change Logs
* 2026/06/30, ADR Created (copied from ADR 2026063002 — metric reviewer)
* 2026/06/30, Fleshed out and implemented. Corrected copy-paste artifacts from the
  metric ADR (provision vs metric naming), confirmed the provision data model
  (`kb.provisions`, id column `prov_id`, category field `category_paths`), filled all
  empty sections. Status Proposal → Accepted.
* 2026/06/30, Branch A correctness fix (mirrors ADR 2026063002): `hybrid_search` edges
  are directional, so the doc provision is on the `target` side of any edge created by a
  document indexed later. Branch A now unions outbound (P=source) and inbound (P=target)
  edges via `LoadConnectionsByTarget`, resolving the opposite endpoint as the match and
  excluding any endpoint with `record_id = record_id`.
* 2026/07/01, Branch A migrated to **on-the-fly** (supersedes the precomputed-edge
  decision in DR1 and the 2026/06/30 correctness fix): semantic provision↔provision
  similarity is no longer materialized as `hybrid_search` / `semantically_related` edges.
  Branch A calls `docprocessing.FindSimilarArtifactsOnTheFly` (same lexical + pgvector RRF
  acceptance policy) per doc provision at review time. Live search is always fresh and
  direction-free, so the A1/A2 inbound/outbound union and `LoadConnectionsByTarget` are no
  longer used by this reviewer. (Note: no provision artifact-indexing step ever wrote these
  edges, so the precomputed Branch A was in practice empty; on-the-fly makes it functional.
  The metric reviewer, ADR 2026063002, made the same change.)
* 2026/07/03, ADR 2026070201 (AR2/AR3/AR5) implemented for this reviewer: prompt v2
  (`prompt-review-provisions-v2.md`), window-first input layout, window-grouped
  seed/stagger execution, `source_doc_authority` + `match_rank` in the matched
  payload, structured `related_artifact_id`/`related_record_id` in findings, and
  tool-use with `get_artifact_context`.
* 2026/07/05, synced with implemented object-centric design (ADR 2026070101): provision
  extraction persists and reconciles artifact objects through the shared
  `kb.artifact_objects` / `kb.object_nodes` contract, and provision indexing writes
  `object_id` / `belong_to` graph edges.
* 2026/07/05, clarified the reviewer goal to match ADR 2026063002: for each
  provision-under-review, retrieve relevant cross-document provisions from the database,
  then ask the LLM to review the provision with that context. Object-anchored retrieval is
  a match branch. The old document-level entity branch is removed because it retrieves
  provisions related to entities in the document-under-review, not necessarily provisions
  relevant to the provision-under-review.

## Context
When a document is added to the knowledge base, the system extracts metrics, entities,
relations, provisions and other artifacts from the document via the doc processors
(refer to [1]).

This document reviewer assumes the document-under-review, identified by `record_id`
(`kb.inputs.id`), has already been processed by all doc processors. The reviewer is
configured as `reviewers.provisions` (group P5) in [2].

### Relationship to the metric reviewer (ADR 2026063002)

This reviewer is the provisions analogue of the metric reviewer [4] and shares its
architecture: it is an **artifact-based, cross-document consistency** reviewer, not a
text reviewer. It does not read the document body; it loads the document's extracted
**provisions** and compares each against semantically-related provisions in *other*
documents, discovered through live hybrid search over `kb.search_artifacts`. It uses
`Input="artifact"`, so the prompt-cache scheduler routes it to `runReviewersLegacy`
which calls `ReviewDocument` directly (no scheduler/strategy changes).

### Provision-specific facts (differ from metrics)

- Provisions live in `kb.provisions`; the artifact id column is **`prov_id`**
  (format `"<record>_prv_<n>"`, globally unique, like `metric_id`). Connection
  `source_id`/`target_id` for provision endpoints equal `prov_id`.
- The artifact type discriminator is `"provision"` (`searchArtifactProvision`).
- Provision indexing hydrates provision rows into `kb.search_artifacts`, writes
  shared-line/category/object graph edges, and writes object-node `belong_to` edges
  through ADR 2026070101. Semantic provision<->provision similarity is not consumed from
  materialized `hybrid_search` edges by this reviewer; Branch A computes it live.
- Provisions carry **`category_paths`** (JSONB array), not `metric_categories`. The
  category field remains useful in prompts and future ranking, but this reviewer does not
  use category overlap as a broad attachment heuristic.
- Unlike the metric reviewer there is **no corpus-wide category-sibling branch** (metric
  Branch B). Provisions match via (A) live hybrid search and (B) object-anchored retrieval.
  (Rationale under Alternative Decisions.)

## Decision
### DR1 — Reviewer logic

The reviewer builds, for each provision extracted from the document-under-review, a
list of **matching provisions** from live semantic search plus object-anchored graph
retrieval, then issues one LLM call per provision. The high-level flow is: given a
provision-under-review, find relevant provisions already in the database, then ask the
LLM to review the provision-under-review with the document context and matching
provisions. Pseudocode:

```text
matches := map[provision] -> []matchingProvision   # keyed by the doc's own provision

# Branch A: provision <-> semantically related provisions, computed LIVE (no materialized edges).
# A single hybrid search per doc provision finds close provisions across the whole corpus
# regardless of when the other document was indexed, so there is no direction to union.
for each provision P extracted from the document-under-review (kb.provisions WHERE input_record_id = record_id):
   hits := FindSimilarArtifactsOnTheFly(
              selfType='provision', selfID=P.prov_id,
              candidateType='provision', maxLinks=PROVISION_REVIEW_MAX_MATCHES)
   resolve each hit (record_id, prov_id) -> a kb.provisions row

   append resolved provisions to matches[P]   (deduped by matching prov_id;
                                               same-document hits excluded)

   # Branch B: object-anchored provisions for the provision-under-review
   objectLinks := kb.artifact_objects ao
      JOIN kb.object_nodes onode ON onode.object_id = ao.object_id
      WHERE ao.source_record_id = record_id
        AND ao.artifact_type = 'provision'
        AND ao.artifact_id = P.prov_id
        AND ao.object_id IS NOT NULL

   for each object node O linked to P:
      peerObjectIDs := O.object_id plus comparable object nodes
                       (same object_type, overlapping normalized_names,
                        reconcile_status <> 'rejected')

      peerEdges := kb.artifact_connections WHERE
         relation_method = 'object_id'
         AND relation_name = 'belong_to'
         AND source_type = 'provision'
         AND target_type = 'object_node'
         AND target_id IN peerObjectIDs

      resolve peerEdges.extra_info.artifact_ids -> kb.provisions rows
      append resolved provisions to matches[P]   (deduped by prov_id;
                                                  same-document hits excluded)

# LLM comparison (parallel)
for each provision P in matches where len(matches[P]) > 0:
   launch one LLM call (configured model + prompt) with:
       - the provision under review (P)
       - all matching provisions (deduped, capped at MaxMatchesPerProvision)
   parse findings; tag Pass="P5", Aspect="provisions"
```

Dedup/cap rules (identical to the metric reviewer):
- A matching provision is identified by its `prov_id`; duplicates across branches are
  collapsed.
- Same-document matches (`record_id = record_id`) are excluded — the reviewer is strictly
  cross-document.
- `matches[P]` is capped at `MaxMatchesPerProvision` (default 20), highest-confidence
  first.

LLM calls run through the artifact-review window-grouped executor (bounded by
`REVIEW_MAX_TASKS`); stop requests are honored at each call boundary (refer to [3] and
the doc-processor stop contract). When `max_tool_turns > 0`, the reviewer uses the
tool-use loop with configured read-only tools.

All Branch A/B retrieval happens before the LLM call and before any tool-use loop. The
LLM receives the provision-under-review plus the already-retrieved matching provisions in
its input payload. Tools are only an optional follow-up mechanism for additional context;
they are not responsible for discovering the object-anchored matches.

### Alternative Decisions
- **Add a corpus-wide category-sibling branch (as in the metric reviewer):** deferred.
  Provision `category_paths` are hierarchical path strings (e.g. `"safety/electrical"`),
  not flat category keys, so a `?|` overlap match is noisier for provisions than for
  metric category keys. Live semantic search (Branch A) already captures cross-document
  provision similarity well. Can be added later if recall proves insufficient.
- **Live hybrid search at review time:** originally rejected by analogy to the first
  metric ADR, then accepted on 2026/07/01. This is now Branch A.
- **Document-level entity branch:** removed from the reviewer design. It used
  entity->provision edges for all entities extracted from the document-under-review, then
  attached targets by category-path overlap. That is a weak provision-under-review
  relevance signal compared with live hybrid search and object-anchored retrieval.
- **Tool-use (agentic) reviewer (`max_tool_turns > 0`):** originally not adopted, then
  implemented by ADR 2026070201 AR4/AR5. Current configuration uses
  `max_tool_turns = 4` and `get_artifact_context`.

### Database Migrations
**None for the reviewer.** Reads `kb.provisions`, `kb.search_artifacts`,
`kb.artifact_objects`, `kb.object_nodes`, and object-id `kb.artifact_connections` edges;
writes findings to the existing `kb.doc_review_findings` (run-scoped via `run_id`, [5]).
No reviewer-owned table, column, or `kb.search_artifacts` partition.

Provision object extraction/reconciliation tables and object-id connection partitions
are owned by ADR 2026070101, not by this reviewer ADR.

### Data Formats

**Provision view (loaded from `kb.provisions`)** — the "provision under review":

```json
{
  "prov_id": "1001_prv_3",
  "prov_name": "Pressure relief requirement",
  "provision_type": "requirement",
  "provision": "The system shall include a pressure relief valve rated for 1.6 MPa.",
  "provision_subject": "pressure relief",
  "category_paths": ["safety/pressure", "equipment/valve"]
}
```

**Matching provision** — same shape plus match provenance:

```json
{
  "provision": { ... provision view ... },
  "source_record_id": 2002,
  "source_filename": "GB_50316_pipe_design.pdf",
  "match_via": "hybrid_search | object_anchor",
  "match_rank": 1,
  "source_doc_authority": "standard"
}
```

**Finding output** — the standard review-finding JSON (`ReviewFinding`); the reviewer
sets `Pass="P5"`, `Aspect="provisions"`, defaults `finding_type="issue"`,
`severity="low"`, and `location` from the provision's `source_line_spans` when the model
leaves them empty.

### Environment Variables
- `REVIEW_MAX_TASKS` (existing) — bounds the per-provision LLM fan-out.
- `PROVISION_REVIEW_MAX_MATCHES` (new, optional, default `20`) — cap on matching
  provisions per doc provision.
- `PROVISION_REVIEW_MAX_PROVISIONS` (new, optional, default `0` = no cap) — cap on the
  number of doc provisions reviewed.

## Implementation

### Code Changes

| File | Change |
|---|---|
| `ChenWeb/server/api/doc-reviews/review-provisions.go` | `provisionsReviewer` implementing `Reviewer` (`Name()="provisions"`, `Group()="P5"`, `Strategy()=StrategyDocument`). `ReviewDocument` loads provisions, builds matches from live `FindSimilarArtifactsOnTheFly` plus object-anchored provision rosters, hydrates source context, and runs window-grouped artifact review units. Tool-use is enabled when configured. |
| `ChenWeb/server/api/doc-reviews/review-document.go` | Resolves `provisions`/P5 runtime, budget, and tool config; appends the `provisionsReviewer` runner with `cfg.Input="artifact"`. |
| `ChenWeb/server/api/doc-processing/search_artifact_indexing.go`, `extract-provisions.go` | Reindex provisions in `kb.search_artifacts`, persist/reconcile provision objects, and index provision object-node edges under the shared object contract. |
| `ChenWeb/doc-review.local.toml` | `reviewers.provisions`: `input="artifact"`, `model="deepseek-v4-flash"`, `prompt="prompt-review-provisions-v2.md"`, `max_tool_turns=4`, `tools=["get_artifact_context"]`. |
| `ChenWeb/prompts/prompt-review-provisions-v2.md` | Current prompt (v2 supersedes v1). |
| `ChenWeb/server/api/doc-reviews/review-provisions_test.go` | **New** tests (assembly branches/dedup/exclusion/cap; reviewProvision payload + tagging). |

Target resolution maps live-search hit ids and object-edge artifact ids to
`kb.provisions` rows. Because `prov_id` is globally unique (`"<record>_prv_<n>"`),
resolution batches by `prov_id` (`WHERE prov_id = ANY($1)`), like the metric reviewer.

## Operational Behaviors
- **No provisions / no matches:** returns zero findings (logged, not an error).
- **Dependency:** meaningful after `extract_provisions` has populated `kb.provisions`,
  `kb.search_artifacts`, and the ADR 2026070101 object graph: artifact-object
  persistence, object-node reconciliation, and object `belong_to` indexing.
- **Parallelism & stop / idempotency:** identical to the metric reviewer and all
  reviewers — concurrent per-provision calls under `REVIEW_MAX_TASKS`, stop at the next
  boundary, findings written under the current `run_id` (prior run findings deleted by
  `PostProcessIndex`).

## Consequences
**Positive**
- Cross-document provision consistency: conflicting/contradictory requirements,
  prohibitions, or obligations across the corpus that no single-document reviewer can
  see.
- Live hybrid search avoids stale/directional semantic edges while reusing the shared
  lexical/vector search registry and existing reviewer plumbing.
- Object-anchored matching retrieves provisions tied to the same canonical object as the
  provision-under-review, improving relevance over document-level entity co-occurrence.

**Negative / cost**
- Per-provision live search adds read-time search cost; bounded by
  `PROVISION_REVIEW_MAX_PROVISIONS` and `MaxMatchesPerProvision`.
- Per-provision LLM fan-out bounded by `PROVISION_REVIEW_MAX_PROVISIONS` and
  `MaxMatchesPerProvision`.
- No category-sibling recall path (deferred); some related provisions that lack a
  live semantic-search hit will not be compared.
- Object-anchored recall depends on provision object extraction and reconciliation
  quality. Provisions without a reconciled `object_id` rely on live hybrid search only.

## Tests
- Branch A: a doc provision with a live hybrid-search hit to a cross-document provision
  -> one LLM call, finding tagged `P5`/`provisions`.
- Branch B: an object-anchored provision in another document is attached to the
  provision-under-review through `kb.artifact_objects` -> `kb.object_nodes` ->
  `kb.artifact_connections`.
- Dedup: a target reached via both branches appears once.
- Same-document exclusion: a target with `target_record_id = record_id` is dropped.
- Cap: `MaxMatchesPerProvision` truncates to highest-confidence matches.
- No matches → no LLM call, no findings.
- `reviewProvision` payload contains `provision_under_review` + `matching_provisions`;
  findings get `Pass=P5`/`Aspect=provisions` and default severity/type/location.

## Documentation Impact
- `doc-processor/+CAPSULE.md` [1]: no pipeline-table change (provisions review is an
  aspect, not a doc processor).
- This ADR + `prompt-review-provisions-v2.md` are the current design/behavior records.
  Shares the live-search and reviewer-integration design with ADR 2026063002 [4].
- Intentionally left undocumented here: exact live-search RRF weighting (owned by
  `search_artifact_indexing.go` / extract-provisions spec); the deferred
  category-sibling branch. Object extraction/reconciliation policy is documented by ADR
  2026070101 [7].

## References
- [1] `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md`
- [2] `ChenWeb/doc-review.local.toml`
- [3] `KnowledgeStore/doc-repo/adrs/202606/2026062804-adr-doc-review-run.md` (run model) and `ChenWeb/server/api/doc-reviews/review_cache_scheduler.go` (dispatch)
- [4] ADR 2026063002 — Metric Document Reviewer (shared architecture, connection loader)
- [5] ADR 2026062804 — `kb.doc_review_runs` run model (run-scoped findings)
- [6] Extract Provisions Spec: `KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-provisions-spec.md`
- [7] `KnowledgeStore/doc-repo/adrs/202607/2026070101-adr-object-centric-design.md`
