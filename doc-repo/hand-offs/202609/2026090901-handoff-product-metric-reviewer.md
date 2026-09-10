# Handoff — product-metric-reviewer implementation

**As of:** 2026-09-09 · **Phases 1–5 + tasks 6.3–6.4 complete** (36/38) · **committed** (2 jj commits).

## TL;DR

**Backend and frontend are done and committed.** `jj log` (linear):
`opzl` "feat(product-metric-reviewer): backend — schema, profile construction, retrieval,
runs, API" (46 files; migrations + `product-review.local.toml` + prompts +
`server/api/product-reviews/` + `routes.go` + `openspec/changes/.../notes.md` + `tasks.md`)
→ `oyxt` "feat(product-metric-reviewer): frontend — /home3/product-metric-review page"
(6 files; service + test, page + view, `messages/{en,zh-cn}.json`). `main` bookmark is
**not** advanced (left where the prior session's `xsqy`/`kmwn` commits left it).
6.3's knowledge-change note is `openspec/changes/product-metric-reviewer/notes.md`.

**Remaining: only 6.1 (e2e against a real corpus) and 6.2 (full-tree `go test ./...` +
`mise build-server`).** Both need a `Ventilator` document set loaded into `miner` (the dev
DB is near-empty). `go build ./...` + `go vet` + `go test ./api/product-reviews/` (50) +
`bun run build` + `bun test` (7 frontend) are all clean.

- **Backend** (`server/api/product-reviews/`): profile construction
  (propose/ground/expand/aspects), retrieval engine (registry + `metric` adapter, doc
  scoring A/B/C, Path D/E, union/tier/score, caps, determinism), run controller + state
  machine, persistence, coverage+gap report, run diff, 17 Echo handlers wired into
  `server/api/routes.go` after `/kb/products`. `go build ./...` clean, `go vet` clean,
  **50 tests pass**. Migrations **applied + recorded** on `miner` (head `20260909000006`).
- **Frontend**: `web/src/lib/services/productMetricReviewService.ts` (typed client, **7
  tests pass** under `bun test`), `web/src/routes/home3/product-metric-review/+page.svelte`
  + `web/src/lib/components/home3/product-metric-review-view.svelte` (the whole page —
  scope-tree with badges/counts/accept-reject-rename-add-delete + ambiguous flag +
  stale-version banner, results grouped by node with node/tier/path/document/text filters
  and a collapsed `document_scope` group, evidence drawer, report tab with coverage/gaps/
  truncation/diff). Light + dark via a `.pmr-shell` token flip (DM Mono + Manrope, bronze
  accent — matches `ontology-metric-analysis`). i18n: 46 `pmr_*` keys in
  `messages/en.json` + `messages/zh-cn.json`; aspect labels come from the server. `bun run
  build` is clean; `svelte-check` adds no new errors.

Nothing is committed; all work sits on a clean worktree over jj commit `xsqy`. The backend
commit (migrations + package + routes) is ready; Phase 6.2/6.3 gate it.

Read [overview.md](overview.md) first for what the app does; this file is only about
implementation state.

## Where things stand

| Task | State |
|---|---|
| 1.1 migrations: `kb.product_profiles`, `kb.product_profile_nodes` | ✅ written, dry-run ok |
| 1.2 migrations: `kb.product_review_requests`, `kb.product_review_runs` | ✅ written, dry-run ok |
| 1.3 migrations: `kb.product_review_run_documents`, `kb.product_review_results` | ✅ written, dry-run ok |
| 1.4 verify migrations apply against dev DB | ✅ **applied + recorded** — `project_db_migration` head is `...0006` |
| 1.5 `product-review.local.toml` | ✅ written |
| 1.6 `prompt-product-structure-v1.md`, `prompt-product-aspect-mapping-v1.md` | ✅ written |
| 2.1 `product-reviews/` package skeleton (config, models, errors) | ✅ built + tested |
| 2.2 profile + node store (create/read/mutate, version bump, cycle, single-root) | ✅ built + tested |
| 2.3 propose pass (one LLM call, tree parse, BFS budget, `CWB_KB_PMR_011` path) | ✅ built + tested |
| 2.4 ground pass (object_nodes → keyword_concepts → ontology_term_labels, embed once, lexical degrade) | ✅ built + tested |
| 2.5 expand pass (accepted `core:part_of`/`core:component_of` + `kb.products` containment) | ✅ built + tested |
| 2.6 aspect attachment from config (carries `relation_types` + `match_mode` onto node) | ✅ built + tested |
| 2.7 sqlmock tests for 2.2–2.6 | ✅ 22 tests, all green |
| 3.1 artifact-type registry + `metric` adapter, `CWB_KB_PMR_020` | ✅ built + tested |
| 3.2 document scoping Path A (product-record + relation weight) / B (RRF over product,summary,topic) / C (standards boost, never filter) | ✅ built + tested |
| 3.3 Path D (document-first) via adapter | ✅ built + tested |
| 3.4 Path E (direct): `subject_concept_id` equality + RRF over the type partition, no doc restriction | ✅ built + tested |
| 3.5 union/dedupe on `(type,id)` keeping paths, tier by matched node, score fusion, inclusion reason | ✅ built + tested |
| 3.6 per-document + per-run caps, `document_scope` removed first, truncated counts | ✅ built + tested |
| 3.7 determinism (pure `assembleResults`, no LLM in the retrieval path) | ✅ tested |
| 3.8 sqlmock/unit tests for every `product-artifact-retrieval` scenario | ✅ 14 tests, all green |
| 4.1 run controller: pin `profile_version`, state machine, `draft` → `CWB_KB_PMR_030`, failure leaves request re-runnable | ✅ built + tested |
| 4.2 persist scoped-doc set + result rows with provenance; filterable by node/tier/path/doc/type | ✅ built + tested |
| 4.3 report builder: coverage table + gap list + attributed/scoped counts + truncation → `report_json` + `report_md` | ✅ built + tested |
| 4.4 diff vs previous run: added / removed / re-tiered + `profile_version` flag | ✅ built + tested |
| 4.5 17 Echo handlers + route block after `/kb/products` in `routes.go` | ✅ built, compiles |
| 4.6 handler + store tests for every `product-metric-review-runs` scenario | ✅ 12 tests, all green |
| 5.1 `productMetricReviewService.ts` typed client + `productMetricReviewService.test.ts` | ✅ 7 tests, `bun test` green |
| 5.2 `/home3/product-metric-review` route + page shell (4 panes), light + dark | ✅ built |
| 5.3 scope-tree: badges (kind/origin/grounding), per-node counts, accept/reject/rename/add/delete, ambiguous flag, stale-version banner + re-run | ✅ built |
| 5.4 results: group by node, filters (node/tier/path/document/text), score sort, collapsed `document_scope`, empty-state → gap list | ✅ built |
| 5.5 evidence drawer: fields, document #, line spans, inclusion reason, paths, source link | ✅ built |
| 5.6 report tab: coverage table, gap list, truncation, diff vs previous run | ✅ built |
| 5.7 i18n `pmr_*` chrome keys (en + zh-cn) + server aspect labels; service tests | ✅ built |
| 6.x | ⬜ not started |

`tasks.md` checkboxes for 1.1–5.7 are ticked. Backend: **50 Go tests green**. Frontend: **7
`bun test` tests green**, `bun run build` clean.

### Files added (all uncommitted)

```
project_migrations/20260909000004_create_kb_product_profiles.sql
project_migrations/20260909000005_create_kb_product_review_requests_runs.sql
project_migrations/20260909000006_create_kb_product_review_run_documents_results.sql
product-review.local.toml
prompts/prompt-product-structure-v1.md
prompts/prompt-product-aspect-mapping-v1.md
openspec/changes/product-metric-reviewer/tasks.md        (checkboxes only)

server/api/product-reviews/                              (Phase 2 — new package `productreviews`)
  errors.go        CWB_KB_PMR_0xx codes + PMRError
  models.go        Profile / ProfileNode structs, kind/origin/status/grounding consts
  config.go        product-review.local.toml loader, locale resolution, AspectVocabulary()
  util.go          asString/asFloat/asStringSlice, normalizeName, formatVector
  store.go         Store: CreateProfile, LoadNodes, AddNode/UpdateNode/DeleteNode,
                   bumpVersion, wouldCreateCycle, single-root guard
  propose.go       Proposer + JSONExtractor iface, planNodes (BFS + depth/node budget)
  ground.go        Grounder + EmbedFunc, 3-source ordered resolution, embed-once
  expand.go        Expander: accepted structural-assertion + kb.products BFS, source_refs
  aspects.go       Store.AttachAspects (config-derived aspect nodes, origin user_added)
  builder.go       Builder.Build = propose → ground → expand → attach aspects; pkg logger
                   ── Phase 3 (retrieval) ──
  registry.go      ArtifactAdapter iface (ListByDocuments / MatchBySubjectConcept /
                   Project / Partition), registry map, AdapterFor → CWB_KB_PMR_020,
                   ValidateArtifactTypes, init() registers metricAdapter
  metric_adapter.go  metricAdapter over kb.search_artifacts_metric JOIN kb.metrics
  scopenodes.go    ScopeNode (identity keys + concept id + stored embedding),
                   LoadScopeNodes (resolves grounded object names), parseVectorText
  hybrid.go        rrfSearch — lexical + optional pgvector RRF fuse over given
                   kb.search_artifacts partitions (rrfK=60); no LLM
  docscope.go      DocumentScoper.Scope = Path A/B/C → []ScopedDoc (JSON-tagged to
                   the kb.product_review_run_documents columns), capped at max_documents
  retrieve.go      Retriever.Retrieve (Path D + E, gathers pathHits) + pure
                   assembleResults (union/dedupe/tier/score/reason + capPerDocument +
                   capPerRun) → RetrieveResult
                   ── Phase 4 (runs, report, API) ──
  run_store.go     RunStore: CreateRequest (pins profile_version), CreateRun (next
                   run_number), MarkRunning/CompleteRun/FailRun, SaveScopedDocs /
                   SaveResults (replace-then-insert in a txn), LoadResults(filters),
                   LoadScopedDocs, PreviousRun, ListRuns/ListRequests
  run_controller.go  RunController.StartReview / Rerun / executeRun (running →
                   completed|failed) / DiffAgainstPrevious; re-run re-pins the
                   request to the profile's current version
  report.go        BuildReport (coverage + gaps + counts, pure) + RenderReportMarkdown
  diff.go          DiffResults (added/removed/retiered + profile_version flag, pure)
  handler.go       17 Echo handlers + newStore/newRunController/newBuilder wiring
                   (newBuilder wires the real LLM client via
                   docprocessing.BuildReviewerLLMClient + docprocessing.LoadPromptByRef
                   + docprocessing.EmbedSearchQuery)
  *_test.go        18 test files, 50 sqlmock/unit tests total
```

`server/api/routes.go` — import `productreviews` + a route block after
`apiGroup.GET("/kb/products", …)`:
`POST/GET /kb/product-profiles`, `…/:id`, `…/:id/build`, `…/:id/ready`,
`…/:id/nodes`, `PATCH/DELETE …/:id/nodes/:node_id`;
`GET /kb/product-reviews/aspects` (`?lang=`), `POST/GET /kb/product-reviews`,
`GET/POST /kb/product-reviews/:id[/rerun]`,
`GET /kb/product-reviews/runs/:run_id[/results|/documents|/diff|/export]`.

### Schema shape (as built)

- **`kb.product_profiles`** — `id` (BIGSERIAL, *is* the profile id — no opaque TEXT id),
  `tenant_id`, `name`, `product_description`, `version`, `status` (`draft`|`ready`),
  `truncated`/`truncated_count`, timestamps.
- **`kb.product_profile_nodes`** — `profile_id` FK, `parent_node_id` self-FK (null for the
  `product` root and root-attached `aspect` nodes), `node_kind`
  (`product`|`module`|`part`|`aspect`), `label`/`label_en`/`aliases`, `depth`, `origin`
  (`llm_proposed`|`graph_expanded`|`user_added`), `status`
  (`proposed`|`accepted`|`rejected`), `confidence`, `rationale`,
  `object_id`/`concept_id`/`term_id` (plain TEXT, **no FK**), `grounding`
  (`object_node`|`keyword_concept`|`ontology_term`|`ungrounded`), `reconcile_status`,
  `aspect_key`, `relation_types` (JSONB), `match_mode`, `embedding vector(1536)`,
  `source_refs` (JSONB).
- **`kb.product_review_requests`** — `profile_id` FK + `profile_version` (pinned),
  `artifact_types` JSONB (default `["metric"]`), `filters`, `notes`, `requester`.
- **`kb.product_review_runs`** — `request_id` FK, `run_number`, `status`
  (`pending`|`running`|`completed`|`failed`), `started_at`/`finished_at`, count columns
  (`result_count`, `attributed_count`, `document_scope_count`, `scoped_document_count`,
  `truncated_count`), `report_json` + `report_md`, `error_message`.
  `UNIQUE (request_id, run_number)`.
- **`kb.product_review_run_documents`** — `run_id` FK, `input_record_id`, `fused_score`,
  `matching_node_ids`, `matching_paths`, `match_reasons`, `doc_kind`.
  `UNIQUE (run_id, input_record_id)`.
- **`kb.product_review_results`** — `run_id` FK, `artifact_type` + `artifact_id`
  (`UNIQUE (run_id, artifact_type, artifact_id)`), `source_row_id`, `input_record_id`,
  `node_id` (plain BIGINT, **no FK**, null for `document_scope`), `tier`
  (`direct`|`part`|`aspect`|`document_scope`), `score`, `paths`, `inclusion_reason`,
  `source_line_spans`. Indexed for the node/tier/path/document/type filters and score sort.

## Phase 2 — as built (notes for the next author)

- **`project_db_migration` is now at `...0006`.** The three migrations were applied by hand
  via `psql` (Up blocks only) and their `(version_id, is_applied)` rows inserted, so the
  server migrator sees them as done and its idempotent `CREATE TABLE IF NOT EXISTS` re-run
  on next rebuild is a no-op. All six `kb.product_*` tables exist in `miner`.
- **No dependency on `doc-processing`.** Phase 2 defines a local `JSONExtractor` interface
  (`ExtractJSON(ctx, llmclients.JSONExtractionInput) (map[string]any, error)`) and a local
  `EmbedFunc`. Phase 4's handler wires the real client via
  `docprocessing.BuildReviewerLLMClient(cfg.Models.Structure)` and an embedder from the
  `kbhandler` `computeQueryEmbedding` pattern (`search_embedding_query.go`).
- **Version-bump discipline:** `Propose`, `AddNode`, `UpdateNode`, `DeleteNode`,
  `AttachAspects`, and `Expand` (only when it inserts) bump `version`. **`Ground` never
  bumps** — grounding refs are not a node-set change, so a run's node set stays stable
  across a re-ground. Keep this when adding curation endpoints.
- **`Grounder.Ground` uses `g.DB` directly, not a txn** (per-node UPDATEs are independent
  and idempotent). `Expand` *is* one txn. `Propose` is one txn (all-or-nothing).
- **Grounding source #3 is `kb.ontology_term_labels`** (matched on `label`, any
  non-rejected role), *not* `kb.ontology_terms` — that table has no label column.
