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

== Four Layers of Knowledge Engineering
Four layers:
- Tags: flat, no hierarchy
- Categories: hierarchical, more organized
- Ontology: define the semantics
- Knowledge Graphs: instantiation of ontology, Knowledge Graph = Ontology + Real Instance Data + Semantic Connections

=== Palantir Foundry

Palantir Foundry is an enterprise data operating system designed to integrate disparate data 
sources, apply complex logic, and power operational applications and AI-driven workflows. 
Rather than functioning simply as a data lake or visualization tool, Foundry acts as a 
complete "Data Operations" platform. It sits alongside Palantir's Artificial Intelligence 
Platform (AIP) and is underpinned by Apollo, their continuous delivery system. Together, 
these platforms consist of over 300 microservices running in a highly available, 
autoscaling compute mesh.

Palantir operates on a common architecture consisting of three primary platforms:

- *Foundry:* The core Data Operations platform, handling data integration, transformation, and application building.
- *AIP (Artificial Intelligence Platform):* The Generative AI platform that connects Large Language Models (LLMs) with enterprise data securely.
- *Apollo:* The continuous software delivery platform that autonomously manages and deploys Foundry and AIP updates across diverse environments.

*Compute Modules*

A major architectural component is Compute Modules, which allow organizations to run serverless 
Docker containers directly within the platform. This enables teams to bring existing 
codebases (in any language) and host custom models or complex data integrations, 
dynamically scaling replicas based on load.

=== The Ontology System

The defining feature of Foundry is the *Ontology*. It translates raw data into 
a semantic representation of the business that both humans and AI agents can interact with.

- *Objects and Links ("Nouns"):* Fragments of data from ERPs, CRMs, and edge 
  sensors are mapped to real-world entities (e.g., *Manufacturing Plant*, *Customer Order*).
- *Actions ("Verbs"):* These are executable operations tied to objects (e.g., 
  *Update Purchase Order*). Actions capture decisions and write data back to 
  underlying systems safely.
- *Ontology MCP (Model Context Protocol):* Introduced widely in 2026, Ontology MCP turns 
  Foundry developer applications into MCP servers. This allows external AI agents 
  to securely read object types, execute predefined actions, and run query functions.

=== Links
In Palantir Foundry, if Objects are the "nouns" of the Ontology (like 'Company', 'Employee', 
or 'Work Order'), Links are the connective tissue that defines how those nouns relate to one 
another. They transform disconnected tables of data into a traversable, interconnected graph 
that mirrors the real world.

Under the hood, Foundry translates standard relational database concepts into semantic 
links. A Link Type is defined by its *Cardinality* and its *Keys*:

- *One-to-One / One-to-Many:* In these relationships, Foundry relies on foreign and 
  primary keys. For example, to link a *Company* (One) to *Employees* (Many), the 
  *Employee* object will have a property (like `Employer_ID`) that acts as a foreign 
  key, pointing to the primary key (`Company_ID`) of the *Company* object.
- *Many-to-Many:* If a *Direct Report* can have multiple *Managers*, and a 
  *Manager* can have multiple *Direct Reports*, a single foreign key isn't enough. 
  Foundry handles this by requiring a *Join Table* (a backing dataset containing 
  pairs of primary keys) to define the complex web of connections.

*Key Metadata*

When a developer configures a Link Type in the Ontology Manager, they define several 
critical pieces of metadata:

- *API Name:* This is how developers interact with the link in code (TypeScript or 
  Python). For example, if the API name for the employee side of a link is `employee`, 
  a developer writing an AI function could use `Company.employee.get()` to instantly 
  retrieve all linked employees.
- *Display Names:* Links have human-readable names for both singular and plural 
  contexts (e.g., *Employer* vs. *Employees*), ensuring that business users interacting 
  with dashboards see natural language rather than database column headers.
- *Visibility:* Developers can set links to be "Prominent," "Normal," or "Hidden." 
  A hidden link won't show up in user applications, which is useful for internal 
  system relationships that business users don't need to see.

Links are not just for organizing data; they actively power the kinetic and analytical 
features of the platform:

- *Graph Navigation for AI and Functions:* Because data is linked semantically, 
  developers (and AI agents using the Ontology MCP) don't need to write complex 
  SQL `JOIN` statements to find related data. An LLM can naturally traverse the 
  graph—moving from a *Factory* object, through a link to its *Production Lines*, 
  and through another link to the *Sensors* on that line.
- *Action Types:* Links make data actionable. When a user clicks "Assign Technician" 
  in an application, the underlying Action Type isn't just updating a spreadsheet; 
  it is validating and executing a change to the link between a *Work Order* object 
  and a *Technician* object, strictly according to the permissions and cardinalities 
  defined in the Ontology.
- *Rapid Application Development:* In tools like Workshop, builders can drop in 
  an "Object List" widget that automatically populates with all objects linked to 
  the user's current selection. If a user clicks on an *Airplane* object, the UI 
  can instantly surface a table of all linked *Maintenance Logs* without requiring 
  the builder to wire up custom database queries.

