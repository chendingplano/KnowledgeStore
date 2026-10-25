# Hybrid KB FTS Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an idempotent, hybrid PostgreSQL full-text search system for Knowledge Base artifacts, with per-artifact search endpoints, LLM-friendly response shapes, and a minimal `home3` test harness.

**Architecture:** Extend artifact-local FTS from the existing metrics implementation to summaries, topics, scene blocks, provisions, and products, while adding a partitioned `kb.search_artifacts` registry as a canonical normalized search surface. Keep indexing record-scoped and idempotent by deleting existing search rows for an `input_record_id` plus artifact type before rebuilding from persisted source artifacts.

**Tech Stack:** Go, Echo, PostgreSQL FTS (`tsvector`, `tsquery`, `ts_headline`, GIN, partitioning), Goose migrations, Svelte.

---

## File Structure

Core backend files likely to change:

- Modify: `ChenWeb/server/api/routes.go`
- Modify: `ChenWeb/server/api/kbhandler/metric_search_handler.go`
- Modify: `ChenWeb/server/api/kbhandler/metrics_search_handler_test.go`
- Modify: `ChenWeb/server/api/kbhandler/summary_record_handler.go`
- Modify: `ChenWeb/server/api/kbhandler/topic_record_handler.go`
- Modify: `ChenWeb/server/api/kbhandler/scene_blocks_handler.go`
- Modify: `ChenWeb/server/api/kbhandler/provision_handlers.go`
- Modify: `ChenWeb/server/api/kbhandler/products_handler.go`
- Modify: `ChenWeb/server/api/doc-processing/generate-summaries-processor.go`
- Modify: `ChenWeb/server/api/doc-processing/generate-topics-processor.go`
- Modify: `ChenWeb/server/api/doc-processing/generate-scene-blocks-processor.go`
- Modify: `ChenWeb/server/api/doc-processing/extract-provisions.go`
- Modify: `ChenWeb/server/api/doc-processing/extract-products.go`

New backend files to create:

- Create: `ChenWeb/server/api/kbhandler/search_common.go`
- Create: `ChenWeb/server/api/kbhandler/search_registry.go`
- Create: `ChenWeb/server/api/kbhandler/search_registry_test.go`
- Create: `ChenWeb/server/api/kbhandler/summary_search_handler.go`
- Create: `ChenWeb/server/api/kbhandler/summary_search_handler_test.go`
- Create: `ChenWeb/server/api/kbhandler/topic_search_handler.go`
- Create: `ChenWeb/server/api/kbhandler/topic_search_handler_test.go`
- Create: `ChenWeb/server/api/kbhandler/scene_block_search_handler.go`
- Create: `ChenWeb/server/api/kbhandler/scene_block_search_handler_test.go`
- Create: `ChenWeb/server/api/kbhandler/provision_search_handler.go`
- Create: `ChenWeb/server/api/kbhandler/provision_search_handler_test.go`
- Create: `ChenWeb/server/api/kbhandler/product_search_handler.go`
- Create: `ChenWeb/server/api/kbhandler/product_search_handler_test.go`
- Create: `ChenWeb/server/api/doc-processing/search_indexing.go`
- Create: `ChenWeb/server/api/doc-processing/search_indexing_test.go`

Likely migration/config files:

- Create: `ChenWeb/server/api/appdatastores/migrations/20260522_hybrid_kb_search.sql`
- Modify: `ChenWeb/server/cmd/config/config.go`
- Modify: `ChenWeb/config.toml`

Minimal `home3` files:

- Modify: `ChenWeb/web/src/lib/components/home3/nav-rail.svelte`
- Modify: `ChenWeb/web/src/lib/components/home3/content-panel.svelte`
- Create: `ChenWeb/web/src/lib/components/home3/kb-search-lab-view.svelte`
- Create: `ChenWeb/web/src/lib/components/home3/kb-search-lab-state.ts`
- Create: `ChenWeb/web/src/lib/services/kbArtifactSearch.ts`

Docs:

- Create: `KnowledgeStore/Capsules/coding-capsules/full-text-search/hybrid-kb-fts-impl.md`

## Cross-Cutting Conventions

