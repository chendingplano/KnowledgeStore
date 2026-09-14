---
name: [[def:BubbleRAG]]
links: [[RAG, Knowledge Base, Search Engine]]
note_date: 2026/04/19
source-url: https://arxiv.org/pdf/2603.20309
source-date: 2026/03/19
---

## 1. Overview

BubbleRAG is a training-free RAG framework that builds and explores “evidence bubbles” 
(small connected subgraphs) to improve multi-hop reasoning and reduce hallucination.
It represents a shift from “retrieve chunks” to “construct evidence structures”.
It is not just retrieving facts. Instead, it constructs a reasoning path before the LLM
ever sees the data. This can improve multi-hop reasoning, grounding, precision, etc.

## 2. Evidence Bubbles

Evidence Bubbles are small, connected groups of evidence, form a local evidence grapph, built around semantic anchors. Each “bubble” is coherent, multi-hop ready, and structured. A bubble is a graph,
not a collection of chunks. 

```
Query → anchor → expand → connected evidence cluster (bubble)
```

Note that BubbleRAG does not construct a new graph from retrieved chunks for every anchor/query. 
It constructs the KG offline. At query time, it selects local portions of that already-existing graph.

The paper has an **offline indexing phase**. It chunks the corpus, uses an LLM to extract 
triples from every passage, links entities across chunks, and stores the resulting KG. 
The original chunks are retained and linked back to graph elements. ([arXiv][1])

So conceptually:

```text
OFFLINE — done once

documents
   ↓ chunk
chunks
   ↓ LLM triple extraction
entities + relations
   ↓
Global Knowledge Graph
```

Then for each user query:

```text
ONLINE — every query

query
  ↓
LLM derives query concepts
  ↓
find candidate anchors in existing KG
  ↓
take h-hop neighborhoods around anchors
  ↓
graph search / bubble expansion
  ↓
candidate evidence graphs
```

The paper explicitly says that its localized graph is formed by taking the **h-hop neighborhoods 
of anchor nodes and unioning them**. It is not running entity/relation extraction again on those 
chunks. ([arXiv][1])

So the expensive graph extraction is amortized across queries.

### 2.1 Could we replace the offline LLM extraction with spaCy?

Technically, yes. BubbleRAG itself doesn't fundamentally require that the KG have been created by an LLM. Once you have nodes, edges, text representations, embeddings, and provenance, its retrieval algorithm can operate over them.

But I would **not say spaCy is generally "good enough."** spaCy can do excellent deterministic NER, dependency parsing, noun-phrase extraction, rule-based matching, etc. But converting arbitrary technical prose into useful semantic relations is substantially harder.

For example:

> “The temperature monitoring device shall generate an audible alarm when the measured temperature exceeds 8°C for more than 10 minutes.”

A conventional NLP pipeline can fairly reliably find:

```text
temperature monitoring device
audible alarm
8°C
10 minutes
```

The harder part is obtaining useful relations such as:

```text
temperature_monitoring_device
    --shall_generate--> audible_alarm

audible_alarm
    --trigger_condition--> temperature > 8°C

trigger_condition
    --duration--> 10 minutes
```

An LLM is much better at that open-ended semantic normalization.

BubbleRAG places unusual importance on **edges**, not merely entities. It stores rich `(A, R, B)` text in an edge so query concepts can match relations as well as nodes. ([arXiv][1])

For SemOS, a more practical architecture would be:

```text
cheap deterministic extraction
        ↓
NER / terminology / syntax / known patterns
        ↓
high-confidence entities + relations
        ↓
LLM only for ambiguous / semantic / complex relations
        ↓
consolidated KG
```

That could substantially reduce offline LLM cost while retaining the semantic relations BubbleRAG needs.
But how to determine which can be done deterministically (i.e., cheaply) and which requires LLMs
is undeterministic.

### 2.2 What actually happens to the bubbles?

It is **not really**:

```text
LLM generate anchor A, B and C

anchor A → bubble A

anchor B → bubble B

anchor C → bubble C

LLM reads A + B + C independently
```

Instead, think of bubbles as **search frontiers growing from multiple anchor groups and trying to meet each other**. IMPORTANT part is 'meet each other'! Suppose the query is:

> Who played the main villain in the movie where Keanu Reeves and Laurence Fishburne starred together?

BubbleRAG might derive anchor groups roughly corresponding to:

```text
S1 = {Keanu Reeves, K. Reeves, ...}
S2 = {Laurence Fishburne, ...}
S3 = {movie, film, ...}
S4 = {main villain, antagonist, ...}
```

Importantly, an **anchor group** is not itself a bubble/evidence graph. It contains alternative graph realizations of one query concept. BubbleRAG intentionally keeps multiple possibilities rather than committing prematurely to one node. ([arXiv][1])

