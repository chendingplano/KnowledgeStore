# Starting the ChenWeb System on the onto.bzton.cn Production Box

**Date:** 2026-09-07 (rev 2026-09-08: renamed `dingbo.bzton.cn` → `https://onto.bzton.cn`,
added TLS + the `/kratos/` reverse-proxy + the Environment-variables section;
rev 2026-09-11: added §2.1 Chinese cell-phone sign-in, key-based root access, and the
`mise build-server-linux` / `deploy-server-china.sh` deploy path)
**Scope:** How to start each component of the ChenWeb stack on the China production box
`210.5.158.91` (`rssvr19`, colloquially "the dingbo box"), which now serves
**`https://onto.bzton.cn`**. This is the **operations** counterpart to the build/deploy
runbooks — it does not cover building or shipping code (see
`2026072401-devdoc-deploy-production.md` and `2026073001-devdoc-deploy-production-china-dingbo.md`).

## Box facts you need before touching anything

- **Access:** `ssh -p 8822 gui@210.5.158.91`. The maintainer's key is installed in
  **both `~gui/.ssh/authorized_keys` and `/root/.ssh/authorized_keys`**, and
  `sshd_config` allows `PermitRootLogin prohibit-password`, so `ssh -p 8822
  root@210.5.158.91` works key-only for the few root-needed steps (`systemctl`,
  editing root-owned files, `journalctl -u` for other-user units). Password login is
  the fallback (`gui` pw and root pw are held by the maintainer).
- **`gui` has no sudo** ("not in the sudoers file"). Root commands run either through
  the root SSH key above, or as `gui` via `su -`. The `su` password prompt is
  localized (Chinese), so force C locale or `expect`-style prompt matching breaks:
  ```bash
  env LC_ALL=C LANG=C su -c '<command>'      # prompts for the root password
  ```
- **`gui` is in `adm`, `systemd-journal`, `docker`** — so `journalctl -u <unit>`,
  `docker …`, and reading logs work **without** root. Only state changes
  (`systemctl start/restart/stop`, editing `/etc/…`) need root.
- **No Go, no `mise`, no `air` on this box.** There is no `ChenWeb/mise.toml` here. The
  only tooling under `~/Workspace/bin/` is `nats`, `nats-server`, `goose`. Everything else
  runs from a **pre-built binary** cross-compiled on the Mac. See §7 and the
  Environment-variables section.
- **Two ways to start each service:**
  - **Method A — systemd (normal).** Units are `enabled`, so a reboot brings the whole
    stack up on its own in dependency order. Use this for day-to-day.
  - **Method B — foreground (debugging).** Run the binary directly as `gui` to watch its
    stdout live. No root needed. This is the closest thing to a "dev" loop on this box —
    there is no live-reload.
- **`docker` works without sudo** (`gui` is in the `docker` group).

## Quick reference

| Component | systemd unit | Runs | Listens | Depends on |
|---|---|---|---|---|
| Postgres (ChenWeb data) | — (Docker) | `chenweb-paradedb` container (ParadeDB = PG + pgvector + pg_search) | `127.0.0.1:5433` | `docker` |
| Postgres (Kratos) | — (Docker) | `kratos-postgres` container | `127.0.0.1:5434` | `docker` |
| JetStream | `nats-server` | `~/Workspace/bin/nats-server -js` | `:4222` | — |
| Kratos (auth) | `kratos` | `~/Workspace/Kratos/kratos-linux serve` | `:4433` public, `:4434` admin | `kratos-postgres` |
| ChenWeb backend | `chenweb` | `~/Workspace/ChenWeb/server-linux serve` | `:8090` | nats, kratos, paradedb |
| Doc Processor | `doc-processor` | `~/Workspace/ChenWeb/doc-processor-linux` | — (NATS worker) | nats, chenweb (schema) |
| Converter | `parser-result-converter` | `~/Workspace/ChenWeb/parser-result-converter-linux` | — (NATS worker) | nats, chenweb (schema) |
| PDF Python | `pdf-parser` | `python/pdf-parser/.venv/bin/python pdf_parser.py` | — (NATS worker) | nats |
| Reverse proxy | `nginx` | shared box nginx | `:80`→301, `:443 ssl` | chenweb, kratos |

