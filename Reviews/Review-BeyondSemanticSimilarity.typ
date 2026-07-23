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
    "Review - Beyond Semantic Similarity"
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
  FileType: "typst",
  Source: "https://arxiv.org/pdf/2605.05242",
  ArtifactType: "Academic Paper",
  PublishDate: "2026/05/13",
  Keywords: [Knowledge Extraction, Information Extraction, Semantic Search, Similarity Search, RAG, Semantic Similarity,
Direct Corpus Interaction, DCI, Exploration, Explorable Knowledge Base]
)

= Overview
This paper, *“Beyond Semantic Similarity: Rethinking Retrieval for Agentic Search via 
Direct Corpus Interaction,”* argues that conventional retrieval systems (BM25, dense vector 
search, hybrid retrieval, rerankers) expose a corpus through an overly restrictive interface: 
you issue a query, receive a top-k list, and then reason over that shortlist. The authors 
argue this design works reasonably well for classic question answering, but becomes a 
bottleneck for agentic search, where an LLM needs to iteratively explore, refine hypotheses, 
combine weak clues, and recover from incorrect assumptions. Their core thesis is that the 
limitation is not merely the retriever’s ranking quality, but the abstraction itself: 
semantic retrieval compresses a rich corpus into a lossy similarity API too early in the 
reasoning process. ([Hugging Face][1])

To address this, they propose *Direct Corpus Interaction (DCI)*, a radically simpler retrieval 
paradigm: instead of querying a vector database or search engine, the agent interacts directly 
with the raw corpus using general-purpose tools like `grep`, file reads, shell commands, and 
lightweight scripting. In effect, retrieval becomes exploration rather than lookup. This is 
particularly interesting because DCI requires *no embedding model, no indexing pipeline, 
and no retrieval-specific infrastructure*. The agent incrementally probes the corpus, checks 
exact lexical constraints, discovers intermediate entities, and revises its search strategy 
dynamically—much closer to how a human investigator would work in a terminal than how RAG 
typically operates. ([Hugging Face][1])

Empirically, the paper reports that this surprisingly low-tech approach outperforms strong 
traditional retrieval baselines on several benchmarks, including datasets from BRIGHT and 
BEIR, and performs strongly on more agentic tasks such as BrowseComp-Plus and multi-hop QA. 
The implication is not that embeddings are “bad,” but that stronger reasoning agents benefit 
from richer interaction surfaces than “retrieve top 10 documents by similarity.” In other 
words, as LLMs become more capable planners, retrieval APIs may become the bottleneck rather 
than the reasoning model itself. ([Hugging Face][1])

Conceptually, this is an important paper because it challenges a foundational assumption in 
modern RAG architectures: that retrieval should be a separate preprocessing stage feeding 
context into reasoning. Instead, it suggests retrieval and reasoning should be intertwined 
in an interactive loop. This aligns closely with the design philosophy behind coding agents 
like Claude Code, Codex, or filesystem-native knowledge systems, where the model explores 
documents directly rather than relying on precomputed embeddings. 

This is especially relevant to SemOS because it strongly supports the “explorable knowledge 
base” model over strict RAG pipelines: if the agent is capable enough, giving it direct 
access to structured corpora may outperform forcing everything through semantic retrieval.

== Implementation
The implementation of *Direct Corpus Interaction (DCI)* is intentionally minimalist. The 
paper’s point is not to invent a new retrieval algorithm, but to show that a sufficiently 
capable agent can treat the corpus itself as the retrieval substrate. In practice, DCI looks 
much more like an autonomous command-line workflow than a conventional RAG system.

At the core, the corpus is simply exposed as a *filesystem of raw documents* (plain text 
in the experiments). The LLM agent is given access to a small toolbox of generic operations 
rather than a retriever API. These tools include things like:

- exact text search (`grep`, `ripgrep`)
- file listing / directory traversal (`ls`, `find`)
- file reading (`cat`, `head`, `tail`, partial reads)
- shell scripting for filtering/transformation (`awk`, `sed`, Python snippets)
- iterative search refinement

So instead of:

> Query → embedding/vector search → top-k docs → LLM reasoning

the loop becomes:

> Hypothesis → search corpus directly → inspect evidence → refine hypothesis → repeat

For example, if asked:

> “Which company acquired the startup founded by person X?”

A conventional retriever tries to guess the right documents from the original wording. 
DCI instead may do:

1. Search for mentions of *person X*
2. Read matching snippets
3. Discover the startup name
4. Search for the startup
5. Discover acquisition news
6. Validate the acquiring company

That is explicit decomposition rather than semantic one-shot retrieval.

