# CDM Editor: Workspace App Tile and Main Page

**Date:** 2026-07-27 \
**Status:** Implemented \
**Component:** SemOS workspace app tiles (ChenWeb `config/site/*.toml`,
`config/workspace-content/`, `project_migrations/`), CDM Editor UI
(ChenWeb `web/src/routes/home3/cdm`, `web/src/lib/components/cdm`) \
**Authors**: Claude \
**Tags**: SemOS, CDM, editor, workspace, frontend, Svelte, page-config, i18n

## Change Logs
* 2026/07/27, document created, recording the addition of the "CDM Editor /
  智能编辑器" workspace app tile and the rebuild of the CDM Editor main page it
  points at.

## Purpose

The CDM Editor MVP (impl `2026072701`, ADR `2026072603`) shipped a working
authoring loop but left it unreachable from the product: nothing on
`/semos/workspace` linked to it, so the only way in was to type `/home3/cdm`
by hand. This change adds the seventh workspace app tile and makes the page it
lands on an actual destination.

It closes two distinct gaps:

1. **Discovery.** `/semos/workspace` lists six app tiles from
   `[[workspace.apps]]` in the active site config. The CDM Editor was not one
   of them.
2. **Destination.** `/home3/cdm` existed, but as route wiring rather than a
   page — `impl 2026072701` describes task group 8 as "routes and
   integration", and what it shipped was a bare `<h1>CDM Documents</h1>`, an
   unstyled `<ul>` of knowledge stores, a create input, and a plain `<table>`.
   No theme awareness, no filtering, no designed empty or error states. The
   project owner assessed it as "basically useless … a temporary bridging
   page", which matches what it was built as.

## Summary

- A seventh workspace app tile, `key = "cdm_editor"`, renders as **CDM
  Editor** in English and **智能编辑器** in Chinese, and links to `/home3/cdm`.
- `/home3/cdm` is rebuilt as the CDM Editor main page: a masthead stating what
  the editor is for, an explicit knowledge-store gate, a create-document row,
  and a document list with status tabs (All / Drafts / Published), a title
  filter, status badges, and designed loading/empty/error states — all
  theme-aware in light and dark.
- `/home3/cdm/[key]` gets matching chrome (a back link to the main page, the
  document key, the same theme tokens) so the two halves of the editor no
  longer look like different products.
- **No API, store, or AST change.** The same three endpoints the bridging page
  called are the only ones this page calls. This is a presentation and
  navigation change on top of the MVP's existing capability.

## Main Code Changes

### 1. The workspace app tile

The tile is declared in all three site configs (`config/site/site-default.toml`,
`site-default-zh-cn.toml`, `tenant-demo.toml`):

```toml
[[workspace.apps]]
key = "cdm_editor"
name = "CDM Editor"
description = "Author documents as meaning, rendered by Typst templates."
href = "/home3/cdm"
icon = "pen-line"
```

Localization follows the established two-layer model (ADR 2026071701 /
2026071602), not a third mechanism: site config carries the base English
content, and the per-language override lives in `kb.page_config`, keyed by the
tile's `key`. Migration
`project_migrations/20260727000001_seed_page_config_cdm_editor_app.sql` seeds
one row per language for `('semos-workspace', 'cdm_editor')` — `{}` for `en`
(so English renders the site-config default) and the translation for `zh-cn`.
The same strings were added to
`config/workspace-content/labels-zh-cn.toml`, which
`sitehandler`'s workspace-content endpoint still serves, keeping the two
sources consistent.

**One non-obvious constraint the migration has to satisfy.** `isAuthorized`
(`server/api/pageconfighandler/access.go`) fails closed: a `kb.page_config` row
whose `access_role` is null or empty is *suspended*, and `resolveEntries`
reports a suspended entry in the response's `hidden` list — which the workspace
page uses to hide a tile. Seeding the two rows without `access_role` would
therefore have made the new tile invisible to every user, with no error
anywhere. The migration grants the same `[system].access_roles` set
20260720000002's closing `UPDATE` gave the existing six tiles. Access is
evaluated on the **default-language** row (`[languages].default = "zh-cn"`), so
both rows carry it.

### 2. The CDM Editor main page

File: `web/src/lib/components/cdm/DocumentListView.svelte` (rebuilt);
`web/src/routes/home3/cdm/+page.svelte`.

The three API calls and the `knowledgeStoreState` scoping are unchanged from
the bridging page — `listKnowledgeStores`, `listDocuments`, `createDocument`,
with `tenant_id`/`ks_store_id` still sourced from home3's existing
active-knowledge-store singleton rather than a new selection mechanism. What
changed is everything around them:

- **A masthead** stating the editor's premise (meaning, not appearance;
  authored documents feed the same pipeline as uploaded ones), so the page
  explains itself to someone arriving from a workspace tile that says only
  "CDM Editor".
- **An explicit store gate.** Nothing on this page is addressable without a
  knowledge store, so when none is active the page renders a titled panel
  offering the choice, with each store's description, rather than a bare list.
- **Status tabs and a title filter**, with counts. Filtering is client-side
  over the page `ListDocuments` already returned: the endpoint has no title or
  status parameter, and adding one is API work this page does not need in order
  to be usable.
- **Designed states** for loading, load failure (with retry), an empty store,
  and a filter that matches nothing — four distinct outcomes the bridging page
  rendered as one-line text or not at all.
- **Theme awareness.** The palette is the "archival reading room" token set
  `inputs-mgmt-view.svelte` established for home3's document surfaces, derived
  from `theme.isDark` exactly as its siblings do.

### 3. Editor route chrome

File: `web/src/routes/home3/cdm/[key]/+page.svelte`.

