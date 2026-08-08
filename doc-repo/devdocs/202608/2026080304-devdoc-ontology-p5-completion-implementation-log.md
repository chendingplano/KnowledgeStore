# SemOS P5 Completion Implementation Log

**Date:** 2026-08-03
**Status:** Chunks A–H of the completion plan executed and merged to `main`; I2 (live proof) pending
**Plan:** `2026080303-plan-ontology-p5-completion.md`
**Review basis:** `2026080302-devdoc-ontology-p5-implementation-review.md` (defects P5-1…P5-30)
**Supersedes for status:** `2026080107-devdoc-ontology-p5-implementation-log.md` (retracted by its own
supersession notice)

## Why this log exists

The prior impl log `2026080107` claimed "all code-level P5 work (G, H, I1, I3) is complete." An
independent audit (bug `2026080301`, consolidated in review `2026080302`) showed that was wrong:
the resolver was inert by construction and unwired, promotion was non-operational, promoted
bindings failed compilation, clearance coverage was keyed on the wrong dimension, and the exit
tests did not test what they claimed to. This log records the remediation that actually closed
those defects.

## Chunk 0 — Baseline

- Advanced the `main` bookmark to the P5 tip and pushed (`jj bookmark set main` + `jj git push
  --bookmark main`); the earlier "P5 changes not on main" confusion was a jj bookmark that did not
  auto-advance plus a detached-HEAD `git commit`, not missing work.
- Captured the regression baseline: exactly 15 pre-existing `doc-processing` + 14 `kbhandler`
  failures (summaries / topics / metrics / products / graphs / connections / search-registry),
  confirmed structurally unrelated to P5. **This set stayed byte-identical after every change in
  this remediation.**
- Task 0.2 (reconcile the plan `2026080103` checkboxes) is recorded in this remediation's own plan
  status update.

## Chunk A — `semrules` correctness

- **A1 (P5-7)** — decision-relevance masking was order-dependent: whether a later sibling masked a
  missing child depended on iteration order. `evaluateAllOrAny` now computes the deciding child
  from the full truth table first, then masks only non-deciding siblings
  (`childDecisionRelevant := decisionRelevant && (truths[i] == deciding || !hasDeciding)`).
- **A2 (P5-14)** — an invalid typed operand (e.g. `eq` between incompatible types) surfaced as
  `operator_error` instead of the distinct `invalid_fact` reason; the observed-value error sites
  now wrap `ErrInvalidFactValue` and the operator-error branch maps it to `ReasonInvalidFact`.
- **A3 (P5-15)** — `EvaluateDocument` silently degraded malformed predicates instead of failing;
  added the validating entry point `EvaluateDocumentValidated` and migrated the five consumers
  (extraction routing, review selector, applicability resolver).
