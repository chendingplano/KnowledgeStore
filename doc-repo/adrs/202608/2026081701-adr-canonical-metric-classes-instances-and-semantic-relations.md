# ADR 2026081701 — Ontology Object Classes, Normalized Metric Instances, and Semantic Relations

**Date:** 2026-08-17 \
**Status:** Proposed \
**Component:** ChenWeb — ontology terms, class contracts, keyword concepts, semantic assertions, assertion evidence, assertion relations, metric processing, and Review Document \
**Authors:** Chen Ding (with Codex) \
**Related:** ADR `2026072901` (ontology platform and adaptive pipeline), ADR `2026081201` (auto-promoted governed terms), ADR `2026081401` (governed metric vocabulary and Phase D failure reporting), user manual `metric-assertion-semantic-processing-v1.2-en.md` §6.11 \
**Tags:** ontology, object class, object instance, metrics, semantic identity, evidence, evolving schema, lossless processing, autonomous resolution, Review Document

## 1. Change Log

* 2026/08/17, initial proposal after investigating user manual §6.11 and the live implementation.
* 2026/08/17, rewritten to establish explicit occurrence, evidence, instance, and class layers; an
  evolving class contract; canonical claim identity; instance relations; and class-first Review
  Document retrieval.
* 2026/08/18, revised after resolving review Issues 01–15. This revision:
  * decouples stable class identity from evolving class-contract revisions;
  * moves historical term and contract states to append-only revision stores;
  * requires every metric instance to reference an existing or provisional class;
  * removes `kb.semantic_decision_candidates` from the normal metric path;
  * keeps `kb.assertion_evidence` as provenance rather than normalized content;
  * persists raw, malformed, ambiguous, nonconforming, missing, and unknown claims instead of
    dropping or deferring them out of semantic processing;
  * separates class identity, class definition, value, and conformance states;
  * specifies class validation capabilities, class-resolution decisions, claim identities, and
    assertion-relation storage; and
  * defines online and offline duplicate-class reconciliation.

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
                                            kb.ontology_class_contract_revisions
```

The layers have different responsibilities:

| Layer | Responsibility |
|---|---|
| Source occurrence | What document processing extracted, including raw values, source wording, spans, model, prompt, and confidence. |
| Evidence | Why an instance exists and which occurrence supports or contradicts it. Evidence preserves provenance; it is not the normalized value store. |
| Ontology object instance | A source-backed normalized or raw-preserved claim with subject, value state, conditions, modality, validation results, and errors. Multiple occurrences may support one instance. |
| Ontology object class | A stable semantic identity plus an evolving, append-only contract history defining attributes, logical datatypes, constraints, and comparison semantics. |

For metrics, `kb.metrics` is the source-occurrence store and `kb.semantic_assertions` is reused as
the ontology object-instance store. This does not make every semantic assertion a metric. The table
remains generic, and only assertion kinds representing ontology object instances require an
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
  current contract:
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
The class term is carried only in qualifier JSON and does not participate through a typed
`instance_of` relationship.

The current relation table also cannot represent the required relation set, and the association
pipeline does not populate it. Same-class instances therefore remain isolated rows.

### 2.6 Validation failures currently remove knowledge from later processing

Some current normalization and mapping failures stop subsequent semantic processing. This loses a
source-backed metric precisely when the knowledge base most needs to preserve and explain the
problem. A failed mapping may indicate a malformed source, but it may instead reveal an incomplete
mapping table, parser, vocabulary, or class contract.

SemOS must preserve sourced claims without automatically endorsing them as correct. Raw values,
unparsed values, missing values, contract violations, ambiguous class candidates, and conflicting
claims are all knowledge. Consumers—not the ingestion pipeline—decide whether a flagged claim is
suitable for their task.

### 2.7 Review Document is the minimum competency test

Review Document must be able to process a document, find the normalized instance for every metric
occurrence, find its ontology class, retrieve other instances of that class, and compare their
source evidence. Today it primarily discovers peers through lexical/vector similarity, shared
categories, and object anchors.

Similarity is useful for candidate discovery. It cannot guarantee same-class identity or explain
why two artifacts are comparable. If the ontology subsystem cannot support the Review Document
class-to-instance traversal, its most important semantic relationship is missing.

### 2.8 Human design is ideal but cannot be mandatory

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
instances. An ontology object instance is a source-backed normalized or raw-preserved claim that
explicitly instantiates one class; it is not the source occurrence, and multiple occurrences may
support it.

For the metric pilot:

* `kb.ontology_terms`, together with the class-contract history defined in DR2, identifies and
  defines the ontology object class;
* `kb.semantic_assertions` stores metric instances;
* `kb.assertion_evidence` connects instances to source occurrences; and
* `kb.metrics` preserves extraction and document provenance.

The stable generic class reference on an object-instance assertion is:

```text
kb.semantic_assertions.instance_of_term_id
```

It identifies the stable `kb.ontology_terms.term_id`, not a changing contract revision. The name
`parent_term_id` is rejected because instantiation is not taxonomy or containment.
`metric_definition_term_id` is rejected on the generic assertion table because the table also holds
provisions, entities, inventory items, and other families.

`instance_of_term_id` is required for every persisted assertion kind that represents an ontology
object instance. If no existing class resolves, the system creates a provisional `identity_only`
class and associates the instance with it. The column may be null only for assertion kinds that
encode relations or other statements that are not ontology object instances. The database enforces
this conditional invariant by assertion kind.

### 3.2 DR2 — Separate stable class identity from append-only term and contract history

Ontology instances must not be rewritten whenever their class contract evolves. The logical storage
model is:

```text
kb.ontology_terms
  term_id                         # stable, unique class identity
  term_kind
  module_id
  current_term_revision_id
  current_contract_revision_id
  current lifecycle/display fields

