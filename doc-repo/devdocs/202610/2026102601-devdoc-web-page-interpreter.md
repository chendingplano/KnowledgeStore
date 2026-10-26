# Web Page Interpreter (WPI)

**Date:** 2026-10-26 \
**Status:** Guiding design. Nothing is built yet; §8 defines the pilot. \
**Background:** research report [2026102602](2026102602-devdoc-web-page-interpreter-research-report.md)

## Summary

A Web Page Interpreter (WPI) shows a web page from a description of the page instead of
from code written for that page. The description is a JSON document called a
*descriptor*. One interpreter, written once, can draw any page that can be described with
the parts it knows.

This document is the overall guide for WPI. The long-term goal is broad: apps, pages,
elements, actions and eventually application behavior, all described as data. We get
there step by step. The first step, the pilot, builds a simple menu-driven app whose pages
are lists and forms that load and save records, with a few common actions, and nothing
more: no page state beyond the data being edited, no conditions, no state machines. Each
later phase adds elements, actions or other constructs when real pages need them.

## 1. Why: separating "what" from "how"

A web page mixes two things that change at very different rates:

- **What the page is**: which fields, buttons and lists it shows, where they go, which data
  they show. This changes all the time.
- **How a page is drawn and made to work**: turning a field into an input box, arranging
  elements on screen, saving data. This rarely changes.

In ordinary frontend code the two are mixed in every page file, so the amount of frontend
code grows with the number of pages. WPI moves the "what" into descriptors and keeps the
"how" in one interpreter. The interpreter's code then grows with the number of *kinds* of
things it supports (element types, layouters, actions), not with the number of pages.
Separating the two is an act of abstraction: the programs are lifted away from the data
they use, so they become more or less pure logic.

Actions can be separated the same way. Take: "When an item in the `category_type`
pulldown menu is selected, open the page `show-metric-details` in the pane `right-pane`."
The pulldown, the page and the pane are the "what"; they belong in an action descriptor.
The "how" — opening some page in some pane — is pure logic that works for any pulldown,
any page and any pane.

What counts as "what" depends on the level. `open_page` is a "what" to a descriptor author
and a "how" inside the interpreter. The aim is not to remove every procedural idea from
descriptors, but to have descriptors *name* stable, reusable operations instead of
implementing them (report §3.4).

## 2. Guiding principles

1. **Descriptors are data, not code.** They are JSON and independent of any programming
   language or framework: no Svelte, DOM or JavaScript inside. Phase 1's interpreter uses
   Svelte for the frontend and Go for the backend, but another interpreter could read the
   same descriptors.
2. **A small vocabulary, grown by need.** WPI supports a fixed set of element types,
   layouters, layout templates and action types, each implemented once in code. A new one
   is added only when a real page needs it. The measure of success is how often a new page
   needs a new element type, action type or interpreter change; that number should fall
   over time.
3. **Definitions have descriptor IDs; running copies have instance IDs** (§3.4).
4. **Anything referenced by ID can be written inline instead.** A page can refer to a
   stored element or action descriptor, or contain a one-off descriptor directly.
5. **Check before running; never fail silently.** Descriptors are validated before a page
   is shown. Anything that cannot be resolved shows a visible error in place and is logged
   (§7).
6. **Descriptors ask; the server decides.** A descriptor can ask to load or save data. The
   backend runs only descriptors stored in the database, never descriptor text sent by the
   browser, and checks names and values before it touches any table (§5.2). Descriptors may
   one day be written by an LLM, so they are never trusted just because they are not code.
7. **Data lives in the database.** Descriptors are stored in `kb` tables with a version
   column, not in Git (§6).
8. **Incremental.** Each phase adds only what pages need. We do not design a complete
   declarative programming language up front (report §8).

## 3. Concepts

| Term | Meaning |
| --- | --- |
| WPI app | What a user opens in the browser. Has its own URL, which holds only the app's ID. Defined by an app descriptor. |
| Layout template | A built-in, named way of dividing an app's viewport into panes, e.g. `single-pane`. |
| Pane | A rectangular region of the viewport that controls geometry. Holds panels and shows at most one at a time. |
| Panel | One open page inside a pane: a page descriptor plus its data. A pane can keep hidden panels to show again later. |
| Page | What a panel shows: a list of elements and the layouter that arranges them. |
| Element | One visible part of a page: text, input, pulldown menu, button, list, menu. |
| Element type | A built-in kind of element implemented in the interpreter, e.g. `input`. |
| Layouter | Arranges a page's elements in one specific way. |
| Action | An operation the interpreter performs, e.g. load data, save data, open a page. |
| Descriptor | A JSON document describing one app, page, element or action. Has a descriptor ID. |
| Input doc | The JSON data a panel shows and edits. |
| Data binding | The link between an element and one attribute of the input doc. |
| Instance ID | Identity of one running copy of an app, page or element, generated by the system. |

