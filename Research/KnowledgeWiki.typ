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

= Reviews

== Google Open Knowledge Format (OKF)
OKF ([1]) is an open, human- and agent-friendly format for representing knowledge — the metadata, 
context, and curated insight that surrounds data and systems. It is designed to be authored by people, 
generated by agents, exchanged across organizations, and consumed by both.

*Terminology*
- Knowledge Bundle: similar to a knowledgebase
- Concept: a single unit of knowledge within a bundle. Represented as one markdown document.
- Concept ID: the path of the concept's file within the bundle, such as `tables/users.md`
- Frontmatter: YAML metadata block delimited by `---`
- Body: Everything in the file after the frontmatter
- Link: a standard markdown link from one concept to another, used to express
  relations beyond the implicit parent/child hierarchy
- Citation: a link from a concept to an external source that supports a claim in the body.

*Bundle Structure*
```text
path/to/bundle/
├── index.md                      # Optional. Directory listing for progressive disclosure.
├── log.md                        # Optional. Chronological history of updates.
├── <concept>.md                  # A concept at the bundle root.
├── <concept>.md
├── ...
└── <subdirectory>/               # Subdirectories organize concepts into groups.
    ├── index.md
    ├── <concept>.md
    ├── <concept>.md
    ├── ...
    └── <subdirectory>/
        └── …
```

*Frontmatter*
```text
---
type: <Type name>                  # REQUIRED
title: <Optional display name>
description: <Optional one-line summary>
resource: <Optional canonical URI for the underlying asset>
tags: [<tag>, <tag>, …]            # Optional
timestamp: <ISO 8601 datetime>     # Optional last-modified time
# … other producer-defined key/value pairs
---
```

*`<concept>.md` Example*
```text
---
type: BigQuery Table
title: Customer Orders
description: One row per completed customer order across all channels.
resource: https://console.cloud.google.com/bigquery?p=acme&d=sales&t=orders
tags: [sales, orders, revenue]
timestamp: 2026-05-28T14:30:00Z
---

# Schema

| Column        | Type      | Description                              |
|---------------|-----------|------------------------------------------|
| `order_id`    | STRING    | Globally unique order identifier.        |
| `customer_id` | STRING    | Foreign key into [customers](/tables/customers.md). |
| `total_usd`   | NUMERIC   | Order total in US dollars.               |
| `placed_at`   | TIMESTAMP | When the customer submitted the order.   |

# Joins

Joined with [customers](/tables/customers.md) on `customer_id`.

# Citations

[1] [BigQuery table schema](https://console.cloud.google.com/bigquery?p=acme&d=sales&t=orders)

```

*Index Files*

An index.md file MAY appear in any directory, including the bundle root. It 
enumerates the directory's contents to support progressive disclosure — letting a 
human or agent see what is available before opening individual documents.

```text
# Section / Group Heading

* [Title 1](relative-url-1) - short description of item 1
* [Title 2](relative-url-2) - short description of item 2

# Another Section

* [Subdirectory](subdir/) - short description of the subdirectory
```

*Log Files*
```text
# Directory Update Log

## 2026-05-22
* **Update**: Added new BigQuery table reference for [Customer Metrics](/tables/customer-metrics.md).
* **Creation**: Established the [Dataplex Playbook](/playbooks/dataplex.md).

## 2026-05-15
* **Initialization**: Created foundational directory structure.
* **Update**: Added progressive-disclosure guidelines to the root [index](/index.md).
```

*Citations*
```text
# Citations

[1] [BigQuery public dataset announcement](https://cloud.google.com/blog/products/data-analytics/...)
[2] [Internal data quality runbook](https://wiki.acme.internal/data/quality)
```

== SemOS and OKF
There are two repositories in SemOS:
- ARTIFACT_DIR
- ARTIFACT_WEB_DIR

ARTIFACT_DIR stores the artifacts based on records. ARTIFACT_WEB_DIR stores artifact based
on category hierarchy.

