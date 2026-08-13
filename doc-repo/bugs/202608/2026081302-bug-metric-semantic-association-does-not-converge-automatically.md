# Metric semantic association does not converge automatically after document processing

Date: 2026-08-13

Status: second follow-up implementation reviewed against code and production
data (2026-08-13); **do not close — one operational step remains.** All five
original findings are now fixed at the code level, including the range
fabrication regression (F3/G1), verified across every `range`-family row in
`kb.metrics`, not just the four originally cited. Record 416 itself has not
been reprocessed: its `kb.artifact_objects` rows are still the stale,
wrong-subject July links, and it must go through metric extraction again
(never a direct association run) before its acceptance criteria can be
verified against real output (G3). A non-blocking completeness gap remains in
the range fallback's unit handling (G2).

System: `ChenWeb` document processing / SemOS semantic assertion pipeline

Component: `extract_metrics`, metric identity resolution, `normalize_assertions`,
`associate_semantics`, deferred-candidate recovery, artifact-to-object reconciliation

Input record: `416` (`std_1503937.pdf`)

Related: [Metric Assertions and Semantic Processing manual](../../user-manuals/metric-assertion-semantic-processing-v1.1-en.md),
[production measurement-vocabulary bootstrap bug](2026081301-bug-production-semantic-association-missing-measurement-vocabulary.md),
`ChenWeb/server/api/ontology/assertions/{metric_normalizer.go,associate_semantics.go,backlog_drain.go}`.

## Implementation update (2026-08-13)

Implemented in ChenWeb commit `406a` (`Fix metric semantic association
convergence`). The implementation:

- canonicalizes the production extractor's lower-bound, upper-bound, exact,
  and range vocabulary before normalization;
- derives metric assertion-kind eligibility from released `mea:*` ontology
  terms, so released `mea:exact_value` is no longer blocked by a Go
  allowlist;
- automatically re-normalizes referent-deferred records and retries
  governed-term-deferred candidates only when their dependency availability
  fingerprint changes;
- carries `metric_definition_term_id` into the semantic candidate and the
  accepted assertion's qualifiers; and
- logs deferred-candidate counts by reason in the Phase-D run report.

The change also claimed: "Fresh metric processing already reconciles usable
metric subjects before Phase D. A later subject-object link is picked up by
the automatic re-normalization recovery path." **The review below shows this
claim is false on the live extraction path** (see R3). Record 416 has not yet
been reprocessed as part of this change.

Implementation details and test record:

- `ChenWeb/docs/superpowers/specs/2026-08-13-metric-semantic-convergence-design.md`
- `ChenWeb/docs/superpowers/plans/2026-08-13-metric-semantic-convergence.md`

## Summary

The metric semantic-processing path is documented and intended to run without
a human operator:

```text
extract_metrics
  -> resolve metric name to keyword concept and metric-definition term
  -> kb.metrics
  -> normalize_assertions
  -> kb.semantic_decision_candidates
  -> associate_semantics
  -> kb.semantic_assertions + kb.assertion_evidence
```

For input record 416, metric name resolution completed for every extracted
metric: all 66 `kb.metrics` rows have both `keyword_concept_id` and
`metric_definition_term_id`. Nevertheless, all 66 metric decision candidates
are deferred and no accepted assertion or evidence row exists for the record.

This is not an intended requirement for human review. Human review is useful
for correcting genuinely bad extraction, but ordinary lower/upper bounds,
exact numeric values, and subjects present in the document must proceed
automatically. The observed result is caused by three confirmed automation
bugs and two implementation gaps.

## Expected behavior

For a metric whose name has been resolved, whose value can be expressed in a
supported form, and whose subject can be determined from the document, the
pipeline should automatically create an accepted assertion and supporting
evidence. If a prerequisite becomes available later, such as a released
governed term or a reconciled subject object, the affected candidate should be
automatically retried.

The `status` and the accompanying `decision_reason`/
`dependency_fingerprint` on `kb.semantic_decision_candidates` should provide
the operational explanation for every candidate that does not reach
`accepted`.

## Actual behavior and database evidence

The following query exposes the association outcome and reason directly from
the candidate table:

```sql
SELECT source_artifact_type, status, dependency_fingerprint, count(*)
FROM kb.semantic_decision_candidates
WHERE input_record_id = 416
GROUP BY 1, 2, 3
ORDER BY 4 DESC;
```

Metric candidates for record 416 are all `deferred`:

| Deferral reason | Count | Meaning |
|---|---:|---|
| `no_governed_assertion_kind_term:unparsed` | 37 | Normalization did not map the extracted value shape to a supported assertion kind. |
| `unresolved_referent` | 20 | No `kb.artifact_objects` subject-object link was present for the metric. |
| `no_governed_assertion_kind_term:exact_value` | 6 | `mea:exact_value` was not yet released when these were processed; it is now, but see Finding 5 -- release alone does not unblock them. |
| `governed_term_not_released:mea:measured_by,mea:lower_bound_requirement` | 3 | The candidate was processed before required measurement terms became available. |

There are no semantic assertions or evidence rows scoped to record 416:

```sql
SELECT a.id, a.status, a.subject_object_id, a.predicate_term_id,
       a.assertion_kind_term_id
FROM kb.semantic_assertions a
JOIN kb.assertion_evidence e ON e.assertion_id = a.id
WHERE e.input_record_id = 416;
```

