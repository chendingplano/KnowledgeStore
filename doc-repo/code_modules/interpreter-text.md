# Code module: `text`

**Code module ID:** `text` \
**Classes using it:** `text`; other paragraph classes may reuse this module \
**Implementation status:** baseline implemented; expanded contract below proposed \
**Design revision:** R1, 2026-10-30 — **Awaiting human design review** \
**Approval:** none recorded \
**Catalogue identity:** existing `kb.code_modules` row `text`, type `element`, seeded active
with `module_doc: text.md`. The canonical document is `interpreter-text.md`; correcting
the catalogue filename is pending implementation, not a database change made here. \
**Frontend:** `ChenWeb/web/src/lib/wpi/elements/TextElement.svelte`, registered in `elements/index.ts` \
**Backend:** `codeModules["text"]`, `element()` and `elementComplete()` in `ChenWeb/server/api/wpi/validate.go` \
**Part of:** reusable module `20261026-01`, [Web Page Interpreter frontend](../modules/module-web-page-interpreter-frontend.md) \
**Design:** [WPI devdoc](../devdocs/202610/2026102601-devdoc-web-page-interpreter.md),
§3.5 Elements and code modules, §3.6 Lists, §3.7 Layout, §3.8 Binding, §5 Actions,
§7 Validation; [input reference](interpreter-input.md); [future Page Styles](interpreter-page-styles.md).

## Purpose and boundary

Display one selectable paragraph: instructions written in a descriptor, or a value read
from the current page instance's input doc. Bound text follows changes made by other
elements and actions. It never edits the doc, marks it dirty, retrieves records or saves.
For example, a customer summary can display `$input_doc.name` beside editable fields;
instructions can use the proposed English/Chinese static text map.

This is a primitive text element with no separate caption, placeholder, icon, tooltip,
children, validation rules, action triggers or data operations. Use separate elements for
links, buttons, labelled inputs, lists, rich text and semantic headings. Large or bold
text remains a paragraph. HTML, Markdown, expressions and callbacks are not interpreted.

## Current implementation versus R1

| Capability | Implemented baseline | R1 proposal |
| --- | --- | --- |
| Static content | `text` accepts a string, including an empty string | Also accept a localized language map. |
| Bound content | `data_binding`; null/missing shows nothing; other values use JavaScript `String(value)` | Preserve conversion and read-only behavior. |
| Appearance | `<p class="py-1 text-sm break-words">`; inherited font and foreground | Configurable typography, foreground, background and padding. |
| Whitespace | HTML whitespace collapsing and long-word wrapping | Add optional preservation of line breaks/spaces; retain `normal` default. |
| Dimensions | Layouter handles `width`, `height`, `min_width`, `max_width` | Retain these attributes; define accessible overflow behavior. |
| Properties | Generic class-defined properties | Localized groups and typed controls below. |

Only string `text`, `data_binding` and the four size attributes are supported today.
Proposed attributes need renderer, types, validator and editor work after approval.
A localized `text` object currently fails the string-only check; it is not a warning.
Page Styles remains future work: `page_style` is accepted and ignored today. Its proposed
16px common font and preserved-line-break defaults do not describe this renderer.

## Descriptor rules and precedence

A class has its own `descriptor_id`, `schema_version: "0.4"`, and `code_module_id: "text"`.
An instance lives at `$.panels.<pane_id>.elem_list[i]`, names its class in `element`, and
holds the complete class row in `class`. `element` must equal `class.descriptor_id`.
A page cannot invent a class inline: example copies represent separately registered
classes. Runtime instance IDs are generated, never stored as instance attributes.

In the tables, `E` means that instance location: `E.text` is flat; its definition is
`E.class.text`, or `$.text` in a standalone class. Properties groups are presentation
only and do not add nested JSON objects.