- **`kb.object_nodes.reconcile_status` CHECK only allows** `active|merged|pending_review|
  rejected` — there is no literal `ambiguous` value in that table. `Grounder` copies
  whatever string is on the row into the node and `ProfileNode.NeedsReconcileReview()`
  treats `{ambiguous, pending_review}` as "flag for review", so the spec's `ambiguous`
  scenario still works if the corpus ever uses it.
- **`planNodes`** (propose.go) is the pure BFS budgeter: dedupes paths, drops
  `depth > max_depth` (not counted as truncation), stable-sorts by path length, caps at
  `max_nodes`, returns `(kept, discardedCount)`. Orphans (child whose parent path was
  dropped/never emitted) are skipped, not re-parented.
- **`config.aspectOrder`** is recovered by scanning `[aspects.<key>]` headers in the raw
  TOML (go-toml unmarshals a table to an unordered map) — same trick as
  `doc-reviews/review-config.go` `packageOrderFromTOML`.

## Phase 3 — as built (notes for the next author)

- **Retrieval calls no LLM and no embedder.** The vector half of every hybrid query uses
  the node label embedding **already stored on `kb.product_profile_nodes.embedding`** by
  the Phase 2 grounding pass (`LoadScopeNodes` reads it via `embedding::text` →
  `parseVectorText`). When a node has no stored embedding (grounding ran with semantic
  search off), that node's hybrid search degrades to lexical-only. This is what makes
  Requirement-06 (determinism) hold for free.
