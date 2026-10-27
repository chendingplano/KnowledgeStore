# Module: Web Page Interpreter (backend)

**Module ID:** `20261026-02`
**Type:** backend · **Language:** go · **Version:** 2.4.0
**Status:** under-dev — pilot, with element and action classes (descriptor format `0.2`;
element class rows `0.3`, each instance attribute an object with a help tip and a default) and
pages in their own table with stored SQL statements and files, and element classes created as
drafts by the WPI editor (2026-10-27); serves the WPI frontend (module `20261026-01`)
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

Elements and actions come as classes and instances. A class (`input`, `list`, `load`,
`save`, `open-page`, …) is a stored row whose ID names the code that implements it; an
instance is written inside the page that uses it and is checked against its class. Checking
happens before anything is shown: missing pages or classes, instances that do not fit their
class, panes that the app's layout does not have, tables or columns that do not exist, unsafe
binding paths, classes without code, and statements or files that are not stored are all
reported, with the descriptor and the place inside it. Only instances written in stored pages
run, so the browser can supply values but never table names, column names or SQL. Stored
statements and files list the user roles that may use them, and statements run read-only.

It is not a general data API: it only runs actions written as WPI descriptors. Design:
devdoc `2026102601-devdoc-web-page-interpreter.md`; what was built: devdoc
`2026102603-devdoc-wpi-pilot.md`; formal requirements: OpenSpec changes `wpi-pilot`,
`wpi-classes-and-instances`, `wpi-pages` and `wpi-create-element-class`.

## 2. Files

| File | Purpose |
|---|---|
| `ChenWeb/server/api/wpi/types.go` | Kinds, descriptor format `0.2`, templates and layouters, bundle and action types |
| `ChenWeb/server/api/wpi/refs.go` | Reference parsing and rules; `$args` substitution |
| `ChenWeb/server/api/wpi/refs_test.go` | Tests for `refs.go` |
| `ChenWeb/server/api/wpi/validate.go` | What each class's code accepts (`elementAttrs`, `actionAttrs`, keyed by class ID); checks of one descriptor (`ValidateDescriptor`), class rows, instances against their class (`pageInstances`, `classDefaults`, `mergeInstance`); where action instances sit in a page (`actionPositions`); element class rows in format 0.3 (`elementClassAttrs`) and drafts (`ValidateDraftClass`) |
| `ChenWeb/server/api/wpi/validate_test.go` | Tests for `validate.go` |
| `ChenWeb/server/api/wpi/bundle.go` | Loads an app, the pages it reaches and all classes, and validates the whole set, including that named statements and files are stored (`BuildBundle`) |
| `ChenWeb/server/api/wpi/bundle_test.go` | Tests for `bundle.go` |
| `ChenWeb/server/api/wpi/catalog.go` | Table and column existence from `information_schema`; identifier quoting |
| `ChenWeb/server/api/wpi/catalog_test.go` | Tests for `catalog.go` |
| `ChenWeb/server/api/wpi/store.go` | Latest active descriptor lookup (pages from `kb.frontend_pages`, other kinds from `kb.wpi_descriptors`); inserting a new version; page summaries for search; stored statements and files; inserting an element class draft and listing element classes |
| `ChenWeb/server/api/wpi/store_test.go` | Tests for `store.go` |
| `ChenWeb/server/api/wpi/handler.go` | `Handler`, `New`; app bundle, descriptor write, page search and page read, element class create and list endpoints |
| `ChenWeb/server/api/wpi/handler_test.go` | Tests for `handler.go` |
| `ChenWeb/server/api/wpi/actions.go` | Action run endpoint: find the instance by page and pointer, merge it with its class, then load, save, query (read-only) or load-file, with the stored rows' access controls |
| `ChenWeb/server/api/wpi/actions_test.go` | Tests for `actions.go` |
| `ChenWeb/server/api/wpi/sqlbuild.go` | Pure SELECT / INSERT / UPDATE builders with quoted identifiers and parameters |
| `ChenWeb/server/api/wpi/sqlbuild_test.go` | Tests for `sqlbuild.go` and `rules.go` |
| `ChenWeb/server/api/wpi/rules.go` | Save rules: required, max_length, pattern, email format |
| `ChenWeb/server/api/wpi/stored_test.go` | Tests for `query`, `load-file`, access controls, page search and page read |
| `ChenWeb/server/api/wpi/seed_test.go` | Checks that the seeded classes and `customer-admin` app (both seeds) are valid |
| `ChenWeb/project_migrations/20261026000001_create_kb_wpi_descriptors.sql` | Table `kb.wpi_descriptors` |
| `ChenWeb/project_migrations/20261026000002_create_kb_wpi_demo_customers.sql` | Demo table `kb.wpi_demo_customers` |
| `ChenWeb/project_migrations/20261026000003_seed_wpi_customer_admin.sql` | Pilot demo app (format `0.1`; its stored elements and actions are retired) |
| `ChenWeb/project_migrations/20261027000002_seed_wpi_classes_and_instances.sql` | Element and action classes; demo app in format `0.2` |
| `ChenWeb/project_migrations/20261027000003_create_kb_frontend_pages.sql` | Table `kb.frontend_pages`; moves every page row out of `kb.wpi_descriptors` |
| `ChenWeb/project_migrations/20261027000004_create_kb_stored_stmts_and_files.sql` | Tables `kb.stored_stmts` and `kb.stored_files` |
| `ChenWeb/project_migrations/20261027000005_seed_wpi_pages_demo.sql` | `query` and `load-file` classes; demo statements and file; demo pages with names, static data, directory and About |
| `ChenWeb/project_migrations/20261027000006_wpi_element_classes_0_3.sql` | The six element classes again (version 2) in format `0.3`, with help tips in English and Chinese |

