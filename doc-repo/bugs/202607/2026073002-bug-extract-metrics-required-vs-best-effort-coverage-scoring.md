# Bug (follow-up): reframing extract_metrics instability with required-vs-best-effort coverage scoring

Date: 2026-07-30\
Status: open\
System: `ChenWeb` document processing / benchmark scoring\
Component: `benchmark/doc-processors/gold/display-module-v1` (`coverage.go`, `gold.toml`)\
Related: [2026073001 — `extract_metrics` recall is unstable across identical, temperature-0 repeated calls](2026073001-bug-extract-metrics-recall-instability-across-identical-calls.md)

## Summary

Bug 2026073001 measured `extract_metrics` recall across four identical repeated runs of
one document and found row counts of 4/6/8/4, with individual clauses appearing in some
runs and not others. That investigation scored every clause the same way: present or
missing. This follow-up removes that flattening.

Several of the fixture's clauses are, by design, vague and non-verifiable prose — no
defined scope for "关键参数", no defined "正常使用位置", no measurement method for
"清晰可辨识". Extracting them is good when it happens; their absence should not be scored
as a defect, because they cannot be used to judge compliance either way. Clauses that
state a decidable fact even without a number (e.g. "this standard does not specify a
pixel limit") are a different case entirely and remain fully expected.

This document is not a correction of 2026073001 — its four runs, its per-clause table, and
its conclusion that temperature is not the cause all stand unchanged. This is the same
dataset scored with the distinction the raw investigation was missing, which changes which
findings turn out to matter.

## What Changed

### `gold.toml`: a per-clause `expectation` field

Added to the `[[clause]]` schema (`benchmark/doc-processors/gold/display-module-v1/generate.go`,
`Clause.Expectation`). Empty (unset) means `required` — the default, so no existing clause
needed touching except the ones being reclassified. `best_effort` marks a clause whose
absence from an extraction is acceptable.

Marked `best_effort`: every clause with `form = "qualitative"` fixture-wide — 19 clauses
across CN, ISO, EU, US, and one enterprise clause (`cl:ent-readability-1m`, a borderline
case: it names a concrete "1 m" test distance, which is more checkable than the others,
but was included for consistency; flagged here in case that judgment should be revisited).

Deliberately **not** marked `best_effort`: clauses with `form = "limit_absent"` (the
`resolution` clause in CN/ISO/EU/US). "本标准未规定显示屏具体像素限值" is a decidable,
checkable statement — a human can verify whether the document specifies a pixel limit,
and it explicitly says it does not. That is a fact about the document, not vague prose,
so it stays `required`.

Line 1 (the merged brightness/readability-fragment defect noted in 2026073001) was left
exactly as it was — this fold-in does not touch clause text, only how a miss on that
clause is scored.

### `coverage.go`: the scoring mechanism

New file, pure function, no DB dependency (matching every other package built this
session):

```go
type CoverageJudgement string
const (
    Captured          CoverageJudgement = "captured"
    MissingRequired    CoverageJudgement = "missing_required"
    MissingBestEffort  CoverageJudgement = "missing_best_effort"
)

func ClauseLines(f File, document string) []Clause
func ScoreCoverage(f File, document string, coveredLines map[int]bool) []ClauseCoverage
func ParseLineSpans(spans []string) map[int]bool
```

`ScoreCoverage` takes a plain set of covered line numbers — the caller decides where that
comes from (a `kb.metrics.source_line_spans` query, a JSON blob, a hand-built test case).
Tested (`coverage_test.go`) against synthetic cases and, directly, against this bug's own
four real runs: feeding each run's actual line coverage through `ScoreCoverage` reproduces
2026073001's findings as enforced test assertions rather than a manually-read table.

## The CN Document, Rescored

### Test Document

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

Line/clause map (unchanged from 2026073001):

| Line | Clause | Form | Expectation |
|---|---|---|---|
| 1 | brightness (+ stray fragment) | qualitative | best_effort |
| 2 | contrast range | range | **required** |
| 3 | alarm response time | upper_bound | **required** |
| 4 | touch response | qualitative | best_effort |
| 5 | resolution | limit_absent | **required** |
| 6 | viewing angle | qualitative | best_effort |
| 7 | cleaning | qualitative | best_effort |
| 8 | readability | qualitative | best_effort |

Only three clauses in this document are `required` at all: contrast, alarm, resolution.
Rescoring all four runs (13, 22, 23, 24 — same runs, same coverage data):

| Run | Required defects (`missing_required`) | Which | Best-effort misses (acceptable) |
|---|---|---|---|
| 13 | 2 | alarm, resolution (Line 3) | 2 (brightness, touch) |
| 22 | **1** | resolution (Line 5) | 2 (cleaning, readability) |
| 23 | **1** | resolution (Line 5) | 0 (Line 5)|
| 24 | 3 | contrast (Line 2), alarm (Line 3), resolution (Line 5) | 1 (touch) |

### Required-clause reliability, isolated from best-effort noise

| Line | Clause | Captured / 4 runs | Reliability |
|---|---|---|---|
| 2 | contrast (range) | 3/4 (13, 22, 23) | 75% |
| 3 | alarm (upper_bound) | 2/4 (22, 23) | 50% |
| 5 | resolution (limit_absent) | 0/4 | **0%** |

## What This Reframing Does and Does Not Resolve

**Resolves:** the apparent instability that made runs 13/22/23/24 look like a scattered
4/6/8/4 mess is, for the most part, acceptable variation on clauses that were never going
to be scored strictly in the first place. Run 23 in particular — previously "8 rows, best
coverage, still not clean" — is now recognizable as a near-perfect run: it fails only on
the one clause that fails everywhere.

**Does not resolve, and this is the point:** `resolution` (limit_absent) failing 4/4, and
`alarm` (a plain, unambiguous, single-sentence, explicit-numeric clause) succeeding only
2/4, are both still real, open problems — now isolated from the noise rather than
explained away by it. 2026073001's F1 (resolution, 0/4) and F2 (alarm instability) stand
exactly as before; F3's pairing observation (lines 3+4 moving together) is now visibly a
pairing between one required clause (alarm) and one best-effort clause (touch), which is
worth someone re-examining — a "required+best-effort clause pair moves together" is a
different, weaker signal for a structural/chunking hypothesis than "two arbitrary clauses
move together" was.

## Open Questions For Review

1. Is `cl:ent-readability-1m` correctly `best_effort`, given it names a concrete test
   distance unlike the other 18? (Flagged above, not resolved here.)
2. `resolution` at 0/4 remains this dataset's clearest, most reproducible defect, now with
   noise removed from around it — still needs the prompt/source-context review
   2026073001's F1 called for.
3. Should `captured` further split into "captured and correct" vs "captured but wrong"
   for `best_effort` clauses? The user's original framing ("if extracted, as long as
   correct, GOOD") implies an extracted-but-wrong best-effort clause might still be a
   defect, distinct from never extracting it at all — `coverage.go` does not yet
   distinguish this; it only checks line coverage, not value correctness.

## Appendix: Every Extracted Metric, All Four Runs, With Expectation

Same 22 `kb.metrics` rows as 2026073001's appendix (records 13, 22, 23, 24), reproduced
here so this document is self-contained, with two columns added that only make sense in
this document's context: **Line** (which of the 8 gold clauses this row's
`source_line_spans` maps to) and **Expectation** (`required`/`best_effort` for that
clause, per the line/clause map above). `metric_name` is the literal string
`extract_metrics` produced for that run — note it is *not* stable across runs even for
the same clause (see the "names" discussion this bug follows from).

