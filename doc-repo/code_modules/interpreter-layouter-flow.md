# Flow Layouter

**Layouter ID:** `flow-layouter` \
**Date:** 2026-10-28, revised 2026-10-30 (configured per panel; OpenSpec change `wpi-pages-own-panes`) \
**Status:** implemented and active \
**Frontend code:** `ChenWeb/web/src/lib/wpi/layouters/FlowLayouter.svelte`, registered in
`ChenWeb/web/src/lib/wpi/layouters/index.ts`; sizing in `ChenWeb/web/src/lib/wpi/layout.ts` \
**Backend checks:** page validation in `ChenWeb/server/api/wpi/validate.go` \
**Catalogue:** `kb.code_modules.code_module_id = flow-layouter`, type `element-layouter`, status `active`;
registered by `ChenWeb/project_migrations/20261028000003_register_flow_layouter.sql`, moved to type
`element-layouter` by `20261030000001_wpi_pages_own_panes.sql`. Its class, also `flow-layouter`, is a
row of `kb.wpi_descriptors` with kind `element-layouter` whose `config` holds every parameter's default \
**Design:** [Web Page Interpreter, Element layouters](../devdocs/202610/2026102601-devdoc-web-page-interpreter.md#element-layouters)

## 1. What it does

The Flow Layouter arranges a collection of elements in rows. It puts as many elements
as fit in the current row, then continues on the next row. When the available width
changes, it lays them out again automatically. The elements keep their original order.

A typical use is a collection of cards. A wide page may show four cards per row, a
narrower page two, and a small page one. Authors choose card sizes and spacing rather
than a fixed number of columns. Horizontal alignment positions cards within each row;
vertical alignment positions cards of different heights within that row. The
configuration below makes both choices explicit.

The same layouter can arrange buttons, fields or other page elements. It controls their
outer boxes, not the text alignment, padding or arrangement of content inside them.

## 2. Current behavior

A panel selects this layouter with a copy of the `flow-layouter` class in its
`elem_layouter`: `{"layouter": "flow-layouter", "class": {…}, "config"?: {…}}`. The panel's
`elem_list` supplies the elements in display order, after each instance has been merged with
its class copy by the interpreter. The code that draws the panel is the copy's
`code_module_id`.

The component uses a wrapping horizontal CSS flex container. By default it leaves a
`0.75rem` gap between elements and rows, normally `12px`. Rows start at the horizontal
start edge, and each element aligns to the top of its row. The settings below control
spacing and alignment. A setting missing from the panel's `config`, or from its class copy's
when the panel has none, keeps its default.

Each row is as tall as its tallest element. The following row begins after that height
and the row gap. Shorter elements leave space beneath them; later elements do not move
up into those holes. Flow layout therefore does not produce masonry columns or a grid
with shared column boundaries across rows.

### 2.1 Element sizes

The layouter applies these attributes to each element's wrapper:

| Attribute | Current behavior |
| --- | --- |
| `width`: a length, such as `240px` or `100%` | Uses that width without flex growth or shrinkage, subject to width limits. A percentage is relative to the containing layout width. |
| `width`: `auto`, or omitted | Uses content sizing, without flex growth or shrinkage. |
| `width`: `elastic` | Uses `min_width`, or `0px` when omitted, as its flex basis and shares remaining row width with other elastic elements, subject to width limits. |
| `min_width`, `max_width` | Constrain the element's width. An elastic card should normally have a meaningful minimum so wrapping preserves a usable card width. |
| `height`: a length | Sets the wrapper height. It does not automatically make the element's inner component fill that height. |
| `height`: `auto`, omitted, or `elastic` | Sets no wrapper height. The current code does not distribute spare vertical space for elastic height. |

Wrapping takes the gaps and width constraints into account. Elastic growth happens
within each row after its elements have been placed. A last row with one elastic card
can therefore grow wider than the cards above it; use `max_width` to limit that growth.

A fixed-width element wider than the available area occupies a row by itself and can
still overflow. The current layouter does not silently shrink it to fit. The containing
pane's scrolling policy determines whether overflow remains reachable.

The current `auto` behavior is content sizing. The handoff from layout to a Page Style
fallback described in [Page Styles](interpreter-page-styles.md) is proposed and is not
implemented here.

## 3. Configuration

A panel's own `config` replaces its class copy's `config` whole; without one, the copy's
applies. The class row of `flow-layouter` gives every setting its default, so a panel that
changes one setting lists all of them. The validator rejects non-object configuration,
unknown settings and unsupported values at their descriptor paths, in the panel and in the
copy.

| Setting | Values | Default | Meaning |
| --- | --- | --- | --- |
| `column_gap` | Nonnegative length in `px` or `rem` | `0.75rem` | Minimum space between adjacent elements in a row. |
| `row_gap` | Nonnegative length in `px` or `rem` | `0.75rem` | Minimum space between adjacent rows. |
| `horizontal_alignment` | `start`, `center`, `end`, `space-between` | `start` | Distribution of unused horizontal space in each row. |
| `vertical_alignment` | `top`, `center`, `bottom`, `stretch` | `top` | Placement of elements within their row's height. |
| `rows_alignment` | `top`, `center`, `bottom`, `space-between` | `top` | Placement of the complete set of rows when the layout area has spare vertical space. |

