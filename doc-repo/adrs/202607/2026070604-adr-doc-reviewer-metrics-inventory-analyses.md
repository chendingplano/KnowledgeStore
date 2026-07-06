# ADR 2026070604 — Metrics and Inventory-Items Reviewers: Mandatory Comparison Analyses

**Date:** 2026-07-06 \
**Status:** Proposal \
**Component:** ChenWeb — `server/api/doc-reviews`, `prompts` \
**Authors:** Chen Ding \
**Tags:** document reviewer, metrics, inventory-items, cross-document consistency, tool-use loop, DeepSeek

---

## Change Logs
* 2026/07/06, ADR created as a proposal extending ADR 2026070602 to the metrics and inventory-items reviewers.

## Context

ADR 2026070602 gave the provisions reviewer a mandatory `analyses` array
alongside `findings`, so that its per-candidate comparison reasoning survives
even when the LLM concludes there is no conflict — previously that reasoning
was performed and then discarded, since only `findings` was captured. That ADR
persisted the result in a new table, `kb.doc_review_provision_analyses`, and
explicitly left open whether the metrics and inventory-items reviewers — which
share the same matched-candidate architecture and prompt shape — should get
the same treatment.

ADR 2026062203 §1.2 (report generation) has since decided the answer: the
doc-review report groups `metrics`, `provisions`, and `inventory_items`
findings per-artifact (via `artifact_id`, ADR 2026070603), and within each
artifact's section it compiles that artifact's comparison analyses together
with its findings — for all three reviewers, not only provisions. That
decision presumed `kb.doc_review_metric_analyses` and
`kb.doc_review_inventory_item_analyses` tables would exist; this ADR defines
them and the surrounding reviewer changes.

Both reviewers already run through the same building blocks provisions uses:
a matched-candidate array in the LLM payload (`matching_metrics` /
`matching_items`, ADR 2026070201 AR4/AR5) and the shared tool-use loop
(`runToolUseReview`, `review-tool-loop.go`) at `max_tool_turns = 4`. The same
gap ADR 2026070602 fixed for provisions exists here: a "no conflict" result
still requires a substantive comparison, and none of that reasoning is
retained today.

## Decision

### DR1 — Prompt updates: mandatory `analyses` array

- `prompt-review-metrics-v3.md` (new; supersedes `prompt-review-metrics-v2.md`
  as the active prompt) adds a required `analyses` array: one entry per
  candidate in `matching_metrics`, always populated, independent of whether
  anything rises to a finding.
- `prompt-review-inventory-items-v3.md` (new; supersedes
  `prompt-review-inventory-items-v2.md`) adds the same `analyses` array: one
  entry per candidate in `matching_items`.
- Both mirror provisions v4's entry shape (`related_artifact_id` /
  `related_record_id`, `relationship`, `summary`) and contract: `findings: []`
  is a legitimate empty result, but `analyses` must not be empty when the
  matching array is non-empty.

### DR2 — Tool-use loop: reuse the existing payload-returning entry point

ADR 2026070602 DR2 already added `runToolUseReviewWithPayload` (and its
supporting `WithPayload` chain) as a generic, reviewer-agnostic entry point
that returns the raw LLM payload alongside findings. No further change to
`review-tool-loop.go` is needed: `reviewMetric` and `reviewItem` switch their
tool-use branch to call `runToolUseReviewWithPayload` instead of
`runToolUseReview`, the same way `reviewProvision` already does.

### DR3 — Persistence: two new tables, same shape as provisions'

Following ADR 2026070602 DR3's precedent (a dedicated table per reviewer
rather than overloading `kb.doc_review_findings`):

- `kb.doc_review_metric_analyses` — own-artifact column `metric_id`.
- `kb.doc_review_inventory_item_analyses` — own-artifact column
  `inventory_item_id`.

Both are otherwise identical in shape to `kb.doc_review_provision_analyses`:
`id`, `input_record_id`, `run_id`, the own-artifact-ID column,
`related_artifact_id`, `related_record_id`, `relationship`, `summary`,
`create_time`, scoped to `input_record_id` + `run_id` like every other
doc-review artifact.

Persistence happens directly inside `metricsReviewer.reviewMetric` /
`inventoryItemsReviewer.reviewItem` via `saveMetricAnalyses` /
`saveInventoryItemAnalyses`, mirroring `saveProvisionAnalyses`'s behavior: a
missing `db` handle or a context with no `run_id` causes the save to no-op
rather than error or panic.

### DR4 — Report: no further report-side decision needed

