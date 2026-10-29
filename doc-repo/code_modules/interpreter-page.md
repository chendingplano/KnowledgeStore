# Page Interpreter — running a page descriptor inside a pane

**Date:** 2026-10-29 \
**Status:** implemented in ChenWeb, including the page appearance attributes (margins, alignment, scrolling, colors). `page_policy` and `page_style` are accepted but not yet acted on. \
**Scope:** How a stored page becomes an open, editable page, and how this relates to the revised descriptor shape and storage rules. \
**Code roots:** `ChenWeb/web/src/lib/wpi/`, `ChenWeb/server/api/wpi/`

## 1. Summary

The Page Interpreter displays a page from its stored description. That description says
which elements to show, how to arrange them, and where the page's data comes from. The
interpreter supplies the running copy: it loads the data, follows edits, saves when asked,
and asks before unsaved work is lost. The same page can be opened several times with
different data, without writing another page component.

A page always runs inside a pane of a WPI app. Pages have no classes and are reused by
copying their descriptors under new IDs. Page descriptions are stored in
`kb.frontend_pages`; app descriptions and element and action classes are stored in
`kb.wpi_descriptors`. A page's element and action instances remain inside its description.

The interpreter supports page sizes, margins, horizontal and vertical placement, scrolling
under a maximum size, background and foreground colors, data binding and the Flow Layouter.
`page_policy` and `page_style` are reserved for later phases: they are accepted and ignored.

## 2. Design and behavioral contracts

The overall design is [Web Page Interpreter](../devdocs/202610/2026102601-devdoc-web-page-interpreter.md),
especially §3.2, §3.3, §3.8–§3.9, §4.2 and §6. This document describes the code present on
the date above, including where the revised design goes beyond it.

The OpenSpec specifications are the behavioral contracts. If behavior changes, update the
applicable specification as well as this document:

- [Pages](../../../ChenWeb/openspec/specs/wpi-pages/spec.md): page identity, storage, attributes, static input and discovery.
- [Page rendering](../../../ChenWeb/openspec/specs/wpi-page-rendering/spec.md): layout, bindings, dirty tracking and save feedback.
- [App shell](../../../ChenWeb/openspec/specs/wpi-app-shell/spec.md): panes, panels, sharing and refresh.
- [Descriptor store](../../../ChenWeb/openspec/specs/wpi-descriptor-store/spec.md): descriptor writes and bundle loading.
- [Stored sources](../../../ChenWeb/openspec/specs/wpi-stored-sources/spec.md) and [data actions](../../../ChenWeb/openspec/specs/wpi-data-actions/spec.md): server-side data access.

The archived `wpi-pages` change records the implementation's
[proposal](../../../ChenWeb/openspec/changes/archive/2026-10-27-wpi-pages/proposal.md),
[design](../../../ChenWeb/openspec/changes/archive/2026-10-27-wpi-pages/design.md) and
[completed tasks](../../../ChenWeb/openspec/changes/archive/2026-10-27-wpi-pages/tasks.md).
The archived [class/instance change](../../../ChenWeb/openspec/changes/archive/2026-10-27-wpi-classes-and-instances/design.md)
explains the class merge. The current [code-module change](../../../ChenWeb/openspec/changes/wpi-code-modules/design.md)
adds module selection and attributes fixed by an element class.

## 4. A descriptor the current interpreter accepts

This is a complete read-only page, assuming the active `text` class is installed. It can
be named by an app pane or an `open-page` action.

```json
{
  "descriptor_id": "page-interpreter-about",
  "schema_version": "0.2",
  "page_name": { "en": "About", "zh-cn": "关于" },
  "description": "A static page displayed by the Page Interpreter",
  "layouter": "flow-layouter",
  "max_width": "640px",
  "hori_align": "center",
  "binding_mode": "read-only",
  "input": { "title": "Page Interpreter" },
  "elements": [
    { "element": "text", "data_binding": "$input_doc.title", "width": "100%" }
  ]
}
```

