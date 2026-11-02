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

The right-hand Properties panel shows the selected page, pane, panel or element. Every one of
these editors is drawn by one shared property editor from a definition, so they all look and
work the same way (§1.3.9). The adjacent Class tab edits the reusable stored definition,
with an attribute tree and inline forms (§1.3.7).

## 1.2 What is on the screen

- **Left — node palette.** Building blocks you can drag onto the canvas, in folders
  (AI, Data, Actions, plus empty Pages and Elements folders kept for WPI). Folders start
  folded; typing in the search box opens every folder with a match.
- **Middle — tool bar and canvas.** The tool bar runs along the top of the canvas (table
  below). The canvas has zoom controls at the bottom left, an overview map at the bottom
  right, and a gear button at the top right for line style and grid settings.
- **Right — properties.** The property editor of the one selected entity (§1.3.9): an
  element box, or the page, a pane or a panel chosen with **View page config**, **Panes** and
  **Panel** above the canvas or by clicking the preview. With nothing selected, or several
  boxes, the property editor is empty. **Properties** edits the selected instance;
  **Class** edits its reusable stored class (§1.3.7). A pane selects its page layouter
  class; a panel selects its element layouter class. Pages have no class. An action
  box offers a class selector on Class. Other flow boxes show their own settings in
  Properties. Drag the panel's left edge to make it wider or narrower (200–640 px;
  it starts at 390 px).
- **Above a selected box — its tool bar.** **Duplicate** adds a copy one grid cell down and
  right (further while another box sits there), with the same data and size, and selects
  it; lines are not copied. **Delete** removes the box and every line attached to it. Both
  can be undone. An element box also has **Edit class** (pencil), which opens the Class
  tab on the box's class (below).

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
| `web/src/lib/components/shared-ui/canvas/{NodePalette,PropertiesPanel,FlowPicker}.svelte`, `nodes/*` | Shared with the Flow page (`canvas-01.svelte`). In the WPI editor `PropertiesPanel` shows only flow nodes and page/action boxes |
| `web/src/lib/components/shared-ui/canvas/WpiProperties.svelte` | The Properties panel for WPI entities: the element, page, pane or panel editor for the selection, or nothing |
| `web/src/lib/components/shared-ui/canvas/PaneStructure.svelte` | The pane editor's tree and its split, add, merge and delete commands |
| `web/src/lib/components/shared-ui/canvas/edit-session.ts` | One undo step per focus; tests in `edit-session.test.ts` |
| `web/src/lib/components/shared-ui/property-editor/`, `value-editors/` | The shared property editor and the value editors (reusable modules `20261102-01` to `-08`) |
| `web/src/lib/wpi/properties/` | The property editor definitions and the sources that read and write each kind of entity (§1.3.9) |
| `web/src/lib/components/shared-ui/canvas/{WpiClassPanel,EntityClassEditor,ClassAttributeTree,ClassEditorOptions}.svelte`, `class-editor.ts` | The Class tab, stored-class drafts, recursive attributes and editor configuration |
| `server/api/wpi/class_editor.go` | Class read/update endpoints and editor metadata validation |
| `web/src/lib/components/shared-ui/canvas/node-actions.ts` | The box tool bar's Duplicate and Delete: each canvas provides them through Svelte context (`setNodeActions`) and `nodes/BaseNode.svelte` calls them; pure `duplicateNode`/`removeNode`, tests in `node-actions.test.ts`. The Flow page provides them too |
| `web/src/lib/components/shared-ui/canvas/CreateElementDialog.svelte` | Create Element: defines a new element class as a draft |
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
  delete and rename. A property edit is one step per focus: everything changed in one
  property between entering it and leaving it is a single step (`canvas/edit-session.ts`);
  a canvas action, undo or redo during the focus starts a new one.
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

The editor reads and writes reusable element, action and layouter classes in
`kb.wpi_descriptors`. Pages and their instance values remain separate, in
`kb.frontend_pages`. A pane's Class tab opens the page layouter; a panel's opens
its element layouter. Action boxes can select a stored action class, but they are
still flow-only canvas nodes: saving them as page actions is not built.

### 1.3.7 Editing a class

