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
    "Research - Agentic RAG"
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
  logical_name: "Agentic RAG",
  file_id: "2026061101",
  content_type: "research",
  document_date: "2026/06/11",
  keywords: [RAG, Agentic RAG, Graph RAG, Knowledge System],
)

= Overview
[[ref:[1]]] is an article about graph RAG. 
Many people struggle (at least I) about flat-RAG and graph-RAG. The author of this article lists:
- What concepts relate to this issue?
- Which prerequisite skill may be lacking?
- Which resource previously addressed this gap?
- What assessment verifies improvement?
- Which rule restricts recommendations?

I am not sure whether these should be treated as a search requests or question-answering 
requests. To me, it is more the latter than the former. Search requires very little 'smartness', 
tend to be more 'mechanical', while question-answering requires much more 'smartness'. 

If it is the latter, when a user asks "What concepts relate to \<this issue\>?", the request is 
routed to an LLM. I am not sure whether (most likely not) the LLM will just throw the original 
questions back to an RAG, asking for supporting materials, and answer the questions. Instead, 
the LLM analyze the question, and formulates search queries, if needed, and then send the 
search queries to an RAG.

== Agentic RAG
What is 'Agentic RAG'? 

Looking at Claude Code, Codex, or any coding assistant, they are essentially an infinte loop:

- Receive a request
- Let LLM 'think', with proper prompt, list of tools and possibly something more
- LLM understand what it needs to do
- Formulate search requests, often the time through tool-calling, such as 'grep ...', as needed
- The coding assistant checks whether it has right to run the tool
- Run the tool if it can. This includes asking users for clarity, providing additional information,
  chooses the way to move forward, etc.
- Get results, feed back with session history (memory) to the LLM. This includes user feedbacks
  such as whether it solves the problem, if not, the reasons, etc.
- LLM reviews the results, reasons
- (...) essentially going back to the beginning of the loop

My understanding is an agentic RAG is an RAG that has a 'brain'. It uses the brain to think, 
reason, and uses 'search' as a tool, as needed, to find the relevant information, and so on.

If this is what an agentic RAG is, it is not just an RAG, it is an agentic solution, an 
agentic app, just like Claude Code, Codex, etc. This is the reason why we never categorize 
Claude Code as an RAG, agentic or not, but as a kind of 'super app'.

If this is the case, where is the agentic RAG, or what exactly is an agentic RAG?

*(from Fable 5)* \
At the fully agentic end, "agentic RAG" is architecturally indistinguishable from "an agent 
with retrieval tools." The term survives for reasons of lineage and emphasis, not because it 
names a distinct architecture.

*The lineage explanation.* RAG (the 2020 Lewis et al. paper) named a fixed pipeline: 
```text
embed query → retrieve → stuff context → generate. 
```

Crucially, the LLM sits at the *end* of the pipeline as a passive consumer. Control flow 
belongs to the pipeline, not the model. Over 2023–2025, people kept patching this pipeline's 
failures by adding LLM-powered decision points:

- *Query rewriting/decomposition*: an LLM reformulates the user's question before retrieval
- *Routing*: an LLM decides *which* index/retriever to query (vector store vs. graph vs. SQL vs. web)
- *Grading/reflection*: an LLM judges whether retrieved chunks are actually relevant, and re-retrieves if not (Self-RAG, Corrective RAG)
- *Iteration*: multi-hop retrieval where the result of one retrieval informs the next query

Each patch hands a bit more control flow to the model. "Agentic RAG" is the umbrella term 
for any point along this gradient. Push the gradient to its limit — LLM owns the loop entirely, 
retrieval is just a tool it calls when it wants — and yes, you've reproduced exactly the 
Claude Code loop you sketched, with `vector_search` where `grep` would be. Your observation 
that the categories merge at the limit is correct.

*But here's the nuance: most things sold as "agentic RAG" are not at the limit.* 

