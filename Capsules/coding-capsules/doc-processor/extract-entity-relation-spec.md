# Extract Entity & Relation Processor — Spec

A configurable doc processor that uses an LLM to extract two — and only two — kinds of structured knowledge from chunked input: **entities** and **relations**.

This processor is independent of [`extract_structured_knowledge`](extract-structured-knowledge-spec.md): the two run side by side and write to different tables.

## Inputs

- `record_id`: the value of `kb.inputs.id`
- chunks loaded from `ARTIFACT_DIR/<group_id>/<record_id>/<filename_root>_<parser_name>.chunks` (produced by the [Chunking](../chunking/+CAPSULE.md) processor)
- input line file under `ARTIFACT_DIR` (used to resolve chunk line bodies)

## Environment Variables

| Name | Required | Purpose |
|---|---|---|
| `EXTRACT_ENTITY_RELATION_MODEL_NAME` | yes | Primary LLM model reference |
| `EXTRACT_ENTITY_RELATION_FALLBACK` | optional | Fallback LLM model reference, used if the primary model errors on a chunk |
| `EXTRACT_ENTITY_RELATION_PROMPT` | optional | Prompt file ref. Defaults to `prompt-extract-entity-relation-v1.md` |
| `EXTRACT_ENTITY_RELATION_MAX_TASKS` | optional | Max concurrent chunk-processing goroutines. Default `1` (sequential). |
| `ARTIFACT_DIR` | yes | Root artifact directory where `.chunks`, `.entities`, `.relations` files live |
| `MODEL_DEF_FILE` | yes | Model registry used by the shared model loader |

If `EXTRACT_ENTITY_RELATION_MODEL_NAME` resolves to a model config error, the processor logs the issue, records a `failed` status entry, and returns. The pipeline continues with the remaining processors.

## Single-Pass Per Chunk

For each chunk produced by the Chunking processor, this processor makes **one LLM call** using `EXTRACT_ENTITY_RELATION_PROMPT`. The prompt is responsible for emitting both the extracted items and, when the input language is not English, the corresponding `_en` translations in the same response.

Rationale: keeping extraction in a single call (vs. the multi-pass design used by `extract_metrics` / `extract_structured_knowledge`) is sufficient because we only emit two narrow categories and we do not need category-path expansion. If a chunk's combined extraction+translation exceeds the model's reliable output, the prompt explicitly permits returning empty `_en` fields and a follow-up translation pass MAY be added later without breaking the schema.

## Fallback Model

When a chunk's primary LLM call errors:

1. Log the primary error at `Warn`.
2. If `EXTRACT_ENTITY_RELATION_FALLBACK` is set and loads cleanly, retry the same chunk with the fallback model.
3. If the fallback also errors with an "empty JSON" shape, treat the chunk as having no extractions and continue.
4. If both error in any other way, log at `Error` and skip the chunk.

A chunk being skipped is not a processor-level failure; the processor only fails when:

- the prompt cannot be loaded, or
- the primary model config cannot be loaded, or
- the chunk artifact cannot be read.

## Output Schema

Per-item LLM output is normalized into two row shapes.

### Entity row

| Field | Type | Notes |
|---|---|---|
| `entity_id` | text | `<record_id>_e_<seqno>`; seqno starts at 1 |
| `event_id` | text | JetStream event ID (or `rest-api` for API path) |
| `input_record_id` | bigint | source `kb.inputs.id` |
| `language` | text | detected input language |
| `entity` | text | original-language entity name |
| `entity_en` | text | English translation; empty if input is English |
| `entity_type` | text | e.g. `software_system`, `organization`, `concept`; original language |
| `entity_type_en` | text | English translation; empty if input is English |
| `aliases` | jsonb | array of original-language aliases |
| `aliases_en` | jsonb | array of English-translated aliases; empty if input is English |
| `desc` | text | original-language short description |
| `desc_en` | text | English translation; empty if input is English |
| `keywords` | jsonb | original-language keyword array |
| `keywords_en` | jsonb | English-translated keyword array; empty if input is English |
| `source_line_spans` | jsonb | array of `"ddd"` or `"ddd-ddd"` line spans |
| `confidence` | double | model-reported confidence 0.0–1.0 |
| `chunk_seq_no` | int | chunk this row came from (also stored in `ext_info`) |
| `model_name` | text | model used |
| `prompt_name` | text | prompt ref |
| `search_document` | text | maintained by trigger; concatenation of searchable fields |
| `search_vector` | tsvector | maintained by trigger; `to_tsvector('simple', search_document)` |
| `ext_info` | jsonb | `{"language", "schema_version", "chunk_seq_no"}` |
| `create_time` | timestamptz | row creation time |

### Relation row

| Field | Type | Notes |
|---|---|---|
| `relation_id` | text | `<record_id>_r_<seqno>`; seqno starts at 1 |
| `event_id` | text | as above |
| `input_record_id` | bigint | source `kb.inputs.id` |
| `language` | text | detected input language |
| `subject` | text | original-language subject |
| `subject_en` | text | English translation; empty if input is English |
| `predicate` | text | original-language predicate (lowercase snake_case verb phrase) |
| `predicate_en` | text | English translation; empty if input is English |
| `object` | text | original-language object |
| `object_en` | text | English translation; empty if input is English |
| `desc` | text | optional original-language short description |
| `desc_en` | text | English translation; empty if input is English |
| `keywords` | jsonb | original-language keyword array |
| `keywords_en` | jsonb | English-translated keyword array; empty if input is English |
| `source_line_spans` | jsonb | array of `"ddd"` or `"ddd-ddd"` line spans |
| `confidence` | double | 0.0–1.0 |
| `chunk_seq_no` | int | chunk this row came from (also stored in `ext_info`) |
| `model_name` | text | model used |
| `prompt_name` | text | prompt ref |
| `search_document` | text | maintained by trigger |
| `search_vector` | tsvector | maintained by trigger |
| `ext_info` | jsonb | `{"language", "schema_version", "chunk_seq_no"}` |
| `create_time` | timestamptz | row creation time |

