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
```
where:
- `ddd` is an integer (line number), `ddd-ddd` represents a range of continuous lines
   with the starting and ending line numbers.
- `po`: the overlapping lines before the chunk lines
- `cl`: the chunk lines, or the lines contained in the chunk

The first chunk has no `po`.

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
- Skip lines with `line_type = TOC` (case-insensitive); do not include them in any chunk.
- Chunk by line boundaries only.
- Chunk target size: `CHUNK_SIZE` bytes (not lines).
- Overlap: `CHUNK_OVERLAP_PERCENT` (line-based overlap ratio).
- Represent the persisted chunk artifact using line-number ranges:
  - `overlap`: overlap lines carried from the previous chunk
  - `lines`: regular lines in the chunk
- Never split `table` blocks.
- Never split `formula` blocks.
- Never split non-numerical list.
- Numerical list blocks are also kept intact by default, but may be split when the block is very large (for example `>= 3 * CHUNK_SIZE`).
- `chunk_seqno` starts at 1 and increments by 1.

### 5.2. List Detection Rules
There are currently four types of lists:
- `list-item`: general
- `list-item-num`: numerical lists, such as "1. xxx\n 2. xxx"
- `list-item-s-sym`: single-symbal lists, such as "a. xxx\n b. xxx"
- `list-item-m-sym`: multiple-symbal lists, such as "case 1: xxx\n case 2: xxx"

Refer to `ChenWeb/server/api/doc-processing/structure-static-analyzer.go`.

Treat lines whose `line_type` starts with 'list-item' as list candidates. Continuous lines with exactly
the same list type form a list. Below is an example:
```text
120 6 paragraph Health check items include:
121 6 list-item-s-sym a) Heart rate
122 6 list-item-s-sym b) Blood pressure
125 6 list-item-s-sym c) Weight
126 6 list-item-s-sym d) Height
Make sure all checked items meet the requirements.
```
In the above example, Lines 121-122, 125-126 form a list.
IMPORTANT: line numbers may not be continous. In the above example, it misses Line 123 and 124.
These lines are most likely removed (refer to Capsules/doc-structure-analyzer-static/+CAPSULE.md)

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

Consumer parsing requirements:

- Readers of `.chunks` MUST treat only explicit `lines:` rows as chunk payload.
- `overlap:` rows are metadata and MUST NOT be treated as chunk content.
- Blank separator lines between chunk entries are allowed and MUST be ignored.
- Consumers MUST preserve the order of `lines:` rows as the canonical chunk order.

UI expectation for `ChenWeb::/home3/knowledge -> Chunks`:

- The `Chunks` page MUST display only entries parsed from `.chunks`.
- It MUST NOT enrich, replace, or fall back to `.topics` or `topics.txt`.
- Topic extraction artifacts belong to `Semantic Web`, not to the `Chunks` list.
- When the UI shows source-line coverage for a chunk, continuous lines on the same page should be compressed into page-aware ranges such as `P8:183-192`.

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
      "categories": [
        {
          "category_path": [
            {
              "name": "public_health",
              "keywords": ["health management", "disease prevention", "public health"],
              "confidence": 0.95
            },
            {
              "name": "vaccination",
              "keywords": ["vaccination", "immunization", "vaccine administration"],
              "confidence": 0.94
            },
            {
              "name": "record_management",
              "keywords": ["vaccination records", "recipient data", "immunization information system"],
              "confidence": 0.92
            }
          ],
          "path_keywords": ["vaccination records", "recipient data", "information system"],
          "path_confidence": 0.92
        },
        ...
      ]
    },
    {
      next-topic
    },
    ...
  ]
}
```

### 6.3 Topic File
Topics are stored in topic files. Topic file name is:
  `ARTIFACT_DIR/<group_id>/<record_id>/<topic_file_name>`
where `<topic_file_name>` is:
```text
the root of 'kb.inputs.staging_filename' + "_" + 'kb.inputs.parser_name' + ".topics"
```

Topic file format is:
```text
topic_id: ddd,
topic_type: "topic-type"
lines: [ddd, ddd-ddd, ...]
topic_keywords: ["keyword", ...]
topic: "topic"
category_paths: [(<path_keywords>, <path_confidence>, [<category_name>, <keywords>, <confidence>]), ...]

<next-topic>
...
```

### 6.4 Embed Topics
* Use TOPIC_EMBEDDING_MODEL_NAME to embed topics.
* Save topic embeddings in the file:
  `ARTIFACT_DIR/<group_id>/<record_id>/embeddings/topic_<topic_id>.embed`

### 6.5 Topic Indexing
A topic has one or more category paths. A category path is made of one or more categories.
Category paths are stored as file directories under TOPIC_TREE_ROOT_DIR, where each
category maps to a sub-directory. For instance, if a category path is 
"medical_standards/surgical_conditions", there will be two directories:
```text
TOPIC_TREE_ROOT_DIR/medical_standards
TOPIC_TREE_ROOT_DIR/medical_standards/surgical_conditions
```

#### 6.5.1 Topic 'metadata.txt' File
Each directory under TOPIC_TREE_ROOT_DIR has a 'metadata.txt' file. The file format is:
```text
"desc":"category description"
"confidence":0.95
"keywords":["keyword",...]
"create_time":"yyyymmdd-hhmmss"
```

#### 6.5.2 Category Embedding
It embeds a category and save the vector in the file 'category.embed'

#### 6.5.3 'topics.txt' File
This file saves all the topics whose category matches the directory's category.
Its file format is:
```text
record_id: ddd,
topic_type: "topic-type"
lines: [ddd, ddd-ddd, ...]
topic_keywords: ["keyword", ...]
topic: "topic"

<next-topic>
...
```

Topics in 'topics.txt' are sorted by record IDs.

#### 6.5.4 Workflow
* For each category path: `category_path`
  * Set TOPIC_TREE_ROOT_DIR as its current directory
  * For the i-th category in `category_path`:
    * Find the sub-directory by the category name. If no sub-directory with the category
      name is found, find the closest sub-directories in the current directory by 
      calculating the cosine of their vectors as the similarity score. If the similarity
      score (score is between 0.0 and 1.0, the bigger, the closer) is no less than
      CATEGORY_SIMILARITY_MIN_SCORE, the current category is considered 'the same' as 
      the i-th category in `category_path`.
    * If the above step found the sub-directory, set it as the current directory. 
      Merge the category's keywords with the one in the 'metadata.txt'.
      Move on to the next category, if any.
    * Otherwise, this is a new category in the current directory. Create the sub-directory
      and the metadata file for the sub-directory, embed the topic and save it to the embed file. Then move on to the next category, if any.
    * If it is the last category in `category_path`, upsert the topic to the 'topic.txt' file.
      If the file does not exist yet, create it.

## 7. Summaries
* Refer to 'spec-generate-chunk-summary.md' for generating summaries.
* Generate category paths for **every** summary (both leaf and group summaries),
  not just the root. Each summary gets its own category path from the LLM.
* Refer to 'spec-category-extraction.md' for how to extract category paths and
  save summaries in the Summary File Tree.

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
9. Generate a category path for each summary (leaf and group) via LLM, then update the Summary File Tree with each summary's own category path.
10. Insert a chunking summary record into `kb.chunks`.
10. Upsert `kb.inputs.status` with `operation = "chunked"` and runtime stats.

## 11. Failure Semantics
If any step fails:
- stop processing,
- upsert `kb.inputs.status` with `proc_status = "failed"` and a non-empty `error`,
- do not mark operation as successful.
