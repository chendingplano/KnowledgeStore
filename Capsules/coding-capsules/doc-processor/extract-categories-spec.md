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

## 3 Category Path Generation
It uses an LLM to extract category paths for each artifact, which can be summaries or topics.

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

## 4 Index Summaries
Given a document, the doc processing pipeline breaks the document into chunks, generates a summary
for each chunk and generates category paths for the summary (refer to 'spec-chunking-fix-size.md' 
for document chunking, chunk summary generation and summary storage).

### 4.1 Summary Category File Tree
Document summaries are clustered by Category Paths. ory paths are used to create a file tree under SUMMARY_TREE_DIR:
```text
SUMMARY_TREE_DIR
  |- level-1-category-name-1
     |- level-2-category-name-1
        ...
     |- level-2-category-name-2
     ...
  |- level-1-category-name-2
  ...
```
Each of the node in the tree is a directory, called `Category Directory`.

### 4.2 'metadata.txt' File
Each category directory has a `metadata.txt'. Its format is:
```text
desc:"the category description"
category_type:"the category type"
confidence:ddd
keywords:["ddd", ...]
create_time:"yyyymmdd-hhmmss"
```
Values for the field 'desc' should escape '"' and '\n'.

**Updating 'metadata.txt'**
When a new category path is generated and its categories in the category path
match the existing directory, if the new category contains keywords that are not
present in this file, add them.

**Edge Case: Missing 'metadata.txt' File**
When a new category path is generated and its categories match an existing directory,
if the directory does not have the 'metadta.txt' file yet, add it.

### 4.3 'summaries.txt' File
Each category directory may have a `summaries.txt` file. Its formatt is:
```text
<summary_id>
<summary_id>
...
```
Refer to 'spec-generate-chunk-summary.md' for the definition and
format of `<summary_id>`.

If the current directory is the last category of a category path,
it will upsert its summary ID to this file. If the file does not
exist yet, it will create it.

Summary IDs are sorted based on 'record_id', 'level' and 'seqno'.

### 4.4 Embed Summaries
It embeds 'desc' and 'keywords' fields in its 'metadata.txt' file and saves
the vector to 'category.embed' file, in the format:
```text
[0.01018524169921875, 0.038726806640625, 0.02056884765625, 0.0008440017700195312,...]
```

### 4.4 Workflow
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
    * If the similarity score (score is between 0.0 and 1.0, the bigger, the closer) is no less than CATEGORY_SIMILARITY_MIN_SCORE, 
      the current category is considered 'the same' as the closest one. Set 
      the closest as its current directory. Move on to the next category, if any.
    * Otherwise, this is a new category in the current directory. Create the sub-directory
      and the metadata file for the sub-directory. Then move on to the next category, if any.
    * Each directory has a '
  * Upsert its summary ID to the file 'summaries.txt', if the current directory matches the last category of the category path
    (refer to "4.2 'summaries.txt' File" section).

## 5 Handle Topics
Given a document, the doc processing pipeline will generate a collection of topics (refer to
'spec-chunking-fix-size.md' for the topics it generates). 

## 5.1 Topic Storage
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


