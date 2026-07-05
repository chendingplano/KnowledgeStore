# ADR 2026063005 — Inventory-Item Document Reviewer

**Date:** 2026-06-30 \
**Status:** Accepted \
**Component:** ChenWeb — `server/api/doc-reviews`, `server/api/doc-processing` (connection loader), `prompts` \
**Authors**: Chen Ding\
**Tags**: Document Reviewer, Inventory Item, Cross-Document Consistency

## Change Logs
* 2026/06/30, ADR Created — models the inventory-item reviewer on the metric reviewer
  (ADR 2026063002 [1]); same cross-document, artifact-based design, applied to
  `kb.inventory_items` instead of `kb.metrics`.
* 2026/06/30, Branch A correctness fix (mirrors ADR 2026063002): `hybrid_search` edges
  are directional, so the doc item is on the `target` side of any edge created by a
  document indexed later. Branch A now unions outbound (I=source) and inbound (I=target)
  edges via `LoadConnectionsByTarget`, resolving the opposite endpoint as the match and
  excluding any endpoint with `record_id = record_id`.
* 2026/07/01, Branch A migrated to **on-the-fly** (supersedes the precomputed-edge
  decision in DR1 and the 2026/06/30 correctness fix): semantic item↔item similarity is
  no longer materialized as `hybrid_search` / `semantically_related` edges. Indexing
  (`inventory_item_indexing.go`) stops writing them; the reviewer's Branch A calls
  `docprocessing.FindSimilarArtifactsOnTheFly` (same lexical + pgvector RRF acceptance
  policy) per doc item at review time. Live search is always fresh and direction-free, so
  the A1/A2 inbound/outbound union and `LoadConnectionsByTarget` are no longer used by
  this reviewer. Rationale: any artifact is already discoverable by hybrid search over
  `kb.search_artifacts`; a stored snapshot only duplicates that computation and goes stale
  as the corpus grows. (The metric reviewer, ADR 2026063002, made the same change.)
* 2026/07/03, ADR 2026070201 (AR2/AR3/AR5) implemented for this reviewer: prompt v2
  (`prompt-review-inventory-items-v2.md`), window-first input layout, window-grouped
  seed/stagger execution, `source_doc_authority` + `match_rank` in the matched
  payload, structured `related_artifact_id`/`related_record_id` in findings, and
  tool-use with `get_artifact_context`.
* 2026/07/05, synced with implemented object-centric design (ADR 2026070101):
  inventory-item extraction persists a `self` artifact object for each item, reconciles
  artifact objects to `kb.object_nodes`, and inventory indexing writes `object_id` /
  `belong_to` graph edges.
* 2026/07/05, clarified the reviewer goal to match ADR 2026063002: for each
  inventory-item-under-review, retrieve relevant cross-document inventory items from the
  database, then ask the LLM to review the item with that context. Object-anchored
  retrieval is a match branch. The old document-level entity branch is removed because it
  retrieves items related to entities in the document-under-review, not necessarily items
  relevant to the inventory-item-under-review.

## Context
When a document is added to the knowledge base, the system extracts metrics,
inventory items, provisions, entities, relations and other artifacts via the doc
processors. The metric reviewer (ADR 2026063002 [1]) introduced the first
**artifact-based** review aspect: instead of reading the document body, it loads a
document's already-extracted metrics and cross-references each against semantically
related metrics in *other* documents, surfacing conflicting values, units, or
thresholds for what is plausibly the same quantity.

This ADR applies the identical pattern to **inventory items** (`kb.inventory_items`):
catalog-style artifacts describing physical products / parts (item name, manufacturer,
brand, model number, part number, normalized specifications, applicable standards). The
goal is to detect cross-document inconsistencies such as:
- the same part/model number attributed to **different manufacturers or brands**;
- conflicting **normalized specifications** (e.g. one document lists a valve as `DN50`,
  another as `DN65` for the same model number);
- conflicting **applicable standards** for the same catalog item;
- the same canonical item described with materially contradictory identity attributes.

