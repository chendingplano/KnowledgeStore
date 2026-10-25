# 1. Hybrid Search (Lexical + Semantic)

- DocID: `doc-2026060201`
- **Status:** Accepted
- **Date:** 2026-06-02
- **Last Updated**: 2026-10-25 (by Claude Code; §8.3 effort levels, metric route correction, §13.2 candidate traces)
- **Deciders:** Chen Ding
- **Tags:** Search Engine, Hybrid Search

## 2. Overview

Search over extracted artifacts (`kb.search_artifacts`) runs as a **hybrid** of two
independent, complementary retrieval paths fused with Reciprocal Rank Fusion (RRF):

- **Lexical** — ParadeDB `pg_search` BM25 (Jieba tokenizer) by default, queried on the
  per-type partitions that carry the BM25 indexes; optionally matching LLM-extracted query
  keywords instead of every query word. PostgreSQL `tsvector` full-text search
  (`ts_rank_cd`) remains as the alternative backend and the fallback when a ParadeDB query
  fails.
- **Semantic** — `pgvector` embedding cosine similarity, meaning-based matching that
  bridges synonyms and Chinese ⇄ English gaps that lexical search cannot.

This is the **pgvector + ParadeDB** implementation of the larger design in
`KnowledgeStore/Research/PostgreSQLIndex.typ`. Graph-traversal expansion remains
**deferred** (see [Future Work](#future-work)). Everything below describes what is actually
implemented today (updated 2026-10-24).

> **History note (2026-10-24).** Until openspec `search-query-keywords`, the ParadeDB
> queries read the partitioned parent `kb.search_artifacts`, which pg_search rejects
> ("does not contain a USING bm25 index"). Every search therefore failed over to the
> `tsvector` path; BM25 had never actually served a search. The same day, hybrid search
> stopped scanning every embedding (the vector CTE could not use the HNSW index) and the
> RRF weights became configurable.

## 3. Status & feature flag

The semantic half is dark-launched behind one environment variable:

```
SEARCH_SEMANTIC_ENABLED   (required; accepts 1/true/yes/on, anything else = off)
```

The variable must be set explicitly. `kbhandler.CheckSearchBackend` runs at startup and
the process exits with an error if it is unset or empty (set it to `false` to keep
lexical-only search).

- **OFF (`false`):** the write and read paths reference no embedding columns and behave
  exactly like the original lexical-only system. Safe to deploy before pgvector exists.
- **ON:** reindex computes + writes embeddings, and search fuses lexical + semantic via
  RRF.

The flag lives in `kbsearch.SemanticSearchEnabled()` (`ChenWeb/server/api/kbsearch/semantic.go`).

> **Ordering rule:** never set `SEARCH_SEMANTIC_ENABLED=true` before the pgvector
> migration is applied. With the flag on, `InsertSearchRegistryRows` switches to the
> statement that writes the `embedding` column; if that column does not exist yet, every
> reindex insert fails and breaks the search-indexing step for all artifact types.

## 4. Prerequisites

All four must be in place for embeddings to be written/queried:

1. **pgvector installed** on the Postgres server. On the Nix-managed instance this means
   adding `pgvector` to the postgresql package set and restarting (it is not a plain
   `CREATE EXTENSION` — the extension binary must exist on the server first).
2. **Migrations `20260603000001` and `20260925000004` applied** (adds columns + HNSW
   indexes; the second resizes them to 1024 — see below).
3. **`EMBEDDING_MODEL_NAME` configured** and resolvable in `.models.toml`, with
   `EMBEDDING_DIMENSIONS=1024`. Current value `bgem3-runshen-19` → bge-m3 (1024-dim).
   Until 2026-09-25 it was `gpt-embedding-small` → `text-embedding-3-small` (1536-dim).
4. **`SEARCH_SEMANTIC_ENABLED=true`**.

## 5. Schema

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

- `embedding` — originally `vector(1536)`; now `vector(1024)` since migration
  `20260925000004` (dimension must match `kbsearch.EmbeddingDim` /
  `EMBEDDING_DIMENSIONS`). NULL ⇒ the row is lexical-only.

### 5.1 Changing the embedding model

Vectors from different models are not comparable, so a model switch always means a
full re-embed, and a dimension change also needs a migration. The 2026-09-25 switch to
bge-m3 (`20260925000004`) resized every embedding column to `vector(1024)` with
`USING NULL` — `kb.search_artifacts` (all partitions), `kb.ontology_class_contract_search`,
`kb.product_profile_nodes`, `kb.object_nodes`, `kb.cdm_projections` — then re-embedded:

- `kb.search_artifacts`: `mise exec -- go run ./server/cmd/search-embedding-backfill`
  (batched, session-free; skips entity/relation when `EMBED_ENTITY_RELATION` is off).
  The per-row `POST /kb/search/backfill-embeddings` endpoint is too slow for a full
  corpus.
- `kb.ontology_class_contract_search`: `class-contract-search-backfill --reembed-all`.
- `kb.product_profile_nodes`: refilled lazily during product-review grounding.

The shared vLLM bge-m3 host (`210.5.158.91:8801`) manages ~350 chars/s and times out
under concurrent load, so bulk re-embeds should use the local llama.cpp profile
(`EMBEDDING_MODEL_NAME=bge-m3-llama-cpp` for that command only); its vectors match the
vLLM host's (cosine 0.99999 on the same text). Cosine thresholds tuned for
`text-embedding-3-small` (`CATEGORY_MATCH_MIN_COSINE`, `ARTIFACT_CONNECT_MIN_COSINE`,
product-review `object_embedding_min` / `hybrid_similarity_min`, semantic-clustering
0.85 defaults) need recalibrating for bge-m3.
- `embedding_text` — the exact text that was embedded (kept for re-embedding/debug).
- HNSW indexes are created **per partition**, not on the parent. pgvector parent
  propagation works, but per-partition matches the doc-processor "Add New Doc Processor"
  checklist, so a new artifact-type partition must create its own embedding HNSW index.

The down-migration drops the columns + indexes but intentionally leaves the `vector`
extension installed (it is a shared server facility).

## 6. Write path (how embeddings get populated)

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

## 7. Registry search documents and weights

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

## 8. Read path (RRF fusion)

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
$1 = query text (or first keyword)   $2 = query embedding (::vector)
$3.. = structural filters, then any further keywords, then page size and offset
```

- **lexical CTE**
  - *Postgres:* rows matching `tsvector @@ tsquery` (+ CJK ILIKE fallback), ranked by
    `ts_rank_cd`, `ROW_NUMBER()` → `rnk`, `LIMIT hybridCandidateLimit` (200).
  - *ParadeDB:* reads the `kb.search_artifacts_<type>` partitions, never the parent:
    the requested type's partition, or a `UNION ALL` with one branch per partition (all
    11, or those named in `artifact_types`), each branch taking its own top 200 by
    `pdb.score(artifact_id)`. Partition names come only from a fixed list of types
    (`searchArtifactPartitionTypes`). The match clause covers the registry fields
    `search_document`, `primary_label`, `secondary_label`, `snippet_basis`,
    `source_title` and `source_filename`, never raw source-table columns:
    - without keywords: `field ||| $1` — any token of the raw query;
    - with keywords (see below): `field &&& $k` — every token of one keyword in one
      field — OR-ed over keywords, so artifacts matching more keywords score higher.
    No CJK ILIKE fallback is needed because the BM25 index uses the Jieba tokenizer.
    In a mixed-type search each branch scores with its own partition's statistics.
- **semantic CTE** — `ORDER BY embedding <=> $2::vector LIMIT 200` on the parent
  (pgvector merges the per-partition HNSW scans), then `ROW_NUMBER()` over the distance.
  The plain `ORDER BY … LIMIT` is the only shape pgvector serves from the index; the
  earlier `ROW_NUMBER() OVER (ORDER BY distance)` computed every distance first. The query
  runs in a transaction with `SET LOCAL hnsw.iterative_scan = relaxed_order`; without it an
  HNSW scan returns at most `hnsw.ef_search` rows (40 by default), not 200. Identical in
  both backends.
- **fused** — `FULL OUTER JOIN` on `(artifact_type, artifact_id)`; score =
  `COALESCE(wl/(rrfK + rnk_lex), 0) + COALESCE(ws/(rrfK + rnk_sem), 0)` with `rrfK = 60`
  and `wl`, `ws` from `[artifact_search] hybrid_lexical_weight` / `hybrid_semantic_weight`
  (default 1.0 each; 0 drops a list). The weights are written as `float8` literals; a bare
  `1` made the division integer and every score 0.
- **Final SELECT** joins back to `kb.search_artifacts` for display columns. Snippet is
  `ts_headline(...)` on the Postgres path; raw `snippet_basis` / `search_document` on the
  ParadeDB path (no equivalent of `ts_headline` in pg_search).

### 8.1 Query keywords for BM25

With the ParadeDB backend and `SEARCH_QUERY_KEYWORDS=on`
(`kbhandler/search_query_keywords.go`, spec `openspec/specs/search-query-keywords`), an LLM
first turns the query into 2–6 keywords, each in English and Chinese: question words and
filler are dropped, codes and symbols kept, and no concepts the query does not mention are
added (`prompts/prompt-search-query-keywords-v1.md`). The cleaned list (at most 12 strings)
replaces the raw query in the ParadeDB clause of the count, the lexical-only search and the
hybrid lexical CTE.

- Model: the `.models.toml` profile in `SEARCH_QUERY_KEYWORDS_MODEL_NAME` (default
  `deepseek-flash-processor`), always with reasoning disabled (about 1 s per call; with
  reasoning DeepSeek Flash takes about 70 s).
- Cache: in memory per trimmed query string, 24 hours, 2,000 entries; failures are not
  cached.
- Fallback: switch off, model or prompt load failure, timeout
  (`SEARCH_QUERY_KEYWORDS_TIMEOUT_MS`, default 3000), LLM error or no usable keyword →
  the raw-query clause, exactly as before. Search never fails because of this step.
- Measured (benchmark below, 212 paraphrased queries over 2,660 metrics): BM25 R@10 0.47 →
  0.80 (English queries 0.20 → 0.75), matching a median of about 110 metrics instead of all
  of them; hybrid at weights 1.0/1.0: 0.85 → 0.90. Vector alone: 0.95.

### 8.2 Search run IDs

Each search takes one run ID from the sequence `kb.search_run_id_seq` (migration
`20261024000015`): one per search API request (`searchRegistryArtifacts`, shared by its count and
result queries), one per agent search call (`SearchAgentKnowledge`) and one per benchmark question
(§13.2). The ID and the user (when known) travel in the context (`searchCall`,
`kbhandler/search_run.go`) to the search's LLM calls, which record them as `run_id` / `user_id` in
`public.llm_usage_event`:

- query embedding — `call_reason = search_query_embedding`, `call_loc = MID-20261024-02`;
- query keywords — `call_reason = search_query_keywords`, `call_loc = MID-20261024-01`.

A keyword cache hit makes no call, so a repeated query may log only its embedding. Filter LLM
Usage Logs by Run ID to see one search's calls. If the sequence cannot be read, the search still
runs with run ID 0 (a warning is logged).

### 8.3 Effort levels

Registry search (`/kb/search` and the per-type routes in the table below) takes
`effort=low|medium|high` (default `low`; other values → HTTP 400, `CWB_KB_GSR_015`).
Code: `kbhandler/search_effort.go`; openspec change `hybrid-search-effort-levels`.

- **low** — the input is the query, exactly as before.
- **medium / high** — an LLM first analyses the input (`prompt-search-effort-analyze-v1.md`):
  *direct* (it names what it wants; the first attempt searches it as written) or *compose* (it
  describes a situation; the LLM writes 1–3 queries naming the inferred quantity). Each
  **attempt** runs the current queries through the normal hybrid search (top 20 each), fuses
  everything seen so far with RRF (k = 60), and a judge LLM (`prompt-search-effort-judge-v1.md`)
  sees the request, the inferred need, the queries tried and the top 10 candidates (label,
  snippet and the first 800 characters of their `search_document`). It returns whether a
  candidate answers the request, which ones, and new queries from another angle. The loop stops
  when one matches, when the judge proposes nothing new, or after `HYBRID_SEARCH_MEDIUM_EFFORTS`
  (default 2) / `HYBRID_SEARCH_HIGH_EFFORTS` (default 5) attempts. Matches are ranked first, then
  the fused list.
- "Found" is the judge's decision — live search has no ground truth.
- Model `HYBRID_SEARCH_EFFORT_MODEL_NAME` (default `deepseek-flash-processor`, reasoning off),
  `HYBRID_SEARCH_EFFORT_TIMEOUT_MS` per call (default 20000). Calls carry the search run ID with
  call reasons `search_effort_analyze` / `search_effort_judge`.
- Failures degrade: analysis failure → low-effort search; judge failure → the fused results so
  far. The response adds `effort` and `effort_trace` (strategy, need, attempts with queries,
  matches and reasons); `total` is the length of the final list.
- First measurement (12 prompt-v3 questions, keywords on): single-shot hybrid ranked the
  targets 1–44; high effort put 10 of 12 at rank 1 and the worst from 44 to 7, at about 3–6 s per
  question when the first attempt succeeds and 20–27 s when all five attempts run.

**Choosing types.** The type comes from the route (`/search/<type>`, or the all-types route).
On the all-types route, `artifact_types=a,b` (comma-separated) narrows the set; an unknown
value is rejected with HTTP 400 (`CWB_KB_GSR_014`).

**Artifact types.** There are 11, one partition `kb.search_artifacts_<type>` each (the list is
`searchArtifactPartitionTypes` in `search_registry.go`; the partitions come from the migrations
`20260522000002`, `20260526000001`, `20260526000004`, `20260527000010`, `20260531000001`):

| `artifact_type` | Per-type route | Also in `artifact_types=` |
|---|---|---|
| `summary` | `/kb/summaries/search` | yes |
| `topic` | `/kb/topics/search` | yes |
| `scene_block` | `/kb/scene-blocks/search` | yes |
| `metric` | none (`/kb/metrics/search` is a separate full-text search over `kb.metrics`, not hybrid; use `/kb/search?artifact_types=metric`) | yes |
| `provision` | `/kb/provisions/search` | yes |
| `product` | `/kb/products/search` | yes |
| `inventory_item` | `/kb/inventory-items/search` | yes |
| `semantic_projection` | none | yes |
| `knowledge` | none | yes |
| `entity` | none | yes |
| `relation` | none | yes |

All types are searched together by `/kb/search`. A new type needs a partition, a BM25 index,
an HNSW embedding index and an entry in `searchArtifactPartitionTypes`.

**Candidate counts.** The 200-row cap applies per branch, not per query: a lexical search
over N partitions can feed up to 200 × N rows into the fusion step (the semantic list is
always one list of 200). The final page is cut after RRF fusion.

**Structural filters** (`artifact_type`, `input_record_id`, category, `semantic_payload`
facets) apply to **both** CTEs. The hybrid path uses `buildStructuralFilterClauses`
(filters only, no FTS clause); the lexical path uses `appendArtifactFilterClauses` inside
`buildRegistrySearchWhereClause` (filters + FTS clause). Both encode the same filter set.
The FTS clause constrains **only** the lexical list, so semantically-similar artifacts
that share no query terms can still surface.

> **Known limitation:** the result `total` reported by the handler still comes from the
> lexical `countRegistrySearchResults`, so it can undercount semantic-only matches.
> Acceptable for the interim; revisit if exact hybrid totals are needed.

## 9. Key tunables

| Name | Location | Value | Meaning |
|---|---|---|---|
| `EmbeddingDim` | kbsearch/semantic.go | 1024 (was 1536) | Vector dim; must match `vector(N)` + model |
| `rrfK` | kbhandler/search_registry.go | 60 | RRF constant |
| `hybridCandidateLimit` | kbhandler/search_registry.go | 200 | Per-list candidate cap before fusion |
| `hybrid_lexical_weight`, `hybrid_semantic_weight` | config.toml `[artifact_search]` | 1.0, 1.0 | RRF weights of the lexical and semantic lists; 0 drops a list |
| `hnsw.iterative_scan` | `SET LOCAL` in hybrid queries | `relaxed_order` | Lets an HNSW scan return the full 200 candidates |
| `SEARCH_QUERY_KEYWORDS` | env | `off` (dev: `on`) | LLM query keywords for the ParadeDB clause |
| `SEARCH_QUERY_KEYWORDS_MODEL_NAME`, `_PROMPT`, `_TIMEOUT_MS` | env | `deepseek-flash-processor`, `prompt-search-query-keywords-v1.md`, 3000 | Keyword model, prompt and timeout |
| `max_mutable_docs`, `max_deleted_ratio` | `maintain_bm25_indexes` schedule params | 500, 0.5 | When the maintenance job rebuilds a BM25 index |
| `maxEmbeddingRunes` | doc-processing/search_indexing_embedding.go | 6000 | Index-time embed text cap |
| `embeddingQueryMaxRunes` | kbhandler/search_embedding_query.go | 6000 | Query/backfill embed text cap |
| `*_search_weights` | config.toml | artifact-specific | Registry `search_document` repeat weights |

## 10. Verifying the rollout

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

## 11. Files

| Concern | File |
|---|---|
| Migration | `ChenWeb/project_migrations/20260603000001_add_pgvector_embedding_to_search_artifacts.sql` |
| Flag, dim, vector literal | `ChenWeb/server/api/kbsearch/semantic.go` |
| RegistryRow + insert statements | `ChenWeb/server/api/kbsearch/registry.go` |
| Backfill engine | `ChenWeb/server/api/kbsearch/backfill.go` |
| Embedding-on-reindex | `ChenWeb/server/api/doc-processing/search_indexing_embedding.go` |
| Reindex choke point + weighted registry document builders | `ChenWeb/server/api/doc-processing/search_indexing.go` |
| Search weight config | `ChenWeb/config.toml`, `ChenWeb/server/cmd/config/config.go` |
| Hybrid RRF query + filters, ParadeDB partition reads | `ChenWeb/server/api/kbhandler/search_registry.go` |
| Query keyword extraction + cache | `ChenWeb/server/api/kbhandler/search_query_keywords.go`, `ChenWeb/prompts/prompt-search-query-keywords-v1.md` |
| BM25 index maintenance job | `ChenWeb/server/api/kbsearch/bm25_maintenance.go`, registered in `ChenWeb/server/api/kbhandler/scheduler_jobs.go`; schedule seed `ChenWeb/project_migrations/20261024000010_seed_bm25_index_maintenance_schedule.sql` |
| Specs | `ChenWeb/openspec/specs/search-query-keywords/`, `…/search-index-maintenance/` |
| Benchmark (category index, hybrid, keywords) | `ChenWeb/benchmark/category-index/` (README has all results) |
| Live benchmark page (generated questions) | `ChenWeb/server/api/kbhandler/hybrid_search_benchmark*.go`, `ChenWeb/server/api/kbhandler/search_trace.go` (candidate traces), `ChenWeb/web/src/lib/components/home3/hybrid-search-benchmark-view.svelte`, `…/hybrid-search-benchmark-analyze.svelte` |
| Backend default + startup check | `ChenWeb/server/api/kbhandler/search_registry.go` (`registryLexicalBackend`, `CheckSearchBackend`, `CheckParadeDBInstalled`) |
| Query embedding + embedder builder | `ChenWeb/server/api/kbhandler/search_embedding_query.go` |
| Search run IDs (usage-log correlation) | `ChenWeb/server/api/kbhandler/search_run.go` |
| Effort levels (analyse → search → judge loop) | `ChenWeb/server/api/kbhandler/search_effort.go`, `ChenWeb/prompts/prompt-search-effort-*-v1.md` |
| Backfill handler | `ChenWeb/server/api/kbhandler/backfill_embeddings_handler.go` |
| Route registration | `ChenWeb/server/api/routes.go` (`POST /kb/search/backfill-embeddings`) |
| Startup wiring | `ChenWeb/server/cmd/deepdoc/main.go` (calls `CheckSearchBackend` after migrations) |

## 12. ParadeDB BM25

Go implementation and migrations are complete. ParadeDB is now the **default** lexical
backend (see `doc-2026061103`). Set `SEARCH_LEXICAL_BACKEND=postgres` to fall back to
tsvector.

- Migrations: `20260603000002_add_paradedb_bm25_to_search_artifacts.sql`,
  `20260603000003_ensure_paradedb_bm25_search_artifacts.sql`
- Read path branches into `queryRegistrySearchResultsParadeDB` /
  `queryHybridSearchResultsParadeDB` unless `SEARCH_LEXICAL_BACKEND=postgres`.
- Startup check: `kbhandler.CheckSearchBackend` verifies `pg_search` is installed
  after migrations; process exits with a fatal error if it is not.
- **Partitions only.** pg_search 0.21.8 accepts BM25 operators (`|||`, `&&&`, `pdb.score`)
  only on a table that has the BM25 index, i.e. each `kb.search_artifacts_<type>`
  partition, never the partitioned parent (any form: literal or bound type filter,
  generic or custom plan). A new artifact-type partition needs its own BM25 index and an
  entry in `searchArtifactPartitionTypes`.

### 12.1 Mutable segments and the maintenance job

pg_search keeps recently written documents in **mutable segments**, which it searches
without the compiled index structures. Reindexing a record deletes and re-inserts its
registry rows, so a partition rewritten in one go can end up with most documents mutable
and its old segment full of deleted documents. On 2026-10-24 the summary partition held all
789 documents (about 4,000 characters each) in a mutable segment: each BM25 predicate took
0.6 s, and an all-types keyword search 15 s. `REINDEX` brought a predicate to 1 ms.
`VACUUM` does not compact mutable segments, the index option `mutable_segment_rows = 0` does
not help after a rewrite, and `paradedb.force_merge` is deprecated.

The scheduled job **`maintain_bm25_indexes`** ("Maintain Search BM25 Indexes", spec
`search-index-maintenance`) therefore runs hourly (schedule seeded by migration
`20261024000010`):

1. drops invalid leftovers of an interrupted concurrent rebuild (`…_ccnew…`);
2. lists the BM25 indexes on `kb.search_artifacts_%` from the catalog (new partitions are
   covered automatically);
3. reads each index's segments with `paradedb.index_info(index, false)`;
4. rebuilds with `REINDEX INDEX CONCURRENTLY` (searches keep working) each index whose
   mutable documents exceed `max_mutable_docs` (500) or whose deleted share exceeds
   `max_deleted_ratio` (0.5).

Params on the schedule row: `max_mutable_docs`, `max_deleted_ratio`, `dry_run` (report only)
and `limit` (rebuilds per run, default unlimited). One index's failure does not stop the
others. Each run's result in `kb.scheduled_job_runs` lists every index with its live,
mutable and deleted document counts, the action (`rebuilt`, `would_rebuild`, `skipped`,
`over_limit`, `failed`) and the time taken. The first live run rebuilt three indexes
(inventory_item, metric, product) in about 0.2 s each.

Inspect an index by hand:

```sql
SELECT mutable, num_docs, num_deleted
FROM paradedb.index_info('kb.kb_search_artifacts_summary_bm25'::regclass, false);
```

## 13. Future work

Deferred from the design in `KnowledgeStore/Research/PostgreSQLIndex.typ`:

- **Graph-traversal expansion** over artifact connections (`kb.metric_conns`,
  `kb.topic_conns`, `derive-connections.md`) as a candidate-expansion stage between
  generation and reranking — with weighted edges, bounded hops, and re-scoring.
- **LLM / cross-encoder reranking** of the fused top-k.
- **Exact hybrid totals** (current `total` is lexical-only).
- **Tune the RRF weights from real queries.** On the benchmark's paraphrased queries a
  lexical weight of 0.5 ranked better than 1.0, but those queries favour vector search by
  construction; the weights stay at 1.0 until real query logs are evaluated.

(The multilingual embedding model listed here earlier is done: bge-m3 since 2026-09-25.)

### 13.1 Evaluation

`ChenWeb/benchmark/category-index/` measures search on 212 LLM-paraphrased known-item queries
(half English, half Chinese) over the 2,660 metrics in `kb.metrics`, against testbed copies
of the search rows. Main results (R@10): vector alone 0.95; raw-query BM25 0.47; BM25 with
query keywords 0.80; hybrid at weights 1.0/1.0 0.85 with the raw query and 0.90 with
keywords. Adding `kb.metrics.metric_categories` keys to the search document changed nothing.
The benchmark also tested a category index (ICS domain × metric facet) as a replacement for
vector search: at the same share of the corpus scanned, k-means IVF found more targets. See
its README for details and caveats.

### 13.2 Live benchmark page

**System Admin → Benchmark → Hybrid Search Benchmark → Run Benchmark** (development page;
openspec change `hybrid-search-benchmark`) measures the live search instead of testbed copies. A
run takes the `testbed.generated_questions` rows of a purpose — all of them, or those picked in the *Tests to run* dialog — (only `search_metrics` today; each
question targets one metric, `metric_id` = `artifact_id`) and searches artifact type `metric`
over the whole corpus three times with the production hybrid query
(`queryHybridSearchResultsParadeDB`, or the tsvector variant): weights 1/0 (lexical only), 0/1
(semantic only) and the configured `[artifact_search]` weights (hybrid). A zero weight leaves the
other list's order unchanged; results with fused score 0 count as misses. It records the target's
rank in the first 200 results (`hybridCandidateLimit`) and reports R@1/5/10 and MRR per mode,
overall and by hop type and language.

- Tables: `testbed.hybrid_search_benchmark_runs` (status, progress and the settings in force:
  lexical backend, `SEARCH_QUERY_KEYWORDS`, `EMBEDDING_MODEL_NAME`, weights, candidate limit) and
  `testbed.hybrid_search_benchmark_results` (question snapshot, keywords, three ranks, hybrid top
  10, error, search run ID — §8.2). Migrations `20261024000014`, `20261024000015`.
- API (admin): `POST|GET /kb/hybrid-search-benchmark/runs`, `GET …/runs/:id`,
  `GET …/questions` (the dialog's search: created from/to, question-generation run, hop type,
  language, input record, words in question, words in answer — every word must occur, as a
  case-insensitive substring — and exact metric ID; returns every match up to 2,000). A run's
  `question_ids` (up to 5,000) must all belong to its purpose, else HTTP 400.
- The *Query keywords* default is the server process's `SEARCH_QUERY_KEYWORDS`. A dev server
  started before that variable was added to `mise.local.toml` reports it off; restart `mise dev`.
- Run options (start form; defaults = the live configuration, returned as `defaults` by the run
  list): query keywords on/off, the two RRF weights (0–100, not both 0) and candidates per list
  (1–1000, `registrySearchConfig.candidateLimit`; ranks beyond it are misses). Keywords are
  switched per search through `searchCall.keywords`, overriding `SEARCH_QUERY_KEYWORDS`. A run
  records the keyword model and prompt it used (migration `20261024000016`).
- Timings per question (ms): query embedding, keyword extraction (a fresh LLM call that bypasses
  the keyword cache, `searchCall.freshKeywords`; the three searches then hit the cache), and each
  mode's search query. The page's *Query time* = embedding + keywords + hybrid query, i.e. one
  live hybrid search. First live check (5 questions, keywords on): about 1.2–1.5 s, of which the
  keyword call 0.9–1.4 s, embedding 40–100 ms, each search query 120–290 ms.
- Every mode searches only the metric partition: the lexical side reads
  `kb.search_artifacts_metric` directly, and the semantic side's `artifact_type = $n` filter makes
  Postgres prune the other ten partitions at run time (`EXPLAIN`: *Subplans Removed: 10*).
- Questions run in a pool of *Parallel queries* workers (run option, 1–32, default 8; migration
  `20261025000001`). Query times therefore include the load of the other workers. 40 questions
  took 6.7 s at 8 workers. Each stored result extends the run's 10-minute deadline, and an expired
  `running` run is marked failed on the next listing. A server restart (e.g. air rebuilding) kills
  the worker goroutines, so the run then expires.
- A failed or empty keyword call is not cached, so after one the question's three searches run
  without keywords (the raw query, as live search falls back to) instead of calling the model
  again; the result row records `query keywords failed or empty`. On 2026-10-25 every
  `deepseek-flash` call returned HTTP 402 (account balance exhausted), which produced exactly this.
- Run IDs are per feature, so a search run ID can equal another feature's run ID in
  `llm_usage_event`; filter by Run ID *and* Call Reason (`search_query_*`).
- The question generator writes each question from its target metric's own context, so these
  are easy known-item queries that favour vector search (as in §13.1). Only the exact target
  counts as a hit (no near-duplicate credit).
- **Candidate traces** (openspec `hybrid-search-benchmark-trace`, migration `20261025000004`). A
  benchmark search can carry a `searchTraceSink` (`registrySearchConfig.trace`, set only by the
  benchmark worker). Both hybrid queries are built from shared CTEs — ParadeDB:
  `lexical_partitions` (the per-partition BM25 branches) → `lexical` (merged by raw score) →
  `semantic` → `fused`; tsvector: `lexical` → `semantic` → `fused` — and with a sink
  `queryWithVectorIndexScan` runs, in the same `REPEATABLE READ, READ ONLY` transaction right after
  the production statement, a trace statement: the same CTEs plus `hybridTraceSelect`, one row per
  candidate per stage. The production statement's text gained the extra CTE and columns but its
  plan is unchanged (`EXPLAIN` compared). The fused order is checked against the returned results
  (`trace differs from the search results` otherwise); a failed trace never fails the search.
  Traced: each question's hybrid-mode search (`seq` 1) and every effort-loop search (matched to
  its attempt by query text). Stored in `testbed.hybrid_search_benchmark_queries` and
  `testbed.hybrid_search_benchmark_candidates`: `lexical_partition` (BM25 `pdb.score`, rank within
  the partition), `lexical` (BM25 or `ts_rank_cd`, merged rank + `partition_rank`), `semantic`
  (similarity = 1 − cosine distance), `fused` (RRF score, final rank, `lexical_rank`,
  `semantic_rank`). `hybrid_ms`/`effort_ms` exclude trace time. Read through
  `GET …/results/:id/trace?limit=` (first `limit` rows per stage + the target's rows), shown in the
  page's *Analyze* dialog. Check runs 20/21: stored ranks equal the trace ranks for every question;
  ~1,000 rows per traced search, ~280 bytes per row.

### 13.3 Artifact types
Currently, there are 11 artifact types. More types may be added in the future.
Table 'kb.search_artifacts' is partitioned by artifact types. When querying, 
it queries all the involved types, one per query, and each returns 200 candidates.
If there are too many types, it will affect performance.

An improvement is not to partition on artifact types but by a separate field.
A partition can contain multiple types.

Partitions will be dynamic.
- Initially, there is only one partition
- When a partition becomes too big, split it to multiple by re-grouping
  on its member types. We will test how big a partition should consider splitting

## 14. Appendix: Backfill (one-time operation, already completed)

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
