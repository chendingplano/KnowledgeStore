# Purpose
A Wiki-style page as the main entrance to SemOS, a deep knowledge base.

## Corpus
The corpus of SemOS is mainly documents, notes, web pages, etc., collectively called `Docs`, mostly unstructured data.
New docs may be added constantly. Existing docs may be modified or deleted.

## Doc Processors
Docs are converted to the Line files ([1]). Doc processors (refer to [2]) are then 
invoked to process docs. Most doc processors will generate results, which are
saved in the database.

## Docs and Artifacts
Docs and their artifacts (i.e., the results of doc processors) are stored in the directory:
```text
    ARTIFACT_DIR/<group_id>/<record_id>
```

Artifacts are connected through relations, forming an Artifact Wiki.
Refer to [Relation Types](#relation-types)

## Relation Types

| Type | From | To | Generation |
|------|------|----|------------|
| entity relations | `entity` | `entity` | LLM extracted from docs | 
| belong-to-category | `metric` | `category` | LLM extracted from docs based on chunks |
| has-metrics | chunk | `metric` | Determined by chunks and metrics sharing the same source lines |
| has-part-component | chunk | `part-component` | Determined by chunks and parts sharing the same source lines |
| has-scene | chunk | `scene` | Determined by chunks and scenes sharing the same source lines |
| has-topic | chunk | `topic` | Determined by chunks and topics sharing the same source lines |
| has-provision | chunk | `provision` | Determined by chunks and provisions sharing the same source lines |
-----

## Page Layout
```text
------------------------------------------------------------------------------------------
|                                       |                                                |
|          Panel A                      |             Panel B                            |
|                                       |                                                |
------------------------------------------------------------------------------------------
|                                                                                        |
|                                                                                        |
|                               Panel C                                                  |
|                                                                                        |
------------------------------------------------------------------------------------------
```

## Page Design
### Panel A
Similar to https://www.wikipedia.org, the top part. 
Replace the globe image in the center of the top part with an image. Surround the image with:
  - "Documents - <the number of documents and articles> 
  - "Content Segments - <the number of chunks> 
  - "Topics - <the number of topics> 
  - "Metrics - <the number of metrics> 
  - "Provisions - <the number of topics> 
  - "Parts and Components - <the number of parts and components> 
  - "Scenes - <the number of scenes> 
  - "Entities = <the number of entities>
  - "Relations = <the number of relations>

At the bottom:
- A keyword-based search 
- Let people select their language

### Panel B
Similar to the lower-right part of https://www.wikipedia.org, with the following components:
- Documents (clickable) / "documents, notes, articles, ..."
- Content Segments (clickable) / "content segments, chunks, ..."
- Topics (clickable) / "browsing/search topics, ..."
- Metrics (clickable) / "browsing/search metrics, ..."
- Parts and Components (clickable) / "browsing/search parts and components, ..."
- Scenes (clickable) / "browsing/search scents, ..."
- Provisions (clickable) / "browsing/search provisions, ..."
- Graphs (clickable) / "browsing/search entities and relations, ..."

### Panel C
- Recent Adds: A list that lists the documents added, sorted by create time in descending order
- Recent Edits: A list that lists the documents modified, sorted by modify time in descending order
- Recent Processed: A list that lists the processed documents, sorted by the process time in descending order
- Errors: A list that lists errors, sorted by the time in the descending order

## Implementations
Refer to [3] about the implementations.

## References
[1] KnowledgeStore/DevDocuments/Specs/spec-line-file.md \
[2] KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md \
[3] KnowledgeStore/Capsules/coding-capsules/deep-wiki/deep-wiki-impl.md
