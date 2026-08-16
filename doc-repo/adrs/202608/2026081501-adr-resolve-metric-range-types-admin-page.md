# ADR 2026081501 — Resolve Metric Range Types Admin Page

**Date:** 2026-08-15 \
**Status:** Implemented \
**Component:** ChenWeb — `kb.metrics`, `kb.metric_value_range_type_map` (schema unchanged, one new
index), `server/api/kbhandler/metric_range_type_errors_handler.go`,
`server/api/ontology/assertions/metric_normalizer.go`,
`web/src/lib/components/home3/resolve-metric-range-types-{view.svelte,client.ts}` \
**Authors:** Chen Ding (with Claude) \
**Related:** ADR `2026081401` (governed, DB-backed metric vocabulary mapping — this page closes its
§7 "no admin UI is proposed here" open question); precedent: the existing "Resolve Ambiguous
Objects" admin page for `kb.object_nodes` reconciliation, which §7 named as the shape to copy \
**Tags:** admin UI, governed vocabulary, kb.metrics, kb.metric_value_range_type_map, Database
Maintenance, System Admin

## 1. Change Logs

* 2026/08/15, ADR created and implemented same day, via OpenSpec change
  `ChenWeb/openspec/changes/resolve-metric-range-types/` (proposal/design/specs/tasks, all 22
  tasks complete). Companion document: Implementation `2026081501` (this ADR's decisions mapped
  to actual code, file by file).
* 2026/08/15, first live click-through (by the requester, in an already-authenticated browser
  session, immediately after the page shipped) found two defects: the results list stopped short
  of the Right panel's actual height, and DR2's full-width Map Block was unreachable in practice
  behind a multi-page source PDF. Root-caused and fixed same day — see DR10, which supersedes
  DR2's Map Block placement. Companion Implementation document updated to match.
* 2026/08/15, second defect report (same day, after DR10 shipped): clicking a metric in the
  results list neither moved the PDF display to the matching page nor highlighted the matching
  content, and the PDF panel visibly flashed/reloaded on every click. Root-caused and fixed same
  day — see DR11. Companion Implementation document updated to match.

## 2. Context

ADR `2026081401` (DR6) made `extract_metrics` set `kb.metrics.value_range_type_error` the moment a
row's `value_range_type` normalizes to a `kb.metric_value_range_type_map` entry with
`status = 'proposed'` — i.e., a raw string no human has ever approved or marked `'ambiguous'`. That
ADR's §7 explicitly deferred building any triage tool for these rows or their underlying map
entries:

> No admin UI is proposed here for triaging `status='proposed'` rows — operators can query the
> table directly for now. If this becomes a routine workflow, an admin page listing proposed rows
> by `occurrence_count`, with the DR6 best-effort `canonical_bucket` guess shown for quick
> approve/correct (same shape as the existing "Resolve Ambiguous Objects" page for `kb.object_nodes`
> reconciliation) would close the loop the way that page does for object reconciliation.

By 2026-08-15 that backlog was real and growing with every extraction run, and nothing in the
codebase ever cleared `value_range_type_error` once set — not even after a human corrected the
underlying mapping by hand. This ADR records the decision to build that page now, using the
requester's own numbered requirements as the starting spec:

1. Input scope: `kb.metrics` rows where `value_range_type_error` is non-empty.
2. Two-panel layout (Left/Right), modeled on the existing Metrics page
   (`home3/knowledge` → Knowledge System → Metrics).
3. Left panel: search by record ID, time, or error type; results list.
4. Selecting a record shows an Information Block (name, description, context, value, value data
   type, value range type, error message); the Right panel highlights the matching PDF content.
5. A Map Block listing every `kb.metric_value_range_type_map` entry (`raw_value`,
   `canonical_bucket`, `status`) with a per-entry "Apply" action; users can also add new entries.
   Any entry whose `status != 'approved'` counts as invalid.
6. `canonical_bucket` is edited via a dropdown of valid buckets, but free text is also accepted.
7. Applying/entering a bucket on an invalid entry saves it and automatically corrects every
   `kb.metrics` row sharing that `raw_value`.

Relevant pre-existing constraints this decision had to work within:

- `kb.metric_value_range_type_map.canonical_bucket` carries **no DB `CHECK` constraint** — only
  `status` does (`ANY (ARRAY['proposed','approved','ambiguous'])`). The only buckets any code path
  has ever produced are `lower_bound`, `upper_bound`, `exact`, `range` (confirmed against live data:
  17/16/13/8 rows respectively, plus 20 blank `proposed` rows at the time of this ADR).
- `assertions.ValueRangeTypeMapper` caches the whole governed table in-process for a 30s TTL,
  invalidated on write — but only from calls made *inside* the `assertions` package.
- `MetricNormalizer.Normalize` never writes to `kb.metrics` — it only reads it and proposes
  `kb.semantic_decision_candidates` rows. The only `kb.metrics` column any part of this feature
  family writes is `value_range_type_error` itself.
- No admin page in this codebase has a dedicated backend role/permission check; "admin-only" is
  enforced entirely by nav placement plus server-resolved `kb.page_config`/`access_role` gating on
  the nav tree itself (confirmed by inspecting how "Resolve Ambiguous Objects" is gated).

## 3. Decision

**DR1 — Page placement: nav-gated, no new route, no new backend middleware.**
Added as a fifth child under the existing System Admin → Database Maintenance → "Database
Maintenance" nav group, alongside "Resolve Ambiguous Objects." Home3 admin pages are not
URL-routed — nav selection is pure client-side state (`content-panel.svelte` dispatches by
`activeMenu.childId`) — so this page needed no new SvelteKit route. Its three new API endpoints sit
on the existing `apiGroup` (`authmiddleware.AuthMiddleware` only), matching every other `/kb/...`
endpoint including the ones "Resolve Ambiguous Objects" already added. Admin-only access comes
entirely from the nav tree being hidden from non-admin `access_role`s server-side, not from an
endpoint-level check. **Alternative considered:** a dedicated backend role check on the three new
endpoints — rejected as inconsistent with every other admin-only `/kb/...` endpoint in this
codebase, which would make this feature an unexplained exception rather than following the
established pattern.

**DR2 — Layout: Left/Right split for record triage, plus a separate full-width Map Block.**
The Left panel holds search + results list; the Right panel holds the Information Block and PDF
Display, matching requirement 2's "similar to the Metrics page" instruction. The Map Block —
requirement 5 — is **not** folded into either panel: it governs `kb.metric_value_range_type_map`
across *all* records, not just the one currently selected, so it is rendered as its own full-width
section below the Left/Right split. **Alternative considered:** placing the Map Block inside the
Right panel below the PDF viewer — rejected because it would visually tie a cross-record governance
table to whichever single record happens to be selected, which misrepresents its scope.
**Superseded 2026-08-15 by DR10:** the full-width-section placement itself turned out to be
unreachable in practice (see DR10) — the Map Block now lives in the page-level Context Info shelf
instead.

**DR3 — One upsert endpoint serves both "Apply" (requirement 7) and "Add Entry" (requirement 5).**
`POST /api/v1/kb/metric-value-range-type-map` with `{raw_value, canonical_bucket, note?}` does
`INSERT ... ON CONFLICT (raw_value) DO UPDATE`, always setting `status = 'approved'` — a bucket is
required. **Alternative considered:** separate POST (create) / PATCH (correct) endpoints — rejected
as duplication: from the database's point of view, "add a new approved entry" and "correct an
existing invalid one" are the identical write (upsert-by-`raw_value`), and requirement 7's cascade
must run in both cases, since a freshly-added entry can retroactively match rows that already
errored before the entry existed.

**DR4 — New handler, reusing the existing `metricRecord` DTO for the errored-metrics list.**
`GET /api/v1/kb/metrics/range-type-errors` filters `WHERE value_range_type_error IS NOT NULL` plus
optional `input_record_id` / `date_from` / `date_to` / `value_range_type` ("error type"), returning
the same `metricRecord` shape `ListMetrics`/`UpdateMetric` already use (extended with one new
optional `value_range_type_error` field) rather than inventing a parallel DTO. `GET
/api/v1/kb/metric-value-range-type-map` lists the full governed table, invalid entries first. The
"error type" search filter (requirement 3) is sourced from the Map Block's own non-approved rows
rather than a fourth endpoint — today there is exactly one error message shape
(`unmapped value_range_type: "<raw>"`), so the only meaningful "type" axis already **is** "which raw
value triggered it."