The result is empty.

## Findings and root causes

### 1. Normalization and extraction use incompatible `value_range_type` vocabularies

`MetricNormalizer.resolveMetricValue` maps only these structured range types:

```text
lower_bound, upper_bound, exact, range
```

The actual extractor output for record 416 includes, among others:

```text
min, max, minimum, maximum, exact_count, exact_duration,
exact_ratio, exact_specification, min_threshold
```

Since a nonempty but unrecognized `value_range_type` prevents the normalizer
from falling back to its otherwise capable free-text parser, values such as
`≥30` and `≤30` become `unparsed` rather than lower- or upper-bound
assertions. Examples:

| Metric | Extracted range type | Extracted value | Current outcome |
|---|---|---|---|
| 有机质的质量分数（以烘干基计） | `min` | `≥30` | `unparsed` / deferred |
| 水分（鲜样）的质量分数 | `max` | `≤30` | `unparsed` / deferred |
| 总砷（As）（以烘干基计） | `max` | `≤15` | `unparsed` / deferred |

This is a confirmed contract bug. The normalizer must canonicalize the
extractor's accepted vocabulary before mapping it to assertion kinds, or the
extractor must emit the normalizer's canonical vocabulary. Tests must exercise
the real variants, not only `lower_bound` and `upper_bound`.

### 2. Deferred candidates are terminal to ordinary association runs

`AssociateSemantics.Run` selects only candidates with status `candidate` or
`in_review`. It does not select `deferred` rows.

The three lower-bound candidates and six exact-value candidates were deferred
when their required terms were unavailable. The terms are now present with
`status = 'included_in_release'`, but a later standalone
`associate_semantics` run examined no candidates because their status remained
`deferred`. (The three lower-bound candidates would pass on such a retry; the
six exact-value candidates would not -- see Finding 5, a separate allowlist
bug that blocks them independent of term release.)

The existing `DrainDeferredCandidates` helper only selects the exact
dependency fingerprint `unresolved_referent`; it does not retry
`governed_term_not_released:*` or `no_governed_assertion_kind_term:*` rows.

This is a confirmed recovery bug. Candidates must be retried automatically
when a dependency changes. A release of a required governed term must enqueue
or drain candidates deferred on that term. Re-normalization should be used
where the candidate payload itself changes; a dependency-based retry is
appropriate when only term availability changes.

### 3. Subject-object reconciliation covers only 46 of 66 metrics

The normalizer obtains `subject_object_id` through `kb.artifact_objects`. For
record 416, 46 distinct metric artifacts have such a link and 20 do not.
Those 20 candidates defer with `unresolved_referent`, even though metrics such
as `分类投放定时`, `收运频率`, and `农村户用沼气池容积` have extracted
`metric_subject` text.

Association is correct not to invent a governed subject. The missing
automation is upstream: the pipeline must reconcile the extracted metric
subject to an object node, or create a deterministic document-scoped object
when policy allows it. Without that step, fully automatic association is
impossible for those metrics.

### 4. Metric identity resolution is not consumed by assertion association

All 66 metrics have successful identity fields:

```sql
SELECT count(*) AS metrics,
       count(keyword_concept_id) AS keyword_concepts,
       count(metric_definition_term_id) AS metric_definition_terms
FROM kb.metrics
WHERE input_record_id = 416;
```

Result:

| Metrics | Keyword concepts | Metric-definition terms |
|---:|---:|---:|
| 66 | 66 | 66 |

However, the metric candidate payload and `processMetric` carry metric name,
value, unit, condition, and subject object only. They do not carry or persist
`metric_definition_term_id`. Thus a successfully auto-created or matched
metric-definition term is currently irrelevant to the acceptance decision.

This is a design gap rather than the direct cause of every deferral, but it
breaks the intended end-to-end semantic connection and makes the prior metric
identity work unavailable to semantic-assertion queries.

### 5. The governed assertion-kind allowlist excludes `exact_value` regardless of term release

`AssociateSemantics.processMetric` gates every metric candidate on a
hardcoded Go allowlist, `governedMetricAssertionKinds`, before it ever checks
whether the corresponding ontology term is released:

```text
lower_bound_requirement, upper_bound_requirement, interval_requirement,
observed_value, target, reference, capability
```

`exact_value` is not a member. The check `!governedMetricAssertionKinds[p.AssertionKind]`
short-circuits and defers on `no_governed_assertion_kind_term:exact_value`
*before* the subsequent `termExists` lookup runs, so a candidate with
`assertion_kind: exact_value` cannot be accepted regardless of whether
`mea:exact_value` is released. It now is (`kb.ontology_terms.status =
'included_in_release'`), but the six exact-value candidates for record 416
remain `deferred`: releasing the term was necessary but not sufficient, and
fixing Finding 2's recovery bug alone would not unblock them either, since a
retry would hit the same allowlist gate.

`MetricNormalizer.resolveMetricValue`'s own comment predates this: it
documents `exact_value` deferring via `no_governed_assertion_kind_term`
"because no governed `mea:exact_value` term is seeded yet." That term now
exists; `governedMetricAssertionKinds` in `associate_semantics.go` was never
updated to match, so the deferral reason recorded for these six rows is now
stale rather than descriptive of the actual blocker.

