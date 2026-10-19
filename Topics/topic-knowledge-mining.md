---
ID: topic-knowledge-mining
Contributors: ChatGPT, Chen Ding
Create Date: 2026/10/19
Keywords: knowledge, knowledge-mining
---

# 1. Overview
Knowledge is very important but very difficult to handle. To help understand what exactly knowledge is, 
we can use a Goal-Oriented Knowledge Model to define knowledge.

The center of a knowledge model is a goal, such as Product X Quality. Contextual information, such as 
tools, materials, storage, transportation, manufacturing, environments, and many other factors that are 
may potentially affect the quality of Product X is extracted or collected. This forms a Knowledge Model 
for the knowledge of "Product X Quality". The model includes all the possible factors. Knowledge mining 
then extract related materials and feed them to the model. 

## 1.1 What exactly is knowledge

A useful starting point is to distinguish four levels of information.

| Level                 | Example: Product X Quality                                                                                                   |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Data                  | Storage temperature = 8°C                                                                                                    |
| Information           | Product X was stored at 8°C for 12 hours                                                                                     |
| Knowledge             | Prolonged exposure above a specified temperature may degrade Product X                                                       |
| Operational knowledge | To maintain quality, keep temperature within an established range and limit excursions according to validated stability data |

The essential difference is that knowledge describes relationships, regularities, mechanisms, constraints, or procedures that can be applied beyond a single observation.

**Relations**, however, should be used with care. SemOS does have processors to extract
entities and relations. It can extract huge amount of entities and relations.
The problem with this approach is that entities and relations are flooded, may not
be well normalized/canonicalized. Canonicalizing entities and relations can be
challenging unless a stable vocabulary is in place and all the entities and
relations use that vocabulary. But in reality, that vocabulary, if any, will
change, constantly.

Organizing entities and relations around goals can alleviate the problem (solving the 
problem completely can be very challenging).

Consider these statements:

- Product X was stored at 8°C. This is an observation.
- Product X must be stored between 2°C and 8°C. This is a normative requirement.
- Higher temperatures accelerate degradation of Product X. This is a scientific relationship.
- The degradation rate depends on temperature and exposure duration. This is a conditional relationship.
- If the predicted degradation exceeds an acceptable threshold, reject the batch. This is a decision rule.

All five are useful. However, the last four encode different forms of knowledge, while the first is primarily factual data.

There is no universally sharp boundary between data and knowledge. For engineering purposes, I suggest defining knowledge in SemOS as:

> A reusable, evidence-grounded representation of relationships, constraints, mechanisms, procedures, or decision rules that enables explanation, prediction, or action under specified conditions.

This definition is deliberately broader than scientific knowledge. It accommodates technical standards, regulations, manufacturing processes, engineering design, and scientific publications.

# 2. Architecture
## 2.1 Goal-Oriented Knowledge

A Knowledge Model is created around a goal:
1. Knowledge is organized around a goal, rather than merely around entities, topics, or document categories.
2. Knowledge describes how different factors influence that goal, including their relationships, 
   mechanisms, conditions, and constraints.
3. Knowledge can be operationalized, not just retrieved. It can support prediction, optimization, inverse 
   design, and decision-making.

It involves:
- Knowledge Model
- Extracted Knowledge
- Reasoning Models built from that knowledge

These are three different things, and keeping them separate would make SemOS substantially more flexible.

## 2.2 Goal-oriented Knowledge Model

A goal-oriented knowledge model involves:
- Goal: Maintain or improve Product X quality.
- Target variable: A measurable representation of quality.
- Factors: Variables that may affect the target.
- Relationships: How the factors influence the target or one another.
- Constraints: Requirements that limit acceptable conditions or actions.
- Evidence: Documents, experiments, measurements, and observations supporting the relationships.
- Reasoning
- Actions

The distinction between a goal and a target variable matters. "Improve quality" is an objective, while "defect rate" or "product stability" is something that can be measured or predicted.

**Example: Product X Quality Model**
![An example of goal-oriented model](../images/image_2026101901.png)

This is an excellent starting structure for knowledge mining.

