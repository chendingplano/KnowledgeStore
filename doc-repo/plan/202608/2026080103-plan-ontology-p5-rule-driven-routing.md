# SemOS P5 Rule-Driven Routing Implementation Plan

> **Status (2026-08-03): superseded for status by `2026080303-plan-ontology-p5-completion.md`.** The
> checkboxes below were reconciled on 2026-08-03 to reflect implemented-and-verified-after-
> remediation work. An independent audit (bug `2026080301`, review
> `2026080302-devdoc-ontology-p5-implementation-review.md`) found several of these tasks were not
> operational as first implemented; the completion plan's Chunks A–H fixed them (resolver wired,
> promotion transactional, checksums canonical, clearance keyed on `document.doc_kind`, exit
> criteria corrected), and the boxes are checked only where that work is verified. The four I2
> boxes (live PostgreSQL + synthetic-corpus proof) remain unchecked — that is the only outstanding
> P5 item.

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement ADR `2026072901` P5 and spec `2026080102`: one three-valued applicability evaluator shared by extraction routing and deterministic review-profile selection, with bounded document classification and benchmark-cleared enforcement.

**Architecture:** Expand `ontology/semrules` into the code-owned mechanism layer, then adapt P1 policy data into canonical conditional bindings and processor gates. Build immutable fact observations and selection snapshots around it. Suppressive decisions remain shadow unless an append-only clearance covers their exact policy/document-kind/checksum slice.

**Tech Stack:** Go 1.25, PostgreSQL/Goose, Echo v4, `sqlmock`, existing ChenWeb processor/runtime and ontology module/profile stores, `jj`.

**Source of truth:** `KnowledgeStore/doc-repo/specs/202608/2026080102-spec-ontology-p5-rule-driven-routing.md`

---

## File map

New focused files:

- `ChenWeb/server/api/ontology/semrules/{types,facts,validate,evaluate,canonical}.go` — grammar, fact registry, validation/static analysis, evaluator, canonical checksum.
- `ChenWeb/server/api/doc-processing/{applicability_facts,pipeline_bindings,pipeline_gates,routing_clearance}.go` — extraction consumer and enforcement boundary.
- `ChenWeb/server/api/doc-processing/classify-document.go` — mandatory-gated pre-decision classifier.
- `ChenWeb/server/api/ontology/profiles/select.go` — deterministic profile-selection consumer.
- `ChenWeb/server/api/ontology/modules/applicability_proposals.go` — release-carried routing proposals and draft-policy promotion.
- `ChenWeb/server/api/doc-benchmark/routing_clearance.go` — paired benchmark decision and clearance evidence.
- migrations `20260801000015` through `20260801000020` — policy predicates, fact observations, review snapshots, clearances, module proposals, audit events.
- `KnowledgeStore/doc-repo/devdocs/202608/2026080107-devdoc-ontology-p5-implementation-log.md` — evidence and deferred boundary.

Existing files changed surgically:

- P1 planner/stores/handlers: `server/api/doc-processing/{processor_plan,pipeline_selection,pipeline_rules_store,doc_facet_store}.go`, `server/api/kbhandler/{pipeline_rules_handler,pipeline_bindings_handler,pipeline_policies_handler}.go`.
- P4 profiles/review: `server/api/ontology/profiles/{profiles_store,review_scopes_store,review_service}.go`, `server/api/kbhandler/ontology_review_scopes_handler.go`.
- compiler/runtime/routes: `server/api/ontology/modules/{validate,releases_store}.go`, `server/api/doc-processing/runtime.go`, `server/api/routes.go`.
- docs: ADR status annotation, ontology/doc-processor capsules, ontology-status handoff.

## Chunk A — Full `semrules` mechanism

### Task A1: Three-valued AST and fact registry

**Files:**
- Create: `ChenWeb/server/api/ontology/semrules/types.go`
- Create: `ChenWeb/server/api/ontology/semrules/facts.go`
- Modify: `ChenWeb/server/api/ontology/semrules/semrules.go`
- Test: `ChenWeb/server/api/ontology/semrules/types_test.go`
- Test: `ChenWeb/server/api/ontology/semrules/facts_test.go`