This is a confirmed bug -- a hardcoded allowlist that has drifted out of sync
with the released term catalog -- not a term-availability timing issue.

## Status observability

The failure reasons were found by reading the rows in
`kb.semantic_decision_candidates`, specifically:

- `status` — the lifecycle state, such as `candidate`, `deferred`, or
  `accepted`;
- `decision_reason` — the reason recorded when association resolves, defers,
  or rejects the candidate; and
- `dependency_fingerprint` — the dependency-specific key used by recovery
  logic to identify why a candidate could not progress.

For example, to inspect individual metric failures:

```sql
SELECT source_artifact_id,
       proposed_payload->>'assertion_kind' AS assertion_kind,
       proposed_payload->>'value_form' AS value_form,
       status,
       decision_reason,
       dependency_fingerprint
FROM kb.semantic_decision_candidates
WHERE input_record_id = 416
  AND source_artifact_type = 'metric'
ORDER BY id;
```

This table is therefore the correct primary diagnostic source for association
failures. It should be surfaced in operational telemetry and review tooling,
not treated as an internal-only record.

## Required remediation

1. Define one canonical `value_range_type` contract shared by extraction and
   normalization; map the currently emitted synonyms and structured shapes.
2. Add regression tests using the actual production values (`min`, `max`,
   `minimum`, `maximum`, exact counts/durations, and ranges).
3. Add automatic deferred-candidate recovery keyed by dependency type:
   governed-term release, new assertion-kind support, and resolved referent.
4. Add `exact_value` to `governedMetricAssertionKinds` in
   `associate_semantics.go`, or derive the allowlist from released `mea:*`
   terms directly so the Go allowlist and the term catalog cannot drift apart
   again.
5. Ensure every association-eligible metric gets an automatic subject-object
   reconciliation attempt before normalization/association.
6. Carry `metric_definition_term_id` from `kb.metrics` into the semantic
   candidate and accepted assertion model, or explicitly revise the design to
   state that metric identity is not part of semantic assertions.
7. Emit per-run counters by defer reason and alert when a normally supported
   metric corpus has a high deferred rate.

## Acceptance criteria

- Reprocessing record 416 after the fixes creates accepted metric assertions
  and corresponding `kb.assertion_evidence` rows without a human edit.
- `min`/`max` values such as `≥30` and `≤30` normalize as lower/upper bound
  requirements.
- Candidates deferred solely because their required terms were unreleased are
  retried and accepted after those terms are released.
- Candidates deferred as `no_governed_assertion_kind_term:exact_value` are
  accepted once `mea:exact_value` is released, without requiring a separate
  code change to an assertion-kind allowlist.
- Every metric with a usable extracted subject is automatically linked to a
  valid object or is reported with an explicit, actionable reconciliation
failure.
- Operational output reports candidate counts by status and deferral reason
for each document-processing run.

## Review of the implementation (2026-08-13)

Reviewed commit `406a` against the source tree and against live `miner` data
for record 416. `go test -count=1 ./server/api/ontology/assertions/...
./server/api/doc-processing/...` passes.

| Original finding | Verdict | Detail |
|---|---|---|
| 1. `value_range_type` vocabulary mismatch | **Partially fixed; new regression** | R1 |
| 2. Deferred candidates terminal to association runs | **Fixed**, untested | R2 |
| 3. Subject-object reconciliation covers 46/66 | **Not fixed**; worse than reported | R3 |
| 4. Metric identity not consumed by association | **Fixed** | R4 |
| 5. `exact_value` allowlist | **Fixed** | R5 |
| 7. Per-run deferral telemetry | **Fixed** (counters); no alerting | R6 |

### R1. Canonicalization is real but incomplete, and now fabricates one value

`canonicalMetricValueRangeType` in `metric_normalizer.go` resolves the three
examples in Finding 1 correctly — verified by driving `resolveMetricValue`
with record 416's actual column values:

| Metric | `value_range_type` | `metric_value` | Result |
|---|---|---|---|
| 有机质的质量分数 | `min` | `≥30` | `lower_bound_requirement`, `>=`, 30 ✅ |
| 水分（鲜样）的质量分数 | `max` | `≤30` | `upper_bound_requirement`, `<=`, 30 ✅ |
| 总砷（As） | `max` | `≤15` | `upper_bound_requirement`, `<=`, 15 ✅ |

Three problems remain.

**(a) A fabricated numeric value — new, introduced by this change.**
`exact_ratio` now canonicalizes to `exact`, and the `exact` branch calls
`firstParseableNumber(metric_value)`, which has no ratio handling. Record
416's 固液比 (solid-liquid ratio) has `metric_value = '1:10'`, and
`firstParseableNumber` returns **1**:

```text
固液比   vrt=exact_ratio   value=1:10   =>   kind=exact_value   cmp==   num=1
```

`mea:exact_value` is released and the Go allowlist gate is gone, so this row
will now be **accepted** as an assertion stating the ratio equals 1. Before
the change, `exact_ratio` was an unmapped enum and the row deferred as
`unparsed` — safe. `parseThresholdOrTarget` already carries
`reRatioDenominatorOne` for exactly this notation; the structured path has no
equivalent. This violates the normalizer's own documented "never fabricates a
value" invariant.

