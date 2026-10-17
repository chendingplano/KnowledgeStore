A metric is a quantitative, measurable item used to evaluate, compare, monitor, verify, or assess something. Metrics are often defined in standards, specifications, requirements, policies, test plans, scorecards, or compliance documents.

A requirement with nothing to measure is not a metric (ADR 2026100603 DR1). "The bin shall have a
lid" (an inspection requirement) and "shall comply with CJJ 52" (a requirement delegated to
another document) are requirements; `extract_metrics` does not store them (see 3.3.1 and 3.4.2).
A requirement that names a measurable property is extracted with its criterion ("总砷 ≤
15 mg/kg").

**A metric has at least a value** (user decision, 2026-10-09). A row that states no value is not
stored as a metric, whatever it names: a quantity whose value is left open ("设备应标明比能耗"), a
definition, a formula ("标准排热量 = (主测法 + 校核方法) / 2") or a quantity listed to be recorded. It
is set aside to `kb.metrics_dropped` with reason `no_value` (3.4.2). This replaces the earlier
treatment of value-open quantities as metrics (gold rule A4), which the gold rules still have.

**A metric is identified by its subject (the object), its property and its condition** (user
decision, 2026-10-16). The condition is everything the source states that limits when, where, for
whom or how the value holds: applicability (population, category, size class, variant), environment
and operating state, test method or apparatus, location or body site, load, input level or time
point. The same property of the same object under two conditions is two metrics, even with the same
value: GB/T 44700 clauses 6.5.14.1 (运动模拟装置) and 6.5.14.2 (模拟物) state the same test settings
and give two rows each. Each row holds one value (3.3.1, "Conditions and one value per row").

This processor uses a multi-pass extraction strategy.

## 1. Input

- `record_id`: the value of `kb.inputs.id`
- `chunks`: see the chunking spec
- file name

## 2. Implementation

- The code is in `ChenWeb/`
- It may use functions/modules in `shared/`

## 3. Multi-Pass

Single-pass design asks one LLM call to do all of the following at once:

- detect metric mentions
- decide whether each candidate is a real metric
- infer the final normalized metric schema
- translate fields
- generate category paths
- implicitly handle overlap cleanup and dedup

This caused:

- unstable extraction counts
- duplicate metrics from overlapping chunks
- prompt/schema overload on smaller models
- malformed or partial JSON outputs
- weak deterministic cleanup

### 3.1 Multi-Pass Pipeline

To solve the single-pass problem, we will use multi-pass pipeline, which
breaks the processing into multiple passes:

1. Pass 1: extract metric candidates from each chunk
2. Deterministic Step A: merge and deduplicate candidates across overlapping chunks
3. Pass 2: enrich candidates into final metric rows, batched by chunk (see `METRIC_ENRICH_GROUP_SIZE`)
4. Deterministic Step B: final metric dedup before persistence

### 3.2 Incremental Processing
Incremental processing is documented in [10]. Since 2026-10-16 the merge treats the condition as
part of a metric's identity: `metricsIdentical` (including its resolved-concept shortcut, since a
concept names the property, not the metric instance) and `metricStaticMatch` require equal
normalized conditions (an empty and a non-empty condition differ), `metricMergeComparedFields`
lists `condition`, the merge-resolve payload carries `condition`, and
`prompt-merge-resolve-metrics-v2.md` (env `METRIC_MERGE_RESOLVE_PROMPT`) says a different
condition is a different metric. Normalization as in 3.4.

### 3.3 Pass 1: Metric Candidates

Pass 1 uses:

- model env: `EXTRACT_METRIC_CANDIDATES_MODEL_NAME`
- prompt env: `EXTRACT_METRIC_CANDIDATES_PROMPT`

Optional fallback:

- `EXTRACT_METRIC_CANDIDATES_MODEL_FALLBACK`

Pass 1 output:

```json
{
  "language": "string",
  "candidates": [
    {
      "candidate_id": "48_1",
      "metric_name_hint": "string",
      "subject_hint": "string",
      "evidence_quote": "string",
      "source_line_spans": ["12", "13:15"],
      "unit_hint": "string",
      "value_hint": "string",
      "condition_hint": "string",
      "confidence": 0.0,
      "confidence_reason": "string"
    }
  ]
}
```

`candidate_id` rules:

- format: `<chunk_id>_<seqno>`
- `chunk_id` is the source chunk sequence number used by the metrics processor
- `seqno` starts at `1` within that chunk's Pass 1 candidate list
- this ID is human-readable and is used as the lineage key between Pass 1 candidates and later final metrics/logs

Pass 1 rules:

- maximize recall for plausible metric candidates
- do not generate the full final metric schema
- do not generate category paths
- do not translate
- do not keep overlap-only candidates unless the same metric is supported by normal lines
- do not extract a requirement with nothing to measure: an inspection requirement, or a clause
  whose criteria live only in a cited document (e.g. "应按照 CJJ 27 的要求配置…") (see 3.3.1)
- emit one candidate per stated quantity, including plain counts in dense test-method clauses
  (samples, replicates, blank controls), and check every normal line of the chunk, not only
  its tables (since candidates prompt v12); since v13 (2026-10-08) a count is evidence of a
  metric only through what it counts (3.3.1)
- do not extract a definition: a statement that only says what a term, quantity or symbol means,
  wherever it appears (a definitions clause, a symbol list, a "式中" explanation, a note or running
  text), unless it comes with its own criterion (since candidates v14, 3.3.1)
- in a data dictionary, emit one candidate per data element for its data format and allowed
  occurrences, never for the value the field will hold (since candidates v15, 3.3.1)
- since candidates v16 (2026-10-16, 3.3.1): put the object in `subject_hint` and its qualifiers
  in `condition_hint`; in a table whose columns give different properties of one item (value,
  resolution, permitted error) every filled cell is a candidate, and a cell holding values for
  different conditions gives one candidate per value; a limit written as a fraction or multiple of
  another limit is a value; a requirement value inside a narrative table cell is a candidate;
  cells of a data set (records, simulated subjects, example cases) are not candidates
- since candidates v19 (2026-10-16, 3.3.1): a number that only qualifies another value of its
  clause (a paired load, an apparatus grade, a restated setting) is that value's `condition_hint`,
  not a candidate; a limit equal to another limit ("不应大于允许误差的绝对值") is a candidate with
  `value_hint` 1 倍

#### 3.3.1 Requirements With Nothing To Measure

Since candidates prompt v11 / enrich prompt v8 (2026-10-07, openspec change
`exclude-pure-requirements-from-metrics`), neither pass asks for a *pure requirement*: a
requirement with no measurable property. Two shapes are excluded:

| Statement kind | Example |
|---|---|
| `inspection_requirement` | "垃圾桶应加盖", "shall be clearly legible" |
| `delegated_requirement` | "应按照 CJJ 27 和 GB 16889 的要求配置…设施", "shall comply with CJJ 52" |

These belong to `kb.provisions` (ADR 2026100603 DR2/DR3). Until `extract_provisions` runs
reliably on every document, an excluded requirement is kept only in `kb.metrics_dropped`
(`drop_stage = statement_kind`) and the `drop_metric_rows` log (3.4.2, 3.7).

Still extracted:

- a requirement with a numeric criterion (`lower_bound`, `upper_bound`, `exact`, `range`)
- a requirement that names a measurable quantity but leaves its value open or to be declared
  (`limit_absent`): still extracted by the prompts, but set aside as `no_value` (3.4.2)
- a clause that states its own number and cites a document only for the test method
- a numeric value quoted from a cited document (`value_class = reference`)

**Value left open** (`limit_absent`, since candidates v12 / enrich v9, 2026-10-07). A quantity
with a unit or scale whose value the document leaves open is a metric with no value, not a
pure requirement: a value to be declared ("设备应明确比能耗、发酵周期"), to be sized by another
factor or by design ("应根据垃圾日处理量合理设置单室体积"), or agreed between parties for a
property of the object or process. Enrich v8 dropped these as obligations; record 416 lost
比能耗, 发酵周期 and 单室体积 that way (score run 1). This matches gold rules ≥ 5.0.0, rule A4.
**Superseded 2026-10-09:** such rows have no value, so the deterministic `no_value` stage (3.4.2)
sets them aside; the prompts still produce them so the full row reaches `kb.metrics_dropped`.

Also not extracted (since v12 / v9), matching gold rules X2, X5, X13 and D1: a named property
whose value comes only from a cited document ("粪大肠菌群数应达到 NY 884"); a pointer to a
table of the same document ("其他指标应达到表2和表3"); a number that only scopes which objects a
clause applies to ("容积在50立方米以下的户用沼气池应符合 NY/T 90"); an agreed time or frequency
of an activity; the operands of a formula the document gives; and a practice, method, record
or feature, which is never `limit_absent`.

