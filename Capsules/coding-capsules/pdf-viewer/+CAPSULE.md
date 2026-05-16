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
| `pdf-view-window.svelte` | Reusable wrapper; manages sidebar width, resize handle, and built-in selection dialog |
| `pdf-line-selection-dialog.svelte` | Self-contained "Add Metric / Extract Provision" dialog — rendered by `PdfViewWindow` by default |
| `inputs-mgmt-view.svelte` | Document Details view — uses `PdfViewWindow` |
| `metric-mgmt-view.svelte` | Metrics view — uses `PdfViewWindow` with its own `onselect` handler |
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
| `enableSelectionDialog` | `boolean` | `true` | When `true` (default) and no external `onselect` is provided, activates the built-in drag-select → "Add Metric / Extract Provision" dialog. Pass `false` to opt out entirely. |
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

### `metric-mgmt-view` Add Metric dialog

The Metrics view uses PDF drag-selection to open an **Add Metric** dialog. This dialog now supports a two-step metric workflow:

1. Review and optionally edit/remove the selected source lines.
2. Press **Extract Metric** to call the backend extraction API.
3. While extraction is running, the dialog shows a spinner because the LLM call may take a while.
4. When the response returns, the dialog lists **all extracted metrics** returned by the backend.
5. Users may remove any unwanted extracted metrics from the preview list.
6. Press **Save** to persist only the remaining metrics to `kb.metrics`.

The extraction step no longer writes directly to the database. Persistence happens only after the user reviews the previewed metrics and confirms with **Save**.

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
| `doc-structure-view` | Edit Line Type · *sep* · Edit Coordinates · *sep* · Delete Line |

#### `metric-mgmt-view` tool details

| Tool | Behaviour |
|------|----|
| Edit Lines | Toggles edit-line mode (highlighted when active). Mutually exclusive with Delete Lines — activating one clears the other. |
| Delete Lines No | Toggles delete-line mode (highlighted when active). Mutually exclusive with Edit Lines. |
| Add Line Yes | Toggles the "Add Line" panel open/closed (highlighted while open). |
| Show Lines Yes | Switches between the PDF canvas view and the lines view. When active the icon changes (List → FileText) and the button title becomes "Show PDF Document". |

#### `doc-structure-view` tool details

| Tool | Enabled when | Behaviour |
|------|-------------|-----------|
| Edit Line Type (`SquarePenIcon`) | A line is selected | Opens the inline type-select dropdown in the sidebar. |
| Edit Coordinates (`CrosshairIcon`) | A line is selected | Enters coord-edit mode. Button shows `.active` highlight; title becomes "Cancel coordinate edit". Clicking again cancels. |
| Delete Line (`Trash2Icon`) | A line is selected and no delete in progress | Opens the delete-confirm dialog. |

---

## Edit Coordinates Feature (`doc-structure-view`)

### Overview

The **Edit Coordinates** tool in `doc-structure-view` lets users repair the bounding-box coordinates stored for a document structure line. Only `doc-structure-view` supports line selection (via the line list panel), so this tool only appears there.

### Files Changed

| File | Change |
|------|--------|
| `doc-structure-view.svelte` | New state vars, `renderCoordEditor`, `makeHandle`, `startEditCoords`, `cancelEditCoords`, `saveEditCoords`; toolbar button; updated `renderStructureHighlights` and `highlightVersion` prop |
| `web/src/lib/services/kbService.ts` | Added `coords?: number[]` to `UpdateDocStructureLinePayload` |
| `server/api/kbhandler/doc_structure_handler.go` | Added `Coords *[]float64` to `updateDocStructureLineRequest`; updated validation and update loop to apply it |

### State

| Variable | Type | Role |
|----------|------|------|
| `editingCoordsMode` | `boolean` | Whether the coord editor is active |
| `editCoordsDraft` | `number[]` | Current `[x1, y1, x2, y2]` in PDF space, mutated during editing |
| `editCoordsSaving` | `boolean` | True while the PATCH call is in flight |
| `editCoordsError` | `string` | Last save error message (shown via `window.alert`) |

### Type Extension

