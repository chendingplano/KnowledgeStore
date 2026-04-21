## Summary
This Go program uses an LLM to extract topics and chunk an input file into chunks based on topics and persists chunk artifacts plus chunking metadata.

- Language: Go
- Implementation target: `aas/server/api/doc-processing/semantic-chunking.go`
- Main inputs: `record_id` and `input_file` buffer

## Inputs
- `record_id`: value of `kb.inputs.id`
- `input_filename`: the input file name
- `input_file`: buffer containing the parsed input file content

Input file line format:

```text
<line_number> <page_number> <line_type> <content> <coordinate>
```

Field definitions:
- `<line_number>`: integer, starts from 1
- `<page_number>`: integer
- `<line_type>`: line category such as `heading`, `paragraph`, `list-item`, `table`, `formula`
- `<content>`: textual content
- `<coordinate>`: `[x1, y1, x2, y2]`

## Environment Variables
- CHUNK_BLOCK_SIZE: the block size (see below) in number of pages
- CHUNK_LLM_NAME: the name of LLM to use to chunk the input file
- CHUNK_LLM_API_KEY: the LLM's API Key
- CHUNK_OVERLAP_PERCENT: the overlap percent, default: 20%
- CHUNK_LLM_BASE_URL: the LLM's base URL
- CHUNK_LLM_TIMEOUT_SEC: the timeout in second for the LLM
- CHUNK_DIR: the directory in which chunk files are stored. If not specified, it is an error.

## Retrieve Record
Load the source record from `kb.inputs` where `kb.inputs.id = record_id`.

Error handling:
- If database access fails, report error and stop.
- If record does not exist, report error and stop.

## Extract Topics

- Break the input file into blocks. Each block contains 1 overlap page (except the first block) and CHUNK_BLOCK_SIZE content pages
- Use the LLM to recognize and extract all the topics from each block. 
- Ignore the Table of Contents, if any.
- Treat the cover page, if any, as one topic
- For tables, write a description about a table as its topic. The topic type is 'table'.
- For formulas, write a description based on the context as its topic. The topic type is 'formula'
- For item lists, write a description based on the list as its topic. The topic type is 'list'
- The above are only a few known types of topics. There can be more content types (or topic types), such as workflows, policies, rules, etc.

## Output

A topic is defined as `<seqno> <topic_type> <lines> <topic>`
where:
- `<seqno>` is a sequence number, starting from 1
- `<topic_type>` is the type of a topic.
- `<lines>` is the line numbers from which a topic is derived, stored as an array of single line numbers or ranges of lines, such as '[38-45, 47, 49, 55-62]'

Save all the topics in a file. The file name is:
    CHUNK_DIR + '/<group_id>/<record_id>/topics.txt',
where:
- '<group_id>' is the integral part of 

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
5. Write chunk files to `CHUNK_DIR/<group_id>/<record_id>/chunk_dddd`.
6. Insert a chunking summary record into `kb.chunks`.
7. Upsert `kb.inputs.status` with `operation = "chunked"` and runtime stats.

## Failure Semantics
If any step fails:
- stop processing,
- upsert `kb.inputs.status` with `proc_status = "failed"` and a non-empty `error`,
- do not mark operation as successful.
