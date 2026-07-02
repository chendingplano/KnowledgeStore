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
documents, discovered through the precomputed `kb.artifact_connections` edges. It uses
`Input="artifact"`, so the prompt-cache scheduler routes it to `runReviewersLegacy`
which calls `ReviewDocument` directly (no scheduler/strategy changes).

### Provision-specific facts (differ from metrics)

- Provisions live in `kb.provisions`; the artifact id column is **`prov_id`**
  (format `"<record>_prv_<n>"`, globally unique, like `metric_id`). Connection
  `source_id`/`target_id` for provision endpoints equal `prov_id`.
- The artifact type discriminator is `"provision"` (`searchArtifactProvision`).
- The provision-indexing step (`indexArtifactsByOverlapAndConnect` →
  `connectArtifactsBySearch`, `search_artifact_indexing.go`) writes the same
  `hybrid_search` / `semantically_related` edges per provision that metrics get.
- Provisions carry **`category_paths`** (JSONB array), not `metric_categories`. The
  entity-branch "shares a category" test uses `category_paths`.
- **Two branches only.** Unlike the metric reviewer there is **no corpus-wide
  category-sibling branch** (metric Branch B). Provisions match via (A) precomputed
  semantic edges and (B) shared-entity edges. (Rationale under Alternative Decisions.)

## Decision
### DR1 — Reviewer logic

The reviewer builds, for each provision extracted from the document-under-review, a
list of **matching provisions** drawn from the precomputed artifact graph, then issues
one LLM call per provision that has at least one match. Pseudocode:

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

   append resolved provisions to matches[P]   (deduped by the matching provision's (record_id, prov_id);
                                               same-document hits excluded)

# Branch B: entity -> provisions related to that entity
for each entity->provision edge for the document
    (kb.artifact_connections WHERE source_type='entity' AND source_record_id=record_id AND target_type='provision'):
   resolve target provision PT
   attach PT to every doc provision that shares a category_paths key with PT
   (if none shares a category, PT is recorded as an unattached entity-provision and skipped)

# LLM comparison (parallel)
for each provision P in matches where len(matches[P]) > 0:
   launch one LLM call (configured model + prompt) with:
       - the provision under review (P)
       - all matching provisions (deduped, capped at MaxMatchesPerProvision)
   parse findings; tag Pass="P5", Aspect="provisions"
