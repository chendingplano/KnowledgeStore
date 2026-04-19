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

= List of Figures
#outline(
  title: [],
  target: figure.where(kind: image),
)
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
    "Diary-20260313"
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

// #figure(
//   image("Images/image_2026030101.png", width: 100%),
//   caption: [Hardware setup (#a_030105)],
// )

#set page(numbering: "1")
#counter(page).update(1)
#counter(heading).update(0)

= Inside Claude Code 

#let a_0101 = link(
  "https://ccunpacked.dev/#agent-loop"
)[#text(fill: blue)[WebSite]]

#let a_0102 = link(
  "https://alex000kim.com/posts/2026-03-31-claude-code-source-leak/"
)[#text(fill: blue)[Article]]

#a_0101 \
Source: Hacker News

This website analyzes Claude Code (leaked yesterday).

#figure(
  image("Images/image_2026040101.png"),
  caption: [Claude Code Tools (#a_0101)]
)

#figure(
  image("Images/image_2026040102.png"),
  caption: [Claude Code Commands (#a_0101)]
)

#figure(
  image("Images/image_2026040103.png"),
  caption: [Claude Code Hidden Features (#a_0101)]
)

== Frustration Detection via Regex

This is kind of surprising to me:
```text
/\b(wtf|wth|ffs|omfg|shit(ty|tiest)?|dumbass|horrible|awful|
piss(ed|ing)? off|piece of (shit|crap|junk)|what the (fuck|hell)|
fucking? (broken|useless|terrible|awful|horrible)|fuck you|
screw (this|you)|so frustrating|this sucks|damn it)\b/
```

I thought LLMs can understand the languages and thus will determine the sentiment 
by understanding what the users are saying. But regex is faster and cheaper than an
LLM inference call.

Note that Google Gemini CLI and OpenAI Codex area already open source. But those 
companies open-sourced their agent SDK (a toolkit), not the full internal wriing
of their flagship products.

My understanding is that: it still matters, maybe not such a big deal. As we have
seen, Anthropic did something in the code to cope with distillation, cheating 
the use of their subscription APIs, etc. When all the internal work is open-sourced,
there is hardly any means to hide what they want to do but do not want users know it.

Anthropic acquired Bun at the end of 2025 and Claude Code is built on top of it.

= 2026/04/01 - CAD in Browsers

#let a_0103 = link(
  "https://solvespace.com/webver.pl"
)[#text(fill: blue)[WebSite]]

#a_0103 \
Source: Hacker News

Below is an example:
#figure(
  image("Images/image_2026040104.png"),
  caption: [CAD Drawing (#a_0103)]
)

This is still in an alpha release. We can wait for it to mature. Not sure whether we can use it or not.

= 2026/04/02 - Pretex

#let a_0201 = link(
  "https://github.com/chenglou/pretext"
)[#text(fill: blue)[GitHub]]

#a_0201 \
Source: Hacker News

This is an open-source TypeScript library to render text around objects.

= 2026/04/02 - Let Codex Work for You 24 Hours

#let a_0403 = link(
  "https://github.com/thu-nmrc/OpenHarness-For-Codex"
)[#text(fill: blue)[GitHub]]

#a_0403 \
Source: WeChat

This is a Python code. Can be integrated with OpenClaw, to make Codex work for you 24 hours a day.

One thing to notice that it has a file MISSION.md. You express what you want to do in this
markdown doc. This is quite important.

= 2026/04/02 - LangChain DeepAgents Harness

#let a_0404 = link(
  "https://mp.weixin.qq.com/s/jnKW_jxGbvlMzrW_T2GJ1A"
)[#text(fill: blue)[Article]]

This article uses LangChain DeepAgents to develop a `Harness`. When I have time, I may need to look at it.

= 2026/04/03 - Gemma 4

#let a_0301 = link(
  "https://deepmind.google/models/gemma/gemma-4/"
)[Article]

#a_0301 \
Source: Hacker News

Looks like it is pretty good: open-source, 26B and 31B.

#figure(
  image("Images/image_2026040301.png"),
  caption: [Claude Code Tools (#a_0301)]
)

= 2026/04/05 - Context Graphs

#let a_0501 = link(
  "https://dzone.com/articles/context-graphs-from-outcomes-to-decisions"
)[text(fill: blue)[Article]]

#a_0501 \
Source: dzone

The core concept is that when the system makes a decision, it needs to store not just the decision,
but the context, rules, exceptions, references, etc. that lead to the decision.

"*Decisions Are Data Tool*" 

In AHS (Artifact Hybrid Store), when the system makes a decision, we need to record:
- The context
- The rules applied
- The exception, if any
- Any other references
- A group of keywords
- Semantic signature (i.e., the description about the decision in natural language)

= 2026/04/05 - Karpathy LLM Wiki

#let a_0502 = link(
  "https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f"
)[text(fill: blue)[Karpathy Article]]

#let a_0503 = link(
  "https://x.com/karpathy/status/2039805659525644595"
)[#text(fill: blue)[Karpathy Tweet]]
#a_0502 \
Source: Hacker News

"Instead of just retrieving from raw documents at every time, the LLM *incrementally builds
and maintains a persisted wiki* - a structured, interlinked collection of markdown files that
sits between you and the raw sources. When you add a new source, the LLM doesn't just index it for
later retrieval. It reads it, extracts the key information, and integrates it into the existing
wiki - updating entity pages, revising topic summaries, noting where new data contradicts
old claims, streanthening or challenging the evolving synthesis The knowledge is compiled once
then kept current, not re-derived on every query."

*Automatic and Updated All the Time*

You never (or rarely) write the wiki youself - the LLM writes and maintains all of it:
- Summarize
- Cross-reference
- Filing
- Bookkeeping
- Reasoning: if this is a conclusion or a decision
- Rules
- Score systems
- Social network feeds
- Third-party apps
- And so on

Quote:

- *Personal*: tracking your own goals, health, psychology, self-improvement — filing journal entries, articles, podcast notes, and building up a structured picture of yourself over time.
- *Research*: going deep on a topic over weeks or months — reading papers, articles, reports, and incrementally building a comprehensive wiki with an evolving thesis.
- *Reading a book*: filing each chapter as you go, building out pages for characters, themes, plot threads, and how they connect. By the end you have a rich companion wiki. Think of fan wikis like Tolkien Gateway — thousands of interlinked pages covering characters, places, events, languages, built by a community of volunteers over years. You could build something like that personally as you read, with the LLM doing all the cross-referencing and maintenance.
- *Business/team*: an internal wiki maintained by LLMs, fed by Slack threads, meeting transcripts, project documents, customer calls. Possibly with humans in the loop reviewing updates. The wiki stays current because the LLM does the maintenance that no one on the team wants to do.
- *Competitive analysis, due diligence, trip planning, course notes, hobby deep-dives* — anything where you're accumulating knowledge over time and want it organized rather than scattered.

== Architecture

- *Raw sources* - The storage layer
- *The Wiki*
- *The Schema* - A document (e.g., CLAUDE.md for Claude Code or AGENTS.md for Codex) that tells
the LLM how the wiki is structured, what the convetions are, and what workflows to follow when
ingesting sources, answering questions, or maintaining the wiki. 

=== Lint

Periodically, ask the LLM to health-check the wiki. Look for: contradictions between pages, stale claims that newer sources have superseded, orphan pages with no inbound links, important concepts mentioned but lacking their own page, missing cross-references, data gaps that could be filled with a web search. The LLM is good at suggesting new questions to investigate and new sources to look for. This keeps the wiki healthy as it grows.

=== Index

"index.md is content-oriented. It's a catalog of everything in the wiki — each page listed with a link, a one-line summary, and optionally metadata like date or source count. Organized by category (entities, concepts, sources, etc.). The LLM updates it on every ingest. When answering a query, the LLM reads the index first to find relevant pages, then drills into them. This works surprisingly well at moderate scale (~100 sources, ~hundreds of pages) and avoids the need for embedding-based RAG infrastructure."

This 'linear' index is not scalable. We will use a Index Tree. An entry in Index Tree contains:
- Link
- One-line summary
- Metadata
- Type (container or leaf)
- ...

=== Log

Log is chronological. It is an append-only record of what happened and when - ingests, queries,
lint passes. A useful tip: if each entry starts with a consistent prefix (e.g., `\#\# [2026-04-02] 
ingest | Article Title`), the log becomes parseable with simple unix tools.

Since logs can be huge, we will provide an API to let LLMs retrieve logs.

= 2026/04/05 - Virtual File System and `just-bash`

#let a_0504 = link(
  "https://www.mintlify.com/blog/how-we-built-a-virtual-filesystem-for-our-assistant"
)[#text(fill: blue)[Article]]

#a_0504 \
Source: Hacker News

"Our assistant could only retrieve chunks of text that matched a query. If the answer lived across multiple pages, or the user needed exact syntax that didn't land in a top-K result, it was stuck. We wanted it to *explore docs the way you'd explore a codebase*."

I think 'explorability' is one of the major departure from the conventional schema-based databases,
a journey from deterministic to undeterministic.

== Faking a Shell

Agents do not need a real file system. It just needs the illusion of one.

== How It Works

=== Store File System in a structure. 

When the system starts, it loads the 'file system' into memory. For larger file
systems, it can load a portion of it as needed.

For each of the command, such as `ls`, `cd`, and `find`, run them in local memory
with no network calls.

*Access Controls*

When loading the file system in memory, the file system is pruned based on what the
users can see and can do. If a user does not have read-access, the virtual file
system can either not showing the file at all or grey it out.

#figure(
   image("Images/image_2026040701.png", width: 100%),
   caption: [Hardware setup (#a_0504)],
)

*Reassembling Pages from Chunks*

When files are stored in chunks, we need to reassemble them from chunks dynamically
for commands such as `more` or `cat`.

*Optimizing Grep*

--------- \
`cat` and `ls` are straightforward to virtualize, but grep -r would be far too slow
if it naively scanned every file over the network. We intercept just-bash’s grep, 
parse the flags with yargs-parser, and translate them into a Chroma query
(\$contains for fixed strings, \$regex for patterns).

Chroma acts as a coarse filter that identifies which files might contain the hit, 
and we bulkPrefetch those matching chunks into a Redis cache. From there, we rewrite
the grep command to target only the matched files and hand it back to just-bash for
fine filter in-memory execution, which means large recursive queries complete in
milliseconds.

--------- \

= 2026/04/05 - Just-Bash

#let a_0505 = link(
  "https://github.com/vercel-labs/just-bash"
)[#text(fill: blue)[Article]]

#a_0505 \
Source: Hacker News

Just-bash is a virtual bash environment with an in-memory filesystem, written in TypeScript
and designed for AI agents. It aims to let agents use familiar Unix workflows like find, grep, pipes, jq, and basic scripting without spawning a real shell or giving access to the real filesystem by default. The project is explicitly marked beta.

This project is in beta. Use it with care.

= 2026/04/05 - Why People Tend to Choose TypeScript

Source: ChatGPT

*TypeScript is often the shortest path from idea to usable product*. Not the fastest runtime. Not the strongest systems language. But often the *best overall tradeoff*.

== Ecosystem

Projects like `just-bash`, coding agents, CLI tools, tool runners, MCP-style integrations, web
backends, and developer tooling usually need to work with:

- Node.js
- package managers like npm/pnpm
- JSON, YAML, Markdown
- web APIs
- browser or editor integrations
- LSPs, AST tooling, build tools
- AI SDKs and model provider SDKs

TypeScript sits in the middle of all of that very naturally. If your product touches:

- terminal-like UX
- web UI
- backend API
- editor integration
- agent tools
- SDKs

then TS lets one team stay in one language across most of the stack. That is a huge productivity win.

== Tooling-Heavy, not Compute-Heavy

A lot of agent systems are not dominated by raw CPU performance. They spend much of their time doing
things like:

- orchestrating tools
- calling APIs
- parsing files
- managing state
- handling JSON
- streaming model outputs
- gluing together services

That workload is usually *I/O-bound and integration-bound*, not CPU-bound. So Go or Rust may be faster, but the speedup often does not matter much compared with:

- model latency
- network latency
- tool latency
- database latency

If 80% of your wall-clock time is waiting for LLM responses or external services, then TypeScript’s
runtime overhead is often acceptable.

== The Language: TypeScript

TypeScript is much better than JavaScript for large codebases, while keeping JavaScript’s
flexibility People want:

- easy iteration
- huge ecosystem
- dynamic expressiveness

But plain JavaScript becomes painful at scale. TypeScript gives:

- type checking
- editor support
- easier refactoring
- interface contracts
- decent maintainability

So it hits a sweet spot:

- much faster to build than Rust in many teams
- much safer to maintain than plain JS

That sweet spot matters a lot for startup-style or research-to-product projects.

== Talent

AI product teams often already have strong TypeScript talent. A practical reason: many teams
building these tools already come from:

- frontend
- full-stack web
- platform/product engineering

Those teams are often much stronger in TypeScript than in Go or Rust. So TypeScript is not just a
technical choice. It is a *team optimization choice*.

A team of excellent TS engineers will usually ship a better agent product faster than the same
team trying to force itself into Rust for prestige or theoretical performance.

== Fast Iteration

Fast iteration matters more than peak correctness in early agent systems. A lot of agent software
is still evolving quickly. The interfaces are not settled.

Teams are still learning:

- what tools the agent needs
- how tool schemas should look
- what abstractions work
- where the real bottlenecks are

In that environment, TypeScript is attractive because it supports:

- rapid prototyping
- frequent refactoring
- quick library integration
- easy debugging

Go and Rust are often better once the architecture is clearer and the bottlenecks are known. 
But TypeScript is often better when the problem itself is still moving.

== Node.js

Node is extremely convenient for CLI and developer-tool workflows. This is especially relevant for
projects like `just-bash`, Claude Code–style tools, and other coding assistants.

TypeScript/Node is very good at:

- shipping CLIs
- spawning/managing subprocesses
- working with files
- talking to local dev tools
- wrapping shell commands
- handling streams
- integrating with editors and webviews

If your product is “developer tool + AI,” Node is often the path of least resistance.

== Frontend, Backend, and SDKs Agnostic

Sharing types across frontend, backend, and SDKs is valuable. A lot of modern AI tools have:

- a backend service
- a web UI
- an SDK
- maybe a CLI

With TypeScript, you can share:

- request/response types
- tool schemas
- config schemas
- event types
- model message formats

That is very convenient and reduces friction. Go or Rust can do this too, but usually not
as smoothly across the web stack.

== The Backend

The backend in these systems is often not a classic backend. Many of the projects are really
closer to:

- orchestration layers
- tool runtimes
- developer platforms
- agent harnesses
- integration servers

Those are not always the same as a classic high-throughput backend like:

- a database
- a proxy
- a low-latency RPC service
- a storage engine

For classic backend infra, Go or Rust often make more sense. For orchestration-heavy agent systems,
TypeScript often feels more natural.

== Why not Go

Go is a very strong choice when you want:

- simple deployment
- good concurrency
- solid performance
- operational clarity
- smaller memory overhead than Node
- easier static binaries

Go is especially good for:

- APIs
- workers
- ingestion services
- control planes
- daemons

But Go is often less pleasant than TypeScript for:

- rich JS ecosystem access
- dynamic data wrangling
- frontend/backend type sharing
- moving quickly in web/AI integration-heavy codebases

So Go is often excellent for the *strong backend core*, but not always the preferred language
for the *agent-facing integration layer*.

== Why not Rust

Rust is attractive when you need:

- high performance
- low memory usage
- strong correctness guarantees
- security-sensitive systems programming
- parsers, runtimes, databases, sandboxes

For something like a real shell/runtime/sandbox, Rust can be a very compelling choice.

But Rust has higher costs:

- slower development for many teams
- steeper learning curve
- more friction for rapid product iteration
- smaller “plug-and-play AI app” ecosystem than Node

So many teams avoid Rust unless they truly need its strengths.

== Conclusion

Because AI tooling often combines all of these:

- web product
- CLI
- streaming APIs
- JSON-heavy interfaces
- fast-moving abstractions
- SDK integrations
- developer tooling
- prompt/tool orchestration

That is almost the ideal habitat for TypeScript. So the choice is often not:

> “What language is best in theory?”

It is:

> “What language minimizes total friction across the whole product?”

== Hybrid Architecture

That hybrid architecture is often the strongest one. So the real answer is not “TypeScript instead
of Go/Rust.” It is often:

> *TypeScript at the edges, Go/Rust in the core.*

That pattern fits our EHS idea very well.

= 2026/04/05 - Obsidian

= 2026/04/06 - Sage-Wiki

#let a_0601 = link(
  "https://x.com/xoai/status/2040936964799795503"
)[#text(fill: blue)[Article]]

#let a_0602 = link(
  "https://github.com/xoai/sage-wiki"
)[#text(fill: blue)[GitHub]]

#a_0601 \
#a_0602 \
Source: Hacker News

- Problem: In RAG, the LLM starts from scratch on every question. Nothing compounds.
- Raw sources are the source files. The LLM is the compiler. The wiki is the build output.
- Like any good build system, you don't recompile everything from scratch - you track what changed and rebuild only what's affected.
- Key: Users add papers, articles, and notes to a folder, and sage-wiki compiles them into structured, interlinked markdown.
- Extract: concepts, identifies cross-references, flags contradctions, and ensures all content is searchable.
- Each new source enriches the wiki, allowing knowledge to accumulate.

#figure(
   image("Images/image_2026040602.png", width: 100%),
   caption: [Hardware setup (#a_0601)],
)

--------- \

*Pass 1* — Diff. Hash every file in raw. Compare against the manifest from the last run. Produce a changeset: new, modified, and deleted files. If nothing has changed, stop. This is pure Go, no LLM call — it should be instant.

*Pass 2* — Summarize. For each new or modified source, the LLM reads the full document and writes a structured summary. Different source types get different treatment — a 50-page research paper needs deeper extraction than a 2-page blog post. The summaries are the compiler’s intermediate representation.

*Pass 3* — Extract concepts. The LLM identifies entities and concepts from the summaries, deduplicates them against the existing ontology (e.g., is “transformer architecture” the same as “Transformer model”?), and registers new nodes in the knowledge graph. This is where the ontology layer — typed entities with relations, BFS traversal, cycle detection — earns its keep.

*Pass 4* — Write articles. For each concept that was touched (new or updated), the LLM writes or updates a wiki article. This is the pass that creates the interlinked markdown. A single source might touch 10-15 wiki pages. Cross-references, contradiction flags, and confidence tags — all generated here.

*Pass 5* — Images. Extract and reference images from source documents. LLMs can’t natively parse Markdown with inline images in a single pass, so this is handled separately.

--------- \

#figure(
   image("Images/image_2026040601.png", width: 100%),
   caption: [The 5-pass compiler pipeline (#a_0601)],
)

== Search

Sage-wiki does not use vector store. It uses SQLite with two search strategies:

--------- \

*FTS5 for BM25 Search* — FTS5 is SQLite’s full-text search extension, and BM25 is an algorithm for keyword-based document ranking. Together, they provide fast and effective keyword search capabilities.

*BLOB vectors for semantic search* — Embeddings (high-dimensional numeric representations of text) are stored as BLOBs (binary large objects) inside SQLite. Cosine similarity computation allows comparing these vectors at query time for semantic search. No need for external databases like Pinecone or Qdrant, nor a separate background process.

--------- \

We may want to use PostgreSQL instead of SQLite to improve scalability. Note thatt PostgreSQL has an extention for full-text search. Not sure the quality and performance, comparing with ElasticSearch.

Another important design decision is not to provide a gigantic collection of vectors.
Instead, we will have many smaller vector collections. When a node becomes too big,
we may create a vector collection for it. Its child nodes normally do not have their
vector collections. I tend to create a vector collection for each of the second
level nodes.

*Vector Index*

Without vector index, we would need to compare each and every vector for a query. 
This is acceptable only when there are not many vectors in a collection. Otherwise, 
a vector index (such as the ones used in most vector databases or the one
open-sourced by Facebook).

== Lessions Leared

--------- \
1. *The ontology is the hardest part*. Concept deduplication — deciding whether “attention mechanism” and “self-attention” should be the same node or different nodes linked by a relation — is where the LLM struggles most. I’ve found that maintaining a typed entity system with explicit relation types (is-a, part-of, related-to, contradicts) produces much cleaner wikis than letting the LLM free-form link things.

2. *Linting is more valuable than I expected*. The sage-wiki lint command runs health checks: orphan pages with no inbound links, stale claims that newer sources have superseded, missing cross-references, and important concepts mentioned but lacking their own page. The LLM is surprisingly good at this — it can scan the wiki and suggest exactly where the gaps are. I run it after every compile.

3. *Every task should produce two outputs*. Whatever you asked the wiki — a comparison, an analysis, a connection you discovered — that’s output one. Output two is updates to the relevant wiki articles. If you don’t make this explicit, the LLM will do the work and let the knowledge evaporate into chat history. This is the rule that makes the wiki compound.

4. *Source type classification matters*. Don’t treat every document the same at ingest time. A research paper needs a different extraction than a blog post or a podcast transcript. Classify first, then run type-specific prompts. This saves tokens and produces better summaries.

  If you want to extend sage-wiki to handle new source types, you can add custom type handlers. Developers can define new source types in the configuration file and associate each type with a specific extraction and summarization prompt. This makes it possible to support domain-specific formats, such as datasets, code repositories, or meeting transcripts, by mapping each one to its own processing logic. The handler lookup is modular, so adding new logic requires only a config update and, if needed, a new Go snippet for preprocessing. This approach empowers users to customize the tool for their own formats and workflows.

5. *The self-learning loop is underrated*. sage-wiki inherits a mistake-prevention system from my earlier project, sage-memory: when the compiler or linter reports an error, the correction is stored. Corrections, conventions, and fixes are recorded directly in the main SQLite database alongside user preferences. Each correction is linked to its triggering pattern so that when the compiler or linter sees the same pattern in the future, it can automatically recall and apply the fix. This system currently supports five types of learning: corrections, conventions, API drift, error fixes, and preferences. The approach is incremental and reliable, making it easy for developers to extend or inspect the accumulated knowledge over time. The compiler literally gets better with every run.

6. *Collaborative wikis*. Right now, Sage-wiki is single-player. Karpathy hints at team use cases—Slack threads, meeting transcripts, shared knowledge. That is a genuinely different problem involving merge conflicts, access control, and multi-writer consistency. These features are not in scope for v1, but the SQLite foundation could support them in the future. Collaboration is on the roadmap, and I am interested in working with contributors who want to design and implement these capabilities. If you are interested in helping shape the direction of collaborative features, I invite you to get involved or share ideas.

7. *Improvement: Better image understanding*. Pass 5 (images) is the weakest. LLMs still can’t natively read markdown with inline images in a single pass. The workaround — read text first, then view images separately — works but is clunky. This will get better as models improve.

8. *Improvement: Streaming compilation feedback*. Right now, compiling a large batch of sources is a black box while it runs. I want real-time progress: which source is being summarized, which articles are being updated, and what concepts were discovered. This is a UX problem, not an architecture problem.

9. *Provenance tracking*. One comment on Karpathy’s gist described tracking content hashes per proposition — so when a source file changes, the wiki knows exactly which claims might be stale. sage-wiki tracks source-level freshness but not proposition-level. This is a meaningful gap for high-stakes use cases.

  *Comment*: the word 'proposition' means a claim, a concept, an entity, a relation, etc. Instead of tracking changes on files or chunks, the ability to track proposition is very important so that when a file changes, we do not have to re-work on everything but only the affected propositions.

10. *Cost optimization*. Running the full compiler on 50 papers isn’t cheap. Smarter batching, prompt caching, and model selection per pass (for example, using a cheaper model or locally hosted models for summarization and a stronger one for article writing) would help. The config already supports per-pass model selection

= 2026/04/12 - Anthropic Tool Design

File: 20260412-anthropic-tool-design

= 2026/04/12 - Skills

Installed 19 skills from https://github.com/ComposioHQ/awesome-claude-skills/tree/master

= 2026/04/12 - Buffett Letters

https://buffett-letters-eir.pages.dev/

It collects all the letters that Buffett wrote to the board, from 1958 to 2025.
This is a good source to test our knowledge store.

= 2026/04/12 - wechat-cli

github.com/freestylefly/wechat-cli

We can use this CLI to access WeChat.

= 2026/04/13 - everything-claude-code

This is a huge package. For more information, refer to Workspace/KnowledgeStore/AI/Project-EverythingClaudeCode.md.

= 2026/04/15 - EverOS

This is a memory system. Refer to [[EverOS]], [[fileid:2026041501]].

= 2026/04/15 - VRAG

#let a_002 = link(
  "https://github.com/Alibaba-NLP/VRAG"
)[#text(fill: blue)[Alibaba VRAG]]

#a_002 \
Source: WeChat

VRAG is a multimodal, agentic RAG framework that teaches vision-language models (VLMs) to actively explore, 
retrieve, and reason over visual data using reinforcement learning. Traditional RAG (even multimodal RAG) 
fails on visual-heavy data. VRAG adds the visual probe capability, or visual retrieval. VRAG enables models
to actively explore visual data (images, PDFs, charts) through multi-step reasoning and reinforcement
learning, instead of passively retrieving text chunks.

Instead of:
```text
query → retrieve → generate
```

VRAG turns RAG into:

```
Thought → Action → Observation → Update → (repeat)
```

Retrieval is no longer “which document”, but “which part of which image”.
It works as:
```text
* `<region>[xmin, ymin, xmax, ymax]</region>`
* Crop → re-analyze → refine
```

This enables fine reasoning:

1. Retrieve a page/image
2. Identify interesting region
3. Zoom into it
4. Extract fine-grained info

Like how humans read documents.

The repo is mainly about VRAG-RL, which is a reinforcement learning framework to train agents to do
the above effectively

VRAG system consists of three main components:

*1. Visual search engine*

- index images (converted from PDFs, etc.)
- uses visual embeddings (e.g., ColPali family)

*2. VLM agent (e.g., Qwen2.5-VL)*

- generates thoughts/actions
- interacts with search engine

*3. RL training loop*

- samples trajectories
- optimizes behavior over time

```text
| Aspect      | Traditional RAG | VRAG                   |
| ----------- | --------------- | ---------------------- |
| Data        | Text            | Visual + multimodal    |
| Retrieval   | Passive         | Active exploration     |
| Granularity | Document/chunk  | Region-level           |
| Loop        | Single-step     | Multi-step             |
| Training    | Supervised      | Reinforcement learning |
| Query       | Static          | Iteratively refined    |
```

Compared to EverOS (previous discussion)

```text
| Dimension | EverOS            | VRAG                   |
| --------- | ----------------- | ---------------------- |
| Focus     | Memory            | Retrieval + reasoning  |
| Data      | structured memory | visual corpora         |
| Time      | long-term         | short-term task loop   |
| Core loop | memory lifecycle  | agent exploration loop |
```

Compared to SemOS

```text
| SemOS                      | VRAG equivalent           |
| -------------------------- | ------------------------  |
| Explorability (filesystem) | ✅ but in visual space    |
| Path-native exploration    | ❌ (action-based instead) |
| Unified memory             | ❌ (not focus)            |
| Strong backend retrieval   | ✅                        |
| Agent loop                 | ✅ central                |
```

*Key conceptual shift*

```
Classic RAG:
  retrieve → read

VRAG:
  look → zoom → search → refine → reason
```

== Conclusion

We can't use VRAG directly but we can use it as an add-on to complement the visual analysis
and reasoning capabilities to SemOS. We need to come back to this project when the needs arise.

= 2026/04/17 - Unsloth

#let a_003 = link(
  "https://unsloth.ai/docs/new/studio"
)[#text(fill: blue)[Link]]

#a_003 \
Source: Hacker News

= 2026/04/17 - Run Qwen 3.6 Locally

#let a_004 = link(
  "https://unsloth.ai/docs/models/qwen3.6"
)[#text(fill: blue)[Link]]

#a_004 \
Source: Hacker News

= References

[1]: https://arxiv.org/abs/2505.22019?utm_source=chatgpt.com "VRAG-RL: Empower Vision-Perception-Based RAG for Visually Rich Information Understanding via Iterative Reasoning with Reinforcement Learning"

= 2026/04/18 - Onyx

Refer to [[Onyx]]

= 2026/04/18 - Installed web-access Skill

#let a_005 = link(
  " https://github.com/eze-is/web-access"
)[#text(fill: blue)[GitHub]]

#let a_006 = link(
  "https://mp.weixin.qq.com/s/A1aYj3Dh-T32NqQdlYh27Q"
)[#text(fill: blue)[WeChat Article]]

#a_005 \
#a_006 \
Source: WeChat

This skill is used to help using web to search and deep research.

I tested using Claude Code:
```
帮我调研 Dify、Coze、FastGPT 这三个 AI 工作流平台，重点关注：支持的节点类型、模型接入方式、是否支持私有化部署、价格策略。整理成对比表格。
```

The results are in [[compare dify coze fastgpt]]

