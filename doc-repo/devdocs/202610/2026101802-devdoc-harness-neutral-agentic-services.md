# Harness-Neutral Agentic Services — ChenWeb and agent harnesses

**Date:** 2026-10-18 (revised 2026-10-20) \
**Scope:** How ChenWeb works with agent harnesses (Pi, Claude Code, Codex, and later others): the two ways a harness is connected, what is built today, where the code is, and what is still open. Open this before adding a harness or changing either integration. \
**Code root:** `ChenWeb/server/api/agentservicehandler/` (SemOS-owned services), `ChenWeb/server/api/harnessfrontend/`, `ChenWeb/gateways/claude-code/` and `ChenWeb/gateways/codex/` (harness front end)

**Traceability — openspec** (none of these changes is archived yet):
- `ChenWeb/openspec/changes/harness-adapter-registry/` — `proposal.md`, `design.md`, `tasks.md`, and `specs/agent-harness-adapters/spec.md`: adapter registry, capability checks, per-run harness record for the SemOS-owned services.
- `ChenWeb/openspec/changes/harness-frontend-sessions/` — `proposal.md`, `design.md`, `tasks.md`, and `specs/harness-frontend/spec.md`: ChenWeb as a front end to Claude Code, including the model list and the chat page.
- `ChenWeb/openspec/changes/codex-harness-frontend/` — `proposal.md`, `design.md`, `tasks.md`, and `specs/harness-frontend/spec.md`: Codex as a second harness behind the same front end.
- `ChenWeb/openspec/specs/agent-conversation-history/spec.md` — conversation history rules for the SemOS-owned services.

The spec files are the contract. **If behavior changes, update the spec, not only this document.** This document explains the design for people and points at the code.

Note: SemOS is the product name of the project ChenWeb.

## Summary

An *agent harness* is the program that turns a language model into a working assistant. It writes the instructions the model sees, runs the loop of thinking and using tools, remembers the conversation, handles errors and fallbacks, and asks the user before risky actions. Claude Code, Pi, Codex, OpenClaw and OpenCode are harnesses. Building one is a large job, so ChenWeb does not build its own; it uses existing ones.

ChenWeb connects to harnesses in two different ways.

**1. Harness front end — ChenWeb as the harness's user interface (the direction going forward).** ChenWeb plays the role VS Code plays for Claude Code or Codex. The harness stays exactly as it is, with its own instructions, tools, memory, skills, settings and conversation history. ChenWeb only:
- sends what the user types;
- shows what the harness answers, as it arrives;
- passes the user's approvals back.

ChenWeb keeps no copy of the conversation; when a page needs the history, it asks the harness. Claude Code and Codex are connected this way. Each runs on the server under the server's own login for that harness (the same one VS Code uses) and works in `/Users/cding/Workspace`. Either can do any task it can do in a terminal (coding first, but nothing limits it to coding), so this front end is restricted to administrators.

