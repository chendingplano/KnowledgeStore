# Hybrid KB Search Design

Reviewed against ChenWeb source and migrations on **2026-10-15**. This document describes implemented behavior and identifies the remaining chunk retrieval work. It does not establish which extensions, flags, or backfills are active in a running database.

**Target capability:** Retrieve document artifacts as evidence for RAG and tools, preserving source documents and canonical line references. Chunks are evidence artifacts in their own right and need lexical and vector retrieval alongside derived summaries, topics, metrics, and other artifacts.

**Current architecture:** Source artifacts feed the partitioned `kb.search_artifacts` registry. Registry search supports ParadeDB BM25, PostgreSQL FTS fallback, and optional pgvector cosine search fused with lexical results. Artifact-local search columns and a dedicated metric search API also remain. Individual chunks currently have range-based connections but **do not yet have registry BM25/vector retrieval**.

The original plan, `ChenWeb/docs/superpowers/plans/2026-05-22-hybrid-kb-fts-implementation.md`, is historical context; current code and Goose migrations determine the behavior below.

## 1. Artifact coverage

Registry values use **singular** artifact types. HTTP scopes and UI labels may use plurals.

| Registry type | ID code | Source | Retrieval status |
|---|---|---|---|
| `summary` | `sum` | `kb.summaries`; summary artifact-file fallback | Registry search |
| `topic` | `tpc` | `kb.topics`; topic artifact-file fallback | Registry search |
| `scene_block` | `sbk` | `kb.scene_objects` | Registry search |
| `metric` | `mtc` | `kb.metrics`, with assertion evidence | Registry search and dedicated metric FTS |
| `provision` | `prv` | `kb.provisions` | Registry search |
| `product` | `prd` | `kb.products` | Registry search |
| `semantic_projection` | `smp` | `kb.semantic_projections` | Registry search |
| `knowledge` | `knw` | `kb.knowledges` | Registry search |
| `entity` | `ent` | `kb.entities` | Registry search |
| `relation` | `rel` | `kb.relations` | Registry search |
| `inventory_item` | `inv` | `kb.inventory_items` | Registry search |
| `chunk` | `chk` | `.chunks` plus canonical lines; `kb.chunk_ranges` for connections | ID helper and UI scope exist; no search partition or registry writer |

`kbsearch.ArtifactTypeCode` also recognizes `inventory_item_duplicate` (`dup`). Recognition by the ID helper alone does not establish registry indexing support.

All artifacts refer to a source document through `kb.inputs.id`. Most source tables and the registry use `input_record_id`; the chunking-run table uses `source_record_id`.

## 2. Chunk production and the retrieval gap

The [chunking capsule](../chunking/+CAPSULE.md) describes the fixed-size chunker. It operates on finalized canonical lines supplied as file bytes or a `BlockBuffer`, skips TOC lines, cuts at line boundaries, and protects table, formula, and list runs. Size is measured in serialized bytes, not tokens.

The chunking operation currently:

1. Builds chunks with regular (`n`) and overlap (`o`) lines.
2. Writes `ARTIFACT_DIR/<floor(record_id / 1000)>/<record_id>/<staging-root>_<parser>.chunks`.
3. Inserts **one run summary** into `kb.chunks`, including aggregate overlap/normal/chunk line-number JSON.
4. Updates the `chunked` entry in `kb.inputs.status`.

Each `.chunks` entry contains only line-number references:

```text
overlap: [38-40]
lines: [41-52, 55]
```

It contains no source text or embeddings. Consumers reconstruct text from canonical lines. Only explicit `lines:` rows define chunk payload and order; `overlap:` is context metadata. Topic extraction and summary generation are separate operations with their own registry reindex calls. Their embeddings do not make the underlying chunk searchable.

A separate `kb.chunk_ranges` table has key `(input_record_id, chunk_id)`, `source_line_spans`, and a generated GiST-indexed `line_range`. `replaceChunkRangesForRecord` transactionally replaces these ranges from canonical fixed-size chunks in downstream indexing paths. This supports line-overlap connections; it is not a text/vector index and is not written by the basic chunking handler itself.

The frontend maps the **content-segments** scope to `artifact_types=chunk`, and the ID helper supports `chunk`. However, migrations define no `kb.search_artifacts_chunk` partition, and indexing has no chunk registry builder/reindex function. That scope therefore cannot retrieve chunks through the current registry population path.

### Required extension: searchable chunks (not implemented)

Chunks should use the existing registry retrieval infrastructure. This design does not require changing `kb.chunks` into a per-chunk text table.

The extension needs to:

1. Add a `chunk` registry partition through Goose, including GIN, record lookup, BM25, cosine HNSW, and inherited GiST line-range index coverage consistent with other partitions.
2. Build one registry row per canonical chunk, resolving its regular line numbers against the finalized canonical source. Populate searchable text, snippet text, source spans, source document metadata, and a useful label. The `.chunks` index alone is insufficient input for text retrieval.
3. Define the ID mapping explicitly. Chunk sequence numbers start at 1, while connection IDs use `ChunkConnectionID(recordID, block.Index)`. Reuse or reconcile that mapping so search results resolve to the same chunk as range connections and the viewer.
4. Keep regular source spans as evidence coverage. If overlap is included as embedding or retrieval context, preserve it separately so it is not presented as new evidence or counted twice.
5. Generate embeddings using the same configured model and dimension as query embeddings, then replace the document's chunk registry rows after successful chunk persistence. Reuse common BM25/FTS and optional hybrid queries; the existing global API can filter `artifact_types=chunk`.
6. Rebuild chunk ranges and search rows when canonical lines or boundaries change, removing stale chunks when counts shrink. Define failure/status reporting and a repair/backfill entry point: `chunked=success` currently does not guarantee search readiness.

Verification must include lexical matches, semantic-only matches, source-line reconstruction, overlap handling, consistent connection IDs, and repeat processing with fewer chunks. These chunk search capabilities are not implemented by this documentation update.

## 3. Canonical search registry

`kb.search_artifacts` is LIST-partitioned by `artifact_type`, with primary key `(artifact_type, artifact_id)`. The original six partitions have been extended with semantic projections, knowledge, entities, relations, and inventory items.

| Columns | Purpose |
|---|---|
| `artifact_type`, `artifact_id`, `input_record_id`, nullable `source_row_id` | Registry identity and source linkage |
| `primary_label`, `secondary_label` | Display labels |
| `search_document`, `search_vector` | Search text and PostgreSQL `tsvector` |
| `snippet_basis` | Preferred excerpt text |
| `source_title`, `source_filename` | Document provenance |
| `category_paths`, `source_line_spans`, `semantic_payload` | JSONB classification, evidence spans, and family-specific data |
| `keywords` | Dedicated `TEXT[]`, default empty array |
| `embedding_text`, `embedding` | Embedded input and nullable `vector(1024)` |
| `line_range` | Stored generated `int8multirange` derived from source spans |
| `updated_at` | Registry refresh timestamp |

Indexes include per-partition GIN on `search_vector` and record lookup, BM25 indexes when `pg_search` is available, cosine HNSW indexes for embeddings, and GiST on `line_range`. New partitions need equivalent coverage; adding an ID code creates neither a partition nor indexes.

Registry IDs follow `<record_id>_<type_code>_<sequence>`, for example `123_mtc_4`. Source-native IDs remain in source tables and payloads. Sequence/position-based IDs do not promise stable identity across changed extraction or chunking results.

The registry is derived. Structured source tables remain authoritative; summary/topic loaders prefer database rows and can fall back to artifact files. Artifact-local search columns still exist, but most artifact search endpoints query the registry directly. This differs from the original proposal that every endpoint would use source-table FTS.

## 4. Retrieval and ranking

### Lexical backend

`registryLexicalBackend()` defaults to **ParadeDB**. `SEARCH_LEXICAL_BACKEND=postgres` (also `pg` or `tsvector`) selects PostgreSQL FTS; other values select ParadeDB.

- **BM25:** Uses the modern `pg_search` API: `search_document ||| query` and `pdb.score(artifact_id)`. Per-partition indexes include the document, labels, snippet, title, and filename, with Jieba tokenization for Chinese/English text.
- **PostgreSQL FTS:** Uses stored `search_vector`, `websearch_to_tsquery` or `plainto_tsquery`, `ts_rank_cd`, and `ts_headline`. CJK queries also use substring matching and label/snippet/document score bonuses.
- Registry inserts build vectors with `to_tsvector('simple', search_document)`. Read configuration allows `simple` or `english`; changing the read dictionary alone does not rebuild stored vectors.

PostgreSQL fallback ranking is not BM25. Query helpers attempt PostgreSQL fallback after ParadeDB query errors. `CheckSearchBackend` can check extension availability and returns an error when the default backend lacks `pg_search`, but the reviewed Go source has no caller for this helper. Do not assume that startup currently enforces this check.

Artifact builders construct `search_document` using family-specific configured weights. Metric/provision construction also avoids duplicate raw/normalized representations. Registry ranking consumes this prepared text rather than executing a separate field-weight formula per family. The dedicated metric API retains weighted field-level PostgreSQL ranking.

