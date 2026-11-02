# Code module: `menu`

**Code module ID:** `menu` \
**Status:** implemented \
**Row in `kb.code_modules`:** `menu`, `module_type` `element`, `module_doc` `menu.md`, `status` `active` \
**Classes using it:** `menu` \
**Frontend code:** `ChenWeb/web/src/lib/wpi/elements/MenuElement.svelte`, registered as `menu`
in `codeModules` (`ChenWeb/web/src/lib/wpi/elements/index.ts`) \
**Backend checks:** `codeModules["menu"]`, the `menu` cases of `element()` and
`elementComplete()`, and `menuItems()` in `ChenWeb/server/api/wpi/validate.go` \
**Part of:** reusable module `20261026-01`, Web Page Interpreter frontend
(`doc-repo/modules/module-web-page-interpreter-frontend.md`) \
**Design:** devdoc 2026102601 §3.3, §3.5.1–§3.5.3

## What it draws

A tree of menu items. A folder shows a folder icon and opens or closes when clicked; every
folder starts open. An item shows a file icon, and clicking it runs its `on_click`, usually
an `open-page`. An item is highlighted while the pane its `open-page` opens a page in shows
that page with the item's input. When the menu is first drawn, which is when the page
holding it is opened, it clicks its `initial_item`. Clicking an item again shows the page
instance the Panel Cache kept for that pane, without reloading it (devdoc 2026102601, Panel
Cache); the menu keeps no bindings of its own.

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
| Items | `items` | json | The menu tree |
| Items | `initial_item` | value-picker | The `item_id`s in `items` that have no children; unset means the first |
| Size | `width`, `height`, `min_width`, `max_width` | length | `auto`, `elastic`, or a number in px, rem, em or %; a bare number means px |

## Limits

- Item labels are plain strings, the same in every language (devdoc §9).
- Items cannot have their own icons.
- Which folders are open is not remembered when the app is reloaded.

## Changing this module

1. Add or change the attribute in the table above.
2. Have a coding assistant such as Claude Code change the code to match: the component
   above, the module's entries in `validate.go`, and the `ElementInstance` and `MenuItem`
   types in `ChenWeb/web/src/lib/wpi/types.ts`.

Until both are done, a class may carry the attribute but it has no effect; saving the
class, and loading an app that uses it, reports a warning (devdoc 2026102601 §3.5.2).
