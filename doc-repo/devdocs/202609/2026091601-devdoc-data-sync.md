# Setting Up and Using ChenWeb Production Data Sync

**Date:** 2026-09-16
**Scope:** How to set up and use the "Sync Data" feature that lets a deployed ChenWeb
instance (the China box today, other customer boxes later) pull specific, registered
reference data from the dev Mac. This is the **setup + usage** doc — for the design
rationale and alternatives considered, see the OpenSpec change at
`ChenWeb/openspec/changes/production-data-sync/` (`proposal.md`, `design.md`,
`specs/production-data-sync/spec.md`). For starting/restarting the China box's other
services and general box facts, see `2026090701-devdoc-start-system-onto.md`. For
shipping a new `server-linux` binary (needed once, to get this feature onto the box at
all), see `2026091501-devdoc-deploy-chenweb-china-box.md`.

**Status as of 2026-09-16:** the code is implemented, unit- and integration-tested,
and builds cleanly for `linux/amd64` (see the OpenSpec change's `tasks.md`, items 1-6,
all checked off). **Mac side is now live:** the router forwards 80/443 to the Mac, Caddy
holds a Let's Encrypt cert for `macmini.deepdocs.me`, and the pull endpoint answers 200
over HTTPS (§1.2, §1.5). **Still to do: the China box's own `.env` (§1.4)** — it already
carries both vars, but `DATA_SYNC_SOURCE_URL` holds the retired
`https://dingbo.bzton.cn`, which now fails outright; the shared secret there is already
correct and needs no change. Verified 2026-09-16 that the box resolves
`macmini.deepdocs.me` and gets a 200 from the new endpoint in ~2s, so only the one line
and a `chenweb` restart remain. This doc is the runbook for finishing that, and for
using the feature once it's live.

**Naming note:** `mise.local.toml` on the Mac already has an unrelated `DATA_SYNC_CONFIG`
var (`~/.config/syncdata/config.toml`) for a separate personal Postgres backup/archive
tool (target `47.187.208.148`, nothing to do with ChenWeb — zero references to it
anywhere in `ChenWeb/`'s Go code). Don't confuse it with the `DATA_SYNC_SHARED_SECRET` /
`DATA_SYNC_SOURCE_URL` vars below; they're unrelated systems that happen to share a
prefix.

## How it works, briefly

- **Direction:** the deployed box always initiates the connection out to the Mac — never
  the reverse. This is deliberate: a future customer box may sit behind a firewall that
  allows outbound traffic but blocks inbound, so "the Mac reaches into the box" was never
  an option. The Mac's home router therefore needs a port-forward so the box can reach
  *it* (see §2.2) — this is the one piece that's specific to the Mac not having a public
  IP; a differently-hosted source wouldn't need it.
- **Sync items:** a small compiled-in registry (`ChenWeb/server/api/datasync/registry.go`)
  lists what can be synced. Today there is exactly one: `kb_product_names`, the NMPA
  medical-device classification catalog table. Adding a second item is "add a registry
  entry" — see §4.
- **Semantics:** incremental, upsert-only. A sync never deletes a row at the target, even
  if it was removed at the source. `kb_product_names` is further scoped to only the
  catalog-imported rows (`source = 'cn_nmpa_medical_device_classification_catalog'`) — a
  box's own locally-extracted `status='proposed'` rows are never touched by a sync.
- **Auth:** a shared-secret bearer token, checked with a constant-time comparison —
  the same pattern already used for the SMS courier relay
  (`shared/go/api/auth/sms_relay.go`) and the mitmproxy-ingest / agent-tools internal
  routes.

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

The two new goose migrations (`project_migrations/20260915000002_add_kb_set_update_time_trigger.sql`,
`.../20260915000003_create_kb_data_sync_state.sql`) run automatically at `chenweb`
startup on the box — **but only if the migration files actually reached the box.** Until
2026-09-16 `mise run build-server-linux` shipped binaries only, so a normal deploy left
`project_migrations/` frozen and goose had nothing to apply; the box sat 22 migrations
behind and `Sync Data` failed with
`pq: relation "kb.data_sync_state" does not exist (42P01)`. Both the build task and
`deploy-server-china.sh` now ship and sync migrations (see
`2026091501-devdoc-deploy-chenweb-china-box.md` §1 and §3). If you ever see a
`relation ... does not exist` at runtime, check the file count on the box against the
Mac before suspecting goose:
`ls ~/Workspace/ChenWeb/project_migrations/*.sql | wc -l`. Note the goose tracking table
is `project_db_migration` (`PG_MIGRATION_TNAME_PROJECT`), **not** `goose_db_version`.

### 1.2 Port-forward and TLS on the Mac's home router

The Mac (`192.168.29.170` on the LAN) has no public IP, so the China box can't reach it
without a forward. **Done 2026-09-16.** The resolved setup:

- Public **80 and 443 → `192.168.29.170`**. Caddy on the Mac terminates TLS and
  reverse-proxies to the dev server on `localhost:8080` (`ChenWeb/Caddyfile`, site
  `macmini.deepdocs.me`; `/kratos/*` → `localhost:4433`).
- DNS: `macmini.deepdocs.me` A → `47.189.245.217`. Caddy holds a production Let's Encrypt
  cert for it (first issued 2026-09-16, auto-renewing).
- The box's source URL is therefore just **`https://macmini.deepdocs.me`** — no port
  suffix.

**The earlier "forward 8055 → 8080" plan does not work — do not use it.** Port 8055
lands on the raw Go server, which speaks plain HTTP, so an `https://…:8055` source URL
fails with `http: server gave HTTP response to HTTPS client` on the box and
`wrong version number` from curl. The shared secret (§1.3) travels as a plain bearer
header, so the connection must be the Caddy-terminated 443 one. If the 8055 forward is
still open it is exposing the dev server in plaintext to the internet; close it.

**Getting the cert requires ports 80 and 443 specifically.** ACME validates HTTP-01 on
port 80 and TLS-ALPN-01 on port 443; both are fixed by the protocol and cannot be
remapped, so no high-port forward can ever satisfy a challenge. If a challenge lands on
some other host, that host's TLS stack answers with an `internal_error` alert and the
issuing side reports `remote error: tls: internal error` — which looks like a Caddy bug
but is purely a routing fact. (These ports previously forwarded to `plano96`,
`192.168.29.96`, which served `dingbo.bzton.cn`; repointing them to the Mac took that
site down and will break its cert renewal — deliberate, that name is retired.)

### 1.3 Mac-side (source) config

Add to `ChenWeb/mise.local.toml`'s `[env]` section, then restart `mise dev` (a plain
`Ctrl-C` + re-run in the terminal it's running in — this does interrupt the live dev
server, so pick a moment that doesn't clobber someone else's testing):

