# ADR 2026081701 — Ontology Object Classes, Normalized Metric Instances, and Semantic Relations

**Date:** 2026-08-17 \
**Status:** Proposed \
**Component:** ChenWeb — ontology terms, class contracts, keyword concepts, semantic assertions, assertion evidence, assertion relations, metric processing, and Review Document \
**Authors:** Chen Ding (with Codex) \
**Related:** ADR `2026072901` (ontology platform and adaptive pipeline), ADR `2026081201` (auto-promoted governed terms), ADR `2026081401` (governed metric vocabulary and Phase D failure reporting), user manual `metric-assertion-semantic-processing-v1.2-en.md` §6.11 \
**Tags:** ontology, object class, object instance, metrics, semantic identity, evidence, evolving schema, autonomous resolution, Review Document

## 1. Change Log

* 2026/08/17, initial proposal after investigating user manual §6.11 and the live implementation.
* 2026/08/17, rewritten after review stopped during DR3. The rewrite:
  * recognizes that existing `kb.ontology_terms` rows are vocabulary identities rather than usable
    ontology object classes;
  * makes the class, instance, evidence, and occurrence layers explicit;
  * adopts an evidence-first logical pipeline;
  * defines one current assertion candidate per atomic metric occurrence while retaining generic
    many-to-many evidence storage;
  * defines ontology classes as evolving, versioned contracts synthesized from observed instances,
    without treating every observed value as valid;
  * makes same-class recognition a primary architectural decision; and
  * resolves reviewer Issues 01–06 and Thoughts 01–04.

## 2. Context

### 2.1 The implemented term layer is not an ontology object-class layer

The original proposal assumed that a `kb.ontology_terms` row with
`term_kind = 'metric_definition'` defined the semantics and syntax of one metric class. The live
implementation does not support that assumption.

For example, term row `12428`, `measurement:auto:kwc_fe55f891fd00`, has a preferred label
`其他垃圾收运频率`, but no definition, value type, range type, permitted units, axioms, mappings, or
profile rules. Its associated keyword-to-term alignment assertion says only that it was
auto-created. The normalized metric assertion separately contains the value, unit, comparator, and
raw text, but the supposed class does not define what those fields mean or which forms are valid.

A production survey on 2026/08/17 found 182 auto-promoted `metric_definition` terms. Fifty-five were
completely label-only, only 45 had definitions, and only seven identified permitted units. Even
populated rows frequently copied free-text properties from one occurrence rather than defining a
governed class contract.

Therefore, the existing `kb.ontology_terms` table is an identity and vocabulary registry. It can
identify that a term exists and store its labels and lifecycle, but a row alone is not an ontology
object class. Treating it as one would build instance identity and comparison on an empty semantic
foundation.

### 2.2 The required ontology has two semantic layers and two provenance layers

The design requires four distinct objects:

```text
source occurrence        evidence/link           normalized instance       object class
kb.metrics M  ---------> kb.assertion_evidence -> kb.semantic_assertions A -> kb.ontology_terms T
                                                      instance_of -----------^
                                                                            |
                                                     kb.ontology_class_contracts
```

The layers have different responsibilities:

| Layer | Responsibility |
|---|---|
| Source occurrence | What one document-processing run extracted, including source wording, spans, model, prompt, and confidence. |
| Evidence | Why a normalized instance exists and which occurrence supports or contradicts it. |
| Ontology object instance | A normalized claim with subject, value, conditions, modality, and value state. Multiple source occurrences may support the same instance. |
| Ontology object class | A stable semantic identity plus a versioned contract defining the instance's attributes, logical datatypes, constraints, and comparison semantics. |

For metrics, `kb.metrics` is the source-occurrence store and `kb.semantic_assertions` is reused as
the ontology object-instance store. This does not make every semantic assertion a metric. The table
remains generic, and only assertion kinds representing normalized object instances carry an
`instance_of` class relationship.

### 2.3 Motivating example

Assume:

```text
A: display luminance >= 250 cd/m2
B: display luminance >= 300 cd/m2
```

The correct representation is:

```text
ontology object class T: Display Luminance
  contract:
    quantity: luminance
    logical value type: numeric luminance quantity
    permitted dimension/unit family: cd/m2
    comparison rule: lower-bound requirement

ontology object instance A:
  instance_of T
  normalized value: >= 250 cd/m2

ontology object instance B:
  instance_of T
  normalized value: >= 300 cd/m2

relation:
  B stronger_than A
  A weaker_than B       # inverse projection

metric occurrence A -> evidence A -> instance A
metric occurrence B -> evidence B -> instance B
```

A and B are instances of the same class but are different claims. If another document contains the
same normalized claim as A, its occurrence may provide additional evidence for instance A rather
than create a duplicate instance.

### 2.4 Three identity questions must not be conflated

The system must answer three different questions:

1. **Same occurrence:** Is a newly extracted metric the same source artifact as a metric from an
   earlier processing of the same document?
2. **Same normalized instance:** Do two occurrences express the same subject, metric class, value,
   unit, comparator, conditions, modality, and applicability?
3. **Same ontology class:** Do differently named or structured artifacts instantiate the same
   logical metric or other ontology object class?

The Phase-2 metric merge mechanism addresses question 1. Canonical assertion identity addresses
question 2. Keyword and ontology reconciliation address question 3. A positive result at one level
does not automatically answer either of the other levels.

