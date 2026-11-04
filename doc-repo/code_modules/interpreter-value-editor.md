# Code module: `value-editor`

**Code module ID:** `value-editor` \
**Classes using it:** 30, one per value editor of the WPI Editor (table below) \
**Implementation status:** implemented and active; 25 classes active, 5 drafts \
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

All rows are `kind = 'element'`, `schema_version` `0.4`; `length-editor` and `string-editor` are version 3 and the other classes are version 2. The emoji class is created by
`seed:wpi-emoji-picker`; the others are created by `seed:wpi-value-editor-elements`. *Caption* is the default `label` (English / Chinese).
*Options* is the default `editor_options`.

| Class | `editor` | Status | Caption | Options | What it draws |
| --- | --- | --- | --- | --- | --- |
| `text-editor` | `text` | active | Text / 文本 | `{}` | One line of text |
| `string-editor` | `string-editor` | active | Text / 文本 | `{"mode":"single","languages":["en","zh-cn"],"emptyAsNull":true,"choices":[],"commitOnBlur":false}` | Single, multilingual, or list value |
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
| `length-editor` | `length` | active | Length / 长度 | `{"keywords": ["auto"], "units": ["px", "rem", "em", "%"], "displayType": false}` | A length or keyword |
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
| `E.editor` | One of the 30 IDs above. In an active class or a page: one of the 25 that are drawn | Required. Class scope: every class fixes it, so an instance cannot change it. Any other value is an error at `/editor`. |
| `E.label` | Text: a string or `{"en", "zh-cn"}` | Required; every class gives the editor's name as the default. Drawn above the editor, in the page's language. |
| `E.data_binding` | `$input_doc.<path>` | Optional. The editor shows the value at the path and writes each value it applies there, creating missing attributes. Absent: the value stays on the page. |
| `E.binding_mode` | `read-only`, `read-write` | Required; class default `read-write`. `read-only` draws the read-only value editor with the bound value. |
| `E.editor_options` | A JSON object | Optional; instance scope, with the class default above. Passed to the editor as its options. Anything but an object is an error at `/editor_options`. |
| `E.width`, `E.min_width`, `E.max_width`, `E.height` | `auto`, `elastic`, or a length in px, rem, em, % | Class default width `elastic`. |
| `E.validators` | An array of validator instances ([validator-primitive.md](validator-primitive.md) §3) | Optional, and allowed even when the class copy does not name it. All must pass. They run after the editor applies a value and before a save, and again in the backend on save; their errors show under the editor. Not checked while `read-only`. |

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
- length property can have values of "value", "auto", "elastic", percent ('%"), pixels ('px'), 'em', 'default'. These are types of length property. If the property does not have a default, do not list 'default'
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
as `"12px"` or `"50%"`; `value` stores a unitless numeric string such as `"12.5"`; `auto` and `elastic` are strings. Selecting **default** unsets
the property rather than storing the literal string `"default"`, so the existing class or
system default can take effect. Offer it only when a concrete property default is known.
For a page-bound value, unsetting writes `null`, as in §4; a page element must explicitly
supply its default in `editor_options.defaultValue` for the choice to appear. Selecting a
default does not write its displayed value to the bound field.

The label and help tip belong to the host property or element. Show them alongside the
value and type; omit the tip icon when no help text is supplied. The type selector offers `value`, configured `keywords` and `units`, plus default when available.
Length properties have no separate Reset button; select default from the type list to restore
a configured default.
An unset length without a configured default starts with `value` selected and an empty input. Preserve `rem` where
already configured: existing descriptors and property definitions use it. Selecting a
numeric unit retains the current numeric amount, or starts at zero when the previous type
had no numeric amount; selecting a keyword applies that keyword. Selecting a unit changes
the suffix without converting the numeric amount. Clearing a numeric input keeps the
selected unit and input active while the field has focus; leaving it empty unsets the value.
Invalid edits remain unapplied and use the existing abandon/stay error flow. Existing length validation, including its nonnegative
and percentage limits, remains in force.

Optional `editor_options` for the page element and the equivalent options on a
Properties-panel definition:

| Option | Type and default | Behavior |
| --- | --- | --- |
| `displayType` | Boolean; default `false` for page elements | Shows the type selector when true. When false, the value control shows and edits the complete length, including its unit; Properties-panel length controls retain their type selector. |
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
`PropertyEditor.svelte` supplies the class default and fixed state; the Editor group exposes
`editor_options.defaultValue` as **Default value**, using the same control as Width; `ValueEditorElement.svelte`
supplies binding state and page help. Existing class copies need no changes. The active
`length-editor` class is version 2; its existing `editor_options` object accepts these
additional options without changing the descriptor schema. Focused value tests cover unit
changes and unsetting. Browser interaction tests cover toggling the type selector and editing a displayed default.

#### 5.2.2 JSON descriptor

A length editor is an instance of the `length-editor` element class. Its descriptor is
an object in a panel's `elem_list`; the `class` object is a complete copy of the class at
the time the element is placed. The `editor` is fixed to `"length"` by that class and
must not be supplied as an instance override. The following paths are relative to the
instance object:

| JSON path | Shape and meaning |
| --- | --- |
| `element` | Required string `"length-editor"`. |
| `class` | Required complete class descriptor copy. It identifies the `value-editor` code module and fixes `editor` to `"length"`. |
| `label` | Optional string or `{ "en": string, "zh-cn": string }`; absent uses the class caption. |
| `data_binding` | Optional string `$input_doc.<path>`; absent keeps the value locally. |
| `binding_mode` | `"read-write"` or `"read-only"`; the class default is `"read-write"`, subject to page-level binding mode. |
| `editor_options` | Optional object. The class default is `{ "keywords": ["auto"], "units": ["px", "rem", "em", "%"], "displayType": false }`. An instance-supplied object replaces the class default as a whole; include `keywords` and `units` when those class choices are desired. |
| `editor_options.keywords` | Array of keyword strings such as `"auto"` and `"elastic"`; when absent from the effective options, no keywords are offered. |
| `editor_options.units` | Array selected from `"px"`, `"rem"`, `"em"`, `"%"`; when absent, the editor uses all four. |
| `editor_options.displayType` | Boolean; default `false`. When true, show the type selector; when false, edit the complete value in the value control. |
| `editor_options.defaultValue` | Optional length or keyword string. Its presence offers **Default** when the type selector is visible; it is a display fallback, not an initial write to the input doc. |
| `editor_options.valueDisplay` | `"input"`, `"label"`, or `"select"`; defaults to `"input"`. Applies to numeric values. |
| `editor_options.choices` | Array of numeric strings, for example `["120", "240"]`; used by `"select"`. |
| `editor_options.allowCustomValue` | Boolean, default `false`; with `"select"`, allows typing as well as choosing. |
| `editor_options.helpTip` | Optional string or localized `{ "en": string, "zh-cn": string }`; supplies the page element's help tip. |
| `width`, `height`, `min_width`, `max_width` | Optional layout lengths for the editor element itself, distinct from the value it edits. The class defaults `width` to `"elastic"`. |

The `value` type is always offered and stores a numeric string without a unit. It is the
initial type when there is no value or configured default. Existing layout fields may
interpret a unitless string as pixels; the editor does not add a unit to the stored value.
Individual properties may apply additional validation.

The following is a complete instance with the current version 2 class copy. It can be
placed in a panel's `elem_list`; the surrounding page and panel are omitted. Its input
doc might contain `{ "panel": { "width": "240px" } }`. A numeric value is stored as
one string with its selected unit, or without a suffix for `value`; `"auto"` and `"elastic"` are stored as strings. Selecting
**Default** writes `null` at the binding, rather than storing `"default"` or `"240px"`.
The `default_value` inside the class copy describes a class attribute's default; it is
separate from `editor_options.defaultValue`, the fallback for the length being edited.

```json
{
  "element": "length-editor",
  "label": {
    "en": "Panel width",
    "zh-cn": "面板宽度"
  },
  "data_binding": "$input_doc.panel.width",
  "binding_mode": "read-write",
  "editor_options": {
    "keywords": [
      "auto",
      "elastic"
    ],
    "units": [
      "px",
      "rem",
      "em",
      "%"
    ],
    "defaultValue": "240px",
    "displayType": true,
    "valueDisplay": "select",
    "choices": [
      "120",
      "240",
      "480"
    ],
    "allowCustomValue": true,
    "helpTip": {
      "en": "Choose the width of the panel.",
      "zh-cn": "选择面板的宽度。"
    }
  },
  "class": {
    "descriptor_id": "length-editor",
    "schema_version": "0.4",
    "code_module_id": "value-editor",
    "description": {
      "en": "A length in px, rem, em or %, or a keyword such as auto",
      "zh-cn": "以 px、rem、em 或 % 表示的长度，或 auto 等关键字"
    },
    "implement_notes": {
      "en": "KnowledgeStore/doc-repo/code_modules/interpreter-value-editor.md"
    },
    "editor": {
      "scope": "class",
      "help_tip": {
        "en": "The value editor this class draws.",
        "zh-cn": "此类绘制的值编辑器。"
      },
      "value_editor": {
        "id": "read-only",
        "options": {}
      },
      "default_value": "length"
    },
    "label": {
      "scope": "instance",
      "help_tip": {
        "en": "The caption shown above the editor.",
        "zh-cn": "显示在编辑器上方的标题。"
      },
      "value_editor": {
        "id": "localized-text",
        "options": {}
      },
      "default_value": {
        "en": "Length",
        "zh-cn": "长度"
      }
    },
    "data_binding": {
      "scope": "instance",
      "help_tip": {
        "en": "The input doc attribute the editor shows and edits, such as $input_doc.theme.accent; leave out to keep the value on the page only.",
        "zh-cn": "编辑器显示并编辑的输入文档属性，例如 $input_doc.theme.accent；留空则值只保留在页面上。"
      },
      "value_editor": {
        "id": "text",
        "options": {}
      }
    },
    "binding_mode": {
      "scope": "instance",
      "help_tip": {
        "en": "read-write lets the user edit the value; read-only only shows it.",
        "zh-cn": "read-write 允许用户编辑该值；read-only 只显示该值。"
      },
      "value_editor": {
        "id": "value-picker",
        "options": {
          "choices": [
            "read-only",
            "read-write"
          ]
        }
      },
      "default_value": "read-write"
    },
    "editor_options": {
      "scope": "instance",
      "help_tip": {
        "en": "keywords: the words allowed, such as auto; units: the units allowed.",
        "zh-cn": "keywords：允许的关键字，例如 auto；units：允许的单位。"
      },
      "value_editor": {
        "id": "json",
        "options": {
          "rows": 3
        }
      },
      "default_value": {
        "keywords": [
          "auto"
        ],
        "units": [
          "px",
          "rem",
          "em",
          "%"
        ],
        "displayType": false
      }
    },
    "width": {
      "scope": "instance",
      "help_tip": {
        "en": "Width of the editor.",
        "zh-cn": "编辑器宽度。"
      },
      "value_editor": {
        "id": "length",
        "options": {
          "keywords": [
            "auto",
            "elastic"
          ],
          "units": [
            "px",
            "rem",
            "em",
            "%"
          ]
        }
      },
      "default_value": "elastic"
    },
    "attribute_definitions": {
      "/description": {
        "scope": "class",
        "value_editor": {
          "id": "localized-text",
          "options": {}
        }
      },
      "/descriptor_id": {
        "scope": "class",
        "value_editor": {
          "id": "text",
          "options": {}
        }
      },
      "/code_module_id": {
        "scope": "class",
        "value_editor": {
          "id": "text",
          "options": {}
        }
      },
      "/schema_version": {
        "scope": "class",
        "value_editor": {
          "id": "text",
          "options": {}
        }
      },
      "/implement_notes": {
        "scope": "class",
        "value_editor": {
          "id": "localized-text",
          "options": {}
        }
      }
    }
  }
}
```

The backend validates that `editor_options` is an object; it does not validate each
nested option. The editor validates entered length values, so use the types and choices
above when authoring descriptors. Changes to the class catalogue do not update a saved
`class` copy; current module code still renders existing copies.

#### 5.2.3 String value editor

**Approved by the user on 2026-11-04.** `string-editor` handles a single string, a
multilingual string, or a string selected from a list. It has its own class and editor ID;
the existing `text-editor` and `localized-text-editor` and their saved class copies keep
their existing behavior.

Show **label + value + …**. The ellipsis opens a keyboard- and touch-operable menu:
**Single / 单一文本**, **Multilingual / 多语言**, and **List / 列表**. The selected
element's Properties panel also has an ellipsis menu with those choices and
**Validators / 验证器**. The Properties menu sets the configured initial mode; the
runtime menu changes the value being edited. Single shows a one-line text field.
Multilingual shows one field per configured language, labelled by
language, with English and Chinese by default. List shows a dropdown of author-defined
string values. The page author defines the list in the Properties panel; the person using
the page selects a value. The menu changes the value's representation, so it is disabled
in read-only mode; the displayed value remains selectable.

Selecting Validators opens and scrolls to the existing Validators group in Properties.
It shows the element's current validators in order and a **+** button with the accessible
name **Add validator / 添加验证器**. The button opens
the available validator classes; choosing one adds an instance. The panel also allows
reordering and removing instances and editing their constraints and messages, using the
existing validator property editor. An empty list is explicitly shown. Opening the group
does not change the current Single, Multilingual or List mode. These are authoring controls:
they edit the element's existing `validators` array, not the bound string value. On a
running page the Validators item is unavailable because page users do not edit the page
descriptor. If validator classes cannot be loaded, the editor reports the loading error;
existing validator instances remain in the descriptor.

The following options are supported under `E.editor_options` for page elements and under
`value_editor.options` for Properties-panel definitions. In all cases the class-fixed
value wins over an instance value, then the class default; the page binding mode still
applies. The surrounding element attributes and validation follow §§3–4 and §9.

| Path within options | Type and default | Behavior |
| --- | --- | --- |
| `mode` | `single`, `multilingual`, `list`; `single` | Initial mode when the value does not establish one. The menu changes the current mode. |
| `languages` | Nonempty array of distinct language tags; `["en", "zh-cn"]` | Fields shown in multilingual mode. Existing language keys outside this list remain intact. |
| `emptyAsNull` | Boolean; `true` | In single or list mode an empty selection/edit writes `null` when true and `""` when false. In multilingual mode it controls each emptied language entry; other language entries remain unchanged. |
| `choices` | Array of distinct strings; `[]` | The options for List mode, in author-defined order. An unset value displays a Select placeholder. A stored string absent from the choices stays visible. An empty string choice follows `emptyAsNull`. |
| `commitOnBlur` | Boolean; `false` | Apply valid text edits on blur when true; otherwise apply while typing. List selections apply immediately. |

Single and List store a JSON string or `null`; Multilingual stores a language-keyed
object such as `{"en":"Hello","zh-cn":"你好"}`, with each entry a string or `null`.
Spaces and Unicode are preserved. Switching Single to Multilingual places the current
string in the current page language if configured, otherwise the first configured language;
other fields start empty. Switching Multilingual to Single or List uses the current page
language, falling back to the first configured language with a string value. Switching
between Single and List keeps the current string, including one absent from `choices`;
the dropdown displays that value until the user chooses another. Switching modes applies
the resulting value; it does not rewrite data merely because the control mounted.
Switching away from Multilingual prompts for confirmation when it would discard nonempty
translations and displays the resulting value. Cancelling preserves the mode and all values.

List choices are configured as data, not executable code. The Properties panel exposes
Mode, Languages, Empty as null, Choices and Commit on blur in the Editor group; it shows
Languages for Multilingual and Choices for List while retaining hidden settings. Values
must be strings, language tags and choices must be unique, and invalid supported options
produce descriptor errors for this editor. Unsupported class attributes remain
warnings and forbidden overrides remain errors. The class's `label`, `binding_mode` and
`width` defaults remain Text / 文本, `read-write` and `elastic`; `data_binding` is
optional because it is page-specific. The host provides the accessible label and errors;
all interface text is English and Chinese. Invalid edits remain available for correction,
and existing validators apply before save. Validators currently receive the complete bound
value: in Multilingual mode this is an object, so primitive string validators reject it;
per-language validator execution requires a separate design. No password masking or multiline input is proposed.

**Design assumption:** List choices are configured by the page author, not
edited by the page's end user. The default `emptyAsNull: true` preserves the existing text editor's
empty-to-unset behavior; authors can select `false` to store empty strings.

The editor is `StringValueEditor.svelte`, with conversion rules in `string-value.ts`.
Migration `20261104000003_wpi_string_editor.sql` creates the class and an active version 2;
the database record was read back with its defaults. Frontend and backend tests pass, and
the browser harness exercises value conversion, list choice, confirmation and adding a
validator. A signed-in WPI Editor session has not been exercised. The authoring Validators
menu opens the existing Properties group; it is separate from the runtime value menu.

The Properties panel edits every value-editor element's `label` with this editor (§9). A
class's `value_editor` setting overrides the code default, so migration
`20261104000004_wpi_value_editor_label_string_editor.sql` gives each value-editor class a
new version whose `label.value_editor` is `string-editor`, multilingual, with `en` and
`zh-cn`. An element placed before that migration keeps the localized-text editor in its
class copy until it is placed again.

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
| `editor` is not one of the 30 IDs (a draft) or of the 25 drawn ones (active class, page) | Class save, page save and run | Error at `/editor` |
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
| Editor | `editor_options.displayType` | switch | Length editor only; defaults to off. |
| Editor | `editor_options.defaultValue` | length | Length editor only; edits the default inside `editor_options`, preserving its other options. The type list offers the class default when one exists. |
| Editor | `editor_options` | json | The editor's options |
| Validators | `validators` | validator-list | The element's validator instances; each then has a group of its constraints ([validator-primitive.md](validator-primitive.md) §7) |
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