### English-only optimization

When the detected input language is English, the processor MUST NOT populate any `_en` column. The migration accepts `NULL` / empty strings / empty JSON arrays for those columns. This mirrors the same optimization used by `kb.metrics`.

## Tables

Two tables in schema `kb`:

- `kb.entities`
- `kb.relations`

Both tables get a `search_document` `TEXT` column plus a `search_vector` `TSVECTOR` column, populated by triggers, and a `GIN` index on `search_vector`. Pattern is the same as `kb.metrics`. See [Full-Text Search](#full-text-search) below.

## Artifact Files

For each processed record, write two artifact files under the standard artifact directory:

```text
ARTIFACT_DIR/<group_id>/<record_id>/<filename_root>_<parser_name>.entities
ARTIFACT_DIR/<group_id>/<record_id>/<filename_root>_<parser_name>.relations
```

where:

- `<group_id>` = `floor(record_id / 1000)`
- `<filename_root>` is the basename of `kb.inputs.staging_filename` minus extension
- `<parser_name>` is `kb.inputs.parser_name`

File format: pretty-printed JSON array of the same shape as the rows persisted to the table (one array per file). This mirrors `.metrics` from `extract_metrics`.

This processor MUST NOT index into `ARTIFACT_WEB_DIR` (no category-paths tree). Entities and relations have no category paths in their output schema.

## Full-Text Search

A new partition is added to the partitioned table `kb.search_artifacts` for each:

- `kb.search_artifacts_entity` (`artifact_type = 'entity'`)
- `kb.search_artifacts_relation` (`artifact_type = 'relation'`)

with GIN indexes on `search_vector` and a btree index on `input_record_id`, identical to the pattern used by `kb.search_artifacts_metric`.

At the end of every successful processor run, the processor calls:

- `ReindexEntitySearchForRecord(ctx, record_id, logger)`
- `ReindexRelationSearchForRecord(ctx, record_id, logger)`

These read back the persisted rows and rebuild that record's portion of the search registry, deleting any prior rows first.

## Status JSON

At the end of every processor invocation, append (or replace) a status entry on the record:

Success:

```json
{
  "record_id": "ddd",
  "file_type": "pdf | doc | docx | ppt | pptx | ...",
  "operation": "extract_entity_relation",
  "proc_status": "success",
  "input_filename": "Artifacts/0/100/std_20039_opendata.txt",
  "start_time": "yyyymmdd hh:mm:ss",
  "ms_used": ddd
}
```

Failure:

```json
{
  "record_id": "ddd",
  "file_type": "pdf | doc | docx | ppt | pptx | ...",
  "operation": "extract_entity_relation",
  "proc_status": "failed",
  "input_filename": "Artifacts/0/100/std_20039_opendata.txt",
  "error": "error-msg",
  "start_time": "yyyymmdd hh:mm:ss",
  "ms_used": ddd
}
```

The status entry is keyed by `operation = "extract_entity_relation"`. A second invocation for the same record replaces the prior entry rather than appending a duplicate.

## Workflow

1. Receive a JetStream `kb.line-file-generated` event.
2. Skip if `ShouldSkipLineFileGeneratedEvent(evt)` returns true.
3. Load the record from `kb.inputs`. Skip on `ErrNoRows`.
4. Resolve the line file path; on error, persist a failed status and return.
5. If `force = true`, delete any prior `kb.entities` and `kb.relations` rows for this record. Otherwise, if rows already exist, persist a success status and return (idempotent skip).
6. Read and parse the line file.
7. Resolve the chunk artifact file (`.chunks`); on error, persist a failed status and return.
8. For each chunk: build the marked input text, call the LLM with the entity-relation prompt (with fallback model on error), parse the JSON, normalize entities and relations. Chunks may be processed concurrently up to `EXTRACT_ENTITY_RELATION_MAX_TASKS` workers. An LLM error on one chunk skips that chunk without cancelling siblings; only a pipeline-stop signal cancels all in-flight workers. Results are aggregated in original chunk-index order so `entity_id` and `relation_id` assignment remains deterministic.
9. Detect input language from the first non-empty `language` field returned. Default to `"unknown"` if nothing was detected.
10. Assign `entity_id = <record_id>_e_<seqno>` and `relation_id = <record_id>_r_<seqno>` globally across all chunks.
11. Insert entity rows into `kb.entities` and relation rows into `kb.relations`.
12. Write the `.entities` and `.relations` artifact files.
13. Reindex search via `ReindexEntitySearchForRecord` and `ReindexRelationSearchForRecord`.
14. Persist the `extract_entity_relation` status entry on the record.

## Failure Semantics

If any step fails before/during chunk processing in a way that aborts the run (e.g., cannot read input file, cannot read chunks file, insert fails):

- log the error,
- upsert `kb.inputs.status` with `proc_status = "failed"` and a non-empty `error`,
- do not mark the operation successful.

A failing individual chunk's LLM call does not abort the run; the chunk is skipped and the rest of the chunks proceed.

## References

- [Doc Processor Capsule](+CAPSULE.md) — pipeline ordering and dashboard wiring
- [Chunking](../chunking/+CAPSULE.md) — `.chunks` artifact format
- [Extract Metrics Spec](extract-metrics-spec.md) — the storage and search pattern this processor mirrors
- [Implementation Notes](extract-entity-relation-impl.md)
- [Test Plan](extract-entity-relation-test.md)