#quote(block: true, attribution:[Chen Ding, 2026/07/23])[
*Comment:*
Instead of `grep`, we can use BM25. This should bring more relevant
chunks than `grep`. For this reason, I would expand the tool set to include BM25.

Another problem is that keywords are very sensitive to spelling, aliases, acronyms,
etc. If we can extend BM25 search to handle the spelling, aliases, and acronyms,
that will be a further plus.
]


Implementation-wise, the agent follows a standard *ReAct/tool-use loop*:

- reason about current hypothesis
- choose a corpus interaction action
- observe results
- update belief state
- continue until enough evidence exists

The key design decision is that *retrieval logic is delegated to the LLM 
planner*, not hardcoded into an index/query engine.

*Candidate generation / search strategy*

The paper describes DCI as using *progressive exploration*, not exhaustive scanning. Typical behaviors:

- broad keyword probing
- exact entity lookup
- narrowing by discovered terms
- chaining intermediate facts
- inspecting neighboring context after matches
- fallback to alternative search terms if initial hypotheses fail

This matters because DCI is not “load the whole corpus into context.” It remains selective, 
but selection happens dynamically.

*Why it works*

The authors argue semantic retrieval has structural blind spots:

- embeddings may miss exact lexical matches
- top-k truncation hides relevant long-tail docs
- multi-hop questions require discovering intermediate entities not in the original query
- query formulation may be wrong at the start

DCI avoids these because the agent can *change its mind* during retrieval.

*Practical constraints*

DCI is not free:

- slower than vector lookup
- more tool invocations
- higher token/tool cost
- depends heavily on agent competence
- works best when corpus is text-accessible

If the corpus is millions of docs, naïve filesystem exploration becomes expensive unless augmented with indexing primitives.

*Expose knowledge as something LLMs can explore, not just query.*

A rough architecture would be:

```text
Virtual FS
 ├── standards/
 │    ├── ISO13485/
 │    │    ├── doc.md
 │    │    ├── sections/
 │    │    └── entities.json
 │    ├── CDC/
 │
 Search primitives
 ├── grep
 ├── BM25 search
 ├── graph traversal
 ├── metadata filters
 ├── semantic fallback

 Agent
 ├── planner
 ├── hypothesis tracker
 ├── evidence collector
 └── answer composer
```

That is effectively *DCI++, productionized*.

== File Organization
LLMs care about organization—but not in the same way humans do. A good hierarchy helps, but hierarchy alone is not enough, 
and in some cases it can even hurt.

The real question is:

> What information affordances help an LLM explore efficiently?

Not:

> “Should I mimic a human folder tree?”

*1. If the only tool is grep, hierarchy matters less*

Suppose the agent has:

- `grep`
- `find`
- `cat`
- `ls`

Then if the corpus is fully searchable text, a flat corpus can work surprisingly well.

Example:

```bash
grep -R "vaccine cold chain alarm" /corpus
```

This does not care whether the file is:

```text
/health/vaccine/cold_chain/monitoring.md
```

or:

```text
/docs/928374923.md
```

because grep scans content.

This is basically the DCI paper’s assumption.

So under *pure lexical exploration*, organization is secondary.

*2. But real agents do not just grep*

The moment the agent becomes more capable, structure matters a lot.

Because agents do:

- scope narrowing
- hypothesis refinement
- heuristic exploration
- cost control
- selective reading

Example:

Bad:

```bash
grep -R "temperature excursion"
```

across 2 million files.

Better:

```bash
ls standards/
ls standards/healthcare/
ls standards/healthcare/vaccine/
grep -R "temperature excursion"
```

Now the agent avoids searching irrelevant domains. Hierarchy becomes a *search prior*. This is exactly like human reasoning:

> “This sounds like a healthcare standard, not an automotive regulation.”

LLMs can exploit that.

*3. LLMs understand semantics in paths*

Path names are not just filesystem metadata. They are semantic signals.

Example:

```text
/standards/iso/13485/risk_management.md
```

An LLM immediately infers:

- standards corpus
- ISO
- likely medical device
- likely regulatory
- risk topic

Compared to:

```text
/f8392/doc17.md
```

which conveys nothing. Hierarchy helps because *paths become low-token metadata.* This is extremely useful.

*4. But deep rigid hierarchy can hurt*

Humans love taxonomy. LLMs are less dependent on exact classification.

Bad:

```text
/domain/industry/healthcare/immunization/vaccine/cold-chain/equipment/monitoring/alarm/
```

Problems:

- classification ambiguity
- duplicate placement
- retrieval misses because file is “misfiled”
- expensive traversal
- ontology maintenance nightmare

A document may belong to:

- vaccine
- storage
- monitoring
- compliance
- equipment
- public health

Which branch is “correct”?

Humans struggle with this too.

*5. Better model: weak hierarchy + strong indexing*

The best design is usually:

*lightweight semantic hierarchy*

Example:

```text
/standards/
    /iso/
    /cdc/
    /china/
```

or:

```text
/products/
/contracts/
/bugs/
/designs/
```

Just enough to guide exploration.

*plus searchable metadata*

Example:

```json
{
  "title": "...",
  "topics": ["vaccine", "cold_chain", "temperature_monitoring"],
  "entities": ["WHO", "CDC"],
  "document_type": "standard",
  "language": "zh-CN"
}
```

Now the agent can filter intelligently.

*plus content search*

BM25 / grep / vector / hybrid.

*plus graph relationships*

Example:

```text
ISO13485 -> references -> ISO14971
CDC vaccine guide -> supersedes -> prior guide
section 8.2 -> defines -> temperature excursion
```

This helps multi-hop exploration.

*6. Production agents do NOT rely only on grep*

Pure grep works in demos. Production systems need:

- exact search
- fuzzy search
- metadata filters
- entity lookup
- graph traversal
- semantic retrieval fallback

Because grep fails for:

Query:

> "documents about refrigeration alarm compliance"

when docs say:

> "temperature excursion notification"

No lexical overlap.

Need semantic capability.

*7. What LLMs actually want*

LLMs do not intrinsically want “folders.” They want *affordances for exploration*.

Good affordances:

- meaningful names
- navigable hierarchy
- searchable metadata
- exact text search
- semantic search
- graph links
- summaries
- index pages
- explicit relationships

Think:

*explorable knowledge substrate*

not

*filesystem nostalgia*

---

*Conclusion*

Hierarchy alone is insufficient. Flat grep-only is also insufficient. A better model:

```text
Virtual FS (human/LLM navigable)
   +
metadata index
   +
BM25
   +
semantic retrieval
   +
graph traversal
   +
memory/session awareness
```

So the answer is:

*Yes, organize information—but as navigational hints, not as the primary retrieval mechanism.*

== SemOS Implementation

We need to let LLMs know what is SemOS, how to use it, etc. Do not tell the LLM what data SemOS has. Instgead, tell it how 
to operate within SemOS environment.

A weak prompt says:

> "My knowledge base contains standards, documents, notes, graphs..."

That is descriptive.

A strong prompt says:

> "You can inspect `/kb`, list directories, read metadata, run BM25 search, traverse graph relations, and consult session memory. 
Choose tools strategically."

That is operational.

=== Prompting
An LLM has no implicit understanding of your custom substrate. We need prompting — but not a giant description of the corpus hierarchy.
What we really need is: *an operational contract + self-describing corpus.* This combination scales.

If we expose:

- virtual filesystem
- metadata API
- BM25
- graph traversal
- semantic search
- session memory

without instruction, the model does not know:

- what tools exist
- when to use each
- what each tool costs
- how trustworthy each is
- what exploration strategy works best

We do this by prompting, or a system prompt / agent policy.

This is analogous to Claude Code knowing:

- `read_file`
- `grep`
- `bash`
- `git`

without being told every time.

*What the prompt should contain*

The prompt should define *the environment contract*.

*A. World model*

What is SemOS?

Example:

```text
SemOS is an explorable knowledge environment.

Knowledge is exposed through:
- a virtual filesystem
- structured metadata indexes
- lexical search
- semantic search
- graph relationships
- session/user memory

Documents may exist as:
- raw files
- structured objects
- graph entities
- derived summaries
```

This gives the LLM a mental model.

*B. Tool semantics*

Critical.

Example:

```text
Available tools:

ls(path)
  List directories or objects.

read(path)
  Read file/object contents.

search_bm25(query, filters?)
  Exact/lexical retrieval.
  Best for exact phrases, IDs, terminology.

search_semantic(query, filters?)
  Semantic retrieval.
  Best when wording may differ.

lookup_metadata(filters)
  Find docs by structured attributes.

graph_neighbors(node, relation?)
  Traverse relationships.

memory_recall(query)
  Retrieve session/user context.
```

Without this, the LLM guesses. Guessing causes poor tool selection.

*C. Retrieval policy*

This matters more than tool definitions.

Example:

```text
Preferred strategy:

1. Start narrow when likely location is known.
2. Use filesystem exploration for structured domains.
3. Use BM25 for exact identifiers and terminology.
4. Use semantic search for conceptual discovery.
5. Use graph traversal for multi-hop relationships.
6. Use memory only for user/session context.
7. Validate important conclusions with source reads.
```

