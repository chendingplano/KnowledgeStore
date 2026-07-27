# Bug: `extract_metrics` recall is unstable across identical, temperature-0 repeated calls on the same document

Date: 2026-07-30\
Status: open\
System: `ChenWeb` document processing / `extract_metrics`\
Component: `server/api/doc-processing/extract-metrics.go`, `prompts/prompt-extract-metric-candidates-v6.md`, `prompts/prompt-enrich-metrics-v4.md`\
Model: `deepseek-flash-chen` (`deepseek-v4-flash`, DeepSeek cloud API)

## Summary

Running `extract_metrics` four times against the **same** generated document, with the
**same** prompts and **temperature already at 0**, produced four different sets of
extracted metrics — row counts of 4, 6, 8, and 4, with individual clauses appearing in
some runs and not others. One clause (`resolution-absent`, phrased as an explicit
non-specification) failed to extract in **all four** runs. Two pairs of adjacent clauses
succeeded or failed **together** across runs, suggesting the instability may cluster by
processing unit rather than being independent per-clause noise. A distinct, already
root-caused fixture authoring defect was also found during this investigation and is
documented separately below so it does not contaminate conclusions about the model's
behavior.

This bug exists to hand off a fully-diagnosed dataset for review, per the plan agreed
with the user: run N times, compare, and decide from evidence whether this is prompt
tuning, an overlooked mechanical issue, or an accepted model/provider limitation to
revisit later if the model itself changes.

## Test Document

CDM-generated synthetic standard `doc:cn-gb-syn-9706-1-2020` (显示屏模块 gold fixture,
`ChenWeb/benchmark/doc-processors/gold/display-module-v1/gold.toml`), 8 clauses about a
ventilator display module, rendered to a canonical line file via the real Typst pipeline
(one clause per line). The line file used by every run below (post-`static_analyzer`,
identical across runs):

```text
1  关键参数应在正常使用位置清晰可辨识；显示亮度应保证在预期使用环境下清晰可见。
2  显示屏静态对比度应处于 500:1 至 2000:1 范围内。
3  6.3.2.2 视觉报警信号应在触发条件出现后 150 ms 内显示。
4  触控操作反馈不应存在不可接受的延迟。
5  本标准未规定显示屏具体像素限值。
6  显示屏在正常操作位置应可读。
7  清洁消毒后应保持标记清晰与功能正常。
8  关键参数应在正常使用位置清晰可辨识。
```

Line 1 is contaminated — see "Distinct fixture defect found during this investigation"
below. Everything else in this report treats line 1's two candidate concepts (a stray
readability-like fragment, and the actual brightness clause) as one combined cell in the
per-line table, since they cannot currently be told apart cleanly in the data.

## Method

`gold-run` (`ChenWeb/server/cmd/doc-benchmark/gold_run.go`) ran this single document four
times against an isolated database (`chenweb_test`) and isolated artifact root
(`ThirdParty-2/Data/Artifacts`), through the real, unmocked production pipeline
(`docprocessing.NewProductionRuntime`, `extract_metrics` only). Prompts held constant
across all four runs:

- `prompt-extract-metric-candidates-v6.md` (candidate extraction)
- `prompt-enrich-metrics-v4.md` (enrichment/classification)

Record 13 was the first run of this document under these prompt versions (part of a full
9-document corpus run); records 22, 23, 24 are three immediate repeats of this document
alone, run consecutively, no other variable changed.

**Temperature is already 0 for every call.** Confirmed in
`shared/go/api/llm/openai_client.go` (`extractTextWithFormat`): the request body
hardcodes `"temperature": 0`, with no config path to change it per-model or per-call.
There is no sampling-parameter lever left to pull here — the variance below is either
provider-side inference non-determinism (a known characteristic of mixture-of-experts
models like `deepseek-v4-flash` under batched GPU inference, where temperature=0 makes
*sampling* deterministic but does not guarantee bit-identical logits across calls) or a
prompt-side sensitivity, not a client misconfiguration.

## Evidence: per-clause presence across all four runs

✓ = a metric row was extracted whose `source_line_spans`/`metric_desc` matches this
clause. Confidence and `value_range_type` shown for the runs where present.

