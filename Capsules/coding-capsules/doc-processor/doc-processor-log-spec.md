# 1. Doc Processor Log — Specification

## 1.1 Purpose

Provide a persistent audit trail of every LLM call and every doc-processor invocation so that:
- Debugging failures is straightforward (see exactly what was sent to which model and what came back).
- Cost and latency can be analysed per processor, per pass, and per activity.
- Summary-oriented processors such as `generate_summaries` and `generate_topics` emit their own processor-level log entries.
- Old entries can be automatically purged to control table size.

For doc processor log requirements, refer to [1].

---

## 1.2 Database Table

**Schema:** `kb`  
**Table:** `doc_proc_logs`

| Column | Type | Nullable | Description |
|---|---|---|---|
| `id` | BIGSERIAL PK | NO | Surrogate primary key |
| `call_reason` | TEXT | YES | Human-readable reason this log was emitted |
| `doc_proc_name` | TEXT | NO | Name of the doc processor (e.g. `extract_metrics`) |
| `model_names` | TEXT[] | YES | Model name(s) used in this call / invocation |
| `prompt_name` | TEXT | YES | Name of the prompt template used |
| `record_id` | BIGINT | YES | Input record ID being processed |
| `proc_progress` | TEXT | YES | Human-readable progress such as `66% (2/3)` |
| `entry_type` | TEXT | NO | `'llm_call'`, `'doc_proc_summary'`, `'generate_summary'`, or `'generate_summary_finish'` |
| `pass` | INTEGER | YES | Pass number (1-based); NULL for summaries |
| `llm_call_id` | TEXT | YES | Unique ID for the LLM call; NULL for summaries |
| `activity_name` | TEXT | YES | Activity within the processor (e.g. `extract_metrics_candidates`) |
| `proc_loc` | TEXT | YES | A string of 'filename' + '_' + 'line number' right before the log instrument call |
| `artifact` | JSONB | YES | The extracted/generated artifact |
| `errors` | TEXT | YES | Error message if the call failed |
| `extra_info` | JSONB | YES | Processor-specific supplementary data |
| `ms_used` | BIGINT | YES | Time used by the call / invocation in milliseconds |
| `create_time` | TIMESTAMPTZ | NO | Row insertion time (DEFAULT NOW()) |

### 1.2.1 Indexes

| Index | Columns | Purpose |
|---|---|---|
| `idx_kb_doc_proc_logs_doc_proc_name` | `doc_proc_name` | Filter by processor |
| `idx_kb_doc_proc_logs_record_id` | `record_id` | Filter by input record |
| `idx_kb_doc_proc_logs_entry_type` | `entry_type` | Filter by type |
| `idx_kb_doc_proc_logs_create_time` | `create_time` | Retention cleanup, time-range queries |
| `idx_kb_doc_proc_logs_llm_call_id` | `llm_call_id` | Look up by call ID |

---

## 1.3 Doc Processors

**General Rule**
For doc processors that involve LLM calls:
- Should generate a Summary Record.
- Except the 'Summary Record', any time when inserting a record to 'kb.doc_proc_logs', update the `progress` attribute of the corresponding entry in `kb.inputs.status.status` with the current progress.

### 1.3.1 Generate Summaries

One row per summary. Populated fields:

- `call_reason` = 'generate summary'
- `doc_proc_name` = 'generate_summary'
- `model_names`
- `prompt_name`
- `record_id`: the ID of the record the doc processor is processing
- `proc_progress`: progress immediately after this summary finishes, e.g. `"66% (2/3)"`
- `entry_type = 'generate_summary'`
- `llm_call_id`: unique ID (e.g. UUID) for deduplication / correlation
- `activity_name` = 'generate_summary'
- `proc_loc`
- `pass`: NULL
- `artifact`: NULL 
- `errors`: any error message
- `extra_info`: activity-specific payload
- `ms_used`

**`extra_info`** Shape
```json
{
  "level": 0,
  "seqno": 3,
  "lines": ["20-50"]
}
```

