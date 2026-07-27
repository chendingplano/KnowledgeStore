# Phone Login (China Phase 1) Session Handoff

Date: July 29, 2026

## Scope

Implemented Phase 1 of "Login through Phone" for ChenWeb: Chinese mobile number + SMS verification code login, integrated natively into Kratos (not a bespoke side-channel), across three repos (`Kratos/`, `shared/go/`, `ChenWeb/`). The code path is fully built and live-tested up to the point of actually sending a real SMS — that step is currently blocked on getting compliant SMS-delivery credentials for China (see "Current blocker" below).

Phase 2 (US mobile numbers) is explicitly out of scope for this session.

## Where the work lives

- `ChenWeb/openspec/changes/add-phone-login-china/{proposal,design,tasks}.md` — the authoritative, up-to-date task-by-task record, including every bug found during live testing and its fix. **Read `tasks.md` first** if picking this up cold; it's more current than this handoff will be a week from now.
- `KnowledgeStore/doc-repo/adrs/202607/2026072801-adr-phone-login-china.md` — the architecture ADR (why Kratos-native, why the relay design, all bugs found via live testing with root causes: DR7 `passwordless_enabled`, DR8 E.164 format, DR9 route-path fix).
- `Kratos/CLAUDE.md` — "Add More User Fields" section now documents the actual `phone` trait / courier config, corrected after live testing.

## Current state: what's built and live-tested

