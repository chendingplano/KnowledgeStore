# Spec: Adding a Chunk-Based Doc Processor (Batch Cache-Optimized)

Date: 2026-07-02

Status: **Active — applies to all new chunk-consuming doc processors.**

References:
- Design: [2026062704 — DeepSeek Cache Algorithm Change](../design/202606/2026062704-design-deepseek-cache-algorithm-change.md)
- ADR: [2026062701 — DeepSeek Prompt Cache for Doc Processors](../adrs/202606/2026062701-adr-deepseek-cache-doc-processors.md)
- Capsule: [Doc Processor Capsule](../../Capsules/coding-capsules/doc-processor/+CAPSULE.md)

## 1. Overview

All chunk-based doc processors that make LLM calls with a shared, cacheable
chunk prefix **must** implement the `ChunkBatchProcessor` interface. This
integrates the processor into the three-phase per-chunk batching coordinator,
which schedules LLM calls so that calls sharing an identical `InputText` arrive
at DeepSeek back-to-back, reusing the implicit prompt cache.

A processor that consumes chunks but does not implement this interface runs via
the legacy per-unit fallback path — it *disables* the cache optimization only for
itself, not for other processors. However, **every** chunk processor should
implement it because the chunk prefix it sends is the same prefix the other
processors cache-share.

## 2. Preconditions

Before implementing the batch interface, confirm the processor is:

- **Chunk-based**: it reads the shared `.chunks` artifact and processes each
  `Chunk` independently. If the processor uses blocks or a different input
  source, the interface may not apply — consult the ADR.
- **Using the canonical chunk InputText**: `canonicalChunkInputText(chunk.Lines,
  docCtx)` from `input_lines.go`. This produces byte-identical input across all
  processors so DeepSeek reuses the cached prefix. All per-processor task text
  (schema, labels, chunk index) goes in the `<TASK>` section of the prompt —
  never in `InputText`.
- **1-pass or 2-pass**: a 1-pass processor makes one LLM call per chunk. A
  2-pass processor (e.g. candidate extraction → enrichment) makes two calls per
  chunk and is registered in `multiPassProcessors` so it is never chosen as the
  cache seed.

## 3. Step-by-Step Implementation

### 3.1 Struct fields

Add **batch state** fields to the processor struct. The template:

```go
// batch state (set by ChunkBatchProcessor.InitChunkBatch)
batchRecordID int64
batchChunks   []Chunk
batchDocCtx   string
batchResults  []myChunkOutcome // per-chunk accumulator slice
batchMu       sync.Mutex       // protects batchResults under concurrent Phase 3
batchStart    time.Time
```

Replace `myChunkOutcome` with a processor-specific result type that carries
everything needed by `FinalizeChunkBatch`:

```go
type myChunkOutcome struct {
    items     []map[string]any // the extracted rows
    modelName string
    language  string
    failed    bool
    fallback  bool
}
```

The `batchMu` mutex is **required**: Phase 3 calls a single processor's
`ProcessChunk` concurrently for different chunk indices, so unsynchronized
`append` to the accumulator slice is a data race.

`"sync"` must be added to the import block.

### 3.2 InitChunkBatch

Validate prompts and models, reset accumulators. Must **not** make LLM calls.

```go
func (p *MyProcessor) InitChunkBatch(ctx context.Context, recordID int64, chunks []Chunk, docCtx string) error {
    if p.PromptErr != nil {
        return fmt.Errorf("(MID_<assigned>) %s prompt error: %w", p.Name(), p.PromptErr)
    }
    if p.ModelErr != nil {
        p.Logger.Warn("%s skipped: model config error", p.Name(), "record_id", recordID, "error", p.ModelErr)
        return nil
    }
    p.batchStart = p.Now()
    p.batchRecordID = recordID
    p.batchChunks = chunks
    p.batchDocCtx = docCtx
    p.batchResults = make([]myChunkOutcome, 0, len(chunks))
    return nil
}
```

