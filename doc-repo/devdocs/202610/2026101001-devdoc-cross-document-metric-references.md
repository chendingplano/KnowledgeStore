# Cross-document metric references — keeping references and resolving them to metrics

**Date:** 2026-10-10 \
**Status:** **Superseded 2026-10-10 by devdoc 2026101002 (`extract_references` processor).**
The user decided to keep `extract_metrics` unchanged (references stay dropped) and to handle
references in a separate processor. The review points below (R1 reference kinds, R4 document
identity, R5 definition targets, R6 stable keys, R7 review state, R8 policy) still apply and are
cited from 2026101002. The "keep reference rows in `extract_metrics`" design is not pursued.
**Scope:** How `extract_metrics` should treat a metric whose value, method or meaning lives in
another document, how such references are stored, and how they are linked to the actual metrics
of the cited document. Open this before touching cited-document handling, `kb.metrics_dropped`
reasons `delegated_requirement` / `no_value`, or gold rule X16.
**Code root (today):** `ChenWeb/server/api/doc-processing/` (`extract-metrics.go`
`excludePureRequirements`, `metric_soft_drop.go` `excludeRowsWithoutValue`,
`metric_statement_kind.go`), prompts `ChenWeb/prompts/prompt-enrich-metrics-v11.md`

**Related:** devdoc 2026100801 (soft drops and the "a metric has a value" rule), ADR 2026100603
DR3, spec `ChenWeb/openspec/specs/metric-statement-kind/spec.md`, benchmark rules
`.agents/skills/extract-metrics-benchmark/rules/6.0.0.md` (X14, X16, X18).

## Summary

Standards constantly point at other standards: "粪大肠菌群数应达到 GB 7959 的要求" (the limit is
in GB 7959), "额定功率按照 GB/T 755 确定" (the method is in GB/T 755). Today `extract_metrics`
throws these rows into the "dropped" pile, because this document gives no value of its own. That
is the right call for *this document's* metric list. But it loses something valuable: the link
between the metric here and the metric over there.

The plan is to keep those links. Each document's references to other documents go into one
table. When a reference is about a specific metric, a second table records which metric in the
cited document it points to. Linking works in both directions. When a document is processed,
its references are matched against cited documents that are already processed. Older documents
that were waiting for it are matched too. When the system cannot find a match it is sure of, it
does not guess. It marks the reference for a person to decide and shows the best candidates it
found.

The result: from any metric you can follow a reference to the metric that actually holds the
value, and from any standard you can see who relies on it.

## The proposal, as given

1. A table of the original references a document makes (normally document-level, sometimes
   chapter/section-level).
2. A metric-relation table: which metric is referenced by which metric.
3. Reference-type metrics are not dropped. They are kept in `kb.metrics`, marked as references,
   and their resolved targets are stored in the relation table.
4. When processing a document, for each reference metric: if the cited document was processed by
   `extract_metrics`, find the corresponding metrics. If none is confident enough, flag it and
   list the candidates for a human to decide.

The direction is sound and matches how standards are actually written. The review below accepts
all four points and adjusts how they are carried out.

## Review — what changes, and why

### R1. There are several kinds of reference, and only one of them is a metric

"References a metric in another document" covers different situations. They need different
handling:

| Kind | Example | What lives in the cited document | Row in `kb.metrics`? |
|---|---|---|---|
| **Value delegation** | 粪大肠菌群数应达到 GB 7959 的要求 | the limit of a named quantity | **Yes — a reference metric** (point 3) |
| **Method reference** | 含水率按 GB/T 9969 测定，应不大于 30% · 额定功率按照 GB/T 755 确定 | how the quantity is measured or determined | Only if the row is a metric for another reason (it has its own value). The reference becomes a relation. |
| **Definition reference** | 术语和定义见 GB/T 2900.1 | what a term means | No. Document- or section-level reference only. |
| **Blanket compliance** | 收运过程应符合 CJJ 184 | a whole document, no named quantity | No. Document- or section-level reference only. It is a provision, not a metric. |
| **Normative-reference list** | §2 规范性引用文件 entries | — | No. Document-level references (today rule X14 drops them silently). |

Only value delegation turns into a reference metric, because only there does the clause name a
quantity whose value exists, just not in this document. A blanket compliance clause names no
quantity. If it became a metric row it would have to link to *every* metric of the cited
document, which says nothing.

**The case that started this, 753_drp_49** (风扇电机的额定功率，按照 GB/T 755 确定), is a method
reference on a value declared by the manufacturer. GB/T 755 holds no value for this product
either, so the row stays dropped as `no_value`. Its citation of GB/T 755 is still recorded, as a
clause-level reference (R2).