Each definition includes author-facing `help_tip`, optional `default_value`, and optional
`instance_modifiable`. New help tips provide English and Chinese. Omitted `default_value`
means optional with no class default; null means every instance must supply a value before
running. A non-null default supplies an omitted instance value. `instance_modifiable: false`
requires a non-null default and forbids any instance override, even an equal one. Omitted
or true permits overrides. Definition null is a requiredness marker, not nullable content.
Instance null is invalid for every attribute here; `text: ""` is valid empty static content.

For valid descriptors, resolve fixed values, otherwise instance values, otherwise non-null
saved-copy defaults, otherwise the module fallback below. An attempted fixed override is
an error; applying fixed values last in the merge does not authorize it. Theme inheritance
supplies properties the module leaves inherited. There is no Page Style layer in R1.

Instances may set only attributes their saved class copy names, plus the common sizes.
Later class edits affect newly placed instances only. Old copies keep their defaults and
fixed values, and new code must preserve their small-paragraph appearance and normal
whitespace when new attributes are absent. Configuring new attributes on old instances
requires an explicit class-copy update through the supported authoring workflow; never
silently reread the latest stored class.

`binding_mode` is unsupported by this renderer. Page-level mode is inherited only by
classes declaring it; it cannot make text editable. An older/custom copy declaring
`read-write` still cannot make this renderer write. Unsupported class attributes remain
visible warnings, not supported options.

## Attribute contract

### Content and binding

| Exact instance path | Type/allowed values | Default/absence, validation and behavior |
| --- | --- | --- |
| `E.text` | Currently string; proposed string or language map | No module default. Exactly one resolved source. Plain strings include `""` and are identical in every locale. Proposed maps require nonempty string `en`, valid WPI locale keys and nonempty string translations; new authored content includes `en` and `zh-cn`. |
| `E.data_binding` | String `$input_doc.<segment>[.<segment>...]` | No module default. Exactly one resolved source. Read current page instance data only. Segments match `[A-Za-z_][A-Za-z0-9_]*`; reject `__proto__`, `constructor`, `prototype`, empty segments, bracket/index syntax and other roots. |

Source exclusivity applies after merging. A class default `text` plus instance
`data_binding` is invalid; null cannot remove the default. For a general class, declare
both sources optional without defaults. For a specialized class, require one source using
`default_value: null` and omit the other definition. Never require both.

Proposed localization selects the current locale, then `en`, using the existing WPI text
fallback. Locale changes update static maps without remounting or changing the doc.
Bound objects are not language maps; callers supply an appropriately localized string.
Strings are literal: `$input_doc.name` inside `text` is not interpolated.

| Bound data | Display, baseline and R1 |
| --- | --- |
| Missing path or null | Empty string. |
| String | As text, without trimming. |
| Number or boolean | JavaScript string form; `0` and `false` remain visible. |
| Array | JavaScript array string form, e.g. `[1,2]` becomes `1,2`. |
| Object | JavaScript object string form, normally `[object Object]`, not JSON formatting. |

Arrays cannot be traversed by binding paths. A missing, null or non-object intermediate
value yields an empty display. Structured, date and numeric locale formatting and empty
replacement text are deferred; callers should provide display strings. All content is
escaped, including strings containing HTML.

### Typography and surface — proposed

Every attribute here is optional. Omission uses the listed fallback. Empty string and
null are invalid. No arbitrary CSS declarations, URLs or executable content are accepted.

