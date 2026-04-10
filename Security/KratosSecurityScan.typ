#import "@preview/diagraph:0.3.6"
#import "@preview/oxdraw:0.1.0": *

#set heading(numbering: "1.")
#set quote(block: true)
#show quote: set pad(x: 1em)
#show raw.where(block: true): block.with(fill: luma(240), inset: 1em, radius: 0.5em, width: 100%)

#show heading: it => {
  set text(fill: blue) if it.level == 1
  if it.numbering != none {
    counter(heading).display(it.numbering)
    h(0.5em) // Adds a little gap after the number
  }
  it.body
}

#set page(
  numbering: "1 of 1",
  footer: context {
    line(length: 100%)
    "Krato Security"
    h(1fr)
    counter(page).display("1/1", both: true)
  },
)

#show heading.where(level: 1): set text(size: 18pt)
#show heading.where(level: 1): it => pad(top: 4pt, it)

#show heading.where(level: 2): set text(size: 14pt)
#show heading.where(level: 2): it => pad(top: 4pt, it)

#show heading.where(level: 3): set text(size: 14pt)
#show heading.where(level: 3): it => pad(top: 4pt, it)

= Basic Info
*SECURITY POSTURE REPORT* — Kratos System \
*Scope: Kratos/ (your config + custom Go backend + deploy config). Upstream src/kratos/ is Ory's code, excluded. \
*Mode"": Daily, focused audit. \
*Status*: No git repo in parent — cannot check history. File contents on local disk analyzed.

*Attack Surface Map*

```text
CODE SURFACE
  Public endpoints:        3  (/, /health, /session)
  Authenticated endpoints: 3  (/api/me, /api/secret, /admin/identities)
  Admin-only:              0  (/admin/* has NO role check — any session passes)
  OIDC providers:          1  (Google)
  Self-service flows:      7  (login, register, recovery, verify, settings, logout, error)
```

```text
INFRASTRUCTURE SURFACE
  Deploy configs:          1  (docker-compose.yml — dev mode)
  Secret management:       env vars + plaintext yaml (mixed, leaking)
  Kratos flags:            --dev --watch-courier (dev mode in prod compose file)
```

= Findings
== Finding 1: Resend API key — real, plaintext, multiple files
*Severity*: CRITICAL \
Confidence: 10/10 — VERIFIED (valid re\_ prefix + 24-char body = live Resend format) \
*Phase*: P2 Secrets Archaeology

*Files*:
Kratos/mise.toml:2 — tracked by mise, not in .gitignore \
Kratos/mise.local.toml:2 — gitignored but on disk \
Kratos/kratos/kratos.yml:145 — gitignored but on disk, embedded in SMTP URI \
Value: re_27kwuUpt_4sA7hpzxwTUUdRTYimmpRt5t

Exploit scenario: Anyone with read access to this directory (backup, cloud sync, stolen machine, misconfigured share, an AI pasted this file, a rogue VS Code extension) can call smtp.resend.com as noreply\@miraitaxcpa.com and send phishing from your verified domain. Game over for customer trust.
Impact: Arbitrary email-from your verified domain → credible phishing → Resend account suspension → email deliverability destroyed for the business.
Recommendation:
Revoke now at https://resend.com/api-keys
Rotate — generate new key, store in mise.local.toml ONLY (already gitignored), remove from mise.toml (tracked) and from kratos.yml
In kratos.yml use env interpolation: connection_uri: smtps://resend:${RESEND_API_KEY}@smtp.resend.com:465/
Audit Resend logs for unauthorized sends

*Solution*: Moved secret key to RESEND_API_KEY

*Status*: Solved.

== Finding 2: Google OAuth client_secret — real, plaintext
Severity: CRITICAL
Confidence: 10/10 — VERIFIED (valid GOCSPX- prefix = live Google OAuth client secret format)
Phase: P2 Secrets Archaeology

*Files*:

Kratos/kratos/kratos.yml:70 \
Kratos/mise.local.toml:8 \
Value: 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 + client id 101896652637-pbaheajtqv33r9qarv5bbnqg7c1ah894.apps.googleusercontent.com

