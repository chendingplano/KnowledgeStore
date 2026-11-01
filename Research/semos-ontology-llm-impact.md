---
Date: 2026/11/01
Contributors: ChatGPT, Chen Ding
---

## 1. Highlights
- Understanding: Making information interpretable by a machine.
- Organization: Making information discoverable, comparable, and reusable.
- Reasoning: Deriving new knowledge from existing knowledge according to defined semantics.
- OWL reasoning is logically constrained, whereas LLM reasoning is semantically flexible
- Ontology is fundamentally a formal specification of concepts, relations and their intended semantics
- Ontology can becomre more useful when it shifts from enabling machine understanding to establishing
  shared, precise semantics 
- Formal reasoning does not eliminate uncertainty introduced during knowledge extraction. It prevents additional nondeterminism during the reasoning stage.
- Organize knowledge in three levels: L1: Lightweight semantics, L2: structured knowledge, L3: formal semantics
- Natural language as the primary knowledge source, lightweight semantics as the retrieval infrastructure, structured knowledge as the analytical substrate, and formal logic as an optional verifiation and reasoning layer.

The central argument:

> LLMs reduce the need to transform unstructured knowledge into structured representations merely to make that knowledge computationally accessible.

However, we need to distinguish between three purposes of knowledge representation:

1. Understanding: Making information interpretable by a machine.
2. Organization: Making information discoverable, comparable, and reusable.
3. Reasoning: Deriving new knowledge from existing knowledge according to defined semantics.

LLMs have dramatically changed the first, substantially changed the second, but have not eliminated the need for formal methods in the third.

## 1. The historical shift: from symbolic knowledge to LLMs

Before LLMs, conventional software could not reliably interpret arbitrary natural-language statements.

Consider:

> John is a software engineer employed by Google. Google is a technology company headquartered in Mountain View.

A conventional application might need to transform this into:

```
ex:John rdf:type ex:SoftwareEngineer .
ex:John ex:worksFor ex:Google .
ex:Google rdf:type ex:TechnologyCompany .
ex:Google ex:headquarteredIn ex:MountainView .
```

Then, given an ontology:

```
ex:SoftwareEngineer rdfs:subClassOf ex:Employee .
ex:TechnologyCompany rdfs:subClassOf ex:Organization .
```

A reasoner could derive:

```
ex:John rdf:type ex:Employee .
ex:Google rdf:type ex:Organization .
```

Today, an LLM can read the original paragraph and derive these facts directly, without requiring RDF, OWL, or a knowledge graph.

Moreover, an LLM can answer questions that would require considerably more sophisticated symbolic modeling.

For example:

> Is John likely to have experience working in a large technology organization?

An LLM can provide a qualified answer based on general knowledge and the supplied context. An OWL reasoner cannot derive this conclusion unless the relevant concepts and inference rules are explicitly modeled.

This reveals an important difference:

OWL reasoning is logically constrained, whereas LLM reasoning is semantically flexible.

Neither completely replaces the other.

## 2. Ontology is more than converting unstructured knowledge into structured knowledge

> Ontology is also a way of turning unstructured to structured.

This describes a common application of ontology, but not its essential purpose.

An ontology is fundamentally a formal specification of concepts, relationships, and their intended semantics.

For example:

```
ex:Employee rdfs:subClassOf ex:Person .
ex:worksFor rdfs:domain ex:Employee .
ex:worksFor rdfs:range ex:Organization .
```

The ontology does not necessarily contain facts about John or Google. Instead, it defines the semantics used to interpret such facts.

It helps to distinguish:

| Component                 | Purpose                                       | Example                                              |
| ------------------------- | --------------------------------------------- | ---------------------------------------------------- |
| Natural-language document | Express knowledge                             | John works for Google                                |
| Knowledge base            | Represent factual assertions                  | `(John, worksFor, Google)`                           |
| Ontology                  | Define concepts and their semantics           | Domain of `worksFor` is `Employee`                   |
| Reasoner                  | Derive logical consequences                   | John is an Employee                                  |
| LLM                       | Interpret, generate, and reason over language | Understand the relationship without explicit triples |

An LLM can perform several of these functions, but that does not make them conceptually identical.

In fact, ontology can become more useful when its primary role shifts from enabling machine understanding to establishing shared, precise semantics.

## 3. Where LLMs + RAG can replace ontology and symbolic reasoning

Consider three questions:

| Question                              | LLM + RAG                    | OWL                        |
| ------------------------------------- | ---------------------------- | -------------------------- |
| Who does John work for?               | Retrieve and answer directly | Query asserted triples     |
| Is John an employee?                  | Infer from retrieved text    | Infer using domain         |
| What responsibilities does John have? | Interpret relevant passages  | Requires explicit modeling |

For these relatively straightforward questions, there is often little justification for constructing and maintaining a comprehensive OWL knowledge base.

The costs of ontology engineering are substantial: defining classes, properties, restrictions, mappings, extracting instances, resolving identities, and keeping everything synchronized.

An LLM + RAG system avoids much of this upfront work.

But there is a qualification: RAG retrieval is not guaranteed to retrieve all the information necessary for a correct answer. An LLM's reasoning ability cannot compensate for evidence that was never retrieved, except by guessing or relying on prior knowledge.

This becomes particularly important when questions require exhaustive coverage, complex dependencies, or evidence distributed across many documents.

## 4. Where formal symbolic reasoning remains valuable

We will explore the valules of symbolic approaches from four areas.

### 4.1 Deterministic and reproducible reasoning

Consider a technical standard:

> If a device operates above 100°C and contains a pressurized fluid, it must satisfy safety requirement R17.

We can express the rule conceptually as:

$$Temperature(x)>100 \land Pressurized(x) \Rightarrow Requires(x,R17)$$

Suppose the knowledge base contains:

```
Device A operating temperature = 120°C
Device A contains pressurized fluid = true
```

A deterministic rule engine can conclude:

```
Device A requires R17.
```

An LLM can reach the same conclusion, but a formal engine provides a much stronger guarantee that the same inputs and rules produce the same conclusion.

One technical distinction: this particular rule is better represented using Datalog, a rule engine, or an OWL-compatible rule extension than OWL alone. OWL is not a general-purpose programming or arithmetic rule language.

### 4.2 Complex logical relationships

OWL can express relationships that are not immediately obvious from individual facts.

For example:

```
ex:hasParent a owl:ObjectProperty ;
    owl:inverseOf ex:hasChild .
```

Given:

```
ex:Alice ex:hasChild ex:Bob .
```

We can derive:

```
ex:Bob ex:hasParent ex:Alice .
```

OWL can also represent transitivity, property chains, disjointness, cardinality restrictions, equivalence, and other logical constructs.

An LLM can reason about these concepts, but it does not provide the same formal completeness and soundness guarantees as a suitable OWL reasoner.

### 4.3 Exhaustive analysis across large knowledge bases

Imagine a knowledge base containing:

- 100,000 technical standards
- 10 million extracted requirements
- 5 million equipment specifications
- 20 million relationships

Suppose we need to identify every equipment specification that violates a particular requirement.

An LLM + RAG approach may retrieve relevant examples and reason correctly about them.

However, retrieval-based answering does not guarantee that every relevant item was found.

A structured knowledge base combined with deterministic queries and rules can support exhaustive analysis over the represented facts.

The qualification is important: exhaustiveness applies to the knowledge actually represented and the rules evaluated, not necessarily to everything present in the original documents.

### 4.4 Explainability and traceability

Formal reasoning can produce an explicit derivation:

Rule R1: Temperature above 100°C AND pressurized → Requires R17
Fact F1: Device A = 120°C
Fact F2: Device A is pressurized
Derived conclusion: Device A requires R17

The derivation is explicit, inspectable, and reproducible.

LLMs can generate explanations, but those explanations are not necessarily faithful records of the computation that produced the answer.

For regulated domains, that distinction matters.

## 5. Hybrid architecture

> Use LLMs to construct OWL/ontology or knowledge bases in general, then use formal reasoning to eliminate the nondeterministics of LLMs.

Formal reasoning does not eliminate uncertainty introduced during knowledge extraction. It prevents additional nondeterminism during the reasoning stage.

For example, suppose an LLM incorrectly extracts:

```
ex:DeviceA ex:operatingTemperature "120" .
```

when the original document actually states 80°C.

A deterministic reasoner will faithfully derive conclusions from the incorrect fact.

This suggests an architecture with explicit separation of extraction, verification, and inference.

```text
Source documents
  -> Standards, regulations, specifications
  -> LLM interpretation and extraction: 
        Entities · Relations · Rules · Concepts
  -> Verification and normalization
        Source evidence · Identity resolution · Units · Schema validation
  -> Structured knowledge base
        Facts · Ontology · Rules · Provenance
  -> Deterministic reasoning engine
        OWL · Datalog · SHACL · SQL · Constraint solvers
  -> Verified logical conclusions
        Derivations · Evidence · Validation results
```