- **The dev corpus is currently near-empty** (`kb.products` 0 rows, `kb.metrics` 56,
  `kb.doc_facet_values` has no `document.doc_kind` rows, 6551 orphaned
  `kb.search_artifacts_metric` rows whose source metrics were re-extracted). So Phase 3 is
  **unit-tested only** (sqlmock + pure-function). The real end-to-end lives in task 6.1 and
  needs a `Ventilator` corpus loaded first.
- **`metricAdapter` keys on `kb.search_artifacts_metric` INNER JOIN `kb.metrics`** (join on
  `m.id = sa.source_row_id`) — the join drops the orphaned search rows automatically. No
  seq recomputation: `sa.artifact_id` is authoritative.
- **`assembleResults` in `retrieve.go` is the pure core** — union on `(type,id)`, node
  attribution (concept equality ∪ normalized-subject match ∪ hybrid anchor node), tier by
  highest-precedence matched node (`direct`>`part`>`aspect`>`document_scope`), score =
  raw path scores + `tierBonus` (keeps attributed above scoped in the final sort),
  `capPerDocument` then `capPerRun` (both drop `document_scope` before attributed). Test it
  directly with `pathHit` fixtures — most of `retrieve_test.go` needs no DB.
- **`DocumentScoper.pathA`** matches `kb.products` by `lower(canonical_name)` /
  `canonical_name_en` against the union of every node's normalized name keys (grounded
  nodes also contribute their `kb.object_nodes` canonical + `normalized_names`). Aspect
  nodes with `relation_types` scope a doc when the row identity is the **root** and
  `relation_type ∈ aspect.RelationTypes`. Aspect nodes are skipped in Path B unless they
  are lexical-mode (`len(RelationTypes)==0`).
