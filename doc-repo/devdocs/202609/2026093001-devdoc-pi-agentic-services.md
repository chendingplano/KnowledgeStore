# Pi Agentic Services — Pi as the agentic engine behind ChenWeb's Knowledge Desk

**Date:** 2026-09-30 \
**Scope:** How ChenWeb (SemOS) uses Pi as its "Claude Code inside": the agentic loop that answers user requests by calling ChenWeb's knowledge-base tools. Also records the implementation status verified on 2026-09-30 and the known gaps. Open this before extending the tool set, running the pilot, or replacing Pi with another harness. \
**Code root:** `ChenWeb/server/api/agentservicehandler/` (ChenWeb side), `ThirdParty/pi/gateway/` (Pi side)

## Summary

ChenWeb needs more than search results. It needs an assistant that can read a user's question, decide what to look up, look it up, and answer with citations. That repeated cycle of "think → use a tool → think again → answer" is called an *agentic loop*. We do not write that loop ourselves. We use **Pi**, an existing open-source agent harness, and give it a small set of ChenWeb tools for reading the SemOS knowledge base.

Users never talk to Pi directly. They use the **Knowledge Desk** page in ChenWeb. ChenWeb checks who they are, saves the conversation, and passes each question to a small private Pi service (the *gateway*) running on the same machine. Pi runs the loop. Whenever Pi wants information, it asks ChenWeb, and ChenWeb checks the user's permissions again before answering. ChenWeb also verifies every source Pi cites before it shows or saves the answer.

Two guides are available: **Knowledge Guide** (answers questions from documents) and **Problem Diagnosis Guide** (helps investigate product, process, or documentation problems). Both are read-only.

**Status (2026-09-30):** Everything is built, committed, and passes its automated tests. It has **never been run with a real AI model or a real user**. As currently configured it cannot start, because its secrets are not set and no user has been granted knowledge access. The tools it offers are general document-search tools. Most SemOS-specific knowledge, such as the metric ontology, class contracts, and terminology, is **not yet available to Pi**.

## Details

### Where the pieces live

| Piece | Location | Role |
|---|---|---|
| Requirements | `KnowledgeStore/doc-repo/requirements/202609/2026091401-rqmt-pi-agentic-services-for-chenweb.md` | Intent (doc-2026091401) |
| Handoff | `KnowledgeStore/doc-repo/hand-offs/202609/2026091501-handoff-pi-agentic-services-handoff.md` | Implementation handoff, 2026-09-15 |
| Operations guide | `ChenWeb/docs/pi-agentic-services-operations.md` | Setup, grants, troubleshooting, evaluation |
| ChenWeb backend | `ChenWeb/server/api/agentservicehandler/` | Profiles, conversation APIs, run bridge, knowledge tools, persistence |
| Route wiring | `ChenWeb/server/api/routes.go` (around line 280) | Profile registry, capability signer, route registration |
| Pi gateway | `ThirdParty/pi/gateway/` (`server.ts`, `knowledge-tools.ts`, `permission-gate.ts`, `session-registry.ts`, `types.ts`) | Runs Pi sessions; proxies tool calls to ChenWeb |
| Prompts | `ChenWeb/prompts/prompt-agent-knowledge-guide-v1.md`, `prompt-agent-problem-diagnosis-v1.md` | System prompts (override the directory with `PROMPT_DIR`) |
| Migrations | `ChenWeb/project_migrations/20260914000001_*`, `20260914000002_*`, `20260915000001_*` | Agentic tables, grants, one-running-turn guard |
| UI | `ChenWeb/web/src/routes/home3/agent-services/+page.svelte` | Knowledge Desk (Workspace → Knowledge Desk) |
| Eval set | `ChenWeb/server/api/agentservicehandler/testdata/evaluation-cases.json` | Pilot scenarios for both guides |
| Launcher | `mise dev-agent-services` (ChenWeb) | Runs API + web + `mise dev-agent-gateway` together |

### Request flow

