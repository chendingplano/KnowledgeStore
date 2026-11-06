# Module: Web Page Interpreter (frontend)

**Module ID:** `20261026-01`
**Type:** frontend · **Language:** svelte · **Version:** 3.16.0
**Status:** under-dev — pages own their panes and instances hold copies of their classes
(formats `0.5` for apps and pages, 2026-10-30, OpenSpec change `wpi-pages-own-panes`); used
by the `customer-admin` and `customers-demo` apps
**Project:** ChenWeb (web front end)
**Location:** `ChenWeb/web/src/lib/wpi`
**Created:** 2026-10-26

Panes and panels support optional fixed or light/dark background and foreground colors; pane backgrounds take precedence over panel backgrounds. List class version 5 supports single or light/dark background, font, odd-row and even-row colors through the shared color value editor. Button class version 7 supports an optional single or light/dark background through the same editor. Existing page class copies retain their original attributes and appearance.

## 1. What it is

The browser half of the Web Page Interpreter (WPI). Given an app's descriptors (JSON
documents that describe its pages, their panes, fields, lists, menus and actions), it draws the
app and makes it work: it lays out panes and elements, shows and edits data, keeps pages that
are switched away from, asks before unsaved changes are lost, and calls the backend to load
and save records. A new screen therefore needs new descriptors, not new Svelte code.

An app opens its initial page in its page area. A page divides its space into panes with a
copy of a page layouter class (a pane tree with one root pane); each leaf pane holds a panel of
elements arranged by a copy of an element layouter class. A page opened in a pane of another
page puts that pane in place of its own root pane. The Panel Cache keeps the pages opened in
each pane: switching pages hides the one shown, and opening the same page with the same input
shows it again.

Each element and action instance holds a whole copy of its class in `class`; the interpreter
draws an element with the code module its copy names and merges in the copy's defaults, then
the values the copy fixes. The stored class is never read at run time. Pages have no classes.

It is not a general page builder or a form library to embed in hand-written pages: it runs
whole WPI apps, opened at `/wpi/<app-id>`, and draws pages in the WPI editor's preview. The
design is devdoc `KnowledgeStore/doc-repo/devdocs/202610/2026102601-devdoc-web-page-interpreter.md`;
what the pilot built is devdoc `2026102603-devdoc-wpi-pilot.md`. The server half is module
`20261026-02` (Web Page Interpreter backend).

The WPI editor client reads and updates element, action and layouter classes through
`getEntityClass` and `updateEntityClass`. `listActionClasses` includes all active action
classes, independently of click-trigger choices. Optional `attribute_definitions`
metadata is retained in copies and excluded from runtime defaults. Property editors
can use the copy's value-editor choices and configuration through `withClassEditors`;
older copies without metadata retain the module defaults. The Class editor UI is
documented in devdoc 2026102701 §1.3.7.

## 2. Files

