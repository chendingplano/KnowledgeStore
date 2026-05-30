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
    "Research - File Format Conversion"
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
  logical_name: "FileFormatConversion",
  file_id: "2026052803",
  content_type: "research",
  document_date: "2026/05/29",
  keywords: [PanDoc, Document Type Conversion, File Format Conversion],
)

= Overview
SemOS will use PanDoc ([1], [2], [3]) as its primary file format converter.

PanDoc uses templates to let users customize the conversion. SemOS will
let users create/edit templates through its GUI.

= References
[1] Pandoc Review, [[file_id:2026052801]]

[2] Pandoc Research, [[file_id:2026052802]]

[3] Pandoc Website, https://pandoc.org/