They're usually a *directed graph with LLM-powered decision nodes* — think LangGraph-style: a router 
node, a rewrite node, a retrieve node, a grade node, a conditional edge back to rewrite, then 
generate. The topology is fixed by the developer; the LLM only picks branches within it. That's 
meaningfully less than Claude Code, where the model decides at every turn what to do next in 
an open-ended loop with no predetermined topology. So one defensible definition is:

- *Classic RAG*: fixed pipeline, zero LLM decisions about control flow
- *Agentic RAG*: developer-fixed topology, LLM-controlled branching within it
- *Agent*: LLM-controlled topology — the loop you described

*The teleological explanation.* 

The other reason Claude Code isn't called RAG while a 
"support copilot" doing nearly identical loops is: the terms describe *purpose*, not mechanism. 
RAG, agentic or not, names systems whose end product is an answer grounded in a corpus — retrieval 
is the point, and the system is read-only with respect to the world. Claude Code's retrieval (grep, 
file reads) is incidental; its point is to *act* — edit files, run tests, commit. We categorize by 
what the system is for and what it can touch, not by its loop structure. By this lens, Anthropic's 
and OpenAI's "deep research" features are the clearest real-world examples of agentic RAG at the 
fully-agentic end: an open-ended agent loop whose only tools are search and fetch, whose only output 
is a grounded answer. Nobody markets them as RAG, which rather proves your point — once the agency 
is obvious, the RAG label gets dropped.

*And the cynical explanation, which deserves mention.* 

"Agentic RAG" is also a marketing term coined by the ecosystem that grew up around RAG — vector 
databases, orchestration frameworks, chunking tools — at the moment plain RAG started looking 
commoditized and agents became the hot category. Calling your product "agentic RAG" lets you 
keep your existing positioning while claiming the new trend. That's not the whole story, but 
it explains why the term is used far more by vendors and framework docs than by research papers, 
which prefer specific names like Self-RAG, ReAct, or multi-hop retrieval.

So to answer "where is the agentic RAG?": it lives in the middle of a spectrum. At one end, a 
static pipeline nobody would call agentic; at the other, a full agent nobody bothers to call RAG. 
"Agentic RAG" names the transitional region — retrieval-centric systems where the LLM has been 
given partial control of the retrieval process but the system's identity is still "answers questions 
over a corpus" rather than "does things in the world." You're right that it's not a third kind 
of thing; it's a waypoint between two kinds, named from the perspective of people who started at 
the RAG end.