- **`ScopedDoc` JSON tags already match the `kb.product_review_run_documents` columns**
  (`matching_node_ids`, `matching_paths`, `match_reasons`, `fused_score`, `doc_kind`) —
  Phase 4.2 just marshals. Same for `Result` → `kb.product_review_results`.
- `rrfSearch` (`hybrid.go`) is self-contained (own `rrfK=60`, `hybridCandidateLimit=200`);
  it does **not** reuse the handler-private `queryHybridSearchResults` — that one is tangled
  with `appconfig` dictionary/phrase settings. Uses the `'simple'` tsconfig.

## Phase 4 — as built (notes for the next author)

- **`profile_version` is pinned on the request, not the run** (the schema has no per-run
  version column). `RunController.Rerun` **re-pins** `request.profile_version` to the
  profile's current version, and every run stashes the version it executed against in
  `report_json.profile_version`. `DiffAgainstPrevious` reads both runs' `report_json`
  versions — that is how "Diff flags a profile change" works despite the shared column.
- **`newBuilder()` (handler.go) is the only place the real LLM client + embedder are
  wired** — `docprocessing.BuildReviewerLLMClient(cfg.Models.Structure)` (satisfies the
  local `JSONExtractor`), `docprocessing.LoadPromptByRef("prompt-product-structure-v1.md")`,
  and `docprocessing.EmbedSearchQuery` (an **exported** `func(ctx,string)([]float64,bool)`
  in `api/doc-processing/search_indexing_embedding.go:172` — assignable straight to
  `productreviews.EmbedFunc`), gated by `kbsearch.SemanticSearchEnabled()`.
