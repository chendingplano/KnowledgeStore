# Blocking Processor — Implementation Notes

**Spec:** `KnowledgeStore/DevDocuments/Specs/spec-blocking.md`  
**Controller spec:** `KnowledgeStore/DevDocuments/Specs/spec-doc-processor.md`  
**Package:** `ChenWeb/server/api/doc-processing`  
**Entry point:** `ChenWeb/server/cmd/doc-processor/main.go`

---

## 1. Files Changed

| File | Change |
|---|---|
| `server/api/doc-processing/blocking-processor.go` | New — types, context helpers, processor |
| `server/api/doc-processing/blocking-processor_test.go` | New — unit tests |
| `server/api/doc-processing/control.go` | `BlockingProcessor Processor` field; `runSingleProcessor` helper; block-buffer context injection |
| `server/api/doc-processing/chunking-processor.go` | Prefers block buffer over file when available |
| `server/api/doc-processing/chunking.go` | `chunkingBlockHandler` interface; `ChunkingController.HandleBlockInput` |
| `server/api/doc-processing/fix-size-chunking.go` | `ParseBlockBufferLines`; `handleChunkLines` extraction; `HandleBlockInput` |
| `server/api/doc-processing/semantic-chunking.go` | `handleSemanticLines` extraction; `HandleBlockInput` |
| `server/cmd/doc-processor/main.go` | Wires `NewBlockingProcessor` into `ControlService` |

---

## 2. Types (`blocking-processor.go`)

```
BlockLine   flag (o/n) + line_number + page_number + line_type + content
Block       index + []BlockLine
BlockBuffer []Block  (in-memory; never written to disk)
```

**Output format per line** (matches spec):
```
<flag>\t<line_number>\t<page_number>\t<line_type>\t<content>
```
`font`, `font_size`, and `coordinate` from the input line file are dropped.

---

## 3. Block-Building Algorithm

Input: sorted unique pages `[p₁ … pN]`, block size `B` (env `INPUT_BLOCK_SIZE`, default 8).

Each block `k` (1-indexed, stride `B`):

| Lines | Flag | Source |
|---|---|---|
| All lines from `pages[start-1]` | `o` | Previous-overlap (omitted for block 1) |
| All lines from `pages[start … start+B-1]` | `n` | Core pages |
| All lines from `pages[start+B]` | `o` | Subsequent-overlap (omitted for last block) |

Malformed input lines (not exactly 7 TAB-separated fields, or non-positive line/page numbers) are silently skipped.

---

## 4. Context-Based Block Buffer Sharing

`ControlService.handleEvent` injects a mutable `blockBufferHolder` into the request context before running any processor:

```
ctx, _ = withBlockBufferHolder(ctx)
```

`BlockingProcessor.HandleEvent` reads the holder from context and stores its result:

```go
if h, ok := ctx.Value(blockBufferCtxKey{}).(*blockBufferHolder); ok {
    h.mu.Lock()
    h.buffer = buf
    h.mu.Unlock()
}
```

Downstream processors retrieve it via the public helper:

```go
buf := BlockBufferFromContext(ctx)  // nil if blocking processor did not run
```

---

## 5. Always-Execute Guarantee

`ControlService` has a dedicated field:

```go
BlockingProcessor Processor  // always runs before Processors
```

In `handleEvent`, the blocking processor runs **before** the operations filter is applied to `Processors`. This means it executes even when the event's `operation` field names only specific downstream processors.

The `ControlService.Processors` slice should **not** include `blocking`; the dedicated field handles it.

---

## 6. Downstream Integration: ChunkingProcessor

`ChunkingProcessor.HandleEvent` checks for a block buffer in context **before** falling back to disk I/O:

```
if buf := BlockBufferFromContext(ctx); buf != nil {
    if bh, ok := p.Service.(chunkingBlockHandler); ok {
        → bh.HandleBlockInput(ctx, recordID, inputFilename, buf)
        return
    }
}
// fall back: read file from disk, call HandleInput([]byte)
```

`chunkingBlockHandler` (defined in `chunking.go`) is satisfied by both `FixedSizeChunkingService` and `SemanticChunkingService`, and is dispatched through `ChunkingController`.

---

## 7. `ParseBlockBufferLines`

Converts a `BlockBuffer` to a `[]Line` for use by the chunking services:

- Iterates blocks in order; collects only `flag == "n"` lines (each page is a normal line in exactly one block, so no duplicates occur under correct blocking).
- Deduplicates by `LineNumber` defensively.
- Sorts by `LineNumber` ascending.
- Leaves `Font`, `FontSize`, `Coordinate` empty — `FixedSizeChunkingService` does not use these fields in its chunking logic (`lineRawForChunking` uses only `LineNo`, `PageNo`, `LineType`, `Content`).
- `SemanticChunkingService.HandleBlockInput` calls `ParseBlockBufferLines` and skips `validateCanonicalLine` (which checks `FontSize`/`Coordinate`), since those fields are not present in block-format lines.

---

## 8. Refactors in Existing Services

To avoid duplicating the post-parse processing logic, two private helpers were extracted:

| Method | Service | Contains |
|---|---|---|
| `handleChunkLines(ctx, rec, filename, start, lines)` | `FixedSizeChunkingService` | BuildChunks → topics → summaries → status |
| `handleSemanticLines(ctx, rec, filename, start, lines)` | `SemanticChunkingService` | BuildSemanticPageBlocks → topics → status |

`HandleInput` (file path) and `HandleBlockInput` (buffer path) both call the same helper after their respective parse step.

---

## 9. Environment Variables

| Variable | Default | Effect |
|---|---|---|
| `INPUT_BLOCK_SIZE` | `8` | Pages per core block; shared with `StructureAnalyzerProcessor` |

---

## 10. Processors That Depend on Block Buffer ("after 1")

Per the doc-processor spec, all processors listed as "after 1" receive the block buffer via context. Current wiring:

| Processor | Uses block buffer? | Fallback |
|---|---|---|
| `chunking` | Yes — `HandleBlockInput` | Reads input file directly |
| `extract_doc_metadata` | Not yet wired | Reads input file directly |
| `extract_metrics` | Not yet wired | Reads input file directly |
| `extract_provisions` | Not yet wired | Reads input file directly |
| `structure_analyzer` | Not yet wired | Reads input file directly |

The block buffer is available in context for all of these; wiring them follows the same pattern as the chunking processor.