### 2.5 Current assertion identity does not converge equivalent occurrences

`MetricNormalizer` currently creates a decision candidate with the occurrence-derived logical key:

```text
metric:<input-record-id>:<metric-id>
```

`associate_semantics` copies that identity into `kb.semantic_assertions`. Consequently, two source
metrics cannot converge on one normalized assertion even when their semantic payloads are identical.
The class term is carried only in qualifier JSON and does not participate through a typed,
versioned `instance_of` relationship.

The current relation table also cannot represent the required relation set, and the association
pipeline does not populate it. Same-class instances therefore remain isolated rows.

### 2.6 Review Document is the minimum competency test

Review Document must be able to process a document, find the normalized instance for every metric
occurrence, find its ontology class, retrieve other instances of that class, and compare their
source evidence. Today it primarily discovers peers through lexical/vector similarity, shared
categories, and object anchors.

Similarity is useful for candidate discovery. It cannot guarantee same-class identity or explain
why two artifacts are comparable. If the ontology subsystem cannot support the Review Document
class-to-instance traversal, its most important semantic relationship is missing.

### 2.7 Human design is ideal but cannot be mandatory

Human domain experts should define and lock important ontology classes. It is not practical to
require human design for every class discovered in a large and continuously changing corpus.

The system therefore needs a hybrid model:

* curated class contracts for critical artifacts;
* deterministic synthesis and evolution where evidence is sufficient;
* statistical and LLM-assisted proposals for ambiguity that deterministic rules cannot resolve;
* versioned policy-controlled autonomous activation; and
* optional human correction, locking, merge, or split at any time.

Human involvement is never a runtime prerequisite for ordinary document processing.

## 3. Decision

### 3.1 DR1 — Establish ontology object class and object instance as first-class concepts

The terms **ontology object class** and **ontology object instance** are normative throughout the
design and implementation.

An ontology object class defines the shared semantic and syntactic contract for a family of
instances. An ontology object instance is a normalized claim that explicitly instantiates one
class; it is not the source occurrence, and multiple occurrences may support it.

For the metric pilot:

* `kb.ontology_terms`, together with the class-contract records defined in DR2, identifies and
  defines the ontology object class;
* `kb.semantic_assertions` stores normalized metric instances;
* `kb.assertion_evidence` connects instances to source occurrences; and
* `kb.metrics` preserves extraction and document provenance.

The generic class reference on `kb.semantic_assertions` is:

```text
instance_of_term_id
instance_of_term_version
```

The name `parent_term_id` is rejected because instantiation is not taxonomy or containment.
`metric_definition_term_id` is rejected on the generic assertion table because the table also holds
provisions, entities, inventory items, and other assertion families. `artifact_definition_term_id`
is rejected because not every assertion is an artifact instance.

The class reference is nullable for assertion kinds that encode relations or other claims without
an applicable object class. An accepted normalized metric instance requires exactly one resolved
metric class.

### 3.2 DR2 — Treat `kb.ontology_terms` as the class identity header and add a real class contract

`kb.ontology_terms` remains the stable identity, term kind, module, version, label, lifecycle, and
governance header. A new versioned class-contract store supplies the missing semantics:

```text
kb.ontology_class_contracts
  term_id
  term_version
  contract_schema_version
  definition_state
  class_kind
  contract_payload
  synthesis_method
  confidence
  policy_version
  provenance
  lifecycle/status
```

There is exactly one authoritative class-contract record for each `(term_id, term_version)`.
`contract_schema_version` versions the serialization format only; it is not a second semantic
version. Any decision-relevant change to class meaning, attributes, logical datatypes, constraints,
or comparison rules creates a new `kb.ontology_terms` version and its corresponding contract. Thus
`instance_of_term_id/version` identifies the exact semantic contract used for normalization.

The detailed schema will be specified by OpenSpec, but `contract_payload` must be able to define:

* the class's meaning and applicability;
* attribute identifiers, labels, and definitions;
* logical datatypes, which define semantic value spaces rather than Go, SQL, or JSON storage types;
* attribute cardinality and required, optional, or conditional presence;
* permitted units, dimensions, value forms, and special values;
* normalization and canonical serialization rules;
* constraints, tolerances, defaults, and cross-attribute rules;
* known errors, exceptions, and missing-value interpretations;
* assertion modalities and valid-time/applicability behavior;
* rules for equivalence, stronger/weaker comparison, conflict, and incomparability; and
* broader, narrower, exact, close, or related class mappings.

For example, a logical datatype may state that normal values are integers while named exceptional
values are also permitted. It is not limited to a programming-language primitive.

An ontology class is therefore the aggregate of its term identity, observed class profile, class
contract, labels, axioms, mappings, and applicable profile rules. The observed profile preserves
the structural superset discovered in the corpus; the contract identifies which parts currently
have authoritative meaning. A `kb.ontology_terms` row without a class contract is not silently
presented as a complete class.

Class definition state is separate from term lifecycle:

```text
identity_only -> partially_defined -> class_ready
```

Auto-promotion may create `identity_only`. A class becomes `class_ready` only after its contract
passes versioned completeness and coherence validation. That promotion may be autonomous under
policy; human approval is optional.

