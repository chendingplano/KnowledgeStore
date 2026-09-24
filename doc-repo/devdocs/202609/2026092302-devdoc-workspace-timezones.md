# ChenWeb Workspace Timezones

**Date:** 2026-09-23
**Scope:** LLM usage capture, reconciliation, filters, and Spend Reports in ChenWeb.

## Configuration

ChenWeb reads the base `config.toml`, then merges the optional sibling
`config.local.toml`. Values in the local file override values in the base file.
The `[llm]` section belongs in `config.local.toml` because the correct timezone and
archive paths depend on the machine.

```toml
[llm]
workspace_timezone = "America/Chicago"
```

The China deployment uses Beijing time:

```toml
[llm]
workspace_timezone = "Asia/Shanghai"
```

`config.local.toml` is gitignored and is not copied by `mise run build-server-linux` or
`deploy-server-china.sh`. This is intentional: deploying the Mac's local configuration
could overwrite China-specific paths, credentials, or timezone settings.

## What the timezone controls

The workspace timezone is the business/reporting timezone. It controls:

- the `workspace_day` stored with each `llm_usage_event`;
- the date boundary used by Today and Yesterday filters;
- daily reconciliation and daily report generation;
- hourly Spend Reports bucket labels;
- the scheduled reconciliation run hour.

The database column `request_started_at` remains a timestamp representing the original
instant. It is not rewritten when the workspace timezone changes. Queries convert that
instant with PostgreSQL `AT TIME ZONE` before hourly grouping.

For example, an event stored as `2026-09-23 20:56:00 UTC` is:

| Workspace timezone | Local bucket | Workspace day |
| --- | --- | --- |
| `America/Chicago` | `2026-09-23 15:00` during daylight time | `2026-09-23` |
| `Asia/Shanghai` | `2026-09-24 04:00` | `2026-09-24` |

The same event can therefore belong to different workspace days on different
deployments. That is expected when the deployments represent different business
locations.

## China-machine procedure

On the China box:

```bash
cd ~/Workspace/ChenWeb
vi config.local.toml
```

Preserve the existing machine-local settings and ensure the file contains:

```toml
[llm]
workspace_timezone = "Asia/Shanghai"
```

Then restart both services:

```bash
systemctl restart doc-processor
systemctl restart chenweb
```

Check the resulting process logs and the Spend Reports page. The page's Today filter,
workspace-day rows, and hourly labels should all follow Beijing time. A browser's own
display timezone and PostgreSQL's session timezone should not determine those labels.

## Troubleshooting

If the chart shows a UTC-looking hour or a date that is one day off:

1. Check that `config.local.toml` is next to the running binary's `config.toml`.
2. Check that `[llm].workspace_timezone` is exactly `Asia/Shanghai` on the China box.
3. Restart both `doc-processor` and `chenweb`; configuration is loaded at startup.
4. Confirm the deployed binary was started with the expected working directory.
5. Compare the event's UTC instant with the expected `Asia/Shanghai` conversion.

Do not infer the workspace timezone from the browser timestamp in the LLM Usage Logs
table. That table may render the timestamp in the browser's local timezone, while Spend
Reports use the configured workspace timezone by design.
