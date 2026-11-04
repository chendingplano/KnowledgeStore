# Code module: `value-editor`

**Code module ID:** `value-editor` \
**Classes using it:** 29, one per value editor of the WPI Editor (table below) \
**Implementation status:** implemented and active, 2026-11-02; 24 classes active, 5 drafts \
**Catalogue row:** `kb.code_modules` `value-editor`, "Value Editor", type `element`, `module_doc`
`interpreter-value-editor.md`, status `active`, from migration
`ChenWeb/project_migrations/20261102000003_wpi_value_editor_elements.sql` \
**Frontend:** `ChenWeb/web/src/lib/wpi/elements/ValueEditorElement.svelte`, registered in
`elements/index.ts`; editor IDs resolved by `ChenWeb/web/src/lib/wpi/properties/editor-ids.ts`;
the editors themselves in `ChenWeb/web/src/lib/components/shared-ui/value-editors/` \
**Backend:** `codeModules["value-editor"]` in `ChenWeb/server/api/wpi/validate.go`; checks in
`ChenWeb/server/api/wpi/value_editor_attributes.go` \
**OpenSpec:** ChenWeb change `wpi-value-editor-elements` \
**Part of:** reusable module `20261026-01`, [Web Page Interpreter frontend](../modules/module-web-page-interpreter-frontend.md) \
**Design:** [WPI Editor devdoc](../devdocs/202610/2026102701-devdoc-wpi-editor.md) §1.3.9 (the
value editors); [WPI devdoc](../devdocs/202610/2026102601-devdoc-web-page-interpreter.md) §3.5 Elements

## Purpose and boundary

The value editors are the controls the WPI Editor's Properties panel uses to edit one property:
a colour picker, a length editor, a data-source editor and so on. This module puts any of them
on a WPI page as an element. The element shows a caption above the editor and binds the
editor's value to an input-doc field, like `input`.

Each class fixes which editor it draws (`editor`) and gives the editor's default options
(`editor_options`). So one module serves every value editor, and building a new editor needs
no new module: it needs the editor, a line in `editor-ids.ts`, and a class.

In the WPI Editor's palette the classes are listed in the **VALUE EDITORS** folder, after
ELEMENTS. They are dropped, configured and saved exactly like the classes in ELEMENTS.

Not part of the module: field rules (`required`, validation), on-change actions, and styling
beyond the caption. The editors keep the compact look they have in the Properties panel.

## Classes

All rows are `kind = 'element'`, version 1, `schema_version` `0.4`. The emoji class is created by
`seed:wpi-emoji-picker`; the others are created by `seed:wpi-value-editor-elements`. *Caption* is the default `label` (English / Chinese).
*Options* is the default `editor_options`.

| Class | `editor` | Status | Caption | Options | What it draws |
| --- | --- | --- | --- | --- | --- |
| `text-editor` | `text` | active | Text / 文本 | `{}` | One line of text |
| `multiline-text-editor` | `multiline-text` | active | Text / 文本 | `{"rows": 3}` | Longer text |
| `localized-text-editor` | `localized-text` | active | Text / 文本 | `{}` | One string, or English and Chinese |
| `number-editor` | `number` | active | Number / 数字 | `{"integer": false}` | A number; `min`, `max`, `integer` |
| `switch` | `switch` | active | Enabled / 启用 | `{}` | On or off |
| `value-picker` | `value-picker` | active | Value / 值 | `{"choices": []}` | One value from `choices` |
| `ordered-multi-picker` | `ordered-multi-picker` | active | Values / 值 | `{"choices": [], "minItems": 0}` | Several values from `choices`, in order |
| `string-list` | `string-list` | active | Keywords / 关键词 | `{}` | Comma-separated words |
| `date-picker` | `date-picker` | draft | Date / 日期 | `{}` | Not built |
| `time-picker` | `time-picker` | draft | Time / 时间 | `{}` | Not built |
| `color-picker` | `color` | active | Colour / 颜色 | `{"theme": true}` | None, one colour, or light and dark |
| `length-editor` | `length` | active | Length / 长度 | `{"keywords": ["auto"], "units": ["px", "rem", "em", "%"]}` | A length or keyword |
| `font-picker` | `font-picker` | active | Font / 字体 | `{}` | The text editor; accepts only `inherit` or a CSS font-family list |
| `alignment-picker` | `alignment-picker` | active | Alignment / 对齐 | `{"choices": ["left", "center", "right"]}` | The value-picker; an instance may use `top`, `center`, `bottom` |
| `icon-picker` | `icon-picker` | active | Icon / 图标 | `{}` | The shared icon library's search picker; stores the icon name |
| `emoji-picker` | `emoji-picker` | active | Emoji / 表情 | `{}` | The shared emoji library's search picker; stores the Unicode string |
| `button-type-picker` | `button-type-picker` | draft | Button type / 按钮类型 | `{}` | Not built |
| `database-picker` | `database-picker` | draft | Database / 数据库 | `{}` | Not built |
| `schema-picker` | `schema-picker` | draft | Schema / 模式 | `{}` | Not built |
| `table-picker` | `table-picker` | active | Table / 表 | `{}` | Pick Table (`20261029-01`); stores `database.schema.table` |
| `field-picker` | `field-picker` | active | Fields / 字段 | `{"table": ""}` | Pick Fields (`20261029-02`) for `table`; stores the field list |
| `data-source-editor` | `data-source` | active | Data source / 数据源 | `{}` | Table, fields, row limit, action, result, sort order |
| `column-list-editor` | `column-list` | active | Columns / 列 | `{}` | A list's columns |
| `sort-order-editor` | `sort-order-editor` | active | Sort order / 排序 | `{}` | Sort columns, each ascending or descending |
| `validation-editor` | `validation` | active | Input rules / 输入规则 | `{"numberRules": false}` | Text or number input rules |
| `action-picker` | `action-picker` | active | Action / 动作 | `{}` | The value-picker; without `choices`, every active action class |
| `layouter-picker` | `layouter-picker` | active | Page layouter / 页面布局器 | `{}` | The value-picker; without `choices`, every page layouter class |
| `read-only-value` | `read-only` | active | Value / 值 | `{}` | The value, shown and not edited |
| `json-editor` | `json` | active | JSON / JSON | `{"rows": 3}` | Any value as JSON text |