| Exact path | Type and allowed values | Module fallback, meaning and interactions |
| --- | --- | --- |
| `E.font_family` | Nonempty CSS font-family list string | Inherit theme stack. Accept family names/lists only, not declarations, `url()`, `var()` or CSS-wide keywords; missing fonts use browser fallback. |
| `E.font_size` | Positive decimal length string in `px`, `rem`, `em` | `0.875rem`, matching current `text-sm`; reject zero, percentages, numbers and expressions. |
| `E.font_weight` | Integer 100–900 in steps of 100, or string `normal`/`bold` | Inherit surrounding weight. Numeric strings are invalid. Does not change paragraph semantics. |
| `E.font_style` | String `normal`, `italic`, `oblique` | `normal`; arbitrary angles unsupported. |
| `E.line_height` | Finite positive JSON number | Explicit number multiplies font size. If omitted with font size omitted, preserve current `1.25rem` line height; if font size is supplied, use multiplier `1.5`. |
| `E.color` | CSS color string restricted below | Inherit surrounding foreground, including page foreground/theme. |
| `E.background_color` | CSS color string restricted below | `transparent`; applies to the paragraph box including padding. |
| `E.text_align` | String `start`, `center`, `end`, `justify` | `start`; start/end follow writing direction. Aligns text within its box, not the box within the panel. |
| `E.white_space` | String `normal`, `pre-wrap` | `normal` collapses whitespace as today. `pre-wrap` preserves newlines and repeated spaces while wrapping. Both break long unbroken text when necessary. |
| `E.padding` | String with 1–4 nonnegative decimal `px`/`rem` lengths separated by spaces | `0.25rem 0px`, matching `py-1`. CSS shorthand order: all; vertical/horizontal; top/horizontal/bottom; top/right/bottom/left. No negative values or expressions. |

Color syntax in R1: `#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`, standard named colors
(including `transparent`), or comma-separated `rgb(r,g,b)` / `rgba(r,g,b,a)` with integer
channels 0–255 and alpha 0–1. No `auto`, CSS variables, `currentColor`, HSL or arbitrary
functions. Client and server must validate the same grammar and ranges; browser acceptance
alone is insufficient. Explicit colors stay literal in both themes; omission is recommended
for theme inheritance. Invalid values are errors, not silently discarded styles.

Borders, radius, shadow, decoration, per-state colors and animation are deferred. No
Page Style integration is implied by these local controls.

### Size and layout — common implemented attributes

| Exact path | Type/allowed values | Absence and behavior |
| --- | --- | --- |
| `E.width` | String `auto`, `elastic`, or nonnegative decimal length in `px`, `rem`, `em`, `%` | Unset behaves as `auto` (content width). `elastic` shares available row width. |
| `E.height` | Same size-string grammar | Unset/`auto`: content height. Explicit length sets wrapper height. Current flow layouter accepts but does not stretch `elastic` height. |
| `E.min_width` | Same currently accepted size-string grammar | Unset: no explicit author minimum. Use a concrete length; accepted `auto`/`elastic` tokens are not useful portable constraints. |
| `E.max_width` | Same currently accepted size-string grammar | Unset: no explicit author maximum. Concrete lengths constrain wrapping; percentages relate to containing width. Same constraint-token caveat as minimum. |

Sizes apply to the whole element through the layouter and may be class-fixed. Numeric
JSON values are invalid for text, unlike list-specific numeric sizes. Current validation
checks syntax, not cross-unit minimum/maximum ordering; authors must choose consistent
limits. R1 does not introduce cross-unit conversion or validation.

Proposed box sizing is border-box: padding is included in assigned width/height. Prefer
auto height for prose. No truncation, line clamp, hidden content or maximum line count:
complete text remains readable and copyable. A fixed height too small for its content must
provide element-local scrolling without covering siblings. Explicit widths that cannot
fit require reachable horizontal scrolling. Implementation must distinguish content-height
from explicit-height wrappers. These are proposed overflow guarantees: today's renderer
has no text-specific overflow management.

## States, lifecycle and accessibility

| State/transition | Behavior |
| --- | --- |
| Initial/ready | Resolve the copy and source; render a paragraph in document order. No retrieval, local draft or debounce. |
| Empty | Empty paragraph; padding and assigned dimensions remain. No placeholder or error inferred from missing data. |
| Doc changes | Reactively show the current value; no write or participation in save-field validation. |
| Loading/load failure | Owned by page/action runtime. Text starts no request and does not infer load status from absence. |
| Hidden/cached/show | Follow preserved input doc. Showing text does not refresh; page refresh policy owns retrieval. |
| Unmount | No element-owned request/timer requiring cancellation or a new stale-response protocol. |
| Invalid descriptor | WPI error reporting; no guessed content/style. |
| Disabled/dirty/validating/saving/success | No text-specific flags or states; remains a read-only display while other fields work. |