kb.ontology_term_revisions        # append-only historical term snapshots
  id
  term_id
  revision
  snapshot/reason/provenance
  supersedes_revision_id
  create_time/create_by

kb.ontology_class_contract_revisions
  id
  term_id
  revision
  contract_schema_version
  identity_schema_version
  definition_state
  contract_payload
  synthesis_method
  confidence
  policy_version
  provenance
  supersedes_revision_id
  create_time/create_by

kb.ontology_class_contract_capabilities
  contract_revision_id
  capability_term_id
  result_state
  validator_id/validator_version
  validation_result/evidence
  evaluated_time
```

`kb.ontology_terms` contains one current identity header per stable term ID. Existing historical
term versions migrate into the append-only revision store. `current_contract_revision_id` identifies
the current class contract. Old revisions remain queryable but are not parallel current class
identities.

`contract_payload` is the authoritative semantic definition of the class. It must express:

* class meaning and applicability;
* attribute identifiers, labels, and definitions;
* logical datatypes, which define semantic value spaces rather than Go, SQL, or JSON primitives;
* attribute cardinality and required, optional, or conditional presence;
* permitted units, dimensions, value forms, and special values;
* normalization and canonical serialization rules;
* constraints, tolerances, defaults, and cross-attribute rules;
* known errors, exceptions, and missing-value interpretations;
* assertion modalities and valid-time/applicability behavior;
* rules for equivalence, stronger/weaker comparison, conflict, and incomparability; and
* broader, narrower, exact, close, or related class mappings.

`contract_schema_version` identifies the schema used to serialize and validate
`contract_payload`. For example, a later schema may add named rule groups without changing the
class's semantic identity. It is not the class identity and is not stored in `instance_of`.

`identity_schema_version` identifies the active set of contract fields used to construct canonical
claim identity for this class. It is distinct from payload serialization. A contract revision that
changes only definitions, non-identity-bearing optional attributes, validation guidance, or display
metadata does not change claim identity. Adding, removing, or changing an identity-bearing field is
a canonical-key migration: it creates a new identity schema/key version, computes shadow identities
for every affected occurrence, reports convergences and splits, creates required assertion
redirects, and cuts over atomically only after validation. New writes continue using the prior
active identity schema until that migration completes. If the change alters the logical meaning of
the class itself rather than only claim discrimination within it, the system creates a new term ID.

An object instance may record:

```text
normalized_against_contract_revision_id
```

This optional immutable audit reference says which contract revision was used for normalization.
It is not used for class grouping. Adding a compatible optional attribute or improving a rule
creates a new contract revision under the same term ID and does not require mass-updating instances.
A decision-relevant revision can enqueue affected instances for asynchronous revalidation. If the
underlying meaning changes so that it is no longer the same logical class, the system creates a new
term ID and an explicit mapping or supersession relation.

The authoritative payload may initially be JSONB because class attributes are extensible. The
OpenSpec design may add normalized child tables or indexed projections for attributes and rules;
those projections do not become competing sources of truth.

### 3.3 DR3 — Define class identity, definition, and capabilities independently

Class identity and class readiness are not one state machine.

Class identity resolution uses:

```text
resolved_existing        # confidently matched an existing class
provisional_new          # no safe match; a provisional class was created
ambiguous_candidates     # provisional class used while several alternatives remain plausible
candidate_evidence_conflict
                         # identity evidence supports mutually incompatible alternatives
```

Class definition state, stored on the current contract revision, uses:

```text
identity_only            # class identity exists, but no usable semantic contract exists
partially_defined        # some contract semantics are validated
validated                # the declared capability checks pass
```

Class capabilities are explicit rather than implied by one global “ready” flag:

```text
can_instantiate
can_validate_values
can_compare_instances
can_drive_completeness_checks
```

Each capability is a governed `capability_term_id` with an independent `result_state` of
`enabled`, `disabled`, or `indeterminate` in
`kb.ontology_class_contract_capabilities`. A capability may be `enabled` only when the named
validator/version records a passing result and supporting evidence for that contract revision.
`identity_only` may enable `can_instantiate` but cannot enable value validation, instance comparison,
or completeness checks. `partially_defined` may enable only the capabilities whose prerequisites
pass. `validated` means every capability declared enabled by the contract has passed; it does not
require every possible capability to be enabled.

An `identity_only` or partially defined class can receive instances. It simply cannot claim
unsupported capabilities. Ambiguity over whether to reuse an existing class is an identity state,
not a definition state.

Every contract revision is validated by a named validator and validator version. Validation checks:

* payload structure against `contract_schema_version`;
* unique and coherent attribute identities and meanings;
* compatible cardinality, required/optional/conditional rules, and defaults;
* compatible logical datatypes, special values, units, and dimensions;
* satisfiable cross-attribute constraints;
* declared normalization and raw-value fallback behavior;
* comparison rules limited to supported value forms, modalities, and applicability contexts;
* presence of every definition required by each declared capability; and
* provenance and the policy decision that activated the revision.

Validation is capability-specific. A metric class may be valid for grouping and instantiation while
remaining unsuitable for stronger/weaker comparison. Human approval is optional; versioned policy
may activate a validated contract autonomously.

### 3.4 DR4 — Use a lossless evidence-first pipeline without metric decision-candidate staging

The logical and physical metric flow is:

```text
1. kb.metrics raw occurrence
      -> build a raw-preserving normalized shape in memory
