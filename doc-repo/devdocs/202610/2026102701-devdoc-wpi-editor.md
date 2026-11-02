# 1. WPI Editor — a canvas for laying out WPI pages, elements and actions

**Date:** 2026-10-27 \
**Scope:** What the WPI Editor in ChenWeb is today, what each control does, how it stores
its work, and what is missing. Read this before extending the editor or
connecting it to WPI descriptors. The Web Page Interpreter itself is described in devdoc
[2026102601](2026102601-devdoc-web-page-interpreter.md) (design) and
[2026102603](2026102603-devdoc-wpi-pilot.md) (what was built). \
**Code root:** `ChenWeb/web/src/lib/components/shared-ui/wpi-editor.svelte`

## 1.1 Summary

The WPI Editor is a drawing board inside ChenWeb, opened from **Development → Tools → WPI
Editor**. It is meant to become the place where people build Web Page Interpreter (WPI)
pages by arranging boxes on a canvas instead of writing descriptions by hand. Today it is
an early shell. You can add boxes for pages, elements and actions, draw lines between
boxes, line boxes up with alignment tools, and undo or redo your changes. It also still
offers the general building blocks it inherited from the Flow page it was copied from.

The editor loads stored WPI pages into separate tabs. Save writes the current page and its
updated element instances as a new active descriptor version. Only administrators can save;
server validation errors are shown to the author. Empty canvases and canvases containing
non-element nodes or connections cannot yet be saved. Flow management and template saving
still use placeholder endpoints.

## 1.2 What is on the screen

- **Left — node palette.** Building blocks you can drag onto the canvas, in folders
  (AI, Data, Actions, plus empty Pages and Elements folders kept for WPI). Folders start
  folded; typing in the search box opens every folder with a match.
- **Middle — tool bar and canvas.** The tool bar runs along the top of the canvas (table
  below). The canvas has zoom controls at the bottom left, an overview map at the bottom
  right, and a gear button at the top right for line style and grid settings.
- **Right — properties.** When exactly one box is selected, it is edited here on two tabs:
  **Properties** (its name and settings) and **Node** (its descriptor, the JSON *View JSON*
  shows, as name/value rows to add, rename, change and remove). Drag the panel's left edge
  to make it wider or narrower (200–640 px; it starts at 390 px).
- **Above a selected box — its tool bar.** **Duplicate** adds a copy one grid cell down and
  right (further while another box sits there), with the same data and size, and selects
  it; lines are not copied. **Delete** removes the box and every line attached to it. Both
  can be undone. An element box also has **Edit class** (pencil), which opens the Create
  Element form on the box's class (below).

The Panes and Panel properties include `background_color` and `foreground_color`. Choose no color, one color, or separate light and dark colors. Use the color picker or enter a CSS color in the adjacent field; choose None to leave it unset. The canvas preview follows the editor theme and inherits each unset pane color from the closest ancestor and gives the effective pane background precedence over its panel background.

### 1.2.1 Tool bar

| Control | What it does | Available when |
|---|---|---|
| Flow name | Click to rename the current canvas; a yellow dot means unsaved changes | Always |
| ▾ next to the name | Opens the picker of saved canvases (My Flows / Shared Flows / Templates); asks first if there are unsaved changes | Always |
| **Create Nodes ▾** | Menu: **Create Page**, **Create Element**, **Create Action** — adds that kind of box in the middle of the visible canvas | Always |
| **Load Page** | Searches stored pages and opens one in a new tab | Always |
| **Code ▾** | **View JSON** opens the selected node’s descriptor, or the page descriptor if no node is selected; **View element tree** shows the page’s pane hierarchy, with a panel, its layouter name and element list under each leaf pane; element classes appear in reading order | In edit mode |
| Undo / Redo | Steps back or forward through changes | When there is something to undo / redo |
| Align left / horizontal centres / right | Lines the selected boxes up on that edge or centre line | Two or more boxes selected |
| Align top / vertical centres / bottom | Same, vertically | Two or more boxes selected |
| Distribute horizontally / vertically | Keeps the outermost selected boxes in place and spaces the ones between them evenly | Three or more boxes selected |
| Save | Saves the loaded page as a new active descriptor version (admin only) | Always |
| Save as template | Saves the canvas as a template — **currently stores nothing** | Always |

