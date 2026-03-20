# DOCMAP

Version: 1.0
Purpose: Machine-readable map of documentation for AI agents.

---

## 1.1 Metadata
Metadata includes the following data items:
- doc-name: "doc name"
- doc-no: "doc no"
- publish date: "publish date"
- release date: "release date"
- abolish date: "abolish date"
- current state: "state"
- replace: [doc-no, ...]
- created: "YYYY-MM-DD"
- last_updated: "YYYY-MM-DD"
- parser: "parser-version"

## 1.2 Contributors
Contributors include organizations and individuals.
  - main organizations: ["org-name", "org-name",...]
  - participating organizations: ["org-name", "org-name",...]
  - main authors: ["person-name", "person-name",...]
  - participating authors: ["person-name", ...]

---

## 1.3 Catagory and Classification
Catagories:
- Catagory I
- Catagory II
- Catagory III
- Catagory IV
- Catagory V

CCS: "ccs-code"
ICS: "ics-code"

## 1.4 Agent Info
This section contains information specific for agents:
- chunking strategy
- chunk size
- human reviewed: {yes|no}
- accuracy level: [0.0, 1.0], the bigger, the more accurate

## 1.5 Executive Summary

<3–6 sentences describing the doc>

Example:

This documentation describes a platform that validates technical documents
against industry standards. The system extracts standards, identifies
requirements, and verifies compliance within technical documentation.
The repository contains architecture descriptions, API references,
developer guides, and operational procedures.

---

## 1.6 Short Summary

1-3 paragraphs describing the doc.

## 1.7 Documentation Scope

included_topics:
  - Doc Structure
  - API Reference
  - Main Data Reference
  - Machine Readability Reference
  - Machine Executable Reference
  - Developer guides
  - Operations
  - Metric Index
  - Compliance Rule Index
  - Relevant Standard Reference

excluded_topics:
  - experimental notes
  - internal drafts

---

## 1.7 Keywords

List the keywords for the doc. Examples: [AI, RAG, document analysis, compliance, standards validation] 

---

## 1.8 Documentation Structure

root: docs/

tree:

  overview:
    description: High-level introduction to the system
    documents:
      - docs/overview/system-overview.md

  architecture:
    description: System design and components
    documents:
      - docs/architecture/architecture.md
      - docs/architecture/components.md

  guides:
    description: User and developer guides
    documents:
      - docs/guides/installation.md
      - docs/guides/usage.md

  api:
    description: API documentation
    documents:
      - docs/api/api-reference.md

  operations:
    description: Deployment and operational procedures
    documents:
      - docs/operations/deployment.md
      - docs/operations/monitoring.md

---

## 1.9 Document Index

documents:

  - path: docs/overview/system-overview.md
    summary: Overview of the system and its purpose
    keywords: [overview, introduction]

  - path: docs/architecture/architecture.md
    summary: Detailed architecture description
    keywords: [architecture, system design]

  - path: docs/guides/installation.md
    summary: Installation instructions
    keywords: [installation, setup]

  - path: docs/api/api-reference.md
    summary: API endpoint reference
    keywords: [api, reference]

---

## 1.10 Key Concepts

concepts:

  - name: Standard
    description: Industry specification used for compliance
    related_docs:
      - docs/standards/standards-list.md

  - name: Requirement
    description: Specific rule defined by a standard
    related_docs:
      - docs/standards/standards-list.md

  - name: Validation
    description: Process of checking a document against requirements
    related_docs:
      - docs/architecture/architecture.md

---

## 1.11 Topics
Concepts are fundamental ideas or entities. Topics are the areas of discussion about ideas, concepts, entities., etc.
    - Topic Reference
    - Topic and Content Relation

# 1.12 Logical Relationships
Logical relationships are mainly used for agent to reason.

# 1.13 Concept Relationships

relationships:

  - Standard -> contains -> Requirement
  - Document -> references -> Standard
  - Validator -> checks -> Requirement

