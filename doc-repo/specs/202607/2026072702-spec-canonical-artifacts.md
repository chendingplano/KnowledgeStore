# Spec 2026072702 - Canonical Artifact Links and Ontology Governance

**Date:** 2026-07-27  
**Status:** Proposal  
**Component:** SemOS Knowledge Base, Ontology, Document Processing, and Review  
**Authors:** Chen Ding

## 1. Summary

SemOS artifacts include metrics, provisions, inventory items, entities, summaries,
semantic projections, topics, and scene blocks. These artifacts are extracted from
documents and retain source evidence. They are information objects; they are not
automatically canonical descriptions of the world or authoritative statements of what
should be.

Some artifacts identify or mention real-world and domain referents. SemOS already
reconciles those mentions through:

```text
source artifact
  -> kb.artifact_objects
    -> kb.object_nodes
```

`kb.object_nodes` is the canonical referent registry. It answers:

> Which mentions refer to the same thing?

Canonical referents alone, however, cannot answer SemOS's central governance question:

> For an object or object class in a defined context, what properties, metrics,
> relationships, constraints, and evidence should or must exist?

That question requires an ontology vocabulary, qualified assertions, and versioned
application profiles in addition to canonical object identity.

This specification makes the following decisions:

1. Do not create a universal "canonical artifact" layer.
2. Keep `kb.object_nodes` as the canonical registry for referents, including identifiable
   individuals, types, collections, and occurrences.
3. Introduce a governed ontology-term and concept-scheme layer for classes, properties,
   quantity kinds, assertion kinds, roles, and controlled concepts.
4. Introduce qualified semantic assertions with one-to-many source evidence.
5. Represent "what should be" through explicit, versioned ontology profiles and profile
   rules, not through corpus frequency or similarity.
6. Link summaries, semantic projections, topics, and scene blocks to referents, terms,
   assertions, and profiles when evidence supports the link; do not canonicalize these
   derived artifacts themselves.
7. Keep `kb.search_artifacts` as the retrieval surface and
   `kb.artifact_connections` as a derived navigation graph. Neither is the sole
   authoritative ontology or assertion store.

## 2. Problem

### 2.1 Current Strength

Metrics, provisions, inventory items, and selected entities can produce
`kb.artifact_objects` rows. Reconciliation links object mentions to stable
`kb.object_nodes` referents across artifacts, processors, and documents.

The relationship is many-to-many:

- one artifact may mention several objects in different roles;
- one canonical object may be supported by many artifact-object mentions;
- an artifact-object mention resolves to at most one active canonical referent at a time;
- ambiguous mentions may remain unresolved pending deterministic, LLM, or human review.

This identity layer allows SemOS to collect artifacts that concern the same referent.

### 2.2 Current Gap

Canonical identity does not define domain meaning or normative expectations.

For example, resolving the strings "pump," "P-101," and "centrifugal pump P-101" to
canonical referents does not by itself tell SemOS:

- whether P-101 is an instance of a pump class;
- which pump subclass applies;
- which metrics are meaningful for that class;
- which metrics are mandatory rather than optional;
- which unit dimensions and value ranges are valid;
- which standard, jurisdiction, operating mode, or effective date governs the rule;
- which evidence establishes that the reviewed document satisfies the rule.

Today, related artifacts may be discovered through full-text/vector search, source-line
overlap, category paths, and `kb.artifact_connections`. These mechanisms are useful for
retrieval and navigation, but they do not establish canonical identity, ontology meaning,
or normative applicability.

### 2.3 Risk in Canonicalizing Every Artifact

Summaries, semantic projections, topics, and scene blocks have different semantics and
lifecycles:

- summaries and semantic projections are regenerated views of source spans;
- topics are document-scoped concept candidates and retrieval facets;
- scene blocks combine occurrences, participants, actions, states, and claims.

Treating each family as a new canonical-node family would conflate:

```text
same identity      != same class
same class         != same topic
same topic         != same assertion
same assertion     != similar text
similar text       != same occurrence
```

Such conflation would cause false merges, accidental ontology rules, loss of provenance,
and unstable identities whenever processors, prompts, chunk boundaries, or source
documents change.

## 3. Goals

This specification has the following goals:

1. Enable SemOS to answer ontology-governed "what should be" questions.
2. Preserve a clear boundary between source evidence, referent identity, ontology
   vocabulary, assertions, profiles, navigation, and retrieval.
