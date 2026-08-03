# SemOS P5 Completion Plan

**Document ID:** `2026080303`
**Date:** 2026-08-03
**Status:** Draft — awaiting review
**Goal:** Close every defect in review `2026080302` so P5 can be declared complete against spec
`2026080102` §12 and ADR `2026072901` §8.3.8.

**Source of truth:** consolidated review `2026080302-devdoc-semos-p5-implementation-review.md`
(defect ids **P5-1 … P5-30**) · spec `2026080102` · original plan `2026080103`

**Supersedes:** fix plan `2026080201` (partially executed; residue folded in as Chunk H)

**Tech stack:** Go 1.25, PostgreSQL/Goose, Echo v4, `sqlmock`, `jj`.

**Workflow note:** P5 has been tracked with KnowledgeStore plan documents throughout
(`2026080103`, `2026080201`), not `ChenWeb/openspec/changes/`. This plan continues that convention.

---

## 0. Decisions — resolved 2026-08-03

All six decisions are answered. Recorded here because several change what gets built.

| # | Decision | Resolution |
|---|---|---|
| **D1** | Merge before or after fixing? | **Merge first.** Confirmed. It is a fast-forward bookmark move, not a rebase — see Task 0.1 for the root cause. |
| **D2** | P5-6 interim document kind, until the classifier works. | **Empty / fail closed.** Spec §9 mandates that a missing document kind leaves the subject shadow-only. Keeping `input_doc_type` fails *open* toward over-enforcement. Zero regression risk given D3's disposable-data ruling. |
| **D3** | P5-5 checksum parity direction. | **Fix-forward only; no backfill.** Existing rows are disposable and will be discarded, so no backfill migration is written. The runtime loader recomputes canonically and fails loudly on mismatch; the writer is corrected so fresh databases are right from the start. |
| **D4** | `classify_document` live, or behind a flag? | **Flag, default off** (`CLASSIFY_DOCUMENT_ENABLED=false`), mirroring `SEMANTIC_ASSOCIATION_ENABLED` from P3. Wiring is provable without LLM spend; Chunk I flips it for the proof run. |
| **D5** | Activation liveness. | **Implement in-process reload.** Restart-to-apply silently defeats E2's atomic activation and regresses P1. |
| **D6** | Scope. | **Full plan, Chunks 0–I.** |

### Standing constraint: existing data is disposable

Per D3, no task in this plan writes a data-backfill migration. Where a stored value is wrong
(predicate checksums, proposal checksums), the fix corrects the **writer** and adds a **loud
runtime guard**; existing rows are left to be discarded with the database. Any task that would
otherwise cost significant effort purely to preserve existing rows is out of scope. Schema
migrations that change structure are still required and still written.

---

## 1. Execution order and parallelism

```
Chunk 0 (merge + baseline)          ── must be first
   ├── Chunk A (semrules core)      ── pure, no deps
   ├── Chunk B (clearance identity) ── depends on A for canonical checksum helpers
   ├── Chunk C (enforcement/policy)
   ├── Chunk D (profiles)
   └── Chunk F (proposals/promotion)
Chunk E (classifier wiring)         ── depends on A (masking) + B (doc_kind)
Chunk G (tests/exit criteria)       ── depends on A–F
Chunk H (hygiene + doc corrections) ── depends on A–G for accurate status
Chunk I (I2 live proof)             ── last; gate for "P5 complete"
```

Parallelisable after Chunk 0: **{A, C, D, F}** are independent. **B** wants A's helpers. **E** is the
largest single task and should not be parallelised with **B**.

Every task is TDD: write the failing test, verify red, implement, verify green, commit with `jj`.

---

## Chunk 0 — Merge, baseline, and record reconciliation

### Task 0.1: Advance the `main` bookmark to the P5 tip

**Root cause (diagnosed 2026-08-03).** The commit chain is already linear; nothing is orphaned. Two
things left the label behind:

1. **jj bookmarks do not auto-advance.** Unlike git — where committing on an attached branch drags
   the branch pointer along — a jj bookmark stays put until explicitly moved. Six commits were
   created on top of `main` without `main` ever moving.