- **The run executes inline in the request handler** (`CreateProductReview` calls
  `StartReview` synchronously). doc-review does this async via JetStream; product-review
  runs are cheap (pure SQL, no LLM) so inline is fine for v1. If runs get slow with a real
  corpus, move `executeRun` behind a goroutine / JetStream like `docreviews.SubmitRequest`.
- **`fail()` in handler.go maps errors → HTTP**: `*PMRError` → 422 with `error_code`;
  `ErrCycle`/`ErrMultipleRoots`/`ErrNodeNotFound` → 422; else 500.
- **`SaveScopedDocs` / `SaveResults` are replace-then-insert** (DELETE by run_id, then
  per-row INSERT, one txn) so a re-execute of the same run id is idempotent. The UNIQUE
  constraints (`run_id,input_record_id` / `run_id,artifact_type,artifact_id`) are belt-and-
  braces.
- **`LoadResults` filter `path`** uses the JSONB `?` containment operator on the `paths`
  array; `exclude_tier` is a comma list → repeated `tier <> $n`.
- **`assembleResults` sets one representative `NodeID` per result** (the winning-tier
  node). `BuildReport` counts coverage by `Result.NodeID == node.id`, so a metric that also
  weakly matched other nodes only counts for its winning node. Good enough for v1; revisit
  if per-node recall reporting needs the full match set.

