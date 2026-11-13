---
title: System Monitor
language: en
format: markdown
version: 1.0
status: active
author: Not specified
owner: Not specified
audience: ChenWeb administrators monitoring workspace services
create-time: 2026-11-13T08:56:57-06:00
last-modify-time: 2026-11-13T10:12:42-06:00
keywords: system monitor, runtime logs, live logs, service logs, streaming, pause, time filter, search, troubleshooting
---

# System Monitor

The System Monitor lets administrators watch recent runtime logs from ChenWeb and its supporting services in one place. A **log** is a record of messages a service writes while it runs. Logs can help you see what a service is doing or investigate an error.

Each service has its own window. You can follow new messages, pause one window while the others continue, search the displayed text, narrow it by time, and choose which windows to show.

## Open the monitor

1. Sign in with an administrator or owner account.
2. Open **Development → System Admin → System → System Monitor**.

The monitor has windows for **ChenWeb**, **Doc Processor**, **Kratos**, **NATS**, **Doc Service**, **pdf-parser**, **Caddy**, **parser-result-converter**, and **deepseek-watcher**. A window shows the recent messages available for that service; it does not establish whether the service is healthy or currently running.

## Follow and pause messages

The monitor checks for new log content about once a second. When you are near the bottom of a window, it follows new output automatically. Scroll upward to inspect earlier displayed messages without the window continually moving to the bottom. Scroll back down to follow new output again.

Select **Pause** in a window to freeze its displayed text. The other windows continue updating. Select **Resume** to show the latest available messages again. Pausing the display does not stop the service or its logging.

For example, pause the Doc Processor window when an error appears, read the surrounding messages, then select **Resume** to return to the latest output.

The monitor shows a limited recent portion of each log, not its complete history. Messages can be missed if more output is written than fits in that portion between updates. After a pause, resuming shows the latest portion; it may not include everything written while the window was paused. A notice appears when only the most recent log data is being shown.

## Search a window

Enter text in **Search logs** in the service window. Matching text is highlighted, regardless of capitalization. Use the up and down arrow buttons to move to the previous or next match. Search applies to the text currently displayed in that window, including any active time filter; it does not search the full log history. Clear the search field to remove the highlights.

For example, enter `error` in the ChenWeb window and use the arrows to move between matching messages.

## Filter by time

Select **Filter** in a window and enter a **From** time, a **To** time, or both. The displayed log changes as you edit the fields. Choose **Clear filter** to remove both limits, and use the dialog's **×** to close it. The filter remains in effect when the dialog is closed. You can move the dialog by its title bar and resize it from its lower-right corner.

For example, set **From** to 9:00 and **To** to 9:30 on the same day to focus on messages from that interval. The time fields use your browser's local time.

Time filtering works only for timestamps the monitor recognizes, such as `2026-11-13 09:15:00` or an ISO-style timestamp. Lines without a recognized timestamp are treated as part of the preceding recognized entry. Lines before the first recognized timestamp in the displayed portion are not shown while a time filter is active. Some services use other timestamp formats, so a time filter may omit their messages. Clear the filter to see the available unfiltered text.

## Arrange the windows

- Open **Windows** at the top of the page and select or clear a service's checkbox to show or hide its window. Click outside the menu to close it.
- Select **×** on a window to hide it. To bring it back, select it again in **Windows**.
- Drag the grip beside a window's name to move it. The windows start in rows and can overlap when moved.
- Drag the grip at a window's lower-right corner to resize it, or change its **Width** and **Height** values. You can also focus either grip and use the arrow keys to move or resize the window.

Your window choices, searches, filters, and other page state remain available when you navigate away through the menu and return during the same browser session. Closing a window hides it; it does not stop the service.

## If a log is unavailable

- **Log file is not available yet:** The configured file could not be found. The service may not have written a log at that location yet. Ask the system administrator to check the service and its log configuration.
- **Unable to read log:** The monitor found a problem reading that service's log. Ask the system administrator to check the file and its permissions.
- **Unable to load logs:** The page could not obtain the monitor data. Check your connection and sign-in, then contact the system administrator if the message persists.
- **No log entries in this time range:** There may be no available text for the selected range, or its timestamps may not be recognized. Clear the time filter to inspect the available text.

## Change Log

| Version | Timestamp | Author | Reason and summary |
| --- | --- | --- | --- |
| 1.0 | 2026-11-13T10:12:42-06:00 | Not specified | Document menu dismissal and moving and resizing windows. |
| 1.0 | 2026-11-13T08:56:57-06:00 | Not specified | Initial manual for the System Monitor and its log windows. |
