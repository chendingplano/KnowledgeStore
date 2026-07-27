# Bug (wrap-up): extract_metrics recall investigation — final state and disposition

Date: 2026-07-30\
Status: open, paused by decision (see Disposition)\
System: `ChenWeb` document processing / `extract_metrics`\
Component: `prompts/prompt-extract-metric-candidates-v{6,7,8,9}.md`, `prompt-enrich-metrics-v4.md`\
Related: [2026073001 — recall instability across identical calls](2026073001-bug-extract-metrics-recall-instability-across-identical-calls.md), [2026073002 — required-vs-best-effort coverage scoring](2026073002-bug-extract-metrics-required-vs-best-effort-coverage-scoring.md)

## Summary

This closes out a three-stage investigation into `extract_metrics` recall and
consistency, run entirely against one real, temperature-0, unmocked test document
(`doc:cn-gb-syn-9706-1-2020`) across 16 separate LLM calls spanning four prompt
versions. One root cause was found and fixed with high confidence (a scope-language
misclassification). A second was found, partially fixed, and left open (a heading
misclassification interacting with a genuine recall-consistency problem). A third —
clauses failing in correlated pairs across identical calls — was observed twice,
independently, and remains unexplained.

Per the user's decision on 2026-07-30, this line of investigation is being paused here
to move on to other work. This document exists so the next person (which may be the same
person, later) does not have to re-derive any of this from scratch.

## Timeline

