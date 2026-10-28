# 1. Overview

A **Page Style** defines the default look and feel of a page and its elements. A project
can use one Page Style across its pages so that buttons, fields, text, lists and other
elements look consistent without repeating appearance attributes on every instance.

**Status: proposed design, 2026-10-28.** This document completes the Page Style idea; it
does not describe a feature already implemented. The interpreter currently has six
element code modules: `button`, `input`, `select`, `text`, `list` and `menu`. The wider
catalogue below describes commonly used elements for future modules as well. A style
entry alone does not register an element, add an attribute or implement its behavior.

A Page Style controls presentation: sizes, spacing, typography, colours, borders, icons
and visual states. Element classes and instances still define content, data bindings,
validation and actions. A style cannot make a field editable, add a save action, change
menu order or enable a feature that its code module does not support.

## 1.1 Applying a Page Style

The proposed selection rule is: a page may select a Page Style; otherwise it uses its
project's default. If neither selects one, use the interpreter's built-in defaults.
An app hosted in that project uses the same project default. A selected style is merged
over the built-in defaults, so an omitted property still has a usable value.

The properties below use dotted names, for example `button.width`, to mean the `width`
property of the `button` style entry. These are proposed style properties, not new
attributes that can already be saved in a page descriptor. The illustrative object in
§4 uses nested objects to express them.

Element style entries are keyed by **code module**, rather than by the class ID. For
example, classes `save-button` and `cancel-button` that both use the `button` module
share `button.*` defaults. Variants can distinguish their appearance without requiring
one Page Style entry per class. The module must explicitly support each variant.

## 1.2 Precedence and enforcement

Resolve each supported appearance property in this order, highest priority first:

1. A fixed class attribute (`instance_modifiable: false`). Instances may not override it.
2. An explicit, non-empty instance value for an attribute the class allows.
3. A non-empty class default.
4. The selected Page Style's element entry, including its selected variant and state.
5. The Page Style's common defaults, where applicable.
6. The interpreter's built-in fallback.

Fixed attributes and instance validation keep their existing meanings. A required
semantic attribute whose class default is `null` still requires an instance value;
Page Styles cannot supply missing labels, bindings, options or actions. For optional
appearance properties, absent, `null` and empty values contribute no override. For
`width` and `height`, absence at all element/class levels normalizes to `auto` and uses
the special sizing procedure in §1.3.

A project default makes pages consistent by default. To **enforce** a property against
instance overrides, use a fixed class attribute supported by the module. To enforce it
across all project pages also requires a policy restricting which classes and Page
Styles authors may select; that policy is outside this proposal. A Page Style alone is
not an authorization or enforcement boundary.

## 1.3 Width and height

Resolve width and height independently:

1. Resolve the class/instance size, respecting fixed class attributes. An absent, `null`
   or empty size becomes `auto`.
2. If it is a specific length, keep it. A Page Style does not replace an explicit size.
3. If it is `elastic`, let a supporting layouter distribute the available space, within
   the element's size limits. This is a layout instruction, not a style fallback.
4. If it is `auto`, let the layouter determine that dimension first. If no layouter is
   configured, or it leaves that dimension undetermined, use the corresponding Page
   Style property, such as `button.width` or `button.height`.
5. If that property is absent, `null`, empty or `auto`, use the element's built-in
   fallback from §2. A style fallback must not restart layout resolution recursively.

Dimensions are element-specific: `common.width` and `common.height` are not supported.
Page Style width/height values may be supported nonnegative lengths, percentages or
`auto`; `elastic` is only an element layout instruction and is invalid in a style entry.

An unsupported `elastic` instruction is a validation error, not a reason to guess a
fixed size. A percentage needs a definite containing dimension; where that cannot be
resolved, use the element's intrinsic fallback and report a diagnostic. An unresolved
percentage must not become a zero-height control.

In the tables, **content** means intrinsic size based on text, children, media or the
native control; **available** means the containing block's usable dimension. They
describe fallback behavior, not new descriptor keywords. Content-sized elements still
include padding and borders. Use border-box sizing throughout.