**DR5 — Cascade correction matches via a SQL-side port of the Go normalization, not an app-side
loop.** The upsert handler runs
`UPDATE kb.metrics SET value_range_type_error = NULL WHERE value_range_type_error IS NOT NULL AND
lower(regexp_replace(trim(value_range_type), '[- ]', '_', 'g')) = $1` — a faithful single-pass
regex port of `normalizeValueRangeTypeRaw` (lowercase, trim, hyphen/space → underscore), proven
equivalent by a fixture-based unit test. **Alternative considered:** load candidate rows into Go and
filter with the real Go function — rejected in favor of one set-based `UPDATE`, at the accepted cost
of the SQL and Go normalization logic needing to be kept in sync by hand (mitigated with a
cross-referencing comment and the equivalence test).

**DR6 — Two small exported functions added to the `assertions` package, not a new package or
callback mechanism.** `InvalidateValueRangeTypeMapCache()` and `NormalizeValueRangeTypeRaw(raw
string) string` wrap the pre-existing unexported `invalidate`/`normalizeValueRangeTypeRaw`, letting
the new handler (a) clear the up-to-30s-stale in-process cache immediately after a correction and
(b) key `raw_value` identically to the runtime lookup. **Alternative considered:** a
package-level callback/observer registry for cache invalidation — rejected as overengineering two
one-line wrappers around functions that already existed.

**DR7 — `canonical_bucket` is edited as a native HTML `<input list>` combobox, not a strict
`<select>`.** Seeded with the four known buckets (`lower_bound`, `upper_bound`, `exact`, `range`)
via a shared `<datalist>`, but any text is accepted — matching the column's actual DB-level
looseness (requirement 6). The backend does not validate `canonical_bucket` against this list
either, only that it is non-empty, for the same reason.

**DR8 — The PDF-highlight mechanism is duplicated into the new page, not extracted into a shared
util.** `metric-mgmt-view.svelte` (4,291 lines, the primary Metrics page) already implements
span→page/line resolution and highlight-overlay rendering against `GET /kb/raw-lines` +
`PdfViewWindow`. The new page reimplements the same ~150-line slice rather than refactoring the
high-traffic existing component. **Alternative considered:** extracting a shared
`normalizeMetricSpans`/`renderHighlights` util — rejected as a refactor-for-one-caller of
already-shipped code, carrying real regression risk to the primary Metrics page for no functional
gain to this one; flagged as worth revisiting if a third page ever needs the same mechanism.

**DR9 — One new partial index, no other schema changes.**
`idx_kb_metrics_range_type_error ON kb.metrics (input_record_id, created_at) WHERE
value_range_type_error IS NOT NULL` — covers both the exact-match and time-range filters over the
(small) error-only row subset. Both `kb.metrics.value_range_type_error` and
`kb.metric_value_range_type_map` already existed (from ADR `2026081401`); nothing about this page
required a new table or column.

