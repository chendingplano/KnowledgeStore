# SemOS P3 Implementation Review — Completeness, Correctness, Tests

**Date:** 2026-08-01
**Status:** Review record. Downgrades the "Built and complete" framing in ADR `2026072901` §8.3.6
and in the P3 implementation log (`2026080103-devdoc-semos-p3-implementation-log.md`) for the items
below; the schema/store-layer claims in that log stand. **Update, same day:** the six items in the
Recommendation section were fixed in this session — see the P3 log's §12 addendum and the ADR
§8.3.6 correction block for the fix summary. This document is kept as the historical finding
record; it is not itself updated in place.

**Scope reviewed:** migrations `20260801000001`–`20260801000006`; `ChenWeb/server/api/ontology/assertions/`;
the Phase D wiring in `ChenWeb/server/api/doc-processing/phase_d.go` and `control.go`; the drain
endpoint in `ChenWeb/server/api/kbhandler/drain_deferred_decisions_handler.go`. `go test
./server/api/ontology/assertions/... -count=1` passes as of this review (5ms; no DB-backed tests
exist to fail).

## Summary

The schema and store layer (DR9 assertion/evidence tables, the operational state machine, the
decision-candidate lifecycle, fingerprint dedup) is sound and matches DR9/DR11 seam 5 as designed.
What does not hold up is the claim that P3 delivered Phase D as ADR §8.2 defines it, and the claim
that the mechanisms behind several §16.2/§16.3 exit criteria are actually reachable in production.
Two concrete gaps dominate:

1. **The three Phase D stages were never built as doc processors.** ADR §8.1/§8.2 requires
   `normalize_assertions`, `associate_semantics`, `project_semantics` to each be a declared,
   routed `ProcessorSpec` with pipeline-table/dashboard registration (the same checklist P4 later
   followed for its four processors). P3 chunk F replaced the three per-stage wrapper files with
   one orchestrator (`assertions.RunPhaseD`) called from one hardcoded site in `control.go`,
   gated only by an environment flag — invisible to the DR5 planner, the DR6 routing policy, and
   the persisted execution plan.
2. **The free-text metric parser fabricates and mis-parses values** on inputs shaped like the real
   corpus, contradicting the P3 log's own "never a fabricated value" claim, and several mechanisms
   the exit-criteria mapping cites as satisfied (projection staleness, evidence retraction, seam
   5/7 extensibility, telemetry reconciliation) have no caller anywhere in production code.

## 1. Completeness

**Phase D is not a stage DAG participant.** `ChenWeb/server/api/doc-processing/phase_d.go:37`
(`ControlService.runPhaseD`) is called unconditionally from `control.go:825` after Phase C,
gated only by `SEMANTIC_ASSOCIATION_ENABLED`. Verified absent, by contrast with P4's
`extract_metric_definitions` (`processor_plan.go:308`, `runtime.go:72`,
`control.go:1890`, dashboard state):

| Required (ADR §8.1/§8.2, DR5) | Phase D |
|---|---|
| `ProcessorSpec` entry in `productionProcessorSpecs` | none |
| Processor type + `runtime.go` registration | none |
| `requiresChunkingDependency` / DAG dependency declaration | none |
| Dashboard registration | none |
| Persisted execution plan visibility ("why did/didn't X run") | none |

`RunPhaseD` (`telemetry.go:126`) also runs every registered normalizer against every input record
unconditionally once the flag is on — there is no per-store or per-document routing, which is the
exact capability DR6/DR7 exist to provide.

**Seams 5 and 7 are open registries feeding closed consumers.** `AssociateSemantics.Run`
(`associate_semantics.go:46`) filters `source_artifact_type IN ('metric','provision')` and
dispatches on a hardcoded `switch` (`:116`); `DrainDeferredCandidates`
(`backlog_drain.go:80`) hardcodes `LookupNormalizer("metric")`. `ProjectSemantics.Run`
(`project_semantics.go:41`) looks up exactly one projection kind and its target query
(`classificationTargetsForRecord`, `:60`) is hardcoded to `core:instance_of` — despite the
adjacent comment claiming a second projection kind "requires no change here." A third family
registered through seam 5 would have its candidates counted by telemetry and then never
processed by any downstream stage.

