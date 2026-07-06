# ADR 2026070603 — `kb.doc_review_findings`: `artifact_id` Column for Per-Artifact Reviewers

**Date:** 2026-07-06 \
**Status:** Accepted — implemented 2026/07/06 \
**Component:** ChenWeb — `server/api/doc-reviews` \
**Authors:** Chen Ding \
**Tags:** document reviewer, metrics, provisions, inventory-items, schema

---

## Change Logs
* 2026/07/06, ADR created and implemented.

## Context

The per-artifact reviewers (metrics, provisions, inventory_items) each iterate over the
artifacts extracted from the document under review (`kb.metrics`, `kb.provisions`,
`kb.inventory_items`) and, for each one, compare it against semantically-matched
artifacts from other documents (ADR 2026063002/3/5), emitting `kb.doc_review_findings`
rows.

`kb.doc_review_findings` already carries a cross-document reference —
`related_artifact_id` / `related_record_id`, added by ADR 2026070201 AR5 and stored in
the `metadata` JSONB — but that pair identifies the *matched* artifact in the *other*
document. There has never been a column identifying which artifact *in the document
under review* a finding is about. The reviewers compute this value already (e.g.
`dm.view.MetricID`, `dp.view.ProvID`, `di.view.ItemID` in `review-metrics.go` /
`review-provisions.go` / `review-inventory-items.go`) and use it for logging
(`ReviewLogEntry.UnitKey`) and cache lookups, but discard it before persisting the
finding. Without it, a finding can only be traced back to its source artifact by
re-parsing the `location` line-span string, which is lossy (spans are not unique keys)
and does not support a direct `WHERE artifact_id = ...` lookup across runs.

## Decision

### DR1 — New column: `artifact_id TEXT`, not metadata

Unlike `related_artifact_id`/`related_record_id` (kept in `metadata` per ADR 2026070201
DR since they are secondary, cross-document bookkeeping), `artifact_id` identifies the
finding's own primary subject. It is added as a real, indexed column so it can be
queried and filtered directly — e.g. "all findings ever raised about metric
`2002_met_14`" — without parsing JSONB.

```sql
ALTER TABLE kb.doc_review_findings ADD COLUMN artifact_id TEXT;
CREATE INDEX idx_doc_review_findings_artifact
    ON kb.doc_review_findings (input_record_id, artifact_id);
```

### DR2 — Populated by three reviewers only

`artifact_id` is set in the finding-tagging loop of the three artifact-anchored
reviewers only, alongside the existing `Pass`/`Aspect`/`Location` assignment:

| Reviewer | Source |
|---|---|
| metrics (`review-metrics.go`) | `dm.view.MetricID` |
| provisions (`review-provisions.go`) | `dp.view.ProvID` |
| inventory_items (`review-inventory-items.go`) | `di.view.ItemID` |

The `entities` reviewer and the text-chunk reviewers (P1–P4, e.g. `grammar_spelling`)
leave it null: entities' redesign was deferred to a separate discussion (per the
session-2026-07-02 investigation notes), and text-chunk reviewers are not
artifact-anchored — a null `artifact_id` is the correct representation for both, not a
gap to fill later.

### DR3 — Plumbing through the finding-storage pipeline

`ReviewFinding` (`review-document.go`) gains `ArtifactID string`. It flows through
`prepareFindingForStorage` / `prepareFindingForStorageWithoutTranslation`
(`finding_translation.go`) into `preparedFindingForStorage.Canonical`, and
`ReviewFindingsSQLStore.SaveFindings`'s `INSERT` gains the column and a `$14`
placeholder (empty string treated as `NULL`, same convention as `evidence`/`location`/
`suggestion`).