`PdfPageViewport` (the basic type used by `renderHighlights` callback) only exposes `convertToViewportRectangle`. A separate `PdfPageViewportFull` extends it with `convertToPdfPoint(x, y): number[]`, which is a real PDF.js `PageViewport` method available at runtime. `renderStructureHighlights` casts `viewport as PdfPageViewportFull` before passing it to `renderCoordEditor`.

### Entry / Exit Flow

```
User clicks "Edit Coordinates" button
  → startEditCoords()
      guards: selectedLine != null AND selectedLine.coords.length >= 4
      editCoordsDraft = [...selectedLine.coords.slice(0, 4)]
      editingCoordsMode = true
      highlightSelectionVersion++     ← triggers highlightVersion prop change

highlightVersion prop changes
  → SharedPdfViewer $effect fires
      → tick() → paintHighlights() → paintOverlayForPage(page)
        → renderStructureHighlights(pageNo, viewport, overlay)
            checks editingCoordsMode && editCoordsDraft.length >= 4
            → renderCoordEditor(viewport as PdfPageViewportFull, overlay)

User clicks "Cancel" (or selects a different line)
  → cancelEditCoords()  (or $effect on selectedLineKey)
      editingCoordsMode = false
      editCoordsDraft = []
      highlightSelectionVersion++     ← re-renders static highlight

User clicks "Save"
  → saveEditCoords()
      PATCH /api/v1/kb/doc-structure  { coords: editCoordsDraft }
      on success: lines updated, selectLine(updatedLine), editingCoordsMode = false
      on error: window.alert(editCoordsError)
```

### `renderCoordEditor` — Interactive Overlay

The function is called from inside `renderHighlights`, which runs inside `paintOverlayForPage`. It builds the interactive overlay entirely with imperative DOM calls (no Svelte reactivity inside the function).

**Coordinate tracking**

```
editCoordsDraft [x1, y1, x2, y2]  ← PDF space (origin bottom-left)
  ↓ viewport.convertToViewportRectangle()
vLeft, vTop, vRight, vBottom       ← raw viewport-space boundaries (no padding)
  ↓ ± PAD_H/PAD_V (5px / 4px)
displayed rect position and size   ← matches static highlight dimensions exactly
```

**Elements created (all children of the `pdf-overlay` div)**

| Element | CSS `pointer-events` | Purpose |
|---------|---------------------|---------|
| `rectEl` | `auto` | Filled amber rect (`rgba(212,162,76,0.3)`), same background/outline as static highlight; `cursor:move` |
| `hTL hTC hTR` | `auto` | Top-row handles (corners + edge mid): 8×8 px white square, gold border; cursors `nwse-resize`, `n-resize`, `nesw-resize` |
| `hML hMR` | `auto` | Left/right edge midpoint handles; cursors `w-resize`, `e-resize` |
| `hBL hBC hBR` | `auto` | Bottom-row handles; cursors `nesw-resize`, `s-resize`, `nwse-resize` |
| `btnPanel` | `none` (panel) / `auto` (buttons) | Row of **Save** (amber) + **Cancel** (muted) buttons, positioned 8 px below the rect |

The `pdf-overlay` parent has `pointer-events: none` (scoped CSS in `SharedPdfViewer`). Children with `pointer-events: auto` still receive pointer events; events bubble up through the `pointer-events: none` ancestor normally.

**Drag mechanics (`attachDrag`)**

Each draggable element gets a `pointerdown` handler that:
1. Calls `e.stopPropagation()` — prevents the PDF canvas-host drag-select from triggering
2. Calls `el.setPointerCapture(e.pointerId)` — keeps drag alive even if pointer leaves the element
3. Snapshots the four raw viewport boundaries into `sv = { l, t, r, b }`
4. On each `pointermove`: calls `applyDelta(sv, dx, dy)` → updates `vLeft/vTop/vRight/vBottom` → calls `applyLayout()` to reposition elements via direct `style` writes (no Svelte re-render during drag)
5. On `pointerup`: calls `commitCoords()`

**`commitCoords()`**

```typescript
const [x1, y1] = viewport.convertToPdfPoint(Math.min(vLeft, vRight), Math.max(vTop, vBottom));
const [x2, y2] = viewport.convertToPdfPoint(Math.max(vLeft, vRight), Math.min(vTop, vBottom));
editCoordsDraft = [x1, y1, x2, y2];
highlightSelectionVersion++;
```

