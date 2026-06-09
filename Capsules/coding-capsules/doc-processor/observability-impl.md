# Doc Processor Observability Implementation

## Summary

The ChenWeb doc processor now has OpenTelemetry-based observability wired through the shared `observability` package and the ClickStack/HyperDX local stack design.

The implementation is intentionally local-first and opt-in:

- Observability is disabled by default.
- The doc processor can run without ClickHouse, HyperDX, or ClickStack when observability is disabled.
- When observability is enabled, telemetry is exported through OTLP HTTP, normally to ClickStack at `http://localhost:4318`.

This document records what has been implemented, how it works, what runtime dependencies are required, and what remains.

## Runtime Requirement

The system does **not** require ClickHouse or HyperDX to run in the default configuration.

By default:

```text
OBSERVABILITY_ENABLED unset
OTEL_ENABLED unset
```

In that state, `observability.Init(...)` returns a no-op shutdown function and no OpenTelemetry exporters are created.

ClickStack is required only when telemetry export is enabled:

```bash
export OBSERVABILITY_ENABLED=true
# or
export OTEL_ENABLED=true
```

When enabled and no endpoint is set, the default endpoint is:

```text
http://localhost:4318
```

That endpoint is expected to be served by the local ClickStack/HyperDX stack. If observability is enabled but the collector is unavailable, the app may still start, but trace/metric export will fail or be dropped by the OpenTelemetry exporter. For useful observability, start the local stack first.

## Local Stack

The local stack lives under:

```text
ChenWeb/observability/
```

It includes:

- ClickStack all-in-one container
- OTLP HTTP/gRPC endpoints
- HyperDX UI
- OpenTelemetry Collector file-log tailer for ChenWeb logs

Useful tasks:

```bash
cd ChenWeb
mise run obs-up
mise run obs-down
mise run obs-logs
mise run obs-ui
```

Expected local endpoints:

| Purpose | Endpoint |
|---|---|
| OTLP HTTP | `http://localhost:4318` |
| OTLP gRPC | `localhost:4317` |
| HyperDX UI | `http://localhost:8088` |
| ClickHouse HTTP | `http://localhost:18123` |
| ClickHouse native | `localhost:19000` |

## Shared Observability Package

Package:

```text
shared/go/api/observability/
```

Implemented files:

| File | Purpose |
|---|---|
| `config.go` | Reads env config and ClickStack defaults |
| `init.go` | Initializes trace and metric providers |
| `middleware.go` | Echo HTTP middleware for request spans and duration metrics |

Config environment variables:

| Variable | Purpose |
|---|---|
| `OBSERVABILITY_ENABLED` | Enables observability when true-ish |
| `OTEL_ENABLED` | Alternate enable flag |
| `OTEL_SERVICE_NAME` | Overrides service name |
| `APP_ENV` / `ENV` | Sets deployment environment |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OTLP endpoint |
| `OTEL_EXPORTER_OTLP_HEADERS` | Comma-separated `key=value` headers |

The package installs:

- OTLP HTTP trace exporter
- OTLP HTTP metric exporter
- OpenTelemetry tracer provider
- OpenTelemetry meter provider
- W3C Trace Context propagator
- W3C Baggage propagator

Resource attributes currently include:

```text
service.name
deployment.environment.name
```

## Doc Processor Wiring

The doc processor entrypoint initializes observability in:

```text
ChenWeb/server/cmd/doc-processor/main.go
```

Service name:

```text
chenweb-doc-processor
```

Startup behavior:

1. Load `.env`.
2. Create logger.
3. Load shared config.
4. Build observability config from env.
5. Initialize OpenTelemetry if enabled.
6. Defer graceful shutdown with a 5 second timeout.
7. Continue normal doc-processor startup.

## Trace Model

The implementation creates one root processing trace per valid JetStream event.

Root span:

```text
doc_processor.pipeline
```

Root span attributes include:

| Attribute | Meaning |
|---|---|
| `messaging.system` | `nats_jetstream` |
| `messaging.destination.name` | JetStream subject |
| `doc_processor.event_id` | local event id |
| `doc.record_id` | `kb.inputs.id` |
| `doc.filename` | requested filename |
| `doc.operation.requested` | requested operations |
| `doc.force` | force flag |
| `pipeline.mode` | all processors or selected processors |
| `pipeline.concurrent` | whether Phase B fan-out is enabled |
| `pipeline.status` | success or failed |

Current root-span timing:

```text
JetStream event received
  -> persist kb.events received row
  -> acquire async processing slot
  -> parse event
  -> start doc_processor.pipeline
  -> run controller preflight
  -> run Phase A
  -> run Phase B
  -> run Phase C
  -> mark kb.events consumed
  -> end doc_processor.pipeline
```

Important note: `doc_processor.event.persist` is not implemented yet, so the current root trace begins after the event has been inserted and accepted into the async processing slot.

## Startup / Preflight Spans

Implemented in:

```text
ChenWeb/server/api/doc-processing/control.go
```

Preflight child spans:

```text
doc_processor.record.load
doc_processor.input_file.resolve
doc_processor.input_file.validate
```

These spans expose common startup failures:

- `kb.inputs` record not found
- missing parser name
- missing result filename
- input path resolution failure
- input file not found
- input file stat failure
- empty input file

Successful input validation records:

```text
doc.input_size_bytes
doc.input_path
doc.parser_name
doc.result_filename
```

## Phase Spans

Implemented in:

```text
ChenWeb/server/api/doc-processing/control.go
ChenWeb/server/api/doc-processing/observability.go
```

Phase spans:

```text
doc_processor.phase_a
doc_processor.phase_b
doc_processor.phase_c
```

Phase A:

- sequential
- mandatory setup processors
- includes processors such as static analyzer, chunking, and metadata extraction

Phase B:

- configurable processors
- concurrent by default
- all goroutines receive the same Phase B parent context
- each processor creates its own child span

Phase C:

- post-process indexing
- wraps processors implementing `PostProcessIndexer`

## Processor Spans

Each processor invocation emits:

```text
doc_processor.processor.<processor_name>
```

Examples:

```text
doc_processor.processor.chunking
doc_processor.processor.extract_metrics
doc_processor.processor.generate_topics
doc_processor.processor.extract_entity_relation
```

Processor span attributes include:

| Attribute | Meaning |
|---|---|
| `doc.record_id` | document record id |
| `processor.name` | canonical processor name |
| `processor.phase` | `A`, `B`, or `C` |
| `processor.type` | mandatory, configurable, or post-process |
| `processor.requires_llm` | whether the processor normally uses LLMs |
| `processor.status` | success, failed, or stopped |
| `processor.duration_ms` | elapsed processor time |

Errors are recorded with:

```go
span.RecordError(err)
span.SetStatus(codes.Error, err.Error())
```

## LLM Correlation Spans

Implemented in:

```text
ChenWeb/server/api/doc-processing/doc_proc_log_store.go
ChenWeb/server/api/doc-processing/observability.go
```

Every write to `kb.doc_proc_logs` that includes an `llm_call_id` emits:

```text
doc_processor.llm_call
```

The LLM span carries:

| Attribute | Meaning |
|---|---|
| `doc.record_id` | document record id |
| `doc_proc.name` | processor / operation name |
| `doc_proc.entry_type` | doc proc log entry type |
| `llm.call_id` | same id stored in `kb.doc_proc_logs.llm_call_id` |
| `llm.prompt_name` | prompt identifier |
| `llm.model_names` | model names |
| `llm.pass` | pass number, if present |
| `llm.activity_name` | activity name, if present |
| `llm.duration_ms` | duration from audit log, if present |
| `llm.status` | success or failed |
| `doc_proc.log_loc` | log call-site location |

This gives immediate trace-to-audit-log correlation.

Limitation: these spans are emitted when the audit log row is written. They do not yet wrap the actual LLM network call. The next hardening slice should start the span immediately before the LLM client call and end it immediately after the client returns.