### 3.3 DR3 — Use an evidence-first logical pipeline and a dependency-safe persistence order

The logical ontology-processing flow for a metric is:

```text
1. kb.metrics occurrence
      -> evidence proposal
2. evidence proposal
      -> candidate normalized assertion (ontology object instance)
3. candidate assertion
      -> resolve or create ontology object class
4. class-aware validation
      -> accepted/deferred instance + authoritative evidence link
5. accepted same-class instances
      -> semantic relations and Review Document projections
```

Evidence is logically prior to an assertion: the system must not invent an instance with no source
support. Physical database insertion follows referential integrity. Because
`kb.assertion_evidence.assertion_id` is non-null, the transactional writer first finds or creates
the assertion row and then inserts or restores its evidence row. This storage order does not change
the logical provenance order.

The complete physical order is:

1. persist or reuse the occurrence-derived `kb.semantic_decision_candidates` row containing the
   evidence proposal and class-independent instance payload;
2. resolve an existing class, or create its term identity and observed profile and synthesize a
   class-contract proposal;
3. activate a new ontology-term version and corresponding contract only if policy and class
   validation permit it;
4. once a usable class version exists, transactionally find or create the normalized
   `kb.semantic_assertions` row with `instance_of_term_id/version`; and
5. in the same transaction, insert or restore `kb.assertion_evidence` and record the candidate's
   resulting assertion.

An unresolved or insufficiently defined class leaves the evidence-bearing decision candidate
deferred. The authoritative store never inserts an accepted, classless metric assertion and later
patches in its class.

The current `kb.semantic_decision_candidates` record already carries the source artifact, source
spans, proposed payload, method, and confidence. It serves as the evidence-bearing proposal during
resolution; a separate pre-assertion evidence table is not required unless OpenSpec finds that the
candidate lifecycle cannot preserve all required evidence.

Class resolution is deliberately two-pass:

1. occurrence normalization builds the best class-independent candidate shape and preserves all raw
   evidence; and
2. after class resolution, the candidate is validated and normalized again against the selected
   class contract.

This avoids a circular dependency: a class can be discovered from instances, while an accepted
instance still receives class-aware validation. An unresolved class leaves the candidate queryable
and deferred; it does not block completion of the document pipeline.

### 3.4 DR4 — One atomic metric occurrence has at most one current candidate assertion

The metric extraction contract is one atomic metric claim per `kb.metrics` row. Under that contract:

* one metric occurrence creates at most one **current** assertion decision candidate;
* unchanged reprocessing reuses the current candidate and updates `last_seen`;
* changed reprocessing creates a new candidate revision and supersedes the previous revision;
* an accepted current candidate resolves to at most one current semantic assertion; and
* an active metric occurrence supports at most one current metric-instance assertion.

Historical candidate revisions and historical evidence may still exist for audit. “At most one”
therefore applies to the current lifecycle state, not to all rows ever written. When changed
reprocessing maps the same metric occurrence to a different current assertion, the transaction
soft-deletes the prior supporting evidence link with a supersession reason and creates the new one.
For `artifact_type = 'metric'`, one current occurrence therefore has at most one active
(`deleted = false`, `evidence_role = 'supports'`) occurrence-to-instance link. Contradictory evidence
uses its separate evidence role and does not become the metric's current normalized-instance link.

If one extracted row contains multiple independent metric claims, the extraction is malformed and
must be split into multiple `kb.metrics` occurrences before ontology association. The ontology
pipeline must not silently fan one metric row into unrelated current assertions.

The database relationship remains generic and many-to-many through `kb.assertion_evidence` because:

* many occurrences may support one normalized assertion;
* non-metric artifact families may legitimately produce several assertions from one artifact; and
* history, contradictory evidence, and future composite artifacts must remain representable.

Consequently, this ADR does not add `kb.metrics.assertion_id` or
`kb.metrics.metric_assertion_id` as an authoritative foreign key. A `primary_assertion_id` may be
exposed as a rebuildable current-state projection for query convenience, but the evidence table is
the source of truth.

### 3.5 DR5 — Build evolving classes from instance observations, but do not equate observation with validity

The system adopts the proposed corpus-driven class-construction method with an essential safety
boundary.

For every candidate instance, the processor collects its observed structure, including known fields
such as value, logical value type, range form, unit, condition, subject, and modality, plus
domain-specific attributes such as `normal speed`, `red-zone speed`, or `value when used outside`.
Observed attributes are normalized and reconciled using the same cheapest-first identity principles
as keyword reconciliation.

The ontology class aggregate preserves a **structural superset** of the attributes recognized
across its instances in its observed profile. As more documents are processed, new legitimate
attribute definitions may be promoted into later authoritative ontology-term versions and their
corresponding contracts. The authoritative contract is a validated synthesis of that superset, not
its raw union: every observation remains known, but every observed value, datatype, unit, or
attribute is not automatically permitted.

The implementation separates:

```text
observed class profile                    authoritative class contract
append-only/derived corpus evidence  ->   versioned governed semantics
```

The observed profile records:

* candidate attribute names and normalized identities;
* observed logical datatypes, units, value forms, and cardinalities;
* frequency and document/domain distribution;
* examples and source evidence;
* co-occurrence and conditional patterns;
* contradictions and outliers; and
* confidence and the method that grouped each observation.

