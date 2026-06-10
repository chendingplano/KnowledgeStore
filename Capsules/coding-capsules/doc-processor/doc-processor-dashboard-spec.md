## Doc Processing Pipeline
- Detect changes in the staging directory
- Create a record and insert it to 'kb.inputs'. Publish a 'kb.pdf.staged' event to JetStream
- Doc processor `PDF Parser` is triggered by the event. It parses the document and publish a 'kb.pdf.parsed' event
- Doc processor `Result Converter` is triggered by the event. It converts the JSON results from the PDF Parser into a line file (refer to 'KnowledgeStore/Capsules/coding-capsules/input-management/spec-line-file.md'). It publishes 'kb.line-file-generated'
- A number of doc processors are triggered by the event 'kb.line-file-generated'. Refer to "Doc Processors" section in [1]. These include (but are not limited to):
  - `extract_products` — Extract Product Relations (see [4])

The pipeline by default executes all the processors unless the events otherwise specifies.
More specifically, the 'kb.line-file-generated' event may hand-pick the proccors to execute by the 'operation'
attribute. Refer to the 'Processor Name' column of the table in the "Doc Processors" section in [1]

## Doc Processing Status
Each record in 'kb.inputs' identifies a document. 'kb.inputs.status' manages its status. Refer to [2] for 'kb.inputs' table schema and its 'kb.inputs.status'.

The system may process multiple, normally up to 10, concurrent doc processing threads.

### Update `doc_processing`
The pipeline coordinator upserts the following entry to `kb.inputs.status` when the pipeline starts and updates it as each Phase B processor begins:
```json
  {
    "operation": "doc_processing",
    "start_time": "20260528 17:56:10",
    "proc_status": "running",
    "doc_processor_name": "extract_metrics"
  }
```

`doc_processor_name` reflects the most recently started processor. During Phase B concurrent execution, multiple processors start nearly simultaneously, so `doc_processor_name` may point to any one of the concurrent processors — not necessarily all of them or the one currently taking the longest.

When the pipeline fully exits (after Phase C post-process indexing completes), a deferred function replaces the entry with `proc_status = "success"`, `"failed"`, or `"stopped"` and clears `doc_processor_name`.

A record is considered **finished** when all expected processors have reached `proc_status` = `"success"`, `"failed"`, or `"stopped"`. The expected set is the four mandatory processors (`blocking`, `structure_analyzer`, `chunking`, `extract_metadata`) plus every processor listed in `[doc-processing].required_processors` in `config.toml`. Refer to [1] for the full completion criteria.

### Individual Processor Status Entries
Each processor writes its own entry directly into `kb.inputs.status` using its operation name as the key (e.g. `extract_entity_relation`, `generate_summaries`). These entries are independent of `doc_processing`. A processor writes its entry:
- Once at the start (with `proc_status = "in_progress"` and a progress marker), for processors that report per-chunk progress.
- Once on completion (with `proc_status = "success"` or `"failed"`), replacing the in-progress entry.

**Status entry priority for display**: when both a direct processor entry and a `doc_processing` entry (with matching `doc_processor_name`) exist for the same processor, the **direct entry takes precedence**. The `doc_processing` entry is used only as a fallback when no direct entry exists. This handles the case where a crash leaves `doc_processing` stale while the processor's own final entry is already written correctly.

## Dashboard 
### Show Pipelines
- For each processing thread, show the pipeline and mark the current stage(s)
- Fetch active pipelines by querying records with `operation = "doc_processing"` and `proc_status = "running"`, capped by `MAX_DOC_PROCESS_PIPELINES`.
- Visually distinguish **mandatory** processors (always run) from **configurable** processors (driven by `[doc-processing].required_processors` in `config.toml`). For example, use a filled badge for mandatory and an outlined badge for configurable.
- When mouse hovers over a node in a pipeline, show the node details including whether it is mandatory or configurable
- **Stop a processing thread** — see "Stop Pipeline" section below
- Restart a processing thread, hand-pick the processors to re-run. Default: re-run all.
- Exclude records whose `file_name` ends with `.zip` — do not monitor or display `.zip` file status

#### Pipeline Phases

The pipeline runs in three phases. The dashboard reflects Phases A and B visually:

