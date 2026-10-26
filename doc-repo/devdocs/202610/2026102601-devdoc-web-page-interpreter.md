# Web Page Interpreter (WPI)

**Date:** 2026-10-26 \
**Status:** Guiding design. Nothing is built yet; §8 defines the pilot. \
**Background:** research report [2026102602](2026102602-devdoc-web-page-interpreter-research-report.md)

## Summary

A Web Page Interpreter (WPI) shows a web page from a description of the page instead of
from code written for that page. The description is a JSON document called a
*descriptor*. One interpreter, written once, can draw any page that can be described with
the parts it knows.

This document is the overall guide for WPI. The long-term goal is broad: pages, elements,
actions and eventually application behavior, all described as data. We get there step by
step. The first step, the pilot, builds simple data pages — lists and forms that load and
save records — with a few common actions, and nothing more: no page state beyond the data
being edited, no conditions, no state machines. Each later phase adds elements, actions or
other constructs when real pages need them.

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
   layouters and action types, each implemented once in code. A new one is added only when
   a real page needs it. The measure of success is how often a new page needs a new element
   type, action type or interpreter change; that number should fall over time.
3. **Definitions have descriptor IDs; running copies have instance IDs** (§3.2).
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
| WPI App | What a user opens in the browser, through a URL. Defined by an app descriptor. |
| Layout template | A named way of dividing an app's viewport into panes, e.g. `single-pane`. |
| Descriptor | A JSON document describing one app, page, element or action. Has a descriptor ID. |
| Page | What a panel shows. Either a *content page* or a *split page*. |
| Pane | A rectangular area that controls geometry. Holds panels and shows one at a time. |
| Panel | One open page inside a pane: a page descriptor plus its data. |
| Element | One visible part of a page: text, input, pulldown menu, button, list. |
| Element type | A built-in kind of element implemented in the interpreter, e.g. `input`. |
| Layouter | Arranges a content page's elements in one specific way. |
| Action | An operation the interpreter performs, e.g. load data, save data, open a page. |
| Input doc | The JSON data a panel shows and edits. |
| Data binding | The link between an element and one attribute of the input doc. |
| Instance ID | Identity of one running copy of a page or element, generated by the system. |

### 3.1 WPI Apps, Pages, panes and panels

A WPI App can be opened directly in a web browser through URLs. 
WPI apps are not the conventional concept of applications,
but closely related. Conventional applications can be deployed individually
and independently, while WPI apps are not independent applications, unless
the application has one and only one page.

Pane defines and controls the geometry of its area: width and height, minimum and maximum
size, whether the user can resize it, and whether and how it scrolls. A pane holds one or more
**panels**. A panel shows one **page**: it takes a page descriptor (what the page is) and
lays out its elements with a layouter (how).

A page descriptor describes its content in one of two ways:

- **Content page**: a list of elements and the layouter that arranges them. Forms and
  lists are content pages. Most pages are content pages.
- **Split page**: divides its area into panes, each showing a panel with another page. A
  metric workspace with a category list on the left, a PDF viewer in the middle and metric
  details on the right is a split page.

A panel shows a page in the region of its parent pane. A split page is
an embedded WPI app, which uses a layout template to divide the region
of its parent pane, so pages nest. Nesting always ends
in content pages. A WPI page cannot be opened directly. It must be opened
with a WPI app.

```text
WPI App
└── Viewport 
    └── Panes
        └── Pane "top"
            └── Panel → page "customer-header"
        └── Pane "middle"
            └── Panel → page "customer-dashboard"
        └── Pane "bottom"
            └── Panel → page "customer-footer"
```

**How a pane handles multiple panels**

A pane always show one and only one page, which is done through a panel. 
A pane, however, can have multiple panels.
- A WPI app that has a menu tree on the left, a pane in the middle
  so that when clicking a menu item, the middle pane hide its current
  page, if any, and loads the corresponding 
  panel. The panel now is an instance of the page. The menu pane remembers
  the binding between the menu item and the panel instance id so that when
  the same menu item is clicked again, it can simple show the page instead of
  reloading it.
