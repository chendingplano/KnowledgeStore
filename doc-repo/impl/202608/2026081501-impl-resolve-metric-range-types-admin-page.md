# Resolve Metric Range Types Admin Page Implementation

**Date:** 2026-08-15 \
**Status:** Implemented \
**Component:** ChenWeb — `server/api/kbhandler/metric_range_type_errors_handler.go`,
`server/api/ontology/assertions/metric_normalizer.go`, `server/api/routes.go`,
`project_migrations/20260815000002_add_kb_metrics_range_type_error_index.sql`,
`web/src/lib/components/home3/resolve-metric-range-types-{view.svelte,client.ts}`,
`web/src/lib/components/home3/{nav-rail.svelte,content-panel.svelte}` \
**Authors:** Chen Ding (with Claude)

## Change Logs

* 2026/08/15, document created, at implementation completion.

## Purpose

This document records the implementation completed for the **Resolve Metric Range Types** admin
page — System Admin → Database Maintenance → "Resolve Metric Range Types" in ChenWeb's home3
shell.

It complements:

- ADR `2026081501` — `KnowledgeStore/doc-repo/adrs/202608/2026081501-adr-resolve-metric-range-types-admin-page.md`
  (the decision record; DR1–DR9)
- OpenSpec change — `ChenWeb/openspec/changes/resolve-metric-range-types/` (proposal, design,
  specs, tasks — all 22 tasks complete)

It focuses on:

- how DR1–DR9 map to actual code, file and function
- the full list of files touched, by layer
- what was tested, and what was verified live against the running dev server and database
- what was intentionally left out of scope

## Summary

The page closes the admin-UI gap ADR `2026081401` deferred: an operator can now find `kb.metrics`
rows with an unmapped `value_range_type`, see enough context (including the source PDF) to judge
the correct classification, and fix the underlying `kb.metric_value_range_type_map` entry — with
the fix applying retroactively to every already-flagged row sharing that raw value.

```
kb.metrics rows with value_range_type_error != NULL
  -> Left panel: search (record id / date range / error type) + results list
  -> select a row
      -> Right panel: Information Block (name/desc/context/value/type/range type/error)
      -> Right panel: PDF Display, highlighted via the same raw-line/bbox mechanism
         the existing Metrics page uses (no new storage needed)
  -> Map Block (full width, below): every kb.metric_value_range_type_map entry,
     invalid (status != 'approved') ones first
      -> set/correct canonical_bucket, click Apply
          -> entry saved as status='approved'
          -> in-process governed-lookup cache invalidated immediately
          -> every kb.metrics row with this raw_value AND a set error: error cleared
      -> or add a brand-new raw_value entry (same upsert call)
```

No schema changes were required beyond one new index — both `kb.metrics.value_range_type_error`
and `kb.metric_value_range_type_map` already existed from ADR `2026081401`.

## DR1–DR9 → Implementation

### DR1 — Page placement: nav-gated, no new route, no new middleware

- `web/src/lib/components/home3/nav-rail.svelte:260` — new child
  `{ id: 'sysadmin-db-resolve-metric-range-types', label: 'Resolve Metric Range Types' }` added to
  the existing `sysadmin-db` ("Database Maintenance") group's `children`.
- `web/src/lib/components/home3/content-panel.svelte:158` — added to the `showFooter` exclusion
  list (this page manages its own scroll, like "Resolve Ambiguous Objects").
- `content-panel.svelte:257` — new dispatch branch rendering
  `<ResolveMetricRangeTypesView {darkMode} />` on `activeMenu?.childId ===
  'sysadmin-db-resolve-metric-range-types'`.
- `server/api/routes.go:533-535` — three new routes registered on the existing `apiGroup` (only
  `authmiddleware.AuthMiddleware`), immediately after the other `/kb/metrics/...` routes. No new
  Go middleware, no new Svelte route file.

### DR2 — Layout: Left/Right split + full-width Map Block

`resolve-metric-range-types-view.svelte` — a single page component (628 lines):

- Left panel (`~line 300` onward): search inputs (record ID, date-from, date-to, error-type
  `<select>`) over a results list built from `listMetricRangeTypeErrors`.
- Right panel: an Information Block built from plain field rows (not the `AttrDef`-group pattern
  `metric-mgmt-view.svelte` uses — that pattern was judged unnecessarily heavy for this page's
  seven fixed fields) plus a `PdfViewWindow` instance.
