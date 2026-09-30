# Extract-Metrics Review Report, Record 416 — research report on what the metric extractor got right and wrong for one standard

**Date:** 2026-09-29 \
**Scope:** A manual, line-by-line review of the `extract_metrics` output for input record 416
(农村生活垃圾分类处理规范, *Specification for source separation and treatment of rural domestic
solid waste*, 2018). It answers three questions: which metrics were missed, which rows are not
metrics, and whether each row's attributes are correct. Open this when tuning the extraction prompt,
the post-extraction filter ([2026092902-devdoc-extract-metrics-filter.md](2026092902-devdoc-extract-metrics-filter.md)),
or the re-run merge logic. \
**Code root:** `ChenWeb/server/api/kbhandler/extract-metric-handler.go`,
`ChenWeb/prompts/prompt-enrich-metrics-v5.md`

## Summary

The source is a short provincial standard (164 extracted lines). Most of it is organisational
("the village shall set up a ledger"); only a handful of clauses carry real numbers — the fertilizer
quality tables (Tables 2 and 3), the seed-germination test in Appendix B, a few counts and
frequencies.

The extractor stored **73 rows** for it. Our review finds that **about 41 are genuine metrics** and
the extractor found **every numeric metric in the document** — nothing numeric was missed. The
problems are on the other side:

- **17 rows are not metrics at all**: slogans ("日产日清"), a category count ("four kinds of waste"),
  pointers to tables that were already extracted, and the conditions that describe *where* a
  treatment method suits a village (population density, amount of kitchen waste) with no value.
- **8 rows are duplicates** created when the extractor was re-run on 2026-09-20. The re-run's merge
  step absorbed 52 repeats correctly but let these 8 through under new IDs.
- **7 rows are the inputs of a formula** (germination rate, root length) — they belong inside the
  germination-index definition, not as metrics on their own.
- Among the rows we keep, the recurring attribute faults are: the `condition` field is **empty on
  all 73 rows** even where the text states a condition ("dry basis", "at room temperature"); the
  comparison sign is mixed into the value ("≥30" instead of "30"); `value_min`/`value_max` were never
  filled; and several free-text fields use a dozen spellings for the same idea.

## Details

### Data examined

| Item | Value |
|---|---|
| `kb.inputs.id` | 416, `doc_no` empty, parser `mineru`, `pipeline_state = success` |
| Source text | `~/Apps/SemOS/Artifacts/0/416/std_1503937_mineru.txt` (164 lines) |
| `kb.metrics` rows | 73 — 56 created 2026-08-22, 17 created 2026-09-20 |
| Model / prompt | `deepseek-v4-flash` / `prompt-enrich-metrics-v5.md` (all rows) |
| Re-run merge | 52 rows carry `ext_info.merge_log` entries from the 2026-09-20 run (`absorbed_metric_ids`) |

Metric IDs below are `metric_id` values with the `416_` prefix dropped (`mtc_12` = `416_mtc_12`).
"L" means source line number.

### 1. Missed metrics

**No numeric metric was missed.** Every number that expresses a requirement or a test parameter
(L85, L96, L99, L116 volume, L123, L126, L129, L153, L154, L158) has at least one row.

There are **consistency gaps** — items of the same kind the extractor *did* keep elsewhere, so by its
own standard they are missing. None is high-value; list them only if the pipeline intends to keep
"complies with standard X" rows (it currently does: `mtc_48`–`51`, `mtc_53`, `mtc_54`).

| Line | Candidate | Why it counts as a gap |
|---|---|---|
| L116 (Table 1, 机器成肥 / 太阳能辅助堆肥) | Composting harmlessness — 堆肥发酵过程符合 CJJ 52 无害化要求 | Same shape as `mtc_48`–`51` (standard-referenced requirement) |
| L116 (Table 1, 太阳能辅助堆肥) | Wastewater and odour discharge — 废水和恶臭污染物达标排放 | Same as `mtc_50` (恶臭污染物排放) for a different facility |
| L116 (Table 1, 卫生填埋) | Landfill pollution control — 符合 GB 16889 | Same as `mtc_49` |
| L116 (Table 1, 焚烧处理) | Incinerator flue-gas / pollution control — 尾气达标排放, 符合 GB 18485 | Same shape |
| L138 | Sorting accuracy — 垃圾分类的准确率 | A named performance indicator (a KPI) with no value; comparable to `mtc_43`, which was kept |

