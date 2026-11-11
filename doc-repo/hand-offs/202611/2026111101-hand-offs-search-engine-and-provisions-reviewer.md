# Handoff: search engine package and provisions reviewer

**Date:** 2026-11-11
**Status:** All of ChenWeb now searches through the `searchengine` package, and `kbhandler`'s copy of the hybrid
search SQL is deleted (2026-11-11, third session, committed). Open: the `search-query-keywords` scenario tests on the
engine path, a disposable-database test for the criteria, and a benchmark-page run before and after.
**Scope:** `ChenWeb/server/api/searchengine`, `ChenWeb/server/api/doc-reviews/review-provisions.go`,
`ChenWeb/server/api/kbhandler/searchengine_hooks.go`.
**Specs and docs:** OpenSpec change `ChenWeb/openspec/changes/hybrid-search-engine-api/` (proposal, design,
specs, `tasks.md` with a status note under sections 2 and 4); devdoc
`KnowledgeStore/doc-repo/devdocs/202611/2026111002-devdoc-provisions-reviewer.md`.

## What was done

1. **No model call without matches.** `reviewProvision` now records one analysis (relationship
   `unrelated`, summary "未在其他文档中找到相关条款（No relevant provisions found in other documents）。")
   and skips the model when a provision has no matches. Test:
   `TestReviewProvision_NoMatchesSkipsModelAndRecordsAnalysis`. Three older tests now pass
   `oneProvisionMatch()` so they still reach the model.
2. **Own provisions excluded before ranking.** `findSimilarProvisions` calls the engine with a reference
   query on `(provision, id)`, `Filters{ArtifactTypes: ["provision"], ExcludeRecordIDs: [recordID]}`,
   `Criteria{MinCosine: provisionMinCosine()}`. The exclusion applies to both candidate lists before
   fusion, so the document's own provisions can no longer crowd out other documents. `MinCosine`
   reads `ARTIFACT_CONNECT_MIN_COSINE` (default 0.75). An unindexed reference
   (`ErrReferenceNotIndexed`) logs a warning and counts as no matches.
3. **`searchengine` package** (new, imports neither `kbhandler` nor `doc-processing`). Entry point
   `Search(ctx, db, cfg, req)`. Files: `types.go`, `hooks.go`, `config.go`, `filters.go`, `terms.go`,
   `lexical.go`, `vector.go`, `engine.go`, plus unit and integration tests.
   - Query is text or a reference; both or neither is rejected.
   - Keyword weights (`pdb.boost` on ParadeDB, weighted `ts_rank_cd` on Postgres); required,
     excluded and minimum-matched keywords; minimum cosine. These run on the fused candidates, with
     counts of removed candidates per criterion.
   - Per-result diagnostics: lexical rank and score, vector rank, cosine, matched keywords.
   - Fusion is unchanged: `wl/(60+lexical_rank) + ws/(60+vector_rank)`, 200 candidates per list.
4. **Hooks.** `kbhandler/searchengine_hooks.go` registers the embedder and the keyword extractor
   with the engine from `init()` (`SetEmbedder`, `SetKeywordExtractor`). The extractor wraps
   `searchQueryKeywords` ([search_query_keywords.go](../../../../ChenWeb/server/api/kbhandler/search_query_keywords.go)),
   forcing keywords on when the request asks for them.

## Second session: similar-artifact callers moved (committed in jj `tnov`)

All callers of `docprocessing.FindSimilarArtifactsOnTheFly` now use the engine, and the function is deleted.

1. **`searchengine.Similar`** (`searchengine/similar.go`): `Similar(ctx, db, ref, SimilarOptions)`. Excludes the
   reference itself, applies `Filters` before ranking, applies the cosine floor, and returns no results (not an
   error) for a reference with no index row. `SimilarOptions.FallbackText` searches by text (keyword extraction off,
   artifact excluded by id) when the reference is not indexed. Also exports `ConnectMinCosine()`
   (`ARTIFACT_CONNECT_MIN_COSINE`, 0.75) and `ConnectMaxLinks()` (`ARTIFACT_CONNECT_MAX_LINKS`, 10).
   New sentinel `ErrNoQueryVector` (a cosine floor with no query vector). Test: `similar_test.go`.
2. **Reviewers** (metrics, inventory items, entities, provisions) call `findSimilarMatches`
   (`doc-reviews/similar.go`), which excludes the record's own artifacts before ranking. Provisions' private
   `provisionMinCosine` is gone; it uses `ConnectMinCosine()`.
3. **Clustering** (`semantic_clustering.go`, `inventory_item_semantic_clustering.go`) and the object-graph handler
   (`kbhandler/object_graph_handler.go`) call `Similar` directly.
