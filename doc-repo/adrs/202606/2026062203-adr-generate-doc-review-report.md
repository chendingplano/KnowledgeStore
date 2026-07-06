# 1. Overview
- Document review requests are stored in `kb.doc_review_requests`
- Document review findings are stored in `kb.doc_review_findings`
- Document review reports are stored in `kb.doc_review_reports`

Workflow on generating document review reports:
- Input: `kb.doc_review_requests.id`
- Language: if not specified, defaults to DOC_REVIEW_REPORT_LANGUAGE
- Initiated when a document review request is finished.
- Retrieve the report (JSON) from `kb.doc_review_reports`
- Use the Typst template (refer to [1]) to create the report by the review report (JSON). The English and Chinese finding content is already generated and stored in `kb.doc_review_findings.metadata`, so use those localized values to create two reports, one in English and one in Chinese. Save them to DOC_REVIEW_REPORTS/`yyyymmdd-hhmm-` + `kb.doc_review_runs.id` + '-report-en.typ'/'-report-cn.typ'. The env var DOC_REVIEW_TEMPLATE_FILENAME defines the template file name.
- Convert the Typst files to PDF, using the same file names but with '.pdf'

Report finding rendering:
- Each finding card title must identify the persisted finding row, not only its ordinal position in the report. Render the title as `'Finding-' + kb.doc_review_findings.id`, for example `Finding-42`.
- Legacy report JSON without a finding row ID may continue to render an ordinal fallback such as `Finding F-03`.
- For the `metrics`, `provisions`, and `inventory_items` reviewers, findings are not rendered as a flat list — see 1.2 for per-artifact grouping and how each reviewer's comparison analyses are compiled into the same section as its findings.

Cross-document metric evidence:
- Metric consistency findings must identify the matched metric record in prose by `kb.metrics.metric_id`, for example `diaryMac.docx (refer to 415-mtc-2) specifies 48小时 ...`.
- The finding description must not rely on the filename alone when referencing a conflicting peer metric. It should include the matched metric ID, the referenced value/unit, and enough location context to let a reader find the source.
- The finding description must not inline-dump `source_context` lines. The prompt should return `related_artifact_id` and `related_record_id`; the report renderer uses those IDs to fetch the matched metric's `source_line_spans`.
- Render referenced matched metric lines as a separate source-style block, using the same visual treatment as "Related Source Lines": context lines before, highlighted referenced line(s), and context lines after. For metrics, include the matched metric's line span and the available +/- 10 surrounding source lines as `line_number: content`.

## 1.1 Artifact-based review LLM message contract

The artifact consistency reviewers configured in `ChenWeb/doc-review.local.toml`
under `[reviewers.metrics]`, `[reviewers.provisions]`, and
`[reviewers.inventory_items]` do not ask the LLM to read the full document from
the beginning. Each call is centered on one extracted artifact and a bounded set
of related artifacts from other records.

The message sent to the LLM has two parts:

1. Source-window prefix: when the artifact's `source_line_spans` can be mapped
   to the current document's line file, the reviewer sends the canonical
   scheduler window as `<DOCUMENT_INPUT>`. This is the same `{"doc_context": ...,
   "lines": [...]}` envelope used by per-chunk reviewers, usually around 200
   lines, and it is selected by the first line of the artifact under review.
2. Artifact review task: the reviewer appends the prompt text plus an
   `# ARTIFACT REVIEW INPUT` JSON object. The JSON always contains:
   - the artifact under review as name-value fields;
   - `artifact_line_spans`, copied from the artifact under review;
   - a matched-artifact array (`matching_metrics`, `matching_provisions`, or
     `matching_items`);
   - `context_truncated: true` only when the artifact span crosses the selected
     source-window boundary.

When tool use is enabled, the same user message is wrapped as:

```text
<DOCUMENT_INPUT>
{source-window JSON}
</DOCUMENT_INPUT>

<REVIEW_TASK>
{prompt text}

# ARTIFACT REVIEW INPUT
{artifact payload JSON}
</REVIEW_TASK>
```