== Engineering Closed-Loop
#let a_001 = link(
  "https://dzone.com/articles/graph-rag-closed-loop"
)[#text(fill: blue)[Engineering Closed-Loop]]

Most RAG systems use open-loop:
```text
Query → Retrieve → Generate → Answer
```
Once the answer is generated, the system stops (#a_001).

A closed-loop:
```text
Query → Retrieve → Generate → Validate → Answer → Observe Outcome → Update System
```

The content to update include:
- The embedding index?
- The graph?
- The prompt?
- The ranking function?
- The rule layer?
- The source document?
- The user profile?
- Nothing until a human reviews it?

Feedbacks should not be just thumbs up or thumbs down. The system needs detailed
information about the problems.

When receiving a feedback, the system classifies the feedback and route it 
to the correponding module using a map such as the one below:
```text
Wrong document retrieved      → retrieval index or ranking review
Missing relationship          → graph edge review
Unsupported claim             → generation prompt or validation rule review
Policy violation              → rule layer update or blocklist review
Low usefulness but correct    → personalization or response format update
Repeated user confusion       → explanation template review
Expert correction             → human-approved graph or source update
Latency failure               → retrieval depth, caching, or model routing update
```

*What Feedbacks Should Update*
- Retrieval Weights among vector search, BM25, etc.
- Graph Edges: we may need to add new edges
- Source Knowledge: missing source knowledge
- Prompt/Response Template
- Rule Layer
- The `Query → Retrieve → Generate → Validate → Answer → Observe Outcome → Update System` loop

== Evaluating a Graph-RAG System
(Refer to [4])

*Seven Layers of Evaluation Framework*

=== Layer 1 - Retrieval Quality

Some useful metrics:
- Precision\@k
- Recall\@k
- MRR\@k
- Node recall
- Edge recall
- Path correctness
- evidence Coverage

=== Layer 2 - Relation-Based Reasoning

Ask questions like:
- Did the system identify the correct entity?
- Did it traverse the right relationship?
- Did it avoid irrelevant neighboring nodes?
- Did it distinguish prerequisite, correlation, ownership, and policy relationships?
- Did it explain the evidence path clearly?

Note that without graphs, LLMs can search nodes, normally by keywords. 
BM25 can be a critical
tool. In debugging, for instance, if it fails loading a page, by looking at the 
url, it checks where the url is routed. Once related code is found, it reads the
code, checking for every failure case. 

For each failure case, it traces back, again by keyword search. Note that if 
graphs are available, it can use graphs. But what if the relations were not 
captured during building time? Search on graphs is unreliable, to say the least.
Graphs are at best a complement.

Even without graphs, LLMs can still reason by search. 
One important thing to note is that after LLMs generate answers, we should
ask the LLM to summarize its reasoning, such as:
- Search '/home3/knowledge' to find out how the url is routed
- Found the file: '...'
- Examine the failure case: ...
- Trace back for the reasons why it fails
- ...

The LLM then generate the following relations:
- `url-xxx` `is-routed` `file-name-1`
- `url-xxx` `handled-by` `function-name-1`
- `function-name-1` `fail-on` `failure-case-1`
- `function-name-1` `fail-on` `failure-case-2`
- `failure-case-1` `source-code` `function-name-2`
- `failure-case-1` `source-code` `function-name-2`
- `function-name-2` `fail-on` `failure-case-3`
- ...

This is important for two reasons:
- To explain the problem and how the problem is solved
- The more the system is used, its knowledge base is better

This is called Self-Evolving Knowledge System

=== Layer 3 - Answer Generation Quality

Metrics:
- Factual correctness
- Completeness
- Clarity
- Grounding in retrieved evidence
- Absence of unsupported claims
- Appropriate uncertainty
- Fit to the detected problem
- Specificity
- Actionability: if the query requires actions, check whethere the recommendation
  contains actionable content
- Personalization
- Measurable next step
- Tone and usefulness

=== Layer 4 - Rules of Compliance

Questions to ask:
```text
Does the answer cite supporting evidence?
Does the recommendation match the user’s role?
Does it avoid unsupported claims?
Does it include a measurable next step?
Does it avoid resources the user already completed?
Does it require human approval?
```

=== Layer 5 - Expert and User Value
Ask experts for opinions and recommendations.
```text
The recommendation is technically correct but unrealistic.
The evidence is weak.
The system missed an important contextual clue.
The response is too generic.
The next step is measurable but not meaningful.
```

=== Layer 6 - Latency and Dependability
Metrics:
```text
Entity extraction latency
Graph traversal latency
Vector search latency
Reranking latency
Prompt construction latency
LLM generation latency
Rule validation latency
Total response latency
```

Measure them for P50, P95 and P99.
- P50 measures the normal or typical experience
- P95 measures the experience of users encountering moderately slow requests
- P99 exposes severe tail-latency problems, such as cache misses, garbage
  collection, database contention, retries, or overloaded downstream services.

=== Layer 7 - Closed-Loop System Health
If the system uses feedback (can be from human users or LLMs), 
determine whether that learning is both safe and beneficial.

Evaluate:
```text
Feedback volume by type
Feedback classification accuracy
Percentage routed to human review
Approved vs. rejected graph updates
Prompt or rule changes after feedback
Rollback frequency
Performance before and after updates
Drift by domain or user segment
```

== Contextual RAG
Anthropic publishes an article ([2]), introducting "Contextual Retrieval". The main idea
is to use LLMs to generate a context for a given chunk. It then embeds the context
and the chunk.

Chunk size should be around 500 bytes. Note that if we want to embed chunks (normally we should),
chunks should not be too big.

Here is the prompt the article recommends:
```text
<document> 
{{WHOLE_DOCUMENT}} 
</document> 
Here is the chunk we want to situate within the whole document 
<chunk> 
{{CHUNK_CONTENT}} 
</chunk> 
Please give a short succinct context to situate this chunk within the overall document for the 
purposes of improving search retrieval of the chunk. Answer only with the succinct context and nothing else.
```

#figure(
  image("Images/image_2026061401.png"),
  caption: [Anthropic Contextual Retrieval]
)

Using a rerank step will introduce latency. Normally, in search, we do not want to use rerank.
In more advanced apps, such as deep research, agentic apps, QA, etc., we may use rerank.
As the figure shows, reranking can further improve retrieval quality.
#figure(
  image("Images/image_2026061402.png"),
  caption: [Contextual Retrieval Performance]
)