2. **The `aa15` commit was made on a detached HEAD.** `git branch -av` shows `* (no branch) aa15b2f3`,
   so git did not advance `main` either. Both tools agree `main = 41a5dd5b`.

Observed state:

```
@   4b1c  (empty working copy, no description)
○   aa15  fixing P5 implementation bugs
○   7011  I1 · 71d0 H2 · 7598 H1 · af8d G2 · 66aa G1
◆   41a5  [main] [main@git] [main@origin]   <- pinned six commits below @
```

`main@origin` is also at `41a5`, so GitHub carries none of G/H/I.

**This is a fast-forward label move — no rebase, no merge, no conflict risk.**

- [ ] Record the pre-move baseline failure list (15 `doc-processing`, 14 `kbhandler`) to a scratch
      file so any later regression is distinguishable.
- [ ] `jj bookmark set main -r @-` — targets `aa15`, skipping the empty undescribed working copy.
- [ ] Verify `jj bookmark list --all-remotes` shows `main`, `main@git` and `@-` in agreement, and
      `git branch -av` shows `main` at `aa15b2f3`.
- [ ] `jj git push` to advance `main@origin`.
- [ ] Re-run the full suite and diff against the recorded baseline — the failure set must be identical.
- [ ] **Do not use `git commit` for any subsequent work in this plan** (workspace CLAUDE.md); the
      detached-HEAD state above is exactly the failure mode that rule prevents.

### Task 0.2: Reconcile the plan record

- [ ] In plan `2026080103`, check off A1–A4, B1–B3, C1, E3, F1, F2 (implemented; verified by review
      `2026080302` §2) and leave I2 unchecked.
- [ ] Commit KnowledgeStore separately from ChenWeb.

---

## Chunk A — `semrules` core correctness

### Task A1: Logical (not positional) decision-relevance masking — **P5-7**

**Files:** `server/api/ontology/semrules/evaluate.go` · `evaluate_test.go`

- [ ] Write failing tests asserting `DecisionRelevantMissingPaths` is **identical** under child
      reordering, for `all[missing,false]` / `all[false,missing]` and `any[missing,true]` /
      `any[true,missing]`, plus nested cases under `not` and mixed three-child forms.
- [ ] Verify red — current output is `[document.doc_kind]` vs `[]`.
- [ ] Reimplement as two passes over `Items`: evaluate all children collecting truths, determine
      whether the node is already decided by a definitive child (`false` in `all`, `true` in `any`),
      then mark decision-relevance. Missing paths from indeterminate children are collected **only**
      when no definitive sibling exists, regardless of position.
