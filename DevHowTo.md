## 1. What is a Claude Code Hook
In Claude Code, a **hook is a deterministic action that Claude Code runs automatically when a particular lifecycle event occurs**.

The important idea is:

> **A Skill tells the LLM how to behave. A Hook tells the harness what to do when an event happens.**

Hooks are therefore closer to **event handlers / triggers** than to prompts or skills.

### A simple example

Suppose you want to ensure code is formatted whenever Claude edits a Go file.

Conceptually:

```text
Claude edits file
       │
       ▼
 PostToolUse event
       │
       ▼
     Hook
       │
       ▼
    gofmt
```

Claude does **not** need to remember:

> "After editing a Go file, I should run gofmt."

The harness sees the event and invokes the configured hook automatically.

That distinction is significant because LLM instructions are probabilistic, while hooks provide deterministic enforcement.

### What events can trigger hooks?

Claude Code exposes lifecycle events such as:

| Event                | When it happens               |
| -------------------- | ----------------------------- |
| `SessionStart`       | Claude Code session starts    |
| `UserPromptSubmit`   | User submits a prompt         |
| `PreToolUse`         | Before Claude executes a tool |
| `PostToolUse`        | After a tool finishes         |
| `PostToolUseFailure` | After a tool fails            |
| `PermissionRequest`  | Permission is requested       |
| `SubagentStart`      | A subagent starts             |
| `SubagentStop`       | A subagent finishes           |
| `Stop`               | Claude finishes responding    |
| `PreCompact`         | Before context compaction     |
| `SessionEnd`         | Session ends                  |

There are additional events as well.

This allows fairly sophisticated policies. For example:

```text
PreToolUse(Bash)
    ↓
Check command
    ↓
Is it dangerous?
   / \
 yes  no
  │    │
block allow
```

Or:

```text
PostToolUse(Edit)
    ↓
Detect edited language
    ↓
Run formatter/linter
```

### Hooks don't have to be shell scripts

A Claude Code hook can invoke several kinds of handlers, including shell commands and LLM-based evaluation.

For example, a command hook can run:

```text
"command": "go test ./..."
```

But Claude Code also supports `prompt` hooks, where an LLM evaluates something, and `agent` hooks, where an agent can perform a more involved verification task.

So there is an interesting spectrum:

```text
                    Increasing intelligence
                           ────────►

Shell hook          Prompt hook          Agent hook
   │                    │                    │
gofmt               LLM judgment       tool-using agent
grep                semantic check      investigation
go test
```

The first category is particularly useful for **hard invariants**.

### Hook vs Skill

This is probably the most useful distinction:

```text
Skill
─────
"When modifying Go code,
run gofmt afterward."

        LLM reads instruction
                 ↓
        decides what to do
                 ↓
             gofmt


Hook
────
PostToolUse(Edit)
        ↓
      gofmt
```

With the Skill, the **LLM is responsible for compliance**.

With the Hook, the **harness is responsible for enforcement**.

That makes hooks useful for things you don't want the model to forget.

For example:

```text
Skill:
    How we design database migrations
    How we review APIs
    How we write tests

Hook:
    Never allow .env to be committed
    Format modified Go files
    Run validation after edits
    Log tool usage
```

### Hook vs traditional Git hooks

The concept is very similar to Git hooks:

```text
Git:

git commit
    ↓
pre-commit hook
    ↓
lint / validate / reject
```

Claude Code generalizes the same idea to the **agent execution lifecycle**:

```text
Claude calls Bash
    ↓
PreToolUse hook
    ↓
validate / modify / reject
    ↓
execute Bash
    ↓
PostToolUse hook
```

This is one reason hooks are important in **agent harness engineering**. You can move important constraints out of `CLAUDE.md` and prompts and turn them into executable policies.

For example, instead of making `CLAUDE.md` grow indefinitely:

```text
Never edit generated files.
Never commit secrets.
Always format Go.
Don't disable tests.
Don't modify migrations after release.
...
```

some of these can become deterministic mechanisms:

```text
                Policy
                  │
        ┌─────────┴──────────┐
        │                    │
   semantic rule        enforceable rule
        │                    │
      Skill                  Hook
        │                    │
 "understand why"       "make it happen"
```

That's a useful architectural division: **Skills encode knowledge and procedures; hooks encode event-driven enforcement and automation.**

## 2. What is a Claude Code Plugin
A **Claude Code Plugin is essentially a packaging and distribution mechanism for Claude Code extensions**.

The key distinction is:

> **Skills, subagents, hooks, MCP servers, LSP servers, etc. provide capabilities. A Plugin packages those capabilities into one installable, versioned unit.**

Anthropic itself describes plugins as the **“packaging layer”** for Claude Code extensions. ([Claude][1])

### What can be inside a plugin?

A plugin can bundle several kinds of Claude Code extensions:

| Component       | Purpose                                                                    |
| --------------- | -------------------------------------------------------------------------- |
| **Skills**      | Reusable instructions/workflows/knowledge                                  |
| **Agents**      | Specialized subagents                                                      |
| **Hooks**       | Run actions when Claude Code events occur                                  |
| **MCP servers** | Give Claude external tools/services                                        |
| **LSP servers** | Give Claude code intelligence such as definitions, references, diagnostics |
| **Monitors**    | Background monitoring                                                      |
| **Executables** | Commands made available to Claude's Bash tool                              |
| **Settings**    | Default plugin-specific Claude Code configuration                          |

