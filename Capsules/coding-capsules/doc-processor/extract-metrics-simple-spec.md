# extract_metrics_simple

`extract_metrics_simple` extracts the same `kb.metrics` rows as `extract_metrics` [1] at a
fraction of the cost, accepting some loss of quality. It exists to be compared with
`extract_metrics` on the metric benchmark; whether to deploy it is decided from those scores and
costs. Status (2026-11-01): built, opt-in only, not in any default processor list. Contract:
openspec change `extract-metrics-simple` [2].

## 1. What differs from extract_metrics

| | extract_metrics | extract_metrics_simple |
|---|---|---|
| LLM calls | Pass 1 per chunk + Pass 2 per batch of candidates (+ coverage and value-review retries) | one per chunk (a failed call is retried once as two halves) |
| Request layout | chunk first, instructions after (`DocumentFirst = true`) | instructions as the system message, chunk as the user message (`DocumentFirst = false`) |
| Prompt | candidates v30 (40 KB) + enrich v29 (70 KB) | `prompt-extract-metric-simple-v1.md` (24 KB) |
| Output | long keys, every field, English for most fields, `objects`, `frame` | short keys, empty keys left out, English only for name, subject and condition |
| Set-aside items | `dropped_candidates` per candidate | `x` list: lines, name, reason |

Why the layout matters: with the chunk first, the instructions follow variable text and are never
a cached prefix across chunks or documents. Run 240 (record 800) had 800k cache-miss input tokens
against 79k hits. With the instructions as the system message, every call of every document shares
one prefix, billed at 2% of the miss price once DeepSeek has cached it.

**Warm-up.** A new DeepSeek prefix becomes reusable about 60 s after the call that planted it
(KnowledgeStore bug 2026081601). The first call of a run therefore goes alone; the others wait until
it returned and either at least half of its input was cached (the prefix was warm already) or 60 s
have passed since it started. The coordinator's `LLM_CALL_STAGGER` (1 s) is too short to prime a
prefix and applies only to the seed processor.

## 2. Output contract

`{"lang": "zh", "m": [rows], "x": [set-aside items]}`. Row keys:

| Key | Field | | Key | Field |
|---|---|---|---|---|
| `n` | `metric_name` | | `c` | `condition` |
| `ne` | `metric_name_en` | | `ce` | `condition_en` |
| `s` | `subject` | | `l` | `source_line_spans` |
| `se` | `subject_en` | | `t` | `source_table_rows` |
| `v` | `metric_value` | | `vs` | `value_structure` |
| `u` | `unit` | | `lo`, `hi` | `value_min`, `value_max` (only for a range not written `a~b`, `a-b`, `a±b`) |
| `r` | `value_range_type` | | `g` | `reasoning_tags` |
| `k` | `value_class` | | `d` | `formula_or_definition` |
| `cat` | `metric_categories` | | | |

There is no `frame` key: the model writes resources, methods and stages as labelled condition parts
(`试验装置：5等量块`, `药物：50％葡萄糖`, `给药途径：静脉推注`, `治疗阶段：…`), which `applyMetricFrames`
already moves into `frame` for every row (`metricConditionLabelFacets`). Lost against
`extract_metrics`: the `device` role and `frame.procedure.step` (used only by the provision link).

`x` items are `{"l", "n", "r"}` with the drop reasons of `extract_metrics`, plus `no_value` for a
quantity whose value is left open (the shared `no_value` stage would set such a row aside anyway).
They are saved to `kb.metrics_dropped` with stage `enrich`. A row without `n` or `l` is set aside as
`invalid_row`. Rows and items whose lines are all overlap lines are discarded, as Pass 1 discards
overlap-only candidates.

## 3. Fields built in code

`expandSimpleMetricRow` (`extract-metrics-simple.go`) fills what the model no longer writes:

- `candidate_id` `<chunk seq>_<n>`, numbering the chunk's rows, then its set-aside items
- `context` and `threshold_or_target`: the text of the cited lines (a table line gives its header
  rows and the cited data rows), cut to 300 characters; table rows then get the table context
  `applyTableMetricContextsForRecord` builds
- `table_name_or_section`: the nearest `heading-*` or `table-caption` line at or before the row
- `location_type` `table` or `text`; `value_data_type` `number` or `string`
- `value_class_en` = `value_class`; `unit_en` from a table of common Chinese units (次 → times,
  个 → pcs, 次/日 → times/d), else the unit itself
