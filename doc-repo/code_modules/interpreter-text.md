# Code module: `text`

**Code module ID / existing class ID:** `text` / `text` \
**Implementation:** baseline implemented; R2 extension proposed \
**Design revision:** R2, 2026-10-30 — **Awaiting human design review** \
**Approval:** none; R2 incorporates the user's three R1 revisions \
**Descriptor record:** existing `kb.wpi_descriptors`, `kind: element`, `descriptor_id: text`.
Version 3 is active; the explicitly requested R2 update is a new draft version, not a new
identity or an in-place replacement. Write/read-back evidence appears below. \
**Code module row:** existing `kb.code_modules.text`, type `element`, seeded active with
`module_doc: text.md`. Canonical document is `interpreter-text.md`; that catalogue filename
correction remains pending implementation. \
**Frontend:** `ChenWeb/web/src/lib/wpi/elements/TextElement.svelte`, registered in `elements/index.ts` \
**Backend:** `codeModules["text"]`, `element()` and `elementComplete()` in `ChenWeb/server/api/wpi/validate.go` \
**Part of:** reusable module `20261026-01`, [WPI frontend](../modules/module-web-page-interpreter-frontend.md) \
**References:** [WPI design](../devdocs/202610/2026102601-devdoc-web-page-interpreter.md)
§3.5–3.8, §5 and §7; [input](interpreter-input.md); [future Page Styles](interpreter-page-styles.md).

## Purpose and implemented boundary

Display a selectable paragraph containing literal text or a value from the page instance's
input doc. It follows changes from other fields/actions without writing, dirtying, loading
or saving the doc. R2 adds an optional caption, decorative icon and supplementary tooltip.
These parts belong to one element and share its layout box. The caption is not a form label
for an editable control; the body keeps paragraph semantics.

The implemented renderer only accepts string `text` or `data_binding`, plus common sizes.
It renders `<p class="py-1 text-sm break-words">`, collapses whitespace, and converts bound
values through JavaScript `String(value)` (null/missing becomes empty). Localization,
caption, icon, tooltip, appearance controls and element-local overflow below are proposed.
Unsupported class attributes produce visible warnings; a localized `text` map currently
fails the supported string-only type check. The R2 draft does not activate these features.

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
an alternative precedence choice. Explicit `inherit` is a supported proposed token that
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

Defaults below are both proposed base-class `default_value` and module fallback, except
explicitly marked omitted. All controls are optional unless a specialized class requires
one. Supported invalid values and fixed overrides are errors.

### Content, caption, icon and tooltip

| Exact path | Type / allowed values | Default and behavior |
| --- | --- | --- |
| `E.text` | String, proposed localized map | Omitted; exactly one source after merging. Empty string is valid. Literal content, no reference interpolation. |
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

### Caption and icon layout — proposed

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

### Typography and surface — proposed

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

### Size and layout — implemented grammar, proposed explicit defaults

| Exact path | Type / accepted values | R2 default and behavior |
| --- | --- | --- |
| `E.width` | String `auto`, `elastic` or nonnegative decimal `px`, `rem`, `em`, `%` length | `auto`: content width. `elastic` shares row space. |
| `E.height` | Same size-string grammar | `auto`: content height. Explicit lengths size the wrapper. Flow currently accepts but does not stretch `elastic` height. |
| `E.min_width` | Same current size grammar | `0px`: no positive author minimum. Prefer concrete lengths; accepted `auto`/`elastic` are not useful portable constraints. |
| `E.max_width` | Same current size grammar | Omitted: no author-imposed cap. No reasonable universal finite maximum or accepted `none` token. |

Sizes apply to the whole element, caption/icon/help included; text does not accept the list
module's numeric JSON pixel sizes. Existing validation checks syntax, not cross-unit bound
ordering; authors choose consistent limits. R2 does not introduce unit conversion.