- [x] Write failing tests for `TruthTrue|TruthFalse|TruthIndeterminate`, JSON grammar v1, fact states, registered paths/types, duplicate path rejection, and immutable registry snapshots.
- [x] Run `go test ./server/api/ontology/semrules -run 'Test(Truth|PredicateJSON|FactRegistry)' -count=1`; verify failures identify missing types/registry.
- [x] Add `Document{Version,Expression}`, `Predicate{Kind,Path,Op,Value,MinConfidence,Items}`, `Truth`, `Fact`, `FactState`, `FactType`, and `PathSpec`.
- [x] Register the exact initial paths/types/operators from spec §3.3, including legacy `document.knowledge_store_binding_state` and tier-3 metadata.
- [x] Preserve `RegisterOperator` as extension seam 3, but change operator inputs to typed known values; keep a compatibility `Evaluate(Predicate,map[string]any)` wrapper until consumers migrate.
- [x] Run the focused tests and commit with `jj commit -m "feat(semrules): add typed facts and three-valued grammar"`.

### Task A2: Validation, static analysis, and canonical checksum

**Files:**
- Create: `ChenWeb/server/api/ontology/semrules/validate.go`
- Create: `ChenWeb/server/api/ontology/semrules/canonical.go`
- Test: `ChenWeb/server/api/ontology/semrules/validate_test.go`
- Test: `ChenWeb/server/api/ontology/semrules/canonical_test.go`

- [x] Write table-driven failing tests for unknown versions/kinds/paths/operators, invalid node arity, heterogeneous `in`, illegal operator/type pairs, confidence outside `[0,1]`, stable required paths/facets, specificity, and canonical checksum independent of object-key order.
- [x] Verify red with `go test ./server/api/ontology/semrules -run 'Test(Validate|Analyze|Canonical)' -count=1`.
- [x] Implement `Validate(Document) error`, `Analyze(Document) Analysis`, and `Canonicalize(Document) ([]byte,string,error)`; canonical child order remains authored order because logical trace/order is auditable.
- [x] Return path-local validation errors such as `expression.items[1].op`.
- [x] Run all semrules tests and commit with `jj commit -m "feat(semrules): validate and checksum predicates"`.

### Task A3: Structured evaluator and decision-relevance traces

**Files:**
- Create: `ChenWeb/server/api/ontology/semrules/evaluate.go`
- Replace compatibility implementation in: `ChenWeb/server/api/ontology/semrules/semrules.go`
- Test: `ChenWeb/server/api/ontology/semrules/evaluate_test.go`
- Update: `ChenWeb/server/api/ontology/semrules/semrules_test.go`

- [x] Write failing truth-table tests for `all|any|not`, `exists`, every typed operator, low-confidence/conflicting/invalid facts, and decision-relevance marking of logically masked children.
- [x] Verify red with `go test ./server/api/ontology/semrules -run TestEvaluate -count=1`.
- [x] Implement `EvaluateDocument(Document,FactSet) Result` returning structured `TraceNode` trees and stable reason codes.
- [x] Ensure all children appear in traces, while missing paths from masked children are excluded from `Result.DecisionRelevantMissingPaths`.
- [x] Make the old wrapper produce legacy Boolean behavior only for existing callers/tests; all new consumers call `EvaluateDocument`.
- [x] Run `go test ./server/api/ontology/semrules -count=1` and `go vet ./server/api/ontology/semrules`; commit.

### Task A4: Neutral bounded predicate-overlap analyzer

**Files:**
- Create: `ChenWeb/server/api/ontology/semrules/overlap.go`
- Test: `ChenWeb/server/api/ontology/semrules/overlap_test.go`

- [x] Write failing tests for equal/disjoint/intersecting conjunctions of scalar `eq|in`, unconstrained paths, agreeing targets, and predicates outside the analyzable subset.
- [x] Implement `AnalyzeOverlap(left,right) {MayOverlap,Analyzable,Reason}` in `semrules`, keeping policy meaning out of this neutral mechanism.
- [x] Run focused overlap tests and commit; policy compilation and module validation both consume this package without importing each other.

## Chunk B — P5 storage and fact observations

### Task B1: Policy predicate and compatibility migration

**Files:**
- Create: `ChenWeb/project_migrations/20260801000015_add_p5_pipeline_predicates.sql`
- Test: `ChenWeb/server/api/doc-processing/p5_migration_contract_test.go`

