# kb.provisions

This table stores normative provisions extracted from standards, regulatory documents, and similar documents by the `extract_provisions` doc processor.

## Table Schema

| Field Name | Required | Explanation |
|:-----------|:---------|:------------|
| id | mandatory | Database auto-increment ID |
| input_record_id | mandatory | Source `kb.inputs.id` |
| extract_id | mandatory | Extraction invocation ID in `yyyymmdd-hhmmss` format |
| input_filename | mandatory | Source input filename |
| prov_id | mandatory | Provision sequence number starting from 1, unique within `input_record_id` |
| prov_name | optional | Normalized short provision name |
| prov_name_en | optional | English translation of prov_name |
| provision_type | optional | Provision type, such as `mandatory`, `recommended`, or `optional` |
| source_text | optional | Source text reconstructed from `source_line_spans` |
| source_line_spans | mandatory | JSON array of source page/line spans |
| provision | optional | Original provision text |
| provision_en | optional | English provision text or translation |
| provision_subject | optional | Provision subject |
| provision_subject_en | optional | English translation of provision_subject |
| prov_desc | optional | Provision description or provision text |
| prov_desc_en | optional | English translation of prov_desc |
| prov_context | optional | Context in which the provision appears |
| prov_context_en | optional | English translation of prov_context |
| provision_keywords | mandatory | JSON array of provision keywords |
| provision_keywords_en | optional | JSON array of English provision keywords |
| category_paths | mandatory | JSON array containing category path payloads |
| category_paths_en | optional | JSON array containing English category path payloads |
| location_type | optional | Source location type, such as `sentence`, `paragraph`, `bullet`, `table_row`, `table_cell`, `heading_context`, or `mixed` |
| confidence | optional | Confidence score from 0 to 1 |
| is_explicit | optional | Whether the provision is explicit in the source text |
| need_verify | optional | Whether the provision should be verified by a human |
| num_blocks | optional | Number of blocks processed during provision extraction |
| num_provisions | optional | Number of provisions extracted for the input record |
| time_per_provision | optional | Average extraction time per provision in milliseconds |
| model_name | optional | Model used for provision extraction |
| prompt_name | optional | Prompt reference used for provision extraction |
| status | mandatory | Provision record status, default `active` |
| create_time | mandatory | Creation time |
| modify_time | mandatory | Last modification time |
| public_info | mandatory | Additional public JSON metadata, including source line spans and original/English provision text |
| private_info | mandatory | Additional private JSON metadata |
| notes | optional | Notes |
| error_msg | optional | Error message |

## Constraints

- `id` is the primary key.
- `input_record_id` references `kb.inputs(id)` with `ON DELETE CASCADE`.
- `(input_record_id, prov_id)` is unique so reprocessing can upsert deterministically.

## Indexes

- `idx_kb_provisions_input_record_id`
- `idx_kb_provisions_extract_id`
- `idx_kb_provisions_status`
- `idx_kb_provisions_keywords_gin`
- `idx_kb_provisions_categories_gin`

## Removed / Deprecated Columns

The table should not use these older or redundant columns:

- `provision_name`: use `prov_name`
- `provision_context`: use `prov_context`
- `categories`: use `category_paths`
- `prov_conf`: use `confidence`
- `prov_subject`: use `provision_subject`
- `prov_keywords`: use `provision_keywords`
- `provision_original`: use `provision`
