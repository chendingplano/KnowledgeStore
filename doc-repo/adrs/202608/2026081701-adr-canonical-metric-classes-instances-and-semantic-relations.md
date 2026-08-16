# ADR 2026081701 — Canonical Metric Classes, Normalized Instances, and Semantic Relations

**Date:** 2026-08-17 \
**Status:** Proposed \
**Component:** ChenWeb — ontology terms, keyword concepts, semantic assertions, assertion evidence, assertion relations, metric comparison, and Review Document \
**Authors:** Chen Ding (with Codex) \
**Related:** ADR `2026072901` (ontology platform and adaptive pipeline), ADR `2026081201` (auto-promoted governed terms), ADR `2026081401` (governed metric vocabulary and Phase D failure reporting), user manual `metric-assertion-semantic-processing-v1.2-en.md` §6.11 \
**Tags:** ontology, metrics, semantic identity, class-instance model, assertion relations, autonomous resolution, Review Document

## 1. Change Log

* 2026/08/17, ADR proposed after investigating user manual §6.11 and the live implementation.
  The investigation confirmed that metric occurrences sharing a governed metric term still create
  separate assertion identities, assertion relations are not produced, and Review Document uses
  similarity retrieval rather than canonical ontology identity.

## 2. Context

### 2.1 The missing class-instance distinction

The current implementation treats several different identities as if they were interchangeable:

* a raw metric occurrence in `kb.metrics`;
* a keyword concept in `kb.keyword_concepts`;
* a governed metric definition in `kb.ontology_terms`;
* a normalized claim in `kb.semantic_assertions`; and
* the evidence that a source artifact provides for a normalized claim.

These objects serve different purposes and must not share one occurrence-derived identity.

For example:

```text
A: display luminance >= 250 cd/m2
B: display luminance >= 300 cd/m2
```

Both A and B instantiate the same logical metric, **Display Luminance**. They are not the same
claim: B is a stronger lower-bound requirement than A. The ontology must therefore represent one
metric class, two normalized instances, and a relation between the instances.

The intended model is analogous to a class and its instances:

```text
metric-definition class: Display Luminance
├── normalized assertion A: display luminance >= 250 cd/m2
└── normalized assertion B: display luminance >= 300 cd/m2
    └── stronger_than -> assertion A

kb.metric occurrence A --evidence--> assertion A
kb.metric occurrence B --evidence--> assertion B
```

`kb.metrics` remains the occurrence and extraction-provenance store. It is not the canonical
ontology instance store.

### 2.2 Confirmed implementation defect

`MetricNormalizer` currently assigns every metric candidate an occurrence-derived logical key:

```text
metric:<input-record-id>:<metric-id>
```

`associate_semantics` copies that key directly into `kb.semantic_assertions`. Assertion persistence
then creates or revises an assertion only by that key. Two source metrics therefore cannot converge
on one canonical assertion even when they have the same subject, metric definition, normalized
value, unit, and conditions.

The governed `metric_definition_term_id` is carried only as qualifier JSON on the assertion. It is
not a typed, indexed relationship that participates in assertion identity.

The current relation table is also insufficient. `kb.assertion_relations` permits only
`conflicts_with`, `supersedes`, and `superseded_by`, and the association pipeline does not populate
it. It cannot represent identical, equivalent, stronger, weaker, syntactically incompatible,
missing-value, or presently unknown relation cases.

### 2.3 Production evidence

A read-only survey of the staging `miner` database on 2026/08/17 found:

* 7,074 rows in `kb.metrics`;
* 89 metrics with both `keyword_concept_id` and `metric_definition_term_id`;
* 71 non-deleted metric evidence rows pointing to 71 distinct assertion rows;
* no assertion with evidence from more than one metric occurrence;
* seven governed metric terms each referenced by two different assertion logical identities; and
* zero rows in `kb.assertion_relations`.

This proves that term convergence, where it occurs, does not produce assertion convergence or
instance relations.

### 2.4 Review Document is using similarity, not ontology identity

Review Document's metric reviewer currently retrieves peers through:

1. live lexical/vector similarity;
2. shared metric categories; and
3. shared object anchors.

Its review payload and retrieval queries do not use `metric_definition_term_id` or accepted
`kb.semantic_assertions` as the primary matching identity. Similarity is useful for discovery, but
it cannot guarantee that two artifacts instantiate the same logical metric, nor can it explain a
match through a governed semantic decision.

This conflicts with ADR `2026072901`'s intended competency question CQ-M02: assertions measuring
the same property or quantity kind must group under one governed metric/property while similar but
different metrics remain separate.

### 2.5 Auto-promotion can obstruct its own repair

ADR `2026081201` creates one auto-promoted metric-definition term for every keyword concept without
an existing alignment. The term ID is derived from the concept ID. If two equivalent concepts exist,
the system therefore creates two terms.