On the **Chat** page (Development → Workspace → Chat), choosing Claude Code or Codex in the harness menu lets a user:
- pick a model from the list the harness offers that account (Anthropic models for Claude Code, OpenAI models for Codex);
- send messages and watch the answer stream in;
- see each tool the harness uses (Codex's commands appear as `Shell`, its file changes as `Edit`);
- approve or deny actions the harness asks about, and answer its questions;
- stop a running reply;
- reopen the harness's earlier sessions, including ones started in VS Code, with their full history.

**2. SemOS-owned services — the Knowledge Desk (Pi).** The Knowledge Desk answers questions from ChenWeb's knowledge base. Here ChenWeb is in charge:
- it stores the conversation;
- it decides which documents a user may see;
- it allows only a few read-only knowledge tools;
- it checks every citation before showing it.

Pi runs these services through an *adapter*, a small translator between ChenWeb's run format and Pi's. A registry of adapters checks, before a service runs, that its harness supports what the service needs, such as stopping a run or asking for approval. Each run records which harness, adapter version and model handled it. Pi is the only adapter today.

Why two ways: the services model needs a harness to accept ChenWeb's strict limits, and doing that to Claude Code meant switching off nearly everything that makes it Claude Code. A Claude Code adapter for the services model was built on 2026-10-20 and then backed out for that reason. Whether the Knowledge Desk later moves to the front-end model is an open decision.

## How each model divides the work

| | Harness front end (Claude Code, Codex) | SemOS-owned services (Pi Knowledge Desk) |
| --- | --- | --- |
| Instructions, agent loop, tools | The harness's own | Set by ChenWeb's service profile; only ChenWeb's knowledge tools |
| Conversation history and memory | Kept by the harness; ChenWeb stores nothing | Stored and resent by ChenWeb |
| Model choice | From the harness's own model list | Fixed per service profile version |
| Who may use it | Administrators only (the harness has shell and file access) | Users granted access to the service and its knowledge stores |
| Approvals | The harness's own permission rules (Codex: its sandbox and approval policy); ChenWeb shows the prompt and relays the answer | ChenWeb's ask/auto setting per service |
| Login to the model provider | The machine's Claude Code or Codex login | Credentials configured for the Pi gateway |

For the services model these rules hold whatever the harness:
- the browser never receives harness credentials or calls the harness directly;
- every tool call is authorized by ChenWeb with a short-lived, run-scoped capability;
- a harness gets no shell, filesystem, database or network access beyond the service's tools;
- ChenWeb validates citations and source access before an answer counts as complete;
- logs and public events never contain hidden reasoning, credentials or protected tool output.

A harness that cannot be held to these rules cannot be a services adapter. The front-end model does not carry these rules; it relies on administrator-only access instead.

## Where things live

**Harness front end**
- `ChenWeb/gateways/claude-code/` — a small private service on the server (Bun) that runs the real Claude Code through the Claude Agent SDK, used only as the connection, the way an IDE launches Claude Code. Its README documents the routes, settings and permission handling. Start it with `mise dev-claude-code-gateway`.
- `ChenWeb/server/api/harnessfrontend/` — ChenWeb's admin-only routes under `/api/v1/harness-frontend/:harness/...` (models, sessions, history, send, stop, approve), which relay to the gateway.
- `ChenWeb/gateways/codex/` — the same kind of service for Codex. It drives the real Codex through `codex app-server`, the interface the Codex VS Code extension uses. Its README documents the routes, settings and how Codex's approvals and questions are shown. Start it with `mise dev-codex-gateway`.
- Chat page: `web/src/lib/components/shared-ui/chatter-01.svelte`, with `harness-dialog.svelte` and `harness-conversation.ts` beside it, and `web/src/lib/services/harnessFrontendService.ts`. `HARNESS_BY_AGENT` in that service decides which entries in the harness menu are served by a gateway (currently Claude Code and Codex).
- Settings in ChenWeb's `mise.local.toml`: `CLAUDE_CODE_GATEWAY_URL`, `CLAUDE_CODE_GATEWAY_SECRET`, `CLAUDE_CODE_WORKSPACE`, and for Codex `CODEX_GATEWAY_URL`, `CODEX_GATEWAY_SECRET`, `CODEX_WORKSPACE`. A harness's routes exist in ChenWeb only when its URL and secret are set.
- A new harness joins by getting its own gateway that speaks the same protocol (the gateway READMEs describe it), one entry in the gateway list in `server/api/routes.go`, and one entry in `HARNESS_BY_AGENT`. Codex was added this way with no change to `harnessfrontend` or the chat page.

**SemOS-owned services**
- `ChenWeb/server/api/agentservicehandler/`:
  - `run_handler.go`: runs a turn and saves its outcome;
  - `harness.go`: adapter registry and capability checks;
  - `gateway.go`: the Pi adapter; the Pi gateway client itself is in the shared library;
  - `profiles.go` and `profile_store.go`: versioned service profiles.
- Pi gateway: `ThirdParty/pi/gateway/`.
- Administrator page for Pi profiles: Development → Coding Assistant → Harnesses → Pi. It manages immutable, versioned profiles for the two Pi services. New conversations use the active version and existing ones keep theirs. This page configures Pi only.
- Each run's harness, adapter version and model are recorded in `kb.agentic_response_attempts`.

**Verified on 2026-10-20 against the real Claude Code**, using the Claude Code login, with no API key involved:
- **Model list:** the menu showed the models Claude Code offers the account.
- **Approval:** a file write outside the workspace raised an approval card in the Chat page; after approval, the file was written.
- **Memory:** a follow-up message was answered from Claude Code's own memory.
- **Earlier sessions:** reopening an earlier session showed its full history.

**Verified on 2026-10-20 against the real Codex** (codex-cli 0.146.0), using the Codex login (ChatGPT Plus), with no API key involved, through ChenWeb's real handler (`HARNESS_NAME=codex go test -tags live ./api/harnessfrontend/`) and the gateway's `live-check.ts`:
- **Model list:** the three models Codex offers the account (GPT-5.6-Sol, -Terra, -Luna).
- **Approval:** a write to the home folder raised a `Shell` approval; after Allow, the file was written.
- **Memory:** a follow-up message was answered from Codex's own thread.
- **Earlier sessions:** the thread was listed with the workspace's VS Code threads, and its history was read back.
- Not checked live: Codex's questions (`request_user_input`) and the Chat page in a browser.

## Known limitations

**Harness front end (both harnesses)**
- It works in one folder (`/Users/cding/Workspace`).
- A reply stops if the browser disconnects; nothing runs unattended.
- The Chat page cannot yet switch permission mode (normal, accept edits, plan). Attachments, the Prompt picker and the result-format menu are not connected for Claude Code tabs.
- Open tabs are not kept when the page is reloaded; earlier sessions are reopened from the Sessions menu.
- Text written by Claude Code's helper agents (subagents) is not streamed; their tool use is shown.
- Claude Code's hidden reasoning is never shown.
- Sessions started from ChenWeb also appear in VS Code's session list, and the other way round, because Claude Code keeps one history for the folder.
- A harness's gateway must be running for it to work in ChenWeb; neither gateway is started with `mise dev`.

**Harness front end (Codex only)**
- Codex's MCP elicitations (a form or link an MCP server asks the user for) are declined, because the Chat page cannot show them. Codex questions that expect free text get only the listed options.
- A message sent without a model uses `model` from `~/.codex/config.toml`. On 2026-10-20 that was `gpt-6.1-sol`, which Codex reports this ChatGPT account cannot use, so such turns fail with Codex's error. Choosing a model from the menu avoids it.
- On macOS, Codex's default sandbox can write to temporary folders such as `/tmp` without asking; only writes outside the workspace and those folders raise an approval.
- Codex reports tokens, not cost, so the reported cost is always 0.

**SemOS-owned services (Pi Knowledge Desk)**
- Pi is the only adapter.
- Run error codes keep their historical `gateway_*` names for every harness.
- The Pi pilot has not had the real-provider, signed-in user evaluation described in the handoff. Passing automated checks does not establish answer quality.
- Running the same evaluation cases against a second adapter (access revocation, hostile source content, approval denial, cancellation, citation checks) has not been done; there is no second adapter.
- There is no shared configuration screen across harnesses, no automatic failover between harnesses, and no moving a conversation from one harness to another.

**Open decisions**
- Whether the Knowledge Desk moves to the front-end model.
- Which harness is connected next (Pi as a full harness, OpenCode, ...). Each needs its own review of how it runs, how it signs in, and what it can access.

## References

[1] KnowledgeStore/doc-repo/requirements/202609/2026091401-rqmt-pi-agentic-services-for-chenweb.md

[2] KnowledgeStore/doc-repo/hand-offs/202609/2026091501-handoff-pi-agentic-services-handoff.md

[3] ChenWeb/gateways/claude-code/README.md — gateway routes, settings, login and permission handling

[4] ChenWeb/gateways/codex/README.md — the Codex gateway: app-server connection, login, approvals and questions
