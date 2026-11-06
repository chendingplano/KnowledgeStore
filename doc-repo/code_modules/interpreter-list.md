# Code module: `list`

**Code module ID:** `list` \
**Status:** implemented; class version 5 adds light/dark color options \
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
| Data | `source` | data-source | Table (Pick Table), fields (Pick Fields), row limit, action (`load`, `query`), result (`list`) and sort order (sort-order) |
| Columns | `columns` | column-list | Label, field and width of each column |
| Columns | `presentation` | value-picker | `rows` |
| Columns | `pagination` | value-picker | `yes`, `no`, or unset for the default |
| Columns | `on_row_click` | json | An action instance |
| Size | `width`, `height`, `min_width`, `max_width` | length | `auto`, `elastic`, or a number in px, rem, em or %; a bare number means px |

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

## Color properties

**Status: implemented.** The user approved revision 1 on 2026-11-06. The `list` class
version 4 adds these fields; version 5 enables light/dark values; existing page instances retain their embedded class copies.

The request's “single-row” is interpreted here as **odd-numbered row**. The first record
is odd; the second is even. The user approved this interpretation.

All four attributes are flat members of a list instance (for example,
`/panels/main/elem_list/0/background_color`), rather than members of a nested `colors`
object. Each is a CSS color string or an object with `light` and `dark` CSS color strings, accepted by the existing color-picker value editor and WPI
CSS-color validation rules; invalid supplied values are descriptor validation errors.
The class defines each with `help_tip`, the default below and `scope: instance` (modifiable);
standard class-fixed and instance override rules apply if a class author changes that
flag. Explicit instance values take precedence over class defaults. Reset removes the
instance override. These attributes are optional on instances because the class supplies
non-null defaults.

| Properties group | Label | Attribute | Class default | Effect |
| --- | --- | --- | --- | --- |
| Colors | Background color | `background_color` | `transparent` | Background of the whole list, including its header, empty space and pagination area. The parent surface shows through when transparent. |
| Colors | Font color | `font_color` | `inherit` | Inherited text color for the list, including header, records, messages and pagination; error messages retain any explicit error-state color. |
| Colors | Single-row background color | `odd_row_background_color` | `transparent` | Background of odd-numbered data rows, beginning with the first record; transparent reveals the list background. |
| Colors | Even-row background color | `even_row_background_color` | `transparent` | Background of even-numbered data rows; transparent reveals the list background. |

Number rows by their position in the returned records, so striping remains consistent
when pagination changes; the header is not a data row. Row colors apply to both clickable
and non-clickable rows. Keep the existing hover and keyboard-focus feedback visible for
clickable rows. The configured font color applies equally to odd and even records.
Loading, empty and error states do not create artificial data rows. The default values
preserve the existing inherited colors and transparent surfaces, including for old class
copies that lack these attributes. An old copy cannot expose these attributes for editing
until refreshed through the normal class-copy workflow.

Add a **Colors** group to the list Properties panel, after **Columns** and before **Size**,
with the four fields in the table order. Each field uses the shared `color-picker` value editor with None, Single color, and Light and dark modes.
Group and labels must be available in English and Chinese. Normal help, fixed-value and
reset behavior applies. The editor and backend must agree on accepted color values; do not
silently accept invalid colors or change them into a different value.

The following is an **abbreviated instance illustration**, not a complete runnable page or
class copy:

```json
{
  "element": "list",
  "background_color": "#ffffff",
  "font_color": "#202020",
  "odd_row_background_color": "#ffffff",
  "even_row_background_color": "#f3f4f6"
}
```

The renderer, Properties editor and backend validator implement these attributes. Migration
`20261106000001_wpi_list_colors.sql` creates class version 4 and `20261106000002_wpi_list_theme_colors.sql` creates version 5 without changing saved copies.
Browser verification covered the four controls and the rendered list, text and alternating
row colors in both light and dark schemes; backend tests cover valid and invalid colors. Existing copies continue to render
with their original appearance. The generic color picker remains independent of these list
attributes and can be reused for other elements.
