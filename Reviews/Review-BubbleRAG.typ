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
    "Review - BubbleRAG"
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
  Source: "https://arxiv.org/pdf/2603.20309",
  ArtifactType: "Academic Paper",
  PublishDate: "2026/05/16",
  Keywords: [BuggleRAG, Knowledge Extraction, Information Extraction, Semantic Search, 
    Similarity Search, RAG, Semantic Similarity,
    Direct Corpus Interaction, DCI, Exploration, Explorable Knowledge Base]
)

= Overview
This paper, *“BubbleRAG: Evidence-Driven Retrieval-Augmented Generation for Black-Box Knowledge Graphs”*, addresses 
a specific weakness in graph-based RAG systems: they often assume prior knowledge of the graph schema, relation 
semantics, or traversal structure. In many practical settings—especially enterprise knowledge graphs, 
heterogeneous metadata graphs, or third-party graph databases—this assumption fails. The paper calls these 
*black-box knowledge graphs*, where the schema is unknown or only partially accessible. The authors argue that 
existing graph-RAG methods suffer from two major failure modes: *poor recall* (missing relevant evidence because 
traversal starts in the wrong place or follows the wrong paths) and *poor precision* (retrieving noisy or 
weakly related subgraphs that confuse generation). ([goatstack.ai][1])

The core contribution is a formalization of retrieval as the *Optimal Informative Subgraph Retrieval (OISR)* problem. 
Rather than treating retrieval as “find nearest nodes” or “expand k hops,” BubbleRAG frames it as finding 
the smallest but most informative evidence subgraph that sufficiently supports answering a query. 
The authors show this is computationally hard (related to Group Steiner Tree optimization), which 
justifies heuristic approximation rather than exact search. Their practical solution uses a multi-stage 
pipeline: first identifying *semantic anchors* from the question, then grouping similar anchors into 
“bubbles,” expanding these bubbles heuristically to discover candidate evidence graphs, ranking them 
with composite scoring, and finally applying reasoning-aware expansion if evidence is insufficient. 
The design is notable because it explicitly optimizes both completeness and evidence quality, 
instead of relying on naïve graph traversal. ([goatstack.ai][1])

Architecturally, BubbleRAG is interesting because it is *training-free and plug-and-play*. 
No retriever fine-tuning or graph schema engineering is required. This makes it attractive for 
environments where documents, entities, and extracted relations may evolve continuously and schema 
rigidity is undesirable. Conceptually, BubbleRAG behaves less like standard vector RAG and more 
like an *evidence graph explorer*: it incrementally builds a candidate reasoning substrate rather 
than retrieving isolated chunks. This aligns with the broader “explore model” (Codex/Claude-style 
filesystem exploration), except BubbleRAG constrains exploration through graph evidence optimization.

Experimentally, the paper reports state-of-the-art performance on multi-hop QA benchmarks, 
outperforming strong graph-RAG baselines in F1 and accuracy. The key practical takeaway is not 
merely benchmark gains, but *why* those gains occur: BubbleRAG reduces the brittleness of 
fixed traversal heuristics. Standard graph RAG often fails because the correct reasoning 
chain is not obvious from the initial query terms; BubbleRAG compensates by maintaining 
multiple plausible evidence hypotheses and refining them. In other words, it treats 
retrieval as an uncertain reasoning problem, not a deterministic lookup problem. ([goatstack.ai][1])

BubbleRAG is particularly relevant if we want to support *knowledge graph retrieval over imperfect, 
evolving, semi-structured corpora*. If the graphs are schema-light, dynamically extracted, or partially 
noisy (which is typical for automated document knowledge extraction), BubbleRAG’s approach is much 
more realistic than classic graph-RAG pipelines that assume ontology cleanliness. The limitation 
is computational complexity: heuristic graph exploration can become expensive at scale compared 
with BM25/vector retrieval. So this is strongest as a *precision retrieval layer for complex 
multi-hop reasoning*, not necessarily as the universal first-pass retriever.

== Example

Suppose the knowledge graph contains extracted entities and relations from standards documents:

```text
[WHO Vaccine Storage Guideline]
   ├── defines → [Temperature Monitoring]
   ├── requires → [Continuous Monitoring]
   └── references → [Alarm Requirement]

[CDC Vaccine Toolkit]
   ├── mentions → [Digital Data Logger]
   ├── supports → [Continuous Monitoring]

[ISO 17025]
   ├── requires → [Calibration]
   └── applies_to → [Measurement Equipment]

[Digital Data Logger]
   ├── has_feature → [Excursion Alarm]
   ├── requires → [Calibration]
```

Now the user asks: "What are the requirements for vaccine cold chain monitoring alarms?"

A typical graph RAG might do:

*Step 1: Entity linking*

Extract keywords:

```text
vaccine
cold chain
monitoring
alarm
```

Map to nodes:

```text
[Vaccine Storage]
[Temperature Monitoring]
[Alarm Requirement]
```

*Step 2: Fixed traversal*

Expand 2 hops from each.

Retrieved:

```text
WHO Vaccine Storage Guideline
Temperature Monitoring
Alarm Requirement
CDC Vaccine Toolkit
```

Problem:

It may miss:

```text
Digital Data Logger
Calibration
ISO 17025
Excursion Alarm
```

But these may actually be critical to answering properly because the graph does not explicitly say:

```text
cold chain monitoring alarm → digital data logger
```

