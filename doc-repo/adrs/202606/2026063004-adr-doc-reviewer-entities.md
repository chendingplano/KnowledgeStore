# ADR 2026063004 — Entities Document Reviewer

**Date:** 2026-06-30 \
**Status:** Accepted \
**Component:** ChenWeb — `server/api/doc-reviews`, `server/api/doc-processing` (connection loader), `prompts` \
**Authors**: Chen Ding\
**Tags**: Document Reviewer, Entities, Cross-Document Consistency

## Change Logs
* 2026/06/30, ADR Created (copied from ADR 2026063003 — provisions reviewer, itself
  copied from ADR 2026063002 — metric reviewer)
* 2026/06/30, Fleshed out and implemented. Confirmed the entity data model
  (`kb.entities`, id column `entity_id`, name fields `entity`/`entity_en`, category
  field `categories`), resolved the second match branch to a **name-sibling** scan
  (entity-appropriate replacement for the metric category-sibling branch), filled all
  sections. Status Proposal → Accepted.
* 2026/06/30, Branch A correctness fix (mirrors ADR 2026063002): `hybrid_search` edges
  are directional, so the doc entity is on the `target` side of any edge created by a
  document indexed later. Branch A now unions outbound (E=source) and inbound (E=target)
  edges via `LoadConnectionsByTarget`, resolving the opposite endpoint as the match and
  excluding any endpoint with `record_id = record_id`.
* 2026/07/01, Branch A migrated to **on-the-fly** (supersedes the precomputed-edge
  decision in DR1 and the 2026/06/30 correctness fix): semantic entity↔entity similarity
  is no longer materialized as `hybrid_search` / `semantically_related` edges. Branch A
  calls `docprocessing.FindSimilarArtifactsOnTheFly` (same lexical + pgvector RRF
  acceptance policy) per doc entity at review time. Live search is always fresh and
  direction-free, so the A1/A2 inbound/outbound union and `LoadConnectionsByTarget` are no
  longer used by this reviewer. (Note: no entity artifact-indexing step ever wrote these
  edges, so the precomputed Branch A was in practice empty; on-the-fly makes it functional.
  The metric reviewer, ADR 2026063002, made the same change.)

## Context
When a document is added to the knowledge base, the system extracts metrics, entities,
relations, provisions and other artifacts from the document via the doc processors
(refer to [1]).

This document reviewer assumes the document-under-review, identified by `record_id`
(`kb.inputs.id`), has already been processed by all doc processors. The reviewer is
configured as `reviewers.entities` (group P5) in [2].

### Relationship to the metric and provisions reviewers (ADRs 2026063002 / 2026063003)

This reviewer is the **entities** analogue of the metric reviewer [4] and the provisions
reviewer [6], and shares their architecture: it is an **artifact-based, cross-document
consistency** reviewer, not a text reviewer. It does not read the document body; it loads
the document's extracted **entities** and compares each against semantically-related and
same-named entities in *other* documents, discovered through the precomputed
`kb.artifact_connections` edges and a corpus-wide name scan. It uses `Input="artifact"`,
so the prompt-cache scheduler routes it to `runReviewersLegacy` which calls
`ReviewDocument` directly (no scheduler/strategy changes).

### Entity-specific facts (differ from metrics / provisions)

- Entities live in `kb.entities`; the artifact id column is **`entity_id`**
  (format `"<record>_e_<seq>"`, globally unique, like `metric_id`/`prov_id`).
  Connection `source_id`/`target_id` for entity endpoints equal `entity_id`.
- The artifact type discriminator is `"entity"` (`searchArtifactEntity`, [7]).
- The entity-indexing step (`IndexEntitiesForRecord` → `indexArtifactsByOverlapAndConnect`
  → `connectArtifactsBySearch`, `search_artifact_indexing.go`) writes the same
  `hybrid_search` / `semantically_related` edges per entity that metrics and provisions
  get (`source_type='entity'`, `target_type='entity'`).
- Entities are **bilingual**: `entity`/`entity_en` (name), `entity_type`/`entity_type_en`,
  `aliases`/`aliases_en`, `desc_text`/`desc_text_en`. The reviewer passes both languages
  so the model can detect conflicts regardless of source language.
- Entities carry **`categories`** (JSONB array of flat category keys), like metric
  `metric_categories`.