ADR 2026062203 §1.2 already specifies how these tables are consumed: loaded
per artifact section using the same grouping key as findings
(`input_record_id` + `run_id` + own-artifact-ID), rendered analyses-first
followed by that artifact's findings. This ADR supplies the schema that
section anticipated; it makes no independent report-rendering decision.

## Alternative Decisions
- **Single generic `kb.doc_review_analyses` table with an `artifact_type`
  discriminator:** rejected — breaks with the per-reviewer-table precedent
  ADR 2026070602 already shipped for provisions, and a discriminated shared
  table would need a migration touching the already-live provisions table to
  unify schemas. Three parallel tables cost a small amount of duplication but
  keep each reviewer's migration and schema independently stable.
- **Fold into `kb.doc_review_findings` via `finding_type: "observation"`:**
  rejected for the same reasons ADR 2026070602 rejected it for provisions —
  conflates "checked, no issue" with genuine low-confidence findings and
  inflates report finding counts.

## Database Migrations
Two new tables, mirroring
`20260706000001_create_doc_review_provision_analyses.sql`:

```sql
-- project_migrations/20260706000003_create_doc_review_metric_analyses.sql
CREATE TABLE IF NOT EXISTS kb.doc_review_metric_analyses (
    id                  BIGSERIAL    PRIMARY KEY,
    input_record_id     BIGINT       NOT NULL,
    run_id              BIGINT       NOT NULL,
    metric_id           TEXT         NOT NULL,
    related_artifact_id TEXT,
    related_record_id   BIGINT,
    relationship        TEXT         NOT NULL,
    summary             TEXT         NOT NULL,
    create_time         TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
-- + indexes on input_record_id, run_id, metric_id
```

```sql
-- project_migrations/20260706000004_create_doc_review_inventory_item_analyses.sql
CREATE TABLE IF NOT EXISTS kb.doc_review_inventory_item_analyses (
    id                  BIGSERIAL    PRIMARY KEY,
    input_record_id     BIGINT       NOT NULL,
    run_id              BIGINT       NOT NULL,
    inventory_item_id    TEXT         NOT NULL,
    related_artifact_id TEXT,
    related_record_id   BIGINT,
    relationship        TEXT         NOT NULL,
    summary             TEXT         NOT NULL,
    create_time         TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
-- + indexes on input_record_id, run_id, inventory_item_id
```

No changes to `kb.doc_review_findings`, `kb.doc_review_provision_analyses`, or
any other existing table.

## Data Formats

**LLM output**, `analyses` entry (identical shape for both reviewers):

```json
{
  "related_artifact_id": "2002_m_3",
  "related_record_id": 2002,
  "relationship": "same_subject | related_subject | unrelated",
  "summary": "concise comparison: value/spec match, context differences, and why this does or does not rise to a finding"
}
```

**Go representation** (`review-metrics.go`, `review-inventory-items.go`):

```go
type MetricAnalysis struct {
    RelatedArtifactID string
    RelatedRecordID   int64
    Relationship      string
    Summary           string
}

type InventoryItemAnalysis struct {
    RelatedArtifactID string
    RelatedRecordID   int64
    Relationship      string
    Summary           string
}
```

`parseMetricAnalysesJSON` / `parseInventoryItemAnalysesJSON` read
`payload["analyses"]` the same way `parseProvisionAnalysesJSON` does; entries
with an empty `summary` are dropped rather than persisted as noise.

## Environment Variables
None new.

## Implementation

### Code Changes (planned)

| File | Change |
|---|---|
| `ChenWeb/prompts/prompt-review-metrics-v3.md` | New prompt: adds the mandatory `analyses` array (DR1). |
| `ChenWeb/prompts/prompt-review-inventory-items-v3.md` | New prompt: adds the mandatory `analyses` array (DR1). |
| `ChenWeb/doc-review.local.toml` | `reviewers.metrics.prompt` → `prompt-review-metrics-v3.md`; `reviewers.inventory_items.prompt` → `prompt-review-inventory-items-v3.md`. |
| `ChenWeb/server/api/doc-reviews/review-metrics.go` | New `MetricAnalysis` type, `parseMetricAnalysesJSON`, `saveMetricAnalyses`. `reviewMetric` calls `runToolUseReviewWithPayload` (tool-use branch) and persists parsed analyses after building findings (DR2/DR3). |
| `ChenWeb/server/api/doc-reviews/review-inventory-items.go` | New `InventoryItemAnalysis` type, `parseInventoryItemAnalysesJSON`, `saveInventoryItemAnalyses`. `reviewItem` calls `runToolUseReviewWithPayload` and persists parsed analyses (DR2/DR3). |
| `ChenWeb/project_migrations/20260706000003_create_doc_review_metric_analyses.sql` | New table `kb.doc_review_metric_analyses` (DR3). |
| `ChenWeb/project_migrations/20260706000004_create_doc_review_inventory_item_analyses.sql` | New table `kb.doc_review_inventory_item_analyses` (DR3). |
| `ChenWeb/server/api/doc-reviews/review-metrics_test.go` | New: `TestParseMetricAnalysesJSON`, `TestParseMetricAnalysesJSON_NoAnalysesKey`, `TestReviewMetric_SavesAnalyses`. |
| `ChenWeb/server/api/doc-reviews/review-inventory-items_test.go` | New: `TestParseInventoryItemAnalysesJSON`, `TestParseInventoryItemAnalysesJSON_NoAnalysesKey`, `TestReviewItem_SavesAnalyses`. |
| `ChenWeb/server/api/doc-reviews/typst_report.go` | Report loader gains queries for the two new tables, joined into each artifact's section alongside its findings (ADR 2026062203 §1.2). |

