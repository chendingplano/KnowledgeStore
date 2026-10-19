---
ID: topic-knowledge-semantics
Contributors: ChatGPT, Chen Ding
Creation Date: 2026/10/19
---

# 1. Overview
Semantics is an important architectural question for SemOS: What is the computational representation of meaning, and how can we make that meaning usable by software and LLM agents?

Embeddings, keywords, topics, categories, and labels can all represent aspects of semantics. However, they capture different aspects of meaning, with different levels of precision and different computational properties.

We want to make one fundamental distinction:

**Semantics is meaning. A semantic representation is an encoding of some aspect of that meaning. Embeddings are one such encoding, not semantics itself.**

From an engineering perspective, the central challenge is not simply representing meaning, but preserving enough of it to support the operations we want to perform: search, comparison, classification, inference, explanation, and decision-making.

## 2. Semantics
## 2.1 What exactly is semantics?

Consider this sentence:

> Increasing storage temperature accelerates the degradation of Product X.

A human reader can understand several things:

- The subject is storage temperature.
- The outcome is product degradation.
- There is a directional relationship between them.
- Increasing temperature increases degradation rate.
- The relationship applies to Product X.
- The statement expresses a general relationship rather than a single measurement.

These are all aspects of the sentence's semantics. The keyword is **ASPECTS**. 
The reasons why embedding uses vectors with high dimensions are that it wants
to sack all aspects into one digital representation.

- Category is one aspect
- Keyword is one aspect
- Topic may involve multiple aspects
- Label is one aspect

Semantics can/should be represented in multiple different ways.
![Semantics](../images/image_2026101905.png)

Each representation is useful, but none captures everything.

The embedding may help retrieve semantically similar sentences. Keywords identify concepts. Categories organize the statement. A structured relationship preserves a particular assertion.

This suggests a useful engineering definition:

> Semantics is the interpretation of information that determines what it refers to, what it asserts, under which conditions it applies, and what conclusions or operations are justified by it.

The last part is especially important. Meaning is not just about similarity; it is also about what we can validly infer.

## 2.2 Different dimensions of semantics

Rather than treating semantics as a single thing, we can decompose it into several dimensions.

| Dimension   | Question                                   | Example                                             |
| ----------- | ------------------------------------------ | --------------------------------------------------- |
| Lexical     | What do the words mean?                    | "Thermal" relates to heat                           |
| Referential | What entities do they refer to?            | "Product X" identifies a particular product         |
| Topical     | What is the content about?                 | Product stability                                   |
| Taxonomic   | What kind of thing is it?                  | Degradation is a process                            |
| Relational  | How are concepts connected?                | Temperature influences degradation                  |
| Logical     | What is asserted or implied?               | A requirement applies only under certain conditions |
| Causal      | What produces an effect?                   | Higher temperature accelerates a reaction           |
| Contextual  | Under which circumstances does it apply?   | During storage of Product X                         |
| Pragmatic   | What is the intended use of the statement? | Warning, requirement, recommendation                |

These dimensions overlap. They are not intended as a formal linguistic taxonomy.

For SemOS, the value is that different extraction and representation mechanisms can target different dimensions.

For example, embedding search is often effective for topical similarity, while a rule engine is more suitable for checking logical constraints.

## 2.3 Comparing semantic representations

We can characterize the major representations from an engineering perspective.

| Representation    | Main strength                     | Main limitation                                 |
| ----------------- | --------------------------------- | ----------------------------------------------- |
| Keywords          | Precise lexical retrieval         | Synonyms and paraphrases                        |
| Tags/labels       | Flexible classification           | Ambiguous without definitions                   |
| Topics            | Organize broader meaning          | Often too coarse for detailed reasoning         |
| Categories        | Hierarchical organization         | Fixed taxonomies can be restrictive             |
| Embeddings        | Generalized similarity            | Meaning is implicit and difficult to inspect    |
| Entities          | Explicit references               | Limited relationship information                |
| Relations/triples | Explicit assertions               | Conditions and context may be lost              |
| Ontologies        | Formalized concepts and semantics | Modeling and maintenance costs                  |
| Rules/logic       | Precise, executable constraints   | Requires explicit formalization                 |
| Equations         | Quantitative relationships        | Limited to mathematically expressible knowledge |

