# Code module: `text`

**Code module ID / existing class ID:** `text` / `text` \
**Implementation:** R2 implemented; text class version 5 active \
**Design revision:** R2, 2026-10-30 — **Approved by the user** \
**Approval:** the user explicitly approved R2 in this conversation on 2026-10-30; the attribute contract is unchanged by implementation \
**Descriptor record:** existing `kb.wpi_descriptors`, `kind: element`, `descriptor_id: text`.
Version 5 is active; version 3 and draft version 4 are retained. No identity or stored
version was replaced in place. Write/read-back evidence appears below. \
**Code module row:** existing `kb.code_modules.text`, type `element`, active with `module_doc: interpreter-text.md`, verified after migration. The canonical
document remains `interpreter-text.md`. \
**Frontend:** `ChenWeb/web/src/lib/wpi/elements/TextElement.svelte`, registered in `elements/index.ts` \
**Backend:** `codeModules["text"]`, `element()` and `elementComplete()` in `ChenWeb/server/api/wpi/validate.go` \
**Part of:** reusable module `20261026-01`, [WPI frontend](../modules/module-web-page-interpreter-frontend.md) \
**References:** [WPI design](../devdocs/202610/2026102601-devdoc-web-page-interpreter.md)
§3.5–3.8, §5 and §7; [input](interpreter-input.md); [future Page Styles](interpreter-page-styles.md).

## Purpose and implementation

Display a selectable paragraph containing literal text or a value from the page instance's
input doc. It follows changes from other fields/actions without writing, dirtying, loading
or saving the doc. R2 adds an optional caption, decorative icon and supplementary tooltip.
These parts belong to one element and share its layout box. The caption is not a form label
for an editable control; the body keeps paragraph semantics.

R2 implements localized static text, caption, icon, tooltip, appearance controls and local
scrolling. Before R2, the renderer accepted only string `text` or `data_binding` plus sizes
and rendered `<p class="py-1 text-sm break-words">`. Old copies keep that small-text/normal-
whitespace appearance. Bound conversion still uses JavaScript `String(value)` (null/missing
becomes empty). Unsupported class attributes remain visible warnings.

Rich text, Markdown, HTML interpretation, semantic headings, links, inline child elements,
data formatting, action triggers, editing and record operations are outside this module.
Large/bold text remains a paragraph. No embedded JavaScript or executable callbacks.
Page Styles remains future work; `page_style` is accepted and ignored today.

## Class copies, defaults and precedence

Classes use format `0.4` and `code_module_id: "text"`. Instances live at
`$.panels.<pane_id>.elem_list[i]`, name the class in `element`, and hold its whole descriptor
in `class`. The class must have been registered separately; copying it into a page does
not create a class. `element` equals `class.descriptor_id`. Runtime IDs are not stored.

Tables use `E` for that instance path. `E.label` is flat; its definition is `E.class.label`
(or `$.label` in a standalone class). Properties groups never create JSON nesting.

Each definition includes bilingual author `help_tip`, optional `default_value` and optional
`instance_modifiable`. Omitted default means optional/no default. A null default requires
an instance value before running; it is not a nullable content value. Non-null defaults
supply omitted values. `instance_modifiable: false` requires a non-null fixed default and
forbids any override, even an equal one. Omitted/true permits overrides. All R2 base-class
attributes are modifiable; specialized classes may fix supported non-action values.

Resolution is fixed class value, otherwise instance value, otherwise saved-copy default,
otherwise the module fallback documented below. A prohibited override is an error, not
an alternative precedence choice. Explicit `inherit` is a supported token that
resolves from the surrounding theme/page or the specified parent below; it is a concrete
class default, not an unspecified value. Page Styles is not a resolution layer.

Every configurable attribute has the same documented and descriptor default except:

- `text` and `data_binding`: page-specific alternatives. No universally meaningful text or
  binding exists; a default text, even empty, would conflict with a bound instance after
  merging. Both are optional in the general class, but exactly one is required to run.
- `label`: optional page-specific caption with no meaningful universal wording. Omit it
  for no caption. The existing shared text validator forbids empty labels, so no empty
  caption default is stored. An instance may supply a nonempty string/language map.
- `max_width`: optional, no default cap; inventing a finite maximum would constrain valid
  pages. The existing size grammar has no `none` token. Omission is deliberately unbounded.

Tooltip and icon default to `""`, meaning absent. Other attributes reject instance null
and empty strings; literal `text: ""` remains valid empty content. Required specialized
classes may use null for a source, but must not require both sources.

Saved pages retain complete class copies and never reread the latest class. Later class
edits affect newly placed instances only. Old copies without new attributes use the same
module fallbacks as the new defaults, preserving small text, normal whitespace and no
caption/icon/tooltip. New attributes cannot be set on an old copy that does not declare
them, except common sizes. Explicitly update the copy through the authoring workflow.

