# Semantic Clustering — Design Spec

- **DocID:** `doc-2026062001`
- **Status:** Accepted — implemented (P1 entity semantic clustering)
- **Date:** 2026-06-20
- **Component:** Doc Processor — Post-Processing (Phase C)
- **Authors:** Chen Ding
- **Tags:** semantic-clustering, entity-resolution, identity, hybrid-search, llm-adjudication

---

## Overview

**Semantic Clustering** is a post-extraction identity resolution step that determines
whether a newly extracted artifact refers to the *same real-world thing* as
existing artifacts already in the knowledge base, and merges them into a single
canonical node when it does.

It applies to **all** artifact types (entities, relations, metrics, provisions,
etc.), but is rolled out one type at a time, starting with **entities**.

### Motivation

The same real-world entity ("Odor Treatment Facility") surfaces in many
documents — sometimes under different surface forms, different languages, or
different levels of detail. The extraction pipeline produces one `entity_id` per
document (*per-document consolidation* via `consolidateEntities` at Phase 1.5),
but nothing merges those IDs across documents. The result is N rows for one
real-world entity in `kb.entities`.

Lexical normalization (exact name + alias match) catches the easy duplicates.
It cannot catch the hard ones: synonyms, translations, abbreviations, or
near-identical-but-not-identical surface forms. Semantic Clustering closes that
gap by using the same **hybrid search infrastructure** (BM25 + pgvector RRF on
`kb.search_artifacts`) that already exists for ranked discovery, repurposed as a
**candidate-generation (blocking)** mechanism, followed by an **LLM adjudicator**
that decides true identity.

### Artifact independence

An entity is *extracted from* a document but is conceptually
**document-independent**: the same real-world entity recurs across many documents.
Identity must therefore be decided on the entity's **own intrinsic attributes**
(name, aliases, type, description, keywords, categories — called the *identity
signature*), never on the source document's text or line evidence.

---

## Scope and rollout order

| Phase | Artifact type | Table | Search partition |
|---|---|---|---|
| P1 | Entity | `kb.entities` | `kb.search_artifacts_entity` | **Implemented** (2026-06-20) |
| P2 | Inventory item | `kb.inventory_items` | `kb.search_artifacts` (`artifact_type = 'inventory_item'`) | **Implemented** (2026-06-20) |
| P3 | Relation | `kb.relations` | `kb.search_artifacts_relation` | Deferred |
| P4+ | Metric, provision, … | respective tables | respective partitions | Deferred |
| P5 | Category (all types) | `kb.artifact_categories` | Direct pgvector + BM25 on `kb.artifact_categories` | Deferred |

This spec documents P1 (entities) in full and P2 (inventory items) as an appendix.
Each subsequent phase will add an appendix rather than a separate spec.

---

## Integration point: Phase C post-processing

Semantic clustering runs **after** an entity is persisted and reindexed into
`kb.search_artifacts_entity` — i.e., **at the end of Phase C**, as the last step
in the entity post-processor. This timing guarantees:

1. The newly extracted entity already has an `entity_id` and a
   `kb.search_artifacts_entity` row (with an embedding if
   `SEARCH_SEMANTIC_ENABLED=true`), so it is discoverable by hybrid search.
2. The entity's own attributes (name, type, description, etc.) are fully
   available for the identity signature.
3. Clustering does **not** block Phase B extraction or the Phase C indexing of
   other artifact types.

### Self-exclusion

Before searching, the new entity's own `artifact_id` is excluded from results
(WHERE clause `artifact_id <> $selfID`). Without semantic search enabled, the
lexical-only fallback may still return the self-entry; validate and skip it.

---

## Algorithm (P1 — Entities)

