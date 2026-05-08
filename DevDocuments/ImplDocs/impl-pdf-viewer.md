# PDF Viewer — Implementation Notes

## Overview

The PDF viewer used across `/home3/knowledge` is a two-layer component stack:

```
PdfViewWindow          ← manages sidebar width + resizer drag handle
  └─ SharedPdfViewer  ← PDF.js rendering, page/zoom/highlight state
```

**`SharedPdfViewer`** handles all PDF.js rendering (canvas per page, zoom, highlights, page rotation). It exposes two named slots: `sidebar` and `sidebar-resizer`, consumed only by `PdfViewWindow`.

**`PdfViewWindow`** wraps `SharedPdfViewer` and owns the sidebar resize UX — width state, drag-to-resize with Pointer Events, keyboard stepping, and the visual drag handle. Consumer views pass their sidebar panel content via a Svelte 5 snippet.

The pattern was previously duplicated in five views. It is now consolidated into `PdfViewWindow`.

---

## Files

| File | Role |
|------|------|
| `shared-pdf-viewer.svelte` | PDF.js renderer; named slots `sidebar` / `sidebar-resizer` |
| `pdf-view-window.svelte` | Reusable wrapper; manages sidebar width + resize handle |
| `inputs-mgmt-view.svelte` | Document Details view — uses `PdfViewWindow` |
| `metric-mgmt-view.svelte` | Metrics view — uses `PdfViewWindow` |
| `doc-structure-view.svelte` | Document Structure view — uses `PdfViewWindow` |
| `chunk-mgmt-view.svelte` | Chunks view — uses `PdfViewWindow` |
| `summary-tree-view.svelte` | Summary Tree view — uses `PdfViewWindow` |

All files are under `web/src/lib/components/home3/`.

---

## PdfViewWindow Props

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `inputId` | `number \| null` | *(required)* | Passed through to SharedPdfViewer |
| `fileUrl` | `string` | *(required)* | PDF URL |
| `page` | `number` | `1` | Bindable; current page |
| `zoom` | `number` | `0.5` | Bindable; zoom level |
| `numPages` | `number` | `0` | Bindable; total pages |
| `highlightVersion` | `number \| string` | `0` | Changing this value triggers a highlight re-render pass |
| `renderHighlights` | `function` | — | Optional per-page highlight renderer callback |
| `loadingLabel` | `string` | `'Rendering page…'` | Loading overlay text |
| `respectPageRotation` | `boolean` | `true` | Honour PDF page rotation metadata |
| `sidebarMinWidth` | `number` | `140` | px — minimum drag width |
| `sidebarMaxWidth` | `number` | `420` | px — maximum drag width |
| `sidebarDefaultWidth` | `number` | `270` | px — initial width |
| `showingLines` | `boolean` | `false` | Bindable; when `true` renders `linesView` instead of the PDF |
| `toolbar` | `Snippet` | — | Optional snippet; rendered as a toolbar bar above the PDF/lines area |
| `linesView` | `Snippet` | — | Optional snippet; content shown when `showingLines` is true |
| `sidebar` | `Snippet` | — | Svelte 5 snippet; sidebar panel content |

### Per-view sidebar dimensions

| View | Min | Max | Default |
|------|-----|-----|---------|
| Document Details (`inputs-mgmt-view`) | 260 | 620 | 340 |
| Metrics, Document Structure, Chunks | 140 | 420 | 270 |
| Summary Tree | 240 | 520 | 320 |

---

## Consumer Usage Pattern

```svelte
<PdfViewWindow
    inputId={currentInput.id}
    {fileUrl}
    bind:page={docPage}
    bind:zoom={pdfZoom}
    bind:numPages={pdfNumPages}
    highlightVersion={currentInput.id}
    bind:showingLines={showLines}
    sidebarMinWidth={260}
    sidebarMaxWidth={620}
    sidebarDefaultWidth={340}
>
    {#snippet toolbar()}
        <!-- configurable tool buttons; defined in caller scope so they close over caller state -->
        <button class="pvw-tool-btn" onclick={...}>Tool A</button>
        <button class="pvw-tool-btn" class:active={showLines} onclick={() => (showLines = !showLines)}>
            Show Lines
        </button>
    {/snippet}
    {#snippet sidebar()}
        <aside class="my-panel">
            <!-- panel content -->
        </aside>
    {/snippet}
    {#snippet linesView()}
        <!-- rendered when showingLines is true; replaces the PDF canvas area -->
        <div class="my-lines-panel">...</div>
    {/snippet}
</PdfViewWindow>
```

