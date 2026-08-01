# SemOS P5 Rule-Driven Routing Specification

Date: 2026-08-01

Status: Approved design; implementation pending

Supersedes: none

Implements: ADR `2026072901-adr-ontology-platform-and-adaptive-pipeline.md` DR3, the deferred
DR6/DR7 predicate-and-gate schema, and phase P5 (§8.3.8)

Depends on: implemented P1 pipeline plane and generic P4 profile/review runtime

## 1. Purpose

P5 replaces the remaining flat-column routing path with one governed applicability mechanism
shared by extraction planning and review-profile selection. It adds the full `semrules` contract,
JSON predicates, per-processor effects, selective tier-3 document classification, module-supplied
routing proposals, and benchmark-gated enforcement.

P5 does not invent the authority-confirmed ventilator fixture that remains gated in P4. Generic
runtime completion and synthetic-corpus routing evidence may proceed independently; claims about
domain completeness remain blocked until the approved fixture exists.

## 2. Existing baseline

The implementation starts from these live facts:

- P1 persists policies, named pipelines, store bindings, flat pipeline-selection rules, document
  facets, immutable execution plans, and shadow/enforced operation.
- The active P1 rule matcher understands only three equality columns:
  `match_input_doc_type`, `match_source_language`, and
  `match_knowledge_store_binding`. It selects a pipeline but cannot gate individual processors.
- `server/api/ontology/semrules` is an unused P2 seam. It returns a Boolean plus string traces;
  missing facts usually collapse to `false`; its documented `object_class` predicate kind is not
  implemented.
- P4 stores profile and profile-rule applicability as JSON, but review scopes are selected
  explicitly. No runtime consumes those applicability values.
- `classify_document` does not exist as a declared processor.

These behaviors remain the compatibility baseline until the P5 parity gates described below pass.

## 3. Decisions

### 3.1 One evaluator, two consumers

Both pipeline planning and deterministic review-profile selection use the same predicate parser,
validator, fact model, evaluator, operator registry, result algebra, and trace format. Consumers
may add policy-specific precedence after evaluation; they may not reinterpret predicate truth.

### 3.2 Three-valued results

An evaluation returns exactly one of:

- `true`: the predicate is satisfied;
- `false`: the available facts establish that it is not satisfied;
- `indeterminate`: required facts are absent, invalid, conflicting, or below a declared confidence
  threshold.

An invalid predicate is an authoring/compilation error, not an `indeterminate` runtime result.
Operator failures caused by valid but unusable runtime facts are `indeterminate` and appear in the
trace.

`exists` is the one operator that asks about absence directly: it returns `true` for a `known`
fact and `false` for a `missing` fact. It returns `indeterminate` for `conflicting` or `invalid`
facts. If `min_confidence` is present, a known fact below the threshold is `indeterminate`. Every
other operator returns `indeterminate` for any fact state other than `known`.

Logical composition uses strong Kleene semantics:

| Expression | Result |
|---|---|
| `all` containing `false` | `false` |
| `all` with no `false` and at least one `indeterminate` | `indeterminate` |
| `all` containing only `true` | `true` |
| `any` containing `true` | `true` |
| `any` with no `true` and at least one `indeterminate` | `indeterminate` |
| `any` containing only `false` | `false` |
| `not(true)` / `not(false)` | `false` / `true` |
| `not(indeterminate)` | `indeterminate` |

Empty `all` is `true`; empty `any` is `false`. `not` requires exactly one child.

### 3.3 Predicate grammar

The persisted JSON grammar is versioned independently from policy versions:

```json
{
  "version": 1,
  "expression": {
    "kind": "all",
    "items": [
      {
        "kind": "fact",
        "path": "document.doc_kind",
        "op": "in",
        "value": ["standard", "specification"]
      },
      {
        "kind": "fact",
        "path": "document.numeric_unit_density",
        "op": "gte",
        "value": 0.02,
        "min_confidence": 0.8
      }
    ]
  }
}
```

