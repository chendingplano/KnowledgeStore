#import "@preview/diagraph:0.3.6"
#import "@preview/oxdraw:0.1.0": *

#set heading(numbering: "1.")
#set quote(block: true)
#show quote: set pad(x: 1em)
#show raw.where(block: true): block.with(fill: luma(240), inset: 1em, radius: 0.5em, width: 100%)

#set page(numbering: "i")
#counter(page).update(1)

= Table of Contents
#outline()
#pagebreak()

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
    "Everything Claude Code"
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

#show heading.where(level: 4): set text(size: 12pt)
#show heading.where(level: 4): it => pad(top: 4pt, it)

#set page(numbering: "1")
#counter(page).update(1)
#counter(heading).update(0)

#let frontmatter = (
  created: "2026/04/13",
  logical_name: "everything-claude-code",
  file_id: "2026041301",
  file_type: "Typst",
  keywords: ["agent harness", "skills", "subagent", "rules"],
  source_url: "https://github.com/affaan-m/everything-claude-code",
  feed: "Hacker News"
)

= Overview

everything-claude-code (ECC) is NOT an app. It’s a *“prebuilt agent harness + ecosystem”* for Code Assistants (such as Claude Code, Codex, etc.). It is a production-grade “agent operating system” layered on top of a code assistant.
It packages: agents, skills, rules, hooks, commands and memory system into something cohesive. ([GitHub][1])

ECC is a concrete implementation of "What does a serious agent system actually look like in practice?”
It is a “configuration OS”, not a framework, No runtime. No server. It just adds files, prompts, structure, etc.
But behaves like a system.

ECC is more a *process-aware AI*. By 'encoding' steps in software development into the workflow, instead of letting
users "remember to do code review”, it becomes *an agent that always does code review*.

The system is structured into 4 layers:

1. Interaction Layer: “Interface to the harness”: This is how you talk to the system: through slash
   commands (`/plan`, `/tdd`, `/review`, etc.), rules (always-loaded constraints). Example: `/plan` will trigger the
   planning agent, `/tdd` switches to test-driven workflow.

2. Intelligence Layer: “Agents + Skills”: This is the core. This is a fast-growing project. Subagents are agents
   with constrained capabilities. Originally, it had 13 subagents. Now (2026/04/13), it has 47 specialized subagents,
   181 skills, and 79 commands in version 1.10.0 [GitHub][3].. Examples 
   of agents: Planner, Architect, TDD, Code Reviewer, etc.

3. Automation Layer: “Hooks (THIS is underrated)”: Hooks = event-driven automation. Examples:

   - Before tool use: validate
   - After tool use: verify
   - Session start: load memory
   - Session end: persist learning

   Hooks turn the agent from reactive to an autonomous workflow engine.

4. Learning Layer: “Memory + evolution system”: This is an important feature. There are two systems: 
   (1) Skill extraction: Extract patterns from sessions and store them as reusable skills, (2) Instincts: fine-grained
   behaviors with confidence scores; can be merged into skills.

   This layer forms a primitive self-improving agent loop.

== Core Design Ideas

*1. Multi-Agent Orchestration (NOT single LLM)*

It implements a Pipeline-based agent collaboration. Workflow example:

1. Planner → breaks tasks
2. Architect → designs system
3. TDD agent → writes tests
4. Review agents → validate
5. E2E agent → runs tests
6. Doc agent → updates docs

*2. Context Window Economics*

They explicitly optimize:

- Rules = always loaded (~5–8K tokens)
- Skills = loaded on demand
- Agents = activated dynamically

This is one of the few repos that treats context as a scarce resource. ([Apiyi Blog][2])

*3. Security-First Agents (AgentShield)*

There are 900+ rules as of this writing (2026/04/13). They can detect API leaks, permission issues, prompt injection vectors, etc.

*4. Continuous Learning (Cross-Session Memory)*

It can save patterns between sessions; evolves behavior over time.


*5. Encodes *Process*, not just Capability*

Most tools just generate code. ECC instructs the system how to build software correctly. It does so by:

- forces TDD
- enforces review
- enforces architecture step

== Workflows

What exactly is a workflow?

Workflow is not a first-class primitive in most agent systems. It’s an emergent pattern implemented through other
primitives.

A workflow = a *controlled progression of state transitions* over a task, driven by policies (rules), capabilities
(skills/tools), and coordination (agents). A workflow is:

- stateful
- conditional
- possibly branching
- possibly iterative (loops)
- enforced (or nudged) by the system

Workflow is a pattern formed by the interaction of:

- user intent
- agent roles
- skills
- rules
- control logic
- memory/state

Most agent systems do not have native workflow object (like BPMN, Airflow DAG, etc.). But there is workflow behavior,
implemented implicitly. Workflow exists conceptually, but not structurally in these systems.

A workflow normally consists of:

1. Intent: (user input), such as 'Build a feature'
2. Routing / Delegation: the system determines which agent to handle it, harness it to the agent.
3. Execution Steps (hidden or explicit), such as (1) plan, (2) design, (3) implement, (4) test and (5) review,
   implemented by skills, subagents, or even hard coded.
4. Control logic: such as “Don’t write code until plan is approved”, “Run tests after code”, “If fail → fix → retry”
5. State, such as plan exists? code written? tests passing?

Note that:

- Skills encode capabilities or procedures, not full workflows. They are reusable, stateless and local, such as
  “how to write a REST API”, “how to refactor code”. Skills are more like functions than workflows.
