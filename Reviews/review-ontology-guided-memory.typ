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
    "Review - Ontology Guided Memory"
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
  logical_name: "review-ontology-guided-memory",
  file_id: "20261014",
  source: "",
  content_type: "review",
  document_date: "2026/10/04",
  keywords: [Memory, ontology],
)

= Overview
*Paper Summary*: Ontology-Guided Long-Term Agent Memory for Conversational RAG

MLSys 2026 · Shuang Cao and Rui Li · 18 pages

The central idea of this paper is to combine a dynamically learned knowledge graph, 
vector retrieval, and an adaptive retrieval router to give LLM agents reliable long-term 
conversational memory. Instead of simply storing conversation histories as text or 
embeddings, the system extracts durable facts, organizes them into an ontology, and 
learns how to retrieve them efficiently.

The paper addresses an important limitation of traditional RAG: semantic similarity is 
not necessarily the same as contextual relevance. For example, a user might mention 
enjoying the movie Titanic in an early conversation, then ask several weeks later, 
"What should I watch this weekend?" A vector search for the new question may not 
retrieve the earlier preference because the two statements have little semantic overlap. 
The proposed system solves this by storing structured relationships such as 
`User → LIKES → Titanic` and `User → PREFERS_GENRE → Romance`. Graph traversal can 
recover the preference even when the current query contains no relevant keywords.

This is essnetially a search problem. Many rely on semantic search but semantic
search often fails (missing the relevant) because semantics is diluted as more
content adding to its vector database. 

== Three key technical contributions

=== Tag2Graph-Learner: Automatically building a dynamic ontology

The system converts conversational statements into structured knowledge through a 
multi-stage process:

1. Entity and relation extraction: A sequence tagger using BIO labeling identifies 
   entities and attributes, while a lightweight relation classifier produces candidate triples.
2. LLM validation: A constrained LLM validates candidate triples and normalizes their 
   relationships. Importantly, the LLM is used primarily for validation rather than 
   performing all extraction.
3. Conceptual relation promotion: Repeated observations can be generalized into higher-level 
   relationships. For example, liking several romantic movies may establish a preference 
   for the romance genre.
4. Feedback-driven refinement: Successful retrievals strengthen relevant graph relationships, 
   while contradictory or uncertain evidence can prevent promotion.

Unlike a fixed-schema knowledge graph, this ontology can evolve as new preferences, entities, 
and relationships emerge. Every accepted assertion retains provenance and timestamps, allowing 
the system to trace or reverse changes.

=== Graph × Dense Consistency: Aligning two retrieval mechanisms

Graph retrieval and vector retrieval have complementary strengths. Graphs are effective at 
following explicit relationships and performing multi-hop reasoning, while embeddings are 
effective at retrieving semantically related information even when no structured relationship 
exists.

However, their rankings frequently disagree. The authors report that the graph and dense 
top-10 results overlap by only 3.2 items on average for personalized queries.

Rather than simply combining scores, the system learns to align the two retrieval methods 
using evidence that has previously been verified as useful. This improves agreement without 
requiring expensive alignment across every candidate.

=== Learnable Routing: Choosing retrieval strategies dynamically

Not every query requires graph traversal. Some questions are better answered using vector 
search, while others require structured reasoning.

The system uses a contextual-bandit-based router to select between graph-first and dense-first 
retrieval and allocate computational budgets.

For example, "What should I watch this weekend?" may trigger graph-first retrieval because it 
implies personalization without naming any specific movie. A query explicitly mentioning a 
movie may instead favor dense-first retrieval.

This adaptive routing is intended to improve retrieval quality while minimizing serving costs.

== System architecture

The paper organizes the system into three phases:

#figure(
  image("../Images/image_2026101401.png"),
  caption:[Ontology Guided Memory Architecture]
)

A particularly useful feature is that graph assertions are connected to their original 
conversational evidence. The graph provides conceptual navigation, while the vector store 
preserves the original information needed for grounded responses.

== Experimental results

The authors evaluate their system on an Implicit Preference Recall benchmark containing 
500 multi-session dialogues, as well as the public LoCoMo benchmark.

The following are the paper's main reported results.

