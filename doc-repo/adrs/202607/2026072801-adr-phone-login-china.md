# ADR 2026072801 — Login Through Phone (China Phase 1) via Kratos Native `code`/`sms`

**Date:** 2026-07-28 \
**Status:** Proposal \
**Component:** ChenWeb login UI, shared auth (`shared/go`), Kratos identities/courier \
**Authors**: Claude Code \
**Tags**: auth, kratos, sms, china, phone-login

## Change Logs
* 2026/07/28, ADR created.
* 2026/07/28, updated after live testing against a running Kratos instance (user restarted Kratos twice during this session). Three bugs found and fixed that source-reading alone hadn't caught: (1) `code.enabled: true` alone doesn't enable code-based *login*, needs `passwordless_enabled: true`; (2) Kratos's phone normalization requires full E.164 format, not the bare 11-digit number originally assumed everywhere; (3) the relay route needed to live under `/auth` to bypass ChenWeb's frontend-auth-gate middleware. Also corrected the account-not-found message ID from an assumed 4000037 to the actual 4000035. See DR5/DR8 (new) and Consequences for details.

## Context

ChenWeb's `/login` page (`web/src/lib/components/login-01.svelte`) supports email/password and Google/GitHub OAuth, both driven through Ory Kratos (`AUTH_USE_KRATOS=true`). A partner team in China needs users to be able to log in with a Chinese mobile number + SMS verification code — the dominant consumer login pattern there, where many users have no email address at all.

A reference implementation exists in `ThirdParty-2/bzton-www` (Vue frontend) and `ThirdParty-2/bzton-be` (Java backend): a thin wrapper around Aliyun's Dysmsapi `SendSms` action, a 6-digit code cached in Redis with a 5-minute TTL, and a phone-login endpoint that auto-registers a new account on first use. It is a useful reference for the SMS mechanics but not for the architecture: it hard-codes Aliyun credentials in source, has no server-side rate limit on the send-code endpoint (only a client-side 60s timer, trivially bypassed), and its CN phone regex (`^1[3,4,5,7,8][0-9]{9}$`) omits currently valid prefixes.

Separately, this workspace's `Kratos/` instance (built from source, `Kratos/kratos/kratos.yml` + `identity.schema.json`) is **shared** between `ChenWeb` and `tax` (Mirai Tax CPA) in this environment — both point at the same `KRATOS_PUBLIC_URL`/`KRATOS_ADMIN_URL` on `127.0.0.1`. Any schema/config change here is visible to both projects at the Kratos API level, even though only ChenWeb's frontend will expose a phone-login UI.

Kratos already has a native `code` credential method that can be bound to any identity trait via `via`, and a courier subsystem that supports a custom `channels` entry (`id: "sms"`, `type: "http"`) for SMS delivery to an arbitrary HTTP endpoint. Before this ADR, `identity.schema.json` only defined `email`/`username` traits, and courier was SMTP-only.

## Decision

### DR1 — Extend Kratos natively, do not build a bespoke phone/OTP side-channel

Google/GitHub login in this codebase (`HandleGoogleLoginKratos`, `kratos.go:1861`) works by driving Kratos's own `self-service/login/browser` flow, not by minting sessions through a parallel identity system. Phone login follows the same precedent: a `phone` trait + Kratos's native `code` method (`via: "sms"`), not a hand-rolled OTP store + manual Admin-API identity creation.

**Rejected alternative**: build phone+OTP entirely in `shared/go` (own Redis/Postgres OTP store, direct Aliyun call, then create-or-fetch a Kratos identity via the Admin API and mint a session manually). Rejected because it duplicates OTP storage/expiry/identity-creation logic Kratos already provides, and diverges from the only existing non-password login pattern in this codebase.

### DR2 — SMS delivery relays through a new Go endpoint, not a Kratos Jsonnet template calling Aliyun directly

