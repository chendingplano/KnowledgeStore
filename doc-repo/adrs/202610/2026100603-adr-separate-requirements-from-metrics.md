# ADR 2026100603 — Separate Requirements from Metrics

**Date:** 2026-10-06 \
**Status:** Proposed \
**Component:** ChenWeb — `extract_metrics`, `extract_provisions`, `kb.metrics`, `kb.provisions`,
`kb.semantic_assertions`, `kb.assertion_relations`, metric ontology classes, customer-facing
metric/requirement pages, the `extract-metrics-benchmark` skill \
**Authors**: Chen Ding (with Claude) \
**Related:** ADR `2026072701` (referent identity, governed meaning, evidence-backed assertions),
ADR `2026081701` (ontology object classes and metric instances), ADR `2026081801` (lossless
semantic processing), devdoc `2026100601-devdoc-gold-metrics-416-review`, benchmark analysis
report `20261006-1311` (record 416, rules 2.0.0) \
**Tags**: metrics, requirements, provisions, ontology, extract_metrics, benchmark, vocabulary

## Change Logs
* 2026/10/06, ADR created (proposed). Prompted by the record-416 benchmark review: rows shown to
  customers as "metrics" are, to a domain expert, requirements.
* 2026/10/06, Review decisions: (1) existing records are out of scope, with no backfill or
  migration of current rows; (2) the requirement-to-metric link is a `provision_id` column on
  `kb.metrics`; (3) `extract_provisions` work is deferred to a later change. Updated DR2, DR4,
  Scope, Database Migrations, Implementation, Consequences and Tests accordingly.
* 2026/10/06, Phase 1 implemented (openspec change `requirements-metrics-phase1`): migration
  `20261006000005_add_provision_id_to_kb_metrics.sql`; evidence retired before re-extraction
  deletes metrics; statement-kind classifier and badge in the metric wiki, category panel, Metric
  Ontology Explorer search and metric detail groups. The benchmark delete sites were left
  unchanged: they cannot reuse `metric_id`, because the benchmark's own input is deleted with
  its metrics. The search and wiki responses now also carry the fields the classifier needs.
* 2026/10/07, Decision (user): pure requirements leave `kb.metrics` now, without waiting for
  `extract_provisions`; the provisions benchmark is deferred. Implemented by openspec change
  `exclude-pure-requirements-from-metrics`: prompts `extract-metric-candidates-v11` and
  `enrich-metrics-v8` stop asking for them, and a server-side filter
  (`server/api/doc-processing/metric_statement_kind.go`, same rules as the Phase 1 classifier)
  drops any `inspection_requirement` or `delegated_requirement` row before saving, logging each one
  to `kb.doc_proc_logs` (activity `exclude_pure_requirements`). Numeric criteria and value-open
  requirements stay. Updated DR4.
* 2026/10/08, Dropped rows are kept, not discarded (openspec change
  `metric-row-soft-drop-decision-model`, user decision): every row `extract_metrics` sets aside,
  including the pure requirements of DR4, is saved to the new table `kb.metrics_dropped`
  (`drop_stage`, `drop_reason`, full row as JSONB) and logged as one `drop_metric_rows` entry,
  which replaces `exclude_pure_requirements`. `kb.metrics` still holds only live rows. Two pages
  show dropped rows: Knowledge System → Metrics and the metrics Benchmark. The same change adds a
  decision-model check (`jev_emulated`, policy `metric_open_value_kind`) that sets aside
  value-open requirements which are only an activity's agreed time or frequency (gold rule X2).

## Context

### The question customers ask

Customers read our results as if a human expert had produced them. They do not see the processor,
the prompt or the benchmark rules. When they see a row such as

> 垃圾转运车辆密闭性 — 乡镇（街道）应配备密闭的垃圾转运车辆 (DB33/T 2030—2018, 5.2)

labelled as a *metric*, an expert's answer is: **this is a requirement, not a metric**. Nothing is
measured. It obliges a party to provide something, and "enclosed" is an inspectable feature of
that something. Calling it a metric makes the product look wrong.