Things deliberately **not** listed as misses: publication/implementation dates (L3–L4), clause
numbers, the reference list, "定期" (periodically) in L132/L138 (no measurable content), and the
"无臭气、无污水、无地面垃圾" site condition (L121), which is an inspection criterion, not a quantity.

### 2. Rows that should not be metrics

#### 2a. Not a metric — remove (17 rows)

| Row(s) | Line | Name | Reason |
|---|---|---|---|
| `mtc_2` | L50 | 分类类别数 = 4 类 | Counts the items in a definition ("four categories"). A classification scheme, not a measurable property. Also marked `is_explicit_metric = true`, confidence 0.8 — the worst false positive in the set |
| `mtc_93` | L41 | 日产日清 | Slogan/principle. Its concrete content (daily collection) is already captured by `mtc_1` and `mtc_30` |
| `mtc_94` | L41 | 应收尽收，应分尽分 | Slogan ("collect all that should be collected") |
| `mtc_95` | L44 | 用地指标 | Says land-use quotas must be *included in county planning*; the document states no quota |
| `mtc_41`, `mtc_42`, `mtc_92` | L103 | 垃圾数量 / 收运作业时间 / 作业时间 | Factors the collector should consider when staffing; the sentence imposes nothing on the quantities themselves. `mtc_92` also duplicates `mtc_42` |
| `mtc_43` | L109 | 可回收物收购频次 = 定期 | "Periodically" — no value, no referenced standard, nothing checkable |
| `mtc_33` | L116 | 垃圾日处理量 | Design input to the sizing of the solar composting room (see `mtc_34`), not itself constrained |
| `mtc_36`–`mtc_40` | L116 | 日人均生活垃圾量, 人口密度, 易腐垃圾量, 易腐垃圾纯度, 有机肥需求量 | Table 1's "适用范围" column: qualitative descriptions of which villages suit which treatment method ("population density high"). They are applicability conditions of the treatment-mode provisions, not metrics of this document |
| `mtc_55`, `mtc_104` | L123 | 肥料其他指标 = 达到表2和表3的要求 | Pointer to Tables 2/3, whose contents are already rows `mtc_4`–`11`. `mtc_104` is also a duplicate of `mtc_55` |
| `mtc_56` | L123 | 重金属限量 = 达到表3的要求 | Pointer to Table 3. Its useful content — *which* fertilizer Table 3 applies to — belongs in the `condition` of `mtc_7`–`11` (see §3) |

#### 2b. Duplicates from the 2026-09-20 re-run — remove (8 rows)

The re-run's merge absorbed 52 repeats, but these slipped through with new IDs because the name or
subject was worded slightly differently:

| Duplicate | Original | Difference that defeated the merge |
|---|---|---|
| `mtc_69` 新鲜物料试样数量 | `mtc_12` 试样数量 | name prefix, subject |
| `mtc_70` 每个试样干基质量 | `mtc_13` 干基质量 | name prefix; value "20.0" vs "≥20.0" |
| `mtc_71` 聚乙烯瓶容量 | `mtc_14` 具塞聚乙烯瓶容量 | name; unit "ml" vs "mL" |
| `mtc_77` 蒸馏水空白对照数量 | `mtc_20` 空白对照数量 | name prefix |
| `mtc_79` 水堇或萝卜种子数量 | `mtc_23` 种子数量 | name prefix, subject |
| `mtc_83` 每个样品重复次数 | `mtc_27` 重复次数 | name prefix |
| `mtc_88` 收运频率 (qualitative) | `mtc_30` 定时收运频次 (1 次/日) | the re-run classified the same clause as qualitative |
| `mtc_101` 种子发芽指数阈值 | `mtc_47` 发芽指数判定阈值 | name |

`mtc_92` and `mtc_104` are also duplicates but are already removed under 2a. The pattern — the
same span, same value, name differing by a qualifier prefix — suggests the merge key should include
`(source_line_spans, metric_value, unit)` and not rely on name similarity alone.

#### 2c. Formula inputs — demote into the definition (7 rows)

`mtc_28` 发芽率, `mtc_29` 根长, `mtc_45` 种子发芽率, `mtc_46` 种子平均根长, `mtc_98` 处理的种子平均根长,
`mtc_99` 蒸馏水的种子发芽率, `mtc_100` 空白的种子平均根长 (L154, L156).

These are the four operands of the germination-index formula (B.1). The standard sets no requirement
on any of them; they exist only to compute the index. They should live as variables inside
`mtc_44`'s `formula_or_definition`, not as metrics. They are also internally duplicated
(`mtc_28`≈`mtc_45`, `mtc_29`≈`mtc_46`, and `mtc_98`–`100` split `mtc_45`/`46` by group).