Explicit `min_width` and `max_width` constrain the resulting width; reject a minimum
greater than its maximum. This document does not add `min_height` or `max_height` to
the current descriptor format. On a narrow page, wrap or scroll as appropriate; never
silently shrink text or controls below their usable sizes to satisfy layout.

## 1.4 Common styles

These proposed properties apply where meaningful. A module documents which ones it
supports; for example, a divider has no meaningful `font_size`.

| Group | Properties | Built-in default / rule |
| --- | --- | --- |
| Typography | `font_family`, `font_size`, `font_weight`, `line_height`, `text_align` | Project font with Latin and Chinese fallbacks; `16px`, `400`, `1.5`, logical start alignment. |
| Colour | `color`, `background`, `border_color` | Theme foreground, surface and border colours. Keep semantic colours for primary, muted, success, warning and danger roles. |
| Box | `padding`, `border_width`, `border_style`, `border_radius`, `shadow` | No padding, border or shadow unless an element below supplies one; `8px` radius for boxed controls. |
| Placement | `margin`, `gap` | Element margin `0`; layout gap `12px`. The layouter owns placement and spacing between siblings. |
| Icon | `icon_size`, `icon_gap` | `20px`, `8px`. Icons must not replace an accessible label. |
| State | `states.hover`, `states.focus`, `states.active`, `states.disabled`, `states.read_only`, `states.invalid`, `states.loading`, `states.selected` | Apply only to states the element actually has; see §3. |

Within each source (built-in or selected style), an element entry overrides that
source's common defaults. Selected style values then override built-in values as in
§1.2. Thus an input has a built-in border although the built-in common box default has
none, and an explicit selected-style common border can replace that fallback.
Theme colours must resolve for
both light and dark modes; a light surface must not be paired with a dark-mode text
colour accidentally. Arbitrary CSS, scripts and selectors are not Page Style values;
only module-supported, validated properties are accepted.

# 2. Element styles

All sizes in this section are **built-in fallbacks after the layouter**, not mandatory
sizes. Every listed element may override its fallback through its corresponding style
entry. Properties that describe internal parts, such as a table header or field label,
belong to that element's entry.

## 2.1 Button styles

### 2.1.1 Width and height

- If the element's value is `null`, empty or absent, it defaults to `auto`.
- If its value is a specific length, keep it.
- If its value is `auto`, let the layouter determine it first. If the layouter is not
  configured or does not determine it, use `button.width` / `button.height`. If these
  are not specified, default to **200px / 50px**, respectively.

### 2.1.2 Appearance

Use `button.padding: 12px 20px`, `button.font_weight: 500`, `button.border_radius: 8px`
and a `1px` border. The default variant is `primary`; proposed alternatives are
`secondary`, `outline`, `ghost` and `danger`. Each variant defines its foreground,
background and border colours together. Its selected variant is part of the resolved
appearance; it does not change the action.

Keep the label centred and allow translated labels to wrap when necessary. An explicit
fixed height may require visible overflow or scrolling rather than clipped text;
authors should prefer content height for unusually long labels. An icon-only button
uses the `icon_button` entry (fallback `44px × 44px`) and requires an accessible name.
Loading and disabled appearances must leave the label readable and reserve space for
the loading indicator.

## 2.2 Form controls

For labelled fields, `width` describes the whole field block. `height` describes that
block too: a label, control, help text and error text may all contribute. Use the
separate style property `control_height` for the inner control. Help and errors remain
in normal flow and are never covered by the next field. If an explicit whole-field
height cannot contain them, scroll that field block rather than overlapping siblings.
`control_height` is a minimum for text-bearing controls so wrapped content can expand;
it is independent of the whole-field height.

