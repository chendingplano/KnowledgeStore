# ADR: Artifact Categories

**Date:** 2026-06-15 \
**Status:** Proposal \ 
**Component:** ChenWeb\
**Authors**: Chen Ding \
**Tags**: artifact categories \

## Change Logs
* 2026/06/15, ADR Created
* 2026/06/15, Problem 01 reframed as documentation of the current implementation;
  Problem 02 decided: entity names are not categories — use `kb.entities.categories`
  and `kb.relations.categories`. Implemented in entity-name indexing.

## Problems
### Problem 01: Multilingual Support (current implementation)

This section *documents* the multilingual category-resolution mechanism as it is
implemented today (it is not a proposal). The implementation landed via the
2026-06-07 "Category Resolution Redesign"
(`ChenWeb/docs/superpowers/plans/2026-06-07-category-resolution-redesign.md`).

**Problem it solves.** A category key may arrive in any language. A naïve exact
match against `kb.artifact_categories.category_key` (English) would miss every
non-English key and trigger a redundant LLM call on each occurrence — including
across concurrent pipelines.

**Mechanism.**
- A process-wide in-memory index (`categoryIndex`, a `sync.RWMutex`-guarded
  `map[categoryType]map[normalizedKey]int64`) is the primary resolution layer.
  It is loaded once per `category_type` from the DB and maps every `match_keys`
  entry — the canonical `category_key` **plus** all `display_names`, `aliases`,
  and `acronyms` — to a `category_id`.
  - Files: `categoryIndex` and `loadIntoIndex` in
    `ChenWeb/server/api/doc-processing/artifact_category_registry.go`;
    `categoryResolver` in
    `ChenWeb/server/api/doc-processing/artifact_category_resolver.go`.
- Resolution is two-tier and deterministic:
  1. **Index hit** → return the `category_id`. The raw (e.g., Chinese) key is
     absorbed into the category's `match_keys` (`absorbAlias`) so it hits tier 1
     next time.
  2. **Index miss** → one `CREATE_ARTIFACT_CATEGORY` LLM call mints the category.
     Concurrent creates of the same `(category_type, key)` are coalesced
     process-wide via `singleflight` (`categoryCreateGroup`), and the DB upsert
     (`ON CONFLICT`) is the cross-process safety net. After a create, both the
     canonical key and the **original raw key** are written to the index — the
     raw key acts as a *translation cache*, so the next occurrence of the
     non-English form is a direct tier-1 hit with no LLM call.
- **Alias conflicts** (one normalized key mapping to two or more `category_id`s)
  are resolved deterministically: the entry with the higher `seen_count` wins,
  and every conflict is recorded in `kb.category_alias_conflicts` for later human
  review. The resolution path does **not** call the LLM to disambiguate at lookup
  time, and the index intentionally holds a single winner per key (not an array).
- The redesign deliberately **removed** the embedding/cosine-similarity tier that
  earlier resolution used: "No embedding or cosine is used in the resolution path."

### Problem 02: Entity Categories

**Decision: entity *names* are no longer treated as categories.** Previously,
entity-name indexing fed each entity's name (`entity_en`/`entity`) into the
category resolver as a `category_type = "entity"` key. That conflated an entity's
*name* (its identity in the name dictionary) with its *class membership*, and it
produced sentence-like category keys such as:

```text
"opinions on steadily promoting the classification and treatment of rural domestic waste"
```

— which are document/policy titles, not categories. This name-as-category path is
removed.

**Decision: categories come from the explicit `categories` columns.** Both
entities and relations now carry an LLM-extracted `categories` array:
- `kb.entities.categories` (added 2026-06-13; populated from the
  `entity_categories` field of the extraction LLM)
- `kb.relations.categories` (added 2026-06-14; populated from
  `relation_categories`)

These arrays are the sole source of category keys. Each key is resolved through
the Problem 01 mechanism (`ResolveBatch` under `category_type = "entity"` for
entities, `"relation"` for relations), and membership is projected to
`kb.category_instance` plus a `belong-to-category` edge per resolved category.
The entity *name* continues to be catalogued in the `kb.entity_names` dictionary
(`has-instance` edge) — that is the legitimate "name" role, kept separate from
categories.

Because category keys are now author-controlled extraction outputs rather than
whole entity names, the long-key concern is addressed at the source (the LLM emits
concise category terms), so no length-threshold heuristic or BM25/similarity
fallback is introduced — consistent with Problem 01 having removed the
similarity tier from the resolution path.

## Context

## Decision

### Alternative Decisions

### Database Migrations

### Data Formats

### Environment Variables

## Implementation

### Code Changes

Problem 01 is already implemented (no code change). Problem 02 changes
`ChenWeb/server/api/doc-processing/entity_name_indexing.go`:

- Removed `resolveEntityNameCategories` / `entityNameCategoryRequests` — entity
  names are no longer sent to the category resolver.
- Added `resolveEntityCategoryIDs` (resolves `kb.entities.categories` via
  `ResolveBatch` under `category_type = "entity"`) and
  `upsertEntityCategoryInstances` (projects membership to `kb.category_instance`),
  mirroring the existing relation path in `relation_graph_indexing.go`.
- `loadEntityNameGraphRows` now also selects `kb.entities.categories`;
  `entityNameGraphRow` gains a `Categories []string` field (parsed via the shared
  `parseRelationCategories`).
- `buildEntityNameGraphConnections` now emits a `belong-to-category` edge
  (entity → category) per resolved category, alongside the existing `has-instance`
  name-dictionary edge. Relations already implemented this behavior; no change there.

## Operational Behaviors

The `kb.artifact_categories` rows of `category_type = "entity"` are now populated
from extracted category terms rather than entity names; pre-existing
name-derived "entity" categories from prior runs are stale and may be pruned.

## Consequences

- Category keys for entities are now concise, author-controlled terms, eliminating
  sentence-like category rows.
- Entity category membership is queryable the same way as relations
  (`kb.category_instance` + `belong-to-category` edges).
- Depends on the extraction LLM populating `entity_categories`; entities with an
  empty `categories` array contribute no category membership (their names are still
  catalogued).

## Tests

`ChenWeb/server/api/doc-processing/entity_name_indexing_test.go`:
- `TestBuildEntityNameGraphConnections` updated to the new signature; asserts both
  the `has-instance` name edge and the `belong-to-category` edge, and that an
  unresolved category key is skipped.
- Removed `TestEntityNameCategoryRequests` (the name-as-category helper is gone).

## Documentation Impact

- This ADR documents the Problem 01 mechanism (previously only in the 2026-06-07
  redesign plan).
- The 2026-06-07 redesign plan remains accurate for Problem 01.

## References

- `ChenWeb/docs/superpowers/plans/2026-06-07-category-resolution-redesign.md`
- `ChenWeb/project_migrations/20260613000001_add_categories_to_kb_entities.sql`
- `ChenWeb/project_migrations/20260614000001_amend_kb_relations_schema.sql`