Version 1 supports `all`, `any`, `not`, and `fact` nodes. Built-in operators are `eq`, `neq`,
`in`, `not_in`, `contains`, `gt`, `gte`, `lt`, `lte`, and `exists`. New operators register
through the existing seam without modifying evaluator dispatch.

`fact` nodes use canonical, case-sensitive namespaced paths. Version 1 namespaces are:

- `document.*`: governed document facets and deterministic structural facts;
- `object.class`: accepted object-classification terms visible in scope;
- `review.*`: `as_of`, `jurisdiction`, `operating_context`, and `purpose`;
- `deployment.*`: `workspace`, `tenant`, `knowledge_store`, `user`, and `corpus`.

Document facet values remain governed terms where DR4 requires governed vocabulary. Fact lookup
does not silently lowercase keys. Compatibility adapters normalize legacy values before building
the fact set.

The fact-path registry is code-owned mechanism metadata, while allowed governed values remain
ontology data. Each registered path declares its namespace, value type, allowed operators,
whether it is tier-3-producible, and an optional governed value scheme. Adding a path requires a
registry entry and tests; adding an allowed governed value does not require code.

Version 1 types and operators are:

| Type | Permitted operators | Comparison contract |
|---|---|---|
| `string` / governed term id | `eq`, `neq`, `in`, `not_in`, `exists` | exact UTF-8 equality after producer-specific canonicalization; no evaluator coercion |
| `number` | `eq`, `neq`, `in`, `not_in`, `gt`, `gte`, `lt`, `lte`, `exists` | JSON numbers converted losslessly to a common numeric representation; strings never parse as numbers |
| `boolean` | `eq`, `neq`, `exists` | exact Boolean equality |
| `date` | `eq`, `neq`, `in`, `not_in`, `gt`, `gte`, `lt`, `lte`, `exists` | strict ISO `YYYY-MM-DD`, compared chronologically |
| `string_set` | `contains`, `exists` | `contains` tests exact membership; set order and duplicates are ignored |

`in` means that one scalar fact equals one member of a homogeneous expected array. `not_in` is its
Boolean inverse for a known fact. Cross-type equality is a validation error when detectable from
the predicate and an `invalid_fact` runtime outcome otherwise. JSON `null` is not a known value; it
is represented as a `missing` fact.

The initial registry must include at least:

| Path | Type | Producer |
|---|---|---|
| `document.input_doc_type` | `string` | deterministic ingestion metadata |
| `document.source_language` | `string` | deterministic/metadata facet producer |
| `document.knowledge_store_binding_state` | `string` (`bound` or `absent`) | deterministic ingestion metadata |
| `document.has_document_number` | `boolean` | deterministic facet producer |
| `document.numeric_unit_density` | `number` | deterministic facet producer |
| `document.doc_kind` | governed term id | tier 1–3 |
| `document.domain` | governed term id | tier 2–3 |
| `document.normative_status` | governed term id | tier 2–3 |
| `document.jurisdiction` | governed term id | tier 2–3 |
| `object.class` | `string_set` | accepted classification assertions |
| `review.as_of` | `date` | review request |
| `review.jurisdiction` | governed term id | review request |
| `review.operating_context` | `string` | review request |
| `review.purpose` | governed term id | review request |
| `deployment.workspace` | `string` | runtime configuration |
| `deployment.tenant` | `string` | authenticated/request context |
| `deployment.knowledge_store` | `string` | `kb.inputs.ks_store_id` resolved to a stable id |
| `deployment.user` | `string` | authenticated/request context |
| `deployment.corpus` | `string` | benchmark/runtime context |

### 3.4 Fact records and traces

A fact carries:

- path and typed value;
- state: `known`, `missing`, `conflicting`, or `invalid`;
- optional confidence;
- method and evidence reference;
- producing run/policy/release identifiers where applicable.

