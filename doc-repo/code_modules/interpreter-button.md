# Code module: `button`

**Code module ID:** `button` \
**Status:** implemented; button class version 7 adds background color \
**Row in `kb.code_modules`:** `button`, `module_type` `element`, `module_doc` `button.md`, `status` `active` \
**Classes using it:** `button` \
**Frontend code:** `ChenWeb/web/src/lib/wpi/elements/ButtonElement.svelte`, registered as `button`
in `codeModules` (`ChenWeb/web/src/lib/wpi/elements/index.ts`) \
**Backend checks:** `codeModules["button"]` and the `button` case of `element()` in
`ChenWeb/server/api/wpi/validate.go` \
**Part of:** reusable module `20261026-01`, Web Page Interpreter frontend
(`doc-repo/modules/module-web-page-interpreter-frontend.md`) \
**Design:** devdoc 2026102601 §3.5.1–§3.5.2

## Background color — revision 1

**Approved by the user on 2026-11-06; implemented in class version 7.** The existing
active `button` class and `button` code module retain their identities.

Add the flat instance attribute `background_color` (for example,
`/panels/main/elem_list/0/background_color`). It accepts either one valid CSS color
string or an object containing exactly `light` and `dark`, both valid CSS color strings.
The chosen color applies to the button background; the light/dark form follows the active
color scheme. Invalid values are validation errors, consistent with other surface colors.
The attribute is optional: when absent, the button retains the theme's default background.
No concrete class default is proposed because the existing theme supplies that background
and its value changes with the theme. Empty strings and incomplete color pairs are invalid;
the editor's None mode removes the override. A class may set a default or fix a non-null
value using the existing class rules; otherwise an instance value overrides the class default.
The existing foreground, focus indicator, hover and disabled treatments remain those of the
button component. Authors should choose colors that keep the label legible in each theme.

In the Properties panel, add **Colors / 颜色** after General and before Size, with
**Background color / 背景颜色** using the shared `color-picker` value editor (editor ID
`color`, theme option enabled). It offers None, Single color, and Light and dark; reset
restores the class default or removes the instance override when there is none. Fixed
class values are displayed read-only under the normal class rules. Suggested help:
“Button background; leave unset to use the theme.” / “按钮背景；留空时使用主题颜色。”

Illustrative excerpts only, not complete runnable descriptors:

```json
{
  "descriptor_id": "button",
  "code_module_id": "button",
  "background_color": {
    "help_tip": {"en": "Button background; leave unset to use the theme.", "zh-cn": "按钮背景；留空时使用主题颜色。"},
    "value_editor": {"id": "color", "options": {"theme": true}}
  }
}
```

```json
{
  "element": "button",
  "class": {"descriptor_id": "button", "code_module_id": "button", "background_color": {"value_editor": {"id": "color", "options": {"theme": true}}}},
  "background_color": {"light": "#ffffff", "dark": "#202020"},
  "on_click": {"action": "close-page"}
}
```

Pages retain embedded class copies: older copies continue to use the theme background
and cannot configure this attribute until updated with the new class copy. Unsupported
class attributes remain warnings under current WPI rules.
The change does not add foreground, border, icon or variant controls. The renderer uses the
configured color at rest and a 90% color mix on hover, matching the existing button treatment.
Backend tests cover valid and invalid colors; the descriptor was read back from the database.

## What it draws

A button that runs an action when it is clicked, drawn with ChenWeb's own button
component. While the action runs the button is disabled, so a second click cannot run it
again.

## Attributes

| Attribute | Required | Value | What the code does with it |
| --- | --- | --- | --- |
| `label` | yes | text: a string, or one text per language | The button's text, in the user's language. |
| `on_click` | yes | an action instance of `save`, `open-page`, `close-page` or `save-page` | Run when the button is clicked. It holds an action, so a class can neither give it a default nor fix it. |
| `background_color` | no | CSS color or `{ "light": color, "dark": color }` | Overrides the theme background as described above. |

*Required* means the code cannot work without the attribute: every instance must end up
with a value, set by the instance itself or by its class's default.

Like every code module, `button` also accepts the size attributes `width`, `height`,
`min_width` and `max_width`. The layouter applies them (devdoc §3.7); this code does not
read them.

## Property editor

The WPI Editor's Properties panel draws this module's property editor at run time from
`ChenWeb/web/src/lib/wpi/properties/elements.ts` (OpenSpec `wpi-property-editors`); no Svelte
file is written per module. The table below is the contract that file follows: change the
two together. Every editor starts with a **Placement** group showing the element's pane
and its position on the page (read-only). Help tips are the class's `help_tip` for each
attribute; an attribute with a non-empty tip gets an info icon at the upper right of its
value editor. A class attribute the table does not list appears under **Other** with the
common-sense value editor (chosen from its name and default value). Value editors are
described in devdoc 2026102701 §1.3.9.

| Group | Attribute | Value editor | Data and rules |
| --- | --- | --- | --- |
| General | `label` | string-editor | English and Chinese by default (Multilingual, default `{"en": "Button", "zh-cn": "按钮"}`); the Options menu switches to Single or List. A plain-string label shows in Single. |
| General | `on_click` | value-picker | The active trigger action classes (`GET /api/v1/wpi/classes/action`); choosing one stores `{ "action": id }` |
| Colors | `background_color` | color-picker | Optional single color or light/dark pair; unset uses the theme. |
| Size | `width`, `height`, `min_width`, `max_width` | length | `auto`, `elastic`, or a number in px, rem, em or %; a bare number means px; a note under `width` says the panel's limits also apply |

## Limits

- It uses the theme's button style apart from its optional background color; there are no
  attributes for variants, icons or foreground color.
- It cannot ask for confirmation before running its action.

## Changing this module

1. Add or change the attribute in the table above.
2. Have a coding assistant such as Claude Code change the code to match: the component
   above, the module's entries in `validate.go`, and the `ElementInstance` type in
   `ChenWeb/web/src/lib/wpi/types.ts`.

Until both are done, a class may carry the attribute but it has no effect; saving the
class, and loading an app that uses it, reports a warning (devdoc 2026102601 §3.5.2).
