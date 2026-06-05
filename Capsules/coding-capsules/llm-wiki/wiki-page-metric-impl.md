# Metric Wiki Page — Implementation

Implementation notes for the per-metric wiki page specified in
[wiki-page-metric-design.md](wiki-page-metric-design.md) and planned in
[wiki-page-metric-plan.md](wiki-page-metric-plan.md). This document records what
was built, where it lives, and the contracts between the pieces.

## Summary

A metric wiki page is a lazily-generated, file-cached, Wikipedia-style page for a
single extracted metric (`metric_id = <record_id>_<seqno>`). The backend resolves
a metric to its artifact directory, returns the cached page JSON if present, and
otherwise compiles the metric's grounded data, asks an LLM to write the prose
sections, assembles the page, saves it, and returns it. The frontend renders that
JSON through a Svelte template and links Metrics search results to it.

```text
Search result (Metrics scope)
  └─ /home3/knowledge?section=kb-metric-wiki&metric_id=<rid>_<seq>
       └─ MetricWikiView → GET /api/v1/kb/metrics/:metric_id/wiki?lang=en
            ├─ cache hit  → saved page JSON (generated:false)
            └─ cache miss → compile → LLM prose → assemble → save → JSON (generated:true)
```

## Files

| Layer | Path | Role |
|---|---|---|
| Handler | `ChenWeb/server/api/kbhandler/metric_wiki_handler.go` | `GetMetricWiki`; id/lang parse, path resolve, cache-read, single-flight miss path |
| Compile | `ChenWeb/server/api/kbhandler/metric_wiki_compile.go` | `compileMetricWikiContext`; kb.metrics row + source-doc metadata + `source_hash` |
| Generate | `ChenWeb/server/api/kbhandler/metric_wiki_generate.go` | Prompt, primary/fallback model load, LLM call, page assembly, atomic save |
| Route reg. | `ChenWeb/server/api/routes.go` | `GET /kb/metrics/:metric_id/wiki` |
| Tests | `ChenWeb/server/api/kbhandler/metric_wiki_handler_test.go`, `metric_wiki_generate_test.go` | 9 unit tests |
| Service | `ChenWeb/web/src/lib/services/metricWikiService.ts` | `getMetricWiki()`, `metricIdFromArtifactId()`, `MetricWiki*` types |
| View | `ChenWeb/web/src/lib/components/home3/metric-wiki-view.svelte` | Renders the page JSON: building/error states, infobox, sections, labels |
| Route (section) | `ChenWeb/web/src/routes/home3/knowledge/+page.svelte` | `section=kb-metric-wiki` → `MetricWikiView` |
| Search link | `ChenWeb/web/src/lib/components/home3/kb-search-results-view.svelte` | `resultHref()` links Metrics results to their wiki page |

## Identity and storage

`metric_id = <record_id>_<seqno>` (seqno ≥ 1), never null — a null/empty/unparsable
value is an error. The page path is fully derivable from `record_id`:

```text
ARTIFACT_DIR/<floor(record_id/1000)>/<record_id>/wikipage_metric_<metric_id>.<lang>.json
```

resolved via the shared `resolveRecordArtifactDir` helper. `<lang>` is `en`
(always generated) or `zh-cn` (translation, not yet wired). `parseMetricID` and
`metricWikiPath` are unit-tested, including 12 malformed-id cases and the
`group_id = floor(record_id/1000)` rule.

## Backend: `GET /api/v1/kb/metrics/:metric_id/wiki`

Sits behind the same `/api/v1/kb` auth (`EchoFactory`, reason-code prefix
`CWB_KB_MWIKI_*`). Flow:

1. Parse `:metric_id` and `?lang=`; bad id → 400 (`_010`); missing `ARTIFACT_DIR`
   → 500 (`_011`); bad lang → 400 (`_012`).
2. **Cache hit** — if the page file exists, return it verbatim as
   `{status:true, generated:false, page:<json>}`.
3. **Cache miss** — acquire a per-`(metric_id, lang)` lock, **double-check** the
   file (a peer may have written it while waiting), then compile → generate →
   atomic-save → return `{status:true, generated:true, page:<json>}`. Compile not
   found → 500 (`_030`); save failure → 500 (`_031`).

**Single-flight:** a process-wide `map[key]*sync.Mutex` serializes generation per
page, so concurrent first-hits collapse into one generation (verified under
`-race` with 8 concurrent requests → generator invoked once).

### Compilation (grounding)

`compileMetricWikiContext` gathers:

- the `kb.metrics` row by `metric_id` (`fetchMetricByMetricID`) — includes the
  rich columns `formula_or_definition`, `threshold_or_target`,
  `measurement_frequency`, value/unit/range, subject, context;
