# Pi Agentic Services — Pi as the agentic engine behind ChenWeb's Knowledge Desk

**Date:** 2026-09-30 \
**Scope:** How ChenWeb (SemOS) uses Pi as its "Claude Code inside": the agentic loop that answers user requests by calling ChenWeb's knowledge-base tools. Also records the implementation status verified on 2026-09-30 and the known gaps. Open this before extending the tool set, running the pilot, or replacing Pi with another harness. \
**Code root:** `ChenWeb/server/api/agentservicehandler/` (ChenWeb side), `ThirdParty/pi/gateway/` (Pi side)

## 1. Summary

ChenWeb needs more than search results. It needs an assistant that can read a user's question, decide what to look up, look it up, and answer with citations. That repeated cycle of "think → use a tool → think again → answer" is called an *agentic loop*. We do not write that loop ourselves. We use **Pi**, an existing open-source agent harness, and give it a small set of ChenWeb tools for reading the SemOS knowledge base.

Users never talk to Pi directly. They use the **Knowledge Desk** page in ChenWeb. ChenWeb checks who they are, saves the conversation, and passes each question to a small private Pi service (the *gateway*) running on the same machine. Pi runs the loop. Whenever Pi wants information, it asks ChenWeb, and ChenWeb checks the user's permissions again before answering. ChenWeb also verifies every source Pi cites before it shows or saves the answer.

Two guides are available: **Knowledge Guide** (answers questions from documents) and **Problem Diagnosis Guide** (helps investigate product, process, or documentation problems). Both are read-only.

**Status (2026-09-30):** Everything is built, committed, and passes its automated tests. It has **never been run with a real AI model or a real user**. As currently configured it cannot start, because its secrets are not set and no user has been granted knowledge access. The tools it offers are general document-search tools. Most SemOS-specific knowledge, such as the metric ontology, class contracts, and terminology, is **not yet available to Pi**.

## 2. Details

### 2.1 Where the pieces live

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

### 2.2 Request flow

```text
Browser ──(signed-in, /api/v1/agent-services/...)──▶ ChenWeb
ChenWeb ──(POST /v1/runs, Bearer PI_GATEWAY_SECRET, NDJSON stream back)──▶ Pi gateway 127.0.0.1:4317
Pi gateway: createAgentSession(...) → Pi's agent loop → model provider
Pi tool call ──(POST /api/internal/agent-tools/<tool>, Bearer PI_GATEWAY_SECRET
               + x-chenweb-run-capability, x-chenweb-run-id)──▶ ChenWeb
ChenWeb: verify capability → re-check user grant + profile scope → SQL → bounded JSON
ChenWeb ──(SSE, filtered)──▶ Browser; verifies citations, saves the turn
```

### 2.3 How Pi is used (the loop is Pi's, not ours)

`createPiSession` in `gateway/server.ts`:

1. Looks up the profile's fixed `provider` and `model` in Pi's `ModelRuntime` registry to get the model's details (API, limits, credential). Pi does **not** choose the model; ChenWeb does, through the profile. An unknown pair fails the run with "configured model is unavailable", with no fallback. It caps `maxTokens` at the profile's output limit. See *Where Pi finds models and credentials* below.
2. Builds an in-memory `SessionManager` and seeds it with the conversation history sent by ChenWeb (`seedHistory`). **Pi keeps no state between turns.** Each turn gets a fresh session, and ChenWeb is the only store of record.
3. Supplies a stub `ResourceLoader`: no extensions, skills, prompt templates, or AGENTS files. The system prompt is the profile's prompt file.
4. Calls `createAgentSession({ …, noTools: "builtin", tools: allowedTools, customTools: knowledgeTools })`. Pi's built-in shell, edit, and file tools are **off**, and the only tools Pi sees are ChenWeb's.
5. Uses `SettingsManager.inMemory({ compaction: { enabled: false }, retry: { enabled: false } })`.
6. Enforces an elapsed-time limit (abort on timer) and a cumulative output-token limit across the loop's model calls. Hitting either one aborts the session and emits a terminal `completion` status of `timed_out` or `limit_reached`.

