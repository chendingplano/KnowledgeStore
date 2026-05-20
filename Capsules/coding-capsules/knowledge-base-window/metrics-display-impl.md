# Metric Chart (Focus Mode) — Implementation Notes

Companion to the `Metrics` section in
[`+CAPSULE.md`](+CAPSULE.md). This document records **how** the metric chart is
built and **why** the design landed where it did, after two rounds of iteration
that ended on a Scene-Blocks-style radial layout.

## Summary

When the user selects a metric in `Subject Wiki → Metrics`, the right pane
enters focus mode: the metric and the source PDF go side-by-side. The metric
side is a **radial attribute map** modeled after the Scene Blocks chart, with
a click-driven info panel for inspecting any group's attribute values.

The full UI is in a single component:

- [`ChenWeb/web/src/lib/components/home3/metric-mgmt-view.svelte`](../../../../ChenWeb/web/src/lib/components/home3/metric-mgmt-view.svelte)

It uses the same `kb.metrics` API and `KbInputRecordBrowser` / `PdfViewWindow`
plumbing the rest of the workbench shares; only the chart and the info panel
are bespoke to this view.

## Design evolution

The current layout is the third iteration of the chart, with a subsequent
cleanup pass that removed bilingual merging. The intermediate versions are
worth recording because they explain why some pieces (geometry helpers, hook
up to PDF resize) survived while others (property pills, source-doc circle,
bilingual merging, metadata panel) were removed.

| Version | What it was | Why it was changed |
|---|---|---|
| **v1: two-entity satellite map** | Metric circle on the left, Source Doc circle on the right, 5 attribute satellites around each (Name / Confidence / Value / Location / Keywords; Title / Type / Doc No / File / Date). | Each satellite showed only one preselected attribute. Most of the metric's 24 fields were invisible. |
| **v2: tree-graph with pill leaves** | Same two-entity layout, but the metric side grew 5 *group satellites* (Metadata / Context / Metric / Reasoning / Grounding), each with property pills as leaves connected by edges. Bilingual fields were merged. | Pills overlapped each other in dense groups and pushed the left-stack Context column off-canvas at narrow widths. Visual noise outweighed the information density gain. |
| **v3: Scene-Blocks-style radial** | Single metric disc in the center, 5 group circles at 72° spacing, attribute satellites fanning off each group. No source-doc circle. Click a group to open a formatted info panel. | Reads as a coherent hub-and-spoke. Inspecting values is a deliberate click instead of a hover guess. |
| **v4: attribute cleanup** | Bilingual merging removed; `joinPair`/`mergedChips` helpers deleted. Each attribute shows only its primary field (no `_en` suffix). | Users preferred seeing the raw extracted value without the `zh / en` separator. |

Bilingual merging (`joinPair`, `mergedChips`) was introduced in v2 and kept
through v3, but was removed in the v4 cleanup. The helpers and the `_en` field
references are gone; attributes now reference primary fields directly.

## Data model

The chart works off a single `KbMetricRecord` (the selected metric) plus the
record's raw lines (for the Grounding group). The data layer in
[`metric-mgmt-view.svelte`](../../../../ChenWeb/web/src/lib/components/home3/metric-mgmt-view.svelte)
defines the following types in the script block:

```ts
type AttrKind = 'text' | 'chips' | 'lines';
type LineEntry = { head: string; content: string; lineType: string };
type AttrDef = {
  key: string;       label: string;     icon: any;
  kind: AttrKind;    value: string;     items: string[];
  entries: LineEntry[];                 // structured entries for `lines` kind
  count: number;     hasValue: boolean;
};
type SatelliteNode = AttrDef & {
  x: number; y: number;
  wire: { x1: number; y1: number; x2: number; y2: number };
};
type GroupNode = {
  key: string; label: string; icon: any;
  count: number; filledCount: number; hasValue: boolean;
  x: number; y: number;
  wire: { x1: number; y1: number; x2: number; y2: number };
  satellites: SatelliteNode[];
  attrs: AttrDef[];
};
type MetricsCanvas = {
  W: number; H: number; Rc: number; Rgn: number; Rsn: number;
  cx: number; cy: number;
  metricLabel: string; metricSubLabel: string;
  groups: GroupNode[];
};
```

