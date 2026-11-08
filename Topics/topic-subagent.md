---
Date: 2026/11/08
Contributors: ChatGPT, Chen Ding
---

In Claude Code and Codex, a subagent as:

> A subagent is a separate agent execution context, created or delegated to by a parent agent, with its own conversation history, instructions, and potentially its own tools and permissions. It executes a delegated task and reports its results to the parent.

The critical distinction is between a session, an agent configuration, and a harness.

## 1. Evaluating your three statements

| Form | Assessment                                                                                                  |
| ---------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| 1. A subagent is just another new session                  | Mostly correct, but a session alone does not make something a subagent. It needs a delegation relationship. |
| 2. A subagent is an expert with specialized system prompts | Optional. Specialization is common, but a general-purpose agent can also be a subagent.                     |
| 3. A subagent is another harness                           | Not necessarily. Usually it is another execution instance managed by the same harness.                      |

The most important distinction is that subagent describes a relationship, not a particular kind of model or software.

For example, Claude Code can launch another Claude Code agent execution to investigate a bug. The child becomes a subagent because the parent delegated the investigation to it.

The same execution could be a top-level agent if you started it directly.

## 2. What actually happens when a subagent is created?

Consider this example:

> Review my application for security vulnerabilities, performance problems, and code quality issues. Use three subagents.

```text
Parent agent — Claude Code / Codex:
  Main conversation, context and orchestration
    => Security: Separate context
       - Security prompt: Find vulnerabilities
       - Results returned to parent
    => Performance: Separate context
       - Performance prompt: Find bottlenecks
       - Results returned to parent
    => Code review: Separate context
       - Review prompt: Find defects
       - Results returned to parent

Parent synthesizes findings:
  Produces consolidated review
```

Each subagent has its own LLM interaction loop:

```text
Receive delegated task
    ↓
Build context + instructions
    ↓
Call LLM
    ↓
Execute tools
    ↓
Observe results
    ↓
Call LLM again (repeat as needed)
    ↓
Return result to parent
```

This is essentially the same agent loop used by the parent.

Importantly, the subagents do not automatically receive the parent's entire conversation. Claude Code typically starts them with fresh context; Codex can control how much context is propagated.

## 3. Is a subagent another harness?

This depends on how you define harness.

A harness typically provides the execution machinery: model invocation, tool execution, context management, permissions, and agent orchestration.

In Claude Code, a subagent uses Claude Code's underlying execution machinery, but has its own context and agent loop. It is not normally another independent Claude Code CLI process.

Similarly, Codex supports spawning agent threads within its multi-agent execution system.

Therefore:

| Concept          | Meaning                                                       |
| ---------------- | ------------------------------------------------------------- |
| Harness          | The software implementing the agent execution environment     |
| Agent definition | Instructions, model choice, tools, and configuration          |
| Agent instance   | A running execution of an agent definition                    |
| Session/thread   | Conversation and execution state                              |
| Subagent         | An agent instance delegated work by another agent             |
| Skill            | Reusable instructions or procedures that an agent can execute |

An agent instance can be backed by the same harness as its parent, or by a different harness in a custom multi-agent architecture.

## 4. How Claude Code and Codex implement this

Claude Code

Custom subagents are defined using Markdown files under `.claude/agents/`. These define the agent's description, system prompt, tools, and optional model. Claude Code invokes them through its Agent tool.&#x20;

Codex

Codex supports spawning delegated agent threads, including general-purpose agents and specialized custom agents. Its orchestration system can start agents, send additional instructions, wait for results, and collect responses.&#x20;

The architectural pattern is similar, even though the configuration formats and orchestration interfaces differ.

## 5. The implication for SemOS and Pi

SemOS should separate three concepts in its architecture:

- AgentDefinition: A reusable specification containing instructions, tools, model preferences, and constraints.
- AgentRun: A particular execution with its own context, state, and lifecycle.
- Delegation: A parent-child relationship between AgentRuns, including task assignment and result reporting.

For example:

```
AgentDefinition
  id: security-reviewer
  system_prompt: ...
  tools: [read_file, grep, bash]
  model: ...

AgentRun
  id: run-002
  definition: security-reviewer
  parent_run_id: run-001
  task: Review authentication code
  status: running
```