To select several boxes, hold ⌘ (Ctrl on Windows/Linux) while clicking them.

## 1.3 Details

### 1.3.1 Where it lives

| File | Role |
|---|---|
| `web/src/lib/components/shared-ui/wpi-editor.svelte` | The editor: state, undo/redo, create/align/distribute, save, canvas, settings panel |
| `web/src/lib/components/shared-ui/canvas/WpiCanvasToolbar.svelte` | The tool bar (presentational; all actions are callbacks into the editor) |
| `web/src/lib/components/shared-ui/canvas/WpiTreeDialog.svelte`, `wpi-json.ts` | Read-only element tree, assembled from the current canvas using the same pane assignment and reading order as the page descriptor |
| `web/src/lib/components/shared-ui/canvas/align-nodes.ts` | Pure align/distribute functions; tests in `align-nodes.test.ts` (`bun test`) |
| `web/src/lib/components/shared-ui/canvas/nodes/WpiNode.svelte` | Renders the three WPI node types; icon chosen by node type |
| `web/src/lib/components/shared-ui/canvas/{NodePalette,PropertiesPanel,FlowPicker}.svelte`, `nodes/*` | Shared with the Flow page (`canvas-01.svelte`) |
| `web/src/lib/components/shared-ui/canvas/NodeDescriptorEditor.svelte`, `node-descriptor.ts` | The properties panel's Node tab; only the WPI editor turns it on (`nodeTab`), so the Flow page's panel has no tabs |
| `web/src/lib/components/shared-ui/canvas/node-actions.ts` | The box tool bar's Duplicate and Delete: each canvas provides them through Svelte context (`setNodeActions`) and `nodes/BaseNode.svelte` calls them; pure `duplicateNode`/`removeNode`, tests in `node-actions.test.ts`. The Flow page provides them too |
| `web/src/lib/components/shared-ui/canvas/CreateElementDialog.svelte` | Create Element, and, given a `classId`, Edit class: loads the class's latest row, keeps its ID, updates its existing row in place |
| `web/src/lib/components/shared-ui/canvas/canvas-theme.ts` | Dark and light colours of the canvas editors, as `--cv-*` CSS variables |
| `web/src/lib/services/flowService.ts` | Client for `/api/v1/flows*` and `/api/v1/flow-node-types` |
| `server/api/flowhandler/` | Server handlers for those endpoints — **stubs** (below) |

- Menu entry: `nav-rail.svelte` child id `wpi-editor` (label `m.nav_wpi_editor()`), rendered
  by `home3/content-panel.svelte`. URL: `/development?view=tools&child=wpi-editor`.
- The editor is a `position: fixed` overlay (`z-index: 40`) covering the content panel.
  Left edge = the nav rail width (`railOffset` prop). Top edge = `calc(4.25rem + 1px)`, the
  height of the sticky site header (`routes/semos/components/SiteHeader.svelte`,
  `h-[4.25rem]` plus a 1px border, `z-50`). **If the site header's height changes, change
  this offset**, or the header will cover the tool bar again (it did until 2026-10-27).
- Built on Svelte Flow (`@xyflow/svelte` 1.5.1).
- **Light and dark.** The editor follows the site theme through its `darkMode` prop. Its
  root sets the colours from `canvas-theme.ts` as `--cv-*` CSS variables
  (`canvasThemeVars(darkMode)`), and the palette, tool bar, properties panel and nodes read
  them with `var(--cv-…)` — **use these variables, not hex colours, in anything inside
  the editor**. Two exceptions: the Create Element dialog and the flow picker render
  outside the root, so each sets the variables on its own backdrop; and the Create Nodes
  menu opens in a portal, so it keeps the site theme's own menu colours. Svelte Flow's
  zoom controls, overview map and lines follow its `colorMode` prop. Text is black in light
  mode and white in dark mode at every level (`--cv-text`, `-text-2`, `-text-muted`,
  `-text-faint`); size and weight set the levels apart. Headings in the accent colour
  (NODE PALETTE, PROPERTIES) and red delete/error text are the exceptions.
