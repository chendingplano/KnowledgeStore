# Fixed-Size Chunk Summary Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add full chunk summary generation, summary-tree storage, and summary clustering to the fixed-size chunking with topics pipeline in `ChenWeb`.

**Architecture:** Extend `FixedSizeChunkingService` as the single orchestration path after topic extraction. Add one focused shared helper file for summary configuration, summary-tree generation and persistence, and cluster persistence so summary logic stays isolated from chunk-boundary and topic-writing code.

**Tech Stack:** Go, stdlib filesystem APIs, existing `docprocessing` services/tests, existing LLM extraction abstractions, Git

---

## File Structure

### Existing files to modify

- `ChenWeb/server/api/doc-processing/fix-size-chunking.go`
  Purpose: orchestration, env-backed service config, success/failure persistence, logging.
- `ChenWeb/server/api/doc-processing/chunking_test.go`
  Purpose: fixed-size chunking service tests and end-to-end behavior checks.

### New files to create

- `ChenWeb/server/api/doc-processing/chunk_summary_shared.go`
  Purpose: summary config loading, summary item models, summary file read/write helpers, summary-tree builders, `ARTIFACT_WEB_DIR` persistence, `SUMMARY_CLUSTER_DIR` persistence, reclustering metadata helpers.
- `ChenWeb/server/api/doc-processing/chunk_summary_shared_test.go`
  Purpose: focused helper tests for summary grouping, line-range compaction, summary-tree storage, cluster slug/file behavior, and reprocessing cleanup.

### Files expected to remain unchanged unless investigation proves otherwise

- `ChenWeb/server/api/doc-processing/topic_chunking_shared.go`
  Reuse generic helpers only; do not mix summary-specific behavior into this file unless a tiny shared utility is clearly justified.
- `ChenWeb/server/api/doc-processing/store.go`
  No schema or store interface changes are planned in this pass.
- `ChenWeb/server/api/doc-processing/chunking-processor.go`
  No event pipeline changes are planned in this pass.

## Execution Notes

- Follow TDD strictly: write the failing test, run it to confirm the expected failure, then implement the minimal code to pass.
- Keep summary-tree and cluster writes deterministic.
- Preserve existing fixed-size topic behavior and `.chunks` / `.topics` artifact naming.
- Do not touch unrelated `KnowledgeStore` spec files during implementation.

## Chunk 1: Service Contract and Summary Config

### Task 1: Add failing service test for summary artifacts and config wiring

**Files:**
- Modify: `ChenWeb/server/api/doc-processing/chunking_test.go`
- Test: `ChenWeb/server/api/doc-processing/chunking_test.go`

- [ ] **Step 1: Write the failing test**

Add a test modeled after `TestService_HandleInput_WritesChunksAndStatus` that expects:
- `summary_0_0001.txt` and `summary_0_0002.txt` to exist
- at least one higher-level summary file to exist
- `ARTIFACT_WEB_DIR` to receive a `summaries.txt` leaf containing the root summary ID
- `SUMMARY_CLUSTER_DIR` to receive a cluster markdown file

- [ ] **Step 2: Run the targeted test to verify it fails**

Run: `go test ./server/api/doc-processing -run TestService_HandleInput_WritesSummariesTreeAndClusters`

Expected: FAIL because summary files, tree storage, and cluster files are not implemented yet.

- [ ] **Step 3: Add service config fields without behavior**

In `fix-size-chunking.go`, add `FixedSizeChunkingService` fields for:
- `ArtifactWebDir`
- `SummaryClusterDir`
- `SummaryGroupSize`
- `SummaryModelName`
- `SummaryPromptText`
- summary prompt/model loading errors
- similarity threshold / reclustering days config

Wire them in `NewFixedSizeChunkingService(...)` using env lookups, but do not implement the full workflow yet.

- [ ] **Step 4: Re-run the targeted test**

Run: `go test ./server/api/doc-processing -run TestService_HandleInput_WritesSummariesTreeAndClusters`

Expected: FAIL, but now on missing summary behavior rather than missing service fields or setup.

- [ ] **Step 5: Commit**

```bash
git add ChenWeb/server/api/doc-processing/fix-size-chunking.go ChenWeb/server/api/doc-processing/chunking_test.go
git commit -m "test: add failing fixed-size summary service coverage"
```

## Chunk 2: Summary File Models and Leaf Summary Writing

### Task 2: Add failing helper tests for summary file generation

**Files:**
- Create: `ChenWeb/server/api/doc-processing/chunk_summary_shared_test.go`
- Create: `ChenWeb/server/api/doc-processing/chunk_summary_shared.go`
- Test: `ChenWeb/server/api/doc-processing/chunk_summary_shared_test.go`

- [ ] **Step 1: Write the failing helper tests**

