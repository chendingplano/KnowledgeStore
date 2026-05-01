## 1. Overview
This service chunks a parsed line file into fixed-size chunks and persists chunk artifacts plus chunking metadata.

- Language: Go
- Implementation target:
  - `ChenWeb/server/api/doc-processing/fix-size-chunking.go`
  - `ChenWeb/server/api/doc-processing/topic_chunking_shared.go`
- Main inputs: `record_id` and `input_file` buffer

## 2. Inputs
- `record_id`: value of `kb.inputs.id`
- `input_filename`: the input file name
- `input_file`: buffer containing the parsed input file content

Input file line format:
- The input file MUST conform to the canonical Line File spec:
  `KnowledgeStore/DevDocuments/Specs/spec-line-file.md`.

## 3. Environment Variables
- CHUNK_SIZE: optional, the chunk size, default:300
- CHUNK_OVERLAP_PERCENT: optional, the overlap percent, default: 20%
- ARTIFACT_DIR: required, the directory in which chunk files are stored.
- CHUNK_TREE_ROOT_DIR: required, the root dir of the chunk file tree.
- CHUNK_EXTRACT_TOPIC_MODEL_NAME: optional, the name of the model to extract topics and to generate summary tree categories, default to 'gpt-5-4-mini'
- CHUNK_EXTRACT_TOPIC_PROMPT: required, the prompt for extracting topics from the chunk.
- GENERATE_CATEGORY_PROMPT: optional, the prompt used to infer the summary tree category path via LLM. If not defined, an error is logged at startup and a built-in default prompt is used as fallback. The prompt receives the root summary text as input and must instruct the LLM to return a JSON object `{"category_path": [...]}` with 1–2 snake_case labels.

## 4. Retrieve Record
Load the source record from `kb.inputs` where `kb.inputs.id = record_id`.

Error handling:
- If database access fails, report error and stop.
- If record does not exist, report error and stop.

## 5. Chunking
A chunk is defined in memory by three line groups:
```text
po:[ddd, ddd-ddd, ...]
cl: [ddd, ddd-ddd, ...]
pn: [ddd, ddd-ddd, ...]
```
where:
- `ddd` is an integer (line number), `ddd-ddd` represents a range of continuous lines
   with the starting and ending line numbers.
- `po`: the overlapping lines before the chunk lines
- `cl`: the chunk lines, or the lines contained in the chunk
- `pn`: the overlapping lines next to the chunk lines

The first chunk has no `po`, the last chunk has no `pn`.

In the persisted `.chunks` artifact, each chunk is written as a two-line summary:
```text
overlap: [ddd, ddd-ddd, ...]
lines: [ddd, ddd-ddd, ...]
```
where:
- `overlap` lists the carried overlap line numbers (`po`)
- `lines` lists the regular line numbers contained in the chunk (`cl`)

The current implementation does not persist the raw line bodies inside the `.chunks` file. Consumers that need the original lines resolve them from the source canonical line file by these line numbers.

### 5.1. Chunking Rules
- Method: `fix-size`
- Skip lines with `line_type = TOC` (case-insensitive); do not include them in any chunk.
- Chunk by line boundaries only.
- Chunk target size: `CHUNK_SIZE` bytes (not lines).
- Overlap: `CHUNK_OVERLAP_PERCENT` (line-based overlap ratio).
- Represent the persisted chunk artifact using line-number ranges:
  - `overlap`: overlap lines carried from the previous chunk
  - `lines`: regular lines in the chunk
- Never split `table` blocks.
- Never split `formula` blocks.
- Never split non-numerical list blocks.
- Numerical list blocks are also kept intact by default, but may be split when the block is very large (for example `>= 3 * CHUNK_SIZE`).
- `chunk_seqno` starts at 1 and increments by 1.

### 5.2. List Detection Rules
Treat lines with `line_type = list-item` as list candidates, then apply these rules:

- If content starts with `ddd.ddd` (both `ddd` are digit strings), treat it as a section identifier, not as a list item.
- Typical list-item content is: `<list-item-seqno><spaces><content>`.
- `list-item-seqno` may be numeric (`1`, `2`, `3`, ...), or non-numeric symbols (`*`, `-`, `--`, etc.).
- A numeric seqno list item is a **numerical list item**.
- Two or more continuous numerical list items form a **numerical list block**.