`binding_mode` remains unsupported. Page-level mode only flows into classes declaring it
and cannot make this renderer write, even for custom copies declaring `read-write`.
Unsupported declarations remain warnings.

## Attribute contract

Defaults below are both base-class `default_value` and module fallback, except
explicitly marked omitted. All controls are optional unless a specialized class requires
one. Supported invalid values and fixed overrides are errors.

### Content, caption, icon and tooltip

| Exact path | Type / allowed values | Default and behavior |
| --- | --- | --- |
| `E.text` | String, localized map | Omitted; exactly one source after merging. Empty string is valid. Literal content, no reference interpolation. |
| `E.data_binding` | String `$input_doc.<segment>[.<segment>...]` | Omitted; exactly one source. Segments match `[A-Za-z_][A-Za-z0-9_]*`; reject `__proto__`, `constructor`, `prototype`, empty segments, bracket/index syntax and other roots. |
| `E.label` | Nonempty string or localized map | Omitted: no caption. Page-specific content; independent of body source. |
| `E.help_tip` | String or localized map | `""`: no tooltip trigger/popup. Supplementary runtime help, not the author help at `E.class.<attribute>.help_tip`. |
| `E.icon` | String `""`, `info`, `circle-help`, `circle-check`, `triangle-alert`, `file-text`, `user` | `""`: no icon/space. Explicit finite local Lucide registry, not arbitrary SVG, markup, URLs or remote icon loading. Unknown IDs are errors. |

Localized maps follow the existing WPI locale-key grammar, require nonempty string `en`
and nonempty string translations. New authored maps include `en` and `zh-cn`. Runtime
selects current locale then `en`; a plain string stays the same in all languages. Switching
locale updates caption, static text, tooltip and accessible control names without remounting.
Bound objects are not locale maps; the caller supplies localized display strings.

Exclusivity uses resolved keys: class default `text` plus instance binding is invalid;
instance null cannot remove a default. A general class declares both without defaults.
A static/bound specialized class may require one source and omit the other definition.

| Bound value | Display (existing behavior retained) |
| --- | --- |
| Missing/null | Empty string. |
| String | Literal text without trimming. |
| Number/boolean | JavaScript string form; `0` and `false` remain visible. |
| Array/object | JavaScript string form, e.g. `1,2` / `[object Object]`, not JSON formatting. |

Missing/non-object intermediate values yield empty display; arrays cannot be traversed.
All text is escaped. Empty body does not remove a configured caption/icon/tooltip.
Formatting, empty replacements and locale-aware date/number conversion are deferred.

### Caption and icon layout — implemented R2

Lengths here are nonnegative decimal pixel strings, including `0px`; `icon_size` and
`label_max_width` must be positive. Caption text wraps fully without a line limit or ellipsis, so it needs no separate
truncation tooltip. Caption font family/size/style/color/line height inherit the content
appearance; only caption weight has its own override in this revision.

| Exact path | Type / allowed values | Default and behavior |
| --- | --- | --- |
| `E.label_placement` | `top`, `left`, `right`, `bottom` | `top`; relative to the content row containing icon, paragraph and help control. |
| `E.label_horizontal_gap` | Pixel length string | `8px`; left/right caption gap. |
| `E.label_vertical_gap` | Pixel length string | `4px`; top/bottom caption gap, also used for narrow-layout fallback. |
| `E.label_horizontal_align` | `start`, `center`, `end` | `start`; caption text alignment, follows writing direction. |
| `E.label_vertical_align` | `top`, `center`, `bottom` | `top`; caption box alignment beside the entire content row. |
| `E.label_max_width` | Positive pixel length string | `160px`; additionally limited by available space; full caption wraps without truncation. |
| `E.label_font_weight` | Integer 100–900 by 100, or `normal`/`bold`/`inherit` | `500`; same weight grammar as content. |
| `E.icon_placement` | `start`, `end` | `start`; relative to paragraph text, follows writing direction. |
| `E.icon_size` | Positive pixel length string | `16px`; both dimensions, no layout space when icon absent. |
| `E.icon_gap` | Pixel length string | `8px`; icon-to-paragraph gap. |
| `E.icon_color` | Color syntax below, or `inherit` | `inherit`; follows resolved content foreground. |

For left/right placement use a horizontal caption/content pair; below a 250px element
container width, stack caption above content using vertical gap. Top/bottom remain stacked.
Long content can wrap within each region. Placement changes visual position without changing
accessible reading order: caption, body, help control. Caption uses ordinary text, not an
HTML `<label>` aimed at a non-control; associate the content region with its unique ID.
No caption means no caption box or caption gap. Hidden layout settings retain their values.
The decorative icon is `aria-hidden`, never a focusable button or the sole status cue.

