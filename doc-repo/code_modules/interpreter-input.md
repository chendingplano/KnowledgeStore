# Code module: `input`

**Code module ID:** `input` \
**Status:** implemented; input class version 4 provides the expanded attributes \
**Row in `kb.code_modules`:** `input`, `module_type` `element`, `module_doc` `input.md`, `status` `active` \
**Classes using it:** `input` \
**Frontend:** `ChenWeb/web/src/lib/wpi/elements/InputElement.svelte`, registered in `elements/index.ts` \
**Backend:** `codeModules["input"]` and the `input` case of `element()` in `ChenWeb/server/api/wpi/validate.go` \
**Part of:** reusable module `20261026-01`, Web Page Interpreter frontend \
**Related design:** devdoc 2026102601 §3.5.1–§3.5.2, §3.8; [Page Styles](interpreter-page-styles.md)

## Purpose and behavior

An input displays and optionally edits one attribute of the panel's input doc. It uses a
localized caption and single-line control, writes edits to the bound attribute, and displays
client and server errors beside it. Read-only text remains selectable. The attributes below
are available on input class version 4. Pages retain copies of their classes: previously saved
pages must be saved with the updated class copy before they can set newly added attributes.
Existing pages without placement attributes use the new `left` component default.

`label` and `data_binding` are required; `binding_mode` defaults to `read-write` in the
class and may be supplied by the page. `input_type` defaults to `text`. The layouter handles
`width`, `height`, `min_width`, and `max_width` for the whole element. Attributes not listed
in a saved class copy cannot be set on that instance.

For an explicit height, the field block fills the height assigned by the layouter and
the input control takes the remaining space after its caption and help content. The
layouter's minimum and maximum row heights still constrain the assigned height.

## Attribute contract

The names and defaults below describe the input module. Required attributes must have a value
after class defaults, instance values and applicable page settings are resolved. Existing
class/instance precedence and fixed-attribute rules apply. Descriptor validation checks the
attribute values. Unknown attributes in a class are reported as unsupported.

### Caption and layout

`label` remains required and identifies the field even when a placeholder is present.
All lengths below are non-negative CSS pixel lengths expressed as strings (for example,
`"10px"`); `0px` is allowed. `width` and related layout attributes describe the entire
field block, not just the control. Help and errors are placed below the control regardless
of caption placement and contribute to the block's height.

| Attribute | Values | Default and behavior |
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
The module uses a 10px gap by default. The Page Styles catalog describes a generic 6px
field gap; input-specific style integration and precedence remain to be reconciled.

### Control and content

| Attribute | Values | Default and behavior |
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

| `validation` member | Meaning |
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

**Validators** (2026-11-04, OpenSpec `wpi-primitive-validators`). An input may also hold
validator instances in `validators`, even when its class copy does not name it
([validator-primitive.md](validator-primitive.md)). They are an add-on: `required`,
`max_length`, `validation` and the `input_type` formats keep working unchanged. Validators run
together with these rules, on blur, then on every change, and before a save; all must pass.
The backend runs them again on every save, after the input rules, and refuses failing values
with 422 `validation_errors`. Their errors show under the control after the input's own,
from the code and params, or from the instance's `messages`. A `read-only` input is not
checked.

### Accessibility, state, and examples

A real label must be associated with the control by a unique ID for every instance. Keep
text selectable, visible focus indicators, sufficient theme contrast, and keyboard navigation.
Required, error, and read-only states must not depend on color alone. Language changes must
update localized content without losing the value or focus. Tab order follows the rendered
control and any help or disclosure controls; reordering captions must not reorder fields.
Do not use placeholder text in place of a caption or help. The field accepts one line only;
use a separate multiline component for long text.

Example descriptor:

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

## Property editor