#### 2.3.1 How ChenWeb picks a model
In the current implementation, ChenWeb picks the model by the guide's profile
and pinned to each conversation (i.e., fixed), and nothing chooses a model 
per turn.

In the future, we should implement a Model Router that picks the right model
that best fits the current turn.

Changing models during a session can be a cache issue. We will work on it 
in the future.

#### 2.3.2 Where Pi finds models and credentials

Pi doesn't choose a model. It is the app (such as ChenWeb) to decide which model to use. Pi has
its own way of defining models. ChenWeb picks a model based on the guide's profile. It then 
asks Pi to 'resolve' or to make sure Pi recognizes the model that ChenWeb picked.

Here is the code, from server.ts:144-147:
```text
const modelRuntime = await ModelRuntime.create();
const configuredModel = modelRuntime.getModel(run.profile.provider, run.profile.model);
if (!configuredModel) throw new Error("configured model is unavailable");
const model = { ...configuredModel, maxTokens: Math.min(configuredModel.maxTokens, run.profile.maxOutputTokens) };
```

How it works:

1. ChenWeb picks the model. It comes from the guide's profile in profiles.go. The default 
   is anthropic / claude-sonnet-4-5, and you can override it with PI_<GUIDE>_PROVIDER and
   PI_<GUIDE>_MODEL. Each conversation is pinned to the model it started with (see §2.8). 
   ChenWeb sends that provider and model to the gateway in the /v1/runs request.
2. Pi only looks it up. ModelRuntime.getModel(provider, id) looks up that exact pair in 
   Pi's model registry. It returns the model's details: which API to call, the context window, 
   the maximum output tokens, and the credential to use. It doesn't decide anything. If Pi 
   doesn't know the pair, the run fails with "configured model is unavailable". Nothing falls 
   back to another model.
3. The output cap is applied. maxTokens is set to the lower of the model's own limit and 
   the profile's maxOutputTokens. Later, while the loop runs, server.ts:80 lowers it further 
   as the turn's total output budget gets used up.

So the same model is used for every step of every turn, and nothing chooses a model per turn.

Pi already knows the common AI providers and their models, so most setups need no model 
configuration. You only configure what Pi doesn't know yet. A model also needs a credential 
(an API key or login) before it can actually be called.

The gateway calls `ModelRuntime.create()` with no options (`gateway/server.ts`, `createPiSession`), 
so Pi uses its defaults:

| Source | What it provides | Notes |
|---|---|---|
| Built-in catalog (in the installed `@earendil-works/pi-ai` package) | Built-in providers (`anthropic`, `openai`, `amazon-bedrock`, …) and their models | Fixed at the installed package version. The gateway does not refresh it over the network (`allowModelNetwork` defaults to `false`). Pi 0.84.2's Anthropic models: `claude-sonnet-4-5`, `claude-sonnet-4-6`, `claude-sonnet-5`, `claude-opus-4-5`…`claude-opus-5`, `claude-haiku-4-5`, `claude-fable-5`. **Not** included: `claude-opus-5-5`, `claude-sonnet-5-5` |
| `<agent dir>/models.json` | Custom providers and extra models | Only needed for a provider that isn't built in, or a model newer than the catalog. On the dev Mac it currently defines a `qwen` (DashScope) provider |
| `<agent dir>/auth.json` | Stored credentials, keyed by provider | Checked first. On the dev Mac it currently holds `deepseek` and `openai-codex` |
| Environment variables | Credentials, e.g. `ANTHROPIC_API_KEY` (also `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_OAUTH_TOKEN`) | Used when `auth.json` has no entry. The variable must be present in the **gateway process's** environment |

`<agent dir>` is `~/.pi/agent/` for whichever OS user runs the gateway, or the directory in `PI_CODING_AGENT_DIR` if set. A server deployment therefore needs its own `models.json`/`auth.json` (or environment variables) for that user. Nothing is shared with the developer's Mac.

Consequences:

- The default `anthropic` / `claude-sonnet-4-5` resolves with no configuration. It only needs `ANTHROPIC_API_KEY` (or an `auth.json` entry).
- To use a model newer than the catalog, either upgrade the Pi package or add the model to `models.json`.
- Mistakes show up late. ChenWeb doesn't check provider or model names when it starts, and gateway `GET /health` doesn't check models or credentials. A wrong name or a missing key only shows up when a turn starts.

#### 2.3.3 Sessions: ChenWeb conversations are the real sessions

A user's ongoing dialog with a guide, the equivalent of a Claude Code session, is a **conversation** in ChenWeb. It holds one or more turns. ChenWeb owns it, saves it in the database, and lists it on the Knowledge Desk so the user can reopen it later and keep going. Pi has no lasting sessions of its own. A "Pi session" lives for exactly one turn, starting from a copy of the conversation that ChenWeb gives it.

Two different things share the word "session":

| Term | Lifetime | Owner | Where it lives |
|---|---|---|---|
| **Conversation** (the real session) | Until the user deletes it | ChenWeb | `kb.agentic_conversations` + `kb.agentic_messages` (+ attempts, tool calls with full results in `kb.agentic_tool_results`, sources, feedback) |
| **Pi session** | One turn | Pi gateway | In memory (`SessionManager.inMemory()`), thrown away when the turn ends |

How one turn uses the conversation (`RunHandler.Start` in `run_handler.go`):

1. Load the conversation and its messages (`LoadResumeState`). Check that the user still has access to the guide (`ResolveVersion`) and that the pinned model still matches (`409` otherwise).
2. Load stored tool calls (`LoadToolResults`) and apply the **snapshot rule** (`FilterResumeState`, below). Answers are never hidden.
3. Create a response attempt. A database guard allows only one running attempt per conversation. Then save the new user message and an empty assistant message (`status = streaming`).
4. On the first turn, set the conversation's title from the question (`titleFromMessage`): first line, whitespace collapsed, cut at 60 characters. An existing title is never overwritten.
5. Build the history from the turns that came **before** this one (`history.go`):
   - **Whole turns only.** A turn is a user message and a `complete` assistant message with the same `attempt_id`. A question whose answer failed, stopped, or was interrupted is left out, so the model never sees two user messages in a row.
   - **Tool calls included.** Each turn carries the tool calls of its attempt that survived the snapshot rule, in call order, with their arguments and results. A result over `PI_<GUIDE>_MAX_HISTORY_TOOL_RESULT_BYTES` (default 4,096) is replaced in the history by a truncated JSON object giving its full size, its tool-call ID and `retrieve_with: get_saved_tool_result`. The stored copy stays complete.
   - **Shortened, not skipped.** Each message is cut to 15,000 UTF-16 units (ending in `…[truncated]`) so it stays under the gateway's per-message limit.
   - **Sources carried forward.** Each earlier answer ends with `[Sources cited in this answer]` and up to 8 of its cited sources (title, page, lines), so the model knows what was cited and can re-read it.
   - **Budgeted.** Turns are taken newest first until they fill the history budget (below), at most 50 turns, then sent oldest first. As a final guard the encoded request is kept under 480 KiB.
   - **Summary.** If the conversation has a rolling summary, only turns after it are candidates, and the summary goes with the run as `historySummary`. The summary is always kept as saved.
6. Send `{history, historySummary, message, profile, capability, knowledge}` to the gateway. `seedHistory` writes the history into a new in-memory Pi session, replaying each turn as the question, an assistant message with its tool calls, one tool-result message per call, and the answer. A call to a tool this run doesn't offer (for example, after the user lost every grant) is folded into the answer text as `[Earlier tool call …]`. The gateway appends the summary to the system prompt under "Summary of earlier turns in this conversation", and `session.prompt(message)` runs the loop.
7. Stream the answer back, check citations, and save the answer, sources, tool-call records and attempt outcome. The Pi session is then thrown away. Tool calls were already stored while the turn ran: the gateway sends each call's ID in `X-ChenWeb-Tool-Call-ID`, and ChenWeb's internal tool route stores the arguments, the exact response body (including error responses), and the documents it references.
8. If the turn completed, fold history in the background (`foldHistory`). If the unsummarized turns now exceed the budget, the oldest are sent with the previous summary to the gateway's `POST /v1/summaries`. The gateway summarizes them with the conversation's own provider and model, without tools, using `prompts/prompt-agent-history-summary-v1.md`. Folding continues until the remaining turns fit in half the budget. The new summary is stored on the conversation with a compare-and-set, so a stale concurrent fold is discarded. A failure is logged and changes nothing; the next turn simply drops the oldest turns.