However, the diagram hides a fundamental challenge: knowing which factors exist is not the same as knowing how those factors affect quality.

For example, suppose we identify:

- Temperature
- Storage duration
- Humidity
- Packaging material
- Product degradation

A taxonomy or entity graph can represent these five concepts.

But actual knowledge requires relationships such as:

- Temperature influences degradation rate.
- Storage duration influences cumulative degradation.
- Packaging modifies the effect of humidity.
- The impact of temperature depends on the product's chemical composition.

These relationships make the model useful for reasoning.

Importantly, some extracted relationships may be correlations rather than established causal effects. SemOS should preserve that distinction instead of automatically treating every reported influence as causation.

## 2.3 Three layers: Knowledge Model, Knowledge Base, and Reasoning Model

![Layered model](../images/image_2026101902.png)

These layers are conceptually distinct, although an implementation can have feedback loops between them.

### 2.3.1 Knowledge Model: What do we want to know?

The Knowledge Model is a schema or conceptual framework. It defines the types of knowledge that SemOS should look for.

For Product X Quality, it might specify:

```
knowledge_model:
  target: product_quality

  target_metrics:
    - defect_rate
    - degradation_rate
    - product_stability

  factor_categories:
    - materials
    - manufacturing
    - storage
    - transportation
    - environment

  relationship_types:
    - influences
    - causes
    - correlates_with
    - depends_on
    - mitigates
    - requires
    - prohibits

  knowledge_types:
    - empirical_relationship
    - causal_mechanism
    - constraint
    - procedure
    - predictive_equation
```

This is not yet a collection of knowledge. It is a framework for organizing and extracting knowledge.

Do not have to have a complete list of all possible factors. In an open scientific domain, such a list is practically impossible to construct.

Instead, use an open-world, extensible Knowledge Model: begin with known factors, then allow knowledge mining to discover additional factors and relationships.

For example, a paper might reveal that packaging permeability is an important factor. SemOS should be able to add it without redesigning the schema.

### 2.3.2 Knowledge Base: What do we actually know?

The Knowledge Base contains extracted and normalized knowledge instances.

Consider this illustrative statement:

> For Product X, higher storage temperatures accelerate degradation, with the effect depending on exposure duration.

A possible structured representation is:

```
knowledge:
  subject: storage_temperature
  relation: influences
  object: degradation_rate

  direction: positive

  conditions:
    product: Product X
    process: storage

  modifiers:
    - exposure_duration

  evidence:
    - document_id: paper_123
      section: results

  evidence_type: experimental
  causal_status: suggested
  confidence: 0.85
```

The confidence value is illustrative, not a measured score.

This is a knowledge instance, not a Knowledge Model. It can be linked to many goals, such as quality control, shelf-life estimation, and logistics optimization.

A key design decision is to store the knowledge independently of the goal. The same knowledge should be reusable across multiple goal-oriented views.

It should also store the original claim, exact source span, applicable conditions, uncertainty, and whether the evidence is observational, experimental, theoretical, or regulatory.

For SemOS's standards corpus, this is especially important. A mandatory regulatory requirement is not equivalent to an experimentally established scientific relationship.

### 2.3.3 Reasoning Models: What can we do with knowledge?

A reasoning model turns extracted knowledge into an operational capability.

For example, suppose we have a validated degradation model:

$$D = f(T,t,H,P)$$

where:

- $D$: product degradation
- $T$: storage temperature
- $t$: storage duration
- $H$: humidity
- $P$: packaging characteristics

The predictor estimates degradation under a given set of conditions.

But the Knowledge Base might also contain qualitative relationships, regulatory constraints, and procedures that cannot be directly represented by this predictor.

Therefore, the Knowledge Base is broader than any individual predictive model.

This distinction is particularly important because not all knowledge needs to be learned through machine learning.

| Knowledge type                       | Appropriate reasoning method            |
| ------------------------------------ | --------------------------------------- |
| Mandatory storage temperature range  | Rule engine                             |
| Temperature–degradation relationship | Predictive model or physical equation   |
| Packaging reduces moisture exposure  | Causal or mechanistic reasoning         |
| Manufacturing sequence               | Workflow/process model                  |
| Conflicting regulatory requirements  | Evidence comparison and legal reasoning |
| Optimal manufacturing parameters     | Constrained optimization                |

