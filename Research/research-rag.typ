#import "@preview/diagraph:0.3.6"
#import "@preview/oxdraw:0.1.0": *

#set heading(numbering: "1.")
#set quote(block: true)
#show link: set text(fill: blue)
#show bibliography: set text(fill: blue)
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
    "Research - RAG"
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

#show heading.where(level: 4): set text(size: 14pt)
#show heading.where(level: 4): it => pad(top: 4pt, it)

#bibliography("../references/references.bib")

= RAG

== Chunking

=== Reference outside chunks

Example:
```text
超过上述阈值后，该模块会切换到备用流程。
```

If "the above threhold" or "the fallback workflow" is not in the
current chunk, this can be a problem.

A straightforward solution is to let LLM check whether a 
chunk references content somewhere else. If yes, bring it
back.

This solution works, but it costs.

A simple solution is to delay the completion process until
when such a chunk is used. LLM recognizes the missing information
and retrieves the surrounding context incrementally. After finding
all the missing information, it updates the chunk, with either
the additional information or references to them so that when
the chunk is used the next time, it contains all the information.

QChunker (@ref-QChunker, #link("file:///Users/cding/Workspace/KnowledgeStore/Reviews/review-QChunker.md")[QChunker])
main ideas are:
- Use LLM to generate questions from the document
- Segment the document based on the questions, make sure a chunk contains
  all the information for the questions it can answer
- Generate multiple chunks
- Use an algorithm to score the chunks
- Use the score to choose the 'best' chunks
- Use LLM to check completeness of chunks. If a chunk misses information,
  complete it by retrieving the relevant content and re-write the chunk

The main limitations are the costs and time. We may use its ideas (some of them).



