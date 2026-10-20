# Handoff: agentic services in ChenWeb (Pi Knowledge Desk and the Claude Code front end)

Date: 2026-09-15, updated 2026-10-20.

Status:
- **Pi Knowledge Desk:** built and tested automatically; the live pilot with a real model and a chosen user has **not** been run.
- **Claude Code front end:** built and checked live against the real Claude Code on 2026-10-20. Its browser page works with Claude Code, but some page controls are not connected yet.
- **Codex front end:** built on 2026-10-20 behind the same protocol and Chat page, and checked live through ChenWeb's handler against the real Codex. Not yet checked in a browser.

ChenWeb now connects to agent harnesses in two ways. A *harness* is the program that turns a model into a working assistant: Pi, Claude Code, Codex and so on.
- **SemOS-owned services:** the Pi Knowledge Desk. ChenWeb keeps the conversation and controls the tools and citations.
- **Harness front end:** Claude Code and Codex. ChenWeb is only the user interface, the way VS Code is for either.

The design and the reasons for having two ways are in the devdoc `KnowledgeStore/doc-repo/devdocs/202610/2026101802-devdoc-harness-neutral-agentic-services.md`. Read that first.

## 1. Pi Knowledge Desk

### What is ready

ChenWeb has two guides, `knowledge-guide` and `problem-diagnostics`, on the Knowledge Desk page (Workspace → Knowledge Desk, `/home3/agent-services`). Each has its own prompt, model, limits and knowledge scope. Signed-in users can:
- create, reopen, delete and rate conversations;
- ask questions and see streamed answers, plain-language tool activity and checked source cards;
- choose ask-before-use or automatic permission for the read tools;
- stop a run.

**How it is put together.**
- The browser talks only to ChenWeb. ChenWeb owns the user check, conversation storage, source access checks and the final answer.
- A loopback-only gateway in `ThirdParty/pi` runs Pi with ChenWeb's read-only knowledge tools: hybrid search, source passages, artifact details, document context and related knowledge. A sixth tool returns the full stored result of an earlier tool call.
- Pi receives a short-lived run capability, never the browser's sign-in or database access.
- An answer that depends on sources becomes complete only after ChenWeb verifies and saves its citations.

**Changed since 2026-09-15.**
- **Knowledge stores (09-30).** Each run tells Pi which knowledge stores the user may use, and which one is the default. A user with no granted store can still chat, but gets no knowledge tools.
- **History (10-04):**
  - Earlier turns are resent to Pi within a token budget, and older turns are folded into a rolling summary. Conversations get titles.
  - Tool calls are stored and replayed with later turns.
- **Snapshot rule (10-04).** This **replaces the 09-15 behavior** of hiding answers whose sources changed. Saved history younger than `PI_HISTORY_SNAPSHOT_DUR` (default 48 hours) is shown and resent exactly as saved. In older history, sources and tool results for documents the user can no longer access are removed. Answers are never hidden.
- **Profiles (10-18).** Service profiles are now immutable, numbered versions stored in the database. They are managed on an admin page: Development → Coding Assistant → Harnesses → Pi. New conversations use the active version; existing ones keep theirs.
- **Adapter registry (10-20).** Pi runs through an adapter registry. Before a service runs, ChenWeb checks that its harness supports what the service needs. Each run records its harness, adapter version and model in `kb.agentic_response_attempts`. Pi is the only adapter.

Project migrations create:
- the conversation tables;
- explicit user knowledge grants;
- a one-active-turn guard;
- the history-summary columns;
- stored tool results;
- profile versions;
- the per-run harness columns.

Prompts are under `ChenWeb/prompts`, not in code.

### Start a pilot

Exact steps are in `ChenWeb/docs/pi-agentic-services-operations.md`. In brief:
1. Configure the project database and the Pi provider credential.
2. Give ChenWeb and Pi the same private `PI_GATEWAY_SECRET`.
3. Give ChenWeb a separate `PI_RUN_CAPABILITY_SECRET`.
4. Set `PI_GATEWAY_DIR` to `ThirdParty/pi`.
5. Grant the chosen signed-in user access to the **verified numeric** knowledge-store ID.
6. Run `mise dev-agent-services` from ChenWeb and open Workspace → Knowledge Desk.

The gateway listens on `127.0.0.1:4317` and must not be publicly proxied. After the first start, change profiles on the admin page; environment variables only seed the first version.

Grants are still created by an operator; there is no grant admin page. A visible guide is not a knowledge grant. Before inviting pilot users, choose:
- the user;
- the store and tenant;
- the document scope;
- the expiry;
- the model/provider disclosure.

Conversation data stays until the user deletes it; there is no retention job.

### Verification