When the doc processor finishes, generate one record:
- `call_reason` = 'generate summary'
- `doc_proc_name` = 'generate_summary'
- `model_names`
- `prompt_name`
- `record_id`: the ID of the record the doc processor is processing
- `proc_progress`: `"100% (N/N)"`
- `entry_type = 'generate_summary_finish'`
- `llm_call_id`: NULL
- `activity_name` = 'generate_summary'
- `proc_loc`
- `pass`: NULL
- `artifact`: NULL
- `errors`: any error message
- `extra_info`: activity-specific payload
- `ms_used`

**`extra_info`** Shape
```json
{
  "num_summaries": 12,
  "total_lines": 231,
  "total_time_ms": 234567
}
```

### 1.3.1.1 Generate Summaries Progress Algorithm

`generate_summaries` progress is persisted to the corresponding `kb.inputs.status` JSON entry after each successfully completed summary generation call.

- Status entry: `operation = 'generate_summaries'`
- Field name in `kb.inputs.status`: `progress`
- Running status value: `proc_status = 'running'`
- Final success value: `proc_status = 'success'`
- Failure value: `proc_status = 'failed'`

**Denominator**

The total planned summary count is the total number of summary nodes that will be generated across the whole summary tree:

1. Start with the number of leaf summaries, which equals the chunk count.
2. For each higher level, add the number of parent summaries created by grouping the previous level using `SUMMARY_GROUP_SIZE`.
3. Stop when the current level has only one summary node.

In formula form:

```text
total_planned_summaries =
level0_count +
ceil(level0_count / group_size) +
ceil(level1_count / group_size) + ...
until the level count becomes 1
```

**Numerator**

- Increment `completed_summaries` by 1 immediately after one summary finishes successfully.
- Failed summary calls do not increment the numerator.

**Percentage**

```text
percent = floor(completed_summaries * 100 / total_planned_summaries)
progress = "<percent>% (<completed_summaries>/<total_planned_summaries>)"
```

Examples:

- 1 of 3 summaries finished -> `33% (1/3)`
- 2 of 3 summaries finished -> `66% (2/3)`
- 3 of 3 summaries finished -> `100% (3/3)`

---

### 1.3.2 Extract Topics

One row per chunk. Populated fields:

- `call_reason` = 'extract topics'
- `doc_proc_name` = 'extract_topics'
- `model_names`: both the primary and fallback model names
- `proc_progress`: "20%",
- `prompt_name`: the prompt name
- `record_id`: the ID of the record the doc processor is processing
- `entry_type = 'extract_topics'`
- `llm_call_id`: unique ID (e.g. UUID) for deduplication / correlation
- `activity_name` = 'generate_topic'
- `proc_loc`
- `pass`: NULL
- `artifact`: the topics extracted (in JSON)
- `errors`: any error message
- `extra_info`: activity-specific payload
- `ms_used`

**Calculate Progress**
```text
  progress = the current chunk ID (starting from 1) / total chunks * 100
```

**`extra_info`** Shape
```json
{
  "chunk": 3,
  "total_chunks": 15,
  "num_topics": 12,
  "topics_so_far": 22,
  "percent": "20%",
  "lines": [20-50]
}
```

When the doc processor finishes, generate one record:
- `call_reason` = 'extract topics'
- `doc_proc_name` = 'extract_topics',
- `model_names`: NULL
- `prompt_name`: NULL
- `proc_progress`: "100%",
- `record_id`: the ID of the record the doc processor is processing
- `entry_type = 'extract_topics_finish'`
- `llm_call_id`: NULL
- `activity_name` = 'extract_topics'
- `proc_loc`
- `pass`: NULL
- `artifact`: NULL
- `errors`: any error message
- `extra_info`: activity-specific payload
- `ms_used`

**`extra_info`** Shape
```json
{
  "total_topics": 22,
  "total_chunks": 4,
  "total_lines": 231,
  "total_time_ms": 234567
}
```


### 1.3.2.1 Extract Topics Progress Algorithm

`extract_topics` progress is persisted to the corresponding `kb.inputs.status` JSON entry after each successfully completed topic extraction call.

- Status entry: `operation = 'generate_topics'`
- Field name in `kb.inputs.status`: `progress`
- Running status value: `proc_status = 'running'`
- Final success value: `proc_status = 'success'`
- Failure value: `proc_status = 'failed'`
- User-stop value: `proc_status = 'stopped'` — written at the next LLM call boundary after a stop request is detected; `num_topics` reflects topics extracted so far

