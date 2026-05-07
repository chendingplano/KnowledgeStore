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
      "formula_or_definition": "...",
      "threshold_or_target": "...",
      "measurement_frequency": "...",
      "metric_subject": "...",
      "metric_subject_en": "...",
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

It generates an 'ExtractInvokeID', which is "yyyymmdd-hhmmss", used to identify all the metrics this skill generated for the input file.

Save each metric in the table 'kb.metrics' (refer to KnowledgeStore/table-schemas/table-kb-metrics.md).