### What experts mean by the two words

- A **metric** is a measurable property with a defined way of measuring it: a name, the kind of
  object it applies to, a unit or scale, and usually a method. *Total arsenic content, mg/kg,
  dry basis.* A metric on its own says nothing about what is good or bad.
- A **requirement** is a normative statement: something *shall* (应), *shall not* (不得), *should*
  (宜) or *may* (可) be so. It has a subject, a modality, an applicability condition and a source
  clause.

The two usually appear together. "总砷 ≤ 15 mg/kg" is a requirement whose criterion is stated on a
metric:

```text
requirement  — 成品肥料应达到表3要求          (who/what, shall, when, source clause)
  criterion  — ≤ 15                           (comparator + value)
    metric   — 总砷（As）, mg/kg, 以烘干基计   (measurable property)
```

### What the system does today

Strictly, **every row in `kb.metrics` that has `value_class = requirement` is a requirement**,
including the numeric ones. The numeric ones are requirements *on* a metric. The qualitative ones
are requirements with no metric behind them. The data model stores both in one record called a
metric. This is deliberate, not accidental:

- `prompts/prompt-enrich-metrics-v7.md` has a section "Do Not Drop Qualitative Requirements"
  ("still emit exactly one output row for it"). It defines `qualitative` as "a requirement about
  this property exists, but no number is given". For delegated requirements it tells the model to
  name the metric "the requirement as [object] + [what is required]".
- Live `kb.metrics` on 2026-10-06: 1,224 rows from 12 documents. 625 (51%) are `qualitative`, and
  `requirement` + `qualitative` is the largest single group (337). Another 158 rows are
  `definition` + `qualitative`.
- ADR `2026081701` builds metric **ontology object classes** on these rows. Each qualitative
  requirement therefore produces a provisional "metric class" such as *垃圾转运车辆密闭性* or
  *菌种种名*, which have no unit, no scale and nothing to compare. That ADR's 2026-08-17 survey
  found 55 of 182 auto-promoted metric terms were label-only. Requirement rows dressed as metrics
  are one source of empty classes.

At the same time, **a requirements store already exists and is underused**:

- `kb.provisions`, filled by `extract_provisions` (`server/api/doc-processing/extract-provisions.go`,
  prompt `prompt-extract-provisions-v3.md`), extracts "mandatory requirements, prohibitions,
  recommendations, permissions, and compliance constraints" with `provision_type`
  (`mandatory | recommended | optional`), subject and regulated objects.
- `server/api/ontology/assertions/provision_normalizer.go` turns provisions into semantic assertions
  with kinds `prov:required`, `prov:prohibited` and `prov:permitted`. Metric rows become `mea:*`
  kinds. The assertion layer already separates the two families.
- But `kb.provisions` holds only 168 rows from 2 documents (637, 638), while `kb.metrics` covers 12.
  The two families overlap in content and are not linked to each other. `kb.assertion_relations`
  (`assertion_id`, `related_assertion_id`, `relation_kind`) exists but has 0 rows.

### Evidence from the record-416 benchmark

The 69 gold rows for DB33/T 2030—2018 (run `20261006_121911`, rules 2.0.0, gpt-6.1-sol) sort as
follows when an expert reads them:

| What the row actually is | Rows | Example |
|---|---:|---|
| Requirement with a numeric criterion on a metric | 12 | 总砷 ≤ 15 mg/kg; GI ≥ 60%; ≥ 2 containers per household |
| Requirement that names a metric but leaves its value open | 7 | equipment shall state its specific energy consumption |
| Inspection requirement, no metric | 15 | vehicle enclosed; bin has a lid; no odour in the operating area |
| Requirement delegated to another standard | 17 | shall comply with CJJ 52 |
| Test-method setting | 15 | incubate at 25 ℃ for 48 h |
| Metric definition or interpretation scale | 3 | GI formula; GI < 100% means phytotoxic |

The document defines **about 15 distinct metrics** (germination index, the 8 fertilizer
indicators, container count, collection frequency and time, specific energy consumption,
fermentation cycle, chamber volume). It contains **51 product/process requirements** and
**15 test-method settings**. Today all 69 are presented as metrics.