Concept merging currently refuses to merge concepts that are aligned to different governed terms.
That guard assumed different governed terms were reliable evidence of different meanings. Once terms
are auto-created from unreconciled concepts, the assumption is circular:

```text
fragmented concepts
-> different auto-promoted terms
-> different accepted alignments
-> concept merge rejected
-> fragmentation cannot repair itself
```

ADR `2026081201` explicitly left duplicate auto-promoted-term reconciliation undecided. This ADR
resolves that open decision.

### 2.6 Human review cannot be a runtime dependency

Mandatory review of every concept, term, assertion, or relation would make high-volume document
processing operationally unusable. Human involvement must remain available but optional.

Autonomy introduces false-merge and false-relation risks. Those risks must be managed through
confidence, evidence, reversibility, sampling, and explicit uncertainty—not by blocking normal
processing until a person acts.

Some semantic decisions cannot be made deterministically. LLM use is acceptable and important for
those cases. Deterministic mechanisms should be used first because they are cheaper, reproducible,
and easier to audit; LLM adjudication should handle the remaining semantic ambiguity.

## 3. Decision

### 3.1 DR1 — `kb.ontology_terms` defines metric classes

A row in `kb.ontology_terms` with `term_kind = 'metric_definition'` represents one canonical logical
metric class. It defines the common semantic contract for its instances, including, where known:

* preferred and alternative labels;
* definition and scope;
* observable property and quantity kind;
* permitted value datatypes and value forms;
* permitted units or dimensional constraints;
* expected ranges and assertion kinds;
* default conditions and applicability; and
* relationships to broader, narrower, exact, close, or related metric classes.

All names that mean the same logical metric must resolve to exactly the same canonical term ID.
For example, approved uses of `display luminance`, `显示亮度`, and a domain-approved abbreviation
must resolve to one metric-definition term, not parallel terms.

Lexical similarity alone does not prove identity. Resolution uses the layered policy in DR8.

### 3.2 DR2 — Reuse `kb.semantic_assertions` as normalized metric instances

`kb.semantic_assertions` is the normalized instance store. A separate
`kb.ontology_term_instances` table is not introduced because it would duplicate assertion values,
conditions, lifecycle, revisions, evidence, and provenance and create competing sources of truth.

Every metric assertion must carry a direct, typed relationship to its metric class:

```text
kb.semantic_assertions.metric_definition_term_id
kb.semantic_assertions.metric_definition_term_version
```

The `(term_id, version)` pair references the governed term version used when the assertion was
normalized. Canonical identity and grouping use the stable `term_id`; the version records the exact
class definition under which the decision was made. That normalization-time version is immutable.
Using a later compatible term version is a read projection; adopting changed class semantics requires
an explicit re-normalization decision and, when decision-relevant, a new assertion revision.

Class resolution is represented independently from value state through a governed
`class_resolution_state_term_id`, initially `resolved`, `unresolved`, `ambiguous`, or `conflict`.
The resolution decision records candidate term IDs, method, confidence, evidence, rationale, and
producer provenance. During migration the class columns may be nullable for historical rows. A new
accepted metric assertion requires `class_resolution_state = resolved` and a governed class
reference. An unresolved, ambiguous, or conflicting normalized occurrence remains `deferred` or
otherwise explicitly non-accepted; it remains queryable and available to Review Document fallback
but cannot participate in canonical class convergence. A string inside `qualifiers` is not
sufficient for either class identity or resolution state.

### 3.3 DR3 — Keep occurrences and evidence; converge identical normalized instances

`kb.metrics` remains unchanged as the extraction occurrence store. Each occurrence retains its own:

* `metric_id` and source record;
* source line spans and source wording;
* extraction run, model, and prompt;
* confidence and raw structured fields; and
* keyword and governed-term resolution results.

`kb.assertion_evidence` links those occurrences to normalized assertions.

When two independently extracted occurrences normalize to the same canonical claim, they converge
on one `kb.semantic_assertions` logical identity and create separate evidence rows. New evidence by
itself does not create an assertion revision.

The identity decision remains auditable. Candidate IDs, prior assertion IDs, matching method,
confidence, rationale, and redirects from any absorbed duplicate are retained. `identical_to` is a
temporary or exceptional relation when immediate convergence is unsafe—for example, while context
or lifecycle scope remains unresolved. The steady-state representation contains one canonical
assertion, not duplicate assertion rows connected only by `identical_to`.

Assertion convergence is represented by `kb.semantic_assertion_redirects`, not only by changing
evidence foreign keys. Each redirect records the absorbed assertion logical identity, canonical
assertion logical identity, identity-decision reference, effective/reversed lifecycle, rationale,
and before/after evidence membership. One absorbed identity has at most one active redirect;
redirects are acyclic; readers follow the chain to one canonical survivor; and compaction may
shorten a chain without deleting its decision history.

