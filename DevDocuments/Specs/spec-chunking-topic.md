## Goals
This Go program uses an LLM to extract topics and chunk an input file into chunks based on topics and persists chunk artifacts plus chunking metadata.

- Language: Go
- Implementation target: `ChenWeb/server/api/doc-processing/semantic-chunking.go`
- Main inputs: `record_id` and `input_file` buffer

## Inputs
- `record_id`: value of `kb.inputs.id`
- `input_filename`: the input file name
- `input_file`: buffer containing the parsed input file content

Input file line format:
- The input file MUST conform to the canonical Line File spec:
  `KnowledgeStore/DevDocuments/Specs/spec-line-file.md`.

## Environment Variables
- INPUT_BLOCK_SIZE: the block size (see below) in number of pages
- TOPIC_CHUNK_MODEL_NAME: the name of LLM to use to chunk the input file (refer to /Users/cding/Workspace/KnowledgeStore/DevDocuments/Specs/spec-model-def.md for how to specify LLM models)
- ARTIFACT_DIR: the directory in which chunk files are stored. If not specified, it is an error.
- TOPIC_CHUNK_PROMPT: the file name of the prompt to use, which can be an absolute path or relative to 'PROMPT_DIR'.
- SEMANTIC_CHUNKING_PROMPT: if 'TOPIC_CHUNK_PROMPT' is not specified or empty, use this one. If none of these
  is specified, it will use the hard-coded prompt, which is defined in 'server/api/doc-processing/semantic-chunking.go', var name = 'defaultTopicChunkPrompt'.

## Retrieve Record
Load the source record from `kb.inputs` where `kb.inputs.id = record_id`.

Error handling:
- If database access fails, report error and stop.
- If record does not exist, report error and stop.

## Extract Topics

- Break the input file into blocks. Each block contains 1 overlap page (except the first block) and FILE_BLOCK_SIZE content pages
- Skip lines with `line_type = TOC` (case-insensitive); do not pass them to the LLM or include them in any chunk.
- Use the LLM to recognize and extract all the topics from each block.
- Treat the cover page, if any, as one topic
- For tables, write a description about a table as its topic. The topic type is 'table'.
- For formulas, write a description based on the context as its topic. The topic type is 'formula'
- For item lists, write a description based on the list as its topic. The topic type is 'list'
- The above are only a few known types of topics. There can be more content types (or topic types), such as workflows, policies, rules, etc.
- Generate keywords for each topic

## Output

A topic is defined as `<seqno> <topic_type> <lines> <keywords> <topic>`
where:
- `<seqno>` is a sequence number, starting from 1
- `<topic_type>` is the type of a topic.
- `<lines>` is the line numbers from which a topic is derived, stored as an array of single line numbers or ranges of lines, such as '[38-45, 47, 49, 55-62]'
- `<keywords>`: an array of keywords in the form '[xxx, xxx, ...]'

Save all the topics in a file. The file name is:
    ARTIFACT_DIR + '/<group_id>/<record_id>/topics.txt',
where:
- '<group_id>' is the integral part of record_id / 1000

## Table `kb.chunks`
This table stores one chunking run summary record.

Fields:
- `id`: auto-generated integer
- `source_record_id`: source `record_id`
- `chunking_method`: string
- `chunking_size`: integer
- `overlap_percent`: integer
- `num_chunks`: integer
- `notes`: text
- `create_time`: timestamp
- `update_time`: timestamp

Write behavior:
- Insert one record per chunking run with:
  - `chunking_method = 'topic-chunking'`

## Update `kb.inputs.status`
Upsert operation status JSON with `operation = "chunked"`.

Payload schema:

```json
{
  "operation": "topic_chunk",
  "input_filename": "...",
  "num_pages": ...,
  "num_lines": ...,
  "num_chunks": ...,
  "ms_used": ...,
  "start_time": "...",
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
4. Generate topics
5. Write topics to chunk files.
6. Insert a chunking summary record into `kb.chunks`.
7. Upsert `kb.inputs.status` with `operation = "topic_chunk"` and runtime stats.

## Failure Semantics
If any step fails:
- stop processing,
- upsert `kb.inputs.status` with `proc_status = "failed"` and a non-empty `error`,
- do not mark operation as successful.
