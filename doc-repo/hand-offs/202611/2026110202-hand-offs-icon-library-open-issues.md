# Handoff: icon library — three open issues

**Date:** 2026-11-02  
**Status:** The icon library is built, live-tested and committed. Issues 1 and 2 were closed on 2026-11-02 by ChenWeb OpenSpec change `wpi-value-editor-elements` (see the notes under each). Issue 3 remains open.  
**Scope:** `shared/` (Go `iconlib`, Svelte `Icon` / `IconSearchPicker`), ChenWeb wiring. Current description: devdoc `KnowledgeStore/doc-repo/devdocs/202611/2026110201-devdoc-icon-library.md`. Contract: `shared/openspec/specs/icon-library`, `icon-search`, `icon-picker`. Catalogue entries: modules `20261102-09` (backend) and `20261102-10` (frontend).

## State at hand-off

- Table `shared.icon_library` holds 6,525 icons (2,292 Lucide, 4,233 Tabler outline), all with Chinese and English tags, category and description, and a 1024-dimension embedding. It exists in the dev database `miner`; **it has not been applied to production** (the migration is `ChenWeb/shared_migrations/20261103000001_create_shared_icon_library.sql`, and prod would also need `icon-seed` and `icon-enrich` run, or a dump of the table).
- Endpoints: `GET /shared_api/v1/icons/search`, `GET /shared_api/v1/icons/by-name/:name/svg`, `POST /shared_api/v1/icons/library` (login required).
- ChenWeb registers its search embedder at start-up (`kbhandler.RegisterIconSearchEmbedder`, called in `server/cmd/deepdoc/main.go`). The running server must be restarted to pick this up.
- Commits: shared `wuom` (code), `urqt` (archive and specs); ChenWeb `mpns`; KnowledgeStore `yuop`. The OpenSpec change is archived as `2026-11-02-shared-icon-library`.
- Not yet verified: the picker in a browser, and fused (BM25 + vector) results through the running server. Live Go tests cover BM25 and SVG fetch only.

## Issue 1 — Connect the page-designer `icon-picker` to the new picker

**Closed 2026-11-02.** The `icon-picker` editor ID now draws `IconSearchPicker`, adapted in
`ChenWeb/web/src/lib/components/shared-ui/value-editors/IconPickerEditor.svelte`, and shows the
stored name with `Icon`. This applies in the Properties panel and in the new `icon-picker`
element class. The `'icon-picker': 'value-picker'` alias is gone; `editor-ids.ts` now decides
which editor draws each ID. A browser check picked an icon after typing `reload` and found its
name in the input doc. That check used keyword search only: `reload` ranked first and
`refresh-cw` was not tested. The text element's own `icon` attribute still uses its fixed
list, which `TextElement` draws and `text_attributes.go` checks. Moving it to the library is a
separate follow-up.

**Problem.** In ChenWeb the WPI attribute type `icon-picker` is only an alias of `value-picker` (`ChenWeb/web/src/lib/wpi/properties/class-definition.ts`, the `aliases` table). Users still choose from a hand-written list; nothing in the UI uses the library.

**Why it is not done.** Value editors are owned by the pending OpenSpec change `ChenWeb/openspec/changes/wpi-value-editor-elements` (proposal awaiting review, not implemented). Wiring it separately would conflict with that restructuring.

**To do.**
1. Decide with the user whether to wait for that change or add an `icon-search` editor now.
2. Render `IconSearchPicker` (import from `@chendingplano/shared`) as the `icon-picker` editor; store the icon **name** as the value.
3. Render the stored value with `Icon`, so saved pages show the picked icon.
4. Remove the `'icon-picker': 'value-picker'` alias and any hand-written icon lists once the editor works.

**Done when.** Picking an icon by typing "刷新" or "reload" in the page designer saves `refresh-cw`, and reopening the page shows the icon.

## Issue 2 — Paraglide keys for the picker's text

**Closed 2026-11-02.** `icon_search_placeholder`, `icon_search_empty` and `icon_search_error`
are in both ChenWeb message files, and the adapter passes `locale={getLocale()}`.
`bun run check` passes, and the picker rendered in ChenWeb's shell.

**Problem.** The shared Svelte library has no translations, so `IconSearchPicker` takes `labels` (`placeholder`, `empty`, `error`) and `locale` from the host app. The usage example in the frontend module doc calls `m.icon_search_placeholder()`, `m.icon_search_empty()` and `m.icon_search_error()`. **These keys do not exist** in `ChenWeb/web/messages/en.json` or `zh-cn.json`.

**To do.** When Issue 1 first uses the picker:
1. Add the three keys to both message files in the same change, with real Chinese text (for example 按关键词或描述搜索图标 / 未找到图标 / 图标搜索失败).
2. Pass `locale={getLocale()}` so tooltips use the Chinese or English description.
3. Run `bun run check` in `ChenWeb/web` (it fails if the files differ or if new hard-coded text appears).
4. If the shared library should ever carry its own default Chinese text, that is a separate decision; today its defaults are English only.

**Also check.** `IconSearchPicker` and `Icon` pass `bun run check` in `shared/svelte`, but have not been rendered in ChenWeb's shell. `dashboard.svelte` sets `select-none` on its main area; a view hosting the picker must set `select-text` at its root (the picker's own root already does).

## Issue 3 — Decide what happens to the old upload-based icon manager

**Problem.** `shared/` now has two icon stores. The older one is a file-upload manager: Go `shared/go/api/icons`, `sysdatastores/table-icons.go`, handlers `HandleListIcons` and friends under `/shared_api/v1/icons` (list, `:id`, categories, upload, delete, `file/...`), and Svelte `IconPicker`, `IconGrid`, `IconManager`, `iconStore`. It stores files on disk, accepts bitmaps, searches only by name and tags, and its table is configured as `resources`. That table does **not exist** in the dev database, and a search of ChenWeb and tax found no caller.

**Options.**
- **Retire it** (recommended if nobody objects): remove the routes, service, table creation and Svelte components; keep nothing but the new library. Check tax and any deployed instance first; confirm the production database has no `resources` rows before removing the table creation.
- **Keep it for bitmaps only**, and document that it is not for UI icons. Cost: two stores and a confusing name collision on `/icons`.
- **Fold its uploads into the library** by converting SVG uploads to custom library icons. Cost: effort for a feature with no users.

**Needs a user decision before any work.** Removal touches shared APIs used by every project (see the workspace rules on backward compatibility); do it as its own commit, separate from application changes, and run `go work sync` and a build of ChenWeb and tax.

## Smaller notes (not issues)

- Upgrading Lucide or Tabler: re-run `icon-seed` (updates SVG, tags and category, bumps `version`), then `icon-enrich` to fill the text and embeddings of any new icons. Existing icons keep their old translations.
- `icon-enrich` is resumable and was run with `deepseek-flash-processor` and `bge-m3-llama-cpp` from `ChenWeb/.models.toml`. The local embedding server must be up (`127.0.0.1:18083`).
- Custom icons added through the API get no translations or embeddings until `icon-enrich` runs; until then they are found by BM25 on what the uploader supplied.
- The shared working copy still contains another session's uncommitted alert-log work; do not sweep it into an icon commit.
