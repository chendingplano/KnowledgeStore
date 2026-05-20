# Artifact Wiki — Implementation Notes

Companion to the `Artifact Wiki` section in [`+CAPSULE.md`](+CAPSULE.md) (lines 472–484)
and the full design in [`artifact-wiki-spec.md`](artifact-wiki-spec.md).
This document records **what was built**, **where it lives**, and **why** key
design decisions landed where they did.

---

## What it replaces

Before this change the `Wiki → Artifact Wiki` menu entry (section ID
`kb-summary-graph`) rendered `summary-graph-view.svelte`, which is a thin
wrapper that delegates to `TreeGraphView mode="summary"`.  That covered
summaries only.  The new implementation handles all six artifact types:
summaries, topics, metrics, scenes, provisions, and products.

---

## Files changed or created

### New frontend files

| File | Role |
|---|---|
| [`ChenWeb/web/src/lib/components/home3/artifact-wiki-view.svelte`](../../../../ChenWeb/web/src/lib/components/home3/artifact-wiki-view.svelte) | Outer shell: owns the tab strip + routes each tab to the right panel |
| [`ChenWeb/web/src/lib/components/home3/artifact-category-panel.svelte`](../../../../ChenWeb/web/src/lib/components/home3/artifact-category-panel.svelte) | Per-category split view: SVG artifact graph (left) + PDF pane (right) |

### Modified frontend files

| File | What changed |
|---|---|
| [`ChenWeb/web/src/routes/home3/knowledge/+page.svelte`](../../../../ChenWeb/web/src/routes/home3/knowledge/+page.svelte) | Import swapped `SummaryGraphView` → `ArtifactWikiView`; render block updated for `kb-summary-graph`; menu relabeled (see below) |
| [`ChenWeb/web/src/lib/components/home3/tree-graph-view.svelte`](../../../../ChenWeb/web/src/lib/components/home3/tree-graph-view.svelte) | Two new props: `hideTabStrip` and `onOpenCategoryTab`; bug fix: node click selection (see below) |
| [`ChenWeb/web/src/lib/services/kbService.ts`](../../../../ChenWeb/web/src/lib/services/kbService.ts) | New service calls: `getMetricCategory`, `getSceneCategory`, `getProductCategory`, `getArtifactCategoryCounts`; new exported types |
| [`ChenWeb/web/src/lib/components/home3/knowledge-sections.js`](../../../../ChenWeb/web/src/lib/components/home3/knowledge-sections.js) | Added `kb-product-parts` under-construction entry |

### New backend files

| File | Role |
|---|---|
| [`ChenWeb/server/api/kbhandler/artifact_category_handler.go`](../../../../ChenWeb/server/api/kbhandler/artifact_category_handler.go) | Four new HTTP handlers for artifact category lookups |

### Modified backend files

| File | What changed |
|---|---|
| [`ChenWeb/server/api/routes.go`](../../../../ChenWeb/server/api/routes.go) | Four new `GET` routes wired to the handlers above |

---

## Menu changes (`+page.svelte`)

Per the capsule spec (lines 66–86, 472–484):

| Before | After |
|---|---|
| Parent section label: `Subject Wiki` | `Wiki` |
| Child entry label: `Subject Wiki` | `Artifact Wiki` |
| Child entry description: `Category-first summary graph` | `Category-first artifact exploration` |
| `kb-topic-graph` (Topic Wiki) present | Removed from menu |
| `kb-provision-graph` (Provision Wiki) present | Removed from menu |
| — | `kb-product-parts` added as under-construction entry |

The render blocks for `kb-topic-graph` and `kb-provision-graph` were left in
`+page.svelte`; they are dead paths now that the menu entries are gone, but
removing them was out of scope.

---

## Architecture: three-layer composition

```
ArtifactWikiView          ← owns the tab strip
  │
  ├── [Tab: "Artifact Graph"] ──→ TreeGraphView (mode="summary", hideTabStrip, onOpenCategoryTab)
  │                                 double-click a category node → fires onOpenCategoryTab
  │
  └── [Tab: "…/some/path"] ──→ ArtifactCategoryPanel (categoryPath=...)
```