**Projection staleness has no caller.** `ProjectionStateStore.MarkStale`
(`projection_registry.go:180`) is never invoked in production; `buildPrimaryClassProjection`
(`classification_projection.go:47`) records success/failure by writing or clearing
`kb.projection_state` directly, and `ProjectSemantics.Run` does `report.Errors++; continue` on a
build failure (`project_semantics.go:47-50`) without marking anything stale. `stale`/`stale_reason`
are therefore dead columns. `RepairStaleProjections` (`project_semantics.go:93`) likewise has no
caller — no endpoint, no `kb.scheduled_jobs` entry (the mechanism DR8 names explicitly for
backlog/drain work) — so `StaleProjectionsFound`/`Repaired` on `AssociationRunReport` are
permanently zero.

**Evidence retraction has no caller.** `EvidenceStore.DeleteEvidence` — the mechanism behind
§16.3 item 16 (accepted → `unsupported` → restored) — is exercised only by the deleted
`p3validate` program. No reprocessing or input-deletion path in this workspace calls it.

**`extract_metrics` structured output remains undone**, now across two phases. ADR §8.2 calls it
"the single highest-leverage change for the application"; P3 deferred it explicitly (log §8 item
10), P4 built the other three changed/new §8.2 processors but not this one. It is the direct cause
of Finding 2b below, since the metric normalizer has to parse `threshold_or_target` free text
instead of consuming structured fields.

**Not built, correctly recorded as deferred in the log:** `kb.artifact_semantic_links`, the
keyword lexicon (Track B, design-only), the DR6/DR7 halves of the backlog drain, a
governed-term-availability drain, a real classification-assertion producer, the input-deletion
cascade, unit-term resolution against QUDT. These are honest non-claims and are not re-litigated
here.

## 2. Correctness

Ranked by likelihood of surfacing against the real pilot corpus, mirroring the P4 review's format.

**a. The F3 revision-supersede bug was fixed in one store and left in the sibling store.**
`AssertionStore.CreateRevision` (`assertions_store.go:352`) supersedes the prior revision only
`if prior.Status == StatusAccepted` — verbatim the bug §F3 of the P3 log found and fixed in
`DecisionCandidateStore.Propose` (`decision_candidates_store.go:285`, now
`prior.Status != StatusSuperseded`). Reachable today: `associate_semantics.processMetric` creates
the assertion at `candidate` and then performs five more un-transacted writes
(`associate_semantics.go:227-256`); a crash after `persistAssertion` but before the final
`TransitionStatus` leaves revision 1 at `candidate` while a later run creates revision 2, and both
sit in a non-terminal/accepted status simultaneously. If the prior revision is `unsupported`,
`EvidenceStore.AddEvidence` restoring it to `accepted` produces the same two-live-revisions shape
next to a newer revision.

**b. The metric parser fabricates values and mis-detects comparators on corpus-shaped text.**
Verified by running `parseThresholdOrTarget` (`metric_normalizer.go:173`) directly:

| Input | Produced | Correct |
|---|---|---|
| `1 m 距离处清晰辨识` | `observed_value`, 1 | `unparsed` |
| `在 1 m 距离处不低于 250 cd/m²` | `>= 1` | `>= 250` |
| `-20 ℃ 至 50 ℃` | `observed_value`, −20 | interval [−20, 50] |
| `不应超过 5 %` | `observed_value`, 5 | `<= 5` |
| `GB 9706.1-2020 规定不低于 250` | interval [9706.1, 2020] | `>= 250` |

Causes: `reNumber.FindString` (`:196`) takes the first number in the string regardless of the
comparator's position; `reRange` (`:153`) matches any `N - M` shape including numbers embedded in
identifiers/dates, and range-matching runs before comparator detection (`:185` precedes the
switch at `:205`); and `不应超过` is absent from `reUpperBound` (`:152`), so a prohibition on
exceeding a value silently becomes an `observed_value`. Row 1 directly contradicts P3 log §C2,
which cites this exact string as a correctly-`unparsed` case and states the normalizer "never
fabricates a value." These land as `accepted` assertions with wrong `numeric_value`/
`assertion_kind`/`comparator`, feeding DR21 comparisons downstream.