A draft is listed in the palette, marked as a draft, and is never run: a page that names one is
rejected. To build one: add its editor under `value-editors/`, register it in
`property-editor/editors.ts`, add its ID to `editor-ids.ts`, take it out of
`pendingValueEditors` in `value_editor_attributes.go` and `PENDING_EDITORS` in
`canvas/class-editor.ts`, then activate the class through the class update endpoint.

## Descriptor rules and precedence

As for every element: `schema_version` `"0.4"`, `code_module_id` `"value-editor"`, the complete
class copy in `class`, a fixed value before the instance value before the class default, `null`
instance values invalid, and later class edits reaching only new instances. A page-level
`binding_mode` applies.

## Attribute contract

| Exact path | Type and allowed values | Absence, validation and behaviour |
| --- | --- | --- |
| `E.editor` | One of the 29 IDs above. In an active class or a page: one of the 24 that are drawn | Required. Class scope: every class fixes it, so an instance cannot change it. Any other value is an error at `/editor`. |
| `E.label` | Text: a string or `{"en", "zh-cn"}` | Required; every class gives the editor's name as the default. Drawn above the editor, in the page's language. |
| `E.data_binding` | `$input_doc.<path>` | Optional. The editor shows the value at the path and writes each value it applies there, creating missing attributes. Absent: the value stays on the page. |
| `E.binding_mode` | `read-only`, `read-write` | Required; class default `read-write`. `read-only` draws the read-only value editor with the bound value. |
| `E.editor_options` | A JSON object | Optional; instance scope, with the class default above. Passed to the editor as its options. Anything but an object is an error at `/editor_options`. |
| `E.width`, `E.min_width`, `E.max_width`, `E.height` | `auto`, `elastic`, or a length in px, rem, em, % | Class default width `elastic`. |

**Values.** A value the editor unsets is written as `null`. Server field errors for the bound
path are shown under the editor, as for `input`. `action-picker` and `layouter-picker` load
their choices when drawn, from `/api/v1/wpi/classes/action?scope=all` and
`/api/v1/wpi/classes/page-layouter`; if loading fails, "The choices could not be loaded." /
"无法加载可选项。" is shown. `editor_options.choices` replaces the loaded list. Options that are
functions in the Properties panel (choice labels) cannot be stored, so pickers on a page show
raw values.

**font-picker.** Until font management exists (a separate change, decided 2026-11-02), the font
picker is the text editor. Text that is not `inherit` or a CSS font-family list is not applied.
Leaving the field shows why, with Abandon Edit and Stay Edit, as in the Properties panel.

**icon-picker.** A button shows the chosen icon and its name, or "Choose an icon" / "选择图标";
it opens the library's search, which finds icons by English or Chinese keyword or description.
Picking one stores its name, for example `refresh-cw`, and closes the search. **Clear** /
**清除** unsets it. The search uses `/shared_api/v1/icons/search` and `/by-name/:name/svg`,
which need the `shared.icon_library` table.

## Color-picker revision 1

This section describes the approved change to the existing `color` editor.
It applies both in the Properties panel and when the `color-picker` class is placed on a
page. The existing class identity, descriptor attributes, defaults, binding and value shapes
remain unchanged; saved class copies receive the revised editor without a descriptor update.

In the Properties panel, the mode selector sits in the property heading immediately before
Reset; the current color controls are below. A color-picker element places the selector next
to its caption and the current color controls below, matching the Properties panel. Retain the existing None,
Single and Light and dark choices (the latter is available when `editor_options.theme` is
true or the current value is already a theme). None shows no color; Single shows one swatch
and editable color value; Light and dark shows two individually labeled swatches and values.
Use the compact swatch/value/opacity treatment in the supplied reference. On narrow panels,
keep the row usable with horizontal overflow rather than clipping controls. CSS color text
remains editable and copyable, including existing values that are not hex colors.