3. Allow every artifact family to make evidence-grounded links to canonical referents and
   ontology semantics.
4. Support document review for completeness, conformance, contradiction, and traceability.
5. Preserve conflicting or superseded source assertions without corrupting canonical
   identity.
6. Make every normative result explainable through profile rules, source authority, and
   evidence.
7. Support versioning, deprecation, merge/split, reprocessing, and human adjudication.

## 4. Non-Goals

This specification does not:

- treat all extracted entities as canonical objects;
- promote every topic or category path to an ontology class;
- infer normative requirements from document frequency;
- treat vector or lexical similarity as identity or semantic equivalence;
- store all ontology meaning directly on `kb.object_nodes`;
- use `kb.artifact_connections` as the authoritative store for qualified assertions;
- define every domain ontology module in one release;
- require RDF, OWL, SKOS, SHACL, or a graph database as the operational system of record.

PostgreSQL remains the operational system of record. Standards-compatible RDF, OWL,
SKOS, and SHACL representations may be generated from governed records.

## 5. Terminology

### 5.1 Artifact

An extracted or generated information object with provenance, such as a metric,
provision, inventory item, entity, summary, semantic projection, topic, or scene block.

### 5.2 Artifact-Object Mention

A `kb.artifact_objects` row recording that an artifact mentions a possible referent, with
role, names, evidence, line spans, confidence, and reconciliation status.

### 5.3 Canonical Referent

A stable `kb.object_nodes` identity representing the thing to which one or more mentions
refer. A referent is normally an individual, collection, occurrence, document,
organization, place, or other identifiable subject of assertions.

An ontology class or concept normally exists only as an ontology term. A type or concept
receives an object node only when SemOS must make claims about that type or concept as an
independently identified referent. In that exceptional case:

- the ontology term remains the authoritative definition of its meaning;
- the object node carries referent identity and provenance only;
- an explicit `denotes_term` assertion links the object node to exactly one active
  ontology term;
- labels or similarity must not create the object node or `denotes_term` assertion
  automatically.

For example, the class "centrifugal pump" is an ontology term. Pump P-101 is a canonical
object classified under that term. A separately identified standards-body concept record
may receive both an object node and a term only if SemOS needs to track claims about that
concept record itself.

Normative identity/vocabulary decision table:

| Input | Artifact retained? | Object node? | Ontology term? | Required relationship |
|---|---:|---:|---:|---|
| Pump P-101 at Plant A | If extracted | Yes, `individual` scoped to Plant A | No new term | `instance_of` the existing pump-class term |
| Class "centrifugal pump" | If extracted as evidence | No by default | Yes, `class` | Class axioms and governed labels |
| Topic "pump maintenance" | Yes, as topic | No | Candidate or accepted `concept` term | `about_term` after mapping review |
| Summary discussing P-101 | Yes, as summary | No | No new term by default | Object mention and/or `about_term`, grounded in spans |
| Failure occurrence at 2026-07-01 10:00 | If extracted as scene/evidence | Yes, `occurrence`, when identity evidence is sufficient | Optional failure-class term | `describes_occurrence` plus occurrence classification |
| Standards-body concept record used as a claim subject | If extracted | Yes, exceptionally | Yes | Exactly one active accepted `denotes_term` assertion |

### 5.4 Ontology Term

A governed semantic identifier with a definition and lifecycle. A term may represent a
class, property, quantity kind, assertion kind, role, controlled concept, or profile rule
identifier. Terms are not interchangeable with canonical object referents.

### 5.5 Semantic Assertion

A qualified claim with a subject, predicate, value or object, assertion kind, modality,
conditions, confidence, status, valid time, and provenance.

Examples include:

- P-101 is an instance of centrifugal pump;
- P-101 has a measured discharge pressure of 690 kPa;
- pumps of class C shall declare maximum allowable working pressure;
- a safety pump must be inspected every 12 months.

### 5.6 Ontology Profile

A versioned, scoped set of expectations used to answer "what should be" for a target
class and context. A profile may define required properties, cardinalities, units,
conditions, prohibitions, and evidence expectations.

### 5.7 Retrieval and Navigation Relations

Search similarity, line overlap, structural adjacency, and projected graph edges help
users and reviewers discover related information. They are not automatically identity,
classification, assertion, or normative-rule decisions.

## 6. Design Principles

### P1. Canonical Objects Identify Referents

`kb.object_nodes` identifies things. It must not become a bag of mutable facts or a
generic deduplication store for generated text.

