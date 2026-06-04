# Metric Wiki Page — Implementation Plan

> **For agentic workers:** Steps use checkbox (`- [ ]`) syntax for tracking.
> Implement task-by-task; run the listed command after each task and commit when
> it is green. TDD where a unit boundary exists; integration-verify the rest.

**Goal:** Give every extracted metric a lazily-generated, cached, Wikipedia-style
page in SemOS Deep Wiki, reached by clicking a Metrics search result.

**Architecture:** A Go handler under `/api/v1/kb` resolves a metric to its
artifact directory, returns a cached page JSON if present, otherwise compiles the
metric's data, calls an LLM to produce the page JSON, saves it, and returns it.
A Svelte `kb-metric-wiki` section renders that JSON through a template; the search
page links Metrics results to it.

**Tech Stack:** Go + Echo (`ChenWeb/server`), PostgreSQL (`kb.*`), the shared LLM
client, Svelte 5 runes + Tailwind 4 (`ChenWeb/web`).

**Source of truth:** [wiki-page-metric-design.md](wiki-page-metric-design.md).

---

## Conventions reused (do not reinvent)

- **Artifact dir:** `resolveRecordArtifactDir(artifactDir, recordID)` in
  `ChenWeb/server/api/kbhandler/summary_record_handler.go:169` already yields
  `ARTIFACT_DIR/<floor(recordID/1000)>/<recordID>`. Reuse it verbatim.
- **Handler scaffolding:** `EchoFactory.NewFromEcho(c, "CWB_KB_<X>_001")` +
  `defer rc.Close()` + `rc.GetLogger()`; `ApiTypes.ProjectDBHandle`;
  `resolveInputTable(db)`. Mirror `summary_record_handler.go`.
- **LLM call:** mirror the model-by-env-name + `ThinkingType="disabled"` pattern
  in `ChenWeb/server/api/doc-processing/extract-metrics.go`. New env var:
  `WIKIPAGE_CREATION_MODEL_NAME`.
- **Route registration:** add to the `/kb/...` block in
  `ChenWeb/server/api/routes.go:289`.
- **Search page wiring:** `KbSearchResultsView`
  (`ChenWeb/web/src/lib/components/home3/kb-search-results-view.svelte`) and the
  section switch in `ChenWeb/web/src/routes/home3/knowledge/+page.svelte`.
- **DB schema changes:** none required for this feature.

---

## File structure

| Action | Path | Responsibility |
|---|---|---|
| Create | `ChenWeb/server/api/kbhandler/metric_wiki_handler.go` | HTTP handler: validate, resolve path, cache-or-generate, return JSON |
| Create | `ChenWeb/server/api/kbhandler/metric_wiki_compile.go` | Compile the metric's source data (kb.metrics row, `.metrics` file, doc meta, chunk summary) into a generation context |
| Create | `ChenWeb/server/api/kbhandler/metric_wiki_generate.go` | Build prompt, call `WIKIPAGE_CREATION_MODEL_NAME`, parse/validate page JSON, single-flight lock, save |
| Create | `ChenWeb/server/api/kbhandler/metric_wiki_handler_test.go` | Unit tests for id parsing, path building, cache hit, validation |
| Modify | `ChenWeb/server/api/routes.go:289` | Register `GET /kb/metrics/:metric_id/wiki` |
| Create | `ChenWeb/web/src/lib/services/metricWikiService.ts` | Frontend fetch wrapper + `MetricWikiPage` type |
| Create | `ChenWeb/web/src/lib/components/home3/metric-wiki-view.svelte` | Template that renders the page JSON (infobox, sections, grounded/background labels, building/error states) |
| Modify | `ChenWeb/web/src/routes/home3/knowledge/+page.svelte` | Add `section=kb-metric-wiki` → render `MetricWikiView` with `metric_id` |
| Modify | `ChenWeb/web/src/lib/components/home3/kb-search-results-view.svelte` | Link Metrics results to `?section=kb-metric-wiki&metric_id=<id>` |

---

## Chunk 1: Backend — identity, path, cache-read

### Task 1: `metric_id` parsing & validation

**Files:**
- Create: `ChenWeb/server/api/kbhandler/metric_wiki_handler.go`
- Test: `ChenWeb/server/api/kbhandler/metric_wiki_handler_test.go`

- [ ] **Step 1: Write failing tests** for a `parseMetricID(s string) (recordID int64, seqno int, err error)` helper.

