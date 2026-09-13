# Product Review: 3D Drawing + Resizable Results Layout

**Date:** 2026-09-13 \
**Scope:** Knowledge-change record for openspec change `product-review-3d-resizable-layout`
(`ChenWeb/openspec/changes/product-review-3d-resizable-layout/`) — what changed, what's now
documented, and what was intentionally left undone.

**Code root:** `ChenWeb/server/api/productdrawings/`, `ChenWeb/server/api/product-reviews/`,
`ChenWeb/web/src/lib/components/home3/product-metric-review-view.svelte`,
`ChenWeb/web/src/lib/components/home3/dashboard.svelte`,
`ChenWeb/web/src/lib/components/home3/content-panel.svelte`

## What knowledge changed

1. **The Product Review results page can now generate and keep a product drawing**, reusing the
   existing System Admin "Generate 3D Product Drawings" flow (`productdrawings` package /
   `productDrawingService.ts`) rather than a new generation mechanism. A kept drawing is cached
   against the review profile via a new nullable `kb.product_profiles.drawing_id` column
   (migration `20260913000001_add_drawing_id_to_product_profiles.sql`), so it isn't regenerated
   on every page visit.
2. **`KeepPending`'s `INSERT INTO kb.product_drawings` previously had no `RETURNING id`** — the
   backend had no way to tell a caller which row it just created. This was a real gap, not just
   an omission for this feature: any future caller wanting to reference a specific kept drawing
   would have hit the same wall. Fixed by adding `RETURNING id` and a new `KeepResponse.ID` field
   (JSON `id`, `omitempty`).
3. **The scope-tree/results/metric-details panes on the Results tab are now user-resizable**,
   following the hand-rolled pointer-capture splitter pattern already established in
   `metric-ontology-explorer/panel-shell.svelte` — deliberately *not* the shadcn/paneforge
   `web/src/lib/components/ui/resizable/*` wrapper, which turned out to be wired into only two
   demo/scaffold routes (`example-left-right-panes`, `sidebar-01`) and nowhere in the real app,
   despite being present in the tree. Worth remembering next time a resizable-panel need comes up
   elsewhere: the paneforge wrapper is not dead code to delete, but it is *not* the app's actual
   convention either.
4. **The dashboard's generic "App Status" context panel (`context-shelf.svelte`) is now
   nav-id-scoped**, not just `shelfOpen`-scoped: `dashboard.svelte` gates it (and its resize
   divider) on `shelfOpen && activeMenu?.childId !== 'apps-product-review'`, and
   `content-panel.svelte` hides the shared topbar's toggle button under the same condition. This
   is the first page in the app to opt out of that panel; the mechanism is generic (keyed off
   `activeMenu?.childId`) and could be reused for a future page with the same need, but nothing
   else currently uses it.

## Which docs/specs/tests are affected

- New openspec capability spec: `openspec/changes/product-review-3d-resizable-layout/specs/product-review-results-layout/spec.md` (10 requirements / scenarios, all `ADDED`).
- New user manual version: `KnowledgeStore/doc-repo/user-manuals/product-metric-reviewer-v1.3-en.md` (v1.0–v1.2 left untouched, per the established convention that older revisions keep `status: current` and aren't edited).
- Go tests: new/updated cases in `server/api/product-reviews/store_test.go` and `helpers_test.go`
  (`TestGetProfileWithDrawing`, `TestGetProfileNoDrawing`, `TestSetProfileDrawingAssociates`,
  `TestSetProfileDrawingClears`, plus `TestListProfilesMixedRunHistory` extended to assert
  `DrawingID`); five pre-existing `profileRows(...)`-shaped test fixtures updated for the new
  `drawing_id` column in `CreateProfile`/`FindProfileByName`/`ListProfiles`.
- Frontend tests: `productDrawingService.test.ts` and `productMetricReviewService.test.ts` extended
  for the new `id` field and `setProfileDrawing` call.

## Which docs are now stale

None directly caused by this change. One **pre-existing** gap surfaced during design and is worth
recording here since it will keep tripping up anyone editing that capability: the
`product-metric-reviewer-page` spec (proposal `2026-09-13-product-metric-reviewer`, archived the
same day this change was made) was never merged into `openspec/specs/` — `openspec spec list`
does not show it, even though the change directory is under `openspec/changes/archive/`. This
change did **not** attempt to fix that (out of scope), and instead used a new, non-overlapping
capability name (`product-review-results-layout`) rather than a `MODIFIED` delta against a base
spec that doesn't exist in the registry. Whoever eventually reconciles that gap should check
whether `product-review-results-layout` ought to be folded into `product-metric-reviewer-page` at
that point.

## What was intentionally left undocumented / undone

- **No handler-level test for `SetProductProfileDrawing`** — matches its sibling
  `SetProductProfileReady`, which also has no handler-level test in this package (only store-level
  sqlmock tests exist for either). Not a regression introduced by this change.
- **No cleanup of superseded `kb.product_drawings` rows after "Regenerate."** Matches
  `ProductDrawingsView`'s existing behavior, which has no such cleanup for its own list either.
  Old rows accumulate; nothing currently reads or deletes them once a profile's `drawing_id`
  moves on.
- **No real, logged-in, non-stubbed click-through end to end.** This environment has no login
  credentials (same boundary every prior Product Review change has hit — see
  `product-review-intake`'s task 8.3 and `product-review-history-list`'s task 5.3). Verification
  here used a headless-Chromium Playwright script against the live `mise dev` frontend with
  `/api/v1/**` intercepted and stubbed; it exercised the generate → keep → regenerate flow, all
  three drag handles (including persistence across a reload), the Report-tab non-interference
  check, and the shelf-suppression/regression check against an unrelated nav item. Someone with
  real credentials should still do one live pass.