When no source window is available, the task is still sent, but without the
`<DOCUMENT_INPUT>` block.

### 1.1.1 Metrics reviewer

`[reviewers.metrics]` uses `prompt-review-metrics-v2.md`,
`max_tool_turns = 4`, and `tools = ["get_artifact_context"]`.

For each metric under review, the reviewer retrieves candidate metrics by live
hybrid search, metric-category siblings, and entity-linked metrics. Each matched
metric is resolved by `metric_id` back to `kb.metrics` before it is included in
the LLM payload.

The metric payload shape is:

```json
{
  "metric_under_review": {
    "metric_id": "1001_m_7",
    "metric_name": "最大工作压力",
    "metric_name_en": "maximum working pressure",
    "metric_subject": "管道系统",
    "metric_subject_en": "pipeline system",
    "metric_desc": "pressure limit under normal operating conditions",
    "metric_context": "applies to the pressure test section",
    "metric_value": "1.6",
    "metric_unit": "MPa",
    "metric_unit_en": "MPa",
    "value_data_type": "number",
    "value_range_type": "single",
    "value_class": "maximum",
    "value_class_en": "maximum",
    "formula_or_definition": "",
    "threshold_or_target": "",
    "measurement_frequency": "",
    "location_type": "table",
    "table_name_or_section": "Table 3",
    "metric_categories": ["pressure", "pipe-spec"],
    "source_line_spans": ["120-124"]
  },
  "artifact_line_spans": ["120-124"],
  "matching_metrics": [
    {
      "metric": {
        "metric_id": "2002_m_3",
        "metric_name": "最大工作压力",
        "metric_subject": "管道",
        "metric_value": "2.5",
        "metric_unit": "MPa",
        "value_class": "maximum",
        "metric_categories": ["pressure", "pipe-spec"],
        "source_line_spans": ["88-90"]
      },
      "source_record_id": 2002,
      "source_filename": "GB_50316_pipe_design.pdf",
      "source_doc_authority": "standard",
      "match_via": "hybrid_search",
      "match_rank": 1,
      "source_context": [
        {"line_number": 78, "content": "..."},
        {"line_number": 88, "content": "matched metric source line"}
      ]
    }
  ]
}
```

`source_context` is pre-attached for matched metrics. It is composed from the
matched metric's source document as 10 lines before `source_line_spans[0]`, all
actual lines covered by `source_line_spans`, and 10 lines after
`source_line_spans[0]`. If the matched document's line file cannot be loaded, the
reviewer keeps the resolved metric fields and omits usable context rather than
failing the whole review.

### 1.1.2 Provisions reviewer

`[reviewers.provisions]` uses `prompt-review-provisions-v2.md`,
`max_tool_turns = 4`, and `tools = ["get_artifact_context"]`.

For each provision under review, the reviewer retrieves candidate provisions by
live hybrid search and entity-linked provisions. Each matched provision is
resolved by `prov_id` back to `kb.provisions` before it is included in the LLM
payload.

The provision payload shape is:

```json
{
  "provision_under_review": {
    "prov_id": "1001_prv_3",
    "prov_name": "Pressure relief requirement",
    "provision_type": "requirement",
    "provision": "The system shall include a pressure relief valve rated for at least 1.6 MPa.",
    "provision_subject": "pressure relief",
    "category_paths": ["safety/pressure", "equipment/valve"]
  },
  "artifact_line_spans": ["88-90"],
  "matching_provisions": [
    {
      "provision": {
        "prov_id": "2002_prv_9",
        "prov_name": "Relief valve rating",
        "provision_type": "requirement",
        "provision": "A pressure relief valve rated for 2.5 MPa shall be installed.",
        "provision_subject": "relief valve",
        "category_paths": ["safety/pressure"],
        "source_line_spans": ["188-190"]
      },
      "source_record_id": 2002,
      "source_filename": "GB_50316_pipe_design.pdf",
      "source_doc_authority": "standard",
      "match_via": "hybrid_search",
      "match_rank": 1,
      "source_context": [
        {"line_number": 178, "content": "..."},
        {"line_number": 188, "content": "matched provision source line"}
      ]
    }
  ]
}
```