### Typography and surface — implemented R2

| Exact path | Type / allowed values | Default and meaning |
| --- | --- | --- |
| `E.font_family` | `inherit` or nonempty CSS family list | `inherit`: theme/ancestor stack. Lists contain family names, not declarations, URLs, functions or other CSS-wide keywords. |
| `E.font_size` | Positive decimal `px`, `rem`, `em` string | `0.875rem`, preserving `text-sm`. |
| `E.font_weight` | Integer 100–900 by 100, or `normal`, `bold`, `inherit` | `inherit`: ancestor weight. Numeric strings invalid. |
| `E.font_style` | `normal`, `italic`, `oblique` | `normal`; no arbitrary angles. |
| `E.line_height` | `normal` or positive finite JSON number | `normal` is a module token: `1.25rem` at the fallback `0.875rem` font size, otherwise multiplier `1.5`. A numeric value is an explicit font-size multiplier. |
| `E.color` | Restricted color or `inherit` | `inherit`: page/ancestor foreground. |
| `E.background_color` | Restricted color | `transparent`; entire outer box, including padding. |
| `E.text_align` | `start`, `center`, `end`, `justify` | `start`; aligns paragraph text, not the element. |
| `E.white_space` | `normal`, `pre-wrap` | `normal` collapses whitespace; `pre-wrap` preserves spaces/newlines. Both wrap long text. |
| `E.padding` | String of 1–4 nonnegative decimal `px`/`rem` lengths | `0.25rem 0px`, matching `py-1`; CSS shorthand order. |

Restricted colors: hex `#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`, standard named colors
(including `transparent`), or comma-separated `rgb(r,g,b)` / `rgba(r,g,b,a)` with integer
channels 0–255 and alpha 0–1. `inherit` is only valid where explicitly listed. No `auto`,
`var()`, `currentColor`, HSL, expressions or declarations. Client/server must share grammar
and range checks; browser CSS acceptance alone is insufficient. Explicit colors stay literal
in both themes. Border, radius, shadow, decoration, per-state colors and animation are deferred.

### Size and layout — implemented grammar and R2 defaults

| Exact path | Type / accepted values | R2 default and behavior |
| --- | --- | --- |
| `E.width` | String `auto`, `elastic` or nonnegative decimal `px`, `rem`, `em`, `%` length | `auto`: content width. `elastic` shares row space. |
| `E.height` | Same size-string grammar | `auto`: content height. Explicit lengths size the wrapper. Flow currently accepts but does not stretch `elastic` height. |
| `E.min_width` | Same current size grammar | `0px`: no positive author minimum. Prefer concrete lengths; accepted `auto`/`elastic` are not useful portable constraints. |
| `E.max_width` | Same current size grammar | Omitted: no author-imposed cap. No reasonable universal finite maximum or accepted `none` token. |

Sizes apply to the whole element, caption/icon/help included; text does not accept the list
module's numeric JSON pixel sizes. Existing validation checks syntax, not cross-unit bound
ordering; authors choose consistent limits. R2 does not introduce unit conversion.

Border-box sizing includes padding in assigned dimensions. Prefer auto height.
Complete text remains copyable with no clamp/ellipsis. Too-small explicit dimensions require
reachable scrolling inside the element without covering siblings; focusable overflow regions
need a visible focus indicator and keyboard/touch scrolling. The text renderer observes overflow and makes only overflowing regions keyboard focusable;
fixed-height wrappers use their assigned height and scroll locally.

## Tooltip interactions, states and accessibility

A nonempty `help_tip` adds a focusable help button with localized name “More information” /
“更多信息”, associated with the paragraph and tooltip. Empty help produces no button or gap.
The separate decorative `icon` never doubles as this control. Open on help-button focus,
hover, click or touch tap; keep open while pointer/focus is in trigger or popup. Escape or
outside activation closes it without an action or page submission. Escape retains trigger
focus; closing by outside activation respects the user's new focus target. Popup has tooltip
semantics, selectable wrapped text, no interactive children, and stays within the viewport.
Allow hover transfer to copy text; use a 150ms close delay and cancel it on re-entry. Clean
up delay/listeners on unmount. No native `title` as the only tooltip access path.

| State | Contract |
| --- | --- |
| Initial/ready | Resolve current source and defaults; no retrieval or draft state. |
| Empty body | Show empty body plus configured optional parts and padding. No placeholder/error inferred. |
| Doc or locale change | Reactively update content; preserve page state and focus. Open tooltip updates its localized text. |
| Loading/load failure | Page/action runtime owns this; text does not synthesize status from missing data. |
| Hidden/cached/show | Close tooltip on hide; preserve input doc and reopen no popup automatically. Page owns refresh. |
| Unmount | Clear tooltip timer, listeners and portal content; no orphaned popup. |
| Invalid descriptor | WPI error UI, no guessed content/styles. |
| Disabled/dirty/validating/saving/success | No text-specific flags; paragraph remains read-only during other fields' work. |