Proposed border-box sizing includes padding in assigned dimensions. Prefer auto height.
Complete text remains copyable with no clamp/ellipsis. Too-small explicit dimensions require
reachable scrolling inside the element without covering siblings; focusable overflow regions
need a visible focus indicator and keyboard/touch scrolling. Current code has no text-specific
overflow handling, so these guarantees require implementation and browser checks.

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

## Properties panel — proposed

Groups are display-only; attributes remain flat. Localize every label/help through Paraglide.
Show available class-copy fields plus common sizes. Unknown fields stay under Other / 其他
with warnings. Fixed values show read-only with Fixed by class / 类固定值. Reset removes
an override to restore the saved default/fallback; it never stores null. Clearing an optional
caption removes its key. Empty text, help or icon is an explicit string value, not omission.

| Order/group EN / 中文 | Fields in order (EN / 中文) | Controls and help |
| --- | --- | --- |
| 1. Content / 内容 | `text` Text / 文本; `data_binding` Binding / 数据绑定; `label` Caption / 标题; `help_tip` Tooltip / 提示 | Localized editors and binding path. “Set one content source.” / “只设置一个内容来源。” |
| 2. Caption layout / 标题布局 | `label_placement` Placement / 位置; `label_horizontal_gap` Horizontal gap / 水平间距; `label_vertical_gap` Vertical gap / 垂直间距; `label_horizontal_align` Horizontal alignment / 水平对齐; `label_vertical_align` Vertical alignment / 垂直对齐; `label_max_width` Maximum width / 最大宽度; `label_font_weight` Weight / 字重 | Choices/length/weight. “Wrap the full caption.” / “完整显示并换行标题。” |
| 3. Icon / 图标 | `icon` Icon / 图标; `icon_placement` Placement / 位置; `icon_size` Size / 尺寸; `icon_gap` Gap / 间距; `icon_color` Color / 颜色 | Local icon picker, choices, lengths, color/inherit. “Decorative; keep meaning in text.” / “仅作装饰；请用文字表达含义。” |
| 4. Typography / 字体 | `font_family` Family / 字体族; `font_size` Size / 字号; `font_weight` Weight / 字重; `font_style` Style / 样式; `line_height` Line height / 行高 | Typed fields with default/inherit options. “Defaults preserve small paragraph text.” / “默认保留小号段落文字。” |
| 5. Appearance and layout / 外观与布局 | `color` Foreground / 前景色; `background_color` Background / 背景色; `text_align` Alignment / 对齐; `white_space` Whitespace / 空白处理; `padding` Padding / 内边距 | Color, choices and spacing. “Check both themes.” / “检查两种主题。” |
| 6. Size / 尺寸 | `width` Width / 宽度; `height` Height / 高度; `min_width` Minimum width / 最小宽度; `max_width` Maximum width / 最大宽度 | Size fields; optional maximum. “Size the entire element.” / “设置整个元素的尺寸。” |

Caption controls are conditional on a supplied caption; icon layout is conditional on a
nonempty icon. Hide irrelevant horizontal/vertical caption controls by placement but retain
values. No `source_mode` is stored: source switching explicitly clears the prior instance
source; defaults/fixed source conflicts require a suitable class copy, not silent deletion.
Display whether each effective value comes from an override, class default or module fallback.

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

### Complete R2 class — proposed, stored as draft

Each definition includes its actual default or a documented exception. Compact formatting
does not omit fields. This is JSON data, not a runnable class until implementation.

