# SemOS P5 Implementation Review — Consolidated

**Document ID:** `2026080302`
**Date:** 2026-08-03
**Status:** Final (consolidated from two independent reviews)
**Verdict:** P5 is **not** complete. I2 is not the only remaining item.

**Supersedes as the authoritative P5 review record:**
- Bug report `2026080301-bug-semos-p5-rule-driven-routing-not-finished.md` (review A)
- Fix plan `2026080201-plan-semos-p5-fix-dead-code-exit-test-documentation.md` §1 findings (partially executed; see §6)

**Baseline:** ADR `2026072901` (§8.3.8, changelog 2026-08-03) · Spec `2026080102` (§12, 16 acceptance
criteria) · Plan `2026080103` (A1–I3) · Impl log `2026080107` · Handoff `2026073002`

**Tree reviewed:** ChenWeb working copy `pmtv 4b1c` (clean), parent `kksq aa15 "fixing P5
implementation bugs"`; `main` at `otpr 41a5`.

---

## 1. How this consolidation was produced

Two independent reviews were run against the same tree:

- **Review A** — bug report `2026080301`. Reviewer-verified items marked ✓; the remainder attributed
  to five parallel deep-review agents at file:line.
- **Review B** — an independent second pass that did not consult review A until after reaching its
  own conclusions.

Both reached the same top-line verdict and the same three structural facts (unmerged work, Chunk G
dead, Chunk H non-operational). This document merges them and, critically, **adjudicates every item
review A attributed to agents but did not itself verify**. Each finding below carries a verification
mark:

| Mark | Meaning |
|---|---|
| **[V]** | Verified in this consolidation by direct code reading and/or an executed probe |
| **[V-probe]** | Verified by an executed throwaway Go test whose output is quoted (probe removed afterwards) |
| **[U]** | Reported but **not** verifiable without live PostgreSQL — deferred to I2 |
| **[R]** | Reported by review A, **revised or downgraded** here after adjudication |

Everything previously unverified in review A is now marked. No finding below rests solely on an
unreviewed agent report.

---

## 2. Where the two reviews agreed

All of the following were independently reached by both reviews and are re-verified here.

### 2.1 Completion status

**[V] P5 is not on `main`.** `main` = `otpr 41a5` (the E3–F2 merge). G1, G2, H1, H2, I1 and the
`kksq aa15 "fixing P5 implementation bugs"` commit are floating above it.
`jj diff --from main --to @` = **27 files, +3434 / −14**. A build from `main` contains no classifier,
resolver, proposal store, promotion, proposals handler, or exit tests. Plan I3's commit checkbox is
correctly unchecked.

**[V] The fix commit proves the implementation log was premature.** Impl log `2026080107` (dated
08-02) declares G/H/I complete. The later `aa15` commit (20 files, +1122) then supplies the H1 HTTP
handler and its routes, the promotion type-adapter rework, the `control.go` resolver call site, the
`pipeline_bindings.go` enriched-facts overlay, and proposal audit-event kinds — all things the log
implied already existed.

**[V] Chunk G is dead code in production.** `ControlService.Resolver` has **zero assignments anywhere
in the tree**; `runtime.go:140` constructs `ControlService` without it, so the sole call site
`control.go:665` is permanently guarded off. `NewDocumentClassifier` has no non-test caller.
`profiles/select.go` never references the resolver, so review-time classification is absent entirely.
Acceptance criterion 11 is wholly about this mechanism.

**[V] Chunk H promotion is non-operational.** Promotion exists only in `ontology-compiler`'s
`runRelease`, *after* `CreateRelease` commits, with failure downgraded to `log.Printf("warning: …")`.
`runActivate` never promotes. `modules/releases_store.go` has no promoter call in either path. The
release id passed to `ListApprovedProposals` is a *freshly minted* id that no proposal can yet
reference (proposals are authored via HTTP against an existing release id), so in practice the call
returns zero proposals and promotion is always a no-op.

**[V] I2 is genuinely deferred, and correctly so** — it maps to ADR §8.3.8's exit criterion. But it
is not merely "run the proof"; several defects below would surface there first.

### 2.2 Test posture