Preserve text selection at the root even under a shared shell disabling it. Ordinary prose
has no tab stop, textbox role or automatic live region. Tab order includes the help button
and scrollable regions only as needed. Keep caption/body order meaningful for screen readers.
Check 4.5:1 normal-text contrast, both themes, zoom, Chinese, long URLs and narrow panes.
Caption/tooltip text stays available to keyboard and touch users; no hover-only content.
No animation is required. Captions are visible context; tooltip is supplementary help.

## Validation and errors

Preserve incomplete-save behavior: saving may omit both sources or required values; running
requires exactly one source and all required values. Both sources is an error even on save.
Invalid supported values, malformed bindings, unknown instance attributes and fixed overrides
are errors. Missing/null bound data is valid. Unsupported class attributes remain visible
warnings and are preserved when round-tripping. Draft storage does not mean runtime support.

Backend errors use WPI's descriptor/path error contract and existing logger conventions.
No content/value logging is added. Retrieval authorization belongs to backend actions;
caption/icon/tooltip choices grant no permission. No text-specific input validation rules.

## Property editor

The WPI Editor's Properties panel draws this module's property editor at run time from
`ChenWeb/web/src/lib/wpi/properties/text.ts` (OpenSpec `wpi-property-editors`); no Svelte
file is written per module. The table below is the contract that file follows: change the
two together. Groups are presentation only; the instance stays flat. Every editor starts
with a **Placement** group showing the element's pane and its position on the page
(read-only). Labels and group names are in Paraglide. Help tips are the class's `help_tip`
for each attribute; an attribute with a non-empty tip gets an info icon at the upper right
of its value editor. A value fixed by the class is shown read-only, marked fixed; *Reset*
removes the instance's own value. Hidden attributes keep their values. A class attribute
the table does not list appears under **Other** with the common-sense value editor. Value
editors are described in devdoc 2026102701 §1.3.9.

Each group has a one-line hint under its heading. Caption settings are shown only when the
element has a caption, icon settings only when it has an icon, and the horizontal gap and
vertical alignment only for `left` and `right` placement. When neither the instance nor its
class sets a value, the editor shows the module default (`textDefaults`). Values are checked
with `validTextAttribute`; an invalid one is not applied. A width or height above `max_width`
or the panel's maximum element width or row height, and a binding set beside `text`, are shown
as warnings. No `source_mode` is stored.

| Group | Attribute | Value editor | Data and rules |
| --- | --- | --- | --- |
| Content | `text` | localized-text | One text, or English and Chinese; *Use empty text* stores `""` |
| Content | `data_binding` | text | A path under `$input_doc` |
| Content | `label` | localized-text | The caption |
| Content | `help_tip` | localized-text | The tooltip; *No tooltip* stores `""` |
| Caption layout | `label_placement` | value-picker | `top`, `left`, `right`, `bottom` |
| Caption layout | `label_horizontal_gap`, `label_vertical_gap`, `label_max_width` | length | px |
| Caption layout | `label_horizontal_align` | value-picker | `start`, `center`, `end` |
| Caption layout | `label_vertical_align` | value-picker | `top`, `center`, `bottom` |
| Caption layout | `label_font_weight` | value-picker | `inherit`, `normal`, `bold`, `100`–`900`; numbers are stored as numbers |
| Icon | `icon` | value-picker | *None* (stored as `""`) and the icons in `server/api/wpi/text-values.json` |
| Icon | `icon_placement` | value-picker | `start`, `end` |
| Icon | `icon_size`, `icon_gap` | length | px |
| Icon | `icon_color` | color | None or one CSS colour; `inherit` may be typed |
| Typography | `font_family` | text | A CSS font family or `inherit` |
| Typography | `font_size` | length | px, rem or em |
| Typography | `font_weight` | value-picker | `inherit`, `normal`, `bold`, `100`–`900` |
| Typography | `font_style` | value-picker | `normal`, `italic`, `oblique` |
| Typography | `line_height` | json | `normal` or a positive number |
| Appearance and layout | `color`, `background_color` | color | None or one CSS colour |
| Appearance and layout | `text_align` | value-picker | `start`, `center`, `end`, `justify` |
| Appearance and layout | `white_space` | value-picker | `normal`, `pre-wrap` |
| Appearance and layout | `padding` | text | One to four lengths in px or rem |
| Size | `width`, `height`, `min_width`, `max_width` | length | `auto`, `elastic`, or a number in px, rem, em or %; a bare number means px |

## Examples

### Baseline class — currently supported