The `AttrDef.kind` discriminator drives info-panel rendering and the
satellite count badge. `count` is `1` for text scalars with a value, the array
length for chips/lines, and `0` for empty attributes.

## Attribute groups

Five functional groups, every one populated from `KbMetricRecord` fields in
[`buildMetricGroupAttrs`](../../../../ChenWeb/web/src/lib/components/home3/metric-mgmt-view.svelte):

| Group | Attributes | Notes |
|---|---|---|
| **Metadata** (`BookOpenIcon`) | ID, Name, Confidence, Desc, Formula, Explicit | `Confidence` uses the existing `confidencePct()` helper. Primary fields only (no `_en` suffix). |
| **Context** (`TagIcon`) | Section, Context, Keywords | `Keywords` uses only `metric_keywords` (no `_en` merge). Primary fields only. |
| **Metric** (`TrendingUpIcon`) | Subject, Frequency, Value, Threshold, Unit, Class, Data Type, Range Type, Location | Primary fields only (no `_en` suffix). |
| **Reasoning** (`ActivityIcon`) | Tags | Single chips attribute fed by `reasoning_tags`. |
| **Grounding** (`MapPinIcon`) | Lines | Single `lines`-kind attribute. Each entry is a `LineEntry { head, content, lineType }`, resolved against `rawLineByKey`. Multi-paragraph raw line content is split on `\n` so each paragraph renders as its own card. |

### Bilingual merging (removed)

The v2/v3 chart merged `_en` (English) fields into their corresponding
primary field using `joinPair` (for text scalars) and `mergedChips` (for
keyword arrays). This was removed in the v4 cleanup: every attribute now
references its primary field directly.

```ts
// Before (v3):  textAttr('name', 'Name', TypeIcon, joinPair(m.metric_name, m.metric_name_en))
// After  (v4):  textAttr('name', 'Name', TypeIcon, fmt(m.metric_name), has(m.metric_name))
```

The `joinPair` and `mergedChips` helper functions were deleted. The `_en`
fields are still present in the `KbMetricRecord` data type but are no longer
referenced in the chart or info panel.

#### Why it was removed

Bilingual merging was removed because users preferred seeing the raw
extracted value. The `zh / en` separator added visual noise in the info
panel rows and satellite labels without providing actionable information,
since the two versions rarely differed meaningfully.

## Geometry

Layout constants live inline in the `metricsMap = $derived.by(...)` block and
follow the same shape as `kb-extraction-view.svelte:579`:

```ts
const Rc  = clamp(54..94,  base * 0.115);   // center metric disc
const Rgn = clamp(42..58,  base * 0.072);   // group node circle
const Rsn = 21;                              // attribute satellite

const reachY = cy - 12 - Rsn - 34;
const reachX = cx - 12 - 66;
const reach  = max(120, min(reachY, reachX));
let   Rs = clamp(90..200, base * 0.22);     // group → satellite
let   Rg = clamp((Rc+Rgn+26)..330, base * 0.34, reach - Rs); // center → group
// Fallback if reach is tight: shrink Rs first, then push Rg outward.
```

Group placement is hard-coded to five angles at 72° spacing starting at
`-90°` (top):

```
g_metadata   -90°   top
g_context    -18°   upper-right
g_metric      54°   lower-right
g_grounding  126°   lower-left
g_reasoning  198°   upper-left
```

Attribute satellites fan out from each group along an arc centered on the
group's outward direction. The arc span is

```ts
span = k > 1 ? min(π·0.62, (k-1)·0.44) : 0
```

so a group with one attribute (Reasoning, Grounding) places the satellite
directly outward, and a group with many attributes (Metric: 9) spreads them
across about 110° of arc but never more than `0.62π` ≈ 112°. This caps the
arc so a dense group can't wrap around behind the center disc.

All wires are computed by `shortenLine(...)` at both ends (already in
the file) so SVG `<line>` strokes don't penetrate the node circles.

## Component composition

The chart only renders inside the existing `recordBrowserFolded`
focus-mode block — the un-focused Metrics list view is untouched.

