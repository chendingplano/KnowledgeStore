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
    "Graphify"
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
  created: "2026/04/11",
  logical_name: "Graphify",
  file_type: "Typst",
  keywords: ["Semantic Object", "SemOS", "Knowledge Base"]
)

= Graphify

Source: ChatGPT\
Date: 2026/04/11

`graphify` is an open-source *knowledge-graph builder for code and mixed documents*, packaged both as a Python
CLI/library and as a *skill for AI coding assistants* like Claude Code, Codex, Cursor, Gemini CLI, OpenClaw, Aider,
Copilot CLI, and others. Its core idea is: instead of making the assistant repeatedly grep raw files, build a persistent graph of entities and relationships first, then query that graph for architectural understanding. ([GitHub][1])

What it is trying to solve is a real problem in agentic coding workflows: raw repositories, docs, screenshots, papers, and notes are often too large and too weakly structured for an LLM to navigate efficiently. `graphify` takes a folder and produces a `graphify-out/` directory with an interactive HTML graph, a `GRAPH_REPORT.md`, a persistent `graph.json`, and a content cache so later runs only reprocess changed files. The repo explicitly positions this as a way to understand a codebase faster and preserve structure across sessions. ([GitHub][1])

At a high level, it works in *three passes*. 
- First, it does a deterministic *AST-based extraction* over code to pull out classes, functions, imports, call relationships, docstrings, and rationale comments without needing an LLM. 
- Second, it can transcribe audio/video locally with `faster-whisper`. 
- Third, it runs assistant subagents over documents, images, papers, and transcripts to extract concepts, relationships, and design rationale; then it merges all of that into a NetworkX graph and clusters it with Leiden-style community detection before exporting reports and visualizations. ([GitHub][1])

The architecture doc shows this is not just a vague “AI graph” claim. The pipeline is explicitly decomposed into modules like `detect()`, `extract()`, `build_graph()`, `cluster()`, `analyze()`, `report()`, and `export()`. Each stage passes plain Python dicts or NetworkX graphs, and the extraction schema is simple and inspectable: nodes have IDs, labels, source files, and source locations; edges have source, target, relation type, and confidence category. ([GitHub][2])

One of the most interesting design choices is its treatment of *certainty*. Relationships are labeled `EXTRACTED`, `INFERRED`, or `AMBIGUOUS`, and inferred edges carry confidence scores. That is a strong design decision because many “GraphRAG” style tools blur together direct evidence and model guesswork. Here, the repo is explicitly trying to distinguish “found in the source” from “reasonable deduction” and “needs human review.” ([GitHub][1])

Another notable design choice is that `graphify` says it does *not rely on embeddings or a vector database for clustering*. Instead, it uses graph structure itself as the similarity signal: semantic similarity edges extracted by the model are added into the graph, and community detection is then run over that topology. In other words, it is closer to a *graph-first retrieval/exploration system* than a classic embed-chunk-search RAG stack. ([GitHub][1])

For practical use, the repo encourages a workflow like this: run `/graphify .`, inspect `GRAPH_REPORT.md` for the high-level picture, and then use `graphify query` or path/explain commands to extract a *small, focused subgraph* for the question at hand instead of dumping the full corpus into context. The README is very explicit that `graph.json` is not meant to be pasted wholesale into a prompt. ([GitHub][1])

It also goes beyond “run once and inspect output.” For several assistants, it installs an *always-on mechanism* so the assistant consults the graph before searching raw files. In Claude Code, for example, it adds instructions to read `GRAPH_REPORT.md` and installs a hook that triggers before glob/grep-style operations. Cursor uses always-applied rules; some other tools use `AGENTS.md` as the persistent control surface. That makes `graphify` more than a converter: it is trying to become part of the assistant’s navigation strategy. ([GitHub][1])

The implementation footprint is fairly approachable. The package is Python 3.10+, built around `networkx` plus a wide set of `tree-sitter` grammars for many languages. Optional extras add PDF parsing, office docs, watch mode, video transcription, Neo4j export, and MCP support. That suggests the project is meant to stay hackable and modular rather than becoming a giant monolith. ([GitHub][3])

My read on its strengths:

- It is *graph-native*, not just “vector search with graph marketing.” The graph is the main artifact. ([GitHub][1])
- It is *multimodal* in a practical way: code, docs, images, screenshots, PDFs, audio/video, even YouTube ingestion are part of the stated workflow. ([GitHub][1])
- It explicitly models *design rationale*, not just syntax and symbol references. That is unusually valuable for architecture understanding. ([GitHub][1])
- It keeps the result *persistent and queryable*, which aligns well with your recurring interest in memory layers and path-native exploration. ([GitHub][1])

Its likely limitations are also pretty clear from the repo design. The semantic layer still depends on assistant-driven extraction, so quality will vary with the underlying model and prompts. It is also strongest for *exploration and architectural understanding*, not as a replacement for exact program analysis, type checking, or deterministic dependency analysis. And because it builds a knowledge graph artifact, it introduces another derived layer that can become stale unless you rerun or use watch/update mode. Those are partly my inferences, but they follow directly from the architecture and CLI design. ([GitHub][1])

So the simplest way to think about `graphify` is:

*It is a graph-first, assistant-integrated, multimodal codebase understanding tool.*
Not a database, not a vector store, not a plain doc index.
Its real product is a *persistent structural memory of a repository/corpus* that an LLM can query more intelligently than raw grep. ([GitHub][1])

A few current project facts: the repository is MIT licensed, publicly visible, has over 20k GitHub stars, and the PyPI package name is `graphifyy` while the CLI command remains `graphify`. The GitHub page also shows a latest release `0.4.1` dated April 10, 2026. ([GitHub][1])

For Semantic Object Store project, `graphify` is worth looking at as an example of:

- *unifying code understanding + docs + media into one graph*
- *using graph structure instead of embeddings as the primary exploration surface*
- *feeding an assistant through a persistent intermediate artifact rather than raw corpus rereads* ([GitHub][1])

I can also compare `graphify` with your MKBP / unified memory ideas, or contrast it with GraphRAG, Obsidian-style vaults, and file-native exploration systems.

== References
[1]: https://github.com/safishamsi/graphify "GitHub - safishamsi/graphify: AI coding assistant skill (Claude Code, Codex, OpenCode, Cursor, Gemini CLI, OpenClaw, Factory Droid, Trae). Turn any folder of code, docs, papers, images, videos, or YouTube links into a queryable knowledge graph · GitHub"

[2]: https://github.com/safishamsi/graphify/blob/v4/ARCHITECTURE.md "graphify/ARCHITECTURE.md at v4 · safishamsi/graphify · GitHub"

[3]: https://github.com/safishamsi/graphify/blob/v4/pyproject.toml "graphify/pyproject.toml at v4 · safishamsi/graphify · GitHub"