**(b) The `range` canonicalization is inert.** The `range` branch requires
both `value_min` and `value_max`. Across the whole database, **0 of 654** rows
with a range-family `value_range_type` have either column populated. Record
416's two range metrics — 酸碱度（pH）`5.5~8.5` and 浸出液保存温度 `0℃～4℃`
— therefore still resolve to `unparsed`. The free-text parser would have
handled `5.5~8.5` via `reRangeKeyword`, but the structured path deliberately
does not fall through to it. Mapping `range`/`interval`/`between`/
`value_range` accomplishes nothing until either the extractor populates
`value_min`/`value_max` or the range branch parses `metric_value`.

**(c) 16 of record 416's 66 rows still carry unmapped vocabulary**:
`standard` (8), `percentage` (3), `unspecified` (2), `continuous`,
`categorical`, `binary`. Several are legitimately non-numeric — the
`standard` rows hold values like `NY884`, `GB 16889`, `表3`, which are
conformance references rather than measurements — so deferring is correct;
but they defer under `no_governed_assertion_kind_term:unparsed`, which
misdescribes them. Meanwhile the new map adds synonyms that appear nowhere in
production (`lower_limit`, `upper_threshold`, `interval`, `between`,
`value_range`): the vocabulary was enumerated from this bug report rather than
derived from the extractor or the data. Remediation item 1 asked for one
canonical contract shared by extraction and normalization; the extractor side
is untouched, so the drift can recur.

A related, unaddressed instance of the same drift: `value_class` is matched
against a closed English enum (`observation`, `requirement`, `target`,
`reference`, `design_capability`, `definition`), but production emits free
text (`限量指标`, `标准符合性`, `实验参数`, `ratio`, `amplitude_threshold`, …).
Every lookup misses, so the requirement-vs-observation refinement is silently
inert. It fails safe — the base kind is kept — so it is not blocking.

**(d) The regression tests use idealized values, not production ones.**
`TestResolveMetricValueCanonicalizesExtractorRangeVariants` exercises
`exact_ratio` with `"3"` and `minimum` with `"30"`, and sets
`value_class = "requirement"`. The real corpus has `1:10`,
`每日（至少每日一次）` (no digits — still unparsed), `100（应分尽分）`,
`50 m³ 以下`, and Chinese `value_class` values. Remediation item 2 asked
specifically for the actual production values; `1:10` as a test case would
have caught (a).

### R2. Deferred recovery is correct, but untested

`AssociateSemantics.recoverDeferredCandidates` plus the widened
`DrainDeferredCandidates` — which now selects every `deferred` row rather than
only `unresolved_referent` — resolve Finding 2. Traced against the live rows:

- the 6 `no_governed_assertion_kind_term:exact_value` and the 3
  `governed_term_not_released:mea:measured_by,mea:lower_bound_requirement`
  candidates compute a differing availability fingerprint, so `RetryDeferred`
  reopens them and they proceed to accepted. ✅
- the 37 `no_governed_assertion_kind_term:unparsed` candidates are *not*
  recovered by this path (kind `unparsed` is skipped). They recover only
  because `normalize_assertions` runs before `associate_semantics` in Phase D
  and in the drain, producing a new payload revision. A bare
  `AssociateSemantics.Run` would not recover them.

Two caveats:

- The `unresolved_referent` branch has no gate: whenever any such candidate
  exists it calls `NormalizeAllFamilies` on **every** run. For record 416 that
  is 20 candidates re-normalizing all families indefinitely. The design's
  "records with unchanged dependencies make no changes" does not hold for this
  class.
- `recoverDeferredCandidates` — the entire mechanism this finding turns on —
  has **no test coverage**. The design promised "SQL-mock tests will cover
  deferred term retry selection/fingerprints and associate runs that include
  reopened candidates"; the three tests added are pure-function unit tests
  over `metricAssertionKindTermID`, `metricQualifiers`, and
  `governedTermDependencyFingerprint`.

### R3. Subject-object reconciliation: unresolved, and the corpus is worse than Finding 3 reported

The implementation made no change here, on the stated grounds that fresh
processing already reconciles subjects. The live data contradicts this.

**All 20 unlinked metrics have a non-empty `metric_subject`, and none has a
`kb.artifact_objects` row at all** — this is not an ambiguity or
NULL-`object_id` case; the rows simply do not exist:

```sql
SELECT ao.reconcile_status, (ao.object_id IS NULL), count(*)
FROM kb.artifact_objects ao
WHERE ao.input_record_id = 416 AND ao.artifact_type = 'metric'
GROUP BY 1, 2;
--  matched | f | 28
--  new     | f | 18        (46 rows total; zero unresolved)
```

**The 46 rows that do exist are stale, and 45 of them are attached to the
wrong metric.** The object rows were written 2026-07-03; all 66 `kb.metrics`
rows were written 2026-08-12 17:07. The normalizer joins on
`artifact_id = metric_id`, and `metric_id` is positional (`416_mtc_N`), so
July's objects silently re-attach to August's metrics by index — which is why
the split is contiguous (`416_mtc_1`…`_46` linked, `_47`…`_66` not):

| `metric_id` | metric | `metric_subject` | linked `object_name` |
|---|---|---|---|
| `416_mtc_4` | 有机质的质量分数 | 肥料 | 机器成肥设备 |
| `416_mtc_7` | 总砷（As） | 肥料 | 农村户用沼气池 |
| `416_mtc_9` | 总铅（Pb） | 肥料 | 渗滤液预处理出水 |
| `416_mtc_12` | 垃圾分类准确率 | 村民委员会 | 微生物菌种 |

