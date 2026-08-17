# ADR 2026081801 — Lossless Semantic Processing and Knowledge Preservation

**Date:** 2026-08-18 \
**Status:** Proposed \
**Component:** ChenWeb — document processors, artifact stores, semantic normalization, ontology association, semantic assertions, error reporting, retry, projections, and Review Document \
**Authors:** Chen Ding (with Codex) \
**Related:** ADR `2026072901` (ontology platform and adaptive pipeline), ADR `2026081401` (governed metric vocabulary and Phase D failure reporting), ADR `2026081701` (ontology object classes, instances, and relations), user manual `metric-assertion-semantic-processing-v1.2-en.md` \
**Tags:** lossless processing, raw preservation, semantic findings, non-blocking pipeline, invalid knowledge, provenance, retry, ontology

## 1. Decision Summary

SemOS stores source-backed claims even when they are malformed, incomplete, ambiguous,
nonconforming, conflicting, or not yet understood.

A content-level semantic problem must never cause an extracted artifact to disappear from later
semantic processing. The processor preserves the raw occurrence, creates a raw-preserved semantic
instance when the artifact family supports instances, records explicit outcome states and errors,
links the source evidence, and continues. Consumers decide whether a flagged claim is suitable for
their task.

Only system execution failures—such as inability to read required input, invoke a required service,
commit required data, or preserve the result safely—fail a processor run. Vocabulary gaps, parser
uncertainty, class ambiguity, missing values, datatype mismatches, and contract violations are
semantic findings, not runtime failures.

## 2. Context

### 2.1 Current processing can lose the most informative artifacts

The current metric pipeline can persist a raw `kb.metrics` row and then stop semantic processing
when a value-range type does not map to a governed bucket. `normalize_assertions` may leave the
candidate unparsed; `associate_semantics` may defer it; ADR `2026081401` additionally requires an
unreviewed mapping to fail both `extract_metrics` and `associate_semantics` so operators notice it.

This makes an operational alert visible, but it prevents the affected metric from becoming a
semantic instance. Review Document and other consumers then miss the metric or see only the raw
artifact through fallback retrieval.

The inference “normalization failed, therefore the source claim is invalid and should not enter the
knowledge base” is unsound. Failure may mean:

* the source is malformed;
* the source intentionally uses a special value;
* the parser does not understand a valid form;
* a governed mapping is incomplete;
* the ontology class contract is incomplete;
* several class candidates are plausible;
* the source conflicts with another source; or
* required contextual evidence has not yet been processed.

Every case is knowledge. Dropping the artifact hides both the source claim and the system's own
knowledge gap.

### 2.2 Source fidelity and semantic endorsement are different

SemOS is a knowledge store, not a truth filter at ingestion time. Persisting a source-backed claim
means:

> The source expressed this claim, and SemOS preserved what it could determine about it.

It does not mean:

> The claim is true, valid, internally consistent, or conformant with an ontology class.

Truth, authority, applicability, conformance, and comparison are independent evaluations. A source
claim can be faithfully stored while being flagged as nonconforming or conflicting.

### 2.3 Raw and normalized representations have different ownership

Raw artifact tables such as `kb.metrics` preserve what document processing extracted.
`kb.semantic_assertions` represents normalized or raw-preserved ontology instances.
`kb.assertion_evidence` explains which source artifacts support or contradict each instance.

`kb.assertion_evidence` is provenance. It must not become a second normalized artifact store or
overwrite raw values with canonical values.

### 2.4 Pipeline failure and semantic outcome are different axes

A processor can execute successfully and still discover many semantic problems. Conversely, a
processor can fail operationally before it can make any trustworthy semantic determination.

The current status model and ADR `2026081401` conflate these axes for mapping misses. This ADR
separates them:

| Axis | Example | Effect |
|---|---|---|
| Execution status | Database transaction failed. | Processor fails; retry is operationally required. |
| Semantic outcome | Raw range type has no approved mapping. | Processor succeeds with findings; raw claim and semantic instance remain available. |
| Consumer usability | Review rule requires a normalized numeric interval but value is unparsed. | That comparison produces no verdict; other consumers may still use or display the claim. |

### 2.5 Scope

This ADR establishes cross-cutting behavior for all artifact families and semantic stages. Metrics
are the first vertical slice because the current failure is confirmed there and ADR `2026081701`
requires this decision before its new metric-instance pipeline.

An artifact family does not claim compliance until its extractor, normalizer, association logic,
projections, retry path, and consumers preserve and expose its non-success semantic outcomes.

## 3. Decision

### 3.1 DR1 — Apply the lossless semantic-processing invariant

For every source-backed artifact that extraction can identify, SemOS must produce one of:

1. a normalized semantic instance with source evidence;
2. a raw-preserved semantic instance with explicit unresolved, malformed, missing, ambiguous, or
   nonconforming state and source evidence; or
3. when the artifact cannot yet be instantiated by that family, a durable unresolved semantic
   occurrence and outcome record that remains eligible for later materialization.

The system must not silently skip, delete, or make the artifact unreachable because semantic
normalization is incomplete.

