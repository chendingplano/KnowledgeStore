# Hybrid Search (Lexical + Semantic)

## Overview

Search over extracted artifacts (`kb.search_artifacts`) runs as a **hybrid** of two
independent, complementary retrieval paths fused with Reciprocal Rank Fusion (RRF):

- **Lexical** — PostgreSQL `tsvector` full-text search (`ts_rank_cd`), token/keyword
  matching. This is the existing, always-on path.
- **Semantic** — `pgvector` embedding cosine similarity, meaning-based matching that
  bridges synonyms and Chinese ⇄ English gaps that lexical search cannot.

This is the **pgvector interim** of the larger design in
`KnowledgeStore/Research/PostgreSQLIndex.typ`. The eventual target replaces the lexical
half with ParadeDB `pg_search` (true BM25 + Jieba) and adds graph-traversal expansion;
both are **deferred** (see [Future Work](#future-work)). Everything below describes what
is actually implemented today.

## Status & feature flag

The semantic half is dark-launched behind one environment variable:

```
SEARCH_SEMANTIC_ENABLED   (default: false; accepts 1/true/yes/on)
```

- **OFF (default):** the write and read paths reference no embedding columns and behave
  exactly like the original lexical-only system. Safe to deploy before pgvector exists.
- **ON:** reindex computes + writes embeddings, and search fuses lexical + semantic via
  RRF.

The flag lives in `kbsearch.SemanticSearchEnabled()` (`ChenWeb/server/api/kbsearch/semantic.go`).

> **Ordering rule:** never set `SEARCH_SEMANTIC_ENABLED=true` before the pgvector
> migration is applied. With the flag on, `InsertSearchRegistryRows` switches to the
> statement that writes the `embedding` column; if that column does not exist yet, every
> reindex insert fails and breaks the search-indexing step for all artifact types.

## Prerequisites

All four must be in place for embeddings to be written/queried:

1. **pgvector installed** on the Postgres server. On the Nix-managed instance this means
   adding `pgvector` to the postgresql package set and restarting (it is not a plain
   `CREATE EXTENSION` — the extension binary must exist on the server first).
2. **Migration `20260603000001` applied** (adds columns + HNSW indexes; see below).
3. **`EMBEDDING_MODEL_NAME` configured** and resolvable in `.models.toml`. Current value
   `gpt-embedding-small` → `text-embedding-3-small` (1536-dim).
4. **`SEARCH_SEMANTIC_ENABLED=true`**.

## Schema

Migration: `ChenWeb/project_migrations/20260603000001_add_pgvector_embedding_to_search_artifacts.sql`

`kb.search_artifacts` is a LIST-partitioned table (one partition per `artifact_type`:
summary, topic, scene_block, metric, provision, product, semantic_projection, knowledge,
entity, relation, inventory_item). The migration:

```sql
CREATE EXTENSION IF NOT EXISTS vector;

-- added on the partitioned parent -> propagates to all partitions
ALTER TABLE kb.search_artifacts
    ADD COLUMN IF NOT EXISTS embedding_text TEXT,
    ADD COLUMN IF NOT EXISTS embedding      vector(1536);

-- one HNSW (cosine) index per partition, created in a DO loop
CREATE INDEX ... ON kb.search_artifacts_<type> USING hnsw (embedding vector_cosine_ops);
```

- `embedding` — the 1536-dim vector (`vector(1536)`; dimension must match
  `kbsearch.EmbeddingDim`). NULL ⇒ the row is lexical-only.
- `embedding_text` — the exact text that was embedded (kept for re-embedding/debug).
- HNSW indexes are created **per partition**, not on the parent. pgvector parent
  propagation works, but per-partition matches the doc-processor "Add New Doc Processor"
  checklist, so a new artifact-type partition must create its own embedding HNSW index.

The down-migration drops the columns + indexes but intentionally leaves the `vector`
extension installed (it is a shared server facility).

## Write path (how embeddings get populated)

Every processor calls `ReindexXxxSearchForRecord` at the end of its run, which funnels
through the single choke point `replaceRegistryRows`
(`ChenWeb/server/api/doc-processing/search_indexing.go`):

```
ReindexXxxSearchForRecord
  └─ buildXxxRegistryRows           (maps artifact columns -> RegistryRow)
  └─ replaceRegistryRows
       ├─ if SemanticSearchEnabled(): embedRegistryRows(rows)   ← embeds in place
       ├─ DeleteSearchRegistryRowsForRecord
       └─ InsertSearchRegistryRows  (lexical OR embedding-aware statement)
```

- `embedRegistryRows` (`search_indexing_embedding.go`) builds an embedder from
  `EMBEDDING_MODEL_NAME` + `.models.toml`, then for each row embeds
  `EmbeddingText` (falling back to `SearchDocument`), truncated to `maxEmbeddingRunes`
  (6000). It is **best-effort**: a missing model, per-row API failure, or dimension
  mismatch is logged and leaves that row lexical-only (NULL embedding) — it never fails
  the processor.
- `kbsearch.RegistryRow` carries `EmbeddingText` and `Embedding []float64`.
- `InsertSearchRegistryRows` (`registry.go`) branches on the flag:
  - flag OFF → `insertStmtLexical` (13 args, no embedding columns — identical to the
    original behavior).
  - flag ON → `insertStmtSemantic` (adds `embedding_text` = `$14`, `embedding` =
    `$15::vector`). The vector is bound as the text literal `[v1,v2,...]` via
    `kbsearch.FormatVectorLiteral`.

**Scope:** the write path only embeds rows a processor re-indexes *from now on*. Running
`extract_metrics` on record X embeds only record X's metrics, not the rest of the corpus.
Use the backfill endpoint for pre-existing rows.

## Read path (RRF fusion)

`ChenWeb/server/api/kbhandler/search_registry.go`. The handler entry
`queryRegistrySearchResults` branches:

- If `SemanticSearchEnabled()` **and** the query can be embedded
  (`computeQueryEmbedding`, `search_embedding_query.go`) → `queryHybridSearchResults`.
- Otherwise → the original lexical-only query (unchanged, still used as the fallback when
  the query can't be embedded).

`queryHybridSearchResults` builds one statement with two CTEs fused by RRF:

```
$1 = query text     $2 = query embedding (::vector)     $3.. = structural filters
```

- **lexical CTE** — rows matching the FTS clause (`tsvector @@ tsquery`, plus the CJK
  ILIKE fallback), ranked by `ts_rank_cd`, `ROW_NUMBER()` → `rnk`, `LIMIT
  hybridCandidateLimit` (200).
- **semantic CTE** — rows with `embedding IS NOT NULL`, ranked by `embedding <=>
  $2::vector` (cosine), `ROW_NUMBER()` → `rnk`, same limit.
- **fused** — `FULL OUTER JOIN` on `(artifact_type, artifact_id)`; score =
  `COALESCE(1/(rrfK + rnk_lex), 0) + COALESCE(1/(rrfK + rnk_sem), 0)` with `rrfK = 60`.
- Final SELECT joins back to `kb.search_artifacts` for display columns + `ts_headline`
  snippet, ordered by fused score.

**Structural filters** (`artifact_type`, `input_record_id`, category, `semantic_payload`
facets) apply to **both** CTEs and are built by `buildStructuralFilterClauses` /
`appendArtifactFilterClauses` (shared with the lexical `buildRegistrySearchWhereClause`).
The FTS clause constrains **only** the lexical list, so semantically-similar artifacts
that share no query terms can still surface.

> **Known limitation:** the result `total` reported by the handler still comes from the
> lexical `countRegistrySearchResults`, so it can undercount semantic-only matches.
> Acceptable for the interim; revisit if exact hybrid totals are needed.

## Backfill (embedding existing rows)

Rows indexed before the feature was enabled have NULL embeddings. The backfill endpoint
populates them in place without re-running the doc pipeline:

```
POST /kb/search/backfill-embeddings
     ?artifact_type=   (optional; "" / "all" = every type)
     ?limit=           (rows per call; default 200 — call repeatedly until remaining=0)
     ?reembed_all=     (true = recompute every row, not just NULL embeddings)
```

- Handler: `kbhandler.BackfillSearchEmbeddings` (`backfill_embeddings_handler.go`).
- Engine: `kbsearch.BackfillEmbeddings` (`backfill.go`) — selects candidate rows (NULL
  embedding + non-empty text), reads them fully (so the SELECT cursor is not held across
  embedding calls), then embeds + `UPDATE`s each. Returns
  `{scanned, embedded, skipped, failed, remaining}`.
- The embedding client is built once and reused across all rows.
- Independent of `SEARCH_SEMANTIC_ENABLED` — you can backfill first, flip the read flag
  after.

## Key tunables

| Name | Location | Value | Meaning |
|---|---|---|---|
| `EmbeddingDim` | kbsearch/semantic.go | 1536 | Vector dim; must match `vector(N)` + model |
| `rrfK` | kbhandler/search_registry.go | 60 | RRF constant |
| `hybridCandidateLimit` | kbhandler/search_registry.go | 200 | Per-list candidate cap before fusion |
| `maxEmbeddingRunes` | doc-processing/search_indexing_embedding.go | 6000 | Index-time embed text cap |
| `embeddingQueryMaxRunes` | kbhandler/search_embedding_query.go | 6000 | Query/backfill embed text cap |

## Verifying the rollout

```bash
PSQL() { PGPASSWORD="$PW" psql -h localhost -U admin -d miner -tAc "$1"; }

# 1. migration recorded by goose (1 = applied)
PSQL "SELECT is_applied FROM public.project_db_migration WHERE version_id = 20260603000001;"

# 2. extension + columns + indexes physically present
PSQL "SELECT extversion FROM pg_extension WHERE extname='vector';"
PSQL "SELECT count(*) FROM pg_indexes WHERE schemaname='kb' AND indexname LIKE '%_embedding_hnsw';"  -- expect 11

# 3. live process has the flags (doc-processor runs via 'go run')
ps eww -p "$(pgrep -f 'doc-processor' | head -1)" | tr ' ' '\n' | grep -E 'SEARCH_SEMANTIC_ENABLED|EMBEDDING_MODEL_NAME'

# 4. embedding coverage
PSQL "SELECT artifact_type, count(*) total, count(embedding) embedded
      FROM kb.search_artifacts GROUP BY artifact_type ORDER BY artifact_type;"
```

Rollout order: install pgvector → restart Postgres (migration auto-applies) → confirm
`EMBEDDING_MODEL_NAME` resolves → backfill existing rows → set
`SEARCH_SEMANTIC_ENABLED=true` (new reindexes then embed automatically).

## Files

| Concern | File |
|---|---|
| Migration | `ChenWeb/project_migrations/20260603000001_add_pgvector_embedding_to_search_artifacts.sql` |
| Flag, dim, vector literal | `ChenWeb/server/api/kbsearch/semantic.go` |
| RegistryRow + insert statements | `ChenWeb/server/api/kbsearch/registry.go` |
| Backfill engine | `ChenWeb/server/api/kbsearch/backfill.go` |
| Embedding-on-reindex | `ChenWeb/server/api/doc-processing/search_indexing_embedding.go` |
| Reindex choke point | `ChenWeb/server/api/doc-processing/search_indexing.go` |
| Hybrid RRF query + filters | `ChenWeb/server/api/kbhandler/search_registry.go` |
| Query embedding + embedder builder | `ChenWeb/server/api/kbhandler/search_embedding_query.go` |
| Backfill handler | `ChenWeb/server/api/kbhandler/backfill_embeddings_handler.go` |
| Route registration | `ChenWeb/server/api/routes.go` (`POST /kb/search/backfill-embeddings`) |

## Future work

Deferred from the design in `KnowledgeStore/Research/PostgreSQLIndex.typ`:

- **ParadeDB `pg_search` (true BM25 + Jieba)** to replace `tsvector` for the lexical half.
  Blocked on running the ParadeDB distribution (not installable as an extension on the
  current stock Postgres). See `+CAPSULE.md` §3 ("Hybrid Search Index") for the target
  per-partition BM25 index shape.
- **Graph-traversal expansion** over artifact connections (`kb.metric_conns`,
  `kb.topic_conns`, `derive-connections.md`) as a candidate-expansion stage between
  generation and reranking — with weighted edges, bounded hops, and re-scoring.
- **LLM / cross-encoder reranking** of the fused top-k.
- **Multilingual embedding model** (e.g. bge-m3 / multilingual-e5) if Chinese semantic
  recall underperforms with the current OpenAI general model.
- **Exact hybrid totals** (current `total` is lexical-only).
