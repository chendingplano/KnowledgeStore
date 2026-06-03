# Inventory Items Window — Implementation Notes

Companion to the `Inventory Items` section in
[`+CAPSULE.md`](+CAPSULE.md). This document records **how** the Inventory Items
Window is built and **why** the design landed where it did. The window was
created by adapting the
[Metric Window](metrics-display-impl.md) as a template, so the two share the same
"archival reading room" layout, focus-mode behaviour, and source-grounding
plumbing. This note focuses on what is *specific* to inventory items.

## Summary

The Inventory Items Window is the management view for the rows produced by the
`extract_inventory_items` doc processor (see the
[Extract Inventory Items Spec](../doc-processor/extract-inventory-items-spec.md)).
Like the Metric Window, when the user clicks an item in the list the main
navigation panel and the record-list panel are both hidden and the view enters
**focus mode**: the full viewport is split between an **Information Panel** (left,
scrollable attribute list) and a **PDF Display Panel** (right, source document
with line highlights).

The full UI lives in a single component:

- [`ChenWeb/web/src/lib/components/home3/inventory-items-view.svelte`](../../../../ChenWeb/web/src/lib/components/home3/inventory-items-view.svelte)

It reuses the same `KbInputRecordBrowser` / `PdfViewWindow` plumbing the rest of
the workbench shares, and a new `kb.inventory_items` API in `kbService.ts`.

## Navigation placement

The window is registered as the `kb-inventory-items` section in the Knowledge
workbench and is listed **immediately after “Provisions”** in the Wiki menu
group:

- [`ChenWeb/web/src/routes/home3/knowledge/+page.svelte`](../../../../ChenWeb/web/src/routes/home3/knowledge/+page.svelte)

Three touch points wire it in:

1. `'kb-inventory-items'` is added to the `KbSectionId` union.
2. An `{ id: 'kb-inventory-items', label: 'Inventory Items', … }` menu entry is
   placed right after the `kb-provision-tree` (“Provisions”) entry.
3. A render branch mounts the view with the shared focus-mode fold callback:

   ```svelte
   {:else if activeSection === 'kb-inventory-items'}
       <InventoryItemsView {darkMode} onFocusModeChange={handleExtractionFocusMode} />
   ```

`handleExtractionFocusMode` is the same callback Metrics, Scene Blocks, and
Products use — it collapses the left menu while an item is on the canvas and
restores it on `goBack()`.

## Data source

The window is **read-only**. Inventory items are produced by the doc processor;
there is no interactive add / extract / edit flow (unlike the Metric Window,
which still carries metric-creation machinery). Accordingly the metric-specific
extraction dialog, the “Add / Edit / Delete line” modes, and the global search
panel were **not** carried over.

### Service layer

[`kbService.ts`](../../../../ChenWeb/web/src/lib/services/kbService.ts) gained:

```ts
export type InventoryItemSpec = { name?: string; value?: string | number; unit?: string };

export type KbInventoryItemRecord = {
  id: number;
  inventory_item_id: string;
  input_record_id?: number;
  item_name?: string;
  canonical_name?: string;
  item_category?: string;
  manufacturer?: string;
  brand?: string;
  model_number?: string;
  part_number?: string;
  normalized_specs?: InventoryItemSpec[];
  raw_specs?: InventoryItemSpec[];
  standards?: string[];
  aliases?: string[];
  evidence_quote?: string;
  source_line_spans?: SourceLineSpan[];
  validation_flags?: string[];
  missing_required_attrs?: string[];
  dedupe_key?: string;
  schema_version?: string;
  dictionary_version?: string;
  confidence?: number;
  confidence_reason?: string;
  model_name?: string;
  prompt_name?: string;
  create_time?: string;
  modify_time?: string;
};

export async function listKbInventoryItems(inputRecordId: number): Promise<ListKbInventoryItemsResponse>;
```

`listKbInventoryItems` calls `GET /api/v1/kb/inventory-items?input_record_id=N`,
served by `kbhandler.ListInventoryItems`. The response shape is
`{ status, input_id, file_name, results, total }`; the component reads
`results`. The record type mirrors the handler’s JSON exactly (note `id` is the
DB row id and `inventory_item_id` is the `<record_id>_i_<seqno>` business key).