#### 2d. Kept (41 rows)

| Group | Rows | Note |
|---|---|---|
| Collection & household requirements | `mtc_1`, `mtc_3`, `mtc_30`, `mtc_68` | `mtc_68` (limit set by agreement → `limit_absent`) is a model example of a correct no-number row |
| Equipment parameters that must be declared | `mtc_31` 比能耗, `mtc_32` 发酵周期, `mtc_34` 单室体积 | Real quantities whose value is fixed by the equipment or design — reclassify (§3) |
| Scope threshold | `mtc_35` 沼气池容积 50 m³ | Keep, but reclassify (§3) |
| Standard-referenced requirements | `mtc_48`–`51`, `mtc_53`, `mtc_54` | Acceptable as qualitative rows |
| Fertilizer quality | `mtc_4`–`11`, `mtc_52` | The core of the document; values correct |
| Germination test method (Appendix B) | `mtc_12`–`27` | All values correct; see note on subject below |
| Germination index | `mtc_44` (definition), `mtc_47` (100 % interpretation boundary) | `mtc_44` and `mtc_52` are one metric — see §3 |

### 3. Correctness and appropriateness of attributes (kept rows)

**Values are correct.** Every kept row's number and unit matches the source text. The faults are in
how the values are shaped and in the descriptive fields.

#### 3a. Systemic issues (affect many rows)

| # | Issue | Rows | Fix |
|---|---|---|---|
| A1 | **`condition` is empty on all 73 rows**, although the text states conditions: "以烘干基计" (dry basis), "鲜样" (fresh sample), "室温" (room temperature), "25℃黑暗", "以干重计", and the scope "机器成肥产出的肥料" vs "太阳能辅助堆肥产出的成品肥料" | `mtc_4`–`11`, `mtc_15`, `mtc_18`, `mtc_25`, `mtc_52` | Prompt v5 defines `condition`; the model ignores it. Move the basis qualifier out of `metric_name` (`有机质的质量分数（以烘干基计）` → name `有机质质量分数`, condition `以烘干基计`) |
| A2 | **Comparator inside `metric_value`**: "≥30", "≤15", "≥20.0", "≥100", "≥40" — but `mtc_52` stores "60", `mtc_70` "20.0" | `mtc_4`,`5`,`7`–`11`,`13`,`16`,`17` | `metric_value` should be the bare number; the comparator is already carried by `value_range_type` |
| A3 | **`value_min`/`value_max` NULL on every row**, including the two ranges (`mtc_6` pH 5.5~8.5, `mtc_21` 0～4 ℃), which prompt v5 says must be filled | `mtc_6`, `mtc_21` | Not data-losing today — `metric_normalizer.go`'s `reWholeRange` fallback parses both — but the prompt contract is not being met |
| A4 | **Wrong subject for Tables 2/3**: all eight rows say `肥料`. Table 2 applies only to 机器成肥 fertilizer; Table 3 applies to both 机器成肥 and 太阳能辅助堆肥 (L123) | `mtc_4`–`11` | Subject `成品肥料` + condition naming the production method(s) |
| A5 | **`value_data_type` has 12 spellings**: integer, number, numeric, float, percentage, ratio, string, text, qualitative, length, standard_reference, table_reference | all | Needs a closed vocabulary like `value_range_type`; `qualitative` (`mtc_92`) is a range-type value leaking into this field |
| A6 | **`location_type` has 12 spellings** mixing document structure (section, clause, list_item, list-item, table, appendix, standard_annex) with physical places (rural_area, treatment_facility) | all | Closed vocabulary; drop the physical-place values |
| A7 | **`metric_categories` language drift**: English snake_case in the Chinese field for some rows (`mtc_1` `["waste_management"]`), Chinese for others (`mtc_101`) | all | Chinese in `metric_categories`, English in `metric_categories_en` |
| A8 | **Subject convention varies**: actor (`mtc_1` 生活垃圾收运单位) vs object (`mtc_30` 其他垃圾) for the same kind of clause; Appendix B rows use 11 different subjects (试样, 浸出液, 往复式水平振荡机, 培养箱, …) | `mtc_1`, `mtc_12`–`27` | Subject = the thing measured (waste stream, fertilizer, the test method 植物种子发芽试验) |
| A9 | **Invented placeholder text** in `threshold_or_target` of qualitative rows ("按数量配置（未给出具体值）", "较大（未给出具体值）") | removed rows mostly | Prompt says leave empty; the filter should strip these |
| A10 | **Downstream linkage missing on the re-run rows**: `keyword_concept_id` is NULL on all 17 rows created 2026-09-20 | `mtc_68`–`104` | Only `mtc_68` survives this review; re-run keyword linking for it |

