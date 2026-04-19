A metric is a quantitative, measurable item used to evaluate, compare, monitor, verify, or assess something. Metrics are often defined in standards, specifications, requirements, policies, test plans, scorecards, or compliance documents.

## Input

Inputs to this skill are a input file name and a record_id, an integer from the the 'id' field of the table kb.inputs.

**Input File Format**:

Input files contain lines. Each line has five fields:
* line number: an integer
* page number: an integer
* line type: one-word that indicates the type of the line, such as 'title', 'list-item', etc.
* content: the actual content
* coordinate: expressed as an array of numbers

Below is an example:
```text
65 6 list-item 2.0.7 integrated bathroom with shower, sink [90,246.953,505.2,284.484]
```
where:
* line number: 65
* page number: 6
* line type: list-item
* content: 2.0.7 integrated bathroom with shower, sink
* coordinate: [90,246.953,505.2,284.484]

## Metrics
Metrics may appear:

* in normal prose or sentences
* in bullet lists
* in definitions sections
* in tables

Important:

* For each recognized metric, include the textual evidence that it is intended to be measured, calculated, thresholded, monitored, scored, reported, or evaluated.
* Most tables define metrics, but not all tables define metrics. 
* Do not assume every table row is a metric.
* Extract only items that are truly metrics or explicit candidate metrics.
* Be conservative. Precision is more important than recall.
* If uncertain, list the uncertain metrics in a special section to let human users verify.

## What counts as a metric

Treat an item as a metric if the document defines or implies:

1. a measurable quantity, value, ratio, percentage, score, rate, count, duration, threshold, limit, index, or formula
2. something that can be observed, calculated, tested, monitored, or reported
3. a criterion with numeric bounds or target values
4. a named measurement in a table, especially if accompanied by unit, formula, target, threshold, frequency, method, or description of how it is measured

Examples of likely metrics:

* response time
* uptime percentage
* defect density
* mean time to recovery
* packet loss rate
* compliance score
* false positive rate
* number of incidents per month
* accuracy
* precision / recall / F1
* maximum latency <= 200 ms
* CPU utilization %
* audit completion rate

## What does NOT count as a metric

Do NOT extract:

* general concepts, goals, principles, or qualities with no measurable form
* non-quantitative requirements unless they clearly define a measurable evaluation criterion
* ordinary tables that list entities, names, examples, roles, references, sections, or descriptions but not measurements
* raw facts that are not framed as measurable indicators
* units alone
* formulas alone unless they define a metric
* procedures, controls, or methods unless they explicitly define what is being measured

Examples of non-metrics:

* "The system should be user friendly"
* "Security is important"
* a table of roles and responsibilities
* a table of abbreviations
* a list of components
* section numbers or identifiers without measurement meaning

## Special handling for tables

When analyzing tables:

1. First determine whether the table is actually about metrics.
2. A table is more likely to define metrics if columns include names such as:

   * Metric
   * Measure
   * Indicator
   * KPI
   * Threshold
   * Target
   * Unit
   * Formula
   * Frequency
   * Baseline
   * Benchmark
   * Calculation
   * Acceptance Criteria
3. A table is less likely to define metrics if it mainly contains:

   * names
   * IDs
   * categories
   * references
   * descriptions only
   * roles
   * owners
   * notes
4. If only some rows in a table define metrics, extract only those rows.
5. Use surrounding text, captions, headers, and section titles to interpret the table.

## Extraction requirements

For every extracted metric, produce a structured record with the following fields:

* `metric_name`: normalized short name of the metric
* `source_text`: exact text span in form of line numbers or close excerpt that supports extraction
* `location_type`: one of `sentence`, `bullet`, `table_row`, `table_cell`, `heading_context`, `mixed`
* `context`: short explanation of why this item is a metric
* `unit`: unit if present, otherwise null
* `formula_or_definition`: formula or explicit definition if present, otherwise null
* `threshold_or_target`: target / threshold / acceptable limit if present, otherwise null
* `measurement_frequency`: if stated, otherwise null
* `subject`: what is being measured
* `confidence`: number from 0 to 1
* `is_explicit_metric`: true if the document clearly defines it as a metric; false if inferred but still strongly supported
* `table_name_or_section`: table caption, section title, or nearest heading if available
* `reasoning_tags`: short tags such as `named_metric`, `has_unit`, `has_threshold`, `formula_present`, `performance_measure`, `quality_measure`, `compliance_measure`, `inferred_from_table`

## Decision rules

Apply these rules strictly:

* Prefer explicit evidence over inference.
* If an item has a unit, threshold, formula, or target, that strongly supports metric status.
* If the text says "measure", "metric", "indicator", "KPI", "score", "rate", "percentage", "shall be measured", "shall not exceed", "must be at least", or similar, that strongly supports metric status.
* If a table row appears metric-like but lacks measurement meaning, do not extract it.
* Do not hallucinate formulas, units, thresholds, or names.
* Do not merge distinct metrics unless the document clearly treats them as one metric.
* Preserve exact wording in `source_text`.
* Normalize `metric_name` only enough to make it concise and readable.

## Output

### Output Language

The output should use the language derived from its input file.

### Output Schema

It generates the following attributes for each metric:

```text
"metric_name": a short descriptive phrase for the metric
"source_line_spans": the line numbers of the source text, such as [10-12, 15, 20-22]
"subject": must be descriptive and complete, include the context information, used to semantically identify the metric. Don't just say "max speed", say "electric vehicle main motor max speed".
"desc": "...",
"context": a summary of the context in which the metric is defined. This will be embedded for semantic search.
"keywords": keywords are used for search. Include all important keywords.
"location_type": "sentence|bullet|table_row|table_cell|heading_context|mixed",
"unit": "... or null",
"formula_or_definition": "... or null",
"threshold_or_target": "... or null",
"measurement_frequency": "... or null",
"confidence": 0.0,
"is_explicit_metric": true,
"table_name_or_section": "... or null",
"reasoning_tags": ["..."]
```

### Output Storage

It generates an 'ExtractInvokeID', which is "yyyymmdd-hhmmss", used to identify all the metrics this skill generated for the input file.

Save each metric in the table 'kb.metrics'. The table schema include:
- 'id': an auto-incremented integer that uniquely identifies the record
- 'input_record_id': the user-provided 'record_id' that identifies the record in the 'kb.inputs' table.
- 'extract_id': it is the 'ExtractInvokeID'
- 'input_filename'
- 'metric_name'
- 'source_line_spans'
- 'metric_subject'
- 'metric_desc'
- 'metric_context'
- 'metric_keywords'
- 'location_type'
- 'metric_unit'
- 'formula_or_definition'
- 'threshold_or_target'
- 'measurement_frequency'
- 'confidence'
- 'is_explicit_metric'
- 'reasoning_tags'
- 'ext_info': save additional and possibly customized information in a JSON doc
- 'created_at'
- 'modified_at'

## Final instruction

Analyze the entire input carefully. Extract only genuine metrics. Remember:

* metrics may be in prose or tables
* many tables are not metric tables
* some tables contain only a few metric rows
* do not over-extract
