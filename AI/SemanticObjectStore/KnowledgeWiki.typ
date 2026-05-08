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
    "Knowledge Wiki"
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
  created: "2026/05/07",
  logical_name: "Knowledge Wiki",
  file_id: "2026050701",
  file_type: "Typst",
  keywords: ["Wiki", "Knowledge Wiki", "LLM Wiki"],
)

= Overview

== File Structure
A Knowledge Wiki assumes the following file structure:

```text
my-first-wiki/
├── wiki.config.md
├── raw/
├── documents/
│   └── index.md
│   └── document-0001
│       └── document-0001
├── more documents/
├── wiki/
│   └── index.md
│       └── L1-category
│           └── L2-category
│       └── L1-category
│       ...
├── derived/
├── prompts/
│   ├── compile-index.md
│   ├── compile-source-page.md
│   ├── compile-concept-page.md
│   ├── query-and-file.md
│   └── lint-wiki.md
├── logs/
│   └── maintenance-log.md
└── sources.md
```

=== Raw
All documents are stored in this directory.

```text
├── raw/
│   └── index.md
│   └── 2026
│       └── document-0001
```