**[V] P5-specific suites pass.** `semrules`, `profiles`, `modules`, `policyaudit`, `assertions`,
`candidates`, `comparison`, `semid`, `terms`, `doc-benchmark` — all green (`-count=1`). `go vet`
clean; `go build ./...` succeeds.

**[V] The 29 other failures are genuinely pre-existing and unrelated.** `doc-processing` 15,
`kbhandler` 14 — all legacy (summaries / topics / metrics / products / graphs / connections /
search-registry). Verified structurally: **no P5 commit touched any file containing them** (checked
across all twelve P5 commits). The impl log's claim on this point holds.

**[V] Exit tests prove name resolution, not reachability.** Criterion 11's classifier tests pass
green while the classifier is unreachable from production.

---

## 3. Findings review B adds

These are not in review A.

### 3.1 [V] The resolver is inert by construction, not merely unwired — **Critical**

Review A correctly notes `runID=0` and an empty document sample. The deeper defect:
`ResolveExtractionFacts` (`applicability_resolver.go:180-187`) **never populates `req.Predicates`**.

Consequently `Resolve` runs `evaluateAll(nil, baseFacts)` → empty results → `decisionRelevantTier3Paths`
returns empty → the function returns at line 65-70 before ever reaching the classifier.

**Setting `ControlService.Resolver` alone changes nothing.** The remediation is larger than review A's
step 2 implies: the resolver must be handed the active policy's binding and gate predicate documents,
which nothing currently assembles for it. This materially changes the effort estimate for Chunk G.

### 3.2 [V] Clearance coverage is keyed on the wrong dimension — **Critical**

`control.go:1920` sets `DocumentKind: facts.RoutingFacets.InputDocType` — the *file format*
(`pdf`/`docx`).

Spec §9 keys clearance coverage on **document kind**, the governed tier-3 facet
`document.doc_kind` (`semrules/facts.go:201`, `Tier3Producible: true`, values such as
`narrative-research` / `product-specification` / `regulated-reference` per the P0 benchmark evidence).
No `DocKind` field exists anywhere in `ProductionPlanFacts` or `ProductionRoutingFacets`; the only
producer is the dead classifier.

