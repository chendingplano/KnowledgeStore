# Semantic Projections Window — Implementation Notes

Companion to the `Semantic Projections` section in
[`+CAPSULE.md`](+CAPSULE.md). This document records **how** the Semantic
Projections Window is built and **why** the design landed where it did. The
window was created by adapting the
[Inventory Items Window](inventory-items-display-impl.md) as a template, so the
two share the same "archival reading room" layout, focus-mode behaviour, and
record-browser plumbing. This note focuses on what is *specific* to semantic
projections.

## Summary

The Semantic Projections Window is the management view for the rows produced by
the `extract_semantic_projections` doc processor (see the
[Extract Semantic Projection Spec](../doc-processor/extract-semantic-projection-spec.md)).
Like the Inventory Items Window, when the user clicks an item in the list the
main navigation panel and the record-list panel are both hidden and the view
enters **focus mode**: the full viewport is split between an **Information Panel**
(left, scrollable attribute list) and a **PDF Display Panel** (right, source
document).

The full UI lives in a single component:

- [`ChenWeb/web/src/lib/components/home3/semantic-projections-view.svelte`](../../../../ChenWeb/web/src/lib/components/home3/semantic-projections-view.svelte)

It reuses the same `KbInputRecordBrowser` / `PdfViewWindow` plumbing the rest of
the workbench shares, and a new `kb.semantic_projections` API in `kbService.ts`.

## Navigation placement

The window is registered as the `kb-semantic-projections` section in the
Knowledge workbench and is listed **immediately after “Artifact Wiki”** in the
Wiki menu group:

- [`ChenWeb/web/src/routes/home3/knowledge/+page.svelte`](../../../../ChenWeb/web/src/routes/home3/knowledge/+page.svelte)

Three touch points wire it in:

1. `'kb-semantic-projections'` is added to the `KbSectionId` union.
2. A `{ id: 'kb-semantic-projections', label: 'Semantic Projections', … }` menu
   entry is placed right after the `kb-summary-graph` (“Artifact Wiki”) entry.
3. A render branch mounts the view with the shared focus-mode fold callback:

   ```svelte
   {:else if activeSection === 'kb-semantic-projections'}
       <SemanticProjectionsView {darkMode} onFocusModeChange={handleExtractionFocusMode} />
   ```

`handleExtractionFocusMode` is the same callback Metrics, Scene Blocks, Products,
and Inventory Items use — it collapses the left menu while an item is on the
canvas and restores it on `goBack()`.

## Data source

The window is **read-only**. Semantic projections are produced by the doc
processor; there is no interactive add / extract / edit flow. As with the
Inventory Items template, the metric-creation machinery, the “Add / Edit / Delete
line” modes, and the global search panel were **not** carried over.

### Backend handler

A new handler serves the list endpoint:

- [`ChenWeb/server/api/kbhandler/semantic_projections_handler.go`](../../../../ChenWeb/server/api/kbhandler/semantic_projections_handler.go)

`ListSemanticProjections` answers `GET /api/v1/kb/semantic-projections?input_record_id=N`,
registered in [`routes.go`](../../../../ChenWeb/server/api/routes.go) right after
the `inventory-items` route:

```go
apiGroup.GET("/kb/semantic-projections", kbhandler.ListSemanticProjections)
```

It selects from `kb.semantic_projections` ordered by `id` and returns
`{ status, input_id, file_name, results, total }`. It reuses the package’s shared
helpers (`resolveInputTable`, `jsonArrayOrEmpty`, `errorResponse`) — the same
ones the inventory handler uses. Nullable `TEXT` columns are scanned through
`sql.NullString`; the JSONB columns (`keywords`, `keywords_en`, `category_paths`,
`category_paths_en`, `line_spans`) are passed through as `json.RawMessage`,
defaulting to `[]`.

The error-code prefix for this handler is `CWB_KB_SP_*`.

### Service layer

[`kbService.ts`](../../../../ChenWeb/web/src/lib/services/kbService.ts) gained:

```ts
export type SemanticCategoryNode = { name?: string; keywords?: string[]; confidence?: number };
export type SemanticCategoryPath = {
  category_path?: SemanticCategoryNode[];
  path_keywords?: string[];
  path_confidence?: number;
};

export type KbSemanticProjectionRecord = {
  id: number;
  semantic_proj_id: string;
  input_record_id?: number;
  event_id?: string;
  language?: string;
  descriptive_name?: string;
  descriptive_name_en?: string;
  keywords?: string[];
  keywords_en?: string[];
  semantic_projection?: string;
  semantic_projection_en?: string;
  category_paths?: SemanticCategoryPath[];
  category_paths_en?: SemanticCategoryPath[];
  line_spans?: SourceLineSpan[];
  model_name?: string;
  prompt_name?: string;
  create_time?: string;
};

export async function listKbSemanticProjections(inputRecordId: number): Promise<ListKbSemanticProjectionsResponse>;
```