`source_context` is pre-attached for matched provisions. It is composed from the
matched provision's source document as 10 lines before `source_line_spans[0]`,
all actual lines covered by `source_line_spans`, and 10 lines after
`source_line_spans[0]`. The LLM should call
`get_artifact_context(record_id, artifact_id)` with `source_record_id` and
`prov_id` only when the included context is missing or insufficient to verify
scope, conditions, or exact normative wording.

### 1.1.3 Inventory items reviewer

`[reviewers.inventory_items]` uses `prompt-review-inventory-items-v2.md`,
`max_tool_turns = 4`, and `tools = ["get_artifact_context"]`.

For each inventory item under review, the reviewer retrieves candidate items by
live hybrid search, item-category siblings, and entity-linked inventory items.
Each matched item is resolved by `inventory_item_id` back to
`kb.inventory_items` before it is included in the LLM payload.

The inventory-item payload shape is:

```json
{
  "inventory_item_under_review": {
    "inventory_item_id": "1001_inv_3",
    "item_name": "球阀",
    "canonical_name": "ball valve",
    "manufacturer": "Acme Valve Co.",
    "brand": "AcmeFlow",
    "model_number": "BV-2200",
    "part_number": "PN-50-316",
    "item_categories": ["valve", "pipe-fitting"],
    "standards": ["GB/T 12237"],
    "normalized_specs": [{"name": "nominal_diameter", "value": "50", "unit": "mm"}]
  },
  "artifact_line_spans": ["210-212"],
  "matching_items": [
    {
      "item": {
        "inventory_item_id": "2002_inv_7",
        "item_name": "球阀",
        "canonical_name": "ball valve",
        "manufacturer": "Beta Industrial",
        "brand": "AcmeFlow",
        "model_number": "BV-2200",
        "part_number": "PN-50-316",
        "item_categories": ["valve"],
        "standards": ["GB/T 12237"],
        "normalized_specs": [{"name": "nominal_diameter", "value": "65", "unit": "mm"}],
        "source_line_spans": ["330-332"]
      },
      "source_record_id": 2002,
      "source_filename": "GB_12237_valves.pdf",
      "source_doc_authority": "standard",
      "match_via": "hybrid_search",
      "match_rank": 1,
      "source_context": [
        {"line_number": 320, "content": "..."},
        {"line_number": 330, "content": "matched item source line"}
      ]
    }
  ]
}
```

`source_context` is pre-attached for matched inventory items. It is composed
from the matched item's source document as 10 lines before
`source_line_spans[0]`, all actual lines covered by `source_line_spans`, and 10
lines after `source_line_spans[0]`. The LLM should call
`get_artifact_context(record_id, artifact_id)` with `source_record_id` and
`inventory_item_id` only when the included context is missing or insufficient to
verify variants, configurations, or exact spec table values.

### 1.1.4 `get_artifact_context` tool return contract

`get_artifact_context` is the cross-record, read-only source-line tool available
to `[reviewers.metrics]`, `[reviewers.provisions]`, and
`[reviewers.inventory_items]`.

Tool arguments:

```json
{
  "record_id": 2002,
  "artifact_id": "2002_m_3"
}
```

`record_id` is the matched artifact's `source_record_id`. `artifact_id` is the
artifact-family ID: `metric_id`, `prov_id`, `inventory_item_id`, or `entity_id`.

When the artifact is found, the tool returns:

```json
{
  "found": true,
  "record_id": 2002,
  "artifact_id": "2002_m_3",
  "artifact_type": "metric",
  "line_spans": ["88-90"],
  "lines": [
    {"line_number": 78, "content": "..."},
    {"line_number": 88, "content": "matched artifact source line"}
  ]
}
```

