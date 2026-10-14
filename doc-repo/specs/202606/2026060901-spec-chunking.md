## 1. Overview
The `chunking` processor builds fixed-size chunks from parsed line records and persists the `.chunks` artifact, a chunk-run record, and `kb.inputs.status`. Topic extraction and summary generation are separate processor operations that consume those chunks. The shared service implementation is in `ChenWeb/server/api/doc-processing/fix-size-chunking.go`; chunk/topic artifact helpers are in `topic_chunking_shared.go` and summary helpers are in `chunk_summary_shared.go`.

- Language: Go
- Implementation target:
  - `ChenWeb/server/api/doc-processing/fix-size-chunking.go`
  - `ChenWeb/server/api/doc-processing/topic_chunking_shared.go`
  - `ChenWeb/server/api/doc-processing/chunking-processor.go`
- Inputs: `record_id`, input filename, and either canonical line-file bytes or a `BlockBuffer` from the blocking processor. The event processor prefers the block buffer when present.

## 2. Inputs
- `record_id`: value of `kb.inputs.id`
- `input_filename`: the input file name
- `input_file`: buffer containing the parsed input file content

Input file line format:
- The input file MUST conform to the canonical Line File spec:
  `KnowledgeStore/Capsules/coding-capsules/input-management/spec-line-file.md`.

Pipeline ordering requirement:
- Finalize the canonical line file before chunking so persisted line numbers match the lines downstream consumers read.
- When the line file comes from the PDF converter, run the static analyzer first; corrections/removals can change line numbering.
- The event pipeline may pass the finalized records as a `BlockBuffer` rather than rereading a `.txt` file. Both paths must describe the same finalized canonical lines.
- A `.chunks` artifact made against earlier line numbering is stale and must be rebuilt.

## 3. Environment Variables
- CHUNK_SIZE: optional, the chunk size, default:300
- CHUNK_OVERLAP_PERCENT: optional, the overlap percent, default: 20%
- ARTIFACT_DIR: required, the directory in which chunk files are stored.
- ARTIFACT_WEB_DIR: required by the service, the root directory for topic and summary category trees.
- EXTRACT_TOPIC_MODEL_NAME: optional model profile for topic extraction; if unset, the default model name is `deepseek-v4-flash`.
- EXTRACT_TOPIC_PROMPT: required, the prompt for extracting topics from the chunk.
- CHUNK_SUMMARY_MODEL_NAME: optional summary model profile; falls back to `EXTRACT_TOPIC_MODEL_NAME`, then the default model name.
- GENERATE_SUMMARY_PROMPT: required summary prompt configuration used by summary generation.
- EMBEDDING_MODEL_NAME: required at service construction; used for topic and summary embeddings.
- EXTRACT_TOPIC_FALLBACK: optional fallback model profile for topic extraction.
- CHUNK_EXTRACT_TOPIC_MODELS_FILE, CHUNK_SUMMARY_MODELS_FILE, MODEL_DEF_FILE, PROMPT_DIR: optional model/prompt configuration locations used by the loaders.
- SUMMARY_GROUP_SIZE: optional number of child summaries grouped per parent, default 5.
- CATEGORY_SIMILARITY_MIN_SCORE: retained configuration/default, but topic category directory matching currently uses normalized exact names; embedding similarity matching is disabled in the topic tree writer.

## 4. Retrieve Record
Load the source record from `kb.inputs` where `kb.inputs.id = record_id`.

Error handling:
- If database access fails, report error and stop.
- If record does not exist, report error and stop.

## 5. Chunking
A chunk is represented in memory by a sequence number and marked lines:
```text
Chunk{SeqNo, Lines: [{Line, Mark: "n" | "o"}, ...]}
```
where:
- `n` marks a regular line in the chunk.
- `o` marks a carried overlap line from the preceding chunk.

The first chunk has no overlap lines.

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
- Chunk target size: `CHUNK_SIZE` bytes of serialized line content (not lines).
- Overlap: `CHUNK_OVERLAP_PERCENT` (line-based overlap ratio).
- Chunk-size sanity check:
  - For every non-final chunk, the regular `lines` payload, excluding `overlap`, MUST be at least `80%` of `CHUNK_SIZE` by byte size.
  - The overlap payload SHOULD be no more than `20%` of `CHUNK_SIZE` by byte size.
  - If overlap is larger than `20%` of `CHUNK_SIZE`, remove overlap lines from the front until the overlap is under that limit or only one overlap line remains.
  - The final chunk may have a regular payload smaller than `80%` of `CHUNK_SIZE`.
