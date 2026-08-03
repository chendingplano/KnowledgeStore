# Bug: SemOS P5 rule-driven routing declared complete but is not finished (wiring gaps, correctness bugs, unmerged work)

Date: 2026-08-03\
Status: open\
System: `SemOS` / `ChenWeb`\
Component: P5 rule-driven routing — `server/api/ontology/semrules`, `server/api/doc-processing` (bindings/gates/enforcement/clearance/alarm/compile/classify/resolver/promotion), `server/api/ontology/profiles` (deterministic selection), `server/api/ontology/modules` (proposals), `server/api/ontology/policyaudit`, `server/api/kbhandler`, `server/cmd/ontology-compiler`, migrations `20260801000015`–`20260801000022`\
Model: n/a (code-review audit; the tier-3 classifier would use `CLASSIFY_DOCUMENT_MODEL_NAME`, default `deepseek-chat`, but it is not wired)

## Summary

The working assumption — *"P5 (rule-driven routing) is completely finished except I2 (live PostgreSQL/synthetic-corpus proof)"* — is **not accurate**. The P5 components exist, are well-structured, and pass every P5-specific unit test, but three structural facts stand between the code and "finished," and the parts that *are* wired contain several real correctness defects. In short: the components are implemented and unit-tested as **isolated libraries**, but **Chunk G (tier-3 `classify_document`) is dead code in production, Chunk H (proposals → draft-policy promotion) is functionally non-operational, nothing past Chunk F is merged to `main`, and a large unmerged "fixing P5 implementation bugs" commit supplies wiring the implementation log claimed was already done.** I2 is genuinely deferred and is the *only operationally* remaining item — but it is not the *only* remaining item; several code-level items are outstanding before I2 could pass.

## Baseline consulted

- ADR `2026072901-adr-ontology-platform-and-adaptive-pipeline.md` (P5 change-log entry 2026-08-03; §8.3.8 exit criterion)
- Spec `2026080102-spec-semos-p5-rule-driven-routing.md` (especially §12, the 16 acceptance criteria)
- Plan `2026080103-plan-semos-p5-rule-driven-routing.md` (task checklist A1–I3)
- Implementation log `2026080107-devdoc-semos-p5-implementation-log.md`
- Handoff `2026073002-handoff-semos-ontology-status.md` (P5 post-handoff updates)

## Section A — Completion status: what is actually true

### A1. Only chunks A–F are on `main`; G/H/I + bug fixes are unmerged

`jj bookmark list` shows a single bookmark: `main` at `otpr` (the E3–F2 merge, `7e778891`). The commits for G1, G2, H1, H2, I1 **and** `kksq "fixing P5 implementation bugs"` are floating commits above `main`, reachable only through the working-copy parent chain. `jj diff --from main --to @` = **27 files, +3434 lines** — the entire classifier, resolver, proposals store + migration `20260801000022`, promotion, exit tests, and the fix-commit wiring (`control.go`, `pipeline_bindings.go`, `policyaudit`, `routes.go`, `ontology-compiler`). A build from `main` has none of it.

The plan's own I3 closeout checkbox ("commit ChenWeb and KnowledgeStore separately… verify linear `jj log`") is **unchecked**.

### A2. The "fixing P5 implementation bugs" commit proves the implementation log was premature

The implementation log (dated 08-02) claims Chunks G/H/I complete. The unmerged fix commit (`kksq`, 1122 insertions, 20 files) then had to add things the log implied already existed:

- the `ontology_applicability_proposals_handler.go` — plan H1's handler, required by the plan but never mentioned as created in the log;
- the promotion-adapter rework — the original `PromoteModuleReleaseProposals` used an unexported `proposalRecord` type that `modules.ProposalStore` structurally could not satisfy (it was unwireable);
- the classifier wiring into `control.go` (the `Resolver` field + `ResolveExtractionFacts` call) and the enriched-facts overlay into `pipeline_bindings.go`;
- proposal audit-event kinds in `policyaudit`.

Without that commit, G2 and H2 did nothing. The "complete" claim was written against a tree that did not yet have working wiring.

### A3. Chunk G (tier-3 `classify_document`) is dead code in production

