# Wiki Searchability Brainstorm v1

## Context

Deep Wiki needs connections among documents and processor-generated artifacts.
There are two important connection families:

1. LLM-extracted connections, such as entities and semantic relations.
2. Calculated connections between artifacts from the same document that share
   source lines.

The initial idea in `derive-connections.md` is to create multiple connection
tables, such as `kb.topic_conns` and `kb.metric_conns`. The main concerns are:

- avoiding one gigantic table that slows traversal and search;
- making connection rows themselves searchable;
- keeping the design extensible as more artifact types are added.

## Main Recommendation

Use one logical connection model, but partition it physically.

Instead of creating a separate table for each source artifact type, create a
canonical edge table such as `kb.artifact_connections` and partition it by a
high-value discriminator such as `source_type` or `relation_method`.

This keeps the application model simple while still allowing PostgreSQL to prune
partitions for common queries.

Conceptual shape:

```text
kb.artifact_connections

id
input_record_id
source_type
source_id
target_type
target_id
relation_name
relation_method
confidence
evidence_line_spans
semantic_signature
extra_info
create_time
```

Recommended `relation_method` values:

```text
llm
line_overlap
calculated
manual
```

Examples:

```text
LLM extracted relation:
source_type = entity
target_type = entity
relation_method = llm

Shared-line relation:
source_type = chunk
target_type = metric
relation_method = line_overlap
extra_info = { overlap_lines, overlap_count, source_spans, target_spans }
```

## Proposed Tables

### `kb.artifact_connections`

This should be the canonical graph edge table. It stores the durable connection
between any two typed artifacts.

It should be optimized for graph traversal, filtering, and rebuilds by document.
Useful indexes:

```sql
(input_record_id, source_type, source_id)
(input_record_id, target_type, target_id)
(input_record_id, relation_name)
(input_record_id, relation_method)
```

If most queries start from a source artifact, partition by `source_type`. If the
system expects very different lifecycle and volume patterns between LLM-derived
and calculated edges, partition by `relation_method`.

### `kb.artifact_line_refs`

For shared-line derivation, do not rely only on JSON line spans at query time.
Normalize artifact-to-line provenance into a narrow helper table:

```text
kb.artifact_line_refs

input_record_id
artifact_type
artifact_id
line_no
```

This table may be large, but it is mechanical, narrow, and indexable. It lets
the system derive line-overlap connections with joins on:

```text
(input_record_id, line_no)
```

The table can be rebuilt from artifact source spans when a document is
reprocessed.

### `kb.search_artifacts_connection`

Connection rows should be searchable through the existing partitioned
`kb.search_artifacts` registry pattern used by other artifact types.

Add a partition such as:

```text
kb.search_artifacts_connection
artifact_type = connection
```

The search document for a connection should combine:

- source artifact label or name;
- target artifact label or name;
- `relation_name`;
- `semantic_signature`;
- evidence text or reconstructed source snippets when available;
- relevant keywords, category paths, or entity names from source and target.

This separates graph storage from search indexing. The connection table remains
fast for traversal, while the search registry handles full-text search.

## Why Not Many Connection Tables

Separate tables such as `kb.topic_conns` and `kb.metric_conns` are appealing at
first because each table is smaller and source-specific. The downside is that
the table name encodes source type.

As Deep Wiki adds more artifact types, this creates several problems:

- new artifact types require new tables and new query branches;
- cross-type graph traversal requires unions across many tables;
- indexes, constraints, and rebuild logic can drift between tables;
- search indexing becomes repetitive;
- UI and API code must know too much about physical storage.

A partitioned canonical table gives most of the performance benefit without
fragmenting the data model.

## Searchability Strategy

`semantic_signature` is useful, but it should not carry the full search burden.
Treat it as one part of a generated search document.

Recommended search flow:

1. Store durable edges in `kb.artifact_connections`.
2. Build or rebuild connection search rows in `kb.search_artifacts_connection`.
3. Use PostgreSQL full-text search on the search registry for keyword search.
4. Use the connection table indexes for graph expansion after a search result is
   selected.

This allows searches such as:

- find connections involving a topic, metric, entity, or provision;
- search relation descriptions and evidence snippets;
- filter to one document via `input_record_id`;
- filter to relation families such as `llm` or `line_overlap`;
- traverse from a found artifact to nearby artifacts.

## Practical Defaults

For a first implementation, prefer:

```text
canonical edge table: kb.artifact_connections
partition key: source_type
line provenance table: kb.artifact_line_refs
search partition: kb.search_artifacts_connection
```

Use `relation_method = line_overlap` for shared-line connections and
`relation_method = llm` for model-extracted semantic edges.

Keep `extra_info` for method-specific details, but keep common traversal fields
as first-class columns. In particular, do not hide `source_type`, `source_id`,
`target_type`, `target_id`, `relation_name`, or `relation_method` inside JSON.

The design goal is to let Deep Wiki act like an artifact graph while preserving
the existing typed artifact search model.
