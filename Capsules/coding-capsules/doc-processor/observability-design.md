# Doc Processor Observability — Design

## 1. Purpose

Instrument the ChenWeb doc-processing pipeline so humans and coding agents can inspect a document run end to end:

- which JetStream event started the run
- which record and input file were used
- which processors ran
- which phase each processor belonged to
- where time was spent
- which LLM calls happened
- which processors failed, stopped, or completed
- which artifacts were indexed in post-process

This design complements the existing persistent audit log in `kb.doc_proc_logs`. OpenTelemetry is for runtime investigation and correlation; `kb.doc_proc_logs` remains the domain audit trail for LLM calls and processor summaries.

---

## 2. Scope

Initial scope:

- `ChenWeb/server/cmd/doc-processor/`
- `ChenWeb/server/api/doc-processing/`
- shared OpenTelemetry wiring in `shared/go/api/observability/`
- ClickStack/HyperDX local stack under `ChenWeb/observability/`

Out of scope for the first pass:

- `tax`
- production alerting
- long-term ClickHouse retention policy
- full LLM prompt/response capture in observability

---

## 3. Query Model

After ingestion, logs, metrics, and traces are stored in ClickHouse tables and explored with HyperDX or SQL.

Agents should use:

```text
HyperDX search / trace explorer / dashboards
ClickHouse SQL
```

Do not design around LogQL, PromQL, or TraceQL. In ClickStack, the equivalent query layer is HyperDX search plus ClickHouse SQL.

`grep` is still useful for local file debugging, but it should not be the main observability workflow once telemetry is ingested.

---

## 4. Pipeline Model to Instrument

The doc processor receives a JetStream event on:

```text
kb.line-file-generated
```

Event payload:

```json
{
  "record_id": "...",
  "filename": "...",
  "operation": ["extract_metrics"],
  "force": true
}
```

The pipeline has three execution phases:

| Phase | Execution | Processors |
|---|---|---|
| Phase A | sequential | `blocking`, `structure_analyzer` / `static_analyzer`, `chunking`, `extract_metadata` |
| Phase B | concurrent | configured processors such as `extract_metrics`, `extract_provisions`, `generate_summaries`, `generate_topics`, `generate_scene_blocks`, `extract_semantic_projections`, `extract_structured_knowledge`, `extract_entity_relation`, `extract_inventory_items` |
| Phase C | post-process indexing | processors implementing `PostProcessIndexer`, currently including `MetricsProcessor` |

The trace model should mirror this structure.

---

## 5. Trace Design

### 5.0 Trace Creation Rule

Create **one OpenTelemetry trace per JetStream event**.

The root trace is created at the JetStream event handler / pipeline controller boundary. In the first implementation slice, the event is decoded, persisted to `kb.events`, accepted into the async processing slot, and then the root span is opened around the processing pipeline:

```text
JetStream event decoded
  -> persist kb.events row
  -> acquire processing slot
  -> start root span: doc_processor.pipeline
  -> load kb.inputs record
  -> resolve/validate input file
  -> run Phase A
  -> run Phase B
  -> run Phase C
```

The root span's context must be passed through the whole pipeline. For Phase B concurrent processors, every goroutine must receive the same parent context and create its own child processor span from that context. This keeps all concurrent processor work inside the same trace.

### 5.1 Root Span

Create one root span per received JetStream event:

```text
doc_processor.pipeline
```

Start it after the event is decoded and accepted for processing, before `kb.inputs` validation and processor execution. A later hardening slice should move `doc_processor.event.persist` under the same trace as a child span.

Attributes:

| Attribute | Example | Notes |
|---|---|---|
| `messaging.system` | `nats_jetstream` | low cardinality |
| `messaging.destination.name` | `kb.line-file-generated` | subject |
| `doc.record_id` | `12345` | high-cardinality but essential for traces/logs |
| `doc.filename` | `std_20039_opendata_paddleocr.txt` | traces/logs only, not metrics |
| `doc.operation.requested` | `extract_metrics,generate_topics` | comma-separated list |
| `doc.force` | `true` | event flag |
| `pipeline.mode` | `all_processors` or `selected_processors` | derived from event |
| `pipeline.concurrent` | `true` | from `RUN_DOC_PROCESSOR_CONCURRENT` |

Do not attach document content, prompt text, or raw LLM output.

### 5.2 Event Handling Spans

Add child spans:

```text
doc_processor.event.persist
doc_processor.record.load
doc_processor.input_file.resolve
doc_processor.input_file.validate
```

These spans make startup failures obvious:

- missing `record_id`
- record not found
- missing parser name
- missing result filename
- input file not found
- empty input file

Implementation status:

- `doc_processor.phase_a`, `doc_processor.phase_b`, `doc_processor.phase_c`, processor spans, and Phase C index spans are implemented.
- `doc_processor.record.load`, `doc_processor.input_file.resolve`, and `doc_processor.input_file.validate` are implemented in the controller preflight.
- `doc_processor.event.persist` is still planned. The current root trace begins after the event has been inserted and accepted into the async processing slot.

### 5.3 Phase Spans

Add one span per phase:

```text
doc_processor.phase_a
doc_processor.phase_b
doc_processor.phase_c
```

Attributes:

- `phase`: `A`, `B`, or `C`
- `processor.count`
- `processor.names`
- `doc.record_id`

Phase B should enclose the `sync.WaitGroup` fan-out. Each concurrent processor gets its own child span.

### 5.4 Processor Spans

Each processor invocation gets one span:

```text
doc_processor.processor.<processor_name>
```

Examples:

```text
doc_processor.processor.blocking
doc_processor.processor.chunking
doc_processor.processor.extract_metrics
doc_processor.processor.generate_topics
doc_processor.processor.extract_entity_relation
```

Attributes:

| Attribute | Example |
|---|---|
| `doc.record_id` | `12345` |
| `processor.name` | `extract_metrics` |
| `processor.type` | `mandatory` or `configurable` |
| `processor.phase` | `A`, `B`, or `C` |
| `processor.requires_llm` | `true` |
| `processor.status` | `success`, `failed`, or `stopped` |
| `processor.progress` | `66% (2/3)` |

On failure:

```go
span.RecordError(err)
span.SetStatus(codes.Error, err.Error())
span.SetAttributes(attribute.String("processor.status", "failed"))
```

On stop:

```go
span.SetAttributes(attribute.String("processor.status", "stopped"))
span.SetStatus(codes.Ok, "stopped by user request")
```

### 5.5 LLM Call Spans

Every LLM call should have a child span under the processor span:

```text
doc_processor.llm_call
```

Implementation status: writes to `kb.doc_proc_logs` with an `llm_call_id` emit a correlated `doc_processor.llm_call` span. This gives broad trace correlation immediately through the existing audit-log path. A future hardening slice can move the span start/end directly around each LLM client call for precise waterfall timing.

Attributes:

| Attribute | Example | Notes |
|---|---|---|
| `doc.record_id` | `12345` | trace/log only |
| `processor.name` | `extract_metrics` | low cardinality |
| `llm.activity_name` | `extract_metric_candidates` | from existing `activity_name` |
| `llm.call_id` | UUID | must match `kb.doc_proc_logs.llm_call_id` |
| `llm.pass` | `1` | if applicable |
| `llm.model` | `gpt-5-mini` | model name |
| `llm.prompt_name` | `EXTRACT_METRIC_CANDIDATES_PROMPT` | prompt identifier only |
| `llm.fallback_used` | `true` / `false` | if applicable |
| `llm.output_items` | `12` | count only |

Never attach:

- prompt body
- source document text
- raw LLM response
- extracted artifact JSON

Those belong in `kb.doc_proc_logs` only if they are already allowed by the domain audit policy.

### 5.6 Status Update Spans

Status writes to `kb.inputs.status` are important because Phase B processors update status concurrently behind an in-process per-record mutex.

Add spans:

```text
doc_processor.status.update
doc_processor.status.lock_wait
```

Attributes:

- `doc.record_id`
- `processor.name`
- `status.operation`
- `status.proc_status`
- `status.progress`
- `status.lock_scope`: `record`

If the status lock is later replaced with a database row lock, keep the same span names so historical queries stay stable.

### 5.7 Post-Process Indexing Spans

Each `PostProcessIndexer` invocation gets a span:

```text
doc_processor.post_process_index
```

Attributes:

- `doc.record_id`
- `processor.name`
- `indexer.name`
- `artifact.type`
- `artifact.count`
- `index.status`

For `MetricsProcessor`, add child spans for major indexing steps:

```text
doc_processor.index.metrics.search_artifacts
doc_processor.index.metrics.connected_artifacts
doc_processor.index.metrics.category_instances
doc_processor.index.metrics.category_path_file
doc_processor.index.metrics.hybrid_search_links
```

---

## 6. Metrics Design

Metrics should be aggregate-friendly and low-cardinality.

### 6.1 Pipeline Metrics

| Metric | Type | Unit | Attributes |
|---|---|---|---|
| `doc_processor.pipeline.started_total` | counter | `{run}` | `mode`, `concurrent` |
| `doc_processor.pipeline.completed_total` | counter | `{run}` | `status`, `mode`, `concurrent` |
| `doc_processor.pipeline.duration` | histogram | `s` | `status`, `mode`, `concurrent` |

Do not put `record_id` on metrics.