The evaluator returns a structured tree trace. Each trace node records predicate kind, fact path,
operator, expected value, observed fact state/value, outcome, and reason code. Parent nodes retain
all evaluated child traces; short-circuiting may determine the result but must not erase the facts
that explain it. Each child is marked `decision_relevant`; a child evaluated only for explanation
after the parent result was already fixed is not reported as a missing dependency. The persisted
execution-plan representation may store a compact projection of the same trace.

Stable reason codes include at least `matched`, `not_matched`, `missing_fact`,
`confidence_below_minimum`, `conflicting_fact`, `invalid_fact`, and `operator_error`.

### 3.5 Validation and static analysis

Before a draft policy or module proposal can be activated, validation must reject:

- unknown grammar versions, kinds, operators, or fact namespaces;
- structurally invalid logical nodes;
- missing fact paths or operators on `fact` nodes;
- operator/value type mismatches detectable without runtime facts;
- invalid confidence thresholds;
- routing effects outside the governed effect vocabulary.

Static analysis also derives:

- the set of required fact paths;
- the set of required document facets;
- predicate specificity, defined as the count of distinct leaf fact constraints;
- whether tier-3 facts could be required.

Specificity is used only where DR7 explicitly names it as a tie-breaker. It does not change truth.

## 4. Compatibility migration

### 4.1 Storage evolution

`kb.pipeline_bindings` gains a nullable `predicate` JSONB document, the general DR6 scope columns,
and `binding_kind` (`conditional` or `store_default`) while retaining current knowledge-store
binding behavior. Bindings are the only governed policy rows that select a pipeline. Existing P1
store rows become `store_default`; generalized predicated bindings are `conditional`.

`kb.pipeline_rules` gains:

- nullable `predicate` JSONB;
- non-null `target_processor` for P5-authored rows;
- `effect` constrained to `require`, `enable`, `skip`, or `defer`;
- derived `required_facets` JSONB;
- source-module release and approval metadata required by DR6.

The current `kb.pipeline_rules` rows are actually conditional pipeline selectors, despite the DR6
name. The P5 migration copies them into `kb.pipeline_bindings` with their ids preserved in
`legacy_rule_id`, their selected pipeline unchanged, and their flat predicate translated as in
§4.2. Those legacy rows become read-only compatibility records and are no longer loaded as
processor rules. New `kb.pipeline_rules` rows are processor gates only.

A P5-authored binding/rule uses a JSON predicate. Compatibility records may retain legacy flat
columns for audit, but the canonical JSON predicate and checksum are persisted during migration.
Database checks and API validation prevent a new row from mixing JSON and flat authorship.

Because the P1 `kb.doc_facets` table is a fixed one-row projection, P5 adds
`kb.doc_facet_values`: one immutable observation per record, path, producer tier/method, source
fingerprint, value, confidence, evidence, run, and pinned vocabulary release. The old table remains
the compatibility projection for its existing fields; it is not the authoritative P5 fact store.

### 4.2 Legacy adapter

Each legacy row is translated deterministically into a version-1 `all` expression containing
equality leaves for its non-empty flat fields. The exact mappings are:

| Legacy column | Canonical path | Canonical value |
|---|---|---|
| `match_input_doc_type` | `document.input_doc_type` | Unicode trim, then lowercase |
| `match_source_language` | `document.source_language` | Unicode trim, then lowercase |
| `match_knowledge_store_binding` | `document.knowledge_store_binding_state` | Unicode trim, then lowercase; only the existing `bound`/`absent` state, not a store id or display name |

SQL `NULL`, an empty string, or a value that normalizes to empty emits no leaf. Zero emitted leaves
produce `{version:1, expression:{kind:"all", items:[]}}`, which is `true`. Leaves appear in the
table order above so canonical JSON and checksums do not depend on map iteration. This preserves
current normalization and wildcard semantics.

Existing CRUD remains compatible for legacy clients. New requests use `predicate`,
`target_processor`, and `effect`. Responses expose the canonical predicate plus a
`predicate_source` value (`json` or `legacy_adapter`).

