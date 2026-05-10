# PDF Viewer — Toolbar in Page Bar

## Overview

The PDF viewer toolbar (tool buttons that control annotation modes, line editing, etc.) is used to provide
tools for users to manipulate the PDF documents (actually, the content behind the displayed document).

## Toolbar

| Tool | Enabled/Disabled | Explanation |
|------|--------|-----|
| Add Metrics | Always enabled | Add new metrics based on the selected lines or user entered content |
| Add Compliance Provisions | Always Enabled | Add new provisions based on the selected lines or user entered content |
| Change Line Types | Enabled only when lines are selected | Change the line types of the selected lines |
| Add Lines | Always enabled | Add new lines before or after the selected lines or user specified lines |
| Delete Lines | Always enabled | Delete the highlighted lines or user specified lines |
| Show Lines | Always enabled | Show the line files instead of the PDF document |
| Edit Lines | Always enabled | Edit the highlighted lines or user specified lines |
---

## Toolbar API

Since the PDF Viewer in which Tools in the toolbar may not be applicable to 
Callers that pass a `{#snippet toolbar()}` block continue to work without modification; the buttons simply now appear in the page bar instead of a dedicated row.

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


## Toolbar Slot — `page-bar-tool`

### In `shared-pdf-viewer.svelte`

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

### In `pdf-view-window.svelte`

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

## Layout — `doc-page-bar` Flex Row

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

## CSS — Pill Theming

The pill uses four CSS custom properties injected via inline `style` from `PdfViewWindow`'s `darkMode`-derived values:

| Variable | Dark value | Light value | Applied to |
|----------|-----------|-------------|------------|
| `--pvw-surf` | `rgba(15,23,42,0.55)` | `rgba(255,255,255,0.72)` | pill background |
| `--pvw-bdc` | `rgba(148,163,184,0.18)` | `rgba(100,116,139,0.18)` | pill border |
| `--pvw-tc` | `#94a3b8` | `#64748b` | button icon colour |
| `--pvw-hvr` | `rgba(99,102,241,0.14)` | `rgba(99,102,241,0.10)` | button hover background |

Consumer views define `.pvw-tool-btn` and `.pvw-tool-sep` in their own `<style>` blocks. Because the toolbar snippet is defined in the consumer's component scope, Svelte's scoped CSS hashes carry through correctly when the snippet is rendered inside the pill.

---

