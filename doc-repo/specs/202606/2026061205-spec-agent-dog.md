# Spec: AgentDog-Style LLM Traffic Capture via mitmproxy + HyperDX

**Date:** 2026-06-12
**File(s):**
- `ChenWeb/server/api/proxytracehandler/handler.go`
- `ChenWeb/server/api/proxytracehandler/observability.go`
- `ChenWeb/server/api/routes.go`
- `ChenWeb/tools/mitmproxy/llm_trace_addon.py`
- `ChenWeb/tools/mitmproxy/start_llm_trace_capture.sh`
- `ChenWeb/tools/mitmproxy/README.md`
- `ChenWeb/observability/README.md`

---

## Summary

This change adds a local `mitmproxy`-based capture path for logging LLM traffic
between coding agents and their cloud APIs, then forwarding the captured
request/response exchanges into ChenWeb and HyperDX.

The goal is AgentDog-style observability for agents used outside ChenWeb's own
runner, especially:

- Claude Code in VS Code
- Codex in VS Code

The capture path is:

```text
VS Code / extension / CLI
    -> mitmproxy
    -> ChenWeb local ingest endpoint
    -> OpenTelemetry span
    -> HyperDX
```

---

## What Problem This Solves

ChenWeb already normalizes traces for agents launched by the Agent Platform
worker. That path captures agent-level events such as tool calls, usage, final
answers, and timeline events.

However, when Claude Code or Codex is used directly inside VS Code, those
sessions do not automatically flow through ChenWeb's agent runner, so their
network traffic is not visible to ChenWeb or HyperDX by default.

This spec adds a second observability path:

- traffic-level capture using `mitmproxy`
- local forwarding into ChenWeb
- HyperDX spans for captured LLM HTTP exchanges

---

## Server-Side Endpoint

ChenWeb now exposes a local-only ingest endpoint:

```text
POST /api/internal/mitmproxy/ingest
```

### Auth model

This endpoint is not behind the normal session auth middleware. Instead, it is
protected by a shared token:

```text
MITM_TRACE_INGEST_TOKEN
```

Use the following command to generate a token:
```text
openssl rand -hex 32
```

Request authentication supports either:

```text
Authorization: Bearer <token>
```

or:

```text
X-Trace-Token: <token>
```

If the token is not configured, the endpoint returns `503`.
If the token is wrong or missing, the endpoint returns `403`.

---

## Ingest Payload

The ingest handler accepts one JSON payload per captured HTTP exchange.

Important fields:

- `source`
- `agent_kind`
- `agent_name`
- `agent_session`
- `session_id`
- `method`
- `url`
- `host`
- `path`
- `status_code`
- `started_at`
- `duration_ms`
- `request_headers`
- `response_headers`
- `request_body`
- `response_body`
- `error`

The handler normalizes the payload and derives:

- `llm.provider`
- `llm.model`
- token usage

### Provider detection

Detected from host:

- `api.anthropic.com` -> `anthropic`
- `api.openai.com` -> `openai`

### Model detection

Detected from JSON request or response bodies via:

```json
{
  "model": "..."
}
```

### Token usage detection

Detected from response JSON:

```json
{
  "usage": {
    "input_tokens": ...,
    "cached_input_tokens": ...,
    "output_tokens": ...,
    "reasoning_output_tokens": ...,
    "total_tokens": ...
  }
}
```

For Anthropic-style responses, if `total_tokens` is absent, ChenWeb derives:

```text
total_tokens = input_tokens + output_tokens
```

---

## HyperDX Span Shape

Each forwarded exchange becomes one OpenTelemetry span:

```text
agent_proxy.http_exchange
```

### Span attributes

Default attributes include:

- `proxy.source`
- `agent.kind`
- `agent.name`
- `agent.session`
- `proxy.session_id`
- `llm.provider`
- `llm.model`
- `http.method`
- `http.url`
- `http.host`
- `http.path`
- `http.status_code`
- `http.duration_ms`
- `http.request.body_bytes`
- `http.response.body_bytes`
- `llm.usage.input_tokens`
- `llm.usage.cached_input_tokens`
- `llm.usage.output_tokens`
- `llm.usage.reasoning_output_tokens`
- `llm.usage.total_tokens`

### Span events

Two events are emitted:

- `http.request`
- `http.response`

### Optional request/response bodies

Full request and response bodies are only attached to the span when:

```text
MITM_TRACE_OTEL_INCLUDE_CONTENT=true
```

---

## mitmproxy Addon

The local addon is:

```text
ChenWeb/tools/mitmproxy/llm_trace_addon.py
```

### Responsibilities

It:

- filters traffic to LLM hosts
- extracts request and response bodies
- redacts sensitive headers
- optionally writes local JSONL
- forwards each captured exchange to ChenWeb

### Default allowed hosts

```text
api.anthropic.com,api.openai.com
```

Override with:

```text
MITMTRACE_ALLOWED_HOSTS
```

### Body size limit

Default:

```text
16384 bytes
```

Override with:

```text
MITMTRACE_MAX_BODY_BYTES
```

Oversized request or response bodies are truncated with a marker.

### Header handling

Headers are omitted by default.

Set:

```text
MITMTRACE_INCLUDE_HEADERS=true
```

to include them, with these values redacted:

- `authorization`
- `x-api-key`
- `cookie`
- `set-cookie`

### Optional local JSONL archive

If set:

```text
MITMTRACE_JSONL_PATH
```

the addon appends one JSON line per captured exchange.

---

## macOS / VS Code Workflow

### 1. Install mitmproxy

```bash
brew install --cask mitmproxy
```

### 2. Generate and trust the mitmproxy root certificate

Run once:

```bash
mitmdump --version
```

Then import:

```text
~/.mitmproxy/mitmproxy-ca-cert.pem
```

into Keychain Access and mark it as:

```text
Always Trust
```

Without trusted TLS interception, you may only see CONNECT tunnels or metadata,
not the decrypted LLM request/response bodies.

### 3. Start ChenWeb with the ingest token

Example:

```bash
cd /Users/cding/Workspace/ChenWeb
export OBSERVABILITY_ENABLED=true
export OTEL_SERVICE_NAME=chenweb
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:14318
export OTEL_EXPORTER_OTLP_HEADERS="authorization=${CLICKSTACK_API_KEY}"
export MITM_TRACE_INGEST_TOKEN=replace-me
mise exec -- ./.cache/server.exe serve --dir ./pb_data --dev --http=:8080
```

### 4. Start mitmproxy

Use:

```bash
cd /Users/cding/Workspace/ChenWeb
export MITM_TRACE_INGEST_TOKEN=replace-me
export MITMTRACE_JSONL_PATH="$HOME/.mitmproxy/chenweb-llm-trace.jsonl"
./tools/mitmproxy/start_llm_trace_capture.sh
```

### 5. Launch VS Code through the proxy

Example shell launch:

```bash
export HTTP_PROXY=http://127.0.0.1:8081
export HTTPS_PROXY=http://127.0.0.1:8081
export NO_PROXY=127.0.0.1,localhost
export MITMTRACE_AGENT_NAME="VS Code"
open -na "Visual Studio Code"
```

If the extension runtime does not inherit those environment variables cleanly,
use macOS system proxy settings for the same host/port while capturing.

---

## Practical Scope and Limitations

### What this does capture

- OpenAI API calls from Codex sessions that route through the proxy
- Anthropic API calls from Claude Code sessions that route through the proxy
- model name
- token usage, when present in the API response
- HTTP-level request/response timing and status
- request/response bodies, subject to truncation and content settings

### What this does not guarantee

- internal agent reasoning beyond what the provider returns on the wire
- local IDE-only actions that never touch the provider
- automatic capture of every VS Code extension process without proxy routing

This is traffic-level observability, not OS-level interception of arbitrary
local app behavior.

---

## HyperDX Queries

Search for all proxy-captured exchanges:

```text
span.name:"agent_proxy.http_exchange"
```

Useful filters:

```text
llm.provider:"anthropic"
llm.provider:"openai"
agent.kind:"claude_code"
agent.kind:"codex"
```

---

## Verification

The implementation was validated with:

```bash
go test ./server/api/proxytracehandler ./server/api
python3 -m py_compile tools/mitmproxy/llm_trace_addon.py
bash -n tools/mitmproxy/start_llm_trace_capture.sh
```

Server-side route registration is covered by test.
The proxy ingest handler and HyperDX span generation are covered by focused Go
tests.

---

## Related Files

- `ChenWeb/server/api/proxytracehandler/handler_test.go`
- `ChenWeb/server/api/routes_proxytrace_test.go`
- `ChenWeb/observability/README.md`

