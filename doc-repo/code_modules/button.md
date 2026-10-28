# Code module: `button`

**Code module ID:** `button` \
**Status:** implemented \
**Classes using it:** `button` \
**Frontend code:** `ChenWeb/web/src/lib/wpi/elements/ButtonElement.svelte`, registered as `button`
in `elementClasses` (`ChenWeb/web/src/lib/wpi/elements/index.ts`) \
**Backend checks:** `elementAttrs["button"]` and the `button` case of `element()` in
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

## Limits

- It always looks like the theme's default button: there are no attributes for variants,
  size, icons or colour.
- It cannot ask for confirmation before running its action.

## Changing this module

1. Add or change the attribute in the table above.
2. Have a coding assistant such as Claude Code change the code to match: the component
   above, the module's entries in `validate.go`, and the `ElementInstance` type in
   `ChenWeb/web/src/lib/wpi/types.ts`.

Until both are done, a class may carry the attribute but it has no effect (devdoc
2026102601 §3.5.2). Until `code_module_id` is built, the server instead refuses, in an
active class, an attribute this code does not support.
