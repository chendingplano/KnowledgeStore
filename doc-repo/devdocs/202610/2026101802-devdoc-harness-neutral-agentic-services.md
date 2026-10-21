# Harness-Neutral Agentic Services — ChenWeb and agent harnesses

**Date:** 2026-10-18 (revised 2026-10-20) \
**Scope:** How ChenWeb works with agent harnesses (Pi, Claude Code, Codex, DeepSeek Harness, and later others): the two ways a harness is connected, what is built today, where the code is, and what is still open. Open this before adding a harness or changing either integration. \
**Code root:** `ChenWeb/server/api/agentservicehandler/` (SemOS-owned services), `ChenWeb/server/api/harnessfrontend/`, `ChenWeb/gateways/claude-code/`, `ChenWeb/gateways/codex/`, `ChenWeb/gateways/deepseek-harness/` and `ChenWeb/gateways/pi/` (harness front end)

**Traceability — openspec** (none of these changes is archived yet):
- `ChenWeb/openspec/changes/harness-adapter-registry/` — `proposal.md`, `design.md`, `tasks.md`, and `specs/agent-harness-adapters/spec.md`: adapter registry, capability checks, per-run harness record for the SemOS-owned services.
- `ChenWeb/openspec/changes/harness-frontend-sessions/` — `proposal.md`, `design.md`, `tasks.md`, and `specs/harness-frontend/spec.md`: ChenWeb as a front end to Claude Code, including the model list and the chat page.
- `ChenWeb/openspec/changes/codex-harness-frontend/` — `proposal.md`, `design.md`, `tasks.md`, and `specs/harness-frontend/spec.md`: Codex as a second harness behind the same front end.
- `ChenWeb/openspec/changes/deepseek-harness-frontend/` — `proposal.md`, `design.md`, `tasks.md`, and `specs/harness-frontend/spec.md`: DeepSeek Harness as a third harness behind the same front end.
- `ChenWeb/openspec/changes/pi-harness-frontend/` — `proposal.md`, `design.md`, `tasks.md`, and `specs/harness-frontend/spec.md`: Pi as a fourth harness behind the same front end, and the removal of the earlier Pi session copy.
- `ChenWeb/openspec/specs/agent-conversation-history/spec.md` — conversation history rules for the SemOS-owned services.

The spec files are the contract. **If behavior changes, update the spec, not only this document.** This document explains the design for people and points at the code.

Note: SemOS is the product name of the project ChenWeb.

## Summary

An *agent harness* is the program that turns a language model into a working assistant. It writes the instructions the model sees, runs the loop of thinking and using tools, remembers the conversation, handles errors and fallbacks, and asks the user before risky actions. Claude Code, Pi, Codex, DeepSeek Harness, OpenClaw and OpenCode are harnesses. Building one is a large job, so ChenWeb does not build its own; it uses existing ones.

ChenWeb connects to harnesses in two different ways.

**1. Harness front end — ChenWeb as the harness's user interface (the direction going forward).** ChenWeb plays the role VS Code plays for Claude Code or Codex. The harness stays exactly as it is, with its own instructions, tools, memory, skills, settings and conversation history. ChenWeb only:
- sends what the user types;
- shows what the harness answers, as it arrives;
- passes the user's approvals back.

ChenWeb keeps no copy of the conversation; when a page needs the history, it asks the harness. Claude Code, Codex, DeepSeek Harness and Pi are connected this way. Each runs on the server under the server's own login for that harness (for Claude Code and Codex, the same one VS Code uses; for DeepSeek Harness, the one stored in `~/.dsh`; for Pi, the one stored in `~/.pi/agent`) and works in `/Users/cding/Workspace`. Each can do any task it can do in a terminal (coding first, but nothing limits it to coding), so this front end is restricted to administrators.

