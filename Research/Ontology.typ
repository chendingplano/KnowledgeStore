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
  [2026/04/23], [Ontology, file name: Ontology.typ],
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
    "Ontology"
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
  logical_name: "Ontology",
  file_id: "2026042702",
  file_type: "Typst",
  content_type: "Research",
  doc_time: "2026/04/27",
  keywords: ["Ontology", "Knowledge Graph", "Knowledge Base"],
)

#let a_001 = link(
  "https://github.com/H2020-OpenModel/OntoFlow"
)[#text(fill: blue)[OntoFlow]]

#let ref_ontology_vs_semantic_layer = link(
  "https://lowhangingdata.com/article/ontology-vs-semantic-layer/"
)[#text(fill:blue)[Ontology vs Semantic Layer]]
= Ontology

== Ontology vs Semantic Layer
#ref_ontology_vs_semantic_layer is a good article. It explains what ontology and semantic
layer are; their differences; and how they work together.

https://lowhangingdata.com/ focuses on data analysis. Read its introduction and the 'about' page
for more information.

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

= Reviews

== Open-Source: OntoFlow

#a_001 \
Date: 2026/04/27

== OLOGS: A Categorical Framework for Knowledge Representation
#let a_002 = link(
  "https://arxiv.org/pdf/1102.1889"
)[#text(fill:blue)[URL]]

#a_002 \
Source: WeChat

=== Concepts
==== Category

A category is a mathematical structure that appears much like a directed
graph: it consists of objects (nodes) and arrows (edges) between them (a graph).
The feature of categories that distinguishes them from graphs is
the ability to declare an equivalence relation on the set of paths.

*Objects*\
This is the node. The main differences are that a node may have parameters.
```text
Node A: "a pair (w, m) where w is a woman and m is a man" is a node. The node has
two parameters: `w` and `m`. In general, nodes do have attributes in graphs.
```

Then we can ask "Is w a man or woman?". In Olog, we can draw a relation:

```text
Node B: a woman
Node C: m man

Edge: Node A 'w' B
Edge: Node A 'm' C
```

We can further derive:
```text
Node D: "a person"

D has-as-mother C

```

*Arrows*\
This is the edge.

*Types*\
A type is an abstract concept (nodes in graphs). It defines a class of things instead of individual 
instances. `an automobile` is a type. It represents automobiles of any kind.

Examples:
```text
a main
an automobile
a pair (a, w), where w is a woman and a is an automobile
a pair (a, w) where w is a woman and a is a blue automobile owned by w
```

*Types with Compound Structures*\
```text
a man and a woman
a food f and a child c such that c ate all of f
a triple (p, a, j) where p is a paper, a is an author of p, and j is a journal in which p was published
```

==== Aspects
An aspect of a thing x is a way of viewing it. Below is a view:
```text
'a woman --is--> 'a person'
```

Aspects are functional relationships. Suppose we wish to say that a thing
classified as X has an aspect f whose result set is Y. This means there is
a functional relationship called f between X and Y. X is the domain of 
definition for the aspect of, and Y the set of result values for f.

Rules:
- Each arrow must emanate from a dot (instance) in X and point to a dot (instance) in Y
- Each dot in X must have precise one arrow emanating from it

*Invalid Aspects*\
Aspects that violate the above two rules are invalid aspects.

```text
'a person --has-->'a child'
```

This is an invalid aspect because not all persons (dots in X) has one and only one child (dots in Y).

It appears that `aspect` is a formal way of `edges`. Note that edges are kind of vague.
When we say "chunk has metric", it connects a chunk to a metric. From `aspect` point of view,
this is an invalid aspect because not all chunks have metrics. I am not sure whether `aspect`
is truly useful.

==== Facts
A `Fact` is a derived relation. This is quite counterintuitive. We can declare "Person A is a woman"
as a fact. But in Olog, we need to list "Person A has-as-parents a pair (w, m) where w is a woman
and m is a man", then we can declare "Person A has-as-mother is a woman".

= References
[1] #a_001 \
[2] #ref_ontology_vs_semantic_layer \
