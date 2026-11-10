# Module: Compact Document Lines

**Module ID:** `20261110-01`
**Type:** backend · **Language:** go · **Version:** 1.0.0
**Status:** active — used by the artifact reviewers (`metrics`, `provisions`, `inventory_items`, `metrics_completeness`)
**Project:** ChenWeb (server)
**Location:** `ChenWeb/server/api/doc-processing`
**Created:** 2026-11-10
**Devdocs:** None

## 1. What it is

Two helpers for putting document text into an LLM call cheaply:

- **`RenderLinesCompact`** turns document lines into plain text, one text line per document
  line: `[43] 分类投放要定时…`. A short tag after the line number marks the line types a
  reader needs to see (`[36 h1]` heading, `[121 table]`, `[119 caption]`, `[161 eq]`).
  Lines that hold only an image path are left out. Compared with the per-line JSON wrapper
  (`{"flag":…,"line_number":…,"page_number":…,"line_type":…,"content":…}`) it is about
  60% shorter on a typical standard.
- **`LoadRecordChunks`** returns a record's extraction chunks, the ~2,000-byte units with
  overlap lines that the chunk-based extractors read, from the record's saved `.chunks`
  file, so a later step can show the model exactly the text an artifact was extracted from.

It is not the extractors' input format: the extractors and the per-chunk reviewers still
send `canonicalChunkInputText` / `RawLinesToJSON` JSON, whose byte-identical prefixes their
prompt caching relies on.

## 2. Files

| File | Purpose |
|---|---|
| `ChenWeb/server/api/doc-processing/input_lines.go` | `RenderLinesCompact` and its tag rule `compactLineTag` (beside the JSON serializers) |
| `ChenWeb/server/api/doc-processing/render_lines_compact_test.go` | Tests of the format: tags, tables, image lines, newlines, document line |
| `ChenWeb/server/api/doc-processing/review_exports.go` | `LoadRecordChunks` (exported for the `docreviews` package) |

## 3. Interface

```go
// Plain text: optional "Document: <docCtx>" line, then "[<line>] <content>" or
// "[<line> <tag>] <content>" per line.
func RenderLinesCompact(lines []MarkedLine, docCtx string) string

// Saved chunks from $ARTIFACT_DIR/<record/1000>/<record>/<base>.chunks; when no file
// exists, chunks rebuilt with BuildChunks and rebuilt = true.
func LoadRecordChunks(rec DocMetadataInputRecord, lines []Line) (chunks []Chunk, rebuilt bool, err error)
```

Tags: `heading-N` → `hN`, `heading` → `h`, `table`, `table-caption` → `caption`,
`equation` → `eq`; `paragraph`, `list-item` and `text` get none; any other type keeps its
raw name (`footnote`, `title`). Table lines are rendered by `LLMLineContent` as numbered rows
(`121#h0: …`, `121#r1: …`, one per text line); newlines inside any other line become spaces.
Overlap flags and page numbers are not written.

A chunk's `Lines` are its overlap lines (`Mark == "o"`) followed by its regular lines; every
document line is regular in exactly one chunk.

## 4. Configuration

| Key | Default | Meaning |
|---|---|---|
| `ARTIFACT_DIR` | `""` | Directory of the per-record artifact folders that hold the `.chunks` files; empty means rebuild |
| `CHUNK_SIZE` | `300` | Chunk size in bytes for the rebuild fallback (the doc-processor's setting, `2000` locally) |
| `CHUNK_OVERLAP_PERCENT` | `20` | Overlap for the rebuild fallback |

## 5. Usage

From `docreviews` (`review-artifact-window.go`), the source passage of an artifact review
call:

```go
chunks, rebuilt, err := docprocessing.LoadRecordChunks(rec, lines)
if err != nil {
	return nil, err
}
if rebuilt {
	logger.Warn("no saved .chunks file; rebuilt extraction chunks", "record_id", rec.ID)
}
docCtx := docprocessing.BuildDocContextLine(rec)
passage := docprocessing.RenderLinesCompact(chunks[i].Lines, docCtx)
// "Document: 农村生活垃圾分类处理规范 | DB33/T 2030—2018\n[22] GB 14554 …\n[36 h1] 3 术语和定义\n…"
```

Plain lines without overlap marks can be wrapped as `MarkedLine{Line: l}`.

## 6. Behaviour and conventions

- Line numbers are never changed, so a model can cite spans exactly as stored.
- Prompts that receive this format must describe it (see the artifact reviewer prompts,
  e.g. `prompt-review-provisions-v6.md`, Part 1).
- `LoadRecordChunks` reads the same file the doc-processor's per-chunk batching coordinator
  reads, so its chunks match what the extractors saw unless the line file was re-parsed
  after chunking (missing lines are skipped).

## 7. Scope and limits

- Not used by the extractors or the per-chunk reviewers; moving them would change cached
  prefixes and needs their prompts and gold benchmarks re-validated.
- No page numbers: callers that need pages must add them themselves.
- ChenWeb only; move to `shared/` if another project needs it.
