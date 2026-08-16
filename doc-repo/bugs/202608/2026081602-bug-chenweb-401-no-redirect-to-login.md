# ChenWeb admin pages surface a raw 401/"No valid session" error instead of redirecting to `/login` when the Kratos session expires

Date: 2026-08-16

Status: open — root-caused, fix scoped, not yet implemented.

Scope: `shared/svelte` (`stores/auth.svelte.ts`, `stores/dbstore.ts`, `utils/auth.ts` — used by every
project on the shared library, not just ChenWeb) plus 11 near-identical page-local `req<T>()` fetch
helpers under `ChenWeb/web/src/lib/components/home3/*-client.ts` and
`ChenWeb/web/src/lib/services/userManagementService.ts`. Backend
(`shared/go/api/auth/kratos.go`, `shared/go/authmiddleware/auth.go`) is correct as-is — 401 is the
right response; no backend change is proposed.

Code read:
`shared/go/api/auth/kratos.go:170-192` (`ValidateSession`, returns 401 `echo.HTTPError` "No valid
session found..."), `:632-650` (`HandleAuthMeKratos`, returns 401 JSON
`{authenticated:false, message:"No valid session"}`); `shared/go/authmiddleware/auth.go:157-178`;
`shared/svelte/src/lib/stores/auth.svelte.ts:261-368` (`checkAuthStatus`, the `/auth/me` call made on
every store creation / page load), `:159-195` (cross-tab logout — the only path that already does
`window.location.href='/login'` on auth loss), `:434-499` (`logout()`);
`shared/svelte/src/lib/stores/dbstore.ts:56-109` (`checkSystemResp`/`handleResp`);
`shared/svelte/src/lib/utils/auth.ts` (`isAuthenticated`/`clearAuthCache`);
`shared/svelte/src/lib/types/CommonTypes.ts:169-178` (`CustomHttpStatus`, incl. `NotLoggedIn: 557`);
`ChenWeb/web/src/lib/components/home3/llm-activities-client.ts:125-148` (`req<T>`, representative of
the pattern) and the same shape in `llm-model-profiles-client.ts:35`, `llm-accounts-client.ts:43`,
`doc-processors-client.ts:50`, `resolve-ambiguous-objects-client.ts:115`, `schedules-client.ts:48`,
`agentplatform-client.ts:159`, `doc-process-dag-client.ts:100`, `llm-models-client.ts:20`,
`resolve-metric-range-types-client.ts:120`, `ChenWeb/web/src/lib/services/userManagementService.ts:54`;
`ChenWeb/web/src/lib/components/home3/llm-usage-logs-view.svelte:107-130,417-421` (where the raw error
is caught and rendered as a banner — the symptom the user saw);
`ChenWeb/web/src/routes/home3/+layout.ts`, `ChenWeb/web/src/routes/development/+layout.ts` (confirmed:
no route-level auth guard exists in either tree — only fetches `siteConfig`).

Evidence:
```
[API] 2026-08-16 15:21:00 INFO [req=e-c7f516a8] +++++ user not logged in [echo.go:589->kratos.go:644]
error="code=401, message=No valid session found, no credentials provided (SHD_0207142600)"
```
Reported by the user opening `ChenWeb/development, System Admin => Logs => LLM Usage Logs` with an
expired session: the page showed an inline error banner instead of redirecting to `/login`; a manual
refresh correctly prompted login (the top-level page load path works — see §2).

Related: none yet — first doc on this topic.

---

## 1. Summary

An expired Kratos session makes the backend return `401` (correctly). Nothing in the frontend
currently turns that `401` into a redirect to `/login` — every code path that can observe it either
does nothing (the auth store) or renders it as a plain error banner (every per-page data fetcher).
The user's own diagnosis was correct: the fix is to redirect on auth failure instead of surfacing raw
error text, and the gap is systemic across ChenWeb's admin surface, not local to the LLM Usage Logs
page.

## 2. Root cause

Two independent gaps, both need closing:

**Gap A — the auth store's own session check never redirects.**
`checkAuthStatus()` (`auth.svelte.ts:266-358`) runs `/auth/me` on every store creation (i.e. on every
page load) and, on a non-ok response, just sets `status: 'login'` in the writable store
(`:321-337`) — it never navigates. Nothing in the app currently subscribes to `status === 'login'` to
trigger a redirect. The *only* two places that ever call `window.location.href = '/login'` are the
cross-tab `BroadcastChannel` logout listener (`:192`) and the explicit `logout()` action (`:471`,
`:496`). A session that's already expired *before* the page loads triggers neither.

**Gap B — every data-fetch helper treats 401 as just another error.**
`dbstore.ts`'s `checkSystemResp` (app-wide, used by every `db_store` consumer) special-cases `401`
but only to build a nicer `JimoResponse.error_msg` — never a redirect. Separately, 11 near-identical
hand-rolled `req<T>()` helpers across ChenWeb's `/home3` admin pages (full list in §3) do even less:
any non-2xx status, 401 included, becomes `throw new Error(msg)`, which the calling Svelte component
catches and renders as an inline banner — `llm-usage-logs-view.svelte:129-130,417-421` is the exact
path the user hit.