- [x] Write a failing migration contract test that reads the SQL and asserts: generalized binding scope, `binding_kind`, canonical predicate/checksum, `legacy_rule_id`, processor gate fields, required facets, module provenance, approval metadata, and constraints preventing mixed new authorship.
- [x] Add the Goose migration. Tag existing bindings `store_default`; copy P1 selector rows into `conditional` bindings with deterministic version-1 JSON; retain old selector rows for read-only API compatibility; make P5 processor-rule fields nullable only where old selector rows require it.
- [x] Add indexes for active policy + binding rank and policy + target processor + gate rank.
- [x] Verify migration SQL contract and `go test ./server/api/doc-processing -run TestP5MigrationContract -count=1`; commit.

### Task B2: Immutable facet observations and deterministic reduction

**Files:**
- Create: `ChenWeb/project_migrations/20260801000016_create_kb_doc_facet_values.sql`
- Create: `ChenWeb/server/api/doc-processing/applicability_facts.go`
- Modify: `ChenWeb/server/api/doc-processing/doc_facet_store.go`
- Test: `ChenWeb/server/api/doc-processing/applicability_facts_test.go`
- Test: `ChenWeb/server/api/doc-processing/doc_facet_store_test.go`

- [x] Write failing pure tests for `deterministic > metadata > classifier`, same-rank minimum confidence, conflicting values, malformed-plus-usable becoming invalid, lower-rank non-interference, and fact-set namespaces.
- [x] Write failing SQL-store tests for immutable insert/idempotent retry using `(record,path,decision_attempt_id,invocation_id)` and list-by-record/release pins.
- [x] Add `kb.doc_facet_values` with typed JSON value, method/tier, confidence, evidence, source fingerprint, decision-attempt/invocation ids, vocabulary release, and timestamps.
- [x] Implement `FacetObservationStore`, `ReduceFacetObservations`, and `BuildApplicabilityFactSet`; continue updating the P1 `kb.doc_facets` projection for legacy APIs.
- [x] Run focused tests, then `go test ./server/api/doc-processing -run 'Test(Facet|ApplicabilityFact)' -count=1`; commit.

### Task B3: Complete fact-set adapters

**Files:**
- Create: `ChenWeb/server/api/doc-processing/applicability_classifications.go`
- Test: `ChenWeb/server/api/doc-processing/applicability_classifications_test.go`
- Create: `ChenWeb/server/api/ontology/profiles/applicability_context.go`
- Test: `ChenWeb/server/api/ontology/profiles/applicability_context_test.go`
- Modify: `ChenWeb/server/api/doc-processing/applicability_facts.go`

- [x] Write separate failing tests for accepted `core:instance_of` classification loading into `object.class`, canonical `review.*` request facts, authenticated/runtime `deployment.*` facts, missing/conflicting states, and vocabulary/release pins on every governed value.
- [x] Implement focused adapters: `ClassificationFactLoader`, `BuildReviewContextFacts`, and `BuildDeploymentFacts`; merge them with facet observations through one `semrules.FactSetBuilder` that rejects duplicate known producers rather than silently overwriting.
- [x] Run one shared predicate fixture through extraction and review fact builders and assert identical values, truth result, trace, and pinned provenance.
- [x] Run `go test ./server/api/doc-processing ./server/api/ontology/profiles -run 'Test(Applicability|ClassificationFact|ReviewContext|DeploymentFact)' -count=1`; commit.

## Chunk C — Conditional bindings and legacy API parity

### Task C1: Canonical binding store and DR7 decision table

**Files:**
- Create: `ChenWeb/server/api/doc-processing/pipeline_bindings.go`
- Modify: `ChenWeb/server/api/doc-processing/pipeline_rules_store.go`
- Modify: `ChenWeb/server/api/doc-processing/pipeline_selection.go`
- Modify: `ChenWeb/server/api/doc-processing/processor_plan.go`
- Modify: `ChenWeb/server/api/doc-processing/event.go`
- Modify: `ChenWeb/server/api/doc-processing/control.go`
- Test: `ChenWeb/server/api/doc-processing/pipeline_bindings_test.go`
- Update: `ChenWeb/server/api/doc-processing/pipeline_rules_test.go`
- Update: `ChenWeb/server/api/doc-processing/pipeline_rules_store_test.go`
- Update: `ChenWeb/server/api/doc-processing/runtime_selection_test.go`
- Update: `ChenWeb/server/api/doc-processing/handle_event_run_test.go`

