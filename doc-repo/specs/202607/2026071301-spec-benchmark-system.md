# ADR 2026071301 — Doc Processor Benchmark System

**Date:** 2026-07-13 \
**Status:** Proposed \
**Component:** ChenWeb — `server/api/doc-processing`, benchmark harness, reporting \
**Authors:** Chen Ding, Codex \
**Tags:** doc processor, benchmark, evaluation, quality, cost, latency

---

## Context

The doc-processor pipeline has grown into a multi-stage system with:

- deterministic structural processors such as `blocking`, `structure_analyzer`,
  and `chunking`
- extraction processors such as `extract_metadata`, `extract_metrics`,
  `extract_provisions`, `extract_entity_relation`, and
  `extract_inventory_items`
- generative processors such as `generate_summaries`, `generate_topics`, and
  `generate_scene_blocks`
- run-time concurrency, prompt-cache optimization, and per-call telemetry

The current system already provides strong operational observability:

- the pipeline contract and processor topology are documented in the
  doc-processor capsule [1]
- `kb.doc_proc_logs` records per-call and per-processor execution data,
  including latency and prompt-cache counters [2]
- OpenTelemetry traces describe run-time flow across Phase A, Phase B, and
  Phase C [3]
- `kb.doc_process_runs` provides first-class run identity for each pipeline
  invocation [4]

What is still missing is a benchmark system that answers the harder product
questions:

- Did a processor change improve or degrade output quality?
- Which documents or document classes regress?
- Did a prompt or model change trade quality for latency or cost acceptably?
- Can a candidate change be promoted safely?

Today, quality evaluation is mostly ad hoc: inspect artifacts manually, compare
selected outputs, and infer trends from logs. That does not scale across many
processors, many document types, and repeated reprocessing of the same records.

The benchmark system therefore needs to evaluate both:

1. **Pipeline health** — whether the processor ran successfully, efficiently,
   and repeatably.
2. **Artifact quality** — whether the produced artifact is correct, faithful,
   useful, and properly grounded in source lines/pages.

These two dimensions must be tracked separately. A processor can be operationally
healthy but semantically poor, or semantically strong but too slow, expensive,
or failure-prone.

---

## Decision

### DB1 — Introduce a first-class benchmark domain

The benchmark system is a separate evaluation domain that reuses the production
doc-processing pipeline instead of re-implementing it.

Core entities:

- `benchmark_suite` — a named, versioned collection of benchmark cases, such as
  `contracts_v1` or `mixed_ocr_v1`
- `benchmark_case` — one document plus metadata, target processors, and scoring
  expectations
- `benchmark_gold_artifact` — expected output or scoring rubric for one case and
  one processor
- `benchmark_run` — one execution of one processor configuration against one
  suite
- `benchmark_result` — one scored result for one case, processor, and metric
- `benchmark_judgment` — optional human or LLM-judge rubric evaluation attached
  to a result

This domain is intentionally separate from `kb.doc_proc_logs` and
`kb.doc_process_runs`, but it must join to them via `run_id`, `record_id`, and
benchmark IDs.

### DB2 — Benchmark execution must reuse the normal pipeline

The benchmark harness must launch the standard doc-processing flow rather than a
special benchmark-only processor path.

Rationale:

- it exercises the real pipeline, including Phase A/Phase B/Phase C behavior
- it naturally captures logs, traces, cost, and cache telemetry
- it avoids divergence between "production behavior" and "benchmark behavior"

Each benchmark case execution creates or reuses a `kb.inputs` record, launches a
normal doc-processing run, and records the resulting `kb.doc_process_runs.id` as
the benchmark run's underlying pipeline run.

### DB3 — Benchmark scoring is processor-specific, not one-size-fits-all

The benchmark system must not use a single score formula for all doc processors.
Processors fall into different evaluation classes.

#### DB3.1 Structural processors

Processors:

- `blocking`
- `structure_analyzer`
- `chunking`

Metrics:

- schema validity
- ordering correctness
- coverage of input lines
- boundary precision / recall against gold spans
- overlap and duplication errors
- orphan-line count

