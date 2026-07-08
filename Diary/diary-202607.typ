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
    "Diary - 2026/07"
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
  created: "2026/07/01",
  logical_name: "Diary-202607",
  file_id: "2026070101",
  file_type: "Typst",
  keywords: ["Diary"],
)

= 2026/07/02 - chartdb

#let a_001 = link(
  "https://github.com/chartdb/chartdb"
)[#text(fill: blue)[ChartDB]]

#a_001 \
Source: WeChat

This is an open-source pure TypeScript project that draws ER charts for databases.
We may integrate this open source to SemOS.

= 2026/07/02 - Skill Management
#let a_002 = link(
  "https://mp.weixin.qq.com/s/J_qkNulpWYDkKDaReM9QzQ?poc_token=HJRFRmqjrBMZIuuIcRdJpeljVKu5NGFaYlz-m_La"
)[#text(fill: blue)[Skill Management]]

#a_002 \
Source: WeChat

Main features:
- Skill repository
- Search
- Management
- Security
- Status Management
- Installation to Coding Agents
- Statistics on using/not using a specific skill
- Skill usage statistics
- Skill Room: each skill room is dedicated to a specific skill, showing how to use the skill, the effectiveness, etc.

#figure(
   image("Images/image_2026070201.png", width: 100%),
   caption: [Skill Platform (#a_002)],
)

= 2026/07/06 - Traefik
#let a_003 = link(
  "https://traefik.io/traefik"
)[#text(fill: blue)[Traefik]]

#a_003 \
Source: Jimmy

This is a replacement for Nginx.

= 2026/07/07 - Use Cheap Model to Filter RAG 
#let a_004 = link(
  "https://www.kapa.ai/blog/how-we-prune-rag-context"
)[#text(fill: blue)[How We Taught a Small LLM to Throw away 68% of RAG Context]]

#a_004 \
Source: Hacker News

There are two types of rerankers: (1) the reranker that fuses entries from two or more ordered lists
and (2) reranker that orders retrieved by LLMs. The former is pure reranker, while the latter
is more about relevance.

*Example*

We have always struggled over whether to use vector search. Here is an example:
- Question: Can I turn off audit log forwarding for just one project?"
- RAG 1: Audit log forwarding is toggled in org settings
- RAG 2: Projects cannot override org settings

Most rerankers may throw away RAG 2. If vector search is not used, it
won't be able to find it at all since it mentions none of the keywords.

The real question is: how to find RAG 2.

For agentic RAG, which I mean LLMs are the driver:
- Tool use: Find chunks related to 'Audit log'
- LLM analyze the chunks, trying to find out who controls the audit log.
  If there are too many results by 'audit log', the LLM may add more
  conditions: 'audit log', 'config/setting'.
- If the retrieved contains RAG 2, the LLM analyzes it and should be
  able to answer the question correctly.

I believe the true question is:
- Who should be in the driver seat: LLM or agent (or the apps we wrote)
- The budget: if it is a quick-and-dirty question/answering system, users
  care more about the latency than answer quality, a 1-3 turns may be
  the max. If it is a problem solving system, or a system whose missions
  are to solve user problems, regardless of the latency and the cost,
  the harness will be more resiliant to retrieval quality. LLMs can explore
  the knowledge base, possibly through multiple turns.
