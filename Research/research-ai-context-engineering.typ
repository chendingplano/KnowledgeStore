#import "@preview/diagraph:0.3.6"
#import "@preview/oxdraw:0.1.0": *
#import "/Reviews/Review-OntoKG.typ": onto_kg_review

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
    "Research - Context Engineering"
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
  logical_name: "research-ai-context-engineering",
  file_id: "2026091801",
  source: "",
  content_type: "research",
  document_date: "2026/09/18",
  keywords: [Context Engineering],
)

= Overview
There should be the following types of context (@context-engineering):
1. Instructions: instructions define rules, goals, and boundaries. They tell
   an agent what its job is and what it should not do. For example, an incident
   investigation agent may be instructed to gather evidence, summarize findings,
   and avoid triggering production actions.
2. Knowledge: knowledge includes documents, architecture diagrams, service
   metadata, domain data, repositories, and runbooks. This is factual material
   an agent needs to understand the environment.
3. Memory: memory holds session logs, previous decisions, persistent state,
   user preferences, etc. It lets an agent maintain continuity across multi-step
   workflows rather than treating every action as a completely new task.
4. Examples: examples provide short demonstrations and reference patterns.
   They show an agent what a useful output or a correct workflow looks like.
   This is especially useful when a task needs a consistent format.
5. Tools: tools include APIs, scripts, CI systems, and external services.
   Tools turn an agent from a chat interface into something that can retrieve
   current data and execute approved tasks.
6. Guardrails: guardrails are the hard constraints: safety rules, policy
   requirements, and approval gates. They are critical when an agent can do 
   more than just answer a question.
7. Service Catalog: a service catalog can hold details about the services
   the system provides, include:
   - Service name and identifier
   - Environment, such as staging or production
   - Owning team
   - Repository association
   - Runbook URL
   - Slak channel, Wechat group, etc.
   - Service tier and visibility
   - Observability links
   - on-call rotation status

#onto_kg_review()

Instructions, knowledge, memory and guardrails are relatively static.
Examples, tools are dynamic because they can change with the workflow, 
the service and the current situation

#bibliography("/references/references.bib")
