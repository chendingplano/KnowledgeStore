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

= List of Figures
#outline(
  title: [],
  target: figure.where(kind: image),
)
#pagebreak()

*Change History*
#table(
  columns: 2,
  align: left,
  [Date], [Remarks],
  [2026/03/21], [Created, file name: AgenticSystem.typ],
  [2026/04/10], [Moved Knowledge Base part to [Semantic Object Store]]
)

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
    "Agent"
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
  created: "2026/03/21",
  logical_name: "AgenticSystem",
  file_type: "Typst",
  keywords: ["Agentic", "Agentic System", "Agent"]
)

#let ref_001 = link("file://file/full/path:@sec2")[#text(fill: blue)[LLMs]]


= Semantic Object Store (SemOS)

*Build one context system with different memory classes, not separate knowledge base system and memory,
enhanced with explorability*

Current memory systems are converging on a similar shape: a small always-in-context layer for durable
user/agent facts, plus a much larger on-demand archival layer for facts, documents, and other retrievable
knowledge. The system explicitly separates core memory from archival memory, where core memory is always
visible in-context and achival memory is queried on demand or `explored` by #ref_001.

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
[ Memory Systems (SemOS)]
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

Depending on the complexity, agents may be classified by complexity.

A modern agentic system can be viewed as:
```text 
    LLM + Skill + Tools + Iteration + Friendly Dataset + Strong Backend
```

*Level 1 App Agent (minimal, most useful)*
```
  Agent = LLM + tool usage loop
```

This is what most frameworks (LangChain, etc.) implement. It is called App Agent because
each such agent implements a specific feature (or app).

*Example - PR reviewer agent*
```text
  Input: GitHub PR

  Skills:
    1. fetch diff
    2. run tests
    3. static analysis

  Loop:
    analyze → comment → refine
```

That’s a real “agent”. Note that most app agents can be implemented through skills.
That is probably the reason why OpenAI team YouTubed "Don't Create Agents. Create Skills".

When to create an agent and when to create a skill? This can be very simple: can you implement
the `agent` that you want to create by skills? If yes, create skills instead.

Creating an agent normally implies that you want to change some of the characteristics of agents
(see below for Agent Loop), such as memory management.

*Level 2 (structured agent)*
```
  Agent = planner + tools + memory + execution loop
```
It adds planning step, tool selection and state tracking.

*Level 3 (product agent)*
```text
  agent = full system (Codex, Claude Code, OpenClaw, OpenCode, etc.)
```

It includes user interfaces, infrastructures, scaliing and reliability engineering.

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

=== What Makes AI Assistant Different aaa

Agent loop is at the heart of agents. But, on the other hand, agent loops are very abstractive, 
agnostic about the domain, the purpose, and many other nuances of agents. 
- Domain-agnostic
- Task-agnostic
- Architecture-agnostic

One agent may: 
```text
write code → tests → fixes, repeat until the maxi retries is reached or all problems are fixed.
```
Another agent may:
```text
writes once → stops
```

In other word, all agents share the same computational skeleton. This is similar to:
- All programs run on CPUs
- All neural nets do matrix multiplications

In this sense, can we save "All agents are made equal" in the core?
For instance, both Codex and Claude Code are coding assistent (agent). 
If Claude Code and Codex both use the same LLM (hypothetically) and use the same skills, 
they are essentially the same: in terms of what they can do and the quality of doing them?

The short answer is: NO!

Because what matters is not the parts, but how they are composed and controlled.
Even with identical LLM + tools + skills, agents can behave very differently du to many factors.

=== Explorability <explorability>

(TBD)

=== `Brain`

Harness will completement LLMs with local knowledge. This is used to be handled by RAG.
Harness turns things around. Instead of using RAG to find the relevant information for LLMs,
Harness manages the `external knowledge` in such a way that LLMs can effectively explore
the knowledge base for the things they need.

Knowledge base used to be handled by tools, such as vector databases, graph databases, 
search engines (such as ElasticSearch) or even relational databases. They may still be important,
but these are difficult to use and not designed for LLMs.

File-based knowledge are much more explorable than these tools.

=== Knowledge Base

Refer to [Knowledge Object Store]

=== Multi-Agents

(TBD)