### 4.3 Parity gate

Before JSON predicates govern production decisions, every active legacy selection rule is
evaluated through both the old matcher and the adapter-backed `semrules` path against a fixture set
covering match, miss, wildcard, normalization, equal-priority agreement, and conflict. Any mismatch
blocks activation and enforcement.

The old matcher is removed only after parity is proven and all active rows have been migrated or
are intentionally retained behind the adapter.

## 5. Extraction-planner consumer

### 5.1 Pipeline selection

Bindings evaluate against the production fact set. `true` candidates can select; `false`
candidates cannot. `indeterminate` candidates remain possible winners until the following
decision procedure proves them irrelevant.

Existing explicit-request and named-pipeline precedence remains unchanged.

At DR7 binding precedence level 4, evaluate only `binding_kind=conditional` and rank candidates by
descending priority and then scope
specificity (`document`, `user`, `knowledge_store`, `tenant`, `system`). For each rank:

| Candidates at rank | Decision |
|---|---|
| no `true` or `indeterminate` | examine the next rank |
| one or more `true`, all selecting one pipeline, and every `indeterminate` at that rank selects that same pipeline | select that pipeline |
| one or more `true` selecting different pipelines | conflict |
| any `indeterminate` could select a different pipeline from a `true` candidate | indeterminate |
| only `indeterminate` candidates | indeterminate |

Once a rank selects a pipeline, lower ranks—including indeterminate candidates—cannot affect the
result and are trace-only. An indeterminate at a higher rank always blocks falling through to a
lower winner.

In block mode, conflict or indeterminate fails the plan. In fallback mode, discard the entire
ambiguous rank, raise one warning for the plan, and continue through the remaining ranks and then
the `binding_kind=store_default` row for the record's knowledge store and the configured system
default. The trace records every discarded candidate. This preserves P1's unconditional order
“matching flat rule before store binding” because migrated flat rules are conditional bindings and
all pre-P5 store bindings are store defaults. This is the single operational interpretation of
DR7's fallback ladder for P5.

### 5.2 Processor gates

After pipeline selection, matching rules for each routed processor yield effects:

- `require`: run and treat the processor as required for this plan;
- `enable`: run;
- `skip`: do not run;
- `defer`: do not run now; persist the missing dependency/fact fingerprint for reevaluation.

Mandatory processors are never gated. Explicit requests and run overrides retain precedence.
Within policy rules, apply DR7 priority, specificity, and effect precedence. A remaining conflict
or decision-relevant `indeterminate` blocks under `DOC_PIPELINE_ON_CONFLICT=block`; fallback mode
uses the processor's declared `OnUndetermined` and records an alarm and trace.

The effect order is `require > defer > skip > enable`. `require > skip > enable` is inherited from
DR7; `defer` sits below `require` because an explicit requirement must run, and above `skip`
because it preserves a dependency-bound retry rather than declaring the processor unnecessary.
At the highest rule priority, then highest specificity:

| Candidate state | Decision |
|---|---|
| all `false` | use the processor's declared default |
| one or more `true` | choose the highest effect; agreeing effects are not a conflict |
| `indeterminate` rules only | gate is indeterminate |
| `true` plus `indeterminate` | choose the true effect only if every indeterminate rule's known effect could not outrank it; otherwise gate is indeterminate |

Lower-priority/specificity indeterminate rules cannot change a winner. In fallback mode an
indeterminate gate uses `OnUndetermined`; in block mode it fails before execution. A `defer`
decision must include at least one missing/dependency fact and its fingerprint; authoring a rule
whose effect is always `defer` without a dependency is invalid.

Execution plans persist the canonical predicate checksum, outcome, winning rule/effect,
structured trace, required/missing facts, and whether the decision was shadowed or enforced.

### 5.3 Shadow first