Spec §9 is explicit: *"If a record's document kind is missing … that subject remains shadow-only."*
The correct fail-closed behaviour is an empty `DocumentKind`. As written, a clearance approved for
`document_kind="pdf"` would authorise suppression across **every PDF regardless of its actual
document kind** — precisely the over-broad enforcement the exact-coverage rule (§9: *"P5 v1 requires
exact document-kind coverage—no wildcard or overlapping range"*) exists to prevent.

This defect is currently masked by §3.3's checksum break and by the clearance tables being empty, but
it is the more dangerous of the two: it fails *open* in the direction of over-enforcement once
clearances exist.

### 3.3 [V] Policy activation has no runtime effect until process restart — **Important**

`runtime.go:131-139` loads the pipeline registry, bindings, and gates **once at startup**. No handler
reloads them: `grep` for `LoadProduction*` / `SetProductionPipeline*` across
`pipeline_policies_handler.go`, `pipeline_bindings_handler.go`, `pipeline_rules_handler.go` returns
nothing.

E2's carefully compiled, locked, atomic activation endpoint is therefore **inert against a running
process**. This is also a regression relative to P1, whose implementation log records store→pipeline
bindings resolving *live* via SQL JOIN "so store-pipeline binding changes take effect immediately
without restart." P5 moved conditional bindings — which now *outrank* store defaults — into a
startup-only in-memory cache.

### 3.4 [V] Three acceptance criteria are mapped to tests that do not test them — **Important**

The I1 registry satisfies its own name-resolution check while pointing at the wrong tests.

**Criterion 13** ("a failed policy compilation or activation leaves the previous active version
effective") → `TestPolicyCompileFailureLeavesActiveUntouched` and `TestPolicyActivationFailureRollback`
(`policy_promotion_test.go:71,107`). Both exercise `EnsureDraftFromModuleRelease` — *draft creation*.
The first asserts a failed `INSERT` returns an error; the second is a **successful happy path** that
merely asserts no activation query was issued. Neither touches compilation or activation, nor asserts
anything about the active version. Genuine coverage **does** exist —
`TestActivatePipelinePolicyCompilerFailureLeavesPriorActiveUntouched` and
`TestActivatePipelinePolicyTransactionFailureRollsBackArchive` in `kbhandler` — but the registry does
not reference them. The names appear chosen to satisfy the parser check.

**Criterion 15** ("the benchmark report records cost, yield, recall/precision, and explainable skips
**for routing on versus off**") → two tests in `doc-benchmark/report_test.go` that hand-build a
`BenchmarkReport`, marshal it, unmarshal it, and assert the fields survive. No routing on/off
comparison; no explainable skips. They are struct-serialization tests wearing criterion names.

**Criterion 9** ("review-profile selection and extraction routing evaluate identical predicates") →
`TestB3CrossConsumerPredicateFixture…`, which uses `docprocessing.BuildApplicabilityFactSet` as "the
extraction fact builder". Production extraction routing uses `BuildPipelineBindingFactSet`;
`BuildApplicabilityFactSet` is called only from `kbhandler/ontology_review_document_facts.go` — the
*review* path. **The cross-consumer fixture compares two review-side builders.** (The fixture is
otherwise honest and self-documents its own B3 origin.)

### 3.5 [V] The exit-test parser check skips every cross-package pointer — **Important**

`p5_exit_test.go:127` does `if strings.Contains(name, ":") { continue }`. Every pointer prefixed
`semrules:`, `profiles:`, `doc-benchmark:` or `I2:` bypasses verification — criteria 1–4, 9, 10, 14,
15, 16.

All 15 such names **do** resolve today (verified by grep). But the mechanism review A praised as
"genuinely good" only guards same-package names; the cross-package half is unguarded and will silently
rot. This is a partial revision of review A's §C assessment.

### 3.6 [V] Plan-mandated test files were never created — **Important**

- `kbhandler/ontology_applicability_proposals_handler_test.go` — required by plan H1 with named
  coverage for "unauthenticated/unauthorized rejection, owner/admin/`k_engineer` curator
  authorization through D2's helper, actor derivation, predicate/checksum validation, source release
  pinning, and failed release preserving activation." The handler exists (149 lines, 4 endpoints, 4
  registered routes) with **zero test coverage**.
- `ontology/modules/releases_store_test.go` — required by plan H2. Never created, which is why H2's
  stated tests ("both release creation and later activation call `EnsureDraftFromModuleRelease`
  **inside their transactions**", "rollback on promotion failure") do not exist.

### 3.7 [V] Documentation and hygiene

- **`gofmt -l` flags `server/api/doc-processing/routing_alarm.go`** (const-block alignment). I3's
  "gofmt clean" claim is false.
- **`Capsules/coding-capsules/doc-processor/+CAPSULE.md` has zero P5 mentions.** Plan I3 required
  modifying it; only the ontology capsule was updated.
- **`restoreMandatoryProcessors`** (`routing_enforcement.go:269`) hardcodes `static_analyzer` and
  `chunking`, omitting `classify_document` despite its `mandatory_gated` class
  (`processor_plan.go:405`). Currently moot — `classify_document` is excluded from
  `selectableProductionProcessorOrder`, so it never appears in a requested list — but the two
  mandatory-processor definitions have already diverged. **Minor.**

---

## 4. Adjudication of review A's unverified findings

Review A's Critical block was fully reviewer-verified and is confirmed here. This section resolves the
**Important** and **Minor** items review A attributed to agents.

### 4.1 Confirmed

| Finding | Verification |
|---|---|
| **Legacy migrated bindings can never be cleared.** Migration `20260801000015:176` writes `md5(lr.predicate::text)`; `policy_compile.go:308-316` overwrites it in memory with canonical SHA-256; the *runtime* loader `pipeline_bindings.go:100-160` reads the raw md5 into `PredicateChecksum`, which feeds `ConditionalBindingSubjectChecksum`. Compile-time and runtime disagree. Breaks criterion 16 for exactly the migrated P1 class P5 exists to migrate. Fails closed. | **[V]** all three sites read |
| **`semrules` decision-relevance masking is order-dependent.** Forward-only short-circuit, not logical masking. | **[V-probe]** `all[missing,false]` → `paths=[document.doc_kind]`; `all[false,missing]` → `paths=[]`. Same for `any[missing,true]` vs `any[true,missing]`. Compounded by `Canonicalize` deliberately preserving authored child order: logically identical policies get different checksums **and** different classifier-invocation behaviour. Every existing masking test places the deciding child first, so it ships green. |
| **`frozenSubjectFacts` matches by `DocumentID` only.** `review_service.go:291` — `TargetObjectID` ignored; with multiple targets per document every pinned rule gates against the first target's facts. | **[V]** |
| **Indeterminate-only profiles are never pinned.** `select.go:279` appends to `snapshot.Selected` only when `len(subjectsTrue) > 0`, so such a profile produces no findings at all — the operator sees only `selection_status=indeterminate` plus a warning. Contradicts spec §6. | **[V]** |
| **Gate block mode is unreachable.** `DOC_PIPELINE_ON_CONFLICT` appears **only in a comment** (`routing_enforcement.go:199`) and is never read. Bindings hardcode `PipelineBindingOnConflictBlock` (`pipeline_selection.go:118`); gates hardcode `PipelineBindingOnConflictFallback` (`processor_plan.go:232`). | **[V]** |
| **Run-scoped processor-gate overrides are dead code.** `ProcessorGateOverrides` is declared, cloned and read (`processor_plan.go:65,215,231,341`) but **never populated** from an event. The `run_override` precedence branch in `FinalizeRoutingPlan` cannot fire in production. | **[V]** |
| **Store-default fallback ignores the record's knowledge store.** `pipeline_bindings.go:298-317` returns the first non-empty `store_default` row with no `KnowledgeStoreID` filter — a multi-store deployment can route a record to another store's default pipeline. | **[V]** |
| **Enforcement-order gap on fallback.** `BuildProcessorGateShadowPlan` is called with `baselineNames` derived from `specs`, which is built from `effectiveRequested` — i.e. the **selected** pipeline's post-allowlist set (`processor_plan.go:180-197, 221-233`). When `FinalizeRoutingPlan` falls back to the baseline pipeline, processors re-admitted by the baseline have no entry in `GateShadow`, so `gateDecisionFor` returns `ok=false` and they run **ungated** (`routing_enforcement.go:150-153`). | **[V]** |
| **Wrong-typed runtime facts yield `operator_error`, not `invalid_fact`.** §11 treats operator failure as fail-closed alarm territory while invalid facts stay indeterminate/trace-only, so a malformed producer value trips the wrong path. | **[V-probe]** boolean-typed `document.has_document_number` with value `"not-a-bool"` → `truth=indeterminate reason=operator_error` |
| **`EvaluateDocument` never validates.** `Validate` correctly rejects a two-child `not` ("expression.items: not requires exactly one child"), but `EvaluateDocument` on the same document silently returns `indeterminate`. | **[V-probe]** both outputs captured |
| **Proposal lifecycle is TOCTOU.** `TransitionProposal` (`applicability_proposals.go:104-136`) reads status via `GetProposal`, validates, then `UPDATE … WHERE id = $1` with **no status guard** and no optimistic concurrency. `included_in_release` is a manual HTTP transition accepting an arbitrary `included_in_release_id` with no verification that the release contains the proposal — contradicting plan H1's "include only approved proposals in the immutable module snapshot." | **[V]** |
| **`EnsureDraftFromModuleRelease` is non-atomic.** | **[V]** — and worse than reported; see §4.2 |
| **Active-policy load failure silently falls back.** `control.go:1540` **discards the error entirely** (not even logged); `runtime.go:134-138` reduces binding/gate load failure to `logger.Warn(… "no policy binding will apply")`. Spec §11: *"An active-policy pointer that cannot be loaded is an error and must not silently fall back as though no policy existed."* | **[V]** |
| **`in`/`not_in` element order changes the canonical checksum.** | **[V-probe]** `in[pdf,docx]` = `6437aee5…`, `in[docx,pdf]` = `8005c5f6…` |
| **Classifier truncates the sample by bytes.** `truncateSample` (`classify-document.go:334-343`) uses `text[:maxSample]`, splitting a multi-byte rune — the pilot corpus is predominantly Chinese. | **[V]** |
| **A known fact with nil confidence bypasses `min_confidence`.** `belowConfidenceThreshold` returns `false` when `fact.Confidence == nil`. A classifier observation carrying no confidence satisfies **any** `min_confidence` gate. | **[V-probe]** `min_confidence=0.9` vs a fact with no confidence → `truth=true reason=matched` |

### 4.2 Confirmed, and worse than reported

**`EnsureDraftFromModuleRelease` (`policy_promotion.go:47-125`) — [V].** Review A calls it
"non-atomic." Four compounding defects:

1. **Structurally cannot be transactional.** It takes `*sql.DB`, not `*sql.Tx`, so it can never join a
   caller's transaction — yet its own doc comment claims it "creates draft pipeline-policy versions
   from approved module proposals **inside the release transaction**", and `DraftPolicyPromoter` is
   documented as "the minimal **transaction** interface". Both are false. A failure after the policy
   `INSERT` leaves an orphan draft with partial bindings.
2. **`MAX(version)+1` race with a swallowed error** — line 73 discards the scan error with `_ =`, so a
   failed query silently yields `nextVersion = 1`, colliding with the existing version 1.
3. **Idempotency key is wrong** — `WHERE source_ref = $1 AND status = 'draft'`. Once promoted and
   activated, the draft is no longer `draft`, so a re-release creates a **second** draft for the same
   release.
4. **Nil-lister panic** — `PromoteModuleReleaseProposals` guards `promoter == nil` then calls
   `lister.ListApprovedProposals` unconditionally.

**Proposal checksums make every promoted draft un-activatable — [V].** Review A says the compiler
"would reject" a promoted draft. It **always** will. `predicateChecksum`
(`applicability_proposals.go:315-318`) returns `"sha256:" + hex(sha256(rawClientBytes))` — a prefixed
hash of unnormalised client bytes. `semrules.Canonicalize` returns a **bare** hex string (verified:
`632b3226a0d1c3ab…`). `policy_compile.go:177-179` compares `stored != checksum` and errors. The two
can never be equal, for any input. Promotion → activation is a closed path.

### 4.3 Revised or downgraded

**[R] `overlap.go` "dead/inverted flags and an unreachable return" — confirmed but harmless; downgrade
to cosmetic.** `leftHasExtra`/`rightHasExtra` (lines 33-34, 51-56) are set only inside the branch that
also sets `leftEqual = false` (line 57); since line 70 requires `leftEqual`, they can never affect the
outcome. Line 79's `return` is unreachable: `leftEqual=false` is set only at line 57 (which sets
`unconstrained=true`, caught at 73) or line 65 (which sets `intersecting=true`, caught at 76).
**However**, the analyzer only ever returns `MayOverlap: false` for genuinely disjoint path values
(line 62), so it is conservative — it over-rejects at compile time rather than under-rejecting. No
correctness hole; dead code only.

**[R] Numeric `2` vs `2.0` "become spuriously conflicting" — narrower than stated.**
`canonicalFactValueKey` → `normalizeObservationValue` (`applicability_facts.go:180-204`) only
normalises *string slices*; scalars pass through to `json.Marshal`. Go marshals `int(2)` and
`float64(2.0)` **both** to `2`, so those do not conflict. Only a `json.Number("2.0")` — which a JSONB
decode can produce — marshals verbatim as `2.0` and collides. Real but narrow. `semrules`' own numeric
comparison is lossless (verified: `int 2`, `float64 2.0`, `json.Number("2.0")` all match `eq 2`).
**Minor.**

**[R] Alarm writer "NULL-kind insert path would error" — likely incorrect, and moot.** PostgreSQL
infers the `ON CONFLICT` arbiter from the index *predicate* matching the statement's `WHERE` clause,
at plan time, independent of row values; the partial index exists, so inference should succeed and a
NULL-`kind` row simply never conflicts. Not fully verifiable without live PostgreSQL **[U]**. Moot
regardless: every P5 alarm producer sets `Kind`.

**[R] Review A's "The I1 exit-test machinery is genuinely good" — partially revised.** The `go/parser`
mechanism is sound and does fail on phantom names, but it skips all cross-package pointers (§3.5) and
three criteria point at tests that do not test them (§3.4).

### 4.4 Not confirmed as defects

Both reviews independently agree:

- **No truth-value bug in the three-valued core.** Kleene logic for `all`/`any`/`not`, typed
  operators, `Validate`, `Canonicalize`, and the fact registry are correct. The masking defect is
  about *trace/decision-relevance*, not truth values.
- **No path where an uncleared suppressive decision changes execution.** Shadow/effective separation
  holds; `checkRoutingClearance` fails closed on nil checker, `ErrNoEffectiveRoutingClearance`,
  multiple clearances, and lookup errors; mandatory-processor immunity holds. `FinalizeRoutingPlan`'s
  enforcement ordering is correct.
- **The alarm dedup migrations are well-formed** — `20260801000019` / `20260801000021` partial unique
  indexes are correctly scoped and mutually non-competing. Their runtime behaviour is **[U]** pending
  I2.

---

## 5. Consolidated defect register

Ordered by remediation priority. IDs are referenced by the companion plan `2026080303`.

| ID | Severity | Finding | Location |
|---|---|---|---|
| **P5-1** | Blocker | G/H/I + fix commit not merged to `main` | repo state |
| **P5-2** | Critical | Resolver inert by construction (`Predicates` never populated) **and** unwired (`ControlService.Resolver` never set); no document sample; `runID=0`; `VocabularyReleaseID=0`; review-side classification absent | `applicability_resolver.go:180-187`, `runtime.go:140`, `control.go:665`, `profiles/select.go` |
| **P5-3** | Critical | Promoted drafts are un-activatable — prefixed non-canonical proposal checksum vs canonical compiler check | `applicability_proposals.go:315`, `policy_compile.go:177-179` |
| **P5-4** | Critical | Promotion never runs in practice (fresh release id, outside transaction, warn-on-failure, `runActivate` omitted) | `cmd/ontology-compiler/main.go:118-131`, `modules/releases_store.go` |
| **P5-5** | Critical | Migrated bindings can never be cleared — md5 stored, canonical expected | migration `…000015:176`, `policy_compile.go:308-316`, `pipeline_bindings.go:100-160` |
| **P5-6** | Critical | Clearance coverage keyed on `input_doc_type`, not `document.doc_kind` | `control.go:1920` |
| **P5-7** | Critical | `semrules` decision-relevance masking is order-dependent | `evaluate.go:57-71, 87-100` |
| **P5-8** | Critical | `frozenSubjectFacts` ignores `TargetObjectID` | `review_service.go:291` |
| **P5-9** | Critical | Indeterminate-only profiles never pinned → no findings | `select.go:279` |
| **P5-10** | Important | `EnsureDraftFromModuleRelease` non-atomic, racy version, wrong idempotency key, nil-lister panic | `policy_promotion.go:47-152` |
| **P5-11** | Important | Active-policy / binding / gate load failure silently degrades (spec §11) | `control.go:1540`, `runtime.go:131-139` |
| **P5-12** | Important | Activation has no runtime effect until restart | `runtime.go:131-139`, policy handlers |
| **P5-13** | Important | Enforcement-order gap: baseline-fallback re-admits processors ungated | `routing_enforcement.go:137-153`, `processor_plan.go:221-233` |
| **P5-14** | Important | Wrong-typed facts → `operator_error` instead of `invalid_fact` | `evaluate.go:197-214` |
| **P5-15** | Important | `EvaluateDocument` never validates; invalid docs degrade to `indeterminate` | `evaluate.go:35` |
| **P5-16** | Important | Nil confidence bypasses `min_confidence` | `evaluate.go:245-250` |
| **P5-17** | Important | Proposal lifecycle TOCTOU; `included_in_release` unverified | `applicability_proposals.go:96-136` |
| **P5-18** | Important | Store-default fallback ignores knowledge store | `pipeline_bindings.go:298-317` |
| **P5-19** | Important | `DOC_PIPELINE_ON_CONFLICT` never read; gate block mode unreachable | `routing_enforcement.go:199`, `pipeline_selection.go:118` |
| **P5-20** | Important | `ProcessorGateOverrides` never populated → `run_override` path dead | `processor_plan.go:65` |
| **P5-21** | Important | Criteria 9, 13, 15 mapped to tests that do not test them | `p5_exit_test.go:40-97` |
| **P5-22** | Important | Exit-test parser check skips all cross-package pointers | `p5_exit_test.go:127` |
| **P5-23** | Important | Proposals handler has zero tests; `releases_store_test.go` missing | plan H1/H2 file list |
| **P5-24** | Minor | `in`/`not_in` operand order changes canonical checksum | `canonical.go`, `overlap.go` |
| **P5-25** | Minor | Classifier byte-truncates UTF-8 (CJK corpus) | `classify-document.go:334-343` |
| **P5-26** | Minor | `json.Number("2.0")` vs `2` spuriously conflicting | `applicability_facts.go:180-204` |
| **P5-27** | Minor | `overlap.go` dead flags + unreachable return (conservative; harmless) | `overlap.go:33-34, 51-57, 79` |
| **P5-28** | Minor | `restoreMandatoryProcessors` omits `classify_document` | `routing_enforcement.go:269` |
| **P5-29** | Minor | `gofmt` fails on `routing_alarm.go`; doc-processor capsule has no P5 section | — |
| **P5-30** | Deferred | I2 live PostgreSQL + synthetic-corpus proof | plan I2 |

---

## 6. Status of the earlier fix plan `2026080201`

Partially executed by commit `aa15`. Reconciled here:

| Phase | Item | State |
|---|---|---|
| A1 | Wire `ApplicabilityResolver` into `ControlService` | **Incomplete** — field + call site added; nothing constructs the resolver, and §3.1 shows the call is inert anyway |
| A2 | Fix `PromoteModuleReleaseProposals` type mismatch | **Done** |
| A3 | Wire promotion into `ontology-compiler` | **Done but ineffective** — see P5-4 |
| A4 | Create proposals HTTP handler | **Done**; tests never written (P5-23) |
| A5 | Register proposal routes | **Done** — `routes.go:479-482` |
| B1 | Replace phantom test names | **Done** — all 15 now resolve |
| B2 | Add missing tests for uncovered criteria | **Nominally done** — 3 of 7 do not test their criterion (P5-21) |
| B3 | Strengthen coverage verification | **Partial** — `go/parser` check added, cross-package names skipped (P5-22) |
| C1 | Update ontology capsule | **Done** |
| C2 | Update ADR changelog | **Done, but the entry is now inaccurate** — it claims P5 is "implemented and **wired**: … two-pass `classify_document` resolver with tier-3 facets" |
| C3 | Check off plan checkboxes | **Not done for A1–F2** — still unchecked |
| D | Verification | **Partial** — `gofmt` not clean (P5-29) |

---

## 7. Documentation impact

**What knowledge changed.** P5 is not complete in the code-level sense the ADR, handoff, and impl log
claim. Two independent reviews converged on this. Beyond review A: the resolver is inert by
construction rather than merely unwired (larger remediation), clearance coverage is keyed on the wrong
dimension (fails *open* toward over-enforcement), activation is inert until restart, and three
acceptance criteria are satisfied by tests that do not test them.

**Which docs are affected / now stale.**

- ADR `2026072901` — the 2026-08-03 P5 entry overstates completion; "wired" is false.
- Handoff `2026073002` — "All code-level P5 work (G, H, I1, I3) is complete" is false.
- Impl log `2026080107` — commit list predates `aa15`; G/H/I claims, the "gofmt clean" line, and the
  three-item "Known limitations" list are all incomplete.
- Plan `2026080103` — checkboxes A1–A4, B1–B3, C1, E3, F1, F2 unchecked despite implemented code;
  I3 closeout unchecked. Not a reliable completion record.
- Fix plan `2026080201` — superseded by §6 above and the companion plan.
- Bug report `2026080301` — superseded by this document; three items revised (§4.3).

**Which docs were updated.** This review only. Corrections to the ADR / handoff / impl log / plan
checkboxes are scheduled as work items in plan `2026080303`, not applied here.

**What was intentionally left undocumented.** Authority-owned pilot values and standard editions
remain out of scope (unchanged from the spec's own non-goals). No code, schema, or documentation
outside this file was changed by this review; the two throwaway probe test files were deleted after
their output was captured, and both repositories were left as found.

**Working-tree note.** `KnowledgeStore` carried uncommitted changes before this review began
(`bugs/202608/2026080301-…md` and `bugs/OPEN.md`). They are unrelated to this document and were not
touched.
