# ADR 2026071603 — Doc Review Report: Artifact Field Blocks and Reordered Finding Cards

**Date:** 2026-07-16 \
**Status:** Accepted \
**Component:** ChenWeb — `server/api/doc-reviews` \
**Authors:** Chen Ding \
**Tags:** document reviewer, metrics, provisions, inventory-items, report rendering

---

## Change Logs
* 2026/07/16, ADR created.

## Context

ADR 2026062203 §1.2 defined per-artifact report sections for the `metrics`, `provisions`,
and `inventory_items` reviewers: findings grouped by `artifact_id`, with each reviewer's
comparison analyses rendered first, followed by that artifact's findings. A rendered
finding card (`review-finding(...)` in `template-document-report.typ`) today shows, in
order: Related Source Lines (相关源行) → Errors (错误, the card title) → Explanation
(说明) → Referenced Matching Metric Lines (引用的匹配指标源行) → Recommended Correction
(建议的修正, currently always rendered even when empty).

Two problems with this, found by inspecting a rendered report:

1. The card never shows *what the artifact under review actually is* — a reader sees
   source lines and a finding description, but not the metric's own name/value/unit (or
   the provision's text, or the item's model/part number) as a structured block. The LLM
   payload already carries this (`metric_under_review` etc., ADR 2026062203 §1.1), but it
   is discarded before the report is built.
2. Likewise for the *matched/referenced* artifact: the card shows the referenced
   artifact's source lines but never its structured fields (its own name/value/unit, or
   provision text, or model/part number) — only prose in `description` references it.

## Decision

### DR1 — Persist two new raw-JSON fields in the existing `metadata` envelope

No schema migration. `kb.doc_review_findings.metadata` already carries
`related_artifact_id`/`related_record_id` (ADR 2026070201 AR5) via
`FindingMetadataEnvelope` (`models.go`). Extend that envelope with:

```go
ArtifactFields        json.RawMessage `json:"artifact_fields,omitempty"`
RelatedArtifactFields json.RawMessage `json:"related_artifact_fields,omitempty"`
```

Each holds the exact `metricView` / `provisionView` / `inventoryItemView` struct
(already defined in each reviewer file, already used verbatim for the LLM payload)
marshaled as-is. `encoding/json` preserves struct field order on marshal, so the report
renderer gets a stable, self-describing field order for free — no separate ordered-list
storage format needed.

### DR2 — Populated in the existing per-finding tagging loop

Each of the three reviewers already has a loop that stamps `Pass`/`Aspect`/`ArtifactID`
onto every finding before returning it (e.g. `review-metrics.go` lines ~283-296). Extend
that loop:

- `ArtifactFields = json.Marshal(dm.view)` (`dp.view` / `di.view` for provisions /
  inventory items) — always set, since the artifact-under-review is already in scope.
- `RelatedArtifactFields = json.Marshal(matchedView)` — set only when
  `RelatedArtifactID` is non-empty, looked up from a `map[string]<view>` built once from
  the matched-candidates slice (`ms` / `mp` / `mi`) already passed into
  `reviewMetric`/`reviewProvision`/`reviewItem`.

This covers both LLM-emitted findings and the synthesized "comparison analysis" findings
(`metricAnalysesAsFindings` / `provisionAnalysesAsFindings` /
`inventoryItemAnalysesAsFindings`), since both pass through the same tagging loop.

### DR3 — Plumbing through storage and read paths

`ReviewFinding` (`review-document.go`) gains the two fields. `prepareFindingForStorage`
and `prepareFindingForStorageWithoutTranslation` (`finding_translation.go`) copy them
into `preparedFindingForStorage.Metadata` alongside the existing `RelatedArtifactID`
copy. `SaveFindings`'s `json.Marshal(prepared.Metadata)` picks them up automatically — no
`INSERT` column change.

On read, `applyFindingMetadata` (`models.go`) copies the two fields out of metadata into
`FindingItem`, and `report.go`'s `ReportFinding` carries them through unchanged into the
Typst-building path — no new query, since `loadReportFindingsWithMetadata` already reads
the full `metadata` column.

