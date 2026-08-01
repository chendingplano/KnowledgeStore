
#set page(
  paper: "us-letter",
  margin: (x: 0.85in, y: 0.8in),
)

#set text(
  font: "Libertinus Serif",
  size: 10.5pt,
)

#set heading(numbering: "1.")
#set par(justify: true, leading: 0.65em)
#set list(indent: 1.2em, body-indent: 0.5em)

#show raw.where(block: true): set block(
  fill: luma(245),
  inset: 10pt,
  radius: 4pt,
)

#let callout(title, body) = block(
  fill: rgb("#f3f6fa"),
  stroke: (left: 3pt + rgb("#4b6b88")),
  inset: (left: 12pt, right: 10pt, top: 8pt, bottom: 8pt),
  radius: 3pt,
)[
  *#title*

  #body
]

= Problems
In BM25 search, keywords are treated as isolated entities. The keyword 'apple' can mean apple-as-fruit 
or apple-as-company. When users issues a query "apple" over a big enough dataset, entries with 
apple-as-fruit are probably overwhelming. Users can, of course, refine the query: "apple, company". 
It may help BM25 to return entries for apple-as-company, but to certain degree because as isolated, 
independent keywrds, both 'company' and 'apple' can bring many entries, with many companies that 
produce apples, process apples, sell apples, etc.

= From a Bag of Words to a Bag of Meanings

Lexical retrieval systems such as BM25 operate primarily over words or tokens. This creates an 
obvious ambiguity problem: the token "apple" may refer to a fruit, Apple Inc., Apple Records, or 
some other entity. The central question is whether BM25 already resolves this ambiguity, and, if 
not, whether retrieval can instead operate over meanings or conditional interpretations.

== Does BM25 solve word-sense ambiguity?

BM25 does not explicitly distinguish among different meanings of the same token. It is 
fundamentally a bag-of-words ranking function. Given the query:

```text
apple
```

BM25 scores documents based on the occurrence, frequency, rarity, and document-length-normalized 
frequency of the token "apple." It does not represent:

```text
apple as a fruit
```

and:

```text
Apple as a company
```

as different semantic objects.

For example, the following two documents both contain the same lexical token:

```text
Apple released a new iPhone.
```

```text
The apple contains vitamin C.
```

To BM25, the token "apple" is identical in both documents, subject only to tokenizer and normalization behavior.

=== Adding contextual terms

A query such as:

```text
apple company
```

usually improves results because documents about Apple Inc. often contain terms such as "company," "technology," 
"iPhone," "Mac," or "software." However, BM25 still treats "apple" and "company" as separate query terms.

A document such as:

```text
The company grows and sells apples.
```

may also score well because it contains both terms.

BM25 cannot directly express:

```text
company is the intended sense of apple
```

It can only express something closer to:

```text
apple AND company
```

These are not equivalent.

=== Why BM25 often appears to work

BM25 benefits from statistical regularities in language. Documents about Apple Inc. tend to contain terms such as:

```text
iphone, mac, ios, software, tim cook, cupertino
```

Documents about apple fruit tend to contain terms such as:

```text
orchard, tree, juice, cultivar, nutrition, harvest
```

Therefore, additional query terms and document vocabulary can indirectly separate senses. This is distributional evidence, not explicit semantic understanding.

#callout(
  "Key distinction",
  [
    BM25 retrieves documents conditioned on the presence of words. What is desired is retrieval conditioned on the intended meaning of those words.
  ],
)

== 2. A conditional-probability interpretation

The desired operation is not merely:

$ P("document" | "apple", "company") $

but something closer to:

$ P("document" | "apple means Apple Inc.") $

A more complete probabilistic decomposition is:

$ P(D | w) = sum_(m in M(w)) P(D | m) P(m | w) $

where:

- $D$ is a document,
- $w$ is the observed word,
- $M(w)$ is the set of possible meanings of that word,
- $m$ is one candidate meaning.

For the surface form "apple," candidate meanings may include:

- Apple Inc.,
- apple fruit,
- Apple Records,
- Apple Bank.

The system first estimates the intended meaning, then retrieves documents associated with that meaning.

This corresponds to a pipeline such as:

```text
surface word
    ↓
candidate meanings
    ↓
contextual disambiguation
    ↓
canonical meaning or entity
    ↓
retrieval
```

== 3. Entity and sense resolution

Instead of indexing only the raw token "apple," the system can maintain canonical objects:

```json
{
  "id": "org.apple-inc",
  "label": "Apple Inc.",
  "aliases": [
    "Apple",
    "Apple Inc.",
    "Apple Computer",
    "AAPL"
  ],
  "type": "company"
}
```

and:

```json
{
  "id": "concept.apple-fruit",
  "label": "apple",
  "aliases": [
    "apple",
    "apples"
  ],
  "type": "fruit"
}
```

The query:

```text
apple as a company
```

can then be compiled into:

```text
entity_id = org.apple-inc
```

instead of:

```text
apple AND company
```

This is concept or entity retrieval rather than ordinary lexical retrieval.

== 4. Recommended retrieval architecture

BM25 should remain a lexical retriever rather than being forced to solve semantic ambiguity. A semantic layer can operate above it:

1. Resolve surface forms into candidate senses or entities.
2. Use query context to select or weight the candidates.
3. Rewrite the query using canonical identifiers, aliases, types, and related concepts.
4. Execute lexical, vector, graph, and structured retrieval.
5. Re-rank results using semantic consistency.

This preserves BM25's speed and explainability while allowing the overall system to search for meanings rather than isolated words.

= Building a Bag-of-Meanings Retrieval System

The broader goal is to replace a bag of words with a bag of meanings. This requires solving two related problems:

1. How meanings should be represented and stored.
2. How words and phrases should be mapped to meanings in context.

A large language model can perform this mapping, but using one for every token, mention, document, or query is often too expensive, slow, and nondeterministic. A practical alternative is to build a lexical-semantic system around dictionaries, terminology resources, ontologies, deterministic rules, and lightweight classifiers.

== 5. Represent meanings as stable sense objects

A meaning should not be stored only as a textual definition. It should be represented as a stable, machine-addressable sense object.

```json
{
  "sense_id": "apple.n.company.apple-inc",
  "lemma": "apple",
  "part_of_speech": "proper_noun",
  "definition": "The consumer electronics and software company Apple Inc.",
  "sense_type": "organization",
  "canonical_entity_id": "org.apple-inc",
  "aliases": [
    "Apple",
    "Apple Inc.",
    "Apple Computer",
    "AAPL"
  ],
  "context_terms": [
    "iphone",
    "mac",
    "ios",
    "software",
    "technology",
    "cupertino"
  ],
  "negative_context_terms": [
    "orchard",
    "fruit",
    "juice",
    "tree"
  ],
  "broader_concepts": [
    "company",
    "technology company"
  ],
  "related_concepts": [
    "iphone",
    "macos",
    "tim cook"
  ]
}
```

The fruit sense is stored separately:

```json
{
  "sense_id": "apple.n.fruit",
  "lemma": "apple",
  "definition": "The edible fruit of trees in the genus Malus.",
  "sense_type": "biological_object",
  "context_terms": [
    "fruit",
    "tree",
    "orchard",
    "juice",
    "nutrition"
  ],
  "negative_context_terms": [
    "iphone",
    "macos",
    "software"
  ]
}
```

The governing principle is:

#callout(
  "Representation principle",
  [
    Words are surface forms or aliases. Senses are canonical searchable objects.
  ],
)

A document can preserve both the original text and semantic annotations:

```json
{
  "text": "Apple introduced a new processor for the Mac.",
  "mentions": [
    {
      "surface": "Apple",
      "sense_id": "apple.n.company.apple-inc",
      "confidence": 0.99
    },
    {
      "surface": "Mac",
      "sense_id": "product.apple.mac",
      "confidence": 0.98
    }
  ]
}
```

== 6. The dictionary as candidate generator

A dictionary or sense registry can deterministically produce possible meanings:

```text
apple
├── apple.n.fruit
├── apple.n.company.apple-inc
├── apple.n.record-label
└── apple.n.bank
```

The dictionary does not necessarily need to make the final decision. Its primary role is to reduce an open-ended interpretation problem to a small candidate-ranking problem.

