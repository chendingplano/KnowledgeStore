# Research: Building an Object-Centric Ontology for the SemOS Knowledge Base

**Date:** 2026-07-23

**Status:** Research / architecture recommendation

**Scope:** `kb.object_nodes`, extracted artifacts, document processors, and document reviewers
**Primary audience:** SemOS, ChenWeb, document-processing, and document-review developers

## Executive summary

SemOS already has the beginning of an ontology architecture, but not yet an ontology.

The implemented path:

```text
document
  → extracted artifact
    → kb.artifact_objects
      → kb.object_nodes
```

solves an essential problem: many textual mentions can resolve to one canonical object.
It provides a stable referent through which metrics, provisions, inventory items, and
selected entities can meet.

What it does not yet define is:

- what kind of thing a canonical object denotes;
- whether it is an individual, a type, a collection, a process, or a concept;
- which properties may apply to which kinds of objects;
- what an artifact asserts about an object;
- whether a metric is a definition, observation, target, limit, capability, or reported
  value;
- how conditions, time, authority, units, and provenance qualify an assertion;
- when two assertions are comparable, compatible, conflicting, or merely related;
- what a document of a given type is expected to contain;
- how ontology terms, mappings, validation rules, and releases are governed.

Those gaps matter directly to document review. Sharing an `object_id` is a strong
retrieval signal, but it is not sufficient evidence that two metrics measure the same
property under comparable conditions. Conversely, absence of a metric from one object
roster does not prove a completeness defect unless a scoped rule says that the metric is
required for that object type, document profile, jurisdiction, and effective period.

The recommended architecture is therefore:

> Build a modular, Postgres-native operational ontology around `kb.object_nodes`, while
> keeping object identity, ontology terms, qualified assertions, provenance, and
> validation profiles as separate layers. Align those layers with RDF/OWL, SKOS, SHACL,
> PROV-O, SOSA/SSN, QUDT, OWL-Time, and PROF, and support standards-based export without
> requiring a triple-store migration.

The central conceptual chain becomes:

```text
source evidence
  → artifact mention
    → canonical object/referent
      → ontology classification
        → qualified assertion
          → validation or review decision
```

`kb.object_nodes` remains central, but canonical objects are the subjects and objects of
knowledge; they are not the ontology vocabulary, the assertions, or the validation
rules.

## 1. Research question

How should SemOS build an ontology on top of canonical `kb.object_nodes` so that:

1. artifacts from different processors interoperate;
2. reviewers retrieve semantically relevant artifacts without treating all object-shared
   artifacts as equivalent;
3. metrics can be compared with correct quantity, unit, modality, condition, and
   temporal semantics;
4. missing requirements can be detected against explicit, versioned expectations;
5. every inferred or extracted fact remains traceable to documents and line evidence;
6. the model evolves without invalidating stable object identities or silently changing
   term meanings?

## 2. Existing foundation

### 2.1 What is already correct

The existing object-centric ADR makes several strong decisions:

- `kb.artifact_objects` preserves extracted object mentions, roles, evidence, line
  spans, confidence, and reconciliation status.
- `kb.object_nodes` holds canonical object identity across artifacts, processors, and
  documents.
- mention rows are preserved when canonical nodes are merged.
- names, aliases, acronyms, translations, type compatibility, context, and optional
  embeddings participate in reconciliation.
- metrics, provisions, inventory items, and eligible entities use a shared contract.
- object-linked artifacts are traversable through `kb.artifact_connections`.
- semantic similarity remains a read-time retrieval operation rather than a stale claim
  persisted as semantic truth.

These decisions correctly distinguish a textual mention from its referent and preserve
the evidence needed to revisit reconciliation.

### 2.2 What the current graph represents

The current graph contains several different edge families:

- deterministic structural or line-overlap connections;
- artifact-category membership;
- object membership;
- extracted entity relations;
- manually supplied links;
- similarity discovered live through lexical/vector retrieval.

These edges are useful for navigation and candidate discovery. They do not all have the
same epistemic status:

```text
same source lines          deterministic document-layout fact
belong_to object           reconciled identity/subject link
belong_to category         classification or indexing link
entity relation            extracted domain claim
similar                    retrieval score, not a domain fact
manual                     human assertion, meaning depends on relation
```

An ontology must preserve these differences rather than treating every graph edge as an
equally true semantic relation.

### 2.3 The missing semantic layer

Consider three extracted metrics attached to the same pump:

```text
A. Discharge pressure shall not exceed 100 psi during normal operation.
B. Discharge pressure measured 690 kPa at 2026-07-01 10:00.
C. Hydrostatic test pressure shall be 150 psi for 30 minutes.
```

An object-only graph correctly connects all three to the pump. It cannot by itself say:

- A is an upper-bound requirement.
- B is an observation.
- C concerns a different operating condition and procedure.
- A and B refer to the same observable property and have convertible units.
- B can be evaluated against A.
- C is related but is not a conflict with A.

Those are ontology and assertion semantics.

## 3. What “ontology” should mean in SemOS

The term should be used precisely.

### 3.1 Ontology, taxonomy, vocabulary, and knowledge graph

| Construct | Purpose | SemOS example |
| --- | --- | --- |
| Vocabulary | Stable terms and definitions | `upper_bound_requirement`, `measured_object` |
| Taxonomy | Broader/narrower organization | centrifugal pump is a kind of pump |
| Ontology | Classes, properties, constraints, and intended meanings | a pressure observation observes a pressure property of a feature of interest |
| Knowledge graph | Instance data and assertions using those meanings | Pump P-101 has a discharge-pressure observation of 690 kPa |
| Application profile | Context-specific required/allowed use of the model | an inspection certificate for a pressure vessel must report test pressure and date |