```toml
DATA_SYNC_SHARED_SECRET = "<a long random token — generate with `openssl rand -hex 32`>"
```

Without this set, the pull endpoint refuses every request with a 500 (fails closed, does
not silently allow unauthenticated access — see
`server/api/datasync/pull_handler.go`'s `HandlePullChanges`).

### 1.4 Box-side (target) config

On the China box, add to `~/Workspace/ChenWeb/.env` (same value as §1.3 for the secret;
**no quotes, no spaces around `=`** — see the box's env-var translation rules in
`2026090701-devdoc-start-system-onto.md`'s Environment-variables section):

```
DATA_SYNC_SHARED_SECRET=<same token as the Mac>
DATA_SYNC_SOURCE_URL=https://macmini.deepdocs.me
```

Then restart:

```bash
env LC_ALL=C LANG=C su -c 'systemctl restart chenweb'
```

### 1.5 Verify the wiring

From the box, confirm it can actually reach the Mac's pull endpoint (this is the
source-side route — no Kratos session needed, just the shared secret):

```bash
curl -s -H "Authorization: Bearer $DATA_SYNC_SHARED_SECRET" \
  "https://macmini.deepdocs.me/api/internal/data-sync/items/kb_product_names/changes?since=&limit=5"
```

Expect a JSON body shaped like:

```json
{"item_id":"kb_product_names","next_cursor":"2026-09-...","has_more":true,"rows":[...]}
```

A `401 {"error":"unauthorized"}` means the secret doesn't match on one side; a
`500 {"error":"data sync source is not configured"}` means `DATA_SYNC_SHARED_SECRET`
isn't set on the Mac; a connection failure/timeout means the port-forward (§1.2) isn't
actually working yet. `http: server gave HTTP response to HTTPS client` (or curl's
`wrong version number`) means the URL is pointing past Caddy at the raw Go server —
almost always a leftover `:8055` in `DATA_SYNC_SOURCE_URL`.

## 2. Using it (System Admin → Resources → Sync Data)

Log into the box as a sysadmin and go to **home3 → System Admin → Resources → Sync
Data** (`web/src/lib/components/home3/sync-data-view.svelte`, menu id
`sysadmin-resources-sync-data`, next to Videos / External Terminology Resources in the
same Resources submenu).

The page lists every registered sync item (today, just `kb_product_names`) with its last
sync time and row count. Per item:

- **Preview** — calls the Mac, reports how many rows have changed since this box's last
  successful sync. Read-only: no data is written, the stored cursor doesn't move.
- **Sync** — does the real thing: fetches the same changes and upserts them, then
  advances the stored cursor only if the whole run succeeds. If it fails partway (the
  Mac unreachable mid-run, a bad row, etc.), the cursor is left exactly where it was, so
  clicking Sync again safely retries from the same starting point — nothing is lost or
  double-applied.

There's no scheduling here — every sync is a manual button click. (`kb.schedules`, the
existing generic scheduled-job framework, is a plausible place to hook in an automatic
periodic sync later; nothing wires it up today.)

**What actually changes when you click Sync on `kb_product_names`:** rows in the box's
`kb.product_names` table whose natural key (`source, seq_no, product_name`) matches an
incoming row get updated in place (their local surrogate `id` is untouched); rows with a
natural key not yet present get inserted with a fresh local `id`. Nothing is ever
deleted. Only catalog rows are ever in scope — a box's own `extract_products`-sourced
`proposed` rows are structurally invisible to this sync (see registry `Filter`, §
"How it works" above) and are never touched either way.