- The Flow page shares the palette, properties panel, picker and nodes but has no light
  theme yet, so it passes the dark colours (`canvasThemeVars(true)`, `darkMode={true}` to
  the picker); its text is white too.

### 1.3.2 Node types

- **From the server:** `GET /api/v1/flow-node-types` returns 11 hard-coded types
  (`server/api/flowhandler/nodetypes.go`): AI — `ai-assistant`, `coding-assistant`;
  Data — `text`, `document`, `file`, `media`; Actions — `tool`, `mcp`, `http-request`,
  `rule`, `git`. These appear in the palette. The palette also shows empty `Pages` and
  `Elements` folders (`WPI_PALETTE_CATEGORIES`).
- **WPI node types (client only):** `wpi-page`, `wpi-element`, `wpi-action`, defined in
  `WPI_NODE_TYPES` in `wpi-editor.svelte`. They are created only from the tool bar and are
  not in the palette. Each has one input handle and one output handle, and
  `defaultData: {}`, so a node's data is just `{ label }` and the properties panel shows
  only its name. The label is the type name ("Page", "页面", …) in the language active
  when the node was created, stored as plain text.
- **Placement on create:** the centre of the visible canvas minus half the minimum node size
  (160 × 60), snapped to the grid when snap is on. If another node already sits at exactly
  that position, the new one moves one grid cell down and right until the spot is free.

### 1.3.3 Editing behaviour

- **Align / distribute** (`align-nodes.ts`): act on nodes with `selected: true`. Align
  needs two and distribute three; with fewer, the functions return the input unchanged
  and the buttons are disabled. Sizes come from `node.measured`, falling back to
  `width`/`height`, then 0. Results are **not** snapped to the grid, because snapping would
  undo centre alignment. Distribute orders nodes by their left (or top) edge, keeps the
  first and last in place, and sets equal gaps; overlapping nodes give a negative gap.
- **Undo / redo:** full snapshots of the page descriptor, preview size, nodes and edges, at
  most 50 undo steps. A step is recorded before every change: create, palette drop,
  duplicate, delete (tool bar or Backspace), the start of a drag, page and pane resizing,
  new edge, align, distribute, edge-style change, edits in the properties panel (both
  tabs) and in View JSON, page, pane and panel settings, and pane split, merge, add,
  delete, rename and move. Typing in an element's property field records one step per
  keystroke, so undoing a typed value takes one step per character and uses up the 50
  steps quickly.
- **Keyboard:** ⌘/Ctrl+Z undo; ⌘/Ctrl+Y or ⌘/Ctrl+Shift+Z redo; ⌘/Ctrl+S save;
  Backspace deletes the selection (Svelte Flow default).
- **Edges:** dragged from an output handle to an input handle. A second edge between the
  same two handles is ignored.
- **Canvas settings (gear):** edge style — curve, step, rounded step or straight. It
  applies to all existing edges and to new ones. Also grid resolution (1–50, default 20)
  and snap to grid (default on).
- **Zoom:** on load the canvas fits all nodes, but never zooms in past 100%
  (`fitViewOptions={{ maxZoom: 1 }}`). Without that cap, an empty canvas waits for its
  first node and then zooms to 200%.
- **Unsaved changes:** "dirty" means the canvas, page configuration, preview size or flow name differs from
  its saved baseline. Closing a dirty tab asks for confirmation; switching tabs preserves it.
- **Size warnings:** a one-time message above 500 nodes or 1000 edges.