### Artifact ID Contract

All registry rows and search responses must use a normalized `artifact_id`:

- format: `<record_id>_<artifact_type_code>_<seqno>`
- examples:
  - `1042_sum_1`
  - `1042_tpc_1`
  - `1042_sbk_7`
  - `1042_mtc_3`
  - `1042_prv_5`
  - `1042_prd_2`

Artifact type codes used in phase 1:

- `sum`
- `tpc`
- `sbk`
- `mtc`
- `prv`
- `prd`

Do not expose source-native identifiers such as `metric_id`, `prov_id`, or `product_rel_id` as the registry/API `artifact_id`. Those values may still be retained in source tables or semantic payloads for traceability.

## Chunk 1: Search Schema And Registry Foundation

### Task 1: Create the migration for registry + artifact-local search support

**Files:**
- Create: `ChenWeb/server/api/appdatastores/migrations/20260522_hybrid_kb_search.sql`
- Reference: `ChenWeb/server/api/kbhandler/extract-metric-handler.go`
- Reference: `ChenWeb/server/api/doc-processing/extract-metrics.go`

- [ ] **Step 1: Write the failing migration test or validation target**

Document the migration acceptance checks in the SQL file header or a paired test note:

- registry table exists
- partitions exist for `summary`, `topic`, `scene_block`, `metric`, `provision`, `product`
- unique key exists on `(artifact_type, artifact_id)`
- `GIN` exists on partition `search_vector`
- btree exists on `input_record_id`

- [ ] **Step 2: Write the migration**

Add SQL for:

- `kb.search_artifacts`
- partition creation
- shared helper functions for safe text flattening if needed
- artifact-local `search_document` / `search_vector` additions for artifact tables that lack them
- indexes for artifact-local search columns where required

- [ ] **Step 3: Make the migration idempotent**

Use `IF NOT EXISTS` checks or guarded DDL patterns so repeated deploy/test runs do not fail.

- [ ] **Step 4: Verify migration structure**

Run the project’s migration verification path or at minimum inspect for:

- valid schema names
- no duplicate partition/index names
- column names matching actual artifact tables

- [ ] **Step 5: Commit**

```bash
git add ChenWeb/server/api/appdatastores/migrations/20260522_hybrid_kb_search.sql
git commit -m "feat: add hybrid kb search schema"
```

### Task 2: Add shared backend search/registry helpers

**Files:**
- Create: `ChenWeb/server/api/kbhandler/search_common.go`
- Create: `ChenWeb/server/api/kbhandler/search_registry.go`
- Create: `ChenWeb/server/api/kbhandler/search_registry_test.go`

- [ ] **Step 1: Write failing tests for registry helper behavior**

Cover:

- delete registry rows by `artifact_type` + `input_record_id`
- insert normalized rows
- duplicate rebuild does not create duplicates
- `artifact_id` follows the normalized `<record_id>_<type>_<seqno>` contract

- [ ] **Step 2: Implement common types**

Add shared structs such as:

```go
type artifactSearchEnvelope struct {
	Status         bool           `json:"status"`
	Query          string         `json:"query"`
	ArtifactType   string         `json:"artifact_type"`
	Page           int            `json:"page"`
	PageSize       int            `json:"page_size"`
	Total          int64          `json:"total"`
	AppliedFilters map[string]any `json:"applied_filters"`
	Results        []any          `json:"results"`
}
```

and shared helpers for:

- query validation
- page parsing
- `input_record_id` parsing
- TS config sanitization

- [ ] **Step 3: Implement registry write helpers**

Create helpers resembling:

```go
func deleteRegistryRowsForRecord(ctx context.Context, db *sql.DB, artifactType string, recordID int64) error
func insertRegistryRows(ctx context.Context, db *sql.DB, rows []registryRow) error
```

- [ ] **Step 4: Run tests**

Run: `go test ./server/api/kbhandler -run 'SearchRegistry|MetricSearch'`

Expected: PASS for new helper tests and no regressions in metric search tests.

- [ ] **Step 5: Commit**

