# Harness-Neutral Agentic Services — one adapter per harness

**Date:** 2026-10-18 \
**Scope:** Proposed architecture for extending SemOS's Pi-powered agentic services to support additional agent harnesses while preserving SemOS's conversation, permission, and evidence controls. \
**Code root:** `SemOS/server/api/agentservicehandler/`

## 1. Summary

SemOS's agentic services should support multiple agent harnesses through one adapter per harness. A harness is the runtime that coordinates a model and its tools, such as Pi, Codex, Claude Code, OpenClaw, or OpenCode. SemOS remains the product: it authenticates the user, chooses the service and harness, checks access, stores the conversation, and decides which events and citations reach the user. Each adapter translates between SemOS's stable run contract and one harness's own API or process model. This keeps Pi useful while allowing later integrations without making harness-specific details part of the SemOS page or conversation model.

**Change of direction (2026-10-20).** A second integration model now exists beside the one above: ChenWeb as a **front end** to a harness, the way VS Code is a front end to Claude Code. In that model the harness keeps its own system prompt, loop, tools, memory, skills and session history. ChenWeb only sends the user's messages, relays what the harness streams back, and passes approvals to it. Claude Code is the first harness built this way (§2.7). It is not limited to coding; the intended use is close to Claude Cowork, handling general tasks. The SemOS-owned services model (Pi Knowledge Desk, sections 2.1–2.6) is unchanged for now. Whether it moves to the front-end model is an open decision.

Note: SemOS is the product name of the project ChenWeb.

## 2. Details

### 2.1 Current boundary

The proof of concept already separates most product behavior from the Pi runtime:

- `RunHandler` in `server/api/agentservicehandler/run_handler.go` owns turn creation, user and source checks, bounded history, capability minting, event collection, persistence, and outcome settlement.
- `GatewayBridge` is the runtime boundary used by `RunHandler` for starting and cancelling a run, handling permission decisions, obtaining model context-window information, and summarizing history.
- `PiGatewayClient` in `gateway.go` implements that boundary and maps SemOS profile and history data to Pi gateway requests.
- The gateway emits normalized run events that SemOS filters, stores, and turns into the public SSE stream.

The handler boundary now uses harness-neutral names: `HarnessAdapter`, `AgentRunRequest`, `AgentRunProfile`, and `AgentServiceProfile`. `PiHarnessAdapter` implements that contract and maps the normalized request to the shared Pi gateway protocol. Pi wire types, gateway credentials, and transport details remain inside that adapter.

`RunHandler` no longer holds a single adapter. It gets one from a `HarnessRegistry` (`harness.go`) using the `harness` field of the pinned service profile. Profile versions stored before that field existed are read as `pi`. Each adapter describes itself with a `HarnessDescriptor`: its name, adapter version, declared capabilities, and the largest run request it accepts. Each run attempt records the harness, adapter version and model that executed it (`kb.agentic_response_attempts.harness`, `adapter_version`, `model_name`). Cancel and approval decisions go to the adapter recorded on the attempt.

### 2.2 Recommended architecture

Keep one SemOS-owned conversation lifecycle and add a distinct adapter implementation for each supported harness:

```text
Browser
  │ authenticated SemOS API / public SSE
  ▼
SemOS agent-service layer
  ├─ identity, service selection, access checks, run capability
  ├─ conversation history, source verification, persistence, public events
  └─ HarnessAdapter registry
       ├─ Pi adapter ─────── Pi SDK gateway
       ├─ Codex adapter ──── isolated Codex worker/runtime
       ├─ Claude Code adapter ─ isolated Claude Code worker/runtime
       └─ future adapters ── OpenClaw, OpenCode, etc.
```

Pi (`PiHarnessAdapter`, gateway in `ThirdParty/pi/gateway`) is the only adapter in this model. A Claude Code adapter for it was built on 2026-10-20 and then backed out. It had to strip Claude Code down to a bare loop (its own prompt, tools, settings and sessions all switched off) to fit SemOS's tool boundary, which defeats the point of using a harness. Claude Code is integrated through the front-end model instead (§2.7).