### A related defect found while preparing this ADR

`kb.assertion_evidence` links metric instances by the string `metric_id` (e.g. `416_mtc_1`). For
the 2 records that have metric evidence (416 among them), every linked `kb.metrics` row was created (latest 2026-09-29) after its
assertion (2026-09-05 / 09-13). The `metric_id` strings are reused when a document is
re-extracted, so the evidence now points at different metrics: a qualitative requirement linked
to `mea:lower_bound_requirement`, a lower bound linked to `mea:upper_bound_requirement`, and so on.
The stale links on existing records are out of scope (see Scope). The reuse of `metric_id` must
still be fixed, so that new extractions link correctly (Phase 1).

### Scope

- **New extractions only.** Existing `kb.metrics`, `kb.provisions` and assertion rows are not
  migrated, backfilled or re-linked. They are replaced when a document is re-extracted.
- **`extract_provisions` is deferred.** Its prompt, its coverage (2 documents today) and how it
  runs alongside `extract_metrics` will be handled in a later change. This ADR fixes the target
  model now and states what waits for that change (DR4, Phase 2).

## Decision

Treat requirements and metrics as different things everywhere: in storage, in processing, in the
ontology and in what customers see. Link them where a requirement constrains a metric.

### DR1 — Adopt the expert definitions as the normative vocabulary

- **Metric**: a measurable property of a kind of object, with a unit or scale and, where stated, a
  method. It is a class-level concept: the ontology object class of ADR `2026081701`.
- **Metric value**: a stated value of a metric for a subject: an observation, a design capability,
  a target, or the criterion of a requirement. It is a metric instance (`mea:*` assertion).
- **Requirement**: a normative statement with modality, subject, condition and source clause. It
  is a provision (`prov:*` assertion).
- **Criterion**: the link from a requirement to a metric value that states what passes.

A row is called a metric only when there is a measurable property. "Must be enclosed", "must
comply with CJJ 52" and "must have a licence" are requirements without a metric.

### DR2 — `kb.provisions` is the system of record for every normative statement

Every normative clause in a document is captured as a provision, whether or not it has a number.
`kb.metrics` and `mea:*` instances hold only claims about measurable properties. Per ADR
`2026072701` DR7, each relationship has one owner store: the clause belongs to provisions; the
measurable value belongs to metrics.

A numeric requirement therefore produces **two linked records**:

```text
provision P  (prov:required)  "机器成肥产出的肥料…重金属限量应达到表3的要求"
   └─ constrains ─>  metric instance M (mea:upper_bound_requirement)  总砷 ≤ 15 mg/kg, 以烘干基计
                        └─ instance_of ─>  metric class  总砷（As）含量
```

The link is a new column **`kb.metrics.provision_id`**: a nullable reference to `kb.provisions.id`
naming the provision clause that the metric row is a criterion of. It is the authoritative link
(ADR `2026072701` DR7). One provision may be referenced by many metric rows (Table 3 gives five).
A metric row has at most one source provision. It is null for observations, design capabilities
and targets, which have no provision, and until linking runs.

At the assertion layer, normalization derives a `kb.assertion_relations` row with
`relation_kind = 'constrains'` from the provision assertion to the metric instance. That row is a
projection of `provision_id`, not a second owner. It is also where a metric value constrained by
more than one provision, for example the same limit repeated in another clause, is recorded.

### DR3 — Where each kind of current "metric" row belongs