## Operational Behaviors
- **No matches for a metric/item:** unchanged — no LLM call, no findings, no
  analyses.
- **`analyses` absent or empty in the LLM response** (still running under the
  `v2` prompts, or a model that ignores the instruction): the parser returns
  nil, the save function is not called. Findings behavior is unaffected.
- **No `run_id` in context, or no `db` handle:** save no-ops silently rather
  than failing the review.
- **Analysis persistence failure:** logged as a warning and swallowed — must
  not fail the reviewer's findings, which are the primary output.
- **Tool-use loop for other reviewers:** unaffected — `runToolUseReviewWithPayload`
  already exists and is reviewer-agnostic; adding two more callers changes
  nothing about its behavior or that of `runToolUseReview`'s 21 remaining
  callers (now 19, with provisions/metrics/inventory-items all migrated to
  the `WithPayload` entry point).

## Consequences

**Positive**
- Closes ADR 2026070602's "Intentionally left undocumented / open" item:
  metrics and inventory-items now retain comparison reasoning the same way
  provisions does.
- Gives ADR 2026062203 §1.2's per-artifact report design real data to render
  for all three reviewers, not only provisions.
- No change to the tool-use loop or any of its other callers — reuses
  `runToolUseReviewWithPayload` as-is.

**Negative / cost**
- Two more tables and two more prompt variants to maintain in parallel with
  provisions' equivalents; the three reviewers now carry near-identical
  analyses plumbing three times over rather than a shared implementation —
  accepted for the same reasons ADR 2026070602 accepted the `WithPayload`
  duplication (lower risk than a shared generic path today).
- Same silent-degradation risk ADR 2026070602 flagged: a model ignoring the
  `analyses` instruction degrades to "no analyses persisted" without failing
  loudly.

## Tests
- `TestParseMetricAnalysesJSON`, `TestParseInventoryItemAnalysesJSON` — parse
  a mixed `analyses` array, confirm an entry with an empty `summary` is
  dropped.
- `TestParseMetricAnalysesJSON_NoAnalysesKey`,
  `TestParseInventoryItemAnalysesJSON_NoAnalysesKey` — payload without an
  `analyses` key returns nil (backward compatible with `v2` prompt output).
- `TestReviewMetric_SavesAnalyses`, `TestReviewItem_SavesAnalyses` —
  sqlmock-backed, assert the exact `INSERT` into the new tables with `run_id`
  taken from context.
- `go build ./...` and `go test ./server/api/doc-reviews/...` clean after the
  change.

## Documentation Impact
- Resolves ADR 2026070602's open question about extending the `analyses`
  mechanism to metrics and inventory-items.
- Supplies the schema ADR 2026062203 §1.2 anticipated for
  `kb.doc_review_metric_analyses` / `kb.doc_review_inventory_item_analyses`.
- **Intentionally left undocumented / open:** none of DR1-DR3 is implemented
  yet (Status: Proposal). Once implemented, update this ADR's Status line to
  `Accepted — implemented` per this repo's convention.

## References
- [1] ADR 2026070602 — Provisions Reviewer: Mandatory Comparison Analyses
- [2] ADR 2026070603 — `kb.doc_review_findings`: `artifact_id` Column for Per-Artifact Reviewers
- [3] ADR 2026062203 — Document Review Report Generation (§1.2: Per-artifact report sections)
- [4] ADR 2026070201 — Document Review: Artifact Reviewer Context, Prompt-Cache Layout, and Missing-Metric Detection (AR4/AR5: tool-use and prompt-v2 groundwork for provisions/metrics/inventory-items)
- [5] ADR 2026063002 — Cross-Document Metric Consistency Reviewer
- [6] ADR 2026063005 — Cross-Document Inventory-Item Consistency Reviewer