([Claude][2])

Conceptually, therefore:

```text
Claude Code
│
├── CLAUDE.md
│
├── Skills
├── Subagents
├── Hooks
├── MCP servers
├── LSP servers
│
└── Plugins
      │
      └── package several of the above together
```

A plugin might physically look like:

```text
my-plugin/
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   ├── review/
│   │   └── SKILL.md
│   └── commit/
│       └── SKILL.md
├── agents/
│   └── security-reviewer.md
├── hooks/
│   └── hooks.json
├── .mcp.json
├── .lsp.json
└── bin/
```

The `plugin.json` identifies the plugin, while the other directories contain its capabilities. ([Claude][2])

### Plugin vs. Skill

This distinction is particularly important.

Suppose you have:

```text
~/.claude/skills/code-review/SKILL.md
```

That's simply a **Skill**.

But suppose you create:

```text
my-dev-tools/
├── .claude-plugin/plugin.json
├── skills/code-review/SKILL.md
├── skills/commit/SKILL.md
├── agents/security-reviewer.md
└── hooks/hooks.json
```

Now `my-dev-tools` is a **Plugin** containing multiple Claude Code extensions.

Plugin skills are also namespaced. For example:

```text
/my-dev-tools:code-review
/my-dev-tools:commit
```

rather than simply:

```text
/code-review
/commit
```

The namespace prevents collisions between independently developed plugins. ([Claude][2])

### Why introduce Plugins at all?

Without plugins, you can already put things directly under `.claude/`:

```text
.claude/
├── skills/
├── agents/
└── ...
```

That works well for **one repository or your own configuration**.

Plugins solve a different problem: **reuse, installation, distribution, versioning, and lifecycle management**.

For example, imagine you've developed a good development harness containing:

```text
Skills:
    code-review
    fix-tests
    update-docs
    create-adr

Agents:
    security-reviewer
    architecture-reviewer

Hooks:
    run-tests-after-edit
    prevent-committing-secrets

MCP:
    github
```

Instead of manually copying those files into every project, you could package them as:

```text
chen-dev-harness
```

and install the plugin once at user scope so it's available across projects. Plugins can alternatively be installed at project or local scope. ([Claude][3])

### Plugin marketplaces

Claude Code also has **plugin marketplaces**. A marketplace is basically a catalog/index of plugins—not the plugin itself.

The relationship is:

```text
Marketplace
    │
    ├── Plugin A
    │     ├── skills
    │     ├── agents
    │     └── hooks
    │
    ├── Plugin B
    │     ├── skills
    │     └── MCP
    │
    └── Plugin C
          └── LSP
```

Claude Code includes Anthropic's official marketplace, and you can add third-party or private marketplaces. ([Claude][4])

For example:

```text
/plugin install github@claude-plugins-official
```

Or you can browse/manage them through `/plugin`; VS Code also exposes plugin management in its UI. ([Claude][4])

[Claude Code plugin documentation](https://code.claude.com/docs/en/plugins?utm_source=chatgpt.com)

### The mental model I recommend

Given the distinctions among skills, subagents, harnesses, and workflows, I would model Claude Code's extension system roughly as:

```text
                    Claude Code
                        │
              ┌─────────┴─────────┐
              │                   │
        Core capabilities    Extensions
                                  │
              ┌────────┬──────────┼─────────┐
              │        │          │         │
            Skills   Agents     Hooks      MCP ...
              │        │          │
              └────────┴──────────┘
                       │
                    Plugin
             packaging/distribution
                       │
                  Marketplace:w

                    catalog
```

So **Plugin is not another abstraction competing with Skill, Agent, Hook, or MCP**. It sits at a different level.

In software-engineering terms, I'd compare it to:

**Skill ≈ module/functionality; Plugin ≈ package; Marketplace ≈ package registry/catalog.**

This also explains why something such as ECC can feel conceptually related to Claude Code plugins: both deal with **packaging/managing coding-assistant extensions**, although ECC's cross-assistant management problem is broader than Claude Code's native plugin system.

\[1\]: https://code.claude.com/docs/en/features-overview?utm_source=chatgpt.com "Extend Claude Code - Claude Code Docs" \
\[2\]: https://code.claude.com/docs/en/plugins?utm_source=chatgpt.com "Create plugins - Claude Code Docs" \
\[3\]: https://code.claude.com/docs/en/plugins-reference?utm_source=chatgpt.com "Plugins reference - Claude Code Docs" \
\[4\]: https://code.claude.com/docs/en/discover-plugins?utm_source=chatgpt.com "Discover and install prebuilt plugins through marketplaces - Claude Code Docs"

## Pi Commands
| Command | Explanations |
|---------|--------------|
| /login | Login |
| /logout | Logout |
| /quit | Quit pi |
| Shift + Tab | Pick thinking level |
| Control + L (Shift) | Pick model |
| Ctrl + G | Open a full multiline editor (vim) |