# Page Interpreter — running a page descriptor

**Date:** 2026-10-29, rewritten 2026-10-30 \
**Status:** implemented in ChenWeb: pages own their panes, panels hold elements, every instance and layouter copy holds a copy of its class, and pages opened in panes are kept by the Panel Cache (OpenSpec change `wpi-pages-own-panes`). `page_policy` and `page_style` are accepted but not yet acted on. \
**Scope:** How a stored page becomes an open, editable page: its descriptor, its panes and panels, its input doc, saving and the Panel Cache. \
**Code roots:** `ChenWeb/web/src/lib/wpi/`, `ChenWeb/server/api/wpi/`

## 1. Summary

The Page Interpreter displays a page from its stored description. That description says how
the page divides its space into panes, which elements each pane shows and how they are
arranged, and where the page's data comes from. The interpreter supplies the running copy:
it loads the data, follows edits, saves when asked, and asks before unsaved work is lost. The
same page can be opened several times with different data, without writing another page
component.

A WPI app opens its initial page in its page area. A page can open other pages in its panes,
and those pages can open pages in theirs. Pages have no classes and are reused by copying
their descriptors under new IDs. Page descriptions are stored in `kb.frontend_pages`; apps
and element, action and layouter classes are stored in `kb.wpi_descriptors`. A page's element
and action instances remain inside its description, each with a copy of its class.

The interpreter supports page sizes and placement, pane trees with sizes, margins, alignment,
scroll bars and drag-resizing, background and foreground colors, data binding and the Flow
Layouter. `page_policy` and `page_style` are reserved for later phases: they are accepted and
ignored.

## 2. Design and behavioral contracts