### P2. Ontology Terms Define Meaning

Object classification, property definitions, quantity kinds, roles, and assertion kinds
must reference governed ontology terms. Labels and lexical similarity generate
candidates; they do not establish equivalence.

The authoritative boundary is:

```text
object node     identifies a referent
ontology term   defines intensional meaning
denotes_term    explicitly connects the exceptional referent that denotes a term
```

### P3. Preserve Source Assertions

Different documents may make conflicting claims about the same referent. Preserve each
qualified assertion and its evidence. Authority and applicability determine how SemOS
uses a claim; they do not erase competing claims.

### P4. Profiles Govern "What Should Be"

The absence of an artifact from the corpus does not prove that a requirement is
unsatisfied, and corpus frequency does not make a property mandatory. Normative
expectations must come from explicit profiles and profile rules with scope, version,
authority, and effective dates.

### P5. Classification Is Not Identity

Two objects classified as pumps are not the same pump. A topic called "pump maintenance"
is not a pump object. A category called "pressure metrics" is not automatically an OWL
class or a required-property rule.

### P6. Similarity Is a Candidate Generator

Hybrid search and embeddings may propose links, mappings, or review candidates.
Similarity must never silently create identity, exact-term mappings, ontology axioms, or
normative requirements.

### P7. Important Semantics Require Provenance

Identity, classification, assertion, mapping, and profile-rule decisions must retain
their method, confidence, source, version, and review state.

## 7. Target Architecture

SemOS shall use the following logical layers:

```text
Layer 7  Review and applications
         completeness, conformance, contradiction, explanations

Layer 6  Ontology profiles
         scoped and versioned definitions of what should/must exist

Layer 5  Qualified semantic assertions
         what a source or authority claims, with conditions and evidence

Layer 4  Domain ontology modules
         pump, tax, document, organization, and other bounded modules

Layer 3  Ontology terms and concept schemes
         classes, properties, quantity kinds, assertion kinds, roles, concepts

Layer 2  Canonical referent identity
         kb.object_nodes, classifications, merges, redirects

Layer 1  Source artifacts and evidence
         extracted artifacts, kb.artifact_objects, line spans, provenance

Access   kb.artifact_connections and kb.search_artifacts
         derived navigation and retrieval surfaces
```

Each layer has an independent lifecycle. A processor rerun may replace derived artifacts
without changing a governed ontology term or canonical referent. An ontology release may
deprecate a term without deleting source evidence. A profile revision may change review
expectations without rewriting historical assertions.

## 8. Logical Data Contracts

Final physical schemas require a follow-up ADR and migrations. The logical contracts
below establish the required boundaries.

### 8.1 Canonical Referents

`kb.object_nodes` remains the canonical referent registry. It should be extended, as
specified in the ontology research, with:

- `ontological_level`: individual, type, collection, occurrence, or concept;
- `identity_scope`: plant, organization, catalog, jurisdiction, or another namespace;
- external identifiers;
- validity information where identity changes over time;
- explicit classification and role relations rather than a single overloaded type.

`ontological_level = type|concept` is a compatibility capability, not the default
representation of ontology vocabulary. New classes and concepts must be created in
`kb.ontology_terms`. A type/concept object node is permitted only under the exceptional
rule in Section 5.3 and requires an accepted `denotes_term` assertion.

### 8.2 Ontology Terms

Use governed logical stores equivalent to:

```text
kb.ontology_terms
kb.ontology_term_labels
kb.ontology_axioms
kb.ontology_mappings
kb.ontology_releases
```

Terms require immutable IDs, stable IRIs, definitions, term kinds, namespaces, release
provenance, status, and deprecation/replacement semantics.

Mappings must distinguish `exact`, `close`, `broad`, `narrow`, and `related`. Lexical or
embedding similarity alone may create a candidate mapping, not an approved exact mapping.

### 8.3 Qualified Assertions and Evidence

Use logical stores equivalent to:

```text
SemanticAssertion
  assertion_id
  subject_ref
  predicate_term_id
  object_ref or typed_literal
  assertion_kind_term_id
  polarity
  modality
  qualifiers
  confidence
  status
  valid_time
  transaction_time

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
  evidence_role
```

Several artifacts may support one assertion, and one artifact may support several
assertions. Assertions must survive processor-specific index rebuilds and support
adjudication, supersession, and conflict relationships.

### 8.4 Ontology Profiles

