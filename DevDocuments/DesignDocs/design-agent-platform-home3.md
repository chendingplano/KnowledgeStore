# Design: Managed Agent Platform (home3)

**Status:** Draft · **Owner:** cding · **Created:** 2026-04-22
**Reference inspiration (concept only, not code):** https://github.com/multica-ai/multica
**Location:** `ChenWeb/web/src/routes/home3` (frontend) + `ChenWeb/server` (backend) + `shared/go` (shared utilities)

---

## 1. Motivation

We want an internal, commercially-distributable managed-agent platform: a Linear/Jira-style board where humans and coding agents share a queue of issues. Issues can be assigned to a human *or* an agent; when assigned to an agent, ChenWeb's backend executes the work in a server-side sandbox, streams progress to the board in real time, and captures the resulting artifacts (diffs, logs, artifacts) back into the issue.

Multica is an excellent reference for the product shape (workspaces → agents → issues → kanban → skills → runtimes), but its *modified* Apache-2.0 license forbids embedding or redistributing the code in a commercial product. We therefore build a concept-equivalent, native to our stack (Go + shared/go + Kratos + goose + SvelteKit), not a fork.

### 1.1 Goals (MVP)

1. **Workspaces** — multi-tenant isolation (one user may belong to many).
2. **Agents** — named agent profiles (e.g. "Claude-Backend", "Codex-Frontend") with a runtime binding and an instruction prompt.
3. **Issues** — kanban board with status (Backlog / Todo / In-Progress / In-Review / Done), priority, assignee (human or agent), comments.
4. **Task execution** — assigning an issue to an agent enqueues a task; a server-side runtime picks it up, runs the agent, streams progress via WebSocket, and writes back status + artifacts.
5. **home3 UI** — SvelteKit views under `/home3` fitting the existing rail / content / shelf shell.

### 1.2 Non-Goals (v1, deferred to later milestones)