The architecture combines the flexibility of language interpretation with the rigor of formal reasoning.

It also separates two kinds of correctness:

- Epistemic correctness: Are the extracted facts and rules faithful to the source?
- Logical correctness: Does the conclusion follow from those facts and rules?

Formal reasoning primarily addresses the second.

## 6. A further distinction: ontology versus knowledge organization

For SemOS, I would distinguish three levels of semantic representation.

| Level                     | Representation                                         | Primary value                            |
| ------------------------- | ------------------------------------------------------ | ---------------------------------------- |
| L1: Lightweight semantics | Keywords, topics, categories, aliases, embeddings      | Discovery and retrieval                  |
| L2: Structured knowledge  | Entities, attributes, relations, requirements, metrics | Comparison, integration, analysis        |
| L3: Formal semantics      | Ontologies, logical axioms, constraints, rules         | Deterministic inference and verification |

These levels are complementary rather than strictly sequential.

Not every extracted entity needs an OWL class. Not every relationship needs formal logical semantics. And not every document needs to be converted into a knowledge graph.

In fact, I would avoid building a comprehensive OWL ontology for an entire corpus unless the intended applications justify it.

Instead, I would use selective formalization:

Keep most knowledge in its original textual form, enrich it with lightweight semantic structures, and formalize only the concepts and rules that benefit from deterministic reasoning.

For example, in standards analysis:

- A descriptive paragraph about equipment maintenance may remain natural language.
- A metric such as maximum operating pressure should be extracted into a typed structure.
- A mandatory requirement should be represented as a structured obligation with conditions and applicability.
- A safety-critical compliance rule may be formalized into executable logic.

This substantially reduces the cost of knowledge engineering while retaining the benefits of symbolic reasoning where they matter.

## 7. One more important insight: formal semantics can guide retrieval, not just reasoning

There is another role for ontology that I think deserves attention.

Consider a user asking:

> Find all requirements applicable to refrigerated vaccine transportation.

The relevant documents may use terminology such as:

- Cold-chain logistics
- Temperature-controlled distribution
- Refrigerated transport
- Biological product transportation
- Pharmaceutical cold storage

A lightweight ontology can encode broader/narrower relationships, synonyms, and other semantic associations.

These can guide retrieval even before any formal inference occurs.

For example:

```
Vaccine transportation
    → Pharmaceutical distribution
    → Temperature-controlled logistics
    → Cold-chain management
```

An LLM may generate these connections from its general knowledge, but an explicit domain vocabulary provides a consistent, corpus-specific reference that can be maintained and verified.

This is closer to SKOS-style knowledge organization than full OWL reasoning.

For a retrieval-oriented system, this lighter semantic layer may deliver more practical value than a sophisticated logical ontology.

## 8. My conclusion

I would summarize the evolution as follows:

| Era                           | Central problem                                                                 | Typical solution                                          |
| ----------------------------- | ------------------------------------------------------------------------------- | --------------------------------------------------------- |
| Traditional software          | Computers cannot interpret natural language                                     | Convert knowledge into structured data                    |
| Semantic Web / OWL            | Computers need explicit shared semantics and logical inference                  | Ontologies and formal knowledge representations           |
| LLM + RAG                     | Computers can interpret natural language but need relevant evidence             | Retrieval plus language-model reasoning                   |
| Hybrid neuro-symbolic systems | Language understanding is flexible but not sufficiently reliable for every task | LLM interpretation plus formal verification and reasoning |

The most important architectural change is that knowledge no longer needs to be fully formalized before it becomes useful to software.

That changes the economics of knowledge engineering dramatically.

Previously, formalization was often a prerequisite for computational use. Now it can be an optional investment made where precision, exhaustiveness, consistency, or reproducibility justify its cost.

For SemOS, I would adopt this principle:

Natural language as the primary knowledge source, lightweight semantics as the retrieval infrastructure, structured knowledge as the analytical substrate, and formal logic as an optional verification and reasoning layer.

One final observation: OWL itself is not necessarily the most important symbolic technology in such a system. For standards and regulatory knowledge, Datalog, SHACL, SQL constraints, temporal logic, and domain-specific rule engines may sometimes be more practical than OWL's description logic.

The long-term opportunity is not necessarily to combine LLMs with OWL, but to combine probabilistic semantic interpretation with deterministic symbolic computation, choosing the appropriate representation and reasoning method for each problem.&#x20;
