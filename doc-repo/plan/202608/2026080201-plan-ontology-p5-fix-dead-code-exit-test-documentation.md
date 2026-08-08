# P5 Fix Plan: Dead Code Wiring, Exit Test Repair, Documentation

**Document ID:** `2026080201`
**Date:** 2026-08-02
**Status:** Draft
**Related:** ADR `2026072901`, Spec `2026080102`, Plan `2026080103`, DevDoc `2026080107`

---

## 1. Findings Summary

A review of P5 (SemOS rule-driven routing) identified three categories of problems beyond the already-known I2 (live operational proof):

### 1.1 G/H — Dead Code (ApplicabilityResolver, DocumentClassifier, PolicyPromotion)

| Component | Status | Issue |
|-----------|--------|-------|
| `ApplicabilityResolver` (`applicability_resolver.go`, 194 lines) | Implemented, unit-tested | **Never called from production** (`control.go`) |
| `DocumentClassifier` (`classify-document.go`, 459 lines) | Implemented, unit-tested | **Never called from production** (`control.go`) |
| `ControlService` struct | Missing fields | No `Classifier` or `Resolver` fields |
| `PromoteModuleReleaseProposals` (`policy_promotion.go`) | Type mismatch | `proposalLister` interface expects `[]proposalRecord` but `ProposalStore.ListApprovedProposals` returns `[]ApplicabilityProposal` |
| `ontology-compiler/main.go` | Missing call | `runRelease` and `runActivate` never call promotion |
| HTTP handler for proposals | Missing | Plan H1 calls for `kbhandler/ontology_applicability_proposals_handler.go` — never created |
| Routes for proposals | Missing | No proposal routes registered in `routes.go` |

### 1.2 I1 — Fabricated Exit Test

- `p5_exit_test.go` (doc-processing) maps 16 acceptance criteria to ~35 named test pointers.
- `TestP5AcceptanceCriteriaCoverage` only checks `len(tests) > 0` — it **never verifies the named tests exist** as actual `func Test*` functions.
- **~15 of ~35 names are phantom** — no corresponding Go test function exists anywhere in the codebase.

Key phantom names:
- `TestTypedOperatorBehavior` (real: `TestEvaluateDocumentTypedOperators`)
- `TestExistsDistinguishesMissingFromUnusable` (real: `TestEvaluateDocumentIndeterminateReasons`)
- `TestProcessorGateEffects` (real: `TestResolveProcessorGateIteratesRanksAndUsesEffectPrecedence`)
- `TestRoutingEnforcementBlocksOnConflict` (no direct match; covered by `TestFinalizeRoutingPlan_*` tests)
- `TestPolicyCompileFailureLeavesActiveUntouched` (no match — needs new test)
- `TestBenchmarkReportRecordsCostYield` (no match — needs new test)
- `TestReviewReloadAfterActivationChange` (no match — needs new test)

### 1.3 I3 — Missing Documentation

| Document | Issue |
|----------|-------|
| `KnowledgeStore/Capsules/coding-capsules/ontology/+CAPSULE.md` | No P5 mention |
| ADR `2026072901` changelog | No P5 implementation status annotation |
| Plan `2026080103` checklist | Most checkboxes still unchecked despite implementation |

---

## 2. Fix Plan

### Phase A: G/H Production Wiring

#### A1. Wire ApplicabilityResolver into ControlService

**File:** `ChenWeb/server/api/doc-processing/control.go`

- Add `Resolver *ApplicabilityResolver` field to `ControlService` struct.
- In `handleEvent`, after `resolveProductionPlanFacts` succeeds and before `BuildProductionProcessorPlanFromFacts`, call `Resolver.ResolveExtractionFacts` when `Resolver != nil`.
- Use the enriched `semrules.FactSet` for downstream binding/gate evaluation.
- **Nil-safe:** when `Resolver` is nil, behavior is unchanged (base facts only).

#### A2. Fix PromoteModuleReleaseProposals type mismatch

**File:** `ChenWeb/server/api/doc-processing/policy_promotion.go`