#### DB3.2 Extraction processors

Processors:

- `extract_metadata`
- `extract_metrics`
- `extract_provisions`
- `extract_semantic_projections`
- `extract_entity_relation`
- `extract_inventory_items`

Metrics:

- field-level exact match or normalized match
- object/entity precision
- object/entity recall
- F1
- relation precision / recall / F1 where applicable
- schema validity
- duplicate-rate
- unsupported hallucination rate
- grounding completeness: does the output cite line/page provenance where the
  schema requires or supports it?

#### DB3.3 Generative processors

Processors:

- `generate_summaries`
- `generate_topics`
- `generate_scene_blocks`

Metrics:

- faithfulness to source
- coverage of important content
- conciseness / redundancy
- actionability or usefulness
- formatting/schema compliance

These are primarily rubric-scored. Exact-match evaluation is not sufficient.

### DB4 — Provenance is a benchmark requirement

Where a processor's artifact format can reasonably include source grounding, the
benchmark system treats provenance as a first-class quality property.

Preferred grounding fields:

- `page_number`
- `line_number`
- line-span or page-span where relevant

If a processor omits provenance for an extractive claim that should be grounded,
its quality score must be penalized even if the semantic content looks correct.

This reduces the risk of fluent but weakly supported outputs and makes human
spot-checking much cheaper.

### DB5 — Measure four metric families separately

Every benchmark report must separate metrics into four families:

1. **Correctness**
   - artifact-level semantic quality
2. **Robustness**
   - quality across noisy OCR, long documents, tables, mixed layouts, and edge
     cases
3. **Efficiency**
   - latency, token use, cache-hit rate, retries, and cost
4. **Operability**
   - pipeline success rate, stuck-run rate, partial-failure rate, and
     reproducibility

The benchmark system may publish a weighted composite score, but the individual
families remain visible and queryable. A single composite score alone would hide
important tradeoffs.

### DB6 — Gold data uses three evidence tiers

The benchmark suite uses three levels of supervision:

#### Tier 1 — Exact gold

Small, carefully labeled datasets with precise expected outputs. This is the
highest-trust set and is used for regression gating.

#### Tier 2 — Weak or partial gold

Partially labeled data or "silver" labels derived from previously trusted runs
and then reviewed. This is useful for broader trend tracking where full manual
annotation would be too expensive.

#### Tier 3 — Rubric judgment

Human and/or LLM-judge scoring using explicit rubrics. This is required for
generative tasks such as summaries and topics, and may supplement Tier 1/2 for
ambiguous extraction tasks.

### DB7 — LLM-as-judge is allowed only with calibration and auditability

LLM-based judging is useful, but it must not be the only authority for
high-stakes benchmark conclusions.

Requirements:

- use explicit rubrics, not vague free-form judging
- retain the judge prompt version and model name
- store rationale and subscores when possible
- periodically calibrate against human review on a fixed audit subset
- do not allow judge-only pass/fail promotion for critical extractive processors
  without human spot-checks

### DB8 — Benchmark suites are versioned and partially protected from overfitting

Each benchmark suite must be versioned. Changes to:

- case membership
- gold labels
- rubrics
- scoring rules

produce a new suite or suite revision.

The system should support:

- a visible regression suite for day-to-day development
- a larger nightly suite
- an optional holdout suite not routinely exposed in detail, to reduce prompt
  overfitting and benchmark gaming

### DB9 — Benchmark reports evaluate both artifact-level and pipeline-level behavior

Every benchmark run produces two related views:

#### Artifact-level view

Per case and per processor:

- semantic score
- schema validity
- grounding quality
- error notes

#### Pipeline-level view

Across the run:

- end-to-end success/failure
- p50 / p95 latency
- token/cost totals
- cache-hit ratios
- retry behavior
- stuck-run and crash outcomes

This separation is required because a processor may look strong in isolation
while still harming the end-to-end pipeline through instability, latency, or
downstream incompatibility.

### DB10 — Initial rollout is intentionally narrow

Version 1 of the benchmark system should focus on a useful, maintainable
subset:

- suites of 20 to 50 documents
- representative document classes:
  - clean text-heavy
  - OCR-noisy
  - table-heavy/spec-heavy
  - long documents
  - adversarial edge cases
- initial scored processors:
  - `extract_metadata`
  - `extract_metrics`
  - `extract_entity_relation`
  - `generate_summaries`

Other processors can be added incrementally once the data model, run harness,
and scoring/reporting loops are stable.

---

## Benchmark Data Model

The following logical schema is recommended. Table names may be refined during
implementation, but the separation of concerns should remain.

### 1. `kb.benchmark_suites`

Fields:

- `id`
- `suite_name`
- `suite_version`
- `status` (`draft`, `active`, `retired`)
- `description`
- `tags`
- `created_by`
- `create_time`

### 2. `kb.benchmark_cases`

Fields:

- `id`
- `suite_id`
- `case_name`
- `document_type`
- `source_kind` (`pdf`, `line_file`, other)
- `source_path`
- `metadata` JSONB
- `difficulty` (`easy`, `medium`, `hard`, `adversarial`)
- `target_processors` JSONB
- `enabled`
- `create_time`

Recommended `metadata`:

- language
- page_count
- line_count
- OCR quality class
- table density
- image density
- layout complexity

### 3. `kb.benchmark_gold_artifacts`

Fields:

- `id`
- `case_id`
- `processor_name`
- `gold_type` (`exact`, `partial`, `rubric`)
- `artifact` JSONB
- `rubric` JSONB
- `notes`
- `create_time`

### 4. `kb.benchmark_runs`

Fields:

- `id`
- `suite_id`
- `run_name`
- `status`
- `trigger_mode` (`manual`, `ci`, `nightly`)
- `candidate_label`
- `baseline_label`
- `config_snapshot` JSONB
- `doc_process_run_ids` BIGINT[]
- `started_at`
- `finished_at`
- `error_message`

`config_snapshot` should capture effective benchmark knobs such as:

- models
- prompt refs
- required processors
- environment flags
- concurrency mode

### 5. `kb.benchmark_results`

Fields:

- `id`
- `benchmark_run_id`
- `case_id`
- `record_id`
- `doc_process_run_id`
- `processor_name`
- `metric_family`
- `metric_name`
- `score_numeric`
- `score_label`
- `passed`
- `details` JSONB
- `create_time`

### 6. `kb.benchmark_judgments`

Fields:

- `id`
- `benchmark_result_id`
- `judge_type` (`human`, `llm`)
- `judge_model`
- `rubric_version`
- `subscores` JSONB
- `rationale`
- `create_time`

---

## Execution Model

### 1. Suite selection

The operator or CI job selects:

- a benchmark suite
- a candidate configuration
- optionally a baseline configuration for comparison

### 2. Case materialization

For each case, the harness prepares a benchmark record:

- either reuse a canonical line file
- or stage a source document and let the standard upstream pipeline create the
  line file

Version 1 should prefer canonical line-file inputs where possible, because they
reduce non-doc-processor variance and isolate processor quality more cleanly.

### 3. Pipeline execution

The harness launches the normal doc-processing pipeline using the target
processor set and configuration.

The harness records:

- `record_id`
- `kb.doc_process_runs.id`
- processor set
- effective configuration

### 4. Artifact collection

After the run completes, the harness gathers:

- artifacts written by the processors
- `kb.doc_proc_logs`
- run status from `kb.doc_process_runs`
- traces and timing summaries as needed

### 5. Scoring

The scorer loads the matching gold artifact and applies the appropriate scoring
function for each processor and metric family.

### 6. Reporting

The report layer produces:

- case-level failures
- processor-level aggregates
- suite-level pass/fail
- candidate vs baseline deltas

---

## Scoring Model

The benchmark system should support both hard gates and weighted rollups.

### Hard gates

Examples:

- `extract_metadata` exact/normalized match must be at or above a threshold
- `extract_metrics` F1 must be at or above a threshold
- `generate_summaries` faithfulness must be at or above a threshold
- run success rate must be above a threshold

