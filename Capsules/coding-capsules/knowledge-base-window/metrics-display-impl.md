# Metric Window (Focus Mode) — Implementation Notes

Companion to the `Metrics` section in
[`+CAPSULE.md`](+CAPSULE.md). This document records **how** the Metric Window is
built and **why** the design landed where it did, across five iterations.

## Summary

When the user clicks a metric in the `kb.metrics` list, the main navigation panel
and the record-list panel are both hidden and the view enters **focus mode**: the
full viewport is split between an **Information Panel** (left, scrollable attribute
list) and a **PDF Display Panel** (right, source document with line highlights).

The full UI lives in a single component:

- [`ChenWeb/web/src/lib/components/home3/metric-mgmt-view.svelte`](../../../../ChenWeb/web/src/lib/components/home3/metric-mgmt-view.svelte)

It uses the same `kb.metrics` API and `KbInputRecordBrowser` / `PdfViewWindow`
plumbing the rest of the workbench shares.

## Opening the Metric Window

Clicking a metric card calls `selectMetric(m)`:

```ts
async function selectMetric(m: KbMetricRecord) {
    selectedMetricId = m.id;
    highlightSelectionVersion += 1;
    enterFocusMode();                  // hides the left panels
    const first = normalizeMetricSpans(m)[0];
    if (first) docPage = first.page_number; // jump PDF to source page
}

function enterFocusMode() {
    recordBrowserFolded = true;
    onFocusModeChange?.(true);
}
```

`recordBrowserFolded = true` has two effects:

1. The `.body` grid collapses from its three-column layout
   (`KbInputRecordBrowser` · metric sidebar · right panel) to a single column
   (`minmax(0, 1fr)`), hiding both the record browser and the metric sidebar.
2. The `.right` section gains the `.focus-split` class, switching it to a
   flex-row that houses the Information Panel, the resize handle, and the PDF panel.

The `Escape` key also calls `goBack()` when focus mode is active.

## Layout of the Metric Window

```
.right.focus-split  (flex-direction: row)
├─ .metric-canvas-wrap          (flex: 1 1 0; min-width: 0; overflow: hidden)
│  ├─ .canvas-toolbar           (toolbar strip — see Controls below)
│  └─ .metric-canvas            (overflow-y: auto; scrollable)
│     ├─ .attr-view             (when a metric is selected)
│     │  ├─ .attr-view-header   (metric name + optional sub-label)
│     │  ├─ .attr-group × 5    (one rounded card per group)
│     │  │  ├─ .attr-group-head (icon · label · filled/total count)
│     │  │  └─ .attr-group-body (attribute rows — see Attribute groups)
│     │  └─ …
│     └─ .canvas-empty          (when no metric is selected)
├─ .focus-resize-handle         (draggable column resizer, flex: 0 0 14px)
└─ .doc-frame-wrap              (flex: 0 0 {focusPdfWidth}px)
   └─ <PdfViewWindow>           (source document with source-line highlights)
```

The split between the two panels is draggable. The PDF panel width is stored in
`focusPdfWidth` (default: `round(window.innerWidth / 3)`), clamped to
`[280, 1460]`, and persisted to `localStorage["metrics:focus-pdf-width"]`.

## Controls in the Information Panel toolbar

The `.canvas-toolbar` strip runs across the top of the Information Panel and
contains the following controls, left to right:

### Back button

```svelte
<button class="toolbar-back" onclick={goBack}>
    <ArrowLeftIcon /> Back
</button>
```

`goBack()` sets `recordBrowserFolded = false`, clears `selectedMetricId`, and
calls `onFocusModeChange?.(false)`. This restores the three-column body layout
and re-displays both the record browser and the metric sidebar.

### Filter by name (dropdown)

```svelte
<select class="toolbar-select" value={metricNameDropdownValue}
        onchange={handleMetricNameDropdown}>
    <option value="">— Metric by name —</option>
    {#each metrics as m}
        <option value={m.id}>{metricNameOf(m)}</option>
    {/each}
</select>
```

Lists every metric in the current record. Selecting an entry calls
`handleMetricNameDropdown()` → `selectMetric()`. The select's `value` is kept in
sync with `selectedMetricId` via a `$effect`, so it always reflects whichever
metric is displayed — whether it was opened from this dropdown, the card list, or
the Prev / Next buttons.

### Filter by keyword (text input)

```svelte
<input class="toolbar-kw-input" type="text"
       list="metric-keywords-datalist-focus"
       bind:value={keywordFilter} />
```

Bound to `keywordFilter`. The `filteredMetrics` derivation retains only metrics
where `keywordFilter` (lowercased) appears in `metric_keywords`,
`metric_keywords_en`, `metric_name`, or `metric_subject`. The datalist is
populated from `allKeywords` — the union of every keyword across all loaded
metrics. A clear button (×) appears while the field is non-empty.