Aliyun's Dysmsapi `SendSms` is a signed RPC-style API (HMAC-SHA1 over a canonicalized query string). Kratos's courier `request_config.body` is a static Jsonnet template — it cannot compute that signature. So `Kratos/kratos/kratos.yml`'s `courier.channels` entry (`id: sms`, `type: http`) points at a new endpoint, `POST /internal/sms-courier/send`, implemented in `shared/go/api/auth/sms_relay.go` (`HandleSMSCourierRelay`), which performs the actual signed Aliyun call. The Jsonnet template (`Kratos/kratos/templates/courier/sms/request.config.jsonnet`) only reshapes Kratos's `ctx` into `{to, code}` for the relay.

Aliyun credentials (`ALIYUN_SMS_ACCESS_KEY_ID/SECRET/SIGN_NAME/TEMPLATE_CODE`) live only in `ChenWeb/.env` (gitignored), never in Kratos's config or source — a direct fix of the bzton reference's hard-coded-credentials anti-pattern.

### DR3 — `phone` trait is additive; `traits.anyOf` gains a third alternative

`identity.schema.json`'s `traits.anyOf` required `email` or `username`. Added `{"required": ["phone"]}` as a third alternative so existing email/username identities are unaffected and a phone-only identity (no email) is valid, matching bzton's behavior where phone-login users don't need an email.

### DR4 — CN phone validation uses a broad structural pattern, not an enumerated prefix list

`^1[3-9][0-9]{9}$` for the *user-facing* bare 11-digit number (frontend input, `kratos_phone.go` request validation) instead of bzton's `^1[3,4,5,7,8][0-9]{9}$`, which is already missing currently-valid prefixes. Carrier prefix assignments change over time; a structural check plus the SMS gateway's own delivery failure is more durable than trying to keep an exact prefix enumeration current. Note this is distinct from the E.164 pattern Kratos itself requires internally — see DR8.

### DR5 — Login and registration are two chained Kratos flows, not one flow that transparently does both

Read directly from Kratos source (`selfservice/strategy/idfirst/strategy_login.go:80-196`, `selfservice/strategy/code/strategy_login.go:371-428`): Kratos's login flow with the `code` method does **not** auto-create an identity for an unrecognized identifier.

**Correction after live testing** (source reading alone got the specific error wrong): the actual error returned is `schema.NewNoCodeAuthnCredentials()`, message ID **4000035** (`ErrorValidationNoCodeUser`, text "This account does not exist or has not setup sign in with code."), not `schema.NewAccountNotFoundError()` / 4000037 as first assumed — confirmed via a direct curl trace against a running Kratos instance. `kratos_phone.go`'s `kratosMessageIDAccountNotFound` was corrected to 4000035.

`shared/go/api/auth/kratos_phone.go`'s `HandlePhoneSendCodeKratos` therefore: attempts a native login flow first; if the response carries message ID 4000035, falls back to a native registration flow with the same phone number. The registration flow's `after.code.hooks: [{hook: session}]` (new in `kratos.yml`, alongside the existing `password`/`oidc` hooks) creates the identity and issues a session in the same step once the code is verified — this is what gives phone login its bzton-like "login doubles as signup" behavior, without bzton's `platform.code.enable` global kill-switch anti-pattern.

### DR7 (new) — Login via the `code` method requires `passwordless_enabled: true`, not just `enabled: true`

Found via live testing: `selfservice.methods.code.enabled: true` only covers registration/recovery/verification codes. `Strategy.Login()` (`selfservice/strategy/code/strategy_login.go`) checks `SelfServiceCodeStrategy(ctx).PasswordlessEnabled` (or `.MFAEnabled`) first and bails out with `ErrStrategyNotResponsible` if both are false — surfacing as a generic "no strategy found" error (message 4010002), not an account-not-found error, which would have silently broken the login→registration fallback in DR5. Fixed by adding `selfservice.methods.code.passwordless_enabled: true` to `kratos.yml`.

### DR8 (new) — Phone numbers must be sent to Kratos in E.164 format, not the bare national format users type

Found via live testing: Kratos's identifier normalization (`Kratos/src/kratos/x/normalize.go`) calls `phonenumbers.Parse(value, "")` with an **empty default region** — it cannot infer a country from a bare `13800003333` and rejects it with "invalid country code" (message 4000001). Kratos gives no config knob for a default region; the caller must always supply E.164.