Clause `resolution` (line 5, `required`) has **zero** rows in any of the four runs — it
never appears in this appendix at all, which is itself the data behind this document's
central finding.

### Record 13

| id | Line | Expectation | metric_name | metric_value | metric_unit | value_range_type | is_explicit_metric | confidence |
|---|---|---|---|---|---|---|---|---|
| 35 | 2 (contrast) | required | 显示屏静态对比度 | 500:1 至 2000:1 | ratio | range | t | 0.9 |
| 36 | 6 (viewing angle) | best_effort | 可读性 | (empty) | (empty) | qualitative | f | 0.9 |
| 37 | 7 (cleaning) | best_effort | 标记清晰度与功能正常性 | (empty) | (empty) | qualitative | f | 0.9 |
| 38 | 8 (readability) | best_effort | 清晰可辨识性 | (empty) | (empty) | qualitative | f | 0.9 |

### Record 22

| id | Line | Expectation | metric_name | metric_value | metric_unit | value_range_type | is_explicit_metric | confidence |
|---|---|---|---|---|---|---|---|---|
| 72 | 1 (brightness/fragment) | best_effort | 关键参数清晰可辨识 | (empty) | (empty) | qualitative | f | 0.9 |
| 73 | 1 (brightness/fragment) | best_effort | 显示亮度清晰可见 | (empty) | (empty) | qualitative | f | 0.9 |
| 74 | 2 (contrast) | required | 显示屏静态对比度 | 500:1 to 2000:1 | ratio | range | t | 0.95 |
| 75 | 3 (alarm) | required | 视觉报警信号显示时间 | 150 | ms | exact | t | 0.95 |
| 76 | 4 (touch) | best_effort | 触控操作反馈延迟 | (empty) | (empty) | qualitative | f | 0.8 |
| 77 | 6 (viewing angle) | best_effort | 显示屏可读性 | (empty) | (empty) | qualitative | f | 0.9 |