### 3.4 DR4 — Canonical claim identity is semantic, not occurrence-derived

Metric candidates may retain occurrence-derived keys because each candidate records one source
proposal. Accepted assertion identity must instead be computed from canonical semantic content.

The versioned canonical-key input contains, where applicable:

* canonical subject/referent identity;
* canonical `metric_definition_term_id`;
* predicate and governed assertion kind;
* normalized value, interval, or state-specific identity payload;
* canonical unit and quantity kind;
* comparator and boundary inclusivity;
* condition, procedure, modality, polarity, and applicability scope;
* valid-time interval; and
* other fields explicitly registered as identity-bearing by the metric-class contract.

It excludes:

* input record ID and `metric_id`;
* source wording and line spans;
* extraction run, producer, model, and prompt;
* confidence; and
* mutable display labels.

Value-state identity is explicit:

| Value state | Identity-bearing value payload |
|---|---|
| `present` | Canonical typed value/interval, datatype, comparator, inclusivity, unit, and quantity kind. |
| `missing` | The `missing` state plus subject, class, and applicability context; there is no fabricated value. |
| `unparsed` | Stable fingerprint of normalized raw value and declared/inferred datatype. Different raw values must not collapse. |
| `datatype_mismatch` | Offending typed/raw value fingerprint, observed datatype, and expected class datatype. |
| `not_applicable` | The state plus the explicit non-applicability scope and conditions. |
| `unknown` | Stable unresolved-value fingerprint when source content exists; otherwise the state plus semantic context. |

Only states where no source value exists may omit the object literal/value payload. Unparsed and
datatype-mismatch instances preserve the offending value and datatype for later adjudication.
Parser, validation-rule, model, prompt, and decision versions remain normalization provenance and do
not enter semantic identity. If reprocessing produces a different semantic value or state, that
changed semantic result—not the processor version itself—creates a new claim.

Canonical claim identity is stored in a dedicated identity registry,
`kb.semantic_claim_identities`, containing a stable claim ID, canonical-key version, canonical
payload, digest, and current canonical assertion ID. This registry is not a second instance store:
`kb.semantic_assertions` remains the normalized instance and revision record, while the registry
supplies concurrency-safe logical identity and owns the pointer to its one current assertion. The
database enforces one identity per `(identity_scope, canonical_key_version, digest)`. The initial
`identity_scope` is the ChenWeb project database; any future shared multi-tenant database must add
the tenant/project key before enabling canonical writes. On a digest hit, the canonical payload bytes
must compare equal before reuse; unequal payloads are a collision error, never an automatic merge.
Assertions reference the stable claim ID, and historical assertion revisions may share it, but only
the registry's locked current pointer is authoritative for new evidence and relations.

The current `logical_identity_key` contract is changed for metric assertions: it identifies the
canonical claim, not the originating occurrence. Assertion revisions represent governance or
decision-relevant revisions of that same claim. A change to an identity-bearing semantic component
creates a different claim and, where appropriate, a relation to the prior claim; it is not merely
a new revision under the old occurrence key.

Physically, the new claim-identity foreign key and identity registry are authoritative. The existing
assertion `logical_identity_key` is populated from the stable claim ID during compatibility rollout,
becomes read-only legacy data, and may be removed after all consumers migrate. Decision-candidate
`logical_identity_key` remains occurrence-derived because it identifies a source proposal, not an
accepted canonical claim.

Association performs a transactional find-or-create through the identity registry and then inserts
or restores the occurrence's evidence. Concurrent processing of the same claim must converge safely.

### 3.5 DR5 — Every resolved occurrence has an explicit governed value state

A missing or malformed value is meaningful information and must not cause an occurrence to vanish
from semantic processing.

Metric assertions gain a governed value-state reference. Initial terms include:

| Value state | Meaning |
|---|---|
| `present` | A usable normalized value or interval is present. |
| `missing` | The metric is present but an expected value is absent. |
| `unparsed` | Source value exists but normalization could not parse it. |
| `datatype_mismatch` | The occurrence's datatype conflicts with the metric-class contract. |
| `not_applicable` | The source explicitly states that the metric does not apply. |
| `unknown` | The processor cannot yet classify the value state. |

These are governed ontology terms, not a closed database enum. New value states can be added without
schema surgery. The assertion schema permits no object literal only when the governed value state
means that no source value exists; DR4 defines the required payload for every other state.

A missing-value instance participates in Review Document. It can support findings such as “the
required metric is mentioned but no value is supplied,” distinct from “the metric is absent from the
document.” A datatype mismatch is a syntactic conflict even when no determination about real-world
correctness is possible.

### 3.6 DR6 — Persist first-class, governed relations among instances