Now imagine simultaneous expansion:

```text
Keanu Reeves             Laurence Fishburne
      \                         /
       \                       /
        ─────── The Matrix ────
                    |
              Agent Smith
                    |
               Hugo Weaving
```

The search is essentially multi-source Dijkstra. Each frontier grows preferentially through nodes semantically relevant to the query. When frontiers originating from different anchor groups **collide**, BubbleRAG backtracks the paths and fuses them into a connected **Candidate Evidence Graph (CEG)**. ([arXiv][1])

So the interesting thing is precisely the **collision/connection between bubbles**.

## The lifecycle is actually closer to this

```text
                 Query
                   │
                   ▼
        ┌─────────────────────┐
        │ Semantic concepts   │
        └─────────────────────┘
                   │
          ┌────────┼────────┐
          ▼        ▼        ▼
        Group A  Group B  Group C
          │        │        │
          ▼        ▼        ▼
        anchors  anchors  anchors
          │        │        │
          └──── bubble expansion ────┐
                     │               │
                 collisions          │
                     │               │
                     ▼               ▼
                  CEG 1    CEG 2    CEG 3 ...
                     │
                     ▼
                  ranking
                     │
               top-N CEGs
                     │
                     ▼
            LLM-guided expansion
                     │
                     ▼
           expanded CEG 1 ... N
                     │
                     ▼
                  MERGE
                     │
                     ▼
          Unified Evidence Graph
                     │
                     +
            source text chunks
                     │
                     ▼
                    LLM
                     │
                     ▼
                  Answer
```

That final **MERGE** is explicitly part of BubbleRAG. After reasoning-aware expansion, the top-N expanded CEGs are merged into a single `G_final`; duplicate nodes/edges are consolidated, source chunks are retrieved through provenance pointers, and the LLM receives both serialized graph triples and original text. ([arXiv][1])

What if they don't meet? A few things can cause this happening:
- The anchors are truly independent (the quality of anchors)
- The global graph is not good enough (missing critical entities and relations)
- Need more hops: deep relations require more hops

On the other hand, BuggleRAG does allow multiple CEGs (Candidate Evidence Graphs). 

### 2.3 Handling Multiple CEGs

Once BubbleRAG has discovered and ranked the CEGs, it does **not** ask the LLM to examine every 
graph candidate and freely wander. It first algorithmically ranks them and retains only the 
**top-N**. ([arXiv][1])

Then comes what the paper calls **Reasoning-Aware Expansion**.

Suppose the CEG has already discovered:

```text
Keanu Reeves
      ↓
 The Matrix
      ↑
Laurence Fishburne
```

That's excellent evidence for:

> movie where Keanu Reeves and Laurence Fishburne starred together

But it hasn't answered:

> who played the main villain?

So BubbleRAG exposes the immediate neighbors of this CEG:

```text
The Matrix
   ├── release_date → 1999
   ├── director → Wachowskis
   ├── antagonist → Agent Smith
   ├── genre → science fiction
   └── producer → Joel Silver
```

Now the LLM sees the query + current evidence + candidate neighbors and says, effectively:

```text
antagonist → Agent Smith
```

is promising, while the others aren't.

Expand again:

```text
Agent Smith
    ├── played_by → Hugo Weaving
    ├── species → program
    └── appears_in → ...
```

LLM chooses:

```text
played_by → Hugo Weaving
```

Now there is enough evidence.

The paper explicitly says expansion continues until either the configured maximum depth is reached **or the LLM selects no more nodes / determines that current evidence is sufficient**. ([arXiv][1])

### 2.4 Two different kinds of expansion

This distinction is probably the most important architectural point.

**Bubble Expansion is algorithmic.** It starts with all anchor groups and performs a semantic-cost-guided graph search. Its purpose is to **discover connecting evidence structures**. It uses embeddings/cosine similarity and graph algorithms, not repeated LLM reasoning. ([arXiv][1])

**Reasoning-Aware Expansion is LLM-driven.** It operates only on the best CEGs and asks, essentially, **“Given what I know now, which neighboring graph elements should I inspect next?”** ([arXiv][1])

So:

```text
Stage 1
Anchor groups
      ↓
algorithmic expansion
      ↓
connect anchors
      ↓
CEGs


Stage 2
Top CEGs
      ↓
LLM reasoning
      ↓
"What evidence am I still missing?"
      ↓
select neighbors
      ↓
expand
      ↓
enough evidence?
   no ↺    yes ↓
             answer
```

This separation is quite elegant because the LLM is **not paying attention to every possible graph traversal**. Cheap graph algorithms perform broad exploration; expensive LLM reasoning is reserved for the small number of promising evidence structures.