The WPI Editor's Properties panel draws this module's property editor at run time from
`ChenWeb/web/src/lib/wpi/properties/input.ts` (OpenSpec `wpi-property-editors`); no Svelte
file is written per module. The table below is the contract that file follows: change the
two together. Groups are presentation only; the instance stays flat. Every editor starts
with a **Placement** group showing the element's pane and its position on the page
(read-only). Labels and group names are in Paraglide. Help tips are the class's `help_tip`
for each attribute; an attribute with a non-empty tip gets an info icon at the upper right
of its value editor. A value fixed by the class is shown read-only, marked fixed; *Reset*
removes the instance's own value. Hidden attributes keep their values. A class attribute
the table does not list appears under **Other** with the common-sense value editor. Value
editors are described in devdoc 2026102701 §1.3.9.

When neither the instance nor its class sets a caption or type attribute, the editor shows the
value `InputElement.svelte` uses (`inputDefaults` in the definition file).

| Group | Attribute | Value editor | Data and rules |
| --- | --- | --- | --- |
| General | `label` | localized-text | One text, or English and Chinese |
| General | `data_binding` | text | A path such as `$input_doc.name` |
| General | `binding_mode` | value-picker | `read-only`, `read-write` |
| General | `input_type` | value-picker | `text`, `password`, `email`, `number`, `tel`, `url`, `search` |
| Caption layout | `label_placement` | value-picker | `left`, `top`, `right`, `bottom` |
| Caption layout | `label_horizontal_gap` | length | px; shown for `left` and `right` placement |
| Caption layout | `label_vertical_gap` | length | px; shown for `top` and `bottom` placement |
| Caption layout | `label_horizontal_align` | value-picker | `left`, `center`, `right` |
| Caption layout | `label_vertical_align` | value-picker | `top`, `center`, `bottom`; shown for `left` and `right` placement |
| Caption layout | `label_max_width` | length | px |
| Caption layout | `label_max_lines` | number | A whole number, at least 1 |
| Caption appearance | `label_font_family` | text | A CSS font family |
| Caption appearance | `label_font_size` | length | px |
| Caption appearance | `label_color` | color | None or one CSS colour |
| Caption appearance | `label_font_weight` | value-picker | `normal`, `bold`, `100`–`900`; numbers are stored as numbers |
| Caption appearance | `label_font_style` | value-picker | `normal`, `italic`, `oblique` |
| Input and help | `placeholder`, `help_text`, `help_tip` | localized-text | One text, or English and Chinese |
| Input and help | `autocomplete` | text | An autocomplete token |
| Validation | `required` | switch | |
| Validation | `max_length` | number | A whole number, at least 0; hidden for `number` inputs |
| Validation | `validation` | validation | `min`, `max`, `step` for `number` inputs; `min_length`, `pattern` otherwise. Rules of the other kind are kept |
| Validators | `validators` | validator-list | The input's validator instances; each then has a group of its constraints ([validator-primitive.md](validator-primitive.md) §7) |
| Size | `width`, `height`, `min_width`, `max_width` | length | `auto`, `elastic`, or a number in px, rem, em or %; a bare number means px; a note under `width` says the panel's limits also apply |

## Implementation and verification

The input class is stored in `kb.wpi_descriptors`; migration
`ChenWeb/project_migrations/20261030000003_wpi_input_attributes.sql` adds version 4 without
altering saved page copies. Frontend validation blocks a save for invalid mounted fields; the
server also checks input rules against the stored page's class copies before the save action.
Save-action field rules and database constraints still apply. Client errors revalidate after
blur or a save attempt; server errors are discarded when the document has changed since the
request. Client and server support the numeric bounds, step, text length, pattern and format
checks described above.

The narrow-layout fallback uses a 250px container breakpoint. Client maximum-length handling
limits newly typed or pasted text by Unicode code point and waits for IME composition to
finish; an already overlength bound value is preserved and reported. The current Properties
panel uses generic text/JSON controls for localized values and lengths; a dedicated bilingual
text editor is not yet available. Browser-based verification of the signed-in editor requires
an authenticated session.