---

## 1.14 Task-Oriented Navigation

tasks:

  understand_system:
    steps:
      - docs/overview/system-overview.md
      - docs/architecture/architecture.md

  install_system:
    steps:
      - docs/guides/installation.md

  use_api:
    steps:
      - docs/api/api-reference.md

  deploy_system:
    steps:
      - docs/operations/deployment.md

---

## 1.15 External References

external_standards:

  - name: ISO 9001
    description: Quality management standard

  - name: IEEE 829
    description: Software test documentation standard

---

## 1.16 Retrieval Hints (For RAG Systems)

query_examples:

  - system architecture
  - API usage
  - installation steps
  - deployment configuration
  - standards validation

recommended_docs:

  architecture:
    - docs/architecture/architecture.md

  installation:
    - docs/guides/installation.md

  api:
    - docs/api/api-reference.md

---

## 1.17 Update Policy

DOCMAP.md must be updated when:

- new documentation directories are added
- documents are renamed or removed
- architecture or major system components change

---

## 1.19 Entity Relations and Logical Relations
The terms **“Entity Relations”** and **“Logical Relationships”** overlap but are used with **different emphasis and abstraction levels**, especially in **knowledge graphs, ontologies, and reasoning systems for agents**.

### 1.19.1 Entity Relations

An **entity relation** is a **formal connection between entities (nodes)**. It explicitly exhibits a factual connection between entities.

#### Knowledge retrieval

Uses **entity relations**.

Example:

```
Find all Requirements contained in ISO9001
```

Typical form:

```
(subject) --relation--> (object)
```

Example:

```
Standard --contains--> Requirement
Document --references--> Standard
Validator --checks--> Requirement
```

Characteristics:

* **objective**
* **structural**
* **machine-readable**
* **explicitly defined**
* used in **graphs, databases, and ontologies**

Entity relatoins are **data**, not reasoning.

### 1.19.2 Logical Relationships

Reasoning-based connections derived from rules, constraints, or interpretations.

For AI agents, the distinction between entity relations and logical relationship is important.

Agents operate in two phases:
A **logical relationship** is a **relationship defined by reasoning or logic**, rather than just a stored edge.

Logical relationships often represent:

* **implication**
* **dependency**
* **causality**
* **constraints**
* **derivations**

Examples:

```
If Document references Standard
AND Standard contains Requirement
THEN Document must satisfy Requirement

Section A --contradicts--> Section B
```

Logical relationships are often expressed as:

* rules
* implications
* constraints

Example rule:

```
references(Document, Standard)
contains(Standard, Requirement) → must_satisfy(Document, Requirement)
```

---

#### Logical Relation Interpretations

Logical relations should include interpretations because they are often derived or even subjective.

Example:

```
Document --implies--> compliance, explain how it comes to this conclusion.
```

Especially when generated by:

* humans
* LLM reasoning
* rule systems

---

#### Example: Subjectiveness

Consider this statement:

```
Requirement R1 is stricter than Requirement R2
```

This is **not always a pure fact**.

It may depend on interpretation.

So it is better classified as a **logical relationship** rather than a simple relation.

---

### 1.19.3 Layered View (Very Useful)

You can think of three layers.

#### Layer 1 — Entities

```
Standard
Requirement
Document
Section
```

#### Layer 2 — Entity Relations (Facts)

```
Standard --contains--> Requirement
Document --references--> Standard
Requirement --located_in--> Section
```

---

#### Layer 3 — Logical Relationships (Reasoning)

```
references + contains → must_satisfy

must_satisfy + violation → non_compliant
```

These are **rules**.

---

## 1.20 Practical Example

In the **document compliance checker**:

#### Entity Relations

```
Document --references--> Standard
Standard --contains--> Requirement
Requirement --located_in--> Section
```

---

#### Logical relationships

```
references + contains → must_satisfy

must_satisfy + missing_requirement → violation

violation → non_compliance
```