# ChenWeb Observability — Design

## 1. Purpose

Build an observability stack that makes ChenWeb runtime behavior directly inspectable by humans and coding agents.

The design is inspired by OpenAI's harness-engineering pattern: the application should expose logs, metrics, and traces to a local, queryable stack so an agent can reproduce a workload, inspect runtime evidence, implement a fix, restart, and validate again.

Initial scope is **ChenWeb only**. The `tax` project is production-facing and should not be changed until the ChenWeb implementation proves the pattern.

---

## 2. Decision

Use **OpenTelemetry + ClickStack/HyperDX + ClickHouse** for ChenWeb observability.

### 2.1 Why ClickStack

ClickStack is the preferred local and future production direction because:

- It is OpenTelemetry-native.
- It stores high-volume telemetry in ClickHouse.
- HyperDX provides a useful UI for logs, traces, metrics, and correlation.
- ClickHouse can later support both observability and broader OLAP/application analytics.
- Another external project already uses HyperDX, so the operational model is familiar.

### 2.2 Why Not LGTM First

Loki/Prometheus/Tempo/Grafana is a strong default stack, but it would introduce a second analytics storage direction. Since the long-term plan includes ClickHouse for OLAP, using ClickStack avoids splitting observability data from analytical data too early.

---

## 3. Architecture

```text
ChenWeb Go server
ChenWeb workers / processors
        |
        | OTLP traces
        | OTLP metrics
        v
ClickStack OTLP endpoint
        |
        v
ClickHouse
        |
        v
HyperDX UI
```

Logs use a local filelog collector:

```text
JimoLogger JSON logs
        |
        v
LOG_FILE_DIR/app.log
        |
        v
OpenTelemetry Collector filelog receiver
        |
        v
ClickStack OTLP endpoint
        |
        v
ClickHouse / HyperDX
```

This split keeps the first implementation simple:

- traces and metrics are emitted directly by the Go process through OTLP HTTP
- logs continue using the existing `JimoLogger` file output path
- JSON log mode is opt-in with `JIMO_LOG_FORMAT=json`

---

## 4. Components

### 4.1 Shared Observability Package

Path:

```text
shared/go/api/observability/
```

Responsibilities:

- Parse observability environment variables.
- Initialize OpenTelemetry trace and metric providers.
- Export telemetry to a ClickStack-compatible OTLP HTTP endpoint.
- Provide Echo middleware for request correlation, HTTP spans, and request duration metrics.

Important files:

```text
shared/go/api/observability/config.go
shared/go/api/observability/init.go
shared/go/api/observability/middleware.go
```

### 4.2 Logger Correlation

Path:

```text
shared/go/api/loggerutil/jimologger.go
```

The existing `JimoLogger` abstraction remains the public logging API. This avoids rewriting call sites across ChenWeb, shared packages, and future consumers.

New behavior:

- `CreateLoggerFromContext(ctx, loc)` creates a logger that reuses the request ID from context.
- `JIMO_LOG_FORMAT=json` switches file/stdio logging to JSON mode.
- Default dev logging remains unchanged unless JSON mode is explicitly enabled.

### 4.3 Request Context Integration

Path:

```text
shared/go/api/EchoFactory/echo_factory.go
```

`EchoFactory.NewFromEcho` now uses the context-aware logger constructor. Handlers that call `rc.GetLogger()` can inherit request correlation without changing every handler.

### 4.4 ChenWeb Wiring

Paths:

```text
ChenWeb/server/cmd/deepdoc/main.go
ChenWeb/server/api/routes.go
```

ChenWeb startup:

- builds config with `observability.ConfigFromEnv("chenweb")`
- initializes OpenTelemetry only when enabled
- registers `observability.RequestMiddleware`
- logs whether observability is enabled or disabled

ChenWeb router:

- preserves an existing request ID from middleware/context
- falls back to generating one only when needed
- avoids replacing the request ID mid-request

### 4.5 Local ClickStack Stack

Path:

```text
ChenWeb/observability/
```

Files:

```text
docker-compose.yml
otel-filelog-collector.yaml
README.md
queries/
```

Local ports:

| Purpose | Local URL / Port |
|---|---|
| HyperDX UI | `http://localhost:8088` |
| OTLP HTTP | `http://localhost:14318` |
| OTLP gRPC | `localhost:14317` |
| ClickHouse HTTP | `http://localhost:18123` |
| ClickHouse native | `localhost:19000` |

HyperDX is mapped to `8088` because ChenWeb already uses `8080`.

---

## 5. Environment Variables

Minimum local configuration:

```bash
export OBSERVABILITY_ENABLED=true
export OTEL_SERVICE_NAME=chenweb
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:14318
export JIMO_LOG_FORMAT=json
export FILE_LOGGER=lumberjack
export LOG_FILE_DIR=/Users/cding/Apps/ChenWebLog
```

If ClickStack requires an ingestion key:

```bash
export CLICKSTACK_API_KEY=...
export OTEL_EXPORTER_OTLP_HEADERS="authorization=${CLICKSTACK_API_KEY}"
```

Defaults:

- observability is disabled unless `OBSERVABILITY_ENABLED=true` or `OTEL_ENABLED=true`
- service name defaults to `chenweb` when called from ChenWeb
- environment defaults to `APP_ENV`, then `ENV`, then `local`
- local ClickStack OTLP endpoint defaults to `http://localhost:14318` when observability is enabled and no endpoint is provided

---

## 6. Local Workflow

Start the local stack:

```bash
cd ChenWeb
mise obs-up
```

Print local URLs:

```bash
mise obs-ui
```

Run ChenWeb with observability enabled:

```bash
export OBSERVABILITY_ENABLED=true
export OTEL_SERVICE_NAME=chenweb
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:14318
export JIMO_LOG_FORMAT=json
export FILE_LOGGER=lumberjack
export LOG_FILE_DIR=/Users/cding/Apps/ChenWebLog
mise dev
```

Open:

```text
http://localhost:8088
```

Stop the stack:

```bash
mise obs-down
```

---

## 7. Signals

### 7.1 Traces

Each HTTP request creates a server span with attributes:

- `service.name`
- `deployment.environment.name`
- `http.request.method`
- `url.path`
- `http.route`
- `http.response.status_code`
- `request.id`

Additional spans should be added around:

- database queries
- LLM calls
- document processing phases
- file parsing
- embedding/indexing
- NATS/JetStream operations
- external HTTP calls

### 7.1.1 How to Instrument OpenTelemetry

Use the shared observability package to initialize the OpenTelemetry SDK once at process startup. ChenWeb already does this in:

```text
ChenWeb/server/cmd/deepdoc/main.go
```

The startup pattern is:

```go
obsCfg := observability.ConfigFromEnv("chenweb")
obsShutdown, err := observability.Init(ctx, obsCfg)
if err != nil {
    logger.Error("failed to initialize observability", "error", err)
    os.Exit(1)
}
defer obsShutdown(context.Background())

e.Use(observability.RequestMiddleware(obsCfg))
```

For normal HTTP handlers, the request middleware creates the top-level server span automatically. Handler code should use the request context when creating child spans:

```go
ctx, span := otel.Tracer("chenweb").Start(rc.Context(), "doc_processor.extract_metrics")
defer span.End()

span.SetAttributes(
    attribute.String("processor", "extract_metrics"),
    attribute.Int64("record_id", recordID),
    attribute.String("phase", "candidate_extraction"),
)
```

When an operation fails, record the error on the current span:

```go
if err != nil {
    span.RecordError(err)
    span.SetStatus(codes.Error, err.Error())
    return err
}
```

For timed operations, prefer a span even if a metric is also emitted. A span explains where time went; a metric shows aggregate behavior.

Example for a document processor phase:

```go
func runExtractMetrics(rc ApiTypes.RequestContext, recordID int64) error {
    ctx, span := otel.Tracer("chenweb").Start(rc.Context(), "doc_processor.extract_metrics")
    defer span.End()

    span.SetAttributes(
        attribute.Int64("record_id", recordID),
        attribute.String("processor", "extract_metrics"),
    )

    if err := doExtractMetrics(ctx, recordID); err != nil {
        span.RecordError(err)
        span.SetStatus(codes.Error, err.Error())
        return err
    }
    return nil
}
```

For background workers that do not have an Echo request context, create or reuse a context explicitly:

```go
ctx, span := otel.Tracer("chenweb").Start(context.Background(), "worker.docgen.requeue_stalled_jobs")
defer span.End()
```

Metrics should be used for aggregate values that will be charted or alerted on:

```go
meter := otel.Meter("chenweb")
counter, _ := meter.Int64Counter("doc_processor.completed_total")
counter.Add(ctx, 1,
    metric.WithAttributes(
        attribute.String("processor", "extract_metrics"),
        attribute.String("status", "success"),
    ),
)
```

Metric attributes must stay low-cardinality. Do not put `record_id`, file names, raw errors, prompts, or user text on metrics.

### 7.2 Metrics

Initial metric:

```text
http.server.duration
```

Unit:

```text
s
```

Future metrics:

- server startup duration
- request count by route/status
- document processor duration
- LLM call duration
- LLM token usage
- embedding generation duration
- queue depth
- worker success/failure count

### 7.3 Logs

Logs are emitted through `JimoLogger`.

For observability mode:

```bash
JIMO_LOG_FORMAT=json
```

Logs should prefer:

- request IDs
- trace IDs when available
- record IDs
- processor names
- operation names
- durations
- counts
- statuses
- error categories

Logs must avoid:

- raw document text
- raw prompts
- LLM prompt/response bodies unless explicitly redacted
- emails unless necessary and safe
- cookies
- tokens
- API keys
- session IDs
- uploaded file contents

---

## 8. Data Model Direction

ClickHouse should eventually separate observability data from application analytics:

```text
observability_raw
  otel_logs
  otel_traces
  otel_metrics

chenweb_analytics
  document_processing_facts
  user_journey_facts
  llm_call_facts

marts
  daily_usage
  processing_latency
  error_rates
```

Retention should be explicit:

| Data | Suggested Retention |
|---|---|
| debug logs | 7-14 days |
| info/error logs | 30 days |
| raw traces | 14-30 days |
| raw metrics | 30-90 days |
| rollups | 90+ days |
| business analytics facts | long-lived |

---

## 9. Agent Debugging Loop

Target workflow:

```text
1. Start ClickStack.
2. Start ChenWeb with observability enabled.
3. Run a UI/API/document-processing workload.
4. Query logs, traces, and metrics.
5. Identify slow/erroring path.
6. Implement fix.
7. Restart app.
8. Rerun workload.
9. Compare telemetry.
```

Useful future commands:

```bash
mise obs-errors -- --since 15m
mise obs-trace -- --request-id e-...
mise obs-slow-spans -- --threshold 2s
mise obs-startup -- --limit-ms 800
mise obs-sql -- "SELECT ..."
```

These commands should query ClickHouse/HyperDX rather than LogQL/PromQL/TraceQL because ClickStack is the chosen stack.

### 9.1 Query Model

ClickStack stores observability events in ClickHouse tables. Logs are not just local text files once ingested; they become database rows that can be searched and correlated with traces and metrics.

Agents should not rely on `grep` as the primary debugging method after telemetry is ingested. `grep` is still useful before ingestion, while debugging local file output, or when ClickStack is down. The normal observability path is:

```text
find logs/traces/metrics with HyperDX search or ClickHouse SQL
```

This replaces the query-language split used by other observability stacks:

| Other Stack Query | Purpose | ClickStack Equivalent |
|---|---|---|
| LogQL | logs | HyperDX Lucene-style search + ClickHouse SQL |
| PromQL | metrics | HyperDX dashboards + ClickHouse SQL |
| TraceQL | traces | HyperDX trace explorer + ClickHouse SQL |

The agent-facing scripts should therefore generate SQL or call HyperDX/ClickStack APIs, not LogQL/PromQL/TraceQL.

---

## 10. Rollout Plan

### Phase 1 — ChenWeb Local Baseline

Status: started.

Scope:

- local ClickStack compose stack
- OpenTelemetry config/init package
- request ID middleware
- HTTP request spans
- HTTP duration metric
- JSON log mode
- filelog collector for `app.log`

### Phase 2 — Useful ChenWeb Instrumentation

Add spans/metrics around the highest-value ChenWeb workflows:

- document upload
- PDF parsing
- doc processor phase orchestration
- LLM calls
- embedding/indexing
- search/index queries
- JetStream publish/consume

Add low-cardinality attributes first:

- `record_id`
- `processor`
- `operation`
- `phase`
- `model`
- `status`

Avoid high-cardinality or sensitive text fields.

### Phase 3 — Agent Query Scripts

Add repeatable scripts under:

```text
ChenWeb/observability/queries/
```

Initial queries:

- recent errors
- slow HTTP routes
- slow spans
- traces by request ID
- doc processor failures
- LLM latency by model

### Phase 4 — Production Candidate

Only after ChenWeb proves the pattern:

- decide self-hosted ClickStack vs managed ClickStack
- design ClickHouse retention/backup policy
- define RBAC and ingestion keys
- document PII policy
- consider adopting in `tax`

---

## 11. Guardrails

### 11.1 ChenWeb First

Do not wire `tax` until ChenWeb has:

- stable local development workflow
- useful dashboards/queries
- proven low overhead
- clear PII redaction rules

### 11.2 PII Boundary

Observability may contain:

- IDs
- durations
- statuses
- operation names
- counts
- file sizes
- model names
- error categories

Observability must not contain:

- secrets
- tokens
- cookies
- raw document text
- raw user-uploaded content
- unredacted prompts
- unredacted LLM responses

### 11.3 Cardinality

Use high-cardinality fields mainly in logs and traces where they are necessary for debugging. Be careful with metrics attributes.

Safe metric attributes:

- route
- method
- status
- processor
- phase
- model

Risky metric attributes:

- user ID
- record ID
- file name
- prompt name if too granular
- arbitrary error text

---

## 12. Verification

Current targeted verification:

```bash
cd shared/go
go test ./api/loggerutil ./api/observability ./api/EchoFactory

cd ../../ChenWeb
go test ./server/cmd/deepdoc ./server/api
docker compose -f observability/docker-compose.yml config

cd ..
go work sync
```

Expected behavior:

- tests pass
- ChenWeb server entrypoint compiles
- route package tests pass
- compose config renders successfully
- observability is disabled by default
- enabling observability exports traces/metrics to `http://localhost:14318`
- JSON logs are available for filelog collection when `JIMO_LOG_FORMAT=json`

---

## 13. References

- `shared/go/api/observability/`
- `shared/go/api/loggerutil/jimologger.go`
- `shared/go/api/EchoFactory/echo_factory.go`
- `ChenWeb/server/cmd/deepdoc/main.go`
- `ChenWeb/server/api/routes.go`
- `ChenWeb/observability/README.md`
- `ChenWeb/observability/docker-compose.yml`
- `ChenWeb/observability/otel-filelog-collector.yaml`
