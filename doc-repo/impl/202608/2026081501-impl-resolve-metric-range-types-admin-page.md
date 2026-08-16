# Resolve Metric Range Types Admin Page Implementation

**Date:** 2026-08-15 \
**Status:** Implemented \
**Component:** ChenWeb — `server/api/kbhandler/metric_range_type_errors_handler.go`,
`server/api/ontology/assertions/metric_normalizer.go`, `server/api/routes.go`,
`project_migrations/20260815000002_add_kb_metrics_range_type_error_index.sql`,
`web/src/lib/components/home3/resolve-metric-range-types-{view.svelte,client.ts,shelf-store.svelte.ts}`,
`web/src/lib/components/home3/{nav-rail.svelte,content-panel.svelte,context-shelf.svelte}` \
**Authors:** Chen Ding (with Claude)

## Change Logs

* 2026/08/15, document created, at implementation completion.
* 2026/08/15, DR10 added: the requester's first live click-through found the results list not
  stretching to match the Right panel, and the Map Block unreachable behind a multi-page PDF.
  Root-caused to a missing `height:100%; overflow:hidden` layout chain and fixed same day,
  alongside relocating the Map Block to the Context Info shelf. See DR10 below.
* 2026/08/15, DR11 added: a second live click-through found that clicking a metric neither moved
  the PDF to the matching page nor highlighted it, and the PDF panel flashed/reloaded on every
  click. Root-caused to `selectRow` unconditionally refetching and remounting `PdfViewWindow` on
  every row click; fixed same day by porting `metric-mgmt-view.svelte`'s same-record navigation
  pattern. See DR11 below.

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
     (stretches to match the Right panel's height — DR10)
  -> select a row
      -> Right panel: Information Block (name/desc/context/value/type/range type/error)
      -> Right panel: PDF Display, highlighted via the same raw-line/bbox mechanism
         the existing Metrics page uses (no new storage needed); properly bounded to
         page-at-a-time rendering instead of stacking every page — DR10
  -> Context Info shelf (right-hand panel, always visible regardless of PDF length — DR10):
     every kb.metric_value_range_type_map entry, invalid (status != 'approved') ones first
      -> set/correct canonical_bucket, click Apply
          -> entry saved as status='approved'
          -> in-process governed-lookup cache invalidated immediately
          -> every kb.metrics row with this raw_value AND a set error: error cleared
      -> or add a brand-new raw_value entry (same upsert call)
```

No schema changes were required beyond one new index — both `kb.metrics.value_range_type_error`
and `kb.metric_value_range_type_map` already existed from ADR `2026081401`.

## DR1–DR11 → Implementation

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

### DR10 — Root-cause layout fix + Map Block moved to the Context Info shelf

Found via the requester's first live click-through (in an authenticated browser session) on
2026-08-15, immediately after the page shipped:

- `resolve-metric-range-types-view.svelte`'s root changed from `min-height:100%` (unbounded,
  natural document flow) to `height:100%; overflow:hidden` plus `display:flex;
  flex-direction:column` — matching the pattern already used by
  `resolve-ambiguous-objects-view.svelte` and `metric-mgmt-view.svelte`'s
  `.metric-mgmt`/`.doc-frame-wrap`. The Left/Right split became `flex:1; min-height:0`; the
  results list changed from `max-height:640px; overflow-y:auto` to `flex:1; min-height:0;
  overflow-y:auto`; the PDF wrapper changed from a hardcoded `min-height:600px` to `min-height:0`
  inside the now-bounded row. This alone fixes both reported symptoms: `PdfViewWindow` now gets
  the definite-height ancestor its internal `height:100%`/`overflow:hidden` chain requires, so it
  paginates one page at a time in its own scrollable box instead of stacking every page of the
  source document; and the results list now stretches via flex to match the info/PDF column's
  height instead of stopping at a fixed 640px.
- New file `resolve-metric-range-types-shelf-store.svelte.ts` — mirrors
  `finding-shelf-store.svelte.ts`'s content/shelf bridging pattern exactly (`active` flag set on
  mount / cleared on destroy, `$state`-held `entries`/`loading`/`error`, plus
  `loadRangeTypeMapEntries`/`applyRangeTypeMapEntry` functions; an `onCorrected` callback lets the
  view refresh its errored-metrics list after a shelf-side correction).
- `resolve-metric-range-types-view.svelte` no longer owns any Map Block state — `mapEntries`,
  `mapLoading`, `mapError`, `mapBucketDraft`, `mapApplying`, `mapApplyResult`, `mapApplyError`,
  `newEntryRawValue`, `newEntryBucket`, `addingEntry`, `addEntryError`, `addEntryResult`,
  `loadMapEntries`, `applyMapEntry`, `addNewEntry`, and `sortedMapEntries` were all removed; the
  `errorTypeOptions` derived now reads `rangeTypeMapShelf.entries` instead of a local `mapEntries`.
  `CANONICAL_BUCKET_OPTIONS` and the Apply/Add-Entry icon imports (`RefreshCwIcon`, `CheckIcon`,
  `PlusIcon`) were also dropped from this file — the design tokens `surface2`, `colorWarn`,
  `colorOk` and the `@keyframes spin` rule went with them, since nothing left in the file used
  them.
- `context-shelf.svelte` renders the Map Block: a new `{:else if rangeTypeMapShelf.active}` title
  and body branch (parallel to the pre-existing `findingShelf.active` branch) shows a compact
  vertical list — raw_value, status badge, an `<input list>` bucket combobox seeded from
  `CANONICAL_BUCKET_OPTIONS`, and an Apply button per entry — plus an Add New Entry mini-form,
  replacing DR2's five-column grid table (too wide for the shelf's ~280–400px width). Per-entry
  draft/apply-status state (`mapBucketDraft`, `mapApplying`, `mapApplyResult`, `mapApplyError`) and
  the add-entry form state live in `context-shelf.svelte` itself, not the store — the store holds
  only data shared across the content/shelf boundary, matching how `FindingDetailsPanel` owns its
  own local UI state around `findingShelf`'s shared data. A `$effect` + `untrack` seeds
  `mapBucketDraft` for newly-seen entries without clobbering an in-progress edit on reload. The
  refresh-icon spinner uses Tailwind's `animate-spin` utility (already used elsewhere in this
  codebase, e.g. `doc-review-findings-view.svelte`) rather than a new hand-rolled `@keyframes`
  rule.

### DR11 — `selectRow` no longer remounts `PdfViewWindow` for same-record clicks

`resolve-metric-range-types-view.svelte`'s `selectRow` (previously ~24 lines) was restructured:

```ts
async function selectRow(id: number) {
	selectedId = id;
	const row = rows.find((r) => r.id === id);
	if (!row) return;

	if (currentInput?.id === row.input_record_id) {
		// Source document already loaded -- just move the PDF display to the
		// target page and repaint the highlight, without refetching or
		// remounting PdfViewWindow (matches metric-mgmt-view.svelte's
		// selectMetric, which avoids the same remount/reload trap).
		const spans = normalizeSpans(row);
		if (spans.length > 0) docPage = spans[0].page_number;
		highlightSelectionVersion += 1;
		return;
	}

	pdfLoading = true;
	pdfError = '';
	try {
		const [inputRes, linesRes] = await Promise.all([
			getKbInput(row.input_record_id),
			getRawLines(row.input_record_id)
		]);
		currentInput = inputRes.record;
		rawLines = linesRes.lines;
		const spans = normalizeSpans(row);
		docPage = spans.length > 0 ? spans[0].page_number : 1;
		highlightSelectionVersion += 1;
	} catch (e) {
		pdfError = e instanceof Error ? e.message : String(e);
		currentInput = null;
		rawLines = [];
	} finally {
		pdfLoading = false;
	}
}
```

Two changes from the original:

- **New early-return branch** for `row.input_record_id === currentInput?.id`: updates only
  `docPage`/`highlightSelectionVersion` (both cheap `$state` writes), never touching `pdfLoading`,
  `currentInput`, or `rawLines`. Since the template's `{:else if pdfLoading}` branch is what swaps
  `PdfViewWindow` out for a text placeholder, and `PdfViewWindow` never unmounts on this path, the
  already-loaded `pdf.js` document and its rendered canvases stay alive; `SharedPdfViewer`'s
  `page`- and `highlightVersion`-tracking `$effect`s (not its document-loading `$effect`) pick up
  the change and scroll/repaint against the already-rendered pages immediately.
- **Fetch path unchanged except the `docPage` fallback**: previously, if the newly selected row's
  `source_line_spans` failed to resolve any page (`spans.length === 0`), `docPage` was left at
  whatever it had been — silently showing the *previous* document's page number in the *new*
  document. It now falls back to `1`, matching `loadMetricsForRecord`'s `docPage = 1` reset in
  `metric-mgmt-view.svelte`.

Root cause this fixes: every row click was going through the fetch path unconditionally, including
clicks on a different metric from the *same* source document — a common case, since one
mis-mapped `value_range_type` routinely produces several errored `kb.metrics` rows against the same
document. `pdfLoading = true` (set before the `await`) is flushed to the DOM while the network
request is in flight, swapping `PdfViewWindow` out for the placeholder `<div>` and running its
`onDestroy`, which tears down the loaded PDF document and its `PDFWorker`
(`shared-pdf-viewer.svelte`'s `onMount` cleanup). When the fetch resolves, `pdfLoading = false`
remounts a *brand-new* `PdfViewWindow`/`SharedPdfViewer` instance, which reloads the PDF from the
network via `pdfLib.getDocument(...)` from scratch — the visible flash. Because this teardown/reload
cycle restarts on every click, rapid successive clicks (ordinary list-browsing behavior) kept
resetting the in-flight load before its scroll-to-page/highlight step — which only runs once
rendering finishes — ever got a chance to complete, which is what read as "clicking a metric
doesn't navigate or highlight."

No backend change was needed — `source_line_spans` was already selected and scanned correctly by
`ListMetricRangeTypeErrors` (confirmed by reading `metric_range_type_errors_handler.go`); the bug
was entirely in the frontend's per-click fetch/remount logic.

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

- `web/src/lib/components/home3/resolve-metric-range-types-client.ts` (124 lines) — typed API
  client (`listMetricRangeTypeErrors`, `listValueRangeTypeMapEntries`,
  `upsertValueRangeTypeMapEntry`), `CANONICAL_BUCKET_OPTIONS`, `isInvalidMapEntry`. Unchanged by
  DR10 — both the new store and `context-shelf.svelte` import from it directly.
- `web/src/lib/components/home3/resolve-metric-range-types-client.test.ts` (134 lines) —
  `node:test`-based client tests (see Tests). Unchanged by DR10.
- `web/src/lib/components/home3/resolve-metric-range-types-view.svelte` (628 lines originally; DR10
  removed the Map Block section and its state/handlers and reworked the root/row/list/PDF-wrapper
  layout to a bounded `height:100%; overflow:hidden` flex column; DR11 restructured `selectRow` to
  skip the fetch/remount path when the clicked row's source record is already loaded) — the page
  itself.
- `web/src/lib/components/home3/resolve-metric-range-types-shelf-store.svelte.ts` (new, DR10) —
  content/shelf bridge for the Map Block, mirroring `finding-shelf-store.svelte.ts`.
- `web/src/lib/components/home3/context-shelf.svelte` (DR10) — new `rangeTypeMapShelf.active`
  title/body branch rendering the Map Block as a compact list, plus its local
  draft/apply-status/add-entry state.
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

**DR10 (2026/08/15 follow-up):** no new automated tests were added — it is a layout/composition
change (CSS flex sizing, moving existing markup from one component to another via a new `$state`
store) with no new business logic to unit-test. Verification relied on `svelte-check` and direct
Vite module compilation (see Verification below).

**DR11 (2026/08/15 follow-up):** no new automated tests were added. `selectRow`'s logic is `$state`-
coupled Svelte component code with no existing component-level test harness for this page (only
`resolve-metric-range-types-client.test.ts`'s pure-function tests and the Go handler tests exist
today) — same test-coverage gap DR10 already noted for this file. Verification relied on
`svelte-check` and direct Vite module compilation (see Verification below).

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
- **2026-08-15 update:** the requester completed the authenticated browser click-through in their
  own session and found the two DR10 defects (results list not extending to match the Right
  panel's height; Map Block unreachable behind a multi-page PDF). Both are now fixed. This
  environment still has no seeded dev/test credentials (real Kratos auth only — see below), so the
  DR10 fix has been verified via `svelte-check` (clean across the workspace; the one pre-existing
  error is the same unrelated `doc-processor-dashboard-state.test.ts` noted above) and by
  requesting each of the three changed files directly from the running Vite dev server (port
  `5173`) to confirm they transform without error and contain no leftover references to the
  removed Map Block state (`grep` for `mapEntries`/`CANONICAL_BUCKET_OPTIONS`/
  `upsertValueRangeTypeMapEntry` in the compiled `resolve-metric-range-types-view.svelte` module
  returned zero matches). A final visual re-confirmation in the requester's existing authenticated
  session is the last step (see Recommended Follow-up).
- **2026-08-15 update (DR11):** the requester's second click-through found clicking a metric never
  moved the PDF to the matching page or highlighted it, and the panel flashed/reloaded on every
  click. Fixed via the `selectRow` restructuring above. Same credential constraint as DR10 applied,
  so verification used the same two checks: `bun run check` (svelte-check) — clean for this file,
  same single pre-existing unrelated `doc-processor-dashboard-state.test.ts` error as before, no
  new errors or warnings — and fetching the compiled module directly from the running Vite dev
  server (`curl http://localhost:5173/src/lib/components/home3/resolve-metric-range-types-view.svelte`),
  confirming it transforms without error and that the new early-return branch and its explanatory
  comment appear in the compiled output. A final visual re-confirmation in an authenticated browser
  session is still pending, same as DR10 (see Recommended Follow-up).
- No dev-login bypass or seeded dev/test credentials exist anywhere in this codebase or the
  sibling `Kratos` project — auth is real (`AUTH_USE_KRATOS=true`, backed by Ory Kratos). `/development`
  itself has no server-side route guard (`hooks.server.ts`'s `PROTECTED_ROUTES` is just
  `['/dashboard']`), but `dashboard.svelte`'s shell does its own auth check and redirects to
  `/login` when no session cookie is present, which is what an unauthenticated `curl`/Playwright
  request to `/development` hits.

## Documentation Impact

- ADR `2026081401` — §1 gained a 2026/08/15 changelog entry; §7's "no admin UI" bullet marked
  `~~struck~~` and annotated "Resolved 2026-08-15," pointing to this ADR/implementation pair.
- ADR `2026081501` (this implementation's companion) — records the same DR1–DR10 in decision-record
  form, including DR10's supersession of DR2's original Map Block placement.
- No other existing document was found to reference this gap or this table pair besides ADR
  `2026081401` itself.

## Recommended Follow-up

- Re-confirm the DR10 fix (list height, Map Block reachability) and the DR11 fix (click-to-navigate,
  no reload flash) in an authenticated browser session — the requester found both sets of bugs via
  click-through; both fixes have only been confirmed via `svelte-check` and Vite compilation so
  far, not visually.
- Decide whether "Apply" should also surface a way to trigger `normalize_assertions`/
  `associate_semantics` reprocessing for the records it just corrected, rather than relying
  entirely on the existing backlog-drain mechanism to eventually pick them up (ADR `2026081501` §5).
- Add real pagination to the Map Block / errored-metrics list if either grows past the current
  500-row cap / current few-dozen-entry scale — more pressing for the Map Block after DR10, since
  the shelf is narrower than the old full-width table.
- A "mark ambiguous" action from the Map Block, so operators no longer need direct DB access for
  that one status transition.
- Revisit DR8's duplicated PDF-highlight logic for extraction into a shared util if a third admin
  page ever needs the same source-highlighting mechanism.
