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
    "Review - AnySearch"
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
  Source: "https://www.anysearch.com/home",
  ArtifactType: "Web Site",
  DocumentDate: "2026/05/19",
  Keywords: [AnySearch, Search Engine, Google, Agentic Search Engine],
)

#let a_001 = link(
  "https://www.anysearch.com/home"
)[#text(fill:blue)[AnySearch Web Site]]

= Overview
[AnySearch](https://www.anysearch.com?utm_source=chatgpt.com) is an AI-oriented search infrastructure platform that provides a unified interface for retrieving information from the public web and other online sources. Rather than being a traditional end-user search engine like [Google Search](https://www.google.com?utm_source=chatgpt.com), its core product is an API and tooling layer designed for LLM applications, autonomous agents, and developer workflows. The central idea is to abstract away the complexity of integrating multiple search providers, scraping heterogeneous web content, normalizing results, and delivering structured, machine-consumable outputs that AI systems can use directly.

Architecturally, AnySearch resembles a search orchestration layer more than a standalone search engine. A query submitted by an application is likely analyzed for intent, expanded or rewritten for better retrieval, then routed to one or more upstream sources depending on the task. Results are collected, normalized into a consistent schema, deduplicated, ranked, and returned as structured evidence. This makes it conceptually similar to “Internet-scale RAG” or dynamic search-augmented retrieval: instead of retrieving chunks from a pre-indexed private corpus, it retrieves live information from the open web and packages it for downstream LLM reasoning.

A notable aspect of the project is its explicit agent-first positioning. The service appears designed to plug into modern AI execution environments rather than human browser workflows. That means support for APIs, MCP-compatible integrations, and tooling intended for systems like coding assistants or autonomous agents. For developers building agentic applications, this removes the need to individually integrate search engines, implement content extraction pipelines, manage ranking logic, or maintain scraping infrastructure. In practical terms, it acts as “search middleware” between an LLM agent and the Internet.

The main value proposition is operational simplicity and cleaner retrieval for AI systems, but its exact strategic position depends on how much native infrastructure it owns. If it operates as a true multi-provider orchestrator with intelligent routing and fusion, it is meaningful infrastructure. If it mainly wraps one or two upstream search providers behind a cleaner API, it is more of a convenience abstraction. Either way, for AI agent builders, its relevance is much closer to tools like Exa, Tavily, SerpAPI, or Perplexity’s API layer than to consumer search engines.

== Google and AnySearch
It is not a replacement of Google. AnySearch is an AI search infrastructure platform, explicitly 
“API-first,” “ad-free,” and designed for AI agents, not traditional human browsing. ([AnySearch][1])
It exposes a unified search API (`/v1/search`) that routes queries to different providers, 
fuses results, and returns structured JSON with metadata like source, relevance score, 
timestamps, etc. ([AnySearch][2])

It provides integration paths for agent tools like Claude Desktop, OpenCode, OpenClaw, 
MCP servers, and “skills,” which strongly suggests the primary audience is developers 
building agentic systems. ([AnySearch][2])

Google offers:

- massive web index
- maps
- shopping
- local businesses
- images
- news
- videos
- knowledge graph
- instant answers
- Gmail/Workspace ecosystem integration
- mature ranking quality

AnySearch focuses on:

- agent-consumable search
- structured machine-readable retrieval
- API access
- multi-source routing
- execution-friendly data


AnySearch can be a drop-in external search substrate to SemOS. Assume users want to
“Find recent FDA guidance about vaccine cold chain monitoring.” Instead of scraping Google,
agent calls AnySearch API, gets normalized JSON:

  - title
  - URL
  - cleaned content
  - timestamps
  - source types
  - quality scores

That is much easier for autonomous agents than parsing HTML SERPs.

Internally, it is (appears) a standard RAG stack:
- Detect intent
- Route to providers
- Merge heterogeneous sources
- Clean content
- standard schema
- rerank
- relevance
- quality scoring

```text
User query
   ↓
Query understanding / rewriting
   ↓
Retriever over local corpus
   ↓
Retrieve top-k chunks
   ↓
(optional rerank)
   ↓
LLM synthesis
```
== Interfaces
It supports MCP, skills, and API.

== Related Products/Services
- Perplexity
- You.com
- Exa
- Tavily

== Content normalization

Internet content can be very messy:

- HTML
- PDFs
- JavaScript pages
- snippets
- malformed metadata
- duplicate mirrors

This is a big engineering challenge. AnySearch tries to solve some of the problems,
such as dedup, extracting metadata, etc.

== Integration with SemOS
SemOS needs the ability to search the Internet. AnySearch (and the similar products/services)
can be a good fit.

Most such products/services are fee-based. AnySearch does not have a pricing plan yet.
No API keys required yet. Currently, it supports anonymous access (no Authhorization header),
with usage limited by per-IP daily free quota and lower rate/concurrency limits.

[1]: https://www.anysearch.com/about?utm_source=chatgpt.com "About | AnySearch | AnySearch"
[2]: https://www.anysearch.com/docs?utm_source=chatgpt.com "AnySearch — AI Search Infrastructure for Agents"

