#import "@preview/diagraph:0.3.6"
#import "@preview/oxdraw:0.1.0": *

#set heading(numbering: "1.")
#set quote(block: true)
#show quote: set pad(x: 1em)
#show raw.where(block: true): block.with(fill: luma(240), inset: 1em, radius: 0.5em, width: 100%)

#show heading: it => {
  set text(fill: blue) if it.level == 1
  if it.numbering != none {
    counter(heading).display(it.numbering)
    h(0.5em) // Adds a little gap after the number
  }
  it.body
}

#set page(
  numbering: "1 of 1",
  footer: context {
    line(length: 100%)
    "Review - Agent Harness Kit"
    h(1fr)
    counter(page).display("1/1", both: true)
  },
)

#show heading.where(level: 1): set text(size: 18pt)
#show heading.where(level: 1): it => pad(top: 4pt, it)

#show heading.where(level: 2): set text(size: 14pt)
#show heading.where(level: 2): it => pad(top: 4pt, it)

#show heading.where(level: 3): set text(size: 14pt)
#show heading.where(level: 3): it => pad(top: 4pt, it)

#let frontmatter = (
  FileType: "typst",
  Source: "https://github.com/enmanuelmag/agent-harness-kit",
  ArtifactType: "Open-Source Project",
  PublishDate: "2026/05/08",
  Keywords: [Agent Harness]
)

= Overview
[agent-harness-kit](https://github.com/enmanuelmag/agent-harness-kit?utm_source=chatgpt.com) is a lightweight 
orchestration framework for structured multi-agent software development workflows. Rather than treating an “AI coding agent” as a single monolithic assistant, the project formalizes development work into a coordinated pipeline of specialized agents with clearly separated responsibilities. The framework is intentionally provider-agnostic, meaning it can work with tools like Claude Code, OpenCode, or other MCP-compatible systems instead of being tied to one vendor or model ecosystem. ([GitHub][1])

The core idea is what the project calls a “harness”: a runtime structure that governs how agents collaborate, hand off work, validate outputs, and persist state. The framework defines four primary agent roles: a Lead agent that orchestrates tasks, an Explorer agent that analyzes the codebase without modifying it, a Builder agent that implements changes, and a Reviewer agent that validates the results against acceptance criteria and health checks. This separation resembles a formalized software engineering workflow more than a typical autonomous agent loop. In practice, the harness acts as a coordination layer around LLMs rather than replacing the LLM itself. ([GitHub][1])

A notable design choice is that the system is highly local-first and operationally simple. Instead of requiring cloud orchestration services or distributed infrastructure, it stores workflow state in SQLite and exposes tooling through CLI commands and an MCP server. Tasks are maintained in structured backlog files such as `feature_list.json`, while all actions, file modifications, and workflow transitions are logged into a local audit trail database. The project also includes concepts like health checks, writable-path restrictions, and explicit task acceptance criteria, which push the framework closer to disciplined engineering automation rather than “free-form vibe coding.” ([GitHub][1])

Architecturally, the project aligns with a growing trend in what recent research calls “harness engineering”: the idea that agent performance depends not only on the underlying LLM, but on the orchestration logic, execution contracts, tool boundaries, and memory/runtime structure surrounding it. The harness becomes a reusable, inspectable control system. In that sense, agent-harness-kit is less about inventing a new autonomous agent and more about standardizing the operational scaffolding around agents. That is probably why the project emphasizes auditability, deterministic workflows, and role isolation instead of fully autonomous behavior. ([arXiv][2])

One interesting aspect relative to SemOS and “path-native exploration” ideas is that this project treats the harness 
as an explicit engineering artifact rather than hidden controller code. The Lead → Explorer → Builder → Reviewer 
pipeline is effectively a codified software process encoded into prompts, configs, and runtime contracts. 
Compared with systems like Claude Code, which often hide orchestration internally, agent-harness-kit exposes the 
workflow structure directly to developers. That makes it easier to customize, reason about, and potentially evolve 
into more sophisticated multi-agent systems with richer memory, retrieval, or knowledge-base integration later on.

For the four agent roles: Explorer, Builder, Reviewer and Lead, the first three can
and mostly are implemented through skills. These are essentially task modes with instructions, 
constraints, and output formats, which is exactly what skills are good at.

The Lead role is different. It is less a skill and more a controller / harness / workflow manager. The Lead decides:

- which skill to invoke
- in what order
- when to stop
- whether Builder must revise
- whether Reviewer passed or failed
- how state is persisted
- how tasks move through lifecycle stages

In other words, skills can implement role behavior, but the harness implements role coordination.

Note that LLMs are stateless and memory-less. It knows nothing about you and the conversations, the history,
the context. Without the harness, LLMs must remember and enforce the workflow every time. A harness makes 
the workflow explicit and durable: task state, audit trail, permissions, acceptance criteria, retries, and transitions.

== Thoughts
There are many agent harness implementations, include:
- Claude Code
- Codex
- Qwen Code
- ...
- OpenClaw
- OpenCode
- Pi
- Crush
- ...

It appears to me that this is another one. I am not sure whether I am going to use it. Probably we can learn
something from it.

It designed four agent roles: Lead, Explorer, Builder and Reviewer. I am not sure whether this is a good
idea. If something can be implemented through skills, we should use skills because skills are higher level
abstraction object. It leverages the underlying harness, a mechanism to implement application-specific
business logic.

Any time when we are talking about agent harness, we need to think about "What Is an Agent Harness".

== Status
Will come back when we dive deep into Agent Harness.

== References
[1]: https://github.com/enmanuelmag/agent-harness-kit/tree/main/docs?utm_source=chatgpt.com "docs"

[2]: https://arxiv.org/abs/2603.25723?utm_source=chatgpt.com "Natural-Language Agent Harnesses"

