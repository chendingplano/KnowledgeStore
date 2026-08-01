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
`in`, `not_in`, `gt`, `gte`, `lt`, `lte`, and `exists`. New operators register through the
existing seam without modifying evaluator dispatch.

`fact` nodes use canonical, case-sensitive namespaced paths. Version 1 namespaces are:

- `document.*`: governed document facets and deterministic structural facts;
- `object.class`: accepted object-classification terms visible in scope;
- `review.*`: `as_of`, `jurisdiction`, `operating_context`, and `purpose`;
- `deployment.*`: `workspace`, `tenant`, `knowledge_store`, `user`, and `corpus`.

Document facet values remain governed terms where DR4 requires governed vocabulary. Fact lookup
does not silently lowercase keys. Compatibility adapters normalize legacy values before building
the fact set.

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
that explain it. The persisted execution-plan representation may store a compact projection of the
same trace.

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

`kb.pipeline_bindings` gains a nullable `predicate` JSONB document and the general DR6 scope
columns while retaining current knowledge-store binding behavior.

`kb.pipeline_rules` gains:

- nullable `predicate` JSONB;
- nullable `target_processor`;
- `effect` constrained to `select_pipeline`, `require`, `enable`, `skip`, or `defer`;
- derived `required_facets` JSONB;
- source-module release and approval metadata required by DR6.

The current flat match columns remain readable during P5. A row may use either a JSON predicate or
legacy flat columns, never both. Database checks and API validation enforce that invariant.

### 4.2 Legacy adapter

At read time, each legacy row is translated deterministically into a version-1 `all` expression
containing equality leaves for its non-empty flat fields. An empty legacy predicate is `true`.
This preserves current normalization and wildcard semantics.

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

Bindings and `select_pipeline` rules evaluate against the production fact set. Only `true` rules
participate in selection. `false` rules do not match. `indeterminate` rules are retained in the
selection trace and handled by DR7; they must never silently become a match or miss when they can
affect the winning precedence level.

Existing explicit-request and named-pipeline precedence remains unchanged.

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

Execution plans persist the canonical predicate checksum, outcome, winning rule/effect,
structured trace, required/missing facts, and whether the decision was shadowed or enforced.

### 5.3 Shadow first

`DOC_PIPELINE_PLAN_ONLY=true` remains the default. It computes the complete P5 plan and records
would-run/would-skip/would-defer outcomes while executing the original requested processor set.
Enforced mode uses only rules that have passed the benchmark gate in §9.

## 6. Review-profile consumer

P5 adds deterministic selection for P4 review scopes:

1. Load only profiles visible through pinned active module releases and knowledge-store ontology
   visibility.
2. Evaluate each profile's applicability predicate against the same fact-set contract.
3. Freeze all `true` profiles and their releases into the immutable review scope.
4. Record `false` and `indeterminate` candidates with traces in the selection snapshot.
5. Apply the existing precedence policy. An unresolved applicability conflict yields an
   `indeterminate` scope decision; it does not silently choose a profile.

Explicit profile selection remains supported. Existing explicit review scopes are unchanged.
Automatic selection uses `selection_mode=deterministic_rule`.

Profile-rule-level applicability is evaluated again within the already pinned scope. It may
exclude a rule from a run but cannot add an unpinned profile or release.

## 7. Tier-3 document classification

`classify_document` is a routed, cheap-LLM declared processor. It receives only the unresolved
governed facet keys required by decision-relevant predicates and a bounded document sample. It
returns values from the active `document-authority` vocabulary with confidence and source spans.

The planner follows this sequence:

1. Build deterministic tier-1 and metadata-derived tier-2 facts.
2. Statically inspect applicable policy/profile predicates for unresolved required facets.
3. If no decision-relevant tier-3 facet is missing, never invoke the classifier.
4. Otherwise schedule `classify_document`, persist its facet facts, rebuild the fact set, and
   evaluate once more.
5. If facts remain absent, conflicting, or below minimum confidence, preserve
   `indeterminate`; do not repeatedly call the classifier in the same run.

The prompt is a versioned file under `ChenWeb/prompts`; it is never embedded in Go.

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
- Decision-relevant conflict in block mode: fail before processors run and raise exactly one
  error alarm for the plan.
- Conflict in fallback mode: apply DR7 fallback, raise a warning, and persist the losing choices.
- Tier-3 classifier failure: preserve `indeterminate`; do not overwrite prior known facts.
- Benchmark regression: keep the affected rule shadow-only.

## 12. Acceptance criteria

P5 generic runtime is complete when automated and live validation prove:

1. three-valued logical truth tables and typed operator behavior;
2. structured traces distinguish missing, conflicting, invalid, and low-confidence facts;
3. validation rejects malformed or unknown predicates before activation;
4. required-fact extraction and specificity are deterministic;
5. every legacy flat rule has adapter parity with the current matcher;
6. JSON predicates select pipelines with the existing DR7 precedence;
7. processor `require|enable|skip|defer` effects alter enforced execution and remain shadow-only
   in plan-only mode;
8. an unresolved gate conflict blocks before artifact production and raises exactly one alarm;
9. automatic review-profile selection and extraction routing evaluate identical predicates to
   identical truth results and traces;
10. explicit P4 scopes remain byte-compatible;
11. `classify_document` runs only for unresolved, decision-relevant governed facets and runs at
    most once per record/run;
12. module proposals produce draft policy content without changing active routing;
13. a failed policy compilation or activation leaves the previous active version effective;
14. execution/review snapshots remain reproducible after policy or module activation changes;
15. the benchmark report records cost, yield, recall/precision, and explainable skips for routing
    on versus off;
16. only benchmark-cleared rule slices can be enforced.

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