### Record 23

| id | Line | Expectation | metric_name | metric_value | metric_unit | value_range_type | is_explicit_metric | confidence |
|---|---|---|---|---|---|---|---|---|
| 78 | 1 (brightness/fragment) | best_effort | 关键参数清晰可辨识性 | (empty) | (empty) | qualitative | f | 0.9 |
| 79 | 1 (brightness/fragment) | best_effort | 显示亮度可见性 | (empty) | (empty) | qualitative | f | 0.9 |
| 80 | 2 (contrast) | required | 显示屏静态对比度 | 500:1 至 2000:1 | ratio | range | t | 0.9 |
| 81 | 3 (alarm) | required | 视觉报警信号显示延迟 | 150 | ms | upper_bound | t | 0.9 |
| 82 | 4 (touch) | best_effort | 触控操作反馈延迟 | (empty) | (empty) | qualitative | f | 0.9 |
| 83 | 6 (viewing angle) | best_effort | display readability | (empty) | (empty) | qualitative | f | 1.0 |
| 84 | 7 (cleaning) | best_effort | marking legibility and function normality after cleaning | (empty) | (empty) | qualitative | f | 1.0 |
| 85 | 8 (readability) | best_effort | key parameter identifiability | (empty) | (empty) | qualitative | f | 1.0 |

### Record 24

| id | Line | Expectation | metric_name | metric_value | metric_unit | value_range_type | is_explicit_metric | confidence |
|---|---|---|---|---|---|---|---|---|
| 86 | 1 (brightness/fragment) | best_effort | 关键参数清晰可辨识 | (empty) | (empty) | qualitative | f | 0.9 |
| 87 | 6 (viewing angle) | best_effort | 显示屏可读性 | (empty) | (empty) | qualitative | f | 1.0 |
| 88 | 7 (cleaning) | best_effort | 标记清晰度与功能正常性 | (empty) | (empty) | qualitative | f | 1.0 |
| 89 | 8 (readability) | best_effort | 关键参数可辨识性 | (empty) | (empty) | qualitative | f | 1.0 |

Reading down the **Expectation** column confirms the rescored table above directly: every
row in every run is either `required` (and there are never more than two of those per
run, out of three possible) or `best_effort`. No run ever produces a `required` row for
line 5, which is why it never appears here at all.

## Change Record

Not yet committed. Changed/added:
- `benchmark/doc-processors/gold/display-module-v1/generate.go` — `Clause.Expectation` field
- `benchmark/doc-processors/gold/display-module-v1/gold.toml` — 19 clauses marked `expectation = "best_effort"`
- `benchmark/doc-processors/gold/display-module-v1/coverage.go` — new
- `benchmark/doc-processors/gold/display-module-v1/coverage_test.go` — new

Verification: `go build ./...`; `go test ./benchmark/... ./server/api/doc-benchmark/... ./server/api/ontology/...` — all pass, no regressions.

## Documentation Impact

What knowledge changed:
- Extraction-recall scoring is no longer binary; `gold.toml` clauses now declare whether
  their own non-extraction is a defect (`required`, default) or acceptable
  (`best_effort`), and `coverage.go` computes the resulting judgement from real line
  coverage.
- Rescoring 2026073001's dataset under this distinction isolates `resolution` (0/4) and
  `alarm` (2/4) as the two problems still worth chasing; the rest of the apparent
  instability in that bug's raw row counts was largely acceptable best-effort variation.

Which docs/specs/ADRs are affected:
- ADR `2026072901-adr-ontology-platform-and-adaptive-pipeline.md` — the "qualitative
  clause extraction is inconsistent" finding recorded there should be read alongside this
  distinction; not every qualitative-clause miss in that finding is necessarily a defect.

Which docs were updated: this bug record and its `Related` predecessor's index entry in
`OPEN.md` (see below). 2026073001 itself was intentionally left unmodified, per instruction.

What was intentionally left undocumented:
- Open question 3 above (captured-but-wrong scoring) is named, not designed or built.