## Phase 5 — as built (notes for the next author)

- **The whole page is one view component** — `web/src/lib/components/home3/
  product-metric-review-view.svelte` (~900 lines, Svelte 5 runes) — rendered by a thin
  `+page.svelte` that passes `darkMode` (from `?dark=` or the `theme` store, same contract
  as `/home3/metrics`). Not registered in `nav-rail.svelte`; reachable directly at
  `/home3/product-metric-review?run=<id>`.
- **Entry is `?run=<id>`.** The component loads `getRun` → `getReview(request_id)` (for
  `profile_id` + pinned `profile_version`) → `getProfile` (nodes + current version) →
  `getRunResults` / `getRunDocuments` / `getRunDiff` in parallel. No run picker (out of
  scope); an id field is shown when `?run` is absent.
- **`report_json` is the source of truth for coverage + gaps** (not recomputed client-side).
  Per-node artifact counts on the tree come from `report_json.coverage`.
- **Styling matches `ontology-metric-analysis`**: DM Mono + Manrope from Google Fonts, an
  oklch paper/ink/bronze light palette + a `#111827/#182334/#ff9b54` dark palette, flipped
  by `.pmr-shell` / `.pmr-shell.dark` — driven by the `darkMode` prop, **not** the global
  `.dark` class (these standalone data apps own their theme).
