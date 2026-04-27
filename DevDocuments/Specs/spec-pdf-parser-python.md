# PDF Parser Python Service Spec

## File

`ChenWeb/python/pdf-parser/pdf_parser.py`

## Purpose

This service is the Python parsing tier for `kb.inputs`. It finds unprocessed PDF input records, selects the correct parser backend, generates structured JSON output, updates record status in PostgreSQL, and publishes parsed-result events for downstream processors.

## Scope

The service only processes records whose `kb.inputs.type` is `pdf`.

It supports two execution modes:

1. `poll`
2. `jetstream`

## High-Level Responsibilities

1. Connect to PostgreSQL.
2. Resolve repository, backup, and staging directories from environment.
3. Fetch candidate `kb.inputs` rows that have not been parsed yet.
4. Resolve the input PDF location.
5. Detect duplicates by MD5.
6. Dispatch parsing to the selected backend.
7. Write the parsed JSON result into the record’s repository directory.
8. Update `kb.inputs.status`, `file_name`, `result_filename`, `backup_filename`, and `parser_name`.
9. Publish a parsed event.

## Configuration

### Required

- `PG_HOST`
- `PG_PORT`
- `PG_DB_NAME`
- `PG_USER_NAME`
- `PG_PASSWORD`

### Important optional variables

- `DATA_HOME_DIR`
- `DATA_BACKUP_DIR`
- `DATA_STAGING_DIR`
- `PDF_BACKUP_DIR`
- `PDF_POLL_INTERVAL`
- `PDF_BATCH_SIZE`
- `PDF_DEFAULT_PARSER`
- `PDF_PIPELINE_MODE`
- `NATS_URL`
- `NATS_USER`
- `NATS_PASS`
- `NATS_TOKEN`
- `PDF_STAGE_EVENT_SUBJECT`
- `PDF_PARSED_EVENT_SUBJECT`
- `PDF_STAGE_EVENT_DURABLE`
- `PDF_STAGE_EVENT_STREAM`
- `PDF_PARSED_EVENT_STREAM`

## Directory Model

### Repository root

`_repo_dirs()` currently derives repository roots from `DATA_HOME_DIR` and appends `Artifacts` to each configured base path.

Example:

- `DATA_HOME_DIR=/Users/cding/Apps/SemOS`
- effective repo root:
  `/Users/cding/Apps/SemOS/Artifacts`

### Record directory

For record `id = N`, the parser uses:

`{repo_dir}/Artifacts/{N // 1000}/{N}/`

Note:

The current implementation appends `Artifacts` both in `_repo_dirs()` and again when building `record_dir`, so the effective runtime path shape is driven by the code exactly as written.

### Backup directory

`_backup_dir()` prefers `PDF_BACKUP_DIR`. Otherwise it uses:

`{DATA_BACKUP_DIR}/pdf_files`

## Parser Backends

The service supports these parser names:

- `opendata`
- `paddleocr`
- `mineru`
- `docling`

Backends are cached after first initialization.

If a record has no `parser_name`, the service uses `PDF_DEFAULT_PARSER`, defaulting to `opendata`.

## Input Resolution

`_resolve_input_file()` locates the source PDF in this order:

1. Staging directory via `staging_filename`
2. `kb.inputs.file_name`
3. `kb.inputs.result_filename`
4. Record repository directory candidates
5. Legacy `pdf_parser/{record_id}` directory candidates

It returns:

- `(source_path, True)` when the file is found in staging
- `(source_path, False)` when the file is already in repository storage

## Relative Path Behavior

The service now supports database values stored relative to `DATA_HOME_DIR`.

### Reads

- `file_name` is resolved through `resolve_repo_path()`
- `result_filename` is resolved through `resolve_repo_path()`

### Writes

When parse succeeds, the service stores:

- `kb.inputs.file_name` relative to `DATA_HOME_DIR` when possible
- `kb.inputs.result_filename` relative to `DATA_HOME_DIR` when possible

`backup_filename` is left in its existing backup-path form.

Example:

- stored `file_name`:
  `Artifacts/0/86/std_33830.pdf`
- stored `result_filename`:
  `Artifacts/0/86/std_33830_opendata.json`

## Duplicate Handling

Before parsing, the service checks whether another processed record already has the same MD5.

If a duplicate is found:

1. The record is marked with parsed status `duplicated`
2. The duplicate record id is stored in status
3. Parsing stops for that record

## Parsing Flow

`_process_record()` is the core per-record workflow.

### When source comes from staging

1. Choose a repository directory with `choose_repo_dir()`
2. Build the record directory
3. Copy the PDF into the record directory
4. Copy the PDF into backup storage

### When source is already in repo storage

1. Reuse the existing file path
2. Reuse the record directory from that path
3. Reuse `backup_filename` from the record

### During parsing

1. Write a `parsing` status entry
2. Use throttled progress updates
3. Call `backend.parse(pdf_path, output_dir, on_progress)`

### On success

1. Write a consolidated JSON file:
   `{pdf_stem}_{parser_name}.json`
2. Update `kb.inputs` with parsed success state
3. Update `result_filename`
4. Update `file_name`
5. Update `backup_filename`
6. Update `parser_name`
7. Remove the staging source file if it came from staging

### On failure

1. Replace parsing status with parsed failure state
2. Store the error message
3. Return a failed result payload

## Output JSON Structure

The generated result JSON includes:

- `input_id`
- `source_pdf`
- `generated_at`
- `engine`
- `pages`

## Status Updates

Status entries are managed in `shared.py`.

Important operations:

- `parsing`
- `parsed`

Important helpers:

- `record_parsing()`
- `record_parsed_success()`
- `record_parsed_failure()`
- `record_duplicated()`

## Poll Mode

`run()` is the default runtime mode.

Flow:

1. Connect to PostgreSQL
2. Ensure repo and backup dirs exist
3. Repeatedly call `scan_staging_once()`
4. Fetch candidates using `fetch_candidates()`
5. Process each eligible record
6. Publish one parsed event per processed record
7. Sleep for `PDF_POLL_INTERVAL`

### Error handling in poll mode

- PostgreSQL errors trigger reconnect logic
- other exceptions are logged and the loop continues

## JetStream Mode

`run_jetstream()` is used when `PDF_PIPELINE_MODE=jetstream`.

Flow:

1. Connect to PostgreSQL
2. Connect to NATS JetStream
3. Subscribe to the stage-event subject
4. Fetch one message at a time
5. Validate message fields
6. Load the matching `kb.inputs` record
7. Process it
8. Publish parsed event
9. Ack the message

### JetStream filtering

Stage events are ignored when:

- `record_id` is invalid
- `type` is present and not `pdf`
- `status` is present and not `success`

### Ack/Nak rules

- permanent payload/data errors are acked and dropped
- transient failures are nacked for retry

## Parsed Event Payload

The parsed event includes:

- `record_id`
- `type`
- `status`
- `file_format`
- `result_filename`

## Key Dependencies

- `shared.py`
- `parser_base.py`
- `parser_opendata.py`
- `parser_paddle.py`
- `parser_mineru.py`
- `parser_docling.py`
- `psycopg2`
- optional `nats-py`

## Recent Behavior Notes

This spec reflects the current code including the relative-path persistence change:

1. `file_name` is stored relative to `DATA_HOME_DIR` when possible
2. `result_filename` is stored relative to `DATA_HOME_DIR` when possible
3. runtime readers resolve those relative paths back to absolute filesystem paths

## Verification References

Relevant tests covering the current behavior include:

- `python/pdf-parser/tests/test_pdf_parser.py`
- `python/pdf-parser/tests/test_shared.py`

