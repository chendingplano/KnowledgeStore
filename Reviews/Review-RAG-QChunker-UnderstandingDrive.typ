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
    "Reading-202602"
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
  Source: "https://arxiv.org/pdf/2603.11650",
  ArtifactType: "Acadamic Paper",
  PublishDate: "2026/3/12",

)

= Overview

- "Questions Are the Answer" - from Hal Gregerson
- Multi-agent debate framework comprising four specialized components:
  - Question Outline Generator
  - Text Segmenter
  - Ing4egrity Reviewer
  - Knowledge Completer

=== Question Outline Generator

This agent acts like an expert, performing in-depth analysis and exploration of the
given doc. Its main goal is to generate questions that are used by LLMs to
drive the process of This process is not
a mere information extraction but rather an endeavor to establish a profound
understanding of the intrinsic connections between the macro structures and micro
structures of the document.

The questions are designed to probe into the motivation, core assumptions, 
methodology, key conclusions, and their underlying logical chains with the
document. The process of generating questions compels the model to transition from
a passive text processor to an active knowledge explorer, constructing an abstract
understanding of the document's knowledge system through self-inquiry and providing a crucial semantics.