### Why a wrapper instead of extending `TreeGraphView`

`TreeGraphView` already carries a tab strip for its own category tabs
(Summary / Topic per category).  Adding a second layer of tabs inside the same
component would have coupled unrelated concerns.  Instead:

- `TreeGraphView` gained two new optional props:
  - `hideTabStrip` — suppresses the internal tab strip render so the component
    acts purely as the graph stage.
  - `onOpenCategoryTab(categoryPath)` — when set, double-clicking a node fires
    this callback instead of creating an internal tab, letting the parent own
    tab lifecycle.
- `ArtifactWikiView` owns the outer tab strip with the same visual style
  (copied from `summary-graph-tabs.svelte`).

This keeps `TreeGraphView` fully backward-compatible; all existing call sites
that omit both props behave identically to before.

---

## Backend: new API endpoints

All four handlers follow the same pattern established by `GetSummaryCategory`
and `GetProvisionCategory`:

1. Read `ARTIFACT_WEB_DIR/{categoryPath}/{type}.txt` — one ID per non-blank,
   non-comment line.
2. Query the relevant `kb.*` table using `WHERE id/object_id/product_rel_id IN ($1,$2,…)`.
3. Return `{ status, categoryPath, type, items[] }`.

### Endpoint table

| Method | Path | Handler | Index file | DB table | ID field |
|---|---|---|---|---|---|
| `GET` | `/api/v1/kb/metric-category` | `GetMetricCategory` | `metrics.txt` | `kb.metrics` | numeric `id` |
| `GET` | `/api/v1/kb/scene-category` | `GetSceneCategory` | `scenes.txt` | `kb.scene_objects` | `object_id` (string) |
| `GET` | `/api/v1/kb/product-category` | `GetProductCategory` | `products.txt` | `kb.products` | `product_rel_id` (string) |
| `GET` | `/api/v1/kb/artifact-category-counts` | `GetArtifactCategoryCounts` | all six | — | line counts only |

Error codes follow the `CWB_KB_{TYPE}_{seq}` convention already used in the
package.

### `IN` clause placeholders

`lib/pq` array parameters are not used in this handler package.  Placeholders
are built manually with `buildPlaceholders(n)` → `"$1,$2,…,$n"` and the args
slice is typed `[]any`.  This matches the pattern in the existing provision
and summary handlers.

### `artifact-category-counts` endpoint

`GetArtifactCategoryCounts` does not hit the database.  It calls
`readArtifactIndexIDs` for each of the six index file names and returns the
line counts.  The frontend uses this to decide which group circles to show as
populated in the SVG graph before any items are loaded.

---

## `ArtifactCategoryPanel`: SVG artifact graph

The panel is a fixed-size SVG (`viewBox="0 0 820 520"`) with:

- Six group circles (r=50) arranged at radius=210 from the center (CX=410, CY=260),
  one per artifact type, each with its own accent color.
- Up to 8 instance nodes (84×26 rounded rects, rx=13) per group, fanned at
  radius=108 from the group center.
- Edges drawn with `<line>` elements: center → group, group → instances.
- A resize-drag handle between the SVG pane and the PDF `<iframe>` pane
  (left panel clamped 320–720 px).

### Interaction model

| Gesture | Effect |
|---|---|
| Single-click group circle | `toggleGroup` — expand/collapse instance nodes |
| Single-click instance node | `selectItem` — shows info card; loads PDF |
| Drag handle | Resize left (graph) / right (PDF) panels |

All six groups are loaded in parallel on `onMount` via the corresponding
service call.  Groups with no items in the category display with reduced
opacity but are still rendered.

### PDF pane

When an instance is selected the right pane renders:

```
/api/v1/kb/inputs/{inputId}/file#page={page}&zoom=page-width
```

in an `<iframe>`.  This is the same URL pattern used by the summary and topic
category tab panels.

---

## Service layer additions (`kbService.ts`)

