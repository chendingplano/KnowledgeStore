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
    sidebarMinWidth={260}
    sidebarMaxWidth={620}
    sidebarDefaultWidth={340}
>
    {#snippet sidebar()}
        <aside class="my-panel">
            <!-- panel content -->
        </aside>
    {/snippet}
</PdfViewWindow>
```

The `sidebar` snippet is optional. When omitted, `PdfViewWindow` renders `SharedPdfViewer` without any sidebar.

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
