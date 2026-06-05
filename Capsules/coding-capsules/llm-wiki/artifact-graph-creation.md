# Artifact Graph Creation

How Deep Wiki turns documents and processor-generated artifacts into a connected
**artifact graph**: the connection catalog it must support, the storage model that holds
the edges, the edge-count discipline that keeps it from exploding, which doc processor
creates which connections, and how the graph is made searchable.

Consolidates [wiki-searchability-brainstorm-v1.md](wiki-searchability-brainstorm-v1.md)
(storage model) and [wiki-searchability-brainstorm-v2.md](wiki-searchability-brainstorm-v2.md)
(edge-count and searchability analysis), and implements the relation catalog in
[+deep-wiki-rqmt.md](+deep-wiki-rqmt.md).

## Scope

There are two connection families:

1. **LLM-extracted** semantic connections (entity relations, metric categorization).
2. **Calculated** connections between artifacts of the *same* document that share source
   lines (the `has-*` family).

A third, **structural**, family is needed for the summary hierarchy (see
[Edge-count discipline](#edge-count-discipline)).

The LLM relation store already exists as `kb.relations` /
[`kb.entities`](../../../../ChenWeb/project_migrations/20260527000010_create_kb_entities_relations_tables.sql).
This spec does **not** rebuild it; it adds the cross-artifact edge graph around it.

## Connection catalog (must support)

Every connection documented in [+deep-wiki-rqmt.md](+deep-wiki-rqmt.md), plus the owning
processor that creates it:

| `relation_name`      | source_type | target_type     | `relation_method` | Owning processor |
|----------------------|-------------|-----------------|-------------------|------------------|
| entity relations     | `entity`    | `entity`        | `llm`             | [`extract-entity-relation.go`](../../../../ChenWeb/server/api/doc-processing/extract-entity-relation.go) |
| belong-to-category   | `metric`    | `category`      | `llm`             | [`extract-metrics.go`](../../../../ChenWeb/server/api/doc-processing/extract-metrics.go) + [`category_tree_indexing.go`](../../../../ChenWeb/server/api/doc-processing/category_tree_indexing.go) |
| has-metrics          | `chunk`     | `metric`        | `line_overlap`    | [`extract-metrics.go`](../../../../ChenWeb/server/api/doc-processing/extract-metrics.go) |
| has-topic            | `chunk`     | `topic`         | `line_overlap`    | [`generate-topics-processor.go`](../../../../ChenWeb/server/api/doc-processing/generate-topics-processor.go) |
| has-provision        | `chunk`     | `provision`     | `line_overlap`    | [`extract-provisions.go`](../../../../ChenWeb/server/api/doc-processing/extract-provisions.go) |
| has-part-component   | `chunk`     | `part-component`| `line_overlap`    | [`extract-products.go`](../../../../ChenWeb/server/api/doc-processing/extract-products.go) |
| has-scene            | `chunk`     | `scene`         | `line_overlap`    | [`generate-scene-blocks-processor.go`](../../../../ChenWeb/server/api/doc-processing/generate-scene-blocks-processor.go) |

The `has-*` rows are all **chunk → artifact** and derived from shared source lines. New
artifact types follow the same pattern by adding a row, not a table (see
[Extensibility](#extensibility)).

## Storage model

### One canonical edge table, not many

Do **not** create a separate table per source type (`kb.topic_conns`, `kb.metric_conns`, …).
The table name would encode the source type, and as artifact types grow this forces new
tables, new query branches, unions across tables for cross-type traversal, and drift in
indexes/constraints/rebuild logic.

Use a single canonical edge table, **partitioned by `relation_method`**, so the three
families — which have very different volume and lifecycle (`line_overlap` is bulky and
disposable/recomputed; `llm` is smaller and provenance-rich; `structural` is tiny and
explicit) — live in isolated partitions while sharing one schema and one traversal surface.

```sql
CREATE TABLE kb.artifact_connections (
    id               BIGSERIAL,
    input_record_id  BIGINT NOT NULL REFERENCES kb.inputs(id) ON DELETE CASCADE,
    source_type      TEXT   NOT NULL,         -- 'entity','chunk','metric',...
    source_id        TEXT   NOT NULL,
    target_type      TEXT   NOT NULL,         -- 'entity','metric','topic','category',...
    target_id        TEXT   NOT NULL,
    relation_name    TEXT   NOT NULL,         -- 'has-metrics','has-topic','entity relations',...
    relation_method  TEXT   NOT NULL,         -- 'llm' | 'line_overlap' | 'structural' | 'manual'
    confidence       DOUBLE PRECISION,        -- llm only
    overlap          JSONB,                   -- line_overlap: { overlap_count, overlap_lines, source_spans, target_spans }
    provenance       JSONB,                   -- llm: { model_name, prompt_name }
    semantic_signature TEXT,                  -- optional descriptive passage (mainly llm edges)
    extra_info       JSONB,
    create_time      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (relation_method, id),
    UNIQUE (relation_method, source_type, source_id, target_type, target_id, relation_name)
) PARTITION BY LIST (relation_method);

CREATE TABLE kb.artifact_connections_llm         PARTITION OF kb.artifact_connections FOR VALUES IN ('llm');
CREATE TABLE kb.artifact_connections_line_overlap PARTITION OF kb.artifact_connections FOR VALUES IN ('line_overlap');
CREATE TABLE kb.artifact_connections_structural  PARTITION OF kb.artifact_connections FOR VALUES IN ('structural');
CREATE TABLE kb.artifact_connections_manual      PARTITION OF kb.artifact_connections FOR VALUES IN ('manual');
```

Per-partition indexes for traversal and document-scoped rebuilds:

```sql
(input_record_id)                              -- delete/rebuild a document's edges
(input_record_id, source_type, source_id)      -- expand from a source artifact
(input_record_id, target_type, target_id)      -- expand into a target artifact
(input_record_id, relation_name)               -- filter by relation family
```

**Schema notes (these were defects in the original `derive-connections.md` draft):**

- `target_type` is **required** — `target_id` alone is unresolvable (`123` could be a chunk,
  a metric, or a category). Keep `source_type`/`source_id`/`target_type`/`target_id`/
  `relation_name`/`relation_method` as first-class columns, never hidden in JSON.
- A **uniqueness key** makes writes idempotent across reprocessing (`ON CONFLICT`).
- `input_record_id` (not `record_id`) matches the schema-wide name and FKs to
  `kb.inputs(id) ON DELETE CASCADE`, so deleting a document cleans up its edges for free.
- For `line_overlap` edges, store the **evidence** (overlapping line range + count) so edges
  are auditable and rankable ("share 1 line" vs "share 40").
- Surrogate `BIGINT id`s are fine and fast for a derived table recomputed on reprocess; the
  stable join keys are the typed artifact ids (`entity_id`, `metric_id`, …) in
  `source_id`/`target_id`.

### Line provenance for overlap derivation

`line_overlap` edges are a function of the source line spans every artifact already carries
(`line_spans` / `source_line_spans`). Two ways to derive them; pick per measured need:

- **Materialize directly** (recommended default here). Because chunks are small and almost
  every artifact is chunk-scoped, the overlap is a cheap per-document lookup at the moment a
  processor writes its artifact (it knows the artifact's spans → finds the containing
  chunk). Write the `has-*` edge then and there. No standing join needed.
- **Normalize a line-ref helper** if ad-hoc overlap queries are needed outside processors:

  ```text
  kb.artifact_line_refs ( input_record_id, artifact_type, artifact_id, line_no )
  index: (input_record_id, line_no)
  ```

  Large but narrow and mechanical; rebuilt from spans on reprocess; lets the system derive
  overlaps with a self-join on `(input_record_id, line_no)`. (An `int4range` column with a
  GiST index and the `&&` operator is an equivalent alternative.)

## Edge-count discipline

The edge count of a rule is `Σ over sources of (targets whose lines it overlaps)`.

- **Narrow → wide is linear.** Anchoring a point-like artifact (metric, etc.) into a small
  container (chunk) yields ≈ one edge per artifact — effectively one-to-one. Every `has-*`
  rule is chunk-anchored and chunks are small, so the whole `line_overlap` partition is
  **linear in the number of artifacts**.
- **Wide × wide × dense is the only superlinear case** — two many-instance, multi-line types
  densely co-occupying the same lines. Guard a rule only when *both* endpoints span many
  lines.

### The summary hierarchy — the one wide-span exception

Of all artifact types (summaries, topics, semantic projections, metrics, inventory items,
scene blocks, entities/relations), **only higher-level summaries are wide-span**:

- **Level 0 summaries are chunk-based** → narrow. They participate in `line_overlap`
  connections like any other artifact.
- **Level ≥ 1 summaries cover multiple chunks** → wide. **Exclude them from `line_overlap`
  derivation.** A document-spanning summary trivially shares lines with everything beneath
  it, so the "shared line ⇒ related" heuristic collapses and you manufacture trivial,
  high-degree hub edges. That relationship already exists, better-structured, in the summary
  rollup tree.

Represent higher-level-summary relationships with `relation_method = 'structural'` drawn
from the summary tree's parent/child pointers — one edge per link, explicit and level-aware.
Excluding the only wide type removes the entire wide×wide risk surface in one rule.

## Connection creation — each processor owns its edges

**Rule: the processor that produces an artifact creates the connections into it**, at the
moment it writes the artifact, because that is when it holds the source line spans (for
`line_overlap`) or the model output (for `llm`). No separate batch graph-builder pass.

| Processor | Connections it creates |
|-----------|------------------------|
| [`extract-entity-relation.go`](../../../../ChenWeb/server/api/doc-processing/extract-entity-relation.go) | `entity → entity` (`llm`) — already its job via `kb.relations`; also writes the mirror edges into `kb.artifact_connections` |
| [`extract-metrics.go`](../../../../ChenWeb/server/api/doc-processing/extract-metrics.go) | `chunk → metric` (`line_overlap`); `metric → category` (`llm`, with [`category_tree_indexing.go`](../../../../ChenWeb/server/api/doc-processing/category_tree_indexing.go)) |
| [`generate-topics-processor.go`](../../../../ChenWeb/server/api/doc-processing/generate-topics-processor.go) | `chunk → topic` (`line_overlap`) |
| [`extract-provisions.go`](../../../../ChenWeb/server/api/doc-processing/extract-provisions.go) | `chunk → provision` (`line_overlap`) |
| [`extract-products.go`](../../../../ChenWeb/server/api/doc-processing/extract-products.go) | `chunk → part-component` (`line_overlap`) |
| [`generate-scene-blocks-processor.go`](../../../../ChenWeb/server/api/doc-processing/generate-scene-blocks-processor.go) | `chunk → scene` (`line_overlap`) |
| [`generate-summaries-processor.go`](../../../../ChenWeb/server/api/doc-processing/generate-summaries-processor.go) | Level 0: `chunk → summary` (`line_overlap`). Level ≥ 1: `summary → child` (`structural`) from the rollup tree — **never** `line_overlap` |

### Idempotent writes / reprocessing

A document may be reprocessed at any time. Each processor must make edge creation repeatable:

1. **Scope-delete then insert**: `DELETE FROM kb.artifact_connections WHERE input_record_id = $1
   AND relation_name = $2` before re-inserting that document's edges for that relation, **or**
2. **Upsert** on the uniqueness key with `ON CONFLICT ... DO UPDATE`.

Because `input_record_id` FKs `ON DELETE CASCADE`, deleting/replacing a document drops its
edges automatically. Run edge creation in the same transaction/phase that writes the
artifact, so the artifact and its connections never drift. Schema changes go through goose
(the `db-migration` skill).

## Searchability

**Search the nodes, traverse the edges.** Full-text search runs against the artifacts in the
partitioned [`kb.search_artifacts`](../../../../ChenWeb/project_migrations/20260522000002_add_hybrid_kb_search_registry.sql)
registry; the edge table is for graph expansion *after* a result is selected. Do not put a
`tsvector` on the bulky, mechanical `line_overlap` partition by default — it is high cost for
a query no one runs.

When connection rows themselves should be searchable (mainly the semantically rich `llm`
edges), reuse the existing registry pattern rather than inventing one — add a
`kb.search_artifacts_connection` partition (`artifact_type = 'connection'`) whose
`search_document` combines: source label, target label, `relation_name`, `semantic_signature`,
and relevant keywords/category paths from both endpoints; then `search_vector TSVECTOR`, the
`BEFORE INSERT OR UPDATE` refresh trigger, and a GIN index — exactly like
`kb.refresh_relation_search_columns`. Populate it primarily for `llm` edges; leave
`line_overlap` hub edges out unless a concrete "search the relationship" need appears.

Resulting flow: keyword search hits `kb.search_artifacts*` → select a node → expand via
`kb.artifact_connections` indexes (filter by `input_record_id`, `relation_name`, or
`relation_method`).

## Extensibility

New artifact types (semantic projections, inventory items, …) join the graph by **adding a
catalog row**, not a table:

- chunk-scoped artifact → a `chunk → <type>` `line_overlap` rule, created by its producing
  processor ([`extract-semantic-projections.go`](../../../../ChenWeb/server/api/doc-processing/extract-semantic-projections.go),
  [`extract-inventory-items.go`](../../../../ChenWeb/server/api/doc-processing/extract-inventory-items.go), …);
- any wide-span artifact → a `structural` rule, never `line_overlap`.

## Defaults summary

```text
canonical edge table : kb.artifact_connections   (PARTITION BY LIST relation_method)
partitions           : llm | line_overlap | structural | manual
overlap derivation   : materialize at write time (chunks are small); kb.artifact_line_refs only if needed
edge ownership       : producing processor writes its connections, idempotently, in-phase
wide-span rule       : higher-level summaries → structural, excluded from line_overlap
search               : nodes via kb.search_artifacts*; optional kb.search_artifacts_connection for llm edges
```

## References

- [+deep-wiki-rqmt.md](+deep-wiki-rqmt.md) — relation-type catalog and page requirements.
- [wiki-searchability-brainstorm-v1.md](wiki-searchability-brainstorm-v1.md) — canonical-table / line-ref / search-partition storage model.
- [wiki-searchability-brainstorm-v2.md](wiki-searchability-brainstorm-v2.md) — edge-count analysis and the summary wide-span exception.
- [deep-wiki-impl.md](deep-wiki-impl.md) — the Deep Wiki entrance page these counts and links feed.
