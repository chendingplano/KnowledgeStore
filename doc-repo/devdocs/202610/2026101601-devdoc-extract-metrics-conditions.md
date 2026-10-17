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

- a bare `±2 mm` tolerance is an upper limit on the deviation, while a centred tolerance such as
  `65±5 mm` is a range from 60 to 70 mm even if the model labels it an upper bound;
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

- **Prompts:** `ChenWeb/prompts/prompt-extract-metric-candidates-v25.md` (finding candidates, with
  a condition hint), `prompt-enrich-metrics-v23.md` (the "Conditions" and "One Value Per Row"
  sections) and `prompt-merge-resolve-metrics-v2.md` (a different condition is a different metric).
  They are the defaults in code and in `mise.local.toml`.
- **Database:** `kb.metrics.condition`, `condition_en` (new, migration
  `20261016000001_add_kb_metrics_condition_en.sql`), `value_min`, `value_max`.
- **Value clean-up:** `metric_value_notation.go` (`normalizeMetricValueNotation`).
  `metric_multi_value_recovery.go` retries candidates whose values combine several numbers,
  using the original evidence. For example, `20%、80%及中间区段任意2~3个` becomes two percentage
  positions and a separate count of intermediate points. The code accepts replacements only
  when they retain the original numbers and supporting lines; failed retries preserve the
  original rows. Rows still holding several values are listed in `kb.doc_proc_logs` under
  the activity `multi_value_rows`.
- **Clause-wide qualifiers:** `inheritClauseConditions` in `metric_value_notation.go` copies a
  clause's `试验装置` / `试验方法` / `试验介质` qualifier to the rows of that clause that lack it. It
  does so only when the clause's rows agree on one value and the clause's opening line names it.
  Rows from table lines are left alone.
- **Duplicate checks:** `dedupeFinalMetricRows` in `extract-metrics.go`, and `metricsIdentical` /
  `metricStaticMatch` in `metrics_merge.go`. All of them compare the condition. Reordering or
  repeating the same labelled qualifiers does not create another identity. Different labels or
  qualifier values remain distinct.
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
- Splitting combined values needs model judgement. The code retries once per affected candidate
  evidence group and preserves originals if the retry fails validation. Its conservative checks
  may reject equivalent numeric rewrites; unresolved rows remain available for review.
- Fraction ranges such as `1/2~2/3` get no numeric end points.
- The scorer compares only the source-language condition; `condition_en` is shown but not scored.
- A metric wiki page generated before this change keeps its old infobox, with no condition, until
  it is refreshed.
- Gold runs made before rules 6.4.0 have no `condition_en`.

## Improving extraction after the record 371 review

The comparison against gold run `20261016_085615` (rules 6.4.0, claude-opus-5-5) scored the
previous candidates-v17/enrich-v14 output at 93/100 using scoring version 2. It matched 469 of
474 gold assertions. Most field mismatches concerned conditions; the two 80 mm loading widths
and the 0.1% grip-test dynamometer accuracy were missing as independent metrics.

The saved run-220 candidate logs explain two different failures. The widths and grip-test
accuracy appeared inside other candidates' condition hints without becoming candidates. The
adult beat-error candidate was present with the correct population; the saved final rows had
only the student assertion. A stopwatch-error candidate on line 271 appeared only in the next
chunk's overlap, which cannot rescue a miss on the normal source line.

The current prompts audit dense clauses for embedded settings, keep each table population tied
to its own row, name the parent property of generic resolution/error columns, and keep a
clause's apparatus on every setting it governs. Numeric dimensions and accuracy get separate rows.
(Until enrich v19 the apparatus qualifier also kept its qualitative capabilities; see the next
section.) Product specifications and
acceptance criteria are distinguished from the setup used to test them. An instruction to
adjust a knob after a reading exceeds a trigger does not create a second acceptance limit.

The Go normalizer repairs the unambiguous `a±b` comparator error and clears endpoints on
non-range numeric rows. It does not guess missing metrics, infer populations, or reclassify
assertions from domain-specific keywords. Those decisions remain in the extraction prompts.

