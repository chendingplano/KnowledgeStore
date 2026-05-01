## 1 Overview
The inputs are a collection of artifacts (a block of text). It uses an LLM to extract one or more category paths per artifact representing
distinct topics in the artifact.

## 2 Input
It expects the input in the following format:
```text
<line_number> <artifact>
<line_number> <artifact>
...
```
where:
- `<line_number>` is the line number, starting from 1
- `<artifact>` is the content (text) from which the category paths are generated

## 3 Category Path Generation Rules
- Extract one or more category paths per line
- Use an LLM to extract category paths.

The format of the LLM output is:
```json
[
{
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
    }
  ]
},
...
]
```

## 4 Handle Summaries
Given a document, the doc processing pipeline breaks the document into chunks and generate summaries
for all the chunks (refer to 'spec-chunking-fix-size.md' for document chunking and chunk
summary generation). It then moves on to this step to generate category paths for all
the summaries and summaries of summaries. 

Below is the workflow:

* Compose all the summaries (including summaries of summaries) into the format specified in
  the 'Input' section (above)
* Use the LLM and the prompt (must be present and valid. Otherwise, fail this step) to generate
  category paths.
* Summaries are all stored in the root directory SUMMARY_TREE_DIR. If SUMMARY_TREE_DIR is not defined,
  empty, or an invalid directory name, it is an error. It raises an error and fails this step.
* Create the SUMMARY_TREE_DIR directory if it does not exist yet.
* Set the category paths to the summary files (return to "Summary File Format" section in 'spec-generate-chunk-summary.md')
* For each category path: `category_path`
  * Set SUMMARY_TREE_DIR as its current directory
  * For the i-th category in `category_path`, find the closest sub-directories in the 
    current directory by calculating the cosine of their vectors as the similarity score:
    * If the similarity score is no less than CATEGORY_SIMILARITY_MIN_SCORE (the bigger, 
      the closer), the current category is considered 'the same' as the closest one. Set 
      the closest as its current directory. Move on to the next category, if any.
    * Otherwise, this is a new category in the current directory. Create the sub-directory
      and the metadata file for the sub-directory. Then move on to the next category, if any.
  * For the last category in `category_path`, store/update its summary to the file 'summaries.txt'

### 4.1 Summary Storage
Each category in a category path is a directory:
```text
  SUMMARY_TREE_DIR/category_1/category_2/.../category_n
```
where:
* SUMMARY_TREE_DIR is an environment variable (required)
* category_i is the i-th category in a category path

### 4.2 Category Metadata
A category directory stores the following metadata in the file 'category_meta.json':
```json
{
  "category_path": "the path from SUMMARY_TREE_DIR to this directory",
  "keywords": ["keyword", ...]
  "embedding_model": "the name of the embedding model",
  "centroid": "the centroid's vector",
  "desc": "the description of the category",
}
```

### 4.3 Summaries
If a category path ends at this directory, it stores its summary in the file 'summaries.txt':

## 5 Handle Topics
Given a document, the doc processing pipeline will generate a collection of topics (refer to
'spec-chunking-fix-size.md' for the topics it generates). It then moves on to this step
to generate category paths for all the topics.

The workflow is similar to `Handle Summaries` except that the root directory is TOPIC_TREE_ROOT_DIR

## 5 Topic Storage
Each category in a category path is a directory:
```text
  TOPIC_TREE_ROOT_DIR/category_1/category_2/.../category_n
```
where:
* TOPIC_TREE_ROOT_DIR is an environment variable (required)
* category_i is the i-th category in a category path

### 5.1 Topic Metadata
A category directory stores the following metadata in the file 'topic_meta.json':
```json
{
  "category_path": "the path from SUMMARY_TREE_DIR to this directory",
  "keywords": ["keyword", ...]
  "embedding_model": "the name of the embedding model",
  "centroid": "the centroid's vector",
  "desc": "the description of the category",
}

```text
<record_id>, <summary_id>, <time>
<record_id>, <summary_id>, <time>
...
```
where:
* `<record_id>` is the record id
* `<summary_id>` is the ID of the summary (refer to 'spec-chunking-fix-size.md' about summary ID)
* `<time>` is the time in `yyyymmdd-hhmmss` format when the summary was added to it