## 3. Adding a new sync item

Edit `server/api/datasync/registry.go`'s `Registry` slice — one more `TableSyncItem`
literal:

```go
{
    ID:         "some_new_item",              // used in URLs and kb.data_sync_state
    Table:      "kb.some_table",
    CursorCol:  "update_time",                 // must be a TIMESTAMPTZ, bumped on every UPDATE
    NaturalKey: []string{"col_a", "col_b"},     // a real UNIQUE constraint on the table — never the surrogate id
    Columns:    []string{ /* every column to transfer, excluding id */ },
    JSONColumns: []string{ /* the subset that are jsonb */ },
    Filter:     "", // optional, raw SQL WHERE fragment scoping which rows this item ever touches
}
```

Two things every new item needs that aren't automatic:

1. **A working cursor.** `CursorCol` must actually be bumped on every `UPDATE`, not just
   default on `INSERT` — `kb.product_names.update_time` needed a new trigger for exactly
   this reason (`kb.set_update_time()`, attached in
   `project_migrations/20260915000002_...`). If the new table doesn't already have a
   reliably-maintained `update_time`-style column, add one (a migration attaching the
   same `kb.set_update_time()` trigger function — it's written to be reusable) before
   registering the item.
2. **A real natural key.** `NaturalKey` becomes the `ON CONFLICT` target — it must be
   backed by an actual `UNIQUE` constraint on the table, and must never be (or include)
   the table's surrogate `BIGSERIAL` id, since source and target databases generate that
   independently (see design.md Decision 2 for why this matters).

No route/registration/UI changes are needed beyond that — the pull handler, admin
handlers, and the Sync Data page all iterate the registry generically.

## 4. API reference

| Route | Side | Auth | Purpose |
|---|---|---|---|
| `GET /api/internal/data-sync/items/:itemId/changes?since=&limit=` | Source (Mac) | `Authorization: Bearer <DATA_SYNC_SHARED_SECRET>` | Rows of `itemId` changed since `since` (empty = everything). Returns `{item_id, next_cursor, has_more, rows}`. |
| `GET /api/v1/data-sync/items` | Target (box) | Kratos session | List registered items + last sync status. `{ok, items:[{item_id, table, last_synced_at, last_row_count, last_error}]}` |
| `POST /api/v1/data-sync/items/:itemId/preview` | Target (box) | Kratos session | Fetch-only; no writes. `{ok, item_id, changed_row_count}` |
| `POST /api/v1/data-sync/items/:itemId/apply` | Target (box) | Kratos session | Fetch + upsert + advance cursor on success. `{ok, item_id, synced_row_count}` |

The target routes are the same shape as the existing LLM-accounts `.models.toml` import
preview/apply pair (`llmadminhandler`) — same `{ok, message}` error envelope.

## 5. Troubleshooting

| Symptom | Check |
|---|---|
| Preview/Sync button shows "DATA_SYNC_SOURCE_URL and DATA_SYNC_SHARED_SECRET must both be set" | Box's `.env` is missing one; `chenweb` needs a restart after editing `.env`. |
| `502`/network error on Preview or Sync | Box can't reach the Mac — check the port-forward (§1.2) is actually live and the Mac's `mise dev` is running; try the §1.5 curl from the box directly. |
| Source returns `401 unauthorized` | Secret mismatch between the box's `.env` and the Mac's `mise.local.toml` — they must be byte-identical. |
| Source returns `500 data sync source is not configured` | `DATA_SYNC_SHARED_SECRET` isn't set on the Mac, or `mise dev` wasn't restarted after adding it. |
| Preview always shows 0 changed rows even though the Mac's catalog looks different | The natural key (`source, seq_no, product_name`) didn't change and neither did `update_time` — confirm the edit on the Mac actually went through an `UPDATE` (not a raw `id`-keyed patch that bypassed the trigger) and that `kb.set_update_time` trigger exists: `\d kb.product_names` on the Mac should show `trg_kb_product_names_set_update_time`. |
| Sync fails partway, "sync applied but failed to persist state" | The upsert itself succeeded but writing `kb.data_sync_state` failed (e.g. the box's DB briefly unavailable) — safe to just click Sync again; worst case it re-applies the same already-correct rows (upsert is idempotent). |
| A box's own locally-extracted product names look wrong after a sync | They shouldn't be touched at all — if they changed, check the registry's `Filter` for `kb_product_names` hasn't been edited to something broader than `source = 'cn_nmpa_medical_device_classification_catalog'`. |

## See also

- `ChenWeb/openspec/changes/production-data-sync/` — the full proposal/design/spec/tasks
  for this feature (design rationale, alternatives considered, risk analysis).
- `2026090701-devdoc-start-system-onto.md` — China box operations (starting/restarting
  services, box facts, env-var translation rules referenced in §1.4 above).
- `2026091501-devdoc-deploy-chenweb-china-box.md` — how to ship the `server-linux`
  binary this feature lives in.
