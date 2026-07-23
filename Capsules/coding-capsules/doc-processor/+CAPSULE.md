## 1. Summary
This is a service to process parsed store objects. Its main.go is in ChenWeb/server/cmd/doc-processsor.

## 2. JetStream Subscription
It subscribes to JetStream, with subject `kb.pdf.start-doc-processing`.

The service has two invocation modes:

- **Auto Mode:** the normal pipeline path. A payload with a single `record_id`
  and no Dev Mode selectors runs the configured doc-processing pipeline for that
  record, preserving the previous "process this parsed document" behavior.
- **Dev Mode:** an explicit reprocessing command. It selects records by
  `record_ids` or `all`, optionally selects processors with `doc-processors`,
  and defaults to rerunning only failed processors.

### 2.1 DOC_PROCESSOR_MODE

`DOC_PROCESSOR_MODE` controls how messages on `kb.pdf.start-doc-processing`
are interpreted.

| `DOC_PROCESSOR_MODE` value | Mode | Behavior |
|---|---|---|
| unset or empty | Auto Mode | Default. Treat each message as a normal single-record doc-processing event. |
| `auto` | Auto Mode | Treat each message as a normal single-record doc-processing event. |
| `dev` | Dev Mode | Treat each message as an explicit reprocessing command. |
| any other value | Error | The service must fail fast during startup. |

Examples:

```bash
# Default behavior; equivalent to DOC_PROCESSOR_MODE=auto
unset DOC_PROCESSOR_MODE

# Explicit Auto Mode
DOC_PROCESSOR_MODE=auto go run ./server/cmd/doc-processor

# Dev Mode for reprocessing commands
DOC_PROCESSOR_MODE=dev go run ./server/cmd/doc-processor
```

Auto Mode payload:
```json
{
	"record_id":"...",
	"filename":"...",
	"operation":"...",
	"force":true | false
}
```
where:
- "record_id": mandatory, is the value of table field 'kb.inputs.id',
- "filename": optional. If specified, it specifies the name of its input. If the file name has no path, the file is in the same directory derived the field kb.inputs.result_filename.
- "operation": optional. If present, which is a list of doc processor names, it lists the doc processor(s) this service will use on the input. Refer to "Operation" section for more info. 
- "force": optional. If not specified, it defaults to true.

Dev Mode payload:
```json
{
  "record_ids": [12, "22-31"],
  "all": "parsed | failed-procs",
  "doc-processors": ["<doc-processor-name>", "..."],
  "failed-proc-only": true
}
```

where:
- `record_ids`: optional list of record ids. Items may be numbers or quoted
  ranges such as `"22-31"`. JSON does not permit an unquoted `22-31` token.
- `all`: optional selector. If `all` is `"parsed"`, reprocess every PDF record
  in `kb.inputs` whose PDF parsing status is success
  (`operation = "parsed"` and `proc-status`/`proc_status = "success"`).
  If `all` is `"failed-procs"` (also accepted: `"with-failed-procs"`),
  reprocess every record that contains at least one failed doc processor status.
  Any other non-empty value is an error.
- If `all` is empty and `record_ids` is empty, the request is an error.
- Otherwise, the command reprocesses the listed records.
- `doc-processors`: optional processor allow-list. If omitted, it defaults to
  all configured doc processors.
- `failed-proc-only`: optional boolean or boolean string. It defaults to `true`
  in Dev Mode. When true, only failed doc processors are reprocessed. When false,
  all selected doc processors are reprocessed.

Compatibility aliases:
- `record_id` is accepted as a single-record target.
- `doc_processors` is accepted as an alias for `doc-processors`.
- `failed_proc_only` is accepted as an alias for `failed-proc-only`.

## 3. Handle JetStream Events

Since processing an event can potentially take long time, Doc Processor will handle JetStream events as follows:
- Receive an event
- Insert a record to 'kb.events' (refer to KnowledgeStore/database-table-schemas/table-kb-events.md)
- Respond JetSteram

## 4. Retrieve Record

It retrieves the record from 'kb.inputs' by 'kb.inputs.id' = 'event.record_id'. 

Error Handling:
- If failed accessing the database, report the error and finish.
- If the record does not exist, report the error and finish.

## 5. Input File
- If event.filename is present and not empty, it specifies the input file.
- If the file name does not contain path, its directory is derived from kb.inputs.result_filename. 
- If the file name contains path, it must be an absolute path
- If event.filename is absent or empty, the input file name is: '<filename_root>' + '_' + kb.inputs.parser_name + '.txt', where '<filename_root>' is derived from kb.inputs.staging_filename.

Error Handling:
- If kb.inputs.parser_name is null or empty, update 'kb.inputs.status' with error 'missing parser name' and finish.
- If kb.inputs.result_filename is null or empty, update 'kb.inputs.status' with error 'missing result filename' and finish.
- If the specified input file does not exist, update 'kb.inuts.status' with error "input file not exist" and then finish.
- If the specified file is empty, update 'kb.inputs.status' with error "input file empty" and then finish.