- Reusable compiled "skills" (Multica's skill packages). Simple per-agent instruction strings cover v1.
- Autopilots (scheduled/recurring agent triggers).
- Email/notification service, invitation flows.
- Inbox aggregation across workspaces.
- External CLI daemon (local-user-machine) — v1 runs agents server-side only.
- Billing / usage metering.
- Public marketplace of skills.

### 1.3 Explicit License Boundary

We read Multica's README and license, but we do **not** copy code, schema SQL, migration ordering, prompts, proto files, UI components, or configuration files. This document describes our own design; any resemblance is at the level of conventional nouns (workspace, issue, agent, task) and generic REST shapes.

---

## 2. High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    SvelteKit  (ChenWeb/web)                      │
│  home3/+page.svelte  → home3 rail routes kanban/agents/settings  │
│         │                                                         │
│         ├── REST (fetch)  ─┐                                      │
│         └── WebSocket      │                                      │
└────────────────────────────┼──────────────────────────────────────┘
                             │
┌────────────────────────────▼──────────────────────────────────────┐
│                    Go Backend  (ChenWeb/server)                   │
│  routes/agentplatform → handlers → services → stores → PG         │
│         │                                                          │
│         ├── auth: shared/go/authmiddleware  (Kratos session)       │
│         ├── db:   shared/go/api/databaseutil (PG_DB_Project pool)  │
│         ├── log:  shared/go/api/loggerutil                         │
│         ├── llm:  shared/go/api/llm (+ new agentrun sub-pkg)       │
│         └── migrations: project_migrations/*_agent_platform_*.sql  │
│                                                                    │
│    agentrun worker pool ──► sandbox executor ──► CLI runtime       │
│            ▲                     (docker run)         │            │
│            └── pubsub/WS ◄────── progress stream  ◄───┘            │
└────────────────────────────────────────────────────────────────────┘
                             │
                             ▼
              ┌──────────────────────────────┐
              │  Sandbox containers (per     │
              │  task): claude-code, codex,  │
              │  openclaw, opencode — mount  │
              │  issue workdir, run CLI,     │
              │  tail output                 │
              └──────────────────────────────┘
```

Key decisions:

- **Single backend process.** No sidecar daemon. The worker pool runs inside the existing ChenWeb Go server.
- **Docker-based sandboxing.** Each task run spawns a container with a per-issue working directory mounted. No user code runs in-process with our server.
- **LLM utility is Go.** Per your preference. New package: `shared/go/api/llm/agentrun/` providing `Runner` abstraction (see §7).
- **WebSocket over existing Echo server.** We add one endpoint `/ws/agent-platform` that fan-outs per-workspace task events. If ChenWeb already has a WS framework, we reuse it.

---

## 3. Data Model

All tables live in `project_migrations/` and are owned by ChenWeb (per CLAUDE.md: project-level tables go in `database.CreateTables(...)`). Naming prefix: `ap_` (agent platform) to avoid collisions.

### 3.1 Tables

| Table | Purpose |
|---|---|
| `ap_workspace` | Tenant boundary. Owner + slug. |
| `ap_workspace_member` | User ↔ workspace membership + role (owner / member / viewer). |
| `ap_agent` | Agent profile (name, avatar, runtime kind, instructions, model). |
| `ap_project` | Optional grouping for issues (Linear-style). |
| `ap_issue` | Issue (title, description, status, priority, assignee_user_id or assignee_agent_id, project_id, issue_number). |
| `ap_comment` | Comment thread on issue (author = user or agent). |
| `ap_task_run` | One execution attempt of an issue by an agent. |
| `ap_task_event` | Append-only progress events (stdout/stderr/status/heartbeat). |
| `ap_artifact` | File produced by a task run (diff, log file, generated doc). |

### 3.2 Key Columns Sketch

```sql
-- ap_issue
id                uuid primary key
workspace_id      uuid not null references ap_workspace(id)
project_id        uuid null references ap_project(id)
issue_number      int  not null     -- monotonic per workspace, e.g. CHE-17
title             text not null
description       text not null default ''
status            text not null check (status in ('backlog','todo','in_progress','in_review','done','canceled'))
priority          smallint not null default 0   -- 0=none,1=low,2=medium,3=high,4=urgent
assignee_user_id  uuid null
assignee_agent_id uuid null
created_by        uuid not null
created_at        timestamptz not null default now()
updated_at        timestamptz not null default now()
unique (workspace_id, issue_number)
check (assignee_user_id is null or assignee_agent_id is null)  -- at most one
```

```sql
-- ap_task_run
id              uuid primary key
issue_id        uuid not null references ap_issue(id) on delete cascade
agent_id        uuid not null references ap_agent(id)
status          text not null check (status in ('queued','claimed','running','succeeded','failed','canceled'))
queued_at       timestamptz not null default now()
claimed_at      timestamptz null
started_at      timestamptz null
finished_at     timestamptz null
exit_code       int null
error_message   text null
runner_version  text null                 -- e.g. "claude-code@1.2.3"
workdir_path    text null                 -- absolute path inside server
lease_expires_at timestamptz null         -- for crash-recovery reclaim
```

Note: field name `description` protected — aligns with CLAUDE.md rule on reserved keywords.

### 3.3 Migrations

Per goose convention used in `project_migrations/`:

```
project_migrations/
  20260501000001_create_agent_platform_tables.sql
  20260501000002_seed_default_workspace.sql
```

All migrations run from `database.CreateTables(...)` on server start (CLAUDE.md rule).

---

## 4. Backend API Surface

### 4.1 Module Layout

```
ChenWeb/server/
├── api/
│   └── agentplatform/            # new
│       ├── handler_workspace.go
│       ├── handler_agent.go
│       ├── handler_issue.go
│       ├── handler_task.go
│       ├── handler_ws.go
│       └── routes.go             # wires to Echo
├── stores/
│   └── agentplatform/            # new — DB access layer
│       ├── workspace.go
│       ├── agent.go
│       ├── issue.go
│       └── task.go
└── services/
    └── agentplatform/            # new — business logic
        ├── issue_service.go
        ├── task_service.go       # enqueue, claim, lifecycle guards
        └── worker.go             # background worker pool
```

And in shared:

```
shared/go/api/llm/agentrun/       # new — reusable across projects
├── runner.go                     # Runner interface
├── runner_claude.go              # Claude Code CLI runner
├── runner_codex.go               # Codex runner
├── runner_openclaw.go            # OpenClaw runner
├── runner_opencode.go            # OpenCode runner
├── sandbox_docker.go             # docker-based executor
└── event.go                      # event types
```

### 4.2 REST endpoints (v1)

All endpoints are workspace-scoped and require auth via `authmiddleware.JWTAuth`.

| Method | Path | Purpose |
|---|---|---|
| `GET`  | `/api/v1/workspaces` | List workspaces I belong to |
| `POST` | `/api/v1/workspaces` | Create workspace |
| `GET`  | `/api/v1/w/:slug/agents` | List agents |
| `POST` | `/api/v1/w/:slug/agents` | Create agent |
| `PATCH`| `/api/v1/w/:slug/agents/:id` | Edit agent |
| `DELETE`| `/api/v1/w/:slug/agents/:id` | Archive agent |
| `GET`  | `/api/v1/w/:slug/issues` | List issues (filter: status, project, assignee) |
| `POST` | `/api/v1/w/:slug/issues` | Create issue |
| `GET`  | `/api/v1/w/:slug/issues/:num` | Get issue detail |
| `PATCH`| `/api/v1/w/:slug/issues/:num` | Edit issue (status, assignee, etc.) |
| `POST` | `/api/v1/w/:slug/issues/:num/assign-agent` | Assign to agent (enqueues task) |
| `POST` | `/api/v1/w/:slug/issues/:num/comments` | Add comment |
| `GET`  | `/api/v1/w/:slug/issues/:num/runs` | List task runs |
| `GET`  | `/api/v1/w/:slug/runs/:id` | Get task run detail |
| `POST` | `/api/v1/w/:slug/runs/:id/cancel` | Cancel running task |
| `GET`  | `/api/v1/w/:slug/runs/:id/events` | Paginated event log (post-hoc) |

Kanban-friendly batch update:

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/api/v1/w/:slug/issues/bulk-move` | Reorder / restatus a set of issues (for drag-drop) |

### 4.3 WebSocket

Single endpoint: `GET /ws/agent-platform?workspace=<slug>` — authenticated via same session cookie.

Server pushes JSON events tagged by workspace. Client filters by topic:

```json
{ "type":"task.event", "run_id":"…", "kind":"stdout", "payload":"…", "at":"…" }
{ "type":"task.status","run_id":"…", "status":"running", "at":"…" }
{ "type":"issue.updated","issue_id":"…", "fields":{"status":"done"} }
{ "type":"comment.created","issue_id":"…", "comment_id":"…", "author_kind":"agent" }
```

In-process pubsub (channels) is fine for v1; we can swap to Redis later if we scale beyond one server process.

---

## 5. Execution Subsystem

### 5.1 Lifecycle

```
queued → claimed → running → succeeded | failed | canceled
```

Guards:
- `claim` requires `status=queued` and sets `lease_expires_at = now() + 60s`.
- Worker renews lease every 30s while running.
- A sweeper reclaims rows where `lease_expires_at < now() and status in ('claimed','running')` → `status='failed', error_message='lease expired'`.

### 5.2 Runner interface (Go, in `shared/go/api/llm/agentrun`)

```go
type Runner interface {
    // Kind returns a stable identifier, e.g. "claude-code","codex","openclaw","opencode".
    Kind() string

    // Prepare creates the workdir, writes the prompt file, initializes git if needed.
    Prepare(ctx context.Context, spec TaskSpec) (WorkDir, error)

    // Run executes the agent CLI inside a sandbox and streams events.
    // It MUST respect ctx cancellation.
    Run(ctx context.Context, wd WorkDir, spec TaskSpec, out chan<- Event) error

    // Collect gathers artifacts (diff, logs) into ap_artifact rows.
    Collect(ctx context.Context, wd WorkDir) ([]Artifact, error)
}
```

Concrete implementations wrap CLIs we already have in the workspace:
- `runner_claude.go` → Claude Code CLI (`claude`)
- `runner_codex.go` → `codex`
- `runner_openclaw.go` → OpenClaw (already in `Workspace/openclaw/`)
- `runner_opencode.go` → OpenCode (already in `Workspace/opencode/`)

### 5.3 Sandbox

Each `Run` call executes inside a container:

```
docker run --rm \
  --network=none \                  # explicit opt-in per-agent
  --memory=2g --cpus=2 \
  --user=1000:1000 \
  -v /srv/agentplatform/workdirs/<run_id>:/workspace:rw \
  -v /srv/agentplatform/secrets/<run_id>:/run/secrets:ro \
  chenweb/agentrun-<kind>:<version> \
  /entrypoint.sh
```

- Images built ahead-of-time; we version them (`chenweb/agentrun-claude:v1`).
- Workdir lifecycle: create on `Prepare`, purge on `Collect + N hours` retention.
- Network policy is per-agent: network-disabled by default; opt-in per agent for tasks that need external API access.
- Secrets (API keys for Claude, OpenAI, etc.) are written per-run into a tmpfs-mounted file and deleted after run.

### 5.4 Worker pool

- `services/agentplatform/worker.go` spawns N goroutines (configurable).
- Each goroutine claims a task (`UPDATE … RETURNING` + `FOR UPDATE SKIP LOCKED`) and drives it end-to-end.
- Events flow: `Runner.Run → chan Event → persistence (ap_task_event) + pubsub → WS`.

### 5.5 LLM utility module

`shared/go/api/llm/agentrun/` is a new sub-package of the existing `shared/go/api/llm/`. Public surface is just the `Runner` interface, `TaskSpec`, `Event`, and a `NewRunnerByKind(kind string) (Runner, error)` factory. Other projects (e.g. `tax/`) can import and build their own agent-driven workflows on top of the same primitives.

---

## 6. Frontend: home3

### 6.1 Information architecture

`home3/+page.svelte` already provides a rail + content + shelf shell. We add new rail items and their view components:

| Rail item | View component (new) | Description |
|---|---|---|
| **Board** | `kanban-board-view.svelte` | The default landing view — drag-drop kanban across 5 statuses, grouped by status column. |
| **Issues** | `issues-list-view.svelte` | Dense table with filters (status, assignee, priority, project). |
| **Agents** | `agents-view.svelte` | List + create/edit agent profiles; shows runtime kind, model, last run. |
| **Projects** | `projects-view.svelte` | Simple list of projects; clicking filters the board. |
| **Settings → Workspace** | `workspace-settings-view.svelte` | Members, roles, workspace slug. |

The context shelf on the right shows contextual detail for the selected object (selected issue card → issue detail + run log stream; selected agent → recent runs).

### 6.2 Components (new, under `web/src/lib/components/home3/`)

```
kanban-board-view.svelte           # columns + KanbanCard
kanban-column.svelte
kanban-card.svelte
issues-list-view.svelte
issue-detail-panel.svelte          # used in the shelf
agents-view.svelte
agent-card.svelte
agent-edit-modal.svelte
projects-view.svelte
workspace-settings-view.svelte
run-log-stream.svelte              # WebSocket-bound live log
agentplatform-client.ts            # REST + WS helpers
agentplatform-store.svelte.ts      # Svelte 5 runes store
```

We reuse existing styles/tokens from `+page.svelte` and the existing rail/shelf pattern — no new design language.

### 6.3 Client data flow

- `agentplatform-store.svelte.ts` holds workspace-scoped state using Svelte 5 `$state` runes.
- REST calls from `agentplatform-client.ts` with `credentials: 'same-origin'` (same pattern as `handleLogout`).
- On mount, the store opens a WebSocket and routes events into the reactive state. Issues and task runs update in real time.

### 6.4 Drag-drop on kanban

- Use **`@dnd-kit-svelte`** — already present in [web/package.json](../../../ChenWeb/web/package.json) as a devDependency (`@dnd-kit-svelte/svelte`, `@dnd-kit/abstract`, `@dnd-kit/helpers`). No new package needed.
- Optimistic update: move card in local state, POST `/issues/bulk-move`, revert on error.
- `@dnd-kit-svelte` handles keyboard accessibility, touch, and cross-column drop zones out of the box — better than rolling our own over native HTML5 drag events.

---

## 7. Auth & Security

- **Authn:** re-use `shared/go/authmiddleware.JWTAuth`. No separate multica-style sessions or PATs.
- **Authz:** simple RBAC in `services/agentplatform/authz.go`:
  - `owner` — full write on workspace.
  - `member` — write issues/comments, run tasks.
  - `viewer` — read-only.
- **Multi-tenant:** every store query filters by `workspace_id` derived from the verified membership row. Queries without a `workspace_id` filter should fail lint (code review rule).
- **Sandbox:** see §5.3. No agent output reaches the server process as trusted input. Logs are treated as untrusted text (escape on render).
- **Secrets:** agent-side API keys are workspace-scoped rows in an encrypted column (AES-GCM, key from env). Never logged.
- **Reserved keywords:** per CLAUDE.md, we protect SQL column names (`description`, `status`, `priority` are all fine in PG; any other additions get reviewed).
- **Logging:** every request and every task state transition logs via `shared/go/api/loggerutil` (per CLAUDE.md).

---

## 8. Deployment & Operations

- **Prereq:** host runs Docker (for sandbox). `mise.toml` task gains a `docker-pull-runners` step.
- **Runner images:** built and pushed by a CI job in ChenWeb. Tagged by `agentrun-<kind>-<semver>`.
- **Workdirs:** on-host at `/srv/agentplatform/workdirs/<run_id>`. Retention policy: purge on success after 72h, on failure after 7d.
- **Feature flag:** home3 agent platform views are gated by config flag `AGENT_PLATFORM_ENABLED=true` during rollout.
- **Observability:** a new Grafana panel (or the existing one) reads from `ap_task_event` for runtime latency and success rate.

---

## 9. Resolved Decisions

*(Previously "Open Questions"; decided 2026-04-22.)*

1. **WebSocket framework.** ChenWeb does not have one. We build a thin WS layer at `ChenWeb/server/api/ws/` using `nhooyr.io/websocket` (or `gorilla/websocket` — whichever `shared/go` already pulls in; check before adding). The `/ws/agent-platform` handler from §4.3 registers against it. This is new scope added to **M2** (budget: +~1 day).
2. **Sandbox runtime.** Production will have Docker. No fallback needed for v1. We require Docker at server start (fail fast with a clear error if the socket is unreachable).
3. **Workspace bootstrap.** On first login we auto-create a workspace named **"Personal"** with slug `personal-<userid-suffix>`. The user becomes its `owner`. An idempotent service call `services/agentplatform/bootstrap.EnsurePersonalWorkspace(ctx, userID)` runs from the auth middleware's post-login hook. **This gets added to M0 scope.**
4. **Issue numbering.** Per-workspace sequential integer, no project prefix (e.g. `#17` in the UI; internally `workspace_id + issue_number`). Allocation uses `SELECT … FOR UPDATE` on an `ap_workspace_counter` row to stay race-free; a per-workspace advisory lock is a cheaper alternative if contention shows up. The schema already has `unique (workspace_id, issue_number)` — unchanged.
5. **Kanban library.** Use `@dnd-kit-svelte` — already a devDependency in [web/package.json](../../../ChenWeb/web/package.json). See §6.4.

---

## 10. Milestones

Rough sequencing. Each milestone is independently shippable behind the feature flag.

| M | Scope | Rough size |
|---|---|---|
| **M0** | Migrations, stores, workspace + membership REST + `/agents` + `/issues` CRUD (no runner yet). Auto-create "Personal" workspace on first login (§9.3). Per-workspace `issue_number` allocator (§9.4). Basic kanban board UI reading/writing REST, no realtime. | ~4-6 days |
| **M1** | `Runner` interface + Claude Code runner only + sandbox + worker pool + `ap_task_run`/`ap_task_event`. Assigning issue to agent produces a real run. Post-hoc log view. Server fails fast if Docker socket is missing (§9.2). | ~4-6 days |
| **M2** | Build WS layer at `server/api/ws/` (§9.1) + `/ws/agent-platform` endpoint + live log stream in shelf + realtime kanban updates + cancel action. | ~3-4 days |
| **M1c** | ✅ Shipped 2026-04-23. `ClaudeCodeRunner` at `shared/go/api/llm/agentrun/runner_claude.go` using `DockerSandbox`; image spec at `ChenWeb/docker/agentrun-claude/` (Dockerfile + entrypoint.sh + README). `factory.go` maps `claude_code` → the real runner; worker persists the image tag as `runner_version` via an optional `Versioned` type assertion. Image must be built manually (`docker build -t chenweb/agentrun-claude:v1 .`); `AGENT_PLATFORM_CLAUDE_IMAGE` overrides the tag. | done |
| **M3** | ✅ Shipped 2026-04-23. Added `CodexRunner` / `OpenClawRunner` / `OpenCodeRunner` at `shared/go/api/llm/agentrun/runner_{codex,openclaw,opencode}.go`, all driven through a new shared `DockerRunnerConfig` + `prepareWithIssueMarkdown` + `collectWorkdirArtifacts` in `runner_base.go` (runner_claude.go refactored onto the same helpers). Image specs at `ChenWeb/docker/agentrun-{codex,openclaw,opencode}/` (Dockerfile + entrypoint.sh + README each). `factory.go` now resolves `codex` / `openclaw` / `opencode` to real runners; env overrides per kind: `AGENT_PLATFORM_CODEX_IMAGE`, `AGENT_PLATFORM_OPENCLAW_IMAGE`, `AGENT_PLATFORM_OPENCODE_IMAGE`. Images must be built manually. | done |
| **M4** | ✅ Shipped 2026-04-24. `projects-view.svelte` (list/create/inline-edit/delete projects). `nav-rail.svelte` gained `ap-projects` child; `content-panel.svelte` dispatches to it. `kanban-board-view.svelte` gained project filter pills (All + per-project) wired to `apStore.setProjectFilter` — `grouped` derived filters by `activeProjectFilterID`. `agents-view.svelte` gained per-card inline edit form calling `apStore.updateAgent` (name, emoji, model, instructions, enabled). | done |
| **M5 (deferred)** | Autopilots, skills library, external daemon support, inbox, email. Separate design doc. | — |

Total to a usable internal MVP (M0–M2): roughly two weeks of focused work.

---

## 11. Appendix: What we are NOT copying from Multica

For the record — these concepts exist in Multica but we either skip, redesign, or implement independently:

- No copy of migration SQL. Our schema is prefixed `ap_` and written by us.
- No copy of Go code, handler signatures, or sqlc queries. We use our own DB access pattern.
- No copy of React components, component names, or proto files.
- No import of multica-ai/multica's Go module.
- No derivative CLI (`cmd/multica` analogue is out of scope in v1).

The product surface (workspaces, kanban, agent assignment, task runs, skills) is a generic pattern that predates Multica and is not theirs to license.

---

*End of document. Next step: review this doc, answer §9 open questions, then begin M0.*
