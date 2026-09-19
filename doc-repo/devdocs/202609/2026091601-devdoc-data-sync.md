# Setting Up and Using ChenWeb Data Sync

**Date:** 2026-09-16, rewritten 2026-09-17 as the source-of-truth doc for the whole feature.
**Scope:** How to set up and use the "Sync Data" feature that lets a deployed ChenWeb
instance (the China box today, other customer boxes later) pull specific, registered
data from another instance — reference tables (`kind: table`) and, as of 2026-09-17,
tables whose rows reference a file on disk (`kind: table_with_files`, e.g. `kb.videos`) —
and how an admin registers a new syncable item at runtime via the "New Data Syncher"
button instead of editing Go source. **This is the single source-of-truth document for
data sync as a whole** — setup, usage, the registry model, both item kinds,
troubleshooting. Look here first for any issue. For the *why* behind a specific design
choice, see the two OpenSpec changes instead of re-deriving it here:
`ChenWeb/openspec/changes/production-data-sync/` (the original table-only design) and
`ChenWeb/openspec/changes/configurable-data-sync-items/` (runtime-created items,
`table_with_files`, cross-instance discovery). For starting/restarting the China box's
other services and general box facts, see `2026090701-devdoc-start-system-onto.md`. For
shipping a new `server-linux` binary, see `2026091501-devdoc-deploy-chenweb-china-box.md`.

**Status as of 2026-09-17:** both changes are implemented, unit- and integration-tested,
and build cleanly for `linux/amd64` (`configurable-data-sync-items/tasks.md` items 1-5 and
7 all checked off). **Verified live against the running Mac dev instance** (not just
tests): the new discovery endpoint (`GET /api/internal/data-sync/items`) answers
correctly both on `localhost:8080` and over the public `https://macmini.deepdocs.me`
route, and the file-transfer endpoint's error paths (`400` for a non-file item, `404` for
an unknown item) behave as designed; the original `.../changes` endpoint is confirmed
unaffected by the refactor underneath it. `kb_videos` (registered as item id `video`) and
`kb.images` (item id `kb-images`) have both since been created via the New Data Syncher UI
on the Mac (source) as two independent `table_with_files` items — see §4.1 for a design
point specific to this pair: `kb.videos.image_uid` referencing `kb.images.uid` by natural
key rather than by `kb.images.id`. **Not yet done:**
- **Cross-machine Apply of `video`/`kb-images`** — verified so far via local-dev-DB
  integration tests (§4.1) and against the Mac's own discovery/file endpoints, but not yet
  a real Preview/Apply from another box pulling from the Mac.
- **The China box's own `.env`** (§1.4) — as of the previous revision of this doc,
  `DATA_SYNC_SOURCE_URL` there still held the retired `https://dingbo.bzton.cn`; confirm
  this is fixed before expecting the box to actually reach the Mac.

## How it works, briefly

- **Direction:** the deployed (target) box always initiates the connection out to the
  source — never the reverse. Deliberate: a customer box may sit behind a firewall that
  allows outbound but blocks inbound. The Mac's home router needs a port-forward so a box
  can reach *it* (§1.2) — specific to the Mac having no public IP.
- **Sync items come from two places**, unioned (a compiled id always wins a collision):
  1. A small compiled-in registry, `ChenWeb/server/api/datasync/registry.go`'s
     `Registry` slice — today just `kb_product_names`. Adding here means editing Go
     source and shipping a new binary; see §3.2.
  2. `kb.data_sync_items`, a table an admin can insert into at runtime via the **New Data
     Syncher** button on the Sync Data page — no redeploy. See §2 and §3.1.
- **Two kinds:**
  - `table` (the original, and still the only kind `kb_product_names` uses): plain
    row sync.
  - `table_with_files` (new): one column of each row holds a server-local file path.
    Applying such an item copies the referenced file to the target *before* upserting
    the row, and rewrites the row's file column to the file's new local path. See §4.