```
Kratos session expires
        |
        v
GET /shared_api/v1/jimo_req  (or /api/v1/llm/..., or /auth/me)
        |
        v
kratos.go ValidateSession() / HandleAuthMeKratos fails -> HTTP 401
        |
        +-------------------------+-------------------------------+
        v                         v                               v
checkAuthStatus()           dbstore.ts                      home3/*-client.ts
(auth.svelte.ts)            checkSystemResp()                req<T>()
  sets status:'login'         builds error JimoResponse        throw new Error(msg)
  no navigation                no navigation                     |
                                                                   v
                                                          Svelte view catches,
                                                          renders error banner
                                                          <- what the user saw
```

Because neither gap redirects, an expired session always surfaces as an error banner somewhere on
the current page, whichever of these paths happens to fire first. A full page refresh works only
because SvelteKit's own top-level navigation/load path happens to re-run auth checks that (by luck of
timing, not design) route to the login prompt.

## 3. Blast radius

Not page-specific. The same `req<T>()` shape (evidently copy-pasted) exists in all of:

- `ChenWeb/web/src/lib/components/home3/llm-activities-client.ts`
- `ChenWeb/web/src/lib/components/home3/llm-model-profiles-client.ts`
- `ChenWeb/web/src/lib/components/home3/llm-accounts-client.ts`
- `ChenWeb/web/src/lib/components/home3/llm-models-client.ts`
- `ChenWeb/web/src/lib/components/home3/doc-processors-client.ts`
- `ChenWeb/web/src/lib/components/home3/doc-process-dag-client.ts`
- `ChenWeb/web/src/lib/components/home3/resolve-ambiguous-objects-client.ts`
- `ChenWeb/web/src/lib/components/home3/resolve-metric-range-types-client.ts`
- `ChenWeb/web/src/lib/components/home3/schedules-client.ts`
- `ChenWeb/web/src/lib/components/home3/agentplatform-client.ts`
- `ChenWeb/web/src/lib/services/userManagementService.ts`

...and the shared-library gaps (`dbstore.ts`, `auth.svelte.ts`) are on the path of every project that
depends on `shared/svelte` (`tax`, `ChenWeb`, others) — only ChenWeb's `/home3` admin surface was
actually exercised this session, so whether `tax` shows the same symptom is unverified (see §6).

## 4. Recommended fix

Surgical helper, chosen over consolidating the 11 `req()` copies into one shared `apiFetch()` — the
latter would be a larger diff touching code that isn't otherwise broken, which ChenWeb's own coding
guideline (`CLAUDE.md` §1.3, "Surgical Changes") argues against absent a separate request to do that
cleanup.

1. Add one exported helper to `shared/svelte` — natural home is `utils/auth.ts`, next to
   `clearAuthCache` — e.g. `redirectToLoginIfUnauthorized(res: Response): boolean` that checks
   `res.status === 401` (and, for `db_store` consumers, `CustomHttpStatus.NotLoggedIn` / 557 — see open
   question in §6), and if so calls `clearAuthCache()` then `window.location.href = '/login'` (or a
   `/login?redirect=<path>` variant — also §6), returning `true` so the caller can stop processing.
2. Call it from `dbstore.ts`'s `checkSystemResp` before building the 401 `JimoResponse`.
3. Call it from each of the 11 `req<T>()` implementations and `userManagementService.ts`, right after
   `if (!res.ok)`, before constructing/throwing the `Error` — short-circuit so callers don't also
   render a banner underneath the redirect.
4. Wire `checkAuthStatus()`'s not-ok branch (`auth.svelte.ts:321-337`) to the same helper, so a
   session that's already dead *before* first paint also redirects, not just mid-session failures.

## 5. Tasks

- [ ] Add `redirectToLoginIfUnauthorized` (or equivalent) to `shared/svelte/src/lib/utils/auth.ts`
- [ ] Wire it into `dbstore.ts:checkSystemResp`
- [ ] Wire it into `auth.svelte.ts:checkAuthStatus`'s not-ok branch
- [ ] Wire it into all 11 `req<T>()` helpers listed in §3 + `userManagementService.ts`
- [ ] `shared/svelte`-only change: run `bun run check` / `bun test` in `shared/svelte`, no `go work sync`
      needed
- [ ] Verify live in a ChenWeb dev session with an intentionally expired/cleared session cookie —
      hitting `/home3/...` should redirect to `/login`, not show a banner
- [ ] Resolve the open questions in §6 before implementing (redirect-back URL, `tax`/other consumers,
      557 handling)

## 6. Open questions / future related activities

- Should the redirect preserve where the user was (`/login?redirect=/home3/...`) so login returns
  them to the same page? None of the existing redirect call sites do this today.
- Does `tax` (or other `shared/svelte` consumers) show the same symptom, or does it already guard
  against this some other way? Not checked this session.
- Should `CustomHttpStatus.NotLoggedIn` (557) also redirect, or does it mean something narrower
  ("logged in but not authorized") that should stay an inline error? Requires finding where 557 is
  actually returned server-side — not done this session.
- Once the surgical fix lands, is consolidating the 11 duplicated `req<T>()` bodies into one shared
  `apiFetch()` worth a separate follow-up? Deliberately deferred out of this fix's scope.