### 6.2 Processor Metrics

| Metric | Type | Unit | Attributes |
|---|---|---|---|
| `doc_processor.processor.started_total` | counter | `{run}` | `processor`, `phase`, `type` |
| `doc_processor.processor.completed_total` | counter | `{run}` | `processor`, `phase`, `type`, `status` |
| `doc_processor.processor.duration` | histogram | `s` | `processor`, `phase`, `type`, `status` |

### 6.3 LLM Metrics

| Metric | Type | Unit | Attributes |
|---|---|---|---|
| `doc_processor.llm.calls_total` | counter | `{call}` | `processor`, `activity`, `model`, `status` |
| `doc_processor.llm.duration` | histogram | `s` | `processor`, `activity`, `model`, `status` |
| `doc_processor.llm.output_items` | histogram | `{item}` | `processor`, `activity`, `model` |

Only add token metrics if token counts are reliably available:

```text
doc_processor.llm.input_tokens
doc_processor.llm.output_tokens
```

### 6.4 Indexing Metrics

| Metric | Type | Unit | Attributes |
|---|---|---|---|
| `doc_processor.index.completed_total` | counter | `{run}` | `processor`, `artifact_type`, `status` |
| `doc_processor.index.duration` | histogram | `s` | `processor`, `artifact_type`, `status` |
| `doc_processor.index.artifacts_total` | histogram | `{artifact}` | `processor`, `artifact_type` |

---

## 7. Log Design

`JimoLogger` remains the application logging API. Logs are emitted as JSON when:

```bash
JIMO_LOG_FORMAT=json
```

Logs should include:

- `record_id`
- `processor`
- `phase`
- `operation`
- `status`
- `progress`
- `llm_call_id`
- `activity_name`
- `model`
- `ms_used`
- `error`
- `loc`

Logs should not include:

- raw document lines
- raw prompt text
- raw LLM responses
- tokens
- cookies
- API keys
- session IDs

Useful log events:

```text
doc processor event received
doc processor event persisted
doc processor record loaded
doc processor input file resolved
doc processor phase started
doc processor phase completed
doc processor processor started
doc processor processor completed
doc processor llm call started
doc processor llm call completed
doc processor status updated
doc processor stop requested
doc processor post-process indexing completed
```

---

## 8. Correlation IDs

Use these IDs consistently across logs, traces, metrics, and database audit rows.

| ID | Where It Appears | Purpose |
|---|---|---|
| `trace_id` | OpenTelemetry traces/logs | connect all runtime events in one pipeline run |
| `span_id` | OpenTelemetry traces/logs | locate exact operation |
| `record_id` | traces/logs/`kb.doc_proc_logs` | connect runtime to `kb.inputs` |
| `llm_call_id` | traces/logs/`kb.doc_proc_logs` | connect LLM span to audit row |
| `processor.name` | all signals | filter by processor |
| `activity_name` | spans/logs/`kb.doc_proc_logs` | filter by LLM activity |

When writing `kb.doc_proc_logs`, include the same `llm_call_id` used on the LLM span.

Future enhancement: add `trace_id` and `span_id` columns to `kb.doc_proc_logs`, or store them inside `extra_info`, so HyperDX traces can deep-link to domain audit rows.

---

## 9. Implementation Pattern

### 9.1 Processor Wrapper

Create a small helper in `ChenWeb/server/api/doc-processing/`:

```go
func runProcessorWithSpan(
    ctx context.Context,
    processorName string,
    phase string,
    recordID int64,
    fn func(context.Context) error,
) error {
    ctx, span := otel.Tracer("chenweb").Start(ctx, "doc_processor.processor."+processorName)
    defer span.End()

    span.SetAttributes(
        attribute.Int64("doc.record_id", recordID),
        attribute.String("processor.name", processorName),
        attribute.String("processor.phase", phase),
    )

    start := time.Now()
    err := fn(ctx)
    status := "success"
    if err != nil {
        status = "failed"
        span.RecordError(err)
        span.SetStatus(codes.Error, err.Error())
    }
    span.SetAttributes(
        attribute.String("processor.status", status),
        attribute.Int64("processor.duration_ms", time.Since(start).Milliseconds()),
    )
    return err
}
```

Use the helper at the controller boundary rather than scattering top-level span creation inside every processor.

### 9.2 LLM Call Wrapper

Create a helper for LLM calls:

```go
func runLLMCallWithSpan(
    ctx context.Context,
    params LLMSpanParams,
    fn func(context.Context) error,
) error {
    ctx, span := otel.Tracer("chenweb").Start(ctx, "doc_processor.llm_call")
    defer span.End()

    span.SetAttributes(
        attribute.Int64("doc.record_id", params.RecordID),
        attribute.String("processor.name", params.Processor),
        attribute.String("llm.activity_name", params.ActivityName),
        attribute.String("llm.call_id", params.CallID),
        attribute.String("llm.model", params.Model),
        attribute.String("llm.prompt_name", params.PromptName),
    )

    err := fn(ctx)
    if err != nil {
        span.RecordError(err)
        span.SetStatus(codes.Error, err.Error())
    }
    return err
}
```

This helper should wrap the existing places where processors write `kb.doc_proc_logs` entries for LLM calls.

### 9.3 Status Update Wrapper

Wrap status update code with:

```text
doc_processor.status.update
```

This should be especially useful in concurrent Phase B runs, where status updates are serialized by the per-record mutex.

---

## 10. Agent Queries

Create query scripts under:

```text
ChenWeb/observability/queries/
```

Recommended first queries:

| Query | Purpose |
|---|---|
| `doc-processor-recent-errors.sql` | recent failed/stopped processors |
| `doc-processor-run-by-record.sql` | all spans/logs for a `record_id` |
| `doc-processor-slow-processors.sql` | slowest processor spans |
| `doc-processor-llm-latency.sql` | LLM latency by processor/model/activity |
| `doc-processor-indexing-failures.sql` | Phase C indexing failures |
| `doc-processor-status-updates.sql` | status transitions for a record |

Agent-facing commands should eventually look like:

```bash
mise obs-doc-run -- --record-id 12345
mise obs-doc-errors -- --since 1h
mise obs-doc-slow-processors -- --threshold-ms 30000
mise obs-doc-llm -- --record-id 12345
```

---

## 11. Rollout Plan

### Phase 1 — Controller-Level Tracing

Instrument:

- JetStream event receive/decode
- event persistence to `kb.events`
- record load
- input file resolution/validation
- Phase A span
- Phase B span
- Phase C span
- one child span per processor invocation

### Phase 2 — LLM Call Tracing

Instrument LLM calls in:

- `extract_metadata`
- `extract_metrics`
- `extract_provisions`
- `generate_summaries`
- `generate_topics`
- `generate_scene_blocks`
- `extract_semantic_projections`
- `extract_structured_knowledge`
- `extract_entity_relation`
- `extract_inventory_items`

Each LLM span must carry the same `llm_call_id` that is written to `kb.doc_proc_logs`.

### Phase 3 — Metrics

Add pipeline, processor, LLM, and indexing metrics.

Keep attributes low-cardinality. Do not use `record_id` on metrics.

### Phase 4 — Query Scripts

Add SQL/API scripts for the agent debugging loop.

### Phase 5 — Audit Row Correlation

Add `trace_id` and `span_id` to `kb.doc_proc_logs` either as columns or inside `extra_info`.

---

## 12. Verification

Manual verification:

1. Start ClickStack:

```bash
cd ChenWeb
mise obs-up
```

2. Start the doc processor with observability enabled:

```bash
export OBSERVABILITY_ENABLED=true
export OTEL_SERVICE_NAME=chenweb-doc-processor
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
export JIMO_LOG_FORMAT=json
export FILE_LOGGER=lumberjack
export LOG_FILE_DIR=/Users/cding/Apps/ChenWebLog
mise run-all-tests
```

Or run a targeted event through JetStream / CLI once available.

3. Open HyperDX:

```text
http://localhost:8088
```

4. Verify:

- a root `doc_processor.pipeline` trace exists
- each phase appears as a child span
- each invoked processor appears as a child span
- failed processors record errors
- stopped processors record `processor.status=stopped`
- LLM call spans include `llm_call_id`
- `record_id` can find all relevant logs/traces

---

## 13. Safety Rules

Observability may contain:

- record IDs
- processor names
- phase names
- operation names
- status/progress
- durations
- counts
- model names
- prompt identifiers
- error categories

Observability must not contain:

- raw document text
- raw prompts
- raw LLM responses
- uploaded file contents
- API keys
- tokens
- cookies
- session IDs

When in doubt, put sensitive domain details in the existing audited database tables only if allowed by their spec, not in OpenTelemetry attributes.

## 14. Implementations
Refer to KnowledgeStore/Capsules/coding-capsules/doc-processor/observability-impl.md

---

## 15. References

- `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md`
- `KnowledgeStore/Capsules/coding-capsules/observability/observability-design.md`
- `ChenWeb/server/cmd/doc-processor/main.go`
- `ChenWeb/server/api/doc-processing/control.go`
- `ChenWeb/server/api/doc-processing/status_lock.go`
- `ChenWeb/server/api/doc-processing/stop.go`
- `ChenWeb/observability/README.md`
- `KnowledgeStore/Capsules/coding-capsules/doc-processor/observability-impl.md`
