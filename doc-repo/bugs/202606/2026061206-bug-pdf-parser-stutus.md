# Bug: PDF Parser Status Not Updating During Active Parse

- DocID: `doc-2026061206`
- **Status:** Implemented
- **Date:** 2026-06-12
- **Deciders:** Chen Ding
- **Tags:** pdf parser, mineru, dashboard, progress, status

## Change Logs
- Created by Chen Ding on 2026/06/12
- Implemented by Claude on 2026/06/12

# Context

The Doc Processor dashboard (`/home3`) has an "Active PDF Parsing" section that shows records currently being parsed, with a progress bar and percentage. Four related bugs were found and fixed:

1. **Wrong query for active records** — the frontend queried `operation='parsing', procStatus='running'` but the Python parser writes `operation='parsed', proc_status='active'`. Active records never appeared.
2. **Progress helper looking for wrong operation** — `parseProgressPercent` searched for `operation='parsing'` but the entry uses `operation='parsed'`. Fixed with `findParseEntry` matching `{'parsed', 'parsing', 'parse'}`.
3. **Deployed SQL function missing 'parsing' clause** — `kb.input_status_parse_state` returned `'parsed_failed'` for `proc_status='active'` records because the WHEN clause for active states was absent in the deployed version. Fixed by re-applying the corrected function and adding migration `20260612000002`.
4. **Auto-sync stopping during PDF parsing** — the stop condition only checked active doc_processing pipelines. Fixed by checking `pdfStats.active === 0` too and adding a dedicated `pdfPollInterval` keepalive.
5. **No progress updates during MinerU parse** (this document) — `progress` stayed `"0%"` for the entire parse duration; the dashboard showed a static 0% bar that looked broken.

This document covers bug 5.

## Root Cause

`parser_mineru.py` runs MinerU as a subprocess. The original implementation only called `on_progress(0, 1)` at the very start and `on_progress(total_pages, total_pages)` at the very end, with nothing in between.

MinerU uses `tqdm` for progress bars, which writes with `\r` (carriage return) rather than `\n`. The line-by-line subprocess reader blocks waiting for `\n`, which tqdm only emits when a bar completes at 100%. This means the main thread can be silently blocked for the full parse duration (minutes) with no intermediate progress updates.

On the frontend, `parseProgressPercent` returns `0` (not `null`) for `progress="0%"`, so the template picks the filled-bar branch at 0% width — visually indistinguishable from an empty bar — instead of the existing indeterminate animation.

# Decision

## Implementation

### Modified Files

**`ChenWeb/python/pdf-parser/parser_mineru.py`**

Three changes:

1. **Real page count before parsing** — added `_get_pdf_page_count(pdf_path)` using `fitz` (PyMuPDF, already in the parser venv) to get the actual page count. The initial `on_progress` call now passes the real page count instead of the placeholder `1`.

2. **Heartbeat thread** — a background thread fires every 15 seconds and calls `on_progress(_state["pages_done"], _state["total"])`. The `throttled` wrapper computes `ms_used` from the wall clock, so `ms_used` advances in the DB even during silent periods. A non-blocking `threading.Lock` guards the call to prevent concurrent writes on the non-thread-safe psycopg2 connection.