Fix: `identity.schema.json`'s `phone` trait pattern is `^\+861[3-9][0-9]{9}$` (E.164), not the bare pattern originally used. `kratos_phone.go` adds `toE164CN()`, prepending `+86` to the user-typed number before it's ever sent to Kratos as `Identifier` or `Traits.phone` — the bare 11-digit form (DR4) is only ever seen by the user and by request validation, never by Kratos itself. `sms_relay.go` correspondingly validates the *E.164* form it receives from Kratos's courier (`cnMobileE164Pattern`) and strips the `+86` prefix before calling Aliyun, whose domestic `SendSms` action expects the bare national number.

### DR9 (new) — The SMS relay route must live under `/auth`, not a standalone `/internal` prefix

Found via live testing: ChenWeb's global frontend-routing middleware (`server/api/routes.go`) only exempts paths under `/api`, `/auth`, `/shared_api`, `/ws` (plus a short static-asset allowlist) from its session-auth gate. The relay was originally registered at `/internal/sms-courier/send`, which matches none of those prefixes, so Kratos's courier call (which carries no session cookie) was rejected with a 401 before ever reaching `HandleSMSCourierRelay`. Moved to `/auth/internal/sms-courier/send`, consistent with how `/auth/phone/send-code` and `/auth/phone/verify` already worked without a session.

### DR6 — Server-side send-rate limiting reuses the existing in-process `RateLimiter`, no new table

`shared/go/api/auth/rate_limiter.go` already implements a sliding-window limiter used for login/signup/password-reset (`loginRateLimiter`, `signupRateLimiter`, `accountLockoutRateLimiter`). Added `smsRateLimiter`, keyed by phone number, checked in `HandleSMSCourierRelay` before calling Aliyun. This directly closes the gap in the bzton reference, whose send-code endpoint has no server-enforced cooldown.

### DR7 — Feature-flagged rollout, default off

`enable_phone_login` (`ChenWeb/server/cmd/config/config.go` → `GET /api/config` → `login-01.svelte`) defaults to **false**, unlike the OAuth flags which default to true — the opposite default, because this flow depends on an external Aliyun account/sign-name approval and a shared-infrastructure config change that hasn't been live-tested end-to-end yet (see Consequences).

## Alternative Decisions

- **Bespoke OTP side-channel** (own store + manual Kratos Admin-API identity creation) — rejected, see DR1.
- **Kratos Jsonnet template calls Aliyun directly** — rejected, see DR2: Jsonnet cannot compute Aliyun's RPC signature.
- **Copy bzton's exact regex/rate-limiting/credential-handling** — rejected: bzton's implementation has three specific gaps (hard-coded credentials, no server-side send throttle, stale prefix regex) that this design deliberately does not replicate.
- **Separate Kratos instance for ChenWeb** — not adopted for Phase 1 (adds real operational cost); flagged as a possible future follow-up if `ChenWeb`'s and `tax`'s auth requirements diverge further, given the shared-instance caveat in DR1's context.

## Implementation

### Code Changes

- `Kratos/kratos/identity.schema.json` — add `phone` trait, extend `traits.anyOf`
- `Kratos/kratos/kratos.yml` — add `courier.channels` (`sms`), add `registration.after.code.hooks: [{hook: session}]`
- `Kratos/kratos/templates/courier/sms/request.config.jsonnet` — new Jsonnet request-body template
- `shared/go/api/auth/sms_relay.go` — new: `HandleSMSCourierRelay`, Aliyun Dysmsapi signed `SendSms` call, shared-secret auth
- `shared/go/api/auth/kratos_phone.go` — new: `HandlePhoneSendCodeKratos`, `HandlePhoneVerifyCodeKratos`
- `shared/go/api/auth/rate_limiter.go` — add `smsRateLimiter` / `CheckSMSSendRateLimit`
- `shared/go/api/auth/kratos.go` — add `Phone` to `identityInfo`/`extractIdentityInfo`
- `shared/go/api/router.go` — register `/internal/sms-courier/send`, `/auth/phone/send-code`, `/auth/phone/verify` (Kratos-mode only)
- `ChenWeb/server/cmd/config/config.go`, `ChenWeb/server/api/confighandler/handler.go` — `enable_phone_login` config flag
- `ChenWeb/web/src/lib/components/login-01.svelte` — phone-login UI mode
- `ChenWeb/.env` — `SMS_RELAY_SHARED_SECRET`, `ALIYUN_SMS_*` (placeholder pending a real Aliyun account)