- [x] Write failing tests for legacy adapter canonical paths/order/checksum and exact match/miss/wildcard/normalization/conflict parity.
- [x] Write failing binding-rank tests for true/false/indeterminate combinations, same-pipeline indeterminate agreement, higher-rank indeterminate blocking, lower-rank irrelevance, block/fallback, and migrated conditional-before-store-default behavior.
- [x] Add failing precedence fixtures proving `LineFileGeneratedEvent.Operations` bypasses policy processor selection, persisted requested pipelines outrank conditional bindings, and new run-scoped `pipeline_override`/processor overrides parsed from the event outrank policy bindings/gates without losing their audit annotation.
- [x] Implement canonical `PipelineBinding`, load conditional/store-default rows from the active policy, evaluate with `semrules`, and return structured selection traces.
- [x] Retire the in-memory flat matcher from runtime resolution while keeping a test-only parity function until P5 closeout.
- [x] Run the focused filter, then the full package `go test ./server/api/doc-processing -count=1` so runtime/event override tests cannot be skipped; commit.

### Task C2: Compatibility CRUD without dual writes

**Files:**
- Modify: `ChenWeb/server/api/kbhandler/pipeline_rules_handler.go`
- Modify: `ChenWeb/server/api/kbhandler/pipeline_bindings_handler.go`
- Test: `ChenWeb/server/api/kbhandler/pipeline_rules_handler_test.go`
- Test: `ChenWeb/server/api/kbhandler/pipeline_bindings_handler_test.go`

- [x] Write failing handler tests proving legacy create writes one conditional binding; get/list omit predicates not losslessly representable in the old shape; representable rows round-trip; both update and delete resolve pre-migration `legacy_rule_id`; both update and delete resolve post-migration compatibility ids; active-policy writes return conflict; and no `kb.pipeline_rules` selector write occurs.
- [x] Extend binding CRUD for canonical predicate/scope/priority fields and validate through `semrules`.
- [x] Implement the pipeline-rules compatibility adapter at the HTTP boundary; new processor-gate requests use the canonical schema and old selector-shaped requests redirect to bindings.
- [x] Run focused handler tests and commit.

## Chunk D — Benchmark decision and append-only clearance evidence

### Task D1: Pure paired routing benchmark decision

**Files:**
- Create: `ChenWeb/server/api/doc-benchmark/routing_clearance.go`
- Test: `ChenWeb/server/api/doc-benchmark/routing_clearance_test.go`
- Modify: `ChenWeb/server/cmd/doc-benchmark/gold_analyze.go`
- Test: `ChenWeb/server/cmd/doc-benchmark/main_test.go`

- [x] Write one failing test per approval condition: identical manifest and repetitions, complete paired cases, minimum three cases, gold-positive denominator, zero processor/infrastructure/scorer failures, and exact aggregate routed recall `>=` baseline recall.
- [x] Implement pure `EvaluateRoutingClearance(Evidence) Decision`; it owns all benchmark approval logic and returns counts, recall/precision, cost/yield, document kind, checksums, traces, and a stable rejection reason.
- [x] Add an analyze option that emits approval-ready evidence but never writes approval state.
- [x] Run `go test ./server/api/doc-benchmark ./server/cmd/doc-benchmark -run 'Test(RoutingClearance|AnalyzeRouting)' -count=1`; commit.

### Task D2: Append-only clearance store and authenticated API

**Files:**
- Create: `ChenWeb/project_migrations/20260801000017_create_kb_pipeline_routing_clearances.sql`
- Create: `ChenWeb/server/api/doc-processing/routing_clearance.go`
- Test: `ChenWeb/server/api/doc-processing/routing_clearance_test.go`
- Create: `ChenWeb/server/api/kbhandler/pipeline_routing_clearances_handler.go`
- Test: `ChenWeb/server/api/kbhandler/pipeline_routing_clearances_handler_test.go`
- Create: `ChenWeb/server/api/kbhandler/policy_authorization.go`
- Test: `ChenWeb/server/api/kbhandler/policy_authorization_test.go`
- Modify: `ChenWeb/server/api/routes.go`

