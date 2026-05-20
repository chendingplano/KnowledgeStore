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

## Doc Processing Pipeline
This service is a controller. For a received event, it applies a number of doc processors to it.
Currently, it has the following doc processors:
| Seqno | Processor Name | Type | Dependence | Explanation |
|---|---|---|---|---|
|1 | blocking | mandatory | after 1 | Blocking Processor. Refer to [6]. This processor is always executed. |
|2 | structure_analyzer | mandatory | none | Doc Structure Static Analyzer. Refer to [1] |
|3 | chunking | mandatory | after 1 | Chunking Processor. Refer to [2]|
|4 | extract_metadata | mandatory | after 1 | Extract Doc Metadata Processor. Refer to [3] for its spec |
|5 | extract_metrics | configurable | after 1 | Extract Metrics Processor. Refer to [4] for its spec |
|6 | extract_provisions | configurable | after 1 | Extract provisions. Refer to [5] |
|7 | generate_summaries | configurable | after 3 | Generate summaries. Refer to [7] |
|8 | generate_topics | configurable | after 3 | Generate topics. Refer to [8] |
|9 | generate_scene_blocks | configurable | after 3 | Generate scene blocks. Refer to [9] |
|10 | extract_products | configurable | after 1 | Extract product relations. Refer to [10] |
---

Note: the term 'after n' (such as 'after 1') means it uses the processor 'n' output as its input.
For instance, 'after 1' means it uses the Blocking Processor's output as its input.

### Processor Categories

**Mandatory processors** (`blocking`, `structure_analyzer`, `chunking`, `extract_metadata`) are always executed regardless of configuration or the `operation` field in the event payload.

**Configurable processors** (`extract_metrics`, `extract_provisions`, `generate_summaries`, `generate_topics`, `generate_scene_blocks`, `extract_products`) are executed only when they are listed in `config.toml` under `[doc-processing].required_processors`. Example:

```toml
[doc-processing]
required_processors = ["extract_metrics", "extract_provisions", "generate_summaries", "generate_topics", "generate_scene_blocks", "extract_products"]
```

If `required_processors` is absent or empty, no configurable processors run by default.

### Record Completion Criteria

A record in `kb.inputs` is considered **finished** when every processor that is expected to run for that record has reached `proc_status` = `"success"` or `"failed"`. The expected set is:

1. All four mandatory processors.
2. Every configurable processor listed in `config.toml` `[doc-processing].required_processors` at the time the event was dispatched.

If the event payload supplies an explicit `operation` list, the expected set is instead the union of mandatory processors and the intersection of the `operation` list with the configured `required_processors`.

Important:
- `generate_summaries` and `generate_topics` are separate doc processors now.
- They used to be hard coded inside `chunking`, but that coupling has been removed.
- As a result, running `chunking` alone no longer implicitly runs `generate_summaries` or `generate_topics`.
- To preserve the old behavior, include `generate_summaries` and/or `generate_topics` explicitly in the requested `operation` list, or omit `operation` so the full configured pipeline runs.

## Doc Process Status

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
When: When the Generate Topics ([8]) processor finishes.

Status JSON:
```json
{
    "record_id":"ddd",
    "file_type":"pdf | doc | docx | ppt | pptx | ...",
    "operation": "generate_topics",
    "proc_status":"success | failed",
    "num_topics":ddd,
    "input_filename": "xxx"
    "output_filename": "xxx"
    "error":"xxx",
    "start_time":"yyyymmdd hh:mm:ss",
    "ms_used":ddd,
}
```

---

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