## 3. Thoughts

Its deepest idea isn't simply "LLM generates several search anchors." The more interesting pattern is:

> **LLM for semantic hypothesis formation → cheap algorithms for broad evidence discovery → LLM for selective investigative exploration.**

That is remarkably close to the **candidate discovery → investigative search** model (i.e., the 
exploration model) we discussed for SemOS. The KG is effectively providing a constrained search 
space in which the second-stage investigation can operate, while Bubble Expansion solves the 
important problem of **connecting independently discovered clues before handing them back to 
the LLM**. ([arXiv][1])

Do we want to use this solution?
- Build a global graph
- Generate anchors for a query
- Extract the bubbles (local graph) by these anchors with h-hops
- Expand them, check whether they meet, generate CEGs
- Rank CEGs
- Examine CEGs to determine whether they are good enough
- If not, continue expanding them until either a maximum hop is reached or 
  CEGs are good enough

Essentially, it achieves the same thing as the exploration model does, or it is an exploration
model, implemented through graphs. 

Building graphs is expansive and undeterministic. It requires process inputs, build a global
graph before they can be used by LLMs. Codex and Claude Code proves that this is unnecessary.

My conclusion (2026/09/13) is: 
we do not need to use graphs. Instead, rely on model's capabilities. Use harness such as Codex, Pi, etc.

## 4. How BubbleRAG works

### 4.1 Anchor selection

It identifies key semantic anchors from the query. These are starting points for retrieval.

### 4.2 Bubble expansion

Expand from anchors using heuristics, Build Candidate Evidence Graphs (CEGs) ([Goatstack][1]), which connect related pieces, forming a local graph instead of flat chunks.

### 4.3 Composite ranking

Rank candidate bubbles using relevance, coverage (multi-hop completeness) and coherence, not just “best chunk”, but best evidence structure.

## 5. Reasoning-aware expansion

Iteratively refine bubbles based on reasoning needs, adding missing links if needed.

## 6. Final generation

Feed the best bubble(s) into LLM, which generates answer grounded in structured evidence.

This paper is essentially doing:

> **“Global graph construction on-the-fly during retrieval”**

Compare with your earlier mental models:

| Idea            | Equivalent in BubbleRAG |
| --------------- | ----------------------- |
| Super tree      | ❌ (not used)            |
| Global index    | ✅ (anchors)             |
| Tree traversal  | ❌                       |
| Graph traversal | ✅ (bubbles)             |

## 7. Example

> “Which university did the CEO of the company that acquired Instagram attend?”

This requires **multiple reasoning hops**:

1. Instagram → acquired by → Facebook
2. Facebook → CEO → Mark Zuckerberg
3. Mark Zuckerberg → education → Harvard

Final answer: **Harvard University**

The keywords from this query should include:
* CEO: but we don't know the company ('Facebook') yet (can be a problem)
* university: but we don't know the university name yet (can be problem)
* Instagram: this is the only thing certain

It uses the keywords to search all the nodes, which can return many. The critical part is to pick the 
right nodes to start with. In this example: 
* Pick 'Instagram' then lets LLM to form a query to expand: "Who acquire Instagram?" It should return only one (very good).
* Pick 'CEO', query to expand: "it with Instagram, the effect is similar to picking 'Instagram' (good)
* Pick 'CEO' with 'university': normally it should yield not good results because it can pick tons of 
nodes.

it can pick tons of nodes.

Typical RAG might retrieve:

* Chunk A: “Instagram was acquired by Facebook in 2012”
* Chunk B: “Mark Zuckerberg is the CEO of Facebook”
* Chunk C: “Zuckerberg attended Harvard”

Problems are these chunks are independent. The LLM must connect them and verify consistency. This often leads to missing links, hallucination, wrong joins.

# 🫧 How BubbleRAG handles it

### Step 1: Anchor selection

From the query, BubbleRAG extracts anchors like:

* “Instagram”
* “acquired”
* “CEO”
* “university”

These are directly from the query. These guide retrieval

## Step 2: Build the first “bubble”

Start with anchor Instagram:

Retrieve and connect:

```
Instagram ──acquired by──> Facebook
```

Now we have a **connected mini-graph**, not just a chunk.

## Step 3: Expand the bubble (multi-hop)

From **Facebook**, expand:

```
Facebook ──CEO──> Mark Zuckerberg
```

Now the bubble becomes:

```
Instagram → Facebook → Mark Zuckerberg
```

## Step 4: Continue expansion

From **Mark Zuckerberg**:

```
Mark Zuckerberg ──educated at──> Harvard University
```

Final bubble:

```
Instagram
   ↓ acquired by
Facebook
   ↓ CEO
Mark Zuckerberg
   ↓ educated at
Harvard University
```