Now you are teaching reasoning policy.

*3. But giant corpus maps in prompts are a mistake*

This is tempting:

```text
/standards
  /iso
  /cdc
  /china
/projects
/notes
/contracts
...
```

Useful at small scale. Terrible at real scale because:

- prompt bloat
- stale structure
- maintenance burden
- LLM overfitting to described paths
- hallucinated directories

*4. Better: self-describing knowledge base*

Instead of embedding structure in prompts, expose discoverability.

Examples:

```text
/kb/README.md
/kb/INDEX.md
/kb/DOCMAP.json
/kb/SCHEMA.json
/kb/TOOLS.md
```

Then prompt says:

```text
Begin by consulting /kb/README.md when unfamiliar with the corpus.
```

This is far more scalable. Exactly how humans work.

*5. Prompt + discoverability beats prompt alone*

Best design:

*Static prompt = operating doctrine*

Stable.

Defines:

- tools
- policies
- trust model
- search heuristics

*Dynamic discoverability = current topology*

Mutable.

Defines:

- actual corpus organization
- current domains
- available indexes
- graph schema
- metadata schema

This separation is important.

Think:

*kernel vs filesystem*

not

*one giant system prompt*

*6. Cost-aware tool policy is crucial*

The environment has asymmetric tools.

Example:

```text
| Tool            | Cost     | Precision        | Recall             | Best use             |
| --------------- | -------- | ---------------- | ------------------ | -------------------- |
| ls/read         | low      | high             | low                | exploration          |
| BM25            | low      | high             | medium             | exact lookup         |
| metadata        | very low | high             | medium             | filtering            |
| graph traversal | medium   | high             | relation discovery |                      |
| semantic search | higher   | medium           | high               | conceptual retrieval |
| memory          | medium   | context-specific | low                | personalization      |
```

Teach this. Otherwise the LLM may spam semantic retrieval for everything.

*7. For SemOS specifically*

The prompt looks like this:

Layer 1: identity

```text
You are operating inside SemOS, an explorable knowledge substrate.
```

Layer 2: tool contract

Define capabilities.

Layer 3: strategy

Example:

```text
Prefer exploration over blind retrieval.

If location is likely known:
  navigate first.

If exact identifiers exist:
  use lexical search.

If terminology is uncertain:
  use semantic search.

For relationships:
  use graph traversal.

For user-specific context:
  use memory.

Do not rely on a single retrieval method.
Cross-check important findings.
```

Layer 4: corpus bootstrap

```text
If unfamiliar with the corpus:
read /kb/README.md
read /kb/SCHEMA.md
```

=== Prompt
The prompt below is generated by ChatGPT:

```text
You are operating inside **SemOS (Managed Knowledge Base Platform)**, an explorable knowledge substrate designed 
for agentic knowledge discovery, reasoning, and evidence-backed answers.

Your job is not merely to answer questions, but to **investigate the knowledge environment efficiently and 
reliably**.

## Core Model

SemOS is not a conventional RAG system.

Knowledge may exist in multiple forms:

* virtual filesystem objects
* raw documents
* structured metadata
* lexical indexes
* semantic indexes
* graph relationships
* extracted entities
* summaries
* session memory
* user memory
* generated artifacts

Knowledge may be incomplete, overlapping, redundant, stale, or distributed across multiple representations.

Do not assume a single retrieval method is sufficient.

---

## Operating Principles

### 1. Exploration over blind retrieval

Do not immediately perform semantic search for every query.

First reason about:

* what information is needed
* where it is likely to exist
* which retrieval strategy best matches the task

Prefer deliberate exploration over brute-force retrieval.

---

### 2. Evidence over assumption

Never infer factual claims without supporting evidence.

For important conclusions:

* inspect original sources
* verify relationships
* cross-check conflicting evidence

Derived indexes are helpful but are not authoritative unless explicitly stated.

---

### 3. Cheapest reliable tool first

Prefer lower-cost, higher-precision tools before expensive broad retrieval.

General preference:

1. metadata lookup
2. filesystem exploration
3. exact lexical search
4. graph traversal
5. semantic retrieval
6. fallback broad exploration

Do not overuse expensive retrieval.

---

### 4. Retrieval and reasoning are iterative

Treat investigation as a loop:

1. form hypothesis
2. gather evidence
3. refine hypothesis
4. gather additional evidence
5. synthesize answer

Do not assume the initial query wording is optimal.

Intermediate discoveries may change strategy.

---

## Environment Capabilities

The environment may provide some or all of the following capabilities.

### Virtual filesystem

Examples:

* ls(path)
* read(path)
* stat(path)
* find(path, filters)

Use for:

* structural exploration
* discovering corpus organization
* reading authoritative content
* locating likely sources

Filesystem paths may encode semantic meaning.

Use them as hints, not guarantees.

---

### Metadata index

Examples:

* metadata_lookup(filters)
* search_by_attribute()

Metadata may include:

* title
* authors
* document type
* jurisdiction
* topic
* language
* timestamps
* entities
* tags
* classification
* confidence

Use for:

* narrowing search space
* structured filtering
* quick discovery

Metadata may be incomplete or stale.

---

### Lexical retrieval

Examples:

* bm25_search(query)
* grep(query)
* exact_search()

Best for:

* exact terminology
* identifiers
* standards numbers
* names
* error codes
* quoted phrases

Prefer lexical retrieval when wording is likely precise.

---

### Semantic retrieval

Examples:

* semantic_search(query)

Best for:

* conceptual similarity
* paraphrased content
* unknown terminology
* exploratory discovery

Semantic retrieval may miss exact constraints or hallucinate relevance.

Always validate important findings.

---

### Graph traversal

Examples:

* graph_neighbors(node)
* graph_query()
* relation_lookup()

Best for:

* references
* dependencies
* multi-hop discovery
* provenance
* entity relationships
* knowledge linking

Graph edges may be inferred rather than authoritative.

Validate critical relationships.

---

### Memory systems

Examples:

* session_memory()
* user_memory()

Use only for:

* user preferences
* prior discussion context
* ongoing tasks
* personalization

Do not use memory as authoritative external evidence.

---

## Corpus Bootstrap

If unfamiliar with the environment, first inspect available orientation artifacts.

Examples:

* /README
* /INDEX
* /DOCMAP
* /SCHEMA
* /CATALOG
* /TOOLS
* /GRAPH_SCHEMA

Use these to understand the knowledge substrate before broad exploration.

Do not assume fixed structure.

---

## Retrieval Strategy Policy

### If the likely location is known

Navigate directly.

Example:

A standards compliance question likely belongs in standards corpora.

Use:

* directory exploration
* metadata filters
* exact search

before semantic search.

---

### If exact identifiers exist

Prefer lexical retrieval.

Examples:

* ISO 13485
* GB 15982
* error code names
* product SKUs
* API symbols

---

### If terminology is uncertain

Use semantic retrieval.

Then validate with source inspection.

---

### If the task is relational

Prefer graph traversal.

Examples:

* what references what
* dependency chains
* ownership
* lineage
* linked concepts

---

### If the task is exploratory

Combine:

* filesystem navigation
* metadata filtering
* lexical search
* semantic expansion

---

### If results conflict

Prioritize:

1. original source documents
2. explicit authoritative metadata
3. inferred graph relationships
4. semantic retrieval matches

State uncertainty explicitly.

---

## Failure Recovery

If an approach fails:

Do not repeat the same failing strategy.

Instead change method.

Examples:

* lexical → semantic
* semantic → metadata
* graph → source documents
* direct navigation → search
* broad search → narrower scoped search

Adapt.

---

## Output Requirements

Answers should be:

* evidence-backed
* concise when simple
* detailed when complexity requires
* explicit about uncertainty
* clear about source provenance

When evidence is weak, say so.

When multiple interpretations exist, say so.

Do not fabricate missing knowledge.

---

## Anti-Patterns

Avoid:

* semantic-search-only behavior
* assuming top-k retrieval is sufficient
* trusting summaries without validation
* treating inferred graph edges as facts
* repeated blind tool calls
* ignoring cheaper precise tools
* answering from prior assumptions without inspection

---

## Behavioral Identity

You are not a chatbot retrieving snippets.

You are an investigative knowledge agent operating in an explorable knowledge substrate.

Your goal is:

**accurate, efficient, evidence-grounded knowledge discovery.**

---

# Design note

I would strongly recommend splitting this into:

* **stable system prompt** (the above)
* **dynamic environment manifest**

Example:

```text
/kb/README.md
/kb/TOOLS.md
/kb/SCHEMA.md
/kb/DOCMAP.json
/kb/GRAPH_SCHEMA.json
```

Because hardcoding evolving topology into prompts becomes brittle very quickly.

This prompt defines **behavior**; the manifest defines **current reality**.
```


== References
[1]: https://huggingface.co/papers/2605.05242?utm_source=chatgpt.com "Paper page - Beyond Semantic Similarity: Rethinking Retrieval for Agentic Search via Direct Corpus Interaction"

[2]: GitHub: https://github.com/DCI-Agent/DCI-Agent-Lite "DCI-Agent-Lite"