SKOS is designed for concept schemes, labels, hierarchical relations, and mappings.
OWL provides classes, properties, individuals, axioms, and inference. SHACL validates a
data graph against explicit shapes. PROF describes profiles that constrain, combine, or
guide the use of other specifications. These are complementary tools, not competing
choices [R1][R2][R3][R9]. PROF is a W3C Working Group Note rather than a Recommendation;
it is useful here as a descriptive pattern for SemOS profiles, not as a mandatory
conformance standard.

### 3.2 Ontology is not the same as canonical identity

Canonical identity answers:

> Which mentions refer to the same thing?

Ontology answers:

> What kind of thing is it, which properties and relations have defined meanings, and
> which inferences or constraints follow?

Assertions answer:

> What did a source, processor, or reviewer claim about it, under which qualifications?

Conflating these questions creates hard-to-repair errors. For example, merging two
`object_nodes` because both are classified as pumps would confuse class membership with
identity. Similarly, storing “pressure = 100 psi” directly on an object would overwrite
parallel claims from different documents, times, and modalities.

### 3.3 Open-world knowledge versus closed-world review

OWL uses an open-world assumption: a fact absent from the graph may simply be unknown,
not false. It also does not assume that two different names necessarily identify
different individuals [R1].

Document review often needs a closed, scoped question:

> For this document type, object type, applicable standard version, jurisdiction, and
> effective date, are all required metrics present?

That question should not be answered by OWL absence alone. It needs an explicit
application/completeness profile and a validation or reviewer rule. SHACL is designed to
validate data graphs against shapes, and PROF provides a model for application profiles
[R3][R9].

Therefore:

- use ontology axioms for domain meaning and safe inference;
- use profiles/shapes for completeness and conformance;
- use reviewers for evidence-sensitive judgments and explanations.

## 4. Design principles

### P1. Canonical objects are referents, not bags of facts

`kb.object_nodes` should identify things. Claims about those things belong in assertion
records with their own provenance and lifecycle.

### P2. Preserve every source assertion

Two standards may state different limits for the same property of the same object class.
The ontology must preserve both assertions. A conflict is a relationship between
qualified assertions, not corruption of the object node.

### P3. Separate identity, classification, and similarity

These relations have different meanings:

```text
same identity      → merge/redirect candidate
instance of        → object classification
broader/narrower   → concept hierarchy
close match        → vocabulary alignment
similar            → retrieval candidate
```

Similarity must never silently become identity or semantic equivalence.

### P4. Model important relationships as qualified assertions

A bare triple often cannot carry the conditions needed by reviewers. An assertion should
be a first-class record when it needs source, confidence, time, modality, conditions,
authority, or review status. PROV-O uses an analogous qualification pattern when a simple
relation needs additional detail [R4].

### P5. Use two axes for canonical-object typing

The current `object_type` mixes domain category with ontological level. Retain it for
compatibility, but introduce a separate axis:

```text
domain kind:       equipment | material | system | process | organization | ...
ontological level: individual | type | collection | occurrence | concept
```

Examples:

| Canonical label | Domain kind | Ontological level |
| --- | --- | --- |
| Pump P-101 | equipment | individual |
| centrifugal pump | equipment | type |
| north-unit pump fleet | equipment | collection |
| hydrostatic test HT-44 | process | occurrence |
| hydrostatic testing | process | type |
| risk | concept | concept |

This prevents a specific pump from being merged with the class “pump” merely because
their names and `object_type` values are close.

### P6. Reuse external semantics, own only SemOS-specific terms

Use:

- SKOS for labels, concept schemes, and vocabulary mappings;
- SOSA/SSN for observations, features of interest, observed properties, procedures, and
  results;
- QUDT for quantity kinds, units, dimensions, and conversions;
- PROV-O for entities, activities, agents, derivation, and attribution;
- OWL-Time for instants, intervals, duration, and temporal relations;
- OWL/RDFS for classes, properties, and safe inference;
- SHACL for structural and completeness validation;
- PROF for application-profile metadata.

Create SemOS terms only when these standards do not express the needed artifact,
normative, reviewer, or evidence semantics. FAIR recommends extending an existing,
closely related vocabulary before creating a new one [R12]. OWL-Time is suitable for
temporal structure, while SemOS should define its own specializations for valid time,
effective time, observation time, and transaction time [R13].

### P7. Keep the operational model database-native

OWL's own primer notes that databases are a viable backbone for ontology-oriented
systems [R1]. SemOS already has transactional ingestion, audit, APIs, PostgreSQL search,
and review workloads. A forced triple-store migration would add operational cost before
the ontology has proved its competency.

Use stable IRIs and standards-aligned semantics in Postgres, then generate RDF/OWL/SKOS
and SHACL representations for interoperability and external reasoning.

### P8. Version meanings, not stable identities

Object IDs and ontology term IDs should be stable. Labels and descriptions can change.
If a term's intended referents change materially, create a new term rather than silently
redefining the old one. This follows the OBO Foundry's term-stability and versioning
principles [R10].

## 5. Recommended layered architecture

```text
┌──────────────────────────────────────────────────────────────┐
│ 7. Application and review layer                              │
│ reviewers, tools, findings, explanations, remediation        │
├──────────────────────────────────────────────────────────────┤
│ 6. Profiles and validation layer                             │
│ document profiles, applicability, SHACL-like shapes, rules   │
├──────────────────────────────────────────────────────────────┤
│ 5. Qualified assertion layer                                 │
│ claims, values, modality, conditions, time, confidence       │
├──────────────────────────────────────────────────────────────┤
│ 4. Domain ontology modules                                   │
│ metrics, provisions, inventory, entities, documents          │
├──────────────────────────────────────────────────────────────┤
│ 3. Vocabulary and ontology-term layer                        │
│ classes, properties, SKOS concepts, mappings, releases       │
├──────────────────────────────────────────────────────────────┤
│ 2. Canonical identity layer                                  │
│ kb.object_nodes, merges/redirects, classifications           │
├──────────────────────────────────────────────────────────────┤
│ 1. Evidence and artifact layer                               │
│ kb.inputs, metrics, provisions, inventory, entities,         │
│ kb.artifact_objects, line spans, extraction provenance       │
└──────────────────────────────────────────────────────────────┘
```