Add tests for:
- summary ID formatting: `93_0_0001`
- summary filename formatting: `summary_0_0001.txt`
- summary file serialization containing `summary_begin` / `summary_end` (no colon), `keywords_en`, `category_paths` in tuple format, `summary_en_begin`/`summary_en_end`
- leaf summary line-range capture from chunk overlap/regular lines

- [ ] **Step 2: Run the helper tests to verify they fail**

Run: `go test ./server/api/doc-processing -run 'Test(BuildSummaryID|SummaryFileName|WriteSummaryFile|LeafSummaryLines)'`

Expected: FAIL because `chunk_summary_shared.go` does not exist yet.

- [ ] **Step 3: Write minimal helper implementation**

Create `chunk_summary_shared.go` with:
- `summaryGenerateResult` result struct (returned by `generateSummary` and the `GenerateSummary` callback)
- `SummaryItem` struct (includes `SummaryEn`, `KeywordsEn`, `CategoryPathItems`, `CategoryPathItemsEn`)
- `SummaryCluster` struct
- `buildSummaryID(recordID int64, level int, seqNo int) string`
- `summaryFileName(level int, seqNo int) string`
- `writeSummaryFile(...)` — writes new file format with `keywords_en`, `category_paths` (rich tuple format), `category_paths_en`, `summary_begin`/`summary_end`, `summary_en_begin`/`summary_en_end`
- line-range compaction helpers reused by summary writing

- [ ] **Step 4: Re-run the helper tests**

Run: `go test ./server/api/doc-processing -run 'Test(BuildSummaryID|SummaryFileName|WriteSummaryFile|LeafSummaryLines)'`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add ChenWeb/server/api/doc-processing/chunk_summary_shared.go ChenWeb/server/api/doc-processing/chunk_summary_shared_test.go
git commit -m "feat: add summary file helpers for fixed-size chunking"
```

### Task 3: Wire leaf summary generation into the service

**Files:**
- Modify: `ChenWeb/server/api/doc-processing/fix-size-chunking.go`
- Modify: `ChenWeb/server/api/doc-processing/chunking_test.go`
- Test: `ChenWeb/server/api/doc-processing/chunking_test.go`

- [ ] **Step 1: Write a failing service test for leaf summaries only**

Add or refine a test that checks:
- one level-0 summary file per chunk
- file contents include chunk line coverage
- failure status is persisted if summary generation returns an error

- [ ] **Step 2: Run the targeted test to verify it fails**

Run: `go test ./server/api/doc-processing -run 'TestService_HandleInput_(WritesLeafSummaries|SummaryGenerationFailure)'`

Expected: FAIL because `HandleInput(...)` does not generate summaries yet.

- [ ] **Step 3: Implement minimal leaf-summary orchestration**

In `fix-size-chunking.go`:
- add a summary-generation dependency seam compatible with tests
- after topic extraction, build one leaf `SummaryItem` per chunk
- write `summary_0_####.txt` files into the record artifact dir
- preserve existing failure handling via `failAndPersist(...)`

- [ ] **Step 4: Re-run the targeted test**

Run: `go test ./server/api/doc-processing -run 'TestService_HandleInput_(WritesLeafSummaries|SummaryGenerationFailure)'`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add ChenWeb/server/api/doc-processing/fix-size-chunking.go ChenWeb/server/api/doc-processing/chunking_test.go
git commit -m "feat: generate leaf summaries for fixed-size chunks"
```

## Chunk 3: Recursive Summary Tree and `ARTIFACT_WEB_DIR`

### Task 4: Add failing helper tests for recursive grouping

**Files:**
- Modify: `ChenWeb/server/api/doc-processing/chunk_summary_shared_test.go`
- Modify: `ChenWeb/server/api/doc-processing/chunk_summary_shared.go`
- Test: `ChenWeb/server/api/doc-processing/chunk_summary_shared_test.go`

- [ ] **Step 1: Write the failing helper tests**

Add tests for:
- grouping 7 leaf summaries with `SUMMARY_GROUP_SIZE=3` produces 3 level-1 summaries and 1 level-2 root summary
- parent summaries preserve combined child line ranges
- parent summaries keep child IDs in deterministic order

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run: `go test ./server/api/doc-processing -run 'Test(BuildSummaryTree|ParentSummaryLines|ParentSummaryChildren)'`

Expected: FAIL because recursive summary-tree construction is not implemented yet.

- [ ] **Step 3: Implement minimal recursive tree builder**

In `chunk_summary_shared.go`, add:
- a function that groups contiguous summaries by `SUMMARY_GROUP_SIZE`
- parent summary creation with deterministic level-local sequence numbers
- helpers to collect all summaries by level for file writing

- [ ] **Step 4: Re-run the targeted tests**

Run: `go test ./server/api/doc-processing -run 'Test(BuildSummaryTree|ParentSummaryLines|ParentSummaryChildren)'`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add ChenWeb/server/api/doc-processing/chunk_summary_shared.go ChenWeb/server/api/doc-processing/chunk_summary_shared_test.go
git commit -m "feat: build recursive summary trees"
```

