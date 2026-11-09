# Module: Metric Detail Visualizer

**Module ID:** `20261025-01`
**Type:** frontend · **Language:** svelte · **Version:** 1.0.0
**Status:** active — used by the Metrics page's METRIC DETAILS panel (Knowledge Base → Metrics)
**Project:** ChenWeb (web front end)
**Location:** `ChenWeb/web/src/lib/components/shared-ui/metric-detail/`
**Created:** 2026-10-25
**Devdocs:** None

## 1. What it is

A Svelte 5 component that shows everything known about one extracted metric (one
`kb.metrics` row). It is the panel that opens on the right of the Metrics page when you
click a metric:

```
 ← Close   ‹  1 / 27  ›                       ← optional toolbar
 易腐垃圾收运频次                               ← metric name
 Perishable waste collection frequency         ← English name
 ┌ ↗ Metric                            13/19 ┐
 │            Name   易腐垃圾收运频次          │
 │       Metric ID   416_mtc_1               │
 │       Condition   —                       │  ← empty field, dimmed
 │           …                               │
 └───────────────────────────────────────────┘
 ┌ 📖 Metadata                           5/9 ┐ … Context, Grounding, Reasoning
```

The fields are grouped into five cards: **Metric** (what is measured and its value),
**Metadata** (row id, confidence, description), **Context** (source document, section,
keywords), **Grounding** (the document lines the metric was extracted from) and
**Reasoning** (tags). Each card header shows how many of its fields have a value
(`13/19`). Inside a card, the fields are drawn by the
[Name-Value Visualizer](module-name-value-visualizer.md) (`20261024-01`): names on the
left, values on the right, empty fields kept and shown as `—`.

Use it wherever a page shows the details of a single metric. It is not a metric list or
a comparison table, and it does not edit the metric.

## 2. Files

| File | Purpose |
|---|---|
| `ChenWeb/web/src/lib/components/shared-ui/metric-detail/metric-detail-visualizer.svelte` | The component: toolbar, title and the five group cards. |
| `ChenWeb/web/src/lib/components/shared-ui/metric-detail/metric-detail.ts` | `buildMetricDetailGroups()`, `attrToField()` and `metricTitle()`: turn a metric into groups of name-value fields. |
| `ChenWeb/web/src/lib/components/shared-ui/metric-detail/metric-detail.test.ts` | Unit tests for `metric-detail.ts` (`bun test`). |

It builds on two modules that are not part of it:

- `ChenWeb/web/src/lib/components/home3/metric-detail-groups.ts` decides **which fields
  exist, their order and their labels** (`buildMetricGroupAttrs()`). The Product Review
  "Full Details" dialog uses the same builder, so both show the same fields. Add or
  rename a metric field there, not in this module.
- The Name-Value Visualizer draws each card's fields.

## 3. Interface

```ts
// metric-detail-visualizer.svelte props
metric: KbMetricRecord;                       // the row to show ($lib/services/kbService)
rawLines?: RawLine[];                         // lines of the metric's document; default []
position?: { index: number; total: number };  // place in the caller's list; index -1 = not in it
onClose?: () => void;
onPrev?: () => void;                          // missing → "previous" button disabled
onNext?: () => void;                          // missing → "next" button disabled
```

- **Toolbar:** shown only when `onClose` or `position` is given. `position` shows
  `index + 1 / total` (or `— / total`) between the previous/next buttons.
- **Grounding:** filled only when `rawLines` holds the lines of the metric's document.
  The metric's `source_line_spans` are line numbers; the component looks them up in
  `rawLines` to get each line's page, type and text. With no lines, Grounding is empty.

Helpers in `metric-detail.ts`, for callers that want the data without the component:

```ts
type MetricDetailGroupKey = 'metric' | 'metadata' | 'context' | 'grounding' | 'reasoning';
type MetricDetailGroup = {
	key: MetricDetailGroupKey;
	label: string;              // localised
	filled: number;             // fields with a value
	total: number;
	fields: NameValueInput[];   // empty fields have values: []
};
buildMetricDetailGroups(metric: KbMetricRecord, rawLines: RawLine[]): MetricDetailGroup[];
attrToField(a: AttrDef): NameValueInput;
metricTitle(metric: KbMetricRecord): { name: string; subname: string };
```

How each kind of field becomes name-value values (`attrToField`):

| Field kind | Shown as |
|---|---|
| text | one value; identifiers (row ID, document ID, run ID, metric ID, keyword concept ID, definition term ID) in monospace |
| chips (keywords, frame uses/method, tags) | one value per item, stacked |
| JSON (frame) | one monospace line per key, indented two spaces per level |
| lines (grounding) | one value per cited line: `L90 · P6 (text)`, then the line's text below |

## 4. Configuration

None. The component has no settings; everything it shows comes from its props.

## 5. Usage

From the Metrics page (`ChenWeb/web/src/lib/components/home3/metric-mgmt-view.svelte`):

```svelte
<script lang="ts">
	import MetricDetailVisualizer from '$lib/components/shared-ui/metric-detail/metric-detail-visualizer.svelte';
	// selectedMetric: KbMetricRecord; rawLines: RawLine[] of the open document;
	// filteredMetrics, selectedMetricInFilteredIndex, prevMetric, nextMetric from the list.
</script>

<div class="panel" style="--panel-bg:{panelBg}; --panel-bg-alt:{panelBgAlt}; --ink-line:{inkLine}; --brass:{brass}; …">
	<MetricDetailVisualizer
		metric={selectedMetric}
		{rawLines}
		position={{ index: selectedMetricInFilteredIndex, total: filteredMetrics.length }}
		onClose={goBack}
		onPrev={prevMetric ? goToPrevMetric : undefined}
		onNext={nextMetric ? goToNextMetric : undefined}
	/>
</div>
```

A read-only view (for example in a dialog) passes only the data:

```svelte
<MetricDetailVisualizer metric={row} rawLines={documentLines} />
```

Give the component a parent with a bounded height (a flex column or a fixed-height box):
its body scrolls on its own, below the toolbar.

## 6. Behaviour and conventions

- **Text selection:** the panel carries `select-text`, so names and values can be copied
  inside shells that set `select-none` (workspace `CLAUDE.md` → Frontend).
- **i18n:** every label is a Paraglide message — the group names, toolbar text and the
  fallback title (`metric_detail_*` keys) and the field names (`metric_detail_*` keys used
  by `metric-detail-groups.ts`). Values are data and are shown as stored. Labels follow a
  language switch without a reload.
- **Theme:** the component has no colour tokens of its own. It reads the page's CSS
  variables — `--panel-bg`, `--panel-bg-alt`, `--ink-line`, `--ink-line-soft`,
  `--text-primary`, `--text-secondary`, `--text-muted`, `--brass` (accent),
  `--font-serif`, `--font-mono` — and falls back to `--accent`, `currentColor` and system
  fonts when they are not set, so it works in light and dark themes.
- **Width:** works from a ~300px side panel upwards. In containers narrower than 600px
  the Name-Value Visualizer switches to its compact name column.
- **Keyboard:** Close and previous/next are buttons with a visible focus outline;
  previous/next carry `aria-label`s. The Metrics page also closes the panel on Escape
  (that handler belongs to the page, not to this component).

## 7. Scope and limits

- Read-only: no editing, deleting or re-extracting from the panel.
- No per-field render snippets: chips, frame JSON and grounding lines are shown as
  plain stacked text, not as chips, a tree or line cards.
- The Product Review "Full Details" dialog (`product-metric-review-view.svelte`) still
  draws the same fields with its own flat table; it could switch to this component.
- `provision-mgmt-view.svelte` has its own copy of the metric field builder; it is not
  covered by this module.
- If another project needs it, move it with the Name-Value Visualizer and
  `metric-detail-groups.ts` to `shared/svelte` (`@chendingplano/shared`) rather than
  copying it.