### 3.3 ProcessChunk

Bounds-check chunkIdx. Build `InputText` via `canonicalChunkInputText`. Make the
LLM call through the processor's existing `*WithFallback` path. Accumulate the
result under `batchMu`. Use the existing per-chunk logging + cache-token
stamping. Return `nil` on a failed chunk (accumulate what succeeds); return
`ErrPipelineStopped` on context cancellation.

Template (1-pass):

```go
func (p *MyProcessor) ProcessChunk(ctx context.Context, chunkIdx int) error {
    if chunkIdx < 0 || chunkIdx >= len(p.batchChunks) {
        return fmt.Errorf("(MID_<assigned>) %s chunk index %d out of range", p.Name(), chunkIdx)
    }
    if isCtxStopped(ctx) {
        return ErrPipelineStopped
    }

    chunk := p.batchChunks[chunkIdx]
    inputText := canonicalChunkInputText(chunk.Lines, p.batchDocCtx)
    localStart := p.Now()

    payload, modelName, err := p.extractWithFallback(ctx, inputText)
    // ... per-chunk logging + cacheTokenCounts ...

    if err != nil {
        if isCtxStopped(ctx) { return ErrPipelineStopped }
        p.Logger.Warn("%s chunk failed", p.Name(), "record_id", p.batchRecordID, "chunk", chunkIdx, "error", err)
        p.batchMu.Lock()
        p.batchResults = append(p.batchResults, myChunkOutcome{failed: true})
        p.batchMu.Unlock()
        return nil
    }

    // Accumulate (thread-safe).
    p.batchMu.Lock()
    p.batchResults = append(p.batchResults, myChunkOutcome{
        items:     rows,
        modelName: modelName,
        language:  lang,
    })
    p.batchMu.Unlock()
    return nil
}
```

If the processor is **2-pass**, both LLM calls happen inside `ProcessChunk`
for the same chunk, keeping the two calls adjacent so the cached prefix is
reused while warm. Example of the shared-extraction pattern (preferred):

```go
// Extract the per-chunk two-pass body into a method that BOTH the legacy
// HandleEvent path and the batch ProcessChunk call. DRY: no duplicated logic.
func (p *MyProcessor) projectChunk(ctx context.Context, ...) ([]map[string]any, string, error) {
    // Pass 1 (candidate) → Pass 2 (enrich) for one chunk
}
```

Then `ProcessChunk` calls `projectChunk` and accumulates; the legacy
`HandleEvent` path's `runConcurrent` closure also calls `projectChunk`
(preserving all logging, cache-token stamping, fallback tracking, and progress
counters — see §5 Pitfalls).

### 3.4 FinalizeChunkBatch

Accumulate results from `p.batchResults`, stamp IDs and timestamps, save to DB,
write artifact files, and reindex search registries. Must match exactly what the
legacy `HandleEvent` save path does.

```go
func (p *MyProcessor) FinalizeChunkBatch(ctx context.Context) error {
    if len(p.batchResults) == 0 {
        return nil
    }
    if isCtxStopped(ctx) { return ErrPipelineStopped }

    // Accumulate from all chunks.
    rows := make([]map[string]any, 0)
    detectedLang := "unknown"
    usedModel := strings.TrimSpace(p.ModelName)
    for _, outcome := range p.batchResults {
        if outcome.failed { continue }
        if outcome.language != "" && detectedLang == "unknown" { detectedLang = outcome.language }
        if m := strings.TrimSpace(outcome.modelName); m != "" { usedModel = m }
        rows = append(rows, outcome.items...)
    }

    // Stamp IDs + create_time.
    createTime := p.Now().UTC().Format(time.RFC3339)
    for i := range rows {
        rows[i]["<type>_id"] = fmt.Sprintf("%d_<type>_%d", p.batchRecordID, i+1)
        rows[i]["create_time"] = createTime
    }

    // Save, artifact, index, reindex — exactly as the legacy HandleEvent does.
    if _, err := p.Store.SaveXxx(ctx, SaveXxxRequest{
        InputRecordID: p.batchRecordID,
        EventID:       formatBatchEventID(p.batchRecordID),
        Language:      detectedLang,
        ModelName:     firstNonEmptyTrimmed(usedModel, p.ModelName),
        PromptName:    p.PromptRef,
        // ... processor-specific fields
    }); err != nil {
        return fmt.Errorf("(MID_<assigned>) %s save: %w", p.Name(), err)
    }
    // ... artifact write, search reindex ...
    return nil
}
```

