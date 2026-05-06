# Extract Provisions Implementation

Date: 2026-05-05

## Scope

Implemented against:

- `KnowledgeStore/DevDocuments/Specs/spec-doc-processor.md`
- `KnowledgeStore/DevDocuments/Specs/spec-extract-provisions-go.md`
- `ChenWeb/prompts/prompt-extract-provisions.md`

Changed implementation:

- `ChenWeb/server/api/doc-processing/extract-provisions.go`
- `ChenWeb/server/api/doc-processing/extract-provisions_test.go`
- `ChenWeb/server/cmd/doc-processor/main.go`
- `ChenWeb/project_migrations/20260505000001_create_kb_provisions_table.sql`
- `ChenWeb/project_migrations/20260505000002_upgrade_kb_provisions_output_schema.sql`

## Summary

The `extract_provisions` doc processor extracts normative provisions from a parsed document. It uses the block buffer created by the always-run `blocking` processor, calls the configured LLM once per block, normalizes the returned provision records, assigns per-record `prov_id` values, upserts them to `kb.provisions`, writes a `.provisions` artifact file, and writes an `extract_provisions` status entry back to `kb.inputs.status`.

The processor is wired into `server/cmd/doc-processor`, so it can be selected with:

```json
{
  "record_id": "123",
  "operation": ["extract_provisions"],
  "force": true
}
```

To run provisions extraction after chunking in one event, request both processors:

```json
{
  "record_id": "123",
  "operation": ["chunking", "extract_provisions"],
  "force": true
}
```

`operation:"chunking"` alone does not call `extract_provisions`. Topic extraction and summary generation are internal work inside the `chunking` processor; provisions extraction is a separate processor selected by `extract_provisions`, or by omitting the operation filter and allowing the configured default order to run.

## Processor

The processor is implemented as `ProvisionsProcessor`.

Key public construction and interfaces:

- `NewProvisionsProcessor(inputStore, store, extractor, logger)`
- `ProvisionsProcessor.Name()` returns `extract_provisions`
- `ProvisionsProcessor.HandleEvent(ctx, payload)` handles `kb.line-file-generated` events
- `ProvisionsStore` abstracts existence checks, deletion, and persistence
- `ProvisionsSQLStore` stores rows in `kb.provisions`

The processor follows the same broad shape as the existing `MetricsProcessor`, but its input path follows the provisions spec more directly: it processes document blocks instead of chunk artifacts.

## Event Workflow

`HandleEvent` performs the following steps:

1. Parse the event payload with `ParseLineFileGeneratedEvent`.
2. Skip non-PDF or non-success events with `ShouldSkipLineFileGeneratedEvent`.
3. Validate prompt loading, input store, and provisions store.
4. Load the `kb.inputs` record by `record_id`.
5. If model configuration failed, persist a failed `extract_provisions` status and return without crashing the subscriber.
6. If `force=true`, delete existing provisions for the input record.
7. If `force=false`, skip extraction when provisions already exist.
8. Resolve input blocks:
   - Prefer `BlockBufferFromContext(ctx)`, populated by `BlockingProcessor`.
   - Fall back to reading the line file and calling `buildBlocks`.
9. For each block, call the LLM with `EXTRACT_PROVISIONS_PROMPT` and `EXTRACT_PROVISIONS_MODEL_NAME`.
10. Normalize returned provisions.
11. Assign per-record `prov_id` values starting at 1.
12. Upsert provisions into `kb.provisions`.
13. Write `ARTIFACT_DIR/<group_id>/<record_id>/<staging_root>_<parser_name>.provisions`.
14. Persist success or failure status into `kb.inputs.status`.

## Input Handling

Primary input is the in-memory `BlockBuffer` shared through context by the controller:

```text
<flag>\t<line_number>\t<page_number>\t<line_type>\t<content>
```

The `flag` value is:

- `n`: normal line
- `o`: overlap line

The prompt receives both:

- a plain text block-lines section, useful for LLM reading
- a JSON array of the same block lines, useful for stricter parsing

If no block buffer exists in context, the processor resolves the canonical line file through `ResolveInputFilePath`, reads it, and builds blocks using the same `buildBlocks` function as `BlockingProcessor`.

## LLM Configuration

Prompt loading:

- `EXTRACT_PROVISIONS_PROMPT`
- fallback shared key: `PROMPT_FILE_NAME`
- default prompt file: `prompt-extract-provisions.md`

Prompt search order:

1. absolute prompt path, if supplied
2. direct relative path
3. `PROMPT_DIR/<prompt>`
4. `server/cmd/doc-processor/<prompt>`
5. `server/cmd/doc-processor/prompts/<prompt>`
6. `prompts/<prompt>`

Model loading:

- `EXTRACT_PROVISIONS_MODEL_NAME`
- `EXTRACT_PROVISIONS_MODELS_FILE`

The loaded model config is applied to the `LLMJSONExtractor` using the shared `applyStructureModelConfigToExtractor` helper, matching the pattern used by other document processors.

## LLM Output Shape

The processor expects strict JSON:

```json
{
  "language": "en",
  "provisions": [
    {
      "name": "inspection_requirement",
      "type": "mandatory",
      "provision_original": "The operator shall inspect pressure relief valves monthly.",
      "provision_en": "The operator shall inspect pressure relief valves monthly.",
      "source_line_spans": [10],
      "context": "maintenance section",
      "subject": "pressure relief valve inspection",
      "location_type": "sentence",
      "keywords": ["inspection", "pressure relief valve"],
      "confidence": 0.91,
      "is_explicit": true,
      "need_verify": false,
      "categories": []
    }
  ]
}
```

Supported aliases during normalization:

- `name` or `provision_name` -> `provision_name`
- `type` or `provision_type` -> `provision_type`
- `source_text` or `provision_original` -> `source_text`

`source_line_spans` are normalized with page numbers. For example, a line number `10` in a block where line 10 is on page 2 becomes:

```text
2:10
```

## Normalized Provision Fields

Each LLM provision is first normalized internally with:

- `provision_name`
- `provision_type`
- `source_text`
- `source_line_spans`
- `provision_original`
- `provision_en`
- `context`
- `subject`
- `location_type`
- `keywords`
- `confidence`
- `is_explicit`
- `need_verify`
- `categories`

The implementation preserves the raw `categories` payload as JSON-compatible data so richer category structures from the prompt are not flattened away.

Before persistence, the processor converts those internal records to the final output shape required by the spec:

- `prov_id`
- `prov_name`
- `prov_subject`
- `prov_desc`
- `prov_context`
- `prov_keywords`
- `category_paths`
- `location_type`
- `prov_conf`
- `is_explicit`
- `status`
- `create_time`
- `modify_time`
- `public_info`
- `private_info`
- `notes`
- `error_msg`

`public_info` carries supporting details that are useful but not first-class output fields, including:

- `provision_type`
- `source_line_spans`
- `provision_original`
- `provision_en`
- `need_verify`

## Database Storage

The project migration creates `kb.provisions`.

There are two migrations:

- `20260505000001_create_kb_provisions_table.sql`: creates the table with the output schema for new databases.
- `20260505000002_upgrade_kb_provisions_output_schema.sql`: upgrades databases where `kb.provisions` already existed before the final output schema. This is required because `CREATE TABLE IF NOT EXISTS` does not add missing columns such as `prov_id` to an existing table.
- `20260505000003_align_kb_provisions_table_columns.sql`: aligns the table columns with the final storage contract by adding `provision_type`, `source_text`, `source_line_spans`, `provision_original`, `provision_en`, `provision_subject`, `provision_keywords`, `confidence`, and `need_verify`, and by dropping older redundant columns such as `provision_name`, `provision_context`, `categories`, and `prov_conf`.
- `20260505000004_add_kb_provisions_run_metadata.sql`: adds extraction run metadata (`num_blocks`, `num_provisions`, `time_per_provision`, `model_name`, `prompt_name`) and drops the remaining duplicate table columns `prov_subject` and `prov_keywords`.

Main columns:

- `id`
- `input_record_id`
- `extract_id`
- `input_filename`
- `prov_id`
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
- `num_blocks`
- `num_provisions`
- `time_per_provision`
- `model_name`
- `prompt_name`
- `status`
- `create_time`
- `modify_time`
- `public_info`
- `private_info`
- `notes`
- `error_msg`

The table has a unique constraint on `(input_record_id, prov_id)`, which makes reprocessing deterministic and supports upsert.