The **history budget** (estimated tokens: four ASCII characters or one non-ASCII character per token) is `max(2000, min(cap, contextWindow / 4))`. `contextWindow` is the pinned model's context window, from the gateway's `GET /v1/models/:provider/:model` and cached for 10 minutes. `cap` is `PI_<GUIDE>_MAX_HISTORY_TOKENS`, which defaults to 32,000. The cap matters because Pi's catalog lists some models, `claude-sonnet-4-5` among them, with a 1,000,000-token window. If the gateway can't report the window, the budget is `min(cap, 16000)`.

**The snapshot rule** (requirements §11). History is a snapshot of the knowledge base at the time of each turn. `PI_HISTORY_SNAPSHOT_DUR` (hours, default 48) sets the snapshot period, measured per record: a source by its message's `created_at`, a tool result by its own `created_at`.

- Records younger than the period are shown and resent exactly as saved, even if the user has since lost access or the content changed.
- In older records, ChenWeb checks access only (`CheckDocumentAccess`, no fingerprint or version check). A source whose document is no longer accessible is removed, and so is a tool result that references any such document.
- Answer text and summaries are never removed. Removing content derived from a revoked resource is an open question (requirements §18), deliberately out of scope.
- The conversation response reports `snapshot_hours`, `removed_sources` and `removed_tool_results`. The page always shows a snapshot notice on a saved conversation, plus an access-changed notice when anything was removed.

**Retrieving a full result.** Whenever a run has knowledge tools it also gets `get_saved_tool_result` (`{tool_call_id}`). ChenWeb finds the stored call in the same conversation and user, applies the snapshot rule, and returns the stored body verbatim, or `404`. It produces no citations; citations come only from live tool calls, which settlement still checks against current content.

What the model sees of earlier turns:

| Carried into the next turn | Not carried |
|---|---|
| Recent complete turns that fit the budget, with their tool calls and (possibly shortened) results | Model reasoning (never stored) |
| A list of the sources each earlier answer cited | Failed, stopped, or interrupted answers, and the questions that led to them |
| A rolling summary of older turns, in the system prompt | Sources and tool results removed by the snapshot rule |

Consequences of this design:

- **Pi holds no state, so the gateway can restart or scale at any time.** No session is lost because ChenWeb holds the whole conversation.
- **Per-turn cost is bounded.** History, including tool results, never exceeds the budget. Older turns survive only in summary form; the summary sees question and answer text, not tool calls.
- **Users may see content they can no longer access**, inside the snapshot period. This is intended; the page says the history is a snapshot.
- **Summaries cost one extra model call.** Each fold is a call to the guide's provider. It runs after the answer has been delivered, and its usage is recorded as `pi_gateway_summary`.
- **The token count is an estimate.** No tokenizer is used. The 25 % share of the context window leaves a wide margin.
- **Model pinning ends a conversation.** After the guide's model changes, older conversations return `409` and can't continue.

### 2.4 Gateway HTTP API (loopback only, all routes need `Authorization: Bearer PI_GATEWAY_SECRET`)