Reference implementations:
- **1-pass, simplest**: `InventoryItemsProcessor` in `extract-inventory-items.go`
  (InitChunkBatch:1976, ProcessChunk:1992, FinalizeChunkBatch:2042)
- **2-pass, shared extraction**: `MetricsProcessor` in `extract-metrics.go`
  (`enrichMetricCandidates` is called from both HandleEvent and batch paths) and
  `SemanticProjectionsProcessor` in `extract-semantic-projections.go`
  (`projectChunk` shared between both paths)

### 3.5 HandleEvent coexistence

The legacy `HandleEvent(path, payload []byte) error` path must continue to work
for two reasons:

1. Selected-Processor Mode (the `operation` field in the event payload) may
   invoke this processor standalone — no batch coordinator.
2. For 2-pass processors, the batch `ProcessChunk` shares the extracted method
   with `HandleEvent`'s internal loop → they converge.

**1-pass case:** `HandleEvent` keeps its own self-contained extract loop (no
DRY refactor needed — the paths are independent).

**2-pass case:** the per-chunk work is extracted into a shared method called by
both `HandleEvent`'s loop and the batch `ProcessChunk`. The shared method must
preserve **every** side-effect: per-chunk logging, cache-token stamping
(`cacheTokenCounts` / `extractorCacheTokens`), fallback tracking, progress
counters, language detection, and error propagation. Dropping any one of these
(e.g. `UncertainMetrics` discard — a real regression found during metrics
conversion) silently changes the legacy path's behavior.

## 4. Cache Optimization Requirements

### 4.1 Canonical InputText

Every LLM call must:

```go
inputText := canonicalChunkInputText(chunk.Lines, docCtx)
```

**Never** put task text (schema, labels, chunk index, prompt templates) into
`InputText`. Put it in the prompt — it is passed as a separate argument to the
LLM call and placed in the `<TASK>` section of the document-first prompt layout.

### 4.2 Document-first prompt layout

The shared client (`newLLMJSONInput`, `llm_capture_input.go`) sets
`DocumentFirst = true` by default. This produces:

```
system: "You are a document processing engine. Return strict JSON only."
user: <DOCUMENT_INPUT>{line JSON array}</DOCUMENT_INPUT>
      <TASK>{per-processor task text}</TASK>
```

Do not set `DocumentFirst = false` unless the stable cached prefix is the prompt
template, not the document (which only `create_artifact_category` does).

### 4.3 batchMu

Phase 3 calls the same processor's `ProcessChunk` for different chunk indices
concurrently. Every write to a shared batch-state field (slices via `append`,
string accumulators like `batchLang`, `batchModelName`) must be guarded by
`batchMu.Lock()/Unlock()`. Pre-allocated indexed writes (`p.batchResults[i] =`)
are also safe if the index is computed from `chunkIdx` and cannot clash across
goroutines — but `append` is the common pattern and needs the lock.

### 4.4 Seed selection

If the processor makes **more than one LLM call per chunk** (2-pass), add it
to `multiPassProcessors` in `chunk_batch.go`:

```go
var multiPassProcessors = map[string]struct{}{
    "extract_metrics":              {},
    "extract_semantic_projections": {},
    // add your processor here if 2-pass
}
```

