# 1. Knowledgebase Explorability and Searchability

- DocID: `doc-2026061105`
- **Status:** Active
- **Date:** 2026-06-11
- **Deciders:** Chen Ding
- **Tags:** Knowledge Base, Explorability, Searchability

# 2. Knowledgebase
The knowledgebase is built on a corpus of standards and technical documents. Documents are
mostly PDF files, parsed into line files (refer to [1]).

Each document is a Searchable Object. Documents are stored in the table `kb.inputs`,
identified by `kb.inputs.id` (`record_id`), which is an auto-incremented integer.

## 2.1 Documents in Files
A document, its line file, chunks, and all its artifacts are stored in a specific directory:
```text
    Artifacts/<group_id>/<record_id>/
```
where `<group_id>` = floor(`record_id` / 1000).

The directory contains the following files and directories:
| File Name | Explanation |
|-----------|-------------|
| images/ | A directory that lists all the images extracted from the doc for pictures, tables, and formulas|
| std_33830_opendata.chunks | List the document chunks |
| std_33830_opendata.entities | All the entities extracted by LLM from this document |
| std_33830_opendata.json | The parse result in JSON |
| std_33830_opendata.metrics | ALl the metrics extracted by LLM from this document |
| std_33830_opendata.origin | The original line file of the document |
| std_33830_opendata.provisions | All the compliance provisions extracted by the LLM from this document |
| std_33830_opendata.relations | All the relations extracted by the LLM from this document |
| std_33830_opendata.scene_blocks | All the scene blocks extracted by the LLM from this document |
| std_33830_opendata.semantic_projections | All the semantic projections extracted by the LLM from this document |
| std_33830_opendata.inventory_items | All the inventory items extracted by the LLM from this document |
| std_33830_opendata.topics | All the topics extracted by the LLM from this document |
| std_33830_opendata.txt | The line file for the document |
| std_33830.pdf | The original PDF file |
| summary_*.txt | The summary files, one level 0 summary per chunk, one level 1 summary per 8 level 0 summaries, etc.. File name format: `summary_<level>_<seqno>` |
---

In the above, file name format is:
```text
<orig_filename>_<parser_name>.<extention>
```
where `<orig_filename>` is the root of `kb.inputs.staging_filename`, `<parser_name>` = `kb.inputs.parser_name`.

## 2.2 Documents in Database Tables
| Table Name | Explanation |
|------------|-------------|
| `kb.chunks` | artifact table for chunks |
| `kb.entities` | artifact table for entities |
| `kb.relations` | artifact table for entities |
| `kb.inventory_items` | artifact table for inventory items|
| `kb.metrics` | artifact table for metrics |
| `kb.provisions` | artifact table for provisions |
| `kb.scene_objects` | artifact table for scene blocks |
| `kb.semantic_projections` | artifact table for semantic projections |
| `kb.summaries` | artifact table for summaries |
| `kb.topics` | artifact table for topics |
| `kb.artifact_categories` | store artifact categories |
| `kb.artifact_connections` | relations between artifacts |
| `kb.category_instance` | relations between artifact categories and artifacts (mainly metrics and inventory items|
| `kb.search_artifcts` | all searchable artifacts |

# References
[1] KnowledgeStore/doc-repo/202604/2026042101-line-file-spec.md