### 3.1 WPI apps

A **WPI app** is what a user opens in a browser. Each app has its own URL, and the URL
holds only the app's ID. Which panes the app has and which pages they show come from its
**app descriptor** (§4.1).

A WPI app is related to, but not the same as, a conventional application. A conventional
application is deployed individually and independently. A WPI app is not deployed on its
own: it is a descriptor, run by the same interpreter as every other WPI app. What it has of
its own is its URL, which makes it individually loadable in a browser.

Every page lives inside a WPI app; a page cannot be opened by itself. Even a page holding a
single form normally needs a header — with controls for display mode, language, menus and
notifications — and a footer saying who we are, and the app provides them. Single-page
apps are rare, so writing an app descriptor for them is a small cost.

WPI is one way of building frontend pages, not the only one. An application can still
build pages in hand-written code, as ChenWeb does today, and the two coexist.

Loading a WPI app *inside* an ordinary page may be useful later, much as an `<iframe>`
loads a separate document into a page while a `<div>` is part of the page itself. This is
deferred until it is needed (§9).

### 3.2 Layout templates and panes

An app divides its browser viewport into **panes** using a **layout template**. Layout
templates are a small, built-in set of names, like layouters; normally there are only a
few. Templates defined by users may come in a later iteration.

The pilot has two:

- **`single-pane`**: the whole viewport is one pane, `main`.
- **`top-left-middle-right-bottom`**: the viewport is divided into three rows — top,
  middle and bottom — and the middle row into three columns — left, middle and right. That
  gives five panes: `top`, `left`, `middle`, `right` and `bottom`.

Pane IDs come from the template, so an action that targets a pane can be checked before
anything runs. An app may leave regions out: a region its descriptor does not mention takes
no space, so an app without a footer simply omits `bottom`.

A pane defines and controls the geometry of its region: width and height, minimum and
maximum size, whether the user can resize it, and whether and how it scrolls. The app
descriptor sets these for each pane.

### 3.3 Panels

A pane shows one page at a time — or none, before anything has been opened in it —
through a **panel**. A panel is one open instance of a page: the page descriptor, its input
doc and its elements. A pane can keep several panels, showing one and hiding the others.

```text
WPI app "customer-admin"              (URL holds only the app ID)
└── Viewport, divided by layout template "top-left-middle-right-bottom"
    ├── Pane "top"     ── Panel → page "app-header"
    ├── Pane "left"    ── Panel → page "customer-nav"           (holds the menu)
    ├── Pane "middle"  ├─ Panel → page "customers"              visible
    │                  └─ Panel → page "customer-form" (new)    hidden
    └── Pane "right"   ── Panel → page "customer-form" (customer 42)
```

**Menus and panel bindings.** Take the app above: a menu tree in the left pane, pages
shown in the middle pane. When the user clicks a menu item, the middle pane hides its
current page, if any, and shows the item's page:

- The first time, the page is opened: a new panel is created, and its panel instance ID is
  bound to the menu item.
- Later, if the item's panel still exists, the pane simply shows it again instead of
  reloading the page, which is very fast.

The menu's pane keeps these bindings (menu item → panel instance ID). What matters is the
binding itself. One panel can be bound to more than one menu item: items that open the
same page with the same input share one panel.

**Hidden panels.** Hiding a panel does not close it: it keeps its input doc, unsaved
changes included. A pane keeps a hidden panel only while something can show it again, that
is, while a menu item is bound to it. A panel nothing is bound to — for example a customer
opened by clicking a list row — is closed when another panel replaces it, after the
unsaved-changes check (§3.9). Otherwise it would linger, hidden, with no way back to it.

**How long hidden panels are kept.** Hidden panels are removed in two ways:

- **Age-out.** The app descriptor sets how long a panel may stay hidden since it was last
  visible; older panels are closed. A panel with unsaved changes is never aged out.