```

Dedup/cap rules (identical to the metric reviewer):
- A matching provision is identified by `(target_record_id, target_id)`; duplicates
  across branches are collapsed.
- Same-document targets (`target_record_id = record_id`) are excluded — the reviewer is
  strictly cross-document.
- `matches[P]` is capped at `MaxMatchesPerProvision` (default 20), highest-confidence
  first.

LLM calls run in parallel via `runReviewerConcurrent` (bounded by `REVIEW_MAX_TASKS`);
stop requests are honored at each call boundary (refer to [3] and the doc-processor stop
contract).

### Alternative Decisions
- **Add a corpus-wide category-sibling branch (as in the metric reviewer):** deferred.
  Provision `category_paths` are hierarchical path strings (e.g. `"safety/electrical"`),
  not flat category keys, so a `?|` overlap match is noisier for provisions than for
  metric category keys. Semantic edges (Branch A) already capture cross-document
  provision similarity well. Can be added later if recall proves insufficient.
- **Live hybrid search at review time:** rejected for the same reasons as the metric
  reviewer — duplicates index-time work, non-deterministic, more expensive.
- **Tool-use (agentic) reviewer (`max_tool_turns > 0`):** not adopted. The reviewer
  pre-fetches matches and compares in one shot via `ExtractJSON`; it does not use the
  tool-use loop, so `max_tool_turns` is left at `0` (it would otherwise be dead config).
  Revisit only if the model needs to pull additional context (full provision text of
  matches, related provisions) to judge conflicts.

### Database Migrations
**None.** Reads `kb.provisions`, `kb.artifact_connections`, and entity→provision edges;
writes findings to the existing `kb.doc_review_findings` (run-scoped via `run_id`, [5]).
No new table, column, or `kb.search_artifacts` partition.

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
  "match_via": "hybrid_search | entity",
  "confidence": 0.0123
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
| `ChenWeb/server/api/doc-reviews/review-provisions.go` | **New.** `provisionsReviewer` implementing `Reviewer` (`Name()="provisions"`, `Group()="P5"`, `Strategy()=StrategyDocument`). `ReviewDocument` loads the doc's provisions, builds matches via the shared connection loader (Branch A hybrid_search + Branch B entity→provision), resolves target provisions, and fans out one LLM call per matched provision with `runReviewerConcurrent`. Stop-aware. Mirrors `review-metrics.go`. |
| `ChenWeb/server/api/doc-reviews/review-document.go` | Resolve `provisions`/P5 runtime in `NewReviewProcessor`; store client/model/prompt fields; append the `provisionsReviewer` runner in `buildReviewers` with `cfg.Input="artifact"`. |
| `ChenWeb/server/api/doc-processing/connections_store.go` | Reuses `LoadConnectionsBySource` (outbound) **and** `LoadConnectionsByTarget` (inbound), both added by ADR 2026063002 — no change needed here. |
| `ChenWeb/doc-review.local.toml` | `reviewers.provisions`: `input="artifact"`, `prompt="prompt-review-provisions-v1.md"`, `max_tool_turns=0`. |
| `ChenWeb/prompts/prompt-review-provisions-v1.md` | **New** prompt. |
| `ChenWeb/server/api/doc-reviews/review-provisions_test.go` | **New** tests (assembly branches/dedup/exclusion/cap; reviewProvision payload + tagging). |

Target resolution maps an edge `(target_record_id, target_id=prov_id)` to a
`kb.provisions` row. Because `prov_id` is globally unique (`"<record>_prv_<n>"`),
resolution batches by `prov_id` (`WHERE prov_id = ANY($1)`), like the metric reviewer.

## Operational Behaviors
- **No provisions / no matches:** returns zero findings (logged, not an error).
- **Dependency:** meaningful after `extract_provisions` (+ for branch B,
  `extract_entity_relation`) and the provision-indexing step have written
  `hybrid_search` / entity→provision edges. Absent those edges, the reviewer finds
  nothing.
- **Parallelism & stop / idempotency:** identical to the metric reviewer and all
  reviewers — concurrent per-provision calls under `REVIEW_MAX_TASKS`, stop at the next
  boundary, findings written under the current `run_id` (prior run findings deleted by
  `PostProcessIndex`).

## Consequences
**Positive**
- Cross-document provision consistency: conflicting/contradictory requirements,
  prohibitions, or obligations across the corpus that no single-document reviewer can
  see.
- Reuses precomputed edges and the existing reviewer plumbing (loader, legacy path,
  finding store); no schema or scheduler change.

**Negative / cost**
- Match quality bounded by the freshness/quality of the provision `hybrid_search` edges.
- Per-provision LLM fan-out bounded by `PROVISION_REVIEW_MAX_PROVISIONS` and
  `MaxMatchesPerProvision`.
- No category-sibling recall path (deferred); some related provisions that lack a
  semantic edge will not be compared.

## Tests
- Branch A (outbound): a doc provision with an outbound `hybrid_search` edge to a
  cross-document provision → one LLM call, finding tagged `P5`/`provisions`.
- Branch A (inbound): a doc provision that is the `target` of a `hybrid_search` edge from
  a later-indexed document's provision is matched (resolved from the edge `source`);
  duplicates across both directions collapse to one match.
- Branch B: an entity→provision edge whose target shares a `category_paths` key with a
  doc provision is attached to that provision.
- Dedup: a target reached via both branches appears once.
- Same-document exclusion: a target with `target_record_id = record_id` is dropped.
- Cap: `MaxMatchesPerProvision` truncates to highest-confidence matches.
- No matches → no LLM call, no findings.
- `reviewProvision` payload contains `provision_under_review` + `matching_provisions`;
  findings get `Pass=P5`/`Aspect=provisions` and default severity/type/location.

## Documentation Impact
- `doc-processor/+CAPSULE.md` [1]: no pipeline-table change (provisions review is an
  aspect, not a doc processor).
- This ADR + `prompt-review-provisions-v1.md` are the design/behavior records. Shares
  the connection-loader and reviewer-integration design with ADR 2026063002 [4].
- Intentionally left undocumented: provision `hybrid_search` edge weighting (owned by
  `artifact_indexing.go`); the deferred category-sibling branch; live-search fallback.

## References
- [1] `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md`
- [2] `ChenWeb/doc-review.local.toml`
- [3] `KnowledgeStore/doc-repo/adrs/202606/2026062804-adr-doc-review-run.md` (run model) and `ChenWeb/server/api/doc-reviews/review_cache_scheduler.go` (dispatch)
- [4] ADR 2026063002 — Metric Document Reviewer (shared architecture, connection loader)
- [5] ADR 2026062804 — `kb.doc_review_runs` run model (run-scoped findings)
- [6] Extract Provisions Spec: `KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-provisions-spec.md`