- **Semantics:** incremental, upsert-only, for both kinds. A sync never deletes a row at
  the target, even if it disappeared at the source — and, for `table_with_files`, never
  deletes or overwrites a previously-materialized file either, even if the source's file
  later changes (an accepted trade-off — see
  `configurable-data-sync-items/design.md`'s Risks section). `kb_product_names` is
  further scoped to only catalog-imported rows
  (`source = 'cn_nmpa_medical_device_classification_catalog'`) — a box's own
  locally-extracted `status='proposed'` rows are never touched.
- **Auth:** a shared-secret bearer token, constant-time compared — same pattern as the
  SMS courier relay (`shared/go/api/auth/sms_relay.go`) and the mitmproxy-ingest /
  agent-tools internal routes. All four internal (`/api/internal/data-sync/...`) routes
  use it; all five admin (`/api/v1/data-sync/...`) routes use the normal Kratos session
  instead (see §5).
- **Discovery:** a target doesn't need an admin to hand-type the same New Data Syncher
  form twice. Every time the Sync Data page's list loads, the target asks its configured
  source what it can offer (`GET /api/internal/data-sync/items`) and caches any item it
  learns about (`origin = learned`) into its own `kb.data_sync_items`. This is what makes
  an item created on the Mac actually usable on a box — see §3.1 and §6.

## 1. One-time setup

### 1.1 Ship the code

The Mac's `mise dev` (air) already picks this up automatically in dev. To get it onto
the China box, ship a normal `server-linux` build per
`2026091501-devdoc-deploy-chenweb-china-box.md` §1-3:

```bash
cd ~/Workspace/ChenWeb
BINS=server mise run build-server-linux
scp -P 8822 -r /tmp/chenweb-deploy gui@210.5.158.91:~/
ssh -p 8822 gui@210.5.158.91
su -
bash ~/chenweb-deploy/deploy-server-china.sh ~/chenweb-deploy server
```

Migrations run automatically at `chenweb` startup on the box — **but only if the
migration files actually reached the box.** `mise run build-server-linux` and
`deploy-server-china.sh` ship and sync `project_migrations/`; if you ever see a
`relation ... does not exist` at runtime, check the file count on the box against the
Mac: `ls ~/Workspace/ChenWeb/project_migrations/*.sql | wc -l`. The goose tracking table
is `project_db_migration` (`PG_MIGRATION_TNAME_PROJECT`), **not** `goose_db_version`.
The data-sync-relevant migrations, in order: `20260915000002_add_kb_set_update_time_trigger.sql`
(the reusable `kb.set_update_time()` trigger function),
`20260915000003_create_kb_data_sync_state.sql` (per-item cursor/run state),
`20260917000001_create_kb_data_sync_items.sql` (runtime-created item definitions),
`20260917000002_add_update_time_to_kb_videos.sql` (makes `kb.videos` syncable — see §6),
and `20260918000001_add_uid_to_kb_page_tables.sql` (adds portable UUID natural keys
to `kb.page_def` and `kb.page_config`).

### 1.2 Port-forward and TLS on the Mac's home router

The Mac (`192.168.29.170` on the LAN) has no public IP, so a box can't reach it without a
forward. **Done 2026-09-16**, unaffected by the 2026-09-17 change (new routes ride the
same Caddy/443 path as the existing ones):

- Public **80 and 443 → `192.168.29.170`**. Caddy on the Mac terminates TLS and
  reverse-proxies to the dev server on `localhost:8080` (`ChenWeb/Caddyfile`, site
  `macmini.deepdocs.me`; `/kratos/*` → `localhost:4433`).
- DNS: `macmini.deepdocs.me` A → `47.189.245.217`. Caddy holds a production Let's Encrypt
  cert for it (first issued 2026-09-16, auto-renewing).
- A box's source URL is therefore just **`https://macmini.deepdocs.me`** — no port
  suffix.

**The earlier "forward 8055 → 8080" plan does not work — do not use it.** Port 8055
lands on the raw Go server (plain HTTP), so an `https://…:8055` source URL fails with
`http: server gave HTTP response to HTTPS client` / curl's `wrong version number`. The
shared secret travels as a plain bearer header, so the connection must be the
Caddy-terminated 443 one. If an 8055 forward is still open it's exposing the dev server
in plaintext to the internet — close it.

**Getting the cert requires ports 80 and 443 specifically** (ACME's HTTP-01 / TLS-ALPN-01
challenges are fixed to those ports by protocol). (These ports previously forwarded to
`plano96`, which served the now-retired `dingbo.bzton.cn`.)

### 1.3 Mac-side (source) config

**As actually configured on this Mac (verified 2026-09-17):** `DATA_SYNC_SHARED_SECRET`
and `DATA_SYNC_SOURCE_URL` live in `ChenWeb/.env` (there's a
`.env.bak-datasync-20260916` alongside it from when this was set up), **not**
`mise.local.toml` as an earlier draft of this doc assumed. Either location actually
works — `server/cmd/deepdoc/main.go` calls `godotenv.Load("./.env")` directly at process
startup, independent of `mise`'s own env resolution, so a var can come from either
mechanism and `os.Getenv` sees it either way. What matters is that *some* mechanism sets
it before the process starts; right now that's `.env`. To (re)generate a secret:

```
DATA_SYNC_SHARED_SECRET=<a long random token — generate with `openssl rand -hex 32`>
```

Restart `mise dev` after changing it (`Ctrl-C` + re-run in the terminal it's running in —
this interrupts the live dev server, so pick a moment that doesn't clobber someone else's
testing). Without this set, the pull endpoints refuse every request with a `500` (fails
closed — see `server/api/datasync/pull_handler.go`'s `authenticatePullRequest`, shared by
all four `/api/internal/data-sync/...` handlers as of 2026-09-17; it used to be inlined
just in `HandlePullChanges`).

This Mac's `.env` also happens to set `DATA_SYNC_SOURCE_URL=https://macmini.deepdocs.me`
— i.e. it points itself at itself over the public route. That's a deliberate local
verification setup (§1.5's curl and this doc's live smoke tests both rely on it), not
something every source needs; a pure source with no upstream of its own can leave
`DATA_SYNC_SOURCE_URL` unset (Preview/Sync will just report the "must both be set" error
if attempted there, same as always — see §5).

**Naming note:** `mise.local.toml`'s unrelated `DATA_SYNC_CONFIG` var
(`~/.config/syncdata/config.toml`) is for a separate personal Postgres backup tool,
nothing to do with ChenWeb — don't confuse it with the vars above.

### 1.4 Box-side (target) config

On a deployed box, add to `~/Workspace/ChenWeb/.env` (same secret value as §1.3; **no
quotes, no spaces around `=`** — see the box's env-var translation rules in
`2026090701-devdoc-start-system-onto.md`):

```
DATA_SYNC_SHARED_SECRET=<same token as the Mac>
DATA_SYNC_SOURCE_URL=https://macmini.deepdocs.me
```

Then restart:

```bash
env LC_ALL=C LANG=C su -c 'systemctl restart chenweb'
```

### 1.5 Verify the wiring

From the box (or, to reproduce this doc's own 2026-09-17 verification, from the Mac
itself against its own public route — see §1.3):

```bash
curl -s -H "Authorization: Bearer $DATA_SYNC_SHARED_SECRET" \
  "https://macmini.deepdocs.me/api/internal/data-sync/items/kb_product_names/changes?since=&limit=5"

# New as of 2026-09-17 — confirms discovery is wired up too:
curl -s -H "Authorization: Bearer $DATA_SYNC_SHARED_SECRET" \
  "https://macmini.deepdocs.me/api/internal/data-sync/items"
```

Expect, respectively:

```json
{"item_id":"kb_product_names","next_cursor":"2026-09-...","has_more":true,"rows":[...]}
```
```json
{"items":[{"id":"kb_product_names","kind":"table","table":"kb.product_names", ...}]}
```

A `401 {"error":"unauthorized"}` means the secret doesn't match on one side; a
`500 {"error":"data sync source is not configured"}` means `DATA_SYNC_SHARED_SECRET`
isn't set on the source; a connection failure/timeout means the port-forward (§1.2)
isn't actually working; `http: server gave HTTP response to HTTPS client` (or curl's
`wrong version number`) means the URL is pointing past Caddy at the raw Go server —
almost always a leftover `:8055` in `DATA_SYNC_SOURCE_URL`.

