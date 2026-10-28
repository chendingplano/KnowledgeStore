# Code module: `input`

**Code module ID:** `input` \
**Status:** implemented \
**Classes using it:** `input` \
**Frontend code:** `ChenWeb/web/src/lib/wpi/elements/InputElement.svelte`, registered as `input`
in `elementClasses` (`ChenWeb/web/src/lib/wpi/elements/index.ts`) \
**Backend checks:** `elementAttrs["input"]` and the `input` case of `element()` in
`ChenWeb/server/api/wpi/validate.go` \
**Part of:** reusable module `20261026-01`, Web Page Interpreter frontend
(`doc-repo/modules/module-web-page-interpreter-frontend.md`) \
**Design:** devdoc 2026102601 §3.5.1–§3.5.2, §3.8

## What it draws

A caption above a one-line field, drawn with ChenWeb's own input component. The field
shows one attribute of the panel's input doc and, when it is editable, writes every change
back to it. When a save fails, the server's errors for that attribute are shown under the
field.

## Attributes

| Attribute | Required | Value | What the code does with it |
| --- | --- | --- | --- |
| `label` | yes | text: a string, or one text per language | The caption above the field, in the user's language. |
| `data_binding` | yes | a path such as `$input_doc.email` | The field shows this attribute's value and writes changes to it. Save errors are matched to the field by this path. |
| `binding_mode` | yes | `read-only` or `read-write` | `read-write` lets the user edit; `read-only` makes the field read-only, though its text can still be selected and copied. |
| `input_type` | no | `text`, `number` or `email` | The kind of field; `text` when not set. With `number`, an empty field writes `null`, a number writes a JSON number, and anything else is kept as typed text, so the server can report it. |

*Required* means the code cannot work without the attribute: every instance must end up
with a value, set by the instance itself, by its page (`binding_mode`, devdoc §3.2.1) or by
its class's default.

Like every code module, `input` also accepts the size attributes `width`, `height`,
`min_width` and `max_width`. The layouter applies them (devdoc §3.7); this code does not
read them.

## Limits

- One line only; there is no multi-line field.
- No placeholder text and no help text under the field.
- Values are checked only by the server when the page is saved, not as the user types.

## Changing this module

1. Add or change the attribute in the table above.
2. Have a coding assistant such as Claude Code change the code to match: the component
   above, the module's entries in `validate.go`, and the `ElementInstance` type in
   `ChenWeb/web/src/lib/wpi/types.ts`.

Until both are done, a class may carry the attribute but it has no effect (devdoc
2026102601 §3.5.2). Until `code_module_id` is built, the server instead refuses, in an
active class, an attribute this code does not support.