`convertToPdfPoint(viewportX, viewportY)` is the inverse of `convertToViewportRectangle`. For a typical unrotated page: `x_pdf = vx / scale`, `y_pdf = pageHeight − vy / scale`. This correctly handles rotation via PDF.js's internal transform.

### `highlightVersion` prop

```svelte
highlightVersion={editingCoordsMode && editCoordsDraft.length >= 4
    ? `edit:${editCoordsDraft.join(',')}:${highlightSelectionVersion}`
    : selectedHighlightTarget
    ? `${selectedHighlightTarget.page}:${selectedHighlightTarget.coords.join(',')}:${selectedHighlightTarget.version}`
    : `${selectedLineKey ?? ''}:${highlightSelectionVersion}`}
```

During editing the version string uses the `edit:` prefix and embeds the current draft coords, so any drag commit (which changes `editCoordsDraft` and increments `highlightSelectionVersion`) produces a new version string and triggers a re-render of the interactive overlay at the updated position.

### Backend — `PATCH /api/v1/kb/doc-structure`

`updateDocStructureLineRequest` gained:
```go
Coords *[]float64 `json:"coords"`
```
Validation now allows the request if any of `CorrectedLineType`, `Content`, or `Coords` is non-nil. When `Coords` is provided, `lines[i].Coords = *req.Coords` is applied before `writeTxtLinesFile` and `upsertManualFile`.

### Debug Logging

Console logs prefixed `[coord-editor]` are present in `startEditCoords`, `renderStructureHighlights`, `renderCoordEditor`, and `commitCoords` to trace the activation flow and coordinate values during development.

#### Select dialog actions

| Action | Behaviour |
|--------|-----------|
| Extract Provisions | Calls the LLM extract API (with ±5-line overlap context) and shows a loading spinner. Returns provision cards for review; users may remove unwanted ones before saving. |
| Extract Metric | Calls the extract API and shows a loading spinner until the extracted metrics return. |
| Remove (preview provision/metric) | Removes a previewed item from the list without saving it. |

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
| `onselect` | `(ranges: Array<{pageNumber, viewportY1, viewportY2, viewport}>) => void` | Called on drag release with one entry per covered page. `viewportY1`/`viewportY2` are in viewport space, clamped to each page's canvas height. A click with no drag (< 5 px) does not fire the callback. |
| `ondragmove` | Same shape as `onselect` | Called on each `pointermove` during drag with the current page ranges. Enables live preview of overlapping lines while dragging, including across page boundaries. |

**`PdfViewWindow`** — new props:

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `selectedLines` | `number[]` | `[]` | Bindable; the buffer of selected line numbers. Cleared on click-away. |
| `enableSelectionDialog` | `boolean` | `true` | Activates the built-in selection dialog (see below). |
| `onselect` | Same as `SharedPdfViewer`'s | — | Passed through to `SharedPdfViewer` so the consumer gets the drag ranges. When provided, the built-in dialog is suppressed. |
| `ondragmove` | Same as `SharedPdfViewer`'s | — | Passed through to `SharedPdfViewer` for live preview during drag. Ignored when the built-in dialog is active. |

### Gesture Mechanics (SharedPdfViewer)

The drag gesture uses the **Pointer Events API** on `.pdf-canvas-host`:

1. **`pointerdown`**: Records `clientY`, identifies the page via `closest('[data-page]')`, captures the pointer with `setPointerCapture`, sets `dragSelecting = true`.
2. **`pointermove`**: Updates a `position: fixed` indicator overlay div that spans the vertical drag range. Fires `ondragmove` with the current viewport Y range, then calls `paintOverlayForPage()` to immediately repaint the dragged page's overlay. The consumer's `renderHighlights` draws both regular highlights and drag preview lines (via `pdfDragPreviewLines`).
3. **`pointerup`**: Calls `getPageRanges(clientY1, clientY2)` to find every rendered page whose canvas overlaps the drag range, computes clamped viewport Y values for each, and fires `onselect(ranges)`. If the total drag is < 5 px the callback is suppressed. Then calls `paintHighlights()` to restore normal overlays.