## 6. Input File Format
The input file MUST conform to the canonical Line File spec:
`KnowledgeStore/Capsules/coding-capsules/input-management/spec-line-file.md`.

## 6.1. LLM Input Format

All doc processors that make LLM calls **must** send lines to the LLM as a **JSON array**, not as tab-separated text. Each element in the array is an object with this shape:

```json
{ "flag": "n", "line_number": 42, "page_number": 3, "line_type": "text", "content": "..." }
```

Three shared conversion functions in `ChenWeb/server/api/doc-processing/input_lines.go` cover all line source types:

| Function | Input type | When to use |
|---|---|---|
| `blockLinesToJSON([]BlockLine)` | `BlockLine` | Processors whose input comes from the Blocking Processor output (blocks) |
| `markedLinesToJSON([]MarkedLine)` | `MarkedLine` | Processors whose input comes from chunked `Chunk.Lines` |
| `rawLinesToJSON([]Line)` | `Line` | Processors that receive raw `Line` slices (e.g. topic extraction from a single flat slice) |

`markedLinesToJSON` and `rawLinesToJSON` skip lines whose `line_type` is `"image"`.

**Do not** convert lines to tab-separated strings (via `.String()`, `formatMarkedChunkLine`, or `buildMarkedChunkInputText`) and then marshal the string slice. Call the appropriate function above instead.

## 6.2. LLM Prompt Layout & DeepSeek Cache Telemetry

All doc-processor LLM calls go through `newLLMJSONInput` (`ChenWeb/server/api/doc-processing/llm_capture_input.go`), which sets `JSONExtractionInput.DocumentFirst = true`. The shared client (`shared/go/api/llm/openai_client.go::buildMessages`) then emits a **document-first layout**: a constant system message plus the repeated document/chunk text inside `<DOCUMENT_INPUT>…</DOCUMENT_INPUT>` as the stable, cacheable prefix, followed by the per-call task instructions inside `<TASK>…</TASK>`. This maximizes DeepSeek prompt-cache reuse — see ADR 2026062501 (`KnowledgeStore/doc-repo/adrs/202606/2026062501-adr-deepseek-cache.md`) and the doc-processor extension ADR 2026062701.

> For cross-processor cache hits to land, the serialized chunk/block text placed in `InputText` must be **byte-identical** across processors (ADR principle 3). Keep task/schema text out of `InputText` (put it in the prompt, i.e. the `<TASK>` section) and serialize the shared chunk via the canonical helpers in §6.1.