On the read side, `FindingItem` (`models.go`) gains `ArtifactID string`, and the two
`SELECT ... FROM kb.doc_review_findings` queries (`controller.go`'s
`GetRequestWithFindings`, `typst_report.go`'s `loadReportFindingsWithMetadata`) add
`COALESCE(artifact_id,'')` to their column list and `Scan` targets.

## Alternative Decisions
- **Store in `metadata` JSONB alongside `related_artifact_id`:** rejected — this field
  is the finding's primary subject, not secondary cross-reference bookkeeping; a real
  column keeps it queryable/indexable and matches the intent of "add a field to the
  table."
- **Populate for `entities` too:** rejected for this change — entities reviewer's
  artifact-comparison redesign is an open, separate discussion; adding `artifact_id`
  there now would presume an architecture not yet agreed on.

## Database Migrations
New migration, `project_migrations/20260706000002_add_artifact_id_to_doc_review_findings.sql`:

```sql
-- +goose Up
ALTER TABLE kb.doc_review_findings
    ADD COLUMN artifact_id TEXT;

CREATE INDEX IF NOT EXISTS idx_doc_review_findings_artifact
    ON kb.doc_review_findings (input_record_id, artifact_id);

-- +goose Down
DROP INDEX IF EXISTS idx_doc_review_findings_artifact;
ALTER TABLE kb.doc_review_findings
    DROP COLUMN IF EXISTS artifact_id;
```

## Implementation

### Code Changes

| File | Change |
|---|---|
| `ChenWeb/project_migrations/20260706000002_add_artifact_id_to_doc_review_findings.sql` | New column + index (DR1). |
| `ChenWeb/server/api/doc-reviews/review-document.go` | `ReviewFinding.ArtifactID` field; `SaveFindings` INSERT + `$14` arg (DR3). |
| `ChenWeb/server/api/doc-reviews/models.go` | `FindingItem.ArtifactID` field (read side). |
| `ChenWeb/server/api/doc-reviews/finding_translation.go` | `prepareFindingForStorage` / `prepareFindingForStorageWithoutTranslation` carry `ArtifactID` into `Canonical` (DR3). |
| `ChenWeb/server/api/doc-reviews/review-metrics.go` | Finding loop sets `ArtifactID = dm.view.MetricID` (DR2). |
| `ChenWeb/server/api/doc-reviews/review-provisions.go` | Finding loop sets `ArtifactID = dp.view.ProvID` (DR2). |
| `ChenWeb/server/api/doc-reviews/review-inventory-items.go` | Finding loop sets `ArtifactID = di.view.ItemID` (DR2). |
| `ChenWeb/server/api/doc-reviews/controller.go` | `GetRequestWithFindings` SELECT + scan add `artifact_id`. |
| `ChenWeb/server/api/doc-reviews/typst_report.go` | `loadReportFindingsWithMetadata` SELECT + scan add `artifact_id`. |
| `ChenWeb/server/api/doc-reviews/review-metrics_test.go`, `review-provisions_test.go`, `review-inventory-items_test.go` | `TestReview*_PayloadAndFindingTagging` assert `ArtifactID` is set to the artifact's own ID. |
| `ChenWeb/server/api/doc-reviews/finding_translation_test.go` | sqlmock `INSERT` expectations updated for the new column/placeholder; one test asserts an `ArtifactID` value round-trips into the `INSERT` args. |
| `ChenWeb/server/api/doc-reviews/typst_report_test.go` | sqlmock query/row expectations updated for the new column. |

## Operational Behaviors
- **Existing rows** (pre-migration): `artifact_id` is `NULL`. No backfill — the source
  artifact ID for historical findings isn't reliably recoverable from `location` alone,
  and this ADR only concerns findings emitted going forward.
- **Entities / text-chunk reviewers:** `artifact_id` stays `NULL`; this is the correct,
  final state for those reviewers under this ADR, not a temporary gap.

## Consequences

**Positive**
- Findings from the three per-artifact reviewers can now be queried directly by the
  artifact they're about (`WHERE input_record_id = ... AND artifact_id = ...`),
  independent of `location` string parsing.
- Small, mechanical change: one nullable column, no behavior change for any other
  reviewer or existing finding.

**Negative / cost**
- One more column to keep in sync if a future reviewer becomes artifact-anchored;
  acceptable — the pattern (set it in the finding-tagging loop) is now established by
  three reviewers to copy.
- No backfill means older runs can't be queried by `artifact_id`; acceptable per
  Operational Behaviors above.

## Tests
- `TestReviewMetric_PayloadAndFindingTagging`, `TestReviewProvision_PayloadAndFindingTagging`,
  `TestReviewItem_PayloadAndFindingTagging` — each asserts the returned finding's
  `ArtifactID` equals the artifact-under-review's own ID.
- `TestSaveFindingsStoresCanonicalEnglishAndI18NMetadata` — asserts a set `ArtifactID`
  round-trips into the `INSERT` call's args.
- Remaining `TestSaveFindings*` / typst report tests updated for the new column/arg
  shape; no behavior assertions changed.
- `go build ./...`, `go vet ./...`, and `go test ./server/api/doc-reviews/...` clean
  after the change.

## Documentation Impact
- This ADR is the design record for `artifact_id`. ADR 2026070201 AR5 remains the
  design record for `related_artifact_id`/`related_record_id`; the two are
  complementary (own-artifact vs. matched-artifact) and this ADR does not change AR5.
- **Intentionally left undocumented / open:** whether `entities` gets an `artifact_id`
  is deferred to that reviewer's separate redesign discussion (see ADR 2026070201's
  session notes).

## References
[1] ADR 2026070201 — Document Review: Artifact Reviewer Context, Prompt-Cache Layout, and Missing-Metric Detection (AR5: `related_artifact_id`/`related_record_id`) \
[2] ADR 2026063002 — Cross-Document Metric Consistency Reviewer \
[3] ADR 2026063003 — Cross-Document Provision Consistency Reviewer \
[4] ADR 2026063005 — Cross-Document Inventory-Item Consistency Reviewer \
[5] ADR 2026070602 — Provisions Reviewer: Mandatory Comparison Analyses