### Filter by confidence (text input)

```svelte
<input class="toolbar-kw-input" type="text"
       list="confidence-options"
       bind:value={confidenceFilter} />
<datalist id="confidence-options">
    <option value="0.90"></option>
    <option value="0.80"></option>
    <option value="0.70"></option>
    <option value="0.60"></option>
    <option value="0.50"></option>
    <option value="<0.50"></option>
</datalist>
```

Bound to `confidenceFilter`. The datalist provides six presets but free-form
numeric entry is allowed (e.g. `0.85`). Parsing logic in `filteredMetrics`:

```ts
if (cf.startsWith('<')) {
    result = result.filter((m) => (m.confidence ?? 0) < parseFloat(cf.slice(1)));
} else {
    result = result.filter((m) => (m.confidence ?? 0) >= parseFloat(cf));
}
```

Plain number → show metrics with confidence **≥** that value.
`<N` prefix → show metrics with confidence **below** N.
A clear button (×) appears while the field is non-empty.

### Prev / Next buttons and position indicator

```svelte
<button class="toolbar-nav-btn" disabled={!prevMetric}
        onclick={goToPrevMetric}>
    <ChevronLeftIcon />
</button>
<span class="toolbar-nav-pos">
    {selectedMetricInFilteredIndex >= 0
        ? `${selectedMetricInFilteredIndex + 1} / ${filteredMetrics.length}`
        : `— / ${filteredMetrics.length}`}
</span>
<button class="toolbar-nav-btn" disabled={!nextMetric}
        onclick={goToNextMetric}>
    <ChevronRightIcon />
</button>
```

`prevMetric` and `nextMetric` are `$derived` from `filteredMetrics` and
`selectedMetricInFilteredIndex`. Both buttons are disabled at the boundary.
The position indicator shows the 1-based position within the currently filtered
list, e.g. `3 / 12`. Both keyword and confidence filters narrow the list that
Prev / Next step through.

## Information Panel — attribute display

When a metric is selected, the `.metric-canvas` area renders a scrollable
`.attr-view` with:

1. **Header** (`.attr-view-header`): the metric's primary label (`metric_name`,
   falling back to `metric_subject` or `Metric #id`) in serif, and the
   English sub-label below it in small monospace if present.
2. **Five group cards** (`.attr-group`): one rounded card per functional group,
   each with a brass header row and a body of attribute rows.

Groups and their attributes:

| Group | Icon | Attributes |
|---|---|---|
| **Metadata** | `BookOpenIcon` | ID, Name, Confidence, Desc, Formula, Explicit |
| **Context** | `TagIcon` | Section, Context, Keywords |
| **Metric** | `TrendingUpIcon` | Subject, Frequency, Value, Threshold, Unit, Class, Data Type, Range Type, Location |
| **Reasoning** | `ActivityIcon` | Tags |
| **Grounding** | `MapPinIcon` | Lines (source line cards) |

Each attribute row uses one of three renderers driven by `AttrDef.kind`:

- **`text`** — a `gip-label` + `gip-val` pair on one line.
- **`chips`** — a `gip-label` above a row of `gip-chip` pill badges
  (`metric_keywords`, `reasoning_tags`).
- **`lines`** — a `gip-label` above a stack of `gip-line-card` bordered cards,
  one per `LineEntry { head, content, lineType }`. The head shows
  `L<line> · P<page>` in brass monospace; a pill-shaped `line_type` tag follows
  if present. Multi-paragraph content is split on `\n` so each paragraph becomes
  its own card.

Empty attributes render at reduced opacity but are **not hidden** — a dash (`—`)
marks the absence, and the layout is stable across metrics.

## PDF Display Panel

The right side of the focus split is a `<PdfViewWindow>` showing the source
document. When a metric is selected the viewer jumps to the page of the first
source span (`docPage = first.page_number`). Matched source lines are highlighted
in the PDF via `renderMetricHighlights` using the `selectedLinesByPage` map built
from `normalizeMetricSpans` + `rawLineByKey`.

The PdfViewWindow toolbar exposes additional actions via snippets:
- **Edit / Delete / Add line** buttons (operate on raw source lines).
- **Source Lines toggle** — switches the right panel between the PDF renderer and
  a raw-line text view (`linesView` snippet).

## Data model

