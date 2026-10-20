# Code Monitor — daily source size history

**Date:** 2026-10-20  \
**Scope:** ChenWeb's development Code Monitor page and its daily source metrics.  \
**Code root:** `ChenWeb/server/api/codemonitor`

## OpenSpec references

The [Code Monitor specification](../../../../ChenWeb/openspec/specs/code-monitor/spec.md) is the current behavior contract. The archived implementation change includes the [proposal](../../../../ChenWeb/openspec/changes/archive/2026-10-20-code-monitor/proposal.md), [design](../../../../ChenWeb/openspec/changes/archive/2026-10-20-code-monitor/design.md), [tasks](../../../../ChenWeb/openspec/changes/archive/2026-10-20-code-monitor/tasks.md), and the [spec snapshot](../../../../ChenWeb/openspec/changes/archive/2026-10-20-code-monitor/specs/code-monitor/spec.md).

## Summary

Code Monitor gives the development workspace a daily history of configured projects. For each project, it shows how many source lines are in the frontend and backend trees, how many files each tree contains, and how those totals changed since the prior snapshot.

## Details

### Configuration

Set project directory names in the `frontend.projects-to-monitor` string list in `ChenWeb/config.local.toml`. The current local configuration monitors `ChenWeb`. Each name is resolved from the workspace root, which is the parent of the ChenWeb config directory. Each configured project name is also the group name shown in the page and stored in `project_path`.

### Counting rules

- Within each configured project, only paths returned by `git ls-files` under `web/src` and `server` are considered. Frontend metrics count recognized files in `web/src`; backend metrics count recognized files in `server`.
- Recognized extensions in either tree: `.js`, `.jsx`, `.ts`, `.tsx`, `.svelte`, `.css`, `.scss`, `.html`, `.vue`, `.json`, `.go`, `.py`, `.rs`, `.java`, `.kt`, `.php`, `.rb`, `.sql`, `.sh`, `.yaml`, `.yml`, and `.toml`. Directory decides the category: files under `web/src` count as frontend; files under `server` count as backend.
- The total line count sums physical lines in both directories. Blank lines count; a final line without a newline counts; an empty file has zero lines. Other extensions and files outside these directories are ignored.
- A tracked file deleted from the worktree is skipped. Other read failures fail that project's collection for the date, while collection continues for other projects.

### Scheduling and persistence

The server schedules collection for 2:00 am in `llm.workspace_timezone` (`America/Chicago` by default). If that local time does not exist during the spring daylight-saving transition, collection runs at the first valid time afterward. If `kb.code_monitor` is empty at startup, the server immediately writes a snapshot for the current local date with `collected_at` set to 2:00 am local time. Subsequent collection runs daily at 2:00 am.

`kb.code_monitor` has one row per `(project_path, collection_date)`, with totals for lines and frontend/backend files plus the collection timestamp. Repeated writes for that key update the snapshot and timestamp. Deltas are computed as the current total minus the previous recorded row for the same project, even when that row falls before the requested chart range; the first row has a zero delta. The initial schema migration is `project_migrations/20261020000001_create_kb_code_monitor.sql`; the follow-up migration renames `package_path` to `project_path`.

### API and page

The authenticated endpoint is `GET /api/v1/code-monitor?range=<range>`. Its response groups rows by `project_path`; each row has `collection_date`, total and delta values for `total_lines`, `frontend_files`, and `backend_files`.

The page is **Development → System Admin → System → Code Monitor**. It renders three ECharts bar charts per project: total lines, frontend file count, and backend file count. Each chart has Total and Delta bars, with Total on the left y-axis and Delta on the right. Date ranges are inclusive in the configured workspace timezone:

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

- Source languages with unlisted extensions are not counted until the classifier is updated.