The practical lesson is that a predictor is one possible consumer of knowledge, not the final destination of every knowledge-mining pipeline.

### 2.3.4 Inverse design: From predicting outcomes to finding solutions

This is where the proposed knowledge model becomes particularly interesting.

Traditional prediction answers:

> Given the materials, manufacturing process, and storage conditions, what will Product X's quality be?

Inverse design reverses the question:

> Given a required quality level, what materials, processes, and storage conditions should we choose?

Suppose a predictor estimates:

$$Q=f(M,P,S,E)$$

where $Q$ is product quality and $M,P,S,E$ represent materials, processes, storage, and environmental conditions.

Inverse design searches for a configuration:

$$\max\_{M,P,S,E} Q(M,P,S,E)$$

subject to constraints such as:

$$\begin{aligned} \text{Cost} &\leq \text{Budget}\\\ \text{Temperature} &\in [T\_{\min},T\_{\max}]\\\ \text{Materials} &\in \text{Approved Materials}\\\ \text{Process} &\in \text{Validated Processes} \end{aligned}$$

Here, the knowledge extracted from scientific literature and standards has two roles:

1. Predictive guidance: Help estimate which configurations are likely to produce better outcomes.
2. Constraint guidance: Restrict the search to configurations that are physically feasible, legally permitted, or scientifically justified.

For example, an optimizer might discover that a certain manufacturing temperature maximizes predicted quality. But if a regulatory requirement prohibits that temperature, the candidate must be rejected.

This is a powerful combination of machine learning and symbolic knowledge.

There is one important qualification: the optimization system must distinguish controllable variables from observed or uncontrollable variables. Otherwise, it may propose solutions that cannot actually be implemented.

Also, an optimizer can exploit errors in a predictor. Candidate designs should therefore be checked against model uncertainty, training-data coverage, and, where appropriate, simulation or experiment.

### 2.3.5 An important extension: Knowledge should not always be goal-oriented

**Goal-oriented knowledge model** is only one type of knowledge models. 
It starts with a question or objective:

- What affects Product X quality?
- How can manufacturing cost be reduced?
- How can vaccine storage stability be improved?

**Domain-oriented knowledge** describes relationships without requiring a specific goal:

- Temperature affects chemical reaction rates.
- Humidity influences moisture-sensitive materials.
- Packaging permeability influences moisture transfer.
- Manufacturing parameters affect material microstructure.

The second category is important because the same knowledge can serve many goals.

For example:
![Domain-oriented knowledge model](../images/image_2026101903.png)

SemOS stores domain knowledge independently, while using goals to construct contextual 
Knowledge Models or views.

This gives SemOS the benefits of goal-oriented knowledge mining without duplicating 
knowledge or restricting future applications.

### 2.3.6 Knowledge is not necessarily predictive

The goal-oriented knowledge model is:

```text
Knowledge Model → Knowledge Mining → Predictor → Inverse Design.
```

This is appropriate for quantitative scientific domains.

However, SemOS deals with a much broader range of documents, including standards, regulations, specifications, and technical literature.

For many of these, prediction is not the primary objective.

Consider three examples:

| Goal                    | Extracted knowledge                                      | Application                     |
| ----------------------- | -------------------------------------------------------- | ------------------------------- |
| Product quality         | Environmental conditions influence degradation           | Predictive optimization         |
| Regulatory compliance   | A particular process requires periodic calibration       | Compliance checking             |
| Engineering reliability | A failure mode occurs under certain operating conditions | Failure analysis and prevention |

The knowledge representation can be similar, but the downstream reasoning methods differ.

In fact, SemOS could provide considerable value before implementing any predictive models.

For example, an agent could answer:

> Which factors affect the reliability of this device, what mechanisms explain their effects, and which standards constrain the available mitigation strategies?

Answering this question requires a substantial amount of knowledge integration, but no trained predictor.