```
for each newly extracted entity E in record R:
    1.  SEARCH
        Hybrid-search kb.search_artifacts_entity with E.search_document
        (BM25 + pgvector RRF, same query path as the existing read-path).
        Exclude E.artifact_id from results.

    2.  NO MATCH
        If no result passes the coarse filter (step 3) →
            Mark E as its own cluster head:
              canonical_entity_id = E.entity_id   (self-reference)
              reconcile_status    = 'clustered'
            Continue to next entity.

    3.  COARSE FILTER
        Keep only candidates where ALL of:
          semantic_cosine  ≥ SEMCLUSTER_MIN_BLOCK_COSINE  (default 0.85)
          entity_type      = E.entity_type  OR  entity_type_en = E.entity_type_en
          category overlap ≥ 1 shared category (if both have non-empty categories)
        → candidate set C

    4.  FORM WORK UNIT
        One group G = {E} ∪ C  (a star centered on E).
        If C contains entities that are themselves blocked as candidates
        (they share a pending pair in kb.entity_merge_candidates, or are in
        the same cluster), include those edges — but G is the smallest
        connected component containing E.

    5.  BATCH
        Pack SEMCLUSTER_GROUP_SIZE (default: 3) groups into one LLM call (see §Batching below).

    6.  HYDRATE (identity signature only)
        For each member in G, load:
          entity_id, entity (+_en), aliases (+_en), entity_type (+_en),
          desc (+_en), keywords (+_en), categories, entity_status,
          canonical_entity_id, reconcile_status
        Carry doc_name / input_record_id as provenance label only.
        Carry the search cosine + lexical scores as a why-grouped hint.
        Do NOT load entity_context, line_spans, or document text.

    7.  LLM ADJUDICATE
        Send to LLM: partition G into identity sets.
        Output: groups (merge), keep_separate, defer, uncertain.
        Confidence calibrated 0.0–1.0 per proposed merge.

    8.  DECISION POLICY
        confidence ≥ SEMCLUSTER_MERGE_MIN  (default 0.90) → apply merge
        confidence ≥ SEMCLUSTER_HUMAN_MIN  (default 0.60) → needs_human
        confidence <  human-min            → keep separate
        defer / uncertain                  → deferred / needs_human

    9.  APPLY MERGE (reversible)
        For each confirmed group:
          - elect survivor (deterministic, not LLM-chosen)
          - set absorbed.canonical_entity_id = survivor.entity_id
          - union aliases / keywords / categories onto survivor
          - repoint kb.relations.subject/object_entity_id to survivor
          - write reversible kb.entity_merges row
          - set absorbed.reconcile_status = 'merged'
          - promote provisionals (entity_status → 'extracted')
          - set survivor.reconcile_status = 'clustered'
```

### Batching

- When **one entity** produces a work unit, the LLM sees one group only —
  focused, no contamination risk. Prompt overhead is acceptable because the
  common case is either no candidates (quick skip) or a single candidate pair.
- When **multiple new entities** from the same document each produce their own
  independent groups, pack up to `SEMCLUSTER_GROUP_SIZE` (default 3) groups into
  one LLM call to amortize prompt overhead. Each group is labelled with a
  `group_id`; each output block is keyed by `group_id`; and the reconciler
  **discards any returned merge whose members span two input `group_id`s**
  (deterministic cross-group guard).
- Batching uses a stable sort key so re-runs produce identical batch composition.
- Groups are always **disjoint** (by construction: a new entity's candidates are a
  star around it; different new entities trigger different stars). So cross-group
  contamination = the model inventing connections never proposed — the guard
  above neutralizes it.

### Survivor election

Survivor election is **deterministic** and happens in the reconciler, **not
the LLM** (the LLM's `canonical_name` suggestion is kept only as an enrichment
hint). Reuse `electSurvivor` from `entity-reconciliation.go`:

1. Prefer `extracted`-status over `provisional`.
2. Then prefer the entity with the richer surface-form set (more aliases / names).
3. Then prefer the lexicographically smaller `entity_id` (deterministic tie-break).

This guarantees reproducible identity — two runs produce the same cluster head
regardless of LLM tie-breaking.

### Deferred / uncertainty handling

The online semantic clustering path only auto-applies high-confidence merges.
Lower-confidence outputs from the LLM (`keep_separate`, `defer`, `uncertain`)
are **not persisted** to `kb.entity_merge_candidates` in the online path —
they are silently skipped. The batch reconciler (ADR 2026061701) is the
designated path for handling these through the full tiered pipeline.

- **`merge ≥ confidence`** → apply merge now (reversible, with `kb.entity_merges`
  provenance).
- **`keep_separate`, `defer`, `uncertain`** → skipped in the online path; the
  batch reconciler picks them up when scheduled.

### Idempotency and re-processing

- An entity that already has `reconcile_status = 'clustered' | 'merged'` is
  **skipped** — it has already been through clustering.
- An entity whose `canonical_entity_id` points to another `entity_id` is
  **skipped** — it was absorbed into a cluster.
