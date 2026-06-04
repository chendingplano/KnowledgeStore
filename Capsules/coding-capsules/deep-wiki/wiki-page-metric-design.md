# Wiki Page for Metric — Design

Design for the per-metric wiki page in SemOS Deep Wiki. Derived from the rough
requirements in [wiki-page-metric-rqmt.md](wiki-page-metric-rqmt.md) and the
brainstorming dialogue that resolved the open decisions. This document records
the validated design direction; it is the input to a later implementation plan.

## Goal

Give every extracted metric a Wikipedia-style page (cf.
<https://en.wikipedia.org/wiki/Space_vector_modulation>) that presents
everything the corpus knows about it. Pages are **lazily generated** by an LLM
from compiled internal data (no web search), **cached** as JSON, and **rendered**
to HTML through a template. A page is reached by clicking a Metrics result on the
existing Deep Wiki search page.

## Context

- A *metric* is a quantitative, measurable item extracted by the metrics doc
  processor (see [doc-processor/extract-metrics-spec.md](../doc-processor/extract-metrics-spec.md)).
- Metrics are stored in `kb.metrics` and written to a per-document `.metrics`
  artifact file. The `.metrics` file carries enrichment fields that are not
  `kb.metrics` columns (`formula_or_definition`, `threshold_or_target`,
  `measurement_frequency`, `location_type`, `confidence`, `is_explicit_metric`,
  `reasoning_tags`).
- The Deep Wiki entrance ([+deep-wiki-rqmt.md](+deep-wiki-rqmt.md),
  [deep-wiki-impl.md](deep-wiki-impl.md)) and the search page
  ([search-page.md](search-page.md)) already exist. The search page's documented
  *Future work* — "make result titles link to the most useful artifact detail
  page" — is the integration hook this feature fills for the Metrics scope.

## Identity and storage

A metric is identified by `metric_id = <record_id>_<seqno>` (seqno from 1).
`metric_id` is never null; null/empty/not-found is treated as an error.

Pages are stored at:

```text
ARTIFACT_DIR/<group_id>/<record_id>/wikipage_metric_<metric_id>.<lang>.json
```

where `group_id = floor(record_id / 1000)`. Every path component is derivable
from `record_id` alone, so no extra lookup is needed to locate a page.

`<lang>` is the page language (`en`, `zh-cn`). The English page is always
generated first; other languages are produced by translation on demand.

## Decisions

| Area | Decision |
|---|---|
| Page unit | One page per `metric_id`. |
| Format | LLM emits **JSON**; a template renders the HTML. No raw LLM HTML is served (removes the XSS surface). |
| Grounding | Best-effort. Ground content in the compiled data; the model may add background / usage / value-selection guidance from its own knowledge, but is instructed **not to guess or hallucinate when unsure**. Grounded vs. background sections are labeled. |
| Language | Generate English (`.en.json`) always; translate to `.zh-cn.json` on demand. Filename carries the language. |
| Route | In-knowledge surface: `/home3/knowledge?section=kb-metric-wiki&metric_id=<id>`, consistent with the existing `kb-search` section. |
| First-hit | Generate-then-render: backend builds the full JSON (LLM streamed internally for speed); the UI shows a "building this page…" progress state; the page renders once the JSON is complete and saved. The template always sees a complete JSON object. |
| Invalidation | Postponed. A `source_hash` is seeded into the JSON now so a future retention / regeneration policy can detect staleness without a redesign. |

## Compilation sources

When a page must be generated, the metric's information is compiled from:

- the `kb.metrics` row for `metric_id`;
- the metric's entry in the document's `.metrics` artifact file (for the richer
  enrichment fields not stored as columns);
- document metadata from `kb.inputs`;
- the summary of the source chunk(s) the metric was retrieved from, located via
  `source_line_spans`.

Exact field selection and prompt design are deferred to the implementation plan.

## Page JSON schema (strawman)

Each section is tagged grounded (from corpus) or background (model knowledge,
best-effort, labeled in the rendered page).

```jsonc
{
  "metric_id": "5_3",
  "title": "...",                 // metric_name (+ _en)
  "lead": "...",                  // 1-paragraph summary            [grounded]
  "infobox": {                    // Wikipedia-style sidebar        [grounded]
    "value": "...", "unit": "...", "range_type": "...",
    "threshold_or_target": "...", "measurement_frequency": "...",
    "subject": "...", "category_path": [...], "confidence": 0.0
  },
  "definition": "...",            // formula_or_definition expanded [grounded]
  "background": "...",            // what it is generally    [background, labeled]
  "how_used": "...",              // where/when applied      [background, labeled]
  "choosing_values": "...",       // guidance                [background, labeled]
  "in_this_corpus": {             //                                [grounded, cited]
    "source_document": { },       // kb.inputs metadata
    "source_excerpt": "...",      // from source_line_spans
    "chunk_summary": "..."
  },
  "related_metrics": [ ],         // same category / subject        [grounded]
  "generated": {
    "model": "...", "lang": "en", "schema_version": 1, "source_hash": "..."
  }
}
```

## Backend

A handler under the existing `/api/v1/kb` auth, e.g.:

```text
GET /api/v1/kb/metrics/:metric_id/wiki?lang=<lang>
```

Workflow:

1. Validate `metric_id`; resolve `record_id` / `group_id` / file path.
2. If the cached JSON exists, return it.
3. Otherwise: acquire a single-flight lock for this `metric_id`+`lang`, compile
   the sources, call `WIKIPAGE_CREATION_MODEL_NAME` via the shared LLM client
   (thinking off, like the extractors), save the JSON, release the lock, return.

**Concurrency:** the single-flight lock prevents two simultaneous first-hits from
double-generating the same page.

## Frontend

- A new in-knowledge section `kb-metric-wiki` rendered by the Home3 Knowledge
  route, addressed by `?section=kb-metric-wiki&metric_id=<id>`.
- Fetches the page JSON; shows a "building this page…" progress/skeleton state
  while the first-hit generation runs, then renders the template.
- The Metrics scope in `KbSearchResultsView` links each result to its metric
  wiki page (fulfilling the search page's "detail page" future-work item).

## Prerequisites

1. **Expose `metric_id` in search results.** The documented `KbSearchResponse`
   lists `metric_name`, `input_record_id`, `score` but not `metric_id`. Routing a
   clicked Metrics result requires `metric_id`; if absent, surfacing it from
   `kb.search_artifacts` / the registry handler is a precursor task.
2. **Wire the result link** for the Metrics scope to the new section.

## Configuration

- `WIKIPAGE_CREATION_MODEL_NAME` — model used to generate the page JSON.
- `ARTIFACT_DIR` — existing artifact root (shared with doc artifacts).

## Postponed (tracked)

- Exact source-compilation field selection and the generation prompt.
- Cache invalidation / retention policy (the `source_hash` seed is in place).
- Translation trigger and UX for non-English pages.

## References

- [wiki-page-metric-rqmt.md](wiki-page-metric-rqmt.md) — original requirements
- [+deep-wiki-rqmt.md](+deep-wiki-rqmt.md) — Deep Wiki entrance requirements
- [deep-wiki-impl.md](deep-wiki-impl.md) — Deep Wiki entrance implementation
- [search-page.md](search-page.md) — Deep Wiki search page
- [../doc-processor/extract-metrics-spec.md](../doc-processor/extract-metrics-spec.md) — metrics extraction
