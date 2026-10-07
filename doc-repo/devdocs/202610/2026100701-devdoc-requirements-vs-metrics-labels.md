# Requirements vs. Metrics, Phase 1 — labels, provision link and evidence clean-up

**Date:** 2026-10-07 \
**Scope:** What ChenWeb now does to stop presenting requirements as "metrics": the labels
customers see, the new link column on `kb.metrics`, and the fix for evidence that pointed at the
wrong metric after re-extraction. Open this to understand the labels or before building Phase 2. \
**Code root:** `ChenWeb/web/src/lib/metric-statement-kind.ts`,
`ChenWeb/server/api/ontology/assertions/evidence_store.go`

**Traceability:**
- ADR `doc-repo/adrs/202610/2026100603-adr-separate-requirements-from-metrics.md`: the
  decision this implements (Phase 1 of 5), with the review decisions in its change log.
- OpenSpec change `requirements-metrics-phase1`, archived 2026-10-07:
  - `ChenWeb/openspec/changes/archive/2026-10-07-requirements-metrics-phase1/proposal.md`: why
    this exists
  - `ChenWeb/openspec/changes/archive/2026-10-07-requirements-metrics-phase1/design.md`: how it
    was built, the alternatives considered, and the additions made during implementation
  - `ChenWeb/openspec/changes/archive/2026-10-07-requirements-metrics-phase1/tasks.md`:
    implementation log, including what was verified in the browser and what was not
  - Specs (the contract): `ChenWeb/openspec/specs/metric-statement-kind/spec.md`,
    `ChenWeb/openspec/specs/metric-provision-link/spec.md`, and the evidence-retirement
    requirement in `ChenWeb/openspec/specs/metric-supporting-evidence-cardinality/spec.md`.
    **If behavior changes, update the spec, not only this doc.** This doc explains the feature
    for people. The spec is the contract for agents.
- Background: devdoc `2026100601-devdoc-gold-metrics-416-review.md` and benchmark report
  `.agents/skills/extract-metrics-benchmark/analysis-reports/20261006-1311-metric-extraction-analysis-report.md`.

## Summary

**The problem.** Our document processor pulls "metrics" out of standards documents. A domain
expert means something narrow by *metric*: a property you can measure, with a unit or a scale,
such as "total arsenic, mg/kg". Many of the rows we extract are not that. "Waste transfer
vehicles shall be enclosed" is a **requirement**: nothing is measured, someone checks that the
vehicle is enclosed. "Shall comply with CJJ 52" is a requirement that points at another standard.
In the standard DB33/T 2030—2018 (record 416), every one of the 45 extracted rows is, to an
expert, a requirement or a definition, yet the app called all of them metrics. Customers assume
the app speaks like an expert, so this made the product look wrong.

ADR 2026100603 decides to keep requirements and metrics apart in storage, processing and the
interface. Phase 1 is the part that could be done without changing how documents are processed.

**What Phase 1 does.**

1. **Every metric row now shows what it actually is.** A small label appears next to each row:
   *Requirement*, *Metric*, *Test parameter* or *Definition* (要求 / 指标 / 试验参数 / 定义 in
   Chinese). Hovering it gives the finer kind, for example "Inspection requirement (nothing to
   measure)" or "Requirement with a measurable criterion". The label is worked out when the page
   is shown, from fields the row already has. Nothing new is stored, so it applies to every row,
   old and new.

   | Label | Means | Example |
   |---|---|---|
   | Requirement: with a measurable criterion | A "shall" with a number on a measurable property | Moisture ≤ 30% |
   | Requirement: value set elsewhere | Names a measurable property but leaves the value open | Equipment shall state its energy consumption |
   | Requirement: inspection | A "shall" with nothing to measure | Bin shall have a lid |
   | Requirement: delegated | Points at another standard | Shall comply with CJJ 52 |
   | Test parameter | A setting of a test method | Incubate at 25 ℃ |
   | Definition | A formula, or a term definition | GI = … × 100% |
   | Metric | A stated or observed value | Measured 42 ℃ |
   | Unclassified | Not enough information | |

   An unrecognised row is labelled *Unclassified*, never *Metric*, because calling a requirement
   a metric is exactly the mistake this fixes.

