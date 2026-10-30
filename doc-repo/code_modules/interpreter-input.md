# Code module: `input`

**Code module ID:** `input` \
**Status:** implemented with the limited behavior described below; the expanded contract is proposed \
**Row in `kb.code_modules`:** `input`, `module_type` `element`, `module_doc` `input.md`, `status` `active` \
**Classes using it:** `input` \
**Frontend:** `ChenWeb/web/src/lib/wpi/elements/InputElement.svelte`, registered in `elements/index.ts` \
**Backend:** `codeModules["input"]` and the `input` case of `element()` in `ChenWeb/server/api/wpi/validate.go` \
**Part of:** reusable module `20261026-01`, Web Page Interpreter frontend \
**Related design:** devdoc 2026102601 §3.5.1–§3.5.2, §3.8; [Page Styles](interpreter-page-styles.md)

## Purpose and current behavior

An input displays and optionally edits one attribute of the panel's input doc. The current
implementation displays a localized caption above a single-line control, writes edits to the
bound attribute, and displays server save errors for that path below the control. Read-only
text remains selectable. It accepts:

| Attribute | Required | Implemented behavior |
| --- | --- | --- |
| `label` | yes | String or language map; caption in the user's language. |
| `data_binding` | yes | Path such as `$input_doc.email`; reads and writes the attribute and matches save errors. |
| `binding_mode` | yes | `read-only` or `read-write`; may be supplied by the page or class default. |
| `input_type` | no | `text` (default), `number`, or `email`. Number input writes `null` for empty, a JSON number for a valid number, and otherwise the typed string. |

The layouter handles `width`, `height`, `min_width`, and `max_width` for the whole element.
The current component has no placeholder, help text, client validation, or configurable
caption layout. Its errors come from the server on save. The requirements below are a
proposed extension; their attributes and defaults do **not** describe existing behavior.

## Proposed expanded contract

The following names and defaults are proposed for implementation and review. Required
attributes must have a value after class defaults, instance values and applicable page
settings are resolved. Existing class/instance precedence and fixed-attribute rules still
apply. Unknown or invalid attributes should be reported by descriptor validation, not
silently ignored. Existing instances need a compatibility or migration decision before
these new defaults replace their current appearance.

### Caption and layout

`label` remains required and identifies the field even when a placeholder is present.
All lengths below are non-negative CSS pixel lengths expressed as strings (for example,
`"10px"`); `0px` is allowed. `width` and related layout attributes describe the entire
field block, not just the control. Help and errors are placed below the control regardless
of caption placement and contribute to the block's height.

| Proposed attribute | Values | Default and behavior |
| --- | --- | --- |
| `label_placement` | `left`, `top`, `right`, `bottom` | `left`. Position the caption relative to the control; `left` and `right` create a horizontal pair, `top` and `bottom` a vertical pair. |
| `label_horizontal_gap` | length | `10px`; space between caption and control for left/right placement. |
| `label_vertical_gap` | length | `10px`; space between caption and control for top/bottom placement. |
| `label_horizontal_align` | `left`, `center`, `right` | `right`; alignment of caption text within its allocated caption box. |
| `label_vertical_align` | `top`, `center`, `bottom` | `center`; for left/right placement, aligns the caption box against the control, excluding help and errors. |
| `label_max_width` | length | `160px`; maximum caption box width, also constrained by available space. |
| `label_max_lines` | positive integer | `1`; maximum displayed lines. Wrap at word boundaries where possible, falling back to character boundaries for long unbroken text and languages without spaces. |
| `label_font_family` | CSS font family string | inherit the field's font. |
| `label_font_size` | positive pixel length | `14px`. |
| `label_color` | valid CSS color | inherit the theme's field-label color. |
| `label_font_weight` | CSS weight `100`–`900`, `normal`, or `bold` | `500`. |
| `label_font_style` | `normal`, `italic`, `oblique` | `normal`. |

The vertical alignment values above use vertical directions; the request's `left`, `center`,
`right` for vertical alignment is interpreted as `top`, `center`, `bottom`. Horizontal
alignment is physical left/right, independent of language direction. When the caption exceeds
its width and line limit, truncate the final visible line with `…`. Show the complete
localized caption in a tooltip on hover **and keyboard focus**, and retain the complete
caption as the control's accessible name. Do not rely on the tooltip as the only accessible
name. Tooltip text must also be available on touch, for example by tapping a dedicated
focusable disclosure. Show the disclosure only when truncation actually occurs.

At narrow widths, constrain the caption and keep the control usable; if a horizontal pair
cannot fit, stack the caption above the control and retain the configured vertical gap.
Do not clip help, errors, focus indicators, or the control. An explicitly fixed block height
must not hide this content; allow overflow and document it in the layout implementation.
The proposed 10px gap overrides the generic Page Styles field `label_gap` default of 6px
for this module when no explicit module value is supplied; reconcile the style catalog when
implementing precedence rather than assuming the existing style system supports these keys.

### Control and content