**Counts and named quantities** (candidates v13 / enrich v10, 2026-10-08). A count is a metric
only when it counts what the test is performed on or observes, or the parts the object consists
of (samples, specimens, replicates, measuring points, sensors, sets of readings, components). A
count of the document's own parts (methods, procedures, steps, modes, definitions, terms,
concepts, categories, clauses) is not: record 753 stored 753_mtc_4 "试验方法数量 = 2 种" from
"应使用两种试验方法测量排热量". Pass 2 drops it with reason `procedure_count`. An open value must also
be named by the clause itself: "应根据…配备相应的设备和作业人员" names no quantity (gold X7, 416's
配备数量 rows); Pass 2 reason `no_named_quantity`. Both reasons are drop-reason tags (3.4.2). On
2026-10-08 Pass 1 v13 still emitted the 753 method count in 5/5 isolated runs; the drop is made
by Pass 2.

**Definitions** (candidates v14 / enrich v11, 2026-10-09). A statement that only says what a term,
quantity or symbol means is not a metric, wherever it appears: a definitions clause ("3.7 量热计压力：
量热容器的二次流体侧压力", record 753 stored nine such rows), a symbol or abbreviation list, a "式中"
explanation under a formula, a note or running text. It states no value, limit or criterion, even
when the term is a measurable quantity with a unit; the quantity is a candidate where the document
sets or asks for its value. A definition with its own criterion ("含水率是指…，应不大于 30%") is
still a candidate for that criterion, and a number inside a definition (高滑移: 冷凝温度为 40 °C 时滑移温度
超过 3 K) is kept (experts disagree; the user chose to keep such rows). Pass 2 reason
`term_definition`. The Pass 1 rule "general concepts without measurable form" did not cover these:
a defined pressure has a measurable form. The rule was first written for the terms-and-definitions
clause only; it describes the statement, not its location, because definitions appear anywhere.
Since candidates v23 / enrich v21 (2026-10-17, benchmark rules 6.7.0) the kept number must limit a
property measured on the document's own object (高滑移 classifies the refrigerant by its glide). Also
`term_definition`: a category boundary of the people or things the object is for (GB/T 44700 4 注 1,
"3 周岁～6 周岁为幼儿…": nothing on the test equipment is compared with it; the category stays a
`condition`, `适用人群：幼儿`) and a counting, naming or unit convention ("采用跳绳绕轴360°计一圈的方法计数").
A value required of a person, sample or population ("受试者年龄应为 3 周岁～6 周岁") is still a metric.

**Data dictionaries** (candidates v15 / enrich v12, 2026-10-15). In a data dictionary,
data-element catalogue, message or dataset specification the data element is the object, and its
metrics are the constraints the document states on it: the data format when it contains a number
("a..50", "n4..5,1") and the allowed occurrences ("1", "0..1", "1..n"). Pass 1 emits one candidate
per element, with both constraints in `value_hint`; Pass 2 turns it into one row per constraint
(tags `data_format`, unit 位, and `occurrence_count`, unit 次; `value_class = requirement`; the
format kept whole, its comparator taken from the length part). Not rows: the element's own
measured value (身高, cm: no value is stated), a format with no number (YYYYMMDD; the element still
gets its occurrence row), the obligation M/O/C alone, code lists and their meanings
(`term_definition`), the notation clause and its examples (`term_definition`), and the document's
own identifiers and group ranges (`document_identifier`). Matches gold rules 6.3.0 §2.5. Before
this, record 376 (GB/T 40423, a 322-element catalogue) read every element as a value-open
quantity, so all of them were set aside as `no_value`; 41 of its 42 stored rows were notation
examples, codes and identifier ranges. Score 1 (log run 204) → 99 (log run 208) against gold run
6.3.0 `20261015_064942`; on 416 and 753 the new rules never fired. Still open on 376: a printed
misprint is copied as written (`nl` for `n1`, `n3..4.1`), where gold stores the notation's reading;
test settings inside a description or code meaning (连续测量 3 次, 餐后 2 小时) are mostly missed.

**Conditions and one value per row** (candidates v16 / enrich v13 / merge-resolve v2,
2026-10-16, openspec change `extract-metrics-conditions` [13]). Before this change the
doc-processor path never stored a condition: the Pass 2 schema the model was told to use, the
parser and the INSERT all lacked it (0 of 2,383 rows). The model wrote qualifiers into the subject
("身高测试仪(计)（幼儿）") or merged values ("男300 mm、女250 mm"). Now:

- `condition` / `condition_en` hold the stated qualifiers (definition in the introduction), as
  labelled parts `<kind>：<value>` joined by `；` (English `<kind>: <value>` joined by `; `), e.g.
  `适用人群：幼儿；称量≤50 kg`. `subject` names only the object. A table column or sub-header that
  qualifies a row (a population column, 四肢 / 躯干) is a stated condition of every value in that
  row. Not a condition: the object, the comparator or value, a cited document, the measurement basis
  (dry basis), or where a method is a good choice. Never inferred
- `metric_value` holds one value: one number, interval `a~b`, tolerance `±x` or `a±b`. Values for
  different conditions become one row each (男 300 / 女 250); a list of settings or check points
  (10、30、50 mm) one row per value; a cell naming several properties (底座 300 mm×300 mm；高度
  550 mm) one row per property; every filled property column of a table row (规格 | 分度值 |
  允许误差) one row each
- notation: a symmetric tolerance `±x` is `upper_bound` with the ± kept (gold rules ≥ 6.1.0);
  `metric_value` never contains the unit or a comparator (`5~25` with unit s, not `5 s~25 s`)
- **data sets**: a table of records, samples, simulated subjects, example cases or
  input/expected-output pairs is data, not a requirement; its candidates are dropped with reason
  `dataset_record`, and a column is never summarised into a min~max range. Record 371's informative
  Table E.1 (体脂率模拟测试参数库) had produced 75 such rows. Since candidates v24 / enrich v22
  (2026-10-17) a data set is defined by its rows being records of individual cases, and a table
  that prescribes the values a test, its apparatus or a reference standard must have (one row per
  model, grade or setting: 371's 表 3 标准电阻模型阻值) is kept cell by cell with the row as
  condition. The v16–v23 wording ("parameter library … reference data table") made the candidates
  pass skip Table 3 entirely in most runs (0–1 of 6 on the production chunk; 6/6 with v15 and v24)
- **pass criteria vs test settings**: a value that sets the pass criterion of a requirement on the
  product (a load it must withstand, a tilt at which it must stay upright) is a `requirement` with
  its bound and no `test_condition` tag ("倾斜 10° 时不应翻倒" → `lower_bound` 10); a value that only
  says how a test is run keeps `test_condition`

The deterministic step in 3.4.2 enforces the notation rules the model misses. On record 371
(GB/T 44700—2024, re-extracted 2026-10-16, not yet scored against gold 6.4.0): 410 of 483 rows carry
a condition, 102 of 103 ranges have endpoints, all 77 `±x` rows are `upper_bound`, and no row holds
its unit, several values or Table E.1 data. Remaining errors: the model sometimes repeats the
property as a qualifier (`测量部位：座板高度`) or carries one clause's apparatus into the parallel
clause. Matches gold rules 6.4.0 §3 (Conditions).

**Numbers that qualify another value; relative limits** (candidates v19 / enrich v16, 2026-10-16,
user rulings from the record 371 review; ChenWeb jj `qpwu`). Earlier prompts asked for a candidate
for every number, so record 371 stored three numbers that only qualify another value:
- 371_mtc_21: B.1.4 静载荷力 300 N, stored next to the 8 mm deflection row that already carried it
  as its condition
- 371_mtc_76: 6.5.4.1 量块等级 5
- 371_mtc_92: the second 倾斜 10° of 6.4.2.1

Now:

- a number that only says under which load, input, grade or arrangement ANOTHER stated value of the
  same clause holds or is checked goes into that value's `condition`, not into a row of its own:
  - a load paired with a criterion → the criterion's condition (`静载荷力：300 N`)
  - an apparatus grade → the apparatus qualifier (`试验装置：5 等量块`)
  - the same setting stated again in the same clause → one row

  Pass 2 drops the extra candidate as `not_a_metric:condition_of:<candidate_id>` or
  `duplicate_of:<candidate_id>`. A number the clause sets in its own right stays a row, even next
  to other values: a loading width, an apparatus accuracy, a number of readings, the tilt of the
  plane the product is placed on, or a load the product must withstand when the pass criterion
  has no number.
- a limit stated relative to another limit is a value: "多次测量结果之差不应大于该类测试器材所允许误差的绝对值"
  (5.5.2 repeatability, 371_mtc_8) → 重复性, `metric_value` 1, unit 倍, `upper_bound`, condition empty
  ("对于同一测量数据，多次测量" describes the property). It is a requirement of its own, never
  `delegated_requirement` or `duplicate_of`, like the earlier "表 1 规定误差的 1/10" → 1/10 倍.

These match gold rules 6.5.0 (§3 "Numbers that qualify another value", A1/D1). The 6.4.0 gold run
`20261016_085615` predates them: it records 5.5.2 as D1, so 371_mtc_8 scores as a false positive
there, and its gold_282 lacks the 5 等量块 qualifier. Not yet verified by a live re-extraction.

**Row conventions** (enrich v9): every test, sampling or analysis setting carries the
`test_condition` tag (kind `test_parameter`, 3.4.2), but definition rows never do; when a
clause gives different meanings to ranges of one value ("发芽指数小于100%…大于100%…"), each
range is its own `definition` row tagged `interpretation_bound` (+ `strict_bound`).

The prompts are not trusted alone: the deterministic filter in 3.4.2 drops any pure requirement
the model still returns.

**Earlier rows.** Candidates prompt v10 / enrich prompt v7 deliberately kept delegated
requirements as metric rows (`value_hint` `ref:…`, `confidence_reason` `external_reference:…`,
`value_class = reference`, `value_range_type = qualitative`, tags `external_reference` and
`cited_doc:<identifier>`), and earlier enrich prompts kept qualitative requirements. Records
extracted before 2026-10-07 keep those rows until they are re-extracted with `force_clear`.

Pass 2 batching:

- Candidates that share the same source chunk are grouped into one LLM call
- Batch size is controlled by `METRIC_ENRICH_GROUP_SIZE` env var (default: 5)
- A batch is never cut between candidates that quote the same evidence (same first-mention
  `source_line_spans` and normalized `evidence_quote`, typically the cells of one table row), so a
  batch can exceed the size by the rest of that run (`groupCandidatesByChunk` /
  `candidateEvidenceKey`, 2026-10-16). Reason: in record 371 (log run 221, group size 10) the Table 1
  走平衡木 row's candidates 8_40 | 8_41, 8_42 fell into two batches; the call holding only 8_40
  (计时 0~100 s) also emitted the row's 分度值 and 允许误差 as 计时分度值 / 计时允许误差, and the
  other call emitted 分度值 / 允许误差. Final dedup (3.4) keys on the name, so both pairs were stored
  (371_mtc_313/315, 314/316). Since enrich v16, a candidate whose `value_hint` names one cell
  yields only that cell's row
- The batch prompt sends all candidates and source lines once, reducing repeated input tokens
- Each batch returns a `metrics` array covering all candidates in that batch
- Since enrich prompt v9, every row carries its `candidate_id`, and each candidate that yields
  no row is listed in `dropped_candidates` (`{"candidate_id", "reason"}`, reasons such as
  `delegated_requirement`, `own_table_pointer`, `applicability_scope`, `activity_schedule`,
  `formula_operand`, since enrich v10 `procedure_count` and `no_named_quantity`, since enrich v12
  `document_identifier`, since enrich v13 `dataset_record`, and since enrich v16
  `not_a_metric:condition_of:<candidate_id>`). A candidate
  that is neither is logged as a warning (3.7)

Pass 2 uses:

- model env priority:
  - `ENRICH_METRICS_MODEL_NAME`
  - `EXTRACT_METRICS_MODEL_NAME`
- prompt env priority:
  - `ENRICH_METRICS_PROMPT`
- semantic search env:
  - `SEARCH_SEMANTIC_ENABLED`
  - `METRIC_CONNECT_MAX_LINKS` (default: 10)
- index env:
  - `ARTIFACT_WEB_DIR`

Pass 2 output:

```json
{
  "language": "string",
  "metrics": [
    {
      "candidate_id": "48_1",
      "metric_name": "string",
      "metric_name_en": "string",
      "source_line_spans": ["12", "13:15"],
      "subject": "string",
      "subject_en": "string",
      "desc": "string",
      "desc_en": "string",
      "context": "string",
      "context_en": "string",
      "keywords": ["string"],
      "keywords_en": ["string"],
      "location_type": "sentence|bullet|table_row|table_cell|heading_context|mixed",
      "unit": "string",
      "unit_en": "string",
      "metric_value": "string",
      "value_data_type": "string",
      "value_range_type": "string",
      "value_class": "string",
      "value_class_en": "string",
      "formula_or_definition": "string",
      "value_min": 0.0,
      "value_max": 0.0,
      "condition": "string",
      "condition_en": "string",
      "threshold_or_target": "string",
      "measurement_frequency": "string",
      "metric_categories": ["string"],
      "confidence": 0.0,
      "is_explicit_metric": true,
      "table_name_or_section": "string",
      "reasoning_tags": ["string"]
    }
  ],
  "uncertain_metrics": [],
  "dropped_candidates": [{"candidate_id": "48_2", "reason": "applicability_scope"}]
}
```

Important notes:

- one output row = one metric = one value under one condition
- `value_min` / `value_max` are numbers for `range` rows only; `condition_en` is empty for English
  documents. The batch prompt's "use exactly this schema" block (`buildMetricRelationBatchPrompt`)
  must list every field the processor stores: before 2026-10-16 it omitted `condition`,
  `value_min` and `value_max`, so the model never returned them
- use only the merged candidate and its supporting evidence
- each final metric row should carry the originating `candidate_id` when the processor can determine a unique source candidate
- `uncertain_metrics` may be returned by the LLM but are not persisted to `kb.metrics`
- `metric_categories` must contain one or more category keys suitable for lookup in `kb.artifact_categories`
- category paths are not generated or stored by the enrichment pass

### 3.4 Deterministic Step B: Final Metric Dedup

`dedupeFinalMetricRows` deduplicates the enriched metric rows before persistence.

**Dedup key** — built by `normalizedMetricCandidateKey` over five fields (each lowercased, trimmed, and whitespace-collapsed, then joined with `|`), plus the condition:

1. `metric_name`
2. `subject`
3. `unit`
4. `metric_value`
5. normalized `source_line_spans` joined with `,`
6. `|condition=` + `metricConditionKey` (since 2026-10-16): the condition with full-width forms
   folded, lower-cased, all whitespace removed and `;` written as `；`. Without it, rows that
   differ only in condition (握力测试仪 分度值 1 N for 幼儿 and for 成年人, same table line) would
   merge once the population moved out of the subject

`source_line_spans` normalization (`normalizeSourceLineSpans`):
- Accepts string spans (`"12"`, `"13:15"`), bare `float64` integers, or `{"line_number": N}` objects
- Discards zero/negative line numbers
- Sorts spans by start then end
- Merges adjacent or overlapping spans (gap ≤ 1) into a single span
- Returns canonical strings: `"N"` for single lines, `"N:M"` for ranges

**Merge behavior for duplicates** (same key, multiple rows):
- `source_line_spans`: union of both rows' spans (no duplicates; order is preserved from first-seen row then appended new spans)
- `metric_categories`: union of both rows' category keys (no duplicates; order is preserved from first-seen row then appended new keys)
- `confidence`: keeps the higher value between the two rows

**Output order**: first-seen order (insertion order of the first occurrence of each key).

#### 3.4.1 Metric IDs
Metric IDs are defined as `<record_id>` + '_mtc_' + `<seqno>`, where `<seqno>` is a sequence number, starting from 1.

`metric_id` and `candidate_id` are different:

- `candidate_id` identifies the Pass 1 candidate within a chunk
- `metric_id` identifies the persisted row in `kb.metrics`
- `candidate_id` links the pre-persistence candidate logs to the persisted/final metric logs

#### 3.4.2 Dropped Rows (Soft Drop) and the Open-Value Decision

Since 2026-10-08 (openspec change `metric-row-soft-drop-decision-model`, specs
`metric-row-soft-drop` and `metric-open-value-decision`) no row is discarded. A row the pipeline
sets aside is saved to `kb.metrics_dropped`, never to `kb.metrics`, so every reader of
`kb.metrics` sees live rows only. Four stages set rows aside, in this order:

| Stage (`drop_stage`) | Where | Rows | `drop_reason` |
|---|---|---|---|
| `llm_tag` | per enrich batch, `dropRowsTaggedWithDropReason` | `reasoning_tags` hold `applicability_scope`, `formula_operand`, `activity_schedule`, `own_table_pointer`, `procedure_count`, `no_named_quantity`, `term_definition`, `document_identifier`, `dataset_record`, `obligation_no_property`, `inspection_requirement`, `delegated_requirement` or `qualitative_requirement` (the LLM emitted a row it should have listed in `dropped_candidates`) | the tag |
| `statement_kind` | after dedup, `excludePureRequirements` | kind `inspection_requirement` or `delegated_requirement` | the kind |
| `no_value` | after that, `excludeRowsWithoutValue` (`metric_soft_drop.go`) | `metric_value` empty or a placeholder (`-`, `—`, `/`, `N/A`, `无`), whatever the row's class, tags or formula | `no_value` |
| `decision_model` | after that, `judgeOpenValueRows` | kind `requirement_value_open` answered `activity_schedule` or `not_a_quantity` with p ≥ `METRIC_DECISION_DROP_MIN_P` (default 0.9), or whose clause names no quantity of what it only requires providing (below) | `activity_schedule`, `not_a_quantity` or `no_named_quantity` |

The `llm_tag` rows are deduplicated with `dedupeFinalMetricRows` (overlapping chunks), like live
rows. Steps after dedup, inside `enrichMetricCandidates` (shared by the sequential and
chunk-batch save paths, for `force_clear` true and false):

1. canonicalize `value_range_type` (`canonicalizeMetricValueRangeTypes`), then normalize value
   notation (`normalizeMetricValueNotation`, `metric_value_notation.go`, since 2026-10-16) on live
   and tagged rows (it also runs on the sequential save path and in `FinalizeChunkBatch`):
   - remove copies of the row's own unit written next to a number (`5 s~25 s` → `5~25`), only
     when the unit is not followed by a letter or `/` (次 in 次/min stays) and the result is a plain
     value
   - remove one leading comparator from a single number (`≥500` → `500`); an `exact` or empty
     range type takes the comparator's bound, and a strict one (>, <, 大于, 小于) adds
     `strict_bound`
   - `±x` with `exact` or `range` → `upper_bound` (`a±b` and asymmetric tolerances unchanged)
   - a `range` row without both endpoints gets them from `a~b` / `a-b` / `a±b`
   - a value still holding several numbers joined by `、 ； ; ，` or 男…女 is left unchanged and
     listed in the run's `multi_value_rows` log (3.7); `/` is not a separator because it is part of
     units

   Notation only: splitting a multi-value row needs the model
2. classify each row with `metricStatementKind`
   (`server/api/doc-processing/metric_statement_kind.go`) and set aside pure requirements
3. set aside every row without a value (`no_value`). A formula without a value is a definition,
   not a metric (753_mtc_6), so formulas are not exempt
4. judge the remaining `requirement_value_open` rows (below). Since step 3 these rows have no
   value and are already set aside, so the decision model receives no rows; it is kept,
   configured, for a later decision
5. at save time, live rows get `metric_id`s and set-aside rows get `drop_id`s; one
   `drop_metric_rows` log entry lists the set-aside rows (3.7)

**Open-value decision** (`server/api/doc-processing/metric_open_value_decision.go`). A requirement
whose value is left open is either a quantity of an object (gold rule A4, e.g. 比能耗 由设备明确,
抗压强度由供需双方商定: a metric) or the time, frequency or method of an activity that parties must
agree or announce (X2, e.g. 收运单位应与集中供餐单位约定餐厨垃圾收运的时间和频次: not a metric). No
word list can tell them apart across domains, so a decision model judges it. Only rows of kind
`requirement_value_open` are judged; every other kind is decided deterministically, and a unit
does not exempt a row (收运频次 can carry 次/日).

- Model: the `.models.toml` profile named by `METRIC_DECISION_MODEL`, run through
  `jev_emulated` (an `llm` profile) or `jev_compatible` (a `decision-model` profile) by
  `server/api/decisionmodel` (shared with the Decision Model Playground). Must return logprobs:
  no reasoning models.
- Policy: current version of decision policy `metric_open_value_kind` (`shared.decision_policies`),
  seeded from `prompts/prompt-metric-open-value-policy-v2.md` when missing (v2 is current since
  2026-10-08; v1 listed clause 8.2.2 of record 416 as an `object_quantity` example, wrongly).
  Revise it as a new version in the Playground, not in code.
- Request: one per row, state `{"policy", "row": {metric_name, subject, threshold_or_target,
  desc, context}}`, three questions: `kind` (`choice`: `object_quantity`, `activity_schedule`,
  `not_a_quantity`), `named` (`noul`: does the source clause itself name the row's quantity?) and
  `provision_only` (`noul`: does the clause only require providing something, naming no quantity
  of it?). The `named` and `provision_only` wording is in
  `prompts/prompt-metric-open-value-q-named-v1.md` and `...-q-provision-v1.md`; moving it into the
  policy made the answers worse. Usage events: `PromptName = metric_open_value_kind`,
  `CallReason = extract_metrics`.
- Drops: `activity_schedule` or `not_a_quantity` with p ≥ the threshold (`not_a_quantity`, e.g.
  主体工艺 among 运行技术参数, gold X13); or `no_named_quantity`: P(named) ≤
  1 − threshold and P(provision_only) ≥ `METRIC_DECISION_PROVISION_MIN_P` (default 0.1). The
  second catches X7 rows such as 416's "配备数量" (应根据…要求，配备相应的设备和作业人员: the clause
  names no number of equipment or staff). Neither question alone is safe: `named` is low for real
  quantities whose `context` is only a table heading (641/642 design dimensions), and
  `provision_only` misses some provision clauses; the veto keeps the first kind
  (`reason = no_named_quantity_vetoed`). Margins on the 2026-10-08 evaluation (55 rows): real
  metrics P(provision_only) ≤ 0.06, provision rows ≥ 0.14. `not_a_quantity` was record-only until
  2026-10-08: its misfires on real quantities (GHG emission reductions, 零位误差) were all on
  qualitative rows, which are never judged; on judged open-value rows it never took a real metric.
- Every judged row records `{model, profile, policy_id, policy_version, questions, choice,
  choice_meaning, probabilities, named, provision_only, examined, outcome, reason, reason_text,
  threshold, provision_min_p, statement_kind, judged_at}`
  (plus `error`): in `kb.metrics_dropped.decision`, or in `kb.metrics.ext_info.open_value_decision`
  for kept rows. A row with `ext_info.open_value_decision` was examined; `outcome` is `kept` or
  `dropped` and `reason` says why: `activity_schedule_confident`, `not_a_quantity_confident` or
  `no_named_quantity_confident` (dropped), `object_quantity`, `no_named_quantity_vetoed`,
  `activity_schedule_below_threshold`, `not_a_quantity_below_threshold`, `decision_error`, or
  `decision_model_not_configured` (`examined = false`). Rows saved before this field set
  (2026-10-08 09:00 run) carry only model, policy, choice and probabilities.
- A failure never drops a row and never fails the run: unset model, missing policy or a failed
  call keeps the row, records the error and logs a warning.

The word-list check `isAgreedActivitySchedule` (commit `pxwp`, 2026-10-08) was removed by this
change.

The classification rules are those of spec `metric-statement-kind`, applied in this order after
trimming and lower-casing (numeric = `lower_bound`, `upper_bound`, `exact`, `range`):

1. tag `test_condition` → `test_parameter`
2. `value_class = definition` → `metric_definition` with a non-empty `formula_or_definition`, else `definition`
3. `value_class = reference`, or a `cited_doc:` / `external_reference` tag → `metric_value` if numeric, else **`delegated_requirement`**
4. `value_class` `requirement` / `target` → `requirement_with_criterion` if numeric, `requirement_value_open` if `limit_absent`, else **`inspection_requirement`**
5. `value_class` `observation` / `design_capability` → `metric_value` if numeric, else `observation`
6. otherwise → `unclassified`

The same rules exist in `web/src/lib/metric-statement-kind.ts` (display labels) and the
`extract-metrics-benchmark` helper `benchmark_io.py` (gold `kind:` tags). Change all three
together.

Set-aside rows get no `metric_id`, so live rows are numbered without gaps. They are numbered
`<record_id>_drp_<seqno>`, continuing after the record's highest drop id (merge mode appends);
`DeleteMetricsByInputRecordID` (force_clear) deletes the record's `kb.metrics_dropped` rows too,
so drop ids restart at 1. A merge-mode run leaves earlier live and dropped rows in place, and
records extracted before 2026-10-07 keep their pure-requirement rows until re-extracted.

`kb.metrics_dropped` columns: `id`, `input_record_id`, `drop_id`, `candidate_id`, `drop_stage`,
`drop_reason`, `decision` (JSONB), `row_data` (JSONB, the full enriched row; JSONB so the table
does not drift when `kb.metrics` gains columns), `event_id`, `created_at`. Only two pages read it:
Knowledge System → Metrics (`GET /kb/metrics?include_dropped=true`, rows marked `dropped`, with
`metric_id = drop_id` and a negative `id`) and System Admin → LLM → Metrics → Benchmark (through
the `score-extract-metrics` evidence: `extraction.dropped_rows` and the report's "Dropped rows"
section, which flags a drop on the lines of a missed gold row). Dropped rows are never scored.

### 3.5 Indexing

Metrics indexing runs in the pipeline's **Phase C (post-process)** — after every doc
processor for the record has finished — not inside the metrics processor's Phase B
handler. This is required because metric indexing reads other processors' artifacts
(semantic projections, topics, scene blocks, provisions, entities, inventory items, and
their `kb.search_artifacts` rows), which may not exist yet while the metrics processor is
still running in Phase B. See the doc-processor capsule's "Post Process" section.

Indexing runs after the final metric rows are saved to `kb.metrics`. It is idempotent and
re-runs for pre-existing metrics (e.g. when extraction was skipped because metrics already
exist). It has five outputs:

| Relation | Storage |
|----------|---------|
| None | the metric row in `kb.search_artifacts` |
| deterministic line-overlap relation | stored in `kb.metrics.connected_artifacts` |
| relate artifact category to metric | stored in `kb.artifact_connections` |
| relate category path to metric | stored in `metrics.txt` under the matching category paths in `ARTIFACT_WEB_DIR` |
| relate metric to line-overlapping artifacts (entities, inventory_items, provisions, topics, semantic_projections) | stored in `kb.artifact_connections` |
| relate artifact objects to object nodes | stored in `kb.artifact_connections` |

Note: semantic metric↔metric similarity is **not** an indexing output — it is computed live
at read time (see [Semantic Similarity (Computed On-The-Fly)](#semantic-similarity-computed-on-the-fly)),
not materialized as `kb.artifact_connections` edges.

#### 3.5.1 Line-Overlap Artifact Edges

These edges make intra-document, line-overlapping artifacts explicitly traversable in
`kb.artifact_connections`. They are built deterministically at index time — no LLM or hybrid
search is involved here. (`connected_artifacts` itself is computed on demand by
`kb.connected_artifacts(record_id, 'metric', source_row_id)`, not materialized.) Cross-document
neighbor discovery happens later, at read time, in
[Metric Discovery for Document Review](#metric-discovery-for-document-review).

For each metric `M` in the record being indexed:

1. Find every artifact in the **same document** whose line spans overlap `M`'s, grouped by
   type `T ∈ {inventory_item, entity, provision, topic, semantic_projection}` → the anchors.
   Overlap is computed by self-joining `kb.search_artifacts` on the GiST-indexed
   `line_range && line_range` operator, so both endpoints use their canonical `artifact_id`s.
2. For each overlapping artifact (anchor) `X` of type `T`, upsert one edge to
   `kb.artifact_connections`:
   - `source_type = T`, `source_id = X.artifact_id`, `source_record_id = record_id`
   - `target_type = 'metric'`, `target_id = M.metric_id`, `target_record_id = record_id`
   - `relation_name = '#shared_artifact'`
   - `relation_method = 'line-overlapped-artifact'`
   - `confidence = 1.0` (deterministic overlap)
   - `extra_info` containing at least `{"source":"extract_metrics","anchor_type":T}`

Because both endpoints share lines, these edges are always intra-document
(`source_record_id = target_record_id = record_id`).

**Edge direction and bidirectional reads.** `kb.artifact_connections` is one graph in which
different edge families store the metric on different sides: line-overlap edges put the
artifact on the source side and the metric on the target side, while `belong_to` category
edges put the metric on the source side. Every read that looks up an
artifact's connections must therefore match it on **either** side
(`source_id = A OR target_id = A`); do not assume the metric is always source or always
target. Each symmetric edge (`#shared_artifact`) is stored exactly **once** in its canonical
direction (artifact → metric) — never insert the mirror row. Asymmetric relations
(`belong_to`) keep their natural direction; bidirectional matching is only a lookup
convenience and does not change a relation's meaning.

**Idempotency.** Rebuilt each run by `ReplaceSharedArtifactEdges`, which deletes the record's
existing edges scoped to `target_type = 'metric'` (plus
`relation_method = 'line-overlapped-artifact'`, `relation_name = '#shared_artifact'`), then
inserts the fresh set. The delete is scoped by target family so parallel Phase-C family runs
never clobber each other's edges.

#### 3.5.2 Search Artifact Row

Add each persisted metric to `kb.search_artifacts` using the metric's `search_document`.

Rules:

- `artifact_type` is `metric`
- `artifact_id` is `kb.metrics.metric_id`
- `input_record_id` is `kb.metrics.input_record_id`
- `source_line_spans` is copied from `kb.metrics.source_line_spans`
- search text is the same de-duplicated metric text used to populate `kb.metrics.search_document`

#### 3.5.3 Connected Artifacts JSON

Populate `kb.metrics.connected_artifacts` as a JSON object by comparing `kb.metrics.source_line_spans` with artifacts from the same `input_record_id`.

Required JSON shape:

```json
{
  "chunks": ["chunk_id"],
  "semantic_projects": ["proj_id"],
  "topics": ["topic_id"],
  "scenes": ["scene_id"],
  "provisions": ["prov_id"],
  "entities": ["entity_id"],
  "inv_items": ["inv_item_id"]
}
```

Rules:

- An artifact is connected when it has at least one overlapping line number with the metric.
- `chunks` must include all overlapping chunk IDs and must never be empty.
- `semantic_projects` must include all overlapping semantic projection IDs and must never be empty.
- `topics`, `scenes`, `provisions`, `entities`, and `inv_items` may be empty arrays.
- The `connected_artifacts` JSON is the per-metric overlap set for quick lookup; the same line-overlap facts are also written as traversable edges in `kb.artifact_connections` (see [Line-Overlap Artifact Edges](#line-overlap-artifact-edges)).

#### 3.5.4 Metric and Artifact Categories

Connect each metric to its artifact categories.

Rules:

- `kb.metrics.metric_categories` must not be null or empty. If it is null or empty, report an indexing error for that metric.
- For each category key in `kb.metrics.metric_categories`, resolve the category via the **Identify Artifact Categories** procedure in [9], passing `(category_key, category_type = "metric")`. That procedure normalizes the key, matches an existing category (exact/alias, then hybrid semantic), and creates one via the LLM on a true miss — do not insert categories directly here.
- Do not write metric-category membership to `kb.category_instance`.
- For each resolved category, upsert one row in `kb.artifact_connections`.
- The category membership edge connects:
  - `source_type = 'metric'`
  - `source_id = kb.metrics.metric_id`
  - `target_type = kb.artifact_categories.category_type`
  - `target_id = kb.artifact_categories.category_key`
  - `relation_name = 'belong_to'`
  - `relation_method = 'category_name'`
  - `source_record_id = kb.metrics.input_record_id`
  - `target_record_id = kb.metrics.input_record_id`
  - `extra_info` containing at least `{"source":"extract_metrics","category_key":<category_key>,"category_id":<category_id>}`
- Do not use `kb.inventory_categories` for metric categories.

#### 3.5.5 Index Metrics by Category Paths

Use `kb.metrics.source_line_spans` to find semantic projection category paths:

```text
kb.metrics.input_record_id = kb.semantic_projections.input_record_id
AND kb.metrics.source_line_spans overlaps kb.semantic_projections.line_spans
```

Return `kb.semantic_projections.category_paths_en`.

Rules:

- If no category paths are found, report an indexing error for that metric.
- For each returned category path, index the metric in the same way as semantic projection indexing.
- Save metric IDs in `metrics.txt` under the matching category path.
- Each `metrics.txt` entry uses `kb.metrics.metric_id`.

#### 3.5.6 Semantic Similarity (Computed On-The-Fly)

Semantic metric↔artifact similarity is **not materialized** as `kb.artifact_connections`
edges. Every artifact already lives in `kb.search_artifacts` and is discoverable by hybrid
search; a stored `semantically_related` snapshot would only duplicate that computation and go
stale as the corpus grows (and would need directional inbound/outbound bookkeeping to stay
complete). Instead, any consumer that needs "similar artifacts" runs the hybrid search
**live** at read time.

Consequences for indexing:

- The metric indexing step writes **no** `hybrid_search` / `semantically_related` edges.
- It still hydrates each metric's `search_document` and embedding into `kb.search_artifacts`
  so the read-time hybrid search (and the `/api/v1/kb/metrics/search` path) have the data
  they need.

**Hybrid acceptance model** — shared by every on-the-fly caller (the metrics document
reviewer's direct metric↔metric branch, and `neighbors(X)` in
[Metric Discovery for Document Review](#metric-discovery-for-document-review)). Mechanics are
defined in [7]; the implementation is `docprocessing.FindSimilarArtifactsOnTheFly`.

- **Query:** the source artifact's `kb.search_artifacts.search_document`, embedded live when
  semantic search is enabled.
- **Candidate set:** `kb.search_artifacts`, excluding the query artifact's own row;
  optionally restricted to a single `artifact_type` (the reviewer's direct branch and
  `neighbors(X)` both pass their own type).
- **Fusion:** lexical `ts_rank_cd` + `pgvector` cosine, fused with RRF (`rrf_k = 60`,
  200 candidates/list). Falls back to lexical-only when semantic search is disabled or the
  query cannot be embedded.
- **Per-candidate signals:** `rrf_score`, `cosine_sim = 1 - (embedding <=> query_embedding)`
  (null when either embedding is missing), `lexical_score` (null when not in the lexical list).
- **Acceptance (OR across channels):** `cosine_sim >= min_cosine` OR
  `lexical_score >= artifact_search.min_rank`.
- **Rank and cap:** order by `rrf_score DESC`, tie-break `artifact_id ASC`; keep at most
  `max_links`.
- **Scope:** the whole `kb.search_artifacts` registry (cross-document discovery is the point);
  not restricted to the query artifact's own `input_record_id`.
- **Thresholds:** the metrics reviewer's direct branch reuses `METRIC_CONNECT_MIN_COSINE`
  (default `0.75`) and `METRIC_CONNECT_MAX_LINKS` (default `10`); `neighbors(X)` uses
  `METRIC_NEIGHBOR_MIN_COSINE` / `METRIC_NEIGHBOR_MAX_LINKS` (same defaults). Both share
  `artifact_search.min_rank`.

Because nothing is persisted, there is no edge idempotency to manage for semantic similarity.

#### 3.5.7 Indexing Metrics to Objects
Metrics mention artifact objects through `kb.metrics.metric_id` = `kb.artifact_objects.artifact_id`.
Artifact objects connect to object nodes through `kb.artifact_objects.object_id` = 
`kb.object_nodes.object_id`. 

For each metric, add a record to `kb.artifact_connections`:
  - `source_type = 'metric'`
  - `source_id = kb.artifact_object.object_id`
  - `target_type = 'object_node'`
  - `target_id = kb.object_nodes.object_id`
  - `relation_name = 'belong_to'`
  - `relation_method = 'object_id'`
  - `source_record_id = kb.artifact_objects.source_record_id`

### 3.5.2 Ontology Candidate Harvest

After the final metric rows are saved to `kb.metrics`, every metric that carries a
`formula_or_definition` value is converted into a governed ontology candidate
(`kb.ontology_candidates`, `candidate_kind = 'term'`, `term_kind = 'metric_definition'`,
module `measurement`) via `harvestMetricDefinitions`. The `formula_or_definition` field
holds the metric's *definition*: the statement that says what the metric means, including a
formula that defines it (a formula that defines a metric is a definition). A bare value or
threshold is an assertion, not a definition, and is not harvested.

The harvest is **mode-independent**: it runs in both the chunk-batch (concurrent) path
(`FinalizeChunkBatch`) and the sequential fallback path (`HandleEvent`), so converting
extracted metrics to ontology candidates does not depend on `RUN_DOC_PROCESSOR_CONCURRENT`.
Candidate creation is idempotent by fingerprint, so re-running a record never duplicates
review work.

### 3.6 Thinking Behavior

Metrics extraction must force thinking off for all passes:

- primary candidate model
- fallback candidate model
- enrichment model

Implementation rule:

- set `ThinkingType = "disabled"` in metrics processor configs
- shared LLM client must omit the `thinking` request field unless `ThinkingType == "enabled"`

This avoids provider errors such as:

- `Unknown parameter: 'thinking'`

### 3.7 Logging

The processor should log:

- candidate-pass start
- raw parsed LLM payload/error
- merged candidate count
- enrichment-pass start
- enrichment results
- final dedup results
- rows set aside (3.4.2): one `kb.doc_proc_logs` row per run that sets aside at least one row,
  with `doc_proc_name = 'extract_metrics'` and `activity = 'drop_metric_rows'`. `extra_info`
  holds `num_dropped`, `by_stage` and `by_reason`. The artifact's `dropped` array lists each row's
  `drop_id`, `candidate_id`, `drop_stage`, `drop_reason`, `kind`, `metric_name`, `subject`,
  `threshold_or_target`, `context`, `source_line_spans` and `decision`. No row is written when
  nothing is set aside. Runs before 2026-10-08 wrote `exclude_pure_requirements` instead
  (`excluded` array, pure requirements only)
- rows that still hold several values (3.4.2 step 1): one `kb.doc_proc_logs` row per run that has
  any, `activity = 'multi_value_rows'`, `extra_info.num_rows`, artifact `multi_value_rows` listing
  each row's `candidate_id`, `metric_name`, `metric_value` and `source_line_spans` (since
  2026-10-16). It measures the one-value-per-row prompt rule; no row is changed
- open-value decision failures (Warn, with record and candidate ids); an unconfigured decision
  model is warned once per run
- per enrich batch (Info/Warn logger, not `kb.doc_proc_logs`): candidates that are neither
  enriched nor listed in `dropped_candidates`, and rows set aside for carrying a drop-reason tag
  (3.4.2). The `dropped_candidates` reasons themselves are in each `enrich_metrics` log's artifact
- metrics indexing start/result, including connected artifact counts and category-path counts
- metrics indexing errors, including empty `metric_categories`, empty `chunks`, empty `semantic_projects`, or no matching category paths
- when `force_clear=false` (merge mode, see [10] DR2/DR4): for each pending Metric Group sent to the Merge Resolution LLM call, one `kb.doc_proc_logs` row (`activity = 'merge_resolve_metrics'`) containing the exact candidates payload sent to the LLM and the `winning_metrics` (or error) it returned — fires whether the call succeeds or fails, so a merge run always has a traceable record of what was sent and decided

The shared LLM client should also log the raw HTTP response body before decoding.

### 3.8 Metric ID

Metrics are identified by:

```text
<record_id>_mtc_<seqno>
```

where `seqno` starts at `1`.

`metric_id` is reused: a forced (`force_clear`) re-extraction deletes the record's rows and
numbers the new ones from `1` again. Deleting the rows (`DeleteMetricsByInputRecordID`) therefore
first retires every active `kb.assertion_evidence` row with `artifact_type = 'metric'` for the
record (reason "metric rows deleted for re-extraction"). Assertions that lose their last support
become `unsupported`, and a reused `metric_id` never inherits old evidence (ADR 2026100603,
openspec change `requirements-metrics-phase1`).

## 4. Workflow

- For each chunk, run Pass 1 to extract metric candidates.
- Retry candidate extraction with `EXTRACT_METRIC_CANDIDATES_MODEL_FALLBACK` when the primary candidate model fails.
- If both primary and fallback candidate extraction return the empty/truncated JSON failure shape, treat the chunk as an empty candidate result.
- Merge and deduplicate candidates deterministically.
- Group candidates by source chunk; run Pass 2 in batches of up to `METRIC_ENRICH_GROUP_SIZE` (default 5), never cutting between candidates that quote the same evidence (3.3), to enrich each batch into final metrics.
- Deduplicate final metric rows.
- Set aside pure requirements (inspection and delegated), then every row without a value
  (`no_value`), then judge any remaining open-value requirement with the decision model (3.4.2).
  The value check runs after Pass 2, not on Pass 1's `value_hint`: on 416 and 753 an empty hint
  never got a value in Pass 2 (0 of 140), so a pre-filter would save about 40% of enrich calls,
  but the rows set aside would be incomplete. Kept as is (user decision, 2026-10-09).
- Save final metrics to `kb.metrics` and set-aside rows to `kb.metrics_dropped`; log the
  set-aside rows (`drop_metric_rows`).
- After each successful save/upsert step, write one `kb.doc_proc_logs` row with `activity = 'extract_metrics_final'`.
- The `extract_metrics_final` artifact must contain the exact metric rows being saved in that write operation, and every row in that artifact must include `candidate_id`.
- Write `.metrics` artifact output.
- Upsert status in `kb.inputs.status`.

Indexing is **not** part of this Phase B handler. After the whole pipeline finishes
(Phase C / post-process), the controller invokes the metrics processor's post-process
indexing step, which: upserts `kb.search_artifacts`, populates
`kb.metrics.connected_artifacts`, upserts `category_name` membership edges to
`kb.artifact_connections`, writes category-path `metrics.txt` entries, and upserts
line-overlap artifact edges to `kb.artifact_connections`. Semantic metric↔metric similarity
is no longer materialized here — it is computed live at review time. See the
[Indexing](#indexing) section.

**Progress Update (per block):**
- When beginning extraction, set `progress` to `"0%"` in `kb.inputs.status`.
- After each block completes in either pass, insert a log entry to `kb.doc_proc_logs` with `proc_progress` set to the current progress (see [doc-processor-log-spec.md Section 1.3.3](doc-processor-log-spec.md)), then update the `progress` attribute of the corresponding entry in `kb.inputs.status`.
- Pass 1 candidate logs use `activity = 'extract_metric_candidates'` and must include candidate rows with `candidate_id`.
- Final-save logs use `activity = 'extract_metrics_final'` and must include the final metric rows that were written, each with its `candidate_id`.

```text
total_blocks = total_blocks_pass1 + total_blocks_pass2

percent = floor(completed_blocks * 100 / total_blocks)
progress = "<percent>% (<completed_blocks>/<total_blocks>)"
```

Notes:
- `total_blocks_pass1` = number of chunks
- `total_blocks_pass2` = number of enrichment batches (candidates grouped by source chunk, batched by `METRIC_ENRICH_GROUP_SIZE`); calculated after pass 1 completes
- Failed calls do not increment `completed_blocks`

Examples:
- Pass 1, 2 of 15 blocks done (total 30 blocks) → `6% (2/30)`
- Pass 1 complete → `50% (15/30)`
- All done → `100% (30/30)`

Failure status entry:

```json
{
  "record_id": "ddd",
  "file_type": "pdf | doc | docx | ppt | pptx | ...",
  "operation": "extract_metrics",
  "proc_status": "failed",
  "input_filename": "Artifacts/0/100/std_20039_opendata.txt",
  "error": "error-msg",
  "start_time": "yyyymmdd hh:mm:ss",
  "ms_used": ddd
}
```

Success status entry:

```json
{
  "record_id": "ddd",
  "file_type": "pdf | doc | docx | ppt | pptx | ...",
  "operation": "extract_metrics",
  "proc_status": "success",
  "input_filename": "Artifacts/0/100/std_20039_opendata.txt",
  "start_time": "yyyymmdd hh:mm:ss",
  "ms_used": ddd
}
```

## 5. Output Storage

### 5.1 Save to Table `kb.metrics`

Construct a row for each final metric and insert it.

Rules:

- save the JetStream event ID to `event_id`
- if the original language is English, do not generate/store:
  - `metric_name_en`
  - `metric_subject_en`
  - `metric_desc_en`
  - `metric_context_en`
  - `metric_keywords_en`
  - `metric_unit_en`
  - `value_class_en`
  - `condition_en`
- save `condition`, `condition_en` (migration `20261016000001`), `value_min` and `value_max`
  (migration `20260801000014`) from the Pass 2 row; endpoints are NULL unless the row is a `range`
  (never 0 for a missing value). `SaveMetrics` (force_clear) and `UpsertMetrics` (merge, also in
  `ON CONFLICT … DO UPDATE`) both write them, and `GetMetricsByInputRecordID` /
  `loadPersistedMetricArtifactRows` read them back. Until 2026-10-16 the doc-processor path wrote
  none of the three (only the old `kbhandler` import path did); rows extracted earlier keep NULL
  until re-extracted (no backfill)
- when populating `search_document`, concatenate the searchable metric fields only once each; if normalized field text is duplicated across fields such as `metric_desc`/`metric_context` or `metric_unit`/`metric_unit_en`, keep the first occurrence and drop repeats
- save `metric_categories` to support category membership indexing
- initialize `connected_artifacts` as an empty JSON object or the full required shape with empty arrays; the post-save indexing step must update it with deterministic line-overlap links
- save additional information to `ext_info`

`ext_info` requirements:

- always include `language`
- always include `schema_version = "2"`
- seed `title` from `kb.inputs.doc_metadata.title` when present; otherwise fall back to `kb.inputs.title`
- seed `doc_no` from `kb.inputs.doc_metadata.doc_no` when present; otherwise fall back to `kb.inputs.doc_no`
- for metric rows whose artifact objects are later written to `kb.artifact_objects`, merge in `object_name` from the preferred linked object row where:
  - `kb.artifact_objects.artifact_type = 'metric'`
  - `kb.artifact_objects.artifact_id = kb.metrics.metric_id`
  - the preferred row should favor `object_role IN ('measured_object', 'self')`, then first row order
- this is forward-only behavior; no backfill is required for existing metric rows

`provision_id` (nullable, references `kb.provisions.id`, `ON DELETE SET NULL`) names the provision
clause a requirement row is a criterion of (ADR 2026100603 DR2). `extract_metrics` does not fill
it yet. It stays `NULL` until the deferred `extract_provisions` linking work lands.

Customer-facing views label each row's statement kind (requirement, metric, test parameter,
definition) at read time from `value_class`, `value_range_type`, `formula_or_definition` and
`reasoning_tags` (`web/src/lib/metric-statement-kind.ts`). Nothing about the kind is stored.
New extractions contain no `inspection_requirement` or `delegated_requirement` rows in `kb.metrics`; they are in `kb.metrics_dropped` (3.4.2).
Older records may, until they are re-extracted.

### 5.1.1 Read Payload and Metric Detail UI

When returning metric records for the metrics detail view, the read path should expose:

- `document_title`
- `document_doc_no`
- `object_name`

These values come from the same document/object sources described above and are used by the
metrics detail panel with this display order:

- under `Context`, show `Document Title` and `Doc No` above `Section`
- under `Metric`, show `Object` directly under `Subject`
- under `Metric`, show `Condition` and `Condition (English)` after `Subject` (since 2026-10-16;
  `web/src/lib/components/home3/metric-detail-groups.ts`, Paraglide keys `metric_mgmt_condition`,
  `metric_mgmt_condition_en`)

`GET /kb/metrics` (production, gold `source=testbed`, and dropped rows from `row_data`) and the
single-metric read return `condition` and `condition_en`; `PATCH` accepts them. The same panel is
used by the Metrics workspace and the Product Review "Full Details" dialog. The production-vs-gold
comparison shelf (`context-shelf.svelte`) lists both, and the metric wiki infobox shows the
condition in the page language (`metricWikiCondition`; pages cached before 2026-10-16 show it
after a refresh). Gold metrics store `testbed.metrics.condition_en` (migration
`20261016000002`).

### 5.2 Category Table Migration

Metric categories are managed by `kb.artifact_categories`.

Rules:

- Resolve every metric category through the **Identify Artifact Categories** procedure in [9] (with `category_type = "metric"`), which creates the category via the LLM on a true miss. Do not insert into `kb.artifact_categories` directly from the metric workflow.
- Remove the retired `kb.inventory_categories` table.
- Do not create, read, or write `kb.inventory_categories` in the metric extraction or indexing workflow.

### 5.3 Save to File

Write all final metrics to:

```text
ARTIFACT_DIR/<group_id>/<record_id>/<filename_root>_<parser_name>.metrics
```

where:

- `<group_id>` = `floor(record_id / 1000)`
- `<filename_root>` is derived from `kb.inputs.staging_filename`
- `<parser_name>` is `kb.inputs.parser_name`

## 6. Extract Metric API

The preview API is still using the older single-pass flow.

Inputs:

- `record_id`
- `lines`: `["ddd", "ddd-ddd", ...]`

### 6.1 Compose Input

- treat selected lines as normal lines `n`
- treat the five lines immediately before and after as overlap lines `o`
- convert the raw lines into standard chunk format

### 6.2 Handler Workflow

- read the record by `record_id`
- compose the block input
- load one prompt and one model config
- make one LLM call
- expect a top-level `metrics` array in that single response
- return all extracted final metrics
- do not save them to `kb.metrics`
- properly handle all errors

### 6.3 Extract Metric API Response

```json
{
  "status": true,
  "metrics": [
    {
      "metric_name": "...",
      "metric_name_en": "...",
      "metric_desc": "...",
      "metric_desc_en": "...",
      "metric_subject": "...",
      "metric_subject_en": "...",
      "metric_context": "...",
      "metric_context_en": "...",
      "metric_keywords": ["..."],
      "metric_keywords_en": ["..."],
      "source_line_spans": ["ddd", "ddd:ddd"],
      "location_type": "...",
      "metric_unit": "...",
      "metric_unit_en": "...",
      "metric_value": "...",
      "value_data_type": "...",
      "value_range_type": "...",
      "value_class": "...",
      "value_class_en": "...",
      "formula_or_definition": "...",
      "threshold_or_target": "...",
      "measurement_frequency": "...",
      "metric_categories": ["..."],
      "confidence": 0.0,
      "is_explicit_metric": true,
      "table_name_or_section": "...",
      "reasoning_tags": ["..."]
    }
  ]
}
```

## 7. Save Extracted Metrics API

This API persists reviewed final metric rows returned by the preview flow.

### 7.1 Request

```json
{
  "record_id": 123,
  "metrics": [
    {
      "metric_name": "...",
      "metric_name_en": "...",
      "metric_desc": "...",
      "metric_desc_en": "...",
      "metric_subject": "...",
      "metric_subject_en": "...",
      "metric_context": "...",
      "metric_context_en": "...",
      "metric_keywords": ["..."],
      "metric_keywords_en": ["..."],
      "source_line_spans": ["ddd", "ddd:ddd"],
      "location_type": "...",
      "metric_unit": "...",
      "metric_unit_en": "...",
      "metric_value": "...",
      "value_data_type": "...",
      "value_range_type": "...",
      "value_class": "...",
      "value_class_en": "...",
      "formula_or_definition": "...",
      "threshold_or_target": "...",
      "measurement_frequency": "...",
      "metric_categories": ["..."],
      "confidence": 0.0,
      "is_explicit_metric": true,
      "table_name_or_section": "...",
      "reasoning_tags": ["..."]
    }
  ]
}
```

### 7.2 Save Handler Workflow

- read `record_id` and `metrics`
- validate `record_id > 0`
- validate `metrics` is not empty
- validate every metric has non-empty `metric_categories`
- create `kb.metrics` table if needed
- insert rows into `kb.metrics`
- assign `metric_id = <record_id>_mtc_<seqno>` based on existing row count
- set `event_id = rest-api`
- save `ext_info` with at least:
  - `source = "rest-api"`
  - `schema_version = "2"`
  - `title` and `doc_no` seeded from `kb.inputs.doc_metadata` with fallback to top-level input fields, the same way as the document-processor save path
- run the same post-save metrics indexing workflow used by the document processor
- when metric artifact objects are written for these saved metrics, merge `object_name` into `kb.metrics.ext_info` using the same artifact-object linkage rule as the document-processor save path
- leave `model_name`, `prompt_name`, and `metric_keywords_en` empty in the current implementation
- return the number of inserted metrics

## 8. Metric Discovery for Document Review

This is a **read-time** procedure: it is not part of indexing and persists nothing. Its
purpose is to surface metrics from the corpus that a document under review should plausibly
cover — both the ones it explicitly mentions and the ones it may have missed — by walking
from the document's metrics out to same-type "close" artifacts elsewhere in the corpus and
back to the metrics attached to them.

Neighbor closeness is always computed **on the fly** so a freshly added document is picked up
immediately; neighbor sets are never cached across runs.

**Implementation status.** The P5 metrics reviewer currently implements cross-document
discovery as three branches: (A) direct metric↔metric similarity computed live via
`docprocessing.FindSimilarArtifactsOnTheFly`, (B) metrics sharing a category key, and
(C) entity→metric edges. The full anchor → `neighbors(X)` → metrics expansion below and the
mentioned/missed **metric matrix** are the planned extension (matrix deferred to a separate
session); they build on the same on-the-fly hybrid search that Branch A already uses.

For each metric `M` extracted from the document under review:

1. Find every artifact in the same document whose line spans overlap `M.source_line_spans`,
   grouped by type `T ∈ {inventory_item, entity, provision, topic, semantic_projection}` →
   the anchors.
2. For each anchor `X` of type `T`:
   - Compute `neighbors(X)` (see below), excluding `X` itself.
   - For each neighbor `N` (also of type `T`):
     - Find every metric `Y` connected to `N` in `kb.artifact_connections`, matching `N` on
       **either** side (connections are bidirectional):
       ```text
       (source_type = T AND source_id = N.artifact_id AND target_type = 'metric')
       OR
       (target_type = T AND target_id = N.artifact_id AND source_type = 'metric')
       ```
       `Y` is the metric-side endpoint of each matched row. (Restrict to
       `relation_name = '#shared_artifact'` if only metrics that directly line-overlap `N`
       are wanted; leave it open to also include semantically-related metrics.)
     - Add each `Y` to the metric matrix (see the Metric Matrix note).
3. Return the matrix.

### 8.1 neighbors(X)

`neighbors(X)` returns same-type artifacts across the whole corpus that are "close" to the
anchor `X`. It reuses the shared hybrid acceptance model in
[Semantic Similarity (Computed On-The-Fly)](#semantic-similarity-computed-on-the-fly)
(`docprocessing.FindSimilarArtifactsOnTheFly`), re-parameterized for artifact-to-artifact
search:

- **Query:** `X.search_document` and its embedding (from `kb.search_artifacts`).
- **Candidate set:** `kb.search_artifacts` filtered to `artifact_type = T` (same type as the
  anchor), **global** scope (all `input_record_id`), excluding `X` itself.
- **Hybrid search:** reuse the [7] CTEs — `ts_rank_cd` lexical + `pgvector` cosine, fused with
  RRF (`rrf_k = 60`, 200 candidates per list). If semantic search is disabled or `X` has no
  embedding, fall back to lexical-only.
- **Per-candidate signals:** `rrf_score`, `cosine_sim = 1 - (embedding <=> query_embedding)`,
  `lexical_score`.
- **Acceptance (OR across channels):**
  - semantic: `cosine_sim >= METRIC_NEIGHBOR_MIN_COSINE` (default `0.75`), OR
  - lexical: `lexical_score >= artifact_search.min_rank`.
- **Rank and cap:** order by `rrf_score DESC`, tie-break `artifact_id ASC`; keep at most
  `METRIC_NEIGHBOR_MAX_LINKS` (default `10`).

Precondition: every artifact type must have a populated `search_document` (and, for the
semantic channel, an embedding) in `kb.search_artifacts`; a type with a null embedding
degrades to lexical-only rather than returning nothing.

Within a single review invocation, `neighbors(X)` may be memoized by `X.artifact_id` so an
anchor shared by multiple metrics is searched once; this cache must never persist across
invocations (the corpus moves between runs).

### 8.2 Metric Matrix

The metric matrix distinguishes metrics the document **mentions** from metrics it may have
**missed**, keyed so that "close enough" metrics collapse into one entry whose value is the
deduplicated list of contributing metrics. The matrix structure and its metric↔metric
closeness key are specified separately (deferred to the matrix session); this procedure only
supplies candidate metrics `Y` tagged with their `input_record_id` so the matrix step can
classify mentioned vs. missed and dedup within each entry.

## 8.3 Resolved reference rows and step 6 (2026-10-11)

`extract_references` (spec `extract-references-spec.md`) may add rows `<rec>_rfm_<n>` to a record's
`kb.metrics`: metrics of another document that this document requires through a reference. They
have `ref_mention_id` set. `extract_metrics`:

- never deletes, merges or reads them as its own: `DeleteMetricsByInputRecordID`,
  `GetMetricsByInputRecordID`, `MetricsExist` and the indexing load all filter
  `ref_mention_id IS NULL`;
- runs **step 6** after every successful save (force-clear, merge, and the no-candidates wipe):
  `ResolveIncoming(ctx, db, "metric", recordID)` re-resolves other records' metric references to this
  record against its new metrics. A failure is logged at WARN and never fails `extract_metrics`.

Contract: `ChenWeb/openspec/changes/extract-references-processor/specs/metric-reference-resolution/spec.md`.

## 9. Implementations
Refer to [3], [4], [5] and [6].

## 10. References
[1] KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-categories-spec.md\
[2] KnowledgeStore/Capsules/coding-capsules/full-text-search/metric-search-design.md \
[3] KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-metrics-impl.md \
[4] KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-metrics-concurrency-spec.md \
[5] KnowledgeStore/Capsules/coding-capsules/full-text-search/metric-search-design.md \
[6] KnowledgeStore/Capsules/coding-capsules/full-text-search/metric-search-impl.md \
[7] KnowledgeStore/Capsules/coding-capsules/llm-wiki/hybrid-search.md \
[8] KnowledgeStore/Capsules/coding-capsules/llm-wiki/artifact-connections.md \
[9] KnowledgeStore/Capsules/coding-capsules/categories/category-mgmt-spec.md \
[10] KnowledgeStore/doc-repo/adrs/202607/2026071002-adr-doc-processor-incremental.md \
[11] KnowledgeStore/doc-repo/adrs/202610/2026100603-adr-separate-requirements-from-metrics.md \
[12] ChenWeb/openspec/changes/exclude-pure-requirements-from-metrics/ (spec
`metric-pure-requirement-exclusion`) \
[13] ChenWeb/openspec/changes/extract-metrics-conditions/ (specs `metric-condition`,
`metric-value-notation`, `metric-row-granularity`); devdoc
`KnowledgeStore/doc-repo/devdocs/202610/2026101601-devdoc-extract-metrics-conditions.md`