Use native paragraph semantics and preserve text selection, explicitly restoring it at
the root if the shared shell disables it. Do not add textbox roles, `aria-disabled`, an
automatic live region or tab stops to ordinary prose. Overflow regions must be keyboard
scrollable and show a focus indicator when focused. Reading order follows panel order.
Normal mouse/keyboard/touch selection and copy must work; there are no hover-only details.

Check narrow panes, zoom, Chinese without spaces and long URLs. Normal text needs at
least 4.5:1 contrast against its resolved surface in both themes. Locale changes must not
steal focus. No animation means no special reduced-motion behavior. Persistent caption
or help content belongs in a separate text element, not a hidden tooltip.

## Validation and errors

Preserve WPI save-versus-run behavior: a structurally valid incomplete page may be saved
with neither source or with missing required instance values. Running requires exactly
one source and all required values. Supplying both sources is an error even on save.
Invalid supported values, malformed bindings, unknown instance attributes and fixed-value
overrides are errors. Null/missing bound data is valid and produces an empty display.

Unsupported attributes named by a class remain visible warnings on class save/bundle load
and have no renderer effect. Proposed appearance attributes currently fall in that category;
localized `text` currently fails its supported string type instead. Do not hide unknown
fields or drop them when round-tripping the class copy.

Descriptor errors identify the descriptor/path through WPI's error UI; the backend logs
failures under existing logger conventions. No per-render or value logging is introduced.
Retrieval actions authorize bound data; display attributes grant no permission.

## Properties panel — proposed

Groups are presentation only; instance JSON stays flat. Localize labels/help through
Paraglide in English and Chinese. Show available saved-copy attributes and common sizes,
not options absent from that copy. Enum controls store the exact tokens above.

| Order / group EN / 中文 | Member paths in order; labels EN / 中文 | Controls and help EN / 中文 |
| --- | --- | --- |
| 1. Content / 内容 | `text` Text / 文本; `data_binding` Data binding / 数据绑定 | Bilingual text editor and path field. “Set text or a binding, never both.” / “文本和数据绑定只能设置其一。” |
| 2. Typography / 字体 | `font_family` Font family / 字体族; `font_size` Size / 字号; `font_weight` Weight / 字重; `font_style` Style / 字体样式; `line_height` Line height / 行高 | Family/length fields, choices, positive number. “Leave unset for module or inherited defaults.” / “留空以使用模块默认值或继承值。” |
| 3. Appearance / 外观 | `color` Text color / 文字颜色; `background_color` Background / 背景颜色 | Color controls with literal entry/unset. “Check readability in both themes.” / “请检查两种主题下的可读性。” |
| 4. Text layout / 文本布局 | `text_align` Alignment / 对齐方式; `white_space` Whitespace / 空白处理; `padding` Padding / 内边距 | Choices and spacing field. “pre-wrap preserves line breaks.” / “pre-wrap 保留换行。” |
| 5. Size / 尺寸 | `width` Width / 宽度; `height` Height / 高度; `min_width` Minimum width / 最小宽度; `max_width` Maximum width / 最大宽度 | Size fields. “Sizes apply to the whole element; prefer auto height.” / “尺寸作用于整个元素；建议使用自动高度。” |

Unsupported class attributes remain under **Other / 其他** with warnings. Show fixed values
read-only with **Fixed by class / 类固定值** and their author help. For editable values,
reset removes the override and restores the saved-copy default or module fallback. A required
attribute without a concrete default then becomes incomplete. Clearing an optional override
removes its key, not null or an empty string; static text needs an explicit empty-string
choice. Indicate override, class default or module fallback as the displayed value's source.