Use governed logical stores equivalent to:

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
  rule_kind
  evaluation_quantifier
  rule_definition
  severity
  message_template
  authority_id
  authority_document_ref
  authority_edition
  jurisdiction
  effective_from
  effective_to
  source_artifact_type
  source_artifact_id
  source_line_spans
  approval_status
  approved_by
  approved_at
```

Supported rule kinds should include:

- required assertion or property pattern;
- minimum and maximum cardinality;
- datatype and value shape;
- quantity kind and unit dimension;
- conditional requirement;
- allowed or prohibited relation;
- evidence and authority requirement.

Operational execution may initially use SQL and Go, provided it is semantically
equivalent to the versioned profile and can be exported as a SHACL-compatible shape.

Every active rule must identify its authoritative document or governed authority record,
edition/version, jurisdiction or scope, effective interval, source provision or artifact,
line-level evidence where available, and approval decision. A rule without complete
authority provenance remains `draft` and cannot produce a normative finding.

### 8.5 Artifact Semantic Links

Every artifact family may link to ontology semantics, but each semantic relationship has
one authoritative owner. The same relationship must not be independently authored in
several stores.

| Relationship | Authoritative owner | Derived projection allowed |
|---|---|---|
| Artifact mentions/denotes referent | `kb.artifact_objects` | `kb.artifact_connections` |
| Referent classified under term | accepted semantic assertion | object-node convenience field and graph edge |
| Object node denotes ontology term | accepted `denotes_term` assertion | graph edge |
| Artifact supports/contradicts assertion | assertion-evidence record | graph edge |
| Artifact is about ontology concept | artifact-semantic link | search payload and graph edge |
| Scene block describes occurrence | artifact-semantic link | graph edge |
| Review scope governed by profile | immutable review-scope selection record | finding metadata |

A dedicated artifact-semantic-link contract is therefore limited to relationships not
owned by `kb.artifact_objects`, semantic assertions, assertion evidence, or review-scope
selection. Its initial link kinds are:

| Link kind | Meaning |
|---|---|
| `about_term` | Artifact is substantively about a governed ontology term. |
| `describes_occurrence` | Artifact describes an identifiable occurrence object node. |

For `describes_occurrence`, the artifact-semantic link owns the relationship. The target
`kb.object_nodes` row independently owns only the occurrence's canonical identity.

Each link must record:

- source artifact type and ID;
- target reference type and ID;
- relation kind;
- extraction or decision method;
- source line spans or other evidence;
- confidence;
- status: candidate, accepted, rejected, or superseded;
- processor/model/prompt or human provenance;
- creation and modification times.

Search-only similarity must not be persisted as an accepted semantic link unless a
separate decision process validates it.

Derived projections must carry the authoritative source record ID and may not be edited
independently. Rebuilding a projection must not delete or replace its authoritative
record. If projected and authoritative values disagree, the authoritative store wins,
the projection is marked stale, and repair is queued and logged.

## 9. Artifact-Family Decisions

| Artifact family | Canonicalize the artifact? | Required ontology treatment |
|---|---|---|
| Metric | No | Link object mentions to referents; normalize property, quantity kind, unit, value, and assertion kind. |
| Provision | No | Link regulated objects and actors; normalize modality, authority, conditions, and required/prohibited assertions. |
| Inventory item | No | Reconcile the item and related systems to referents; classify the referent and preserve inventory claims as assertions. |
| Entity | No | Selectively reconcile concrete entities to referents; map entity concepts to governed terms only after validation. |
| Summary | No | Preserve as a derived evidence view; link to referents, terms, and assertions through grounded source spans. |
| Semantic projection | No | Preserve as document/chunk search enrichment; link to referents or terms only when grounded and typed. |
| Topic | No | Treat as a document-scoped concept candidate; reconcile to ontology terms or SKOS-like concepts, not directly to canonical object identity. |
| Scene block | Usually no | Link actors/resources to referents; represent actions, states, and outcomes as assertions; canonicalize only an identifiable occurrence. |

### 9.1 Summaries

A summary's identity depends on document version, chunking, grouping, processor version,
prompt, and model. It is therefore not a stable cross-document referent.

Summaries may:

- mention several canonical referents;
- be about several ontology concepts;
- support or summarize several assertions;
- inherit candidate links from grounded child source spans.

Inherited links must remain distinguishable from explicit extraction. Higher-level
summaries must not amplify a weak child association into an accepted semantic fact.

### 9.2 Semantic Projections

Semantic projections are one-to-one with processing chunks and serve as search
enrichment through descriptive names, keywords, category paths, and vectors. They are
not canonical semantic objects.

Category paths are retrieval facets. They may generate candidate ontology-term mappings,
but they must not automatically create class axioms, identity, or profile rules.

### 9.3 Topics

Topics are document-scoped descriptions of what a span discusses. A topic may map to:

- one or more governed SKOS-like concepts;
- one or more ontology classes or properties after review;
- one or more canonical referents when the topic concerns specific instances;
- no canonical term when it is too broad, compound, transient, or ambiguous.

SemOS shall not create a separate `Canonical Topics` registry. Canonical conceptual
meaning belongs in `kb.ontology_terms` and concept schemes. Extracted topics remain
evidence for candidate mappings.

### 9.4 Scene Blocks

A scene block is a structured evidence artifact, not a single semantic entity. It may
contain:

- actors and resources that resolve to canonical referents;
- an occurrence that may have canonical identity;
- a process or workflow class;
- actions, states, decisions, constraints, causes, and outcomes represented as qualified
  assertions.

Two scene blocks should be reconciled to one occurrence only when identity evidence
supports that conclusion, such as a shared event identifier, time, location, participants,
and source context. Similar workflows or failure patterns are class/similarity relations,
not occurrence identity.

The existing `kb.scene_objects.object_id` is a scene-local artifact identifier and is not
`kb.object_nodes.object_id`. A follow-up migration should rename or deprecate it in favor
of `scene_block_id` before canonical occurrence links are added.

## 10. "What Should Be" Review Workflow

### 10.1 Review Scope and Profile Selection

A normative review must begin with an immutable review-scope record:

```text
OntologyReviewScope
  review_scope_id
  reviewed_document_ids
  target_object_ids
  target_class_term_ids
  as_of_date
  jurisdiction
  operating_context
  selected_profile_ids_and_versions
  selection_mode              explicit | deterministic_rule
  precedence_policy
  closed_world_dimensions
  selected_by
  selection_reason
  created_at
