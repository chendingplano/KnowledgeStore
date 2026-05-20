# PostgreSQL Metric Search Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship global PostgreSQL-backed metric search for `kb.metrics`, optimized for LLM/tool retrieval and available in the metrics UI.

**Architecture:** Add trigger-backed search columns plus a GIN index on `kb.metrics`, expose a dedicated search endpoint with weighted ranking and semantic filters, and integrate the feature into the metrics page through extracted frontend modules rather than more inline Svelte logic.

**Tech Stack:** Go, Echo, Goose, PostgreSQL FTS, Svelte.

---

## Chunk 1: Backend Search and Indexing

**Files:**
- Modify: `server/cmd/config/config.go`
- Modify: `config.toml`
- Create: `project_migrations/20260522000001_add_kb_metrics_search.sql`
- Create: `server/api/kbhandler/metric_search_handler.go`
- Modify: `server/api/routes.go`
- Test: `server/api/kbhandler/metrics_search_handler_test.go`

- [x] Write the failing backend search-handler tests.
- [x] Verify the tests fail because the handler and response types do not exist yet.
- [x] Add metric-search config defaults and TOML settings.
- [x] Add the migration for `search_document`, `search_vector`, trigger sync, backfill, and GIN index.
- [x] Implement the dedicated metric search handler and query-builder layer.
- [x] Register the new `/api/v1/kb/metrics/search` route.
- [x] Re-run the focused backend search tests and confirm they pass.

## Chunk 2: Frontend Search Modules and UI Wiring

**Files:**
- Create: `web/src/lib/services/kbMetricSearch.ts`
- Create: `web/src/lib/components/home3/kb-metric-search-state.js`
- Create: `web/src/lib/components/home3/kb-metric-search-result.js`
- Modify: `web/src/lib/components/home3/metric-mgmt-view.svelte`
- Test: `web/src/lib/components/home3/kb-metric-search-state.test.js`

- [x] Write the failing frontend search-state test first.
- [x] Verify it fails because the helper module does not exist yet.
- [x] Add the standalone search client and state/result helper modules.
- [x] Wire the metrics view to use the new modules and add global-search UI controls.
- [x] Keep per-record metric browsing intact and route search hits back into the existing metric-selection flow.
- [x] Re-run the frontend search-state test and confirm it passes.

## Chunk 3: Documentation and Verification

**Files:**
- Create: `docs/superpowers/specs/2026-05-22-postgresql-metric-search-design.md`
- Create: `docs/superpowers/plans/2026-05-22-postgresql-metric-search.md`

- [x] Write the design/spec document.
- [x] Write the implementation-plan document.
- [ ] Run formatting on modified Go files.
- [ ] Run focused verification commands for the new backend and frontend search tests.
- [ ] Run a compile-oriented Go check that includes route registration with a workspace-local `GOCACHE`.
- [ ] Record any unrelated pre-existing test failures separately instead of attributing them to this feature.
