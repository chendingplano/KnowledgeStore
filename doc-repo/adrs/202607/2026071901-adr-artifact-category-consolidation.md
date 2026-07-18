# ADR 2026071901 - Artifact Category Consolidation: Typed Namespaces, Membership Edges, and Hierarchy

**Date:** 2026-07-19 \
**Status:** Proposal \
**Component:** ChenWeb \
**Authors**: Chen Ding \

## Change Logs
* 2026/07/19, ADR Created

## Context

The doc-processor pipeline extracts several artifact families (metrics,
compliance provisions, semantic projections, summaries, topics, scene blocks,
entities, relations, inventory items — see
`KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md`). Several of
these families carry **categories** stored in `kb.artifact_categories`, keyed by
`(category_type, category_key)`:

- `metric`, `inventory_item`, `entity`, `relation` are the primary category
  producers (resolver-based creation with LLM enrichment);
- the artifact index configs also declare `summary`, `topic`, `provision`, and
  `scene_block` as `category_type` values
  (`ChenWeb/server/api/doc-processing/search_artifact_indexing.go`,
  `metric_indexing.go`, `inventory_item_indexing.go`,
  `entity_name_indexing.go`, `relation_graph_indexing.go`).

Because each artifact family uses its own `category_type`, the families do
**not** share categories: a metric category `max-temperature` and an entity
category `max-temperature` are distinct rows. Since "sharing the same category"
is an important mechanism to correlate artifacts, the question arose whether the
per-type separation is a design flaw.

Three questions are addressed:

1. Should `kb.artifact_categories.category_type` separate the category
   namespace by artifact type?
2. How should category↔artifact relations be created, maintained, and used —
   `kb.category_instance`, `kb.artifact_connections`, or something else?
3. Categories are currently flat; how do we support hierarchical categories?

### Current-state findings (from code review, 2026-07-19)