2. normalized shape and metric-name evidence
      -> resolve an existing class or create a provisional class
3. selected/provisional class
      -> normalize and validate where its contract permits
4. class + normalized/raw-preserved semantic payload
      -> find or create canonical claim identity and kb.semantic_assertions
5. source occurrence
      -> insert kb.assertion_evidence for the assertion
6. instance observations
      -> update observed class profile and derive eligible relations
```

`kb.metrics` remains the source-of-truth for what extraction found. `kb.assertion_evidence` remains
a provenance link containing the source artifact, evidence quote, spans, extraction run, model,
prompt, confidence, and evidence role. It does not normalize the metric and does not store the best
candidate shape. Normalized fields, raw fallback, value state, conformance state, and processing
errors belong to `kb.semantic_assertions` and its validation records.

`kb.semantic_decision_candidates` is removed from the normal metric path. The processor builds the
shape in memory and transactionally creates or reuses the semantic assertion and evidence link. The
existing table remains temporarily for migration and for other artifact workflows that genuinely
manage competing proposals; it may be retired globally only after those consumers are audited.

Class identity alternatives and their decisions are stored in DR7's append-only resolution table,
not by duplicating every metric into a generic staging row.

### 3.5 DR5 — Persist every source-backed metric, including failures and nonconformance

A normalization, mapping, class-resolution, or validation failure must never cause a source artifact
to disappear from semantic processing.

The processor must:

* preserve raw value, raw declared datatype, raw unit, raw range description, and source wording;
* record every attempted normalization and its outcome;
* populate normalized fields when possible and use raw-preserved identity when not;
* create the semantic assertion even when it is provisional, ambiguous, unparsed, nonconforming,
  missing, or unknown;
* attach evidence and continue downstream processing;
* expose capability and quality flags so consumers choose whether and how to use it; and
* retry targeted decisions when mappings, contracts, or identity evidence improve.

A failed mapping does not prove that the source is wrong. It may reveal an incomplete map, parser,
vocabulary, or contract. The system therefore records precise states such as
`mapping_unresolved`, `unparsed`, `datatype_mismatch`, `contract_violation`, `class_provisional`,
`class_ambiguous`, and `source_conflict` rather than applying one global `incorrect` label.

Admission into `kb.semantic_assertions` means “this source-backed claim is represented,” not “this
claim is true or conforms to its class.” Consumers make risk-appropriate decisions from the
assertion's state and evidence.

This lossless-processing principle applies across the complete lifecycle, including extraction,
normalization, class synthesis, claim convergence, relation derivation, projections, Review
Document, reprocessing, and backfill. A separate cross-cutting ADR must apply the same rule to all
artifact families and correct existing fail/stop behavior; that ADR is a required implementation
dependency, not an unresolved decision in this ADR.

### 3.6 DR6 — Build evolving classes from observations without treating observations as valid rules

For every instance, the processor collects its observed structure, including value, logical value
type, range form, unit, condition, subject, modality, and domain-specific attributes such as
`normal speed`, `red-zone speed`, or `value when used outside`.

The class aggregate preserves a structural superset of attributes recognized across its instances
in an observed profile. The observed profile records:

* candidate attribute names and normalized identities;
* observed logical datatypes, units, value forms, and cardinalities;
* frequency and document/domain distribution;
* examples and source evidence;
* co-occurrence and conditional patterns;
* contradictions and outliers; and
* confidence and the method that grouped each observation.

The authoritative contract is a validated synthesis of this superset, not its raw union. A malformed
string does not expand a numeric datatype into “numeric or arbitrary string.” The string remains a
raw-preserved observation with `datatype_mismatch` or another precise state until a later decision
changes the contract.

Class synthesis must decide whether a new field is:

* an attribute of the existing class;
* an alias for an existing attribute;
* a condition or applicability qualifier;
* a related but separate metric class;
* a specialized subclass/profile; or
* erroneous or presently unresolved.

For example, `normal speed` and `red-zone speed` might be conditional attributes of a speed class,
or they might be separate metrics related to a common equipment class. The system preserves the
ambiguity and raw evidence until contextual and corpus evidence support one model.

### 3.7 DR7 — Make same-class resolution reusable, explicit, and auditable

The most difficult and important operation is deciding whether different artifacts instantiate the
same ontology class. Class creation must not become “one new label, one new class,” and class growth
must not merge merely similar concepts.

The existing keyword Tier-0 through Tier-6 machinery remains one shared implementation:

* Tier 0: exact surface identity;
* Tier 1: current normalized-key identity;
* Tier 2: alternate keys such as alphanumeric, sorted, and singular forms;
* Tier 3: governed rewrite rules and retry of earlier deterministic tiers;
* Tier 4: initials/acronym bridges;
* Tier 5: guarded fuzzy matching; and
* Tier 6: offline multilingual embedding and governed terminology identity evidence.

The code is factored behind a reusable identity-resolution service rather than copied into metrics,
classes, entities, inventory, or other processors:

```text
ResolveIdentity(context, IdentityRequest) -> IdentityDecision
```

The shared resolver owns tier execution, blocking, evidence collection, caching, decision reuse, and
escalation. Artifact-family adapters provide structural fields, compatibility rules, negative
constraints, and risk policy.

Name identity is necessary but not sufficient for class identity. Class resolution also uses stable
source identifiers, redirects, governed mappings, quantity kind, observable property, unit
dimension, subject compatibility, attribute shape, logical datatypes, conditions, modality,
applicability, domain scope, ontology neighborhood, corpus evidence, and bounded LLM adjudication.

Every decision is written to:

```text
kb.semantic_class_resolution_decisions
  id
  decision_key
  input_record_id
  source_artifact_type
  source_artifact_id
  assertion_id
  selected_term_id
  outcome
  candidate_term_ids
  method
  confidence
  evidence
  rationale
  policy_version
  model/prompt_version when applicable
  supersedes_decision_id
  create_time/create_by
