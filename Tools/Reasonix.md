# Reasonix

**Version:** v0.50.0 · MIT License  
**Source:** https://esengine.github.io/DeepSeek-Reasonix/  
**Repo:** https://github.com/esengine/DeepSeek-Reasonix

A DeepSeek-native AI coding agent for the terminal. Talks directly to `api.deepseek.com` with an append-only, byte-stable prefix cache loop — long sessions hold 90%+ cache hit and input-token cost drops to ~1/5 of normal.

---

## Install

**Requirements:** Node ≥ 22 · macOS / Linux / Windows (PowerShell, Git Bash, Windows Terminal)

```bash
# Recommended — no global install
npx reasonix code

# Or install globally
npm install -g reasonix
```

First launch walks you through pasting a DeepSeek API key.

**DeepSeek API pricing:**  
- $0.07 / Mtok (uncached input)  
- $0.014 / Mtok (cached — ~1/5 rate)

---

## Three Pillars

### P1 — Cache-First Loop
The loop is append-only: messages and tool results are only appended, history is never mutated. No reordering, no marker-based compaction, fully deterministic tool-call ordering. The cached prefix survives every tool call, achieving ~94% cache hit in long sessions.

### P2 — R1 Thought Harvest
Scavenges escaped reasoning-chain tool calls so they are never lost.

### P3 — Tool-Call Repair
Schema-aware self-healing of malformed tool calls.

---

## Features

| ID | Feature | Details |
|----|---------|---------|
| F-01 | Terminal-native TUI | TypeScript + Ink TUI; `git diff` for diffs, `ls` for file trees |
| F-02 | V4 two-tier models | V4-Flash by default; `/pro` lifts a single turn to V4-Pro; `/preset max` makes the whole session run on Pro |
| F-03 | MCP first-class | `--mcp "name=cmd args"` mounts external servers; supports stdio, SSE, Streamable HTTP |
| F-04 | Sandbox + plan gate | Tools sandboxed to launch dir; `/plan` puts the session in read-only audit mode — no writes until the plan is approved |
| F-05 | Composable skills | Drop a Markdown file in `.reasonix/skills/<name>.md`; supports `runAs: subagent` and `allowed-tools` |
| F-06 | Replay & events | Every event is written to disk — replay past sessions, run stats on tokens / cache / cost |

---

## Configuration

Config lives in `~/.reasonix/config.json` (Windows: `%USERPROFILE%\.reasonix\config.json`). Created automatically on first run. Project-level overrides live in `<project>/.reasonix/`; project settings win over global when names collide. Skip config entirely with `--no-config` (CI-friendly).

### Top-level `config.json` Keys

```jsonc
{
  "apiKey": "sk-...",
  "baseUrl": "https://api.deepseek.com",
  "lang": "en",                       // en | zh
  "preset": "auto",                   // auto | flash | pro
  "editMode": "review",               // review | auto | yolo
  "reasoningEffort": "high",          // high | max
  "theme": "auto",                    // light | dark | auto
  "search": false,                    // enable web_search / web_fetch tools
  "webSearchEngine": "mojeek",        // mojeek | searxng | metaso
  "webSearchEndpoint": "http://localhost:8080",
  "mcp": [],                          // MCP server list (shorthand strings)
  "mcpServers": {},                   // MCP server objects (canonical format)
  "mcpDisabled": [],                  // servers to skip on startup
  "projects": {                       // per-workspace overrides
    "/abs/path": {
      "shellAllowed": ["npm", "git status"]
    }
  },
  "semantic": { ... }                 // embedding provider for `reasonix index`
}
```

**`editMode` trust levels:**
- `review` — queues file changes + blocks shell commands
- `auto` — writes directly to disk + blocks shell commands
- `yolo` — no blocks at all (sandbox only)

---

## MCP Servers

### Shorthand string format (`config.mcp`)
```json
{
  "mcp": [
    "fs=npx -y @modelcontextprotocol/server-filesystem /tmp",
    "git=uvx mcp-server-git --repository ."
  ]
}
```
Format: `name=command arg1 arg2`. The `name=` prefix namespaces all tools from that server.

### SSE (HTTP)
```json
{
  "mcp": [
    "remote=https://example.com/mcp/sse",
    "https://other.example.com/mcp"
  ]
}
```