This ensures it is never chosen as the cache seed (the seed must plant each
chunk's prefix with a single clean call).

## 5. Pitfalls

### 5.1 Behavior preservation in shared extraction (2-pass)

When extracting a shared method for 2-pass processors, audit the old inline
loop for every side-effect. The `metrics` conversion (Task 5) dropped
`UncertainMetrics` from the extracted method's return — the legacy
`HandleEvent` path's operational log `uncertain_metrics_count` silently became
0. Every output the old loop produced must thread through the new signature.

### 5.2 PromptName / ModelName consistency

`FinalizeChunkBatch`'s save request must use the **same** `PromptName` and
`ModelName` conventions as the legacy `HandleEvent` save. The `metrics`
conversion initially used `MentionPromptRef` (Pass-1 prompt) in the batch save
while `HandleEvent` used `RelationPromptRef` (Pass-2 prompt) — fixed to match
the legacy path. Copy the existing save call exactly.

### 5.3 Status persistence gap

The batch coordinator's `FinalizeChunkBatch` callbacks currently omit the
`persist<X>Status(ctx, rec, start, nil)` success-status write and the
`log<X>Summary(...)` finish log that `HandleEvent` performs at the end of its
save path. This means batch-processed records have no per-processor success
entries in `kb.inputs.status` and no finish log in `kb.doc_proc_logs`. This is
a **known gap** — document which status fields and log entries your processor
writes via `HandleEvent` so the gap can be closed in a follow-up (likely in the
coordinator, not per-processor).

### 5.4 Phase-3 concurrency

`ProcessChunk` may be called concurrently for the same processor on different
chunk indices. Do not rely on sequential-order assumptions (e.g. a
`batchCompletedP1` int counter without a mutex). Guard all shared writes.

### 5.5 Error handling

`ProcessChunk` should return `nil` on a per-chunk LLM failure (accumulate what
succeeds) and `ErrPipelineStopped` on context cancellation. Do not `return err`
on an ordinary LLM failure — it would abort the coordinator's Phase 3.

## 6. Registration and Configuration

### 6.1 main.go

Register the new processor in `ChenWeb/server/cmd/doc-processor/main.go`:

```go
// In the NewControlService Processors slice:
docprocessing.NewMyProcessor(inputStore, store, llmClient, logger),
```

If the `Processor` constructor requires a custom LLM client, create one as the
existing processors do (load prompts + model config from env, call the
constructor, fall back on error).

### 6.2 config.toml

If the processor is **configurable** (not mandatory Phase A), add its name to
`[doc-processing].required_processors`:

```toml
[doc-processing]
required_processors = [
    "extract_metrics",
    "extract_provisions",
    "extract_semantic_projections",
    "extract_entity",
    "extract_relation",
    "extract_inventory_items",
    "my_processor"
]
```

The processor name in `config.toml` must match `Name()` exactly.

### 6.3 Mandatory vs. configurable

If the processor is **mandatory** (Phase A), add its name to the mandatory set
in `main.go::filterConfiguredProcessors` and `control.go::isPhaseAProcessor`.
Mandatory processors always run sequentially before Phase B and do not
participate in the chunk-batch coordinator — they do not need
`ChunkBatchProcessor`.

## 7. Search Indexing

Refer to the Capsule §12.3. In short:

- Add a `searchArtifact<Xxx>` constant in `search_indexing.go`.
- Add `ReindexXxxSearchForRecord` and `buildXxxRegistryRows` functions.
- Call `ReindexXxxSearchForRecord` from `FinalizeChunkBatch` (and from the
  legacy `HandleEvent` path — same call site).
- Add a goose migration to create the `kb.search_artifacts_<type>` partition
  and BM25 + HNSW indexes.

## 8. Dashboard

Update `ChenWeb/web/src/lib/components/home3/doc-processor-dashboard-view.svelte`
per the Capsule §12.4: add the new `operation` to the stage map, add it to
`PIPELINE_FINAL_OPS` and `ALL_PROCESSOR_IDS`, and add the downstream guard.

## 9. Testing

### 9.1 Interface assertion

At minimum, verify `ChunkBatchProcessor` is satisfied:

```go
func TestMyProcessorImplementsChunkBatch(t *testing.T) {
    var _ ChunkBatchProcessor = (*MyProcessor)(nil)
}
```

### 9.2 Behavioral test (recommended)

If the package has a fake extractor (`fakeJSONExtractor`) + fake store harness,
write a test that drives `InitChunkBatch → ProcessChunk(×N) → FinalizeChunkBatch`
and asserts the store received the expected accumulated rows.

```go
func TestMyProcessor_BatchProcessChunkAccumulatesAndSaves(t *testing.T) {
    // Build a processor with fake extractor + fake store.
    // InitChunkBatch → ProcessChunk(×2) → FinalizeChunkBatch.
    // Assert store.saved has expected rows with correct IDs.
}
```

### 9.3 Pre-existing failures

The `doc-processing` package has ~23 pre-existing test failures at the current
baseline. Verify your new code introduces **zero** net-new failures:

```bash
go test ./server/api/doc-processing/ 2>&1 | grep "^--- FAIL" | sort > /tmp/head.txt
# Compare against the known baseline. New failures must be 0.
```

## 10. Checklist

- [ ] Processor confirmed chunk-based (reads shared `.chunks` artifact)
- [ ] `canonicalChunkInputText(chunk.Lines, docCtx)` used in every LLM call
- [ ] No task text in `InputText` (schema, labels, chunk-index in prompt only)
- [ ] Struct: batch-state fields (`batchRecordID`, `batchChunks`, `batchDocCtx`, batch accumulator, `batchMu sync.Mutex`, `batchStart`)
- [ ] `InitChunkBatch` — validates prompts/models, resets accumulators, no LLM calls
- [ ] `ProcessChunk` — LLM call + accumulate under `batchMu`; return `nil` on chunk failure, `ErrPipelineStopped` on cancel
- [ ] `FinalizeChunkBatch` — accumulate, stamp IDs, save to DB, write artifact, reindex search
- [ ] 2-pass: shared extraction method called by both `HandleEvent` and batch paths; all side-effects preserved
- [ ] 2-pass: processor added to `multiPassProcessors` in `chunk_batch.go`
- [ ] `"sync"` imported
- [ ] `FinalizeChunkBatch` PromptName/ModelName match the legacy `HandleEvent` save
- [ ] Batch-path save+artifact+index+reindex chain matches legacy `HandleEvent` exactly
- [ ] Registered in `main.go` `NewControlService.Processors` slice
- [ ] Added to `config.toml` `[doc-processing].required_processors` (if configurable)
- [ ] Search indexing: `searchArtifact<Xxx>` + `ReindexXxxSearchForRecord` + `buildXxxRegistryRows` + goose migration
- [ ] Dashboard: stage map, `PIPELINE_FINAL_OPS`, `ALL_PROCESSOR_IDS`, downstream guard
- [ ] Test: `var _ ChunkBatchProcessor = (*MyProcessor)(nil)` compiles
- [ ] Test: behavioral test of `InitChunkBatch → ProcessChunk(×N) → FinalizeChunkBatch` if harness available
- [ ] Test: zero net-new failures vs. the known baseline (~23 pre-existing)
- [ ] `go build ./server/api/doc-processing/ && go vet ./server/api/doc-processing/` clean
- [ ] Spec file: `KnowledgeStore/Capsules/coding-capsules/doc-processor/<name>-spec.md`
- [ ] Impl file: `KnowledgeStore/Capsules/coding-capsules/doc-processor/<name>-impl.md`
- [ ] Capsule "+CAPSULE.md" table + status section updated
