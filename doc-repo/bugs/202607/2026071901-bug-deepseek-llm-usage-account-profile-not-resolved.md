# Bug: LLM usage events for `deepseek-v4-flash-300` logged without account/profile linkage

Date: 2026-07-19\
Status: fixed-unverified\
System: `ChenWeb` LLM usage tracking (DeepSeek entity-relation extraction)\
Component: `shared/go/api/llm` (usage capture), `ChenWeb/server/api/llmusage` (sink), `llm_account` / `llm_account_model_profile` tables

## Summary

Every DeepSeek call through the `deepseek-v4-flash-300` profile logged:

```
WARN (MID-20260708-01) llm usage event account/profile not resolved; event will be logged without account linkage
provider="deepseek" base_url="https://api.deepseek.com" model="deepseek-v4-flash"
profile_name="deepseek-v4-flash-300" prompt_name="prompt-extract-entities-v3.md"
call_loc="MID-CWB-ENTITY-RELATION"
```

Observed call flow: `extract-entity-relation.go` → `structured_output.go` →
`openai_client.go` (`captureUsage`) → `usage_capture.go` (`captureUsageRecord`)
→ `llmusage/sink.go` (`Sink.Capture` → `resolveAccountProfileIDs`).

## Root Cause

**Not a code bug — a data-registration gap between `.models.toml` and the
`llm_account` / `llm_account_model_profile` tables.**

`resolveAccountProfileIDs` (`ChenWeb/server/api/llmusage/sink.go:182`) looks up
the account/profile by joining on
`provider + base_url + api_key_ref + profile_name` (falling back to
`model_name`). It returns `"", "", nil` (no error) when nothing matches, which
is what triggers the WARN in `Sink.Capture`.

Timeline reconstructed from the `miner` DB (`llm_account`,
`llm_account_model_profile`, `llm_usage_event.request_started_at`):

- `llm_account` `f28c78f1…` ("deepseek:api.deepseek.com", created
  2026-06-20) owned the `deepseek-v4-flash-300` profile, with
  `api_key_ref = sk-897ee395…`.
- On 2026-07-05 the DeepSeek key in `.models.toml` was rotated to
  `sk-7091f67b…`. A new `llm_account` **"DeepSeek Chen"** (`1b75ceb2…`,
  15:05) was registered for the new key — but no
  `llm_account_model_profile` row for `deepseek-v4-flash-300` /
  `deepseek-v4-flash` was ever created against it.
- 2.5 hours later a second, apparently accidental duplicate account
  **"deepseek-chen"** (`77566441…`, 17:40) was created with the *same*
  `api_key_ref`, carrying an unrelated profile (`deepseek-flash-chen`).
- Result: the join in `resolveAccountProfileIDs` never matched for
  `profile_name="deepseek-v4-flash-300"` from 2026-07-05 15:43 onward — 237
  `llm_usage_event` rows accumulated with `account_id`/`profile_id = NULL`
  by the time this was investigated (2026-07-19).

Note: `llm_account`/`llm_account_model_profile` are **not** auto-synced from
`.models.toml` — they're maintained manually via `llmadminhandler`
(confirmed: no sync code path exists). Rotating a key or adding a profile in
`.models.toml` only affects the actual API call (the client reads `APIKey`
straight from config); it does **not** register or update the DB rows used
for usage-event attribution. The two only agree if someone remembers to
update both.

This only breaks usage-tracking attribution/reporting — the DeepSeek API
calls themselves still worked throughout, since `OpenAIJSONClient.APIKey`
comes directly from `.models.toml`, not from the DB lookup.

## Fix

No code change. Registered the missing profile under the account that
already holds the currently-active API key, alongside its sibling profile,
per user decision to co-locate it with `deepseek-flash-chen`:

```sql
INSERT INTO llm_account_model_profile (
  account_id, profile_name, model_name, thinking_type, timeout_sec,
  max_inflight, max_requests_per_minute, max_tokens_per_minute, token_reserve_per_call, is_active
) VALUES (
  '77566441-ec9f-41f8-bfb7-0d51ebcc3058', 'deepseek-v4-flash-300', 'deepseek-v4-flash', 'disabled', 300,
  300, 2500, 3000000, 256, true
);
```