- **i18n**: 46 `pmr_*` keys added to `messages/en.json` + `messages/zh-cn.json` (baseLocale
  is `zh-cn`). `m.pmr_*()` for chrome; aspect labels come from
  `GET /kb/product-reviews/aspects?lang=` (the service's `listAspects`). Run
  `bunx @inlang/paraglide-js compile --project ./project.inlang --outdir ./src/lib/paraglide`
  after editing messages (or just `bun run build`, which runs the vite plugin).
- **Tests**: `productMetricReviewService.test.ts` in the house `node:test` + `fetch`-stub
  style, run with **`bun test`** (`node --test` can't resolve the extensionless imports).
  There is **no Svelte component-render test infra** in this repo (no vitest /
  @testing-library) — 5.7's "component tests" are covered as service + URL-serialization
  tests; a full render harness would be new infra.
- **Known v1 gaps** (small, not blocking): the evidence drawer shows the document *number*
  (`#<record_id>`) not its *title* — the results / scoped-doc payloads don't carry it; the
  source link goes to `/home3/knowledge?section=kb-input-details&record_id=…`, not deep-
  linked to the cited line. Add a title to `ResultRow`/`ScopedDocument` server-side (join
  `kb.inputs`) if the drawer needs it.

## How to pick up — Phase 6 (verification + docs + commit)

- **6.1 e2e** — needs a real corpus in `miner` first (`kb.products`, `kb.metrics`,
  `kb.doc_facet_values` for `document.doc_kind` are all near-empty today). Load a
  `Ventilator` document set, `POST /kb/product-profiles {name:"Ventilator"}`,
  `POST …/:id/build`, curate + `POST …/:id/ready`, `POST /kb/product-reviews {profile_id}`,
  then confirm a part-attributed metric (e.g. a display/battery metric), an aspect-attributed
  metric, and a populated gap list.
- **6.2** — `go test ./...` in `ChenWeb/server` (whole tree, not just the package),
  `mise build-server`, `bun run build` in `web/` — all already clean for the package /
  frontend; run the full server suite to be sure nothing else regressed.
- **6.3** — the knowledge-change note (workspace `CLAUDE.md` "Coding Best Practice"): what
  the app assumes about `kb.products.relation_type` and `kb.metrics.subject_concept_id`
  (sparse — 0 rows today), which docs are now stale, what was left undocumented. Format:
  the sibling `analysis-node-related-metrics/notes.md`.
- **6.4** — two `jj` commits: (1) migrations + `product-review.local.toml` + prompts +
  `server/api/product-reviews/` + `server/api/routes.go`; (2)
  `web/src/lib/services/productMetricReviewService*.ts` +
  `web/src/routes/home3/product-metric-review/` +
  `web/src/lib/components/home3/product-metric-review-view.svelte` + `messages/*.json`.
  Confirm `jj log` stays linear.

Backend endpoints available now (all under `/api/v1`):
`POST /kb/product-profiles` · `GET /kb/product-profiles/:id` (profile + nodes) ·
`POST /kb/product-profiles/:id/build` · `POST /kb/product-profiles/:id/ready` ·
`POST /kb/product-profiles/:id/nodes` · `PATCH|DELETE /kb/product-profiles/:id/nodes/:node_id` ·
`GET /kb/product-reviews/aspects?lang=` · `POST|GET /kb/product-reviews` ·
`GET /kb/product-reviews/:id` (request + runs) · `POST /kb/product-reviews/:id/rerun` ·
`GET /kb/product-reviews/runs/:run_id` (run + `report_json`/`report_md`) ·
`GET …/runs/:run_id/results?node_id=&tier=&exclude_tier=&path=&input_record_id=&artifact_type=` ·
`GET …/runs/:run_id/documents` · `GET …/runs/:run_id/diff` · `GET …/runs/:run_id/export` (CSV).

Reference — patterns already used by the backend:

| Need | Where |
|---|---|
| Echo handler style, `EchoFactory.NewFromEcho`, `ApiTypes.ProjectDBHandle` | `api/kbhandler/metric_graph_handler.go`; `productreviews/handler.go` now follows it |
| Config + aspect vocabulary | `productreviews.GetConfig()` + `Config.AspectVocabulary(lang)` → `[]AspectEntry` |
| Error codes | `errors.go`: `CWB_KB_PMR_010` cycle · `011` proposal-call · `020` unregistered type · `030` draft profile |

`kb.products.relation_type` real vocabulary (from `prompts/prompt-enrich-product-relations-v1.md`):
`scope`, `regulated_object`, `requirement_target`, `performance_requirement`,
`design_requirement`, `material_requirement`, `testing_requirement`,
`certification_requirement`, `usage_condition`, `installation_requirement`,
`maintenance_requirement`, `storage_requirement`, `prohibited_product`, `exempted_product`,
`component_of`, `contains_product`, `compatible_with`, `replacement_or_alternative`,
`measurement_object`, `risk_source`, `other`.

## Decisions already made (don't re-litigate without reason)

1. **Profile id = BIGSERIAL `id`**, no opaque TEXT id. Runs pin `(profile_id, profile_version)`.
2. **`object_id`/`concept_id`/`term_id` on nodes: plain TEXT, no FK** — per design, scope
   nodes are app-local and only *reference* governed rows; an upstream merge/delete must not
   cascade into a curated profile. Partial indexes (`WHERE ... IS NOT NULL`).
3. **`product_review_results.node_id`: plain BIGINT, no FK** — `document_scope` rows have
   none; a later node delete must not disturb a finished run. Risk: a hard-deleted node
   leaves a dangling id (the `inclusion_reason` text still names it). If Phase 4 needs it,
   add a `matched_node_label` snapshot column.
4. **Aspect `relation_types` + `match_mode` live on the node**, not re-resolved from config
   at query time (spec: "the storage node records that mapping for retrieval").
5. **No run-node snapshot table.** The 6-table list has none; "a completed run's node set
   doesn't change" is honored by pinning `profile_version` and by curation being
   status-changes not row-rewrites. Revisit only if hard-delete of nodes proves common.
6. Migrations keep `object_id` etc. FK-free on purpose — see #2. `run_id`/`request_id`/
   `profile_id` FKs *are* present (same schema, same migration set, `ON DELETE CASCADE`).

## Open / needs tuning

- **Every number in `product-review.local.toml` is a placeholder**: `object_embedding_min
  = 0.82`, `concept_label_min`/`ontology_label_min = 0.90`, `standards_boost = 0.25`,
  `max_depth = 3`, `max_nodes = 200`, `max_documents = 400`, `max_results = 2000`,
  `per_document_cap = 60`, and all `relation_type_weights`. Tune against the real corpus in
  task 6.1 (`Ventilator`).
- **`testing` aspect added** beyond design D3's list of 8 (because `testing_requirement` is a
  real relation type). Drop it if unwanted.
- **`transport`, `packaging`, `disposal`, `emc` → `match_mode = "lexical"`** because the
  real `relation_type` enum has no matching value. `prompt-product-aspect-mapping-v1.md`
  exists for the case where someone adds an aspect whose mapping isn't obvious.
- **Prompt output schemas** in the two prompt files are a first cut — the propose-pass
  parser (task 2.3) and its tests will firm them up. `prompt-product-structure-v1.md` uses a
  `path` array (label path from the product root) to express hierarchy.

## Environment & gotchas

- **Dev DB:** `miner` on `127.0.0.1:5432`, user `admin` (creds in `mise.local.toml` /
  `.env`). Migration version table: **`project_db_migration`**. Schema: `kb`.
- ⚠️ **Never point `TEST_DATABASE_URL` at `miner`** — some tests unconditionally wipe
  `module_id='quantity'` rows. Tests use `chenweb_test`.
- **Migrations auto-apply** on `mise dev` / `mise build-server` rebuild (air hot-reload).
  No standalone `goose` binary.
- **Build / test:** `mise build-server`; `go test ./api/product-reviews/` from `ChenWeb/server`
  (full `go build ./...` also clean as of Phase 2).
- **Config + prompts** are loaded by `productreviews.GetConfig()` (walks up for
  `product-review.local.toml`, env override `PRODUCT_REVIEW_CONFIG_FILE`) and by
  `docprocessing.LoadPromptByRef("prompt-product-structure-v1.md")`. Not yet called by any
  handler — that is Phase 4.5.
- `vector` extension and `kb.object_nodes` / `kb.keyword_concepts` / `kb.products` /
  `kb.semantic_assertions` / `kb.ontology_term_labels` all confirmed present in `miner`.

## Commit plan (task 6.4)

Worktree is clean apart from this work. Earlier this session, `overview.md` was committed
path-scoped as `kmwn` ("docs(product-metric-reviewer): add plain-language overview"); the
unrelated WIP was then committed by the user as `xsqy`.

Task 6.4 wants **migrations + backend as one commit, frontend as another**. The backend
commit is everything under `project_migrations/2026090900000[4-6]*.sql`,
`product-review.local.toml`, `prompts/prompt-product-*-v1.md`,
`server/api/product-reviews/`, and the `server/api/routes.go` diff. The frontend commit is
`web/src/lib/services/productMetricReviewService*.ts`,
`web/src/routes/home3/product-metric-review/`,
`web/src/lib/components/home3/product-metric-review-view.svelte`, and the
`web/messages/*.json` diff. Path-scope each (`jj commit <paths> -m …`) and keep `jj log`
linear. Also ship `openspec/changes/product-metric-reviewer/tasks.md` (checkbox-only) with
whichever commit — or its own.

## Remaining roadmap

- **Phase 2 (2.1–2.7)** — ✅ done. `product-reviews/` package, profile/node store, propose /
  ground / expand passes, aspect attachment, 22 sqlmock tests.
- **Phase 3 (3.1–3.8)** — ✅ done. Artifact-type registry + `metric` adapter, document
  scoring (Paths A/B/C), Path D + Path E retrieval, union/dedupe/tier/score, caps,
  determinism; 14 more tests (36 total).
- **Phase 4 (4.1–4.6)** — ✅ done. Run controller + state machine, result/scoped-doc
  persistence, coverage+gap report builder, run diff, 17 Echo handlers + route block in
  `server/api/routes.go` after `/kb/products`; 14 more tests (50 total).
- **Phase 5 (5.1–5.7)** — ✅ done. `productMetricReviewService.ts` (+ 7 `bun test` tests),
  the `/home3/product-metric-review` page (one `product-metric-review-view.svelte` view:
  scope-tree, results, evidence drawer, report tab), 46 `pmr_*` i18n keys (en + zh-cn).
  `bun run build` clean.
- **Phase 6 (6.1–6.4)** — e2e against a loaded `Ventilator` corpus (dev DB is empty — load
  documents first), full `go test ./...` + `mise build-server` + `bun run build` clean,
  record the knowledge change (CLAUDE.md "Coding Best Practice" — see the sibling
  `analysis-node-related-metrics/notes.md` for the format), then the two `jj` commits.
