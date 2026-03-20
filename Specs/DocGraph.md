**DocGraph** for agents: a graph-native architecture for **LLM document analysis** that combines:

* a **DOCMAP.md** layer for machine-readable document navigation,
* a **reasoning graph** for multi-step evidence chains,
* and **hybrid retrieval** over chunks, clauses, entities, citations, and document structure.

Graph-based retrieval is especially useful for **multi-hop questions**, long corpora, and domains with explicit cross-references like standards, specs, and regulations. ([arXiv][1])

## DocGraph

```text
                                  ┌───────────────────────────┐
                                  │        USER QUERY         │
                                  │ "Which clauses require X  │
                                  │  if system Y uses Z?"     │
                                  └─────────────┬─────────────┘
                                                │
                                                ▼
                     ┌──────────────────────────────────────────────┐
                     │            QUERY PLANNER / ROUTER            │
                     │ intent, scope, entities, doc families, hops  │
                     └───────┬───────────────────────┬──────────────┘
                             │                       │
                             │                       │
                             ▼                       ▼
              ┌────────────────────────┐   ┌───────────────────────────┐
              │      DOCMAP.md         │   │     VECTOR / BM25 INDEX   │
              │ machine-readable map   │   │ chunks, headings, tables  │
              │ of corpus structure    │   │ semantic + lexical search │
              └──────────┬─────────────┘   └─────────────┬─────────────┘
                         │                               │
                         ▼                               ▼
      ┌────────────────────────────────────────────────────────────────────┐
      │                            DOCGRAPH                                │
      │                                                                    │
      │  Document nodes      Section nodes      Clause nodes               │
      │  Standard nodes      Table/Figure nodes Term/Definition nodes      │
      │  Entity nodes        Citation nodes     Requirement nodes          │
      │                                                                    │
      │  Edge types:                                                       │
      │  CONTAINS • DEFINES • CITES • AMENDS • REFERENCES • OVERRIDES      │
      │  APPLIES_TO • EXCEPTION_TO • SATISFIES • CONFLICTS_WITH            │
      │  DERIVED_FROM • VERSION_OF • NEARBY • SAME_TOPIC                   │
      └──────────┬───────────────────────────────────────────────┬─────────┘
                 │                                               │
                 ▼                                               ▼
   ┌──────────────────────────────┐                 ┌───────────────────────────┐
   │     REASONING GRAPH          │                 │    EVIDENCE ASSEMBLER     │
   │ query-specific working graph │                 │ ranks passages + paths +  │
   │ hypotheses, hops, subclaims  │                 │ citations + provenance    │
   └──────────────┬───────────────┘                 └─────────────┬─────────────┘
                  │                                               │
                  └──────────────────────┬────────────────────────┘
                                         ▼
                          ┌────────────────────────────────┐
                          │   LLM ANSWER + CITED TRACE     │
                          │ answer, uncertainty, evidence  │
                          │ path, clause-level grounding   │
                          └────────────────────────────────┘
```

## What each layer does

### 1) DOCMAP.md

This is the **agent-facing control plane** for the corpus.

**DOCMAP.md is to documents what SKILL.md is to skills**. It tells the model:

* what document families exist,
* where authoritative versions live,
* how the corpus is organized,
* which files are normative vs explanatory,
* which sections are definitions, requirements, exceptions, annexes, change logs, and crosswalks.

Recent agent-oriented docs ecosystems are already converging on this pattern: a root map file that points the agent to the right documentation subsets instead of making it scan everything blindly. ([Simon Willison’s Weblog][2])

Refer to `DOCMAP.md` for doc map.

### 2) DocGraph

This is the **persistent corpus graph**.

It stores both:

* **structural relationships**: document → section → clause → table,
* **semantic relationships**: term A defines B, clause C cites D, section E overrides F.

For standards/specs/regulations, the most important node types are usually:

* **Document**
* **Section / subsection / clause**
* **Definition**
* **Requirement**
* **Exception**
* **Citation / cross-reference**
* **Term / controlled vocabulary**
* **Version / amendment**
* **Entity / system / component / actor**

This is where large technical repositories benefit most, because those corpora are not just text collections; they are **networks of obligations, definitions, scope limits, and references**. Graph-based RAG papers consistently highlight that this structure improves retrieval for complex and multi-hop queries. ([arXiv][3])

### 3) Reasoning graph

This is the **temporary query-time graph**.

Unlike the persistent DocGraph, the reasoning graph is built per question. It tracks:

* subquestions,
* retrieved evidence,
* hypotheses,
* unresolved ambiguities,
* support/contradiction links,
* final evidence paths.

Example for a regulatory question:

```text
Q: "Does clause 8 require redundancy for remote shutdown in offshore systems?"

Reasoning graph:
  H1: "remote shutdown" is defined in Spec A
  H2: offshore systems fall under Scope B
  H3: clause 8 imposes a SHALL requirement
  H4: annex C provides an exception
  H5: newer amendment modifies annex C

Evidence path:
  DOCMAP route
    -> Spec A
    -> Scope B
    -> Clause 8
    -> Annex C
    -> Amendment 2025-2
```

That separation is useful:

* **DocGraph** = durable corpus memory
* **Reasoning graph** = per-query working memory

### 4) Retrieval

A strong DocGraph system should use **hybrid retrieval**, not graph-only.

Best pattern:

* **DOCMAP routing** narrows the search space
* **vector/BM25 retrieval** finds candidate chunks
* **graph traversal** expands along citations, definitions, exceptions, and version links
* **reranking** scores passages plus graph paths together

This aligns with current GraphRAG practice: hybrid approaches often outperform either pure vector retrieval or pure graph traversal alone, especially when the question requires joining evidence across multiple clauses or documents. ([ScienceDirect][4])

---

## Why this is good for standards, specs, and regulations

These repositories usually have all the properties that make flat chunking weak:

* hierarchical structure,
* dense cross-references,
* explicit definitions,
* versioning/amendments,
* exceptions and carve-outs,
* many questions that are inherently multi-hop.

A DocGraph helps answer questions like:

* “Which clauses define, constrain, or override this requirement?”
* “What changed between the 2023 and current version?”
* “Which tables and annexes apply to this component?”
* “Is this requirement normative, informative, or superseded?”
* “What chain of clauses supports this conclusion?”

That is exactly the kind of scenario where graph-enhanced retrieval has been reported to help most. ([MDPI][5])

## A good mental model

Think of the stack like this:

```text
DOCMAP.md      = how to navigate the corpus
DocGraph       = what the corpus knows structurally + semantically
Reasoning graph= how this specific question is being solved
Retrieval      = how evidence enters the system
LLM            = how the grounded answer is synthesized
```

## Recommended node and edge schema

A compact schema for implementation:

```text
Nodes:
  Document(id, title, type, version, authority)
  Section(id, heading, level)
  Clause(id, text, modality)          # SHALL / SHOULD / MAY / MUST NOT
  Definition(id, term, definition)
  Requirement(id, requirement_type)
  Exception(id)
  Citation(id, target_ref)
  Table(id)
  Figure(id)
  Entity(id, name, type)
  Topic(id, label)

Edges:
  CONTAINS
  NEXT
  PARENT_OF
  DEFINES
  REFERENCES
  CITES
  AMENDS
  SUPERSEDES
  APPLIES_TO
  EXCEPTION_TO
  SATISFIES
  CONFLICTS_WITH
  MENTIONS
  SAME_TOPIC
  DERIVED_FROM
```

## If you want the simplest possible pipeline

```text
1. Parse corpus into documents/sections/clauses
2. Build DOCMAP.md from corpus metadata
3. Build vector index over chunks
4. Build DocGraph over structure + refs + definitions + versions
5. At query time:
   a. DOCMAP route
   b. retrieve top chunks
   c. expand via graph neighbors
   d. build reasoning graph
   e. synthesize answer with clause-level citations
```

## Bottom line

A **DocGraph** is most useful when you want the model to treat a document repository as a **navigable evidence system**, not just a bag of chunks.

In one sentence:

> **DOCMAP.md chooses where to look, DocGraph models what is connected, the reasoning graph tracks how the answer is derived, and retrieval brings in the exact evidence.**

I can also turn this into a **formal spec** with:

* a `DOCMAP.md` template,
* a JSON schema for DocGraph nodes/edges,
* and an end-to-end query flow for standards/regulatory corpora.

[1]: https://arxiv.org/abs/2404.16130?utm_source=chatgpt.com "A Graph RAG Approach to Query-Focused Summarization"
[2]: https://simonwillison.net/2025/Oct/24/claude-code-docs-map/?utm_source=chatgpt.com "claude_code_docs_map.md"
[3]: https://arxiv.org/pdf/2501.13958?utm_source=chatgpt.com "A Survey of Graph Retrieval-Augmented Generation for ..."
[4]: https://www.sciencedirect.com/science/article/pii/S092658052600035X?utm_source=chatgpt.com "Bridging dual knowledge graphs for multi-hop question ..."
[5]: https://www.mdpi.com/2079-9292/14/11/2102?utm_source=chatgpt.com "Document GraphRAG: Knowledge Graph Enhanced ..."