3. **tqdm output parsing** — each subprocess output line is split on `\r` (to handle tqdm's carriage-return updates). Segments matching `X/Y` (e.g. `"Processing pages: 60%|██| 3/5 [00:06<00:04]"`) update `_state["pages_done"]` and `_state["total"]` so the heartbeat reports actual page progress when tqdm bars complete.

```python
# Module-level
_PAGE_PROGRESS_RE = re.compile(r'\b(\d+)/(\d+)\b')

def _get_pdf_page_count(pdf_path: str) -> int:
    try:
        import fitz
        with fitz.open(pdf_path) as doc:
            return len(doc)
    except Exception as exc:
        log.debug("_get_pdf_page_count fitz failed: %s", exc)
    return 0
```

The heartbeat runs for the lifetime of the subprocess and is stopped (via `threading.Event`) in the `finally` block before `proc.wait()`.

**`ChenWeb/web/src/lib/components/home3/doc-processor-dashboard-view.svelte`**

Two changes in the progress helper functions:

1. **`parseProgressPercent`** — returns `null` (instead of `0`) when `progress="0%"` and `proc_status="active"`. This triggers the existing indeterminate stripe animation instead of rendering a 0%-wide invisible bar.

2. **`parsingProgressText`** — returns a formatted elapsed time string (e.g. `"45s"`, `"2m 30s"`) derived from `ms_used` (the server-side elapsed milliseconds updated by the heartbeat) when `progress="0%"` and active. Returns `""` when `ms_used` is not yet available, causing the template to fall through to `"parsing…"`.

```typescript
// Before: static "0%" text and invisible bar
// After: animated stripe + "parsing…" → "45s" → "2m 30s" as ms_used advances
```

### New Files

**`ChenWeb/project_migrations/20260612000002_fix_input_status_parse_state_parsing_case.sql`** — fixes the deployed `kb.input_status_parse_state` SQL function to include the missing WHEN clause for `proc_status IN ('active', 'running', 'parsing', 'in_progress')` → `'parsing'`. Also backfills any stale `parse_state` values.

### Key Design Decisions

**Why a heartbeat thread instead of parsing tqdm output for progress?**

tqdm emits `\n` only when a bar reaches 100%, not on every tick. By the time we see a tqdm line in the subprocess reader, the phase is already done. The heartbeat is the only way to push `ms_used` updates during the long silent period between tqdm bar completions.

**Why show indeterminate instead of 0%?**

`0%` with no visible movement looks like a broken/hung state to the user. An animated indeterminate bar honestly communicates "parsing is in progress, progress unknown." Elapsed time from `ms_used` (updated every 15 s) gives concrete evidence that work is happening.

**Why non-blocking lock?**

psycopg2 connections are not thread-safe. The main thread calls `on_progress` only before the heartbeat starts (initial update) and after the heartbeat is joined (final 100% update). So in practice there is no contention. The lock is a safety net against future code changes that might add `on_progress` calls in the output loop.

### Environment Variables

None added.

## Operational Behavior

- At parse start: DB entry has real page count (from fitz), `ms_used=0`, `progress="0%"`. Dashboard shows animated stripe + "parsing…".
- Every 15 s: heartbeat fires, `ms_used` advances. Dashboard shows elapsed time ("45s", "2m 30s", ...).
- If tqdm output with `X/Y` page count is captured: `pages_done` and `total` update, heartbeat fires with real percentage.
- At parse end: `record_parsed_success` writes `progress="100%"`, `proc_status="success"`. Record moves from active to success list.

## Consequences

### Positive

- Dashboard always shows an animated progress indicator while parsing is active.
- Elapsed time display (`ms_used`) confirms the parser is alive, not hung.
- Real page count (`num_pages`) is accurate from the start instead of showing `1`.
- If MinerU emits tqdm lines with page counts, actual percentage progress is shown.

### Trade-offs

- One extra `fitz.open()` call per record before parsing starts. Negligible overhead.
- Heartbeat adds a daemon thread per concurrent parse. Joins cleanly on parse completion.
- `ms_used` updates every 15 s, not every second. Elapsed time display has 15 s granularity during early phases when tqdm output is sparse.

## Verification

1. Submit a multi-page PDF for parsing.
2. On the dashboard, the "Active PDF Parsing" row should show an animated moving stripe immediately.
3. After ~15 s, the label should change from "parsing…" to an elapsed time like "15s".
4. After parse completes, the record should move to the success count and the active list should be empty.
5. Check the DB: `SELECT status FROM kb.inputs WHERE id = <id>` — the `parsed` entry should have `ms_used > 0` before `proc_status` transitions to `success`.

## Documentation Impact

- `KnowledgeStore/Capsules/coding-capsules/pdf-parser/+pdf-parser.md` — Section on progress reporting should note that the `on_progress` callback must be called during parsing to keep `ms_used` and `progress` fields alive. Backends that run long subprocesses (like MinerU) should implement a heartbeat mechanism.

# References
[1] `ChenWeb/python/pdf-parser/parser_mineru.py`

[2] `ChenWeb/python/pdf-parser/pdf_parser.py`

[3] `ChenWeb/web/src/lib/components/home3/doc-processor-dashboard-view.svelte`

[4] `ChenWeb/project_migrations/20260612000002_fix_input_status_parse_state_parsing_case.sql`

[5] `KnowledgeStore/Capsules/coding-capsules/pdf-parser/+pdf-parser.md`