### 5.3 Chunk Files
Chunk file name = `ARTIFACT_DIR/<group_id>/<record_id>/<chunk_file_name>`
where:
- `group_id = floor(record_id / 1000)`
- `<chunk_file_name>` is:
```text
   the root of 'kb.inputs.staging_filename' + "_" + 'kb.inputs.parser_name' + ".chunks"
```

Chunk file content format:
```text
overlap: [ddd, ddd-ddd, ...]
lines: [ddd, ddd-ddd, ...]
```
repeated once per chunk in chunk sequence order.

## 6. Topics

### 6.1 Extract Topics
- Use the model defined by CHUNK_EXTRACT_TOPIC_MODEL_NAME and the prompt CHUNK_EXTRACT_TOPIC_PROMPT to extract topics from each chunk.
- The LLM returns the topics in JSON (see the JSON format below)

LLM Output JSON format:
```json
{
"topics": [
    {
      "topic_id":<seqno>,
      "topic_type": "string",
      "lines": ["38-45", "47"],
      "topic_keywords": ["k1", "k2"],
      "topic": "topic description",
      "categories": <refer to 'Extract Topic Category Paths' section>
    },
    {
      next-topic
    },
    ...
  ]
}
```

### 6.2 Extract Topic Category Paths

It extracts category paths for all the topics. Refer to 'spec-category-extraction.md' for how to 
extract category paths and its output format.

### 6.3 Topic File
Topic file name = `ARTIFACT_DIR/<group_id>/<record_id>/<topic_file_name>`
where `<topic_file_name>` is:
```text
the root of 'kb.inputs.staging_filename' + "_" + 'kb.inputs.parser_name' + ".topics"
```

Topic file format is:
```text
topic_id: 32
topic_type:	"requirement"
lines: [104-108]
topic_keywords:	[血压, 心率, 呼吸系统, 神经系统, 代谢疾病]
topic: "消防员体格检查中内科部分的要求，包括血压、心率、呼吸循环等系统正常，无代谢及结缔组织疾病。"
category_paths: [(<path_keywords>, <path_confidence>, [<category_name>, <keywords>, <confidence>]), ...]

<next_topic>
...
```

### 6.4 Embed Topics
* Use TOPIC_EMBEDDING_MODEL_NAME to embed topics.
* Save topic embeddings in the file:
  `ARTIFACT_DIR/<group_id>/<record_id>/<embed_file_name>`
where `<embed_file_name>` is:
```text
the root of 'kb.inputs.staging_filename' + "_" + 'kb.inputs.parser_name' + ".embed"
```

## 7. Summaries
* Refer to 'spec-generate-chunk-summary.md' for generating summaries.
* Refer to 'spec-category-extraction' for how to extract category paths and
  save summaries in the Summary File Tree.

## 7.1 Embed Summaries
* Use SUMMARY_EMBEDDING_MODEL_NAME to embed summaries.

## 8. Table `kb.chunks`
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

## 9. Update `kb.inputs.status`
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

## 10. Workflow
1. Retrieve source record from `kb.inputs`.
2. Validate and parse the input line buffer.
3. Detect list structures using the list rules above.
4. Build fixed-size chunks with overlap while respecting no-split constraints.
5. Extract topics from each chunk.
6. Write the chunk summary file to `ARTIFACT_DIR/<group_id>/<record_id>/<chunk_file_name>`, where `<chunk_file_name>` is `the root of 'kb.inputs.staging_filename' + "_" + 'kb.inputs.parser_name' + ".chunks"`.
7. Write the topic file to `ARTIFACT_DIR/<group_id>/<record_id>/<topic_file_name>`, where `<topic_file_name>` is similar to 
   `<chunk_file_name>` except that it uses the '.topics' file extention.
8. Update the Topic File Tree.
9. Update the Summary File Tree.
10. Insert a chunking summary record into `kb.chunks`.
10. Upsert `kb.inputs.status` with `operation = "chunked"` and runtime stats.

## 11. Failure Semantics
If any step fails:
- stop processing,
- upsert `kb.inputs.status` with `proc_status = "failed"` and a non-empty `error`,
- do not mark operation as successful.
