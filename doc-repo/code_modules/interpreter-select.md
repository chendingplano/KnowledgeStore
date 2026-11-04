# Code module: `select`

**Code module ID:** `select` \
**Status:** implemented \
**Row in `kb.code_modules`:** `select`, `module_type` `element`, `module_doc` `select.md`, `status` `active` \
**Classes using it:** `select` \
**Frontend code:** `ChenWeb/web/src/lib/wpi/elements/SelectElement.svelte`, registered as
`select` in `codeModules` (`ChenWeb/web/src/lib/wpi/elements/index.ts`) \
**Backend checks:** `codeModules["select"]`, the `select` case of `element()` and `options()`
in `ChenWeb/server/api/wpi/validate.go` \
**Part of:** reusable module `20261026-01`, Web Page Interpreter frontend
(`doc-repo/modules/module-web-page-interpreter-frontend.md`) \
**Design:** devdoc 2026102601 §3.5.1–§3.5.2, §3.8

## What it draws

A caption above a pulldown menu (the browser's native one) with a fixed list of choices.
The first choice is an empty placeholder, in the user's language, that means "no value".
The chosen value is kept in one attribute of the panel's input doc. When a save fails, the
server's errors for that attribute are shown under the pulldown.

## Attributes

| Attribute | Required | Value | What the code does with it |
| --- | --- | --- | --- |
| `label` | yes | text: a string, or one text per language | The caption above the pulldown, in the user's language. |
| `data_binding` | yes | a path such as `$input_doc.category` | Holds the chosen option's value. Save errors are matched to the pulldown by this path. |
| `binding_mode` | yes | `read-only` or `read-write` | `read-write` lets the user choose; `read-only` disables the pulldown. |
| `options` | yes | a list of `{ "value": …, "label": "…" }`; `value` is a string or a number, `label` a string | The choices, in order. Choosing one writes its `value` with its own type, so a number stays a number; choosing the placeholder writes `null`. |
| `validators` | no | an array of validator instances ([validator-primitive.md](validator-primitive.md) §3) | Allowed even when the class copy does not name it. All must pass. They run after a value is chosen and before a save, and again in the backend on save; their errors show under the pulldown. Not checked while `read-only`. |

*Required* means the code cannot work without the attribute: every instance must end up
with a value, set by the instance itself, by its page (`binding_mode`, devdoc §3.2.1) or by
its class's default.

Like every code module, `select` also accepts the size attributes `width`, `height`,
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
| General | `label` | localized-text | One text, or English and Chinese |
| General | `data_binding` | text | A path such as `$input_doc.category` |
| General | `binding_mode` | value-picker | `read-only`, `read-write` |
| General | `options` | json | The list of `{ value, label }` |
| Validators | `validators` | validator-list | The element's validator instances; each then has a group of its constraints ([validator-primitive.md](validator-primitive.md) §7) |
| Size | `width`, `height`, `min_width`, `max_width` | length | `auto`, `elastic`, or a number in px, rem, em or %; a bare number means px |

## Limits

- Option labels are plain strings, the same in every language (devdoc §9).
- The options are written in the descriptor; they cannot be loaded from data.
- Only one option can be chosen.

## Changing this module

1. Add or change the attribute in the table above.
2. Have a coding assistant such as Claude Code change the code to match: the component
   above, the module's entries in `validate.go`, and the `ElementInstance` type in
   `ChenWeb/web/src/lib/wpi/types.ts`.

Until both are done, a class may carry the attribute but it has no effect; saving the
class, and loading an app that uses it, reports a warning (devdoc 2026102601 §3.5.2).