Assertions sharing a canonical metric class form an instance set. Members of the set may be:

* identical and therefore converged;
* equivalent after normalization or unit conversion;
* stronger or weaker;
* conflicting;
* syntactically incompatible, including datatype mismatch;
* missing, unparsed, or unknown in value state;
* incomparable because conditions, scopes, or dimensions differ; or
* related in ways not yet known when this ADR is written.

`kb.assertion_relations.relation_term_id` becomes the authoritative relation type. The legacy
`relation_kind` column is mapped during migration, becomes read-only compatibility data for one
release, and is then removed; there is no indefinite dual-write contract. Initial relation terms
include:

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

The vocabulary is extensible without changing a database CHECK constraint.

Each relation records:

* both assertion IDs;
* relation term and direction;
* status and lifecycle;
* derivation method and rule version;
* confidence;
* rationale and structured comparison evidence;
* producer/model/prompt when an LLM participated;
* creation and modification actors/times; and
* supersession or reversal history.

Only one direction is stored. Inverse relations are governed metadata and are derived at read time.
For symmetric relations, endpoints are stored in ascending assertion-ID order. For directional
relations, the stored direction carries the declared meaning (`stronger_than`, for example) and its
inverse is projected; an inverse term cannot be independently inserted for the reversed endpoints.

Relation terms belong to governed relation families. The semantic-comparison family contains
`equivalent_to`, stronger/weaker, conflict, syntactic conflict, and incomparable verdicts. At most
one active semantic-comparison verdict exists for the same canonical endpoint pair, applicability
context, and governing comparison decision/rule set—not merely one per relation term. Supersession
and other orthogonal families have their own uniqueness contracts. Re-evaluation supersedes the
prior family verdict. If active rules disagree, the comparison decision becomes explicitly
`uncertain`/`conflicted`; the system does not persist several contradictory authoritative verdicts.

For the motivating example, both assertions belong to the Display Luminance class and have the same
subject and compatible conditions:

```text
A = lower bound 250 cd/m2
B = lower bound 300 cd/m2

B stronger_than A
A weaker_than B
```

The relation says nothing by itself about which source artifact is correct. Review Document may flag
the difference and use authority, applicability, or other evidence to assess it later.

Relation derivation uses satisfying-set semantics after strict comparability gates:

1. Resolve both instances to the same canonical metric class or to an explicitly comparable governed
   mapping.
2. Require compatible canonical subjects, quantity dimensions, conditions, applicability scope,
   modality, and valid time. A configured rule may declare a specific difference comparable; absent
   such a rule, the result is `incomparable_with` rather than a guessed ordering.
3. Interpret comparable requirement/capability constraints as sets of satisfying values. Equal sets
   are equivalent; a strict subset is stronger; a strict superset is weaker; disjoint sets conflict
   only when both constraints are expected to apply simultaneously; all other cases are incomparable.
4. Do not apply stronger/weaker semantics to observations merely because their point values differ.
   Comparable observations are equivalent when canonically equal within a governed tolerance. They
   conflict only when a rule establishes the same measurement event/context and mutually exclusive
   values; otherwise they are distinct observations.
5. A class-contract datatype failure is first a per-assertion `datatype_mismatch` value state. A
   pairwise `syntactically_conflicts_with` relation is created only when a governed rule compares it
   with another instance under the same class and applicability context.
6. Missing, unparsed, and unknown values do not receive stronger/weaker relations until their values
   become comparable.

The comparison rule registry is keyed by assertion kind/modality, comparator/value form, quantity
dimension, condition/applicability policy, and rule version. This makes relation results testable and
prevents interval mathematics from being applied to semantically different assertion kinds.

### 3.7 DR7 — Canonicalize duplicate metric classes through mappings plus redirects

`kb.ontology_mappings` remains the governed store for `exact`, `close`, `broad`, `narrow`, and
`related` term mappings. It is extended as needed to carry method, confidence, evidence, and producer
provenance consistently with assertion relations.

An accepted exact mapping is the semantic decision that two term IDs represent the same logical
metric. Operational canonicalization additionally requires a redirect/merge record:

```text
kb.ontology_term_redirects
    absorbed_term_id
    canonical_term_id
    decision/mapping reference
    reason and provenance
    effective and reversal state
```

Terms are not hard-deleted. Reads follow redirects to the canonical survivor, while history can
still explain which original term an occurrence used and why it was redirected.

Observed and canonical class references are distinct. The class-resolution decision preserves the
immutable concept/term IDs observed at processing time; `kb.metrics.metric_definition_term_id` and
the assertion's canonical class reference are current materialized resolutions. Repointing updates
the current resolution but never erases the observed reference or decision history.

Term redirects have the following invariants:

* one active redirect per absorbed term;
* no self-redirects or cycles;
* redirect-chain resolution under the ontology identity mutation lock;
* deterministic path compression as a projection only, with original decisions retained;
* no redirect from a canonical survivor while active dependents are being rewritten; and
* reversal implemented as a new superseding decision, not deletion of history.

Survivor selection is deterministic where possible: released and explicitly curated terms outrank
auto-promoted terms; otherwise the oldest stable eligible term wins. A decision may override that
ordering with a recorded rationale.

Concept reconciliation and term reconciliation execute as one coordinated identity transaction.
Two auto-promoted terms derived from two candidate concepts are not sufficient evidence that the
concepts differ. The existing concept-merge conflict gate is changed:

* distinct curated or explicitly `never_merge` terms may block a concept merge;
* distinct auto-promoted terms trigger term-identity adjudication;
* an accepted same-metric decision redirects one term, merges/repoints the concepts and alignments,
  and updates dependent metric/assertion canonical references; and
* a rejected identity decision records `never_merge` or an appropriately scoped negative decision.

After canonical assertion writes are cut over, a forward term merge never updates only the
assertion's class column. Because the class term is part of canonical claim identity, the identity
transaction operates evidence-first: for every affected evidence occurrence it resolves the new
canonical class, recomputes the canonical claim payload, creates or finds the destination claim
identity, converges evidence and current assertions, writes assertion redirects, supersedes obsolete
identity current pointers and affected relations, and then rebuilds projections. If formerly
distinct classes produce an identical claim after the merge, their assertions converge in that
transaction. Partial class-reference rewrites that leave old claim digests or payloads active are
forbidden.

During initial migration, before shadow claim identities are validated, term reconciliation creates
term redirects, immutable resolution decisions, and current class-resolution projections only. It
does not rekey or converge legacy assertions. Phase 3 computes shadow claim identity against those
redirect-resolved classes; Phase 4 performs the first historical convergence. This separates safe
initial migration from the post-cutover steady-state transaction above.

Reversal after assertion convergence is a controlled split. The system replays each evidence row's
immutable observed class reference through the superseding class-resolution decision, recomputes its
canonical claim payload, creates or finds the resulting claim identity/assertion, and transactionally
reassigns evidence. It then supersedes affected assertion redirects and relations and rebuilds
dependent projections. The before/after evidence-membership snapshot on the original merge decision
is the audit and recovery boundary; a term redirect alone is never assumed sufficient to reconstruct
the split.

### 3.8 DR8 — Resolve autonomously through deterministic, statistical, and LLM stages

The canonical metric resolver uses the following ordered stages:

1. **Deterministic:** stable IDs and redirects, exact governed mappings, normalized labels and
   aliases, exact class contracts, canonical units, value/datatype rules, and canonical claim keys.
2. **Rule/statistical:** fuzzy lexical matching, embeddings, shared quantity kind, compatible
   subjects, class applicability, ontology neighborhood, and corpus evidence.
3. **LLM adjudication:** decide whether unresolved candidates express the same logical metric,
   identify missing distinctions, classify value state, or propose instance relations when the
   earlier stages are insufficient.
4. **Policy decision:** accept, reject, keep uncertain, or defer based on evidence, confidence,
   risk class, and configured thresholds.

Human review is optional at every stage. It can merge, split, override, or lock decisions but is not
a prerequisite for document processing or ordinary semantic availability.

The existing principle that an LLM does not directly write active governed content is retained as an
ownership boundary, not as a requirement for human approval. An LLM produces a structured proposal
and evidence; a deterministic, versioned policy engine owns the autonomous activation decision.
This permits meaningful LLM use while keeping activation attributable, reproducible from recorded
inputs where possible, and reversible.

Uncertain output does not disappear and does not fail the whole document. It remains queryable with
resolution state and confidence. Consumers choose risk-appropriate thresholds. Review Document may
show or use uncertain candidates explicitly; it must not silently present them as exact identity.

### 3.9 DR9 — Review Document uses ontology identity first and similarity as fallback

Review Document retrieves comparable metric instances in this order:

1. same canonical `metric_definition_term_id` after redirect resolution;
2. governed exact/close/broad/narrow/related metric mappings appropriate to the review task;
3. compatible subject, quantity kind, class applicability, and ontology neighborhood;
4. lexical/vector similarity; and
5. LLM adjudication for remaining high-value ambiguity.

The first channel is authoritative class membership. Later channels discover candidates; they do
not silently turn similarity into identity. Retrieval and comparison are separate stages: every
retrieved pair must pass DR6's subject, dimension, assertion-kind/modality, condition, applicability,
and valid-time gates before Review Document presents a semantic comparison. A retrieved but
non-comparable candidate may still be shown as context, explicitly labeled with its discovery method
and failed comparability gates.

