# Web Page Interpreter pilot — pages drawn from descriptors stored in the database

**Date:** 2026-10-26, updated 2026-10-27 for classes and instances, and for pages \
**Scope:** What the WPI pilot built in ChenWeb, how to open and change a WPI app, and its
limits. The overall design and later phases are in devdoc
[2026102601](2026102601-devdoc-web-page-interpreter.md). \
**Code root:** `ChenWeb/server/api/wpi` (backend), `ChenWeb/web/src/lib/wpi` (frontend)

**Traceability — openspec:**
- `ChenWeb/openspec/changes/wpi-pilot/proposal.md` — why this exists
- `ChenWeb/openspec/changes/wpi-pilot/design.md` — technical decisions, the exact
  descriptor format the pilot accepts (schema_version `0.1`), the API, risks
- `ChenWeb/openspec/changes/wpi-pilot/tasks.md` — implementation log and how each part
  was verified
- `ChenWeb/openspec/changes/wpi-pilot/specs/wpi-*/spec.md` — the requirements; after the
  change is archived they live in `ChenWeb/openspec/specs/wpi-descriptor-store`,
  `wpi-data-actions`, `wpi-app-shell` and `wpi-page-rendering`. **Update these spec files,
  not just this doc, if behavior changes** — this doc explains the feature for people; the
  specs are the contract.
- `ChenWeb/openspec/changes/wpi-classes-and-instances/` — the change of 2026-10-27 that
  replaced stored per-field elements and actions with classes and instances (descriptor
  format `0.2`); its `design.md` has the decisions, and its specs add capability
  `wpi-classes` and modify three of the four above.
- `ChenWeb/openspec/changes/wpi-pages/` — the change of 2026-10-27 that gave pages their own
  table, names, descriptions, size and alignment, and new sources of data (static data,
  stored SQL statements, stored files); its specs add capabilities `wpi-pages` and
  `wpi-stored-sources`.

## Summary

ChenWeb can now show a small application whose screens are not programmed but described.
Each screen, field, button, list and action is a short JSON description (a *descriptor*)
stored in the database. One general-purpose program, the interpreter, reads those
descriptors and draws the screens. To add or change a screen, someone writes or edits
descriptors; no frontend code changes.

Since 2026-10-27, fields, buttons, lists and actions are written inside the page that uses
them, as *instances* of a few *classes* such as "input", "list" or "open page". A class is
stored once, carries the defaults its instances share, and is tied to the program code that
draws or runs it. Pages have no classes: a page is complete in itself, has a name and a
description so that authors can find it, and is reused by copying it.

The pilot proves this with a demo app, **customer admin**, opened at
`/wpi/customer-admin`. It has a header, a menu on the left, a list of customers in the
middle and a customer form on the right. A user can:

- switch between *Customers* and *New customer* in the menu. Each page is kept as it was,
  so a half-filled form keeps its entries, and the customer list re-reads the database
  each time it is shown again;
- add a customer. The server checks the entries; problems (a missing name, a malformed
  email) appear next to the field concerned;
- click a customer to open it on the right, edit it and save it;
- be asked before unsaved changes are thrown away, whether by opening another customer,
  closing a page or leaving the browser page;
- open *Directory*, a customer list read through a SQL statement stored on the server, and
  *About*, a read-only page whose text comes from a file stored in the database. The header's
  title is data written in the page itself.

The interpreter's own messages (the unsaved-changes question, error messages) appear in
English or Chinese, and so do the customer form's labels, which the descriptors give in
both languages; other text written inside descriptors is shown as written.

## Where things live

- **Open an app:** `/wpi/<app-id>` in a logged-in browser. The URL holds only the app's ID;
  everything else comes from its descriptors. WPI apps have no entry in ChenWeb's menus.
- **Descriptors:** pages in table `kb.frontend_pages`, apps and classes in
  `kb.wpi_descriptors`, one row per version. The interpreter uses the newest active version
  of each descriptor. The classes and the demo app (format `0.2`) were seeded by migration
  `ChenWeb/project_migrations/20261027000002_seed_wpi_classes_and_instances.sql`, and the
  demo's current pages by `20261027000005_seed_wpi_pages_demo.sql`; the pilot's original
  seed, `20261026000003_seed_wpi_customer_admin.sql`, is superseded and its stored elements
  and actions are retired. The demo data is in `kb.wpi_demo_customers`.
