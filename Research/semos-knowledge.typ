#import "@preview/diagraph:0.3.6"
#import "@preview/oxdraw:0.1.0": *
#import "../Reviews/Review-ai-laya.typ": ref_review_laya
#import "../Reviews/review-knowhere.typ": ref_review_knowhere

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
    "Knowledge"
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
  logical_name: "semos-knowledge",
  file_id: "semos-knowledge",
  source: "",
  content_type: "SemOs",
  document_date: "2026/10/14",
  keywords: [Knowledge, what is knowledge],
)

= Introduction
This chapter focuses on:
- What exact is knowledge
- Knowledge and semantics
- Knowledge mining
- Knowledge and applications

== Knowledge

*Knowledge and Facts*

Facts are not knowledge. 

== Knowledge and Semantics

The most important question about semantics is how to represent semantics.
There is no silver-bullet method of representing semantics. 

Below are the methods of representing semantics:
- Vector
- Keyword
- Tag
- Topic
- Category
- Graph
- Rules

*Vector View*

LLMs use vectors to represent semantics. Content with similar semantics share 
similar vectors. The semantic similarity can be calculated by their vectors
cosine or dot-product. The importance and limitations are obvious.

*Keyword View*
Keywords can relate content with similar semantics. 

*Tags*

*Topics*

*Categories*

*Graphs*

== Knowledge Mining

Knowledge mining requires deep understanding of knowledge.
One form of knowledge is to set a goal and collect all the information
that may affect the goal.

In [review-rag-MatSeek], it extracts 