| Method / path | Purpose |
|---|---|
| `GET /health` | Liveness only. Does **not** check model credentials |
| `POST /v1/runs` | Start a turn and stream NDJSON events. Body is limited to 512 KiB and validated by `validateRunRequest`. Optional `historySummary` (at most 16,000 characters) is appended to the system prompt. History assistant messages may carry `toolCalls` (`{id, name, arguments, result, isError}`), replayed as tool messages |
| `GET /v1/models/:provider/:model` | `{provider, model, contextWindow, maxTokens}` from Pi's model registry; `404` if unknown |
| `POST /v1/summaries` | `{provider, model, systemPrompt, previousSummary?, messages, maxTokens}` → `{summary}`. One-shot `completeSimple` call, no tools. `502` on failure |
| `POST /v1/runs/:runId/cancel` | Abort the run and release pending permission requests |
| `POST /v1/runs/:runId/permissions/:requestId` | `{allowed: boolean}` answers an ask-mode tool approval |

Events emitted by `normalizePiEvent` are `answer_delta`, `activity` (tool `started`/`completed`/`retrying`), `usage`, `sources`, `permission_request`, `error`, and `completion`. **Thinking or reasoning deltas are not forwarded.**

### 2.5 ChenWeb API (under `/api/v1/agent-services`, `authmiddleware.AuthMiddleware`)

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

### 2.6 Knowledge tools exposed to Pi

| Tool | Backend (`tools.go`) | Reads |
|---|---|---|
| `search_knowledge` | `kbhandler.SearchAgentKnowledge` (hybrid keyword + semantic) | `kb.search_artifacts` |
| `read_source_passages` | `readPassages`: at most 4 ranges and at most 120 lines per call | `kb.inputs` parsed lines |
| `get_artifact_details` | `artifactDetails` | `kb.search_artifacts` (payload truncated to 16 KB) |
| `get_document_context` | `documentContext` | `kb.inputs`, `kb.knowledge_store`, artifact count |
| `find_related_knowledge` | `related` | `kb.search_artifacts` anchored on an artifact or document |
| `get_saved_tool_result` | `InternalToolHandler.executeSavedResult` | `kb.agentic_tool_results` for the same conversation, under the snapshot rule (§2.3.3). Offered whenever a run has knowledge tools; no citations |

Every result item carries `knowledge_store_id`, `document_id`, `artifact_id`/`artifact_type`, `source_title`, `source_version`/`source_fingerprint`, `page`, `line_start`/`line_end`, `validation_status` (default `unreviewed`), and `untrusted_evidence: true`. The gateway wraps the tool text as `{"untrusted_evidence": true, "evidence": …}`, caps the response at `maxEvidenceBytes` (hard ceiling 128 KiB), and caps call count at `maxToolCalls`.

### 2.7 Guides
## 1. What the guides are

