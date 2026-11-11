# Handoff: search engine package and provisions reviewer

**Date:** 2026-11-11
**Status:** Reviewer fixes and the new `searchengine` package are done and committed. The other
`FindSimilarArtifactsOnTheFly` callers have moved onto the engine (2026-11-11, **uncommitted**). Moving
`kbhandler`'s own search code onto the engine is open.
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

## Second session: similar-artifact callers moved (uncommitted)

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

## Commits

- ChenWeb jj `sotp` (git `eba3`): "Provisions reviewer: search engine package, no model call without
  matches". Explicit paths only. Working copy is now `tnov`.
- **Not committed (second session):** `searchengine/similar.go`, `similar_test.go`, `engine.go`/`types.go`
  (`ErrNoQueryVector`), `doc-reviews/similar.go`, the four `review-*.go` files, the two clustering files,
  `doc-processing/artifact_indexing.go`, `metric_indexing.go`, `metric_indexing_test.go` and
  `kbhandler/object_graph_handler.go`. Commit with explicit paths; the working copy also holds the other session's
  files.
- **Not committed:** the edit to the provisions-reviewer devdoc in KnowledgeStore (summary, step 2,
  steps 6 and 7, known limitations, files table). The same file holds another session's unrelated
  uncommitted rewrite, so commit it by hunk, not as a whole.
- `kbhandler/hybrid_search_benchmark*.go`, two migrations
  (`20261111000011`, `20261111000012`) and web files are dirty from **another session**. Do not
  commit or reformat them.

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
| 1 | Tasks 1.1, 1.2 | Spike `pdb.more_like_this` latency on entity/relation/metric partitions; record a golden result set (benchmark questions plus provision and chunk queries via `/kb/search` and `SearchAgentKnowledge`). **Needed before any move.** |
| 2 | Tasks 2.2, 2.4 | Move `kbhandler`'s lexical/vector/fusion/embedding/keyword SQL, HTTP routes, `SearchAgentKnowledge`, effort loop and benchmark worker/trace onto the engine; golden set must match exactly; then delete the duplicates. Blocked on the other session's benchmark edits landing. Until then two copies of the SQL exist. |
| 3 | Tasks 4.1–4.3 | `search-query-keywords` scenarios on the engine path; disposable-DB integration test (exclusion before ranking, required keyword removing a vector-only result, cosine floor on a lexical-only result); benchmark before and after. |
| 4 | Tasks 5.1–5.3 | Hybrid-search capsule; Artifact Search catalogue row `20261111-01` plus `module-artifact-search.md` (v1.1.0) and the catalogue check; devdoc for the engine API (create-devdoc skill). |
| 5 | ~~Follow-up changes~~ | Done, uncommitted; see "Second session" above. |

## Decisions and pitfalls

- **Additive, not a move.** The engine was written beside `kbhandler` to avoid colliding with the other
  session's dirty files. That is a deviation from tasks 2.2/2.4 as written; `tasks.md` says so.
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

- **Changed knowledge:** reviewer matching path and no-match behaviour; new engine package and its contract;
  `Similar` and the cosine floor replace `FindSimilarArtifactsOnTheFly` everywhere.
- **Updated:** `tasks.md`, the provisions-reviewer devdoc (uncommitted).
- **Stale:** code comments in `inventory_item_indexing.go` and `metric_indexing.go` (~lines 85, 153) still name
  `FindSimilarArtifactsOnTheFly`; the provisions-reviewer devdoc and the reviewer devdocs may too.
- **Stale or missing:** the Artifact Search module doc and catalogue row, the hybrid-search capsule, and a
  devdoc for the engine API (tasks 5.1–5.3). Nothing about the engine is yet in the `hybrid-search-benchmark` docs.
- **Reusable modules:** the engine is not registered in the catalogue yet (task 5.2).
