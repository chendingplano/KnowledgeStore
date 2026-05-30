## Summary
This is a service to process parsed store objects. Its main.go is in ChenWeb/server/cmd/doc-processsor.

## JetStream Subscription
It subscribes to JetStream, with subject 'kb.line-file-generated'. The event payload is:
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

## Handle JetStream Events

Since processing an event can potentially take long time, Doc Processor will handle JetStream events as follows:
- Receive an event
- Insert a record to 'kb.events' (refer to KnowledgeStore/database-table-schemas/table-kb-events.md)
- Respond JetSteram

## Retrieve Record

It retrieves the record from 'kb.inputs' by 'kb.inputs.id' = 'event.record_id'. 

Error Handling:
- If failed accessing the database, report the error and finish.
- If the record does not exist, report the error and finish.

## Input File
- If event.filename is present and not empty, it specifies the input file.
- If the file name does not contain path, its directory is derived from kb.inputs.result_filename. 
- If the file name contains path, it must be an absolute path
- If event.filename is absent or empty, the input file name is: '<filename_root>' + '_' + kb.inputs.parser_name + '.txt', where '<filename_root>' is derived from kb.inputs.staging_filename.

Error Handling:
- If kb.inputs.parser_name is null or empty, update 'kb.inputs.status' with error 'missing parser name' and finish.
- If kb.inputs.result_filename is null or empty, update 'kb.inputs.status' with error 'missing result filename' and finish.
- If the specified input file does not exist, update 'kb.inuts.status' with error "input file not exist" and then finish.
- If the specified file is empty, update 'kb.inputs.status' with error "input file empty" and then finish.

## Input File Format
The input file MUST conform to the canonical Line File spec:
`KnowledgeStore/DevDocuments/Specs/spec-line-file.md`.

## LLM Input Format

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

## Doc Processing Pipeline
This service is a controller. For a received event, it applies a number of doc processors to it.
Currently, it has the following doc processors:
| Seqno | Processor Name | Type | Require LLMs | Dependence | Explanation |
|---|---|---|---|---|---|
|1 | blocking | mandatory | No | after 1 | Blocking Processor. Refer to [6]. This processor is always executed. |
|2 | structure_analyzer | mandatory | No | none | Doc Structure Static Analyzer. Refer to [1] |
|3 | chunking | mandatory | No | after 1 | Chunking Processor. Refer to [2]|
|4 | extract_metadata | mandatory | Yes | after 1 | Extract Doc Metadata Processor. Refer to [3] for its spec |
|5 | extract_metrics | configurable | Yes | after 1 | Extract Metrics Processor. Refer to [4] for its spec |
|6 | extract_provisions | configurable | Yes | after 1 | Extract provisions. Refer to [5] |
|7 | generate_summaries | configurable | Yes | after 3 | Generate summaries. Refer to [7] |
|8 | generate_topics | configurable | Yes | after 3 | Generate topics. Refer to [8] |
|9 | generate_scene_blocks | configurable | Yes | after 3 | Generate scene blocks. Refer to [9] |
|10 | extract_products | configurable | Yes | after 1 | Extract product relations. Refer to [10] |
|11 | extract_semantic_projections | configurable | Yes | after 3 | Extract semantic projections. Refer to [11] |
|12 | extract_structured_knowledge | configurable | Yes | after 3 | Extract structured knowledge. Refer to [12] |
|13 | extract_entity_relation | configurable | Yes | after 3 | Extract entities and relations. Refer to [13] |
---

Note: the term 'after n' (such as 'after 1') means it uses the processor 'n' output as its input.
For instance, 'after 1' means it uses the Blocking Processor's output as its input.

### Processor Categories

**Mandatory processors** (`blocking`, `structure_analyzer`, `chunking`, `extract_metadata`) are always executed regardless of configuration or the `operation` field in the event payload.

**Configurable processors** (`extract_metrics`, `extract_provisions`, `generate_summaries`, `generate_topics`, `generate_scene_blocks`, `extract_products`, `extract_semantic_projections`, `extract_structured_knowledge`, `extract_entity_relation`) are executed only when they are listed in `config.toml` under `[doc-processing].required_processors`. Example:

```toml
[doc-processing]
required_processors = ["extract_metrics", "extract_provisions", "generate_summaries", "generate_topics", "generate_scene_blocks", "extract_products", "extract_semantic_projections", "extract_structured_knowledge", "extract_entity_relation"]
```

If `required_processors` is absent or empty, no configurable processors run by default.

### Record Completion Criteria

A record in `kb.inputs` is considered **finished** when every processor that is expected to run for that record has reached `proc_status` = `"success"`, `"failed"`, or `"stopped"`. The expected set is:

1. All four mandatory processors.
2. Every configurable processor listed in `config.toml` `[doc-processing].required_processors` at the time the event was dispatched.

If the event payload supplies an explicit `operation` list, the expected set is instead the union of mandatory processors and the intersection of the `operation` list with the configured `required_processors`.

Important:
- `generate_summaries` and `generate_topics` are separate doc processors now.
- They used to be hard coded inside `chunking`, but that coupling has been removed.
- As a result, running `chunking` alone no longer implicitly runs `generate_summaries` or `generate_topics`.
- To preserve the old behavior, include `generate_summaries` and/or `generate_topics` explicitly in the requested `operation` list, or omit `operation` so the full configured pipeline runs.

## Doc Process Status

Refer to [14] about updating the following entry in `kb.inputs.status`:

```json
  {
    "operation": "doc_processing",
    "start_time": "20260528 17:56:10",
    "proc_status": "running"
  }
```

### Structure Analayzer
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

### Chunking
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

### Extract Doc Metadata 
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

### Extract Provisions
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

### Extract Metrics
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

### Generate Summaries
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

### Generate Topics
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

### Extract Semantic Projection
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

### Extract Structured Knowledge
When: When the extract structured knowledge ([12]) processor finishes.

Status JSON:
```json
{
  "record_id": "ddd",
  "file_type": "pdf | doc | docx | ppt | pptx | ...",
  "operation": "extract_structured_knowledges",
  "proc_status": "success | failed",
  "start_time": "yyyymmdd hh:mm:ss",
  "ms_used": ddd
}
```

### Extract Entity & Relation
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

## Handle Stop Request

A user stop request is signalled by cancelling the pipeline's context with the cause `ErrPipelineStopped`. The pipeline controller (`ControlService`) triggers this via a 1-second polling goroutine that checks the `stop_requested` flag in `kb.inputs.status`.

### Shared Function: `CheckAndHandleStop`

Every doc processor that makes LLM calls **must** call `CheckAndHandleStop` at each LLM call boundary to provide prompt, consistent stop behaviour. The function is defined in `ChenWeb/server/api/doc-processing/stop.go`.

```go
// CheckAndHandleStop checks whether the pipeline context was cancelled by a user
// stop request. If it was, onStop is called with a background context (for DB
// writes), and the function returns true. The caller must then return
// ErrPipelineStopped immediately.
func CheckAndHandleStop(ctx context.Context, onStop OnStopFunc) bool
```

`OnStopFunc` is `func(bgCtx context.Context)`. The background context is always passed because the pipeline context is already cancelled at the point of the call.

### Contract for Each Processor

When `CheckAndHandleStop` returns true the `onStop` callback **must**:

1. Write `proc_status = "stopped"` to the appropriate `kb.inputs.status` entry, preserving progress counters accumulated so far (e.g. `num_topics`, `num_metrics`).
2. Write a finish log entry to `kb.doc_proc_logs` (the processor's `finish` entry type) with a human-readable stopped reason in the `errors` field.
3. Use the provided background context for all DB writes.

After `CheckAndHandleStop` returns true, the calling function returns `ErrPipelineStopped` immediately — no further LLM calls or artifact writes.

### Call-Site Pattern

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

### Reference Implementation

`generate_topics` (`ChenWeb/server/api/doc-processing/fix-size-chunking.go`, function `handleGenerateTopicsLines`) is the reference implementation. Use it as the template when adding stop support to other processors.

## JetStream Request

JetStream request payload may have an 'operation' attribute. If present, it specifies the doc
processor to apply to the input file (or chunk files). Its value must be the ones in the 
table [Doc Processing Pipeline](#doc-processing-pipeline).

If multiple processors are specified, they must be applied in the order in which they are listed.

Important:

- The `operation` field is an explicit processor filter.
- If `operation` is omitted or empty, Doc Processor applies all configured processors in the configured order.
- If `operation` is `"chunking"`, Doc Processor runs the always-on `blocking` processor and then the `chunking` processor only.
- `generate_summary` and `generate_topics` are no longer implicitly included in `chunking`.
- `extract_provisions` is a separate processor. To run it with chunking, request both operations, for example:

```json
{
  "record_id": "123",
  "operation": ["chunking", "extract_provisions"],
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

## Workflow

- Receive an event
- Retrieve the record by event.record_id
- Read the input file (refer to "Input File" section) into a buffer, called Input File Buffer
- Apply Blocking Processor to break the input file into blocks. Save the result into Block Buffer.
- Apply all the doc processors in the same order as listed in "Doc Processing Pipeline" section

## Add New Doc Processor

Use this checklist when adding a new doc processor (mandatory or configurable).

### 1. Documentation

- Create a spec file: `KnowledgeStore/Capsules/coding-capsules/doc-processor/<name>-spec.md`
- Create an impl file: `KnowledgeStore/Capsules/coding-capsules/doc-processor/<name>-impl.md`
- Add the processor to the **Doc Processing Pipeline** table in this file with its seqno, type (`mandatory` / `configurable`), dependency, and a reference link.
- Add a status JSON subsection under **Doc Process Status** in this file.
- If configurable, add the processor name to the `required_processors` example in the **Processor Categories** section.

### 2. Implementation

- Implement the processor in `ChenWeb/server/api/doc-processing/`.
- Register it in `ChenWeb/server/cmd/doc-processor/main.go`.
- If configurable, add its name to `[doc-processing].required_processors` in `config.toml`.
- When building LLM input text from lines, call the appropriate shared helper (`blockLinesToJSON`, `markedLinesToJSON`, or `rawLinesToJSON`). See **LLM Input Format** above.

### 3. Full-Text Search Index

Every processor whose output should be full-text searchable needs a dedicated `search_artifacts` partition and indexer:

- Add a `searchArtifactXxx` string constant in `ChenWeb/server/api/doc-processing/search_indexing.go`.
- Add `ReindexXxxSearchForRecord` and `buildXxxRegistryRows` functions following the pattern of the existing artifact types in the same file.
- Call `ReindexXxxSearchForRecord` at the end of the processor's workflow (after saving output to the database).
- In `buildXxxRegistryRows`, scan any nullable column (`TEXT`, `JSONB`, etc.) into `sql.NullString` / `[]byte` — never into a plain `string`. Scanning a NULL PostgreSQL column into a plain Go `string` produces `sql: Scan error … converting NULL to string is unsupported` at runtime. Use `nullVar.String` when building the `RegistryRow` fields.

- Add a goose migration in `ChenWeb/project_migrations/` to create the partition and its indexes:

```sql
CREATE TABLE IF NOT EXISTS kb.search_artifacts_<type> PARTITION OF kb.search_artifacts
    FOR VALUES IN ('<type>');

CREATE INDEX IF NOT EXISTS idx_kb_search_artifacts_<type>_search_vector
    ON kb.search_artifacts_<type> USING GIN (search_vector);
CREATE INDEX IF NOT EXISTS idx_kb_search_artifacts_<type>_record
    ON kb.search_artifacts_<type> (input_record_id);
```

Skipping this migration causes a `pq: no partition of relation "search_artifacts" found for row` error at runtime.

### 4. Dashboard

Update `ChenWeb/web/src/lib/components/home3/doc-processor-dashboard-view.svelte`:

- **Node state mapping** — add the processor's `operation` name to the `operation → Stage` map used to render pipeline cards in the Active Pipelines section.
- **`PIPELINE_FINAL_OPS`** — add the processor so `isActiveRecord` waits for it to reach a final state before dismissing a record from the active view.
- **`ALL_PROCESSOR_IDS`** — if configurable, add it so it appears as a toggleable checkbox in the Manual Launch and Restart dialogs. Mandatory processors are always included and shown disabled; do not add them here.
- **`isActiveRecord` downstream guard** — add the processor name to the list of downstream processors checked when blocking has succeeded but leaf processors have not yet started.

Also update [14] to reflect the updated `PIPELINE_FINAL_OPS` and `ALL_PROCESSOR_IDS` lists.

## References

[1] Doc Structure Analyzer Spec: KnowledgeStore/Capsules/coding-capsules/doc-processor/structure-analyzer-static-spec.md

[2] Chunking Processor Spec: KnowledgeStore/Capsules/coding-capsules/chunking/+CAPSULE.md

[3] Extract Doc Metadata Spec: KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-metadata.md 

[4] Extract Metrics Spec: KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-metrics-spec.md

[5] Extract Terms Spec: KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-provisions-spec.md

[6] Break Documents to Blocks: KnowledgeStore/Capsules/coding-capsules/blocking-spec.md

[7] Generate Summaries: KnowledgeStore/Capsules/coding-capsules/doc-processor/generate-summary-spec.md

[8] Generate Summaries: KnowledgeStore/Capsules/coding-capsules/doc-processor/generate-topic-spec.md

[9] Generate Scene Blocks: KnowledgeStore/Capsules/coding-capsules/doc-processor/generate-scene-blocks.md

[10] Extract Product Relations: KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-products-spec.md

[11] Extract Semantic Projections: KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-semantic-projection-spec.md

[12] Extract Structured Knowledge: KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-structured-knowledge-spec.md

[13] Extract Entity & Relation: KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-entity-relation-spec.md

[14] KnowledgeStore/Capsules/coding-capsules/doc-processor/doc-processor-dashboard-spec.md