**c. Provision modality substring-matches over untokenized text.** `应` (`provision_normalizer.go:136`)
matches inside 响应/适应/相应 — `"触摸响应时间为 120 ms"` classifies as `required`; `可`
(`:137`) matches inside 可能/可靠性. `parseProvisionModality`'s negation-first ordering (`:145`)
correctly handles 不应-contains-应, but does nothing for these false-positive substring matches.
`recommended` and `permitted` are also collapsed into the same `assertion_kind` by
`provisionAssertionKind` (`:166`), erasing a distinction DR21 needs later. Currently inert (every
provision candidate defers on the missing deontic-predicate term, log §5), so latent rather than
live.

**d. Association telemetry cannot detect what it claims to detect.** `BuildAssociationRunReport`
(`telemetry.go:57`) increments `ArtifactsExamined` and all three buckets
(`CandidatesByMethod`/`ResolutionOutcomes`/`LifecycleCounts`) from the same per-row loop
(`:88-96`), so `Reconciles()` (`:37`) is true by construction for any report this function
produces — it cannot fail, so it cannot catch an unaccounted candidate; `TestAssociationRunReportDetectsUnaccountedCandidates`
only proves the arithmetic, not that a real gap would surface. Separately, `ArtifactsExamined`
counts decision-candidate rows, not artifacts examined — the normalizers *do* skip artifacts
(`metric_normalizer.go:85`, `provision_normalizer.go:76` via `report.Skipped++`), but
`RunPhaseD` (`telemetry.go:144`) discards each `NormalizeReport` entirely, so skipped artifacts
never appear anywhere in the run report.

**e. Ambiguous vs. absent referents share one label.** A metric candidate with *zero* resolved
referents is recorded with `resolution_reason='ambiguous_targets'`
(`associate_semantics.go:160`) and then deferred under reason `unresolved_referent` (`:163`).
"Ambiguous" means multiple candidates, not none — the mismatch is confusing during backlog triage
and echoes a labeling issue already seen in the object-reconciliation backlog work.

**f. No FK protects P3's record-scoping columns.** `kb.assertion_evidence.input_record_id`
(migration `20260801000002:19`) and `kb.semantic_decision_candidates.input_record_id`
(`20260801000006:7`) are both plain `BIGINT` with no `REFERENCES kb.inputs(id)` — unlike
`kb.ontology_review_runs.input_record_id`, which P4 added correctly with the FK and a note that
P3/P4 had previously pointed a sibling column at the wrong table. Deleting an input currently
orphans both rows silently; no input-deletion cascade exists yet either (log §8 item 8, already
recorded as deferred).

**Minor:**
- `AssociateSemantics.Run`'s five-plus-write sequence per accepted metric
  (`associate_semantics.go:227-256`) is not wrapped in a transaction; (a) above is the concrete
  consequence.
- `ProjectSemantics.classificationTargetsForRecord` hardcodes `core:instance_of` rather than
  iterating registered projection kinds' own target queries, so seam 7's "adding a kind requires
  no change here" claim (`project_semantics.go:22`) does not hold once a second kind exists.

## 3. Tests

`go test ./server/api/ontology/assertions/... -count=1` passes in 5ms because no test in the
package opens a database connection or exercises a store method against anything beyond
`sqlmock`. Files with zero tests: `associate_semantics.go` (the entire resolve/validate/adjudicate/
persist path), `project_semantics.go`, `classification_projection.go` (only
`TestClassificationProjectionSelfRegistered`, which checks registration, not behavior),
`normalizer_registry.go`, `relations_store.go`. The P3 log §9's claim of "corresponding `_test.go`
files" for all fifteen implementation files is inaccurate for these five.

**Neither live-found bug (§F3, §F6) has a regression test.** The F3 supersede fix has none at all.
The F6 `in_review` resumability fix is represented by
`TestP3ExitItem13ResumesFromInReviewAfterSimulatedCrash`, which asserts two state-machine
transition predicates directly and never calls `AssociateSemantics.Run` — deleting the
`status IN ('candidate','in_review')` clause from the real SQL query would leave this test green.

`p3_exit_test.go` maps 17 spec §16.3 items plus 2 §16.2 items onto 4 tests; the majority
(§16.2 items 6, §16.3 items 6/7/10/11/14/16/17 in the case of item 17 above) are backed only by
"live-validated" pointers to the deleted `p3validate` program, not by anything that runs in CI.
This is the same test-shape critique the P4 implementation review made of P4's own suite
("honest about shape and misleading about behavior") — it applies equally here.

