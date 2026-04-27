---
name: [[def:treesearch]]
doc create time: 2026/04/19
url: https://github.com/shibing624/TreeSearch
---

# 🧠 What TreeSearch is

**TreeSearch** is a structure-aware document retrieval system designed as an alternative to embedding-based RAG.
TreeSearch = “BM25 + tree traversal + document structure” as a lightweight, interpretable alternative to embedding-based RAG. Its main idea is to keep global layer simple (index), push structure to local level.

* Core idea: **retrieve documents using their hierarchical structure instead of embeddings**
* Positioning: lightweight, fast, and deterministic retrieval for **documents + codebases**
* Tagline: *“Structure-aware document retrieval without embeddings”* ([Trendshift][1])

---

# ⚙️ Key Concepts

## 1. Tree-based indexing

Instead of chunking text flatly like typical RAG:

* Documents are parsed into a **tree structure**

  * e.g. headings → sections → paragraphs → code blocks
* Retrieval operates by **traversing this tree (best-first search)**

👉 This preserves:

* document hierarchy
* semantic locality
* context boundaries

---

## 2. No embeddings required

Unlike vector search systems:

* ❌ No embedding models
* ❌ No vector database
* ✅ Uses classical IR techniques (e.g. BM25, FTS5) ([PyPI][2])

**Implication:**

* zero GPU requirement
* no embedding drift / versioning issues
* easier deployment in enterprise/local environments

---

## 3. Best-first tree search

Retrieval works like:

1. Start from root nodes (documents / files)
2. Score nodes using keyword relevance
3. Traverse down **only promising branches**
4. Return the most relevant leaf nodes

👉 This is essentially:

* **guided search over document structure**
* not brute-force chunk ranking

---

## 4. Designed for RAG

TreeSearch is meant to be plugged into:

* LLM pipelines
* local knowledge base systems
* code search tools

Typical flow:

```
User query → TreeSearch retrieval → relevant structured chunks → LLM
```

---

# 🚀 Key Features

### ⚡ Fast & lightweight

* Millisecond-level retrieval on **10k+ documents** ([Trendshift][1])
* No heavy model inference

### 🧩 Multi-format support

Via optional extras:

* PDF, DOCX, HTML parsing ([PyPI][2])
* code parsing (tree-sitter)

### 🔍 Hybrid retrieval signals

* lexical matching (BM25)
* full-text search (FTS5)
* structural signals (tree traversal)

---

# 🆚 How it differs from typical RAG

| Aspect           | TreeSearch           | Standard RAG                |
| ---------------- | -------------------- | --------------------------- |
| Representation   | Tree (hierarchical)  | Flat chunks                 |
| Retrieval        | Tree traversal       | Vector similarity           |
| Dependencies     | None (no embeddings) | Embedding model + vector DB |
| Cost             | Very low             | Medium–high                 |
| Interpretability | High                 | Low                         |
| Semantic power   | Medium               | High                        |

👉 Insight:
TreeSearch trades **semantic generalization** for:

* speed
* determinism
* structural awareness

---

# 🎯 When it works best

**Good fit:**

* structured documents (manuals, specs, code)
* enterprise knowledge bases
* local/offline deployments
* cost-sensitive systems

**Less ideal:**

* fuzzy semantic queries
* cross-domain reasoning
* paraphrase-heavy retrieval

---

# 🧩 Big Picture Insight

TreeSearch represents a broader trend:

> Moving from **embedding-heavy RAG → hybrid / structure-aware retrieval**

It’s especially aligned with your earlier idea:

* using **document structure + logical relationships**
* instead of relying purely on embeddings

---

## Organize Documents
TreeSearch doesn’t build a global hierarchical tree across documents. Instead, it uses something closer to:

> **“Forest + index” rather than a single super tree**

It organizes data as a forest of independent trees, each document is parsed into its own tree. There is no
explicit parent structure across documents.

---

### Global Index Layer

Instead of a super tree, TreeSearch builds a **global retrieval index over nodes**, typically:

* BM25 index (keywords)
* SQLite FTS5 (full-text search)
* Possibly metadata filters

This index contains nodes from all document trees, with references like:

  ```
  node_id → (doc_id, path_in_tree, content)
  ```
In other word, it breaks down documents into nodes based on document structures and build an index of 
all the nodes from all the documents. 'Breaking down' is chunking, a chunking mechanism that uses
document structures.

---

### Retrieval

When a query comes in:

### Step 1: Global candidate retrieval (flat)

* Search the **global index**
* Return top-K **entry nodes**

  * These could be:

    * document roots
    * sections
    * paragraphs

This is the cross-document routing mechanism

---

### Step 2: Local tree traversal (structured)

For each candidate:

* Traverse **within that document’s tree**
* Use best-first search to go deeper
* Refine results using:

  * structure
  * local context
  * relevance scores

---

### Step 3: Merge results

* Combine results from multiple trees
* Return top relevant chunks

---

Why they don’t build a super tree

ChatGPT thinks a global tree has serious problems: 1. No natural hierarchy across documents, 2. Scalability issues, a giant tree becomes deep, sparse, inefficient to traverse, and 3. Cross-document relations are not hierarchical. They are semantic, referential, graph-like. A tree is the wrong abstraction at global level.

But my opinion is different. When we write code, which may contain thousands or even hundreds of thousands of files, we do organize them, or we do build a 'super tree'. All files naturally fit into this super tree. It is true 
that this is a tree (file system), not a graph or network (referential). We can view this as the 'First Dimension',
or the 'Semantic Dimension'.

SemOS takes the 'super tree' approach. It builds a super tree (though virtual). The tree itself is a tree, not a graph, but nodes link to each other.

## Conclusion

My conclusion is:
1. The major difference between TreeSearch and other [[Knowledge System]] is that TreeSearch uses document structures
   to chunk documents. We would like to chunk documents this way, but not all documents are structural, or 
   can be structured, even though their original content is structured. OCR often fails recognizing 
   document structures. If it supports only structured documents, this is a serious limitation.
2. The index is essentially BM25. Any search engine can do it. One can, of course, implement its own.
3. Any knowledge system can remove the vector search. I don't think this is the right approach. Vector search (or
   semantic search) is important, though it does add dependency and system complexity. Removing it just because
   it is not easy to have it is not a good reason.

A full-blown search engine, such as ElasticSearch, does add significant resource. This is especially true for
cloud deployment. Based on https://mp.weixin.qq.com/s/k2HHfziaAoQUF_FVWfrRMg, self-implemented BM25 can be 
1/50 or even 1/100 cheaper than ElasticSearch. The number may be over claimed, but we all understand the 
meaning. 

SQLite supports BM25. PostgreSQL supports BM25. SemOS plans to use PostgreSQL BM25.

TreeSearch thus adds very little value to SemOS.

---

[1]: https://trendshift.io/repositories/24831?utm_source=chatgpt.com "shibing624/TreeSearch — GitHub trending stats & insights"

[2]: https://pypi.org/project/pytreesearch/?utm_source=chatgpt.com "pytreesearch · PyPI"

