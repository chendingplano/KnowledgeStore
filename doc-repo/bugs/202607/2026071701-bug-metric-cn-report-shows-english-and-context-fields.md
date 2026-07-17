# Bug: Chinese doc review report shows English-duplicate and internal-context metric fields

Date: 2026-07-17\
Status: fixed-unverified\
System: `ChenWeb` document review report generation\
Component: `server/api/doc-reviews`

## Summary

The Chinese-language (`-report-cn.pdf`) doc review report rendered metric
field rows that should not appear in that language's report:

- `指标名称（英文）` (metric name, EN)
- `对象（英文）` (subject, EN)
- `描述` (description)
- `描述（英文）` (description, EN)
- `上下文` (context)
- `上下文（英文）` (context, EN)
- `单位（英文）` (unit, EN)

## Symptom

Observed in `/Users/cding/Apps/DocReviewReports/20260717-1005-73-report-cn.pdf`:
the metric card for `244_mtc_1` rendered all of the fields above alongside the
fields that should be kept (`指标 ID`, `指标名称`, `对象`, `数值`, `单位`,
`数值类型`, `取值范围类型`, `数值类别`, `阈值/目标`, `分类`, `源行范围`, etc).

## Root Cause

`metricFieldRows` in `typst_report.go` unconditionally appended a row for
every metric field regardless of report language. `addFieldRow` only chooses
which label text to use (English vs. Chinese) per `lang` — it does not omit a
row for either language. So every field, including the English-duplicate and
internal-context fields, rendered in both the English and Chinese reports.

## Fix

`metricFieldRows` now skips `MetricNameEn`, `SubjectEn`, `Description`,
`DescriptionEn`, `Context`, `ContextEn`, and `UnitEn` when the report
language is Chinese (`zh`, `zh-cn`, `zh-hans`). These fields continue to
render in the English report.

Code change:

- `ChenWeb/server/api/doc-reviews/typst_report.go` (`metricFieldRows`)

Doc updated:

- `KnowledgeStore/doc-repo/adrs/202606/2026062203-adr-generate-doc-review-report.md`
  — recorded the Chinese-report field-suppression rule under the metrics
  reviewer payload section.

No test was added; no existing test exercised `metricFieldRows` output
directly (checked `typst_report_test.go` and other `doc-reviews` tests before
the change — none assert on rendered field-row labels).

## Verification

- `go build ./api/doc-reviews/...` — passes
- `go test ./api/doc-reviews/...` — passes (pre-existing suite, no new
  assertions added for this fix)

Still owed (see `OPEN.md`):

- No sample report was regenerated and visually re-checked against a real
  PDF. The original repro used
  `/Users/cding/Apps/DocReviewReports/20260717-1005-73-report-cn.pdf`; that
  request should be re-run through report generation and the resulting
  `-report-cn.pdf` inspected to confirm the seven fields are gone and the
  `-report-en.pdf` is unaffected.

## Change Record

Not yet committed. `ChenWeb` working copy has the `typst_report.go` edit
staged locally; commit was deliberately deferred because both the `ChenWeb`
and `KnowledgeStore` working copies had unrelated pre-existing uncommitted
changes at the time, and the user asked not to commit yet.

## Documentation Impact

What knowledge changed:
- The Chinese doc review report intentionally omits English-duplicate and
  internal-context metric fields; this was previously unspecified and the
  renderer showed every field in every language.

Which docs/specs/tests are affected:
- ADR 2026062203 (`§1.1.1 Metrics reviewer`) now documents the omitted-field
  list for the Chinese report.

Which docs were updated:
- ADR 2026062203.
- This bug record.

Which docs may still be stale:
- None known. `provisionFieldRows` and `inventoryItemFieldRows` were not
  touched and were out of scope for this report (only metrics fields were
  reported as wrong).

What was intentionally left undocumented:
- No regression test was written; flagged above as owed if this recurs.