The reviewer is configured as `reviewers.inventory_items` (group P5) in [2] and assumes
the document-under-review, identified by `record_id` (`kb.inputs.id`), has already been
processed by the `extract_inventory_items` doc processor and its artifact-indexing step.
ADR 2026070101 [7] is implemented for inventory items: each item emits shared
`kb.artifact_objects` rows, reconciles them to canonical `kb.object_nodes`, and indexes
object-node membership edges.

### How this reviewer works (same shape as the metric reviewer)

Like `metrics` (and `provisions`/`entities`), this reviewer does **not** read the
document text. It consumes already-extracted `kb.inventory_items` rows and the
artifact object graph plus live search over `kb.search_artifacts`.
It is therefore a
**cross-document consistency** check, not a single-document text review.

The `extract_inventory_items` artifact-indexing step (`inventory_item_indexing.go`,
binding the shared `artifact_indexing.go` engine with `SelfType = "inventory_item"`)
hydrates every inventory item's `search_document` and embedding into
`kb.search_artifacts`. Semantic item↔item similarity is **not** materialized as
`kb.artifact_connections` edges (see the 2026/07/01 change log): the reviewer computes it
**live** at review time via `docprocessing.FindSimilarArtifactsOnTheFly` (lexical +
pgvector RRF, the same acceptance policy the indexing step used to apply). Live search is
always fresh and needs no directional edge bookkeeping — identical to the metric
reviewer's revised DR1 ([1]).

## Decision
### DR1 — Reviewer logic

The reviewer builds, for each inventory item extracted from the document-under-review, a
list of **matching inventory items** from live semantic search, category siblings, and
object-anchored graph retrieval, then issues one LLM call per item that has at least one
match. The high-level flow is: given an inventory-item-under-review, find relevant
inventory items already in the database, then ask the LLM to review the item with the
document context and matching items. Pseudocode:

```text
matches := map[item] -> []matchingItem   // keyed by the doc's own inventory item

# Branch A: item <-> semantically related items, computed LIVE (no materialized edges).
# A single hybrid search per doc item finds close items across the whole corpus regardless
# of when the other document was indexed, so there is no inbound/outbound direction to union.
for each item I extracted from the document-under-review
        (kb.inventory_items WHERE input_record_id = record_id):
   hits := FindSimilarArtifactsOnTheFly(
              selfType='inventory_item', selfID=I.inventory_item_id,
              candidateType='inventory_item', maxLinks=INVENTORY_REVIEW_MAX_MATCHES)
   resolve each hit -> a kb.inventory_items row (the matching item)

   append resolved matches to matches[I]   (deduped by matching inventory_item_id;
                                            same-document hits excluded)

   # Branch B: item -> items sharing an item category (corpus-wide)
   for each category key C in I.item_categories:
      sibling items := kb.inventory_items WHERE item_categories @> C AND input_record_id <> record_id
      append sibling items to matches[I]   (deduped, capped)

   # Branch C: object-anchored items for the inventory-item-under-review
   objectLinks := kb.artifact_objects ao
      JOIN kb.object_nodes onode ON onode.object_id = ao.object_id
      WHERE ao.source_record_id = record_id
        AND ao.artifact_type = 'inventory_item'
        AND ao.artifact_id = I.inventory_item_id
        AND ao.object_id IS NOT NULL

   for each object node O linked to I:
      peerObjectIDs := O.object_id plus comparable object nodes
                       (same object_type, overlapping normalized_names,
                        reconcile_status <> 'rejected')

      peerEdges := kb.artifact_connections WHERE
         relation_method = 'object_id'
         AND relation_name = 'belong_to'
         AND source_type = 'inventory_item'
         AND target_type = 'object_node'
         AND target_id IN peerObjectIDs

      resolve peerEdges.extra_info.artifact_ids -> kb.inventory_items rows
      append resolved items to matches[I]   (deduped by inventory_item_id;
                                             same-document hits excluded)

# LLM comparison (parallel)
for each item I in matches where len(matches[I]) > 0:
   launch one LLM call (configured model + prompt) with:
       - the item under review (I)
       - all matching items (deduped, capped at MaxMatchesPerItem)
   parse findings; tag Pass="P5", Aspect="inventory_items"
```