```

Profile selection may be:

- explicit, by an authorized user or calling workflow; or
- deterministic, using approved applicability rules over object classification,
  jurisdiction, authority, document type, service, safety class, and effective date.

An LLM may recommend profiles but may not be the sole authority that activates a profile.
Every selected profile version and selection reason must be frozen in the review scope so
that the result can be reproduced later.

Multiple profiles are additive unless the review scope contains an approved precedence
policy. SemOS must not silently assume that the strictest, newest, or highest-confidence
rule wins. When applicable rules conflict and the precedence policy does not resolve the
conflict, the affected result is `indeterminate` and the conflict is reported.

Closed-world evaluation must be declared per rule family or dimension. For example, a
scope may be closed for required pump metrics but open for optional maintenance topics.
Only a closed dimension may produce a `missing` finding.

### 10.2 Pump Example

Assume a reviewed document mentions "centrifugal pump P-101."

SemOS should process the reference as follows:

```text
1. Evidence
   Entity/inventory/metric/provision artifacts preserve the source text and spans.

2. Referent resolution
   "P-101" resolves to a canonical object node scoped to the relevant plant.

3. Classification
   P-101 is classified as an instance of the ontology class "centrifugal pump."

4. Profile selection
   Select applicable pump profiles using document type, pump class, jurisdiction,
   governing standard and version, service, safety classification, and effective date.

5. Expected assertion patterns
   The selected profile requires, for example:
   - manufacturer and model;
   - rated flow rate;
   - rated head;
   - maximum allowable working pressure;
   - operating temperature range;
   - inspection interval;
   - required units and evidence.

6. Observed assertions
   Normalize document metrics and provisions into qualified assertions linked to P-101.

7. Comparison
   Match observed assertions to expected patterns by canonical referent, ontology
   property, quantity kind, assertion kind, modality, unit dimension, and conditions.

8. Findings
   Report satisfied, missing, conflicting, inapplicable, or indeterminate requirements.

9. Explanation
   Trace every finding to the profile rule, authority, object classification,
   normalized assertion, and source evidence.