- [x] Write failing store tests for exact document-kind coverage, processor-rule/conditional-binding checksums, incomparable pipeline removed-set deltas, replacement/revocation, and zero/multiple-effective lookup.
- [x] Write failing handler tests proving approval reloads the named benchmark runs and calls the exact `docbenchmark.EvaluateRoutingClearance` function; a client cannot submit precomputed pass/fail or actor identity.
- [x] Add clearance, coverage-generation, and append-only revocation tables; implement `Approve`, `Replace`, `Revoke`, and `ResolveEffective` with a transaction-scoped subject-slice lock.
- [x] Add an injected policy authorizer. Production permits clearance approval/revocation and policy activation only to owner/admin users (`IsOwner`, `Admin`, or normalized `admin` role); proposal approval additionally permits normalized `k_engineer`. Tests distinguish unauthenticated `401`, authenticated-but-unauthorized `403`, and authorized success. Derive the actor from `UserName`; never accept it from the body.
- [x] Run focused store/handler/route tests; commit.

## Chunk E — Gates, policy compilation, enforcement, and audit

### Task E1: Pure processor-gate resolution and shadow plan

**Files:**
- Create: `ChenWeb/server/api/doc-processing/pipeline_gates.go`
- Test: `ChenWeb/server/api/doc-processing/pipeline_gates_test.go`
- Modify: `ChenWeb/server/api/doc-processing/processor_plan.go`
- Update: `ChenWeb/server/api/doc-processing/control_test.go`
- Update: `ChenWeb/server/api/doc-processing/doc_process_plan_store_test.go`

- [x] Write separate failing tests for rank iteration, `require > defer > skip > enable`, agreeing effects, true plus outranking indeterminate, defaults, mandatory immunity, defer fingerprints, explicit processor-list bypass, and run override precedence.
- [x] Implement pure gate evaluation and record the would-run/would-skip/would-defer shadow decision without changing effective processors in this task.
- [x] Persist complete fact snapshots, pinned policy/version/checksum, selected pipeline definition/checksum, baseline pipeline checksum, binding/gate traces, and rule checksums in the execution plan.
- [x] Prove plan reload is identical after in-memory policy/pipeline registry changes in `TestPersistedP5PlanReloadIgnoresLaterActivation`.
- [x] Run focused planner/store tests; commit.

### Task E2: Compile and transactionally activate a policy

**Files:**
- Create: `ChenWeb/server/api/doc-processing/policy_compile.go`
- Test: `ChenWeb/server/api/doc-processing/policy_compile_test.go`
- Modify: `ChenWeb/server/api/kbhandler/pipeline_policies_handler.go`
- Test: `ChenWeb/server/api/kbhandler/pipeline_policies_handler_test.go`

- [x] Write failing compiler tests for predicate validation, legacy-adapter parity, canonical checksums, unknown processors/pipelines, invalid clearance references, overlapping conditional bindings selecting different pipelines, overlapping bindings agreeing on one pipeline, and overlapping processor gates whose differing effects resolve deterministically by `require > defer > skip > enable`.
- [x] Consume `semrules.AnalyzeOverlap`: reject only overlapping same-rank binding candidates that can select different pipelines or otherwise remain unresolved under DR7. Do not reject overlapping gate effects when the effect order determines one winner. Predicates outside the analyzable subset rely on runtime conflict handling and receive `runtime_conflict_check_required`.
- [x] Write failing activation tests proving anonymous/body-supplied actor rejection, authenticated non-admin rejection, compiler failure leaves the prior active row untouched, transaction failure rolls back archival, and successful activation uses D2's owner/admin authorizer and derives actor from `UserName`.
- [x] Compile before opening the activation transaction, lock policy rows, recheck the compiled checksum inside the transaction, then archive/activate atomically.
- [x] Run policy compiler/handler tests; commit.

### Task E3: Clearance-aware atomic enforcement, alarms, and audit events