The authoritative contract records what the system currently accepts as the class definition. A
malformed string in one document must not expand a numeric datatype into “numeric or arbitrary
string,” because doing so would hide a datatype conflict. It instead remains an observed outlier or
`datatype_mismatch` until deterministic rules, an LLM-assisted proposal, policy, or a human decision
changes the class contract.

Class synthesis must also decide whether a newly observed field is:

* an attribute of the existing class;
* an alias for an existing attribute;
* a condition or applicability qualifier;
* a related but separate metric class;
* a specialized subclass/profile; or
* erroneous or presently unresolved.

For example, `normal speed` and `red-zone speed` might be conditional attributes of a speed class,
or they might be separate metrics related to a common equipment class. The system must preserve the
ambiguity until contextual and corpus evidence support one model.

Class evolution produces a new immutable ontology-term version with one corresponding contract.
Existing assertions retain the exact `instance_of_term_id/version` under which they were normalized.
Compatible versions may be projected as current; decision-relevant changes trigger revalidation or
a new assertion revision.

### 3.6 DR6 — Make same-class recognition the primary cross-document resolution problem

The most difficult and important operation is deciding whether different artifacts instantiate the
same ontology class. Class creation must not become “one new label, one new class,” and class growth
must not merge merely similar concepts.

The resolver reuses the existing keyword Tier-0 through Tier-6 machinery for names:

* Tier 0: exact surface identity;
* Tier 1: current normalized-key identity;
* Tier 2: alternate keys such as alphanumeric, sorted, and singular forms;
* Tier 3: governed rewrite rules and retry of earlier deterministic tiers;
* Tier 4: initials/acronym bridges;
* Tier 5: guarded fuzzy matching; and
* Tier 6: offline multilingual embedding and governed terminology identity evidence.

The exact deployed tier definitions and thresholds remain owned by the keyword subsystem; this ADR
does not create a competing normalization stack.

Name identity is necessary but not sufficient for class identity. Class resolution additionally
uses:

* stable source identifiers and existing redirects;
* approved keyword-concept and term mappings;
* quantity kind, observable property, unit dimension, and subject compatibility;
* attribute-shape and logical-datatype compatibility;
* conditions, modality, applicability, and domain scope;
* ontology neighborhood and external governed terminology evidence;
* corpus co-occurrence and distribution;
* lexical/vector candidate generation; and
* LLM adjudication when deterministic and statistical evidence remain ambiguous.

Resolution follows the proven Phase-2 hybrid pattern: deterministic blocking and matching first,
then LLM calls only for the bounded ambiguous set. The existing Phase-2 metric reprocessing matcher
is reused as an implementation pattern and evidence source, not as proof of class identity: it was
designed to recognize the same occurrence within one document, whereas class identity operates
across documents and contexts.

Candidate decisions are `same`, `different`, `uncertain`, or `conflicted`, with method, confidence,
evidence, policy version, and reversibility. Low-cost negative gates—different quantity dimension,
incompatible subject kind, explicit `never_merge`, or incompatible applicability—must reject unsafe
candidates before embeddings or LLM calls.

### 3.7 DR7 — Reuse `kb.semantic_assertions` as normalized object instances

A separate `kb.ontology_term_instances` table is not introduced. It would duplicate the assertion's
subject, value, conditions, lifecycle, revisions, evidence, and provenance.

Every normalized metric instance carries:

```text
instance_of_term_id
instance_of_term_version
class_resolution_state_term_id
value_state_term_id
```

The class-resolution decision separately preserves observed class candidates, canonical class,
method, confidence, rationale, producer/model/prompt where applicable, and decision policy. The
normalization-time class version is immutable.

Initial class-resolution states are `resolved`, `unresolved`, `ambiguous`, and `conflict`. A new
accepted metric instance requires `resolved` and a `class_ready` contract, unless a named policy
explicitly permits a partially defined class for a low-risk use. Other cases remain queryable as
candidate or deferred and remain available to Review Document's fallback paths.

### 3.8 DR8 — Make normalized claim identity semantic rather than occurrence-derived

Candidate identity remains occurrence-derived because it identifies one source proposal. Accepted
instance identity is computed from canonical semantic content.

For metrics, the versioned canonical identity includes, where applicable:

* canonical subject/referent;
* canonical `instance_of` class after redirect resolution;
* predicate and assertion kind/modality;
* normalized value, interval, or explicit value state;
* canonical unit and quantity kind;
* comparator and boundary inclusivity;
* conditions, procedure, polarity, and applicability;
* valid time; and
* class-contract fields marked identity-bearing.

It excludes source record, metric ID, wording, spans, extraction run, model, prompt, confidence, and
display labels.

`kb.semantic_claim_identities` provides concurrency-safe find-or-create for the canonical payload
and points to the current assertion revision. Equal digests are reused only after canonical payload
bytes compare equal. Changed processor versions alone do not create new semantic identity; changed
semantic output may do so.

When two occurrences produce the same canonical claim, they converge on one normalized assertion
and retain independent evidence rows. New evidence alone does not create an assertion revision.
Absorbed historical assertion identities remain resolvable through audited, acyclic assertion
redirects.

### 3.9 DR9 — Represent missing and malformed values as meaningful instance states

A missing or malformed value must not make an artifact disappear. Initial governed value states
include:

| State | Meaning |
|---|---|
| `present` | A usable normalized value or interval exists. |
| `missing` | The metric is present but an expected value is absent. |
| `unparsed` | Source value exists but normalization cannot parse it. |
| `datatype_mismatch` | Observed datatype conflicts with the selected class contract. |
| `not_applicable` | The source explicitly says the metric does not apply. |
| `unknown` | Available evidence does not yet support another state. |

Unparsed and mismatched instances preserve the offending raw value and observed datatype. Missing
and unknown instances retain subject, class candidates, applicability, and source evidence. These
states are ontology terms rather than a closed database enum.

“Metric absent” is different from “metric present with missing value.” Absence can be concluded only
relative to a named, versioned profile or class contract that declares the metric expected in the
review scope.

### 3.10 DR10 — Persist governed relations among same-class instances

Instances of one canonical class may be:

* identical and converged;
* equivalent after normalization or unit conversion;
* stronger or weaker;
* conflicting;
* syntactically conflicting;
* missing, unparsed, or unknown;
* incomparable because conditions, scopes, subjects, dimensions, or modalities differ; or
* related by future relation kinds not known today.

`kb.assertion_relations.relation_term_id` becomes the authoritative governed relation type. Initial
terms include:

```text
core:equivalent_to
core:stronger_than
core:weaker_than
core:conflicts_with
core:syntactically_conflicts_with
core:incomparable_with
core:supersedes
core:superseded_by
```

Every relation records endpoints, direction, relation term, applicability context, derivation
method/rule version, confidence, structured comparison evidence, rationale, producer provenance,
lifecycle, and supersession or reversal history.

Comparison is class-contract-driven:

1. validate same canonical class or an explicitly comparable mapped class;
2. validate compatible subject, dimension, assertion modality, conditions, applicability, and time;
3. normalize units and values under the relevant class contract;
4. apply the registered comparison rule; and
5. persist one active verdict per relation family, endpoint pair, context, and rule set.

For requirement constraints, satisfying-set containment defines stronger and weaker. For example,
`>= 300 cd/m2` is stronger than `>= 250 cd/m2`. Numeric ordering alone does not define
stronger/weaker for observations. A datatype mismatch is first an instance value state; it becomes a
pairwise syntactic conflict only when a governed comparison rule establishes the relevant context.

The relation does not declare either source correct or incorrect. Review Document may flag the
difference and separately present source authority and applicability.

### 3.11 DR11 — Reconcile duplicate classes through mappings and redirects

All names and concepts determined to mean the same logical class resolve to one canonical
`kb.ontology_terms.term_id`. Auto-promoted terms are candidates for reconciliation, not evidence
that two meanings differ.

`kb.ontology_mappings` records exact, close, broad, narrow, and related semantic decisions. Exact
identity additionally creates an operational `kb.ontology_term_redirects` record from absorbed term
to canonical survivor. Terms are not hard-deleted.

Term reconciliation and keyword-concept reconciliation are coordinated. Distinct curated or
explicitly `never_merge` terms may block a merge. Distinct auto-promoted terms trigger class
identity adjudication rather than circularly preventing concept repair.

Because class identity participates in claim identity, a term merge re-resolves affected evidence,
recomputes normalized claim identities, converges equal assertions, writes redirects, recomputes
relations, and rebuilds projections. Reversal replays each evidence row through the superseding
class decision rather than guessing how previously merged assertions should split.

### 3.12 DR12 — Use deterministic processing first and LLMs for bounded ambiguity

Class resolution, class synthesis, instance convergence, and relation derivation use this ordered
strategy:

1. **Deterministic:** stable IDs, redirects, exact keyword tiers, governed mappings, canonical
   serialization, units/dimensions, logical datatype checks, and comparison rules.
2. **Rule/statistical:** guarded fuzzy matching, structural signatures, corpus statistics,
   embeddings, and ontology-neighborhood evidence.
3. **LLM adjudication:** determine likely same-class identity, attribute meaning, class shape,
   applicability distinctions, or relation semantics for the bounded ambiguous set.
4. **Policy activation:** accept, reject, retain uncertainty, or defer according to risk, evidence,
   confidence, and versioned thresholds.

An LLM produces a structured proposal and evidence. A governed policy-owned writer activates it;
LLM code does not directly mutate active class contracts or canonical identities. This preserves an
auditable ownership boundary without turning human approval into a mandatory gate.

LLM cost is controlled through deterministic negative gates, candidate blocking, batching, caching,
reuse of prior decisions, and re-adjudication only when decision-relevant evidence changes.

### 3.13 DR13 — Make Review Document class-first with labeled fallback

For every metric occurrence in a document under review, Review Document performs:

```text
kb.metrics
  -> current kb.assertion_evidence
  -> current kb.semantic_assertions instance
  -> instance_of canonical kb.ontology_terms class
  -> all current instances of that class
  -> their kb.assertion_evidence and source artifacts
  -> governed comparisons and one Comparison Matrix row
```

“Current `kb.assertion_evidence`” means the active supporting link for the current metric occurrence:
`artifact_type = 'metric'`, matching `input_record_id` and `artifact_id`,
`evidence_role = 'supports'`, and `deleted = false`. Its assertion is resolved through any active
assertion redirect to the claim registry's current assertion. The current accepted candidate for
the occurrence must point to that same assertion. Reprocessing changes this link through DR4's
transactional soft-supersession rule; historical evidence is excluded from the current traversal
but remains auditable.

