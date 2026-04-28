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
    "Review - RAG-Anything"
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
  Source: "https://github.com/HKUDS/RAG-Anything",
  FileID: "file-2026042802",
  FileName: "Review-RAG-Anything.typ",
  ArtifactType: "GitHub Open-Source",
  DocTime: "2026/04/28"
)

= Overview

RAG-Anything is an open-source framework developed by HKU’s Data Intelligence Lab that extends traditional
Retrieval-Augmented Generation (RAG) into a fully multimodal system. The core problem it addresses is that
most RAG pipelines are text-centric, while real-world documents (e.g., PDFs, reports, research papers) contain
mixed content such as images, tables, charts, and equations. This mismatch leads to incomplete retrieval and
poor reasoning. RAG-Anything aims to solve this by enabling unified understanding and querying across all content
types within a single system. ([GitHub][1])

High-quality, well-structured data is more important than the model itself in many cases. The system typically
incorporates a knowledge layer (e.g., document stores, retrieval systems, or domain-specific datasets) to
ground the model’s responses. This allows the AI to retrieve relevant context instead of relying purely on
parametric memory, improving accuracy, consistency, and domain alignment.

The key innovation is treating all document elements—text, visuals, structured data, and formulas—as interconnected
knowledge entities rather than separate modalities. Instead of building multiple pipelines (e.g., OCR for images,
parsers for tables), RAG-Anything integrates everything into one cohesive framework. This allows users to query complex
documents holistically, where answers may depend on relationships across modalities (e.g., a paragraph explaining a
chart or a formula tied to a table). ([Medium][2])

*From Model-Centric to System-Centric Design*
A key idea in the article is shifting from a model-centric mindset to a system-centric one. Instead of relying solely
on the raw capabilities of an LLM, the project builds a structured system around it. This includes task decomposition,
tool/API integration, workflow orchestration, and iterative execution. The LLM acts as the “brain,” but the surrounding
system provides the “body” and “process,” enabling it to handle multi-step, real-world tasks more effectively.