**Files:**
- Create: `ChenWeb/project_migrations/20260801000018_create_kb_pipeline_policy_events.sql`
- Create: `ChenWeb/server/api/doc-processing/routing_enforcement.go`
- Test: `ChenWeb/server/api/doc-processing/routing_enforcement_test.go`
- Create: `ChenWeb/server/api/doc-processing/routing_alarm.go`
- Test: `ChenWeb/server/api/doc-processing/routing_alarm_test.go`
- Create: `ChenWeb/server/api/ontology/policyaudit/store.go`
- Test: `ChenWeb/server/api/ontology/policyaudit/store_test.go`
- Modify: `ChenWeb/server/api/doc-processing/control.go`
- Modify: `ChenWeb/server/api/kbhandler/pipeline_rules_handler.go`
- Modify: `ChenWeb/server/api/kbhandler/pipeline_bindings_handler.go`
- Modify: `ChenWeb/server/api/kbhandler/pipeline_policies_handler.go`
- Modify: `ChenWeb/server/api/kbhandler/pipeline_routing_clearances_handler.go`

- [x] Write failing enforcement-order tests for: explicit list bypass; explicit/run override; conditional binding evaluation; conditional-binding clearance or store-default fallback; pipeline allowlist; processor gate evaluation; gate clearance; mandatory restoration; final effective set. Test partial clearance and incomparable pipelines.
- [x] Implement one `FinalizeRoutingPlan` boundary that receives pure decisions plus clearance lookups and returns both shadow and effective plans; D2 is now available, so no temporary clearance seam is needed.
- [x] Write failing alarm tests for binding/gate conflict, decision-relevant operator failure, policy load/integrity failure, fallback warning, and exactly-one dedupe per run before processor execution.
- [x] Add append-only `kb.pipeline_policy_events` and neutral `policyaudit.Writer`/SQL store so doc-processing, ontology modules, and handlers can emit events without import cycles.
- [x] Wire and test content-safe stable-id events now for binding/rule authoring, policy activation, conflicts, fallback, clearance approval/revocation, and enforced/shadow decisions. Later G/H tasks explicitly wire classifier and module promotion events through the same writer.
- [x] Verify irrelevant evaluator errors remain trace-only.
- [x] Run doc-processing and affected handler tests; commit.

## Chunk F — Deterministic review-profile selection

### Task F1: Review selection schema and released-profile loader

**Files:**
- Create: `ChenWeb/project_migrations/20260801000019_extend_kb_ontology_review_scopes_for_p5.sql`
- Modify: `ChenWeb/server/api/ontology/profiles/profiles_store.go`
- Modify: `ChenWeb/server/api/ontology/profiles/review_scopes_store.go`
- Test: `ChenWeb/server/api/ontology/profiles/profiles_store_test.go`
- Test: `ChenWeb/server/api/ontology/profiles/review_scopes_store_test.go`

- [x] Write separate failing tests for nullable-compatible columns, one-store derivation, stable attempt id, exact release pins/checksums, visibility, short repeatable-read transaction, and historical reload after activation changes.
- [x] Add the five P5 scope columns with explicit-mode-compatible defaults; implement the pinned loader and scope scan/create changes.
- [x] Run focused profile store tests; commit.

### Task F2: Profile and profile-rule applicability

**Files:**
- Create: `ChenWeb/server/api/ontology/profiles/select.go`
- Test: `ChenWeb/server/api/ontology/profiles/select_test.go`
- Create: `ChenWeb/server/api/ontology/profiles/selection_alarm.go`
- Test: `ChenWeb/server/api/ontology/profiles/selection_alarm_test.go`
- Modify: `ChenWeb/server/api/ontology/profiles/review_service.go`
- Test: `ChenWeb/server/api/ontology/profiles/review_service_test.go`
- Modify: `ChenWeb/server/api/kbhandler/ontology_review_scopes_handler.go`
- Test: `ChenWeb/server/api/kbhandler/ontology_review_scopes_handler_test.go`

- [x] Write individual failing tests for per-document/target subjects, overlapping true profiles, false/indeterminate snapshots, closed-dimension continuation, mixed-store/client-profile rejection, and one warning per indeterminate scope.
- [x] Run the shared cross-consumer predicate fixture from B3 and assert identical truth/trace.
- [x] Add failing review-service tests that evaluate each pinned profile rule's `applicability`, exclude only that rule on `false`, emit indeterminate applicability on decision-relevant `indeterminate`, and never add an unpinned profile/release.
- [x] Write a failing alarm test for exactly one warning row per indeterminate scope id, independent of run-id routing alarms; implement an injected `SelectionAlarmWriter` with a production `alarms_errors` store.
- [x] Implement selector, immutable snapshot, rule-level applicability, and scope-deduplicated warning while preserving explicit mode exactly.
- [x] Run profile and scope handler tests; commit.