## HTTP Server Observability

Although this document focuses on the doc processor, the ChenWeb HTTP server also initializes the shared observability package in:

```text
ChenWeb/server/cmd/deepdoc/main.go
```

It installs Echo request middleware:

```text
observability.RequestMiddleware(obsCfg)
```

The middleware creates request spans and request duration metrics for incoming HTTP traffic.

## Logs

The shared logger now supports JSON output:

```bash
export JIMO_LOG_FORMAT=json
```

The local ClickStack setup includes an OpenTelemetry Collector file-log tailer for ChenWeb logs. This is intended to ingest file logs into ClickStack so HyperDX can correlate logs with traces.

Current limitation: automatic `trace_id` / `span_id` injection into every log line is not complete yet. Some correlation exists through explicit attributes such as `record_id`, `event_id`, and `llm_call_id`; automatic trace log correlation remains an observability package task.

## Query Model

Because this implementation uses ClickStack, the main query tools are:

- HyperDX search
- HyperDX trace explorer
- ClickHouse SQL

This stack does not use LogQL, PromQL, or TraceQL directly. The functional equivalents are ClickHouse tables and HyperDX query/search UI.

Useful search pivots:

| Pivot | Use |
|---|---|
| `doc.record_id` | find all telemetry for one document |
| `doc_processor.event_id` | find one JetStream processing run |
| `processor.name` | compare processor behavior |
| `llm.call_id` | connect trace span to `kb.doc_proc_logs` |
| `pipeline.status` | find failed runs |
| `processor.status` | find failed/stopped processors |

## Verification Performed

Focused checks passed:

```bash
cd ChenWeb
go test ./server/cmd/doc-processor
go test ./server/api/doc-processing -run 'TestControlService|TestRunDocProcessorConcurrent|TestMaxDocProcessPipelines|TestFilter|TestExpand|TestDocProcLoggerLogExtractMetrics'
```

Previously verified shared observability checks:

```bash
cd shared/go
go test ./api/loggerutil ./api/observability ./api/EchoFactory
```

Previously verified ChenWeb server checks:

```bash
cd ChenWeb
go test ./server/cmd/deepdoc ./server/api
docker compose -f observability/docker-compose.yml config
```

Known unrelated package failures:

```bash
cd ChenWeb
go test ./server/api/doc-processing
```

This full package test currently fails on category logging expectations in:

```text
artifact_category_wiring_test.go
```

The observed failures expect one debug print per category LLM call but receive start/end log pairs.

## Remaining Work

High-value next items:

1. Add exact LLM network-call spans around each LLM client invocation.
2. Add `doc_processor.event.persist` under the same root trace.
3. Propagate trace context through JetStream message headers from publisher to consumer.
4. Inject `trace_id` and `span_id` into JSON logs automatically.
5. Add doc-processor metrics:
   - pipeline duration
   - processor duration
   - LLM duration
   - processor failures
   - stopped runs
   - active pipeline slots / saturation
6. Add a smoke script that starts ClickStack, submits one sample JetStream event, and verifies spans/logs are queryable.
7. Add query examples for HyperDX and ClickHouse.

## Practical Startup Modes

Run without observability:

```bash
cd ChenWeb
unset OBSERVABILITY_ENABLED
unset OTEL_ENABLED
mise run <doc-processor-task>
```

Run with local ClickStack:

```bash
cd ChenWeb
mise run obs-up

export OBSERVABILITY_ENABLED=true
export OTEL_SERVICE_NAME=chenweb-doc-processor
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
export JIMO_LOG_FORMAT=json

mise run <doc-processor-task>
```

Then open:

```text
http://localhost:8088
```

## Bottom Line

The doc processor does not require ClickHouse or HyperDX unless observability is enabled. With observability disabled, the new code path is effectively no-op for OpenTelemetry export. With observability enabled, ClickStack/HyperDX provides the local telemetry backend for traces, metrics, and logs.
