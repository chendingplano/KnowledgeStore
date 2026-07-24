# How to Build and Deploy a Production System
**Date:** 2026-07-24 (updated 2026-07-24 after first full bring-up on staging)
**Scope:** Deploy `ChenWeb` — Go backend + Kratos (auth) + NATS/JetStream + Postgres/ParadeDB + the Python `pdf-parser`/MinerU service — to a Linux server (Ubuntu 20.04 LTS or newer), built from a MacMini. Target reference machine in this doc: `192.168.29.96` (ssh port `8822`, user `cding`).

**Audience:** This doc is written so both a human and Claude Code can follow it end-to-end on a brand-new box with no prior state. Every gotcha below was hit for real on a fresh Ubuntu 20.04 machine — follow the order given, it avoids most of the trial-and-error.

## Overview

ChenWeb is not just one Go binary. A full deployment needs, in dependency order:

1. **Postgres for Kratos** — Ubuntu's stock PostgreSQL (12) is fine for this.
2. **Postgres for ChenWeb's own data (`miner` db)** — **must** be Postgres 14+ with the `pgvector` and ParadeDB `pg_search` extensions. Ubuntu 20.04's stock PG12 is **not sufficient** (see §2).
3. **NATS server with JetStream** — no packaged install exists anywhere in this workspace; install the binary directly.
4. **Ory Kratos** — built from source, its own Postgres database, its own migrations.
5. **The ChenWeb Go binary** — cross-compiled on the Mac, frontend embedded at build time.
6. **The `pdf-parser` Python service** (+ MinerU) — separate from the Go binary, optional but part of the full system.

None of these have an existing Docker Compose or one-shot install script in this workspace. This doc is that script, in prose form.

## 1. Prepare the Linux Environment

### 1.1 Target (Linux) System

Version: Ubuntu 20.04 LTS (focal). Confirm resources are adequate — ParadeDB's auto-tuning (§2.2) scales its config to detected CPU/RAM, so more of both directly improves performance.

### 1.2 Docker (needed for ParadeDB, §2.2)

```bash
# Usually already present on shared/staging boxes — check first:
docker --version
docker compose version
```

If missing, install Docker CE per Docker's official Ubuntu 20.04 instructions.

**Gotcha:** a non-root user needs to be in the `docker` group to run `docker` without `sudo`:

```bash
sudo usermod -aG docker $(whoami)
```

A **new SSH connection** (not just a new shell) picks up the updated group — no reboot needed.

