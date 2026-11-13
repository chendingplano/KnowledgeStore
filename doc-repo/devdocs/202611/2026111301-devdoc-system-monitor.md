# System Monitor — live service logs

**Date:** 2026-11-13  
**Scope:** ChenWeb development System Admin log monitor.  
**Code root:** `ChenWeb/server/api/systemmonitor`, `ChenWeb/web/src/lib/components/home3/system-monitor-view.svelte`

## Summary

The System Monitor shows recent runtime logs for nine workspace services in separate windows. An administrator can follow output, pause each window, search, set a time range, change its size, and hide or reopen it. Settings and scroll positions are retained while navigating away and back during the browser session.

## Details

The admin-only `GET /api/v1/system-admin/system-monitor` endpoint reads configured local files and returns up to 256 KiB from the end of each current file. The browser polls once per second. A paused window retains its displayed snapshot; resuming loads the latest tail. A window follows the bottom unless the user has scrolled up.

`scripts/system-monitor-env.sh` defines the defaults consumed by the development backend and service launchers. `SYSTEM_MONITOR_LOG_ROOT` defaults to `~/Apps/ChenWebLog/system-monitor`. Go logger directories are `GO_BACKEND_LOG_DIR`, `DOC_PROCESSOR_LOG_DIR`, `DOC_SERVICE_LOG_DIR`, and `PARSER_RESULT_CONVERTER_LOG_DIR`. The monitor reads the newest current `app.log` or `log_*` file in each directory. Other sources use `KRATOS_LOG_FILE`, `NATS_LOG_FILE`, `PDF_PARSER_LOG_FILE`, `CADDY_LOG_FILE`, and `DEEPSEEK_WATCH_LOG`. Export the same overrides to the backend and the corresponding service before starting them. The services must restart to apply new paths. The Go logger uses its own rotation settings; the terminal capture launchers append through `tee`.

## Known limitations

- Polling shows a bounded snapshot, so output exceeding the snapshot size between polls can be skipped. Paused windows catch up to the latest snapshot, not a complete backlog.
- Time filtering recognizes timestamps formatted as `YYYY-MM-DD HH:MM:SS` or RFC 3339. Untimestamped lines are associated with the previous recognized timestamp; other formats are not interpreted.
- Terminal capture files append without automatic rotation. Arrange external rotation with a copy-and-truncate method, since `tee` keeps the file open.