Candidate retrieval order is:

1. same canonical class after redirect resolution;
2. governed exact/close/broad/narrow mappings allowed by the review rule;
3. structurally compatible subjects, quantity kinds, class contracts, and ontology neighborhoods;
4. lexical/vector similarity; and
5. LLM adjudication for high-value residual ambiguity.

Class membership is authoritative. Later channels discover candidates and are labeled as fallback;
they do not silently turn similarity into identity. Every candidate pair must pass subject,
dimension, modality, condition, applicability, and time gates before semantic comparison.

Review Document distinguishes equivalent, stronger, weaker, conflicting, syntactically conflicting,
missing, unparsed, incomparable, unresolved-class, and similarity-only results. If ontology
processing is incomplete, the application continues through its existing fallback paths and shows
the resolution state. Semantic enrichment is not an availability dependency.

### 3.14 DR14 — Make every decision idempotent, observable, and reversible

Every class, instance-identity, and relation decision records:

* inputs and candidates considered;
* observed and canonical identities;
* deterministic, statistical, and LLM methods used;
* policy, thresholds, rule, model, and prompt versions;
* evidence, confidence, and rationale;
* what was merged, redirected, rejected, or left uncertain;
* how the decision can be superseded or reversed; and
* which projections require rebuilding.

Re-running unchanged versioned inputs does not create duplicate candidates, classes, instances,
evidence links, or relations. Changed evidence creates a new decision or revision only when it is
decision-relevant.

## 4. Disposition of Review Issues and Additional Thoughts

### 4.1 Issues 01–06

| Review item | Disposition |
|---|---|
| Issue 01 | Confirmed. DR1 and the diagrams explicitly distinguish ontology object classes, normalized instances, evidence, and source occurrences. The actual table name is `kb.semantic_assertions`. |
| Issue 02 | Confirmed that metrics resolve through instances rather than directly treating terms as instances. A singular `kb.metrics.assertion_id` is not authoritative; DR4 retains the normalized evidence link. |
| Issue 03 | Confirmed. DR13 makes the Review Document traversal a minimum competency and acceptance test, using `kb.assertion_evidence` rather than a singular metric foreign key. |
| Issue 04 | Confirmed. DR1–DR2 define the two ontology layers and a real semantic/syntactic class contract. |
| Issue 05 | Confirmed concern. The generic field is `instance_of_term_id/version`, not a metric-specific name or the ambiguous `parent_term_id`. |
| Issue 06 | Confirmed that the current direct term column is not the future authoritative instance path. Rejected renaming it to singular `metric_assertion_id`; the evidence association remains authoritative. |

### 4.2 Thoughts 01–04

| Thought | Disposition |
|---|---|
| Thought 01 | Confirmed with a lifecycle qualification: one atomic metric occurrence has at most one current candidate assertion and one current resulting assertion. Reprocessing may create superseded historical candidate/evidence revisions. |
| Thought 02 | Confirmed logically. Metrics produce evidence-bearing proposals, which produce normalized instances, which resolve to classes. Physical inserts remain dependency-safe because authoritative evidence has a non-null assertion foreign key. |
| Thought 03 | Adopted with the observed-profile/authoritative-contract boundary in DR5. Classes evolve as structural supersets of recognized attributes, but anomalous observations do not automatically become permitted semantics. |
| Thought 04 | Confirmed as the central difficulty. DR6 separates occurrence, instance, and class identity; reuses the keyword tiers and Phase-2 deterministic-first hybrid pattern; and reserves LLM adjudication for bounded ambiguity. |

## 5. Alternatives Considered

### 5.1 Continue treating a term row as a complete class

Rejected. The live row commonly contains only identity and a label. Optional free-text
`definition`, `value_type`, and `range_type` columns cannot express the required attribute,
constraint, logical datatype, applicability, exception, and comparison semantics.

### 5.2 Make the authoritative class contract the raw union of observed instances

Rejected. A raw union maximizes recall but turns malformed values and extraction errors into valid
class semantics. It would make datatype and constraint conflicts progressively disappear. The
observed profile remains inclusive; the authoritative contract remains governed and versioned.

### 5.3 Create `kb.ontology_term_instances`

Rejected. It would duplicate most of `kb.semantic_assertions` and create two sources of truth for
instance values, conditions, lifecycle, revisions, evidence, and provenance.

### 5.4 Add `kb.metrics.metric_assertion_id`

Rejected as the authoritative relationship. It would encode a metric-specific one-to-one
assumption in a system whose generic provenance relationship is many-to-many. A current projection
can provide equivalent query convenience without replacing `kb.assertion_evidence`.

### 5.5 Define every class manually

Rejected as a universal requirement. It produces the best result for critical classes but cannot
keep pace with corpus scale. The selected design permits curated, autonomous, and hybrid classes
under the same versioned contract.

### 5.6 Automatically promote every observed attribute and value

Rejected. It is inexpensive but makes one erroneous source redefine the class. New observations
produce evidence and proposals, not unconditional semantic expansion.

### 5.7 Use only deterministic identity rules

Rejected. Deterministic methods are the default and must run first, but cross-language,
context-sensitive, and domain-specific equivalence cannot always be resolved deterministically.

