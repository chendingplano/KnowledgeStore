# Chinese Cell-Phone (SMS-code) Sign-in — Implementation

**Date:** 2026-09-11
**Scope:** How phone-number + SMS-verification-code login/sign-up is built in ChenWeb.
For an engineer who needs to understand, debug, extend, or re-deploy it. Phase 1 is
**Chinese mobile numbers only**. Operations (how it's wired on the `onto.bzton.cn` box)
are in `2026090701-devdoc-start-system-onto.md` §2.1.

Related: openspec change `ChenWeb/openspec/changes/add-phone-login-china/`,
ADR `KnowledgeStore/doc-repo/adrs/202607/2026072801-adr-phone-login-china.md`,
memory `project_chenweb_phone_login_deploy`.

---

## 1. What it is

A "Log in with Phone" mode on the DeepDocs login page. The user types an 11-digit
Chinese mobile number, receives a 6-digit code by SMS, types it back, and is logged
in. **A number with no existing account is registered on the spot** (JIT) — phone
login doubles as sign-up.

It is built **on Kratos's own `code` credential method** (`via: "sms"`), the same way
email login uses Kratos's `password`/`code` methods — not a bespoke OTP table or a
parallel session system. Kratos owns the identity, the code, its TTL, and the
session. ChenWeb only:

- drives Kratos's native login/registration flows (`shared/go/api/auth/kratos_phone.go`),
- relays Kratos's outbound SMS to Aliyun, because Kratos's courier can't compute
  Aliyun's request signature (`shared/go/api/auth/sms_relay.go`),
- treats a phone-code session as "verified" (`shared/go/api/auth/kratos.go`).

```
 browser (login-01.svelte)
   │  POST /auth/phone/send-code {phone:"186…"}
   ▼
 ChenWeb  HandlePhoneSendCodeKratos            shared/go/api/auth/kratos_phone.go
   │  1. Kratos CreateNativeLoginFlow + submit code method (identifier=+86186…)
   │     └─ Kratos msg 4000035 "no code user"?  ── no ──► SMS queued, flow_type="login"
   │                          └─ yes ──► 2. Kratos CreateNativeRegistrationFlow + submit
   │                                        (traits.phone=+86186…)     flow_type="registration"
   ▼
 Kratos  code strategy → courier "sms" channel (kratos.yml)
   │  renders request.config.jsonnet → POST {to:"+86186…", code:"NNNNNN"}
   ▼
 ChenWeb  HandleSMSCourierRelay  /auth/internal/sms-courier/send   sms_relay.go
   │  shared-secret check → per-phone rate limit → strip "+86" → signed Aliyun SendSms
   ▼
 Aliyun Dysmsapi → SMS to the handset
 ───────────────────────────────────────────────────────────────────────────────
   browser  POST /auth/phone/verify {phone, code, flow_id, flow_type}
   ▼
 ChenWeb  HandlePhoneVerifyCodeKratos
   │  submit code to the same Kratos flow → Kratos issues identity + session
   │  set session_token cookie ; AddSessionLog ; GetRedirectURL
   ▼
   { "status":"ok", "redirect_url":"https://…/semos/workspace" }  + Set-Cookie: session_token=ory_st_…
```

---

## 2. Component map

| Piece | File | Responsibility |
|---|---|---|
| Frontend UI | `ChenWeb/web/src/lib/components/login-01.svelte` | `phone` mode gated on `enable_phone_login`; CN regex `^1[3-9]\d{9}$`; calls `send-code` / `verify`; 60 s client-side resend cooldown |
| Config flag | `ChenWeb/server/cmd/config/config.go` (`FrontendConfigSection.EnablePhoneLogin`), `ChenWeb/server/api/confighandler/handler.go` | `[frontend] enable_phone_login` → `GET /api/config` `enable_phone_login` (default **false**) |
| Flow handlers | `shared/go/api/auth/kratos_phone.go` | `HandlePhoneSendCodeKratos`, `HandlePhoneVerifyCodeKratos`, `toE164CN`, `kratosMessageIDAccountNotFound = 4000035` |
| Route registration | `shared/go/api/router.go` | `/auth/phone/send-code`, `/auth/phone/verify`, `/auth/internal/sms-courier/send` — all Kratos-mode only (`AUTH_USE_KRATOS=true`) |
| SMS relay | `shared/go/api/auth/sms_relay.go` | `HandleSMSCourierRelay`; `sendAliyunSMS` (hand-rolled RPC signing); `cnMobileNumberPattern`, `cnMobileE164Pattern` |
| Rate limiting | `shared/go/api/auth/rate_limiter.go` | `CheckLoginRateLimit` (IP, on send-code); `smsRateLimiter` / `CheckSMSSendRateLimit` (per-phone, in the relay) |
| Verified gate | `shared/go/api/auth/kratos.go` | `identityPhoneProvenByCode`, `isIdentityVerified` — a phone-code session counts as verified |
| Kratos identity schema | `Kratos/kratos/identity.schema.json` | `phone` trait, `credentials.code {identifier:true, via:"sms"}`, `anyOf` includes `{required:["phone"]}` |
| Kratos server config | `Kratos/kratos/kratos.yml` | `methods.code.passwordless_enabled`, `registration.after.code` session hook, `courier.channels[sms]` |
| SMS courier template | `Kratos/kratos/templates/courier/sms/request.config.jsonnet` | reshapes Kratos's courier `ctx` → `{to, code}` for the relay |

---

## 3. Request flow in detail

### 3.1 `POST /auth/phone/send-code`  → `HandlePhoneSendCodeKratos`

Body `{"phone":"18625008130"}` (bare 11-digit).

1. **IP rate limit** — `CheckLoginRateLimit(c.RealIP())`; over limit → `429`.
2. **Validate** against `cnMobileNumberPattern` = `^1[3-9]\d{9}$` → else `400 "invalid CN mobile number"`.
3. `e164Phone := toE164CN(req.Phone)` — literally `"+86" + bare`.
4. **Try login first.** `CreateNativeLoginFlow` then `UpdateLoginFlow` with
   `UpdateLoginFlowWithCodeMethod{Method:"code", Identifier:&e164Phone}`.
   - The Go SDK returns a **non-nil error** here even on success, because the flow
     isn't "complete" until the code is submitted. So inspect the response body:
   - `kratosBodyHasMessageID(body, 4000035)` — walks all nested `messages[].id`.
     - **not found** ⇒ Kratos accepted the identifier and is asking for the code ⇒
       the SMS was queued ⇒ return `{status:"ok", flow_id, flow_type:"login"}`.
     - **found** (`ErrorValidationNoCodeUser`, "This account does not exist or has
       not set up sign in with code") ⇒ no identity ⇒ step 5.
5. **Fall back to registration.** `CreateNativeRegistrationFlow` then
   `UpdateRegistrationFlow` with
   `UpdateRegistrationFlowWithCodeMethod{Method:"code", Traits:{"phone":e164Phone}}`.
   Same "error-means-awaiting-code" semantics. Return
   `{status:"ok", flow_id, flow_type:"registration"}`.

The frontend stores `flow_id` **and** `flow_type` and echoes both back to `verify`.

### 3.2 SMS dispatch (Kratos → relay → Aliyun)

Submitting the code method to the flow makes Kratos's **code strategy** generate the
OTP and hand it to the courier. Because the `sms` channel is `type: http`, Kratos
renders `request.config.jsonnet` against its per-dispatch `ctx` and POSTs the result:

```jsonnet
function(ctx) {
  to: ctx.recipient,                       // "+8618625008130"
  code:
    if "login_code" in ctx.template_data then ctx.template_data.login_code
    else if "registration_code" in ctx.template_data then ctx.template_data.registration_code
    else if "recovery_code" in ctx.template_data then ctx.template_data.recovery_code
    else if "verification_code" in ctx.template_data then ctx.template_data.verification_code
    else null,
}
```

`HandleSMSCourierRelay` (`POST /auth/internal/sms-courier/send`):

1. `SMS_RELAY_SHARED_SECRET` env unset → `500 "sms relay is not configured"`.
2. `X-Internal-Relay-Secret` header ≠ the secret (constant-time compare) → `401`.
3. Decode `{to, code}`. `to` must match `cnMobileE164Pattern` = `^\+861[3-9]\d{9}$` → else `400`.
4. `CheckSMSSendRateLimit(to)` — per-phone, over limit → `429`.
5. `bareNumber := strings.TrimPrefix(to, "+86")` — Aliyun's **domestic** `SendSms`
   wants the bare national number, not E.164.
6. `sendAliyunSMS`:
   - `loadAliyunSMSConfig()` reads `ALIYUN_SMS_ACCESS_KEY_ID / _SECRET / _SIGN_NAME
     / _TEMPLATE_CODE`; any missing → error → `502`.
   - Builds the RPC request (`Action=SendSms`, `Version=2017-05-25`,
     `RegionId=cn-hangzhou`, `TemplateParam={"code":"NNNNNN"}`), signs it
     (sorted params → canonical query → `POST&%2F&…` → HMAC-SHA1 with key
     `<secret>&` → base64), POSTs to `https://dysmsapi.aliyuncs.com/`.
   - Parses `{Code, Message}`; `Code != "OK"` → error → `502`.
7. Success → `200`, log `sms code dispatched`.

Kratos records the outcome in its own `courier_messages` / `courier_message_dispatches`
tables (status `queued`→`sent` on success, `→ abandoned` after ~5–6 failed retries).

### 3.3 `POST /auth/phone/verify`  → `HandlePhoneVerifyCodeKratos`

Body `{"phone","code","flow_id","flow_type"}`.

- Validate phone/code/flow_id; `e164Phone := toE164CN(...)`.
- `switch flow_type`:
  - `"registration"` → `UpdateRegistrationFlow(flow_id)` with
    `{Method:"code", Code:&code, Traits:{"phone":e164Phone}}` → `result.Session`,
    `result.SessionToken`, `result.Identity`.
  - `"login"` → `UpdateLoginFlow(flow_id)` with
    `{Method:"code", Code:&code, Identifier:&e164Phone}` → `result.Session`,
    `result.SessionToken`, `session.Identity`.
  - error → `parseKratosUIError(body)` → `401` ("Invalid or expired code").
- `setSessionTokenCookie(c, *sessionToken)` — cookie **`session_token`** (not
  `ory_kratos_session`; that name is reserved for Kratos's own browser-flow cookie),
  `Path=/`, `HttpOnly`, `Secure` (per `shouldUseSecureCookies`), `SameSite=Lax`,
  `Expires = now + cookie_timeout_hours`.
- `sysdatastores.AddSessionLog{LoginMethod:"kratos_phone_"+flow_type, …}`.
- `redirectURL := GetRedirectURL(rc, req.Phone, false, false)` — see gotcha 7.
- `200 {"status":"ok","redirect_url":…}`.

The frontend does `window.location.href = data.redirect_url`.

### 3.4 Session validation on later requests

`authmiddleware` → `ValidateSession` (`kratos.go`): tries browser cookies first
(`ory_kratos_session`), then the `session_token` cookie via `X-Session-Token` to
Kratos `/sessions/whoami`. A phone session resolves via the **`session_token`** path
(Attempt 2). Then the **verified gate** runs — see gotcha 6.

---

## 4. Gotchas (each cost real debugging time)

> **1 — Kratos needs E.164, always.** `Kratos/src/kratos/x/normalize.go` calls
> `phonenumbers.Parse(value, "")` with **no default region**, so a bare `18625008130`
> is rejected as "invalid country code" (Kratos message 4000001). There is no config
> knob for a default region. `toE164CN()` prepends `+86` before the number ever
> reaches Kratos as an `Identifier` or a `traits.phone`. Users type and see the bare
> 11-digit form; every stored/transmitted value is `+86…`.

> **2 — `code.enabled: true` is not enough for code *login*.** You also need
> `selfservice.methods.code.passwordless_enabled: true` in `kratos.yml`. Without it
> `Strategy.Login()` returns `ErrStrategyNotResponsible` and Kratos answers with a
> generic "no strategy found" (message **4010002**) instead of the account-not-found
> error the fallback logic keys on. Nothing looks obviously broken until you read the
> message ID.

> **3 — Code login does not auto-create an identity.** For an unknown identifier the
> login flow's code strategy returns `schema.NewNoCodeAuthnCredentials()` — message ID
> **4000035** (`ErrorValidationNoCodeUser`). (Not 4000037 / `NewAccountNotFoundError`;
> that's a different, unreached path.) So `send-code` must attempt a **login** flow
> first and, only on 4000035, start a **registration** flow with the same number —
> two chained Kratos flows. Message IDs are stable across Kratos versions, so keying
> on 4000035 is safe.

> **4 — The relay route must live under `/auth/`.** ChenWeb's frontend catch-all
> middleware (`server/api/routes.go`) only exempts paths under `/api`, `/auth`,
> `/shared_api`, `/ws` from the session-auth gate. Kratos's courier call carries no
> session cookie, so a route like `/internal/sms-courier/send` gets a `401` before the
> handler ever runs. It is `/auth/internal/sms-courier/send`.

> **5 — The Aliyun access key is IP-restricted.** `ALIYUN_SMS_ACCESS_KEY_ID`
> (with sign `润申标准化`, template `SMS_223202121`) is the
> **same key bzton production uses** (hard-coded in their
> `bzton-be/.../AliyunSms/AliyunSmsEntity.java`). Its RAM policy only permits
> `SendSms` from bzton's server IPs. From anywhere else Aliyun returns
> `InvalidAccessKeyId.AccessPolicyDenied — Specified access key denied due to access
> policy` (not a signature error — signing is fine). `onto.bzton.cn` runs on
> `210.5.158.91`, the **same public IP as `www.bzton.com`**, so it works there. It
> **cannot** work from a dev machine. If ChenWeb ever moves to a different egress IP,
> either get that IP added to the key's RAM `acs:SourceIp` condition / SMS anti-fraud
> allowlist on the Aliyun account, or ask bzton for a dedicated un-restricted key
> (drop it into `ALIYUN_SMS_ACCESS_KEY_ID/_SECRET`, restart `chenweb`).

> **6 — Phone identities fail ChenWeb's "verified" gate unless the code says
> otherwise.** `HandleAuthMeKratos` and `authmiddleware` block any identity with no
> **verified verifiable address** (`isIdentityEmailVerified` → 403 `EMAIL_NOT_VERIFIED`
> on every `/api/v1/*` call). Email gets one from the verification link; Google from an
> OIDC auto-verify exception; **phone gets none** — the trait carries no `verification`
> block, code registration never populates a verifiable address, and things that look
> like fixes are dead ends:
> - Kratos's `PUT /admin/identities/{id}` **silently ignores**
>   `verifiable_addresses[].verified` — the address stays `pending`.
> - Adding `"verification": {"via":"sms"}` to the phone trait requires also adding a
>   `"format"` (Kratos: *"a format is required if verification is enabled"*), and then
>   registration only creates a `pending` SMS address anyway.
>
> The fix is **code-side** (`kratos.go`, jj commit `322a`): `identityPhoneProvenByCode`
> returns true when `traits.phone` matches `^\+861[3-9]\d{9}$`, and `isIdentityVerified
> = isIdentityEmailVerified || identityPhoneProvenByCode` is used at the three gate
> sites (`HandleAuthMeKratos`, `buildUserInfoFromKratosSession`, the RC session path).
> Completing an SMS code *is* proof of ownership — the same trust basis as the OIDC
> exception. The `phone` trait is only ever written by
> `HandlePhoneSendCodeKratos`'s registration flow, so its presence is sufficient;
> `identity.Credentials` **can't** be inspected here because Kratos omits credentials
> from the `/sessions/whoami` identity that every caller has.

> **7 — Post-login redirect.** `GetRedirectURL` (`shared/go/api/auth/auth-util.go`)
> returns `<APP_BASE_URL> + os.Getenv("VITE_DEFAULT_NORM_ROUTE")` (or
> `VITE_DEFAULT_ADMIN_ROUTE` for admins). If the env var is unset it falls back to
> `/dashboard` and logs `ERROR missing VITE_DEFAULT_NORM_ROUTE`. This is shared by
> email, Google and phone login. On `onto.bzton.cn` both are set to
> `/semos/workspace` in the box `.env`.

> **8 — Two rate limiters, and the per-phone one counts failures.**
> `CheckLoginRateLimit` (IP: 5 / 15 min, 15 min block) fires on `send-code`.
> `smsRateLimiter` / `CheckSMSSendRateLimit` (phone: **5 / hour, 1 hour block**) fires
> inside the relay, *before* the Aliyun call, and is **not** reset on failure. Kratos's
> courier retries a failing dispatch ~5–6 times, so a single broken send (e.g. wrong
> Aliyun IP) burns the whole hourly quota and locks that number out for an hour.
> Restarting `chenweb` clears the in-memory limiter; use a fresh number to retest.

---

## 5. Configuration checklist

### 5.1 Kratos (`Kratos/kratos/…`)

`identity.schema.json` — under `properties.traits.properties`:

```json
"phone": {
  "type": "string",
  "title": "Phone Number",
  "pattern": "^\\+861[3-9][0-9]{9}$",
  "ory.sh/kratos": {
    "credentials": { "code": { "identifier": true, "via": "sms" } }
  }
}
```
plus `{ "required": ["phone"] }` in `traits.anyOf` (additive; does not affect
existing email/username identities). **No `verification` / `format` block** — see
gotcha 6.

`kratos.yml`:

```yaml
selfservice:
  methods:
    code:
      enabled: true
      passwordless_enabled: true          # gotcha 2
  flows:
    registration:
      after:
        code:
          hooks: [ { hook: session } ]    # JIT identity + session on first verify

courier:
  template_override_path: <ABS>/Kratos/kratos/templates
  channels:
    - id: sms
      type: http
      request_config:
        url: http://127.0.0.1:<CHENWEB_HTTP_PORT>/auth/internal/sms-courier/send
        method: POST
        headers:
          X-Internal-Relay-Secret: <== SMS_RELAY_SHARED_SECRET, byte-for-byte
        body: file://<ABS>/Kratos/kratos/templates/courier/sms/request.config.jsonnet
```

Kratos ships default SMS **body** templates for the `code` method, so no
`courier.templates` override is needed — only the `request.config.jsonnet`
request-shaper.

> All paths and the port in `kratos.yml` are environment-specific. The Mac copy uses
> `/Users/cding/…` and port `8080`; the box copy must use `/home/gui/…` and `8090`.
> `kratos.yml` is gitignored, so there is no canonical version — keep them in sync by
> hand. (A stale Mac path/port here was the last thing blocking the 2026-09-11 launch.)

### 5.2 ChenWeb

| var / setting | where | value |
|---|---|---|
| `AUTH_USE_KRATOS` | env | `true` — the phone routes only register in Kratos mode |
| `enable_phone_login` | `config.toml` / `config.local.toml` `[frontend]` | `true` (default false) |
| `SMS_RELAY_SHARED_SECRET` | env (in ChenWeb/.env) | 32-byte hex; **must equal** the `X-Internal-Relay-Secret` header in `kratos.yml`; (secret — see secrets store, not committed) |
| `ALIYUN_SMS_ACCESS_KEY_ID` | env (in ChenWeb/.env) | (secret — see secrets store, not committed; shared w/ bzton — gotcha 5) |
| `ALIYUN_SMS_ACCESS_KEY_SECRET` | env (in ChenWeb/.env) | (secret — see secrets store, not committed) |
| `ALIYUN_SMS_SIGN_NAME` | env (in ChenWeb/.env) | `润申标准化` (approved signature) |
| `ALIYUN_SMS_TEMPLATE_CODE` | env (in ChenWeb/.env) | `SMS_223202121` — a verification-code template whose variable is `${code}` |
| `VITE_DEFAULT_NORM_ROUTE` / `_ADMIN_ROUTE` | env (in ChenWeb/.env) | `/semos/workspace` (gotcha 7) |
| `KRATOS_ADMIN_URL` | env (in ChenWeb/.env) | `http://127.0.0.1:4434` |

> This doc originally had the real `ALIYUN_SMS_ACCESS_KEY_ID` / `_SECRET` and
> `SMS_RELAY_SHARED_SECRET` values inline; GitHub push protection caught it on the
> ChenWeb repo (2026-09-12) before it left the machine. Redacted here and in
> `ChenWeb/deploy/phone-login/02-chenweb-env.md` / `03-kratos-config.md`, and the
> commits that introduced them were rewritten to drop the plaintext from history.
> Never put live credentials in a committed doc — reference the secrets store instead.

Frontend: `enable_phone_login` gates the "Log in with Phone" link and the whole
`phone` block in `login-01.svelte`. Rebuild the frontend into the binary
(`server/api/webbuild` is `//go:embed`-ed and gitignored) — `mise run
build-server-linux` does this automatically.

---

## 6. Test end-to-end

From the box (or wherever the relay's Aliyun IP restriction is satisfied):

```bash
NUM=18625008130
DSN=$(grep '^DSN=' ~/Workspace/Kratos/kratos.env | cut -d= -f2-)

# 1. config flag live
curl -s http://127.0.0.1:8090/api/config | grep -o '"enable_phone_login":[^,}]*'   # :true

# 2. relay secret enforced
curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  http://127.0.0.1:8090/auth/internal/sms-courier/send \
  -H 'X-Internal-Relay-Secret: wrong' -d '{"to":"+8613800000000","code":"0"}'       # 401

# 3. Kratos offers the code method
curl -s http://127.0.0.1:4433/self-service/login/api | grep -o '"group":"code"'     # match

# 4. send
curl -s -X POST http://127.0.0.1:8090/auth/phone/send-code \
  -H 'Content-Type: application/json' -d "{\"phone\":\"$NUM\"}"
#   -> {"flow_id":"…","flow_type":"login"|"registration","status":"ok"}

# 5. courier result  (status 2 = SENT, 4 = ABANDONED)
psql "$DSN" -c "select status,send_count,left(body,40),created_at from courier_messages
                where recipient='+86$NUM' order by created_at desc limit 1;"
MID=$(psql "$DSN" -Atqc "select id from courier_messages where recipient='+86$NUM'
                         order by created_at desc limit 1")
psql "$DSN" -x -c "select status,error from courier_message_dispatches
                   where message_id='$MID' order by created_at desc limit 2;"

# 6. verify (code from the handset, or from courier_messages.body while testing)
curl -s -i -X POST http://127.0.0.1:8090/auth/phone/verify -H 'Content-Type: application/json' \
  -d "{\"phone\":\"$NUM\",\"code\":\"NNNNNN\",\"flow_id\":\"…\",\"flow_type\":\"login\"}"
#   -> 200  Set-Cookie: session_token=ory_st_…   {"status":"ok","redirect_url":"…/semos/workspace"}

# 7. identity + session usable
TOK=ory_st_…
curl -s http://127.0.0.1:4434/admin/identities?credentials_identifier=%2B86$NUM | python3 -m json.tool
curl -s -o /dev/null -w '%{http_code}\n' --cookie "session_token=$TOK" \
  http://127.0.0.1:8090/api/v1/workspace/announcements                              # 200, not 403
```

chenweb log lines to grep: `no identity for phone`, `phone registration code requested`,
`sms code dispatched`, `aliyun sms send failed`, `phone login success`,
`unverified user blocked` (should be **absent**).

---

## 7. Extending beyond China (Phase 2, not built)

Everything CN-specific is a regex or a hard-coded `+86`:

- `login-01.svelte` `cnPhonePattern` `/^1[3-9]\d{9}$/`
- `kratos_phone.go` `cnMobileNumberPattern`, `toE164CN` (`"+86" + n`)
- `sms_relay.go` `cnMobileE164Pattern`, `strings.TrimPrefix(phone, "+86")` (+ Aliyun's
  domestic `SendSms` — international send is a different action / a different provider)
- `kratos.go` `identityPhoneProvenByCode` uses `cnMobileE164Pattern`
- `identity.schema.json` `phone.pattern`

A general E.164 build would: collect the country code on the frontend, keep the
number in E.164 everywhere (drop `toE164CN`), widen the patterns to `^\+[1-9]\d{6,14}$`,
and branch SMS delivery by country (Aliyun domestic vs. Aliyun International / Twilio /
a Chinese aggregator). WeChat mini-program login (`wxOpenId`) is a separate track.

---

## See also

- `2026090701-devdoc-start-system-onto.md` §2.1 — running/troubleshooting phone login on the box
- `2026072401-devdoc-deploy-production.md` — build + deploy runbook
- `ChenWeb/openspec/changes/add-phone-login-china/` — proposal / design / tasks
- `KnowledgeStore/doc-repo/adrs/202607/2026072801-adr-phone-login-china.md` — "extend Kratos natively" decision
- `project_chenweb_phone_login_deploy` (memory) — deployment state + all root causes