**Cross-page selection** — `getPageRanges` iterates `pdfViewportByPage`, looks up each canvas element via DOM id, and checks whether `[clientY1, clientY2]` intersects `[canvasRect.top, canvasRect.bottom]`. For overlapping pages, the viewport Y range is clamped to `[0, viewport.height]`, so page N gets `[dragStartRelative, pageNBottom]` and page N+1 gets `[0, dragEndRelative]`.

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

| View | Selection mode | Drag preview | Dialog |
|------|---------------|--------------|--------|
| `metric-mgmt-view` | Custom `onselect` + `ondragmove` | Green `pdf-highlight-preview` marks (consumer-owned) | Consumer-owned "Add Metric" dialog; built-in dialog suppressed |
| All other views | Built-in (`enableSelectionDialog=true`) | Green `pdf-highlight-preview` marks (built-in) | `PdfLineSelectionDialog` rendered by `PdfViewWindow` |

### Implementation Pitfalls

These four issues were found and fixed after the initial implementation. Document them here so they are avoided on the first shot in any future re-implementation.

---

**1. The dialog overlay must not block or blur the PDF.**

Do **not** put `background` or `backdrop-filter: blur(…)` on the overlay wrapper. The user still needs to read the document while the dialog is open. Set the overlay to `pointer-events: none` so all clicks pass through to the PDF canvas. Give the dialog shell itself `pointer-events: auto` so it still receives its own events. There is no click-away-to-close in this design; the user closes explicitly via the Close button or Escape.

---

**2. `onselect` / `ondragmove` must carry an array of page ranges, not a single page.**

If the callback carries only `{ pageNumber, viewportY1, viewportY2, viewport }` for the page where the drag *started*, a drag that crosses a page boundary silently loses all lines on subsequent pages. The correct signature is `Array<{ pageNumber, viewportY1, viewportY2, viewport }>`.

In `SharedPdfViewer`, implement a `getPageRanges(clientY1, clientY2)` helper that iterates every entry in `pdfViewportByPage`, looks up each page's canvas element via `document.getElementById(…)`, checks whether `[clientY1, clientY2]` overlaps `[canvasRect.top, canvasRect.bottom]`, and builds a clamped viewport-Y entry for each overlapping page. Sort by `pageNumber` before returning. Use this helper in both `onDragPointerMove` (for live preview) and `onDragPointerUp` (for the final selection).

During `onDragPointerMove`, call `paintOverlayForPage(r.pageNumber)` for **every** range returned, not just the starting page — otherwise the live green preview only appears on one page while the drag indicator spans multiple.