- Map Block: a separate full-width `<div>` below the Left/Right flex row, with its own header,
  results grid, and an "Add New Entry" form at the bottom.

### DR3 — Single upsert endpoint for Apply + Add Entry

`UpsertValueRangeTypeMapEntry` (`metric_range_type_errors_handler.go:265`) — `POST
/api/v1/kb/metric-value-range-type-map`. Validates `raw_value` (normalized via
`assertions.NormalizeValueRangeTypeRaw`, rejects empty) and `canonical_bucket` (rejects empty),
then:

```sql
INSERT INTO kb.metric_value_range_type_map (raw_value, canonical_bucket, status, note, modify_time)
VALUES ($1, $2, 'approved', $3, now())
ON CONFLICT (raw_value) DO UPDATE
   SET canonical_bucket = EXCLUDED.canonical_bucket,
       status = 'approved',
       note = COALESCE(EXCLUDED.note, kb.metric_value_range_type_map.note),
       modify_time = now()
```

The frontend calls this same `upsertValueRangeTypeMapEntry` client function from both the per-row
"Apply" button and the "Add New Entry" form (`resolve-metric-range-types-view.svelte`'s
`applyMapEntry`/`addNewEntry` functions).

### DR4 — New handler, reused `metricRecord` DTO

- `metricRecord` (`server/api/kbhandler/metrics_handler.go`) gained one new optional field,
  `ValueRangeTypeError *string` (`json:"value_range_type_error,omitempty"`) — additive, no existing
  caller affected.
- `ListMetricRangeTypeErrors` (`metric_range_type_errors_handler.go:31`) — `GET
  /api/v1/kb/metrics/range-type-errors`. Builds `WHERE value_range_type_error IS NOT NULL` plus
  optional `input_record_id` / `date_from`/`date_to` (`created_at` range) / `value_range_type`
  conditions, `ORDER BY created_at DESC LIMIT 500`, scanning into `metricRecord`.
- `ListValueRangeTypeMapEntries` (`:203`) — `GET /api/v1/kb/metric-value-range-type-map`, `ORDER BY
  (status <> 'approved') DESC, occurrence_count DESC, raw_value ASC`.
- Frontend "error type" dropdown (`resolve-metric-range-types-view.svelte`'s `errorTypeOptions`
  derived value) is computed client-side from the already-fetched Map Block entries
  (`mapEntries.filter(isInvalidMapEntry)`) — no fourth endpoint added, per DR4's design decision.

### DR5 — Cascade correction via SQL-ported normalization

Inside `UpsertValueRangeTypeMapEntry`, immediately after the upsert:

```sql
UPDATE kb.metrics
   SET value_range_type_error = NULL
 WHERE value_range_type_error IS NOT NULL
   AND lower(regexp_replace(trim(value_range_type), '[- ]', '_', 'g')) = $1
```

`result.RowsAffected()` becomes the response's `corrected_count`. A dedicated equivalence test,
`TestSQLNormalizePredicateAgreesWithGoNormalize`
(`metric_range_type_errors_handler_test.go`), runs a fixture set (empty/whitespace-only, mixed
case, hyphens, spaces, CJK text) through both `assertions.NormalizeValueRangeTypeRaw` and a
Go-side mirror of the SQL regex, asserting agreement — this is a same-process Go comparison, not a
live-Postgres integration test, to avoid the `TEST_DATABASE_URL` risk this workspace has previously
been burned by.

### DR6 — Two small exported functions on `assertions`

`server/api/ontology/assertions/metric_normalizer.go:342-354`:

```go
func InvalidateValueRangeTypeMapCache() {
	defaultValueRangeTypeMapCache.invalidate()
}

func NormalizeValueRangeTypeRaw(raw string) string {
	return normalizeValueRangeTypeRaw(raw)
}
```

Both are thin wrappers around pre-existing unexported functions — zero behavior change for any
existing caller. `UpsertValueRangeTypeMapEntry` calls `InvalidateValueRangeTypeMapCache()` after
the cascade UPDATE succeeds, so the corrected mapping is visible to the next extraction/normalize
run within the same process immediately, not after the pre-existing 30s TTL. New tests:
`TestNormalizeValueRangeTypeRawMatchesUnexported`,
`TestInvalidateValueRangeTypeMapCacheClearsDefaultCache` (`metric_normalizer_test.go`).

### DR7 — `canonical_bucket` combobox