Shared field defaults are `label_gap: 6px`, `help_gap: 4px`, `control_height: 44px`,
`padding: 10px 12px`, a `1px` theme border and `8px` radius. These box properties apply
to the inner control; the field block has no padding by default. Field labels use
`label_font_size: 14px` and `label_font_weight: 500`, matching the standalone `label`
entry; help and error text use `14px` and `1.5` line height. Placeholder text is visually
distinct from entered text and never replaces a label.

| Style entry | Width / height fallback | Additional presentation defaults |
| --- | --- | --- |
| `input` | `280px` / content | One-line text, email and password controls share these defaults. Masking and input type are behavior, not styles. |
| `textarea` | `400px` / content | `control_height: 120px`; top-aligned text, wrapping, vertical resize handle. Preserve user resizing until the field is remounted. |
| `number_input` | `160px` / content | Start-aligned editable value; reserve room for step controls when the module provides them. Units sit beside the value without covering it. |
| `select` | `280px` / content | Reserve trailing space for a dropdown indicator. Its popup uses content height, a maximum height of `320px` and vertical scrolling. |
| `multiselect` | `320px` / content | Selected-value chips wrap with `4px` gaps; empty control is at least `44px` high. Options reuse select popup styling. |
| `autocomplete` | `280px` / content | Reuse input and select popup styling. Highlight the active suggestion independently of the selected value. |
| `checkbox` | content / content | Box `20px × 20px`, radius `4px`, label gap `8px`; a wrapping label aligns with the box at the first line. |
| `radio` | content / content | Indicator `20px` diameter, label gap `8px`; group gap `12px`, vertical group orientation by default. |
| `switch` | content / content | Track `40px × 24px`, thumb `20px`, label gap `8px`; distinguish on/off with position as well as colour. |
| `date_picker`, `time_picker`, `datetime_picker` | `240px`, `180px`, `320px` / content | Reuse field styling and reserve room for the picker icon. Popup content must fit the viewport. |
| `slider` | `280px` / content | Track `4px`, thumb `20px`; ticks and value labels have their own space. |
| `file_upload` | `400px` / content | Drop area has `24px` padding, a dashed `1px` border and content height of at least `120px`. File rows and errors expand beneath it. |

Checkbox/radio groups use a content-sized fieldset with a group label, `12px` item
gaps and vertically stacked choices by default; an inline presentation wraps. Search
and password inputs reuse `input` styling and reserve space for any clear, search or
visibility controls provided by the module. Those controls use icon-button targets.

Checkboxes, radios, switches and slider thumbs have an interaction target of at least
`44px × 44px`, using surrounding space when the visible mark is smaller. Styling
`number_input` does not require a separate implementation: a module may expose the
same style role for `input_type: number`. Such role mappings must be documented by
the module; they are not inferred from class names.

## 2.3 Text and content

| Style entry | Width / height fallback | Additional presentation defaults |
| --- | --- | --- |
| `text` | content / content | Common typography; preserve intentional line breaks, wrap long words and URLs, and allow text selection. |
| `heading` | content / content | Sizes for levels 1–6: `32px`, `28px`, `24px`, `20px`, `18px`, `16px`; weight `600`, line height `1.3`. Heading level is semantic and remains independent of visual size. |
| `label` | content / content | `14px`, weight `500`; required indicator has a `4px` gap and a text/accessibility equivalent. |
| `link` | content / content | Theme link colour and underline; visible hover and keyboard focus. Navigation destination comes from the element, not its style. |
| `badge`, `tag` | content / content | `12px`, line height `1.5`, padding `2px 8px`, pill radius; neutral default with semantic colour variants. A removable tag reserves room for its remove button. |
| `code` | available / content | Monospace font `14px`, line height `1.5`, padding `16px`, muted surface and `8px` radius. Preserve whitespace; scroll long lines horizontally. Inline code uses content width and `2px 4px` padding. |
| `divider` | available / `1px` | Theme border colour, no shadow. A vertical variant swaps the axes and needs a definite available height. A caption interrupts the rule with `12px` gaps. |

