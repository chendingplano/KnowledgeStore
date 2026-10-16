# extract_metrics conditions — every metric row now says when, where, for whom or how its value holds

**Date:** 2026-10-16 \
**Scope:** What a metric's *condition* is, how `extract_metrics` fills and uses it, and the value
clean-ups added with it. Open this when a metric row's condition looks wrong, when two rows seem to
be duplicates, or when comparing scores from before and after this change.
**Code root:** `ChenWeb/server/api/doc-processing` (`extract-metrics.go`, `metric_value_notation.go`,
`metrics_merge.go`)

**Traceability — openspec:**
- `ChenWeb/openspec/changes/extract-metrics-conditions/proposal.md` — why this exists
- `ChenWeb/openspec/changes/extract-metrics-conditions/design.md` — rationale, alternatives
  considered, risks/trade-offs
- `ChenWeb/openspec/changes/extract-metrics-conditions/tasks.md` — implementation log,
  including anything not independently verified
- `ChenWeb/openspec/changes/extract-metrics-conditions/specs/` — `metric-condition`,
  `metric-value-notation` and `metric-row-granularity`; after the change is archived they live
  under `ChenWeb/openspec/specs/`. **Update these spec files, not just this doc, if behavior
  changes** — this doc explains the feature for humans and points at code; the specs are the
  contract for agents.

## Summary

A standard often gives the same kind of number several times for different situations: one height
range for preschool children and another for adults, one tolerance for loads up to 50 kg and
another above, the same test settings once with a simulation device and once with a simulant
object. The number alone does not say which situation it belongs to. That situation is the
metric's **condition**: who or what the value is for, the environment or operating state, the test
method or apparatus, the body site or part, the load or time point.

The database had a place for the condition since August 2026, but the document processor never
filled it: 0 of 2,383 stored metrics had one. The extracting model worked around the gap by
writing the condition into the object's name ("height tester (preschool children)") or by putting
several values into one row ("male 300 mm, female 250 mm"). Rows that differed only in their
condition could also be merged by mistake.

Now:

- every metric row carries its condition in the document's language and in English, written as
  labelled parts such as `适用人群：幼儿；称量≤50 kg`;
- the object field names only the object;
- two rows that differ only in their condition are always kept as two metrics;
- each row holds one value, so "male 300, female 250" becomes two rows with conditions male and
  female.

The same change cleans up how values are stored:

- a `±2 mm` tolerance is an upper limit on the deviation;
- the value field no longer repeats the unit or the "≥" sign;
- ranges carry their two end numbers;
- tables of example data (such as a list of simulated test subjects) are no longer turned into
  metrics.

On record 371 (GB/T 44700—2024), the first run after the change filled a condition on 410 of 483
rows. It removed all unit repeats, wrong tolerance comparators, merged values and example-data rows.

The answer key and the scoring tool changed with it. Gold rules version 6.4.0 defines conditions
the same way. The `score-extract-metrics` score now includes a condition check, so scores from
before 2026-10-16 (scoring version 1) cannot be compared with newer ones (scoring version 2).

## Where things live

- **Prompts:** `ChenWeb/prompts/prompt-extract-metric-candidates-v16.md` (finding candidates, with
  a condition hint), `prompt-enrich-metrics-v13.md` (the "Conditions" and "One Value Per Row"
  sections) and `prompt-merge-resolve-metrics-v2.md` (a different condition is a different metric).
  They are the defaults in code and in `mise.local.toml`.
- **Database:** `kb.metrics.condition`, `condition_en` (new, migration
  `20261016000001_add_kb_metrics_condition_en.sql`), `value_min`, `value_max`.
- **Value clean-up:** `metric_value_notation.go` (`normalizeMetricValueNotation`). Rows that still
  hold several values are listed in `kb.doc_proc_logs` under the activity `multi_value_rows`.
- **Duplicate checks:** `dedupeFinalMetricRows` in `extract-metrics.go`, and `metricsIdentical` /
  `metricStaticMatch` in `metrics_merge.go`. All of them compare the condition.
- **Pages:** the metric details panel (Metrics workspace and Product Review "Full Details") shows
  Condition and Condition (English) for production and gold metrics, the side-by-side
  production/gold comparison shows both, and the metric wiki infobox shows the condition in the
  page's language. The metrics API returns and accepts `condition` / `condition_en`.
- **Answer key and scoring:** `.agents/skills/extract-metrics-benchmark/rules/6.4.0.md` (§3,
  Conditions), `testbed.metrics.condition_en` (migration `20261016000002`, required by the
  benchmark tooling from rules 6.4.0 for a non-English condition), and
  `.agents/skills/score-extract-metrics` (condition check, weights in `score.json`). The in-app
  scorer uses the matching prompt `prompt-score-extract-metrics-v2.md`.

## Known limitations

- Existing rows were not backfilled. A document gets conditions the next time `extract_metrics`
  runs on it.
- The model sometimes adds a qualifier the source doesn't state. On record 371 it repeated the
  property as a "location" (`测量部位：座板高度` on the seat-height resolution row), and it carried
  the first clause's apparatus into the parallel clause 6.5.14.2. The scorer counts these as
  condition errors.
- Splitting a row that holds several values is left to the model. The code only reports such rows;
  it never splits them itself.
- Fraction ranges such as `1/2~2/3` get no numeric end points.
- The scorer compares only the source-language condition; `condition_en` is shown but not scored.
- A metric wiki page generated before this change keeps its old infobox, with no condition, until
  it is refreshed.
- Gold runs made before rules 6.4.0 have no `condition_en`.