- `NewDocumentClassifier` and `NewApplicabilityResolver` have **zero non-test callers** anywhere in `server/` and `cmd/` (grep-verified).
- The production `ControlService` at `server/api/doc-processing/runtime.go:140` leaves `Resolver` nil; the only call site `server/api/doc-processing/control.go:665` is `if s.Resolver != nil` guarded, so it never runs.
- Even if wired, that call passes `runID=0` and an **empty document sample**: `ResolveExtractionFacts(ctx, planFacts, evt.RecordID, 0, "")`. `runID=0` collapses every invocation to `invocation_id = "extraction-<recordID>-0"`, which permanently short-circuits later runs via the stable-retry path; the empty sample means no text to classify.
- `VocabularyReleaseID` is hardcoded `0` (`server/api/doc-processing/applicability_resolver.go:185`); no governed-vocabulary source exists. The review consumer (`server/api/ontology/profiles/select.go`) never references the resolver at all — review-time classification is absent.

### A4. Chunk H (promotion) is functionally non-operational

`server/cmd/ontology-compiler/main.go` `runRelease` calls `PromoteModuleReleaseProposals` **after** `CreateRelease` commits (outside the transaction), on a fresh `rel.ID` that no proposal can reference yet (proposals are authored via the HTTP API against an *existing* release id), and a failure is downgraded to `log.Printf("warning: …")`. `runActivate` **never promotes**. `server/api/ontology/modules/releases_store.go` has zero promoter calls in either `CreateRelease` or `Activate`. Additionally, proposal checksums are raw SHA-256 of client bytes, not canonical (`semrules.Canonicalize`), so `server/api/doc-processing/policy_compile.go:179-181` would reject a promoted draft at activation.

### A5. I2 is genuinely deferred — and it is the ADR's exit criterion

I2 (live Postgres + synthetic corpus) maps to the ADR §8.3.8 P5 exit: *"a documented, per-document-kind reduction in processor invocations with no measured loss of review recall on the benchmark corpus; every skip explainable from its plan."* That part of the assumption holds. But I2 would also be the first place the bugs below would surface — so it is not merely "run the proof," it is "the proof is not ready to pass."

## Section B — Correctness findings

Key: **✓ = verified directly by the reviewer against the code**; unmarked items came from parallel deep-review agents at file:line and were spot-checked where feasible.

### Critical / contract-breaking

| # | Finding | Location |
|---|---|---|
| ✓ | **Legacy migrated bindings can never be cleared.** Migration `20260801000015` writes `predicate_checksum = md5(predicate::text)` for migrated rows; `policy_compile.loadBindings` overwrites it with the canonical SHA-256; runtime clearance lookups carry the md5 value. An approved clearance for a migrated conditional binding therefore never matches at runtime → always fails closed to shadow with a fallback alarm. Breaks acceptance criterion 16 for exactly the migrated P1 class P5 exists to migrate. Fail-safe, but the compatibility story is broken. | `project_migrations/20260801000015_add_p5_pipeline_predicates.sql:176`, `server/api/doc-processing/policy_compile.go:308-316`, `server/api/doc-processing/pipeline_bindings.go:139` |
| ✓ | **Chunk G is not wired** (A3 above) — the tier-3 mechanism, which acceptance criterion 11 is entirely about, can never run. | `runtime.go:140`, `control.go:665` |
| ✓ | **Chunk H promotion is non-operational** (A4 above) — no working path from approved proposal to draft policy. | `server/cmd/ontology-compiler/main.go`, `server/api/ontology/modules/releases_store.go` |
| ✓ | **`semrules` decision-relevance masking is order-dependent.** `all[missing, false]` and `any[missing, true]` report the earlier missing path as decision-relevant even though the later sibling fixes the result → spurious `classify_document` invocations and misleading traces (violates criterion 11 and spec §7.2). All masking tests place the deciding child *first*, so the bug ships green. | `server/api/ontology/semrules/evaluate.go:57-71`, `:87-100` |
| ✓ | **`frozenSubjectFacts` matches by `DocumentID` only**, ignoring `TargetObjectID`. For a scope with multiple targets of the same document, every pinned rule gates against the first target's facts — a rule referencing `object.class` can be applied to the wrong target. | `server/api/ontology/profiles/review_service.go:282-296` |
| ✓ | **Indeterminate-only profiles are never pinned**, so their intersecting closed dimensions silently produce no findings at all — the outcome spec §6 forbids ("affected subject/dimension yields an indeterminate result/finding"). The operator only sees `selection_status=indeterminate` plus a warning. | `server/api/ontology/profiles/select.go:277-290` |