| File | Purpose |
|---|---|
| `ChenWeb/web/src/lib/wpi/types.ts` | Descriptor, pane, panel, layouter copy, class, instance, bundle and action-reference types (apps and pages `0.5`; element class rows `0.4`; action class rows `0.2`) |
| `ChenWeb/web/src/lib/wpi/api.ts` | Client for the app bundle and action endpoints, page save (returns the stored page with its class copies), and for listing element classes with their instance attributes, creating them, and reading and updating one class, and listing `kb.code_modules`; used by the WPI editor; `WpiError` |
| `ChenWeb/web/src/lib/wpi/api.test.ts` | Tests for `api.ts` |
| `ChenWeb/web/src/lib/wpi/save-page.test.ts` | Tests for `savePage` |
| `ChenWeb/web/src/lib/wpi/list-request.ts` | List source availability, preview columns and request timeouts for lists |
| `ChenWeb/web/src/lib/wpi/list-request.test.ts` | Tests for `list-request.ts` |
| `ChenWeb/web/src/lib/wpi/refs.ts` | `$input_doc` / `$record` / `$args` references; safe path get/set |
| `ChenWeb/web/src/lib/wpi/refs.test.ts` | Tests for `refs.ts` |
| `ChenWeb/web/src/lib/wpi/dirty.ts` | Key-order-independent snapshots for unsaved-change tracking |
| `ChenWeb/web/src/lib/wpi/dirty.test.ts` | Tests for `dirty.ts` |
| `ChenWeb/web/src/lib/wpi/panel-cache.ts` | The Panel Cache: sharing keys, cached page instances per pane, show (hides the one shown), forget; pane instance IDs |
| `ChenWeb/web/src/lib/wpi/panel-cache.test.ts` | Tests for `panel-cache.ts` |
| `ChenWeb/web/src/lib/wpi/layout.ts` | Pane trees (`effectiveRoot`, `leafPanes`, `findPane`) and their CSS: split panes, pane sizes, a leaf pane's margins, alignment and scroll bars, the page box and its height rule, panel width, flow layouter and element sizes |
| `ChenWeb/web/src/lib/wpi/layout.test.ts` | Tests for `layout.ts` |
| `ChenWeb/web/src/lib/wpi/entries.ts` | Merges instances with their page's `binding_mode` and their class copies (`mergeElement`, fixed values last; `mergeAction`; `resolveEntry`, which adds the copy's code module); names action instances by page and pointer under `/panels/<pane>/elem_list/<i>` (`actionRef`); text by language (`textIn`); static data versus action instances as input (`isAction`, `staticInput`) |
| `ChenWeb/web/src/lib/wpi/entries.test.ts` | Tests for `entries.ts` |
| `ChenWeb/web/src/lib/wpi/runtime.svelte.ts` | `AppRuntime`: page instances, pane instances and the Panel Cache, the outward pane lookup (`resolvePane`), input docs (static or loaded), saves, action instances by class, the unsaved-changes prompt, pane sizes dragged by the user |
| `ChenWeb/web/src/lib/wpi/text.ts` | Translated messages for save error codes; `localized` text from descriptors |
| `ChenWeb/web/src/lib/wpi/WpiApp.svelte` | Root component: creates the runtime, opens the initial page in the app's page area, leave warning |
| `ChenWeb/web/src/lib/wpi/PageView.svelte` | One page instance: in the app's page area its frame and box with its root pane; in a host pane only its box, the host pane taking the root's place |
| `ChenWeb/web/src/lib/wpi/PaneView.svelte` | One pane, the code of the `page-layouter` module: a split pane's row or column of child panes; a leaf pane's own panel or the page instance shown in it (hidden ones stay mounted); drag-resize handle |
| `ChenWeb/web/src/lib/wpi/PanelView.svelte` | One panel, drawn by the element layouter its copy names |
| `ChenWeb/web/src/lib/wpi/ErrorBox.svelte` | Visible error for anything that cannot be drawn or run |
| `ChenWeb/web/src/lib/wpi/UnsavedDialog.svelte` | Save / discard / keep editing prompt (native `<dialog>`) |
| `ChenWeb/web/src/lib/wpi/layouters/index.ts` | Element layouter registry `elementLayouters`, keyed by code module ID |
| `ChenWeb/web/src/lib/wpi/layouters/FlowLayouter.svelte` | `flow-layouter`: wrapping left-to-right flow, configured by the panel's or the copy's `config` |
| `ChenWeb/web/src/lib/wpi/layouters/flow-geometry.ts` | Row-count breaks, overflow text, and separator geometry |
| `ChenWeb/web/tests/wpi-flow/test_flow.py` | Browser checks for flow wrapping, count limits, alignment and text overflow |
| `ChenWeb/web/src/lib/wpi/elements/index.ts` | Code module registry `codeModules`, keyed by code module ID |
| `ChenWeb/web/src/lib/wpi/elements/Element.svelte` | Draws one element instance with its class copy's code module, or an error box naming the module |
| `ChenWeb/web/src/lib/wpi/elements/TextElement.svelte` | `text`: localized static/bound text with optional caption/icon/tooltip and configurable appearance |
| `ChenWeb/web/src/lib/wpi/elements/InputElement.svelte` | `input`: configurable caption, single-line field, help and validation errors |
| `ChenWeb/web/src/lib/wpi/input-validation.ts` | Client-side input rules and error codes |
| `ChenWeb/web/src/lib/wpi/input-validation.test.ts` | Input rule tests |
| `ChenWeb/web/src/lib/wpi/elements/SelectElement.svelte` | `select`: pulldown with options from the instance |
| `ChenWeb/web/src/lib/wpi/elements/ButtonElement.svelte` | `button`: runs its `on_click` trigger |
| `ChenWeb/web/src/lib/wpi/elements/ListElement.svelte` | `list`: queries its records, rows, row click, re-query on show |
| `ChenWeb/web/src/lib/wpi/elements/MenuElement.svelte` | `menu`: tree with folders, `initial_item`, current item from the pane it opens pages in |
| `ChenWeb/web/src/lib/wpi/elements/ChatComposerElement.svelte` | `chat-composer`: message box and tool bar for a harness-backed assistant ([doc](../code_modules/interpreter-chat-composer.md)) |
| `ChenWeb/web/src/lib/wpi/elements/ChatPanelElement.svelte` | `chat-panel`: Chat and Dialog tabs of the page's chat ([doc](../code_modules/interpreter-chat-panel.md)) |
| `ChenWeb/web/src/lib/wpi/elements/ValueEditorElement.svelte` | `value-editor`: any value editor under a caption, bound to an input-doc field; drawn for the 28 value-editor classes ([doc](../code_modules/interpreter-value-editor.md)) |
| `ChenWeb/web/src/lib/components/shared-ui/value-editors/StringValueEditor.svelte` | Single, multilingual and list string value control |
| `ChenWeb/web/src/lib/components/shared-ui/value-editors/string-value.ts` | Empty-value and string-mode conversion rules |
| `ChenWeb/web/src/lib/components/shared-ui/value-editors/string-value.test.ts` | String conversion tests |
| `ChenWeb/web/tests/wpi-string-editor/Harness.svelte` | Browser fixture for string and validator authoring |
| `ChenWeb/web/tests/wpi-string-editor/index.html` | Browser fixture entry page |
| `ChenWeb/web/tests/wpi-string-editor/main.ts` | Browser fixture entry point |
| `ChenWeb/web/tests/wpi-string-editor/vite.config.ts` | Browser fixture configuration |
| `ChenWeb/web/tests/wpi-string-editor/test_editor.py` | Browser interaction checks |
| `ChenWeb/web/src/lib/wpi/chat-session.svelte.ts` | The chat of one page instance, shared by its chat elements; reference-counted per runtime and page instance |
| `ChenWeb/web/src/lib/wpi/chat-agents.ts` | The four harness-backed assistants and the assistant and model selection |
| `ChenWeb/web/src/lib/wpi/chat-agents.test.ts` | Assistant selection tests |
| `ChenWeb/web/src/routes/wpi/[appId]/+page.ts` | Route load (`ssr = false`) |
| `ChenWeb/web/src/routes/wpi/[appId]/+page.svelte` | Route page: fetches the bundle, shows validation errors or the app |
| `ChenWeb/web/src/lib/wpi/text-attributes.ts` | Text R2 defaults, value checks and literal/bound conversion |
| `ChenWeb/web/src/lib/wpi/text-attributes.test.ts` | Text defaults, conversion, shared value vectors and old-copy tests |
| `ChenWeb/web/src/lib/wpi/properties/types.ts` | Property editor definition types: `EditorDef`, `GroupDef`, `PropertyDef`, `PropertySource` (OpenSpec `wpi-property-editors`) |
| `ChenWeb/web/src/lib/wpi/properties/common-sense.ts` | The value editor for a property no definition describes |
| `ChenWeb/web/src/lib/wpi/properties/common-sense.test.ts` | Common-sense editor tests |
| `ChenWeb/web/src/lib/wpi/properties/shared.ts` | Groups and choices the definitions share: placement, element size, binding modes, font weights |
| `ChenWeb/web/src/lib/wpi/properties/text.ts` | `text` property editor definition, with the module's validation and warnings |
| `ChenWeb/web/src/lib/wpi/properties/input.ts` | `input` property editor definition and the input module's defaults |
| `ChenWeb/web/src/lib/wpi/properties/elements.ts` | `select`, `button`, `list` and `menu` property editor definitions |
| `ChenWeb/web/src/lib/wpi/properties/chat.ts` | `chat-composer` and `chat-panel` property editor definitions |
| `ChenWeb/web/src/lib/wpi/properties/page.ts` | Page, pane and flow-layouter panel property editor definitions |
| `ChenWeb/web/src/lib/wpi/properties/sources.ts` | What the property editor reads and writes for an element, the page, a pane and a panel |
| `ChenWeb/web/src/lib/wpi/properties/index.ts` | Definitions by code module ID; `moduleFallbacks` |
| `ChenWeb/web/src/lib/wpi/properties/properties.test.ts` | Definition and source tests |
| `ChenWeb/web/src/lib/components/shared-ui/canvas/text-property-labels.ts` | Paraglide labels/help for text attributes, groups and choices |
| `ChenWeb/server/api/wpi/text-values.json` | Shared finite CSS-color and icon vocabulary used by client/server |
| `ChenWeb/server/api/wpi/text-attribute-cases.json` | Shared valid/invalid client/server text-value cases |
| `ChenWeb/web/tests/wpi-text/Harness.svelte` | Real-component Chromium harness and interaction checks |
| `ChenWeb/web/tests/wpi-text/bundle.json` | Real-component Chromium harness and interaction checks |
| `ChenWeb/web/tests/wpi-text/index.html` | Real-component Chromium harness and interaction checks |
| `ChenWeb/web/tests/wpi-text/main.ts` | Real-component Chromium harness and interaction checks |
| `ChenWeb/web/tests/wpi-text/test.css` | Real-component Chromium harness and interaction checks |
| `ChenWeb/web/tests/wpi-text/test_text.py` | Real-component Chromium harness and interaction checks |
| `ChenWeb/web/tests/wpi-text/vite.config.ts` | Real-component Chromium harness and interaction checks |
| `ChenWeb/web/src/lib/wpi/properties/class-definition.ts` | Applies value-editor configuration from frozen class metadata to property definitions |
| `ChenWeb/web/src/lib/wpi/properties/class-definition.test.ts` | Regression tests for class editor overrides and value conversions |
| `ChenWeb/web/src/lib/wpi/properties/editor-ids.ts` | Which value editor draws each catalogue ID (built, variant to base, none for unbuilt); used by class overrides and the value-editor element |
| `ChenWeb/web/src/lib/wpi/properties/editor-ids.test.ts` | Every catalogue ID with code resolves to a registered editor |
| `ChenWeb/web/src/lib/components/shared-ui/canvas/element-palette.ts` | Palette entries of element classes: value-editor classes in VALUE EDITORS, the others in ELEMENTS |
| `ChenWeb/web/src/lib/components/shared-ui/canvas/element-palette.test.ts` | Tests for the palette split |
| `ChenWeb/web/src/lib/wpi/validators/index.ts` | Validators as elements use them: instance types, effective constraints, `runValidators` (allOf), `bindingPointer`, `newValidatorInstance`, `acceptsValidators` (OpenSpec `wpi-primitive-validators`) |
| `ChenWeb/web/src/lib/wpi/validators/run.ts` | The nine primitive validator modules and their shared constraints, the twin of the Go package; reads `server/api/wpi/validators/modules.json` |
| `ChenWeb/web/src/lib/wpi/validators/decimal.ts` | Exact decimals with BigInt for comparisons, rounding and `multiple_of` |
| `ChenWeb/web/src/lib/wpi/validators/text.ts` | Whitespace, line breaks, length units and portable patterns |
| `ChenWeb/web/src/lib/wpi/validators/messages.ts` | Error text from codes and params, instance messages, constraint, choice and category labels |
| `ChenWeb/web/src/lib/wpi/validators/cases.test.ts` | Runs the shared `validator-cases.json`, plus decimal, pattern and instance tests |
| `ChenWeb/web/src/lib/wpi/validators/messages.test.ts` | Every error code and constraint has its text |
| `ChenWeb/web/src/lib/wpi/properties/validators.ts` | The Validators group, one group per validator instance, and the source serving `validators.<n>.<constraint>` |
| `ChenWeb/web/src/lib/wpi/properties/validators.test.ts` | Tests for the validator groups and source |
| `ChenWeb/web/src/lib/components/shared-ui/canvas/validator-drop.ts` | Dropping a validator from the palette onto an element node |
| `ChenWeb/web/src/lib/components/shared-ui/canvas/validator-drop.test.ts` | Tests for the drop and the VALIDATORS palette entries |