```go
// metric_id is "<record_id>_<seqno>", seqno >= 1. Never empty.
func TestParseMetricID(t *testing.T) {
    rid, seq, err := parseMetricID("5_3")
    if err != nil || rid != 5 || seq != 3 {
        t.Fatalf("got rid=%d seq=%d err=%v", rid, seq, err)
    }
    for _, bad := range []string{"", "5", "5_", "_3", "5_0", "x_3", "5_3_1"} {
        if _, _, err := parseMetricID(bad); err == nil {
            t.Errorf("expected error for %q", bad)
        }
    }
}
```

- [ ] **Step 2: Run, verify it fails.** `cd ChenWeb && go test ./server/api/kbhandler/ -run TestParseMetricID` → FAIL (undefined).
- [ ] **Step 3: Implement `parseMetricID`** (split on last `_`, both sides positive ints; seqno ≥ 1).
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit** `feat(kb): parse and validate metric_id`.

### Task 2: page file path

- [ ] **Step 1: Failing test** for `metricWikiPath(artifactDir, recordID, metricID, lang)` →
  `ARTIFACT_DIR/<rid/1000>/<rid>/wikipage_metric_<metric_id>.<lang>.json`, building the dir via `resolveRecordArtifactDir`. Default `lang="en"`; reject unknown langs (`en`, `zh-cn` only for now).
- [ ] **Step 2–4:** implement using `resolveRecordArtifactDir`; run.
- [ ] **Step 5: Commit** `feat(kb): metric wiki page path resolver`.

### Task 3: handler skeleton + cache-hit path

**Files:** `metric_wiki_handler.go`, `routes.go:289`

- [ ] **Step 1:** Implement `GetMetricWiki(c echo.Context) error`:
  parse `:metric_id` and `?lang=`; on parse error → 400 (`CWB_KB_MWIKI_010`);
  resolve path; if the file exists, read and return it raw with
  `{"status":true, "page": <json>, "generated": false}`. Missing-but-no-error
  falls through to Chunk 2 (return a `501`/"not generated" placeholder for now so
  the route is testable).
- [ ] **Step 2:** Register `apiGroup.GET("/kb/metrics/:metric_id/wiki", kbhandler.GetMetricWiki)` in `routes.go`.
- [ ] **Step 3:** Test cache-hit by writing a temp file under a temp `ARTIFACT_DIR` and asserting it is returned verbatim.
- [ ] **Step 4: Run** `go build ./server/... && go test ./server/api/kbhandler/ -run TestMetricWiki`.
- [ ] **Step 5: Commit** `feat(kb): GET /kb/metrics/:metric_id/wiki cache-read`.

> **Review gate:** dispatch the plan/code reviewer on Chunk 1 before Chunk 2.

---

## Chunk 2: Backend — compile + generate + single-flight

### Task 4: compile generation context

**Files:** Create `metric_wiki_compile.go`