| Line | Clause (gold) | Run 13 | Run 22 | Run 23 | Run 24 |
|---|---|---|---|---|---|
| 1a | brightness (`vent:display_brightness`, qualitative) | ✗ | ✓ (0.9, qualitative) | ✓ (0.9, qualitative) | ✗ |
| 1b | stray readability fragment (fixture defect, see below) | ✗ | ✓ (0.9, qualitative) | ✓ (0.9, qualitative) | ✓ (0.9, qualitative) |
| 2 | contrast range (`vent:static_contrast_ratio`, explicit range 500–2000) | ✓ (0.9) | ✓ (0.95) | ✓ (0.9) | ✗ |
| 3 | **alarm response time (`vent:alarm_response_time`, explicit upper_bound 150ms)** | ✗ | ✓ (0.95) | ✓ (0.9) | ✗ |
| 4 | touch response (`vent:touch_response_time`, qualitative) | ✗ | ✓ (0.8) | ✓ (0.9) | ✗ |
| 5 | **resolution (`vent:screen_resolution`, limit_absent)** | ✗ | ✗ | ✗ | ✗ |
| 6 | viewing angle (`vent:effective_viewing_angle`, qualitative) | ✓ (0.9) | ✓ (0.9) | ✓ (1.0) | ✓ (1.0) |
| 7 | cleaning (`vent:cleaning_disinfection_cycles`, qualitative) | ✓ (0.9) | ✗ | ✓ (1.0) | ✓ (1.0) |
| 8 | readability, real clause (`vent:key_parameter_readability`, qualitative) | ✓ (0.9) | ✗ | ✓ (1.0) | ✓ (1.0) |

Row/candidate totals: 4, 6, 8, 4.

## Findings

### F1 — `resolution` (line 5, `limit_absent`) failed in all 4/4 runs, not just some

Per the review plan's own escalation rule ("if all three tries failed... it may be a
prompt issue, a source-file issue, or something overlooked — flag it"), this clause
already meets that bar with the data on hand; no further runs were needed to establish
it. This is the single most reproducible failure in the dataset — more reproducible than
the alarm clause this bug was originally opened to investigate.

Hypothesis, not yet confirmed: this clause is phrased as an explicit **non**-specification
("本标准未规定显示屏具体像素限值" — "this standard does not specify pixel limits").
Every other clause states a positive requirement, even the qualitative ones. It's
possible the extraction prompts, despite `v6`'s explicit addition of `limit_absent` as a
category, still implicitly bias toward "a requirement exists" framing and the model does
not recognize an explicit-absence statement as a candidate worth extracting at all. This
would be a real, fixable prompt gap distinct from the run-to-run noise problem, but it
needs the source-context/prompt review the user asked for before concluding that.

### F2 — the alarm clause (line 3, the original trigger for this investigation) is genuinely inconsistent: 2/4

Present in runs 22 and 23, absent in 13 and 24. Confidence when present (0.9–0.95) gives
no indication the model was ever unsure about it — when it extracts, it extracts
cleanly. This looks like true call-to-call non-determinism on an otherwise
unambiguous, well-formed, single-sentence clause containing an explicit number and unit.

### F3 — lines 3 and 4 succeed or fail together, perfectly, across all 4 runs; so do lines 7 and 8

- Line 3 (alarm, explicit) and line 4 (touch, qualitative) are both present in runs 22
  and 23, both absent in runs 13 and 24. 4/4 correlated.
- Line 7 (cleaning) and line 8 (readability) are both present in runs 13, 23, 24, both
  absent in run 22. 4/4 correlated.

Four clauses, two pairs, perfect within-pair correlation across all four observations.
With this few data points this could be coincidence, but it is exactly the pattern you'd
expect if the instability is **not** independent per-clause noise but instead something
that affects a contiguous span or processing unit as a whole — e.g. chunk composition,
batch-level attention effects, or how the model apportions output budget across the
candidates it decides to enumerate in one response. This reframes the question: it may
not be "is clause X hard to extract" so much as "what determines which half of the
document gets full attention in a given call." Needs more runs (and ideally, deliberately
varied chunk boundaries) to tell coincidence from a real structural effect.

### F4 — line 6 (viewing angle) was the only clause present in all 4/4 runs

Worth noting as a positive control: something in this run *is* fully stable. Not
obviously different in form from lines 4 or 7 (also qualitative, similar sentence
length), which weakens a simple "qualitative clauses are just harder" explanation and is
more consistent with F3's structural hypothesis than a per-clause-difficulty one.

## Distinct fixture defect found during this investigation (not a model/prompt bug)

While tracing `source_line_spans` back to source text to build the table above, line 1's
`metric_desc` values revealed that the gold fixture's own `text_template` for
`cl:cn-9706-7.1.2-brightness` is malformed:

```text
'关键参数应在正常使用位置清晰可辨识；显示亮度应保证在预期使用环境下清晰可见。'
```

This clause should state only the brightness requirement. The leading clause
("关键参数应在正常使用位置清晰可辨识") is a near-duplicate of the *separate*,
deliberately-authored `cl:cn-readability-qual` clause's text
("关键参数应在正常使用位置清晰可识别。" — note 可辨识 vs 可识别, otherwise nearly
identical) and does not belong here. This is a copy/paste authoring error in
`gold.toml` from when the fixture was written, not an extraction defect.