4. **Deleted:** `FindSimilarArtifactsOnTheFly`, `queryArtifactHybridCandidates`, `hybridCandidate`,
   `metricConnectMinCosine/MaxLinks` and their constants, `sanitizeTSDictionary`, and their three tests.
   `OnTheFlySemanticMatch` stays (reviewers and the object graph consume it).

**Behaviour changes:**

- A keyword-only match below the cosine floor is dropped; the old code accepted it on lexical score alone.
- With no query vector (semantic search off, or the embedding call failed), `Similar` errors. Reviewers and the object
  graph propagate it, so the review fails; clustering logs a warning and skips the item.
- Metrics, inventory-item and entity reviewers now exclude the record's own artifacts before ranking (they dropped
  them afterwards before).
- The engine hooks (embedder, keyword extractor) are registered by `kbhandler`'s `init()`. `doc-processor` and
  `deepdoc` link `kbhandler`, so both have them; `doc-service` links neither the reviewers nor the clustering.

**Verification:** `go build ./...`, `go vet` for the touched packages, `go test` for `searchengine`, `doc-reviews` and
the `kbhandler` graph tests pass. `doc-processing` has one failing test,
`TestKBMetricsReadersExcludeResolvedRows`, caused by another session's `question_generator_worker.go:133` (a
`kb.metrics` reader without `ref_mention_id IS NULL`). **Not run:** a live review or clustering run comparing old and
new matches; `SEARCHENGINE_TEST_DATABASE_URL` was not set.

## Third session: `kbhandler` moved onto the engine, old SQL deleted

1. **Golden baseline (task 1.2).** `kbhandler/search_golden_live_test.go` (live, read-only, `SEARCH_GOLDEN_MODE=record|compare`,
   `SEARCH_GOLDEN_FILE`) records 65 queries: four questions per generated-question purpose, free text typed and all-types,
   page 2, type and record filters, a provision facet; total, order, score and snippet. Recorded in four configurations
   (hybrid or lexical-only × ParadeDB or Postgres) from the old code. Files are local, in the session scratchpad, not committed;
   re-record before the next change to search with `SEARCH_QUERY_KEYWORDS=off` (the test sets it).
2. **Engine additions** so one implementation serves the HTTP search: `Options.Offset`, `Options.Trace` → `Response.Trace`,
   `Count`, `Config.CandidateLimit`, `MinLexicalScore`, `PhraseFriendly`, `PreviewWords`, the Chinese substring fallback and
   `ts_headline` snippets on the Postgres backend, `ErrNoQueryVector`, `BackendFromEnv`, `PartitionTypes`.
3. **`kbhandler/search_registry.go` is an adapter**: `queryRegistrySearchResults` (retries once keyword-only if the engine
   fails), `queryRegistrySearchResultsCtx` (strict; the benchmark uses it), `countRegistrySearchResults`, and the swappable
   `registrySearchCount` / `registrySearchQuery` the handlers call. `withPrecomputedEmbedding` hands the benchmark's own query
   vector to the searches that follow (the engine never takes vectors in a request). `search_trace.go` builds trace rows from
   `Response.Trace`; the second trace statement and its `REPEATABLE READ` transaction are gone.
4. **Deleted:** `queryHybridSearchResults*`, `queryRegistrySearchResults{Postgres,ParadeDB}`, the WHERE/filter/CTE builders,
   `queryWithVectorIndexScan`, `hybridTraceQuery`/`hybridTraceSelect`, and the tests that asserted that SQL. Handler tests now
   stub the search layer; `search_trace_test.go` tests the conversion.
5. **Result (task 2.4):** default config (hybrid, ParadeDB) 65/65 identical incl. scores, snippets and totals; hybrid Postgres
   65/65; keyword-only Postgres 65/65 (order); keyword-only ParadeDB 58/65, the 7 others are long Chinese questions where the
   old ParadeDB statement failed silently and the old code returned nothing. Intended keyword-only differences: fused score
   instead of raw BM25, stored-text snippet on ParadeDB, 200-result paging cap.
6. **Spike (task 1.1):** reference search about 100 ms on entity (43k rows), relation, metric and provision, more-like-this
   and stored keywords alike.
7. **Docs:** capsule rewritten, Artifact Search row and doc at 1.1.0 (catalogue check in sync), devdoc
   `devdocs/202611/2026111104-devdoc-search-engine-api.md`, `tasks.md` updated.