- **Phase A — Sequential** (`blocking → structure_analyzer → chunking → extract_metadata`): render as a horizontal chain. Exactly one node is active at a time; highlight the single node whose `proc_status = "running"`.
- **Phase B — Concurrent** (all configurable processors): render as a parallel fan-out below/after Phase A. During Phase B, **multiple nodes may carry `proc_status = "running"` simultaneously**; highlight all of them at once.
- **Phase C — Post-process indexing** (internal): runs after all Phase B processors complete. Cross-artifact indexing (e.g. metric search index) happens here. Phase C is fully internal — no per-processor status entries are written. The pipeline's `doc_processing` entry remains `"running"` throughout Phase C and is only finalized to `"success"/"failed"/"stopped"` once Phase C completes. **A process crash during Phase C leaves `doc_processing` permanently at `"running"` even though all individual processor entries are `"success"`** — see "Stuck Pipeline Recovery" below.

#### Determining Active Nodes

For a given record, the set of active nodes is determined from `kb.inputs.status`:

- Collect all entries where `proc_status = "running"`.
- If the running entry is one of the four mandatory processors, only that single node is highlighted (Phase A is in progress).
- If one or more running entries are configurable processors, Phase B is in progress — highlight every configurable processor whose entry shows `proc_status = "running"` concurrently.
- A configurable processor node that has already reached `"success"`, `"failed"`, or `"stopped"` is shown in its terminal state even while sibling processors are still running.

#### Node State Rendering

Each pipeline node reflects its `proc_status` value:

| `proc_status`  | Visual state            |
|----------------|-------------------------|
| *(no entry)*   | Pending / not started   |
| `"running"`    | Active / highlighted    |
| `"success"`    | Complete                |
| `"failed"`     | Error                   |
| `"stopped"`    | Stopped                 |

During Phase B, the dashboard may show several configurable nodes in `"running"` state simultaneously alongside others already in a terminal state — this is the expected concurrent behavior, not an error.

**Display priority**: the UI resolves each stage's status by first looking for a direct processor entry (e.g. `operation = "extract_entity_relation"`). If found, that entry's `proc_status` is authoritative regardless of what `doc_processing.doc_processor_name` says. The `doc_processing` entry is used only when no direct entry exists for the stage (i.e. the processor has not yet started or not yet written its own entry).

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

## Stuck Pipeline Recovery

### Condition
A pipeline is **stuck** when:
1. `doc_processing.proc_status = "running"` with a non-empty `doc_processor_name`, AND
2. Every other entry in `kb.inputs.status` (excluding `stop_requested`) has a final `proc_status` (`"success"`, `"fail"`, `"failed"`, or `"stopped"`).

This happens when the process crashes during Phase C post-process indexing — all Phase B processors have completed and written their own success entries, but the deferred finalization that updates `doc_processing` never ran.

**Known incident (2026-06-09):** Record 246 — process crashed at 09:16:06 immediately after Phase C began (entity-relation post-process chunks were loaded but no further progress logged). All 8 processors had finished. `doc_processing` was left at `running, doc_processor_name: extract_entity_relation` indefinitely.

### Auto-Heal on Query
`GET /api/v1/kb/inputs?operation=doc_processing&proc_status=running` (the active-pipeline poll) auto-heals stuck records before returning results:

1. For each record returned by the database query, `FixStuckPipeline` is called.
2. `isStuckPipeline` inspects the full status JSON array:
   - Finds the `doc_processing` entry; verifies `proc_status = "running"` and `doc_processor_name` is non-empty.
   - Iterates every other entry (skipping `stop_requested`); checks that all have a final effective `proc_status` (reading `proc_status`, then `proc-status`, then `status` in that order).
   - Returns true only when both conditions hold.
3. If stuck: calls `appendPipelineStatus("success")` and persists to `kb.inputs` atomically. The record is then excluded from the response.
4. If not stuck (pipeline genuinely running): record is returned unchanged.

The total count returned by the API is decremented for each auto-healed record.

### UI Display During Stuck State (before auto-heal)
When a stuck record is displayed before the auto-heal fires:
- The `doc_processing` entry (e.g. `doc_processor_name: extract_entity_relation`) would otherwise shadow the direct `extract_entity_relation: success` entry in the stage status calculation.
- Fix: the UI always prefers direct processor entries over the `doc_processing` umbrella entry. A stage shows as `success` (green) if its direct entry says `proc_status: "success"`, even if `doc_processing` still names that processor as running.

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