Notice that this is not a ranking. Each representation preserves different information.

### 2.3.1 Keywords: Lightweight semantic anchors

Keywords can be more than arbitrary words extracted from text.

For example:

```
keywords:
  - storage_temperature
  - thermal_degradation
  - product_stability
```

These keywords encode important concepts.

If SemOS normalizes keywords into canonical concepts, they can function as lightweight semantic identifiers.

Consider:

- "temperature excursion"
- "out-of-range temperature event"
- "storage temperature deviation"

These phrases may refer to the same or closely related concepts, depending on their definitions.

If SemOS maps them to a canonical concept such as `temperature_excursion`, keyword-based retrieval becomes more semantic than ordinary string matching.

This is an important distinction:

A normalized keyword can act as an identifier for a concept, rather than merely a string to match.

For SemOS, I would strongly favor canonical concept IDs, with multilingual labels and aliases attached.

### 2.3.2 Topics: Semantic summaries

A topic represents what a piece of content is principally about.

For example:

```
topic:
  name: Temperature effects on vaccine stability
  keywords:
    - temperature
    - stability
    - degradation
```

A topic can group multiple statements with related meaning.

But topics generally do not preserve detailed assertions.

Two documents might share the topic "Temperature effects on vaccine stability" while reaching opposite conclusions.

Therefore, topics are useful for discovery and navigation, but insufficient as a complete representation of knowledge.

### 2.3.3 Categories: Taxonomic semantics

Categories introduce structure.

For example:

```
Science
└── Materials Science
    └── Material Properties
        └── Thermal Stability
```

This structure encodes classification relationships.

However, a category hierarchy must have clear semantics.

Consider:

```
Materials
└── Temperature
```

What does the parent-child relationship mean?

Is temperature a type of material? Obviously not.

Perhaps temperature is a property associated with materials, or a factor influencing material behavior.

This is precisely why taxonomies sometimes become difficult to maintain: hierarchical placement can accidentally mix several different relationships.

A well-designed taxonomy should distinguish:

- `is_a`: subclass or specialization
- `part_of`: composition
- `related_to`: general association
- `affects`: influence
- `used_for`: function or purpose

Only some of these are naturally hierarchical.

Treat categories as typed semantic classifications, not arbitrary directory hierarchies.
Categories are used to index semantics.

### 2.3.4 Embeddings: Implicit, distributed semantics

An embedding maps text or another object into a numerical vector:

$$f(x) \in \mathbb{R}^d$$

The vector's coordinates do not ordinarily correspond to explicit human-readable properties.

Instead, its geometry reflects patterns learned during training.

For example, these sentences might have similar embeddings:

- Increasing temperature accelerates degradation.
- Higher temperatures increase the rate of deterioration.

This is valuable because the sentences use different words but express similar ideas.

However, embeddings have important limitations.

#### 2.3.4.1 Limitation 1: Similarity is not equivalence

Consider:

- Temperature increases degradation.
- Temperature decreases degradation.

These statements are topically very similar but assert opposite relationships.

Their embeddings may also be close.

A high cosine similarity does not establish logical equivalence.

#### 2.3.4.2 Limitation 2: Weak guarantees for numerical and logical precision

Consider:

- Temperature must not exceed 8°C.
- Temperature must remain above 8°C.

These statements differ critically in their constraints.

A generic embedding model is not guaranteed to preserve that difference in a way that nearest-neighbor search can reliably distinguish.

#### 2.3.4.3 Limitation 3: Limited interpretability

A 1,024-dimensional vector does not directly tell us:

- Which entities were identified
- Which relationships were asserted
- Whether a requirement is mandatory
- Which conditions limit applicability
- Whether two statements contradict each other

Those properties may influence the vector, but they are not explicitly accessible.

#### 2.3.4.4 Limitation 4: Context and granularity

The meaning of a sentence can depend on the surrounding document.

For example:

> This effect was not observed at lower temperatures.

Without the preceding paragraph, the referent of "this effect" is unknown.

Embedding the isolated sentence may lose critical context.

This is one reason contextual embeddings, late chunking, and contextual enrichment can be useful.

#### 2.3.4.5 Limitation 5: Model dependence