- Replace the `proposalLister` interface (which expects `[]proposalRecord`) with an adapter that accepts `[]ApplicabilityProposal` from `modules.ProposalStore` and converts to `[]PromotedProposal`.
- Remove the `proposalRecord` shim type.
- The adapter avoids the import cycle (`modules` → `profiles` → `docprocessing` → `modules`).

#### A3. Wire promotion into ontology-compiler

**File:** `ChenWeb/server/cmd/ontology-compiler/main.go`

- In `runRelease`: after `rs.CreateRelease` succeeds, call `PromoteModuleReleaseProposals` with the new release's ID and checksum.
- Wire `PolicyPromotionStore{DB: db, Audit: policyaudit.SQLWriter{DB: db}}` as the `DraftPolicyPromoter`.
- Per spec §8, promotion happens at release time, not activation.

#### A4. Create proposals HTTP handler

**File:** `ChenWeb/server/api/kbhandler/ontology_applicability_proposals_handler.go` (new)

Follow the pattern from `pipeline_routing_clearances_handler.go`:
- Echo handlers with `EchoFactory.NewFromEcho`
- Auth via `pipelineRoutingAuthorizer`
- `decodeStrictJSON` for request validation
- Audit events via `writePolicyAuditEvent`

**Endpoints:**

| Method | Path | Handler | Description |
|--------|------|---------|-------------|
| POST | `/kb/ontology/applicability-proposals` | `CreateApplicabilityProposal` | Create draft proposal |
| GET | `/kb/ontology/applicability-proposals/:id` | `GetApplicabilityProposal` | Get proposal by ID |
| POST | `/kb/ontology/applicability-proposals/:id/transition` | `TransitionApplicabilityProposal` | Transition status |
| GET | `/kb/ontology/applicability-proposals` | `ListApplicabilityProposals` | List proposals (filter by release_id, status) |

#### A5. Register proposal routes

**File:** `ChenWeb/server/api/routes.go`

Add 4 routes after the existing ontology routes block (after line 477).

---

### Phase B: I1 Exit Test Repair

#### B1. Replace phantom names with real test function names

**Files:**
- `ChenWeb/server/api/doc-processing/p5_exit_test.go`
- `ChenWeb/server/api/ontology/profiles/p5_exit_test.go`

**Complete name mapping:**