Method references also occur on ordinary rows that **do** have a value ("按 GB/T 9969 测定，应不大于
30%"). Those rows are kept as normal metrics and get a `measured_per` relation. So relations come
from reference metrics *and* from normal metrics, not only from reference rows (refines point 2).

### R2. Record every citation, not only those that become metrics

The reference table (point 1) should hold every citation: the §2 normative list (document level),
section-level statements, and clause-level citations on metric rows. A citation found only on a
dropped row still goes there. It is the "who cites whom" index (point 1's purpose) and the place
where unresolved target documents are listed.

### R3. Resolution must run in both directions

Point 4 matches outgoing references against documents that are already processed. Documents are
processed in any order, though. When document B is processed, every earlier reference to B that
was waiting must be resolved too. Processing a document therefore does two passes: **outgoing**
(my references → processed targets) and **incoming** (waiting references → me).

### R4. Identifying the cited document is the first real problem

The cited identifier must be matched to a `kb.inputs` record before any metric can be matched.
Observed today:

- `cited_doc:` tags are written loosely: `GB/T755`, `GB/T 24634—2009`, `IEC60529`, `ISO 14253-1`.
- Some tags are not documents at all: `cited_doc:表2` and `cited_doc:附录B` (record 642) point
  inside the same document.
- `kb.inputs.doc_no` is filled for only **47 of 215** records, with mixed dash styles
  (`T/CI 140—2023`, `GB 3053-1993`). Record 753 (GB/T 46121-2025) has no `doc_no`, even though
  its filename carries the number.

Needed: one normalizer for document identifiers (prefix, number, part, year; `GB/T755` →
`GB/T 755`; `—`/`–`/`-` before a 4-digit year is the edition, while `-1` in `ISO 14253-1` is a
part number), a backfill of `doc_no` from title, filename and metadata, and edition rules. An
**undated** reference means the latest edition (GB/T 1.1). A **dated** reference means that
edition. If only another edition is processed, mark it `edition_mismatch` and offer that
edition's metrics as candidates. Never resolve to it silently.

### R5. Targets are often definitions, which the pipeline currently drops

For method and definition references, the matching item in the cited document is usually a
definition (GB/T 755 defines rated output and how to establish it). Since prompts v14/v11 and the
`no_value` stage, such items end up in `kb.metrics_dropped` (`term_definition`, `no_value`), not
in `kb.metrics`. So candidate search must look in `kb.metrics_dropped` as well, or the most
common targets will never be found. A relation must say which table its target is in.

### R6. Metric row ids are not stable across re-runs

`kb.metrics.metric_id` is positional, and the rows are rebuilt on every run (see
`persistCurrentMetricObjects` in `extract-metrics.go`). `kb.metrics_dropped.drop_id`
(`<rec>_drp_<n>`) is positional too. A relation that stores only row ids breaks the next time
either document is re-processed. Worse, a human's confirmed match would be lost. Each end of a
relation therefore also stores a **stable metric key**: a fingerprint of the record, section,
normalized metric name, subject and condition. After a re-run, relations are reattached by that
key. A confirmed relation whose key no longer exists becomes `stale` and is flagged, never
deleted silently.

### R7. "Flag the error" should be a review state, not a failure

An unresolved reference is a normal outcome. It is not a processing error. The run succeeds. The
reference is marked `needs_review`, its candidates (ranked, with scores) are stored, a WARN log
line is written, and the run's log reports the counts. A review list in the UI lets a person
confirm a candidate, pick another metric, or mark "no matching metric".

### R8. "Confident enough" must be a versioned policy, not a constant

Matching should reuse the existing decision infrastructure (`shared.decision_policies`, devdocs
2026100502 / 2026100503). Matching signals, strongest first:

1. A shared ontology term (`metric_definition_term_id`, `keyword_concept_id`).
2. A narrowed scope: if the clause names a table or clause of the cited document ("GB 7959
   表 1"), search only there.
3. Name, alias and subject match (Chinese and English).
4. Embedding similarity over `search_document` (bge-m3).
5. An LLM judge for the top candidates.

The thresholds are calibrated on real references, not chosen in advance.

### R9. Keeping reference rows touches other parts of the system

Rows with `value_class = reference` have no value of their own. Everything that reasons about
values must skip them or follow the link: class contracts and per-instance conformance, the
doc-review reviewers' counts, comparisons, and the metric explorer (which should show the link).
They also conflict with the current principle "a metric has at least a value" and with benchmark
**6.0.0 rule X16**, which excludes named-quantity delegations. Two consistent options:

- **(a, recommended)** Stay with the principle. A reference metric's value exists, only
  elsewhere, so "has a value" means "has a value here, or a reference to where it is". Write a
  new gold version that accepts named-quantity delegations as reference rows and scores them
  separately from valued metrics.
- **(b)** Keep reference rows outside the benchmark's scope entirely.

This is a user decision to make before the gold is revised.

## Details (proposed)

### Pipeline placement in `extract_metrics`

1. After Pass 2, **before** `excludePureRequirements`: classify citations on each row (value
   delegation / method / definition / blanket) and normalize each cited identifier. Pointers into
   the same document (`表2`, `附录B`, clause numbers) are not citations.
2. Rows that are a **value delegation of a named quantity** with a real document identifier are
   kept in `kb.metrics` (`value_class = reference`, statement kind `delegated_requirement`). They
   are exempt from the pure-requirement and `no_value` stages. Everything else follows the
   current rules.
3. Write every citation to `kb.document_references`, including the §2 normative list and
   citations on dropped rows. These rows are replaced on each run of the citing document.
4. **Outgoing resolution** for this document's references. **Incoming resolution** for waiting
   references whose cited identifier matches this document.
5. Log counts per state in the run log.

Prompts must emit the citation kind and tag method citations. Today 753_drp_49 carries no
`cited_doc:` tag at all, only `limit_absent`, and enrich v11 tells the model to emit no row for a
value delegation. New Pass 2 fields need Go changes, because the code appends a fixed schema and
drops unknown fields.

### Table 1 — `kb.document_references` (one row per citation)

| Column | Meaning |
|---|---|
| `id` | key |
| `citing_input_id` | `kb.inputs.id` of the citing document |
| `scope` | `document` · `section` · `clause` |
| `section`, `source_line_spans` | where the citation is |
| `cited_raw` | as written (`GB/T755`) |
| `cited_doc_key` | normalized identifier without year (`GB/T 755`) |
| `cited_edition` | year if dated, else null (undated = latest) |
| `reference_kind` | `normative_list` · `value` · `method` · `definition` · `blanket` |
| `cited_scope` | table or clause of the cited document, if named |
| `target_input_id` | resolved `kb.inputs.id`, null if unknown |
| `target_state` | `unknown_document` · `not_processed` · `processed` · `edition_mismatch` |
| `event_id`, `run_id`, `created_at` | provenance |

Cited documents that are `unknown_document` together form the list of documents worth acquiring
next.

### Table 2 — `kb.metric_relations` (one row per citing metric → candidate or resolved target)

| Column | Meaning |
|---|---|
| `id` | key |
| `document_reference_id` | the citation it came from |
| `relation_kind` | `value_delegated_to` · `measured_per` · `defined_by` (open for future kinds) |
| `citing_input_id`, `citing_metric_key`, `citing_metric_row_id` | stable key + current `kb.metrics.id` |
| `target_input_id`, `target_metric_key`, `target_table`, `target_row_id` | `target_table` is `metrics` or `metrics_dropped` |
| `status` | `candidate` · `resolved` · `needs_review` · `confirmed` · `rejected` · `stale` |
| `confidence`, `match_method`, `rationale` | `match_method`: `term` · `name` · `embedding` · `llm_judge` · `human` |
| `policy_id`, `policy_version` | the decision policy that scored it |
| `decided_by`, `decided_at` | set for `confirmed` / `rejected` |

The reference row's own state (`resolved` / `needs_review` / `pending_target`) is also kept in
its `kb.metrics.ext_info`, so list pages can show it without a join. Human decisions
(`confirmed`, `rejected`) survive re-runs through the stable keys (R6). A reference may resolve to
several metrics, for example one per condition or class, so the relation is one-to-many.

Schema changes go through goose migrations, and the tables are created at start-up per workspace
rules. `kb.assertion_relations` (semantic-assertion level) was considered and not reused: it links
assertions, not metric rows, and has no notion of an unresolved target document.

## Open decisions

- Option (a) or (b) in R9, and the new gold version that follows.
- Whether blanket compliance clauses with a cited **table** ("应符合 GB 7959 表 1") count as value
  delegation for every row of that table.
- Initial confidence thresholds. They will be calibrated once the first set of resolved
  references exists.

## Known limitations (by design)

- A reference resolves only to documents that are in `kb.inputs` and processed by
  `extract_metrics`. Everything else stays `pending_target` until that document arrives.
- Nothing is imported from the cited document: a reference row never copies the target's value
  into the citing document. The link is followed when read.
- Same-document pointers (`表2`, `附录B`) are out of scope. They are handled by the rows they
  point to.
