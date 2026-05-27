# Extract Semantic Projections — Implementation

## Overview

`extract_semantic_projections` is a configurable doc processor in `ChenWeb/server/cmd/doc-processor`. It runs after the Blocking Processor and extracts one compact, semantically rich projection per input block using a two-pass LLM pipeline.

## Source Files

| File | Role |
|---|---|
| `ChenWeb/server/api/doc-processing/extract-semantic-projections.go` | Processor, SQL store, tree indexer, status helpers |
| `ChenWeb/server/api/doc-processing/extract_semantic_projections_test.go` | Unit tests |
| `ChenWeb/server/api/doc-processing/search_indexing.go` | Added `ReindexSemanticProjectionSearchForRecord`, `buildSemanticProjectionRegistryRows`, `searchArtifactSemanticProjection` constant |
| `ChenWeb/server/api/doc-processing/llm_contracts.go` | Added `semanticProjectionExtractionContract` |
| `ChenWeb/server/cmd/doc-processor/main.go` | Wired `NewSemanticProjectionsProcessor` into the pipeline |

## Environment Variables

| Variable | Required | Purpose |
|---|---|---|
| `EXTRACT_SEMANTIC_PROJECTION_PROMPT` | Yes | Path/name of the Pass 1 prompt file |
| `EXTRACT_SEMANTIC_PROJECTION_MODEL_NAME` | Yes | Model ref key for Pass 1 (must exist in `MODEL_DEF_FILE`) |
| `EXTRACT_SEMANTIC_PROJECTION_MODEL_FALLBACK` | No | Fallback model ref key for Pass 1 |
| `ENRICH_SEMANTIC_PROJECTION_PROMPT` | Yes | Path/name of the Pass 2 prompt file |
| `ENRICH_SEMANTIC_PROJECTION_MODEL_NAME` | Yes | Model ref key for Pass 2 |
| `ARTIFACT_DIR` | Yes | Root directory for artifact file output |
| `ARTIFACT_WEB_DIR` | Yes | Root directory for the category tree index |

Default prompt filenames (resolved via `PROMPT_DIR` or standard search paths):
- Pass 1: `prompt-extract-semantic-projection-v1.md`
- Pass 2: `prompt-enrich-semantic-projection-v1.md`

## Two-Pass Pipeline

### Pass 1 — Candidate Extraction (per chunk)

For each chunk produced by the Chunking Processor, the processor calls the LLM with the chunk lines (formatted via `buildMarkedChunkInputText`) and expects:

```json
{
  "semantic_projection": "compact semantically rich summary of this chunk",
  "keywords": ["keyword1", "keyword2"]
}
```

If the primary model fails, it retries with `EXTRACT_SEMANTIC_PROJECTION_MODEL_FALLBACK`. If both fail, it is an error and processing stops.

Chunks that return an empty `semantic_projection` are skipped silently.

### Pass 2 — Enrichment (per candidate)

For each Pass 1 result, the processor calls the enrich model with the candidate's `semantic_projection`, `keywords`, and the original chunk lines. It expects:

```json
{
  "language": "string",
  "descriptive_name": "string",
  "descriptive_name_en": "string",
  "keywords": ["string"],
  "keywords_en": ["string"],
  "category_paths": [...],
  "category_paths_en": [...]
}
```

## Semantic Projection ID

Each projection is assigned an ID:

```
<record_id>_0_<seqno>
```

where level is `0` (chunk-level, matching the leaf level convention from the chunking system) and `seqno` is the chunk's own `SeqNo` (1-based, assigned by the Chunking Processor).

## Database Table — `kb.semantic_projections`

```sql
CREATE TABLE IF NOT EXISTS kb.semantic_projections (
    id               BIGSERIAL PRIMARY KEY,
    event_id         TEXT,
    input_record_id  BIGINT NOT NULL,
    semantic_proj_id TEXT,
    language         TEXT,
    descriptive_name     TEXT,
    descriptive_name_en  TEXT,
    keywords         JSONB,
    keywords_en      JSONB,
    category_paths   JSONB,
    category_paths_en JSONB,
    model_name       TEXT,
    prompt_name      TEXT,
    search_document  TEXT,
    search_vector    TSVECTOR,
    ext_info         JSONB,
    create_time      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

The table is created on first use (inside `ensureSemanticProjectionsTable`). The `search_document` and `search_vector` columns are reserved for future FTS trigger support.

### English Language Handling

When the detected language is `en` or `english` (case-insensitive), the `_en` fields (`descriptive_name_en`, `keywords_en`, `category_paths_en`) are not stored — matching the same convention used by `kb.metrics` and `kb.products`.

## Artifact File Output

All final projections are written as a JSON array to:

```
ARTIFACT_DIR/<group_id>/<record_id>/<filename_root>_<parser_name>.semantic_projections
```

where `group_id = floor(record_id / 1000)` and `filename_root` is derived from `kb.inputs.staging_filename`.

## Category Tree Index

Projections are indexed into the category tree under `ARTIFACT_WEB_DIR` using the same `parseCategoryPathsArray` / `findOrCreateCategorySubdir` mechanism used by metrics and products. Each leaf directory receives a `semantic_projections.txt` file containing sorted `semantic_proj_id` values. Both the native-language and English category paths are indexed.

On re-processing, `removeSemanticProjectionTreeRecord` strips all prior entries for the record before re-indexing.

## Full-Text Search Registry

After saving, `ReindexSemanticProjectionSearchForRecord` is called. It queries `kb.semantic_projections` for the record and upserts `RegistryRow` entries into the search registry with:

- `ArtifactType`: `"semantic_projection"`
- `PrimaryLabel`: `descriptive_name`
- `SecondaryLabel`: `language`
- `SearchDocument`: joined `descriptive_name`, `descriptive_name_en`, flattened `keywords`, `keywords_en`
- `SemanticPayload`: `{language, descriptive_name, keywords}`

## Status Entry in `kb.inputs.status`

Operation name: `extract_semantic_projections`

```json
{
  "record_id": "ddd",
  "file_type": "pdf | docx | ...",
  "operation": "extract_semantic_projections",
  "proc_status": "success | failed",
  "input_filename": "Artifacts/0/100/file.txt",
  "start_time": "yyyymmdd hh:mm:ss",
  "ms_used": ddd,
  "error": "error message (only on failure)"
}
```

Re-runs replace the existing entry for the same operation rather than appending.

## Logging

The processor emits structured log entries at each stage:

| Event | Fields |
|---|---|
| Candidate-pass start | `record_id`, `chunk_idx`, `seq_no`, `num_lines`, `model_name`, `prompt` |
| Raw candidate LLM payload | `record_id`, `chunk_idx`, `seq_no`, `semantic_projection_len`, `keywords_count` |
| Enrichment-pass start | `record_id`, `seq_no`, `model_name`, `prompt` |
| Enrichment results | `record_id`, `seq_no`, `language`, `descriptive_name` |
| Final results | `record_id`, `total_chunks`, `candidates`, `projections`, `language` |

## Pipeline Position

The processor runs after the Chunking Processor (`after 3` in the pipeline table). In `main.go` it is registered immediately after `extract_doc_metadata` and before `extract_metrics`.

To enable it, add `"extract_semantic_projections"` to `required_processors` in `config.toml`:

```toml
[doc-processing]
required_processors = ["extract_metrics", "extract_provisions", "generate_summaries", "generate_topics", "generate_scene_blocks", "extract_semantic_projections"]
```

## MID Code Range

Error codes `MID_26052101` – `MID_26052199` are reserved for this processor.
