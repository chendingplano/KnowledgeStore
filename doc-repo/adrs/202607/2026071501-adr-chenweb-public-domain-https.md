# ADR 2026071501 — ChenWeb LAN Login Failure, Public Domain, and HTTPS via Caddy

**Date:** 2026-07-15 \
**Status:** Accepted \
**Component:** ChenWeb, Kratos \
**Authors**: Chen Ding \
**Tags**: auth, kratos, dns, https, caddy, networking \

## Change Logs
* 2026/07/15, ADR Created
* 2026/07/15, Added "How to Change Domain Name" runbook; resolved which Google OAuth redirect URIs are mandatory vs. dead-in-current-config (`AUTH_USE_KRATOS`/`OPENMETADATA_SSO_MODE` code analysis)
* 2026/07/15, Live testing (Caddy + router setup) surfaced a fourth hardcoded-domain location missed by the original static-analysis sweep: Vite's `server.allowedHosts` in `ChenWeb/web/vite.config.ts`, which rejected requests with `Blocked request. This host ("dingbo.bzton.cn") is not allowed.` Fixed by deriving `allowedHosts` from `APP_BASE_URL` (already read into this file for the dev-server proxy targets) instead of a second hardcoded literal, so no vite.config.ts edit is needed on future domain changes either.
* 2026/07/15, **Confirmed live** the "unverified assumption" flagged in Consequences: Kratos rejected Google login with `self_service_flow_return_to_forbidden` / `Requested return_to URL "https://dingbo.bzton.cn/oauth/callback" is not allowed`, even though `SELFSERVICE_ALLOWED_RETURN_URLS_8` was set to exactly that value. Root cause: env var overrides can only patch fields *within* an existing array index — they cannot extend a file-declared array past its original length (`selfservice.allowed_return_urls` was 7 items in the file; indices 7-10 supplied only via env were silently dropped). Fixed by making every index of both `serve.public.cors.allowed_origins` (7) and `selfservice.allowed_return_urls` (11) `set-via-env`, including the previously-static `localhost`/`127.0.0.1` entries, matching the proven working pattern (`secrets.cookie`, `identity.schemas` — single source of truth, no file/env mixing).
* 2026/07/15, Restart after the above fix failed with a second error: `items at index 5 and 6 are equal` (JSON schema `uniqueItems` violation on `serve.public.cors.allowed_origins`). While converting the two `macmini.deepdocs.me` CORS entries (`:8080` and `:5173`, distinct ports) to `dingbo.bzton.cn`, both were collapsed to the identical plain-domain value. `selfservice.allowed_return_urls` had the same mistake at indices 7/9 and 8/10. Fixed by giving indices `SERVE_PUBLIC_CORS_ALLOWED_ORIGINS_6`, `SELFSERVICE_ALLOWED_RETURN_URLS_9`/`_10` their original `:5173` (Vite dev port) distinction back — `https://dingbo.bzton.cn:5173` / `.../oauth/callback` — instead of duplicating the plain-domain entries at `_5`/`_7`/`_8`. Both arrays re-verified locally as having zero duplicates before the next restart.

## Context

ChenWeb (`home3`) was reachable from other LAN machines via `http://192.168.29.170:8080` — the login page loaded correctly — but clicking "Login through Google" or submitting email/password login produced "This site can't be reached" in the browser, even though the backend log showed the login flow completing successfully server-side (`Kratos login success`, `get redirect_url`).

### Root cause

`APP_BASE_URL` (and every domain-bearing field in `Kratos/kratos/kratos.yml` — `serve.public.base_url`, `selfservice.default_browser_return_url`, `selfservice.allowed_return_urls`, all `flows.*.ui_url`, `session.cookie.domain`) was hardcoded to `macmini.deepdocs.me`. That hostname resolved **only** via a `/etc/hosts` entry (`192.168.29.170 macmini.deepdocs.me`) present exclusively on the macmini itself — `dig macmini.deepdocs.me` returned no public DNS record.

- The login page loaded fine on any LAN machine because it was reached by raw IP (`192.168.29.170:8080`) — no DNS lookup needed.
- The backend completed the login flow because the Go server and Kratos both run *on* the macmini and could resolve `macmini.deepdocs.me` via that machine's own `/etc/hosts`.
- The final step — a browser redirect to `http://macmini.deepdocs.me:8080/...` (and, for Google OAuth, to Kratos's public API at `macmini.deepdocs.me:4433`) — failed on any other LAN device, since no such device had that `/etc/hosts` entry or any public DNS record for the name. Result: `DNS_PROBE_FINISHED_NXDOMAIN` → "This site can't be reached."

### Follow-up requirements

Once the root cause was understood, three related decisions were needed:

1. Make the app domain configurable for ChenWeb (it had previously only ever run under `macmini.deepdocs.me`), including on the Kratos side.
2. Adopt a real public domain, `dingbo.bzton.cn` (already resolving to public IP `47.189.245.217`, confirmed via `curl ifconfig.me` run directly on the macmini — no carrier-grade NAT in the way), with a router port-forward so the app is reachable from outside the LAN.
3. Add HTTPS, matching how `tax` already does it (Caddy, not Nginx).

## Decision

### Domain configurability

`Kratos/kratos/kratos.yml` already used a `set-via-env` convention for secrets and the Google OIDC provider config (e.g. `providers.0.client_id: set-via-env`, resolved by env var `SELFSERVICE_METHODS_OIDC_CONFIG_PROVIDERS_0_CLIENT_ID` defined in `Kratos/mise.toml`). That specific var is not a static value in `Kratos/mise.local.toml` — it's assigned inline in the `start-kratos`/`start-kratos-prod` task bodies in `Kratos/mise.toml` (lines 85, 96), sourced from `GOOGLE_OAUTH_CLIENT_ID`, which *is* a static value in `Kratos/mise.local.toml`. Every hardcoded `macmini.deepdocs.me` field in `kratos.yml` was converted to the same `set-via-env` placeholder, but resolved more directly: as new static env vars added straight to `Kratos/mise.local.toml`'s `[env]` block, with no task-level indirection needed since (unlike the Google credential) the mise var names and the Kratos config var names are already identical. This means a future domain switch touches only the two `mise.local.toml` files — `kratos.yml` and `mise.toml` never need editing again.

Per the user's explicit instruction, all new/changed env vars were placed in each project's `mise.local.toml` (`[env]` block — `ChenWeb/mise.local.toml` for ChenWeb's vars, `Kratos/mise.local.toml` for Kratos's), **not** `.env`. `godotenv.Load()` (used by ChenWeb's Go binaries) does not override variables already present in the process environment, and mise injects `[env]` from the project's `mise.local.toml` before any task runs — so `ChenWeb/mise.local.toml` was already silently taking precedence over `ChenWeb/.env` for any key both files defined. `ChenWeb/.env` was left untouched but is now stale/shadowed for `APP_BASE_URL` and `GOOGLE_OAUTH_REDIRECT_URL`.

### Public domain and port forwarding

Chose **standard ports 80/443 via Caddy**, not a custom external port (the user's original plan was `47.189.245.217:10170 → 192.168.29.170:8080` over plain HTTP). Reasoning:

- Nothing was listening on 80/443 on the macmini (`tax`'s Caddy instance runs elsewhere), so the ports were free.
- Caddy gets automatic Let's Encrypt HTTPS with a ~5-line config, matching `tax/Caddyfile` exactly.
- Users reach `https://dingbo.bzton.cn` with no port number.
- A non-standard external port would still have needed HTTPS layered on top separately, and offers no advantage once 80/443 are available.

### Alternative Decisions

**Per-client `/etc/hosts` entries** — add `192.168.29.170 macmini.deepdocs.me` to every LAN device that needs to log in. Rejected as the primary fix: doesn't scale, must be repeated per device, and does nothing for genuinely external users.

**Router-level LAN DNS override only (no public domain)** — configure the router or a local DNS server to resolve `macmini.deepdocs.me` LAN-wide. Would have fixed the original bug but doesn't satisfy requirement #2 (public reachability), so superseded by the `dingbo.bzton.cn` + port-forward approach.

**Keep port 10170, add TLS directly on that port** — rejected; Let's Encrypt's default HTTP-01/TLS-ALPN challenges expect 80/443, and a non-standard port offers no benefit here.

**Kratos native env-array-override for *every* CORS/allowed-return-url entry (including the static `localhost`/`127.0.0.1` dev entries)** — rejected in favor of leaving those static entries as literal YAML and only parameterizing the domain-specific array indices, to minimize risk of an env-provided array wholesale-replacing a file-provided array (see Consequences — unverified assumption).

### Environment Variables

**`ChenWeb/mise.local.toml`** (changed/added):

| Variable | Old value | New value |
|---|---|---|
| `APP_BASE_URL` | `http://macmini.deepdocs.me:8080` | `https://dingbo.bzton.cn` |
| `APP_HOST` | `macmini.deepdocs.me` | `dingbo.bzton.cn` |
| `GOOGLE_OAUTH_CLIENT_ID` | (was only in `.env`) | `196965176198-oca6ud4spfujn37vettjdu6t15p61lmh.apps.googleusercontent.com` |
| `GOOGLE_OAUTH_REDIRECT_URL` | (was only in `.env`, `http://macmini.deepdocs.me:8080/auth/google/callback`) | `https://dingbo.bzton.cn/auth/google/callback` |

`APP_PORT` (`8080`) is unchanged — it is the Go server's internal bind port; Caddy proxies to `localhost:8080`. Note `APP_HOST` is **not** used as the bind address (the server binds `:8080` on all interfaces regardless); it is informational/CORS-adjacent config only.

**`Kratos/mise.local.toml`** (added):

| Variable | Value |
|---|---|
| `SERVE_PUBLIC_BASE_URL` | `https://dingbo.bzton.cn/kratos/` |
| `SERVE_ADMIN_BASE_URL` | `http://127.0.0.1:4434/` (always loopback-only, never public) |
| `SERVE_PUBLIC_CORS_ALLOWED_ORIGINS_0`..`_6` | All 7 indices, env-driven (was indices 0–4 literal in the file + 5–6 via env; see the 2026-07-15 Change Log entries for why partial file/env mixing was abandoned, and for the `uniqueItems` duplicate-value bug this introduced) — `0`-`4` are the unchanged `localhost`/`127.0.0.1`/LAN-IP dev origins, `5` is `https://dingbo.bzton.cn`, `6` is `https://dingbo.bzton.cn:5173` (must stay distinct from `_5` — Kratos enforces unique array entries) |
| `SELFSERVICE_DEFAULT_BROWSER_RETURN_URL` | `https://dingbo.bzton.cn/oauth/callback` |
| `SELFSERVICE_ALLOWED_RETURN_URLS_0`..`_10` | All 11 indices, env-driven (same reason) — `0`-`6` are the unchanged dev origins, `7`/`8` are `https://dingbo.bzton.cn` / `.../oauth/callback`, `9`/`10` are the distinct `:5173` variants `https://dingbo.bzton.cn:5173` / `.../oauth/callback` (not duplicates of `7`/`8` — same `uniqueItems` constraint) |
| `SELFSERVICE_FLOWS_ERROR_UI_URL` | `https://dingbo.bzton.cn/error` |
| `SELFSERVICE_FLOWS_SETTINGS_UI_URL` | `https://dingbo.bzton.cn/set-password` |
| `SELFSERVICE_FLOWS_RECOVERY_UI_URL` | `https://dingbo.bzton.cn/recovery` |
| `SELFSERVICE_FLOWS_VERIFICATION_UI_URL` | `https://dingbo.bzton.cn/verification` |
| `SELFSERVICE_FLOWS_VERIFICATION_AFTER_DEFAULT_BROWSER_RETURN_URL` | `https://dingbo.bzton.cn/login?verified=true` |
| `SELFSERVICE_FLOWS_LOGOUT_AFTER_DEFAULT_BROWSER_RETURN_URL` | `https://dingbo.bzton.cn/login` |
| `SELFSERVICE_FLOWS_LOGIN_UI_URL` | `https://dingbo.bzton.cn/login` |
| `SELFSERVICE_FLOWS_REGISTRATION_UI_URL` | `https://dingbo.bzton.cn/registration` |
| `SESSION_COOKIE_DOMAIN` | `dingbo.bzton.cn` |
| `SESSION_COOKIE_SECURE` | `true` (was `"false"` for local HTTP dev) |

## Implementation

### Code Changes

- **`Kratos/kratos/kratos.yml`** — replaced every literal `macmini.deepdocs.me` occurrence with `set-via-env`, following the pre-existing pattern used for secrets and the Google OIDC provider block. Initially only the domain-specific array indices of `serve.public.cors.allowed_origins` and `selfservice.allowed_return_urls` were parameterized, leaving the static `localhost`/`127.0.0.1` entries as file literals; **revised same day** after a live failure (`self_service_flow_return_to_forbidden`) showed env vars can only patch fields within an existing array index, not extend the array past the file's declared length — every index of both arrays is now `set-via-env`. No other structural changes to the file.
- **`Kratos/mise.local.toml`** — added the domain env vars listed above under a new `# --- Domain config ---` block, including all indices of both arrays per the revision above.
- **`ChenWeb/mise.local.toml`** — updated `APP_BASE_URL`/`APP_HOST`, added `GOOGLE_OAUTH_CLIENT_ID`/`GOOGLE_OAUTH_REDIRECT_URL`.
- **`ChenWeb/Caddyfile`** — new file, modeled directly on `tax/Caddyfile`:
  ```
  dingbo.bzton.cn {
      handle /kratos/* {
          uri strip_prefix /kratos
          reverse_proxy localhost:4433
      }
      handle {
          reverse_proxy localhost:8080
      }
  }
  ```
  `ChenWeb/mise.toml` already lists `caddy = "2.11.4"` under `[tools]`; no mise task changes were made since running Caddy on privileged ports 80/443 needs root (`sudo caddy run ...` or `sudo brew services start caddy`), which doesn't fit the existing nohup/pidfile background-task pattern used for `pdf-parser`/`ocr-service`.
- **`ChenWeb/web/vite.config.ts`** — `server.allowedHosts` was hardcoded to `['macmini.deepdocs.me']`; Vite's dev server rejects any request whose `Host` header isn't in this list (`Blocked request. This host (...) is not allowed.`). Changed to derive the host from `APP_BASE_URL` (already read into this file for the `/api`, `/auth`, `/shared_api`, `/kratos` proxy targets) via `new URL(APP_BASE_URL).hostname`, so this file needs no further edits on future domain changes. Found during live Caddy/router testing, not the original static-analysis sweep — see Consequences.

`ChenWeb/.env` was **not** modified (see Domain configurability above) — it still contains the old `macmini.deepdocs.me` values for `APP_BASE_URL`/`GOOGLE_OAUTH_REDIRECT_URL`/etc., which are now dead/shadowed by `mise.local.toml`.

## Operational Behaviors

**Steps outside this repo, required before login works from outside the LAN (one-time, not domain-specific):**

1. **Router:** forward external TCP 80 and 443 → `192.168.29.170:80`/`:443`.
2. **Install & run Caddy:** `brew install caddy`; run with `sudo caddy run --config /Users/cding/Workspace/ChenWeb/Caddyfile` (root required to bind 80/443), or `sudo brew services start caddy` for a persistent daemon.
3. **Test LAN access** to `https://dingbo.bzton.cn` from another LAN device once forwarding is live. This is a NAT-hairpin/loopback check: LAN devices resolving `dingbo.bzton.cn` will get the public IP and need the router to route that back inside. If it fails while external access works, add a router-level local DNS override (or enable NAT loopback, if the router supports it) for `dingbo.bzton.cn → 192.168.29.170`.

See "How to Change Domain Name" below for the per-domain steps (config edits, DNS, Google Console).

## How to Change Domain Name

Everything domain-specific lives in three places: `ChenWeb/mise.local.toml`, `Kratos/mise.local.toml`, and `ChenWeb/Caddyfile`. `kratos.yml`, `mise.toml` in both projects, and `ChenWeb/web/vite.config.ts` never need editing — `vite.config.ts` derives its `allowedHosts` from `APP_BASE_URL` at dev-server startup. Replace `<new-domain>` below with the new hostname (e.g. `app.example.com`) and `<scheme>` with `https` (or `http` for local/LAN-only dev without Caddy).

1. **`ChenWeb/mise.local.toml`** — update:
   | Variable | New value |
   |---|---|
   | `APP_BASE_URL` | `<scheme>://<new-domain>` |
   | `APP_HOST` | `<new-domain>` |
   | `GOOGLE_OAUTH_REDIRECT_URL` | `<scheme>://<new-domain>/auth/google/callback` |

   (`APP_PORT` stays `8080` — it's the internal bind port behind Caddy, not domain-specific.)

2. **`Kratos/mise.local.toml`** — update the domain-derived vars below in the `# --- Domain config ---` block. (`SERVE_PUBLIC_CORS_ALLOWED_ORIGINS_0`..`_4` and `SELFSERVICE_ALLOWED_RETURN_URLS_0`..`_6` are also env vars now, but they hold the fixed `localhost`/`127.0.0.1`/LAN-IP dev origins and are **not** domain-specific — leave them alone on a domain switch.)
   | Variable | New value |
   |---|---|
   | `SERVE_PUBLIC_BASE_URL` | `<scheme>://<new-domain>/kratos/` |
   | `SERVE_PUBLIC_CORS_ALLOWED_ORIGINS_5` | `<scheme>://<new-domain>` |
   | `SERVE_PUBLIC_CORS_ALLOWED_ORIGINS_6` | `<scheme>://<new-domain>:5173` (**must differ** from `_5` — Kratos rejects duplicate array entries with a `uniqueItems` error) |
   | `SELFSERVICE_DEFAULT_BROWSER_RETURN_URL` | `<scheme>://<new-domain>/oauth/callback` |
   | `SELFSERVICE_ALLOWED_RETURN_URLS_7` | `<scheme>://<new-domain>` |
   | `SELFSERVICE_ALLOWED_RETURN_URLS_8` | `<scheme>://<new-domain>/oauth/callback` |
   | `SELFSERVICE_ALLOWED_RETURN_URLS_9` | `<scheme>://<new-domain>:5173` (**must differ** from `_7`, same reason) |
   | `SELFSERVICE_ALLOWED_RETURN_URLS_10` | `<scheme>://<new-domain>:5173/oauth/callback` (**must differ** from `_8`) |
   | `SELFSERVICE_FLOWS_ERROR_UI_URL` | `<scheme>://<new-domain>/error` |
   | `SELFSERVICE_FLOWS_SETTINGS_UI_URL` | `<scheme>://<new-domain>/set-password` |
   | `SELFSERVICE_FLOWS_RECOVERY_UI_URL` | `<scheme>://<new-domain>/recovery` |
   | `SELFSERVICE_FLOWS_VERIFICATION_UI_URL` | `<scheme>://<new-domain>/verification` |
   | `SELFSERVICE_FLOWS_VERIFICATION_AFTER_DEFAULT_BROWSER_RETURN_URL` | `<scheme>://<new-domain>/login?verified=true` |
   | `SELFSERVICE_FLOWS_LOGOUT_AFTER_DEFAULT_BROWSER_RETURN_URL` | `<scheme>://<new-domain>/login` |
   | `SELFSERVICE_FLOWS_LOGIN_UI_URL` | `<scheme>://<new-domain>/login` |
   | `SELFSERVICE_FLOWS_REGISTRATION_UI_URL` | `<scheme>://<new-domain>/registration` |
   | `SESSION_COOKIE_DOMAIN` | `<new-domain>` (bare hostname, no scheme/port) |

   `SERVE_ADMIN_BASE_URL` and `SESSION_COOKIE_SECURE` are **not** domain-specific — leave them as `http://127.0.0.1:4434/` and `true` (or `false` only for local HTTP-only dev) respectively.

3. **`ChenWeb/Caddyfile`** — change the site block hostname from the old domain to `<new-domain>` (first line of the file). No other line changes.

4. **DNS:** point `<new-domain>` (A record, or CNAME to a dynamic-DNS name) at the public IP that the router forwards 80/443 from. If the IP is unchanged (same router/ISP connection as this ADR), only the DNS record for the new name needs creating — the router port-forward rule itself doesn't need to change since it targets the macmini by LAN IP, not by domain.

5. **Google Cloud Console:** add `<scheme>://<new-domain>/kratos/self-service/methods/oidc/callback/google` as an authorized redirect URI — this is the **only mandatory** one. With `AUTH_USE_KRATOS="true"`, `/auth/google/login` calls `HandleGoogleLoginKratos` ([router.go:29-31](../../../../shared/go/api/router.go#L29-L31)), which hands the OAuth flow to Kratos entirely; Kratos is the actual OAuth client and redirects Google to this URL, built from `SERVE_PUBLIC_BASE_URL`. Optionally also add `<scheme>://<new-domain>/auth/google/callback` (the legacy `google.go` path, registered for backwards-compatibility but unreachable while `AUTH_USE_KRATOS="true"`) as cheap insurance in case Kratos is ever disabled. Do **not** bother with an OpenMetadata `:8080/callback` equivalent — `callbackURLForRequest` ([sso.go:190-200](../../../../ChenWeb/server/api/openmetadatahandler/sso.go#L190-L200)) only constructs that redirect when `OPENMETADATA_SSO_MODE == "shared-idp"`, and the actual active mode is `token-bridge` (`ChenWeb/mise.local.toml`, which overrides the stale `"shared-idp"` still sitting in `ChenWeb/.env`) — it's dead in the current config. A fourth pre-existing entry pointing at port `:8585` (OpenMetadata's native port) is not constructed anywhere in `openmetadatahandler` and is presumably OpenMetadata's own independent Google SSO config, outside this repo's control; skip it unless you're also reconfiguring OpenMetadata directly.

6. **Restart services:** `mise start-kratos` (or `start-kratos-prod`) picks up the new `Kratos/mise.local.toml` values on next launch; restart/reload Caddy (`sudo caddy reload --config ChenWeb/Caddyfile` or restart the `brew services` daemon) to pick up the new Caddyfile hostname; restart the ChenWeb Go server to pick up `ChenWeb/mise.local.toml`.

7. **Verify:** confirm `mise start-kratos` boots without config errors, then run through email/password login and Google login end-to-end against `<scheme>://<new-domain>` before considering the switch complete.

## Consequences

**Benefits:**
- The original LAN-login bug (redirect to an unresolvable hostname) cannot recur silently — the domain is now a single, obviously-editable config point in `ChenWeb/mise.local.toml` and `Kratos/mise.local.toml` instead of ~19 scattered literals across `.env` and `kratos.yml`.
- ChenWeb gains a real public HTTPS endpoint, matching the security posture `tax` already has.
- The Vite dev-server `allowedHosts` fix (below) means the `mise dev` workflow (Go dev server via `air` proxying to Vite on 5173) also survives a domain change with zero manual edits, not just the production `mise serve` path.

**Limitations / open risks:**
- **Unverified assumption:** the per-index env var overrides for `serve.public.cors.allowed_origins` and `selfservice.allowed_return_urls` (arrays of plain strings) are assumed to merge into specific array indices rather than replace the whole array wholesale, based on how `selfservice.methods.oidc.config.providers.0.*` (an array of objects) already behaves in this file. This has **not** been confirmed against a live Kratos boot for plain-string arrays. First `mise start-kratos` after this change should be checked for config validation errors; if the merge doesn't work as assumed, the fix is to move the untouched `localhost`/`127.0.0.1` entries into env vars too rather than leaving them in the file.
- **NAT hairpin/loopback is untested** — LAN access to `https://dingbo.bzton.cn` after the port-forward may fail for LAN devices (including the macmini itself) depending on router support; mitigation is documented above but not yet exercised.
- **CGNAT was ruled out** for this connection (macmini's `curl ifconfig.me` matches the domain's resolved IP exactly), but the router's own port-forward rule and any OS firewall on the Mac still need manual verification.
- `courier.smtp.from_address`/`from_name` in `kratos.yml` remain `noreply@miraitaxcpa.com` / "Mirai Tax CPA" — unrelated to this ADR's scope, but ChenWeb's password-reset/verification emails will show Mirai Tax CPA branding until addressed separately.
- **Resolved 2026-07-15:** which Google-login code path is live was initially unconfirmed; static analysis of `router.go` (`AUTH_USE_KRATOS="true"` → `/auth/google/login` calls `HandleGoogleLoginKratos`, not the legacy `google.go` flow) and `openmetadatahandler/sso.go` (OpenMetadata's `shared-idp` callback is only constructed when `OPENMETADATA_SSO_MODE == "shared-idp"`, but the active mode is `token-bridge`) settled it: only the Kratos OIDC callback (`<domain>/kratos/self-service/methods/oidc/callback/google`) is mandatory in Google Cloud Console for the current config. See "How to Change Domain Name" step 5. This was confirmed by code reading, not live browser testing — still worth a real login test after any domain switch.

## Tests

Config-only change; no automated tests apply. `Kratos/kratos/kratos.yml` was validated for YAML syntax only (`ruby -ryaml`). Manual verification required:
- `mise start-kratos` boots without config validation errors.
- Login (email/password and Google) succeeds end-to-end from a non-macmini LAN device once Caddy/port-forwarding are live.
- Session cookie is set with `domain=dingbo.bzton.cn` and `Secure` attribute present.

## Documentation Impact

- `Kratos/CLAUDE.md`'s dev/production config table (`<domain_name>`, `<base_url>` placeholders) documents the same substitution pattern this ADR automates via `set-via-env` + `mise.local.toml`; not updated as part of this change since the manual-template instructions are still accurate as a reference, just no longer the mechanism actually used to populate `kratos.yml`.
- This ADR is the primary record of the domain-configurability mechanism and the LAN-login root cause; no other docs described either before this change.

## References

- `shared/go/api/auth/auth-util.go` — `GetRedirectURL`, reads `APP_BASE_URL`
- `shared/go/api/auth/kratos.go` — Kratos login handlers; log lines that surfaced the original symptom
- `shared/go/api/auth/google.go` — reads `GOOGLE_OAUTH_REDIRECT_URL`
- `shared/go/api/auth/csrf.go`, `authme.go`, `email.go`, `shared/go/api/ApiUtils/ApiUtils.go` — other `APP_BASE_URL` consumers
- `Kratos/kratos/kratos.yml` — Kratos config, domain fields parameterized by this ADR
- `Kratos/mise.local.toml` — new domain env vars
- `Kratos/mise.toml` — `start-kratos`/`start-kratos-prod` tasks (unchanged; env vars flow through automatically via mise)
- `ChenWeb/mise.local.toml` — `APP_BASE_URL`/`APP_HOST`/Google OAuth env vars
- `ChenWeb/Caddyfile` — new, HTTPS reverse proxy config
- `ChenWeb/web/vite.config.ts` — `server.allowedHosts` now derived from `APP_BASE_URL`; `router.go`, `openmetadatahandler/sso.go` — Google OAuth redirect URI mandatory/optional determination (see Consequences)
- `tax/Caddyfile`, `tax/docs/plans/2025-12-29-https-caddy-setup.md` — reference pattern this ADR follows
- `Kratos/CLAUDE.md` — pre-existing manual domain-substitution template this ADR automates