### 5.8 Use embeddings or an LLM as the identity authority

Rejected. Both are valuable candidate-generation or adjudication mechanisms. Neither alone is an
auditable, stable canonical identity decision.

## 6. Implementation Sequence

Implementation is tracked through a separate OpenSpec change. The order is:

### Phase 0 — Protect the current system and characterize the corpus

1. Mark existing label-only and incomplete metric terms with a derived definition state.
2. Produce completeness reports for all current `metric_definition` terms.
3. Inventory metric attributes and identify core fields, candidate domain fields, conflicts, and
   likely related submetrics.
4. Establish baseline tests for Phase-2 occurrence matching and Review Document retrieval.

### Phase 1 — Class-contract and instance-of foundation

1. Create the versioned ontology class-contract and observed-profile stores.
2. Add generic `instance_of_term_id/version`, class-resolution state, and value state to semantic
   assertions.
3. Seed governed state and relation terms.
4. Add completeness/coherence validation and identity-only/partial/class-ready projections.
5. Preserve current metric term columns as compatibility/observed-resolution data during rollout.

### Phase 2 — Evidence-first metric candidate pipeline

1. Enforce one atomic metric occurrence to one current candidate invariant.
2. Make the candidate payload an explicit evidence-bearing proposal.
3. Resolve class after initial occurrence normalization.
4. Revalidate and normalize against the class contract before acceptance.
5. Preserve unresolved candidates without blocking the document pipeline.

### Phase 3 — Class observation, synthesis, and same-class recognition

1. Aggregate observed attribute profiles from metric candidates and accepted instances.
2. Normalize attribute names through the existing keyword resolution system.
3. Apply deterministic class identity and negative gates.
4. Use statistical/LLM adjudication only for bounded ambiguous candidates.
5. Create or evolve ontology-term versions and their corresponding class contracts through
   policy-controlled activation.
6. Reconcile duplicate auto-promoted terms and repair keyword/term alignments.

### Phase 4 — Canonical instance identity and relations

1. Compute shadow semantic claim identities.
2. Report convergence groups, collisions, mismatches, and unresolved cases.
3. Converge identical instances without losing independent evidence.
4. Persist redirects and switch writes to concurrency-safe canonical find-or-create.
5. Derive governed same-class relations incrementally.

### Phase 5 — Review Document integration

1. Implement the DR13 class-to-instance traversal.
2. Add class, instance, value-state, relation, and evidence fields to review payloads.
3. Make canonical class membership the first retrieval channel.
4. Retain and label structural, lexical, vector, and LLM fallbacks.
5. Expose class completeness and resolution uncertainty in diagnostics.

## 7. Migration and Backfill Safety

Migration is additive until shadow validation passes.

* Existing `kb.metrics` occurrences and source provenance are not deleted or coalesced.
* Existing term IDs remain addressable through redirects.
* Existing assertion IDs remain addressable through assertion redirects.
* Historical candidate revisions and their resulting assertions remain auditable.
* Observed class profiles never overwrite authoritative class contracts.
* Class-contract changes create new ontology-term versions rather than silent in-place semantic
  mutation.
* Backfill runs in bounded, restartable batches and emits dry-run decision reports.
* Term merge/split replays evidence and recomputes claim identity and relations.
* Redirects are single-active-target, acyclic, lock-protected, and reversible by superseding
  decisions.
* Review Document retains fallback retrieval throughout rollout.

Required pre-cutover reports include:

* identity-only, partially defined, and class-ready term counts;
* observed attributes proposed for each class and their evidence distribution;
* class versions proposed to change and why;
* terms and concepts proposed to merge, split, or keep distinct;
* assertions proposed to converge and their evidence membership;
* instances receiving relations rather than convergence;
* unresolved classes, values, attributes, and comparison cases;
* LLM call volume, cache reuse, cost, and decision yield; and
* changes to Review Document candidate and comparison sets.

## 8. Acceptance Criteria

### 8.1 Class foundation

* A `class_ready` metric term has a validated, versioned class contract; a label-only term cannot be
  reported as class-ready.
* The contract can express logical datatypes, attribute meaning/cardinality, conditions, units,
  constraints, errors, exceptions, missing states, and comparison rules.
* New corpus attributes appear first in the observed profile and do not silently become valid
  contract fields or values.
* A legitimate new attribute can create a new ontology-term version and corresponding class contract
  with evidence and provenance.
* Existing instances remain tied to their normalization-time class version and can be revalidated.

### 8.2 Occurrence and candidate lifecycle

* One atomic metric occurrence has at most one current assertion candidate.
* Unchanged reprocessing reuses the candidate; changed reprocessing supersedes it with a new
  revision.
* A compound metric extraction is split rather than producing multiple unrelated current assertions
  from one metric row.
* Historical revisions remain auditable and are not used as current state.

### 8.3 Class and instance identity

* Approved aliases and translations of one logical metric resolve to one canonical term after
  redirect resolution.
* Same-label metrics with different quantity kinds, subject meanings, or applicability remain
  distinct.
* Two semantically identical occurrences converge on one normalized assertion with independent
  evidence.
* Two different values of the same class remain different instances and receive an appropriate
  relation where comparable.
* Duplicate auto-promoted terms can be reconciled without concept alignments creating a circular
  merge block.