[Hands-On Ontology Modeling: Object Types, Links & Actions](https://www.youtube.com/watch?v=aQ--AP4YJMs)

This hands-on tutorial demonstrates how to configure object relationships in the 
platform, including setting up foreign key mappings and defining cardinality.

=== Data Integration and Pipelines

Foundry treats data engineering like software engineering, offering robust 
tools for building and managing pipelines:

- *Data Connection:* Supports over 200 out-of-the-box connectors (REST, JDBC, 
  streaming, geospatial) with flexible ingress topologies. Recent 2026 updates 
  include OAuth2 client credentials flows for Snowflake via external identity 
  providers like Okta or Entra ID.
- *Pipeline Builder & Code Workspaces:* Low-code and pro-code environments 
  (PySpark, R, SQL) for data transformation. Pipeline Builder features 
  "branch-aware auto-upgrades," ensuring inference pipelines always resolve 
  to the latest published model version on the current branch.
- *Global Branching:* Development in Foundry is heavily version-controlled. 
  Global branching allows users to view and interact with modified datasets, 
  ontology entities, and applications in a secure sandbox before merging 
  changes to production.

=== Application Development

Foundry provides a suite of tools to build operational applications directly on top of the Ontology:

- *Workshop:* The native low-code application builder. It manages underlying 
  storage and compute, allowing builders to create highly complex applications 
  ranging from simple dashboards to mission-critical operations center screens.
- *Slate:* A platform for front-end developers to build highly customized, 
  widget-driven web applications using JavaScript and SQL/Ontology data.
- *Carbon:* A module-based workspace system that allows builders to 
  string together parameterized Foundry applications (like Workshop 
  modules and Quiver dashboards) into cohesive navigation workflows.

=== AI Platform (AIP) Integration

AIP embeds generative AI natively into Foundry's data and ontology, ensuring 
models respect existing security primitives.

- *Model Agnosticism & BYOM:* Foundry supports bring-your-own-model (BYOM), 
  providing streamlined integration with standard provider APIs (OpenAI, 
  Anthropic, and recently xAI's Grok via Grok Build 0.1).
- *AIP Logic & Evals:* Developers can build AI-backed functions and rigorously 
  test them using *AIP Evals*. The platform includes 19 built-in evaluators 
  (exact match, LLM-as-a-judge, Levenshtein distance) to automatically run 
  tests, diagnose failures, and refine prompts.
- *AIP Chatbots:* Organizations can deploy custom-sourced AI assistants that 
  respect strict data access controls, complete with session logging and 
  deployment via the platform's internal Marketplace.

=== Security, Governance & Observability

Palantir is renowned for its military-grade security models, and Foundry enforces 
a "zero-trust" infrastructure.

- *Granular Security:* Role-, classification-, and purpose-based access controls 
  propagate automatically through data lineage. If a user does not have permission 
  to see a row of data, they will not see it in any downstream application, dashboard, 
  or LLM output.
- *Data Health & Observability:* The platform features comprehensive telemetry. 
  *Workflow Lineage* provides seven days of execution history, tracing the full 
  request journey across functions, actions, and LLM calls. Developers can view 
  near real-time success/failure counts and P95 execution durations for all 
  pipelines and active agents.

Palantir Foundry focuses on semantics, or ontology. It can be roughly viewed as:
- Classes: Classify objects with same properties, such as 'device', 'provider', 'factory', 'failure events'
- Instances: individual instances in the class, such as: three-axile CNC-003号
- Properties: member properties in a class, example: purchase date, provider.qualification-level, etc.
- Relationships: Class/Instance relations, such as 供应商 - 供应 → 配件；配件 — 安装于→ 设备
- Inference Rules: 从已有知识推导新知识, such as: 如果供应商资质等级=吊销 ∧ 该供应商供应配件X → 所有安装X的设备标记"风险待评估"

The most important feature of Palantir ontology is *Inference*. 
It does what tagging and categories fail to do. As an example, below are
what we know:
1. 张三是设备部主管
2. 设备部主管对所有三轴CNC有审批权限
3. CNC-003号是三轴CNC

we should be able to inference: （无需人工录入）：
→ 张三对CNC-003号有审批权限
本体让计算机知道它从未被显式告诉的信息。

*Object*
Real-world objects are mapped to *Object*.
Palantir Foundry Ontology 的核心竞争力不是"大数据平台"，而是在数据之上的一层Ontology（本体）。
它将分散的数据库表映射为"真实世界的对象": Object, such as 卡车、病人、合同、生产线, 并定义它们之间的语义关系。
- Object Type: 定义实体（如"订单"、"患者"）本体中的"类"
- Link Type: 定义实体间关系（如"订单 — 包含→ 产品"）本体中的"关系"
- Action Type: 定义可执行的操作（如"审核订单"）从"知道"到"行动"的闭环
- Functions: 计算和推理引擎（如自动计算交付优先级）本体推理的实现层

= References
[1] #a_001

[2] #ref_ontology_vs_semantic_layer

[3] 标签 vs 分类法 vs 本体 vs 知识图谱：企业知识组织四层金字塔,
https://mp.weixin.qq.com/s/YSJFvt-J9DHbF5JzFlXTZg 
