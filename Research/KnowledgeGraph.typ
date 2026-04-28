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

*Change History*
#table(
  columns: 2,
  align: left,
  [Date], [Remarks],
  [2026/04/23], [Knowledge Graph, file name: KnoweledgeGraph.typ],
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
    "Knowledge Graph"
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
  created: "2026/04/27",
  logical_name: "Knowledge Graph",
  file_id: "2026042701",
  file_type: "Typst",
  content_type: "Research",
  doc_time: "2026/04/27",
  keywords: ["Knowledge Graph", "Knowledge Base", "Graph Entity", "Graph Relation", "Entity Relation"],
)

= Knowledge Graph

*Are Knowledge Graphs Useful*

My answer is YES or NO, and mostly not much. It is useful to 'programs', or any object that does not 
understand natural languages. For instance, if "Mary is John's wife" is a relation, if we ask a program
"Is John Mary's husband?", it will probably answer "I don't know". The reason? Because programs can't
understand natural languages. If we ask an LLM, it can easily tell the relations between John and Mary.

I think most people did not think twice about who are going to use knowledge graphs before diving into
building them.

Can we add rules to programs so that programs can reason? Absolutely YES. For a small set of datasets,
rules may be defined. But for an open model, it will be difficult. 

So my answer to the question "Are knowledge graphs useful?" is yes if and only if we have a 'program'
that can reason on knowledge graphs.

== Types of Relations
#table(
  columns: 2,
  align: left,
  [Relation], [Description],
  [ISA], [Is an instance of, such as "A is a Person"],
  [AKO], [kind-of],
  [AMO], [Membership],
  [is-parent], [parent-child relation],
  [is-child], [`A is a child of B`],
)

== Ontology Rules

[[def:Ontology Rules, Rules]]

Entity relations are instances of 'a class', while Rules are the 'class'. 

=== Rule-001 If ... Then ...

*Example*
```text
If A is B's wife, B is A's husband
If A is an investor of B, A works for C, C is a company, then C invests B
```

=== Rule-002 Entity Class
Entity classes define a class and entities are instances of entity classes.
Rules are often defined on entity classes in ontology instead of on individual entities.
In most graphs, the class-instance relations are expressed explicitly, such as
"Mockingbird is a Bird". In ontology, entity class is an attribute of entities.

=== Rule-003 Relation Class
Relation Class defines a category of entity relations (relations for short). Relations in knowledge graphs are
instances of Relation Class. 

=== Rule-004 Relation Hierarchy


== Reviews

