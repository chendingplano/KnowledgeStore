# Fixed-Size Chunk Summary Design

Date: 2026-04-29
Status: Draft for review

## Goal

Add full chunk summary capabilities from `spec-generate-chunk-summary.md` to the existing fixed-size chunking with topics flow defined in `spec-chunking-fix-size.md`.

The implementation target remains the current fixed-size chunking pipeline in:

- `ChenWeb/server/api/doc-processing/fix-size-chunking.go`
- `ChenWeb/server/api/doc-processing/topic_chunking_shared.go`

The new work must preserve the current fixed-size chunking behavior and topic outputs while adding:

- per-chunk summaries
- recursive summary tree generation
- summary clustering
- incremental cluster updates with periodic full reclustering

## Scope

This design includes the full summary scope:

1. Generate a leaf summary for each fixed-size chunk.
2. Generate parent summaries recursively until a single root summary remains.
3. Persist summary artifacts in the record artifact directory.
4. Cluster summaries across documents into stable cluster markdown files.
5. Support record reprocessing by deleting stale summary artifacts and replacing prior cluster contributions for the same record.

Out of scope:

- redesigning the fixed-size chunk boundary algorithm
- replacing the current topic extraction behavior
- introducing database tables for summaries or clusters in this pass
- changing `kb.chunks` schema or `kb.inputs.status` schema beyond existing success/failure behavior

## Chosen Approach

We will extend the existing fixed-size chunking pipeline directly instead of introducing a second post-processing service or a broader enrichment framework.

Why this approach:

- the current fixed-size service already orchestrates record lookup, chunk building, topic extraction, artifact writing, and status persistence
- summary generation is additive and naturally follows chunk/topic extraction
- failure semantics stay simple because the whole run still succeeds or fails as one unit
- existing service tests can be extended to cover the new behavior without large refactors

## Architecture

### 1. Service Orchestration

`FixedSizeChunkingService.HandleInput(...)` remains the top-level orchestrator.

Updated execution order:

1. Load input record.
2. Parse canonical line file.
3. Build fixed-size chunks.
4. Write `.chunks` artifact.
5. Extract topics for each chunk.
6. Write `.topics` and compatibility `topics.txt`.
7. Update topic category tree.
8. Generate leaf summaries for each chunk.
9. Build recursive summary tree.
10. Persist summary files for all levels.
11. Update shared summary clusters.
12. Insert `kb.chunks` run summary.
13. Upsert `kb.inputs.status` with `operation = "chunked"` success payload.

If any step fails:

- stop immediately
- persist failed `kb.inputs.status`
- do not insert a successful completion state

### 2. Shared Summary Helpers

Add a new helper file:

- `ChenWeb/server/api/doc-processing/chunk_summary_shared.go`

Responsibilities:

- load summary model and prompt configuration from environment
- normalize summary payloads
- build summary IDs and file names
- serialize and parse summary file content
- build recursive summary tree from leaf summaries
- manage summary cleanup for reprocessing
- manage cluster assignment, slug generation, and markdown persistence

This keeps `fix-size-chunking.go` focused on orchestration and keeps summary-specific logic reusable and testable.

### 3. Existing Topic Helpers Stay Intact

`topic_chunking_shared.go` remains responsible for:

- topic extraction
- topic file writing
- category tree writing
- artifact naming helpers already shared by chunking modes

The new summary helper file may reuse general helpers from there where appropriate, but topic behavior should not be merged into summary behavior unless the shared code is clearly generic.

## Data Model

### Summary Item

Add an in-memory summary model similar to:

```go
// summaryGenerateResult carries all LLM output for one summary generation call.
type summaryGenerateResult struct {
    Summary             string
    SummaryEn           string            // English translation when input is non-English
    Keywords            []string
    KeywordsEn          []string          // English translation when input is non-English
    CategoryPaths       []string          // flat segment names for tree-dir indexing
    CategoryNodes       []CategoryPathNode // per-node metadata for first category path
    CategoryPathItems   []CategoryPathEntry // rich format written to summary file
    CategoryPathItemsEn []CategoryPathEntry // English translations
}

type SummaryItem struct {
    SummaryID           string
    RecordID            int64
    Level               int
    SeqNo               int
    Lines               []string
    Children            []string
    Keywords            []string
    KeywordsEn          []string
    CategoryPaths       []string            // flat names for tree-dir indexing
    CategoryNodes       []CategoryPathNode
    CategoryPathItems   []CategoryPathEntry // rich format for summary file
    CategoryPathItemsEn []CategoryPathEntry // English translations
    Summary             string
    SummaryEn           string
    Embedding           []float64
}
```

