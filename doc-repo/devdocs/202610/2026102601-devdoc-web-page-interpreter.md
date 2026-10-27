# Web Page Interpreter (WPI)

**Date:** 2026-10-26 \
**Status:** Guiding design. The pilot (§8) was built and verified on 2026-10-26; see devdoc
[2026102603](2026102603-devdoc-wpi-pilot.md) and the ChenWeb OpenSpec change `wpi-pilot`. The
class/instance model of §3.5 and §5 (descriptor format `0.2`) was built and verified on
2026-10-27 (OpenSpec change `wpi-classes-and-instances`). \
**Background:** research report [2026102602](2026102602-devdoc-web-page-interpreter-research-report.md)

## Summary

A Web Page Interpreter (WPI) shows a web page from a description of the page instead of
from code written for that page. The description is a JSON document called a
*descriptor*. One interpreter, written once, can draw any page that can be described with
the parts it knows.

This document is the overall guide for WPI. The long-term goal is broad: apps, pages,
elements, actions and eventually application behavior, all described as data. We get
there step by step. The first step, the pilot, was built and verified on 2026-10-26: a
simple menu-driven app whose pages are lists and forms that load and save records, with a
few common actions, and nothing more: no page state beyond the data being edited, no
conditions, no state machines (§8; what was built is devdoc 2026102603). Each later phase
adds elements, actions or other constructs when real pages need them. §11 records what the
pilot taught.

## 1. Why: separating "what" from "how"

A web page mixes two things that change at very different rates:

- **What the page is**: which fields, buttons and lists it shows, where they go, which data
  they show. This changes all the time.
- **How a page is drawn and made to work**: turning a field into an input box, arranging
  elements on screen, saving data. This rarely changes.

In ordinary frontend code the two are mixed in every page file, so the amount of frontend
code grows with the number of pages. WPI moves the "what" into descriptors and keeps the
"how" in one interpreter. The interpreter's code then grows with the number of *kinds* of
things it supports (element classes, layouters, action classes), not with the number of
pages.
Separating the two is an act of abstraction: the programs are lifted away from the data
they use, so they become more or less pure logic.

Actions can be separated the same way. Take: "When an item in the `category_type`
pulldown menu is selected, open the page `show-metric-details` in the pane `right-pane`."
The pulldown, the page and the pane are the "what"; they belong in an action instance.
The "how" — opening some page in some pane — is pure logic that works for any pulldown,
any page and any pane.

What counts as "what" depends on the level. `open-page` is a "what" to a descriptor author
and a "how" inside the interpreter. The aim is not to remove every procedural idea from
descriptors, but to have descriptors *name* stable, reusable operations instead of
implementing them (report §3.4).

## 2. Guiding principles

1. **Descriptors are data, not code.** They are JSON and independent of any programming
   language or framework: no Svelte, DOM or JavaScript inside. Phase 1's interpreter uses
   Svelte for the frontend and Go for the backend, but another interpreter could read the
   same descriptors.
2. **A small vocabulary, grown by need.** WPI supports a fixed set of element classes,
   layouters, layout templates and action classes, each implemented once in code. A new
   one is added only when a real page needs it. The measure of success is how often a new
   page needs a new element class, action class or interpreter change; that number should
   fall over time.
3. **Definitions have descriptor IDs; running copies have instance IDs** (§3.4).
4. **Classes are named; instances are written where they are used.** Element and action
   classes are few and stored, and each class ID names the code that implements it
   (§3.5.1, §5). Element and action instances are written inside the page that uses them
   and are never stored by themselves.
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
| Element class | A kind of element, e.g. `input`. Its ID names the frontend code that draws it. Classes are few and stable. |
| Element instance | One use of an element class on a page, with its own values. Lives inside the page's descriptor. |
| Layouter | Arranges a page's elements in one specific way. |
| Action | An operation the interpreter performs, e.g. load data, save data, open a page. |
| Action class | A kind of action, e.g. `save`. Its ID names the code that performs it. Classes are few and stable. |
| Action instance | One use of an action class, with its own values, written where it is used. |
| Descriptor | A JSON document describing one app, page, element class or action class. Has a descriptor ID. |
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

- **Age-out** (planned; not in the pilot). The app descriptor sets how long a panel may
  stay hidden since it was last visible; older panels are closed. A panel with unsaved
  changes is never aged out.
- **Manually.** The user closes the panel (`close-page`).