**Denominator**

Total chunks to process.

**Numerator**

- Increment `completed_chunks` by 1 immediately after one chunk's topics are successfully extracted.
- Failed extraction calls do not increment the numerator.

**Percentage**

```text
percent = floor(completed_chunks * 100 / total_chunks)
progress = "<percent>% (<completed_chunks>/<total_chunks>)"
```

Examples:

- 1 of 4 chunks finished -> `25% (1/4)`
- 3 of 4 chunks finished -> `75% (3/4)`
- 4 of 4 chunks finished -> `100% (4/4)`

---

### 1.3.3 Extract Metrics

#### 1.3.3.1 Pass 1

One row per block. Populated fields:

- `call_reason` = 'extract metrics'
- `doc_proc_name` = 'extract_metrics'
- `model_names`: both the primary and fallback model names for Pass 1
- `prompt_name`: the prompt name
- `proc_progress`: "20%",
- `record_id`: the ID of the record the doc processor is processing
- `entry_type = 'extract_metrics'`
- `llm_call_id`: unique ID (e.g. UUID) for deduplication / correlation
- `activity_name` = 'extract_metrics_candidates'
- `proc_loc`
- `pass`: NULL
- `artifact`: the metrics extracted (in JSON)
- `errors`: any error message
- `extra_info`: activity-specific payload
- `ms_used`

**Calculate Progress**
```text
  progress = the current block ID (starting from 1) / total blocks * 100
```

**`extra_info`** Shape
```json
{
  "block": 3,
  "total_blocks": 15,
  "num_metrics": 12,
  "metrics_so_far": 22,
  "percent": "20%",
}
```

#### 1.3.3.2 Pass 2

One row per block. Populated fields:

- `call_reason` = 'extract metrics'
- `doc_proc_name` = 'extract_metrics'
- `model_names`: both the primary and fallback model names for Pass 1
- `prompt_name`: the prompt name
- `proc_progress`: "20%",
- `record_id`: the ID of the record the doc processor is processing
- `entry_type = 'enrich_metrics'`
- `llm_call_id`: unique ID (e.g. UUID) for deduplication / correlation
- `activity_name` = 'extract_metrics_candidates'
- `proc_loc`
- `pass`: NULL
- `artifact`: the metrics extracted (in JSON)
- `errors`: any error message
- `extra_info`: activity-specific payload
- `ms_used`

**Calculate Progress**
```text
  progress = the current block ID (starting from 1) / total blocks * 100
```

**`extra_info`** Shape
```json
{
  "block": 3,
  "total_blocks": 15,
  "num_metrics": 12,
  "metrics_so_far": 22,
  "percent": "20%",
}
```

When the doc processor finishes, generate one record:
- `call_reason` = 'extract topics'
- `doc_proc_name` = 'generate_topics',
- `model_names`: NULL
- `prompt_name`: NULL
- `proc_progress`: "100%",
- `record_id`: the ID of the record the doc processor is processing
- `entry_type = 'extract_topics_finish'`
- `llm_call_id`: NULL
- `activity_name` = 'extract_topics'
- `proc_loc`
- `pass`: NULL
- `artifact`: NULL
- `errors`: any error message
- `extra_info`: activity-specific payload
- `ms_used`

**`extra_info`** Shape
```json
{
  "total_topics": 22,
  "total_chunks": 4,
  "total_lines": 231,
  "total_time_ms": 234567
}
```


### 1.3.3.3 Extract Metrics Progress Algorithm

`extract_metrics` progress is persisted to the corresponding `kb.inputs.status` JSON entry after each successfully completed extraction call across both passes.

- Status entry: `operation = 'extract_metrics'`
- Field name in `kb.inputs.status`: `progress`
- Running status value: `proc_status = 'running'`
- Final success value: `proc_status = 'success'`
- Failure value: `proc_status = 'failed'`

**Denominator**

Total blocks across both passes (`total_blocks_pass1 + total_blocks_pass2`). Both totals are known before processing begins.