All three snippets are optional. The `toolbar` snippet renders inside a `pvw-toolbar-pill` container at the right end of the `doc-page-bar`. Callers define which tools appear by controlling the snippet content — button styles and click handlers live in the caller's scope. `showingLines` is bindable so both the toolbar snippet and the caller's own code can toggle the lines/PDF switch. When `linesView` is omitted and `showingLines` is `true`, the PDF is still shown.

## Toolbar Tool Configuration

Each consumer view decides which tools to expose by defining the `toolbar` snippet. Tool button styles are defined in the consumer's `<style>` block using the `.pvw-tool-btn` and `.pvw-tool-sep` classes.

| View | Tools |
|------|-------|
| `metric-mgmt-view` | + Metric, Edit Lines, Delete Lines, + Line, Show Lines |

### Standard toolbar CSS classes (defined per consumer)

```css
.pvw-tool-btn        /* icon button: 32×32px, transparent background, no border */
.pvw-tool-btn.active /* active/toggled state: indigo highlight (--pvw-hvr) + #818cf8 icon colour */
.pvw-tool-sep        /* vertical 1×18px separator */
```

---

## Resize Mechanism

Drag-to-resize uses the **Pointer Events API** (`setPointerCapture`) so the drag continues even if the pointer leaves the handle element:

1. `onpointerdown` on the resizer button: captures the pointer, records `startX` and `startWidth`, sets `resizing = true`.
2. `pointermove` on `window`: computes new width as `startWidth + (e.clientX - startX)`, clamped to `[sidebarMinWidth, sidebarMaxWidth]`.
3. `pointerup` / `pointercancel` on `window` (`{ once: true }`): releases capture, removes listeners, resets cursor.

Keyboard accessibility is also supported on the resizer button:

| Key | Action |
|-----|--------|
| `ArrowLeft` | Decrease width by 16 px |
| `ArrowRight` | Increase width by 16 px |
| `Home` | Snap to `sidebarMinWidth` |
| `End` | Snap to `sidebarMaxWidth` |

---

## ResizeObserver Fix in SharedPdfViewer

PDF.js renders each page onto a `<canvas>` sized to the available width. The outer `pdfStageEl` element does not change width when the sidebar resizes (it fills the remaining space via `flex: 1`), so the original single `ResizeObserver` on `pdfStageEl` never fired on sidebar drag.

The fix adds a **second `ResizeObserver`** on `pdfCanvasHostEl` (the direct canvas host inside the scroll area). This element *does* change width on sidebar resize because it is inside the flex layout. When its width changes and differs from the last-rendered width, it schedules a `requestAnimationFrame` re-render:

```ts
$effect(() => {
    if (!pdfCanvasHostEl) return;
    const ro = new ResizeObserver(() => {
        const w = Math.floor(pdfCanvasHostEl?.clientWidth ?? 0);
        if (w <= 0 || w === pdfLastRenderWidth) return;
        if (pdfResizeRaf) cancelAnimationFrame(pdfResizeRaf);
        pdfResizeRaf = requestAnimationFrame(() => { void renderPdfPages(); });
    });
    ro.observe(pdfCanvasHostEl);
    return () => ro.disconnect();
});
```

Before this fix, `inputs-mgmt-view` worked around the bug by appending `metadataPanelWidth` to `highlightVersion` so any sidebar drag would force a full highlight re-render. That workaround has been removed.

---

## CSS Architecture

`PdfViewWindow` uses scoped CSS classes (`pvw-*`) so they never collide with consumer panel styles.

```
.pvw-shell          position:relative; flex:0 0 auto; height:100%; padding-right:16px
.pvw-resizer        position:absolute; right:0; width:16px; cursor:col-resize
.pvw-resizer-grip   dotted pill overlay using radial-gradient + CSS vars
```

