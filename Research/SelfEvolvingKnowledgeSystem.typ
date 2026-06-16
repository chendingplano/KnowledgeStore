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
    "Research - Self-Evolving Knowledge System"
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
  logical_name: "SelfEvolvingKnowledeSystem",
  file_id: "2026061601",
  content_type: "research",
  document_date: "2026/06/16",
  keywords: [Knowledge System, Self-Evolving],
)

= Overview

Without graphs, LLMs can search nodes, normally by keywords. 
BM25 can be a critical
tool. In debugging, for instance, if it fails loading a page, by looking at the 
url, it checks where the url is routed. Once related code is found, it reads the
code, checking for every failure case. 

For each failure case, it traces back, again by keyword search. Note that if 
graphs are available, it can use graphs. But what if the relations were not 
captured during building time? Search on graphs is unreliable, to say the least.
Graphs are at best a complement.

Even without graphs, LLMs can still reason by search. 
One important thing to note is that after LLMs generate answers, we should
ask the LLM to summarize its reasoning, such as:
- Search '/home3/knowledge' to find out how the url is routed
- Found the file: '...'
- Examine the failure case: ...
- Trace back for the reasons why it fails
- ...

The LLM then generate the following relations:
- `url-xxx` `is-routed` `file-name-1`
- `url-xxx` `handled-by` `function-name-1`
- `function-name-1` `fail-on` `failure-case-1`
- `function-name-1` `fail-on` `failure-case-2`
- `failure-case-1` `source-code` `function-name-2`
- `failure-case-1` `source-code` `function-name-2`
- `function-name-2` `fail-on` `failure-case-3`
- ...

This is important for two reasons:
- To explain the problem and how the problem is solved
- The more the system is used, its knowledge base is better

This is called Self-Evolving Knowledge System