**How traffic flows:** browser → `https://onto.bzton.cn` (nginx :443, Let's Encrypt cert) →
`location /kratos/` proxies to `127.0.0.1:4433` (Kratos, prefix stripped);
`location /` proxies to `127.0.0.1:8090` (ChenWeb). `:80` just 301-redirects to `:443`.

> **Kratos MUST be same-origin under `/kratos/`.** The built frontend hardcodes
> `KRATOS_PUBLIC_URL = '/kratos'` (`web/src/lib/services/ory.ts`) — every browser-side
> auth call is a relative `/kratos/self-service/...`. If the nginx `/kratos/` location is
> missing, login/registration silently fail (the calls hit the Go backend, which 404s
> them). The vhost is `/etc/nginx/conf.d/onto-bzton-cn.conf`.

> The box also runs a **native PostgreSQL on `:5432`** — that is the box's own instance and
> is **not used by ChenWeb or Kratos**. Both of ours are the Docker containers above.

## Start / check everything

```bash
# Start the whole stack (systemd honours the dependency order via After=/Wants=)
env LC_ALL=C LANG=C su -c 'systemctl start nats-server kratos chenweb doc-processor parser-result-converter pdf-parser'

# Status of everything
for s in docker nats-server kratos chenweb doc-processor parser-result-converter pdf-parser nginx; do
  printf '%-26s %s\n' "$s" "$(systemctl is-active "$s")"
done
docker ps --format '{{.Names}}\t{{.Status}}' | grep -E 'paradedb|kratos-postgres'

# Health — loopback
curl -s http://127.0.0.1:4433/health/alive; echo                     # kratos -> {"status":"ok"}
curl -s -o /dev/null -w 'chenweb :8090 -> %{http_code}\n' http://127.0.0.1:8090/
curl -s http://127.0.0.1:8090/session; echo                          # -> {"error":"Login required"} (401)
~/Workspace/bin/nats --server nats://127.0.0.1:4222 stream ls

# Health — public edge
curl -s -o /dev/null -w 'http  -> %{http_code} (%{redirect_url})\n' http://onto.bzton.cn/     # 301 -> https
curl -s -o /dev/null -w 'https / -> %{http_code}\n' https://onto.bzton.cn/                    # 200
curl -s https://onto.bzton.cn/kratos/health/alive; echo                                       # {"status":"ok"}
```

## Startup order (dependency chain)

```
1. docker            -> chenweb-paradedb (:5433), kratos-postgres (:5434)   [restart=unless-stopped, auto]
2. nats-server       (:4222)
3. kratos            (:4433/:4434)   needs kratos-postgres
4. chenweb           (:8090)         needs nats + kratos + paradedb; runs goose migrations at startup
5. doc-processor + parser-result-converter   need nats + chenweb's schema
6. pdf-parser        needs nats
7. nginx             already running; only `reload` if the vhost changed
```

On a normal reboot you do **nothing** — every unit is `enabled` and chained. This document
is for the cases where something was stopped by hand, a single service needs a restart, or
you want to watch one service's output live.

---

## 1. PostgreSQL

Two Docker Postgres containers, both `--restart unless-stopped` (so they come back on their
own once `docker` is up). Nothing to do on a normal boot.

| Container | Host port | Database | User | Purpose |
|---|---|---|---|---|
| `chenweb-paradedb` | `127.0.0.1:5433` | `miner` | `admin` | ChenWeb's `kb`/`public`/`shared` schemas; ParadeDB gives `pg_search` (BM25) + `vector` (pgvector) |
| `kratos-postgres` | `127.0.0.1:5434` | `kratos_dingbo` | (see `Kratos/kratos.env` `DSN`) | Kratos identity store — the `kratos_dingbo` **name** is historical, unrelated to the domain; leave it |

**Start (manual):**
```bash
docker start chenweb-paradedb kratos-postgres      # no sudo needed
```

**Check:**
```bash
docker exec chenweb-paradedb pg_isready -U admin -d miner        # -> accepting connections
docker exec chenweb-paradedb psql -U admin -d miner -c '\dx' | grep -E 'pg_search|vector'
# applied migrations:
docker exec chenweb-paradedb psql -U admin -d miner -tAc \
  'select count(*), max(version_id) from project_db_migration'
```

**Notes**
- The volume mount is the container's `/var/lib/postgresql` (not `.../data`) — see the deploy
  devdoc §1.3.2. Don't recreate these containers casually; `docker start` an existing one.
- ChenWeb reads `PG_HOST=127.0.0.1 PG_PORT=5433 PG_DB_NAME=miner PG_USER_NAME=admin` from
  `~/Workspace/ChenWeb/.env`.
- ChenWeb **does not** create the database — it runs schema migrations (goose) against an
  existing `miner` DB at every `chenweb` startup.

---

## 2. Kratos

Runs the cross-compiled `kratos-linux` binary directly (not `mise run` — that deviation is
documented in `2026073001-devdoc-deploy-production-china-dingbo.md`).

**Start (systemd):**
```bash
env LC_ALL=C LANG=C su -c 'systemctl start kratos'
```

**Start (foreground / debugging):**
```bash
cd ~/Workspace/Kratos
set -a; source kratos.env; set +a
./kratos-linux serve --config ./kratos/kratos.yml --watch-courier
```

**Migrate (only needed on a fresh Kratos DB — already done here):**
```bash
cd ~/Workspace/Kratos
set -a; source kratos.env; set +a
./kratos-linux migrate sql --config ./kratos/kratos.yml --read-from-env --yes
```
The systemd unit does **not** run migrations; `bringup.sh` does. On this box Kratos is
already migrated, so `systemctl start kratos` is enough.

**Check:**
```bash
curl -s http://127.0.0.1:4433/health/alive          # {"status":"ok"}  (public API, direct)
curl -s http://127.0.0.1:4434/health/alive           # {"status":"ok"}  (admin API, loopback only)
curl -s https://onto.bzton.cn/kratos/health/alive     # {"status":"ok"}  (through nginx, the path the browser uses)
# end-to-end: a login flow's ui.action must come back prefixed https://onto.bzton.cn/kratos/
curl -s -H 'Accept: application/json' https://onto.bzton.cn/kratos/self-service/login/browser \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["ui"]["action"])'
```

**Notes**
- Config: `~/Workspace/Kratos/kratos.env` (secrets + URLs), plus the checked-in
  `kratos/kratos.yml`, `kratos/identity.schema.json`, `kratos/google_mapper.jsonnet`,
  `kratos/templates/`. Since 2026-09-08 the URLs are **https and same-origin**:
  - `SERVE_PUBLIC_BASE_URL=https://onto.bzton.cn/kratos/` (trailing slash matters — Kratos
    builds all browser-facing flow URLs from this; nginx strips the `/kratos/` prefix
    before the request reaches Kratos)
  - all `SELFSERVICE_*` return / flow-UI URLs are port-less `https://onto.bzton.cn/...`
  - `SESSION_COOKIE_DOMAIN=onto.bzton.cn`, `SESSION_COOKIE_SECURE=true`
  - the fixed-size `SERVE_PUBLIC_CORS_ALLOWED_ORIGINS_*` (8 slots) and
    `SELFSERVICE_ALLOWED_RETURN_URLS_*` (13 slots) arrays require **every slot filled with a
    unique value** — unused slots are padded `http://127.0.0.1:<n>` (deploy-china devdoc
    gotcha #3). Don't collapse duplicates to a real URL.
- `WorkingDirectory` must be `~/Workspace/Kratos` (`--config ./kratos/kratos.yml` is relative).
- Password login only. Google login needs redirect URI
  `https://onto.bzton.cn/kratos/self-service/methods/oidc/callback/google` registered in
  Google Cloud Console — not done. SMTP is a placeholder (`smtp://user:pass@127.0.0.1:1025/`).
- Sysadmin bootstrap (one-shot, idempotent). The account's login id is still
  `admin@dingbo.bzton.cn` — email is just the identifier, no need to change it:
  ```bash
  cd ~/Workspace/ChenWeb
  set -a; source .env; set +a
  export SHARED_LIB_CONFIG_DIR=/home/gui/Workspace/shared/libconfig.toml
  ./create-admin-linux -email admin@dingbo.bzton.cn
  ```

### 2.1 Chinese cell-phone (SMS-code) sign-in

Live since 2026-09-11. Implementation detail is in
`2026091101-devdoc-phone-login-china.md`; this is the operational view.

**What's wired on this box**

| Layer | Setting on the box | Notes |
|---|---|---|
| Frontend flag | `config.local.toml` `[frontend] enable_phone_login = true` | gates the "Log in with Phone" link + the phone flow; `chenweb` restart to apply |
| ChenWeb env | `.env`: `SMS_RELAY_SHARED_SECRET`, `ALIYUN_SMS_ACCESS_KEY_ID/_SECRET/_SIGN_NAME/_TEMPLATE_CODE`, `VITE_DEFAULT_NORM_ROUTE=/semos/workspace` | the Aliyun key is **shared with bzton production** (`LTAI5tPs…`, sign `润申标准化`, template `SMS_223202121`) |
| Kratos schema | `kratos/identity.schema.json`: `phone` trait (`credentials.code {via:"sms"}`), `anyOf` has `{required:["phone"]}` | no `verification`/`format` block — deliberate |
| Kratos config | `kratos/kratos.yml`: `methods.code.passwordless_enabled: true`; `registration.after.code` → `session` hook; `courier.channels[sms]` HTTP channel → `http://127.0.0.1:8090/auth/internal/sms-courier/send` with header `X-Internal-Relay-Secret` = the `.env` secret; `body: file:///home/gui/Workspace/Kratos/kratos/templates/courier/sms/request.config.jsonnet` | **box paths + port 8090**, not the Mac's `/Users/cding/…` + `8080`. `kratos.yml` is gitignored so it drifts — a stale Mac path here silently breaks SMS. |

Kratos courier delivery of the SMS goes **Kratos → `chenweb` relay → Aliyun**; the
relay does the signed `SendSms`. Kratos itself never talks to Aliyun.

**Why it works here and not from a dev box:** the Aliyun key's RAM policy only permits
`SendSms` from bzton's server IPs. This box is `210.5.158.91` — the same public IP as
`www.bzton.com` — so it's allowed. From anywhere else Aliyun returns
`InvalidAccessKeyId.AccessPolicyDenied`. If ChenWeb ever moves IPs, the new egress IP
must be allowlisted on the Aliyun account (or get a dedicated key).

**Verify (from the box)**

```bash
# flag live
curl -s http://127.0.0.1:8090/api/config | grep -o '"enable_phone_login":[^,}]*'      # :true
# relay secret enforced (wrong secret must 401)
curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  http://127.0.0.1:8090/auth/internal/sms-courier/send \
  -H 'X-Internal-Relay-Secret: wrong' -d '{"to":"+8613800000000","code":"0"}'          # 401
# Kratos offers the code method
curl -s http://127.0.0.1:4433/self-service/login/api | grep -o '"group":"code"'        # match
# full send/verify + DB checks: see 2026091101-devdoc-phone-login-china.md §6
```

**Troubleshoot**

| Symptom | Check |
|---|---|
| "Log in with Phone" link missing | `/api/config` `enable_phone_login` — flag not set, or `chenweb` not restarted |
| Code never arrives | `psql "$(grep '^DSN=' ~/Workspace/Kratos/kratos.env \| cut -d= -f2-)" -c "select status,send_count from courier_messages where recipient='+86<num>' order by created_at desc limit 1"` — `2`=sent, `4`=abandoned. Then `courier_message_dispatches.error`. `journalctl -u chenweb \| grep -E 'aliyun sms\|sms code dispatched\|sms send rate'` |
| `InvalidAccessKeyId.AccessPolicyDenied` in the log | call originated from a non-allowlisted IP (not this box), or the shared key was rotated |
| `giving up after 1 attempt(s)` / `code:500` in `courier_message_dispatches` | relay returned non-2xx — usually a missing `SMS_RELAY_*`/`ALIYUN_SMS_*` env var (`chenweb` not restarted after editing `.env`) or the wrong port/path in `kratos.yml`'s courier `url` |
| Logged in, then bounced to login on every page / `403 EMAIL_NOT_VERIFIED` | old `server-linux` without the `isIdentityVerified` fix (shared/go jj `322a`) — redeploy |
| Redirects to `/dashboard` not `/semos/workspace` | `VITE_DEFAULT_NORM_ROUTE` / `VITE_DEFAULT_ADMIN_ROUTE` missing from `.env` (affects email + Google too) |
| Number stuck "try again later" for up to an hour | per-phone SMS rate limiter (5/hr, in-process). `systemctl restart chenweb` clears it, or use another number |

---

## 3. JetStream (NATS)

"JetStream" = the NATS server started with `-js`. One process, `~/Workspace/bin/nats-server`.

**Start (systemd):**
```bash
env LC_ALL=C LANG=C su -c 'systemctl start nats-server'
```

**Start (foreground / debugging):**
```bash
~/Workspace/bin/nats-server -js -sd ~/Workspace/nats-data -p 4222
```

**Check:**
```bash
(echo > /dev/tcp/127.0.0.1/4222) && echo "nats port ok"
~/Workspace/bin/nats --server nats://127.0.0.1:4222 stream ls
```

Expected streams (created by the **workers** on their startup, not by NATS itself):

| Stream | Primary subject(s) | Owner |
|---|---|---|
| `doc-processor-start-events` | `kb.pdf.start-doc-processing`, `kb.line-file-generated` | doc-processor |
| `doc-processor-line-file-events` | `kb.line-file-generated` | doc-processor |
| `doc-review-events` | `kb.doc-review.start` | doc-processor |
| `pdf-parsed-events` | `kb.pdf.parsed` | parser-result-converter |
| `kb-pdf-staged-events` | `kb.pdf.staged` | pdf-parser |

**Notes**
- Data dir: `~/Workspace/nats-data/jetstream`. Deleting it wipes stream state/consumers.
- The `nats` CLI lives at `~/Workspace/bin/nats` (not on `PATH`). Useful: `nats stream info
  <name>`, `nats consumer ls <stream>`.

---

## 4. PDF Python service — `ChenWeb/python/pdf-parser`

A standalone Python 3.12 service that subscribes to JetStream `kb.pdf.staged`, shells out to
MinerU (CPU / pipeline backend, v3.0.9) to OCR/parse the PDF, and publishes the result to
`pdf-parsed-events`.

**Start (systemd):**
```bash
env LC_ALL=C LANG=C su -c 'systemctl start pdf-parser'
```

**Start (foreground / debugging):**
```bash
cd ~/Workspace/ChenWeb/python/pdf-parser
set -a; source ~/Workspace/ChenWeb/.env; set +a
VIRTUAL_ENV=~/Workspace/ChenWeb/python/pdf-parser/.venv \
PYTHONPATH=. \
MINERU_DEVICE_MODE=cpu \
MINERU_BACKEND=pipeline \
MINERU_TOOLS_CONFIG_JSON=~/Workspace/mineru.json \
PDF_STAGE_EVENT_STREAM=kb-pdf-staged-events \
PDF_PARSED_EVENT_STREAM=pdf-parsed-events \
  .venv/bin/python pdf_parser.py
```
(These `Environment=` lines are baked into `pdf-parser.service`; reproduce them for a
foreground run.)

**Check:**
```bash
journalctl -u pdf-parser -n 20 --no-pager      # -> "starting pdf_parser service in jetstream mode"
~/Workspace/ThirdParty/mineru/.venv/bin/mineru --version   # -> mineru, version 3.0.9
```

**Notes**
- Venv Python is uv-managed (`~/.local/share/uv/python/cpython-3.12-...`), symlinked in
  `.venv/bin/python`.
- MinerU model weights: `~/.cache/huggingface/hub/models--opendatalab--PDF-Extract-Kit-1.0/...`,
  wired via `~/Workspace/mineru.json` (`models-dir.pipeline`).
- Relevant `.env` keys: `PDF_PARSER_NAME=mineru`, `MINERU_EXTRA_ARGS=-m ocr -l ch`,
  `PDF_STAGE_EVENT_SUBJECT=kb.pdf.staged`, `PDF_PIPELINE_MODE=jetstream`.
- End-to-end has not been exercised against a real PDF on this box (all streams show 0
  messages). To test, stage a document through `kb.pdf.staged` and confirm MinerU output.

---

## 5. Converter — `ChenWeb/server/cmd/parser-result-converter`

On the box this is the compiled binary `~/Workspace/ChenWeb/parser-result-converter-linux`
(there is no `server/cmd/` source tree here). NATS worker: consumes `kb.pdf.parsed`
(stream `pdf-parsed-events`), converts MinerU output into line-files, publishes
`kb.line-file-generated` (stream `doc-processor-start-events`).

**Start (systemd):**
```bash
env LC_ALL=C LANG=C su -c 'systemctl start parser-result-converter'
```

**Start (foreground / debugging):**
```bash
cd ~/Workspace/ChenWeb
set -a; source .env; set +a
export SHARED_LIB_CONFIG_DIR=/home/gui/Workspace/shared/libconfig.toml
./parser-result-converter-linux
```

**Check:**
```bash
journalctl -u parser-result-converter -n 20 --no-pager
# -> "file converter service starting" + "jetstream subscription active" subject="kb.pdf.parsed"
```

**Notes**
- `WorkingDirectory=~/Workspace/ChenWeb` — it reads `./config.toml` and `./.env` relative to
  cwd. `PARSER_RESULT_CONVERTER_CONFIG=./config.toml` and
  `PARSER_RESULT_CONVERTER_STREAM=pdf-parsed-events` are set in `.env`.
- `SHARED_LIB_CONFIG_DIR` **must be a real exported env var**, not just present in `.env`
  (systemd sets it via `Environment=`; a foreground run must `export` it) — see deploy
  devdoc §3.

---

## 6. Doc Processor — `ChenWeb/server/cmd/doc-processor`

Compiled binary `~/Workspace/ChenWeb/doc-processor-linux`. The main pipeline worker:
chunking, extraction (metrics / provisions / entities / relations / semantic projections /
inventory items / topics / scene blocks) and the doc-review pipeline.

Subscribes to:
- `kb.pdf.start-doc-processing` and `kb.line-file-generated` (stream `doc-processor-start-events`)
- `kb.doc-review.start` (stream `doc-review-events`)

**Start (systemd):**
```bash
env LC_ALL=C LANG=C su -c 'systemctl start doc-processor'
```

**Start (foreground / debugging):**
```bash
cd ~/Workspace/ChenWeb
set -a; source .env; set +a
export SHARED_LIB_CONFIG_DIR=/home/gui/Workspace/shared/libconfig.toml
./doc-processor-linux
```

**Check:**
```bash
journalctl -u doc-processor -n 30 --no-pager
# -> "doc processor starting" then 3x "jetstream subscription active"
```

**Notes**
- Needs **real LLM API keys** in `.env` to do work (not just to start): `OPENAI_API_KEY`,
  `ANTHROPIC_API_KEY`, `DASHSCOPE_API_KEY` — all present. Model routing is the large block of
  `*_MODEL_NAME` / `*_MODEL_FALLBACK` vars in `.env`; prompts come from
  `PROMPT_DIR=~/Workspace/ChenWeb/prompts`.
- `DOC_PROCESSOR_CONFIG=./config.toml`, `DOC_PROCESSOR_EVENT_STREAM=doc-processor-start-events`.
- **Known WARN (non-fatal):** current code expects `CLASSIFY_DOCUMENT_MODEL_NAME`, which is
  not in the box `.env` — logs `missing one of CLASSIFY_DOCUMENT_MODEL_NAME` at startup and
  otherwise runs. Add it next to the other `*_MODEL_NAME` entries to silence (see the
  Environment-variables section for how to find the delta from `mise.local.toml`).
- The active processor list is `configured_required_processors` in `config.toml` (8 stages).
  Current code ships 6 more optional stages (`normalize_assertions`, `associate_semantics`,
  `project_semantics`, `extract_metric_definitions`, `extract_test_methods`,
  `extract_product_structure`) that are **not** enabled on this box.

---

## 7. ChenWeb Go backend — "Air"

**There is no Air on this box, and there cannot be** — Air is a live-reload wrapper around
`go build`, and there is no Go toolchain here. `.air.toml` / `mise dev-server` / `go tool
air` are a **local-dev-only** workflow on the Mac.

On the box the backend is the pre-built binary `~/Workspace/ChenWeb/server-linux`, listening
on **`:8090`** (moved from 8080 on 2026-09-08), fronted by nginx for `onto.bzton.cn`. It
runs goose migrations against the `miner` DB at every startup.

**Start (systemd):**
```bash
env LC_ALL=C LANG=C su -c 'systemctl start chenweb'
```

**Restart (systemd):**
```bash
env LC_ALL=C LANG=C su -c 'systemctl restart chenweb'
journalctl -u chenweb -f
```

**Start (foreground / debugging — the closest thing to "watching Air"):**
```bash
cd ~/Workspace/ChenWeb
set -a; source .env; set +a
export SHARED_LIB_CONFIG_DIR=/home/gui/Workspace/shared/libconfig.toml
./server-linux serve --dir /home/gui/Workspace/ChenWeb/Data
```
You get live stdout (including the goose migration log) but **no rebuild-on-change**.

**Check:**
```bash
curl -s -o /dev/null -w 'chenweb :8090 -> %{http_code}\n' http://127.0.0.1:8090/     # 200
curl -s http://127.0.0.1:8090/session; echo                                          # {"error":"Login required"}
curl -s -o /dev/null -w 'https edge -> %{http_code}\n' https://onto.bzton.cn/          # 200
journalctl -u chenweb -n 40 --no-pager | grep -v 'goose:'
```

**The dev-loop equivalent on the box** is: rebuild on the Mac, transfer the binary,
`systemctl restart chenweb`. As of 2026-09-11 this is packaged:

```bash
# --- on the Mac, in ChenWeb/ ---
mise run build-server-linux                 # all four linux/amd64 binaries + .sha256
BINS=server mise run build-server-linux     # just server-linux (fast; frontend rebuilt too)
#   output: /tmp/chenweb-deploy/{server-linux[,.sha256], deploy-server-china.sh, MANIFEST}

scp -P 8822 -r /tmp/chenweb-deploy gui@210.5.158.91:~/

# --- on the box, as root (su - or the root SSH key) ---
bash ~/chenweb-deploy/deploy-server-china.sh ~/chenweb-deploy server
#   per binary: verify sha256 + ELF/arch, back up the current one (.bak-<ts>, keeps 3),
#   stop → install → start the mapped unit (server→chenweb, doc-processor→doc-processor,
#   parser-result-converter→…, create-admin→install only), health-gate, auto-rollback
#   on failure. DRY_RUN=1 to preview.
```

`build-server-linux` is `CGO_ENABLED=0 GOOS=linux GOARCH=amd64 -trimpath -ldflags "-s -w"`
and rebuilds the embedded frontend first when `server` is in the set
(`server/api/webbuild` is gitignored). The task lives in `ChenWeb/mise.toml`, the
script in `ChenWeb/scripts/deploy-server-china.sh` (ChenWeb jj commit `012e`).
Box-side enablement that a binary swap does **not** carry (config flags, env, Kratos)
is in `ChenWeb/deploy/phone-login/`. Older/fuller procedure:
`2026072401-devdoc-deploy-production.md` §2 and `project_chenweb_dingbo_deployment` (memory).

**Notes**
- `Environment=SHARED_LIB_CONFIG_DIR=...` in the unit is required — its `sync.Once` fires
  before `.env` is parsed, so it will not work from `.env` alone (deploy devdoc §3).
- Config precedence: `config.toml` <- `config.local.toml` (Linux overrides:
  `[app_info] host`, `[llm] archive_root`, `[config] config_filename`) <- `.env`.
- If the HTTP port ever changes again it lives in: `.env` (`APP_PORT`/`PORT`),
  `config.toml` (`[app_info] port`), and `/etc/nginx/conf.d/onto-bzton-cn.conf`
  (`proxy_pass`). `kratos.env` URLs are now port-less (nginx-fronted), so they don't.

---

## Environment variables (there is no `mise` on this box)

`mise.local.toml` is a **Mac-only** mechanism. On the box, env vars live in plain files that
systemd reads via `EnvironmentFile=`:

| File | Feeds |
|---|---|
| `~/Workspace/ChenWeb/.env` | `chenweb`, `doc-processor`, `parser-result-converter`, `pdf-parser` |
| `~/Workspace/Kratos/kratos.env` | `kratos` |
| `Environment=` lines inside the `.service` units | `SHARED_LIB_CONFIG_DIR`; the `MINERU_*` block for `pdf-parser` |

These two `.env` files are the **production source of truth**. They are maintained by hand
and hold prod values (prod domain, prod API keys, `/home/gui/...` paths, port 8090, https).
The Mac's `mise.local.toml [env]` holds dev values (`macmini.deepdocs.me`,
`/Users/cding/...`, port 8080). They are **parallel, not synced.**

**When a var changes / is added in `mise.local.toml` and should also apply to prod:**

1. On the Mac, see the delta:
   ```bash
   cd ~/Workspace/ChenWeb
   scripts/render-prod-env.sh --diff /path/to/a/copy/of/the/box/.env
   ```
   It prints: keys only in `mise.local.toml` (candidates to port), keys only in the box file
   (box-specific — leave), and keys whose value differs (mostly the expected
   domain/path/port drift; secret-ish values are masked). Get a current copy of the box file
   with `scp -P 8822 gui@210.5.158.91:Workspace/ChenWeb/.env /tmp/box.env`.
2. Hand-edit the box file for the handful that matter. **Translation rules:**
   - `KEY = "value"` (TOML) → `KEY=value` — strip the quotes, **no spaces around `=`**.
     systemd 237's `EnvironmentFile=` parser is strict and takes the value literally
     (quotes would become part of the value). See deploy-china devdoc bug #4.
   - `/Users/cding/...` → `/home/gui/...`
   - drop Mac-only vars (`PGDATA`, `TEST_DATABASE_URL`, `DATA_SYNC_CONFIG`,
     `PG_BACKUP_REMOTE_*`, `MINERU_DEVICE_MODE=mps`, …)
3. `su -c 'systemctl restart <affected units>'`.

**Never `scp` the raw `render-prod-env.sh` output onto the box** — it would overwrite prod
values with Mac ones. It is a diff aid, not a deploy artifact.

---

## Restart / logs for one service

```bash
env LC_ALL=C LANG=C su -c 'systemctl restart <unit>'        # chenweb | kratos | nats-server | doc-processor | parser-result-converter | pdf-parser
systemctl status <unit>
journalctl -u <unit> -n 100 --no-pager                       # -f to follow; no sudo needed to read
```

Ordered full restart (after changing `.env` / `kratos.env` / `config.local.toml` / the vhost):
```bash
env LC_ALL=C LANG=C su -c '
  systemctl restart nats-server kratos && sleep 3 &&
  systemctl restart chenweb doc-processor parser-result-converter pdf-parser && sleep 3 &&
  nginx -t && systemctl reload nginx
'
```

## nginx & TLS

Shared box nginx (also serves `bzton-platform-prod`, `bzt.cdbzh.com`, etc. — **do not** stop
it). The ChenWeb vhost is `/etc/nginx/conf.d/onto-bzton-cn.conf`:

- `server { listen 80; ... location / { return 301 https://$host$request_uri; } }` plus a
  `/.well-known/acme-challenge/` location rooted at `/var/www/letsencrypt` (for cert renewal)
- `server { listen 443 ssl; ssl_certificate /etc/letsencrypt/live/onto.bzton.cn/fullchain.pem; ... }`
  with `location /kratos/` → `proxy_pass http://127.0.0.1:4433/;` (trailing slash strips the
  prefix) and `location /` → `proxy_pass http://127.0.0.1:8090;`

The old `dingbo-bzton-cn.conf` is parked as `...conf.disabled` (rollback). `.bak-http` is
the pre-TLS version of the onto vhost.

```bash
env LC_ALL=C LANG=C su -c 'nginx -t && systemctl reload nginx'
```

**Cert:** Let's Encrypt, issued with certbot 0.27 via
`certbot certonly --webroot -w /var/www/letsencrypt -d onto.bzton.cn`. Auto-renewal is the
packaged `certbot.timer` (`systemctl is-enabled certbot.timer` → `enabled`). Manual renew:
`su -c 'certbot renew && systemctl reload nginx'`. certbot 0.27 is old; if a future renewal
fails, either `apt install` a newer certbot from a backports/PPA or obtain the cert the way
the sibling bzton vhosts do (a per-domain PEM+key dropped into the nginx `certs/` tree).

## Reboot behaviour

All of `nats-server`, `kratos`, `chenweb`, `doc-processor`, `parser-result-converter`,
`pdf-parser`, `nginx`, `docker` are `enabled`; the two Postgres containers are
`--restart unless-stopped`. A clean reboot brings the entire stack back with no manual
action. Verify afterwards with the "check everything" block above.

## Manual bring-up script

`~/Workspace/bringup.sh` starts nats → kratos (with migrate) → chenweb via `nohup`
(no systemd, no root). It predates the 8090 move and the domain rename, so its trailing
health checks still probe `:8080` and it references `dingbo` — cosmetic only; the services
themselves read everything from `.env`. Prefer the systemd path unless you specifically need
a rootless start.

## See also

- `2026091101-devdoc-phone-login-china.md` — implementation of §2.1 (Kratos code
  method, the SMS relay, the JIT-registration and verified-gate specifics, gotchas).
- `2026072401-devdoc-deploy-production.md` — full build + deploy runbook, config-var
  reference (§3), migration bootstrap (§4), verification checklist (§7), operations (§8).
- `2026073001-devdoc-deploy-production-china-dingbo.md` — why this box deviates (Ubuntu
  18.04, blocked registries, Kratos PG in Docker, cross-compiled Kratos, flaky link,
  Kratos fixed-size array gotcha #3).
- `project_chenweb_dingbo_deployment` (memory) — current deployed state, the 2026-09-08
  code refresh and the dingbo→onto rename.
