# Page Interpreter — running a page descriptor inside a pane

**Date:** 2026-10-28 \
**Status:** implemented in ChenWeb; the additional page appearance fields proposed in the guiding design are not implemented. \
**Scope:** How a stored page becomes an open, editable page, and how this relates to the revised descriptor shape and storage rules. \
**Code roots:** `ChenWeb/web/src/lib/wpi/`, `ChenWeb/server/api/wpi/`

## Summary

The Page Interpreter displays a page from its stored description. That description says
which elements to show, how to arrange them, and where the page's data comes from. The
interpreter supplies the running copy: it loads the data, follows edits, saves when asked,
and asks before unsaved work is lost. The same page can be opened several times with
different data, without writing another page component.

A page always runs inside a pane of a WPI app. Pages have no classes and are reused by
copying their descriptors under new IDs. Page descriptions are stored in
`kb.frontend_pages`; app descriptions and element and action classes are stored in
`kb.wpi_descriptors`. A page's element and action instances remain inside its description.

The current interpreter supports page sizes, horizontal placement, data binding and the
Flow Layouter. Page styles, independent page scrollbars and page background colours in the
revised design need further implementation; storing those attributes today fails validation.

## Design and behavioral contracts

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

## Review of the revised guide

The §6 clarification is consistent with `store.go` and migration
`20261027000003_create_kb_frontend_pages.sql`: that migration moves every page version to
`kb.frontend_pages` and removes `page` from the permitted kinds in `kb.wpi_descriptors`.
“Other descriptors” means app descriptors and element/action class descriptors; code-module
catalogue rows, stored statements and stored files each have their own tables.

The new §4.2 shape introduces fields beyond the current page format:

| Revised field | Current implementation |
| --- | --- |
| `descriptor_id`, `schema_version`, `layouter`, `elements` | Supported and required. Page format is `0.2`. |
| `width`, `height` | Supported, with `min_width` and `max_width` also available. |
| `page_style` | Unsupported. No page-style resolver exists. |
| `hori_align` | Unsupported. `page_alignment` places the page box left, centre or right in its pane. Flow's `horizontal_alignment` instead places elements within rows. |
| `vert_align` | Unsupported. Flow's `vertical_alignment` aligns elements within a row, and `rows_alignment` places rows in a definite page height; neither places the page box vertically in its pane. |
| `hori_scrollbar`, `vert_scrollbar` | Unsupported. The pane's `scroll` sets both axes together: `auto` by default, or `none`. |
| `background_color` | Unsupported. Appearance currently follows the application's theme. |

The §4.2 block is an outline rather than valid JSON: several values have no opening quote,
and `<an element>` and `...` are placeholders. It also omits supported data/lifecycle fields
listed in §3.2.1 and `layouter_config` from §3.7. Until those differences are resolved, use
the example below for the running interpreter. The new names are not aliases for existing
fields and are rejected as unknown page attributes.

Two nearby guide sections also need reconciliation: §3.5.3 ends with an unfinished “The”,
and §3.5.2's “Default Page” association has no corresponding runtime behavior. Neither is
an implemented page facility.

## A descriptor the current interpreter accepts

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
  "page_alignment": "center",
  "binding_mode": "read-only",
  "input": { "title": "Page Interpreter" },
  "elements": [
    { "element": "text", "data_binding": "$input_doc.title", "width": "100%" }
  ]
}
```

Optional page fields are `page_name`, `description`, `input`, `save_action`, `refresh`,
`page_alignment`, `width`, `height`, `min_width`, `max_width`, `binding_mode` and
`layouter_config`. The authoritative checks are in `validator.page()` in
[`validate.go`](../../../ChenWeb/server/api/wpi/validate.go), with the browser shape in
[`types.ts`](../../../ChenWeb/web/src/lib/wpi/types.ts).

Page sizes accept `auto` or non-negative lengths in `px`, `rem`, `em` or `%`; they do not
accept `elastic`, although element and pane widths can. With no width, the page fills its
available pane content area; with no height, its height follows its content.
`page_alignment` defaults to left and becomes visible when width or maximum width leaves
space. `page_name` and `description` are searchable author metadata, not rendered headings.
They accept a string or language-keyed strings including `en`.

`layouter_config` controls Flow's gaps, alignment within rows and placement of rows. Its
contract is in the page-rendering specification; implementation is `flowStyle()` and
`FlowLayouter.svelte`. These settings arrange the elements inside the page box.

## From stored description to running page

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

## Input, edits, saving and panel lifetime

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

## Storage and authoring

| Data | Storage and identity |
| --- | --- |
| Complete page descriptor | `kb.frontend_pages`, unique `(descriptor_id, version)`, body in `body` JSONB. |
| App, element class, action class | `kb.wpi_descriptors`, unique `(kind, descriptor_id, version)`. |
| Element/action instances | Inline in their page; no independent rows. |
| Module catalogue, named SQL, named JSON file | `kb.code_modules`, `kb.stored_stmts`, `kb.stored_files`, respectively. |
| Running panel and its edited doc | Browser state; saving the doc changes application records, not its page descriptor. |

Page rows also carry `schema_version`, `status`, `created_by`, `updated_by`, `created_at`
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

## Where to change the implementation

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

For this documentation review, `go test ./server/api/wpi/` passed (cached), and
`bun test src/lib/wpi` passed all 39 tests. The document's relative links and JSON example
were checked locally. No new live-backend or browser verification was performed.

## Known limitations and documentation impact

- Only Flow layout is implemented. Page styles, page-box vertical alignment, independent
  page scrollbar controls and background overrides remain proposed.
- There is no automatic default-page wrapper for a standalone element, timed refresh,
  panel age-out or automatic update of a visible list after a save elsewhere.
- Concurrent record edits use last-save-wins. Open apps do not subscribe to descriptor changes.
- Interpreter controls use English/Chinese Paraglide messages; descriptor text is only
  partly localized. Element labels support language maps, but menu labels, column labels,
  option labels and text content do not. Text remains selectable.

This document adds an implementation reference and records the review findings. The guiding
design is left unchanged; its new §4.2 fields and unfinished page-style/default-page text
still need specification and implementation work. No code, database schema, existing
specification or module catalogue entry changes with this documentation task. Individual
element attribute contracts and the full Flow configuration remain in their existing
documents/specifications rather than being repeated here.