Embeddings from different models generally occupy incompatible vector spaces.

Changing embedding models may require re-embedding the corpus.

By contrast, a canonical concept identifier such as `temperature_excursion` can remain stable across model upgrades.

That is a significant architectural advantage for a long-lived knowledge system.

#### 2.3.4.6 Semantic dilution
A piece of text may contain multiple 'semantics', especially when text is big.
When we search, we often want to search a specific 'semantics'. 

Another source of diluting embeded vectors is the corpus size.

## 2.4 Ontology: Making semantics explicit

This brings us back to your original question about ontology.

An ontology is a mechanism for making selected aspects of meaning explicit and formally interpretable.

Consider the concept:

```
concept:
  id: temperature_excursion
  type: Event

  definition: >
    An occurrence in which a monitored
    temperature falls outside a specified
    acceptable range.

  aliases:
    - temperature deviation
    - out-of-range temperature event

  relations:
    - occurs_during: StorageProcess
    - involves: TemperatureMeasurement
```

This representation does more than provide a label.

It establishes:

1. Identity: What concept the identifier refers to.
2. Definition: What the concept means.
3. Classification: What kind of entity it is.
4. Relationships: How it connects to other concepts.
5. Constraints: What conditions must hold for something to qualify as an instance.

A formal ontology can additionally encode axioms that support logical inference.

For example:

$$\text{TemperatureExcursion} \sqsubseteq \text{MonitoringEvent}$$

This means every temperature excursion is a monitoring event.

A reasoner can use that axiom to infer that an instance of `TemperatureExcursion` is also an instance of `MonitoringEvent`.

An embedding cannot provide that kind of logical guarantee by itself.

But there is an important qualification: ontologies formalize selected aspects of semantics. They do not automatically capture the complete meaning of natural language.

# 5. Semantic representations form a spectrum

I find it useful to visualize semantic representations along two dimensions:

- Explicitness: How directly the representation exposes its meaning.
- Formal precision: How rigorously its interpretation and inference rules are defined.

![Semantic Representation](../images/image_2026101906.png)

This diagram also suggests that semantic representations can complement one another.

An embedding provides broad similarity. A category provides a classification. A formal rule provides an exact condition.

Combining them is often more useful than trying to replace one with another.

# 6. Semantics as a multi-representation system

SemOS stores multiple semantic representations of the same content.

Suppose a document contains:

> Storage temperature above 8°C may accelerate the degradation of Product X.

SemOS could produce:

```
semantic_record:
  source: document_123
  text: >
    Storage temperature above 8°C may
    accelerate the degradation of Product X.

  concepts:
    - storage_temperature
    - degradation_rate
    - product_x

  keywords:
    - thermal_degradation
    - temperature_threshold
    - product_stability

  categories:
    - product_quality/thermal_stability

  topic:
    - temperature_effects_on_stability

  claims:
    - subject: storage_temperature
      relation: may_increase
      object: degradation_rate
      conditions:
        temperature: "> 8 °C"
        product: product_x

  embedding:
    model: embedding_model_version
    vector_ref: embedding_456
```

Each field supports different operations.

| Operation                                   | Most useful representation       |
| ------------------------------------------- | -------------------------------- |
| Find exact terminology                      | Keywords                         |
| Find paraphrases                            | Embeddings                       |
| Browse knowledge hierarchically             | Categories                       |
| Find documents about a subject              | Topics                           |
| Find all claims involving a concept         | Entities and relations           |
| Determine whether two requirements conflict | Structured claims and conditions |
| Infer subclass membership                   | Ontology axioms                  |
| Check compliance                            | Rules and constraints            |
| Explain causal mechanisms                   | Causal knowledge model           |

This architecture fits SemOS's existing combination of file-native exploration, BM25, and vector search.

Instead of asking which semantic representation is best, SemOS can select representations according to the retrieval or reasoning task.

# 7. An important distinction: Semantic similarity vs. semantic understanding

These are frequently conflated.

Semantic similarity asks:

> How similar are the meanings of two pieces of content?

Semantic understanding asks:

> What exactly does this content assert, and what follows from it?

For example:

A: "The temperature must remain below 8°C."

B: "The temperature must remain above 8°C."

