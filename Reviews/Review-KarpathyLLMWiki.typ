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
    "Review - Karpathy LLM Wiki"
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
  file_type: "typst",
  logical_name: "LLM Wiki",
  file_id: "2026060401",
  source: "https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f",
  content_type: "review",
  document_date: "2026/06/04",
  keywords: [LLM Wiki, Karpathy],
)

= Overview
Karpathy’s “LLM Wiki” is less a software project and more a proposal for a new knowledge-management paradigm. 
Instead of treating LLMs primarily as question-answering systems over a document collection (the traditional 
RAG approach), he suggests using them as knowledge compilers that continuously transform raw information into 
a structured, evolving wiki. Raw sources—papers, articles, repositories, datasets, images, notes, and 
conversations—are stored in a corpus, and an LLM incrementally reads, summarizes, organizes, links, and 
updates a collection of Markdown pages that become the user's knowledge base. ([Gist][1])

A central idea is that knowledge should be compiled ahead of time rather than reconstructed at query time. 
In a RAG system, the knowledge remains mostly in its original form and is searched whenever a question is 
asked. In the LLM Wiki model, new information is proactively integrated into the existing knowledge structure. 
The LLM creates or updates topic pages, adds cross-references, reconciles contradictions, and generates summaries. 
Over time, the wiki becomes a condensed representation of the corpus rather than merely an index 
into it. ([Houdao][2])

Karpathy also introduces the concept of an “idea file.” In the age of agentic coding tools such as Claude Code, 
Codex, and similar systems, he argues that sharing the underlying idea may be more valuable than sharing a specific 
implementation. Rather than distributing software tied to a particular environment, one can distribute a 
specification describing the architecture and workflow. Another person's agent can then adapt and implement the 
idea within their own tools, operating system, and workflow. ([Agentpedia Codes][3])

The architecture is intentionally simple. The knowledge base is primarily a collection of Markdown files (often 
managed in tools such as Obsidian), organized into a wiki of concepts, entities, and topics. An LLM agent performs 
operations such as ingestion, updating, linking, summarization, and consistency checking. Instead of relying on 
complex vector databases, ontologies, or enterprise knowledge graph infrastructure, the system leverages the LLM's 
reasoning abilities to maintain structure and relationships directly in human-readable documents. ([Agentpedia Codes][3])

From the perspective of SemOS project, the most significant insight is the shift from retrieval-oriented knowledge 
management to knowledge compilation. The goal is not merely to help the LLM find documents later, but to continuously 
transform raw content into increasingly structured and interconnected knowledge artifacts. This aligns closely with 
your interests in summaries, semantic projections, scene blocks, metrics, causal models, and explorable knowledge 
structures. In fact, SemOS can be viewed as a more ambitious extension of the LLM Wiki idea: Karpathy's wiki compiles 
knowledge into Markdown pages, while SemOS aims to compile knowledge into multiple layers of structured 
artifacts—summaries, semantic projections, knowledge objects, causal relations, graphs, metrics, and navigable filesystem 
representations. ([Gist][1])

The most important sentence in the entire article is arguably:

> *Knowledge should compound.*

Instead of repeatedly paying the cost of understanding the same corpus every time a question is asked, the system 
continuously invests computation to make the knowledge base itself smarter, denser, and easier for future LLMs 
to explore. ([Houdao][2])

For someone building SemOS, this article is noteworthy because it validates the core intuition you have been exploring 
for months: *prepare knowledge in a form that LLMs can navigate and reason over directly, rather than relying 
exclusively on retrieval from raw documents.*

== SemOS
In SemOS, we currently extract (or compiles):
- Summaries (whole documents, chunks)
- Semantic Projections
- Topics
- Scene Blocks
- Metrics
- Provisions
- Invectory Items
- Entities and Relations

What SemOS misses:
- Schemas (similar to CLAUDE.md for Claude Code, AGENTS.md for Codex)
- LLM Results

== Schemas
This is a document that tells the LLM how the wiki is structured, what the conventions are, and what workflows
to follow when ingesting sources, answering questions, or maintaining the wiki.

This is the key configuration file. It is what makes the LLM a disciplined wiki maintainer rather
than a generic chatbot.

In SemOS, Schemas are hierarchical. Each directory in ARTIFACT_WEB has a DOCMAP.md file.
ARTIFACT_WEB is equivalent to Karpatyh's `The Wiki`. Each directory is a compount artifact.
It contains:
- Brief discription about the compound artifact
- Keywords
- Creation Time
- Last Modification Time
- Last Lint Time
- Special Conventions: if it differs from its parent
- Special Workflows: if it differs from its parent
- Usage Statistics


== The Wiki
This is similar to ARTIFACT_DIR. Each directory in 'The Wiki' is a `Compound Artifact`,
or a directory of LLM-generated markdown files. Summaries, entity pages, concept pages, comparisons,
an overview, a synthesis. The LLM owns this layer entirely. It creates pages, updates them when new
sources arrive, maintains cross-references, and keeps everything consistent.

Each directory in 'The Wiki' is an 'Object'. Its content may come from multiple source files.
This is similar to ARTIFACT_WEB, which is a hierarchy of directories. Each directory contains
- Summaries
- Scenes
- Semantic Projections
- Topics
- Metrics
- Provisions
- Inventory Items
- Entities and Relations

Below are the planned:
- Change Log (TBD)
- Concept (TBD)
- Comparisons (TBD)
- Overview (should we do it?)
- Synthesis (TBD)
- Case Studies (TBD)
- Contradictions (TBD)
- Cross-reference (TBD)
- Discussions (TBD)
- Chat (TBD)

== Index.md
It is a catalog of everything in a compound artifact. It contains:
- List pages in the compound artifact, each page with:
  - One-line summary
  - Creation Time
  - Last Modification Time
  - Activity statistics
  - Inbound clicks
  - Outbound clicks
- Children

SemOS updates it on every ingest and modification of the inputs related to this compound 
artifact. 

When answering a query, the LLM reads the index first to find relevant pages,
then drills into them.

== Change Log
ChangeLog.md is chronological. It is an append-only record of what happened and when.

Operations:
- Ingest
- Query
- Lint
- Edit
- Remove
- Clear (or reset)

*Entry Format*
```text
## [2026-06-04 06-12-22] NGST
## [2026-06-04 06-12-22] QURY
## [2026-06-04 06-12-22] LINT
## [2026-06-04 06-12-22] EDIT
## [2026-06-04 06-12-22] REMV
## [2026-06-04 06-12-22] CLER
```

== Chat
Users ask questions, the system generates answers. This is called Chat.

Chats are stored in ARTIFACT_WEB.

== Synthesis

- Question-Answer Pairs
- Derived relations

== Lint
The system periodically lints ARTIFACT_WEB. Since there can be too many entities in
ARTIFACT_WEB, it may lint selectively, such as the ones being modified recently,
used heavily, the ones that have contradictions, etc.

- Contraditions
- Stale claims that newer sources have superseded
- Orphan pages with no inbound links
- Important concepts mentioned but lack their own page
- ...

== References
[1]: https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f?utm_source=chatgpt.com "LLM Wiki"\

[2]: https://www.houdao.com/d/7670-Andrej-Karpathy-OpenSources-LLM-Agent-Framework-for-Compounding-Knowledge-with-Obsidian?utm_source=chatgpt.com "Andrej Karpathy Open-Sources LLM Agent Framework for ..."\

[3]: https://antigravity.codes/blog/karpathy-llm-wiki-idea-file?utm_source=chatgpt.com "Karpathy's LLM Wiki: The Complete Guide to His Idea File"