Complete class JSON with optional alternative sources; this does not create a new identity.

```json
{
  "descriptor_id": "text",
  "schema_version": "0.4",
  "code_module_id": "text",
  "description": {
    "en": "Static or bound paragraph",
    "zh-cn": "静态或绑定段落"
  },
  "text": {
    "help_tip": {
      "en": "Set text or a binding.",
      "zh-cn": "设置文本或数据绑定。"
    }
  },
  "data_binding": {
    "help_tip": {
      "en": "Read an input doc attribute.",
      "zh-cn": "读取输入文档属性。"
    }
  }
}
```

### Complete R2 class — implemented R2, stored as draft

Each definition includes its actual default or a documented exception. Compact formatting
does not omit fields. The active version 5 record carries this descriptor; its attribute definitions match approved R2.

```json
{
  "descriptor_id": "text",
  "schema_version": "0.4",
  "code_module_id": "text",
  "description": {"en": "Static or bound paragraph with optional caption, icon and tooltip", "zh-cn": "支持可选标题、图标和提示的静态或绑定段落"},
  "implement_notes": {"en": "Approved R2: localized read-only paragraph, optional caption/icon/tooltip and configurable appearance.", "zh-cn": "已批准的 R2：本地化只读段落、可选标题/图标/提示及可配置外观。"},
  "text": {"help_tip": {"en": "Literal content; set text or data_binding, not both.", "zh-cn": "静态内容；文本和数据绑定只能设置其一。"}},
  "data_binding": {"help_tip": {"en": "Input doc path; set text or data_binding, not both.", "zh-cn": "输入文档路径；文本和数据绑定只能设置其一。"}},
  "label": {"help_tip": {"en": "Optional caption; omit when no caption is needed.", "zh-cn": "可选标题；无需标题时请省略。"}},
  "help_tip": {"help_tip": {"en": "Optional tooltip; empty means no tooltip.", "zh-cn": "可选提示；空字符串表示不显示提示。"}, "default_value": ""},
  "icon": {"help_tip": {"en": "Decorative icon identifier; empty means no icon.", "zh-cn": "装饰图标标识；空字符串表示不显示图标。"}, "default_value": ""},
  "label_placement": {"help_tip": {"en": "Caption position relative to the content row.", "zh-cn": "标题相对于内容行的位置。"}, "default_value": "top"},
  "label_horizontal_gap": {"help_tip": {"en": "Caption gap for left/right placement.", "zh-cn": "标题位于左右时的间距。"}, "default_value": "8px"},
  "label_vertical_gap": {"help_tip": {"en": "Caption gap for top/bottom placement.", "zh-cn": "标题位于上下时的间距。"}, "default_value": "4px"},
  "label_horizontal_align": {"help_tip": {"en": "Caption text alignment.", "zh-cn": "标题文字对齐方式。"}, "default_value": "start"},
  "label_vertical_align": {"help_tip": {"en": "Caption alignment beside the content row.", "zh-cn": "标题在内容行旁的垂直对齐方式。"}, "default_value": "top"},
  "label_max_width": {"help_tip": {"en": "Maximum caption width; all caption text remains available.", "zh-cn": "标题最大宽度；保留完整标题文字。"}, "default_value": "160px"},
  "label_font_weight": {"help_tip": {"en": "Caption font weight.", "zh-cn": "标题字重。"}, "default_value": 500},
  "icon_placement": {"help_tip": {"en": "Icon position relative to paragraph text.", "zh-cn": "图标相对于段落文字的位置。"}, "default_value": "start"},
  "icon_size": {"help_tip": {"en": "Decorative icon size.", "zh-cn": "装饰图标尺寸。"}, "default_value": "16px"},
  "icon_gap": {"help_tip": {"en": "Gap between icon and paragraph.", "zh-cn": "图标与段落的间距。"}, "default_value": "8px"},
  "icon_color": {"help_tip": {"en": "Icon color; inherit follows content foreground.", "zh-cn": "图标颜色；inherit 跟随内容前景色。"}, "default_value": "inherit"},
  "font_family": {"help_tip": {"en": "Content font family; inherit uses surrounding font.", "zh-cn": "内容字体；inherit 使用周围字体。"}, "default_value": "inherit"},
  "font_size": {"help_tip": {"en": "Content font size.", "zh-cn": "内容字号。"}, "default_value": "0.875rem"},
  "font_weight": {"help_tip": {"en": "Content font weight; inherit uses surrounding weight.", "zh-cn": "内容字重；inherit 使用周围字重。"}, "default_value": "inherit"},
  "font_style": {"help_tip": {"en": "Content font style.", "zh-cn": "内容字体样式。"}, "default_value": "normal"},
  "line_height": {"help_tip": {"en": "Line height; normal preserves module small-text line height.", "zh-cn": "行高；normal 保留模块的小号文本行高。"}, "default_value": "normal"},
  "color": {"help_tip": {"en": "Content foreground; inherit follows page/theme.", "zh-cn": "内容前景色；inherit 跟随页面或主题。"}, "default_value": "inherit"},
  "background_color": {"help_tip": {"en": "Whole element background.", "zh-cn": "整个元素的背景颜色。"}, "default_value": "transparent"},
  "text_align": {"help_tip": {"en": "Paragraph alignment within its box.", "zh-cn": "段落在自身区域中的对齐方式。"}, "default_value": "start"},
  "white_space": {"help_tip": {"en": "Whitespace handling; pre-wrap preserves line breaks.", "zh-cn": "空白处理；pre-wrap 保留换行。"}, "default_value": "normal"},
  "padding": {"help_tip": {"en": "Whole element padding.", "zh-cn": "整个元素的内边距。"}, "default_value": "0.25rem 0px"},
  "width": {"help_tip": {"en": "Whole element width.", "zh-cn": "整个元素的宽度。"}, "default_value": "auto"},
  "height": {"help_tip": {"en": "Whole element height; prefer auto for prose.", "zh-cn": "整个元素的高度；段落建议使用 auto。"}, "default_value": "auto"},
  "min_width": {"help_tip": {"en": "Minimum whole element width.", "zh-cn": "整个元素的最小宽度。"}, "default_value": "0px"},
  "max_width": {"help_tip": {"en": "Optional maximum width; omit for no author-imposed cap.", "zh-cn": "可选最大宽度；省略表示不设置作者指定的上限。"}}
}
```