### 8.4 Missing, malformed, and contradictory observations

* A metric with no value produces a queryable `missing` instance or candidate rather than
  disappearing.
* An observed string where the class expects a numeric logical value produces
  `datatype_mismatch`; it does not automatically broaden the class datatype.
* Outlier attributes and values remain linked to evidence and can later be promoted, corrected, or
  rejected.
* Conflicts are flagged without declaring either source correct or incorrect.

### 8.5 Relations

* `display luminance >= 300 cd/m2` is `stronger_than`
  `display luminance >= 250 cd/m2` when subject and applicability are compatible.
* Unit-equivalent values converge or receive an explainable `equivalent_to` relation when
  convergence is intentionally deferred.
* Observations do not inherit stronger/weaker semantics merely from numeric order.
* Incompatible conditions or dimensions produce `incomparable_with`, not a guessed ordering.
* Future relation terms can be added without changing a closed database enum.

### 8.6 Autonomous operation

* No ordinary processing stage requires human approval.
* Deterministic identity and negative gates run before statistical or LLM methods.
* LLM calls operate only on bounded ambiguous candidates and are cached by versioned inputs.
* Autonomous class or identity activation occurs only through a recorded policy decision.
* Human corrections can override and lock decisions; all autonomous merges and contract changes are
  reversible or supersedable.

### 8.7 Review Document

* Starting from a `kb.metrics` occurrence, Review Document can retrieve its current normalized
  instance through evidence, its canonical class through `instance_of`, and all comparable
  instances and their source metrics.
* Same-class retrieval precedes similarity-only candidate discovery.
* Results explain class identity, comparison relation, value state, confidence, and evidence.
* The application distinguishes missing value from metric absence.
* Unresolved ontology processing does not block review; fallbacks are visibly labeled.

### 8.8 Competency and regression tests

The OpenSpec change must include:

* CQ-M02 positive and negative fixtures from ADR `2026072901`;
* label-only term rejected as class-ready;
* observed-profile expansion without automatic contract expansion;
* ontology-term/class-contract version evolution and revalidation;
* Phase-2 same-document reprocessing with unchanged and changed metric payloads;
* multilingual and alias class convergence;
* same-label/different-quantity negative identity;
* exact assertion convergence with multiple evidence rows;
* unit-normalized equivalence;
* lower/upper-bound and interval relation cases;
* missing, unparsed, datatype mismatch, conflict, and incomparability;
* deterministic, statistical, and LLM-assisted class decisions;
* merge, split, redirect reversal, cycle rejection, and `never_merge`; and
* the complete Review Document traversal in DR13.

## 9. Consequences

### 9.1 Positive

* The ontology gains a real class layer instead of treating labels as definitions.
* Classes can grow from corpus evidence without requiring a human for every discovery.
* Bad observations remain visible without poisoning the class contract.
* Same occurrence, same instance, and same class become separate auditable decisions.
* Equivalent claims converge without losing provenance.
* Meaningful differences become relations rather than isolated rows.
* Review Document gains deterministic class-first comparison and retains similarity recall.

### 9.2 Costs and risks

* Versioned class contracts and observed profiles add schema and lifecycle complexity.
* Class synthesis can misclassify an attribute, condition, submetric, or error.
* A false class merge affects more downstream objects than a false similarity match.
* LLM adjudication adds cost, latency, and nondeterminism.
* Class evolution can trigger expensive instance revalidation and relation recomputation.
* Pairwise comparison can become quadratic without class-specific blocking and incremental updates.

These risks are managed by separating observation from authority, deterministic-first resolution,
negative gates, bounded LLM use, versioned policy, shadow computation, complete provenance, and
reversible decisions.

## 10. Relationship to Earlier Decisions

### ADR `2026072901`

This ADR implements and sharpens the class/instance intent and CQ-M02 behavior. It retains the
governed write boundary while clarifying that policy-controlled autonomous activation does not
require a human reviewer.

Any earlier wording that treats a term identity row as a complete class or implies mandatory human
activation is superseded for this workflow.

### ADR `2026081201`

Automatic term creation remains permitted, but it creates an `identity_only` class candidate unless
a validated contract is also synthesized. Duplicate auto-promoted terms must be reconciled rather
than used as circular evidence that keyword concepts differ.

### ADR `2026081401`

Governed `value_range_type` mapping remains part of deterministic occurrence normalization. This ADR
adds the higher-level logical datatype, class contract, observed profile, class identity, value
state, and comparison semantics.

### User manual §6.11

This ADR adopts §6.11's defect finding and replaces occurrence-derived isolation with an explicit
occurrence–evidence–instance–class model and governed relations among instances.

## 11. Open Questions for OpenSpec

These are implementation details rather than unresolved architectural direction:

1. The physical normalization of class-contract attributes versus a versioned JSON contract.
2. The precise completeness rules for each class kind and risk tier.
3. The initial thresholds for autonomous class identity, class evolution, and LLM-assisted
   activation.
4. The canonical serialization of conditions, procedures, applicability, and domain-specific
   attributes.
5. Whether the current decision-candidate table carries sufficient pre-assertion evidence or needs
   a dedicated evidence-proposal table.
6. How Review Document presents incomplete class contracts and uncertain comparisons without
   overwhelming users.

These questions must be resolved and tested before production cutover.