- **Manually.** The user closes the panel (`close_page`).

A menu item whose panel has been removed opens its page afresh the next time it is
clicked.

**Refreshing a page.** Any page, visible or hidden, may refresh its content: its lists
re-run their queries and its input doc is reloaded from its load action. The page
descriptor says when (§4.2):

- on a timer, every given number of seconds;
- with that timer stopped while the page is hidden;
- each time the page changes from hidden to visible.

A refresh never reloads an input doc that has unsaved changes; the user's edits win.

### 3.4 Descriptors and instances

A descriptor is a definition; an instance is one running copy of it.

| | Descriptor (definition) | Instance (running copy) |
| --- | --- | --- |
| App | app descriptor ID, e.g. `customer-admin` | an app instance, generated each time the app is opened |
| Page | page descriptor ID, e.g. `customer-form` | a panel, with a panel instance ID generated when the page is opened |
| Element | element descriptor ID, e.g. `customer-email` | an element instance ID, generated when its panel is drawn |
| Action | action descriptor ID, e.g. `save-customer` | an execution ID, generated for each run and used in logs |

The same page can be open in several panels at once, as `customer-form` is in the diagram
above. Each panel is a separate instance with its own input doc, so they never share data
by accident. Likewise, one element descriptor can be placed on many pages, or several
times on one page. Instance IDs are always generated by the system and never written in
descriptors.

### 3.5 Elements

An element is one visible part of a page. Every element has an `element_type` — a
built-in kind implemented once in the interpreter — and an element descriptor that
configures it:

```json
{
  "descriptor_id": "customer-email",
  "element_type": "input",
  "label": "Email",
  "data_binding": "$input_doc.email",
  "binding_mode": "read-write",
  "width": "elastic",
  "min_width": "200px",
  "max_width": "400px"
}
```

A page lists its elements in one of two ways:

- **By reference** to a stored element descriptor: `{ "element": "customer-email" }`.
  Attributes written next to the reference override the stored ones, so
  `{ "element": "customer-email", "binding_mode": "read-only" }` shows the same field
  without letting the user edit it.
- **Inline**, as a complete element descriptor whose ID only has to be unique within the
  page. This suits one-off elements such as a page's save button.

A **menu** element is a tree of items. An item either opens a page (through its `on_click`
action) or is a folder of further items. The menu keeps the panel bindings described in
§3.3. An example is in §4.2.

