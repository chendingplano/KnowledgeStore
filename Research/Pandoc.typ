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
    "Research - PanDoc"
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
  logical_name: "PanDoc",
  file_id: "2026052802",
  content_type: "research",
  document_date: "2026/05/29",
  keywords: [PanDoc, Document Type Conversion],
)

= Overview
PanDoc is a universal file format converter. It supports extensive 

== A Typst Template for Pandoc
Refer to [[local_ref:3, A New Typst Template for Pandoc]]

== Supported File Formats
(From [2])

=== Lightweight markup formats
- ↔︎ Markdown (including CommonMark and GitHub-flavored Markdown)
- ↔︎ reStructuredText
- ↔︎ AsciiDoc
- ↔︎ Emacs Org-Mode
- ↔︎ Emacs Muse
- ↔︎ Textile
- → Markua
- ← txt2tags
- ↔︎ djot
- → BBCode

=== HTML formats
- ↔︎ (X)HTML 4
- ↔︎ HTML5
- → Chunked HTML

=== Ebooks
- ↔︎ EPUB version 2 or 3
- ↔︎ FictionBook2

=== Documentation formats
- → GNU TexInfo
- ← pod
- ↔︎ Haddock markup
- → Vimdoc

=== Roff formats
- ↔︎ roff man
- → roff ms
- ← mdoc

=== TeX formats
- ↔︎ LaTeX
- → ConTeXt

=== XML formats
- ↔︎ DocBook version 4 or 5
- ↔︎ JATS
- ← BITS
- → TEI Simple
- → OpenDocument XML

=== Outline formats
- ↔︎ OPML

=== Bibliography formats
- ↔︎ BibTeX
- ↔︎ BibLaTeX
- ↔︎ CSL JSON
- ↔︎ CSL YAML
- ← RIS
- ← EndNote XML

=== Word processor formats
- ↔︎ Microsoft Word docx
- ↔︎ Rich Text Format RTF
- ↔︎ OpenOffice/LibreOffice ODT

=== Interactive notebook formats
- ↔︎ Jupyter notebook (ipynb)

=== Page layout formats
- → InDesign ICML
- ↔︎ Typst

=== Wiki markup formats
- ↔︎ MediaWiki markup
- ↔︎ DokuWiki markup
- ← TikiWiki markup
- ← TWiki markup
- ← Vimwiki markup
- → XWiki markup
- → ZimWiki markup
- ↔︎ Jira wiki markup
- ← Creole

=== Slide show formats
- → LaTeX Beamer
- ↔︎ Microsoft PowerPoint
- → Slidy
- → reveal.js
- → Slideous
- → S5
- → DZSlides

=== Data formats
- ← CSV tables
- ← TSV tables
- ← Microsoft Excel spreadsheets

=== Terminal output
- → ANSI-formatted text

=== Serialization formats
- ↔︎ Haskell AST
- ↔︎ JSON representation of AST
- ↔︎ XML representation of AST

=== Custom formats
- ↔︎ custom readers and writers can be written in Lua

=== PDF
- → via pdflatex, lualatex, xelatex, latexmk, tectonic, wkhtmltopdf, weasyprint, prince, pagedjs-cli, context, or pdfroff.

= References
[1] Pandoc Review, [[file_id:2026052801]]

[2] Pandoc Website, https://pandoc.org/

[3] A New Typst Template for Pandoc, https://imaginarytext.ca/posts/2025/typst-templates-for-pandoc/