## 2. Using it (System Admin → Resources → Sync Data)

Log into an instance as a sysadmin and go to **home3 → System Admin → Resources → Sync
Data** (`web/src/lib/components/home3/sync-data-view.svelte`, menu id
`sysadmin-resources-sync-data`, next to Videos / External Terminology Resources).

The page lists every item this instance knows about — compiled, `local` (created here),
and `learned` (cached from its configured source) — with kind, origin, last-sync time,
and row count. Per item:

- **Preview** — calls the source, reports how many rows have changed since this
  instance's last successful sync. Read-only.
- **Sync** — fetches the same changes and upserts them (for `table_with_files`, also
  copies each row's file first — see §4), then advances the stored cursor only on full
  success. A partial failure leaves the cursor untouched, so clicking Sync again safely
  retries from the same starting point.
- **New Data Syncher** (toolbar button) — opens a form to register a new item: kind
  (`table` / `table_with_files`), table, cursor column, natural key, columns, optional
  filter, and — for `table_with_files` — the file column plus where to store synced
  files locally (an env var name, a default subdirectory under `DATA_HOME_DIR`, or
  both). Submitting creates an `origin = local` item, usable immediately.
- **Edit** (row action, `local` items only) — reopens the same form, pre-filled.
  Submitting replaces the item's shape **and resets its stored sync state**, so the next
  sync starts fresh rather than risking a stale cursor against a changed shape. Not
  offered for `learned` or compiled items (see §3.1).
- **Delete** (row action, `local` and `learned` items) — removes the item definition and
  its stored sync state. For a `learned` item this only clears the local cache row; it
  reappears on the next list refresh if the source still offers it, and stays gone if the
  source doesn't. Not offered for compiled items.

There's no scheduling — every sync is a manual button click (`kb.schedules` is a
plausible future hook; nothing wires it up today).