Color variables (`--ink-line`, `--brass`, `--text-muted`, `--panel-bg`, `--ink-line-soft`) are cascaded from the view root element and not defined in the component itself.

At `max-width: 1200px` the shell collapses (`width: auto !important`, `padding-right: 0`) and the resizer is hidden, stacking the sidebar above the PDF.

Consumer panels (e.g. `.metadata-panel`, `.meta-panel`, `.summary-sidebar`) only need `width: 100%; height: 100%` to fill the shell. They should not set their own fixed widths — width is owned by `PdfViewWindow`.

## Toolbar

The PDF viewer toolbar provides view-specific action buttons for manipulating the document data (lines, metrics, etc.) behind the displayed PDF. Because each consumer view exposes different operations, the toolbar content is supplied via a caller-defined `toolbar` snippet rather than being built into `PdfViewWindow`.

### Per-View Tool Configuration

Each consumer view declares its own toolbar buttons inside the `{#snippet toolbar()}` block. The current views and their tools are:

| View | Tools (left → right) |
|------|----------------------|
| `metric-mgmt-view` | Add Metric · *sep* · Edit Lines · Delete Lines · Add Line · *sep* · Show Lines |

#### `metric-mgmt-view` tool details

| Tool | Button in Select Dialog| Behaviour |
|------|-----------|----|
| Edit Lines | No | Toggles edit-line mode (highlighted when active). Mutually exclusive with Delete Lines — activating one clears the other. |
| Delete Lines No | | Toggles delete-line mode (highlighted when active). Mutually exclusive with Edit Lines. |
| Add Line Yes | No | Toggles the "Add Line" panel open/closed (highlighted while open). |
| Show Lines Yes | | Switches between the PDF canvas view and the lines view. When active the icon changes (List → FileText) and the button title becomes "Show PDF Document". |

### Toolbar API

The toolbar is dynamically configured by each caller. `PdfViewWindow` makes no assumptions about which buttons are present — it simply renders whatever the `toolbar` snippet provides inside the `pvw-toolbar-pill` container in the page bar.

```svelte
<PdfViewWindow ...>
    {#snippet toolbar()}
        <button class="pvw-tool-btn" onclick={...}>...</button>
        <div class="pvw-tool-sep"></div>
        <button class="pvw-tool-btn" ...>...</button>
    {/snippet}
    {#snippet sidebar()}...{/snippet}
</PdfViewWindow>
```

### Toolbar Slot — `page-bar-tool`

#### In `shared-pdf-viewer.svelte`

A new named slot `page-bar-tool` is placed at the right end of `.doc-page-bar`, after the `page-controls-wrap`:

```svelte
<div class="doc-page-bar">
    <div class="page-bar-sidebar-spacer" style={`width:${pdfSidebarWidth}px;`}></div>
    <div class="page-controls-wrap">
        <!-- ‹ page N/M › − zoom% + ↗ -->
    </div>
    <slot name="page-bar-tool" />   <!-- toolbar pill goes here -->
</div>
```

The `page-controls-wrap` has `flex: 1`, so it fills available space between the sidebar spacer and the toolbar pill. The toolbar pill sits at the far right of the bar.

#### In `pdf-view-window.svelte`

`PdfViewWindow` provides the slot content — a `pvw-toolbar-pill` div wrapping the caller's `toolbar` snippet:

```svelte
<SharedPdfViewer ...>
    <div slot="page-bar-tool">
        {#if toolbar}
            <div
                class="pvw-toolbar-pill"
                style={`--pvw-surf:${pillSurface}; --pvw-bdc:${pillBorder}; --pvw-tc:${pillText}; --pvw-hvr:${pillHover};`}
            >
                {@render toolbar()}
            </div>
        {/if}
    </div>
    <div slot="sidebar">...</div>
</SharedPdfViewer>
```

The slot element must be a **direct child** of the component — Svelte does not allow `{#if}` to wrap a `slot="..."` element. The wrapper div is always present; the pill is rendered conditionally inside it. When `toolbar` is undefined the wrapper is empty and collapses to zero width in the flex row.

---

### Layout — `doc-page-bar` Flex Row

