## What is Hermes Agent? [[Agentic System]]

URL: https://github.com/nousresearch/hermes-agent\
Date: 2026/04/16\
Creator: ChatGPT

**Nous Research’s Hermes Agent** is an **open-source, autonomous AI agent platform** designed to behave more like a *persistent teammate* than a stateless assistant. ([Openflows][1])

It solves the problem of:
> **LLMs forget. Hermes tries to make them *learn*.**

Hermes Agent is one of the first serious attempts at a “real agent OS”.  But:

* Still early
* More infra-heavy
* Less polished than Claude Code / Codex UX

It is:
* **Not a direct replacement**
* **Same ecosystem, different layer**
* Hermes = *persistent, evolving agent runtime*
* Claude Code / Codex = *interactive coding agents*

It is not a replacement of coding assistant (Claude Code, Codex, etc.). The closest sibling is OpenClaw.

### Core idea (in your terminology)

Hermes Agent is essentially:

* **Agent + Memory system + Skill system + Execution environment**
* Running **continuously (server-side)** instead of per-session
* With a built-in **self-improvement loop**

---

## Key capabilities (what makes it different)

### 1) Persistent, multi-level memory (not just RAG)

* Remembers across sessions (days/weeks)
* Stores knowledge as **“Skill Documents” (markdown)** (refer to [[skill differences]] for skills)
* Reuses past solutions as procedural knowledge
  ([MarkTechPost][2])

More importantly:

* It **writes new knowledge itself** after solving tasks

---

### 2) Self-improving via skill generation

* When it solves a task → it **creates a reusable skill**
* Skills (or knowledge) are searchable and composable
* Over time → agent gets *strictly better*, with more knowledge learned from tasks

([GitHub][3])

---

### 3) Lives on your machine (persistent agent, not session-based)

* Runs on a server (local or remote)
* Keeps **state + environment + tools**
* Not tied to a single chat

([NOUS RESEARCH][4])

---

### 4) Multi-channel interface (not just terminal)

* CLI + Telegram + Slack + Discord + WhatsApp
* Same agent, same memory, across channels
  ([NOUS RESEARCH][4])

This is similar to OpenClaw. This is also an important feature of future agentic systems [[agentic system feature]].

---

### 5) Real execution + sandboxing

* Can execute code / commands via:

  * local
  * Docker
  * SSH
  * etc.
    ([NOUS RESEARCH][4])

---

### 6) Sub-agents + parallelization

* Spawns isolated sub-agents for tasks
* Parallel workflows
  ([NOUS RESEARCH][4])

---

## Layered comparison (important)

### Layer 1 — LLM (brain)

* Hermes Agent → uses models (e.g., Hermes-3, OpenAI-compatible)
* Claude Code / Codex → also just orchestrate models

Hermes Agent can use virtually any LLMs (such as Open Router, etc.) available in the market, which 
Claude Code may restrict you from using other models.

---

### Layer 2 — Agent loop / harness

* Hermes Agent → **full autonomous agent runtime**
* Claude Code / Codex → **interactive coding agents**

👉 **Different philosophy**

Hermes Agent is not “non-interactive,” but it is “not primarily interactive.”
It can ask questions—but it’s designed to act first, interrupt only when needed, unlike Claude Code / Codex which are conversation-first.

Hermes is designed to operate inside a trusted execution environment. So typically, it does NOT prompt for every action.
It assumes you trust it and the environment is sandboxed (Docker, VM, etc.)

Hermes usually asks only in these cases:

1) Missing information
“Which repo?”
“Which environment?”
2) Ambiguous intent
“Do you want to overwrite existing files?”
3) High-risk decisions (depending on config)
deleting data
production changes
4) Explicit “human-in-the-loop” mode

If configured, it can pause before execution, require approval.

### Layer 3 — Memory & learning

* Hermes Agent → **persistent + self-improving**
* Claude Code / Codex → mostly:

  * session memory
  * project context (CLAUDE.md, etc.)
  * no real learning loop

👉 Hermes is **stronger here**

---

### Layer 4 — Interface

* Hermes → multi-channel (chat apps + CLI)
* Claude Code / Codex → mostly terminal / IDE

👉 Hermes is broader

---

### Layer 5 — Primary use case

| Tool                | Primary role                        |
| ------------------- | ----------------------------------- |
| Claude Code / Codex | Coding assistant (interactive)      |
| OpenClaw            | Agentic coding workflows            |
| Hermes Agent        | Persistent **personal AI operator**, not just coding |

