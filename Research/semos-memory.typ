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
    "SemOS - Memory"
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
  created: "2026/05/18",
  logical_name: "semos-design",
  file_id: "2026051802",
  file_type: "Typst",
  content_type: "Research",
  doc_time: "2026/05/18",
  keywords: ["Coding Assistant", "Harness", "SemOS"],
)

= Memory

```text
Architecture from @ref-enterprise-memory:
#figure(
  image("../Images/image_2026100902.png"),
  caption:[Memory architecture]
)
```

== Memory Identification
Long-running agent workflows often use a thead identifier.
That identifier must not become the only access control.
A hybrid search is important to memory, but uniquely identify
memory capsules is equally important.

Thread ids (not the computing thread ids) should be stored
in memory, including its paths:
```text
  /principal/{principal_id}/thread/{thread_id}
```

== The Core memory

This is for the real memory subsystem. It should hold:

- who the user is in practical terms
- stable preferences
- communication preferences
- ongoing projects
- durable constraints
- long-lived goals
- important relationships
- recurring tools/workflows

Keep it small. Think *0.5–3 KB per user/project*, not a dump.

```text
Letta’s @memory-blocks-core-memory are a useful reference point here: always-visible, persistent, small, and structured.
```

Example:

```yaml
user_profile:
  preferred_language: English
  role: software engineer
  recurring_interests:
    - agent systems
    - knowledge systems
    - path-native exploration
  response_preferences:
    - prefers conceptual precision
    - likes system-level comparisons
    - values practical architecture advice
current_projects:
  - SemOS
durable_facts:
  - user sees memory and RAG as converging systems
```

Core memory should be:

- human-auditable
- editable
- compact
- high precision
- low churn

Do not let the system stuff noisy retrieved facts into core memory automatically.

== Episodic Memory

This is what happened. It stores:

- session summaries
- important discussion milestones
- decisions
- task attempts
- task outcomes
- mistakes corrected
- user feedback

Its structure:
```text
messages = [
  system_message,
  recent_user_message,
  relevant_tool_result
]
```

Example:

```text
2026-04-10: user asked to design a unified memory layer emphasizing filesystem exploration, chunking, embeddings, and real user memory.
```

This is not always in context, but searchable and summarizable.

== Semantic Memory

This is extracted knowledge and stable facts. It stores:

- user preferences inferred from conversation
- project facts
- domain concepts learned
- definitions
- relationships

Example:

```text
Fact: In the user’s architecture, a virtual filesystem is preferred as the LLM-facing exploration interface.
Confidence: high
Scope: project/SemOS
```

This is where memory starts to overlap strongly with KB/RAG.

== Artifact Memory

This is the “real KB” side:

- documents
- markdown files
- slides
- PDFs
- code
- notes
- tables
- records

Artifacts should preserve:

- original form
- chunks
- metadata
- logical path
- extracted entities/facts
- summaries

It stores not just memory but content or artifacts. In practice, modern memory systems already blur this line: Letta’s archival memory is explicitly for facts, knowledge, and external information at scale, not only personal memory. ([Letta Docs][3])

== Procedural Memory

Often forgotten, but very important. It store:

- how the user likes tasks done
- reusable workflows
- templates
- skill descriptions
- tool usage patterns

Example:

```text
When explaining infrastructure systems, prefer layered architecture and contrasts with adjacent concepts.
```

This is closer to “skills” than “knowledge,” but it belongs in a unified memory layer.

== Memory Processing Pipeline Layer

This is where the system becomes more than storage.

*Ingestion pipeline*

For each incoming artifact or conversation event:

1. persist raw source
2. extract structure
3. chunk
4. embed
5. keyword-index
6. entity extraction
7. fact extraction
8. relation linking
9. summary generation
10. memory classification
11. salience scoring
12. write to stores

This pipeline for both docs/files and user conversations, same system, different policies.

= Design Principles

== Zero-Mem
`Zero-Mem: Zero-Token Memory Operations for LLM Agents` addresses one of the 
major inefficiencies of today's LLM agents: almost every memory system repeatedly 
invokes an LLM to summarize conversations, extract facts, create memory records, 
or decide which memories to retrieve. Although these intermediate reasoning steps 
improve long-term memory, they incur substantial token costs, latency, and the 
risk of losing information through summarization. The paper asks a fundamental 
question: do memory operations require an LLM at all? The authors argue that they 
do not. Instead, they propose *Zero-Mem*, a framework in which every memory 
operation—except the final question answering step—is completely deterministic 
and consumes *zero LLM input/output tokens*. ([arXiv][1])

Rather than generating summaries or structured memories, Zero-Mem preserves the 
original interaction history as the authoritative record. It indexes these 
interactions using two complementary structures. The first is an *entity-context 
graph*, which connects entities, concepts, and their relationships across 
conversations, making it easy to retrieve semantically related information 
regardless of when it occurred. The second is a *temporal hierarchy*, 
which organizes conversations according to their chronological structure, preserving 
local conversational context, session state, and nearby interactions. When a user 
issues a query, the system dynamically balances these two views: graph traversal 
discovers semantically connected evidence, while temporal traversal reconstructs 
the surrounding conversational context. A deterministic calibration stage removes
conflicting evidence before the retrieved context is passed to a single LLM that 
generates the final answer. ([arXiv][1])

The most interesting contribution is philosophical as much as technical. Most 
existing agent memory systems—including frameworks such as Mem0, LightMem, LongMem, 
and many production agents—treat memory as another generative task: they ask an 
LLM to decide what to remember and later ask another LLM to decide what to 
retrieve. Zero-Mem instead treats memory as an *information retrieval and data
organization problem*, not a generation problem. The memory subsystem behaves much 
more like a search engine or database index than another language model. This 
avoids information loss caused by summarization, preserves complete provenance 
because all retrieved evidence comes directly from the original interaction traces, 
and makes the behavior substantially more deterministic and reproducible. ([arXiv][1])

Experimentally, Zero-Mem achieves competitive accuracy on long-memory and 
long-context question-answering benchmarks while eliminating all intermediate LLM 
calls. Using the same final answering model and identical context budget as 
competing methods, it reduces *memory-operation latency by 57.6%* relative to the 
fastest baseline because indexing, retrieval, graph traversal, and conflict resolution 
are entirely deterministic algorithms. Ablation studies show that both the entity 
graph and the temporal hierarchy contribute significantly, and that dynamically 
combining the two retrieval views performs better than relying on either one alone. 
The overall conclusion is that effective long-term agent memory does not 
require repeatedly asking an LLM to generate memory representations; carefully 
designed indexing structures and retrieval algorithms can perform the memory 
management, reserving the LLM solely for the final reasoning task. ([arXiv][1])

From the perspective of *SemOS* work, this paper is particularly interesting because 
its design philosophy closely matches the direction SemOS has been exploring. Instead 
of treating memory as generated summaries, Zero-Mem treats memory as *structured access 
to original artifacts*, using graph structures, hierarchical organization, 
deterministic retrieval, and evidence preservation. This is conceptually similar to 
the Virtual FS + BM25 + graph traversal + semantic retrieval architecture: the 
intelligence lies primarily in *how knowledge is organized and explored*, while the LLM 
is used only for synthesizing the final answer. The paper therefore provides empirical 
evidence supporting the idea that improving retrieval and knowledge organization may 
yield larger gains than adding additional LLM-based memory generation stages. ([arXiv][1])

== MuscleMemory
Link: https://github.com/TheWariend/MuscleMemory