A guide is effectively an **app built on Pi**. Pi provides the engine (the loop, model calls, tool dispatch 
and streaming), and a guide is a configuration of that engine. In the code this configuration is a 
**profile** (`PiProfile` in [profiles.go:78-95](server/api/agentservicehandler/profiles.go#L78-L95)), 
identified by its slug.

| Part of a guide | What it controls |
|---|---|
| Prompt file | Who the assistant is and how it behaves |
| Provider and model | Which AI model it uses, and how hard it thinks |
| Allowed tools | Which ChenWeb tools it may call |
| Allowed stores and document groups | Which knowledge it may reach |
| Limits | Tool calls, time, output tokens and evidence size |
| Permission mode | Ask before each tool call, or run automatically |
| Pilot users, enabled flag, version | Who can see it and which version runs |

Every guide runs on the same gateway code and the same Pi engine. Adding a third guide means adding 
one entry to `definitions` in `profiles.go` plus one prompt file; no new engine code is needed. 
One limitation is that both guides currently get the **same five knowledge tools** (plus `get_saved_tool_result`). The allowed-tools list is 
always set to every knowledge tool (`AllowedTools: knowledgeToolNames`), so today the guides differ 
only in prompt, thinking level and limits.

Each guide has a guide-specific prompt, serving as the 'system prompt' for Pi, 
with one small addition by Pi. The gateway passes the prompt file as Pi's custom system prompt, 
through `getSystemPrompt: () => run.profile.systemPrompt` in `server.ts`. When 
Pi's `buildSystemPrompt` sees a custom prompt, it **replaces** Pi's default coding-agent prompt 
entirely. It then appends only what is turned on, and the gateway turns off appended text, 
context files and skills. The one thing Pi always appends is:

```
Current working directory: /Users/cding/Workspace/ThirdParty/pi
```

So what the model actually receives is:

- **System prompt:** the guide's prompt file, which is short (15–17 lines), plus that working-directory 
  line. The line is harmless, but it slightly contradicts the requirement not to expose internal details.
- **Tool definitions:** sent separately through the provider's tools parameter, not inside the 
  system prompt. These are the weak shared schema and one-line descriptions noted earlier.
- **Messages:** the saved history, then the user's message exactly as typed. ChenWeb adds no context.

### 2.8 Profiles (`profiles.go`, loaded at startup, so restart after changes)

| Slug | Friendly name | Default provider/model | Thinking | Max tool calls | Max elapsed | Max output tokens | Max evidence |
|---|---|---|---|---|---|---|---|
| `knowledge-guide` | Knowledge Guide | anthropic / `claude-sonnet-4-5` | medium | 12 | 90 s | 1200 | 64 KiB |
| `problem-diagnostics` | Problem Diagnosis Guide | anthropic / `claude-sonnet-4-5` | high | 16 | 120 s | 1600 | 96 KiB |

Both default to allowed store `Research` and permission mode `auto`. Every value can be overridden with `PI_KNOWLEDGE_GUIDE_*` or `PI_PROBLEM_DIAGNOSTICS_*` plus one of these suffixes: `ENABLED`, `ACTIVE_VERSION`, `PROVIDER`, `MODEL`, `PROVIDER_DISCLOSURE`, `THINKING_LEVEL`, `PERMISSION_DEFAULT`, `ALLOWED_STORES`, `ALLOWED_DOCUMENT_GROUPS`, `PILOT_USERS`, `MAX_TOOL_CALLS`, `MAX_ELAPSED_SECONDS`, `MAX_OUTPUT_TOKENS`, `MAX_EVIDENCE_BYTES`, `MAX_HISTORY_TOKENS`, `MAX_HISTORY_TOOL_RESULT_BYTES`. Only `v1` exists for each profile.

Each suffix is set separately for each guide. For example, `PI_KNOWLEDGE_GUIDE_MODEL` changes only the Knowledge Guide. Values are read once when ChenWeb starts, so restart ChenWeb after changing any of them. An invalid value stops ChenWeb from starting, except where the table says otherwise. A variable that is unset or blank keeps its default. The two list variables are the exception: setting one to an empty value gives an empty list.

| Suffix | What it controls | Format | Default | Notes |
|---|---|---|---|---|
| `ENABLED` | Whether the guide can be used at all | `true` / `false` (also `1` / `0`) | `true` | When `false`, users can neither start new conversations nor continue saved ones. This is the quick way to switch a guide off. |
| `ACTIVE_VERSION` | Which profile version new conversations use | Version name | `v1` | Only `v1` exists, so any other value stops startup. Existing conversations stay on the version they started with. |
| `PROVIDER` | Which AI provider runs the guide | Pi provider name, e.g. `anthropic` | `anthropic` | Must be a provider Pi's model runtime knows and has a credential for (see *Where Pi finds models and credentials* in §2.3). Otherwise runs fail when they start, not at ChenWeb startup. |
| `MODEL` | Which model the guide uses | Pi model ID | `claude-sonnet-4-5` | Each conversation is pinned to the model it started with. After a change, older conversations cannot continue (409 "pinned model is no longer available") and users must start new ones. |
| `PROVIDER_DISCLOSURE` | The notice telling users where their messages go | Free text | "Messages and retrieved evidence are sent to the *provider* model provider." | Shown on the Knowledge Desk page. Keep it accurate whenever `PROVIDER` changes. |
| `THINKING_LEVEL` | How much the model reasons before answering | `off`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max` | `medium` (Knowledge Guide), `high` (Problem Diagnosis) | Checked by the Pi gateway, not by ChenWeb. A wrong value doesn't stop startup, but every run fails. |
| `PERMISSION_DEFAULT` | Whether tool calls need the user's approval | `ask` or `auto` | `auto` | `ask` makes the user approve each knowledge tool call. The user can override this for each message on the page. |
| `ALLOWED_STORES` | Which knowledge stores the guide may use, by name | Comma-separated store names | `Research` | A limit, not a grant: users still need a row in `kb.agentic_knowledge_grants`. Setting it to an empty value stops startup. |
| `ALLOWED_DOCUMENT_GROUPS` | Restricts the guide to certain document types | Comma-separated `kb.inputs.type` values | Empty (no restriction) | When set, every tool call must name one of these groups, and results from other groups are dropped. |
| `PILOT_USERS` | Who may use the guide | Comma-separated ChenWeb user IDs | Empty (every signed-in user) | Users not on the list don't see the guide and cannot continue saved conversations. The list itself is never sent to the browser. |
| `MAX_TOOL_CALLS` | Most tool calls allowed in one answer | Positive integer | 12 / 16 | Must be 100 or less, or every run fails. Once reached, further tool calls fail and the model has to answer with what it has. |
| `MAX_ELAPSED_SECONDS` | Longest time one answer may take | Positive integer (seconds) | 90 / 120 | Must be 600 or less, or every run fails. Once reached, the run stops and is recorded as timed out. |
| `MAX_OUTPUT_TOKENS` | Total text the model may write for one answer, across all its steps | Positive integer (tokens) | 1200 / 1600 | Must be 100,000 or less, or every run fails. Once reached, the run stops with "reached its output limit". |
| `MAX_EVIDENCE_BYTES` | Largest single tool result passed to the model | Positive integer (bytes) | 65536 / 98304 | Must be 131072 (128 KiB) or less, or every run fails. Larger results are rejected, not cut short. |
| `MAX_HISTORY_TOKENS` | Most estimated tokens of earlier turns sent with each answer | Positive integer (tokens) | 32000 | The actual budget is the lower of this and a quarter of the model's context window, and at least 2,000 (§2.3.3). Older turns are folded into a rolling summary. |
| `MAX_HISTORY_TOOL_RESULT_BYTES` | Largest tool result carried unshortened in later turns' history | Positive integer (bytes) | 4096 | Must be 32768 or less, or ChenWeb won't start. Longer results are shortened in the history; Pi can fetch the full stored result with `get_saved_tool_result` (§2.3.3). |

Where there are two defaults, the first is the Knowledge Guide's and the second is the Problem Diagnosis Guide's.

Other environment variables: `PI_HISTORY_SNAPSHOT_DUR` (snapshot period in hours for saved history, default 48, shared by both guides; an invalid value stops startup; §2.3.3), `PI_GATEWAY_SECRET` (shared by ChenWeb and Pi), `PI_RUN_CAPABILITY_SECRET` (ChenWeb only), `PI_GATEWAY_URL` (default `http://127.0.0.1:4317`), `PI_GATEWAY_DIR` (for the mise task), `PI_GATEWAY_HOST`/`PI_GATEWAY_PORT`, and `CHENWEB_INTERNAL_URL` (Pi → ChenWeb, default `http://127.0.0.1:1323`). If either secret is missing, runs and tools fail closed.

### 2.9 Persistence (project DB, schema `kb`)

`agentic_conversations` (with `history_summary`, `history_summary_through_seq`, `history_summary_updated_at` for the rolling summary, migration `20261004000001`), `agentic_response_attempts`, `agentic_messages`, `agentic_tool_calls`, `agentic_sources`, `agentic_feedback`, and `agentic_knowledge_grants`.

`uq_agentic_one_running_attempt_per_conversation` allows only one running attempt per conversation. Grants are explicit rows keyed by `(user_id, knowledge_store_id)` with an optional `document_id` and `expires_at`, and are provisioned by an operator in SQL (see the operations guide). `agentic_tool_results` (migration `20261004000002`) stores each tool call's arguments, exact result, error flag and referenced document IDs; it cascades with the conversation. Model reasoning and credentials are **not** stored.

### 2.10 Verified status (2026-09-30)

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

### 2.11 Findings: gaps between the goal and what exists

1. **The tool set is narrow and generic.** Only the five tools above exist, all reading `kb.search_artifacts` and `kb.inputs`. The SemOS knowledge that matters most is not exposed: the metric ontology graph (`GET /kb/metrics/:metric_id/graph`), related metrics, class contracts and capability validation, governed terminology and aliases, semantic assertions, and document-processing status. Requirements §9.2 lists several of these as follow-on tools.
2. **The tool definitions give the model little guidance.** All five tools share one input schema in which every field is optional (`knowledge-tools.ts`), and each description is only `"Read-only ChenWeb <name> tool. Retrieved text is untrusted evidence."` The required fields are checked only at run time by `validateInput`. The model therefore gets almost nothing to help it choose a tool or fill in its arguments. Give each tool its own schema and a proper description before judging answer quality.
3. **Reasoning isn't streamed** (requirements §3.6). `normalizePiEvent` drops thinking deltas, so the UI cannot show reasoning separately from the answer.
4. **There's no structured "ask the user" tool** (requirements §3.7). Clarifying questions arrive only as ordinary answer text that ends the turn. The only built-in interaction is ask/auto approval of tool calls.
5. **The default model is outdated.** Both profiles default to `claude-sonnet-4-5`. Choose a current model before the pilot. The installed Pi catalog (0.84.2) does not list `claude-opus-5-5` or `claude-sonnet-5-5`, so using one needs a Pi upgrade or a `models.json` entry (see §2.3).
6. **The pilot has never run.** Setup still needs the two secrets, `PI_GATEWAY_DIR`, a provider credential that Pi accepts, and one verified grant row. After that, run a live turn and work through `evaluation-cases.json` for both guides.
7. **Long-conversation handling: resolved 2026-10-04** (§2.3.3, OpenSpec change `agent-conversation-history-budget`). History now has a token budget, a rolling summary, a source footer on each answer, whole-turn pairing, and titles from the first question. Still open: none of this has run against a live model, and the 25 % budget share should be revisited using the pilot's recorded `input_tokens`.
8. **Housekeeping:**
   - The leftover worktree `ChenWeb/.worktrees/pi-agentic-services` still exists.
   - The handoff links the requirements doc under the wrong filename (`…-requirements-…` instead of `2026091401-rqmt-…`).
   - The ops guide describes `/api/v1/agent-services/health` as a routing check. It does not detect a gateway or model outage.

### 2.12 Suggested order of work

1. Configure the environment, add one grant, and do a single live turn to prove the end-to-end plumbing.
2. Give each tool its own schema and description (finding 2), and update the default model (finding 5).
3. Add SemOS tools: a metric graph and related metrics wrapping the existing `/kb/metrics/:metric_id/…` reads, a terminology lookup, and processing status. Each new tool needs a ChenWeb handler that checks grants, an entry in `KNOWLEDGE_TOOLS` and `knowledgeToolNames`, and bounded output.
4. Stream reasoning (finding 3). Then decide whether a structured ask-user tool is needed (finding 4).

## 3. Known limitations

These are by design for the proof of concept:

- The gateway binds to loopback only, and nothing has been deployed to production (`onto.bzton.cn`).
- Every tool is read-only. Tools that change records are out of scope, as are shell, file, and web access.
- Knowledge grants are managed in SQL by an operator. There is no admin page.
- There is no automatic retention job. Conversations last until the user deletes them.
- Source cards open the document page and show line and page references, but they do not jump to the cited line.
- The real session is the ChenWeb conversation (§2.3.3). Each turn starts a new, one-turn Pi session with a budgeted text history and a rolling summary seeded back in. Nothing is kept warm between turns, and tool results aren't carried over (only a list of cited sources).
- Profiles are defined in Go code with environment-variable overrides. Only `v1` exists, and there is no system for publishing new profile versions or testing them with selected users.