A menu item whose panel has been removed opens its page afresh the next time it is
clicked.

**Refreshing a page.** Any page, visible or hidden, may refresh its content: its lists
re-run their queries and its input doc is reloaded from its `load` instance. The page
descriptor says when (§4.2):

- on a timer, every given number of seconds (planned; not in the pilot);
- with that timer stopped while the page is hidden (planned; not in the pilot);
- each time the page changes from hidden to visible.

A refresh never reloads an input doc that has unsaved changes; the user's edits win.

### 3.4 Descriptors and instances

A descriptor is a definition; an instance is one running copy of it.

| | Descriptor (definition) | Instance (running copy) |
| --- | --- | --- |
| App | app descriptor ID, e.g. `customer-admin` | an app instance, generated each time the app is opened |
| Page | page descriptor ID, e.g. `customer-form` | a panel, with a panel instance ID generated when the page is opened |
| Element | element class ID, e.g. `input` | an element instance ID, generated when its panel is drawn |
| Action | action class ID, e.g. `save` | an execution ID, generated for each run and used in logs |

The same page can be open in several panels at once, as `customer-form` is in the diagram
above. Each panel is a separate instance with its own input doc, so they never share data
by accident. Likewise, one element class can be placed on many pages, or several times on
one page. Instance IDs are always generated by the system and never written in
descriptors.

An element's attributes are split into *class attributes*, which all its instances share,
and *instance attributes*, which each instance may set (§3.5.1). Actions are split the
same way (§5); both are built (descriptor format `0.2`, 2026-10-27). Whether pages are too
is not decided yet.

### 3.5 Elements

#### 3.5.1 Element classes and instances

An element is one visible part of a page. Elements come as classes and instances, much as
objects do in C++:

- An **element class** is a kind of element, such as `input`, `pulldown-menu`,
  `toggle-button` or `check-box`. Each class maps to frontend code that draws it, so all
  elements of a class behave exactly the same; only their values differ. A class is
  stored as an element descriptor whose `descriptor_id` is the class ID.

**A class ID names its code.** The frontend keeps a registry of element code keyed by
class ID, so the class `input` is drawn by the code registered as `input`. There is no
separate element type: the class is the type. A class and its code are added, renamed and
removed together, and the validator reports a class that has no code in this interpreter
(§7).
- An **element instance** is one use of a class on a page, with its own values: for
  example, an `input` labelled "Phone" and bound to `$input_doc.phone_number`. Instances
  live inside their page's descriptor (§3.5.2) and are never stored by themselves. An
  instance's ID is generated by the system each time its panel is drawn, so it never
  appears in a descriptor.

Classes are few, normally no more than about 100, and stable: a class is added only
together with the code that implements it. Instances are many, thousands or more, and new
ones come with every new page. Keeping classes few is what makes pages easy to write. An
author picks from a short list of names that are easy to remember, instead of searching
an ever-growing set of one-off definitions that nobody can keep track of.

An element's attributes are of two kinds:

- **Class attributes** are shared by all instances of the class and cannot be changed by
  an instance, like static member data in C++. This document defines them, and every
  class has the same ones: `descriptor_id`, `schema_version` and `description`. More may
  be added, but rarely.
- **Instance attributes** belong to every instance, but each instance may give them its
  own value, like ordinary member data. The class's code defines which instance
  attributes exist: the ones many classes share (table below) and its own, such as a
  pulldown menu's `options`, a button's `on_click` or a list's `columns` (§3.6). The
  class row gives each a default value, or `null`, meaning every instance must set it; a
  page with an instance that does not fails validation (§7). Instance attributes the row
  leaves out are optional and have no default, such as a list's `on_row_click`. An
  instance that does not set an attribute uses the class's default.

