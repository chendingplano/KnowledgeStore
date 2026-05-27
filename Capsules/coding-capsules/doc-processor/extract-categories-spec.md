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
    },
    {
      <next category path>
    },
    ...
  ],
  "categories_en": [
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
    {
      <next category path>
    },
  ]
}
```
where `categories` is in its input language and `categories_en` is the accurate English translation of `categories` if 
the input language is not English.


## 4 Category Tree
Artifacts, such as summaries, topics, compliance provisions, etc., are indexed by Category Paths. 

For each category path (input language version and its English translation, if any, are treated as different paths), 
convert the category path into a directory path `summary-directory-path` and compose its full directory path as:
```text
  ARTIFACT_WEB_DIR + '/' + summary-directory-path
```

This directory is called `Category Director Path`. Category directory paths form a `Category Tree`

### 4.1 'metadata.txt' File
Each directory in a `category directory path` has a `metadata.txt`. Its format is:
```text
desc:"the category description", in its input language
desc_en: the English translation of 'desc' if its input language is not English
category_type:"the category type"
confidence:ddd
keywords:["ddd", ...], keywords are in its input language
keywords_en:["ddd", ...], the English translation of `keywords` if the input language is not English
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

## 4.2 Index Summaries
Given a document, the doc processing pipeline breaks the document into chunks, generates a summary
for each chunk and generates category paths for the summary (refer to documents in 
'KnowledgeStore/Capsules/coding-capsules/chunking' for document chunking, chunk summary generation and summary storage).

Below is the workflow of indexing summaries:

For each category path:
* For each category path:
  * Compose its `category path`
  * Set ARTIFACT_WEB_DIR as its current directory
  * For the i-th category in `category path`, find the sub-directories in the 
    current directory by the normalized category name:
    * If the sub-directory exists, merge its keywords/keywords_en to 'metadata.txt' and set the sub-directory as its current directory. Move on to the next category, if any.
    * Otherwise, create the sub-directory and the metadata file for the sub-directory. Set the sub-directory as the current directory. Then move on to the next category, if any.
  * Upsert its summary to 'summaries.txt', if the current directory matches the last category of the category path

`summaries.txt` format:
```text
<summary_id>
<summary_id>
...
```

Note that `<summary_id>` format is `<record_id>_<level>_<seqno>`. Summary IDs are sorted based on `record_id`, 
`level` and `seqno`.

## Index Metrics
Indexing metrics is the same as indexing summaries, except that metrics are stored in `metrics.txt` file.
`metrics.txt` file format is:
```text
<record_id>_<seqno>
<record_id>_<seqno>
...
```
where `<record_id>` is the record ID and `<seqno>` is the sequence number for the given record, starting from 1.

## Index Topics
Indexing topics is the same as indexing summaries, except that topics are stored in `topics.txt` file.

`topics.txt` file format is:
```text
record_id: <record-id>
topic_id: 4
topic_type: "compliance"
lines: [ddd, ddd-ddd...]
topic_keywords: [规范性引用文件, ...]
topic_keywords_en: [normative references, ...]
topic_desc: "列出本标准的规范性..."
topic_desc_en: "Lists the normative references ..."
category_paths: [(["规范性引用文件", ...], 0.95, [("标准", ["标准", "规范性引用文件"], 0.95), ("引用标准", ["国家标准", "行业标准", "国际标准"], 0.95)]), (...), ...]
category_paths_en: [(["normative references", ...], 0.95, [("standard", ["standard", "normative references"], 0.95), ("referenced standards", ["national standards", "industry standards", "international standards"], 0.95), (...), ...])]
```

Note:
* It uses an empty line to separate topics. 
* Topics are sorted by `record_id` and `topic_id`.

## Index Provisions
Indexing provisions is the same as indexing summaries, except that provisions are stored in `provisions.txt` file.

`provisions.txt` file format is:
```text
<record_id>_<prov_id>
<record_id>_<prov_id>
...
```

Its content is sorted by `<record_id>` and `<prov_id>` (provision ID).

## Index Scenes
Indexing scenes is the same as indexing summaries, except that scenes are stored in `scenes.txt` file.

## Index Products
Indexing products is the same as indexing summaries, except that scenes are stored in `products.txt` file.

## Index Semantic Projections
Indexing semantic projections is the same as indexing summaries, except that semantic projections
are stored in `semantic_projections.txt`. Save semantic projects (JSON) in the file.

## Index Structured Knowledge
Indexing structured knowledge is the same as indexing summaries, except that structured knowledge
is stored in `knowledges.txt`. Save structured knowledge JSON (not just its `knowledge_id`) in the file.