---

## The real relationship (most accurate framing)

Think of Hermes Agent as:

> **“User-driven loop”**
> vs
> **“Self-driven loop”**

From a *user experience* perspective, tools like Codex / Claude Code **feel always-on**—you can invoke them anytime.

But the **real distinction is not about availability**.
It’s about **who drives the agent loop**.

---

# 1) Claude Code / Codex → *User-driven agents*

Even if they *feel always-on*, their execution model is:

> **They only run when you ask them to**

### Key properties

* No internal scheduler
* No independent goals
* No background processing
* No persistence of “intent”

Self-driven agents loop exists independently of users. It has a **persistent process**, maintains **task queues / goals**.
These can be achieved via cron, triggers, events. More importantly, it can **resume work without being asked again**.

### Example (Hermes-style)

```text
Loop:
  wake up
  check GitHub issues
  if issues:
    solve
    create PR
    store skill
  sleep
```

### What Is a Code Assistant

> “Any task that can be solved by a brain + files + tools can be fulfilled by a coding assistant”

Coding assistants today:

* General-purpose **brains**
* But **not autonomous systems**

### Agent Platform (Hermes Agent):

* General-purpose **brain**
* **+ autonomy layer**

Instead of thinking in categories like:

* coding assistant
* agent platform

# 8) Why this matters (non-obvious insight)

This difference leads to **entirely different system design constraints**:

## In user-driven systems:

* Memory = context window + retrieval
* Skills = tools
* Safety = permission prompts

---

## In self-driven systems:

* Memory = long-term state
* Skills = accumulated experience
* Safety = sandboxing + policy
* Scheduling = required

Think in this axis:

```text
Stateless  ←──→  Stateful
Reactive   ←──→  Proactive
User-loop  ←──→  Agent-loop
```

---

# 6) Same capability, different control model

| Dimension      | Claude Code / Codex | Hermes Agent |
| -------------- | ------------------- | ------------ |
| Capability     | High                | High         |
| Tool usage     | Yes                 | Yes          |
| File access    | Yes                 | Yes          |
| Task scope     | Broad               | Broad        |
| **Loop owner** | **User**            | **Agent**    |
| **Continuity** | None (per task)     | Persistent   |
| **Initiative** | Reactive            | Proactive    |

---

## Hermes Skills and Code Assistant Skills [Skill Differences]

Hermes skills are not the same as skills in coding assistants. They *look similar on the surface*, but they live at **different layers** and serve different purposes.

In Hermes Agent, a **skill = learned procedural knowledge**, typically stored as a Markdown document. Example:

> “When I solved X, here is how I did it so I can do it again.”

A more complex example:

```md
# Skill: Fix PostgreSQL column does not exist error

## Context
Occurs when JSON is used incorrectly in SQL update.

## Steps
1. Ensure column type is json/jsonb
2. Use '{}'::jsonb instead of "{}"
3. Verify schema

## Example
update kb.inputs set status = '{}'::jsonb where id = 20;
```

The skills are:

* Human-readable
* LLM-readable
* **Generated by the agent itself**
* Retrieved later via semantic search

Hermes skills may be converted to the ones that code assistants can use.

## Three levels of “skill evolution”

### Level 1 — Documentation (Hermes default)

* Markdown
* Retrieved + interpreted
* Flexible but indirect

---

### Level 2 — Structured skill

Convert into:

```json
{
  "name": "fix_postgres_json_error",
  "trigger": "...",
  "steps": [...]
}
```

---

### Level 3 — Executable skill (Claude Code style)

Turn into:

* MCP tool
* CLI command
* API

Now it becomes:

> **A real capability**

---

# The missing bridge (important for you)

Right now, most systems **don’t connect these two layers well**.

# References

[1]: https://openflows.org/currency/currents/hermes-agent/?utm_source=chatgpt.com "Hermes Agent - Openflows"
[2]: https://www.marktechpost.com/2026/02/26/nous-research-releases-hermes-agent-to-fix-ai-forgetfulness-with-multi-level-memory-and-dedicated-remote-terminal-access-support/?utm_source=chatgpt.com "Nous Research Releases 'Hermes Agent' to Fix AI ..."
[3]: https://github.com/NousResearch/hermes-agent?utm_source=chatgpt.com "NousResearch/hermes-agent: The agent that grows with you"
[4]: https://nousresearch.com/hermes-agent/?utm_source=chatgpt.com "Hermes Agent — An Agent That Grows With You"