`listKbSemanticProjections` calls
`GET /api/v1/kb/semantic-projections?input_record_id=N`. The response shape is
`{ status, input_id, file_name, results, total }`; the component reads `results`.
The record type mirrors the handler’s JSON exactly (note `id` is the DB row id
and `semantic_proj_id` is the `<record_id>_<level>_<seqno>` business key).

### Loading a record

`loadItemsForRecord(id)` fetches three things in parallel and resets all filters:

```ts
const [itemRes, inputRes, rawRes] = await Promise.all([
    listKbSemanticProjections(id),
    getKbInput(id).catch(() => null),
    getRawLines(id).catch(() => null)
]);
items = itemRes.results ?? [];
currentInput = inputRes?.record ?? null;
rawLines = rawRes?.lines ?? [];
```

`rawLines` are also used to resolve the compact `line_spans` arrays returned by
`kb.semantic_projections` into concrete `{ page_number, line_number }` refs for
the PDF viewer highlight overlay.

## Opening the Semantic Projection Window

Clicking an item card calls `selectItem(m)`:

```ts
async function selectItem(m: KbSemanticProjectionRecord) {
    selectedItemId = m.id;
    highlightSelectionVersion += 1;
    enterFocusMode();                 // hides the left panels
    const first = normalizeItemSpans(m)[0];
    if (first) docPage = first.page_number;
}
```

`enterFocusMode()` sets `recordBrowserFolded = true` and calls
`onFocusModeChange?.(true)`. The body grid collapses from its three-column layout
(`KbInputRecordBrowser` · item sidebar · right panel) to a single column, and the
`.right` section gains `.focus-split`, switching it to the flex-row that houses
the Information Panel, the resize handle, and the PDF panel. `Escape` calls
`goBack()` while focus mode is active.

`normalizeItemSpans` resolves the projection’s compact `line_spans` array
against the loaded raw lines, so selecting a projection jumps the PDF to the
first grounded page and enables the same highlight overlay the inventory window
uses.

## Layout of the Semantic Projection Window

```
.right.focus-split  (flex-direction: row)
├─ .metric-canvas-wrap          (flex: 1 1 0; min-width: 300px; overflow: hidden)
│  ├─ .canvas-toolbar           (toolbar strip — see Controls below)
│  └─ .metric-canvas            (overflow-y: auto; scrollable)
│     ├─ .attr-view             (when a projection is selected)
│     │  ├─ .attr-view-header   (descriptive name + category/language sub-label)
│     │  └─ .attr-group × 6    (one rounded card per group)
│     └─ .canvas-empty          (when no projection is selected)
├─ .focus-resize-handle         (draggable column resizer, flex: 0 0 14px)
└─ .doc-frame-wrap              (flex-basis: {focusPdfWidth}px)
   └─ <PdfViewWindow>           (source document, semantic-projection line highlights)
```

The CSS class names (`.metric-mgmt`, `.metric-canvas`, `.metric-sidebar`, …) are
inherited verbatim from the inventory/metric template; they are component-scoped,
so the reuse is cosmetic only.

### PDF / Information split sizing

The split is draggable. The PDF panel width is stored in `focusPdfWidth`
(default `round(window.innerWidth / 3)`) and persisted to
`localStorage["semantic-projections:focus-pdf-width"]`.

The clamp matches the inventory window: the upper bound is **75 % of the window**
(`window.innerWidth * 0.75`), not the fixed `FOCUS_PDF_MAX` constant, so the
Information Panel can always be dragged down to ~25 % of the window. As a floor,
`.metric-canvas-wrap` carries `min-width: 300px`.

## Controls in the Information Panel toolbar

The `.canvas-toolbar` strip runs across the top of the Information Panel:

### Back button

`goBack()` sets `recordBrowserFolded = false`, clears `selectedItemId`, and calls
`onFocusModeChange?.(false)`, restoring the three-column body layout.

### Filter by name (dropdown)

Lists every projection in the current record by `itemNameOf(m)` (descriptive name
→ descriptive name EN → `semantic_proj_id` → `Projection #id`). Selecting an
entry calls `selectItem()`. The select’s value is kept in sync with
`selectedItemId` via a `$effect`.

