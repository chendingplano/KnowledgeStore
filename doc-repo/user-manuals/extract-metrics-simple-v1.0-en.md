# Extract Metrics Simple

| Field | Value |
|---|---|
| title | Extract Metrics Simple |
| language | en |
| format | markdown |
| version | 1.0 |
| status | Draft |
| author | Not specified |
| owner | Not specified |
| audience | Document-processing users, reviewers, and administrators |
| create-time | 2026-11-13T06:51:53-06:00 |
| last-modify-time | 2026-11-13T06:51:53-06:00 |
| keywords | extract_metrics_simple, metric extraction, document processing, benchmarks, quantitative requirements, cost, review |

## What it does

`extract_metrics_simple` finds measurable values in a document and stores 
them as metrics for review and further document processing. It is a simplified 
version of `extract_metrics`, aiming at reducing the cost of the extraction
without sacrificing much quality.

A metric describes a measurable property, its value, and any stated conditions. For example, “total arsenic must be no more than 15 mg/kg” describes a property, an upper limit, and a unit. Conditions such as a test environment or method can change how a value should be interpreted, so check them against the source document.

Refer to the `Doc processing pipeline configuration` for how to configure this processor.

**Note** If you select `extract_metrics_simple`, do not select `extract_metrics`. These
two should be mutually exclusive.

## Choosing an extractor

| | `extract_metrics_simple` | `extract_metrics` |
|---|---|---|
| Approach | Normally one model call per document chunk; a failed call is retried once as two halves. | Uses candidate extraction and enrichment passes, with additional review calls in some cases. |
| Purpose | Reduce cost while accepting a possible loss of quality. | Use the multi-pass extraction approach. |
| Results | Writes to the document's metric results and shares processing after model calls with the other extractor. | Writes to the same metric results and shares processing after model calls with the simple extractor. |

Do not select both processors for the same run: the system refuses the combination because both write the document's metrics. Compare their results in separate runs. Lower cost does not establish that the simpler method is accurate enough; use benchmark scores and review the source evidence before deciding.

## What to expect in the results

A saved metric can include the property name, subject, value, unit, conditions, and references to the source lines or table rows. The processor uses the cited text to provide context and identifies a nearby heading or table caption where available. It also applies shared processing to handle duplicate results and organize conditions, resources, and methods.

Some fields are less complete than in `extract_metrics`: the simple processor supplies English translations for the name, subject, and condition, but not for every field. Description, English context, and measurement frequency are left empty. The device role and procedure step available to the other extractor are not captured in the same way. Its confidence value is assigned as 0.8 by the software, so do not interpret it as a measured probability that a particular result is correct.

A quantity whose value is left open is set aside rather than saved as a metric. For example, “the equipment must state its energy consumption” names a measurable quantity but gives no value. Items can also be set aside for other reasons, including an invalid result. Set-aside items are recorded in `kb.metrics_dropped`; they are not part of the saved metric list. The set-aside list is not necessarily a complete inventory of everything excluded.

Some combined values cannot be classified automatically. These remain marked `unresolved` with the tag `value_review_unresolved`; check the original text to understand them. Extraction can also miss conditions or include values outside the benchmark's intended scope, so check the value, unit, subject, conditions, and source evidence when reviewing results.

## Using the processor

An administrator must make `extract_metrics_simple` selectable by listing it in `config.local.toml` under `[doc-processing].required_processors`. It is not added to `default_processors`. Select it for the document-processing run without selecting `extract_metrics` in the same run. The specification does not describe the exact screen controls for starting a run; ask your administrator how selection is exposed in your installation.

After processing, review the document's metrics and their source references. Processing also produces a `.metrics` file and uses the shared downstream steps for links, objects, and indexing. Run logs and statuses identify the processor as `extract_metrics_simple`.

## Compare quality and cost

Use a document with a metric benchmark (a reviewed reference set) to compare the two methods:

1. Run one extractor on the document with `force_clear`, then score the results using the in-app Benchmark page or `score_io.py`. Record the score and run identifier before continuing.
2. Run the other extractor on the same document with `force_clear`, then score and record its results separately. Both scoring methods evaluate the metrics currently stored for the document.
3. Compare the scores, inspect differences against the source, and compare model usage costs by run identifier and call reason. `kb.metrics.prompt_name` identifies which processor wrote the stored rows.

`force_clear` changes the stored results, so retain the first run's score before running the second. For caching comparisons, inspect a second run: the specification notes that the first run after a prompt change measures about zero cache hits. Actual cost and quality depend on the document, model, pricing, and configuration.

In a November 1, 2026 trial on one document, the simple processor's model calls cost approximately ¥0.035, and the 30 extracted rows covered the values and units in 27 rows from an earlier `extract_metrics` run. Three extra rows appeared, one outside the cited benchmark scope, and two conditions present in the earlier results were missing. The trial had not yet been scored against the gold benchmark; it is an illustration, not a quality or cost guarantee.

## Configuration reference

For administrators, the prompt is selected by `EXTRACT_METRICS_SIMPLE_PROMPT`; if unset, it defaults to `prompt-extract-metric-simple-v1.md`. The model is selected by `EXTRACT_METRICS_SIMPLE_MODEL_NAME`, falling back to `ENRICH_METRICS_MODEL_NAME` and then `EXTRACT_METRICS_MODEL_NAME`. `EXTRACT_METRICS_MAX_TASKS` controls concurrency on the sequential path; coordinator limits apply otherwise. The prompt setting is placed in `ChenWeb/mise.local.toml` under `[env]` so a deployment build embeds it in the document-processor binary.

For a cold DeepSeek prompt prefix, the first call runs alone while the processor waits for the prefix to become reusable. This can add about a minute before the other calls begin; a warm prefix can avoid that wait. The specification's caching and cost observations are specific to the described setup.

## Source

This manual is based on the [extract_metrics_simple specification](../../Capsules/coding-capsules/doc-processor/extract-metrics-simple-spec.md), including its November 1, 2026 status and measurements.

## Change Log

| Version | Timestamp | Author or responsible party | Reason | Summary |
|---|---|---|---|---|
| 1.0 | 2026-11-13T06:51:53-06:00 | Not specified | Initial manual | Described the processor, results, limitations, selection, and comparison workflow. |
