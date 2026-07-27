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
8. Create active ontology content through a governed candidate, change-set, validation,
   approval, module, and immutable-release lifecycle.
9. Associate artifacts through an idempotent candidate-resolution pipeline that persists
   each accepted relationship in exactly one authoritative owner store before building
   graph or search projections.

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
8. Define how artifact discoveries become reviewable ontology candidates without
   automatically becoming governed semantics.
9. Make ontology creation, artifact association, release, projection, retry, and
   supersession observable and reproducible.

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
| Topic "pump maintenance" | Yes, as topic | No | Candidate concept term or active concept term included in a module release | `about_term` after association review |
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

An artifact-semantic link is an authoritative accepted relationship, not a candidate
queue row. Before acceptance, `SemanticDecisionCandidate` owns the
`candidate|in_review|deferred|rejected` lifecycle and all considered targets. On
acceptance, the authoritative artifact-semantic link is created. Each authoritative link
must record:

- source artifact type and ID;
- target reference type and ID;
- relation kind;
- extraction or decision method;
- source line spans or other evidence;
- confidence;
- status: accepted or superseded;
- processor/model/prompt or human provenance;
- creation and modification times.

Search-only similarity remains a `SemanticDecisionCandidate` and must not create an
authoritative semantic link unless a separate decision process accepts it.

Derived projections must carry the authoritative source record ID and may not be edited
independently. Rebuilding a projection must not delete or replace its authoritative
record. If projected and authoritative values disagree, the authoritative store wins,
the projection is marked stale, and repair is queued and logged.

## 9. Ontology Authoring and Release Lifecycle

### 9.1 Creation Model

SemOS shall use a hybrid ontology-creation model:

```text
top-down governance
  authoritative standards + domain experts + imported ontologies
    -> governed terms, axioms, modules, profiles, and releases

bottom-up discovery
  artifacts + processors + reviewers + users
    -> candidates and source assertions
      -> reconciliation, validation, and governed promotion
```

Bottom-up discovery is necessary because documents reveal vocabulary, aliases,
relationships, and requirements that the governed ontology may not yet represent.
However, artifact frequency, model confidence, or retrieval similarity must not activate
ontology meaning or normative requirements automatically.

The creation authority depends on the object being created:

| Ontology object | Permitted sources | Activation authority |
|---|---|---|
| Ontology term | Manual authoring, approved import, authoritative extraction, artifact-discovered candidate | Curator approval; activation only through an ontology-module release |
| Term label or mapping | Import, artifact aliases, curator, reconciliation process | Curator approval; exact mappings require explicit approval; activation only through a module release |
| Ontology axiom | Domain modeling, approved import, authoritative source | Curator approval and validation; activation only through a module release |
| Semantic assertion | Artifact extraction, import, reviewer, or human statement | Assertion policy or adjudicator accepts that the source made the claim |
| Ontology profile rule | Authoritative standard, regulation, contract, or organizational policy | Profile-owner approval; activation only through a module release |
| Domain module | Curated set of terms, axioms, mappings, profiles, dependencies, and fixtures | Module-maintainer approval; release approver activates the module release |
| Ontology-module release | One validated module version plus pinned dependency releases | Release approver |

An LLM may extract, normalize, recommend, compare, or draft any candidate. It may not be
the sole authority that activates an ontology term, axiom, exact mapping, normative
profile rule, or release.

### 9.2 Authoring Roles

The logical governance roles are:

| Role | Responsibility |
|---|---|
| Candidate producer | Processor, importer, reviewer, or user that proposes a change with evidence. |
| Domain curator | Defines and reconciles terms, labels, mappings, and axioms within a module. |
| Assertion adjudicator | Reviews ambiguous or policy-gated assertion normalization and evidence. |
| Profile owner | Converts authoritative requirements into scoped, testable profile rules. |
| Module maintainer | Owns module boundaries, dependencies, validation, and change sets. |
| Release approver | Authorizes immutable ontology-module releases for production use. |
| System operator | Runs imports, validations, projections, backfills, and rollback procedures without changing semantic meaning. |

A deployment may assign several roles to one person, but every transition must retain the
acting role and actor. Production governance should support separation of proposal and
approval for high-impact axioms, exact mappings, and normative profile rules.

### 9.3 Candidate, Decision, and Change-Set Contracts

Governed ontology content and operational semantic decisions have different activation
semantics and therefore use separate records and state machines.

Suggested logical records are:

```text
OntologyCandidate
  candidate_id
  candidate_kind             term | label | mapping | axiom |
                             profile | profile_rule | module_change
  proposed_payload
  proposed_module_id
  source_type
  source_ref
  source_line_spans
  discovery_method
  confidence
  fingerprint
  candidate_matches
  status
  proposed_by
  created_at
  updated_at

SemanticDecisionCandidate
  decision_candidate_id
  candidate_kind             assertion | artifact_association
  logical_identity_key
  payload_revision
  normalized_payload
  source_artifact_type
  source_artifact_id
  source_evidence_lineage
  target_candidates
  discovery_method
  confidence
  dependency_fingerprint
  status
  decision_reason
  decided_by
  created_at
  updated_at

OntologyChangeSet
  change_set_id
  target_module_id
  base_release_id
  ontology_candidate_ids
  rationale
  compatibility_impact
  validation_status
  review_status
  reviewed_by
  approved_by
  created_at
  approved_at
```