```
doc-page-bar (display: flex; gap: 10px; padding: 10px 14px)
├── .page-bar-sidebar-spacer    flex: 0 0 auto;  width = pdfSidebarWidth px
├── .page-controls-wrap         flex: 1;  justify-content: center
│   └── .page-controls          ‹ page input / total › − zoom% + ↗
└── slot[page-bar-tool]
    └── .pvw-toolbar-pill       display: inline-flex  (collapses when empty)
        └── toolbar snippet buttons
```

`pdfSidebarWidth` is measured from `.pdf-sidebar-cluster` via `ResizeObserver`, so the page controls stay centred over the PDF canvas area even as the metadata sidebar is dragged.

---

### CSS — Pill Theming

The pill uses four CSS custom properties injected via inline `style` from `PdfViewWindow`'s `darkMode`-derived values:

| Variable | Dark value | Light value | Applied to |
|----------|-----------|-------------|------------|
| `--pvw-surf` | `rgba(15,23,42,0.55)` | `rgba(255,255,255,0.72)` | pill background |
| `--pvw-bdc` | `rgba(148,163,184,0.18)` | `rgba(100,116,139,0.18)` | pill border |
| `--pvw-tc` | `#94a3b8` | `#64748b` | button icon colour |
| `--pvw-hvr` | `rgba(99,102,241,0.14)` | `rgba(99,102,241,0.10)` | button hover background |

Consumer views define `.pvw-tool-btn` and `.pvw-tool-sep` in their own `<style>` blocks. Because the toolbar snippet is defined in the consumer's component scope, Svelte's scoped CSS hashes carry through correctly when the snippet is rendered inside the pill.

---

## Drag-and-Select Feature

The drag-and-select feature lets users drag a vertical range on the PDF canvas to select document lines, which are then stored in a buffer for toolbar tools to act on.

### Architecture

```
Drag gesture (SharedPdfViewer)
  → ondragmove callback (during move)
    → line detection (consumer)
      → paintOverlayForPage → renderHighlights draws drag preview
  → onselect callback (on release)
    → line detection (consumer view, e.g. metric-mgmt-view)
      → selectedLines buffer (PdfViewWindow)
        → click-away clears buffer unless click is on toolbar
          → toolbar tools read buffer for enabled state
```

When the mouse button is released (after the dragging), if any line is selected, it opens the "Selected 
Lines Dialog".

The gesture capture lives in `SharedPdfViewer` (it owns the canvas DOM), line-detection logic lives in the consumer view (it owns the `rawLines` data), and the buffer lifecycle is managed by `PdfViewWindow`.



### New Props

**`SharedPdfViewer`** — new props:

| Prop | Type | Description |
|------|------|-------------|
| `onselect` | `(detail: {pageNumber, viewportY1, viewportY2, viewport}) => void` | Called on drag release. `viewportY1`/`viewportY2` are the top/bottom Y coordinates in viewport space (not PDF space). A click with no drag (startY ≈ endY) does not fire the callback. |
| `ondragmove` | Same shape as `onselect` | Called on each `pointermove` during drag with intermediate values. Enables live preview of overlapping lines while dragging. |

**`PdfViewWindow`** — new props:

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `selectedLines` | `number[]` | `[]` | Bindable; the buffer of selected line numbers. Cleared on click-away. |
| `onselect` | Same as `SharedPdfViewer`'s | — | Passed through to `SharedPdfViewer` so the consumer gets the drag detail. |
| `ondragmove` | Same as `SharedPdfViewer`'s | — | Passed through to `SharedPdfViewer` for live preview during drag. |

### Gesture Mechanics (SharedPdfViewer)

The drag gesture uses the **Pointer Events API** on `.pdf-canvas-host`:

1. **`pointerdown`**: Records `clientY`, identifies the page via `closest('[data-page]')`, captures the pointer with `setPointerCapture`, sets `dragSelecting = true`.
2. **`pointermove`**: Updates a `position: fixed` indicator overlay div that spans the vertical drag range. Fires `ondragmove` with the current viewport Y range, then calls `paintOverlayForPage()` to immediately repaint the dragged page's overlay. The consumer's `renderHighlights` draws both regular highlights and drag preview lines (via `pdfDragPreviewLines`).
3. **`pointerup`**: Computes `viewportY1`/`viewportY2` by subtracting `canvasEl.getBoundingClientRect().top` from the client Y values. If a real drag is detected (`viewportY2 - viewportY1 >= 5`), calls `onselect`, then calls `paintHighlights()` to restore normal overlays (clearing drag preview).