- Subagents implement *roles with policies*, which *participate in workflows*. They don’t own the full workflow,
  but own *a slice* of it. For example, 'planner': planning phase, 'reviewer': validation phase. A subagent is like:
  a *service in a pipeline*.
- Agent Harness: The harness is where workflows *emerge or are enforced*. It provides routing, memory, tool access,
  lifecycle hooks, etc. Agent Harness is the *runtime where workflows happen*.

What we should do is to treat workflow as an object. Workflows can be defined in YAML, suchas:

```yaml
workflow:
  name: "feature-development"
  states:
    - plan
    - design
    - implement
    - test
    - review
  transitions:
    - from: plan
      to: design
      condition: approved
    - from: test
      to: implement
      condition: failed
  agents:
    plan: planner-agent
    design: architect-agent
    implement: coder-agent
    test: tester-agent
```

In our system:
- agents = executors
- skills = tools
- workflow = control plane

== Limitations

1. Still prompt-engineering-heavy: Skills = markdown prompts; Not structured programmatically
2. No true stateful backend: Memory is file-based, Not a real DB / retrieval system (note that this may not be a limitation!)
3. Multi-agent = expensive: Each agent = separate API call ([Apiyi Blog][2])

== How to Use ECC

ECC just enriches the environment. Users normally do not need to explicitly mention ECC in order to use it.
But users can use its slash commands, skills, etc. These commands and skills are just normal ones.
ECC, however, forces loading all the rules (about xxx KB size). The code assistant should be smart enough to
*delegates user requests to the right subagent when appropriate*. The planner agent, for example, is described
as “Use PROACTIVELY” and “Automatically activated for planning tasks.” ([GitHub][4])

That said, *you can also force it explicitly* through a command. For example, `/plan` explicitly invokes the `planner` agent.
The repo’s plan command says exactly that: “This command invokes the planner agent.” ([GitHub][5])

=== Agent Routing

Using subagents can be automatic or manual. 
There is clearly an *automatic delegation* model. For example, `/build-fix` is documented as detecting build errors
and *delegating to the right build-resolver agent automatically*. ([GitHub][7])

There is also clearly a *manual/explicit orchestration* model, because the repo includes commands like `/orchestrate`, `/devfleet`, `/multi-plan`, `/multi-workflow`, and `/multi-execute`, which are explicitly about multi-agent or multi-model coordination. ([GitHub][8])

For many tasks, the main assistant can invoke subagents automatically. For special workflows, you can 
*explicitly trigger a command* that launches a particular workflow. For more advanced parallel orchestration, the repo
gives you manual orchestration commands.

=== Slash Command

A *slash command* is basically a named workflow entrypoint exposed in Claude Code. The repo’s quick reference says
these are commands you can invoke by typing `/` in a session. `/plan` is one of those commands. ([GitHub][8])

For `/plan` specifically, the repo says it:

- restates requirements
- assesses risks
- writes a step-by-step plan
- then *waits for your confirmation before touching code*. ([GitHub][5])

So `/plan` is *not just “use the planner subagent raw.”* It is better thought of as a packaged workflow that uses the
planner agent in a specific way. That means a slash command is not identical to a skill and not identical to a subagent.

A useful distinction is:

- *Subagent* = specialized worker
- *Skill* = reusable know-how / instructions / reference material
- *Slash command* = user-facing trigger for a workflow, often invoking one or more agents and/or skills

That framing is consistent with the repo docs: rules define broad standards, skills provide deep task guidance, 
and commands act as named operational workflows. ([GitHub][9])

= References

[1]: https://github.com/affaan-m/everything-claude-code/blob/main/CLAUDE.md?utm_source=chatgpt.com "everything-claude-code/CLAUDE.md at main"

[2]: https://help.apiyi.com/en/everything-claude-code-plugin-guide-en.html?utm_source=chatgpt.com "Decoding everything-claude-code: A Comprehensive Analysis ..."

[3]: https://github.com/affaan-m/everything-claude-code/blob/main/AGENTS.md "everything-claude-code/AGENTS.md at main · affaan-m/everything-claude-code · GitHub"

[4]: https://github.com/affaan-m/everything-claude-code/blob/main/agents/planner.md "everything-claude-code/agents/planner.md at main · affaan-m/everything-claude-code · GitHub"

[5]: https://github.com/affaan-m/everything-claude-code/blob/main/commands/plan.md "everything-claude-code/commands/plan.md at main · affaan-m/everything-claude-code · GitHub"

[6]: https://github.com/affaan-m/everything-claude-code/issues/84?utm_source=chatgpt.com "How to resolve the conflict between the planner subagent ..."

[7]: https://github.com/affaan-m/everything-claude-code/blob/main/COMMANDS-QUICK-REF.md "everything-claude-code/COMMANDS-QUICK-REF.md at main · affaan-m/everything-claude-code · GitHub"

[8]: https://github.com/affaan-m/everything-claude-code/blob/main/COMMANDS-QUICK-REF.md?utm_source=chatgpt.com "everything-claude-code/COMMANDS-QUICK-REF.md at ..."

[9]: https://github.com/affaan-m/everything-claude-code/blob/main/rules/README.md "everything-claude-code/rules/README.md at main · affaan-m/everything-claude-code · GitHub"

[10]: https://github.com/affaan-m/everything-claude-code/issues/88?utm_source=chatgpt.com "This installation method will not recognize the rules · Issue ..."