Notes:

- `SummaryID` uses the canonical form `<record_id>_<level>_<seqno>`.
- `Lines` for leaf summaries come from the chunk line ranges.
- `Lines` for parent summaries represent the combined covered line ranges of descendant leaves.
- `Children` contains child summary IDs for non-leaf summaries.
- `SummaryEn` and `KeywordsEn` are only populated when the source content is non-English.
- `CategoryPathItems` and `CategoryPathItemsEn` are the rich structured form used in the summary file; `CategoryPaths` and `CategoryNodes` are the flat form used for tree-dir indexing.
- `Embedding` is optional in-memory and persisted only in `.embed` files alongside the summary file.

### Cluster Model

Add an in-memory cluster model similar to:

```go
type SummaryCluster struct {
    ClusterID          string
    ClusterName        string
    ClusterLevel       string
    CreatedAt          string
    UpdatedAt          string
    SummaryIDs         []string
    RepresentativeIDs  []string
    RelatedClusterIDs  []string
    CentroidEmbedding  []float64
}
```

Notes:

- `ClusterID` is permanent and stable, e.g. `cluster_000001`.
- filename is derived separately via slugified label text
- centroid is an internal helper value and does not need to be written into markdown unless later required

## Configuration

Add environment-backed configuration to `FixedSizeChunkingService`:

- `CHUNK_SUMMARY_MODEL_NAME`
- `CHUNK_SUMMARY_PROMPT`
- `SUMMARY_GROUP_SIZE`
- `ARTIFACT_WEB_DIR` — directory used for summary-tree indexing (previously `ARTIFACT_WEB_DIR`)
- `ARTIFACT_WEB_DIR`
- `SUMMARY_CLUSTER_SIMILARITY_THRESHOLD`
- `RECLUSTERING_DAYS`
- `SUMMARY_EMBEDDING_MODEL_NAME` if embeddings are generated through a separate model

Defaults:

- model name defaults should follow the current LLM configuration pattern used by chunk/topic extraction
- `SUMMARY_GROUP_SIZE` should default to a small deterministic value such as `5`
- `RECLUSTERING_DAYS` should default to a conservative value such as `7`

If required summary model or prompt configuration is missing:

- fail the run before summary generation starts
- persist failure status

## Artifact Layout

### Per-Record Summary Files

Store summary artifacts in:

- `ARTIFACT_DIR/<group_id>/<record_id>/summary_<level>_<seqno>.txt`

Examples:

- `ARTIFACT_DIR/0/93/summary_0_0001.txt`
- `ARTIFACT_DIR/0/93/summary_0_0002.txt`
- `ARTIFACT_DIR/0/93/summary_1_0001.txt`

File format:

```text
summary_id: "93_1_0001"
record_id: 93
level: 1
lines: [1-45]
children: ["93_0_0001", "93_0_0002"]
keywords: ["vaccination records", ...]
keywords_en: ["vaccination records", ...]
category_paths: [([...], 0.92, [("public_health", [...], 0.95), ...]), ...]
category_paths_en: [([...], 0.92, [("public health", [...], 0.95), ...]), ...]
summary_begin
<summary text, may span multiple lines>
summary_end
summary_en_begin
<English translation, only when source is non-English>
summary_en_end
```

Notes:

- `keywords_en`, `category_paths_en`, and `summary_en_begin`/`summary_en_end` blocks are omitted when the source content is English
- leaf summaries use `children: []`
- line ranges are deterministic and compacted
- embeddings are stored in `.embed` files only, not in the `.txt` file

### Summary Tree Storage

Store summary-tree category outputs under:

- `ARTIFACT_WEB_DIR/<category_1>/<category_2>/.../summaries.txt`

Workflow:

1. take the root summary of the current document summary tree
2. extract up to 6 levels of descriptive categories from that root summary
3. normalize each category segment to snake_case
4. use the category path as a directory tree under `ARTIFACT_WEB_DIR`
5. append or replace the current document root summary ID in the leaf `summaries.txt`

Leaf file format:

```text
53_0_0018
77_0_0021
```

Notes:

- the summary tree storage is separate from summary clustering
- this path stores root summary IDs only, not full summary bodies
- writes must be idempotent for a reprocessed record
- invalid or missing category paths should fall back to a deterministic uncategorized path

