# Hybrid Search Benchmark — measure the live metric search with generated questions

**Date:** 2026-10-25 \
**Scope:** What the Hybrid Search Benchmark page does, how to read its numbers, and what to check
when a result looks wrong. Open it before changing search (keywords, weights, embeddings, indexes)
or before trusting a benchmark score. \
**Code root:** `ChenWeb/server/api/kbhandler/hybrid_search_benchmark*.go`,
`ChenWeb/web/src/lib/components/home3/hybrid-search-benchmark-*.svelte`

**Traceability — openspec** (change `hybrid-search-benchmark`, implemented, not yet archived;
when it is archived the files move to `openspec/changes/archive/<date>-hybrid-search-benchmark/`
and the spec to `openspec/specs/hybrid-search-benchmark/spec.md`):
- `ChenWeb/openspec/changes/hybrid-search-benchmark/proposal.md` — why this exists
- `ChenWeb/openspec/changes/hybrid-search-benchmark/design.md` — how it works, alternatives
  considered, risks
- `ChenWeb/openspec/changes/hybrid-search-benchmark/tasks.md` — implementation log, eight task
  groups added as the page grew
- `ChenWeb/openspec/changes/hybrid-search-benchmark/specs/hybrid-search-benchmark/spec.md` — the
  requirements. **Update this spec file, not just this doc, if behavior changes** — this doc
  explains the feature for people and points at code; the spec is the contract for agents.

Related: search itself is described in spec `doc-2026060201` (hybrid search; §8.2 search run IDs,
§13.2 this benchmark). The questions come from the Question Generator, devdoc
`2026102401-devdoc-question-generator.md`.

## Summary

The knowledge base search finds metrics in two ways and combines them:

- **Lexical** search matches words, like a classic search engine (BM25). When *query keywords* are
  on, a language model first rewrites the question into short English and Chinese keywords.
- **Semantic** search matches meaning, using embeddings (numeric fingerprints of text), so it can
  find a metric worded differently or written in the other language.
- **Hybrid** search merges the two ranked lists (Reciprocal Rank Fusion, RRF). This is what users
  get.

The Question Generator writes test questions, each meant to find one specific metric. This page
sends those questions through the real search code and records, for each question, where its
target metric ended up in each of the three lists. That turns "is search good?" into numbers you
can compare before and after a change.

**Running a benchmark.** Open **Development → System Admin → Benchmark → Hybrid Search Benchmark →
Run Benchmark**. In *Start a benchmark run*:

- Choose the *Purpose* (today only **Search Metrics**) and optionally describe what changed.
- Adjust the search settings for this run. Each starts at the server's current configuration:
  **Query keywords** on/off, **Lexical weight** and **Semantic weight** (how much each list counts
  when merged; 0 ignores a list), **Candidates per list** (how many results each list keeps; a
  target ranked lower counts as not found), and **Parallel queries** (how many questions run at
  once).
- Optionally press **Tests to run** to pick questions. The dialog searches the questions by
  creation time, generating run, hop type, language, source document, words in the question or
  answer, and metric ID; tick individual questions or select every match. Ticks survive new
  searches. With nothing ticked, the run uses every question of the purpose.
- Press **Run benchmark**. The run works in the background; the page refreshes every two seconds
  until it finishes.

**Reading the results.** The *Runs* table lists past runs with their progress and hybrid R@10;
**View** opens one. A run shows its settings in two groups (*Run* and *Search settings*, including
the keyword prompt and model), then:

- **Scores** per mode, for all questions or split by hop type or language. **R@k** is the share of
  questions whose target is in the top k results (R@10 = 0.9 means 9 in 10 were on the first page
  of ten). **MRR** (mean reciprocal rank) averages 1 ÷ rank: 1.0 if every target came first, 0.5 if
  every target came second; a miss counts as 0. MRR rewards putting the target near the top, not
  just on the page.
