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
    "Tool Design"
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
  created: "2026/04/12",
  logical_name: "Tool Design",
  file_type: "Typst",
  file_id: "2026041201-anthropic-tool-design",
  keywords: ["Tool", "Tool Design", "Anthropic"],
  source_url: "https://claude.com/blog/seeing-like-an-agent",
  feed: "Wechat"
)

#let a_context_exploration = link(
  "Context Exploration"
)[#text(fill: blue)[Context Exploration]]

= How Anthropic Design Tools

- One of the hardest parts about building an agent harness is constructing its tools.

Tool primitives:
- bash
- skills
- code execution

Thinking:
- Do you give it one general-purpose tool like bash or code execution? Or fifty specialized tools, one for each use case?
- When to create a tool? When to remove one?
- You want to give agents tools that are shaped to its own abilities.
- How do you know the 'abilities'? You pay attention, read its outputs, experiment. 
- You learn to see like an agent.

*AskUserQuestion* Tool (Elicitation)

== Search Tool [[context exploration]]

The most consequential tools they have built are the ones that let Claude find its own context!
This is extremely important.

But the question is: how to let Claude find its own context?

Initially, they used RAG. The problem is that it requires indexing and setup and could be
fragile across a host of different environments. Most importantly, Claude was given
this context instead of finding the context itself.

To let Claude find the context itself: `grep` and the similar facilities. More importantly,
by giving Claude a grep tool, it becomes increasingly good at building its context.

This becomes even more important when Skills use progressive disclosure, which allows
agents to incrementally discover relevant context through [[context exploration]].

== Progressive Disclosure

*Another Dimension of Context Exploration*

Tools like 'grep', 'find', 'glob', etc. are good at finding information. This is just one
dimension of context explorability. 

Another dimension is through the use of skills. Claude can read skill files. Skill files
may reference other files, which can be any type of files, including skill files, too.
The common use of skills is to add more search capabilities to Claude like giving it 
instructions on how to use an API or query a database.

"Over the course of a year, Claude went from not really being able to build its own context
to being able to do nested search across several layers of files to find the exact context
it needed.

Progressive disclosure is now a common technique we use to add new functionality without
adding a tool."

== Subagent

Users sometimes ask questions about Claude Code. Anthropic does have documents about 
Claude Code. One way to add the ability is to add something in every prompt to remind
the model how to handle Claude Code related questions. The drawbacks of this approach
are apparent.

Anthropic decided to use a subagent: *Claude Code Guide*. The subagent does the doc-searching
in its own context, follows detailed instructions on how to search and what to extract,
and hands back only the answer. The main agent's context stays clearn.

When to use subagent? Claude Code Guide is a very common scenario where subagents can be
very helpful: do the search in an isolated environment and give back the results only.
The main agent's context kepps clean.

In general, when an agent want to do something that is not trivial, requires extensive
searching, which is not directly related to the main (or parent) agent, a subagent can
be the rescue.
