# Metric frame — a metric records what it uses, how, and at which step, not only when it holds

**Date:** 2026-10-18 \
**Scope:** What a metric's *frame* is (the resources a value uses, its method and its place in a
procedure), how `extract_metrics` fills it, and why the strength of a product is no longer a metric
of its own. Open this when a metric row's condition, resources or method look wrong, when a
strength or concentration seems to be missing as a metric, or when comparing scores from before and
after 2026-10-18.
**Code root:** `ChenWeb/server/api/doc-processing` (`metric_frame.go`, `metric_frame_backfill.go`,
`metric_value_notation.go`, `extract-metrics.go`, `metrics_merge.go`)

**Traceability — openspec:**
- `ChenWeb/openspec/changes/metric-frame/proposal.md` — why this exists
- `ChenWeb/openspec/changes/metric-frame/design.md` — rationale, alternatives considered,
  risks/trade-offs
- `ChenWeb/openspec/changes/metric-frame/tasks.md` — implementation log, including anything not
  independently verified
- `ChenWeb/openspec/changes/metric-frame/specs/` — `metric-frame`, `metric-resource-spec`,
  `metric-frame-benchmark`, and changes to `metric-condition` and `metric-provision-link`; after the
  change is archived they live under `ChenWeb/openspec/specs/`. **Update these spec files, not just
  this doc, if behavior changes** — this doc explains the feature for humans and points at code; the
  specs are the contract for agents.

## Summary

A number in a standard or a treatment protocol rarely stands alone. "Give 40 ml of 50 % glucose by
intravenous push" states one quantity, the 40 ml dose. The "50 %" only says *which* product is
used; it is not something anyone measures or checks on the patient. Before this change the system
had one place for everything around a value, the *condition*, so the extracting model turned
the 50 % into a second metric ("glucose concentration 50 %"). Record 364 (WS/T 810—2022) had four
such rows, and the condition field had grown about 45 different labels, many of which were not
conditions at all: test apparatus, test methods, routes of administration, treatment stages.

Now every metric can carry a **frame** next to its condition:

- **Uses**: the things the value uses, each with its role and, when the source gives one, its own
  specification. Example: the agent 葡萄糖 (glucose) with concentration 50 %; the apparatus 量块
  (gauge block) with grade 5; the reagent 盐酸溶液 (hydrochloric acid) at 0.1 mol/L. The roles are
  agent, material, apparatus, reagent, medium, sample and device.
- **Method**: how the value is applied or measured, for example a test method, a cited test
  standard, or a route such as intravenous push.
- **Procedure**: where the value sits in a procedure: the clause of the step (A.2.4), the stage
  ("after the patient regains consciousness") and the step before it.

The **condition** keeps its original job: when, where, for whom or in what state the value holds
(population, trigger, environment, location, load, the variant of the product).

Three rules come with it:

- **A product's strength, dilution or grade is not a metric** when it only says which product
  another value uses. It is kept with the product in *uses*. The exception is a document that
  specifies the product itself: in a standard for glucose injection, "content 95 %–105 % of the
  label" is still a metric. A requirement on the apparatus, such as "accuracy 0.1 %", is also still
  a metric.
- **A step with a strength but no amount** ("then continue with a 10 % glucose drip") is not a
  metric: there is nothing to measure.
- **Metric names leave out the strength**: "glucose IV push dose", not "50 % glucose IV push dose".
  Two doses that differ only in strength (50 % and 25 %) are still two metrics, because the frame
  is part of what makes a metric unique.

On record 364 A.2.4/A.2.5 the new prompts gave exactly the dose rows with their glucose or mannitol
strength in *uses*, the route in *method* and the clause in *procedure*, and no concentration rows.
The live quality suite (12 cases, including the older test-equipment cases from record 371) passed.

The answer key and the scoring tool changed with it. Gold rules version 9.0.0 annotate the frame.
Scoring version 4 checks *uses* and *method* as well as the condition. Its scores cannot be compared
with version 3 scores. Against older answer keys, which keep the apparatus in the condition, the
scorer reads the frame back into the condition, so those keys stay usable.

## Where things live

- **Database:** column `frame` (JSON) on `kb.metrics` and `testbed.metrics`, migration
  `ChenWeb/project_migrations/20261018000001_add_metrics_frame.sql`. Rows set aside because they
  only state a strength are kept in `kb.metrics_dropped` with reason `resource_spec`. Their data
  names the row that uses the product (`resource_spec_host`).
- **Extraction:** prompts `prompt-extract-metric-candidates-v29.md`, `prompt-enrich-metrics-v28.md`
  and `prompt-merge-resolve-metrics-v3.md` in `ChenWeb/prompts/` (defaults in code and in
  `mise.local.toml`). In code, `metric_frame.go` holds three safety nets:
  - a fixed table that moves old labels (试验装置, 给药途径, 治疗阶段, …) out of the condition into the
    frame;
  - the strength-row guard;
  - the link from a step to its provision (`provision_id`).
- **Existing rows:** the command `server/cmd/metric-frame-backfill` moves the old labels without an
  LLM. It has a dry run, writes a backup file and can revert from that file.
- **Screens:** the metric detail panel (Metrics workspace, Product Review "Full Details") shows
  Uses, Method and Procedure next to Condition, in English and Chinese.
- **Ontology:** the measurement module has the new terms `mea:resource`, `mea:uses_resource`,
  `mea:resource_role`, `mea:has_spec` and seven role terms. Nothing reads them yet.
- **Benchmark:** `.agents/skills/extract-metrics-benchmark/rules/9.0.0.md` (gold rules) and
  `.agents/skills/score-extract-metrics/` (scoring version 4).

## Known limitations

- Validated live only on hand-built line excerpts of records 364 and 371 plus one synthetic reagent
  clause. Re-extracting full documents (364, 371 and one document of another kind) and scoring
  them is still open.
- Existing rows are not moved until the backfill command is run. Rows moved by it keep their old
  names, so a stored "50％葡萄糖静推剂量" row stays named that way until the record is re-extracted.
- A strength that an old row stored as "药物浓度：…" in its condition stays there when the row names
  no single agent. Only re-extraction fixes it.
- The provision link is set only when exactly one provision covers the metric's lines and the row
  has a step. Few records have provisions yet.
- The frame is not yet turned into ontology assertions, so the resource and method do not take part
  in cross-document comparison.
- The in-app scorer prompt (`prompt-score-extract-metrics-v2`) does not know the frame yet.
