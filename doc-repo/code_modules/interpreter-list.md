# Code module: `list`

**Code module ID:** `list` \
**Status:** implemented \
**Row in `kb.code_modules`:** `list`, `module_type` `element`, `module_doc` `list.md`, `status` `active` \
**Classes using it:** `list` \
**Frontend code:** `ChenWeb/web/src/lib/wpi/elements/ListElement.svelte`, registered as `list`
in `codeModules` (`ChenWeb/web/src/lib/wpi/elements/index.ts`) \
**Backend checks:** `codeModules["list"]`, the `list` case of `element()` and `listColumns()`
in `ChenWeb/server/api/wpi/validate.go` \
**Part of:** reusable module `20261026-01`, Web Page Interpreter frontend
(`doc-repo/modules/module-web-page-interpreter-frontend.md`) \
**Design:** devdoc 2026102601 §3.5.1–§3.5.2, §3.6

## What it draws

A table-like list of records, one record per row, under a header row of column labels. The
list reads its own records: it runs its `source` when it is first drawn, and again each
time its page is shown again if the page sets `"refresh": { "on_show": true }`. While
loading it shows a loading message, on failure an error box, and with no records an empty
message, all in the user's language.

## Attributes

| Attribute | Required | Value | What the code does with it |
| --- | --- | --- | --- |
| `source` | yes | a `load` or `query` action instance that returns a list | Run to read the records; its `args` are passed with it. It holds an action, so a class can neither give it a default nor fix it. |
| `presentation` | yes | `rows` | Only `rows` exists. The validator accepts nothing else; the code always draws rows. |
| `columns` | yes | a list of `{ "field": …, "label": …, "width": … }` | One column each. `field` is the record attribute shown, a plain name such as `user_name`; `label` is the header text; `width` is a length, `auto`, or `elastic`, which shares the free space and is used when `width` is left out. A cell holding an object is shown as JSON. |
| `width` | no | "auto" or an integer in px | The list's width |
| `height` | no | "auto" or an integer in px | The list's height|
| `pagination` | no | "yes" or "no", default "yes" | Client-side pagination, 20 records per page. Previous/next controls and page/record counts use the user's language. "no" shows all returned records. Reloading the source returns to page 1. |
| `on_row_click` | no | an action instance of `save`, `open-page`, `close-page` or `save-page` | When set, every row can be clicked and runs it, with `$record` meaning the clicked row's record. It holds an action, so a class can neither give it a default nor fix it. |

*Required* means the code cannot work without the attribute: every instance must end up
with a value, set by the instance itself or by its class's default.

Like every code module, `list` also accepts size strings for `width`, `height`,
`min_width` and `max_width` (lengths, `auto`, or `elastic`). In addition, list `width`
and `height` accept non-negative integers in pixels. The layouter applies these sizes
(devdoc §3.7). A fixed-height list scrolls its records while keeping pagination controls visible.

## Limits

- Read-only: records cannot be edited in the list.
- Rows only; no cards or other presentations.
- No sorting or filtering. Paging operates on records already returned by `source`;
  it does not fetch additional records or override the source's result limit.
- Column labels are plain strings, the same in every language (devdoc §9).
- A list on a visible page is not refreshed when a record it shows is saved in another
  pane (devdoc §9).

## Changing this module

1. Add or change the attribute in the table above.
2. Have a coding assistant such as Claude Code change the code to match: the component
   above, the module's entries in `validate.go`, and the `ElementInstance` type in
   `ChenWeb/web/src/lib/wpi/types.ts`.

Until both are done, a class may carry the attribute but it has no effect; saving the
class, and loading an app that uses it, reports a warning (devdoc 2026102601 §3.5.2).