```

The table is append-only. `input_record_id`, `source_artifact_type`, `source_artifact_id`,
`assertion_id`, and `selected_term_id` are required for an instance-resolution decision.
Class resolution is computed in memory first; the transaction then finds or creates the assertion
and inserts the resolution decision and evidence link with both concrete references. No decision
row is inserted early and later mutated to attach an assertion. A later reconsideration inserts a
new row with the same stable `decision_key`, points `supersedes_decision_id` to the former decision,
and triggers any required assertion/class redirect processing. For an ambiguous case,
`selected_term_id` is the provisional class used by the persisted instance, while alternatives
remain in `candidate_term_ids`.

`candidate_evidence_conflict` means that identity evidence supports mutually incompatible class
candidates. It does not mean that a resolved instance violates its class contract. The latter has
`class identity = resolved_existing` and a separate `conformance = contract_violation`, with a
specific value or validation state.

### 3.8 DR8 — Reuse `kb.semantic_assertions` as instances with independent state dimensions

A separate `kb.ontology_term_instances` table is not introduced because it would duplicate the
assertion's subject, value, conditions, lifecycle, revisions, evidence, and provenance.

Every metric instance carries, directly or through its current validation records:

```text
instance_of_term_id
normalized_against_contract_revision_id
class_identity_state_term_id
value_state_term_id
conformance_state_term_id
processing_error_details
```

The state term IDs refer to governed records in `kb.ontology_terms`, normally in a core
semantic-processing module. Class definition and capability state belong to the class contract
revision, not the assertion.

If no existing class resolves, the system creates a provisional class and uses
`class_identity_state = provisional_new`. If several classes remain plausible, the instance points
to a provisional class and uses `ambiguous_candidates`; the alternatives remain in the resolution
decision. If class identity is known but its definition is incomplete, the assertion remains
`resolved_existing` while the class contract independently remains `identity_only` or
`partially_defined`.

Value state includes:

| State | Meaning |
|---|---|
| `present` | A usable normalized value or interval exists. |
| `missing` | The document mentions the metric but supplies no expected value. |
| `unparsed` | Source value exists but normalization cannot parse it. |
| `datatype_mismatch` | Observed datatype conflicts with the selected class contract. |
| `not_applicable` | The source explicitly says the metric does not apply. |
| `unknown` | The occurrence and raw evidence exist, but the processor cannot yet determine another value state. |

`missing` and `unknown` describe persisted assertions; they do not mean an instance row is absent.
Unparsed, mismatched, missing, and unknown instances preserve raw content, class identity or
candidates, applicability, errors, and evidence. A genuine missing-value assertion requires the
current `kb.semantic_assertions` object-reference-or-literal constraint to be revised.

Conformance state initially includes `conforms`, `contract_violation`, and `not_evaluated`.
Applications choose whether to include, warn about, or exclude each combination of identity,
definition, value, conformance, and error states.

### 3.9 DR9 — Make normalized claim identity semantic rather than occurrence-derived

A **normalized claim** is the semantic content represented by a `kb.semantic_assertions` logical
identity; a row may be one revision of that claim. Claim identity is computed from canonical
semantic content rather than the source occurrence.

For metrics, the canonical identity includes, where applicable:

* canonical subject/referent;
* stable `instance_of_term_id` after redirect resolution;
* predicate and assertion kind/modality;
* normalized value, interval, or explicit raw-preserved value-state payload;
* canonical unit and quantity kind;
* comparator and boundary inclusivity;
* conditions, procedure, polarity, and applicability;
* valid time; and
* fields in the class's active `identity_schema_version`.

It excludes source record, metric ID, wording, spans, extraction run, model, prompt, confidence, and
display labels.

A new table provides concurrency-safe find-or-create:

```text
kb.semantic_claim_identities
  claim_id
  identity_scope
  canonical_key_version
  canonical_payload
  canonical_digest
  current_assertion_id
  create_time
```

`canonical_payload` is a deterministic serialization of the identity-bearing semantic fields. For
example:

```json
{
  "subject": "display-1",
  "class_term_id": "measurement:display_luminance",
  "assertion_kind": "lower_bound_requirement",
  "value_state": "present",
  "value": 300,
  "unit": "cd/m2",
  "comparator": ">=",
  "applicability": "normal operation"
}
```

Equal digests are reused only after canonical payload bytes compare equal. Given a metric, the
system first resolves or creates its class, builds the canonical payload, and finds or creates the
claim identity and assertion. Several metric occurrences can therefore support the same
`kb.semantic_assertions` row through separate evidence records. New evidence alone does not create
an assertion revision.

An identity-bearing contract change follows DR2's canonical-key migration. It cannot silently alter
find-or-create behavior. The old key version remains authoritative until shadow recomputation,
convergence/split review, redirects, and atomic activation of the new `canonical_key_version`
complete.

Raw-preserved failure states also have deterministic identity payloads so two different unparsed
strings do not collapse merely because they share a class and `unparsed` state. Absorbed historical
assertion identities remain resolvable through audited, acyclic assertion redirects.

### 3.10 DR10 — Persist governed relations among same-class instances

Instances of one canonical class may be identical and converged, equivalent after normalization,
stronger or weaker, conflicting, syntactically conflicting, incomparable, or related by future
relation kinds not known today.

The existing `kb.assertion_relations` table is extended rather than replaced:

```text
kb.assertion_relations
  id
  assertion_id
  related_assertion_id
  relation_term_id
  relation_family_term_id
  comparison_context
  context_fingerprint
  status
  derivation_method
  rule_version
  confidence
  comparison_evidence
  rationale
  decision_id
  supersedes_relation_id
  create_time/create_by
