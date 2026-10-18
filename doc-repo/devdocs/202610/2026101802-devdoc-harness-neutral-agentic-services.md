# Harness-Neutral Agentic Services — one adapter per harness

**Date:** 2026-10-18 \
**Scope:** Proposed architecture for extending ChenWeb's Pi-powered agentic services to support additional agent harnesses while preserving ChenWeb's conversation, permission, and evidence controls. \
**Code root:** `ChenWeb/server/api/agentservicehandler/`

## Summary

ChenWeb's agentic services should support multiple agent harnesses through one adapter per harness. A harness is the runtime that coordinates a model and its tools, such as Pi, Codex, Claude Code, OpenClaw, or OpenCode. ChenWeb remains the product: it authenticates the user, chooses the service and harness, checks access, stores the conversation, and decides which events and citations reach the user. Each adapter translates between ChenWeb's stable run contract and one harness's own API or process model. This keeps Pi useful while allowing later integrations without making harness-specific details part of the ChenWeb page or conversation model.

## Details

### Current boundary

The proof of concept already separates most product behavior from the Pi runtime:

- `RunHandler` in `server/api/agentservicehandler/run_handler.go` owns turn creation, user and source checks, bounded history, capability minting, event collection, persistence, and outcome settlement.
- `GatewayBridge` is the runtime boundary used by `RunHandler` for starting and cancelling a run, handling permission decisions, obtaining model context-window information, and summarizing history.
- `PiGatewayClient` in `gateway.go` implements that boundary and maps ChenWeb profile and history data to Pi gateway requests.
- The gateway emits normalized run events that ChenWeb filters, stores, and turns into the public SSE stream.

The current interface is a useful starting point, but its names and request types are Pi-oriented (`GatewayBridge`, `GatewayRunProfile`, `PiGatewayClient`). Pi profile mapping and gateway protocols should remain inside the Pi adapter as support for more runtimes is added.

### Recommended architecture

Keep one ChenWeb-owned conversation lifecycle and add a distinct adapter implementation for each supported harness:

```text
Browser
  │ authenticated ChenWeb API / public SSE
  ▼
ChenWeb agent-service layer
  ├─ identity, service selection, access checks, run capability
  ├─ conversation history, source verification, persistence, public events
  └─ HarnessAdapter registry
       ├─ Pi adapter ─────── Pi SDK gateway
       ├─ Codex adapter ──── isolated Codex worker/runtime
       ├─ Claude Code adapter ─ isolated Claude Code worker/runtime
       └─ future adapters ── OpenClaw, OpenCode, etc.
```

Each adapter translates requests, events, cancellation, and any supported approval flow. The adapter may use an SDK, a private HTTP service, or a supervised worker process, depending on the harness. Harness packages and wire protocols must not leak into ChenWeb's browser API or persisted product-level conversation model.

### Adapter contract

Introduce a harness-neutral interface in the agent-service backend. The contract should cover only lifecycle operations ChenWeb actually needs:

| Operation | Required behavior |
| --- | --- |
| Start a run | Accept a bounded, authorized run request and return a stream of normalized events. |
| Cancel a run | Stop work for the specified run as promptly as the harness permits. |
| Resolve an approval | Allow or deny a pending action when the adapter advertises interactive approval. |
| Report capabilities | Declare optional features and limits so ChenWeb can reject incompatible service configurations before a run starts. |
| Summarize history / report context capacity | Optional operations. Use only when supported; keep fallback behavior in ChenWeb. |

The normalized request should carry ChenWeb's run ID, service slug and pinned version, user message, bounded visible history, run-scoped capability, and service limits. Harness-specific launch options and model fields belong in adapter configuration. Keep optional metadata explicit; do not assume that every harness supports the same context-window query, usage accounting, session resume, permission prompts, or stop guarantees.

The normalized event vocabulary should stay small and product-focused: answer delta, safe activity/tool status, approval request, validated source references, usage metadata, completion, interruption, and safe error. Adapters must omit hidden reasoning, credentials, raw protected tool output, and internal harness state. ChenWeb remains responsible for validating source references and tool calls before persistence or public display.