Hard gates are used for promotion and regression blocking.

### Weighted rollups

An example suite-level composite score:

- correctness: 60%
- robustness: 20%
- efficiency: 10%
- operability: 10%

The exact weights may vary by suite. For example, a cost-sensitive nightly suite
may give efficiency more weight, while a product-release gate should emphasize
correctness and operability.

### Processor-specific examples

#### `extract_metadata`

- normalized field accuracy
- required-field completeness
- false-positive field rate

#### `extract_metrics`

- metric object precision / recall / F1
- unit normalization accuracy
- provenance completeness

#### `extract_entity_relation`

- entity precision / recall / F1
- relation precision / recall / F1
- duplicate cluster rate
- unsupported relation rate

#### `generate_summaries`

- faithfulness
- coverage
- conciseness
- usefulness
- schema/format compliance if structured

---

## Reporting Requirements

The benchmark system should report at least the following:

### Per suite

- total cases
- total failed cases
- total blocked/errored runs
- aggregate score by processor
- family scores: correctness, robustness, efficiency, operability

### Per processor

- pass/fail against thresholds
- score delta vs baseline
- p50 / p95 latency
- token totals
- cache-hit and cache-miss tokens
- failure rate

### Per case

- output artifact
- expected artifact or rubric summary
- mismatches
- provenance failures
- relevant logs and run IDs

---

## Anti-Gaming Rules

The benchmark system should explicitly guard against superficial wins:

1. Schema-valid but semantically wrong outputs must score poorly.
2. Fluent summaries that hallucinate or omit key facts must fail faithfulness.
3. Outputs lacking required provenance must be penalized.
4. Public benchmark details should be sufficient for development but not so
   complete that prompt tuning trivially overfits a tiny fixed set.
5. Candidate quality claims should be supported by both quality and operational
   metrics.

---

## Version 1 Implementation Plan

### Phase 1 — Benchmark spec and storage

- create benchmark tables
- define suite/case/gold JSON contracts
- define processor-specific scoring interfaces

### Phase 2 — Run harness

- materialize cases into runnable records
- launch standard doc-processing runs
- capture `doc_process_run_id` and logs

### Phase 3 — Scorers

Implement V1 scorers for:

- `extract_metadata`
- `extract_metrics`
- `extract_entity_relation`
- `generate_summaries`

### Phase 4 — Reports

- candidate vs baseline comparison
- suite summary
- failed-case drilldown

### Phase 5 — CI/nightly integration

- small regression suite for routine development
- broader nightly suite for trend tracking

---

## Consequences

### Positive

- quality becomes measurable, repeatable, and comparable over time
- prompt/model changes can be evaluated with evidence instead of anecdotes
- operational telemetry and artifact quality are connected in one workflow
- regressions can be caught before broader rollout

### Costs

- building and maintaining gold datasets takes ongoing effort
- generative-task judging requires careful rubric design and calibration
- benchmark infrastructure adds new tables, harness code, and reporting logic

### Risks

- overfitting to a small visible benchmark set
- false confidence if judge quality is weak
- excessive complexity if too many processors are benchmarked at once

These risks are addressed by phased rollout, holdout suites, processor-specific
scoring, and explicit human calibration.

---

## Recommendation

Adopt this benchmark system in a narrow V1 focused on:

- benchmark harness reuse of the real doc-processing pipeline
- versioned suites with 20 to 50 representative documents
- first-class scoring for `extract_metadata`, `extract_metrics`,
  `extract_entity_relation`, and `generate_summaries`
- reports that keep correctness, robustness, efficiency, and operability
  distinct

This provides an actionable foundation without blocking the team on a
full-coverage evaluator for every processor immediately.

---

## References

[1] `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md`

[2] `KnowledgeStore/Capsules/coding-capsules/doc-processor/doc-processor-log-spec.md`

[3] `KnowledgeStore/Capsules/coding-capsules/doc-processor/observability-design.md`

[4] `KnowledgeStore/doc-repo/adrs/202607/2026071201-adr-doc-process-runs.md`
