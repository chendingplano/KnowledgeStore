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
    "Review - PanDoc"
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
  file_id: "2026052801",
  source: "https://github.com/jgm/pandoc",
  content_type: "review",
  document_date: "2026/05/29",
  keywords: [PanDoc, Document Type Conversion],
)

= Overview
[Pandoc GitHub Repository](https://github.com/jgm/pandoc?utm_source=chatgpt.com) is one of the most influential 
open-source document processing tools in the technical writing, academic publishing, and developer ecosystems. 
Created by John MacFarlane, Pandoc is a universal document converter written primarily in Haskell. Its core 
purpose is to transform documents between a very large number of markup, publishing, and office document 
formats. The project describes itself as a "universal markup converter" and is often referred to as the 
"Swiss Army knife" of document conversion. ([GitHub][1])

The key architectural idea behind Pandoc is that it parses input documents into a unified intermediate abstract 
syntax tree (AST) rather than performing direct format-to-format conversions. This allows any supported input 
format to be transformed into any supported output format through a common internal representation. Pandoc 
supports an exceptionally broad range of formats, including Markdown variants, HTML, LaTeX, Typst, DOCX, ODT, 
EPUB, Org-mode, reStructuredText, Jupyter Notebooks, MediaWiki, DocBook, and many others. On the output side, 
it can generate HTML, PDF, DOCX, EPUB, PowerPoint presentations, Typst, LaTeX, reveal.js slides, and numerous 
publishing-oriented formats. ([Wikipedia][2])

Pandoc is heavily used in academic and technical publishing workflows because it treats plain text as the primary 
authoring format. A common workflow is writing content in Markdown and then generating multiple deliverables such 
as PDF, Word documents, websites, e-books, and presentation slides from the same source. It includes sophisticated 
support for citations, bibliographies, cross-references, tables, footnotes, mathematics, metadata, and templates, 
making it suitable for research papers, books, standards documents, technical manuals, and 
documentation systems. ([Wikipedia][2])

One of Pandoc's strongest features is extensibility. Users can customize conversions through templates, filters, 
and Lua scripting. Organizations often build automated publishing pipelines around Pandoc, using it as the document 
transformation engine within CI/CD systems, documentation generators, knowledge management platforms, and 
static-site workflows. Because Pandoc exposes a structured document model, it can also serve as a normalization 
layer for downstream processing tasks such as semantic analysis, content extraction, document indexing, 
and AI-powered document workflows. ([GitHub][1])

For projects like SemOS system, Pandoc is particularly interesting because it acts as a format normalization layer. 
Instead of building separate parsers for DOCX, Markdown, HTML, LaTeX, Typst, EPUB, and other formats, documents 
can first be converted into Pandoc's internal representation or a normalized Markdown-like form. This makes downstream 
tasks such as topic extraction, provision extraction, knowledge graph generation, scene block generation, and semantic 
indexing significantly more uniform. In practice, many document-processing systems use Pandoc as the first stage of a 
larger ingestion pipeline before applying NLP, retrieval, knowledge extraction, or LLM-based reasoning. ([GitHub][1])

== Integration with SemOS
Pandoc is primarily a standalone command-line engine, not a GUI application.

Internally, Pandoc consists of:

1. Reader modules

   - DOCX reader
   - HTML reader
   - Markdown reader
   - LaTeX reader
   - EPUB reader
   - etc.

2. Internal AST

   - A structured document model
   - All formats are converted into this representation

3. Writer modules

   - DOCX writer
   - HTML writer
   - Markdown writer
   - PDF writer
   - Typst writer
   - etc.

The CLI (`pandoc`) is simply a thin wrapper around these components.

=== Integration Option 1: Call Pandoc CLI (Most Common)

Most systems integrate Pandoc by executing the binary:

```bash
pandoc input.docx -t markdown -o output.md
```

From Go:

```go
cmd := exec.Command(
    "pandoc",
    "input.docx",
    "-t", "markdown",
    "-o", "output.md",
)
err := cmd.Run()
```

Advantages:

- Very stable
- No Haskell dependency in your code
- Easy deployment
- Used by many production systems

For SemOS, this is probably the easiest solution.

Pipeline:

```text
DOCX
 ↓
Pandoc
 ↓
Markdown
 ↓
SemOS Extraction
   - Topics
   - Provisions
   - Metrics
   - Scene Blocks
   - Knowledge Objects
```

=== Integration Option 2: Use Pandoc JSON AST

This is particularly interesting for SemOS.

Pandoc can output its AST as JSON:

```bash
pandoc input.docx -t json
```

Example:

```json
{
  "pandoc-api-version": [1,23],
  "meta": {},
  "blocks": [
    {
      "t": "Para",
      "c": [
        {
          "t": "Str",
          "c": "Hello"
        }
      ]
    }
  ]
}
```

Then your Go code can:

```go
type PandocDoc struct {
    Blocks []Block `json:"blocks"`
}
```

This gives you a structured document representation instead of plain Markdown.

For SemOS, this is arguably more valuable than Markdown because:

```text
DOCX
 ↓
Pandoc AST
 ↓
Topic Extraction
 ↓
Provision Extraction
 ↓
Knowledge Extraction
```

without losing as much document structure.

=== Integration Option 3: Use Pandoc as a Haskell Library

Pandoc is also available as a Haskell library:

```haskell
import Text.Pandoc
```

However:

- SemOS is Go-based.
- Embedding Haskell into Go is painful.
- Few non-Haskell projects use Pandoc this way.

This is not recommend.

=== What Pandoc Does Not Provide

Pandoc is not a document parser. It does not try to:

- OCR PDFs
- Detect document layouts
- Understand tables semantically
- Extract figures
- Build knowledge graphs
- Generate embeddings

SemOS would use Pandoc primarily as a format normalization layer for DOCX, Markdown, HTML, Typst, 
LaTeX, EPUB, and similar formats.


[1] Pandoc GitHub Repository: https://github.com/jgm/pandoc?utm_source=chatgpt.com "jgm/pandoc: Universal markup converter"\
[2] Wikipedia: https://en.wikipedia.org/wiki/Pandoc?utm_source=chatgpt.com "Pandoc"

