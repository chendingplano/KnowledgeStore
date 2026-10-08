# extract_metrics: kept-aside rows, decision model and the "a metric has a value" rule

**Date:** 2026-10-08 \
**Scope:** How `extract_metrics` now decides that a candidate is *not* a metric, where those
rows go, and why each rule exists. It records one long working session (records 416 and 753)
that changed these rules several times, so that the next person knows which rules are current,
which were tried and abandoned, and what was measured. Open this before changing how
`extract_metrics` filters rows.
**Code root:** `ChenWeb/server/api/doc-processing/` (`extract-metrics.go`, `metric_soft_drop.go`,
`metric_open_value_decision.go`), prompts in `ChenWeb/prompts/`

**Traceability — openspec:**
- `ChenWeb/openspec/changes/metric-row-soft-drop-decision-model/proposal.md`: why rows are kept
  aside instead of discarded, and why a decision model replaced a word list
- `.../design.md`: storage choice, pipeline order, the feasibility check of the decision model
- `.../tasks.md`: implementation log, including what was verified live and what was not
- `.../specs/metric-row-soft-drop/spec.md` and `.../specs/metric-open-value-decision/spec.md`:
  the requirements, including "A metric states a value". The change is not archived yet. **When
  behaviour changes, update these spec files, not just this doc.**

## Status (2026-10-09)

| Part | State |
|---|---|
| Kept-aside rows (`kb.metrics_dropped`), drop log, pages | committed (ChenWeb `ukzo`, page files in `mtsr`) |
| Decision model for open-value rows, policy v2, its three questions | committed (`ypto`, `mnyx`, `kuur`) |
| Prompts candidates v13 / enrich v10 (counts of procedure parts, unnamed quantities) | committed (`twlu`) |
| Prompts candidates v14 / enrich v11 (definitions) | committed 2026-10-09; defaults in code and pinned in `mise.local.toml` |
| "A metric has a value" check (`no_value`) | committed 2026-10-09, after a live re-run of 753 by the user; older tests updated to give their fixture rows a value |
| Gold rules (extract-metrics-benchmark) | **not changed**; rule A4 (metric with no value) now conflicts with the code |

## Summary

`extract_metrics` reads a standard and stores the measurable things it finds ("metrics") in
`kb.metrics`. An LLM proposes candidates (Pass 1), another LLM call fills each one in (Pass 2),
and a few fixed rules then decide what is stored. This session was about the candidates that
look like metrics but are not, as a domain expert would see them.

**Nothing is thrown away any more.** Before, a row the pipeline rejected was simply deleted, so a
wrong rejection was invisible. Now every rejected row is saved in a separate table,
`kb.metrics_dropped`, with the reason it was rejected and the full row. `kb.metrics` still holds
only accepted metrics, so search, reviews, indexing and the ontology work never see rejected
rows. Two pages can show them on request: Knowledge System → Metrics ("Show dropped") and the
Benchmark page (in the score report, which also flags a rejected row sitting on the same lines
as a gold metric the run missed, the sign of a wrong rejection).

**The rule that now decides most cases is simple: a metric has a value.** A row whose value is
empty is not stored as a metric; it goes to `kb.metrics_dropped` with reason `no_value`. This
was the user's decision after many rounds of trying to tell "good" value-less rows from "bad"
ones (see the history below). A named quantity without a value is at most a definition. This
includes formulas: "标准排热量 = (主测法 + 校核方法) / 2" defines a value but states none.
The check runs after Pass 2, because only Pass 2 produces complete rows to keep aside; filtering
earlier would have saved cost (Pass 1's value hint predicted the outcome perfectly on 416 and
753) but would have lost the rejected rows.

**The prompts also stop some false metrics earlier.** Pass 1 and Pass 2 now tell the model that
these are not metrics: a count of the document's own parts ("应使用两种试验方法", "分为四大类"); a duty to
provide something that names no quantity of it ("应根据…配备相应的设备和作业人员"); and a definition
of a term, wherever it appears ("量热计压力：量热容器的二次流体侧压力"). Real counts (samples,
measuring points, sets of readings) stay metrics.

**What a person can now do:** see why any row was rejected, find rejected rows on two pages,
and judge the extractor on real false positives instead of guessing what was deleted.

## History: what was tried, and why it changed

The order matters: several rules were replaced, and the reasons are not obvious from the code.

1. **416_mtc_3 (an agreed collection time and frequency) was stored as a metric.** A word-list
   check was added first (commit `pxwp`), then rejected by the user: which words mean "agreed"
   or "a schedule" differs by domain.
2. **Kept-aside rows and a decision model.** Instead of word lists, an LLM "decision model"
   (`jev_emulated`, devdoc 2026100502) answered one multiple-choice question per value-less
   requirement, using a versioned policy (devdoc 2026100503). Rows that are clearly metrics
   (with a number) never went to it. A feasibility check on 416 separated the cases cleanly.
3. **416_mtc_12/13 ("配备数量", provide suitable equipment and staff) were kept.** Cause: the
   first policy wrongly used this very clause as an example of a real metric. A fourth choice
   ("no quantity is named") never got picked. What worked was two extra yes/no questions:
   *does the clause name the quantity?* and *does it only require providing something?* Each
   failed alone (the first misread metrics whose context is a table heading, the second missed
   provision clauses); together they separated all 55 evaluation rows, with thin margins.
4. **416_mtc_16 (主体工艺, a process) was kept** because "not a quantity" answers were recorded
   but never acted on. That restriction came from mistakes on rows the model is never asked
   about; it was lifted.