```

Initial governed relation terms include:

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

The table prohibits self-relations, canonicalizes endpoints for symmetric relations, stores one
direction for directional relations and derives the inverse, and permits one active verdict per
relation family, endpoint pair, context, and rule version. Changed decisions supersede rather than
destructively replace prior rows.

Comparison is class-contract-driven:

1. validate same canonical class or an explicitly comparable mapped class;
2. validate compatible subject, dimension, assertion modality, conditions, applicability, and time;
3. check value and conformance states without dropping a nonconforming instance;
4. normalize units and values where the class contract permits;
5. apply the registered comparison rule; and
6. persist the verdict, or `incomparable_with`/an explicit no-verdict reason when comparison is not
   supported.

For requirement constraints, satisfying-set containment defines stronger and weaker. For example,
`>= 300 cd/m2` is stronger than `>= 250 cd/m2`. Numeric ordering alone does not define
stronger/weaker for observations. A datatype mismatch is first an instance value/conformance state;
it becomes a pairwise syntactic conflict only when a governed rule establishes the relevant
comparison context.

Relations do not declare which source is correct. Review Document presents the difference,
conformance, source authority, and applicability separately.

### 3.11 DR11 — Reconcile duplicate classes online and incrementally

The end-to-end order is:

```text
kb.metrics raw occurrence
  -> resolve metric name to kb.keyword_concepts
  -> build raw-preserving semantic shape
  -> resolve an existing class or create a provisional kb.ontology_terms class
  -> normalize/validate under the class contract where possible
  -> build canonical claim identity
  -> find or create kb.semantic_assertions
  -> create kb.assertion_evidence
  -> update the class observed profile