For artifact families already modeled as ontology object instances, including metrics under ADR
`2026081701`, option 2 is mandatory. They do not fall back to option 3.

### 3.2 DR2 — Preserve raw data independently from every normalized representation

Raw source fields are immutable processing inputs. Normalized fields are derived interpretations.

The following invariants apply:

* Raw values, units, datatypes, labels, conditions, source wording, and line spans are preserved.
* Normalization never overwrites the raw representation.
* A failed parse preserves the exact offending value and declared/inferred datatype.
* A mapping decision records both raw input and selected canonical value.
* Human or autonomous correction creates a new decision or derived revision; it does not rewrite
  what the source originally expressed.
* Deletion or reprocessing follows existing provenance retention rules and never deletes canonical
  history merely to make the current projection look clean.

Artifact-family tables remain the primary raw occurrence stores. Where their existing columns do
not preserve a complete structured source representation, they gain an immutable/raw payload or
equivalent family-specific fields rather than relying on log text.

The ownership rule is:

* the artifact-family row is authoritative for the current raw occurrence;
* the assertion's raw payload is an immutable normalization-time snapshot used for claim identity
  and history, and records the source occurrence revision/fingerprint from which it was copied;
* evidence quote/spans are provenance excerpts, not authoritative copies of the artifact payload;
* an outcome's `raw_fragment` is populated only when no identified artifact row can preserve that
  content; and
* derived search/projection copies are rebuildable caches.

At assertion creation, the raw snapshot fingerprint must match the referenced occurrence revision.
Reprocessing creates or supersedes the occurrence/current link according to the family lifecycle; it
does not mutate an historical assertion snapshot to resemble the new extraction.

### 3.3 DR3 — Separate execution failures from semantic findings

Processor outcomes are classified as follows:

| Category | Examples | Processor status | Semantic continuation |
|---|---|---|---|
| `system_failure` | Required input unreadable, database unavailable, transaction rollback, required model/service invocation failed with no usable output, invariant violation prevents safe persistence. | `failed` | Stop the affected dependency branch; retry operationally. |
| `source_or_output_unrecoverable` | Processor output is so malformed that no artifact can be identified or safely preserved. | `failed` | Preserve invocation/raw output and error where possible; retry processor. |
| `semantic_finding` | Mapping missing, value unparsed, datatype mismatch, class provisional/ambiguous, contract violation, missing value, source conflict. | `completed` with mandatory finding summary | Persist artifact, instance/outcome, evidence, and continue. |
| `semantic_success` | Required normalization and validation capabilities produced usable output. | `completed` | Persist and continue. |

Execution status is canonically binary: `completed` or `failed`. A completed run has mandatory
`finding_count`, highest finding severity, and finding-summary counts by governed finding term. UIs
may display the derived phrase “completed with findings,” but it is not a third persisted execution
status. The legacy schema projects `completed` to `success` and `failed` to `failed`.
`has_failed_proc` and failed-processor retry queues include only `failed` execution.

Content-level findings can still carry `error` severity for users. Severity does not convert them
into execution failures unless SemOS cannot safely persist or continue.

“Cannot continue” means that required infrastructure or the required atomic persistence set cannot
complete. Inability to parse, classify, validate, compare, or project a semantic result remains a
finding when the input, outcome, provenance, and an explicit no-result reason can be durably
committed. Optional enrichment-service failure is a finding when the stage contract declares and
persists a deterministic fallback; failure of a service declared required by that stage is an
execution failure.

### 3.4 DR4 — Persist structured semantic outcomes

A generic append-only store records processing outcomes:

```text
kb.semantic_processing_outcomes
  id
  outcome_key
  input_record_id
  artifact_type
  artifact_id                 # nullable only when no artifact could be identified
  assertion_id                # nullable until/when the family supports an instance
  stage_term_id
  disposition_term_id         # normalized, raw_preserved, not_applicable, or no_result
  finding_count
  highest_severity_term_id
  raw_fragment                # only when no normal artifact field can preserve it
  dependency_fingerprint      # aggregate of stage and child-finding dependencies
  processor_name/version
  extraction_run
  model/prompt_version
  supersedes_outcome_id
  input_fingerprint
  active
  last_seen
  create_time/create_by
```

The table is append-only except for idempotent `last_seen` and the transactionally maintained active
projection. Every required semantic-stage attempt, including success, has exactly one outcome
envelope or reuses an identical existing envelope. `outcome_key` is the deterministic hash/encoding
of `input_record_id`, `artifact_type`, `artifact_id`, and `stage_term_id`. `input_fingerprint`
identifies the exact raw occurrence revision. The database enforces uniqueness on
`(outcome_key, input_fingerprint, dependency_fingerprint)`.

An outcome envelope has zero or more append-only typed findings:

```text
kb.semantic_processing_findings
  id
  outcome_id
  finding_key
  dimension_term_id           # mapping, value, class, conformance, identity, conflict, ...
  finding_term_id
  severity_term_id
  retry_state_term_id
  error_code
  details
  dependency_fingerprint
  supersedes_finding_id
  active
  last_seen
  create_time/create_by
```