- **Two branches.** (A) precomputed semantic `hybrid_search` edges (entity→entity), and
  (B) a corpus-wide **name-sibling** scan — entities in other documents that share a
  normalized name or alias with a doc entity. Branch B is the entity-appropriate
  replacement for the metric *category-sibling* branch: for entities the salient
  cross-document consistency question is "is this the **same named entity**, described
  differently?", so siblings are keyed on **name identity**, not category co-membership
  (which for entities — e.g. every "organization" — is far too broad to be useful).

## Decision
### DR1 — Reviewer logic

The reviewer builds, for each entity extracted from the document-under-review, a list of
**matching entities** drawn from the precomputed artifact graph plus a name scan, then
issues one LLM call per entity that has at least one match. Pseudocode:

```text
matches := map[entity] -> []matchingEntity   # keyed by the doc's own entity

# Branch A: entity <-> semantically related entities, computed LIVE (no materialized edges).
# A single hybrid search per doc entity finds close entities across the whole corpus
# regardless of when the other document was indexed, so there is no direction to union.
for each entity E extracted from the document-under-review (kb.entities WHERE input_record_id = record_id):
   hits := FindSimilarArtifactsOnTheFly(
              selfType='entity', selfID=E.entity_id,
              candidateType='entity', maxLinks=ENTITY_REVIEW_MAX_MATCHES)
   resolve each hit (record_id, entity_id) -> a kb.entities row

   append resolved entities to matches[E]   (deduped by the matching entity's (record_id, entity_id);
                                             same-document hits excluded)

# Branch B: entity -> same-named entities in other documents (corpus-wide name scan)
names := union of every doc entity's normalized name keys (lower(entity), lower(entity_en), aliases)
siblings := kb.entities WHERE input_record_id <> record_id
                          AND (lower(entity) = ANY(names) OR lower(entity_en) = ANY(names))
for each sibling S:
   attach S to every doc entity that shares a name key with S
   (if none shares a name key, S is skipped)

# LLM comparison (parallel)
for each entity E in matches where len(matches[E]) > 0:
   launch one LLM call (configured model + prompt) with:
       - the entity under review (E)
       - all matching entities (deduped, capped at MaxMatchesPerEntity)
   parse findings; tag Pass="P5", Aspect="entities"
```

Dedup/cap rules (identical to the metric / provisions reviewers):
- A matching entity is identified by `(target_record_id, target_id=entity_id)`; duplicates
  across branches are collapsed.
- Same-document targets (`target_record_id = record_id`) are excluded — the reviewer is
  strictly cross-document. Same-document near-duplicates are the job of entity
  reconciliation ([8]), not this reviewer.
- `matches[E]` is capped at `MaxMatchesPerEntity` (default 20), highest-confidence first.

LLM calls run in parallel via `runReviewerConcurrent` (bounded by `REVIEW_MAX_TASKS`);
stop requests are honored at each call boundary (refer to [3] and the doc-processor stop
contract).

### DR2 — Prompt
Create `ChenWeb/prompts/prompt-review-entities-v1.md` and reference it from
`reviewers.entities.prompt` in [2]. The prompt instructs the model to compare one "entity
under review" against a set of matching entities drawn from other documents and to emit
findings only for genuine cross-document discrepancies about what is plausibly the **same
real-world entity** — conflicting type/classification, conflicting definitions or
descriptions, contradictory attributes, or incompatible aliases — not mere restatements
or two genuinely different entities that merely share a name. Output conforms to the
standard review-finding JSON contract (see Data Formats).

### Alternative Decisions
- **Corpus-wide category-sibling branch (as in the metric reviewer):** rejected for
  entities. Entity `categories` are broad type buckets (e.g. `organization`, `standard`,
  `person`); a `?|` overlap match would pair an entity with hundreds of unrelated
  same-type entities, swamping the LLM with noise. Name identity (Branch B) is the precise
  signal for entity consistency.
- **Read `kb.entity_merge_candidates` (reconciliation pairs) as a branch:** deferred.
  Reconciliation ([8]) decides *identity* (should two entities be merged) and already
  compares descriptions for that purpose; this reviewer instead reports *factual conflicts*
  between entities that remain distinct rows. Folding in merge candidates would overlap the
  reconciliation pipeline and is left as a possible future recall path.
- **Live hybrid search at review time:** rejected for the same reasons as the metric /
  provisions reviewers — duplicates index-time work, non-deterministic w.r.t. index state,
  more expensive.
