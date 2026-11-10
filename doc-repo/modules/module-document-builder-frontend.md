# Module: Document Builder (frontend)

**Module ID:** `20261109-03`
**Type:** frontend · **Language:** svelte · **Version:** 2.0.0
**Status:** active — Resources › Documents (one entry per group) and Development › System Admin › Document Groups
**Project:** ChenWeb (web front end)
**Location:** `ChenWeb/web/src/lib/components/shared-ui/document-builder`
**Created:** 2026-11-09
**Devdocs:** [2026111001-devdoc-document-groups](../devdocs/202611/2026111001-devdoc-document-groups.md)
**Pairs with:** [Document Builder (backend)](module-document-builder-backend.md) `20261109-02`

## 1. What it is

The reader and the administrator's screen for document groups.

- **Reader** (`DocumentBuilderView`): a category tree on the left and the selected document on the
  right. Markdown goes through the [Markdown Viewer](module-markdown-viewer.md) (`20261109-01`);
  a PDF opens in the browser's own viewer; Markdown has an **Export as PDF** link.
- **Admin** (`DocGroupsAdminView`): create groups, set labels, parent menu, position and roles,
  add or remove members, remove or delete documents, rescan, classify.

The Resources nav rail builds its Documents children from the groups the user may see.

## 2. Files

| File | Purpose |
|---|---|
| `ChenWeb/web/src/lib/components/shared-ui/document-builder/document-builder-view.svelte` | The reader |
| `ChenWeb/web/src/lib/components/shared-ui/document-builder/document-builder-types.ts` | Tree types, URL builders, `firstLeaf`, `findLeaf`, `stripFrontMatter` |
| `ChenWeb/web/src/lib/components/shared-ui/document-builder/document-builder-types.test.ts` | Tests for the helpers |
| `ChenWeb/web/src/lib/components/home3/doc-groups-admin-view.svelte` | The admin screen |
| `ChenWeb/web/src/lib/components/home3/doc-groups-client.ts` | Typed admin API calls, `parseRoles` |
| `ChenWeb/web/src/lib/components/home3/doc-groups-client.test.ts` | Test for `parseRoles` |

Wiring (not part of the module): `home3/nav-rail.svelte` (menu from `/doc-groups/menu`,
`docgroup-<key>` ids, System Admin entry) and `home3/content-panel.svelte` (renders both views).

## 3. Interface

`DocumentBuilderView` props: `group: string` (group key), `darkMode?: boolean`,
`leftWidthDefault?: number`. `DocGroupsAdminView` props: `darkMode?: boolean`.
Text is in `messages/*.json` under `docbuilder_*`, `docgroups_*` and `nav_sysadmin_doc_groups`.

## 4. Configuration

| Key | Default | Meaning |
|---|---|---|
| `group` | required | Group key, e.g. `user-manuals` |
| `darkMode` | `true` | Dark or light colours |
| `leftWidthDefault` | `260` | Starting width of the tree pane in px (180–480 when dragged) |

## 5. Usage

```svelte
<DocumentBuilderView group="user-manuals" {darkMode} />
```

A new menu entry needs no code: create a group on the admin screen and it appears under its parent
menu on the next page load.

## 6. Behaviour and conventions

- Per browser session and per group it restores the open document, expanded categories, pane width
  and scroll positions (`sessionStorage`, guarded).
- Every entry has an icon: a folder per category (open when expanded), a text-file icon per Markdown
  document, a file icon per PDF. Leading YAML front matter is removed before rendering.
- Text is selectable; all interface text goes through Paraglide (English and Chinese).
- The tree shows only the latest version of each document (decided by the server).

## 7. Scope and limits

- Not yet in the UI: comments, tickets, to-dos, upload, per-document category editing.
- Admin roles are entered as comma-separated text; the server keeps only valid roles.
- Browser-checked only as far as the type check and helper tests; see the OpenSpec tasks for the live check.
- The old `home3/user-manual-viewer.svelte` is unused and can be deleted.
