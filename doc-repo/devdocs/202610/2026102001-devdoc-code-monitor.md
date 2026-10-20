# Code Monitor — daily source size history

**Date:** 2026-10-20  \
**Scope:** ChenWeb's development Code Monitor page and its daily source metrics.  \
**Code root:** `ChenWeb/server/api/codemonitor`

## OpenSpec references

The [Code Monitor specification](../../../../ChenWeb/openspec/specs/code-monitor/spec.md) is the current behavior contract. The archived implementation change includes the [proposal](../../../../ChenWeb/openspec/changes/archive/2026-10-20-code-monitor/proposal.md), [design](../../../../ChenWeb/openspec/changes/archive/2026-10-20-code-monitor/design.md), [tasks](../../../../ChenWeb/openspec/changes/archive/2026-10-20-code-monitor/tasks.md), and the [spec snapshot](../../../../ChenWeb/openspec/changes/archive/2026-10-20-code-monitor/specs/code-monitor/spec.md).

## Summary

Code Monitor gives the development workspace a daily history for each configured project. It shows total project source lines and the frontend/backend line changes since the previous recorded snapshot.

## Details

### Configuration

Set project directory names in the `frontend.projects-to-monitor` string list in `ChenWeb/config.local.toml`. The current local configuration monitors `ChenWeb`, `shared`, and `tax`. Each name is resolved from the workspace root, which is the parent of the ChenWeb config directory. Each configured project name is also the group name shown in the page and stored in `project_path`.

### Counting rules

- Within each configured project, paths returned by `git ls-files` throughout the project are considered. Recognized files under `web/src`, `svelte/src`, `frontend/src`, or `client/src` are frontend; other recognized files are backend.
- Recognized extensions: `.js`, `.jsx`, `.ts`, `.tsx`, `.svelte`, `.css`, `.scss`, `.html`, `.vue`, `.json`, `.go`, `.py`, `.rs`, `.java`, `.kt`, `.php`, `.rb`, `.sql`, `.sh`, `.yaml`, `.yml`, and `.toml`.
- The total line count sums physical lines across the entire project. Blank lines count; a final line without a newline counts; an empty file has zero lines. Files with unrecognized extensions are ignored.
- A tracked file deleted from the worktree is skipped. Other read failures fail that project's collection for the date, while collection continues for other projects.

### Scheduling and persistence

The server schedules collection for 2:00 am in `llm.workspace_timezone` (`America/Chicago` by default). If that local time does not exist during the spring daylight-saving transition, collection runs at the first valid time afterward. If `kb.code_monitor` is empty at startup, the server immediately writes a snapshot for the current local date with `collected_at` set to 2:00 am local time. Subsequent collection runs daily at 2:00 am.

`kb.code_monitor` has one row per `(project_path, collection_date)`, with total project lines, frontend and backend line totals, and the collection timestamp. Repeated writes for that key update the snapshot and timestamp. The API derives each component's daily delta from the current snapshot minus the previous recorded snapshot for that project, even when the previous row falls before the requested chart range. The first row has zero component deltas. The redesign migration clears incompatible file-count history and replaces it with component line totals.

### API and page

The authenticated endpoint is `GET /api/v1/code-monitor?range=<range>`. Its response groups rows by `project_path`; each row has `collection_date`, `total_lines`, `total_lines_delta`, `frontend_lines`, `frontend_lines_delta`, `backend_lines`, and `backend_lines_delta`. Deltas compare with the previous snapshot, and are zero when no previous snapshot exists.

The page is **Development → System Admin → System → Code Monitor**. It renders three ECharts bar charts per project on the same row: project total, frontend, and backend. Each chart shows paired bars for the corresponding line total and its delta from the previous snapshot, using separate value axes. A project's first recorded delta is zero. Date ranges are inclusive in the configured workspace timezone:

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
