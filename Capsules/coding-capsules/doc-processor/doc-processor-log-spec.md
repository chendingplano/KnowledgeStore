# Doc Processor Log — Specification

## Purpose

Provide a persistent audit trail of every LLM call and every doc-processor invocation so that:
- Debugging failures is straightforward (see exactly what was sent to which model and what came back).
- Cost and latency can be analysed per processor, per pass, and per activity.
- Summary-oriented processors such as `generate_summaries` and `generate_topics` emit their own processor-level log entries.
- Old entries can be automatically purged to control table size.

---

## Database Table

**Schema:** `kb`  
**Table:** `doc_proc_logs`

| Column | Type | Nullable | Description |
|---|---|---|---|
| `id` | BIGSERIAL PK | NO | Surrogate primary key |
| `call_reason` | TEXT | YES | Human-readable reason this log was emitted |
| `doc_proc_name` | TEXT | NO | Name of the doc processor (e.g. `extract_metrics`) |
| `model_names` | TEXT[] | YES | Model name(s) used in this call / invocation |
| `prompt_name` | TEXT | YES | Name of the prompt template used |
| `entry_type` | TEXT | NO | `'llm_call'` or `'doc_proc_summary'` |
| `pass` | INTEGER | YES | Pass number (1-based); NULL for summaries |
| `llm_call_id` | TEXT | YES | Unique ID for the LLM call; NULL for summaries |
| `activity_name` | TEXT | YES | Activity within the processor (e.g. `extract_metrics_candidates`) |
| `artifact` | JSONB | YES | The extracted/generated artifact |
| `errors` | TEXT | YES | Error message if the call failed |
| `extra_info` | JSONB | YES | Processor-specific supplementary data |
| `ms_used` | BIGINT | YES | Time used by the call / invocation in milliseconds |
| `create_time` | TIMESTAMPTZ | NO | Row insertion time (DEFAULT NOW()) |

### Indexes

| Index | Columns | Purpose |
|---|---|---|
| `idx_kb_doc_proc_logs_doc_proc_name` | `doc_proc_name` | Filter by processor |
| `idx_kb_doc_proc_logs_entry_type` | `entry_type` | Filter by type |
| `idx_kb_doc_proc_logs_create_time` | `create_time` | Retention cleanup, time-range queries |
| `idx_kb_doc_proc_logs_llm_call_id` | `llm_call_id` | Look up by call ID |

---

## Entry Types

### `llm_call`

One row per LLM call per artifact. Populated fields:

- `call_reason`, `doc_proc_name`, `model_names`, `prompt_name`
- `entry_type = 'llm_call'`
- `pass` — which processing pass this call belongs to
- `llm_call_id` — unique ID (e.g. UUID) for deduplication / correlation
- `activity_name` — name of the activity (e.g. `extract_metrics_candidates`)
- `artifact` — the JSON artifact produced (or an error object)
- `errors` — any error message
- `extra_info` — activity-specific payload
- `ms_used`

### `doc_proc_summary`

One row per doc-processor invocation. Populated fields:

- `doc_proc_name`, `model_names` (all models used), `prompt_name` (all prompts used)
- `entry_type = 'doc_proc_summary'`
- Must be emitted for every doc-processor invocation, including `generate_summaries` and `generate_topics`
- `errors` — aggregated errors
- `extra_info` — processor-specific summary JSON (examples below)
- `ms_used`
- `pass`, `llm_call_id`, `activity_name`, `artifact` — **NULL** for summaries

#### Example `extra_info` for `extract_metrics`:

```json
{
  "total_metrics": 45,
  "fallback_count": 3,
  "failed_llm_calls": 1
}
```

#### Example `extra_info` for `generate_summaries`:

```json
{
  "total_chunks": 12,
  "summaries_generated": 12
}
```

---

## Go API

### `DocProcLogger`

```go
type DocProcLogger struct {
    DB *sql.DB
}

func (l DocProcLogger) LogLLMCall(ctx context.Context, rec DocProcLogRecord) error
func (l DocProcLogger) LogSummary(ctx context.Context, rec DocProcLogRecord) error
```

