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
    "Review - OntoKG"
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
  Source: "https://arxiv.org/abs/2604.02618",
  FileID: "file-2026042803",
  ArtifactType: "Academic Paper",
  DocTime: "2026/04/28"
)

#let onto_kg_review() = {
  "Ref: Reviews/Review-OntoKG.typ"
}

= Overview
The paper *OntoKG: Ontology-Oriented Knowledge Graph Construction with Intrinsic-Relational Routing* proposes a new framework for
building knowledge graphs (KGs) that is explicitly guided by ontologies rather than relying purely on data-driven extraction. 
The motivation is that traditional KG construction methods—especially those powered by LLMs—often produce inconsistent, noisy, 
or weakly structured outputs because they lack a strong, global semantic schema. OntoKG addresses this by tightly coupling 
extraction with ontology constraints, ensuring that the resulting graph adheres to well-defined conceptual structures. ([arXiv][1])

At the core of the method is a mechanism called *Intrinsic-Relational Routing*. Instead of treating entity extraction and relation 
extraction as independent steps, the model dynamically routes information based on both intrinsic properties (what an entity is) 
and relational context (how it connects to others). This allows the system to better disambiguate entities and assign more 
accurate relationships, especially in complex or ambiguous text. In effect, the model jointly reasons over ontology structure and 
textual evidence, rather than applying a fixed pipeline. ([arXiv][1])

Another key contribution is the emphasis on *ontology-aware reasoning during construction*. The framework integrates ontology rules 
directly into the generation process, which improves consistency and reduces invalid or contradictory triples. This is particularly 
important for large-scale knowledge graph construction, where small inconsistencies can propagate and degrade downstream applications. 
The paper also demonstrates that this approach improves tasks like entity disambiguation and domain-specific customization, 
indicating better alignment between extracted knowledge and real-world semantics. ([LinkedIn][2])

The authors validate OntoKG through experiments on large datasets and downstream tasks, showing measurable improvements over existing 
methods. For example, the system achieves better performance in entity linking benchmarks and can scale to very large corpora 
(e.g., datasets with tens of millions of entities), while maintaining structural coherence. ([LinkedIn][2])

Overall, the paper represents a shift from *“LLM-as-extractor” to “LLM-as-ontology-guided constructor.”* Instead of generating loosely 
structured triples, OntoKG enforces a principled semantic backbone during extraction. This makes it particularly relevant for applications 
like RAG systems, enterprise knowledge bases, and domain-specific “second brain” architectures—where correctness, consistency, 
and evolvability of knowledge are critical.

== Example

*Input Text*

> “Apple released the new M4 chip in 2025. It significantly improves AI performance. The chip is used in MacBook Pro devices.”

Without Ontology (Typical LLM Extraction), the outputs may look like:

- (Apple, released, M4 chip)
- (M4 chip, improves, AI performance)
- (chip, used in, MacBook Pro)

They are:

1. Entity ambiguity: “Apple” → could be fruit or company, “chip” → unclear whether it refers to M4 or generic chips
2. Inconsistent typing: “AI performance” is vague (metric? capability?), “MacBook Pro” is not typed (product? category?)
3. Weak structure: No guarantee relations are valid or consistent, “improves” is free-form, not normalized

With Ontology (OntoKG-style), the outputs may look like (simplified):

Ontology (simplified)

The ontology may define classes: `Company`, `Product`, `Chip`, `Device`, `PerformanceMetric` and relations: 
* `produces(Company → Product)`
* `released(Product → Date)`
* `used_in(Chip → Device)`
* `improves(Chip → PerformanceMetric)`

Ontology-Guided Extraction Output:
* (Apple Inc., type, Company)
* (M4 Chip, type, Chip)
* (MacBook Pro, type, Device)
* (AI Performance, type, PerformanceMetric)
* (Apple Inc., produces, M4 Chip)
* (M4 Chip, released, 2025)
* (M4 Chip, improves, AI Performance)
* (M4 Chip, used_in, MacBook Pro)

Ontology acts as a constraint + prior knowledge. It improves (This is the Key):

1. Disambiguation via ontology: “Apple” → forced into `Company` → becomes Apple Inc.; “chip” → resolved to M4 
   Chip (correct coreference)
2. Relation normalization: “released” → mapped to `released(Product → Date)`; “improves” → constrained to 
   valid target (`PerformanceMetric`). No random verbs like: “enhances”, “boosts”, “makes better” → all normalized
