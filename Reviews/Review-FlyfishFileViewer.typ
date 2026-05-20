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
    "Review - Flyfish File Viewer"
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
  Source: "https://github.com/flyfish-dev/file-viewer",
  ArtifactType: "Open-Source Project",
  DocumentDate: "2026/05/23",
  Keywords: [File Viewer],
)

= Overview
[flyfish-dev/file-viewer GitHub repository](https://github.com/flyfish-dev/file-viewer?utm_source=chatgpt.com) is an open-source browser-based file preview framework focused on *client-side rendering of many document formats*. Rather than being a narrow PDF viewer, it aims to be a general-purpose “attachment preview” layer for business systems such as OA platforms, knowledge bases, ticketing systems, and document portals. The project supports a notably broad set of formats including Word, Excel, PowerPoint, PDF, OFD (important in Chinese enterprise/government contexts), CAD drawings, Excalidraw, draw.io diagrams, EPUB, Markdown, source code, images, audio, and video. A key architectural choice is to keep rendering in the browser whenever possible, reducing reliance on backend document conversion pipelines. ([Flyfish Viewer][1])

Architecturally, this is more of a *frontend document rendering platform* than a simple UI widget. The maintainers provide multiple integration modes: Vue 3, Vue 2.7, and iframe embedding. The iframe mode is particularly practical because it decouples the viewer from application frameworks, making it usable across heterogeneous systems. Heavy parsers are loaded asynchronously based on file type, which is an important engineering decision—formats like Office documents, CAD, or PDF can significantly bloat bundles if eagerly loaded. This makes the project suitable for enterprise web applications where users preview many attachment types but performance still matters. ([Flyfish Viewer][1])

From a product perspective, the most compelling value is eliminating the classic “convert everything to PDF on the server” architecture. Traditional document preview systems often require LibreOffice, custom conversion workers, temporary storage, queues, and cleanup logic. Flyfish File Viewer pushes much of that complexity to the browser, simplifying infrastructure and lowering operational cost. That said, this also creates tradeoffs: browser memory usage can become significant for large files, parsing fidelity depends on the JavaScript rendering libraries underneath, and extremely complex Office layouts may still render imperfectly compared with native desktop applications.

For SemOS, this project is relevant since we need a universal document preview layer inside a web UI. For example, if users navigate standards, regulations, design docs, CAD attachments, or markdown artifacts from the knowledge base, this could provide immediate in-browser inspection without building separate preview infrastructure. 

This is a fully functional open-source, not an interface to a cloud service. We can install 
it locally. The main concern to SemOS is that it is implemented in Vue. How to integrate
it is an issue.

== Limitations
It supports only Vue and React.

== References
[1]: https://doc.flyfish.dev/?utm_source=chatgpt.com "Flyfish Viewer"