```
.right.focus-split
├─ .metric-canvas-wrap
│  ├─ .canvas-toolbar      (Back / metric-name / keyword / confidence / Prev-Next)
│  └─ .metric-canvas       (bind:clientWidth/Height into canvasW/canvasH)
│     ├─ <svg.canvas-wires>     spokes (center→group) + leaves (group→satellite)
│     ├─ .canvas-node.metric-node  the center disc + .main-node-cap "METRIC"
│     ├─ .group-node-circle     five clickable buttons, each emitting onclick={toggleActiveGroup}
│     ├─ .sat-node + .sat-label one satellite per AttrDef, with count badge for list-kind
│     ├─ .canvas-legend         "Metric / Functional group / Attribute"
│     └─ .group-info-panel      shown when activeGroup != null; draggable right-edge resize handle
├─ .focus-resize-handle     (resizer between chart and PDF)
└─ .doc-frame-wrap         (PdfViewWindow; width driven by focusPdfWidth)
```

## Interaction

Chart and toolbar state:

```ts
let hoveredCanvasAttr = $state<string | null>(null);  // satellite hover highlight
let activeGroupKey    = $state<string | null>(null);  // open info panel
const ALL_METRIC_KEY  = '__all_metric__';             // sentinel for "show all attributes"

let gipWidth          = $state<number | null>(null);  // info panel width (null = CSS default)
let gipResizing       = $state(false);                // drag in progress
let confidenceFilter  = $state('');                   // confidence threshold filter
```

Chart interactions:

- **Hover a satellite** → its wire and label brighten; the satellite circle
  picks up the brass active border. No tooltip, no inspector. The hover state
  exists for visual feedback only.
- **Click a group circle** → `activeGroupKey` toggles. Clicking the same
  group again closes the panel; clicking another swaps to the new group.
- **Click a satellite** → also sets `activeGroupKey` to that satellite's
  parent group. The whole sub-tree of a group is a single click target,
  whichever node the user happens to land on.
- **Click the metric center disc** → sets `activeGroupKey = ALL_METRIC_KEY`,
  which opens the info panel with **every** attribute, broken into one
  section per group (group name as a brass section header, with each group's
  `filled/total` count to the right). Click the metric disc again to close.
- **Close button on the info panel** → clears `activeGroupKey`.

`activeGroup` is a `$derived` lookup against `metricsMap.groups`. A second
derived `showAllMetricAttrs = activeGroupKey === ALL_METRIC_KEY` switches the
panel into all-groups mode, and `totalAttrCount` sums each group's
`filledCount` / `count` for the header count badge.

### Confidence filter

The canvas toolbar includes a confidence threshold filter:

```html
<input type="text" list="confidence-options" bind:value={confidenceFilter} />
<datalist id="confidence-options">
  <option value="0.90"></option>   <!-- shows metrics with confidence >= 0.90 -->
  <option value="0.80"></option>
  <option value="0.70"></option>
  <option value="0.60"></option>
  <option value="0.50"></option>
  <option value="<0.50"></option>  <!-- shows metrics with confidence < 0.50 -->
</datalist>
```

The `<datalist>` provides preset values while allowing free-form entry (e.g.,
`0.85`). The `filteredMetrics` derivation chains the confidence check after
the keyword filter:

```ts
const cf = confidenceFilter.trim();
if (cf.startsWith('<')) {
  const th = parseFloat(cf.slice(1));
  result = result.filter((m) => (m.confidence ?? 0) < th);
} else {
  const th = parseFloat(cf);
  result = result.filter((m) => (m.confidence ?? 0) >= th);
}
```

The filter feeds into `selectedMetricInFilteredIndex` / `prevMetric` /
`nextMetric` the same way the keyword filter does, so navigation arrows
honour the current confidence restriction.

## The Group Info Panel

The panel is an `<aside class="group-info-panel">` positioned absolutely in
the top-left of the canvas at z-12. It mirrors the Scene Blocks meta-card
layout but is driven by `AttrDef.kind`:

```svelte
{#each ag.attrs as a}
  <div class="gip-row" class:gip-row-col={a.kind !== 'text'}>
    <span class="gip-label">{a.label}</span>
    {#if !a.hasValue}        <span class="gip-empty">—</span>
    {:else if a.kind === 'text'}   <span class="gip-val">{a.value}</span>
    {:else if a.kind === 'chips'}  <div class="gip-chips">{#each a.items as it}<span class="gip-chip">{it}</span>{/each}</div>
    {:else}                        <ul class="gip-lines">{#each a.items as it}<li>{it}</li>{/each}</ul>
    {/if}
  </div>
{/each}
```

- `text` rows are a label + value pair on one line (label is a fixed-width
  monospace cap so values align).
- `chips` rows wrap into multi-row pill chips with `gap: 4px` between them.
- `lines` rows render as a vertical stack of bordered cards
  (`.gip-line-card`), one card per `LineEntry`. Each card has a head row
  (`L<n> · P<p>` in brass monospace, plus a pill-shaped `line_type` tag if
  present) above the raw line `content` in the sans body font. Multi-paragraph
  raw line content is split on `\n` (in `spans.flatMap(...)`) so each paragraph
  renders as its own card with the same `${head}` prefix.
- Empty attributes render dimmed (`.gip-row-empty`) but **are not hidden** —
  a missing field is information too, and the panel layout is stable
  metric-to-metric.

The panel scrolls internally (`overflow: auto` on `.gip-body`) so a metric
with many Grounding lines doesn't push the close button off-screen.

### Info panel resize handle

The panel has a draggable right-edge resize handle:

- `<button class="gip-resize-handle">` — `position: absolute; right: 0; top: 0; bottom: 0; width: 10px; cursor: col-resize`. Contains a centered `.gip-resize-grip` pill (2×32px, hidden by default, fading in on hover/drag). The handle background transitions to `var(--brass-faint)` on hover.
- `onpointerdown` → `startGipResize` attaches `pointermove` / `pointerup` / `pointercancel` listeners to `window`, restores body cursor/userSelect on release. Drag delta is `e.clientX - startX` (handle is on the right edge of the panel, so dragging right grows it).
- `onkeydown` → `onGipResizerKeydown` adjusts width by 16 px per arrow press.
- Panel width is driven by `style:width=${gipWidth}px` (inline style), falling back to CSS `clamp(260px, 30%, 360px)` when no user width is saved. Clamped to [220, 620] and persisted to `localStorage["metrics:info-panel-width"]`.

## Things removed in the v3/v4 cleanup

To keep the file from accumulating dead code, the following were removed
(recorded here in case they need to be revived):

### v3 removals

- `PropertyRect` type, `layoutGroupRects`, `wireToRect` helper.
- `CanvasNode` type for `docNodes`, the entire Source Doc circle render
  block, the `connectWire` between Metric and Doc.
- `hoveredNodeInfo` derived and the `.canvas-inspector` floating tooltip
  (replaced by the click-driven panel).
- CSS: `.doc-node`, `.wire.leaf-wire(.active)`, `.canvas-inspector`,
  `.inspector-label`, `.inspector-value`, `.lg-prop`, all `.prop-rect*`.
- Adaptive `Rs` constraint that was needed to keep the v2 Context left-stack
  on-canvas (no longer relevant since attributes are circles, not pills).
- `TypeIcon` import was removed in v2 and re-added in v3 (it's used for
  Name and Subject satellites).

### v4 removals (attribute cleanup)

- `joinPair` helper function and all `_en` field references in `buildMetricGroupAttrs`.
- `mergedChips` helper function. `Keywords` now uses only `metric_keywords`.
- Dead intermediate variables: `name`, `desc`, `ctx`, `subject`, `unit`, `cls`, `keywords`.

### PDF pane cleanup (Scene-Blocks parity pass)

