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
| Seqno | Processor Name | Dependence | Explanation |
|---|---|---|---|
|1 | blocking | after 1 | Blocking Processor. Refer to [6]. This processor is always executed. |
|2 | structure_analyzer | none | Doc Structure Static Analyzer. Refer to [1] |
|3 | chunking | after 1 | Chunking Processor. Refer to [2]|
|4 | extract_doc_metadata | after 1 | Extract Doc Metadata Processor. Refer to [3] for its spec |
|5 | extract_metrics | after 1 | Extract Metrics Processor. Refer to [4] for its spec |
|6 | extract_provisions | after 1 | Extract provisions. Refer to [5] |
|7 | generate_summary | after 3 | Generate summaries. Refer to [5] |
---

Note: the term 'after n' (such as 'after 1') means it uses the processor 'n' output as its input.
For instance, 'after 1' means it uses the Blocking Processor's output as its input.

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

We use Redis to monitor status changes for the [Doc Processing Pipeline](#doc-processing-pipeline).

| Seqno | Action | Redis Key | Redis Value |
|---|---|---|---|
|1 | structure_analyzer | 'structure_analyzing' | 'success', 'error-msg'|
|2 | chunking | 'chunking' | 'success', 'error-msg' |
|3 | extract_doc_metadata | 'extract_doc_metadata' | 'success', 'error-msg' |
|4 | extract_metrics | 'extract_metrics' | 'success', 'error_msg' |
|5 | extract_provisions | 'extract_provisions' | 'success', 'error_msg' |

When Doc Processor finishes, it generates
## Operation

If present, it specifies the doc processor to apply to the input file (or chunk files). Currently,
the valid values are: 
- 'structure_analyzer'
- 'chunking'
- 'extract_doc_metadata' 
- 'extract_metrics'
- 'extract_provisions'
If multiple processors are specified, they must be applied in the order in which they are listed.

Important:

- The `operation` field is an explicit processor filter.
- If `operation` is omitted or empty, Doc Processor applies all configured processors in the configured order.
- If `operation` is `"chunking"`, Doc Processor runs the always-on `blocking` processor and then the `chunking` processor only.
- Topic extraction and summary generation are internal steps of the `chunking` processor.
- `extract_provisions` is a separate processor. To run it with chunking, request both operations, for example:

```json
{
  "record_id": "123",
  "operation": ["chunking", "extract_provisions"],
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

[1] Doc Structure Analyzer Spec: KnowledgeStore/Capsules/coding-capsules/doc-structure-analyzer/+CAPSULE.md

[2] Chunking Processor Spec: KnowledgeStore/Capsules/coding-capsules/chunking/+CAPSULE.md

[3] Extract Doc Metadata Spec: KnowledgeStore/Capsules/coding-capsules/extract-metadata/+CAPSULE.md

[4] Extract Metrics Spec: KnowledgeStore/Capsules/coding-capsules/extract-metrics-spec.md

[5] Extract Terms Spec: KnowledgeStore/Capsules/coding-capsules/extract-provisions-spec.md

[6] Break Documents to Blocks: KnowledgeStore/Capsules/coding-capsules/blocking-spec.md

[7] Generate Summaries: KnowledgeStore/Capsules/coding-capsules/generate-summary-spec.md

[8] Generate Summaries: KnowledgeStore/Capsules/coding-capsules/generate-topics-spec.md