That relationship may only emerge through reasoning. So naive traversal gets incomplete evidence.

*BubbleRAG approach*

BubbleRAG treats retrieval as evidence discovery.

*Step 1: semantic anchors*

Instead of literal keyword matching only, BubbleRAG derives anchor concepts:

Query:

> vaccine cold chain monitoring alarms

Possible anchors:

```text
vaccine storage
temperature monitoring
cold chain
alarm
continuous monitoring
monitoring equipment
excursion alert
```

Already better than keyword lookup.

*Step 2: create bubbles*

Group semantically related anchors.

Bubble A:

```text
vaccine storage
cold chain
temperature monitoring
```

Bubble B:

```text
alarm
excursion alert
continuous monitoring
```

Bubble C:

```text
monitoring equipment
data logger
calibration
```

A bubble is basically a hypothesis cluster.

*Step 3: evidence expansion*

Bubble A expands:

```text
WHO Vaccine Storage Guideline
CDC Vaccine Toolkit
```

Bubble B expands:

```text
Alarm Requirement
Excursion Alarm
Continuous Monitoring
```

Bubble C expands:

```text
Digital Data Logger
Calibration
ISO 17025
```

Now retrieved evidence becomes:

```text
WHO guideline
CDC toolkit
alarm concepts
data logger
ISO calibration requirements
```

*Step 4: Scoring*

BubbleRAG scores candidate evidence.

Bad evidence:

```text
vaccine inventory management
shipment tracking
patient immunization records
```

These mention vaccines but do not help answer alarm requirements.

Good evidence:

```text
Digital Data Logger → has excursion alarm
ISO 17025 → requires calibration
WHO → continuous monitoring
```

*Final evidence subgraph*

BubbleRAG constructs:

```text
WHO Guideline
   → requires continuous monitoring
   → requires alarms

CDC Toolkit
   → recommends digital data logger

Digital Data Logger
   → provides excursion alarms
   → requires calibration

ISO 17025
   → requires calibration for measuring equipment
```

*Final answer generation*

LLM now answers:

> Vaccine cold chain monitoring should use continuous temperature monitoring.
> Alarm capability must detect temperature excursions.
> Digital data loggers are commonly required/recommended as the monitoring device.
> Monitoring equipment should be calibrated per ISO 17025 or equivalent requirements.

*Why BubbleRAG is better*

Naive Graph RAG thinks:

> "Find nearby nodes."

BubbleRAG thinks:

> "Find the minimum evidence graph needed to support the answer."

That difference is huge.

*Analogy to SemOS*

In SemOS, It may have:

```text
documents
topics
metrics
provisions
references
entities
tables
images
citations
```

User asks:

> "What standards define response time metrics for vaccine cold chain alarms?"

Naive retrieval: match "response time" nodes only.

BubbleRAG: forms bubbles like:

```text
alarm timing
temperature excursion
monitoring alert latency
cold chain equipment requirements
performance metrics
```

Then explores graph paths until enough evidence is found.

That is much closer to *agentic evidence discovery* than conventional RAG.
This is why BubbleRAG is interesting: it makes graph retrieval behave more like an investigator 
than a keyword expander.

== Thoughts on SemOS
=== Ontology Beans
*Step 1: Map Documents to Ontology Beans*
Most (if not all) documents can be mapped to top-level ontology beans, such as "Standards", 
"Software Specification", "Design Document", "Academic Paper", "Open-Source Project", etc.

=== Ontology Bean Indexing 
This is probably the most important factor of SemOS: we don't just collect data. One critical purpose of SemOS
is how to find them. This is what we call *Ontology Bean Indexing*.

Ontology beans must be indexed in multiple dimensions:
- Ontology Bean Categories
- Topics
- Time
- ...

The term 'Index' is different from the one used in databases or search engines. Indexing is more
about connecting entities than entity clustering.

Take 'indexing on category' as an example. A Standard Document D is normally categorized as:
```text
Standard → Medical Standards -> Healthcare Standards -> ...
```

Note here that 'Standard', 'Medical Standard', 'Healthcare Standard' are all ontology beans. 
If Document D is a 'Healthcare Standard', indexing Document D means to connect D to the
'Healthcare Standard' ontology bean.

Let's assume that initially there are no hierarchy on 'standards'. There will be many standards of 
many different categories, such as 'Healthcare Standard', 'Medical Standard', 'Microwave Standard', etc.
When there are too many categories, we can use LLMs to classify them.

If we have 100,000 categories, here is what we can do:
- For the first N categories (N is configurable and defaults to 2000), use an LLM to classify them.
  The result is a collection of Level 1 categories for these N leaf categories. Note that a leaf
  category may belong to multiple Level 1 categories.
- For the next N categories, use the same LLM to classify them, with the Level 1 categories.
  Instruct the LLM to add new Class 1 categories as needed. The result is an expanded Level 1 category set.
- Repeat the above step until all categories are classified
- If the total number of Level 1 categories is too big, repeat the above process to generate Level 2
  categories, recursively.

The above algorithm will build a hierarchy of categories.

The above only exhibits a specific index dimension: document type.
There can be many more dimensions:
- Keywords
- Topics
- References
- Mention
- Terminology
- Concept
- ...

== References
[1]: https://goatstack.ai/articles/2603.20309?utm_source=chatgpt.com "BubbleRAG: Evidence-Driven Retrieval-Augmented Generation for Black-Box Knowledge Graphs"