=== Prompting / System Design

Two agents can use the same LLM but:

- different system prompts
- different instructions
- different constraints

Example:
- One agent: “be cautious, ask before acting”
- Another: “act aggressively and autonomously”

👉 Same brain, different personality & behavior

=== Loop Strategy

The loop is abstract - but its implementation is not:
- How many steps allowed
- When to stop
- When to retry
- Error recovery strategy
- Relfection
- Self-critique

=== Tool Usage Strategy

Same tools ≠ same usage. LLMs decide:
- When to use tools
- Which tools to use
- How to chain them


These are in the details of agent loops.

=== Decition Making

There can be quite a few places where agents may need to make decisions:
- When there are too many errors
- Unexpected happens
- Abnormal conditions, especially malicious attempts are detected
- Violating the guardrails
- Tasks/skills spent too long time
- ...

=== Planning vs Reactive Behavior

Aome agents may plan ahead (multi-step decomposition), while other agents may act step-by-step without planning.
This dramatically affects:
- Correctness
- Efficiency
- Robustness

With two agents both plan, they may plan tasks at different levels, depth, etc.

=== Evaluation and Feedback Loops

Advanced agents include:
- Self-critique
- Test execution
- Scoring
- Re-planning

This is where systems like coding agents really differ.

This is often called Outcome-Oriented (vs. Response-Oriented).

