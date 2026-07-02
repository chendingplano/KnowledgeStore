# Extract Topics
- Use the model defined by EXTRACT_TOPIC_MODEL_NAME and the prompt EXTRACT_TOPIC_PROMPT to extract topics from each chunk.
- The LLM returns the topics in JSON (see the JSON format below)

LLM Output JSON format:
```json
{
"topics": [
    {
      "topic_id":"<record_id>_tpc_<seqno>",
      "topic_type": "string",
      "lines": ["38-45", "47"],
      "topic_keywords": ["keyword", "keyword",...],
      "topic_keywords_en": ["keyword", "keyword",...],
      "topic_desc": "topic description",
      "topic_desc_en": "topic description, present only when its input language is not English",
      "category_paths": [
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
      ]
      "category_paths_en": the accurate English translation of `category_paths` if the input language is not English
    },
    {
      <the next topic>
    },
    ...
  ]
}
```

## Topic File
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
topic_keywords_en: ["keyword", ...]
topic_desc: "topic"
topic_desc_en: "topic"
category_paths: [(<path_keywords>, <path_confidence>, [<category_name>, <keywords>, <confidence>]), ...]
category_paths_en: [(<path_keywords>, <path_confidence>, [<category_name>, <keywords>, <confidence>]), ...]

<next-topic>
...
```

## Embed Topics
* Use TOPIC_EMBEDDING_MODEL_NAME to embed topics.
* Save topic embeddings in the file:
  `ARTIFACT_DIR/<group_id>/<record_id>/embeddings/topic_<topic_id>.embed`

## Topic Indexing
A topic has one or more category paths. A category path is made of one or more categories.
Category paths are stored as file directories under ARTIFACT_WEB_DIR, where each
category maps to a sub-directory. For instance, if a category path is 
"medical_standards/surgical_conditions", there will be two directories:
```text
ARTIFACT_WEB_DIR/medical_standards
ARTIFACT_WEB_DIR/medical_standards/surgical_conditions
```

### Topic 'metadata.txt' File
Each directory under ARTIFACT_WEB_DIR has a 'metadata.txt' file. The file format is:
```text
"desc":"category description"
"confidence":0.95
"keywords":["keyword",...]
"create_time":"yyyymmdd-hhmmss"
```

### 'topics.txt' File
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

### Workflow
* For each category path: `category_path`
  * Set ARTIFACT_WEB_DIR as its current directory
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

### Line-Overlap Artifact Edges

In Phase C (`GenerateTopicsProcessor.PostProcessIndex`), after the topic rows are rebuilt in
`kb.search_artifacts` (`ReindexTopicSearchForRecord`) and the category-path files are written
(`IndexTopicsForRecord`), indexing materializes intra-document, line-overlapping artifacts as
traversable edges in `kb.artifact_connections`. They are built deterministically (no LLM or
hybrid search). Reviewers start from a topic and reach the entities/metrics/etc. that share its
lines (a read matches either endpoint).

For each topic `TP` in the record being indexed:

1. Find every artifact in the **same document** whose line spans overlap `TP`'s, grouped by
   type `T ∈ {entity, metric, provision, inventory_item, semantic_projection}` (the self
   family, `topic`, is excluded). Overlap is computed by self-joining `kb.search_artifacts` on
   the GiST-indexed `line_range && line_range` operator, so both endpoints use their canonical
   `artifact_id`s.
2. For each overlapping artifact (anchor) `X` of type `T`, upsert one edge to
   `kb.artifact_connections`:
   - `source_type = T`, `source_id = X.artifact_id`, `source_record_id = record_id`
   - `target_type = 'topic'`, `target_id` = the topic's canonical registry `artifact_id` (the
     `<record>_tpc_<seq>` form in `kb.search_artifacts`, which differs from
     `kb.topics.topic_id`, e.g. `100_1`), `target_record_id = record_id`
   - `relation_name = '#shared_artifact'`
   - `relation_method = 'line-overlapped-artifact'`
   - `confidence = 1.0` (deterministic overlap)
   - `extra_info` containing at least `{"source":"generate_topics","anchor_type":T}`

The overlapping anchor is the **source** and the topic is the **target**; because both share
lines, these edges are always intra-document (`source_record_id = target_record_id =
record_id`).

**Idempotency.** Rebuilt each run by `ReplaceSharedArtifactEdges`, which deletes the record's
existing edges scoped to `target_type = 'topic'` (plus
`relation_method = 'line-overlapped-artifact'`, `relation_name = '#shared_artifact'`), then
inserts the fresh set. The delete is scoped by target family so parallel Phase-C family runs
never clobber each other's edges.

The chunk→topic `has-topic` line-overlap edges (chunk endpoints) are written earlier, in
Phase B, by the chunking processor; they are separate from these artifact↔artifact edges.
`connected_artifacts` for a topic is computed on demand by
`kb.connected_artifacts(record_id, 'topic', source_row_id)` and is not materialized.

## Update `kb.inputs.status`
Persist operation status using canonical name:
- `operation = "generate_topics"`

**Progress Update (per chunk):**
- When beginning the extraction, update the `progress` attribute of the corresponding entry in `kb.inputs.status` with "0 %".
- After extracting topics from each chunk, update the `progress` attribute of the corresponding entry in `kb.inputs.status` with the current progress.

```text
progress = current_chunk (starting from 1) / total_chunks * 100
```

Status payload schema:

```json
{
    "record_id":"ddd",
    "file_type":"pdf | doc | docx | ppt | pptx | ...",
    "operation": "generate_topics",
    "proc_status":"success | failed | stopped",
    "num_topics":ddd,
    "input_filename": "xxx",
    "output_filename": "xxx",
    "error":"xxx",
    "start_time":"yyyymmdd hh:mm:ss",
    "ms_used":ddd,
}
```

Notes:
- `error` is present only when `proc_status = "failed"`.
- `proc_status = "stopped"` is written when a user stop request is detected at an LLM call boundary. `num_topics` reflects topics extracted before the stop. `output_filename` and `error` are absent.
- Prefer snake_case keys (for example `ms_used`, `proc_status`) for consistency.

## Failure Semantics
If any step fails:
- stop processing,
- upsert `kb.inputs.status` with `proc_status = "failed"` and a non-empty `error`,
- do not mark operation as successful.

## Stop Semantics
When a user stop request is detected at the boundary of an LLM call (i.e. `isCtxStopped(ctx)` returns true):
- Stop processing immediately — do not attempt the current or any remaining LLM call.
- Upsert `kb.inputs.status` with `proc_status = "stopped"` and the topics extracted so far in `num_topics`. No `error` field.
- Write a finish log entry to `kb.doc_proc_logs` (entry type `extract_topics_finish`) with the stopped reason in `errors`.
- Return `ErrPipelineStopped` to the pipeline controller.

## Search And Artifact Connections

- The shared hybrid-search behavior is configured by `ChenWeb/config.toml` `[artifact_search]`.
- Topic-specific lexical emphasis is configured by `ChenWeb/config.toml` `[topics_search_weights]`.
- After topics are persisted (Phase B), the implementation rebuilds that record's topic rows in
  `kb.search_artifacts` and writes the chunk→topic line-overlap `has-topic` edges.
- In Phase C (`GenerateTopicsProcessor.PostProcessIndex`) indexing writes the category-path
  files and the `#shared_artifact` line-overlap artifact edges (see [Line-Overlap Artifact
  Edges](#line-overlap-artifact-edges)). Semantic topic↔topic similarity is **not** materialized
  — it is computed live at read time via `FindSimilarArtifactsOnTheFly` (there is no index-time
  hybrid artifact-connection step).

## Implementations
Refer to [1]

# References
[1] KnowledgeStore/Capsules/coding-capsules/doc-processor/generate-topic-impl.md

[2] KnowledgeStore/Capsules/coding-capsules/doc-processor/doc-processor-log-spec.md