`finding_key` is deterministic within the outcome's family-declared decision scope. The database
enforces uniqueness on `(outcome_id, finding_key, dependency_fingerprint)` and exactly one active
finding per `(current outcome, finding_key)`. Thus one stage can simultaneously report, for example,
`datatype_mismatch`, `contract_violation`, and `source_conflict` without duplicating its stage
outcome. `finding_count` and highest severity are transactionally derived from the current child
set; reports count child `finding_term_id` values, not the envelope disposition.

An unchanged replay reuses that row and only advances `last_seen`; it does not append or re-alert.
A changed input or dependency inserts a new row, marks the former active row superseded in the same
transaction, and makes exactly one row active per `(outcome_key, current input occurrence)`. Logs
alone are never the outcome source of truth.

Reusable vocabulary findings and occurrence aggregation are separate from artifact outcomes. A
mapping table may count many artifact-specific findings, but two artifacts never share one outcome
envelope or child finding row.

Initial governed disposition terms are:

```text
semantic:normalized
semantic:raw_preserved
semantic:not_applicable
semantic:no_result
```

Initial governed finding terms include:

```text
semantic:mapping_unresolved
semantic:mapping_ambiguous
semantic:unparsed
semantic:value_missing
semantic:value_unknown
semantic:datatype_mismatch
semantic:contract_violation
semantic:class_provisional
semantic:class_ambiguous
semantic:identity_evidence_conflict
semantic:source_conflict
semantic:no_verdict
```

Disposition, dimension, and finding terms are extensible ontology terms, not closed database enums.
Stable machine-readable `error_code` values identify programmatic cases; human details do not
participate in identity.

### 3.5 DR5 — Define cardinality and the atomic persistence boundary

For the metric vertical slice, one atomic current `kb.metrics` occurrence has exactly:

* one active supporting assertion link;
* one active semantic-processing outcome envelope for each adapter-declared required semantic stage,
  containing zero or more typed findings across the stage's declared decision scopes;
* one active class-resolution decision;
* zero or one current normalized value representation inside its assertion; and
* one raw occurrence revision/fingerprint preserved independently of normalization.

Many metric occurrences may converge on the same assertion. One metric occurrence does not fan out
to several current metric assertions; compound extractions must first split into atomic metric rows.

For each metric semantic stage, the atomic transaction includes all writes applicable to that
attempt:

1. idempotent mapping observation/upsert keyed by the distinct source occurrence, so retry does not
   increment occurrence counts again;
2. existing/provisional class and class-resolution decision preparation;
3. canonical claim find-or-create and assertion creation/reuse;
4. supersession of any prior current supporting evidence link and insertion/restoration of the new
   link;
5. the mandatory semantic-processing outcome envelope, complete child-finding set, and
   validation/error records; and
6. projection/retry invalidation records required for committed state.

The raw artifact occurrence must already be durably committed before this transaction begins. Run
status and aggregate finding summaries are derived after artifact transactions; crash recovery
recomputes them from committed outcomes. A transaction rollback leaves no new assertion, current
evidence link, resolution decision, mapping observation count, or outcome for that attempt.

Other artifact families declare their occurrence-to-assertion cardinality in their adapter, but
must retain the mandatory outcome, evidence, idempotency, and atomicity invariants.

### 3.6 DR6 — Persist raw-preserved semantic assertions

When an artifact family supports ontology instances, normalization always creates or reuses a
`kb.semantic_assertions` row.

The assertion contains, directly or through validation/outcome records:

```text
instance_of_term_id
class_identity_state_term_id
mapping_resolution_state_term_id
value_state_term_id
conformance_state_term_id
raw_text/raw_payload
normalized value fields when available
processing_error_details or linked outcome IDs
```

If no existing class resolves, the pipeline creates a provisional class. If the value cannot be
parsed, canonical identity includes a deterministic fingerprint of the raw value and observed
datatype. If the source mentions a metric but supplies no value, identity includes the explicit
`missing` state and semantic context rather than fabricating a value.

When several classes are plausible, the pipeline creates one deterministic provisional class for
the occurrence/identity cluster, stores that ID in `instance_of_term_id`, records
`class_identity_state = ambiguous_candidates`, and records every candidate term, score, method, and
evidence in the class-resolution decision table from ADR `2026081701`. No candidate class populates
authoritative class-derived normalized fields before resolution. Canonical claim identity uses the
provisional term ID plus raw semantic fingerprint, so ambiguous occurrences remain distinct unless
their provisional identity and raw claim are equal.

An ambiguous governed range-type mapping creates one assertion with
`mapping_resolution_state = ambiguous`, a `mapping_ambiguous` finding, and no authoritative bucket;
it does not create several interpretations. Its candidate buckets and evidence remain in the mapping
decision/finding details. A missing/proposed mapping similarly uses
`mapping_resolution_state = unresolved` and a `mapping_unresolved` finding. Mapping resolution and
value parsing are independent: when the literal itself parsed successfully, its normalized numeric
value and `value_state = present` remain populated even though bucket/type-dependent fields remain
empty. `value_state = unparsed` is used only when the literal value itself cannot be parsed.