The ontology-candidate fingerprint is a deterministic identity over the normalized
proposal, source, and intended module. The semantic decision's
`logical_identity_key` identifies the stable evidence/relationship independent of a
processor or decision revision; `payload_revision` and `dependency_fingerprint` detect
meaningful changes. Together they prevent duplicate review work while preserving
revision history.

#### Governed Ontology-Content State Machine

Terms, labels, mappings, axioms, profiles, profile rules, and module changes use:

```text
discovered -> draft -> in_review -> approved -> included_in_release
                    \-> rejected
                    \-> deferred
deferred --dependency changed--> draft
approved --withdrawn/replaced--> superseded
included_in_release --later replacement--> superseded
```

Rules:

- `discovered` means a source or processor proposed a possible ontology change.
- `draft` may be edited and enriched without affecting production semantics.
- `in_review` freezes the reviewed payload; later edits create a new revision.
- `approved` authorizes inclusion in a change set but is not production-active.
- `included_in_release` identifies the immutable module release that activated the item.
- `rejected` is terminal for that candidate revision and retains the rejection reason.
- `deferred` is non-terminal and requires a blocker plus dependency fingerprint.
- `superseded` is terminal for that revision and points to its replacement.
- A rejected proposal may be reconsidered only as a new candidate revision with changed
  evidence or semantics.

#### Operational Semantic-Decision State Machine

Assertions and artifact associations use:

```text
candidate -> in_review -> accepted
                      \-> rejected
                      \-> deferred
candidate ------------> accepted          approved deterministic policy
deferred --dependency changed--> candidate
accepted --decision-relevant revision--> superseded
accepted assertion --last evidence lost--> unsupported
unsupported --qualifying evidence restored--> accepted
```

Rules:

- `candidate` and `in_review` are non-terminal.
- `deferred` and assertion-only `unsupported` are non-terminal and ineligible for
  normative use.
- `accepted` is decision-complete but may transition to `unsupported` after evidence
  loss or to `superseded` after a decision-relevant revision.
- `rejected` and `superseded` are terminal for a specific payload revision.
- `rejected` may be reconsidered only through a new payload revision.
- `accepted` means the normalized relationship or source claim passed an approved
  decision policy; it is not an ontology release.
- `unsupported` preserves a formerly accepted assertion after its final qualifying
  evidence is removed and records the evidence-loss event.
- Restoration reuses the logical identity, adds a new payload/evidence revision, returns
  the assertion to `accepted`, and records the transition in the audit log.

Resolution labels such as `matched` or `new_target_candidate` are outcomes recorded in
the decision payload, not lifecycle statuses. Ambiguity is a `deferred` decision with
reason `ambiguous_targets`. Retry is permitted only when the dependency fingerprint
changes.

### 9.4 Ontology-Term Creation

Terms may be created through four channels:

1. **Manual domain authoring.** A curator defines the term, labels, scope, and intended
   semantics.
2. **Governed import.** An importer proposes terms and mappings from an external ontology
   release while retaining source IRIs, licenses, versions, and checksums.
3. **Authoritative extraction.** A processor drafts terms from standards or other
   controlled sources with line-level evidence.
4. **Artifact discovery.** Topics, categories, entities, metrics, provisions, summaries,
   or semantic projections propose candidate vocabulary and aliases.

All four channels use the same reconciliation and release gates:

```text
candidate
  -> normalize labels and proposed definition
  -> search existing terms and mappings
  -> classify as duplicate, mapping, extension, or new term
  -> validate term kind, namespace, definition, and module ownership
  -> review mappings and axioms
  -> include in an approved change set
  -> activate through an immutable module release
```

Candidate matching must consider definitions, term kind, domain/range, quantity kind,
external identifiers, language-tagged labels, module scope, and existing mappings.
Lexical or vector similarity alone cannot establish exact equivalence.

An activated term receives an immutable `term_id` and stable IRI. Labels, mappings, and
definitions are release-versioned. If a change materially alters the intended referents
or meaning, create a replacement term and deprecate the old term rather than silently
redefining it.

### 9.5 Semantic-Assertion Creation

Semantic assertions are created more frequently than governed ontology terms. Typical
sources include:

- metrics normalized into property/value assertions;
- provisions normalized into requirements, permissions, or prohibitions;
- inventory items normalized into classification, composition, or quantity assertions;
- entity relations normalized into domain claims;
- scene blocks decomposed into occurrence, participant, action, state, cause, and outcome
  assertions;
- imported datasets or human-authored statements.

The assertion workflow is:

```text
source artifact or statement
  -> candidate assertion
  -> resolve subject and object references
  -> map predicate, property, quantity kind, unit, role, and assertion kind
  -> normalize modality, polarity, conditions, and time
  -> attach one or more evidence records
  -> validate required fields and ontology constraints
  -> accept, reject, defer, or supersede
```

Assertion acceptance means:

> SemOS accepts that the identified source made this normalized claim with the recorded
> evidence and qualifications.

It does not mean that the claim is universally true, current, authoritative, or
applicable to every review. Truth assessment, authority precedence, conflict resolution,
and applicability remain reviewer/profile responsibilities.

Assertions created by deterministic mappings may be accepted automatically when an
independently approved deterministic policy and complete evidence permit it. The policy
must evaluate source type, mapping status, required fields, evidence completeness,
ontology constraints, and configured risk class. An LLM's confidence, agreement, or
structured output is never sufficient by itself for automatic acceptance.

LLM-normalized, ambiguous, or high-impact assertions remain candidates unless an
approved deterministic policy independently verifies every acceptance condition or an
authorized human accepts them. The LLM output, model confidence, and rationale remain
provenance inputs, not acceptance authority.

### 9.6 Profile and Rule Creation

Profiles govern "what should be" and therefore require the strongest source and approval
controls.

Profile rules may originate from:

- standards and specifications;
- laws and regulations;
- contracts;
- manufacturer or organizational policies;
- approved internal engineering requirements.

Ordinary descriptive artifacts, topic frequency, search similarity, and model-generated
generalizations may suggest a profile candidate but cannot serve as sole normative
authority.

The profile workflow is:

```text
authoritative source and edition
  -> extract candidate provisions and requirements
  -> identify target classes and applicability scope
  -> normalize required assertion patterns and rule quantifiers
  -> attach authority, jurisdiction, effective dates, provisions, and line spans
  -> choose closed/open-world dimensions
  -> create positive, negative, boundary, and conflict fixtures
  -> validate operational and SHACL-equivalent behavior
  -> profile-owner review
  -> immutable profile version
  -> inclusion in an ontology-module release
```

Every immutable profile version must include:

- an immutable profile ID and version;
- target classes and applicability rules;
- authority and source provenance;
- effective interval and jurisdiction;
- rule definitions and evaluation quantifiers;
- precedence-policy references;
- closed/open-world declarations;
- expected-result fixtures;
- dependencies on ontology-module releases;
- approval and release metadata.

A draft profile or rule may support exploratory analysis but cannot produce normative
`missing`, `nonconforming`, or compliance findings.

Profile versions do not have an independent production-active pointer. A profile version
becomes eligible for production selection only when included in an immutable ontology
module release. The active module-release pointer is the single activation authority for
its terms, axioms, mappings, profiles, and profile rules. A historical review may pin an
older released module and a profile version contained by it explicitly; an unreleased
profile version cannot be selected for normative review.

### 9.7 Domain-Module Creation

A domain module is a governed package and ownership boundary, not another semantic node.
Its release manifest should contain:

```text
OntologyModuleRelease
  module_id
  module_version
  title
  scope
  owner
  term_ids_and_versions
  axiom_ids_and_versions
  mapping_ids_and_versions
  profile_ids_and_versions
  dependency_releases
  validation_fixtures
  compatibility_notes
  content_checksum
  approval_metadata
  released_at
```

For example:

```text
pump-module
  depends_on:
    core-object-module
    quantity-and-unit-module
    document-authority-module
  contains:
    pump classes and roles
    pump properties and quantity kinds
    pump-specific axioms and mappings
    pump review profiles
    conformance fixtures
```

Modules should be small enough to have clear ownership and competency questions.
Dependencies must be explicit and acyclic. A module may reference shared terms from a
dependency but must not copy or silently redefine them.

### 9.8 Validation and Release

Before release, a change set must pass:

- schema and required-field validation;
- duplicate and identity checks;
- dangling-reference and dependency checks;
- logical consistency checks for axioms and mappings;
- profile-rule conflict and quantifier checks;
- positive, negative, boundary, and regression fixtures;
- operational SQL/Go versus exported SHACL parity where applicable;
- backward-compatibility and deprecation checks;
- provenance, authority, license, and approval checks;
- deterministic serialization and content checksum generation.

Releases are immutable. Corrections create a new release. Production review scopes pin
exact module releases and the profile versions contained by them so historical results
remain reproducible.

Activation should be atomic: either all approved items and dependencies in a release
become available together, or none do. Rollback changes the active release pointer; it
does not delete the rejected release or its audit history.

The ontology-module release is the only activatable release unit. Immutable profile
versions and other release items are constituents, not independently activated releases.
A profile-only rollout uses a small module release containing that profile change and its
dependencies.

### 9.9 Deprecation and Change Control

Released records are never edited in place in a way that changes their meaning.

- Labels may be added through a new release.
- Compatible metadata corrections require a new release and audit entry.
- Material semantic changes require a replacement term, axiom, rule, profile, or module
  version.