Effect on this investigation: line 1 produces zero, one, or two candidates depending on
whether the run splits the merged sentence, which contaminated any attempt to read
line-1 behavior as evidence about the model. It was excluded from the F1–F4 conclusions
above by treating its two possible candidates as a separate combined row rather than
folding it into the single-clause analysis. It should be fixed in `gold.toml` (remove the
stray leading sentence from `cl:cn-9706-7.1.2-brightness`'s `text_template`) before any
further runs use line 1 as a signal, and this specific document's earlier full-corpus
result (record 13) and this bug's own table should be treated as reflecting the
contaminated fixture, not a clean baseline.

## What was NOT the cause

- **Sampling temperature.** Already 0, hardcoded, no config path — ruled out directly by
  reading the client code (see Method).
- **Prompt drift between runs.** All four runs used the exact same two prompt files
  (`v6`/`v4`); confirmed by re-reading the env-var overrides used for each invocation.
- **Line file / grounding differences between runs.** All four runs used the same
  generated CDM document, so the line file content and numbering are identical across
  runs (verified: the dump above is one representative file; the same document input was
  used unmodified for all four calls).
- **Loss between extraction and storage.** `metric_desc` on every stored row is a
  verbatim or near-verbatim quote of the correct source sentence with a correct
  `source_line_spans` citation (except the pre-existing line-1 fixture defect above) —
  when a candidate is extracted, it is extracted and stored faithfully. The loss happens
  before that, inside the LLM call(s) themselves (candidate extraction and/or
  enrichment/merge), not in deterministic Go code downstream of them.

## Open Questions For Review

1. Is F1 (resolution/`limit_absent`, 0/4) a prompt-instruction gap specific to
   absence-framed statements, distinct from F2/F3's general noise? Worth testing in
   isolation once the line-1 fixture defect is fixed.
2. Is F3's pairing real (a structural, chunk/attention-level effect) or coincidence from
   only 4 observations? More repeated runs — ideally with deliberately varied chunk
   boundaries — would help distinguish these.
3. Per the user's plan: is >95–98% single-call reliability achievable at all for this
   model/provider, or is running N=3 (or more, "for important documents") and merging —
   which the production pipeline already supports by design (it adds newly-found metrics
   without wiping existing ones) — the intended, accepted mitigation rather than a prompt
   fix? If so, F1's 0/4 result matters more than F2/F3, since repetition cannot rescue a
   clause the model never extracts under any of these prompts.
4. Should the gold fixture defect (line 1) be fixed now, independently of the above, so
   future runs of this document aren't contaminated by it?

## Appendix: Every Extracted Metric, All Four Runs

Complete `kb.metrics` rows for records 13, 22, 23, 24 (this bug's four repeated runs of
`doc:cn-gb-syn-9706-1-2020`). `id` is the `kb.metrics` primary key. All fields shown are
exactly as stored; nothing paraphrased.

### Record 13 (first run, part of the original 9-document corpus run)

| id | metric_name | metric_subject | metric_value | metric_unit | value_range_type | value_class | is_explicit_metric | confidence | source_line_spans | threshold_or_target |
|---|---|---|---|---|---|---|---|---|---|---|
| 35 | 显示屏静态对比度 | 显示屏 | 500:1 至 2000:1 | ratio | range | requirement | t | 0.9 | ["2"] | (empty) |
| 36 | 可读性 | 显示屏 | (empty) | (empty) | qualitative | requirement | f | 0.9 | ["6"] | (empty) |
| 37 | 标记清晰度与功能正常性 | 标记与功能 | (empty) | (empty) | qualitative | requirement | f | 0.9 | ["7"] | (empty) |
| 38 | 清晰可辨识性 | 关键参数 | (empty) | (empty) | qualitative | requirement | f | 0.9 | ["8"] | (empty) |

### Record 22 (repeat 1)

| id | metric_name | metric_subject | metric_value | metric_unit | value_range_type | value_class | is_explicit_metric | confidence | source_line_spans | threshold_or_target |
|---|---|---|---|---|---|---|---|---|---|---|
| 72 | 关键参数清晰可辨识 | 关键参数 | (empty) | (empty) | qualitative | requirement | f | 0.9 | ["1"] | (empty) |
| 73 | 显示亮度清晰可见 | 显示亮度 | (empty) | (empty) | qualitative | requirement | f | 0.9 | ["1"] | (empty) |
| 74 | 显示屏静态对比度 | 显示屏 | 500:1 to 2000:1 | ratio | range | requirement | t | 0.95 | ["2"] | 500:1 to 2000:1 |
| 75 | 视觉报警信号显示时间 | 视觉报警信号 | 150 | ms | exact | requirement | t | 0.95 | ["3"] | 150 ms |
| 76 | 触控操作反馈延迟 | 触控操作反馈 | (empty) | (empty) | qualitative | requirement | f | 0.8 | ["4"] | (empty) |
| 77 | 显示屏可读性 | 显示屏 | (empty) | (empty) | qualitative | requirement | f | 0.9 | ["6"] | (empty) |

### Record 23 (repeat 2 — the best-coverage run, missing only `resolution`)

| id | metric_name | metric_subject | metric_value | metric_unit | value_range_type | value_class | is_explicit_metric | confidence | source_line_spans | threshold_or_target |
|---|---|---|---|---|---|---|---|---|---|---|
| 78 | 关键参数清晰可辨识性 | 关键参数 | (empty) | (empty) | qualitative | requirement | f | 0.9 | ["1"] | (empty) |
| 79 | 显示亮度可见性 | 显示亮度 | (empty) | (empty) | qualitative | requirement | f | 0.9 | ["1"] | (empty) |
| 80 | 显示屏静态对比度 | 显示屏静态对比度 | 500:1 至 2000:1 | ratio | range | requirement | t | 0.9 | ["2"] | (empty) |
| 81 | 视觉报警信号显示延迟 | 视觉报警信号 | 150 | ms | upper_bound | requirement | t | 0.9 | ["3"] | (empty) |
| 82 | 触控操作反馈延迟 | 触控操作反馈 | (empty) | (empty) | qualitative | requirement | f | 0.9 | ["4"] | (empty) |
| 83 | display readability | display | (empty) | (empty) | qualitative | requirement | f | 1.0 | ["6"] | (empty) |
| 84 | marking legibility and function normality after cleaning | markings and functions | (empty) | (empty) | qualitative | requirement | f | 1.0 | ["7"] | (empty) |
| 85 | key parameter identifiability | key parameters | (empty) | (empty) | qualitative | requirement | f | 1.0 | ["8"] | (empty) |

### Record 24 (repeat 3 — the worst run, loses both explicit numeric metrics)

| id | metric_name | metric_subject | metric_value | metric_unit | value_range_type | value_class | is_explicit_metric | confidence | source_line_spans | threshold_or_target |
|---|---|---|---|---|---|---|---|---|---|---|
| 86 | 关键参数清晰可辨识 | 医用电气设备 | (empty) | (empty) | qualitative | requirement | f | 0.9 | ["1"] | (empty) |
| 87 | 显示屏可读性 | 显示屏 | (empty) | (empty) | qualitative | requirement | f | 1.0 | ["6"] | (empty) |
| 88 | 标记清晰度与功能正常性 | 标记 | (empty) | (empty) | qualitative | requirement | f | 1.0 | ["7"] | (empty) |
| 89 | 关键参数可辨识性 | 关键参数 | (empty) | (empty) | qualitative | requirement | f | 1.0 | ["8"] | (empty) |

Note on `id` 72/86 (record 22/24, both citing source line 1): both are near-duplicates of
`id` 78/38 (the deliberate `cl:cn-readability-qual` clause at line 8), not the brightness
clause. This is the line-1 fixture defect surfacing again, concretely: the model is
picking up the same accidental phrase from two different places in the document
(the merged fragment at line 1 and the real, separately-authored clause at line 8) and
sometimes representing it as two candidates, sometimes one. See "Distinct fixture defect"
above.

## Change Record

No code or prompt changes made as part of this bug report. `prompt-extract-metric-candidates-v6.md` and `prompt-enrich-metrics-v4.md` already exist as separate, prior work (not modifying the still-active `v4`/`v2` in production) and were used unmodified to produce the evidence above.

## Documentation Impact

What knowledge changed:
- Confirmed `extract_metrics` recall is not 100% deterministic even at temperature 0
  against an identical input, with evidence of clustering rather than pure independent
  per-clause noise.
- Found and isolated a specific fixture authoring defect in `gold.toml` unrelated to the
  model/prompt behavior.

Which docs/specs/ADRs are affected:
- ADR `2026072901-adr-ontology-platform-and-adaptive-pipeline.md` (P3 findings section) —
  this bug is the detailed backing evidence for the "qualitative clause extraction is
  inconsistent" finding recorded there at a summary level.

Which docs were updated: this bug record only.

What was intentionally left undocumented:
- No fix applied yet — pending the review this document was written to support.
- The gold.toml fixture defect is described here but not yet corrected in the fixture
  file itself.