## Chunk G — Mandatory-gated `classify_document`

### Task G1: Classifier contract and registration

**Files:**
- Create: `ChenWeb/prompts/prompt-classify-document-v1.md`
- Create: `ChenWeb/server/api/doc-processing/classify-document.go`
- Test: `ChenWeb/server/api/doc-processing/classify-document_test.go`
- Modify: `ChenWeb/server/api/doc-processing/processor_plan.go`
- Modify: `ChenWeb/server/api/doc-processing/runtime.go`
- Update: `ChenWeb/server/api/doc-processing/registries_test.go`

- [x] Write one failing test per contract: requested governed keys only, bounded sample, unknown value rejection, confidence/evidence, stable retry, content-safe audit event, and `mandatory_gated` immunity.
- [x] Implement injected-client classifier and versioned prompt; inject E3's `policyaudit.Writer` for invocation/result events and register outside ordinary Phase A/B/C waves.
- [x] Run focused tests; commit.

### Task G2: Two-pass extraction and review resolvers

**Files:**
- Create: `ChenWeb/server/api/doc-processing/applicability_resolver.go`
- Test: `ChenWeb/server/api/doc-processing/applicability_resolver_test.go`
- Modify: `ChenWeb/server/api/doc-processing/control.go`
- Test: `ChenWeb/server/api/doc-processing/control_test.go`
- Modify: `ChenWeb/server/api/ontology/profiles/select.go`
- Test: `ChenWeb/server/api/ontology/profiles/select_test.go`

- [x] Write separate failing tests for decision-relevant versus masked missing paths, one invocation per record/extraction run, one per record/review attempt, partially failed retry, multi-document review, classifier failure, concurrent invocation observations, and activation change between release pin/final scope.
- [x] Implement shared two-pass orchestration with consumer-specific decision relevance; review-time calls write only facets and never run extraction/Phase D.
- [x] Run the exact test files above and commit.

## Chunk H — Module proposals and separate promotion

### Task H1: Governed proposal lifecycle and release snapshot

**Files:**
- Create: `ChenWeb/project_migrations/20260801000020_create_kb_ontology_applicability_proposals.sql`
- Create: `ChenWeb/server/api/ontology/modules/applicability_proposals.go`
- Test: `ChenWeb/server/api/ontology/modules/applicability_proposals_test.go`
- Create: `ChenWeb/server/api/kbhandler/ontology_applicability_proposals_handler.go`
- Test: `ChenWeb/server/api/kbhandler/ontology_applicability_proposals_handler_test.go`
- Modify: `ChenWeb/server/api/ontology/modules/validate.go`
- Modify: `ChenWeb/server/api/ontology/modules/releases_store.go`
- Modify: `ChenWeb/server/api/routes.go`

- [x] Write failing store/handler tests for `draft -> in_review -> approved -> included_in_release`, invalid transitions, unauthenticated/unauthorized rejection, owner/admin/`k_engineer` curator authorization through D2's helper, actor derivation, predicate/checksum validation, source release pinning, and failed release preserving activation.
- [x] Add append-only/versioned proposal rows and create/read/transition APIs; derive curator identity from request context, emit E3 policy-audit events, and include only approved proposals in the immutable module snapshot.
- [x] Reuse only neutral `semrules.AnalyzeOverlap` to annotate proposal pairs as disjoint/may-overlap/unanalyzable. Do not make policy-level conflict decisions in the modules package; H2 passes proposals to E2's policy compiler, which owns binding/gate interpretation.
- [x] Run module/handler/compiler tests; commit.

### Task H2: Automatically materialize release proposals as a draft policy only

**Files:**
- Create: `ChenWeb/server/api/doc-processing/policy_promotion.go`
- Test: `ChenWeb/server/api/doc-processing/policy_promotion_test.go`
- Modify: `ChenWeb/server/api/ontology/modules/releases_store.go`
- Create: `ChenWeb/server/api/ontology/modules/releases_store_test.go`
- Modify: `ChenWeb/server/cmd/ontology-compiler/main.go`