A static/bound source selector may be editor context but adds no `source_mode` attribute.
Switching must explicitly remove the old instance source, never erase it silently. If a
class default or fixed source prevents switching, explain why and require a suitable class
copy. Hiding a source control never bypasses exclusivity or deletes its value automatically.

## Examples

### Complete minimal class — current format

Both sources are optional in this class, but each runnable instance needs exactly one.
This illustrates the existing identity, not a registration performed by this document.

```json
{
  "descriptor_id": "text",
  "schema_version": "0.4",
  "code_module_id": "text",
  "description": { "en": "Static or bound paragraph", "zh-cn": "静态或绑定段落" },
  "text": {
    "help_tip": { "en": "Set text or a binding.", "zh-cn": "设置文本或数据绑定。" }
  },
  "data_binding": {
    "help_tip": { "en": "Read an input doc attribute.", "zh-cn": "读取输入文档属性。" }
  }
}
```

### Complete page and full copies — current format

Assumes separately registered layout/text classes; this is a page, not an app bundle.
Changing `customer.name` updates the paragraph without a text action. Both languages
appear in representative data; the baseline renderer does not translate that string.

```json
{
  "descriptor_id": "text-example",
  "schema_version": "0.5",
  "page_name": { "en": "Customer summary", "zh-cn": "客户摘要" },
  "input": { "customer": { "name": "Example customer / 示例客户" } },
  "page_layouter": {
    "layouter": "single-pane",
    "class": {
      "descriptor_id": "single-pane",
      "schema_version": "0.5",
      "code_module_id": "page-layouter",
      "description": { "en": "One pane", "zh-cn": "单窗格" },
      "root": { "pane_id": "main" }
    }
  },
  "panels": {
    "main": {
      "elem_layouter": {
        "layouter": "flow-layouter",
        "class": {
          "descriptor_id": "flow-layouter",
          "schema_version": "0.5",
          "code_module_id": "flow-layouter",
          "description": { "en": "Wrapping flow", "zh-cn": "自动换行布局" },
          "config": {}
        }
      },
      "elem_list": [
        {
          "element": "text",
          "class": {
            "descriptor_id": "text",
            "schema_version": "0.4",
            "code_module_id": "text",
            "description": { "en": "Static or bound paragraph", "zh-cn": "静态或绑定段落" },
            "text": {
              "help_tip": { "en": "Set text or a binding.", "zh-cn": "设置文本或数据绑定。" }
            },
            "data_binding": {
              "help_tip": { "en": "Read an input doc attribute.", "zh-cn": "读取输入文档属性。" }
            }
          },
          "data_binding": "$input_doc.customer.name",
          "width": "elastic",
          "max_width": "640px"
        }
      ]
    }
  }
}
```

### Complete configured class and instance — proposed R1

These JSON objects are complete but **not runnable by the current renderer/validator**.
After implementation, register this proposed class and place its instance in a page
panel's `elem_list`. The static-only class requires text and fixes whitespace handling.
Its full class copy is preserved in the instance; no fixed override is supplied.

```json
{
  "descriptor_id": "text-instructions",
  "schema_version": "0.4",
  "code_module_id": "text",
  "description": { "en": "Multiline instructions", "zh-cn": "多行说明" },
  "text": {
    "help_tip": { "en": "Supply English and Chinese instructions.", "zh-cn": "填写英文和中文说明。" },
    "default_value": null
  },
  "font_size": {
    "help_tip": { "en": "Paragraph font size.", "zh-cn": "段落字号。" },
    "default_value": "1rem"
  },
  "white_space": {
    "help_tip": { "en": "Preserve authored line breaks.", "zh-cn": "保留编写的换行。" },
    "default_value": "pre-wrap",
    "instance_modifiable": false
  }
}
```