Mapping traversal is task-scoped and directional. `exact` may join canonical candidate sets;
`close` only proposes a candidate; `broad` and `narrow` are traversed only when the selected review
rule declares that direction useful; `related` never establishes comparability by itself. Candidates
found through multiple channels are deduplicated by canonical assertion identity while preserving
all contributing discovery reasons.

Review payloads include canonical metric term ID, normalized assertion ID, value state, relation
type/status/confidence, and evidence provenance. Review Document must distinguish:

* metric absent;
* metric present with missing value;
* metric present with unparsed value;
* datatype or syntactic conflict;
* semantically stronger/weaker/equivalent constraints;
* unresolved or uncertain class identity; and
* a likely similar metric found only through fallback retrieval.

“Metric absent” is asserted only relative to a named, versioned ontology profile or other governed
applicability contract that declares the metric expected for the subject and review scope. Without
that expected set, Review Document may say only “no occurrence found in the searched scope.” This
keeps corpus retrieval failure from becoming a false completeness finding.

If semantic processing is incomplete, Review Document continues through its existing fallback paths
and labels the resolution state. Semantic enrichment improves correctness but does not become a
hard availability dependency.

### 3.10 DR10 — Make identity and relation processing idempotent, reversible, and observable

Every identity or relation decision must answer:

* what was compared;
* what canonical class and instances resulted;
* which deterministic rules, statistical signals, or LLM calls participated;
* which policy and thresholds produced the verdict;
* what evidence supports it;
* what was merged, redirected, or left unresolved;
* how to reverse or supersede the decision; and
* which downstream projections require rebuilding.

Processors are idempotent. Re-running the same versioned inputs does not create duplicate terms,
assertions, evidence, or relations. Changed semantic inputs create explicit new decisions and
targeted projection invalidation rather than untraceable mutation.

## 4. Alternatives Considered

### 4.1 Create `kb.ontology_term_instances`

Rejected. A dedicated instance table provides attractive class-instance naming but duplicates most
of `kb.semantic_assertions`: subject, value, conditions, lifecycle, revisioning, evidence, and
provenance. Linking the new instance back to an assertion would create two sources of truth and an
additional consistency boundary without adding required semantics.

### 4.2 Add a generic ontology-instance layer between terms and assertions

Deferred. A generic `ontology_instances` abstraction could eventually serve non-metric domains, but
the required identity and lifecycle contracts are not yet demonstrated across those domains. Metrics
already have a suitable first-class instance object in `kb.semantic_assertions`.

### 4.3 Keep occurrence-derived assertions and connect all duplicates with relations

Rejected. This preserves unnecessary duplicate canonical claims, makes every query traverse a
duplicate graph, and allows contradictory lifecycle states for what should be one normalized
instance. Exact identity should converge; relations represent genuine semantic differences or
temporary uncertainty.

### 4.4 Require human approval for semantic identity

Rejected. It makes throughput proportional to reviewer capacity and leaves the ontology unusable at
document-processing scale. Human correction remains valuable, but evidence, policy, confidence,
sampling, and reversibility manage autonomous risk.

### 4.5 Use only deterministic rules

Rejected. Deterministic normalization handles values, units, aliases, and many comparisons well but
cannot reliably decide all cross-language, context-sensitive, or domain-specific equivalence cases.
LLM adjudication is an explicit supported stage, not an accidental side channel.

### 4.6 Use embeddings as semantic identity

Rejected. Embeddings are a candidate-generation signal. They are valuable for recall but cannot by
themselves justify exact identity, redirects, or assertion convergence.

## 5. Implementation Sequence

Implementation must be proposed and tracked through a separate OpenSpec change. The intended order
is:

### Phase 1 — Schema and governed vocabulary

1. Seed governed class-resolution-state, value-state, and assertion-relation terms.
2. Add typed metric-class, class-resolution-state, value-state, and claim-identity references to
   semantic assertions.
3. Create the semantic claim-identity registry and semantic-assertion redirects.
4. Make governed `relation_term_id` the assertion-relation source of truth and add decision metadata,
   confidence, evidence, lifecycle, supersession, and reversal support.
5. Add ontology-term redirects, immutable class-resolution decisions, and required mapping
   provenance.
6. Add shadow canonical payload/key columns and indexes without changing production reads or writes.

### Phase 2 — Metric-class reconciliation

1. Detect duplicate auto-promoted and curated metric terms using deterministic signals first.
2. Run statistical/LLM adjudication only for unresolved candidates.
3. Apply autonomous policy decisions and create exact mappings plus redirects.
4. Create term redirects, immutable resolution decisions, and current metric/keyword class-resolution
   projections. Do not rekey or converge legacy assertions in this phase; Phase 3 must first compute
   and validate their redirect-resolved shadow identities.
5. Change the concept merge gate so auto-promoted term differences invoke reconciliation rather than
   automatically blocking a merge.