The **Class** tab, also opened by **Edit class** on an element box, edits the
selected entity's latest stored class. It reads the database record, even when the
instance already holds an older class copy. Each attribute is a button showing its
name. Clicking it reveals its form and any nested attributes; clicking again folds
it. Element defaults are shown directly, without their storage wrapper.
The header shows the class record's **Version** and **Schema version** alongside
its draft or implemented status.

While **Class** is selected, **Code → View JSON** shows that class's whole descriptor
body, including unsaved form edits. **Edit → Apply** updates the same class draft;
**Save class** writes the changed body to `kb.wpi_descriptors.body`. Descriptor ID
and schema version remain fixed. No temporary instance ID is added to this JSON.
While **Properties** is selected, View JSON continues to show the instance or page.

The form edits the attribute name, its description in one or both languages, the
**Attribute scope** dropdown (**Class attribute** or **Instance attribute**), its
default, and its value editor. Choosing an editor
shows configuration fields such as choices, number limits or allowed length units.
**Editor options as JSON** edits only the selected value editor's configuration;
for `localized-text`, it is that editor's options, not the translated text or class
body. An empty object uses the editor's default options. Names must be unique;
identity fields and array indices retain their names. Descriptor ID and schema
version values are read-only. Blank default text removes the default; `null` means
an instance must supply it; `""` means an empty string.

For a top-level element attribute, **Class** fixes its non-null default for every
new instance; **Instance** allows each instance to change it. Built-in class
attributes keep their class scope. For nested attributes and action or layouter
classes, the flag records authoring scope only and does not restrict runtime
overrides; the form says so beside the flag.

**Save class** updates the existing record in place, retaining its version, status
and creation details. Every displayed attribute's scope, editor ID and options
are explicit in `body.attribute_definitions`, including `/label`; descriptions
also remain in the element's help tip. Older descriptors missing definitions get
them in the local draft. A note asks the author to save those definitions to the
body; opening a descriptor alone does not write the database. Existing explicit
configuration is preserved. Clearing a plain description removes both its help tip
and description metadata. Dirty checks ignore object-key ordering from PostgreSQL.
Save is disabled for a complete, unchanged descriptor and while loading or
saving. Invalid edits stay in the form with the server's issues; no record is
changed. A missing class returns 404 and saving never creates a replacement.
A successful save refreshes the class lists. Existing instances retain their own
class copies; class changes apply to new copies. Properties edits remain separate.

Unsaved class drafts stay available while switching entities, editor or canvas
tabs, sidebar views and runtime Preview. They are kept in memory for this editor
session. Route navigation and browser unload warn before discarding them; explicit
**Discard changes** also asks first. Class edits use their own Save class command,
and canvas undo/save shortcuts do not intercept typing in the Class form.

**Implementation and contract.** The endpoints are authenticated
`GET /api/v1/wpi/classes/:kind/:classId` and admin-only `PUT` at the same path, for
`element`, `action`, `page-layouter` and `element-layouter`. Existing element
endpoints are preserved. `/api/v1/wpi/classes/action?scope=all` lists every active
action class for the selector; the ordinary request still lists click triggers.
Optional `attribute_definitions` metadata stores descriptions, scopes and editor
configuration by logical JSON pointer; it is never an instance value or runtime
default. Renaming an attribute moves its nested metadata too.

The [design and implementation plan](../../../../../ChenWeb/openspec/changes/wpi-class-editor/design.md)
and [Class editor spec](../../../../../ChenWeb/openspec/changes/wpi-class-editor/specs/wpi-class-editor/spec.md)
carry the implementation details and contract. Update that spec when this behavior
changes. Regression tests are in `web/tests/wpi-class-editor/test_editor.py` and
`canvas/class-editor.test.ts`; backend tests are in `server/api/wpi/class_editor_test.go`.

### 1.3.8 Text and languages

All interface text goes through Paraglide. The editor's own keys are `wpi_toolbar_*` and
`wpi_editor_*`; Class tab keys are `wpi_class_*`. It also reuses `flowtoolbar_*`, `canvas_01_*` and `nodepalette_*` from
the Flow page components.

### 1.3.9 Property editors

**Status: built 2026-11-02** (OpenSpec change `wpi-property-editors` in ChenWeb; its spec is
the contract and must be updated if this behaviour changes). The page, pane, panel and every
element editor follow the rules below. Not built yet: the manual layouter (so positions are
read-only everywhere), and the value editors no property uses (date, time and button-type
pickers, and standalone database and schema pickers).

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