All consumers (`handleBuiltinSelect`, `handleBuiltinDragMove`, `handleDragSelect`, `handleDragMove`, and `PdfLineSelectionDialog`'s `$effect`) must iterate the full array and accumulate lines from each page.

---

**3. Changing `highlightVersion` (or any version wired into it) from inside the dialog-open handler scrolls the PDF back to `page`, which defaults to 1.**

`SharedPdfViewer` has a `$effect` that watches `highlightVersion`. After calling `paintHighlights()`, it calls `scrollToFirstHighlight(page)` and falls back to `scrollToPage(page)`. If `page` has never been updated from user navigation (it defaults to `1`), this scrolls to page 1 every time.

Do **not** increment any version counter from inside `handleBuiltinSelect`. The trailing `paintHighlights()` call already made in `SharedPdfViewer.onDragPointerUp` (right after `onselect()`) is sufficient to repaint the overlays.

For repaints that must not scroll (e.g., clearing highlights when the dialog closes), add a separate `repaintVersion` prop to `SharedPdfViewer` backed by its own `$effect` that calls only `paintHighlights()` with no scroll side-effect. Never reuse `highlightVersion` for this purpose.

---

**4. Do not clear `builtinDragPreviewLines` when the dialog opens.**

If `builtinDragPreviewLines` is set to `[]` in `handleBuiltinSelect`, the trailing `paintHighlights()` call redraws the overlays with no green lines, erasing the selection highlight the moment the dialog appears. The user can no longer see which lines they selected.

The correct lifecycle is:
- *Dialog opens*: leave `builtinDragPreviewLines` as-is. `paintHighlights()` redraws with the green lines still present.
- *Dialog closes*: clear `builtinDragPreviewLines` in a `$effect` that detects the `builtinDialogOpen` false transition, then increment `builtinRepaintVersion` to trigger a scroll-free repaint via `repaintVersion`.

A guard (e.g., `builtinDialogPrevOpen`) prevents the close-effect from firing spuriously on component initialization when `builtinDialogOpen` is already `false`.

---

## Selection Dialog (`PdfLineSelectionDialog`)

### Overview

The drag-select → "Selection Dialog" is available in **all** uses of `PdfViewWindow` by default, not only in `metric-mgmt-view`. It is opt-out: passing `enableSelectionDialog={false}` disables it, as does supplying a custom `onselect` prop (which signals the consumer is managing selection itself).

The dialog has an 'Operation' pulldown menu, which has the following operations:
| Operation | What It Does |
|-----------|--------------|
| Ask AI | It asks AI about the selected content |
| Extract Metrics | It uses an LLM to extract metrics from the selected content. Refer to [4] for information about extracting metrics. |
| Extract Provisions | It uses an LLM to extract compliance provisions. Refer to [2] and [3] for information about extracting provisions. |
| Extract References | Users can manually or use an LLM to extract references from the selected content |
| Write Comments | It offers a text editor to let users write comments about the selected content |

#### 'Run' Button
There is a 'Run' button next to the 'Operation' pulldown menu. This button is disabled by default. It is enabled when and only when users select "Extract Provisions" or "Extract Metrics". Click the "Run" button will actually run the operation.

#### 'Save' Button
Persist the currently previewed metrics to `kb.metrics` or the previewed provisions to `kb.provisions`. |

#### 'Close' Button
Press this button to close the dialog.

### Activation Logic

`PdfViewWindow` computes a single derived flag:

```typescript
let useBuiltinDialog = $derived(enableSelectionDialog && !onselect);
```

When `useBuiltinDialog` is `true`, `PdfViewWindow`:
- Wires its own `handleBuiltinSelect` / `handleBuiltinDragMove` as the effective `onselect` / `ondragmove` passed to `SharedPdfViewer`
- Wraps any external `renderHighlights` prop inside `renderBuiltinHighlights` (so per-view highlights — chunk, topic, structure — still appear)
- Renders `<PdfLineSelectionDialog>` in the template

When `useBuiltinDialog` is `false`, all three effective props fall back to whatever the consumer passed (or `undefined`), and no dialog is rendered — identical to the previous behaviour.

### `rawLines` Fetching

`PdfViewWindow` fetches raw lines internally when the built-in dialog is active:

```typescript
$effect(() => {
    if (!useBuiltinDialog || inputId == null || inputId === builtinRawLinesInputId) return;
    builtinRawLinesInputId = inputId;
    builtinRawLines = [];
    getRawLines(inputId)
        .then((res) => {
            if (inputId === builtinRawLinesInputId) builtinRawLines = res.lines ?? [];
        })
        .catch(() => {});
});
```

The guard `inputId === builtinRawLinesInputId` prevents re-fetching when the component re-renders without a document change. The stale-guard in `.then()` drops results that arrived after a document switch.

### Drag Preview Highlights

The built-in mode replicates the green line-highlight behaviour of `metric-mgmt-view` exactly:

**`handleBuiltinDragMove`** — called on each `pointermove` during drag; filters `builtinRawLines` for the dragged page and viewport Y overlap (same interval math as the consumer pattern), writing the result to `builtinDragPreviewLines`.

**`renderBuiltinHighlights`** — passed as `renderHighlights` to `SharedPdfViewer`:
1. Calls the external `renderHighlights` prop first (preserving chunk / topic / structure highlights).
2. Then iterates `builtinRawLines`, draws a `pdf-highlight-preview` div for each line in `builtinDragPreviewLines`.

Since `SharedPdfViewer.onDragPointerMove` calls `paintOverlayForPage(pageNo)` synchronously *after* invoking `ondragmove`, the state update (`builtinDragPreviewLines = …`) is already committed by the time `renderBuiltinHighlights` reads it.

**Highlight lifecycle across the drag → dialog → close sequence:**

- *During drag*: `handleBuiltinDragMove` fills `builtinDragPreviewLines`; `SharedPdfViewer` calls `paintOverlayForPage` for each covered page synchronously after the callback, so the green preview appears immediately.
- *On release*: `handleBuiltinSelect` is called by `SharedPdfViewer.onDragPointerUp` **before** the trailing `paintHighlights()`. `builtinDragPreviewLines` is intentionally **not** cleared here, so `paintHighlights()` redraws the overlays with the green lines still showing — the selection stays visible while the dialog is open.
- *On dialog close*: a `$effect` in `PdfViewWindow` detects the `builtinDialogOpen` false transition, clears `builtinDragPreviewLines`, and increments `builtinRepaintVersion`. This triggers the `repaintVersion` effect in `SharedPdfViewer`, which calls `paintHighlights()` without scrolling, removing the green lines.

**`repaintVersion` vs `highlightVersion` in `SharedPdfViewer`:**

`SharedPdfViewer` has two separate paint effects:
- `highlightVersion` → `paintHighlights()` + scroll to first highlight / current page. Used by consumers to signal new persistent highlights.
- `repaintVersion` → `paintHighlights()` only, no scroll. Passed by `PdfViewWindow` as `builtinRepaintVersion` for internal repaint-without-scroll needs (dialog close).

### `pdf-highlight-preview` CSS

The `:global(.pdf-highlight-preview)` rule is defined in `pdf-view-window.svelte`'s `<style>` block so it is available in all views, regardless of whether `metric-mgmt-view` has been rendered:

```css
:global(.pdf-highlight-preview) {
    position: absolute;
    background: rgba(22, 163, 74, 0.16);
    border: 1px solid rgba(22, 163, 74, 0.55);
    box-shadow: inset 0 0 0 1px rgba(134, 239, 172, 0.15);
}
```

Previously the rule lived only in `metric-mgmt-view.svelte` as `:global`, so it was absent until that view was loaded.

### `PdfLineSelectionDialog` Component

**File:** `pdf-line-selection-dialog.svelte`

Self-contained component extracted from the "Add Metric" dialog in `metric-mgmt-view`. It has no knowledge of the surrounding view — all data it needs is passed as props.

**Props:**

| Prop | Type | Description |
|------|------|-------------|
| `inputId` | `number \| null` | Used in backend API calls (extract, save, provision) |
| `open` | `boolean` (bindable) | Dialog visibility |
| `rawLines` | `RawLine[]` | Full line list for the document; used to resolve line numbers to content and to support "+ Add" navigation |
| `selectionDetail` | `Array<{ pageNumber, viewportY1, viewportY2, viewport }> \| null` | All covered page ranges from the drag; the dialog derives selected lines from each range on each change, accumulating across pages |
| `onrawlineupdate` | `(updated: RawLine) => void` | Called after a line-edit save; the parent updates its `rawLines` copy |

**Internal state computed from `selectionDetail`:**

On each change to `selectionDetail`, a `$effect` iterates all page ranges and re-runs the viewport-overlap hit-test for each, accumulating results into `bufferLines: number[]`. The rest of the dialog logic (edit/remove/add-adjacent/extract/save/provision) operates on `bufferLines` and is identical to the original single-page implementation.

**CSS:** The dialog is fully self-contained — it defines all its own styles (`.dialog-overlay`, `.dialog`, `.am-*`, `.chip-*`, etc.) and sets its own dark-theme token variables on the overlay element. It does not inherit tokens from the surrounding view, so it looks identical regardless of which view hosts it.

**Overlay behaviour:** The `.dialog-overlay` has `pointer-events: none` and no background or `backdrop-filter`, so the PDF canvas behind the dialog remains fully visible and interactive while the dialog is open. The dialog itself sets `pointer-events: auto` to receive its own events. Close-on-overlay-click is intentionally absent; use the Close button or Escape key.

**Moveable dialog:** The `.dialog-head` element acts as a drag handle. On `pointerdown` it calls `setPointerCapture` so `pointermove`/`pointerup` are reliably delivered during drag. State variables `translateX`/`translateY` accumulate the drag delta and are applied as `transform: translate(…)` on the dialog shell. Both values reset to `0` whenever `open` transitions to `true`, so the dialog re-centres on each new selection.

**API calls made:**

| Function | Endpoint | Trigger |
|----------|----------|---------|
| `extractKbMetrics` | `POST /api/v1/kb/metrics/extract` | "Run" button (Extract Metrics) |
| `saveExtractedKbMetrics` | `POST /api/v1/kb/metrics/save-extracted` | "Save" button (after metric review) |
| `extractKbProvisions` | `POST /api/v1/kb/provisions/extract` | "Run" button (Extract Provisions) |
| `saveExtractedKbProvisions` | `POST /api/v1/kb/provisions/save` | "Save" button (after provision review) |
| `updateRawLine` | `PATCH /api/v1/kb/raw-lines` | "Save" on an edited line row |

### Opt-out Patterns

| Scenario | How to opt out |
|----------|----------------|
| View manages its own dialog (`metric-mgmt-view`) | Provide `onselect={myHandler}` — `useBuiltinDialog` becomes `false` automatically |
| View wants no dialog and no drag-select at all | Pass `enableSelectionDialog={false}` |
| View wants drag-select for a custom purpose | Provide `onselect` + `ondragmove`; built-in dialog is suppressed |

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

### Extract Provisions Flow

The Extract Provisions operation follows the same two-step extract→review→save pattern as Extract Metrics.

**Backend endpoints** — implemented in `ChenWeb/server/api/kbhandler/extract-provision-handler.go`:

| Endpoint | Handler | Purpose |
|----------|---------|---------|
| `POST /api/v1/kb/provisions/extract` | `ExtractProvisions` | Reads the raw line file, adds ±5-line overlap context, calls the LLM, returns normalized provision objects |
| `POST /api/v1/kb/provisions/save` | `SaveExtractedProvisions` | Upserts reviewed provisions into `kb.provisions` with sequential `prov_id` values |

**LLM input composition:**
- The handler resolves `result_filename` from `kb.inputs` and opens the corresponding `.txt` raw line file.
- Lines inside the user selection carry flag `n` (normal); lines ±5 before/after the selection carry flag `o` (overlap/context).
- Each line is formatted as: `<flag>\t<line_number>\t<page_number>\t<line_type>\t<content>`.
- The prompt file is read from `EXTRACT_PROVISIONS_PROMPT` (default: `prompt-extract-provisions.md`), and the model from `EXTRACT_PROVISIONS_MODEL_NAME` + `EXTRACT_PROVISIONS_MODELS_FILE`.

**LLM response normalization** — `normalizeExtractedProvisions` maps LLM field aliases to canonical names before returning to the frontend (e.g., `name`/`provision_name` → `prov_name`, `type`/`provision_type` → `provision_type`, `context`/`prov_context` → `prov_context`).

**Save logic** — `saveExtractedProvisions` queries `MAX(prov_id)` per `input_record_id` then assigns sequential IDs starting from `maxProvID + 1`. Uses `ON CONFLICT (input_record_id, prov_id) DO UPDATE` so re-runs are idempotent.

**Frontend flow** (in `pdf-line-selection-dialog.svelte`):

1. User selects operation "Extract Provisions" from the Operation dropdown and clicks **Run**.
2. `extractProvision()` calls `extractKbProvisions({ record_id, source_line_spans })`.
3. While the LLM call is in flight, `busyAction = 'extract'` shows a spinner.
4. On return, `provisionPreview` is set to the array of provision objects returned by the backend.
5. Each provision is shown as a card displaying its name, type, confidence %, and description. A **Remove** button removes a card from the list without saving.
6. Clicking **Save** calls `saveExtractedKbProvisions({ record_id, provisions: provisionPreview })` and closes the dialog.

**Frontend types** (in `kbService.ts`):

```typescript
ExtractedKbProvision   // prov_name, provision_type, provision, provision_en, prov_desc, prov_context, confidence, ...
ExtractKbProvisionsPayload    // { record_id, source_line_spans }
ExtractKbProvisionsResponse   // { status, provisions?, language?, error? }
SaveExtractedKbProvisionsPayload  // { record_id, provisions }
SaveExtractedKbProvisionsResponse // { status, inserted?, error? }
```

**Error code range:** `CWB_KB_P_400` – `CWB_KB_P_434`

Refer to [2] and [3] for the provision data model and the full LLM prompt specification.

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

## References
[1] Doc Processor, 'KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md

[2] Extract Provisions Spec, 'extract-provisions-spec.md'

[3] Extract Provisions Implementation, 'extract-provisions-impl.md'

[4] Extract Metric Spec, 'extract-metrics-spec.md'
