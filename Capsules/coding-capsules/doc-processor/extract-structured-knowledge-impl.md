# Extract Structured Knowledge — Implementation Notes

## Overview

`extract_structured_knowledge` is a configurable doc processor in `ChenWeb/server/cmd/doc-processor`. It runs after the Chunking Processor and extracts typed knowledge items (entities, concepts, relationships, normative statements, etc.) from each chunk using a two-pass LLM pipeline.

## Source Files

| File | Role |
|---|---|
| `ChenWeb/server/api/doc-processing/extract-structured-knowledge.go` | Processor, SQL store, category tree indexer, status helpers |
| `ChenWeb/server/api/doc-processing/search_indexing.go` | Added `ReindexKnowledgeSearchForRecord`, `buildKnowledgeRegistryRows`, `searchArtifactKnowledge` constant |
| `ChenWeb/server/api/doc-processing/llm_contracts.go` | Added `structuredKnowledgeCandidateContract`, `structuredKnowledgeEnrichContract` |
| `ChenWeb/server/cmd/doc-processor/main.go` | Wired `NewStructuredKnowledgeProcessor` into the pipeline |

## Environment Variables

| Variable | Required | Purpose |
|---|---|---|
| `EXTRACT_STRUCTURED_KNOWLEDGE_PROMPT` | Yes | Path/name of the Pass 1 prompt file |
| `EXTRACT_STRUCTURED_KNOWLEDGE_MODEL_NAME` | Yes | Model ref key for Pass 1 (must exist in `MODEL_DEF_FILE`) |
| `EXTRACT_STRUCTURED_KNOWLEDGE_MODEL_FALLBACK` | No | Fallback model ref key for Pass 1 |
| `ENRICH_STRUCTURED_KNOWLEDGE_PROMPT` | Yes | Path/name of the Pass 2 prompt file |
| `ENRICH_STRUCTURED_KNOWLEDGE_MODEL_NAME` | Yes | Model ref key for Pass 2 |
| `ARTIFACT_DIR` | Yes | Root directory for artifact file output |
| `ARTIFACT_WEB_DIR` | Yes | Root directory for the category tree index |

Default prompt filenames (resolved via `PROMPT_DIR` or standard search paths):
- Pass 1: `prompt-extract-structured-knowledge-v1.md`
- Pass 2: `prompt-enrich-structured-knowledge-v1.md`

## Knowledge Types

Twelve types are extracted, processed in this canonical order (defined in `knowledgeTypeOrder`):

| Type | JSON array key | Primary field |
|---|---|---|
| `entity` | `entities` | `entity` |
| `concept` | `concepts` | `concept` |
| `relationship` | `relationships` | `relation` |
| `normative_statement` | `normative_statements` | `normative_stmt` |
| `quantitative_constraint` | `quantitative_constraints` | `quantitative_constraint` |
| `temporal_constraint` | `temporal_constraints` | `temporal_constraint` |
| `conditional_logic` | `conditional_logic` | `conditiona_logic` |
| `causal_relationship` | `causal_relationships` | `causal_relation` |
| `assumption` | `assumptions` | `assumption` |
| `reference` | `references` | `reference` |
| `procedure` | `procedures` | `procedure` |
| `ambiguity` | `ambiguities` | `ambiguity` |

## Two-Pass Pipeline

### Pass 1 — Candidate Extraction (per chunk)

For each chunk, calls the LLM with the chunk lines (formatted via `buildMarkedChunkInputText`) and expects a JSON object with all twelve type arrays. If the primary model fails, retries with `EXTRACT_STRUCTURED_KNOWLEDGE_MODEL_FALLBACK`. If both fail, **the chunk is logged and skipped** — processing continues with remaining chunks (unlike semantic projections, a per-chunk failure is not a hard error). Chunks that yield an empty payload (all twelve arrays are empty or absent) are also skipped silently.

### Pass 2 — Enrichment (per candidate)

For each Pass 1 result, calls the enrich model with the candidate payload and the original chunk lines. Expects a JSON object containing all twelve type arrays plus their `_en` translations and `category_paths` / `category_paths_en`. Enrichment failure is a hard error and aborts processing for the record.

## Knowledge ID

Each item is assigned a globally-sequential ID across all chunks and types:

```
<record_id>_0_<globalSeqNo>
```

where level is `0` and `globalSeqNo` increments from 1 across all chunks in `knowledgeTypeOrder` order (see `flattenKnowledgeItems`).

## English Language Handling

When the detected language is `en` or `english` (case-insensitive), the `_en` fields (`knowledge_value_en`, `desc_text_en`, `keywords_en`, `category_paths_en`) are not stored — consistent with the convention used by `kb.metrics`, `kb.products`, and `kb.semantic_projections`.