The overall design is [Web Page Interpreter](../devdocs/202610/2026102601-devdoc-web-page-interpreter.md),
especially [Pages](../devdocs/202610/2026102601-devdoc-web-page-interpreter.md#pages),
[Panes](../devdocs/202610/2026102601-devdoc-web-page-interpreter.md#panes),
[Panels](../devdocs/202610/2026102601-devdoc-web-page-interpreter.md#panels),
[Opening a page](../devdocs/202610/2026102601-devdoc-web-page-interpreter.md#opening-a-page),
[Panel Cache](../devdocs/202610/2026102601-devdoc-web-page-interpreter.md#panel-cache),
[Input doc lifecycle](../devdocs/202610/2026102601-devdoc-web-page-interpreter.md#input-doc-lifecycle) and
[Storage](../devdocs/202610/2026102601-devdoc-web-page-interpreter.md#storage). This document describes the code present on
the date above.

The OpenSpec specifications are the behavioral contracts. If behavior changes, update the
applicable specification as well as this document:

- [Pages](../../../ChenWeb/openspec/specs/wpi-pages/spec.md): page identity, storage, attributes, access, static input, discovery and the editor.
- Panes (`wpi-panes`, in the [wpi-pages-own-panes change](../../../ChenWeb/openspec/changes/wpi-pages-own-panes/specs/wpi-panes/spec.md) until it is archived): page layouters, panes, panels, opening a page in a pane, the pane lookup and the Panel Cache.
- [Page rendering](../../../ChenWeb/openspec/specs/wpi-page-rendering/spec.md): the page box, Flow layout, bindings, dirty tracking and save feedback.
- [App shell](../../../ChenWeb/openspec/specs/wpi-app-shell/spec.md): opening an app, menus, refresh and leaving with unsaved changes.
- [Descriptor store](../../../ChenWeb/openspec/specs/wpi-descriptor-store/spec.md): descriptor writes, class copies and bundle loading.
- [Stored sources](../../../ChenWeb/openspec/specs/wpi-stored-sources/spec.md) and [data actions](../../../ChenWeb/openspec/specs/wpi-data-actions/spec.md): server-side data access.

The [wpi-pages-own-panes change](../../../ChenWeb/openspec/changes/wpi-pages-own-panes/design.md)
records the design decisions of this implementation; the archived
[wpi-pages](../../../ChenWeb/openspec/changes/archive/2026-10-27-wpi-pages/design.md) and
[class/instance](../../../ChenWeb/openspec/changes/archive/2026-10-27-wpi-classes-and-instances/design.md)
changes those before it.

## 3. What changed on 2026-10-30

| Topic | Before | Now |
|-------|--------|-----|
| App | `layout_template` and `panes` that name pages | `initial_page` only; the app has no panes and no menu |
| Where a page is drawn | in a pane of the app | in a page area: the app's own, or a pane of another page in which `open-page` opened it |
| Panes | from the app's layout template | from the page's `page_layouter`, a copy of a page layouter class, with exactly one root pane |
| Elements | the page's `elements` | `panels.<pane_id>.elem_list` |
| Element layouter | the page's `layouter` and `layouter_config` | the panel's `elem_layouter`, a copy of an element layouter class, with its own `config` |
| Instances | named their class; unset attributes came from the stored class when the page was loaded | hold a whole copy of their class in `class`; unset attributes come from the copy |
| Margins | on the page, default `30px` | on leaf panes, default `0px`, counted when deciding whether to scroll |
| `open-page` | `pane` named a pane of the app | `pane` is looked up outward through the pages the page is opened in; the target pane takes the place of the opened page's root pane |
| Running copy | a panel, closed when replaced unless a menu item was bound to it | a page instance; a pane that switches pages hides the one it showed; menus have no bindings |
| Bundle | app, pages, element and action classes | app and pages |

Migration `20261030000001_wpi_pages_own_panes.sql` converted every stored page and app.

## 4. A descriptor the interpreter accepts

This is a complete read-only page, written without class copies; storing it adds them.

```json
{
  "descriptor_id": "page-interpreter-about",
  "schema_version": "0.5",
  "page_name": { "en": "About", "zh-cn": "关于" },
  "description": "A static page displayed by the Page Interpreter",
  "max_width": "640px",
  "binding_mode": "read-only",
  "input": { "title": "Page Interpreter" },
  "page_layouter": { "layouter": "single-pane", "root": { "pane_id": "main", "left_margin": "30px", "top_margin": "30px" } },
  "panels": {
    "main": {
      "elem_layouter": { "layouter": "flow-layouter" },
      "elem_list": [ { "element": "text", "data_binding": "$input_doc.title", "width": "100%" } ]
    }
  }
}
```

### 4.1 Page attributes

There are no page classes, but the attributes below are the ones every page has. The
authoritative checks are in `validator.page()` in
[`validate.go`](../../../ChenWeb/server/api/wpi/validate.go), with the browser shape in
[`types.ts`](../../../ChenWeb/web/src/lib/wpi/types.ts). `descriptor_id`, `schema_version`
(`"0.5"`) and `page_layouter` are required. A page's status is the `status` column of
`kb.frontend_pages` (§8), not a body attribute; the former `page_alignment`, `layouter`,
`layouter_config`, `elements`, the margins and any other unlisted attribute fail validation.

| Attribute | Data type | Default | Explanation | Validation |
|-----------|-----------|---------|-------------|------------|
| `descriptor_id` | string | none | Identifies a page | Unique together with the version; max length 128 |
| `schema_version` | string | none | Descriptor format version (not the page's revision) | `"0.5"` |
| `page_layouter` | object | none | The page's copy of a page layouter class: `layouter`, `class`, optional own `root` | §4.2 |
| `panels` | object | `{}` | Panels keyed by leaf pane ID | §4.2 |
| `page_name` | string or language map | null | Page name; when absent the UI shows `descriptor_id` | Multilingual; max length 100 |
| `description` | string or language map | null | Page description | Multilingual; max length 1000 |
| `access_controls` | array of roles | null | Roles permitted to access the page; null or empty means public | Non-empty strings |
| `keywords` | array of strings | null | For search; normally derived from the meaning of the page | Max items 200 |
| `page_tags` | array of strings | null | For search; normally used to categorize pages | Max items 200 |
| `page_policy` | string | null | Names the page policy; accepted, ignored for now | None |
| `page_style` | string | null | Names the page style; accepted, ignored for now | None |
| `input` | JSON | null | The page's input | See below and §7 |
| `binding_mode` | string | class copy's default | Page-level default binding mode of its elements | Precedence in §7 |
| `save_action` | action | null | Run by `save-page` and by the close prompt | A `save` instance |
| `refresh` | JSON | null | Refresh behavior, e.g. `{ "on_show": true }` | `on_show` boolean |
| `width`, `height` | string | `auto` | Page size inside its page area | Length (below), or `auto` |
| `min_width`, `min_height` | string | `50px` | Minimum size | Length |
| `max_width`, `max_height` | string | null | Maximum size | Length |
| `hori_align` | `left`, `center`, `right` | `center` | Horizontal placement in the app's page area | Listed value |
| `vert_align` | `top`, `center`, `bottom` | `top` | Vertical placement in the app's page area | Listed value |
| `hori_scrollbar`, `vert_scrollbar` | `auto`, `hide` | `auto` | Scrolling in the app's page area when the page is bigger | Listed value |
| `bkgd_color`, `frgd_color` | color | `auto` | Background and foreground color | `auto` or a CSS color |

**Length.** A non-negative number, optionally followed by a unit `px`, `rem`, `em` or `%`.
Spaces may separate the number and the unit; a value without a unit is in `px`; decimals are
allowed. `auto` is accepted for `width` and `height` only, and `elastic` is not accepted for
pages (it is for panes and elements). A `%` value must be within 0 to 100.

**Size and placement.** Without a width the page is as wide as its page area. Without a
height it fills its page area when its root pane is split into columns, or into rows with an
elastic row; otherwise it is as tall as its content. In the app's page area the page's
`hori_align`, `vert_align` and scroll bars place it. Opened in a pane of another page, that
pane's margins, alignment and scroll bars do so instead; the page's sizes and colors still
apply, measured inside the pane.

**Colors.** `auto` inherits the application theme's background and foreground, so the page
follows light and dark mode. An explicit color is fixed and does not follow the mode; set
`bkgd_color` and `frgd_color` together so the text stays readable. A color is a CSS color:
`#rgb`, `#rrggbb` (with optional alpha), `rgb()`/`rgba()`/`hsl()`/`hsla()` or a named color.

**Access.** `access_controls` uses the same role rule as stored statements: absent or empty
means public (every logged-in user), and an admin holds the role `admin`. A page the user may
not use is left out of the app bundle, and reading it or running an action written in it is
refused with 403.

**`input`.** Not every page needs an input; lists, for instance, retrieve their own data. It is
one of:

1. *Static data*: any JSON object without an `action` key, copied into the page instance so
   edits do not change the descriptor.
2. *An action instance* that retrieves the data when the page opens:

| `action` | Meaning | Attributes |
|----------|---------|------------|
| `load` | Reads rows from one table, a record or a list; `where`, `order_by` and `limit` narrow it | `table`, `result` (`record` or `list`), `fields`; optional `where`, `order_by`, `limit` |
| `query` | Runs a stored SQL statement from `kb.stored_stmts`; authors never write SQL in a page | `sql_stmt_id`, `result`; optional `params` |
| `load-file` | Reads a stored JSON file from `kb.stored_files` | `file_id` |

`page_name` and `description` are searchable author metadata, not rendered headings.

### 4.2 Panes and panels

`page_layouter` is `{"layouter": <class ID>, "class": <class row>, "root"?: <pane tree>}`; the
page's own `root` replaces the copy's whole. The tree has one root pane; a pane with `split`
(`rows` or `columns`) has two or more `children`, and a pane without is a leaf. Pane
attributes, their defaults and the classes `single-pane` and `top-left-middle-right-bottom`
are in [Page Layouter](interpreter-layouter-page.md).

`panels` maps leaf pane IDs to `{"elem_layouter": <copy>, "elem_list": [<element instances>]}`.
The element layouter copy is `{"layouter": "flow-layouter", "class": <class row>,
"config"?: <parameters>}`; the panel's own `config` replaces the copy's whole. Flow's
parameters are in [Flow Layouter](interpreter-layouter-flow.md). A panel's size comes from its
content; elastic and percentage element widths make it as wide as its pane's content area.

## 5. Example: Customers

The page `demo-customers` shows a title followed by customer records from
`kb.wpi_demo_customers`. The `text` and `list` elements each occupy the full row, so the Flow
Layouter places the list below the title. Class copies are left out.

```json
{
  "descriptor_id": "demo-customers",
  "schema_version": "0.5",
  "page_name": { "en": "Customers", "zh-cn": "客户" },
  "description": "Lists demo customers with their phone numbers and email addresses",
  "refresh": { "on_show": true },
  "page_layouter": { "layouter": "single-pane", "root": { "pane_id": "main", "hori_align": "left",
    "left_margin": "30px", "right_margin": "30px", "top_margin": "30px", "bottom_margin": "30px" } },
  "panels": {
    "main": {
      "elem_layouter": { "layouter": "flow-layouter" },
      "elem_list": [
        { "element": "text", "text": "Demo - Customers", "width": "100%" },
        {
          "element": "list",
          "width": "100%",
          "source": {
            "action": "load",
            "table": "kb.wpi_demo_customers",
            "result": "list",
            "fields": [
              { "column": "user_name", "attribute": "user_name" },
              { "column": "phone_number", "attribute": "phone_number" },
              { "column": "email", "attribute": "email" }
            ],
            "order_by": [ { "column": "user_name", "direction": "asc" } ],
            "limit": 200
          },
          "presentation": "rows",
          "columns": [
            { "field": "user_name", "label": "User name", "width": "elastic" },
            { "field": "phone_number", "label": "Phone number", "width": "160px" },
            { "field": "email", "label": "Email", "width": "elastic" }
          ]
        }
      ]
    }
  }
}
```

The app `customers-demo` opens it as its initial page. The list loads its own records when
first drawn and reloads when its page instance is shown again, because `refresh.on_show` is
enabled. Store a page through `PUT /api/v1/wpi/descriptors/page/<id>`; the response returns it
with its class copies.

## 6. From stored description to running page

1. A user opens `/wpi/<app-id>`. `GET /api/v1/wpi/apps/<app-id>` calls `BuildBundle()`, which
   loads the app, its `initial_page` and the pages reached through `open-page` instances. Page
   traversal handles cycles by trying each ID once. The bundle contains descriptors, with
   their class copies, not the pages' loaded records.
2. The server checks each page completely against its class copies (structure, pane trees,
   panels, instances), the code modules the copies name, the pane every `open-page` names
   (looked up outward through every chain of pages a page can be opened in, from the initial
   page), data tables and columns, and stored sources. Invalid bundles return 422 with
   descriptor IDs and paths; warnings accompany a valid bundle.
3. `WpiApp.svelte` creates `AppRuntime`, places it in Svelte context and opens the initial
   page in the app's page area (`start()`). A page instance has its own ID, input doc, clean
   snapshot, loading/error state, field errors and show counter.
4. `PageView.svelte` draws a page instance: in the app's page area a frame with the page's
   alignment and scroll bars around the page box, and the root pane inside; in a host pane
   only the page box, whose content is the root's children or the root's panel.
   `PaneView.svelte`, the `page-layouter` code, draws split panes as flex rows or columns and
   leaf panes with their margins, alignment and scroll bars, showing the pane's own panel or
   the page instance the Panel Cache shows there; hidden ones stay mounted with CSS.
5. `PanelView.svelte` chooses the element layouter its copy names. `FlowLayouter.svelte`
   resolves each element against its class copy and passes the result to `Element.svelte`,
   which selects the copy's `code_module_id` in the element registry. Layout owns the
   element's size; the element module draws it and uses the runtime for bindings and
   triggers.

## 7. Input, edits, saving and the Panel Cache

An omitted `input` or `{}` starts an empty input doc. Any other object without `action` is
static data, copied into the page instance so edits do not mutate the descriptor. An action
input uses `load`, `query` or `load-file` to retrieve data. An explicit `open-page.input`,
including `{}`, overrides the page's default input.

Elements read and write `$input_doc.<path>` through `AppRuntime.read()` and `write()`;
missing nested attributes are created on write. For a modifiable `binding_mode`, precedence
is instance, then page, then the instance's class copy. A value fixed by the copy takes
precedence over these; validation rejects an instance that sets it. The server and browser
apply the same merge rules.

Dirty tracking compares a canonical, key-order-independent representation of the input doc
with the last loaded or saved snapshot. Reverting an edit makes the page instance clean.
`save-page` and the close prompt both use the page's `save_action`. Successful saves write
the returned record key into the doc and replace the clean snapshot; field validation errors
remain beside their bound fields and clear when those fields are edited.

`open-page` resolves its `pane` outward from the page instance that holds the element: that
page's leaf panes, then those of the page it was opened in, and so on; a page opened in a pane
has that pane in place of its root, so its root's ID names it. The pane hides the page
instance it shows and shows the cached instance of the same page with the same resolved input,
or creates one. Hiding never prompts. `close-page` closes the page instances opened in the
page's panes first, then the page, each after the unsaved-changes check (save, discard or keep
editing; a failed save keeps the page open); the pane then shows its own panel. `close-page`
in the page of the app's page area does nothing. The browser leave warning checks hidden page
instances too. A menu item is shown as current while its pane shows its page with its input.

On a hidden-to-shown transition, `refresh.on_show` reloads an action-backed page input only if
its doc is clean. Static inputs are never reloaded. Lists query their own sources and observe
the show counter separately; their records are not the page's input doc.

Server actions use `POST /api/v1/wpi/actions/run` with a stored location, for example
`{"kind":"page","id":"customers","pointer":"/panels/main/elem_list/1/source"}`, plus
arguments and, for a save, the input doc. The server resolves that location in the latest
active stored page and checks and merges the action against the class copy it holds. The
browser does not supply SQL, table definitions or executable descriptor bodies to this
endpoint. Actions require login; stored statements/files additionally enforce their role
controls. Handlers log operations through `CreateDefaultLogger("20261026-418")`.

## 8. Storage and authoring

| Data | Storage and identity |
| --- | --- |
| Current page descriptor, with class copies | `kb.frontend_pages`, body in `body` JSONB; earlier versions and recovery copies are in `archive.frontend_pages`. |
| App, element class, action class, page layouter class, element layouter class | `kb.wpi_descriptors`, unique `(kind, descriptor_id, version)`. |
| Element/action instances, layouter copies | Inline in their page; no independent rows. |
| Module catalogue, named SQL, named JSON file | `kb.code_modules`, `kb.stored_stmts`, `kb.stored_files`, respectively. |
| Running page instance and its edited doc | Browser state; saving the doc changes application records, not its page descriptor. |

Page rows also carry `schema_version`, `status` (the page's status: `active`, `draft` or
`retired`), `created_by`, `updated_by`, `created_at` and `updated_at`. Reads choose the
highest active version. A higher draft or retired version does not supersede an older active
version.

Logged-in authors search with `GET /api/v1/wpi/pages?q=<text>&limit=<n>` and read with
`GET /api/v1/wpi/pages/<id>`. An admin saves the descriptor body with
`PUT /api/v1/wpi/descriptors/page/<id>`: instances and layouter copies without a `class` get a
copy of the active class, the page is checked completely, and a new active version is stored;
the response returns the stored page. To copy a page, change its body ID and PUT it under the
new ID; its copies come along. The WPI editor loads pages with their panes, edits pane trees
and panels, and adopts the stored page after saving.

### Page versions

A new page starts at version 1. When an existing page is modified and saved, copy its current
record to `archive.frontend_pages`, then update the current record with the new page and
increase its version by one. The archive copy and current-record update must succeed or fail
together. The archive preserves the previous version for later reference.

Saves of the same page are serialized; concurrent ordinary saves use last-save-wins. Existing
historical rows in `kb.frontend_pages` are left in place; reads continue to select the highest
active version. New saves archive and update the highest-version row.

### Auto Saving

In the WPI Editor, each dirty page is automatically saved every N seconds since its last save
or auto-save; N defaults to 10. An auto-save stores a recovery copy of the editor's page
descriptor in `archive.frontend_pages` and does not make it the saved page version or mark
the page clean. A successful ordinary save removes the author's auto-save record in the same
transaction. The interval can be changed per browser with the `wpi.autoSaveSeconds` local
storage setting; non-positive or invalid values use the 10-second default.

When the editor loads a page that has an auto-save record, it loads that recovery copy and
marks the page dirty. This is separate from saving a running page's input doc (§7). Recovery
records belong to the author. Unnamed pages use temporary IDs and reopen as dirty tabs when
the editor starts. The first interval starts when a tab opens. An auto-save against an obsolete
page version is rejected; a recovery copy already stored before another author saves remains
available to its owner. A version check and per-page lock prevent an in-flight auto-save from
recreating stale recovery after an ordinary save.

An already open app retains its downloaded bundle. Opening another page uses that bundle; it
does not fetch a fresh page descriptor. In contrast, server actions resolve the latest active
page on each request. Descriptor versions are not pinned across a running session, so
changing action locations while an app is open can affect its next action request.

## 9. Where to change the implementation

| Responsibility | Files relative to `ChenWeb/` |
| --- | --- |
| Page storage, discovery, writes, recovery, class copies | `server/api/wpi/store.go`, `handler.go`, `recovery.go`, `copies.go` |
| Bundle traversal, pane lookup and validation | `server/api/wpi/bundle.go`, `validate.go`, `types.go` |
| Server-side action resolution | `server/api/wpi/actions.go` |
| Runtime data, page instances, Panel Cache | `web/src/lib/wpi/runtime.svelte.ts`, `panel-cache.ts`, `dirty.ts`, `refs.ts` |
| Page, panes and panels | `web/src/lib/wpi/PageView.svelte`, `PaneView.svelte`, `PanelView.svelte`, `layout.ts` |
| Copy resolution and element dispatch | `web/src/lib/wpi/entries.ts`, `elements/Element.svelte`, `elements/index.ts` |
| Element layouters and Flow | `web/src/lib/wpi/layouters/index.ts`, `layouters/FlowLayouter.svelte` |
| Editor: pages, panes, preview | `web/src/lib/components/shared-ui/wpi-editor.svelte`, `canvas/wpi-json.ts`, `canvas/pane-edit.ts`, `canvas/PagePreview.svelte`, `canvas/PageConfigPanel.svelte` |

A new page or pane attribute needs its specification, Go validation, TypeScript shape and
consuming runtime/rendering code changed together, and a migration when stored pages must
change. Merely adding attributes to a descriptor cannot activate behavior.

Backend checks live in `validate_test.go`, `bundle_test.go`, `flow_test.go`, `handler_test.go`,
`store_test.go`, `actions_test.go`, `stored_test.go`, `preview_test.go` and `seed_test.go`;
`recovery_test.go` and `recovery_integration_test.go` cover recovery and page version storage;
`customers_demo_integration_test.go` checks the migrated database with `WPI_TEST_DB=1`.
Browser-side helpers are covered by the tests alongside `entries.ts`, `layout.ts`,
`panel-cache.ts`, `dirty.ts`, `refs.ts`, `canvas/wpi-json.ts` and `canvas/pane-edit.ts`.
Relevant commands are `go test ./server/api/wpi/` from ChenWeb, and `bun test src/lib` and
`bun run check` from ChenWeb/web.

On 2026-10-30, `go test ./server/api/wpi/` passed, the database check passed against the
migrated development database, `bun test src/lib/wpi` and the editor helper tests passed, and
`bun run check` reported no errors. A browser run against the real handlers checked the
`customer-admin` app (menu, pages in `middle` and `right`, switching without prompts, the
close prompt, saves and field errors, static input, stored statements and file, the centred
About page, Chinese text) and the editor (loading a page, splitting a pane, moving an element,
saving with class copies, previewing two panes).

## 10. Known limitations

- Only the Flow element layouter and the `page-layouter` code exist; layouter classes have no
  editor screen. `page_policy` and `page_style` are accepted and ignored.
- `open-page` opens pages in panes only; tabs, new tabs and iframes are planned.
- There is no automatic default-page wrapper for a standalone element, timed refresh,
  age-out (a pane keeps every page opened in it until it is closed) or automatic update of a
  visible list after a save elsewhere.
- A dragged pane size lasts until the app is reloaded.
- Concurrent record edits use last-save-wins. Open apps do not subscribe to descriptor changes.
- Interpreter controls use English/Chinese Paraglide messages; descriptor text is only
  partly localized. Element labels support language maps, but menu labels, column labels,
  option labels and text content do not. Text remains selectable.