### Filter by keyword (text input)

Bound to `keywordFilter`. The `filteredItems` derivation keeps projections where
the (lowercased) keyword appears in `descriptive_name`, `descriptive_name_en`,
`semantic_projection`, `semantic_projection_en`, any `keywords` / `keywords_en`
entry, or any category-path node name. The datalist (`allKeywords`) is the union
of every keyword (both languages) and every category node name across the loaded
projections.

### Filter by category (text input)

Bound to `categoryFilter`, with a datalist of `allCategories` (the distinct
category-path node names in the record). Substring match against any node name in
the projection’s `category_paths` / `category_paths_en`. Category paths are the
primary axis of the semantic ontology, so they earn their own filter rather than
being folded into the keyword box.

### Filter by confidence (text input)

Bound to `confidenceFilter`. Same input grammar as the template: a plain number
shows projections with confidence **≥** that value; a `<N` prefix shows
projections **below** N. Because a projection has no single confidence field, the
threshold is compared against `maxPathConfidence(m)` — the highest
`path_confidence` across the projection’s `category_paths`. Datalist presets:
`0.90`–`0.50` and `<0.50`.

### Prev / Next buttons and position indicator

`prevItem` / `nextItem` are `$derived` from `filteredItems` and
`selectedItemInFilteredIndex`. Buttons disable at the boundary; the indicator
shows the 1-based position within the filtered list (e.g. `3 / 124`). All three
filters narrow the list that Prev / Next step through.

## Information Panel — attribute display

When a projection is selected, `.metric-canvas` renders a scrollable
`.attr-view`:

1. **Header** (`.attr-view-header`): the projection’s primary label
   (`itemNameOf`) in serif and a small monospace sub-label
   (`topCategoryName(m) || m.language`).
2. **Six group cards** (`.attr-group`): one rounded card per functional group,
   each with a brass header (icon · label · filled/total count) and a body of
   attribute rows.

Groups and their attributes (built by `buildItemGroupAttrs`):

| Group | Icon | Attributes |
|---|---|---|
| **Identity** | `HashIcon` | Projection ID, Descriptive Name, Descriptive Name (EN), Language |
| **Projection** | `FileTextIcon` | Projection (semantic_projection), Projection (EN) |
| **Keywords** | `TagIcon` | Keywords (chips), Keywords (EN) (chips) |
| **Categories** | `ListTreeIcon` | Category Paths (path cards), Category Paths (EN) (path cards) |
| **Grounding** | `ListIcon` | Lines (resolved from `line_spans`, shown with raw-line content when available) |
| **Provenance** | `ActivityIcon` | Model, Prompt, Event ID, Created |

Each attribute row uses one of three renderers driven by `AttrDef.kind`
(carried over from the template):

- **`text`** — a `gip-label` + `gip-val` pair on one line.
- **`chips`** — a `gip-label` above a row of `gip-chip` pill badges.
- **`lines`** — a `gip-label` above a stack of `gip-line-card` bordered cards.

Empty attributes render at reduced opacity but are **not hidden** — a dash (`—`)
marks the absence, and the layout is stable across projections.

### Projection text

`semantic_projection` (and its `_en` variant) are rendered with the **`lines`**
renderer, each wrapped as a single line card (head `Original` / `English`). The
line-card body wraps multi-line prose cleanly, which suits the longer projection
text better than the one-line `text` renderer.

### Category-path formatting

`category_paths` is an array of
`{ category_path: [{ name, keywords, confidence }], path_keywords, path_confidence }`.
Each path is flattened to one `lines` card by `pathEntries`:

- **head** — `path · NN%` when `path_confidence` is present (formatted by
  `confidencePct`), otherwise just `path`.
- **content** — the node names joined with ` › `, e.g. `Standards › Safety › Electrical`.

`category_paths_en` is rendered as a separate attribute with the same treatment.

## PDF Display Panel

The right side of the focus split is a `<PdfViewWindow>` showing the source
document. The viewer is configured **read-only**: `enableSelectionDialog={false}`,
and no `onselect` / `ondragmove` / editable selection bindings are passed. The
only toolbar snippet is the **Source Lines toggle**, which switches the right
panel between the PDF renderer and the raw-line text view (`linesView` snippet).
The lines view is display-only.

Semantic projections are still chunk-level artifacts (their id encodes
`<record_id>_<level>_<seqno>`), but they now persist compact `line_spans`.
`normalizeItemSpans` resolves those spans against the loaded raw lines, and
`selectedLinesByPage` feeds the resulting rectangles into the same PDF highlight
overlay the inventory window uses.