### 1.3.4 Storage

For a loaded WPI page, Save sends the page descriptor and the current element instances
to `PUT /api/v1/wpi/descriptors/page/:descriptorId`. The server validates the descriptor
and its instances and stores a new active version in `kb.frontend_pages`. The dirty marker
clears only after a successful response. Page configuration is preserved, and element order
follows canvas order. Canvas viewport, preview size, and flow-only nodes and connections
are not part of the page descriptor; saving a canvas with non-element nodes or connections
is rejected. An empty canvas without a page descriptor cannot yet be saved.

Flow picker, new-flow and template endpoints under `server/api/flowhandler/` remain stubs;
they do not persist canvases. The separate Flow page still uses those endpoints.

### 1.3.5 Automatic recovery saves

The editor keeps a private recovery copy of an unsaved page so the author can resume work
later. This is separate from **Save**: a recovery copy does not create an active version or
clear the unsaved marker. Only administrators can use the recovery endpoints.

Once per second the editor checks each tab. A dirty tab with a page descriptor is eligible
when at least N seconds have elapsed since its last ordinary save or recovery attempt; N
comes from browser local storage `wpi.autoSaveSeconds` when it is a positive number, and
otherwise defaults to 10 seconds. It writes only if the page descriptor assembled from the
canvas differs from the last successfully written or restored recovery copy. An unchanged
page is not written repeatedly. The timer is measured from the last save, rather than from
the last keystroke. Changes made during a write are picked up at a later check; failed writes
show a message and are retried after the interval. A recovery already in progress or an
ordinary save blocks another recovery write for that tab.

`PUT /api/v1/wpi/pages/:pageId/recovery` writes the descriptor to the author's recovery row
in `archive.frontend_pages`; it checks the page version and rejects a stale version. Loading
a saved page also loads the author's recovery copy if present, leaving the tab dirty. New
unnamed pages use temporary `unnamed-yyyymmdd-hhmmss` IDs and their recovery tabs are
restored when the editor opens. Closing an unnamed recovery tab discards its recovery copy;
a successful ordinary save removes the recovery in the same transaction as the page save. Recovery stores
the page descriptor and element instances, not flow-only edges, viewport or preview size.
The formal contract is in `ChenWeb/openspec/specs/wpi-pages/spec.md` and must be updated if
this behavior changes.

### 1.3.6 Relationship to WPI

The editor reads and writes element classes in `kb.wpi_descriptors` through
`/api/v1/wpi/classes/element*` (Create Element, the ELEMENTS folder, the Properties panel,
Edit class). Page and action nodes are not linked to WPI pages or to the action classes
(`load`, `save`, `open-page`, `close-page`, `save-page`). The WPI design (devdoc 2026102601,
§3.2.3) expects the editor to create page instances from page classes. That work, and
whatever **Load Page** should open, has not been decided or built.

### 1.3.7 Editing an element class

**Edit class** on an element box reads the class's latest draft or active row
(`GET /api/v1/wpi/classes/element/<class-id>`) into the Create Element form: the class
attributes first, then the instance attributes, with `descriptor_id` read-only. The form
says whether the class is a draft or implemented. **Save** sends the row to
`PUT /api/v1/wpi/classes/element/<class-id>` (admins only), which updates the latest draft or active record in place, keeping its version, status
and creation details. It updates the descriptor body and the last-updated user and time.
A missing record returns 404, including if it disappears before the update; saving never
creates a replacement. Drafts use the draft rules; active classes must name a registered
code module. Attribute edits use structural validation, and unsupported attributes return
warnings. Invalid edits show the server's issues in the form without changing the record. After a save the palette and the
properties panel reload the class list. A class's edits reach every box of that class; a
box's own values (Properties tab) are not part of the class.

Save stays disabled until the descriptor changes. Opening an attribute without editing
it leaves Save disabled; restoring the original values disables it again. Pending edits
to an existing attribute enable Save and use the existing Apply/Abandon prompt. Save is
also disabled while loading or saving, and unchanged descriptors do not send an update.