## 3. Interface

- **Route:** `/wpi/<app-id>` (login required by the server). The URL holds only the app ID.
- **Component:** `WpiApp.svelte` with prop `bundle: Bundle` (from `fetchApp(appId)`);
  `Bundle = {app, pages, warnings}`.
- **Registries** — the extension points; each name must also be accepted by the backend
  validator (`server/api/wpi/validate.go`):
  - `elementLayouters: Record<string, Component<LayouterProps>>` with
    `LayouterProps = { instanceId: string; page: PageDescriptor; paneId: string; panel: Panel }`;
    the page layouter code is `PaneView.svelte` (module `page-layouter`);
  - `codeModules: Record<string, Component<ElementProps>>`, keyed by code module ID, with
    `ElementProps = { instanceId: string; element: ResolvedElement }`; `element.module` is the
    class copy's `code_module_id`. Each module also needs its row in `kb.code_modules` and its
    document in `KnowledgeStore/doc-repo/code_modules/`. Action classes are dispatched by
    class ID in `runtime.svelte.ts` (`runTrigger`).
- **Runtime** (`getRuntime()` inside the app): `start`, `openPage`, `resolvePane`,
  `closePage`, `save`, `runTrigger`, `isShowing`, `queryList`, `read` / `write` / `errorsFor` /
  `validationErrorsFor` for bindings, `isDirty`, `anyDirty`; state `pages` (page instances),
  `panes` (Panel Cache), `paneSizes`, `root`.