## Recommendation / next steps

The schema and store-layer model are worth keeping as-is; ranked by what's load-bearing before P3
can be re-claimed as complete:

1. **Fix the sibling supersede bug** — `assertions_store.go:352`, change the guard to
   `prior.Status != StatusSuperseded` to match the already-fixed `decision_candidates_store.go`
   logic, and add a regression test for both the assertion- and candidate-store cases.
2. **Register the three Phase D stages as `ProcessorSpec`s** and route them through the normal
   pipeline (Phase D, `Class: routed`, `DependsOn` the Phase C processors) — copy P4's
   registration pattern (`processor_plan.go`, `runtime.go`, `control.go`,
   `requiresChunkingDependency`, dashboard state). Keep `assertions.RunPhaseD` as the
   implementation the new processor(s) call.
3. **Fix the metric parser**: anchor the numeric match to the comparator's position rather than
   taking the first number in the string, require the range separator to sit between two bare
   numbers (not inside an identifier/date), and add `不应超过`/`不得超过`/`不得低于` to the
   upper-bound vocabulary. Re-run against the record-2 gold-corpus rows and reconcile the result
   with the P3 log's §C2/§D2 numbers, which do not currently reproduce.
4. **Wire projection staleness end to end**: call `MarkStale` on a build failure in
   `ProjectSemantics.Run`, and give `RepairStaleProjections` a caller (endpoint or
   `kb.scheduled_jobs` entry, per DR8).
5. **Make seams 5 and 7 registry-driven in their consumers**, not just their producers —
   `AssociateSemantics.Run`'s artifact-type filter/dispatch, `DrainDeferredCandidates`'s
   hardcoded normalizer lookup, and `ProjectSemantics`'s hardcoded target query should all iterate
   registered instances.
6. **Correct the status annotations** in the P3 implementation log and ADR `2026072901` §8.3.6:
   "Built and complete," "never a fabricated value," and the "corresponding `_test.go` files"
   claim all overstate current state, and P4 was built on top of this framing without knowing it
   understated the gap.

Separately: `extract_metrics` structured output has now been skipped across two consecutive
phases while remaining the ADR's stated highest-leverage change. This needs an explicit decision
(commit to it, or formally move it into a later phase) rather than a third silent deferral.

**2026-08-01 (decision made and implemented, same day):** committed and built by the OpenSpec
change `extract-metrics-structured-output`
(`ChenWeb/openspec/changes/extract-metrics-structured-output/`) — `kb.metrics` gains
`value_min`/`value_max`/`condition`; the normalizer consumes the structured fields with
`parseThresholdOrTarget` demoted to a legacy fallback; QUDT unit-term resolution is implemented in
`associate_semantics.processMetric`. Finding 2b's fabrication class is closed for new rows
structurally. See the P3 log `2026080103` §12.1 addendum and the ADR §8.2 status annotation.

## Documentation impact

**What knowledge changed?** P3's "Built and complete" status is downgraded: the schema/store
layer stands; the Phase D pipeline-integration and several exit-criteria mechanisms
(projection staleness, evidence retraction, telemetry reconciliation, seam 5/7 extensibility) do
not meet their own stated acceptance criteria, and the metric-value parser is unreliable on
corpus-shaped Chinese text.

**Which docs/specs/ADRs/tests are affected?** The P3 implementation log
(`2026080103-devdoc-semos-p3-implementation-log.md`) and ADR `2026072901` §8.3.6's 2026-08-01
status annotation. `p3_exit_test.go` exists but under-covers its own mapping table; several items
have no code-reviewable test at all.

**Which docs were updated?** This devdoc (status line only). The P3 log gained a §12 addendum and
the ADR §8.3.6 status block gained a correction paragraph, both recording that items 1, 2, 3, and
the projection-staleness/seam-5/seam-7 halves of items 4–5 were fixed in this same session (item
6, `extract_metrics` structured output, was explicitly left open — see the Separately note above).

**Which docs are stale?** The P3 log's framing of chunks 0–F as "complete against their stated
scope" is stale relative to the findings above; its DR9 schema and state-machine claims are not
stale.

**What was intentionally left undocumented?** None — this review is itself the record of what was
found undocumented (Phase D's absence from the stage DAG, the un-called staleness/retraction
mechanisms) in the prior log.