### Task 5: Add failing tests for `ARTIFACT_WEB_DIR` storage and reprocessing

**Files:**
- Modify: `ChenWeb/server/api/doc-processing/chunking_test.go`
- Modify: `ChenWeb/server/api/doc-processing/chunk_summary_shared_test.go`
- Modify: `ChenWeb/server/api/doc-processing/chunk_summary_shared.go`
- Modify: `ChenWeb/server/api/doc-processing/fix-size-chunking.go`

- [ ] **Step 1: Write the failing tests**

Add service/helper tests for:
- root summary category path normalized to snake_case under `ARTIFACT_WEB_DIR`
- root summary ID written to `summaries.txt`
- reprocessing the same `record_id` replaces prior root summary IDs instead of duplicating them
- invalid category path falls back to an uncategorized location

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run: `go test ./server/api/doc-processing -run 'Test(ArtifactWebDir|SummaryTreeReprocess|SummaryTreeFallback|Service_HandleInput_WritesSummaryTree)'`

Expected: FAIL because `ARTIFACT_WEB_DIR` writes are not implemented yet.

- [ ] **Step 3: Implement minimal `ARTIFACT_WEB_DIR` behavior**

In `chunk_summary_shared.go`:
- add root-summary category-path normalization
- add `summaries.txt` read/replace/write helpers
- remove stale record references before writing the new root summary ID

In `fix-size-chunking.go`:
- write the root summary into `ARTIFACT_WEB_DIR` after the summary tree is built

- [ ] **Step 4: Re-run the targeted tests**

Run: `go test ./server/api/doc-processing -run 'Test(ArtifactWebDir|SummaryTreeReprocess|SummaryTreeFallback|Service_HandleInput_WritesSummaryTree)'`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add ChenWeb/server/api/doc-processing/fix-size-chunking.go ChenWeb/server/api/doc-processing/chunk_summary_shared.go ChenWeb/server/api/doc-processing/chunk_summary_shared_test.go ChenWeb/server/api/doc-processing/chunking_test.go
git commit -m "feat: persist summary trees under ARTIFACT_WEB_DIR"
```

## Chunk 4: Summary Clusters in `SUMMARY_CLUSTER_DIR`

### Task 6: Add failing helper tests for cluster files and cluster state

**Files:**
- Modify: `ChenWeb/server/api/doc-processing/chunk_summary_shared_test.go`
- Modify: `ChenWeb/server/api/doc-processing/chunk_summary_shared.go`

- [ ] **Step 1: Write the failing helper tests**

Add tests for:
- slug generation for `cluster_000001_example_topic.md`
- metadata file creation at `SUMMARY_CLUSTER_DIR/_cluster_state.json`
- stable next cluster ID allocation
- renaming cluster markdown when label changes but `cluster_id` stays fixed

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run: `go test ./server/api/doc-processing -run 'Test(ClusterSlug|ClusterState|ClusterRename|NextClusterID)'`

Expected: FAIL because cluster helpers are not implemented yet.

- [ ] **Step 3: Implement minimal cluster persistence helpers**

In `chunk_summary_shared.go`, add:
- slugify helper matching the spec
- cluster state read/write helpers
- cluster markdown filename generation
- basic create/update helpers inside `SUMMARY_CLUSTER_DIR`

- [ ] **Step 4: Re-run the targeted tests**

Run: `go test ./server/api/doc-processing -run 'Test(ClusterSlug|ClusterState|ClusterRename|NextClusterID)'`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add ChenWeb/server/api/doc-processing/chunk_summary_shared.go ChenWeb/server/api/doc-processing/chunk_summary_shared_test.go
git commit -m "feat: add summary cluster storage helpers"
```

### Task 7: Add failing service tests for cluster assignment and reprocessing

**Files:**
- Modify: `ChenWeb/server/api/doc-processing/chunking_test.go`
- Modify: `ChenWeb/server/api/doc-processing/fix-size-chunking.go`
- Modify: `ChenWeb/server/api/doc-processing/chunk_summary_shared.go`

- [ ] **Step 1: Write the failing service tests**

Add tests that verify:
- cluster markdown files are written under `SUMMARY_CLUSTER_DIR`
- the same record can be reprocessed without duplicate source summary IDs remaining in clusters
- cluster-write failures trigger `proc_status = "failed"`

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run: `go test ./server/api/doc-processing -run 'TestService_HandleInput_(WritesSummaryClusters|ClusterReprocessReplace|ClusterWriteFailure)'`

