# Module: Web Page Interpreter (frontend)

**Module ID:** `20261026-01`
**Type:** frontend · **Language:** svelte · **Version:** 2.2.0
**Status:** under-dev — pilot, with element and action classes (descriptor format `0.2`) and
page sizes, alignment, page-wide binding mode and static input (2026-10-27); used by the
`customer-admin` demo app
**Project:** ChenWeb (web front end)
**Location:** `ChenWeb/web/src/lib/wpi`
**Created:** 2026-10-26

## 1. What it is

The browser half of the Web Page Interpreter (WPI). Given an app's descriptors (JSON
documents that describe its panes, pages, fields, lists, menus and actions), it draws the
app and makes it work: it lays out the elements, shows and edits data, keeps pages that
are switched away from, asks before unsaved changes are lost, and calls the backend to load
and save records. A new screen therefore needs new descriptors, not new Svelte code.

Each element and action on a page is an *instance* of a *class* such as `input`, `list` or
`open-page`. The class ID is the name the code that implements it is registered under, so
the interpreter draws an instance with its class's component and merges in the class's
defaults. Pages have no classes. A page places itself in its pane (width, maximum width,
alignment), may make all its fields read-only at once (`binding_mode`), and may carry its
own data as its input instead of loading it.

It is not a general page builder or a form library to embed in hand-written pages: it runs
whole WPI apps, opened at `/wpi/<app-id>`. The design is devdoc
`KnowledgeStore/doc-repo/devdocs/202610/2026102601-devdoc-web-page-interpreter.md`; what the
pilot built is devdoc `2026102603-devdoc-wpi-pilot.md`. The server half is module
`20261026-02` (Web Page Interpreter backend).

## 2. Files

| File | Purpose |
|---|---|
| `ChenWeb/web/src/lib/wpi/types.ts` | Descriptor, class, instance, bundle and action-reference types (schema_version `0.2`) |
| `ChenWeb/web/src/lib/wpi/api.ts` | Client for the app bundle and action endpoints, and for listing and creating element classes (used by the WPI editor); `WpiError` |
| `ChenWeb/web/src/lib/wpi/api.test.ts` | Tests for `api.ts` |
| `ChenWeb/web/src/lib/wpi/refs.ts` | `$input_doc` / `$record` / `$args` references; safe path get/set |
| `ChenWeb/web/src/lib/wpi/refs.test.ts` | Tests for `refs.ts` |
| `ChenWeb/web/src/lib/wpi/dirty.ts` | Key-order-independent snapshots for unsaved-change tracking |
| `ChenWeb/web/src/lib/wpi/dirty.test.ts` | Tests for `dirty.ts` |
| `ChenWeb/web/src/lib/wpi/panels.ts` | Pane/panel bookkeeping: menu bindings, panel sharing, hide-or-close decision |
| `ChenWeb/web/src/lib/wpi/panels.test.ts` | Tests for `panels.ts` |
| `ChenWeb/web/src/lib/wpi/layout.ts` | Size attributes (fixed / elastic / auto) to CSS for elements and panes; a page's box in its pane (`pageStyle`) |
| `ChenWeb/web/src/lib/wpi/layout.test.ts` | Tests for `layout.ts` |
| `ChenWeb/web/src/lib/wpi/entries.ts` | Merges instances with their page's `binding_mode` and their class rows (`mergeInstance`, `resolveEntry`); names action instances by page and pointer (`actionRef`); text by language (`textIn`); static data versus action instances as input (`isAction`, `staticInput`) |
| `ChenWeb/web/src/lib/wpi/entries.test.ts` | Tests for `entries.ts` |
| `ChenWeb/web/src/lib/wpi/runtime.svelte.ts` | `AppRuntime`: panes, panels, input docs (static or loaded), saves, action instances by class, the unsaved-changes prompt |
| `ChenWeb/web/src/lib/wpi/text.ts` | Translated messages for save error codes; `localized` text from descriptors |
| `ChenWeb/web/src/lib/wpi/WpiApp.svelte` | Root component: creates the runtime, picks the layout template, leave warning |
| `ChenWeb/web/src/lib/wpi/Pane.svelte` | One pane: geometry, its panels (hidden ones stay mounted), drag-resize handle |
| `ChenWeb/web/src/lib/wpi/Panel.svelte` | One open page: its box in the pane, loading/error state and its layouter |
| `ChenWeb/web/src/lib/wpi/ErrorBox.svelte` | Visible error for anything that cannot be drawn or run |
| `ChenWeb/web/src/lib/wpi/UnsavedDialog.svelte` | Save / discard / keep editing prompt (native `<dialog>`) |
| `ChenWeb/web/src/lib/wpi/templates/index.ts` | Layout template registry |
| `ChenWeb/web/src/lib/wpi/templates/SinglePane.svelte` | `single-pane` template (pane `main`) |
| `ChenWeb/web/src/lib/wpi/templates/TopLeftMiddleRightBottom.svelte` | `top-left-middle-right-bottom` template |
| `ChenWeb/web/src/lib/wpi/layouters/index.ts` | Layouter registry |
| `ChenWeb/web/src/lib/wpi/layouters/FlowLayouter.svelte` | `flow-layouter`: wrapping left-to-right flow |
| `ChenWeb/web/src/lib/wpi/elements/index.ts` | Element class registry `elementClasses`, keyed by class ID |
| `ChenWeb/web/src/lib/wpi/elements/Element.svelte` | Draws one element instance with its class's component, or an error box |
| `ChenWeb/web/src/lib/wpi/elements/TextElement.svelte` | `text`: static text or a bound value |
| `ChenWeb/web/src/lib/wpi/elements/InputElement.svelte` | `input`: text, number or email field with field errors |
| `ChenWeb/web/src/lib/wpi/elements/SelectElement.svelte` | `select`: pulldown with options from the instance |
| `ChenWeb/web/src/lib/wpi/elements/ButtonElement.svelte` | `button`: runs its `on_click` trigger |
| `ChenWeb/web/src/lib/wpi/elements/ListElement.svelte` | `list`: queries its records, rows, row click, re-query on show |
| `ChenWeb/web/src/lib/wpi/elements/MenuElement.svelte` | `menu`: tree with folders, menu-item bindings, `initial_item` |
| `ChenWeb/web/src/routes/wpi/[appId]/+page.ts` | Route load (`ssr = false`) |
| `ChenWeb/web/src/routes/wpi/[appId]/+page.svelte` | Route page: fetches the bundle, shows validation errors or the app |

