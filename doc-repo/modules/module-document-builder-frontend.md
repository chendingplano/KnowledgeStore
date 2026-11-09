# Module: Document Builder (frontend)

**Module ID:** `20261109-03`
**Type:** frontend · **Language:** svelte · **Version:** 1.0.0
**Status:** active — new; not yet mounted on a page
**Project:** ChenWeb (web front end)
**Location:** `ChenWeb/web/src/lib/components/shared-ui/document-builder`
**Created:** 2026-11-09
**Devdocs:** None
**Pairs with:** [Document Builder (backend)](module-document-builder-backend.md) `20261109-02`

## 1. What it is

A two-pane document viewer. The left pane is a menu tree (categories that open to show their
documents); the right pane shows the selected document. Markdown is rendered by the
[Markdown Viewer](module-markdown-viewer.md) (`20261109-01`); a PDF is shown by the browser's own
PDF viewer in an iframe. The pane divider can be dragged.

It shows whatever the backend source returns; it does not decide categories.

## 2. Files

| File | Purpose |
|---|---|
| `ChenWeb/web/src/lib/components/shared-ui/document-builder/document-builder-view.svelte` | The component |
| `ChenWeb/web/src/lib/components/shared-ui/document-builder/document-builder-types.ts` | Tree types, URL builders, `firstLeaf`, `findLeaf` |
| `ChenWeb/web/src/lib/components/shared-ui/document-builder/document-builder-types.test.ts` | Tests for the helpers |

## 3. Interface

Props: `source: string` (the backend source key), `darkMode?: boolean`, `leftWidthDefault?: number`.
It calls `GET /api/v1/docbuilder/:source/tree` and `.../file?path=`. User text is in
`messages/*.json` under `docbuilder_*`.

## 4. Configuration

| Key | Default | Meaning |
|---|---|---|
| `source` | required | Backend source key, e.g. `user-manuals` |
| `darkMode` | `true` | Dark or light colours (same palette as the user manual viewer) |
| `leftWidthDefault` | `260` | Starting width of the tree pane in px (180–480 when dragged) |

## 5. Usage

```svelte
<script lang="ts">
  import DocumentBuilderView from '$lib/components/shared-ui/document-builder/document-builder-view.svelte';
</script>

<DocumentBuilderView source="user-manuals" {darkMode} />
```

The page (for example Resources › User Manuals) only needs a source defined in
`ChenWeb/docbuilder.local.toml` and classified once.

## 6. Behaviour and conventions

- Per browser session and per source, it remembers the open document, which categories are
  expanded, the pane width and each document's scroll position, and restores them on return
  (`sessionStorage`, guarded; the page works without it).
- Text is selectable (`select-text` on the root); only the divider is `select-none`.
- All interface text goes through Paraglide (English and Chinese).
- A banner line shows how many documents are not categorised yet.

## 7. Scope and limits

- Not browser-verified yet: it is covered by the type check and helper tests, but has not been
  mounted on a page and clicked through.
- The existing `home3/user-manual-viewer.svelte` (hard-coded tree) is not replaced.
- No search inside the tree; no deep links to a document.