- A `Collapse` element (such as the one in https://ant.design/components/collapse)
  may have multiple multiple panels. When expanding a folder, if the panel
  has not been loaded yet, it loads the panel. It then shows the page (i.e., the 
  panel). When close a folder, it simply hides the panel, which can be re-expanded.
  Re-expanding a folder can be simply showing the page again, which can be extremely
  fast, instead of loading the same page again.

### 3.2 Descriptors and instances

A descriptor is a definition; an instance is one running copy of it.

| | Descriptor (definition) | Instance (running copy) |
| --- | --- | --- |
| App | app descriptor ID, e.g. `customer-admin` | an app instance, generated each time the app is opened or embedded |
| Page | page descriptor ID, e.g. `customer-form` | a panel, with a panel instance ID generated when the page is opened |
| Element | element descriptor ID, e.g. `customer-email` | an element instance ID, generated when its panel is drawn |
| Action | action descriptor ID, e.g. `save-customer` | an execution ID, generated for each run and used in logs |

The same page can be open in two panels at once, for example two customers side by side.
Each panel is a separate instance with its own input doc, so the two never share data by
accident. Likewise, one element descriptor can be placed on many pages, or several times on
one page. Instance IDs are always generated by the system and never written in
descriptors.

### 3.3 WPI App 
A WPI app is defined by an **App Descriptor.** 
An app describper has a browser viewport. 
It uses a **Layout Template** to divide its viewport into one or more panes. 

A "single-pane" layout template assumes 
there is on and only one pane in its viewport. A "top-left-middle-right-bottom" layout
template assumes:
- the viewport is divided into three rectangles: top, middle and bottom regions
- the top region is a pane
- the middle region is further divided into left, middle, and right regions, each is a pane
- the button region is a pane

Thus the viewport is divided into five regions: top, left, middle, right and buttom regions,
each is a **pane**.

### 3.4 Elements

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

A content page lists its elements in one of two ways:

- **By reference** to a stored element descriptor: `{ "element": "customer-email" }`.
  Attributes written next to the reference override the stored ones, so
  `{ "element": "customer-email", "binding_mode": "read-only" }` shows the same field
  without letting the user edit it.
- **Inline**, as a complete element descriptor whose ID only has to be unique within the
  page. This suits one-off elements such as a page's save button.

The [Ant Design component overview](https://ant.design/components/overview) is a good
catalogue of element types worth adding over time. It is a reference for *which* types to
offer, not an implementation: WPI element types are built with ChenWeb's own Svelte
components.

### 3.5 Lists

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
  first drawn. Most lists query their data themselves, and in the first iteration every
  list does. Passing records in from outside (for example through the input doc) may come
  later.
- Lists are read-only in the pilot.
- `presentation` chooses how records look. The pilot has `rows` (a table-like list);
  `cards` and other presentations come later.
- `columns[].field` is relative to one record. Inside a list, `$record` means the record
  of the row the user acted on.

### 3.6 Layouters

A layouter arranges a content page's elements automatically, each layouter in its own
way. WPI has several layouters and each content page names the one it uses. The pilot has
one:

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

### 3.7 Input doc and data binding

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

### 3.8 Input doc lifecycle

1. **Load.** A requester — an action, an API or application code — retrieves data from the
   database and converts it into a JSON input doc. For a new record, the doc is `{}`.
2. **Open.** A panel is created from a page descriptor and the input doc. The interpreter
   keeps a copy of the doc as it was opened.
3. **Edit.** `read-write` elements change the doc as the user works.
4. **Save.** A save button runs the page's save action, which sends the doc to the backend.
   On success, the saved doc becomes the new unchanged copy.
5. **Close.** Before the panel closes — or is replaced by another page, or the user leaves
   the browser page — the interpreter checks whether the doc is *dirty*, i.e. differs from
   the last loaded or saved copy. If it is, the user is asked to save, discard, or keep
   editing.

Dirty means the content differs, so changing a field and changing it back is not dirty.

Hiding a panel (§3.1) is not closing it: a hidden panel keeps its input doc, unsaved
changes included, and is checked only when it is finally closed. Leaving the browser page
checks every panel, hidden ones included.

A page descriptor may name a default `input`: `{}` or a load action. It is used when the
page is opened without being given an input doc, for example from a menu. A page
descriptor also names its `save_action`, so the close prompt saves the same way the
page's save button does.

## 4. Page descriptor

A content page, the customer form:

```json
{
  "descriptor_id": "customer-form",
  "schema_version": "0.1",
  "page_kind": "content",
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

The three input fields are stored element descriptors like `customer-email` in §3.3. The
two buttons are inline. The close button's action is inline too, because `close_page`
needs no configuration.

A split page, the customer workspace:

```json
{
  "descriptor_id": "customer-workspace",
  "schema_version": "0.1",
  "page_kind": "split",
  "direction": "horizontal",
  "panes": [
    {
      "pane_id": "left",
      "width": "elastic",
      "min_width": "320px",
      "resizable": true,
      "panel": { "page": "customer-list" }
    },
    {
      "pane_id": "right",
      "width": "elastic",
      "min_width": "400px"
    }
  ]
}
```

The left pane opens `customer-list`, whose list element queries the customers itself
(§3.5). The right pane starts empty; clicking a customer opens `customer-form` there (§5.1).

Every descriptor carries `schema_version`, so an interpreter can reject a descriptor
written for a format it does not understand rather than misread it.

## 5. Actions

An action is an operation the interpreter performs. Action types are built in and
implemented once; an **action descriptor** configures one for a particular use. Elements
trigger actions through events. The pilot has two: a button's `on_click` and a list's
`on_row_click`.

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
`source` (§3.5). `where` supports equality only in the pilot.

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
- `pane` is looked up in the app (or embedded app) that contains the panel where the event
  happened. If that app has no pane with this ID, the next enclosing app is searched. An
  unknown pane is an error.
- In the full design the pane hides its current panel and shows the new one, and an
  already-open panel can be shown again instead of reloaded (§3.1). In the pilot, where a
  pane has one panel, the current panel is replaced, after the unsaved-changes check.

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
- A WPI page reachable from a menu also registers a `page_key` in `kb.page_def`. That
  table's comment currently says page structure stays in the frontend; it should be
  updated when WPI pages start registering there.
- Copying descriptors from staging to production needs an export/import path. Not in the
  pilot.

## 7. Validation and errors

Descriptors are checked when they are saved to the database and again before a page is
shown:

| Check | Example |
| --- | --- |
| Structure | Valid JSON; only attributes known to the element, action or page type |
| References | Every referenced app, page, element, action and pane exists |
| Tables | Every table and column named in a `load` or `save` action exists |
| Bindings | Paths are well formed; `__proto__`, `constructor` and `prototype` are rejected |
| Consistency | Every attribute in a `save` action is bound `read-write` by some element on the page (warning) |
| Capabilities | Every element type, layouter and action type is supported by this interpreter |

Failures are never silent. On screen, an error box replaces the element or page and names
the descriptor and the problem. On the backend, the failure is logged.

## 8. Pilot (phase 1)

**Goal:** build simple data pages entirely from descriptors, with no page-specific
frontend code.

**In scope**

- Page kinds: content pages, and split pages with fixed panes and one panel per pane.
- Element types: `text`, `input`, `select` (pulldown menu with options listed in the
  descriptor), `button`, and `list` (`rows` presentation, read-only, querying its own
  records).
- Layouter: `flow-layouter`, with fixed, elastic and auto sizes.
- Data binding: `$input_doc` paths, `read-only` and `read-write`, dirty tracking.
- Actions: `load`, `save`, `open_page`, `close_page`, triggered by `on_click` and
  `on_row_click`.
- Storage in `kb.wpi_descriptors`, validation as in §7.
- One generic ChenWeb route that opens a WPI app by its descriptor ID.

**Deliberately out of scope:** page state beyond the input doc, state machines,
conditions, action sequences, expressions, appearance attributes and element classes,
i18n of descriptor text (§9), editable lists, lists that receive records instead of
querying them, refreshing a list after a save in another pane, paging and non-equality
filters, several panels per pane, protection against two users editing the same record
(last save wins), LLM-generated descriptors.

**Done when**, on a small demo `customers` table and using only descriptors stored in
`kb.wpi_descriptors`:

1. A *new customer* form — empty input doc, three `read-write` inputs, save and close
   buttons — inserts a row, shows a server validation error next to the right field, and
   warns about unsaved changes on close.
2. A *customer workspace* split page — list on the left, form on the right — opens the
   clicked customer in the right pane, saves edits as an update, and warns before
   replacing a customer with unsaved edits.

### 8.1 Implementation notes for the pilot

These are about "how" and never appear in descriptors.

- Code lives in ChenWeb: frontend in `web/src/lib/wpi/`, backend in `server/api/wpi/`. It
  moves to `shared/` once a second project needs it.
- The input doc is held in Svelte 5 `$state`, which tracks changes deep inside the doc;
  bindings read and write it by path. WPI does not add its own reactivity system.
- Element types form a registry that maps each `element_type` to a Svelte component,
  wrapping the existing `components/ui` (bits-ui) parts.
- `flow-layouter` maps naturally onto CSS flexbox with wrapping. An elastic width is a
  flexible width with a basis and min/max limits, so widths are recomputed on pane resize
  without JavaScript. Split pages can use the existing `resizable` component.
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
  Until then, WPI pages are an exception to the "every page in English and Chinese" rule
  and should not be shown to end users.
- **More elements and presentation:** textarea, checkbox, date and number inputs, tabs;
  card presentation and editable lists; lists that receive their records from outside;
  paging and filters; appearance attributes and element classes; more layouters.
- **Several panels per pane** (§3.1): menu-driven panes and the `Collapse` element.
- **Page state and richer actions:** state scopes, change events, conditions, action
  sequences, derived values (report §5–6).
- **Composition:** elements built from other elements, reusable parameterized actions,
  and registered domain services for logic that should not be declarative (report §8).
- **Workflows and state machines** for multi-step behavior.
- **Production runtime:** descriptor format migrations, permission capabilities,
  execution tracing, moving descriptors between staging and production.
- **LLM-generated pages:** an LLM writes descriptors, which are validated before use
  (report §11).

## 10. Open questions

Raised by the WPI App design (§3.1, §3.3):

1. Is a split page the same thing as an embedded WPI app? If so, a page could always be a
   content page, and a panel would show either a page or an embedded app.
2. Panes and the `Collapse` element both hold panels but show them differently: a pane
   shows exactly one, a Collapse any number. Should "panel host" be a general idea, with a
   visibility rule per kind of host?
3. Who remembers already-open panels so they can be shown again: the element that opened
   them (the menu, in §3.1), or the target pane, keyed by page and input?
4. When is a re-shown panel's data refreshed, and how many hidden panels may a pane keep?
5. Does every page need its own app descriptor, or can a built-in single-pane app wrap any
   page?
6. Layout templates: are they a built-in, named vocabulary like layouters? Can an app leave
   regions out (no bottom bar)? Where are pane sizes set? Which templates does the pilot
   need?
7. What does an app's URL hold: only the app ID, or also the page being shown, so that a
   reload or bookmark restores the view?
8. Are several panels per pane (menu-driven panes, `Collapse`) part of the pilot?