Formally:

// $ hat(s) = argmax_(s in S(w)) "compatibility"(s, C) $
$ hat(s) = op("argmax")_(s in S(w)) "compatibility"(s, C) $

where:

- $w$ is the surface form,
- $S(w)$ is the candidate-sense set,
- $C$ is the context,
- $s$ is one candidate sense.

This is much simpler than asking a model to generate an interpretation from scratch.

== 7. Deterministic contextual disambiguation

A practical resolver should combine several inexpensive signals.

=== 7.1 Longest phrase and alias matching

Specific multiword expressions should be resolved before individual tokens:

```text
Apple Inc.    → Apple Inc.
apple juice   → fruit-derived product
Apple TV      → Apple product or service
Apple Records → record label
```

Longest-match and exact-alias rules remove a large fraction of ambiguity.

=== 7.2 Context-term overlap

The local context can be compared with each sense profile.

For example:

```text
Apple released a new version of iOS.
```

strongly overlaps with the company sense and barely overlaps with the fruit sense.

A transparent score can be defined as:

$ "score"(s) =
  sum_(t in C ∩ P_s) w(t, s)
  -
  sum_(t in C ∩ N_s) v(t, s) $

where:

- $P_s$ is the positive context vocabulary for sense $s$,
- $N_s$ is its negative or contradictory vocabulary.

=== 7.3 Type and relation constraints

Syntactic and semantic roles provide stronger evidence than loose word co-occurrence.

For example:

```text
Apple acquired the startup.
```

The agent of "acquired" is normally an organization, person, or government. A fruit is type-incompatible with that role.

This can be encoded as:

```text
acquire.agent ∈ organization | person | government
```

and:

```text
apple.n.company.apple-inc → organization
apple.n.fruit             → food | biological_object
```

Incompatible senses can be removed before ranking.

=== 7.4 Document-level topic priors

A sentence may be ambiguous while the document is not.

A document containing:

```text
processor, smartphone, operating system, developer, software
```

strongly favors the company sense.

A document containing:

```text
orchard, harvest, cultivar, juice, storage
```

strongly favors the fruit sense.

The disambiguation objective can incorporate a document prior:

$ P(s | w, C, D) ∝ P(C | s) P(s | D) P(s | w) $

where $D$ is the larger document context.

== 8. Use a confidence-based cascade

A robust system should not rely on one universal resolver. It should use an escalating cascade:

```text
surface form
    ↓
dictionary candidate generation
    ↓
exact phrase and alias rules
    ↓
type and relation constraints
    ↓
context-vocabulary scoring
    ↓
small embedding model or classifier
    ↓
LLM only for unresolved cases
```

A working policy might be:

```text
one candidate                  → accept
exact canonical alias          → accept
high-confidence rule match     → accept
classifier confidence ≥ 0.90   → accept
otherwise                      → unresolved
```

The unresolved cases can be processed in a slower reconciliation mode. This keeps online retrieval deterministic, fast, and inexpensive.

== 9. Lightweight models between rules and LLMs

There is a useful middle layer between hand-written rules and large language models. Because the dictionary limits the candidate senses, the system can use:

- logistic regression,
- gradient-boosted decision trees,
- a small sentence encoder,
- a compact cross-encoder,
- nearest-neighbor matching against sense examples,
- a domain-specific classifier.

Each sense can store example contexts:

```json
{
  "sense_id": "apple.n.company.apple-inc",
  "examples": [
    "Apple announced a new iPhone.",
    "Apple's revenue increased this quarter.",
    "Developers distribute apps through Apple."
  ]
}
```

The embeddings for definitions and examples can be generated once and cached. Runtime resolution becomes a small closed-set comparison rather than a generative task.

== 10. Preserve uncertainty

A system should not force every occurrence into one sense.

Consider:

```text
Apple prices increased.
```

This may refer to fruit prices, product prices, or a financial interpretation depending on the surrounding corpus.

The resolver can store a weighted candidate set:

```json
{
  "surface": "Apple",
  "candidates": [
    {
      "sense_id": "apple.n.company.apple-inc",
      "score": 0.56
    },
    {
      "sense_id": "apple.n.fruit",
      "score": 0.44
    }
  ],
  "status": "ambiguous"
}
```