### Streamable HTTP (2025-03 spec)
```json
{
  "mcp": [
    "edge=streamable+https://edge.example.com/mcp"
  ]
}
```

### Canonical `mcpServers` format
```json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": { "GITHUB_TOKEN": "ghp_***" }
    },
    "postgres": {
      "transport": "sse",
      "url": "https://mcp.internal/pg/sse",
      "headers": { "Authorization": "Bearer ***" }
    },
    "edge": {
      "transport": "streamable-http",
      "url": "https://edge.example.com/mcp"
    }
  }
}
```

### CLI flag
```bash
npx reasonix code \
  --mcp 'github=npx -y @modelcontextprotocol/server-github' \
  --mcp 'pg=https://mcp.internal/pg/sse'
```

---

## Skills

Skills are Markdown playbooks the model can invoke with `/skill <name>`. Names and descriptions are pinned into the prompt; bodies are loaded on demand.

### Directory layout
```
~/.reasonix/skills/          # global
  audit-logs.md
  refactor-react/
    SKILL.md                 # folder form, for skills with assets

<project>/.reasonix/skills/  # project (overrides global)
  release-notes.md
```

### Frontmatter
```yaml
---
name: audit-logs
description: Review git log for security red flags.
runAs: inline          # inline | subagent
allowed-tools: bash,read   # subagent tool whitelist
model: deepseek-chat       # subagent model override
max-iters: 32              # tool-call budget (default 16, max 32)
---

## Task
1. Pull the last 20 commits.
2. Flag commits mentioning password / secret / token.
3. Summarize.
```

- `runAs: inline` — body runs in the parent loop  
- `runAs: subagent` — isolated sub-loop, only returns final result

---

## Memory

Memory is private knowledge pinned into the immutable prefix so the agent reads it every turn. Two scopes: **global** (cross-project facts) and **project** (per-workspace context).

### Directory layout
```
~/.reasonix/memory/
  global/
    MEMORY.md                    # index — pinned into prefix
    user_role.md
  <project-hash>/                # sha1(absRoot)[0..16]
    MEMORY.md
    project_release_freeze.md
```

### Entry format
```yaml
---
name: user_role
description: User is a senior backend engineer, new to React.
type: user             # user | feedback | project | reference
scope: global
created: 2026-05-09
---
Body content here.
```

To add a memory, just say it in conversation — the model calls `scaffold_memory` to draft the file; `/apply` writes it to disk.

---

## Hooks

Hooks run shell commands on lifecycle events. Configured in `settings.json` (not `config.json`). Project-level takes precedence over global.

### Locations
```
<project>/.reasonix/settings.json   # project scope
~/.reasonix/settings.json           # global scope
```

