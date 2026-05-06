# Tree Graph View — Implementation Notes

## Overview

`tree-graph-view.svelte` is a shared ECharts horizontal-tree component used by both the **Document Summaries → Summary Graph** and **Semantic Web → Semantic Web** pages inside `home3/knowledge`. Both pages were previously separate files (`summary-graph-view.svelte` and `topic-graph-view.svelte`) with near-identical implementations. They are now thin wrappers:

```svelte
<!-- summary-graph-view.svelte -->
<TreeGraphView mode="summary" {darkMode} />

<!-- topic-graph-view.svelte -->
<TreeGraphView mode="topic" {darkMode} />
```

---

## Props

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `mode` | `'summary' \| 'topic'` | *(required)* | Selects data source and labels |
| `darkMode` | `boolean` | `true` | Light/dark theme |

---

## Node Style Toggle

The component has an internal `nodeStyle: 'circle' | 'rect'` state. It defaults to:

- `'circle'` when `mode === 'summary'`
- `'rect'` when `mode === 'topic'`

The user can toggle between the two styles at any time using the circle/square icon button added to `view-toolbar.svelte`. The toggle is wired via `onToggleNodeStyle` prop on `ViewToolbar`:

```svelte
<ViewToolbar
  {darkMode}
  {nodeStyle}
  onToggleNodeStyle={() => {
    nodeStyle = nodeStyle === 'circle' ? 'rect' : 'circle';
  }}
/>
```

`ViewToolbar` only renders the toggle button when `onToggleNodeStyle` is provided, so other usages of the toolbar are unaffected.

### Circle style
- ECharts symbol: `emptyCircle`
- Symbol size: `11` (selected: `16`)
- Label positioned outside the node (left for parents, right for leaves)
- Mini-map nodes rendered as SVG `<circle>`

### Rectangle style
- ECharts symbol: `rect`
- Symbol size: `[160, 64]`
- Label rendered inside the node with a two-line rich-text formatter (`name` + `confidence · keywords`)
- Mini-map nodes rendered as SVG `<rect>`

---

## Unified Node Type

Both `SummaryCategoryNode` and `TopicCategoryNode` are normalised on load into a shared internal type:

```typescript
type GraphCategoryNode = {
  id: string;
  label: string;
  categoryPath: string;
  metadata: {
    desc: string;
    confidence: number;
    keywords: string[];
    create_time: string;
    category_type?: string; // summary mode only
  };
  childIds: string[];
  itemIds: string[];       // summaryIds  OR  topicIds
  hasItemsFile: boolean;   // hasSummariesFile  OR  hasTopicsFile
  expanded: boolean;
};
```

Normalisation happens inside `loadGraph()`:

```typescript
// summary
itemIds: n.summaryIds,
hasItemsFile: n.hasSummariesFile

// topic
itemIds: n.topicIds,
hasItemsFile: n.hasTopicsFile
```

The dialog (`SummaryNodeDialog`) still expects `SummaryCategoryNode`, so a `toDialogNode()` helper converts back when needed.

---

## Mode-Specific Behaviour

### Colors

| Token | Summary | Topic |
|-------|---------|-------|
| `accent` | `#818cf8` (dark) / `#4f46e5` (light) | `#22c55e` (dark) / `#16a34a` (light) |
| `warm` | `#fbbf24` (dark) / `#b45309` (light) | `#4ade80` (dark) / `#15803d` (light) |
| `lineColor` | `rgba(148,163,184,0.28)` | `rgba(34,197,94,0.28)` |

### Data loading

| Mode | List API | Category API |
|------|----------|--------------|
| summary | `listSummaryGraph()` | `getSummaryCategory(path)` |
| topic | `listTopicGraph()` | `getTopicCategory(path)` |

### Tab components

| Mode | Tab bar | Content tab |
|------|---------|-------------|
| summary | `SummaryGraphTabs` | `SummaryCategoryTabPanel` (`summary-category-tab.svelte`) |
| topic | `TopicGraphTabs` | `TopicCategoryTabPanel` (`topic-category-tab.svelte`) |

Tab IDs are prefixed by mode to prevent collisions:

```
summary  →  "category:<path>"
topic    →  "topic-category:<path>"
```

### Hero stats

| Mode | Third stat label | Third stat value |
|------|-----------------|-----------------|
| summary | Mode | `Phase 1 Mock` |
| topic | Topics | sum of `node.itemIds.length` |

---

## Hover / Click Architecture

The component uses the more robust click-handling logic from the original `summary-graph-view`, applied to both modes:

1. **ECharts `onclick`** (`handleChartNodeClick`) — fires on direct node hits, records `lastEChartsClickStamp`.
2. **ZRender `click`** (`scheduleZrClickFallback`) — scheduled with `setTimeout(0)` so it runs *after* the ECharts event. Skipped if ECharts already handled the click within 50 ms.
3. **`findRenderedNodeHit`** — spatial hit-test against rendered node positions, using both label-text matching and proximity thresholds (`NODE_CLICK_FALLBACK_MAX_DX / DY`).
4. **Hover keep-alive zone** (`isPointInHoverKeepAliveZone`) — prevents the hover card from disappearing while the pointer moves between a node and the card.

---

## Layout Constants

These constants are fixed; `hoverGapRightX` and `revealMargin` are derived from `nodeStyle`:

| Constant | circle | rect |
|----------|--------|------|
| `hoverGapRightX` | 150 | 95 |
| `revealMargin` | 96 | 112 |

Reveal bounding box padding also adjusts: rect nodes use ±90/190/64 px margins vs circle's ±48/160/48 px.

---

## ViewToolbar Changes

`view-toolbar.svelte` gained several new optional fields:

```typescript
type Props = {
  nodeStyle?: 'circle' | 'rect';
  onToggleNodeStyle?: () => void;
  onCollapseSelected?: () => void;
  collapseSelectedDisabled?: boolean;
  // ... existing props unchanged
};
```

### Node Style Toggle

The toggle button is rendered only when `onToggleNodeStyle` is supplied. It shows a `CircleIcon` when `nodeStyle === 'circle'` and a `SquareIcon` when `nodeStyle === 'rect'`, with a tooltip indicating what the click will switch to.

### Toolbar Button Order

Buttons left-to-right: Expand/Collapse All → Filter → Reset Filter → Expand Selected (popover) → Collapse Selected → Export PNG → Node Style Toggle (conditional) → **Settings** (always last, `SettingsIcon` gear icon).

### Collapse Selected Node

A `Minimize2Icon` button sits immediately after the "Expand Selected Node" popover. It collapses the currently selected node by setting `expanded: false` without toggling (so it never accidentally re-expands). The button is disabled when no node is selected or the selected node is already collapsed.

Wired in `tree-graph-view.svelte` via:

```svelte
<ViewToolbar
  collapseSelectedDisabled={!selectedNode?.expanded}
  onCollapseSelected={collapseSelectedNode}
/>
```

`collapseSelectedNode` sets `expanded: false` on the selected node directly (no toggle) and syncs the mini-map viewport.

---

## Settings

The gear icon (`SettingsIcon`) at the far right of the toolbar opens a settings popover. Settings are stored as component-local `$state` variables and are not persisted between sessions.

### Setting Fields

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `defaultExpandDepth` | `number` (integer) | `6` | Maximum depth of child levels expanded when "Expand Selected Node" is triggered. |
| `showInfoBlock` | `boolean` | `false` | When `true`, a hover card appears next to a node while the pointer is over it. When `false`, the hover card is suppressed entirely. |

### Wiring

`GraphSettings` is exported from `view-toolbar.svelte` and imported by `tree-graph-view.svelte`:

```typescript
// tree-graph-view.svelte
import ViewToolbar, { type GraphSettings } from './view-toolbar.svelte';

const GRAPH_SETTINGS_KEY = 'tree-graph-view-settings';
const defaultGraphSettings: GraphSettings = { defaultExpandDepth: 6, showInfoBlock: false };

function loadGraphSettings(): GraphSettings {
  try {
    const raw = localStorage.getItem(GRAPH_SETTINGS_KEY);
    if (raw) return { ...defaultGraphSettings, ...JSON.parse(raw) };
  } catch {}
  return { ...defaultGraphSettings };
}

let graphSettings = $state<GraphSettings>(loadGraphSettings());

$effect(() => {
  localStorage.setItem(GRAPH_SETTINGS_KEY, JSON.stringify(graphSettings));
});
```

`ViewToolbar` receives the settings object and a callback to update it:

```svelte
<ViewToolbar
  settings={graphSettings}
  onSettingsChange={(patch) => { graphSettings = { ...graphSettings, ...patch }; }}
/>
```

Inside the toolbar a `toolbar-settings-wrap` div (same pattern as `toolbar-expand-level-wrap`) holds the `settingsOpen` popover toggled by `handleSettings`. The popover renders two controls:

- **Default Expand Selected Node Depth** — `<input type="number" min="1" max="20">` using `oninput` to call `onSettingsChange?.({ defaultExpandDepth: v })`.  
  Help text: *"The maximum depth of expanding the selected node."*
- **Show Information Block** — `<input type="checkbox">` using `onchange` to call `onSettingsChange?.({ showInfoBlock: checked })`.  
  Help text: *"Control whether to show the information when the mouse hovers over a node."*

`closePopoverOnOutside` also closes `settingsOpen` when the click lands outside `.toolbar-settings-wrap`.

The popover is anchored to the right edge of the button (`right: 0`) so it stays on-screen.

### Consumer behaviour

- **`defaultExpandDepth`** — used as the `max` attribute of the expand-level range slider. A `$effect` in `view-toolbar.svelte` clamps `expandLevel` if it exceeds the new max when settings change.
- **`showInfoBlock`** — gates the hover card in `tree-graph-view.svelte`: the `{#if hoveredNode}` block becomes `{#if hoveredNode && graphSettings.showInfoBlock}`. When `false` (default), the hover card is never rendered.

---

## File Map

| File | Role |
|------|------|
| `tree-graph-view.svelte` | Unified shared component |
| `summary-graph-view.svelte` | Thin wrapper: `<TreeGraphView mode="summary">` |
| `topic-graph-view.svelte` | Thin wrapper: `<TreeGraphView mode="topic">` |
| `view-toolbar.svelte` | Added `nodeStyle` / `onToggleNodeStyle` props |
| `summary-graph-state.js` | Still used for test coverage; logic inlined in shared component |
| `topic-graph-state.js` | Same — logic inlined |
| `summary-graph-hover-position.js` | Shared hover-card positioning utils (unchanged) |
| `graph-layout-utils.js` | Tree layout width / reveal calculations (unchanged) |
