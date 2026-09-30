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
    "SemOS - Search Engine"
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
  logical_name: "semos-search-engine",
  file_id: "2026100101",
  source: "",
  content_type: "research",
  document_date: "2026/10/01",
  keywords: [search engine, hybrid search, bm25, vector search, similarity search],
)

= Overview
The typical architecture for search is hybrid search: BM25 + vector.
The major problem for this approach is: most vector stores require
loading the entire vector database into memory (such as FAISS).
This presents a serious scalability issues.

SemOS Search Engine (SSE) uses the following method:
```text
Search candidates
        |
Vector similarity compare (optional)
```

The key is picking candidates. BM25 is syntactical. It is a good 
algorithm to find
the relevant candidates. Its accuracy is, however, critically dependent
on the unification of keywords. Keywords may have aliases, acronyms,
jargons, in different languages, etc. Any single character difference
may fail a search.

In addition to syntactial method, we also need ways to find candidates
semantically. Vectors are the most popular data structure for 
searching candidates semantically. But it presents serious scalability
issues.

Vectors are not the only way of expressing semantics. There are
quite a few methods to associate semantics to content, including:

- Canonical Keyword 
- Categories
- Labels/tags

== Canonical Keywords

== Categories
(TBD).

== Labels
We may use LLMs to label chunks. The advantages of labels include:
- can be normalized
- can be hierarchical

== Hierarchical Explorability
Categories, labels, and canonical keywords can be organized in hierarchy.

If a node can have up to 99 + 1 children:
```text
Level       Size
--------------------------------------------
1           100
2           10,000
3           1,000,000           1 million
4           100,000,000         100 millions
5           10,000,000,000      10 billions
6           1,000,000,000,000   1 trillion
--------------------------------------------
```

