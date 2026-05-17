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
- The LLM generates zero or more provisions for each block. 
- Provisions are identified by `prov_id`, which is a sequence number, starting at 1.
- If primary extraction fails and the fallback model also returns an empty/truncated JSON response (for example `unexpected end of JSON input` with an effectively empty payload), treat that block as a successful empty extraction rather than a processor failure.
- After processing all blocks, save all the extracted provisions from all the blocks to the table `kb.provisions` (refer to "Output Storage" section).
- Save all extracted provisions to a `.provisions` artifact file (refer to "Output Storage" section).
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
      "category_paths_en": [    // This is the English translation of 'category_path', present only when the input language is not English!
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
    },
    {
      <next provision>
    },...
  ]
}
```

## Index Provisions
Refer to 'KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-categories-spec.md'

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
- Upsert all provisions to 'kb.provisions'
- Save all provisions in 
`ARTIFACT_DIR + /<group_id>/<record_id>/<filename_root>_<parser_name>.provisions`
where:
  - `<group_id>` = floor(record_id / 1000)`
  - `<filename_root>` is the root of 'kb.inputs.staging_filename'
  - `<parser_name> is 'kb.inputs.parser_name'

`provisions.txt` file format:

```text
[
    {
      "prov_id":1,
      "prov_name": "<provision name>",
      "prov_name_en": "<provision name>",
      "prov_type": "mandatory",
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
      "category_paths_en": [    // This is the English translation of 'category_path', present only when the input language is not English!
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
    },
    {
      <next provision>
    },...
]
```

## Implementations
Refer to KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-provisions-impl.md