On 2026-09-15:
- Pi gateway: 17 tests and the TypeScript check passed.
- ChenWeb frontend: 374 tests passed.
- ChenWeb backend: `go test ./...`, `go vet ./...` and `mise build-server` passed.
- The first three migrations passed up → down → up on an empty probe database.

Each later change was committed with its own tests passing. On 2026-10-20, the `agentservicehandler` tests, `go vet` and `mise build-server` passed. One existing migration test was fixed: it had started failing after the migration file was reformatted, and its check no longer depends on spacing.

These checks do **not** establish answer quality with a real model.

### Next acceptance step (still open)

Run a real signed-in browser pilot with one chosen user and a current provider credential. Work through the evaluation cases in `ChenWeb/server/api/agentservicehandler/testdata/evaluation-cases.json` for both guides:
- normal evidence;
- ambiguity;
- missing evidence;
- conflicting sources;
- a hostile document;
- denied access;
- access revoked after saving.

Record each answer with its citations and have a person review them. Do not widen access, or rely on the guides for consequential decisions, until that review is done.

Source cards open ChenWeb's knowledge-document page and show the record ID and line/page/artifact references; they do not jump to the cited line. A grant admin page, a retention policy, and deployment and monitoring beyond the local loopback pilot were left out on purpose. They are separate decisions for a wider rollout.

## 2. Claude Code front end

### What is ready

Claude Code runs as itself: its own instructions, tools, MCP servers, skills, memory, settings and session history. ChenWeb sends messages, streams the replies, and passes approvals back; it stores nothing about these conversations. Claude Code uses the server's own Claude Code login (no API key) and works in `/Users/cding/Workspace`. It can do any task Claude Code can, so every route is admin-only.

On the Chat page (Development → Workspace → Chat), choosing **Claude Code** in the harness menu gives:
- **Model menu:** the models Claude Code offers the account, the same list as its `/model` picker.
- **Replies:** messages stream in, with answers rendered as Markdown (raw HTML is shown as text).
- **Tool calls:** shown as rows that expand to their input and result.
- **Approvals:** a card with Allow and Deny whenever Claude Code would ask in a terminal. Its questions appear as option buttons.
- **Stop:** ends the running reply.
- **Sessions menu:** reopens Claude Code's stored sessions with their history, including ones started in VS Code in the same folder.
- **Other harnesses:** OpenClaw, Codex and the rest behave as before.

The pieces:
- `ChenWeb/gateways/claude-code/`: a private Bun service that runs the real Claude Code through the Claude Agent SDK, used only as the connection. Its README documents the routes, settings, login and permissions.
- `ChenWeb/server/api/harnessfrontend/`: admin-only relay routes under `/api/v1/harness-frontend/:harness/...`.
- The chat page files: `chatter-01.svelte`, `harness-dialog.svelte` and `harness-conversation.ts` in `web/src/lib/components/shared-ui/`, and `web/src/lib/services/harnessFrontendService.ts`.

No database migration is involved.

### Run it

1. Start the gateway with `mise dev-claude-code-gateway` from ChenWeb.
2. ChenWeb's `mise.local.toml` (not committed) already holds `CLAUDE_CODE_GATEWAY_URL=http://127.0.0.1:4318`, a generated `CLAUDE_CODE_GATEWAY_SECRET` and `CLAUDE_CODE_WORKSPACE=/Users/cding/Workspace`.
3. Restart `mise dev` whenever those settings change.

The gateway is **not** started by `mise dev`; Claude Code appears only while it runs. The gateway removes `ANTHROPIC_API_KEY` from Claude Code's environment, because that key would override the Claude Code login, and it currently has no credit.

### Verification

On 2026-10-20:
- Gateway: 13 tests and the TypeScript check passed.
- ChenWeb: Go tests, `go vet` and `mise build-server` passed. Frontend: 9 tests, `svelte-check` and the i18n check passed.

Live checks against the real Claude Code with the Claude Code login:
- the model list loaded;
- a file write raised an approval card in the Chat page, and the file was written after approval;
- a follow-up message was answered from Claude Code's own memory;
- reopening an earlier session showed its full history.

For the browser check, ChenWeb's real handler ran on a side port with a stand-in admin user, because there is no test login. The live test for the Go relay is `go test -tags live ./api/harnessfrontend/` against a running gateway.

Those runs left a few small test sessions ("Chenweb-ui-e2e…") in Claude Code's history for the Workspace folder. They also show in VS Code's session list and can be deleted there.

### Next steps (open)

- Permission-mode switching (normal, accept edits, plan) on the Chat page.
- Attachments, the Prompt picker and the result-format menu for Claude Code tabs.
- Keeping open tabs across a page reload.
- More than one workspace folder.
- Letting a reply keep running after the browser disconnects; today it stops.
- Showing text written by Claude Code's helper agents (subagents).
- Archiving the OpenSpec changes `harness-adapter-registry` and `harness-frontend-sessions` once the work is accepted.

