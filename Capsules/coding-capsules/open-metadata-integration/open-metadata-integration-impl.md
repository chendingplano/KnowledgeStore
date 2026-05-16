# OpenMetadata Integration Implementation

## Summary

This document records the first working implementation of the OpenMetadata GUI integration into `ChenWeb::/home3`.

The implemented slice delivers:

- a ChenWeb-authenticated backend bootstrap endpoint
- a ChenWeb-authenticated same-origin reverse proxy for the OpenMetadata UI/API
- a new `home3` navigation entry at `Tools -> OpenMetadata`
- a ChenWeb-owned workspace shell around an embedded OpenMetadata iframe

This is the phase-1 foundation. It supports protected embedding and ChenWeb-owned shell controls, but it does **not** yet implement full identity-provider token exchange or deep context synchronization.

## Goal

The goal was to expose OpenMetadata inside ChenWeb `home3` as a dedicated workspace panel, while keeping ChenWeb in control of:

- navigation
- shell chrome
- access control
- the future SSO boundary

The design direction chosen earlier was:

- embedded application
- hybrid shell
- dedicated `home3` panel route
- ChenWeb auth as primary
- true SSO as the long-term target

## Implementation Scope

The implementation completed here includes:

1. Backend session/bootstrap contract
2. Backend reverse proxy under a same-origin ChenWeb path
3. Echo route registration
4. `home3` navigation and content-panel integration
5. A first OpenMetadata workspace component

The implementation intentionally does not yet include:

- IdP-backed user-to-user handoff into OpenMetadata
- per-user session provisioning inside OpenMetadata
- postMessage bridge
- bidirectional route sync
- real ChenWeb-to-OpenMetadata context sync

## Backend Design

### Package

A new package was added:

- `ChenWeb/server/api/openmetadatahandler`

Files:

- `handler.go`
- `proxy.go`
- `types.go`
- `handler_test.go`

### Session Endpoint

The backend exposes:

- `GET /api/v1/integrations/openmetadata/session`

Behavior:

- requires an authenticated ChenWeb user
- reads runtime config from environment
- returns a JSON payload describing the OpenMetadata launch surface

Current response shape includes:

- `status`
- `launch_url`
- `proxy_base_path`
- `display_name`
- `user_id`
- `sso_mode`
- `capabilities`
- `auth_boundary_note`
- `message`

Current capabilities returned:

- `embedded_ui`
- `open_in_new_tab`
- `reload`

### Auth Resolution

The package uses ChenWeb's existing Echo auth conventions through `EchoFactory`.

`resolveCurrentUser` currently maps the authenticated ChenWeb user into a small local shape:

- `user_id`
- `email`
- `display_name`

Display name fallback order:

1. `UserName`
2. `FirstName + LastName`
3. `Email`

### Runtime Config

Current environment variables:

- `OPENMETADATA_UPSTREAM_URL`
  - required
  - upstream OpenMetadata base URL, for example `http://localhost:8585`
- `OPENMETADATA_PUBLIC_BASE_PATH`
  - optional
  - defaults to `/integrations/openmetadata/`
- `OPENMETADATA_DISPLAY_NAME`
  - optional
  - defaults to `OpenMetadata`
- `OPENMETADATA_SSO_MODE`
  - optional
  - defaults to `proxy-only`
  - allowed values:
    - `proxy-only`
    - `shared-idp`
    - `session-bootstrap`
- `OPENMETADATA_BEARER_TOKEN`
  - required when `OPENMETADATA_SSO_MODE=session-bootstrap`
  - used by the ChenWeb reverse proxy to inject `Authorization: Bearer <token>` into upstream OpenMetadata requests

If `OPENMETADATA_UPSTREAM_URL` is missing, the backend returns a config error.
If `OPENMETADATA_SSO_MODE` is invalid, the backend returns a config error.
If `OPENMETADATA_SSO_MODE=session-bootstrap` and `OPENMETADATA_BEARER_TOKEN` is missing, the backend returns a config error.

