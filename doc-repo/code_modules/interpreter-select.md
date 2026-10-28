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

*Required* means the code cannot work without the attribute: every instance must end up
with a value, set by the instance itself, by its page (`binding_mode`, devdoc §3.2.1) or by
its class's default.

Like every code module, `select` also accepts the size attributes `width`, `height`,
`min_width` and `max_width`. The layouter applies them (devdoc §3.7); this code does not
read them.

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