### Optional semantic retrieval

`SEARCH_SEMANTIC_ENABLED=true` enables registry embedding writes and hybrid reads; it is **off by default**. `EMBEDDING_MODEL_NAME` resolves the embedding profile. `EMBED_ENTITY_RELATION=false` can skip indexing embeddings for those two families independently.

The current schema/default dimension is **1024**. Migration `20260925000004` replaced the original 1536-dimensional columns with `vector(1024)` and cleared existing vectors, requiring re-embedding. `EMBEDDING_DIMENSIONS` must agree with the stored column type. Equal dimensions alone do not make different models' vectors comparable.

A hybrid registry query:

1. Embeds the query, with a 6000-rune input cap and configured-dimension check.
2. Retrieves up to **200 lexical candidates**, ranked by BM25 or PostgreSQL FTS.
3. Retrieves up to **200 semantic candidates**, ordered by pgvector cosine distance (`<=>`), excluding null embeddings.
4. Applies the same structural filters to both lists. Semantic matches do not need lexical term matches.
5. Joins by `(artifact_type, artifact_id)` and uses reciprocal rank fusion:

```text
score = 1 / (60 + lexical_rank) + 1 / (60 + semantic_rank)
```

A missing rank contributes zero. Results sort by fused score, then artifact ID, before pagination. Scores are backend-specific ranking values, not probabilities.

Query embedding failure falls back to lexical retrieval. A failed ParadeDB hybrid query tries PostgreSQL hybrid; subsequent failures fall through to lexical queries. Failed/unavailable artifact embeddings leave rows usable for lexical retrieval.

**Current limits:** Hybrid retrieval searches a bounded candidate union. `total` still comes from a separate lexical count, so it can undercount semantic-only hits and does not describe the fused result set. PostgreSQL minimum-rank filtering is applied in the lexical result query rather than its count. ParadeDB snippets are plain preferred text; PostgreSQL snippets use `ts_headline`. Callers must tolerate these differences.

## 5. Index lifecycle and failure behavior

`search_indexing.go` supplies family-specific `Reindex*SearchForRecord` functions; inventory indexing has its own family implementation. Summary/topic processing invokes reindexing after producing artifacts. Existing-artifact skip paths can also attempt reindexing.

The common replacement path:

1. Loads source data/builds registry rows before deleting existing registry data.
2. Attempts semantic enrichment when enabled.
3. Deletes registry rows for the document and artifact type.
4. Inserts/upserts rows on `(artifact_type, artifact_id)`.
5. Logs artifact type, record ID, deleted count, and inserted count on success.

Successful repetition removes obsolete rows and avoids duplicates. However, **the registry delete and per-row insert loop do not share a transaction**. An insert failure can leave an empty or partial registry, and readers may observe intermediate state. Source-table triggers maintain local search columns independently; source-plus-registry refresh is not atomic. Error propagation/status behavior depends on the processor caller; skip-path reindex failures are logged as warnings.

Repair options include rerunning family reindexing and backfilling embeddings. `POST /api/v1/kb/search/backfill-embeddings` accepts query parameters `artifact_type`, `limit` (default 200), and `reembed_all=true`. It works independently of the semantic-search flag and returns scanned/embedded/skipped/failed/remaining counts. `ChenWeb/server/cmd/search-embedding-backfill` also exists. These repair existing registry vectors; they do not populate missing chunk rows or rebuild source artifacts.

For bounded `reembed_all=true` calls, repeated requests do not necessarily advance: candidate selection includes already embedded rows and starts from the same ordered prefix. Plan full re-embedding accordingly.

## 6. APIs, tools, and UI

Implemented routes under `/api/v1` include:

| Route | Behavior |
|---|---|
| `GET /kb/search` | Global registry search; optional comma-separated `artifact_types` using singular values |
| `GET /kb/summaries/search` | Registry scope `summary` |
| `GET /kb/topics/search` | Registry scope `topic` |
| `GET /kb/scene-blocks/search` | Registry scope `scene_block` |
| `GET /kb/provisions/search` | Registry scope `provision` |
| `GET /kb/products/search` | Registry scope `product` |
| `GET /kb/inventory-items/search` | Inventory registry search |
| `GET /kb/metrics/search` | Dedicated source-table PostgreSQL metric search |

Use global search for metric BM25/hybrid retrieval and for semantic projections, knowledge, entities, and relations. The dedicated metric route is not the registry hybrid path; it also permits filter-only listing when a supported filter is present.