**What actually changes when you click Sync:** for a `table` item, rows at the target
whose natural key matches an incoming row get updated in place (local surrogate `id`
untouched); a natural key not yet present gets inserted with a fresh local `id`. Nothing
is ever deleted. For a `table_with_files` item, the same row-level rule applies, plus:
the row's file column is rewritten to a fresh local path before the upsert happens (§4).

## 3. Registry model: compiled, local, and learned items

Every item has an **origin** that governs what you can do with it:

| Origin | What it means | Create | Edit | Delete | Preview / Sync |
|---|---|---|---|---|---|
| **compiled** | A literal in `registry.go`'s `Registry` slice | — (edit source, redeploy) | No — edit source, redeploy | No | Yes |
| **local** | Created on *this* instance via New Data Syncher | Via the button | Yes (resets sync state) | Yes (also clears sync state) | Yes |
| **learned** | Cached from this instance's configured source via discovery | — (only discovery creates these) | No — shape is owned by the source | Yes (clears the local cache only) | Yes |

`ItemByID`/list lookups check the compiled `Registry` first, then `kb.data_sync_items`
— a compiled id can never be shadowed by a bad DB row. Discovery
(`fetchSourceItemDefinitions` in `client.go`, called from `HandleListSyncItems` on every
list-page load) upserts what it learns as `origin = learned`, but a matching `local` row
always wins and is left untouched — you can never accidentally have your own
hand-authored item overwritten by whatever a source happens to advertise under the same
id.

### 3.1 Adding a new item via the UI (recommended)

Click **New Data Syncher** on the Sync Data page (§2) and fill in the form. This is now
the normal path — no code change, no redeploy, usable the moment you submit it. As of
2026-09-17 the form is picker-driven, backed by live schema introspection
(`server/api/datasync/schema_introspect.go`), not free text:

- **Schema** and **Table** are two cascading dropdowns (every non-system schema's base
  tables), not text fields — you can't type a table that doesn't exist.
- **Columns** isn't a field at all. The syncher always copies every column of the
  selected table (minus the surrogate primary key) — the server derives this itself from
  the table's real shape at create/edit time, every time, so it's always current even if
  the table gains a column later via an unrelated migration.