- **Tool-use (agentic) reviewer (`max_tool_turns > 0`):** not adopted. The reviewer
  pre-fetches matches and compares in one shot via `ExtractJSON`; `max_tool_turns` stays
  `0`. Revisit only if the model needs to pull additional context (full entity context,
  related relations) to judge conflicts.
- **New `ReviewStrategy` enum value + scheduler branch:** rejected as unnecessary, exactly
  as in [4]. A reviewer whose `Input` is neither `per-chunk` nor `per-block` is already
  routed to `runReviewersLegacy`, which calls `ReviewDocument`. The entity reviewer uses
  that path with `Input="artifact"`.

### Database Migrations
**None.** Reads `kb.entities`, `kb.artifact_connections`, and `kb.inputs`; writes findings
to the existing `kb.doc_review_findings` (run-scoped via `run_id`, [5]). No new table,
column, or `kb.search_artifacts` partition.

### Data Formats

**Entity view (loaded from `kb.entities`)** — the "entity under review":

```json
{
  "entity_id": "1001_e_4",
  "entity": "中国石化",
  "entity_en": "Sinopec",
  "entity_type": "组织",
  "entity_type_en": "organization",
  "aliases": ["中国石油化工集团", "Sinopec Group"],
  "desc_text_en": "A Chinese oil and gas enterprise headquartered in Beijing.",
  "categories": ["organization", "energy"]
}
```

**Matching entity** — same shape plus match provenance:

```json
{
  "entity": { ... entity view ... },
  "source_record_id": 2002,
  "source_filename": "annual_report_2024.pdf",
  "match_via": "hybrid_search | name",
  "confidence": 0.0123
}
```

**Finding output** — the standard review-finding JSON (`ReviewFinding`); the reviewer sets
`Pass="P5"`, `Aspect="entities"`, defaults `finding_type="issue"`, `severity="low"`, and
`location` from the entity's `line_spans` when the model leaves them empty, mirroring
`grammarSpellingReviewer` and the metric/provisions reviewers.

### Environment Variables
- `REVIEW_MAX_TASKS` (existing) — bounds the per-entity LLM fan-out.
- `ENTITY_REVIEW_MAX_MATCHES` (new, optional, default `20`) — cap on matching entities per
  doc entity.
- `ENTITY_REVIEW_MAX_ENTITIES` (new, optional, default `0` = no cap) — cap on the number of
  doc entities reviewed (safety valve for entity-heavy documents).
- No new model/prompt env vars: model and prompt come from `reviewers.entities` in [2] via
  the existing `resolveReviewerRuntime` path.

## Implementation

### Code Changes

| File | Change |
|---|---|
| `ChenWeb/server/api/doc-reviews/review-entities.go` | **New.** `entitiesReviewer` implementing `Reviewer` (`Name()="entities"`, `Group()="P5"`, `Strategy()=StrategyDocument`). `ReviewDocument` loads the doc's entities, builds matches via the shared connection loader (Branch A hybrid_search entity→entity) + a corpus-wide name-sibling scan (Branch B), resolves target entities, and fans out one LLM call per matched entity with `runReviewerConcurrent`. Stop-aware. Mirrors `review-provisions.go`. |
| `ChenWeb/server/api/doc-reviews/review-document.go` | Resolve `entities`/P5 runtime in `NewReviewProcessor`; store client/model/prompt fields on `ReviewProcessor`; append the `entitiesReviewer` runner in `buildReviewers` with `cfg.Input="artifact"`. |
| `ChenWeb/server/api/doc-processing/connections_store.go` | Reuses `LoadConnectionsBySource` (outbound) **and** `LoadConnectionsByTarget` (inbound), both added by ADR 2026063002 — no change needed here. |
| `ChenWeb/doc-review.local.toml` | New `[reviewers.entities]`: `input="artifact"`, `prompt="prompt-review-entities-v1.md"`, `max_tool_turns=0`. Model `deepseek-v4-pro`. |
| `ChenWeb/prompts/prompt-review-entities-v1.md` | **New** prompt (DR2). |
| `ChenWeb/server/api/doc-reviews/review-entities_test.go` | **New** tests (assembly branches/dedup/exclusion/cap; reviewEntity payload + tagging). |

Target resolution maps an edge `(target_record_id, target_id=entity_id)` to a
`kb.entities` row. Because `entity_id` is globally unique (`"<record>_e_<seq>"`),
resolution batches by `entity_id` (`WHERE entity_id = ANY($1)`), like the metric /
provisions reviewers.