Only 1 of the 46 links has `metric_subject = object_name`.

**Root cause.** `MetricsProcessor.persistMetricObjects` has exactly one call
site — `extract-metrics.go:708`, in the legacy non-batch `HandleEvent` path.
The live chunk-batch path (`InitChunkBatch` / `ProcessChunk` /
`FinalizeChunkBatch`, in both the `force_clear` and the merge branch) never
calls it, so metric subject reconciliation does not run at all on the current
pipeline. This is an omission rather than a design choice:
`ProvisionsProcessor.FinalizeChunkBatch` *does* call `persistProvisionObjects`
(`extract-provisions.go:2163`).

**Consequences.**

1. The 20 `unresolved_referent` candidates will never recover. The recovery
   path re-normalizes, the payload is unchanged (still no
   `subject_object_id`), `Propose` returns `Reused`, and the candidate stays
   deferred forever.
2. Reprocessing record 416 now yields roughly **29 accepted assertions**
   (12 exact + 10 lower-bound + 7 upper-bound among the linked rows) — and
   nearly all of them assert the metric against the **wrong subject object**.
   Before this change those candidates were deferred, i.e. safely blocked. The
   pipeline moves from "does not converge" to "converges on wrong data", which
   inverts the acceptance criterion rather than satisfying it.

**Required before this bug can be closed:** persist metric objects from
`MetricsProcessor.FinalizeChunkBatch` (matching the provisions processor), and
delete or rebuild the stale `kb.artifact_objects` metric rows for record 416
before reprocessing. Reconciliation must be keyed to the extraction run that
produced the metrics, not to positional `metric_id` reuse across runs.

### R4. Metric identity propagation — fixed

`metric_definition_term_id` is selected in the normalizer query, written into
the candidate payload when non-empty, carried on `metricCandidatePayload`, and
emitted into the accepted assertion's `qualifiers`. Both hops have tests. The
decision to use `qualifiers` rather than a new column is documented in the
design; no migration needed.

### R5. Assertion-kind allowlist — fixed

`governedMetricAssertionKinds` is gone. `metricAssertionKindTermID` rejects
only empty and `unparsed`; everything else is gated by `termExists` against
`kb.ontology_terms.status = 'included_in_release'`. Verified that
`mea:exact_value`, `mea:measured_by`, `mea:lower_bound_requirement`,
`mea:upper_bound_requirement`, `mea:interval_requirement` and
`mea:observed_value` are all released. The reachable kind set is bounded by
`structuredValueAssertionKind` ∪ `valueClassAssertionKind` ∪ the parser
constants, so removing the allowlist widens acceptance by `exact_value` only.

Residual: the stale comment this finding called out is still present in
`metric_normalizer.go`, above `structuredValueAssertionKind` — it still reads
"exact_value is included even though no governed mea:exact_value term is
seeded yet". It should be removed.

### R6. Telemetry — counters fixed, alerting not implemented

`AssociationRunReport.DeferredByReason` buckets deferred candidates by
`dependency_fingerprint`, and `phase_d.go` logs it per run, satisfying the
acceptance criterion. The second half of remediation item 7 — "alert when a
normally supported metric corpus has a high deferred rate" — is not
implemented; the report is logged at `Info` with no threshold.

The bucketing key is `dependency_fingerprint`, so the degenerate reasons noted
in R1(c) surface verbatim: the 7 `qualitative` rows produce an empty-suffixed
`no_governed_assertion_kind_term:` because their assertion kind resolves to the
empty string.

### Projected outcome of reprocessing record 416 as the code stands

| Bucket | Count | Outcome |
|---|---:|---|
| Linked + parses (exact / lower / upper) | 29 | accepted — **wrong subject on ~28** |
| No `kb.artifact_objects` row | 20 | deferred `unresolved_referent`, permanently |
| Unmapped `value_range_type` | 12 | deferred `unparsed` |
| `range` (no `value_min`/`value_max`) | 2 | deferred `unparsed` |
| Empty `value_range_type` → free text | 3 | depends on `threshold_or_target` |

### Recommended order of work

1. Fix R3 — persist metric objects from `FinalizeChunkBatch`, purge the stale
   record-416 object rows. **Blocking**: without it, reprocessing writes wrong
   accepted assertions.
2. Fix R1(a) — handle ratio notation in the structured `exact` path, or drop
   `exact_ratio` from the `exact` mapping until it can be represented.
3. Fix R1(b) — parse `metric_value` in the `range` branch, or make the
   extractor populate `value_min`/`value_max`.
4. Add sqlmock coverage for `recoverDeferredCandidates` (R2) and rewrite the
   canonicalization tests against the real record-416 values (R1(d)).
5. Remove the stale `structuredValueAssertionKind` comment (R5).

## Review follow-up implementation (2026-08-13)

Implemented the review-required source corrections in the follow-up ChenWeb
change after commit `406a`:

- `MetricsProcessor.FinalizeChunkBatch` now rebuilds the complete metric
  `kb.artifact_objects` snapshot after both force-clear saves and merge-mode
  upserts. This matches the provision batch path and ensures that reprocessing
  record 416 deletes the stale July metric-object rows before writing object
  links for the August metric extraction.
