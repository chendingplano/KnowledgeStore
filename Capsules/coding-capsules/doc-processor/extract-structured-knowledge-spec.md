Extract structured knowledge is a doc processor (refer to [1]). It uses a multi-pass extraction strategy.

## Input

- `record_id`: the value of `kb.inputs.id`
- `chunks`: using the fix-size chunking (refer to [5])

## Multi-Pass Pipeline

Multi-pass pipeline breaks the processing into multiple passes:

1. Pass 1: extract structured knowledge candidates from each chunk.
2. Pass 2: enrich each candidate into final structured knowledge rows

### Pass 1: Extract Candidates

Pass 1 uses:

- model env: `EXTRACT_STRUCTURED_KNOWLEDGE_MODEL_NAME`
- prompt env: `EXTRACT_STRUCTURED_KNOWLEDGE_PROMPT`

Optional fallback:

- `EXTRACT_STRUCTURED_KNOWLEDGE_MODEL_FALLBACK`

Pass 1 output:

```json
{
  "entities": [
    {
        "entity":"string",
        "desc":"string",
        "keywords":["string"]
        "lines":[ddd, ddd-ddd]
    }
  ],
  "concepts": [
    {
        "concept":"string",
        "desc":"string",
        "keywords":["string"]
        "lines":[ddd, ddd-ddd]
    }
  ],
  "relationships": [
    {
        "relation":"string",
        "desc":"string",
        "keywords":["string"]
        "lines":[ddd, ddd-ddd]
    }
  ],
  "normative_statements": [
    {
        "normative_stmt":"string",
        "desc":"string",
        "keywords":["string"]
        "lines":[ddd, ddd-ddd]
    }
  ],
  "quantitative_constraints": [
    {
        "quantitative_constraint":"string",
        "desc":"string",
        "keywords":["string"]
        "lines":[ddd, ddd-ddd]
    }
  ],
  "temporal_constraints": [
    {
        "temporal_constraint":"string",
        "desc":"string",
        "keywords":["string"]
        "lines":[ddd, ddd-ddd]
    }
  ],
  "conditional_logic": [
    {
        "conditiona_logic":"string",
        "desc":"string",
        "keywords":["string"]
        "lines":[ddd, ddd-ddd]
    }
  ],
  "causal_relationships": [
    {
        "causal_relation":"string",
        "desc":"string",
        "keywords":["string"]
        "lines":[ddd, ddd-ddd]
    }
  ],
  "assumptions": [
    {
        "assumption":"string",
        "desc":"string",
        "keywords":["string"]
        "lines":[ddd, ddd-ddd]
    }
  ],
  "references": [
    {
        "reference":"string",
        "desc":"string",
        "keywords":["string"]
        "lines":[ddd, ddd-ddd]
    }
  ],
  "procedures": [
    {
        "procedure":"string",
        "desc":"string",
        "keywords":["string"]
        "lines":[ddd, ddd-ddd]
    }
  ],
  "ambiguities": [
    {
        "ambiguity":"string",
        "desc":"string",
        "keywords":["string"]
        "lines":[ddd, ddd-ddd]
    }
  ],
}
```

### Pass 2

Pass 2 uses:

- model env priority:
  - `ENRICH_STRUCTURED_KNOWLEDGE_MODEL_NAME`
- prompt env priority:
  - `ENRICH_STRUCTURED_KNOWLEDGE_PROMPT`

Pass 2 output:

```json
{
  "language": "string",
  "entities": [
    {
        "entity":"string",
        "desc":"string",
        "keywords":["string"]
        "lines":[ddd, ddd-ddd]
    }
  ],
  "entities_en": [...],
  "concepts": [
    {
        "concept":"string",
        "desc":"string",
        "keywords":["string"]
        "lines":[ddd, ddd-ddd]
    }
  ],
  "concepts_en": [...],
  "relationships": [
    {
        "relation":"string",
        "desc":"string",
        "keywords":["string"]
        "lines":[ddd, ddd-ddd]
    }
  ],
  "relationships_en": [...],
  "normative_statements": [
    {
        "normative_stmt":"string",
        "desc":"string",
        "keywords":["string"]
        "lines":[ddd, ddd-ddd]
    }
  ],
  "normative_statements_en": [...],
  "quantitative_constraints": [
    {
        "quantitative_constraint":"string",
        "desc":"string",
        "keywords":["string"]
        "lines":[ddd, ddd-ddd]
    }
  ],
  "quantitative_constraints_en": [...],
  "temporal_constraints": [
    {
        "temporal_constraint":"string",
        "desc":"string",
        "keywords":["string"]
        "lines":[ddd, ddd-ddd]
    }
  ],
  "temporal_constraints_en": [...],
  "conditional_logic": [
    {
        "conditiona_logic":"string",
        "desc":"string",
        "keywords":["string"]
        "lines":[ddd, ddd-ddd]
    }
  ],
  "conditional_logic_en": [...],
  "causal_relationships": [
    {
        "causal_relation":"string",
        "desc":"string",
        "keywords":["string"]
        "lines":[ddd, ddd-ddd]
    }
  ],
  "causal_relationships_en": [...],
  "assumptions": [
    {
        "assumption":"string",
        "desc":"string",
        "keywords":["string"]
        "lines":[ddd, ddd-ddd]
    }
  ],
  "assumptions_en": [...],
  "references": [
    {
        "reference":"string",
        "desc":"string",
        "keywords":["string"]
        "lines":[ddd, ddd-ddd]
    }
  ],
  "references_en": [...],
  "procedures": [
    {
        "procedure":"string",
        "desc":"string",
        "keywords":["string"]
        "lines":[ddd, ddd-ddd]
    }
  ],
  "procedures_en": [...],
  "ambiguities": [
    {
        "ambiguity":"string",
        "desc":"string",
        "keywords":["string"]
        "lines":[ddd, ddd-ddd]
    }
  ],
  "ambiguities_en": [...],
  "category_paths": [
    {
      "category_path": [
        {"name": "string", "keywords": ["string"], "confidence": 0.0},
        {"name": "string", "keywords": ["string"], "confidence": 0.0}
      ],
      "path_keywords": ["string"],
      "path_confidence": 0.0
    }
  ],
  "category_paths_en": [
    {
      "category_path": [
        {"name": "string", "keywords": ["string"], "confidence": 0.0},
        {"name": "string", "keywords": ["string"], "confidence": 0.0}
      ],
      "path_keywords": ["string"],
      "path_confidence": 0.0
    }
  ],
}
```

### Logging

The processor should log:

- candidate-pass start
- raw parsed LLM payload/error
- enrichment-pass start
- enrichment results
- final results

The shared LLM client should also log the raw HTTP response body before decoding.

### Structured Knowledge ID

Structured knowledge is identified by:

```text
<record_id>_knw_<seqno>
```

where `<seqno>` is a global sequence number, starts at `1`.

Assign a structured knowledge ID to each structured knowledge.

## Workflow

- For each chunk, run Pass 1 to extract its structured knowledge.
- Retry extraction with `EXTRACT_STRUCTURED_KNOWLEDGE_MODEL_FALLBACK` when the primary model fails.
- If both primary and fallback extraction return the empty/truncated JSON shape, just log it.
- For each structured knowledge, run Pass 2 to enrich it into final structured knowledge.
- Generate a structured knowledge ID for each structured knowledge and save it as `knowledge_id`
- Add a `create_time` to each structured knowledge.
- Save final structured knowledge to `kb.knowledges`.
- Write `.knowledges` artifact output.
- Index structured knowledge.
- Upsert status in `kb.inputs.status`.

Failure status entry:

```json
{
  "record_id": "ddd",
  "file_type": "pdf | doc | docx | ppt | pptx | ...",
  "operation": "extract_structured_knowledges",
  "proc_status": "failed",
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
  "operation": "extract_structured_knowledges",
  "proc_status": "success",
  "start_time": "yyyymmdd hh:mm:ss",
  "ms_used": ddd
}
```

## Output Storage

### Save to Table `kb.knowledges`

Construct a row for each strctured knowledge and insert it.

Rules:

- save the JetStream event ID to `event_id`
- if the original language is English, do not generate/store the "_en" fields.
- save additional information to `ext_info`

### Save to File

Write all final strctured knowledge in JSON to:

```text
ARTIFACT_DIR/<group_id>/<record_id>/<filename_root>_<parser_name>.knowledges
```

where:

- `<group_id>` = `floor(record_id / 1000)`
- `<filename_root>` is derived from `kb.inputs.staging_filename`
- `<parser_name>` is `kb.inputs.parser_name`

## Index Structured Knowledge

### Index by Category Paths
Refer to [2].

### Full-Text Search Index
Make sure structured knowledge can be full-text searched, similar to [3] and [4].

## Implementations
Refer to [7].

## References
[1] KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md \
[2] KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-categories-spec.md \
[3] KnowledgeStore/Capsules/coding-capsules/full-text-search/metric-search-design.md \
[4] KnowledgeStore/Capsules/coding-capsules/full-text-search/metric-search-impl.md \
[5] KnowledgeStore/Capsules/coding-capsules/chunking/+CAPSULE.md \
[6] KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-structured-knowledge-impl.md \
[7] KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-structured-knowledge-impl.md