# Module: Artifact Search

**Module ID:** `20261111-01`
**Type:** backend · **Language:** go · **Version:** 1.1.0
**Status:** active — used by document processors, public search, agents and search benchmarks
**Project:** ChenWeb (server)
**Location:** `ChenWeb/server/api/kbsearch`, `ChenWeb/server/api/searchengine`, `ChenWeb/server/api/doc-processing`, `ChenWeb/server/api/kbhandler`, `ChenWeb/server/api/doc-reviews`
**Created:** 2026-11-11
**Devdocs:** [2026111102-devdoc-chunk-hybrid-search](../devdocs/202611/2026111102-devdoc-chunk-hybrid-search.md), [2026102501-devdoc-hybrid-search-benchmark](../devdocs/202610/2026102501-devdoc-hybrid-search-benchmark.md), [2026111104-devdoc-search-engine-api](../devdocs/202611/2026111104-devdoc-search-engine-api.md)

## 1. What it is

Indexes document artifacts and original source chunks in one registry and searches them by words and meaning. Use it when adding another searchable artifact, exposing search to a page or agent, asking "what is similar to this?" from server code, or repairing embeddings. From Go, call `searchengine` (below) instead of writing another lexical-plus-vector query. It combines lexical ranking with cosine similarity through reciprocal rank fusion, preserving source provenance and structural filters.

## 2. Files

| File | Purpose |
|---|---|
| `ChenWeb/server/api/kbsearch/registry.go` | Registry row representation and inserts |
| `ChenWeb/server/api/kbsearch/artifact_ids.go` | Existing artifact address conventions |
| `ChenWeb/server/api/kbsearch/semantic.go` | Feature flag, dimensions and provider limits |
| `ChenWeb/server/api/kbsearch/backfill.go` | Embedding repair, including chunk windows |
| `ChenWeb/server/api/kbsearch/chunk_embeddings.go` | Windowing, generation checks and atomic chunk persistence |
| `ChenWeb/server/api/kbsearch/chunk_source_lock.go` | Source-operation serialization |
| `ChenWeb/server/api/kbsearch/chunk_embeddings_test.go` | Window coverage and transactional failure tests |
| `ChenWeb/server/api/doc-processing/search_indexing.go` | Existing artifact-to-registry builders |
| `ChenWeb/server/api/doc-processing/search_indexing_test.go` | Registry construction tests |
| `ChenWeb/server/api/doc-processing/search_indexing_embedding.go` | Configured embedding batches, retries and attribution |
| `ChenWeb/server/api/doc-processing/search_indexing_embedding_test.go` | Embedding tests |
| `ChenWeb/server/api/doc-processing/search_indexing_chunks.go` | Chunk source rows, strict loading and window embeddings |
| `ChenWeb/server/api/doc-processing/search_indexing_chunks_test.go` | Source/index lifecycle tests |
| `ChenWeb/server/api/doc-processing/chunk_search_backfill.go` | Cursor-based registry creation from saved chunks |
| `ChenWeb/server/api/searchengine/types.go` | Request, response, diagnostics, trace types and the score contract |
| `ChenWeb/server/api/searchengine/engine.go` | `Search`, `Count`, fusion, criteria, result loading |
| `ChenWeb/server/api/searchengine/lexical.go` | Keyword list (ParadeDB BM25, Postgres full text) and counts |
| `ChenWeb/server/api/searchengine/vector.go` | Vector list (registry rows and chunk windows) and cosines |
| `ChenWeb/server/api/searchengine/filters.go` | Filters rendered for every list; partition list |
| `ChenWeb/server/api/searchengine/terms.go` | Keyword cleaning and frequent terms |
| `ChenWeb/server/api/searchengine/hooks.go` | Embedder and keyword-extractor registration |
| `ChenWeb/server/api/searchengine/config.go` | Engine configuration and backend selection |
| `ChenWeb/server/api/searchengine/similar.go` | `Similar` and the similar-artifact thresholds |
| `ChenWeb/server/api/searchengine/engine_test.go` | Unit tests |
| `ChenWeb/server/api/searchengine/engine_integration_test.go` | Read-only integration tests (`SEARCHENGINE_TEST_DATABASE_URL`) |
| `ChenWeb/server/api/searchengine/similar_test.go` | Threshold tests |
| `ChenWeb/server/api/kbhandler/search_registry.go` | HTTP/agent adapter over `searchengine` |
| `ChenWeb/server/api/kbhandler/searchengine_hooks.go` | Registers the query embedder and keyword extractor with the engine |
| `ChenWeb/server/api/kbhandler/search_trace.go` | Benchmark candidate traces built from the engine's lists |
| `ChenWeb/server/api/kbhandler/search_trace_test.go` | Trace conversion tests |
| `ChenWeb/server/api/kbhandler/search_golden_live_test.go` | Live golden-result recorder and comparer (`SEARCH_GOLDEN_MODE`) |
| `ChenWeb/server/api/doc-reviews/similar.go` | Reviewers' similar-artifact helper |
| `ChenWeb/server/api/kbhandler/search_registry_test.go` | Registry retrieval tests |
| `ChenWeb/server/api/kbhandler/summary_search_handler.go` | Public registry search handlers, including chunks |
| `ChenWeb/server/api/kbhandler/chunk_search_backfill_handler.go` | Saved-chunk backfill handler |
| `ChenWeb/server/api/kbhandler/chunk_search_test.go` | Chunk type/query tests |
| `ChenWeb/server/api/kbhandler/chunk_search_integration_test.go` | Disposable PostgreSQL integration test |
| `ChenWeb/server/api/kbhandler/agent_search.go` | Bounded, scoped agent search |

