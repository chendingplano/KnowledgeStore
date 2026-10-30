# Module: Web Page Interpreter (backend)

**Module ID:** `20261026-02`
**Type:** backend · **Language:** go · **Version:** 3.1.0
**Status:** under-dev — apps and pages in format `0.5`: pages own their panes through a copy
of a page layouter class, panels hold elements with a copy of an element layouter class, and
every instance holds a copy of its class, filled in when a page is written (2026-10-30,
OpenSpec change `wpi-pages-own-panes`); element class rows `0.4`, action class rows `0.2`;
serves the WPI frontend (module `20261026-01`)
**Project:** ChenWeb (server)
**Location:** `ChenWeb/server/api/wpi`
**Created:** 2026-10-26

## 1. What it is

The server half of the Web Page Interpreter (WPI). It keeps the descriptors that describe
WPI apps in the database, checks them, hands the browser an app together with everything
the app uses, and runs the actions that touch data: loading and saving records, running SQL
statements stored on the server (`query`), and reading JSON files stored in the database
(`load-file`). It also lets authors search pages and read one to copy, since pages have no
classes and are reused by copying, and lets the WPI editor define a new element class as a
draft before its code exists.

Elements, actions and layouters come as classes; using one copies it. A class (`input`,
`list`, `load`, `open-page`, `single-pane`, `flow-layouter`, …) is a stored row. An action
class's ID names the code that implements it; an element or layouter class names its code
module in `code_module_id`, which must be an active module of the right type in
`kb.code_modules` (`element`, `page-layouter`, `element-layouter`). When a page is written,
every element instance, action instance and layouter copy without a `class` gets a copy of the
active class; copies already there are kept, so a later change to a class reaches only pages
written afterwards. Instances are checked and merged against their own copy, never the stored
class. Checking happens before anything is shown: missing pages, instances that do not fit
their copy or set an attribute it fixes, pane trees that are not one tree, panels of panes the
page does not have, `open-page` panes that no page in any chain it can be opened in has,
tables or columns that do not exist, unsafe binding paths, copies with a module that is not
active, and statements or files that are not stored are all reported, with the descriptor and
the place inside it. An attribute a class names that its code module does not support is a
warning, not an error. Only instances written in stored pages run, so the browser can supply
values but never table names, column names or SQL. Stored statements and files list the user
roles that may use them, and statements run read-only.

It is not a general data API: it only runs actions written as WPI descriptors. Design:
devdoc `2026102601-devdoc-web-page-interpreter.md`; what was built: devdoc
`2026102603-devdoc-wpi-pilot.md`; formal requirements: OpenSpec changes `wpi-pilot`,
`wpi-classes-and-instances`, `wpi-pages`, `wpi-create-element-class`, `wpi-code-modules` and
`wpi-pages-own-panes`.

## 2. Files