LLM calls run through the artifact-review window-grouped executor (bounded by
`MaxConcurrent` / `REVIEW_MAX_TASKS`); stop requests are honored at each call boundary
(`ErrPipelineStopped`). When `max_tool_turns > 0`, the reviewer uses the tool-use loop
with configured read-only tools.

Dedup/cap rules (identical to the metric reviewer):
- A matching item is identified by its `inventory_item_id`; duplicates across branches are
  collapsed.
- An item's own document is never a match (`recordID == record_id` excluded), so the
  reviewer is strictly cross-document; same-document near-duplicates are handled by the
  inventory deduplication/reconciliation pipeline, not this reviewer.
- `matches[I]` is capped at `MaxMatchesPerItem` (default 20), highest-confidence first.

### DR2 — Prompt
The original prompt was `ChenWeb/prompts/prompt-review-inventory-items-v1.md`; current
configuration uses `prompt-review-inventory-items-v2.md`. The prompt instructs the model
to compare one "inventory item under review" against a set of matching items from other
documents and to emit findings only for genuine cross-document discrepancies (conflicting
manufacturer/brand, model/part numbers, normalized specifications, or applicable
standards for what is plausibly the same catalog item), not mere restatements. Output
conforms to the standard review-finding JSON contract (see Data Formats).

### Alternative Decisions
- **Live hybrid search at review time**: originally rejected for the same reasons as in
  [1], then accepted on 2026/07/01. This is now Branch A.
- **Category co-membership only (drop hybrid_search edges)**: rejected — the
  live hybrid-search result is the semantic match signal and catches cross-document conflicts
  between items that are textually dissimilar but describe the same product.
- **Document-level entity branch:** removed from the reviewer design. It used
  entity->inventory_item edges for all entities extracted from the document-under-review,
  then attached targets by item-category overlap. That is a weak
  inventory-item-under-review relevance signal compared with live hybrid search,
  category siblings, and object-anchored retrieval.
- **New `ReviewStrategy` enum value + scheduler branch**: rejected as unnecessary. A
  reviewer whose `Input` is neither `per-chunk` nor `per-block` is already routed to
  `runReviewersLegacy`, which calls `ReviewDocument`. The inventory reviewer uses that
  path with `Input = "artifact"`, exactly like `metrics`, `provisions`, and `entities`.

### Database Migrations
**None for the reviewer.** The reviewer reads existing tables (`kb.inventory_items`,
`kb.search_artifacts`, `kb.artifact_objects`, `kb.object_nodes`, and object-id
`kb.artifact_connections` edges) and writes findings to the existing
`kb.doc_review_findings` (run-scoped via `run_id`, per ADR 2026062804 [5]). No
reviewer-owned table, column, or `kb.search_artifacts` partition is required.

Inventory object extraction/reconciliation tables and object-id connection partitions
are owned by ADR 2026070101, not by this reviewer ADR.

### Data Formats

**Doc inventory item (loaded from `kb.inventory_items`)** — fields passed to the LLM as
the "inventory_item_under_review":

```json
{
  "inventory_item_id": "1001_inv_3",
  "item_name": "球阀",
  "canonical_name": "ball valve",
  "manufacturer": "Acme Valve Co.",
  "brand": "AcmeFlow",
  "model_number": "BV-2200",
  "part_number": "PN-50-316",
  "item_categories": ["valve", "pipe-fitting"],
  "standards": ["GB/T 12237"],
  "normalized_specs": [{"name": "nominal_diameter", "value": "50", "unit": "mm"}]
}
```

**Matching item** — same shape plus provenance of the match:

```json
{
  "item": { ... same fields as above ... },
  "source_record_id": 2002,
  "source_filename": "GB_12237_valves.pdf",
  "match_via": "hybrid_search | item_category | object_anchor",
  "match_rank": 1,
  "source_doc_authority": "standard"
}
```

**Finding output (LLM → `ReviewFinding`)** — the standard review-finding JSON used by
every reviewer:

```json
{
  "severity": "low|medium|high|critical",
  "finding_type": "issue|observation",
  "title": "Conflicting manufacturer for model BV-2200",
  "description": "This document lists model BV-2200 as Acme Valve Co.; doc 2002 lists the same model as Beta Industrial.",
  "evidence": "doc 1001 item 1001_inv_3 vs doc 2002 item 2002_inv_7",
  "location": "120:124",
  "suggestion": "Confirm the manufacturer of record for model BV-2200.",
  "confidence": 0.0
}
```

The reviewer sets `Pass="P5"` and `Aspect="inventory_items"` on every finding (defaulting
`finding_type="issue"`, `severity="low"`, and `location` to the doc item's
`source_line_spans` when the model leaves them empty), mirroring `metricsReviewer`.

### Environment Variables
- `REVIEW_MAX_TASKS` / `MaxConcurrent` (existing) — bounds reviewer-internal parallelism;
  reused for the per-item LLM fan-out.
- `INVENTORY_REVIEW_MAX_MATCHES` (new, optional, default `20`) — cap on matching items per
  doc item.
- `INVENTORY_REVIEW_MAX_ITEMS` (new, optional, default `0` = no cap) — cap on the number of
  doc items reviewed (safety valve for inventory-heavy documents).
- No new model/prompt env vars: model and prompt come from `reviewers.inventory_items` in
  [2] via the existing `resolveReviewerRuntime` path.

## Implementation

### Code Changes

| File | Change |
|---|---|
| `ChenWeb/server/api/doc-reviews/review-inventory-items.go` | `inventoryItemsReviewer` implementing `Reviewer` (`Name()="inventory_items"`, `Group()="P5"`, `Strategy()=StrategyDocument`). `ReviewDocument` loads the doc's inventory items, builds matches from live `FindSimilarArtifactsOnTheFly`, category siblings, and object-anchored item rosters, hydrates source context, and runs window-grouped artifact review units. Tool-use is enabled when configured. |
| `ChenWeb/server/api/doc-reviews/review-document.go` | In `NewReviewProcessor`, resolve `inventory_items`/P5 runtime, budget, and tool config. In `buildReviewers`, append the `inventoryItemsReviewer` runner with `cfg.Input="artifact"`. |
| `ChenWeb/server/api/doc-reviews/aspects.go` | Register the `inventory_items` aspect (P5, Label "Inventory Item Consistency", DefaultModel `deepseek-v4-pro`). |
| `ChenWeb/server/api/doc-processing/extract-inventory-items.go`, `inventory_item_indexing.go` | Persist/reconcile inventory item artifact objects, reindex inventory items in `kb.search_artifacts`, and index object-node/category/shared-line graph edges. Semantic item<->item edges are not consumed from materialized `hybrid_search` edges. |
| `ChenWeb/doc-review.local.toml` | `[reviewers.inventory_items]`: `input="artifact"`, `prompt="prompt-review-inventory-items-v2.md"`, tool-use with `get_artifact_context`. |
| `ChenWeb/prompts/prompt-review-inventory-items-v2.md` | Current prompt (v2 supersedes v1). |
| `ChenWeb/server/api/doc-reviews/review-inventory-items_test.go` | **New** tests (see Tests). |

Branch A uses live search. Branch C uses the implemented object graph:
`kb.artifact_objects` -> `kb.object_nodes` -> object-id `kb.artifact_connections` edges
whose `extra_info.artifact_ids` resolve back to `kb.inventory_items`. The reviewer reuses
artifact-window layout, `newDocReviewLLMJSONInput`, `normalizeFindingsJSON`, tool-use
review plumbing, and `parseJSONStringArray`, so cache telemetry and finding normalization
are identical to other artifact reviewers.

## Operational Behaviors

- **No items / no matches:** if the document has no `kb.inventory_items` rows, or no item
  has any cross-document match, the reviewer returns zero findings (logged, not an error).