## 3. Interface

- `kbsearch.RegistryRow`, `InsertSearchRegistryRows`, `DeleteSearchRegistryRowsForRecord`: ordinary registry writes.
- `kbsearch.ChunkEmbeddingTexts`, `ReplaceChunkSearchRows`, `UpdateChunkEmbeddings`, `InvalidateChunkSearch`, `ChunkSearchGeneration`, `LockChunkSearchSource`: chunk windows and lifecycle. Acquire the source lock and capture the generation before reading source files, then pass that generation to publication. Publication advances the generation; embedding-only repair checks it without advancing it.
- `docprocessing.EmbedRegistryRows`: configured batching; homogeneous chunk batches cover all windows. `docprocessing.BackfillChunkSearch` creates registry rows from saved boundaries through a supplied centralized pool.
- `searchengine.Search(ctx, db, cfg, Request)`: one hybrid search. `Query` is a text or a reference to an indexed artifact; `Filters` (types, records, exclusions, scope, facets) apply before ranking; `Criteria` (weighted, required and excluded keywords, minimum matched, minimum cosine) filter the fused candidates; `Options` set limit, offset, keyword extraction and tracing. Results carry `Diag` (ranks, cosine, matched keywords). `Score` orders one response only.
- `searchengine.Count`, `searchengine.Similar(ctx, db, ref, SimilarOptions)`, `searchengine.SetEmbedder`, `searchengine.SetKeywordExtractor`: total, similar-to-this-artifact, and the hooks a program registers (`kbhandler` registers both).
- `GET /api/v1/kb/search?q=...&artifact_types=chunk,summary`: standard query with record/category filters and optional effort.
- `GET /api/v1/kb/chunks/search?q=...`: chunk-only query.
- `POST /api/v1/kb/search/backfill-chunks?input_record_id=42`: index saved chunks of one document. Cursor batches use `after_record_id` and `limit` (1–100).
- `kbhandler.SearchAgentKnowledge`: bounded retrieval with knowledge-store scope enforced before ranking.

## 4. Configuration

| Key | Default | Meaning |
|---|---|---|
| `SEARCH_SEMANTIC_ENABLED` | explicitly required | Enable semantic indexing and retrieval |
| `SEARCH_LEXICAL_BACKEND` | `paradedb` | BM25 or `postgres` FTS |
| `EMBEDDING_MODEL_NAME` | required for vectors | Configured embedding profile |
| `EMBEDDING_DIMENSIONS` | `1024` | Must match database vector dimensions |
| `MODELS_FILE` | resolved model file | Model configuration resolution |
| `EMBEDDING_MAX_GOROUTINES` | `20` | Index-time embedding workers |
| `EMBEDDING_BATCH_SIZE` | `8` | Batch size, bounded by provider limits |
| `ARTIFACT_DIR` | required for saved chunks | Per-record artifact root |
| `ARTIFACT_CONNECT_MIN_COSINE` | `0.75` | Cosine floor of `searchengine.Similar` |
| `ARTIFACT_CONNECT_MAX_LINKS` | `10` | Results of `searchengine.Similar` |

Additional existing search keyword, effort and weight controls are documented in [Hybrid Search](../../Capsules/coding-capsules/llm-wiki/hybrid-search.md).

## 5. Usage

```text
GET /api/v1/kb/search?q=thermal+insulation&artifact_types=chunk&input_record_id=42
POST /api/v1/kb/search/backfill-chunks?input_record_id=42
```

These routes use the application's existing authentication middleware. Backfill returns per-record errors and a cursor; embedding failures retain lexical availability.

## 6. Behaviour and conventions

Use centralized database pools, configured models, goose migrations, existing artifact addresses and attributed embedding calls. Additional chunk windows collapse to their parent before fusion. Source spans retain the registry's line-only format; chunk payload reference objects add page numbers and distinguish overlap.

## 7. Scope and limits

ChenWeb-specific registry schema and artifact builders; move only genuinely cross-project functionality to `shared/`. Requires applied vector/chunk migrations. New artifact types need their partition and BM25/HNSW/FTS indexes plus an entry in the search type list. Embedding-only backfill cannot create missing registry rows. Direct file edits need explicit reindexing. Low-effort totals remain lexical counts.
