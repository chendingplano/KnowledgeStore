I installed OpenMetadata in ThirdParty/OpenMetadata (refer to [1]) and integrated with 
ChenWeb (refer to [2]). One important requirement of integrating OpenMetadata with 
ChenWeb is SSO. Currently, it is not truly SSO. If a user has not logged in to 
OpenMetadata through ChenWeb, it still prompt for sign-in, even when the user 
has already signed in ChenWeb.

Another issue is that it appears that OpenMetadata supports only Sign-in with Google.

## SSO
The true SSO means: once a user signs in ChenWeb, he can access OpenMetadata without
being prompt to sign-in to OpenMetadata.

## Implementation of SSO
In my naive way of implementing the SSO is:
- When ChenWeb creates a user, it creates the same user in OpenMetadata by directly
insert a record ito its user table (I configured OpenMetadata to use PostgreSQL), which
is `openmetadata_db.user_entity`.
- If OpenMetadata uses cookies to keep track of user login status, set the cookies

The actual implementation can be much more complicated than this naive approach.
The above is just another way of explaining what I mean "SSO".

---

# Implemented Solution (Status: WORKING)

True SSO is now implemented via a new `token-bridge` SSO mode. When a ChenWeb
user opens **Tools → OpenMetadata**, OpenMetadata loads embedded with no
sign-in prompt (the user lands directly on the OpenMetadata home page).

## Approach: `token-bridge` mode

A new value `token-bridge` was added to `OPENMETADATA_SSO_MODE` alongside the
existing `proxy-only`, `shared-idp`, and `session-bootstrap` modes. It combines
three mechanisms:

1. **Server-side user provisioning.** On the ChenWeb session bootstrap
   endpoint, ChenWeb calls the OpenMetadata REST API (using an admin token) to
   ensure the ChenWeb user exists in OpenMetadata. This uses the REST API
   (`GET /api/v1/users?email=...`, then `POST /api/v1/users` if missing) — not
   a direct `user_entity` table insert. A per-user in-memory cache (1-hour TTL)
   avoids re-provisioning on every request.

2. **Proxy-side token injection.** The ChenWeb reverse proxy injects
   `Authorization: Bearer <admin token>` into every request forwarded to
   OpenMetadata. This makes all upstream API calls authenticated.

3. **Browser-side session bootstrap (the key piece).** The reverse proxy
   injects a `<script>` into OpenMetadata's HTML that writes the admin token
   into OpenMetadata's client-side auth storage *before the React app boots*,
   so the SPA never shows its login screen.

## Critical discovery: OpenMetadata's auth storage is a Service Worker

The naive "set a cookie / localStorage key" idea does not work for
OpenMetadata 1.12.6. The OpenMetadata SPA stores its OIDC token at
`app_state.primary` and reads it through a **Service Worker** (`/app-worker.js`)
that caches `app_state` **in memory** on activation. A stale/empty `app_state`
in the Service Worker's in-memory cache silently shadows any IndexedDB or
localStorage write — which is why early attempts had no effect.

The working injection therefore writes the token to **all three layers** and
explicitly refreshes the Service Worker's in-memory cache:

- IndexedDB `AppDataStore` → `keyValueStore` → key `app_state` =
  `{"primary":"<token>"}` (what the SW reads on init)
- `localStorage["app_state"]` (fallback when SW/IndexedDB unavailable)
- A `postMessage({type:'set', key:'app_state', value:...})` to the live
  Service Worker controller, re-sent on `controllerchange`

This mirrors exactly what OpenMetadata's own Playwright E2E test helper
(`playwright/utils/tokenStorage.ts`) does to bypass login in tests.

The injected token is the OpenMetadata **`ingestion-bot`** JWT (admin role,
no expiry). All embedded users currently share the `ingestion-bot` identity
inside OpenMetadata. True per-user identity is a future enhancement (it needs
admin-generated per-user OpenMetadata tokens, which the OM API does not yet
expose cleanly).

## Configuration

OpenMetadata runtime env for ChenWeb lives in `ChenWeb/mise.local.toml`
(NOT `ChenWeb/.env` — `mise` does not source `.env`, and a value in
`mise.local.toml` overrides it). Required values:

```toml
OPENMETADATA_UPSTREAM_URL     = "http://localhost:8585"
OPENMETADATA_PUBLIC_BASE_PATH = "/integrations/openmetadata/"
OPENMETADATA_DISPLAY_NAME     = "OpenMetadata"
OPENMETADATA_SSO_MODE         = "token-bridge"
OPENMETADATA_ADMIN_TOKEN      = "<ingestion-bot JWT>"
```

The admin token is obtained from OpenMetadata → Settings → Bots →
`ingestion-bot` → JWT. `OPENMETADATA_ADMIN_TOKEN` is required when
`OPENMETADATA_SSO_MODE=token-bridge`; loading fails fast if it is missing.
After editing `mise.local.toml`, restart ChenWeb and hard-reload the browser.

## Logout button hidden in the embed

OpenMetadata's left-sidebar **Logout** control is hidden when embedded under
`token-bridge` (a scoped CSS rule injected alongside the bootstrap script:
`[data-testid="app-bar-item-logout"]`). In `token-bridge` the ChenWeb session
owns identity, so an in-frame logout would only drop the embed into a broken
state. Standalone OpenMetadata (`proxy-only` / `shared-idp`) still shows Logout
normally.

## Known benign error: `ingestionPipelines/status` returns 400

In the browser console you may see:

```
GET .../integrations/openmetadata/api/v1/services/ingestionPipelines/status 400
```

This is **not** an SSO bug. The local stack runs
`start-stack-postgres-no-ingestion`, so there is no Airflow ingestion service.
OpenMetadata's `getRESTStatus()` tries to reach Airflow, fails, and
`PipelineServiceClientException extends WebServiceException(BAD_REQUEST)` → 400.
It is cosmetic; the UI loads and works. Running the full stack
(`mise run start-stack-postgres`) makes it disappear. (See the *ingestion
pipeline* note below for what these pipelines are.)

### What an ingestion pipeline is

An OpenMetadata *ingestion pipeline* is a scheduled Airflow workflow that
connects to a data system and harvests metadata into the OpenMetadata catalog
(types: metadata, usage, lineage, profiler, data quality, dbt). OpenMetadata
stores metadata *about* data, not the data itself; ingestion pipelines are how
the catalog gets populated. They run on the Airflow "ingestion service"
container, which the no-ingestion local stack deliberately omits.

## Files changed (ChenWeb)

Backend (`ChenWeb/server/api/openmetadatahandler/`):

- `sso.go` (new) — `EnsureOpenMetadataUser`: REST-API user provisioning
- `tokencache.go` (new) — in-memory per-user provision cache (1-hour TTL)
- `types.go` — added `AdminToken` to config; `ProvisionStatus` to session
- `handler.go` — `token-bridge` allowed mode; reads `OPENMETADATA_ADMIN_TOKEN`;
  provisions user on session fetch
- `proxy.go` — admin-token injection for `token-bridge`; HTML
  `injectSessionBootstrap` (IndexedDB + localStorage + Service Worker);
  `hideLogoutStyle`; `[OMD-SSO]` structured request/response tracing
- `handler_test.go`, `sso_test.go` — tests for all of the above

Frontend:

- `web/src/lib/components/home3/openmetadata-workspace.svelte` — "SSO active"
  badge, provision-status chip, `[ChenWeb-OM-SSO]` console tracing

## Diagnostic logging

Both sides emit traceable logs (still in place; can be quieted later):

- Backend: structured `slog` lines prefixed `[OMD-SSO]` — every proxied
  request, auth-relevant upstream responses with status codes, HTML rewrite +
  token-injection confirmation.
- Browser console: `[ChenWeb-OM-SSO]` — component mount, session response,
  IndexedDB write + readback, Service Worker ack, iframe load.

Grep `[OMD-SSO]` (backend) / `[ChenWeb-OM-SSO]` (browser) to trace the flow.

## Future work

- Per-user OpenMetadata identity instead of shared `ingestion-bot`.
- Optionally lower diagnostic logging to debug level once stable.

## References
[1] ThirdParty/OpenMetadata/USER_MANUAL.md

[2] KnowledgeStore/Capsules/coding-capsules/open-metadata-integration/open-metadata-integration-impl.md