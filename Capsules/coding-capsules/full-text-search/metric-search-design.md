# PostgreSQL Metric Search Design

> **For agentic workers:** This design is paired with `docs/superpowers/plans/2026-05-22-postgresql-metric-search.md` and implements a global, LLM-friendly metric search for `kb.metrics`.

**Goal:** Make extracted metrics searchable across the whole knowledge base using native PostgreSQL full-text search, with a response shape that works well for both humans and agent tools.

**Architecture:** PostgreSQL owns corpus indexing through `search_document` and `search_vector` columns on `kb.metrics`, plus a trigger-backed sync path for inserts and updates. ChenWeb exposes a dedicated `/api/v1/kb/metrics/search` endpoint that applies semantic filters, weighted ranking, and concise snippets, while the metrics UI calls that endpoint through separate frontend search modules instead of growing `metric-mgmt-view.svelte`.

**Tech Stack:** Go, Echo, PostgreSQL FTS (`tsvector`, `tsquery`, GIN), Goose migrations, Svelte.

---

## Design Summary

- Use a dedicated backend handler and query-builder layer under `server/api/kbhandler` for metric search.
- Keep `metric_keywords` and `metric_keywords_en` as the highest-weight ranking fields.
- Store a broad search document and search vector in `kb.metrics`; let ranking weights remain app-configurable in Go.
- Optimize the HTTP response for LLM/tool use by returning ranked hits, primary labels, snippets, semantic fields, and source metadata in one call.
- Integrate global search into the metrics UI without adding more search-specific logic to the already large Svelte file.

## Data Design

- Migration adds:
  - `kb.metrics.search_document TEXT`
  - `kb.metrics.search_vector TSVECTOR`
  - immutable helper functions to flatten JSONB arrays and build the searchable text
  - a trigger that refreshes both search columns on insert/update
  - a one-time backfill for existing rows
  - a GIN index on `search_vector`
- Search document includes:
  - names, subjects, keywords, descriptions, contexts
  - units, value classes, table/section names
  - category paths when present

## API Design

- New endpoint: `GET /api/v1/kb/metrics/search`
- Query params:
  - `q`
  - `page`, `page_size`
  - `input_record_id`
  - `is_explicit_metric`
  - `value_class`
  - `value_data_type`
  - `metric_unit`
- Response returns:
  - query echo
  - pagination
  - applied filters
  - ranked results with `primary_label`, `snippet`, `score`, source ids, and core semantic fields

## Config Design

- New `[metric_search]` section in `config.toml`
- Configurable knobs:
  - dictionary
  - default/max page size
  - preview length
  - phrase-friendly query parsing
  - minimum rank
  - per-field weights, with keywords highest

## UI Design

- Keep the existing per-record metric browsing flow.
- Add a separate global-search panel in the metrics sidebar.
- Extract search request/state/result helpers into separate modules:
  - `web/src/lib/services/kbMetricSearch.ts`
  - `web/src/lib/components/home3/kb-metric-search-state.js`
  - `web/src/lib/components/home3/kb-metric-search-result.js`
- Search results can jump directly to the source record and selected metric.
