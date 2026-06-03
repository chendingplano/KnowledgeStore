# Connections Design Review — Searchability & Table Layout (v2)

Review of [derive-connections.md](derive-connections.md) (the proposed `kb.topic_conns` /
`kb.metric_conns` tables) against the existing SemOS schema. Focus: the two stated
concerns — (1) avoid a gigantic table that slows queries, (2) improve searchability.

## Context grounding

The relevant existing pieces this design must fit into:

- **LLM entities/relations already exist** —
  [`20260527000010_create_kb_entities_relations_tables.sql`](../../../../ChenWeb/project_migrations/20260527000010_create_kb_entities_relations_tables.sql)
  defines `kb.entities` and `kb.relations`, each with `search_document` + `search_vector TSVECTOR`,
  a `BEFORE INSERT OR UPDATE` refresh trigger, and a GIN index.
- **A partitioned search surface already exists** —
  [`20260522000002_add_hybrid_kb_search_registry.sql`](../../../../ChenWeb/project_migrations/20260522000002_add_hybrid_kb_search_registry.sql)
  defines `kb.search_artifacts` as `PARTITION BY LIST (artifact_type)` with per-type
  partitions and per-partition GIN indexes.
- **Every artifact already carries line spans** — `line_spans` on entities/relations,
  `source_line_spans` on `kb.search_artifacts`, plus `input_record_id` for doc scope.

## The big-picture reframe

Two facts change the calculus before we touch table layout:

1. **Connection type 1 (LLM entities/relations) already exists** — it's `kb.relations`.
   Don't rebuild it. The genuinely *new* work is connection type 2: the
   "has-metrics / has-topic / has-provision…" edges that are "determined by sharing the
   same source lines." Scope `topic_conns`/`metric_conns` to type 2 and avoid duplicating
   the LLM relation store.

2. **Type-2 connections are a pure function of data already stored.** Every artifact has
   `line_spans`/`source_line_spans` and `input_record_id`. A "they share a line" edge is
   just a line-range overlap between two artifacts of the same document. That is
   denormalization, which reframes the whole "gigantic table" question (below).

## Issue 1 — "don't make a gigantic table"

**Separate hand-written tables are the wrong tool, and the right one already exists.**
`kb.search_artifacts` is `PARTITION BY LIST (artifact_type)` with per-partition GIN
indexes. That pattern gives the table-isolation you want (smaller per-partition indexes,
drop/reattach a partition, no cross-type lock contention) *without* N hand-maintained
tables, N triggers, N sets of DDL drift. If you want sharding, use **one declaratively
partitioned `kb.connections`**, not sibling tables.

**But partitioning won't speed up the actual queries — indexes will.** Partition pruning
only helps when the query filters on the partition key. The dominant access pattern for an
edge table is traversal: "all connections from this artifact" (`WHERE source_id = …`) and
"all connections in this doc" (`WHERE input_record_id = …`). Those are B-tree point
lookups; Postgres serves them fine at hundreds of millions of rows. So:

- Partition for **operational** wins (per-document reprocessing, retention, separating the
  two pipelines), not for read latency.
- The single highest-value index is on `input_record_id`, because reprocessing a doc means
  *delete all its edges and recompute* — that must be cheap, and the schema needs it anyway.

**Edge count — and when it is, and isn't, a concern.** The number of edges produced by a
rule is:

```
edges = Σ over source artifacts of (number of targets whose lines it overlaps)
```

For the rules in this taxonomy, this is **linear, not combinatorial**. A connection
anchors a *narrow* artifact (a metric, or another point-like extraction occupying a few
lines) into a *wide* container (a topic or chunk spanning many lines). Each metric sits
inside ~1 topic, so the topic↔metric rule produces roughly one edge per metric — an
effectively **one-to-one** relation, exactly as expected. The same holds for metric→chunk,
provision→chunk, etc. Summed over all such rules, the entire calculated table is roughly
**linear in the number of artifacts**, which is manageable.