| Version | Change | Resolution (limit_absent) | Alarm (upper_bound) | Contrast (range) |
|---|---|---|---|---|
| `v4`/`v2` (production baseline) | — | untested here; 2026073001 found the original 4/6/8/4 instability under `v6`/`v4`'s predecessor state | — | — |
| `v6` | broadened candidate recall to include qualitative statements; closed the `value_range_type`/`value_class`/`is_explicit_metric` vocabulary (2026073002's context) | 0/4 | 2/4 | 3/4 |
| `v7` | added a carve-out so "document does not specify limit for X" is extracted like a positive requirement | **4/4** — but the example was the literal test sentence (evaluation contamination, caught before trusting this result) | 2/4 | 4/4 |
| `v8` | rewrote the example with an unrelated property/wording to force generalization instead of pattern-matching | 3/4 (honest, credible) | 3/4 | 3/4 |
| `v9` | added explicit guidance that a heading-tagged line can still carry real normative content, especially in Chinese standards where clause numbers prefix the requirement itself | 4/4 | 3/4 | 3/4 |

Full per-run data for `v6` is in 2026073001/2026073002's appendices. `v7`/`v8`/`v9` runs
are records 25–28, 29–32, 33–36 respectively in `chenweb_test`; this document's own
appendix below has the complete extraction for `v9`, the version left in place.

## Root Causes Found

### RC1 — scope-language misclassification (resolution/limit_absent) — fixed

CN's resolution clause ("本标准未规定显示屏具体像素限值" — "this standard does not
specify a pixel limit") failed 4/4 under `v6` while the *same clause type*, phrased
differently, succeeded in ISO/EU/US ("X shall be determined by Y; no fixed value is
specified"). The candidate-extraction prompt's "do not extract... general statement of
purpose or scope" rule was catching CN's phrasing because the document, not the
property, is the sentence's grammatical subject. `v7`/`v8`/`v9` added an explicit
carve-out for this pattern. `v8`'s honest (non-contaminated) result — 3/4, then 4/4
under `v9` — confirms this is a real, fixed root cause, not a fluke of giving away the
answer.

### RC2 — heading misclassification interacting with recall consistency — partially addressed, not resolved

CN's alarm clause line ("6.3.2.2 视觉报警信号应在触发条件出现后 150 ms 内显示。") is
tagged `line_type: heading-4` by `static_analyzer`'s heading detector in **100% of 8
observations checked** — a numbered-clause prefix ("6.3.2.2") the same document's own
enterprise-standard sibling shows is *not* a reliable trigger for the same detector
(some numbered lines there are tagged headings, others aren't, with no pattern found on
inspection). The user's proposed root cause — this is a real, factual property of how
Chinese national standards number clauses, not a fixture defect to remove — was
confirmed, and the fix was placed in the extraction prompt (`v9`: "headings can contain
content") rather than in the fixture (removing the clause number, which would have made
the fixture less realistic).

Result: alarm went from 2/4 (`v6`, `v7`) to 3/4 (`v8`, `v9`) — real movement, but not a
solved problem. `v8` did not contain the heading-content fix and also scored 3/4,
so the improvement may be partly attributable to `v9`'s fix and partly to the same
noise floor RC3 describes; this investigation did not run enough trials to separate the
two cleanly.

### RC3 — correlated-pair clause failures — observed twice, unexplained, open

2026073001 first observed lines 3+4 (alarm, touch) succeeding or failing together in
4/4 of the original runs. This investigation's `v9` batch produced a second, independent
instance: lines 2+3 (contrast, alarm) both missing in the same run (record 34) while
both present in the other three. Two different clause pairs, two different prompt
versions, the same clustering signature. This is now the most interesting open question
from the whole investigation and was not pursued further — candidate hypotheses (chunk
composition, per-response attention/output-budget effects, correlated provider-side
noise on adjacent token spans) remain untested.

## Cumulative Reliability (16 real LLM calls, one document, four prompt versions)

| Clause | v6 | v7 | v8 | v9 | Cumulative (v6+v8+v9, excluding contaminated v7) |
|---|---|---|---|---|---|
| resolution | 0/4 | 4/4* | 3/4 | 4/4 | 7/12 = 58%, trending solved |
| alarm | 2/4 | 2/4 | 3/4 | 3/4 | 8/12 = 67% |
| contrast | 3/4 | 4/4 | 3/4 | 3/4 | 9/12 = 75% |

\* `v7`'s resolution result is excluded from the cumulative column; it is not trustworthy
evidence on its own (see RC1).

## What Was Solved

- The general qualitative-clause under-extraction and inconsistent shape problem
  (2026073002's context; `v6`'s contribution) — holds across all four subsequent
  versions without regression.
- RC1 (scope-language misclassification of `limit_absent` statements) — fixed with
  credible, non-contaminated evidence.

## What Remains Genuinely Open

1. RC2: alarm/contrast reliability plateaued at 67–75%, not solved. `v9`'s
   heading-content fix helped some; whatever remains is not yet explained.
2. RC3: the correlated-pair failure pattern, observed twice independently, with no
   hypothesis tested.
3. From 2026073002: whether a captured `best_effort` clause can itself be scored
   "wrong" (`coverage.go` currently only checks line coverage, not value correctness).
4. From 2026073002: whether `cl:ent-readability-1m` is correctly marked `best_effort`
   given it names a concrete "1 m" test distance unlike the other 18 clauses so marked.
5. `v9` has been validated on exactly one of the fixture's nine documents. It has not
   been run against the other eight, so there is no evidence yet on whether "headings
   can contain content" causes new false positives elsewhere (e.g. a genuine
   title-only heading getting misread as content because of this new instruction).

## Disposition

Per user decision (2026-07-30): this investigation is paused here to reallocate effort
to the rest of the framework. This is a deliberate stop, not an abandonment — every item
above is tracked and resumable, not forgotten.

**Recommendation, not yet acted on:** do not promote `v9`/`v4` to the production default
(`mise.local.toml` still pins `v4`/`v2`) until the full 9-document fixture is rerun under
it and shows no regressions, per open item 5 above. The evidence collected here is real
and encouraging, but it was gathered on a single, deliberately adversarial test document
chosen because it already exhibited every symptom under investigation — it is not yet a
broad validation.

## Appendix: Every Extracted Metric, `v9` Runs (Records 33–36)

Same shape as 2026073002's appendix, for the prompt version this investigation ends on.

Full field values below are from a direct query against `kb.metrics` for
`input_record_id IN (33,34,35,36)` (29 rows, `id` 154–182), not inferred from
`metric_name`. `threshold_or_target` is blank except where noted.

### Record 33 (perfect run)

| id | Line | metric_name | metric_subject | metric_value | metric_unit | value_range_type | is_explicit_metric | confidence |
|---|---|---|---|---|---|---|---|---|
| 154 | 1 | 清晰可辨识 | 关键参数 | (empty) | (empty) | qualitative | f | 0.95 |
| 155 | 1 | 清晰可见 | 显示亮度 | (empty) | (empty) | qualitative | f | 0.95 |
| 156 | 2 | 静态对比度 | 显示屏 | 500:1 至 2000:1 | ratio | range | t | 0.99 |
| 157 | 3 | 视觉报警信号显示时间 | 视觉报警信号 | 150 ms | ms | upper_bound | t | 0.99 |
| 158 | 4 | 操作反馈延迟 | 触控操作反馈 | (empty) | (empty) | qualitative | f | 0.80 |
| 159 | 5 | 像素限值 | 本标准 | (empty) | (empty) | limit_absent | f | 0.90 |

### Record 34 (the one imperfect run — contrast and alarm both missing)

| id | Line | metric_name | metric_subject | metric_value | metric_unit | value_range_type | is_explicit_metric | confidence |
|---|---|---|---|---|---|---|---|---|
| 160 | 1 | 关键参数清晰可辨识性 | 医用电气设备 | (empty) | (empty) | qualitative | f | 0.95 |
| 161 | 5 | 显示屏像素限值 | 显示屏 | (empty) | (empty) | limit_absent | f | 0.90 |
| 162 | 6 | 可读性 | 显示屏 | (empty) | (empty) | qualitative | f | 0.85 |
| 163 | 7 | 标记清晰度及功能正常性 | 标记 | (empty) | (empty) | qualitative | f | 0.85 |
| 164 | 8 | 关键参数清晰可辨识性 | 关键参数 | (empty) | (empty) | qualitative | f | 0.85 |

Lines 2 (contrast) and 3 (alarm) have no rows at all in this run — see RC3.

### Record 35 (perfect run)

| id | Line | metric_name | metric_subject | metric_value | metric_unit | value_range_type | is_explicit_metric | confidence | threshold_or_target |
|---|---|---|---|---|---|---|---|---|---|
| 165 | 1 | 清晰可辨识性 | 关键参数 | (empty) | (empty) | qualitative | f | 0.90 | |
| 166 | 1 | 显示亮度清晰可见 | 显示亮度 | (empty) | (empty) | qualitative | f | 0.90 | |
| 167 | 2 | 静态对比度 | 显示屏 | 500:1 ~ 2000:1 | ratio | range | t | 1.00 | 500:1 to 2000:1 |
| 168 | 3 | 视觉报警信号显示延迟 | 视觉报警信号 | 150 | ms | upper_bound | t | 1.00 | 150 ms |
| 169 | 4 | 触控操作反馈延迟 | 触控操作反馈 | (empty) | (empty) | qualitative | f | 0.90 | |
| 170 | 5 | 像素限值 | 显示屏 | (empty) | (empty) | limit_absent | f | 0.95 | |
| 171 | 6 | 可读性 | 显示屏 | (empty) | (empty) | qualitative | f | 0.95 | |
| 172 | 7 | 标记清晰与功能正常 | 标记及功能 | (empty) | (empty) | qualitative | f | 0.90 | |
| 173 | 8 | 清晰可辨识 | 关键参数 | (empty) | (empty) | qualitative | f | 0.95 | |

### Record 36 (perfect run)

| id | Line | metric_name | metric_subject | metric_value | metric_unit | value_range_type | is_explicit_metric | confidence | threshold_or_target |
|---|---|---|---|---|---|---|---|---|---|
| 174 | 1 | 关键参数清晰可辨识 | 关键参数 | (empty) | (empty) | qualitative | f | 0.80 | |
| 175 | 1 | 显示亮度清晰可见 | 显示亮度 | (empty) | (empty) | qualitative | f | 0.80 | |
| 176 | 2 | 显示屏静态对比度 | 显示屏 | 500:1 至 2000:1 | ratio | range | t | 1.00 | 500:1 至 2000:1 |
| 177 | 3 | 视觉报警信号显示延迟 | 视觉报警信号 | 150 | ms | upper_bound | t | 1.00 | 150 ms |
| 178 | 4 | 触控操作反馈延迟 | 触控操作反馈 | (empty) | (empty) | qualitative | f | 0.80 | |
| 179 | 5 | 像素限值 | 显示屏 | (empty) | (empty) | limit_absent | f | 0.95 | |
| 180 | 6 | 可读性 | 显示屏 | (empty) | (empty) | qualitative | f | 0.95 | |
| 181 | 7 | 标记清晰与功能正常 | 标记 | (empty) | (empty) | qualitative | f | 0.95 | |
| 182 | 8 | 清晰可辨识 | 关键参数 | (empty) | (empty) | qualitative | f | 0.95 | |

Note on `value_range_type` for the alarm clause (line 3): all four `v9` extractions
classify it as `upper_bound`, not `(n/a)` — the closed vocabulary introduced in `v4`
holds up even where the extraction-candidate step (`v9`) itself is unstable about
whether the line gets extracted at all. This is consistent with `v4`/`v6`'s scope being
purely downstream of `v9`'s recall.

## Change Record

Not committed. New prompt files added during this investigation, none replacing an
existing active file (per standing instruction to always version rather than modify):
- `prompts/prompt-extract-metric-candidates-v7.md`
- `prompts/prompt-extract-metric-candidates-v8.md`
- `prompts/prompt-extract-metric-candidates-v9.md`

`mise.local.toml` unchanged — production still pins `v4`/`v2`. No fixture files changed
in this document's investigation (the "6.3.2.2" prefix was deliberately kept, per the
user's judgment that it is a factual property of the input, not a defect).

## Documentation Impact

What knowledge changed:
- Two of `extract_metrics`'s recall problems have identified, and one has a fixed, root
  cause. A third (correlated-pair failures) is confirmed as a repeatable phenomenon
  across two independent instances, with no explanation yet.
- Chinese national standards' numbered-clause convention (a clause number can prefix the
  requirement text itself, not sit above it as a separate heading) is now documented
  prompt guidance, not just an observation.

Which docs/specs/ADRs are affected:
- ADR `2026072901-adr-ontology-platform-and-adaptive-pipeline.md`'s P3 findings section
  should be read alongside this document's more complete root-cause picture.

Which docs were updated: this document and `OPEN.md`. 2026073001 and 2026073002 remain
unmodified, per standing instruction.

What was intentionally left undocumented:
- No decision was made on `v9` vs. production `v4`/`v2`; see Disposition.
- RC2 and RC3 are named and evidenced but not diagnosed further.