```

### 10.3 Finding Decision Procedure

SemOS shall first compile the selected profiles into an applicable rule set. Two rules
conflict when their applicability regions overlap for the same target and semantic slot
and they cannot both be satisfied within that overlap. A semantic slot is the normalized
combination of target class, property/relation, assertion kind, and relevant qualifier
dimensions. Conflicts include incompatible required/prohibited patterns, minimum
cardinality greater than maximum cardinality, disjoint datatype or unit requirements, or
mutually exclusive value constraints during any shared effective interval or condition
region.

Apply the frozen precedence policy to each conflict set. If it selects a governing rule,
record the selected and suppressed rule IDs with the policy reason. If it does not resolve
the set, emit one `profile_rule_conflict` scope finding with result `indeterminate`, skip
per-rule evaluation only for that affected semantic slot, and continue evaluating
unaffected rules.

For each remaining applicable profile rule, SemOS shall evaluate findings in this order:

1. **Resolve scope and applicability.** If object identity, classification, profile
   version, jurisdiction, effective time, or rule conditions cannot be resolved, return
   `indeterminate`. If the conditions are resolved and do not apply, return
   `inapplicable`.
2. **Select qualifying evidence.** Include only assertions whose subject, validity,
   conditions, authority class, and evidence status satisfy the review scope.
3. **Normalize and classify candidates.** Map properties and quantity kinds to ontology
   terms, convert units through approved mappings, and classify every candidate as
   conforming, nonconforming, or indeterminate against non-cardinality constraints.
   Numeric tolerance, rounding, allowed units, and comparison operators come from the
   profile rule; there is no global tolerance.
4. **Resolve precedence.** Apply only the precedence policy frozen in the review scope.
   Never prefer an assertion solely because it is newer or has higher model confidence.
5. **Detect assertion conflict.** If two individually conforming assertions remain
   mutually incompatible after normalization and precedence for a slot whose semantics
   require a single compatible value, return `conflicting`. A conforming candidate and a
   nonconforming candidate do not produce `conflicting`; the rule quantifier governs that
   mixed set.
6. **Apply the rule quantifier.** Every rule definition must declare one evaluation
   quantifier:
   - `exists_conforming`: at least one conforming assertion satisfies the rule;
     nonconforming candidates are retained as separate assertion-level findings unless
     the rule also declares `reject_nonconforming = true`, in which case any
     nonconforming candidate makes the aggregate rule `nonconforming`;
   - `all_conforming`: any qualifying nonconforming candidate makes the aggregate rule
     `nonconforming`;
   - `count_conforming`: the number of conforming assertions must fall within the rule's
     minimum and maximum cardinality;
   - `none_matching`: any matching assertion violates a prohibition and makes the rule
     `nonconforming`.
7. **Evaluate conformance and satisfaction.** Apply datatype, unit, range, modality,
   cardinality, and prohibition constraints under the declared quantifier. Return
   `nonconforming` when the quantifier fails because qualifying evidence violates a
   constraint; return `satisfied` when it succeeds.
8. **Evaluate absence according to the quantifier.**
   - `none_matching` with zero matching assertions returns `satisfied`.
   - `count_conforming` with minimum zero and zero conforming assertions returns
     `satisfied`.
   - `exists_conforming`, `all_conforming` with minimum one, or `count_conforming` with
     minimum greater than zero returns `missing` only when the relevant dimension is
     closed; otherwise it returns `indeterminate`.
   - `all_conforming` must declare a minimum cardinality; zero is allowed and makes an
     empty candidate set `satisfied`.

Every evaluation must retain the candidate assertion set, rejected-candidate reasons,
normalization operations, precedence decisions, and final rule result.

### 10.4 Expected Result Categories

A reviewer must distinguish:

- `satisfied`: qualifying evidence satisfies the applicable rule;
- `missing`: a closed-world profile requires an assertion and none is present;
- `conflicting`: relevant assertions disagree after normalization;
- `nonconforming`: an assertion violates a constraint, unit, range, or prohibition;
- `inapplicable`: the rule's stated conditions do not apply;
- `indeterminate`: classification, applicability, identity, or evidence is insufficient.

Absence may be reported as `missing` only within an explicitly selected closed-world
profile. Outside such a profile, absence means unknown.

## 11. Relationship to Existing Stores

### 11.1 `kb.artifact_objects`

Continue using this table as the source of truth for extracted object mentions. Extend
producer coverage only when an artifact contains grounded object evidence. Do not use it
as the hybrid-search registry or as a canonical-artifact table.

### 11.2 `kb.object_nodes`

Continue using this table as the stable referent registry. Do not store mutable metric
values, normative requirements, or generated summaries directly on object nodes.

### 11.3 `kb.search_artifacts`

Continue using this table as the normalized lexical/vector retrieval surface. Search
results are candidates for navigation or adjudication, not accepted identity or ontology
decisions.

### 11.4 `kb.artifact_connections`

Continue using this table for line-overlap, structural, category, manual, object, and
projected semantic traversal edges. Authoritative qualified assertions and profile rules
must have independent stores and lifecycles. Selected assertions may be projected into
`kb.artifact_connections` for backward-compatible traversal.

### 11.5 Current-State Verification

The existing-store descriptions in this section are based on ADRs and migrations
reviewed on 2026-07-27. Before implementation, Phase 1 must verify them against the
deployed database and current code, including:

- artifact-object cardinality and reconciliation constraints;
- active `kb.search_artifacts` partitions and reindex behavior;
- `kb.artifact_connections` partitions, uniqueness, and replacement lifecycle;
- scene-block identifier semantics;
- cascade, deletion, and reprocessing behavior.

Any mismatch must update this specification or a superseding ADR before migrations are
written. Once verified, these responsibilities become normative contracts and require
regression tests.

## 12. Alternatives Considered

### A1. Canonicalize Every Artifact Family

Rejected. Generated summaries, projections, topics, and scene blocks do not share stable
identity criteria. This approach would conflate evidence, concepts, occurrences, and
claims.

### A2. Use Only `kb.object_nodes`

Rejected. Referent identity cannot express ontology definitions, property semantics,
qualified assertions, authority, conditions, or closed-world completeness profiles.

### A3. Use Only `kb.artifact_connections`

Rejected. The table is optimized for derived traversal edges and processor-specific
replacement. Qualified assertions need multiple evidence records, temporal and modal
qualifiers, revision state, and an independent lifecycle.

### A4. Use Search Similarity as the Semantic Layer

Rejected. Similarity is useful for candidate generation but cannot safely establish
identity, exact mappings, applicability, or normative requirements.

### A5. Layered Ontology Architecture

Accepted for this proposal. It reuses canonical referents while introducing separate
governed layers for terms, assertions, profiles, and evidence-grounded artifact links.

## 13. Phased Delivery

### Phase 1. Correct Boundaries and Identifiers

- Correct documentation that describes artifact-object cardinality as one-to-one.
- Document `kb.search_artifacts`, `kb.artifact_objects`, and
  `kb.artifact_connections` responsibilities consistently.
- Rename or deprecate `kb.scene_objects.object_id` as `scene_block_id`.
- Define typed reference and semantic-link contracts.
- Add provenance and status requirements for semantic decisions.

### Phase 2. Ontology Terms and Classification

- Implement governed ontology terms, labels, mappings, axioms, and releases.
- Add `ontological_level` and identity scope to canonical referents.
- Add explicit object classification and role assertions.
- Map selected topic/category candidates to governed terms through reviewable workflows.

### Phase 3. Qualified Assertions and Evidence

- Implement semantic assertions and one-to-many assertion evidence.
- Normalize metric and provision outputs into assertion kinds, properties, quantities,
  units, modalities, and conditions.
- Project selected accepted assertions into `kb.artifact_connections`.

### Phase 4. Profiles and "What Should Be" Review

- Implement ontology profiles and profile rules.
- Begin with one bounded pump profile and a controlled set of required metric patterns.
- Select profiles explicitly by scope and applicability.
- Produce traceable completeness and conformance findings.
- Export equivalent SHACL shapes for validation and interoperability.

### Phase 5. Additional Artifact Links

- Add grounded referent/term/assertion links for summaries and semantic projections.
- Reconcile topics to concept schemes.
- Decompose scene blocks into participant links, occurrence identity candidates, and
  qualified assertions.
- Measure precision before enabling automatic accepted links.

## 14. Acceptance Criteria

### 14.1 Specification Acceptance

This architecture specification is ready for follow-up ADRs when:

1. Every artifact family in Section 9 has an explicit canonicalization decision.
2. Every semantic relationship in Section 8.5 has exactly one authoritative owner.
3. The static type/concept decision table in Section 5.3 classifies:
   - pump P-101 as an object node;
   - "centrifugal pump" as an ontology class term;
   - a pump-maintenance topic as an artifact mapped to a concept term;
   - an exceptional concept referent as an object node only with an accepted
     `denotes_term` assertion.
4. A profile rule without complete authority provenance is prohibited from active status.
5. A review cannot produce `missing` unless its immutable scope declares the evaluated
   dimension closed.
6. Multiple applicable profiles with unresolved rule conflicts produce `indeterminate`,
   not an implicit winner.
7. Physical schema, release governance, and domain-module details remain explicitly
   assigned to follow-up ADRs rather than implied by this specification.

### 14.2 Phase 1-3 Implementation Acceptance

The identity, term, and assertion foundations are complete when automated integration
tests demonstrate:

1. One artifact persists two object mentions with different roles and each reconciles
   independently.
2. Executable tests realize every row of the specification's type/concept decision table.
3. Creating or updating a search-similarity result creates no object node, exact ontology
   mapping, accepted semantic link, assertion, or profile rule.
4. Reprocessing a document replaces processor-owned artifacts and derived projections
   while preserving immutable term IDs, released profile versions, accepted assertions,
   and canonical object IDs unless an audited reconciliation action changes them.
5. Two conflicting source assertions remain separately queryable with independent
   evidence and provenance.
6. Every graph projection references its authoritative source record; a deliberately
   corrupted projection is detected as stale and repaired from that source.
7. Topic mappings exercise candidate, accepted, rejected, and superseded states without
   changing the extracted topic artifact.
8. Migration up/down tests and backfill fixtures report ambiguous records without
   assigning arbitrary identities or mappings.

### 14.3 Phase 4 Pump-Review Acceptance

The first "what should be" implementation is complete when a fixed pump fixture and
versioned profile produce these deterministic results:

1. A complete P-101 document with all required, correctly normalized assertions returns
   `satisfied` for every rule.
2. Removing rated flow from the same fixture returns `missing` when the metric dimension
   is closed and `indeterminate` when it is open.
3. Supplying an incompatible unit dimension or out-of-range value returns
   `nonconforming`.
4. Supplying two applicable, incompatible pressure assertions without a resolving
   precedence rule returns `conflicting`.
5. Under `exists_conforming`, one conforming and one nonconforming assertion satisfies the
   aggregate rule and emits a separate assertion-level nonconformance; the same evidence
   under `all_conforming` returns aggregate `nonconforming`.
6. A `count_conforming` fixture exercises minimum and maximum cardinality boundaries.
7. Two incompatible applicable profile rules without a resolving precedence policy emit
   `profile_rule_conflict = indeterminate`, skip only their shared semantic slot, and do
   not block unrelated rules.
8. Removing the pump classification, applicable jurisdiction, or profile version returns
   `indeterminate`.
9. A conditionally irrelevant rule returns `inapplicable`.
10. Every result resolves through an API or audit query to the frozen review scope,
   canonical referent, classification assertion, profile and rule version, authority
   document and edition, normalized candidate assertions, source artifacts, and line
   spans.
11. SQL/Go evaluation and generated SHACL evaluation run against the same conformance
   fixtures and return identical result categories and rule IDs.

Performance thresholds are not ontology semantics. The Phase 4 ADR must establish a
representative corpus, baseline p50/p95 latency, and an explicit allowable regression
before performance becomes a release gate.

## 15. Open Decisions for Follow-Up ADRs

1. Physical schema and typed-reference representation for assertions and semantic links.
2. Whether object classification is stored as a specialized assertion table or in the
   general assertion model.
3. Ontology release workflow, ownership, approval, and immutable IRI policy.
4. Domain-specific precedence-policy vocabulary and authorization when several
   authorities or jurisdictions apply. The baseline behavior remains Section 10.1:
   unresolved conflicts are `indeterminate`.
5. Conflict and supersession semantics among profile rules and source assertions.
6. Confidence thresholds and human-review requirements for topic-term mappings.
7. Identity criteria for scene occurrences and process instances.
8. Backfill strategy for existing artifacts and category paths.
9. Initial pump domain module, competency questions, and authoritative source selection.

## 16. References

[1] `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md`

[2] `KnowledgeStore/doc-repo/adrs/202607/2026070101-adr-object-centric-design.md`

[3] `KnowledgeStore/doc-repo/adrs/202607/2026070701-adr-object-reconciliation-ambiguous-tie-resolution.md`

[4] `KnowledgeStore/doc-repo/research/202607/2026072302-rsch-object-centric-ontology.md`

[5] `KnowledgeStore/Capsules/coding-capsules/doc-processor/generate-summary-spec.md`

[6] `KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-semantic-projection-spec.md`

[7] `KnowledgeStore/Capsules/coding-capsules/doc-processor/generate-topic-spec.md`

[8] `KnowledgeStore/Capsules/coding-capsules/doc-processor/generate-scene-blocks-spec.md`