## Operational Behaviors
- **No entities / no matches:** if the document has no `kb.entities` rows, or no entity has
  any cross-document match, the reviewer returns zero findings (logged, not an error).
- **Dependency:** meaningful after `extract_entity_relation` and the entity-indexing step
  have written `hybrid_search` edges. Absent those edges, Branch A contributes nothing and
  only the name scan (Branch B) applies.
- **Parallelism & stop / idempotency:** identical to the metric / provisions reviewers and
  all reviewers — concurrent per-entity calls under `REVIEW_MAX_TASKS`, stop at the next
  boundary (`ErrPipelineStopped`), findings written under the current `run_id` (prior run
  findings deleted by `PostProcessIndex`, [5]).

## Consequences

**Positive**
- Cross-document entity consistency: conflicting types, definitions, descriptions, or
  attributes for the same real-world entity across the corpus — which no single-document
  reviewer can see.
- Reuses precomputed `hybrid_search` edges and the existing reviewer plumbing (loader,
  legacy path, finding store); no schema or scheduler change.
- The bilingual view lets the model catch conflicts that span Chinese/English sources.

**Negative / cost**
- Match quality bounded by the freshness/quality of the entity `hybrid_search` edges and by
  name-normalization quality; homonyms (different entities sharing a name) surface as
  candidates and rely on the LLM to reject them.
- Per-entity LLM fan-out can be large for entity-heavy documents; bounded by
  `ENTITY_REVIEW_MAX_ENTITIES` and `MaxMatchesPerEntity`.
- The name-sibling scan is corpus-wide; it is bounded by a `LIMIT` and indexed lookups on
  `entity`/`entity_en`, but a very large corpus with very common names can still return
  many candidates (capped before the LLM call).

## Tests
- Branch A (outbound): a doc entity with an outbound `hybrid_search` edge to a
  cross-document entity → one LLM call, finding tagged `P5`/`entities`.
- Branch A (inbound): a doc entity that is the `target` of a `hybrid_search` edge from a
  later-indexed document's entity is matched (resolved from the edge `source`); duplicates
  across both directions collapse to one match.
- Branch B: a name-sibling in another document sharing a normalized name with a doc entity
  is attached to that entity, `via="name"`.
- Dedup: a target reached via both branches appears once.
- Same-document exclusion: a target with `target_record_id = record_id` is dropped.
- Cap: `MaxMatchesPerEntity` truncates to highest-confidence matches.
- No matches → no LLM call, no findings.
- `reviewEntity` payload contains `entity_under_review` + `matching_entities`; findings get
  `Pass=P5`/`Aspect=entities` and default severity/type/location.

## Documentation Impact
- `doc-processor/+CAPSULE.md` [1]: no pipeline-table change (entities review is an aspect,
  not a doc processor).
- This ADR + `prompt-review-entities-v1.md` are the design/behavior records. Shares the
  connection-loader and reviewer-integration design with ADRs 2026063002 [4] and
  2026063003 [6].
- Intentionally left undocumented: entity `hybrid_search` edge weighting (owned by
  `search_artifact_indexing.go` / the entity-indexing spec); the deferred
  merge-candidate branch and live-search fallback; the relationship to entity
  reconciliation ([8]), beyond the note that this reviewer is complementary (conflicts in
  distinct rows) rather than an identity decision.

## References
- [1] `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md`
- [2] `ChenWeb/doc-review.local.toml`
- [3] `KnowledgeStore/doc-repo/adrs/202606/2026062804-adr-doc-review-run.md` (run model) and `ChenWeb/server/api/doc-reviews/review_cache_scheduler.go` (dispatch)
- [4] ADR 2026063002 — Metric Document Reviewer (shared architecture, connection loader)
- [5] ADR 2026062804 — `kb.doc_review_runs` run model (run-scoped findings)
- [6] ADR 2026063003 — Provisions Document Reviewer (two-branch artifact reviewer)
- [7] `ChenWeb/server/api/doc-processing/search_artifact_indexing.go`, `search_indexing.go` (entity indexing + `searchArtifactEntity` type)
- [8] `ChenWeb/server/api/doc-processing/entity-reconciliation.go`, `entity-reconciliation-store.go` (`kb.entity_merge_candidates`, identity merging)