2. **Metric rows can now point at the requirement clause they come from.** A new, optional
   column, `kb.metrics.provision_id`, links a row to its clause in the requirements table
   (`kb.provisions`). Nothing fills it yet. Filling it is part of Phase 2, which waits for the
   requirements extractor to be revisited. Existing rows were deliberately left alone.

3. **Old evidence no longer attaches itself to new metrics.** When a document is re-extracted,
   its metrics are deleted and renumbered from `<record>_mtc_1`. Supporting evidence for our
   semantic claims was linked by that number, so after a re-extraction it silently pointed at
   unrelated new rows (both records that had such evidence were affected). Now, before the
   metrics are deleted, their evidence is retired, and any claim that loses its last support is
   marked "unsupported" with the reason recorded. Records that were already wrong are not
   repaired. They heal the next time they are re-extracted.

## Where things live

- **What users see** (Knowledge Base area, `/home3/knowledge`):
  - **Metric wiki page**: label under the title.
  - **Metric Ontology Explorer → Search tab**: label on each row of a record's metric list and on
    each Global Metric Search result.
  - **Knowledge System → Metrics**: a "Statement kind / 陈述类型" line in a metric's detail
    panel, right after *Class*.
  - **Document Knowledge Base (category tabs)**: a "Statement kind" line in a metric's details.
- **Web code** (`ChenWeb/web/src/lib/`):
  - `metric-statement-kind.ts`: the classification rules. They are pure and tested in
    `metric-statement-kind.test.ts`, including all 69 rows of the record-416 benchmark.
  - `metric-statement-kind-labels.ts`: the English/Chinese label text.
  - `components/home3/statement-kind-badge.svelte`: the label itself.
- **Server code** (`ChenWeb/server/api/`):
  - `ontology/assertions/evidence_store.go`: `RetireMetricEvidenceForRecord`.
  - `doc-processing/extract-metrics.go`: `DeleteMetricsByInputRecordID`, which calls it before
    deleting.
  - `kbhandler/`: the metric list, detail, search, wiki and category responses now include the
    fields the label needs. The wiki response carries them in a small `statement` object read
    live, never cached.
- **Database:** migration `ChenWeb/project_migrations/20261006000005_add_provision_id_to_kb_metrics.sql`.

## Known limitations

- **The label is only as good as the extraction.** It reads what the processor stored. Rows the
  processor got wrong are labelled consistently with that mistake. For example, record 416's
  "population density" and "daily waste per person" come from a table's applicability column.
  They were stored as qualitative requirements, so they show *Requirement*, although they are
  really scope descriptions.
- **Test settings from production extraction show as requirements.** Only the benchmark tags test
  settings today, so values such as "25 ℃ incubation" from live extraction show as
  *Requirement: with a measurable criterion* rather than *Test parameter*.
- **Some requirements still live in the metrics table.** Phase 1 changes what people see, not
  where things are stored. Since 2026-10-07 (openspec change
  `exclude-pure-requirements-from-metrics`), new extractions no longer store *inspection* or
  *delegated* requirements as metrics. Those rows are dropped and logged to `kb.doc_proc_logs`
  (activity `exclude_pure_requirements`). Requirements with a measurable criterion or an open
  value are still stored and labelled here. Records extracted earlier keep their old rows until
  they are re-extracted with force-clear. `provision_id` stays empty until Phase 2.
- **No server-side filtering or counting by kind.** The classification runs in the browser. Admin
  views other than the metric detail panel are unchanged.
- **Evidence clean-up is forward-only.** It runs when metrics are deleted for re-extraction. It
  does not repair links that were already stale, and benchmark clean-up is not covered because it
  cannot reuse metric numbers.
- **Not checked in the browser:** the category panel label (its data was verified through the
  API). The other views were checked in English and Chinese on 2026-10-07.