`server/api/doc-processing/metric_extraction_quality_test.go` provides an opt-in real-model
check for representative clauses from this review. It exercises both extraction passes, checks
the missing settings, distinct populations/methods, classification, tolerances and adjustment
exclusion, and keeps returned metrics out of the database:

```sh
mise exec -- env METRIC_QUALITY_LIVE=1 \
  METRIC_QUALITY_OUTPUT=/tmp/metric-quality.json \
  go test ./server/api/doc-processing -run '^TestMetricExtractionQualityLive$' -count=1 -v
```

Run this from ChenWeb. The ordinary suite skips the model calls. These focused checks do not
replace re-extracting and scoring the full document against the same gold run. Existing
`kb.metrics` rows and gold metrics are not rewritten by these fixes.

Verification on 2026-10-16: all six live cases passed with the configured deepseek-flash model,
returning 27 metrics and satisfying 16 expected assertions plus adjustment-trigger exclusion.
The ordinary processor/handler suites passed (1,729 checks, four skips), along with `go vet`,
the doc-processor build and strict validation of the OpenSpec change. An initial run under the
full mise environment exposed unrelated environment-dependent suite failures; the ordinary
suite passes without those production overrides. No new full-document score is claimed.

## Matching the gold's condition conventions (2026-10-17)

Run 226 (candidates v21 / enrich v19) found 503 of the 512 rows of gold run `20261016_162743`
(rules 6.6.0, gpt-6.1-sol) with no false positives, but only 53.7% of the pairs had the right
condition. Most of the 234 failures were not model mistakes:

- About 76 followed the prompt, which asked for a different form than the gold uses. The prompt
  kept an apparatus's capabilities in its qualifier (`运动模拟装置（可触动运动起点…）`), named
  resistor rows `RA阻值` with only `模型：模型 1`, and added `取值区段：量程中间区段`.
- About 85 left out a qualifier that the clause states once for all its rows: the 6.5.7 gas-flow
  standard and its air medium, the 5 等量块 named in 6.5.4.1 for the checks in 6.5.4.2, the
  apparatus in 6.5.5.3 and 6.5.20.1, the method column of Table C.1, and the 耐久性 exemption.
- About 25 were inconsistencies in the gold itself, mostly the parallel 5.4.3 loading clauses.

The user decided to follow the gold. Candidates v22 and enrich v20 now ask for:

- the apparatus by name only, keeping a grade or alternatives that are part of the name
  (`5等量块`, `脉搏标准测试仪或等同准确度的脉冲信号发生器或频率计`). Accuracy and capabilities are left out;
- a table cell's column label in the condition (`模型：模型 1；电阻位置：RA`, name `电阻阻值`);
- the part a clause checks as `检验项目：计时装置`;
- no `取值区段` qualifier;
- `适用条件：…` for exemptions and stated exceptions.

`inheritClauseConditions` then copies the clause-wide apparatus or method in code. Replayed on the
run-226 rows, it changed 9 rows, all toward the gold. Copying from any row in the clause had also
spread one list item's method across the other items of 5.4.3. That is why the value has to appear
in the clause's opening line.

The scorer now treats dash variants as equal in conditions (`GB/T 19851.21—2007` vs `-2007`).
The scoring agent is reminded to override a condition that states the same qualifiers in other
words.

The gold inconsistencies are fixed in a corrected copy, run `20261017_060405` (6.6.0 /
claude-opus-5-5). It has the same ledger and rows and changes 24 rows in 5.4.3.3, 6.4.2.3, 6.4.2.6
and Table C.1. Each list item's equipment category is now a condition (`器材类别：…`) rather than part
of the subject, and every row of an item carries all the qualifiers the item states. The change
log is in the run's `correctness_review`. Score 371 against that run from now on.

Not done yet: a full re-extraction of 371 with v22/v20 and a new score. The doc-processor must be
restarted to load the new prompts.

