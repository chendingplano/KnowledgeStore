#import "@preview/diagraph:0.3.6"
#import "@preview/oxdraw:0.1.0": *
#import "../Reviews/Review-ai-laya.typ": ref_review_laya
#import "../Reviews/review-knowhere.typ": ref_review_knowhere

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
    "Knowledge"
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
  logical_name: "semos-knowledge",
  file_id: "semos-knowledge",
  source: "",
  content_type: "SemOs",
  document_date: "2026/10/14",
  keywords: [Knowledge, what is knowledge],
)

= Introduction
This chapter focuses on:
- What exact is knowledge
- Knowledge and semantics
- Knowledge mining
- Knowledge and applications

= Knowledge

*Knowledge and Facts*

Facts are not knowledge. 

= Facts

- Facts are normally buried in unstructured data
- The same fact can be expressed differently
- Facts can be stored, structrually, in different formats
- Facts can be expressed as triples
- Most facts do not have names
- Fact mining is the process of extract facts from raw data

== Knowledge and Semantics

The most important question about semantics is how to represent semantics.
There is no silver-bullet method of representing semantics. 

Below are the methods of representing semantics:
- Vector
- Keyword
- Tag
- Topic
- Category
- Graph
- Rules

*Vector View*

LLMs use vectors to represent semantics. Content with similar semantics share 
similar vectors. The semantic similarity can be calculated by their vectors
cosine or dot-product. The importance and limitations are obvious.

*Keyword View*

Keywords can relate content with similar semantics. 

*Name View*

Names can be semantic objects, such as device names, human names, company
names, object names, etc. 

Names themselves do not have any meaning. `Human Names` does have. They
are names of humans. The semantics is identifying persons. If one says
"xxx is the the king of Qing dynasty", we instantly know `xxx` is not
alive now; he/she was born and died on some days.

When computers (or LLMs) see human names, they understand they represent
persons, having date of birth, which may be known or unknown.


*Tags*

*Topics*

*Categories*

*Graphs*

== Knowledge Mining

Knowledge is normally buried in unstructured content. Knowledge mining
extracts/discovers knowledge from the raw data.

Knowledge mining requires deep understanding of knowledge.
One form of knowledge is to set a goal and collect all the information
that may affect the goal.

In [review-rag-MatSeek], it extracts 

= Ontology - Knowledge Models

Below is from (@ref-from-data-eng-2-knowledge-eng)
- Palantir: Knowledge + Actions 
- Semantic View: such as Snowflake Semantic View
  focus on extracting semantics, turn unstructured data into structured
  knowledge, facts, properties, classes, instances, relations
- Apache Ossie: from dbt, Snowflake, focus on the openness of knowledge
  system, separating ontology and semantics, mapping between them.
  Ontology defines the model, mapping combines knowledge model to
  businesses. Ontology stays relatively stable, knowledge is more
  dynamic.
- Genie Ontology: combines ontology and semantics. There is no clear
  boundary between ontology and knowledge. It may be closer to 
  specific implementations, closer to businesses.
- Agent Memory: unstructured text is also a form of knowledge.
  When users interact with agents, users are constantly outputs
  knowledge, so do agents. These are very important sources of
  knowledge.

= Knowledge Sources

- Structured data, such as databases, spreadsheets, JSON documents,
  XML documents, etc.
- Dialogs between users and agents
- Unstructured content, such as documents
- Videos
- Audios
- Social medias
- Websites

= Knowledge, Experiences, Judgements

Experiences and judgements can be the most difficult form of knowledge.

= Knowledge in Production

- "Agents in Dev, Artifacts in Prod" (@ref-from-data-eng-2-knowledge-eng)
- Humans in the loop: LLMs extract artifacts, humans review them
- Knowledge systems need continuous maintenance. New knowledge comes in
  every day; existing knowledge may no longer be valid, may be
  updated by new knowledge
- Categorize/classify knowledge based on domains, purpose, freshness, etc.
- Loop: facts => relations => knowledge => facts

#bibliography("../references/references.bib")