- The extraction path and normalizer now share the exported
  `CanonicalMetricValueRangeType` contract; new persisted metric rows use the
  canonical vocabulary while normalization remains compatible with historical
  rows.
- Structured `range` metrics parse populated `metric_value` text when the
  extractor has not supplied `value_min`/`value_max`, including the live forms
  `5.5~8.5` and `0℃～4℃`.
- Structured `exact_ratio` values such as `1:10` no longer accept the first
  number as an exact scalar. They remain `unparsed` until a governed ratio
  representation is introduced.
- Deferred referents are re-normalized only after an actual resolved
  `kb.artifact_objects.object_id` exists, avoiding unbounded no-op retries.
- Phase-D telemetry now emits a warning when at least half of examined
  candidates remain deferred, alongside its reason counters.

Regression tests cover the live ratio and range forms, the batch object
snapshot rebuild, and the resolved-object recovery gate. The focused
assertions and document-processing test suites pass. Record 416 must be
reprocessed after deployment to rebuild its stale object links and then
regenerate semantic assertions; that operational database mutation was not
performed as part of the source change.

## Review of the follow-up implementation (2026-08-13)

Reviewed commit `a5b1b83` (`Fix reviewed metric semantic convergence gaps`)
against the source tree, ran `go test -count=1
./server/api/ontology/assertions/... ./server/api/doc-processing/...`
(passes), and drove the real `resolveMetricValue` function -- not a
reimplementation of it -- against both all 66 of record 416's current
`kb.metrics` rows and every `range`-family row in the whole database with a
colon in `metric_value`.

| Follow-up claim | Verdict | Detail |
|---|---|---|
| Batch metric-object snapshot rebuild (R3) | **Fixed** | F1 |
| `exact_ratio` no longer fabricates a scalar (R1a) | **Fixed** | F2 |
| `range` parses `metric_value` when endpoints are absent (R1b) | **Fixed for clean two-number ranges; reopens fabrication for compound text** | F3 |
| Unbounded re-normalization on `unresolved_referent` (R2 caveat) | **Fixed** | F4 |
| High-deferred-rate telemetry warning (R6) | **Fixed** | F5 |
| Record 416 itself | **Still not reprocessed; stale wrong-subject links are still live** | F6 |

### F1. Metric-object snapshot rebuild -- fixed

`MetricsProcessor.FinalizeChunkBatch` now calls the new
`persistCurrentMetricObjects` after both the force-clear `SaveMetrics` call
and the merge-mode upsert call. That method loads the record's current
`kb.metrics` rows and calls the pre-existing `persistMetricObjects`, which
ends in `ArtifactObjectSQLStore.ReplaceObjectsForRecord`
(`artifact_objects.go:399`) -- confirmed to run inside a transaction as a
real `DELETE FROM kb.artifact_objects WHERE source_record_id = $1 AND
artifact_type = $2` followed by fresh `INSERT`s (`artifact_objects.go:408`),
not an additive upsert. `MetricsProcessor.ObjectStore` and
`.ObjectReconciler` were already wired for the pre-existing non-batch
`HandleEvent` path (`extract-metrics.go:556-561`); the fix only needed the
two new call sites, so there is no remaining wiring gap.

### F2. `exact_ratio` fabrication -- fixed

`resolveMetricValue`'s `exact` case now breaks to `unparsed` whenever
`metric_value` contains `:`, before `firstParseableNumber` runs. Verified:
`vrt=exact_ratio, metric_value="1:10"` produces `ValueForm=unparsed`,
`NumericValue=nil` against the live function, matching
`TestResolveMetricValueProductionRatioDoesNotFabricateScalar`.

### F3. `range` fallback reopens value fabrication on compound production text -- new, unaddressed

The new range fallback (`metric_normalizer.go`, `case "range"`) reuses
`parseThresholdOrTarget` on `metric_value` when `value_min`/`value_max` are
NULL. `parseThresholdOrTarget` was written to extract a single number
adjacent to a comparator, or two numbers around a lone range separator, from
free text -- it has no notion of "this text is one coherent range statement
and nothing else." Feeding it real `range`-typed `metric_value` strings
pulled from the whole `kb.metrics` table (not record 416 alone) produces
fabricated intervals:

| Record | `metric_value` | Actual meaning | Result |
|---|---|---|---|
| `244_mtc_88` | `白天6:00～22:00; 夜间22:00～次日6:00` | a day/night collection-time schedule | **fabricated** `interval_requirement`, lower=**0**, upper=**22** -- the "00" minutes from "6:00" and the "22" hour from the second timestamp, not a real interval |
| `365_mtc_148` | `I级: <30; II级: 30~40` | a two-tier classification | **fabricated** interval 30-40; the "Tier I: <30" clause is silently discarded |
| `365_mtc_149` | `I级: <10; II级: 10~20` | same pattern | fabricated interval 10-20 |
| `365_mtc_150` | `I级: <15; II级: 15~20` | same pattern | fabricated interval 15-20 |