### Schema
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "command": "node scripts/audit.js",
        "match": "^(write|edit_file|bash)$",
        "description": "Audit before risky tool calls",
        "timeout": 5000
      }
    ],
    "PostToolUse": [
      { "command": "echo done >> /tmp/reasonix.log" }
    ],
    "UserPromptSubmit": [],
    "Stop": []
  }
}
```

### Events
| Event | Blocking | Timeout | Notes |
|-------|----------|---------|-------|
| `PreToolUse` | Yes — `exit 2` blocks, `exit 0` passes | 5s default | Fires before tool execution |
| `PostToolUse` | No — non-zero is a warning only | 30s default | Fires after tool execution |
| `UserPromptSubmit` | Yes — `exit 2` blocks the message | — | Fires before user input is processed |
| `Stop` | No | — | Fires on `/quit` or session exit |

Each hook receives JSON on stdin:
```json
{
  "event": "PreToolUse",
  "cwd": "/workspace",
  "toolName": "bash",
  "toolArgs": { "command": "rm -rf /" },
  "turn": 3
}
```

---

## Web Search

```bash
/search-engine mojeek
/search-engine searxng                        # defaults to http://localhost:8080
/search-engine searxng http://192.168.1.5:8888
/search-engine metaso
```

Run a local SearXNG instance:
```bash
podman run -d --replace --name searxng -p 8080:8080 docker.io/searxng/searxng
```

---

## Semantic Index

```json
{
  "semantic": {
    "provider": "ollama",
    "ollama": {
      "baseUrl": "http://localhost:11434",
      "model": "nomic-embed-text"
    },
    "openaiCompat": {
      "baseUrl": "https://api.example.com/v1",
      "apiKey": "...",
      "model": "text-embedding-3-small"
    }
  }
}
```

Build the index: `reasonix index`

---

## Quick Reference

### Session / Model Commands

| Command | Description |
|---------|-------------|
| `/pro` | Lift the current turn to V4-Pro (one turn only) |
| `/preset max` | Switch the entire session to V4-Pro |
| `/preset flash` | Switch the entire session to V4-Flash (default) |
| `/preset auto` | Return to automatic model selection |
| `/plan` | Enter read-only audit gate — no writes until the plan is approved |
| `/apply` | Flush all pending file edits to disk |
| `/quit` | Exit the session |

### MCP Commands

| Command | Description |
|---------|-------------|
| `/mcp` | Open the interactive MCP hub |
| `/mcp disable <name>` | Disable a server (writes to `mcpDisabled`; takes effect on next launch) |
| `/mcp enable <name>` | Re-enable a previously disabled server |
| `/mcp reconnect <name>` | Reconnect an online server and incrementally register new tools |

### Skill Commands

| Command | Description |
|---------|-------------|
| `/skill list` | List all skills by scope (global / project) |
| `/skill new <name>` | Scaffold a new project-scoped skill stub; add `--global` for `~/.reasonix/skills/` |
| `/skill show <name>` | Print the full skill body |
| `/skill <name> [args]` | Run the skill; optional args are appended to the body as a string |

### Memory Commands

| Command | Description |
|---------|-------------|
| `/memory list` | List all entries across both scopes |
| `/memory show <name>` | Display the body of an entry (scope auto-resolved) |
| `/memory forget <name>` | Delete a memory entry |
| `/memory clear <scope> confirm` | Wipe an entire scope; `confirm` keyword required |

### Permissions Commands

| Command | Description |
|---------|-------------|
| `/permissions list` | View the shell allowlist for the current project |
| `/permissions add <prefix>` | Add a shell command prefix to the allowlist |
| `/permissions rm <prefix\|index>` | Remove an entry by name or index |
| `/permissions clear confirm` | Clear the entire allowlist; `confirm` keyword required |

### Search Commands

| Command | Description |
|---------|-------------|
| `/search-engine mojeek` | Switch to Mojeek (default, no setup required) |
| `/search-engine searxng [url]` | Switch to SearXNG; optional custom endpoint URL |
| `/search-engine metaso` | Switch to Metaso (100 free searches/day) |

### CLI Commands

| Command | Description |
|---------|-------------|
| `npx reasonix code` | Launch the TUI in the current directory |
| `npx reasonix code --dir <path>` | Launch with a specific working directory |
| `npx reasonix code --mcp "name=cmd"` | Mount an MCP server at launch |
| `npx reasonix code --no-config` | Skip config file (CI-friendly) |
| `npx reasonix mcp inspect "name=cmd"` | Inspect an MCP server's tools without launching the TUI |
| `npx reasonix mcp list` | List all configured MCP servers |
| `reasonix index` | Build the semantic embedding index for the current project |

---

## Desktop App

Native Tauri client with bundled Node runtime — shares `~/.reasonix` config with the CLI. No separate npm install required. Features: multi-tab sessions, side panel showing files read/written this session, live cost / cache / token meters.

Download: https://esengine.github.io/DeepSeek-Reasonix/download.html

---

## FAQ

**Why DeepSeek only?**  
Design choice, not limitation. The loop's invariants are engineered around DeepSeek's byte-stable prefix cache. Pointing at other providers (Anthropic-compatible endpoints) breaks the cache mechanics. Generic tools (Aider, Cline, Continue) compress history, destroying byte stability.

**Can I use a self-hosted DeepSeek endpoint?**  
Yes (since v0.30). Set `baseUrl` to your internal address — the loop, cache strategy, and tool protocol are unchanged.

**Will there be an IDE plugin?**  
No. Reasonix is terminal-first by design.

**Are tool calls safe?**  
All built-in tools (`read_file`, `write_file`, `edit_file`, `run_command`, …) are sandboxed to the launch directory. SEARCH/REPLACE edits queue as pending — nothing hits disk until `/apply`. `/plan` mode blocks all writes.

**Can I switch working directories mid-session?**  
No — exit and relaunch with `reasonix code --dir <path>`.