5. **753_mtc_4 (试验方法数量 = 2) was stored.** Pass 1 had been told to propose every count. The
   fix (prompts v13/v10) says a count is a metric only through what it counts.
6. **753_mtc_1–9 (term definitions) were stored.** The Pass 1 rule "general concepts without
   measurable form" did not apply: a defined pressure *has* a measurable form. Prompts v14/v11
   exclude definitions. The first wording tied this to the "Terms and definitions" clause; the
   user pointed out that definitions appear anywhere, so it now describes the statement itself.
7. **The user set the principle "a metric has at least a value"** and asked for a deterministic
   check instead of more clever filtering. Numbers inside definitions (for example "high glide:
   glide over 3 K at 40 °C") are kept: experts disagree, and the user chose to be aggressive.
8. **Formulas without a value are not metrics either** (753_mtc_6). An exemption for formula
   rows was briefly in place and removed.

With rule 7 in place, the decision model no longer receives any rows: everything it judged was
a value-less requirement, and those are now rejected before it runs. Its code, policy and
settings are still there.

## Where things live

| What | Where |
|---|---|
| Pipeline order and each rejection stage | `extract-metrics.go` (`enrichMetricCandidates`): Pass 2 → tagged rows (`llm_tag`) → dedup → pure requirements (`statement_kind`) → **no value (`no_value`)** → decision model (`decision_model`) → save |
| Kept-aside rows | table `kb.metrics_dropped` (migration `project_migrations/20261008000001_create_kb_metrics_dropped.sql`): `drop_id` (`<record>_drp_<n>`), `drop_stage`, `drop_reason`, `decision`, full row as JSON |
| One log entry per run listing every rejected row | `kb.doc_proc_logs`, activity `drop_metric_rows` (replaced `exclude_pure_requirements`) |
| Decision model setup | `metric_open_value_decision.go`; profile `METRIC_DECISION_MODEL`; thresholds `METRIC_DECISION_DROP_MIN_P` (0.9), `METRIC_DECISION_PROVISION_MIN_P` (0.1); policy `metric_open_value_kind` in the shared decision-policy store (version 2 current), question wording in `prompts/prompt-metric-open-value-q-*.md` |
| Why a kept row was judged | `kb.metrics.ext_info.open_value_decision` (choice, probabilities, outcome, reason, reason_text) |
| Prompts in use | `prompts/prompt-extract-metric-candidates-v14.md`, `prompts/prompt-enrich-metrics-v11.md` (defaults in code and pins in `mise.local.toml`) |
| Pages | Knowledge System → Metrics, "Show dropped"; System Admin → LLM → Metrics → Benchmark, report section "Dropped rows" |
| Scoring | skill `score-extract-metrics` reads dropped pure requirements from `kb.metrics_dropped`, falling back to the old log for older runs |
| Rules in detail | coding capsule `KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-metrics-spec.md`, section 3.4.2 |

Rejection reasons a reader will meet in `kb.metrics_dropped.drop_reason`:

| Reason | Meaning |
|---|---|
| `no_value` | the row states no value (includes formulas and definitions without a value) |
| `inspection_requirement`, `delegated_requirement` | a requirement with nothing to measure, or whose criteria are in another document |
| `activity_schedule`, `not_a_quantity`, `no_named_quantity` | decision-model verdicts (now rarely reached) |
| `applicability_scope`, `formula_operand`, `procedure_count`, `term_definition`, … | Pass 2 tagged the row with its own rejection reason |

## Measured results (2026-10-08)

- **753 (GB/T 46121-2025, condenser test method):** 292 stored rows at the start of the
  session. With v14/v11 and the final no-value rule: about 108–112 rows, all with a value (the
  range is run-to-run variation). The terms-and-symbols sections dropped from 51 rows to 0–4;
  every value-less row went to `kb.metrics_dropped`. No row with a value was lost.
- **416 (DB33/T 2030—2018, rural waste sorting):** about 30 rows, all with a value. The rows
  that left were all value-less, including 比能耗, 发酵周期 and 单室体积.
- **Pass 1 value hint vs. Pass 2 value:** 111 of 264 candidates on 753 and 29 of 66 on 416 had
  no value hint; none of them got a value in Pass 2.

## Known limitations

- **Gold rules disagree with the code.** Gold rule A4 counts "a metric with no value" (for
  example 比能耗 to be declared by the manufacturer) as a metric. The code now rejects it, so
  benchmark scores for 416 fall until the gold rules get a new version and the gold runs are
  redone.
- **A real criterion written as a formula can be lost.** 753_mtc_89, "the test lasts at least
  τ ≥ (200 × Δt_i × C) / P", had its formula in the definition field and an empty value, so it
  is rejected. Pass 2 would have to put such a formula into the value field.
- **The decision model is idle but still configured.** Removing or repurposing it is a
  separate decision.
- **Run-to-run variation is large.** The same document gives noticeably different rows from run
  to run (one Pass 1 chunk sometimes returns nothing; a table may become one row with three
  values instead of three rows). Judge a change on repeated runs, not one.
- **Multi-value rows are not split.** A table of conditions (SC1/SC2/SC3) can become one row
  with "25; 25; 35". Detecting it is easy; splitting it correctly needs the table-row mapping.
  Not done.
- **Pass 1 ignores some exclusions.** Pass 1 v13 still proposed 753's "two test methods" in 5 of
  5 isolated runs; Pass 2 is what rejects it.
- **Rows saved before 2026-10-08 keep the old behaviour** until their document is re-extracted.