3. Type safety (this is huge): Without ontology, this could happen: (M4 Chip, used_in, AI performance). 
   With ontology: `used_in(Chip → Device)`. It prevents invalid edges.
4. Better graph structure (less entropy): Without ontology, Graph = loose triples; with ontology, Graph = typed, 
   constrained, composable. This enables queries, such as: “Which chips are used in devices?”, “Which companies 
   released chips after 2024?”

OntoKG adds beyond this basic example:

- Intrinsic routing: “What is this entity?” (Chip vs Product vs Company)
- Relational routing: “What relations are valid here?”
- Both happen during extraction, not after

Ontology defines semantic models, such as "An entity must have a type", refer to (Apple Inc., type, Company), 
(M4 Chip, type, Chip) in the above example. *Note types* are very important, in terms of being more semantics-rich 
(more meaningful), less ambiguous, etc.

The question is: who create the types?

Node types can be created bu human users. This is a feasible solution for small datasets and the model is very
clear only.

It is possible to use existing ontologies/standards, such as:
- Schema.org: `Organization`, `Product`, etc.
- DBpedia: extracted from Wikipedia
- Wikidata: massive, real-world entity typing

These ontologies/standards are useful, but they can be too generic.

The emerging trend is to use LLM to propose types, cluster entities into categories, normalize synonyms, and
possibly other methods. The weakness of LLM-driven typing is less stable (deterministic). This is where
OntoKG comes in.

Conceptually, we can start with a small, human-created ontology, use it as soft-constraints. During extraction, we
can instruct LLMs to pay attention to ontology, or more specific, about the model at hand. When the LLM extracts
something, it will consult the ontology model to see whether nodes and edges fall into the model. If yes, use the
model to normalize the extraction (so the extraction 'lives' inside the model). Otherwise, we can instruct the LLM
to extend the model by proposing new types and relations.

OntoKG does not introduce a totally new paradigm. Its contribution, if any, is to turn the pipeline into
a joint, structured decision process during extraction.

The above conceptual mode:
```
  Text ->
    LLM use ontology to guide extraction decisions step-by-step ->
      Check against ontology ->
        Normalize / fix ->
          Extend ontology
```

During OntoKG extraction, it forces the LLM to decide along two axes simultanenously:
* Intrinsic (What is this entity?), e.g., "Apple" => Company? Fuite? Brand?
* Relational (What relationships are valid here?), e.g., If `Apple` is Company, it can `produce`; if `Apple`
  is `Fruit`, it cannot release chips.

The extraction decision MUST not be independent or checking the model after the extraction. Extraction and
ontology MUST be applied during the extraction, together.

In the 'Apple' case, the LLM should check if `Apple` is `Fruit`, `Fruit` cannot release `Product`, thus rejected.
It then try `Apple` is `Company` and `Company` can release `Product`. It is accepted. In this case, ontology
is used as a search constraint, not a validator. Instead of letting LLMs extract entities and relations freely
and then fix them later, OntoKG explores the candidates and use ontology to prune valid candidates.

If OntoKG finds no suitable nodes (intrisic) and/or relation in the current model, it does not automatically
expand the model. Instead, it stays within the ontology as much as possible, if not, degrate gracefully.

More specifically:
- It can map approximately (normalize), such as `Startup` map to `Company`
- Partially fit, such as "Apple improved user experience": the ontology has `improves(Chip -> PerformanceMetric)`, but
  it does not have `user experience`, it may map to PerformanceMetric (approximation) or siplify relation.
- Truly not fit at all: OntoKG will still extract something, but with weaker quarantees, such as less constrained
  and less confident relations.

OntoKG deliberately avoid auto-expansion, due to the following concerns:
- Explosion: every document introduces new types. This can lead ontology useless
- Synonym Fragmentation: `Company`, `Corporation`, `Firm`, `Businessentity`, etc. They can co-exist, leading to chaos.
- Loss of Constraint Power: ontology thus becoming less constrainable.

How to solve this problem?

== References
[1]: https://arxiv.org/abs/2604.02618?utm_source=chatgpt.com "OntoKG: Ontology-Oriented Knowledge Graph ..."

[2]: https://www.linkedin.com/posts/lawrencepaulson_abstract-consistency-properties-activity-7447959651104657408-41XQ?utm_source=chatgpt.com "Lawrence Paulson - Abstract Consistency Properties"