`DOC_PIPELINE_PLAN_ONLY=true` remains the default. It computes the complete P5 plan and records
would-run/would-skip/would-defer outcomes while executing the original requested processor set.
Enforced mode uses only rules that have passed the benchmark gate in §9.

## 6. Review-profile consumer

P5 adds deterministic selection for P4 review scopes:

1. Derive the single knowledge store from all reviewed documents; a mixed-store deterministic
   request is rejected in P5 v1 and may be split into separate scopes.
2. In one repeatable-read transaction, pin the active module releases and load only profiles
   visible to that knowledge store.
3. Evaluate each profile once per applicability subject: each reviewed document paired with each
   requested target object/class, or a document-only subject when no target is supplied.
4. Freeze every profile/release with at least one `true` subject into the immutable review scope,
   together with the exact subjects to which it applies.
5. Record all `false` and `indeterminate` subjects with traces in a selection snapshot.

Profiles are not mutually exclusive: overlapping `true` profiles are intentionally pinned
together, and P4's finding procedure reports incompatible requirements rather than P5 discarding
one silently. A deterministic scope is `indeterminate` and cannot execute when a candidate profile
has an indeterminate outcome for a subject/dimension the request declares closed. An
indeterminate profile outside requested closed dimensions is retained in the snapshot but does not
block execution.

Explicit profile selection remains supported. Existing explicit review scopes are unchanged.
Automatic selection uses `selection_mode=deterministic_rule`.

A deterministic-scope request supplies reviewed document ids, target object/class ids, review
context, closed dimensions, and selection reason; it must not supply `selected_profiles`.
Knowledge-store identity comes from `kb.inputs.ks_store_id`, not client input. The scope table gains
`knowledge_store_id`, `selection_status`, `fact_snapshot`, and `selection_snapshot` JSONB. Each
selected-profile snapshot entry includes profile/version, pinned release id/checksum, applicable
document/target subjects, predicate checksum, outcome, and trace. Scope creation commits the
activation pins and snapshot atomically; a concurrent activation either precedes or follows the
transaction, never partially changes the scope.

Profile-rule-level applicability is evaluated again within the already pinned scope. It may
exclude a rule from a run but cannot add an unpinned profile or release.

## 7. Tier-3 document classification

`classify_document` is a cheap-LLM, **mandatory-gated pre-plan producer**, matching the ADR §8.2
roster. It is registered and observable as a processor, but ordinary processor-gate rules cannot
skip or require it. The plan resolver invokes it between an initial applicability pass and final
plan freeze, avoiding a dependency cycle. It receives only unresolved governed facet keys and a
bounded document sample, and returns values from the pinned `document-authority` vocabulary with
confidence and source spans.

The planner follows this sequence:

1. Build deterministic tier-1 and metadata-derived tier-2 facts.
2. Evaluate policy/profile predicates with current facts. A missing tier-3 path is
   decision-relevant only when it contributes to an `indeterminate` candidate that could change
   the result: a binding at or above the current winning rank, a processor rule at the winning
   priority/specificity whose effect could outrank the current effect, or any visible profile on a
   requested closed dimension. The evaluator reports only missing paths that survive logical
   truth-table reduction; a missing child masked by an already-false `all` or already-true `any`
   does not qualify.
3. If no decision-relevant tier-3 path is missing, never invoke the classifier.
4. Otherwise schedule `classify_document`, persist its facet facts, rebuild the fact set, and
   evaluate once more.
5. If facts remain absent, conflicting, or below minimum confidence, preserve
   `indeterminate`; do not repeatedly call the classifier in the same run.

The prompt is a versioned file under `ChenWeb/prompts`; it is never embedded in Go.