```bash
git add ChenWeb/server/api/kbhandler/search_common.go ChenWeb/server/api/kbhandler/search_registry.go ChenWeb/server/api/kbhandler/search_registry_test.go
git commit -m "feat: add kb search registry helpers"
```

## Chunk 2: Idempotent Indexing Pipeline

### Task 3: Add doc-processing search indexing orchestration

**Files:**
- Create: `ChenWeb/server/api/doc-processing/search_indexing.go`
- Create: `ChenWeb/server/api/doc-processing/search_indexing_test.go`
- Modify: `ChenWeb/server/api/doc-processing/generate-summaries-processor.go`
- Modify: `ChenWeb/server/api/doc-processing/generate-topics-processor.go`
- Modify: `ChenWeb/server/api/doc-processing/generate-scene-blocks-processor.go`
- Modify: `ChenWeb/server/api/doc-processing/extract-provisions.go`
- Modify: `ChenWeb/server/api/doc-processing/extract-products.go`

- [ ] **Step 1: Write failing tests for record-scoped replace behavior**

Cover:

- initial indexing inserts expected rows
- second indexing run for same artifact type and `input_record_id` replaces rather than duplicates
- reduced regenerated artifact set removes stale rows
- generated registry rows use normalized `artifact_id` values rather than source ids

- [ ] **Step 2: Implement indexing entry points**

Create one helper per artifact family, for example:

```go
func ReindexSummarySearchForRecord(ctx context.Context, db *sql.DB, inputRecordID int64) error
func ReindexTopicSearchForRecord(ctx context.Context, db *sql.DB, inputRecordID int64) error
func ReindexSceneBlockSearchForRecord(ctx context.Context, db *sql.DB, inputRecordID int64) error
func ReindexProvisionSearchForRecord(ctx context.Context, db *sql.DB, inputRecordID int64) error
func ReindexProductSearchForRecord(ctx context.Context, db *sql.DB, inputRecordID int64) error
```

Each helper should:

- load persisted source rows
- delete existing registry rows for that record + artifact type
- rebuild normalized rows
- insert fresh registry rows

- [ ] **Step 3: Hook the helpers into successful processor persistence flows**

Call reindex helpers only after the artifact rows have been successfully saved.

- [ ] **Step 4: Add clear logging**

Log:

- artifact type
- `input_record_id`
- deleted row count if easy to capture
- inserted row count
- indexing failures

- [ ] **Step 5: Run tests**

Run: `go test ./server/api/doc-processing -run 'SearchIndexing|Summary|Topic|Scene|Provision|Product'`

Expected: PASS with explicit idempotency coverage.

- [ ] **Step 6: Commit**

```bash
git add ChenWeb/server/api/doc-processing/search_indexing.go ChenWeb/server/api/doc-processing/search_indexing_test.go ChenWeb/server/api/doc-processing/generate-summaries-processor.go ChenWeb/server/api/doc-processing/generate-topics-processor.go ChenWeb/server/api/doc-processing/generate-scene-blocks-processor.go ChenWeb/server/api/doc-processing/extract-provisions.go ChenWeb/server/api/doc-processing/extract-products.go
git commit -m "feat: add idempotent kb search indexing"
```

## Chunk 3: Per-Artifact Search Endpoints

### Task 4: Factor shared endpoint patterns from metric search

**Files:**
- Modify: `ChenWeb/server/api/kbhandler/metric_search_handler.go`
- Modify: `ChenWeb/server/api/kbhandler/metrics_search_handler_test.go`
- Create: `ChenWeb/server/api/kbhandler/summary_search_handler.go`
- Create: `ChenWeb/server/api/kbhandler/topic_search_handler.go`
- Create: `ChenWeb/server/api/kbhandler/scene_block_search_handler.go`
- Create: `ChenWeb/server/api/kbhandler/provision_search_handler.go`
- Create: `ChenWeb/server/api/kbhandler/product_search_handler.go`
- Create: corresponding `*_test.go` files

- [ ] **Step 1: Write failing tests for one new artifact endpoint**

Start with summaries because they are simpler than scene blocks/products.

Test:

- missing `q` rejected
- valid query returns normalized envelope
- `input_record_id` filter works

- [ ] **Step 2: Extract reusable search patterns from metrics**

