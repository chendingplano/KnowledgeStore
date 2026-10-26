# Module: Web Page Interpreter (backend)

**Module ID:** `20261026-02`
**Type:** backend · **Language:** go · **Version:** 1.0.0
**Status:** under-dev — pilot; serves the WPI frontend (module `20261026-01`)
**Project:** ChenWeb (server)
**Location:** `ChenWeb/server/api/wpi`
**Created:** 2026-10-26

## 1. What it is

The server half of the Web Page Interpreter (WPI). It keeps the descriptors that describe
WPI apps in the database, checks them, hands the browser an app together with everything
the app uses, and runs the two actions that touch data: loading records and saving them.

Checking happens before anything is shown: missing pages or elements, panes that the app's
layout does not have, tables or columns that do not exist, unsafe binding paths and
unsupported types are all reported, with the descriptor and the place inside it. Loading and
saving run only actions taken from stored descriptors, so the browser can supply values but
never table or column names.

It is not a general data API: it only runs actions written as WPI descriptors. Design:
devdoc `2026102601-devdoc-web-page-interpreter.md`; what was built: devdoc
`2026102603-devdoc-wpi-pilot.md`; formal requirements: OpenSpec change `wpi-pilot`.

## 2. Files

| File | Purpose |
|---|---|
| `ChenWeb/server/api/wpi/types.go` | Kinds, supported templates/layouters/element and action types, bundle and action types |
| `ChenWeb/server/api/wpi/refs.go` | Reference parsing and rules; `$args` substitution |
| `ChenWeb/server/api/wpi/refs_test.go` | Tests for `refs.go` |
| `ChenWeb/server/api/wpi/validate.go` | Structure and capability check of one descriptor (`ValidateDescriptor`) |
| `ChenWeb/server/api/wpi/validate_test.go` | Tests for `validate.go` |
| `ChenWeb/server/api/wpi/bundle.go` | Walks everything an app reaches and validates the whole set (`BuildBundle`) |
| `ChenWeb/server/api/wpi/bundle_test.go` | Tests for `bundle.go` |
| `ChenWeb/server/api/wpi/catalog.go` | Table and column existence from `information_schema`; identifier quoting |
| `ChenWeb/server/api/wpi/catalog_test.go` | Tests for `catalog.go` |
| `ChenWeb/server/api/wpi/store.go` | Latest active descriptor lookup; inserting a new version |
| `ChenWeb/server/api/wpi/store_test.go` | Tests for `store.go` |
| `ChenWeb/server/api/wpi/handler.go` | `Handler`, `New`; app bundle and descriptor write endpoints |
| `ChenWeb/server/api/wpi/handler_test.go` | Tests for `handler.go` |
| `ChenWeb/server/api/wpi/actions.go` | Action run endpoint: resolve stored action, load, save, JSON Pointer |
| `ChenWeb/server/api/wpi/actions_test.go` | Tests for `actions.go` |
| `ChenWeb/server/api/wpi/sqlbuild.go` | Pure SELECT / INSERT / UPDATE builders with quoted identifiers and parameters |
| `ChenWeb/server/api/wpi/sqlbuild_test.go` | Tests for `sqlbuild.go` and `rules.go` |
| `ChenWeb/server/api/wpi/rules.go` | Save rules: required, max_length, pattern, email format |
| `ChenWeb/server/api/wpi/seed_test.go` | Checks that the seeded `customer-admin` app is valid |
| `ChenWeb/project_migrations/20261026000001_create_kb_wpi_descriptors.sql` | Table `kb.wpi_descriptors` |
| `ChenWeb/project_migrations/20261026000002_create_kb_wpi_demo_customers.sql` | Demo table `kb.wpi_demo_customers` |
| `ChenWeb/project_migrations/20261026000003_seed_wpi_customer_admin.sql` | Demo app descriptors |

## 3. Interface

Routes (registered on the authenticated `/api/v1` group in `server/api/routes.go`):

| Method and path | Who | Request | Response |
| --- | --- | --- | --- |
| `GET /api/v1/wpi/apps/:appId` | logged-in | — | 200 `{app, pages, elements, actions, warnings}`; 404; 422 `{errors, warnings}` |
| `PUT /api/v1/wpi/descriptors/:kind/:descriptorId` | admin | descriptor JSON | 200 `{kind, descriptor_id, version}`; 400 `{errors}`; 403 |
| `POST /api/v1/wpi/actions/run` | logged-in | `{ref: {kind, id, pointer?}, args, input_doc}` | load 200 `{result}`; save 200 `{key_attribute, key_value}` or 422 `{field_errors}`; 400; 404 |

Go API: `wpi.New(db *sql.DB) *Handler` (methods `GetApp`, `PutDescriptor`, `RunAction`);
`Handler{DB, User}` with an injectable user lookup for tests; `ValidateDescriptor(kind, id,
body) []Issue`; `BuildBundle(ctx, appID, Loader, Columns) (*BundleResult, error)`.

## 4. Configuration

None. Fixed limits: list loads return 200 rows by default and at most 1000; request bodies
are read up to 1 MiB.

## 5. Usage

Storing a new version of a page (admin session cookie required):

```bash
curl -X PUT http://localhost:8080/api/v1/wpi/descriptors/page/customers \
  -H 'Content-Type: application/json' --cookie "session_id=…" \
  -d '{"descriptor_id": "customers", "schema_version": "0.1", "layouter": "flow-layouter",
       "refresh": {"on_show": true}, "elements": [{"element": "customer-list"}]}'
```

Registering the routes in another Echo group:

```go
h := wpi.New(ApiTypes.ProjectDBHandle)
group.GET("/wpi/apps/:appId", h.GetApp)
group.PUT("/wpi/descriptors/:kind/:descriptorId", h.PutDescriptor)
group.POST("/wpi/actions/run", h.RunAction)
```

## 6. Behaviour and conventions

- Every request is logged with `CreateDefaultLogger`; every action run logs the action
  reference, user, table, mode, row count and duration.
- Values always go to PostgreSQL as parameters; table and column names are checked against
  the catalog and quoted. Request numbers are kept as text so PostgreSQL converts them to
  the column type.
- Error messages returned to the browser never contain database internals; database
  rejections of a value become 400 "The database rejected the values".
- Descriptor versions are append-only; the newest active version is used.

## 7. Scope and limits

- Any logged-in user may run any stored `load`/`save`, on any table (decided for the pilot);
  only admins write descriptors.
- Last save wins; no conflict detection.
- `where` supports equality only; no paging.
- Tests use `go-sqlmock`; none touch the `miner` database.
- Move to `shared/go` when a second project uses it.