- **`kb.category_instance` is dead code.** The table exists (migration
  `20260604000010_create_kb_category_instance.sql`) but no Go code writes or
  reads it. The only remaining references are two comments in
  `ChenWeb/server/api/kbhandler/extract-metric-handler.go`. Two documents still
  claim it is live and are therefore stale:
  - `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md` §7.4
    ("builds `connected_artifacts`, `category_instance`, …");
  - `KnowledgeStore/Capsules/coding-capsules/categories/category-mgmt-spec.md`
    §3 counters note ("artifact↔category usage is tracked by
    `kb.category_instance`").
- **Membership actually lives in `kb.artifact_connections`.** Phase C indexing
  writes one edge per (artifact, category) membership with
  `relation_name = 'belong_to'`, `relation_method = 'category_name'`,
  `target_type = category_type`, `target_id = category_key`, and the surrogate
  `category_id` buried in `extra_info` JSONB
  (`ChenWeb/server/api/doc-processing/artifact_indexing.go`,
  `buildArtifactCategoryConnections` / `upsertArtifactCategoryConnections`).
- **The `category_name` partition has no dedicated indexes.** Migration
  `20260616000004_add_category_name_connection_partition.sql` only creates the
  partition. All parent-table indexes lead with `input_record_id`, so the
  cross-document query "all artifacts in category X" has no usable index.
- **A hierarchy seed already exists but is unused.** `parent_categories` and
  `related_categories` JSONB columns were added by migration
  `20260606000002_add_parent_related_categories_to_kb_artifact_categories.sql`;
  the background enricher populates `parent_categories` from the LLM's
  `subcategory_of` output
  (`ChenWeb/server/api/doc-processing/artifact_category_registry.go`), but
  nothing reads them.
- **A second, disconnected hierarchy exists.** Semantic-projection category
  paths are hierarchical and are indexed into per-leaf tree files on disk
  (`ChenWeb/server/api/doc-processing/category_tree_indexing.go`). Neither
  hierarchy is queryable as a graph in SQL.

## Decision 1: Keep `category_type` — do not merge the category namespace

**Decision:** Retain `kb.artifact_categories.category_type` as a namespace
qualifier. Do not merge categories of different artifact types into a single
shared namespace.

**Rationale:**

- The types are not the same *kind* of thing. A `metric` category names a
  measurement concept (with `plausible_ranges`, units, `required_attrs`); an
  `inventory_item` category names a class of physical things (with `specs`); an
  `entity` category names an ontological class; a `relation` category names a
  predicate type. A shared surface key such as `max-temperature` denotes a
  *measurement concept* in one role and a *class of things* in another. Merging
  the namespaces conflates concept with role.
- The resolver deliberately scopes matching to
  `WHERE category_type = $1` (category-mgmt-spec §resolution) to avoid false
  merges (e.g. `range` the metric span vs. `range` the kitchen appliance). A
  merged namespace removes that guard.
- The Stage-B enrichment prompt takes `category_type` as input; type-specific
  enrichment produces better aliases, specs, and plausible ranges than a
  type-agnostic prompt would.
- **Cross-type correlation is not blocked by the separation.** Membership edges
  store `target_id = category_key` (the human-readable key). Querying
  `target_id = 'max-temperature'` while ignoring `target_type` already returns
  artifacts of every type in that category-key group.

**The real gap is vocabulary drift, not schema.** Each extractor's LLM invents
its own keys, so metrics may emit `max-temperature` while entities emit
`maximum_temperature`; the string join then silently fails. Remediation, in
increasing cost:

1. **Cross-type alias linking during enrichment (adopted).** When the
   background enricher processes a category, it additionally probes the other
   `category_type`s for rows with overlapping `match_keys` and records links in
   the existing `related_categories` column. Cross-type correlation then joins
   through `match_keys` / `related_categories` instead of raw key equality.
2. **Shared concept layer (deferred).** A `kb.concepts` table with an optional
   `concept_id` on each typed category is the textbook answer, but it
   introduces a new cross-type resolution problem (an LLM judgment) and a new
   table. Do not build it until a concrete query needs it.

## Decision 2: `kb.artifact_connections` is the single membership mechanism; drop `kb.category_instance`

**Decision:** Keep the `belong_to` / `category_name` edges in
`kb.artifact_connections` as the only category↔artifact relation store.
Formally drop `kb.category_instance` via a goose migration. Do not maintain two
membership stores.

**Rationale:** The instance table is already dead; reviving it would buy FK
integrity at the price of a second write path that will drift out of sync. The
edge table provides one traversal surface for the whole artifact graph, which
is why `category_instance` was abandoned in the first place.

**Required fixes to the edge-based design:**

1. **Global category→members index.** Add an index on
   `kb.artifact_connections_category_name (target_type, target_id)` (or
   `(target_id)` alone if cross-type grouping becomes the dominant query). The
   partition currently relies on parent indexes that all lead with
   `input_record_id`, so the defining cross-document query has no index.
2. **Merge (`canonical_of`) semantics.** Edges point at `category_key` text
   with no FK; when a category row is later `merged`, existing edges keep
   pointing at the merged-away key. **Resolve `canonical_of` at query time**
   (join through `kb.artifact_categories`) rather than rewriting edges on
   merge: merges are rare, and cross-partition edge rewrites are a background
   job that will be forgotten.
3. **Documentation hygiene.** Update the two stale doc sites listed in Context
   and note in `category-mgmt-spec.md` that membership lives in
   `kb.artifact_connections` (`category_name` edges), not
   `kb.category_instance`.

## Decision 3: Materialize the hierarchy as category→category edges with real rows

**Decision:** Promote `parent_categories` from write-only JSONB into a real,
queryable DAG:

- During Stage-B enrichment, resolve each `subcategory_of` key through the same
  placeholder-upsert flow, **within the same `category_type`** (a metric
  taxonomy and an entity taxonomy are different trees). This guarantees every
  parent exists as a category row.
- Store the link in a dedicated join table
  `kb.category_edges (child_id, parent_id)` with FKs to
  `kb.artifact_categories(category_id)`. A dedicated table is preferred over
  `kb.artifact_connections` because hierarchy edges are category-scoped, not
  document-scoped: `artifact_connections.input_record_id` is
  `NOT NULL REFERENCES kb.inputs`, which would force a fake record id onto
  edges that belong to no document.
- Keep the `parent_categories` JSONB column as raw LLM output / provenance.
- Query ancestors/descendants with a recursive CTE. Do not adopt `ltree` or
  materialized paths until profiling demands it.

**Guardrails (the hierarchy is LLM-authored):**

- Allow multiple parents — it is a DAG, not a tree.
- Check for cycles at insert time; LLMs will happily produce `A ⊂ B ⊂ A`
  across two documents. Reject (and log) the edge that would close a cycle.

**Interaction with Decision 1:** if a shared concept layer is ever added, the
question "does the hierarchy live on typed categories or on concepts?" reopens.
This is a further reason to sequence flat cross-type linking first,
hierarchy-within-type second, and a concept layer only if a real query demands
it.

**Note:** the semantic-projection category-path trees
(`category_tree_indexing.go`) remain a separate, per-document navigation
mechanism. Unifying them with the category DAG is out of scope for this ADR.

## Implementation Plan

Each step is small and independent; they should land as separate changes:

1. **Hygiene:** goose migration to drop `kb.category_instance`; update the two
   stale doc sites (+CAPSULE.md §7.4, category-mgmt-spec §3 counters note).
2. **Indexing/merge:** add `(target_type, target_id)` index on
   `kb.artifact_connections_category_name`; route category-group queries
   through a `canonical_of`-resolving join.
3. **Cross-type linking:** extend the Stage-B enricher to probe other
   `category_type`s via `match_keys` overlap and populate
   `related_categories`.
4. **Hierarchy:** create `kb.category_edges` (FKs, multi-parent, cycle check);
   extend the enricher to resolve `subcategory_of` parents via placeholder
   upsert and write edges; expose recursive-CTE helpers for
   ancestor/descendant queries.

## Consequences

**Positive:**

- Cross-type artifact correlation works without a namespace merge and without
  losing type-scoped resolution and enrichment quality.
- One membership mechanism; the schema stops advertising a dead table.
- The defining category query ("all members of X across documents") becomes
  index-backed.
- Hierarchy becomes queryable in SQL with referential integrity, multi-parent
  support, and cycle safety.

**Negative / accepted costs:**

- Query-time `canonical_of` resolution adds a join to category-group queries.
- Enricher cross-type probing adds work per newly created category (bounded by
  the existing worker pool).
- The category DAG is only as good as the LLM's `subcategory_of` output;
  quality curation (status/review workflow) remains future work.

**Explicitly deferred:**

- `kb.concepts` shared concept layer (build only when a concrete query needs
  it).
- Unifying semantic-projection category-path trees with the category DAG.
- `ltree` / materialized-path optimization.

## Affected Documents

- `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md` §7.4 —
  stale (`category_instance` reference); update in step 1.
- `KnowledgeStore/Capsules/coding-capsules/categories/category-mgmt-spec.md` —
  stale counters note; membership mechanism section to be added in step 1;
  enricher extensions (steps 3–4) must be reflected when implemented.
- ADR 2026070302 (create-artifact-categories) — unaffected; the non-LLM
  creation mode applies orthogonally. Note that in `not-use-llm` mode steps 3–4
  produce no cross-type links or parents (enrichment does not run).