## 3. Interface

- **Route:** `/wpi/<app-id>` (login required by the server). The URL holds only the app ID.
- **Component:** `WpiApp.svelte` with prop `bundle: Bundle` (from `fetchApp(appId)`).
- **Registries** — the extension points; each name must also be accepted by the backend
  validator (`server/api/wpi/types.go`, `validate.go`):
  - `templates: Record<string, Component>` in `templates/index.ts`;
  - `layouters: Record<string, Component<LayouterProps>>` with
    `LayouterProps = { panelId: string; page: PageDescriptor }`;
  - `elementClasses: Record<string, Component<ElementProps>>`, keyed by element class ID,
    with `ElementProps = { panelId: string; element: ResolvedElement }`. Action classes are
    dispatched by class ID in `runtime.svelte.ts` (`runTrigger`).
- **Runtime** (`getRuntime()` inside the app): `openPage`, `closePanel`, `save`,
  `runTrigger`, `queryList`, `read` / `write` / `errorsFor` for bindings, `isDirty`,
  `anyDirty`, `isShowing`.
- **API client:** `fetchApp(appId)`, `runAction(ref, args, inputDoc?)` with
  `ref = {kind: 'page', id, pointer}`; both throw `WpiError` (`status`, `issues`,
  `fieldErrors`).

## 4. Configuration

None.

## 5. Usage

Adding an element class, for example a checkbox:

```ts
// elements/CheckboxElement.svelte receives { panelId, element } and uses
// rt.read(panelId, element.desc.data_binding) / rt.write(...), like InputElement.
// elements/index.ts:
import CheckboxElement from './CheckboxElement.svelte';
export const elementClasses = { /* … */ checkbox: CheckboxElement };
// server/api/wpi/validate.go: add "checkbox" to elementAttrs with its attributes,
// then store the class row "checkbox" with a default or null per instance attribute.
```

Opening an app: write its descriptors with `PUT /api/v1/wpi/descriptors/<kind>/<id>`
(module `20261026-02`), then open `/wpi/<app-id>`.

## 6. Behaviour and conventions

- The route's root sets `select-text`; only the pane resize handle is `select-none`.
- All of the interpreter's own text goes through Paraglide (`wpi_*` keys in English and
  Chinese). A `label` (and a class's `description`) may hold one text per language and is
  shown in the current locale, falling back to `en`; other text inside descriptors is shown
  as written.
- Colours come from theme tokens, so WPI pages follow light and dark mode.
- Nothing fails silently: unknown templates, layouters, element types, failed loads and
  failed saves show an `ErrorBox`; save rule failures show translated messages next to the
  bound field.
- A hidden panel stays mounted (hidden with CSS), keeping its input doc and unsaved
  changes. Leaving the page while any panel is dirty triggers the browser's warning.
- A page's or `open-page`'s `input` without an `action` attribute is static data: the panel
  starts with a copy of it (`$state.snapshot`, since the bundle is held in `$state`) and
  never reloads it. Inputs with an action (`load`, `query`, `load-file`) run on the server.

## 7. Scope and limits

- Small vocabulary: two templates, one layouter, six element classes, action classes
  `load`, `save`, `query`, `load-file`, `open-page`, `close-page`, `save-page`. No page
  state, conditions, timed refresh or panel age-out; lists are read-only.
- The interpreter does not show `page_name` or a page's `description`; they are for authors
  searching pages (backend `GET /api/v1/wpi/pages`).
- Only labels can be given per language; menu items, list columns, select options and text
  elements are shown as written, so WPI apps are not linked from ChenWeb menus.
- Only fixed-pixel panes can be resized.
- Move to `shared/svelte` when a second project uses it.