Each kind of entity used to have its own property editor, written separately, and they had
drifted apart. Some had a title and some did not. Some showed help tips and some did not.
Many properties that should have been pulldown menus were plain text fields. Some editors did
not show the effect of a change, or did not pick up a change made on the canvas. The rules
below make every property editor look and work the same way and reuse the same value
editors.

**Where property editors come from**

A new entity class is built in four steps:

1. Write a proposal.
2. Review it, and revise it until it is approved.
3. Implement it. The implementation includes the class's property editor. For example,
   the `chart` element's implementation contains both the code that draws charts and the
   definition of a chart's property editor (below).
4. Add the class's record to `kb.wpi_descriptors`.

A property editor is not a Svelte file. It is a *definition*: data in code, in
`web/src/lib/wpi/properties/`, that lists the entity's groups and, for each property, its
label, its value editor and the data that editor needs. Pulldown choices normally come from
the entity's class: the action classes for an `on_click`, the page layouter classes for a
page, the items of a menu for its first item. One renderer,
`shared-ui/property-editor/PropertyEditor.svelte`, draws every property editor from its
definition while the app runs. Class metadata may override the value editor and
its options for element attributes and panel layouter configuration. The metadata
travels with the class copy, so older instances keep their existing configuration.

Each element's code-module document (`KnowledgeStore/doc-repo/code_modules/`) has a
*Property editor* table giving every attribute's group and value editor; the page, page
layouter and flow layouter documents have one too. An attribute without one gets the
*common-sense* value editor, chosen from its name and default value: a length for sizes,
gaps and margins, a colour picker for `…_color`, a switch for a boolean, a number for a
number, localized text for labels and descriptions, JSON for other objects, and text
otherwise. It appears under **Other**. So implementing a class (step 3) includes writing its
definition and its document's table. Describing property editors with descriptors and
drawing them with WPI, as WPI pages, may come later.

**What property editors change**

The WPI Editor edits pages. Placing a class on a page copies it into the page as an
instance. The **Properties** tab changes instances. The separate **Class** tab
changes a stored class (§1.3.7).

**Rules for every property editor**

- **Shows the selection.** The Properties panel shows the property editor of the selected
  entity. With nothing selected, or more than one entity selected, it shows nothing.
  **Panes** with no pane selected selects the root pane; **Panel** shows the panel of the
  selected pane only when it is a leaf. Choosing the page, a pane or a panel leaves no box
  selected.
- **Same layout.** A title naming the entity, then its properties in groups, all open at
  first. Clicking a group's heading folds or unfolds it. Each property has a label (with `*`
  when every instance must set it), a value editor and a help tip, which may be empty. A
  non-empty tip shows as an info icon at the upper right of the value editor; hovering over
  it or focusing it shows the tip. *Reset* removes a property's own value so the default
  applies; it is not offered for the page layouter or a pane's ID.
- **Right value editor.** Each property uses the value editor for its type (table below).
  A property with a fixed set of values uses a pulldown menu, never a text field.
- **Changes show at once.** A changed value takes effect on the canvas immediately, while
  the author is still in the field.
- **Invalid values are not applied.** Text that is not valid (a length of `12xy`, say) is
  not applied and is not flagged while the author types, because half-typed values are
  normal. When the author leaves the field (or presses Enter), the text stays in the field
  and the editor shows, under the value editor, why it is invalid, with two buttons:
  **Abandon Edit** shows the stored value again; **Stay Edit** puts the cursor back in the
  field to fix it. Warnings about an applied value (a width above the maximum) show at
  once.
- **Canvas changes show at once.** Moving or resizing an entity, or splitting a pane, on
  the canvas updates the property editor immediately. An editor whose values differ from
  what the canvas shows is a bug.
- **Positions.** Element and pane editors show the position, x and y in page pixels from
  the page's top-left corner, measured on the canvas. Where a layouter places the entity,
  the position is read-only and is not stored. The planned manual layouter places nothing
  itself: users will arrange entities by dragging them, and the property editor will show
  and edit their positions, in step with the canvas.
- **Undo.** Everything changed in one property between entering it and leaving it is one
  undo step (see Editing behaviour).
