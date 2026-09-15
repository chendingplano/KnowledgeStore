# Starting the ChenWeb System on the onto.bzton.cn Production Box

**Date:** 2026-09-07 (rev 2026-09-08: renamed `dingbo.bzton.cn` → `https://onto.bzton.cn`,
added TLS + the `/kratos/` reverse-proxy + the Environment-variables section;
rev 2026-09-11: added §2.1 Chinese cell-phone sign-in, key-based root access, and the
`mise build-server-linux` / `deploy-server-china.sh` deploy path;
rev 2026-09-14: added §8 Doc Service — this box never had it deployed, so the whole
staging → `kb.inputs` → JetStream ingest pipeline had never fired a single message since
the streams were created on 2026-07-30/31; also installed `libreoffice-writer` for the
docx→pdf reroute path;
rev 2026-09-15: added §9 LLM Account/Profile Import — `.models.toml` is deployed to this
box but the DB-side account/profile import was never run against its dedicated
`chenweb-paradedb`, so every LLM usage event logs `(MID-20260708-01)` unresolved-account
WARNs;
rev 2026-09-16: added §6.1 — `typst` was never installed on this box, so every doc-review
PDF render failed non-fatally (`exec: "typst": executable file not found in $PATH`) since
provisioning; fixed by installing the static-musl v0.14.2 release to `/usr/local/bin/`;
added §6.2 — `doc-review.local.toml` was also never deployed here (missing from the
original deploy runbook's rsync list, now fixed there too), silently disabling 6 reviewer
aspects; fixed by rsyncing it over and restarting `doc-processor`)
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
| Doc Service | `doc-service` | `~/Workspace/ChenWeb/doc-service-linux -config ./config.toml` | — (staging dir watcher + NATS publisher) | nats, chenweb (schema) |
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
env LC_ALL=C LANG=C su -c 'systemctl start nats-server kratos chenweb doc-service doc-processor parser-result-converter pdf-parser'

# Status of everything
for s in docker nats-server kratos chenweb doc-service doc-processor parser-result-converter pdf-parser nginx; do
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
5. doc-service + doc-processor + parser-result-converter   need nats + chenweb's schema
6. pdf-parser        needs nats + doc-service (publishes the kb.pdf.staged event it consumes)
7. nginx             already running; only `reload` if the vhost changed
```

> **doc-service is the pipeline's front door.** It watches `DATA_STAGING_DIR`, writes the
> `kb.inputs` row, and publishes the `kb.pdf.staged` JetStream event that `pdf-parser`
> consumes. Every other worker downstream (`pdf-parser` → `parser-result-converter` →
> `doc-processor`) can be running correctly and still process nothing if `doc-service` isn't
> — see §8.

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
  messages as of 2026-09-14) — **root cause: `doc-service`, the only thing that ever
  publishes to `kb.pdf.staged`, was never deployed here**; see §8. Once it's deployed and a
  file is dropped in `DATA_STAGING_DIR`, this stream should show its first message ever.

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

### 6.1 `typst` (doc-review PDF rendering)

**Fixed 2026-09-16 — this binary was never provisioned on the box.** The doc-review
pipeline (`server/api/doc-reviews/typst_report.go`, `correction_report.go`) shells out to a
bare `typst compile --root / <in>.typ <out>.pdf` with no config override — it relies
entirely on `typst` being on `PATH`. Unlike the LibreOffice reroute (§8), no deploy script
or devdoc ever installed it, so every doc-review PDF render failed non-fatally since this
box was provisioned, logging:
```
WARN typst PDF generation failed error="typst compile (zh): exec: \"typst\": executable file not found in $PATH"
```
(cosmetic-ish: the WARN is non-fatal and doc-review otherwise completes, but no PDF/report
artifact is produced.)

**Fix applied:** installed the static-linked release matching the Mac's dev version
(`typst 0.14.2`, Nix-provisioned there) to avoid any glibc mismatch against this box's old
Ubuntu 18.04 (`glibc 2.27`):
```bash
# --- on the Mac ---
curl -sSL -o typst.tar.xz \
  https://github.com/typst/typst/releases/download/v0.14.2/typst-x86_64-unknown-linux-musl.tar.xz
tar xJf typst.tar.xz   # -> typst-x86_64-unknown-linux-musl/typst (static-pie, x86_64, stripped)
scp -P 8822 typst-x86_64-unknown-linux-musl/typst gui@210.5.158.91:~/typst-v0.14.2

# --- on the box, as root ---
install -o root -g root -m 0755 /home/gui/typst-v0.14.2 /usr/local/bin/typst
rm -f /home/gui/typst-v0.14.2
env LC_ALL=C LANG=C su -c 'systemctl restart doc-processor'
```
Installed to **`/usr/local/bin/`, not `~/Workspace/bin/`** (unlike `nats`/`goose`) —
`doc-processor.service` has no `Environment=PATH=...` override, so it only sees systemd's
default `PATH` (`/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`); dropping
the binary into `~/Workspace/bin` would have needed a unit edit, `/usr/local/bin` needs
none.

CJK rendering ("zh" in the error) was verified separately — the box already has
`SimSun`/`SimHei` (`/usr/share/fonts/{chinese,win}/...`, left over from the MinerU/OCR
provisioning) so `typst compile` on Chinese text works with no extra font install.

**Verify:**
```bash
typst --version                                          # -> typst 0.14.2 (b33de9de)
echo '= hi' > /tmp/t.typ && typst compile --root / /tmp/t.typ /tmp/t.pdf && ls -la /tmp/t.pdf
journalctl -u doc-processor -n 50 --no-pager | grep -i 'typst PDF generation failed'   # should stay empty going forward
```

**If `typst` needs a version bump later:** re-run the same curl/scp/install steps with the
new `vX.Y.Z` tag and the same `-musl` asset (keep it static — the `-gnu` asset needs a
newer glibc than this box has), then restart `doc-processor` (and `chenweb`, if the
correction-report path in `server/api/doc-reviews/correction_report.go` is ever moved
off it).

### 6.2 `doc-review.local.toml` (per-aspect reviewer config)

**Fixed 2026-09-16 — this file was never provisioned on the box either.** Found right
after the §6.1 `typst` fix, on the first real doc-review run that got far enough to try:
```
INFO doc-review config file not found; reviewer disabled aspect="grammar_spelling"
INFO doc-review config file not found; reviewer disabled aspect="tone_voice"
INFO doc-review config file not found; reviewer disabled aspect="formatting_consistency"
INFO doc-review config file not found; reviewer disabled aspect="readability"
INFO doc-review config file not found; reviewer disabled aspect="localization"
INFO doc-review config file not found; reviewer disabled aspect="logical_flow"
```
`GetDocReviewConfig()` (`server/api/doc-reviews/review-config.go`) walks up from
`doc-processor`'s working directory looking for `doc-review.local.toml`; when it's absent
it returns `(nil, nil)` — **not an error**, so this is silent at startup and only shows up,
one `INFO` per aspect, the first time a doc-review actually runs. Despite the `.local.`
name this is a real, git-tracked repo-root file (ChenWeb commit `616fa90c`), not a
gitignored machine-specific override — it should have been in the original deploy
runbook's rsync list (`2026072401-devdoc-deploy-production.md` §2.4) alongside
`prompts`/`.models.toml`/`docs/doc-templates`, and wasn't. Fixed there too (added to that
rsync line + a warning note) so this doesn't regress on the next fresh box.

**Fix applied:**
```bash
# --- on the Mac ---
rsync -avz -e "ssh -p 8822" /Users/cding/Workspace/ChenWeb/doc-review.local.toml \
  gui@210.5.158.91:~/Workspace/ChenWeb/doc-review.local.toml

# --- on the box, as root ---
systemctl restart doc-processor
```
No translation needed — the file only has symbolic `model = "deepseek-flash-chen"` /
`prompt = "prompt-review-*.md"` refs, both already present on the box (`.models.toml`,
`prompts/`), verified before restarting.

**Verify:** trigger a real doc-review run and confirm the six aspects above no longer log
`doc-review config file not found`; a resolved reviewer instead logs its own
model/prompt-load path (or `reviewer not configured` / `reviewer disabled by doc-review
config` if explicitly turned off in the TOML — those are legitimate, not the bug).

**If `doc-review.local.toml` is edited later:** it has to be manually re-rsynced and
`doc-processor` restarted — there's no watch/reload, and (unlike `config.toml`) it isn't
part of the `deploy-server-china.sh` binary-swap flow at all, since it's data, not a
binary.

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

## 8. Doc Service — `ChenWeb/server/cmd/doc-service`

**Added 2026-09-14 — this service did not exist on the box before that date.** It is the
front door of the whole document pipeline: it watches `DATA_STAGING_DIR`, MD5-dedups the
file, copies it into `DATA_BACKUP_DIR` and `DATA_HOME_DIR`, inserts/updates the `kb.inputs`
row, and — for PDFs — publishes a `kb.pdf.staged` JetStream event (subject configurable via
`PDF_STAGE_EVENT_SUBJECT`). `.doc`/`.docx` files are instead converted to PDF via
LibreOffice headless (`soffice`) and rerouted into the same PDF pipeline. Runs goose
migrations on every startup, same as the other Go workers.

Without this running, `pdf-parser` has nothing to consume — see the note in §4 and the
Startup-order section above. That's the state this box was in from the streams' creation
(2026-07-30/31) until 2026-09-14: every JetStream stream showed 0 messages, ever.

**Start (systemd):**
```bash
env LC_ALL=C LANG=C su -c 'systemctl start doc-service'
```

**Restart**
```bash
env LC_ALL=C LANG=C su -c 'systemctl restart doc-service'
```

**Start (foreground / debugging):**
```bash
cd ~/Workspace/ChenWeb
set -a; source .env; set +a
export SHARED_LIB_CONFIG_DIR=/home/gui/Workspace/shared/libconfig.toml
./doc-service-linux -config ./config.toml
```

**Check:**
```bash
journalctl -u doc-service -n 30 --no-pager
# -> "docx parse workers started" then "staging thread started"
~/Workspace/bin/nats --server nats://127.0.0.1:4222 stream info kb-pdf-staged-events
# drop a test PDF into DATA_STAGING_DIR, then re-check: messages should go 0 -> 1
soffice --version   # LibreOffice 6.0.7.x — confirms the docx->pdf reroute path works
```

**systemd unit** (`/etc/systemd/system/doc-service.service`, modeled on `doc-processor.service`):
```ini
[Unit]
Description=ChenWeb doc-service (staging directory ingest -> kb.inputs + JetStream)
After=network.target docker.service nats-server.service kratos.service
Wants=docker.service nats-server.service kratos.service

[Service]
Type=simple
User=gui
WorkingDirectory=/home/gui/Workspace/ChenWeb
Environment=SHARED_LIB_CONFIG_DIR=/home/gui/Workspace/shared/libconfig.toml
EnvironmentFile=/home/gui/Workspace/ChenWeb/.env
ExecStart=/home/gui/Workspace/ChenWeb/doc-service-linux -config ./config.toml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```
Install + enable (not yet done on this box as of this writing — do this once the binary is
in place):
```bash
# binary already in ~/Workspace/ChenWeb/doc-service-linux (scp'd from mise build-server-linux)
env LC_ALL=C LANG=C su -c '
  systemctl daemon-reload &&
  systemctl enable doc-service &&
  systemctl start doc-service
'
```

**Notes**
- Requires three env vars or it exits immediately at startup: `DATA_STAGING_DIR`,
  `DATA_BACKUP_DIR`, `DATA_HOME_DIR`. All three were already present in this box's `.env`
  (someone had half-provisioned this before) — only `PDF_STAGE_EVENT_STREAM` was missing.
- **Gotcha — stream name must match the existing consumer.** `doc-service` defaults to
  ensuring a JetStream stream named `pdf-stage-events` for the `kb.pdf.staged` subject if
  `PDF_STAGE_EVENT_STREAM` isn't set. But `pdf-parser` (the Python consumer, §4) already owns
  that subject under a *differently named* stream, `kb-pdf-staged-events` (created
  2026-07-31). A NATS subject can only belong to one stream, so on first start
  `doc-service` would fail to create `pdf-stage-events`, log a warning, and **silently run
  with JetStream publishing disabled** — it would still ingest into `kb.inputs`, just never
  hand off to OCR. Fixed by adding `PDF_STAGE_EVENT_STREAM=kb-pdf-staged-events` to `.env`
  (added 2026-09-14, right after the existing `PDF_STAGE_EVENT_SUBJECT=kb.pdf.staged` line;
  original `.env` backed up alongside it as `.env.bak-pre-doc-service-<timestamp>`).
- `-config ./config.toml` must be passed explicitly — the binary's own default
  (`../../../config.toml`) assumes it's run from three directories below
  `server/cmd/doc-service/`, which is wrong when `WorkingDirectory=~/Workspace/ChenWeb`
  (unlike `doc-processor`/`parser-result-converter`, which read their config path from an
  env var instead of a CLI flag).
- The checked-in `config.toml`'s `[pdf_parser]` section (`staging_dir`, `backup_dir`,
  `python_bin`, etc.) is **dead** for this binary — current `main.go` reads
  `DATA_STAGING_DIR`/`DATA_BACKUP_DIR`/`DATA_HOME_DIR` from the environment only. Don't
  bother editing that TOML section; it isn't wired to anything (`GetPDFParserConfig()` has
  no callers).
- `.doc`/`.docx` conversion needs LibreOffice on `PATH` (`soffice`). Installed 2026-09-14:
  `apt-get install libreoffice-writer` (pulls in `libreoffice-core`; no need for the full
  `libreoffice` metapackage — Writer + core is enough for headless `--convert-to pdf`).
  `SOFFICE_PATH` env var overrides the `PATH` lookup if ever needed.
- `server/cmd/doc-service/USER_MANUAL.md` describes an older two-tier design (Go polls
  `config.toml [pdf_parser]`, a separate `mise ocr-service-*` Python OCR tier via
  OpenDataLoader/PaddleOCR) that **no longer matches the code** — the live pipeline is the
  JetStream one documented here and in §4/§5/§6. The manual predates the MinerU/JetStream
  rework and needs a rewrite; don't follow its config.toml or mise-task instructions.

---

## 9. LLM Account / Profile Import — usage-linkage backfill

**Added 2026-09-15.** Not a running service — a one-time, per-database admin action that was
missed when this box was provisioned. Every LLM call (chat and embedding) flows through
`shared/go/api/llm` → `ChenWeb/server/api/llmusage/sink.go`, which tries to attach each
`llm_usage_event` row to an `llm_account` / `llm_account_model_profile` record so spend can be
attributed and reconciled. When no match is found it still writes the usage row (`account_id`/
`profile_id` left `NULL` — allowed since migration
`20260705000001_llm_usage_event_nullable_account.sql`) but logs:

```
WARN (MID-20260708-01) llm usage event account/profile not resolved; event will be logged without account linkage
```

This is exactly what's showing up in `doc-processor`'s log for the `qwen-embedding-v4`
profile (`text-embedding-v4` via dashscope) — the embedding call itself succeeds (see the
`INFO llm-call embed` line right before the WARN); only cost attribution is lost.

**Why it happens here:** `llm_account`/`llm_account_model_profile` rows are never created
automatically. They only exist once someone calls
`POST /api/v1/llm/accounts/import-models-toml/apply` (the "Apply" button on the LLM Accounts
admin page), which reads `.models.toml` and upserts those two tables
(`server/api/llmimport/models_toml.go`, `server/api/llmadminhandler/handler.go:78`).
`.models.toml` **is** rsynced to this box on every deploy
(`2026072401-devdoc-deploy-production.md`, the `rsync -avz ... .models.toml ...` step), but
nothing in the deploy runbook or in this bring-up doc ever calls the import endpoint. Since
this box's Postgres (`chenweb-paradedb` / `miner`, §1) is its own dedicated, freshly-migrated
database — separate from wherever the import was previously run by hand — the two tables here
start out empty (or missing whichever profile was added most recently). The lookup in
`resolveAccountProfileIDs` (`llmusage/sink.go`) matches on the exact
`(provider, base_url, api_key, profile_name-or-model_name)` tuple, so any `.models.toml`
profile never imported into *this* DB will always miss.

**Impact:** cosmetic only, not fatal — LLM calls keep working. The LLM Admin dashboards
(`llmreporthandler`: `/llm/reports/daily`, `/llm/summary/today`, `/llm/balances/current`) and
`llmreconcile` will under-count or miss this box's usage until the import is run.

**Fix (run once — and again any time `.models.toml` changes, e.g. a new model/profile or a
rotated API key; it is not automatic on deploy or on `chenweb` startup).** Auth on this box is
Kratos-session-based end to end (`shared/go/authmiddleware/auth.go` — the legacy `session_id`
cookie path is dead code), so the simplest way is the built-in UI, not curl:

1. Log into `https://onto.bzton.cn` as a sysadmin.
2. **home3 → System Admin → LLM Accounts** (`web/src/lib/components/home3/llm-accounts-view.svelte`,
   menu id `sysadmin-llm-accounts`).
3. Click **Import** (calls the preview endpoint, no writes) to see what it found, then
   **Apply** (`accounts_imported`/`profiles_imported` counts come back in the response).

If curl is preferred, don't hand-extract the Kratos cookie — while logged in on that page, open
DevTools → Network, find any XHR to `onto.bzton.cn`, and **Copy as cURL**; swap the URL for:
```
POST https://onto.bzton.cn/api/v1/llm/accounts/import-models-toml         # preview, no writes
POST https://onto.bzton.cn/api/v1/llm/accounts/import-models-toml/apply   # applies it
```
(note the `/api/v1/` prefix — `apiGroup := e.Group("/api/v1")` in `routes.go:286`, guarded by
`authmiddleware.AuthMiddleware`).

**Verify:**
```bash
docker exec chenweb-paradedb psql -U admin -d miner -tAc \
  "select account_name, provider, base_url from llm_account"
docker exec chenweb-paradedb psql -U admin -d miner -tAc \
  "select profile_name, model_name from llm_account_model_profile"
# the WARN should stop appearing for profiles that are now imported:
journalctl -u doc-processor -f | grep -i 'MID-20260708-01'
```

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
env LC_ALL=C LANG=C su -c 'systemctl restart <unit>'        # chenweb | kratos | nats-server | doc-service | doc-processor | parser-result-converter | pdf-parser
systemctl status <unit>
journalctl -u <unit> -n 100 --no-pager                       # -f to follow; no sudo needed to read
```

Ordered full restart (after changing `.env` / `kratos.env` / `config.local.toml` / the vhost):
```bash
env LC_ALL=C LANG=C su -c '
  systemctl restart nats-server kratos && sleep 3 &&
  systemctl restart chenweb doc-service doc-processor parser-result-converter pdf-parser && sleep 3 &&
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

All of `nats-server`, `kratos`, `chenweb`, `doc-service`, `doc-processor`,
`parser-result-converter`, `pdf-parser`, `nginx`, `docker` are `enabled`; the two Postgres
containers are `--restart unless-stopped`. A clean reboot brings the entire stack back with
no manual action. Verify afterwards with the "check everything" block above.

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