## Data model

```ts
type AttrKind = 'text' | 'chips' | 'lines';
type LineEntry = { head: string; content: string; lineType: string };
type AttrDef = {
  key: string; label: string; icon: any;
  kind: AttrKind; value: string; items: string[];
  entries: LineEntry[];
  count: number; hasValue: boolean;
};
type GroupNode = {
  key: string; label: string; icon: any;
  count: number; filledCount: number; hasValue: boolean;
  attrs: AttrDef[];
};
type ItemCanvas = {
  itemLabel: string; itemSubLabel: string;
  groups: GroupNode[];
};
```

`itemMap = $derived.by(...)` looks up the selected record, calls
`buildItemGroupAttrs`, and assembles the six `GroupNode`s. As with the inventory
view, `ItemCanvas` is text-only — no SVG/radial geometry is retained.

Helper functions specific to this view:

- `pathNodeNames(p)` — the non-empty `name`s of a category path, in order.
- `categoryNamesOf(m)` — the distinct node names across both language variants
  (drives the keyword/category datalists and the category filter).
- `maxPathConfidence(m)` — the highest `path_confidence` on a record (drives the
  card score and the confidence filter).
- `topCategoryName(m)` — the leaf name of the highest-confidence path (the card
  chip and the header sub-label).
- `pathCount(m)` — number of `category_paths` (the card’s span-style badge).

## Differences from the Inventory Items template

| Aspect | Inventory Items Window | Semantic Projections Window |
|---|---|---|
| Data origin | Doc processor (read-only) | Doc processor (read-only) |
| Source-line grounding | Present (`source_line_spans`, highlights) | Present (`line_spans`, highlights) |
| PDF highlights | Per-item line highlights | Per-projection line highlights |
| Attribute groups | Identity · Maker · Specifications · Validation · Grounding | Identity · Projection · Keywords · Categories · Grounding · Provenance |
| Confidence | Top-level `confidence` field | Derived `maxPathConfidence` over category paths |
| Bilingual fields | — | `_en` variants for name / keywords / projection / paths |
| Card badge | `N spans` | `N paths` |
| localStorage key | `inventory-items:focus-pdf-width` | `semantic-projections:focus-pdf-width` |

## File map

- [`semantic-projections-view.svelte`](../../../../ChenWeb/web/src/lib/components/home3/semantic-projections-view.svelte)
  — Everything described here lives in this one component.
- [`inventory-items-view.svelte`](../../../../ChenWeb/web/src/lib/components/home3/inventory-items-view.svelte)
  — The template this view was adapted from.
- [`semantic_projections_handler.go`](../../../../ChenWeb/server/api/kbhandler/semantic_projections_handler.go)
  — `ListSemanticProjections` list endpoint.
- [`routes.go`](../../../../ChenWeb/server/api/routes.go)
  — Route registration (after `inventory-items`).
- [`kbService.ts`](../../../../ChenWeb/web/src/lib/services/kbService.ts)
  — `KbSemanticProjectionRecord` / `SemanticCategoryPath` shapes and `listKbSemanticProjections`.
- [`knowledge/+page.svelte`](../../../../ChenWeb/web/src/routes/home3/knowledge/+page.svelte)
  — Menu registration (after “Artifact Wiki”) and render branch.

## Maintenance notes

- **Adding an attribute to an existing group**: extend the relevant array in
  `buildItemGroupAttrs`. The text view auto-renders the new row based on `kind`.
- **Adding a new group**: append a `GroupSpec` to the `groupSpecs` array inside
  `itemMap`, with its attribute array from `buildItemGroupAttrs`. The text view
  picks it up automatically.
- **Adjusting the PDF/Information split floor**: the JS clamp
  (`window.innerWidth * 0.75`) sets the ~25 % minimum for the Information Panel;
  `.metric-canvas-wrap { min-width }` sets the hard px floor (currently 300 px).
- **Resizing the PDF panel default**: delete
  `localStorage["semantic-projections:focus-pdf-width"]` to revert to the
  `round(window.innerWidth / 3)` first-load default.
- **English-only documents**: the processor does not generate the `_en` fields
  for English originals (see the spec). The `_en` attributes then render empty
  (dashed) rather than duplicating the originals.

## References

- [Inventory Items Window — Implementation Notes](inventory-items-display-impl.md) (template)
- [Extract Semantic Projection Processor — Spec](../doc-processor/extract-semantic-projection-spec.md)
- [Knowledge Base Window Capsule](+CAPSULE.md)