- **Validators** (`$lib/wpi/validators`): `runValidator(module, constraints, value, path)` →
  `{valid, errors, value, hasValue}`; `runValidators(list, value, path)` for an element's
  instances; `validationErrorText(error, instance)` in `messages.ts`. `input`, `select` and
  value-editor elements run them when editing ends and before a save
  ([contract](../code_modules/validator-primitive.md)).
- **API client:** `fetchApp(appId)`, `runAction(ref, args, inputDoc?)` with
  `ref = {kind: 'page', id, pointer}`; both throw `WpiError` (`status`, `issues`,
  `fieldErrors`, `validationErrors`). For the editor: `savePage` (returns `{version, page}`),
  `listElementClasses`, `createElementClass`, `getElementClass`, `updateElementClass`,
  `listCodeModules`, `listValidatorClasses`.

## 4. Configuration

The shared length editor accepts the optional `editor_options` described in
[its code-module document](../code_modules/interpreter-value-editor.md#521-contract-and-implementation),
including value display, numeric choices, default and help tip. Existing option defaults and
stored length strings remain supported. Its `value` type accepts a unitless numeric string; the Properties panel exposes its default as a length control.

## 5. Usage

Adding a code module, for example a checkbox:

```ts
// 1. A row in kb.code_modules (a migration) and its document,
//    KnowledgeStore/doc-repo/code_modules/checkbox.md.
// 2. elements/CheckboxElement.svelte receives { instanceId, element } and uses
//    rt.read(instanceId, element.desc.data_binding) / rt.write(...), like InputElement.
// elements/index.ts:
import CheckboxElement from './CheckboxElement.svelte';
export const codeModules = { /* … */ checkbox: CheckboxElement };
// 3. server/api/wpi/validate.go: add "checkbox" to codeModules with its attributes.
// 4. Store a class row naming it (format 0.4): "code_module_id": "checkbox", and per
//    instance attribute {"help_tip": …, "default_value": …, "instance_modifiable": false?},
//    default_value null when every instance must set it.
```

A new class of an existing module, such as `fancy-button` drawn by `button`, needs no
code: only its class row. Pages written afterwards get copies of it; pages written before keep
the copies they hold.

Opening an app: write its descriptors with `PUT /api/v1/wpi/descriptors/<kind>/<id>`
(module `20261026-02`), then open `/wpi/<app-id>`.

## 6. Behaviour and conventions

Text R2 is implemented in the existing `text` module/class (active class version 5). Its
30 flat attributes have 26 concrete defaults, with deliberate omissions for content,
binding, caption and maximum width. See [text contract](../code_modules/interpreter-text.md).
Text remains read-only and selectable. Its caption wraps, icons are decorative, tooltips
support keyboard/touch and close on hide/unmount, and explicit dimensions scroll locally.
No Page Styles integration is implied. Browser checks run with
`python3 web/tests/wpi-text/test_text.py --start-server` from ChenWeb.

- Input controls validate on blur and before save, and the server validates the stored page rules; see `doc-repo/code_modules/interpreter-input.md`.
- `rt.read` reads each attribute on a binding's path as a property before calling `getPath`.
  A property read subscribes to an attribute the input doc does not have yet, and
  `Object.hasOwn` on a Svelte state proxy does not. So an element bound to an absent attribute
  shows a value written there later (fixed 2026-11-02 in 3.7.0; value editors, which redraw
  from the stored value, exposed it).
- The route's root sets `select-text`; only the pane resize handle is `select-none`.
- All of the interpreter's own text goes through Paraglide (`wpi_*` keys in English and
  Chinese). A `label` (and a class's `description`) may hold one text per language and is
  shown in the current locale, falling back to `en`. The text module also localizes static
  content, captions and tooltips; plain strings are shown as written.
- Colours come from theme tokens, so WPI pages follow light and dark mode; split panes are
  separated by the theme's border colour.
- Nothing fails silently: unknown page or element layouters, code modules, panes an
  `open-page` cannot resolve, failed loads and failed saves show an `ErrorBox`; save rule
  failures show translated messages next to the bound field.
- A pane that switches pages hides the one it showed: it stays mounted (hidden with CSS),
  keeping its input doc and unsaved changes, and never prompts. Closing a page (`close-page`)
  closes the pages opened in its panes first, each after the unsaved-changes check; its pane
  then shows its own panel. Leaving the page while any page instance is dirty triggers the
  browser's warning.
- A page's or `open-page`'s `input` without an `action` attribute is static data: the page
  instance starts with a copy of it (`$state.snapshot`, since the bundle is held in `$state`)
  and never reloads it. Inputs with an action (`load`, `query`, `load-file`) run on the server.

## 7. Scope and limits

- Small vocabulary: one page layouter code module (`page-layouter`, classes `single-pane`
  and `top-left-middle-right-bottom`), one element layouter (`flow-layouter`), eight element
  code modules (the six first ones, `chat-composer` and `chat-panel`), action classes `load`, `save`, `query`, `load-file`, `open-page`,
  `close-page`, `save-page`. No page state, conditions, timed refresh or age-out; lists are
  read-only; `open-page` opens pages in panes only (no tab, new tab or iframe yet).
- The interpreter does not show `page_name` or a page's `description`; they are for authors
  searching pages (backend `GET /api/v1/wpi/pages`).
- Text content/captions/tooltips and field labels can be localized. Menu items, list columns
  and select options still use plain strings, so complete descriptor-wide localization remains future work.
- Only panes with a pixel size can be resized by dragging; the dragged size lasts until the
  app is reloaded.
- Until age-out is built, a pane keeps every page opened in it.
- Move to `shared/svelte` when a second project uses it.