**Verification:** `go build ./...`; `go vet` for the touched packages; `searchengine` unit and integration tests (against `miner`,
read-only); the chunk integration test on a throwaway database (both backends; the database is dropped); golden comparison above.
Failing tests, none in code touched here: `kbhandler` `TestPlanInputDeletePaths…` (2), `TestMetricScore…` (2) and
`doc-processing` `TestKBMetricsReadersExcludeResolvedRows` (`question_generator_worker.go:133` has no `ref_mention_id IS NULL`).
**Not run:** the benchmark page before and after; `SearchAgentKnowledge` against a knowledge store (same code path as the HTTP
search, covered by the golden lists).

## Commits

- ChenWeb jj `sotp` (git `eba3`): "Provisions reviewer: search engine package, no model call without matches".
- ChenWeb jj `tnov` (6205): the second session's work (similar-artifact callers), committed together with the other
  session's benchmark changes.
- ChenWeb jj `wslt` (67df): "Search engine: move kbhandler search onto searchengine, remove the old hybrid SQL".
- KnowledgeStore: devdoc, module doc, capsule (`2026060201-spec-hybrid-search.md`) and this hand-off, one commit.
- The edit to the provisions-reviewer devdoc (summary, step 2, steps 6 and 7, known limitations, files table) was
  committed in the daily update; the doc may still mention `FindSimilarArtifactsOnTheFly`.

## Verification

- `go test` for `doc-reviews` and `searchengine` passes.
- Integration tests (`searchengine/engine_integration_test.go`, read-only, need
  `SEARCHENGINE_TEST_DATABASE_URL`) passed on the ParadeDB and Postgres backends against dev DB `miner`.
  Never point `TEST_DATABASE_URL` at `miner` (some other tests wipe rows there).
- Four `kbhandler` tests fail with and without this work: two `TestPlanInputDeletePaths…`, two
  `TestMetricScore…`. Confirmed by removing the hooks file.
- **Not run:** a live provisions review comparing `matching_provisions` with the old matches.

## Open work (in order)

| # | Item | Notes |
|---|---|---|
| 1 | Tasks 4.1–4.3 | Separate tests for the `search-query-keywords` scenarios on the engine path; disposable-database test for the criteria (exclusion before ranking, required keyword removing a vector-only result, cosine floor on a lexical-only result); a benchmark-page run before and after. |
| 2 | Archive the change | `openspec archive hybrid-search-engine-api` once 4.x is done; then point the devdoc at `openspec/specs/hybrid-search-engine/`. |
| 3 | Cosine floor | `ARTIFACT_CONNECT_MIN_COSINE` (0.75) was tuned for text-embedding-3-small; recalibrate for bge-m3. |
| 4 | Stale-index metric rows | 5,621 of 8,281 metric index rows belong to records with no `kb.metrics` rows (capsule §13.2); search still returns them. |

## Decisions and pitfalls

- **Not a literal move.** The engine had its own queries from the first session; the third session extended it until it
  matched `kbhandler`'s results on the golden set, then deleted `kbhandler`'s copy.
- **Cosine floor.** The reviewer keeps `MinCosine` 0.75 to preserve the old effective behaviour. It drops
  keyword-only matches below 0.75 cosine (for example provisions that only share a standard number).
  Dropping `Criteria.MinCosine` in `findSimilarProvisions` lifts that, at the cost of weaker matches.
- **Query keywords.** Extraction is off unless `SEARCH_QUERY_KEYWORDS=on`, needs
  `SEARCH_QUERY_KEYWORDS_MODEL_NAME`, falls back to the raw query on any failure, and caches 24 h.
- Engine configuration: `LoadConfig()` reads `[artifact_search]`, `SEARCH_LEXICAL_BACKEND` and
  `SEARCH_SEMANTIC_ENABLED`.
- Use `jj` with explicit paths, never a bare `jj commit`, and never run jj for several repos in
  parallel tool calls.
- `sed -i` fails in this shell environment; edit with python or the Edit tool.

## Documentation status

- **Changed knowledge:** one search engine for every server module; `Similar` and the cosine floor replace
  `FindSimilarArtifactsOnTheFly`; `kbhandler` is an adapter; traces come from the engine's lists.
- **Updated:** `tasks.md`, the hybrid-search capsule, Artifact Search row and doc (1.1.0, catalogue check in sync),
  the new engine devdoc, this hand-off.
- **Stale:** the provisions-reviewer devdoc and the other reviewer devdocs may still name
  `FindSimilarArtifactsOnTheFly`; other openspec `design.md` files (hybrid-search-benchmark,
  hybrid-search-benchmark-trace, analysis-node-related-metrics) describe the removed SQL and CTE trace as history.
  `docs`/`HowTo.md` were not searched.
- **Intentionally left:** the golden result files (local, data-dependent); the old design text of archived changes.
- **Reusable modules:** the engine is part of Artifact Search (`20261111-01`), registered.
