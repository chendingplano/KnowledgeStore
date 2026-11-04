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

## 1. Purpose and boundary

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

## 2. Classes

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

## 3. Descriptor rules and precedence

As for every element: `schema_version` `"0.4"`, `code_module_id` `"value-editor"`, the complete
class copy in `class`, a fixed value before the instance value before the class default, `null`
instance values invalid, and later class edits reaching only new instances. A page-level
`binding_mode` applies.

## 4. Attribute contract

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

## 5. Value Editors

### 5.1 Color picker

The `color` editor is shared by the Properties panel and the `color-picker` page element.
The mode selector appears in the property heading before Reset, or beside the page element's
caption. The color controls appear below it. Light and Dark are separate rows; their labels
are outside the color fields. Each field shows a swatch, editable CSS color text and opacity.

The stored value determines the selected mode:

| Mode | Value | Behavior |
| --- | --- | --- |
| None | Missing, `null`, or an empty string | No color controls. Unsetting a bound value writes `null`. |
| Single color | A CSS color string, such as `"#89cff0"` | One color control. |
| Light and dark | `{ "light": "#ffffff", "dark": "#000000" }` | One control for each variant. Editing one preserves the other. |

`editor_options.theme: true` enables the Light and dark option. It also remains available
when the current value is already a theme object. Changing to Single keeps the light color;
changing a single color to Light and dark starts both variants from that color. Changing
`auto` or an unset value to Light and dark starts with white and black. A newly mounted,
unbound color-picker with `theme: true` starts with that white/black pair. Its local value
is lost when the element is unmounted. A bound editor displays the bound value, including
an unset value, without writing defaults to the input document.

Click a swatch to open a floating dialog for that variant. It provides a color field, hue
and opacity sliders, RGB inputs and a palette. The palette menu offers **Common colors /
常用颜色** and **Color families / 颜色系列**; the latter also offers a family selector.
Selecting a swatch or changing a dialog control applies a color through the editor's existing
validation and binding path. The dialog edits one variant at a time. Its title bar moves it,
and its resize handle changes its dimensions; both support arrow keys. Escape or the close
button closes it and returns focus to the swatch. Applied changes remain in place.

Typing an invalid CSS color leaves the draft editable without applying it; leaving the field
shows the error and options to abandon or continue editing. Opening the dialog alone does
not rewrite an existing color. The dialog does not provide the reference image's libraries,
gradients or eyedropper. CSS values dependent on context, such as custom properties, cannot
be resolved by its canvas conversion and appear black in the dialog until changed.

#### 5.1.1 Element sizing and canvas resize

A `color-picker` element has a content minimum of **200 × 120 CSS pixels** in the flow
layouter, including the canvas preview. This minimum is combined with the element and
panel's configured minimums. A canvas resize below an applicable minimum opens a confirmation
beside the selected element; the resize is not applied while the confirmation is open.
**Cancel** discards the resize; **OK** applies it with each undersized dimension raised to
its minimum. The element remains selected. If the resulting size crosses another adjustable
limit, its existing override confirmation still applies. A class-fixed size or limit cannot
be overridden in the canvas. These controls apply to canvas resizing; an ancestor pane that
is itself too small can still constrain what is visible.

#### 5.1.2 Implementation and verification

The color editor is `ChenWeb/web/src/lib/components/shared-ui/value-editors/ColorPicker.svelte`;
`ColorModeSelect.svelte` shares its mode selector with the Properties panel and
`ValueEditorElement.svelte`. `color-math.ts` handles RGB/HSV and opacity conversion, and
`commonColors.ts` provides palette data. The content minimum is in
`web/src/lib/wpi/element-minimum.ts`; `layout.ts` applies it and
`canvas/PagePreview.svelte` handles resize confirmation and selection. Existing saved class
copies use these editor changes without a descriptor update. No new descriptor attributes or
catalogue rows were introduced.

The user approved the initial color-picker revision on 2026-11-04; the subsequent layout and
resize changes were requested in the same session. Focused tests cover color conversion,
mode changes, minimum-size calculation, layout and resize limit calculations. Frontend
`bun run check` passed during implementation with one unrelated existing CSS warning.
The latest selection-preservation fix has not been verified in an authenticated browser
session.

### 5.2 Length Editor

"Length" property is defines the values of width, height, radius, etc.