**Indicator CSS** (in `SharedPdfViewer`):

```css
.pdf-drag-indicator {
    position: fixed;
    z-index: 10;
    pointer-events: none;
    background: rgba(99, 102, 241, 0.10);
    border-left: 3px solid rgba(99, 102, 241, 0.5);
    border-right: 3px solid rgba(99, 102, 241, 0.5);
}
```

The indicator uses `position: fixed` so it stays aligned with the viewport during scroll. Its `top`/`left`/`width`/`height` are updated on each `pointermove` via `$state` runes.

### Line Detection (Consumer View)

The consumer view (e.g. `metric-mgmt-view`) implements the `onselect` handler:

```typescript
function handleDragSelect(detail: {
    pageNumber: number;
    viewportY1: number;
    viewportY2: number;
    viewport: PdfPageViewport;
}) {
    const { pageNumber, viewportY1, viewportY2, viewport } = detail;
    const pageLines = rawLines.filter((l) => l.page_number === pageNumber);
    const selected = pageLines
        .filter((line) => {
            if (!Array.isArray(line.coords) || line.coords.length < 4) return false;
            const [vx1, vy1, vx2, vy2] = viewport.convertToViewportRectangle(line.coords.slice(0, 4));
            const lineTop = Math.min(vy1, vy2);
            const lineBottom = Math.max(vy1, vy2);
            return Math.max(lineTop, viewportY1) <= Math.min(lineBottom, viewportY2);
        })
        .map((l) => l.line_number);
    pdfSelectedLines = selected;
}
```

**Coordinate math**: Lines have `coords: [x1, y1, x2, y2]` in PDF space (origin bottom-left). `viewport.convertToViewportRectangle()` converts to viewport space. The drag range `[viewportY1, viewportY2]` and each line's viewport-space bounding box are tested for overlap using the standard interval overlap formula: `max(lineTop, dragTop) <= min(lineBottom, dragBottom)`.

### Buffer Lifecycle (PdfViewWindow)

- **Filling**: `selectedLines` is set by the consumer's `onselect` handler via `bind:selectedLines`.
- **Clearing**: A capture-phase `click` listener on `window` clears `selectedLines = []` unless the click target (or an ancestor) matches `.pvw-tool-btn`. This ensures toolbar tool clicks don't erase the buffer before the tool can use it.
- **Reading**: Toolbar buttons read `selectedLines.length` to set their `disabled` state.

### Live Preview During Drag

During an active drag, `SharedPdfViewer` fires the `ondragmove` callback on each `pointermove`. The consumer computes overlapping lines (same overlap math as `handleDragSelect`) and stores them in a separate reactive variable `pdfDragPreviewLines`, which is read by `renderHighlights` to draw temporary highlight marks on the overlay.

**Timeline within a single `pointermove` (all synchronous):**

1. `SharedPdfViewer.onDragPointerMove()` computes the viewport Y range
2. Calls `ondragmove(detail)` → consumer's `handleDragMove` → sets `pdfDragPreviewLines = [lineNumbers]`
3. Calls `paintOverlayForPage(pageNo)` → clears overlay.innerHTML → calls `renderHighlights(pageNo, viewport, overlay)`
4. Consumer's `renderHighlights` draws regular highlights first, then iterates `rawLines` filtered by `pdfDragPreviewLines` and draws green-hued preview marks with class `pdf-highlight-preview`

On `pointerup`:
1. `handleDragSelect` fires and clears `pdfDragPreviewLines = []` as its first action
2. `onselect` is called with the final range
3. `paintHighlights()` repaints all overlays without drag preview lines