```json
{
  "descriptor_id": "text",
  "schema_version": "0.4",
  "code_module_id": "text",
  "description": {"en": "Static or bound paragraph with optional caption, icon and tooltip", "zh-cn": "支持可选标题、图标和提示的静态或绑定段落"},
  "implement_notes": {"en": "R2 draft: expanded attributes require renderer, validator and editor implementation before activation.", "zh-cn": "R2 草稿：扩展属性需完成渲染器、验证器和编辑器实现后方可启用。"},
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

### Complete proposed page with full class copy

The page and layout copies use format `0.5`. Its element copy equals the R2 class above;
layout classes must already be registered. This is a complete page, not an app bundle.
The configured static source is bilingual. For a bound instance, remove its `text` and
set `data_binding: "$input_doc.customer.name"`; the same copy supports both alternatives.
The page is not runnable by the baseline renderer/validator.

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
            "description": {"en": "Static or bound paragraph with optional caption, icon and tooltip", "zh-cn": "支持可选标题、图标和提示的静态或绑定段落"},
            "implement_notes": {"en": "R2 draft: expanded attributes require renderer, validator and editor implementation before activation.", "zh-cn": "R2 草稿：扩展属性需完成渲染器、验证器和编辑器实现后方可启用。"},
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

R1 documented the baseline and proposed a paragraph-only configurable extension. On
2026-10-30 the user requested (1) updating existing descriptor records, (2) reasonable
attribute defaults and (3) optional caption, icon and tooltip. R2 incorporates all three.
It replaces R1's exclusion of caption/icon/tooltip, retains meaningful source/default
exceptions and adds a complete proposed descriptor. No human approval of R2 is recorded.

Remaining review scope: optional parts and their defaults, finite icon choices, top caption
placement with narrow fallback, supplementary accessible tooltip, and preserved baseline
appearance. Material changes require a new review revision.

## Registration, implementation and verification

The live database was read on 2026-10-30: `kind=element`, `descriptor_id=text`, version 3,
schema `0.4`, status `active`. Its two source definitions have no defaults. The user's
explicit request authorizes saving the revised record as a new draft before renderer
approval. This is a limited exception to the skill's usual document-only review stage;
activation and frontend implementation remain pending human approval.

**Draft write/read-back:** completed on 2026-10-30. Goose applied
`20261030000004_wpi_text_r2_draft.sql`; read-back confirmed version **4**, schema **0.4**,
status **draft**, `code_module_id: text`, and equality of all 30 attribute definitions
against this R2 contract (26 concrete defaults and four documented exceptions). Version
3 remains active. The existing shared draft validator accepts the proposed class. The
migration's Up was exercised twice and Down once inside a rolled-back transaction,
confirming idempotence, removal of only the new draft, and preservation of active version 3.
The version number is allocated as max existing version plus one at write time, with an
idempotent seed marker. Existing stored versions, custom attributes and all page copies
are preserved. The existing active module row is not duplicated or suspended.

Draft migration: `ChenWeb/project_migrations/20261030000004_wpi_text_r2_draft.sql`.
It updates identity `text` through a new draft version with the defaults and bilingual help
above. No new class identity is needed for instructions. The shared draft validator must
accept this body; unsupported runtime capabilities remain pending. Read-back must compare
all reviewed fields/defaults and verify status before reporting success.

After human approval, implement renderer/types, supported-attribute/value validation,
local icon registry, tooltip lifecycle and localized Properties controls together. Only then
activate a new implemented class version, correct the existing `kb.code_modules.module_doc`
filename via goose, and update the parent reusable-module record/document `20261026-01`,
WPI OpenSpec requirements and devdoc capability notes. Do not rewrite existing page copies.

Verification must cover source exclusivity on save/run; default-only instances; every
missing-default exception; fixed attributes; invalid values and icons; old copies; null,
zero, false and structured bound values; localization; caption placements and narrow fallback;
decorative icon semantics; tooltip focus/hover/tap/Escape/outside close/cleanup; reset and
hidden-field preservation; text selection, zoom, both themes and fixed-size scrolling.
Document checks confirm all three JSON examples parse, the page's full element copy equals
the proposed class, all contract paths are represented in that class, and relative links
resolve. Whitespace checks pass in both changed repositories.
Runtime/browser checks are pending implementation; database checks do not establish that
these proposed interactions work.

Knowledge changed: this document now covers optional supporting content and a fully defaulted
class contract, and a draft record update is explicitly tracked. Baseline runtime descriptions
remain accurate; implementation specs/module docs will need updating when R2 ships. Page
Styles integration, rich text, actions and detailed renderer implementation remain deferred.