- **Stored SQL statements and files:** tables `kb.stored_stmts` and `kb.stored_files`,
  written only by migrations or `psql`; each row lists the user roles that may use it.
- **Changing a descriptor:** an admin sends the new body with
  `PUT /api/v1/wpi/descriptors/<kind>/<descriptor-id>`, which checks it and stores it as a
  new version. Nothing edits rows in place, and apart from creating element classes (below)
  there is no editor screen yet. The format
  is described in devdoc 2026102601 §3.2, §3.5 and §5, with complete examples in its §4.
- **Finding a page to copy:** `GET /api/v1/wpi/pages?q=<text>` searches page IDs, names and
  descriptions; `GET /api/v1/wpi/pages/<page-id>` returns a page's newest version.
- **Creating an element class:** in the WPI editor (Development → Tools → WPI Editor),
  *Create Nodes → Create Element* opens a form listing the class's attributes, starting
  with `descriptor_id`, `schema_version` and `description` (*Add Attribute* adds instance
  attributes; double-click a value to edit it, or an instance attribute's name to rename
  it; the form resizes from its corner), and stores the class as a draft through `POST /api/v1/wpi/classes/element`
  (admins). An ID that already exists is refused. The palette's ELEMENTS folder lists the
  classes from `GET /api/v1/wpi/classes/element`. A draft is not used until a developer
  registers its code and PUTs the class row, which stores it as active (devdoc 2026102601
  §3.5.1). The form is `web/src/lib/components/shared-ui/canvas/CreateElementDialog.svelte`.
- **Backend** (`ChenWeb/server/api/wpi/`): validation of single descriptors
  (`validate.go`) and of everything an app reaches (`bundle.go`); the endpoints
  (`handler.go`, `actions.go`); storage (`store.go`); SQL building and save rules
  (`sqlbuild.go`, `rules.go`).
  Routes are registered in `server/api/routes.go`.
- **Frontend** (`ChenWeb/web/src/lib/wpi/`): the running app (`runtime.svelte.ts`), pane and
  panel bookkeeping (`panels.ts`), layout templates (`templates/`), the flow layouter
  (`layouters/`), element classes (`elements/`, registered by class ID). The page is
  `web/src/routes/wpi/[appId]/+page.svelte`.
- **Tests:** `go test ./server/api/wpi/` (includes tests that the seeded demo app is
  valid) and `bun test src/lib/wpi` from `web/`.

## Known limitations

- **Most descriptor text is not translated.** Labels can be given per language, but menu
  items, list columns, select options and text elements appear as written, which breaks the
  "every page in English and Chinese" rule; that is why WPI apps are not linked from
  ChenWeb's menus (devdoc 2026102601 §9).
- **Any logged-in user can run any load or save written in a stored page, on any table.**
  This was decided on purpose for the pilot. The only safeguards are that only stored
  descriptors run (the browser cannot name tables or columns), only admins can write
  descriptors, and every run is logged. Stored SQL statements and files are stricter: each
  lists the roles that may use it, and statements run read-only.
- **The last save wins.** Two people editing the same record do not see each other's
  changes, and nothing warns them.
- **A list does not update while it is visible.** After a customer is saved on the right,
  the list in the middle still shows the old values until it is shown again (for example by
  clicking *Customers*).
- **Pages kept in the background stay until closed.** There is no time limit yet, and no
  timed refresh.
- **Small vocabulary:** two layout templates (`single-pane`,
  `top-left-middle-right-bottom`), one layouter (`flow-layouter`), six element classes
  (text, input, select, button, list, menu), seven action classes (load, save, query, load
  file, open page, close page, save page).
  Lists are read-only, show at most 1000 rows and filter by equality only; pulldown options
  are written in the descriptor.
- **Only panes with a fixed width in pixels can be resized** by dragging.
- **A value that starts with `$` is always read as a reference** (such as `$input_doc.email`),
  so a literal text that begins with `$` cannot be written in a descriptor.
- **How it was verified:** the four checks of devdoc 2026102601 §8 passed in a browser on
  2026-10-26, and again on 2026-10-27 in format `0.2` together with the Chinese labels,
  using the real backend code, database and frontend, but with a stand-in user in place of
  a login, because ChenWeb has no test login. The pages features (header from static data,
  *Directory*, *About* centred and read-only) were checked the same way on 2026-10-27.