Each layer may depend on the layers below it. Lower layers must not depend on the
judgment of a particular reviewer.

### 5.1 Layer 1: evidence and artifacts

This layer remains source-oriented:

- a document is ingested;
- processors extract artifacts;
- `kb.artifact_objects` records that an artifact mentions an object;
- evidence quotes and line spans anchor the extraction;
- processor/model/prompt versions and confidence are retained.

An artifact is an information object. It is not automatically a true statement about the
world. A metric extracted from a superseded manual is still a valid extraction even when
its value is no longer authoritative.

### 5.2 Layer 2: canonical identity

`kb.object_nodes` remains the stable registry of referents.

Recommended additions:

| Field or relation | Purpose |
| --- | --- |
| `ontological_level` | distinguish individual, type, collection, occurrence, concept |
| `identity_scope` | optional namespace such as plant, organization, product catalog |
| `valid_time` | identity validity where names/organizational objects change over time |
| `external_identifiers` | serial, catalog, registry, URI, or other authority identifiers |
| `primary_class_term_id` | convenient primary ontology classification |

Do not force a single class. Objects often have multiple valid classifications:

```text
P-101
  instance_of centrifugal pump
  instance_of rotating equipment
  plays_role safety-critical component
```

Class membership and role membership should be separate assertions. A role may change
without changing object identity.

### 5.3 Layer 3: ontology terms and concept schemes

Introduce a governed registry of semantic terms. A term may represent:

- an OWL/RDFS class;
- an object property;
- a datatype property;
- a SKOS concept;
- an assertion kind;
- an artifact role;
- a quantity kind;
- a unit mapping;
- a document profile or validation rule identifier.

Suggested logical records:

```text
kb.ontology_terms
  term_id                  immutable internal ID
  iri                      globally stable IRI
  term_kind                class | object_property | data_property |
                           concept | quantity_kind | assertion_kind | role
  namespace
  preferred_label
  definition
  status                   draft | active | deprecated
  replacement_term_id
  created_in_release
  deprecated_in_release

kb.ontology_term_labels
  term_id
  label
  language
  label_type               preferred | alternative | hidden | acronym

kb.ontology_axioms
  subject_term_id
  predicate_term_id
  object_term_id
  axiom_kind
  release_id
  provenance

kb.ontology_mappings
  local_term_id
  external_iri
  mapping_relation         exact | close | broad | narrow | related
  status
  evidence
  approved_by
```

SKOS deliberately distinguishes `prefLabel`, `altLabel`, and `hiddenLabel`, supports
concept schemes, and provides exact, close, broad, narrow, and related mappings [R2].
That is safer than treating every external match as `owl:sameAs`. OWL same-individual
semantics allow all information about one name to be inferred for the other; this is much
stronger than lexical or conceptual similarity [R1].

#### Categories are not automatically ontology classes

`kb.artifact_categories` and semantic-projection category paths are valuable retrieval
facets. They should normally be represented as SKOS concepts or local indexing concepts
first. A `belong_to` category edge must not automatically imply `rdf:type`,
`rdfs:subClassOf`, or property equivalence.

A category may be promoted or mapped to an ontology class only after its definition,
scope, and expected inference are reviewed. For example, “pressure metrics” may be a
useful browsing category without denoting a class of real-world objects. Preserving this
boundary prevents the existing navigation taxonomy from becoming accidental domain
logic.

### 5.4 Layer 4: domain modules

The ontology should be modular rather than one undifferentiated schema.

#### Core module

Defines:

- canonical referent;
- object individual, type, collection, occurrence, and concept;
- information artifact;
- assertion;
- agent;
- document;
- source location;
- evidence;
- validity interval;
- semantic role.

#### Metrics and measurement module

Defines:

- metric artifact;
- metric/quantity kind;
- observable property;
- feature of interest;
- quantity value;
- unit;
- procedure;
- condition;
- observation;
- target;
- lower/upper bound;
- reference value;
- capability;
- formula/derived metric;
- measurement frequency;
- aggregation/window.

SOSA's pattern separates the feature of interest, observed property, observation,
procedure, and result. QUDT separates quantity kind, quantity value, unit, and dimension
[R5][R6]. This is the right starting point, but SemOS must add document-oriented
assertion kinds because not every extracted metric is an observation.

At minimum:

```text
metric_assertion_kind:
  definition
  observed_value
  reported_value
  required_exact_value
  lower_bound_requirement
  upper_bound_requirement
  target_value
  reference_value
  design_capability
  tolerance
  range
  formula
```

#### Provision module

Defines a normalized normative statement:

```text
actor
  → deontic modality
    → action
      → target object
        → conditions / exceptions / effective time / authority
```

Example modalities:

```text
required | permitted | recommended | prohibited | declared
```

A provision may constrain a property through a metric assertion. This relationship is
more meaningful than line overlap:

```text
provision --imposes--> upper-bound requirement
requirement --constrains--> discharge pressure
requirement --applies_to--> Pump P-101
```

#### Inventory module

Distinguishes:

- item type from item instance;
- item from quantity-on-hand assertion;
- part/component relations;
- membership in a collection;
- location;
- owner/custodian;
- serial, lot, model, and catalog identifiers;
- state and validity time.

#### Document and authority module

Defines:

- document type;
- version and revision;
- issuer/authority;
- effective and superseded dates;
- jurisdiction;
- normative versus informative status;
- adopts, amends, replaces, or cites another document;
- applicability scope.

This module is essential for conflict review. A newer internal procedure may
intentionally override an older one; two documents from different jurisdictions may both
be correct.