### Phase 3 — Shadow canonical assertion identity

1. Compute canonical keys without changing writes.
2. Populate the identity registry and assign shadow claim IDs, reusing one registry row only after
   canonical payload equality is verified.
3. Report exact convergence groups, class fragmentation, collisions, stronger/weaker pairs,
   conflicts, missing values, datatype mismatches, and unresolved cases.
4. Sample outcomes and tune deterministic, statistical, LLM, and policy thresholds.
5. Version all identity inputs and rules and produce a complete assertion/evidence redirect plan.

### Phase 4 — Converge history, enforce uniqueness, then cut over writes

1. Enter the bounded identity-migration write mode so old and new writers cannot race.
2. Converge historical duplicates, attach evidence to survivors, and create assertion redirects with
   before/after evidence membership.
3. Validate that every claim identity has at most one current assertion and that every digest reuse
   has byte-equal canonical payload.
4. Install and validate the identity-registry uniqueness constraint and current-assertion ownership
   contract.
5. Switch association writes to transactional identity-registry find-or-create under a row/advisory
   lock, then leave migration mode.
6. Derive and persist instance relations with idempotent rule ownership.
7. Rebuild affected semantic projections and comparison data.

### Phase 5 — Review Document integration

1. Add canonical term/assertion/value-state/relation fields to review queries and payloads.
2. Make canonical class membership the first retrieval channel.
3. Retain current object/category/vector paths as explicitly labeled fallbacks.
4. Expose missing, malformed, stronger/weaker, equivalent, conflicting, incomparable, and uncertain
   outcomes in findings and operator diagnostics.

## 6. Migration and Backfill Safety

Migration is additive until shadow validation passes.

* Existing `kb.metrics` rows and source provenance are never deleted or coalesced.
* Existing assertions remain addressable through redirects after convergence.
* Observed class references and resolution decisions remain immutable even when current canonical
  references are repointed.
* Backfill operates in bounded, restartable batches with dry-run counts and decision reports.
* Term reconciliation processes dependencies transactionally and records the before/after graph.
* Assertion convergence records before/after evidence membership; reversal replays evidence through
  the superseding class decision and recomputes claim identities rather than guessing how to split.
* Redirects are single-active-target, acyclic, lock-protected, and reversible only through a
  superseding decision.
* Canonical-key collisions are treated as diagnostic failures until their canonical serialization is
  shown to be equal; hash equality alone never merges data.
* Review Document retains fallback retrieval throughout rollout.

Required pre-cutover reports include:

* terms and concepts proposed to converge;
* assertions proposed to converge and their evidence counts;
* assertions sharing a class but receiving semantic relations instead of convergence;
* unresolved class and value states;
* relation counts by method, confidence, and status;
* changes to Review Document candidate sets; and
* reversible identifiers for every proposed absorbed term/assertion.

## 7. Acceptance Criteria

### 7.1 Class identity

* Approved aliases and translations of the same logical metric resolve to exactly one canonical
  `kb.ontology_terms.term_id` after redirect resolution.
* Similar-looking metrics with different quantity kinds, scopes, or definitions remain distinct.
* Duplicate auto-promoted terms can be reconciled without the existing concept-alignment gate
  creating a circular block.
* A post-cutover term merge recomputes affected claim identities and converges assertions that become
  identical; no assertion retains a canonical payload keyed by the absorbed class.

### 7.2 Instance identity and evidence

* Two occurrences with identical canonical subject, metric class, normalized value, unit, and
  conditions resolve to one semantic assertion with two evidence rows.
* Source record, metric ID, wording, spans, model, and prompt remain independently queryable.
* New evidence does not create an assertion revision.
* Two different unparsed strings or datatype-mismatched values do not converge merely because they
  share subject, class, and value state.
* Every absorbed assertion identity resolves to one acyclic canonical redirect target and can be
  split through recorded evidence membership and superseding class decisions.

### 7.3 Instance relations

* `display luminance >= 300 cd/m2` is `stronger_than` `display luminance >= 250 cd/m2` when subject
  and applicability are compatible; the inverse is queryable as `weaker_than`.
* Unit-equivalent values, such as compatible canonical representations of the same luminance, either
  converge or receive an explainable `equivalent_to` relation when convergence is intentionally
  deferred.
* Different value datatypes produce a syntactic conflict when the class contract requires one
  datatype.
* Conflicts are flagged without declaring either source correct or incorrect.
* Unknown future relation terms can be introduced without altering a database relation-kind CHECK.
* Requirement stronger/weaker results follow satisfying-set subset rules; observations do not inherit
  stronger/weaker semantics from numeric ordering.
* Exactly one authoritative active semantic-comparison verdict exists per canonical endpoint pair,
  applicability context, and governing rule set; inverse relations are derived at read time and
  contradictory rule outputs become an uncertain/conflicted decision.