`artifact_type` is one of `metric`, `provision`, `inventory_item`, or `entity`.
`line_spans` are read from the artifact's source table:
`kb.metrics.source_line_spans`, `kb.provisions.source_line_spans`,
`kb.inventory_items.source_line_spans`, or `kb.entities.line_spans`.

`lines` contains source document lines loaded from the matched record's line
file. For every parsed span, the tool includes up to 10 lines before the span
start, the span lines themselves, and up to 10 lines after the span end, in
document order. The response is capped at 120 lines. The LLM must use these
lines only as verification evidence; findings should cite the matched artifact
by returning `related_artifact_id` and `related_record_id`, not by dumping the
tool output into `description`.

When the artifact ID is unknown for the requested record, the tool returns:

```json
{
  "found": false,
  "record_id": 2002,
  "artifact_id": "missing_id"
}
```

### 1.2 Per-artifact report sections (metrics, provisions, inventory items)

The report renders `metrics`, `provisions`, and `inventory_items` findings as
three separate parts of the report, one per reviewer — findings from
different reviewers are never merged into a shared section. Within each
reviewer's own part, the report groups by the artifact under review rather
than rendering a flat, ordinally-numbered finding list:

- `kb.doc_review_findings.artifact_id` (ADR 2026070603) identifies which
  artifact-under-review a finding is about, for these three reviewers only.
  Each reviewer's part of the report groups its findings by `artifact_id`, so
  all findings about the same metric/provision/inventory item render together
  as one section, titled by the artifact's own ID (`metric_id`, `prov_id`, or
  `inventory_item_id`).
- Each reviewer also persists a comparison-analysis record per matched
  candidate, independent of whether a finding was raised on it — one row per
  entry in `matching_metrics` / `matching_provisions` / `matching_items`.
  Provisions' table (`kb.doc_review_provision_analyses`) was introduced by ADR
  2026070602; the same mechanism extends to `kb.doc_review_metric_analyses`
  and `kb.doc_review_inventory_item_analyses` for the metrics and
  inventory-items reviewers, resolving that ADR's open question. All three
  tables are keyed by `input_record_id` + `run_id` + the reviewer's own
  artifact-ID column (`prov_id` / `metric_id` / `inventory_item_id`), matching
  the key used to group findings above.
- Within an artifact's section, the report loads that artifact's analyses
  rows and finding rows using the same grouping key and renders them
  together: analyses first (one line per matched candidate — related
  artifact, relationship, summary), followed by that artifact's findings, if
  any. An artifact's analysis and its findings are always compiled into the
  same section — never split across different parts of the report.
- The `entities` reviewer and the text-chunk reviewers (P1-P4) have no
  `artifact_id` or analyses table; their findings continue to render in the
  existing flat/ordinal sections, unaffected by this grouping.
- The metrics and inventory-items analyses tables/migrations follow ADR
  2026070602's `kb.doc_review_provision_analyses` schema shape (`id`,
  `input_record_id`, `run_id`, own-artifact-ID column, `related_artifact_id`,
  `related_record_id`, `relationship`, `summary`, `create_time`); their
  migrations and reviewer/prompt changes (mirroring that ADR's DR1-DR3) are
  defined in ADR 2026070604 (Status: Proposal as of this writing — not yet
  implemented).

# 2. References
[1] ChenWeb/docs/doc-templates/template-document-report.typ

[2] 2026062202-adr-document-report-template.md

[3] ADR 2026070602 — Provisions Reviewer: Mandatory Comparison Analyses (`KnowledgeStore/doc-repo/adrs/202607/2026070602-adr-doc-reviewer-provisions.md`)

[4] ADR 2026070603 — `kb.doc_review_findings`: `artifact_id` Column for Per-Artifact Reviewers (`KnowledgeStore/doc-repo/adrs/202607/2026070603-adr-doc-review-findings-artifact-id.md`)

[5] ADR 2026070604 — Metrics and Inventory-Items Reviewers: Mandatory Comparison Analyses (`KnowledgeStore/doc-repo/adrs/202607/2026070604-adr-doc-reviewer-metrics-inventory-analyses.md`)