**Drag preview CSS** (in consumer's `<style>` block):

```css
:global(.pdf-highlight-preview) {
    position: absolute;
    background: rgba(134, 239, 172, 0.15);
    border-left: 2px solid rgba(74, 222, 128, 0.7);
    border-right: 2px solid rgba(74, 222, 128, 0.7);
}
```

The preview lines use green tones, visually distinct from the crimson-toned regular metric highlights and the blue drag indicator.

**Per-page overlay repaint** (`paintOverlayForPage`):

```typescript
function paintOverlayForPage(pageNo: number) {
    const overlay = document.getElementById(`...-overlay-${pageNo}`) as HTMLDivElement | null;
    const viewport = pdfViewportByPage.get(pageNo);
    if (!overlay || !viewport) return;
    overlay.innerHTML = '';
    renderHighlights?.(pageNo, viewport, overlay);
}
```

Only the overlay for the page being dragged is cleared and repainted — overlays for all other pages are untouched. This keeps the per-frame cost minimal.

### Consumer Wiring

The consumer passes `onselect`, `ondragmove`, and `selectedLines` to `PdfViewWindow`, and manages a `pdfDragPreviewLines` state for live preview:

```typescript
// Consumer state
let pdfSelectedLines = $state<number[]>([]);
let pdfDragPreviewLines = $state<number[]>([]);
```

```svelte
<PdfViewWindow
    ...
    onselect={handleDragSelect}
    ondragmove={handleDragMove}
    bind:selectedLines={pdfSelectedLines}
>
    {#snippet toolbar()}
        <button type="button" class="pvw-tool-btn"
            disabled={pdfSelectedLines.length === 0}
            ...>...</button>
    {/snippet}
</PdfViewWindow>
```

The `handleDragMove` function has the same overlap logic as `handleDragSelect` but stores results in `pdfDragPreviewLines` instead of `pdfSelectedLines`. `renderHighlights` draws both regular highlights and drag preview lines, the latter using the `pdf-highlight-preview` class with green tones.

### Per-Consumer Status

| View | `onselect` wired | `ondragmove` wired | `selectedLines` bound | Drag preview rendering | Toolbar disabled states |
|------|-----------------|-------------------|----------------------|------------------------|------------------------|
| `metric-mgmt-view` | Yes | Yes | Yes | Yes — green `pdf-highlight-preview` marks | Edit Lines, Delete Lines disabled when `selectedLines` is empty |
| Other views | No | No | No | No | N/A |

---

## Add Metric Dialog

The "Add Metric" tool button in `metric-mgmt-view` opens a dialog that lets users review PDF-selected lines, edit or remove entries, extend the selection with adjacent lines, and then create a new metric from the remaining lines.

### Trigger

The toolbar button (`<CirclePlusIcon>`) is always clickable — it does not depend on `selectedLines.length`. This lets users open the dialog even before dragging, to see the empty-state instructions.

### State

| Variable | Type | Role |
|----------|------|------|
| `addMetricOpen` | `boolean` | Dialog open/closed |
| `addMetricEditKey` | `string \| null` | Which line is being edited (`"page:line"`), or null |
| `addMetricEditContent` | `string` | Draft content during inline edit |
| `addMetricSaving` | `boolean` | Loading state during save/extract API calls |

### Derived Data

`addMetricDialogLines` resolves the raw line-number buffer (`addMetricBufferLines: number[]`) against the full `rawLines` array, deduplicating by `page_number:line_number` key. The result is sorted by line number. Note that the read buffer is a **dedicated buffer** (`addMetricBufferLines`) set during drag-select — separate from `pdfSelectedLines` which is cleared on click-away:

```typescript
let addMetricDialogLines = $derived.by(() => {
    const seen = new Set<string>();
    const result: Array<RawLine & { key: string }> = [];
    for (const lineNo of addMetricBufferLines) {
        for (const ln of rawLines) {
            if (ln.line_number !== lineNo) continue;
            const key = `${ln.page_number}:${ln.line_number}`;
            if (seen.has(key)) continue;
            seen.add(key);
            result.push({ ...ln, key });
        }
    }
    return result.sort((a, b) => a.line_number - b.line_number);
});
```

### Adjacent Line Insertion

The dialog provides two **"+ Add"** buttons to extend the selected line set with adjacent document lines:

| Button | Position | Action | Guard |
|--------|----------|--------|-------|
| `+ Add` | _Section head, right of "SELECTED LINES"_ | Inserts the line immediately before the first selected line | Disabled when `!canAddPrevious` (no earlier line exists in the document) |
| `+ Add` | _Table foot, right-aligned_ | Inserts the line immediately after the last selected line | Disabled when `!canAddNext` (no later line exists in the document) |

Both derive their enabled state from `rawLines`:

```typescript
let canAddPrevious = $derived.by(() => {
    if (addMetricBufferLines.length === 0 || rawLines.length === 0) return false;
    const minLine = Math.min(...addMetricBufferLines);
    return rawLines.some((ln) => ln.line_number < minLine);
});
let canAddNext = $derived.by(() => {
    if (addMetricBufferLines.length === 0 || rawLines.length === 0) return false;
    const maxLine = Math.max(...addMetricBufferLines);
    return rawLines.some((ln) => ln.line_number > maxLine);
});
```

The insert functions search for the closest eligible line number not already in the buffer:

```typescript
function addPreviousLine() {
    if (addMetricBufferLines.length === 0) return;
    const minLine = Math.min(...addMetricBufferLines);
    const prev = rawLines
        .filter((ln) => ln.line_number < minLine && !addMetricBufferLines.includes(ln.line_number))
        .sort((a, b) => b.line_number - a.line_number)[0];
    if (prev) addMetricBufferLines = [prev.line_number, ...addMetricBufferLines];
}

function addNextLine() {
    if (addMetricBufferLines.length === 0) return;
    const maxLine = Math.max(...addMetricBufferLines);
    const next = rawLines
        .filter((ln) => ln.line_number > maxLine && !addMetricBufferLines.includes(ln.line_number))
        .sort((a, b) => a.line_number - b.line_number)[0];
    if (next) addMetricBufferLines = [...addMetricBufferLines, next.line_number];
}
```

The "+ Add" buttons use teal-tinted styling (`rgba(93, 175, 168, ...)`) to visually distinguish them from destructive/cancel actions.

### Selected Lines Dialog Layout

```
┌────────────────────────────────────────────────────────────────────────────┐
│  KB.Metrics                                                                │
│  Add Metric                                                                │
│  Review selected lines, edit content, or remove                            │
│  unwanted entries before extracting a metric.                              │
├────────────────────────────────────────────────────────────────────────────┤
│  ┌─ dialog-section ──────────────────────────────────────────────────────┐ │
│  │  SELECTED LINES    3 lines selected   [+ Add]                         │ │
│  │  ┌──────────────────────────────────────────────────────────────────┐ │ │
│  │  │ Line #│ Page│ Type  │ Content │ Actions                          │ │ │
│  │  ├───────┼─────┼───────┼─────────┼──────────────────────────────────┤ │ │
│  │  │  90   │  1  │ text  │ Revenue │ Edit Remove                      │ │ │
│  │  │  91   │  1  │ text  │ $1.2M   │ Edit Remove                      │ │ │
│  │  │  92   │  1  │ text  │ (YoY)   │ Save Cancel                      │ │ │
│  │  └──────────────────────────────────────────────────────────────────┘ │ │
│  │                                                             [+ Add]   │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
├────────────────────────────────────────────────────────────────────────────┤
│  [Help]                       [Close] [Extract Provisions] [Extract Metric]│
└────────────────────────────────────────────────────────────────────────────┘
```

Close button is moved from the top-right header to the footer, left of the primary "Extract Metric" button.

### Columns

| Column | Source | Notes |
|--------|--------|-------|
| Line # | `line.line_number` | Monospace, from raw line data |
| Page | `line.page_number` | Monospace, from raw line data |
| Type | `line.line_type` | Rendered as a small badge (`.am-type-badge`) |
| Content | `line.content` | When editing: replaced with a styled `<input>` (`.am-edit-input`). Otherwise: displayed with `white-space: pre-wrap` |
| Actions | — | Dual-state: shows **Edit** + **Remove** normally, or **Save** + **Cancel** when the row is being edited |

### Edit Flow

1. Clicking **Edit** calls `startEditDialogLine(key, content)`, setting `addMetricEditKey` to the line key and `addMetricEditContent` to the current content.
2. The content cell switches to an `<input>` field, and the action cell shows **Save** / **Cancel** buttons.
3. **Cancel** calls `cancelEditDialogLine()` which clears both state values, reverting the row.
4. **Save** calls `saveEditDialogLine(pageNo, lineNo)`:
   - Prompts the user via `window.confirm('Save changes to the original file?')`
   - On confirmation: calls `updateRawLine` (PATCH `/api/v1/kb/raw-lines`) with the updated content
   - On success: updates `rawLines` in-place (so the change is reflected immediately in the lines view)
   - On failure: shows an `alert` with the error message
5. **Enter** key on the input also triggers save; **Escape** triggers cancel.

### Remove Flow

Clicking **Remove** calls `deleteDialogLine(key)`, which filters the line out of `addMetricBufferLines`. Removal is **local to the dialog only** — the underlying raw line is not deleted from the file. The removed line will not be included when the user clicks "Extract Metric".

### Extract Metric Flow

Clicking **Extract Metric** (disabled when `addMetricDialogLines` is empty or `addMetricSaving` is true):

1. Builds a `SourceLineSpan[]` from `addMetricDialogLines` (only `page_number` and `line_number` per span)
2. Calls `createKbMetric` (POST `/api/v1/kb/metrics`)
3. On success: appends the new metric to the `metrics` list and closes the dialog
4. On failure: shows an `alert` with the error message

### Help Button

Opens a `window.alert` with usage instructions explaining the drag-select, edit, remove, and extract workflow.

### Keyboard

| Key | Context | Action |
|-----|---------|--------|
| `Escape` | Dialog open | Closes the dialog (via `onkeydown` on the overlay) |
| `Escape` | Editing a row | Cancels the edit |
| `Enter` | Editing a row | Saves the edit |

### API Endpoints Used

| Endpoint | Method | Function | Purpose |
|----------|--------|----------|---------|
| `/api/v1/kb/raw-lines` | `PATCH` | `updateRawLine` | Save edited line content to the original file |
| `/api/v1/kb/metrics` | `POST` | `createKbMetric` | Create a new metric record with the selected line spans |

### CSS Classes

The dialog table uses scoped classes (prefixed with `am-`) in `metric-mgmt-view`'s `<style>` block:

| Class | Element | Purpose |
|-------|---------|---------|
| `.am-table` | `<table>` | Full-width collapsed border table |
| `.am-table thead th` | `<th>` | Sticky header with uppercase labels |
| `.am-table td` | `<td>` | Cell padding and vertical alignment |
| `.am-mono` | numeric `<td>` | Monospace font for line/page numbers |
| `.am-type-badge` | `<span>` | Small badge for line type |
| `.am-edit-input` | `<input>` | Editing input with brass border and focus glow |
| `.am-btn` | `<button>` | Base button style (rounded, mono, 28px height) |
| `.am-btn-edit` | Edit button | Neutral ghost with visible border |
| `.am-btn-remove` | Remove button | Crimson tint (was previously `.am-btn-delete`) |
| `.am-btn-save` | Save button | Brass tint |
| `.am-btn-cancel-row` | Cancel button | Muted ghost |
| `.am-btn-head-add` | Section-head "+ Add" | Teal tint, `margin-left: auto` to push right |
| `.am-btn-foot-add` | Table-foot "+ Add" | Teal tint, right-aligned via `am-table-foot` flex |
| `.am-btn-help` | Help button | Muted, transparent |
| `.am-btn-foot-cancel` | Close button | Visible neutral button |
| `.am-btn-foot-extract` | Extract Metric button | Reuses `.dialog-search-btn` — bright amber `#d4a24c` |
| `.am-table-foot` | `<div>` after `</table>` | `display: flex; justify-content: flex-end` |

Both `+ Add` buttons are disabled (`opacity: 0.4; cursor: not-allowed`) when no adjacent line exists in the document.

### Empty State

When no lines are selected (`addMetricDialogLines.length === 0`), the dialog body shows a centered empty state with a "§" glyph, "No lines selected" title, and instructions to drag on the PDF to select lines.