- Represent the persisted chunk artifact using line-number ranges:
  - `overlap`: overlap lines carried from the previous chunk
  - `lines`: regular lines in the chunk
- Never split a contiguous run of lines with the same table line type.
- Never split a contiguous run of lines with the same formula line type.
- A run of at least two consecutive list-candidate lines is protected regardless of list subtype. Candidates have a line type containing `list-item`; content matching a numeric section prefix like `ddd.ddd` is excluded. The implementation has no special very-large numerical-list exception.
- `chunk_seqno` starts at 1 and increments by 1.

### 5.2. List Detection Rules
There are currently four types of lists:
- `list-item`: general
- `list-item-num`: numerical lists, such as "1. xxx\n 2. xxx"
- `list-item-s-sym`: single-symbol lists, such as "a. xxx\n b. xxx"
- `list-item-m-sym`: multiple-symbal lists, such as "case 1: xxx\n case 2: xxx"

Refer to `ChenWeb/server/api/doc-processing/structure-static-analyzer.go`.

Chunking treats a line as a list candidate when its line type contains `list-item` (case-insensitive), its content is non-empty, and its content does not start with a numeric section identifier. A protected list block is a consecutive run of at least two candidates; it does not require identical list types. Below is an example:
```text
120 6 paragraph Health check items include:
121 6 list-item-s-sym a) Heart rate
122 6 list-item-s-sym b) Blood pressure
125 6 list-item-s-sym c) Weight
126 6 list-item-s-sym d) Height
Make sure all checked items meet the requirements.
```
In the above example, lines 121, 122, 125, and 126 are adjacent list candidates in the parsed input and therefore form one protected run, even though the source line numbers have gaps.

The chunker does not parse list sequence numbers; protection is based on `line_type` and non-empty content, with numeric section identifiers excluded. See `Capsules/doc-structure-analyzer-static/+CAPSULE.md` for how the analyzer assigns list types.

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
- Use the model defined by EXTRACT_TOPIC_MODEL_NAME and the prompt EXTRACT_TOPIC_PROMPT to extract topics from each chunk.
- The LLM returns the topics in JSON (see the JSON format below)

LLM Output JSON format:
```json
{
"topics": [
    {
      "topic_id": 1,
      "topic_type": "string",
      "lines": ["38-45", "47"],
      "topic_keywords": ["k1", "k2"],
      "topic_keywords_en": ["k1", "k2"],
      "topic_desc": "topic description",
      "topic_desc_en": "English topic description",
      "category_paths": [
        {
          "category_path": [
            {"name": "public_health", "keywords": ["health"], "confidence": 0.95}
          ],
          "path_keywords": ["health"],
          "path_confidence": 0.95
        }
      ]
    },
    {
      next-topic
    },
    ...
  ]
}
```
The current topic prompt's required fields are `topic_id`, `topic_type`, `lines`, `topic_keywords`, and `topic_desc`; English fields and `category_paths` are optional response fields understood by the normalizer when supplied.

### 6.3 Topic File
Topic extraction is a separate processor operation. It loads the existing `.chunks` artifact, extracts topics, writes the topic file, indexes category paths, writes embeddings, and updates topic status. Topic file name is:
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
topic_desc: "topic description"
category_paths: [(<path_keywords>, <path_confidence>, [(<category_name>, <keywords>, <confidence>), ...]), ...]
topic_keywords_en: ["keyword", ...]  # optional
topic_desc_en: "English topic description"  # optional
category_paths_en: [...]  # optional

