# Page Layouter

**Code module ID:** `page-layouter` \
**Date:** 2026-10-30 \
**Status:** implemented and active \
**Frontend code:** `ChenWeb/web/src/lib/wpi/PaneView.svelte`, chosen by `ChenWeb/web/src/lib/wpi/PageView.svelte`;
pane geometry in `ChenWeb/web/src/lib/wpi/layout.ts` \
**Backend checks:** pane trees and page layouter copies in `ChenWeb/server/api/wpi/validate.go`
(`pageLayouterModules`, `paneTree`, `pageLayouterCopy`) \
**Catalogue:** `kb.code_modules.code_module_id = page-layouter`, type `page-layouter`, status `active`;
registered by `ChenWeb/project_migrations/20261030000001_wpi_pages_own_panes.sql`, which also stores its
classes `single-pane` and `top-left-middle-right-bottom` in `kb.wpi_descriptors` (kind `page-layouter`) \
**Design:** [Web Page Interpreter, Page layouters](../devdocs/202610/2026102601-devdoc-web-page-interpreter.md#page-layouters),
[Panes](../devdocs/202610/2026102601-devdoc-web-page-interpreter.md#panes),
[Opening a page](../devdocs/202610/2026102601-devdoc-web-page-interpreter.md#opening-a-page)

## 1. What it does

The Page Layouter divides a page's space into panes. It draws the pane tree of the page's
`page_layouter` copy: a pane split into `rows` stacks its children from top to bottom, a pane
split into `columns` sets them side by side, and a leaf pane shows its own panel, or a page
opened in it. Every page layouter class is drawn by this one module; the classes differ only
in the tree they give their copies.

## 2. Classes

| Class | Tree |
| --- | --- |
| `single-pane` | One leaf pane, `main`. |
| `top-left-middle-right-bottom` | Rows `top` (48px), `middle-row` and `bottom` (32px); `middle-row` split into columns `left` (240px, at least 160px, resizable), `middle` and `right` (at least 400px). |

A page copies a class into its `page_layouter`: `{"layouter": <class>, "class": <class row>,
"root"?: <tree>}`. The page's own `root`, when set, replaces the copy's whole, so a page may
leave panes out, add panes or change their attributes. Saving a page adds the class copy
when it has none.

## 3. Attributes of a pane

| Attribute | Applies to | Values | What the code does with it |
| --- | --- | --- | --- |
| `pane_id` | every pane | lowercase letters, digits and hyphens, unique in the page | Names the pane; a leaf's panel is keyed by it in `panels`; `open-page` names panes by it. |
| `split`, `children` | split panes | `rows` or `columns`; two or more panes | Lays the children out in a column or a row (CSS flex). |
| `width`, `height` | every pane | a length (`px`, `rem`, `em`; `px` when left out), a percentage, `elastic` (default) or `auto` | The size along the parent's axis: fixed, a share of the parent, what fixed, percentage and `auto` siblings leave (shared by `elastic` siblings), or the content's size. The root's size is not used; the page's own sizes apply. |
| `min_width`, `min_height` | every pane | a length or a percentage, default `50px` | Lower limits. |
| `max_width`, `max_height` | every pane | a length or a percentage | Upper limits. |
| `resizable` | every pane | `true` or `false` (default) | With a pixel size along the parent's axis, a drag handle on the edge facing the next sibling (the previous one for the last child) changes the size within the limits while the app runs. |
| `left_margin`, `right_margin`, `top_margin`, `bottom_margin` | leaf panes | a length, default `0px` | Space between the pane's edges and what it shows; counted when deciding whether it fits. |
| `hori_align`, `vert_align` | leaf panes | `left`, `center` (default), `right`; `top` (default), `center`, `bottom` | Where a smaller panel or page sits inside the margins. |
| `hori_scrollbar`, `vert_scrollbar` | leaf panes | `auto` (default) or `hide` | When the content and the margins do not fit: a scroll bar, or clipping. |

The leaf-only attributes on a split pane are validation errors. Split panes are separated by
a line in the theme's border colour.

### 3.1 Property editor

The WPI Editor shows a pane's properties when *Panes* is chosen (the root pane when no pane
is selected) or a pane is clicked in the preview. Above the groups are the pane tree, to choose
another pane, and the commands to split, add, merge and delete panes. The editor is
drawn at run time from `ChenWeb/web/src/lib/wpi/properties/page.ts` (OpenSpec
`wpi-property-editors`); the table is the contract that file follows. Labels and help tips
are Paraglide messages (`wpi_prop_*`) in English and Chinese; a non-empty tip shows as an
info icon at the upper right of the value editor. *Reset* removes the attribute. Value
editors are described in devdoc 2026102701 §1.3.9.

| Group | Attribute | Value editor | Data and rules |
| --- | --- | --- | --- |
| Pane | `pane_id` | text | Applied on leaving the field or Enter; refused when invalid or already used. Renaming moves the panel and elements. No *Reset* |
| Pane | position | read-only | x and y in page pixels from the page's top-left corner |
| Size | `width`, `height` | length | `auto`, `elastic`, or a number in px, rem, em or % |
| Size | `min_width`, `min_height`, `max_width`, `max_height` | length | A number in px, rem, em or % |
| Size | `resizable` | switch | |
| Margins (leaf panes) | `left_margin`, `right_margin`, `top_margin`, `bottom_margin` | length | px, rem or em |
| Colors and border | `background_color`, `foreground_color` | color | None, one CSS colour, or light and dark |
| Colors and border | `border_thickness` | length | px |
| Colors and border | `border_light_color`, `border_dark_color` | color | None or one CSS colour |
| Content placement (leaf panes) | `hori_align`, `vert_align` | value-picker | `left`, `center`, `right`; `top`, `center`, `bottom`; or unset |
| Content placement (leaf panes) | `hori_scrollbar`, `vert_scrollbar` | switch | On stores `auto`, off stores `hide` |

## 4. A page opened in a pane

When a page is opened in a leaf pane of another page, that pane takes the place of the page's
root pane. The host pane keeps its geometry, margins, alignment and scroll bars, which apply
instead of the root's and the page's own; the page's sizes and colours still apply. A
single-pane page's panel is drawn directly in the host pane; a page with more panes has its
root's children drawn inside it. The pages opened in a pane are kept by the runtime's Panel
Cache: hidden ones stay mounted and hidden with CSS.

## 5. Verification

Go tests check pane trees, leaf-only attributes, page layouter copies and classes
(`validate_test.go`, `bundle_test.go`, `seed_test.go`); frontend unit tests cover the tree
helpers and the CSS (`layout.test.ts`). A browser run on 2026-10-30 checked the
`customer-admin` app (home page with a menu, pages opened in `middle` and `right`) and the
editor's split of a single-pane page into two columns. Dragging a pane's edge was not
checked in a browser.