- **Both languages.** Titles, labels, group names and help tips go through Paraglide, in
  English and Chinese (see Text and languages).

**Value editors**

Unless a value editor is very simple, build it as a reusable module and catalogue it
under `KnowledgeStore/doc-repo/modules/`. The list will grow: when a class needs a value
editor that is not listed, add it here and build it the same way. The *Built as* column names
the catalogued module (`KnowledgeStore/doc-repo/modules/`).

| Value editor (ID in definitions) | What it edits | Built as |
|---|---|---|
| text-editor (`text`) | One line of text, such as a data binding or a font family | Property Editor (`20261102-01`) |
| multiline-text-editor (`multiline-text`) | Longer text | Property Editor |
| localized-text-editor (`localized-text`) | Text that is one string or separate English and Chinese versions | Localized Text Editor (`20261102-02`) |
| number-editor (`number`) | A number, optionally whole and within limits | Property Editor |
| switch (`switch`) | On or off, such as *required* or a scroll bar | Property Editor |
| value-picker (`value-picker`) | One value from a list, in a pulldown | Property Editor |
| ordered-multi-picker (`ordered-multi-picker`) | Several values from a list, in order: tick to include, arrows to reorder | Ordered Multi-Picker (`20261102-03`) |
| string-list (`string-list`) | A list of words typed as comma-separated text: keywords, tags, roles | Property Editor |
| date-picker | A date or a range of dates | Not built |
| time-picker | A time or a range of times | Not built |
| color-picker (`color`) | A colour: none, one colour, or separate light and dark colours, chosen with a picker or typed as CSS | Color Picker (`20261102-04`) |
| length-editor (`length`) | `auto` and `elastic` where allowed, or a number in the allowed units (px, rem, em, %); a bare number means px | Length Editor (`20261102-05`) |
| font-picker | A font family | The text editor with the font grammar |
| alignment-picker | Horizontal or vertical alignment | The value-picker with the alignment values |
| icon-picker | An icon | The value-picker with the icon names |
| button-type-picker | One of the button types the system supports | Not built |
| database-picker, schema-picker | A database, a schema | Not built on their own; the first levels of Pick Table |
| table-picker | A table | Pick Table (`20261029-01`), inside the data-source editor |
| field-picker | Fields of a table | Pick Fields (`20261029-02`), inside the data-source editor |
| data-source-editor (`data-source`) | Where a list gets its rows: table, fields, row limit, action, result and sort order | Data Source Editor (`20261102-06`) |
| column-list-editor (`column-list`) | A list's columns: label, field and width, with add and remove | Column List Editor (`20261102-07`) |
| sort-order-editor | Sort columns, each ascending or descending | Property Editor (inside the data-source editor) |
| validation-editor (`validation`) | Input rules: min, max and step for numbers; min length and pattern for text | Validation Rules Editor (`20261102-08`) |
| action-picker | The action an event runs, such as *open page* on a click | The value-picker with the action classes |
| layouter-picker | The page layouter | The value-picker with the page layouter classes |
| read-only-value (`read-only`) | A value shown but not edited: an ID, a schema version, a pane, a position | Property Editor |
| json-editor (`json`) | A property no other value editor fits, as JSON text | Property Editor |

## 1.4 Known limitations

- **Flow storage is incomplete.** The flow server endpoints are placeholders (see Storage);
  ordinary page saves persist WPI descriptors, not arbitrary flow canvases.
- **Page and action boxes are flow-only.** Action boxes can select and edit a stored
  action class, but cannot yet be saved into a WPI page; page boxes have no page class.
- **Positions are read-only**, and shown only for elements and panes. The manual layouter
  that will let authors place entities by dragging is not built.
- **Property editor groups and labels are defined in code** (§1.3.9). Element value
  editors and panel layouter configuration can use overrides from their class copy.
  Date, time and button-type controls, and standalone database/schema controls, are
  configurable placeholders. Standalone table, field and sort controls use JSON;
  their specialized controls remain inside the data-source editor.
- **Fixed to the site header's height.** The top offset is a constant (see Where it lives).
- **The properties panel's width is not remembered.** It returns to 390 px each time the
  editor opens, and the resize handle works with the mouse only, not the keyboard.