An embedding system may consider A and B highly similar.

But a structured interpretation reveals:

```
A:
  property: temperature
  operator: <
  value: 8
  unit: celsius

B:
  property: temperature
  operator: >
  value: 8
  unit: celsius
```

The difference is decisive for compliance.

Even here, detecting a genuine conflict requires checking whether both statements apply to the same product, circumstances, and time period.

This illustrates a broader principle:

Retrieval semantics and reasoning semantics have different requirements.

Embeddings are particularly useful for the former. Explicit knowledge representations are often essential for the latter.

# 8. One more layer: Semantic normalization

The observations about keywords, categories, and embeddings point toward a capability that is especially valuable for SemOS.

Consider these terms:

- Cold chain
- Temperature-controlled supply chain
- Refrigerated distribution
- Cold-chain logistics

They overlap substantially, but they are not necessarily interchangeable.

SemOS needs a mechanism to determine:

- Are they synonyms?
- Is one broader than another?
- Are they related but distinct?
- Do they have different meanings in different contexts?

For this reason, we introduce a Semantic Concept Registry.

An illustrative entry:

```
concept:
  id: cold_chain

  preferred_label: Cold chain

  definition: >
    Temperature-controlled handling,
    storage, and distribution of
    temperature-sensitive products.

  aliases:
    - cold-chain logistics

  broader:
    - supply_chain_management

  related:
    - temperature_controlled_transport
    - refrigerated_storage

  narrower:
    - vaccine_cold_chain
```

The distinction between `aliases`, `broader`, `related`, and `narrower` is important.

A system that collapses all related expressions into synonyms will introduce semantic errors.

SKOS is particularly relevant here because it provides established mechanisms for preferred labels, alternative labels, broader/narrower concepts, and related concepts.

For SemOS, this registry could become a stable semantic layer shared by:

- Keyword normalization
- Category generation
- Entity disambiguation
- Ontology mapping
- Graph construction
- Retrieval expansion

Embeddings could assist with discovering candidate mappings, while definitions and explicit relationships determine whether those mappings are valid.

# 9. A proposed semantic architecture for SemOS

I would organize the system as follows.
![Semantic Architecture](../images/image_2026101907.png)

This is a logical organization, not necessarily a strict pipeline. Semantic representations can be generated independently, cross-validated, and refined iteratively.

I would also distinguish semantic identity from semantic similarity:

- A canonical concept ID establishes which concept an annotation refers to.
- An embedding estimates how similar two representations are.
- A relationship or axiom establishes what can be asserted or inferred about those concepts.

These should not be treated as interchangeable.

# 10. My central recommendation

I would not try to build a single universal semantic representation for SemOS.

Instead, I would treat semantics as a multi-layer, multi-representation capability.

In particular, I would establish three foundational components:

1\. Semantic Concept Registry

A stable registry of canonical concepts, definitions, aliases, classifications, and relationships. SKOS is a useful starting point, with OWL where formal reasoning is needed.

2\. Semantic Projection Layer

Generates multiple representations of documents and extracted knowledge: keywords, topics, categories, embeddings, entities, claims, and relationships.

3\. Semantic Operations Layer

Provides explicit operations such as:

```
resolve_concept(text, context)
find_equivalent_concepts(concept)
find_broader_concepts(concept)
find_related_concepts(concept)
find_semantically_similar(query)
find_claims(subject, relation, object)
check_constraint(claim, conditions)
```

The important shift is from storing semantic representations to providing operations over meaning.

For example, `find_semantically_similar` can use embeddings, while `find_equivalent_concepts` should use canonical mappings and validated equivalence relations. The two operations have different semantics and different correctness guarantees.

Ultimately, I think the most useful engineering definition for SemOS is:

> Semantics is the machine-interpretable meaning of information, represented through complementary lexical, categorical, vector, and symbolic structures, and made operational through well-defined retrieval and reasoning capabilities.

Strictly speaking, meaning itself is not limited to what machines can represent. But this definition gives SemOS a practical engineering target.

The architectural principle I would emphasize is: Embeddings help SemOS find information with related meaning; ontologies, structured claims, and rules help SemOS determine what that information means and what conclusions it supports. Neither replaces the other.&#x20;