- On `force = true` re-processing, clear the prior `canonical_entity_id` and
  `reconcile_status` first (same as setting `reconcile_status = 'pending'`
  via the `content_fingerprint` mechanism, R6).
- The merge step is **idempotent** — re-applying a merge that was already applied
  is a no-op (the absorbed row already points to the survivor).

### Concurrency

Two documents processed concurrently may each extract the same new entity:

1. Doc A finishes Phase C first → entity X gets `reconcile_status = 'clustered'`,
   `canonical_entity_id = X.entity_id` (head of its own cluster).
2. Doc B finishes Phase C → entity Y's hybrid search finds X as a candidate →
   LLM confirms identity → Y merges into X.

This is correct regardless of order: the first one becomes the head, the second
folds in. If **both** finish simultaneously and each sees the other as a
candidate, DB-level advisory locking on `canonical_entity_id` prevents a
double-head race. Alternatively, the batch reconciler (ADR 2026061701) re-checks
all `pending` entities and collapses any residual duplicates.

### Graceful degradation

- **Feature flag off** (`SEMCLUSTER_ENABLED = false`): `semClusterEntities` returns
  immediately; entities are left with `reconcile_status = NULL` (or `pending`).
  The batch reconciler (ADR 2026061701) picks them up later if scheduled.
- **Model / prompt unavailable** (`SEMCLUSTER_ADJ_MODEL_NAME` or
  `SEMCLUSTER_ADJ_PROMPT` unresolvable): logged with a diagnostic message naming
  the missing env vars; function returns early. Entities stay unclustered.
- **LLM adjudication error** (primary model fails): retries with
  `SEMCLUSTER_ADJ_FALLBACK` if configured. If both fail, all pending entities
  are marked as cluster heads (`reconcile_status = 'clustered'`,
  `canonical_entity_id` self-referential) — the safe default: no false merges,
  and the batch reconciler can re-merge them later.
- **Search degraded** (`SEARCH_SEMANTIC_ENABLED = false`): hybrid search falls
  back to lexical-only (BM25). Candidate recall is lower (misses pure semantic
  duplicates like translations / synonyms with no shared tokens) but the algorithm
  runs correctly.
- **pgvector unavailable**: embeddings are NULL in `kb.search_artifacts_entity`.
  The semantic branch of RRF returns nothing; the lexical branch carries the full
  load. Same behaviour as semantic disabled.

---

## Environment variables

| Name | Default | Purpose |
|---|---|---|
| `SEARCH_SEMANTIC_ENABLED` | `false` | Must be `true` for pgvector semantic candidate retrieval |
| `SEMCLUSTER_ENABLED` | `false` | Feature flag — gate until validated |
| `SEMCLUSTER_MIN_BLOCK_COSINE` | `0.85` | Cosine floor for coarse filter; candidates below this are discarded before LLM |
| `SEMCLUSTER_ADJ_MODEL_NAME` | — | LLM model for adjudication; resolved via `MODEL_DEF_FILE` |
| `SEMCLUSTER_ADJ_FALLBACK` | — | Optional fallback model ref; tried if primary adjudication fails |
| `SEMCLUSTER_ADJ_PROMPT` | `prompt-entity-adjudicate-v1.md` | Prompt file ref |
| `SEMCLUSTER_MERGE_MIN` | `0.90` | LLM confidence floor for auto-merge |
| `SEMCLUSTER_HUMAN_MIN` | `0.60` | LLM confidence floor for `needs_human`; below → keep separate |
| `SEMCLUSTER_GROUP_SIZE` | `3` | Max groups packed into one LLM call |
| `SEMCLUSTER_BATCH_MAX_ENTITIES` | `40` | Token/entity budget for packing |

---

## Schema impact

Zero new tables or columns. Semantic clustering reuses the schema already landed
by ADR 2026061701 migration `20260617000004_create_kb_entity_reconciliation_tables.sql`:

- `kb.entities.canonical_entity_id` — the cluster head
- `kb.entities.reconcile_status` — `pending` → `clustered` (head) or `merged` (absorbed)
- `kb.entity_merge_candidates` — blocking candidates, written for every proposed
  pair (including `deferred` and `needs_human`)
- `kb.entity_merges` — immutable, reversible merge provenance
- `kb.relations_resolved` — canonical-resolving view

---