The current `kb.semantic_assertions` constraint requiring an object reference or literal must be
revised so a genuine missing-value instance can exist. The revised constraint requires the payload
appropriate to its governed value state:

* `present`: normalized literal/reference required;
* `unparsed`, `datatype_mismatch`, or raw-valued `unknown`: raw payload required;
* `missing`: no fabricated object, but subject, class, applicability, and evidence required;
* `not_applicable`: explicit non-applicability context required.

Admission into `kb.semantic_assertions` means the claim is represented, not accepted as true or
conformant.

### 3.7 DR7 — Keep evidence as provenance

`kb.assertion_evidence` connects source occurrences to semantic assertions. It records artifact
identity, quote, spans, extraction run, model, prompt, confidence, evidence role, actor, and
lifecycle.

It does not own:

* canonical units or normalized values;
* class resolution state;
* conformance decisions;
* parser or mapping results; or
* the semantic instance's canonical identity.

Those belong to the assertion, class/claim resolution decisions, and semantic outcome records.
Many occurrences may support one assertion, and one generic artifact may support multiple
assertions. Metric extraction retains the separate invariant of at most one current supporting
instance link per atomic metric occurrence.

### 3.8 DR8 — Continue every downstream stage with capability-aware behavior

A downstream processor must not treat a flagged instance as nonexistent. It performs the operations
supported by the instance and its class capabilities and records an explicit outcome for operations
it cannot perform.

Examples:

* Search indexes both raw and normalized text when available.
* Class observed profiles include malformed/outlier observations without promoting them into the
  authoritative contract.
* Claim convergence uses raw-preserved identity rules for unparsed values.
* Comparison produces `no_verdict` or `incomparable_with` when required normalization is missing.
* Review Document displays the claim, raw value, state, error, class confidence, and evidence.
* Completeness checks distinguish absent artifact from present artifact with missing value.

“Do nothing” is not an acceptable terminal behavior. A processor that cannot perform its semantic
operation records why, preserves its inputs, and leaves a retryable outcome when appropriate.

### 3.9 DR9 — Model independent state dimensions

The system does not compress all uncertainty into one status. At minimum it keeps independent:

| Dimension | Examples |
|---|---|
| Execution | completed or failed; completed runs carry mandatory finding summaries |
| Class identity | resolved-existing, provisional-new, ambiguous-candidates, identity-evidence-conflict |
| Class definition/capability | identity-only, partially-defined, validated; can-instantiate, can-validate, can-compare, can-check-completeness |
| Mapping resolution | resolved, unresolved, ambiguous, not-required |
| Value | present, missing, unparsed, datatype-mismatch, unknown, not-applicable |
| Conformance | conforms, contract-violation, not-evaluated |
| Inter-instance relation | equivalent, stronger, weaker, conflict, syntactic-conflict, incomparable, no-verdict |
| Source authority/truth | source-specific authority, confidence, corroboration, contradiction; never inferred solely from admission |

These dimensions can coexist. For example:

```text
class identity: resolved-existing
class definition: validated for value checks
value: datatype-mismatch
conformance: contract-violation
execution: completed; finding_count > 0
```

### 3.10 DR10 — Replace failure retry with dependency-driven semantic retry

Execution failures use the existing failed-processor retry mechanism. Semantic findings use a
separate dependency-driven retry path.

Every retryable semantic outcome records a dependency fingerprint covering relevant versions and
decisions, such as:

* mapping table entry/revision;
* parser/normalizer version;
* class identity decision;
* class-contract revision and validator version;
* unit/quantity vocabulary release; and
* model/prompt version when an LLM participated.

Dependency fingerprints use canonical, versioned serialization. The retry queue is unique on
`(outcome_id, finding_id, target_dependency_fingerprint)`, where `finding_id` is nullable for a
whole-stage retry. Each outcome's dependency fingerprint is the canonical aggregate of its stage
dependency and current child-finding dependencies. Workers claim jobs transactionally using the
database's row-lock/skip-locked mechanism and record a lease/attempt token. Concurrent enqueue is an
idempotent conflict; concurrent execution cannot activate two outcomes. A stale job whose source
input or target dependency no longer matches records `stale` and performs no semantic writes.

When a dependency changes, the system schedules only affected outcomes. An unchanged fingerprint
reuses the existing outcome and does not generate repeated work or alerts. A changed dependency
produces a superseding outcome and, if semantic identity changes, the required assertion
revision/redirect and projection rebuild in one orchestrated transaction or recoverable saga with
an explicit completion marker.

Human involvement remains optional. Approved mappings and corrections may trigger retry, but
ordinary pipeline completion never waits for review.

### 3.11 DR11 — Report findings without producing failure storms

Every processor run reports:

* artifacts examined;
* normalized and raw-preserved instance counts;
* findings by governed finding term, severity, and retry state;
* new versus reused findings;
* downstream operations completed or skipped with explicit reasons; and
* actual system failures separately.

