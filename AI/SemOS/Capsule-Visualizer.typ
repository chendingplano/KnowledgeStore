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

#let frontmatter = (
  created: "2026/05/09",
  logical_name: "Capsule Visualizer",
  file_id: "2026050901",
  file_type: "Typst",
  keywords: ["Capsule", "Visualizer", "Capsule Visualizer", "Capsule Wiki"],
)

== Capsule Visualizer

Capsule Visualizer turns a capsule into a web page. The visualizer is data-driven, wiki-style.