## Relation to ADR 2026061701 (batch reconciler)

Semantic Clustering and the batch reconciler are **siblings in the same
architecture**, not competitors:

| Property | Semantic clustering (this spec) | Batch reconciler (ADR 2026061701) |
|---|---|---|
| Trigger | New entity extracted (online) | Watermark over `kb.entities.modify_time` (periodic) |
| Blocking | Hybrid search (BM25 + pgvector RRF) | Lexical (`pg_trgm` + exact name + alias only) |
| Adjudication | LLM (same `MergeAdjudicator` seam) | Same |
| Apply | Reuse R3/R7 (same) | Same |
| Scope | One new entity + its top-N search neighbours | All entities changed since watermark |
| Purpose | Catch duplicates immediately at extraction time | Backstop: catch residue from concurrency races, later-added aliases, and entities whose enrichment changed their blocking neighbourhood |

The two share the `MergeAdjudicator` interface and the `electSurvivor` /
`ApplyMerge` / reversible-merge machinery. They differ only in *how candidates
are generated* (search vs. SQL blocking) and *when they run* (online vs. batch).

The batch reconciler remains required even with semantic clustering online,
because (a) concurrency races can produce duplicate heads (see §Concurrency),
(b) entities whose aliases / descriptions are enriched later may become mergeable
only after their content fingerprint changes, and (c) the batch run provides a
periodic full-coverage audit.

---

## Tests

- Coarse filter: a candidate at cosine 0.84 is excluded; a candidate at
  cosine 0.86 with matching type is included; a candidate at cosine 0.95 with
  conflicting type is excluded.
- Self-exclusion: the new entity is not returned as its own candidate.
- Idempotency: an entity already `clustered` or `merged` is skipped.
- Survivor election: an `extracted` entity beats a `provisional` one; a richer
  surface set beats a thinner one; same surface set uses lexicographic order.
- Batching: 3 independent groups packed into one call; a returned merge spanning
  two group-ids is discarded.
- No-search fallback: with semantic disabled, the lexical-only path still
  produces candidates (fewer, but structurally correct).
- No-LLM fallback: when the adjudicator is unavailable, pending entities are
  marked as cluster heads (safe default); no auto-merge on score alone.
- Reversibility: un-merging a semantic-clustering merge restores
  `canonical_entity_id = NULL` and `reconcile_status = 'pending'` for the
  absorbed entity.
- Promote provisional: a `provisional` entity absorbed into an `extracted` head
  flips to `entity_status = 'extracted'`.

---

## P2 — Inventory Items