There is exactly one configuration that goes superlinear, and it is worth guarding against
deliberately: a rule connecting **two wide-span types that densely co-occupy the same
lines**. If a 100-line region is covered by 20 chunks *and* 20 provisions that all mutually
overlap, that region alone yields ~400 edges. Narrow→wide anchoring (the pattern used here)
never hits this; wide×wide×many does. So:

1. **Keep edges anchored narrow→wide.** As long as one endpoint is a point-like artifact,
   edge count stays linear. Only audit a rule if *both* endpoints span many lines and many
   instances tile the same region.
2. **Consider not materializing type-2 edges at all.** Store line spans as `int4range[]` (or
   a child line-span table) with a **GiST index**, and derive overlaps at query time with
   the `&&` operator scoped to one `input_record_id`. This skips an entire write/sync
   pipeline and can never go stale after reprocessing. Materialize only if measured query
   latency demands it, or if individual edges need to be curated/annotated.
3. If a rule does risk the wide×wide case, **threshold** (overlap ≥ k lines) and store the
   overlap size so edges are rankable.

## The summary hierarchy — the one wide-span exception

Mapping the abstract guardrail onto the real corpus makes it concrete. The artifact types
are: summaries, topics, semantic projections, metrics, inventory items, scene blocks, and
entities/relations. **All except summaries are chunk-based**, and chunks are guaranteed
small. An artifact occasionally spans two chunks, but that is rare. So every non-summary
artifact is effectively **chunk-scoped (narrow)**, and the line-overlap graph among them is
all narrow×narrow — linear and well-behaved.

Summaries are the exception, and only partly:

- **Level 0 summaries are chunk-based** → narrow. They behave like every other artifact and
  can participate in `calculated` line-overlap connections normally.
- **Higher-level summaries (Level ≥ 1) cover multiple chunks** → wide. These are the only
  wide-span artifacts in the system.

**Recommendation: exclude higher-level summaries from line-overlap (`calculated`)
connection derivation.** Three reasons, in order of importance:

1. **"Shares a line" only implies relatedness when at least one side is narrow.** For
   chunk-scoped artifacts, co-location means "about the same specific content." A
   document-spanning summary trivially shares lines with *every* artifact beneath it, so the
   heuristic that justifies calculated connections collapses — the shared line no longer
   signals a meaningful relationship.
2. **It manufactures trivial hubs.** Summary×narrow-artifact is technically linear
   (≈ artifacts × summary-tree depth), not quadratic — but it produces high-degree,
   low-information edges (one summary connected to everything under it) that pollute
   traversal and ranking far out of proportion to their value.
3. **The information already exists, better-structured, in the summary hierarchy.** "This
   metric falls under this Level-2 summary" is recoverable by walking the rollup tree
   (metric → chunk → Level 0 summary → parent → …). That is an explicit, level-aware,
   cheap **structural** relation — one edge per parent/child link — whereas flattening it
   into line-overlap edges duplicates it lossily (the level structure is lost).

So split the two mechanisms by `relation_method`:

- `calculated` (line overlap) — only among **chunk-scoped** artifacts, including Level 0
  summaries. Stays narrow×narrow and linear.
- `structural` (hierarchy rollup) — for higher-level summaries, drawn from the summary
  tree's parent/child pointers, not from line overlap. Small, explicit, and level-aware.

This also confirms the earlier guardrail empirically: because higher-level summaries are the
*only* wide-span type, excluding them removes the entire wide×(many-narrow) and wide×wide
risk surface in one rule.

## Issue 2 — searchability

**Decide whether edges are search targets or traversal structures.** In almost every KB you
full-text *search the nodes* (`kb.search_artifacts`) and then *traverse the edges*.
Materializing a `semantic_signature` + `search_vector` + GIN on a combinatorial edge table
is a large storage/write cost for a query you may never run ("find a connection about X" is
unusual; "find artifacts about X, then show their connections" is the norm).

- **Default: no tsvector on the calculated-edge table.** Spend the searchability budget on
  the artifacts, where the trigger pattern already exists.