### Shared Cluster Files

Store cross-record cluster markdown files in:

- `ARTIFACT_WEB_DIR/cluster_000001_some_slug.md`

Markdown format follows the chunk summary spec:

```markdown
cluster_id: cluster_000001
cluster_name: Example Cluster
cluster_level: level_1
created_at: 2026-04-29
updated_at: 2026-04-29
summary_count: 42

# Example Cluster

## Cluster Summary

...

## Representative Summaries

93_1_0001, 102_1_0003

## Source Summaries

93_1_0001, 102_1_0003, ...

## Related clusters

cluster_000002_other_topic
```

Notes:

- file name is derived from stable `cluster_id` and current slugified cluster name
- if the cluster label changes, rename the file while preserving `cluster_id`

## Model Output Format

The LLM returns a JSON object with the following shape:

```json
{
  "summary": "summary in its input language",
  "summary_en": "accurate English translation (only when input is non-English)",
  "keywords": ["keyword1", "keyword2"],
  "keywords_en": ["keyword1", "keyword2"],
  "categories": [
    {
      "category_path": [
        { "name": "public_health", "keywords": ["health management"], "confidence": 0.95 },
        ...
      ],
      "path_keywords": ["vaccination records", "recipient data"],
      "path_confidence": 0.92
    }
  ],
  "categories_en": [ ... ]
}
```

- `summary_en`, `keywords_en`, and `categories_en` are generated only when the input language is non-English.
- `categories_en` mirrors the structure of `categories` but uses English names and keywords.

## Summary Generation Flow

### 1. Leaf Summaries

For each fixed-size chunk:

- gather the chunk lines in chunk order
- detect the primary language of the chunk content (English or Chinese)
- append a language directive to the summary prompt so the LLM responds in the same language as the source content
- call the summary model with the language-aware prompt
- create a level 0 summary item
- preserve chunk sequence ordering

#### Language Detection

Inspect the non-whitespace rune count in the input text. If more than 20% of those runes fall in the CJK Unified Ideographs block (U+4E00–U+9FFF), the language is Chinese; otherwise English. This applies to both leaf summaries (line content) and parent summaries (child summary text).

The language directive appended to the prompt is:

- Chinese content: `IMPORTANT: Generate the summary in Chinese.`
- English content: `IMPORTANT: Generate the summary in English.`

Leaf summary numbering:

- level = `0`
- seqno = chunk sequence number

### 2. Parent Summaries

Build higher-level summaries recursively:

- group contiguous summaries in batches of `SUMMARY_GROUP_SIZE`
- summarize each group into the next level
- continue until only one summary remains at the current level

Parent summary numbering:

- seqno starts at `1` within each level
- ordering follows child group order deterministically

### 3. Line Coverage

Each parent summary inherits combined line coverage from descendant leaf summaries.

This keeps every summary mappable back to the original canonical line file and matches the spec’s emphasis on line-based provenance.

## Reprocessing and Cleanup

Generating chunk summaries MUST be idempotent. The pipeline clears all stale artifacts for the record before writing new ones so that reprocessing a record produces exactly the same state as processing it for the first time.

When a record is re-chunked:

1. Delete existing `summary_*` files in `ARTIFACT_DIR/<group_id>/<record_id>/` before generating new summary files.
2. Remove all summary IDs that start with `<record_id>_` from every `summaries.txt` file under `ARTIFACT_WEB_DIR` before writing the new root-summary reference. After removal, append the new root summary ID to the target leaf file (do not overwrite — other records' IDs in that file must be preserved).
3. Load cluster files from `ARTIFACT_WEB_DIR` and remove any summary references belonging to the current `record_id` before assigning new summaries to clusters.
4. Delete cluster files that become empty after removal.
5. Generate fresh summaries and reassign them to trees and clusters.

This prevents stale record content from remaining in summary-tree and cluster outputs while preserving entries from other records that share the same leaf files.

## Clustering Strategy

### 1. Candidate Summaries

Cluster summaries starting from level 1 and above by default.

Rationale:

- level 0 summaries may be too granular and noisy across documents
- level 1 and higher better represent semantically meaningful grouped content

If future usage requires leaf clustering too, make the minimum cluster level configurable.

### 2. Incremental Assignment

For each new candidate summary:

1. generate or load embedding
2. compare against existing cluster centroids
3. assign to nearest cluster if similarity is above threshold
4. otherwise create a new cluster

### 3. Reclustering

Track full reclustering metadata using a small local metadata file under the cluster directory, for example:

- `ARTIFACT_WEB_DIR/_cluster_state.json`

This file stores:

- last full recluster date
- next cluster id sequence

When `RECLUSTERING_DAYS` has elapsed:

- load all current summaries represented in clusters
- run full regrouping
- merge or split clusters as needed
- regenerate cluster markdown files deterministically

### 4. Cluster Naming

Cluster names should be generated from representative summary content through the LLM or deterministic fallback heuristics.

Filename generation uses the spec-compatible slugifier.

## Interfaces and Testability

To keep tests isolated, separate the LLM-style dependencies by responsibility:

- topic JSON extraction interface stays as-is
- summary generation interface for leaf and parent summaries
- embedding generation interface for clustering
- optional cluster label generation interface if labels are LLM-generated

Tests can then stub each stage independently without forcing all behaviors through a single fake extractor.

## Logging

Add structured logs for:

- summary generation start/end per chunk and per parent group
- number of summaries per level
- summary tree category assignment and root-summary storage updates
- cluster assignment decisions
- new cluster creation
- reclustering runs
- cleanup of stale summaries, summary-tree references, and cluster references

This follows workspace logging guidance and will help diagnose cost, latency, and clustering drift.

## Failure Semantics

Any failure in:

- summary prompt/model loading
- leaf summary generation
- parent summary generation
- summary file writing
- summary tree category extraction
- summary tree leaf writing
- cluster metadata loading
- cluster assignment
- cluster markdown writing
- record cleanup during reprocessing

must:

- abort the run
- write failed `kb.inputs.status`
- avoid reporting success

No partial-success mode is introduced in this pass.

## Testing Plan

Follow TDD and extend the current fixed-size service tests first.

### Service-Level Tests

Add failing tests to `ChenWeb/server/api/doc-processing/chunking_test.go` for:

1. `HandleInput` writes leaf summary files for each chunk
2. `HandleInput` writes parent summary files recursively until a root summary exists
3. `HandleInput` writes root-summary IDs into the categorized `ARTIFACT_WEB_DIR` leaf
4. reprocessing removes stale summary files before rewriting
5. reprocessing replaces prior root-summary references for the same record in `ARTIFACT_WEB_DIR`
6. cluster markdown files are created in `ARTIFACT_WEB_DIR` with stable cluster IDs
7. cluster reassignment replaces prior summaries for the same record
8. summary generation failure persists failed input status
9. summary-tree write failure persists failed input status
10. cluster write failure persists failed input status

### Helper Tests

Add focused tests for:

- summary grouping by `SUMMARY_GROUP_SIZE`
- compact line range merging across child summaries
- summary file serialization and parsing
- summary-tree category-path normalization and fallback
- `summaries.txt` idempotent replace behavior
- slug generation
- cluster file rename behavior when label changes
- cluster state metadata persistence
- record-level removal from cluster source summaries

## Risks and Mitigations

### Risk: LLM Call Volume

Fixed-size chunking can produce many chunks, which increases topic and summary call count.

Mitigation:

- keep chunk size configurable
- keep `SUMMARY_GROUP_SIZE` configurable
- log summary counts and durations
- keep summary generation helpers injectable for future batching

### Risk: Cluster Drift

Incremental cluster assignment can slowly diverge from ideal grouping.

Mitigation:

- periodic full reclustering
- stable cluster state metadata
- deterministic regeneration when full reclustering occurs

### Risk: Cross-Record Shared File Consistency

Summary-tree and cluster files are shared across records and can be corrupted by partial updates.

Mitigation:

- write through temp files then atomic rename where practical
- remove stale record references before adding new ones
- preserve deterministic row ordering

### Risk: Over-Coupling Summary and Topic Code

Summary work may tempt reuse that obscures responsibilities.

Mitigation:

- keep summary logic in its own helper file
- reuse only clearly generic helpers

## Rollout Plan

1. Add failing service and helper tests.
2. Implement summary configuration and data models.
3. Implement leaf summary generation and file writing.
4. Implement recursive summary tree generation and writing.
5. Implement cluster metadata and markdown persistence.
6. Implement reprocessing cleanup behavior.
7. Run targeted tests for `doc-processing`.

## Result

This design adds full chunk summary functionality to the existing fixed-size chunking with topics flow using the current service as the orchestration point, a new shared summary helper layer for behavior that is specific to summaries and clustering, deterministic artifact layouts, and full failure propagation through the existing status path.