- `keywords` / `keywords_en`: name and subject; `metric_categories`, when the model gives none: the
  value class
- `confidence` 0.8; `is_explicit_metric` true for numeric range types
- empty: `desc`, `desc_en`, `context_en`, `measurement_frequency`; no `objects`, so
  `synthesizedObjectItems` builds the object from `subject`

## 4. Shared with extract_metrics

The processor is `MetricsProcessor` in simple mode (`name`, `simple`; `NewMetricsSimpleProcessor`).
Everything after the LLM calls is the same code: `finishMetricRows` (frames, condition inheritance,
dedup, value notation, resource-spec rows, pure requirements, `no_value`, the open-value decision),
then save or merge, provision links, objects, the `.metrics` file, the ontology harvest, incoming
reference resolution and Phase C indexing. Its logs, statuses and `kb.doc_proc_logs` rows carry
`extract_metrics_simple`; the per-chunk log activity is `extract_metrics_simple`, and LLM usage
events have `call_reason = extract_metrics_simple`. Not done: the multi-value review call; rows with
an unclassified combined value stay `unresolved` with tag `value_review_unresolved`.

## 5. Configuration and use

- Prompt: env `EXTRACT_METRICS_SIMPLE_PROMPT`, default `prompt-extract-metric-simple-v1.md`
- Model: env `EXTRACT_METRICS_SIMPLE_MODEL_NAME`, falling back to `ENRICH_METRICS_MODEL_NAME`, then
  `EXTRACT_METRICS_MODEL_NAME` (the enrich pass's model, so a comparison uses the same model)
- Concurrency: `EXTRACT_METRICS_MAX_TASKS` (sequential path), the coordinator's limits otherwise
- Selectable when listed in `config.local.toml` `[doc-processing].required_processors`; never in
  `default_processors`. A run that selects both metric processors is refused
  (`metricProcessorConflict`), because both write the record's `kb.metrics` rows.

Comparing the two: run one processor on a record with `force_clear`, score it (`score_io.py` or
the in-app Benchmark page, which score whatever `kb.metrics` holds), run the other, score again.
`kb.metrics.prompt_name` shows which processor wrote the rows. Read costs from `llm_usage_event`
by `run_id` and `call_reason`, and judge caching on a second run: the first run after a prompt
change always measures about 0 cache hits.

## 6. Measurements

Before (extract_metrics, 2026-10-19, DeepSeek flash off-peak: hit ¥0.02, miss ¥1, output ¥4 per
million tokens):

| Record | Calls | Input | Output | Total |
|---|---|---|---|---|
| 800 (run 240) | 17 + 32 | ¥0.80 | ¥0.60 | ¥1.40 |
| 416 (run 237) | 10 + 9 | ¥0.27 | ¥0.07 | ¥0.34 |

About 630 output tokens per stored row (126 candidate + 504 enrich); of the enrich output, 31%
was key names, 32% English text, 20% `objects`, 11% almost-always-empty fields.

extract_metrics_simple, record 416, 2026-11-01, in-process run of the real model (deepseek-flash,
thinking disabled) on the record's 10 chunks, nothing saved:

| | Calls | Cache hit | Cache miss | Output | Total | Rows kept | Set aside |
|---|---|---|---|---|---|---|---|
| prompt v1, set-aside list unrestricted | 10 | 57,600 | 17,639 | 6,178 | ¥0.044 | 30 | 111 |
| prompt v1 as committed (list only statements with a number or a named quantity) | 10 | 57,856 | 18,093 | 3,974 | ¥0.035 | 30 | 37 |

The warm-up worked: the first call had no cache hits, every later call 6,400 of about 7,500 input
tokens. Run time 83 s, 60 s of it the warm-up wait (a cold prefix). The 30 rows covered all 27
extract_metrics rows of run 237 with the same values and units; three more rows were 分类垃圾容器数量
≥2 个, 聚乙烯瓶容积 500 ml and 农村户用沼气池容积 ≤50 m³ (the last a scope that gold rule X5 excludes);
two conditions extract_metrics had (室温, 培养条件：黑暗) were missing. Not yet scored against gold.

## 7. References

[1] `KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-metrics-spec.md` \
[2] `ChenWeb/openspec/changes/extract-metrics-simple/` (spec `metric-simple-extraction`, design,
tasks) \
[3] `KnowledgeStore/doc-repo/bugs/202608/2026081601-bug-pass2-enrich-merge-resolve-zero-prompt-cache.md`
