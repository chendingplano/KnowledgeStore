#import "@preview/diagraph:0.3.6"
#import "@preview/oxdraw:0.1.0": *

#set heading(numbering: "1.")
#set quote(block: true)
#show quote: set pad(x: 1em)
#show raw.where(block: true): block.with(fill: luma(240), inset: 1em, radius: 0.5em, width: 100%)

#set page(numbering: "i")
#counter(page).update(1)

= Table of Contents
#outline()
#pagebreak()

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
    "Review - Superintelligent Retrieval Agent"
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

#show heading.where(level: 4): set text(size: 12pt)
#show heading.where(level: 4): it => pad(top: 4pt, it)

#set page(numbering: "1")
#counter(page).update(1)
#counter(heading).update(0)

#let frontmatter = (
  created: "2026/05/10",
  logical_name: "superintelligent retrieval agent",
  file_id: "2026051001",
  file_type: "Typst",
  keywords: ["Information Retrieval", "Superintelligent", "Agent", "agentic system"],
  source_url: "https://arxiv.org/abs/2605.06647",
  feed: "Hacker News"
)

= Overview
This paper, *“Superintelligent Retrieval Agent: The Next Frontier of Information Retrieval”* (SIRA), proposes a shift in how retrieval systems should work when paired with LLM agents. The authors argue that most current retrieval-augmented systems behave like inexperienced users: they issue a query, inspect results, reformulate, and repeat. This iterative exploration works, but it is inefficient, slow, and often misses relevant evidence. Their core thesis is that a stronger retrieval agent should behave more like a domain expert—able to infer, in one shot, what distinguishing evidence is likely to separate relevant documents from distractors in the corpus. ([arXiv Troller][1])

To achieve this, they introduce *SIRA (SuperIntelligent Retrieval Agent)*. The key conceptual change is that retrieval should not merely expand a user query semantically (“what words are related to this?”), but *discriminate at the corpus level* (“what terms uniquely isolate the target information from all plausible confusers?”). This is an important distinction. Traditional retrieval augmentation often optimizes for query similarity, whereas SIRA aims for *discriminative retrieval intelligence*. In practical terms, instead of progressively searching “vector database indexing” → “ANN search” → “HNSW indexing optimization,” a SIRA-like system would ideally infer the discriminative terminology immediately.

Architecturally, this aligns strongly with emerging agentic retrieval ideas: retrieval becomes an active reasoning process rather than a passive database lookup. The paper essentially reframes retrieval as a planning/intelligence problem. That makes it especially relevant if you're thinking about systems like your MKBP design, where LLMs explore large corpora rather than simply fetch chunks. SIRA’s philosophy is much closer to “knowledge navigation” than classical RAG. It implies a future where retrieval agents maintain corpus priors, understand terminology landscapes, and optimize retrieval actions strategically rather than reactively.

The interesting broader implication is that this pushes retrieval toward something resembling *expert memory systems*. Instead of brute-force vector similarity or repeated query refinement, the retrieval layer itself becomes cognitively informed. Whether the paper fully demonstrates “superintelligence” is debatable—it currently reads more as a strong conceptual framework than a definitive solved system—but the direction is compelling. For anyone designing agentic knowledge systems, the real takeaway is this: *the next leap in RAG may not come from better embeddings, but from smarter retrieval decision-making.*

== The Method
“Discriminate user queries at the corpus level” means: instead of asking “what documents are semantically similar to this query?”, 
ask “what signals best separate the truly relevant documents from the rest of this specific corpus?”

Traditional retrieval thinking uses similarity. Suppose the user asks:

> “How do I optimize PostgreSQL indexes for JSONB queries?”

A normal retrieval system does:

- Embed the query
- Find nearest vectors
- Maybe BM25 keyword match
- Maybe rewrite query:

  1. `"PostgreSQL JSONB indexing"`
  2. `"GIN vs BTREE JSONB"`
  3. `"jsonb query optimization"`

This is query-centric. Its core assumption is "Similar wording ≈ relevant content". The problems are apparent.
A corpus may contain thousands of PostgreSQL docs:

- backups
- replication
- WAL
- partitioning
- query planner
- indexing
- JSONB internals

Semantic similarity alone often pulls many “kind of related” docs.

In SIRA, it thinks like an expert. The real question becomes:

> What vocabulary or concepts uniquely identify the relevant subset?

For JSONB indexing, discriminators may be:

- GIN
- GiST
- jsonb_path_ops
- containment operator `@>`
- expression index
- generated column
- planner statistics

These are not merely semantically related. They are separators, which means documents containing 'JSONB' + 'GIN'
are much more likely relevant than documents merely mentioning PostgreSQL. So retrieval becomes:

"Find discriminative features, not just similar phrases."

In mathematics terms, Classic IR uses:
```text
score(d, q) = similarity(embedding(q), embedding(d)), or:
BM25(q, d)
```

SIRA-style thinking is to estimate:
```text
P(relevant \mid feature, corpus), or more importantly:
discrimination(feature) = P(feature \mid relevant)
P(feature \mid irrelevant)
```

Good discriminators will pick high in relevant docs, low elsewhere.

Example:

Feature `"GIN"` appears in many relevant docs and rare in irrelevant docs, which is good.

Feature `"database"` appears everywhere, which means it can hardly pick useful relevant docs.

The idea is basically feature selection / information gain logic.

== How an LLM do this

The trick is: the LLM doesn’t actually scan the whole corpus every time. Instead, it 
approximates using learned priors. For Example:

> “Find ISO requirements about vaccine cold chain monitoring alarms.”

LLM domain knowledge suggests:

important discriminators:

- cold chain
- data logger
- excursion alarm
- calibration
- continuous monitoring
- temperature excursion
- vaccine storage

Better than naive expansion:

- vaccine
- refrigerator
- monitoring

The LLM acts like an expert guessing:

> “If I were searching a standards corpus, what exact technical terms isolate the 
right documents?”

That’s the paper’s main insight.

*Do we need to fine-tuning the LLM*?

Normally not. An LLM can often suggest useful discriminators without knowing your 
dataset — but only as a *prior expert guesser*, not a true corpus expert. A real 
corpus-level discriminator system needs corpus knowledge, not just pretrained 
world knowledge. This means that we need to combine LLM knowledge and corpus knowledge.

There are two kinds of expertise:
- Domain Expert (world knowledge)

=== Domain expert (world knowledge)

This is where the LLM shines. The LLM knows:

- PostgreSQL JSONB indexing → GIN, `@>`, `jsonb_path_ops`
- vaccine cold chain → excursion alarm, calibration, data logger
- legal contracts → indemnification, limitation of liability, force majeure

This comes from pretraining. No knowledge of *your* corpus needed. This is basically:

> “If I were a human expert, what terms would likely matter?”

This works surprisingly well.

=== Corpus expert (local knowledge)

The corpus expert knows:

- everyone says “AEFI”, never “adverse reaction”
- “temperature excursion” is standard terminology
- “cold chain breach” appears nowhere
- Chinese docs use “温度异常” instead
- one vendor dataset uses proprietary jargon

This cannot come from generic pretraining. This requires dataset-specific learning.

=== Example

Suppose your corpus is public ISO standards. For query:

> "Find requirements for password rotation."

LLM may propose:

- credential lifecycle
- secret management
- authentication policy
- access control
- privileged account management

Because ISO/security terminology overlaps with public knowledge. No corpus-specific 
training required.

Now suppose your private enterprise corpus uses weird internal terms. For query:

> "How do we deploy Canary?"

But internally, "Canary" means: traffic-shifted staged deployment with rollback guardrails

Docs never say "canary." They say:

- phased release
- progressive rollout
- blast radius control
- deployment wave

A generic LLM may keep searching “canary deployment.” and often fails because it lacks 
local vocabulary.

== The Backend

To truly discriminate at corpus level, backend needs corpus statistics, or "Corpus Expert".

- Inverted index / BM25 (the formula): Rare terms discriminate better.
- Metadata distributions, such as "which standards contain term X", "which collections 
  use concept Y". The relation `ICS=11.020` instantly narrows medical standards.
- Concept relations:
`JSONB -> GIN -> containment operator`

or

`vaccine -> cold chain -> temperature excursion`

== Topic model / clusters

Know corpus regions:

- PostgreSQL internals
- SQL tuning
- JSON functions

Then discriminate between clusters.

== Feedback memory

Track:

Previous searches show:

`"temperature monitoring"` too broad

but:

`"continuous excursion alarm"` precise

This becomes retrieval memory.

== A concrete pipeline

A practical implementation:

*Step 1: Parse intent*

User asks:

> “Requirements for adverse event reporting after rabies vaccination.”

Extract concepts:

- adverse event
- reporting
- rabies vaccine
- post vaccination

*Step 2: Generate candidate discriminators*

LLM proposes mandatory terms:

- AEFI
- suspected abnormal reaction
- reporting timeframe
- surveillance
- exposure management

*Step 3: Score against corpus stats*

Check:
```text
| term          | doc freq | discrimination |
| ------------- | -------- | -------------- |
| vaccine       | 12000    | poor           |
| adverse event | 800      | medium         |
| AEFI          | 37       | excellent      |
| rabies        | 12       | excellent      |
```

*Step 4: Build retrieval plan*

Instead of one vector query, it executes:

- BM25 on `"AEFI"`
- vector on semantic expansion
- metadata filter `rabies`
- graph expansion from `AEFI`

*Step 5: Re-rank*

Cross-encoder / LLM rerank.

== Discriminators

A discriminator is not just a relevant term. It must separate relevant docs from 
irrelevant docs. For example, for query:

> "JSON performance"

Candidate terms:

- query
- performance
- index
- GIN
- vacuum

Which discriminate?

Need corpus stats:
```text
| term        | relevant docs | irrelevant docs |
| ----------- | ------------- | --------------- |
| query       | 900           | 15000           |
| performance | 400           | 8000            |
| index       | 300           | 5000            |
| GIN         | 120           | 20              |
```

Only `"GIN"` strongly discriminates.

LLM world knowledge alone cannot know this distribution.

== Do we need fine-tuning

Usually not first. Fine-tuning is expensive and rigid. Better approaches is 
*Retrieval-time adaptation*

Teach dynamically:

- glossary
- ontology
- taxonomy
- metadata
- aliases
- terminology maps

Example:

```json
{
  "AEFI": "adverse events following immunization",
  "温度异常": "temperature excursion",
  "CAPA": "corrective and preventive action"
}
```

Now LLM becomes corpus-aware.

Much cheaper than fine-tuning.

== Feedback Learning

*Observe failures*

If user searches: "cold chain alarm", relevant docs actually use:

> "temperature excursion notification"

Store mapping.

Over time, retrieval memory improves. This means that the backend needs a hashmap.
When a user term ("cold chain alarm") is effectively selected by a discriminator 
("temperature excursion notification"), establish the relation so that the next
time when we encounter "cold chain alarm", we can quickly and effectively convert
it to the corresponding discriminators.

== Ontology

Teach structure:

```text
vaccine storage
  -> cold chain
     -> temperature monitoring
        -> excursion alarm
        -> calibration
```

This improves discriminator generation.

== The ideal architecture

*Layer 1: pretrained LLM prior*

Pick an appropriate LLM. That's all we need to do. Most LLMs have good general knowledge.

*Layer 2: corpus intelligence*

Provides:

- term frequencies
- metadata
- aliases
- taxonomy
- graph relations
- prior retrieval outcomes

This is used to correct LLM guesses.

*Layer 3: adaptive memory*

discriminator = world_knowledge + corpus_knowledge + retrieval_feedback


== Applied to SemOS

Generic LLM knows:

- compliance
- requirements
- metrics
- audit
- control

But our corpus may use:

- ICS categories
- GB/T references
- Chinese terminology
- table-defined metrics
- shorthand references

You want a corpus intelligence layer:

- terminology DB
- ontology
- document metadata
- citation graph
- concept aliases
- retrieval memory

Then the LLM becomes a much better “expert.”

== The hard problem

The phrase "corpus-level discrimination" sounds nice, but the hard part is: where do 
corpus statistics come from? Without them, the LLM is guessing. With them, you need 
infrastructure:

- inverted indexes
- term stats
- taxonomy
- embeddings
- graph memory
- metadata awareness

That is exactly why “smart retrieval” is a systems problem, not just a prompt problem.

xxxxxxx

== Explore Model and SIRA
There are basically two methods for LLMs to use local knowledge: (1) RAG, or LLMs 
formulate queries, the RAG retrieve the relevant docs and feed them back to LLMs, 
and (2) prepare the knowledge in such a way (such as in filesystems) so that LLMs 
can explore the knowledge base for the docs they need. SIRA fits the RAG model. 
Codex, Claude Code, etc., fit the explore model. 

If we want to use the explore model, is SIRA still useful?

The short answer is YES. SIRA is still useful in the explore model, but its role 
changes significantly. Though SIRA is designed for the RAG model, the underlying 
idea — discriminative search intelligence — is broader than RAG.

The real question is:

> In an explore system, does the agent still need help deciding *where to look*?

The answer is emphatically *YES*.

In the RAG model:
```text
User → Query → Retriever → Docs → LLM
```

In the Explore model:

```text
User → LLM agent → ls/find/grep/open → Docs
```

Regardless of how the search is conducted, finding true relevant documents remains
unchanged. What changed is the bottleneck moves. In RAG, retriever chooses docs; 
in explore, agent chooses actions. The intelligence problem remains.

*Retrieval vs exploration are the same decision problem*

Suppose your KB has:

```text
/standards
  /medical
    vaccine_storage.md
    immunization_reporting.md
    cold_chain_monitoring.md

/docs
  glossary.md
  faq.md

/vendors
  vendor_a_manual.pdf
```

User asks:

> "Find ISO requirements about vaccine cold chain monitoring alarms."

Explore agent must decide:

1. Start in `/standards` or `/docs`?
2. Open `glossary.md` first?
3. `grep "alarm"`?
4. `grep "excursion"`?
5. search `"cold chain"`?
6. inspect TOCs?
7. search Chinese aliases?

This is retrieval policy.

Same core problem.

SIRA now becomes action planning, not retrieval ranking

Original SIRA:

```text
query
 → generate discriminators
 → retrieve matching docs
```

Explore version:

```text
query
 → generate discriminators
 → generate exploration plan
 → execute tool actions
```

*Example*

For query:

> "Find rabies post-exposure reporting requirements."

SIRA-like reasoning:

Discriminators:

- rabies
- post exposure
- reporting
- surveillance
- AEFI
- 3h reporting
- exposure management

Action plan:

```text
grep "rabies"
grep "AEFI"
find docs with "post exposure"
open matching sections
expand linked references
```

Same intelligence, different execution.

*Codex / Claude Code already do primitive SIRA*

Claude Code/Codex behavior:

User asks:

> "Where is auth middleware implemented?"

It doesn't:

```text
cat every file
```

It does:

```text
grep auth
grep middleware
find router
open likely files
```

This is discriminator-based exploration. The model infers useful signals.

That’s weak SIRA because current coding assistants rely mostly on pretrained heuristics.
They lack corpus intelligence.

*Where SIRA becomes MORE valuable in explore systems*

Explore systems can be worse than RAG if exploration is naive.

Imagine 100,000 docs.

Naive agent:

```text
ls
ls deeper
grep broad terms
open random docs
```

Problems:

- huge latency
- token waste
- tool spam
- bad planning

SIRA helps by making exploration selective.

Instead of:

```text
grep vaccine
```

Better:

```text
grep "temperature excursion"
grep "continuous monitoring"
grep calibration
```

Massive efficiency gain.

So in explore systems, SIRA may matter even more.

*But SIRA must evolve*

Original SIRA assumes opaque corpus. Retriever owns access. Explore systems expose 
structure. Now agent can exploit:

- directory names
- filenames
- metadata
- summaries
- graph links
- TOCs
- aliases
- object relationships

This means discriminator logic should include structural signals.

Example:

Not just semantic discriminator:

```text
"AEFI"
```

But structural discriminator:

```text
/standards/medical/immunization/*
metadata.domain=medical
type=standard
has_section=requirements
```

That is much stronger.

*Explore systems allow richer discriminators*

RAG discriminators are mostly query terms. Explore discriminators can be:

- lexical

```text
AEFI
temperature excursion
```

- structural

```text
under /standards
filename contains vaccine
```

- metadata

```text
ICS=11.020
language=zh
document_type=standard
```

- graph

```text
doc cites GB 15982
linked to vaccine management docs
```

- procedural

```text
always inspect glossary before searching
```

This is beyond classic SIRA.

== Architecture: SIRA + Explore

For SemOS, ideal design is probably:

*Layer 1: filesystem illusion*

LLM sees:

```text
ls
open
grep
find
```

transparent, explorable.

*Layer 2: hidden intelligence broker*

Behind `grep` / `find`:

not literal filesystem search.

Instead:

```text
grep "AEFI"
```

becomes:

- alias expansion
- BM25
- vector search
- ontology lookup
- metadata filtering
- graph traversal

Filesystem is interface.

Backend is smart retrieval.

*Layer 3: SIRA planner*

Before tool execution, agent reasons:

```text
best discriminators?
best exploration route?
least-cost path?
```

That gives: *explore UX + retrieval intelligence*, which fits SemOS architecture almost 
perfectly.

*Strong opinion*

Pure explore without SIRA-like planning:

> intelligent-looking but inefficient wandering

Pure RAG without explore:

> efficient but opaque and less controllable

Best system:

> *SIRA-guided exploration over a smart virtual filesystem*

In one sentence:

SIRA is not tied to RAG; its real contribution is discriminative search policy, and explore-model agents need that just as much—possibly more.


== Conclusion

The paper’s phrase is intellectually correct, but somewhat hand-wavy. A realistic 
implementation is:

> LLM-generated discriminative hypotheses + corpus statistics + hybrid retrieval planning

not pure LLM magic.

This is also why SemOS *virtual filesystem + strong backend + knowledge graph + memory-aware retrieval* direction is much more realistic than “just use vector search.”

== References
[1]: https://arxiv-troller.com/?q=paper%3A+2601.20671&utm_source=chatgpt.com "arXiv Troller"

[1]: file://my_files/file_0000000023c071fd945af644c70a28e1 "chunk_api_output.json"

[2]: file://my_files/file_0000000010cc71fd9e6746b97a11ff16 "QChunker.md"