The [Ant Design component overview](https://ant.design/components/overview) is a good
catalogue of element types worth adding over time. It is a reference for *which* types to
offer, not an implementation: WPI element types are built with ChenWeb's own Svelte
components.

### 3.6 Lists

A **list** element shows a set of records, one record per row. Repetition is driven by the
data, not by repeating elements in the descriptor. The list's element descriptor says
which records to show and how to show *one* record; the list draws as many rows as there
are records.

```json
{
  "descriptor_id": "customer-list",
  "element_type": "list",
  "source": { "action": "load-customers" },
  "presentation": "rows",
  "columns": [
    { "field": "user_name", "label": "User name", "width": "elastic" },
    { "field": "email", "label": "Email", "width": "elastic" },
    { "field": "phone_number", "label": "Phone", "width": "160px" }
  ],
  "on_row_click": { "action": "open-customer", "args": { "id": "$record.id" } }
}
```

- `source` names the `load` action (§5.1) the list runs to query its own records when it is
  first drawn, and again whenever its page refreshes (§3.3). Most lists query their data
  themselves, and in the first iteration every list does. Passing records in from outside
  (for example through the input doc) may come later.
- Lists are read-only in the pilot.
- `presentation` chooses how records look. The pilot has `rows` (a table-like list);
  `cards` and other presentations come later.
- `columns[].field` is relative to one record. Inside a list, `$record` means the record
  of the row the user acted on.

### 3.7 Layouters

A layouter arranges a page's elements automatically, each layouter in its own way. WPI has
several layouters and each page names the one it uses. The pilot has one:

- **`flow-layouter`** treats the elements as a flow of visual components: it places them
  left to right and wraps to the next row when the next element does not fit in the
  current row.

Vertical stacks, label/field grids and others come later.

Size attributes (`width`, `height`) take one of three kinds of value:

- **A fixed length** such as `"240px"`. The layouter uses it as given.
- **`"elastic"`**. The layouter computes the size from the space available: the pane's
  width, the width already taken by fixed-size elements, the other elastic elements
  sharing the row, and each element's `min_width` and `max_width`. Elastic sizes are
  recomputed when the pane is resized.
- **`"auto"`**. The layouter decides, usually from the element's content or its own
  default.

More generally, any attribute set to `"auto"` or left out is decided by the system: size
and position by the layouter, appearance (font, color) by the theme. The pilot has no
appearance attributes at all, so every WPI page follows the theme, including dark mode.
Element classes (named style presets) come later (§9).

### 3.8 Input doc and data binding

Each panel has an **input doc**: a JSON document holding the data the page shows and
edits. A page descriptor contains no data. It only assumes data of a certain shape, so the
same page can show any data of that shape — any customer, for example.

An element binds to one attribute of the input doc through `data_binding`, written as a
path from the doc's root: `$input_doc.user_name`, `$input_doc.address.city`.
`binding_mode` (earlier called "mutability") says what the binding may do:

| `binding_mode` | Shows the doc's value | User can edit | Edits are written to the doc |
| --- | --- | --- | --- |
| `read-only` | yes | no | no |
| `read-write` | yes | yes | yes |

Changes made to the input doc in other ways, such as by an action, also update every
element bound to the changed attribute.

**The bindings define the shape of the doc.** A form for a new customer starts with an
empty input doc, `{}`. As the user types a user name, the `read-write` input bound to
`$input_doc.user_name` writes it, and the doc becomes `{"user_name": "..."}`. The phone
and email inputs do the same. Through the bindings the page builds a doc of exactly the
shape it needs, with no separate schema. Attributes that do not exist yet are created when
first written. The `save` action then says how that shape maps to table columns (§5).

### 3.9 Input doc lifecycle

1. **Load.** A requester — an action, an API or application code — retrieves data from the
   database and converts it into a JSON input doc. For a new record, the doc is `{}`.
2. **Open.** A panel is created from a page descriptor and the input doc. The interpreter
   keeps a copy of the doc as it was opened.
3. **Edit.** `read-write` elements change the doc as the user works.
4. **Save.** A save button runs the page's save action, which sends the doc to the backend.
   On success, the saved doc becomes the new unchanged copy.
5. **Close.** Before a panel is closed — by the user, by being replaced (§3.3) or by
   age-out — the interpreter checks whether the doc is *dirty*, i.e. differs from the last
   loaded or saved copy. If it is, the user is asked to save, discard, or keep editing.

Dirty means the content differs, so changing a field and changing it back is not dirty.

Hiding a panel is not closing it, so hiding never asks. Leaving the browser page checks
every panel, hidden ones included.

A page descriptor may name a default `input`: `{}` or a load action. It is used when the
page is opened without being given an input doc, for example from a menu. A page
descriptor also names its `save_action`, so the close prompt saves the same way the
page's save button does.

## 4. Descriptors by example

The examples together make up the `customer-admin` app drawn in §3.3.

### 4.1 App descriptor

```json
{
  "descriptor_id": "customer-admin",
  "schema_version": "0.1",
  "layout_template": "top-left-middle-right-bottom",
  "panes": {
    "top": { "height": "48px", "page": "app-header" },
    "left": { "width": "240px", "min_width": "160px", "resizable": true, "page": "customer-nav" },
    "middle": { "width": "elastic" },
    "right": { "width": "elastic", "min_width": "400px" }
  },
  "panel_retention": { "max_hidden_minutes": 30 }
}
```

- `panes` sets each pane's geometry and, optionally, the page it opens when the app
  starts. `bottom` is not mentioned, so this app has no footer.
- The middle pane starts empty; the menu fills it (§4.2). The right pane starts empty; a
  click on a customer fills it (§5.1).
- `panel_retention` is the age-out policy for hidden panels (§3.3).

### 4.2 Page descriptors

The menu page in the left pane:

```json
{
  "descriptor_id": "customer-nav",
  "schema_version": "0.1",
  "layouter": "flow-layouter",
  "elements": [
    {
      "descriptor_id": "nav",
      "element_type": "menu",
      "initial_item": "customers",
      "items": [
        {
          "item_id": "customers",
          "label": "Customers",
          "on_click": { "action_type": "open_page", "page": "customers", "pane": "middle" }
        },
        {
          "item_id": "new-customer",
          "label": "New customer",
          "on_click": { "action_type": "open_page", "page": "customer-form", "pane": "middle", "input": {} }
        }
      ]
    }
  ]
}
```

`initial_item` is the item the menu opens when the app starts. An item with `children`
instead of `on_click` is a folder.

The customer list page, refreshed every time it is shown again:

```json
{
  "descriptor_id": "customers",
  "schema_version": "0.1",
  "layouter": "flow-layouter",
  "refresh": { "on_show": true },
  "elements": [{ "element": "customer-list" }]
}
```

`refresh` takes `on_show` (refresh each time the page goes from hidden to visible),
`every_seconds` (refresh on a timer) and `while_hidden` (whether that timer keeps running
while the page is hidden; `false` by default).

The customer form:

```json
{
  "descriptor_id": "customer-form",
  "schema_version": "0.1",
  "layouter": "flow-layouter",
  "input": {},
  "save_action": "save-customer",
  "elements": [
    { "element": "customer-user-name" },
    { "element": "customer-phone-number" },
    { "element": "customer-email" },
    {
      "descriptor_id": "save",
      "element_type": "button",
      "label": "Save",
      "on_click": { "action": "save-customer" }
    },
    {
      "descriptor_id": "close",
      "element_type": "button",
      "label": "Close",
      "on_click": { "action_type": "close_page" }
    }
  ]
}
```

The three input fields are stored element descriptors like `customer-email` in §3.5. The
two buttons are inline. The close button's action is inline too, because `close_page`
needs no configuration. `app-header` is a page with a single text element.

Every descriptor carries `schema_version`, so an interpreter can reject a descriptor
written for a format it does not understand rather than misread it.

## 5. Actions

An action is an operation the interpreter performs. Action types are built in and
implemented once; an **action descriptor** configures one for a particular use. Elements
trigger actions through events. The pilot has three: a button's `on_click`, a menu item's
`on_click` and a list's `on_row_click`.

A trigger names an action descriptor (or writes one inline) and may pass arguments:

```json
{ "on_row_click": { "action": "open-customer", "args": { "id": "$record.id" } } }
```

Inside the action descriptor, `$args.id` refers to that argument. In the pilot, references
are plain substitutions — `$input_doc.<path>`, `$record.<field>`, `$args.<name>` — with
no calculations, comparisons or conditions.

### 5.1 Pilot action types

| `action_type` | What it does |
| --- | --- |
| `load` | Reads one record, or a list of records, from a table and returns them as JSON. |
| `save` | Sends the panel's input doc to the backend, which validates it and writes it to a table. |
| `open_page` | Opens a page in a pane with an input doc, either empty or produced by a load action. |
| `close_page` | Closes the panel that triggered it, after the unsaved-changes check. |

**`save`**

```json
{
  "descriptor_id": "save-customer",
  "action_type": "save",
  "table": "customers",
  "mode": "upsert",
  "key": "id",
  "fields": [
    { "attribute": "user_name", "column": "user_name", "required": true, "rules": { "max_length": 64 } },
    { "attribute": "phone_number", "column": "phone_number", "required": false, "rules": { "pattern": "^[0-9+ -]{6,20}$" } },
    { "attribute": "email", "column": "email", "required": true, "rules": { "format": "email" } }
  ]
}
```

- `fields` maps input doc attributes to table columns, and says which are required and
  how each is validated.
- `mode` is `insert`, `update` or `upsert` (insert when the doc has no key, update
  otherwise). After an insert the backend returns the new key, which is written into the
  input doc, so saving again updates the same row instead of inserting a duplicate.
- Validation always runs on the server. The browser may check the same rules first for
  quicker feedback, but the server's check is the one that counts. Errors come back per
  attribute and are shown next to the element bound to that attribute; the binding tells
  the interpreter which element that is.
- When two users save the same record, the last save wins. This is deliberately the
  simplest rule for the first iteration; detecting conflicting edits is a hard problem
  left for later.

**`load`**

```json
{
  "descriptor_id": "load-customer",
  "action_type": "load",
  "table": "customers",
  "result": "record",
  "where": { "id": "$args.id" },
  "fields": [
    { "column": "id", "attribute": "id" },
    { "column": "user_name", "attribute": "user_name" },
    { "column": "phone_number", "attribute": "phone_number" },
    { "column": "email", "attribute": "email" }
  ]
}
```

The field mapping mirrors `save`: columns become attributes on the way in, attributes
become columns on the way out. With `"result": "list"`, the action returns an array of
records, with optional `order_by` and `limit`; this is what a list element runs as its
`source` (§3.6). `where` supports equality only in the pilot.

**`open_page`**

```json
{
  "descriptor_id": "open-customer",
  "action_type": "open_page",
  "page": "customer-form",
  "pane": "right",
  "input": { "action": "load-customer", "args": { "id": "$args.id" } }
}
```

- `input` is `{}` for a new, empty doc, or a load action that produces the doc. Without
  it, the page's default `input` is used.
- `pane` names a pane of the app's layout template. An unknown pane is an error.
- The pane hides its current panel and shows the new one. Whether the hidden panel is kept
  or closed follows §3.3.
- When a menu item triggers `open_page`, the new panel is bound to that item (§3.3).

### 5.2 Which tables actions may touch

`load` and `save` may read and write any table in the database. `table` may include its
schema, e.g. `kb.metrics`. There is no allowlist; instead, the only way to reach a table
is to write a descriptor. The backend:

- runs only actions that come from descriptors stored in `kb.wpi_descriptors`. The browser
  says which stored action to run (by ID, or by its place inside a stored page) and supplies
  the arguments. It never sends a table name, a column name or a descriptor body;
- checks that the named table and columns exist, using the database catalog, and quotes
  them;
- passes values only as query parameters, never by building SQL text;
- requires a logged-in user;
- logs every action execution.

Database access goes through an adapter, so the database can be switched later. The pilot
supports PostgreSQL only.

## 6. Storage

Descriptors are stored in the `kb` schema of the `miner` database, versioned, following
the workspace rule that data belongs in the database. Proposed table, to be settled in the
OpenSpec change:

```text
kb.wpi_descriptors
  kind            'app' | 'page' | 'element' | 'action'
  descriptor_id   e.g. 'customer-form'
  version         integer, increasing per descriptor
  schema_version  descriptor format version
  body            JSONB, the descriptor itself
  status          'draft' | 'active' | 'retired'
  created_by, updated_by, created_at, updated_at
  unique (kind, descriptor_id, version)
```

- The interpreter uses the latest `active` version of each descriptor.
- The table is created by a goose migration.
- A WPI app reachable from ChenWeb's own menus also registers a `page_key` in
  `kb.page_def`. That table's comment currently says page structure stays in the
  frontend; it should be updated when WPI apps start registering there.
- Copying descriptors from staging to production needs an export/import path. Not in the
  pilot.

## 7. Validation and errors

Descriptors are checked when they are saved to the database and again before an app or
page is shown:

| Check | Example |
| --- | --- |
| Structure | Valid JSON; only attributes known to the app, page, element or action type |
| References | Every referenced app, page, element and action exists; every pane exists in the app's layout template |
| Tables | Every table and column named in a `load` or `save` action exists |
| Bindings | Paths are well formed; `__proto__`, `constructor` and `prototype` are rejected |
| Consistency | Every attribute in a `save` action is bound `read-write` by some element on the page (warning) |
| Capabilities | Every layout template, element type, layouter and action type is supported by this interpreter |

Failures are never silent. On screen, an error box replaces the element or page and names
the descriptor and the problem. On the backend, the failure is logged.

## 8. Pilot (phase 1)

**Goal:** build a simple menu-driven app, whose pages are lists and forms, entirely from
descriptors, with no page-specific frontend code.

**In scope**

- WPI apps opened by a URL holding the app ID, through one generic ChenWeb route.
- Layout templates `single-pane` and `top-left-middle-right-bottom`, with unused regions
  left out.
- Panes holding several panels: menu bindings, hidden panels kept for bound menu items,
  unbound panels closed when replaced, refresh when a page is shown again (`on_show`).
- Element types: `text`, `input`, `select` (pulldown menu with options listed in the
  descriptor), `button`, `list` (`rows` presentation, read-only, querying its own
  records) and `menu`.
- Layouter: `flow-layouter`, with fixed, elastic and auto sizes.
- Data binding: `$input_doc` paths, `read-only` and `read-write`, dirty tracking.
- Actions: `load`, `save`, `open_page`, `close_page`, triggered by `on_click` (buttons and
  menu items) and `on_row_click`.
- Storage in `kb.wpi_descriptors`, validation as in §7.

**Deliberately out of scope:** page state beyond the input doc, state machines,
conditions, action sequences, expressions, appearance attributes and element classes,
i18n of descriptor text (§9), editable lists, lists that receive records instead of
querying them, refreshing a visible list after a save in another pane, timed refresh,
panel age-out (in the pilot a hidden panel lives until it is closed or the app is closed),
paging and non-equality filters, protection against two users editing the same record
(last save wins), loading an app inside a page, `Collapse` and other elements that hold
panels, user-defined layout templates, LLM-generated descriptors.

**Done when**, on a small demo `customers` table and using only descriptors stored in
`kb.wpi_descriptors`, the `customer-admin` app of §4:

1. opens from its URL with a header, a menu on the left and the customer list in the
   middle;
2. switches between *Customers* and *New customer* in the menu without reloading either
   page: a half-filled new-customer form keeps its entries, and the customer list re-runs
   its query each time it is shown;
3. inserts a new customer from the form and shows a server validation error next to the
   right field;
4. opens a clicked customer in the right pane, saves edits as an update, and asks before
   replacing a customer that has unsaved edits.

### 8.1 Implementation notes for the pilot

These are about "how" and never appear in descriptors.

- Code lives in ChenWeb: frontend in `web/src/lib/wpi/`, backend in `server/api/wpi/`. It
  moves to `shared/` once a second project needs it.
- The input doc is held in Svelte 5 `$state`, which tracks changes deep inside the doc;
  bindings read and write it by path. WPI does not add its own reactivity system.
- A hidden panel stays mounted and is hidden with CSS, so its input doc and the state of
  its elements survive without reloading.
- Element types form a registry that maps each `element_type` to a Svelte component,
  wrapping the existing `components/ui` (bits-ui) parts. Layout templates are a similar
  registry of Svelte components.
- `flow-layouter` maps naturally onto CSS flexbox with wrapping. An elastic width is a
  flexible width with a basis and min/max limits, so widths are recomputed on pane resize
  without JavaScript. Resizable panes can use the existing `resizable` component.
- The interpreter's root element sets `select-text`, because the home3 dashboard shell
  sets `select-none`.
- The interpreter's own text — the unsaved-changes dialog, error boxes — is Svelte code and
  goes through Paraglide like all ChenWeb text. Only text written inside descriptors is
  untranslated in the pilot.
- Backend handlers log through `CreateDefaultLogger`.

## 9. After the pilot

The likely direction, decided phase by phase:

- **i18n of descriptor text.** Labels and other text in descriptors need English and
  Chinese. ChenWeb sends all text through Paraglide, which cannot reach text stored in the
  database, so this needs its own decision, probably an ADR amending ADR 2026093001.
  Until then, WPI apps are an exception to the "every page in English and Chinese" rule
  and should not be shown to end users.
- **More elements and presentation:** textarea, checkbox, date and number inputs, tabs;
  card presentation and editable lists; lists that receive their records from outside;
  paging and filters; appearance attributes and element classes; more layouters.
- **Elements that hold panels**, such as a `Collapse` whose folders each open a page.
  How this fits the pane and panel model is not worked out yet.
- **Timed refresh and panel age-out** (§3.3).
- **User-defined layout templates.**
- **Loading a WPI app inside an ordinary page** (§3.1), when a need appears.
- **Page state and richer actions:** state scopes, change events, conditions, action
  sequences, derived values (report §5–6).
- **Composition:** elements built from other elements, reusable parameterized actions,
  and registered domain services for logic that should not be declarative (report §8).
- **Workflows and state machines** for multi-step behavior.
- **Production runtime:** descriptor format migrations, permission capabilities,
  execution tracing, moving descriptors between staging and production.
- **LLM-generated pages:** an LLM writes descriptors, which are validated before use
  (report §11).

## 10. Confirmed rules

These rules fill gaps in the original design; all four were confirmed on 2026-10-26:

1. Menu items that open the same page with the same input share one panel (§3.3).
2. A panel that no menu item is bound to is closed, not hidden, when another panel
   replaces it (§3.3).
3. A refresh never reloads an input doc with unsaved changes, and a panel with unsaved
   changes is never aged out (§3.3).
4. A menu names an `initial_item`, opened when the app starts (§4.2).