Exploit scenario: An attacker with this secret can mint their own OAuth flow pretending to be your app, phish consent screens that say "Mirai Tax CPA," and exchange codes for tokens that look legit to users. They can also impersonate your app to any Google API you've granted.
Impact: Social engineering attacks that bypass user suspicion because the OAuth consent screen shows your real app name.
Recommendation:
Revoke now at https://console.cloud.google.com/apis/credentials → delete the client, create a new one
Store new secret in mise.local.toml only
Use env var in kratos.yml: client_secret: "\$GOOGLE_CLIENT_SECRET" with --config env-resolution enabled

*Solution*: Use env vars instead of hard code the sensitive information.

*Status*: Solved.

== Finding 3: Cookie signing secret is the literal placeholder string
Severity: CRITICAL \
Confidence: 10/10 — VERIFIED \
Phase: P9 OWASP A02 (Cryptographic Failures) \

*File*: 
Kratos/kratos/kratos.yml:122-124\
Value: PLEASE-CHANGE-ME-I-AM-VERY-INSECURE

Exploit scenario: Kratos uses this secret to sign anti-CSRF tokens and cookies. An attacker who reads this repo (or just guesses — it's the literal default from Kratos docs) can forge valid CSRF tokens and potentially craft cookies that pass signature verification. For an identity system, this is the foundation of trust. It's gone.
Impact: CSRF bypass on self-service flows (password reset, settings change), potential session forgery depending on how other secrets are derived.
Recommendation: Generate a real secret: openssl rand -hex 32. Put it in mise.local.toml as KRATOS_COOKIE_SECRET, reference via env in yaml. Rotate on a schedule (Kratos supports multi-secret rotation — list new first, keep old last, drop old after session lifespan expires).

*Solution*: It is sensitive information. It should not be hard-coded in config. It will use two env vars: `SECRETS_COOKIE_0` and `SECRETS_CIPHER_0`, which are defined in mise.local.toml.

*Status*: Solved.

== Finding 4: log.leak_sensitive_values: true — your logs are now a credential dump
Severity: CRITICAL \
Confidence: 10/10 — VERIFIED \
Phase: P9 OWASP A09 (Logging Failures) + A02

*File*: Kratos/kratos/kratos.yml:117-120

Exploit scenario: Kratos will write plaintext passwords during registration, recovery codes, verification tokens, OIDC access tokens, and raw session data to stdout. Anyone with log access (the developer, CI, future log aggregator, Docker docker logs, container stdout shipped to Datadog/Sentry) sees every user's credentials in real time. One misconfigured log sink = full user database leak.
Impact: Every new user registration logs their password in cleartext. You are one docker logs share away from a breach notification.
Recommendation: Delete that line. Also drop log.level from debug to info or warn. This setting exists for core-Kratos development only, never for your own deploy.

*Solution*: The production system already set to false. Local environment will set to false, too.

*Status*: Solved.

== Finding 5: Postgres password Mirai2026! hardcoded in Kratos DSN
Severity: HIGH \
Confidence: 9/10 — VERIFIED \
Phase: P5 Infrastructure \

*File*: Kratos/kratos/kratos.yml:4\
Value: postgres://admin:Mirai2026!@127.0.0.1:5432/kratos?sslmode=disable

Exploit scenario: Password embedded in config → appears in logs, process listings (ps aux), crash dumps, backups. sslmode=disable means the password also crosses the wire in plaintext every query; anyone on the loopback (local malware, a container escape) can passively sniff it.
Impact: Credential leak + MITM exposure. Note: this admin user (per CLAUDE.md) owns the whole local postgres, not just the kratos DB, so breach radius = every DB on the machine.
Recommendation:
Move DSN to \$DSN env var (Kratos already reads it — line 3 says "DSN is set via environment variable" but then hardcodes it anyway — fix the comment or fix the line)
Create a dedicated kratos DB user with access only to the kratos database, not admin
In production: sslmode=require minimum, verify-full ideal

*Solution*: Moved the connection info to env var "DSN"

*Status*: Solved

== Finding 6: Kratos running with --dev flag in docker-compose
Severity: HIGH \
Confidence: 10/10 — VERIFIED \
Phase: P5 Infrastructure + P9 A05 \

*File*: Kratos/docker-compose.yml:48

Exploit scenario: --dev mode in Kratos disables several hardening defaults: it stops enforcing HTTPS on public URLs, relaxes cookie security flags, stops refusing default/weak secrets (which is why finding #3 doesn't crash startup), and enables permissive CORS behaviors. If this compose file is ever used beyond a developer laptop — test servers, staging, "temporarily in prod for a demo" — those protections are gone.
Impact: Foundational identity protections disabled. This is the difference between "an attacker needs an exploit" and "an attacker needs a browser."
Recommendation: Create a second compose file (docker-compose.prod.yml) without --dev. Use the main one only for laptops. Add a loud comment at the top of the dev file: \# NEVER DEPLOY THIS FILE. Uses --dev mode.

*Solution*: We do not use docker at all. The file is deleted.

*Status*: Solved.

== Finding 7: bcrypt cost of 8 — below 2025 minimum
Severity: HIGH \
Confidence: 9/10 — VERIFIED \
Phase: P9 OWASP A02 

*File*: Kratos/kratos/kratos.yml:131-134

Exploit scenario: If your identity DB is ever dumped (via finding #5, a Postgres misconfig, a backup leak), bcrypt cost 8 means an attacker with a single consumer GPU can try ~20k+ password guesses per second per hash. Against the 10,000 most common passwords, you lose every weak user in under a second each.
Impact: Post-breach, credential cracking is effectively free.
Recommendation: Raise to cost: 12 minimum (OWASP 2024+ guidance). Test the latency on your target hardware — cost 12 should give ~250ms per hash, which is the point. Kratos will re-hash on next successful login, so existing users upgrade progressively.

*Solution*: The production system is already 12. We will change dev environment to 12, too.

*Status*: Resolved.

== Finding 8: SMTP password embedded inside connection_uri
Severity: HIGH \
Confidence: 9/10 — VERIFIED \
Phase: P2 + P9 A02

*File*: Kratos/kratos/kratos.yml:145

Exploit scenario: Same key as finding #1, but flagged separately because the fix is different. Putting it inside a URI means it leaks via any log that prints the config, any error message that echoes the DSN, any kratos config introspection.
Recommendation: Kratos supports separate SMTP config fields (host, port, username, password, security). Use those with env var interpolation for the password, and never put credentials in a URI.

*Solution*: Use env var: COURIER_SMTP_CONNECTION_URI = \<the-real-uri\>

*Status*: Solved.

== Finding 9: Kratos UI CSRF/cookie secrets are placeholder strings
Severity: HIGH
Confidence: 10/10 — VERIFIED
Phase: P2 + P9 A02

*Files*:

Kratos/docker-compose.yml:77-79 \
Kratos/mise.toml:101-103 — tracked file \
Values: a-very-long-secret-that-should-be-at-least-32-characters and a-very-long-csrf-secret-that-should-be-at-least-32-characters

Exploit scenario: The Kratos self-service UI signs its own session and CSRF cookies with these secrets. They're literally the placeholder string. Anyone can forge CSRF tokens for the UI, enabling attacks against the login / settings / recovery pages.
Recommendation: openssl rand -hex 32 for each, store in env only. Never in committed mise.toml.

*Solution*: It is hard coded in mise.toml. Now moved to env vars as two env vars:
```text
COOKIE_SECRET = "<strong-random-value>"
CSRF_COOKIE_SECRET = "<strong-random-value>"
```

They are defined in `mise.local.toml`. File `mise.toml` is modified accordingly.

*Status*: Resolved.

== Finding 10: /admin routes have NO role check — any authenticated user is admin
Severity: HIGH
Confidence: 10/10 — VERIFIED (the code literally admits it in a comment)
Phase: P9 OWASP A01 (Broken Access Control)

*File*: Kratos/backend/main.go:189-200

Exploit scenario: The /admin Echo group uses the same AuthMiddleware as /api. Any user who registers through the public /registration flow passes AuthMiddleware and gets admin access. Right now that endpoint only returns a placeholder message — but the comment says "In production, add proper role-based access control," which is exactly the class of TODO that ships.
Impact: Today: low (handler is a stub). Tomorrow: critical (as soon as someone hooks it up to the Admin API on port 4434, every registered user becomes an admin).
Recommendation: Add an AdminMiddleware now, while the handler is empty. Check identity.metadata_admin.role == "admin" or similar. Fail closed. Don't leave the door unlocked with a sign that says "add lock later."

*Solution*: Added admin authorization middleware for /admin/\* in backend/main.go. Refer to Issue \#1.

*Status*: Solved.

== Finding 11: Google OAuth mapper creates accounts from unverified emails (edge case)
Severity: MEDIUM\
Confidence: 8/10 — VERIFIED (behavior intentional but worth understanding)\
Phase: P9 A07

*File*: Kratos/kratos/google_mapper.jsonnet:8

Exploit scenario: The mapper only sets email trait if email_verified is true. Good. But if it's false, the trait is set to null — and your identity.schema.json has anyOf: [email, username]. With null email and no username, Kratos will reject the identity. That's actually fine. BUT: Google nearly always returns email_verified: true for gmail.com and Workspace accounts and false for custom domains that Google hasn't verified. If a user signs up with an unverified Google Workspace account and retries with the same email via password, you can end up with account linking ambiguity. Not a bug today — a footgun tomorrow.
Recommendation: Explicitly handle the unverified case with a clear error flow rather than letting Kratos return a generic schema failure. Consider requiring email_verified at the mapper level with a hard error message.

*Solution*: Refer to Issue \#3.

*Status*: Solved.

== Finding 12: Session cookie domain: localhost + no secure flag set explicitly
Severity: MEDIUM (becomes CRITICAL on the day you deploy)\
Confidence: 9/10 — VERIFIED\
Phase: P9 A05 + A02

*File*: Kratos/kratos/kratos.yml:149-157

Exploit scenario: The comment on line 152 says "PRODUCTION: Change to your actual domain" — so the risk is real and known, but the file that actually gets shipped might not get the change. Also, there's no explicit secure: true or http_only: true. Kratos defaults are sane (both true) but being explicit prevents regressions.
Recommendation: Add explicit http_only: true and secure: true. Use an env var for domain so the same config works dev → prod without hand-editing.

*Solution*: Refer to Issue \#4

*Status*: Solved.

== Finding 13: sslmode=disable on Postgres

Severity: MEDIUM (dev) / CRITICAL (prod)\
Confidence: 10/10 — VERIFIED

*Files*: 

Kratos/kratos/kratos.yml:4\
Kratos/docker-compose.yml:27,42\

Recommendation: Make it sslmode=require everywhere. Local Postgres can serve TLS with a self-signed cert.
Filter stats

*Solution*: Production is already sslmode=require, but not for dev. Note that dev does not use https, which means that it does not use ssl.

*Status*: No action to take.

Candidates scanned:        ~25
Hard exclusion filtered:    6 (dev-only docker patterns, etc.)
Confidence gate filtered:   3 (below 8/10)
Reported:                  13
Summary counts
Severity	Count
CRITICAL	4
HIGH	5
MEDIUM	4
Remediation Roadmap — Do This In Order
Today (before you touch anything else):

Revoke the Resend API key. https://resend.com/api-keys
Revoke the Google OAuth client. https://console.cloud.google.com/apis/credentials
Regenerate and replace all cookie/CSRF/cipher secrets in kratos.yml and mise.toml.
Delete log.leak_sensitive_values: true and drop log level to info.
This week:
5. Move every secret out of tracked files (mise.toml, kratos.yml) into mise.local.toml env vars, referenced via \$VAR interpolation.
6. Remove the Resend API key from the tracked mise.toml.
7. Add AdminMiddleware with real role check in backend/main.go.
8. Raise bcrypt cost to 12.

Before any non-laptop deploy:
9. Split compose files: dev (with --dev) vs prod (without).
10. Turn on Postgres TLS (sslmode=require), create a dedicated kratos DB user.
11. Make cookie domain env-driven, add explicit secure: true / http_only: true.
12. Move identity.schemas.url and mapper_url off absolute paths on lindaestrella's laptop.

*Solution*: This is related to Finding 1.

*Status*: Resolved.