### DR4 — Finding card: reorder + two new blocks

`review-finding(...)` (`template-document-report.typ`) is reordered to: Explanation
(说明) → Recommended Correction (建议的修正) → **Metric/Provision/Item fields (new)** →
Related Source Lines (相关源行) → **Referenced Metric/Provision/Item fields (new)** →
Referenced Matching Metric Lines (引用的匹配指标源行). The Errors/title block stays as
the card's unlabeled header, not a body section.

Both new blocks reuse the existing `meta-row(label, value)` helper (already defined,
currently only used on the cover page) in a loop over the decoded field list, and render
conditionally — omitted when `ArtifactFields`/`RelatedArtifactFields` is empty (legacy
pre-migration rows, or findings with no matched artifact), mirroring how
`related-sources` is already conditional.

`buildFindingBlock` (`typst_report.go`) decodes the raw JSON into the matching view
struct for the current aspect and converts it to an ordered `[][2]string` via a small
explicit per-type function (`metricFieldRows`, `provisionFieldRows`,
`inventoryItemFieldRows`) — hand-written label/value pairs, not reflection, skipping
empty fields. These become two new `review-finding(...)` args: `metric-fields:` /
`related-metric-fields:`.

### DR5 — Artifact-group section title gets a type label

`buildArtifactGroupsArg`'s `title := artifactID` (`typst_report.go`) becomes
`title := typeLabel + " (" + artifactID + ")"`, e.g. `指标 (244_mtc_2)` / `条款 (...)` /
`产品/零部件 (...)`, which Typst's auto-numbered heading renders as
`4.1.2. 指标 (244_mtc_2)`.

### DR6 — Localization

New entries added to both language maps in `reportLexiconForLanguage`
(`typst_report.go`): one type label per aspect (`指标`/`条款`/`产品/零部件` vs.
`Metric`/`Provision`/`Inventory Item`) — reused for both the new field-block header and
the artifact-group title prefix (DR5) — plus a "referenced description" label (e.g.
`引用的指标说明` vs. `Referenced Metric`).

## Alternative Decisions

- **Requery `kb.metrics`/`kb.provisions`/`kb.inventory_items` at report-build time**
  (mirroring how `buildRelatedSources` already requeries for source-line spans):
  rejected. The requester explicitly wants the report generator to read finding data
  straight off `kb.doc_review_findings` without a live join back to the artifact tables,
  so the field snapshot must be captured once, at finding-creation time.
- **New dedicated columns instead of extending `metadata`:** rejected — unlike
  `artifact_id` (ADR 2026070603 DR1, a queryable primary-subject key), these two fields
  are display-only payload for report rendering, the same category as
  `related_artifact_id`/`related_record_id`, which already live in `metadata`.
- **Ordered `[]struct{Label,Value}` storage format instead of raw view-struct JSON**:
  rejected — `encoding/json` already preserves Go struct field order on marshal, so
  storing the view struct directly is simpler and self-describing (field names are the
  same ones already documented in ADR 2026062203 §1.1), at the cost of the renderer
  needing a small per-type label list to turn JSON field names into display labels.

## Database Migrations
None. `kb.doc_review_findings.metadata` is already `JSONB`; the two new fields are
additive keys within it.

## Implementation

### Code Changes

