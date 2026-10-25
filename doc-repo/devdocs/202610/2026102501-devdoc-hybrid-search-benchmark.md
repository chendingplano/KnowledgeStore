# Hybrid Search Benchmark — measure the live metric search with generated questions

**Date:** 2026-10-25 (updated the same day: effort levels, prompt-v3 questions) \
**Scope:** What the Hybrid Search Benchmark page does, how to read its numbers, and what to check
when a result looks wrong. Open it before changing search (keywords, weights, embeddings, indexes,
effort levels) or before trusting a benchmark score. \
**Code root:** `ChenWeb/server/api/kbhandler/hybrid_search_benchmark*.go`,
`ChenWeb/server/api/kbhandler/search_effort.go`,
`ChenWeb/web/src/lib/components/home3/hybrid-search-benchmark-*.svelte`

**Traceability — openspec** (both changes implemented, not yet archived; when archived, each
change folder moves to `openspec/changes/archive/<date>-<change>/` and its spec to
`openspec/specs/<capability>/spec.md`):
- `ChenWeb/openspec/changes/hybrid-search-benchmark/` — the benchmark page itself:
  `proposal.md` (why), `design.md` (how, alternatives, risks), `tasks.md` (implementation log,
  eight task groups added as the page grew), `specs/hybrid-search-benchmark/spec.md`
  (requirements).
- `ChenWeb/openspec/changes/hybrid-search-effort-levels/` — effort levels for hybrid search and
  the benchmark's *Effort loop* mode: same four documents, spec in
  `specs/hybrid-search-effort/spec.md`.
- **Update those spec files, not just this doc, if behavior changes** — this doc explains the
  feature for people and points at code; the specs are the contract for agents.

Related: search itself is described in spec `doc-2026060201` (hybrid search; §8.2 search run IDs,
§8.3 effort levels, §13.2 this benchmark). The questions come from the Question Generator, devdoc
`2026102401-devdoc-question-generator.md` (openspec `question-generator-indirect-hops` for the
v3 question style).

## Summary

The knowledge base search finds metrics in two ways and combines them:

- **Lexical** search matches words, like a classic search engine (BM25). When *query keywords* are
  on, a language model first rewrites the question into short English and Chinese keywords.
- **Semantic** search matches meaning, using embeddings (numeric fingerprints of text), so it can
  find a metric worded differently or written in the other language.
- **Hybrid** search merges the two ranked lists (Reciprocal Rank Fusion, RRF). This is what users
  get.

Hybrid search can also run at a higher **effort**. At *Low* it searches the user's words as
written. At *Medium* or *High*, a language model first works out what the user is really asking
for, writes its own search queries when the request describes a situation instead of naming the
metric, checks whether the results answer the request, and if not tries again from another angle
— up to 2 attempts at Medium and 5 at High by default.

The Question Generator writes test questions, each meant to find one specific metric. *One-hop*
questions name the metric; *two-hop* and *multi-hop* questions (from prompt v3 on) describe a
situation without naming it, so the searcher has to work out what to look for. This page sends the
questions through the real search code and records, for each question, where its target metric
ended up. That turns "is search good?" into numbers you can compare before and after a change.

**Running a benchmark.** Open **Development → System Admin → Benchmark → Hybrid Search Benchmark →
Run Benchmark**. In *Start a benchmark run*:

- Choose the *Purpose* (today only **Search Metrics**) and optionally describe what changed.
- Adjust the search settings for this run. Each starts at the server's current configuration:
  - **Query keywords** on/off.
  - **Lexical weight** and **Semantic weight** — how much each list counts when merged; 0 ignores
    a list.
  - **Candidates per list** — how many results each list keeps; a target ranked lower counts as
    not found.
  - **Parallel queries** — how many questions run at once.
  - **Effort** — Low, Medium or High (see above). Medium and High add an *Effort loop* result
    for every question and take several seconds per question.
- Optionally press **Tests to run** to pick questions. Its label shows what is selected. The
  dialog searches the questions by creation time, generating run, hop type, language, source
  document, words in the question or answer, and metric ID; tick individual questions or select
  every match. Ticks survive new searches. With nothing ticked, the run uses every question of the
  purpose. Filtering by generating run is how you benchmark old (v1/v2) and new (v3) questions
  separately.
- Press **Run benchmark**. The run works in the background; the page refreshes every two seconds
  until it finishes.

**Reading the results.** The *Runs* table lists past runs with their progress and hybrid R@10;
**View** opens one. A run shows its settings in two groups — *Run* (purpose, progress, start and
finish time, description) and *Search settings* (lexical backend, query keywords, the keyword
prompt and model, embedding model, weights, candidates per list, parallel queries, effort and its
attempt limit) — then:

- **Scores** per mode, for all questions or split by hop type or language. **R@k** is the share of
  questions whose target is in the top k results (R@10 = 0.9 means 9 in 10 were on the first page
  of ten). **MRR** (mean reciprocal rank) averages 1 ÷ rank: 1.0 if every target came first, 0.5 if
  every target came second; a miss counts as 0. MRR rewards putting the target near the top, not
  just on the page. Medium and High runs add an **Effort loop** row.
