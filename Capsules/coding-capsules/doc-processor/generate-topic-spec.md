# Extract Topics
- Use the model defined by EXTRACT_TOPIC_MODEL_NAME and the prompt EXTRACT_TOPIC_PROMPT to extract topics from each chunk.
- The LLM returns the topics in JSON (see the JSON format below)

LLM Output JSON format:
```json
{
"topics": [
    {
      "topic_id":<seqno>,
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


## Update `kb.inputs.status`
Persist operation status using canonical name:
- `operation = "generate_topics"`

Status payload (underscore fields only):
Payload schema:

```json
{
    "record_id":"ddd",
    "file_type":"pdf | doc | docx | ppt | pptx | ...",
    "operation": "generate_topics",
    "proc_status":"success | failed",
    "num_topics":ddd,
    "input_filename": "xxx"
    "output_filename": "xxx"
    "error":"xxx",
    "start_time":"yyyymmdd hh:mm:ss",
    "ms_used":ddd,
}
```

Notes:
- `error` is present only when `proc_status = "failed"`.
- Prefer snake_case keys (for example `ms_used`, `proc_status`) for consistency.

## Failure Semantics
If any step fails:
- stop processing,
- upsert `kb.inputs.status` with `proc_status = "failed"` and a non-empty `error`,
- do not mark operation as successful.

## Implementations
Refer to KnowledgeStore/Capsules/coding-capsules/doc-processor/generate-topic-impl.md