`CANONICAL_BUCKET_OPTIONS = ['lower_bound', 'upper_bound', 'exact', 'range']` (exported constant,
`resolve-metric-range-types-client.ts`) backs a single shared `<datalist
id="rmrt-canonical-bucket-options">` in the view, referenced by both the per-entry
`<input type="text" list="rmrt-canonical-bucket-options">` and the Add-Entry form's bucket input.
Free text is always accepted; the backend only checks non-empty (`UpsertValueRangeTypeMapEntry`'s
`canonicalBucket == ""` check), matching the column's actual DB-level looseness.

### DR8 — Duplicated PDF-highlight logic

`resolve-metric-range-types-view.svelte` ports, without modifying `metric-mgmt-view.svelte`:

- `normalizeSpans` (mirrors `normalizeMetricSpans`) — resolves `source_line_spans` line numbers to
  `{page_number, line_number}` via a `lineNumToPage` map built from `getRawLines`'s response.
- `selectedLinesByPage` / `renderHighlights` (mirrors `renderMetricHighlights`) — scales each
  matched line's `coords` (0–1000 normalized bbox) into the PDF viewport's pixel space and appends
  `.pdf-highlight` overlay `<div>`s, merging contiguous line numbers into one taller box.
- The `:global(.pdf-highlight)` CSS rule is copied into this component's own `<style>` block (the
  class is applied imperatively via `document.createElement`, so it must be defined per-consumer —
  confirmed this is also how `metric-mgmt-view.svelte` itself does it, there being no shared
  stylesheet for it).
- `PdfViewWindow` is used with `showSidebar={false}` and `enableSelectionDialog={false}` — this
  page is read-only viewing, unlike the Metrics page's editable line-selection flow.

### DR9 — One new partial index

`project_migrations/20260815000002_add_kb_metrics_range_type_error_index.sql`:

```sql
CREATE INDEX IF NOT EXISTS idx_kb_metrics_range_type_error
    ON kb.metrics (input_record_id, created_at)
    WHERE value_range_type_error IS NOT NULL;
```

Applied automatically by the running `mise dev`/air dev server on rebuild (workspace convention);
confirmed live via `\d kb.metrics` against the `miner` database post-rebuild (see Verification).

## Files Changed

### Schema

- `project_migrations/20260815000002_add_kb_metrics_range_type_error_index.sql` (new, 12 lines).

### Backend

- `server/api/kbhandler/metric_range_type_errors_handler.go` (new, 345 lines) —
  `ListMetricRangeTypeErrors`, `ListValueRangeTypeMapEntries`, `UpsertValueRangeTypeMapEntry`,
  `valueRangeTypeMapEntryDTO`, shared scan/fetch helpers.
- `server/api/kbhandler/metric_range_type_errors_handler_test.go` (new, 321 lines) — sqlmock-based
  handler tests (see Tests).
- `server/api/kbhandler/metrics_handler.go` (+4 lines) — `metricRecord.ValueRangeTypeError` field.
- `server/api/ontology/assertions/metric_normalizer.go` (+16 lines) —
  `InvalidateValueRangeTypeMapCache`, `NormalizeValueRangeTypeRaw`.
- `server/api/ontology/assertions/metric_normalizer_test.go` (+38 lines) — tests for both new
  exports.
- `server/api/routes.go` (+3 lines) — the three new route registrations.

### Frontend

- `web/src/lib/components/home3/resolve-metric-range-types-client.ts` (new, 124 lines) — typed API
  client (`listMetricRangeTypeErrors`, `listValueRangeTypeMapEntries`,
  `upsertValueRangeTypeMapEntry`), `CANONICAL_BUCKET_OPTIONS`, `isInvalidMapEntry`.
- `web/src/lib/components/home3/resolve-metric-range-types-client.test.ts` (new, 134 lines) —
  `node:test`-based client tests (see Tests).
- `web/src/lib/components/home3/resolve-metric-range-types-view.svelte` (new, 628 lines) — the page
  itself.
- `web/src/lib/components/home3/nav-rail.svelte` (+1 line) — nav entry.
- `web/src/lib/components/home3/content-panel.svelte` (+4 lines) — import, dispatch branch,
  no-footer exclusion.

### Documentation

- ADR `2026081401` — §1 changelog entry + §7 bullet marked resolved, pointing here.
- ADR `2026081501` / this document — the decision record and implementation record for this page.

## Tests

New, by file:

- `metric_normalizer_test.go` — `TestNormalizeValueRangeTypeRawMatchesUnexported`,
  `TestInvalidateValueRangeTypeMapCacheClearsDefaultCache`.
