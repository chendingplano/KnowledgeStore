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
    "Review - Tecent Agent Memory"
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
  Source: "https://github.com/Tencent/TencentDB-Agent-Memory",
  ArtifactType: "Open-Source Project",
  DocumentDate: "2026/05/18",
  Keywords: [Memory, LLM Memory, Memory Management, Tencent, TencentDB],
)

#let a_001 = link(
  "https://github.com/Tencent/TencentDB-Agent-Memory"
)[#text(fill:blue)[TencentDB Agent Memory]]

= Overview
Tencent’s TencentDB-Agent-Memory is an open-source memory subsystem for AI agents, focused on solving a common agent failure mode: loss of context across long sessions or across separate sessions. Rather than treating “memory” as a flat vector store of retrieved chat snippets, the project implements a structured, layered memory architecture intended to progressively distill raw interaction history into increasingly abstract and reusable forms. The stated goal is to reduce token pressure, improve task continuity, and let agents reuse prior experience instead of repeatedly rediscovering the same context. It is designed to run locally with no required external memory API dependencies. ([Tencent Cloud][1])

Architecturally, the most interesting aspect is its four-tier progressive memory model (often described as L0–L3). The lower layers retain fine-grained operational details—conversation traces, tool outputs, transient working context—while higher layers compress these into symbolic or semantic abstractions such as reusable knowledge, task patterns, or persona-like summaries. This is notably different from many “RAG-style memory” systems that simply embed prior text and retrieve semantically similar chunks. Tencent’s design is closer to a memory hierarchy: short-term working memory + compressed episodic memory + distilled long-term knowledge. The system also emphasizes traceability, meaning higher-level abstractions can still be linked back to original evidence instead of becoming opaque summaries. ([Tencent Cloud][1])

From an engineering perspective, the project appears aimed at agent-runtime integration rather than being merely a storage library. It already exposes integrations with frameworks like OpenClaw and Hermes, suggesting Tencent sees this as middleware for agent orchestration stacks rather than just a database-backed retrieval component. The retrieval model combines semantic and keyword-style recall rather than relying exclusively on embeddings, which makes sense for operational agent memory where exact identifiers, commands, filenames, or tool outputs often matter more than semantic similarity alone. This makes it closer to an “agent cognition layer” than a conventional vector-memory plugin. ([Tencent Cloud][1])

== Example

Scenario: AI coding agent fixing a bug in a large codebase

Suppose you tell an agent: “Fix the PostgreSQL status update bug in our KB system.”

The actual issue is:

```sql
update kb.inputs set status = "{}" where id = 20
```

which fails because PostgreSQL interprets `"{}"` as an identifier rather than a string/JSON literal.

The agent begins exploring the repo.

*L0 — Raw working memory (immediate context)*

This is the noisy, uncompressed operational trace.

Examples:

```text
User asked to fix PostgreSQL update bug.

Searched repository for "update kb.inputs".
Found:
  input_repo.go
  migration.sql
  tests/input_test.go

Executed SQL:
update kb.inputs set status = "{}" where id = 20

Error:
ERROR: column "{}" does not exist

Hypothesis:
status may be JSONB.
Need '{}'::jsonb or '{}' as string.
```

This layer is basically the agent’s scratchpad.

Characteristics:

- detailed
- transient
- high token cost
- exact execution traces
- tool outputs
- command history

Equivalent to human “working memory.” Without compression, this grows explosively.

*L1 — Episodic memory (task summary)*

After the task progresses, the system compresses L0 into a cleaner task-level summary.

Example:

```text
Task: Fix PostgreSQL update bug in kb.inputs.

Root cause:
status column is JSONB.
Using "{}" in double quotes makes PostgreSQL parse it as a column name.

Resolution:
Use:
'{}'::jsonb

Affected files:
input_repo.go
tests/input_test.go
```

Notice what disappeared:

- search noise
- failed attempts
- raw command outputs

But important task knowledge remains. This becomes reusable if the task resumes tomorrow.

*L2 — Semantic knowledge (generalized lesson)*

Now the system abstracts beyond the specific incident.

Example:

```text
PostgreSQL rule:
Double quotes denote identifiers.
Single quotes denote string literals.

For JSONB empty object assignment:
'{}'::jsonb
```

This is no longer what happened. It is what was learned (i.e., knowledge).
This matters because future tasks can reuse it. For instance, if users
ask: “Why is my JSONB update failing?”, the agent can retrieve this directly 
without replaying the whole prior debugging session.

*L3 — Procedural / behavioral memory (agent skill)*

Now the system extracts a reusable operational heuristic.

Example:

```text
When PostgreSQL SQL errors mention:
column "<literal>" does not exist

Check whether:
- a literal was incorrectly double-quoted
- JSON/JSONB syntax is malformed
- identifier quoting rules were violated
```

This is closer to a *skill* than memory. Now the agent becomes better 
at debugging SQL generally.

Next time it sees:

```sql
update users set profile = "{}"
```

it immediately suspects quoting.

*Comparing with RAG*

A normal vector-memory system stores chunks like:

```text
"ERROR: column {} does not exist"
```

Later it retrieves semantically similar snippets. That works, but it’s shallow.

Tencent’s approach transforms memory:

Raw trace:

```text
I ran command X and got error Y
```

becomes knowledge:

```text
PostgreSQL identifier quoting rules
```

then becomes behavior:

```text
If this pattern occurs, investigate quoting
```

So memory evolves instead of remaining static retrieval text.

This is roughly:

```text
| Tencent Memory | SemOS |
| -------------- | ---------------------------------------- |
| L0             | raw docs / chat logs / execution traces  |
| L1             | document summaries                       |
| L2             | normalized knowledge objects             |
| L3             | SKILL.md / reusable reasoning heuristics |
```

The biggest conceptual difference:

*Tencent’s memory is agent-centric and automatic.*

The agent silently converts experience into memory.

Your MKBP is more knowledge-centric and explorable:

- files
- graphs
- explicit metadata
- inspectable docs
- deliberate traversal by LLMs

Tencent’s model asks:

> “What should the agent remember?”

Your model asks:

> “What knowledge should exist so an agent can explore it?”

That’s a fundamental architectural difference.

== Scene Block

“Scene Block” is arguably the most interesting idea in TencentDB-Agent-Memory, because it is 
not simply memory chunk with a better name. It appears to sit between raw episodic memory 
and abstract knowledge—something like a structured situational memory unit.

Think human memory:

*L0 — Working memory*

What just happened.

Example:

> I ran `pytest`.
> Test `test_auth_login` failed.
> Stack trace says token expired.

Messy, immediate, noisy.

*L1 — Episode memory*

A coherent event summary.

Example:

> While debugging login failure, discovered JWT expiration mismatch between backend and frontend.

Cleaner, but still tied to a specific event.

*L2 — Scene Block*

A reusable *situation model*.

Example:

"Authentication failure caused by token lifecycle mismatch":

- actor: frontend
- actor: backend
- resource: JWT token
- condition: expiration mismatch
- observable symptom: login rejected
- remediation: align TTL settings

This is no longer just “what happened.” It is a structured semantic situation.

*L3 — Skill / heuristic*

It defines general reusable behavior, such as:

"If auth failures appear after successful issuance, inspect token expiry consistency."

Scene Block is the bridge between event memory and generalized skill.

=== Scene Block Definition

Conceptually, *Scene Block = a structured representation of a meaningful situation.*

A scene is not merely text.

It captures:

- context
- actors
- objects/resources
- state
- actions
- triggers
- outcomes
- relationships
- meaning

In cognitive terms, this resembles:

- episodic schema
- event frame
- situation model
- semantic episode abstraction

=== Concrete Example: Coding Agent

Suppose an agent debugs:

```sql
update kb.inputs set status = "{}"
```

L0 raw traces:

```text
searched repo
opened schema.sql
ran SQL
error: column "{}" does not exist
checked status type
found JSONB
fixed syntax
```

Too noisy.

L1 episode:

```text
Fixed PostgreSQL JSONB update bug caused by invalid quoting.
```

Better, but still flat.

L2 Scene Block:

```json
{
  "scene_type": "database_debugging",
  "scene_name": "postgres_jsonb_update_failure",

  "actors": [
    "agent"
  ],

  "systems": [
    "postgresql"
  ],

  "resources": [
    "kb.inputs.status"
  ],

  "conditions": [
    "status column type is JSONB"
  ],

  "trigger": {
    "event": "sql_update_execution"
  },

  "symptoms": [
    "column \"{}\" does not exist"
  ],

  "root_cause": [
    "double quotes interpreted as identifier"
  ],

  "resolution": [
    "'{}'::jsonb"
  ],

  "outcome": [
    "successful update"
  ]
}
```

Now this is reusable. Future matching:

Agent sees:

```sql
update users set profile = "{}"
```

The scene pattern matches.

=== Scene Blocks and Summaries

A summary says: “Fixed JSONB bug.” A Scene Block says: “This kind of failure occurs under these 
structural conditions.” That means retrieval becomes pattern-based, not just semantic text similarity.
Instead of searching similar wording, the system can search similar situation topology.

Examples:

same:

- SQL syntax issue
- JSONB column
- identifier parsing symptom

even if wording differs.

Another example: standards / compliance (your domain)

Document text:

```text
Vaccine refrigerators shall maintain 2–8°C continuously.
Temperature excursions shall trigger alarms.
```

L1 summary:

```text
Cold-chain storage temperature requirements.
```

Weak retrieval.

Scene Block:

```json
{
  "scene_type": "cold_chain_monitoring",

  "actors": [
    "storage_operator"
  ],

  "resources": [
    "vaccine_refrigerator",
    "temperature_sensor",
    "alarm_system"
  ],

  "constraints": [
    "temperature between 2C and 8C"
  ],

  "trigger": [
    "temperature excursion"
  ],

  "required_action": [
    "raise alarm"
  ],

  "goal": [
    "maintain vaccine viability"
  ]
}
```

Now future queries like:

> "Find standards about vaccine alarm requirements"

can match structurally.

=== Scene Block vs Knowledge Graph Nodes

A KG node is usually atomic, fragmented:

```text
Concept: vaccine
Concept: alarm
Relation: triggers
```

A Scene Block preserves the whole situation. It is closer to a graph 
subgraph or semantic frame.

We can think: KG node = noun and Scene Block = sentence / event Or KG = ontology primitives,
Scene Block = instantiated semantic pattern.

=== Scene Block vs RAG Chunking

RAG chunk = paragraph text, while Scene Block = structured semantic object.

RAG asks: "what text looks similar?", while Scene asks: "what situation looks similar?"
The differences are huge.

=== Scene Block - A New Dimension in Search

Agents operate in situations, not isolated facts. An agent solving tasks needs:

- context
- current state
- actors
- constraints
- causal structure
- outcomes

“Scene” naturally captures this. It is similar to:

- case-based reasoning
- episodic schemas
- event memory
- semantic frames
- situation modeling

=== Document-Level Semantic Operational Frames

We may consider scene blocks as document-level semantic operational frames.
As an example, the expression in a document: "Rabies exposure case handling",
it is converted to a scene block as:
```json
{
  "scene_type": "post_exposure_vaccination_workflow",
  "actors": ["clinician", "patient"],
  "trigger": ["animal injury"],
  "actions": [
    "record vaccination",
    "record exposure details",
    "report severe incidents"
  ],
  "constraints": [
    "report within 3 hours"
  ]
}
```

This is extremely powerful for explorable knowledge because agents think in 
workflows and situations—not isolated clauses.

== Tecent Agent Memory and SemOS
Conceptually, this project aligns strongly with problems we’ve been exploring around SemOS 
and explorable knowledge systems. However, there is a philosophical difference: SemOS emphasizes 
persistent, inspectable knowledge organized in a filesystem/graph that an LLM can deliberately 
explore (Codex/Claude Code style), whereas TencentDB-Agent-Memory is more runtime-centric and 
automatic—memory is extracted, compressed, and recalled on behalf of the agent. In other words: 
our direction is closer to *explicit knowledge navigation*; Tencent’s is closer to *implicit 
cognitive memory management*.

The four-tier memory model is inspiring. When applying to documents:
- L0: Persona
- L1: Scene Block, Project, Domain 
- L2: Atomic Memory, include Summaries, Topics, Provisions, Metrics, References, etc.
- L3: the original documents or its chunks
#figure(
   image("Images/image_2026051801.png", width: 100%),
   caption: [Hardware setup (#a_001)],
)


== References

[1]: https://cloud.tencent.com/developer/article/2668579?utm_source=chatgpt.com "TencentDB Agent Memory 正式开源：让 Agent 沉淀经验，让人专注创造-腾讯云开发者社区-腾讯云"