Common registry requests require non-empty `q` and accept `page`, `page_size`, and `input_record_id`. Defaults are page 1, page size 20, maximum page size 100. Filters include `category_path`, `topic_type`, `scene_type`, `provision_type`, `product_type`, `relation_type`, and inventory/validation fields, as appropriate to the payload.

The common envelope is illustrated below; this is not a runtime result:

```json
{
  "status": true,
  "query": "energy efficiency",
  "artifact_type": "all",
  "page": 1,
  "page_size": 20,
  "total": 1,
  "applied_filters": {"artifact_types": ["metric"]},
  "results": [{
    "artifact_type": "metric",
    "artifact_id": "123_mtc_4",
    "input_record_id": 123,
    "primary_label": "Energy consumption per unit output",
    "snippet": "Energy consumption per unit output",
    "score": 0.0164,
    "source_title": "Example standard",
    "source_line_spans": ["41:52", "55"],
    "keywords": ["energy"],
    "semantic_payload": {}
  }]
}
```

Dedicated metric responses add typed metric fields. The common envelope field is `applied_filters`, not `filters_applied`.

The initial plan for six uniformly shaped per-family tools has not become a universal tool contract. The internal agent service exposes **`search_knowledge`**, using common registry retrieval with active KnowledgeStore scope, optional document group/document/type constraints, and a bounded limit of 1–20. It adds source version/fingerprint and validation metadata for evidence. Document review separately implements `search_metrics`. Tool schemas and permissions must be read at their own boundaries rather than inferred from HTTP routes.

The `home3` search lab and knowledge search views are implemented. `web/src/lib/services/kbArtifactSearch.ts` sends search scopes through `/api/v1/kb/search` with artifact-type filters, including metrics. A UI metric search and the dedicated metric HTTP route can therefore use different ranking paths. The content-segments scope is present but awaits chunk registry indexing.

## 7. Implementation references and verification

Paths below are relative to the workspace root.

| Concern | Source |
|---|---|
| Fixed-size chunks | `ChenWeb/server/api/doc-processing/fix-size-chunking.go`, `chunking-processor.go` |
| Chunk IDs and ranges | `ChenWeb/server/api/doc-processing/connections.go`, `connections_store.go` |
| Family builders/replacement | `ChenWeb/server/api/doc-processing/search_indexing.go`, `search_artifact_indexing.go`, `inventory_item_indexing.go` |
| Embedding generation | `ChenWeb/server/api/doc-processing/search_indexing_embedding.go` |
| Registry writes/IDs/vector config/backfill | `ChenWeb/server/api/kbsearch/{registry,artifact_ids,semantic,backfill}.go` |
| BM25/FTS/hybrid queries | `ChenWeb/server/api/kbhandler/search_registry.go` |
| Envelopes/routes/metric exception | `ChenWeb/server/api/kbhandler/{search_common,summary_search_handler,metric_search_handler}.go`, `ChenWeb/server/api/routes.go` |
| Agent retrieval/tools | `ChenWeb/server/api/kbhandler/agent_search.go`, `ChenWeb/server/api/agentservicehandler/tools.go` |
| Search configuration | `ChenWeb/server/cmd/config/config.go` |
| UI mapping | `ChenWeb/web/src/lib/services/kbArtifactSearch.ts`, `ChenWeb/web/src/lib/components/home3/kb-search-lab-view.svelte` |

Key Goose migrations in `ChenWeb/project_migrations/`:

- `20260522000001`–`20260522000003`: metric FTS, initial registry/local search columns, initial database-artifact backfill.
- `20260526000001`, `20260526000004`, `20260527000010`, `20260531000001`: additional registry families.
- `20260603000001`–`20260603000003`: pgvector and optional/ensure BM25 indexes. Old migration comments about the default backend predate current code.
- `20260614000004`: dedicated keywords column.
- `20260616000003`, `20260617000001`: registry line ranges and chunk connection ranges.
- `20260925000004`: reset vectors and change stored dimension to 1024.

Existing SQL-mock/unit tests in `search_registry_test.go`, `search_indexing_test.go`, and `search_indexing_embedding_test.go` cover registry writes, family builders, filters, mixed results, backend selection, and BM25/pgvector query construction. They do not prove extension availability, live index plans, retrieval quality, atomic replacement, or chunk search support. Those properties need database-backed verification.

This review updates the original design's artifact scope, retrieval behavior, and known gaps. It changes no implementation or formal OpenSpec contract; historical plans and the chunking capsule retain their respective roles. A future chunk retrieval change must add its migration, implementation, tests, and corresponding capsule/spec updates.