**DR10 — (Supersedes DR2's Map Block placement) Root-cause layout fix, plus relocating the Map
Block to the page-level Context Info shelf.** The first live click-through (2026-08-15, same day)
showed DR2's "full-width section below the split" was unreachable in normal use:
`resolve-metric-range-types-view.svelte`'s root never established a definite `height:100%;
overflow:hidden` ancestor the way every other page embedding `PdfViewWindow` does
(`resolve-ambiguous-objects-view.svelte`, `metric-mgmt-view.svelte`'s `.metric-mgmt`/
`.doc-frame-wrap`). Without one, `PdfViewWindow`'s internal `height:100%` chain resolved as `auto`
per the CSS percentage-height spec, so instead of paginating one page at a time inside a bounded,
internally-scrolling box, it stacked every page of the source PDF in normal document flow —
burying the Map Block thousands of pixels below the fold for any multi-page document, and making
the fixed-`640px` results list look short next to the now-unbounded PDF column. Two changes fixed
this:
- The view's layout was brought in line with the established app-shell pattern (`height:100%;
  overflow:hidden` root, `flex:1; min-height:0` row, results list `flex:1; overflow-y:auto`
  instead of a `max-height:640px` cap) — this alone re-bounds `PdfViewWindow` to page-at-a-time
  rendering and makes the list stretch to match the info/PDF column's height, closing both
  reported symptoms.
- Independently, the Map Block itself was moved out of page flow entirely into the page-level
  Context Info shelf (`context-shelf.svelte`), so it stays reachable regardless of how tall any
  given source PDF renders — not just resilient to the specific bug above. This follows the same
  content/shelf bridging pattern already established by `finding-shelf-store.svelte.ts` for the
  Document Review report: a new `resolve-metric-range-types-shelf-store.svelte.ts` holds
  `active`/`entries`/`loading`/`error` plus `loadRangeTypeMapEntries`/`applyRangeTypeMapEntry`,
  published by the view on mount/destroy and rendered by `context-shelf.svelte` as a compact
  vertical list rather than DR2's five-column grid, which doesn't fit the shelf's ~280–400px
  width.

**Alternative considered:** keep the Map Block in page flow and only fix the height chain —
rejected because even a properly-bounded PDF column can still be taller than the list/info column
for a long multi-page document, so the Map Block's reachability would remain a function of which
record happens to be selected; shelf placement makes it unconditionally visible instead.

**DR11 — Root-cause fix: `selectRow` no longer refetches/remounts `PdfViewWindow` when the newly
clicked row shares the already-loaded source record.** The requester's second live click-through
(2026-08-15, same day, after DR10 shipped) found neither reported symptom was a layout issue:
clicking a row never moved the PDF to the matching page or highlighted it, and the PDF panel
visibly flashed on every click. Root cause: `selectRow` unconditionally called `getKbInput`/
`getRawLines` and toggled the page's local `pdfLoading` flag on **every** row click, regardless of
whether the newly selected row's `input_record_id` matched the already-displayed document — a
single mis-mapped source document routinely produces several errored-metric rows, so this fired on
nearly every real click. Because the template swaps to a plain text placeholder while `pdfLoading`
is true, this destroyed and recreated the entire `PdfViewWindow`/`SharedPdfViewer` subtree on every
click, discarding the loaded PDF.js document/worker and reloading the file from the network each
time — the visible flash — and racing the scroll-to-page/highlight step (which only fires once
rendering finishes) against the next click, so it never got a chance to settle. The existing
Metrics page (`metric-mgmt-view.svelte`) already solved this: its `selectMetric` only ever mutates
`docPage`/`highlightSelectionVersion` when navigating within an already-loaded record — no fetch,
no remount — and only calls its record-loading function when the record id actually changes (see
its `// Move display to the selected page without forcing iframe remount/reload` comment). `selectRow`
was changed to match: when `row.input_record_id === currentInput?.id`, it now only updates
`docPage`/`highlightSelectionVersion` and returns; the fetch-and-`pdfLoading` path is reached only
when the record actually changes, in which case `docPage` also now falls back to `1` (rather than
silently keeping the previous document's page) if the new record's spans don't resolve.
**Alternative considered:** none — this is a direct port of the already-proven pattern from
`metric-mgmt-view.svelte`, not a new design.

**Explicit non-decisions (in scope for requirements 1–7, deliberately not built):**

- Clearing `value_range_type_error` does **not** itself trigger `normalize_assertions`/
  `associate_semantics` reprocessing. `MetricNormalizer.Normalize` never wrote to `kb.metrics` in
  the first place (§2), so there is nothing on the metric row left to recompute; a later
  backlog-drain pass is what turns the now-approved bucket into an accepted `kb.semantic_assertions`
  row. This page only removes the stale error flag.
- No UI path to set `status = 'ambiguous'` ("no bound direction is inferable, stop asking"). Today
  that status is set outside this workflow; this page's Apply action only ever produces `approved`,
  since it always requires a bucket. Requirements 5–7 describe only the approve/correct path.
- No audit-log table for map edits — `kb.metric_value_range_type_map.note`/`modify_by`/
  `modify_time` (already present) capture provenance, matching how the table already tracked
  `first_seen_record_id`/`last_seen_record_id`.

## 4. Consequences

**Positive:**

- The operational gap ADR `2026081401` §7 named is closed: an operator can now find, understand
  (with source-PDF context), and fix an unmapped `value_range_type` without touching SQL directly.
- The fix is durable and applies retroactively: correcting one `raw_value` clears every historical
  `kb.metrics` row that already carries that error, not just future extractions.
- No schema risk: additive-only (one index), and the two new `assertions` exports are pure wrappers
  with no behavior change for any existing caller.
- (DR10) The Map Block is now reachable regardless of source-document length, and the fix doubles
  as the general-purpose bugfix every future page embedding `PdfViewWindow` inside this page's
  Left/Right pattern needs to remember to apply.
- (DR11) Clicking any row in a source document that's already displayed now navigates and
  highlights instantly, with no PDF reload — matching the primary Metrics page's behavior. The fix
  is a direct application of that page's already-proven `selectMetric` pattern, so it carries no
  new design risk.

**Negative / accepted costs:**

- SQL/Go normalization logic now exists in two places that must be kept in sync by hand (DR5).
- ~150 lines of PDF-highlight logic are duplicated between this page and `metric-mgmt-view.svelte`
  (DR8).
- The errored-metrics list is capped at 500 rows with no pagination — acceptable at the scale
  observed at implementation time (dozens of `proposed` map entries, low-thousands of total metric
  rows), but will need revisiting if the backlog grows substantially.
- Applying a correction can visually read as "fixed" when only the flag was cleared — the
  underlying `kb.semantic_assertions` row is not regenerated until a later reprocessing pass runs
  (mitigated by the UI's own wording, see Implementation doc).
- (DR10) The Map Block now competes for space in the shared Context Info shelf with whatever other
  page-specific shelf content exists (today only `findingShelf`, which is mutually exclusive by
  page); no automated tests were added for the layout fix or the shelf relocation, and the fix
  itself has not yet been re-confirmed in an authenticated browser (see Implementation doc,
  Verification).
- (DR11) No automated test was added — see Implementation doc for why. Like DR10, this fix has
  only been verified via `svelte-check` and direct Vite module compilation, not yet re-confirmed
  in an authenticated browser session (same missing-dev-credentials constraint as DR10).

## 5. Open Questions / Future Work (explicitly out of scope here)

- Whether "Apply" should also offer to trigger (or link to) a `normalize_assertions` reprocessing
  pass for the newly-corrected records, rather than leaving that entirely to the existing
  backlog-drain mechanism.
- Whether the Map Block needs real pagination once the governed table grows past a few hundred
  rows — today's ordering (invalid first, then by `occurrence_count`) keeps the highest-value rows
  visible without it. More pressing after DR10 than when originally written, since the shelf's
  ~280–400px width shows noticeably fewer entries at a glance than the old full-width table did.
- An explicit "mark ambiguous" action from this page's Map Block, so an operator does not need to
  fall back to direct DB access for that one status transition.
- Whether the duplicated PDF-highlight logic (DR8) should be extracted into a shared util if a
  third admin page ever needs the same source-highlighting mechanism.

## 6. Implementation

Implemented same-day; see Implementation document `2026081501` for the full DR-by-DR code mapping,
file-by-file change list, tests, and verification results (build/vet/test, `svelte-check`, frontend
unit tests, and a live check against the running dev server confirming the migration applied and
both new endpoints are reachable and correctly auth-gated). DR10's layout/shelf fix, applied the
same day after the requester's live click-through surfaced it, is verified there via `svelte-check`
and direct Vite module compilation of the three changed files; a final authenticated-browser
re-confirmation is called out as still pending (no seeded dev/test credentials exist in this
environment). DR11's remount/reload fix, applied the same day after a second live click-through,
is verified the same way (`svelte-check`, direct Vite module compilation), with the same
authenticated-browser re-confirmation still pending.

## 7. References

- ADR `2026081401` — `KnowledgeStore/doc-repo/adrs/202608/2026081401-adr-governed-metric-vocabulary-and-phase-d-failure-reporting.md`
  (the decision this page's admin UI closes; §7, §1 2026/08/15 changelog entry).
- Implementation `2026081501` — `KnowledgeStore/doc-repo/impl/202608/2026081501-impl-resolve-metric-range-types-admin-page.md`.
- OpenSpec change — `ChenWeb/openspec/changes/resolve-metric-range-types/` (proposal, design,
  specs, tasks — all 22 tasks complete).
- Precedent — `web/src/lib/components/home3/resolve-ambiguous-objects-{view.svelte,client.ts}` and
  `server/api/kbhandler/ambiguous_objects_handler.go` (the "Resolve Ambiguous Objects" page ADR
  `2026081401` §7 named as the shape to copy).