Effective facet reduction is deterministic. Rank observations by method
`deterministic > metadata > classifier`; consider only the highest rank containing usable
observations. One canonical value at that rank is `known`; multiple distinct values are
`conflicting`; malformed values are `invalid`; no observations are `missing`. A lower-ranked
observation never overwrites or conflicts with a higher-ranked one. Classifier writes are
immutable/idempotent by `(record_id, path, source_fingerprint, classifier_version)` and never
update earlier rows. Concurrent differing classifier results therefore reduce to `conflicting`
rather than last-writer-wins. The initial plan pins the active vocabulary release; classifier
values are validated against that release and the final pass uses the same pin.

## 8. Domain-module routing proposals

An ontology module release may carry applicability proposals. Importing or activating the module
creates or updates draft pipeline-policy content with source-module release identifiers and
checksums. It never activates routing.

Promotion requires:

- successful predicate validation and static conflict analysis;
- a human approval identity;
- creation of a new immutable pipeline-policy version;
- separate policy activation through the existing audited endpoint.

Rolling back an ontology module does not silently roll back an active pipeline policy. Operators
must activate a replacement policy; the old policy remains reproducible from its pinned source
release metadata.

## 9. Benchmark and enforcement gate

P5 uses the existing `kb.benchmark_*` corpus/results and the P0 profile-report workflow to compare
routing off versus shadowed routing on. Results are grouped by document kind and record:

- processor invocation count and LLM cost;
- artifact yield and useful-artifact yield;
- review recall and precision;
- every proposed skip/defer and its explanation trace.

A rule may move from shadow to enforced only when its covered document-kind slice has no measured
review-recall loss and the evidence record names the corpus version, policy version, predicate
checksums, and run ids. Insufficient sample size or missing review truth leaves the rule in shadow.

Clearance is explicit governed data in `kb.pipeline_rule_clearances`: rule id and predicate
checksum, policy id/version, document kind, corpus manifest checksum, baseline and routed benchmark
run ids, paired case count, processor-failure count, baseline/routed recall and precision,
decision (`draft|approved|revoked`), approver, timestamps, and rationale. An active processor rule
references an approved clearance id for each document kind it may enforce. Approval requires:

- both terminal successful runs over the identical manifest and repetitions;
- every case in the declared document-kind slice paired between variants;
- at least three paired cases and at least one gold-positive review item;
- zero processor/infrastructure/scorer failures;
- routed recall greater than or equal to baseline recall using exact aggregate
  `matched_gold / total_gold` counts (no rounding tolerance).

Precision and cost/yield are recorded but do not override the ADR's no-recall-loss gate. A changed
predicate, rule, policy version, corpus manifest, or benchmark run produces a checksum/id mismatch
and cannot reuse the approval. Revocation takes effect immediately. Historical clearance rows are
never rewritten, so old plans remain auditable. If a record's document kind is missing or has no
matching approved clearance, the rule remains shadow-only even when global plan-only mode is off.

The generic P5 implementation may demonstrate this gate with the existing synthetic corpus. The
normative ventilator conclusion remains blocked until the authority-confirmed P4 fixture is
available.

## 10. APIs and security

Existing authenticated policy authoring and activation routes remain the control surface.
Authoring APIs validate predicates and return actionable path-local errors. Read APIs return
canonical predicates, derived required facts, checksums, and compact traces. Only authorized
humans may approve or activate a policy; LLM output may create proposals but cannot approve or
activate them.

All authoring, promotion, activation, conflict, fallback, classifier, and enforcement events are
logged with stable identifiers. Predicate values and traces must not log document content beyond
the evidence references already authorized for the plan/review surface.

## 11. Failure behavior

- Invalid authored predicate: reject draft write or compilation; active policy unchanged.
- Unknown grammar version: reject; never guess a compatible interpretation.
- Missing/conflicting runtime fact: `indeterminate` with trace.
- Decision-relevant binding/gate conflict, indeterminacy, operator failure, or active-policy load
  failure in block mode: fail before processors run and raise exactly one error alarm for the plan,
  deduplicated by run id.