[image](https://www.google.com/s2/favicons?domain=https://proceedings.mlsys.org\&sz=32)

proceedings.mlsys.org


```text
| Method            | Recall     | nDCG     | P95 latency |
| ----------------- | ---------- | -------- | ----------- |
| Dense-only RAG    | 0.580      | 0.410    | 142 ms      |
| Long-context      | 0.601      | 0.423    | 310 ms      |
| Summary memory    | 0.618      | 0.439    | 165 ms      |
| Dense + reranking | 0.647      | 0.468    | 190 ms      |
| HippoRAG          | 0.671      | 0.491    | 193 ms      |
| Proposed system   | 0.706      | 0.514    | 185 ms      |

```

The improvements are meaningful:

- 21.7% relative improvement in Recall\@10 over dense-only RAG.
- 47% reduction in disagreement between graph and vector retrieval.
- Approximately 81% lower normalized cost compared with the long-context approach.
- At eight times the baseline conversation history, Recall\@10 declines only from 0.706 to 0.668, while P95 retrieval latency remains under 190 ms in the reported test environment.

[image](https://www.google.com/s2/favicons?domain=https://proceedings.mlsys.org\&sz=32)

  proceedings.mlsys.org

These results support the argument that structured memory can improve implicit recall without 
requiring the entire conversation history to be supplied to an LLM.

== Implications for SemOS

Although the paper focuses on conversational memory rather than document knowledge bases, several 
ideas are directly relevant to SemOS.

First, learned ontologies should complement, not replace, existing knowledge representations. 
SemOS already extracts entities, relations, topics, metrics, and other structured artifacts. 
The paper's conceptual-relation promotion mechanism suggests an additional layer that learns 
higher-level relationships from repeated observations, while retaining source-level evidence. 
For a standards corpus, this could mean deriving a broader concept such as temperature-monitoring 
compliance from multiple provisions concerning data loggers, calibration, and excursion alarms.

Second, graph retrieval and semantic retrieval should be treated as complementary discovery 
mechanisms. SemOS's filesystem exploration, metadata, BM25, vector search, and graph traversal 
can produce different candidate sets. The paper's approach suggests learning which mechanisms 
to prioritize based on query characteristics, instead of always applying a fixed retrieval 
pipeline.

Third, provenance and conservative promotion are especially important. For a standards or 
regulatory knowledge base, an inferred relationship must not be confused with an explicit 
requirement. The paper's use of confidence gates, supporting evidence, and reversible 
promotions offers a useful design pattern, although SemOS would need stricter controls 
for normative claims.

Fourth, feedback-driven alignment is promising but depends on trustworthy feedback. The 
paper learns from previously verified evidence. For SemOS, citations accepted by an LLM 
alone should not automatically count as verified. Independent evidence checks, deterministic 
validation, or human-reviewed examples would provide stronger supervision.

== Limitations and assessment

The paper has several limitations worth considering.

Its primary problem is personalized conversational recall, not large-scale knowledge discovery. 
A per-user graph with thousands of edges is substantially different from a knowledge base 
containing millions of documents and potentially hundreds of millions of extracted relationships. 
The reported latency and storage results therefore cannot be extrapolated directly to SemOS.

Its ontology-learning pipeline also depends on several trained components: a sequence tagger, 
relation classifier, promotion scorer, consistency model, and contextual-bandit router. 
The approach reduces reliance on expensive LLM extraction, but it introduces training-data 
and maintenance requirements.

Finally, feedback-driven graph updates can reinforce mistakes if verification is unreliable. 
This is particularly concerning when inferred knowledge influences compliance conclusions.

== Conclusion

The most important contribution is not any single retrieval algorithm. It is the integration 
of structured memory construction, evidence-aware retrieval, and adaptive retrieval planning 
into one system.

For SemOS, I would prioritize two ideas from this paper: conservative, provenance-backed promotion 
of extracted knowledge into higher-level conceptual relations, and query-dependent routing among 
graph, keyword, and vector retrieval.

The paper provides evidence that both can improve retrieval, but it does not establish that 
its particular learning algorithms are necessary for every deployment. A simpler implementation 
using deterministic promotion rules and a heuristic router would be a sensible baseline before 
adopting the full learning architecture.

Source: [Ontology-Guided Long-Term Agent Memory for Conversational RAG (MLSys 2026)](https://proceedings.mlsys.org/paper_files/paper/2026/file/2fb4be70fc9668e9ec2c71b34fb127d4-Paper-Conference.pdf).

== Semantic Promotion
When a user repeatedly mentions like movies of the same type, we may promote 
these to a higher level knowledge: user profiles.

This forms a new layer: Learned Knowledge

Similarly, when agents create web pages that disable text selection
but users keeps on correcting it, it should learn that pages should enable
text selection by default unless users explicitly requests otherwise, 
or being corrected repeated later on.

The central idea of semantic promotion is to analyze and derive new
artifacts. Building knowledge along with users using the system so that
the more a user uses the system, the more the system knows the user.

There should be a Learner. This is the critical part.
