# Design Proposal: Two-Phase Retrieval and Investigative Search for SemOS

## Executive Summary

Traditional Retrieval-Augmented Generation (RAG) systems treat retrieval as a one-time operation. Given a user query, a retriever (BM25, vector search, hybrid retrieval, graph search, etc.) returns the top-*k* documents or chunks, which are then passed to the LLM. Although effective for many tasks, this architecture assumes that the user's original query contains all the information necessary to retrieve the required evidence.

In reality, complex information-seeking tasks rarely work this way. Human investigators continuously refine their understanding while exploring a corpus. New concepts, entities, functions, standards, metrics, or relationships discovered during exploration naturally lead to new questions. The retrieval process therefore becomes iterative rather than one-shot.

Recent work on Direct Corpus Interaction (DCI) and Relevance-Aware RipGrep (RARG) highlights an important architectural idea: **retrieval should not only locate initial candidates, but should also support interactive exploration of those candidates.**

This document generalizes that idea beyond source-code search and proposes a retrieval architecture suitable for SemOS.

---

# Motivation

Consider the following question:

> How is JWT expiration validated?

Initially, the system knows only the concepts explicitly mentioned in the question:

* JWT
* expiration
* validation

A global retrieval stage can easily identify a handful of promising documents.

However, after reading one document, the LLM may discover:

```go
ValidateToken(...)
```

This identifier did not appear in the original query.

The natural next question becomes:

> Where is `ValidateToken()` used?

Later, the system may discover:

```go
RefreshToken(...)
```

leading to another investigation.

The retrieval process therefore evolves like this:

```text
User Question

↓

Retrieve candidates

↓

Read candidate

↓

Discover new knowledge

↓

Investigate new knowledge

↓

Discover more knowledge

↓

Repeat
```

The key observation is that **new search queries emerge during exploration**, not before it.

---

# Limitation of Conventional Retrieval

Suppose we perform:

```
Search A:
JWT expiration validation
```

which returns

```
Document 17
Document 5
Document 42
```

Later we perform

```
Search B:
ValidateToken
```

which returns

```
Document 5
Document 98
Document 71
```

Now we have two independent ranked result sets.

Questions immediately arise:

* Should they be merged?
* Which ranking should dominate?
* Should one search replace the previous one?
* How should previous exploration influence the new search?

Traditional retrieval provides no principled answer because every search is treated as an isolated event.

---

# Core Idea

Instead of viewing retrieval as repeated independent searches, we treat it as an evolving exploration process.

The system maintains an **Exploration State**, which accumulates knowledge discovered during investigation.

Each subsequent search is conditioned not only on the original user query, but also on the current exploration state.

---

# Two Phases of Search

This proposal separates corpus interaction into two complementary phases.

## Phase 1 — Navigation Search

Goal:

> Where should exploration begin?

Characteristics:

* global
* approximate
* ranking-oriented
* tolerant of false positives

Typical retrieval mechanisms include:

* BM25
* dense vector retrieval
* hybrid retrieval
* graph retrieval
* metadata filtering
* ontology/category search

Output:

```
Candidate documents

Candidate artifacts

Candidate graph nodes
```

The objective is not to answer the question directly.

The objective is to identify promising starting locations.

---

## Phase 2 — Investigative Search

Goal:

> Given the current exploration state, what should be investigated next?

Characteristics:

* local
* iterative
* stateful
* hypothesis-driven

Examples include:

```
Find references to ValidateToken()

Find provisions related to Provision X

Find metrics sharing the same category

Traverse neighboring ontology nodes

Find standards citing this standard

Explore graph neighbors

Search Scene Blocks involving authentication
```

Unlike navigation search, investigative search is guided by discoveries made during exploration.

---

# Exploration State

The central component of the architecture is the Exploration State.

Instead of repeatedly issuing independent retrieval requests, the system maintains evolving context.

Example:

```
Current Question
----------------
How is JWT expiration validated?

Visited Documents
-----------------
RFC-7519

authentication.md

token.go

Discovered Entities
-------------------
ValidateToken

RefreshToken

JWT Claims

Expiration

Relevant Provisions
-------------------
...

Relevant Metrics
----------------
...

Rejected Hypotheses
-------------------
...

Confidence
----------
...
```

Every subsequent investigative search is conditioned on this state.

---

# Navigation versus Investigation

The architecture intentionally separates two different retrieval objectives.

Navigation answers:

> Where should I go?

Investigation answers:

> Now that I am here, what should I learn?

This distinction resembles human investigation.

A human developer rarely performs one perfect search.

Instead they:

```
Search

↓

Read

↓

Discover

↓

Search again

↓

Read

↓

Refine understanding

↓

Repeat
```

The important observation is that every new search is informed by previous discoveries.

---

# Generalization Beyond ripgrep

RARG uses `ripgrep` as its investigative tool.

SemOS should generalize this concept.

Possible investigative operations include:

```
search_metrics()

search_provisions()

search_inventory()

search_categories()

search_products()

search_scene_blocks()

graph_neighbors()

find_references()

trace_requirement()

trace_metric_usage()
```

The investigative tool becomes domain-specific rather than text-specific.

---

# Interaction Model

The overall architecture becomes:

```text
User Question
       │
       ▼
Navigation Search
(BM25, Vector, Graph, Metadata)
       │
       ▼
Candidate Objects
       │
       ▼
Exploration State
       │
       ▼
Investigative Search
       │
       ▼
New Evidence
       │
       ▼
Update Exploration State
       │
       └──────────────┐
                      ▼
             Next Investigation
```

Notice that navigation retrieval occurs only when necessary.

Most iterations occur entirely within the exploration loop.

---

# Relationship to Existing RAG

Traditional RAG:

```
Question

↓

Retrieve

↓

LLM

↓

Answer
```

Two-Phase Retrieval:

```
Question

↓

Navigation

↓

Explore

↓

Investigate

↓

Update State

↓

Investigate Again

↓

Answer
```

The second architecture allows the system to discover information that could not have been expressed in the original query.

---

# Implications for SemOS

SemOS already contains significantly richer retrieval objects than plain documents.

These include:

* documents
* topics
* provisions
* metrics
* inventory items
* products
* references
* Scene Blocks
* ontology categories
* graph relationships

Consequently, investigative search should not be limited to text search.

Instead, every artifact type should expose specialized investigative operations.

Examples include:

* Retrieve metrics related to the current provision.
* Find standards defining the current metric.
* Traverse ontology relationships from the current category.
* Explore Scene Blocks involving the same actors.
* Locate products implementing the current requirement.
* Follow citation and dependency graphs.

This transforms SemOS from a retrieval engine into an exploration engine.

---

# Architectural Principle

The central design principle can be summarized as follows:

> Retrieval is not a one-time operation that selects context for an LLM.

Instead,

> Retrieval is a continuous navigation mechanism that guides an evolving exploration process.

Navigation identifies promising starting points.

Investigation incrementally expands understanding.

The Exploration State preserves accumulated knowledge and provides context for every subsequent investigative step.

This separation between **global navigation** and **local investigation** provides a principled way to combine the strengths of conventional retrieval techniques with the exploratory reasoning capabilities of modern LLMs. It also naturally accommodates SemOS's heterogeneous artifact model, where documents are only one of many interconnected knowledge objects that can participate in the investigation process.
