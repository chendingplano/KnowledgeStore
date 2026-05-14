# Generate Topics — Implementation

## Overview

The `generate_topics` processor extracts semantic topics from a document's line content, writes them to a `.topics` file, embeds each topic, and indexes them into a hierarchical category tree. It is processor #8 in the pipeline and is individually invokable via `operation = "generate_topics"`.

It depends on the `chunking` processor (#3): when run standalone the chunk files produced by a prior chunking run must already exist on disk. It is implemented as `GenerateTopicsProcessor` (see [Wiring](#wiring-generatetopicsprocessor) below), separate from `ChunkingProcessor`.

The extraction logic lives in `SemanticChunkingService` (shared with the chunking processor). The status written to `kb.inputs.status` uses `operation = "generate_topics"`.

---

## File Map

| File | Role |
|------|------|
| `ChenWeb/server/api/doc-processing/semantic-chunking.go` | `SemanticChunkingService`: entry points, page-block building, per-block LLM extraction, category tree write, status persistence |
| `ChenWeb/server/api/doc-processing/topic_chunking_shared.go` | Pure helpers: `writeTopicsFile`, `extractTopicsFromLinesWithLLM`, `indexTopicsInTreeDir`, `findOrCreateCategorySubdir`, `upsertTopicToLeafDir`, `writeTopicCategoryMetadata`, cosine similarity, float embed I/O |
| `ChenWeb/server/api/doc-processing/chunking-processor.go` | `ChunkingProcessor`: bridges `ControlService` → `SemanticChunkingService.HandleInput` / `HandleBlockInput` |
| `ChenWeb/server/cmd/doc-processor/main.go` | Wiring: constructs `SemanticChunkingService`, wraps it in `ChunkingProcessor`, registers with `ControlService` |

---

## Key Types

```go
// TopicItem — one extracted topic
type TopicItem struct {
    SeqNo              int
    TopicType          string
    Lines              []string            // line-range strings, e.g. "38-45", "47"
    Keywords           []string
    Topic              string
    CategoryPath       []string            // flat path used for directory traversal
    CategoryPathDetail []CategoryPathEntry // full LLM-returned path detail
}

// CategoryPathEntry — one category path with per-node detail
type CategoryPathEntry struct {
    PathKeywords   []string
    PathConfidence float64
    Nodes          []CategoryPathNode // ordered from root to leaf
}

// CategoryPathNode — one segment in a category path
type CategoryPathNode struct {
    Name       string
    Keywords   []string
    Confidence float64
}
```

---

## Environment Variables

| Variable | Used by | Purpose |
|----------|---------|---------|
| `EXTRACT_TOPIC_MODEL_NAME` | `SemanticChunkingService` | LLM model for topic extraction |
| `EXTRACT_TOPIC_PROMPT` | `SemanticChunkingService` | Prompt text or path for topic extraction |
| `FILE_BLOCK_SIZE` | `SemanticChunkingService` | Pages per block (default 3) |
| `ARTIFACT_DIR` | `SemanticChunkingService` | Root directory for all output files |
| `TOPIC_EMBEDDING_MODEL_NAME` | `indexTopicsInTreeDir` | Model for embedding category nodes |
| `TOPIC_TREE_ROOT_DIR` | `writeTopicsCategoryTree` | Root of the category tree on disk |
| `CATEGORY_SIMILARITY_MIN_SCORE` | `findOrCreateCategorySubdir` | Cosine threshold for matching existing category dirs (default 0.85) |

---

## Step-by-Step Flow

### 1. Entry Point

`ChunkingProcessor.HandleEvent` (in `chunking-processor.go`) parses the JetStream payload, loads the `kb.inputs` record, and calls one of two entry points:

- **`SemanticChunkingService.HandleBlockInput`** — used when the `BlockingProcessor` ran in the same goroutine and placed its output in the context's `BlockBuffer`. Calls `ParseBlockBufferLines(buf)` to get `[]Line`.
- **`SemanticChunkingService.HandleInput`** — falls back to reading the input file from disk and calls `ParseSemanticInputLines(fileBody)`.

Both paths resolve to `handleSemanticLines(ctx, rec, inputFilename, start, lines)`.

### 2. Build Page Blocks

```go
blocks := BuildSemanticPageBlocks(lines, s.FileBlockSize)
```

`BuildSemanticPageBlocks` groups lines by page number. For each block of `FILE_BLOCK_SIZE` content pages, one leading overlap page (the last page of the previous block) is prepended. This ensures context continuity at block boundaries.

For a 3-page block size on a 10-page document, blocks cover pages `[1-3]`, `[1, 4-6]` (page 1 is overlap), `[4, 7-9]`, etc.

### 3. Extract Topics per Page Block (LLM Call)

For each `SemanticPageBlock`, `extractTopicsForBlock` is called, which delegates to `extractTopicsFromLinesWithLLM` in `topic_chunking_shared.go`.

Note: the input unit here is a **page block** (a slice of `Line` values spanning `FILE_BLOCK_SIZE` pages), not a chunk file produced by the chunking processor. The `SemanticChunkingService` never reads chunk files; it partitions the raw line slice by page number before calling the LLM.

```go
parsed, err := extractor.ExtractJSON(ctx, llmclients.JSONExtractionInput{
    PromptText: promptText,
    ModelName:  modelName,
    InputText:  strings.Join(linesText, "\n"),
})
```

The LLM receives the raw line text (without metadata fields) and returns a JSON object with a `"topics"` array. Each element is parsed into a `TopicItem`:

- `topic_id` → `SeqNo` (overridden with a global sequence counter, not the LLM value)
- `topic_type` → `TopicType` (lowercased; defaults to `"general"` if empty)
- `lines` or `line_ranges` → `Lines`
- `topic_keywords` or `keywords` → `Keywords`
- `topic` → `Topic` (sanitized: tabs and newlines replaced with spaces)
- `categories[].category_path` → `CategoryPathDetail`; the first path's node names → `CategoryPath`

Topics with an empty `topic` field are dropped.

#### Category Path Normalization

After parsing, `normalizeAndValidateTopicCategoryPath` validates the flat `CategoryPath`:

- Rejects paths with no segments, segments that are pure numbers, or segments whose names are stop words.
- When the path is invalid or empty, a fallback path is derived from `TopicType` (`keywordCategoryPath` or `fallbackCategoryPath`).
- Each segment is lowercased, trimmed, and truncated to `maxCategoryNameLen` (64) characters; the path is capped to `maxCategoryDepth` (6) levels.

If a fallback was applied, a warning is logged at `WARN` level.

### 4. Deduplication

```go
topics = dedupeTopicItems(topics)
```

After all blocks are processed, duplicate topics are removed. The deduplication key is the concatenation of `topic_type`, `category_path`, `lines`, and `topic` text. Topics from overlap pages may appear in multiple blocks; deduplication ensures each logical topic is emitted only once.

### 5. Write `.topics` File

Call `writeTopicsFile` to produce the spec-format topic file at:

```
ARTIFACT_DIR/<group_id>/<record_id>/<root>_<parser_name>.topics
```

Each topic block is written as:

```text
topic_id: 1
topic_type: "requirement"
topic_type_en: "requirement"
lines: [38-45, 47]
topic_keywords: ["疫苗", "免疫"]
topic_keywords_en: ["vaccination", "immunization"]
topic_desc: "疫苗档案管理需求"
topic_desc_en: "Requirements for vaccination record management"
category_paths: [(["疫苗记录", ...], 0.92, [("健康", [...], 0.95), ...]), ...]
category_paths_en: [(["vaccination records", ...], 0.92, [("_health", [...], 0.95), ...]), ...]
```

Topics are separated by a blank line.

The generated file path is also the value persisted in `kb.inputs.status.output_filename` and the one logged at completion.

### 6. Embed Topics

Call `indexTopicsInTreeDir` with an `Embedder` and `TOPIC_EMBEDDING_MODEL_NAME`. For each new category directory created, the node's name and keywords are embedded and the vector is stored as:

```
<category_dir>/category.embed
```

The embed file format is a single line: `[f1, f2, ..., fn]`.

When the embedder is `nil` or `TOPIC_EMBEDDING_MODEL_NAME` is empty, the similarity-based matching is skipped and category dirs are created/matched by normalized name only.

### 7. Index Topics in Category Tree

`indexTopicsInTreeDir` (in `topic_chunking_shared.go`) walks each topic's `CategoryPathDetail` entries and calls `indexTopicPathInTree` per entry.

#### Directory Resolution (`findOrCreateCategorySubdir`)

For each node in the path, starting at `TOPIC_TREE_ROOT_DIR`:

1. **Exact match**: If a sub-directory with `normalizeCategorySegment(node.Name)` already exists, reuse it and merge the node's keywords into its `metadata.txt`.

2. **Cosine-similarity match**: If an embedder is configured, embed `node.Name + " " + keywords`, then load `category.embed` from every existing sub-directory. If the best cosine score is ≥ `CATEGORY_SIMILARITY_MIN_SCORE` (default 0.85), reuse that directory and merge keywords.

3. **Create new**: If neither step matched, create the directory at the normalized name, write `metadata.txt`, and save the category embedding.

#### `metadata.txt` Format

```text
"desc":"category_name"
"confidence":0.95
"keywords":["keyword",...]
"create_time":"20260101-120000"
```

#### `topics.txt` Upsert

Once the leaf directory is resolved, `upsertTopicToLeafDir` writes or updates `topics.txt`. Old entries for the current `record_id` are removed first; the new topic row is appended and the file is re-sorted by `record_id`.

`topics.txt` format:

```text
record_id: 123,
topic_type: "requirement"
lines: [38-45, 47]
topic_keywords: ["vaccination", "immunization"]
topic: "Requirements for vaccination record management"

record_id: 456,
...
```

#### Idempotency

Before indexing a record's topics, `removeTopicTreeRecord` walks the entire tree and removes all `topics.txt` entries whose `record_id` matches the current record. This ensures re-processing a document replaces old entries rather than accumulating duplicates.

No category directories are written under `ARTIFACT_DIR`; the tree is rooted only at `TOPIC_TREE_ROOT_DIR`.

### 8. Record Chunk Run

```go
s.Store.InsertChunkRun(ctx, ChunkRunRecord{
    SourceRecordID: rec.ID,
    ChunkingMethod: ChunkingMethodTopic,   // "topic-chunking"
    ChunkingSize:   s.FileBlockSize,
    OverlapPercent: 100 / s.FileBlockSize,
    Notes:          "semantic topic chunking with 1-page overlap",
})
```

### 9. Persist Status

`appendTopicChunkStatus` upserts the `generate_topics` status entry in `kb.inputs.status`:

```json
{
    "record_id": 123,
    "file_type": "pdf",
    "operation": "generate_topics",
    "proc_status": "success",
    "num_topics": 42,
    "input_filename": "std_20039_opendata_pdfplumber.txt",
    "output_filename": "Artifacts/0/123/std_20039_opendata_pdfplumber.topics",
    "start_time": "20260101 12:00:00",
    "ms_used": 3210
}
```

On failure, `proc_status` is `"failed"` and an `"error"` key is added.

---

## Error Handling

All failures go through `failAndPersist`:

1. Calls `appendTopicChunkStatus` with `ProcErr` set
2. Calls `Store.UpdateInputStatus` to write `proc_status = "failed"` and `error_msg` to `kb.inputs`
3. Logs the error and returns the error to `ChunkingProcessor.HandleEvent`, which surfaces it back to `ControlService.runSingleProcessor`

The `ControlService` logs the processor failure and continues running the remaining processors for that event (failure is non-fatal at the pipeline level).

---

## Wiring `GenerateTopicsProcessor`

`generate_topics` is implemented as a standalone processor (#8) independent of chunking. The required wiring:

1. Define `GenerateTopicsProcessor` implementing `Processor`:

```go
type GenerateTopicsProcessor struct {
    InputStore    DocMetadataStore
    ChunkStore    ChunkReadStore      // reads chunk files produced by chunking
    Extractor     LLMJSONExtractor
    Embedder      Embedder
    Logger        ApiTypes.JimoLogger
    ArtifactDir   string
    TopicTreeDir  string
    ModelName     string
    PromptText    string
    EmbedModel    string
    SimilarityMin float64
}

func (p *GenerateTopicsProcessor) Name() string { return "generate_topics" }
```

2. In `HandleEvent`, parse the event, load the `kb.inputs` record, locate the chunk files written by the chunking processor, read each chunk's lines, and call `extractTopicsFromLinesWithLLM` per chunk (reusing the existing helper).

3. Call `writeTopicsFile` to write the `.topics` output file, then `indexTopicsInTreeDir` for the category tree.

4. Persist status with `appendTopicChunkStatus`.

5. Register in `main.go` after `NewChunkingProcessor` so chunking always completes before topic generation:

```go
Processors: []docprocessing.Processor{
    ...
    docprocessing.NewChunkingProcessor(inputStore, chunkSvc, logger),
    docprocessing.NewGenerateTopicsProcessor(inputStore, extractor, embedder, logger),
    ...
},
```

The `ControlService` runs processors in registration order, ensuring chunking always completes before topic generation.
