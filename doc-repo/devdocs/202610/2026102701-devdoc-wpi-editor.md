# WPI Editor — a canvas for laying out WPI pages, elements and actions

**Date:** 2026-10-27 \
**Scope:** What the WPI Editor in ChenWeb is today, what each control does, how it stores
its work (it does not, yet), and what is missing. Read this before extending the editor or
connecting it to WPI descriptors. The Web Page Interpreter itself is described in devdoc
[2026102601](2026102601-devdoc-web-page-interpreter.md) (design) and
[2026102603](2026102603-devdoc-wpi-pilot.md) (what was built). \
**Code root:** `ChenWeb/web/src/lib/components/shared-ui/wpi-editor.svelte`

## Summary

The WPI Editor is a drawing board inside ChenWeb, opened from **Development → Tools → WPI
Editor**. It is meant to become the place where people build Web Page Interpreter (WPI)
pages by arranging boxes on a canvas instead of writing descriptions by hand. Today it is
an early shell. You can add boxes for pages, elements and actions, draw lines between
boxes, line boxes up with alignment tools, and undo or redo your changes. It also still
offers the general building blocks it inherited from the Flow page it was copied from.

Two things it cannot do yet matter most. First, it does not read or write real WPI pages:
the boxes are drawings only, and **Load Page** just says it is not available. Second,
**Save does not keep anything**. The server side behind it is a placeholder that answers
"saved" but stores nothing, so everything on the canvas is lost when you reload or leave the
page.

## What is on the screen

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

### Tool bar

| Control | What it does | Available when |
|---|---|---|
| Flow name | Click to rename the current canvas; a yellow dot means unsaved changes | Always |
| ▾ next to the name | Opens the picker of saved canvases (My Flows / Shared Flows / Templates); asks first if there are unsaved changes | Always |
| **Create Nodes ▾** | Menu: **Create Page**, **Create Element**, **Create Action** — adds that kind of box in the middle of the visible canvas | Always |
| **Load Page** | Placeholder: shows "Loading a page is not available yet" | Always |
| Undo / Redo | Steps back or forward through changes | When there is something to undo / redo |
| Align left / horizontal centres / right | Lines the selected boxes up on that edge or centre line | Two or more boxes selected |
| Align top / vertical centres / bottom | Same, vertically | Two or more boxes selected |
| Distribute horizontally / vertically | Keeps the outermost selected boxes in place and spaces the ones between them evenly | Three or more boxes selected |
| Save | Saves the canvas — **currently stores nothing** (see Details) | Always |
| Save as template | Saves the canvas as a template — **currently stores nothing** | Always |

To select several boxes, hold ⌘ (Ctrl on Windows/Linux) while clicking them.

## Details

### Where it lives

| File | Role |
|---|---|
| `web/src/lib/components/shared-ui/wpi-editor.svelte` | The editor: state, undo/redo, create/align/distribute, save, canvas, settings panel |
| `web/src/lib/components/shared-ui/canvas/WpiCanvasToolbar.svelte` | The tool bar (presentational; all actions are callbacks into the editor) |
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

### Node types

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

### Editing behaviour

- **Align / distribute** (`align-nodes.ts`): act on nodes with `selected: true`. Align
  needs two and distribute three; with fewer, the functions return the input unchanged
  and the buttons are disabled. Sizes come from `node.measured`, falling back to
  `width`/`height`, then 0. Results are **not** snapped to the grid, because snapping would
  undo centre alignment. Distribute orders nodes by their left (or top) edge, keeps the
  first and last in place, and sets equal gaps; overlapping nodes give a negative gap.
- **Undo / redo:** full snapshots of nodes and edges, at most 50 undo steps. One step is
  recorded before: create, palette drop, duplicate, delete from the box tool bar, new edge,
  align, distribute and edge-style change.
  Not recorded: edits in the properties panel, and renames. Two handlers record *after* the
  change, so the step is wrong: `onnodedragstop` (undo after a drag restores the
  dragged-to position, so the drag itself cannot be undone) and `ondelete` (undo after a
  Backspace delete restores the state without the deleted nodes; the tool bar's Delete
  records its step first). Both were verified in the browser
  on 2026-10-27. A second undo then steps back past the change.
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
- **Unsaved changes:** "dirty" means nodes or edges differ from the last saved snapshot; a
  rename does not count. Only opening the picker asks for confirmation. Leaving the page,
  switching menus and reloading do not ask.
- **Size warnings:** a one-time message above 500 nodes or 1000 edges.

### Storage: the flow endpoints are stubs

The editor stores a canvas as a *flow* through `flowService`:

| Call | Endpoint | What the server actually does |
|---|---|---|
| load on open | `GET /api/v1/flows/default` | Returns a fixed flow `{flow_id: 1, flow_name: "My First Flow", nodes: [], edges: []}` |
| picker list | `GET /api/v1/flows?scope=mine\|shared\|templates` | Returns that same single flow for every scope |
| new empty | `POST /api/v1/flows` | Returns that same flow |
| Save | `PUT /api/v1/flows/:id` | Returns that same flow with a new `updated_at`; the request body is ignored |
| Save as template | `POST /api/v1/flows/:id/template` | Returns a copy of that flow; nothing stored |

Every handler in `server/api/flowhandler/` says "All handlers return placeholder data" and
has no database table behind it. As a result:

- Save shows "Saved" and clears the unsaved-changes dot, but nothing is stored. Reloading
  the page shows an empty "My First Flow".
- After Save the editor takes the server's reply as the current flow, so **a renamed canvas
  goes back to "My First Flow"** when saved.
- The nodes stay on screen after Save, because the editor keeps its own copy; this makes it
  look as if saving worked.
- The Flow page (`canvas-01.svelte`) uses the same endpoints and has the same problem.

All endpoints require a logged-in user; logged out, they return 401 and the editor opens
with an empty canvas.

### Relationship to WPI

The editor reads and writes element classes in `kb.wpi_descriptors` through
`/api/v1/wpi/classes/element*` (Create Element, the ELEMENTS folder, the Properties panel,
Edit class). Page and action nodes are not linked to WPI pages or to the action classes
(`load`, `save`, `open-page`, `close-page`, `save-page`). The WPI design (devdoc 2026102601,
§3.2.3) expects the editor to create page instances from page classes. That work, and
whatever **Load Page** should open, has not been decided or built.

### Editing an element class

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

### Text and languages

All interface text goes through Paraglide. The editor's own keys are `wpi_toolbar_*` and
`wpi_editor_*`. It also reuses `flowtoolbar_*`, `canvas_01_*` and `nodepalette_*` from
the Flow page components.

## Known limitations

- **Nothing is saved.** The flow server endpoints are placeholders (see Storage). Treat
  every canvas as temporary until a real flow store exists.
- **No connection to WPI descriptors.** The editor cannot open, create or change a real
  WPI page; **Load Page** is a placeholder.
- **Page and action boxes carry only a name.** Element boxes have a class and attributes;
  page and action boxes have no class or attributes yet.
- **Dragging a box, or deleting it with Backspace, cannot be undone**, and properties-panel
  edits and renames are not recorded at all (see Editing behaviour).
- **Text in the editor cannot be selected.** The dashboard shell sets `select-none`, and
  the editor does not turn selection back on with `select-text` at its root, as the
  workspace rules require for each page inside that shell.
- **Fixed to the site header's height.** The top offset is a constant (see Where it lives).
- **The properties panel's width is not remembered.** It returns to 390 px each time the
  editor opens, and the resize handle works with the mouse only, not the keyboard.