### Complete page with full class copy

The page and layout copies use format `0.5`. Its element copy equals the R2 class above;
layout classes must already be registered. This is a complete page, not an app bundle.
The configured static source is bilingual. For a bound instance, remove its `text` and
set `data_binding: "$input_doc.customer.name"`; the same copy supports both alternatives.
The page uses the implemented R2 renderer/validator and the registered layout classes.

```json
{
  "descriptor_id": "text-r2-example",
  "schema_version": "0.5",
  "page_name": {
    "en": "Customer summary",
    "zh-cn": "客户摘要"
  },
  "input": {
    "customer": {
      "name": "Example customer / 示例客户"
    }
  },
  "page_layouter": {
    "layouter": "single-pane",
    "class": {
      "descriptor_id": "single-pane",
      "schema_version": "0.5",
      "code_module_id": "page-layouter",
      "description": {
        "en": "One pane",
        "zh-cn": "单窗格"
      },
      "root": {
        "pane_id": "main"
      }
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
          "description": {
            "en": "Wrapping flow",
            "zh-cn": "自动换行布局"
          },
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
            "description": {
              "en": "Static or bound paragraph with optional caption, icon and tooltip",
              "zh-cn": "支持可选标题、图标和提示的静态或绑定段落"
            },
            "implement_notes": {
              "en": "Approved R2: localized read-only paragraph, optional caption/icon/tooltip and configurable appearance.",
              "zh-cn": "已批准的 R2：本地化只读段落、可选标题/图标/提示及可配置外观。"
            },
            "text": {
              "help_tip": {
                "en": "Literal content; set text or data_binding, not both.",
                "zh-cn": "静态内容；文本和数据绑定只能设置其一。"
              }
            },
            "data_binding": {
              "help_tip": {
                "en": "Input doc path; set text or data_binding, not both.",
                "zh-cn": "输入文档路径；文本和数据绑定只能设置其一。"
              }
            },
            "label": {
              "help_tip": {
                "en": "Optional caption; omit when no caption is needed.",
                "zh-cn": "可选标题；无需标题时请省略。"
              }
            },
            "help_tip": {
              "help_tip": {
                "en": "Optional tooltip; empty means no tooltip.",
                "zh-cn": "可选提示；空字符串表示不显示提示。"
              },
              "default_value": ""
            },
            "icon": {
              "help_tip": {
                "en": "Decorative icon identifier; empty means no icon.",
                "zh-cn": "装饰图标标识；空字符串表示不显示图标。"
              },
              "default_value": ""
            },
            "label_placement": {
              "help_tip": {
                "en": "Caption position relative to the content row.",
                "zh-cn": "标题相对于内容行的位置。"
              },
              "default_value": "top"
            },
            "label_horizontal_gap": {
              "help_tip": {
                "en": "Caption gap for left/right placement.",
                "zh-cn": "标题位于左右时的间距。"
              },
              "default_value": "8px"
            },
            "label_vertical_gap": {
              "help_tip": {
                "en": "Caption gap for top/bottom placement.",
                "zh-cn": "标题位于上下时的间距。"
              },
              "default_value": "4px"
            },
            "label_horizontal_align": {
              "help_tip": {
                "en": "Caption text alignment.",
                "zh-cn": "标题文字对齐方式。"
              },
              "default_value": "start"
            },
            "label_vertical_align": {
              "help_tip": {
                "en": "Caption alignment beside the content row.",
                "zh-cn": "标题在内容行旁的垂直对齐方式。"
              },
              "default_value": "top"
            },
            "label_max_width": {
              "help_tip": {
                "en": "Maximum caption width; all caption text remains available.",
                "zh-cn": "标题最大宽度；保留完整标题文字。"
              },
              "default_value": "160px"
            },
            "label_font_weight": {
              "help_tip": {
                "en": "Caption font weight.",
                "zh-cn": "标题字重。"
              },
              "default_value": 500
            },
            "icon_placement": {
              "help_tip": {
                "en": "Icon position relative to paragraph text.",
                "zh-cn": "图标相对于段落文字的位置。"
              },
              "default_value": "start"
            },
            "icon_size": {
              "help_tip": {
                "en": "Decorative icon size.",
                "zh-cn": "装饰图标尺寸。"
              },
              "default_value": "16px"
            },
            "icon_gap": {
              "help_tip": {
                "en": "Gap between icon and paragraph.",
                "zh-cn": "图标与段落的间距。"
              },
              "default_value": "8px"
            },
            "icon_color": {
              "help_tip": {
                "en": "Icon color; inherit follows content foreground.",
                "zh-cn": "图标颜色；inherit 跟随内容前景色。"
              },
              "default_value": "inherit"
            },
            "font_family": {
              "help_tip": {
                "en": "Content font family; inherit uses surrounding font.",
                "zh-cn": "内容字体；inherit 使用周围字体。"
              },
              "default_value": "inherit"
            },
            "font_size": {
              "help_tip": {
                "en": "Content font size.",
                "zh-cn": "内容字号。"
              },
              "default_value": "0.875rem"
            },
            "font_weight": {
              "help_tip": {
                "en": "Content font weight; inherit uses surrounding weight.",
                "zh-cn": "内容字重；inherit 使用周围字重。"
              },
              "default_value": "inherit"
            },
            "font_style": {
              "help_tip": {
                "en": "Content font style.",
                "zh-cn": "内容字体样式。"
              },
              "default_value": "normal"
            },
            "line_height": {
              "help_tip": {
                "en": "Line height; normal preserves module small-text line height.",
                "zh-cn": "行高；normal 保留模块的小号文本行高。"
              },
              "default_value": "normal"
            },
            "color": {
              "help_tip": {
                "en": "Content foreground; inherit follows page/theme.",
                "zh-cn": "内容前景色；inherit 跟随页面或主题。"
              },
              "default_value": "inherit"
            },
            "background_color": {
              "help_tip": {
                "en": "Whole element background.",
                "zh-cn": "整个元素的背景颜色。"
              },
              "default_value": "transparent"
            },
            "text_align": {
              "help_tip": {
                "en": "Paragraph alignment within its box.",
                "zh-cn": "段落在自身区域中的对齐方式。"
              },
              "default_value": "start"
            },
            "white_space": {
              "help_tip": {
                "en": "Whitespace handling; pre-wrap preserves line breaks.",
                "zh-cn": "空白处理；pre-wrap 保留换行。"
              },
              "default_value": "normal"
            },
            "padding": {
              "help_tip": {
                "en": "Whole element padding.",
                "zh-cn": "整个元素的内边距。"
              },
              "default_value": "0.25rem 0px"
            },
            "width": {
              "help_tip": {
                "en": "Whole element width.",
                "zh-cn": "整个元素的宽度。"
              },
              "default_value": "auto"
            },
            "height": {
              "help_tip": {
                "en": "Whole element height; prefer auto for prose.",
                "zh-cn": "整个元素的高度；段落建议使用 auto。"
              },
              "default_value": "auto"
            },
            "min_width": {
              "help_tip": {
                "en": "Minimum whole element width.",
                "zh-cn": "整个元素的最小宽度。"
              },
              "default_value": "0px"
            },
            "max_width": {
              "help_tip": {
                "en": "Optional maximum width; omit for no author-imposed cap.",
                "zh-cn": "可选最大宽度；省略表示不设置作者指定的上限。"
              }
            }
          },
          "text": {
            "en": "Review the customer details.\nSave after making changes.",
            "zh-cn": "请核对客户信息。\n修改后请保存。"
          },
          "label": {
            "en": "Instructions",
            "zh-cn": "操作说明"
          },
          "help_tip": {
            "en": "Changes are saved with the page save action.",
            "zh-cn": "更改通过页面保存操作保存。"
          },
          "icon": "info",
          "white_space": "pre-wrap",
          "width": "elastic",
          "max_width": "640px"
        }
      ]
    }
  }
}
```