Inventory item semantic clustering follows the same algorithm as P1 (entities)
with an inventory-specific identity signature, coarse filter, and store. See the
[Inventory Items Processor spec](file:///Users/cding/Workspace/KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-inventory-items-spec.md#semantic-clustering)
for the full inventory-specific documentation.

### Identity signature

Same set defined in the inventory spec, carried as the LLM adjudication input:

- `inventory_item_id`, `item_name`, `canonical_name`, `categories`
- `manufacturer`, `brand`, `model_number`, `part_number`
- `aliases`, `standards`

Excluded: `normalized_specs`, `raw_specs`, `source_line_spans`, `evidence_quote`.

### Coarse filter differences

No `entity_type` field exists for inventory items. The coarse filter relies on
**category overlap** (`hasCommonCategory`) as the primary gate. When both sides
have empty categories, the gate is skipped.

### Survivor election

Deterministic lexicographic `inventory_item_id` (all items are `extracted`
provenance — no `provisional` equivalent).

### Implementation

| File | Purpose |
|---|---|
| `inventory_item_semantic_clustering.go` | `semClusterInventoryItems`, `InventoryItemClusterStore`, `batchAdjudicateInvItemsAndApply` |
| `project_migrations/20260620000002_add_kb_inventory_item_reconciliation.sql` | Schema: `canonical_item_id`, `reconcile_status`, `reconciled_at`, `kb.inventory_item_merges` |

### Config (env vars)

Shares the global `SEMCLUSTER_ENABLED`, `SEMCLUSTER_MIN_BLOCK_COSINE`,
`SEMCLUSTER_MERGE_MIN`, `SEMCLUSTER_HUMAN_MIN`, `SEMCLUSTER_GROUP_SIZE`, and
`SEMCLUSTER_BATCH_MAX_ENTITIES` from the entity clustering config.

Dedicated adjudication model (falls back to entity `SEMCLUSTER_ADJ_*` when
unset):

| Name | Default | Purpose |
|---|---|---|
| `SEMCLUSTER_INVITEM_ADJ_MODEL_NAME` | (falls back to `SEMCLUSTER_ADJ_MODEL_NAME`) | LLM model for inventory item adjudication |
| `SEMCLUSTER_INVITEM_ADJ_FALLBACK` | (falls back to `SEMCLUSTER_ADJ_FALLBACK`) | Fallback adjudication model |
| `SEMCLUSTER_INVITEM_ADJ_PROMPT` | `prompt-inventory-item-adjudicate-v1.md` (falls back to `prompt-entity-adjudicate-v1.md`) | Adjudication prompt |

---

## P5 — Artifact Categories

`kb.artifact_categories` stores the shared classification ontology used by all artifact
types. The four `category_type` values (`entity`, `inventory_item`, `metric`, `relation`)
partition the ontology into independent namespaces. Within each namespace, the same
real-world concept can surface under different surface forms across documents —
"Wastewater Treatment" vs. "Waste Water Treatment Facility", "WWTP" — producing
duplicate category rows.

Categories differ from per-document artifacts (entities, items, relations) in several
ways that affect the clustering design:

- They are **ontology nodes**, not extraction results: a category is minted once and
  reused across many documents and artifact instances.
- The existing `status = 'merged'` + `canonical_of` columns already encode the merge
  outcome; no additional `reconcile_status` column is needed.
- The **search substrate is the table itself**: `kb.artifact_categories` holds
  `embedding` (pgvector) and `search_document` (BM25 via GIN) directly. There is
  no `kb.search_artifacts_category` partition.
- Clustering is scoped **within each `category_type`** independently. An `entity`
  category and an `inventory_item` category for the same real-world concept are
  intentionally distinct — they serve different classification roles.
- Because new categories are created through a single controlled choke point
  (`createAndMint`), clustering can run exactly once at creation time without
  a periodic batch backstop.

### Integration point

`semClusterCategories` is called at the end of `createAndMint` in
`artifact_category_resolver.go`, **after** the new category row is persisted and
its embedding is populated. This guarantees:

1. The new category is already in `kb.artifact_categories` with a valid `category_id`
   and `embedding`, making it discoverable by the similarity query.
2. The `globalCategoryIndex` has been populated with the new category's canonical key
   and all surface forms returned by the create-LLM.
3. Clustering does not block the extraction pipeline — `createAndMint` is itself called
   asynchronously from the resolver; any clustering error is non-fatal and logged.

A category with `status = 'merged'` or `status = 'rejected'` is **skipped** — it is
already resolved.

### Algorithm

```
for each newly minted category C (category_type T):
    1.  SEARCH
        Similarity search on kb.artifact_categories WHERE category_type = T:
          pgvector cosine distance on embedding  (if SEARCH_SEMANTIC_ENABLED)
          BM25 on search_document                (always)
          RRF fusion of both channels
        Exclude C.category_id from results.
        Exclude rows with status IN ('merged', 'rejected').

    2.  NO MATCH
        If no result passes the coarse filter (step 3) →
            No action; C remains status = 'pending_review'.
            Continue (clustering is complete for this category).

    3.  COARSE FILTER
        Keep only candidates where:
          semantic_cosine  ≥ SEMCLUSTER_MIN_BLOCK_COSINE  (default 0.85)
          candidate.category_type = T  (enforced by the query WHERE clause)
        → candidate set K

    4.  FORM WORK UNIT
        One group G = {C} ∪ K.

    5.  BATCH
        Same batching logic as P1: pack up to SEMCLUSTER_GROUP_SIZE independent
        groups from concurrent creates into one LLM call.

    6.  HYDRATE (identity signature only)
        For each member in G, load:
          category_id, category_key, display_names, aliases, acronyms,
          category_desc, category_keywords, status, canonical_of, seen_count
        Carry the search cosine + lexical scores as a why-grouped hint.
        Do NOT load category_instance rows or document text.

    7.  LLM ADJUDICATE
        Same MergeAdjudicator interface as P1/P2.
        Output: groups (merge), keep_separate, defer, uncertain.
        Confidence calibrated 0.0–1.0 per proposed merge.

    8.  DECISION POLICY
        Same thresholds as P1/P2:
          confidence ≥ SEMCLUSTER_MERGE_MIN  (default 0.90) → apply merge
          confidence ≥ SEMCLUSTER_HUMAN_MIN  (default 0.60) → needs_human (skipped online)
          confidence <  human-min            → keep separate
          defer / uncertain                  → skipped online

    9.  APPLY MERGE (reversible)
        For each confirmed group:
          - elect survivor (deterministic — not LLM-chosen; see §Survivor election)
          - set absorbed.status        = 'merged'
          - set absorbed.canonical_of  = survivor.category_key
          - union absorbed.aliases / display_names / acronyms /
            category_keywords / match_keys onto survivor (jsonb array merge)
          - update globalCategoryIndex: remap absorbed keys → survivor.category_id
          - (optional V2) write kb.category_merges row for audit/reversibility
```

### Identity signature

Fields presented to the LLM adjudicator:

| Field | Purpose |
|---|---|
| `category_key` | Canonical concept key |
| `display_names` | Human-readable labels |
| `aliases` | Alternate surface forms |
| `acronyms` | Short forms |
| `category_desc` | Description text |
| `category_keywords` | Topic keywords |
| `seen_count` | Frequency weight (informational) |
| `status` | Current review status |

**Excluded**: `required_attrs`, `specs`, `plausible_ranges`, `parent_categories`,
`related_categories`, `embedding` — these are downstream enrichment fields that
do not define identity.

### Coarse filter

The `category_type` equality is enforced by the search query's `WHERE` clause, not
a post-query filter, so no additional type check is needed after search. The only
post-search gate is the cosine floor (`SEMCLUSTER_MIN_BLOCK_COSINE`).

When semantic search is disabled, the BM25 branch alone produces candidates.
Recall is lower (misses pure semantic synonyms) but the algorithm is structurally
correct.

### Survivor election

All active categories are either `pending_review` or `approved` — there is no
`provisional/extracted` dichotomy (unlike entities). Survivor election:

1. Prefer `approved` status over `pending_review`.
2. Then prefer the category with the higher `seen_count` (more evidence).
3. Then prefer the lexicographically smaller `category_key` (deterministic tie-break).

### In-process index invalidation

After a merge, the `globalCategoryIndex` must redirect the absorbed category's
normalized keys to the survivor's `category_id`. Without this, subsequent calls to
`categoryResolver.Resolve` for surface forms belonging to the absorbed category
would resolve to the now-merged (non-canonical) row, causing incorrect `category_id`
references on new artifacts.

Concretely: after `status = 'merged'` is written for the absorbed row, call
`ci.putAll(categoryType, absorbed.matchKeys, survivor.category_id)` to overwrite
the in-process entries. The `put` method's `seen_count` tie-break ensures the
survivor's entry wins even under concurrent updates.

### Schema impact

No new columns are required on `kb.artifact_categories`. The existing `status` and
`canonical_of` columns encode the merge outcome.

A `kb.category_merges` audit table is **recommended for V2** to provide reversibility
on the same model as `kb.entity_merges`:

```sql
CREATE TABLE kb.category_merges (
    merge_id        BIGSERIAL    PRIMARY KEY,
    absorbed_id     BIGINT       NOT NULL REFERENCES kb.artifact_categories(category_id),
    survivor_id     BIGINT       NOT NULL REFERENCES kb.artifact_categories(category_id),
    category_type   TEXT         NOT NULL,
    confidence      FLOAT8       NOT NULL,
    adjudication    JSONB        NOT NULL DEFAULT '{}',
    merged_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
```

A pgvector index on `kb.artifact_categories(embedding)` is needed for efficient
similarity search if not already present:

```sql
CREATE INDEX IF NOT EXISTS idx_kb_artifact_categories_embedding
    ON kb.artifact_categories USING hnsw ((embedding::vector(1536)) vector_cosine_ops)
    WHERE status IN ('pending_review', 'approved');
```

The `SEMCLUSTER_ENABLED` gate and existing global `SEMCLUSTER_*` env vars apply
unchanged. A dedicated adjudication model and prompt can be configured:

| Name | Default | Purpose |
|---|---|---|
| `SEMCLUSTER_CAT_ADJ_MODEL_NAME` | (falls back to `SEMCLUSTER_ADJ_MODEL_NAME`) | LLM model for category adjudication |
| `SEMCLUSTER_CAT_ADJ_FALLBACK` | (falls back to `SEMCLUSTER_ADJ_FALLBACK`) | Fallback adjudication model |
| `SEMCLUSTER_CAT_ADJ_PROMPT` | `prompt-category-adjudicate-v1.md` (falls back to `prompt-entity-adjudicate-v1.md`) | Adjudication prompt |

### Implementation

| File | Purpose |
|---|---|
| `artifact_category_semantic_clustering.go` | `semClusterCategories`, coarse filter, `CategoryClusterStore` (atomic merge: `ApplyMerge`, update `globalCategoryIndex`), `batchAdjudicateCategoriesAndApply` |
| `artifact_category_resolver.go` | Call `semClusterCategories` at end of `createAndMint` (non-fatal) |
| `project_migrations/YYYYMMDDXXXXXX_add_kb_category_merges.sql` | Schema: `kb.category_merges` table + pgvector index on `kb.artifact_categories` |

---

## Future phases (P3 — Relations)

Relation semantic clustering follows the same algorithm with a
relation-specific identity signature. Differences to expect:

- The identity signature carries `subject` (+`_en`), `predicate` (+`_en`),
  `object` (+`_en`), `keywords`, `categories` — not a name/alias structure.
- Blocking: hybrid search of `kb.search_artifacts_relation` using the relation's
  `search_document`.
- Coarse filter: predicate identity + endpoint proximity. A relation's identity
  depends on all three components (subject, predicate, object); two relations
  sharing only the predicate are distinct.
- Survivor election and apply rules are the same.

Subsequent artifact types (metrics, provisions, etc.) follow the same pattern
with a type-specific identity signature and coarse filter.

---

## Implementation Status (2026-06-20)

**Landed** (build + unit tests green):

### P1 — Entities

- `semantic_clustering.go` — Core implementation (~500 loc):
  `semClusterEntities` entry point, coarse filter (`sameEntityType`,
  `hasCommonCategory`), adjudication batching (`batchAdjudicateAndApply`),
  primary+fallback model LLM calling (`callAdjudicator`, `callAdjudicatorWithModel`),
  cross-group guard, deterministic survivor election (`electSurvivorFromIDs`),
  env var accessors, diagnostic logging distinguishing "disabled" from
  "model/prompt unavailable."
- `semantic_clustering_test.go` — 35 unit tests covering the coarse filter,
  survivor election, adjudication result parsing, cross-group guard, env var
  defaults, confidence threshold gating, JSON serialization.
- `prompts/prompt-entity-adjudicate-v1.md` — LLM prompt: identity partitioning
  with explicit negative guidance, few-shot examples, `defer`/`uncertain` output.
- `artifact_postprocess_indexing.go` — Wiring: `semClusterEntities` is called
  in `EntityRelationProcessor.PostProcessIndex` after entity search registry
  reindex, before line-overlap indexing. Non-fatal on failure.
- `entity-relation-split.go` — Wiring: `EntityProcessor.PostProcessIndex` calls
  `semClusterEntities` *before* the relations-exist short-circuit, so entities
  are clustered even when only the entity processor runs and relations already
  exist for the record.
- DB column names: queries use `desc_text` / `desc_text_en` (the actual
  `kb.entities` columns), not the shorthand `desc` / `desc_en` used in the
  adjudication prompt contract.
- Fallback model: `SEMCLUSTER_ADJ_FALLBACK` env var; if the primary adjudication
  model errors, the same input is retried with the fallback before returning the
  error.

### P2 — Inventory Items

- `inventory_item_semantic_clustering.go` — Core implementation (~330 loc):
  `semClusterInventoryItems` entry point, coarse filter (`hasCommonCategory`),
  adjudication batching (`batchAdjudicateInvItemsAndApply`),
  primary+fallback model LLM calling (`callInvItemAdjudicator`,
  `callInvItemAdjudicatorWithModel`), cross-group guard (`allInvInSameGroup`),
  deterministic survivor election (`electSurvivorFromIDs`, reused from P1),
  `InventoryItemClusterStore` (atomic merge with `ApplyMerge`, `MarkClustered`),
  pending-item loading queries (`loadPendingInventoryItemsForSemCluster`,
  `loadInventoryItemForSemCluster`).
- `inventory_item_indexing.go` — Wiring: `semClusterInventoryItems` called in
  `InventoryItemsProcessor.PostProcessIndex` after search registry reindex,
  before line-overlap connections and indexing. Non-fatal on failure.
- `project_migrations/20260620000002_add_kb_inventory_item_reconciliation.sql` —
  Schema: `kb.inventory_items` adds `canonical_item_id`, `reconcile_status`,
  `reconciled_at`; creates `kb.inventory_item_merges` table.
- Config: shares global `SEMCLUSTER_*` settings; dedicated `SEMCLUSTER_INVITEM_ADJ_*`
  env vars for adjudication model and prompt, with fallback to entity `SEMCLUSTER_ADJ_*`.

### New files (both phases)

| File | Purpose |
|---|---|
| `ChenWeb/prompts/prompt-entity-adjudicate-v1.md` | Entity adjudication prompt |
| `ChenWeb/server/api/doc-processing/semantic_clustering.go` | Entity core implementation |
| `ChenWeb/server/api/doc-processing/semantic_clustering_test.go` | Entity unit tests |
| `ChenWeb/server/api/doc-processing/inventory_item_semantic_clustering.go` | Inventory item core implementation |
| `ChenWeb/project_migrations/20260620000002_add_kb_inventory_item_reconciliation.sql` | Inventory item reconciliation migration |

### Modified files

| File | Change |
|---|---|
| `ChenWeb/server/api/doc-processing/artifact_postprocess_indexing.go` | `semClusterEntities` call in `EntityRelationProcessor.PostProcessIndex` |
| `ChenWeb/server/api/doc-processing/entity-relation-split.go` | `semClusterEntities` call in `EntityProcessor.PostProcessIndex` |
| `ChenWeb/server/api/doc-processing/inventory_item_indexing.go` | `semClusterInventoryItems` call in `InventoryItemsProcessor.PostProcessIndex` |

**Deferred:**

- P3 (Relation semantic clustering) — identical algorithm, blocked on the relation
  identity signature and prompt.
- P4+ (other artifact types) — follow-on.
- The batch `Reconciler.Run` (ADR 2026061701) is still not scheduled — the online
  semantic clustering handles new entities/items at extraction time; the batch
  reconciler remains the backstop for concurrency residue and is a separate
  implementation task.
- Stage 2 (deferred context escalation) — the `handleDeferred` function exists in
  the reconciler design but is not yet implemented; `deferred` candidates accumulate
  harmlessly in `kb.entity_merge_candidates`.

**New files:**

| File | Purpose |
|---|---|
| `ChenWeb/prompts/prompt-entity-adjudicate-v1.md` | Adjudication prompt |
| `ChenWeb/server/api/doc-processing/semantic_clustering.go` | Core implementation |
| `ChenWeb/server/api/doc-processing/semantic_clustering_test.go` | Unit tests |

**Modified files:**

| File | Change |
|---|---|
| `ChenWeb/server/api/doc-processing/artifact_postprocess_indexing.go` | `semClusterEntities` call in `EntityRelationProcessor.PostProcessIndex` |
| `ChenWeb/server/api/doc-processing/entity-relation-split.go` | `semClusterEntities` call in `EntityProcessor.PostProcessIndex` (before relations-exist short-circuit) |

## References

[1] ADR 2026061701 — Corpus-Level Entity Reconciliation (batch reconciler; block →
    adjudicate → apply → enrich).

[2] ADR 2026061303 — Entity-relation extraction: entity-linked relations + Change 04
    (hybrid-search merge proposal analysis).

[3] 2026060201-spec-hybrid-search.md — Hybrid search (BM25 + pgvector RRF).

[4] artifact-connections.md — Artifact connection design (entity §3.8).

[5] entity-reconciliation.go — `Reconciler`, `electSurvivor`,
    `MergeAdjudicator` interface.

[6] entity-reconciliation-store.go — `ReconcileSQLStore`, `BlockCandidates`,
    `ApplyMerge`.

[7] search_artifact_indexing.go — `entityIndexConfig`, `IndexEntitiesForRecord`.

[8] artifact_indexing.go — `connectArtifactsBySearch`.

[9] semantic_clustering.go — `semClusterEntities`, `callAdjudicator`,
    `parseAdjudicationResult`.

[10] prompt-entity-adjudicate-v1.md — Adjudication prompt.
