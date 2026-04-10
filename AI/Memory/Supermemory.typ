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
  [2026/04/10], [Created, file name: Supermemory.typ],
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
    "Supermemory"
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


= Overview

Supermemory is a unified memory + knowledge bas system. It is designed to store:
- Memory-like data:
  - conversations
  - user preferences
  - session history
- Knowledge Base:
  - Documents
  - Notes
  - External Content (Notion, Drive, etc.)
  - Arbitrary text/artifacts

Supermemory does not distinguish strongly between memory and knowledge - everything becomes retrievable context.
For large content, such as documents, it does do chunking.

A simplified pipeline of Supermemory:
- Ingest content
- Chunk it
- Generate embeddings
- Store + link to memory graph
- Retriever Layer

== Search

Its search system is a hybrid layered retrieval system:
- Vector search (primary): semantic similarity, embedding-based retrieval
- Keyword / lexical signals: exact match, text overlap
- Graph / Relationship search: links between memories, contextual associations
- Memory-aware ranking: recency, frequency, importance, personalization

== Issues

The main issue is about explorability. It is basically semantic + keyword search, plus memory-awareness.


