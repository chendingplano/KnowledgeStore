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
    "Review - Zot"
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
  logical_name: "zot",
  file_id: "2026053001",
  source: "https://github.com/patriceckhart/zot",
  content_type: "review",
  document_date: "2026/05/30",
  keywords: [Zot, Agent Harness],
)

= Overview
zot is an open-source coding agent harness written in Go that aims to provide a lightweight 
alternative to tools such as Claude Code, Codex CLI, OpenCode, and similar terminal-based 
AI development assistants. The project emphasizes simplicity: it is distributed as a single 
static binary, supports multiple AI providers out of the box, and exposes a minimal set of 
tools for interacting with source code and the local environment. The author describes it 
as "yet another coding agent harness," but the focus is clearly on reducing complexity while 
preserving the core capabilities needed for AI-assisted software development. ([GitHub][1])

One of zot's strongest features is its broad model-provider support. It can connect to a 
large number of commercial and local model backends, including Anthropic, OpenAI/Codex, 
Gemini, GitHub Copilot, Ollama, OpenRouter, Groq, Bedrock, Azure OpenAI, Together, Hugging 
Face, and many others. Rather than coupling the agent to a specific vendor, zot acts as a 
common execution layer that can route requests to whichever model the user prefers. This 
makes it particularly attractive for developers who frequently experiment with different 
models or want to switch providers without changing workflows. ([GitHub][1])

Architecturally, zot is intentionally minimalist. The built-in agent operates with four 
primary tools—read, write, edit, and bash—which is reminiscent of the toolsets used by 
modern coding agents. It supports interactive terminal UI mode, plain-text mode, and JSON 
mode for automation. The system also includes support for reusable instructions through 
`SKILL.md` files, a concept that will likely feel familiar to you given your interest in 
knowledge structures and skill-based prompting. Additionally, zot provides a JSON-RPC-based 
extension framework that allows new capabilities to be implemented in any programming 
language and loaded as subprocesses. ([GitHub][1])

Another interesting aspect is its extension ecosystem. Extensions are not installed by 
default but can be added on demand. For example, the companion project 
[zot-review](https://github.com/patriceckhart/zot-review?utm_source=chatgpt.com) 
implements a structured repository-wide code review system that maps a codebase into 
feature areas, records findings, tracks review state, and generates reports. This 
suggests that the author views zot less as a monolithic coding assistant and more as a 
lightweight agent runtime that can be extended with specialized workflows. ([GitHub][2])

From a SemOS perspective, the most notable idea is the combination of *SKILL.md-based behavior 
injection*, *simple tool abstractions*, and *extension-based specialization*. Zot does not 
appear to have a sophisticated memory system, workflow engine, or knowledge graph. Instead, 
it follows a "small core, extensible edges" philosophy. Compared with Claude Code, Codex, or 
OpenCode, it is closer to a lightweight agent shell. If you were designing SemOS as an explorable 
knowledge system, the most reusable concepts here are probably the skill-loading mechanism and 
the extension architecture rather than the agent itself. In many ways, Zot resembles a streamlined 
framework for building custom AI-powered developer tools rather than a complete autonomous agent 
platform. ([GitHub][1])

== References
[1] Patriceckhart/zot: Yet another coding agent harness, 
https://github.com/patriceckhart/zot?utm_source=chatgpt.com

[2] Patriceckhart/zot-review: Structured repo-wide code,
https://github.com/patriceckhart/zot-review?utm_source=chatgpt.com

