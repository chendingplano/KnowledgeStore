A metric is a quantitative, measurable item used to evaluate, compare, monitor, verify, or assess something. Metrics are often defined in standards, specifications, requirements, policies, test plans, scorecards, or compliance documents.

## Input

- record_id: the value of kb.inputs.id, identifies the record to process
- blocks: refer to KnowledgeStore/DevDocuments/Specs/spec-blocking.md for information about blocks.
- file name

## Implementation
- The code is in the 'ChenWeb/' repo.
- It may use functions/modules in 'shared/' repo.

## Workflow
- For each block, it uses EXTRACT_METRICS_MODEL_NAME model with EXTRACT_METRICS_PROMPT prompt
  to extract metrics from the block. Do not extract metrics from olverlap lines unless metrics live in both the overlap lines and normal lines.
- After processed all the chunk files, save the extracted metrics to kb.metrics (refer to "Output Storage" section).
- Upsert the following entry to kb.input.status if faled:
```json
  {
    "operation": "extract_metrics",
    "proc_status": "failed",
    "error": "error-message",
    "start_time": "...",
    "ms-used": ...
  },
```

Otherwise, upsert the following element to kb.inputs.status:
```json
  {
    "operation": "extract_metrics",
    "proc_status": "success",
    "start_time": "...",
    "ms-used": ...
  },
```

### Output Schema

The LLM will generate a JSON of the following format:
```json
{
   "metrics": [
   {
      "metric_name": "...",
      "metric_name_en": "...",
      "metric_desc": "...",
      "metric_desc_en": "...",
      "source_text": "...",
      "source_text_en": "...",
      "location_type": "sentence|bullet|table_row|table_cell|heading_context|mixed",
      "metric_context": "...",
      "metric_context_en": "...",
      "metric_keywords": "...",
      "metric_keywords_en": "...",
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
      "metric_subject": "...",
      "metric_subject_en": "...",
      "line_spans":["ddd", "ddd:ddd"],
      "confidence": 0.0,
      "need_verify": true or false, 
      "is_explicit_metric": true,
      "table_name_or_section": "...",
      "reasoning_tags": ["..."]
   },
   {
      <next metric>
   },
   ...
}
```

### Output Storage

Construct a record of 'kb.metrics' for each metric and upsert the record to the table. 
When constructing the record, follow the following rules:
* Save the JetSteram event ID to 'event_id'
* If the original language is English, do not generate the fields 'metric_name_en', 'metric_subject_en', 
  'metric_desc_en', 'metric_context_en', 'metric_keywords_en', and 'metric_unit_en'
* Save additional information to 'ext_info'

## Extract Metric API

Frontend uses this API to extract metrics on selected content for **preview**. The API includes:
- record_id: an integer
- lines: specify the lines in the format: ["ddd", "ddd-ddd", ...]

### Compose Input
The format of the input to the LLM is:
```text
<flag>\t<line_number>\t<page_number>\t<line_type>\t<content>
...
```
where:
- `<flag>` can be 'o' for overlapping lines and 'n' for normal lines. 
- `<line_number>` is the line number
- `<page_number>` is the page number
- `<line_type>` identifies the type of lines, such as 'heading', 'paragraph', 'table', etc.
- `<content>` is the line content

It reads all the lines specified in `lines`, plus five lines before and after `lines` as the overlapping lines.

### Handler Workflow
- Read the record by `record_id`.
- Compose the input
- Use EXTRACT_METRICS_MODEL_NAME model with EXTRACT_METRICS_PROMPT prompt to extract metrics from the composed input.
- Return **all extracted metrics** to the frontend.
- Do **not** save the extracted metrics to `kb.metrics` in this handler.
- Properly handle all errors.

### Extract Metric API Response

The handler returns:

```json
{
  "status": true,
  "metrics": [
    {
      "metric_name": "...",
      "metric_desc": "...",
      "metric_subject": "...",
      "source_line_spans": ["ddd", "ddd:ddd"],
      "location_type": "...",
      "metric_unit": "...",
      "metric_value": "...",
      "value_data_type": "...",
      "value_range_type": "...",
      "value_class": "...",
      "formula_or_definition": "...",
      "threshold_or_target": "...",
      "measurement_frequency": "...",
      "confidence": 0.0,
      "is_explicit_metric": true,
      "table_name_or_section": "...",
      "reasoning_tags": ["..."]
    }
  ]
}
```

The frontend should:

1. Show a loading spinner while the request is running.
2. List all returned metrics.
3. Let the user remove unwanted metrics.
4. Save only the remaining metrics after the user presses **Save**.

## Save Extracted Metrics API

This API persists the reviewed metrics returned by the Extract Metric API.

### Request

```json
{
  "record_id": 123,
  "metrics": [
    {
      "metric_name": "...",
      "metric_desc": "...",
      "metric_subject": "...",
      "source_line_spans": ["ddd", "ddd:ddd"],
      "location_type": "...",
      "metric_unit": "...",
      "metric_value": "...",
      "value_data_type": "...",
      "value_range_type": "...",
      "value_class": "...",
      "formula_or_definition": "...",
      "threshold_or_target": "...",
      "measurement_frequency": "...",
      "confidence": 0.0,
      "is_explicit_metric": true,
      "table_name_or_section": "...",
      "reasoning_tags": ["..."]
    }
  ]
}
```

### Save Handler Workflow

- Read `record_id` and `metrics` from the request.
- Validate that `record_id` is positive and `metrics` is not empty.
- Construct a record of `kb.metrics` for each metric and upsert the record to the table.
- When constructing the record, follow the following rules:
  * Set `event_id` = `rest-api`
  * If the original language is English, do not generate the fields `metric_name_en`, `metric_subject_en`,
    `metric_desc_en`, `metric_context_en`, `metric_keywords_en`, and `metric_unit_en`
  * Save additional information to `ext_info`
- Return the number of inserted metrics.

Properly handle all errors!
