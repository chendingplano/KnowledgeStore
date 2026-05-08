# Extract Metrics Implementation

Date: 2026-05-07

## Scope

Implemented against:

- `KnowledgeStore/DevDocuments/Specs/spec-extract-metrics.md`
- `KnowledgeStore/table-schemas/table-kb-metrics.md`

Changed implementation:

- `ChenWeb/server/api/doc-processing/extract-metrics.go`
- `ChenWeb/server/api/doc-processing/control.go`
- `ChenWeb/server/api/doc-processing/extract-metrics_test.go`
- `ChenWeb/server/api/kbhandler/metrics_handler.go`
- `ChenWeb/project_migrations/20260507100000_alter_kb_metrics_schema.sql`
- `ChenWeb/project_migrations/20260507100001_rename_kb_metrics_extract_id_to_event_id.sql`

## Summary

The `extract_metrics` doc processor extracts quantitative metrics from a parsed document. It reads chunk artifact files or a topics artifact produced by the `chunking` processor, calls the configured LLM once per chunk/topics input, normalizes the returned metric records, and persists them to `kb.metrics`. A success or failure status entry is written back to `kb.inputs.status`.

The processor is wired into `server/cmd/doc-processor` and is selected with:

```json
{
  "record_id": "123",
  "operation": ["extract_metrics"],
  "force": true
}
```

To run metrics extraction after chunking in one event, request both processors:

```json
{
  "record_id": "123",
  "operation": ["chunking", "extract_metrics"],
  "force": true
}
```

## Processor

The processor is implemented as `MetricsProcessor`.

Key public construction and interfaces:

- `NewMetricsProcessor(inputStore, store, extractor, logger)`
- `MetricsProcessor.Name()` returns `"extract_metrics"`
- `MetricsProcessor.HandleEvent(ctx, payload)` handles `kb.line-file-generated` events
- `MetricsStore` abstracts existence checks, deletion, and persistence
- `MetricsSQLStore` stores rows in `kb.metrics`

## Event Workflow

`HandleEvent` performs the following steps:

1. Parse the event payload with `ParseLineFileGeneratedEvent`.
2. Skip non-PDF or non-success events with `ShouldSkipLineFileGeneratedEvent`.
3. Validate prompt loading (fail fast if prompt could not be loaded).
4. Load the `kb.inputs` record by `record_id`.
5. If model configuration failed, persist a failed `extract_metrics` status and return without crashing the subscriber.
6. Detect chunk/topics artifacts via `detectChunkingInputs`.
7. Resolve the canonical line file path via `ResolveInputFilePath`.
8. If `force=true`, delete existing metrics for the input record. If `force=false`, skip extraction when metrics already exist.
9. Assemble input lines:
   - If a `.topics` or `topics.txt` file is found, read only the lines referenced in that file.
   - Otherwise, read all regular (non-overlap) lines from each `.chunks` or `chunk_*` file.
10. Call the LLM with the assembled lines.
11. Normalize returned metric records.
12. Save metrics to `kb.metrics` via `SaveMetrics`, passing the JetStream event ID from context.
13. Persist success or failure status into `kb.inputs.status`.

## Input Handling — Chunk and Topics Detection

`detectChunkingInputs` scans `ARTIFACT_DIR/<group_id>/<record_id>/` where `group_id = floor(record_id / 1000)`.

Priority order (first match wins):

| Priority | File pattern | Description |
|----------|-------------|-------------|
| 1 | `*.topics` | Spec-compliant topics artifact |
| 2 | `topics.txt` | Legacy topics artifact |
| 3 | `*.chunks` | Spec-compliant chunk artifact |
| 4 | `chunk_*` | Legacy chunk files |

When a topics file is found, lines are resolved by reading the topics file's line-number ranges and fetching only those lines from the canonical line file. Overlap lines are never included.

When chunk files are found, each file is read and only regular (`r`) lines are used; overlap (`o`) lines are skipped. Chunk files support two formats:

- **Inline format**: lines prefixed with `r ` or `o ` (preferred)
- **Summary format**: `overlap:` / `lines:` directives that reference line numbers in the canonical line file (backward-compatible)

## LLM Configuration

Prompt loading:

- `EXTRACT_METRICS_PROMPT`
- fallback shared key: `PROMPT_FILE_NAME`
- default prompt file: `default_metric_prompt.txt`

Prompt search order:

1. absolute prompt path, if supplied
2. direct relative path
3. `PROMPT_DIR/<prompt>`
4. `server/cmd/doc-processor/<prompt>`
5. `server/cmd/doc-processor/prompts/<prompt>`
6. `python/extract_metrics/prompts/<prompt>`
7. `prompts/<prompt>`

Model loading:

- `EXTRACT_METRICS_MODEL_NAME`
- `EXTRACT_METRICS_MODELS_FILE`

The loaded model config is applied to the `LLMJSONExtractor` using the shared `applyStructureModelConfigToExtractor` helper.

## LLM Output Shape

The LLM is expected to return strict JSON:

```json
{
  "language": "en",
  "metrics": [
    {
      "metric_name": "Latency",
      "metric_name_en": "Latency",
      "source_line_spans": [3, "5:7"],
      "subject": "service latency",
      "subject_en": "service latency",
      "desc": "maximum allowable latency",
      "desc_en": "maximum allowable latency",
      "context": "SLA requirements section",
      "context_en": "SLA requirements section",
      "keywords": ["latency", "SLA"],
      "keywords_en": ["latency", "SLA"],
      "location_type": "sentence",
      "unit": "ms",
      "unit_en": "ms",
      "formula_or_definition": null,
      "threshold_or_target": "<=200",
      "measurement_frequency": null,
      "confidence": 0.95,
      "is_explicit_metric": true,
      "table_name_or_section": "Section 4.2",
      "reasoning_tags": ["threshold"]
    }
  ],
  "uncertain_metrics": []
}
```

`uncertain_metrics` is normalized with the same logic as `metrics` but is logged and not persisted.

## Normalization

`normalizeMetricList` converts each raw LLM item to a fixed internal schema. Key normalization steps:

- All string fields are trimmed.
- `source_line_spans` is normalized to an array of strings in either `"N"` (single line) or `"N:M"` (inclusive range) format, sorted and merged.
- `keywords` and `keywords_en` are converted from `[]any` to `[]string`.
- `confidence` is coerced to `float64`.
- `is_explicit_metric` is coerced to `bool`.

## Output Storage (`kb.metrics`)

### Event ID

The JetStream event ID is threaded from `ControlService.HandleJetStreamEvent` into the processor's `HandleEvent` via Go context using `withEventID` / `eventIDFromContext` helpers in `control.go`. `SaveMetrics` reads the event ID from `SaveMetricsRequest.EventID` and stores it as `event_id` in `kb.metrics`.

If no event ID is present in context (e.g., the processor was called outside the JetStream path via `ControlService.HandleEvent`), `event_id` is stored as NULL.

### English Language Filtering

When `SaveMetrics` determines that `req.Language` is `"en"` or `"english"` (case-insensitive), the following fields are stored as NULL rather than empty strings:

- `metric_name_en`
- `metric_subject_en`
- `metric_desc_en`
- `metric_context_en`
- `metric_keywords_en`
- `metric_unit_en`

This avoids redundant storage when the source document is already in English.

### Additional Information (`ext_info`)

Each row's `ext_info` JSONB column stores:

```json
{
  "language": "<detected language>",
  "schema_version": "2"
}
```

### Table Schema

The `kb.metrics` table is created by `MetricsSQLStore.ensureMetricsTable` for fresh databases, and maintained by goose migrations for existing ones.

