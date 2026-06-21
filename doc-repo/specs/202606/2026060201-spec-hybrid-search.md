# Hybrid Search (Lexical + Semantic)

- DocID: `doc-2026060201`
- **Status:** Accepted
- **Date:** 2026-06-02
- **Deciders:** Chen Ding
- **Tags:** Search Engine, Hybrid Search

## Overview

Search over extracted artifacts (`kb.search_artifacts`) runs as a **hybrid** of two
independent, complementary retrieval paths fused with Reciprocal Rank Fusion (RRF):

- **Lexical** — PostgreSQL `tsvector` full-text search (`ts_rank_cd`), token/keyword
  matching. This is the existing, always-on path.
- **Semantic** — `pgvector` embedding cosine similarity, meaning-based matching that
  bridges synonyms and Chinese ⇄ English gaps that lexical search cannot.

This is the **pgvector + ParadeDB** implementation of the larger design in
`KnowledgeStore/Research/PostgreSQLIndex.typ`. The lexical half now defaults to
ParadeDB `pg_search` (BM25 + Jieba), with PostgreSQL `tsvector` retained as a fallback
backend. Graph-traversal expansion remains **deferred** (see
[Future Work](#future-work)). Everything below describes what is actually implemented
today.

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

## Registry search documents and weights

Hybrid search runs against the normalized registry table `kb.search_artifacts`, not
directly against each source artifact table. For each artifact, the reindexer reads the
source row (`kb.entities`, `kb.metrics`, `kb.summaries`, etc.) and builds one
`kbsearch.RegistryRow`:

- `primary_label`, `secondary_label`, `snippet_basis`, `semantic_payload`, and other
  display/filter fields are stored separately.
- `search_document` is the lexical text indexed in `kb.search_artifacts.search_vector`
  and, for ParadeDB, in the `pg_search` BM25 index.
- `embedding_text` is stored only when semantic indexing succeeds. If no explicit
  `EmbeddingText` is supplied by the registry row builder, the embedding path uses
  `SearchDocument` as the text to embed.

Artifact-specific weight blocks in `config.toml`, such as:

```toml
[entities_search_weights]
entity = 1.8
entity_type = 1.2
aliases = 1.2
desc_text = 1.0
keywords = 2.2
```

do **not** mean that BM25 queries the raw source columns
`kb.entities.entity`, `kb.entities.entity_type`, `kb.entities.aliases`,
`kb.entities.desc_text`, and `kb.entities.keywords` as separate weighted fields.
Instead, those weights are applied during registry-row construction in
`search_indexing.go` by repeating each field's text in the single registry
`search_document`.

The current conversion is:

```go
repeats = round(weight * 2)
```

So `entity = 1.8` and `keywords = 2.2` both currently become about four repeats, while
`desc_text = 1.0` becomes about two repeats. BM25 still sees one text field; the
repetition changes term frequency and therefore influences the lexical score.

For entities specifically:

```
kb.entities fields
  entity, entity_en,
  entity_type, entity_type_en,
  aliases, aliases_en,
  desc_text, desc_text_en,
  keywords, keywords_en
    ↓ buildEntityRegistryRows + entities_search_weights
kb.search_artifacts.search_document
    ↓ lexical BM25 / tsvector search
kb.search_artifacts.embedding_text / embedding
    ↓ semantic pgvector search
```

This means `search_document` is not "mainly for embedding." It is the primary lexical
document searched by BM25/FTS, and it is also the fallback text embedded for semantic
search when `EmbeddingText` is not separately set.

> **Design note:** true BM25 field weighting would require preserving source fields as
> distinct indexed fields in `kb.search_artifacts` or querying artifact-specific source
> tables/indexes directly with field boosts. The current implementation approximates
> field weights through controlled repetition in a single `search_document`.

## Read path (RRF fusion)

`ChenWeb/server/api/kbhandler/search_registry.go`. The handler entry
`queryRegistrySearchResults` branches:

- If `SemanticSearchEnabled()` **and** the query can be embedded
  (`computeQueryEmbedding`, `search_embedding_query.go`):
  - If lexical backend is paradedb (the default; override with `SEARCH_LEXICAL_BACKEND=postgres`) → `queryHybridSearchResultsParadeDB` (BM25 + pgvector RRF).
  - Otherwise → `queryHybridSearchResults` (tsvector + pgvector RRF, described below).
- Otherwise → the original lexical-only query (unchanged, still used as the fallback when
  the query can't be embedded).

Both `queryHybridSearchResults` (Postgres) and `queryHybridSearchResultsParadeDB` share
the same two-CTE RRF structure. The semantic CTE and fusion formula are identical; the
lexical CTE differs by backend:

```
$1 = query text     $2 = query embedding (::vector)     $3.. = structural filters
```

- **lexical CTE**
  - *Postgres:* rows matching `tsvector @@ tsquery` (+ CJK ILIKE fallback), ranked by
    `ts_rank_cd`, `ROW_NUMBER()` → `rnk`, `LIMIT hybridCandidateLimit` (200).
  - *ParadeDB:* rows matching registry fields with `field ||| $query`, ranked by
    `pdb.score(artifact_id)`, same limit. The searched registry fields include
    `search_document`, `primary_label`, `secondary_label`, `snippet_basis`,
    `source_title`, and `source_filename`; they do not include raw source-table fields
    such as `kb.entities.entity` directly. No CJK ILIKE fallback is needed because the
    BM25 index uses the Jieba tokenizer.
- **semantic CTE** — rows with `embedding IS NOT NULL`, ranked by `embedding <=>
  $2::vector` (cosine), `ROW_NUMBER()` → `rnk`, same limit. Identical in both backends.
- **fused** — `FULL OUTER JOIN` on `(artifact_type, artifact_id)`; score =
  `COALESCE(1/(rrfK + rnk_lex), 0) + COALESCE(1/(rrfK + rnk_sem), 0)` with `rrfK = 60`.
- **Final SELECT** joins back to `kb.search_artifacts` for display columns. Snippet is
  `ts_headline(...)` on the Postgres path; raw `snippet_basis` / `search_document` on the
  ParadeDB path (no equivalent of `ts_headline` in pg_search).

**Structural filters** (`artifact_type`, `input_record_id`, category, `semantic_payload`
facets) apply to **both** CTEs. The hybrid path uses `buildStructuralFilterClauses`
(filters only, no FTS clause); the lexical path uses `appendArtifactFilterClauses` inside
`buildRegistrySearchWhereClause` (filters + FTS clause). Both encode the same filter set.
The FTS clause constrains **only** the lexical list, so semantically-similar artifacts
that share no query terms can still surface.

> **Known limitation:** the result `total` reported by the handler still comes from the
> lexical `countRegistrySearchResults`, so it can undercount semantic-only matches.
> Acceptable for the interim; revisit if exact hybrid totals are needed.

## Key tunables

| Name | Location | Value | Meaning |
|---|---|---|---|
| `EmbeddingDim` | kbsearch/semantic.go | 1536 | Vector dim; must match `vector(N)` + model |
| `rrfK` | kbhandler/search_registry.go | 60 | RRF constant |
| `hybridCandidateLimit` | kbhandler/search_registry.go | 200 | Per-list candidate cap before fusion |
| `maxEmbeddingRunes` | doc-processing/search_indexing_embedding.go | 6000 | Index-time embed text cap |
| `embeddingQueryMaxRunes` | kbhandler/search_embedding_query.go | 6000 | Query/backfill embed text cap |
| `*_search_weights` | config.toml | artifact-specific | Registry `search_document` repeat weights |

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
| Reindex choke point + weighted registry document builders | `ChenWeb/server/api/doc-processing/search_indexing.go` |
| Search weight config | `ChenWeb/config.toml`, `ChenWeb/server/cmd/config/config.go` |
| Hybrid RRF query + filters | `ChenWeb/server/api/kbhandler/search_registry.go` |
| Backend default + startup check | `ChenWeb/server/api/kbhandler/search_registry.go` (`registryLexicalBackend`, `CheckSearchBackend`, `CheckParadeDBInstalled`) |
| Query embedding + embedder builder | `ChenWeb/server/api/kbhandler/search_embedding_query.go` |
| Backfill handler | `ChenWeb/server/api/kbhandler/backfill_embeddings_handler.go` |
| Route registration | `ChenWeb/server/api/routes.go` (`POST /kb/search/backfill-embeddings`) |
| Startup wiring | `ChenWeb/server/cmd/deepdoc/main.go` (calls `CheckSearchBackend` after migrations) |

## ParadeDB BM25

Go implementation and migrations are complete. ParadeDB is now the **default** lexical
backend (see `doc-2026061103`). Set `SEARCH_LEXICAL_BACKEND=postgres` to fall back to
tsvector.

- Migrations: `20260603000002_add_paradedb_bm25_to_search_artifacts.sql`,
  `20260603000003_ensure_paradedb_bm25_search_artifacts.sql`
- Read path branches into `queryRegistrySearchResultsParadeDB` /
  `queryHybridSearchResultsParadeDB` unless `SEARCH_LEXICAL_BACKEND=postgres`.
- Startup check: `kbhandler.CheckSearchBackend` verifies `pg_search` is installed
  after migrations; process exits with a fatal error if it is not.

## Future work

Deferred from the design in `KnowledgeStore/Research/PostgreSQLIndex.typ`:

- **Graph-traversal expansion** over artifact connections (`kb.metric_conns`,
  `kb.topic_conns`, `derive-connections.md`) as a candidate-expansion stage between
  generation and reranking — with weighted edges, bounded hops, and re-scoring.
- **LLM / cross-encoder reranking** of the fused top-k.
- **Multilingual embedding model** (e.g. bge-m3 / multilingual-e5) if Chinese semantic
  recall underperforms with the current OpenAI general model.
- **Exact hybrid totals** (current `total` is lexical-only).

## Appendix: Backfill (one-time operation, already completed)

> **Note:** This backfill has already been run on the production corpus. This section is
> kept for reference in case a fresh instance or schema reset requires it again.

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