#### 3b. Row-specific issues

| Row | Field | Stored | Should be | Why |
|---|---|---|---|---|
| `mtc_1` vs `mtc_30` | `value_range_type` | `lower_bound` vs `exact` | the same for both | Identical wording ("应每日定时收运") classified two ways. `exact` (once per day, at a set time) is closer to the text |
| `mtc_6` | `metric_unit` | `pH` | empty / dimensionless | pH is a dimensionless scale, not a unit |
| `mtc_15` | `metric_unit` | `W/V` | `g/mL` (or `ratio`) + condition `以干重计` | W/V names the basis, not a unit; prompt v5 says dimensionless ratios use `ratio` |
| `mtc_14` | `metric_unit` | `mL` (and `ml` in dup `mtc_71`) | `mL` | Unit spelling should be normalised |
| `mtc_27` | `metric_unit` | `个` | `次` | These are repetitions, not items |
| `mtc_31`, `mtc_32`, `mtc_34` | `value_range_type` | `qualitative` | `limit_absent` | The text says the value is set by the equipment/design ("设备应明确…比能耗、发酵周期"; "根据垃圾日处理量合理设置单室体积") — exactly prompt v5's `limit_absent` case |
| `mtc_34` | `condition` | empty | `根据垃圾日处理量` | Carries the sizing rule that `mtc_33` was trying to express |
| `mtc_35` | `value_class` / shape | `upper_bound`, `reference` | condition on an NY/T 90 conformance requirement | "容积在50立方米以下的农村户用沼气池应符合NY/T 90" is a scope boundary deciding which standard applies, not a cap on digester size. As stored, it reads as "digesters must be ≤ 50 m³", which is wrong |
| `mtc_44` / `mtc_52` | identity | two unrelated rows (发芽指数 / 植物种子发芽指数) | one metric | `mtc_44` holds the definition, `mtc_52` the requirement ≥ 60 %. They should share a metric identity so the requirement links to its definition |
| `mtc_47` | `value_range_type` | `exact` | `exact` with `value_class = reference` is tolerable, but see note | 100 % is an interpretation boundary (below = phytotoxic, above = growth-promoting), not a required value. The closed enum has no "boundary" type; record the limitation rather than force it |
| `mtc_98`–`100` (demoted) | `measurement_frequency` | `每个样品做3个重复` | — | Replication count stored as a frequency (moot once demoted, but shows field misuse) |

### Overall tally

| Verdict | Rows |
|---|---|
| Keep (with attribute fixes) | 41 |
| Remove — not a metric | 17 |
| Remove — re-run duplicate | 8 |
| Demote into formula definition | 7 |
| **Total stored** | **73** |
| Missed numeric metrics | 0 |
| Consistency-gap candidates | 5 |

Precision is therefore about 56 % (41/73) and recall of numeric metrics is 100 %. The false
positives are dominated by qualitative rows: 24 of the 32 removed/demoted rows have
`is_explicit_metric = false`, and every row with confidence below 0.5 is among them. Of the 8
removed rows flagged `is_explicit_metric = true`, 7 are re-run duplicates of correct rows; the only
genuine false positive with that flag is `mtc_2` (the category count), which is the case the
planned LLM filter was written for.

### Recommendations, by leverage

1. **Fix the re-run merge key** (2b) — it silently grows the table on every re-run.
2. **Enforce the prompt's own contract** for `condition`, bare `metric_value`, and
   `value_min`/`value_max` (A1–A3) — the prompt already asks; add a validator that rejects rows
   whose `metric_value` starts with a comparator, and logs rows with a range type but no endpoints.
3. **Close the free-text vocabularies** `value_data_type` and `location_type` (A5, A6).
4. **Filter rules** for the post-extraction filter: drop slogans, category counts, table pointers,
   applicability descriptors without values, and formula operands (2a, 2c).

## Known limitations

- This is one document, reviewed by hand. The percentages above are indicative of the failure
  modes, not a benchmark.
- "Is this a metric?" is partly a policy decision. This review applies a precision-first reading:
  a metric needs a value, a pointer to a standard that supplies one, or an explicit statement that
  the value is set elsewhere (`limit_absent`). A pipeline that wants to keep applicability
  descriptors or formula operands as ontology terms would count 2a/2c differently.
- The review did not change any database rows; all 73 rows remain as stored on 2026-09-29.