| Proposed attribute | Values | Default and behavior |
| --- | --- | --- |
| `input_type` | `text`, `password`, `email`, `number`, `tel`, `url`, `search` | `text`. Single-line control; other HTML types require an explicit contract before adding them. |
| `placeholder` | localized text | absent; example: “Please enter the password”. Shown only when empty, never used as the accessible label or as an initial value. |
| `help_text` | localized text | absent; persistent explanatory text below the control, associated through `aria-describedby`. |
| `help_tip` | localized text | absent; supplementary information exposed by a keyboard- and touch-operable control with an accessible name; dismissible with Escape and without moving focus unexpectedly. |
| `required` | boolean | `false`; when true, indicate required visibly and programmatically. |
| `max_length` | non-negative integer | unset; limit text length as defined below. |
| `validation` | object | `{}`; rules in the next section. |
| `autocomplete` | supported HTML autocomplete token or `off` | omitted; allow the browser's normal behavior. Authors should use appropriate tokens such as `email`, `current-password`, or `new-password`. |

Localized text accepts the same string or language-map format and fallback policy as `label`.
Provide English and Chinese text for user-facing content. Empty placeholder, help text, or
tip behaves as absent. Read-only controls remain focusable and copyable and do not write;
required and other validation do not block saving solely because a read-only control is
empty. Any server constraints still apply. Password values are masked; do not place them in
help, tooltips, logs, error messages, or example data. Password managers and paste must work.
A reveal control, if later added, needs an accessible label and must not submit the form.

`max_length` counts Unicode code points, including spaces, without trimming or normalization;
`0` permits only an empty value. Apply it to text-like types (`text`, `password`, `email`,
`tel`, `url`, `search`); reject its use with `number`. Enforce the same definition on client
and server, including pasted and composed text, without corrupting IME composition. Do not
silently truncate an existing bound value; show it and report the violation. Browser-native
`maxlength` alone is insufficient if its counting differs.

### Validation and saving

Validation rules supplement, not replace, server-side save validation. Their definitions
must be shared or mapped explicitly to the save action's existing rules; a client-side rule
alone is not a security or data-integrity guarantee. Server rules remain authoritative.

| Proposed `validation` member | Meaning |
| --- | --- |
| `min_length` | Non-negative integer; minimum Unicode code points for nonempty text-like values, using the same counting as `max_length`. Must not exceed `max_length` when both exist. |
| `pattern` | Optional regular expression for the entire nonempty string; define a common client/server regex dialect and reject unsupported expressions at descriptor validation. |
| `min`, `max` | Finite numeric bounds for `number`, inclusive; `min` must not exceed `max`. |
| `step` | Positive finite number for `number`; valid values are `min + n × step`, or `n × step` when `min` is absent, for integer `n`. |

Type validation checks nonempty email and URL values using one documented client/server
algorithm; `tel`, `search`, `text`, and `password` impose no implicit format. Number values
must be finite. Empty means `null` or the empty string; whitespace is data and is not
implicitly trimmed. Optional empty values bypass format and range rules; required empty
values fail. Preserve the existing number conversion behavior until explicitly migrated.
Keep the user's current text on invalid input; never silently coerce an invalid value into a
different valid value.

Validate on blur and on save; after an error is shown, revalidate as the user edits. Do not
show an error for an untouched field before a save attempt. Invalid editable values block
the save action, remain in the input doc, and receive a localized, actionable message under
the control. Associate errors and help with the field, set `aria-invalid` only while invalid,
and move focus to the first invalid editable field on a blocked save. Server errors are
matched by binding path, displayed alongside client errors without duplicate messages, and
cleared or refreshed when the affected value changes and on the next save response. A later
response for an older value must not overwrite validation for a newer edit. Save failures
unrelated to a field remain visible at page level.

### Accessibility, state, and examples

A real label must be associated with the control by a unique ID for every instance. Keep
text selectable, visible focus indicators, sufficient theme contrast, and keyboard navigation.
Required, error, and read-only states must not depend on color alone. Language changes must
update localized content without losing the value or focus. Tab order follows the rendered
control and any help or disclosure controls; reordering captions must not reorder fields.
Do not use placeholder text in place of a caption or help. The field accepts one line only;
use a separate multiline component for long text.

Example target descriptor (proposed, not accepted by the current implementation):

```json
{
  "element": "input",
  "label": { "en": "Email address", "zh-cn": "电子邮箱" },
  "data_binding": "$input_doc.email",
  "binding_mode": "read-write",
  "input_type": "email",
  "placeholder": { "en": "Enter your email", "zh-cn": "请输入电子邮箱" },
  "help_text": { "en": "We use this to contact you.", "zh-cn": "我们将通过此邮箱与您联系。" },
  "required": true,
  "max_length": 254,
  "label_placement": "left"
}
```

## Implementation and verification

Implementing this proposal requires coordinated changes to the component, descriptor
validation and types, save validation/error handling, localization, and any style resolution.
Align the Page Styles document and devdoc with the chosen contract, and update this document's
status only after implementation. Verify default and all four placements, alignment, gaps,
truncation and keyboard/touch disclosure, narrow layouts, both languages, read-only and
required states, type conversions, Unicode and IME input, every validation rule, save failures
and stale responses. Test keyboard and screen-reader associations, focus, and selection. Check
existing classes and migrate or preserve their appearance deliberately.

Until implementation, a class may carry an unsupported attribute but it has no effect;
saving the class or loading an app that uses it reports a warning (devdoc §3.5.2).
