# Overview

A document is broken down into a number of chunks. This feature does the following:
- Use an LLM to generate a summary for each chunk
- Build a summary tree for a document
- Cluster summaries based on semantic similarity

## 1 Generate Summaries

### 1.1 Workflow
- For each chunk, it uses GENERATE_SUMMARY_MODEL_NAME model with GENERATE_SUMMARY_PROMPT to generate 
  a summary for the chunk.  
- Generate a Level-1 summary for every SUMMARY_GROUP_SIZE continuous leaf summaries using the 
  same model and prompt. 
- Recursively, it generates higher level summaries in the same fashion until there is only
  one summary in its level.

### 1.2 Save Summaries
- Leaf summaries are saved to `ARTIFACT_DIR + /<group_id>/<record_id>/summary_0_dddd.txt`, where
  'dddd' is a sequence number, starting from 1.
- Summaries of summaries are saved to `ARTIFACT_DIR + /<group_id>/<record_id>/summary_n_dddd.txt`,
  where 'n' is the level: 1, 2, ... and 'dddd' is a sequence number, starting from 1.

### 1.3 Model Output Format
The model generates JSONs of the following format:
```json
{
  "summary": "summary in its input language",
  "summary_en": "the accurate English translation of 'summary' if its input language is not English",
  "keywords": ["xxx", ...], the keywords for the summary in its input language",
  "keywords_en": ["xxx", ...], the accurate English translation of 'keywords' if its input language is not English",
  "categories": [
    {
      "category_path": [
        {
          "name": "public_health",
          "keywords": ["health management", "disease prevention", "public health"],
          "confidence": 0.95
        },
        ...
      ],
      "path_keywords": ["vaccination records", "recipient data", "information system"],
      "path_confidence": 0.92
    }
  ], // in the input language
  "categories_en": [...] // the same structure, generate only when its input language is not English
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
summary_id: "<level>_dddd"
record_id": 123
level: 2
lines: [ddd, ddd-ddd]
children: ["1_0012", "1_0013"]
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