These are the same class of defect F2/R1(a) fixed for `exact_ratio` --
`resolveMetricValue`'s documented "never fabricates a value" invariant is
violated again, just relocated to the `range` branch. Two colon-bearing
`range` rows in the same scan (`244_mtc_4`: `6:00-22:00`, `244_mtc_6`:
`22:00-06:00`) correctly stay `unparsed`, because the unspaced ASCII hyphen
does not match either range regex -- so the failure mode is specifically
range separators (`~`/`～`/Chinese dashes) appearing inside text that is not
actually a single range statement, not every colon-bearing string.

The new regression test, `TestResolveMetricValueProductionRangeParsesMetricValue`,
only covers the two clean cases (`5.5~8.5`, `0℃～4℃`) already named in the
prior review. It does not include either fabricating pattern found here, even
though both are real, currently-persisted corpus rows -- the same
idealized-test-data gap the prior review's R1(d) raised for the `exact_ratio`
fix.

This must be fixed (or the `range` fallback narrowed to reject multi-clause
text) before any record with this shape can be safely reprocessed.

### F4. Unbounded re-normalization on `unresolved_referent` -- fixed

`recoverDeferredCandidates` now calls the new
`metricSubjectObjectLinked` (`associate_semantics.go:194`) before setting
`needsRenormalization`, so an `unresolved_referent` candidate only triggers
`NormalizeAllFamilies` once its `kb.artifact_objects` row actually has a
non-blank `object_id`. Verified against live record 416: all 20 genuinely
unresolved metrics (`416_mtc_47`..`416_mtc_66`) currently have no
`artifact_objects` row at all, so `metricSubjectObjectLinked` returns `false`
for each and `needsRenormalization` stays `false` -- the prior review's
"every run re-normalizes all families indefinitely" caveat no longer holds.

One narrowing worth noting: the loop now `continue`s immediately for any
`unresolved_referent` row whose `artifactType != "metric"`, where before it
unconditionally re-normalized regardless of family. No current family other
than `metric` produces `unresolved_referent` (provisions defer under
`no_governed_deontic_predicate`), so this is not live today, but a future
family that reuses that fingerprint would silently stop being retried by this
path.

### F5. High-deferred-rate telemetry warning -- fixed

`phase_d.go` now logs a `Warn` when `LifecycleCounts[StatusDeferred] * 100 >=
ArtifactsExamined * 50`, i.e. at least half of examined candidates are
deferred, with the reason breakdown attached. Record 416 today is 66/66
deferred and would trigger it.

### F6. Record 416 has not been reprocessed; running association on it today would still write wrong-subject assertions

The fixes are code-complete, but nothing has re-run metric extraction for
record 416, so its `kb.artifact_objects` rows are still the same stale,
positionally-misattached July rows F1/R3 described. Driving the live
`resolveMetricValue` against all 66 of record 416's actual current rows,
including their current (stale) object links, produces:

- 30 candidates resolve to a populated `AssertionKind` (10
  `lower_bound_requirement`, 11 `exact_value`, 7 `upper_bound_requirement`, 2
  `interval_requirement`) **and** currently show `linked=true` because rows
  `416_mtc_1`..`416_mtc_46` still carry last month's object links.
- If `associate_semantics` were run against record 416 right now -- without
  first re-running metric extraction to rebuild the object snapshot -- all 30
  would be accepted against the wrong subject, reproducing the exact hazard
  F1/R3 exists to prevent.

Rebuilding the object snapshot only happens inside metric extraction
(`HandleEvent` / `FinalizeChunkBatch`); re-running `normalize_assertions` or
`associate_semantics` alone on the existing `kb.metrics` rows does not touch
`kb.artifact_objects`. The order matters: record 416 must go through metric
extraction again first, and association only after that completes.

### Recommended order of work

1. Fix F3 -- reject or otherwise guard multi-clause/compound `metric_value`
   text in the `range` fallback before it can produce a fabricated interval.
   **Blocking**, for the same reason F2 was blocking: an accepted assertion
   with a wrong number is worse than a deferred candidate.
2. Add regression coverage using `244_mtc_88` and `365_mtc_148`-`150`
   verbatim, not idealized substitutes.
3. Re-run metric extraction for record 416 to rebuild its object snapshot,
   *then* run normalization/association -- never the reverse order.
4. Re-verify record 416's final candidate/assertion counts against corrected
   `range` handling once F3 is fixed.

## Second follow-up implementation (2026-08-13)

The F3 blocker is fixed in ChenWeb commit `5b5f` (`Reject compound metric
range assertions`). The structured range fallback now accepts only an entire
two-number range expression after removing unit markers; it no longer reuses
the free-text parser to extract a range-shaped substring from a compound
statement. Regression coverage uses the reviewed production values verbatim:

- `白天6:00～22:00; 夜间22:00～次日6:00`
- `I级: <30; II级: 30~40`
- `I级: <10; II级: 10~20`
- `I级: <15; II级: 15~20`

All remain `unparsed` with no numeric bounds. Clean standalone ranges
(`5.5~8.5`, `0℃～4℃`) remain accepted as intervals. Focused assertion and
document-processing suites pass.

The remaining record-416 task is an operational reprocessing run: execute
`extract_metrics` first so the transactional snapshot rebuild removes the
stale artifact-object links, then run normalization and association. It is
intentionally not replaced by a direct association run, which would still be
unsafe until extraction completes.

## Review of the second follow-up implementation (2026-08-13)