| File | Purpose |
|---|---|
| `ChenWeb/server/api/wpi/types.go` | Kinds (including `page-layouter` and `element-layouter`), descriptor formats by kind (`0.5` apps, pages and layouter classes; `0.4` element classes; `0.2` action classes), bundle and action types |
| `ChenWeb/server/api/wpi/refs.go` | Reference parsing and rules; `$args` substitution |
| `ChenWeb/server/api/wpi/refs_test.go` | Tests for `refs.go` |
| `ChenWeb/server/api/wpi/validate.go` | What each code module and action class accepts (`codeModules`; `actionAttrs`; `pageLayouterModules`; `elementLayouterModules` with their parameters); checks of one descriptor (`ValidateDescriptor`, `validatePage`): apps, pages, pane trees (`paneTree`, leaf-only attributes), panels, layouter copies and classes, class copies (`classCopy`), instances against their copy (`againstCopy`, `classDefaults`, `mergeInstance` with fixed values); where action instances sit in a page's panels (`actionPositions`); element class rows in format 0.4, drafts and class edits (`ValidateDraftClass`, `validateElementClass`), attributes a module does not support (`classWarnings`) |
| `ChenWeb/server/api/wpi/validate_test.go` | Tests for `validate.go` |
| `ChenWeb/server/api/wpi/flow_test.go` | Tests for a panel's flow-layouter parameters |
| `ChenWeb/server/api/wpi/copies.go` | Copies the active class into every instance and layouter copy of a page that has none (`fillClassCopies`, `copySites`) |
| `ChenWeb/server/api/wpi/bundle.go` | Loads an app, its initial page and the pages its `open-page` instances open, and validates the whole set: pages, the code modules their class copies name (`pageModules`, `moduleErrors`), the outward pane lookup over host chains (`paneErrors`, `resolvePane`), tables, stored statements and files (`BuildBundle`, `BuildPagePreviewBundle`); warnings for unbound save attributes and unsupported attributes in copies |
| `ChenWeb/server/api/wpi/bundle_test.go` | Tests for `bundle.go` |
| `ChenWeb/server/api/wpi/catalog.go` | Table and column existence from `information_schema`; identifier quoting; the table catalog of configured databases |
| `ChenWeb/server/api/wpi/catalog_test.go` | Tests for `catalog.go` |
| `ChenWeb/server/api/wpi/database_catalog_test.go` | Tests for database-qualified tables and their pools |
| `ChenWeb/server/api/wpi/store.go` | Latest active descriptor lookup (pages from `kb.frontend_pages`, other kinds from `kb.wpi_descriptors`); inserting a new version; page summaries for search; stored statements and files; inserting an element class draft, listing element classes and updating one in place; active modules of each type and all rows of `kb.code_modules` |
| `ChenWeb/server/api/wpi/store_test.go` | Tests for `store.go` |
| `ChenWeb/server/api/wpi/handler.go` | `Handler`, `New`; app bundle, page preview bundle, descriptor write (pages get their class copies and are returned), page search and page read, element class create, list, read and edit, and code module list endpoints; the code module check of element and layouter class writes (`checkModule`) |
| `ChenWeb/server/api/wpi/handler_test.go` | Tests for `handler.go` |
| `ChenWeb/server/api/wpi/actions.go` | Action run endpoint: find the instance by page and pointer, check and merge it with its class copy, then load, save, query (read-only) or load-file, with the stored rows' access controls |
| `ChenWeb/server/api/wpi/input_rules.go` | Validates input element values against stored page class copies before saving |
| `ChenWeb/server/api/wpi/input_rules_test.go` | Input rules and descriptor migration tests |
| `ChenWeb/project_migrations/20261030000003_wpi_input_attributes.sql` | Adds the expanded input class version |
| `ChenWeb/server/api/wpi/actions_test.go` | Tests for `actions.go` |
| `ChenWeb/server/api/wpi/preview.go` | Admin preview of an unsaved list source (given a copy of the active `load` class when it has none) |
| `ChenWeb/server/api/wpi/preview_test.go` | Tests for `preview.go` |
| `ChenWeb/server/api/wpi/sqlbuild.go` | Pure SELECT / INSERT / UPDATE builders with quoted identifiers and parameters |
| `ChenWeb/server/api/wpi/sqlbuild_test.go` | Tests for `sqlbuild.go` and `rules.go` |
| `ChenWeb/server/api/wpi/rules.go` | Save rules: required, max_length, pattern, email format |
| `ChenWeb/server/api/wpi/stored_test.go` | Tests for `query`, `load-file`, access controls, page search and page read |
| `ChenWeb/server/api/wpi/seed_test.go` | Checks that the seeded classes, the layouter classes and modules, and the demo apps as `20261030000001` converts them are valid |
| `ChenWeb/server/api/wpi/customers_demo_integration_test.go` | With `WPI_TEST_DB=1`: the migrated demo apps load, and page search works, against a real database (read-only) |
| `ChenWeb/project_migrations/20261026000001_create_kb_wpi_descriptors.sql` | Table `kb.wpi_descriptors` |
| `ChenWeb/project_migrations/20261026000002_create_kb_wpi_demo_customers.sql` | Demo table `kb.wpi_demo_customers` |
| `ChenWeb/project_migrations/20261026000003_seed_wpi_customer_admin.sql` | Pilot demo app (format `0.1`; its stored elements and actions are retired) |
| `ChenWeb/project_migrations/20261027000002_seed_wpi_classes_and_instances.sql` | Element and action classes; demo app in format `0.2` |
| `ChenWeb/project_migrations/20261027000003_create_kb_frontend_pages.sql` | Table `kb.frontend_pages`; moves every page row out of `kb.wpi_descriptors` |
| `ChenWeb/project_migrations/20261027000004_create_kb_stored_stmts_and_files.sql` | Tables `kb.stored_stmts` and `kb.stored_files` |
| `ChenWeb/project_migrations/20261027000005_seed_wpi_pages_demo.sql` | `query` and `load-file` classes; demo statements and file; demo pages with names, static data, directory and About |
| `ChenWeb/project_migrations/20261027000006_wpi_element_classes_0_3.sql` | The six element classes again (version 2) in format `0.3`, with help tips in English and Chinese |
| `ChenWeb/project_migrations/20261028000001_wpi_element_classes_0_4.sql` | The latest row of every element class again in format `0.4`, keeping authors' attributes; active classes get `code_module_id` equal to their ID |
| `ChenWeb/project_migrations/20261028000002_create_kb_code_modules.sql` | Table `kb.code_modules`, seeded with the six element modules |
| `ChenWeb/project_migrations/20261028000003_register_flow_layouter.sql` | The `flow-layouter` code module |
| `ChenWeb/project_migrations/20261028000004_seed_wpi_customers_demo.sql` | The Development menu's Customers demo app and page |
| `ChenWeb/project_migrations/20261028000005_isolate_wpi_customers_demo.sql` | The demo's own page `demo-customers` |
| `ChenWeb/project_migrations/20261029000001_rename_wpi_page_alignment.sql` | Page attribute `page_alignment` renamed `hori_align` |
| `ChenWeb/project_migrations/20261030000001_wpi_pages_own_panes.sql` | Layouter kinds, module types and classes; every page converted to format `0.5` with class copies; `customer-admin-home`; both demo apps naming their initial page |

