# Code module: `menu`

**Code module ID:** `menu` \
**Status:** implemented \
**Classes using it:** `menu` \
**Frontend code:** `ChenWeb/web/src/lib/wpi/elements/MenuElement.svelte`, registered as `menu`
in `elementClasses` (`ChenWeb/web/src/lib/wpi/elements/index.ts`) \
**Backend checks:** `elementAttrs["menu"]`, the `menu` cases of `element()` and
`elementComplete()`, and `menuItems()` in `ChenWeb/server/api/wpi/validate.go` \
**Part of:** reusable module `20261026-01`, Web Page Interpreter frontend
(`doc-repo/modules/module-web-page-interpreter-frontend.md`) \
**Design:** devdoc 2026102601 §3.3, §3.5.1–§3.5.3

## What it draws

A tree of menu items. A folder shows a folder icon and opens or closes when clicked; every
folder starts open. An item shows a file icon, and clicking it runs its `on_click`, usually
an `open-page`. The item whose panel is being shown is highlighted. When the menu is first
drawn, normally when the app starts, it clicks its `initial_item`. The menu keeps the
bindings between its items and their panels (devdoc §3.3), separately for each menu
instance.

## Attributes

| Attribute | Required | Value | What the code does with it |
| --- | --- | --- | --- |
| `items` | yes | a list of items, each `{ "item_id": …, "label": …, "on_click": … }` or `{ "item_id": …, "label": …, "children": [ … ] }` | The menu tree. `item_id` is lowercase letters, digits and hyphens, unique within the menu; `label` is the text shown; an item has exactly one of `on_click` (an action instance of `save`, `open-page`, `close-page` or `save-page`) and `children`, which makes it a folder. It holds actions, so a class can neither give it a default nor fix it. |
| `initial_item` | no | an `item_id` | The item clicked when the menu is first drawn. It must be an item with `on_click`, not a folder. |

*Required* means the code cannot work without the attribute: every instance must end up
with a value, set by the instance itself or by its class's default.

Like every code module, `menu` also accepts the size attributes `width`, `height`,
`min_width` and `max_width`. The layouter applies them (devdoc §3.7); this code does not
read them.

## Limits

- Item labels are plain strings, the same in every language (devdoc §9).
- Items cannot have their own icons.
- Which folders are open is not remembered when the app is reloaded.

## Changing this module

1. Add or change the attribute in the table above.
2. Have a coding assistant such as Claude Code change the code to match: the component
   above, the module's entries in `validate.go`, and the `ElementInstance` and `MenuItem`
   types in `ChenWeb/web/src/lib/wpi/types.ts`.

Until both are done, a class may carry the attribute but it has no effect (devdoc
2026102601 §3.5.2). Until `code_module_id` is built, the server instead refuses, in an
active class, an attribute this code does not support.
