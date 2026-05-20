# Generate Scene Blocks — Implementation Notes

## Overview

`generate_scene_blocks` is pipeline step 9 in the doc-processor service. It extracts structured semantic "scene blocks" from document chunks and persists them to `kb.scene_objects`.

**Spec:** `KnowledgeStore/Capsules/coding-capsules/doc-processor/generate-scene-blocks.md`

---

## Files Changed

| File | Description |
|------|-------------|
| `ChenWeb/server/api/doc-processing/generate-scene-blocks-processor.go` | Processor implementation |
| `ChenWeb/project_migrations/20260518000003_create_kb_scene_objects_table.sql` | DB migration |
| `ChenWeb/server/cmd/doc-processor/main.go` | Processor registration |

---

## Architecture

### Processor Position in Pipeline

```
blocking (1) → chunking (3) → generate_scene_blocks (9)
```

`generate_scene_blocks` depends on chunking output ("after 3"). It runs after the blocking processor (always first) and after chunking.

### Chunk Input Strategy

The processor does **not** read the `.chunks` file from disk (which only stores line number ranges). Instead it reconstructs chunks in memory using the same `BuildChunks()` call the chunking processor uses:

1. If `BlockBuffer` is in context (pipeline running together), use `ParseBlockBufferLines(buf)` to get lines.
2. Otherwise, read the input `.txt` file via `ResolveInputFilePath` → `ParseInputLines`.
3. Call `BuildChunks(lines, ChunkOptions{ChunkSize, OverlapPercent})`.

Chunk parameters (`CHUNK_SIZE`, `CHUNK_OVERLAP_PERCENT`) are read from the same env vars as the chunking processor, ensuring consistency.

---

## Environment Variables

| Variable | Purpose | Default |
|----------|---------|---------|
| `EXTRACT_SCENE_BLOCKS_MODEL_NAME` | LLM model reference | — |
| `MODEL_CONFIG_FILE` | Models config file | '.models.toml' |
| `EXTRACT_SCENE_BLOCKS_PROMPT` | Prompt file name | `prompt-generate-scene-blocks.md` |
| `PROMPT_DIR` | Directory for prompt files | — |
| `CHUNK_SIZE` | Lines per chunk (shared with chunking) | `300` |
| `CHUNK_OVERLAP_PERCENT` | Overlap between chunks | `20` |
| `ARTIFACT_DIR` | Root dir for artifact files | — |

Prompt file search order:
1. Absolute path (if `EXTRACT_SCENE_BLOCKS_PROMPT` is absolute)
2. `PROMPT_DIR/<prompt_ref>`
3. `server/cmd/doc-processor/<prompt_ref>`
4. `server/cmd/doc-processor/prompts/<prompt_ref>`
5. `prompts/<prompt_ref>`

The prompt file is already at `ChenWeb/prompts/prompt-generate-scene-blocks.md`.

---

## Multi-Pass LLM Interaction

The processor now mirrors the product-extraction design:

1. Pass 1 extracts lightweight `candidates` per chunk.
2. Deterministic code merges duplicate candidates and removes overlap-only candidates without normal-line support.
3. Pass 2 enriches each merged candidate into one or more final `scene_blocks`.
4. Deterministic final dedup runs before persistence.

### Pass 1

- Prompt: `prompt-extract-scene-candidates-v1.md`
- Env vars:
  - `EXTRACT_SCENE_CANDIDATES_PROMPT`
  - `EXTRACT_SCENE_CANDIDATES_MODEL_NAME`

This pass operates on the marked chunk text and returns a small candidate schema with:

- `scene_key`
- `scene_type_hint`
- `title`
- `summary_hint`
- `evidence_quote`
- `line_spans`
- `confidence`

### Pass 2

- Prompt: `prompt-enrich-scene-blocks-v1.md`
- Env vars:
  - `ENRICH_SCENE_BLOCKS_PROMPT`
  - `ENRICH_SCENE_BLOCKS_MODEL_NAME`

This pass operates on one merged candidate plus its supporting lines and returns the full `scene_blocks` schema for storage.

---

## Scene Block IDs

IDs are assigned as `<record_id>_<seqno>` where `seqno` is a counter that increments across all chunks and all scene blocks within them, starting at 1.

Examples for `record_id = 201`:
```
201_1
201_2
201_3
```

The `object_id` column in `kb.scene_objects` holds these IDs. The `scene_id` column holds the LLM-generated snake_case semantic identifier (e.g. `vaccine_cold_chain_monitoring`).

---

## Database

### Table: `kb.scene_objects`

Key columns:

| Column | Type | Notes |
|--------|------|-------|
| `object_id` | TEXT | `<record_id>_<seqno>`, part of unique constraint |
| `input_record_id` | BIGINT | FK → `kb.inputs(id)` |
| `event_id` | TEXT | JetStream event ID from context |
| `scene_id` | TEXT | LLM-generated stable identifier |
| `scene_type` | TEXT | e.g. workflow, monitoring, compliance |
| `title` | TEXT | Human-readable title |
| `summary` | TEXT | Standalone semantic description |
| `actors` … `source_refs` | JSONB | Structured scene fields |
| `confidence` | DOUBLE PRECISION | LLM confidence score |
| `model_name` | TEXT | Model used |
| `prompt_name` | TEXT | Prompt file used |
| `ext_info` | JSONB | Additional metadata (event_id is also stored here) |

Unique constraint: `(input_record_id, object_id)` — enables upsert.

Indexes: `input_record_id`, `event_id` (partial, where non-empty), `keywords` (GIN).

### Upsert Behaviour

`UpsertSceneObject` uses `ON CONFLICT (input_record_id, object_id) DO UPDATE SET ...`. Running with `force=true` first deletes existing rows for the record before processing.

---

## Artifact File

Path: `ARTIFACT_DIR/<record_id/1000>/<record_id>/<filename_root>_<parser_name>.scene_blocks`

Content: JSON array of all scene block maps (with `object_id` injected).

---

## Status Persistence

On **failure**, upserts to `kb.inputs.status` with `"operation": "generate_scene_blocks"`.  
On **success**, upserts with `"operation": "extract_scene_blocks"`.

Both include the relation-pass `model_name` and `prompt_name` in the status entry.

---

## Key Types

```go
// SceneObjectsStore — persistence interface
type SceneObjectsStore interface {
    SceneObjectsExist(ctx context.Context, inputRecordID int64) (bool, error)
    DeleteSceneObjectsByInputRecordID(ctx context.Context, inputRecordID int64) (int64, error)
    UpsertSceneObject(ctx context.Context, req UpsertSceneObjectRequest) error
}

// UpsertSceneObjectRequest — one scene block record
type UpsertSceneObjectRequest struct {
    InputRecordID int64
    ObjectID      string
    EventID       string
    SceneBlock    map[string]any  // raw LLM output for this block
    ModelName     string
    PromptName    string
    ExtInfo       map[string]any
}
```

`SceneObjectsSQLStore{DB: *sql.DB}` is the production implementation.

---

## Registration in main.go

```go
sceneBlocksLLMClient := newLLMClient()
// ...
docprocessing.NewSceneBlocksProcessor(
    inputStore,
    docprocessing.SceneObjectsSQLStore{DB: ApiTypes.ProjectDBHandle},
    sceneBlocksLLMClient,
    logger,
),
```

The processor can be invoked standalone via:
```json
{ "record_id": "123", "operation": ["chunking", "generate_scene_blocks"], "force": true }
```

Or as part of a full pipeline run (no `operation` field).
