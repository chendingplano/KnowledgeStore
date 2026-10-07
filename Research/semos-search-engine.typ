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

Given an artifact:
1. Add the root category to 'pending queue'
2. If 'pending queue' is empty, stop. Otherwise, it pops
   a category from the front of the 'pending queue' and
   set it as the 'active category'.
3. If the active category is a leaf category, treat it
   as a group with only one category, goto Step 5.
4. Otherwise, retrieve all the sub-categories from the 
   active category. If there are more than 19 (configurable) 
   sub-categories, divide these sub-categories evenly to N groups,
   each group has no more than 19 sub-categories.
5. For each group, use the decision model to decide whether 
   the given query belong to some of the categories in the group.
   Note that a query may belong to multiple categories. If more than
   M categories are returned from the decision model,
   pick the top M categories. M is configurable and defaults
   to 3.
6. If the LLM returns only 'others' category:
   - If this is not the last group, move on to the next group
   - Otherwise, add the full path of the 'others' to the 
     'matched categories'
7. If the LLM returns other than 'others' categories, for each of the
   matched categories: 
   - if it is a leaf category, add the full path of the category
     to the 'matched categories' list. When 'matched categories'
     list length >= 10, stop.
   - otherwise, push the full path of the category into 
     the 'pending queue'.

=== Process 'others' category
If a 'others' category contains too many artifacts, extract categories
for these artifacts. For each artifact:
- If the 'category list' is not empty, use a decision model to determine
  whether the artifact belongs to one or more of the categories.
- If the decision model returns , add the artifact to each of the matched categoriesuse
- If 
  the categories already extracted. The LLM 
When there are too many entries (such as 1000), we can ask LLMs to create new
higher-level categories for the existing categories, constructing category
hierarchy.

If each node in the hiearchy holds no more than 20 children:
```text
Level       Max Categories
----------------------------------------------
1           20
2           400
3           8000
4           160,000
5           3,200,000           3 millions
6           64,000,000          64 millions
7           1,280,000,000       1.28 billions
8           25,600,000,000      25 billions
9           512,000,000,000     512 billions
10          10,240,000,000,000  10 trillions
----------------------------------------------
```

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