A breadcrumb bar with a back link to the main page and the document key
(which `DocumentEditor`'s own header does not show — it shows the editable
title and version badge), plus the same theme tokens.

`DocumentEditor.svelte` itself is **not modified**. It reads exactly two CSS
custom properties, `--cdm-surface` and `--cdm-muted`, which nothing had ever
defined; both route wrappers now set them per theme. The remaining native form
controls inside it (the title input, the action buttons) style only their
borders, so the wrapper sets `color-scheme` alongside — one declaration that
makes the browser render them dark on the dark page, instead of restyling a
component this change has no reason to touch.

## Verification

- **`bun run check`** — no new errors or warnings in any changed file. (The
  suite reports one pre-existing unrelated error in
  `home3/doc-processor-dashboard-state.test.ts`.)
- **`bun test src/lib/components/cdm/`** — 83 tests across 10 files pass,
  unchanged.
- **`go build ./server/...`** and **`go test ./server/api/sitehandler/...`** —
  pass. `sitehandler_test.go`'s `len(Workspace.Apps) != 6` assertion reads its
  own `testdata/site-valid.toml` fixture, not the real configs, so it is
  unaffected by the seventh tile.
- **All five TOML files parse** and yield 7 apps with the expected keys.
- **The migration was applied against the running dev database** and the two
  rows verified present with `enabled`, `accessible`, and the full
  `access_role` set. (`goose` is not installed locally; the server's own
  migrator will record the version on its next start. The migration is
  idempotent — `ON CONFLICT DO NOTHING` plus an `access_role IS NULL`-guarded
  `UPDATE` — so re-running it is safe.)
- **Live browser (Playwright)**, against the running Vite dev server with the
  CDM and kb APIs mocked at the network layer:
  - `/semos/workspace` renders 7 tiles; the 7th is `CDM Editor` →
    `/home3/cdm` for `en` and `智能编辑器` → `/home3/cdm` for `zh-cn`, with the
    seeded description in each. Clicking it lands on the new main page.
  - `/home3/cdm` in **both themes**: store gate → pick a store → 3 documents,
    tab counts `All=3 / Drafts=2 / Published=1`, status filter narrows to 1 and
    2 respectively, title filter narrows to 1, a non-matching filter shows the
    designed empty state, and the store chip names the active store.
  - Navigating into a document loads the editor with its title, back link, and
    key; the back link returns to `/home3/cdm`.
  - The only network failure in either run is `401 /auth/me`, the app-wide
    session check — expected with no Kratos session, and unrelated to these
    pages.

**Environment constraint, unchanged from impl 2026072701:** this environment
has no way to establish a real Kratos session, so `/api/v1/site-config` and
`/api/v1/page-config/*` return 401 to an unauthenticated client and the browser
runs above mock them. The page-config payloads used were built from the rows
the migration actually seeded, which were read back from the live database.

## What Was Not Changed

1. **Paraglide i18n for editor strings.** The tile's label is localized,
   because app tiles already have a localization mechanism. The editor's own
   strings remain hard-coded English, matching every sibling `home3` feature —
   the decision recorded in ADR 2026072603's 2026/07/27 entry and spec
   `2026072502` §5 is unchanged by this work.
2. **The knowledge-store selection does not survive a page reload.**
   `knowledgeStoreState` is an in-memory singleton with no persistence, so a
   hard reload returns the page to its store gate. This is pre-existing shared
   behavior — `kb-import-view.svelte` and `document-review-view.svelte` use the
   same singleton — and changing it would change all three.
3. **Server-side title/status filtering.** `ListDocuments` gained no
   parameters; filtering is client-side over the returned page. This is
   adequate at current document counts and becomes wrong at pagination scale.
4. **`DocumentEditor.svelte`'s internals.** Themed only through the two CSS
   variables it already read, plus `color-scheme`. Its banner colors remain
   hard-coded.
5. **Everything spec `2026072502` §5 lists as unbuilt** — versioning (§2.5),
   delete (§2.6), templates (§2.8), semantic annotation (§3.2). This change
   adds no capability; it makes the existing capability reachable and
   presentable.

## Known Issue Found, Not Fixed

`config/site/tenant-demo.toml` declares its six original app tiles with **no
`key` field at all**. `key` is the join key for page-config overrides and
visibility, and `/semos/workspace` renders the grid with `{#each visibleApps as
app, i (app.key)}` — so for that tenant all six keys are the empty string,
which is both a duplicate-key hazard in a keyed `each` and a guarantee that no
label override or visibility rule can ever apply to them. The tile added by
this change carries a proper `key`; the six pre-existing ones were left alone,
since fixing them is a separate change with its own verification. Reported to
the project owner.

## References
- [2026072701-impl-cdm-editor-mvp.md](2026072701-impl-cdm-editor-mvp.md)
- [2026072502-spec-cdm-editor.md](../../specs/202607/2026072502-spec-cdm-editor.md)
- [2026072603-adr-cdm-editor-frontend.md](../../adrs/202607/2026072603-adr-cdm-editor-frontend.md) — DR7 (`/home3/cdm` routes)
- [2026071601-adr-configurable-knowledge-menus.md](../../adrs/202607/2026071601-adr-configurable-knowledge-menus.md)
- [2026071602-adr-knowledge-menu-labels-i18n.md](../../adrs/202607/2026071602-adr-knowledge-menu-labels-i18n.md)
- `ChenWeb/config/site/site-default.toml`, `site-default-zh-cn.toml`, `tenant-demo.toml`
- `ChenWeb/config/workspace-content/labels-zh-cn.toml`
- `ChenWeb/project_migrations/20260727000001_seed_page_config_cdm_editor_app.sql`
- `ChenWeb/web/src/routes/home3/cdm/`
- `ChenWeb/web/src/lib/components/cdm/DocumentListView.svelte`