- **Dependency:** meaningful only after `extract_inventory_items` has populated
  `kb.inventory_items`, `kb.search_artifacts`, item categories, and the ADR 2026070101
  object graph: artifact-object persistence, object-node reconciliation, and object
  `belong_to` indexing.
- **Parallelism & stop:** per-item LLM calls run concurrently under `MaxConcurrent`; a user
  stop request cancels remaining calls at the next boundary (`ErrPipelineStopped`).
- **Idempotency:** findings are written under the current `run_id`; a re-run deletes the
  run's prior findings first (existing `PostProcessIndex` behavior, [5]).

## Consequences

**Positive**
- Adds cross-document consistency checking for catalog data — conflicting
  manufacturer/brand, model/part numbers, specs, or standards for the same product across
  the corpus — which no text-based reviewer can detect.
- Live hybrid search avoids stale/directional semantic edges while reusing the shared
  lexical/vector search registry and generic graph loaders.
- Object-anchored matching retrieves items tied to the same canonical object as the
  inventory-item-under-review, improving relevance over document-level entity
  co-occurrence.
- Integrates through the existing `runReviewersLegacy`/`ReviewDocument` path with no
  scheduler or schema changes; fourth member of the artifact-based P5 reviewer family
  (`metrics`, `provisions`, `entities`, `inventory_items`).

**Negative / cost**
- Per-item live search adds read-time search cost; bounded by `INVENTORY_REVIEW_MAX_ITEMS`
  and `MaxMatchesPerItem`.
- Per-item LLM fan-out can be large for inventory-heavy documents; bounded by the same
  caps.
- Object-anchored recall depends on inventory object extraction and reconciliation
  quality. Items without a reconciled `object_id` rely on live hybrid search and category
  siblings only.

## Tests
- `assembleInventoryMatches`: branch coverage (hybrid_search A, category-sibling B,
  object-anchor C), dedup of a target reached via two branches, same-document exclusion,
  and cap to highest-confidence matches.
- Branch A: a live hybrid-search hit to a cross-document item is matched; same-document
  hits are excluded and duplicates collapse to one match.
- Branch C: an object-anchored item in another document is attached to the
  inventory-item-under-review through `kb.artifact_objects` -> `kb.object_nodes` ->
  `kb.artifact_connections`.
- `reviewItem`: payload contains `inventory_item_under_review` + `matching_items`; findings
  are tagged `P5`/`inventory_items` with `finding_type`/`severity`/`location` defaults;
  prompt ref and document-first flag are propagated.
- Item with no matches → no LLM call, no findings.

## Documentation Impact
- This ADR is the design record for the reviewer; `prompt-review-inventory-items-v2.md`
  is the current behavior record (`v1` is historical).
- `aspects.go` gains a new P5 row; `doc-review.local.toml` gains a new reviewer block.
- Intentionally left undocumented here: exact live-search RRF weighting (owned by
  `inventory_item_indexing.go` / extract-inventory-items spec). Object
  extraction/reconciliation policy is documented by ADR 2026070101 [7].

## References
- [1] `KnowledgeStore/doc-repo/adrs/202606/2026063002-adr-doc-reviewer-metric.md` (metric reviewer — the template for this design)
- [2] `ChenWeb/doc-review.local.toml`
- [3] `KnowledgeStore/doc-repo/adrs/202606/2026062804-adr-doc-review-run.md` (run model) and `ChenWeb/server/api/doc-reviews/review_cache_scheduler.go` (dispatch)
- [4] `ChenWeb/server/api/doc-processing/connections.go`, `connections_store.go`, `artifact_indexing.go`, `inventory_item_indexing.go` (artifact graph + live-search hydration)
- [5] ADR 2026062804 — `kb.doc_review_runs` run model (run-scoped findings)
- [6] `KnowledgeStore/doc-repo/adrs/202606/2026063003-adr-doc-reviewer-provisions.md`, `2026063004-adr-doc-reviewer-entities.md` (sibling artifact-based reviewers)
- [7] `KnowledgeStore/doc-repo/adrs/202607/2026070101-adr-object-centric-design.md`
- [8] `KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-inventory-items-spec.md`