No action example applies: this module has no action-valued attributes. Future actions
must be written in pages, with no concrete class default or class-fixed action.

## Review record

R1 proposed paragraph configuration. On 2026-10-30 the user requested updating the existing
record, reasonable defaults, and optional caption/icon/tooltip. R2 incorporated these changes
and the user explicitly replied **Approved**. Approval covers the R2 attribute/default and
interaction contract above. The implementation and catalogue facts added here do not change
that contract. Later material contract changes still require human review.

## Registration, implementation and verification

The existing `text` identity remains in both catalogues. Goose migration
`ChenWeb/project_migrations/20261030000004_wpi_text_r2_draft.sql` saved draft version 4.
After approval and implementation, migration
`ChenWeb/project_migrations/20261030000006_wpi_text_r2_active.sql` saved **version 5, active**,
schema **0.4**, module **text**. Read-back on 2026-10-30 matched all 30 definitions,
including the 26 defaults and four justified exceptions. Version 3 and draft 4 remain
unchanged. The code-module document path reads `interpreter-text.md`; no module identity or
saved page copy was replaced. Both migration Up paths were tested for idempotence and
rollback in transactions. The active class passes the actual backend descriptor validator.

Implemented files:

- Renderer: `ChenWeb/web/src/lib/wpi/elements/TextElement.svelte`, still registered under
  `text` in `elements/index.ts`; public interface remains `{ instanceId, element }`.
