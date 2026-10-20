# Code Monitor — daily source size history

**Date:** 2026-10-20  \
**Scope:** ChenWeb's development Code Monitor page and its daily source metrics.  \
**Code root:** `ChenWeb/server/api/codemonitor`

## Summary

Code Monitor gives the development workspace a daily history of configured parts of the ChenWeb codebase. It shows how many source lines and frontend or backend files each part contains. The daily history is stored in the database, so the charts can show changes across the selected date range.

## Details

### Configuration

Set repository-relative paths in the `frontend.code-packages-to-monitor` string list in `ChenWeb/config.local.toml`. The current local configuration monitors `web/src` and `server`. Paths are resolved from the directory containing the main `ChenWeb/config.toml` file.

### Counting rules

- Only paths returned by `git ls-files` under each configured directory are considered.
- Frontend extensions: `.js`, `.jsx`, `.ts`, `.tsx`, `.svelte`, `.css`, `.scss`, `.html`, `.vue`.
- Backend extensions: `.go`, `.py`, `.rs`, `.java`, `.kt`, `.php`, `.rb`, `.sql`, `.sh`, `.yaml`, `.yml`, `.toml`.
- Other extensions are ignored. The total line count sums physical lines in both recognized categories. Blank lines count; a final line without a newline counts; an empty file has zero lines.
- A file deleted from the worktree after Git lists it is skipped. Other read failures fail that package's collection for the date, while collection continues for other packages.

### Scheduling and persistence

The server schedules collection for 2:00 am in `llm.workspace_timezone` (`America/Chicago` by default). If that local time does not exist during the spring daylight-saving transition, collection runs at the first valid time afterward. The worker waits for the next scheduled time on startup; it does not run a catch-up collection immediately.

`kb.code_monitor` has one row per `(package_path, collection_date)`. Repeated writes for that key update the snapshot and collected timestamp. The Goose migration is `project_migrations/20261020000001_create_kb_code_monitor.sql`.

### API and page

The authenticated endpoint is `GET /api/v1/code-monitor?range=<range>`. Its response groups rows by `package_path`; each row has `collection_date`, `total_lines`, `frontend_files`, and `backend_files`.

The page is **Development → System Admin → System → Code Monitor**. It renders three line-and-bar charts per package. Date ranges are inclusive in the configured workspace timezone:

| Range | Dates |
| --- | --- |
| Today | Current local date |
| Yesterday | Previous local date |
| Last 7 days | Today and the previous 6 dates |
| Last month | 30 local dates ending today |
| Last 6 months | Rolling six calendar months ending today |
| Last 12 months | Rolling twelve calendar months ending today |

For the last two ranges, the start date is clamped to the final day of the target month when that month is shorter than today's day number.

## Known limitations

- A new database or a server started after 2:00 am has no snapshot for the current date until the next scheduled collection.
- The extension classifier is intentionally explicit; a source language with an unlisted extension is not counted until the classifier is updated.