- Conflict in fallback mode: apply DR7 fallback, raise a warning, and persist the losing choices.
- Tier-3 classifier failure: preserve `indeterminate`; do not overwrite prior known facts.
- Benchmark regression: keep the affected rule shadow-only.
- Automatic profile-selection indeterminacy on a requested closed dimension: do not create an
  executable scope; persist/return the selection attempt and raise one warning deduplicated by its
  request correlation id. Non-decision-relevant evaluator errors remain trace-only.
- No active pipeline policy: use the existing legacy/default path. An active-policy pointer that
  cannot be loaded is an error and must not silently fall back as though no policy existed.

## 12. Acceptance criteria

P5 generic runtime is complete when automated and live validation prove:

1. three-valued logical truth tables and typed operator behavior;
2. `exists` distinguishes missing from unusable facts, and structured traces distinguish missing,
   conflicting, invalid, low-confidence, and logically non-contributing facts;
3. validation rejects malformed or unknown predicates before activation;
4. required-fact extraction and specificity are deterministic;
5. every legacy flat rule has adapter parity with the current matcher, including canonical paths,
   normalization, wildcard JSON, and stable checksum;
6. migrated conditional bindings still outrank P1 store defaults, and JSON predicates select
   pipelines using the normative true/false/indeterminate decision table;
7. processor `require|enable|skip|defer` effects alter enforced execution and remain shadow-only
   in plan-only mode, including ties with `defer` and indeterminate rules;
8. an unresolved selection/gate conflict or active-policy load failure blocks before artifact
   production and raises exactly one alarm per run;
9. automatic review-profile selection and extraction routing evaluate identical predicates to
   identical truth results and traces; per-document/target applicability and release pins survive
   later activation changes;
10. deterministic scope creation derives one knowledge store, commits pins and snapshots
    atomically, handles closed-dimension indeterminacy explicitly, and leaves explicit P4 scopes
    byte-compatible;
11. `classify_document` runs only for unresolved, decision-relevant governed facets and runs at
    most once per record/run; concurrent or conflicting observations reduce deterministically
    without overwriting stronger facts;
12. module proposals produce draft policy content without changing active routing;
13. a failed policy compilation or activation leaves the previous active version effective;
14. execution/review snapshots remain reproducible after policy or module activation changes;
15. the benchmark report records cost, yield, recall/precision, and explainable skips for routing
    on versus off;
16. only rule/document-kind slices with a matching approved clearance checksum can be enforced;
    changed or revoked evidence returns the rule to shadow immediately.

The ADR P5 exit additionally requires documented per-document-kind invocation reduction with no
measured review-recall loss. Authority-specific pilot claims require the separately approved P4
fixture and are not implied by generic-runtime completion.

## 13. Non-goals

- Inventing authoritative standards, editions, clauses, or ventilator limit values.
- A general-purpose policy language beyond applicability predicates.
- Arbitrary code execution, user-defined scripts, loops, or side effects in predicates.
- Replacing the ontology module or pipeline-policy approval lifecycles.
- Making ontology activation automatically activate routing.
- Removing explicit pipeline, processor, or review-profile overrides.
- P6 artifact-family work or P7 RDF/SHACL publication.

## 14. Knowledge and documentation impact

**What knowledge changed?** P5 now has an explicit executable contract for three-valued
applicability, compatibility migration, both DR3 consumers, tier-3 classification, proposal
promotion, and benchmark-gated enforcement.

**Which docs/specs/ADRs/tests are affected?** ADR `2026072901` DR3/DR4/DR6/DR7/P5, the ontology
capsule, the ontology-status handoff, P1 routing tests, P4 review-scope tests, and new P5 exit tests.

**Which docs were updated?** This specification. The ADR, capsule, handoff, P5 plan, and P5
implementation log are updated as implementation milestones land.

**Which docs are now stale?** The handoff shorthand that describes P5 only as the full
`semrules` language is incomplete; P5 is the entire ADR §8.3.8 routing phase.

**What was intentionally left undocumented?** Authority-owned pilot values and editions, because
no confirmed worked example has been supplied.