Move or duplicate safely into shared helpers:

- page parsing
- TS config loading
- common envelope assembly
- snippet option building

- [ ] **Step 3: Implement summary search endpoint**

Add `SearchSummaries(c echo.Context) error`.

- [ ] **Step 4: Implement topic search endpoint**

Add `SearchTopics(c echo.Context) error`.

- [ ] **Step 5: Implement scene block search endpoint**

Add `SearchSceneBlocks(c echo.Context) error`.

- [ ] **Step 6: Implement provision search endpoint**

Add `SearchProvisions(c echo.Context) error`.

- [ ] **Step 7: Implement product search endpoint**

Add `SearchProducts(c echo.Context) error`.

- [ ] **Step 8: Register the routes**

Modify `ChenWeb/server/api/routes.go` to add:

- `/kb/summaries/search`
- `/kb/topics/search`
- `/kb/scene-blocks/search`
- `/kb/provisions/search`
- `/kb/products/search`

- [ ] **Step 9: Run tests**

Run: `go test ./server/api/kbhandler`

Expected: PASS for metric and new artifact search handlers.

- [ ] **Step 10: Commit**

```bash
git add ChenWeb/server/api/routes.go ChenWeb/server/api/kbhandler/metric_search_handler.go ChenWeb/server/api/kbhandler/metrics_search_handler_test.go ChenWeb/server/api/kbhandler/summary_search_handler.go ChenWeb/server/api/kbhandler/summary_search_handler_test.go ChenWeb/server/api/kbhandler/topic_search_handler.go ChenWeb/server/api/kbhandler/topic_search_handler_test.go ChenWeb/server/api/kbhandler/scene_block_search_handler.go ChenWeb/server/api/kbhandler/scene_block_search_handler_test.go ChenWeb/server/api/kbhandler/provision_search_handler.go ChenWeb/server/api/kbhandler/provision_search_handler_test.go ChenWeb/server/api/kbhandler/product_search_handler.go ChenWeb/server/api/kbhandler/product_search_handler_test.go
git commit -m "feat: add per-artifact kb search endpoints"
```

## Chunk 4: Tool-Facing Response Contracts

### Task 5: Normalize LLM-first response payloads

**Files:**
- Modify: `ChenWeb/server/api/kbhandler/metric_search_handler.go`
- Modify: all new artifact search handlers
- Modify: `ChenWeb/server/api/kbhandler/search_common.go`

- [ ] **Step 1: Write failing tests for normalized response fields**

Require every artifact endpoint to return:

- `artifact_type`
- `query`
- `applied_filters`
- `total`
- `results`

Require every result to include:

- `artifact_id`
- `input_record_id`
- `primary_label`
- `snippet`
- `score`

- [ ] **Step 2: Add shared response builders**

Implement helpers that reduce drift across endpoints while allowing artifact-specific payload structs.

- [ ] **Step 3: Add artifact-specific semantic payload fields**

Examples:

- metrics: unit, value class, keywords
- summaries: category path, summary text source
- topics: category path, topic description
- scene blocks: participants, scene role, source spans
- provisions: section/provision identifiers
- products: canonical name, relation type, product type

- [ ] **Step 4: Run tests**

Run: `go test ./server/api/kbhandler -run 'Search'`

- [ ] **Step 5: Commit**

```bash
git add ChenWeb/server/api/kbhandler/search_common.go ChenWeb/server/api/kbhandler/metric_search_handler.go ChenWeb/server/api/kbhandler/summary_search_handler.go ChenWeb/server/api/kbhandler/topic_search_handler.go ChenWeb/server/api/kbhandler/scene_block_search_handler.go ChenWeb/server/api/kbhandler/provision_search_handler.go ChenWeb/server/api/kbhandler/product_search_handler.go
git commit -m "feat: normalize kb search responses for tools"
```

## Chunk 5: Minimal `home3` Search Lab

### Task 6: Build a quick-and-dirty test UI