<next-topic>
...
```

### 6.4 Embed Topics
* Use `EMBEDDING_MODEL_NAME` to embed topics (the same configured embedding model is used for summaries).
* Save topic embeddings in the file:
  `ARTIFACT_DIR/<group_id>/<record_id>/embeddings/topic_<topic_id>.embed`

### 6.5 Topic Indexing
A topic has one or more category paths. A category path is made of one or more categories.
Category paths are stored as file directories under ARTIFACT_WEB_DIR, where each
category maps to a sub-directory. For instance, if a category path is 
"medical_standards/surgical_conditions", there will be two directories:
```text
ARTIFACT_WEB_DIR/medical_standards
ARTIFACT_WEB_DIR/medical_standards/surgical_conditions
```

#### 6.5.1 Topic 'metadata.txt' File
Topic category directories are matched by normalized exact name. Existing metadata is merged; otherwise the writer creates the directory and `metadata.txt`. Topic category matching no longer uses embedding similarity. Each topic-tree directory's metadata is localized where available and includes fields such as:
```text
"desc":"category description"
"confidence":0.95
"keywords":["keyword",...]
"create_time":"yyyymmdd-hhmmss"
```

#### 6.5.2 Category Embedding
Topic category indexing does not create or consult category embeddings in the current implementation. Topic and summary artifact embeddings are stored separately under the record artifact directory.

#### 6.5.3 'topics.txt' File
This file saves all the topics whose category matches the directory's category.
Its file format is:
```text
record_id: ddd,
topic_id: ddd
topic_type: "topic-type"
topic_type_en: "English topic type"  # optional
lines: [ddd, ddd-ddd, ...]
topic_keywords: ["keyword", ...]
topic_desc: "topic description"
topic_desc_en: "English topic description"  # optional
topic_keywords_en: ["keyword", ...]  # optional
category_paths: [...]

<next-topic>
...
```

Topics in 'topics.txt' are sorted by record IDs.

#### 6.5.4 Workflow
* Before indexing a record, remove that record's old entries from topic-tree `topics.txt` files.
* For every topic category path, normalize each segment and navigate/create directories using exact normalized-name matching. Merge localized category metadata for existing directories; create metadata for new directories.
* Upsert the topic into the leaf directory's `topics.txt`. Entries are sorted by record ID, then topic sequence number.

## 7. Summaries
* Summary generation is a separate processor operation. It generates one level-0 summary per chunk, then groups summaries by `SUMMARY_GROUP_SIZE` to generate parent levels until one root remains. See `KnowledgeStore/Capsules/coding-capsules/doc-processor/generate-summary-spec.md` for summary content rules.
* Generate category paths for **every** summary (both leaf and group summaries),
  not just the root. Each summary gets its own category path from the LLM.
* Refer to 'spec-category-extraction.md' for how to extract category paths and
  save summaries in the Summary File Tree.

## 8. Table `kb.chunks`
This table stores one chunking run summary record.

Fields persisted by the current store include:
- `id`: auto-generated integer
- `source_record_id`: source `record_id`
- `chunking_method`: string
- `chunking_size`: integer
- `overlap_percent`: integer
- `notes`: text
- `overlap_lines`, `normal_lines`, `chunk_lines`: JSON line-number summaries aggregated from the built chunks
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
"record_id":"ddd",
"file_type":"pdf",
"operation":"chunked",
"proc_status":"success",
"input_filename":"Artifacts/0/100/std_20039_opendata.txt",
"num_lines":703,
"num_pages":26,
"num_labeled_lines":703,
"num_chunks":40,
"start_time":"yyyymmdd hh:mm:ss",
"ms_used":123
}
```

Notes:
- `error` is present only when `proc_status = "failed"`.
- Prefer snake_case keys (for example `ms_used`, `proc_status`) for consistency.

## 10. Workflow
Chunking processor:
1. Load the `kb.inputs` record and finalized canonical line records (from file bytes or block buffer).
2. Parse input, build chunks, filter TOC lines, and enforce byte-size and protected-block rules.
3. Write the `.chunks` index file under `ARTIFACT_DIR/<group_id>/<record_id>/`.
4. Insert the chunking run into `kb.chunks` and upsert the `chunked` status entry.

Topic extraction processor (separate operation):
1. Load and validate the `.chunks` artifact against canonical source lines.
2. Extract topics per chunk; write `.topics`; index category paths under `ARTIFACT_WEB_DIR`; write topic embeddings; update topic status.

Summary generation processor (separate operation):
1. Load or build chunks and generate leaf and parent summaries with category paths.
2. Write summary files and the summary category tree under `ARTIFACT_WEB_DIR`; embed and persist summaries; update summary status.

## 11. Failure Semantics
Each processor records its own operation status. If chunk construction or persistence fails, the `chunked` status is written as failed with a non-empty error where status persistence is possible. Topic extraction and summary generation have their own failure/status paths; they do not run inside the chunking handler.