### Environment Variables

- `SMS_RELAY_SHARED_SECRET` — must match the `X-Internal-Relay-Secret` header value in `Kratos/kratos/kratos.yml`'s `courier.channels` entry
- `ALIYUN_SMS_ACCESS_KEY_ID`, `ALIYUN_SMS_ACCESS_KEY_SECRET`, `ALIYUN_SMS_SIGN_NAME`, `ALIYUN_SMS_TEMPLATE_CODE` — placeholders as of this ADR; real values pending Aliyun account/sign-name/template approval

### Data Formats

No new database tables. Phone identities live entirely in Kratos's own `identities`/`identity_credentials` tables, same as email/password. The pre-existing, currently-unused `users.user_mobile` column (legacy non-Kratos path) is untouched.

## Operational Behaviors

- Ships behind `enable_phone_login`, default **false**. Enable only after: (a) Kratos is restarted with the new config and (b) a live end-to-end test (real phone → real Aliyun SMS → code → session) has been run, since the login/registration-fallback logic in `kratos_phone.go` is based on reading Kratos's source, not yet a live trace (see Consequences).
- Kratos restart required for the schema/courier changes to take effect — this instance is shared with `tax`; restart is a deliberate, communicated step, not incidental. No `mise build-kratos` rebuild needed (config-only change).

## Consequences

### Positive

- Phone login reuses Kratos's identity/session machinery instead of adding a second identity system.
- Fixes three concrete security/robustness gaps present in the bzton reference (hard-coded credentials, no server-side send throttle, stale phone regex).
- Additive schema/config changes: no risk to existing email/OAuth login for either ChenWeb or tax.

### Negative / accepted costs

- This Kratos instance is shared with `tax`; every change here needs a "did email login for tax still work" check, not just a ChenWeb-scoped one.
- The login-then-registration-fallback logic (message ID 4000037 detection) has not yet been exercised against a live Kratos response — it is correct per source reading but unverified in practice pending a Kratos restart and a real Aliyun account.
- `smsRateLimiter` is in-process (resets on restart, not shared across horizontally-scaled instances) — an accepted trade-off already made for this codebase's other auth rate limiters.
- Real Aliyun account/sign-name/template approval is a business/ops dependency outside this change's control; phone login cannot send real SMS until that lands.

## Tests

- `cd shared/go && go build ./... && go vet ./api/auth/...` — passing as of this ADR.
- `cd ChenWeb/web && bun run check` — passing for `login-01.svelte` (pre-existing unrelated errors in other files not touched by this change).
- Not yet run: live Kratos restart + curl trace of the login/registration-fallback branch; real Aliyun SMS send; full browser E2E. Blocked on a real Aliyun account and an explicit go-ahead to restart the shared Kratos instance.

## Documentation Impact

- `Kratos/CLAUDE.md`'s "Add More User Fields" section updated with the actual `phone` trait / SMS courier channel configuration (previously only an unimplemented example snippet).
- This ADR is the "why"; `ChenWeb/openspec/changes/add-phone-login-china/{proposal,design,tasks}.md` carries the detailed task-by-task implementation record and is the up-to-date source for exactly what has/hasn't been verified.
- Nothing else in the workspace's existing docs becomes stale — no prior doc described phone login or SMS as a ChenWeb capability.

## References

- `ChenWeb/openspec/changes/add-phone-login-china/proposal.md`
- `ChenWeb/openspec/changes/add-phone-login-china/design.md`
- `ChenWeb/openspec/changes/add-phone-login-china/specs/phone-login-china/spec.md`
- `ChenWeb/openspec/changes/add-phone-login-china/tasks.md`
- `Kratos/CLAUDE.md`
- `shared/go/api/auth/kratos_phone.go`, `sms_relay.go`, `rate_limiter.go`, `kratos.go`
- `Kratos/kratos/identity.schema.json`, `kratos.yml`, `templates/courier/sms/request.config.jsonnet`
