# Overview

A document is broken down into a number of chunks. This feature does the following:
- Use an LLM to generate a summary for each chunk
- Build a summary tree for a document
- Cluster summaries based on semantic similarity

## 1 Generate Summaries

### 1.1 Leaf Summaries
For each chunk, it uses CHUNK_EXTRACT_TOPIC_MODEL_NAME model to generate a summary
for the chunk and save the summary to:

`ARTIFACT_DIR + /<group_id>/<record_id>/summary_0_dddd.txt`

where 'dddd' is the chunk's id, padded by leading 0's (chunks are identified by a 
sequence number: 1, 2, 3, ...)

These summaries are called `Leaf Summary`.

### 1.2 Group Summaries
This feature will generate a Level-1 summary for every SUMMARY_GROUP_SIZE continuous leaf summaries.
Level-1 summaries are stored to:

`ARTIFACT_DIR + /<group_id>/<record_id>/summary_1_dddd.txt`

where 'dddd' is a sequence number starting from 1.

It will recursively generate higher level summaries in the same fashion until there is only one
summary in its level.

These summaries are called `Group Summaries`.

### 1.3 Edge Cases
- The last group takes the remaining chunks, which may be less than SUMMARY_GROUP_SIZE chunks.

### 1.4 Summary Tree
Below illustrates the summary tree:
```text
ARTIFACT-DIR
  └─ leaf summaries 
      └─ level 1 summaries
          └─ level-2 summaries
              └─ ...
                  └─ root summary
```

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
category_paths: [(<path_keywords>, <path_confidence>, [<category_name>, <keywords>, <confidence>]), ...]
summary_begin
<the summary, can be in multiple lines>
summary_end
```

### 1.8 Summary Category Tree
Refer to 'spec-catgegory-extraction.md' for category extraction and Summary Category Tree update.

### 1.9 Idempotent
When a document is re-chunked, it should clear all the related data and before re-generate the data.
