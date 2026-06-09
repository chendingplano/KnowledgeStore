# 1. Instrument Doc Processors with Observability

## 1.1 Status

ChenWeb observability from `observability-design.md` is implemented for the Phase 1 local baseline and already reaches the doc-processing controller.

Verification run on 2026-06-08:

```bash
cd shared/go
go test ./api/loggerutil ./api/observability ./api/EchoFactory

cd ../../ChenWeb
go test ./server/cmd/deepdoc ./server/api
docker compose -f observability/docker-compose.yml config
```

Results:

- `shared/go/api/loggerutil`, `shared/go/api/observability`, and `shared/go/api/EchoFactory` pass or compile.
- `ChenWeb/server/cmd/deepdoc` and `ChenWeb/server/api` pass or compile.
- `ChenWeb/observability/docker-compose.yml` renders successfully.

The full long-term roadmap is not complete. Phase 3 query scripts and production rollout work remain future work. Processor tracing is implemented, but processor aggregate metrics are still missing.

**Current Status**
The Phase 1 ChenWeb observability baseline is implemented and verified. Doc processors are 
already instrumented (refer to [1]) with pipeline, phase, processor, post-process indexing, 
and LLM-call spans. 
The full roadmap is not completely finished yet: query scripts, production rollout work, 
and aggregate doc-processor metrics are still pending.

## 1.2 Implemented Baseline

The following pieces from the observability design are present:

- `shared/go/api/observability/config.go` reads opt-in environment configuration.
- `shared/go/api/observability/init.go` initializes OpenTelemetry trace and metric providers.
- `shared/go/api/observability/middleware.go` creates HTTP server spans and records `http.server.duration`.
- `shared/go/api/loggerutil/jimologger.go` supports `JIMO_LOG_FORMAT=json` and context request ID reuse.
- `shared/go/api/EchoFactory/echo_factory.go` creates request loggers from Echo request context.
- `ChenWeb/server/cmd/deepdoc/main.go` initializes observability and registers request middleware.
- `ChenWeb/server/api/routes.go` preserves existing request IDs instead of replacing them mid-request.
- `ChenWeb/observability/` contains the ClickStack compose stack and OpenTelemetry collector configs for app telemetry and JSON file logs.

## 1.3 Doc Processor Instrumentation

Doc-processing traces are implemented in:

```text
ChenWeb/server/api/doc-processing/observability.go
ChenWeb/server/api/doc-processing/control.go
ChenWeb/server/api/doc-processing/doc_proc_log_store.go
```

The trace model mirrors the runtime pipeline:

```text
doc_processor.pipeline
  doc_processor.record.load
  doc_processor.input_file.resolve
  doc_processor.input_file.validate
  doc_processor.phase_a
    doc_processor.processor.<phase-a-processor>
  doc_processor.phase_b
    doc_processor.processor.<phase-b-processor>
  doc_processor.phase_c
    doc_processor.post_process_index
  doc_processor.llm_call
```

The root pipeline span is created for JetStream events handled by `ControlService.HandleJetStreamEvent`. It includes attributes for the subject, event ID, record ID, requested operations, force flag, pipeline mode, and whether Phase B concurrency is enabled.

Each processor invocation is wrapped with `startProcessorSpan`. Processor spans include:

- `doc.record_id`
- `processor.name`
- `processor.phase`
- `processor.type`
- `processor.requires_llm`
- `processor.status`
- `processor.duration_ms`

Phase C post-process indexing is also traced with `doc_processor.post_process_index`.

LLM calls are correlated through `recordDocProcLogSpan`, which emits a `doc_processor.llm_call` span for `kb.doc_proc_logs` entries that carry an LLM call ID or are typed as LLM-call entries.

## 1.4 Remaining Gaps

Processor metrics are not implemented yet. Add low-cardinality metrics after the current tracing layer settles:

- `doc_processor.completed_total`
- `doc_processor.duration`
- `doc_processor.failed_total`
- `doc_processor.stopped_total`
- `doc_processor.post_process_index.duration`
- `doc_processor.llm_call.duration`

Use only low-cardinality metric attributes:

- `processor`
- `phase`
- `status`
- `requires_llm`
- `operation`

Do not put record IDs, file names, prompt text, raw errors, raw document text, or user text on metrics.

`doc_processor.event.persist` is also still a useful future trace span. The current root pipeline span starts after the event is inserted and accepted into the async processing slot.

## 1.5 Instrumentation Rules

When adding or changing a doc processor:

1. Ensure it runs through `ControlService` so the existing phase and processor spans wrap it.
2. Return meaningful errors from `HandleEvent`; do not swallow failures that should mark the processor span as failed.
3. Use the passed `context.Context` for database, LLM, embedding, indexing, and file operations.
4. Continue writing LLM audit entries through `DocProcLogger` so `doc_processor.llm_call` spans can be correlated.
5. Log only IDs, counts, durations, statuses, model names, and error categories.
6. Never log raw document text, raw prompts, raw LLM responses, cookies, tokens, API keys, or uploaded file contents.

For nested work inside a processor, create child spans from the incoming context:

```go
ctx, span := otel.Tracer("chenweb-doc-processor").Start(ctx, "doc_processor.extract_metrics.candidate_extraction")
defer span.End()

span.SetAttributes(
    attribute.Int64("doc.record_id", recordID),
    attribute.String("processor.name", "extract_metrics"),
    attribute.String("processor.phase", "B"),
)
```

On error:

```go
span.RecordError(err)
span.SetStatus(codes.Error, err.Error())
```

For aggregate metrics:

```go
counter, _ := otel.Meter("chenweb-doc-processor").Int64Counter("doc_processor.completed_total")
counter.Add(ctx, 1,
    metric.WithAttributes(
        attribute.String("processor", "extract_metrics"),
        attribute.String("phase", "B"),
        attribute.String("status", "success"),
    ),
)
```

## 1.6 Local Workflow

Start the stack:

```bash
cd ChenWeb
mise obs-up
```

Run ChenWeb with telemetry enabled:

```bash
export OBSERVABILITY_ENABLED=true
export OTEL_SERVICE_NAME=chenweb
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:14318
export JIMO_LOG_FORMAT=json
export FILE_LOGGER=lumberjack
export LOG_FILE_DIR=/Users/cding/Apps/ChenWebLog
mise dev
```

Inspect traces and logs in HyperDX:

```text
http://localhost:8088
```

Search by:

- `service.name:chenweb`
- `request.id`
- `doc.record_id`
- `processor.name`
- `processor.status`
- `doc_processor.event_id`

# References
[1] KnowledgeStore/Capsules/coding-capsules/observability/observability-design.md
