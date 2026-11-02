# Web Page Interpreter (WPI)

**Date:** 2026-10-26 \
**Status:** Guiding design. The pilot ([Pilot](#pilot)) was built and verified on 2026-10-26; see devdoc
[2026102603](2026102603-devdoc-wpi-pilot.md) and the ChenWeb OpenSpec change `wpi-pilot`. The
class/instance model of [Elements](#elements) and [Actions](#actions) (descriptor format `0.2`) was built and verified on
2026-10-27 (OpenSpec change `wpi-classes-and-instances`), and so was the page design of
[Pages](#pages): no page classes, page attributes and input sources, storage in `kb.frontend_pages`
(OpenSpec change `wpi-pages`). The editor's *Create Element*, which defines an element
class as a draft before its code exists ([Element classes and instances](#element-classes-and-instances)), was built on 2026-10-27 (OpenSpec change
`wpi-create-element-class`), together with element class format `0.3`, in which each
instance attribute is an object with a help tip and a default. Code modules were built on
2026-10-28 (OpenSpec change `wpi-code-modules`): an element class names its code module in
`code_module_id` (element class format `0.4`), so that several classes can share one piece of
code; a class may fix attributes for all its instances; attributes a module does not support
are stored with a warning; and the code modules are listed in `kb.code_modules` and
documented in `KnowledgeStore/doc-repo/code_modules/` ([Element classes and instances](#element-classes-and-instances), [Code modules](#code-modules)). \
**Background:** research report [2026102602](2026102602-devdoc-web-page-interpreter-research-report.md) \
**Revised 2026-10-29:** the app is the higher level and no longer deals with page details.
Each page divides its own space into panes with a page layouter, and a panel holds the
elements of one pane ([Concepts](#concepts), [Pages](#pages), [Panes](#panes), [Panels](#panels)).
Layouter classes are stored in `kb.wpi_descriptors`. \
**Clarified 2026-10-30:** a page has exactly one root pane, and a page opened in a pane of
another page, with any number of panes, puts that pane in place of its root pane
([Opening a page](#opening-a-page)); a pane that switches to another page hides the one it was
showing and never closes it ([Panel Cache](#panel-cache)); every use of a class, whether
element, action or layouter, copies the whole class, so later changes to the class reach only
new copies ([Descriptors and instances](#descriptors-and-instances)); panes have margins
([Panes](#panes)); an `open-page` can name a pane of an outer page
([Action classes](#action-classes)). \
**Implemented 2026-10-30:** the revised design is built and verified (ChenWeb OpenSpec change
`wpi-pages-own-panes`): formats `0.5` for apps, pages and layouter classes, class copies filled
in when a page is written, the Panel Cache, the outward pane lookup, pane editing in the WPI
editor, and migration `20261030000001_wpi_pages_own_panes.sql`, which converted every stored
page. The pilot ([Pilot](#pilot), [What the pilot taught](#pilot-lessons)) followed the earlier
model, in which the app's panes held pages. Cross-references
in this document are links to a section by name, not section numbers, so that sections can be
added, removed and moved.

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
conditions, no state machines ([Pilot](#pilot); what was built is devdoc 2026102603). Each later phase
adds elements, actions or other constructs when real pages need them. [What the pilot taught](#pilot-lessons) records what the
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
things it supports (element classes, page layouters, element layouters, action classes), not with the number of
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
   page layouters, element layouters and action classes, each implemented once in code. A new
   one is added only when a real page needs it. The measure of success is how often a new
   page needs a new element class, action class or interpreter change; that number should
   fall over time.
3. **Definitions have descriptor IDs; running copies have instance IDs** ([Descriptors and instances](#descriptors-and-instances)).
4. **Classes are named; instances are written where they are used.** Element and action
   classes are few and stored, and each names the code that implements it: an element
   class in `code_module_id`, so that several classes can share one piece of code
   ([Code modules](#code-modules)), an action class by its class ID ([Actions](#actions)). Element and action instances are
   written inside the page that uses them and are never stored by themselves. Page layouters
   and element layouters are stored as classes too. Every use of a class copies the whole
   class, defaults included, and the copy has no further connection to it
   ([Descriptors and instances](#descriptors-and-instances)). Pages have no classes: each page is complete, and pages are reused by
   copying ([Reuse by copying](#reuse-by-copying)).
5. **Check before running; never fail silently.** Descriptors are validated before a page
   is shown. Anything that cannot be resolved shows a visible error in place and is logged
   ([Validation and errors](#validation-and-errors)).
6. **Descriptors ask; the server decides.** A descriptor can ask to load or save data. The
   backend runs only descriptors stored in the database, never descriptor text sent by the
   browser, and checks names and values before it touches any table ([Which tables actions may touch](#which-tables-actions-may-touch)). Descriptors may
   one day be written by an LLM, so they are never trusted just because they are not code.
7. **Data lives in the database.** Descriptors are stored in `kb` tables with a version
   column, not in Git ([Storage](#storage)).
8. **Incremental.** Each phase adds only what pages need. We do not design a complete
   declarative programming language up front (report §8).

<a id="concepts"></a>

## 3. Concepts

| Term | Meaning |
| --- | --- |
| WPI app | What a user opens in the browser. Has its own URL, which names the app. Provides the shell (header, footer) and a page area in which it shows one page at a time. Does not deal with page details. Defined by an app descriptor. |
| Page | Implements one HTML page. Has a page layouter, which divides the page's space into panes, and a panel for each pane. Complete in itself; has no class; pages are reused by copying. |
| Page layouter | Divides a page's space into panes, as a tree. Stored as a class that serves as a read-only template: a page copies all of it and then changes what it needs. |
| Pane | A rectangle of a page, created by the page layouter. Its geometry comes from the page layouter and the user can change it while the app runs. Holds one panel, or a page opened in it. |
| Page area | The space in which a page is rendered: the app's own page area (the browser tab or an iframe), or a pane of another page in which the page was opened. The app's page area shows one page instance; a pane shows one thing at a time, its own panel or a page opened in it ([Panel Cache](#panel-cache)). |
| Panel Cache | A frontend module that caches the pages opened in panes, as `(page-instance-id, pane-instance-id)` entries, so that a pane can show a page again without rendering it again ([Panel Cache](#panel-cache)). |
| Root pane | The pane at the root of a page's page layouter tree: the whole page. Every page has exactly one. |
| Single-pane page | A page whose root pane has no children, so it has one pane and one panel. Usually written with the `single-pane` page layouter. Earlier drafts called it a headless page. |
| Panel | The elements shown in one pane, and the element layouter that arranges them. Implements part of its page. Its geometry comes from its content and only its content can change it. |
| Element layouter | Arranges the elements of a panel in one specific way, e.g. `flow-layouter`. Stored as a class that serves as a read-only template: a panel copies all of it and then changes the parameters it needs. |
| Page instance | One open copy of a page: the page descriptor plus its input doc. Its panes and panels have instance IDs of their own; a page instance opened in a pane and then hidden is kept in the Panel Cache. |
| Element | One visible part of a page, placed in a panel: text, input, pulldown menu, button, list, menu. |
| Element class | A kind of element, e.g. `input`. Its `code_module_id` names the frontend code that draws it ([Code modules](#code-modules)). Classes are few and stable. |
| Code module | The frontend code that draws elements, e.g. `button`, listed in `kb.code_modules` and documented in `KnowledgeStore/doc-repo/code_modules/`. One code module may draw several classes, such as `simple-button` and `fancy-button` ([Code modules](#code-modules)). |
| Element instance | One use of an element class in a panel: a whole copy of the class, made when the element is placed and kept in the instance's `class`, plus the instance's own values. Later changes to the class do not reach it. Lives inside the page's descriptor. |
| Action | An operation the interpreter performs, e.g. load data, save data, open a page. |
| Action class | A kind of action, e.g. `save`. Its ID names the code that performs it. Classes are few and stable. |
| Action instance | One use of an action class: a copy of the class with its own values, written where it is used. |
| Descriptor | A JSON document describing one app, page, page layouter, element layouter, element class or action class. Has a descriptor ID. |
| Input doc | The JSON data a page instance shows and edits. |
| Data binding | The link between an element and one attribute of the input doc. |
| Instance ID | Identity of one running copy of anything addressable — an app, page, page layouter, pane, panel, element layouter or element — generated dynamically by the system. |

<a id="wpi-apps"></a>

### 3.1 WPI apps

A **WPI app** is what a user opens in a browser. Each app has its own URL, and the URL
names the app. A URL can also name a page to load ([Loading a page by URL](#loading-by-url)). Which page the app opens first comes from its
**app descriptor** ([App descriptor](#app-descriptor)). The app does not deal with page details: how a page is divided and
what it shows belong to the page ([Pages](#pages)).

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

`open-page` can also render a page in the current browser tab, in a new tab or in an iframe
instead of in a pane ([Action classes](#action-classes)). The page is then loaded together with
its app, which needs a URL ([Loading a page by URL](#loading-by-url)). This is planned, not in
the pilot.

Loading a WPI app *inside* an ordinary page may be useful later, much as an `<iframe>`
loads a separate document into a page while a `<div>` is part of the page itself. This is
deferred until it is needed ([After the pilot](#after-the-pilot)).

<a id="app-shell"></a>

#### 3.1.1 The app shell and the page area

The app provides what every page needs and no page repeats: the header and the
footer. What remains is the app's **page area**.

A **page area** is the space in which a page is rendered. There are two kinds:

- the **app's page area**, where the app opens its `initial_page`; it is what a browser tab, or
  an iframe, shows of the app;
- a **pane** of another page, when a page is opened in that pane (`open-page`, [Action classes](#action-classes)).

Rendering a page is the same in both: its page layouter creates the panes, and each pane's panel
renders its elements; in a pane, that pane takes the place of the page's root pane
([Opening a page](#opening-a-page)). The app's page area shows one page instance; a pane shows one thing at a time, its own panel
or a page opened in it, and keeps hidden pages in the Panel Cache ([Panel Cache](#panel-cache)). A page's own size attributes (`width`,
`height` and the limits) are measured inside its page area ([Page attributes](#page-attributes)).

A menu is not part of the shell. It is an ordinary element, placed in a panel like any other
([Elements in panels](#elements-in-panels)). The ChenWeb front end, for example, is a home page that
uses the `top-left-middle-right-bottom` page layouter; the panel of its `left` pane holds a menu
tree, and clicking a menu item opens the item's page in the `middle` pane
([A home page with a menu](#home-page-example)).

<a id="loading-by-url"></a>

#### 3.1.2 Loading a page by URL

A page can be loaded in two ways:

- **In a pane of the current page** (`open-page` with target `"pane"`). No URL is involved. The
  interpreter is already running in the browser and renders the page there
  ([Opening a page](#opening-a-page), [Panel Cache](#panel-cache)).
- **In a browser tab, a new tab or an iframe.** The browser needs a URL. A page that has no URL
  cannot be loaded this way, and trying it is an error.

The outline of loading a page by URL:

1. Given a URL, the browser sends a request to the backend.
2. The backend routes the URL to the corresponding handler.
3. The handler determines whether the URL is for a conventional (HTML) page or for a WPI page.
4. For a conventional page, the handler does what it does now. For a WPI page, it renders the WPI
   page, that is, the page inside its app: the page layouter creates the panes and each pane's
   panel renders its elements.

Not designed yet: the shape of the URL (today `/wpi/<app-id>` names only the app; it must also
name the page and its arguments); how the handler tells a WPI page from a conventional page, for
example by a registry of URLs (the existing `kb.page_def`, [Storage](#storage)); how the input is
passed (a URL can carry only arguments; a `load`, `query` or `load-file` input is run again by the
backend); access control; and what an iframe may do.

<a id="pages"></a>

### 3.2 Pages

A page implements an HTML page. It is made of three kinds of part, and each kind has its own
attributes and its own geometry:

| | Page | Pane | Panel |
| --- | --- | --- | --- |
| What it is | The whole HTML page. | A rectangle of the page, created by the page's page layouter. | The elements shown in one pane, with the element layouter that arranges them. |
| Where its geometry comes from | The page's `width` and `height`, inside its page area. | The page layouter. The user can change it while the app runs, if the pane is `resizable`. | Its content, and nothing else. Only its content can change it. |
| Smaller than its container | The page's `hori_align` and `vert_align` place it in its page area; in a pane of another page, that pane's do ([Opening a page](#opening-a-page)). | The pane's `hori_align` and `vert_align` place its panel inside the pane's margins. | Not applicable. |
| Bigger than its container | The page's `hori_scrollbar` and `vert_scrollbar` decide: scroll or hide; in a pane of another page, that pane's do. | The pane's `hori_scrollbar` and `vert_scrollbar` decide, counting the pane's margins: scroll or hide. | Not applicable. |
| Stored in | A row of `kb.frontend_pages`. | The page's `page_layouter`. | The page's `panels`. |
| Attributes | Page attributes ([Page attributes](#page-attributes)) | Panes ([Panes](#panes)) | Panels ([Panels](#panels)) |

A page has a **page layouter** ([Page layouters](#page-layouters)), which creates its panes, and a **panel** for each
pane. So the panes not only divide the page's space; they also decide which elements go where:
the elements of a pane's panel are drawn in that pane. A panel implements part of its page,
through its elements. It is not the page, except when the page has only one pane. A page always
has exactly one **root pane**, the root of its page layouter's tree, which is the whole page; a
page without a `page_layouter` is an error ([Validation and errors](#validation-and-errors)).

**Single-pane pages.** A page whose root pane has no children is a *single-pane page*: its root
pane is its only pane, and it has one panel. (Earlier drafts called it a *headless* page.) The
interpreter treats it like every other page; the page layouter `single-pane` is the usual way
to write one. The root pane matters when a page is opened in a pane of another page: that pane
always takes the place of the page's root pane. For a single-pane page this leaves only its
panel, rendered in that pane ([Opening a page](#opening-a-page)).

Pages have no classes. Each page is complete in itself, much like an HTML file, and pages are
reused by copying them ([Reuse by copying](#reuse-by-copying)). Elements, actions and page layouters do come as classes, and
using one copies it ([Descriptors and instances](#descriptors-and-instances)).

<a id="page-layouters"></a>

#### 3.2.1 Page layouters

A page layouter divides a page's space into panes. Page layouter classes are defined by
descriptors stored in `kb.wpi_descriptors` with `kind` = `page-layouter`. The division is a
**tree**:

- The root of the tree is a pane that is the whole page, the page's root pane. A page has
  exactly one.
- A pane is either a leaf or is split. A split pane has `split`, which is `"rows"` (the
  children are stacked from top to bottom and divide the pane's height) or `"columns"` (the
  children sit side by side from left to right and divide its width), and `children`, two or
  more child panes.
- Any child can be split in turn, in either direction, to any depth.
- Only leaf panes hold panels.

Pane IDs are unique in a page. A split pane has an ID too (below, `middle-row`), but only the
leaf panes have panels. The pilot has two page layouters:

- **`single-pane`**: the root is one leaf, `main`.
- **`top-left-middle-right-bottom`**: the root is split into three rows, `top`, `middle-row`
  and `bottom`; `middle-row` is split into three columns, `left`, `middle` and `right`. That
  gives five leaf panes: `top`, `left`, `middle`, `right` and `bottom`. As a tree:

```json
{
  "pane_id": "page",
  "split": "rows",
  "children": [
    { "pane_id": "top", "height": "48px" },
    { "pane_id": "middle-row", "height": "elastic", "split": "columns", "children": [
      { "pane_id": "left", "width": "240px", "min_width": "160px", "resizable": true },
      { "pane_id": "middle", "width": "elastic" },
      { "pane_id": "right", "width": "elastic", "min_width": "400px" }
    ] },
    { "pane_id": "bottom", "height": "32px" }
  ]
}
```

A page that leaves a region out uses a tree without it; a page without a footer omits `bottom`.
The size of the root pane is not used: the root is the page, and the page's own `width` and
`height` apply ([Page attributes](#page-attributes)).

**A page layouter class** is stored in `kb.wpi_descriptors` with `kind`
`page-layouter` ([Storage](#storage)). An element layouter is stored the same way, with `kind`
`element-layouter` ([Element layouters](#element-layouters)), and a panel copies it as a page copies a page layouter. A page layouter has the following attributes:

| Attribute | Data Type | Default | Explanation | Validation |
|-----------|-----------|---------|-------------|------------|
| descriptor_id | string | none | identifies the layouter | letters, digits, '-', max length: 64 |
| schema_version | string | none | the format version of the descriptor | not null |
| description | string or language map | "" | the layouter description | max length: 1000 |
| code_module_id | string | none | the code module that draws the tree; many layouters can share one | an active module of type `page-layouter` in `kb.code_modules` ([Code modules](#code-modules)) |
| root | object | none | the root pane of the tree, with default values | pane IDs are unique; a split pane has `split` and two or more `children`; the pane attributes are valid ([Panes](#panes)) |

**A page has a layouter instance.** A page layouter class is a template, and it is read-only:
using it never changes it, and only an admin changes it, by storing a new version. A page
that uses one copies all of it, as an element instance copies its class
([Element classes and instances](#element-classes-and-instances)): the whole class row goes
into the instance's `class` as a snapshot, and the page's own values sit beside it. The whole
instance is the page's `page_layouter`:

```json
"page_layouter": {
  "layouter": "single-pane",
  "class": {
    "descriptor_id": "single-pane",
    "schema_version": "0.5",
    "description": { "en": "One pane: the whole page", "zh-cn": "单个窗格：整个页面" },
    "code_module_id": "page-layouter",
    "root": { "pane_id": "main" }
  },
  "root": { "pane_id": "main", "hori_align": "left" }
}
```

`layouter` names the class and must equal the class snapshot's `descriptor_id`; the snapshot's
`code_module_id` names the code that draws the tree. The page's own `root`, when set, replaces
the snapshot's `root` whole; without it the page uses the snapshot's tree. The snapshot has no
connection to its class. The page may change any value in its tree, and may leave panes out or
add panes, as the home page of [A home page with a menu](#home-page-example) leaves out
`bottom`. Modifying or retiring the class does not change the pages that copied it. A pane
attribute that the tree does not set takes its default from [Panes](#panes); those defaults
belong to the format, not to the class. Other examples in this document leave `class` out.

#### 3.2.1.1 Pane Layouter in WPI Editor
- It shows panes, or outlines panes with rectangles with a dim color dash line.
- There is a slider between adjacent edges of panes so that users can drag-and-adjust
  pane width/height.
- Users can visually split a pane in to, either horizontally or vertically
- Users can visually merge two or more panes into one
- Users can change pane_ids, duplicated pane_ids are detected and rejected
- The last pane in each split fills unused space in the editor. Pane boundaries can be dragged
  past their minimum or maximum size; an exceeded limit is adjusted to the resulting size.
  Pane widths and heights cannot be dragged below 20px in the editor.
- Dragging a pane edge on the outside of the page changes the page size and the pane size.
  Dragging the preview corner continues to resize the editor surface.

<a id="panes"></a>

#### 3.2.2 Panes

A pane is a rectangle of a page, created by the page's page layouter ([Page layouters](#page-layouters)). Panes
not only divide the page's space; they also decide which elements go where, because each leaf
pane holds one panel and the elements of that panel are drawn in that pane. A pane's geometry
is set by its page layouter and can be changed while the app runs: the user drags the edge of
a pane that is `resizable`. A panel's geometry is different: it comes from the panel's
content alone ([Panels](#panels)).

Panes have the following attributes. A pane is either a *leaf* or *split* into child panes
([Page layouters](#page-layouters)). All panes may set margins: a split pane places its children inside them, and a leaf pane places
its content inside them. Only a leaf pane holds a panel, so `hori_align`, `vert_align`,
`hori_scrollbar` and `vert_scrollbar` apply to leaf panes only.

| Attribute | Data Type | Default | Explanation | Validation |
|-----------|-----------|---------|-------------|------------|
| pane_id | string | none | identifies the pane within its page; for a leaf pane it is the key of its panel in the page's `panels` | letters, digits, '-', max length 64; unique within the page |
| width | string | "elastic" | the pane's width | a length, a percentage, "elastic" or "auto" (below) |
| height | string | "elastic" | the pane's height | same as `width` |
| min_width | string | "50px" | the least width the pane may have | a length or a percentage |
| min_height | string | "50px" | the least height the pane may have | a length or a percentage |
| max_width | string | null | the greatest width the pane may have; null means no limit | a length or a percentage |
| max_height | string | null | the greatest height the pane may have; null means no limit | a length or a percentage |
| resizable | boolean | false | whether the user can drag the pane's edge to change its size | true or false |
| background_color, foreground_color | color | none | pane background and inherited text color | CSS color or light/dark pair (below) |
| left_margin, right_margin, top_margin, bottom_margin | string | "0px" | the space between the pane's edges and its content or children; counted when deciding whether they fit (below) | a length |
| hori_align | string | "center" | where the panel sits in the pane when it is narrower than the space inside the margins | "left", "center" or "right" |
| vert_align | string | "top" | where the panel sits in the pane when it is shorter than the space inside the margins | "top", "center" or "bottom" |
| hori_scrollbar | string | "auto" | what happens when the panel and the left and right margins are wider than the pane | "auto" or "hide" |
| vert_scrollbar | string | "auto" | what happens when the panel and the top and bottom margins are taller than the pane | "auto" or "hide" |
| `border_thickness` | nonnegative values in 'px' | none | If not defined or its value is 0, do not draw borders. Otherwise, draw pane borders with the specified thickness | value must be nonnegative |
| `border_dark_color` | color | none | The pane border color in the dark mode. Applicable only when `border_thickness` > 0. If not specified, it uses a light color | valid color values |
| `border_light_color` | color | none | The pane border color in the light mode. Applicable only when `border_thickness` > 0. If not specified, it uses a dark color | valid color values |

A pane inherits each unset color independently from the closest ancestor pane that sets it.
For example, if the root sets a red background and white foreground, and a child sets only
a blue foreground, that child and its unset descendants use a red background and blue
foreground. A descendant can override either color without changing the other. An absent
value or `null` is unset. The effective pane background takes precedence over the panel's
background, even when the pane inherited it ([Panels](#panels)).

Values for a pane's `width` and `height`:

- **A length**: a non-negative number, optionally followed by `px`, `rem` or `em`. A number
  without a unit is in `px`. Example: `"240px"`.
- **A percentage**: a share of the pane that contains it, or of the page for the root pane.
  Example: `"30%"`.
- **`"elastic"`**: the pane takes what is left after its fixed, percentage and `auto` siblings, within
  its `min_` and `max_` limits. Elastic siblings share that space equally. The size is
  recomputed when the page is resized.
- **`"auto"`**: for a leaf pane, the size of its panel's content; for a split pane, the size
  its children need. The `min_` and `max_` limits still apply. A leaf pane whose width is
  `"auto"` gives its elements no width to be measured against ([Panels](#panels)).

A panel can be smaller or bigger than its pane. The margins come first: the panel is placed in
the space inside them, and a panel fits in a direction only if the panel and the two margins of
that direction together fit in the pane. When it is smaller in a direction, `hori_align` and
`vert_align` decide where it sits. When it does not fit in a direction, `hori_scrollbar` or
`vert_scrollbar` decides: with `"auto"` the pane shows a scroll bar in that direction; with
`"hide"` it shows no scroll bar and the extra content is not visible. The same rules, with the
page's own attributes, apply to a page that is smaller or bigger than its page area
([Page attributes](#page-attributes)).

A leaf pane shows one thing at any given time: its own panel, or a page opened in it
([Opening a page](#opening-a-page), [Panel Cache](#panel-cache)). The pane's margins, alignment and scroll bar attributes apply to
whatever it shows.

Each unset border attribute inherits independently from the closest ancestor that sets it. An absent value or `null` is unset; an explicit `0px` thickness disables the border for that pane and its descendants unless overridden. Thickness is a nonnegative pixel length such as `2px`. When no color is set, the border is black in light mode and white in dark mode.

<a id="page-attributes"></a>

#### 3.2.3 Page attributes

These are the attributes of the page itself. The attributes of its panes ([Panes](#panes)) and panels
([Panels](#panels)) are different and are not repeated here. Defaults, lengths and colors follow
[Page Interpreter](../../code_modules/interpreter-page.md).

| Attribute | Meaning |
| --- | --- |
| `descriptor_id` | The page's ID, chosen by its author, e.g. `customer-form`. The app's `initial_page` and actions name the page by it: `open-page`'s `page`. |
| `schema_version` | The format version of the page's descriptor ([Descriptors by example](#descriptors-by-example)). |
| `page_name` | The page's name as people see it, e.g. "Customers". |
| `description` | What the page is for. Authors search names and descriptions when looking for a page to reuse ([Reuse by copying](#reuse-by-copying)). |
| `keywords`, `page_tags` | Words and categories that authors search, like `page_name` and `description`. |
| `access_controls` | The user roles that may use the page. None, or an empty list, lets every logged-in user use it, and an admin counts as having the role `admin`. A page the user may not use is left out of the app, and reading it or running an action written in it is refused. |
| `page_layouter` | The page layouter instance: a class snapshot and the page's own values, including its pane tree ([Page layouters](#page-layouters)). |
| `panels` | The page's panels, keyed by the `pane_id` of the leaf pane each one fills ([Panels](#panels)). |
| `input` | Where the page's input doc comes from when the page is opened without being given one ([Page input](#page-input)). |
| `save_action` | The `save` instance that saves the input doc; the close prompt and `save-page` run it ([Input doc lifecycle](#input-doc-lifecycle)). |
| `refresh` | When the page reloads its content, e.g. `{ "on_show": true }` ([Panel Cache](#panel-cache), [Page descriptors](#page-descriptors)). |
| `width`, `height` | The page's own size: the space its page layouter divides into panes. A length such as `"800px"`, a percentage of its page area, or `auto` (default). With `auto` the page is as wide as its page area; its height is that of the page area when the page has `elastic` rows, and otherwise the height of its panes. |
| `min_width`, `min_height`, `max_width`, `max_height` | Limits on the page's size as its page area is resized. A form usually sets `max_width`, so that it does not stretch across a wide page area. |
| `hori_align`, `vert_align` | Where the page sits in its page area when it is smaller: `left`, `center` (default) or `right`; `top` (default), `center` or `bottom`. |
| `hori_scrollbar`, `vert_scrollbar` | What happens when the page is bigger than its page area. `auto` (default) shows a scroll bar in that direction; `hide` shows none, and the extra content is not visible. |
| `bkgd_color`, `frgd_color` | The page's background and foreground colors. `auto` (default) follows the theme. |
| `page_style` | The name of the Page Style that gives the page and its elements their look ([Elements and page styles](#elements-and-page-styles)). Page styles are a later phase and are not supported now; the current code accepts the name and ignores it. |
| `page_policy` | The name of the page policy: rules shared by all pages. A later phase, like `page_style`; the current code accepts the name and ignores it. |
| `binding_mode` | The default `binding_mode` of the page's elements that show data ([Input doc and data binding](#input-doc-and-data-binding)); a viewer page sets `read-only`. An element instance's own value comes first, then the page's, then the default in the instance's class copy ([Element classes and instances](#element-classes-and-instances)). |

`descriptor_id`, `schema_version` and `page_layouter` are required; the rest are
optional. The interpreter does not show `page_name`, `description`, `keywords` or
`page_tags`; they are what authors search when they look for a page to reuse
([Reuse by copying](#reuse-by-copying)).

When the page is opened in a pane of another page, that pane takes the place of both the
page's page area and its root pane. The page's size attributes and colors still apply,
measured inside that pane, but the pane's margins, `hori_align`, `vert_align`, `hori_scrollbar`
and `vert_scrollbar` are used instead of the page's ([Opening a page](#opening-a-page)).

Margins are pane attributes in the revised design ([Panes](#panes)). The code today has
`left_margin`, `right_margin`, `top_margin` and `bottom_margin` on the page, default `30px`
([Page Interpreter](../../code_modules/interpreter-page.md)).

`page_name` and `description` hold text for people in the same two forms as an element's
`label` ([Element classes and instances](#element-classes-and-instances)): a plain string, `"page_name": "Customers"`, or one text per language,
`"page_name": { "en": "Customers", "zh-cn": "客户" }`, which falls back to `en`.

<a id="page-input"></a>

#### 3.2.4 Input

Most pages need data. A form for a new customer builds a JSON doc and saves it to the
database; a `customers` page reads customer records from the database and shows them. A
page's `input` says where its input doc ([Input doc and data binding](#input-doc-and-data-binding)) comes from when the page is opened without
being given one, for example from a menu. `open-page` can give it one instead, in the same
forms ([Action classes](#action-classes)).

| `input` | The page starts with |
| --- | --- |
| left out, or `{}` | An empty doc, which its `read-write` elements fill in ([Input doc and data binding](#input-doc-and-data-binding)). Pages that show no data, such as a header or a menu, leave `input` out. |
| any other object without an `action` attribute | That object, as the page's static data ([Input doc and data binding](#input-doc-and-data-binding)). |
| a `load` instance | Data read from a table ([Action classes](#action-classes)). |
| a `query` instance | The result of a named SQL statement (below). |
| a `load-file` instance | The content of a file named by its ID (below). |

An object with an `action` attribute is an action instance; any other object is the doc
itself. Static data therefore cannot have a top-level attribute named `action`.

**SQL statements and file contents never appear in descriptors.** Descriptors travel over
the network: to the browser when an app is opened, and to the server when they are saved.
Some customers' firewalls block any traffic that carries SQL text. So an SQL statement is
stored on the server under a readable name, and a `query` instance names only that name, its
`sql_stmt_id`. Files are kept out the same way: a `load-file` instance names a stored file
by its `file_id`. Two tables hold them, and neither can be written through the WPI API, so
rows come from migrations or `psql`:

```text
kb.stored_stmts   stmt_name, sql_stmt, description, creator, access_controls
kb.stored_files   file_name, file_content (a JSON object), description, creator, access_controls
```

`access_controls` lists the user roles that may use a row; none, an empty list, or one
containing `all` lets every logged-in user use it, and an admin counts as having the role
`admin`. A `query` instance sets `result` (`record` or `list`) and may set `params`, values
bound in order to the statement's `$1`, `$2`, … as query parameters, never pasted into its
text; `$args.<name>` works in them as in `load`'s `where`. The statement runs in a
read-only transaction with a 10-second limit; each row comes back as a JSON object keyed
by the statement's column names, and a list returns at most 1000 rows. `query` also works as a
list's `source`; `load-file` does not, since a file is one doc. `load` and `save` are
unchanged: they name tables and columns, never SQL ([Which tables actions may touch](#which-tables-actions-may-touch)).

<a id="reuse-by-copying"></a>

#### 3.2.5 Reuse by copying

Pages are reused by copying them, not through classes. To build a page that views and edits
customers, an author first searches the stored pages, by name and description, for one
that fits:

- If one fits exactly, it is used as it is: whatever needs it names its ID.
- If one is close, the author copies it, changes the copy and saves it under a new ID.
- If none is close, the author writes a new page.

Page classes, with pages as their instances, were considered and rejected on 2026-10-27.
Someone would first have to write a class before others could make pages from it, which is
harder to understand than one kind of page, stored and shown as it is. Copying has two
known costs, accepted as not critical:

- It is hard to tell whether two pages were copied from the same page.
- A change meant for every page of one kind, such as adding a `fax_number` field to every
  customer page, has to be made in each page.

The WPI editor's **Load Page** button opens a searchable dialog with 20 pages per
screen. It lists each page's latest active version from `kb.frontend_pages`, with its
ID, localized name and description, and creation/update times. Authors can filter by
ID, description text in any stored language, and created/updated date ranges (inclusive
local calendar days). Previous and Next navigate results. Loading fetches the complete
descriptor into memory and shows the page in a resizable canvas surface (initially
1000 × 650, centered and scaled to fit) using
the interpreter’s layout and element components. Transparent overlays select each element
for editing; repeated classes and all instance attributes are kept. A movable frame in the canvas opens page configuration and the page's layouter properties in
the Properties panel (today the Flow layouter's `layouter_config`, which the revised design
moves to each panel's element layouter). The frame starts aligned with the canvas settings button.
The page preview can be resized with its corner handle or keyboard; this changes the
editor surface rather than the descriptor’s dimensions. Each editor tab keeps up to 50 undo steps for canvas and descriptor edits, including node properties, dragging, deletion, pane changes, and preview resizing. Undo and Redo are available in the toolbar and with Cmd/Ctrl+Z and Cmd/Ctrl+Shift+Z (or Ctrl+Y). A new edit after Undo clears the redo history. The flow data includes
the loaded descriptor; the current flow backend is a stub and
does not persist it across reloads. Loading a page opens a separate editor tab, with its own history. View JSON
keeps the loaded page's metadata. Loading does not write a page version to the database;
the existing Save button still saves the canvas flow.

Authors find pages with `GET /api/v1/wpi/pages?q=<text>`, which matches the ID, name and
description in any language, and read one with `GET /api/v1/wpi/pages/<id>`. The copy is
saved with the admin write of [Storage](#storage) under its new ID. Opening a page loads the latest active
version of its descriptor ([Storage](#storage)). The search endpoint also accepts `descriptor_id`,
`description`, `limit` (default 50, maximum 200), `offset` (default 0), and inclusive
`created_from`/`updated_from` and exclusive `created_to`/`updated_to` RFC3339 timestamps.
It returns `pages` and `has_more`. Filters and pagination run in PostgreSQL after
choosing each ID's latest active version. The behavior contract is
[WPI pages](../../../../ChenWeb/openspec/specs/wpi-pages/spec.md).

<a id="panels"></a>

### 3.3 Panels

Panes and panels accept optional `background_color` and `foreground_color`; absent or null means no color is set. A value is a CSS color, or an object such as `{ "light": "#fff", "dark": "#111" }` that follows the current display mode. Fixed colors stay fixed. Each unset pane color inherits the closest ancestor pane's corresponding color, independently; an explicit child color overrides it. Foreground colors inherit into content unless overridden. If a leaf pane has an effective background color, including one inherited from an ancestor, its panel background is ignored; otherwise the panel background colors its content area. When a page opens in a pane, the host pane replaces its root pane and supplies that precedence. Specify readable foreground/background combinations for both modes.


A panel holds the elements shown in one pane of a page, and the element layouter that arranges
them. A panel implements part of its page, through its elements. It is not the page, except
when the page has only one pane. A page has one panel for each leaf pane it wants to fill; they
are in the page's `panels`, keyed by the `pane_id` of the pane. A leaf pane without a panel is
empty.

Panels have the following attributes:

| Attribute | Data Type | Default | Explanation | Validation |
|-----------|-----------|---------|-------------|------------|
| elem_layouter | object | none | the panel's copy of an element layouter class: the whole class in `class`, and this panel's own `config` beside it when it changes the parameters ([Element layouters](#element-layouters)); the editor starts a new panel with a copy of `flow-layouter` | `layouter` equals the copy's `descriptor_id`; the copy's `code_module_id` is an active module of type `element-layouter` (planned); every key of either `config` is a parameter of that module, with a valid value |
| background_color, foreground_color | color | none | panel background and foreground; the effective pane background takes precedence | CSS color or an object with `light` and `dark` CSS colors |
| elem_list | list | [] | the element instances of the panel, in order | a valid JSON array of element instances ([Elements in panels](#elements-in-panels)) |

```json
"panels": {
  "main": {
    "elem_layouter": { "layouter": "flow-layouter" },
    "elem_list": [ { "element": "text", "text": "Hello" } ]
  }
}
```

**A panel's geometry comes from its content.** A panel has no width or height attribute. The
element layouter places the elements and the panel is as large as the placed elements need;
only the content can change it. The one thing the pane contributes is the width that `elastic`
and percentage element sizes are measured against, the pane's width inside its left and right
margins: such elements make the panel as wide as that, never wider
([Element layouters](#element-layouters)). In a pane whose width is `"auto"` there is no pane
width to measure against, since the pane takes its width from the panel; there, `elastic` and
percentage element widths act as `"auto"`. If the panel is smaller than the space inside the
pane's margins, the pane's `hori_align` and `vert_align` decide where it sits; if the panel and
the margins do not fit, the pane's `hori_scrollbar` and `vert_scrollbar` decide whether it
scrolls or is clipped ([Panes](#panes)).

<a id="page-instances"></a>

#### 3.3.1 Page instances

A **page instance** is one open copy of a page: the page descriptor, its input doc and its
panels. The app's page area shows one page instance, the app's `initial_page`. A page opened in a
pane is a page instance too; it owns the input doc, dirty tracking, `save_action` and refresh of
that page. A page instance, its panes and its panels each have an instance ID of their own
([Descriptors and instances](#descriptors-and-instances)).

A page instance opened in a pane is shown, hidden and closed as a whole, with all its panes and
panels ([Panel Cache](#panel-cache)). For a single-pane page that is its one panel.

```text
WPI app "customer-admin"                       (URL holds the app ID)
├── App shell: header, footer
└── App page area
    └── Page instance → page "customer-admin-home"   (top-left-middle-right-bottom)
        ├── Pane "top"     ── Panel (a title)
        ├── Pane "left"    ── Panel (a menu tree)
        ├── Pane "middle"  ── shows one page at a time; the others are hidden in the Panel Cache
        │   ├── Page instance → page "customers"                     shown
        │   └── Page instance → page "customer-form" (new)           hidden, cached
        └── Pane "right"   ── shows one page at a time; the others are hidden in the Panel Cache
            ├── Page instance → page "customer-form" (customer 42)   shown
            └── Page instance → page "customer-form" (customer 7)    hidden, cached
```

<a id="opening-a-page"></a>

#### 3.3.2 Opening a page

Opening a page renders it in a page area ([The app shell and the page area](#app-shell)): the
page layouter creates the page's panes, and each pane's panel renders its elements, arranged by
its element layouter. A page always has panes; a page without them is an error
([Validation and errors](#validation-and-errors)).

**In the app's page area** (the app's `initial_page`; planned: a browser tab, a new tab or an
iframe), the page is rendered as [Pages](#pages) describes: its own attributes place it in the
page area, and its root pane is the page itself.

**In a pane of another page** (`open-page` with target `"pane"`, [Action classes](#action-classes)),
let A be the pane in which the page P is opened, and B P's root pane. A always takes the place
of B, and everything else stays the same: P is rendered as it would be in the app's page area,
a browser tab or an iframe, except that it has no URL.

- A keeps its geometry, which comes from the page that holds A, and its own attributes. A's
  margins, `hori_align`, `vert_align`, `hori_scrollbar` and `vert_scrollbar` apply to P, in
  place of both B's and P's own. B's attributes are not used.
- P's own size attributes (`width`, `height` and the limits) and colors still apply, measured
  inside A, just as they are measured inside a page area.
- For example, if A is `300px` wide, P's `width` is `500px`, A's `hori_scrollbar` is `auto` and
  B's is `hide`, P is wider than A and a scroll bar appears. If A's `hori_align` is `center` and
  B's is `left`, P is centred in A.
- If P is a single-pane page, B is its only pane, so P's one panel, the one keyed by B's
  `pane_id` in P's `panels`, is rendered in A. Otherwise B's children are created inside A,
  exactly as they would be inside B, and each gets its panel.
- An `open-page` inside P that names B's `pane_id` names A ([Action classes](#action-classes)).

Which page A shows, and whether P is rendered again or shown from memory, is decided by the
Panel Cache ([Panel Cache](#panel-cache)).

<a id="panel-cache"></a>

#### 3.3.3 Panel Cache

The **Panel Cache** is a module of the frontend. It keeps the pages that have been opened in
panes, so that a pane can show one again without rendering it again. (The name comes from
single-pane pages, where keeping the page is keeping its one panel.)

Two words are used strictly:

- **Hide.** The page instance stays loaded and in memory, with its panels and its input doc,
  unsaved changes included, and stays in the cache. It is only not visible. Hiding never asks
  the user anything.
- **Close.** The page instance and its panels are removed from memory and from the cache.
  Closing first runs the unsaved-changes check ([Input doc lifecycle](#input-doc-lifecycle)).

How the cache works:

- **A pane shows one thing at any given time**: its own panel, or a page instance opened in it.
- **An entry** of the cache is a pair `(page-instance-id, pane-instance-id)`: a page instance,
  and the pane in which it was opened. The cache finds a page by looking at the entries of the
  target pane and comparing the page and the resolved input of each.
- **Opening a page in a pane** (`open-page` with target `"pane"`, [Action classes](#action-classes)):
  1. If the pane is showing a page instance, hide it. A pane that switches to another page
     never closes the one it was showing.
  2. If the page, with the same resolved input, is in the Panel Cache for this pane, show it.
     Nothing is rendered or reloaded, which is very fast.
  3. Otherwise render the page in the pane ([Opening a page](#opening-a-page)) and add the
     entry `(page-instance-id, pane-instance-id)` to the cache.

**Menus.** The panel of the `left` pane of the home page ([A home page with a menu](#home-page-example))
holds a menu; each of its items opens a page in the `middle` pane. The first click on an item
renders the page; later clicks find it in the cache and show it again. Items that open the same
page with the same input in the same pane therefore share one page instance. The same holds for
every other `open-page`: clicking the same customer in a list a second time shows the page
already opened for that customer.

**A pane's own panel.** A pane that has a panel of its own, in its page's `panels`, shows it when
its page is rendered. That panel belongs to the pane's page, not to a page opened in the pane,
so it is not a cache entry. When a page is opened in the pane, the pane's own panel is hidden.
When the page instance the pane shows is closed, the pane shows its own panel again, if it has
one; otherwise the pane is empty.

**How long hidden pages are kept.** A hidden page instance stays in the cache until it is closed:

- **Manually.** The user closes it (`close-page`).
- **Age-out** (planned; not in the pilot). The app descriptor sets how long a page instance may
  stay hidden since it was last visible; older ones are closed. A page instance with unsaved
  changes is never aged out.
- **With the app.** Leaving the browser page closes every page instance, after the
  unsaved-changes check of every one, hidden ones included.

Until age-out is built, a pane keeps every page opened in it, so a pane in which many
different records are opened keeps all of them in memory. A page whose instance has been closed
is rendered afresh the next time it is opened.

**Refreshing a page.** Any page instance, shown or hidden, may refresh its content: its lists
re-run their queries and its input doc is reloaded from its `load` instance. The page descriptor
says when ([Page attributes](#page-attributes)):

- on a timer, every given number of seconds (planned; not in the pilot);
- with that timer stopped while the page instance is hidden (planned; not in the pilot);
- each time the page instance changes from hidden to shown.

A refresh never reloads an input doc that has unsaved changes; the user's edits win.

<a id="descriptors-and-instances"></a>

### 3.4 Descriptors and instances

A descriptor is a definition; an instance is one running copy of it.

| | Descriptor (definition) | Instance (running copy) |
| --- | --- | --- |
| App | app descriptor ID, e.g. `customer-admin` | app instance ID, generated each time the app is opened |
| Page | page descriptor ID, e.g. `customer-form` | page instance ID, generated when the page is opened |
| Page layouter | class ID, then the page's copy of it | page layouter instance ID, generated when the page is rendered |
| Pane | `pane_id` in the page layouter's tree | pane instance ID, generated when the page's panes are created |
| Panel | its key in the page's `panels` (a `pane_id`) | panel instance ID, generated when the panel is rendered |
| Element layouter | class ID, then the panel's copy of it | element layouter instance ID, generated with its panel |
| Element | element class ID, e.g. `input` | element instance ID, generated when its panel is drawn |
| Action | action class ID, e.g. `save` | an execution ID, generated for each run and used in logs |

The same page can have several page instances at once, as `customer-form` does in the diagram
above, where it has three page instances. Each page instance has its own input doc, so they never share data by accident.
Likewise, one element class can be placed on many pages, or several times on one page.
In principle, everything that can be addressed has a unique instance ID. Instance IDs are always
generated dynamically by the system and never written in descriptors. A descriptor uses design-time
names, such as class IDs and `pane_id`, and the interpreter resolves them to instance IDs at run
time: the `pane` of an `open-page` becomes the pane instance ID of the pane it resolves to
([Action classes](#action-classes)). The entries of the Panel Cache ([Panel Cache](#panel-cache)) are made of instance IDs.

An element's attributes are split into *class attributes*, which all its instances share,
and *instance attributes*, which each instance may set ([Element classes and instances](#element-classes-and-instances)). Actions are split the
same way ([Actions](#actions)); both are built (descriptor format `0.2`, 2026-10-27; element class rows
moved to format `0.3` the same day and to `0.4` on 2026-10-28, [Element classes and instances](#element-classes-and-instances)). Pages are not: a page
has no class, and pages are reused by copying ([Reuse by copying](#reuse-by-copying)).

**Classes are templates** (decided 2026-10-30). A class is read-only to the pages that use it:
nothing a page does changes it. Only an admin changes one, by storing a new version or, for an
element class, with *Edit class*. Using a class copies it whole, defaults included, and the copy
records which class it came from (`element`, `action` or `layouter`). From then on the copy has
no connection to its class: a change to the class, to any of its attributes, reaches only the
copies made afterwards, never the ones that already exist. This holds for every kind of class:

- **Element and action classes.** An instance copies its whole class into its `class` when it
  is placed, and then sets its own values for the instance attributes. It can use the class
  attributes in the copy but not change them ([Element classes and instances](#element-classes-and-instances), [Actions](#actions)).
- **Page layouters and element layouters.** A page or a panel copies the whole class into the
  copy's `class` and sets its own values beside it, which may change any value of the class
  ([Page layouters](#page-layouters), [Element layouters](#element-layouters)).

Before 2026-10-30, an element or action instance stored only the attributes it set and took
the rest from the stored class when its page was loaded, so a change to a class reached
existing pages.

<a id="elements"></a>

### 3.5 Elements

<a id="element-classes-and-instances"></a>

#### 3.5.1 Element classes and instances

An element is one visible part of a page. Elements come as classes and instances, much as
objects do in C++:

- An **element class** is a kind of element, such as `input`, `pulldown-menu`,
  `toggle-button` or `check-box`. Each class maps to frontend code that draws it, so all
  elements of a class behave exactly the same; only their values differ. A class is
  stored as an element descriptor whose `descriptor_id` is the class ID.

  **A class names its code.** Each class names the frontend code that draws it, its code
  module, in `code_module_id`, and several classes may share one code module ([Code modules](#code-modules)). The
  class ID identifies the descriptor, not the code. The validator reports a class whose code
  module is not an active element module in `kb.code_modules`, or, for an active class, has no
  code ([Validation and errors](#validation-and-errors)).
- An **element instance** is one use of a class on a page, with its own values: for
  example, an `input` labelled "Phone" and bound to `$input_doc.phone_number`. Instances
  live inside a panel of their page's descriptor ([Elements in panels](#elements-in-panels)) and are never stored by themselves. An
  instance's ID is generated by the system each time its panel is drawn, so it never
  appears in a descriptor.

Classes are few, normally no more than about 100, and stable: a class can be used only
once the code that implements it exists. It may be defined first, as a draft (below). Instances are many, thousands or more, and new
ones come with every new page. Keeping classes few is what makes pages easy to write. An
author picks from a short list of names that are easy to remember, instead of searching
an ever-growing set of one-off definitions that nobody can keep track of.

An element's attributes are of two kinds:

- **Class attributes** are copied into every instance, which can use them but not change
  them, like const member data in C++. Every class has the ones this document
  defines: `descriptor_id`, `schema_version`, `code_module_id` ([Code modules](#code-modules)), `description` and
  `implement_notes`. Whoever creates or edits a class may also make any other attribute a
  class attribute (2026-10-28), by setting
  `"instance_modifiable": false` in its object (below). Its `default_value` is then the
  value every new instance gets and may not be `null`, and an instance that sets the
  attribute fails validation ([Validation and errors](#validation-and-errors)). For example, `fancy-button` could fix a `style` attribute to
  `fancy` and `simple-button` fix it to `simple` (the `button` code module has no `style`
  attribute yet).
- **Instance attributes** belong to every instance, but each instance may give them its
  own value, like ordinary member data. The class row names them: the ones many classes
  share (table below) and the ones its code module draws with, such as a pulldown menu's
  `options`, a button's `on_click` or a list's `columns` ([Lists](#lists)). The code module's
  document lists what the module supports; an attribute it does not support may still be
  named, but has no effect ([Code modules](#code-modules)). An instance may set only the attributes its class
  names, plus the sizes (`width`, `height`, `min_width`, `max_width`), which every element
  has. In the class row each instance attribute is an object with three optional parts:
  `help_tip`, text that tells authors what the attribute is for; `default_value`, the
  default; and `instance_modifiable`, which `false` turns into a fixed class attribute
  (above). A `default_value` of `null` means every instance must set the attribute before the page can
  run. An incomplete page can still be saved and reopened for editing ([Validation and errors](#validation-and-errors)). An attribute without
  `default_value` is optional and has no default, such as a list's `on_row_click`. An
  instance that does not set an attribute uses the default in its class copy (below).

**An instance holds a copy of its class** (decided and built 2026-10-30,
[Descriptors and instances](#descriptors-and-instances)). When an element is placed in a panel,
the whole class row is copied into the instance's `class`: `descriptor_id`, `schema_version`,
`code_module_id`, `description`, `implement_notes`, the fixed class attributes and every
instance attribute with its help tip and default. Nothing is left out, so neither the
interpreter nor the editor ever reads the stored class again for that instance. `element`
names the class, and must equal the copy's `descriptor_id`; `class` cannot be used as an
attribute name. The instance's own attributes sit
beside `class` and hold only the instance attributes it sets ([Elements in panels](#elements-in-panels)):

- The interpreter draws the element with the copy's `code_module_id`, and fills in every
  instance attribute the instance does not set from the copy's `default_value`.
- The editor shows the copy's description, implement notes and help tips, and shows the class
  attributes read-only.
- The server checks the instance against its copy: it sets only instance attributes the copy
  names (and the sizes), none the copy fixes, and every one whose default in the copy is `null`
  ([Validation and errors](#validation-and-errors)).

From then on the instance has no connection to its class. A later change to the class, a class
attribute included, reaches only instances placed afterwards, and retiring the class does not
break the pages that use it. An attribute that a code module supports but the copy does not
name, because the module gained it after the copy was made, takes the default given in the
module's document. The copies make pages larger, since every instance carries its class's
help tips and notes. The interpreter never shows them, so the app bundle sent to the browser
can leave them out.

Attributes that hold actions (`on_click`, `on_row_click`, `source` and a menu's `items`)
never have defaults and cannot be made class attributes: their `default_value` is `null`
or left out. So every action instance is written in a page ([Actions](#actions)).

| Attribute | Kind | Meaning |
| --- | --- | --- |
| `descriptor_id` | class | The class ID, e.g. `input`. |
| `schema_version` | class | The format version of the class's descriptor ([Page descriptors](#page-descriptors)). |
| `code_module_id` | class | The code module that draws the class, e.g. `button` for `fancy-button` ([Code modules](#code-modules)). Required in an active class. |
| `description` | class | What the class is for, so that authors can choose among classes. |
| `implement_notes` | class | Optional. The prompt for implementing the class's code, which also helps authors understand the element. |
| `label` | instance | The text shown with the element, such as an input's caption or a button's text. |
| `data_binding` | instance | For elements that show data: the attribute of the input doc they show, e.g. `$input_doc.email` ([Input doc and data binding](#input-doc-and-data-binding)). |
| `binding_mode` | instance | For elements that show data: `read-only` or `read-write` ([Input doc and data binding](#input-doc-and-data-binding)). |
| `width`, `height` | instance | A length such as `"240px"`, `"elastic"` or `"auto"` ([Element layouters](#element-layouters)). |
| `min_width`, `max_width` | instance | The limits of an elastic width, as lengths ([Element layouters](#element-layouters)). |

`label`, `description`, `implement_notes` and an attribute's `help_tip` hold text for
people, in one of two forms:

- a plain string, `"label": "Email"`, shown the same in every language;
- one text per language, keyed by the language codes ChenWeb uses:
  `"label": { "en": "Email", "zh-cn": "电子邮箱" }`. When the user's language is missing,
  the interpreter shows the `en` text, so this form must include `en`.

For now, a binding reaches only the page instance's input doc, `$input_doc`. Bindings to other,
named docs may come later ([After the pilot](#after-the-pilot)).

The `input` class, shortened to three of its attributes. Every instance must set `label`
and `data_binding`; the other instance attributes have defaults:

```json
{
  "descriptor_id": "input",
  "schema_version": "0.4",
  "code_module_id": "input",
  "description": { "en": "A one-line field for typing text", "zh-cn": "单行文本输入框" },
  "label": {
    "help_tip": { "en": "The caption shown with the field.", "zh-cn": "字段旁显示的标题。" },
    "default_value": null
  },
  "data_binding": {
    "help_tip": { "en": "The input doc attribute the field shows and edits, such as $input_doc.email." },
    "default_value": null
  },
  "binding_mode": {
    "help_tip": { "en": "read-write lets the user edit the value; read-only only shows it." },
    "default_value": "read-write"
  }
}
```

Element class rows are written in descriptor format `0.4`; apps, pages and action classes
stay in `0.2`, where an action class row still gives each instance attribute its default
directly (`"mode": "upsert"`) or `null` ([Actions](#actions)). Each kind's `schema_version` is checked
against the format this interpreter supports for that kind.

**Creating an element class.** The WPI editor's *Create Nodes → Create Element* defines a
new class in three steps (decided 2026-10-27):

1. The author describes the class in a form that lists its attributes. The list starts
   with the class attributes `descriptor_id`, `schema_version`, `code_module_id`,
   `description` and `implement_notes`, which cannot be renamed; while `code_module_id` is
   edited, the form lists the active element modules of `kb.code_modules` ([Code modules](#code-modules)).
   `implement_notes`, the prompt for the implementation, is written in a multi-line
   editor. Each instance attribute is entered as a name, a default (empty for none) or
   *every instance must set it* (`null`), optionally *fixed by the class*
   (`"instance_modifiable": false`, which needs a default), and a help tip in English and
   optionally Chinese, and added to the list with *Add Attribute*. Double-clicking an
   attribute loads it into the fields to be modified.
2. *Create Element* stores the descriptor as version 1 of the class, with status `draft`.
   If a row with that class ID already exists, whatever its status, nothing is stored and
   the error is reported. Attributes the class's code module does not support are listed
   as warnings before the form closes.
3. An admin makes the class active by storing the class row again with the admin write
   ([Storage](#storage)), which checks the row against its code module and stores it as `active`. If the
   class names a module that already has code, such as `button`, nothing else is needed.
   If the module is new, a developer first writes its code ([Code modules](#code-modules)).

A draft is never run. The interpreter uses only active rows: instances are copied only from
active classes, and in the code today a page that names a draft class fails validation as if
the class did not exist. When a draft is created, the server
checks what it can check without code: the ID, a required description, the attribute
names, fixed attributes, that attributes holding actions have no default, the defaults of
attributes all classes share (sizes, `label`, `data_binding`, `binding_mode`), and that a
`code_module_id` it names is an active element module in `kb.code_modules`. An attribute
that is optional with no default is written without a `default_value` (format `0.4`). The
editor's palette lists every element class in its ELEMENTS folder, drafts marked as such.

**Editing an element class** (2026-10-27, updated 2026-10-28). An element node's *Edit
class* button, in the small tool bar above a selected node, opens the same form on the
class's latest draft or active row, with the class ID fixed. Saving updates that row in
place, keeping its version and status. Instances already placed in pages are copies and are
not changed. A draft is checked as one. An active class is
checked for structure, must name a code module that has code, and may name attributes its
module does not support, which are listed as warnings. Either way a `code_module_id` must
be an active element module in `kb.code_modules`. Making a draft active is still step 3.

**History.** The pilot (format `0.1`, 2026-10-26) had no stored element classes. Its kinds
of element were hard-coded and named in `element_type`, and its stored elements, such as
`customer-user-name`, were really instances stored by themselves. Format `0.2` replaced
them on 2026-10-27; the pilot's rows are retired. Element class rows moved to format `0.3`
the same day, when instance attributes became objects with a help tip and a default and
`implement_notes` was added; migration `20261027000006_wpi_element_classes_0_3.sql` stored
the six classes again in that format, with help tips. They moved to format `0.4` on
2026-10-28, when classes began to name their code module: migration
`20261028000001_wpi_element_classes_0_4.sql` stored the latest row of every class again in
that format, keeping attributes authors had added, with `code_module_id` equal to the class
ID for active classes.

<a id="elements-in-panels"></a>

**Class editor metadata.** The WPI Editor's Class tab edits stored element, action
and layouter definitions. Its optional `attribute_definitions` object maps logical
JSON pointers to descriptions, Class/Instance scope and `{id, options}` value-editor
settings. For example, `/source/table` describes the `table` field inside an element's
source default; the `default_value` wrapper is not part of that path. This metadata
is retained when a class is copied but is excluded from runtime defaults and instance
attributes. Top-level element Class scope uses `instance_modifiable: false` with a
non-null default; nested and non-element scope is authoring classification only.
Existing descriptors need no metadata or migration. Class changes reach new copies;
existing copies retain their defaults and editor configuration. Panes and panels
have no new class kinds: the tab edits their associated layouter class. See
[WPI Editor §1.3.7](2026102701-devdoc-wpi-editor.md#137-editing-a-class) and the
[Class editor contract](../../../../../ChenWeb/openspec/changes/wpi-class-editor/specs/wpi-class-editor/spec.md).

#### 3.5.2 Elements in panels

A page is defined by a page descriptor ([Page descriptors](#page-descriptors)). Its elements live in its panels:
a panel lists its element instances, in order, in `elem_list`. Each instance holds a copy of
its class in `class` ([Element classes and instances](#element-classes-and-instances)), names
the class in `element`, and sets the instance attributes it needs; the rest come from the
defaults in its copy. One instance in full, with the copy of the `input` class shortened to
three attributes as in [Element classes and instances](#element-classes-and-instances):

```json
{
  "element": "input",
  "class": {
    "descriptor_id": "input",
    "schema_version": "0.4",
    "code_module_id": "input",
    "description": { "en": "A one-line field for typing text", "zh-cn": "单行文本输入框" },
    "label": {
      "help_tip": { "en": "The caption shown with the field.", "zh-cn": "字段旁显示的标题。" },
      "default_value": null
    },
    "data_binding": {
      "help_tip": { "en": "The input doc attribute the field shows and edits, such as $input_doc.email." },
      "default_value": null
    },
    "binding_mode": {
      "help_tip": { "en": "read-write lets the user edit the value; read-only only shows it." },
      "default_value": "read-write"
    }
  },
  "label": "Email",
  "data_binding": "$input_doc.email",
  "binding_mode": "read-only"
}
```

The instance sets `label` and `data_binding`, whose defaults in the copy are `null`, and sets
`binding_mode` to `read-only`, so it shows the email without letting the user edit it. It takes
`code_module_id` from the copy. The pilot's customer form fields become three such instances,
in the panel of a single-pane page. Here and in the other examples of this document, each
instance's `class` is left out:

```json
"panels": {
  "main": {
    "elem_layouter": { "layouter": "flow-layouter" },
    "elem_list": [
      { "element": "input", "label": "User name", "data_binding": "$input_doc.user_name" },
      { "element": "input", "label": { "en": "Phone", "zh-cn": "电话" }, "data_binding": "$input_doc.phone_number" },
      { "element": "input", "label": "Email", "data_binding": "$input_doc.email", "binding_mode": "read-only" }
    ]
  }
}
```

An instance cannot change class attributes. A page cannot define a class inline either: a
class needs frontend code, so it is added together with that code.

Instances live only inside their page and have no rows of their own ([Storage](#storage)). A field that
appears on two pages is written in both.

A **menu** element is a tree of items. An item either opens a page (through its `on_click`
action) or is a folder of further items. A menu is an element like any other: an instance in a
panel's `elem_list`. Its items open pages; clicking an item again shows the page's panel from
the Panel Cache ([Panel Cache](#panel-cache)). A menu may name an `initial_item`, the item it
opens when the page holding the menu is opened. For example:

```json
{ "element": "menu",
  "initial_item": "customers",
  "items": [
    { "item_id": "customers", "label": "Customers",
      "on_click": { "action": "open-page", "page": "customers", "pane": "middle" } },
    { "item_id": "new-customer", "label": "New customer",
      "on_click": { "action": "open-page", "page": "customer-form", "pane": "middle", "input": {} } }
  ] }
```

The [Ant Design component overview](https://ant.design/components/overview) is a good
catalogue of element classes worth adding over time. It is a reference for *which*
classes to offer, not an implementation: WPI element classes are built with ChenWeb's own
Svelte components.

**Default Page**

A single element can be treated as a page by associating a default page to it.

<a id="elements-and-page-styles"></a>

#### 3.5.3 Elements and Page Styles
Page styles define the default look and feel of a page and its elements. A project can 
use one Page Style across its pages so that buttons, fields, text, lists and other elements 
look consistent without repeating appearance attributes on every instance.

**Page styles are a later phase.** The page's `page_style` attribute is accepted and ignored.
Element-local appearance controls do exist for implemented modules, including input and
[text R2](../../code_modules/interpreter-text.md); they do not implement Page Styles.

<a id="code-modules"></a>

#### 3.5.4 Element implementation

An element class names the frontend code that draws it, its *code module*, in the class
attribute `code_module_id` (built 2026-10-28, OpenSpec change `wpi-code-modules`). The
class ID identifies the descriptor; `code_module_id` identifies the code. Each class stored
so far is drawn by the module of the same name: the class `input` by the module `input`.

They are kept apart because one piece of code can draw many classes. Buttons, for example,
can look and behave in many ways. A single `button` class covering every variant would need
a large, complicated descriptor. Instead there can be several small classes, such as
`simple-button`, `fancy-button` and `animated-button`, all drawn by the `button` code
module, each with its own description, help tips, defaults and fixed attributes ([Element classes and instances](#element-classes-and-instances)).

**The table `kb.code_modules` lists the code modules**, one row each:

| Column | Meaning |
| --- | --- |
| `code_module_id` | The module's ID, e.g. `button`. Unique and not null. |
| `module_name` | Its name for people, e.g. "Button". Unique and not null. |
| `description` | What the module does. |
| `module_type` | What it implements: `element`, `action`, `page`, `page-layouter` or `element-layouter`. Two layouter types, not one, so that a panel cannot name the code of a page layouter, nor a page the code of an element layouter. |
| `module_doc` | The file name of its document in `KnowledgeStore/doc-repo/code_modules`, e.g. `button.md`. |
| `notes` | Additional notes. |
| `status` | `active` or `suspended`. |

Rows come from migrations or `psql`; there is no write API, as for `kb.stored_stmts`.
Migration `20261028000002_create_kb_code_modules.sql` created the table with the six element
modules. Migration `20261030000005_wpi_chat_elements.sql` added the element modules
`chat-composer` and `chat-panel` and their active classes (2026-10-30, ChenWeb OpenSpec change
`wpi-chat-elements`): a message box and a Chat/Dialog panel that share the chat of their page
instance, converted from ChenWeb's Chat page ([Chat Composer](../../code_modules/interpreter-chat-composer.md),
[Chat Panel](../../code_modules/interpreter-chat-panel.md)). Migration
`20261102000003_wpi_value_editor_elements.sql` added the element module `value-editor` and 28
classes that all use it, one per value editor of the WPI Editor (2026-11-02, ChenWeb OpenSpec
change `wpi-value-editor-elements`; [Value Editor](../../code_modules/interpreter-value-editor.md)).
Each class fixes the editor it draws, and the five editors without code are drafts. Besides them only the `flow-layouter` element layouter has a row (migration
`20261028000003_register_flow_layouter.sql`): action classes still name their code by
their class ID ([Actions](#actions)), and the code of page layouters is not registered yet. The editor reads the table through
`GET /api/v1/wpi/code-modules`.

**Each code module has a document**, the file `module_doc` names in
`KnowledgeStore/doc-repo/code_modules/`. It says what the module draws, lists every
attribute its code supports and says what the code does with each. Authors read it to
choose a module; a developer, or a coding assistant such as Claude Code, implements the
module from it.

- A `code_module_id` must name an active element module in `kb.code_modules`. The server
  checks this whenever a class is written and whenever an app is loaded.
- A draft may leave `code_module_id` out, and may name a module whose code is not written
  yet: a new module starts with its row and its document. An active class must name a
  module whose code exists in this interpreter, both in the frontend registry and, with the
  attributes it supports, in the backend validator ([Implementation notes for the pilot](#pilot-implementation-notes)).
- A `suspended` module can no longer be named, and an app with an instance drawn by it does
  not load until the module is active again.
- `code_module_id` can be changed when a class is edited. The change reaches only instances
  placed afterwards; existing instances keep the module they copied.
- Like every class attribute, `code_module_id` is in each instance's class copy, and the
  instance cannot change it.
- Action classes have no `code_module_id`: an action class ID still names the code that
  performs it ([Actions](#actions)).

**New attributes.** Whoever creates or edits a class may give it attributes its code module
does not support yet. When an attribute needs new code, the module is changed by hand, in
two steps: the attribute is added to the module's document, and a coding assistant such as
Claude Code reviews the code and changes it to match. Until both are done the attribute is
stored but has no effect. The class writes and the app bundle report it as a warning
instead of refusing the class row, so the gap is visible without blocking the author
(principle 5). The editor shows these warnings when a class is saved.

**Adding a code module.** A new module gets its row in `kb.code_modules` (through a
migration) and its document first; drafts can name it from then on. A developer then writes
its code: a component registered under the module ID in `codeModules`
(`web/src/lib/wpi/elements/index.ts`), and the attributes it supports, with the checks of
their values, under the same ID in `codeModules` (`server/api/wpi/validate.go`). Only then
can a class that names it become active.

The pilot's `element_type` (History, above) also named code, but it was set in each stored
element, which was really an instance. `code_module_id` is set once, in the class.

<a id="lists"></a>

### 3.6 Lists

A **list** element shows a set of records, one record per row. Repetition is driven by the
data, not by repeating elements in the descriptor. A list instance says which records to
show and how to show *one* record; the list draws as many rows as there are records. The
customer list, without its `on_row_click`, which is the `open-page` instance shown in [Action classes](#action-classes):

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

- `source` is the `load` instance ([Action classes](#action-classes)) the list runs to query its own records when it is
  first drawn, and again whenever its page refreshes ([Panel Cache](#panel-cache)). Most lists query their data
  themselves, and in the first iteration every list does. Passing records in from outside
  (for example through the input doc) may come later.
- Lists are read-only in the pilot.
- `presentation` chooses how records look. The pilot has `rows` (a table-like list);
  `cards` and other presentations come later.
- `columns[].field` is relative to one record. Inside a list, `$record` means the record
  of the row the user acted on.

<a id="element-layouters"></a>

### 3.7 Element layouters

An element layouter arranges the elements of a panel automatically, each layouter in its own
way. WPI has several element layouters and each panel holds a copy of the one it uses, in its
`elem_layouter` ([Panels](#panels)).

Element layouters are defined by descriptors, stored in `kb.wpi_descriptors`, with `kind` 
= 'element-layouter'.

The parameters of a layouter are tunable, and they can differ from panel to panel. 

Element layouters are classes, to be stored in `kb.wpi_descriptors` with `kind`
`element-layouter` ([Storage](#storage)), and they are used as page layouters are
([Page layouters](#page-layouters)). A class is a read-only template. An element layouter class
has `descriptor_id`, `schema_version`, `description`, `code_module_id` (an active module of type
`element-layouter`, [Code modules](#code-modules)) and `config`, every parameter with
its default value. A panel copies the whole class row into the `class` of its
`elem_layouter`, every parameter with its default value included. A panel that changes the
parameters sets its own `config` beside `class`, which replaces the copy's `config` whole, so it
lists every parameter. From then on the copy has no connection to its class, so modifying the
class does not change the panels that copied it. 

A panel with wider gaps and centred rows:

```json
"elem_layouter": {
  "layouter": "flow-layouter",
  "class": {
    "descriptor_id": "flow-layouter",
    "schema_version": "0.5",
    "description": { "en": "Places elements left to right and wraps to the next row", "zh-cn": "从左到右排列元素，放不下时换行" },
    "code_module_id": "flow-layouter",
    "config": {
      "column_gap": "0.75rem",
      "row_gap": "0.75rem",
      "horizontal_alignment": "start",
      "vertical_alignment": "top",
      "rows_alignment": "top"
    }
  },
  "config": {
    "column_gap": "1.5rem",
    "row_gap": "1rem",
    "horizontal_alignment": "center",
    "vertical_alignment": "top",
    "rows_alignment": "top"
  }
}
```

`layouter` names the class and must equal the copy's `descriptor_id`. The copy's `config`
holds `flow-layouter`'s defaults; a panel that keeps them sets no `config` of its own. Other
examples in this document leave `class` out. A parameter that a code module gains after a
panel copied its class is missing from that copy; it then takes the default given in the
module's document, so existing copies stay valid.

`rows_alignment` places the rows in a definite height. A panel has no height of its own; its
height comes from its content ([Panels](#panels)). So in a panel `rows_alignment` has no
effect, and the pane's `vert_align` places the panel as a whole instead.

The built-in element layouter is registered as an active `layouter` in `kb.code_modules` under
`flow-layouter`. See [Flow Layouter](../../code_modules/interpreter-layouter-flow.md)
for configuration and examples; the
[page-rendering specification](../../../../ChenWeb/openspec/specs/wpi-page-rendering/spec.md)
is the behavioral contract.

Size attributes (`width`, `height`) take one of three kinds of value:

- **A fixed length** such as `"240px"`. The element layouter uses it as given.
- **`"elastic"`**. The element layouter computes the size from the space available: the
  width of the panel's pane inside its margins, the width already taken by fixed-size elements, the other
  elastic elements sharing the row, and each element's `min_width` and `max_width`. Elastic
  sizes are recomputed when the pane is resized. In a pane whose width is `"auto"`, `elastic`
  acts as `"auto"` ([Panels](#panels)).
- **`"auto"`**. The element layouter decides, usually from the element's content or its own
  default.

More generally, any attribute set to `"auto"` or left out is decided by the system: size
and position by the element layouter, appearance (font, color) by the theme. The pilot has no
appearance attributes at all, so every WPI page follows the theme, including dark mode.
Style presets (named sets of appearance attributes) come later ([After the pilot](#after-the-pilot)).

<a id="input-doc-and-data-binding"></a>

#### 3.7.1 Element layouter class attributes
| Attribute | Kind | Meaning |
| --- | --- | --- |
| `descriptor_id` | class | The class ID, `flow-layouter`. |
| `schema_version` | class | The format version of the class's descriptor ([Page descriptors](#page-descriptors)). |
| `description` | class | Description of the layouter. |
| `` | instance |  |

For more information, refer to 'KnowledgeStore/doc-repo/code_modules/interpreter-layouter-flow.md'.

<a id="flow-layouter"></a>

### 3.8 Input doc and data binding

Each page instance has an **input doc**: a JSON document holding the data the page shows and
edits. Pages are static or dynamic, much like HTML pages. A dynamic page contains no data:
it only assumes data of a certain shape and is given its input doc when it is opened, so
the same page can show any data of that shape — any customer, for example. A static page
carries its data in its own descriptor, as its `input` ([Page input](#page-input)), like a page of help text.
That data is only a default: `open-page` can open the page with other data.

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
first written. The `save` action then says how that shape maps to table columns ([Actions](#actions)).

<a id="input-doc-lifecycle"></a>

### 3.9 Input doc lifecycle

1. **Load.** A requester — an action, an API or application code — retrieves data from the
   database and converts it into a JSON input doc. For a new record, the doc is `{}`; for
   a static page, it is the page's own data.
2. **Open.** A page instance is created from a page descriptor and the input doc. The
   interpreter keeps a copy of the doc as it was opened.
3. **Edit.** `read-write` elements change the doc as the user works.
4. **Save.** A save button runs the page's save action, which sends the doc to the backend.
   On success, the saved doc becomes the new unchanged copy.
5. **Close.** Before a page instance is closed — by the user or by age-out
   ([Panel Cache](#panel-cache)) — the interpreter checks whether the doc is *dirty*, i.e. differs from the last
   loaded or saved copy. If it is, the user is asked to save, discard, or keep editing.

Dirty means the content differs, so changing a field and changing it back is not dirty.

Hiding a page instance is not closing it, so hiding never asks. Leaving the browser page
checks every page instance, hidden ones included.

A page descriptor may name a default `input` ([Page input](#page-input)). It is used when the page is opened without being given an input doc, for example from a menu. A page
descriptor also holds its `save_action`, a `save` instance. The close prompt runs it, and
so does the page's save button through `save-page` ([Action classes](#action-classes)), so both save the same way.

<a id="descriptors-by-example"></a>

## 4. Descriptors by example

The examples together make up the `customer-admin` app. They show the descriptor shapes of
format `0.5`: an app descriptor that names a first page, and page descriptors with a page
layouter and panels. The demo app in ChenWeb has these shapes since migration
`20261030000001_wpi_pages_own_panes.sql`, which converted its pages and added its home page
`customer-admin-home`. (In that demo every page has a name and description, the header shows
its title from static data, *Directory* lists customers through `query` and opens one through
another, with a parameter, and *About* reads a stored file, read-only page-wide and centred.)
The shorter examples in [Concepts](#concepts) and [Actions](#actions) leave out
`schema_version`, which every stored descriptor needs, and every example leaves out the `class`
copy that each element instance, action instance and layouter copy holds
([Elements in panels](#elements-in-panels), [Page layouters](#page-layouters)); a page written
without them gets them from the server. Attributes that are planned but not yet supported are
named in the text, not in the JSON, because the validator rejects attributes it does not know.

<a id="app-descriptor"></a>

### 4.1 App descriptor

```json
{
  "descriptor_id": "customer-admin",
  "schema_version": "0.5",
  "initial_page": "customer-admin-home"
}
```

- The app does not deal with page details. It does not name panes, sizes or layouters; those
  belong to each page ([Pages](#pages)).
- `initial_page` is the page the app opens when it starts, here the home page of
  [A home page with a menu](#home-page-example). The app's page area is empty until then.
- A menu is not an app attribute. It is an element in a panel of a page, like every other
  element ([Elements in panels](#elements-in-panels)).
- Planned: the age-out policy for hidden pages ([Panel Cache](#panel-cache)) will be an app
  attribute such as `"page_retention": {"max_hidden_minutes": 30}`.

<a id="page-descriptors"></a>

### 4.2 Page descriptors

Pages are defined by page descriptors, which are JSON documents. This one has a single pane,
`main`, and one panel, which holds a title and a list. The attributes of the page itself
([Page attributes](#page-attributes)) come first, then the page layouter with the pane's attributes
([Panes](#panes)), then the panel ([Panels](#panels)):

```json
{
  "descriptor_id": "customers",
  "schema_version": "0.5",
  "page_name": { "en": "Customers", "zh-cn": "客户" },
  "description": "Lists demo customers with their phone numbers and email addresses",
  "max_width": "960px",
  "hori_align": "center",
  "refresh": { "on_show": true },
  "page_layouter": {
    "layouter": "single-pane",
    "root": { "pane_id": "main", "hori_align": "left", "vert_scrollbar": "auto" }
  },
  "panels": {
    "main": {
      "elem_layouter": { "layouter": "flow-layouter" },
      "elem_list": [
        { "element": "text", "text": "Demo - Customers", "width": "100%" },
        {
          "element": "list",
          "width": "100%",
          "source": {
            "action": "load",
            "table": "kb.wpi_demo_customers",
            "result": "list",
            "fields": [
              { "column": "user_name", "attribute": "user_name" },
              { "column": "phone_number", "attribute": "phone_number" },
              { "column": "email", "attribute": "email" }
            ]
          },
          "presentation": "rows",
          "columns": [
            { "field": "user_name", "label": "User name", "width": "elastic" },
            { "field": "phone_number", "label": "Phone number", "width": "160px" },
            { "field": "email", "label": "Email", "width": "elastic" }
          ]
        }
      ]
    }
  }
}
```

- `max_width` and `hori_align` belong to the page: in a wide page area the page stays 960 px
  wide and sits in the middle.
- `hori_align` and `vert_scrollbar` inside `root` belong to the pane `main`: the panel sits at
  the left of the pane and the pane scrolls it vertically when it is too tall.
- When `customers` is opened in a pane of another page, as in
  [A home page with a menu](#home-page-example), that pane takes the place of `main`. `max_width`
  still applies, but that pane's margins, `hori_align` and scroll bars are used instead of the
  page's and `main`'s ([Opening a page](#opening-a-page)).
- The panel has no size. It is as large as the title and the list need, and the element
  layouter measures `100%` and `elastic` against the width of the pane.

Every descriptor carries `schema_version`, so an interpreter can reject a descriptor
written for a format it does not understand rather than misread it.

<a id="home-page-example"></a>

### 4.3 A home page with a menu

This is the shape of the ChenWeb front end: a home page that divides its space with the
`top-left-middle-right-bottom` page layouter (here without `bottom`), a menu tree in
the `left` pane, a `middle` pane in which the menu items open their pages, and a `right` pane
in which a clicked customer opens. The page `customers` of [Page descriptors](#page-descriptors)
has one pane, so opening it in `middle` renders its list directly in that pane.

```json
{
  "descriptor_id": "customer-admin-home",
  "schema_version": "0.5",
  "page_name": { "en": "Customer admin", "zh-cn": "客户管理" },
  "page_layouter": {
    "layouter": "top-left-middle-right-bottom",
    "root": {
      "pane_id": "page",
      "split": "rows",
      "children": [
        { "pane_id": "top", "height": "48px" },
        { "pane_id": "middle-row", "height": "elastic", "split": "columns", "children": [
          { "pane_id": "left", "width": "240px", "min_width": "160px", "resizable": true },
          { "pane_id": "middle", "width": "elastic" },
          { "pane_id": "right", "width": "elastic", "min_width": "400px" }
        ] }
      ]
    }
  },
  "panels": {
    "top": {
      "elem_layouter": { "layouter": "flow-layouter" },
      "elem_list": [ { "element": "text", "text": "Customer admin", "width": "100%" } ]
    },
    "left": {
      "elem_layouter": { "layouter": "flow-layouter" },
      "elem_list": [
        { "element": "menu",
          "initial_item": "customers",
          "items": [
            { "item_id": "customers", "label": "Customers",
              "on_click": { "action": "open-page", "page": "customers", "pane": "middle" } },
            { "item_id": "new-customer", "label": "New customer",
              "on_click": { "action": "open-page", "page": "customer-form", "pane": "middle", "input": {} } }
          ] }
      ]
    }
  }
}
```

The `middle` and `right` panes have no panels of their own. When the page opens, the menu opens
its `initial_item`, *Customers*, in `middle`. `right` stays empty until a customer is opened in
it. The `on_row_click` of [Action classes](#action-classes), added to the customer list, does
that: it names the pane `right`, which `customers` does not have, so it resolves to this page's
pane.

<a id="actions"></a>

## 5. Actions

An action is an operation the interpreter performs. Actions come as classes and instances,
exactly as elements do ([Element classes and instances](#element-classes-and-instances)):

- An **action class** is a kind of action, such as `load`, `save` or `open-page`. Its
  class ID is the name of the code that performs it (element classes name theirs in
  `code_module_id` instead, [Code modules](#code-modules)): in the backend for `load`, `save`,
  `query` and `load-file`, in the frontend for `open-page`, `close-page` and `save-page`. Like element classes,
  action classes are few and stable, and a class is added only together with its code (only
  element classes can be drafted first, [Element classes and instances](#element-classes-and-instances)).
- An **action instance** is one use of a class, with its own values. It is written where
  it is used: in an element's trigger, in a list's `source`, in a page's `save_action`, or
  inside another instance, as with `open-page`'s `input`. Instances are never stored by
  themselves. Each run of an instance gets an execution ID ([Descriptors and instances](#descriptors-and-instances)).

Action classes have the class attributes `descriptor_id`, `schema_version` and
`description`, but no `code_module_id`, since an action class ID names its own code. Every action instance may set `args` (below); its
class's code defines the other instance attributes, and the class row gives each a default
or `null` ([Element classes and instances](#element-classes-and-instances)). Like an element
instance, an action instance holds a whole copy of its class in `class`, takes every attribute
it does not set from the defaults there, and is checked against that copy; a later change to
the class reaches only instances written afterwards. The examples leave `class` out. An
instance names its class in `action`:

```json
{ "on_click": { "action": "open-page", "page": "customer-form", "pane": "middle", "input": {} } }
```

Elements trigger actions through events. The pilot has three: a button's `on_click`, a
menu item's `on_click` and a list's `on_row_click`. A trigger may pass arguments in
`args`; inside the instance, and inside instances nested in it, `$args.<name>` refers to
them. A nested `load` that has `args` of its own receives those instead, resolved with
`$args` meaning the outer instance's arguments. The `open-page` example in [Action classes](#action-classes) passes the
ID of the clicked customer this way. References are plain substitutions — `$input_doc.<path>`, `$record.<field>`,
`$args.<name>` — with no calculations, comparisons or conditions.

**History.** The pilot (format `0.1`) had no stored action classes: each action named a
hard-coded kind in `action_type`, its stored actions such as `save-customer` were single
uses stored by themselves, and triggers referred to them by ID. Format `0.2` replaced
them on 2026-10-27.

<a id="action-classes"></a>

### 5.1 Action classes

| Class | What it does |
| --- | --- |
| `load` | Reads one record, or a list of records, from a table and returns them as JSON. |
| `save` | Sends the page instance's input doc to the backend, which validates it and writes it to a table. |
| `query` | Runs an SQL statement stored in `kb.stored_stmts`, named by its `sql_stmt_id`, read-only ([Page input](#page-input)). |
| `load-file` | Returns a JSON file stored in `kb.stored_files`, named by its `file_id` ([Page input](#page-input)). |
| `open-page` | Renders a page ([Opening a page](#opening-a-page)), by default in a pane of the page that holds the element that triggered it or of a page around it; planned: in the current browser tab, in a new tab or in an iframe (these need a URL). The page gets an input doc, either empty or produced by a `load` instance. |
| `close-page` | Closes the page instance that triggered it, after the unsaved-changes check. |
| `save-page` | Runs the `save_action` of the page instance that triggered it ([Input doc lifecycle](#input-doc-lifecycle)). |

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
  example leaves both out and takes them from its class copy. After an insert the backend returns the new key, which is written into the
  input doc, so saving again updates the same row instead of inserting a duplicate.
- Validation always runs on the server. The browser may check the same rules first for
  quicker feedback, but the server's check is the one that counts. Errors come back per
  attribute and are shown next to the element bound to that attribute; the binding tells
  the interpreter which element that is.
- When two users save the same record, the last save wins. This is deliberately the
  simplest rule for the first iteration; detecting conflicting edits is a hard problem
  left for later.

**`load` and `open-page`**, as the `on_row_click` of the customer list ([Lists](#lists)). It opens
the clicked customer in the `right` pane, and its `input` is a `load` instance that reads
that customer. The list is on the page `customers`, which is opened in the `middle` pane of
`customer-admin-home` ([A home page with a menu](#home-page-example)); `customers` has no pane
`right`, so `right` is the home page's pane (below):

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
runs as its `source` ([Lists](#lists)). `where` supports equality only in the pilot.

In `open-page`:

- `input` takes the same forms as a page's `input` ([Page input](#page-input)): `{}` for a new, empty doc,
  static data, or a `load`, `query` or `load-file` instance that produces the doc. Without
  it, the page's default `input` is used.
- `target` says where the page is rendered: `"pane"` (default), or, planned and not in the
  pilot, `"tab"` (the current browser tab), `"new-tab"` or `"iframe"`. The last three need a URL for the
  page; a page that has none is an error ([Loading a page by URL](#loading-by-url)).
- `pane` is required when `target` is `"pane"`. It is the `pane_id` of a leaf pane, looked up
  outward from the page that holds the element that triggered the action:
  1. First that page's own leaf panes. If the page was itself opened in a pane of another page,
     that pane has taken the place of its root pane, and the root pane's `pane_id` names it
     ([Opening a page](#opening-a-page)).
  2. Then the leaf panes of the page in whose pane that page was opened, then those of that
     page's own host, and so on up to the page in the app's page area.

  The nearest page with a leaf pane of that ID wins. A `pane` that resolves to no pane is an
  error.
- In a pane, the pane hides what it is showing and shows the opened page, from the Panel Cache
  if it is there ([Panel Cache](#panel-cache)).
- How the page is rendered, in the app's page area or in a pane, is described in
  [Opening a page](#opening-a-page). A page with any number of panes can be opened in a pane.
- The pilot's `pane` named a pane of the app's layout template. It now names a pane of a page,
  found as above, and the app itself has no panes.

<a id="which-tables-actions-may-touch"></a>

### 5.2 Which tables actions may touch

`load` and `save` may read and write tables in the project database using `table` values
such as `kb.metrics`. The editor also offers databases listed in `[wpi].databases_to_show`
in `config.local.toml`, then their schemas and tables. It stores a selection as
`database.schema.table`; the backend resolves it to that configured database's connection.
An unlisted database is rejected. Existing unqualified references continue to use the
project database. Within an allowed database there is no table allowlist; the backend:

- runs only action instances written in stored pages ([Storage](#storage)). The browser
  names the instance by its place, the page's ID and the instance's JSON Pointer inside
  the page, and supplies the arguments. It never sends a table name, a column name or a
  descriptor body. An administrator editing a page can also preview its current list-load
  source through a separate read-only endpoint, without saving the page. A table-backed
  list defaults to the `load` action and `list` result when those values are unset. The
  endpoint validates the source, permits only list loads and applies the same database checks;
- checks that the named table and columns exist, using the database catalog, and quotes
  them;
- passes values only as query parameters, never by building SQL text;
- requires a logged-in user;
- logs every action execution.

`query` runs only statements stored in `kb.stored_stmts`, read-only, and both `query` and
`load-file` refuse users whose roles the row's `access_controls` do not list ([Page input](#page-input)).

Database access goes through an adapter, so the database can be switched later. The pilot
supports PostgreSQL only.

<a id="storage"></a>

## 6. Storage

Descriptors are stored in the `kb` schema of the `miner` database, versioned, following
the workspace rule that data belongs in the database. The table is created by migration
`ChenWeb/project_migrations/20261026000001_create_kb_wpi_descriptors.sql`:

```text
kb.wpi_descriptors
  id              BIGSERIAL primary key
  kind            'app' | 'element' | 'action' | 'page-layouter' | 'element-layouter'
  descriptor_id   e.g. 'customer-form'
  version         integer, increasing per descriptor
  schema_version  descriptor format version
  body            JSONB, the descriptor itself
  status          'draft' | 'active' | 'retired'
  created_by, updated_by, created_at, updated_at
  unique (kind, descriptor_id, version)
```

- `element` and `action` rows are classes, a small and stable set ([Element classes and instances](#element-classes-and-instances), [Actions](#actions)). So are
  `page-layouter` and `element-layouter` rows ([Page layouters](#page-layouters), [Element layouters](#element-layouters)): `single-pane`,
  `top-left-middle-right-bottom` and `flow-layouter`, added by migration `20261030000001_wpi_pages_own_panes.sql`. A page copies a page layouter
  into its `page_layouter`, and a panel copies an element layouter into its `elem_layouter`. Element
  and action instances live inside their page's descriptor and have no rows of their own,
  so loading a page never has to pick out its instances: the page row holds them all. Each
  instance holds a whole copy of its class, so loading a page needs no class rows; the editor
  reads classes only when an author places a new element or action. The pilot's stored
  elements and actions (format `0.1`), such as `customer-email` and `save-customer`, were
  retired on 2026-10-27.
- The interpreter uses the latest `active` version of each descriptor.
- Versions are never edited in place. An admin writes a new version with
  `PUT /api/v1/wpi/descriptors/<kind>/<descriptor-id>`, which checks it first and stores it
  as `active`. Apart from *Create Element* (below), there is no editor screen yet.
- **Element class drafts** ([Element classes and instances](#element-classes-and-instances)) are `draft` rows written by
  `POST /api/v1/wpi/classes/element` (admins only). It needs no code but refuses a class ID
  that has any row, with 409. `GET /api/v1/wpi/classes/element` lists the latest draft or
  active version of every element class, with its instance attributes, for the editor's
  palette and Properties panel. `GET /api/v1/wpi/classes/element/<class-id>` returns one
  class's latest draft or active row whole, and `PUT` on that path (admins only) updates
  that row in place, keeping its version and status ([Element classes and instances](#element-classes-and-instances)); this is the one exception to
  "versions are never edited in place". All three class writes (the admin write of an
  element class, the draft create and the class edit) return `warnings` for attributes the
  class's code module does not support, and refuse a `code_module_id` that is not an
  active element module in `kb.code_modules`.
- **Code modules** are listed in `kb.code_modules` ([Code modules](#code-modules)), created by migration
  `20261028000002_create_kb_code_modules.sql`, and read by the editor through
  `GET /api/v1/wpi/code-modules`.
- A WPI app reachable from ChenWeb's own menus also registers a `page_key` in
  `kb.page_def`. That table's comment currently says page structure stays in the
  frontend; it should be updated when WPI apps start registering there.
- Copying descriptors from staging to production needs an export/import path. Not in the
  pilot.
- **Pages have their own table, `kb.frontend_pages`** ([Pages](#pages)), with the same columns as
  `kb.wpi_descriptors` except `kind`. Migration `20261027000003_create_kb_frontend_pages.sql`
  moved every page version there, and `kb.wpi_descriptors` no longer accepts pages. The
  admin write above still takes `page` as its kind and writes to the new table.
- Stored SQL statements and files are in `kb.stored_stmts` and `kb.stored_files` ([Page input](#page-input)),
  created by migration `20261027000004_create_kb_stored_stmts_and_files.sql`.

<a id="validation-and-errors"></a>

## 7. Validation and errors

Descriptors are checked when they are saved to the database and again before an app or
page is shown. A page may be saved while an element or action is missing required instance
attributes, so an author can return to configure it later. For example, a new list can be
saved before its `source` and `columns` are set. The save still checks the page structure,
class copies and supplied values. Before the page runs, validation requires the missing
attributes and reports them. Each save creates the latest active page version, even when
incomplete, so that version cannot run until it has been completed and saved again.
The contract is in ChenWeb `openspec/specs/wpi-descriptor-store/spec.md`; update that spec
when this behavior changes.

The checks include:

| Check | Example |
| --- | --- |
| Structure | Valid JSON; only attributes known to the app or page format, or named by the element or action class; an attribute an element class names that its code module does not support is a warning ([Code modules](#code-modules)) |
| Panes | A page has a `page_layouter` with exactly one root pane; pane IDs are unique in the page; a split pane has `split` and two or more `children`; a page without a `page_layouter` is an error |
| References | Every referenced app and page exists (element and action instances hold copies of their classes and need no class rows, [Descriptors and instances](#descriptors-and-instances)); every key of a page's `panels` is the ID of a leaf pane of its page layouter; every `pane` that an `open-page` names resolves to a leaf pane ([Action classes](#action-classes)), checked when an app is loaded, since only then is it known in which panes of which pages a page can be opened; every statement a `query` names and every file a `load-file` names is stored |
| Tables | Every table and column named in a `load` or `save` action exists |
| Bindings | Paths are well formed; `__proto__`, `constructor` and `prototype` are rejected |
| Consistency | Every attribute in a `save` action is bound `read-write` by some element on the page (warning) |
| Instances | An element or action instance is checked against the class copy it holds, not against the stored class ([Element classes and instances](#element-classes-and-instances), [Actions](#actions)): `element` or `action` equals the copy's `descriptor_id`; the instance sets only instance attributes the copy names (an element also its sizes), none the copy fixes. Before a page runs, it must also set every attribute whose default in the copy is `null`. Missing values are allowed when the page is saved |
| Capabilities | The `code_module_id` in the class copy of every page layouter and element layouter is an active code module of its own type (`page-layouter` or `element-layouter`) that has code in this interpreter; the `code_module_id` in every element instance's class copy is an active element module that has code, and every action instance's `action` has code registered under that ID; every active action class has code registered under its class ID; every active element class names a code module that has code and is an active element module in `kb.code_modules` (an element class draft is checked for structure and against `kb.code_modules`, [Element classes and instances](#element-classes-and-instances), [Code modules](#code-modules)) |

Failures are never silent. On screen, an error box replaces the element or page and names
the descriptor and the problem. On the backend, the failure is logged.

<a id="pilot"></a>

## 8. Pilot (phase 1)

**Status:** built and verified on 2026-10-26 (ChenWeb OpenSpec change `wpi-pilot`). All
four checks below passed in a browser against the real backend, database and frontend,
with a stand-in user in place of a login (ChenWeb has no test login). Where the code lives,
how to change an app and the pilot's limits: devdoc 2026102603.

The pilot follows the model before the 2026-10-29 revision: layout templates, app descriptors
whose panes hold pages, and one panel per open page. Read "pane" and "panel" in this section,
[Implementation notes for the pilot](#pilot-implementation-notes) and [What the pilot taught](#pilot-lessons) in that sense; in the revised design a page instance is what the pilot called a
panel ([Page instances](#page-instances)).

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
- Storage in `kb.wpi_descriptors`, validation as in [Validation and errors](#validation-and-errors).

**Deliberately out of scope:** page state beyond the input doc, state machines,
conditions, action sequences, expressions, appearance attributes and style presets, the
split between class and instance attributes ([Element classes and instances](#element-classes-and-instances), [Actions](#actions)), i18n of descriptor text ([After the pilot](#after-the-pilot)), editable lists, lists that receive records instead of
querying them, refreshing a visible list after a save in another pane, timed refresh,
panel age-out (in the pilot a hidden panel lives until it is closed or the app is closed),
server-side paging and non-equality filters, protection against two users editing the same record
(last save wins), loading an app inside a page, `Collapse` and other elements that hold
panels, user-defined layout templates, LLM-generated descriptors.

**Done when**, on the demo table `kb.wpi_demo_customers` and using only descriptors stored
in `kb.wpi_descriptors`, the `customer-admin` app of [Descriptors by example](#descriptors-by-example):

1. opens from its URL (`/wpi/customer-admin`) with a header, a menu on the left and the
   customer list in the middle;
2. switches between *Customers* and *New customer* in the menu without reloading either
   page: a half-filled new-customer form keeps its entries, and the customer list re-runs
   its query each time it is shown;
3. inserts a new customer from the form and shows a server validation error next to the
   right field;
4. opens a clicked customer in the right pane, saves edits as an update, and asks before
   replacing a customer that has unsaved edits.

<a id="pilot-implementation-notes"></a>

### 8.1 Implementation notes for the pilot

These are about "how" and never appear in descriptors.

- Code lives in ChenWeb: frontend in `web/src/lib/wpi/`, backend in `server/api/wpi/`. It
  moves to `shared/` once a second project needs it.
- The input doc is held in Svelte 5 `$state`, which tracks changes deep inside the doc;
  bindings read and write it by path. WPI does not add its own reactivity system.
- A hidden panel stays mounted and is hidden with CSS, so its input doc and the state of
  its elements survive without reloading.
- Element code modules form a registry, `codeModules` in
  `web/src/lib/wpi/elements/index.ts`, that maps each code module ID to a Svelte component
  ([Code modules](#code-modules)); the backend validator keys what each module accepts the same way (`codeModules`
  in `server/api/wpi/validate.go`), and keys action code by action class ID (`actionAttrs`).
  Until 2026-10-28 these were `elementClasses` and `elementAttrs`, keyed by class ID; in the
  pilot the key was `element_type`.
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

<a id="after-the-pilot"></a>

## 9. After the pilot

The likely direction, decided phase by phase:

- **Updating visible pages after a save elsewhere.** The most visible gap in the pilot:
  after a customer is saved in the right pane, the list in the middle keeps showing the
  old values until it is shown again. A page needs a way to learn that data it shows has
  changed, for example an event such as "record saved" that lists listen to ([What the pilot taught](#pilot-lessons)).
- **Authoring descriptors.** The pilot has only the admin write endpoint. A way to browse,
  edit and preview descriptors comes before anyone other than a developer writes them.
  Since pages are reused by copying, the backend can search pages and read one to copy
  ([Reuse by copying](#reuse-by-copying)); the editor uses them through Load Page. The WPI editor creates element classes as
  drafts and edits element classes from their nodes ([Element classes and instances](#element-classes-and-instances), 2026-10-27); retiring a
  draft, and creating pages and action classes there, are still open.
- **Classes and instances.** Built for elements and actions on 2026-10-27 (OpenSpec change
  `wpi-classes-and-instances`). Pages have no classes; they are reused by copying (decided
  2026-10-27, [Reuse by copying](#reuse-by-copying)). Later, *extended attributes*: attributes a single instance adds that
  its class does not name, so that instances of one class can differ in more than their
  values.
- **Pages ([Pages](#pages)).** Built on 2026-10-27 (OpenSpec change `wpi-pages`). Still open: a way
  to add stored statements and files other than migrations or `psql`, and versions for
  them.
- **i18n of descriptor text.** Labels and other text in descriptors need English and
  Chinese. Element labels and descriptions take a plain string or one text per language,
  falling back to `en` ([Element classes and instances](#element-classes-and-instances)), and so do page names and descriptions ([Page attributes](#page-attributes)); the
  text module R2 now also supports these forms for static text, captions and tooltips
  (implemented 2026-10-30, OpenSpec `wpi-text-r2`). The same forms should later cover list
  column labels, menu item labels and select options. ChenWeb sends all text through Paraglide, which cannot
  reach text stored in the database, so this still needs its own decision, probably an ADR
  amending ADR 2026093001.
  Until then, WPI apps are an exception to the "every page in English and Chinese" rule
  and should not be shown to end users.
- **More elements and presentation:** textarea, checkbox, date and number inputs, tabs;
  card presentation and editable lists; lists that receive their records from outside;
  server-side paging and filters; appearance attributes and style presets; more element layouters.
- **Elements that hold panels**, such as a `Collapse` whose folders each open a page.
  How this fits the pane and panel model is not worked out yet.
- **Timed refresh and panel age-out** ([Panel Cache](#panel-cache)). Age-out is what limits the
  memory hidden pages use, since a pane that switches pages never closes one.
- **Authoring layouters.** Page layouters and element layouters are stored classes ([Page layouters](#page-layouters),
  [Element layouters](#element-layouters)), but only the built-in ones exist. A way to create them is open.
- **The 2026-10-29 revision.** Built on 2026-10-30 (OpenSpec change `wpi-pages-own-panes`):
  the app descriptor without panes, page descriptors with `page_layouter` and `panels`, pane
  margins, a whole copy of its class in the `class` of every element instance, action instance
  and layouter copy, the `page-layouter` code module, the `page-layouter` and
  `element-layouter` module types and descriptor kinds, the Panel Cache, the outward lookup of
  an `open-page`'s `pane`, pane editing in the WPI editor, validator and migration
  ([Pages](#pages), [Panel Cache](#panel-cache), [Descriptors by example](#descriptors-by-example)).
- **More `open-page` targets.** Rendering a page in the current tab, in a new tab or in an iframe
  (the URL has to name the page too) ([Loading a page by URL](#loading-by-url), [Action classes](#action-classes)).
- **Loading a WPI app inside an ordinary page** ([WPI apps](#wpi-apps)), when a need appears.
- **Page state and richer actions:** state scopes, named docs that bindings can reach
  besides `$input_doc` ([Element classes and instances](#element-classes-and-instances)), change events, conditions, action sequences, derived
  values (report §5–6).
- **Composition:** elements built from other elements, reusable parameterized actions,
  and registered domain services for logic that should not be declarative (report §8).
- **Workflows and state machines** for multi-step behavior.
- **Production runtime:** descriptor format migrations, permission capabilities,
  execution tracing, moving descriptors between staging and production.
- **LLM-generated pages:** an LLM writes descriptors, which are validated before use
  (report §11).

<a id="confirmed-rules"></a>

## 10. Confirmed rules

These rules fill gaps in the original design; all four were confirmed on 2026-10-26, and rule 2
was replaced on 2026-10-30:

1. Menu items that open the same page with the same input in the same pane share one page instance ([Panel Cache](#panel-cache)).
2. A pane that switches to another page hides the one it was showing and never closes it; the
   Panel Cache finds it again by page and input ([Panel Cache](#panel-cache)). Until
   2026-10-30 this rule read: a panel that no menu item is bound to is closed, not hidden, when
   another panel replaces it.
3. A refresh never reloads an input doc with unsaved changes, and a page instance with unsaved
   changes is never aged out ([Panel Cache](#panel-cache)).
4. A menu may name an `initial_item`, opened when the page holding the menu is opened
   ([Elements in panels](#elements-in-panels), [A home page with a menu](#home-page-example)).

<a id="pilot-lessons"></a>

## 11. Logging 
Refer to "KnowledgeStore/doc-repo/devdocs/202610/2026103001-devdoc-wpi-logging-proposal.md".

## 12. What the pilot taught

Findings from building the pilot that matter for the next phases:

1. **Inline actions can live in elements as well as pages.** A stored element (a list, a
   menu) can carry its own trigger with an inline action, so the server names an action as
   `{kind, id, pointer}`: a stored action by ID, or the JSON Pointer of an inline action
   inside a stored page or element ([Which tables actions may touch](#which-tables-actions-may-touch)).
2. **Strict validation keeps descriptors honest.** The validator rejects attributes it
   does not know, so a descriptor cannot quietly depend on a feature that does not exist
   yet ([Descriptors by example](#descriptors-by-example)). The cost: each new attribute or type must be added in three places, namely
   the Go validator, the TypeScript types and the Svelte registry. Counting such changes
   per new page is the measure of principle 2.
3. **Visible pages go stale.** Refresh on show covers pages that are switched back to, but
   not two pages visible side by side ([After the pilot](#after-the-pilot), first item). This is the first real need for
   events between pages.
4. **Dirty tracking needed content comparison.** Comparing a canonical copy of the doc,
   rather than counting edits, makes "change it back" not dirty and survives the server
   adding the new key after an insert.