### 2.3.7 Goal Relations
Goals can be related in many ways:
- Causal: Goal A can affect goal B
- Temporal: The impact of goal A increases/decreases as time goes by
- Sequential: Goal A, then B, C
- ???: Goal A and B go hand-by-hand, such as if Product X quality goes up,
  Product X sales goes up

## 2.4 Knowledge Mining
Knowledge mining does not stop here. It uses the extracted to train a predictor, which can be used to "search for inverse design, explicitly guided by constraints derived from the extracted scientific knowledge".

## 2.5 Implementation

Build it incrementally rather than attempting to construct a comprehensive knowledge system immediately.

1. Start with knowledge claims.

   Extract atomic statements describing relationships, constraints, mechanisms, and procedures. Preserve their provenance, applicability, and epistemic status. Keep them distinct from factual observations.
2. Normalize and connect claims.

   Resolve entities, units, aliases, and relation types. Merge genuinely equivalent claims while retaining contradictory evidence. Use the existing L1 extraction infrastructure as the foundation.
3. Build goal-oriented Knowledge Models dynamically.

   When the user asks about Product X Quality, SemOS identifies the target variables, retrieves relevant knowledge, expands relationships to intermediate factors, and constructs a contextual knowledge graph.
4. Support explanation and constraint reasoning first.

   Enable questions about influencing factors, mechanisms, dependencies, requirements, and conflicts. This can be done with a combination of graph traversal, search, and LLM reasoning.
5. Introduce predictive models when sufficient quantitative data exists.

   Where the available evidence supports it, train or fit predictors and use them for optimization or inverse design. Otherwise, use rule-based, qualitative, or mechanistic reasoning.

One subtle architectural point: I would not automatically equate L2 with a knowledge graph. Your existing Scene Blocks can represent situations, procedures, and generalized lessons that do not fit naturally into subject–predicate–object triples.

A useful design is to make knowledge claims the common underlying objects, with graphs, Scene Blocks, goal-oriented models, and predictors acting as different representations or consumers of those claims.

### 2.5.1 From extracted relationships to trustworthy knowledge

This is probably the hardest problem, the central research and engineering challenge for SemOS.

Suppose SemOS extracts these three statements from different documents:

- Document A: Increasing temperature accelerates degradation.
- Document B: Temperature has little effect within a particular range.
- Document C: Degradation depends primarily on humidity.

Are these contradictory?

Not necessarily. They might describe different materials, temperature ranges, environmental conditions, or experimental setups.

A naive knowledge graph might store three relationships and report a conflict.

A more sophisticated system must understand the scope of each claim.

SemOS makes the following properties first-class elements of a knowledge claim:

- Applicability: What materials, products, processes, or situations does the claim cover?
- Conditions: Under what circumstances is the claim valid?
- Relationship: What exactly is asserted, including direction and magnitude when available?
- Evidence: What observations, experiments, standards, or theories support it?
- Uncertainty: How reliable is the claim, and what remains unknown?
- Provenance: Where did it originate?
- Exceptions: When does the claim not apply?

This is arguably more important than choosing a sophisticated graph database or ontology language.

A large collection of unqualified relationships is not necessarily a trustworthy knowledge base.

## 2.6 Overall Assessment

We probably need to slightly revise your original conceptual framework.

Instead of:

```text
Goal → Knowledge Model → Knowledge Mining → Predictor → Inverse Design
```

we may:
![Knowledge Model](../images/image_2026101904.png)

This is a logical architecture, not necessarily a strict execution sequence. Goal-oriented models can also guide additional mining when knowledge gaps are discovered.

The most significant difference from your proposal is that knowledge mining does not have to begin with a specific goal, and knowledge does not have to end in a predictor.

A reusable knowledge base becomes the foundation. Goals determine which knowledge is relevant and how it should be used.

For SemOS, I would make the next major milestone knowledge-claim extraction and normalization, rather than predictive modeling. Once SemOS can reliably represent what is known, under which conditions, and according to which evidence, it can support many different forms of reasoning—including inverse design when appropriate.

That would be a substantial progression from a document knowledge base toward a knowledge reasoning system.&#x20;
