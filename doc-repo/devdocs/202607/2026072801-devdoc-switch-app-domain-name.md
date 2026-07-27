# How to Switch the App Domain Name (ChenWeb + Kratos)

**Date:** 2026-07-28
**Scope:** Switching ChenWeb's active domain between production (`dingbo.bzton.cn`) and local testing (`http://macmini.deepdocs.me`, no TLS).
**Why this doc exists:** Switching the domain touches **two separate repos** (`ChenWeb/` and `Kratos/`) with their own `mise.local.toml` files. Updating only the ChenWeb side leaves Kratos still allow-listing the old domain, producing `self_service_flow_return_to_forbidden` ("Requested return_to URL ... is not allowed") on Google login — this happened on 2026-07-28 switching back to `macmini.deepdocs.me`.

## 1. `ChenWeb/mise.local.toml`

Three vars carry the domain:

```toml
APP_BASE_URL = "http://macmini.deepdocs.me:8080"                      # or https://dingbo.bzton.cn
APP_HOST = "http://macmini.deepdocs.me:8080"                          # or dingbo.bzton.cn (no scheme, prod)
GOOGLE_OAUTH_REDIRECT_URL = "http://macmini.deepdocs.me:8080/auth/google/callback"
```

**The `:8080` matters — this is the actual root cause hit on 2026-07-28.** Caddy is already running on this Mac (fronting production `dingbo.bzton.cn` on port 80/443 with automatic HTTPS). Caddy's automatic-HTTPS feature installs a **global** HTTP→HTTPS redirect on port 80 that applies to *any* Host header, not just the domains with a matching site block in `Caddyfile` — confirmed live: `curl http://macmini.deepdocs.me/oauth/callback` returned `308 Location: https://macmini.deepdocs.me/oauth/callback` even though `Caddyfile` has no site block for that host at all. Since `macmini.deepdocs.me` has no valid HTTPS anywhere, the browser then fails with `ERR_SSL_PROTOCOL_ERROR`. ChenWeb itself is reached directly on `:8080` (bypassing Caddy entirely, confirmed via the `origin:http://macmini.deepdocs.me:8080` header in Kratos's own request logs) — but `APP_BASE_URL` without a port defaults the OAuth callback URL to port 80, routing straight into Caddy's trap. Adding `:8080` everywhere keeps the whole flow off port 80 and away from Caddy.

`ChenWeb/mise.local-bzton.toml` is a **saved snapshot** of the full `mise.local.toml` with the `dingbo.bzton.cn` values for these three vars — it is not wired into `mise.toml` as an active profile, it's just a reference to diff/copy from when switching back. Keep it in sync manually if the non-domain vars in `mise.local.toml` ever change.

## 2. `Kratos/mise.local.toml` + `Kratos/kratos/kratos.yml`

This is the part that's easy to miss. `kratos.yml` declares two **fixed-size arrays**, every slot `set-via-env`:

- `serve.public.cors.allowed_origins` (`SERVE_PUBLIC_CORS_ALLOWED_ORIGINS_0..N`)
- `selfservice.allowed_return_urls` (`SELFSERVICE_ALLOWED_RETURN_URLS_0..N`)

**Gotcha (confirmed live, 2026-07-15 and again 2026-07-28):** env vars can only patch an *existing* array index — they cannot extend the array past what `kratos.yml` declares. If a new domain needs a slot beyond the current count, you must add a new `- set-via-env` line to **both** arrays in `kratos.yml` first, then add the matching indexed var in `mise.local.toml`. As of 2026-07-28 both arrays already carry entries for `dingbo.bzton.cn`, `localhost`/`127.0.0.1`, and `macmini.deepdocs.me` side by side — the established pattern here is additive (keep every domain you test against listed), not swapping one for another.

Also check/update — **all of these are single values, not arrays, so they must be flipped (not left additive) to whichever domain you're actively testing**:

- `SELFSERVICE_DEFAULT_BROWSER_RETURN_URL` — cosmetic default (the real `return_to` is set dynamically by `HandleGoogleLoginKratos` from ChenWeb's `APP_BASE_URL`), but keep it in sync anyway.
- `SELFSERVICE_FLOWS_ERROR_UI_URL`, `SELFSERVICE_FLOWS_SETTINGS_UI_URL`, `SELFSERVICE_FLOWS_RECOVERY_UI_URL`, `SELFSERVICE_FLOWS_VERIFICATION_UI_URL`, `SELFSERVICE_FLOWS_VERIFICATION_AFTER_DEFAULT_BROWSER_RETURN_URL`, `SELFSERVICE_FLOWS_LOGOUT_AFTER_DEFAULT_BROWSER_RETURN_URL`, `SELFSERVICE_FLOWS_LOGIN_UI_URL`, `SELFSERVICE_FLOWS_REGISTRATION_UI_URL` — these are the actual browser redirect targets for each self-service flow. Missed on the first pass on 2026-07-28: fixing only the allowlist arrays got past the `return_to forbidden` error, but the browser was still being redirected to `dingbo.bzton.cn`'s login/error/etc. pages instead of the local ones. **All of these need the `:8080` port too** (see the Caddy note in §1) — the first attempt at fixing them omitted the port and hit the same Caddy-redirect-to-https trap.
- `SESSION_COOKIE_DOMAIN` — must match the domain actually being tested, or the browser refuses to persist the session cookie.
- `SESSION_COOKIE_SECURE` — must be `"false"` for a plain-HTTP local domain like `macmini.deepdocs.me`; `"true"` makes the browser silently drop the cookie over non-TLS. Only set `"true"` once the domain is actually served over HTTPS.

**`SERVE_PUBLIC_BASE_URL`** — despite an earlier pass at this doc claiming otherwise, this **is** a blocker. Kratos uses it to build the `ui.action` URL embedded in every self-service flow response (login, registration, recovery, verification, OIDC). `shared/go/api/auth/kratos.go:1945` (`HandleGoogleLoginKratos`) reads that `action` straight out of the flow JSON and puts it, unmodified, as the `action=` of an auto-submitting HTML `<form>` sent to the **browser** — so the browser itself POSTs there, not just the Go backend. Production has it as `https://dingbo.bzton.cn/kratos/` (with the `/kratos/` prefix, because Caddy reverse-proxies and strips that prefix in front of Kratos). Local testing has no Caddy in front of Kratos — it's hit directly on `:4433` — so this must become `http://macmini.deepdocs.me:4433/` (no path prefix).

**Consequence — Google Cloud Console redirect URI.** Kratos's OIDC provider derives the redirect URI it hands to Google from this same `SERVE_PUBLIC_BASE_URL`: `<base>/self-service/methods/oidc/callback/google`. Changing the base URL means **that exact new URL must be added to the OAuth client's Authorized redirect URIs in Google Cloud Console** (keep the production one registered too — Google allows multiple). Skipping this step surfaces as `redirect_uri_mismatch` on Google's own consent page, not a Kratos or ChenWeb log line, so it looks like a totally different failure mode from the earlier `return_to`/UI-URL issues.

## 3. Restart order

Both processes read their env at startup, not live:

1. Update `Kratos/mise.local.toml` (and `kratos.yml` if a slot was added).
2. Restart Kratos: `mise start-kratos` (from `Kratos/`).
3. Update `ChenWeb/mise.local.toml`.
4. Restart ChenWeb (`mise dev` / `mise serve`, from `ChenWeb/`).

## 4. Quick checklist when switching domains

- [ ] `ChenWeb/mise.local.toml`: `APP_BASE_URL`, `APP_HOST`, `GOOGLE_OAUTH_REDIRECT_URL` — **include the port** ChenWeb actually listens on (`:8080`) if Caddy isn't fronting this domain
- [ ] `Kratos/mise.local.toml`: matching CORS origin entry (`SERVE_PUBLIC_CORS_ALLOWED_ORIGINS_N`) includes the same port
- [ ] `Kratos/mise.local.toml`: all 8 `SELFSERVICE_FLOWS_*_UI_URL` / `..._RETURN_URL` vars flipped to the active domain, same port included
- [ ] `Kratos/mise.local.toml`: `SESSION_COOKIE_DOMAIN` flipped to the active domain
- [ ] `Kratos/mise.local.toml`: `SESSION_COOKIE_SECURE` set to `"false"` for plain-HTTP domains, `"true"` only over real HTTPS
- [ ] `Kratos/mise.local.toml`: `SERVE_PUBLIC_BASE_URL` pointed at the active domain (with the right port/prefix for whether Caddy fronts it)
- [ ] Google Cloud Console: the OAuth client's Authorized redirect URIs includes `<SERVE_PUBLIC_BASE_URL>/self-service/methods/oidc/callback/google` for the active domain
- [ ] `Kratos/mise.local.toml` + `kratos.yml`: new domain present in both `allowed_origins` and `allowed_return_urls` (add array slots if needed)
- [ ] Restart Kratos, then restart ChenWeb