Recommended current local configuration:

```env
OPENMETADATA_UPSTREAM_URL="http://localhost:8585"
OPENMETADATA_PUBLIC_BASE_PATH="/integrations/openmetadata/"
OPENMETADATA_DISPLAY_NAME="OpenMetadata"
OPENMETADATA_SSO_MODE="proxy-only"
# OPENMETADATA_BEARER_TOKEN=""
```

`proxy-only` reflects the current implementation boundary:

- ChenWeb is the access gate
- ChenWeb serves the same-origin launch path
- full production SSO still requires either shared-IdP exchange or a stronger server-side OpenMetadata session bootstrap

Current `session-bootstrap` mode is a practical intermediate step:

- ChenWeb still gates access
- ChenWeb reverse-proxies the UI/API
- ChenWeb injects a configured OpenMetadata bearer token into upstream requests
- this gives the embedded workspace a working authenticated upstream surface, but it is still not true per-user SSO

Current `shared-idp` mode now supports the browser-flow pieces needed for real per-user SSO:

- ChenWeb still owns access to the embedded launch surface
- ChenWeb forwards `X-Forwarded-Host`, `X-Forwarded-Proto`, and `X-Forwarded-Prefix` to OpenMetadata
- ChenWeb proxies the OpenMetadata root callback path at `/callback`
- the session payload exposes `callback_url` so the required redirect URI is visible in the UI

For this mode to work, OpenMetadata itself must be configured to trust the same external IdP as ChenWeb. In the current local setup, that means:

- ChenWeb uses Kratos with Google login
- OpenMetadata should be configured for Google SSO or compatible OIDC using the same Google identity source
- the OpenMetadata OIDC callback/redirect URI should be registered as:
  - `{APP_BASE_URL}/callback`
  - example: `http://macmini.deepdocs.me:8080/callback`

This is the key difference from the earlier subpath-only proxy setup: OpenMetadata expects its OIDC callback at the root callback URL, not under `/integrations/openmetadata/`.

### Reverse Proxy

The backend exposes a same-origin proxy at:

- `/integrations/openmetadata`
- `/integrations/openmetadata/`
- `/integrations/openmetadata/*`

The proxy:

- parses the upstream URL from env
- uses `httputil.NewSingleHostReverseProxy`
- strips the public integration prefix before forwarding
- maps the root integration path to upstream `/`
- returns `502 Bad Gateway` if the upstream is unavailable

This gives ChenWeb a stable same-origin surface for the embedded GUI.

## Route Wiring

### Modified File

- `ChenWeb/server/api/routes.go`

### Changes

The following backend route was added to the authenticated API group:

- `GET /api/v1/integrations/openmetadata/session`

The following authenticated proxy group was added:

- `/integrations/openmetadata`

The frontend-catchall middleware was also updated so that:

- `/integrations/openmetadata/*`

is treated as backend traffic rather than being swallowed as a frontend route.

That routing exception is important because the embedded OpenMetadata app needs to fetch assets and API paths through the ChenWeb origin.

## Frontend Design

### New Home3 View

A new component was added:

- `ChenWeb/web/src/lib/components/home3/openmetadata-workspace.svelte`

This component is the ChenWeb-owned shell for the embedded app.

### Responsibilities

The component currently:

- fetches `/api/v1/integrations/openmetadata/session`
- shows loading and error states
- renders top-level shell chrome
- renders a same-origin iframe using the returned launch path
- supports `Reload`
- supports `Open in new tab`
- shows a placeholder `Sync context` toggle

### Iframe Launch Behavior

The iframe URL is built from the returned launch path and currently appends:

- `embed=1`
- `shell=chenweb`
- `reload=<nonce>`

The reload nonce is used to force iframe refreshes without changing the route itself.

### UI Integration

Modified frontend files:

- `ChenWeb/web/src/lib/components/home3/nav-rail.svelte`
- `ChenWeb/web/src/lib/components/home3/content-panel.svelte`

Changes:

- added `OpenMetadata` under `Tools`
- mounted the new `OpenMetadataWorkspace` when `childId === 'openmetadata'`

This keeps the integration inside the existing `home3` shell rather than opening a separate page by default.

## Files Changed

### Backend

- `ChenWeb/server/api/openmetadatahandler/types.go`
- `ChenWeb/server/api/openmetadatahandler/handler.go`
- `ChenWeb/server/api/openmetadatahandler/proxy.go`
- `ChenWeb/server/api/openmetadatahandler/handler_test.go`
- `ChenWeb/server/api/routes.go`

### Frontend

- `ChenWeb/web/src/lib/components/home3/openmetadata-workspace.svelte`
- `ChenWeb/web/src/lib/components/home3/content-panel.svelte`
- `ChenWeb/web/src/lib/components/home3/nav-rail.svelte`

## Tests and Verification

### Focused Backend Tests

The new handler package was implemented test-first and verified with:

```bash
go test ./server/api/openmetadatahandler -v
```

Covered behaviors:

- unauthenticated session request returns `403`
- authenticated session request returns launch payload
- invalid upstream URL returns proxy construction error
- proxy strips `/integrations/openmetadata` prefix correctly
- proxy root request maps to `/`
- missing required upstream env fails config loading

### Backend Compile Check

Also verified:

```bash
go test ./server/api
```

This confirmed the new route wiring compiled cleanly in the main API package.

### Broader Backend Test Suite

Running:

```bash
go test ./server/api/...
```

showed unrelated pre-existing failures in other packages, including:

- `doc-processing`
- `file-converters`
- `kbhandler`

These were not introduced by the OpenMetadata integration work.

### Frontend Check

Running:

```bash
npm run check
```

reported many existing repo warnings and some unrelated pre-existing errors outside this feature area.

A narrowed check of the touched `home3` OpenMetadata files did not surface new feature-specific Svelte errors.

## Current Limitations

This implementation is intentionally a foundation, not the final SSO product.

Known limitations:

- OpenMetadata is embedded, but user identity is not yet handed through as true per-user SSO
- the backend session endpoint currently returns metadata only, not an OpenMetadata-issued user session
- the `Sync context` toggle is currently UI-only
- internal OpenMetadata navigation stays inside the iframe and is not mirrored into ChenWeb routes
- no message bridge exists yet between ChenWeb and the embedded app

## Why This Shape Was Chosen

This approach was chosen because it gives ChenWeb a strong control boundary without immediately overcommitting to a fragile auth integration.

Benefits:

- ChenWeb stays the shell owner
- OpenMetadata remains largely unmodified
- the same-origin proxy solves many cookie/origin problems early
- the architecture leaves room for a later real SSO handoff

## Recommended Next Steps

The next implementation phase should focus on the actual SSO bridge.

Recommended sequence:

1. Define how ChenWeb maps a logged-in user to an OpenMetadata identity.
2. Decide whether the handoff is shared IdP, trusted proxy headers, or session bootstrap.
3. Extend `/api/v1/integrations/openmetadata/session` to return real launch readiness, not just static metadata.
4. Add a server-side mechanism to establish or refresh an OpenMetadata user session.
5. Implement real context sync from ChenWeb selections into OpenMetadata deep links or search.
6. Add a small browser-level smoke test once the frontend test setup is ready for it.

## Restart Notes

If continuing this work later, the most important entry points are:

- backend bootstrap: `ChenWeb/server/api/openmetadatahandler/handler.go`
- backend proxy: `ChenWeb/server/api/openmetadatahandler/proxy.go`
- route wiring: `ChenWeb/server/api/routes.go`
- `home3` shell view: `ChenWeb/web/src/lib/components/home3/openmetadata-workspace.svelte`

That is the current implementation baseline for ChenWeb's OpenMetadata GUI integration.
