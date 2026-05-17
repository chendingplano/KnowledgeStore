A metric is a quantitative, measurable item used to evaluate, compare, monitor, verify, or assess something. Metrics are often defined in standards, specifications, requirements, policies, test plans, scorecards, or compliance documents.

## Input

- record_id: the value of kb.inputs.id, identifies the record to process
- blocks: refer to KnowledgeStore/DevDocuments/Specs/spec-blocking.md for information about blocks.
- file name

## Implementation
- The code is in the 'ChenWeb/' repo.
- It may use functions/modules in 'shared/' repo.

## LLM Output Format
It uses an LLM to extract metrics. The LLM output format is:
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
      "category_paths": [
         {
            "category_path": [
            {
               "name": "public_health",
               "keywords": ["health management", "disease prevention", "public health"],
               "confidence": 0.95
            },
            {
               "name": "vaccination",
               "keywords": ["vaccination", "immunization", "vaccine administration"],
               "confidence": 0.94
            },
            {
               "name": "record_management",
               "keywords": ["vaccination records", "recipient data", "immunization information system"],
               "confidence": 0.92
            }
            ],
            "path_keywords": ["vaccination records", "recipient data", "information system"],
            "path_confidence": 0.92
         },
         {
            <next category path>
         },
         ...
      ],
      "caetgory_paths_en": [...]
   },
   {
      <next metric>
   },
   ...
}
```

## Metric ID
Metrics are identified by Metric IDs: `<record_id>_<seqno>`, where `<seqno>` is a sequence number,
starting at 1. Examples:
```
201_1
201_2
...
```

Assign a metric ID for each of the metrics generated.

## Workflow
- For each block, it uses EXTRACT_METRICS_MODEL_NAME model with EXTRACT_METRICS_PROMPT prompt
  to extract metrics from the block. Do not extract metrics from olverlap lines unless metrics live in both the overlap lines and normal lines.
- After processed all the blocks, save the extracted metrics to kb.metrics (refer to "Output Storage" section).
- Upsert the following entry to kb.input.status if faled:

```json
{
    "record_id":"ddd",
    "file_type":"pdf | doc | docx | ppt | pptx | ...",
    "operation": "extract_metrics",
    "proc_status":"failed",
    "input_filename": "Artifacts/0/100/std_20039_opendata.txt"
    "error":"error-msg",
    "start_time":"yyyymmdd hh:mm:ss",
    "ms_used":ddd,
}
```

Otherwise, upsert the following element to kb.inputs.status:
```json
{
    "record_id":"ddd",
    "file_type":"pdf | doc | docx | ppt | pptx | ...",
    "operation": "extract_metrics",
    "proc_status":"success",
    "input_filename": "Artifacts/0/100/std_20039_opendata.txt"
    "start_time":"yyyymmdd hh:mm:ss",
    "ms_used":ddd,
}
```

### Index Metrics
Refer to KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-categories-spec.md for information about
indexing metrics.

### Output Storage

#### Save to Table `kb.metrics`
Construct a record of 'kb.metrics' for each metric and upsert the record to the table. 
When constructing the record, follow the following rules:
* Save the JetSteram event ID to 'event_id'
* If the original language is English, do not generate the fields 'metric_name_en', 'metric_subject_en', 
  'metric_desc_en', 'metric_context_en', 'metric_keywords_en', and 'metric_unit_en'
* Save additional information to 'ext_info'

#### Save to File
It saves all the metrics into a '.metrics' file. The file name is: 'ARTIFACT_DIR + /<group_id>/<record_id>/<filename_root>_<parser_name>.metrics',
where:
- '<group_id>' = floor(record_id / 1000)
- '<filename_root>' is the root of 'kb.inputs.staging_filename'
- '<parser_name>' is 'kb.inputs.parser_name'

## Extract Metric API

Frontend uses this API to extract metrics on selected content for **preview**. The API includes:
- record_id: an integer
- lines: specify the lines in the format: ["ddd", "ddd-ddd", ...]

### Compose Input
The input to the LLM is a block as defined in blocking-spec.md. To compose the block from the selected `lines`:
- Treat the lines specified in `lines` as normal lines (`n`).
- Treat the five lines immediately before and after `lines` as overlap lines (`o`).
- Apply the blocking process (see blocking-spec.md) to convert the raw lines into block format, i.e., remove the `<font>`, `<font-size>`, and `<coordinate>` fields and prepend the `<flag>` field.

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