- **Questions**: one row per question, with
  - the target metric, hop type and language;
  - its rank in the **Lexical**, **Semantic** and **Hybrid** lists ("miss" when not found) — these
    three are always a single search of the question as written;
  - for Medium/High runs, its **Effort loop** rank, with the number of attempts, whether the model
    judged it found, and the time; a *Queries tried* list under the question shows what the model
    inferred the user needs and every query it tried, with its reason;
  - the **Query time** (one live hybrid search: embedding + keyword extraction + the hybrid query;
    hover for the parts), the keywords used, and a **Search run ID** that finds the question's
    model calls in **LLM Usage Logs**.

  A red note under a question explains a failure, e.g. that keyword extraction failed and lexical
  search used the raw question instead.

Results are kept in the database (schema `testbed`), so runs can be compared later.

**First results.** On 12 prompt-v3 questions with keywords on, a single hybrid search ranked the
targets between 1 and 44 (two-hop up to 11, multi-hop up to 44). At High effort, 10 of the 12
targets came first and the worst improved from 44 to 7.

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
  selection); `search_run.go` (search run IDs and per-search keyword switch); `search_effort.go`
  (the effort loop). API under `/api/v1/kb/hybrid-search-benchmark/`.
- **Search code it measures:** `search_registry.go` (the hybrid query), `search_embedding_query.go`,
  `search_query_keywords.go`, `search_effort.go`. The benchmark calls these directly; it has no
  copy of the search. The same effort levels are available to callers of the hybrid search API as
  `effort=low|medium|high` on `/kb/search` (use `artifact_types=metric` for metrics) and the
  per-type registry routes. `/kb/metrics/search` is a different, older full-text search over
  `kb.metrics`, not hybrid search, and has no effort levels.
- **Prompts** (`ChenWeb/prompts/`): `prompt-search-effort-analyze-v1.md` (what does the request
  need; direct or composed queries), `prompt-search-effort-judge-v1.md` (do the candidates answer
  it; new queries if not).
- **Configuration:** `HYBRID_SEARCH_MEDIUM_EFFORTS` (default 2), `HYBRID_SEARCH_HIGH_EFFORTS`
  (default 5), `HYBRID_SEARCH_EFFORT_MODEL_NAME` (default `deepseek-flash-processor`),
  `HYBRID_SEARCH_EFFORT_TIMEOUT_MS` (default 20000); query keywords use `SEARCH_QUERY_KEYWORDS*`.
- **Data:** `testbed.hybrid_search_benchmark_runs` (one row per run, with its settings),
  `testbed.hybrid_search_benchmark_results` (one row per question: ranks, keywords, timings,
  effort loop result and trace, errors); sequence `kb.search_run_id_seq`. Migrations
  `20261024000014`–`20261024000016`, `20261025000001`, `20261025000002`.

## Known limitations

- **Question difficulty depends on the generator version.** Questions from prompts v1/v2
  (question-generation runs 1–9) were mostly direct or compound lookups that name the target, so
  semantic search found 98–100% in the top 10 at every hop level. Prompt v3 (from run 10) makes
  two- and multi-hop questions describe the need without naming the metric. Questions are still
  written from the target's own text, so they are not real user queries.
- **Effort "found" is the model's opinion.** The loop never sees the target; it stops when its
  judge believes a result answers the question. The Effort loop rank shows whether that belief was
  right: the judge can reject the right metric (for example when the question's situation and the
  metric's text disagree) or accept a wrong one.
- **Effort costs time and model calls.** Each attempt is one judge call plus up to three searches
  (each with its own embedding and, when on, keyword call); the analysis is one more call. A
  question takes about 3–6 s when the first attempt succeeds and 20–27 s when all five High
  attempts run.
- **Results vary between runs.** The keyword and effort models do not answer identically every
  time, so ranks can move a little when the same questions are run again.
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
  `search_query_keywords`, `search_effort_analyze`, `search_effort_judge`).
- **Selection limits.** The Tests to run dialog lists at most 2,000 matches per search, and a run
  takes at most 5,000 picked questions.

## When something looks wrong

- **Query keywords unchecked although `SEARCH_QUERY_KEYWORDS=on`.** The default comes from the
  running server's environment, not the config file. A `mise dev` started before the setting was
  added still reports *off*. Check which process serves port 8080 (`lsof -tiTCP:8080 -sTCP:LISTEN`,
  then `ps eww <pid>`) and restart `mise dev`. Ticking the box overrides it for the run either way.
- **Keywords column empty, lexical misses English questions.** The keyword model failed. Look up
  the question's search run ID in LLM Usage Logs; HTTP 402 from DeepSeek means the account balance
  is exhausted (seen on 2026-10-25).
- **Effort loop rank 1 but "not judged found", all attempts used.** The judge would not accept the
  candidate. Open *Queries tried* and read its reasons: usually the question describes a situation
  the metric's text does not mention (a question-generation issue), or the judge saw too little of
  the candidate.
- **Red "effort: analysis failed" or "judge failed".** The effort model or its prompts were
  unavailable; the question fell back to a plain search (or to the results found so far), so its
  Effort loop rank is a low-effort result.
- **Every question failed with "query embedding failed".** The embedding model in
  `EMBEDDING_MODEL_NAME` is unreachable or misconfigured.
- **New questions still name the metric.** The server may be running an old prompt: check
  `PROMPT_GENERATE_METRIC_QUESTIONS` (should be `prompt-question-generator-search-metrics-v3.md`)
  in the server's environment.