Clicking either swatch opens a floating dialog for that specific color. Its title bar is a
drag handle and includes a close button; a resize handle changes its dimensions. Constrain
the dialog to a usable minimum size and keep it reachable in the viewport. Closing it or
pressing Escape retains already applied changes and returns focus to the opening swatch.
Movement and resizing must have keyboard-accessible alternatives. The dialog uses the
reference's color field, hue and opacity sliders, numeric color controls and a palette area;
all controls need accessible names and visible focus. Changes apply through the existing
validation and binding path. Invalid typed values remain editable and are not applied.

The palette area has a dropdown with **Common colors / 常用颜色** and **Color families /
颜色系列**. Common colors shows a grid of selectable swatches; Color families provides a
family selector and its swatches using the existing family data. A chosen swatch updates the
active color. The controls, labels and errors are available in English and Chinese. The dialog
does not imply support for the reference image's library, gradient, eyedropper or other icons
unless implemented and separately specified. Color conversion and opacity must preserve the
visible result; editing one theme variant must not change the other. Existing CSS values must
not be silently rewritten merely by opening the dialog.

**Review assumptions:** The two menu entries select palette content, not the color mode;
the existing None option and theme availability are retained for compatibility. The dialog
edits one variant at a time, and its position and size need not persist after it closes.
No new configurable descriptor attributes or class defaults are proposed. The existing class remains active. The editor implementation uses the existing shared value
editor; no descriptor or catalog change is needed.

**Review record:** Revision 1 approved by the user on 2026-11-04. Implemented in
`ChenWeb/web/src/lib/components/shared-ui/value-editors/ColorPicker.svelte`, with color
conversion in `color-math.ts`. The existing color families supply the palette. Unit tests
cover conversion and opacity. Browser interaction verification is still pending. CSS values
that depend on context, such as custom properties, cannot be resolved by the canvas preview
and display as black in the dialog until changed; opening alone does not rewrite them.

## States

| State | Behaviour |
| --- | --- |
| Unbound | The editor works; its value is kept by the element and lost when the page closes. |
| Read-only | The bound value is shown as text; nothing can be edited. |
| Editor not drawn | An error box: "Value editor "{editor}" is not built yet." This happens only for a class copy that is changed by hand, since drafts cannot be placed. |
| Editor preview | As on a page; `action-picker` and `layouter-picker` still load their choices. |

## Keyboard, accessibility and text

The caption is a `<label>` for the editor. Each editor keeps its Properties-panel keyboard
behaviour. Text stays selectable. Module text is in Paraglide under `wpi_value_editor_*`,
`wpi_icon_picker_*` and `icon_search_*`; captions are data, shown in the page's language.

## Validation and errors

| Check | When | Result |
| --- | --- | --- |
| `editor` is not one of the 28 IDs (a draft) or of the 23 drawn ones (active class, page) | Class save, page save and run | Error at `/editor` |
| `editor_options` is not an object | Class save, page save and run | Error at `editor_options` |
| `data_binding` is not a `$input_doc` path, or `binding_mode` is not allowed | Page save and run | Error, naming the path |
| An instance sets `editor` | Page save and run | Error: the class fixes it |
| A page names a draft class | Page save | Rejected, as for every draft |

## Property editor

Drawn from `ChenWeb/web/src/lib/wpi/properties/elements.ts` (`valueEditor`); change the two
together. Each class's own `value_editor` metadata travels with its copy, as for every class.

| Group | Attribute | Value editor | Data and rules |
| --- | --- | --- | --- |
| Placement | pane, position | read-only | Measured on the canvas |
| General | `label` | localized-text | |
| General | `data_binding` | text | A `$input_doc` path |
| General | `binding_mode` | value-picker | `read-only`, `read-write` |
| Editor | `editor` | read-only | Fixed by the class |
| Editor | `editor_options` | json | The editor's options |
| Size | `width`, `height`, `min_width`, `max_width` | length | `auto`, `elastic`, or a number in px, rem, em or % |

## Example

The `value-picker` class, abridged (help tips, `value_editor` metadata and
`attribute_definitions` omitted):

```json
{
  "descriptor_id": "value-picker",
  "schema_version": "0.4",
  "code_module_id": "value-editor",
  "description": { "en": "One value from a list, in a pulldown", "zh-cn": "从下拉列表中选择一个值" },
  "editor": { "scope": "class", "default_value": "value-picker" },
  "label": { "scope": "instance", "default_value": { "en": "Value", "zh-cn": "值" } },
  "data_binding": { "scope": "instance" },
  "binding_mode": { "scope": "instance", "default_value": "read-write" },
  "editor_options": { "scope": "instance", "default_value": { "choices": [] } },
  "width": { "scope": "instance", "default_value": "elastic" }
}
```

An instance on a page:

```json
{ "element": "value-picker", "data_binding": "$input_doc.status", "editor_options": { "choices": ["draft", "final"] }, "class": { "...": "the class copy" } }
```