### Capability and service configuration

Separate a **service profile** from a **harness adapter configuration**:

- The service profile defines user-facing purpose, prompt/version, allowed knowledge scope and tools, provider disclosure, resource limits, and access eligibility.
- The adapter selection identifies the harness implementation and an adapter configuration version. That configuration contains only fields understood by that adapter, such as a Pi gateway target or a worker launch profile.
- Model/provider selection is associated with the selected adapter configuration where the harness requires it. ChenWeb must record the effective harness, adapter version, and model identity for each conversation or run so an operator can explain how it was executed.

Each adapter publishes a capability declaration, for example: `streaming`, `cancellation`, `interactive_tool_approval`, `usage_reporting`, `history_replay`, and `context_capacity_reporting`. A service can require capabilities. ChenWeb checks the declaration when loading or activating the service and gives a clear unavailable result if a required capability is missing. Optional features that are unsupported must be disabled explicitly, not silently approximated as if they worked.

Do not build a universal harness configuration schema that attempts to normalize every CLI flag, agent setting, provider, or session format. Keep common product fields small and put the remaining settings in versioned adapter-specific configuration validated by that adapter.

### Security and ownership invariants

Adding an adapter must not change these ChenWeb responsibilities:

1. The browser never receives harness credentials or calls the harness directly.
2. Every tool request is authorized by ChenWeb at the time of use with a short-lived, run-scoped capability. An adapter or harness does not grant itself more access than the profile and current user permissions allow.
3. Harnesses receive only the bounded conversation context and tools needed for the active service. No ambient user credential, database connection, unrestricted filesystem, shell, or network access is implied by harness selection.
4. ChenWeb validates citations and source access before marking a source-dependent response complete.
5. ChenWeb owns idempotency, one-active-run enforcement, cancellation outcome, saved history, deletion, and the public event stream.
6. Logs and public events contain safe operational metadata, never hidden reasoning, credentials, or protected raw tool payloads.

If a harness cannot be constrained to the service's approved tool boundary, it is not a compatible adapter for that service. Harness-specific approval UX may differ internally, but ChenWeb must present consistent user intent and record the decision.

### Rollout sequence

1. Rename/generalize the ChenWeb runtime boundary and event/request types without changing the Pi protocol or user-visible behavior.
2. Move Pi-specific profile mapping, model metadata calls, summaries, and gateway protocol handling behind the Pi adapter. Keep the current Pi implementation as the compatibility reference.
3. Add adapter registration and startup validation for supported capabilities. Keep service-to-adapter selection server-side.
4. Add one second adapter as a vertical slice. Before implementation, select the candidate harness and deployment model, then verify that its tools can be constrained to ChenWeb's capability boundary.
5. Run the same service evaluation cases against Pi and the new adapter, including access denial/revocation, hostile source content, approval denial, cancellation, interrupted streams, and citation validation.

Do not start by integrating all named harnesses. Codex, Claude Code, OpenClaw, and OpenCode have different runtime and trust models; each needs an explicit deployment and capability review before being enabled for a service.

### Documentation and contract ownership

This document records the recommended architecture, not a shipped multi-harness feature contract. When implementation begins, put exact behavior and acceptance criteria in the applicable OpenSpec change or implementation specification. Update this devdoc after the adapter framework and additional adapters are built so it describes the actual architecture and supported capabilities.

## Known limitations

- Only Pi is currently integrated with the user-facing agentic service flow. The ChenWeb handler boundary is adapter-shaped, but profile and transport types still name Pi and need deliberate generalization.
- The Pi pilot has not completed the real-provider, signed-in user evaluation described in the handoff. Passing automated checks does not establish answer quality for any harness.
- No second harness is selected. Worker isolation, credential handling, tool restriction, and data-handling compatibility must be assessed for the specific harness and deployment before implementation.
- This proposal does not define an administrator UI for adapter configuration, automatic failover, cross-harness conversation migration, or exact storage schema changes.