## 3. Interface

Routes (registered on the authenticated `/api/v1` group in `server/api/routes.go`):

| Method and path | Who | Request | Response |
| --- | --- | --- | --- |
| `GET /api/v1/wpi/apps/:appId` | logged-in | — | 200 `{app, pages, elements, actions, warnings}` (`elements` and `actions` are the classes the pages use); 404; 422 `{errors, warnings}` |
| `PUT /api/v1/wpi/descriptors/:kind/:descriptorId` | admin | descriptor JSON | 200 `{kind, descriptor_id, version}`; 400 `{errors}`; 403 |
| `POST /api/v1/wpi/actions/run` | logged-in | `{ref: {kind: "page", id, pointer}, args, input_doc}` | load, query, load-file 200 `{result}`; save 200 `{key_attribute, key_value}` or 422 `{field_errors}`; 400; 403 (stored row's roles); 404 |
| `GET /api/v1/wpi/pages?q=&limit=` | logged-in | — | 200 `{pages: [{descriptor_id, version, page_name, description, updated_at}]}`, matching ID, name or description in any language; 400 |
| `GET /api/v1/wpi/pages/:pageId` | logged-in | — | 200 `{version, page}` (newest active version); 404 |
| `POST /api/v1/wpi/classes/element` | admin | element class row (`descriptor_id`, `schema_version`, required `description`, attributes with defaults or `null`) | 201 `{descriptor_id, version: 1, status: "draft"}`; 400 `{errors}`; 403; 409 when any row of the class ID exists |
| `GET /api/v1/wpi/classes/element` | logged-in | — | 200 `{classes: [{descriptor_id, version, status, description, attributes}]}`: the latest draft or active version of each element class, by ID; `attributes` holds the row's instance attributes, each `{help_tip, default_value}` |

Go API: `wpi.New(db *sql.DB) *Handler` (methods `GetApp`, `PutDescriptor`, `RunAction`,
`SearchPages`, `GetPage`, `CreateElementClass`, `ListElementClasses`); `Handler{DB, User}`
with an injectable user lookup for tests; `ValidateDescriptor(kind, id, body) []Issue`;
`ValidateDraftClass(body) []Issue`; `BuildBundle(ctx, appID, Loader, Columns,
Registered) (*BundleResult, error)`, where a `Loader` called with `ids == nil` returns every
active descriptor of the kind and `Registered` says which stored statements or files exist.

## 4. Configuration

None. Fixed limits: list loads return 200 rows by default and at most 1000; a `query`
returns at most 1000 rows and runs at most 10 seconds; a page search returns 50 pages by
default and at most 200; request bodies are read up to 1 MiB.

## 5. Usage

Storing a new version of a page (admin session cookie required):

```bash
curl -X PUT http://localhost:8080/api/v1/wpi/descriptors/page/customers \
  -H 'Content-Type: application/json' --cookie "session_id=…" \
  -d '{"descriptor_id": "greeting", "schema_version": "0.2", "layouter": "flow-layouter",
       "elements": [{"element": "text", "text": "Hello"}]}'
```

Adding a class, for example `checkbox`: add its attributes to `elementAttrs` in
`validate.go` (or `actionAttrs` for an action), register its frontend code under the same
ID (module `20261026-01`), and store its class row (`PUT /api/v1/wpi/descriptors/element/checkbox`,
or a seed migration). An element class row is format `0.3`: each instance attribute is
`{"help_tip": …, "default_value": …}`, where `null` means every instance must set it and no
`default_value` means optional; an optional `implement_notes` holds the implementation
prompt. An action class row stays `0.2`, with the default or `null` itself. An element
class may be defined first as a draft, from the WPI editor's *Create Element* or with
`POST /api/v1/wpi/classes/element`; the PUT then makes it active once the code exists.

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
- Descriptor versions are append-only; the newest active version is used. Element class
  drafts are `draft` rows, never used by the interpreter.

## 7. Scope and limits

- Any logged-in user may run any `load`/`save` instance in a stored page, on any table
  (decided for the pilot); only admins write descriptors. `query` and `load-file` follow
  their stored row's `access_controls`.
- Stored statements and files have no write API and no versions.
- Only format `0.2` is accepted; descriptors written for `0.1` are rejected.
- Last save wins; no conflict detection.
- `where` supports equality only; no paging.
- Tests use `go-sqlmock`; none touch the `miner` database.
- Move to `shared/go` when a second project uses it.