Expected: FAIL because the service does not update clusters yet.

- [ ] **Step 3: Implement minimal incremental clustering**

In `chunk_summary_shared.go`:
- cluster level-1 and above summaries by default
- remove prior summary references for the current `record_id`
- assign new summaries to an existing cluster when similarity passes threshold
- create a new cluster when no existing cluster qualifies

In `fix-size-chunking.go`:
- invoke cluster persistence after summary tree + `ARTIFACT_WEB_DIR` writing and before success status persistence

- [ ] **Step 4: Re-run the targeted tests**

Run: `go test ./server/api/doc-processing -run 'TestService_HandleInput_(WritesSummaryClusters|ClusterReprocessReplace|ClusterWriteFailure)'`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add ChenWeb/server/api/doc-processing/fix-size-chunking.go ChenWeb/server/api/doc-processing/chunk_summary_shared.go ChenWeb/server/api/doc-processing/chunking_test.go
git commit -m "feat: add incremental summary clustering"
```

## Chunk 5: Reclustering and Full-Service Verification

### Task 8: Add failing helper tests for reclustering cadence

**Files:**
- Modify: `ChenWeb/server/api/doc-processing/chunk_summary_shared_test.go`
- Modify: `ChenWeb/server/api/doc-processing/chunk_summary_shared.go`

- [ ] **Step 1: Write the failing helper tests**

Add tests for:
- reclustering required when `last_full_recluster_at` is older than `RECLUSTERING_DAYS`
- reclustering skipped when still fresh
- reclustering rewrites cluster files deterministically

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run: `go test ./server/api/doc-processing -run 'Test(ReclusterDue|ReclusterNotDue|ReclusterRewrite)'`

Expected: FAIL because reclustering metadata and rewrite logic are incomplete.

- [ ] **Step 3: Implement minimal reclustering support**

In `chunk_summary_shared.go`, add:
- due-date calculation from `_cluster_state.json`
- deterministic full rewrite path for cluster markdowns
- state update after successful reclustering

- [ ] **Step 4: Re-run the targeted tests**

Run: `go test ./server/api/doc-processing -run 'Test(ReclusterDue|ReclusterNotDue|ReclusterRewrite)'`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add ChenWeb/server/api/doc-processing/chunk_summary_shared.go ChenWeb/server/api/doc-processing/chunk_summary_shared_test.go
git commit -m "feat: add summary reclustering metadata"
```

### Task 9: Run the full `doc-processing` verification pass

**Files:**
- Test: `ChenWeb/server/api/doc-processing/*.go`

- [ ] **Step 1: Run the focused package tests**

Run: `go test ./server/api/doc-processing`

Expected: PASS

- [ ] **Step 2: Run the broader ChenWeb verification if the package tests pass**

Run: `go test ./...`

Expected: PASS, or capture unrelated existing failures separately from this change.

- [ ] **Step 3: Inspect artifacts and changed files**

Verify that only the planned files changed:
- `ChenWeb/server/api/doc-processing/fix-size-chunking.go`
- `ChenWeb/server/api/doc-processing/chunk_summary_shared.go`
- `ChenWeb/server/api/doc-processing/chunk_summary_shared_test.go`
- `ChenWeb/server/api/doc-processing/chunking_test.go`

- [ ] **Step 4: Commit the verification-ready implementation**

```bash
git add ChenWeb/server/api/doc-processing/fix-size-chunking.go ChenWeb/server/api/doc-processing/chunk_summary_shared.go ChenWeb/server/api/doc-processing/chunk_summary_shared_test.go ChenWeb/server/api/doc-processing/chunking_test.go
git commit -m "feat: add fixed-size chunk summary pipeline"
```

## References

- Spec: `KnowledgeStore/DevDocuments/Specs/2026-04-29-fix-size-chunk-summary-design.md`
- Source specs:
  - `KnowledgeStore/DevDocuments/Specs/spec-chunking-fix-size.md`
  - `KnowledgeStore/DevDocuments/Specs/spec-generate-chunk-summary.md`
- Key implementation files:
  - `ChenWeb/server/api/doc-processing/fix-size-chunking.go`
  - `ChenWeb/server/api/doc-processing/topic_chunking_shared.go`
  - `ChenWeb/server/api/doc-processing/chunking_test.go`

## Notes for the Implementer

- Prefer adding a narrow summary-generation seam rather than overloading the existing topic extractor contract.
- Keep helper APIs small and file responsibilities clear.
- Do not refactor unrelated topic-chunking code unless a tiny shared helper removes obvious duplication.
- Preserve current status persistence behavior exactly: any summary, summary-tree, or cluster failure must flow through `failAndPersist(...)`.
