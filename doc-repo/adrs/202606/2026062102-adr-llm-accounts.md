# LLM Accounts

## Summary

ChenWeb now treats LLM provider credentials as first-class accounts. Accounts are the unit for:

- daily spend reconciliation
- model-profile configuration
- recent usage-event reporting
- future provider-specific jobs

The database is the source of truth after bootstrap import.

The first drill is now implemented end-to-end for:

- account import and account management UI
- per-call LLM usage logging through `shared/go/api/llm`
- archived prompt/response body capture with retention
- `home3 -> Dashboard -> LLM Activities`
- DeepSeek provider-side daily spend reconciliation

## Current UI

`home3 -> System Admin -> LLM Accounts`

Current actions:

- list accounts
- create an account manually
- edit an account manually
- preview `.models.toml`
- import `.models.toml` into accounts and profiles

Current non-actions:

- disable account
- delete account
- manage profiles directly in the UI
- rotate API key
- test connection

These are follow-up items.

## Import Flow

Bootstrap import uses:

- `POST /api/v1/llm/accounts/import-models-toml` for preview
- `POST /api/v1/llm/accounts/import-models-toml/apply` for actual import

The importer:

1. Reads `CHENWEB_MODELS_TOML` if set, otherwise `./.models.toml`.
2. Groups profiles into provider accounts by provider + base URL + API key.
3. Upserts `llm_account` rows.
4. Upserts `llm_account_model_profile` rows.

Important behavior:

- Multiple accounts on the same host get distinct generated names.
- Re-running import is intended to be idempotent for account/profile rows.
- ChenWeb does not watch `.models.toml` for ongoing sync.

## What To Test

1. Open `LLM Accounts`.
2. Click `Preview .models.toml`.
3. Confirm accounts and profiles look correct.
4. Click `Import Into Accounts`.
5. Confirm imported accounts appear in the table.
6. Re-run import once to confirm it does not duplicate obvious rows.

## Telemetry Coverage

Usage-event persistence exists now, and DeepSeek has the first provider-side reconciliation slice.

Covered now:

- `shared/go/api/llm` call paths in the main `deepdoc` server can persist `llm_usage_event` rows and archive input/output bodies.
- `OpenAIJSONClient`-based JSON extraction calls can capture prompt name, model, token counts, request/response bodies, and provider request IDs.
- `OpenAIJSONClient` embedding calls can now capture request/response bodies and provider token usage when the embedding API returns it.
- when the client supplies `provider + base_url + api_key + profile_name`, ChenWeb can resolve the matching account/profile row before inserting the usage event.
- embedding clients that are built from `.models.toml` in doc-processing and kbhandler now also preserve the profile name on the client configuration.
- `deepdoc` now runs LLM usage retention automatically: it deletes `llm_usage_event` rows and whole archived day directories older than `llm.usage_retention_days`.
- `deepdoc` now auto-generates daily usage-based rows in `llm_daily_account_report` for yesterday and today. These rows use `reconciliation_status = "usage_aggregated"` until a provider-side reconciliation pass overwrites the just-finished day.
- `deepdoc` now runs a daily DeepSeek reconciliation pass at `llm.reconciliation_run_hour` in the configured workspace timezone. For reconciliation-enabled DeepSeek accounts, it:
  - calls `GET /user/balance`
  - writes a `llm_balance_snapshot`
  - archives the raw payload under the configured archive root
  - reconciles today's in-progress report row
  - reconciles yesterday's `llm_daily_account_report` row with `reconciliation_status = "provider_verified"`
- the doc-processor worker now installs the same shared LLM usage sink as `deepdoc`, so doc-processor LLM calls can persist `llm_usage_event` rows too
- ChenWeb also exposes a manual trigger at `POST /api/v1/llm/reconciliation/run`, and `home3 -> Dashboard -> LLM Activities` now includes a `Run Reconciliation` button for ad hoc testing.
- `home3 -> Dashboard -> LLM Activities` now shows:
  - today's top-line stats across all models
  - current provider-side balances per account
  - grouped daily model charts with workspace day on the horizontal axis
  - recent usage events including `record_id`, `call_reason`, and `call_loc`

Not fully covered yet:

- provider-side reconciliation for providers other than DeepSeek
- broader account/profile resolution across every existing caller that still constructs `OpenAIJSONClient` without profile/account metadata
- the remaining non-JSON helper paths that do not yet emit shared usage captures

## DeepSeek Reconciliation Notes

DeepSeek reconciliation currently uses first-of-day provider snapshots:

- today's report:
  - opening balance: first snapshot captured on the current workspace day
  - closing balance: latest snapshot captured so far on the current workspace day
  - spend amount: `opening_balance - closing_balance`
- yesterday's report:
  - opening balance: first snapshot captured on yesterday's workspace day
  - closing balance: first snapshot captured on today's workspace day
  - spend amount: `opening_balance - closing_balance`

Important behavior:

- a later manual reconciliation run on the same day must not rewrite yesterday's closing balance to a later same-day balance snapshot
- usage aggregation must not overwrite a `provider_verified` report row and reset `spend_amount` back to zero
- provider-side spend is authoritative only for providers that currently support reconciliation
- usage-only providers may still show request and token activity while spend remains non-authoritative

This means the DeepSeek slice is useful for daily spend monitoring, but it still does not separate usage spend from same-day account top-ups or credits returned by the provider.

## Table Names

The current LLM activity tables are:

- `llm_account`
- `llm_account_model_profile`
- `llm_usage_event`
- `llm_daily_account_report`
- `llm_balance_snapshot`

For daily reports:

- `opening_balance` is the start-of-day balance for that report row
- `closing_balance` is the provider balance snapshot chosen by the reconciliation policy for that row
- `spend_amount` is `opening_balance - closing_balance`
- `reconciliation_status = "provider_verified"` means the spend came from provider-side balance reconciliation
- `reconciliation_status = "usage_aggregated"` means the row only has locally captured request/token totals and spend should not be treated as authoritative

`account_name` lives in `llm_account`, so report and activity views should usually join that table instead of duplicating the name into every downstream table.

For per-call usage rows in `llm_usage_event`:

- `prompt_name` should never be blank going forward; callers now pass it explicitly and the shared sink falls back to a `missing_prompt_name@...` marker if a caller omits it.
- `record_id` stores the ChenWeb input record when the LLM call belongs to a doc-processing or KB workflow.
- `call_reason` stores the business reason for the call, such as `extract_metrics`, `enrich_scene_blocks`, or `generate_summary`.
- `call_loc` stores a stable source marker such as `MID-CWB-...` so we can trace where the call originated in code.
- embedding/vector calls may legitimately show `output_tokens = 0`; returned vectors are output data, but they are not usually billed or reported as completion/output tokens by the provider APIs we capture today.
