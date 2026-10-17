# Numeric workflow categories incorrectly extracted as metrics

2026-10-17. User's domain-expert ruling: record 364 metrics 1–4 and 79–82 are not true
metrics. Document: 基层医疗卫生机构急重患者判断及转诊技术标准, WS/T 810—2022.

## Source evidence and generalized patterns

Canonical line 129 is Table 3, 患者转诊需求分级. It maps qualitative severity and
resource needs to actions: immediate ambulance referral, immediate referral, referral
as soon as possible, and elective referral/no referral. The final column labels these
categories 1级–4级. The extracted metrics 79–82 mistake those labels for quantitative
values. The conditions are populated but do not turn a category label into a metric.
The numbers rank workflow categories; they state no measured amount or defined
quantitative assessment score. Category names could replace them without losing a
numerical measurement. Exclusion reason: `categorical_label`.

Line 157 selects patients in categories 1–4 for on-site handling. Line 168 selects
category 1 for ambulance contact and categories 2/3 for a choice of referral mode.
Metrics 1–4 turn those applicability references into assertions of a grade or range.
The clauses prescribe actions, without setting or measuring a quantity. Exclusion
reason: `applicability_scope`. Merely adding the grade to a condition is insufficient
when the rest of the clause has no measurable property.

The earlier prompts already excluded some scope numbers and apparatus identities,
but did not explicitly distinguish numbered workflow categories from quantitative
scales. General instructions to extract scores and every filled table cell made the
label column look eligible. No parser or numeric-normalization error was found.

## Prevention

Candidates v27 and enrich v26 add a category-label eligibility gate before the
filled-cell, one-value-per-row and interpretation-band rules. It applies to numbered
workflow, priority, routing and administrative categories, with examples from referral
levels, incident priorities and service tiers. It separately covers clauses using
those labels to select an action. The enrichment drop vocabulary adds
`categorical_label`; the existing code fallback recognizes the same reasoning tag and
soft-drops any tagged row that enrichment emits despite the instruction.

This is a semantic distinction, not a blacklist of 级, grade, class or level. Preserve:

- measurable limits under a class: 2级产品允许误差≤0.1%; 1级患者应在10 min内完成转运;
- model-specific reference quantities: 模型1的电阻150 Ω;
- clinical cutoffs: 呼吸频率≥30次/min, MEWS评分≥5分;
- points assigned on a defined assessment scale: MEWS心率≤40次/min计2分.

The category belongs in a true quantitative assertion's condition. The category
label itself never becomes an additional metric or a synthetic range/count.

Default prompt references and ignored local mise prompt overrides select the new
versions. Older prompts are retained unchanged for reproducibility. A running backend
must restart/reload before using the new prompt selections and code. Semantic judgment
still belongs to the model: the code fallback requires an exclusion tag and does not
claim to detect all untagged category misclassifications.

## Existing-data correction

Archived the eight complete rows as `364_drp_1`–`364_drp_8` in `kb.metrics_dropped`.
The stage is `domain_review`, recording this user's expert ruling, rather than
attributing the decision to a model. The first four use `applicability_scope`, the last
four `categorical_label`; decision metadata retains the original metric ID and reason.
Stored row data includes the enrichment field names expected by the dropped-metrics UI.

Removed the eight live metric rows and their stale search-registry and artifact-object
links. No assertion evidence or resolved metric references pointed at them. Shared
object nodes and historical extraction logs were preserved. Refreshed the `.metrics`
cache. All 136 other live rows are JSON-equivalent to their pre-repair snapshots, with
their IDs preserved, including all 23 scoring-table mappings from the earlier repair.
No metric renumbering or whole-document re-extraction occurred.

Backup, replay-guarded repair script, exact SQL, original cache, removed object/search
links, proposed exclusions and verification audit are under
`/Users/cding/Apps/SemOS/Artifacts/0/364/category-label-repair-20261017/`.
Database log activity `domain_review_numeric_category_labels` records the repair.

## Validation and documentation

The new pipeline regression failed before registering `categorical_label`: eight rows
remained live instead of four. It passes after the fix, with eight auditable exclusions
and four retained quantitative assertions. It covers scope references, category labels,
MEWS points, a clinical threshold, model-specific resistance, and an error limit under
a grade. The full `server/api/doc-processing` test suite also passes.

These are deterministic tests using stub enrichment responses, not a claim that a
fresh live-model extraction has been scored. Current data was verified directly
against the expert ruling and canonical source, with an exact before/after comparison
of every unaffected live row. No historical benchmark run was rewritten.

Updated the extraction specification's eligibility rules and this incident report.
No schema, public API, UI or benchmark-skill change was required. Historical prompt
versions and prior incident reports describe their original state; this report records
the subsequent reduction from 144 to 136 live metrics. Other documents were not audited.
