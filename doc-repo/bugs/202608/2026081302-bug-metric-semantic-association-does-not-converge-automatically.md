# Metric semantic association does not converge automatically after document processing

Date: 2026-08-13

Status: open

System: `ChenWeb` document processing / SemOS semantic assertion pipeline

Component: `extract_metrics`, metric identity resolution, `normalize_assertions`,
`associate_semantics`, deferred-candidate recovery, artifact-to-object reconciliation

Input record: `416` (`std_1503937.pdf`)

Related: [Metric Assertions and Semantic Processing manual](../../user-manuals/metric-assertion-semantic-processing-v1.1-en.md),
[production measurement-vocabulary bootstrap bug](2026081301-bug-production-semantic-association-missing-measurement-vocabulary.md),
`ChenWeb/server/api/ontology/assertions/{metric_normalizer.go,associate_semantics.go,backlog_drain.go}`.

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
automatically. The observed result is caused by two confirmed automation bugs
and two implementation gaps.

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
| `no_governed_assertion_kind_term:exact_value` | 6 | The candidate was processed before `mea:exact_value` became available. |
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
`deferred`.

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
4. Ensure every association-eligible metric gets an automatic subject-object
   reconciliation attempt before normalization/association.
5. Carry `metric_definition_term_id` from `kb.metrics` into the semantic
   candidate and accepted assertion model, or explicitly revise the design to
   state that metric identity is not part of semantic assertions.
6. Emit per-run counters by defer reason and alert when a normally supported
   metric corpus has a high deferred rate.

## Acceptance criteria

- Reprocessing record 416 after the fixes creates accepted metric assertions
  and corresponding `kb.assertion_evidence` rows without a human edit.
- `min`/`max` values such as `≥30` and `≤30` normalize as lower/upper bound
  requirements.
- Candidates deferred solely because their required terms were unreleased are
  retried and accepted after those terms are released.
- Every metric with a usable extracted subject is automatically linked to a
  valid object or is reported with an explicit, actionable reconciliation
failure.
- Operational output reports candidate counts by status and deferral reason
for each document-processing run.