| File | Change |
|---|---|
| `ChenWeb/server/api/doc-reviews/models.go` | `FindingMetadataEnvelope` and `FindingItem` gain `ArtifactFields`/`RelatedArtifactFields json.RawMessage` (DR1, DR3). |
| `ChenWeb/server/api/doc-reviews/review-document.go` | `ReviewFinding` gains the two fields (DR3). |
| `ChenWeb/server/api/doc-reviews/review-metrics.go` | Finding-tagging loop populates both fields from `dm.view` / matched-metric lookup (DR2). |
| `ChenWeb/server/api/doc-reviews/review-provisions.go` | Same, from `dp.view` / matched-provision lookup (DR2). |
| `ChenWeb/server/api/doc-reviews/review-inventory-items.go` | Same, from `di.view` / matched-item lookup (DR2). |
| `ChenWeb/server/api/doc-reviews/finding_translation.go` | `prepareFindingForStorage` / `prepareFindingForStorageWithoutTranslation` carry the two fields into `Metadata` (DR3). |
| `ChenWeb/server/api/doc-reviews/report.go` | `ReportFinding` carries the two fields through (DR3). |
| `ChenWeb/server/api/doc-reviews/typst_report.go` | `metricFieldRows`/`provisionFieldRows`/`inventoryItemFieldRows` helpers; `buildFindingBlock` emits `metric-fields:`/`related-metric-fields:`; `buildArtifactGroupsArg` title gains type-label prefix (DR4, DR5); `reportLexiconForLanguage` gains new label keys (DR6). |
| `ChenWeb/docs/doc-templates/template-document-report.typ` | `review-finding(...)` reordered and gains two new params rendered via `meta-row` loops (DR4). |

## Operational Behaviors
- **Existing findings** (pre-change): `ArtifactFields`/`RelatedArtifactFields` are absent
  from `metadata`. The two new card blocks are simply omitted for those rows — no
  backfill, matching the precedent set by ADR 2026070603.
- **Findings with no matched artifact:** `RelatedArtifactFields` stays unset; only the
  "Metric/Provision/Item" block renders, not the "Referenced ..." block.

## Consequences

**Positive**
- Report readers see the artifact under review and its referenced match as structured
  data, not just prose + source lines — directly addresses the two missing sections
  identified from the rendered report.
- No migration, no new query at report-build time; reuses an established pattern
  (`metadata` envelope) end to end.

**Negative / cost**
- `metadata` JSONB grows per finding (two more, potentially multi-field, JSON blobs);
  acceptable given findings are text-review artifacts, not high-frequency rows.
- Per-type field-row helpers (`metricFieldRows` etc.) are hand-written and must be kept
  in sync if a view struct gains/removes fields — same maintenance cost already accepted
  for the view structs themselves (ADR 2026062203 §1.1).

## Tests
- Per-reviewer finding-tagging tests (mirroring `TestReviewMetric_PayloadAndFindingTagging`
  etc. from ADR 2026070603) extended to assert `ArtifactFields` is always set and
  `RelatedArtifactFields` is set iff `RelatedArtifactID` is set.
- `finding_translation_test.go` — metadata JSON round-trips the two new fields.
- `typst_report_test.go` — `buildFindingBlock` emits `metric-fields:`/
  `related-metric-fields:` args with expected label/value pairs; empty case omits both
  blocks; `buildArtifactGroupsArg` title includes the type-label prefix.
- `go build ./...`, `go vet ./...`, `go test ./server/api/doc-reviews/...` clean.

## Documentation Impact
- This ADR extends ADR 2026062203 §1.2 (per-artifact report sections) with the two new
  field blocks and the reordered card layout; §1.1's payload shapes (`metric_under_review`
  etc.) are the field source of truth referenced by DR1/DR4 and are unchanged.
- **Intentionally left undocumented / open:** the `entities` reviewer is out of scope
  (not artifact-anchored in the ADR 2026070603 sense); no field blocks are added for it.

## References
[1] ADR 2026062203 — Generate Document Review Report (§1.1 artifact payload shapes, §1.2 per-artifact report sections) \
[2] ADR 2026070201 — Document Review: Artifact Reviewer Context, Prompt-Cache Layout, and Missing-Metric Detection (AR5: `related_artifact_id`/`related_record_id`) \
[3] ADR 2026070603 — `kb.doc_review_findings`: `artifact_id` Column for Per-Artifact Reviewers \
[4] ADR 2026070602 — Provisions Reviewer: Mandatory Comparison Analyses \
[5] ADR 2026070604 — Metrics and Inventory-Items Reviewers: Mandatory Comparison Analyses