Reviewed commit `5b5f393` (`Reject compound metric range assertions`) against
the source tree, ran `go test -count=1 ./server/api/ontology/assertions/...
./server/api/doc-processing/...` (passes; one unrelated concurrency-bound
doc-processing test flaked once under combined-package load and cleared 3/3
on retry in isolation -- not touched by this diff), and drove the real
`resolveMetricValue`/`parseThresholdOrTarget` functions -- not
reimplementations -- against all 654 `range`-family rows in `kb.metrics`
across the whole database, diffing old (`a5b1`) vs. new (`5b5f`) output
row by row.

| Second follow-up claim | Verdict | Detail |
|---|---|---|
| F3 fixed: range fallback rejects compound/multi-clause text | **Fixed, and broader than the four cited cases** | G1 |
| Clean standalone ranges remain accepted | **True for `℃`-style ranges; narrower unit coverage than the prior implementation for others** | G2 |
| Record 416 needs an operational reprocessing run | **Confirmed accurate against live DB state** | G3 |

### G1. Compound-range fabrication -- fixed, and generalized well beyond the four originally cited rows

`reWholeRange` (`metric_normalizer.go:191`) anchors with `^...$`, so
`case "range"` (`metric_normalizer.go:276`) now accepts a `metric_value` only
if the *entire* string (after `℃`/`°C`/`°` stripping) is one
number-separator-number expression -- no more extracting a range-shaped
substring out of surrounding text. Comparing old vs. new across all 654
`range`-family rows in the database:

- Zero rows where the new code still fabricates an interval, or produces
  different endpoints than the old code for a row both accept.
- Zero rows where the new code accepts something the old code rejected.
- All four originally-cited fabrication rows (`244_mtc_88`, `365_mtc_148`,
  `365_mtc_149`, `365_mtc_150`) now correctly return `unparsed`, matching
  `TestResolveMetricValueProductionCompoundRangesRemainUnparsed`.
- The anchor also catches roughly 50 *other* compound rows never named in the
  report, spanning records 246, 356, 358, 366, 372, 373, 384, and 386 --
  scoring rubrics (`≤50 (得5分); 50~55 (得2分)`), multi-tier size classes
  (`特大型40001~80000, 大型20001~40000, ...`), point-estimate-plus-CI pairs
  (`1.30 (1.11~1.53)`), and dual-unit duplicates
  (`20 - 60 mmHg (2.7 - 8.0 kPa)`). It incidentally also fixes two latent
  bugs in the pre-`5b5f` free-text range parser that were not part of this
  finding: an inverted range (`373_mtc_24`: `32~26 (240~195)`, previously
  lower=32 > upper=26) and a fraction misread
  (`371_mtc_283`: `1/2~2/3`, previously parsed as the degenerate lower=2,
  upper=2). The anchored-whole-string approach is a more principled fix than
  a patch scoped to the four cited strings would have been.
- Record 416's own two range rows (`5.5~8.5`, `0℃～4℃`) still resolve to
  `interval_requirement` as before.

### G2. Unit-stripping is narrower than the prior implementation, so some clean single ranges now defer that previously didn't

The pre-match cleanup only strips `℃`, `°C`, and `°`
(`metric_normalizer.go:283`). Any other trailing/leading unit text now fails
the whole-string anchor even when the underlying value is a clean,
unambiguous single range with no compound-text risk. Confirmed live examples,
all correctly accepted before `5b5f` and incorrectly deferred as `unparsed`
after it:

| Record | `metric_value` | Why it's safe |
|---|---|---|
| `223_mtc_13` | `0.98~196.1kPa` | one range, one trailing pressure unit |
| `363_mtc_6` | `5～10分钟` | one range, one trailing duration unit |
| `365_mtc_134` | `3300~5300K` | one range, one trailing temperature unit |
| `383_mtc_10` | `100—200ml` | one range, one trailing volume unit |
| `389_mtc_388` | `1310~2460 m^2` | one range, one trailing area unit |
| `357_mtc_72` | `1至2个月` | one range, one trailing Chinese duration unit |

This is a completeness regression, not a correctness bug -- these rows defer
(fail safe) rather than accept anything wrong, and none of them affect record
416, whose two range rows use only `℃`. Non-blocking, but worth a follow-up
to strip a general trailing/leading unit token rather than a fixed three-item
replacer list.

### G3. Record 416 remains unreprocessed -- confirmed against live data

```sql
SELECT status, dependency_fingerprint, count(*)
FROM kb.semantic_decision_candidates
WHERE input_record_id = 416 AND source_artifact_type = 'metric'
GROUP BY 1, 2 ORDER BY 3 DESC;
```

Still exactly the same four `deferred` buckets (37/20/6/3) as every prior
review in this document, and `kb.semantic_assertions` joined to
`kb.assertion_evidence` for record 416 is still empty. The claim that only an
operational reprocessing run remains is accurate as of this review.

### Recommended order of work

1. Reprocess record 416: run `extract_metrics` to rebuild the object
   snapshot, then normalization and association -- per the design already
   stated above. **This is now the only step blocking closure of the
   original bug.**
2. (non-blocking, optional) Broaden the range fallback's unit-stripping past
   `℃`/`°C`/`°` so the rows in G2 are recovered rather than left deferred.
3. Once record 416 is reprocessed, re-run the acceptance-criteria checks
   against its actual `kb.semantic_assertions` output and close the bug if
   they hold.