### Loading a record

`loadItemsForRecord(id)` fetches three things in parallel and resets all filters:

```ts
const [itemRes, inputRes, rawRes] = await Promise.all([
    listKbInventoryItems(id),
    getKbInput(id).catch(() => null),
    getRawLines(id).catch(() => null)
]);
items = itemRes.results ?? [];
currentInput = inputRes?.record ?? null;
rawLines = rawRes?.lines ?? [];
```

`rawLines` are needed both to render the **Source Lines** view and to resolve
each item’s line-number spans to page numbers for PDF highlighting.

## Opening the Inventory Item Window

Clicking an item card calls `selectItem(m)`:

```ts
async function selectItem(m: KbInventoryItemRecord) {
    selectedItemId = m.id;
    highlightSelectionVersion += 1;
    enterFocusMode();                 // hides the left panels
    const first = normalizeItemSpans(m)[0];
    if (first) docPage = first.page_number; // jump PDF to source page
}
```

`enterFocusMode()` sets `recordBrowserFolded = true` and calls
`onFocusModeChange?.(true)`. The body grid collapses from its three-column layout
(`KbInputRecordBrowser` · item sidebar · right panel) to a single column, and the
`.right` section gains `.focus-split`, switching it to the flex-row that houses
the Information Panel, the resize handle, and the PDF panel. `Escape` calls
`goBack()` while focus mode is active.

## Layout of the Inventory Item Window

```
.right.focus-split  (flex-direction: row)
├─ .metric-canvas-wrap          (flex: 1 1 0; min-width: 300px; overflow: hidden)
│  ├─ .canvas-toolbar           (toolbar strip — see Controls below)
│  └─ .metric-canvas            (overflow-y: auto; scrollable)
│     ├─ .attr-view             (when an item is selected)
│     │  ├─ .attr-view-header   (item name + category sub-label)
│     │  └─ .attr-group × 5    (one rounded card per group)
│     └─ .canvas-empty          (when no item is selected)
├─ .focus-resize-handle         (draggable column resizer, flex: 0 0 14px)
└─ .doc-frame-wrap              (flex-basis: {focusPdfWidth}px)
   └─ <PdfViewWindow>           (source document with source-line highlights)
```

The CSS class names (`.metric-mgmt`, `.metric-canvas`, `.metric-sidebar`, …) are
inherited verbatim from the metric template; they are component-scoped, so the
reuse is cosmetic only.

### PDF / Information split sizing

The split is draggable. The PDF panel width is stored in `focusPdfWidth`
(default `round(window.innerWidth / 3)`) and persisted to
`localStorage["inventory-items:focus-pdf-width"]`.

The **clamp is the important detail** and differs from a naive port of the
template:

```ts
function clampFocusPdfWidth(value: number) {
    if (!Number.isFinite(value)) return FOCUS_PDF_DEFAULT;
    const maxPdf = browser ? Math.round(window.innerWidth * 0.75) : FOCUS_PDF_MAX;
    return Math.max(FOCUS_PDF_MIN, Math.min(maxPdf, Math.round(value)));
}
```

The upper bound is **75 % of the window**, not the fixed `FOCUS_PDF_MAX = 1460`
px constant. On a wide (e.g. 4K) monitor a fixed 1460 px cap is only ~50 % of the
panel, which left the Information Panel unable to shrink below ~50 %. Bounding by
`window.innerWidth * 0.75` guarantees the Information Panel can always be dragged
down to ~25 % of the window. As a floor, `.metric-canvas-wrap` carries
`min-width: 300px`. This matches the Provisions window’s behaviour.

## Controls in the Information Panel toolbar

The `.canvas-toolbar` strip runs across the top of the Information Panel:

### Back button

`goBack()` sets `recordBrowserFolded = false`, clears `selectedItemId`, and calls
`onFocusModeChange?.(false)`, restoring the three-column body layout.

### Filter by name (dropdown)