```

Keyword-concept-to-term alignment is strong class-resolution evidence, but it is not always
sufficient by itself. Quantity, unit, subject, attribute shape, conditions, applicability, and
domain scope also participate.

Duplicate-class reconciliation is required in two places:

1. **Online before provisional creation:** attempt to reuse an existing class through deterministic
   gates, governed mappings, structural evidence, and bounded escalation.
2. **Incrementally/offline after creation:** detect duplicates missed earlier as more documents,
   attributes, mappings, external terminology, or LLM evidence become available.

Duplicate provisional classes are expected in an autonomous evolving ontology. Reconciliation is
the same process described by the review feedback: it determines that two class identities mean the
same logical class and redirects them to one canonical term ID.

`kb.ontology_mappings` records exact, close, broad, narrow, and related semantic decisions. Exact
identity additionally creates `kb.ontology_term_redirects` from absorbed term to canonical
survivor. Terms are not hard-deleted. Distinct curated or explicitly `never_merge` terms may block
a merge; distinct auto-promoted terms trigger adjudication rather than circularly proving that two
concepts differ.

Because class identity participates in claim identity, a term merge re-resolves affected evidence,
recomputes canonical claim identities, converges equal assertions, writes assertion redirects,
recomputes relations, and rebuilds projections. Reversal replays evidence through the superseding
class decision rather than guessing how merged assertions should split.

### 3.12 DR12 — Use deterministic processing first and LLMs for bounded ambiguity

Class resolution, class synthesis, instance convergence, and relation derivation use this ordered
strategy:

1. **Deterministic:** stable IDs, redirects, exact keyword tiers, governed mappings, canonical
   serialization, units/dimensions, logical datatype checks, and comparison rules.
2. **Rule/statistical:** guarded fuzzy matching, structural signatures, corpus statistics,
   embeddings, and ontology-neighborhood evidence.
3. **LLM adjudication:** determine likely same-class identity, attribute meaning, class shape,
   applicability distinctions, or relation semantics for the bounded ambiguous set.
4. **Policy activation:** select an existing class, create a provisional class, reject an unsafe
   merge, retain ambiguity, or activate a contract/relation according to risk and evidence.

An LLM produces a structured proposal and evidence. A governed policy-owned writer activates it;
LLM code does not directly mutate current contracts or canonical identities. LLM cost is controlled
through deterministic negative gates, candidate blocking, batching, caching, reuse of prior
decisions, and re-adjudication only when decision-relevant evidence changes.

Human review is optional at every stage. It may correct, lock, merge, split, or supersede a decision,
but it is not a document-processing dependency.

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

“Current evidence” means the active supporting link for the current metric occurrence:
`artifact_type = 'metric'`, matching `input_record_id` and `artifact_id`,
`evidence_role = 'supports'`, and `deleted = false`. Its assertion is resolved through any active
assertion redirect to the claim registry's current assertion.

Candidate retrieval order is:

1. same canonical class after redirect resolution;
2. governed class mappings allowed by the review rule;
3. structurally compatible subjects, quantities, contracts, and ontology neighborhoods;
4. lexical/vector similarity; and
5. LLM adjudication for high-value residual ambiguity.

Class membership is authoritative. Later channels discover candidates and are labeled as fallback;
they do not silently turn similarity into identity. Every pair must pass subject, dimension,
modality, condition, applicability, and time gates before semantic comparison.

Review Document shows class identity and definition states, value state, conformance, processing
errors, comparison relation, confidence, and source evidence. It distinguishes a metric absent from
a metric present with a missing value. Absence can be concluded only relative to a named profile or
contract declaring the metric expected in the review scope.

Nonconforming, provisional, ambiguous, missing, unparsed, and unknown instances remain visible with
warnings. Each application or user chooses whether to include them. Incomplete ontology processing
never blocks Review Document; structural and similarity fallbacks remain available and labeled.

### 3.14 DR14 — Make every decision idempotent, observable, and reversible

Every class, contract, instance-identity, validation, and relation decision records:

* inputs and candidates considered;
* raw observations and canonical identities;
* deterministic, statistical, and LLM methods used;
* policy, thresholds, validator, rule, model, and prompt versions;
* evidence, confidence, rationale, errors, and capability effects;
* what was created, merged, redirected, rejected, superseded, or left ambiguous;
* how the decision can be superseded or reversed; and
* which projections or instances require revalidation.

Re-running unchanged inputs does not create duplicate classes, assertions, evidence links,
decisions, or relations. Changed evidence creates a new append-only decision or revision only when
decision-relevant. Raw evidence is never overwritten by normalized output.

## 4. Review Decisions Incorporated

The review comments are resolved as follows:

* Stable `instance_of_term_id` identifies the class; contract revision is a separate audit reference.
* Every metric instance has an existing or provisional class.
* Identity, definition, capability, value, and conformance states are independent.
* Class contract, serialization schema, validation, and append-only revision storage are explicit.
* Instance class references are not mass-updated when compatible contracts evolve.
* `kb.assertion_evidence` remains provenance and does not normalize metrics.
* `kb.semantic_decision_candidates` leaves the normal metric path.
* Raw and nonconforming claims remain in semantic processing through the entire lifecycle.
* Tiered identity resolution becomes a reusable service.
* Class-candidate conflict is distinct from contract violation.
* Class-resolution decisions and governed state references have explicit stores.
* Normalized claim, canonical payload, and `kb.semantic_claim_identities` are defined.
* Missing and unknown are persisted value states, not missing instance rows.
* `kb.assertion_relations` has an explicit extensible shape.
* Duplicate-class reconciliation runs both before and after provisional class creation.

## 5. Alternatives Considered

### 5.1 Continue treating a term row as a complete class

Rejected. The live row commonly contains only identity and a label. Optional free-text fields cannot
express the required attribute, logical datatype, applicability, exception, and comparison
semantics.

### 5.2 Keep class contract version in `instance_of`

Rejected. Classes evolve frequently, while class identity should remain stable. Coupling every
instance to the current version would either leave most instances pointing to old class rows or
require costly mass updates. Stable term identity plus an optional normalization-revision audit
reference is simpler and preserves reproducibility.

### 5.3 Make the authoritative contract the raw union of observations

Rejected. A raw union turns malformed values and extraction errors into valid class semantics and
causes datatype and constraint conflicts to disappear. The observed profile remains inclusive; the
contract remains governed.

### 5.4 Create `kb.ontology_term_instances`

Rejected. It would duplicate most of `kb.semantic_assertions` and create two sources of truth for
instance values, conditions, lifecycle, revisions, evidence, and provenance.

### 5.5 Keep a decision candidate for every metric

Rejected for the metric path. Lossless assertions can represent provisional, ambiguous, unparsed,
and nonconforming outcomes directly. Alternative class candidates belong in an explicit resolution
decision rather than a duplicate staging copy of every source metric.

### 5.6 Add `kb.metrics.metric_assertion_id`

Rejected as the authoritative relationship. It would encode a metric-specific one-to-one
assumption in a system whose generic provenance relationship is many-to-many. A current projection
can provide query convenience without replacing `kb.assertion_evidence`.

### 5.7 Define every class manually

Rejected as a universal requirement. It produces the best result for critical classes but cannot
keep pace with corpus scale. The selected design permits curated, autonomous, and hybrid classes.

### 5.8 Use only deterministic rules, embeddings, or an LLM

Rejected. Deterministic rules must run first but cannot resolve every contextual meaning. Embeddings
and LLMs are valuable for bounded candidates, but neither alone is a stable identity authority.

## 6. Implementation Sequence

Implementation is tracked through separate OpenSpec changes. The order is:

### Phase 0 — Lossless-processing dependency and corpus characterization

1. Create the cross-cutting ADR for lossless semantic processing.
2. Stop current normalization/mapping failures from dropping artifacts from downstream processing.
3. Preserve raw values and structured error outcomes for all current metric failure paths.
4. Inventory label-only terms, metric attributes, conflicts, and Review Document baselines.

### Phase 1 — Stable class identity and append-only contract history

1. Reshape `kb.ontology_terms` into one current stable identity header per term ID.
2. Create append-only term and class-contract revision stores and migrate existing versions.
3. Create observed class profiles and per-capability validation records.
4. Add generic stable `instance_of_term_id` and optional normalization-contract revision reference.
5. Create the claim-identity registry, canonical-key version registry, and assertion redirects in
   shadow mode.
6. Seed governed identity, definition, capability, value, conformance, error, and relation terms.

### Phase 2 — Lossless metric instance pipeline

1. Move metric normalization to an in-memory raw-preserving shape.
2. Create the reusable identity-resolution service and class-resolution decision store.
3. Resolve an existing class or create a provisional class for every metric.
4. Implement and validate canonical payload serialization and concurrency-safe claim-identity
   find-or-create before enabling the new assertion writer.
5. Create/reuse a semantic assertion regardless of normalization or conformance outcome.
6. Persist the concrete class-resolution decision, evidence, validation results, processing errors,
   and observed class attributes in the same transaction.
7. Remove `kb.semantic_decision_candidates` from the metric path after compatibility validation.

### Phase 3 — Class synthesis and duplicate reconciliation

1. Aggregate observed class profiles without changing authoritative contracts.
2. Normalize attribute identities through the reusable resolver.
3. Apply deterministic identity and negative gates before bounded statistical/LLM adjudication.
4. Synthesize and activate append-only contract revisions through policy.
5. Run online and incremental duplicate-class reconciliation.
6. Repair keyword concepts, term alignments, redirects, and affected observed profiles.

### Phase 4 — Canonical claim identity and relations

1. Backfill legacy assertions into the already-active canonical claim-identity registry, including
   raw-preserved error states.
2. Report convergence groups, collisions, unresolved states, and validation differences.
3. Converge identical legacy assertions without losing independent evidence and persist redirects.
4. Exercise identity-schema migrations through shadow recomputation and atomic cutover tests.
5. Extend `kb.assertion_relations` and derive eligible relations incrementally.

### Phase 5 — Review Document integration

1. Implement the class-to-instance traversal in DR13.
2. Add identity, definition, capability, value, conformance, error, relation, and evidence fields to
   review payloads.
3. Make canonical class membership the first retrieval channel.
4. Retain and label structural, lexical, vector, and LLM fallbacks.
5. Let review policies and users select how flagged instances are used.

## 7. Migration and Backfill Safety

Migration is additive until shadow validation passes.

* Existing `kb.metrics` occurrences and raw provenance are not deleted or coalesced.
* Existing term versions are migrated into append-only history before current identity headers are
  changed.
* Existing term and assertion IDs remain addressable through redirects.
* Existing decision candidates remain available until every consumer is audited and migrated.
* Raw values and errors are preserved before fail/stop behavior is removed.
* Observed class profiles never overwrite authoritative contracts.
* Contract changes create append-only revisions and never require mass class-FK updates.
* Revalidation is targeted, restartable, and separate from class grouping.
* Backfill operates in bounded batches with dry-run decision reports.
* Term merge/split replays evidence and recomputes claim identity and relations.
* Redirects are single-active-target, acyclic, lock-protected, and reversible by superseding
  decisions.
* Review Document retains fallback retrieval throughout rollout.

Required pre-cutover reports include:

* stable term identities and migrated historical revisions;
* identity-only, partially defined, and validated contract counts and capabilities;
* observed attributes proposed for each class and their evidence distribution;
* terms and concepts proposed to merge, split, or keep distinct;
* assertions proposed to converge and their evidence membership;
* all raw-preserved, unparsed, missing, unknown, nonconforming, and ambiguous instances;
* relation counts by type, method, confidence, and status;
* LLM call volume, cache reuse, cost, and decision yield; and
* changes to Review Document candidate and comparison sets.

## 8. Acceptance Criteria

### 8.1 Class foundation

* One stable `term_id` identifies one current ontology class independent of contract revision.
* Historical term and contract states are append-only and queryable.
* An `identity_only` class can receive instances but cannot claim unsupported validation or
  comparison capabilities.
* Every enabled capability has a passing named validator/version result and evidence; capability
  states are independent rows rather than one ambiguous aggregate flag.
* Contract validation checks structure, attribute coherence, logical datatypes, units, constraints,
  applicability, fallback behavior, comparison rules, provenance, and declared capabilities.
* A legitimate new attribute creates a contract revision without mass-updating instance class IDs.
* An identity-bearing field change uses a versioned shadow canonical-key migration and atomic
  cutover; it never silently changes claim find-or-create behavior.
* A meaning change that breaks logical identity creates a new term ID.

### 8.2 Occurrence, evidence, and lossless processing

* One atomic metric occurrence has at most one current supporting instance link.
* Unchanged reprocessing reuses the link; changed reprocessing supersedes it while retaining history.
* `kb.assertion_evidence` preserves provenance and never replaces raw source content with normalized
  values.
* Every source-backed metric produces a semantic assertion and an existing or provisional class.
* Mapping, parsing, class ambiguity, or contract violations never remove the metric from downstream
  semantic processing.
* Raw values, raw datatypes, raw units, errors, methods, and evidence remain queryable throughout the
  lifecycle.

### 8.3 Class and instance identity

* Approved aliases and translations of one logical metric resolve to one canonical stable term ID.
* Same-label metrics with different quantities, subjects, or applicability remain distinct.
* Two semantically identical occurrences converge on one assertion with independent evidence.
* Two different values of the same class remain distinct instances and receive a relation when
  comparable.
* No safe class match creates a provisional class rather than a classless or discarded instance.
* Ambiguous alternatives and conflicting identity evidence are preserved in resolution decisions.
* Every resolution decision has concrete source-occurrence, assertion, and selected-class
  references and is superseded append-only.
* Duplicate provisional classes can be reconciled without keyword alignments creating a circular
  block.

### 8.4 State and validation behavior

* Class identity, class definition/capability, value, and conformance states are independently
  queryable.
* A resolved instance that violates its class remains class-resolved and records the contract
  violation separately.
* A raw string where the class expects a numeric logical value produces `datatype_mismatch` without
  broadening the class contract.
* A mentioned metric with no supplied value produces a persisted `missing` instance.
* An undecidable value produces a persisted `unknown` or `unparsed` instance with raw content.
* Admission into the knowledge base is never presented as proof of correctness.

### 8.5 Relations

* The extended `kb.assertion_relations` stores governed relation type, context, method, rule version,
  confidence, evidence, lifecycle, and supersession.
* `display luminance >= 300 cd/m2` is `stronger_than`
  `display luminance >= 250 cd/m2` when subject and applicability are compatible.
* Unit-equivalent values converge or receive an explainable equivalence relation.
* Observations do not inherit stronger/weaker semantics merely from numeric order.
* Unsupported comparisons yield incomparability or an explicit no-verdict reason.
* Future relation terms do not require a closed database enum change.

### 8.6 Autonomous operation

* No ordinary semantic-processing stage requires human approval.
* Deterministic identity and negative gates run before statistical or LLM methods.
* Tiered identity logic is reused through one resolver with artifact-family adapters.
* LLM calls operate only on bounded ambiguous candidates and are cached by versioned inputs.
* Autonomous activation occurs only through a recorded policy decision.
* Human corrections can override and lock decisions; autonomous merges and contract changes are
  reversible or supersedable.

### 8.7 Review Document

* Starting from a metric occurrence, Review Document retrieves its current assertion through
  evidence, its stable class through `instance_of`, and all same-class instances and source metrics.
* Same-class retrieval precedes similarity-only discovery.
* Results explain identity, definition/capability, value, conformance, errors, relation, confidence,
  and evidence.
* Missing value is distinguishable from metric absence.
* Flagged instances remain available, with application/user policy controlling their use.
* Incomplete ontology processing does not block review; fallbacks are visibly labeled.

### 8.8 Competency and regression tests

The OpenSpec changes must include:

* CQ-M02 positive and negative fixtures from ADR `2026072901`;
* stable class identity across contract revisions;
* append-only term/contract history and targeted revalidation;
* identity-only class instantiation and capability enforcement;
* observed-profile expansion without automatic contract expansion;
* Phase-2 same-document reprocessing with unchanged and changed payloads;
* multilingual and alias class convergence;
* same-label/different-quantity negative identity;
* exact assertion convergence with multiple evidence rows;
* raw-preserved mapping, parsing, missing, unknown, datatype, and contract failures;
* lower/upper-bound, interval, conflict, and incomparability relations;
* deterministic, statistical, and LLM-assisted class decisions;
* online/offline class merge, split, redirect reversal, cycle rejection, and `never_merge`; and
* the complete Review Document traversal in DR13.

## 9. Consequences

### 9.1 Positive

* The ontology gains a real class layer instead of treating labels as definitions.
* Stable instance-to-class references survive ordinary contract evolution.
* Historical contracts remain reproducible without mass-updating assertions.
* Classes can grow from corpus evidence without requiring a human for every discovery.
* Bad or unresolved observations remain visible without poisoning the class contract.
* Same occurrence, same instance, and same class become separate auditable decisions.
* Equivalent claims converge without losing provenance.
* Meaningful differences become relations rather than isolated rows.
* Review Document gains class-first comparison while retaining similarity recall.

### 9.2 Costs and risks

* Current-header plus append-only-history storage requires a careful migration from existing term
  versions.
* Multiple independent state dimensions are more explicit but increase query and UI complexity.
* Lossless ingestion increases stored assertions and requires consumers to apply quality policy.
* Class synthesis can misclassify an attribute, condition, submetric, or error.
* A false class merge affects more downstream objects than a false similarity match.
* LLM adjudication adds cost, latency, and nondeterminism.
* Contract evolution can trigger expensive targeted revalidation and relation recomputation.
* Pairwise comparison can become quadratic without blocking and incremental updates.

These risks are managed by stable identity, append-only decisions, separating observation from
authority, deterministic-first resolution, negative gates, bounded LLM use, shadow computation,
complete provenance, capability-aware consumers, and reversible redirects.

## 10. Relationship to Earlier Decisions

### ADR `2026072901`

This ADR implements and sharpens the class/instance intent and CQ-M02 behavior. It retains the
governed write boundary while clarifying that policy-controlled autonomous activation does not
require a human reviewer. Any wording that treats a term identity row as a complete class, requires
mandatory human activation, or drops unresolved source-backed claims is superseded for this
workflow.

### ADR `2026081201`

Automatic term creation remains permitted, but it creates an `identity_only` provisional class
unless a validated contract is also synthesized. Duplicate auto-promoted terms must be reconciled
rather than used as circular evidence that keyword concepts differ.

### ADR `2026081401`

Governed `value_range_type` mapping remains part of deterministic normalization, but mapping failure
no longer removes the metric from later semantic processing. Raw values and explicit mapping/error
states continue through the pipeline.

### User manual §6.11

This ADR adopts §6.11's defect finding and replaces occurrence-derived isolation with an explicit
occurrence–evidence–instance–class model and governed relations among instances.

## 11. Open Questions for OpenSpec

These are implementation details rather than unresolved architectural direction:

1. The migration mechanics from current `(term_id, version)` rows to stable current headers plus
   append-only revisions.
2. The normalized projections and indexes derived from authoritative JSON class contracts.
3. The precise capability requirements for each class kind and risk tier.
4. Initial thresholds for class identity, contract activation, and LLM-assisted decisions.
5. Canonical serialization of conditions, procedures, applicability, and domain-specific fields.
6. The exact migration or retirement plan for non-metric users of
   `kb.semantic_decision_candidates`.
7. Review Document presentation of multidimensional states without overwhelming users.

These questions must be resolved and tested before production cutover.