- **Kratos**: `phone` trait added to `identity.schema.json` (E.164 pattern `^\+861[3-9][0-9]{9}$`), `courier.channels` SMS relay entry, `selfservice.methods.code.passwordless_enabled: true`, `registration.after.code.hooks: [{hook: session}]`. Live-verified: schema changes hot-reload without a Kratos restart; `kratos.yml` changes need one (the user restarted Kratos twice this session).
- **shared/go**: `shared/go/api/auth/kratos_phone.go` (`HandlePhoneSendCodeKratos`, `HandlePhoneVerifyCodeKratos` — login-then-registration-fallback), `sms_relay.go` (`HandleSMSCourierRelay` — signs and calls Aliyun's `SendSms` directly, no SDK), `rate_limiter.go` (`smsRateLimiter`, phone-keyed).
- **ChenWeb**: `enable_phone_login` config flag (currently **on** in `config.local.toml` for this testing session — flip back to `false` before any real rollout decision), phone-login UI in `login-01.svelte`.
- **Live end-to-end trace completed** (with a syntactically-valid but fake phone number, `13800009999`): `POST /auth/phone/send-code` correctly falls back to registration for an unrecognized number; Kratos's courier correctly reaches the relay at `/auth/internal/sms-courier/send` with the E.164-formatted number; the relay correctly builds and signs an Aliyun `SendSms` request. This confirms the entire pipeline is wired correctly end-to-end **except** the final Aliyun call succeeding.

## Three real bugs found only by live testing (not by reading source)

Reading Kratos's source got the architecture right but missed these — all now fixed, all documented in the ADR (DR7-DR9) and `tasks.md` (4.7-4.10):

1. `selfservice.methods.code.enabled: true` alone does not enable code-based **login** — needs `passwordless_enabled: true` too, or Kratos silently returns a generic "no strategy found" error instead of the expected account-not-found error.
2. Kratos's phone-identifier normalization requires full **E.164** format (`+8613800003333`), not the bare 11-digit number everyone types — `Kratos/src/kratos/x/normalize.go` calls `phonenumbers.Parse(value, "")` with no default region and rejects bare numbers with "invalid country code". Fixed via a `toE164CN()` conversion in `kratos_phone.go`; users still only ever see/type the bare 11-digit form.
3. The relay route had to move from `/internal/sms-courier/send` to `/auth/internal/sms-courier/send` — ChenWeb's global route middleware (`server/api/routes.go`) only exempts `/api`, `/auth`, `/shared_api`, `/ws` from its session-auth gate; Kratos's courier call (no session cookie) was getting rejected with 401 before ever reaching the handler.

Also corrected: the account-not-found message ID is **4000035** (`ErrorValidationNoCodeUser`), not the originally-assumed 4000037 (`ErrorValidationAccountNotFound`) — confirmed via a direct curl trace against Kratos, not by reading source alone.

## Current blocker: no working Aliyun credentials

Bzton's reference credentials (`ThirdParty-2/bzton-be/.../AliyunSms/AliyunSmsEntity.java`) were tried for a real-world test, at the user's request, and Aliyun rejected the send:

```
InvalidAccessKeyId.AccessPolicyDenied - Specified access key denied due to access policy.
```

This confirms the signing implementation is correct (a bad signature would be `SignatureDoesNotMatch`, not this) — the key itself is restricted (likely an IP allowlist tied to bzton's own servers, a scoped RAM permission, or Aliyun auto-quarantining a credential sitting in plaintext in a repo). Not fixable from our side.

Getting a fresh Aliyun account turned out to be impractical for the user: sign-name approval requires **enterprise real-name verification** (a Chinese business entity/documents), which the user doesn't have. This shifted the conversation to alternative US-based SMS providers that can deliver to China — unresolved as of this handoff.

## Open decision: which SMS provider for Phase 1 China delivery

- **Twilio — not currently viable.** Twilio's own guidance: "currently unable to support China message registration," delivery to China is "best-effort" with "limited support only." Got notably worse through 2025.
- **AWS End User Messaging SMS (formerly Pinpoint/SNS) — the more promising option.** Registration is a support-case process that does **not** ask for Chinese business registration — just company name/address/country (can be US)/phone/website, a message template, and use case (there's a specific "One Time Password" category). AWS reviews and sends back a China-specific registration form. Not yet attempted — the follow-up form's exact contents aren't visible until the support case is opened.

Four reference URLs (Twilio ×3, AWS ×1) gathered this session:

- [China: SMS Guidelines | Twilio](https://www.twilio.com/en-us/guidelines/cn/sms)
- [China SMS Registration - Twilio Help Center](https://help.twilio.com/articles/35414613214363)
- [Verify Countries and Regions Deliverability | Twilio](https://www.twilio.com/docs/verify/verify-countries-and-regions-deliverability)
- [China SMS template registration form - AWS End User Messaging SMS](https://docs.aws.amazon.com/sms-voice/latest/userguide/phone-numbers-sms-template-registration.html)

**Next step recommendation**: open an AWS Support case per the last link above, using the "One Time Password" message-type category, and see what the follow-up China-specific registration form actually asks for before deciding whether this path is viable.

## Environment/config state left behind (review before continuing)

- `ChenWeb/.env`: `ALIYUN_SMS_ACCESS_KEY_ID`/`ALIYUN_SMS_ACCESS_KEY_SECRET`/`ALIYUN_SMS_SIGN_NAME`/`ALIYUN_SMS_TEMPLATE_CODE` are currently set to **bzton's confirmed-non-working credentials** (kept for reference/re-testing convenience, not because they work). `SMS_RELAY_SHARED_SECRET` is a real generated value, fine to keep.
- `ChenWeb/config.local.toml`: `enable_phone_login = true` — was flipped on for this testing session. Consider reverting to `false` if the feature shouldn't be visible in the UI until real SMS delivery works.
- `ChenWeb`'s dev backend (`air`/`mise dev`) was manually killed and restarted several times this session via `mise exec -- ./.cache/server.exe serve --dir ./pb_data --dev --http=:8080` (backgrounded, logs to `/tmp/chenweb-manual-restart.log`) — **`air` only watches `ChenWeb/server/`, not the sibling `shared/go` module**, so any further edits to `shared/go/api/auth/*.go` will need the same manual rebuild+restart pattern, not just waiting for hot-reload.
- Kratos itself: restarted twice by the user this session to pick up `kratos.yml` changes; currently running with all the fixes above applied.

## Files that matter

- `Kratos/kratos/identity.schema.json`, `kratos.yml`, `templates/courier/sms/request.config.jsonnet`
- `shared/go/api/auth/kratos_phone.go`, `sms_relay.go`, `rate_limiter.go`, `kratos.go` (added `Phone` to `identityInfo`)
- `shared/go/api/router.go` (route registration)
- `ChenWeb/server/cmd/config/config.go`, `server/api/confighandler/handler.go` (`enable_phone_login`)
- `ChenWeb/web/src/lib/components/login-01.svelte` (phone-login UI)
- `ChenWeb/.env`, `ChenWeb/config.local.toml` (see caveats above)

## Testing completed during the session

```sh
cd shared/go && go build ./... && go test ./... && go vet ./api/auth/...
cd ChenWeb && go work sync && go vet ./... && mise run build-server
cd ChenWeb/web && bun run check   # passes for login-01.svelte; one unrelated pre-existing error elsewhere
```

Live traces (see `tasks.md` 4.7-4.11 for full detail):
- Direct curl against Kratos's public API (`/self-service/login/api`, `/self-service/registration/api`) to isolate and confirm each bug above.
- `POST /auth/phone/send-code` / would-be `/auth/phone/verify` through ChenWeb's actual backend.
- Verified codes land correctly in Kratos's own `courier_messages` table even when Aliyun delivery fails (useful for manual UI testing without real SMS — query `courier_messages` for the `body` column, which contains the plaintext code).

## Known follow-up items

- No working SMS delivery path for China yet — this is the single blocking item for calling Phase 1 "done."
- `tasks.md` 4.5's "tax regression check" was done structurally (login flow still renders correctly after the schema change) but not with a real `tax` account login — worth a real credential test if one becomes available.
- `8.4`/`8.5` (full browser E2E with a real SMS, and the `tax` regression re-check right after a Kratos restart) remain unchecked in `tasks.md`.
- Once a working SMS provider is chosen, if it's not Aliyun, `sms_relay.go`'s `sendAliyunSMS` (and its Aliyun-specific request signing) will need a provider-specific replacement — the rest of the pipeline (Kratos config, `kratos_phone.go`, the frontend) is provider-agnostic and shouldn't need to change.

## Recommended handoff summary

If picking this up next:

1. Decide on the SMS provider for China (AWS End User Messaging SMS support case is the concrete next step; see URLs above).
2. Once real credentials/template exist, swap them into `ChenWeb/.env`'s `ALIYUN_SMS_*` vars (or replace `sendAliyunSMS` entirely if the provider isn't Aliyun) and rebuild `shared/go` + `ChenWeb` (manual restart needed — `air` won't pick up `shared/go` changes).
3. Re-run the live trace: `POST /auth/phone/send-code` with a real Chinese number, confirm a real SMS arrives, complete `POST /auth/phone/verify` with the received code, confirm a session/redirect.
4. Re-check `tasks.md` 4.5/8.4/8.5 with a real end-to-end pass, then decide whether to flip `enable_phone_login` on for real users.