Use logical `start` and `end` for horizontal alignment: in English and Chinese these
normally mean left and right. Configuration belongs to the page's layouter, while each
element retains its own size attributes. Unknown settings, unsupported values and
negative gaps should be validation errors rather than silently ignored instructions.

### 3.1 Horizontal alignment

Resolve element widths, including elastic growth and maximum widths, before distributing
any space left in the row:

- `start`: pack elements at the start edge.
- `center`: centre the row's elements as a group.
- `end`: pack elements at the end edge.
- `space-between`: put the first and last elements at the row's edges and distribute
  extra space between them, in addition to `column_gap`. A row with one element uses
  start alignment.

Apply the rule independently to every row, including the last. If elastic elements
consume all available width, there is no spare space for horizontal alignment to move
them. Alignment never changes element order or chooses different row breaks merely to
balance the last row.

### 3.2 Vertical alignment within a row

For a row containing cards of different heights:

- `top`: align their top edges.
- `center`: centre each card vertically within the row.
- `bottom`: align their bottom edges.
- `stretch`: make cards with auto height fill the row height. Retain explicit heights.

For auto-height elements, the wrapper becomes a vertical flex container and its
rendered roots grow to fill it. A component still controls its own inner content.
Stretching does not stretch text or images, align internal footers, or make cards in
different rows equal in height. A label inside a card still follows that card's own content layout.

### 3.3 Vertical alignment of all rows

`rows_alignment` is separate from alignment within a row. With a definite layout-area
height larger than the rows need, `top`, `center` and `bottom` place the rows as a group.
`space-between` distributes additional vertical space between rows; a single row stays
at the top. The configured `row_gap` remains the minimum separation.

With content height, there is no extra height to distribute. A panel's height comes from
its content (devdoc 2026102601, Panels), so in a panel `rows_alignment` has no effect: the
pane's `vert_align` places the panel as a whole instead. If the rows exceed the available
height, retain top placement and normal overflow so the beginning of the content remains
reachable. Percentage heights still depend on a definite containing height, following CSS
rules.

## 4. Card example

Suppose there are seven cards, each `240px` wide, with `16px` column and row gaps. The
following widths are the usable layout width after surrounding padding:

| Available width | Cards per full row | Rows, in source order |
| --- | --- | --- |
| `1008px` | 4 (`4 × 240 + 3 × 16`) | A B C D / E F G |
| `752px` | 3 (`3 × 240 + 2 × 16`) | A B C / D E F / G |
| `496px` | 2 (`2 × 240 + 16`) | A B / C D / E F / G |
| `240px` | 1 | A / B / C / D / E / F / G |

At `1008px`, the last row occupies `752px`. With horizontal `center`, it has `128px`
of unused space on either side. With `start`, all `256px` is after the last card.
If cards A and B are `180px` and `120px` tall, their row is `180px` high. Vertical
`center` puts B `30px` below the top; `bottom` puts it `60px` below the top.

This **panel fragment** selects centred rows with top-aligned cards (the class copy in
`class` is left out):

```json
"elem_layouter": {
  "layouter": "flow-layouter",
  "config": {
    "column_gap": "16px",
    "row_gap": "16px",
    "horizontal_alignment": "center",
    "vertical_alignment": "top",
    "rows_alignment": "top"
  }
}
```

This fragment is accepted as part of a panel of a complete page descriptor; the panel's
`elem_list` holds the elements, and writing the page adds the class copy. Card elements would supply
their own widths and content. For flexible cards, use `width: elastic` with, for
example, `min_width: 240px` and `max_width: 320px` instead of a fixed width.

The current interpreter has no card element module, and its `list` module supports only
row presentation. These examples describe layout geometry; selecting Flow Layouter
does not create cards or turn list records into card elements. A future collection
renderer must explicitly supply its repeated items to a flow container.

## 5. Boundaries and verification

A page's `width` and `max_width` determine its box within its page area, and a pane's
margins, `hori_align` and `vert_align` place the panel within the pane. Flow layout then
arranges elements inside the panel. Centring a panel in a pane is different from centring
the cards within each row. Elastic and percentage element widths make the panel as wide as
the pane's content area, inside its margins. Card appearance and internal padding
belong to the card component or a supported Page Style; gaps belong to the layouter.
Text remains selectable, and wrapping must preserve reading and keyboard focus order.

The implemented contract remains in the
[page-rendering specification](../../../ChenWeb/openspec/specs/wpi-page-rendering/spec.md).
The panel types, Go validator, flow renderer and sizing helpers implement the same
configuration. Go tests check accepted configurations and invalid values; frontend
unit tests cover defaults and CSS generation. Browser verification of the real Panel
and FlowLayouter covered exact-fit and just-too-narrow rows, pane-width changes,
unequal heights, single-item and single-row space-between, auto-height stretch with
explicit heights retained, definite page height, overflow fallback, elastic maximum
widths, oversized fixed items, selectable English and Chinese text, and keyboard
focus order across wrapped input fields.

The catalogue row records the built-in code and the class row its defaults; panels select
it through their `elem_layouter` copy, without adding element classes. Page Style fallback,
card composition, a card data source and an alignment authoring UI remain outside
this implementation.