### 1.3.8 Text and languages

All interface text goes through Paraglide. The editor's own keys are `wpi_toolbar_*` and
`wpi_editor_*`. It also reuses `flowtoolbar_*`, `canvas_01_*` and `nodepalette_*` from
the Flow page components.

### 1.3.9 Property editors (planned)

**Status: planned, not built.** This section sets the rules that every property editor
must follow. Today's editors do not follow them yet (see Known limitations). All of them,
for the page, panes, panels and elements, will be replaced by editors that do.

**Terms**

| Term | Meaning |
|---|---|
| Entity | A part of a WPI app: the app itself, a page, a pane, a panel, an element or an action |
| Descriptor | The JSON that describes an entity: how it looks and how it behaves |
| Class | The reusable definition of a kind of entity, such as the `chart` element, stored in `kb.wpi_descriptors`. Pages have no classes: a page is complete in itself and is reused by copying |
| Instance | A copy of a class placed in a page. Changing an instance never changes its class |
| Property | One attribute in a descriptor. The code, the API and the specs call these *attributes* |
| Property editor | The form in the right-hand Properties panel that shows and edits the properties of the selected entity |
| Value editor | The control that edits one property, such as a pulldown menu or a colour picker |

**Why**

Each kind of entity has its own property editor, written separately, and they have
drifted apart. Some have a title and some do not. Some show help tips and some do not.
Many properties that should be pulldown menus, or one of the value editors below, are
plain text fields. Some editors do not show the effect of a change, or do not pick up a
change made on the canvas. The rules below make every property editor look and work the
same way and reuse the same value editors.

**Where property editors come from**

A new entity class is built in four steps:

1. Write a proposal.
2. Review it, and revise it until it is approved.
3. Implement it. The implementation includes the class's property editor. For example,
   the `chart` element's implementation contains both the code that draws charts and the
   editor for a chart's properties.
4. Add the class's record to `kb.wpi_descriptors`.

A property editor is a Svelte component written by hand, like the rest of the class's
code. It is built into the app, so selecting the same entity again reuses the component;
nothing is generated or rebuilt while the editor runs. Describing property editors with
descriptors and drawing them with WPI, as if they were WPI pages, may come later. That is
a separate piece of work.

**What property editors change**

The WPI Editor edits pages. Placing a class on a page copies it into the page as an
instance. The WPI Editor and the property editors change instances only, never classes.
(The Edit class form in §1.3.7 does change a class record, but it is a separate form, not
a property editor.)

**Rules for every property editor**

- **Shows the selection.** The Properties panel shows the property editor of the selected
  entity. With nothing selected, or more than one entity selected, it shows nothing.
- **Same layout.** A title naming the entity, then its properties in groups. Clicking a
  group's heading folds or unfolds it. Each property has a label, a value editor and a
  help tip.
- **Right value editor.** Each property uses the value editor for its type (table below).
  A property with a fixed set of values uses a pulldown menu, never a text field.
- **Changes show at once.** A changed value takes effect on the canvas immediately.
- **Canvas changes show at once.** Moving or resizing an entity, or splitting a pane, on
  the canvas updates the property editor immediately. An editor whose values differ from
  what the canvas shows is a bug.
- **Positions.** Every entity's property editor shows its position. Where a layouter
  places the entity, the position is read-only and is not stored. The planned manual
  layouter places nothing itself: users arrange entities by dragging them, and the
  property editor shows and edits their positions, in step with the canvas.
- **Undo.** Every property change can be undone and redone (see Editing behaviour).
- **Both languages.** Titles, labels, group names and help tips go through Paraglide, in
  English and Chinese (see Text and languages).

**Value editors**

Unless a value editor is very simple, build it as a reusable module and catalogue it
under `KnowledgeStore/doc-repo/modules/`. The list will grow: when a class needs a value
editor that is not listed, add it here and build it the same way. The *Today* column says
where the behaviour lives now, before the replacement.

