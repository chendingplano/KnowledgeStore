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
type SummaryItem struct {
    SummaryID string
    RecordID  int64
    Level     int
    SeqNo     int
    Lines     []string
    Children  []string
    Summary   string
    Embedding []float64
}
```

Notes:

- `SummaryID` uses the canonical form `<record_id>_<level>_<seqno>`.
- `Lines` for leaf summaries come from the chunk line ranges.
- `Lines` for parent summaries represent the combined covered line ranges of descendant leaves.
- `Children` contains child summary IDs for non-leaf summaries.
- `Embedding` is optional in-memory and persisted only if available from the configured embedding path for clustering.

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
- `SUMMARY_CLUSTER_DIR` (optional; defaults under `ARTIFACT_DIR/clusters`)
- `SUMMARY_CLUSTER_SIMILARITY_THRESHOLD`
- `RECLUSTERING_DAYS`
- `SUMMARY_EMBEDDING_MODEL_NAME` if embeddings are generated through a separate model

Defaults:

- model name defaults should follow the current LLM configuration pattern used by chunk/topic extraction
- `SUMMARY_GROUP_SIZE` should default to a small deterministic value such as `5`
- `RECLUSTERING_DAYS` should default to a conservative value such as `7`
- cluster dir defaults to `ARTIFACT_DIR/clusters`

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
summary_begin:
<summary text>
summary_end
embedding: [0.123, 0.456]
```

Notes:

- `embedding` is written only when available
- leaf summaries use `children: []`
- line ranges should be deterministic and compacted

### Shared Cluster Files

Store cross-record cluster markdown files in:

- `ARTIFACT_DIR/clusters/cluster_000001_some_slug.md`

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

## Summary Generation Flow

### 1. Leaf Summaries

For each fixed-size chunk:

- gather the chunk lines in chunk order
- call the summary model with the configured summary prompt
- create a level 0 summary item
- preserve chunk sequence ordering

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

When a record is re-chunked:

1. delete existing `summary_*` files in `ARTIFACT_DIR/<group_id>/<record_id>/`
2. load cluster files and remove any summary references belonging to the current `record_id`
3. delete cluster files that become empty after removal
4. generate fresh summaries and reassign them to clusters

This mirrors the spec requirement that summaries be removed before regeneration and prevents stale record content from remaining in cluster files.

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

- `ARTIFACT_DIR/clusters/_cluster_state.json`

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
- cluster assignment decisions
- new cluster creation
- reclustering runs
- cleanup of stale summaries and cluster references

This follows workspace logging guidance and will help diagnose cost, latency, and clustering drift.

## Failure Semantics

Any failure in:

- summary prompt/model loading
- leaf summary generation
- parent summary generation
- summary file writing
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
3. reprocessing removes stale summary files before rewriting
4. cluster markdown files are created with stable cluster IDs
5. cluster reassignment replaces prior summaries for the same record
6. summary generation failure persists failed input status
7. cluster write failure persists failed input status

### Helper Tests

Add focused tests for:

- summary grouping by `SUMMARY_GROUP_SIZE`
- compact line range merging across child summaries
- summary file serialization and parsing
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

Cluster files are shared across records and can be corrupted by partial updates.

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
