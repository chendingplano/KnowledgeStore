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
    "EverOS"
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
  created: "2026/04/15",
  logical_name: "EverOS",
  file_id: "2026041501",
  file_type: "Typst",
  keywords: ["Memory", "MemPalace" ,"Memory OS"],
  source_url: "https://github.com/EverMind-AI/EverOS",
  feed: "Wechat"
)

= Overview
*EverOS (a.k.a. EverMemOS)* is an open-source “memory operating system” for AI agents that gives them long-term, structured,
evolving memory beyond context windows ([GitHub][1]). It acts as a persistent memory layer to store past interactions, understand
them, and reuse them intelligently, thus turn LLMs from stateless functions to stateful agents.
A *memory-centric OS for AI agents* that turns conversations into structured, evolving knowledge and uses it to drive reasoning, 
personalization, and self-improvement.

== Key idea: Memory ≠ storage, it’s a *system*

EverOS is not just a vector DB or RAG. It reframes memory as:

> *A cognitive loop: build → organize → retrieve → reason → update*

*(A) Memory Construction*

Extract structured units from conversations: *MemCell* (atomic memory unit ([GitHub][1])), then organize them into:

  - episodes
  - user profiles
  - preferences
  - relationships
Builds multi-level, thematic memory.

*(B) Memory Perception (retrieval + reasoning)*

It uses hybrid retrieval: semantic + keyword (RRF fusion), reranking with deeper relevance, and multi-step reasoning
to compose context, shifting from not just “retrieve relevant chunks” to “reconstruct the right context for reasoning”.

== Architecture

EverOS uses a brain-inspired 4-layer architecture:

#table(
  columns: 3,
  align: left,
  [Layer], [Role], [Analogy],
[Agentic Layer], [task reasoning & planning], [prefrontal cortex],
[Memory Layer], [long-term storage], [cortex],
[Index Layer], [retrieval (embedding, graph)], [hippocampus],
[API/MCP Layer], [integration], [sensory interface]
)
([TMTPOST][2])

== Unique capabilities (what makes it different)

*1. Coherent Narrative Memory*

- Links fragments into stories
- Maintains multi-threaded context

*2. Evidence-based reasoning*

- Uses memory proactively
- Injects contextual constraints into decisions

Example:

- remembers “user had surgery”
- adjusts recommendations automatically

*3. Living user profiles*

- continuously updated
- not static metadata

*4. Self-evolving agents*

EverOS introduces a key concept:

- Case → Skill abstraction: distill into reusable “skills”
- Agents learn patterns from history
- Reuse them later ([EverMind][3])

*6. Data model*

Core abstractions:

- MemCell: atomic fact/event
- MemScene: aggregated context/theme
- Profile: user identity layer
- Case → Skill: learned behavior patterns

```
Raw conversation
  → structured memory
    → semantic grouping
      → reasoning-ready context
```

*7. Retrieval model*

EverOS ≠ classic RAG:

#table(
  columns: 2,
  align: left,
[ Traditional RAG       ],[EverOS              ],
[ retrieve chunks       ],[reconstruct context ],
[ stateless             ],[evolving memory     ],
[ query-driven          ],[memory-driven       ],
[ no user model         ],[persistent profile  ],
[ no temporal reasoning ],[time-aware          ]
)

== Comparing with SemOS:

#table(
  columns: 2,
  align: left,
[ *SemOS* ],[*EverOS Equivalent*],
[ Unified memory (RAG + memory) ],[ ✔ built], 
[ File-like explorability       ],[ ❌ not primary (more structured DB-like) ],
[ Chunking + embedding          ],[ ✔                                       ],
[ Real memory (user/context)    ],[ ✔ strong                                ],
[ Skills + iteration            ],[ ✔ (Case → Skill)                        ],
[ Strong backend                ],[ ✔ (FastAPI + LangChain + MongoDB)       ]
)

*EverOS Strength*:

- Memory lifecycle design
- User modeling
- Temporal reasoning
- Agent learning (skills)

*EverOS Weakness*:

- Not path-native / file-explorable
- More system-driven than “LLM-exploration-friendly”
- Less emphasis on:

  - filesystem abstraction
  - discoverability via navigation

== Episodes

An Episode is a sequence of MemCells that happened within a time window or session:
- one conversation
- one task execution
- one interaction session

Example:
- "I am planning a trip to Japan"
- "I prefer quiet places"
- "I booked Kyoto"
These MemCells form one episode.

Key property:
- Ordered
- Temporal
- Weak semantics

It answers: “What happened together?”

Analogy: Like a log file or a Git commit session

== MemScene

A MemScene is a theme / topic cluster of related MemCells, independent of time.

Example: MemCells from different days:

- “User likes Kyoto”
- “User prefers quiet travel”
- “User avoids crowded cities”

All belong to: MemScene: Travel Preferences

Key property
- Semantic
- Cross-episode
- Many-to-many

It answers: “What is this about?”

Analogy: Like a tag / topic / embedding cluster

== Story

A Story is: a linked sequence of events with meaning and progression. This is higher-level than Episode.

Example - Across time:

- “User planned Japan trip”
- “User chose Kyoto”
- “User visited Kyoto”
- “User loved the quiet temples”

This forms a Story: “User’s Japan travel journey”

Key property
- Causal / logical
- Cross-episode
- Has progression

It answers: “What unfolded and why does it matter?”

Analogy: Like a timeline with meaning or a knowledge graph path

#table(
  columns: 4,
  align: left,
[Feature], [Episode], [MemScene], [Story],
[Basis], [Time], [Semantics], [Causality],
[Scope], [Single session], [Cross sessions], [Cross sessions],
[Structure], [Sequence], [Cluster], [Directed chain],
[Purpose], [Logging], [Organization], [Reasoning],
[Stability], [Fixed], [Evolves], [Evolves]
)

*How they work together (this is the real insight)*

Same MemCells:

MemCells:
```text
A: "User plans Japan trip"
B: "User prefers quiet places"
C: "User booked Kyoto"
D: "User loved temples"
```

Episode (time)
```text
Episode_1: A, B, C
Episode_2: D
```

MemScene (semantic)
```text
Travel Preferences: B, D
Japan Trip: A, C, D
```

Story (narrative)
```text
Story: A → C → D
```

SAME data, different structure.

*Why EverOS needs all three*

Because each solves a different failure mode:

If only Episode:
  - no cross-session memory
If only MemScene:
  - no time / evolution
If only Story:
  - too expensive + hard to build universally

A good memory system does NOT pick one — it layers all of them.

== Conclusion

We are not going to use EverOS. The main drawback of EverOS is the lack of file-system support.
It uses MongoDB.

Ideas learned from EverOS:
- Memory is not storage; it is a system (I 100% agree)
- MemCell
- Episodes: link fragments into stories, primary binding is time, record what happened in a session
- Story: primary binding is causality / narrative, explains why it matters over time
- MemScene: aggregated context/theme, primary binding is semantics, it explains 'what this is about'
- Same MemCell can belong to multiple 'memory component' simultanenously
- User Profiles
- Preferences
- Maintain multi-threaded context
- Evidence-based reasoning
- Continuously update user preferences, profiles and other derivitives
- Case - Skill abstraction, distill past into reusable 'skills'
- Agents learn patterns from history

*MemoryComp*
One important feature of a memory system is to put isolated memory pieces together, bind them based on a method, 
such as semantically, temporal, causality, narrative, or other 'logical means'. 'MemScene' is thinking in this
direction. More generally:
- Episodes
- Story
- Preference
- Profile
- ...

These are called *MemComp*.

= References
[1]: https://github.com/EverMind-AI/EverMemOS?utm_source=chatgpt.com "EverMind-AI/EverMemOS: A memory OS that makes your ..."

[2]: https://en.tmtpost.com/post/7767347?utm_source=chatgpt.com "TCCI-backed EverMind Unveils EverMemOS, a Brain- ..."

[3]: https://evermind.ai/?utm_source=chatgpt.com "EverMind | Infinite Memory & Long-Term Consistency for AI ..."

