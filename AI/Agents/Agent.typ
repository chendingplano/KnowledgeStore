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
    "Reading-202602"
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

// #table(
//  columns: 3,
//  align: left,
//  [Name], [Description], [Documentation],
//  [Bicep], [Microsoft], [Azure-specific],
//
// #figure(
//   image("Images/image_2026030101.png", width: 100%),
//   caption: [Hardware setup (#a_030105)],
// )

= Agent

*High-Level Memtal Model*

```text
[ User Interface ]
        ↓
[ AI Assistant (product layer) ]
        ↓
[ Orchestrator / Agent Engine ]
        ↓
[ Agent Loop(s) ]
        ↓
[ Tools / Skills / Plugins ]
        ↓
[ Memory Systems ]
        ↓
[ LLM (stateless reasoning core) ]
```

*Agent*
```text
   Agent = LLM
         + Skills (tools)
         + Loop Policy
         + Prompting Strategy
         + Memory System
         + Planning
         + Reflection Mechanisms
```

== Agent Loop

This is the defining feature of agents:
```text
while not done:
    think (LLM)
    decide action
    execute tool
    observe result
```

The agent loop is very important. Different agents may have different agent loops.
Most existing agents have one and only one agent loop.

I am thinking about making agent loops as modules that can be configured and changed by users at runtime.

*TODO*:

Need to investivate the differences and details about agent loops.

=== What Makes AI Assistant Different

Agent loop is at the heart of agents. But, on the other hand, agent loops are very abstractive, 
agnostic about the domain, the purpose, and many other nuances of agents. 
- Domain-agnostic
- Task-agnostic
- Architecture-agnostic

In other word, all agents share the same conputational skeleton. This is similar to:
- All programs run on CPUs
- All neural nets do matrix multiplications

In this sense, can we save "All agents are made equal" in the core?
For instance, both Codex and Claude Code are coding assistent (agent). 
If Claude Code and Codex both use the same LLM (hypothetically) and use the same skills, 
they are essentially the same: in terms of what they can do and the quality of doing them?

The short answer is: NO!

Because what matters is not the parts, but how they are composed and controlled.
Even with identical LLM + tools + skills, agents can behave very differently du to many factors.

==== Prompting / System Design

Two agents can use the same LLM but:

- different system prompts
- different instructions
- different constraints

Example:
- One agent: “be cautious, ask before acting”
- Another: “act aggressively and autonomously”

👉 Same brain, different personality & behavior

==== Loop Strategy 

The loop is abstract - but its implementation is not:
- How many steps allowed
- When to stop
- When to retry
- Error recovery strategy
- Relfection
- Self-critique

==== Memory 

Even with the same tools, different memory implementation has big impact on the final results.
- What gets remembered
- How it is retrieved
- When it is injected

==== Tool Usage Strategy

Same tools ≠ same usage. LLMs decide:
- When to use tools
- which tools to use
- How to chain them

One agent may: 
```text
write code → tests → fixes, repeat until the maxi retries is reached or all problems are fixed.
```
Another agent may:
```text
writes once → stops
```

These are in the details of agent loops.

==== Planning vs Reactive Behavior

Aome agents may plan ahead (multi-step decomposition), while other agents may act step-by-step without planning.
This dramatically affects:
- Correctness
- Efficiency
- Robustness

With two agents both plan, they may plan tasks at different levels, depth, etc.

==== Evaluation and Feedback Loops

Advanced agents include:
- Self-critique
- Test execution
- Scoring
- Re-planning

This is where systems like coding agents really differ.

==== Execution Environment

Even if skills are the same:
- Sandbox vs real system
- Latency
- Parallelism
- Caching

==== Retry Logic

When unexpected or errors happen, different agents may retry differently.
One agent may give up whatever being done and re-do it from scratch. 
Another agent may repair or improve what were done. One may ask users for assistance or
opinions, while others may just decide to do it automatically.

==== Error Handling

Agents may interpret errors differently. Some agents may ignore all the warnings while
other agents try to solve all the warnings, including linting.

==== Chunking Problems

Different agents may chunk (break down) problems differently.

=== Ralph Loop

This is a higher-level loop. Conceptually, it runs on top of the agent loop, forcing the agent
to re-do or re-think what it has done, aiming at achieving better results by simply repeating
what were done.

Conceptually, ralph loop may use different methods in subsequent loops. One example is to
use one LLM or one agent loop for as the initial run. The next run uses a different LLM
to review the implementation. If it found something to fix/improve, do it.

Another important aspect of ralph loop is introducing a Test Expert (skill).
It reviews the implementation and the tests to determine whether the test is sound and thorough.
If not, it can add additional tests.

In other word, ralph loops are not just repeating. It handles the same task from different
answers, using different tools or methods, using different LLMs, etc.

== Harness 

Harness is the infrastructrue that connects LLM + tools + memory + execution. It includes:
- Prompt construction
- Tool wiring
- Retries
- Logging
- Memory injection
- Safety checks