The retrieval layer may then:

- search both meanings with proportional weights,
- use the remaining query terms to disambiguate,
- ask the user to choose,
- defer the decision until more context becomes available.

A bag of meanings is therefore often better modeled as a weighted bag of candidate meanings.

== 11. Lexical senses versus canonical entities

Lexical senses and real-world entities are related but distinct.

A lexical-sense layer represents meanings of words:

```text
bank.n.financial-institution
bank.n.river-edge
```

An entity or concept layer represents canonical objects:

```text
org.apple-inc
org.apple-bank
concept.apple-fruit
product.apple-iphone
```

A surface mention may resolve through both layers:

```text
"Apple"
    ↓
lexical sense: apple.n.company
    ↓
canonical entity: org.apple-inc
```

This distinction is important in technical corpora. Terms such as "profile," "latency," or "response time" may denote concepts rather than named entities, and related terms may overlap without being exact synonyms.

== 12. Building the sense inventory

A general-purpose dictionary is a useful starting point but is insufficient for a specialized corpus. A production sense inventory should be layered:

```text
general lexical dictionary
        +
domain terminology and ontologies
        +
corpus-derived senses
        +
organization-specific concepts and entities
```

For example, the word "profile" may mean:

- a descriptive record,
- a geometric cross-section,
- a configuration set,
- a standards-conformance specialization,
- an exposure or concentration pattern.

A standards-focused corpus may require a dedicated sense such as:

```text
profile.n.standards-conformance-specification
```

with examples, applicable domains, relation constraints, and provenance.

== 13. Retrieval over semantic identifiers

Once documents and queries are annotated, the system can build a semantic inverted index:

```text
sense_id → postings
```

For example:

```text
apple.n.company.apple-inc
    → doc17, doc42, doc83

apple.n.fruit
    → doc2, doc8, doc51
```

The query:

```text
apple as a company
```

is compiled into:

```text
sense_id = apple.n.company.apple-inc
```

BM25 itself can still be used if semantic identifiers are treated as terms:

$ "BM25-sense"(D, Q) =
  sum_(s in Q)
  "IDF"(s) dot "TFNorm"(s, D) $

The indexed document may contain several parallel channels:

```text
lexical_vector  → ordinary words
sense_vector    → canonical sense identifiers
entity_vector   → canonical entity identifiers
category_vector → ontology classes
```

Their scores can be combined in a hybrid ranker.

== 14. Recommended system design

A practical implementation can be divided into three components.

=== 14.1 Sense Registry

The registry stores:

- surface forms and aliases,
- stable sense identifiers,
- definitions and examples,
- positive and negative context terms,
- semantic types,
- domain membership,
- relations and constraints,
- parent and related concepts,
- disambiguation rules,
- provenance and version history.

=== 14.2 Contextual Resolver

The resolver performs:

- candidate generation,
- phrase recognition,
- type filtering,
- local-context scoring,
- document-prior scoring,
- optional lightweight classification,
- confidence estimation,
- ambiguity preservation.

=== 14.3 Semantic Index

The indexing pipeline stores:

- original text,
- lexical terms,
- resolved sense identifiers,
- weighted unresolved candidates,
- canonical entity identifiers,
- ontology categories,
- confidence and provenance.

The query pipeline must use the same sense registry and compatible resolution logic as the document pipeline.

== 15. Role of the LLM

The LLM should be a maintenance and reconciliation tool, not an online dependency.

It can assist with:

- discovering missing senses,
- generating definitions and examples,
- identifying unresolved-context clusters,
- proposing merges or splits,
- suggesting context terms,
- validating contradictory mappings,
- enriching relations and ontology links.

Only validated results should be promoted into the operational dictionary.

The resulting architecture is:

```text
words
  ↓
dictionary and sense registry
  ↓
candidate meanings
  ↓
deterministic contextual resolver
  ↓
weighted semantic identifiers
  ↓
semantic inverted index
  ↓
retrieval and ranking
```

This captures much of the value of semantic interpretation while keeping normal retrieval fast, deterministic, inspectable, and inexpensive.