**Numerator**

- Increment `completed_blocks` by 1 immediately after each block is successfully processed in either pass.
- Failed calls do not increment the numerator.

**Percentage**

```text
percent = floor(completed_blocks * 100 / total_blocks)
progress = "<percent>% (<completed_blocks>/<total_blocks>)"
```

Examples:

- Pass 1, 2 of 15 blocks done (total 30 blocks) -> `6% (2/30)`
- Pass 1 complete, 15 of 30 blocks done -> `50% (15/30)`
- All done -> `100% (30/30)`

---

### 1.3.4 Extract Semantic Projections 

#### 1.3.4.1 Pass 1

One row per chunk. Populated fields:

- `call_reason` = 'extract semantic projections'
- `doc_proc_name` = 'extract_projections'
- `model_names`
- `prompt_name`
- `proc_progress`: "20%",
- `record_id`: the ID of the record the doc processor is processing
- `entry_type = 'extract_projections'`
- `llm_call_id`: unique ID (e.g. UUID) for deduplication / correlation
- `activity_name` = 'extract_projection`'
- `proc_loc`
- `pass`: 1
- `artifact`: the projections extracted (in JSON)
- `errors`: any error message
- `extra_info`: activity-specific payload
- `ms_used`

The progress consists of two parts:
- Pass 1: 50%
- Pass 2: 50%

**Calculate Pass 1 Progress**
```text
  progress = the current block ID (starting from 1) / total chunks * 100 / 2
```

**Calculate Pass 2 Progress**
```text
  progress = the number of projections enriched so far / total projections * 100 / 2 + 50
```

**`extra_info`** Shape
```json
{
  "chunk": 3,
  "total_chunks": 15,
  "percent": "20% (3/15)",
}
```

#### 1.3.4.2 Pass 2

One row per block. Populated fields:

- `call_reason` = 'enrich semantic projections'
- `doc_proc_name` = 'enrich_projections'
- `model_names`
- `prompt_name`
- `proc_progress`: "20%",
- `record_id`: the ID of the record the doc processor is processing
- `entry_type = 'enrich_projections'`
- `llm_call_id`: unique ID (e.g. UUID) for deduplication / correlation
- `activity_name` = 'enrich_projection'
- `proc_loc`
- `pass`: 2
- `artifact`: the enriched projection (in JSON)
- `errors`: any error message
- `extra_info`: activity-specific payload
- `ms_used`

**`extra_info`** Shape
```json
{
  "chunk": 3,
  "total_chunks": 15,
  "percent": "20%",
}
```

When the doc processor finishes, generate one record:
- `call_reason` = 'extract projections'
- `doc_proc_name` = 'extract_semantic_projections',
- `model_names`
- `prompt_name`
- `proc_progress`: "100%",
- `record_id`: the ID of the record the doc processor is processing
- `entry_type = 'extract_projections'`
- `llm_call_id`: NULL
- `activity_name` = 'extract_projections'
- `proc_loc`
- `pass`: NULL
- `artifact`: NULL
- `errors`: any error message
- `extra_info`: activity-specific payload
- `ms_used`

**`extra_info`** Shape
```json
{
  "total_chunks": 4,
  "total_time_ms": 234567
}
```


### 1.3.4.3 Extract Semantic Projections Progress Algorithm

`extract_projections` progress is persisted to the corresponding `kb.inputs.status` JSON entry after each successfully completed extraction or enrichment call.

- Status entry: `operation = 'extract_projections'`
- Field name in `kb.inputs.status`: `progress`
- Running status value: `proc_status = 'running'`
- Final success value: `proc_status = 'success'`
- Failure value: `proc_status = 'failed'`

**Pass 1 Progress** (contributes the first 50%)

```text
percent = floor(completed_chunks * 100 / total_chunks / 2)
progress = "<percent>% (pass 1: <completed_chunks>/<total_chunks>)"
```

**Pass 2 Progress** (contributes the second 50%)

```text
percent = floor(completed_projections * 100 / total_projections / 2) + 50
progress = "<percent>% (pass 2: <completed_projections>/<total_projections>)"
```

Failed calls in either pass do not increment the respective numerator.

Examples:

- Pass 1, 3 of 15 chunks done -> `10% (pass 1: 3/15)`
- Pass 1 complete (15/15) -> `50% (pass 1: 15/15)`
- Pass 2, 6 of 12 projections enriched -> `75% (pass 2: 6/12)`
- All done -> `100% (pass 2: 12/12)`

---

### 1.3.5 Extract Compliance Provisions

It is similar to Section "1.3.3 Extract Metrics"

### 1.3.6 Generate Scene Blocks

It is similar to Section "1.3.4 Extract Semantic Projections"

### 1.3.7 Extract Structured Knowledge

It is similar to Section "1.3.4 Extract Semantic Projections"

### 1.3.8 Extract Entities and Relations

It is similar to Section "1.3.4 Extract Semantic Projections"
but with just one pass.

---

## 1.4 Go API

### 1.4.1 `DocProcLogger`


```go
type DocProcLogger struct {
    DB *sql.DB
}

func (l DocProcLogger) LogLLMCall(ctx context.Context, rec DocProcLogRecord) error
func (l DocProcLogger) LogSummary(ctx context.Context, rec DocProcLogRecord) error
```

`LogLLMCall` sets `entry_type = 'llm_call'` and inserts the record.  
`LogSummary` sets `entry_type = 'doc_proc_summary'` and inserts the record.

### 1.4.2 `DocProcLogRecord`

```go
type DocProcLogRecord struct {
    CallReason    string
    DocProcName   string
    ModelNames    []string
    PromptName    string
    RecordID      *int64
    ProcProgress  *string
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

### 1.4.3 `SQLStore` Methods

```go
func (s SQLStore) InsertDocProcLog(ctx context.Context, rec DocProcLogRecord) error
func (s SQLStore) ListDocProcLogs(ctx context.Context, f DocProcLogFilter) ([]DocProcLogRow, int64, error)
func (s SQLStore) DeleteOldDocProcLogs(ctx context.Context, retentionDays int) (int64, error)
```

### 1.4.4 `DocProcLogFilter`

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

## 1.5 HTTP API

All endpoints are under the authenticated `/api/v1` group.

### 1.5.1 `GET /api/v1/kb/doc-proc-logs`

List log entries with optional filtering and pagination.

**Query parameters:**

| Param | Type | Default | Description |
|---|---|---|---|
| `entry_type` | string | (all) | `llm_call`, `doc_proc_summary`, `generate_summary`, or `generate_summary_finish` |
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
Each row includes `record_id`, `proc_progress`, and `ms_used`, which are persisted directly by the logger.

### 1.5.2 `DELETE /api/v1/kb/doc-proc-logs/old`

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

## 1.6 Frontend

**Location:** `ChenWeb/web/src/lib/components/home3/doc-proc-logs-view.svelte`

**Menu path:** SYSTEM ADMIN → Doc Processor Logs  
**Menu child ID:** `sysadmin-doc-proc-logs`

### 1.6.1 Features

1. **Log table** — paginated table sorted by create_time DESC by default. Columns: Type, Processor, Activity, Model(s), Pass, Duration, Create Time, Errors, Actions.
2. **Order by controls** — each sortable table field has an order control in its header. Clicking a field toggles asc/desc and reloads the list using `order_by` and `order_dir`; the active sorted field and direction are visually indicated.
3. **Details action** — each record has a Details button in the Actions column. Clicking Details shows the selected record in a details panel/modal with call_reason, llm_call_id, prompt, extra_info (pretty-printed JSON), artifact (pretty-printed JSON), and full error text.
4. **Filters** — entry_type (dropdown) and doc_proc_name (text input). Applied on Search button click.
5. **Pagination** — Prev / Next buttons; current page and total shown.
6. **Retention panel** — numeric input for days; Apply Retention button calls DELETE endpoint.

## 1.7 Implementation
Refer to [2].

## 1.8 References
[1] Doc Processor Log Requirements, KnowledgeStore/Capsules/coding-capsules/doc-processor/doc-processor-log-rqmts.md

[2] Doc Processor Log Implementation, KnowledgeStore/Capsules/coding-capsules/doc-processor/doc-processor-log-impl.md