```text
Browser ──(signed-in, /api/v1/agent-services/...)──▶ ChenWeb
ChenWeb ──(POST /v1/runs, Bearer PI_GATEWAY_SECRET, NDJSON stream back)──▶ Pi gateway 127.0.0.1:4317
Pi gateway: createAgentSession(...) → Pi's agent loop → model provider
Pi tool call ──(POST /api/internal/agent-tools/<tool>, Bearer PI_GATEWAY_SECRET
               + x-chenweb-run-capability, x-chenweb-run-id)──▶ ChenWeb
ChenWeb: verify capability → re-check user grant + profile scope → SQL → bounded JSON
ChenWeb ──(SSE, filtered)──▶ Browser; verifies citations, saves the turn
```

### How Pi is used (the loop is Pi's, not ours)

`createPiSession` in `gateway/server.ts`:

- Resolves the model through Pi's `ModelRuntime` using the profile's `provider` and `model`. It caps `maxTokens` at the profile's output limit.
- Builds an in-memory `SessionManager` and seeds it with the conversation history sent by ChenWeb (`seedHistory`). **Pi keeps no state between turns.** Each turn gets a fresh session, and ChenWeb is the only store of record.
- Supplies a stub `ResourceLoader`: no extensions, skills, prompt templates, or AGENTS files. The system prompt is the profile's prompt file.
- Calls `createAgentSession({ …, noTools: "builtin", tools: allowedTools, customTools: knowledgeTools })`. Pi's built-in shell, edit, and file tools are **off**, and the only tools Pi sees are ChenWeb's.
- Uses `SettingsManager.inMemory({ compaction: { enabled: false }, retry: { enabled: false } })`.
- Enforces an elapsed-time limit (abort on timer) and a cumulative output-token limit across the loop's model calls. Hitting either one aborts the session and emits a terminal `completion` status of `timed_out` or `limit_reached`.

### Gateway HTTP API (loopback only, all routes need `Authorization: Bearer PI_GATEWAY_SECRET`)

| Method / path | Purpose |
|---|---|
| `GET /health` | Liveness only. Does **not** check model credentials |
| `POST /v1/runs` | Start a turn and stream NDJSON events. Body is limited to 128 KiB and validated by `validateRunRequest` |
| `POST /v1/runs/:runId/cancel` | Abort the run and release pending permission requests |
| `POST /v1/runs/:runId/permissions/:requestId` | `{allowed: boolean}` answers an ask-mode tool approval |

Events emitted by `normalizePiEvent` are `answer_delta`, `activity` (tool `started`/`completed`/`retrying`), `usage`, `sources`, `permission_request`, `error`, and `completion`. **Thinking or reasoning deltas are not forwarded.**

### ChenWeb API (under `/api/v1/agent-services`, `authmiddleware.AuthMiddleware`)

| Method / path | Handler |
|---|---|
| `GET ""` | List services visible to the user (pilot-user lists are not exposed) |
| `GET /health` | ChenWeb routing health (not gateway or model health) |
| `GET /conversations` | User's conversations |
| `POST /:slug/conversations` | Create a conversation, pinned to the slug, profile version, and model |
| `GET /conversations/:id` | Read it. Rechecks each cited source and hides answers whose sources were revoked or changed |
| `DELETE /conversations/:id` | Delete (cascades) |
| `POST /conversations/:id/messages/:messageId/feedback` | Helpful/unhelpful |
| `POST /conversations/:id/runs` | Start a turn (idempotent; `409` if a turn is already active) |
| `POST /conversations/:id/runs/:runId/cancel` | Stop |
| `POST /conversations/:id/runs/:runId/permissions/:requestId` | Approve or deny a tool call |

Internal tool routes: `POST /api/internal/agent-tools/<tool>`. They are registered outside `/api/v1`, need the gateway secret plus a signed short-lived run capability (`PI_RUN_CAPABILITY_SECRET`, at least 32 bytes), and must never be publicly proxied.

### Knowledge tools exposed to Pi