Repeated occurrences of one unresolved vocabulary value increment governed occurrence evidence and
reuse an existing finding identity where appropriate. Logs summarize per record/run rather than
emitting one alarm for every repeated artifact.

Operator and admin views expose findings and affected artifacts without requiring SQL. They must not
present the derived “completed with findings” label as if the document failed to process.

### 3.12 DR12 — Supersede ADR `2026081401` mapping-miss failure behavior

ADR `2026081401` remains authoritative for the governed
`kb.metric_value_range_type_map`, raw-value discovery, occurrence counts, proposed/approved/
ambiguous mapping states, artifact-level `value_range_type_error`, operator visibility, and the
Phase-C harness's ability to report genuine execution failures.

For execution status, this ADR supersedes only ADR `2026081401` DR3 and DR6's decision to make a
`status = 'proposed'` mapping miss fail `extract_metrics` and `associate_semantics`.

For semantic materialization and continuation, this ADR extends and, where necessary, supersedes
any earlier defer/skip behavior for proposed, ambiguous, absent, malformed, and recognized-special
range types: every identifiable metric now materializes exactly one current semantic instance and
stage outcome envelope, with the precise independent states and findings below. The governed mapping
workflow itself remains unchanged.

The revised behavior is:

1. Persist the raw metric exactly as extracted.
2. Upsert/increment the proposed mapping and preserve `value_range_type_error` as a finding.
3. Create a semantic assertion with `mapping_resolution_state = unresolved`, retain a parsed literal
   with `value_state = present` when possible, and use `value_state = unparsed` only when literal
   parsing also failed.
4. Record a semantic processing outcome envelope, its `mapping_unresolved` child finding, any
   independent value/conformance findings, evidence, and a summary log.
5. Return successful processor execution with findings if all required writes succeed.
6. Continue association, projection, indexing, and Review Document through capability-aware paths.
7. Retry affected outcomes when the mapping decision changes.

`associate_semantics` remains a vocabulary backstop but does not defer the metric out of the
knowledge base. A missing mapping is no longer placed in `has_failed_proc` or the failed-processor
retry queue.

The exact value-range disposition is:

| Input/mapping state | Prior behavior under ADR `2026081401` | New execution status | Mapping/value state | Disposition and findings | Retry trigger |
|---|---|---|---|---|---|
| Approved mapping | Normalize and continue. | `completed` | mapping `resolved`; parsed literal is `present`; authoritative bucket populated | disposition `normalized`; zero or more independent findings | Changed source or mapping revision. |
| Proposed mapping | DR3 and DR6 fail `associate_semantics` and `extract_metrics`; candidate remains deferred. | `completed` with finding summary | mapping `unresolved`; parsed literal remains `present`, otherwise `unparsed`; bucket fields empty | disposition `raw_preserved`; finding `mapping_unresolved`, plus any value/conformance findings | Mapping becomes approved/ambiguous or source changes. |
| Ambiguous mapping | Settled non-failure but remains unparsed/deferred. | `completed` with finding summary | mapping `ambiguous`; parsed literal remains `present`, otherwise `unparsed`; candidate buckets non-authoritative | disposition `raw_preserved`; finding `mapping_ambiguous`, plus any independent findings | Mapping decision or source context changes. |
| Absent range-type field | Ordinary non-failure deferral/absence behavior. | `completed`; finding only when class expects the field | mapping `not-required` when inapplicable; otherwise `unresolved`; value remains independently `present`, `missing`, or `unparsed` | disposition `normalized` or `raw_preserved`; `value_missing`/`mapping_unresolved` only when required | Source or class-contract revision changes. |
| Malformed/unparseable literal | Ordinary deferral/unparsed behavior. | `completed` with finding summary | mapping evaluated independently; value `unparsed`; exact raw literal retained | disposition `raw_preserved`; finding `unparsed`, plus mapping/conformance findings | Parser, mapping, source, or contract changes. |
| Recognized special value | Depends on approved mapping/parser support. | `completed` | mapping `resolved` when governed; value `present`, `unknown`, or `not-applicable` according to contract | disposition `normalized` when supported, otherwise `raw_preserved`; precise findings when nonconforming | Source, mapping, parser, or contract changes. |

The execution-status change supersedes ADR `2026081401` DR3 and DR6 only where they require a
proposed mapping to return a non-nil aggregate processor error and enter failed-processor status.
The table's semantic materialization rules replace any conflicting defer/skip behavior for every
listed state. ADR `2026081401`'s governed table, discovery, logging, artifact flagging, and genuine
Phase-C execution-failure decisions remain.

### 3.13 DR13 — Define unresolved semantic occurrences and family adapter compliance

When a family cannot yet create a semantic assertion, it persists:

```text
kb.unresolved_semantic_occurrences
  id
  occurrence_key
  input_record_id
  artifact_type
  artifact_id                  # nullable only if identification failed
  source_revision/fingerprint
  raw_payload
  provenance
  materialization_state
  resulting_assertion_id
  current_outcome_id
  supersedes_occurrence_id
  input_fingerprint
  dependency_fingerprint
  active
  lease_token/lease_expires_at
  last_seen
  create_time/create_by
```

