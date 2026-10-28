# Code module: `text`

**Code module ID:** `text` \
**Status:** implemented \
**Row in `kb.code_modules`:** `text`, `module_type` `element`, `module_doc` `text.md`, `status` `active` \
**Classes using it:** `text` \
**Frontend code:** `ChenWeb/web/src/lib/wpi/elements/TextElement.svelte`, registered as `text`
in `codeModules` (`ChenWeb/web/src/lib/wpi/elements/index.ts`) \
**Backend checks:** `codeModules["text"]` and the `text` cases of `element()` and
`elementComplete()` in `ChenWeb/server/api/wpi/validate.go` \
**Part of:** reusable module `20261026-01`, Web Page Interpreter frontend
(`doc-repo/modules/module-web-page-interpreter-frontend.md`) \
**Design:** devdoc 2026102601 §3.5.1–§3.5.2, §3.8

## What it draws

One paragraph of text: either a fixed string written in the descriptor, or the value of an
attribute of the panel's input doc, which the paragraph follows as it changes. Long text
wraps. A number or other non-text value is shown as text; a missing value shows nothing.

## Attributes

| Attribute | Required | Value | What the code does with it |
| --- | --- | --- | --- |
| `text` | exactly one of `text` and `data_binding` | a string | Shown as written. |
| `data_binding` | exactly one of `text` and `data_binding` | a path such as `$input_doc.title` | The attribute's current value is shown. The text never writes to it. |

Every instance must end up with exactly one of the two, set by the instance itself or by
its class's default.

Like every code module, `text` also accepts the size attributes `width`, `height`,
`min_width` and `max_width`. The layouter applies them (devdoc §3.7); this code does not
read them.

## Limits

- `text` is a plain string, the same in every language (devdoc §9), and so is a bound
  value.
- There are no attributes for headings, size, weight or colour; the text follows the theme.
- An object or list value is not formatted.

## Changing this module

1. Add or change the attribute in the table above.
2. Have a coding assistant such as Claude Code change the code to match: the component
   above, the module's entries in `validate.go`, and the `ElementInstance` type in
   `ChenWeb/web/src/lib/wpi/types.ts`.

Until both are done, a class may carry the attribute but it has no effect; saving the
class, and loading an app that uses it, reports a warning (devdoc 2026102601 §3.5.2).