| Value editor | What it edits | Today |
|---|---|---|
| text-editor | One line of text, such as a label or a placeholder | Text fields in every panel |
| multiline-text-editor | Longer text, such as a system prompt or a text element's content | Text areas in several panels |
| localized-text-editor | Text that is either one string or separate English and Chinese versions | Text element (`TextProperties.svelte`) |
| number-editor | A number, optionally limited to a range and a step | Chat composer rows, list row limit |
| switch | On or off, such as *required* or a scroll bar | Checkboxes in element panels, switches in the page panel |
| value-picker | One value from a fixed list, in a pulldown menu | Pulldown menus in every panel |
| ordered-multi-picker | Several values from a fixed list, in order: tick to include, arrows to reorder | Chat composer tool bar and agents, chat panel tabs |
| date-picker | A date or a range of dates | Not built |
| time-picker | A time or a range of times | Not built |
| color-picker | A colour: none, one colour, or separate light and dark colours, chosen with a picker or typed as a CSS colour | Pane and panel colours (see What is on the screen); typed text in the text element |
| length-editor | A width, height, gap and the like: `auto`; `elastic`, which grows into the space left in its row, within its minimum and maximum; or a number in `px`, `rem`, `em` or `%`. A property may allow fewer units: font sizes take only `px`, `rem` and `em` | Typed text, checked when entered |
| font-picker | A font family | Typed text, checked when entered |
| alignment-picker | Horizontal or vertical alignment | Pulldown menus |
| icon-picker | An icon | A pulldown of icon names in the text element |
| button-type-picker | One of the button types the system supports | Not built |
| database-picker | A database | Not built on its own; the first level of Pick Table |
| schema-picker | A schema | Not built on its own; the second level of Pick Table |
| table-picker | A table | Pick Table (module `20261029-01`), one menu that steps through database, schema and table |
| field-picker | One or more fields of a table | Pick Fields (module `20261029-02`) |
| data-source-editor | Where a list gets its rows: table, fields, row limit, action and result | List element, using Pick Table and Pick Fields |
| column-list-editor | A list's columns: the label, field and width of each, with add and remove | List element |
| sort-order-editor | The columns a list is sorted by, each ascending or descending | List element |
| validation-editor | Input rules: minimum, maximum and step for numbers; minimum length and pattern for text | Input element |
| action-picker | The action an event runs, such as *save* or *open page* on a click | Element `on_click` pulldown |
| layouter-picker | The layouter of a page or a panel | Pulldown for the page layouter; the panel's is read-only |
| read-only-value | A value that is shown but not edited, such as an ID, a schema version or a position set by a layouter | Page ID and schema version, an element's pane |
| json-editor | A property that no other value editor fits, edited as JSON text | The *Other* group and the Node tab |

## 1.4 Known limitations

- **Flow storage is incomplete.** The flow server endpoints are placeholders (see Storage);
  ordinary page saves persist WPI descriptors, not arbitrary flow canvases.
- **Page and action boxes carry only a name.** Element boxes have a class and attributes;
  page and action boxes have no class or attributes yet.
- **Typing in a property field records one undo step per keystroke** (see Editing
  behaviour).
- **Property editors are not uniform yet.** Titles, help tips, value editors and keeping in
  step with the canvas differ from one kind of entity to another. Some editors do not show
  the effect of a change, or do not pick up a change made on the canvas. Property editors
  (§1.3.9) sets the rules they will all be rebuilt to.
- **Text in the editor cannot be selected.** The dashboard shell sets `select-none`, and
  the editor does not turn selection back on with `select-text` at its root, as the
  workspace rules require for each page inside that shell.
- **Fixed to the site header's height.** The top offset is a constant (see Where it lives).
- **The properties panel's width is not remembered.** It returns to 390 px each time the
  editor opens, and the resize handle works with the mouse only, not the keyboard.