`LogLLMCall` sets `entry_type = 'llm_call'` and inserts the record.  
`LogSummary` sets `entry_type = 'doc_proc_summary'` and inserts the record.

### `DocProcLogRecord`

```go
type DocProcLogRecord struct {
    CallReason    string
    DocProcName   string
    ModelNames    []string
    PromptName    string
    EntryType     string    // set automatically by LogLLMCall / LogSummary
    Pass          *int
    LLMCallID     *string
    ActivityName  *string
    ArtifactJSON  *string   // pre-serialised JSON
    Errors        *string
    ExtraInfoJSON *string   // pre-serialised JSON
    MSUsed        *int64
}
```

### `SQLStore` Methods

```go
func (s SQLStore) InsertDocProcLog(ctx context.Context, rec DocProcLogRecord) error
func (s SQLStore) ListDocProcLogs(ctx context.Context, f DocProcLogFilter) ([]DocProcLogRow, int64, error)
func (s SQLStore) DeleteOldDocProcLogs(ctx context.Context, retentionDays int) (int64, error)
```

### `DocProcLogFilter`

```go
type DocProcLogFilter struct {
    EntryType   string
    DocProcName string
    LLMCallID   string
    Page        int
    PageSize    int
    OrderBy     string // one of the allowed list fields; defaults to create_time
    OrderDir    string // asc or desc; defaults to desc
}
```

`OrderBy` must be validated against an allowlist of sortable fields before building SQL. Supported values:
`entry_type`, `doc_proc_name`, `activity_name`, `model_names`, `pass`, `ms_used`, `create_time`, `errors`.

---

## HTTP API

All endpoints are under the authenticated `/api/v1` group.

### `GET /api/v1/kb/doc-proc-logs`

List log entries with optional filtering and pagination.

**Query parameters:**

| Param | Type | Default | Description |
|---|---|---|---|
| `entry_type` | string | (all) | `llm_call` or `doc_proc_summary` |
| `doc_proc_name` | string | (all) | Exact processor name |
| `llm_call_id` | string | (all) | Exact LLM call ID |
| `page` | int | 1 | Page number (1-based) |
| `page_size` | int | 50 | Rows per page (max 500) |
| `order_by` | string | `create_time` | Field to sort by. Allowed: `entry_type`, `doc_proc_name`, `activity_name`, `model_names`, `pass`, `ms_used`, `create_time`, `errors` |
| `order_dir` | string | `desc` | Sort direction: `asc` or `desc` |

**Response** `200 OK`:

```json
{
  "status": true,
  "results": [ { ...DocProcLogRow... } ],
  "page": 1,
  "page_size": 50,
  "total": 1234
}
```
Each row includes `ms_used`, which is persisted directly by the logger.

### `DELETE /api/v1/kb/doc-proc-logs/old`

Purge log entries older than N days.

**Query parameters:**

| Param | Type | Required | Description |
|---|---|---|---|
| `days` | int | YES | Retain this many days; older rows are deleted |

**Response** `200 OK`:

```json
{
  "status": true,
  "deleted": 203,
  "message": "deleted 203 log entries older than 30 days"
}
```

---

## Frontend

**Location:** `ChenWeb/web/src/lib/components/home3/doc-proc-logs-view.svelte`

**Menu path:** SYSTEM ADMIN → Doc Processor Logs  
**Menu child ID:** `sysadmin-doc-proc-logs`

### Features

1. **Log table** — paginated table sorted by create_time DESC by default. Columns: Type, Processor, Activity, Model(s), Pass, Duration, Create Time, Errors, Actions.
2. **Order by controls** — each sortable table field has an order control in its header. Clicking a field toggles asc/desc and reloads the list using `order_by` and `order_dir`; the active sorted field and direction are visually indicated.
3. **Details action** — each record has a Details button in the Actions column. Clicking Details shows the selected record in a details panel/modal with call_reason, llm_call_id, prompt, extra_info (pretty-printed JSON), artifact (pretty-printed JSON), and full error text.
4. **Filters** — entry_type (dropdown) and doc_proc_name (text input). Applied on Search button click.
5. **Pagination** — Prev / Next buttons; current page and total shown.
6. **Retention panel** — numeric input for days; Apply Retention button calls DELETE endpoint.
