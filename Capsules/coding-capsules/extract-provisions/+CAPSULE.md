# Extract Provisions Processor

This is a Doc Processor ('spec-doc-processor.md'). This processor extracts normative provisions
(or 'provisions' for short) from standards, regulatory documents, or similar documents.

A provision includes requirements, obligations, prohibitions, permissions, and
recommendations.

# Input

- record_id: the value of kb.inputs.id, identifies the record to process
- blocks: refer to 'spec-blocking.md' for blocks.

# Workflow
- For each block, use the EXTRACT_PROVISIONS_MODEL_NAME model with the EXTRACT_PROVISIONS_PROMPT prompt to extract provisions from the block.
- If primary extraction fails and the fallback model also returns an empty/truncated JSON response (for example `unexpected end of JSON input` with an effectively empty payload), treat that block as a successful empty extraction rather than a processor failure.
- After processing all blocks, save the extracted provisions to the table `kb.provisions` (refer to "Output Storage" section).
- Save all extracted provisions to a `.provisions` artifact file (refer to "Output Artifact" section).
- Upsert the following entry to kb.inputs.status if failed:
```json
  {
    "operation": "extract_provisions",
    "proc_status": "failed",
    "error": "error-message",
    "start_time": "...",
    "ms-used": ...
  },
```

Otherwise, upsert the following element to kb.inputs.status:
```json
  {
    "operation": "extract_provisions",
    "proc_status": "success",
    "start_time": "...",
    "ms-used": ...
  },
```

The LLM output format is:
```json
{
  "language": "<detected_language>",
  "provisions": [
    {
      "name": "<provision name>",
      "type": "mandatory",
      "provision_original": "<original provision text>",
      "provision_en": "<English translation or same as original if English>",
      "source_line_spans": ["<page>:<line>", "<page>:<line>"],
      "context":"<the context>",
      "subject":"<the provision's subject>",
      "location_type":"<the location type>",
      "keywords": ["k1", "k2", "k3"],
      "confidence": 0.0,
      "is_explicit": true,
      "need_verify": false,
      "categories": [
        {
          "category_path": [
            {
              "name": "public_health",
              "keywords": ["health management", "disease prevention", "public health"],
              "confidence": 0.95
            },
          ],
          "path_keywords": ["vaccination records", "recipient data", "information system"],
          "path_confidence": 0.92
        }
      ]
    }
  ]
}
```

## Output

### Output Record

For each extracted provision, generate a unique Provision ID (`prov_id`) as a sequence number starting from 1. The `prov_id` is relative to the input record, so uniqueness is:

```text
(input_record_id, prov_id)
```

Normalize each extracted provision to:

- `prov_id`: integer sequence number starting from 1 within the input record
- `prov_name`: normalized provision name
- `prov_subject`: provision subject
- `prov_desc`: provision description or provision text
- `prov_context`: surrounding context
- `prov_keywords`: keywords for search
- `category_paths`: category path payload from the LLM output
- `location_type`: sentence, paragraph, bullet, table_row, table_cell, heading_context, or mixed
- `prov_conf`: confidence score
- `is_explicit`: whether the provision is explicit in the source
- `status`: provision record status, default `active`
- `create_time`: creation time
- `modify_time`: last modification time
- `public_info`: additional public metadata, including source line spans and original/English provision text
- `private_info`: additional private metadata
- `notes`: notes
- `error_msg`: error message, if any

### Output Storage

Upsert one record to `kb.provisions` for each normalized provision. The table storage shape is not identical to the artifact shape: table columns use explicit `provision_*` names for searchable extracted fields, while the artifact keeps the compact `prov_*` output names.

The table schema includes:

- `id`: database auto-increment ID
- `input_record_id`: the source `kb.inputs.id`
- `extract_id`: extraction invocation ID in `yyyymmdd-hhmmss` format
- `input_filename`: source input filename
- `prov_id`: provision sequence number relative to `input_record_id`
- `prov_name`
- `provision_type`
- `source_text`
- `source_line_spans`
- `provision_original`
- `provision_en`
- `provision_subject`
- `prov_desc`
- `prov_context`
- `provision_keywords`
- `category_paths`
- `location_type`
- `confidence`
- `is_explicit`
- `need_verify`
- `num_blocks`: number of blocks processed during provision extraction
- `num_provisions`: number of provisions extracted for the input record
- `time_per_provision`: average extraction time per provision in milliseconds
- `model_name`: provision extraction model name
- `prompt_name`: provision extraction prompt reference
- `status`
- `create_time`
- `modify_time`
- `public_info`
- `private_info`
- `notes`
- `error_msg`

The table MUST have a unique constraint on `(input_record_id, prov_id)` so reprocessing can upsert deterministically.

### Output Artifact

Save all provisions to:

```text
ARTIFACT_DIR/<group_id>/<record_id>/<provision_file_name>
```

where:

- `group_id = floor(record_id / 1000)`
- `<provision_file_name>` is the root of `kb.inputs.staging_filename` + `_` + `kb.inputs.parser_name` + `.provisions`

For example:

```text
ARTIFACT_DIR/4/4001/std-4001_opendata.provisions
```

The file format is a JSON array:

```json
[
  {
    "prov_id":ddd,
    "prov_name":"xxx",
    "prov_subject":"xxx",
    "prov_desc":"xxx",
    "prov_context":"xxx",
    "prov_keywords":"xxx",
    "category_paths":"xxx",
    "location_type":"xxx",
    "prov_conf":"xxx",
    "is_explicit":"xxx",
    "status":"xxx",
    "create_time":"xxx",
    "modify_time":"xxx",
    "public_info":"xxx",
    "private_info":"xxx",
    "notes":"xxx",
    "error_msg":"xxx"
  },
  ...
]
```