`occurrence_key` is deterministic for the source scope and family. The current row is queryable
through the same generic semantic-discovery API as assertions. The database enforces uniqueness on
`(occurrence_key, input_fingerprint, dependency_fingerprint)` and exactly one active row per current
source occurrence. Identical replay advances `last_seen` rather than appending a duplicate; changed
input/dependencies create a superseding row and deactivate the former row transactionally.

Workers claim materialization with row locking and an expiring lease token. Materialization either
atomically creates/reuses the assertion, evidence, class-resolution decision, outcome envelope and
findings, updates `materialization_state`/`resulting_assertion_id`/`current_outcome_id`, and supersedes
the unresolved row, or performs those steps as a recoverable saga with a deterministic idempotency
key and explicit completion marker. A crash cannot leave a materialized assertion paired with an
active unresolved occurrence; reconciliation completes or rolls back the saga before exposing its
current projection. History remains append-only.

The lossless framework is generic; artifact semantics remain family-owned. Each registered artifact
family supplies a versioned adapter defining:

* its raw occurrence identity and raw payload fields;
* how an atomic source occurrence is recognized;
* the minimum raw-preserved semantic instance shape;
* provisional class behavior;
* value and conformance states it uses;
* canonical identity for normalized and raw-preserved cases;
* capability-aware downstream operations; and
* dependency fingerprints and retry triggers.

The adapter also enumerates its required semantic stages, the decision scopes/dimensions each stage
may report, and the disposition/capability contract for every stage. This declaration drives exact
outcome cardinality, conformance tests, and completeness reports.

Shared infrastructure owns outcome/unresolved-occurrence persistence, state vocabulary,
idempotency, retry scheduling, logging, and API query shapes. Family adapters must pass a shared
conformance suite before their lossless writer is activated.

An unregistered or not-yet-compliant family uses the generic unresolved-occurrence fallback; it may
not silently skip the artifact and may not advertise full semantic-instance compliance. A runtime
compliance registry reports adapter name/version, enabled writer mode, conformance-suite version,
and last verified result. Activation is refused when the registered adapter has not passed the
current suite.

## 4. Alternatives Considered

### 4.1 Fail processing whenever semantic normalization is incomplete

Rejected. It makes gaps visible but removes artifacts from semantic consumers, overloads operational
failure status, and can create retry storms that no retry can resolve until external knowledge
changes.

### 4.2 Store only raw artifacts and wait to create assertions until normalization succeeds

Rejected. Raw preservation is necessary but insufficient. Semantic consumers need a durable,
stateful object representing that the metric exists, what is unresolved, and how to retry it.

### 4.3 Put normalized values in `kb.assertion_evidence`

Rejected. Evidence explains provenance. Mixing normalized state into it creates competing instance
representations and makes many-occurrence convergence ambiguous.

### 4.4 Treat all persisted claims as correct facts

Rejected. Persistence establishes source fidelity, not truth. Conformance, authority, conflict, and
consumer suitability are separate dimensions.

### 4.5 Keep `kb.semantic_decision_candidates` as the failure store

Rejected for mature instance families such as metrics. A raw-preserved assertion and explicit
outcome record can represent the real state directly. Candidate tables remain appropriate only for
workflows with genuine alternative proposals awaiting a decision, not as a holding area for every
normalization problem.

### 4.6 Retry semantic findings through the failed-processor queue

Rejected. Most findings depend on a mapping, contract, or resolver change. Blindly re-running an
unchanged dependency wastes resources and repeats alerts without changing the result.

## 5. Implementation Sequence

Implementation must be proposed and tracked through OpenSpec changes.

### Phase 1 — Additive shared foundation and shadow evaluation

1. Define governed execution, semantic-outcome, value-state, class-state, and conformance terms.
2. Create `kb.semantic_processing_outcomes`, `kb.unresolved_semantic_occurrences`, current-state
   projections, retry records, and their uniqueness indexes.
3. Implement the transaction, idempotency, dependency-fingerprint, and adapter-conformance
   framework without changing production writer behavior.
4. Add binary execution-status summaries and retain the legacy `success`/`failed` projection.
5. Run the metric adapter in shadow mode and compare intended assertions, outcomes, and cardinality
   with the existing path; shadow mode performs no consumer-visible semantic writes.

### Phase 2 — Deploy compatible readers before enabling new writers

1. Make APIs, semantic projection, search, comparison, Review Document, reports, and retry tooling
   tolerate both legacy assertions and every new raw-preserved/ambiguous/missing state.
2. Make comparison record no-verdict/incomparability rather than dropping unsupported instances.
3. Expose raw value, normalized value, independent states, errors, and evidence in Review Document.
4. Deploy dual-read behavior and certify each consumer against the reader compatibility suite.
5. Keep default behavior on legacy writers until all required metric consumers are certified.

### Phase 3 — Enable the metric lossless writer behind a cutover gate

