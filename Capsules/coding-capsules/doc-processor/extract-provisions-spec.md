# Extract Provisions Processor

This is a Doc Processor ('spec-doc-processor.md'). This processor extracts normative provisions
(or 'provisions' for short) from standards, regulatory documents, or similar documents.

A provision includes requirements, obligations, prohibitions, permissions, and
recommendations.

# Input

- record_id: the value of kb.inputs.id, identifies the record to process
- `EXTRACT_PROVISIONS_INPUT` (default `"chunks"`): controls the unit fed to the LLM.
  - `"chunks"` (default): use chunks produced by the Chunking Processor. Each chunk's lines are converted with `markedLinesToJSON`.
  - `"blocks"`: use blocks produced by the Blocking Processor (refer to `spec-blocking.md`). Each block's lines are converted with `blockLinesToJSON`.

# Workflow
- At the start of processing, upsert the following entry to `kb.inputs.status`:
```json
{
  "operation": "extract_provisions",
  "start_time": "yyyymmdd hh:mm:ss",
  "proc_status": "running"
}
```
- Depending on `EXTRACT_PROVISIONS_INPUT`, iterate over chunks (default) or blocks. For each unit, use the EXTRACT_PROVISIONS_MODEL_NAME model with the EXTRACT_PROVISIONS_PROMPT prompt to extract provisions. Units may be processed concurrently up to `EXTRACT_PROVISIONS_MAX_TASKS` at a time (default 1, sequential). Results are collected in unit order regardless of completion order.
  - `"chunks"`: convert lines with `markedLinesToJSON`
  - `"blocks"`: convert lines with `blockLinesToJSON`
- The LLM generates zero or more provisions for each block. 
- Provisions are identified by `prov_id`, using the format `<record_id>_prv_<sequence_number>`. The sequence number starts at 1 within the input record.
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
      "source_line_spans": ["20", "25-29"],
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
    }
  ]
}
```

`source_line_spans` uses canonical line-only spans. Each value MUST be either a
single line number such as `"15"` or an inclusive line range such as `"15-18"`.
Do not include page numbers or use `<page_number>:<line_number>` values such as
`"4:48"`.

## Index Provisions
Refer to 'KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-categories-spec.md'

## Output

### Output Record

For each extracted provision, generate a unique Provision ID (`prov_id`) using the format `<record_id>_prv_<sequence_number>`, where the sequence number starts at 1 within the input record. The `prov_id` is relative to the input record, so uniqueness is:

```text
(input_record_id, prov_id)
```

Normalize each extracted provision to:

- `prov_id`: string in the format `<record_id>_prv_<sequence_number>`
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
      "prov_id":"173_prv_273",
      "prov_name": "<provision name>",
      "prov_name_en": "<provision name>",
      "prov_type": "mandatory",
      "provision": "<original provision text>",
      "provision_en": "<English translation or same as original if English>",
      "provision_desc": <the description about the provision>,
      "provision_desc_en": <the English translation of provision_desc>,
      "source_line_spans": ["497-498"],
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
    },
    ...
]
```

## Implementations
### Search And Artifact Connections

- The shared hybrid-search behavior is configured by `ChenWeb/config.toml` `[artifact_search]`.
- Provision-specific lexical emphasis is configured by `ChenWeb/config.toml` `[provisions_search_weights]`.
- After a successful run, the implementation rebuilds the provision rows in `kb.search_artifacts`, writes the line-overlap `has-provision` connections, and runs the hybrid artifact-connection step using `kb.provisions.search_document` against `kb.search_artifacts`.

Refer to KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-provisions-impl.md