For prose, a Page Style may set `text.max_width` to `70ch` for comfortable reading;
leave the built-in maximum unset so small labels and other text uses are unaffected.
Truncation is opt-in and must offer a way to read and copy the full value.

## 2.4 Lists and data displays

| Style entry | Width / height fallback | Additional presentation defaults |
| --- | --- | --- |
| `list` | available / content | Existing WPI record-list presentation: header weight `500`, cell padding `12px 16px`, row separators `1px`, row height at least `44px`. Long values wrap by default. |
| `table` | available / content | Reuse list defaults; header uses a muted surface. Numeric display cells may align to the end. Sticky headers, selection and editable cells require module support. |
| `description_list` | available / content | Two columns, label column `160px`, column gap `16px`, row gap `12px`. Stack label above value when the pair cannot fit. |
| `tree` | `280px` / content | Row height at least `44px`, indentation `20px` per level, expander `16px`, icon gap `8px`. Wrap labels instead of covering expanders. |
| `pagination` | content / content | Control target `44px`, gap `4px`; current page has a selected appearance, unavailable previous/next controls a disabled appearance. |

The current `list` supports only rows. Styling it does not add cards, sorting, paging,
filtering or editing. For a future supported card presentation, use `16px` card padding
and `16px` gaps; let the layouter determine the column count. A wide table scrolls
within its own container rather than forcing the whole page wider. Column sizes and
record order remain descriptor/layout concerns.

## 2.5 Navigation

| Style entry | Width / height fallback | Additional presentation defaults |
| --- | --- | --- |
| `menu` | `240px` / content | Vertical menu; item height at least `44px`, padding `10px 12px`, icon `20px`, nesting indent `20px`. Selected item uses a tinted surface and weight `500`. |
| `tabs` | available / content | Tab target height at least `44px`, horizontal padding `16px`, `2px` active indicator. Allow tab-strip scrolling when tabs cannot fit. |
| `breadcrumb` | content / content | `14px` text, separator gap `8px`, current item visually distinct. Wrap on narrow pages. |
| `steps` | available / content | Marker `28px`, connector `2px`, text gap `8px`; distinguish current, completed and pending steps by shape/text as well as colour. |
| `toolbar` | available / content | Padding `8px`, gap `8px`; wrap groups while preserving their order. Buttons use their own style entries. |

Styles never reorder menu items or tabs, change which page is active, or supply a
navigation action. Folder and page icons retain their distinct meanings.

## 2.6 Containers and overlays

| Style entry | Width / height fallback | Additional presentation defaults |
| --- | --- | --- |
| `container` | available / content | Transparent background, no border or padding; child gap `12px`. Layout direction and child placement belong to its layouter. |
| `card` | available / content | Surface background, `1px` border, `8px` radius, padding `20px`, section gap `16px`; no shadow by default. |
| `fieldset` | available / content | Padding `16px`, border `1px`, radius `8px`, legend weight `500`, child gap `12px`. |
| `accordion` | available / content | Header target height at least `44px`, padding `12px 16px`, content padding `16px`, `1px` separators. Collapse indicator reflects the actual state. |
| `dialog` | `560px` / content | Padding `24px`, radius `12px`, overlay shadow and dimmed backdrop. Limit to viewport minus `32px`; scroll the body while keeping close/actions reachable. |
| `drawer` | `400px` / available | Padding `24px`, surface background, inward shadow; clamp to viewport width and scroll its body. |
| `popover` | `320px` / content | Padding `12px`, `1px` border, radius `8px`, overlay shadow; reposition or constrain to the viewport. |
| `tooltip` | content / content | Maximum width `280px`, padding `6px 10px`, `12px` text, radius `4px`; readable contrast against its background. |

Containers holding children or pages need their own composition contract. This proposal
does not resolve how a future accordion holds WPI panels. Likewise, a dialog's focus
trap, focus restoration, close behavior and keyboard handling are component behavior;
styling its backdrop does not implement them. Overlay stacking order is owned by the
runtime rather than arbitrary per-element z-index values.