| Column | Type | Notes |
|--------|------|-------|
| `id` | BIGSERIAL | Primary key |
| `event_id` | TEXT | JetStream event ID; NULL when not from JetStream path |
| `input_record_id` | BIGINT NOT NULL | References `kb.inputs.id` |
| `metric_name` | TEXT | Original language |
| `metric_name_en` | TEXT | English; NULL when source is English |
| `source_line_spans` | JSONB | Array of `"N"` or `"N:M"` strings |
| `metric_subject` | TEXT | Original language |
| `metric_subject_en` | TEXT | English; NULL when source is English |
| `metric_desc` | TEXT | Original language |
| `metric_desc_en` | TEXT | English; NULL when source is English |
| `metric_context` | TEXT | Original language |
| `metric_context_en` | TEXT | English; NULL when source is English |
| `metric_keywords` | JSONB | Array of strings; original language |
| `metric_keywords_en` | JSONB | Array of strings; NULL when source is English |
| `model_name` | TEXT | |
| `prompt_name` | TEXT | |
| `location_type` | TEXT | `sentence`, `bullet`, `table_row`, etc. |
| `metric_unit` | TEXT | Original language |
| `metric_unit_en` | TEXT | English; NULL when source is English |
| `formula_or_definition` | TEXT | |
| `threshold_or_target` | TEXT | |
| `measurement_frequency` | TEXT | |
| `confidence` | DOUBLE PRECISION | |
| `is_explicit_metric` | BOOLEAN | |
| `table_name_or_section` | TEXT | |
| `reasoning_tags` | JSONB | Array of strings |
| `ext_info` | JSONB | `language`, `schema_version` |
| `created_at` | TIMESTAMPTZ | DEFAULT NOW() |

## Database Migrations

Two migrations cover the `kb.metrics` schema:

- `20260507100000_alter_kb_metrics_schema.sql`: adds columns introduced in the current schema revision (`metric_name_en`, `metric_subject_en`, `metric_desc_en`, `metric_context_en`, `metric_keywords_en`, `model_name`, `prompt_name`, `metric_unit_en`, `table_name_or_section`); drops the obsolete `input_filename` column.

- `20260507100001_rename_kb_metrics_extract_id_to_event_id.sql`: renames `extract_id` to `event_id` and drops the NOT NULL constraint (the column is now optional, NULL when the processor runs outside the JetStream path).

## Context Propagation for Event ID

Two helpers were added to `control.go`:

```go
func withEventID(ctx context.Context, id string) context.Context
func eventIDFromContext(ctx context.Context) string
```

`HandleJetStreamEvent` injects the event ID (generated or retrieved from `kb.events`) into the context before launching the goroutine that runs `handleEvent`:

```go
go func() {
    procErr := s.handleEvent(withEventID(ctx, eventID), payload)
    ...
}()
```

This makes the event ID available to any processor running inside the goroutine without changing the `Processor` interface.

## Status Updates

The processor upserts an `extract_metrics` entry into `kb.inputs.status`.

Success shape:

```json
{
  "operation": "extract_metrics",
  "proc_status": "success",
  "proc-status": "success",
  "start_time": "20260507 10:00:00",
  "ms-used": 1234
}
```

Failure shape:

```json
{
  "operation": "extract_metrics",
  "proc_status": "failed",
  "proc-status": "failed",
  "start_time": "20260507 10:00:00",
  "ms-used": 1234,
  "error": "error-message"
}
```

Both `proc_status` and `proc-status` keys are written for compatibility with existing status conventions.

## API Handler

`ChenWeb/server/api/kbhandler/metrics_handler.go` provides:

```
GET /api/v1/kb/metrics?input_record_id=N
```

Returns all metric rows for the given `input_record_id`, ordered by `id` ASC.

The `metricRecord` response type exposes `event_id` (nullable) instead of the former `extract_id`.

## Tests

Existing tests in `extract-metrics_test.go`:

- `TestReadRegularLinesFromChunk_SkipsOverlap` — verifies overlap lines are excluded from LLM input.
- `TestReadRegularLinesFromChunk_SummaryFormatUsesSourceLineFile` — verifies the summary chunk format resolves lines from the canonical line file.
- `TestMetricsProcessor_ExtractsFromChunkFilesAndWritesStatus` — end-to-end: loads chunks, calls LLM, saves metrics, writes status. Also covers English language extraction (language `"en"`), confirming the processor completes without error.
- `TestMetricsProcessor_DetectChunkingInputs_PrefersSpecArtifacts` — verifies `.topics` / `.chunks` artifacts take priority over legacy `topics.txt` / `chunk_*` files.
- `TestMetricsProcessor_ExtractsFromTopicsFile` — verifies topics-file input path: only lines referenced in the topics file are sent to the LLM; unreferenced lines are excluded.
- `TestLoadMetricsPromptFromEnv_UsesPromptDir` — verifies `EXTRACT_METRICS_PROMPT` + `PROMPT_DIR` lookup.
- `TestParseTopicLineRanges` — unit tests for the `[N-M, K]` line range parser.