- Deprecated records retain replacement pointers and remain resolvable for historical
  assertions and reviews.
- Rejected and superseded candidates remain searchable to prevent repeated proposals.
- A release-impact report must identify affected assertions, profiles, review scopes,
  projections, APIs, and fixtures before activation.

## 10. Artifact-to-Ontology Association Pipeline

### 10.1 Pipeline Overview

Artifact association is a post-persistence semantic-indexing workflow. It may run as part
of document processing or asynchronously after all required artifacts for a record are
available.

```text
1. Persist source artifact and evidence
2. Generate association candidates
3. Resolve candidate targets
4. Validate semantics and applicability
5. Adjudicate policy-gated candidates
6. Persist in the authoritative owner store
7. Build derived graph/search projections
8. Audit outcomes and schedule deferred retries
```

Each step must be independently idempotent. A failure in semantic association must not
delete the persisted source artifact.

### 10.2 Step 1: Persist Artifact and Evidence

The artifact must exist before ontology association begins. Persistence supplies:

- canonical artifact type and ID;
- input record and extraction run;
- source document identity;
- source line spans and evidence quotes;
- processor, model, prompt, and configuration versions;
- artifact-specific structured fields;
- artifact lifecycle and reprocessing identity.

Associations must reference persisted artifact IDs. Processor-local indexes, sequence
positions, labels, or generated text alone are not durable association keys.

### 10.3 Step 2: Generate Candidates

Candidate generation methods are:

| Method | Use | Initial status |
|---|---|---|
| `explicit_structured` | Processor emitted a structured object, term, assertion, or occurrence reference with evidence. | `candidate`; eligible for an approved automatic policy |
| `deterministic_source_span` | Existing accepted artifact/evidence on the same normalized source spans implies a candidate association. | Candidate |
| `released_mapping` | An ontology mapping included in an active module release deterministically maps a normalized field to a governed term. | `candidate`; eligible for an approved automatic policy |
| `lexical_candidate` | Names, labels, aliases, acronyms, or definitions produce possible targets. | Candidate only |
| `semantic_candidate` | Embedding or hybrid similarity produces possible targets. | Candidate only |
| `structural_candidate` | Document hierarchy, category path, summary tree, or scene structure suggests a relation. | Candidate only |
| `human` | Authorized user creates or approves an association with rationale. | Accepted when authorization permits |

Every candidate must include its method, evidence, confidence, target candidates,
fingerprint, and decision status. Candidate generation must not write directly to a
derived graph projection.

### 10.4 Step 3: Resolve Targets

Resolution depends on target type:

- referent candidates reconcile through `kb.artifact_objects` and
  `kb.object_nodes`;
- term candidates reconcile through ontology-term labels, definitions, mappings, kinds,
  namespaces, and module scope;
- assertion candidates resolve typed subject/object references and governed predicate,
  quantity, unit, role, and assertion-kind terms;
- occurrence candidates resolve identity scope, event identifiers, participants, time,
  location, and source context;
- profile candidates resolve an immutable profile ID/version only within a review-scope
  selection workflow.

Resolution outcomes are:

```text
matched | new_target_candidate | rejected | deferred
```

`new_target_candidate` may propose a new referent or ontology term, but it does not
activate one without the corresponding identity or authoring workflow. Ambiguous target
sets produce lifecycle status `deferred` with reason `ambiguous_targets`; `matched` and
`new_target_candidate` are resolution outcomes, not lifecycle statuses.

### 10.5 Step 4: Validate Semantics

Validation must check:

- artifact and target existence;
- permitted relation for the source and target types;
- source-span and evidence consistency;
- object identity scope and role compatibility;
- ontology term kind, namespace, and module compatibility;
- assertion endpoint, datatype, quantity, unit, modality, and qualifier validity;
- occurrence identity evidence;
- profile authority and version status;
- duplicate and mutually exclusive associations;
- policy thresholds and required review level.

A candidate that fails validation is retained as `rejected` with machine-readable reasons.
Missing context produces `deferred`, not an invented target.

### 10.6 Step 5: Adjudicate

Adjudication may be deterministic, LLM-assisted, or human:

- deterministic policy may accept exact, fully constrained mappings;
- an LLM may compare candidates and produce a structured recommendation with confidence
  and rationale;
- a human adjudicator may select, correct, reject, or defer;
- high-impact term, exact-mapping, axiom, and profile candidates always continue through
  the authoring/release lifecycle in Section 9.

Adjudication must not collapse candidate provenance. The accepted result retains all
considered target IDs, scores, methods, model/prompt versions, reviewer actions, and
rejection reasons.

### 10.7 Step 6: Persist Authoritative Associations

Accepted relationships are persisted only in the owner identified by Section 8.5:

| Association | Authoritative persistence |
|---|---|
| Artifact mentions or denotes referent | `kb.artifact_objects` |
| Artifact is about ontology term | artifact-semantic link with `about_term` |
| Artifact supports or contradicts assertion | assertion-evidence record |
| Referent classified under term | accepted classification assertion |
| Scene block describes occurrence | artifact-semantic link with `describes_occurrence` |
| Review governed by profile | immutable review-scope selection record |