| Current row | New home | Shown to customers as |
|---|---|---|
| Numeric requirement (`requirement` + bound/exact/range) | provision **and** metric instance, linked by `constrains` | a requirement, with its metric and criterion |
| Value left open / to be declared (`limit_absent`) | provision; a metric instance with value state "declared elsewhere" when the named parameter is a quantity | a requirement naming a metric whose value is set elsewhere |
| Qualitative inspection requirement (enclosed, lid, no odour) | provision only. The inspected feature may be recorded on the object's class contract (ADR `2026081701` DR3) as a feature, not as a metric class | an inspection requirement |
| Delegation to a standard (`reference`) | provision only, with the cited document as a structured reference | a requirement that points to another standard |
| Test-method setting (25 ℃, 48 h) | metric instance whose subject is the test method, tagged as a method parameter, linked to the provision that defines the method | a parameter of a named test method, not a product metric |
| Formula / metric definition | the metric class contract (how the metric is computed), not an instance | part of the metric's definition |
| Interpretation scale (GI < 100% = phytotoxic) | the metric class contract (interpretation bands) | part of the metric's definition |
| Observation, design capability, target | metric instance only | a metric value |
| Term definition, scope, slogan (`definition` + `qualitative`, 158 rows today) | neither; already excluded by benchmark rules 2.0.0 (X3/X5) | not shown |

### DR4 — `extract_metrics` extracts metrics; `extract_provisions` extracts requirements

- Remove the "Do Not Drop Qualitative Requirements" and delegated-requirement instructions from the
  next metric prompt version. `extract_metrics` emits a row only when there is a measurable
  property. A row for a numeric requirement keeps its comparator and value and gains a reference
  to the provision clause it came from.
- `extract_provisions` runs on every document that `extract_metrics` runs on. It owns qualitative,
  delegated and permissive clauses.
- The lossless invariant of ADR `2026081801` holds **across families**: a qualitative requirement
  removed from `extract_metrics` must be present in `kb.provisions`.
- Linking (DR2) is a deterministic step after both processors have run. It fills
  `kb.metrics.provision_id`, matching on source line span, subject and evidence. An LLM is used
  only for ambiguous cases (ADR `2026081701` DR12).
- **Amended 2026-10-07 for pure requirements.** Inspection and delegated requirements (the DR3
  rows that are "provision only") are no longer emitted or stored by `extract_metrics`, starting
  now. Each excluded row is logged (`kb.doc_proc_logs`, activity `exclude_pure_requirements`). The
  lossless-across-families invariant is knowingly suspended for these rows until
  `extract_provisions` runs reliably: until then they have no customer-visible home. The gate
  below still applies to everything else.
- **Gate: the rest of this DR waits for the `extract_provisions` change.** Running provisions on
  every document, linking (`provision_id`, `constrains`) and the per-document lossless check stay
  deferred. Until then, the requirement rows still stored in `kb.metrics` (numeric criteria and
  value-open requirements) are classified for display by the DR3 table (Phase 1), and
  `provision_id` stays null. (Before the 2026-10-07 amendment this gate also kept qualitative and
  delegated requirements in `extract_metrics`, so that nothing was lost.)

### DR5 — Customer-facing pages use the two words correctly

- Show **Requirements** and **Metrics** as separate lists. A requirement shows the metric(s) it
  constrains and its criterion. A metric shows its definition and every requirement that
  constrains it, across documents. This makes "which standards limit total arsenic, and how
  strictly?" answerable.
- Never label a provision-only row a metric. Test-method parameters are shown under their test
  method, not in the metric list.
- All new labels go through Paraglide in English and Chinese (ADR `2026093001`). Use 要求/规定 for
  requirement and 指标 for metric. Do not use 指标 for a requirement.

### DR6 — The benchmark measures both, separately

`extract-metrics-benchmark` gets a new major rules version (3.0.0) with two gold sets per
document: **gold metrics** (metric classes and values) and **gold requirements** (provisions,
with their `constrains` links). The `A2`/`A3` rows of 2.0.0 move to gold requirements. Scoring
reports metric recall/precision, requirement recall/precision and link accuracy separately.
Released 2.0.0 runs remain valid for scoring the current `extract_metrics`.

### Alternative Decisions

**AD1 — Keep the current model and relabel.** Leave requirements in `kb.metrics` and show
`value_class` to customers. Rejected: customers would still see "metric: 垃圾转运车辆密闭性", and the
ontology would keep creating metric classes with nothing to measure.

