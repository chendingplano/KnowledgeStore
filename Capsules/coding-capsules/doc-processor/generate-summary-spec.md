# Overview

A document is broken down into a number of chunks. This feature does the following:
- Use an LLM to generate a summary for each chunk
- Build a summary tree for a document
- Cluster summaries based on semantic similarity

## 1 Generate Summaries

### 1.1 Workflow
- For each chunk, it uses GENERATE_SUMMARY_MODEL_NAME model with GENERATE_SUMMARY_PROMPT to generate 
  a summary for the chunk.  
- Summaries that belong to the same level may be generated concurrently, capped by
  `GENERATE_SUMMARY_MAX_TASKS`.
- Generate a Level-1 summary for every SUMMARY_GROUP_SIZE continuous leaf summaries using the 
  same model and prompt. 
- Recursively, it generates higher level summaries in the same fashion until there is only
  one summary in its level.
- Higher summary levels still wait for the previous level to finish before they begin.

### 1.2 Save Summaries
- Leaf summaries are saved to `ARTIFACT_DIR + /<group_id>/<record_id>/summary_0_dddd.txt`, where
  'dddd' is a sequence number, starting from 1.
- Summaries of summaries are saved to `ARTIFACT_DIR + /<group_id>/<record_id>/summary_n_dddd.txt`,
  where 'n' is the level: 1, 2, ... and 'dddd' is a sequence number, starting from 1.
- For a leaf summary, the saved `lines` field MUST cover the full chunk input sent to the summary model,
  including both overlap context and regular chunk lines.

### 1.3 Model Output Format
The model generates JSONs of the following format:
```json
{
  "language": "string",
  "summary": "summary in its input language",
  "summary_en": "the accurate English translation of 'summary' if its input language is not English",
  "keywords": ["xxx", ...], the keywords for the summary in its input language",
  "keywords_en": ["xxx", ...], the accurate English translation of 'keywords' if its input language is not English",
}
```

### 1.4 Edge Cases
- The last group takes the remaining chunks, which may be less than SUMMARY_GROUP_SIZE chunks.

### 1.5 Summary ID
```<record_id>_<level>_<seqno>```

where:
- `<record_id>` is the record ID
- `<level>`: the summary level
- `<seqno>`: the summary seqno

### 1.6 Summary Embedding
- Use SUMMARY_EMBEDDING_MODEL_NAME to embed summaries.
- Each summary's embedding vector is stored in a dedicated file alongside its summary file:

`ARTIFACT_DIR + /<group_id>/<record_id>/embeddings/summary_<level>_<dddd>.embed`

For example, the embed file for `summary_0_0001.txt` is `summary_0_0001.embed`.

### 1.7 Summary File Format

```text
summary_id: "<record_id>_<level>_dddd"
record_id": 123
level: 2
lines: [ddd, ddd-ddd]
children: ["1_0012", "1_0013"]
language: "the language"
keywords: ["xxx",...]
keywords_en: ["xxx",...]
category_paths: [(<path_keywords>, <path_confidence>, [<category_name>, <keywords>, <confidence>]), ...]
category_paths_en: [(<path_keywords>, <path_confidence>, [<category_name>, <keywords>, <confidence>]), ...]
summary_begin
<the summary, can be in multiple lines>
summary_end
summary_en_begin
<the summary, can be in multiple lines>
summary_en_end
```

### 1.8 Index Summaries

Refer to Section "Index Summaries" in 'KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-categories-spec.md' for indexing summaries.

### 1.9 Idempotent
When a document is re-chunked, it should clear all the related data and before re-generate the data.

## Update Status

Persist operation status using canonical name:
- `operation = "generate_summaries"`

**Progress Update (per summary):**
- When beginning generation, set `progress` to `"0%"` in `kb.inputs.status`.
- After each summary generation (at every level), insert a log entry to `kb.doc_proc_logs` with `proc_progress` set to the current progress (see [doc-processor-log-spec.md Section 1.3.1](doc-processor-log-spec.md)), then update the `progress` attribute of the corresponding entry in `kb.inputs.status`.

```text
total_planned_summaries =
  level0_count +
  ceil(level0_count / SUMMARY_GROUP_SIZE) +
  ceil(level1_count / SUMMARY_GROUP_SIZE) + ...
  (stop when the level count becomes 1)

percent = floor(completed_summaries * 100 / total_planned_summaries)
progress = "<percent>% (<completed_summaries>/<total_planned_summaries>)"
```

Examples:
- 1 of 3 summaries finished → `33% (1/3)`
- 2 of 3 summaries finished → `66% (2/3)`
- 3 of 3 summaries finished → `100% (3/3)`

Status payload (underscore fields only):

When success:
```json
{
    "record_id":"ddd",
    "file_type":"pdf | doc | docx | ppt | pptx | ...",
    "operation": "generate_summaries",
    "proc_status":"success",
    "input_filename": "Artifacts/0/100/std_20039_opendata.txt"
    "start_time":"yyyymmdd hh:mm:ss",
    "ms_used":ddd,
}
```

When failed:
```json
{
    "record_id":"ddd",
    "file_type":"pdf | doc | docx | ppt | pptx | ...",
    "operation": "generate_summaries",
    "proc_status":"failed",
    "error":"error-msg",
    "input_filename": "Artifacts/0/100/std_20039_opendata.txt"
    "start_time":"yyyymmdd hh:mm:ss",
    "ms_used":ddd,
}
```

## Search And Artifact Connections

- The shared hybrid-search behavior is configured by `ChenWeb/config.toml` `[artifact_search]`.
- Summary-specific lexical emphasis is configured by `ChenWeb/config.toml` `[summaries_search_weights]`.
- After summaries are persisted, the implementation rebuilds that record's summary rows in `kb.search_artifacts`, writes the line-overlap `has-summary` edges for level-0 summaries, and runs the hybrid artifact-connection step using `kb.summaries.search_document` against `kb.search_artifacts`.