#let r_002 = link(
  "https://mp.weixin.qq.com/s/jnKW_jxGbvlMzrW_T2GJ1A"
)[#text(fill: blue)[\[2\]]]

LangChain DeepAgents (#r_002) has a HumanEval that has 160+ manually created checks.
One can use these checks to determine the quality of the code created by AI.

Karparthy (ref?) Autoresearch is another example. The main idea is to automate
a process or a loop. In each iteration, it tries to improve the system, then run the valuation
to determine to keep the changes (getting better) or abandon the changes (no improvements
or getting worse).

The most critical part is the evaluation package. Different applications, skills or
the objects to create may require different evaluation criteria. 

=== Execution Environment

Even if skills are the same:
- Sandbox vs real system
- Latency
- Parallelism
- Caching

=== Conditional or Branching

Complex workflow is normally not linear or straight. This can be driven by a decision tree,
by a graph, or whatever mechanisms it can use to accomplish complex tasks.

=== Retry Logic

When unexpected or errors happen, different agents may retry differently.
One agent may give up whatever being done and re-do it from scratch. 
Another agent may repair or improve what were done. One may ask users for assistance or
opinions, while others may just decide to do it automatically.

=== Error Handling

Agents may interpret errors differently. Some agents may ignore all the warnings while
other agents try to solve all the warnings, including linting.

=== Chunking Problems

Different agents may chunk (break down) problems differently.

=== Testability

(TBD)

=== Heartbeat

(TBD)

=== Selv-Evolving

(TBD)

=== Trainability

(TBD)

=== Tasks

In the current framework, there are:
- Agents
- Skills
- Plugins

Different agents implement different harness for a specific type of tasks. I am not sure what plugins
really are.

What is *Task*?

== Tools

Most agents work with a fixed set of tools to use. 
We may want to implement a method that lets LLMs express the tools they wish to have.
The idea is that LLMs are the brain. When we want LLMs solve problems, they need to use tools.
The tools should contain not only the existing tools, but also a special tool: Meta Tool,
or a tool that is used by LLMs to express the tools they need.

This can be important when we ask LLMs to solve specific problems through skills.
If a skill wants to debug a third-party app, the LLM may need to access its logs, its documents,
its configurations, its execution environment, related regulations and laws, etc.
LLMs can, of course, ask human users for help. Human users may be able to help, if it is a simple
thing, such as pointing a file or a directory where the documents reside. But two problems, if not more:
1. Human users get involved (affecting automation)
2. Human users may not be good at engineering. They may not be able to help.

Asking tools that are not available yet will interrupt the current workflow, possibly halt the task.
But developing new tools is a way to evolve the AI system. Once the desired tool, upon request,
is developed, LLMs will be able to solve the same/similar tasks in the future without human users
involved.

== Meta Agent

(Note: *Meta Agent* is not a common concept! I may change it in the future when a better name arises.)
A *Meta Agent* is a computing paradigm that treats an agent, or even a group of agents, as computing blocks.
It may:
- iterate on the same agent (such as Ralph Loop)
- coordinate multiple agents (i.e., multi-agent systems)
- combine conventional programs and agents

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

For more information about harness, please refer to HarnessEngineering.typ.

== Multi-Agent Architecture

#let a_031 = link(
  "https://dzone.com/articles/scalable-agentic-ai-assistants-graph"
)[#text(fill: blue)[Agentic Architecture]]

#a_031

#figure(
  image("Images/image_2026032501.png", width: 100%),
  caption: [Multi-Agent Architecture (#a_031)],
)

In this architecture, there are:
- Supervisor
- Worker

=== Supervisor

The supervisor examines an incoming request and decides which agent is best to handle it. It then
routes the request to the agent.

There should be a default agent that handles requests that are not for other agents.

```python
# Orchestrator State Management
state = {
    "user_id": "abc123",
    "conversation_history": last_3_turns, # Not entire history
    "current_domain": "payments",
    "session_context": {
        "merchant_id": "merch_789",
        "date_range": "last_30_days"
    }
}
async def orchestrate(query: str, state: dict):
    # Initialize supervisor based on domain
    supervisor = get_supervisor(state["current_domain"])
    # Pass minimal context, not everything
    result = await supervisor.route_and_execute(
        query=query,
        context=state["session_context"]
    )
    # Update state for next turn
    state["conversation_history"].append(result)
    return result
```

In the above code, `state.current_main` is `payments`. Who sets it? I guess the workflow is:
```text
  Request
    ↓
  Type of Request (by LLM)
    ↓
  Payment
    ↓
  Route to Payment
    ↓
   ...
```

=== Skills or Agents

Are workers agents or skills? Ideally, there are Payment Agent, Dispute Agent,
and Analytics Agent. Each with its own agent loop, history, memory management, set of tools to use, etc.
An agent is like an app.


=== Skill (Worker)

The author calls it worker. I think workers can be implemented as skills.

"Because workers are narrowly scoped, they are easier to test, easier to reason about, 
and easier to extend. Adding a new capability means adding a new worker, not refactoring the entire system."

```python
class PaymentWorker:
    """Handles payment-related queries only"""
    
    def __init__(self, tools: List[Tool]):
        self.tools = {
            "lookup": PaymentLookupTool(),
            "stats": PaymentStatsTool(),
            "export": PaymentExportTool()
        }
    
    async def process(self, query: str, context: Context):
        # Single responsibility: payment lookups only
        tool_name = self._select_tool(query)
        tool = self.tools[tool_name]
        
        # Execute with merchant-specific context
        result = await tool.execute(
            query=query,
            merchant_id=context.merchant_id,
            filters=self._extract_filters(query)
        )
        
        return self._format_response(result)
    
    def _select_tool(self, query: str) -> str:
        """Simple keyword matching for tool selection"""
        if "export" in query.lower():
            return "export"
        elif any(word in query.lower() for word in ["total", "sum", "count"]):
            return "stats"
        else:
            return "lookup"
```

== Cost of Agents

=== Complex Systems Fail in Complext Ways

#let r_001 = link(
  "https://dzone.com/articles/ai-agents-vs-llms-choosing-the-right-tool-for-ai-t"
)[#text(fill: blue)[\[1\]]]

#quote(block: true, attribution:[#r_001])[
Source: Richard Cook, “How Complex Systems Fail”

This is why many agent demos look impressive but collapse under real production constraints. Determinism, observability, and cost control become more difficult as autonomy increases.

A simple rule helps here: if you can clearly describe the task as a single question, you probably do not need an agent.
]

==== CLI, Tools, File-Tree

The system should support all: CLI, tools, and file-tree, with the correct order:

#block(
  inset: (left: 1em, top: 0.5em, bottom: 0.5em),
  stroke: (left: 3pt + luma(180)),
)[
*Backend first*
 → *tool API*
 → *CLI as one client*
 → *LLM tools as another client*
]

A CLI alone is not the architecture. It is just an interface. A set of tools alone is also not
enough if there is no coherent model underneath.

*Canonical backend API*

This is the real system boundary.

Core operations:

- ingest artifact
- read artifact
- search artifacts
- retrieve chunks with citations
- resolve entity
- get linked artifacts
- update metadata
- create derived artifact
- diff versions
- list collections
- enforce permissions

*CLI*

CLI is useful for humans, scripts, and agent harnesses.

Examples:

- `mkbp add file.md`
- `mkbp search "duckdb schema evolution"`
- `mkbp open /projects/x/spec.md`
- `mkbp link /notes/a /topics/b`
- `mkbp diff v12 v13`
- `mkbp export project-x`

*LLM Tools*

These should be narrower and safer than the raw backend.

Examples:

- `search_knowledge(query, filters)`
- `open_artifact(id_or_path)`
- `read_chunk(id)`
- `get_neighbors(entity_or_artifact)`
- `create_note(parent, content)`
- `cite_passages(result_ids)`
- `propose_update(artifact, patch)`

LLMs should not directly manipulate the internal storage model.

*The Mistake to Avoid*

- *expose* raw storage primitives as the main interface.
- a pure filesystem
- a pure relational schema exposed to the LLM
- a vector DB with files glued on
- a CLI-only product
- a giant “universal query language” that the LLM must master

Bad primary interface:

- SQL tables
- raw graph nodes/edges
- opaque vector records
- low-level filesystem ops
- arbitrary shell commands

Those can exist internally, but the LLM-facing surface should be:

#block(
  inset: (left: 1em, top: 0.5em, bottom: 0.5em),
  stroke: (left: 3pt + luma(180)),
)[
 *documented knowledge actions over meaningful artifacts*
]