1. Extend metric assertion/value-state storage for raw-preserved and missing-value payloads.
2. Enable the new metric semantic transaction behind the named
   `LOSSLESS_SEMANTIC_WRITES_METRIC` gate only after Phase 2 certification.
3. Create assertions, class decisions, evidence, outcomes, and invalidations for mapped, proposed,
   ambiguous, absent, malformed, and special range types.
4. Stop returning processor errors solely for semantic mapping/normalization findings.
5. Preserve the admin mapping workflow and trigger targeted semantic retry after dependency
   changes.
6. Produce corpus reports proving every current metric has exactly one current supporting assertion
   link or an explicit, bounded migration exception.

### Phase 4 — Activate the generic fallback, then migrate additional families

1. Deploy and certify generic-discovery readers for unresolved occurrences.
2. Wire every registered extractor to generic fallback persistence and run the shared fallback
   conformance suite without changing current production behavior.
3. Backfill or explicitly report historical artifacts that were skipped before lossless processing.
4. Enable fallback writes behind the named global `LOSSLESS_SEMANTIC_FALLBACK_WRITES` gate, with an
   optional per-family deny switch for emergency isolation.
5. Confirm completeness reports show every new identifiable artifact has either a compliant
   instance or exactly one current unresolved occurrence.
6. Factor proven metric behavior into the shared adapter framework, then migrate provisions,
   entities, inventory items, products, relations, and other families one vertical slice at a time.

Before a family-specific writer gate is enabled, its adapter must pass the shared conformance suite
and its required consumers must pass dual-read compatibility. Until then, the enabled generic
fallback is mandatory.

## 6. Migration and Rollout Safety

* The migration is additive before behavior changes.
* Existing raw artifact rows are not rewritten or deleted.
* Existing failed/deferred candidates remain available until converted to assertions/outcomes or
  recorded as explicit migration exceptions.
* The metric vertical slice runs in shadow mode and reports how many previously deferred metrics
  would become raw-preserved instances, without exposing shadow rows to production consumers.
* All required readers deploy and pass dual-read compatibility before
  `LOSSLESS_SEMANTIC_WRITES_METRIC` can be enabled.
* Cutover compares artifact counts, exact current-link/stage-outcome cardinalities, finding counts,
  and Review Document visibility before disabling the old fail/defer path.
* Mapping observation, class resolution, assertion, current evidence, mandatory outcome,
  validation, and invalidation writes follow DR5's atomic boundary for one artifact attempt.
* Backfill is bounded, restartable, idempotent, and dependency-versioned.
* A rollback disables the writer gate and restores the legacy writer. It does not delete committed
  raw-preserved assertions or outcome history; dual-read consumers continue to understand them.
* Consumer APIs add state fields before changing default filtering behavior.
* Mixed-version operation is permitted only in the tested sequence: new dual-read consumers with
  old writers, followed by gated new writers. Old consumers must never run against enabled new
  writers.

Required pre-cutover reports include:

* raw artifacts with no semantic instance or explicit unresolved occurrence;
* instances by value, class identity, and conformance state;
* current proposed mappings and affected occurrence counts;
* old processor failures that become semantic findings;
* downstream no-verdict/skip reasons;
* retry queue size by dependency type; and
* Review Document result changes.

## 7. Acceptance Criteria

### 7.1 Losslessness

* Every identifiable metric occurrence has exactly one current supporting assertion link, one
  current class-resolution decision, and exactly one current outcome envelope for each required
  stage; each envelope has the complete zero-or-more set of independently typed findings.
* A normalized metric has one normalized representation, its immutable raw snapshot, evidence, and
  a `normalized` outcome-envelope disposition.
* An unmapped/proposed range type has one raw-preserved assertion, no normalized bucket, evidence,
  and a `mapping_unresolved` finding.
* An ambiguous mapping has one raw-preserved assertion, non-authoritative candidate buckets, no
  normalized bucket, evidence, and a `mapping_ambiguous` finding; it never fans out into assertions.
* An unparsed value has one raw-preserved assertion containing the exact raw value and observed
  datatype plus an `unparsed` finding.
* A missing required value has one assertion with `missing` state, no fabricated literal, evidence,
  and a `value_missing` finding.
* A datatype or contract violation has one assertion associated with its resolved/provisional class
  and the precise nonconformance finding.
* An ambiguous class has one deterministic provisional `instance_of_term_id` and one decision
  containing all candidate classes; candidate-derived fields remain non-authoritative.
* A family not yet capable of instantiation materializes exactly one current
  `kb.unresolved_semantic_occurrences` row and outcome envelope, exposed through generic discovery.
* No semantic finding silently removes an artifact from downstream processing.

### 7.2 Status and retry

* Content-level findings do not set `has_failed_proc`.
* Database, transaction, required-service, and unsafe-persistence failures still fail processors.
* Processor/run reports persist only `completed` or `failed`; every completed run has the mandatory
  finding summary, and the legacy projection returns `success` or `failed` as specified in DR3.