- [ ] Keep every child present in the trace (plan A3's contract); only `DecisionRelevant` and the
      returned path list change.
- [ ] Add a regression test asserting order-independence for a predicate whose authored order differs
      from its canonical checksum order.

### Task A2: `invalid_fact` vs `operator_error` — **P5-14**

**Files:** `evaluate.go` · `evaluate_test.go`

- [ ] Failing test: a `FactKnown` value whose Go type contradicts the registry `FactType` must yield
      `ReasonInvalidFact`, not `ReasonOperatorError` (§11 routes the two differently).
- [ ] Distinguish *type mismatch on the observed value* (→ `invalid_fact`) from *operator failure on
      the authored operand* (→ `operator_error`) at `evaluate.go:209-214`.
- [ ] Verify no existing alarm test regresses.

### Task A3: Validate at evaluation time — **P5-15**

**Files:** `evaluate.go` · `evaluate_test.go`

- [ ] Failing test: `EvaluateDocument` on a structurally invalid document (two-child `not`, unknown
      kind, unknown version) must surface a distinguishable structural error rather than a plain
      `indeterminate`.
- [ ] Add `EvaluateDocumentValidated(Document, FactSet) (Result, error)` returning `Validate`'s error,
      and make every new consumer use it. Leave `EvaluateDocument` for legacy callers but set a
      distinct reason code (`ReasonInvalidPredicate`) on the root so traces are not silently ambiguous.
- [ ] Migrate the routing and selection consumers to the validated entry point.

### Task A4: `min_confidence` with absent confidence — **P5-16**

**Files:** `evaluate.go` · `evaluate_test.go`

- [ ] Failing test: `min_confidence = 0.9` against a `FactKnown` with `Confidence == nil` must **not**
      return `true`.
- [ ] Treat absent confidence as unsatisfiable when a threshold is declared →
      `TruthIndeterminate` / `ReasonConfidenceBelowMinimum`. Deterministic facets that legitimately
      carry no confidence must be given confidence `1.0` at construction rather than relying on the
      bypass; audit `BuildPipelineBindingFactSet` and `ReduceFacetObservations` for this.

### Task A5: Order-insensitive set operands + overlap cleanup — **P5-24, P5-27**

**Files:** `canonical.go` · `overlap.go` · `canonical_test.go` · `overlap_test.go`

- [ ] Failing test: `in[pdf,docx]` and `in[docx,pdf]` produce the same checksum (currently
      `6437aee5…` vs `8005c5f6…`). Child order of `all`/`any` **stays significant** — that is
      intentional (plan A2) and must be asserted as unchanged.
- [ ] Sort and de-duplicate `in`/`not_in` operand arrays inside `Canonicalize` only.
- [ ] Remove `leftHasExtra`/`rightHasExtra` and the unreachable `overlap.go:79` return; add a test
      pinning the conservative contract (never `MayOverlap:false` except genuinely disjoint values).

> **Checksum note:** A5 changes the canonical checksum of any predicate using `in`/`not_in`. Under
> D3 no backfill is written — existing rows are discarded with the database. Chunk B's runtime guard
> is what catches any stale row that does survive, so A5 must land **before** B1.

---

## Chunk B — Clearance identity and coverage

### Task B1: Canonical checksum parity for migrated bindings — **P5-5**

**Files:** `project_migrations/20260801000015_add_p5_pipeline_predicates.sql` · `pipeline_bindings.go` ·
`policy_compile.go` · `pipeline_bindings_test.go` · `policy_compile_test.go`

Per D3: **no backfill migration.** Correct the writer and add a runtime guard; existing rows die with
the database.

- [ ] Failing test: a binding row whose stored checksum is not the canonical
      `semrules.Canonicalize` value must be detected at load — a clearance approved through the
      compiler path must resolve at runtime for the same binding.
- [ ] Stop migration `…000015:176` writing `md5(lr.predicate::text)`. The canonical checksum is
      SHA-256 over Go-produced canonical JSON and cannot be reproduced in SQL, so the migration must
      not fabricate one. Decide at task time between: (a) writing a clearly-marked
      `pending-canonicalization` sentinel that the loader repairs on first read, or (b) deferring
      conditional-binding materialisation to the compiler so no SQL-authored checksum exists at all.
      **(b) is preferred** — it removes the dual-writer problem rather than papering over it.
      Editing migration `…000015` in place is acceptable under D3 (databases are rebuilt).
- [ ] Add a runtime guard in `PipelineBindingSQLStore.ListPipelineBindings`: recompute the canonical
      checksum on load and fail loudly on mismatch rather than silently carrying a stale value.
- [ ] Add a compiler test asserting stored-vs-canonical divergence is a compile error, not a silent
      in-memory overwrite (today `policy_compile.go:308-316` overwrites).

### Task B2: Clearance coverage keyed on governed document kind — **P5-6**

**Files:** `processor_plan.go` · `control.go` · `applicability_facts.go` ·
`routing_enforcement_test.go` · `control_test.go`

- [ ] Failing tests: (a) when `document.doc_kind` is unknown, `RoutingEnforcementRequest.DocumentKind`
      is empty and every suppressive decision stays shadow-only with no clearance lookup attempted;
      (b) when `document.doc_kind` is known, it — never `input_doc_type` — is the coverage key.
- [ ] Add `DocKind` to `ProductionRoutingFacets`, sourced from reduced facet observations
      (`kb.doc_facet_values`, path `document.doc_kind`) and left empty when absent.
- [ ] Change `control.go:1920` to `DocumentKind: facts.RoutingFacets.DocKind`.
- [ ] Assert the spec §9 sentence directly: *"If a record's document kind is missing … that subject
      remains shadow-only even when global plan-only mode is off."*

---

## Chunk C — Enforcement and policy lifecycle

### Task C1: Policy load failure must fail loudly — **P5-11**

**Files:** `control.go` · `runtime.go` · `routing_alarm.go` · `control_test.go` · `runtime_test.go`

- [ ] Failing tests: a `GetActivePolicy` error must not be silently discarded; a binding/gate load
      failure at startup must not leave the process running as though no policy existed.
- [ ] `control.go:1540` — propagate/raise a `policy_integrity_failure` alarm and block in block mode;
      distinguish *no active policy* (legal, legacy path) from *load failure* (error).
- [ ] `runtime.go:131-139` — a binding/gate load failure returns an error from runtime construction
      rather than `logger.Warn`. Registry-load failure keeps its documented legacy fallback.

### Task C2: In-process reload on activation — **P5-12**

**Files:** `kbhandler/pipeline_policies_handler.go` · `doc-processing/pipeline_bindings.go` ·
`pipeline_gates.go` · handler tests

- [ ] Failing test: after a successful `Activate`, the in-process binding/gate set reflects the newly
      activated policy without a restart.
- [ ] Reload bindings and gates after the activation transaction commits; a reload failure raises a
      `policy_integrity_failure` alarm and is surfaced in the response (activation itself already
      committed and is not rolled back).
- [ ] Document the single-process assumption; multi-process reload is out of scope and recorded as a
      carry-forward.

### Task C3: Gate coverage across baseline fallback — **P5-13**

**Files:** `processor_plan.go` · `routing_enforcement.go` · `routing_enforcement_test.go`

- [ ] Failing test: an uncleared suppressive binding falls back to the baseline pipeline; a processor
      re-admitted by the baseline but absent from the selected pipeline must still be gate-evaluated,
      not run ungated.
- [ ] Build the gate shadow over the **union** of the selected and baseline post-allowlist sets so a
      decision exists for every processor `FinalizeRoutingPlan` can encounter.
- [ ] Alternatively (decide in review): make `gateDecisionFor`'s miss path fail closed. The union
      approach is preferred — it keeps the shadow plan a complete explanation.

### Task C4: Store-default fallback respects the knowledge store — **P5-18**

**Files:** `pipeline_bindings.go` · `pipeline_bindings_test.go`

- [ ] Failing test: two `store_default` bindings for different `ks_store_id`s; a record in store B
      must not receive store A's pipeline.
- [ ] Filter `storeDefaults` by `KnowledgeStoreID`, falling back to a system-scoped row only when no
      store-scoped row matches.

### Task C5: Conflict mode and run overrides — **P5-19, P5-20**

**Files:** `pipeline_selection.go` · `processor_plan.go` · `event.go` · tests

- [ ] Failing tests: `DOC_PIPELINE_ON_CONFLICT=block|fallback` changes binding **and** gate conflict
      behaviour; a run-scoped processor override parsed from the event outranks policy gates while
      retaining its audit annotation (plan C1's third bullet, never delivered).
- [ ] Read `DOC_PIPELINE_ON_CONFLICT` once and thread it to both resolvers, replacing the two
      hardcoded constants.
- [ ] Parse run-scoped gate overrides in the event decoder and populate
      `ProductionPlanFacts.ProcessorGateOverrides`.

---

## Chunk D — Deterministic review selection

### Task D1: Per-target frozen facts — **P5-8**

**Files:** `profiles/review_service.go` · `review_service_test.go`

- [ ] Failing test: a scope with two target objects on one document, whose `object.class` facts differ,
      must gate each pinned rule against **its own** target's facts.
- [ ] Match `frozenSubjectFacts` on `(DocumentID, TargetObjectID)`; thread the target through
      `EvaluatePinnedScope`. A scope with no target ids keeps today's document-only behaviour.

### Task D2: Pin indeterminate-only profiles — **P5-9**

**Files:** `profiles/select.go` · `select_test.go`

- [ ] Failing test: a profile whose every subject evaluates `indeterminate` on a closed dimension
      intersecting the request must still be pinned with `Outcome: indeterminate` and produce an
      explicit indeterminate finding — spec §6, not merely `selection_status=indeterminate`.
- [ ] Record indeterminate subjects in `SelectedProfile` alongside true subjects, marked so the review
      service emits indeterminate applicability rather than silently skipping the profile.

---

## Chunk E — Make Chunk G real — **P5-2**

The largest task. Review `2026080302` §3.1 shows wiring the field is insufficient.

### Task E1: Supply the resolver its predicates

**Files:** `applicability_resolver.go` · `pipeline_bindings.go` · `pipeline_gates.go` ·
`applicability_resolver_test.go`

- [ ] Failing test: `ResolveExtractionFacts` invokes the classifier when an active binding or gate
      predicate references an unresolved, decision-relevant tier-3 path — currently impossible because
      `Predicates` is always empty.
- [ ] Collect the active policy's binding and gate predicate documents and pass them as
      `ResolverRequest.Predicates`.
- [ ] Assert a predicate referencing only tier-1/2 paths triggers **no** classifier call.

### Task E2: Real invocation identity and document sample

**Files:** `control.go` · `applicability_resolver.go` · tests

- [ ] Failing tests: distinct runs of the same record produce distinct `decision_attempt_id` /
      `invocation_id`; a retry within one run reuses them (stable retry); the classifier receives a
      non-empty bounded sample.
- [ ] Resolve the ordering problem that forces `runID=0` at `control.go:665` — either move the
      resolver call after run-row creation or mint a decision-attempt id independent of `run_id`.
      **Prefer the latter**: routing must be decided *before* dispatch.
- [ ] Source a bounded document sample from the existing parsed-text/line-file path; never read the
      raw upload.
- [ ] Resolve `VocabularyReleaseID` from the active `document-authority` module release instead of
      hardcoded `0`.

### Task E3: Production construction, behind a flag

**Files:** `runtime.go` · `classify-document.go` · `runtime_test.go`

- [ ] Failing test: with `CLASSIFY_DOCUMENT_ENABLED=true` the production `ControlService` carries a
      non-nil `Resolver` with a non-nil `Classifier`; with the flag off (default) it stays nil and
      behaviour is byte-identical to today.
- [ ] Construct `NewDocumentClassifier` (LLM extractor, `FacetObservationSQLStore`,
      `policyaudit.SQLStore`, governed vocabulary) and `ApplicabilityResolver` in `runtime.go:140`.
- [ ] Fix `truncateSample` to cut on a rune boundary (**P5-25**) — the pilot corpus is Chinese.
- [ ] Distinguish "LLM failed" from "LLM legitimately returned no classification"; today both surface
      as empty observations.

### Task E4: Review-side classification

**Files:** `profiles/select.go` · `kbhandler/ontology_review_document_facts.go` · tests

- [ ] Failing tests: at most one classifier invocation per record/review-selection-attempt; a
      review-time call writes **only** facet observations and never triggers extraction or Phase D;
      multi-document review; concurrent observations reduce deterministically.
- [ ] Wire the resolver into the deterministic selection path (plan G2's unbuilt half).

---

## Chunk F — Repair proposals and promotion

### Task F1: Canonical proposal checksums — **P5-3**

**Files:** `modules/applicability_proposals.go` · `applicability_proposals_test.go`

Per D3: **no backfill.** Existing proposal rows are disposable.

- [ ] Failing test: a proposal's stored checksum equals `semrules.Canonicalize`'s output, so
      `policy_compile.go:177-179` accepts a promoted binding. This currently fails **for every input**
      (prefixed hash of raw bytes vs bare canonical hex).
- [ ] Replace `predicateChecksum` with `semrules.Canonicalize`; store the canonical predicate bytes
      alongside, so promotion materialises canonical JSON.
- [ ] End-to-end test: create → approve → promote → **compile** the draft policy successfully. This
      path is closed today for any input and is the single best proof that Chunk F works.

### Task F2: Transactional, correct promotion — **P5-4, P5-10**

**Files:** `policy_promotion.go` · `modules/releases_store.go` · `cmd/ontology-compiler/main.go` ·
`policy_promotion_test.go` · new `modules/releases_store_test.go`

- [ ] Failing tests (plan H2's, never written): release creation **and** activation call
      `EnsureDraftFromModuleRelease` inside their transactions; exact release provenance;
      same-release idempotency across draft **and** activated states; a new draft for a distinct
      release; rollback on promotion failure; active routing policy unchanged.
- [ ] Change `DraftPolicyPromoter` to accept a `*sql.Tx` so it can genuinely join the release
      transaction — the current `*sql.DB` signature makes its own doc comment false.
- [ ] Move promotion into `ReleaseStore.CreateRelease`/`Activate`; remove the post-hoc CLI call and
      its `log.Printf` warning. Resolve which release id proposals target (see F3).
- [ ] Fix `MAX(version)+1` (handle the scan error; add a unique constraint on
      `kb.pipeline_policies(version)`), the `status='draft'` idempotency key, and the nil-lister panic.

### Task F3: Proposal lifecycle integrity — **P5-17**

**Files:** `modules/applicability_proposals.go` · `kbhandler/ontology_applicability_proposals_handler.go` · tests

- [ ] Failing tests: a concurrent double transition cannot both succeed; `included_in_release` cannot
      name a release that does not contain the proposal.
- [ ] Add `WHERE id = $1 AND status = $expected` to `TransitionProposal` and treat zero rows affected
      as a conflict.
- [ ] Make `included_in_release` a consequence of the release transaction (F2) rather than a manual
      HTTP transition with a caller-supplied release id, matching plan H1's "include only approved
      proposals in the immutable module snapshot."

---

## Chunk G — Tests and exit criteria

### Task G1: Correct the criterion mappings — **P5-21**

**Files:** `doc-processing/p5_exit_test.go` · `profiles/p5_exit_test.go` · `doc-benchmark/report_test.go`

- [ ] Criterion 13 → point at the real tests
      (`kbhandler: TestActivatePipelinePolicyCompilerFailureLeavesPriorActiveUntouched`,
      `kbhandler: TestActivatePipelinePolicyTransactionFailureRollsBackArchive`). Rename the two
      misnamed `policy_promotion_test.go` tests to describe what they actually assert.
- [ ] Criterion 15 → replace the serialization round-trips with a test that runs the analyzer over a
      routing-off and routing-on fixture pair and asserts recorded cost, yield, recall/precision and
      **explainable skips** differ as expected.
- [ ] Criterion 9 → rebuild the cross-consumer fixture against `BuildPipelineBindingFactSet` (the real
      extraction builder) versus `BuildReviewContextFacts`, not two review-side builders.

### Task G2: Close the parser-check loophole — **P5-22**

**Files:** both `p5_exit_test.go`

- [ ] Failing test: a deliberately phantom `semrules:`-prefixed name must fail the coverage test.
- [ ] Resolve cross-package pointers by parsing the sibling package directories rather than skipping
      any name containing `:`. Keep `I2:` live-proof pointers exempt and assert that exemption is
      explicit rather than incidental.

### Task G3: Missing test files — **P5-23**

**Files:** new `kbhandler/ontology_applicability_proposals_handler_test.go`

- [ ] Plan H1's named coverage: unauthenticated `401`, authenticated-but-unauthorized `403`,
      owner/admin/`k_engineer` success, actor derived from `UserName` and never from the body,
      predicate/checksum validation, source-release pinning, invalid transitions.
- [ ] (`modules/releases_store_test.go` is delivered by F2.)

---

## Chunk H — Hygiene and documentation correction

### Task H1: Code hygiene — **P5-26, P5-28, P5-29**

- [ ] `gofmt -w server/api/doc-processing/routing_alarm.go`; add `gofmt -l` over P5 packages to the
      verification step so it cannot regress.
- [ ] Normalise `json.Number` in `normalizeObservationValue` so a JSONB-decoded `2.0` and a Go `2` do
      not conflict.
- [ ] Derive `restoreMandatoryProcessors` from `isMandatoryProcessor` instead of a hardcoded pair, so
      the two definitions cannot diverge again.

### Task H2: Correct the overstated records

- [ ] ADR `2026072901` — replace the 2026-08-03 entry's "implemented and wired" claim with an accurate
      status and a pointer to review `2026080302`; add the completion entry only after Chunk I passes.
- [ ] Handoff `2026073002` — retract "All code-level P5 work (G, H, I1, I3) is complete."
- [ ] Impl log `2026080107` — correct the commit list, the "gofmt clean" claim, and extend "Known
      limitations" with the defect register, or supersede it with a fresh log for this remediation.
- [ ] `Capsules/coding-capsules/doc-processor/+CAPSULE.md` — add the P5 section plan I3 required.
- [ ] Bug `2026080301` — mark resolved-by/superseded-by `2026080302`; update `bugs/OPEN.md`.
      (Note: that file and `bugs/OPEN.md` are currently **uncommitted** in the KnowledgeStore working
      copy and must be committed as part of this work.)

---

## Chunk I — I2 live proof — **P5-30**

Unchanged from plan `2026080103` I2, executed **after** A–H.

- [ ] Rebuild `chenweb_test` from scratch (D3: existing data is disposable) and apply migrations
      `20260801000015`–`20260801000022` plus any structural migration added by Chunks A–H, through the
      normal datasource path; record schema/version evidence.
- [ ] Prove against live PostgreSQL: legacy parity; override precedence; invalid activation rollback;
      block/fallback alarm dedupe **through the real partial unique indexes**; shadow / partial /
      cleared enforcement; clearance replacement, revocation, and corrupt-multiple fail-closed;
      extraction and review snapshot reload after activation changes; review rule applicability;
      classifier retries and concurrency; module promotion without activation.
- [ ] Run routing off/on against the synthetic corpus; record exact cost / yield / recall / precision
      per document kind; leave insufficient slices shadow-only.
- [ ] Clean disposable rows through governed lifecycle methods; record what remains.
- [ ] Write the completion log and only then annotate the ADR §8.3.8 exit.

---

## 2. Verification (after every chunk, and as the final gate)

```bash
go build ./...
go vet ./server/api/ontology/... ./server/api/doc-processing/... \
       ./server/api/doc-benchmark/... ./server/api/kbhandler/...
gofmt -l server/api/ontology server/api/doc-processing server/api/doc-benchmark
go test ./server/api/ontology/... ./server/api/doc-processing/... \
        ./server/api/doc-benchmark/... ./server/api/kbhandler/... -count=1
```

**Baseline contract:** the pre-existing failure set is exactly 15 in `doc-processing` and 14 in
`kbhandler` (review `2026080302` §2.2). Any change to that set is a regression introduced by this
work and must be fixed, not renegotiated. `gofmt -l` must be empty **for P5-owned files**; unrelated
pre-existing offenders are out of scope per the ChenWeb surgical-changes rule.

---

## 3. Definition of done

P5 may be declared complete only when **all** hold:

1. Every defect P5-1 … P5-29 is closed or explicitly re-classified as a documented carry-forward with
   the user's agreement.
2. All 16 spec §12 acceptance criteria map to tests that **exercise the production path**, verified by
   the repaired coverage check.
3. Chunk I's live proof passes and records per-document-kind invocation reduction with no measured
   review-recall loss (ADR §8.3.8).
4. ADR, handoff, capsules, plan checkboxes, and implementation log agree with the tree.
5. Both repositories are committed via `jj`, `jj log` is linear, and `origin/main` is pushed.

The authority-confirmed ventilator conclusion remains blocked on the P4 data fixture and is **not**
implied by generic-runtime completion.

---

## 4. Knowledge and documentation impact

**What knowledge changed?** The remediation path for P5 is now enumerated against a verified defect
register rather than the earlier partial fix plan.

**Which docs/specs/ADRs/tests are affected?** ADR `2026072901` (P5 status), handoff `2026073002`,
impl log `2026080107`, plan `2026080103` checkboxes, both capsules, both `p5_exit_test.go` files,
bug `2026080301`, fix plan `2026080201`.

**Which docs were updated?** This plan and review `2026080302`.

**Which docs are now stale?** Fix plan `2026080201` (superseded); the ADR/handoff/impl-log claims,
until Chunk H lands.

**What was intentionally left undocumented?** Authority-owned pilot values and standard editions
(spec non-goal). Multi-process binding reload (C2 carry-forward).