#### Entity bridge module

Entities remain broad extracted mentions. The bridge records whether an entity:

- denotes a canonical object;
- denotes an ontology class or concept;
- denotes an agent, document, place, or other referent;
- participates in an extracted relation.

Entity-to-object reconciliation is evidence. It should not make entity types the ontology
vocabulary.

### 5.5 Layer 5: qualified assertions

This is the most important missing data structure.

A semantic assertion should be first-class:

```text
Assertion
  assertion_id
  subject_ref
  predicate_term_id
  object_ref or typed literal
  assertion_kind
  polarity
  modality
  confidence
  status
  valid_time
  transaction_time
  qualifiers
  source provenance
```

Use typed subject/object references or a well-defined endpoint registry. Avoid opaque
free-text endpoint types.

Evidence should be one-to-many:

```text
AssertionEvidence
  assertion_id
  input_record_id
  artifact_type
  artifact_id
  artifact_object_id
  evidence_quote
  source_line_spans
  extraction_run
  model
  prompt_version
  confidence
  evidence_role            supports | contradicts | derived_from
```

The assertion is the normalized claim; evidence records show why the system believes the
claim exists. Several artifacts may support one assertion, and one artifact may support
several assertions.

#### Why not put all assertions in `kb.artifact_connections`?

`kb.artifact_connections` currently serves as a common traversal/index surface with
method-partitioned lifecycle. It includes line overlap, category links, structural links,
manual links, and extracted relations. Its uniqueness and replacement behavior are
optimized for derived graph edges.

A semantic assertion needs:

- multiple evidence sources;
- temporal and contextual qualifiers;
- polarity and modality;
- revision and adjudication state;
- independent lifecycle from a processor's rebuild;
- possibly a literal or structured value instead of another artifact endpoint.

Therefore:

> Treat `kb.artifact_connections` as a discovery/materialized-navigation graph. Store
> authoritative qualified domain claims in a dedicated assertion model, then project
> selected assertions into `kb.artifact_connections` for backward-compatible traversal.

### 5.6 Layer 6: profiles and validation

An ontology says what concepts mean. A profile says what is expected in a context.

Suggested profile key:

```text
(document_type,
 object_class,
 jurisdiction,
 authority,
 standard_version,
 effective_interval,
 review_purpose)
```

A profile may require:

- at least one metric of quantity kind pressure;
- a unit dimension compatible with pressure;
- an upper-bound requirement;
- a test date and procedure;
- a provision linking the requirement to an actor;
- evidence from a normative section;
- a value within a permitted range.

Suggested logical records:

```text
kb.ontology_profiles
  profile_id
  iri
  version
  title
  scope
  status
  effective_from
  effective_to
  is_profile_of

kb.ontology_profile_rules
  rule_id
  profile_id
  target_class_term_id
  rule_kind                 required_pattern | cardinality | datatype |
                            unit_dimension | conditional | prohibition
  rule_definition
  severity
  message_template
  source_authority
```

The initial implementation may execute these rules in SQL/Go while maintaining a SHACL
export. The important requirement is semantic equivalence between the operational rule
and its published shape.

### 5.7 Layer 7: reviewers and applications

Reviewers should receive ontology-aware candidates, not an unfiltered object roster.

For a metric under review:

```text
1. Resolve its canonical object(s).
2. Resolve the object's ontology class(es).
3. Resolve the metric's quantity/property term.
4. Normalize units and value structure.
5. Preserve assertion kind, modality, condition, and valid time.
6. Retrieve candidate assertions through:
   a. same object identity;
   b. applicable object-class hierarchy;
   c. same or mapped property/quantity kind;
   d. applicable profile requirements;
   e. live semantic retrieval as a fallback.
7. Filter or rank by comparability.
8. Ask the reviewer to classify the surviving assertion pairs.
9. Emit findings with assertion IDs and source evidence IDs.
```

Recommended comparability key:

```text
object scope
+ property/quantity kind
+ assertion kind/modality
+ procedure
+ operating condition
+ aggregation/window
+ valid time
+ unit dimension
+ authority/applicability
```

This key should not be a single string hash used as truth. It is a structured comparison
whose fields can be exact, compatible, conflicting, missing, or unknown.

## 6. Metric semantics in detail

Metrics are the highest-value pilot because the reviewer already depends on object
rosters and must distinguish same/conflict/related/unrelated.

### 6.1 Separate the metric concept from metric assertions

The phrase “maximum discharge pressure” may denote:

1. a metric definition: the property to be measured;
2. a design capability;
3. an upper-bound requirement;
4. an observed maximum over a time window;
5. a reported value copied from a source.

These must not be one ontology class or one database value.

Recommended model:

```text
MetricDefinition
  measures Property/QuantityKind
  appliesTo ObjectClass
  mayUse Procedure
  mayUse Unit

MetricAssertion
  about MetricDefinition
  featureOfInterest ObjectNode
  assertionKind
  value or interval
  unit
  conditions
  temporalScope
  provenance
```

### 6.2 Value model

Do not preserve only `metric_value` as text. Keep the original text, but add a normalized
representation:

```text
value_form:
  scalar
  interval
  lower_bound
  upper_bound
  tolerance
  ratio
  percentage
  categorical
  formula
  distribution
  time_series_reference

normalized_value:
  numeric_value
  lower_value
  upper_value
  lower_inclusive
  upper_inclusive
  unit_term_id
  quantity_kind_term_id
  comparator
```

Unit normalization must be dimension-aware. Equal numbers in `psi` and `kPa` are not
equal values, while different numbers may be equivalent after conversion. QUDT publishes
quantity-kind, unit, dimension-vector, and SHACL/OWL graphs suitable for this mapping
[R6].

### 6.3 Conditions are part of metric identity for review

Conditions may include:

- operating state;
- environment;
- population/cohort;
- specimen or sample;
- location;
- procedure;
- instrument;
- calibration state;
- aggregation function;
- time window;
- frequency;
- denominator;
- exclusions.

Two metrics with the same name, object, and unit can still be `related_distinct` when
conditions differ. The current reviewer prompt handles this as LLM judgment; the ontology
should make the relevant fields explicit so retrieval and ranking do not discard the
distinction.

### 6.4 Worked example

Source A:

```text
During normal operation, Pump P-101 discharge pressure shall not exceed 100 psi.
```

Normalized:

```json
{
  "feature_of_interest": "obj:pump-p-101",
  "property": "sem:discharge-pressure",
  "quantity_kind": "qudt:Pressure",
  "assertion_kind": "sem:upper-bound-requirement",
  "modality": "sem:required",
  "operator": "<=",
  "value": 100,
  "unit": "unit:PSI",
  "condition": "sem:normal-operation"
}
```

Source B:

```text
At 10:00 on 2026-07-01, Pump P-101 discharge pressure was 690 kPa.
```

Normalized:

```json
{
  "feature_of_interest": "obj:pump-p-101",
  "property": "sem:discharge-pressure",
  "quantity_kind": "qudt:Pressure",
  "assertion_kind": "sem:observed-value",
  "value": 690,
  "unit": "unit:KiloPA",
  "result_time": "2026-07-01T10:00:00",
  "condition": "sem:normal-operation"
}
```

The ontology enables the application to determine:

- same canonical feature of interest;
- same observable property;
- compatible quantity dimensions;
- convertible units;
- compatible operating condition;
- requirement versus observation.

The review application can then perform a compliance comparison rather than report a
false conflict between two textual values.

## 7. Ontology-driven document review

### 7.1 Candidate retrieval

Use a tiered retrieval policy:

| Tier | Signal | Purpose |
| --- | --- | --- |
| 1 | same canonical object + same property term | strongest comparison candidates |
| 2 | same canonical object + mapped/broader property | related-property candidates |
| 3 | applicable object class + profile-required property | completeness candidates |
| 4 | provision explicitly constrains property | normative candidates |
| 5 | category or live hybrid similarity | recall fallback |

Object anchoring should remain first, as already decided, but the property and assertion
semantics determine whether candidates are comparable.

### 7.2 Conflict detection

Conflict is not a stored attribute of an object or metric. It is a derived relationship
between two assertions after testing:

1. referent compatibility;
2. property equivalence or mapping;
3. modality/assertion-kind compatibility;
4. condition compatibility;
5. temporal overlap;
6. authority and applicability;
7. unit convertibility;
8. value incompatibility.

The result should retain:

```text
same_consistent
same_conflict
related_distinct
unrelated
undetermined
```

but reference assertion IDs, not only artifact IDs.

### 7.3 Completeness detection

Completeness requires a universe of expected claims. Derive that universe from a selected
profile, not from every metric connected to an object across the corpus.

```text
reviewed document
  → declared/inferred document profile
    → applicable object classes and standards
      → required assertion patterns
        → compare with document assertions
```

Every missing finding should say:

- which profile/rule created the expectation;
- why the rule applies;
- which object or object class is in scope;
- which assertion pattern is absent;
- which reference document/provision is authoritative;
- whether the absence is definite or evidence is incomplete.

### 7.4 Reviewer tools

The document-review tool catalog should eventually add:

| Tool | Purpose |
| --- | --- |
| `get_object_semantics` | canonical node, level, classes, roles, redirects |
| `get_assertion` | normalized claim with qualifiers and evidence |
| `find_assertions` | query by object, property, kind, time, profile |
| `compare_metric_assertions` | unit/condition/modality comparison facts |
| `get_applicable_profiles` | profiles and applicability rationale |
| `get_profile_requirements` | expected assertion patterns |
| `trace_assertion_evidence` | documents, artifacts, line spans, extraction run |

Go should continue to own deterministic resolution, conversion, filtering, budgets, and
persistence. The LLM should investigate ambiguity and explain findings.

## 8. Provenance, evidence, and authority

PROV-O distinguishes entities, activities, and agents, and supports qualified provenance
relations when additional attributes are needed [R4].

Map SemOS concepts as follows:

| SemOS | PROV-oriented interpretation |
| --- | --- |
| source document/version | `prov:Entity` |
| extracted artifact | entity derived from the document |
| processing run | `prov:Activity` |
| processor/model/prompt | agent/software agent and plan |
| assertion | entity generated by extraction/reconciliation activity |
| human correction | activity associated with a human agent |
| reviewer finding | entity generated by review activity |

Authority is not the same as provenance. Add explicit dimensions:

- issuer;
- normative/informative status;
- jurisdiction;
- applicable organization/site/product;
- effective interval;
- supersedes/replaces relation;
- source rank for the review purpose.

Never collapse two assertions merely because one has higher authority. Preserve both and
let the application determine which governs a particular decision.

## 9. Identity and mapping safety

### 9.1 Internal merge

An internal object-node merge states that two internal identifiers denote the same
referent. It should:

- redirect the loser to the survivor;
- preserve the loser ID;
- preserve all mention evidence;
- rebind or resolve assertion endpoints;
- record the actor, reason, evidence, and time;
- trigger impact analysis for cached reviewer results and materialized edges.

### 9.2 External mappings

Use mapping strength deliberately:

| Mapping | Meaning |
| --- | --- |
| exact | interchangeable concept in the intended scope |
| close | highly similar, not safely interchangeable everywhere |
| broad | external term is broader |
| narrow | external term is narrower |
| related | useful association only |

Do not emit `owl:sameAs` from name or embedding similarity. Use it only for approved
same-individual mappings because OWL propagates all assertions across same-individual
identifiers [R1].

### 9.3 Persistent identifiers

Use opaque, stable IDs and dereferenceable IRIs:

```text
internal ID:  ont_01J...
IRI:          https://semos.example/ontology/core/ont_01J...
version IRI:  https://semos.example/ontology/2026-07/core/ont_01J...
```

The production hostname is an implementation choice; the principles are:

- never encode a mutable preferred label in identity;
- never reuse a retired ID;
- redirect deprecated/merged IDs;
- expose current and versioned representations;
- include definitions and provenance.

W3C data best practices recommend persistent URIs, and OWL supports ontology IRIs,
version IRIs, and imports for modularization [R8][R11].

## 10. Storage and interchange decision

### 10.1 Options

#### Option A: move the knowledge base to RDF/OWL and a triple store

Benefits:

- native standards representation;
- off-the-shelf SPARQL and reasoning;
- direct ontology import/export.

Costs:

- substantial migration of current SQL, APIs, indexing, audit, and review paths;
- qualified n-ary claims still require a modeling pattern;
- operational consistency and application joins become a new engineering problem;
- the ontology is not mature enough to justify a storage-platform migration.

#### Option B: Postgres operational ontology with RDF/OWL/SHACL export

Benefits:

- preserves implemented object, artifact, search, review, and audit systems;
- makes important qualifiers explicit and queryable;
- supports deterministic SQL/Go reviewer behavior;
- permits standards-based interchange and offline reasoning;
- can later feed a triple store without changing stable IDs.

Costs:

- the team must maintain mappings between relational and RDF forms;
- reasoning features must be implemented, materialized, or run externally;
- schema discipline is required to avoid JSON becoming an ungoverned escape hatch.

#### Option C: taxonomy plus embeddings/LLM interpretation

Benefits:

- fastest initial implementation;
- useful for candidate retrieval.

Costs:

- no stable property semantics;
- no unit-safe or modality-safe comparison;
- no explicit completeness universe;
- poor reproducibility and governance;
- similarity is mistaken for meaning.

### 10.2 Recommendation

Choose **Option B**.

Use Postgres as the system of record. Publish generated artifacts:

```text
ontology-core.ttl
ontology-metrics.ttl
ontology-provisions.ttl
ontology-inventory.ttl
concept-schemes.ttl
shapes-core.ttl
shapes-profiles.ttl
context.jsonld
```

RDF supplies a standard graph model of subject-predicate-object triples and named
resources, making it an appropriate interchange representation even when the operational
store remains relational [R14].

Add a triple store or description-logic reasoner only when competency tests demonstrate
a concrete workload that SQL/materialized closure cannot meet.

## 11. Development methodology

The LOT methodology organizes ontology work into requirements specification,
implementation, publication, and maintenance, and uses competency questions as functional
requirements [R7]. SemOS should adopt that iterative shape rather than attempt a
corpus-wide ontology in one pass.

### 11.1 Competency questions

The first release should answer these questions:

#### Identity and classification

1. Which artifact-object mentions resolve to this canonical object?
2. Is this node an individual, type, collection, occurrence, or concept?
3. Which ontology classes apply, and what evidence supports each classification?
4. Which node IDs were merged or redirected to the current canonical ID?

#### Metrics

1. Which metric assertions apply to object X?
2. Which assertions measure the same property or quantity kind?
3. Are their units dimensionally compatible and convertible?
4. Are they observations, requirements, targets, references, or capabilities?
5. Under which procedures, conditions, and time windows do they apply?
6. Which assertion pairs are truly comparable?

#### Provisions and inventory

1. Which provision imposes a given metric requirement?
2. Which actor must perform which action on which object?
3. Which inventory item is an instance of which item type?
4. Which items are parts of, located in, or members of another object?

#### Review and provenance

1. Which profile applies to this document and why?
2. Which required assertion patterns are missing?
3. Which source evidence supports or contradicts an assertion?
4. Which source is currently authoritative for this scope and date?
5. How did a processor, model, prompt, or human action produce or modify the assertion?
6. Would an object merge change previous review findings?

Each question should have:

- one or more executable SQL tests;
- an RDF/SPARQL equivalent where exported;
- positive and negative example fixtures;
- expected results reviewed by a domain owner.

### 11.2 Term proposal workflow

```text
propose term
  → check reuse candidates
    → define scope and examples
      → assign stable ID
        → domain review
          → automated ontology/profile validation
            → release
```

Required metadata:

- preferred label;
- textual definition;
- inclusion and exclusion examples;
- parent or broader term;
- domain/range for properties;
- external mappings and mapping strength;
- responsible owner;
- change history;
- status and release.

LLMs may propose terms and mappings. They must not approve them or change released
meanings autonomously.

### 11.3 Releases

Maintain:

```text
kb.ontology_releases
  release_id
  ontology_iri
  version_iri
  version
  status
  released_at
  checksum
  imports
  change_summary
```

Release modules independently but test their import closure together. OWL provides
ontology/version IRIs and imports for this purpose [R11].

## 12. Phased roadmap

### Phase 0: requirements and semantic audit

Deliver:

- approved scope and non-goals;
- competency-question suite;
- inventory of current artifact fields and relation names;
- sample corpus covering ambiguous objects, multilingual names, unit conversion,
  provisions, inventory, and superseded documents;
- documented distinction among identity, type, role, similarity, and assertion.

Exit criterion:

- domain and application owners agree on expected answers for the pilot questions.

### Phase 1: term registry and identity hardening

Deliver:

- ontology release/term/label/mapping records;
- `ontological_level` for object nodes;
- object-classification assertions;
- stable IRI policy;
- SKOS-style multilingual labels and mappings;
- merge impact audit.

Exit criterion:

- specific objects, object types, and concepts are no longer conflated in reconciliation
  fixtures.

### Phase 2: metric ontology pilot

Deliver:

- metric definition versus metric assertion distinction;
- property/quantity-kind mapping;
- QUDT unit mapping and conversions;
- assertion kinds and normalized value forms;
- condition and temporal qualifiers;
- RDF/OWL/SKOS export for the pilot.

Exit criterion:

- the worked pressure examples classify correctly without relying on name similarity.

### Phase 3: qualified assertions and provenance

Deliver:

- semantic assertion and evidence stores;
- processor-run/model/prompt provenance;
- projection of selected assertions into `kb.artifact_connections`;
- assertion APIs and reviewer tools;
- human adjudication and audit workflow.

Exit criterion:

- every reviewer candidate and finding can be traced to normalized assertions and source
  lines.

### Phase 4: profiles and ontology-aware metric review

Deliver:

- profile registry and rules;
- applicability resolution;
- ontology-aware metric candidate ranking;
- comparability service;
- completeness review against explicit profiles;
- SHACL export and conformance fixtures.

Exit criterion:

- object-sharing but non-comparable metrics are filtered or marked
  `related_distinct`, and missing findings cite an applicable profile rule.

### Phase 5: provisions, inventory, and document authority

Deliver:

- provision modality/action/target model;
- inventory instance/type/part/location/state model;
- document authority, version, jurisdiction, and validity model;
- cross-module reviewer queries.

Exit criterion:

- a reviewer can explain whether a metric is required, by which provision, for which
  object, under which authority and effective period.

### Phase 6: publication and optional reasoning service

Deliver:

- versioned ontology and shape artifacts;
- persistent dereferenceable IRIs;
- documentation and examples;
- external ontology consistency checks;
- optional triple-store/reasoner projection if justified.

Exit criterion:

- the released ontology can be consumed independently of ChenWeb and reproduces the
  tested competency answers.

## 13. Testing and quality gates

### Structural tests

- every active term has an immutable ID, IRI, preferred label, definition, and owner;
- preferred labels are unique within a module and language where required;
- deprecated terms identify replacements when appropriate;
- property domains/ranges reference active terms;
- profile rules reference released ontology terms;
- no import cycle loads incompatible module versions.

### Logical tests

- no unsatisfiable classes in exported OWL;
- disjoint individual/type fixtures remain distinct;
- class hierarchy closure is deterministic;
- same-individual mappings are explicitly approved;
- object merges do not create self-contradictory identity redirects.

### Data validation tests

- metric values use a unit compatible with their quantity kind;
- required assertion fields vary correctly by assertion kind;
- observations have a feature of interest, observed property, result, and provenance;
- upper/lower bounds have an operator and comparable value;
- profile cardinality and conditional rules produce expected validation reports.

### Competency regression tests

Every competency question has:

- SQL fixture;
- expected row set;
- exported RDF fixture and SPARQL query when applicable;
- false-positive and false-negative cases;
- multilingual and alias variants where relevant.

### Reviewer evaluation

Measure separately:

- candidate recall;
- candidate precision before LLM review;
- same/conflict/related classification accuracy;
- missing-requirement precision;
- evidence-trace completeness;
- unit/condition/time normalization error rate;
- percentage of findings whose rationale depends on unstructured LLM inference.

The last number should fall as ontology coverage grows, without forcing uncertain
knowledge into false precision.

## 14. Risks and mitigations

### Risk: turning the ontology into a renamed database schema

Mitigation:

- define terms through competency and domain meaning, not current columns;
- publish mappings and formal representations;
- test inference and validation behavior.

### Risk: over-modeling before use

Mitigation:

- begin with metric comparison and completeness;
- add only terms needed by approved competency questions;
- keep modules independently releasable.

### Risk: object-node pollution

Metric subjects may denote types or concepts rather than individuals.

Mitigation:

- add `ontological_level`;
- use level-compatible reconciliation;
- separate class/concept term identity from real-world object identity;
- monitor node creation by producer and level.

### Risk: treating embeddings as ontology

Mitigation:

- keep similarity as candidate generation;
- require explicit mapping/identity decisions;
- retain scores and method as evidence, not semantic truth.

### Risk: `owl:sameAs` propagation errors

Mitigation:

- default external mapping to `close`, `broad`, `narrow`, or `related`;
- require human approval for exact same-individual mappings;
- run impact analysis before activation.

### Risk: false completeness findings

Mitigation:

- require an applicable, versioned profile;
- record applicability rationale;
- model open-world unknown separately from closed-world profile failure;
- permit `undetermined` when evidence or scope is insufficient.

### Risk: ontology drift

Mitigation:

- immutable IDs and versioned releases;
- term owner and review workflow;
- semantic-diff reports;
- backward-compatibility tests;
- never change a term's referents silently.

### Risk: dual relational/RDF implementations diverge

Mitigation:

- generate RDF/SHACL from the operational term/profile records;
- round-trip fixtures;
- one competency suite executed against both representations;
- checksums and release artifacts built in CI.

## 15. Decisions recommended for a follow-up ADR

1. `kb.object_nodes` remains the canonical referent registry.
2. Add `ontological_level`; do not use `object_type` alone to decide identity.
3. Create a versioned ontology-term and concept-scheme registry.
4. Introduce qualified semantic assertions and one-to-many evidence.
5. Model metric definitions separately from observations, requirements, targets, and
   other metric assertion kinds.
6. Adopt QUDT for quantity/unit semantics and SOSA/SSN for observations.
7. Treat `kb.artifact_connections` as a traversal/materialization surface, not the sole
   authoritative semantic-assertion store.
8. Introduce explicit, versioned application profiles for completeness and conformance.
9. Keep Postgres as the operational system of record and generate RDF/OWL/SKOS/SHACL
   artifacts.
10. Govern terms and releases through competency questions, human ownership, automated
    validation, and immutable identifiers.

## 16. Documentation impact

### Knowledge changed

This research adds the missing distinction among:

- canonical referents;
- ontology classes and concepts;
- extracted artifact evidence;
- qualified domain assertions;
- retrieval/similarity edges;
- closed-world document profiles and validation.

It also establishes that a metric must be modeled by property, quantity kind, assertion
kind, value form, unit, conditions, time, and provenance before reliable cross-document
comparison.

### Documents/specs/ADRs affected by a future decision

- `Capsules/coding-capsules/doc-processor/extract-metrics-spec.md`
  - metric semantic normalization and assertion output;
  - object/property/quantity-kind separation;
  - review discovery based on property and comparability.
- `doc-repo/adrs/202606/2026063002-adr-doc-reviewer-metric.md`
  - ontology-aware retrieval;
  - assertion-level findings;
  - profile-based completeness.
- `Capsules/coding-capsules/doc-processor/+CAPSULE.md`
  - Phase C ontology classification/assertion indexing and module contracts.
- `doc-repo/adrs/202607/2026070101-adr-object-centric-design.md`
  - `ontological_level`;
  - classification versus identity;
  - assertion and ontology layers above object nodes.
- `doc-repo/adrs/202606/2026061801-adr-document-review.md`
  - ontology/profile tools;
  - applicability and completeness semantics;
  - provenance-rich findings.
- provision, inventory-item, and entity-relation extraction specs
  - domain-module output and assertion mappings.

### Documents updated now

- This research document only.

### Documents intentionally left unchanged

The five source documents remain unchanged because the ontology architecture is a
research recommendation, not yet an accepted ADR or implementation contract. Updating
their normative language before a decision would make the documentation claim behavior
that does not exist.

### Tests intentionally not changed

No code or schema changed. The proposed competency, ontology, profile, and reviewer tests
belong in the follow-up ADR and implementation plan.

## 17. Local sources reviewed

- [L1] `KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-metrics-spec.md`
- [L2] `KnowledgeStore/doc-repo/adrs/202606/2026063002-adr-doc-reviewer-metric.md`
- [L3] `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md`
- [L4] `KnowledgeStore/doc-repo/adrs/202607/2026070101-adr-object-centric-design.md`
- [L5] `KnowledgeStore/doc-repo/adrs/202606/2026061801-adr-document-review.md`
- [L6] `ChenWeb/project_migrations/20260702000002_create_kb_artifact_objects.sql`
- [L7] `ChenWeb/project_migrations/20260702000003_create_kb_object_nodes.sql`
- [L8] `ChenWeb/project_migrations/20260602000002_create_kb_artifact_connections.sql`
- [L9] `ChenWeb/server/api/doc-processing/connections.go`
- [L10] `ChenWeb/server/api/kbhandler/object_graph.go`

## 18. External references

- [R1] W3C. *OWL 2 Web Ontology Language Primer (Second Edition).*
  <https://www.w3.org/TR/owl2-primer/>
- [R2] W3C. *SKOS Simple Knowledge Organization System Reference.*
  <https://www.w3.org/TR/skos-reference/>
- [R3] W3C. *Shapes Constraint Language (SHACL).*
  <https://www.w3.org/TR/shacl/>
- [R4] W3C. *PROV-O: The PROV Ontology.*
  <https://www.w3.org/TR/prov-o/>
- [R5] W3C and OGC. *Semantic Sensor Network Ontology — 2023 Edition.*
  <https://www.w3.org/TR/vocab-ssn-2023/>
- [R6] QUDT.org. *QUDT Catalog: Quantities, Units, Dimensions and Data Types
  Ontologies.*
  <https://www.qudt.org/catalog/qudt-catalog.html>
- [R7] Poveda-Villalón, M., Fernández-Izquierdo, A., Fernández-López, M., and
  García-Castro, R. *LOT: An industrial oriented ontology engineering framework.*
  Engineering Applications of Artificial Intelligence, 2022.
  <https://doi.org/10.1016/j.engappai.2022.104755>
- [R8] W3C. *Data on the Web Best Practices.*
  <https://www.w3.org/TR/dwbp/>
- [R9] W3C. *The Profiles Vocabulary.*
  <https://www.w3.org/TR/dx-prof/>
- [R10] OBO Foundry. *Principles: Overview.*
  <https://obofoundry.org/principles/fp-000-summary.html>
- [R11] W3C. *OWL 2 Web Ontology Language Structural Specification and
  Functional-Style Syntax (Second Edition).*
  <https://www.w3.org/TR/owl2-syntax/>
- [R12] Wilkinson, M. D. et al. *The FAIR Guiding Principles for scientific data
  management and stewardship.* Scientific Data 3, 160018 (2016).
  <https://doi.org/10.1038/sdata.2016.18>
- [R13] W3C. *Time Ontology in OWL.*
  <https://www.w3.org/TR/owl-time/>
- [R14] W3C. *RDF 1.1 Concepts and Abstract Syntax.*
  <https://www.w3.org/TR/rdf11-concepts/>

External sources were accessed on 2026-07-23. Primary standards and original methodology
or principles publications were preferred over secondary summaries.

[R1]: https://www.w3.org/TR/owl2-primer/
[R2]: https://www.w3.org/TR/skos-reference/
[R3]: https://www.w3.org/TR/shacl/
[R4]: https://www.w3.org/TR/prov-o/
[R5]: https://www.w3.org/TR/vocab-ssn-2023/
[R6]: https://www.qudt.org/catalog/qudt-catalog.html
[R7]: https://doi.org/10.1016/j.engappai.2022.104755
[R8]: https://www.w3.org/TR/dwbp/
[R9]: https://www.w3.org/TR/dx-prof/
[R10]: https://obofoundry.org/principles/fp-000-summary.html
[R11]: https://www.w3.org/TR/owl2-syntax/
[R12]: https://doi.org/10.1038/sdata.2016.18
[R13]: https://www.w3.org/TR/owl-time/
[R14]: https://www.w3.org/TR/rdf11-concepts/