- [ ] **Step 1:** Define `metricWikiContext` (the model's input) and
  `compileMetricWikiContext(db, recordID, metricID) (metricWikiContext, error)` that gathers:
  - the `kb.metrics` row for `metric_id` (reuse the select shape in `metrics_handler.go:178 fetchMetricByID`, adapted to filter by `metric_id` text);
  - the metric's richer fields from the `.metrics` artifact file in the record dir (match by `metric_id`/source spans) — for `formula_or_definition`, `threshold_or_target`, `measurement_frequency`, etc. not in columns;
  - document metadata from `kb.inputs` (title, filename, type);
  - the source chunk summary via `source_line_spans` (reuse the summary/line-target readers already in `summary_record_handler.go`).
  - **Not found / empty metric → error** (`CWB_KB_MWIKI_020`), per spec.
- [ ] **Step 2:** Unit-test the `.metrics`-file field merge and the not-found error with a temp dir + fake DB shim where practical; otherwise integration-verify in Task 7.
- [ ] **Step 3: Commit** `feat(kb): compile metric wiki generation context`.

### Task 5: generate page JSON via LLM

**Files:** Create `metric_wiki_generate.go`

- [ ] **Step 1:** Define the page JSON struct matching the design schema
  (`title`, `lead`, `infobox{…}`, `definition`, `background`, `how_used`,
  `choosing_values`, `in_this_corpus{…}`, `related_metrics[]`,
  `generated{model,lang,schema_version,source_hash}`). `source_hash` = stable hash
  of the compiled context.
- [ ] **Step 2:** Build the prompt: instruct **English output**, ground in the
  provided data, mark background/usage/value-guidance as model knowledge, and
  **do not guess or hallucinate when unsure** (best-effort). Call the model named
  by `WIKIPAGE_CREATION_MODEL_NAME` with `ThinkingType="disabled"` (mirror
  `extract-metrics.go`). Parse + validate JSON; on malformed output, one retry,
  then error (`CWB_KB_MWIKI_030`).
- [ ] **Step 3:** `saveMetricWikiPage(path, page)` writes atomically
  (temp file + rename) so a concurrent reader never sees a partial file.
- [ ] **Step 4: Commit** `feat(kb): generate metric wiki page JSON`.

### Task 6: single-flight + wire into handler

**Files:** `metric_wiki_handler.go`, `metric_wiki_generate.go`

- [ ] **Step 1:** Add a process-wide single-flight keyed by `<metric_id>:<lang>`
  (`golang.org/x/sync/singleflight` if already vendored, else a `map[string]*sync.Mutex` guarded by a mutex). On cache-miss: acquire, re-check the file (double-checked), compile → generate → save → return with `"generated": true`.
- [ ] **Step 2:** Replace the Chunk-1 `501` placeholder with the real miss path.
- [ ] **Step 3: Test** concurrency: fire N parallel requests for one missing
  metric against a fake generator that counts calls; assert it is invoked once.
- [ ] **Step 4: Commit** `feat(kb): single-flight metric wiki generation`.

### Task 7: integration verify (real env)

- [ ] Build server; with a populated `ARTIFACT_DIR` + DB and `WIKIPAGE_CREATION_MODEL_NAME` set, `curl` `/api/v1/kb/metrics/<rid>_<seq>/wiki` (authed); confirm the JSON is produced, saved at the spec path, and the second call returns `"generated": false`. Record the result in an impl doc.

> **Review gate:** reviewer on Chunk 2 before Chunk 3.

---

## Chunk 3: Frontend — render + link

### Task 8: service + types

**Files:** Create `ChenWeb/web/src/lib/services/metricWikiService.ts`

- [ ] Define `MetricWikiPage` (mirror the JSON) and
  `getMetricWiki(metricId, lang)` calling `/api/v1/kb/metrics/:id/wiki`.
  Surface a distinct "generating" state for the first-hit wait (loading until the
  response resolves). Run `npm exec svelte-check`. Commit.

### Task 9: render view

**Files:** Create `ChenWeb/web/src/lib/components/home3/metric-wiki-view.svelte`

- [ ] Props `{ metricId: string; darkMode: boolean; lang?: string }`. On mount,
  fetch the page; show a **"Building this page…"** skeleton during first-hit
  generation, an error panel on failure, then render: title, infobox sidebar,
  and sections. **Visually distinguish grounded vs. background** sections
  (e.g. a "general background" tag). Reuse the page-scoped encyclopedic theme
  tokens from `deep-wiki`. `svelte-check`; commit.

### Task 10: route section + result link

**Files:** Modify `home3/knowledge/+page.svelte`, `kb-search-results-view.svelte`

- [ ] **Step 1:** In the knowledge route switch, add `section=kb-metric-wiki`:
  read `metric_id` from the URL and render `MetricWikiView`.
- [ ] **Step 2:** In `KbSearchResultsView`, for Metrics-scope results derive
  `metric_id` from the result's `artifact_id` (`<rid>_mtc_<seq>` → `<rid>_<seq>`)
  and link the title to `/home3/knowledge?section=kb-metric-wiki&metric_id=<id>&dark=<0|1>`.
- [ ] **Step 3: Verify** with Playwright (webapp-testing): search → click a Metrics
  result → lands on the wiki page → first hit shows the building state then the
  rendered page; reload returns instantly. `svelte-check`; commit.

> **Review gate:** reviewer on Chunk 3; then finish the branch.

---

## Out of scope (tracked in design doc)

- Cache invalidation / retention (the `source_hash` seed is written now).
- `zh-cn` translation trigger/UX (English generation only in this plan).
- Eager pre-generation during doc processing.

## Open items to confirm during Task 4/5

- Exact `.metrics` file naming in the record dir (`<filename_root>_<parser_name>.metrics`) and how a single metric is located within it.
- Whether `golang.org/x/sync` is already available for `singleflight`.
- Final wording of the generation prompt (draft in Task 5, refine after Task 7).
