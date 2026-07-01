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

### How this reviewer works (same shape as the metric reviewer)

Like `metrics` (and `provisions`/`entities`), this reviewer does **not** read the
document text. It consumes already-extracted `kb.inventory_items` rows and the
precomputed artifact graph (`kb.artifact_connections`). It is therefore a
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
list of **matching inventory items** drawn from the precomputed artifact graph, then
issues one LLM call per item that has at least one match. Pseudocode (mirrors the metric
reviewer's three branches):

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

   append resolved matches to matches[I]   (deduped by the matching item's (record_id, inventory_item_id);
                                            same-document hits excluded)

# Branch B: item -> items sharing an item category (corpus-wide)
for each category key C in I.item_categories:
   sibling items := kb.inventory_items WHERE item_categories @> C AND input_record_id <> record_id
   append sibling items to matches[I]   (deduped, capped)

# Branch C: entity -> items related to that entity
for each entity E extracted from the document-under-review:
   edges := load kb.artifact_connections WHERE
              source_type='entity' AND source_record_id=record_id AND source_id=E.artifact_id
              AND target_type='inventory_item'
   for each resolved target item IT:
      attach IT to every doc item that shares an item_category with IT
      (if none shares a category, IT is skipped)

# LLM comparison (parallel)
for each item I in matches where len(matches[I]) > 0:
   launch one LLM call (configured model + prompt) with:
       - the item under review (I)
       - all matching items (deduped, capped at MaxMatchesPerItem)
   parse findings; tag Pass="P5", Aspect="inventory_items"
```

LLM calls run in parallel via the shared reviewer concurrency helper
(`runReviewerConcurrent`, bounded by `MaxConcurrent` / `REVIEW_MAX_TASKS`); stop requests
are honored at each call boundary (`ErrPipelineStopped`).

Dedup/cap rules (identical to the metric reviewer):
- A matching item is identified by its `inventory_item_id`; duplicates across branches are
  collapsed.
- An item's own document is never a match (`recordID == record_id` excluded), so the
  reviewer is strictly cross-document; same-document near-duplicates are handled by the
  inventory deduplication/reconciliation pipeline, not this reviewer.
- `matches[I]` is capped at `MaxMatchesPerItem` (default 20), highest-confidence first.

### DR2 — Prompt
Create `ChenWeb/prompts/prompt-review-inventory-items-v1.md` and reference it from
`reviewers.inventory_items.prompt` in [2]. The prompt instructs the model to compare one
"inventory item under review" against a set of matching items from other documents and to
emit findings only for genuine cross-document discrepancies (conflicting
manufacturer/brand, model/part numbers, normalized specifications, or applicable
standards for what is plausibly the same catalog item), not mere restatements. Output
conforms to the standard review-finding JSON contract (see Data Formats).

### Alternative Decisions
- **Live hybrid search at review time**: rejected for the same reasons as in [1] —
  duplicates index-time work, is non-deterministic w.r.t. index state, and is markedly
  more expensive. Precomputed edges can be upgraded to a live fallback later without
  changing the finding contract.
- **Category co-membership only (drop hybrid_search edges)**: rejected — the
  `hybrid_search` edges are the semantic match signal and catch cross-document conflicts
  between items that are textually dissimilar but describe the same product.
- **New `ReviewStrategy` enum value + scheduler branch**: rejected as unnecessary. A
  reviewer whose `Input` is neither `per-chunk` nor `per-block` is already routed to
  `runReviewersLegacy`, which calls `ReviewDocument`. The inventory reviewer uses that
  path with `Input = "artifact"`, exactly like `metrics`, `provisions`, and `entities`.

### Database Migrations
**None.** The reviewer reads existing tables (`kb.inventory_items`,
`kb.artifact_connections`, entities) and writes findings to the existing
`kb.doc_review_findings` (run-scoped via `run_id`, per ADR 2026062804 [5]). No new table,
column, or `kb.search_artifacts` partition is required.

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
  "match_via": "hybrid_search | item_category | entity",
  "confidence": 0.0123
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
| `ChenWeb/server/api/doc-reviews/review-inventory-items.go` | **New.** `inventoryItemsReviewer` implementing `Reviewer` (`Name()="inventory_items"`, `Group()="P5"`, `Strategy()=StrategyDocument`). `ReviewDocument` loads the doc's inventory items + entities, builds the match map via `LoadConnectionsBySource` + category/entity branches, resolves target items, and fans out one LLM call per matched doc item with `runReviewerConcurrent`. Stop-aware. Pure assembly in `assembleInventoryMatches`. |
| `ChenWeb/server/api/doc-reviews/review-document.go` | In `NewReviewProcessor`, resolve `inventory_items`/P5 runtime (`resolveReviewerRuntime`) and store client/model/prompt fields on `ReviewProcessor`. In `buildReviewers`, append the `inventoryItemsReviewer` runner with `cfg.Input="artifact"`. |
| `ChenWeb/server/api/doc-reviews/aspects.go` | Register the `inventory_items` aspect (P5, Label "Inventory Item Consistency", DefaultModel `deepseek-v4-pro`). |
| `ChenWeb/doc-review.local.toml` | Add `[reviewers.inventory_items]` block: `enabled/checked = true`, `group = "P5"`, `input = "artifact"`, `model = "deepseek-v4-pro"`, `prompt = "prompt-review-inventory-items-v1.md"`. |
| `ChenWeb/prompts/prompt-review-inventory-items-v1.md` | **New** prompt (DR2). |
| `ChenWeb/server/api/doc-reviews/review-inventory-items_test.go` | **New** tests (see Tests). |

No new connection loader is required: the generic `LoadConnectionsBySource` (outbound)
and `LoadConnectionsByTarget` (inbound) added for the metric reviewer ([1]) are reused
with `sourceType`/`targetType = "inventory_item"` — Branch A reads both directions. The
reviewer reuses `newDocReviewLLMJSONInput`, `normalizeFindingsJSON`, and
`parseJSONStringArray`, so cache telemetry and finding normalization are identical to
other reviewers.

## Operational Behaviors

- **No items / no matches:** if the document has no `kb.inventory_items` rows, or no item
  has any cross-document match, the reviewer returns zero findings (logged, not an error).
- **Dependency:** meaningful only after `extract_inventory_items` (and for branch C
  `extract_entity_relation`) have run and the artifact-indexing step has written
  `hybrid_search` edges. If those edges are absent, branches A/C contribute nothing and
  only category co-membership (branch B) applies.
- **Parallelism & stop:** per-item LLM calls run concurrently under `MaxConcurrent`; a user
  stop request cancels remaining calls at the next boundary (`ErrPipelineStopped`).
- **Idempotency:** findings are written under the current `run_id`; a re-run deletes the
  run's prior findings first (existing `PostProcessIndex` behavior, [5]).

## Consequences

**Positive**
- Adds cross-document consistency checking for catalog data — conflicting
  manufacturer/brand, model/part numbers, specs, or standards for the same product across
  the corpus — which no text-based reviewer can detect.
- Reuses precomputed `hybrid_search` edges and the generic connection loader: no extra
  search cost and no new query plumbing at review time.
- Integrates through the existing `runReviewersLegacy`/`ReviewDocument` path with no
  scheduler or schema changes; fourth member of the artifact-based P5 reviewer family
  (`metrics`, `provisions`, `entities`, `inventory_items`).

**Negative / cost**
- Match quality is bounded by the freshness/quality of the precomputed `hybrid_search`
  edges; a stale index yields stale matches.
- Per-item LLM fan-out can be large for inventory-heavy documents; bounded by
  `INVENTORY_REVIEW_MAX_ITEMS` and `MaxMatchesPerItem`.

## Tests
- `assembleInventoryMatches`: branch coverage (hybrid_search A, category-sibling B,
  entity C), dedup of a target reached via two branches, same-document exclusion, and cap
  to highest-confidence matches.
- Branch A (inbound): an item that is the `target` of a `hybrid_search` edge from a
  later-indexed document's item is matched (resolved from the edge `source`); duplicates
  across both directions collapse to one match.
- `reviewItem`: payload contains `inventory_item_under_review` + `matching_items`; findings
  are tagged `P5`/`inventory_items` with `finding_type`/`severity`/`location` defaults;
  prompt ref and document-first flag are propagated.
- Item with no matches → no LLM call, no findings.

## Documentation Impact
- This ADR is the design record for the reviewer; `prompt-review-inventory-items-v1.md` is
  the behavior record.
- `aspects.go` gains a new P5 row; `doc-review.local.toml` gains a new reviewer block.
- Intentionally left undocumented: the RRF weighting of `hybrid_search` edges (owned by
  `artifact_indexing.go` / `inventory_item_indexing.go`), and live-search fallback (not
  built) — same boundaries as ADR 2026063002.

## References
- [1] `KnowledgeStore/doc-repo/adrs/202606/2026063002-adr-doc-reviewer-metric.md` (metric reviewer — the template for this design)
- [2] `ChenWeb/doc-review.local.toml`
- [3] `KnowledgeStore/doc-repo/adrs/202606/2026062804-adr-doc-review-run.md` (run model) and `ChenWeb/server/api/doc-reviews/review_cache_scheduler.go` (dispatch)
- [4] `ChenWeb/server/api/doc-processing/connections.go`, `connections_store.go`, `artifact_indexing.go`, `inventory_item_indexing.go` (artifact graph + hybrid_search edges)
- [5] ADR 2026062804 — `kb.doc_review_runs` run model (run-scoped findings)
- [6] `KnowledgeStore/doc-repo/adrs/202606/2026063003-adr-doc-reviewer-provisions.md`, `2026063004-adr-doc-reviewer-entities.md` (sibling artifact-based reviewers)