That is what makes a system LLM-friendly.


Those all either become brittle or too low-level.

=== Architecture for MKBP

A good starting design could be:

*Canonical Object Types*

- Artifact
- Chunk
- Entity
- Relation
- Collection
- Version
- Source
- Job
- Permission policy

*Canonical artifact types*

- markdown
- pdf
- docx
- html snapshot
- transcript
- code file
- table snapshot
- image
- synthesized note
- entity profile

*Core indexes*

- full-text index
- metadata index
- embedding index
- citation/provenance index
- relation graph

*Core APIs/tools*

- ingest
- search
- open
- summarize
- extract
- cite
- link
- compare
- collect
- publish

=== Design

==== Design goal

MKBP should feel like this to users and agents:

- Artifacts
- Search and Exploration
- File-based frontend
- Cite passages
- Link related things
- Create derived notes/artifacts
- Trust Provenance and Versions

The core design is:
#block(
  inset: (left: 1em, top: 0.5em, bottom: 0.5em),
  stroke: (left: 3pt + luma(180)),
)[
 *filesystem-like exploration outside, artifact-aware semantics underneath, strong backend inside*
]

==== Semantic Object layer

Semantic Objects (SemObjs) are the first-class objects visible to users and LLMs.

Examples:

- markdown note
- PDF
- Docs
- HTML snapshot
- meeting transcript
- code file
- table snapshot
- entity profile
- synthesized summary

Each artifact has:

- stable ID
- path-like logical name
- type
- content
- metadata
- source/provenance
- version history
- access policy

==== Semantic layer

These are the derived structures for retrieval and reasoning.

Examples:

- chunks
- summaries
- tags
- extracted entities
- relationships
- embeddings
- canonical aliases

==== Retrieval layer

This layer solves how knowledge is found. It supports:

- keyword search
- semantic search
- hybrid search
- metadata filters
- graph expansion
- reranking
- passage citation

==== Control layer

This layer is responsible for making it safe and debuggable. It supports:

- auth/access control
- validation
- versioning
- drafts vs commits
- audit logs
- ingestion jobs
- retries

==== Storage layer

This is the real substrate. We will consider:

- object store: original blobs and rendered text
- relational DB: metadata, versions, ACLs, jobs, links
- search index: full text
- vector index: semantic retrieval
- queue/worker: ingestion and derivation

*Canonical Data Model*

The data model should be small and durable.


==== Job

Job is for ingestion and background derivation. Fields include:

- `job_id`
- `job_type` (`ingest`, `parse`, `chunk`, `embed`, `extract_entities`, `link`, `summarize`)
- `target_type`
- `target_id`
- `status`
- `attempt_count`
- `error_message`
- `created_at`
- `started_at`
- `completed_at`