Rate-limit columns (`timeout_sec`, `max_inflight`,
`max_requests_per_minute`, `max_tokens_per_minute`,
`token_reserve_per_call`) were copied from the `[deepseek-v4-flash-300]`
section of `.models.toml` (current values), not from the old orphaned row
(`961f1109…`, which had stale `max_requests_per_minute=300` /
`max_tokens_per_minute=500000` — confirming the DB profile config also
drifts from `.models.toml` over time; these columns are informational only,
not enforced at runtime — the client always reads limits from
`.models.toml`).

Left untouched, flagged as a known smell but out of scope:

- The old orphaned row `961f1109…` under `f28c78f1…` (stale key, stale
  rate-limit columns).
- The still-empty duplicate account `1b75ceb2…` ("DeepSeek Chen") — same
  `api_key_ref` as `77566441…` ("deepseek-chen"), zero profiles. Two
  `llm_account` rows for the same provider/base_url/api_key is itself a
  latent source of this class of bug (nothing enforces one account per key,
  and `resolveAccountProfileIDs`'s `LIMIT 1` picks whichever row the
  `profile_name`/`model_name` join happens to match).

## How to diagnose this again

If you see `(MID-20260708-01) llm usage event account/profile not resolved`:

1. Pull the `provider` / `base_url` / `profile_name` / `model` fields from
   the WARN.
2. Check whether a matching account exists for the **current**
   `.models.toml` API key for that profile:
   ```sql
   SELECT id, account_name, api_key_ref FROM llm_account
   WHERE provider = '<provider>' AND base_url = '<base_url>';
   ```
   Compare `api_key_ref` against the live `api_key` in `.models.toml` for
   that profile section.
3. Check whether that account has a profile row matching the WARN's
   `profile_name` (or `model_name` as fallback):
   ```sql
   SELECT p.* FROM llm_account_model_profile p
   JOIN llm_account a ON a.id = p.account_id
   WHERE a.id = '<account_id_from_step_2>';
   ```
4. If the key matches but the profile row is missing (this bug's shape):
   `INSERT` the missing `llm_account_model_profile` row under that account
   (see SQL above; use current `.models.toml` values for the rate-limit
   columns).
5. If the key doesn't match any account: either update the stale account's
   `api_key_ref`, or register a new account via `llmadminhandler`, and only
   then attach the profile.
6. Sanity-check for duplicate accounts (same
   `provider`+`base_url`+`api_key_ref`, different `id`) — they're a sign
   this will keep happening; consider consolidating.
7. Re-run the exact join from `resolveAccountProfileIDs`
   (`ChenWeb/server/api/llmusage/sink.go:195`) with the WARN's values
   substituted in to confirm it now returns one row before considering it
   fixed.

## Verification

- Re-ran the exact `resolveAccountProfileIDs` profile-name query
  (`sink.go:195-202`) with `provider='deepseek'`,
  `base_url='https://api.deepseek.com'`,
  `api_key_ref='sk-7091f67ba56b4365b66e31ed3eab6412'`,
  `profile_name='deepseek-v4-flash-300'` — now returns exactly one row
  (`account_id=77566441…`, `profile_id=a8e7ec9a…`).

Still owed (see `OPEN.md`):

- Not yet confirmed against a live extraction run: the next real
  `MID-CWB-ENTITY-RELATION` call should stop producing the WARN, and its
  `llm_usage_event` row should land with non-null `account_id`/`profile_id`.

## Change Record

Data-only fix (one `INSERT` on the `miner` Postgres database, `staging`
environment). No Go code changed, no commit involved. `KnowledgeStore` had
unrelated pre-existing uncommitted changes (`Diary/diary-202607.typ`, two
`doc-repo/adrs/202607/` files) at the time this doc was added; not touched.

## Documentation Impact

What knowledge changed:
- `llm_account` / `llm_account_model_profile` rows are **not** derived from
  `.models.toml` automatically — they must be kept in sync by hand whenever
  a profile is added or an account's API key is rotated. This was implicit
  before; now written down.

Which docs/specs/tests are affected:
- None found describing the `.models.toml` ↔ `llm_account`/
  `llm_account_model_profile` relationship or the manual-sync requirement.

Which docs were updated:
- This bug record only.

Which docs may still be stale:
- No ADR documents the account/profile registration workflow itself (how
  `llmadminhandler` rows are expected to be created/kept in sync with
  `.models.toml`); this doc's "How to diagnose this again" section is the
  closest thing to that runbook right now. Worth promoting into an ADR if
  this recurs a third time.

What was intentionally left undocumented:
- The two duplicate/orphaned accounts (`1b75ceb2…`, and the stale
  `f28c78f1…` row) were not cleaned up or written up as their own bug —
  flagged above as a known smell only.
