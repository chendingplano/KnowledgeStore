## Doc Processing Pipeline
- Detect changes in the staging directory
- Create a record and insert it to 'kb.inputs'. Publish a 'kb.pdf.staged' event to JetStream
- Doc processor `PDF Parser` is triggered by the event. It parses the document and publish a 'kb.pdf.parsed' event
- Doc processor `Result Converter` is triggered by the event. It converts the JSON results from the PDF Parser into a line file (refer to 'spec-line-file.md'). It publishes 'kb.line-file-generated'
- A number of doc processors are triggered by the event 'kb.line-file-generated'. Refer to "Doc Processors" section in [1]. These include (but are not limited to):
  - `extract_products` — Extract Product Relations (see [4])

The pipeline by default executes all the processors unless the events otherwise specifies.
More specifically, the 'kb.line-file-generated' event may hand-pick the proccors to execute by the 'operation'
attribute. Refer to the 'Processor Name' column of the table in the "Doc Processors" section in [1]

## Doc Processing Status
Each record in 'kb.inputs' identifies a document. 'kb.inputs.status' manages its status. Refer to [2] for 'kb.inputs' table schema and its 'kb.inputs.status'.

The sytem may process multiple, normally up to 10, concurrent doc processing threads.

### Update `doc_processing`
The doc processor upserts the following entry to its `kb.inputs.status` after a processing slot is acquired:
```json
  {
    "operation": "doc_processing",
    "start_time": "20260528 17:56:10",
    "proc_status": "running",
    "doc_processor_name": "extract_metrics"
  }
```

When the pipeline exits, it replaces that entry with `proc_status = "success"` or `"failed"`.

A record is considered **finished** when all expected processors have reached `proc_status` = `"success"`, `"failed"`, or `"stopped"`. The expected set is the four mandatory processors (`blocking`, `structure_analyzer`, `chunking`, `extract_metadata`) plus every processor listed in `[doc-processing].required_processors` in `config.toml`. Refer to [1] for the full completion criteria.

## Dashboard 
### Show Pipelines
- For each processing thread, show the pipeline and mark the current stage
- Fetch active pipelines by querying records with `operation = "doc_processing"` and `proc_status = "running"`, capped by `MAX_DOC_PROCESS_PIPELINES`.
- Visually distinguish **mandatory** processors (always run) from **configurable** processors (driven by `[doc-processing].required_processors` in `config.toml`). For example, use a filled badge for mandatory and an outlined badge for configurable.
- When mouse hovers over a node in a pipeline, show the node details including whether it is mandatory or configurable
- **Stop a processing thread** — see "Stop Pipeline" section below
- Restart a processing thread, hand-pick the processors to re-run. Default: re-run all.
- Exclude records whose `file_name` ends with `.zip` — do not monitor or display `.zip` file status

### Manual Launch Pipelines
- Search records in 'kb.inputs'
- Hand-pick the doc processors to run:
  - **Mandatory processors** (`blocking`, `structure_analyzer`, `chunking`, `extract_metadata`) are always included and cannot be deselected.
  - **Configurable processors** default to the set defined in `[doc-processing].required_processors`; individual processors can be toggled on or off before launching.
- Confirm before launching

### Failed Pipelines
- Records from 'kb.inputs' whose 'status' array contains at least one entry with 'status' = 'failed'
- The section can be expanded or collapsed; collapsed by default
- Manual refresh only; no auto-polling
- Ordered by 'create_time' descending
- Paging control; default page size: 30

## Stop Pipeline

`POST /api/v1/kb/inputs/:id/stop`

Stopping a pipeline always does two things atomically from the caller's perspective:

1. **Writes a `stop_requested` flag** into `kb.inputs.status` (an entry with `operation = "stop_requested"`, `proc_status = "pending"`). The running doc-processor polls this flag every second and cancels its pipeline context when it is detected.
2. **Immediately sets `doc_processing` to `proc_status = "stopped"`** if it is currently `"running"`. This handles the case where the doc-processor service is not running and the record is stuck in a running state.

### When the doc-processor service IS running

- The polling goroutine detects the flag within ~1 second and cancels the pipeline's context (with cause `ErrPipelineStopped`).
- Context cancellation propagates into any in-flight LLM HTTP call, aborting it immediately.
- Each processor that supports fine-grained stop (currently `generate_topics`) checks for the stop signal at the boundary of each LLM call. When detected it:
  - Writes its own `proc_status = "stopped"` entry to `kb.inputs.status` (e.g. `generate_topics: stopped`).
  - Writes a finish log entry to `kb.doc_proc_logs` with the stopped reason.
  - Returns `ErrPipelineStopped`.
- The pipeline controller (`ControlService`) detects `ErrPipelineStopped` from a processor, skips remaining processors, and the deferred cleanup writes `doc_processing: stopped` and clears the `stop_requested` flag.

### When the doc-processor service is NOT running

Step 2 above handles this case — `doc_processing` is updated to `"stopped"` synchronously by the API handler, without any doc-processor involvement.

### Restart after Stop

When a pipeline is (re)started, any stale `stop_requested` flag is cleared at the very beginning of `handleEvent`, before the polling goroutine starts. This ensures a restart always begins with a clean slate.

## Auto Sync
- The page auto syncs with the backend at a given time interval (default: 10 seconds).
- There is a "Start Sync/Stop Sync" button. When it is in the auto-sync mode, the button shows "Stop Sync". Clicking the button will stop the auto-sync and change the label to "Start Sync". The same is true for "Start Sync".
- If there are no outstanding tasks and it auto-synced five consecutive times, no status changes detected, it will stop the auto sync, change the sync button to "Start Sync".

## Implementation
Refer to [3] for its implementation.

## References
[1] KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md 

[2] KnowledgeStore/DevDocuments/Specs/table-schemas/table-kb-inputs.md

[3] KnowledgeStore/Capsules/coding-capsules/doc-processor/doc-processor-dashboard-impl.md

[4] KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-products-spec.md