==== Access Policy

Access Policy controls who can access which and when. Do not bolt this on later. Fields include:

- `policy_id`
- `resource_type`
- `resource_id`
- `subject_type` (`user`, `group`, `service`)
- `subject_id`
- `permission` (`read`, `write`, `admin`, `discover`)
- `effect` (`allow`, `deny`)

== Links

SemObjs are interconnected. We want to implement the links similar to hyperlinks.

=== Markdown Files

=== Typst

Every Typst file has a frontmatter:
```text
#let frontmatter = (
  created: "2026/03/21",
  logical_name: "AgenticSystem",
  file_type: "Typst",
  keywords: ["Agentic", "Agentic System", "Agent"]
)
```
This is the metadata for the file.

Links are implemented as:
```text
#let ref_001 = link("semobj:semobj_name:location")[#text(fill: blue)[LLMs]]
```

where 'semobj' specifies that this is a semobj. Its (logical) name is 'semobj_name'. ":location" is optional.
If not specified, it refers to the semantic object. Otherwise, it refers to the portion pointed to by 'location'.

=== Locations

The table below lists all the locations SemOS currently supports:
#table(
  columns: 2,
  align: left,
  [Location], [Explanation],
  [`@reference`], [A reference (bookmark)],
  [Line:ddd], [A specific line in the file],
  [Lines:ddd-ddd], [A range of lines in the file],
  [Lines:[ddd, ddd-ddd, ddd]], [Multiple regions in a file]
)

= Daily Notes

== Agentic System Features

#let a_001 = link(
  "https://openai.com/index/harness-engineering/"
)[#text(fill: blue)[OpenAI Agent Harness]]

#a_001 \
[[openai-harness-engineering]]

*Humans Steer. Agents Execute*

Human Loop: Humans design the system, check the results, adjust the design, check again.

Agent Loop: Receive request, think, plan, execute, test, verify, repeat until the task finishes, then wait for the next.

Humans interact with the system almost entirely through prompts: an engineer describes a task, runs the agent,
and allows it to open a pull request. To drive a PR to completion, they instruct Codex to review its own changes locally,
request additional specific agent reviews both locally and in the cloud, respond to any human or agent given feedback,
and iterate in a loop until all agent reviewers are satisfied (a Ralph Wiggum Loop).

*Early Stage Is Slower than Expected*

The reason is not LLMs are incapable, but the environment is underspecified.

*Everything Readable by AI*

Instead of feeding LLMs, they make everything readable by LLMs, mainly through files.

*Increasing Application Legibility*

The real bottleneck is human QA capacity. In order to alleviate human constraints, they add more capabilities to the
agent by making things like the application UI, logs, and app metrics themselves directly legible to Codex.
This means (my understanding) it constructs logs in a meaningful way, calculate app metrics and save them in
files, and (I believe) we can add more to make apps more debuggable, behaviors more explorable without actually
running the app.

They made the app bootable per git worktree, so Codex could launch and drive one instance per change.

- Make the app bootable per git worktree, so Codex could launch and drive one instance perchange.
- Logs, metrics, and traces are exposed to Codex via a local observability stack that is ephemeral for
  any given worktree. Codexworks on a fully isolated version of that app - including its logs
  and metrics, which get torn down once that task is complete.
- Agents can query logs with LogQL and metrics with PrompQL.
- Chrome DevTools Protocol into the agent runtime and created skills for working with DOM snapshots,
  screenshots, and naviation.

#figure(
  image("Images/image_2026041401.png", width: 100%),
  caption: [Codex drives the app with Chrome DevTools MCP (#a_001)],
)

#figure(
  image("Images/image_2026041402.png", width: 100%),
  caption: [Logs and Observibility (#a_001)],
)

== References

#r_001 AI Agents vs LLMs: Choosing the Right Tools for AI Tasks, 2026/03/26, Source: dzone

#r_002 LangChain DeepAgents, 2026/04/02, Source: WeChat

[3] Harness Engineering: Leveraging Codex in an Agent-First World, https://openai.com/index/harness-engineering/, February 11, 2026.