* Unrecoverable output that cannot identify or preserve an artifact fails execution while retaining
  the invocation/raw output and error when safe; recoverable malformed content completes with a
  finding and preserved occurrence.
* Unchanged dependency fingerprints do not repeatedly retry or duplicate findings.
* Mapping or contract changes trigger targeted retries and append-only superseding outcome
  envelopes/finding sets.
* Two workers racing on the same occurrence/dependency produce one active outcome and one current
  link; a crashed or expired worker can be safely resumed without duplicate active state.

### 7.3 Provenance and identity

* Raw and normalized values remain independently queryable.
* Evidence contains provenance and does not become the normalized value source.
* Two different unparsed raw values do not converge merely because they share an error state.
* Reprocessing preserves history and has at most one current supporting link per atomic metric.
* Corrections create decisions/revisions rather than rewriting source facts.
* The assertion raw snapshot fingerprint equals the referenced source occurrence revision, while
  evidence remains provenance rather than the canonical raw or normalized value owner.

### 7.4 Downstream behavior

* Search can find a flagged instance by raw wording and normalized wording when available.
* Observed class profiles include outliers without promoting them as valid contract rules.
* Comparison records no-verdict/incomparability with a reason when required capabilities are absent.
* Review Document displays flagged instances, their raw values, states, errors, and evidence.
* Consumers can include, warn about, or exclude findings through explicit policy.
* After a genuine upstream execution failure, only the affected dependency branch stops and enters
  operational retry; after a semantic finding, capable downstream branches continue and incapable
  operations persist an explicit no-result reason.

### 7.5 Regression tests

The OpenSpec changes must include:

* approved, proposed, ambiguous, absent, malformed, and special-value range types, asserting the
  exact row shapes and cardinalities in DR5 and section 7.1;
* parser success/failure and datatype mismatch;
* resolved, provisional, ambiguous, and identity-conflict classes;
* missing and unknown value payload constraints;
* option-3 unresolved-occurrence creation, discovery, and transactional materialization;
* rollback at every DR5 write boundary, proving no partial mapping count, class decision, assertion,
  current evidence link, outcome, validation, or invalidation survives; the previously committed raw
  artifact remains;
* system failure versus binary completed status with mandatory finding summary and legacy-status
  compatibility;
* dependency-change retry, unchanged-dependency idempotency, concurrent duplicate delivery,
  lease expiry, crash/restart, stale jobs, and saga completion recovery;
* raw-preserved canonical identity collision protection;
* reprocessing and evidence supersession; and
* Review Document visibility, search/comparison behavior, consumer filtering, and affected-branch
  behavior after semantic findings and genuine failures;
* at least one non-metric adapter plus the generic unresolved-occurrence fallback passing the shared
  conformance suite; and
* old-writer/new-reader dual operation, gated writer cutover, and rollback with already-committed
  new-state rows.

## 8. Consequences

### 8.1 Positive

* SemOS stops losing the claims that expose source or ontology problems.
* Operational failures and semantic uncertainty become distinguishable.
* Review Document can show malformed, incomplete, and conflicting requirements rather than silently
  omitting them.
* Raw provenance remains trustworthy while normalized interpretations can evolve.
* Mapping and contract improvements can target exactly the affected instances.
* Human review remains useful but optional.

### 8.2 Costs and risks

* More assertions and outcome rows are stored.
* Consumers must understand multidimensional states instead of assuming every row is clean.
* Poor default filters could overwhelm users with low-quality findings.
* Raw-preserved canonical identity requires careful serialization to avoid false convergence.
* Dependency-driven retry and supersession add lifecycle complexity.
* Existing dashboards and alerts must be retrained away from treating semantic findings as failures.

These risks are managed through explicit state vocabulary, capability-aware APIs, conservative
consumer defaults, append-only decisions, deterministic identity, bounded retention, targeted retry,
and clear UI explanations.

## 9. Relationship to Earlier Decisions

### ADR `2026072901`

This ADR strengthens the requirement that unresolved knowledge remain queryable and that human
review not block ordinary operation. Any fail/skip behavior that makes an identifiable artifact
semantically unreachable is superseded.

### ADR `2026081401`

Governed metric range-type mapping, proposal discovery, occurrence counting, artifact error flags,
operator visibility, and genuine Phase-C failure propagation remain. Proposed mapping misses no
longer fail `extract_metrics` or `associate_semantics`; they become semantic findings with targeted
retry.

### ADR `2026081701`

This ADR supplies its Phase-0 dependency. Raw-preserved and nonconforming metrics become ontology
instances with provisional/resolved classes, explicit state, evidence, and consumer-controlled use.

## 10. Open Questions for OpenSpec

These are implementation details rather than unresolved architectural direction:

1. The physical split between assertion columns, validation-result tables, and
   `kb.semantic_processing_outcomes` details.
2. Retention and compaction rules for large raw fragments after source artifacts and immutable
   invocation records already preserve identical content.
3. Default Review Document filters and warning presentation by outcome severity.
4. The first non-metric artifact family to migrate after the metric vertical slice.

These questions must be resolved and tested before production cutover.