- **A4 (P5-16)** — `min_confidence` was bypassed by a nil `Confidence` (nil was treated as "passes
  any bar"); `belowConfidenceThreshold` now treats nil confidence as failing a declared bar, and
  deterministic metadata facts set an explicit 1.0 confidence.
- **A5 (P5-24, P5-27)** — `in`/`not_in` canonical checksums were order-sensitive (different
  key order → different checksum → spurious policy change on every reload); values are now sorted
  and deduplicated before hashing. `overlap.go` unreachable-return/dead-branch cleanup.

## Chunk B — Clearance and binding identity

- **B1 (P5-5)** — `ListPipelineBindings` recomputes each binding's checksum via
  `semrules.Canonicalize` immediately after unmarshal, discarding the stored checksum, so migrated
  rows (authored under the old prefixed scheme) compile cleanly. No backfill (D3).
- **B2 (P5-6)** — clearance coverage was keyed on `document.input_doc_type` (the *file format*,
  `pdf`/`docx`); it is now keyed on the governed `document.doc_kind` tier-3 facet, fail-closed
  (empty `DocumentKind` when missing) so a clearance can never authorise suppression across every
  PDF regardless of its actual kind.

## Chunk C — Enforcement and policy integrity

- **C1 (P5-11)** — binding/gate load failures at runtime construction were downgraded to warnings,
  leaving the process running as though no policy existed; they now fail loudly
  (`PolicyLoadError`), while a registry-load failure keeps its legacy fallback.
- **C2 (P5-12)** — activation did not touch the running process; it now reloads the in-process
  binding/gate set immediately after commit, raising a policy-integrity alarm on failure.
- **C3 (P5-13)** — the gate-shadow plan did not cover a processor suppressed by the baseline
  fallback itself; the shadow build now unions the selected pipeline's specs with the baseline's
  own effective set.
- **C4 (P5-18)** — store-default fallback ignored which knowledge store a record belonged to; the
  default loop now prefers a store-scoped default before the system-scoped fallback
  (`binding.KnowledgeStoreID == recordStoreID`, then `== 0`).
- **C5 (P5-19, P5-20)** — `DOC_PIPELINE_ON_CONFLICT` was never read (gate block mode unreachable);
  it now drives both binding resolution and gate-shadow conflict handling, and run-scoped
  `ProcessorGateOverrides` from the event are threaded into the routing facts.

## Chunk D — Deterministic review selection

- **D1 (P5-8)** — rule applicability was evaluated against a single frozen fact set per scope; it
  is now evaluated against every pinned target's frozen facts, OR-combined at the applicability
  gate (any True wins; else Indeterminate if any target Indeterminate; else Inapplicable).
- **D2 (P5-9)** — a profile indeterminate on a requested closed dimension was silently dropped from
  `SelectedProfiles`; it is now pinned with `Outcome=indeterminate` and its rules route to explicit
  indeterminate findings instead of normal evaluation.

## Chunk E — Make the classifier/resolver real

- **E1 (P5-2 part 1)** — `ResolveExtractionFacts` never populated `Predicates`, so pass 1 always
  evaluated zero predicates and the classifier could never be reached; it now collects the active
  policy's conditional-binding and gate predicate documents.
- **E2 (P5-2 part 2)** — invocation identity was `runID=0` (every invocation for a record
  collapsed to the same id); it is now attempt-unique (`extract-<attemptKey>`) via the just-generated
  line file name, stable across redelivery so the classifier's stable-retry dedupes. The bounded
  document sample comes from the already-parsed line file (never the raw upload), and
  `VocabularyReleaseID` resolves from the active `document-authority` module release
  (`VocabularyReleaseSQLStore`).
- **E3 (P5-2 part 3, P5-25)** — production construction was absent; the resolver is now built in
  `runtime.go` behind `CLASSIFY_DOCUMENT_ENABLED` (default off — D4), degrading to nil with a
  warning on config failure. `truncateSample` now cuts on a UTF-8 rune boundary (the pilot corpus
  is predominantly Chinese), and `ClassifyResult.Failed` distinguishes a genuine LLM failure from a
  well-formed response that validated zero classifications — `ApplicabilityResolver.Resolve`
  branches on it instead of the empty-observations heuristic.
- **E4** — review-time classification was absent entirely; `profiles.Selector` gained an optional
  `ReviewFactEnricher`, wired via `ApplicabilityResolver.ResolveReviewFacts` with the stable
  review-scope id as the attempt key, once per (record, scope-selection-attempt), writing only
  facet observations.

## Chunk F — Proposals and promotion

- **F1 (P5-3)** — proposal checksums were a prefixed hash of raw client bytes, so every promoted
  binding failed the compiler's canonical-checksum check (promotion was a silent no-op); proposals
  now store `semrules.Canonicalize` output — canonical predicate bytes and the bare canonical
  checksum — so create → approve → promote → compile works for any input.
- **F2 (P5-4, P5-10)** — promotion ran as a post-hoc CLI call after the release committed, degraded
  failures to a warning, listed by a fresh release id nothing referenced, and skipped `runActivate`.
  It now joins the release transaction via a `ReleaseStore.Promote` hook
  (`DraftPolicyPromoter` takes `*sql.Tx`); `runActivate` wires the same hook. The
  `MAX(version)+1` scan error is surfaced, idempotency keys on `source_ref` across all statuses,
  the nil-lister panic is guarded, and a unique index on `kb.pipeline_policies(version)`
  (migration `20260801000023`) closes the version race.
- **F3 (P5-17)** — `TransitionProposal` read-then-updated blindly, so a concurrent double
  transition could both succeed, and `approved → included_in_release` was a manual HTTP transition
  naming any release id. The update is now guarded by `status = $expected` (zero rows → conflict),
  and inclusion is a consequence of the release transaction
  (`markApprovedProposalsIncluded`), with the manual transition removed.

## Chunk G — Tests and exit criteria

- **G1 (P5-21)** — criteria 9/13/15 pointed at tests that did not test them. Criterion 9's
  cross-consumer fixture now uses the real extraction builder `BuildPipelineBindingFactSet` (it
  compared two review-side builders); criterion 13 points at the real kbhandler activation tests
  and the two misnamed promotion tests were renamed; criterion 15's proof is a new analyzer test
  (`TestBenchmarkReportRoutingOffVsOnDiffers`) that runs the analyzer over a routing-off/on pair
  and asserts cost/yield/recall/precision and the explainable-skip attribution differ as expected.
- **G2 (P5-22)** — the coverage test skipped every name containing `:`; cross-package pointers
  (`semrules:`/`profiles:`/`doc-benchmark:`/`kbhandler:`) now resolve against the target package's
  own `_test.go` files, and `I2:` pointers must be explicit live-proof pointers. A deliberately
  phantom `semrules:` name now fails.
- **G3 (P5-23)** — the proposals handler had zero tests; the new
  `ontology_applicability_proposals_handler_test.go` covers plan H1's named cases (401/403,
  owner/admin/k_engineer success, actor derivation from `UserName`, canonical predicate/checksum
  storage with source-release pinning, invalid predicate/transition, 404). (`modules/releases_store_test.go`
  was delivered by F2.)

## Chunk H — Hygiene

- **H1 (P5-26, P5-28, P5-29)** — `routing_alarm.go` gofmt'd (the "gofmt clean" claim was false for
  it); `normalizeObservationValue` canonicalises `json.Number` so a JSONB `2.0` and a Go `2` share a
  fact-value key instead of conflicting; `restoreMandatoryProcessors` derives the mandatory set
  from `isMandatoryProcessor` over the registry instead of a hardcoded pair.
- **H2 (documentation)** — recorded here. The handoff `2026073002`, this ADR
  `2026072901`, the retracted impl log `2026080107`, bug `2026080301`, `bugs/OPEN.md`, and the
  doc-processor capsule are corrected in the same pass.

## Verification

- `go build ./...` and `go vet` clean across every touched package.
- `gofmt -l` clean on every file this remediation touched.
- Full suite matches the pre-existing baseline exactly: 15 `doc-processing` + 14 `kbhandler`
  legacy failures, all unrelated to P5; every `ontology/...` subpackage and `doc-benchmark` green;
  all P5-focused tests (semrules, resolver, classifier, promotion, proposals, exit criteria,
  migration contracts) pass.
- ChenWeb `main` fast-forwarded to the remediation tip and pushed to `origin/main` (14 commits).

## Remaining P5 boundary

1. **I2** — live PostgreSQL + synthetic-corpus proof (unchanged; requires a live database).
2. **H2 follow-ups beyond this log** — none; this log set is the H2 closeout.
3. Nothing else: the resolver, classifier, promotion, clearance, review selection, and exit
   criteria are all real and wired.
