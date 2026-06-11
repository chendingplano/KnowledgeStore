# 1. Knowledgebase Explorability and Searchability

- DocID: `doc-2026061105`
- **Status:** Active
- **Date:** 2026-06-11
- **Deciders:** Chen Ding
- **Tags:** Knowledge Base, Explorability, Searchability

# 2. Introduction to Knowledgebase
The knowledgebase is built on a corpus of standards and technical documents. Documents are
mostly PDF files, parsed into line files (refer to [1]).

Each document is a Searchable Object. Documents are stored in the table `kb.inputs`,
identified by `kb.inputs.id` (`record_id`), which is an auto-incremented integer.

A document, its line file, chunks, and all its artifacts are stored in a specific directory:
```text
    Artifacts/<group_id>/<record_id>/
```
where `<group_id>` = floor(`record_id` / 1000).

The directory contains the following files and directories:
| File Name | Explanation |
|-----------|-------------|
| std_33830_images_pages | List all the page images, one image per page |
| std_33830_opendata.chunks | List the document chunks |
| std_33830_opendata.entities | All the entities extracted by LLM from this document |
| std_33830_opendata.json | The parse result in JSON |
| std_33830_opendata.metrics | ALl the metrics extracted by LLM from this document |
| std_33830_opendata.origin | The original line file of the document |
| std_33830_opendata.provisions | All the compliance provisions extracted by the LLM from this document |
| std_33830_opendata.relations | All the compliance provisions extracted by the LLM from this document |
| std_33830_opendata.scene_blocks | All the compliance provisions extracted by the LLM from this document |
| std_33830_opendata.semantic_projections | All the compliance provisions extracted by the LLM from this document |
| std_33830_opendata.topics | All the compliance provisions extracted by the LLM from this document |
| std_33830_opendata.txt
| std_33830.json
| std_33830.md
| std_33830.pdf
| summary_0_xxxx.txt
| summary_1_xxxx.txt
| summary_2_xxxx.txt
----------


# References
[1] KnowledgeStore/doc-repo/202604/2026042101-line-file-spec.md
