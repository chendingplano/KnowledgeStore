# Web Page Interpreter pilot — pages drawn from descriptors stored in the database

**Date:** 2026-10-26 \
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

## Summary

ChenWeb can now show a small application whose screens are not programmed but described.
Each screen, field, button, list and action is a short JSON description (a *descriptor*)
stored in the database. One general-purpose program, the interpreter, reads those
descriptors and draws the screens. To add or change a screen, someone writes or edits
descriptors; no frontend code changes.

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
  closing a page or leaving the browser page.

The interpreter's own messages (the unsaved-changes question, error messages) appear in
English or Chinese; the text written inside descriptors is shown as written.

## Where things live

- **Open an app:** `/wpi/<app-id>` in a logged-in browser. The URL holds only the app's ID;
  everything else comes from its descriptors. WPI apps have no entry in ChenWeb's menus.
- **Descriptors:** table `kb.wpi_descriptors`, one row per version. The interpreter uses
  the newest active version of each descriptor. The demo app's descriptors were seeded by
  migration `ChenWeb/project_migrations/20261026000003_seed_wpi_customer_admin.sql`; its
  data is in `kb.wpi_demo_customers`.
- **Changing a descriptor:** an admin sends the new body with
  `PUT /api/v1/wpi/descriptors/<kind>/<descriptor-id>`, which checks it and stores it as a
  new version. Nothing edits rows in place, and there is no editor screen yet. The format
  each kind of descriptor accepts is listed in the change's `design.md`.
- **Backend** (`ChenWeb/server/api/wpi/`): validation of single descriptors
  (`validate.go`) and of everything an app reaches (`bundle.go`); the three endpoints
  (`handler.go`, `actions.go`); SQL building and save rules (`sqlbuild.go`, `rules.go`).
  Routes are registered in `server/api/routes.go`.
- **Frontend** (`ChenWeb/web/src/lib/wpi/`): the running app (`runtime.svelte.ts`), pane and
  panel bookkeeping (`panels.ts`), layout templates (`templates/`), the flow layouter
  (`layouters/`), element types (`elements/`). The page is
  `web/src/routes/wpi/[appId]/+page.svelte`.
- **Tests:** `go test ./server/api/wpi/` (includes a test that the seeded demo app is
  valid) and `bun test src/lib/wpi` from `web/`.

## Known limitations

- **Descriptor text is not translated.** Labels inside descriptors appear as written, which
  breaks the "every page in English and Chinese" rule; that is why WPI apps are not linked
  from ChenWeb's menus. Deciding how descriptor text is translated is the next phase
  (devdoc 2026102601 §9).
- **Any logged-in user can run any stored load or save action, on any table.** This was
  decided on purpose for the pilot. The only safeguards are that only stored descriptors
  run (the browser cannot name tables or columns), only admins can write descriptors, and
  every run is logged.
- **The last save wins.** Two people editing the same record do not see each other's
  changes, and nothing warns them.
- **A list does not update while it is visible.** After a customer is saved on the right,
  the list in the middle still shows the old values until it is shown again (for example by
  clicking *Customers*).
- **Pages kept in the background stay until closed.** There is no time limit yet, and no
  timed refresh.
- **Small vocabulary:** two layout templates (`single-pane`,
  `top-left-middle-right-bottom`), one layouter (`flow-layouter`), six element types (text,
  input, select, button, list, menu), four actions (load, save, open page, close page).
  Lists are read-only, show at most 1000 rows and filter by equality only; pulldown options
  are written in the descriptor.
- **Only panes with a fixed width in pixels can be resized** by dragging.
- **A value that starts with `$` is always read as a reference** (such as `$input_doc.email`),
  so a literal text that begins with `$` cannot be written in a descriptor.
- **How it was verified:** the four checks of devdoc 2026102601 §8 passed in a browser on
  2026-10-26, using the real backend code, database and frontend, but with a stand-in user
  in place of a login, because ChenWeb has no test login.