### 7.4 Missing and uncertain information

* A metric occurrence with no value creates or links to a `missing`-state normalized instance rather
  than disappearing.
* Missing metric and present metric with missing value are distinguishable.
* Unparsed, datatype-mismatch, not-applicable, unknown, and unresolved-class outcomes remain
  queryable and do not block the document pipeline.
* An accepted metric assertion always has a resolved class; unresolved-class normalized rows remain
  explicitly non-accepted and are available to fallback retrieval.

### 7.5 Autonomous operation

* No normal semantic-processing stage requires human approval.
* Deterministic methods run before statistical or LLM methods.
* LLM proposals can be autonomously activated only through a versioned policy decision with full
  provenance; LLM code does not bypass the governed write path.
* Human corrections can override and lock decisions, and every autonomous merge/relation is
  reversible or supersedable.

### 7.6 Review Document

* Review Document retrieves same-class metric instances before similarity-only candidates.
* It explains whether a candidate came from canonical identity, governed mapping, structural
  compatibility, similarity, or LLM adjudication.
* It identifies equivalent, stronger, weaker, conflicting, syntactically conflicting, missing,
  unparsed, incomparable, and uncertain outcomes.
* It continues operating through labeled fallback retrieval when ontology processing is incomplete.

### 7.7 Competency and regression tests

The OpenSpec change must implement at least:

* CQ-M02 positive and negative fixtures from ADR `2026072901`;
* multilingual and alias-based class convergence;
* same-label/different-quantity negative identity;
* post-cutover term merge causing claim rekeying and assertion convergence;
* exact assertion convergence with multiple evidence;
* unit-normalized equivalence;
* lower- and upper-bound stronger/weaker relations;
* interval overlap, disjointness, and incomparability;
* distinct-unparsed-value identity, datatype conflict, and missing-value cases;
* autonomous deterministic and LLM-assisted decisions;
* human override, evidence-aware assertion split, term/assertion redirect reversal, redirect-cycle
  rejection, and `never_merge` behavior;
* idempotent concurrent processing; and
* Review Document canonical-first and fallback behavior.

CQ-M02 and the class-to-instance query are release gates, not documentation-only aspirations.

## 8. Consequences

### 8.1 Positive

* Ontology classes, normalized instances, occurrences, and evidence gain clear ownership boundaries.
* The same logical metric has one canonical governed identity.
* Equivalent source claims converge without losing provenance.
* Meaningful differences become queryable relations instead of isolated rows.
* Missing and syntactically invalid values become first-class review signals.
* Review Document gains deterministic semantic grouping while retaining broad similarity recall.
* Autonomous processing remains operationally viable, with LLM assistance where necessary.

### 8.2 Costs and risks

* Canonicalization and redirects add migration and query complexity.
* A false class merge has wider impact than a false similarity match.
* LLM adjudication introduces cost, latency, and nondeterminism.
* Canonical claim identity must be versioned carefully as conditions and applicability mature.
* Relation derivation can become quadratic within large class-instance sets unless candidate blocking
  and incremental recomputation are designed explicitly.
* Historical backfill may expose previously hidden contradictions and stale projections.

These risks are mitigated through staged shadow computation, bounded candidate generation,
confidence/risk policy, complete provenance, reversible redirects, and optional human correction.

## 9. Relationship to Earlier Decisions

### ADR `2026072901`

This ADR implements and sharpens its intended metric-definition row identity and CQ-M02 behavior.
It retains the principle that an LLM does not directly bypass governed activation, while clarifying
that human approval is not required: a deterministic policy engine may autonomously activate an
LLM-supported decision.

Any wording that implies ontology candidates must wait for mandatory human activation is superseded
for this metric identity/relation workflow by DR8.

### ADR `2026081201`

This ADR retains automatic metric-term creation but resolves OD2: reconciliation must detect and
merge/redirect duplicate auto-promoted terms, not only keyword concepts. Distinct auto-promoted
alignments no longer automatically prove that two concepts differ.

### ADR `2026081401`

Governed `value_range_type` mapping remains part of deterministic normalization. This ADR adds the
higher-level class contract, canonical instance identity, governed value state, and relations that
consume the normalized result.

### User manual §6.11

This ADR adopts §6.11's defect finding and replaces occurrence-derived assertion identity with the
class-instance-evidence model defined here.

## 10. Open Questions for the OpenSpec Design

The following are implementation questions, not unresolved architectural direction:

1. The initial confidence/risk thresholds for autonomous exact term merges and LLM-assisted
   decisions.
2. The precise canonical serialization and versioning contract for conditions, procedures, and
   time applicability.
3. How Review Document presents uncertain and conflicting instance sets without overwhelming users.

These questions must be resolved in the implementation design and tested before production cutover.