- **Questions**: one row per question with the target metric, its rank in the Lexical, Semantic
  and Hybrid lists ("miss" when not found), the keywords used, the **Query time**, and a **Search
  run ID**. Query time is what one live hybrid search costs: embedding + keyword extraction + the
  hybrid query; hover for the parts. The search run ID finds that question's model calls in **LLM
  Usage Logs**. A red note under a question explains a failure, e.g. that keyword extraction
  failed and lexical search used the raw question instead.

Results are kept in the database (schema `testbed`), so runs can be compared later.

## Where things live

- **Page:** ChenWeb development page, System Admin → Benchmark → Hybrid Search Benchmark → Run
  Benchmark (menu id `sysadmin-hybrid-search-benchmark-run`, shown only on the development page).
  Admin-only, like the Question Generator.
- **Frontend:** `web/src/lib/components/home3/hybrid-search-benchmark-view.svelte` (page),
  `hybrid-search-benchmark-questions.svelte` (Tests to run dialog),
  `web/src/lib/services/hybridSearchBenchmarkService.ts`; text in `web/messages/*.json` (`hsb_*`,
  `hsbq_*`).
- **Backend** (`server/api/kbhandler/`): `hybrid_search_benchmark.go` (types, settings, scoring),
  `_handler.go` (API), `_worker.go` (runs the questions), `_questions.go` (dialog search, question
  selection); `search_run.go` (search run IDs and per-search keyword switch). API under
  `/api/v1/kb/hybrid-search-benchmark/`.
- **Search code it measures:** `search_registry.go` (the hybrid query), `search_embedding_query.go`,
  `search_query_keywords.go`. The benchmark calls these directly; it has no copy of the search.
- **Data:** `testbed.hybrid_search_benchmark_runs` (one row per run, with its settings),
  `testbed.hybrid_search_benchmark_results` (one row per question: ranks, keywords, timings,
  errors); sequence `kb.search_run_id_seq`. Migrations `20261024000014`–`20261024000016`,
  `20261025000001`.

## Known limitations

- **Easy questions.** Each question is written from its target metric's own text, so semantic
  search finds most targets at rank 1. Scores show how modes compare on known-item questions, not
  how search performs on real user queries.
- **Exact target only.** A near-duplicate of the target (the same metric in another document)
  counts as a miss.
- **Metrics only.** The only purpose is *Search Metrics*, and every query searches only metrics
  (the metric partition of `kb.search_artifacts`), across all documents.
- **Parallel load is in the timings.** With several parallel queries, each question's times include
  the load of the others. For clean per-query timings, run with Parallel queries = 1.
- **Restarts end a run.** A run lives in the server process. If the server restarts (the dev
  server rebuilds on every code change), the run stops and shows *failed* about ten minutes after
  its last result. Start it again.
- **Keyword failures fall back silently in live search.** If the keyword model fails, search uses
  the raw question. The benchmark marks such questions, but scores still include them, with
  lexical ranks from the raw question.
- **Run IDs are shared.** Each feature numbers its own runs, so a search run ID can equal an
  unrelated run ID in LLM Usage Logs. Filter by Run ID *and* Call Reason (`search_query_embedding`,
  `search_query_keywords`).
- **Selection limits.** The Tests to run dialog lists at most 2,000 matches per search, and a run
  takes at most 5,000 picked questions.

## When something looks wrong

- **Query keywords unchecked although `SEARCH_QUERY_KEYWORDS=on`.** The default comes from the
  running server's environment, not the config file. A `mise dev` started before the setting was
  added still reports *off*. Check which process serves port 8080 (`lsof -tiTCP:8080 -sTCP:LISTEN`,
  then `ps eww <pid>`) and restart `mise dev`. Ticking the box overrides it for the run either way.
- **Keywords column empty, lexical misses English questions.** The keyword model failed. Look up
  the question's search run ID in LLM Usage Logs; on 2026-10-25 every DeepSeek call returned HTTP
  402 (account balance exhausted).
- **Every question failed with "query embedding failed".** The embedding model in
  `EMBEDDING_MODEL_NAME` is unreachable or misconfigured.