## 2.7 Media

| Style entry | Width / height fallback | Additional presentation defaults |
| --- | --- | --- |
| `icon` | `20px` / `20px` | Inherit text colour; keep aspect ratio. Decorative icons are hidden from assistive technology; meaningful ones need an accessible name. |
| `image` | intrinsic / intrinsic | Preserve source aspect ratio, fit within available width, `object_fit: contain`, no border or radius. Missing media shows a stable placeholder. |
| `avatar` | `40px` / `40px` | Circular crop, `object_fit: cover`, initials fallback centred on a muted surface. |
| `video` | available / aspect ratio | Preserve source ratio; use `16:9` until known. Player controls remain visible and keyboard accessible. |
| `audio` | `320px` / native control | Fit the player within the available width; leave room for playback controls and elapsed/total time. |
| `chart` | available / `320px` | Padding `16px`; theme-aware series palette, readable axes and legend, space for labels. Provide a textual or tabular representation of the data. |

Media URLs, alternative text, captions, playback and chart data are element attributes,
not style values. When only one image dimension is specified, derive the other from its
aspect ratio. If both are fixed, `object_fit` controls fitting within that box.

## 2.8 Feedback and status

| Style entry | Width / height fallback | Additional presentation defaults |
| --- | --- | --- |
| `alert` | available / content | Padding `12px 16px`, radius `8px`, `1px` semantic border, icon `20px`, gap `12px`; info, success, warning and danger appearances. |
| `toast` | `360px` / content | Padding `12px 16px`, radius `8px`, overlay shadow; clamp to viewport minus `32px`, stack with `12px` gaps. |
| `progress` | `280px` / content | Track `8px`, pill radius; label/value gap `8px`. Determinate fill follows the actual value; indeterminate appearance never invents a percentage. |
| `spinner` | `24px` / `24px` | Theme primary colour, stroke `2px`; loading text is available to assistive technology. |
| `skeleton` | available / `20px` | Muted surface, radius `4px`; match the expected content dimensions where known to reduce layout shifts. |
| `empty_state` | available / content | Padding `32px`, centred icon `48px`, title `18px`, body `14px`, gap `12px`; action buttons use button styles. |

Showing, dismissing, announcing or retrying feedback belongs to the component. A Page
Style controls its appearance without changing error severity, loading state or timeout.

# 3. States, accessibility and responsive behavior

- **Focus:** all interactive elements have a visible keyboard focus indicator. Default:
  `2px` theme focus ring with `2px` offset; do not clip it at a container boundary.
- **Hover and active:** adjust surface/border colours without changing box dimensions.
  Touch and keyboard users must be able to access the same actions without hover.
- **Selected and checked:** use a marker, weight, position or checkmark as well as
  colour. A selected item may also have focus; state styles must preserve both cues.
- **Invalid:** retain the value and label; use a danger border plus associated error
  text. Focus on an invalid field keeps its focus ring. Required indicators alone are
  not error messages.
- **Disabled and read-only:** disabled controls cannot run actions; read-only fields
  keep selectable and copyable text. Muted styling must leave labels legible. A style
  cannot turn one state into the other.
- **Loading:** preserve useful dimensions, text and focus. Reduced-motion mode replaces
  nonessential spinning, pulsing and transitions with a static loading indication.
- **State conflicts:** apply base/variant, then selected or checked, then hover/active,
  then read-only/disabled/loading restrictions, then invalid decoration. Draw keyboard
  focus last. Disabled controls suppress hover/active feedback. Semantic cues must
  remain visible even if properties from a later state override the same colour.
- **Contrast:** normal text must meet a `4.5:1` contrast ratio; large text and meaningful
  control boundaries/focus indicators at least `3:1`. Review resolved state colours in
  both themes, not just the base palette.
- **Language and selection:** support English and Chinese without fixed label lengths;
  use logical start/end alignment and spacing. All page and panel text stays selectable.
  Limit selection suppression to small controls such as drag handles.