Lists every item in the current record by `itemNameOf(m)` (canonical name →
item name → `inventory_item_id` → `Item #id`). Selecting an entry calls
`selectItem()`. The select’s value is kept in sync with `selectedItemId` via a
`$effect`.

### Filter by keyword (text input)

Bound to `keywordFilter`. The `filteredItems` derivation keeps items where the
(lowercased) keyword appears in `item_name`, `canonical_name`, `item_category`,
`manufacturer`, `brand`, or any `aliases` entry. The datalist is populated from
`allKeywords` — the union of every `item_category` and alias across the loaded
items. A clear (×) button appears while non-empty.

### Filter by category (text input)

Bound to `categoryFilter`, with a datalist of `allCategories` (the distinct
`item_category` values in the record). Substring match against `item_category`.
This control is the inventory-specific addition — `item_category` is the primary
axis of the ontology (see the spec’s two-layer category model), so it earns its
own filter rather than being folded into the keyword box.

### Filter by confidence (text input)

Bound to `confidenceFilter`. Identical semantics to the Metric Window: a plain
number shows items with confidence **≥** that value; a `<N` prefix shows items
**below** N. Datalist presets: `0.90`–`0.50` and `<0.50`.

### Prev / Next buttons and position indicator

`prevItem` / `nextItem` are `$derived` from `filteredItems` and
`selectedItemInFilteredIndex`. Buttons disable at the boundary; the indicator
shows the 1-based position within the filtered list (e.g. `3 / 124`). All three
filters narrow the list that Prev / Next step through.

## Information Panel — attribute display

When an item is selected, `.metric-canvas` renders a scrollable `.attr-view`:

1. **Header** (`.attr-view-header`): the item’s primary label in serif and the
   `item_category` as a small monospace sub-label.
2. **Five group cards** (`.attr-group`): one rounded card per functional group,
   each with a brass header (icon · label · filled/total count) and a body of
   attribute rows.

Groups and their attributes (built by `buildItemGroupAttrs`):

| Group | Icon | Attributes |
|---|---|---|
| **Identity** | `HashIcon` | Item ID, Item Name, Canonical, Category |
| **Maker** | `FactoryIcon` | Manufacturer, Brand, Model #, Part # |
| **Specifications** | `TrendingUpIcon` | Normalized (chips), Raw Specs (chips), Standards (chips), Aliases (chips) |
| **Validation** | `ActivityIcon` | Confidence, Reason, Flags (chips), Missing (chips), Dedupe Key |
| **Grounding** | `MapPinIcon` | Evidence (quote card), Lines (source line cards) |

Each attribute row uses one of three renderers driven by `AttrDef.kind`
(carried over from the metric template):

- **`text`** — a `gip-label` + `gip-val` pair on one line.
- **`chips`** — a `gip-label` above a row of `gip-chip` pill badges.
- **`lines`** — a `gip-label` above a stack of `gip-line-card` bordered cards,
  one per `LineEntry { head, content, lineType }`. The head shows
  `L<line> · P<page>` in brass monospace; multi-paragraph content is split on
  `\n` so each paragraph becomes its own card.

Empty attributes render at reduced opacity but are **not hidden** — a dash (`—`)
marks the absence, and the layout is stable across items.

### Spec formatting

`normalized_specs` and `raw_specs` are arrays of `{ name, value, unit }`. They are
flattened to chip strings by `fmtSpec`:

```ts
function fmtSpec(spec) {
    const rhs = [value, unit].filter(Boolean).join(' ');
    return name && rhs ? `${name}: ${rhs}` : (name || rhs);
}
```

So `{ name: "power", value: 1500, unit: "w" }` renders as the chip `power: 1500 w`.

### Evidence vs. Grounding lines

The **Grounding** group carries two `lines` attributes:

- **Evidence** — the single `evidence_quote` string, wrapped as one line card.
- **Lines** — the resolved `source_line_spans`, each rendered as a card showing
  the parsed line content from `rawLines`.

## PDF Display Panel

The right side of the focus split is a `<PdfViewWindow>` showing the source
document. When an item is selected the viewer jumps to the page of the first
source span. Matched source lines are highlighted via `renderItemHighlights`
using the `selectedLinesByPage` map built from `normalizeItemSpans` +
`rawLineByKey`.