## 3. Interface

Routes (registered on the authenticated `/api/v1` group in `server/api/routes.go`):

| Method and path | Who | Request | Response |
| --- | --- | --- | --- |
| `GET /api/v1/wpi/apps/:appId` | logged-in | — | 200 `{app, pages, warnings}` (pages carry their class copies); 404; 422 `{errors, warnings}` |
| `GET /api/v1/wpi/pages/:pageId/preview` | logged-in | — | 200 a bundle whose app's initial page is the page; 404; 422 `{errors, warnings}` |
| `PUT /api/v1/wpi/descriptors/:kind/:descriptorId` | admin | descriptor JSON; `kind` is `app`, `page`, `element`, `action`, `page-layouter` or `element-layouter` | 200 `{kind, descriptor_id, version, warnings}`, plus `page` (the stored page, with the class copies the server added) for a page; 400 `{errors}`, including a class with no active row to copy, a page checked completely against its copies, and an element or layouter class whose module is not active in `kb.code_modules`; 403 |
| `POST /api/v1/wpi/actions/preview-list` | admin | `{source, args}` | 200 the records of an unsaved list `load` source; 400; 403 |
| `POST /api/v1/wpi/actions/run` | logged-in | `{ref: {kind: "page", id, pointer}, args, input_doc}` | load, query, load-file 200 `{result}`; save 200 `{key_attribute, key_value}` or 422 `{field_errors}`; 400; 403 (stored row's roles); 404 |
| `GET /api/v1/wpi/pages?q=&limit=` | logged-in | — | 200 `{pages: [{descriptor_id, version, page_name, description, updated_at}]}`, matching ID, name or description in any language; 400 |
| `GET /api/v1/wpi/pages/:pageId` | logged-in | — | 200 `{version, page}` (newest active version); 404 |
| `POST /api/v1/wpi/classes/element` | admin | element class row (`descriptor_id`, `schema_version` `0.4`, required `description`, optional `code_module_id`, attribute objects) | 201 `{descriptor_id, version: 1, status: "draft", warnings}`; 400 `{errors}`, including a `code_module_id` that is not an active element module in `kb.code_modules`; 403; 409 when any row of the class ID exists |
| `GET /api/v1/wpi/classes/element` | logged-in | — | 200 `{classes: [{descriptor_id, version, status, description, attributes}]}`: the latest draft or active version of each element class, by ID; `attributes` holds the row's instance attributes, each `{help_tip, default_value, instance_modifiable}` |
| `GET /api/v1/wpi/classes/element/:classId` | logged-in | — | 200 `{version, status, class}`: the class's latest draft or active row, whole; 404 |
| `PUT /api/v1/wpi/classes/element/:classId` | admin | the edited class row (same `descriptor_id`) | 200 `{descriptor_id, version, status, warnings}`: the latest draft or active row updated in place, keeping its version and status; a draft checked as a draft, an active class for structure and a code module that has code; 400 `{errors}` or a changed `descriptor_id`; 403; 404 when the class has no draft or active row |
| `GET /api/v1/wpi/code-modules` | logged-in | — | 200 `{code_modules: [{code_module_id, module_name, description, module_type, module_doc, notes, status}]}`, by type and ID |

Go API: `wpi.New(db *sql.DB) *Handler` (methods `GetApp`, `GetPagePreview`, `PutDescriptor`,
`RunAction`, `PreviewList`, `SearchPages`, `GetPage`, `CreateElementClass`,
`ListElementClasses`, `GetElementClass`, `UpdateElementClass`, `ListCodeModules`);
`Handler{DB, User}` with an injectable user lookup for tests;
`ValidateDescriptor(kind, id, body) []Issue`; `ValidateDraftClass(body) []Issue`;
`BuildBundle(ctx, appID, Loader, Columns, Registered) (*BundleResult, error)` and
`BuildPagePreviewBundle(ctx, pageID, …)`, where a `Loader` returns the latest active
descriptors of a kind and `Registered` says which stored statements or files exist and which
code modules are active modules of a type.

## 4. Configuration

None. Fixed limits: list loads return 200 rows by default and at most 1000; a `query`
returns at most 1000 rows and runs at most 10 seconds; a page search returns 50 pages by
default and at most 200; request bodies are read up to 1 MiB.

## 5. Usage

Storing a new version of a page (admin session cookie required):

```bash
curl -X PUT http://localhost:8080/api/v1/wpi/descriptors/page/customers \
  -H 'Content-Type: application/json' --cookie "session_id=…" \
  -d '{"descriptor_id": "customers", "schema_version": "0.5",
       "page_layouter": {"layouter": "single-pane"},
       "panels": {"main": {"elem_layouter": {"layouter": "flow-layouter"},
                           "elem_list": [{"element": "text", "text": "Hello"}]}}}'
```

Adding a code module, for example `checkbox`: add its row to `kb.code_modules` (a
migration) and its document to `KnowledgeStore/doc-repo/code_modules/`, add its attributes
to `codeModules` in `validate.go`, and register its frontend code under the same ID (module
`20261026-01`). Then store a class row naming it (`PUT /api/v1/wpi/descriptors/element/<id>`,
or a migration). An element class row is format `0.4`: `code_module_id` names its module, and
each instance attribute is `{"help_tip": …, "default_value": …, "instance_modifiable": …}`,
where a `null` default means every instance must set it, no `default_value` means optional,
and `instance_modifiable: false` fixes the value for every instance; an optional
`implement_notes` holds the implementation prompt. A class of an existing module, such as
`fancy-button` drawn by `button`, needs only its row. Adding an action class: add its
attributes to `actionAttrs` and its code, then store its row, which stays `0.2`, with the
default or `null` itself. An element class may be defined first as a draft, from the WPI
editor's *Create Element* or with `POST /api/v1/wpi/classes/element`; the PUT then makes it
active once its module has code. The editor's *Edit class* changes a class in place through
`PUT /api/v1/wpi/classes/element/:classId`, which keeps its version and status.

Registering the routes in another Echo group:

```go
h := wpi.New(ApiTypes.ProjectDBHandle)
group.GET("/wpi/apps/:appId", h.GetApp)
group.PUT("/wpi/descriptors/:kind/:descriptorId", h.PutDescriptor)
group.POST("/wpi/actions/run", h.RunAction)
group.GET("/wpi/pages", h.SearchPages)
group.GET("/wpi/pages/:pageId", h.GetPage)
group.GET("/wpi/classes/element", h.ListElementClasses)
group.POST("/wpi/classes/element", h.CreateElementClass)
group.GET("/wpi/classes/element/:classId", h.GetElementClass)
group.PUT("/wpi/classes/element/:classId", h.UpdateElementClass)
group.GET("/wpi/code-modules", h.ListCodeModules)
```

Adding a stored statement for `query` (no API writes these tables; use a migration or
`psql`). `access_controls` lists the roles that may run it; NULL, `{}` or `{all}` means
everyone:

```sql
INSERT INTO kb.stored_stmts (stmt_name, sql_stmt, description, creator, access_controls)
VALUES ('customers-by-city', 'SELECT id, user_name FROM kb.customers WHERE city = $1',
        'Customers in one city', 'cding', '{sales}');
```

## 6. Behaviour and conventions

- Every request is logged with `CreateDefaultLogger`; every action run logs the action
  reference, user, table or stored statement or file, mode, row count and duration.
- Values always go to PostgreSQL as parameters; table and column names are checked against
  the catalog and quoted. Request numbers are kept as text so PostgreSQL converts them to
  the column type.
- Error messages returned to the browser never contain database internals; database
  rejections of a value become 400 "The database rejected the values".
- Descriptor versions are append-only, except that *Edit class* updates an element class's
  latest draft or active row in place; the newest active version is used. Element class
  drafts are `draft` rows, never used by the interpreter.

## 7. Scope and limits

- Any logged-in user may run any `load`/`save` instance in a stored page, on any table
  (decided for the pilot); only admins write descriptors. `query` and `load-file` follow
  their stored row's `access_controls`.
- Stored statements and files, and `kb.code_modules`, have no write API and no versions.
- Only format `0.5` (apps, pages, layouter classes), `0.4` (element classes) and `0.2`
  (action classes) are accepted; older formats are rejected.
- Action classes still name their code by their class ID; element and layouter classes name
  a row of `kb.code_modules`.
- Layouter classes have no editor screen; they are written with the descriptor PUT or a
  migration.
- Last save wins; no conflict detection.
- `where` supports equality only; no paging.
- Tests use `go-sqlmock`; none touch the `miner` database.
- Move to `shared/go` when a second project uses it.