- **If you do want searchable edges** (mostly meaningful for LLM relations, where the edge
  carries semantics like a predicate + description), reuse the proven mechanism verbatim: a
  generated `search_document` + `search_vector TSVECTOR`, a `BEFORE INSERT OR UPDATE`
  trigger, and a GIN index — exactly like `kb.refresh_relation_search_columns`. Don't invent
  a new approach for `semantic_signature`.

## Concrete schema problems in the current draft

- **Missing `target_type`.** Targets "can be docs and artifacts," but `target_id` alone is
  unresolvable — id `123` could be a chunk, topic, or doc. Add `target_type` (and arguably
  `source_type` if tables are ever merged). Without it you can't join to the right table.
- **No uniqueness / idempotency key.** Reprocessing must not duplicate edges. Add
  `UNIQUE (source_type, source_id, target_type, target_id, relation_name)` and write with
  `ON CONFLICT`, or adopt delete-by-`input_record_id`-then-insert. Decide and document which.
- **`record_id` naming collides** with the schema-wide `input_record_id`. Use
  `input_record_id` for consistency and so it can FK to `kb.inputs(id) ON DELETE CASCADE`
  (how `search_artifacts` already gets free cleanup on doc deletion).
- **Stable id choice.** `BIGSERIAL` ids change on reprocessing; typed string ids
  (`topic_id`, `metric_id`, `relation_id`) are stable. For a derived edge table recomputed
  every reprocess, surrogate `BIGINT`s are fine and faster to join — but if anything
  *external* references an edge, key on the stable typed ids. Pick deliberately.
- **For calculated edges, store the evidence:** the overlapping line range and the overlap
  count. That is what makes an edge rankable and auditable ("share 1 line" vs "share 40").

## What I'd build

One partitioned table instead of `topic_conns` + `metric_conns` + …:

```sql
CREATE TABLE kb.connections (
    id               BIGSERIAL,
    input_record_id  BIGINT NOT NULL REFERENCES kb.inputs(id) ON DELETE CASCADE,
    source_type      TEXT   NOT NULL,         -- 'chunk','topic','metric',...
    source_id        TEXT   NOT NULL,
    target_type      TEXT   NOT NULL,         -- 'doc','metric','topic',...
    target_id        TEXT   NOT NULL,
    relation_name    TEXT   NOT NULL,         -- 'has-metrics','has-topic',...
    relation_method  TEXT   NOT NULL,         -- 'calculated' | 'llm' | 'structural'
    overlap          JSONB,                   -- shared line ranges + count (calculated)
    confidence       DOUBLE PRECISION,        -- llm only
    provenance       JSONB,                   -- model/prompt for llm
    semantic_signature TEXT,                  -- optional; tsvector only if you truly search edges
    create_time      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (relation_method, id)
) PARTITION BY LIST (relation_method);
-- partitions: 'calculated' (big, disposable, recomputed) vs 'llm' (smaller, provenance-rich)
-- indexes per partition: (source_type, source_id), (target_type, target_id), (input_record_id)
-- UNIQUE (source_type, source_id, target_type, target_id, relation_name)
```

Partitioning by `relation_method` separates the two pipelines cleanly — different write
rates, lifecycles (calculated = disposable/recomputed; llm = expensive/curated), and column
usage — while keeping a single traversal surface and one set of DDL.

## Ranked recommendations

1. Scope this to type-2 only; reuse `kb.relations` for type-1.
2. Seriously evaluate **deriving** type-2 overlaps from line spans via a GiST range index
   before committing to materialization — it removes a whole class of staleness bugs.
3. If you materialize, use **one partitioned `kb.connections`**, not per-source-type tables;
   keep edges anchored narrow→wide (which keeps edge count linear); index `input_record_id`.
4. **Exclude higher-level summaries from `calculated` derivation** — they are the only
   wide-span artifact; relate them via a `structural` rollup from the summary hierarchy
   instead of line overlap.
5. Add `target_type` + a uniqueness key now.
6. Keep full-text search on the **artifacts**, not the edges — add an edge tsvector only for
   LLM relations if a real "search the relationship" use case appears.