**AD2 — Add a `row_kind` flag to `kb.metrics`.** Cheaper: one column, one prompt change, and
filtering in the UI. Rejected as the end state because it puts two owner stores in one table
(ADR `2026072701` DR7) and duplicates `kb.provisions`. A display-time classifier with the same
effect, needing no column, is used while DR4 waits (Phase 1).

**AD5 — Link only through `kb.assertion_relations`.** Rejected (review decision). The link is
needed on the extraction record itself, before and independently of normalization. Customer pages
and the benchmark read `kb.metrics` directly. `provision_id` is the owner. The relation row is
derived from it.

**AD3 — Create a new `kb.requirements` table.** Rejected: `kb.provisions`, its prompt, its
normalizer and the `prov:*` assertion kinds already exist.

**AD4 — Treat pass/fail features as categorical metrics** ("enclosure: yes/no"). Quality
engineering sometimes calls these attribute data. Rejected for customer-facing metrics: an expert
reading a standard calls "vehicle shall be enclosed" a requirement. The feature is still recorded
on the class contract (DR3), so nothing is lost.

### Database Migrations

One Goose project migration in `ChenWeb/project_migrations` (follow the `db-migration` skill):

```sql
ALTER TABLE kb.metrics
  ADD COLUMN provision_id BIGINT NULL
    REFERENCES kb.provisions (id) ON DELETE SET NULL;
CREATE INDEX metrics_provision_id_idx ON kb.metrics (provision_id)
  WHERE provision_id IS NOT NULL;
```

- It references the surrogate `kb.provisions.id`, not the text `prov_id`. Like `metric_id`,
  `prov_id` is likely reused when a document is re-extracted (verify in Phase 1).
- `ON DELETE SET NULL`: re-extracting provisions must not delete metric rows. The metric row
  loses its link until linking runs again.
- No backfill. Existing rows keep `provision_id = NULL` (Scope).

Also in Phase 1: `kb.assertion_evidence` must reference metrics by a key that is not reused
across re-extraction. Register `constrains` as a governed relation kind.

Deferred to the `extract_provisions` change: a structured `modality` column on `kb.provisions`
(`provision_normalizer.go` parses modality from text today).

### Data Formats

The metric prompt's output loses the `qualitative` + `requirement` and `reference` shapes for
non-measurable clauses. It keeps `limit_absent` only for a named quantity. The provision output
may gain `constrains` hints (line span plus metric name) to help linking; that is part of the
deferred `extract_provisions` change. Exact JSON changes belong to the prompt versions written in
Phase 2.

### Environment Variables

None expected. If a cutover flag is needed, follow the `LOSSLESS_SEMANTIC_WRITES_*` pattern from
ADR `2026081801` and quote booleans in `mise.toml`.

## Implementation

### Phases

1. **Now — foundation.**
   - Add `kb.metrics.provision_id` (migration above).
   - Make `assertion_evidence` → `kb.metrics` links use a key that is not reused across
     re-extraction.
   - Add a display classifier that maps each metric row to its DR3 kind from `value_class`,
     `value_range_type` and tags. Customer pages use it to show requirement rows as requirements.
     It is computed at read time; no data is rewritten.
2. **With the `extract_provisions` change (deferred).**
   - Provisions run wherever metrics run.
   - New `enrich-metrics` and `extract-metric-candidates` prompt versions drop the
     qualitative-requirement instructions. *Done early (2026-10-07) for pure requirements: v8 / v11 plus the
     server-side filter; see the change log.*
   - The linker fills `provision_id` and derives `constrains` relations.
   - A per-document gate checks that every qualitative requirement in the old metric output is
     found in provisions before the old prompts are retired.
3. **Ontology.** Stop creating metric classes from provision-only rows. Move formulas and
   interpretation bands into class contracts.
4. **UI.** Separate Requirements and Metrics views as in DR5, in both languages. Before Phase 2,
   the Requirements view is fed by the Phase 1 classifier.
5. **Benchmark.** Release rules 3.0.0 (DR6). Re-run records 416 and 753.

### Code Changes

