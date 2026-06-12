# ADR: Change `kb.chunks` Schema
- DocID: `doc-2026061107`
- **Status:** Accepted
- **Date:** 2026-06-11
- **Deciders:** Chen Ding
- **Tags:** table schema change, kb.chunks

## Change Logs
- Created by Chen Ding on 2026/06/11
- Implemented by Chen Ding on 2026/06/11

# Context
Currently, the table `kb.chunks` schema is:
```sql
	id bigserial NOT NULL,
	source_record_id int8 NOT NULL,
	chunking_method varchar(64) DEFAULT 'fix-size'::character varying NOT NULL,
	chunking_size int4 DEFAULT 300 NOT NULL,
	overlap_percent int4 DEFAULT 20 NOT NULL,
	notes text DEFAULT ''::text NOT NULL,
	create_time timestamptz DEFAULT now() NOT NULL,
	update_time timestamptz DEFAULT now() NOT NULL,
```

# Decision
Add the following fields:
- overlap_lines: "12-15" (text)
- normal_lines: "16-30" (text)
- chunk_lines: the actual lines (text)

## Implementation

### Database Migration
- **Migration file:** `ChenWeb/project_migrations/20260611190000_add_chunk_line_columns_to_kb_chunks.sql`
- Adds three TEXT columns (`overlap_lines`, `normal_lines`, `chunk_lines`) to `kb.chunks` using `ALTER TABLE ... ADD COLUMN IF NOT EXISTS`
- All columns default to empty string (`''`)

### Code Changes
Files changed in `ChenWeb/server/api/doc-processing/`:

1. **`fix-size-chunking.go`** — `ChunkRunRecord` struct updated with three new `string` fields: `OverlapLines`, `NormalLines`, `ChunkLines`

2. **`store.go`** — `InsertChunkRun` SQL INSERT now includes `overlap_lines`, `normal_lines`, `chunk_lines` columns (params $6–$8)

3. **`topic_chunking_shared.go`** — Added `buildChunkLineInfo(chunks []Chunk)` helper that computes overlap/normal line ranges and raw chunk text from `[]Chunk` as JSON arrays. Uses existing `chunkLineNumbers()` and `formatLineNumberRanges()`.

4. **`semantic-chunking.go`** — Added `buildBlockLineInfo(blocks []SemanticPageBlock)` helper for topic-chunking blocks. Overlap_lines is always `"[]"` since semantic chunking has no overlap markers.

5. **Call sites updated:**
   - `fix-size-chunking.go` `handleChunkLines()`: calls `buildChunkLineInfo(chunks)` before `InsertChunkRun`
   - `semantic-chunking.go` `handleSemanticLines()`: calls `buildBlockLineInfo(blocks)` before `InsertChunkRun`

### Data Format
Each field stores a JSON array with one entry per chunk:
- `overlap_lines`: `["[12-15]","[87-90]"]`
- `normal_lines`: `["[16-30]","[91-105]"]`
- `chunk_lines`: `["line text content\nof chunk 1","line text content\nof chunk 2"]`

For semantic (topic) chunking, `overlap_lines` is always `"[]"`.

## Operational Behavior
- New columns are populated automatically on every chunking run (both fixed-size and semantic)
- Existing rows retain the default empty string values
- No breaking changes — new fields are additive only
- Downstream consumers (e.g., `ListChunks` handler) can optionally read these fields to serve chunk line metadata without parsing artifact files

## Consequences
The corresponding code in doc processing (refer to [1]) has been changed to populate the new fields.

### Positive
- Chunk line-level metadata (overlap vs. normal line ranges, raw text) is now queryable directly from the database
- Enables future features like chunk-level search, overlap-aware deduplication, and direct chunk text retrieval without artifact file parsing
- JSON encoding ensures clean programmatic consumption

### Trade-offs
- Increased row size per `kb.chunks` record (proportional to number of chunks and text size)
- `chunk_lines` duplicates data that also exists in `.chunks` artifact files on disk
- `chunk_lines` JSON encoding may need escaping consideration for very large chunks with special characters

## Verification
- All existing chunking tests pass (fixed-size: `TestBuildChunks_*`, `TestFixedSizeChunkingService_*`; semantic: `TestSemanticChunkingService_*`)
- Migration tested: `goose up` adds columns idempotently (`IF NOT EXISTS`), `goose down` removes them in reverse order
- Compilation verified via `go build ./api/doc-processing/`

## Documentation Impact
[1] updated with `kb.chunks` table schema including the three new columns (see section 9.2 Chunking).

# References
[1] KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md