Here, `run-002` is a subagent because it was delegated work by `run-001`. It is not a subagent merely because its definition says `security-reviewer`.

This design also supports different harnesses. One run could execute using Pi, while another could theoretically use Codex, provided your orchestration layer supports both.

My conclusion: Your first statement is closest to the implementation reality, with one refinement: a subagent is not merely a new session; it is a new agent execution with a delegated task and a parent-child relationship. Specialized prompts are optional, and a separate harness is not required.

## 6. Create/use subagents in Codex

In Codex, you can define a custom subagent, give it specialized instructions, and ask the parent Codex agent to delegate a particular task to it.

For example, you could create a `security_reviewer` subagent and then tell Codex:

> Spawn a `security_reviewer` subagent to audit the authentication module. Do not modify any files. Return the findings, severity, and recommended fixes.

There are two separate operations:

1. Define the agent: Configure its role, instructions, model, and behavior.
2. Invoke the agent: Ask Codex to spawn an execution of that agent for a particular task.

This distinction matters because an agent definition is reusable, while each invocation creates a separate execution context.

### 6.1 Enable subagents in Codex

In your Codex configuration file, `~/.codex/config.toml`, add:

```
[features]
multi_agent = true
```

You can also configure concurrency:

```
[agents]
max_concurrent_threads_per_session = 6
```

Restart your Codex session after changing the configuration.

Codex provides built-in agent roles such as `default`, `worker`, and `explorer`, so you can use subagents without creating custom definitions.&#x20;

### 6.2 Create a custom subagent

You have two options for storing custom agent definitions.

| Location           | Scope                                     |
| ------------------ | ----------------------------------------- |
| `~/.codex/agents/` | Personal agents available across projects |
| `.codex/agents/`   | Project-specific agents                   |

For example, create:

`my-project/.codex/agents/security_reviewer.toml`

```
name = "security_reviewer"

description = """
Security specialist for reviewing code,
identifying vulnerabilities, and recommending fixes.
Use for authentication, authorization, input
validation, and dependency security reviews.
"""

model_reasoning_effort = "high"

developer_instructions = """
You are a senior application security engineer.

Responsibilities:
1. Investigate security-sensitive code.
2. Identify exploitable vulnerabilities.
3. Evaluate authentication and authorization.
4. Check input validation and injection risks.
5. Recommend concrete fixes.

Rules:
- Do not modify files.
- Do not report speculative issues as confirmed.
- Provide file paths and line numbers.
- Classify findings by severity.
- Return concise, actionable findings.
"""
```

The three required fields are `name`, `description`, and `developer_instructions`. The model and reasoning settings are optional. If no model is specified, the subagent normally inherits the parent's model.&#x20;

Notice that the subagent has its own `developer_instructions`. This is the agent-specific prompt we discussed earlier.

### 6.3 Instruct Codex to invoke the subagent

In your normal Codex conversation, enter:

```
Spawn a security_reviewer subagent to audit
the authentication module.

Task:
- Review all authentication and authorization code.
- Identify potential security vulnerabilities.
- Do not modify files.
- Return findings with file locations and severity.

Wait for the subagent's results and summarize them.
```

Codex will use the `security_reviewer` agent definition to create the delegated execution, assuming the role is discovered and multi-agent support is available.

You do not need a slash command. You request delegation using natural language.

Internally, Codex has a `spawn_agent` operation with an `agent_type` parameter that identifies the custom agent.&#x20;

Conceptually, the operation looks like this:

```
{
  "agent_type": "security_reviewer",
  "message": "Audit the authentication module and return security findings.",
  "fork_turns": "none"
}
```

This is an illustration of the internal tool call, not JSON that you need to enter manually.

`fork_turns` controls context inheritance:

- `"all"`: Inherit the parent's conversation history.
- `"none"`: Start with a clean conversation context.

The default in the documented tool schema is `"all"`.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://github.com\&sz=32)

GitHub+1



### 6.4 Use multiple specialized subagents

Suppose you define three agents:

```
my-project/
├── AGENTS.md
└── .codex/
    ├── config.toml
    └── agents/
        ├── security_reviewer.toml
        ├── performance_reviewer.toml
        └── test_engineer.toml
```

You can then instruct Codex:

```
Review the current branch against main.

Spawn three subagents in parallel:

1. security_reviewer:
   Audit the changes for security vulnerabilities.

2. performance_reviewer:
   Identify potential performance regressions.

3. test_engineer:
   Evaluate test coverage and missing edge cases.

All subagents must be read-only.

Wait for all three to finish, consolidate the findings,
remove duplicates, and produce a prioritized report.
```

### 6.5 Relationship between AGENTS.md and custom agent instructions

This connects directly to your previous question.

| Configuration                          | Purpose                             |
| -------------------------------------- | ----------------------------------- |
| `AGENTS.md`                            | Repository-wide instructions        |
| `.codex/agents/security_reviewer.toml` | Specialized agent definition        |
| `developer_instructions`               | Specialized behavioral instructions |
| Delegation message                     | Task-specific instructions          |
| Agent thread                           | Independent execution context       |

The custom agent definition does not replace the project's `AGENTS.md`. Project instructions remain applicable through Codex's normal instruction-loading mechanisms.

One important limitation: custom agent files cannot arbitrarily override the parent's permissions, sandbox configuration, or MCP server configuration. These are generally inherited from the parent. Thus, a prompt saying do not modify files is a behavioral constraint, not the same as enforcing a read-only sandbox.&#x20;

### 6.6 How is this different from a Codex skill?

| Aspect                        | Custom subagent   | Skill                      |
| ----------------------------- | ----------------- | -------------------------- |
| Configuration                 | `.toml`           | `SKILL.md`                 |
| Specialized instructions      | Yes               | Yes                        |
| Separate context              | Yes, when spawned | No, not by itself          |
| Separate agent execution loop | Yes               | No, not by itself          |
| Can use tools                 | Yes               | Through executing agent    |
| Main purpose                  | Delegate work     | Supply reusable procedures |

A skill can instruct Codex to spawn subagents, but invoking a skill does not inherently create one.

### 6.7 A practical test

To verify the setup, start with one custom agent, then ask Codex:

```
Spawn the security_reviewer subagent.

Have it inspect the authentication module without
making changes.

Report:
1. Which agent type was spawned.
2. Whether it ran in a separate agent thread.
3. What findings it returned.
```

This lets you verify that Codex actually spawned your custom role rather than merely pretending to adopt its persona in the parent session.

For your VS Code workflow, check that the installed Codex extension and its bundled runtime expose multi-agent tools; availability can vary by client and version.

Official references:

- [Codex subagents documentation](https://developers.openai.com/codex/subagents?utm_source=chatgpt.com)
- [Codex source repository](https://github.com/openai/codex?utm_source=chatgpt.com)

The essential workflow is: define a `.toml` agent → enable multi-agent support → explicitly ask Codex to spawn that named agent → collect its results in the parent session.

## 7. Create/use subagents in Claude Code
Claude Code has a built-in subagent system, similar to Codex. Create specialized subagents using Markdown files, then instruct Claude Code to delegate tasks to them.

The main difference is the configuration format:

| Feature                  | Claude Code                                  | Codex                       |
| ------------------------ | -------------------------------------------- | --------------------------- |
| Agent definition         | Markdown with YAML frontmatter               | TOML                        |
| Project-level directory  | `.claude/agents/`                            | `.codex/agents/`            |
| User-level directory     | `~/.claude/agents/`                          | `~/.codex/agents/`          |
| Specialized instructions | Markdown body                                | `developer_instructions`    |
| Invocation               | Natural language or explicit agent selection | Natural language delegation |
| Separate context         | Yes                                          | Yes                         |
| Built-in orchestration   | Agent tool                                   | `spawn_agent`               |

Unlike Codex's multi-agent feature flag, Claude Code's subagent support is built into its agent system and normally requires no separate feature flag.

### 7.1 Create a custom subagent

Suppose you want a specialized `security-reviewer` agent.

Create this file in your project:

`.claude/agents/security-reviewer.md`

```
---
name: security-reviewer
description: >
  Security specialist for reviewing application code.
  Use for authentication, authorization, input validation,
  and vulnerability assessments.
tools: Read, Grep, Glob, Bash
model: sonnet
---

You are a senior application security engineer.

Your responsibilities:
1. Investigate security-sensitive code.
2. Identify potential vulnerabilities.
3. Evaluate authentication and authorization.
4. Check input validation and injection risks.
5. Recommend concrete fixes.

Rules:
- Do not modify files.
- Do not report speculative issues as confirmed.
- Provide file paths and line numbers.
- Classify findings by severity.
- Return concise, actionable findings.
```

The file has two parts: YAML frontmatter defines the agent's configuration, while the Markdown body provides its specialized instructions.

The `tools` field limits which tools the subagent can use. In this example, omitting `Edit` and `Write` helps prevent direct file modifications, although allowing `Bash` still permits filesystem changes through shell commands. For stronger read-only enforcement, use appropriate permission controls.

### 7.2 Use `/agents` to create and manage subagents

Claude Code provides a built-in management command:

```
/agents
```

This opens the agent management interface, where you can create, inspect, edit, and manage custom agents.

You can choose whether an agent is project-specific or available across your projects. The command is useful because you don't have to write the frontmatter manually.

Custom agents are also discoverable from their Markdown files.&#x20;

### 7.3 Invoke a specific subagent

Once the `security-reviewer` agent exists, enter this in your normal Claude Code conversation:

```
Use the security-reviewer subagent to audit
the authentication module.

Task:
- Review authentication and authorization.
- Identify potential vulnerabilities.
- Do not modify files.
- Return findings with file paths and severity.

Wait for the subagent to finish and summarize
its findings.
```

Claude Code can select subagents automatically based on their descriptions, but explicitly naming the subagent makes your intent clearer.

The parent agent delegates the task through its Agent tool. The subagent runs in its own context and returns results to the parent.

You can also start a Claude Code session directly using a custom agent with the CLI's `--agent` option, but that is different from spawning a subagent: the selected agent becomes the main agent for that session.

### 7.4  Invoke multiple subagents in parallel

Suppose you define:

```
my-project/
├── CLAUDE.md
└── .claude/
    └── agents/
        ├── security-reviewer.md
        ├── performance-reviewer.md
        └── test-engineer.md
```

You can then ask:

```
Review the current branch against main.

Delegate these tasks in parallel:

1. security-reviewer:
   Find security vulnerabilities.

2. performance-reviewer:
   Identify performance regressions.

3. test-engineer:
   Identify missing tests and edge cases.

All subagents must be read-only.

Wait for all three to finish, then consolidate
their findings into one prioritized report.
```

Each subagent has a separate context window. The parent receives the results and synthesizes them.

Subagents normally share the working directory and filesystem with the parent, so concurrent modifications can conflict. For independent implementation tasks, Claude Code supports `isolation: worktree` in the agent definition, which gives the subagent a separate Git worktree.&#x20;

### 7.5 Important configuration options

| Field             | Purpose                                   |
| ----------------- | ----------------------------------------- |
| `name`            | Agent identifier                          |
| `description`     | Helps Claude decide when to delegate      |
| `tools`           | Allowed tools                             |
| `disallowedTools` | Tools explicitly denied                   |
| `model`           | Model used by subagent                    |
| `permissionMode`  | Permission behavior                       |
| `maxTurns`        | Maximum agentic turns                     |
| `skills`          | Skills preloaded into context             |
| `memory`          | Persistent memory scope                   |
| `isolation`       | Optional separate Git worktree            |
| `omitClaudeMd`    | Exclude ordinary `CLAUDE.md` instructions |

For example, a specialized implementation agent could use:

```
---
name: backend-developer
description: Implement backend features and fixes
model: sonnet
tools: Read, Grep, Glob, Edit, Write, Bash
maxTurns: 40
isolation: worktree
skills:
  - backend-conventions
---
```

The `skills` field is especially useful: a subagent can be configured to preload particular skills, combining specialized instructions with reusable workflows.

### 7.6 Relationship to CLAUDE.md

This connects to your earlier question about instruction inheritance.

According to Claude Code's documentation:

- Custom subagents normally load applicable `CLAUDE.md` instructions.
- They receive their own agent-specific system prompt.
- They do not automatically inherit the parent's conversation history.
- You can set `omitClaudeMd: true` to exclude ordinary `CLAUDE.md` instructions.
- The built-in Explore and Plan subagents are exceptions: they omit `CLAUDE.md` by default.

An important detail is that the custom subagent's Markdown body becomes its own system prompt, rather than simply being appended to the parent's full Claude Code system prompt.&#x20;

### 7.7 One correction about `/agents`

The latest Claude Code documentation describes a change: `/agents` now primarily provides guidance for managing agent files, rather than opening the older interactive creation wizard. The wizard existed in Claude Code v2.1.197 and earlier.

The most reliable creation methods are therefore to write `.claude/agents/<name>.md` directly or ask Claude Code to create it for you.&#x20;

For example:

```
Create a project-level subagent named database-expert.

It should specialize in PostgreSQL query optimization,
indexing, full-text search, and schema design.

Use Sonnet. Allow read-only tools and Bash for
EXPLAIN queries. Do not allow file modifications.

Save it under .claude/agents/.
```

Then:

```
Use the database-expert subagent to review the
performance of the search queries in kb.metrics.
```

The key takeaway: Claude Code's custom subagents are reusable agent definitions stored as Markdown files. The parent Claude Code session can invoke them by name, and each invocation gets its own execution context, specialized instructions, and configurable capabilities.

Official documentation: [Create custom subagents — Claude Code](https://code.claude.com/docs/en/sub-agents?utm_source=chatgpt.com)

## 8. Agent, subagent, Claude.md, tools and skills

This subsection covers the relations among agents, subagents, Clude.md/Agents.md, 
tools and skills 

| # | Statement                                                                 | Assessment                     |
| - | ------------------------------------------------------------------------- | ------------------------------ |
| 1 | Parent and subagents use `CLAUDE.md` / `AGENTS.md` the same way           | Generally yes, with exceptions |
| 2 | Subagents may have tool restrictions                                      | Yes                            |
| 3 | Subagents can use any skill available to the parent, without restrictions | Not necessarily                |

### 8.1  Project instructions: generally shared

In Claude Code, custom subagents normally load applicable `CLAUDE.md` instructions, just like the parent.

However:

- A custom subagent can specify `omitClaudeMd: true` to exclude normal `CLAUDE.md` loading.
- Built-in subagents such as Explore and Plan have special behavior.
- A subagent has its own system prompt and conversation context; it does not simply inherit the parent's complete prompt.

In Codex, parent agents and subagents generally use the same `AGENTS.md` resolution mechanism, subject to their working directories and context initialization.&#x20;

### 8.2 Tool restrictions

Claude Code allows you to configure the tools available to a custom subagent.

For example:

```
---
name: code-reviewer
description: Reviews code without modifying it
tools: Read, Grep, Glob
model: sonnet
---
```

This subagent can inspect files but does not have access to the usual editing or shell tools.

Tool restrictions are meaningful because a subagent's capabilities need not equal the parent's.

### 8.3 Skill access: not necessarily unrestricted

This is the most important distinction.

A Claude Code subagent can use skills, but skill availability, skill loading, and skill execution are three different things.

- Availability: Whether the subagent can discover or access a skill.
- Loading: Whether the skill's instructions are included in the subagent's context.
- Execution: Whether the subagent has the necessary tools and permissions to carry out the skill.

For example:

```
---
name: frontend-developer
description: Implements frontend components
tools: Read, Grep, Glob, Edit, Write, Bash
skills:
  - frontend-design
  - accessibility-review
---
```

Here, `frontend-design` and `accessibility-review` are explicitly preloaded into the subagent's context.

That does not necessarily mean these are the only skills it can use. Other discoverable skills may still be available, depending on the agent's configuration and Claude Code's skill-discovery behavior.

Conversely, even if a skill is available, a subagent might not be able to execute it successfully. For instance, a skill requiring `Bash` cannot perform its shell-based steps if the subagent has no shell access.

### 8.4 A more precise formulation

The relations are:

1. Project instructions: Parent agents and subagents generally share applicable project instructions, but loading can be configured independently.
2. Tools: Each subagent can have its own tool restrictions, subject to the harness's permission system.
3. Skills: Subagents can use skills available in their execution environment, but skill discovery, preloading, and execution are subject to agent configuration and tool permissions.

The broader architectural implication is that instructions, tools, and skills are three independent configuration dimensions.