```json
{
  "element": "text-instructions",
  "class": {
    "descriptor_id": "text-instructions",
    "schema_version": "0.4",
    "code_module_id": "text",
    "description": { "en": "Multiline instructions", "zh-cn": "多行说明" },
    "text": {
      "help_tip": { "en": "Supply English and Chinese instructions.", "zh-cn": "填写英文和中文说明。" },
      "default_value": null
    },
    "font_size": {
      "help_tip": { "en": "Paragraph font size.", "zh-cn": "段落字号。" },
      "default_value": "1rem"
    },
    "white_space": {
      "help_tip": { "en": "Preserve authored line breaks.", "zh-cn": "保留编写的换行。" },
      "default_value": "pre-wrap",
      "instance_modifiable": false
    }
  },
  "text": {
    "en": "Review the customer details.\nSave after making changes.",
    "zh-cn": "请核对客户信息。\n修改后请保存。"
  },
  "width": "elastic",
  "max_width": "640px"
}
```

No action example applies: text has no action-valued attributes. A future trigger must
use page-written WPI action instances without concrete defaults or class-fixed actions;
embedded executable callbacks remain prohibited.

## Review record

R1 completes source/default/override rules and proposes bilingual static text,
typography/surface controls, whitespace handling, accessible overflow and Properties
groups. It preserves binding conversion and old class copies. No human feedback or
approval has been recorded.

Assumptions for human review:

1. Keep this a paragraph module; semantic headings, links and rich text belong elsewhere.
2. Preserve normal whitespace and small-font defaults for old copies; opt into line-break
   preservation rather than changing saved pages globally.
3. Keep the first extension small: no formatter, truncation, tooltip, actions, border or
   animation. Callers prepare display strings for structured values.
4. Extend `text` to the established locale-map format while retaining plain strings.

Approval must identify R1 or a subsequent revision and its contract. Material changes
return to review. Automated verification cannot replace human approval.

## Implementation and verification

Read-only inspection on 2026-10-30 confirmed the baseline in `TextElement.svelte`,
`elements/index.ts`, `types.ts`, `entries.ts`, `refs.ts`, `layout.ts`, runtime `read()`,
and backend `validate.go`. Migration `20261028000002_create_kb_code_modules.sql` seeds
`text.md`; live catalogue contents were not queried. These are source-inspection findings,
not runtime verification of R1.

Document checks: all four JSON blocks parse, the two example element copies match their
complete class examples, the page-layouter identity matches the registry, relative document
links resolve, and the diff passes whitespace checks. No application code was changed.

After approval:

- Extend the existing renderer/types, using the reactive locale bridge and existing
  locale fallback. Preserve bound-object conversion and old-copy defaults.
- Extend backend supported-attribute/value validation and localized Properties controls;
  preserve source exclusivity, incomplete saves, fixed-value checks and warnings.
- Update the existing module row via a project goose data migration, correcting
  `module_doc` to `interpreter-text.md`. Seed an updated text class without rewriting saved
  page copies; do not duplicate module identities or activate unimplemented classes.
- Update the existing parent reusable-module record/document `20261026-01`, affected WPI
  OpenSpec requirements and devdoc capability notes.

Verify both/neither source on save/run, defaults/overrides/fixed values, invalid proposed
values/maps, old copies, null/missing/zero/false/array/object data, binding rejection,
escaped HTML, live locale/doc updates, whitespace modes, selectable text under the shared
shell, long URLs/Chinese/narrow panes, zoom and both themes, fixed-height scrolling with
keyboard/touch, resets and unsupported warnings. Run project-required checks and browser
interaction checks, reporting authentication blockers and actual outcomes. None of these
R1 runtime checks is claimed to have passed in this document-only revision.

Knowledge changed: the baseline and proposed text extension now have an explicit review
contract. This canonical document changed; runtime, tests, migrations, catalogues and
formal specs did not. Existing module/spec descriptions remain baseline documentation and
must be updated when R1 ships. Future Page Styles text defaults need reconciliation when
integrated. Implementation design, catalogue updates and future rich-text/action contracts
are intentionally deferred until approval or their own feature proposals.
