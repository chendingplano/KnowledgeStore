# Price Management — admin page for service and LLM price lists

**Date:** 2026-09-28 \
**Scope:** The Price Management page in ChenWeb: what a price definition is, how to
use the page, and the tables and API behind it. \
**Code root:** `ChenWeb/server/api/priceshandler/`, `ChenWeb/web/src/lib/components/home3/prices-view.svelte`

## Summary

Administrators can now keep the system's prices in one place instead of in code or
notes. There are two kinds of prices: **service prices**, which the system charges its
customers, and **LLM prices**, which the system pays AI model providers such as
DeepSeek. Each set of prices is saved under a name, such as `deepseek-pricing`. It holds
a list of price lines, for example "input, cache hit, peak hours: ¥0.04 per million
tokens". The page is under **Development → System Admin → System → Price
Management**. From there you can create, view, edit and delete these price lists.
Only administrators can open it.

## Details

### Concepts

- A **price definition** is identified by `price_def_name`, which is unique across the
  system. It has a `price_type` (`service` or `llm`), an optional description, and
  **one or more** price items.
- A **price item** has these attributes:

| Attribute   | Allowed values                                   | Notes                                             |
|-------------|--------------------------------------------------|---------------------------------------------------|
| `item_name` | any non-empty text                               | unique within its price definition                |
| `item_type` | `input`, `output`                                |                                                   |
| `cache`     | `hit`, `miss`, or empty                          | empty = not applicable; the page shows `-`        |
| `time_span` | `peak`, `off-peak`, or empty                     | empty = not applicable; the page shows `-`        |
| `unit`      | any non-empty text                               | the page suggests `million-tokens`                |
| `currency`  | any non-empty text                               | stored upper case; the page suggests `CN`, `US`   |
| `value`     | non-negative decimal matching `^[0-9]+(\.[0-9]+)?$` | exact; no exponents, signs, `NaN` or `Inf`     |

Leading and trailing spaces are trimmed from the name, item names, unit, currency and value.

### Example: DeepSeek pricing

`price_def_name` = `deepseek-pricing`, `price_type` = `llm`:

```text
| item_name               | item_type | cache | time_span | unit            | currency | value |
|-------------------------|-----------|-------|-----------|-----------------|----------|-------|
| input-cache-hit-peak    | input     | hit   | peak      | million-tokens  | CN       | 0.04  |
| input-cache-hit-off     | input     | hit   | off-peak  | million-tokens  | CN       | 0.02  |
| input-cache-miss-peak   | input     | miss  | peak      | million-tokens  | CN       | 2.00  |
| input-cache-miss-off    | input     | miss  | off-peak  | million-tokens  | CN       | 1.00  |
| output-peak             | output    | -     | peak      | million-tokens  | CN       | 8.00  |
| output-off              | output    | -     | off-peak  | million-tokens  | CN       | 4.00  |
```

### The page

- **Upper panel:** creates or edits one price definition: name, type, description,
  and an editable table of items (add and remove rows). Edits are checked in the
  browser before saving, and the server checks them again.
- **Lower panel:** lists every definition, filtered by **All / Service Prices / LLM
  Prices**. Click a name to expand its items. Each row has **Edit** and **Delete**;
  Delete asks for confirmation and removes the definition's items too.
- Menu id `sysadmin-system-prices` in `web/src/lib/components/home3/nav-rail.svelte`,
  rendered from `content-panel.svelte`. The API client is `prices-client.ts`.

### Storage

The project migration `ChenWeb/project_migrations/20260928000004_create_prices.sql`
creates the tables. The server's startup migrator applies it.

- `public.price_defs`: `id`, `price_def_name` (UNIQUE), `price_type` (CHECK `service|llm`),
  `description`, `created_at`, `updated_at`.
- `public.price_items`: `id`, `price_def_id` (FK → `price_defs.id`, `ON DELETE CASCADE`),
  `item_name`, `item_type`, `cache`, `time_span`, `unit`, `currency`, `value NUMERIC`
  (CHECK `>= 0`), `sort_order`, `created_at`. UNIQUE `(price_def_id, item_name)`, and
  CHECK constraints for the allowed values of `item_type`, `cache` and `time_span`.

`value` travels as a decimal **string** in JSON and is stored as `NUMERIC`, so `0.04`
never becomes `0.0399999…`. The value is returned exactly as it was entered, so `2.00`
comes back as `2.00`.

### API

The routes are admin-only: `401` when not logged in, `403` for users who are not
administrators. They are registered in `ChenWeb/server/api/routes.go`.

| Method & path               | Behaviour                                                               |
|-----------------------------|-------------------------------------------------------------------------|
| `GET /api/v1/prices`        | `{status, results: PriceDef[]}`, sorted by type, then name; items in their saved order |
| `POST /api/v1/prices`       | create; body = definition + `items`; returns `201 {status, id}`         |
| `PUT /api/v1/prices/:id`    | replace the definition **and its complete item list**                   |
| `DELETE /api/v1/prices/:id` | delete the definition and its items                                     |

The definition and all its items are saved in one transaction. Errors: `400`
validation (message names the bad item), `404` unknown id, `409` duplicate
`price_def_name`. Each operation is logged under the log locations `CWB_PRC_001`–`004`.

Short feature note in the repo: `ChenWeb/docs/prices-admin.md`.

## Known limitations

- **Nothing reads these prices yet.** LLM cost reporting
  (`ChenWeb/server/api/llmreporthandler`) still uses its own hardcoded DeepSeek rates.
  Changing a price here does not change any report or bill.
- `item_type` only allows `input` and `output`, and the only suggested unit is
  `million-tokens`. Both come from this document's original LLM-focused design and
  may not fit service prices. Adding a type requires a change to both the database
  constraint and the validation code.
- There is no price history. An edit overwrites the old values, and there is no
  effective date or version.
- Peak and off-peak hours are not defined here. They are configured separately
  (see `2026092402-devdoc-peak-hours-admin.md`).