The attribute computation works off `KbMetricRecord` and the loaded `RawLine[]`.
Core types:

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
  // x, y, wire, satellites — computed by metricsMap but not rendered
  attrs: AttrDef[];
};
type MetricsCanvas = {
  W: number; H: number; /* geometry fields — computed but unused by v5 template */
  metricLabel: string; metricSubLabel: string;
  groups: GroupNode[];
};
```

`buildMetricGroupAttrs` populates each group from the selected `KbMetricRecord`.
`metricsMap = $derived.by(...)` assembles the canvas and geometry — the geometry
fields (`Rc`, `Rgn`, `Rsn`, `x`, `y`, `wire`, `satellites`) are retained in the
derived object but are not consumed by the v5 template.

## Design evolution

| Version | What it was | Why it was changed |
|---|---|---|
| **v1: two-entity satellite map** | Metric circle + Source Doc circle, 5 attribute satellites each. | Most of the 24 metric fields were invisible. |
| **v2: tree-graph with pill leaves** | 5 group satellites with property pills as leaves. Bilingual fields merged. | Pills overlapped; Context column pushed off-canvas at narrow widths. |
| **v3: radial hub-and-spoke** | Single metric disc, 5 group circles at 72° spacing, attribute satellites fanning off each group. Click a group → info panel overlay. | Coherent layout; click-to-inspect reduces visual noise. |
| **v4: attribute cleanup** | Bilingual merging removed (`joinPair` / `mergedChips` deleted). | Users preferred raw extracted value; `zh / en` separator was noise. |
| **v5: text attribute list** | Radial SVG chart replaced by a scrollable vertical list of rounded group cards. All attributes visible at once; no click required. | Chart layout wasted space at the available widths; text list is scannable and requires no interaction to read all values. |

## Things removed in v5

From the **template** (SVG chart and overlay):
- `<svg class="canvas-wires">` — spoke and leaf wires
- `<button class="metric-node">` — center metric disc
- `<button class="group-node-circle">` — five group circles
- `.sat-node` buttons, `.sat-label` and `.sat-badge` elements — attribute satellites
- `<aside class="canvas-legend">` — map legend
- `<aside class="group-info-panel">` — click-driven overlay panel and its resize handle

From the **CSS** (no longer needed):
`.canvas-wires`, `.wire`, `.wire.spoke`, `.canvas-node`, `.main-node`,
`.metric-node`, `.group-node-circle`, `.sat-node`, `.sat-badge`, `.sat-label`,
`.canvas-legend`, `.legend-h`, `.legend-row`, `.legend-hint`,
`.group-info-panel`, `.gip-head`, `.gip-ic`, `.gip-title`, `.gip-count`,
`.gip-close`, `.gip-section-head`, `.gip-resize-handle`, `.gip-resize-grip`,
`.main-node-cap`, `.main-node-label`, `.main-node-sublabel`.

Note: the `.gip-row`, `.gip-label`, `.gip-val`, `.gip-chips`, `.gip-chip`,
`.gip-line-card`, `.gip-line-body`, etc. styles are **retained** — the v5 text
view reuses them for attribute rows inside each `.attr-group-body`.

State and helpers still present in the script but no longer consumed by the
template: `hoveredCanvasAttr`, `activeGroupKey`, `activeGroup`,
`showAllMetricAttrs`, `totalAttrCount`, `hoveredSatelliteInfo`, `gipWidth`,
`gipResizing`, `startGipResize`, `onGipResizerKeydown`, `ALL_METRIC_KEY`.

## File map

- [`metric-mgmt-view.svelte`](../../../../ChenWeb/web/src/lib/components/home3/metric-mgmt-view.svelte)
  — Everything described here lives in this one component.
- [`kb-extraction-view.svelte`](../../../../ChenWeb/web/src/lib/components/home3/kb-extraction-view.svelte)
  — Reference for the Scene-Blocks-style radial chart (the pattern that v3
  followed; still in use in that view).
- [`kbService.ts`](../../../../ChenWeb/web/src/lib/services/kbService.ts)
  — `KbMetricRecord` shape, `listKbMetrics`, `SourceLineSpan`.

## Maintenance notes

- **Adding an attribute to an existing group**: extend the array in
  `buildMetricGroupAttrs`. The text view auto-renders the new row based on
  `kind`. No template changes needed.
- **Adding a new group**: append a `GroupSpec` to `groupSpecs` in `metricsMap`,
  add its attribute array to `buildMetricGroupAttrs`, and add it to
  `buildMetricGroupAttrs`'s return type. The text view picks it up automatically.
- **Adjusting confidence filter presets**: edit the `<datalist id="confidence-options">`
  options. The `filteredMetrics` derivation handles any numeric value.
- **Cleaning up unused v5 state**: `hoveredCanvasAttr`, `activeGroupKey`, and
  related chart state can be removed once it is confirmed no future iteration
  will reintroduce the radial chart. They are harmless but add noise.
- **Resizing the PDF panel**: `localStorage["metrics:focus-pdf-width"]` stores the
  last dragged width. Delete it to revert to the `round(window.innerWidth / 3)`
  first-load default.