== UnWeaver
The paper introduces UnWeaver ([5]), a RAG architecture intended to capture much of GraphRAG’s 
benefit without constructing or traversing an explicit knowledge graph. The authors argue that 
conventional VectorRAG retrieves coarse text chunks whose embeddings mix several topics into 
one representation, while GraphRAG improves structure at the cost of substantially greater 
indexing complexity, graph maintenance, and retrieval heuristics. UnWeaver instead keeps 
vector retrieval but inserts an entity-centric semantic layer between queries and source 
chunks. ([6])

During indexing, an LLM extracts named entities or identifiable “ideas” and a description 
of each from every chunk. Occurrences with syntactically equivalent names are merged, 
and their descriptions from different chunks are concatenated into a richer entity 
representation. These entity descriptions are embedded and stored in a vector index, 
together with mappings back to the original chunks. At query time, the system retrieves 
the most similar entities, lets those entities “vote” for the chunks in which they occur, 
and returns the winning original chunks to the answering LLM. Thus, retrieval operates 
on distilled semantic units, but generation remains grounded in the source text rather 
than in generated graph summaries. 

The authors’ main hypothesis is that entity decomposition reduces retrieval noise and 
links information distributed across multiple chunks, thereby supporting both single-hop 
and multi-hop questions without explicit entity-to-entity graph edges. They also formulate 
chunk selection mathematically as an approval-voting or retrieval-alignment problem, 
where relevant entities are voters and chunks are candidates. A variant using Personalized 
PageRank was tested, but the simpler voting-based UnWeaver generally performed as well 
as or better than that graph-like extension, suggesting that graph propagation itself 
contributed little in these experiments. ([arXiv][6])

Across COVID-QA, eManual, Tech-QA, and the multi-hop MuSiQue dataset, UnWeaver consistently 
outperformed Microsoft GraphRAG and generally matched plain VectorRAG closely. It slightly 
exceeded VectorRAG on COVID-QA, eManual, and MuSiQue, but VectorRAG performed better on 
Tech-QA; HippoRAG2 also achieved the strongest result on Tech-QA and MuSiQue. The clearest 
advantage was therefore not a dramatic accuracy gain over VectorRAG, but obtaining competitive 
graph-oriented retrieval quality at far lower indexing and inference cost than full GraphRAG 
systems. ([arXiv][6])

The practical conclusion is more nuanced than the title: VectorRAG may already be sufficient 
for many QA workloads, provided its index is enriched with clean, queryable semantic abstractions 
such as entities or ideas. Full GraphRAG remains potentially useful when explicit relationships, 
topology, ontology-based traversal, or complex graph operations are intrinsically required. 
But when the main objective is simply to retrieve coherent evidence across chunks, UnWeaver 
suggests that entity-enriched vector retrieval may offer a better engineering trade-off 
than building an entire knowledge graph. ([arXiv][6])

=== Voting
The voting is a way to convert entity relevance into chunk relevance. The query first retrieves 
the top-(K) entities by embedding similarity. Each retrieved entity then “votes for” every source 
chunk from which that entity was extracted. Chunks receiving votes from several query-relevant 
entities are ranked above chunks supported by only one entity. In the paper’s terminology, 
entities are the voters, chunks are the candidates, and the system selects several winning 
chunks rather than one winner. ([arXiv][6])