**Files:**
- Modify: `ChenWeb/web/src/lib/components/home3/nav-rail.svelte`
- Modify: `ChenWeb/web/src/lib/components/home3/content-panel.svelte`
- Create: `ChenWeb/web/src/lib/components/home3/kb-search-lab-view.svelte`
- Create: `ChenWeb/web/src/lib/components/home3/kb-search-lab-state.ts`
- Create: `ChenWeb/web/src/lib/services/kbArtifactSearch.ts`

- [ ] **Step 1: Write a small state/service test if the frontend already follows that pattern**

Cover:

- selected artifact type
- query submission
- response normalization

- [ ] **Step 2: Add a service layer**

Create helpers like:

```ts
export async function searchMetrics(params: SearchParams): Promise<SearchResponse> {}
export async function searchSummaries(params: SearchParams): Promise<SearchResponse> {}
```

- [ ] **Step 3: Build the search lab state**

Track:

- selected artifact type
- query
- `input_record_id`
- loading/error
- results

- [ ] **Step 4: Build the Svelte panel**

Render:

- artifact selector
- query box
- optional record filter
- search button
- result cards with label, score, snippet, and ids

- [ ] **Step 5: Add navigation entry**

Add a `home3` item such as `Tools -> KB Search Lab`.

- [ ] **Step 6: Run frontend checks**

Run the project’s frontend test/build command available in ChenWeb.

Expected: the new panel renders without breaking existing `home3` views.

- [ ] **Step 7: Commit**

```bash
git add ChenWeb/web/src/lib/components/home3/nav-rail.svelte ChenWeb/web/src/lib/components/home3/content-panel.svelte ChenWeb/web/src/lib/components/home3/kb-search-lab-view.svelte ChenWeb/web/src/lib/components/home3/kb-search-lab-state.ts ChenWeb/web/src/lib/services/kbArtifactSearch.ts
git commit -m "feat: add home3 kb search lab"
```

## Chunk 6: Config, Verification, And Documentation

### Task 7: Add configuration and verification coverage

**Files:**
- Modify: `ChenWeb/server/cmd/config/config.go`
- Modify: `ChenWeb/config.toml`

- [ ] **Step 1: Add config sections**

Add artifact search config that can at minimum support:

- dictionary
- default/max page size
- preview length
- phrase-friendly parsing
- minimum rank
- per-artifact weight groups

- [ ] **Step 2: Add defaults compatible with current metric search**

Keep metrics behavior stable while enabling new artifact families.

- [ ] **Step 3: Run backend tests**

Run: `go test ./server/api/...`

Expected: PASS.

- [ ] **Step 4: Run workspace-aware checks if shared code is touched**

If shared dependencies or shared packages are changed:

Run: `go work sync`

Then run:

`go test ./...`

- [ ] **Step 5: Commit**

```bash
git add ChenWeb/server/cmd/config/config.go ChenWeb/config.toml
git commit -m "feat: configure hybrid kb search"
```

### Task 8: Write implementation notes capsule

**Files:**
- Create: `KnowledgeStore/Capsules/coding-capsules/full-text-search/hybrid-kb-fts-impl.md`

- [ ] **Step 1: Write the capsule**

Document:

- schema
- registry pattern
- idempotent indexing rule
- endpoint list
- test harness location
- known follow-up work

- [ ] **Step 2: Verify links to design and plan**

Ensure the capsule points to:

- `docs/superpowers/specs/2026-05-22-hybrid-kb-fts-design.md`
- `docs/superpowers/plans/2026-05-22-hybrid-kb-fts-implementation.md`

- [ ] **Step 3: Commit**

```bash
git add KnowledgeStore/Capsules/coding-capsules/full-text-search/hybrid-kb-fts-impl.md
git commit -m "docs: record hybrid kb fts implementation notes"
```

## Final Verification Checklist

- [ ] migration applies cleanly
- [ ] repeated indexing for the same `input_record_id` is idempotent
- [ ] each artifact family has a working search endpoint
- [ ] each endpoint returns an LLM-friendly normalized response envelope
- [ ] `home3` search lab can exercise all supported artifact families
- [ ] logging clearly identifies indexing failures and rebuilt row counts

Plan complete and saved to `docs/superpowers/plans/2026-05-22-hybrid-kb-fts-implementation.md`. Ready to execute?