Each adapter translates requests, events, cancellation, and any supported approval flow. The adapter may use an SDK, a private HTTP service, or a supervised worker process, depending on the harness. Harness packages and wire protocols must not leak into SemOS's browser API or persisted product-level conversation model.

### 2.3 Adapter contract

Introduce a harness-neutral interface in the agent-service backend. The contract should cover only lifecycle operations SemOS actually needs:

| Operation | Required behavior |
| --- | --- |
| Start a run | Accept a bounded, authorized run request and return a stream of normalized events. |
| Cancel a run | Stop work for the specified run as promptly as the harness permits. |
| Resolve an approval | Allow or deny a pending action when the adapter advertises interactive approval. |
| Report capabilities | Declare optional features and limits so SemOS can reject incompatible service configurations before a run starts. |
| Summarize history / report context capacity | Optional operations. Use only when supported; keep fallback behavior in SemOS. |

The normalized request should carry SemOS's run ID, service slug and pinned version, user message, bounded visible history, run-scoped capability, and service limits. Harness-specific launch options and model fields belong in adapter configuration. Keep optional metadata explicit; do not assume that every harness supports the same context-window query, usage accounting, session resume, permission prompts, or stop guarantees.

The normalized event vocabulary should stay small and product-focused: answer delta, safe activity/tool status, approval request, validated source references, usage metadata, completion, interruption, and safe error. Adapters must omit hidden reasoning, credentials, raw protected tool output, and internal harness state. SemOS remains responsible for validating source references and tool calls before persistence or public display.

### 2.4 Capability and service configuration

Separate a **service profile** from a **harness adapter configuration**:

- The service profile defines user-facing purpose, prompt/version, allowed knowledge scope and tools, provider disclosure, resource limits, and access eligibility.
- The adapter selection identifies the harness implementation and an adapter configuration version. That configuration contains only fields understood by that adapter, such as a Pi gateway target or a worker launch profile.
- Model/provider selection is associated with the selected adapter configuration where the harness requires it. SemOS must record the effective harness, adapter version, and model identity for each conversation or run so an operator can explain how it was executed.

Each adapter publishes a capability declaration: `streaming`, `cancellation`, `interactive_tool_approval`, `usage_reporting`, `history_replay`, `context_capacity_reporting`, and `history_summary`. SemOS checks the declaration when loading or activating the service and gives a clear unavailable result if a required capability is missing. Optional features that are unsupported must be disabled explicitly, not silently approximated as if they worked.

As built, a service's requirements are derived from its profile rather than configured separately:

| Capability | Required when | Without it |
| --- | --- | --- |
| `streaming`, `cancellation` | always | service unavailable; an adapter cannot even register without `streaming` |
| `interactive_tool_approval` | default permission is `ask` | `ask` runs and permission decisions return 409 |
| `history_replay` | the service saves and resumes conversations | service unavailable |
| `context_capacity_reporting` | never | the fallback history budget is used |
| `history_summary` | never | older turns are trimmed instead of folded into a summary |
| `usage_reporting` | never | token counts are recorded as zero |

The checks run at startup (each incompatible service is logged and stays unavailable), when the Pi admin page activates a profile version (rejected with 400), and when a conversation is created or a run starts (503, and the service is left out of the service list). The exact behavior is specified in the OpenSpec change `harness-adapter-registry`.

Do not build a universal harness configuration schema that attempts to normalize every CLI flag, agent setting, provider, or session format. Keep common product fields small and put the remaining settings in versioned adapter-specific configuration validated by that adapter.

### 2.5 Security and ownership invariants

Adding an adapter must not change these SemOS responsibilities:

1. The browser never receives harness credentials or calls the harness directly.
2. Every tool request is authorized by SemOS at the time of use with a short-lived, run-scoped capability. An adapter or harness does not grant itself more access than the profile and current user permissions allow.
3. Harnesses receive only the bounded conversation context and tools needed for the active service. No ambient user credential, database connection, unrestricted filesystem, shell, or network access is implied by harness selection.
4. SemOS validates citations and source access before marking a source-dependent response complete.
5. SemOS owns idempotency, one-active-run enforcement, cancellation outcome, saved history, deletion, and the public event stream.
6. Logs and public events contain safe operational metadata, never hidden reasoning, credentials, or protected raw tool payloads.

If a harness cannot be constrained to the service's approved tool boundary, it is not a compatible adapter for that service. Harness-specific approval UX may differ internally, but SemOS must present consistent user intent and record the decision.

### 2.6 Rollout sequence

1. **Done:** Rename/generalize the SemOS runtime boundary and event/request types without changing the Pi protocol or user-visible behavior.
2. **Done:** Keep Pi-specific profile mapping, model metadata calls, summaries, and gateway protocol handling behind `PiHarnessAdapter`. The existing Pi implementation remains the compatibility reference. The gateway's request-size limit is now declared by the adapter, and run-handler logs and the public start-failure message no longer name Pi.
3. **Done:** Add adapter registration and startup validation for supported capabilities. Keep service-to-adapter selection server-side. (OpenSpec change `harness-adapter-registry`.)
4. **Superseded:** Add one second adapter as a vertical slice. A Claude Code adapter was built and backed out (see §2.2). Claude Code now runs through the harness front end (§2.7) instead of this adapter contract.
5. **Not started:** Run the same service evaluation cases against Pi and any new adapter, including access denial/revocation, hostile source content, approval denial, cancellation, interrupted streams, and citation validation.

Do not start by integrating all named harnesses. Codex, Claude Code, OpenClaw, and OpenCode have different runtime and trust models; each needs an explicit deployment and capability review before being enabled for a service.

### 2.7 Harness front end (Claude Code)

ChenWeb fronts a harness the way an IDE does. The harness is the agent; ChenWeb is its user interface.