## 2a. Codex front end

Codex is served the same way as Claude Code: Codex keeps its own instructions (`AGENTS.md`), tools, sandbox and approval rules, memories and thread history. ChenWeb only relays. It uses the server's Codex login (`~/.codex/auth.json`) and works in `/Users/cding/Workspace`. All routes are admin-only.

The pieces:
- `ChenWeb/gateways/codex/`: a private Bun service that drives the real Codex through `codex app-server`, the interface the Codex VS Code extension uses. Its README explains how Codex's approvals and questions are shown.
- `server/api/routes.go` registers `codex` when `CODEX_GATEWAY_URL` and `CODEX_GATEWAY_SECRET` are set; `HARNESS_BY_AGENT` maps the **Codex** menu entry to it. Nothing else in ChenWeb changed.
- Contract: `ChenWeb/openspec/changes/codex-harness-frontend/`.

**Run it.** `mise dev-codex-gateway` from ChenWeb (port 4319). `mise.local.toml` already holds `CODEX_GATEWAY_URL`, a generated `CODEX_GATEWAY_SECRET` and `CODEX_WORKSPACE`. Restart `mise dev` so ChenWeb picks them up.

**Verification (2026-10-20).** Gateway: 18 tests and the TypeScript check. ChenWeb: Go tests, `go vet`, `mise build-server`, service tests, `svelte-check` and the i18n check. Live, through ChenWeb's real handler: model list, a `Shell` approval that wrote a file after Allow, and a follow-up answered from Codex's memory. Gateway live check: tool use, history and session listing. Codex's questions and the browser page were not checked live.

**Watch out.**
- `~/.codex/config.toml` sets `model = "gpt-6.1-sol"`, which Codex says this ChatGPT account cannot use. A message sent without choosing a model fails with that error; pick one from the menu.
- During testing Codex returned `429 Too Many Requests` for `gpt-5.6-sol` for several minutes, even though usage was low, while `gpt-5.6-luna` worked. The plain Codex CLI got the same 429, so this is on the account side.
- The test runs left a few short threads ("Remember the codeword …", "Reply with the word hi only.") in Codex's history for the Workspace folder; they also show in VS Code.

**Next steps (open).** Browser check of the Chat page with Codex; the Claude Code next steps (permission-mode switching, attachments, keeping tabs across reloads) apply to Codex too; MCP elicitations are declined for now.

## 3. Open decisions

- Whether the Knowledge Desk moves to the front-end model, with Pi as a full harness, or stays SemOS-owned.
- Which harness is connected next (Pi as a full harness, OpenCode, ...). Each needs its own review of how it runs, how it signs in, and what it can access before it is enabled.

## 4. Where to continue

- Design and status: `KnowledgeStore/doc-repo/devdocs/202610/2026101802-devdoc-harness-neutral-agentic-services.md`
- Plain-language intent of the Pi services: `KnowledgeStore/doc-repo/requirements/202609/2026091401-rqmt-pi-agentic-services-for-chenweb.md`
- Contracts:
  - `ChenWeb/openspec/changes/harness-adapter-registry/`
  - `ChenWeb/openspec/changes/harness-frontend-sessions/`
  - `ChenWeb/openspec/specs/agent-conversation-history/spec.md`
- Pi operations and access setup: `ChenWeb/docs/pi-agentic-services-operations.md`
- Knowledge Desk code:
  - `ChenWeb/server/api/agentservicehandler/`
  - `ThirdParty/pi/gateway/`
  - `ChenWeb/web/src/routes/home3/agent-services/+page.svelte`
- Evaluation checklist: `ChenWeb/server/api/agentservicehandler/testdata/evaluation-cases.json`
- Codex front end: `ChenWeb/gateways/codex/` (start with its README), `ChenWeb/openspec/changes/codex-harness-frontend/`
- Claude Code front end:
  - `ChenWeb/gateways/claude-code/` (start with its README)
  - `ChenWeb/server/api/harnessfrontend/`
  - `ChenWeb/web/src/lib/components/shared-ui/chatter-01.svelte`

Commits are separate in ChenWeb, `ThirdParty/pi` and KnowledgeStore. The 2026-10-20 ChenWeb commits are:
- `luzm`: migration test fix;
- `zxwq`: adapter registry;
- `rvwr` and `umou`: a Claude Code services adapter, built and then reverted;
- `tyqq`: the front end;
- `plml`: the model menu;
- `txkz`: the chat page.

The ChenWeb working copy also holds uncommitted `server/api/kbhandler` changes. They are unrelated to this work and were not part of these commits.
