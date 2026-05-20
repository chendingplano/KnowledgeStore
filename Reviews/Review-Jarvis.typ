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
    "Review - Jarvis"
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
  Source: "https://github.com/microsoft/JARVIS",
  ArtifactType: "Open-Source Project",
  DocumentDate: "2026/05/21",
  Keywords: [Agentic System, Harness, Jarvis],
)

= Overview
[Microsoft JARVIS GitHub repository](https://github.com/microsoft/JARVIS?utm_source=chatgpt.com) (closely associated with the HuggingGPT paper) is an early and influential open-source implementation of the “LLM as orchestrator” pattern that later became foundational in agentic AI systems. Its core idea is straightforward but powerful: instead of expecting one large language model to directly solve every task, use the LLM as a controller that understands the user’s intent, decomposes the request into subtasks, selects specialized AI models for each subtask, executes them, and then synthesizes the final response. In the original design, ChatGPT serves as the planner/reasoner, while models from Hugging Face act as expert executors for vision, speech, NLP, generation, and multimodal tasks. ([GitHub][1])

Architecturally, JARVIS follows a four-stage pipeline: *task planning → model selection → task execution → response generation*. For example, if a user asks “Generate an image in the pose of person A but styled like image B,” the LLM first converts that request into a structured execution graph, identifies required capabilities such as pose estimation, image captioning, and image synthesis, maps those tasks to concrete models, executes them in dependency order, and merges outputs into a coherent result. This is effectively a primitive workflow engine for AI tools, where natural language becomes the programming interface. If your interest is agent systems, this is one of the clearest early examples of tool orchestration rather than pure conversational AI. ([GitHub][1])

From a systems perspective, JARVIS is important historically because it demonstrated that a general-purpose AI assistant could be assembled from modular components instead of requiring a monolithic AGI model. Many concepts now common in systems like Codex agents, Claude Code workflows, LangChain agents, AutoGen-style orchestration, and tool-using copilots were already visible here: capability routing, dependency-aware task graphs, intermediate representations, model registry lookup, and executor abstraction. However, the implementation reflects its era. It depends heavily on explicit model descriptions, remote Hugging Face endpoints or heavyweight local deployments, and a relatively brittle orchestration layer compared with modern agent frameworks that use better planning, retries, memory, and tool schemas.

Practically, JARVIS is more of a research prototype than a production-ready framework by today’s 
standards. Its infrastructure assumptions are heavy (significant GPU/RAM requirements for full 
local deployment), its original LLM integration predates modern function calling/tool APIs, 
and the model ecosystem it targets has evolved substantially. But conceptually, it remains highly 
relevant because it established a key design pattern: *LLMs are not just generators of 
text—they can serve as planners that coordinate external computational tools.* For SemOS / explorable-knowledge 
interests, the closest analogy is that JARVIS treats Hugging Face models as an external capability 
graph; SemOS could similarly treat knowledge assets, retrievers, graph traversals, summarizers, and 
analyzers as callable tools under an LLM-controlled orchestration layer.

== Harness
Jarvis shows the early stage shape of Agentic Harness:
- Task Planning
- Model Selection
- Task Execution
- Answer Generation
- and many more modules

The main departure is that instead of developing a powerful AGI (all-inclusive) model, it uses LLMs 
as controllers or planners. Understand user request, design tasks (separation of concerns), dedicate
tasks to specialized models (distribution of responsibility).

Developing AGI may be the ultimate goal. Given enough time, humans may eventually achieve the goal
(it may or may not, at least humans have not yet, even through tens of millions of years evolution).
A deeper question is: is AGI the right direction? If yes, why don't universities have just one
department: Superman Department, instead of many, such as Chemistry, Mechanics, Computer Science,
Eletrical Engineering, etc.

[1]: https://github.com/microsoft/JARVIS?utm_source=chatgpt.com "GitHub - microsoft/JARVIS: JARVIS, a system to connect LLMs with ML community. Paper: https://arxiv.org/pdf/2303.17580.pdf · GitHub"

