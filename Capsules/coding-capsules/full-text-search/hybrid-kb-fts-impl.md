# Hybrid KB FTS Implementation Notes

This note records the first implementation pass for the hybrid Knowledge Base full-text search design.

## What Was Added

- A new partitioned registry table migration:
  - `ChenWeb/project_migrations/20260522000002_add_hybrid_kb_search_registry.sql`
- Registry-backed search endpoints for:
  - summaries
  - topics
  - scene blocks
  - provisions
  - products
- Registry reindex hooks in the doc-processing pipeline for:
  - metrics
  - summaries
  - topics
  - scene blocks
  - provisions
  - products
- A minimal `home3` operator UI:
  - `Tools -> KB Search Lab`

## Key Design Decisions

### 1. Record-Scoped Replace Semantics

Reindexing is idempotent by deleting registry rows for:

- `artifact_type`
- `input_record_id`

and then rebuilding fresh rows from persisted artifacts.

### 2. Mixed Source Model

The current implementation now has table-backed storage for all current artifact families:

- DB-backed artifacts:
  - summaries (`kb.summaries`)
  - topics (`kb.topics`)
  - metrics
  - scene blocks (`kb.scene_objects`)
  - provisions (`kb.provisions`)
  - products (`kb.products`)

For that reason:

- all current artifact families can support both local-table FTS and registry indexing
- summaries and topics still continue writing their artifact files for tree/index/UI compatibility, but they are now also persisted into PostgreSQL tables

### 3. LLM-First Response Shape

The new artifact search endpoints return a normalized envelope with:

- `artifact_type`
- `query`
- `page`
- `page_size`
- `total`
- `applied_filters`
- `results`

Each result is designed to be easy for tool callers to consume.

### 4. Normalized Artifact IDs

The search-facing `artifact_id` is now normalized and no longer reuses source-native ids such as `metric_id` or `prov_id`.

Format:

- `<record_id>_<artifact_type_code>_<seqno>`

Phase 1 codes:

- `sum` for summaries
- `tpc` for topics
- `sbk` for scene blocks
- `mtc` for metrics
- `prv` for provisions
- `prd` for products

Examples:

- `1042_sum_1`
- `1042_mtc_3`
- `1042_prv_5`

This ID is the canonical identifier returned by:

- per-artifact search endpoints
- global `/api/v1/kb/search`
- registry-backed tool responses

Source-native IDs can still remain in source tables, artifact files, or `semantic_payload` for traceability, but they are not the public search identifier.

### 5. Backfill And Reprocessing Notes

Because global search reads from `kb.search_artifacts`, existing DB-backed artifacts needed a backfill after the registry was introduced.

- `20260522000003_backfill_kb_search_registry_db_artifacts.sql` backfills:
  - metrics
  - provisions
  - products
  - scene blocks
- the backfill now generates normalized `artifact_id` values
- live reprocessing uses the same normalized ID convention, so backfilled rows and newly reindexed rows are consistent
- orphaned historical rows whose `input_record_id` no longer exists in `kb.inputs` are skipped during backfill rather than aborting the migration

Summaries and topics now also have table-backed persistence:

- `20260522000004_add_kb_summaries_topics_tables.sql` creates:
  - `kb.summaries`
  - `kb.topics`
- both tables have:
  - `search_document`
  - `search_vector`
  - local GIN indexes
  - refresh triggers for local FTS columns
- the processors now do record-scoped replace into those tables before rebuilding registry rows
- if a summary/topic record still exists only on disk, the reindex path can repopulate the new tables from artifact files on the next reindex

### 6. CJK Query Fallback

PostgreSQL built-in FTS is not reliable for partial Chinese term matching, especially when a field contains mixed Chinese and Latin text such as metric names with symbols or variable suffixes.

To make searches like `平均瞬时日差` work against artifacts whose stored text contains a longer mixed token such as `平均瞬时日差m或平均实走日差M`, the search handlers now use:

- normal PostgreSQL FTS as the primary path
- a CJK-aware substring fallback with `ILIKE` when the query text contains Han, Hiragana, Katakana, or Hangul characters

This fallback is implemented for:

- metric-local search
- registry-backed artifact search

That keeps ordinary FTS ranking for English and token-friendly text while making Chinese partial matches work in the search lab and LLM-facing endpoints.

## Files

### Backend

- `ChenWeb/server/api/kbsearch/registry.go`
- `ChenWeb/server/api/kbhandler/search_common.go`
- `ChenWeb/server/api/kbhandler/search_registry.go`
- `ChenWeb/server/api/kbhandler/summary_search_handler.go`
- `ChenWeb/server/api/doc-processing/search_indexing.go`
- `ChenWeb/server/api/routes.go`

### Frontend

- `ChenWeb/web/src/lib/services/kbArtifactSearch.ts`
- `ChenWeb/web/src/lib/components/home3/kb-search-lab-state.ts`
- `ChenWeb/web/src/lib/components/home3/kb-search-lab-view.svelte`
- `ChenWeb/web/src/lib/components/home3/nav-rail.svelte`
- `ChenWeb/web/src/lib/components/home3/content-panel.svelte`

## Verification Notes

- Targeted Go handler tests passed for:
  - metric search
  - registry helper/search paths
- `doc-processing` package compiled successfully with the new indexing hooks.
- Full frontend `npm run check` is currently noisy because of many unrelated pre-existing errors and warnings elsewhere in the app; the search lab did not introduce a clearly isolated new failure in that run.

## Follow-Up Work

- Add dedicated tests for:
  - summary/topic registry rebuild
  - DB-backed artifact registry rebuild
  - idempotent double-reprocess scenarios
- Decide whether summaries/topics should eventually gain DB-backed canonical tables
- Continue polishing artifact-specific ranking and filters

## References

- Design: `docs/superpowers/specs/2026-05-22-hybrid-kb-fts-design.md`
- Plan: `docs/superpowers/plans/2026-05-22-hybrid-kb-fts-implementation.md`