- source-document metadata from `kb.inputs` (`fetchWikiDocMeta`, degrades to empty
  on error so a page can still be produced).

A missing metric is a hard error. `metricWikiSourceHash` (sha256 of the compiled
context) is stored in the page for a future invalidation policy.

### Generation (grounded fields server-side, prose by LLM)

The key design choice: **structured grounded fields are filled server-side**
(infobox value/unit/threshold/frequency/subject, source document, title), and the
**LLM writes only prose** (`lead`, `definition`, `background`, `how_used`,
`choosing_values`, `related_metrics`). This keeps measured values authoritative
and confines model creativity to explanatory text.

- Models resolved from `WIKIPAGE_CREATION_MODEL_NAME` (required) then
  `WIKIPAGE_CREATION_FALLBACK` (optional) via `.models.toml`, reusing the existing
  OpenAI JSON client; thinking disabled, as with the extractors.
- The built-in prompt (overridable by `WIKIPAGE_CREATION_PROMPT` → `prompts/<file>`)
  instructs the model to write **English**, ground in the provided facts, and
  **not guess or hallucinate** — leaving a field empty when unsure (best-effort).
- `lead` must be non-empty; otherwise the next model is tried.
- Pages are saved atomically (temp file + rename).

### Page JSON shape

```jsonc
{
  "metric_id": "5_3",
  "title": "…",
  "lead": "…",
  "infobox": { "value", "unit", "range_type", "threshold_or_target",
               "measurement_frequency", "subject", "confidence" },
  "definition": "…", "background": "…", "how_used": "…", "choosing_values": "…",
  "in_this_corpus": { "source_document": {…}, "source_excerpt": "…", "chunk_summary": "…" },
  "related_metrics": ["…"],
  "generated": { "model", "lang", "schema_version": 1, "source_hash": "sha256:…" }
}
```

## Frontend: `section=kb-metric-wiki`

A new in-knowledge section addressed by
`/home3/knowledge?section=kb-metric-wiki&metric_id=<id>&dark=<0|1>`. It is exempt
from the active-store gate so it renders directly from a search click.

`MetricWikiView` (Svelte 5 runes) fetches the page via `getMetricWiki`, reloading
when `metric_id` changes. States: a **"Building this page…"** spinner during the
first-hit generation, an error panel with retry, then the rendered page — serif
title, a sticky grounded **infobox** sidebar, prose sections, and a
**grounded vs. "general background"** tag on model-knowledge sections. Dark/light
OKLCH theme; the infobox stacks above the body below 760px.

`kb-search-results-view.svelte` gains `resultHref()`: Metrics-scope results link
to their wiki page (deriving `metric_id` from `artifact_id` via
`metricIdFromArtifactId`, `<rid>_mtc_<seq>` → `<rid>_<seq>` — no schema change);
other artifact types keep linking back to the current search.

## Verification

- `go build ./server/...`, `go vet`, and `gofmt` clean.
- 9 unit tests pass (incl. single-flight under `-race`): id parse, path resolve,
  cache hit, bad id, miss-generates-and-saves, single-flight, grounded-field
  assembly, source-hash stability, prose parsing. (The pre-existing
  `TestListSummaryGraphSuccess` failure in the package is unrelated — it fails on
  clean HEAD.)
- `svelte-check` reports zero errors in the changed frontend files; prettier
  applied. (Project-wide pre-existing svelte-check errors are in other files.)
- **Live verification pending an environment:** a real LLM generation
  (server + DB + `.models.toml` + keys) and a Playwright click-through
  (search → Metrics result → building state → rendered page → instant reload).

## Notes / follow-ups

- **Compile sources** — currently the `kb.metrics` row + document metadata. The
  `.metrics`-file enrichment and the source-chunk summary (via `source_line_spans`)
  are not yet wired (intentionally deferred). The rich fields turned out to be real
  `kb.metrics` columns, so the row already carries most of what the design assumed
  would need the `.metrics` file.
- **Cache invalidation / retention** — deferred; `source_hash` is seeded for it.
- **`zh-cn` translation** — only English generation is wired; the path/handler
  already accept a `lang` and store per-language files.
- **`category_paths` in the infobox** — omitted for now (not selected by the
  metric query).

## References

- [wiki-page-metric-rqmt.md](wiki-page-metric-rqmt.md) — requirements
- [wiki-page-metric-design.md](wiki-page-metric-design.md) — design
- [wiki-page-metric-plan.md](wiki-page-metric-plan.md) — implementation plan
- [search-page.md](search-page.md) — search page (entry point)
- [../doc-processor/extract-metrics-spec.md](../doc-processor/extract-metrics-spec.md) — metric extraction & `metric_id`