Each association has:

- a stable `logical_association_key` over authoritative relation kind, stable source
  artifact identity, normalized target identity, evidence role, source scope, and
  evidence lineage; and
- a separate payload revision and decision revision.

Reprocessing unchanged normalized evidence under a new extraction revision reuses the
logical association, records the new artifact/evidence revision as `last_seen`, and does
not create duplicate review work. If decision-relevant payload changes:

- a non-terminal candidate is updated with a new payload revision;
- an accepted or rejected revision is preserved and superseded by a new candidate
  revision;
- unchanged accepted decisions remain accepted;
- changed target identity or relation kind creates a different logical association.

### 10.8 Step 7: Build Derived Projections

After authoritative persistence, SemOS may project associations into:

- `kb.artifact_connections` for traversal;
- `kb.search_artifacts.semantic_payload` for retrieval and filtering;
- object-node convenience classifications;
- materialized reviewer indexes;
- RDF/OWL/SKOS/SHACL exports.

Every projection must reference its authoritative record and projection version.
Projection repair is deterministic from the authoritative store. Users and processors
must not edit a projection as a substitute for changing the authoritative association.

### 10.9 Step 8: Audit and Retry

Each association run must report:

- artifacts examined;
- candidates generated by method;
- resolution outcomes (`matched`, `new_target_candidate`, rejected, deferred);
- lifecycle counts (`candidate`, `in_review`, `accepted`, `rejected`, `deferred`,
  `unsupported`, and `superseded`);
- newly proposed referents, terms, assertions, and module changes;
- deterministic versus LLM versus human decisions;
- stale projections detected and repaired;
- per-stage timing and errors.

Deferred candidates may be retried only when their dependency fingerprint changes, such
as new target candidates, ontology release, evidence, identity resolution, or policy
version. A schedule alone must not repeatedly invoke an unchanged LLM decision.

### 10.10 Artifact-Family Association Matrix

| Artifact family | Referent owner | Term-association owner | Assertion/evidence owner | Special rules |
|---|---|---|---|---|
| Metric | `kb.artifact_objects` for measured object/component/system mentions | Governed term references inside the semantic assertion | Semantic assertion plus assertion evidence | `about_term` only if the metric artifact as a whole is topically about another concept |
| Provision | `kb.artifact_objects` for regulated object/actor/authority/document mentions | Governed predicate, modality, role, and assertion-kind references inside the assertion | Required/permitted/prohibited assertion plus evidence | Authority and applicability are mandatory |
| Inventory item | `kb.artifact_objects` for item/component/system/supplier mentions | Classification or property terms inside accepted assertions | Classification/composition/quantity/catalog assertions plus evidence | Item identity and class remain distinct |
| Entity | `kb.artifact_objects` for selected concrete referents | `about_term` only for artifact-level concept aboutness; class/property use accepted assertions | Normalized entity-relation assertion plus evidence | Open-vocabulary entity type never activates a term |
| Summary | `kb.artifact_objects` only for grounded referent mentions | Artifact-semantic link `about_term` | Existing assertion-evidence link only when spans support the assertion | Inherited links remain candidates with lineage |
| Semantic projection | `kb.artifact_objects` only for grounded referent mentions | Artifact-semantic link `about_term` | Normally none without explicit source evidence | Category/keyword similarity remains a candidate |
| Topic | `kb.artifact_objects` only for explicitly discussed specific referents | Artifact-semantic link `about_term` | Normally none; may be evidence for a separate ontology-mapping candidate | Compound/broad topics may map to several or no terms |
| Scene block | `kb.artifact_objects` for actors/resources; `describes_occurrence` link for occurrence | `about_term` for artifact-level process/failure concepts; assertion fields for predicate/role terms | Occurrence/participant/action/state/cause/outcome assertions plus evidence | Similar scenes are not the same occurrence |

`kb.ontology_mappings` is reserved for governed vocabulary alignment:

```text
local ontology term -> external ontology IRI
local ontology term -> another governed ontology term
```

An artifact-to-term relation is never an ontology mapping. An artifact may provide
evidence for an `OntologyCandidate(candidate_kind = mapping)`, but the mapping is owned
by `kb.ontology_mappings` and becomes active only through a module release.

### 10.11 Inheritance and Propagation Rules

Association inheritance is allowed only as candidate generation:

- a summary may inherit candidates from its child summaries or source spans;
- a semantic projection may inherit candidates from its chunk;
- a topic may inherit candidates from its source lines and category mappings;
- a scene may inherit actor/resource candidates from grounded entity artifacts.

Inherited candidates must retain the originating artifact/evidence IDs and confidence
path. Confidence must not increase merely because several derived artifacts repeat the
same underlying evidence. Multiple artifacts derived from the same source span count as
one independent evidence lineage unless another source supports the association.

