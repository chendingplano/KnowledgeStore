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
    "SemOS - Search Engine"
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
  logical_name: "semos-search-engine",
  file_id: "2026100101",
  source: "",
  content_type: "research",
  document_date: "2026/10/01",
  keywords: [search engine, hybrid search, bm25, vector search, similarity search],
)

= Overview
The typical architecture for search is hybrid search: BM25 + vector.
The major problem for this approach is: most vector stores require
loading the entire vector database into memory (such as FAISS).
This presents a serious scalability issues.

SemOS Search Engine (SSE) uses the following method:
```text
Search candidates
        |
Vector similarity compare (optional)
```

The key is picking candidates. BM25 is syntactical. It is a good 
algorithm to find
the relevant candidates. Its accuracy is, however, critically dependent
on the unification of keywords. Keywords may have aliases, acronyms,
jargons, in different languages, etc. Any single character difference
may fail a search.

In addition to syntactial method, we also need ways to find candidates
semantically. Vectors are the most popular data structure for 
searching candidates semantically. But it presents serious scalability
issues.

Vectors are not the only way of expressing semantics. There are
quite a few methods to associate semantics to content, including:

- Canonical Keyword 
- Categories
- Labels/tags

== Categories vs. Vector Database
The main argument for vector databases is that it supports semantic search.
Vectors are often viewed as 'semantics'. In reality, however, vectors often
fail the expectation, mainly because of the following:
- Content may contain multiple meanings (semantics).
  Their embedding is the mixture of multiple meanings.
  This seriously affect the accuracy of semantics
- As the corpus grows, the accuracy degrades. In other word, this solution
  is not scalable. One way to tackle this problem is to divide corpus
  by a kind of categories into smaller ones.
  
=== Problems with Vector Databases
FAISS is definitely not what we need because it requires all vectors must be in memory.
When the system becomes big, there is a serious memory issue.

PostgreSQL has disk-based vector index, but I don't think it is good enough.

If we ever want to use a vector database, we should definitely avoid building 
a gigantic global vector index or database. Vector databases should use the
same idea as 'charding'. Contents are sharded (or categorized) first into
smaller sub-corpus, which can recursively sharded into smaller ones until
they are small enough.

In this design, there is no single gigantic global vector database. Instead,
there are many, possibly hundreds, thousands or even more sharded 
vector databases.

Search a vector database will be done as:
- Find the root level sharded vector databases
- For each sharded vector database, recursively find its sharded 
  vector databases, until it reaches leaf sharded databases.
- The above step is 'pick candidates'
- Search the sharded vector databases using vector similarity

If a database is small enough (such as < 10,000 or 20,000 vectors), 
it may not even need indexes.

=== What exactly is semantics?
Embeddings are only one method of expressing semantics. There are many
other methods, including:
- Categories
- Labels
- Topics

These methods do not have the problems as we discussed above.


BM25 is important but it can easily miss candidates even with single-character drift
over the keywords, let alone aliases, multilingual issues, etc.

It appears to me that 'categories' may be the solution. Categories are essentially
'indexes' on semantics. Instead of using vectors for semantic similarities, we should
use categories.

=== Categories
Each type of artifacts maintains its own categories.
Categories are constructed in hierarchy:

```text
category
category
...
category
'others'
```

Each of the category may have its child sub-categories, recursively.
Categories without sub-categories are called 'leaf categories'; otherwise,
they are called 'node categories'.

==== Resolving Artifact Categories

An artifact can be a chunk, metric, provision, etc.
Categories are used as an index for artifacts.
Categories are identified by canonical names (SKOS).

*Category Tree*
Each named category is a category tree. There are two types of nodes
in the tree: inner node and leaf. Members of an inner node should be
either all inner nodes or artifacts.

*Resolve categories for an artifact*

Given an artifact:
1. Add the root category to 'pending queue'
2. If 'pending queue' is empty, stop. Otherwise, it pops
   a category from the front of the 'pending queue' and
   set it as the 'active category'.
3. If the active category is a leaf node, add the artifact
   to the node and associate the node path with the artifact.
4. Otherwise, retrieve all its members. Use a decision model to decide whether 
   the given artifact belongs to some of the members (categories).
   Note that an artifact may belong to multiple categories.
   Most decision models limit the max number of choises. If the number of
   members > R (R defaults to 20), it cuts the members into multiple
   groups, each with no more than 20 categories. It then sends multiple
   requests to the decision model, one per group.
5. If the LLM returns none or only 'others' categories, add the artifact
   to the node's "others" member (create one if it does not have one yet).
   Otherwise, for each returned category, if the corresponding child
   is a leaf node, add the artifact to it and associate the child with
   the artifact. Otherwise, append the category to 'pending queue'.

*Process 'others' category*
The 'others' category contains the artifacts that do not belong to any of
the categories in its level. 

If a 'others' category contains more than S artifacts (S defaults to 1,000), 
use an LLM to extract categories for these artifacts. For each category:
- Use a decision model to determine whether the category belongs to any 
  of the categories in its level. If not (normally it should not belong to 
  any of its siblings), add the category as a new child to its parent.
- Otherwise, resolve this is a sub-category to each of the matched categories.

After that, the "others" node is removed.

*Process inner nodes*

When there are too many children (> T, T defaults to 100), use an LLM
to categorize the children. Then resolve the new categories the same
way as processing the "others" node.

*Process leaf nodes*

Do the same thing when a leaf node has more than W artifacts, W defaults
to 1000.

If each node in the hiearchy holds no more than 100 children:
```text
Level       Max Categories
----------------------------------------------
1           100
2           10,000
3           1,000,000           1 million
4           100,000,000         100 millions
5           10,000,000,000      10 billions 
----------------------------------------------
```

This means that the category tree may have up to 5 levels to index 10 billion
artifacts.

Given a user query, we need to find its categories:
1. Which category the query belongs to, given the level-0 categories (up to 20)
2. If the query matches no given categories, stop with 'no-match-found'
3. If the matched category is a leaf category, stop 'leaf-reached'
4. Otherwise, push the matched categoy to the category path, retrieve the 
   matched category children and repeat Step 1.

When the search loop finishes:
- Stopped with 'no-match-found':
  - If the category path is empty, return none
  - If the category path length is 1, 

== Labels
We may use LLMs to label chunks. The advantages of labels include:
- can be normalized
- can be hierarchical

== Hierarchical Explorability
Categories, labels, and canonical keywords can be organized in hierarchy.

If a node can have up to 99 + 1 children:
```text
Level       Size
--------------------------------------------
1           100
2           10,000
3           1,000,000           1 million
4           100,000,000         100 millions
5           10,000,000,000      10 billions
6           1,000,000,000,000   1 trillion
--------------------------------------------
```