| Owned by the harness | Owned by ChenWeb |
| --- | --- |
| System prompt, agent loop, built-in tools, MCP servers, skills, `CLAUDE.md`, memory, compaction, model fallback | Sign-in and admin authorization |
| Session transcript, resume, session list | Which harness and session a request goes to |
| Permission rules from the user's settings | Showing permission prompts and relaying the decision |
| Model login (the machine's Claude Code login) | Relaying the event stream to the browser |

ChenWeb stores nothing about these conversations. There is no ChenWeb table: sessions and their history are read from the harness.

**Components.**
- **Gateway** `ChenWeb/gateways/claude-code`: a private Bun service on loopback with a bearer secret. It uses the Claude Agent SDK only as the connection to the real Claude Code. Claude Code's own system prompt and tools are kept (the `claude_code` presets) and all setting sources are loaded. It runs in `CLAUDE_CODE_WORKSPACE` (here `/Users/cding/Workspace`) with the machine's Claude Code login. The gateway removes `ANTHROPIC_API_KEY`/`ANTHROPIC_AUTH_TOKEN`, which would override the login, and keeps variables named like secrets out of Claude Code's environment.
- **Sessions.** Each session is one long-lived Claude Code process fed messages as they arrive, like a terminal. After an idle period the process is closed, and the next message resumes the session from Claude Code's own transcript. Sessions started in VS Code in the same folder can be continued too.
- **Harness front-end protocol v1.** All routes are on the gateway:
  - `GET /v1/sessions` and `GET /v1/sessions/:id/messages`
  - `POST /v1/turns` (NDJSON events: `session`, `text`, `tool_use`, `tool_result`, `permission_request`, `status`, `result`, `error`)
  - `POST /v1/sessions/:id/interrupt` and `POST /v1/sessions/:id/permissions/:requestId`

  Hidden reasoning is not relayed. The protocol is harness-neutral: another harness gets its own gateway speaking it.
- **ChenWeb** `server/api/harnessfrontend`: a protocol-v1 client per configured gateway. It exposes admin-only routes under `/api/v1/harness-frontend/:harness/...` and relays turns as SSE. Claude Code is registered when `CLAUDE_CODE_GATEWAY_URL` and `CLAUDE_CODE_GATEWAY_SECRET` are set.

**Models.** The harness decides which models it offers. The gateway asks Claude Code for the list its `/model` picker shows the signed-in account (`supportedModels()`, without sending a message): aliases such as `default`, `opus` and `sonnet`, plus pinned model IDs. ChenWeb relays the list at `GET /api/v1/harness-frontend/:harness/models`. The chat page's model menu (`chatter-01.svelte`) shows it when the selected agent is harness-backed (`HARNESS_BY_AGENT`, currently Claude Code only) and keeps its configured list for other agents. A turn's `model` starts a new session on that model, or switches a live session as `/model` does.

**Permissions.** Claude Code's own permission rules decide first. Calls it would prompt for in a terminal become `permission_request` events, and ChenWeb answers allow or deny. An allow can carry `updatedInput`, which is how answers to `AskUserQuestion` are returned. Modes `default`, `acceptEdits` and `plan` are accepted; `bypassPermissions` is refused. A turn whose client disconnects is interrupted.

**Trust.** Claude Code has shell and file access as the server's OS user, so every front-end route is admin-only. This model does not carry the §2.5 invariants, which belong to SemOS-owned services.

**Verified live (2026-10-20).** The full chain ran through ChenWeb's handler, the gateway and Claude Code with the Claude Code login (`apiKeySource: none`, model `claude-opus-5-5`):
- a `Write` outside the workspace raised a permission request, which was approved through ChenWeb, and the file was written;
- a second turn on the same session recalled the first from Claude Code's own history.

The exact behavior is in the OpenSpec change `harness-frontend-sessions`; operating details are in the gateway's README.

### 2.8 Documentation and contract ownership

This document records the recommended architecture, not a shipped multi-harness feature contract. When implementation begins, put exact behavior and acceptance criteria in the applicable OpenSpec change or implementation specification. Update this devdoc after the adapter framework and additional adapters are built so it describes the actual architecture and supported capabilities.

The Pi integration now has an administrator page at **Development → Coding Assistant → Harnesses → Pi**. It manages versioned profiles for the two existing Pi-backed services and checks the configured Pi gateway. The gateway URL and secret, as well as model-provider credentials, remain deployment-managed. Profile versions are immutable, new conversations pin the active version, existing conversations retain their pinned version, and each version stores its selected prompt snapshot and SHA-256. This page configures Pi only; it does not add another harness or a universal adapter configuration UI.

## 3. Known limitations

- Pi is the only adapter in the SemOS-owned services model. A new adapter must emit the same newline-delimited normalized events that `RunEventCollector` accepts.
- Chat page (`chatter-01.svelte`, Development → Chat): with Claude Code selected, it sends messages to Claude Code and streams the reply. It shows tool calls, approval cards (option buttons for Claude Code's questions), Stop, and a Sessions menu that reopens stored sessions with their history. Not yet supported: permission-mode switching, attachments, and the page's Prompt/Result-format controls for harness tabs. Tabs are not kept across page reloads; reopen sessions from the Sessions menu.
- It supports one workspace folder, and does not keep a turn running after the browser disconnects.
- Subagent text is not streamed; subagent tool calls are, with their parent ID.
- Whether the Knowledge Desk services move to the front-end model is undecided.
- Run-time error codes still use the historical `gateway_*` names (for example `gateway_unavailable`) for every harness.
- The Pi pilot has not completed the real-provider, signed-in user evaluation described in the handoff. Passing automated checks does not establish answer quality for any harness.
- There is no universal administrator UI for adapter configuration, automatic failover, or cross-harness conversation migration. The shipped Pi profile page is Pi-specific and does not configure other harnesses.

## 4. References
[1] KnowledgeStore/doc-repo/requirements/202609/2026091401-rqmt-pi-agentic-services-for-chenweb.md

[2] KnowledgeStore/doc-repo/hand-offs/202609/2026091501-handoff-pi-agentic-services-handoff.md