### Important

| # | Finding |
|---|---|
| **Gate block mode is unreachable.** `DOC_PIPELINE_ON_CONFLICT` is never read anywhere. Bindings are hardcoded to block and gates hardcoded to `fallback` — the spec's dual mode exists only for binding conflicts; gate conflicts never block, and the binding fallback ladder is dead code exercised only by tests. |
| **Run-scoped processor-gate overrides are dead code.** `ProductionPlanFacts.ProcessorGateOverrides` is read but never populated — the event parser only extracts `Operations`/`PipelineOverride`, so the `run_override` precedence path cannot fire in production. |
| **Store-default fallback ignores the record's knowledge store.** `server/api/doc-processing/pipeline_bindings.go:298-317` returns the first `store_default` row regardless of `KnowledgeStoreID` — a multi-store deployment can route a record to another store's default pipeline. |
| **Enforcement-order gap on fallback.** When an uncleared suppressive binding falls back to the baseline pipeline in enforced mode, the re-admitted processors are absent from the gate shadow and run without gate evaluation. |
| **Wrong-typed runtime fact values collapse to `operator_error` instead of `invalid_fact`** — and §11 treats operator failure as a fail-closed alarm while invalid facts are indeterminate/trace-only. A malformed producer value would trip the alarm path. |
| **`EvaluateDocument` never validates** — a structurally invalid predicate (e.g. `not` with two children) silently becomes `indeterminate` instead of a compile error (spec §3.2). |
| **Proposal lifecycle is TOCTOU and `included_in_release` is a manual, unverified HTTP transition.** `TransitionProposal` reads status then updates with no `WHERE status = …` / optimistic concurrency; the release path never sets `included_in_release`, contradicting the candidates convention and plan H1 ("include only approved proposals in the immutable module snapshot"). Any authorized curator can mark any approved proposal `included_in_release` against an arbitrary release id. |
| **`EnsureDraftFromModuleRelease` is non-atomic.** Draft INSERT and binding inserts are separate autocommit statements; partial drafts persist, idempotency is fragile, and versioning has a `MAX(version)+1` race with no unique constraint. |
| **Active-policy load failure silently falls back to legacy** (`server/api/doc-processing/control.go:1539-1544`) — a load *failure* is indistinguishable from "no active policy," despite §11 requiring it to be an error. |

### Minor (representative)

- `in`/`not_in` element order changes the canonical checksum — semantically identical predicates get different checksums (undermines compiler dedup and DR7 specificity).
- Numeric facet `2` vs `2.0` become spuriously conflicting (`canonicalFactValueKey` JSON-marshals the raw value before `semrules` lossless numeric comparison).
- Classifier truncates the sample by bytes, splitting UTF-8 for CJK documents; conflates a legitimate empty classification with LLM failure; `document.jurisdiction` uses a different vocabulary scheme-key than the other tier-3 paths.
- Alarm writer has a NULL-kind insert path that would error (no partial-index arbiter); empty `reason_code` on indeterminate logical trace nodes; `overlap.go` has dead/inverted flags and an unreachable return; a known fact with nil confidence bypasses `min_confidence`.

### Not found

- No critical truth-value bug in the three-valued core — the Kleene logic, typed operators, validation, canonical checksum, and fact registry are correct.
- No path where an *uncleared* suppressive decision changes execution — the shadow/effective separation and "mandatory processors never gated" hold. E3's `FinalizeRoutingPlan` enforcement ordering itself is correct.

## Section C — Test assessment

**P5-specific suites all pass** (re-run by the reviewer): `semrules`, `profiles`, `modules`, `policyaudit`, `doc-benchmark` — all green; all P5-named tests in `doc-processing` and `kbhandler` — green.

**The pre-existing failures are real and unrelated to P5.** `doc-processing` has 15 failing tests and `kbhandler` 14 — all legacy (summaries/topics/metrics/products/graphs/search-registry). One was spot-checked: a sqlmock expectation-order break in the metrics store, unrelated to P5.

**The I1 exit-test machinery is genuinely good** — `p5_exit_test.go` maps all 16 acceptance criteria to named tests and uses `go/parser` to verify each name resolves to a real `func Test*` (mechanism verified; it fails on phantom names).

**But the exit tests prove name-resolution, not reachability:**