=== `index.md`
`index.md` in a subdirectory:
```md
## Relations
| Subject | Predicate | Object | Relation ID |
|---------|-----------|--------|-------------|
| xxx | xxx | xxx | 416_rel_12 |
| xxx | xxx | xxx | 416_rel_12 |
...

## Entities
File Name: `entities.md`
* entity-001 (416_ent_12)
* ...
...

## Scene Objects
...

## Summaries
...

## Semantic Projections
...

## Inventory Items
...

** Compliance Provisions
...

## Topics
...

```

=== Relations
Currently, relations are expressed in JSON:
```text
  {
    "categories": [
      "适用性"
    ],
    "confidence": 0.99,
    "connected_artifacts": {
      "chunks": [
        "416_chk_1"
      ],
      "entities": [
        "416_ent_1",
        "416_ent_157"
      ],
      "inv_items": [],
      "metrics": [],
      "provisions": [
        "416_prv_416_prv_2"
      ],
      "scenes": [],
      "semantic_projects": [
        "416_smp_1"
      ],
      "summaries": [
        "416_sum_0_0001"
      ],
      "topics": [
        "416_tpc_1",
        "416_tpc_3"
      ]
    },
    "desc_text": "该标准适用于农村生活垃圾分类处理",
    "desc_text_en": "",
    "ext_info": {
      "chunk_seq_no": null,
      "language": "zh",
      "schema_version": "1"
    },
    "keywords": [
      "农村生活垃圾分类处理规范",
      "农村生活垃圾分类处理"
    ],
    "keywords_en": [],
    "line_spans": [
      "1",
      "11",
      "14"
    ],
    "model_name": "deepseek-v4-flash",
    "object": "农村生活垃圾分类处理",
    "object_en": "",
    "object_entity_id": "416_ent_157",
    "predicate": "适用于",
    "predicate_en": "",
    "prompt_name": "prompt-extract-relations-v2.md",
    "relation_id": "416_rel_1",
    "search_document": "农村生活垃圾分类处理规范  适用于  农村生活垃圾分类处理  该标准适用于农村生活垃圾分类处理  农村生活垃圾分类处理规范 农村生活垃圾分类处理",
    "subject": "农村生活垃圾分类处理规范",
    "subject_en": "",
    "subject_entity_id": "416_ent_1"
  },
```

Change it to markdown:
```md
---
type: scene-blocks
title: applicable
description: 该标准适用于农村生活垃圾分类处理
resource: record_id=416
timestamp: 2026-05-28T14:30:00Z
---

# relation
* subject: 农村生活垃圾分类处理规范
* predicate: 适用于
* object: 农村生活垃圾分类处理
* relation_id: 416_rel_1
* subject_entity_id: 416_ent_1
* object_entity_id: 416_ent_157


# info
* categories: 适用性
* chunk_seq_no: null
* language": zh
* schema_version: 1
* model_name: deepseek-v4-flash
* prompt_name: prompt-extract-relations-v2.md
* search_document: 农村生活垃圾分类处理规范  适用于  农村生活垃圾分类处理  该标准适用于农村生活垃圾分类处理  农村生活垃圾分类处理规范 农村生活垃圾分类处理

# keywords
* 农村生活垃圾分类处理规范
* 农村生活垃圾分类处理

# line spans
1, 11, 14
```

=== ARTIFACT_WEB_DIR
Its structure is:
```text
├── index.md
├── log.md
├── <buddle_01>/
├── <buddle_02>/
├── <buddle_02>/
├── ...
```

`index.md` describes the buddles in this directory.

`log.md` is the change log
```text
# 2026-06-19
* **Create**: Added buddle-abc
* **Update**: Batch processed documents
* **Freeze**: Freezes xxx
* **Suspend**: suspended bundle-abc
* **Resume**: resumed buddle-abc
* **Drop**: dropped buddle-abc
```

= References
[1] Open Knowledge Format
https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md