- **Cursor Column** is a dropdown listing the selected table's real columns (with their
  Postgres type shown). **This is not a row filter** — it's the "changed since last
  sync" tracking column the incremental engine relies on; the server rejects any column
  whose type isn't `timestamp`/`timestamptz`. It does *not* verify a trigger actually
  bumps it on `UPDATE` (that can't be introspected reliably) — pick a column you know is
  trigger-maintained (e.g. `kb.videos` has both `created_at`, insert-only, and
  `update_time`, trigger-maintained; only the latter works as a cursor).
- **Natural Key** is a dropdown of the table's `UNIQUE` constraints, **excluding the
  primary key** — never offered, on purpose. Syncing by the primary key would corrupt
  data: source and target each generate their own surrogate id independently, so the
  same real-world row gets a different id on each side. Auto-selected when the table has
  exactly one eligible constraint (true for both `kb_product_names` and `kb_videos`); if
  a table has none yet, the picker says so — add a `UNIQUE` constraint via a migration
  first.
- **File Column** (`table_with_files` only) is the same column dropdown as Cursor
  Column.
- **JSON Columns** isn't a field either — auto-derived from which of the copied columns
  are Postgres `jsonb` type.
- **Filter** is the one field that's still free text, because it's the one field that
  actually *does* select which records sync (a raw SQL `WHERE` fragment) — it lives
  under the collapsed **Advanced** section since most items don't need it.

The server re-validates all of this itself even though the UI already constrains it
(cursor column must exist and be a timestamp type; natural key must exactly match a real
non-PK unique constraint; file column must exist) — a direct API call bypassing the UI
gets the same guarantees.

For `table_with_files`, additionally: at least one of the **File Dir Env Var** / **File
Dir Default Subdirectory** fields must be set (§4 explains how they resolve) — these
stay free text since there's nothing in the database to introspect for them.

### 3.2 Adding a new item to the compiled registry (still supported)

Still the right choice for an item you want guaranteed present on every instance with
zero DB dependency, the way `kb_product_names` is. Edit
`server/api/datasync/registry.go`'s `Registry` slice:

```go
{
    ID:         "some_new_item",              // used in URLs and kb.data_sync_state
    Table:      "kb.some_table",
    CursorCol:  "update_time",                 // must be a TIMESTAMPTZ, bumped on every UPDATE
    NaturalKey: []string{"col_a", "col_b"},     // a real UNIQUE constraint — never the surrogate id
    Columns:    []string{ /* every column to transfer, excluding id */ },
    JSONColumns: []string{ /* the subset that are jsonb */ },
    Filter:     "", // optional, raw SQL WHERE fragment scoping which rows this item ever touches
    Kind:       datasync.KindTable, // or KindTableWithFiles -- zero value behaves as KindTable
}
```

No route/registration/UI changes are needed beyond that — the pull handler, admin
handlers, and the Sync Data page all iterate the combined (compiled ∪ DB) registry
generically.

### 3.3 kb.videos's migration

`kb.videos` had neither a working cursor nor a real natural key before 2026-09-17 (only
insert-time `created_at`, and no `UNIQUE` besides the surrogate `id`).
`20260917000002_add_update_time_to_kb_videos.sql` adds `update_time` (backfilled from
`created_at`, then the `kb.set_update_time()` trigger attached) and
`UNIQUE (stored_path)` — safe without a backfill conflict since `UploadVideo` already
names each file `<UnixNano>_<sanitized-filename>`, unique by construction. This migration
is applied; the `kb_videos` item itself still needs to be created via §2/§3.1 — see §6.

## 4. How `table_with_files` works

One column of each row (the **file column**) holds a path that's only meaningful on
whichever instance currently acts as source. Applying such an item:

1. Fetches the page of changed rows the usual way (`.../changes`).
2. For each row with a non-empty file column, fetches that row's file from the source —
   **by natural key, never by the row's raw path** (`GET
   /api/internal/data-sync/items/:itemId/files?key=<JSON array, natural-key order>`).
   The source re-derives the actual path itself via a `SELECT <file_column> FROM <table>
   WHERE ... AND (<natural key>) = (...)` — it never trusts a client-supplied filesystem
   path, which would otherwise let a target probe or read an arbitrary path on the
   source.
3. Saves the bytes locally under the item's **resolved storage directory**: the env var
   named by `FileDirEnv` if set and non-empty, else `<DATA_HOME_DIR>/<FileDirDefaultSubdir>`
   (mirrors `videohandler.videoDir()`'s own resolution order) — a fresh unique filename,
   `<UnixNano>_<sanitized-basename>`, matching `UploadVideo`'s own naming pattern.
4. Rewrites the row's file column to that new local path.
5. Only then upserts the row (steps 3-4 happen for every file-bearing row in the page
   before the batch upsert in step 5 — see `materializeFiles` in `server/api/datasync/files.go`).

A row with an empty/null file column is upserted without any file fetch. If the source's
database row exists but the file is missing on disk, the whole apply run fails for that
item (row not upserted, cursor not advanced) — same "safe to just click Sync again"
property as any other apply failure.

**Files are never deleted or overwritten in place by a sync**, matching the existing
"never delete a row" rule extended to files — if a source's file changes (same row,
different bytes) or a row's file column changes to point elsewhere, the old target-local
file is simply orphaned, not cleaned up. Accepted trade-off, not solved yet
(`configurable-data-sync-items/design.md` Risks).

### 4.1 A row that references another synced table's row: natural key, never surrogate id

`kb.videos` and `kb.images` are two *independent* `table_with_files` items (`video` and
`kb-images`). `kb.videos` also carries a cover-image reference — originally
`image_id BIGINT`, a plain (non-key) column holding `kb.images.id`. That looked harmless,
but it broke silently the same way a `NaturalKey` built from a surrogate id would: source
and target `BIGSERIAL` sequences are assigned independently, so a raw copy of `image_id`
has no relationship to the correct row in the target's `kb.images` — it points at the
wrong row, or none.

The fix (`configurable-data-sync-items/design.md` Decision 8, 2026-09-17) is **not** a
second file column or a new kind — the image's bytes were never the problem, the surrogate
id was. `kb.images` gained a stable `uid UUID DEFAULT gen_random_uuid() UNIQUE`, assigned
once at creation and never touched by `materializeFiles` (which only ever rewrites the
item's `FileColumn`, i.e. `stored_path` — and `stored_path` itself is *not* stable across
a sync, since every target mints a fresh `<UnixNano>_<name>` path when it saves the file,
which is exactly why `stored_path` couldn't be reused as this cross-reference either).
`kb.videos.image_id` was replaced with `image_uid UUID`, a plain data column holding a
copy of the referenced `kb.images.uid` — ordinary `Columns` data, not a `FileColumn`,
needing zero changes to `datasync` itself. `kb-images`'s own `NaturalKey` moved from
`stored_path` to `uid` to match. Like `image_id` before it, `image_uid` carries no SQL
`REFERENCES` constraint — a soft reference by convention only, same as before.

**The rule this generalizes:** if a `table_with_files` (or plain `table`) row needs to
point at a row in another independently-synced table, that pointer must be the other
table's stable natural key, never its surrogate `id` — and if that other table is itself
`table_with_files`, its natural key must be a column `materializeFiles` never rewrites
(i.e. not its own `FileColumn`).

**Sync-order caveat:** if `video` is applied before `kb-images`, `image_uid` on the target
briefly names a `uid` not yet present in the target's `kb.images` — no error (no FK
constraint enforces it), same "soft reference, cover shows a placeholder" tolerance the
column always had, just self-healing once `kb-images` next syncs instead of being
permanently wrong. Verified with two `TEST_DATABASE_URL`-guarded integration tests,
`server/api/datasync/cross_reference_integration_test.go`:
`TestVideoImageUIDCrossReferenceSurvivesIndependentSync` (apply images then videos; the
video's `image_uid` resolves to a real, freshly-materialized target `kb.images` row) and
`TestVideoImageUIDDanglesWithoutErrorWhenAppliedOutOfOrder` (apply videos first — dangling
reference, no error — then images, and confirm it self-heals).

## 5. API reference

| Route | Side | Auth | Purpose |
|---|---|---|---|
| `GET /api/internal/data-sync/items/:itemId/changes?since=&limit=` | Source | Shared secret | Rows of `itemId` changed since `since`. `{item_id, next_cursor, has_more, rows}`. |
| `GET /api/internal/data-sync/items/:itemId/files?key=` | Source | Shared secret | Streams the file for one row of a `table_with_files` item, identified by natural key (JSON array, in `NaturalKey` order). *(New 2026-09-17.)* |
| `GET /api/internal/data-sync/items` | Source | Shared secret | Every item this instance can serve (compiled ∪ its own `kb.data_sync_items`), for discovery. `{items:[...]}`. *(New 2026-09-17.)* |
| `GET /api/v1/data-sync/items` | Target | Kratos session | List known items + last sync status; also triggers a discovery refresh (best-effort). `{ok, items:[{item_id, table, kind, origin, cursor_col, natural_key, columns, json_columns, filter, file_column, file_dir_env, file_dir_default_subdir, last_synced_at, last_row_count, last_error}]}` |
| `GET /api/v1/data-sync/schema/tables` | Target | Kratos session | Every base table in every non-system schema, for the New Data Syncher form's Schema/Table pickers. `{ok, tables:[{schema, table}]}`. *(New 2026-09-17.)* |
| `GET /api/v1/data-sync/schema/tables/:schema/:table` | Target | Kratos session | Columns (name+type), primary key, non-PK unique-constraint candidates, and jsonb columns for one table — backs the Cursor Column/Natural Key/File Column pickers. `{ok, info:{columns, primary_key, natural_key_candidates, json_columns}}`. *(New 2026-09-17.)* |
| `POST /api/v1/data-sync/items` | Target | Kratos session | Create a `local` item. Body: `{id, kind, table, cursor_col, natural_key, filter, file_column, file_dir_env, file_dir_default_subdir}` — **no `columns`/`json_columns`**, the server always derives those from live introspection of `table` (`resolveItemShape` in `admin_handler_items.go`), and validates `cursor_col` is a real timestamp column and `natural_key` exactly matches a real non-PK unique constraint. *(New 2026-09-17; body shape changed same-day to drop columns/json_columns.)* |
| `PUT /api/v1/data-sync/items/:itemId` | Target | Kratos session | Edit a `local` item (same body/derivation as create); resets its sync state. Rejected for compiled/`learned` items. *(New 2026-09-17.)* |
| `DELETE /api/v1/data-sync/items/:itemId` | Target | Kratos session | Delete a `local` or `learned` item + its sync state. Rejected for compiled items. *(New 2026-09-17.)* |
| `POST /api/v1/data-sync/items/:itemId/preview` | Target | Kratos session | Fetch-only; no writes. `{ok, item_id, changed_row_count}` |
| `POST /api/v1/data-sync/items/:itemId/apply` | Target | Kratos session | Fetch + (for `table_with_files`) materialize files + upsert + advance cursor on success. `{ok, item_id, synced_row_count}` |

The `/api/v1/...` routes use the same `{ok, message}` error envelope as the existing
LLM-accounts `.models.toml` import preview/apply pair.

## 6. Registering kb_videos (the table_with_files proof item)

Done, on the Mac (source), via **New Data Syncher** (§2): id `video`, Schema `kb`, Table
`videos`, Kind `table_with_files`; Cursor Column `update_time` (**not** `created_at` —
both are timestamp-typed and both appear in the dropdown, but only `update_time` is
trigger-maintained, see §3.1); Natural Key `stored_path` (the table's only non-PK unique
constraint); File Column `stored_path`; File Dir Env Var `VIDEO_DIR`. Filter left empty —
sync every row, nothing to scope out unlike `kb_product_names`.

`kb.images` was likewise registered as item id `kb-images` (Table `images`, Cursor Column
`created_at` — images are never edited after upload, see
`20260917000003_add_unique_stored_path_to_kb_images.sql` — Natural Key `uid`, File Column
`stored_path`, File Dir Env Var `IMAGE_DIR`), needed because `kb.videos` rows reference a
cover image (`image_uid`) — see §4.1 for why that reference needed its own migration
(`kb.images.uid`) and isn't just "one more file column" on `video`.

After creating both on the Mac (source), a box configured with `DATA_SYNC_SOURCE_URL`
pointed at the Mac will pick them up on its next Sync Data list refresh via discovery
(§3) — no need to also create them on the box. Cross-machine Preview/Apply of either item
hasn't been exercised yet against a real second box (Status above) — only against local
scratch tables (§4.1's integration tests) and the Mac's own discovery/file endpoints.

## 7. Troubleshooting

| Symptom | Check |
|---|---|
| Preview/Sync button shows "DATA_SYNC_SOURCE_URL and DATA_SYNC_SHARED_SECRET must both be set" | This instance's config (§1.3/§1.4) is missing one; restart after fixing. |
| `502`/network error on Preview or Sync | Target can't reach the source — check the port-forward (§1.2) is live and the source's `mise dev`/`chenweb` is running; try the §1.5 curl directly. |
| Source returns `401 unauthorized` | Secret mismatch between target and source config — must be byte-identical. |
| Source returns `500 data sync source is not configured` | `DATA_SYNC_SHARED_SECRET` isn't set on the source. |
| Preview always shows 0 changed rows even though the source's data looks different | The natural key didn't change and neither did the cursor column — confirm the edit went through an `UPDATE` (not a raw `id`-keyed patch bypassing the trigger) and that the `kb.set_update_time` trigger exists on the table (`\d <table>` on the source). |
| Sync fails partway, "sync applied but failed to persist state" | The upsert (and, for `table_with_files`, file copy) succeeded but writing `kb.data_sync_state` failed — safe to click Sync again; worst case it re-applies already-correct data (idempotent). |
| A target's own locally-extracted rows look wrong after a sync | They shouldn't be touched — check the item's `Filter` hasn't been broadened (for `kb_product_names`, it must stay exactly `source = 'cn_nmpa_medical_device_classification_catalog'`). |
| New Data Syncher submission rejected with a validation error | Table must be `schema.table`; `table_with_files` needs a file column and at least one of file-dir-env/file-dir-default-subdir set (§3.1). |
| "cursor column ... must be a timestamp column (found type ...)" | You picked a non-timestamp column as Cursor Column — pick one whose type shown in the dropdown is `timestamp with time zone` or `timestamp without time zone`. |
| "natural key ... does not match any unique constraint on ... other than its primary key" | Either the picker showed "no eligible unique constraint" (add one via a migration first — §3.1), or this came from a direct API call bypassing the picker with a column set that isn't actually backed by a `UNIQUE` constraint. |
| "this is a compiled sync item; edit registry.go and redeploy instead" | You tried to Edit or Delete a compiled item (e.g. `kb_product_names`) — not supported; see §3.2 instead. |
| "this item's shape is owned by the source that advertised it" | You tried to Edit a `learned` item — not supported; Delete it instead if you want it gone (§2), or edit it on the source that actually owns it. |
| File endpoint returns "sync item is not a table_with_files kind" | You're hitting `.../files` for a plain `table` item — only `table_with_files` items have files to fetch. |
| `table_with_files` apply fails with a file-fetch error | The source's row exists but its file is missing on disk there, or the source is unreachable mid-run — same retry-safety as any other apply failure (cursor untouched). |
| A learned item never appears on a target's Sync Data list | The target's configured source must actually be reachable *at least once* for that item to be learned in the first place (discovery is best-effort per list load, not push-based) — check §1.5's discovery curl succeeds from the target. |
| A synced video's cover image is missing/placeholder on the target | Either `kb-images` hasn't been synced to that target yet (`image_uid` is currently dangling — sync `kb-images`, then re-check; no re-sync of `video` itself is needed, see §4.1), or the source video's `image_id`/`image_uid` predates the 2026-09-17 migration and was never backfilled. |

## See also

- `ChenWeb/openspec/changes/production-data-sync/` — original proposal/design/spec/tasks
  (table-only sync, the compiled registry, the pull/preview/apply pipeline).
- `ChenWeb/openspec/changes/configurable-data-sync-items/` — proposal/design/spec/tasks
  for everything added 2026-09-17 (runtime-created items, `table_with_files`,
  cross-instance discovery, edit/delete).
- `2026090701-devdoc-start-system-onto.md` — China box operations (starting/restarting
  services, box facts, env-var translation rules referenced in §1.4).
- `2026091501-devdoc-deploy-chenweb-china-box.md` — how to ship the `server-linux`
  binary this feature lives in.
