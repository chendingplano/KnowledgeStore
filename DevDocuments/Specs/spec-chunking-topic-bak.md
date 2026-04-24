## Semantic Topic Chunking Spec

### 1. Goal
Implement semantic topic chunking in Go at:

- `ChenWeb/server/api/doc-processing/semantic-chunking.go`

The program:
1. reads parsed document lines,
2. extracts semantic topics using an LLM,
3. generates chunk artifacts from topics,
4. persists artifacts and run metadata.

### 2. Inputs

- `record_id` (required): `kb.inputs.id` (integer, > 0)
- `input_filename` (required): original file name
- `input_file` (required): text buffer; one logical line per document line

#### 2.1 Input line format

Each input line MUST conform to the canonical Line File spec:
`KnowledgeStore/DevDocuments/Specs/spec-line-file.md`.

Additional constraints for this processor:
- `line_number` MUST be strictly increasing.
- If any line is malformed, stop processing and mark failed.

### 3. Environment Variables

- `FILE_BLOCK_SIZE` (required): integer >= 1; number of content pages per block.
- `TOPIC_CHUNK_MODEL_NAME` (required): LLM model name (see `spec-model-def.md`).
- `ARTIFACT_DIR` (required): root directory for artifact output.

Validation:
- Missing/invalid env var => fail before processing input.

### 4. Retrieve Source Record

Load row from `kb.inputs` where `id = record_id`.

Failure:
- DB access error => fail.
- Record not found => fail.

### 5. Block Construction

Let pages be `1..N` where `N` is max page number in input.

Create blocks:
- Block 1: pages `[1 .. min(FILE_BLOCK_SIZE, N)]`
- Block k (k > 1):
  - start page = previous block end page
  - end page = `min(start + FILE_BLOCK_SIZE, N)`
  - This yields exactly 1-page overlap between adjacent blocks.

Stop when end page = N.

Examples:
- `N=3, FILE_BLOCK_SIZE=5` => one block `[1..3]`
- `N=10, FILE_BLOCK_SIZE=4` => `[1..4], [4..8], [8..10]`

### 6. Topic Extraction Rules

For each block, call LLM and extract all topics.

Rules:
1. Ignore Table of Contents lines (`line_type == "toc"`).  
   If `line_type` does not include `toc`, no heuristic TOC detection is required.
2. If page 1 exists and contains non-TOC content, create a single `cover` topic from cover lines.
3. Topic typing:
   - table-derived => `table`
   - formula-derived => `formula`
   - list-derived => `list`
   - otherwise free-form type string (e.g., `workflow`, `policy`, `rule`, `section`)
4. Generate keywords per topic (0..10 keywords).
5. A topic must reference at least one line number.

### 7. Overlap Deduplication

Because blocks overlap by 1 page, deduplicate extracted topics globally.

Two topics are duplicates if all are true:
- same normalized `topic_type` (case-insensitive),
- same normalized `topic` text (trim + collapse spaces + lowercase),
- identical sorted set of `line_numbers`.

Keep first occurrence by extraction order.

### 8. Output Artifacts

Output directory:

- `run_dir = ARTIFACT_DIR + "/" + floor(record_id/1000) + "/" + record_id`

Create directories if missing.

Overwrite policy:
- Always overwrite `topics.jsonl` and `chunks.jsonl` for this run.

#### 8.1 topics.jsonl

File: `run_dir/topics.jsonl`

One JSON object per topic:

```json
{
  "seqno": 1,
  "topic_type": "table",
  "line_numbers": [38,39,40,41,42,43,44,45,47,49,55,56,57,58,59,60,61,62],
  "keywords": ["load", "stress", "safety-factor"],
  "topic": "Allowable stress values by material class"
}
```

Constraints:
- `seqno`: starts at 1, continuous.
- `line_numbers`: sorted unique integers.
- `topic`: non-empty string.

#### 8.2 chunks.jsonl

File: `run_dir/chunks.jsonl`

One chunk per topic (practical 1:1 mapping):

```json
{
  "chunk_seqno": 1,
  "topic_seqno": 1,
  "topic_type": "table",
  "page_start": 3,
  "page_end": 4,
  "line_numbers": [38,39,40],
  "chunk_text": "..."
}
```

`chunk_text` is concatenation of referenced input lines in ascending `line_number`, separated by `\n`.

### 9. Database: `kb.chunks`

Insert one summary row per run:

- `source_record_id = record_id`
- `chunking_method = "topic-chunking"`
- `chunking_size = FILE_BLOCK_SIZE`
- `overlap_percent = 25` (fixed because overlap is 1 page; if block has fewer pages, still store 25)
- `num_chunks = number of rows in chunks.jsonl`
- `notes = "model=<TOPIC_CHUNK_MODEL_NAME>; topics_file=topics.jsonl; chunks_file=chunks.jsonl"`
- `create_time`, `update_time`: DB defaults/current timestamp

If insert fails, run fails.

### 10. Update `kb.inputs.status`

Use upsert with operation key:

- `operation = "topic_chunk"` (canonical value)

Payload schema:

```json
{
  "operation": "topic_chunk",
  "input_filename": "...",
  "num_pages": 0,
  "num_lines": 0,
  "num_chunks": 0,
  "ms_used": 0,
  "start_time": "RFC3339",
  "proc_status": "success|failed",
  "error": "only present when failed"
}
```

Rules:
- `error` must be omitted on success.
- All keys use snake_case.
- `ms_used` is end-to-end wall-clock milliseconds.

### 11. Workflow

1. Validate env vars.
2. Set `start_time`.
3. Retrieve `kb.inputs` row by `record_id`.
4. Parse and validate `input_file`.
5. Build page blocks.
6. Extract topics per block via LLM.
7. Deduplicate topics.
8. Build chunks (1:1 from topics).
9. Write `topics.jsonl` and `chunks.jsonl`.
10. Insert summary row into `kb.chunks`.
11. Upsert `kb.inputs.status` with `proc_status="success"`.

### 12. Failure Semantics

On any failure at any step:
1. Stop processing immediately.
2. Upsert `kb.inputs.status` with:
   - `operation="topic_chunk"`
   - `proc_status="failed"`
   - non-empty `error`
3. Do not write success status.
4. Partial files may exist; they are replaced on next run.

### 13. Edge Case Requirements

- Empty input or no valid lines => fail.
- Single-page docs => one block, overlap not applied.
- All lines filtered as TOC => success with zero topics/chunks.
- Unknown `line_type` => allowed; classify by LLM/topic text.
- Duplicate line numbers or non-increasing line sequence => fail.