Expected areas: `server/api/doc-processing/extract-provisions.go`, the metrics processor and
`kbhandler/extract-metric-handler.go`, `server/api/ontology/assertions/` (normalizers, a new
linker), `server/api/ontology/semantic/provision_adapter.go`, `server/api/doc-benchmark/` (scorer
configurations for provisions and links), the metric ontology explorer and review pages in `web/`,
and `.agents/skills/extract-metrics-benchmark/rules/3.0.0.md`.

## Operational Behaviors

- A document is "processed" for this purpose only when both processors have run and linking has
  completed. Partial state is visible as such, not shown as a document with no requirements.
- Linking failures are semantic findings (ADR `2026081801` DR3), not processing failures. An
  unlinked numeric requirement is still shown, with its metric value, and flagged for review.

## Consequences

**Positive**

- Customers see the vocabulary an expert would use. Rows like "垃圾转运车辆密闭性 — metric" stop
  appearing.
- Metric classes become comparable across documents, because every one has something to measure.
  Fewer empty provisional classes.
- "Which requirements apply to X?" and "how is metric Y limited across standards?" become two
  well-defined queries.
- The benchmark stops arguing about whether a qualitative clause "is a metric". Each kind of
  statement has a gold set of its own.

**Negative / costs**

- Two processors per document instead of one: more LLM cost and a linking step to maintain.
- Until the `extract_provisions` change lands, requirements still live in `kb.metrics`. The
  separation is a display classification (Phase 1), not yet a storage one.
- Existing records are not migrated. Documents extracted before and after this change differ
  until they are re-extracted.
- `extract_provisions` has been run on only 2 documents. Its quality is unmeasured until it has a
  benchmark (DR6).
- Scorers and dashboards built on `kb.metrics` counts will see counts drop (record 416: 69 → about
  17 metric values — 12 numeric criteria and about 5 declared quantities — plus 15 method
  parameters). This must be explained as a definition change, not
  a regression.

## Tests

- Unit: the Phase 1 DR3 display classifier on table-driven rows; the migration (column, foreign
  key, `ON DELETE SET NULL` on provision re-extraction); the Phase 2 linker on fixtures (one
  provision → many metric rows; no match leaves `provision_id` null).
- Cross-family lossless check per document (DR4): every qualitative requirement in the old metric
  output appears in provisions (Phase 2).
- Benchmark: scores on records 416 and 753 under rules 3.0.0 for metrics, requirements and links.
- UI: Requirements and Metrics lists in English and Chinese. Text remains selectable.

## Documentation Impact

- **Changed knowledge:** the definitions of metric and requirement; the ownership of normative
  clauses (provisions); `constrains` as a relation kind.
- **To update:** `ChenWeb/KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-metrics-spec.md`,
  the provisions capsule (if one exists; otherwise create one), the user manual
  `metric-assertion-semantic-processing-v1.2-en.md`, the benchmark skill (`SKILL.md`,
  `USER_MANUAL.md`, rules 3.0.0, `CHANGELOG.md`), and ADR `2026081701` (cross-reference: metric
  classes are created only for measurable properties).
- **Becomes stale:** prompt `prompt-enrich-metrics-v7.md` (retired, not edited) and the record-416
  analysis reports' recommendations on A2/A3 handling (superseded by DR6).
- **Intentionally left undocumented here:** exact JSON shapes and migration SQL, which belong to
  the implementation plan and its openspec change.

## References

- ADR `2026072701` — DR5 (qualified assertions), DR7 (one owner store per relationship)
- ADR `2026081701` — DR1/DR3 (object class and contract), DR8 (semantic assertions as instances), DR12
- ADR `2026081801` — lossless invariant, semantic findings vs failures
- ADR `2026093001` — Paraglide standard
- `ChenWeb/prompts/prompt-enrich-metrics-v7.md`, `ChenWeb/prompts/prompt-extract-provisions-v3.md`
- `ChenWeb/server/api/ontology/assertions/provision_normalizer.go`
- `.agents/skills/extract-metrics-benchmark/analysis-reports/20261006-1311-metric-extraction-analysis-report.md`
- devdoc `2026100601-devdoc-gold-metrics-416-review`
