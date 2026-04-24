## Summary
This service chunks a parsed line file into fixed-size chunks and persists chunk artifacts plus chunking metadata.

- Language: Go
- Implementation target: `ChenWeb/server/api/doc-processing/chunking.go`
- Main inputs: `record_id` and `input_file` buffer

## Inputs
- `record_id`: value of `kb.inputs.id`
- `input_filename`: the input file name
- `input_file`: buffer containing the parsed input file content

Input file line format:
- The input file MUST conform to the canonical Line File spec:
  `KnowledgeStore/DevDocuments/Specs/spec-line-file.md`.

## Environment Variables
- CHUNK_SIZE: the chunk size, default:300
- CHUNK_OVERLAP_PERCENT: the overlap percent, default: 20%
- ARTIFACT_DIR: the directory in which chunk files are stored. If not specified, it is an error.

## Retrieve Record
Load the source record from `kb.inputs` where `kb.inputs.id = record_id`.

Error handling:
- If database access fails, report error and stop.
- If record does not exist, report error and stop.

## List Detection Rules
Treat lines with `line_type = list-item` as list candidates, then apply these rules:

- If content starts with `ddd.ddd` (both `ddd` are digit strings), treat it as a section identifier, not as a list item.
- Typical list-item content is: `<list-item-seqno><spaces><content>`.
- `list-item-seqno` may be numeric (`1`, `2`, `3`, ...), or non-numeric symbols (`*`, `-`, `--`, etc.).
- A numeric seqno list item is a **numerical list item**.
- Two or more continuous numerical list items form a **numerical list block**.

## Chunking Rules
- Method: `fix-size`
- Chunk by line boundaries only.
- Chunk target size: `CHUNK_SIZE` bytes (not lines).
- Overlap: `CHUNK_OVERLAP_PERCENT` (line-based overlap ratio).
- Add `<mark>` in front of each emitted line in each chunk:
  - `r`: regular line in this chunk
  - `o`: overlap line carried from previous chunk
  Example:
  - original emitted line: `12 3 paragraph ... [x1,y1,x2,y2]`
  - regular line in chunk: `r 12 3 paragraph ... [x1,y1,x2,y2]`
  - overlap line in chunk: `o 12 3 paragraph ... [x1,y1,x2,y2]`
- Never split `table` blocks.
- Never split `formula` blocks.
- Never split non-numerical list blocks.
- Numerical list blocks are also kept intact by default, but may be split when the block is very large (for example `>= 3 * CHUNK_SIZE`).
- `chunk_seqno` starts at 1 and increments by 1.

## Output Chunk Files
For each chunk, write one chunk file:

- Path pattern: `ARTIFACT_DIR/<group_id>/<record_id>/chunk_dddd`
- `group_id = floor(record_id / 1000)`
- `dddd` is 4-digit, zero-padded `chunk_seqno`

Example:
- `record_id = 7523` => `group_id = 7`
- first chunk file: `.../7/7523/chunk_0001`

## Table `kb.chunks`
This table stores one chunking run summary record.

Fields:
- `id`: auto-generated integer
- `source_record_id`: source `record_id`
- `chunking_method`: string
- `chunking_size`: integer
- `overlap_percent`: integer
- `notes`: text
- `create_time`: timestamp
- `update_time`: timestamp

Write behavior:
- Insert one record per chunking run with:
  - `chunking_method = 'fix-size'`
  - `chunking_size = CHUNK_SIZE`
  - `overlap_percent = CHUNK_OVERLAP_PERCENT`

## Update `kb.inputs.status`
Upsert operation status JSON with `operation = "chunked"`.

Payload schema:

```json
{
  "operation": "chunked",
  "input_filename": "abc",
  "num_pages": 59,
  "num_lines": 267,
  "num_chunks": 25,
  "ms_used": 245,
  "start_time": "20260414 10:04:48",
  "proc_status": "success or failed",
  "error": ""
}
```

Notes:
- `error` is present only when `proc_status = "failed"`.
- Prefer snake_case keys (for example `ms_used`, `proc_status`) for consistency.

## Workflow
1. Retrieve source record from `kb.inputs`.
2. Validate and parse the input line buffer.
3. Detect list structures using the list rules above.
4. Build fixed-size chunks with overlap while respecting no-split constraints.
5. Write chunk files to `ARTIFACT_DIR/<group_id>/<record_id>/chunk_dddd`.
6. Insert a chunking summary record into `kb.chunks`.
7. Upsert `kb.inputs.status` with `operation = "chunked"` and runtime stats.

## Failure Semantics
If any step fails:
- stop processing,
- upsert `kb.inputs.status` with `proc_status = "failed"` and a non-empty `error`,
- do not mark operation as successful.