Indexes:

- `idx_kb_provisions_input_record_id`
- `idx_kb_provisions_extract_id`
- `idx_kb_provisions_status`
- `idx_kb_provisions_keywords_gin`
- `idx_kb_provisions_categories_gin`

`input_record_id` references `kb.inputs(id)` with `ON DELETE CASCADE`.

The artifact file still uses the compact output names such as `prov_subject`, `prov_keywords`, and `prov_conf`. The SQL store maps those values into the table columns `provision_subject`, `provision_keywords`, and `confidence`, and it does not persist duplicate `prov_subject` or `prov_keywords` table columns.

## Artifact File

The processor writes all output provisions to:

```text
ARTIFACT_DIR/<group_id>/<record_id>/<staging_root>_<parser_name>.provisions
```

where `group_id = floor(record_id / 1000)`.

For record `4001`, staging filename `std-4001.pdf`, and parser `opendata`, the artifact path is:

```text
ARTIFACT_DIR/4/4001/std-4001_opendata.provisions
```

The file is a JSON array of the final output records (`prov_id`, `prov_name`, `prov_subject`, etc.).

## Status Updates

The processor upserts an `extract_provisions` entry into `kb.inputs.status`.

Success shape:

```json
{
  "operation": "extract_provisions",
  "proc_status": "success",
  "proc-status": "success",
  "start_time": "20260505 14:25:00",
  "ms-used": 123
}
```

Failure shape:

```json
{
  "operation": "extract_provisions",
  "proc_status": "failed",
  "proc-status": "failed",
  "start_time": "20260505 14:25:00",
  "ms-used": 123,
  "error": "error-message"
}
```

Both `proc_status` and `proc-status` are written for compatibility with existing status conventions.

## Doc Processor Wiring

`server/cmd/doc-processor/main.go` now creates a dedicated LLM client for provisions:

```go
provisionsLLMClient := newLLMClient()
```

The processor list now includes:

```go
docprocessing.NewProvisionsProcessor(
    inputStore,
    docprocessing.ProvisionsSQLStore{DB: ApiTypes.ProjectDBHandle},
    provisionsLLMClient,
    logger,
)
```

Startup logging now includes `extract_provisions` in the configured processor list.

## Tests

Added focused tests:

- `TestProvisionsProcessor_ExtractsFromBlockBufferAndWritesStatus`
  - verifies block-buffer input is sent to the LLM
  - verifies final output provision fields such as `prov_id`, `prov_name`, and `prov_subject`
  - verifies line/page source span normalization
  - verifies the `.provisions` artifact is written
  - verifies `extract_provisions` success status

- `TestProvisionsProcessor_FallsBackToInputFileWhenBlockBufferMissing`
  - verifies line-file fallback builds block input correctly

- `TestLoadProvisionsPromptFromEnv_UsesPromptDir`
  - verifies `EXTRACT_PROVISIONS_PROMPT` and `PROMPT_DIR` lookup

- `TestControlService_ChunkingOperationDoesNotSelectProvisions`
  - verifies `operation:"chunking"` selects only the chunking processor
  - documents that callers must request `extract_provisions` explicitly or omit the operation filter

Verification commands run:

```bash
go test ./server/api/doc-processing -run 'TestProvisions|TestLoadProvisions|TestControlService_ChunkingOperationDoesNotSelectProvisions'
go test ./server/cmd/doc-processor
```

Both passed.

## Known Gaps

The broader `go test ./server/api/doc-processing` command still fails in existing static-analyzer tests unrelated to this implementation:

- `TestStaticAnalyzer_SuccessWritesCorrectedAndStatus`
- `TestStaticAnalyzer_MissingArtifactDirFailsFast`
- `TestStaticAnalyzer_DoesNotLeakTOCToNextPage`

Those failures were observed during verification and were not changed by the provisions implementation.

Potential follow-up work:

- Add an API handler for listing provisions, similar to the existing metrics handler.
- Add UI support under the compliance provisions section.
- Add sqlmock tests for `ProvisionsSQLStore`.
- Decide whether `kb.provisions` should store additional category path fields as first-class columns or continue preserving category payloads in JSONB.
- Consider deduplicating semantically identical provisions across overlapping blocks before insert.