## Database Table — `kb.knowledges`

```sql
CREATE TABLE IF NOT EXISTS kb.knowledges (
    id               BIGSERIAL    PRIMARY KEY,
    event_id         TEXT,
    input_record_id  BIGINT       NOT NULL,
    knowledge_id     TEXT,
    language         TEXT,
    knowledge_type   TEXT,
    knowledge_value  TEXT,
    knowledge_value_en TEXT,
    desc_text        TEXT,
    desc_text_en     TEXT,
    keywords         JSONB,
    keywords_en      JSONB,
    lines            JSONB,
    category_paths   JSONB,
    category_paths_en JSONB,
    model_name       TEXT,
    prompt_name      TEXT,
    search_document  TEXT,
    search_vector    TSVECTOR,
    ext_info         JSONB,
    create_time      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
```

Indexes: `input_record_id`, `knowledge_id`.

The `ext_info` column stores: `language`, `schema_version` (`"1"`), and `chunk_seq_no`.

Created by migration `ChenWeb/project_migrations/20260526000003_create_kb_knowledges_table.sql`.

## Artifact File Output

All final knowledge items are written as a JSON array to:

```
ARTIFACT_DIR/<group_id>/<record_id>/<filename_root>_<parser_name>.knowledges
```

where `group_id = floor(record_id / 1000)` and `filename_root` is derived from `kb.inputs.staging_filename`.

## Category Tree Index

Knowledge items are indexed into the category tree under `ARTIFACT_WEB_DIR` using the same `parseCategoryPathsArray` / `findOrCreateCategorySubdir` mechanism used by other processors. Each leaf directory receives a `knowledges.txt` file.

Unlike other processors that store only IDs, **`knowledges.txt` stores one full JSON object per line**, keyed and de-duplicated by `knowledge_id`. Both the native-language and English category paths are indexed.

On re-processing, `removeKnowledgeTreeRecord` walks the entire tree and strips all lines whose `knowledge_id` has the prefix `<record_id>_` before re-indexing.

## Full-Text Search Registry

After saving, `ReindexKnowledgeSearchForRecord` is called. It queries `kb.knowledges` for the record and upserts `RegistryRow` entries into the search registry with:

- `ArtifactType`: `"knowledge"` (constant `searchArtifactKnowledge`)
- `PrimaryLabel`: `knowledge_value`
- `SecondaryLabel`: `knowledge_type`
- `SearchDocument`: joined `knowledge_type`, `knowledge_value`, `knowledge_value_en`, `desc_text`, `desc_text_en`, flattened `keywords`, `keywords_en`
- `SemanticPayload`: `{knowledge_type, knowledge_value, keywords}`

The `search_artifacts_knowledge` partition is created by migration `ChenWeb/project_migrations/20260526000004_add_search_artifacts_knowledge_partition.sql`.

## Status Entry in `kb.inputs.status`

Operation name: `extract_structured_knowledge`

```json
{
  "record_id": "ddd",
  "file_type": "pdf | docx | ...",
  "operation": "extract_structured_knowledge",
  "proc_status": "success | failed",
  "input_filename": "Artifacts/0/100/file.txt",
  "start_time": "yyyymmdd hh:mm:ss",
  "ms_used": ddd,
  "error": "error message (only on failure)"
}
```

Re-runs replace the existing entry for the same operation rather than appending.

## Logging

| Event | Fields |
|---|---|
| Candidate-pass start | `record_id`, `chunk_idx`, `seq_no`, `num_lines`, `model_name`, `prompt` |
| Raw parsed LLM payload/error | `record_id`, `chunk_idx`, `seq_no`, `error` (on failure) |
| Enrichment-pass start | `record_id`, `chunk_seq_no`, `model_name`, `prompt` |
| Enrichment results | `record_id`, `chunk_seq_no`, `language`, `ms_used` |
| Final results | `record_id`, `total_chunks`, `candidates`, `knowledges`, `language` |

## Pipeline Position

The processor runs after the Chunking Processor (`after 3` in the pipeline table). Registered as position 12 in `main.go` immediately after `extract_semantic_projections`.

To enable it, add `"extract_structured_knowledge"` to `required_processors` in `config.toml`:

```toml
[doc-processing]
required_processors = ["extract_metrics", "extract_provisions", "generate_summaries", "generate_topics", "generate_scene_blocks", "extract_products", "extract_semantic_projections", "extract_structured_knowledge"]
```

## MID Code Range

Error codes `MID_26052601` – `MID_26052699` are reserved for this processor.