- [x] Write failing tests proving both release creation (the DB-native import boundary) and later activation call `EnsureDraftFromModuleRelease` inside their transactions; verify exact release provenance, same-release idempotency, a new draft policy version for a distinct immutable release, compiler reuse, rollback on promotion failure, and unchanged active routing policy.
- [x] Define the minimal `modules.DraftPolicyPromoter` transaction interface required to make those tests green, implemented by `docprocessing.PolicyPromotionStore`; dependency direction stays `command -> modules/docprocessing`.
- [x] Wire the production promoter and E3 `policyaudit.Writer` in `ontology-compiler`; module release/activation automatically ensures the source release's draft policy exists, while routing activation remains E2's separate authenticated endpoint.
- [x] Run focused tests; commit.

## Chunk I — Exit suite, live proof, and documentation closeout

### Task I1: Named acceptance-criteria tests

**Files:**
- Create: `ChenWeb/server/api/doc-processing/p5_exit_test.go`
- Create: `ChenWeb/server/api/ontology/profiles/p5_exit_test.go`

- [x] Add named mappings: criteria 1–4 → `semrules` tests; 5–6 → legacy/binding tests; 7–8 → gate/enforcement/alarm tests; 9–10 → shared fixture/scope tests; 11 → two-pass classifier tests; 12–13 → proposal/policy compiler activation tests; 14 → `TestPersistedP5PlanReloadIgnoresLaterActivation` plus review reload; 15–16 → benchmark/clearance tests.
- [x] Add a consolidated test that fails if any criterion lacks at least one named test/live-proof pointer, matching the P2/P3 exit-test convention.
- [x] Run all focused suites and commit.

### Task I2: Live PostgreSQL and synthetic-corpus proof

**Files:**
- Create: `KnowledgeStore/doc-repo/devdocs/202608/2026080107-devdoc-ontology-p5-implementation-log.md`

- [ ] Apply Goose migrations `20260801000015`–`20260801000020` to `chenweb_test` through the normal datasource path and record schema/version evidence.
- [ ] Create disposable data and prove legacy parity; override precedence; invalid activation rollback; block/fallback alarm dedupe; shadow/partial/cleared enforcement; clearance replacement/revocation and corrupt-multiple fail closed; extraction/review snapshot reload after activation changes; review rule applicability; classifier retries/concurrency; and module promotion without activation.
- [ ] Run routing-off/on against the existing synthetic corpus. Record exact cost/yield/recall/precision and leave insufficient slices shadow-only.
- [ ] Clean disposable rows through governed lifecycle/store methods and record what remains.

### Task I3: Verification, docs, and repository closeout

**Files:**
- Modify: `KnowledgeStore/Capsules/coding-capsules/ontology/+CAPSULE.md`
- Modify: `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md`
- Modify: `KnowledgeStore/doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md` (P5 status only; preserve unrelated edits)
- Modify: `KnowledgeStore/doc-repo/hand-offs/202607/2026073002-handoff-semos-ontology-status.md`
- Modify: `KnowledgeStore/doc-repo/devdocs/202608/2026080107-devdoc-ontology-p5-implementation-log.md`

- [x] Run `go test ./server/api/ontology/semrules ./server/api/doc-processing ./server/api/ontology/profiles ./server/api/ontology/modules ./server/api/doc-benchmark ./server/api/kbhandler -count=1`.
- [x] Run `go vet ./server/api/ontology/... ./server/api/doc-processing/... ./server/api/doc-benchmark/...` and build `./server/cmd/ontology-compiler` and `./server/cmd/doc-benchmark`.
- [x] Document what knowledge changed, affected/updated/stale docs, and intentionally undocumented authority fixture values.
- [x] Commit ChenWeb and KnowledgeStore separately with `jj`; commit only P5 paths around the pre-existing ADR work, then verify linear `jj log` and clean expected status in both repositories.

## Verification boundary

P5 generic runtime may be declared complete only when all automated acceptance mappings and live
mechanism proofs pass. The ADR's final per-document-kind reduction/no-recall-loss exit is declared
only for slices that meet the exact clearance gate. The authority-confirmed ventilator conclusion
remains blocked by the P4 data fixture and must remain documented as such.