- Criterion 11's classifier tests pass while the classifier is dead code — the registry never checks that a test exercises the production path.
- The `semrules` masking bug ships green (all masking tests put the deciding child first — no `all[missing, false]`/`any[missing, true]`).
- The legacy md5-vs-SHA-256 checksum break (criterion 16) is untested — the store test mocks a canonical-looking checksum.
- `sqlmock` structurally cannot cover the partial unique indexes, advisory locks, or `FOR SHARE`/`FOR UPDATE` semantics — those are genuinely deferred to I2, as the tests themselves note.

## Verification method

- Ran `go test` across all P5-affected packages and the P5-named subsets; `go vet`/`go build` per the impl log were reported clean.
- Inspected `jj bookmark list`, `jj log`, `jj diff --from main --to @`, and the fix-commit diff to establish the merge state.
- Directly read and verified the checksum-mismatch chain (migration → compiler → runtime clearance lookup), the resolver/classifier wiring, the promotion transaction boundary, the `all`/`any` masking loop, `frozenSubjectFacts`, the indeterminate-only pin decision, and the `VocabularyRelease=0` provenance.
- The remaining findings are attributed to five parallel deep-review agents (semrules, routing/enforcement, classifier/resolver, profiles, modules/authorization) at file:line.

## What would make P5 actually finished

1. **Merge G/H/I + the fix commit to `main`** (and push), then reconcile the plan checkboxes (A1–F2 are also still unchecked — the plan is not a reliable completion record) and the impl log's commit list.
2. **Wire Chunk G**: construct `NewDocumentClassifier` + `NewApplicabilityResolver` in the production runtime, set `ControlService.Resolver`, supply a real bounded document sample and a governed-vocabulary source (resolving `VocabularyReleaseID`), and wire review-time classification into `profiles/select.go`. Fix the `runID=0`/empty-sample call site.
3. **Repair Chunk H**: call the promoter inside `CreateRelease`/`Activate` transactions targeting the correct release, make `EnsureDraftFromModuleRelease` transactional and idempotent, and compute canonical proposal checksums.
4. **Fix checksum parity** so migrated bindings can actually be cleared (criterion 16).
5. **Address the semantic bugs**: `semrules` forward-masking, `frozenSubjectFacts` by target, indeterminate-only profile pinning, `DOC_PIPELINE_ON_CONFLICT` wiring, run-override parsing, per-store default fallback, `invalid_fact` vs `operator_error`.
6. Only then run **I2** (live Postgres + synthetic corpus) to meaningfully prove the ADR §8.3.8 exit criterion.

## Open Questions For Review

1. Is the "fixing P5 implementation bugs" commit meant to be merged to `main` next, or was it intentionally left floating? (Plan I3's commit checkbox is unchecked.)
2. Should the P5 completion claim in the ADR (2026-08-03 entry) and the handoff be corrected to reflect: not merged, G unwired, H non-operational?
3. For criterion 16's checksum parity: is the md5-in-migration the intended migration-time value with a compile-time canonical overwrite, or is that a genuine one-directional inconsistency? As written, migrated suppressive bindings can never be cleared.

## Change Record

No code, schema, or documentation changes were made as part of this audit. The review is a read-only inspection of the working tree as of 2026-08-03 (working copy `pmtv`, clean; `main` at `otpr`).

## Documentation Impact

What knowledge changed:
- P5 is **not** complete in the code-level sense the ADR/handoff/impl log claim: G is unwired dead code, H is functionally non-operational, and the G/H/I work plus a substantial bug-fix commit are not on `main`.
- The implementation log's completeness claims were written before the "fixing P5 implementation bugs" commit, which supplies wiring the log asserted already existed.

Which docs/specs/ADRs are affected:
- ADR `2026072901` P5 status entry (2026-08-03) — overstates completion.
- Handoff `2026073002` P5 updates — overstates completion ("All code-level P5 work … is complete").
- Implementation log `2026080107` — commit list and G/H/I claims predate the fix commit; H1 handler and wiring are unrecorded.
- Plan `2026080103` — task checkboxes for A1–A4, B1–B3, C1, E3, F1, F2 are unchecked despite implemented code; I3 closeout unchecked.

Which docs were updated: this bug record only.

Which docs are now stale: the three documents above, until P5 reaches a state where the claims match the tree.

What was intentionally left undocumented:
- No fix was applied; the six-step remediation list is a proposal, not a commitment.
- Authority-owned pilot values and editions remain out of scope (unchanged from the spec's own non-goals).