👉 This is the “evidence bubble”

# 🧠 Why this is powerful

## 1. Explicit reasoning chain

The system *constructs*:

* a connected path
* with semantic relationships

👉 The reasoning is no longer implicit in the LLM

## 2. Coherent evidence (not scattered)

Instead of 3 unrelated chunks:

* Everything is **connected**
* Missing links are obvious

## 3. Guided expansion

BubbleRAG doesn’t expand randomly:

* It expands only along meaningful relations
* Stops when the query is satisfied

## 4. Built-in verification

If something doesn’t connect:

* the bubble is incomplete
* it can:

  * expand further
  * or discard the candidate

# ⚖️ Compare side-by-side

### Standard RAG

```
[Chunk A] Instagram → Facebook
[Chunk B] Facebook → CEO
[Chunk C] Zuckerberg → Harvard

LLM must stitch everything together
```

### BubbleRAG

```
Instagram → Facebook → Zuckerberg → Harvard

Single connected structure
```

# 🔥 Where the reasoning actually happens

Important subtlety is BubbleRAG shifts reasoning from the LLM → into the retrieval layer, instead of LLM doing all reasoning. Retrieval builds a reasoning-ready structure. LLM just reads and answers.

# 🧩 Another quick example (more abstract)

### Query:

> “Why did the company’s stock drop after the product launch?”

BubbleRAG might build:

```
Product Launch
   ↓ caused
Negative Reviews
   ↓ led to
Customer Churn
   ↓ impacted
Revenue Decline
   ↓ caused
Stock Drop
```

This is causal reasoning encoded as a graph. It should first resolve "the product". If users mentioned
a product in the current session, of there is only one product in the company, resolve it (resolved in
context). Otherwise, LLMs should clarify it from users.

Now the query is modified as:
> “Why did the company’s stock drop after Product A launch?”

LLM should generate find content by "Product A Launch". If not found, just tell users it could not 
find information about the product launch. 

Otherwise, if Product A has multiple launches, it should retrieve the last launch since users did not specify
which launch. It is important for LLMs to notify the choice (i.e., choosing the latest launch).

It then collects all the information about the features, the product, comments, reviews, discussions 
(may need to search the Internet), related documents, revenue and other financial data, etc.

Do we need a graph? Or do we even need to extract entities and relations?
In this example, a file system works equally well, if not better:
- All the documents are saved in files, with meaningful file names, constructed in a Semantic Tree.
- Large documents are chunked into chunks by topics
- Summary trees

## Picking Anchors

One of the most critical factors in BubbleRAG is picking the right starting anchors. In the above CEO example,
if it picks 'university', there are thousands of universities. Expanding this anchor can lead to a quite big graph. 
Adding the recursive expanding nature, this 'dumb' will create a 'sub-graph' that is too big to be useful at all.

BubbleRAG does not treat all anchors equally or expand them blindly. Anchors are not chosen uniformly; they are scored,
pruned, and constrained by query-dependent relevance and structural signals.

**Scoring**

Scores are related to:
* Branching factor
* Anchor type 
* semantic similarity to query
* entity specificity
* context dependency
* expected informativeness for reasoning path
* Time?
* Metadata?
* (anything else?)

In the CEO example:

| Anchor     | Likely score | Reason                    |
| ---------- | ------------ | ------------------------- |
| Instagram  | ⭐⭐⭐⭐⭐        | central entity            |
| CEO        | ⭐⭐⭐⭐         | role-relevant             |
| acquired   | ⭐⭐           | relation word (weak node) |
| university | ⭐            | too general, too broad    |


**Type-aware filtering**

* entities (Instagram, Facebook)
* relations (acquired, founded)
* generic concepts (university)

**Expansion budget constraint**

* expansion is budget-limited
* e.g. top-K neighbors per hop
* early stopping if:

  * relevance drops
  * path already satisfies query

**Query-conditioned expansion**

Expansion is not just expanding a node. It is expand node in a direction that increases query coverage

**Beam search style pruning**

Instead of full expansion, it keeps top-N partial bubbles at each step

## Anchor Design

Even with these safeguards, BubbleRAG-like systems can still struggle with:

1. Poor anchor extraction: If entity detection is weak → wrong seeds
2. Over-general nodes slipping through: Like “university”, “company”, “country”
3. Over-expansion in dense knowledge graphs

The design of anchors should:

1. Entity-centric anchoring: Only allow named entities, not abstract nouns
2. Query graph alignment: Match anchors to dependency parse of query, relation structure of question

## References
\[1\]: https://goatstack.ai/articles/2603.20309?utm_source=chatgpt.com "BubbleRAG: Evidence-Driven Retrieval-Augmented ..."

