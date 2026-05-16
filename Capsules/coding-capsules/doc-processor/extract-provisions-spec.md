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
    "record_id":"ddd",
    "file_type":"pdf | doc | docx | ppt | pptx | ...",
    "operation": "extract_provisions",
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
    "operation": "extract_provisions",
    "proc_status":"success",
    "input_filename": "Artifacts/0/100/std_20039_opendata.txt"
    "start_time":"yyyymmdd hh:mm:ss",
    "ms_used":ddd,
  },
```

The LLM output format is:
```json
{
  "language": "<detected_language>",
  "provisions": [
    {
      "name": "<provision name>",
      "name_en": "<provision name>",
      "type": "mandatory",
      "provision": "<original provision text>",
      "provision_en": "<English translation or same as original if English>",
      "provision_desc": <the description about the provision>,
      "provision_desc_en": <the English translation of provision_desc>,
      "source_line_spans": ["<page>:<line>", "<page>:<line>"],
      "context":"<the context>",
      "context_en":"<the English translation of the context if its input lanuage is not English>",
      "subject":"<the provision's subject>",
      "subject_en":"<the provision's subject>",
      "location_type":"<the location type>",
      "keywords": ["keyword", "keyword"...],
      "keywords_en": ["keyword", "keyword"...],
      "confidence": 0.0,
      "is_explicit": true or false,
      "need_verify": true or false,
      "category_paths": [
        {
          "category_path": [
            {
              "name": "category-name",
              "keywords": ["keyword", "keyword"...],
              "confidence": ddd
            },
            {
              <the next category>
            },
            ...
          ],
          "path_keywords": ["keyword", "keyword"...],
          "path_confidence": ddd
        }
      ]
      "category_path_en": [    // This is the English translation of 'category_path', present only when the input language is not English!
        {
          "category_path": [
            {
              "name": "category-name",
              "keywords": ["keyword", "keyword"...],
              "confidence": ddd
            },
            {
              <the next category>
            },
            ...
          ],
          "path_keywords": ["keyword", "keyword"...],
          "path_confidence": ddd
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
- `prov_name_en`: English translation of prov_name
- `provision`: original provision text
- `provision_en`: English provision text or translation
- `provision_subject`: provision subject
- `provision_subject_en`: English translation of provision_subject
- `prov_desc`: provision description or provision text
- `prov_desc_en`: English translation of prov_desc
- `prov_context`: surrounding context
- `prov_context_en`: English translation of prov_context
- `provision_keywords`: keywords for search
- `provision_keywords_en`: English keywords for search
- `category_paths`: category path payload from the LLM output
- `category_paths_en`: English category path payload (mapped from LLM field `category_path_en`)
- `location_type`: sentence, paragraph, bullet, table_row, table_cell, heading_context, or mixed
- `confidence`: confidence score
- `is_explicit`: whether the provision is explicit in the source
- `need_verify`: whether the provision should be verified by a human
- `status`: provision record status, default `active`
- `create_time`: creation time
- `modify_time`: last modification time
- `public_info`: additional public metadata, including source line spans
- `private_info`: additional private metadata
- `notes`: notes
- `error_msg`: error message, if any

### Output Storage

Upsert one record to `kb.provisions` for each normalized provision. The table storage shape is not identical to the artifact shape: table columns use explicit `provision_*` names for searchable extracted fields, while the artifact keeps the compact `prov_*` output names.

Refer to 'KnowledgeStore/table-schemas/table-kb-provisions.md' for the table schema.

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
    "prov_id": ddd,
    "prov_name": "xxx",
    "prov_name_en": "xxx",
    "provision": "xxx",
    "provision_en": "xxx",
    "provision_subject": "xxx",
    "provision_subject_en": "xxx",
    "prov_desc": "xxx",
    "prov_desc_en": "xxx",
    "prov_context": "xxx",
    "prov_context_en": "xxx",
    "provision_keywords": ["keyword"],
    "provision_keywords_en": ["keyword"],
    "category_paths": [...],
    "category_paths_en": [...],
    "location_type": "xxx",
    "confidence": 0.0,
    "is_explicit": true,
    "need_verify": false,
    "status": "xxx",
    "create_time": "xxx",
    "modify_time": "xxx",
    "public_info": "xxx",
    "private_info": "xxx",
    "notes": "xxx",
    "error_msg": "xxx"
  },
  ...
]
```

## Implementations
Refer to KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-provisions-impl.md