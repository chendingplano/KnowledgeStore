# WPI logging — proposed activity and audit history

**Date:** 2026-10-30  
**Status:** Proposal; the WPI event log described below is not implemented.  
**Scope:** WPI page use, authoring, actions, generated artifacts, and related activity.  
**Code roots:** `ChenWeb/server/api/wpi/`, `ChenWeb/web/src/lib/wpi/`.

## Summary

The Web Page Interpreter (WPI) already records some server activity and errors, but it does not maintain a complete history of how its pages are used or how a user interaction leads to an action. This document proposes a searchable WPI activity history that connects page use, editor changes, action executions, and related work. It also records what the existing miner database and WPI code provided when examined on 2026-10-30.

The proposal covers meaningful activities and outcomes, including failures and rejected requests. It does not require storing every keystroke or copying all submitted data into logs. Generated artifacts remain in their normal storage; their WPI events identify and link to them.

## Existing logging

The live `miner` PostgreSQL database has several specialized logs. Counts below are point-in-time counts taken on 2026-10-30, not a guarantee of current volume.

| Table | Rows observed | Purpose |
| --- | ---: | --- |
| `kb.events` | 117,133 | Document-processing events and mutable status. |
| `kb.doc_proc_logs` | 126,917 | Document-processing steps, artifacts, timing, and LLM references. |
| `kb.doc_review_logs` | 3,147 | Document review results and findings. |
| `kb.object_audit_log` | 481 | Object changes; its constraints limit it to specific tables and actions. |
| `kb.pipeline_policy_events` | 58 | Pipeline policy decisions and context. |
| `public.jimo_alert_log` | 1,104 | Shared logger warnings and errors, including resolution metadata. |
| `public.llm_usage_event` | 8,715 | Model usage, timing, attribution, and response references. |
| `public.ap_task_event` / `public.ap_agent_trace` | 36 / 5 | Agent platform task events and traces. |
| `public.cust_request_logs` | 0 | Customer-submitted requests, not HTTP access logs. |

The alert table contained 48 warnings and one error with `WPI` in the message at inspection time. This is a message-text search, not a count of all WPI failures. Other specialized logs cover maintenance, semantic decisions, document generation, and prompt optimization.

The WPI backend uses `loggerutil.CreateDefaultLogger` in `server/api/wpi/handler.go`. It logs, among other things, bundle requests, selected descriptor and class operations, action executions, previews, and catalog errors. The shared logger writes to its configured application output and file handlers; warnings and errors can also be emitted to `public.jimo_alert_log`. A package-level logger's generated request ID is not a unique identifier for each HTTP request.

These records do not establish that a served page rendered or was used, and they do not consistently connect browser activity to action executions and downstream work. `kb.events` has a document-processing workflow; `kb.object_audit_log` is constrained to particular object operations. Neither is currently a general WPI activity log.

## Proposed design

Add an append-only `kb.wpi_events` table for the WPI activity timeline. Keep the shared application logger for operational diagnostics and the existing alert table for warnings and errors. Link to LLM usage, agent traces, and other specialized records rather than copying them into the WPI log. Event names and fields below are proposed and require an OpenSpec contract before implementation.

### Open observability and existing telemetry

Use open observability standards, principally OpenTelemetry, so WPI signals can be collected and investigated with different compatible tools. ChenWeb already has shared OpenTelemetry initialization and HTTP middleware, and a local ClickStack configuration with ClickHouse and HyperDX. Their presence does not establish that collection is enabled or healthy. The broader [ChenWeb telemetry proposal](2026102002-devdoc-telemetry.md) describes this foundation and the intended investigation workflow. Reuse it rather than creating a separate WPI telemetry stack.

WPI's durable activity and audit history and operational telemetry serve different needs. `kb.wpi_events` is the proposed authoritative record for its defined audit-critical events; traces, metrics, and operational logs help investigate behavior and performance. OpenTelemetry export, sampling, and collector availability do not by themselves guarantee a complete or transactional audit record. Conversely, an event row may link to a trace that was sampled out or has expired; the activity view must show when supporting telemetry is unavailable.