- Descriptor types and pure client validation/defaults: `types.ts`, `text-attributes.ts`
  and `text-attributes.test.ts` under `ChenWeb/web/src/lib/wpi/`.
- Property editor: the definition `web/src/lib/wpi/properties/text.ts`, with labels from
  `web/src/lib/components/shared-ui/canvas/text-property-labels.ts`.
- Backend: `text_attributes.go`, `text_attributes_test.go`, shared `text-values.json` and
  `text-attribute-cases.json`, plus `validate.go` registration under `server/api/wpi/`.
- Reproducible real-component browser checks: `ChenWeb/web/tests/wpi-text/test_text.py`
  and its local Vite harness. Run `python3 web/tests/wpi-text/test_text.py --start-server`
  from ChenWeb, with Python Playwright/Chromium and project Bun dependencies installed.
- English/Chinese authoring and help-control messages: `ChenWeb/web/messages/en.json`
  and `zh-cn.json`. The existing reactive locale bridge is reused.

Tooltip rendering uses a native manual popover in the top layer, constrained to the viewport.
Resize observers update popup position after translated text changes and close it when its
cached ancestor becomes hidden. Cleanup removes popup/listeners/timers on unmount. An
oversized popup is itself keyboard scrollable. The outer text region uses a resize observer
for the 250px caption fallback without collapsing the intrinsic width of auto-sized elements.

Verification evidence:

- Full `go test ./server/api/wpi` passes, including invalid styles/locales/icons, shared
  client/server vectors, default-only instances, source conflicts, incomplete saves, fixed
  overrides and old-copy compatibility. Go vet is included in final checks.
- Bun WPI and element-attribute tests pass, including the 26-default comparison with the
  reviewed descriptor and unchanged string conversion. Final totals are recorded in the
  completion report rather than tied to concurrent unrelated test additions.
- `bun run check` passes type/i18n validation. Existing unrelated accessibility warnings
  remain outside this change.
- Headless Chromium checks the real renderer, flow layouter and text Properties component:
  live binding/locale changes, escaped HTML, all caption orientations/narrow fallback,
  decorative icons, keyboard/hover/hover-transfer/touch tooltip access, Escape/outside close,
  hidden-page and unmount cleanup, selectable content, fixed-height keyboard scrolling,
  typed invalid/reset/fixed/unsupported fields, bilingual editing and both themes.
- An independent read-only review found the tooltip-clear and translation-resize cases;
  both were fixed and included in browser verification. No human approval was substituted
  by that review.

A signed-in editor session was not used: authenticated editor/API integration remains
unverified by these browser checks. The harness exercises the shipped components without
changing authentication. Native popover/ResizeObserver support is required in target browsers;
Chromium was exercised. Rich text, formatting, actions and Page Styles remain outside R2.

Knowledge changed: this canonical contract now describes the shipped renderer and version 5.
The parent frontend/backend module documents and catalogue rows are updated to 3.2.0, keeping
identities `20261026-01` / `20261026-02` and their existing `under-dev` module status. Formal
requirements are in OpenSpec change `wpi-text-r2`; WPI design notes now distinguish implemented
local text controls from future Page Styles. Detailed future rich-text/action/style contracts
remain intentionally undocumented here. No known text-specific document remains stale.