An accepted association may propagate only through an approved deterministic rule. For
example, an exact term mapping included in the active module release may normalize a
metric property. A close or related mapping may generate a candidate but cannot
propagate an accepted classification or profile rule.

### 10.12 Reprocessing, Deletion, and Supersession

On artifact reprocessing:

1. identify the previous extraction revision;
2. preserve released ontology records and independently accepted assertions;
3. supersede processor-owned candidates and evidence no longer supported by the new
   artifact revision;
4. re-evaluate authoritative associations whose evidence fingerprint changed;
5. leave unchanged decisions untouched;
6. rebuild affected projections;
7. log added, retained, superseded, rejected, and deferred outcomes.

Deleting an input record may cascade document-scoped artifacts, candidates, and evidence
according to existing retention policy. It must not delete released terms, modules,
profiles, or assertions supported by other evidence. Assertions that lose their last
qualifying evidence record transition from `accepted` to `unsupported`, retain their
normalized payload and complete audit history indefinitely by default, and become
ineligible for normative review. The transition records the deleted evidence IDs, actor
or cascade source, time, and reason.

A qualifying human-authored assertion provenance record counts as evidence and prevents
the transition while it remains active. If qualifying evidence with the same logical
lineage is restored, the assertion returns to `accepted`, links the new evidence revision,
and records a restoration audit event. Hard-deletion and finite-retention policy require
a follow-up ADR; until then, `unsupported` assertions are not physically deleted.

## 11. Artifact-Family Decisions

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

### 11.1 Summaries

A summary's identity depends on document version, chunking, grouping, processor version,
prompt, and model. It is therefore not a stable cross-document referent.

Summaries may:

- mention several canonical referents;
- be about several ontology concepts;
- support or summarize several assertions;
- inherit candidate links from grounded child source spans.

Inherited links must remain distinguishable from explicit extraction. Higher-level
summaries must not amplify a weak child association into an accepted semantic fact.

### 11.2 Semantic Projections

Semantic projections are one-to-one with processing chunks and serve as search
enrichment through descriptive names, keywords, category paths, and vectors. They are
not canonical semantic objects.

Category paths are retrieval facets. They may generate candidate ontology-term mappings,
but they must not automatically create class axioms, identity, or profile rules.

### 11.3 Topics

Topics are document-scoped descriptions of what a span discusses. A topic may map to:

- one or more governed SKOS-like concepts;
- one or more ontology classes or properties after review;
- one or more canonical referents when the topic concerns specific instances;
- no canonical term when it is too broad, compound, transient, or ambiguous.

SemOS shall not create a separate `Canonical Topics` registry. Canonical conceptual
meaning belongs in `kb.ontology_terms` and concept schemes. Extracted topics remain
evidence for `about_term` association candidates. When a topic exposes a possible
alignment between two ontology vocabularies, it may separately support an ontology
mapping candidate; the topic itself is never an endpoint of `kb.ontology_mappings`.

### 11.4 Scene Blocks

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

## 12. "What Should Be" Review Workflow

### 12.1 Review Scope and Profile Selection

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

### 12.2 Pump Example

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

### 12.3 Finding Decision Procedure

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

### 12.4 Expected Result Categories

A reviewer must distinguish:

- `satisfied`: qualifying evidence satisfies the applicable rule;
- `missing`: a closed-world profile requires an assertion and none is present;
- `conflicting`: relevant assertions disagree after normalization;
- `nonconforming`: an assertion violates a constraint, unit, range, or prohibition;
- `inapplicable`: the rule's stated conditions do not apply;
- `indeterminate`: classification, applicability, identity, or evidence is insufficient.

Absence may be reported as `missing` only within an explicitly selected closed-world
profile. Outside such a profile, absence means unknown.

## 13. Relationship to Existing Stores

### 13.1 `kb.artifact_objects`

Continue using this table as the source of truth for extracted object mentions. Extend
producer coverage only when an artifact contains grounded object evidence. Do not use it
as the hybrid-search registry or as a canonical-artifact table.

### 13.2 `kb.object_nodes`

Continue using this table as the stable referent registry. Do not store mutable metric
values, normative requirements, or generated summaries directly on object nodes.

### 13.3 `kb.search_artifacts`

Continue using this table as the normalized lexical/vector retrieval surface. Search
results are candidates for navigation or adjudication, not accepted identity or ontology
decisions.

### 13.4 `kb.artifact_connections`

Continue using this table for line-overlap, structural, category, manual, object, and
projected semantic traversal edges. Authoritative qualified assertions and profile rules
must have independent stores and lifecycles. Selected assertions may be projected into
`kb.artifact_connections` for backward-compatible traversal.

### 13.5 Current-State Verification

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

## 14. Alternatives Considered

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

## 15. Phased Delivery

### Phase 1. Correct Boundaries and Identifiers

- Correct documentation that describes artifact-object cardinality as one-to-one.
- Document `kb.search_artifacts`, `kb.artifact_objects`, and
  `kb.artifact_connections` responsibilities consistently.