Instrument server operations using the existing OpenTelemetry request context. Create spans for action execution and significant work such as validation, database operations, and downstream calls where useful; record safe outcomes and duration. Emit structured logs with trace and span IDs where context is available. Export signals through the existing collector using OTLP, subject to verifying the deployed configuration. Use standard OpenTelemetry semantic conventions where applicable and a documented `wpi.*` namespace for domain-specific attributes. Include service, environment, and release identity consistently.

Propagate W3C Trace Context across browser requests, backend calls, and background work where supported; validate incoming context and never treat it as authentication or authorization. Store the actual trace ID and span ID with a WPI event when present, separately from the event, request, session, action-instance, and execution IDs. Do not invent a trace ID when no trace exists. A browser event may have no span; asynchronous operations should retain context or use a trace link when a parent-child relationship is inappropriate. See [OpenTelemetry context propagation](https://opentelemetry.io/docs/concepts/context-propagation/).

Collect low-cardinality counters and duration histograms for page and action outcomes, errors, event delivery, and reconciliation. Keep user IDs, session IDs, page instance IDs, execution IDs, and trace IDs out of metric labels; use trace-linked exemplars where supported. Define trace sampling separately from audit retention, and monitor exporter drops, queue pressure, collector outages, and ingestion lag. Apply the same redaction rules before data reaches any exporter or collector.

Browser OpenTelemetry instrumentation is [documented as experimental](https://opentelemetry.io/docs/languages/js/). Evaluate its maturity, bundle cost, privacy, and deployment constraints before selecting it. The authenticated WPI event endpoint can provide page-use coverage independently; browser tracing should complement it rather than become a prerequisite for the audit history. Verify propagation, including cross-origin policy if applicable, in the deployed application.

### Common event envelope

| Field | Purpose |
| --- | --- |
| `event_id`, `event_type`, `schema_version` | Unique event identifier and versioned event contract. |
| `occurred_at`, `received_at` | Time of activity and time received by the server. |
| `source` | Browser, server, or worker; indicates the origin of the observation. |
| `actor_id`, `session_id` | Authenticated actor and a non-secret WPI session identifier. |
| `trace_id`, `span_id`, `request_id`, `parent_event_id` | Correlation across interaction, request, execution, and downstream activity; trace context is nullable. |
| `app_id`, `page_id`, `page_version`, `panel_id`, `element_id` | WPI context when available. Use stable identifiers and version provenance. |
| `action_class`, `action_pointer`, `action_instance_id`, `execution_id` | Saved action location, runtime instance, and invocation identity when applicable. |
| `outcome`, `error_code`, `duration_ms` | Searchable outcome, safe failure category, and duration. |
| `details` | Bounded JSON with event-specific approved metadata. |

The server derives the actor from authentication and validates browser-supplied context. A browser event is an observation; it does not prove that a server operation succeeded. Server-side execution and authorization events provide the authoritative outcome. IDs must be propagated explicitly; the existing logger's generated ID does not provide the required end-to-end correlation.

### Activities to capture

| Area | Meaningful events and details |
| --- | --- |
| App and page use | App launch, bundle load, page render, page open and close, navigation, panel open and close, and observable session start and end. Include failures. |
| Interactions | Menu and list selection, button activation, pagination, filtering, sorting, refresh, form submission, validation failure, and cancellation. Record identifiers and counts rather than field contents. |
| Actions | Start and completion of `load`, `save`, `query`, `load-file`, and future classes; authorization or validation rejection; target, duration, result count, and safe error category. |
| Data changes | Attempt and confirmed commit, confirmed rollback, or unknown outcome; target, operation, counts, and approved record identifiers where appropriate. |
| Authoring | Editor open, preview, descriptor or class creation, save, validation failure, version and status change, and deletion if supported. Link old and new versions. |
| Security and access | WPI-visible authentication failures, authorization denials, invalid references, disallowed database or table access, and suspicious event-ingestion traffic. |
| Downstream work | IDs and outcomes for related LLM calls, agent runs, background jobs, generated artifacts, exports, and other existing records. |
| Runtime health | Rendering errors, uncaught exceptions, API failures, timeouts, cancellation, and event-delivery failures. |

For high-volume interactions such as typing, resizing, and dragging, record the final meaningful change or aggregate counts. More detailed diagnostics should be explicitly enabled for a limited period.

The proposed `insert-records` action calls for execution and runtime instance IDs, stored page reference, target, requested and committed counts when known, duration, and outcome. Its unknown-commit outcome and no-automatic-retry rules must remain visible in logging. See [insert-records design](../../code_modules/interpreter-action-insert-records.md). That action is itself proposed, not implemented.

### Data and access

Record an artifact's type, ID, version, size, storage reference, and lifecycle outcome as applicable. Keep its contents under their normal storage and access controls. By default, exclude passwords, tokens, cookies, full request bodies, form values, raw SQL parameters, and unrestricted raw database errors. Search terms and URLs can also contain sensitive data. Define an allowlist for each event type and sanitize errors before storing them.

As part of implementation, review existing WPI logging as well: the page-search handler currently logs `q`, and action failure paths pass errors to the shared logger. Apply the same data-handling rules to every sink, including alerts and application files. Restrict access to activity history by role and audit access to sensitive logs.

### Delivery and transaction boundaries

1. **Audit-critical server events:** For data changes and descriptor changes in the same PostgreSQL database as `kb.wpi_events`, commit the success event in the same transaction as the change. Record failed attempts separately after rollback. If the required event cannot commit, fail the corresponding same-database change.
2. **Page-use and diagnostic events:** Send browser events to an authenticated WPI endpoint in batches, with bounded buffering, retry, unique event IDs, and server-side deduplication. Count and alert on dropped or rejected events. Browser events are best-effort: closing a browser or losing connectivity can prevent delivery. Telemetry failure must not prevent page use.
3. **Other target databases:** A transaction in another database cannot atomically commit a central `miner.kb` row. Record the attempt centrally; where the target is controlled and instrumented, write an audit or outbox entry in the target transaction and reconcile it to `miner`. Otherwise document the weaker guarantee. If commit confirmation is lost, retain an unknown outcome and do not automatically retry a potentially committed insert. The policy for an unavailable central log during cross-database operations remains to be decided.

### Retention and querying

An initial proposal is 90 days of searchable activity and one year for audit-critical changes. Confirm actual requirements and measured volume before adopting a permanent policy. Index the event time and common investigations by actor, page, execution, and trace; choose partitioning and archival after measuring volume. Provide a role-restricted activity view and operational alerts for delivery, storage, and reconciliation failures.

## Implementation path

1. Write an OpenSpec change defining event names, field schemas, actor and correlation identities, OpenTelemetry mappings, authorization, retention, failure behavior, and audit-critical operations. The resulting specifications will be the implementation contract.
2. Add the event store through a goose migration and a WPI event writer; instrument existing server actions and descriptor writes first.
3. Add browser lifecycle and meaningful interaction events, batching, deduplication, and correlation with server requests.
4. Link downstream usage and task records; add supported cross-database outbox and reconciliation, a searchable view, and health alerts.
5. Verify success, rejection, failure, cancellation, uncertain commit, duplicate delivery, browser disconnect, logging outage, trace propagation and sampling, collector outage, access controls, and exclusion of submitted values and secrets across all sinks. Update this document to describe shipped behavior and link the resulting OpenSpec contract.

## Current limitations

- The proposed table, event endpoint, correlation model, browser instrumentation, and delivery guarantees do not yet exist as a unified WPI logging system.
- Browser telemetry cannot guarantee capture of every activity, especially when a browser closes or is offline.
- Cross-database atomic audit guarantees require target-side instrumentation; the central database alone cannot provide them.
- Existing log counts and current code observations are a snapshot and will change.