A follow-up pass aligned the right-side PDF pane with the Scene Blocks
layout. The PdfViewWindow's `sidebar` snippet — which rendered three
`EditableMetadataSection`s (kb.metrics Record, kb.inputs Record, kb.inputs
Doc Metadata) plus two `Selected Lines` blocks — was removed entirely, so
the right pane is just the PDF viewer (with the toolbar buttons and
`linesView` snippet still intact). The sidebar-related props on
`<PdfViewWindow>` (`sidebarMinWidth`, `sidebarMaxWidth`, `sidebarDefaultWidth`,
`sidebarTitle`, `sidebarSettingsKey`, `sidebarWidthSettingLabel`) were
dropped because the sidebar is rendered only when the snippet is provided.

`.right.focus-split .doc-frame-wrap` flexes to `0 0 480px` as the fallback,
but the live width is driven by `style:flex-basis="${focusPdfWidth}px"` so a
drag handle can resize it. The first-load default sets
`focusPdfWidth = round(window.innerWidth / 3)` (giving roughly chart 2/3,
PDF 1/3), clamped to `[280, 1460]` and persisted to
`localStorage["metrics:focus-pdf-width"]` on every change.

A draggable resizer sits between `.metric-canvas-wrap` and `.doc-frame-wrap`:

- `<button class="focus-resize-handle">` with a centered `.focus-resize-grip`
  pill. `flex: 0 0 14px`, `cursor: col-resize`, `touch-action: none`.
- `onpointerdown` → `startFocusResize` attaches `pointermove` / `pointerup` /
  `pointercancel` listeners to `window`, restores body cursor/userSelect on
  release. Drag delta is `startX - clientX` (handle on the right of the
  chart, so dragging left grows the PDF).
- `onkeydown` → `onFocusResizerKeydown` adjusts width by 24 px per arrow
  press for keyboard users.

Dead derivations / helpers / imports that only fed the removed sidebar were
also pruned: `metricFieldRows`, `inputRecordMetaRows`, `inputDocMetadataRows`,
`selectedLineGroups`, `filteredPageLines`, `currentPageLines`,
`saveInputMetadataRow`, `saveMetricMetadataRow`, `formatCoords`, the
`MetadataLine` / `MetadataRow` / `MetadataEditorKind` types,
`EditableMetadataSection`, `updateKbMetric`, `updateKbInput`, and the
`kb-metric-metadata.js` / `kb-input-metadata.js` imports. The `.metadata-*`
CSS rules went with them.

## File map

- [`metric-mgmt-view.svelte`](../../../../ChenWeb/web/src/lib/components/home3/metric-mgmt-view.svelte)
  — Everything described here lives in this one component.
- [`kb-extraction-view.svelte`](../../../../ChenWeb/web/src/lib/components/home3/kb-extraction-view.svelte)
  — Reference implementation for the Scene-Blocks-style radial chart. The
  geometry block in `metricsMap` is intentionally aligned with the one in
  this file (`sceneMap = $derived.by(...)` around line 579).
- [`kbService.ts`](../../../../ChenWeb/web/src/lib/services/kbService.ts)
  — `KbMetricRecord` shape, `listKbMetrics`, `SourceLineSpan`. The chart
  uses already-loaded data; there are no chart-specific endpoints.

## Maintenance notes

- **Adding an attribute to an existing group**: extend the corresponding
  array in `buildMetricGroupAttrs`. The satellite arc auto-distributes; the
  info panel auto-renders the new row based on `kind`. No template changes
  needed.
- **Adding a new group**: append a `GroupSpec` to `groupSpecs` in
  `metricsMap`, then redistribute the angles (e.g. 60° spacing for six
  groups). Add a new attribute array to the `buildMetricGroupAttrs` return
  type and populate it from the metric record.
- **Resetting the info panel width**: delete `localStorage["metrics:info-panel-width"]`
  to revert to the CSS `clamp(260px, 30%, 360px)` default, or just drag the
  handle to a new size.
- **Adjusting the confidence filter presets**: edit the `<datalist id="confidence-options">`
  options in the template. The `filteredMetrics` derivation handles any
  numeric value (plain number → ≥, `<N` → below-threshold).
- **Reverting to a hover-driven inspector**: the `hoveredCanvasAttr` plumbing
  is still in place; only the inspector `<div>` was removed. A future
  inspector should key off `hoveredCanvasAttr` and look up the satellite via
  `metricsMap.groups.flatMap(g => g.satellites)`.