On the **Chat** page (Development → Workspace → Chat), choosing Claude Code, Codex, DeepSeek Harness or pi in the harness menu lets a user:
- pick a model from the list the harness offers that account (Anthropic models for Claude Code, OpenAI models for Codex, DeepSeek models for DeepSeek Harness, and for Pi the models of every provider Pi is signed in to);
- send messages and watch the answer stream in;
- see each tool the harness uses (Codex's commands appear as `Shell`, its file changes as `Edit`; DeepSeek Harness's and Pi's tools keep their own names, such as `read`, `write` and `bash`);
- approve or deny actions the harness asks about, and answer its questions (Claude Code and Codex; for Pi, only what a Pi extension asks, since Pi itself asks before nothing);
- stop a running reply;
- reopen the harness's earlier sessions, including ones started in VS Code (or, for DeepSeek Harness, in its own Web UI; for Pi, in a terminal), with their full history.

Pi was connected once before, the wrong way: a Pi extension copied each Pi session into ChenWeb's database after every run. That copy has been removed; Pi's sessions now stay only in Pi's own files.

**2. SemOS-owned services — the Knowledge Desk (Pi).** The Knowledge Desk answers questions from ChenWeb's knowledge base. Here ChenWeb is in charge:
- it stores the conversation;
- it decides which documents a user may see;
- it allows only a few read-only knowledge tools;
- it checks every citation before showing it.

This Pi is configured separately from the Pi on the Chat page: it runs through its own gateway with only ChenWeb's knowledge tools. Pi runs these services through an *adapter*, a small translator between ChenWeb's run format and Pi's. A registry of adapters checks, before a service runs, that its harness supports what the service needs, such as stopping a run or asking for approval. Each run records which harness, adapter version and model handled it. Pi is the only adapter today.

Why two ways: the services model needs a harness to accept ChenWeb's strict limits, and doing that to Claude Code meant switching off nearly everything that makes it Claude Code. A Claude Code adapter for the services model was built on 2026-10-20 and then backed out for that reason. Whether the Knowledge Desk later moves to the front-end model is an open decision.

## How each model divides the work

| | Harness front end (Claude Code, Codex, DeepSeek Harness, Pi) | SemOS-owned services (Pi Knowledge Desk) |
| --- | --- | --- |
| Instructions, agent loop, tools | The harness's own | Set by ChenWeb's service profile; only ChenWeb's knowledge tools |
| Conversation history and memory | Kept by the harness; ChenWeb stores nothing | Stored and resent by ChenWeb |
| Model choice | From the harness's own model list | Fixed per service profile version |
| Who may use it | Administrators only (the harness has shell and file access) | Users granted access to the service and its knowledge stores |
| Approvals | The harness's own permission rules (Codex and DeepSeek Harness: their sandbox and approval policy; Pi: none, unless a Pi extension asks); ChenWeb shows the prompt and relays the answer | ChenWeb's ask/auto setting per service |
| Login to the model provider | The machine's Claude Code or Codex login; DeepSeek Harness's key stored in `~/.dsh`; Pi's login stored in `~/.pi/agent` | Credentials configured for the Pi gateway |

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
- `ChenWeb/gateways/deepseek-harness/` — the same kind of service for DeepSeek Harness (`dsh`, checked out and built in `ThirdParty-2/deepseek-harness`). It drives the real dsh through `dsh --profile acp`, dsh's Agent Client Protocol server. That interface does not give back a conversation's history, so the gateway reads earlier sessions from dsh's own session files in `~/.dsh/sessions`. Its README documents the routes, settings, login and approvals. Start it with `mise dev-deepseek-harness-gateway`.
- `ChenWeb/gateways/pi/` — the same kind of service for Pi. It drives the real Pi through `pi --mode rpc`, Pi's own interface for running it from another program, with one Pi process per open session. That interface reports only the session it is running, so the gateway reads the session list and history from Pi's own session files in `~/.pi/agent/sessions`. Its README documents the routes, settings, login and how Pi's extension dialogs are shown. Start it with `mise dev-pi-harness-gateway`.
- Chat page: `web/src/lib/components/shared-ui/chatter-01.svelte`, with `harness-dialog.svelte` and `harness-conversation.ts` beside it, and `web/src/lib/services/harnessFrontendService.ts`. `HARNESS_BY_AGENT` in that service decides which entries in the harness menu are served by a gateway (currently Claude Code, Codex, DeepSeek Harness and pi; the `pi` entry keeps the lowercase name the menu already had). These entries stay in the menu even when a user's saved chat settings list other agents.
- Settings in ChenWeb's `mise.local.toml`: `CLAUDE_CODE_GATEWAY_URL`, `CLAUDE_CODE_GATEWAY_SECRET`, `CLAUDE_CODE_WORKSPACE`, for Codex `CODEX_GATEWAY_URL`, `CODEX_GATEWAY_SECRET`, `CODEX_WORKSPACE`, and for DeepSeek Harness `DEEPSEEK_HARNESS_GATEWAY_URL`, `DEEPSEEK_HARNESS_GATEWAY_SECRET`, `DEEPSEEK_HARNESS_WORKSPACE`, `DEEPSEEK_HARNESS_BIN`, and for Pi `PI_HARNESS_GATEWAY_URL`, `PI_HARNESS_GATEWAY_SECRET`, `PI_HARNESS_WORKSPACE`, `PI_HARNESS_PASS_ENV`. A harness's routes exist in ChenWeb only when its URL and secret are set. ChenWeb reads them only when `mise dev` starts. When the Go code is rebuilt (by `air`), the server keeps the settings it started with, so after adding or changing a gateway setting, restart `mise dev` itself.
- A new harness joins by getting its own gateway that speaks the same protocol (the gateway READMEs describe it), one entry in the gateway list in `server/api/routes.go`, and one entry in `HARNESS_BY_AGENT`. Codex was added this way with no change to `harnessfrontend` or the chat page; DeepSeek Harness also needed a new entry in the chat page's default agent list, since the menu had none for it. Pi was added the same way as Codex.

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
- **Model list:** the models Codex offers the account: three under codex-cli 0.146.0, and seven after the upgrade to 0.163.0 (GPT-6.1-Sol as the default). A turn on GPT-6.1-Sol was checked under 0.163.0.
- **Approval:** a write to the home folder raised a `Shell` approval; after Allow, the file was written.
- **Memory:** a follow-up message was answered from Codex's own thread.
- **Earlier sessions:** the thread was listed with the workspace's VS Code threads, and its history was read back.
- Not checked live: Codex's questions (`request_user_input`) and the Chat page in a browser.

**Verified on 2026-10-20 against the real DeepSeek Harness** (dsh 0.2.1-rc.2), using the key stored in `~/.dsh`, through ChenWeb's real handler (`HARNESS_NAME=deepseek-harness go test -tags live ./api/harnessfrontend/`) and the gateway's `live-check.ts`:
- **Model list:** the three models dsh offers (deepseek-v4-flash as the default, DeepSeek-V4.1-Flash, DeepSeek-V4-Pro).
- **Approval:** a write to the home folder was refused by dsh's sandbox; dsh then asked to escalate, raising a `write` approval; after Allow, the file was written.
- **Memory:** a follow-up message was answered from dsh's own session.
- **Earlier sessions:** the session was listed with its title, and its history was read back from dsh's session file.
- Not checked live: the Chat page in a browser, and reopening a session started in dsh's own Web UI.

**Verified on 2026-10-20 against the real Pi** (pi 0.84.2, DeepSeek V4 Flash), using Pi's own login, through ChenWeb's real handler (`HARNESS_NAME=pi go test -tags live ./api/harnessfrontend/`) and the gateway's `live-check.ts`:
- **Model list:** 33 models from the providers Pi is signed in to (DeepSeek, OpenAI Codex) and the Qwen models Pi's own configuration declares, Pi's default first.
- **Approval:** Pi asks before nothing by itself, so the live check loaded a small test extension that asks before one write (as Pi's own permission-gate example does). The question appeared as an approval card; after Allow, the file was written.
- **Memory:** a follow-up message was answered from Pi's own session, also after the session was reopened in a new Pi process.
- **Earlier sessions:** the session was listed with its title, and its history was read back from Pi's session file.
- Not checked live: the Chat page in a browser, and a Qwen model: Pi's Qwen key is rejected by the provider, from a terminal too.

## Known limitations

**Harness front end (all harnesses)**
- It works in one folder (`/Users/cding/Workspace`).
- A reply stops if the browser disconnects; nothing runs unattended.
- The Chat page cannot yet switch permission mode (normal, accept edits, plan). Attachments, the Prompt picker and the result-format menu are not connected for harness tabs.
- Open tabs are not kept when the page is reloaded; earlier sessions are reopened from the Sessions menu.
- Text written by a harness's helper agents (subagents) is not streamed. For Claude Code, their tool use is shown; for Codex, only the call that starts or messages a subagent (shown as `Agent`).
- Hidden reasoning is never shown, for any harness.
- Sessions started from ChenWeb also appear in VS Code's session list (DeepSeek Harness: its own Web UI; Pi: a terminal's `/resume`), and the other way round, because each harness keeps one history for the folder (Claude Code in `~/.claude/projects`, Codex in `~/.codex/sessions`, DeepSeek Harness in `~/.dsh/sessions`, Pi in `~/.pi/agent/sessions`).
- A harness's gateway must be running for it to work in ChenWeb; no gateway is started with `mise dev`.
- If the model menu shows "Models unavailable" after a harness is selected, ChenWeb could not get that harness's model list. Check, in this order:
  1. ChenWeb was started after the harness's settings were added. On 2026-10-20, Codex showed "Models unavailable" because `mise dev` had been running since before the `CODEX_*` settings existed; restarting it fixed this.
  2. The harness's gateway is running (`mise dev-claude-code-gateway`, `mise dev-codex-gateway`, `mise dev-deepseek-harness-gateway` or `mise dev-pi-harness-gateway`).
  3. The harness itself can list models; for example, the machine is still signed in to it.

**Harness front end (Codex only)**
- The gateway runs one `codex app-server` process for all sessions. If it exits, running replies end with an error, and the next message starts a new one and resumes the thread.
- Permission modes map to Codex's sandbox: normal leaves Codex's own configuration in charge, accept edits uses `workspace-write`, and plan uses `read-only`. The Chat page cannot switch modes yet.
- Codex's MCP elicitations (a form or link an MCP server asks the user for) are declined, because the Chat page cannot show them. Codex questions that expect free text get only the listed options.
- A message sent without a model uses `model` from `~/.codex/config.toml` (`gpt-6.1-sol` on 2026-10-20). The model menu follows Codex: after Codex was upgraded from 0.146.0 to 0.163.0 on 2026-10-20, the menu grew from three models to seven with no change in ChenWeb. Under 0.146.0, `gpt-6.1-sol` was not offered and turns without a model failed; under 0.163.0 they work.
- On macOS, Codex's default sandbox can write to temporary folders such as `/tmp` without asking; only writes outside the workspace and those folders raise an approval.
- Codex reports tokens, not cost, so the reported cost is always 0.

**Harness front end (Pi only)**
- Pi has no sandbox and asks before nothing: its tools read, write and run commands as this machine's user. Approvals appear only when a Pi extension asks (yes/no and pick-one questions); questions that need typed text are cancelled.
- Choosing a model sends it to Pi the way Pi's own model picker does, which also makes it Pi's default for new sessions, in a terminal too.
- Only the normal permission mode works; Pi has no modes, so accept-edits and plan are refused. The thinking level cannot be chosen from ChenWeb; Pi's setting applies.
- Each open session is its own Pi process, stopped after 30 minutes without a message. A session open in a terminal Pi and in ChenWeb at the same time has two Pi processes writing one file; avoid this.
- Only the current branch of a session is shown; Pi's branches (`/tree`, `/fork`) are not.
- History is read from Pi's session files (format version 3). If a Pi upgrade changes that format, earlier sessions show an error naming the new version until the gateway is updated.
- Providers that Pi reads from environment keys (Anthropic, OpenAI by API key) are not offered, because the gateway does not pass on keys; a key that Pi's own configuration names can be passed with `PI_HARNESS_PASS_ENV`.
- System Admin → LLM → **Pi Sessions** still shows the copy made before the change; it is no longer updated.

**Harness front end (DeepSeek Harness only)**
- The gateway runs one dsh process for all sessions. If it exits, running replies end with an error, and the next message starts a new one and resumes the session.
- Replies appear a message at a time, not word by word: dsh's interface sends each message only once it is complete. Token counts and cost are reported as 0, since that interface carries neither.
- Only the normal permission mode works. dsh's interface has no modes, so a request for accept-edits or plan mode is refused rather than run with dsh's normal permissions. The reasoning-effort setting cannot be chosen from ChenWeb; dsh's default (high) applies.
- dsh's questions, plans and to-do lists are not part of the interface the gateway uses, so they do not appear.
- History and titles are read from dsh's session files, which use dsh's internal format (version 4). If a dsh upgrade changes that format, earlier sessions show an error naming the new version until the gateway is updated. dsh is a developer preview; rerun the gateway's live check after upgrading it.
- Reading the model list opens one session, which dsh keeps as an empty file in `~/.dsh/sessions` (once per start of the dsh process). ChenWeb's session list hides sessions with no messages.
- By default, dsh sends its session log to DeepSeek along with each request (its `session-log-deepseek` plugin). This is dsh's own setting, unchanged by ChenWeb.
- `dsh` runs from the checkout's built files (`apps/cli/lib/bin.js`). After updating the checkout, rebuild it there (`pnpm run build`).

**SemOS-owned services (Pi Knowledge Desk)**
- Pi is the only adapter.
- Run error codes keep their historical `gateway_*` names for every harness.
- The Pi pilot has not had the real-provider, signed-in user evaluation described in the handoff. Passing automated checks does not establish answer quality.
- Running the same evaluation cases against a second adapter (access revocation, hostile source content, approval denial, cancellation, citation checks) has not been done; there is no second adapter.
- There is no shared configuration screen across harnesses, no automatic failover between harnesses, and no moving a conversation from one harness to another.

**Open decisions**
- Whether the Knowledge Desk moves to the front-end model.
- Which harness is connected next (OpenCode, ...). DeepSeek Harness's interface (the Agent Client Protocol) is a standard one that other harnesses also offer, so its gateway may be a starting point for them. Each needs its own review of how it runs, how it signs in, and what it can access.

## References

[1] KnowledgeStore/doc-repo/requirements/202609/2026091401-rqmt-pi-agentic-services-for-chenweb.md

[2] KnowledgeStore/doc-repo/hand-offs/202609/2026091501-handoff-pi-agentic-services-handoff.md

[3] ChenWeb/gateways/claude-code/README.md — gateway routes, settings, login and permission handling

[4] ChenWeb/gateways/codex/README.md — the Codex gateway: app-server connection, login, approvals and questions

[5] ChenWeb/gateways/deepseek-harness/README.md — the DeepSeek Harness gateway: ACP connection, login, session files and approvals

[6] ChenWeb/gateways/pi/README.md — the Pi gateway: RPC connection, login, session files and extension dialogs