| Tool | Backend (`tools.go`) | Reads |
|---|---|---|
| `search_knowledge` | `kbhandler.SearchAgentKnowledge` (hybrid keyword + semantic) | `kb.search_artifacts` |
| `read_source_passages` | `readPassages`: at most 4 ranges and at most 120 lines per call | `kb.inputs` parsed lines |
| `get_artifact_details` | `artifactDetails` | `kb.search_artifacts` (payload truncated to 16 KB) |
| `get_document_context` | `documentContext` | `kb.inputs`, `kb.knowledge_store`, artifact count |
| `find_related_knowledge` | `related` | `kb.search_artifacts` anchored on an artifact or document |

Every result item carries `knowledge_store_id`, `document_id`, `artifact_id`/`artifact_type`, `source_title`, `source_version`/`source_fingerprint`, `page`, `line_start`/`line_end`, `validation_status` (default `unreviewed`), and `untrusted_evidence: true`. The gateway wraps the tool text as `{"untrusted_evidence": true, "evidence": …}`, caps the response at `maxEvidenceBytes` (hard ceiling 128 KiB), and caps call count at `maxToolCalls`.

### Profiles (`profiles.go`, loaded at startup, so restart after changes)

| Slug | Friendly name | Default provider/model | Thinking | Max tool calls | Max elapsed | Max output tokens | Max evidence |
|---|---|---|---|---|---|---|---|
| `knowledge-guide` | Knowledge Guide | anthropic / `claude-sonnet-4-5` | medium | 12 | 90 s | 1200 | 64 KiB |
| `problem-diagnostics` | Problem Diagnosis Guide | anthropic / `claude-sonnet-4-5` | high | 16 | 120 s | 1600 | 96 KiB |

Both default to allowed store `Research` and permission mode `auto`. Every value can be overridden with `PI_KNOWLEDGE_GUIDE_*` or `PI_PROBLEM_DIAGNOSTICS_*` plus one of these suffixes: `ENABLED`, `ACTIVE_VERSION`, `PROVIDER`, `MODEL`, `PROVIDER_DISCLOSURE`, `THINKING_LEVEL`, `PERMISSION_DEFAULT`, `ALLOWED_STORES`, `ALLOWED_DOCUMENT_GROUPS`, `PILOT_USERS`, `MAX_TOOL_CALLS`, `MAX_ELAPSED_SECONDS`, `MAX_OUTPUT_TOKENS`, `MAX_EVIDENCE_BYTES`. Only `v1` exists for each profile.

Other environment variables: `PI_GATEWAY_SECRET` (shared by ChenWeb and Pi), `PI_RUN_CAPABILITY_SECRET` (ChenWeb only), `PI_GATEWAY_URL` (default `http://127.0.0.1:4317`), `PI_GATEWAY_DIR` (for the mise task), `PI_GATEWAY_HOST`/`PI_GATEWAY_PORT`, and `CHENWEB_INTERNAL_URL` (Pi → ChenWeb, default `http://127.0.0.1:1323`). If either secret is missing, runs and tools fail closed.

### Persistence (project DB, schema `kb`)

`agentic_conversations`, `agentic_response_attempts`, `agentic_messages`, `agentic_tool_calls`, `agentic_sources`, `agentic_feedback`, and `agentic_knowledge_grants`.

`uq_agentic_one_running_attempt_per_conversation` allows only one running attempt per conversation. Grants are explicit rows keyed by `(user_id, knowledge_store_id)` with an optional `document_id` and `expires_at`, and are provisioned by an operator in SQL (see the operations guide). Tool arguments and passages, model reasoning, and credentials are **not** stored.

### Verified status (2026-09-30)

