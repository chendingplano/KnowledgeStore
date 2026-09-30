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
    "Review - Knowwhere"
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
  logical_name: "review-knowhere",
  file_id: "2026092601",
  source: "",
  content_type: "review",
  document_date: "2026/09/26",
  keywords: [knowhere, Knowledge Base, Document Parsing, Document Retrieval, 
    hybrid retrieve],
)

#let ref_review_knowhere() = [
  "File: review-knowhere"
]

= Overview
[Knowhere](https://github.com/Ontos-AI/knowhere)  is an open-source document parsing 
and retrieval system developed by Ontos AI. Its central idea is to turn unstructured 
documents into persistent, navigable memory for AI agents, rather than simply 
converting documents into text chunks for conventional RAG. It reconstructs 
document hierarchies, generates summaries, extracts entities, builds cross-document 
relationships, and preserves links to original pages and assets. Agents can then 
explore this structured knowledge base, navigate between sections, and retrieve 
evidence with precise citations. The project is licensed under Apache 2.0 and 
supports self-hosted deployment.

Knowhere 2.0 introduces dual-track document parsing. Its Text Track extracts text 
and preserves native document structure, while its Vision Track uses 
vision-language models (VLMs) to understand complex PDF pages and PowerPoint 
slides directly. This avoids depending entirely on OCR and layout reconstruction, 
which can introduce errors when processing complicated tables, diagrams, or 
technical drawings. Both tracks produce a unified representation containing 
hierarchical document nodes, summaries, metadata, source references, and linked 
assets. The resulting document memory can therefore support consistent retrieval 
regardless of the original file format.

The other major innovation is agent-native retrieval. Instead of forcing every 
query through a fixed retrieval pipeline, Knowhere exposes tools for document 
outlines, structural filtering, exact search, fuzzy recall, full-text reading, 
and graph traversal. An LLM agent decides which tools to invoke, which document 
sections to investigate, and whether additional exploration is necessary. Its 
cross-document graph connects related documents through extracted entities and 
keywords. Knowhere also supports conventional top-K retrieval and provides MCP 
integration, allowing external agents to explore its knowledge base. Its September 
8, 2026 update emphasizes this agent-controlled approach.

Architecturally, Knowhere provides a Python-based API and background workers, 
with PostgreSQL, Redis, and S3-compatible storage among its infrastructure 
dependencies. Separate repositories provide a web dashboard, Docker Compose 
deployment, and Python and Node.js SDKs. For SemOS project, its most relevant 
feature is the combination of hierarchical document navigation, graph-based 
relationships, and agent-directed investigative search. This closely resembles 
your approach of combining conventional retrieval with filesystem-like exploration. 
Knowhere's unified memory schema and source-grounded references are particularly 
relevant design ideas. The developers also report improvements in retrieval 
accuracy and efficiency, although the published benchmark figures come from 
their internal evaluations rather than independent testing.

== Tools
Knowhere exposes a fairly small, concrete toolset to agents through its 
*MCP server*. The current documentation lists nine tools. ([Knowhere][1])

```text
| Tool                            | Purpose                                                          |
| ------------------------------- | ---------------------------------------------------------------- |
| `knowhere_list_documents`       | List documents in the corpus/namespace                           |
| `knowhere_get_document_outline` | Get the hierarchical outline/tree of a document                  |
| `knowhere_read_chunks`          | Read exact chunks by page, section path, chunk ID/type, or range |
| `knowhere_grep_chunks`          | Literal or regex search *within one document*                    |
| `knowhere_search`               | Broad retrieval/search across published documents                |
| `knowhere_async_parse_url`      | Ingest/parse a document from a URL                               |
| `knowhere_async_parse_file`     | Ingest/parse a local file                                        |
| `knowhere_async_get_job_status` | Check asynchronous parsing status/results                        |
| `knowhere_delete_document`      | Soft-delete/archive a document                                   |
```

The first five are the particularly interesting ones for *agentic exploration*. 
They effectively give the agent several different information-access primitives 
rather than one generic `search()` function. `knowhere_search` is corpus-level 
discovery; `knowhere_grep_chunks` provides deterministic exact/regex search 
inside a selected document; `knowhere_get_document_outline` lets the agent 
inspect document structure; and `knowhere_read_chunks` lets it retrieve the 
actual evidence after deciding where to look. ([Knowhere][1])

For example, an agent investigating *"What are the calibration requirements for 
temperature data loggers?"* could conceptually do:

```text
knowhere_search("temperature data logger calibration")
        ↓
candidate documents
        ↓
knowhere_get_document_outline(documentId)
        ↓
identify "Calibration / Verification" section
        ↓
knowhere_grep_chunks(documentId, "calibrat|verification")
        ↓
knowhere_read_chunks(documentId, section/path/pages)
        ↓
actual evidence
```

This distinction is important. *The LLM is not required to accept whatever 
a top-K RAG query returns.* It can first discover candidates, inspect their 
structure, search within them, and then selectively read evidence. Knowhere 
describes the underlying corpus as containing hierarchical sections/chunks 
plus document-level graph relationships; its retrieval implementation also 
maintains separate content, path, and term/grep search representations. ([GitHub][2])

This is quite close to the *"candidate retrieval → investigative exploration"* 
architecture we discussed for SemOS. In fact, the interesting part of Knowhere 
is arguably not its RAG algorithm but this tool boundary:

*Corpus search → document selection → structural navigation → local search → selective reading.*

One difference from a filesystem-style SemOS interface is that Knowhere exposes these 
as *semantic/document operations* (`outline`, `grep_chunks`, `read_chunks`, `search`) 
rather than generic filesystem operations such as `ls`, `cat`, `grep`, and following 
`[[links]]`. Conceptually, though, they are solving much the same problem: give the 
agent enough cheap, progressively more detailed operations that it can *investigate 
knowledge rather than having retrieval make the entire decision for it*. ([Knowhere][1])

[Knowhere MCP documentation](https://docs.knowhereto.ai/mcp?utm_source=chatgpt.com)
[Knowhere GitHub repository](https://github.com/Ontos-AI/knowhere?utm_source=chatgpt.com)

[1]: https://docs.knowhereto.ai/mcp?utm_source=chatgpt.com "Model Context Protocol (MCP) | Knowhere"
[2]: https://github.com/Ontos-AI/knowhere/blob/main/AGENTS.md?utm_source=chatgpt.com "knowhere/AGENTS.md at main · Ontos-AI/knowhere · GitHub"

Sources: 
[Knowhere repository and README](https://github.com/Ontos-AI/knowhere), 

[Architecture context](https://github.com/Ontos-AI/knowhere/blob/main/CONTEXT.md), 

[Retrieval documentation](https://github.com/Ontos-AI/knowhere/blob/main/docs/retrieval-document-scope.md) .

