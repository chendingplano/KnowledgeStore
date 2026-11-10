# Module: Document Builder (frontend)

**Module ID:** `20261109-03`
**Type:** frontend · **Language:** svelte · **Version:** 2.1.0
**Status:** active — Resources › Documents (one entry per group), Development › System Admin › Resources › Documents (overview cards) and Development › System Admin › System › Document Groups
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
- **Overview** (`DocGroupsCardsView`): one card per group with its page status, counts, roles and
  members; **Sync** (rescan, then classify new documents, as `mise build-docs <group>`), **Build
  Page** (enable the group, so it appears at its menu location; disabled while the page exists) and
  **New group** (created without a page; a refused member path removes the new group again).

The Resources nav rail builds its Documents children from the groups the user may see.

## 2. Files

| File | Purpose |
|---|---|
| `ChenWeb/web/src/lib/components/shared-ui/document-builder/document-builder-view.svelte` | The reader |
| `ChenWeb/web/src/lib/components/shared-ui/document-builder/document-builder-types.ts` | Tree types, URL builders, `firstLeaf`, `findLeaf`, `stripFrontMatter` |
| `ChenWeb/web/src/lib/components/shared-ui/document-builder/document-builder-types.test.ts` | Tests for the helpers |
| `ChenWeb/web/src/lib/components/home3/doc-groups-admin-view.svelte` | The admin screen |
| `ChenWeb/web/src/lib/components/home3/doc-groups-cards-view.svelte` | The overview cards |
| `ChenWeb/web/src/lib/components/home3/doc-groups-client.ts` | Typed admin API calls; `syncGroup`, `hasPage`, `buildPage`, `createGroup`, `nextPosition`, `groupLabel`, `parseRoles` |
| `ChenWeb/web/src/lib/components/home3/doc-groups-client.test.ts` | Tests for the client (fetch stubbed) |

Wiring (not part of the module): `home3/nav-rail.svelte` (menu from `/doc-groups/menu`,
`docgroup-<key>` ids, the System Admin entries `sysadmin-doc-groups` and, on the development page
only, `sysadmin-resources-documents`) and `home3/content-panel.svelte` (renders the three views).

## 3. Interface

`DocumentBuilderView` props: `group: string` (group key), `darkMode?: boolean`,
`leftWidthDefault?: number`. `DocGroupsAdminView` and `DocGroupsCardsView` props: `darkMode?: boolean`.
Text is in `messages/*.json` under `docbuilder_*`, `docgroups_*`, `nav_sysadmin_doc_groups` and
`nav_sysadmin_resources_documents`.

A group's *page* is its entry at its menu location. It exists exactly while the group is enabled
(`hasPage`), so Build Page is a save with `enabled: true`; there is no separate page record. Sync
returns `{ classified: null }` when the server has no classification model (HTTP 503 from
`classify`); the rescan has still happened.

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

A new menu entry needs no code: create a group on the overview (or the admin screen), press Build
Page, and it appears under its parent menu on the next page load.

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
- The overview was checked in a browser against a stubbed admin API (Sync, Build Page, refused member); the
  reader and admin screen still await the live check in the OpenSpec tasks.
- The overview creates groups under `documents` only; other parents and member edits are on the admin screen.
- The old `home3/user-manual-viewer.svelte` is unused and can be deleted.