**Gotcha:** if this box already runs other Docker workloads (it's common on shared staging machines), check `docker ps` first and pick container names/ports that don't collide. On `192.168.29.96` there were already Dify, AgentGPT, and unrelated `postgres`/`mysql` containers running.

### 1.3 PostgreSQL — two separate instances are required

#### 1.3.1 Native PostgreSQL 12 (Kratos only)

```bash
sudo apt-get install -y postgresql
sudo systemctl start postgresql
sudo systemctl enable postgresql   # run once — auto-starts on every reboot
```

This instance is used **only by Kratos**. Kratos has no pgvector/ParadeDB dependency, so stock PG12 is fine for it.

**Note:** the pgdg `focal-pgdg` apt repo returns 404 as of 2026-07 — don't try to add it for a newer Postgres version here; use the Docker route in §1.3.2 instead for anything that needs a modern Postgres.

#### 1.3.2 ParadeDB (Postgres 18 + pgvector + pg_search) for ChenWeb's `miner` database — **mandatory, not optional**

**Why:** `ChenWeb/server/api/kbhandler/search_registry.go` defaults `SEARCH_LEXICAL_BACKEND` to `paradedb` (see ADR `2026061103-adr-paradedb-mandatory.md`), and the `kb` schema has `embedding vector(1536)` columns with `hnsw` indexes and `USING bm25` indexes throughout (`kb.search_artifacts_*`, `kb.entities`, `kb.metrics`, etc. — 81 tables, 61 functions in the schema as of 2026-07). None of this runs on stock PG12. ParadeDB (`pg_search`) generally requires Postgres 14+.

Rather than compiling Postgres+pgvector+pg_search from source on Ubuntu 20 (no existing recipe in this workspace, and ParadeDB isn't in nixpkgs-for-Linux the way it is on the Mac's nix-darwin setup — see `nix/modules/darwin/default.nix`), use ParadeDB's official Docker image, which bundles everything prebuilt:

```bash
docker pull paradedb/paradedb:latest

docker run -d \
  --name chenweb-paradedb \
  --restart unless-stopped \
  -e POSTGRES_USER=admin \
  -e POSTGRES_PASSWORD='yourpassword' \
  -e POSTGRES_DB=miner \
  -p 5433:5432 \
  -v chenweb_paradedb_data:/var/lib/postgresql \
  paradedb/paradedb:latest
```

**Gotchas:**
- Use a **different host port** (`5433` here) from the native PG12 instance (`5432`) — don't try to make ChenWeb and Kratos share one Postgres.
- The volume mount **must be `/var/lib/postgresql`**, not `/var/lib/postgresql/data` — this image (based on Postgres 18's docker-library convention) expects the parent dir so it can lay out `PG_VERSION`-named subdirectories. Mounting `.../data` directly produces a "Counter to that, there appears to be PostgreSQL data in: ... (unused mount/volume)" error and the container restart-loops.
- The `POSTGRES_USER` becomes a Postgres **superuser** inside this container — unlike the native PG12 instance, you will **not** need `sudo -u postgres` for `CREATE DATABASE`/`CREATE EXTENSION` here. `pg_search` and `vector` extensions are pre-installed and auto-created in the `POSTGRES_DB` on first boot.
- `gen_random_uuid()` works natively on Postgres 18 (no `pgcrypto` extension needed) — ChenWeb's table-creation code calls it directly.
- Create the autotester database too (see §5.2 for why it's required):
  ```bash
  psql -h 127.0.0.1 -p 5433 -U admin -d postgres -c "CREATE DATABASE miner_autotester OWNER admin;"
  ```

### 1.4 NATS server with JetStream

No package, no Docker Compose entry, no mise task exists anywhere in the workspace for this — install the binary directly:

```bash
mkdir -p ~/bin
curl -sL -o ~/bin/nats-server \
  https://github.com/nats-io/nats-server/releases/download/vX.Y.Z/nats-server-vX.Y.Z-linux-amd64.tar.gz
# (fetch the actual latest release tarball, extract, and copy the `nats-server` binary to ~/bin)
chmod +x ~/bin/nats-server

mkdir -p ~/nats-data
nohup ~/bin/nats-server -js -sd ~/nats-data -p 4222 > ~/.cache/nats-server.log 2>&1 &
disown
```

`ChenWeb`, `pdf-parser`, and the doc-review pipeline all default to `NATS_URL=nats://127.0.0.1:4222` if unset, so no further config is needed as long as it's running on that port on the same host.

The `nohup` start above is fine for a quick smoke test; for anything that needs to survive a reboot, use the systemd unit in §1.7 instead (it supersedes this).

### 1.5 Goose

Goose is a **Go library** (`github.com/pressly/goose/v3`), wired into the ChenWeb binary itself (`shared/go/api/goose/goose.go`) — migrations run **automatically at ChenWeb startup**, not as a separate service. There is nothing to "install" for this to work.

A standalone `goose` CLI is only useful for manually inspecting/running migrations outside the app. If wanted:

```bash
mkdir -p ~/bin
curl -sL -o ~/bin/goose https://github.com/pressly/goose/releases/download/v3.26.0/goose_linux_x86_64
chmod +x ~/bin/goose
```

(Match the version to `shared/go/go.mod`'s `github.com/pressly/goose/v3` pin.)

### 1.6 Ory Kratos (auth)

Kratos is **built from source** on the target machine (no pre-built binary distribution is used in this workspace — see `Kratos/CLAUDE.md`).

#### 1.6.1 Install Go + clone + build

```bash
curl https://mise.run | sh
echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc
source ~/.bashrc

mkdir -p ~/Workspace
cd ~/Workspace
mise use -g go@latest    # installs a Go toolchain managed by mise, no system apt package needed

git clone https://github.com/chendingplano/Kratos.git   # or rsync from the Mac excluding secrets — see below
```

If rsyncing instead of cloning (simpler if the GitHub repo needs auth), **exclude** `mise.local.toml` (it holds production secrets and the production domain) and any pre-built `src/kratos/kratos` binary (rebuild per-arch):

```bash
rsync -avz -e "ssh -p 8822" \
  --exclude mise.local.toml --exclude 'src/kratos/kratos' \
  --exclude node_modules --exclude kratos-selfservice-ui-node --exclude .git \
  ~/Workspace/Kratos/ cding@<host>:~/Workspace/Kratos/
```

Build:

```bash
cd ~/Workspace/Kratos
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
mise trust
cd src/kratos
GOWORK=off go build -o kratos .
```

#### 1.6.2 Write a fresh, non-production `mise.local.toml`

**Do not copy the Mac's `mise.local.toml` as-is** — it has real Resend/SMTP credentials, real Google OAuth secrets, and points `SERVE_PUBLIC_BASE_URL`/CORS/return-URLs at the live production domain. For a new/staging box, generate fresh secrets and point everything at the new host's IP:

```bash
openssl rand -base64 32    # -> SECRETS_COOKIE_0
openssl rand -base64 24 | cut -c1-32   # -> SECRETS_CIPHER_0
```

Minimal working `~/Workspace/Kratos/mise.local.toml` (adjust `<HOST>`, `<PORT-of-ChenWeb-backend>` for the new box):

```toml
[env]
DSN = "postgres://admin:yourpassword@127.0.0.1:5432/kratos?sslmode=disable"
SECRETS_COOKIE_0 = "<generated>"
SECRETS_CIPHER_0 = "<generated>"
COURIER_SMTP_CONNECTION_URI = "smtp://user:pass@127.0.0.1:1025/"   # placeholder — real email won't send; see §8
SELFSERVICE_METHODS_OIDC_CONFIG_PROVIDERS_0_MAPPER_URL = "file:///home/<user>/Workspace/Kratos/kratos/google_mapper.jsonnet"
IDENTITY_SCHEMAS_0_URL = "file:///home/<user>/Workspace/Kratos/kratos/identity.schema.json"

GOOGLE_OAUTH_CLIENT_ID = "not-configured"      # placeholder — Google login won't work; see §8
GOOGLE_CLIENT_SECRET = "not-configured"
GOOGLE_OAUTH_REDIRECT_URL = "http://<HOST>:<PORT-of-ChenWeb-backend>/auth/google/callback"

KRATOS_BIN = "./src/kratos/kratos"

SERVE_PUBLIC_BASE_URL = "http://<HOST>:4433/"
SERVE_ADMIN_BASE_URL = "http://127.0.0.1:4434/"   # admin API stays loopback-only, always

SERVE_PUBLIC_CORS_ALLOWED_ORIGINS_0 = "http://<HOST>:<PORT-of-ChenWeb-backend>"
SERVE_PUBLIC_CORS_ALLOWED_ORIGINS_1 = "http://127.0.0.1:<PORT-of-ChenWeb-backend>"
SERVE_PUBLIC_CORS_ALLOWED_ORIGINS_2 = "http://localhost:<PORT-of-ChenWeb-backend>"
# indices 3-6: fill with any other origins that need to reach Kratos (e.g. a dev frontend port)

SELFSERVICE_DEFAULT_BROWSER_RETURN_URL = "http://<HOST>:<PORT-of-ChenWeb-backend>/oauth/callback"
SELFSERVICE_ALLOWED_RETURN_URLS_0 = "http://<HOST>:<PORT-of-ChenWeb-backend>"
# ... indices 1-10 — kratos.yml declares exactly 11 array slots for both the CORS
# origins and the return URLs, and env overrides can only patch an EXISTING index,
# never extend the array (confirmed by a live "return_to URL is not allowed" failure
# 2026-07-15). Every index must be given a value, even if you duplicate one.

SELFSERVICE_FLOWS_ERROR_UI_URL = "http://<HOST>:<PORT-of-ChenWeb-backend>/error"
SELFSERVICE_FLOWS_SETTINGS_UI_URL = "http://<HOST>:<PORT-of-ChenWeb-backend>/set-password"
SELFSERVICE_FLOWS_RECOVERY_UI_URL = "http://<HOST>:<PORT-of-ChenWeb-backend>/recovery"
SELFSERVICE_FLOWS_VERIFICATION_UI_URL = "http://<HOST>:<PORT-of-ChenWeb-backend>/verification"
SELFSERVICE_FLOWS_VERIFICATION_AFTER_DEFAULT_BROWSER_RETURN_URL = "http://<HOST>:<PORT-of-ChenWeb-backend>/login?verified=true"
SELFSERVICE_FLOWS_LOGOUT_AFTER_DEFAULT_BROWSER_RETURN_URL = "http://<HOST>:<PORT-of-ChenWeb-backend>/login"
SELFSERVICE_FLOWS_LOGIN_UI_URL = "http://<HOST>:<PORT-of-ChenWeb-backend>/login"
SELFSERVICE_FLOWS_REGISTRATION_UI_URL = "http://<HOST>:<PORT-of-ChenWeb-backend>/registration"

SESSION_COOKIE_DOMAIN = "<HOST>"     # bare IP works if the browser hits Kratos at that same IP
SESSION_COOKIE_SECURE = "false"      # "true" only once this is behind real TLS
```

#### 1.6.3 Create the Kratos database and required extensions

On the **native PG12** instance (§1.3.1):

```bash
sudo -u postgres psql -c "CREATE DATABASE kratos OWNER admin;"
# The 'admin' role must already exist (created when Postgres itself was provisioned).
# If it doesn't have CREATEDB, the two commands above (run as the postgres superuser) are required.

# Kratos's identity-search migration needs both of these on PG12 — install as postgres superuser:
sudo -u postgres psql -d kratos -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;"
sudo -u postgres psql -d kratos -c "CREATE EXTENSION IF NOT EXISTS btree_gin;"
```

#### 1.6.4 Migrate and start

```bash
cd ~/Workspace/Kratos
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
mise run migrate
# resumable — if it fails partway (e.g. on a missing extension above), fix the
# extension and re-run; already-applied migrations are skipped automatically.

nohup mise run start-kratos > ~/.cache/kratos.log 2>&1 &
disown
```

`mise run start-kratos` runs Kratos with `--dev` (relaxed CSRF/cookie-secure checks) — appropriate for a box without TLS in front of it. Use `mise run start-kratos-prod` only once this is behind real HTTPS. As with NATS above, the `nohup` here is just for the initial smoke test — §1.7's `kratos.service` (same `mise run start-kratos` command, running under systemd) is what should actually be running afterward.

Verify:

```bash
curl http://127.0.0.1:4433/health/alive   # {"status":"ok"}
curl http://127.0.0.1:4434/health/alive   # {"status":"ok"}
```

### 1.6.5 Setting up Google OAuth (real Google sign-in)

Google sign-in touches **two** separate places, both driven by the *same* Google Cloud OAuth client — it is not enough to configure just one:

1. **Kratos's OIDC provider** (`kratos/kratos.yml:83-94`) — this is what actually runs the OAuth dance when `AUTH_USE_KRATOS=true` (the deployed default, §3). `client_id`/`client_secret`/`mapper_url` are `set-via-env`, resolved from `SELFSERVICE_METHODS_OIDC_CONFIG_PROVIDERS_0_CLIENT_ID`/`_CLIENT_SECRET`/`_MAPPER_URL` — but per `Kratos/mise.toml:80-97`, `mise run start-kratos`/`start-kratos-prod` set those three by reading **`$GOOGLE_OAUTH_CLIENT_ID`** and **`$GOOGLE_CLIENT_SECRET`** out of Kratos's own `mise.local.toml`, so those two plain-named vars are what actually need setting there (not the `SELFSERVICE_METHODS_...` names directly).
2. **ChenWeb's legacy direct-OAuth code path** (`shared/go/api/auth/google.go:32-43`, wired up in `shared/go/api/router.go:38-44`) — only reachable when `AUTH_USE_KRATOS=false`, but it still unconditionally reads `GOOGLE_OAUTH_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_OAUTH_REDIRECT_URL` from ChenWeb's own `.env` at handler-construction time and logs an error if `GOOGLE_OAUTH_REDIRECT_URL` is unset — so set these there too even if Kratos is the active path, for parity and so the logged error doesn't show up.

**Steps:**

1. In [Google Cloud Console](https://console.cloud.google.com/apis/credentials) (same project used for the Mac's `dingbo.bzton.cn` client, or a new one for this box), create/reuse an **OAuth 2.0 Client ID** of type "Web application".
2. Add **both** of these as Authorized redirect URIs (Google will only reject at request-time if the one actually used is missing, but the second exists in code too — no reason not to register both):
   - `<SERVE_PUBLIC_BASE_URL>/self-service/methods/oidc/callback/google` — e.g. `http://<HOST>:4433/self-service/methods/oidc/callback/google` — **this is the one Google actually redirects to** when `AUTH_USE_KRATOS=true`, since `HandleGoogleLoginKratos` (`shared/go/api/auth/kratos.go:1801`) hands the whole flow to Kratos rather than using the `oauth2.Config` built in `google.go`.
   - The value you set for `GOOGLE_OAUTH_REDIRECT_URL` below (ChenWeb's own `/auth/google/callback`) — only exercised on the legacy path, harmless to register regardless.
3. Copy the Client ID and Client Secret.
4. Set in **`~/Workspace/Kratos/mise.local.toml`** (`[env]` block):
   ```toml
   GOOGLE_OAUTH_CLIENT_ID = "<client-id>.apps.googleusercontent.com"
   GOOGLE_CLIENT_SECRET = "<client-secret>"
   SELFSERVICE_METHODS_OIDC_CONFIG_PROVIDERS_0_MAPPER_URL = "file:///home/<user>/Workspace/Kratos/kratos/google_mapper.jsonnet"
   ```
   (The mapper — `kratos/google_mapper.jsonnet` — maps `email`/`given_name`/`family_name` claims into Kratos identity traits and **rejects unverified Google emails**; no changes needed there for a standard Google Workspace/Gmail account.)
5. Set in **`~/Workspace/ChenWeb/.env`**:
   ```bash
   GOOGLE_OAUTH_CLIENT_ID="<same client-id>.apps.googleusercontent.com"
   GOOGLE_CLIENT_SECRET="<same client-secret>"
   GOOGLE_OAUTH_REDIRECT_URL="http://<HOST>:<PORT-of-ChenWeb-backend>/auth/google/callback"
   ```
6. Restart Kratos (`sudo systemctl restart kratos`) — the OIDC config env vars are read at process start, no live reload.
7. Verify: visit `http://<HOST>:<PORT>/auth/google/login` in a browser — it should redirect through Google's consent screen and land back logged in. Check `journalctl -u kratos -n 50` if it instead errors — a `client_id` mismatch or unregistered redirect URI shows up there as `invalid_client`/`redirect_uri_mismatch` from Google's own error page, not a Kratos-side stack trace.

**Gotcha — outbound proxy.** If this box (or the Mac) sits behind an HTTP(S) proxy for outbound traffic (see the mitmproxy notes in §8), Kratos's own OAuth calls to `accounts.google.com`/`oauth2.googleapis.com` must bypass it — `Kratos/mise.toml:82-83` already sets `NO_PROXY`/`no_proxy` for exactly this reason when starting via `mise run start-kratos`. If a systemd `Environment=` block is ever used to launch Kratos directly (bypassing `mise run`), carry that `NO_PROXY` value over explicitly.

**Separately — `GOOGLE_GENERATIVE_AI_API_KEY` is not part of this OAuth setup.** It's a Gemini/Generative-AI API key (a plain Google Cloud API key, not an OAuth client), unrelated to Kratos login. As of 2026-07-24, `shared/go/api/llm/client.go:68-69` returns a `notImplementedClient` for `ProviderGemini` — no code in this workspace actually reads this env var yet. It's carried in the Mac's `mise.local.toml` for when Gemini support lands; there is nothing to configure for it on this box today beyond optionally copying the same value into `~/Workspace/ChenWeb/.env` for forward-compatibility. Get one at [Google AI Studio](https://aistudio.google.com/apikey) when it's actually needed.

### 1.6.6 Setting up SMTP (real outbound email for Kratos)

Kratos's courier (`kratos/kratos.yml:173-178`) sends verification/recovery/password-reset emails. This workspace's established pattern (see `Kratos/CLAUDE.md`, already used for the Mac/tax deployment) is **Resend's SMTP relay** — reuse it rather than standing up a separate email provider, since a verified sending domain (`miraitaxcpa.com`) already exists on the account.

**Steps:**

1. Get (or reuse) a Resend API key from the [Resend dashboard](https://resend.com/api-keys). Tax/Mirai already has `RESEND_API_KEY` configured per the workspace CLAUDE.md — the same key works here; Resend keys aren't tied to a single sending domain, just a single account.
2. Decide the from-address:
   - **Reuse `noreply@miraitaxcpa.com`** (already verified in Resend, zero extra setup) — fine as a placeholder identity even though the domain doesn't match `dingbo.bzton.cn`; recipients only see the Kratos-generated email content, not a ChenWeb UI.
   - **Or verify a `dingbo.bzton.cn` (sub)domain in Resend** (Domains → Add Domain → add the TXT/MX/DKIM records it gives you at your DNS provider, wait for verification — usually minutes, can take up to 72h) if a matching from-address matters for this deployment.
3. Set the courier config. `connection_uri` is already `set-via-env` (`COURIER_SMTP_CONNECTION_URI`), but `from_address`/`from_name` are **hardcoded literals** in `kratos.yml:177-178`, not `set-via-env` — Kratos's native env-override mechanism (any config key can be set via its underscore-joined, uppercased path) still works even though the YAML doesn't use the `set-via-env` marker for these two, since that marker is just a convention in this repo, not something Kratos itself checks. Set in `~/Workspace/Kratos/mise.local.toml`:
   ```toml
   COURIER_SMTP_CONNECTION_URI = "smtp://resend:<RESEND_API_KEY>@smtp.resend.com:587/"
   COURIER_SMTP_FROM_ADDRESS = "noreply@miraitaxcpa.com"   # or your newly-verified dingbo.bzton.cn address
   COURIER_SMTP_FROM_NAME = "ChenWeb"                       # or whatever's appropriate for this deployment
   ```
   (The literal username in the connection URI is always the string `resend`, regardless of account — Resend's SMTP relay auth convention; the password is the API key.)
4. **Gotcha — `template_override_path` is a hardcoded Mac path that silently "works" on the Mac for a filesystem reason that doesn't hold on Linux.** `kratos.yml:174` hardcodes `template_override_path: /Users/cding/Workspace/kratos/kratos/templates` — lowercase `kratos`, not `Kratos`. On the Mac's APFS volume (case-insensitive, case-preserving) this happens to resolve to the same directory as `/Users/cding/Workspace/Kratos/kratos/templates` (confirmed same inode) — so it has never actually been exercised as a real case mismatch. Ubuntu's ext4 **is** case-sensitive: the lowercase path will not exist on this box, and Kratos will either fail to start or (depending on version) silently fall back to its built-in default templates instead of this repo's customized ones. Fix by overriding via env in `mise.local.toml` (no need to touch the checked-in `kratos.yml`):
   ```toml
   COURIER_TEMPLATE_OVERRIDE_PATH = "/home/<user>/Workspace/Kratos/kratos/templates"
   ```
5. Restart Kratos (`sudo systemctl restart kratos`).
6. Verify: trigger a registration or "forgot password" flow at `http://<HOST>:4455/registration` (or whatever the self-service UI is bound to) and confirm the email arrives. `journalctl -u kratos -n 100` shows courier delivery attempts/errors (SMTP auth failures, connection refusals) if it doesn't.

**Fallback for non-production/testing** (no real email needed, e.g. a throwaway staging box): point `COURIER_SMTP_CONNECTION_URI` at a local [Mailslurper](https://github.com/mailslurper/mailslurper) instance instead — catches all outbound mail in a local web UI without sending anything real. This is what the placeholder `smtp://user:pass@127.0.0.1:1025/` in §1.6.2's minimal config assumes, except nothing is actually listening on `127.0.0.1:1025` until Mailslurper (or an equivalent dev SMTP catcher) is actually running there.

**About [Resend dashboard](https://resend.com/api-keys)
Resend offers a permanent free tier, making it a popular choice for side projects and early-stage 
applications. You can use the service completely free without needing a credit card to sign up. [1, 2] 

## Free Tier Limits
The free tier separates your usage by email type: [3] 

* Transactional Emails: Send up to 3,000 emails per month, with a daily cap of 100 emails per day.
* Marketing Emails: Store up to 1,000 contacts and send unlimited marketing broadcasts to them.
* Domain Limits: Connect up to 1 custom domain.
* Data Retention: Access 30 days of email logs and tracking history. [4, 5] 

## Paid Plans
If your application grows and you exceed these limits, you will need to upgrade to a paid tier: [6] 

* Pro Plan ($20/month): Removes the daily limit, increases your volume to 50,000 emails per month, and lets you add up to 10 domains.
* Scale Plan ($90/month): Covers up to 100,000 emails per month and allows up to 1,000 domains. [4] 

[1] [https://resend.com](https://resend.com/blog/new-free-tier)
[2] [https://clarodigi.com](https://clarodigi.com/blog/resend-vs-postmark-vs-brevo-transactional-email/)
[3] [https://www.sequenzy.com](https://www.sequenzy.com/blog/best-email-tools-with-free-tier)
[4] [https://resend.com](https://resend.com/pricing)
[5] [https://resend.com](https://resend.com/docs/knowledge-base/account-quotas-and-limits)
[6] [https://merchantsbancard.com](https://merchantsbancard.com/free-pos-software-review/)

### 1.7 Caddy (optional — TLS termination / reverse proxy)

Caddy is not required for a basic bring-up (the Go binary binds directly to `0.0.0.0:8080`). Add it when you need HTTPS or want a reverse proxy in front of the Go server.

**Gotcha on Ubuntu 20.04:** Caddy's official installation docs say to run:

```bash
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
```

On Ubuntu 20.04, `debian-keyring` and `debian-archive-keyring` do not exist in Ubuntu's repos — they are Debian-only packages. This command will error with `E: Package 'debian-keyring' has no installation candidate`. Skip those two packages and install the Caddy signing key directly instead:

```bash
sudo apt install -y curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
  | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
  | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install -y caddy
```

This is equivalent to the official instructions — `debian-keyring`/`debian-archive-keyring` are only used on Debian to verify the Cloudsmith key chain; Ubuntu does not need them.

### 1.8 Running everything under systemd (do this — `nohup` does not survive a reboot)

The `nohup ... & disown` commands shown above (§1.4, §1.6.4, and the ChenWeb start command in §3) are fine for a quick first test, but nothing started that way survives a reboot. Use systemd units instead. All three need `sudo` to install; `docker` and `postgresql` are already `systemctl enable`d by their own package installs, so only these three need units.

```bash
sudo tee /etc/systemd/system/nats-server.service > /dev/null <<'UNIT'
[Unit]
Description=NATS Server with JetStream
After=network.target

[Service]
Type=simple
User=cding
WorkingDirectory=/home/cding
ExecStart=/home/cding/bin/nats-server -js -sd /home/cding/nats-data -p 4222
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

sudo tee /etc/systemd/system/kratos.service > /dev/null <<'UNIT'
[Unit]
Description=Ory Kratos (ChenWeb auth)
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=cding
WorkingDirectory=/home/cding/Workspace/Kratos
ExecStart=/home/cding/.local/bin/mise run start-kratos
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
# ExecStart intentionally runs `mise run start-kratos` rather than the kratos
# binary directly — mise resolves the env vars from mise.toml/mise.local.toml
# (§1.6.2) itself; reimplementing that env resolution inline in the unit file
# would just duplicate mise.local.toml and drift out of sync with it.

sudo tee /etc/systemd/system/chenweb.service > /dev/null <<'UNIT'
[Unit]
Description=ChenWeb Go backend
After=network.target docker.service nats-server.service kratos.service
Wants=docker.service nats-server.service kratos.service

[Service]
Type=simple
User=cding
WorkingDirectory=/home/cding/Workspace/ChenWeb
Environment=SHARED_LIB_CONFIG_DIR=/home/cding/Workspace/shared/libconfig.toml
ExecStart=/home/cding/Workspace/ChenWeb/server-linux serve --dir /home/cding/Workspace/ChenWeb/Data
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
# The Environment= line is required — see §3's table on which vars must be real
# process env vars vs. which can live in .env. Everything else ChenWeb needs
# comes from ./.env (WorkingDirectory makes "./.env" resolve correctly) and from
# config.toml/config.local.toml.

sudo systemctl daemon-reload

# stop any manually-started (nohup) instances first so the ports are free:
pkill -f "nats-server -js"; pkill -f "kratos serve"; pkill -f "server-linux serve"
sleep 2

sudo systemctl enable --now nats-server
sudo systemctl enable --now kratos
sudo systemctl enable --now chenweb
```

Verify:

```bash
systemctl is-active nats-server kratos chenweb   # each should print "active"
systemctl is-enabled nats-server kratos chenweb  # each should print "enabled"
journalctl -u chenweb -n 50 --no-pager            # check for panics/errors
```

### 1.8 Caddy (reverse proxy for the production domain)

`ChenWeb/Caddyfile` (checked in) is hardcoded to `dingbo.bzton.cn`, reverse-proxying `/kratos/*` → `:4433` and everything else → `:8080`. The end goal for `192.168.29.96` is to actually host that domain (DNS gets cut over once everything here is verified) — so deploy Caddy with the **same** Caddyfile as the Mac, not a bare-IP variant.

**Gotcha — port conflicts on a shared box.** Before installing, check what's already on 80/443:

```bash
ss -tlnp | grep -E ":80 |:443 "
docker ps --format "{{.Names}}: {{.Ports}}"
```

On `192.168.29.96` this found: port 80 was just Ubuntu's default nginx placeholder page (safe to stop), and port 443 was a **live** `docker-nginx-1` container — Dify's own production nginx, with real certbot-issued certs (`/home2/dify/docker/...`). Don't touch a port owned by something else without knowing what's behind it. In this case Dify was being retired anyway, so its containers were `docker stop`'d (not removed — reversible with `docker start <name>`):

```bash
docker stop docker-nginx-1 docker-worker-1 docker-api-1 docker-ssrf_proxy-1 \
  docker-sandbox-1 docker-weaviate-1 docker-web-1 docker-redis-1 docker-db-1
```

(Leave unrelated containers alone — e.g. this box also runs AgentGPT under different container names.)

Install:

```bash
sudo systemctl stop nginx
sudo systemctl disable nginx

sudo apt install -y curl gnupg apt-transport-https
# Note: do NOT include debian-keyring/debian-archive-keyring — despite appearing
# in some copies of Caddy's official install snippet, they aren't on Ubuntu's
# default repos and aren't actually needed; gnupg (for `gpg --dearmor`) is
# the only real prerequisite beyond curl.
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update   # the pre-existing broken focal-pgdg source (§1.3.1) will still
                   # error here — that's unrelated and harmless, Caddy's own repo
                   # fetches fine regardless
sudo apt install -y caddy

sudo cp ChenWeb/Caddyfile /etc/caddy/Caddyfile
sudo systemctl enable --now caddy
```

The apt package ships its own systemd unit (runs as system user `caddy`, not your login user — `journalctl -u caddy` needs `sudo` to show anything). Verify:

```bash
systemctl is-active caddy   # active
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:80/    # 308 (redirect to https)
```

Port 443 will fail its TLS handshake (`curl -k https://127.0.0.1/` → connection/TLS error) until DNS actually points `dingbo.bzton.cn` at this box — Caddy can't complete ACME cert issuance for a domain that doesn't resolve here yet. That's expected, not a misconfiguration; it self-resolves at DNS cutover.

## 2. Build ChenWeb on Mac and Deploy

```bash
cd ~/Workspace/ChenWeb
```

### 2.1 Build the frontend (Mac only, uses Bun)

```bash
mise build-web
```

### 2.2 Cross-compile for Linux amd64

```bash
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 \
  go build -buildvcs=false \
  -o .cache/server-linux \
  ./server/cmd/deepdoc/.
```

### 2.3 Deploy to Linux — directory convention

**Everything on the Linux box lives under `~/Workspace/`, mirroring the Mac's own layout exactly** (`~/Workspace/{ChenWeb,Kratos,ThirdParty,shared}`). This wasn't the original plan — the very first version of this doc deployed just the binary + `config.toml` to a separate `~/chenweb/server/` directory, on the theory that a compiled Go binary needs no source tree. That held up right until Kratos (built from source on the target machine — §1.6) and MinerU/`pdf-parser` (Python, no such thing as "just ship a binary" — §5) entered the picture and needed real source trees somewhere. Rather than inventing a second directory convention for those, `~/chenweb/` was retired (2026-07-24) and folded into `~/Workspace/ChenWeb/` alongside them. One benefit beyond tidiness: `parser_mineru.py`'s default MinerU CLI path is hardcoded to `~/Workspace/ThirdParty/mineru/...` (not configurable via `config.toml`), so `~/Workspace` was already a hard requirement for that piece — this just makes it the requirement for everything, consistently.

Note this differs slightly from the Mac's own ChenWeb repo: there, `config.toml`/`.env` sit at the repo root alongside the actual Go/Svelte source. On Linux, `~/Workspace/ChenWeb/` holds the deploy artifacts (binary, config, migrations, `Data/`) at its root and `python/pdf-parser` as a real source subdirectory — no Go/Svelte source is ever present, since the binary is cross-compiled and the frontend is embedded at build time (§2.1–2.2).

The Go binary and `config.toml` alone are **not enough** — the migration SQL directories and the shared library config also have to be present on disk (they're read from the filesystem at runtime, not embedded in the binary):

```bash
rsync -P -e "ssh -p 8822" .cache/server-linux cding@<host>:~/Workspace/ChenWeb/server-linux
rsync -P -e "ssh -p 8822" config.toml cding@<host>:~/Workspace/ChenWeb/config.toml
rsync -avz -e "ssh -p 8822" project_migrations shared_migrations cding@<host>:~/Workspace/ChenWeb/
rsync -avz -e "ssh -p 8822" ~/Workspace/shared/libconfig.toml cding@<host>:~/Workspace/shared/libconfig.toml
```

Run everything from `~/Workspace/ChenWeb/` as the working directory on Linux — `config.toml`, `.env`, `project_migrations/`, and `shared_migrations/` are all resolved relative to cwd (or its parents, for the migration dirs — see `server/cmd/config/config.go:resolveMigrationDir`).

### 2.4 doc-processor and parser-result-converter (NATS workers)

These two `server/cmd/*` binaries are NATS consumers, not HTTP servers — `doc-processor` does chunking/extraction/doc-review, `parser-result-converter` turns MinerU/pdf-parser output into line-files. Both call the exact same `config.LoadConfig`/`ApiUtils.LoadConfig` path as the main server, so they need the same base config (§3) plus a large additional block: LLM model routing (`*_MODEL_NAME`/`*_MODEL_FALLBACK`, ~30 vars), prompt file references (`PROMPT_DIR` + ~25 `*_PROMPT` filenames), embedding config, and doc-review template paths. There is no shortcut here — copy the full relevant block from the Mac's `mise.local.toml`, translating `/Users/cding/...` paths to their Linux equivalents, into `~/Workspace/ChenWeb/.env`. This also requires rsyncing supporting files/directories that aren't part of the Go binary:

```bash
cd ~/Workspace/ChenWeb
rsync -avz -e "ssh -p 8822" prompts .models.toml docs/doc-templates cding@<host>:~/Workspace/ChenWeb/
```

and creating the directories referenced by `DATA_REVIEW_REPORTS`/`STAGING_DIR`/etc. under `~/Workspace/ChenWeb/Data/`.

**Real API keys are required** for these to function (not just start) — `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `DASHSCOPE_API_KEY` from the Mac's `mise.local.toml`. Decide deliberately whether to reuse the same production keys or provision separate ones before copying them — this is a different class of decision than the Kratos OAuth/SMTP placeholders (real, billable credentials, not just "won't work until configured").

Cross-compile and deploy exactly like the main binary (§2.2–2.3):

```bash
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -buildvcs=false -o .cache/doc-processor-linux ./server/cmd/doc-processor/.
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -buildvcs=false -o .cache/parser-result-converter-linux ./server/cmd/parser-result-converter/.
rsync -P -e "ssh -p 8822" .cache/doc-processor-linux cding@<host>:~/Workspace/ChenWeb/doc-processor-linux
rsync -P -e "ssh -p 8822" .cache/parser-result-converter-linux cding@<host>:~/Workspace/ChenWeb/parser-result-converter-linux
```

Their default `config.toml` path (`../../../config.toml`, relative to `server/cmd/<name>/`, matching the `go run .`/mise-task dev workflow) is wrong once cross-compiled and run from `~/Workspace/ChenWeb/` — override explicitly via env var (`DOC_PROCESSOR_CONFIG=./config.toml` / `PARSER_RESULT_CONVERTER_CONFIG=./config.toml`), same idea as `SHARED_LIB_CONFIG_DIR` needing to be a real env var, not just present in `.env` (§3).

**⚠️ Real bug hit on first boot — JetStream stream-name collision.** Both binaries fall back to the *same* hardcoded default stream name (`pdf-parsed-events`, from `normalizeStreamName`'s fallback in `server/api/file-converters/jetstream.go`) when their respective `*_STREAM` env vars are unset — despite covering different subjects (`kb.pdf.start-doc-processing` for doc-processor's primary subject vs. `kb.pdf.parsed` for parser-result-converter). `EnsureStream` checks for a stream with the target *name* and treats its existence as success without verifying it actually covers the target *subject* — so whichever service starts first silently "wins" the name, and the second one fails at subscribe time with `nats: no stream matches subject`, even though `EnsureStream` itself reported no error. Avoid this by always setting **both** explicitly and differently:

```bash
DOC_PROCESSOR_EVENT_STREAM="doc-processor-start-events"
PARSER_RESULT_CONVERTER_STREAM="pdf-parsed-events"
```

If you hit this after the fact (streams already created wrong), delete the incorrectly-bound stream and restart both services — `EnsureStream` recreates cleanly:

```bash
nats stream rm pdf-parsed-events --server nats://127.0.0.1:4222 --force
sudo systemctl restart doc-processor parser-result-converter
```

(The `nats` CLI isn't installed by default — `curl -sL -o /tmp/nats-cli.zip https://github.com/nats-io/natscli/releases/download/v0.4.0/nats-0.4.0-linux-amd64.zip`, unzip, copy the `nats` binary to `~/bin/`. Genuinely useful for debugging JetStream — `nats stream ls`, `nats stream info <name>` — worth installing proactively rather than only when something breaks.)

Systemd units follow the same pattern as `chenweb.service` (§1.7) — `WorkingDirectory=/home/<user>/Workspace/ChenWeb`, `Environment=SHARED_LIB_CONFIG_DIR=...`, plus the one `*_CONFIG=./config.toml` override each needs; no HTTP port, so no `curl` health check — verify via `systemctl is-active` and `journalctl -u <unit>` showing `jetstream subscription active` for the expected subjects.

## 3. Configuration — what must be a real environment variable vs. what can go in `.env`

ChenWeb's `main.go` calls `godotenv.Load("./.env")` early, but **before that finishes, some config is already read from `os.Getenv` at Go package-`init()` time** (specifically, `ApiUtils.LoadLibConfig` is guarded by a `sync.Once` that appears to fire before `.env` is parsed). On the Mac, this isn't visible because these values come from **mise's `[env]` block** (`ChenWeb/mise.local.toml`), which the OS shell already has set before the binary even starts. When running the binary directly (no `mise run` wrapper) on a fresh Linux box, these must be **exported in the shell** (or wired into a systemd `Environment=` block — see §1.7's `chenweb.service`), not just placed in `.env`:

| Var | Required as | Why |
|---|---|---|
| `SHARED_LIB_CONFIG_DIR` | **real exported env var** | `LoadLibConfig`'s `sync.Once` fires before `.env` is loaded. Putting it only in `.env` silently no-ops: `LibConfig.SystemTableNames.*` all resolve to `""`, which causes a **hard crash** ("IDMgr table name is empty") plus silent non-fatal "Alarm"-level failures creating the `email_store`/`prompt_store`/`resources`/`icons`/`table_manager` tables (their names also come from this same config). |
| `APP_HOST`, `APP_PORT` | `.env` is fine | Read later in `ApiUtils.LoadConfig`, after `.env` is parsed — but still **mandatory**, panics if unset. |
| `PG_HOST`, `PG_PORT` | `.env` is fine | Same — mandatory, no config.toml fallback. |
| `PG_DB_NAME_AUTOTESTER` | `.env` is fine | Mandatory. `CreatePGDB` opens and pings a connection to this database at startup even though most of ChenWeb doesn't use it — the database must actually exist (§1.3.2 creates it). |
| `PROMPT_OPTIMIZER_ENCRYPTION_KEY` | `.env` is fine | Mandatory. Must be `base64` of exactly 32 raw bytes (AES-256-GCM key) — generate with `openssl rand -base64 32`. |
| `DATA_HOME_DIR`, `DATA_BACKUP_DIR` | `.env` is fine | Not mandatory (code falls back to treating paths as relative-to-cwd if unset), but several handlers (`videohandler`, `imagehandler`, `icons`) resolve storage paths relative to this — leaving it unset works but silently scatters files relative to whatever cwd happens to be at the time. Set it explicitly. On the Mac this is `/Users/cding/Apps/SemOS` via `mise.local.toml`; on Linux, point it at a real directory under the deploy root and `mkdir -p` it first. |

Example working `~/Workspace/ChenWeb/.env` (values are the ones used against `192.168.29.96` — adjust host/port/secrets per machine):

```bash
APP_BASE_URL="http://<HOST>:8080"
USE_POSTGRESQL=true
APP_ENV="staging"
SERVER_PORT="8080"
USE_EMBED_FRONTEND="true"

PG_USER_NAME="admin"
PG_PASSWORD="yourpassword"
PG_DB_NAME="miner"
PG_HOST="127.0.0.1"
PG_PORT="5433"                          # the ParadeDB container port, §1.3.2 — NOT 5432
PG_DB_NAME_AUTOTESTER="miner_autotester"

APP_HOST="<HOST>"
APP_PORT="8080"

AUTH_USE_KRATOS="true"
KRATOS_PUBLIC_URL="http://<HOST>:4433"   # must be browser-reachable, not 127.0.0.1 — it's
                                          # used both server-side (session validation) and
                                          # embedded in browser-facing logout redirect URLs
KRATOS_ADMIN_URL="http://127.0.0.1:4434" # loopback-only — fine as long as Kratos runs on
                                          # this same host

NATS_URL="nats://127.0.0.1:4222"

PROMPT_OPTIMIZER_ENCRYPTION_KEY="<openssl rand -base64 32>"

SCHEDULER_ENABLED="true"

DATA_HOME_DIR="/home/<user>/Workspace/ChenWeb/Data/SemOS"     # mkdir -p this first
DATA_BACKUP_DIR="/home/<user>/Workspace/ChenWeb/Data/Backup"  # mkdir -p this first
```

...and start it with `SHARED_LIB_CONFIG_DIR` exported (not just in `.env` — see table above):

```bash
cd ~/Workspace/ChenWeb
export SHARED_LIB_CONFIG_DIR="/home/<user>/Workspace/shared/libconfig.toml"
nohup ./server-linux serve --dir ~/Workspace/ChenWeb/Data > ~/.cache/chenweb.log 2>&1 &
disown
```

Again, this `nohup` form is only for the first smoke test before the migration work in §4 is done — once that's sorted, switch to `chenweb.service` under systemd (§1.7), which sets `SHARED_LIB_CONFIG_DIR` via `Environment=` instead.

`config.toml` itself needs a Linux-specific override for absolute Mac paths — create `config.local.toml` next to `config.toml` (there's a built-in merge for this, see `server/cmd/config/config.go:248-257`):

```toml
[app_info]
host = "0.0.0.0"     # bind externally, not just localhost

[llm]
archive_root = "/home/<user>/Workspace/ChenWeb/Data/llm-logs"   # was a /Users/... Mac path
```

(The `[pdf_parser]` section's Mac-specific paths — `python_bin`, `paddleocr_script`, `work_dir` — do **not** need overriding: that whole code path is currently commented out in `main.go`, so those values are unused. If it's ever re-enabled, override those too. `pdf-parser` runs as its own separate Python service instead — see §5.)

## 4. Bootstrapping the `kb` schema on a brand-new database

**Resolved 2026-07-25.** `project_migrations/` has `ALTER TABLE kb.*` statements going back to `20260420113000_create_kb_chunks_table.sql`, but until 2026-07-25 **no migration anywhere created `kb.inputs`, `kb.metrics`, or `kb.semantic_projections`** (`kb.provisions`, also named in earlier versions of this doc, turned out to have already been fixed on 2026-05-05 — `20260505000001_create_kb_provisions_table.sql` does create it). These tables predated the migration history — on the Mac's long-running dev database they've simply always existed. On a truly fresh database, migrations that `ALTER`/reference these tables failed outright (`relation "kb.inputs" does not exist`), which is what the dump-and-replay workaround below was for.

A real baseline migration now exists: `20260401000000_create_kb_baseline_tables.sql` creates all three with exactly the columns that predate this migration directory (verified column-by-column and constraint-by-constraint against the live dev database — not just "goose up succeeds," since a naive dump-the-final-shape approach would have gotten two things wrong: `kb.inputs.md5` is actually `VARCHAR(64)` on the live DB even though the migration that nominally adds it, `20260609000001_add_kb_inputs_md5.sql`, specifies `TEXT` — md5 is itself another phantom pre-existing column, its `ADD COLUMN IF NOT EXISTS` has always been a silent no-op; and `kb.metrics.input_record_id`/`kb.semantic_projections.input_record_id` have no foreign key to `kb.inputs` on the live database, so the baseline doesn't add one). One companion fix was needed: `20260507100001_rename_kb_metrics_extract_id_to_event_id.sql`'s `RENAME COLUMN extract_id TO event_id` is the only non-idempotent statement touching these three tables anywhere in the migration history (everything else is `ADD`/`DROP COLUMN IF [NOT] EXISTS`), so it's now guarded to skip when `extract_id` doesn't exist — safe to edit despite being long-applied everywhere, since goose never re-runs or diffs an already-applied migration's content.

**Verification method** (repeatable — worth re-running after adding new migrations that touch these tables): run the real `pressly/goose` CLI, pinned to the version in `shared/go/go.mod`, against a brand-new empty Postgres database with just the `vector`/`pg_search` extensions created, then diff `information_schema.columns` and `pg_constraint` for the affected tables against the live dev database:
```bash
go install github.com/pressly/goose/v3/cmd/goose@v3.26.0   # match shared/go/go.mod's pin
createdb -h 127.0.0.1 -U admin miner_fresh_test
psql -h 127.0.0.1 -U admin -d miner_fresh_test -c "CREATE EXTENSION IF NOT EXISTS vector; CREATE EXTENSION IF NOT EXISTS pg_search;"
cd project_migrations
goose postgres "host=127.0.0.1 user=admin password=... dbname=miner_fresh_test sslmode=disable" up
```
This is how a second, unrelated gap was caught in the same pass: `20260527000021_update_kb_doc_proc_logs_ms_used.sql` backfills `ms_used` from `start_time`/`end_time`, but `20260527000020_create_kb_doc_proc_logs.sql` never created those two columns — same root cause (columns that predated their table's own creating migration), just in a table that otherwise *was* properly migration-created. Fixed the same way: guarded the backfill to skip when the columns don't exist. All 152 migrations now run clean, end-to-end, from a genuinely empty database, with zero schema drift from the live dev DB in any of the four affected tables.

**The technique below (dump-and-replay + fast-forward) is no longer needed for this specific gap**, but is kept here since it's the general-purpose fallback for whatever the *next* undiscovered phantom-column/table turns out to be — the verification method above only catches gaps in tables you think to check:

```bash
# On the Mac (or whichever instance has the real, fully-migrated schema):
pg_dump -h 127.0.0.1 -U admin -d miner --schema-only --schema=kb --no-owner --no-privileges > kb_schema.sql

# Copy to the new box and apply using the NEW Postgres instance's own psql client
# (important if versions differ — Mac was PG18, the dump used PG18-only \restrict/
# \unrestrict meta-commands that an older psql client won't understand):
docker cp kb_schema.sql chenweb-paradedb:/tmp/kb_schema.sql
docker exec -e PGPASSWORD=yourpassword chenweb-paradedb \
  psql -U admin -d miner -v ON_ERROR_STOP=1 -f /tmp/kb_schema.sql

# Fast-forward goose's tracking tables so it doesn't try to re-run migrations
# already reflected in the schema dump above. Export the source's tracking rows:
psql -h 127.0.0.1 -U admin -d miner -t -A -F',' \
  -c "SELECT version_id, is_applied, tstamp FROM project_db_migration ORDER BY version_id;" \
  > project_migration_rows.csv
psql -h 127.0.0.1 -U admin -d miner -t -A -F',' \
  -c "SELECT version_id, is_applied, tstamp FROM shared.shared_db_migration ORDER BY version_id;" \
  > shared_migration_rows.csv

# On the new instance, load rows for any version_id not already present
# (docker exec needs -i or the heredoc's stdin never reaches psql):
docker cp project_migration_rows.csv chenweb-paradedb:/tmp/
docker exec -i -e PGPASSWORD=yourpassword chenweb-paradedb psql -U admin -d miner -v ON_ERROR_STOP=1 <<'SQL'
CREATE TEMP TABLE tmp_proj_mig (version_id BIGINT, is_applied BOOLEAN, tstamp TIMESTAMP);
\copy tmp_proj_mig FROM '/tmp/project_migration_rows.csv' WITH (FORMAT csv);
INSERT INTO project_db_migration (version_id, is_applied, tstamp)
SELECT t.version_id, t.is_applied, t.tstamp FROM tmp_proj_mig t
WHERE NOT EXISTS (SELECT 1 FROM project_db_migration m WHERE m.version_id = t.version_id);
SQL
# Repeat the same pattern for shared_migration_rows.csv against shared.shared_db_migration
# (create that table first if it doesn't exist yet — it's only created the first time
# RunSharedMigrations actually executes, which won't have happened if project
# migrations failed first).
```

After this, starting ChenWeb will run goose with **0 pending migrations** for everything already in the dump, and will genuinely apply anything newer that exists in `project_migrations/`/`shared_migrations/` but wasn't yet on the source instance — which is the correct behavior for "staging catches up to current dev state."

**⚠️ Critical gotcha with this technique — don't fast-forward version_ids blindly.** The schema dump above was scoped to `--schema=kb` only. Bulk-copying *all* of the source's `project_db_migration` rows (not just the ones for `kb.*` migrations) marks migrations that touch **other** schemas (e.g. `public`) as "applied" even though their `CREATE TABLE` never actually ran on the new instance — goose only checks the tracking table, it never diffs actual schema state. This bit us for real: `20260619000001_create_llm_activity_tables.sql` (which creates `llm_usage_event`, `llm_daily_account_report`, and others, all in `public`) got marked applied without ever running, and the tables silently didn't exist — ChenWeb didn't crash (it's a background job, not a startup check) but warned every retention/report cycle.

**Do it correctly:** before fast-forwarding, partition the migration files into "covered by the schema dump" vs. not, and only copy tracking rows for the covered ones:

```bash
cd project_migrations
for f in *.sql; do
  grep -qi '\bkb\.' "$f" || grep -qi 'CREATE SCHEMA.*kb\b' "$f" || echo "$f"
done
# ^ migrations NOT touching the kb schema — do NOT fast-forward these version_ids.
# Let goose apply them for real on first boot instead.
```

If you already fast-forwarded too broadly (as happened here), the fix is to delete the wrongly-marked tracking rows and let the next boot apply them for real — safe because the underlying SQL uses `CREATE TABLE IF NOT EXISTS`/`ADD COLUMN IF NOT EXISTS` throughout:

```bash
docker exec -i -e PGPASSWORD=yourpassword chenweb-paradedb psql -U admin -d miner -v ON_ERROR_STOP=1 <<'SQL'
DELETE FROM project_db_migration
WHERE version_id IN (/* the version_ids of the non-kb migrations you fast-forwarded */);
SQL
```
Then stop ChenWeb, restart it (migrations run automatically at startup), and confirm in the log that those versions show `goose: OK up ...` rather than being silently skipped.

**Done (2026-07-25) for `kb.inputs`/`kb.metrics`/`kb.semantic_projections`/`kb.doc_proc_logs`** — see above. **Still worth doing:** double-check whether `email_store`, `prompt_store`, `resources`, `activity_log`, `login_sessions`, `session_log`, `id_mgr`, `table_manager` (the `shared` schema's system tables, created by `sysdatastores.CreateSysTables` using names from `shared/libconfig.toml`) have the same "pre-migration-history baseline" gap — and, more generally, run the verification method above periodically, since it's the only way any of these gaps actually surface (the fast-forward workaround masks them by construction).

## 5. `pdf-parser` (Python) + MinerU

Separate from the Go binary — a standalone Python service that polls `kb.inputs` and dispatches PDF parsing.

### 5.1 MinerU (CPU backend — no GPU on this box)

```bash
curl https://mise.run | sh
curl -LsSf https://astral.sh/uv/install.sh | sh

mkdir -p ~/Workspace/ThirdParty
git clone https://github.com/chendingplano/MinerU.git ~/Workspace/ThirdParty/mineru
cd ~/Workspace/ThirdParty/mineru
mise trust

# Mac's mise.toml hardcodes MINERU_DEVICE_MODE=mps and a /Users/... config path —
# override both for Linux/CPU:
cat > mise.local.toml <<'EOF'
[env]
MINERU_DEVICE_MODE = "cpu"
MINERU_TOOLS_CONFIG_JSON = "/home/<user>/mineru.json"
EOF
cp mineru.template.json ~/mineru.json

# Do NOT run `mise run setup` — it hardcodes the Mac-only MLX install path.
mise exec -- uv venv
mise run install-cpu

# Download pipeline-only models (CPU backend doesn't need VLM models):
.venv/bin/mineru-models-download -s huggingface -m pipeline
```

Verify: `mise run parse-cpu -- -p some.pdf -o /tmp/test-out` should produce `<stem>_content_list.json`.

### 5.2 `pdf-parser` service

```bash
mkdir -p ~/Workspace/ChenWeb/python
rsync -avz -e "ssh -p 8822" --exclude .venv --exclude __pycache__ --exclude .pytest_cache \
  ~/Workspace/ChenWeb/python/pdf-parser cding@<host>:~/Workspace/ChenWeb/python/

cd ~/Workspace/ChenWeb/python/pdf-parser
mise trust
uv sync
```

Force the CPU pipeline backend (the default `hybrid-auto-engine` backend needs a GPU) — add to `mise.local.toml`:

```toml
MINERU_BACKEND = "pipeline"
```

`MINERU_CLI` doesn't need setting explicitly — `parser_mineru.py` auto-detects `~/Workspace/ThirdParty/mineru/.venv/bin/mineru` via `$HOME`, which resolves correctly on Linux.

## 6. Startup order

With everything under systemd (§1.7), this is automatic on every boot via each unit's `After=`/`Wants=`. Manual order, if ever needed:

1. Native PostgreSQL 12 (`systemctl start postgresql`)
2. ParadeDB Docker container (`docker start chenweb-paradedb`, or it's already running per `--restart unless-stopped`, itself gated on `docker.service` being enabled)
3. NATS server (`systemctl start nats-server`)
4. Kratos (`systemctl start kratos`)
5. ChenWeb Go binary + workers (`systemctl start chenweb doc-processor parser-result-converter`)
6. Caddy (`systemctl start caddy`)
7. `pdf-parser` (optional, only if PDF ingestion is needed — not yet made into a systemd unit; still run manually per §5.2)

## 7. Verification checklist

```bash
# systemd — all six should print "active" and "enabled"
for svc in nats-server kratos chenweb doc-processor parser-result-converter caddy; do
  systemctl is-active $svc; systemctl is-enabled $svc
done

# NATS
(echo > /dev/tcp/127.0.0.1/4222) && echo "nats port ok" || echo "check nats"
nats stream ls --server nats://127.0.0.1:4222   # expect doc-processor-start-events,
                                                  # doc-processor-line-file-events,
                                                  # doc-review-events, pdf-parsed-events

# Kratos
curl -s http://127.0.0.1:4433/health/alive
curl -s http://127.0.0.1:4434/health/alive

# ParadeDB
PGPASSWORD=yourpassword psql -h 127.0.0.1 -p 5433 -U admin -d miner -c "\dx" | grep -E "pg_search|vector"

# ChenWeb — should be reachable externally and correctly delegating auth to Kratos
curl -s -o /dev/null -w "%{http_code}\n" http://<HOST>:8080/
curl -s http://<HOST>:8080/session   # expect {"error":"Login required"} (401) when logged out —
                                      # this confirms the Kratos auth chain is actually being
                                      # called, not just that the server didn't crash

# Caddy — 80 redirects, 443 will fail TLS until DNS points here (expected, see §1.8)
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:80/   # 308
```


## 8. Operations

**Scope:** `192.168.29.96` (ssh port `8822`, user `cding`) — the Linux box, eventually the production host for `dingbo.bzton.cn`. Full install details/gotchas: `KnowledgeStore/doc-repo/devdocs/202607/2026072401-devdoc-deploy-production.md`.

Unlike the MacMini's tmux list above, **every service on `.96` runs under systemd and is `enable`d** — after a reboot, everything comes back up on its own in the right order (each unit's `After=`/`Wants=` chains it to the ones it depends on). You should not normally need to start anything by hand. This section is for checking status and for the rare manual restart.

### 8.1 Services

| systemd unit | What it is | Port(s) | Depends on |
|---|---|---|---|
| `nats-server` | JetStream broker | `4222` | — |
| `kratos` | Auth (Ory Kratos, `mise run start-kratos`) | `4433` public, `4434` admin (loopback) | native PostgreSQL 12 |
| `chenweb` | Main Go backend (`deepdoc`) | `8080` | `nats-server`, `kratos`, `docker` (ParadeDB) |
| `doc-processor` | NATS worker: chunking/extraction/doc-review pipeline | — (no HTTP port) | `nats-server`, `kratos`, `docker` |
| `parser-result-converter` | NATS worker: converts MinerU/pdf-parser output to line-files | — (no HTTP port) | `nats-server`, `kratos`, `docker` |
| `caddy` | Reverse proxy for `dingbo.bzton.cn` → ChenWeb/Kratos | `80`, `443` | `chenweb`, `kratos` |

Not (yet) under systemd — still started manually:
* `python/pdf-parser` — `cd ~/Workspace/ChenWeb/python/pdf-parser && mise ocr-service-start` (or `-start-sync` to run in the foreground)

Also running on this box, unrelated to ChenWeb: `chenweb-paradedb` (Docker, ChenWeb's own Postgres 18 + pgvector + pg_search — see the devdoc §1.3.2) and `agentgpt_db`/`platform` (AgentGPT, a separate stack, do not touch).

**Retired on this box (2026-07-24):** Dify's containers (`docker-nginx-1`, `docker-api-1`, `docker-worker-1`, `docker-web-1`, `docker-sandbox-1`, `docker-ssrf_proxy-1`, `docker-weaviate-1`, `docker-redis-1`, `docker-db-1`) were `docker stop`'d — not removed — to free ports 80/443 for Caddy. `docker start <name>` brings any of them back if Dify is needed again. The native Ubuntu `nginx` package was also stopped and disabled for the same reason (it was only ever serving the default placeholder page).

### 8.2 Check everything is up

```bash
for svc in nats-server kratos chenweb doc-processor parser-result-converter caddy; do
  printf "%-25s active=%-10s enabled=%s\n" "$svc" "$(systemctl is-active $svc)" "$(systemctl is-enabled $svc)"
done

curl -s -o /dev/null -w "ChenWeb :8080 -> %{http_code}\n" http://127.0.0.1:8080/
curl -s -o /dev/null -w "Kratos  :4433 -> %{http_code}\n" http://127.0.0.1:4433/health/alive
curl -s http://127.0.0.1:8080/session   # expect 401 {"error":"Login required"} when logged out —
                                         # confirms ChenWeb is actually calling Kratos, not just up
```

### 8.3 Restart / logs for a single service

```bash
sudo systemctl restart <unit>      # e.g. chenweb, doc-processor, kratos, caddy, nats-server, parser-result-converter
sudo systemctl status <unit>
sudo journalctl -u <unit> -n 100 --no-pager     # -f to follow live
```

`journalctl -u <unit>` without `sudo` shows nothing for units running as a different user (e.g. `caddy` runs as system user `caddy`, not `cding`) — use `sudo` or add your user to the `adm`/`systemd-journal` group.

### 8.4 Restart everything (rare — e.g. after changing `.env` or `config.local.toml`)

Order matters because of the dependency chain (`nats-server`/`kratos`/ParadeDB → `chenweb`/workers → `caddy`):

```bash
sudo systemctl restart nats-server kratos
sleep 3
sudo systemctl restart chenweb doc-processor parser-result-converter
sleep 3
sudo systemctl restart caddy
```

### 8.5 Where things live

* `~/Workspace/ChenWeb/` — binaries (`server-linux`, `doc-processor-linux`, `parser-result-converter-linux`), `config.toml`/`config.local.toml`/`.env`, `project_migrations/`, `shared_migrations/`, `prompts/`, `.models.toml`, `docs/doc-templates/`, `python/pdf-parser/`, `Data/` (all runtime storage — logs, staging, artifacts, DocReviewReports, etc.)
* `~/Workspace/Kratos/` — built from source (`src/kratos/kratos`), config in `mise.local.toml` (**not** a copy of the Mac's — separate secrets, see devdoc §1.6.2)
* `~/Workspace/ThirdParty/mineru/` — MinerU, CPU/pipeline backend
* `~/Workspace/shared/libconfig.toml` — shared-library system table names (`SHARED_LIB_CONFIG_DIR` env var points here; **must** be a real exported env var, not just in `.env` — see devdoc §3)
* `/etc/caddy/Caddyfile` — same content as the Mac's `ChenWeb/Caddyfile`
* `/etc/systemd/system/{nats-server,kratos,chenweb,doc-processor,parser-result-converter}.service` — our units; `caddy.service` came from the apt package

### 8.6 Known limitations on this box right now

* `dingbo.bzton.cn` isn't pointed at `.96` yet — Caddy is up and correctly redirecting HTTP→HTTPS, but can't get a real cert until DNS is cut over. Not a bug; resolves itself once DNS points here.
* Google OAuth and outbound email (SMTP) were originally left unconfigured on Kratos (password login only) — see §1.6.5/§1.6.6 for how to turn both on when needed.
* `pdf-parser` has no systemd unit yet.

About 'mitmproxy':
Do not run 'mitmproxy' now since it causes probelsm.
* mitmproxy: 
  * mitmweb --listen-host 127.0.0.1 --listen-port 8081      # Web version
  * mitmproxy --listen-host 127.0.0.1 --listen-port 8081    # Interactive UI
  * mitmdump --listen-host 127.0.0.1 --listen-port 8081     # headless, non-interactive
* cc switch: cd ThirdParty/cc-switch; sh start.sh 
* Start docker: cd ChenWeb; mise docker-start

**Resolve Certificate Issue**

If mitmproxy reports certificate error, do the following:
Run: 
```text
ls -l ~/.mitmproxy/mitmproxy-ca-cert.pem
```
It should show the content.

Next run the following to inspect its fingerprint:
```text
* Run: openssl x509 \
  -in ~/.mitmproxy/mitmproxy-ca-cert.pem \
  -noout -subject -issuer -fingerprint -sha256
```

Then run the following to install the certificate (on MacOS):
```text
sudo security add-trusted-cert \
  -d \
  -r trustRoot \
  -p ssl \
  -p basic \
  -k /Library/Keychains/System.keychain \
  "$HOME/.mitmproxy/mitmproxy-ca-cert.pem"
```

## 9. Known gaps / deliberately deferred

Resolved as of 2026-07-24: systemd units for all six services including Caddy (§1.7, §1.8), `doc-processor`/`parser-result-converter` deployed (§2.4), `DATA_HOME_DIR`/`DATA_BACKUP_DIR` (§3), and the `llm_usage_event`/`llm_daily_account_report` migration gap (§4 — root cause was the fast-forward technique applied too broadly, not a real baseline-schema gap; fixed by re-running those 9 migrations for real).

Resolved as of 2026-07-25: **the `kb.*` baseline-schema gap (§4) is now a real migration** (`20260401000000_create_kb_baseline_tables.sql`) instead of a manual dump-and-replay step — verified by running the actual goose CLI against a genuinely empty database end-to-end (152/152 migrations, zero errors) and diffing the resulting schema column-by-column and constraint-by-constraint against the live dev database (zero mismatches). §4's dump-and-replay technique is kept as the documented fallback for the next undiscovered gap of this kind, not deleted, since the verification method only catches gaps in tables someone thinks to check. Still open: