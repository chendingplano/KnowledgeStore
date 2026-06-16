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
  [2026/05/22], [Knowledge Wiki, file name: KnoweledgeWiki.typ],
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
    "Knowledge Wiki"
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
  logical_name: "Knowledge Wiki",
  file_id: "2026042701",
  file_type: "Typst",
  content_type: "Research",
  doc_time: "2026/04/27",
  keywords: ["Knowledge Graph", "Knowledge Wiki", Knowledge Base", "Graph Entity", "Graph Relation", "Entity Relation"],
)

= Knowledge Wiki

Knowledge Wiki (K-Wiki) is closely related to knowledge graphs. Before we introduce knowledge wiki,
we need to answer the question: *Are knowledge graphs useful?*.

My answer is YES or NO, and mostly not much. It is useful to 'programs', or any object that does not 
understand natural languages. For instance, if "Mary is John's wife" is a relation, if we ask a program
"Is John Mary's husband?", it will probably answer "I don't know". The reason? Because programs can't
understand natural languages. If we ask an LLM, it can easily tell the relations between John and Mary.

I think most people did not think twice about who are going to use knowledge graphs
in general before diving into building them.

So my answer to the question is yes if and only if we have a 'program' that can reason over it.

Knowledge Wiki is similar to knowledge graphs:
- There are nodes and connections (edges)
- Fully connected

Nodes in K-Wiki are quite different. 

== Artifacts
SemOS supports the following types of artifacts:

#table(
  columns:3,
  align: left,
  [Name],                   [Type], [Explanation],
  [Summaries],              [basic artifact], [],
  [Topics],                 [basic artifact], [],
  [Metrics],                [basic artifact], [],
  [Semantic Projections],   [basic artifact], [],
  [Compliance Provisions],  [basic artifact], [],
  [Inventory Items],        [basic artifact], [],
  [Entities],               [basic artifact], [],
  [Relations],              [basic artifact], [],
  [Scenes],                 [basic artifact], [],
  [Facts (TBD)],            [basic artifact], [],
  [References (TBD)],       [basic artifact], [],
  [Artifact Categories],    [categories],     []
)

== Connections
#table(
  columns: 3,
  align: left,
  [Source], [Target], [Mechanism],
  [Document], [chunks], [sharing lines],
  [chunks], [basic artifacts], [sharing lines],
  [Document and semantic projections
  [Chunks and summaries, semantic projections
)

== Indexing
=== Keyword Index
This is currently handled by PostgreSQL full-text search.
Each artifact type stores in a table and has a full-text search index.
In addition, it has a full-text search index for all artifacts,
partitioned by artifact types.

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
  [2026/05/22], [Knowledge Wiki, file name: KnoweledgeWiki.typ],
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
    "Knowledge Wiki"
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
  logical_name: "Knowledge Wiki",
  file_id: "2026042701",
  file_type: "Typst",
  content_type: "Research",
  doc_time: "2026/04/27",
  keywords: ["Knowledge Graph", "Knowledge Wiki", Knowledge Base", "Graph Entity", "Graph Relation", "Entity Relation"],
)

= Knowledge Wiki

== Nodes
#table(
  columns: 3,
  align: left,
  [Name], [Type], [Purpose],
  [Document], [User Input], [source of true],
  [Chunk], [static generated], [the base to extract artifacts],
  [Summary], [LLM generated], [search, context],
  [Semantic Projection], [LLM generated], [search, context],
  [Topic], [LLM generated], [information],
  [Scene Blocks], [LLM generated], [information],
  [Metric], [LLM generated], [information],
  [Compliance Provisions], [LLM generated], [information],
  [Inventory Items], [LLM generated], [Information],
  [Entity], [LLM generated], [Information],
  [Relation], [LLM generated], [Information],
  [Artifact Category], [LLM generated], [categorize and organize artifact],
  [Entity Name], [LLM synthesized], [categorize and organize entities],
  [Relation Predicate], [LLM synthesized], [categorize and organize relation predicates],
)
== Connections

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

== Indexing

=== Artifact IDs

Artifacts are identified by:
```text
    <record_id>_<artifact_type>_<seqno>
```
where:
- `<record_id>`: it is `kb.inputs.id`
- `<artifact_type>`: it identifies the type of the artifact, such as 'summary', 'metric', etc.
- `<seqno>`: it is a sequence number relative to record ID and artifact type, starting from 1.

We can normalize `<artifact_type>` to, say, three letter words, such as:
- sum: summaries
- mtc: metrics
- scb: scene blocks
- sem: semantic objects
- pvs: compliance provisions
- ref: references
- quo: quotations
- kwd: keywords
- and so on

=== Artifact Docids

Artifact Docids are u64. It uniquely identifies artifacts globally.
```text
  Byte 7-4: Record ID (total 4 billions)
  Byte 3-2: Artifact type (total 65535 types)
  Byte 1-0: Sequence Number (total 65535 objects)
```

This schema is good enough for most artifacts:
- There can be up to 4 billion inputs
- Each input may have up to 65535 types of artifacts
- Each artifact can have up to 65535 instances

For the time being, we will use artifact IDs.

=== Keyword Index
Semantic objects are clustered by keywords. Internally, all keywords are English. There is a map
that maps English keywords to keywords in a specific language, such as Chinese.

Keyword indexes are stored in files under KEYWORD_DIR and in PostgreSQL. The file-based
keyword index is for LLM exploration and the PostgreSQL for BM25 search.

=== Category Index

Categories are expressed as category paths:
```text
    domain_subdomain_category_...
```

Category paths are mapped to file paths. Their root directory is CATEGORY_DIR.

Category indexes are stored in files. It is intented to be used by LLMs to explore the artifacts.

=== Relation Index

An artifact can connect to other artifacts:
- By keyword + artifact type
- By category + artifact type
- By entity

== Reviews