- Rename or deprecate `kb.scene_objects.object_id` as `scene_block_id`.
- Define typed reference and semantic-link contracts.
- Add provenance and status requirements for semantic decisions.

### Phase 2. Ontology Terms and Classification

- Implement ontology candidates, deterministic fingerprints, change sets, review states,
  governance roles, validation, module manifests, and immutable releases.
- Implement governed ontology terms, labels, mappings, axioms, and releases.
- Add `ontological_level` and identity scope to canonical referents.
- Add explicit object classification and role assertions.
- Map selected topic/category candidates to governed terms through reviewable workflows.

### Phase 3. Qualified Assertions and Evidence

- Implement the artifact-association pipeline, target-specific reconciliation,
  authoritative association stores, audit outcomes, and projection repair.
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

## 16. Acceptance Criteria

### 16.1 Specification Acceptance

This architecture specification is ready for follow-up ADRs when:

1. Every artifact family in Section 11 has an explicit canonicalization decision.
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
7. Sections 9 and 10 define creation authority, lifecycle states, release boundaries,
   association stages, target-specific resolution, authoritative persistence, and
   reprocessing behavior.
8. Physical schema, concrete role assignments, authorization controls, release tooling,
   and domain-module contents remain explicitly assigned to follow-up ADRs rather than
   implied by this specification.

### 16.2 Phase 1-3 Implementation Acceptance

The identity, term, and assertion foundations are complete when automated integration
tests demonstrate:

1. One artifact persists two object mentions with different roles and each reconciles
   independently.
2. Executable tests realize every row of the specification's type/concept decision table.
3. Creating or updating a search-similarity result creates no object node, exact ontology
   mapping, accepted semantic link, or assertion.
4. Reprocessing a document replaces processor-owned artifacts and derived projections
   while preserving immutable term IDs, released module items, accepted assertions, and
   canonical object IDs unless an audited reconciliation action changes them.
5. Two conflicting source assertions remain separately queryable with independent
   evidence and provenance.
6. Every graph projection references its authoritative source record; a deliberately
   corrupted projection is detected as stale and repaired from that source.
7. Migration up/down tests and backfill fixtures report ambiguous records without
   assigning arbitrary identities or mappings.

### 16.3 Phase 2-3 Authoring and Association Acceptance

The foundational ontology authoring and artifact-association workflows are complete when
automated integration tests demonstrate:

1. Reprocessing an identical governed ontology proposal reuses its
   `OntologyCandidate.fingerprint` and does not create duplicate review work.
2. Reprocessing unchanged semantic evidence reuses its
   `SemanticDecisionCandidate.logical_identity_key`; an unchanged payload records
   `last_seen`, while a decision-relevant change creates a payload revision and
   supersedes any completed prior revision.
3. Candidate transitions enforce both Section 9.3 state machines; rejected candidates
   retain reasons, deferred candidates retry only after dependency changes, and approved
   ontology candidates remain inactive until included in a module release.
4. An LLM-only recommendation or confidence threshold cannot activate a term, axiom,
   exact mapping, module, or release, and cannot accept an assertion or artifact
   association.
5. Activating a module release is atomic, pins dependency releases, records a checksum,
   and can be rolled back without deleting release history.
6. A material term-definition change creates a replacement term and deprecation link
   rather than mutating the released term's meaning.
7. An approved change set containing a term, label, exact mapping, and axiom activates
   all items together through one module release; a deliberately
   failed validation or activation leaves the previous active release unchanged.
8. Accepting an assertion through an approved deterministic policy records that its
   source made the normalized claim without
   promoting the assertion into a universal fact or profile requirement.
9. Lexical, semantic, and structural associations remain candidates until an
   approved decision path accepts them.
10. Accepted associations persist in the owner specified by Sections 8.5 and 10.7; graph
    and search records are projections that reference that authoritative record.
11. Reprocessing changed evidence supersedes processor-owned candidates no longer
    supported by evidence, preserves unchanged decisions, and rebuilds only affected
    projections.
12. A deferred candidate with an unchanged dependency fingerprint does not repeat an LLM
    adjudication; a changed ontology release or evidence fingerprint makes it eligible.
13. A transient resolution/adjudication failure leaves the candidate non-terminal and can
    resume idempotently without duplicating decisions.
14. A partial projection failure leaves the authoritative association committed, marks
    the projection stale, and repairs it idempotently on retry.
15. Deleting one input removes its document-scoped candidates and evidence without
    deleting released ontology content or assertions that retain other evidence.
16. Deleting an assertion's final qualifying evidence moves it to `unsupported` and
    excludes it from normative review; restoring qualifying evidence returns the same
    logical assertion to `accepted` with a complete audit trail.
17. Association-run telemetry reconciles examined artifacts across every resolution
    outcome and lifecycle status without unaccounted candidates.

### 16.4 Phase 4 Pump-Review Acceptance

The first "what should be" implementation is complete when a fixed pump fixture and
versioned profile produce these deterministic results:

1. An LLM-only recommendation or confidence threshold cannot activate a profile or
   profile rule.
2. A draft or artifact-inferred profile rule cannot produce a normative finding.
3. An approved profile version and its rules become selectable only when their containing
   module release is activated; a deliberately failed module activation leaves the
   previous profile version active.
4. A complete P-101 document with all required, correctly normalized assertions returns
   `satisfied` for every rule.
5. Removing rated flow from the same fixture returns `missing` when the metric dimension
   is closed and `indeterminate` when it is open.
6. Supplying an incompatible unit dimension or out-of-range value returns
   `nonconforming`.
7. Supplying two applicable, incompatible pressure assertions without a resolving
   precedence rule returns `conflicting`.
8. Under `exists_conforming`, one conforming and one nonconforming assertion satisfies the
   aggregate rule and emits a separate assertion-level nonconformance; the same evidence
   under `all_conforming` returns aggregate `nonconforming`.
9. A `count_conforming` fixture exercises minimum and maximum cardinality boundaries.
10. Two incompatible applicable profile rules without a resolving precedence policy emit
   `profile_rule_conflict = indeterminate`, skip only their shared semantic slot, and do
   not block unrelated rules.
11. Removing the pump classification, applicable jurisdiction, or profile version returns
   `indeterminate`.
12. A conditionally irrelevant rule returns `inapplicable`.
13. Every result resolves through an API or audit query to the frozen review scope,
   canonical referent, classification assertion, profile and rule version, authority
   document and edition, normalized candidate assertions, source artifacts, and line
   spans.
14. SQL/Go evaluation and generated SHACL evaluation run against the same conformance
   fixtures and return identical result categories and rule IDs.

Performance thresholds are not ontology semantics. The Phase 4 ADR must establish a
representative corpus, baseline p50/p95 latency, and an explicit allowable regression
before performance becomes a release gate.

### 16.5 Phase 5 Additional-Artifact Acceptance

The additional artifact associations are complete when:

1. Summary and semantic-projection inherited links retain the originating evidence
   lineage and never gain confidence merely through repeated derivation.
2. Topic `about_term` links are persisted only as artifact-semantic links; a topic can
   support but never become an endpoint of an ontology mapping.
3. Topic `SemanticDecisionCandidate` revisions exercise candidate, accepted, rejected,
   deferred, and superseded decisions without changing the extracted topic artifact;
   only accepted decisions create authoritative `about_term` links.
4. Compound and ambiguous topics can retain several candidates or no accepted
   `about_term` association without creating a synthetic canonical topic.
5. Scene actors/resources resolve through `kb.artifact_objects`, occurrence identity
   resolves independently, and `describes_occurrence` remains the sole owner of the
   scene-to-occurrence relation.
6. Similar scene blocks do not merge distinct occurrences without sufficient identity
   evidence.
7. The Phase 5 ADR defines a labeled evaluation corpus and per-method precision threshold
   before enabling any automatic acceptance; below-threshold methods remain
   candidate-only.
8. Reprocessing summaries, projections, topics, or scenes supersedes authoritative links
   whose evidence no longer supports them and repairs projections without changing
   released ontology content.

## 17. Open Decisions for Follow-Up ADRs

1. Physical schema and typed-reference representation for assertions and semantic links.
2. Whether object classification is stored as a specialized assertion table or in the
   general assertion model.
3. Concrete governance-role assignments, authorization controls, release tooling, and
   immutable IRI namespace policy. Section 9 defines their required logical behavior.
4. Domain-specific precedence-policy vocabulary and authorization when several
   authorities or jurisdictions apply. The baseline behavior remains Section 12.1:
   unresolved conflicts are `indeterminate`.
5. Conflict and supersession semantics among profile rules and source assertions.
6. Confidence thresholds and human-review requirements for topic-term mappings.
7. Identity criteria for scene occurrences and process instances.
8. Backfill strategy for existing artifacts and category paths.
9. Initial pump domain module, competency questions, and authoritative source selection.
10. Hard-deletion and finite-retention policy for unsupported assertions and rejected or
    superseded candidates. Until decided, Section 10.12 requires indefinite audited
    retention.

## 18. References

[1] `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md`

[2] `KnowledgeStore/doc-repo/adrs/202607/2026070101-adr-object-centric-design.md`

[3] `KnowledgeStore/doc-repo/adrs/202607/2026070701-adr-object-reconciliation-ambiguous-tie-resolution.md`

[4] `KnowledgeStore/doc-repo/research/202607/2026072302-rsch-object-centric-ontology.md`

[5] `KnowledgeStore/Capsules/coding-capsules/doc-processor/generate-summary-spec.md`

[6] `KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-semantic-projection-spec.md`

[7] `KnowledgeStore/Capsules/coding-capsules/doc-processor/generate-topic-spec.md`

[8] `KnowledgeStore/Capsules/coding-capsules/doc-processor/generate-scene-blocks-spec.md`