- length property has a label that describes what it is
- length property may define its default value
- length property can have values of "auto", "elastic", percent ('%"), pixels ('px'), 'em', 'default'. These are types of length property. If the property does not have a default, do not list 'default'
- the actual value of "auto" and "elastic" will be determined by system defaults, layouters, styles, etc.

**Looking-and-feel**

- Show as "label" + "value" + "type", and a small icon for its help tip
- "value" can be displayed as a label, an input, or a pulldown menu. 
- "value" can be read-only or read-write. Read-only shows "value" as a label with a background color. Read-write shows "value" using the input element.
- if "value" is shown as a pulldown menu, users can use the pulldown menu to select a value instead of manually enter the value. Optionally, the pulldown menu allows users to enter values.
- If "value" is displayed as a label and the property is read-write, double clicking the label changes it to use an input element to let users enter/change values and it changes back to "label" when losing focus.


#### 5.2.1 Contract and implementation

The following contract was approved on 2026-11-04.

The existing `length` editor is shared by the Properties panel and page elements. Keep
existing stored values and class copies compatible: a numeric length is a CSS string such
as `"12px"` or `"50%"`; `auto` and `elastic` are strings. Selecting **default** unsets
the property rather than storing the literal string `"default"`, so the existing class or
system default can take effect. Offer it only when a concrete property default is known.
For a page-bound value, unsetting writes `null`, as in §4; a page element must explicitly
supply its default in `editor_options.defaultValue` for the choice to appear. Selecting a
default does not write its displayed value to the bound field.

The label and help tip belong to the host property or element. Show them alongside the
value and type; omit the tip icon when no help text is supplied. The type selector offers
only configured `keywords` and `units`, plus default when available. Preserve `rem` where
already configured: existing descriptors and property definitions use it. Selecting a
numeric unit retains the current numeric amount, or starts at zero when the previous type
had no numeric amount; selecting a keyword applies that keyword. Selecting a unit changes
the suffix without converting the numeric amount. Invalid edits remain unapplied and use
the existing abandon/stay error flow. Existing length validation, including its nonnegative
and percentage limits, remains in force.

Optional `editor_options` for the page element and the equivalent options on a
Properties-panel definition:

| Option | Type and default | Behavior |
| --- | --- | --- |
| `defaultValue` | Valid length string; absent | Enables default and provides its displayed value. In the Properties panel, use the property's class default if present. |
| `valueDisplay` | `input`, `label`, `select`; default `input` | Label enters editing on double-click or keyboard activation when writable; it returns to a label on blur after a valid edit. |
| `choices` | Array of numeric strings; default `[]` | Values offered by `select` for the selected numeric unit. |
| `allowCustomValue` | Boolean; default `false` | In `select` mode, allow typing a value as well as choosing one. |
| `helpTip` | Localized text; absent | Page-element help text; Properties-panel help continues to come from its property definition or class. |

Read-only shows the current value as a non-editable, shaded label and disables type
changes. `auto`, `elastic`, and default have no separately editable numeric amount. An
unset value without a default is displayed empty. A saved value whose unit or keyword is
no longer offered remains visible until changed; merely opening the editor does not rewrite
it. The UI text and accessible names are localized in English and Chinese. A keyboard user
can activate the editable label and operate the type and value selectors.

The shared control is `LengthEditor.svelte`; `values.ts` splits and changes types.
`PropertyEditor.svelte` supplies the class default and fixed state; `ValueEditorElement.svelte`
supplies binding state and page help. Existing class copies need no changes. The active
`length-editor` class remains version 1; its existing `editor_options` object accepts these
additional options without changing the descriptor schema. Focused value tests cover unit
changes and unsetting. Browser interaction verification remains pending.

## 6. States

| State | Behaviour |
| --- | --- |
| Unbound | The editor works; its value is kept by the element and lost when the page closes. |
| Read-only | The bound value is shown as text; nothing can be edited. |
| Editor not drawn | An error box: "Value editor "{editor}" is not built yet." This happens only for a class copy that is changed by hand, since drafts cannot be placed. |
| Editor preview | As on a page; `action-picker` and `layouter-picker` still load their choices. |

## 7. Keyboard, accessibility and text

The caption is a `<label>` for the editor. Each editor keeps its Properties-panel keyboard
behaviour. Text stays selectable. Module text is in Paraglide under `wpi_value_editor_*`, `wpi_color_*`,
`wpi_icon_picker_*` and `icon_search_*`; captions are data, shown in the page's language.

## 8. Validation and errors

| Check | When | Result |
| --- | --- | --- |
| `editor` is not one of the 29 IDs (a draft) or of the 24 drawn ones (active class, page) | Class save, page save and run | Error at `/editor` |
| `editor_options` is not an object | Class save, page save and run | Error at `editor_options` |
| `data_binding` is not a `$input_doc` path, or `binding_mode` is not allowed | Page save and run | Error, naming the path |
| An instance sets `editor` | Page save and run | Error: the class fixes it |
| A page names a draft class | Page save | Rejected, as for every draft |

## 9. Property editor

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

## 10. Example

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
