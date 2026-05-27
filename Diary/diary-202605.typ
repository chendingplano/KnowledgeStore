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
    "Contextual Retrieval"
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
  created: "2026/05/02",
  logical_name: "Contextual Retrieval",
  file_id: "2026050201",
  file_type: "Typst",
  keywords: ["Contextual Retrieval", "Contextual RAG", "RAG"],
)

= 2026/05/02 - Contextual Retrieval

#let a_001 = link(
  "https://www.anthropic.com/engineering/contextual-retrieval"
)[#text(fill: blue)[Anthropic Blog]]

#a_001 \
Source: WeChat

Contextual retrieval uses an LLM to generate context for each chunk before embedding ([[Contextual
Embedding]]) and creating the BM25 index ([[Contextual BM25]]). 

Below is Anthropic's prompt for generating the context for a chunk:
```text
<document> 
{{WHOLE_DOCUMENT}} 
</document> 
Here is the chunk we want to situate within the whole document 
<chunk> 
{{CHUNK_CONTENT}} 
</chunk> 
Please give a short succinct context to situate this chunk within the overall document for the purposes 
of improving search retrieval of the chunk. Answer only with the succinct context and nothing else.
```
#figure(
   image("Images/image_2026050201.png", width: 100%),
   caption: [Anthropic Contextual Retrieval (#a_001)],
)

#figure(
   image("Images/image_2026050202.png", width: 100%),
   caption: [Anthropic Contextual Retrieval (#a_001)],
)

== Thoughts
For file-based knowledge stores, when LLMs find a chunk but need contextual information, LLMs can
'explore' the store for it. 

In Anthropic example:
```text
original_chunk = "The company's revenue grew by 3% over the previous quarter."

contextualized_chunk = "This chunk is from an SEC filing on ACME corp's performance in Q2 2023; 
the previous quarter's revenue was $314 million. The company's revenue grew by 3% over the previous 
quarter."
```
without the context, we can't tell which company and in what time the original chunk it. Can LLMs
find the context? Without proper organizing content, they should be able.

=== Topics
In SemOS, we generate topics. 

= 2026/05/03 - TRiP 

#let a_002 = link(
  "https://github.com/carlovalenti/TRiP"
)[#text(fill:blue)[GitHub]]

#a_002 \
Source: WeChat

This is a complete transformer, written entirely in C.

= 2026/05/03 - Twelve Agent Harness Components

#figure(
   image("Images/image_2026050301.png", width: 100%),
)

#figure(
   image("Images/image_2026050302.png", width: 100%),
   caption: [Hardware setup (#a_001)],
)

= 2026/05/03 - SQLite ZSTD and FTS5

#let a_003 = link(
"https://www.toutiao.com/article/7634925447050002959/?app=news_article&category_new=__all__&module_name=iOS_tt_others&req_id_new=2026050218395282353CDD8B72BFB262A0&share_did=MS4wLjACAAAAw3rqzAbRbSo4klPah7FJFhb-dpoy0Y2_hu6Pcvvt2pc&share_token=c8a992d1-4614-11f1-82cc-043f72ac845a&share_uid=MS4wLjABAAAAw3rqzAbRbSo4klPah7FJFhb-dpoy0Y2_hu6Pcvvt2pc&timestamp=1777719050&tt_from=weixin&upstream_biz=iOS_wechat&use_new_style=1&utm_campaign=client_share&utm_medium=toutiao_ios&utm_source=weixin&wxshare_count=1&source=m_redirect"
)[#text(fill:blue)[Article]]

#a_003 \
Source: WeChat

It uses a few techniques to reduce the like-search from four hours to 400ms over a 250-GB, 50 millions
of rows table.

- ZSTD (Zstandard): a compression algorithm from Meta Yann Collect team, open-source.
  Its speed is 2-4GB/s per core.
- FTS5: SQLite full-text search (BM25)
- It used covered index
- No RowID: SQLite (MySQL is similar) uses a hidden field rowid as its primary key.
  Indexes point to rowid, and rowid resolves to physical results. This introduces
  another B-tree lookup. SQLite lets users turn off rowid through "WITHOUT ROWID". 
  Use this feature with care. The table's primary key must be short or integr.
  Otherwise, it may be slower.
- Partial index: we can add conditions to indexes so that it indexes only the ones
  that meet the conditions.

For more information, read the article.

= 2026/05/03 - How to Use Codex

#let a_004 = link(
  "https://www.toutiao.com/video/7634929795175809551/?app=news_article&category_new=__all__&module_name=iOS_tt_others&req_id_new=2026050218395282353CDD8B72BFB262A0&share_did=MS4wLjACAAAAw3rqzAbRbSo4klPah7FJFhb-dpoy0Y2_hu6Pcvvt2pc&share_token=68d34cc6-4614-11f1-a652-0c42a1692be4&share_uid=MS4wLjABAAAAw3rqzAbRbSo4klPah7FJFhb-dpoy0Y2_hu6Pcvvt2pc&timestamp=1777718889&tt_from=weixin&upstream_biz=iOS_wechat&utm_campaign=client_share&utm_medium=toutiao_ios&utm_source=weixin&wxshare_count=1&source=m_redirect"
)[#text(fill:blue)[How to use Codex]]

#a_004 \
Source: WeChat

This is a video. It shows a few quite important Codex features.

= 2026/05/03 - Understand-Anything

#let a_004 = link(
  "https://github.com/Lum1104/Understand-Anything/tree/main"
)[#text(fill:blue)[GitHub]]

#a_004 \
Source: WeChat

Understand-Anything (by Yuxiang Lin) is an open-source developer tool designed to solve a very practical 
problem: quickly understanding large, complex codebases or knowledge repositories. Instead of relying on 
manual reading or scattered documentation, it transforms an entire project into a structured, explorable 
knowledge graph, enabling both humans and AI agents to reason about the system at a higher level. 
([GitHub][1])

At its core, the project uses a multi-agent analysis pipeline. It first performs static analysis of the 
codebase, extracting structural elements such as files, classes, functions, and their relationships 
(e.g., dependencies, calls, inheritance). These elements are then organized into a graph representation, 
where nodes represent code entities and edges represent relationships. The output is a reusable JSON 
knowledge graph that effectively serves as a “digital twin” of the system’s architecture. ([Houdao][2])

On top of this graph, the tool provides an interactive dashboard and querying interface. Users can visually 
explore the system (zooming, searching, and navigating nodes), view plain-English summaries of code 
components, and follow auto-generated “guided tours” that explain architecture in dependency order. It also 
supports fuzzy and semantic search (e.g., asking “which parts handle authentication?”) and can map code 
structure to higher-level business domains, helping both engineers and non-engineers understand system 
logic. ([GitHub][1])

A key design philosophy is to act as a “comprehension layer” rather than a coding assistant. Instead of 
generating code, it enhances understanding and context for both developers and LLM-based agents. 
This makes it particularly useful for onboarding, impact analysis (e.g., understanding how changes 
propagate), documentation generation, and enabling downstream AI workflows that require structured 
context about a codebase. ([Houdao][2])

Overall, Understand-Anything represents a shift toward *graph-based, agent-assisted code comprehension*. 
By turning code and knowledge bases into navigable, queryable graphs, it bridges the gap between raw 
source code and high-level reasoning—making complex systems more explorable for humans and more usable 
for AI systems.

[1]: https://github.com/Lum1104/Understand-Anything?utm_source=chatgpt.com "Lum1104/Understand-Anything: Claude Code skills ..."

[2]: https://www.houdao.com/d/6400-UnderstandAnything-An-AIPowered-Knowledge-Graph-Tool-for-Rapidly-Understanding-Complex-Codebases?utm_source=chatgpt.com "Understand-Anything: An AI-Powered Knowledge Graph ..."

= 2026/05/04 - Open-Source Crawler

#let a_005 = link(
  "https://mp.weixin.qq.com/s/rhCId53g-rlnmBO-N3jlQw"
)[#text(fill:blue)[Crawler]]

#a_005 \
Source: WeChat

For info!

= 2026/05/06 - System Prompts 

#let a_006 = link(
  "https://github.com/asgeirtj/system_prompts_leaks"
)[#text(fill:blue)[GitHub]]

#a_006 \
Source: WeChat

It contains many system prompts from Anthropic, OpenAI, etc. The site is continously updated.

= 2026/05/07 - WikiBuilder

#let a_007 = link(
  "https://academy.dair.ai/blog/wiki-builder-claude-code-plugin"
)[#text(fill: blue)[Wiki Builder: A Claude Code Plugin for Building LLM Knowledge Bases]]

#let a_008 = link(
  "https://github.com/dair-ai/dair-workshops/tree/main/agentic-engineering-wiki"
)[#text(fill: blue)[GitHub: agentic-engineering-wiki]]

#a_007 \
#a_008 \
Source: Hacker News

It discusses how to build Knowledge Bases. It open sourced a WikiBuilder.

A wiki assumes the following file structure:

```text
agentic-engineering-wiki/
├── wiki.config.md
├── raw/
├── wiki/
│   └── index.md
├── derived/
├── prompts/
│   ├── compile-index.md
│   ├── compile-source-page.md
│   ├── compile-concept-page.md
│   ├── query-and-file.md
│   └── lint-wiki.md
├── logs/
│   └── maintenance-log.md
└── sources.md
```

SemOS can borrow this idea. Below is what I come up for SemOS:
```text
my-first-wiki/
├── wiki.config.md
├── raw/
├── documents/
│   └── index.md
│   └── document-0001
│       └── document-0001
├── more documents/
├── wiki/
│   └── index.md
│       └── L1-category
│           └── L2-category
│       └── L1-category
│       ...
├── derived/
├── prompts/
│   ├── compile-index.md
│   ├── compile-source-page.md
│   ├── compile-concept-page.md
│   ├── query-and-file.md
│   └── lint-wiki.md
├── logs/
│   └── maintenance-log.md
└── sources.md
```

= 2026/05/08 - Agent Harness

#let a_009 = link(
  "https://aakashgupta.medium.com/2025-was-agents-2026-is-agent-harnesses-heres-why-that-changes-everything-073e9877655e"
)[#text(fill:blue)[Article - 2025 Was Agents. 2026 Is Agent Harness]]

- An agent harness wraps around a model to manage long-running tasks reliably. The model is the Engine; the harness is the Car!
  The model generates responses. The harness handles everything else. Human approvals.
  Sub-agent coordination. Filesystem access. Prompt presets. Lifecycle hooks. Planning and execution.
- Human-in-the-loop
- Filesystem Access
- Tool Orchestration

== Six Components

- Component 1: Human-in-the-loop
- Component 2: Filesystem Access Management: get what the model wants; limit what the model can see; create what
  the model want to create; etc.
- Component 3: Tool Call Orchestration. Bad orchestration creates infinite loops and cascading failures. 
  Vercel's 80% tool reduction reveals harness thinking. Right tools, right times, right order, proper error handling.
- Component 4: Sub-agent Coordination. Complex tasks need specialized agents.
- Component 5: Prompt Preset Management. Different tasks need different instructions.
- Component 6: Lifecycle Hooks. Initialize context. run tasks. Save state. Handle failures. Retry logic. Logging.

== Three Harness Design Principles

- Minimal Necessary Intervention. Only intervene when the model can't self-correct. Let the model handle
  ambiguity. Step in for irreversible actions or security boundaries.
- Progressive Disclosure. Start with limited tools and permissions. Expand as tasks required. Don't give database
  delete permissions unless needed. Least privilege by default.
- Fail-Fast with Recover. Detect failures quickly. Don't let agents spiral. When failures occur, provide recovery
  paths. Retry with different approaches. Fall back to humans. Never fail silently.

= 2026/05/20 - PDFCraft
This is an open-source project. I have forked it (https://github.com/chendingplano/pdfcraft.git) and
installed on MacMini. The good thing about this project is that it has 99+ PDF related tools.
We can integrate these to SemOS.

Visit ThirdParty/pdfcraft/USER_MANUAL.md for more information.

= 2026/05/23 - Verify LLM Claims

#let a_010 = link("
  https://dzone.com/articles/fact-check-llm-outputs
  ")[#text(fill: blue)[Article]]

#a_010 \
Source: dzone

This article uses a separate LLM to verify the claims extracted by the primary LLM.
We may want to do similar thing.

= 2026/05/23 - DeepSeek Concurrency and User ID
#let a_011 = link(
  "https://api-docs.deepseek.com/quick_start/rate_limit"
)[#text(fill:blue)[Link]]

#a_011 \
Source: Hacker News

This link offers the connection concurrency and set user_id information.

= 2026/05/26 - OpenGUI

#let a_012 = link(
  "https://github.com/akemmanuel/OpenGUI"
)[#text(fill:blue)[GitHub]]

#a_012 \
Source: WeChat

This is an open-source that provides a uniform GUI for coding assistants, such as
Claude Code, Codex, Pi, etc.

= 2026/05/26 - Pandoc

#let a_013 = link(
  "https://github.com/jgm/pandoc"
)[#text(fill:blue)[GitHub]]

#a_013 \
Source: WeChat

Pandoc 是一个开源的文件转换工具，可以用它把 Markdown 转成 Word，也可以把 Word 转成 
Markdown，把网页 HTML 转成 Markdown，把 Markdown 转成 PDF、PPTX、EPUB，或者处理 CSV、LaTeX、Org、Jupyter Notebook 等格式。

= 2026/05/26 - Open-Source OCR Projects

#let a_014 = link(
  "https://github.com/RapidAI/RapidOCR"
)[#text(fill:blue)[RapidOCR]]

#let a_015 = link(
  "https://github.com/JaidedAI/EasyOCR"
)[#text(fill:blue)[EasyOCR]]

#let a_016 = link(
  "https://github.com/VikParuchuri/surya"
)[#text(fill:blue)[Surya]]

= 2026/05/26 - Build Knowledge Web Skill
#let a_017 = link(
  "https://github.com/cyj4578/chen-skillshub/blob/main/chen-knowledge-web/SKILL.md"
)[#text(fill:blue)[GitHub]]

#a_017 \
Source: WeChat

This is a skill to build a knowledge web.

= 2026/05/26 - Tecent Marvis

#let a_018 = link(
  "https://marvis.qq.com/"
)[#text(fill: blue)[URL]]

#a_018 \
Source: WeChat

It is Tecent's solution to "AI Operating System". We may want to install it.

= 2026/05/27 - Claude Code Guidelines

#let a_019 = link(
  "https://arps18.github.io/posts/claude-code-mastery/"
)[#text(fill:blue)[URL]]

#a_019 \
Source: Hacker News

Very important document. Need to read!

= 2026/05/27 - Constract Review
#let a_020 = link(
  "https://mp.weixin.qq.com/s/hNqb7wDxvjS7zWzsW89D6A"
)[#text(fill: blue)[URL]]

#a_020 \
Source WeChat

This link has a few skills, including a contract review skill.