- **Narrow containers:** respond to the space available inside the pane, not only the
  browser width. Auto-sized fields fit within that space; text wraps, menus and tables
  scroll when needed, and overlays stay inside the viewport. Explicit fixed sizes
  remain fixed and may require scrolling; Page Styles do not silently replace them.

# 4. Illustrative Page Style

This is a partial **proposed style object**, not a descriptor accepted by the current
validator. Storage, identifiers, project/page selection attributes and versioning need
an implementation specification before this can be saved or loaded by the interpreter.
Omitted properties use the built-in defaults above. Theme colours are omitted here so
the example does not accidentally define only a light theme.

```json
{
  "common": {
    "font_size": "16px",
    "line_height": 1.5,
    "border_radius": "8px",
    "gap": "12px"
  },
  "button": {
    "width": "200px",
    "height": "50px",
    "padding": "12px 20px",
    "font_weight": 500
  },
  "input": {
    "width": "320px",
    "control_height": "44px",
    "label_gap": "6px"
  },
  "textarea": {
    "width": "400px",
    "control_height": "144px"
  },
  "menu": {
    "width": "240px",
    "icon_size": "20px"
  },
  "card": {
    "padding": "20px",
    "gap": "16px"
  }
}
```

Examples of resolution:

| Element / layout input | Result |
| --- | --- |
| Button width omitted; layouter leaves width unresolved | `200px` from `button.width`. |
| Button `width: auto`; layouter assigns `160px` | `160px`; the style fallback is not consulted. |
| Button `width: 120px`; style width is `200px` | `120px`; explicit size is retained. |
| Button `width: auto`, `height: auto`; layouter assigns only width | Layout width; height `50px` from the style. |
| Button dimensions unresolved; no button entry in the selected style | Built-in `200px × 50px`. |
| Button `width: elastic`; supporting layouter has `300px` free | Layouter computes the share within min/max limits; style width does not replace it. |
| Input width unresolved; class default is `360px` | `360px`; the class default precedes the style's `320px`. |
| Auto-height input with a label and error message | Inner control at least `44px` high; whole field expands to include label and error. |
| Class fixes button width to `180px`; instance sets `220px` | Validation error; fixed class attributes cannot be overridden. |

# 5. Implementation boundary and related documents

The current `flow-layouter` maps `auto` to content sizing. Implementing this proposal
must distinguish a dimension it deliberately resolves from one it leaves for a Page
Style fallback. A computed browser size alone is not proof that the layouter made that
decision. The current `pageStyle()` helper in `ChenWeb/web/src/lib/wpi/layout.ts` only
maps page dimensions and alignment to CSS; it is not this Page Style feature.

Before implementation, capture the formal contract in OpenSpec: style selection and
storage, supported property/value validation, merging and state resolution, module style
roles, layout handoff, and fallback diagnostics. Extend the Go validator, TypeScript
types and renderers together. Cover the resolution examples above and verify translated
labels, narrow panes, focus, text selection and both themes. Do not mark a catalogue
element supported until its code, validation and module documentation exist.

Related documents:

- [Interpreter design](../devdocs/202610/2026102601-devdoc-web-page-interpreter.md),
  §3.5 for classes and fixed attributes, §3.7 for layout, §9 for future features.
- Current code module contracts: [button](interpreter-button.md),
  [input](interpreter-input.md), [select](interpreter-select.md),
  [text](interpreter-text.md), [list](interpreter-list.md), [menu](interpreter-menu.md).
- [Frontend module](../modules/module-web-page-interpreter-frontend.md) and
  [backend module](../modules/module-web-page-interpreter-backend.md).

This document adds a proposed presentation contract. The module documents and existing
OpenSpec requirements still describe the implemented behavior and remain unchanged.
No schema changes, new `kb.wpi_elements` rows or runtime support are introduced here.
Detailed behavioral contracts for future elements, storage design and an authoring UI
are intentionally left to their implementation proposals.