| Criterion | Phantom Name | Real Name | Status |
|-----------|-------------|-----------|--------|
| 1 | `TestEvaluateDocumentTruthTables` | `TestEvaluateDocumentTruthTablesAndDecisionRelevantMissingPaths` | Rename |
| 1 | `TestTypedOperatorBehavior` | `TestEvaluateDocumentTypedOperators` | Rename |
| 2 | `TestExistsDistinguishesMissingFromUnusable` | `TestEvaluateDocumentIndeterminateReasons` | Rename |
| 2 | `TestStructuredTraceDistinguishesFactStates` | `TestFactStates` | Rename |
| 3 | `TestValidateRejectsMalformedPredicates` | `TestValidateRejectsInvalidDocuments` | Rename |
| 3 | `TestValidateRejectsUnknownPaths` | `TestValidateRejectsInvalidDocuments` | Same test |
| 4 | `TestRequiredFactExtractionDeterministic` | `TestAnalyzeReturnsStableRequirementsAndDistinctSpecificity` | Rename |
| 4 | `TestSpecificityDeterministic` | `TestAnalyzeReturnsStableRequirementsAndDistinctSpecificity` | Same test |
| 5 | `TestLegacyRulePredicateDocument` | `TestPipelineBindingLegacyAdapterCanonicalPathsOrderAndChecksum` | Rename |
| 5 | `TestBuildPipelineBindingFactSet` | — | **New test** |
| 6 | `TestResolvePipelineBindingsConditionalOutranksStoreDefault` | `TestPipelineBindingDR7DecisionTable` | Rename |
| 6 | `TestResolvePipelineBindingsTrueFalseIndeterminate` | `TestPipelineBindingDR7DecisionTable` | Same test |
| 7 | `TestProcessorGateEffects` | `TestResolveProcessorGateIteratesRanksAndUsesEffectPrecedence` | Rename |
| 7 | `TestProcessorGateShadowOnly` | `TestBuildProcessorGateShadowPlanDoesNotChangeEffectiveProcessors` | Rename |
| 7 | `TestProcessorGateDeferTies` | `TestResolveProcessorGateFallbackDefaultsAndDeferFingerprint` | Rename |
| 8 | `TestRoutingEnforcementBlocksOnConflict` | `TestFinalizeRoutingPlan_OperatorFailureFailsClosedAndAlarms` | Rename |
| 8 | `TestRoutingAlarmExactlyOnePerRun` | `TestDedupeRoutingAlarmsKeepsExactlyOnePerKind` | Rename |
| 9 | `TestReviewProfileSelectionIdenticalPredicates` | `TestSelectEvaluatesEachProfileOncePerDocumentTargetSubject` | Rename |
| 9 | `TestReviewProfileReleasePinsSurviveActivation` | `TestLoadReleasedProfilesPinsReleaseIDsAndChecksums` | Rename |
| 10 | `TestDeterministicScopeCreationOneKnowledgeStore` | `TestSelectRejectsDuplicateKnownFactProducers` | Rename |
| 10 | `TestScopeCreationAtomicPinsAndSnapshots` | `TestSelectSnapshotCarriesPinnedReleaseAndPredicateChecksums` | Rename |
| 10 | `TestScopeCreationExplicitIndeterminateContinuation` | `TestSelectMarksScopeIndeterminateWhenProfileClosedDimensionsIntersectRequest` | Rename |
| 10 | `TestScopeCreationLeavesExplicitP4ScopesByteCompatible` | — | **New test** |
| 11 | `TestApplicabilityResolverTwoPass` | `TestResolverDecisionRelevantUnmaskedTier3Path` | Rename |
| 11 | `TestApplicabilityResolverOneInvocationPerRun` | `TestResolverOneInvocationPerRecordExtractionRun` | Rename |
| 11 | `TestClassifyDocumentMandatoryGatedImmunity` | `TestClassifyDocumentMandatoryGatedImmunity` | ✅ Exact |
| 11 | `TestApplicabilityResolverEnrichedFactsDontOverwrite` | `TestResolverEnrichedFactsDoNotOverwriteKnown` | Rename |
| 12 | `TestPolicyPromotionStoreImplementsInterface` | `TestPolicyPromotionStoreImplementsInterface` | ✅ Exact |
| 12 | `TestPolicyPromotionStoreRequiresReleaseID` | `TestPolicyPromotionStoreRequiresReleaseID` | ✅ Exact |
| 12 | `TestPolicyPromotionStoreRequiresChecksum` | `TestPolicyPromotionStoreRequiresChecksum` | ✅ Exact |
| 13 | `TestPolicyCompileFailureLeavesActiveUntouched` | — | **New test** |
| 13 | `TestPolicyActivationFailureRollback` | — | **New test** |
| 14 | `TestPersistedP5PlanReloadIgnoresLaterActivation` | `TestPersistedP5PlanReloadIgnoresLaterActivation` | ✅ Exact |
| 14 | `TestReviewReloadAfterActivationChange` | — | **New test** |
| 15 | `TestBenchmarkReportRecordsCostYield` | — | **New test** |
| 15 | `TestBenchmarkReportRecordsRecallPrecision` | — | **New test** |
| 16 | `TestRoutingEnforcementClearanceGate` | `TestFinalizeRoutingPlan_IncomparablePipelineIsSuppressiveAndGatedByClearance` | Rename |
| 16 | `TestRoutingClearanceRevocationReturnsToShadow` | `TestRoutingClearanceRevokeIsAppendOnly` | Rename |

#### B2. Add missing tests for uncovered criteria

New test functions needed:

1. **`TestBuildPipelineBindingFactSet`** (criterion 5) — verify fact set construction from `ProductionPlanFacts`, ensure all expected paths are populated
2. **`TestScopeCreationLeavesExplicitP4ScopesByteCompatible`** (criterion 10) — verify P4 scopes unchanged by P5 selection
3. **`TestPolicyCompileFailureLeavesActiveUntouched`** (criterion 13) — verify failed compile doesn't change active policy version
4. **`TestPolicyActivationFailureRollback`** (criterion 13) — verify failed activation preserves prior active version
5. **`TestReviewReloadAfterActivationChange`** (criterion 14) — verify review snapshots reproducible after module activation change
6. **`TestBenchmarkReportRecordsCostYield`** (criterion 15) — verify report includes cost/yield fields
7. **`TestBenchmarkReportRecordsRecallPrecision`** (criterion 15) — verify report includes recall/precision metrics

#### B3. Strengthen coverage verification

**Files:** Both `p5_exit_test.go` files

Change `TestP5AcceptanceCriteriaCoverage` to verify each named test exists as an actual `func Test*` function:

**Recommended approach:** Use `go/parser` to scan `_test.go` files in the relevant packages and verify each name in the registry resolves to a real function declaration. This runs at test time and fails fast if a name is phantom.

---

### Phase C: I3 Documentation

#### C1. Update ontology capsule

**File:** `KnowledgeStore/Capsules/coding-capsules/ontology/+CAPSULE.md`

Add P5 section describing:
- Rule-driven routing with three-valued applicability semantics
- semrules evaluator (predicate grammar, truth tables, typed operators)
- Pipeline bindings (conditional/store_default) and processor gates (require/enable/skip/defer)
- classify_document two-pass resolver (tier-3 facets)
- Governed proposal lifecycle (draft → in_review → approved → included_in_release)
- Draft-policy promotion from module releases
- Benchmark clearance gate (suppressive decisions stay shadow unless cleared)

#### C2. Update ADR changelog

**File:** `KnowledgeStore/doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md`

Add P5 implementation status annotation in the changelog section.

#### C3. Update plan checklist

**File:** `KnowledgeStore/doc-repo/plan/202608/2026080103-plan-ontology-p5-rule-driven-routing.md`

Check off completed tasks: G1, G2, H1, H2, I1, I3.

---

### Phase D: Verification

- `go vet ./...` across all P5 packages
- `gofmt -l` on modified files
- `go test ./...` for: semrules, doc-processing, profiles, modules, doc-benchmark, policyaudit
- `go build ./...` for the full server
- Verify exit tests pass with real name resolution

---

## 3. Execution Order

```
A2 (type mismatch fix) ──→ A3 (ontology-compiler promotion)
A1 (resolver wiring)     ──→ (independent)
A4 + A5 (handler + routes) ──→ (independent)
B1 + B2 + B3 (exit test repair) ──→ (independent of A)
C1 + C2 + C3 (documentation) ──→ (independent)
D (verification) ──→ after all above
```

Parallelizable groups:
- **Group 1:** A1, A2, A4, A5 (independent code changes)
- **Group 2:** A3 (depends on A2)
- **Group 3:** B1, B2, B3 (independent test changes)
- **Group 4:** C1, C2, C3 (independent doc changes)
- **Group 5:** D (after all above)

---

## 4. Risk Assessment

| Risk | Mitigation |
|------|------------|
| Resolver wiring changes production routing behavior | Nil-safe design; Resolver=nil preserves current behavior |
| Type mismatch fix may break existing callers | `PromoteModuleReleaseProposals` is dead code — no callers |
| New tests may reveal actual bugs | Expected; fix inline |
| Exit test verification may be fragile | Use `go/parser` approach, not runtime reflection |

---

## 5. What Knowledge Changed?

- **Which docs/specs/ADRs/tests are affected?** ADR `2026072901` (P5 status), ontology capsule, P5 plan checklist, P5 exit tests, P5 implementation log.
- **Which docs were updated?** This plan document.
- **Which docs are now stale?** The P5 implementation log (`2026080107`) claims G/H/I complete — needs correction after fixes land.
- **What was intentionally left undocumented?** I2 (live operational proof) remains out of scope for this fix plan.
