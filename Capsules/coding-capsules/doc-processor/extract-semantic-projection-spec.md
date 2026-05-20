A semantic projection is a a compact, semantically rich representation optimized for retrieval, discoverability, clustering, and semantic matching.

This processor uses a multi-pass extraction strategy.

## Input

- `record_id`: the value of `kb.inputs.id`
- `chunks`

## Implementation

- The code is in `ChenWeb/`
- It may use functions/modules in `shared/`

## Multi-Pass Pipeline

Multi-pass pipeline breaks the processing into multiple passes:

1. Pass 1: extract semantic projection candidates from each chunk.
2. Pass 2: enrich each candidate into final semantic projection rows

### Pass 1: Metric Candidates

Pass 1 uses:

- model env: `EXTRACT_SEMANTIC_PROJECTION_MODEL_NAME`
- prompt env: `EXTRACT_SEMANTIC_PROJECTION_PROMPT`

Optional fallback:

- `EXTRACT_SEMANTIC_PROJECTION_MODEL_FALLBACK`

Pass 1 output:

```json
{
  "semantic_projection": "...",
  "keywords": ["..."]
}
```

### Pass 2: Final Metric Rows

Pass 2 uses:

- model env priority:
  - `ENRICH_SEMANTIC_PROJECTION_MODEL_NAME`
  - `EXTRACT_SEMANTIC_PROJECTION_MODEL_NAME`
- prompt env priority:
  - `ENRICH_SEMANTIC_PROJECTION_PROMPT`
  - `EXTRACT_SEMANTIC_PROJECTION_PROMPT`

Pass 2 output:

```json
{
  "language": "string",
  "metrics": [
    {
      "category_paths": [],
      "category_paths_en": []
    }
  ],
  "uncertain_metrics": []
}
```

Important notes:

- one output row = one metric

### Logging

The processor should log:

- candidate-pass start
- raw parsed LLM payload/error
- enrichment-pass start
- enrichment results
- final results

The shared LLM client should also log the raw HTTP response body before decoding.

### Semantic Projection ID

Semantic projectionsare identified by:

```text
<record_id>_<level>_<seqno>
```

where `<level>` is the chunk level, `<seqno>` is a sequence number within a given level, starts at `1`.

## Workflow

- For each chunk, run Pass 1 to extract its semantic projection.
- Retry extraction with `EXTRACT_SEMANTIC_PROJECTION_MODEL_FALLBACK` when the primary candidate model fails.
- If both primary and fallback candidate extraction return the empty/truncated JSON failure shape, it is an error.
- For each semantic projection, run Pass 2 to enrich it into final semantic projection.
- Save final semantic projection to `kb.semantic_projections`.
- Write `.semantic_projections` artifact output.
- Index semantic projections.
- Upsert status in `kb.inputs.status`.

Failure status entry:

```json
{
  "record_id": "ddd",
  "file_type": "pdf | doc | docx | ppt | pptx | ...",
  "operation": "extract_semantic_projection",
  "proc_status": "failed",
  "input_filename": "Artifacts/0/100/std_20039_opendata.txt",
  "error": "error-msg",
  "start_time": "yyyymmdd hh:mm:ss",
  "ms_used": ddd
}
```

Success status entry:

```json
{
  "record_id": "ddd",
  "file_type": "pdf | doc | docx | ppt | pptx | ...",
  "operation": "extract_semantic_projection",
  "proc_status": "success",
  "input_filename": "Artifacts/0/100/std_20039_opendata.txt",
  "start_time": "yyyymmdd hh:mm:ss",
  "ms_used": ddd
}
```

## Output Storage

### Save to Table `kb.semantic_projections`

Construct a row for each final metric and insert it.

Rules:

- save the JetStream event ID to `event_id`
- if the original language is English, do not generate/store the "_en" fields.
- save additional information to `ext_info`

### Save to File

Write all final semantic projections to:

```text
ARTIFACT_DIR/<group_id>/<record_id>/<filename_root>_<parser_name>.semantic_projections
```

where:

- `<group_id>` = `floor(record_id / 1000)`
- `<filename_root>` is derived from `kb.inputs.staging_filename`
- `<parser_name>` is `kb.inputs.parser_name`

## Index Semantic Projections

### Index Semantic by Category Paths
Refer to [1].

### Full-Text Search Index
Refer to [2] and [3].

### Handler Workflow

- read the record by `record_id`
- compose the chunk input
- load one prompt and one model config
- make one LLM call
- expect the semantic projection for the chunk
- properly handle all errors

### Save Handler Workflow

- read `record_id` and `semantic_projections`
- validate `record_id > 0`
- validate `semantic_projection` is not empty
- create `kb.semantic_projections` table if needed
- insert rows into `kb.semantic_projections`
- set `event_id = rest-api`
- save `ext_info = {"source":"rest-api","schema_version":"2"}`
- leave `model_name`, `prompt_name`, and `metric_keywords_en` empty in the current implementation
- return the number of inserted metrics

## References
[1] KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-categories-spec.md\
[2] KnowledgeStore/Capsules/coding-capsules/full-text-search/metric-search-design.md \
[3] KnowledgeStore/Capsules/coding-capsules/full-text-search/metric-search-impl.md