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

The doc processor writes a `doc_processing` status entry with `proc_status = "running"` only after a processing slot is acquired. When the pipeline exits, it replaces that entry with `proc_status = "success"` or `"failed"`.

A record is considered **finished** when all expected processors have reached `proc_status` = `"success"` or `"failed"`. The expected set is the four mandatory processors (`blocking`, `structure_analyzer`, `chunking`, `extract_metadata`) plus every processor listed in `[doc-processing].required_processors` in `config.toml`. Refer to [1] for the full completion criteria.

## Dashboard 
### Show Pipelines
- For each processing thread, show the pipeline and mark the current stage
- Fetch active pipelines by querying records with `operation = "doc_processing"` and `proc_status = "running"`, capped by `MAX_DOC_PROCESS_PIPELINES`.
- Visually distinguish **mandatory** processors (always run) from **configurable** processors (driven by `[doc-processing].required_processors` in `config.toml`). For example, use a filled badge for mandatory and an outlined badge for configurable.
- When mouse hovers over a node in a pipeline, show the node details including whether it is mandatory or configurable
- Stop a processing thread
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