### 4.1 Page attributes

There are no page classes, but the attributes below are the ones every page has. Each has a
default, and a descriptor may override it. The authoritative checks are in `validator.page()`
in [`validate.go`](../../../ChenWeb/server/api/wpi/validate.go), with the browser shape in
[`types.ts`](../../../ChenWeb/web/src/lib/wpi/types.ts). `descriptor_id`, `schema_version`
and `elements` are required; `layouter` is required and normally `flow-layouter`. A page's
status is the `status` column of `kb.frontend_pages` (§8), not a body attribute; the former
`page_alignment` and any other unlisted attribute fail validation.

| Attribute | Data type | Default | Explanation | Validation |
|-----------|-----------|---------|-------------|------------|
| `descriptor_id` | string | none | Identifies a page | Unique together with the version; max length 100 |
| `schema_version` | string | none | Descriptor format version (not the page's revision) | Not null |
| `page_name` | string or language map | null | Page name; when absent the UI shows `descriptor_id` | Multilingual; max length 100 |
| `description` | string or language map | null | Page description | Multilingual; max length 1000 |
| `access_controls` | array of roles | null | Roles permitted to access the page; null or empty means public | Non-empty strings |
| `keywords` | array of strings | null | For search; normally derived from the meaning of the page | Max items 200 |
| `page_tags` | array of strings | null | For search; normally used to categorize pages | Max items 200 |
| `page_policy` | string | null | Names the page policy; accepted, ignored for now | None |
| `page_style` | string | null | Names the page style; accepted, ignored for now | None |
| `input` | JSON | null | The page's input | See below and §7 |
| `layouter` | string | none | The layouter that arranges the elements | A registered layouter |
| `layouter_config` | JSON | null | Layouter settings (Flow: gaps, alignment within rows, row placement) | See below |
| `binding_mode` | string | class default | Page-level default binding mode of its elements | Precedence in §7 |
| `save_action` | action | null | Run by `save-page` and by the close prompt | An action allowed here |
| `refresh` | JSON | null | Refresh behavior, e.g. `{ "on_show": true }` | `on_show` boolean |
| `width`, `height` | string | `auto` | Page size | Length (below), or `auto` |
| `min_width`, `min_height` | string | `50px` | Minimum size | Length |
| `max_width`, `max_height` | string | null | Maximum size | Length |
| `hori_align` | `left`, `center`, `right` | `center` | Horizontal placement | Listed value |
| `vert_align` | `top`, `center`, `bottom` | `top` | Vertical placement | Listed value |
| `left_margin`, `right_margin`, `top_margin`, `bottom_margin` | string | `30px` | Space between the pane edge and the page edge | Length |
| `bkgd_color`, `frgd_color` | color | `auto` | Background and foreground color | `auto` or a CSS color |

**Length.** A non-negative number, optionally followed by a unit `px`, `rem`, `em` or `%`.
Spaces may separate the number and the unit; a value without a unit is in `px`; decimals are
allowed. `auto` is accepted for `width` and `height` only, and `elastic` is not accepted for
pages (it is for panes and elements). A `%` value must be within 0 to 100.

**Size and scrolling.** With no width the page fills the pane's content width inside its
margins; with no height its height follows its content. Percentages refer to the pane
content area *excluding* the margins. When `max_height` is set and the content is taller, the
page shows a vertical scroll bar; likewise `max_width` and a horizontal scroll bar.
`hori_align` and `vert_align` matter only when the page is narrower or shorter than the space
inside the margins (for example because `width` or `max_width` is set).

**Colors.** `auto` inherits the application theme's background and foreground, so the page
follows light and dark mode. An explicit color is fixed and does not follow the mode; set
`bkgd_color` and `frgd_color` together so the text stays readable. A color is a CSS color:
`#rgb`, `#rrggbb` (with optional alpha), `rgb()`/`rgba()`/`hsl()`/`hsla()` or a named color.

**Access.** `access_controls` uses the same role rule as stored statements: absent or empty
means public (every logged-in user), and an admin holds the role `admin`. A page the user may
not use is left out of the app bundle, and reading it or running an action written in it is
refused with 403.

**Policy and style.** `page_policy` will name rules shared by all pages (some overridable by a
page, some not; several policies may exist, with a system default that WPI may mandate for
every page). `page_style` will name shared styles for consistent look and behavior, such as
one scroll bar design, and text that is always selectable unless explicitly prohibited (such as
passwords). Both are reserved for later phases.

**`input`.** Not every page needs an input; lists, for instance, retrieve their own data. It is
one of:

1. *Static data*: any JSON object without an `action` key, copied into the panel so edits do
   not change the descriptor.
2. *An action instance* that retrieves the data when the page opens:

| `action` | Meaning | Attributes |
|----------|---------|------------|
| `load` | Reads rows from one table, a record or a list; `where`, `order_by` and `limit` narrow it | `table`, `result` (`record` or `list`), `fields`; optional `where`, `order_by`, `limit` |
| `query` | Runs a stored SQL statement from `kb.stored_stmts`; authors never write SQL in a page | `sql_stmt_id`, `result`; optional `params` |
| `load-file` | Reads a stored JSON file from `kb.stored_files` | `file_id` |

```json
{ "action": "query", "sql_stmt_id": "customer-by-id", "result": "record", "params": ["$args.customer_id"] }
```

`page_name` and `description` are searchable author metadata, not rendered headings.

### 4.2 Flow configuration

`layouter_config` controls Flow's gaps, alignment within rows and placement of rows. Its
contract is in the page-rendering specification; implementation is `flowStyle()` and
`FlowLayouter.svelte`. These settings arrange the elements inside the page box.

## 5. Example: Customers

This page shows a title followed by customer records from `kb.wpi_demo_customers`.
The `text` and `list` elements each occupy the full row, so the Flow Layouter places
the list below the title. The list retrieves and displays the three customer attributes:
`user_name`, `phone_number` and `email`.

```json
{
  "descriptor_id": "customers",
  "schema_version": "0.2",
  "page_name": { "en": "Customers", "zh-cn": "客户" },
  "description": "Lists demo customers with their phone numbers and email addresses",
  "layouter": "flow-layouter",
  "refresh": { "on_show": true },
  "elements": [
    {
      "element": "text",
      "text": "Demo - Customers",
      "width": "100%"
    },
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
```

The list loads its own records when first drawn and reloads when its hidden panel is
shown again, because `refresh.on_show` is enabled. It displays up to 200 records ordered
by user name. The page does not need an `input`: its title is fixed text, and the list
uses its own `source`. No record ID is needed because this example only displays records.

This requires active `text`, `list` and `load` classes and the demo table. Store the body
through `PUT /api/v1/wpi/descriptors/page/customers`, then reference `customers` from an
app pane or an `open-page` action. Writing it under this ID creates a new version if the
demo's `customers` page already exists. The title and column labels are plain strings,
as required by their current element formats.

## 6. From stored description to running page

1. A user opens `/wpi/<app-id>`. `GET /api/v1/wpi/apps/<app-id>` calls `BuildBundle()`,
   which loads the app, its initial pages, pages reached through `open-page` actions, and
   the element/action classes they use. Page traversal handles cycles by trying each ID
   once. The bundle contains descriptors, not the panels' loaded records.
2. The server checks structure, class instances, referenced pages and panes, data tables
   and columns, stored sources, and element code modules. Invalid bundles return 422
   with descriptor IDs and paths; warnings accompany a valid bundle. A page PUT checks
   structure and instances against active classes, but is not a complete app-bundle check.
3. `WpiApp.svelte` creates `AppRuntime`, places it in Svelte context and opens initial
   pages. `openPage()` chooses the supplied input or the page's default, then creates or
   reuses a panel in the target pane. A panel has its own ID, input doc, clean snapshot,
   loading/error state, field errors and show counter.
4. `Pane.svelte` keeps each panel mounted and hides inactive ones with CSS.
   `Panel.svelte` finds its page in `bundle.pages`, applies `pageStyle()` and chooses the
   registered layouter. It displays loading and action-error feedback. An unknown
   layouter displays a visible error.
5. `FlowLayouter.svelte` resolves each element against its class and passes the resulting
   instance to `Element.svelte`. That component selects the class's `code_module_id` in
   the element registry. Layout owns the element's size; the element module draws it and
   uses the runtime for bindings and triggers.

The Page Interpreter is this cooperation between the server bundle loader, runtime and
rendering components. There is no separately selected page code module and no page-level
`code_module_id` attribute. The catalogue permits module type `page`, but the current
migrations do not register a Page Interpreter row. This document does not create one or
change catalogue document paths.

## 7. Input, edits, saving and panel lifetime

An omitted `input` or `{}` starts an empty input doc. Any other object without `action`
is static data, copied into the panel so edits do not mutate the descriptor. An action
input uses `load`, `query` or `load-file` to retrieve data. Static data cannot use a
top-level `action` key. An explicit `open-page.input`, including `{}`, overrides the
page's default input.

Elements read and write `$input_doc.<path>` through `AppRuntime.read()` and `write()`;
missing nested attributes are created on write. Svelte's reactive state propagates changes.
For a modifiable `binding_mode`, precedence is instance, then page, then class default.
A value fixed by the class takes precedence over these defaults; validation rejects an
instance attempting to override it. The server and browser apply the same merge rules.

Dirty tracking compares a canonical, key-order-independent representation of the input
doc with the last loaded or saved snapshot. Reverting an edit makes the panel clean.
`save-page` and the close prompt both use the page's `save_action`. Successful saves write
the returned record key into the doc and replace the clean snapshot; field validation
errors remain beside their bound fields and clear when those fields are edited.

Menu bindings retain panels when hidden, and menu requests for the same page and resolved
input can share a panel within a pane. Replacing an unbound panel closes it. Closing a dirty
panel offers save, discard or keep editing; failed saves prevent closing. Hiding does not
prompt. The browser leave warning checks hidden panels too.

On a hidden-to-visible transition, `refresh.on_show` reloads an action-backed page input
only if its doc is clean. Static inputs are never reloaded. Lists query their own sources
and observe the show counter separately; their records are not the panel's input doc.

Server actions use `POST /api/v1/wpi/actions/run` with a stored location, for example
`{"kind":"page","id":"customer-form","pointer":"/save_action"}`, plus arguments
and, for a save, the input doc. The server resolves that location in the latest active
stored page and validates the action against its class. The browser does not supply SQL,
table definitions or executable descriptor bodies to this endpoint. Actions require login;
stored statements/files additionally enforce their role controls. Handlers log operations
through `CreateDefaultLogger("20261026-418")`.

## 8. Storage and authoring

| Data | Storage and identity |
| --- | --- |
| Complete page descriptor | `kb.frontend_pages`, unique `(descriptor_id, version)`, body in `body` JSONB. |
| App, element class, action class | `kb.wpi_descriptors`, unique `(kind, descriptor_id, version)`. |
| Element/action instances | Inline in their page; no independent rows. |
| Module catalogue, named SQL, named JSON file | `kb.code_modules`, `kb.stored_stmts`, `kb.stored_files`, respectively. |
| Running panel and its edited doc | Browser state; saving the doc changes application records, not its page descriptor. |

Page rows also carry `schema_version`, `status` (the page's status: `active`, `draft` or `retired`), `created_by`, `updated_by`, `created_at`
and `updated_at`. Reads choose the highest active version. A higher draft or retired
version does not supersede an older active version. The row's integer `version` records
descriptor revisions; `schema_version` identifies the descriptor format.

Logged-in authors search with `GET /api/v1/wpi/pages?q=<text>&limit=<n>` and read with
`GET /api/v1/wpi/pages/<id>`. Search matches IDs, names and descriptions in any language,
ignoring case, and returns summaries ordered by ID (default limit 50, maximum 200). A read
returns `{"version": n, "page": <descriptor>}`. An admin saves the descriptor body with
`PUT /api/v1/wpi/descriptors/page/<id>`, which appends a new active version in
`kb.frontend_pages`. To copy a page, change its body ID and PUT it under the new ID.

An already open app retains its downloaded bundle. Opening another panel uses that bundle;
it does not fetch a fresh page descriptor. In contrast, server actions resolve the latest
active page on each request. Descriptor versions are not pinned across a running session,
so changing action locations while an app is open can affect its next action request.

## 9. Where to change the implementation

| Responsibility | Files relative to `ChenWeb/` |
| --- | --- |
| Page storage, discovery, writes | `server/api/wpi/store.go`, `handler.go` |
| Bundle traversal and validation | `server/api/wpi/bundle.go`, `validate.go`, `types.go` |
| Server-side action resolution | `server/api/wpi/actions.go` |
| Runtime data and panel lifecycle | `web/src/lib/wpi/runtime.svelte.ts`, `panels.ts`, `dirty.ts`, `refs.ts` |
| Page box and rendering | `web/src/lib/wpi/Panel.svelte`, `Pane.svelte`, `layout.ts` |
| Class resolution and element dispatch | `web/src/lib/wpi/entries.ts`, `elements/Element.svelte`, `elements/index.ts` |
| Layout selection and Flow | `web/src/lib/wpi/layouters/index.ts`, `layouters/FlowLayouter.svelte` |

A new page attribute needs its specification, Go validation, TypeScript shape and consuming
runtime/rendering code changed together. A new stored schema needs a goose migration;
adding a supported JSON attribute alone does not require a table column. Adding the proposed
style and scrollbar attributes also requires defining their values and ownership relative
to pane scrolling and Flow alignment. Merely adding attributes to a descriptor cannot
activate those behaviors.

Existing backend checks live in `store_test.go`, `handler_test.go`, `bundle_test.go`,
`validate_test.go`, `flow_test.go`, `actions_test.go`, `stored_test.go` and `seed_test.go`.
Browser-side helpers are covered by the tests alongside `entries.ts`, `layout.ts`,
`panels.ts`, `dirty.ts` and `refs.ts`. Relevant commands are
`go test ./server/api/wpi/` from ChenWeb, and `bun test src/lib/wpi` from ChenWeb/web.
Rendering or interaction changes also need `bun run check` and a browser check; helper
tests alone do not exercise Svelte's full panel lifecycle.

On 2026-10-29, `go test ./server/api/wpi/` and `bun test src/lib/wpi` (48 tests) passed, and
`bun run check` reported no errors. No live-backend or browser verification was performed.

## 10. Known limitations and documentation impact

- Only Flow layout is implemented. `page_policy` and `page_style` are accepted and ignored.
- There is no automatic default-page wrapper for a standalone element, timed refresh,
  panel age-out or automatic update of a visible list after a save elsewhere.
- Concurrent record edits use last-save-wins. Open apps do not subscribe to descriptor changes.
- Interpreter controls use English/Chinese Paraglide messages; descriptor text is only
  partly localized. Element labels support language maps, but menu labels, column labels,
  option labels and text content do not. Text remains selectable.

Changed on 2026-10-29: the page attributes in §4.1, with `page_alignment` renamed `hori_align`
(migration `20261029000001_rename_wpi_page_alignment.sql`) and the specifications
`wpi-pages` (attributes, access, page box). The `wpi-page-rendering` specification is
unchanged, and the guiding design's page-style and default-page text is still open.
No module catalogue entry changes. Individual
element attribute contracts and the full Flow configuration remain in their existing
documents/specifications rather than being repeated here.