The viewer is configured **read-only**: `enableSelectionDialog={false}`, and no
`onselect` / `ondragmove` / `selectedLines` bindings are passed. The only toolbar
snippet is the **Source Lines toggle**, which switches the right panel between the
PDF renderer and the raw-line text view (`linesView` snippet). The lines view is
display-only — the metric template’s edit / delete / add-line buttons are omitted.

### Span normalization

`source_line_spans` use line-number spans only (`"12"`, `"13-15"`). Page numbers
are resolved through `lineNumToPage`, built from the loaded raw lines.
`normalizeItemSpans` accepts strings (single or `start[-:,]end` ranges, capped at
+200 lines), bare numbers, and `{ line_number }` objects — the same parser as the
Metric Window. `spanCount` counts spans (expanding ranges) for the card footer
badge.

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
`buildItemGroupAttrs`, and assembles the five `GroupNode`s. Unlike the metric
template’s `MetricsCanvas`, **no SVG geometry fields are retained** — the
inventory view was built directly on the v5 text-list design, so there is no
radial-chart vestige to carry.

## Differences from the Metric Window template

| Aspect | Metric Window | Inventory Items Window |
|---|---|---|
| Data origin | Interactive + processor | Doc processor only (read-only) |
| Add / extract / edit | Present (extract, save, provision dialog) | Removed |
| Global search panel | Present (`searchKbMetrics`) | Removed |
| Line edit/delete/add modes | Present | Removed (lines view is display-only) |
| Extra filter | — | **Category** filter (item_category) |
| PDF width cap | `FOCUS_PDF_MAX` (1460 px) | `window.innerWidth * 0.75` (+ 300 px floor) |
| Canvas geometry | `MetricsCanvas` retains unused SVG fields | `ItemCanvas` is text-only |
| localStorage key | `metrics:focus-pdf-width` | `inventory-items:focus-pdf-width` |

## File map

- [`inventory-items-view.svelte`](../../../../ChenWeb/web/src/lib/components/home3/inventory-items-view.svelte)
  — Everything described here lives in this one component.
- [`metric-mgmt-view.svelte`](../../../../ChenWeb/web/src/lib/components/home3/metric-mgmt-view.svelte)
  — The template this view was adapted from.
- [`kbService.ts`](../../../../ChenWeb/web/src/lib/services/kbService.ts)
  — `KbInventoryItemRecord` / `InventoryItemSpec` shapes and `listKbInventoryItems`.
- [`knowledge/+page.svelte`](../../../../ChenWeb/web/src/routes/home3/knowledge/+page.svelte)
  — Menu registration (after “Provisions”) and render branch.

## Maintenance notes

- **Adding an attribute to an existing group**: extend the array in
  `buildItemGroupAttrs`. The text view auto-renders the new row based on `kind`.
- **Adding a new group**: append a `GroupSpec` to the `groupSpecs` array inside
  `itemMap`, with its attribute array from `buildItemGroupAttrs`. The text view
  picks it up automatically.
- **Adjusting the PDF/Information split floor**: the JS clamp
  (`window.innerWidth * 0.75`) sets the ~25 % minimum for the Information Panel;
  `.metric-canvas-wrap { min-width }` sets the hard px floor (currently 300 px).
- **Resizing the PDF panel default**: delete
  `localStorage["inventory-items:focus-pdf-width"]` to revert to the
  `round(window.innerWidth / 3)` first-load default.
- **`category_status` (pending_review / approved):** the list API does not yet
  return the read-path `category_status` join from `kb.inventory_categories`. If
  surfaced later, it would slot naturally into the **Identity** or **Validation**
  group as a `text` attribute.

## References

- [Metric Window — Implementation Notes](metrics-display-impl.md) (template)
- [Provisions Window — Implementation Notes](provisions-display-impl.md)
- [Extract Inventory Items Processor — Spec](../doc-processor/extract-inventory-items-spec.md)
- [Knowledge Base Window Capsule](+CAPSULE.md)