**Canonical chunk serialization (Phase 2.3).** Chunk-based processors build `InputText` via the single helper `canonicalChunkInputText(chunk.Lines, docCtx)` (`input_lines.go`) = `wrapLinesWithDocContext(markedLinesToJSON(lines), docCtx)`, where `docCtx = buildDocContextLine(rec)`. Because every chunk processor loads the same `.chunks` artifact and the same record, the same chunk yields a byte-identical `InputText` across processors → DeepSeek reuses the cached prefix. No per-processor schema/label/index text goes in `InputText`; it lives in the prompt (`<TASK>`). All six chunk-consuming processors are converged: `extract_metrics` (pass 1 candidate — `chunksToBlocks` is 1:1 so it shares the same chunk boundaries; output mapping still uses `Block` internally), `extract_semantic_projections` (pass 1 candidate **and** pass 2 enrich — pass 2 reuses pass 1's chunk prefix), `extract_entity_relation` (entities + freeform relations), `extract_inventory_items`, and `extract_provisions` **chunk mode** (`EXTRACT_PROVISIONS_INPUT` unset/`chunks`).

> **Not converged:** `extract_provisions` **blocks mode** uses `Block`s with a different serialization, so its LLM input unit differs from chunk mode. `create_artifact_category` is intentionally **task-first** (its prompt template, not the per-call key, is the stable prefix).

**InputText sequencer (Phase 3).** Even with canonical prefixes, Phase B fans out one goroutine per processor and each launches its per-chunk goroutines concurrently — identical chunk prefixes from different processors may not be temporally adjacent. An `inputTextSequencer` (`shared/go/api/llm/openai_sequencer.go`) serialises the shared client's HTTP calls by `InputText` key: when `DocumentFirst` is true, the call acquires a per-InputText binary semaphore before the HTTP request and releases after. Calls with the same canonical InputText (same chunk) queue — so the same prefix arrives at DeepSeek back-to-back, guaranteeing cache hits. Controlled by env `LLM_INPUT_TEXT_SEQUENCER` (default `true`).

`kb.doc_proc_logs` records the provider prompt-cache counters per LLM call in two columns,
`prompt_cache_hit_tokens` and `prompt_cache_miss_tokens` (nullable; NULL for non-LLM
entries). They are populated from the LLM client's `LastJSONUsage()` via
`extractorCacheTokens` (`cache_log.go`) at each `llm_call` log site, mirroring the
`llm_usage_event` cache columns. Use them to validate cache effectiveness
(migration `project_migrations/20260627000001_add_doc_proc_logs_cache_tokens.sql`).

## 7. Doc Processing Pipeline
This service is a controller. For a received event, it applies a number of doc processors to it.
Currently, it has the following doc processors:
| Seqno | Processor Name | Type | Require LLMs | Dependence | Explanation |
|---|---|---|---|---|---|
|1 | blocking | mandatory | No | after 1 | Blocking Processor. Refer to [6]. This processor is always executed. |
|2 | structure_analyzer | mandatory | No | none | Doc Structure Static Analyzer. Refer to [1] |
|3 | chunking | mandatory | No | after 2 | Chunking Processor. Refer to [2]|
|4 | extract_metadata | mandatory | Yes | after 1 | Extract Doc Metadata Processor. Refer to [3] for its spec |
|5 | extract_metrics | configurable | Yes | after 3 | Extract Metrics Processor. Refer to [4] for its spec |
|6 | extract_provisions | configurable | Yes | after 3 (default) or after 1 (EXTRACT_PROVISIONS_INPUT="blocks") | Extract provisions. Refer to [5] |
|7 | extract_semantic_projections | configurable | Yes | after 3 | Extract semantic projections. Refer to [11] |
|8 | generate_summaries | configurable | Yes | after 3 | Generate summaries. Refer to [7] |
|9 | generate_topics | configurable | Yes | after 3 | Generate topics. Refer to [8] |
|10 | generate_scene_blocks | configurable | Yes | after 3 | Generate scene blocks. Refer to [9] |
|11 | extract_entity_relation | configurable | Yes | after 3 | Extract entities and relations. Refer to [13] |
|12 | extract_inventory_items | configurable | Yes | after 3 | Extract inventory item objects. Refer to [15] |
|13 | review_document | configurable | Yes | after 3 | Document review: LLM-powered multi-aspect review pipeline. On-demand only (Phase C). Refer to [16] — ADR 2026061801 |
---

Note: the term 'after n' (such as 'after 1') means it uses the processor 'n' output as its input.
For instance, 'after 1' means it uses the Blocking Processor's output as its input.

### 7.1 Processor Categories

**Mandatory processors** (`blocking`, `structure_analyzer`, `chunking`, `extract_metadata`) are always executed regardless of configuration or the `operation` field in the event payload.

**Configurable processors** (`extract_metrics`, `extract_provisions`, `generate_summaries`, `generate_topics`, `generate_scene_blocks`, `extract_semantic_projections`, `extract_entity_relation`) are executed only when they are listed in `config.toml` under `[doc-processing].required_processors`. Example:

```toml
[doc-processing]
required_processors = ["extract_metrics", "extract_provisions", "generate_summaries", "generate_topics", "generate_scene_blocks", "extract_semantic_projections", "extract_entity_relation", "extract_inventory_items"]
```

If `required_processors` is absent or empty, no configurable processors run by default.

### 7.2 Pipeline Invocation Modes

The doc processor pipeline can be invoked in one of the following modes:
- All-Processor Mode: run all the configured doc processors
- Selected-Processor Mode: run only selected processors

The `all-processor` mode is used to process documents as whole. The `selected-processor` 
mode is normally invoked by users through GUI or CLI to chery pick the ones to run.

JetStream command mode selection:
- When `DOC_PROCESSOR_MODE=auto`, the default subject runs Auto Mode. It runs
  the configured pipeline unless `operation` explicitly filters processors.
- When `DOC_PROCESSOR_MODE=dev`, the default subject runs Dev Mode. It accepts
  `record_ids`, `all`, `doc-processors`, and `failed-proc-only`; it defaults
  `failed-proc-only` to `true`.
- If Dev Mode selects no processors for a record because no selected processor
  is currently failed, the record is skipped and a log entry is emitted.

### 7.3 Pipeline Execution Model

The pipeline uses a three-phase model per record:

- **Phase A (sequential):** the four mandatory processors (`blocking`, `structure_analyzer`/`static_analyzer`, `chunking`, `extract_metadata`) are executed **in dependency order, one at a time**, regardless of the concurrency flag. Their outputs feed downstream processors. The block buffer is cleared after `static_analyzer` (stale pre-analysis blocks); chunk-buffer consumers read only.
- **Phase B (concurrent):** all configured configurable processors (#5–#14 from the pipeline table) are **fanned out as concurrent goroutines** under a `sync.WaitGroup`, because they have no cross-dependencies. A per-record mutex serializes all `kb.inputs.status` read-modify-write sequences so concurrent status entries are never lost. Each processor runs to completion independently; a failure in one does not cancel siblings.
- **Phase C (indexing):** after all doc processors finish, it kicks off this phase [Post Process](#post_process), which indexes the artifacts of the artifacts the doc processors generated.

Controlled by `RUN_DOC_PROCESSOR_CONCURRENT` env var (default `"true"`). Set to `"false"` to fall back to the original sequentially-ordered pipeline.

**Single-instance constraint:** the status lock is an in-process mutex. If doc-processor is ever scaled to multiple replicas, upgrade to a DB row lock (`SELECT … FOR UPDATE`) + `jsonb_set` or a shared coordinator (Redis / dedicated primary status instance). See `ChenWeb/server/api/doc-processing/status_lock.go` and `docs/superpowers/specs/2026-06-01-concurrent-doc-processors-design.md`.

### 7.4 Record Completion Criteria

A record in `kb.inputs` is considered **finished** when every processor that is expected to run for that record has reached `proc_status` = `"success"`, `"failed"`, or `"stopped"`. The expected set is:

1. All four mandatory processors.
2. Every configurable processor listed in `config.toml` `[doc-processing].required_processors` at the time the event was dispatched.

If the event payload supplies an explicit `operation` list, the expected set is instead the union of mandatory processors and the intersection of the `operation` list with the configured `required_processors`.

Important:
- `generate_summaries` and `generate_topics` are separate doc processors now.
- They used to be hard coded inside `chunking`, but that coupling has been removed.
- As a result, running `chunking` alone no longer implicitly runs `generate_summaries` or `generate_topics`.
- To preserve the old behavior, include `generate_summaries` and/or `generate_topics` explicitly in the requested `operation` list, or omit `operation` so the full configured pipeline runs.

### 7.4 Post Process
Indexing the artifacts processed by doc processors is not done by doc processors.
When the pipeline finishes Phase B (i.e., finish processing all doc processors),
the pipeline goes to this phase to (re-)index only the artifacts from the 
invoked doc processors in this pipeline.

**Implementation:** the controller (`ChenWeb/server/api/doc-processing/control.go`) defines
`PostProcessIndexer { PostProcessIndex(ctx, recordID) error }`. After Phase B completes
(and the pipeline was not stopped), `runPostProcessIndexing` calls `PostProcessIndex` on
each invoked processor that implements the interface. Indexing errors are logged and do
not abort sibling processors. `MetricsProcessor` is the first adopter (its
`PostProcessIndex` reindexes `kb.search_artifacts`, then builds `connected_artifacts`,
`category_instance`, category-path `metrics.txt`, and `hybrid_search` links). Other
processors still index inline at the end of their Phase B `HandleEvent`; migrate them to
`PostProcessIndexer` as cross-artifact indexing is added.

For more information about indexing artifacts, refer to [16].

**Deletion lifecycle:** any processor or post-process indexer that writes
document-owned rows or files for a `kb.inputs.id` must also participate in
the input deletion contract. The source of truth is ADR 2026072301:
`KnowledgeStore/doc-repo/adrs/202607/2026072301-adr-kb-input-artifact-deletion.md`.
That ADR lists the current generated tables/files and defines the future
per-module deleter registration model.

### 7.5 Artifact Category Creation Under Concurrent Pipelines

Some doc processors, currently `extract_metrics` and
`extract_inventory_items`, may discover new artifact categories while they run.
Because configurable processors already run concurrently in Phase B, and
multiple documents may be processed at the same time, category creation must
not perform synchronous one-by-one LLM calls in the request path.

The pipeline contract is:

- a processor may resolve a category and receive a valid `category_id`
  immediately, even if that category's metadata is still incomplete;
- the processor must not wait for category-enrichment LLM work before finishing;
- category enrichment is delegated to a shared background worker pool that is
  global across all pipelines;
- multiple processors and multiple pipelines may race on the same missing
  `(category_type, category_key)`, but they must all converge on the same
  placeholder category row;
- only the background enricher performs the expensive LLM call, using a
  database-backed claim/lease mechanism so exactly one worker enriches a given
  category at a time.

Operationally, this turns category creation into a two-stage flow:

1. The doc processor synchronously performs a fast placeholder upsert and gets
   back the canonical `category_id`.
2. The doc processor continues normal artifact persistence and indexing.
3. A shared category-enricher service later fills in aliases, description,
   specs, keywords, and embeddings concurrently.

This model preserves Phase B processor concurrency and scales cleanly when the
system runs multiple pipelines at once.

## 8. JetStream Request

JetStream request payload may have an `operation` or `doc-processors` attribute. If present, it specifies the doc
processor to apply to the input file (or chunk files). Its value must be the ones in the 
table [Doc Processing Pipeline](#doc-processing-pipeline).

If multiple processors are specified, they must be applied in the order in which they are listed.

Important:

- The `operation` field is an explicit processor filter.
- If `operation` is omitted or empty, Doc Processor applies all configured processors. Mandatory (Phase A) processors always run in dependency order; configurable (Phase B) processors run concurrently (order unspecified).
- If `operation` is `"chunking"`, Doc Processor runs the always-on `blocking` processor and then the `chunking` processor only.
- `generate_summary` and `generate_topics` are no longer implicitly included in `chunking`.
- `extract_provisions` is a separate processor. When `EXTRACT_PROVISIONS_INPUT="chunks"` (default), it depends on the chunking output and both must be requested together:

```json
{
  "record_id": "123",
  "operation": ["chunking", "extract_provisions"],
  "force": true
}
```

When `EXTRACT_PROVISIONS_INPUT="blocks"`, it depends only on the blocking processor (always-on) and can be requested standalone:

```json
{
  "record_id": "123",
  "operation": ["extract_provisions"],
  "force": true
}
```

- `generate_topics` depends on the `chunking` processor (pipeline #3). When invoked standalone, the chunk files produced by a prior chunking run must already exist on disk. To run chunking and topic generation together in one event:

```json
{
  "record_id": "123",
  "operation": ["chunking", "generate_summary", "generate_topics"],
  "force": true
}
```

## 9. Doc Process Status

`kb.inputs.status` is a JSON array holding one entry per processor and is the **source of truth**
for doc-processing status. Processors append/replace their own entry exactly as documented below.

**Indexed projections (do not write these directly).** Because filtering tens of millions of rows
by a predicate *inside* the JSON array forced sequential scans, two read-optimized projections of
`status` are maintained automatically by **database triggers** on `kb.inputs` (migration
`ChenWeb/project_migrations/20260609000002_add_kb_inputs_status_rollups.sql`):

- Rollup columns on `kb.inputs`: `parse_state` (`pending|parsed_success|parsed_failed`),
  `pipeline_state` (`pending|running|success|failed|stopped`, from the `doc_processing` entry),
  and `has_failed_proc` (boolean, real doc-processor failures only).
- Child table `kb.input_proc_status (record_id, processor, proc_status, start_time, ms_used,
  error, ...)` — one row per processor, for per-processor status queries.

Implications for processor authors:

- **You do not change anything.** Keep writing `kb.inputs.status`; the triggers derive the
  projections on every write. This holds for every writer across pdf-parser, file-converters and
  doc-processor — none of them maintain the projections in code.
- A **new** processor needs no schema change: its `kb.input_proc_status` row appears automatically
  once it writes a status entry. Only extend `kb.canonical_op` if it introduces a legacy
  operation-name alias.
- Read/filter status via the rollup columns (`parse_state`, `pipeline_state`, `has_failed_proc`)
  or `kb.input_proc_status`, never via `jsonb_array_elements(status)` / `jsonb_path_exists`.
- See `KnowledgeStore/Capsules/coding-capsules/input-management/input-status-mgmt.md` for the full
  design.

Refer to [14] about updating the following entry in `kb.inputs.status`:

```json
  {
    "operation": "doc_processing",
    "start_time": "20260528 17:56:10",
    "proc_status": "running"
  }
```

### 9.1 Structure Analayzer
When: When the structure analyzer finishes.

Status JSON:
```json
{
    "record_id":"ddd",
    "file_type":"pdf | doc | docx | ppt | pptx | ...",
    "operation":"static_analzyer",
    "proc_status":"success | failed",
    "input_filename": "std_20039_opendata.txt",
    "num_lines": 703,
    "num_pages": 26,
    "num_labeled_lines": 610,
    "error":"xxx",
    "start_time":"yyyymmdd hh:mm:ss",
    "ms_used":ddd,
}
```

### 9.2 Chunking
When: When the Chunking processor finishes.

Status JSON:
```json
{
    "record_id":"ddd",
    "file_type":"pdf | doc | docx | ppt | pptx | ...",
    "operation":"chunked",
    "proc_status":"success | failed",
    "input_filename": "Artifacts/0/100/std_20039_opendata.txt"
    "num_lines": 703,
    "num_pages": 26,
    "num_labeled_lines": 610,
    "num_chunks": 40,
    "error":"xxx",
    "start_time":"yyyymmdd hh:mm:ss",
    "ms_used":ddd,
}
```

The chunking processor also inserts a row into `kb.chunks` for each chunk run:

| Column | Type | Description |
|---|---|---|
| `id` | `BIGSERIAL` | Primary key |
| `source_record_id` | `BIGINT` | FK → `kb.inputs.id` |
| `chunking_method` | `VARCHAR(64)` | `fix-size-chunking` or `topic-chunking` |
| `chunking_size` | `INTEGER` | Byte size (fixed) or page count (topic) per chunk |
| `overlap_percent` | `INTEGER` | Overlap percentage between chunks |
| `notes` | `TEXT` | Free-text notes about the chunk run |
| `overlap_lines` | `TEXT` | JSON array of overlap line ranges per chunk, e.g. `["[12-15]","[87-90]"]` |
| `normal_lines` | `TEXT` | JSON array of normal (non-overlap) line ranges per chunk |
| `chunk_lines` | `TEXT` | JSON array of raw text content per chunk |
| `create_time` | `TIMESTAMPTZ` | Row creation timestamp |
| `update_time` | `TIMESTAMPTZ` | Row last-update timestamp |

For semantic (topic) chunking, `overlap_lines` is always `"[]"` since semantic chunking has no overlap markers.

See ADR: [doc-2026061107](../../doc-repo/202606/2026061107-adr-chunk-table-changes.md).

### 9.3 Extract Doc Metadata 
When: When the Extract Doc Metadata processor finishes.

Status JSON:
```json
{
    "record_id":"ddd",
    "file_type":"pdf | doc | docx | ppt | pptx | ...",
    "operation":"extract_metadata",
    "proc_status":"success | failed",
    "input_filename": "Artifacts/0/100/std_20039_opendata.txt"
    "error":"xxx",
    "start_time":"yyyymmdd hh:mm:ss",
    "ms_used":ddd,
}
```

### 9.4 Extract Provisions
When: When the Extract Provisions processor finishes.

Status JSON:
```json
{
    "record_id":"ddd",
    "file_type":"pdf | doc | docx | ppt | pptx | ...",
    "operation": "extract_provisions",
    "proc_status":"success | failed",
    "input_filename": "Artifacts/0/100/std_20039_opendata.txt"
    "error":"xxx",
    "start_time":"yyyymmdd hh:mm:ss",
    "ms_used":ddd,
}
```

### 9.5 Extract Metrics
When: When the Extract Metrics processor finishes.

Status JSON:
```json
{
    "record_id":"ddd",
    "file_type":"pdf | doc | docx | ppt | pptx | ...",
    "operation": "extract_metrics",
    "proc_status":"success | failed",
    "input_filename": "Artifacts/0/100/std_20039_opendata.txt"
    "error":"xxx",
    "start_time":"yyyymmdd hh:mm:ss",
    "ms_used":ddd,
}
```

### 9.6 Generate Summaries
When: When the Generate Summary ([7])processor finishes.

Status JSON:
```json
{
    "record_id":"ddd",
    "file_type":"pdf | doc | docx | ppt | pptx | ...",
    "operation": "generate_summaries",
    "proc_status":"success | failed",
    "input_filename": "Artifacts/0/100/std_20039_opendata.txt"
    "error":"xxx",
    "start_time":"yyyymmdd hh:mm:ss",
    "ms_used":ddd,
}
```

### 9.7 Generate Topics
When: When the Generate Topics ([8]) processor finishes (success, failure, or user-requested stop).

Status JSON:
```json
{
    "record_id":"ddd",
    "file_type":"pdf | doc | docx | ppt | pptx | ...",
    "operation": "generate_topics",
    "proc_status":"success | failed | stopped",
    "num_topics":ddd,
    "input_filename": "xxx",
    "output_filename": "xxx",
    "error":"xxx",
    "start_time":"yyyymmdd hh:mm:ss",
    "ms_used":ddd,
}
```

`proc_status = "stopped"` is written when a user stop request is detected mid-execution (at the boundary of an LLM call). `num_topics` reflects how many topics were extracted before the stop. `error` is absent on a clean stop.

### 9.8 Extract Semantic Projection
When: When the extract semantic projection ([11]) processor finishes.

Status JSON:
```json
{
  "record_id": "ddd",
  "file_type": "pdf | doc | docx | ppt | pptx | ...",
  "operation": "extract_semantic_projections",
  "proc_status": "success",
  "input_filename": "Artifacts/0/100/std_20039_opendata.txt",
  "start_time": "yyyymmdd hh:mm:ss",
  "ms_used": ddd
}
```

### 9.9 Extract Entity & Relation
When: When the extract entity-relation ([13]) processor finishes.

Status JSON:
```json
{
  "record_id": "ddd",
  "file_type": "pdf | doc | docx | ppt | pptx | ...",
  "operation": "extract_entity_relation",
  "proc_status": "success | failed",
  "input_filename": "Artifacts/0/100/std_20039_opendata.txt",
  "error": "xxx",
  "start_time": "yyyymmdd hh:mm:ss",
  "ms_used": ddd
}
```

### 9.10 Extract Inventory Items
When: When the extract inventory items ([15]) processor finishes.

Status JSON:
```json
{
  "record_id": "ddd",
  "file_type": "pdf | doc | docx | ppt | pptx | ...",
  "operation": "extract_inventory_items",
  "proc_status": "success | failed",
  "input_filename": "Artifacts/0/100/std_20039_opendata.txt",
  "error": "xxx",
  "start_time": "yyyymmdd hh:mm:ss",
  "ms_used": ddd
}
```

## 10 Handle Stop Request

A user stop request is signalled by cancelling the pipeline's context with the cause `ErrPipelineStopped`. The pipeline controller (`ControlService`) triggers this via a 1-second polling goroutine that checks the `stop_requested` flag in `kb.inputs.status`.

### 10.1 Shared Function: `CheckAndHandleStop`

Every doc processor that makes LLM calls **must** call `CheckAndHandleStop` at each LLM call boundary to provide prompt, consistent stop behaviour. The function is defined in `ChenWeb/server/api/doc-processing/stop.go`.

```go
// CheckAndHandleStop checks whether the pipeline context was cancelled by a user
// stop request. If it was, onStop is called with a background context (for DB
// writes), and the function returns true. The caller must then return
// ErrPipelineStopped immediately.
func CheckAndHandleStop(ctx context.Context, onStop OnStopFunc) bool
```

`OnStopFunc` is `func(bgCtx context.Context)`. The background context is always passed because the pipeline context is already cancelled at the point of the call.

### 10.2 Contract for Each Processor

When `CheckAndHandleStop` returns true the `onStop` callback **must**:

1. Write `proc_status = "stopped"` to the appropriate `kb.inputs.status` entry, preserving progress counters accumulated so far (e.g. `num_topics`, `num_metrics`).
2. Write a finish log entry to `kb.doc_proc_logs` (the processor's `finish` entry type) with a human-readable stopped reason in the `errors` field.
3. Use the provided background context for all DB writes.

After `CheckAndHandleStop` returns true, the calling function returns `ErrPipelineStopped` immediately — no further LLM calls or artifact writes.

### 10.3 Call-Site Pattern

```go
// Define the callback once, before the loop.
onStop := func(bgCtx context.Context) {
    s.stopAndPersistFoo(bgCtx, rec, inputFilename, start, itemsSoFar)
}

for _, item := range items {
    // Check before the primary LLM call.
    if CheckAndHandleStop(ctx, onStop) {
        return ErrPipelineStopped
    }
    result, err := callLLM(ctx, ...)

    if err != nil {
        if s.FallbackExtractor != nil {
            // Check before the fallback LLM call.
            if CheckAndHandleStop(ctx, onStop) {
                return ErrPipelineStopped
            }
            result, err = callFallbackLLM(ctx, ...)
            if err != nil {
                // Check after fallback failure (context may have been cancelled
                // during the call).
                if CheckAndHandleStop(ctx, onStop) {
                    return ErrPipelineStopped
                }
                // handle normal fallback failure...
            }
        } else {
            // Check before returning a real error.
            if CheckAndHandleStop(ctx, onStop) {
                return ErrPipelineStopped
            }
            return fmt.Errorf("...: %w", err)
        }
    }
}
```

### 10.4 Reference Implementation

`generate_topics` (`ChenWeb/server/api/doc-processing/fix-size-chunking.go`, function `handleGenerateTopicsLines`) is the reference implementation. Use it as the template when adding stop support to other processors.

## 11. Workflow

- Receive an event
- Retrieve the record by event.record_id
- Read the input file (refer to "Input File" section) into a buffer, called Input File Buffer
- Apply Blocking Processor to break the input file into blocks. Save the result into Block Buffer.
- Apply all the doc processors in the same order as listed in "Doc Processing Pipeline" section

## 12. Add New Doc Processor

Use this checklist when adding a new doc processor (mandatory or configurable).

### 12.1. Documentation

- Create a spec file: `KnowledgeStore/Capsules/coding-capsules/doc-processor/<name>-spec.md`
- Create an impl file: `KnowledgeStore/Capsules/coding-capsules/doc-processor/<name>-impl.md`
- Add the processor to the **Doc Processing Pipeline** table in this file with its seqno, type (`mandatory` / `configurable`), dependency, and a reference link.
- Add a status JSON subsection under **Doc Process Status** in this file.
- If configurable, add the processor name to the `required_processors` example in the **Processor Categories** section.

### 12.2. Implementation

- Implement the processor in `ChenWeb/server/api/doc-processing/`.
- Register it in `ChenWeb/server/cmd/doc-processor/main.go`.
- If configurable, add its name to `[doc-processing].required_processors` in `config.toml`.
- When building LLM input text from lines, call the appropriate shared helper (`blockLinesToJSON`, `markedLinesToJSON`, or `rawLinesToJSON`). See **LLM Input Format** above.

### 12.3. Hybrid Search Index (BM25 + embeddings)

> **Status — target design (migration in progress).** Search is moving from `tsvector` + GIN
> to ParadeDB `pg_search` (BM25 + Jieba) for lexical retrieval plus `pgvector` for semantic
> retrieval, fused with RRF. See `KnowledgeStore/Research/PostgreSQLIndex.typ`. Until the
> migration lands, the live `kb.search_artifacts` partitions and `search_indexing.go` still use
> `search_vector TSVECTOR` / `USING GIN` — treat the steps below as the destination, not the
> current code.

Every processor whose output should be searchable needs a dedicated `kb.search_artifacts`
partition and indexer:

- Add a `searchArtifactXxx` string constant in `ChenWeb/server/api/doc-processing/search_indexing.go`.
- Add `ReindexXxxSearchForRecord` and `buildXxxRegistryRows` functions following the pattern of the existing artifact types in the same file. `buildXxxRegistryRows` maps the artifact's own columns onto the generic search fields (`title`, `keywords`, `description`, `context`, `source_text`) and builds the synthetic `embedding_text` used to compute the embedding (see `KnowledgeStore/Research/PostgreSQLIndex.typ` → "Create a normalized embedding text").
- Call `ReindexXxxSearchForRecord` at the end of the processor's workflow (after saving output to the database). It upserts one flattened row per artifact into `kb.search_artifacts`; the BM25 and HNSW indexes are live, so no materialized-view refresh is needed.
- In `buildXxxRegistryRows`, scan any nullable column (`TEXT`, `JSONB`, etc.) into `sql.NullString` / `[]byte` — never into a plain `string`. Scanning a NULL PostgreSQL column into a plain Go `string` produces `sql: Scan error … converting NULL to string is unsupported` at runtime. Use `nullVar.String` when building the `RegistryRow` fields.

- Add a goose migration in `ChenWeb/project_migrations/` to create the partition and its indexes. ParadeDB BM25 indexes do **not** propagate from the partitioned parent, so create both the BM25 and HNSW indexes on the partition itself:

```sql
CREATE TABLE IF NOT EXISTS kb.search_artifacts_<type> PARTITION OF kb.search_artifacts
    FOR VALUES IN ('<type>');

-- lexical: BM25 + Jieba (replaces the old GIN (search_vector) index)
CREATE INDEX IF NOT EXISTS idx_kb_search_artifacts_<type>_bm25
    ON kb.search_artifacts_<type>
    USING bm25 (
        id,
        (title::pdb.jieba),
        (keywords::pdb.jieba),
        (description::pdb.jieba),
        (context::pdb.jieba),
        (source_text::pdb.jieba)
    )
    WITH (key_field = 'id');

-- semantic: pgvector HNSW over the embedding column
CREATE INDEX IF NOT EXISTS idx_kb_search_artifacts_<type>_hnsw
    ON kb.search_artifacts_<type>
    USING hnsw (embedding vector_cosine_ops);

CREATE INDEX IF NOT EXISTS idx_kb_search_artifacts_<type>_record
    ON kb.search_artifacts_<type> (input_record_id);
```

Skipping this migration causes a `pq: no partition of relation "search_artifacts" found for row` error at runtime.

Requires the `pg_search`, `vector` (pgvector), and Jieba tokenizer extensions installed on the instance.

### 12.4. Dashboard

Update `ChenWeb/web/src/lib/components/home3/doc-processor-dashboard-view.svelte`:

- **Node state mapping** — add the processor's `operation` name to the `operation → Stage` map used to render pipeline cards in the Active Pipelines section.
- **`PIPELINE_FINAL_OPS`** — add the processor so `isActiveRecord` waits for it to reach a final state before dismissing a record from the active view.
- **`ALL_PROCESSOR_IDS`** — if configurable, add it so it appears as a toggleable checkbox in the Manual Launch and Restart dialogs. Mandatory processors are always included and shown disabled; do not add them here.
- **`isActiveRecord` downstream guard** — add the processor name to the list of downstream processors checked when blocking has succeeded but leaf processors have not yet started.

Also update [14] to reflect the updated `PIPELINE_FINAL_OPS` and `ALL_PROCESSOR_IDS` lists.

## 13. References

[1] Doc Structure Analyzer Spec: KnowledgeStore/Capsules/coding-capsules/doc-processor/structure-analyzer-static-spec.md

[2] Chunking Processor Spec: KnowledgeStore/Capsules/coding-capsules/chunking/+CAPSULE.md

[3] Extract Doc Metadata Spec: KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-metadata.md 

[4] Extract Metrics Spec: KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-metrics-spec.md

[5] Extract Terms Spec: KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-provisions-spec.md

[6] Break Documents to Blocks: KnowledgeStore/Capsules/coding-capsules/blocking-spec.md

[7] Generate Summaries: KnowledgeStore/Capsules/coding-capsules/doc-processor/generate-summary-spec.md

[8] Generate Summaries: KnowledgeStore/Capsules/coding-capsules/doc-processor/generate-topic-spec.md

[9] Generate Scene Blocks: KnowledgeStore/Capsules/coding-capsules/doc-processor/generate-scene-blocks.md

[11] Extract Semantic Projections: KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-semantic-projection-spec.md

[13] Extract Entity & Relation: KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-entity-relation-spec.md

[14] KnowledgeStore/Capsules/coding-capsules/doc-processor/doc-processor-dashboard-spec.md

[15] Extract Inventory Items Spec: KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-inventory-items-spec.md

[16] ADR 2026061801 — Document Review: LLM-Powered Multi-Aspect Review Pipeline:
  `KnowledgeStore/doc-repo/adrs/202606/2026061801-adr-document-review.md`
  
[17] Document Review Spec: `KnowledgeStore/Capsules/coding-capsules/doc-processor/document-review-spec.md`
