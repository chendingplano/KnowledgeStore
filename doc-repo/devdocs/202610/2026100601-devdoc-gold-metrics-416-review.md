# Gold Metrics Review, Record 416 — what the v1.0.0 benchmark got wrong

**Date:** 2026-10-06 \
**Scope:** Row-by-row review of the gold (benchmark) metrics that skill `extract-metrics-benchmark`
v1.0.0 produced for document 416, the root causes in the skill, and what the next skill version must
change. Open this before revising the skill or before using run `22aa157c` to score `extract_metrics`.
**Code root:** `.agents/skills/extract-metrics-benchmark/` (skill), `testbed.metrics` (data)

## Summary

The benchmark skill reads a document and records the "correct" list of metrics for it, so that the
production extractor (`extract_metrics`) can be scored against that list. For document 416, the
Zhejiang standard DB33/T 2030—2018 on sorting and treating rural household waste, the skill saved
134 gold metrics. On review, only about half of them are real metrics.

- **49 rows are sound.** These are numeric limits (fertilizer heavy metals, pH, germination index),
  physical or functional properties of a named object (bins have lids, vehicles are fully enclosed),
  and requirements that hand their criteria to a cited standard.
- **52 rows should not be metrics.** They include general principles ("collect everything, sort
  everything"), planning and administrative duties, instructions telling residents what to do with
  their waste, descriptions of which regions suit a treatment method, and one requirement split into
  several near-identical rows.
- **33 rows depend on rules you need to set.** There are 15 numeric settings from the test method in
  Annex B, and 18 rows about licences/certificates, housekeeping states ("site kept tidy"), or
  references to unnamed requirements ("emissions meet the standard").

In short, the skill has no working test for what counts as a metric. In practice it treated almost
every "应" (shall) clause as one, and it split sentences too finely. As a result the gold set is about
twice the size it should be. That would wrongly lower `extract_metrics` recall: for comparison,
production `kb.metrics` holds 45 rows for this record. Do not use run `22aa157c` for scoring until a
corrected run exists.

Skill versioning was added at the same time (now v1.2.0). Every benchmark row records the skill name,
the skill version, and the model that ran it (see "Provenance" below), so a corrected run can be told
apart from this one.

## Details

### Inputs reviewed

| Item | Value |
|---|---|
| Document | `kb.inputs.id = 416`, DB33/T 2030—2018 《农村生活垃圾分类处理规范》 |
| Source | `/Users/cding/Apps/SemOS/Artifacts/0/416/std_1503937_mineru.txt`, 169 lines, sha256 `5acb3df6…0fcd` |
| Benchmark run | `22aa157c-d712-46be-abc8-d7f195cff483`, 134 rows; backfilled `skill_name = 'extract-metrics-benchmark'`, `skill_version = '1.0.0'`, `model_name = 'gpt-6.1-sol'` (Codex session rollout 2026-10-06T06-22-06) |
| Ledger | `ext_info.candidates` (295 candidates: 134 accepted, 161 excluded) |

The whole source and all 134 rows were read. The excluded candidates in the ledger were read too, to
check consistency. Production `kb.metrics` was not compared; only its row count (45) was looked at.

### Working definition used for this review

A row is a metric when the source names **(a)** an object (thing, facility, product, sample) and
**(b)** a property of that object that can be measured or inspected, and gives **(c)** a value, bound,
or concrete criterion. Two forms also count: an explicit delegation of the criterion to an identified
document (spec §3.3.1 `reference`), and an explicit statement that the limit is set elsewhere
(`limit_absent`). The following are not metrics: actions people must take, organizational duties,
principles and slogans, term definitions, and descriptions of where a method is applicable. This
definition is narrower than the one v1.0.0 applied. Adopting it in the skill is recommendation S1.

### Verdict by row (all 134)

**A. Keep as is (45):** 7, 8, 9, 11, 12, 13, 25, 26, 27, 28, 32, 33, 34, 35, 36, 37, 38, 39, 46, 47, 48,
49, 50, 54, 55, 58, 59, 60, 64, 75, 76, 77, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 104.

- Numeric limits: 13 (≥2 bins per household), 89 (GI ≥60%), 92–94 (Table 2), 95–99 (Table 3).
- Object properties: 7, 36 (enclosed vehicles), 11, 12 (bin lid, visible sign), 35, 37–39 (vehicle
  marking, anti-odour/anti-spill/anti-leak), 49, 50 (sunroom sealing, insulation), 33, 34 (enclosed
  collection).
- Frequencies: 25, 32 (daily collection); 26, 27 (`limit_absent`: time and frequency are left to an
  agreement between the parties).
- Delegated to a cited document: 8, 9, 28, 46, 47, 54, 55, 58–60, 64, 75–77, 88, 90, 91. Rows 90 and 91
  are the best case of this pattern: a named property (fecal coliform count, roundworm egg mortality)
  whose value lives in NY 884.
- Sizing rule without a value: 48 (sunroom single-chamber volume set by daily throughput, `limit_absent`).
- Formula definition: 104 (germination index, eq. B.1).

**B. Keep but fix fields (4):**

| Row | Problem | Fix |
|---|---|---|
| 43, 44 | Line 121 requires the equipment to state its 比能耗 (specific energy consumption) and 发酵周期 (fermentation cycle). Gold models these as qualitative "参数明确性" (clarity of the parameter). | Model each as the named property itself, `limit_absent`: the value must be declared by the supplier, and this document gives none. |
| 133, 134 | `metric_value` holds `<100` and `>100`, while every other row stores a bare number. `upper_bound`/`lower_bound` cannot express the strict inequality. | Store `100`; keep the comparator in `threshold_or_target`; decide how strict bounds are represented (S6). |

**C. Annex B test-method settings (15), pending a decision:** 105, 106, 108, 109, 110, 111, 112, 113,
114, 115, 121, 122, 123, 124, 125. These are sample count and dry mass, solid:liquid ratio, shaker
frequency and amplitude, extraction and settling time, blank count, extract storage time and
temperature, seeds per dish, extract volume, incubation temperature and time, and replicates. They
are numeric, but they constrain the test procedure, not the waste or the product. Neither the spec nor
the skill says whether they belong in the benchmark. The recommendation is to keep them, tagged as
test conditions (S4).

**D. Need a rule decision (18):**

| Pattern | Rows | Question |
|---|---|---|
| Party holds a licence, certificate, or documented provenance | 31, 40, 41 (hazardous-waste licence, qualified enterprise), 74 (equipment certificate of conformity), 86, 87 (strain source and species name stated) | Is "has a qualifying document" a metric? It is a yes/no compliance check, not a measured property. |
| Housekeeping states with no defined criterion | 21, 22 (containers intact, tidy and attractive), 29, 30 (transfer facility and surroundings tidy), 78–80 (no odour, no sewage, no litter), 81–83 (equipment in good condition, site tidy) | These are inspectable but subjective. 78–80 are the strongest (absence is observable), and 22, 30, 83 the weakest (整洁美观, "tidy and attractive"). |
| Delegation to an unnamed requirement | 53 (siting meets "biogas safety protection requirements"), 61 (flue gas "达标排放", meets standard) | §3.3.1 needs an identified document. Row 61 is also covered by row 64 (GB 18485) in the same cell. |

**E. Exclude (52):**

| Reason | Rows | Notes |
|---|---|---|
| Term definition, principle, or slogan | 1 (四分四定 "定时"), 2, 3, 4 (应收尽收/应分尽分/日产日清) | Lines 43 and 46 are the definitions clause and the "基本要求" principles. The ledger itself excluded 定人/定车/定位 from the same line 43 (c0259). Row 4's daily frequency is stated concretely in rows 25 and 32. |
| Classification structure | 10 ("四大类" = 4) | A count of categories in the classification scheme, not a measurement of anything. |
| Planning or administrative duty | 5, 6 (layout/scale/land-use figures go into county plans), 100, 101 ("定期" inspection, publicity) | No property of an object. The ledger excluded "layout" from the same clause (c0260) and all other §10 duties (c0233–c0240). |
| Direction-only aspiration | 102 (提高…分类的准确率, "improve sorting accuracy") | A named KPI with no value or target level. The skill text says to exclude vague aspirations. |
| Instructions to residents/operators (actions) | 14, 15, 16, 17, 18, 19, 20, 23, 24 | "Drain before disposal", "cover the bin", "keep recyclables clean as far as possible (尽量)", "collect and transport separately". The ledger excluded the equivalent routing instructions 7.1.5/7.1.6 (c0265, c0266). |
| Facility provision or disposal route | 51, 52, 56, 57, 62, 63 | "Equip a collection or treatment system", "residues have a reasonable outlet", "fly ash/slag effectively disposed". Rows 51 and 52 also invent a condition ("采用达标排放处理系统时", when a compliant treatment system is used) that is not in the source. The ledger excluded the same kind of provision on line 125 (c0281). |
| Applicability descriptors stored as `definition` | 65, 66, 67, 68, 69, 70, 71, 72 | "人口密度高" (high population density) and similar describe where a treatment mode suits. They are not requirements and have no value. `value_class = definition` is meant for metric definitions. |
| Applicability boundary | 73 (户用沼气池 ≤50 m³) | The scope condition for NY/T 90, already carried as row 54's `condition`. Its own annotation note says it is not a required maximum. |
| Not quantities / duplicates | 42 (主体工艺, main process), 45 (equipment strain source, duplicates 86), 84 (strain "安全", made concrete by row 88), 85 (strain "有效", effective, with no criterion) | |
| Formula operands split from the formula | 129, 130, 131, 132 | Germination rates and root lengths are inputs to eq. B.1 (row 104), with no requirement of their own. |
| Permissive wording | 103 (彩色标志颜色**可**按照 GB/T 19095) | "可" means "may", so the clause imposes no requirement. §3.3.1 covers clauses that require. |
| Test-procedure steps and apparatus | 107 (500 ml bottle), 116 (room temperature), 117 (sealed bottle), 118 (fixed vertically), 119 (shake before analysis), 120 (one filter paper), 126 (dark incubator), 127 (lid on), 128 (seeds spread evenly) | Procedure, not a measured setting. Rows 116 and 126 are better carried as `condition` on rows 111 and 123. The line 158 equivalent of 127 (盖紧瓶盖, cap tightly) was not extracted, which shows the granularity is arbitrary. |

**Completeness.** No real metric was found missing from the source. Every numeric statement on lines
90, 128, 131, 134, 158, 159 and 161–163 is captured. The problem is precision, not recall.

### Root causes in skill v1.0.0

| # | Cause | Evidence |
|---|---|---|
| R1 | No operational test for "is this a metric". The inclusion list ("explicit testable requirements", "a concrete measured-property requirement as qualitative") is satisfied by almost any 应 clause. | Groups E-instructions, E-planning, D |
| R2 | The splitting rule ("split distinct properties in a sentence") is applied to conjunctions of vague adjectives and to formula operands. | 18–20, 21/22, 29/30, 56/57, 62/63, 81/82, 84–87, 129–132 |
| R3 | No consistency check between accepted and excluded candidates. The same reasoning excluded one half of a clause and accepted the other. | gold_5/6 vs c0260; gold_1 vs c0259; 17/23/24 vs c0265/c0266; 51/52 vs c0281; 100/101 vs c0233–c0240 |
| R4 | No rule for test-method parameters, permissive modality (可/宜/鼓励), unnamed references ("达标", "safety requirements"), or applicability descriptors. | Groups C, D-delegation, E-permissive, E-applicability |
| R5 | `value_class = definition` has no stated meaning, so it absorbed applicability descriptors and term definitions. | 1, 65–73 |
| R6 | Representation gaps: no rule for strict inequalities, and no pattern for "supplier must declare named parameter X". | 43, 44, 133, 134 |
| R7 | The correctness review did not catch an invented condition or evidence fragments that cannot stand alone. | 51/52 condition; `threshold_or_target` of 14 ("分类垃圾容器并分类投放") and 87 ("种名") |
| R8 | The recall-first stance ("do not inherit precision-over-recall") combined with R1 to push the set toward inclusion, with no counterweight. | 134 gold rows against about 64 that hold up |

### Recommended changes for the next skill version

- **S1** Put the three-part metric test (object, property, value/criterion, or explicit
  delegation/`limit_absent`) into SKILL.md as the gate every accepted candidate must pass. List the
  non-metric patterns explicitly: actions by people, organizational duties, planning inclusion,
  principles and slogans, term definitions, applicability descriptors, direction-only aspirations,
  provision of facilities, and disposal routes.
- **S2** Restrict splitting to parts that each pass S1 independently. Never split formula operands
  away from their formula.
- **S3** Add a consistency audit: for every excluded candidate, check that no accepted row on the same
  line relies on the same reasoning, and the reverse. Record the rule ID used for each decision in the
  ledger.
- **S4** Decide and document test-method parameters. Proposed: keep numeric settings that affect the
  result, tagged `test_condition`; carry qualitative test settings as `condition`; exclude apparatus
  identity and procedural steps.
- **S5** Modality and references: exclude 可/宜/鼓励 clauses unless the user decides otherwise. A
  delegation needs an identified document. Unnamed "达标" or "requirements" either fail S1 or follow a
  rule chosen from group D.
- **S6** Define `value_class = definition` (metric/formula definitions only). Define how strict bounds
  are stored. Add the "declared named parameter → `limit_absent`" pattern.
- **S7** The correctness review must confirm that every `condition` appears in the source, and that
  each `threshold_or_target` states the requirement on its own.
- **S8** Rows in group D need your decision before S1–S7 are finalized.

### Provenance (added with this review)

Each `testbed.metrics` row now records who produced it:

| Column | Source | Migration |
|---|---|---|
| `skill_name` | SKILL.md frontmatter `name` | `20261006000003_add_skill_and_model_name_to_testbed_metrics.sql` |
| `skill_version` | SKILL.md frontmatter `metadata.version` (currently **1.2.0**; history in the skill's `CHANGELOG.md`) | `20261006000002_add_skill_version_to_testbed_metrics.sql` |
| `model_name` | `benchmark_io.py prepare --model-name <exact model ID>` (required) | `20261006000003_…` |

- All three columns are `TEXT NOT NULL`. `benchmark_io.py` writes them into the prepared payload and
  rejects a payload prepared under another skill or version, or one without a model name.
- Rows saved before these columns existed (run `22aa157c`, 134 rows) were backfilled with
  `extract-metrics-benchmark` / `1.0.0` / `gpt-6.1-sol`. The model was identified from the Codex
  session log that saved the run.
- Bump rule: patch for wording changes that don't affect outcomes, minor for compatible additions,
  major for rules that change which assertions are metrics. The fixes above are a major change
  (2.0.0).

## Known limitations

- This review was done by one reviewer against a definition stated here, not one already in the spec.
  Groups C and D are policy questions, not settled errors.
- Run `22aa157c` stays in `testbed.metrics`, because runs are immutable snapshots. A corrected run
  will sit beside it, and evaluation must name the run explicitly.
- The Gold Metrics view (`metrics_handler.go`, `testbedMetricsQuery`) shows the latest run per
  document. It does not display `skill_name`, `skill_version` or `model_name` yet.
