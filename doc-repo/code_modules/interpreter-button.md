# Code module: `button`

**Code module ID:** `button` \
**Status:** implemented \
**Row in `kb.code_modules`:** `button`, `module_type` `element`, `module_doc` `button.md`, `status` `active` \
**Classes using it:** `button` \
**Frontend code:** `ChenWeb/web/src/lib/wpi/elements/ButtonElement.svelte`, registered as `button`
in `codeModules` (`ChenWeb/web/src/lib/wpi/elements/index.ts`) \
**Backend checks:** `codeModules["button"]` and the `button` case of `element()` in
`ChenWeb/server/api/wpi/validate.go` \
**Part of:** reusable module `20261026-01`, Web Page Interpreter frontend
(`doc-repo/modules/module-web-page-interpreter-frontend.md`) \
**Design:** devdoc 2026102601 §3.5.1–§3.5.2

## What it draws

A button that runs an action when it is clicked, drawn with ChenWeb's own button
component. While the action runs the button is disabled, so a second click cannot run it
again.

## Attributes

| Attribute | Required | Value | What the code does with it |
| --- | --- | --- | --- |
| `label` | yes | text: a string, or one text per language | The button's text, in the user's language. |
| `on_click` | yes | an action instance of `save`, `open-page`, `close-page` or `save-page` | Run when the button is clicked. It holds an action, so a class can neither give it a default nor fix it. |

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
| Size | `width`, `height`, `min_width`, `max_width` | length | `auto`, `elastic`, or a number in px, rem, em or %; a bare number means px; a note under `width` says the panel's limits also apply |

## Limits

- It always looks like the theme's default button: there are no attributes for variants,
  size, icons or colour.
- It cannot ask for confirmation before running its action.

## Changing this module

1. Add or change the attribute in the table above.
2. Have a coding assistant such as Claude Code change the code to match: the component
   above, the module's entries in `validate.go`, and the `ElementInstance` type in
   `ChenWeb/web/src/lib/wpi/types.ts`.

Until both are done, a class may carry the attribute but it has no effect; saving the
class, and loading an app that uses it, reports a warning (devdoc 2026102601 §3.5.2).