```ts
// New exported types
export type ArtifactCategoryItem   = { id, label, sublabel?, inputId, page }
export type GetArtifactCategoryResponse = { status, categoryPath, type, items[] }
export type ArtifactCategoryCount  = { type, count }
export type GetArtifactCategoryCountsResponse = { status, categoryPath, counts[] }

// New functions
getMetricCategory(categoryPath, ksStoreId?)   → GetArtifactCategoryResponse
getSceneCategory(categoryPath, ksStoreId?)    → GetArtifactCategoryResponse
getProductCategory(categoryPath, ksStoreId?)  → GetArtifactCategoryResponse
getArtifactCategoryCounts(categoryPath)       → GetArtifactCategoryCountsResponse
```

`getSummaryCategory`, `getTopicCategory`, and `getProvisionCategory` already
existed; the new functions follow the same signature and return shape.

---

## Artifact type → ID mapping

| Type | Index file | DB table | `id` field in response | Meaning |
|---|---|---|---|---|
| summaries | `summaries.txt` | `kb.summaries` | numeric record id | existing |
| topics | `topics.txt` | `kb.topics` | numeric record id | existing |
| metrics | `metrics.txt` | `kb.metrics` | numeric `metrics.id` | new |
| scenes | `scenes.txt` | `kb.scene_objects` | `object_id` string | new |
| provisions | `provisions.txt` | `kb.provisions` | string provision id | existing |
| products | `products.txt` | `kb.products` | `product_rel_id` string | new |

---

## Bug fixes

### Node click selection always highlighted the first node (2026-05-25)

**Symptom:** Clicking any node in the Artifact Graph always selected the first
node instead of the clicked one.

**Root cause — `setPointerCapture` in `startStagePan`:**

`startStagePan` called `setPointerCapture` on the `graph-stage` `<div>` on
every `pointerdown`.  Pointer capture routes all subsequent pointer events
(including `pointerup`) to the capturing element, bypassing the ZRender canvas
element underneath.

ZRender's click handler (`Handler.js`) fires only when
`_downEl === _upEl`.  ZRender sets `_upEl` in its local `mouseup`/`pointerup`
listener, which is mounted directly on the ZRender canvas `<canvas>` element.
When pointer capture was active, the `pointerup` event was delivered to
`graph-stage` instead — ZRender's canvas listener never fired, `_upEl` was
never set (remained `undefined`), and the `_downEl !== _upEl` guard suppressed
every click.  The displayed `selectedNodeId` therefore never changed from its
initial value (`nodes[0].id`).

**Fix:** Removed the `setPointerCapture` call from `startStagePan`.
The existing `window.addEventListener('pointerup', handlePointerUp)` registered
in `onMount` already ensures `stopStagePan` is called on pointer release, so
pan tracking is unaffected.  The only behavioral change is that dragging past
the chart boundary no longer continues (no capture), which is acceptable.

**Secondary fix — `getRenderedNodePoint` wrong coordinate space:**

The original code called `group.transformCoordToGlobal(localX, localY)` where
`group` is the outer series-view group but `localX/Y` come from `_mainGroup`
(a child group offset by `layoutInfo.x/y`), introducing a systematic error.
It then subtracted page-level `stageRect.left/top` from the resulting
canvas-relative coordinates, compounding the error.

Fixed by using `seriesData.getItemGraphicEl(dataIndex).transformCoordToGlobal(0, 0)`:
the symbol element's accumulated world transform already incorporates all parent
offsets (series-view group roam transform → `_mainGroup` layout offset → element
position), and `transformCoordToGlobal` returns ZRender canvas-relative
coordinates directly comparable to `offsetX/offsetY` from the canvas element.

---

## What is not yet done

- `getArtifactCategoryCounts` is fetched by the frontend but currently only
  used to decide which groups have items (`count > 0`).  The count is not
  displayed in the UI.
- The `ArtifactCategoryPanel` loads all six groups unconditionally on mount.
  A lazy-load strategy (load only after the user expands a group) would reduce
  initial round-trips for categories with many artifact types.
- The `kb-topic-graph` and `kb-provision-graph` render blocks in `+page.svelte`
  can be removed once confirmed that no deep-link URLs point to those section IDs.