| Check | Result |
|---|---|
| ChenWeb commits | 7 feature/docs commits on 2026-09-15 (`384c122`…`7e0ac0d`). Later touched by `fd7c8b0` (shared AI transports, 09-20) and `fd470cf` (tenant_id→user_id, 09-28). No uncommitted changes in this area |
| Pi commits | `2aab956`, `645aad0`, `0f6c4c1` (09-15). Working copy clean |
| `go test` / `go vet ./server/api/agentservicehandler/` | Pass |
| `bun test gateway` / `bun run check` in `ThirdParty/pi` | 16/16 pass; `tsc` clean |
| Migrations on `miner` | Applied; all 7 `kb.agentic_*` tables exist |
| Rows in `kb.agentic_*` on `miner` | **0 in every table**: no conversation has ever run, and no grant exists |
| `PI_*` variables in ChenWeb's `mise env` | **None set**, so the gateway cannot start and runs fail closed |
| Live model pilot / evaluation set | **Not run** |

### Findings: gaps between the goal and what exists

1. **The tool set is narrow and generic.** Only the five tools above exist, all reading `kb.search_artifacts` and `kb.inputs`. The SemOS knowledge that matters most is not exposed: the metric ontology graph (`GET /kb/metrics/:metric_id/graph`), related metrics, class contracts and capability validation, governed terminology and aliases, semantic assertions, and document-processing status. Requirements §9.2 lists several of these as follow-on tools.
2. **The tool definitions give the model little guidance.** All five tools share one input schema in which every field is optional (`knowledge-tools.ts`), and each description is only `"Read-only ChenWeb <name> tool. Retrieved text is untrusted evidence."` The required fields are checked only at run time by `validateInput`. The model therefore gets almost nothing to help it choose a tool or fill in its arguments. Give each tool its own schema and a proper description before judging answer quality.
3. **Reasoning isn't streamed** (requirements §3.6). `normalizePiEvent` drops thinking deltas, so the UI cannot show reasoning separately from the answer.
4. **There's no structured "ask the user" tool** (requirements §3.7). Clarifying questions arrive only as ordinary answer text that ends the turn. The only built-in interaction is ask/auto approval of tool calls.
5. **The default model is outdated.** Both profiles default to `claude-sonnet-4-5`. Choose a current model (and confirm Pi's `ModelRuntime` knows it) before the pilot.
6. **The pilot has never run.** Setup still needs the two secrets, `PI_GATEWAY_DIR`, a provider credential that Pi accepts, and one verified grant row. After that, run a live turn and work through `evaluation-cases.json` for both guides.
7. **Housekeeping:**
   - The leftover worktree `ChenWeb/.worktrees/pi-agentic-services` still exists.
   - The handoff links the requirements doc under the wrong filename (`…-requirements-…` instead of `2026091401-rqmt-…`).
   - The ops guide describes `/api/v1/agent-services/health` as a routing check. It does not detect a gateway or model outage.

### Suggested order of work

1. Configure the environment, add one grant, and do a single live turn to prove the end-to-end plumbing.
2. Give each tool its own schema and description (finding 2), and update the default model (finding 5).
3. Add SemOS tools: a metric graph and related metrics wrapping the existing `/kb/metrics/:metric_id/…` reads, a terminology lookup, and processing status. Each new tool needs a ChenWeb handler that checks grants, an entry in `KNOWLEDGE_TOOLS` and `knowledgeToolNames`, and bounded output.
4. Stream reasoning (finding 3). Then decide whether a structured ask-user tool is needed (finding 4).

## Known limitations

These are by design for the proof of concept:

- The gateway binds to loopback only, and nothing has been deployed to production (`onto.bzton.cn`).
- Every tool is read-only. Tools that change records are out of scope, as are shell, file, and web access.
- Knowledge grants are managed in SQL by an operator. There is no admin page.
- There is no automatic retention job. Conversations last until the user deletes them.
- Source cards open the document page and show line and page references, but they do not jump to the cited line.
- Each turn starts a new Pi session with the saved history seeded back in. Nothing is kept warm between turns, and compaction is disabled, so long conversations send their full history each turn.
- Profiles are defined in Go code with environment-variable overrides. Only `v1` exists, and there is no system for publishing new profile versions or testing them with selected users.
