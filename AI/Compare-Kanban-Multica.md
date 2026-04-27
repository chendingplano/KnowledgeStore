<!--
  created: "2026/04/24",
  logical_name: "compare Kanban multica",
  file_id: "2026042403",
  file_type: "md",
  entities: ["agent harness", "kanban", "multi-agent", "agentic system", "agentic software development", "agent collaboration", "product compare"],
  source_url: "https://github.com/BloopAI/vibe-kanban", "https://github.com/multica-ai/multica",
  doc_date: "2026/04/24"
  event_date: "2026/04/24"
  contributor: "ChatGPT"
  links: [kanban, multia]
-->

At a glance, **vibe-kanban** and **Multica** may look similar—they both use a Kanban-style UI and involve AI agents doing coding work—but they represent **two different layers of abstraction** in the “agent-native development” stack.

---

## 1. Core Philosophy: Interface vs System

**Vibe Kanban** is fundamentally a **workflow interface**. It takes the familiar Kanban board and adapts it for AI agents, helping you organize, assign, and track tasks visually. It assumes agents already exist and focuses on making them easier to coordinate.

**Multica**, on the other hand, is a **full system for running agents**. It doesn’t just organize work—it **defines how agents live, operate, and collaborate**. It treats agents as persistent entities with lifecycles, identities, and responsibilities.

## 2. Agent Model: Tools vs Teammates

In **Vibe Kanban**, agents behave more like **tools you invoke**. You assign a task, an agent runs it (often in a workspace), and you review the result. The interaction is still somewhat session-based.

In **Multica**, agents are **first-class teammates**:

* They claim tasks
* Report blockers
* Update progress continuously
* Persist across tasks

Multica formalizes the lifecycle (enqueue → claim → execute → complete), while Vibe Kanban leaves that largely implicit.

---

## 3. Execution Model: Parallel Work vs Managed Lifecycle

**Vibe Kanban** emphasizes **parallel execution**:

* Multiple agents can run simultaneously
* Each task gets its own workspace (branch, terminal, etc.)
* Great for throughput and reducing idle time

**Multica** emphasizes **controlled execution**:

* Central scheduler / daemon manages tasks
* Agents operate within a structured lifecycle
* Real-time monitoring and coordination are built-in

Difference:

* Vibe Kanban = *“Run many agents in parallel”*
* Multica = *“Manage a fleet of agents reliably”*

---

## 4. Memory & Reuse: Stateless vs Compounding

This is where things diverge more deeply:

* **Vibe Kanban** is mostly **stateless per task**
  Each task runs, produces output, and is done. Knowledge reuse is not a core concept.

* **Multica** introduces **skills and reuse**
  Outputs can be turned into reusable capabilities, building a **compounding knowledge base** over time.

This aligns strongly with SemOS idea:

> “LLM + Skill + Iteration + Friendly Dataset + Strong Backend + Self Evolving”

Multica is explicitly trying to become that backend.

---

## 5. Architecture Fit (Important for You)

* **Vibe Kanban fits as a front-end layer**

  * Could sit on top of your system
  * Provides visualization + human control
  * Doesn’t constrain backend design

* **Multica overlaps with your backend vision**

  * Unified runtime
  * Agent lifecycle
  * Skill accumulation
  * Multi-agent coordination

SemOS does not use Multica directly but implements its core capabilities.

---

## Bottom Line

* **Vibe Kanban** = *“Make agents usable”*
  → Focus on UX, visualization, and parallel workflows

* **Multica** = *“Make agents operational”*
  → Focus on infrastructure, lifecycle, and team-like behavior

Map this to the conceptual stack:

```
[ Human UX Layer ]     → Vibe Kanban
[ Agent Harness ]      → (Claude Code / Codex / your system)
[ Agent Runtime ]      → Multica
[ Memory / RAG Layer ] → SemOS
```
