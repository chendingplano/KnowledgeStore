# LLM Account Balance Monitoring

Tracks the official provider-reported balance of each LLM account (currently
DeepSeek), derives spending from it, and renders it as charts on the
Development dashboard.

## Schema: `llm_balance_snapshot`

One row per (account, currency, point in time). Key columns:

| Column           | Meaning                                                                 |
|------------------|--------------------------------------------------------------------------|
| `account_id`     | FK to `llm_account`.                                                     |
| `captured_at`    | When this reading was taken (or the manual entry was made).              |
| `workspace_day`  | Local calendar day the reading belongs to.                               |
| `balance_amount` | The provider-reported balance for `currency_code` at `captured_at`.      |
| `currency_code`  | `USD` or `CNY`. A single balance poll produces one row per currency.     |
| `entry_kind`     | `provider_balance` (default), `deposit`, or `set-total-spending`.        |
| `deposit_amount` | For `deposit`: the amount added. For `set-total-spending`: the total-spending value being set. Unused for `provider_balance`. |
| `total_spending` | Running total spend for this account+currency, as of this row. See below.|
| `capture_source` | `hourly` (background job), `manual` (on-demand run), or `admin_deposit`. |
| `note`           | Free-text note attached to manual entries.                               |

`total_spending` was added and backfilled (from 2026-09-20 12:00 onward) in
`project_migrations/20260921000001_add_total_spending_to_llm_balance_snapshot.sql`.

## Hourly retrieval

`llmreconcile.Runner` (`server/api/llmreconcile/service.go`) polls each active,
reconciliation-enabled DeepSeek account's official balance and writes a
`provider_balance` snapshot per currency.

- **Schedule:** `llmreconcile.StartBackgroundReconciliation`
  (`server/api/llmreconcile/jobs.go`), started from `server/cmd/deepdoc/main.go`,
  runs once at startup and then again at the top of every hour
  (`nextHourlyReconciliationRunAt`).
- **Idempotency:** before fetching, the runner calls
  `Store.ClaimHourlyBalanceCapture(accountID, hour)`, which does an
  `INSERT ... ON CONFLICT (account_id, scheduled_hour) DO NOTHING` into
  `llm_balance_capture_slot`. If that hour was already claimed for this
  account, the fetch is skipped — a manual run in the same hour (see below)
  will not create a duplicate scheduled capture.
- **Manual trigger:** `POST /llm/reconciliation/run`
  (`llmreporthandler.RunReconciliationNow`) runs the same `Runner` on demand
  (used by the dashboard's "Run Reconciliation Now" action and by the daily
  usage report generator). It reuses the same insert path, so it also
  respects the total_spending rule below.
- **Archival:** the raw provider response is written under `ArchiveRoot` and
  referenced by `raw_payload_ref`.
- **Per-account isolation and alarming:** each account is processed by
  `Runner.processAccount`. If one account's claim/fetch/insert fails, the
  run does not abort — the failure is recorded in `RunResult.Failures`,
  `runReconciliationOnce` logs it (`jobs.go`), and
  `Store.RaiseBalanceFetchAlarm` writes an `alarms_errors` row (`severity =
  'error'`, `kind = 'deepseek_balance_fetch_failed'`, `scope_id =
  account_id`, deduplicated via `uq_alarms_errors_scope_id_kind`), surfaced
  on `/semos/admin/alarms` like every other operator alarm. The run then
  continues to the next account. Because `llm_balance_capture_slot` is keyed
  per `(account_id, scheduled_hour)`, a failed hour for one account never
  blocks that account's *next* hourly attempt, nor any other account in the
  same run — it only blocks a retry within that same hour (idempotency,
  above).

### `total_spending` on insert

`Store.InsertBalanceSnapshot` (`server/api/llmreconcile/store.go`) computes
`total_spending` in the same `INSERT` statement, per `(account_id,
currency_code)`:

```
total_spending = previous total_spending
                + max(0, previous provider_balance − this balance_amount)
```

- "Previous provider_balance" only ever looks at prior `entry_kind =
  'provider_balance'` rows — a `deposit` row is never used as the reference
  point, so a deposit's balance bump is never misread as negative spending.
- The `max(0, …)` clamp means a balance *increase* (deposit, currency
  fluctuation, provider-side correction) contributes zero to spending rather
  than reducing the running total.
- If there is no prior `provider_balance` row for that account+currency, the
  first row's spending is 0 (nothing to compare against).

## Manual entries: deposits and total-spending resets

Two admin-only, manually-triggered entry kinds exist
(`server/api/llmadminhandler`), both going through the same
`Store.AddDeposit`:

- `POST /llm/balances/deposits` → `entry_kind = 'deposit'`. Records that the
  admin topped up the account; `balance_amount` is the account's balance
  after the deposit, `deposit_amount` is the amount added.
  `total_spending` carries forward unchanged (a deposit is not spend), and —
  per the rule above — this row is invisible to the next `provider_balance`
  row's spending calculation.
- `POST /llm/balances/total-spending` → `entry_kind = 'set-total-spending'`.
  Hard-resets `total_spending` to `deposit_amount` (the value the admin
  supplies). Every later row keeps accumulating on top of that reset value.

`GET /llm/balances/manual-records` (`ListManualRecords`) lists both kinds for
the admin UI's audit view.

## Charts

The Development dashboard's "Official Account Balance and Spending" chart
(`web/src/lib/components/home3/llm-activities-view.svelte`) calls
`GET /llm/balances/hourly` (`llmreporthandler.ListHourlyBalanceReports`,
`server/api/llmreporthandler/store.go`) with a `frequency` of `hourly`,
`daily`, or `monthly`.

- The frontend derives `frequency` from the selected time range: `Today` /
  `Yesterday` → `hourly`; every other range (7/30 days, this/last month,
  custom) → `daily` (`llm-activities-view.svelte`, `balanceFrequency`).
- The query buckets snapshots with `date_trunc(<hour|day|month>, captured_at)`
  and, per bucket:
  - `balance_usd` / `balance_cny`: the last `provider_balance` reading in
    that bucket (deposit/set-total-spending rows are excluded here so a
    manual entry's placeholder balance never corrupts the balance line).
  - `total_spending_cny` / `total_spending_usd`: the last `total_spending`
    value in that bucket, from *any* entry kind (so a mid-bucket
    `set-total-spending` reset is reflected).
  - `spending_cny`: `total_spending_cny(this bucket) − total_spending_cny(previous bucket)`,
    clamped at 0.
- **Hourly and daily spending use the identical query** — only the
  `date_trunc` unit changes. There is no separate daily rollup logic;
  daily/monthly spending is just the same total_spending delta computed at a
  coarser bucket.

Other balance endpoints (`GET /llm/balances/current`,
`GET /llm/balances/history`) read raw, unbucketed snapshot rows and are used
for simpler "latest balance" and "balance over time" views — they do not
compute spending.