Attributes that hold actions (`on_click`, `on_row_click`, `source` and a menu's `items`)
never have defaults: the class row gives them `null` or leaves them out. So every action
instance is written in a page (§5).

| Attribute | Kind | Meaning |
| --- | --- | --- |
| `descriptor_id` | class | The class ID, e.g. `input`; also the name of the frontend code that draws the class. |
| `schema_version` | class | The format version of the class's descriptor (§4.2). |
| `description` | class | What the class is for, so that authors can choose among classes. |
| `label` | instance | The text shown with the element, such as an input's caption or a button's text. |
| `data_binding` | instance | For elements that show data: the attribute of the input doc they show, e.g. `$input_doc.email` (§3.8). |
| `binding_mode` | instance | For elements that show data: `read-only` or `read-write` (§3.8). |
| `width`, `height` | instance | A length such as `"240px"`, `"elastic"` or `"auto"` (§3.7). |
| `min_width`, `max_width` | instance | The limits of an elastic width, as lengths (§3.7). |

`label` and `description` hold text for people, in one of two forms:

- a plain string, `"label": "Email"`, shown the same in every language;
- one text per language, keyed by the language codes ChenWeb uses:
  `"label": { "en": "Email", "zh-cn": "电子邮箱" }`. When the user's language is missing,
  the interpreter shows the `en` text, so this form must include `en`.

For now, a binding reaches only the panel's input doc, `$input_doc`. Bindings to other,
named docs may come later (§9).

The `input` class. Every instance must set `label` and `data_binding`; the other instance
attributes have defaults:

```json
{
  "descriptor_id": "input",
  "schema_version": "0.2",
  "description": { "en": "A one-line field for typing text", "zh-cn": "单行文本输入框" },
  "label": null,
  "data_binding": null,
  "binding_mode": "read-write",
  "input_type": "text",
  "width": "elastic",
  "min_width": "200px",
  "max_width": "400px"
}
```

**History.** The pilot (format `0.1`, 2026-10-26) had no stored element classes. Its kinds
of element were hard-coded and named in `element_type`, and its stored elements, such as
`customer-user-name`, were really instances stored by themselves. Format `0.2` replaced
them on 2026-10-27; the pilot's rows are retired.

#### 3.5.2 Elements and pages

A page lists its element instances, in order, in `elements`. Each instance names its class
in `element` and sets the instance attributes it needs; the rest come from the class's
defaults. The pilot's customer form fields become three instances of `input`:

```json
"elements": [
  { "element": "input", "label": "User name", "data_binding": "$input_doc.user_name" },
  { "element": "input", "label": { "en": "Phone", "zh-cn": "电话" }, "data_binding": "$input_doc.phone_number" },
  { "element": "input", "label": "Email", "data_binding": "$input_doc.email", "binding_mode": "read-only" }
]
```

The third instance sets `binding_mode` itself, so it shows the email without letting the
user edit it. An instance cannot set class attributes. A page cannot define a class
inline either: a class needs frontend code, so it is added together with that code.

Instances live only inside their page and have no rows of their own (§6). A field that
appears on two pages is written in both.

A **menu** element is a tree of items. An item either opens a page (through its `on_click`
action) or is a folder of further items. The menu keeps the panel bindings described in
§3.3. An example is in §4.2.

The [Ant Design component overview](https://ant.design/components/overview) is a good
catalogue of element classes worth adding over time. It is a reference for *which*
classes to offer, not an implementation: WPI element classes are built with ChenWeb's own
Svelte components.

### 3.6 Lists

A **list** element shows a set of records, one record per row. Repetition is driven by the
data, not by repeating elements in the descriptor. A list instance says which records to
show and how to show *one* record; the list draws as many rows as there are records. The
customer list, without its `on_row_click`, which is the `open-page` instance shown in §5.1:

```json
{
  "element": "list",
  "source": {
    "action": "load",
    "table": "customers",
    "result": "list",
    "fields": [
      { "column": "id", "attribute": "id" },
      { "column": "user_name", "attribute": "user_name" },
      { "column": "email", "attribute": "email" },
      { "column": "phone_number", "attribute": "phone_number" }
    ]
  },
  "presentation": "rows",
  "columns": [
    { "field": "user_name", "label": "User name", "width": "elastic" },
    { "field": "email", "label": "Email", "width": "elastic" },
    { "field": "phone_number", "label": "Phone", "width": "160px" }
  ]
}
```

- `source` is the `load` instance (§5.1) the list runs to query its own records when it is
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
Style presets (named sets of appearance attributes) come later (§9).

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

A page descriptor may name a default `input`: `{}` or a `load` instance. It is used when
the page is opened without being given an input doc, for example from a menu. A page
descriptor also holds its `save_action`, a `save` instance. The close prompt runs it, and
so does the page's save button through `save-page` (§5.1), so both save the same way.

## 4. Descriptors by example

The examples together make up the `customer-admin` app drawn in §3.3. The demo app seeded
in ChenWeb (migration `20261027000002_seed_wpi_classes_and_instances.sql`) follows them;
its menu items sit in a folder, and its actions name the demo table
`kb.wpi_demo_customers`. Every complete descriptor in this document passes the
interpreter's validator; the shorter examples in §3 and §5 leave out `schema_version`,
which every stored descriptor needs. Attributes that are planned but not yet supported are
named in the text, not in the JSON, because the validator rejects attributes it does not
know.

### 4.1 App descriptor

```json
{
  "descriptor_id": "customer-admin",
  "schema_version": "0.2",
  "layout_template": "top-left-middle-right-bottom",
  "panes": {
    "top": { "height": "48px", "page": "app-header" },
    "left": { "width": "240px", "min_width": "160px", "resizable": true, "page": "customer-nav" },
    "middle": { "width": "elastic" },
    "right": { "width": "elastic", "min_width": "400px" }
  }
}
```

- `panes` sets each pane's geometry and, optionally, the page it opens when the app
  starts. `bottom` is not mentioned, so this app has no footer.
- The middle pane starts empty; the menu fills it (§4.2). The right pane starts empty; a
  click on a customer fills it (§5.1).
- `resizable` lets the user drag the pane's edge. In the pilot it works only for panes
  with a fixed width in pixels.
- Planned: the age-out policy for hidden panels (§3.3) will be an app attribute such as
  `"panel_retention": {"max_hidden_minutes": 30}`.

### 4.2 Page descriptors

The menu page in the left pane:

```json
{
  "descriptor_id": "customer-nav",
  "schema_version": "0.2",
  "layouter": "flow-layouter",
  "elements": [
    {
      "element": "menu",
      "initial_item": "customers",
      "items": [
        {
          "item_id": "customers",
          "label": "Customers",
          "on_click": { "action": "open-page", "page": "customers", "pane": "middle" }
        },
        {
          "item_id": "new-customer",
          "label": "New customer",
          "on_click": { "action": "open-page", "page": "customer-form", "pane": "middle", "input": {} }
        }
      ]
    }
  ]
}
```

`initial_item` is the item the menu opens when the app starts. An item with `children`
instead of `on_click` is a folder.

The customer list page, refreshed every time it is shown again. Its list is the one of
§3.6, and its row click the `open-page` of §5.1:

```json
{
  "descriptor_id": "customers",
  "schema_version": "0.2",
  "layouter": "flow-layouter",
  "refresh": { "on_show": true },
  "elements": [
    { "element": "text", "text": "Customers", "width": "100%" },
    {
      "element": "list",
      "source": {
        "action": "load",
        "table": "customers",
        "result": "list",
        "fields": [
          { "column": "id", "attribute": "id" },
          { "column": "user_name", "attribute": "user_name" },
          { "column": "email", "attribute": "email" },
          { "column": "phone_number", "attribute": "phone_number" }
        ]
      },
      "columns": [
        { "field": "user_name", "label": "User name", "width": "elastic" },
        { "field": "email", "label": "Email", "width": "elastic" },
        { "field": "phone_number", "label": "Phone", "width": "160px" }
      ],
      "on_row_click": {
        "action": "open-page",
        "page": "customer-form",
        "pane": "right",
        "args": { "id": "$record.id" },
        "input": {
          "action": "load",
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
      }
    }
  ]
}
```

`refresh` takes `on_show` (refresh each time the page goes from hidden to visible). Timed
refresh is planned as `every_seconds` (refresh on a timer) and `while_hidden` (whether that
timer keeps running while the page is hidden; `false` by default); the pilot does not
support them yet.

The customer form:

```json
{
  "descriptor_id": "customer-form",
  "schema_version": "0.2",
  "layouter": "flow-layouter",
  "input": {},
  "save_action": {
    "action": "save",
    "table": "customers",
    "fields": [
      { "attribute": "user_name", "column": "user_name", "required": true, "rules": { "max_length": 64 } },
      { "attribute": "phone_number", "column": "phone_number", "rules": { "pattern": "^[0-9+ -]{6,20}$" } },
      { "attribute": "email", "column": "email", "required": true, "rules": { "format": "email" } }
    ]
  },
  "elements": [
    { "element": "input", "label": { "en": "User name", "zh-cn": "用户名" }, "data_binding": "$input_doc.user_name" },
    { "element": "input", "label": { "en": "Phone", "zh-cn": "电话" }, "data_binding": "$input_doc.phone_number" },
    { "element": "input", "label": { "en": "Email", "zh-cn": "电子邮箱" }, "input_type": "email", "data_binding": "$input_doc.email" },
    { "element": "button", "label": { "en": "Save", "zh-cn": "保存" }, "on_click": { "action": "save-page" } },
    { "element": "button", "label": { "en": "Close", "zh-cn": "关闭" }, "on_click": { "action": "close-page" } }
  ]
}
```

The fields and buttons are instances of `input` and `button` (§3.5.2), with labels in
English and Chinese; the inputs take their sizes and `binding_mode` from the class. The
Save button runs the page's `save_action` through `save-page`, and the Close button runs
`close-page`, which needs no attributes. `app-header` is a page with a single `text`
instance.

Every descriptor carries `schema_version`, so an interpreter can reject a descriptor
written for a format it does not understand rather than misread it.

## 5. Actions

An action is an operation the interpreter performs. Actions come as classes and instances,
exactly as elements do (§3.5.1):

- An **action class** is a kind of action, such as `load`, `save` or `open-page`. Its
  class ID is the name of the code that performs it: in the backend for `load` and `save`,
  in the frontend for `open-page`, `close-page` and `save-page`. Like element classes,
  action classes are few and stable, and a class is added only together with its code.
- An **action instance** is one use of a class, with its own values. It is written where
  it is used: in an element's trigger, in a list's `source`, in a page's `save_action`, or
  inside another instance, as with `open-page`'s `input`. Instances are never stored by
  themselves. Each run of an instance gets an execution ID (§3.4).

Action classes have the same class attributes as element classes: `descriptor_id`,
`schema_version` and `description`. Every action instance may set `args` (below); its
class's code defines the other instance attributes, and the class row gives each a default
or `null` (§3.5.1). An instance names its class in `action`:

```json
{ "on_click": { "action": "open-page", "page": "customer-form", "pane": "middle", "input": {} } }
```

Elements trigger actions through events. The pilot has three: a button's `on_click`, a
menu item's `on_click` and a list's `on_row_click`. A trigger may pass arguments in
`args`; inside the instance, and inside instances nested in it, `$args.<name>` refers to
them. A nested `load` that has `args` of its own receives those instead, resolved with
`$args` meaning the outer instance's arguments. The `open-page` example in §5.1 passes the
ID of the clicked customer this way. References are plain substitutions — `$input_doc.<path>`, `$record.<field>`,
`$args.<name>` — with no calculations, comparisons or conditions.

**History.** The pilot (format `0.1`) had no stored action classes: each action named a
hard-coded kind in `action_type`, its stored actions such as `save-customer` were single
uses stored by themselves, and triggers referred to them by ID. Format `0.2` replaced
them on 2026-10-27.

### 5.1 Action classes

| Class | What it does |
| --- | --- |
| `load` | Reads one record, or a list of records, from a table and returns them as JSON. |
| `save` | Sends the panel's input doc to the backend, which validates it and writes it to a table. |
| `open-page` | Opens a page in a pane with an input doc, either empty or produced by a `load` instance. |
| `close-page` | Closes the panel that triggered it, after the unsaved-changes check. |
| `save-page` | Runs the `save_action` of the panel that triggered it (§3.9). |

`close-page` and `save-page` have no instance attributes.

**`save`**, as the `save_action` of the `customer-form` page:

```json
{
  "action": "save",
  "table": "customers",
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
  otherwise). The `save` class defaults `mode` to `upsert` and `key` to `id`, so the
  example leaves both out. After an insert the backend returns the new key, which is written into the
  input doc, so saving again updates the same row instead of inserting a duplicate.
- Validation always runs on the server. The browser may check the same rules first for
  quicker feedback, but the server's check is the one that counts. Errors come back per
  attribute and are shown next to the element bound to that attribute; the binding tells
  the interpreter which element that is.
- When two users save the same record, the last save wins. This is deliberately the
  simplest rule for the first iteration; detecting conflicting edits is a hard problem
  left for later.

**`load` and `open-page`**, as the `on_row_click` of the customer list (§3.6). It opens
the clicked customer in the right pane, and its `input` is a `load` instance that reads
that customer:

```json
{
  "action": "open-page",
  "page": "customer-form",
  "pane": "right",
  "args": { "id": "$record.id" },
  "input": {
    "action": "load",
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
}
```

In `load`, the field mapping mirrors `save`: columns become attributes on the way in,
attributes become columns on the way out. With `"result": "list"`, a `load` instance
returns an array of records, with optional `order_by` and `limit`; this is what a list
runs as its `source` (§3.6). `where` supports equality only in the pilot.

In `open-page`:

- `input` is `{}` for a new, empty doc, or a `load` instance that produces the doc.
  Without it, the page's default `input` is used.
- `pane` names a pane of the app's layout template. An unknown pane is an error.
- The pane hides its current panel and shows the new one. Whether the hidden panel is kept
  or closed follows §3.3.
- When a menu item triggers `open-page`, the new panel is bound to that item (§3.3).

### 5.2 Which tables actions may touch

`load` and `save` may read and write any table in the database. `table` may include its
schema, e.g. `kb.metrics`. There is no allowlist; instead, the only way to reach a table
is to write a descriptor. The backend:

- runs only action instances written in pages stored in `kb.wpi_descriptors`. The browser
  names the instance by its place, the page's ID and the instance's JSON Pointer inside
  the page, and supplies the arguments. It never sends a table name, a column name or a
  descriptor body;
- checks that the named table and columns exist, using the database catalog, and quotes
  them;
- passes values only as query parameters, never by building SQL text;
- requires a logged-in user;
- logs every action execution.

Database access goes through an adapter, so the database can be switched later. The pilot
supports PostgreSQL only.

## 6. Storage

Descriptors are stored in the `kb` schema of the `miner` database, versioned, following
the workspace rule that data belongs in the database. The table is created by migration
`ChenWeb/project_migrations/20261026000001_create_kb_wpi_descriptors.sql`:

```text
kb.wpi_descriptors
  id              BIGSERIAL primary key
  kind            'app' | 'page' | 'element' | 'action'
  descriptor_id   e.g. 'customer-form'
  version         integer, increasing per descriptor
  schema_version  descriptor format version
  body            JSONB, the descriptor itself
  status          'draft' | 'active' | 'retired'
  created_by, updated_by, created_at, updated_at
  unique (kind, descriptor_id, version)
```

- `element` and `action` rows are classes, a small and stable set (§3.5.1, §5). Element
  and action instances live inside their page's descriptor and have no rows of their own,
  so loading a page never has to pick out its instances: the page row holds them all, and
  the classes they name are fetched together, one query per kind. The pilot's stored
  elements and actions (format `0.1`), such as `customer-email` and `save-customer`, were
  retired on 2026-10-27.
- The interpreter uses the latest `active` version of each descriptor.
- Versions are never edited in place. An admin writes a new version with
  `PUT /api/v1/wpi/descriptors/<kind>/<descriptor-id>`, which checks it first. There is no
  editor screen yet.
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
| Structure | Valid JSON; only attributes known to the app or page format, or named by the element or action class |
| References | Every referenced app, page, element and action exists; every pane exists in the app's layout template |
| Tables | Every table and column named in a `load` or `save` action exists |
| Bindings | Paths are well formed; `__proto__`, `constructor` and `prototype` are rejected |
| Consistency | Every attribute in a `save` action is bound `read-write` by some element on the page (warning) |
| Instances | An element or action instance sets only instance attributes its class names, and sets every one whose class value is `null` (§3.5.1, §5) |
| Capabilities | Every layout template and layouter is supported by this interpreter, and every element and action class has code registered under its class ID |

Failures are never silent. On screen, an error box replaces the element or page and names
the descriptor and the problem. On the backend, the failure is logged.

## 8. Pilot (phase 1)

**Status:** built and verified on 2026-10-26 (ChenWeb OpenSpec change `wpi-pilot`). All
four checks below passed in a browser against the real backend, database and frontend,
with a stand-in user in place of a login (ChenWeb has no test login). Where the code lives,
how to change an app and the pilot's limits: devdoc 2026102603.

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
conditions, action sequences, expressions, appearance attributes and style presets, the
split between class and instance attributes (§3.5.1, §5), i18n of descriptor text (§9), editable lists, lists that receive records instead of
querying them, refreshing a visible list after a save in another pane, timed refresh,
panel age-out (in the pilot a hidden panel lives until it is closed or the app is closed),
paging and non-equality filters, protection against two users editing the same record
(last save wins), loading an app inside a page, `Collapse` and other elements that hold
panels, user-defined layout templates, LLM-generated descriptors.

**Done when**, on the demo table `kb.wpi_demo_customers` and using only descriptors stored
in `kb.wpi_descriptors`, the `customer-admin` app of §4:

1. opens from its URL (`/wpi/customer-admin`) with a header, a menu on the left and the
   customer list in the middle;
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
- Element classes form a registry, `elementClasses` in `web/src/lib/wpi/elements/index.ts`,
  that maps each class ID to a Svelte component (§3.5.1); the backend validator keys what
  each class's code accepts the same way (`elementAttrs` and `actionAttrs` in
  `server/api/wpi/validate.go`). In the pilot the key was `element_type`.
  Inputs and buttons wrap the existing `components/ui` parts; the pulldown is a native
  `<select>` and the unsaved-changes prompt a native `<dialog>`. Layout templates and
  layouters are similar registries.
- `flow-layouter` maps naturally onto CSS flexbox with wrapping. An elastic width is a
  flexible width with a basis and min/max limits, so widths are recomputed on pane resize
  without JavaScript. A resizable pane with a fixed pixel width gets a drag handle on its
  inner edge; the existing `resizable` component sizes panes in percentages, which does not
  fit pixel and elastic panes.
- The interpreter's root element sets `select-text`, because the home3 dashboard shell
  sets `select-none`.
- The interpreter's own text — the unsaved-changes dialog, error boxes — is Svelte code and
  goes through Paraglide like all ChenWeb text. Only text written inside descriptors is
  untranslated in the pilot.
- Backend handlers log through `CreateDefaultLogger`.

## 9. After the pilot

The likely direction, decided phase by phase:

- **Updating visible pages after a save elsewhere.** The most visible gap in the pilot:
  after a customer is saved in the right pane, the list in the middle keeps showing the
  old values until it is shown again. A page needs a way to learn that data it shows has
  changed, for example an event such as "record saved" that lists listen to (§11).
- **Authoring descriptors.** The pilot has only the admin write endpoint. A way to browse,
  edit and preview descriptors comes before anyone other than a developer writes them.
- **Classes and instances.** Built for elements and actions on 2026-10-27 (OpenSpec change
  `wpi-classes-and-instances`). Still open: whether pages get the split too (§3.4);
  later, *extended attributes*: attributes a single instance adds that its class does not
  name, so that instances of one class can differ in more than their values.
- **i18n of descriptor text.** Labels and other text in descriptors need English and
  Chinese. Element labels and descriptions take a plain string or one text per language,
  falling back to `en` (§3.5.1); the same forms should cover the other text in
  descriptors, such as list column labels, menu item labels and select options. ChenWeb sends all text through Paraglide, which cannot
  reach text stored in the database, so this still needs its own decision, probably an ADR
  amending ADR 2026093001.
  Until then, WPI apps are an exception to the "every page in English and Chinese" rule
  and should not be shown to end users.
- **More elements and presentation:** textarea, checkbox, date and number inputs, tabs;
  card presentation and editable lists; lists that receive their records from outside;
  paging and filters; appearance attributes and style presets; more layouters.
- **Elements that hold panels**, such as a `Collapse` whose folders each open a page.
  How this fits the pane and panel model is not worked out yet.
- **Timed refresh and panel age-out** (§3.3).
- **User-defined layout templates.**
- **Loading a WPI app inside an ordinary page** (§3.1), when a need appears.
- **Page state and richer actions:** state scopes, named docs that bindings can reach
  besides `$input_doc` (§3.5.1), change events, conditions, action sequences, derived
  values (report §5–6).
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

## 11. What the pilot taught

Findings from building the pilot that matter for the next phases:

1. **Inline actions can live in elements as well as pages.** A stored element (a list, a
   menu) can carry its own trigger with an inline action, so the server names an action as
   `{kind, id, pointer}`: a stored action by ID, or the JSON Pointer of an inline action
   inside a stored page or element (§5.2).
2. **Strict validation keeps descriptors honest.** The validator rejects attributes it
   does not know, so a descriptor cannot quietly depend on a feature that does not exist
   yet (§4). The cost: each new attribute or type must be added in three places, namely
   the Go validator, the TypeScript types and the Svelte registry. Counting such changes
   per new page is the measure of principle 2.
3. **Visible pages go stale.** Refresh on show covers pages that are switched back to, but
   not two pages visible side by side (§9, first item). This is the first real need for
   events between pages.
4. **Dirty tracking needed content comparison.** Comparing a canonical copy of the doc,
   rather than counting edits, makes "change it back" not dirty and survives the server
   adding the new key after an insert.