Suppose the query is:

> What affects response time under heavy load?

The entity search returns:
```text
| Retrieved entity      | Source chunks |
| --------------------- | ------------- |
| `response time`       | C1, C2        |
| `load testing`        | C1, C3        |
| `time to first byte`  | C1, C4        |
| `database contention` | C2, C5        |
```

Each entity gives one vote to every chunk associated with it:

```text
C1: response time + load testing + time to first byte = 3 votes
C2: response time + database contention             = 2 votes
C3: load testing                                    = 1 vote
C4: time to first byte                              = 1 vote
C5: database contention                             = 1 vote
```

If the retriever needs three chunks, it chooses C1, C2, and one of C3–C5, subject to 
its tie-breaking or weighting rule.

The paper formalizes this as a binary entity–chunk matrix:

```text
                     C1  C2  C3  C4  C5
response time         1   1   0   0   0
load testing          1   0   1   0   0
time to first byte    1   0   0   1   0
database contention   0   1   0   0   1
```

After entity retrieval, rows corresponding to irrelevant entities are removed. Summing 
the remaining columns gives the basic approval-voting score. The paper leaves the exact 
committee-selection rule open, mentioning possibilities such as ordinary Approval 
Voting, Proportional Approval Voting, or Chamberlin–Courant. ([arXiv][6])

The implementation uses a slightly more elaborate weighted score:

$"score"(c) = "votes"(c) * (1 - "bestRank"(c) / K)$

where:

- `votes(c)` is the number of retrieved entities associated with chunk (c);
- `bestRank(c)` is the zero-based rank of the highest-ranked retrieved entity associated with (c);
- (K) is the number of entities retrieved.

The code first counts how many retrieved entities point to each chunk. It then applies a 
rank discount based on the first—and therefore highest-ranked—entity that supports that chunk. 
Finally, it sorts chunks by this score and keeps the top requested number.

For example, assume three entities are retrieved in this order:

```text
rank 0: response time       → C1, C2
rank 1: load testing        → C1, C3
rank 2: database contention → C1, C4
```

There are six total entity–chunk incidences:

```text
C1: 3 votes
C2: 1 vote
C3: 1 vote
C4: 1 vote
```

The implementation calculates approximately:

```text
C1 = 3/6 × 1       = 0.500
C2 = 1/6 × 1       = 0.167
C3 = 1/6 × 2/3     = 0.111
C4 = 1/6 × 1/3     = 0.056
```

The main part of the voting mechanism is chunks with multiple entities.
For the ones with only one vote, it then selects the ones by chunk-hitting
score of its entity.

*Conclusion*
- The retrieved are chunks, not entities, relations, or other artifacts
- Entities are used to remove 'noise' for the hybrid search
- In SemOS, there are 'entities', 'inventory items', 'metrics' that
  can be used as the 'niddles'.
- We may want to consider 'artifact_categories' to help find the niddles
- Let niddles vote for chunks

[1]: https://arxiv.org/pdf/2603.29875 "UnWeaving the knots of GraphRAG – turns out VectorRAG is almost enough"


== References
[1] From Retrieval to Reasoning (part 1), 
https://dzone.com/articles/graph-rag-closed-loop-retrieval-reasoning

[2] Introducing Contextual Retrieval, 
https://www.anthropic.com/engineering/contextual-retrieval

[3] Closing the Loop in Graph-RAG Systems (part 3), 
https://dzone.com/articles/graph-rag-closed-loop

[4] Evaluating a Graph-RAG System (part 4), 
https://dzone.com/articles/graph-rag-closed-loop-evaluation-system

[5] UnWeaving the knots of GraphRAG – turns out VectorRAG is almost enough
https://arxiv.org/pdf/2603.29875 

[6] https://arxiv.org/pdf/2603.29875
