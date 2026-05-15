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
    "Review - OpenMetadata"
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
  Source: "https://github.com/open-metadata/openmetadata",
  ArtifactType: "Open-Source Project Review",
  PublishDate: "2026/05/14",
  Keywords: [Metadata, Ontology, Knowledge Engineering, Metadata Operating System]
)

= Overview
[[OpenMetadata]](https://open-metadata.org?utm_source=chatgpt.com) (GitHub repo: [[open-metadata, 
OpenMetadata]](https://github.com/open-metadata/OpenMetadata?utm_source=chatgpt.com)) is an open-source 
metadata management platform aimed at solving a common enterprise data problem: metadata fragmentation across warehouses, pipelines, dashboards, ML systems, and governance tooling. Conceptually, it sits at the intersection of data catalog, lineage platform, governance hub, and observability system. Instead of treating metadata as passive documentation, OpenMetadata builds a central metadata graph that models datasets, pipelines, dashboards, users, services, quality signals, lineage relationships, and governance objects in one system. ([GitHub][1])

Architecturally, OpenMetadata is more than a UI catalog. Its core design includes metadata schemas (the canonical data model), a central metadata store (graph-oriented logical model), APIs for metadata production/consumption, and an ingestion framework that continuously pulls metadata from external systems. This means it behaves like infrastructure rather than a documentation website. It supports ingestion from modern data ecosystems—data warehouses, databases, orchestration systems, BI tools, messaging platforms, etc.—so instead of manually curating metadata, teams can automate collection and enrichment. From an engineering perspective, think of it as a metadata operating system for the modern data stack. ([GitHub][1])

Feature-wise, OpenMetadata combines several traditionally separate product categories. It offers data discovery (searchable catalog of assets), lineage visualization (including column-level lineage), governance (ownership, classifications, glossary terms, domains, policies), data quality (profiling, tests, test suites), observability (freshness, volume, anomalies), collaboration (comments, tasks, conversations), and KPI/reporting around metadata health. That breadth is one of its defining characteristics: unlike narrower catalogs that only help users find tables, OpenMetadata tries to become the control plane for metadata-driven operations. If your mental model includes systems like DataHub, Atlan, Collibra, or Apache Atlas, OpenMetadata belongs in that design space, with a stronger open-source/platform engineering orientation. ([GitHub][1])

From LLM-friendly knowledge systems / explorable knowledge infrastructure, the most interesting part is that 
OpenMetadata is fundamentally structured knowledge, not document retrieval. It builds explicit typed entities 
and relationships rather than relying on chunk embeddings. That makes it much closer to a curated enterprise 
knowledge graph than a RAG vector store. However, it is optimized for enterprise data assets, not arbitrary 
document corpora like standards/specifications. It builds on the idea of letting LLMs exploring knowledge 
natively. It offers relevant ideas—entity modeling, lineage graphs, metadata schemas, ownership/governance 
semantics, ingestion pipelines. It is for corpus that can be normalized into strongly typed metadata entities 
rather than free-form documents.

*OpenMetadata is an enterprise metadata platform / data control plane, not a general-purpose second-brain or 
document intelligence system* in the sense that it focuses on metadata, not the corpus itself.
The ideas of *knowledge graph structure + ingestion architecture + governed metadata APIs* is inspiring
is highly relevant to SemOS. It is, however, adjacent rather than directly applicable to a filesystem-native 
explorable knowledge base for technical documents.

== Main Features
- Discovery
- Lineage
- Observability
- Quality
- Collaboration
- Governance
- Scheduling
- Database
- Connectors

== Example
Example: use OpenMetadata to build a data-asset knowledge graph.

Suppose we have:

```text
Postgres table: raw.orders
dbt model: mart.customer_lifetime_value
Dashboard: Sales Overview
Business term: Customer Lifetime Value
Owner: data-team
```

In OpenMetadata, these become graph nodes:

```text
[raw.orders] ──feeds──> [mart.customer_lifetime_value] ──used_by──> [Sales Overview Dashboard]
       │                  │
       │                  ├──has_glossary_term──> [Customer Lifetime Value]
       │                  └──owned_by──> [data-team]
```

How you create it:

1. *Ingest technical metadata*
   Connect OpenMetadata to Postgres, Snowflake, BigQuery, dbt, Airflow, Tableau, etc. It automatically creates entities such as databases, schemas, tables, columns, pipelines, dashboards, and services.

2. *Add semantic metadata*
   Create glossary terms such as `customer`, `order`, `revenue`, `customer_lifetime_value`, 
   then attach them to tables/columns. OpenMetadata models glossaries and glossary terms as 
   first-class governance entities. ([OpenMetadata Documentation][3])

3. *Add lineage edges*
   Define that `raw.orders` flows into `mart.customer_lifetime_value`, and that the model 
   feeds the dashboard. OpenMetadata’s Lineage API manages lineage relationships between 
   entities and can include column-level mappings. ([OpenMetadata Documentation][4])

4. *Query/explore the graph*
   Then you can answer questions like:

```text
What dashboards depend on raw.orders?
Who owns mart.customer_lifetime_value?
Which columns define Customer Lifetime Value?
If I change orders.total_amount, what downstream assets break?
```

For SemOS/document-KG context, the analogy would be:

```text
[standard document]
   ├──contains──> [section]
   ├──defines──> [term]
   ├──contains──> [requirement]
   ├──references──> [other standard]
   └──has_topic──> [vaccine cold chain monitoring]
```

But OpenMetadata is best when the graph is about *data assets*. For standards/documents, 
we would likely borrow the pattern—typed entities, relationships, glossary, lineage—but 
implement your own domain model.

*Thoughts - Ontology Objects - AgenticBeans*

In this example, "Customer" is an ontology object (or an object in the ontology) or a
AgenticBean (short for Knowledge Bean).

```text
customer
   ├──storage──> [@customer-storage]
   ├──description──> ['the-description']

customer-storage
   ├──type──> ['database table']
   ├──database──> [@postgreSQL]
   ├──db-name──> ['business']
   ├──table-name──> ['customers']
   ├──table-schema──> [json:{...}]
   ├──table-migration──> [files:{...}]
```

== References
[1]: https://github.com/open-metadata/openmetadata?utm_source=chatgpt.com "GitHub - open-metadata/OpenMetadata: OpenMetadata is a unified metadata platform for data discovery, data observability, and data governance powered by a central metadata repository, in-depth column level lineage, and seamless team collaboration. · GitHub"

[2] https://open-metadata.org/, the official website for OpenMetadata.

[3]: https://docs.open-metadata.org/v1.12.x/how-to-guides/data-governance/glossary?utm_source=chatgpt.com "OpenMetadata Data Glossary Guide"

[4]: https://docs.open-metadata.org/v1.12.x/api-reference/lineage?utm_source=chatgpt.com "Lineage"