- `metric_range_type_errors_handler_test.go` — `TestListMetricRangeTypeErrorsNoFilters`,
  `TestListMetricRangeTypeErrorsWithFilters`, `TestListMetricRangeTypeErrorsInvalidRecordID`,
  `TestListValueRangeTypeMapEntries`, `TestUpsertValueRangeTypeMapEntrySuccess`,
  `TestUpsertValueRangeTypeMapEntryMissingCanonicalBucket`,
  `TestUpsertValueRangeTypeMapEntryMissingRawValue`,
  `TestSQLNormalizePredicateAgreesWithGoNormalize`.
- `resolve-metric-range-types-client.test.ts` — 9 tests covering `buildRangeTypeErrorsQuery`,
  `listMetricRangeTypeErrors`, `listValueRangeTypeMapEntries`, `upsertValueRangeTypeMapEntry`
  (success + server-error surfacing), `isInvalidMapEntry`.

## Verification

```bash
cd ChenWeb/server && go build ./... && go vet ./... && go test ./...
cd ChenWeb/web && bun run check && bun test src/lib/components/home3/resolve-metric-range-types-client.test.ts
```

Results:

- `go build`/`go vet` clean across the workspace.
- `go test ./...`: all new tests pass; `TestListMetricRangeTypeErrors*`,
  `TestListValueRangeTypeMapEntries`, `TestUpsertValueRangeTypeMapEntry*`,
  `TestSQLNormalizePredicateAgreesWithGoNormalize`,
  `TestNormalizeValueRangeTypeRawMatchesUnexported`,
  `TestInvalidateValueRangeTypeMapCacheClearsDefaultCache` all pass. A handful of pre-existing
  failures elsewhere (`doc-reviews` seed-timing test, `kbhandler`'s `ARTIFACT_WEB_DIR`-dependent
  and topic-category tests, ontology-candidates/search-registry/`llmusage`/`ontology/keywords`
  tests, `qudt-import`) were confirmed unrelated by direct diff inspection — none of those packages
  or files appear in this change's diff, and the three `kbhandler` failures were independently
  reproduced against the pre-session commit. Not fixed here — out of scope.
- `bun run check` (svelte-check): clean for every file this change touched; one pre-existing error
  in an unrelated, untouched test file (`doc-processor-dashboard-state.test.ts`) confirmed
  unrelated the same way.
- `bun test` on the new client test file: 9/9 pass.

### Live verification against the running dev server and database

- `mise dev`/air auto-rebuilt and restarted the server after the Go changes (confirmed via process
  start time); the new migration applied automatically — confirmed via
  `\d kb.metrics` against `miner`:
  `"idx_kb_metrics_range_type_error" btree (input_record_id, created_at) WHERE value_range_type_error IS NOT NULL`.
- `curl http://localhost:8080/api/v1/kb/metric-value-range-type-map` and
  `.../kb/metrics/range-type-errors` both returned `401` (not `404`) with no session cookie —
  confirms both routes are correctly registered and gated by the standard auth middleware exactly
  as designed (DR1), with no extra role check.
- **Not done:** an authenticated browser click-through of the actual page (search, select-record
  PDF-highlight, Apply/Add-Entry flows). No authenticated session was available in this
  environment; this remains a manual verification step before considering the page fully done.

## Documentation Impact

- ADR `2026081401` — §1 gained a 2026/08/15 changelog entry; §7's "no admin UI" bullet marked
  `~~struck~~` and annotated "Resolved 2026-08-15," pointing to this ADR/implementation pair.
- ADR `2026081501` (this implementation's companion) — records the same DR1–DR9 in decision-record
  form.
- No other existing document was found to reference this gap or this table pair besides ADR
  `2026081401` itself.

## Recommended Follow-up

- Decide whether "Apply" should also surface a way to trigger `normalize_assertions`/
  `associate_semantics` reprocessing for the records it just corrected, rather than relying
  entirely on the existing backlog-drain mechanism to eventually pick them up (ADR `2026081501` §5).
- Add real pagination to the Map Block / errored-metrics list if either grows past the current
  500-row cap / current few-dozen-entry scale.
- A "mark ambiguous" action from the Map Block, so operators no longer need direct DB access for
  that one status transition.
- Complete a manual, authenticated click-through of the page in a browser — not done as part of
  this implementation (see Verification).
- Revisit DR8's duplicated PDF-highlight logic for extraction into a shared util if a third admin
  page ever needs the same source-highlighting mechanism.
