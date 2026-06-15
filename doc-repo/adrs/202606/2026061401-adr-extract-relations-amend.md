# ADR 2026061401 — Canonical Relation Store, Projections, and Entity-is-Artifact

**Date:** 2026-06-14 \
**Status:** Proposal \ 
**Component:** ChenWeb, Doc Processor => extract-entity-relation doc processor \
**Authors**: Chen Ding \
**Tags**: doc processor, extract relations \

---

## Change Logs
* 2026/06/14, ADR Created
* 2026/06/14, Amended: canonical relation store + projections + entity-is-artifact decision drafted (D1–D7); fixed stale title.

## Context
`extract-entity-relation` is a doc processor (refer to [1] and [2]).

New changes:
* For each newly extracted relation: for each category in `kb.relations.categories`, use it (translate it if it is not in English) to compose the key ('category_type' = 'relation' and 'category_key' = `kb.relations.predicate_en` to check `kb.artifact_categories`. If the entry does not exist, use LLM to normalize it the same way as [3] does and add it to `kb.artifact_categories`. Also, make sure `kb.relations.categories` is in English.
* Create a new table `kb.relation_predicates` as a dictionary to store relation predicates
* For each newly extracted relation, use `kb.relations.predicate_en` (translate `kb.relations.predicate` if `kb.relations.predicate_en` is null/empty) as the key to look up the dictionary. If not exist, do the same thing as the categories.
* For each newly relation in `kb.relations`, add a record to `kb.artifact_connections`
* for each `kb.relations.categories`, add a record to `kb.artifact_connections` that connects the category and the relation
* for each `kb.relations`, add a record to `kb.artifact_connections` that connects the relation predicate and the relation
---

## Decision

We adopt a **single canonical relation store with derived projections**, and we promote every
node-like dictionary entry to a first-class **artifact**. This removes the ambiguity of "which
table owns this fact" while preserving the performance characteristics that motivated the
separate tables in the first place.

### D1. `kb.artifact_connections` is the single source of truth

Every relation in the knowledge base — regardless of its semantic kind (peer connection,
category membership, predicate typing, entity relation) — is stored as **one triple**:

```
(source_type, source_id)  --[ relation_name ]-->  (target_type, target_id)
```

There is exactly **one logical relation model** and **one write path**. No other table is an
independent author of relation facts.

### D2. Everything is an artifact

An "artifact" is anything that can be the `source` or `target` of a connection. The following
are hereby declared artifact types (each carries a stable `(artifact_type, artifact_id)`
identity and may appear on either side of a triple):

| `artifact_type`      | Backing table              | Notes                                              |
|----------------------|----------------------------|----------------------------------------------------|
| `entity`             | `kb.entities`              | **Entity is an artifact** (was a separate graph).  |
| `category`           | `kb.artifact_categories`   | Categories are artifacts (dictionary + node).      |
| `relation_predicate` | `kb.relation_predicates`   | Predicates are artifacts (dictionary + node).      |
| `relation`           | `kb.relations`             | **Reified** — each relation is itself an artifact. |
| `metric`, `inventory_item`, … | (existing)        | Unchanged; already artifacts.                      |

Consequence: there is no longer an "entities-only" relation graph separate from the
artifact graph. `kb.relations` rows participate in the same canonical store as everything else.

### D3. Relations are reified

Each `kb.relations` row is both **an edge and a node**:

* As an **edge**, it produces the primary triple `(subject_entity) --[predicate_en]--> (object_entity)`
  in `kb.artifact_connections` (Context bullet, line 21).
* As a **node** (artifact_type = `relation`), it can itself be the target of connections, so we
  can attach metadata to the statement:
  * `(category) --[instance_of]--> (relation)` for each `kb.relations.categories` (line 22).
  * `(relation_predicate) --[predicate_of]--> (relation)` for each relation (line 23).

This is standard relation reification: it lets a statement be categorized and typed without
inventing per-kind relation tables.

### D4. The other relation tables are projections, not sources of truth

| Table / view          | Role after this ADR                                                        |
|-----------------------|---------------------------------------------------------------------------|
| `kb.category_instance`| **Derived projection** of `artifact_connections` where `relation_name = 'instance_of'`. Read-optimized for membership lookup. Never written directly. |
| `kb.relations`        | Remains the **authoring/search surface** for entity statements (serves the "search relations like `X reference Y`" access pattern), but each row is **mirrored into** `artifact_connections` on write. It is a projection w.r.t. graph traversal. |

Projections are maintained by the write path (or as materialized views / partitions — see
Migrations). Readers doing **graph traversal** always go through `artifact_connections`;
readers doing **relation text search** use `kb.relations`.

### D5. Dictionaries stay dictionaries

`kb.artifact_categories` and `kb.relation_predicates` are **catalog/dimension** tables that
define artifacts; they are not relation tables. Membership/typing *edges* live in
`artifact_connections` (D3), not in the dictionaries.

### D6. Write path (extract-entity-relation processor)

For each newly extracted relation, the processor MUST, in order:

1. Normalize `predicate_en` (translate `predicate` if empty); ensure `kb.relations.categories`
   are English.
2. Upsert each category into `kb.artifact_categories` (`category_type='relation'`,
   `category_key=predicate_en`), LLM-normalizing per [3] when missing.
3. Upsert the predicate into `kb.relation_predicates` keyed by `predicate_en`, LLM-normalizing
   when missing.
4. Write the reified relation node + the three connection triples of D2/D3 into
   `kb.artifact_connections` (primary edge, category→relation, predicate→relation).

### D7. Read path / access layer

Callers MUST NOT pick a table by hand. Provide one repository interface:

* `relations.neighbors(ref, direction?, filter?)` → fans out over `artifact_connections`.
* `relations.search(pattern)` → serves `X <predicate> Y` lookups via `kb.relations`.

This is what removes the day-to-day complexity tax: the physical split survives for
performance, but no query author has to know it exists.

### Alternative Decisions

* **A1 — Keep independent tables, no canonical store.** Rejected: this is the status quo that
  produced overlapping responsibilities and the "which table do I query?" tax.
* **A2 — Single table only, drop `category_instance` and `kb.relations`.** Rejected: loses the
  read-optimized access paths (fast membership lookup; relation text search). We keep them as
  *projections* instead of deleting them.
* **A3 — Solve performance purely with partitioning/indexing on one table.** Viable for graph
  traversal, but does not serve the relation-**search** access pattern well; hence projections
  are retained (D4).

### Database Migrations

> Handled via `goose` (see `shared/go/api/goose/goose.md`). Draft — confirm column names against
> live schema before generating.

1. **New dictionary** `kb.relation_predicates(predicate_en PK/uk, predicate_raw, lang, normalized_by, created_at, …)`.
2. **Artifact identity** — ensure `kb.entities`, `kb.artifact_categories`, `kb.relation_predicates`,
   `kb.relations` each expose a resolvable `(artifact_type, artifact_id)`; add `artifact_type`
   discriminator columns/constants where missing.
3. **`kb.artifact_connections`** — confirm composite indexes on `(source_type, source_id)`,
   `(target_type, target_id)`, and `(relation_name)`; consider partitioning by `relation_name`
   or `source_type` to address the original "big table is slow" concern.
4. **`kb.category_instance`** — convert to a (materialized) view / partition over
   `artifact_connections WHERE relation_name='instance_of'`, OR keep the table but make the
   write path the only writer. Decide and record here.

### Data Formats

Canonical triple (logical):

```json
{
  "source": { "type": "entity",            "id": "ent_123" },
  "relation_name": "references",
  "target": { "type": "entity",            "id": "ent_456" },
  "via_relation_id": "rel_789"            // reified relation node, when applicable
}
```

Reification edges for one extracted relation `rel_789`:

```
(entity:subject)            --references-->   (entity:object)
(category:cat_taxonomy)     --instance_of-->  (relation:rel_789)
(relation_predicate:pred_x) --predicate_of--> (relation:rel_789)
```

### Environment Variables

None introduced by this ADR.

---

## Implementation

### Code Changes

Implemented in `ChenWeb` (`server/api/doc-processing`), wired into the entity-relation
processor's post-process step.

* **Migration** `project_migrations/20260614000002_create_kb_relation_predicates.sql` —
  creates the `kb.relation_predicates` dictionary (D2), keyed by `predicate_key`
  (normalized English predicate), with `seen_count` observability.
* **`connections.go`** — added `RelationMethodEntityRelation` (single method tagging all
  three relation-graph edge kinds), `RelationHasPredicate`, and the artifact-type
  discriminators `artifactTypeCategory` / `artifactTypeRelationPredicate`.
* **`connections_store.go`** — added `ReplaceRecordConnectionsByMethod`: an idempotent,
  method-scoped replace (delete all `source_record_id = target_record_id = recordID`
  rows for the method, then insert). Needed because the subject→object edge name is the
  open-ended predicate and cannot be enumerated for the existing relation_name-scoped
  delete.
* **`relation_graph_indexing.go`** (new) — `IndexRelationGraphForRecord` loads
  `kb.relations`, resolves relation categories (`category_type='relation'`) in one batch,
  writes `kb.category_instance` rows (membership projection, D4), catalogues predicates in
  `kb.relation_predicates`, and materializes the three canonical triples via the pure,
  unit-tested `buildRelationGraphConnections`.
* **`artifact_postprocess_indexing.go`** — calls `IndexRelationGraphForRecord` right after
  `IndexRelationsForRecord`, so reprocessing a record idempotently rebuilds its edges.

**Deviations from the draft, recorded:**

1. **Predicate cataloguing is a deterministic upsert, not an LLM normalization.** D6 said
   "LLM-normalizing per [3]." Predicates are already normalized to snake_case English at
   extraction time (`normalizePredicate`, `predicate_en`), so the dictionary upsert is
   deterministic. Async LLM enrichment of predicates (aliases/description) can be added
   later, mirroring the category Stage B; left undocumented as a deferred optimization.
2. **`belong-to-category` edge direction** is `(relation) -> (category)`, reusing the
   existing catalog constant `RelationBelongToCategory`, rather than D3's illustrative
   `(category) --instance_of--> (relation)`. The edge_kind and category_instance
   projection carry the same membership fact; direction follows the established convention.
3. **category_instance is still written directly for relations**, matching metrics/
   inventory. Fully inverting category_instance into a pure projection of
   `artifact_connections` across all families is out of scope for this ADR (relations only).

---

## Operational Behaviors 

---

## Consequences

**Positive**
* One logical relation model; one write path; one traversal store. The "which table owns this
  fact?" ambiguity is eliminated.
* Entity, category, and predicate graphs unify — entity relations are no longer a walled-off
  subsystem.
* Performance levers (partitioning, composite indexes) apply to one canonical table.
* Read-optimized access patterns (membership lookup, relation search) survive as projections.

**Negative / costs**
* Write amplification: each extracted relation now writes a reified node + ≥3 connection rows.
* Projection consistency must be maintained (materialized-view refresh or write-path mirroring).
* Backfill required to bring existing `kb.relations` / `category_instance` data into
  `artifact_connections`.

**Risks**
* If the access layer (D7) is not enforced, query authors may bypass it and reintroduce the
  table-choice tax.
* Reification adds a level of indirection; relation-search queries must be benchmarked.

---

## Tests

* Write path: one extracted relation produces exactly the primary edge + category→relation +
  predicate→relation triples; dictionaries upserted idempotently.
* Idempotency: re-running the processor on the same relation creates no duplicates.
* Projection parity: `kb.category_instance` matches `artifact_connections WHERE relation_name='instance_of'`.
* Access layer: `relations.neighbors()` and `relations.search()` return equivalent results to
  direct (legacy) queries during migration.

---

## Documentation Impact

* **Update** `extract-entity-relation-spec.md` [2] — new write-path steps (D6) and the
  `kb.relation_predicates` dictionary.
* **Update** `category-mgmt-spec.md` [3] — categories are artifacts; membership edges live in
  `artifact_connections`, not in the dictionary.
* **New/Update** schema doc for `kb.artifact_connections` describing the canonical triple model,
  artifact-type registry (D2), and the projection rules (D4).
* **Stale** — any doc that describes `kb.relations` as the entities-only relation store, or
  `category_instance` as an independently authored table, is now stale and must be revised.
* **Intentionally undocumented** — exact partitioning strategy and projection-refresh mechanism
  are deferred to the Migrations decision once live schema is confirmed.

---

## References
[1] KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md

[2] KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-entity-relation-spec.md

[3] KnowledgeStore/Capsules/coding-capsules/categories/category-mgmt-spec.md