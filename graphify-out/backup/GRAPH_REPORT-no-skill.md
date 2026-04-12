# Graph Report - /Users/cding/Workspace/KnowledgeStore  (2026-04-11)

## Corpus Check
- 75 files · ~475,233 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 75 nodes · 362 edges · 19 communities detected
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 4 edges (avg confidence: 0.6)
- Token cost: 0 input · 0 output

## God Nodes (most connected - your core abstractions)
1. `releasemgr` - 20 edges
2. `migration-users` - 20 edges
3. `pgbackup` - 20 edges
4. `Logs` - 20 edges
5. `dbmigration-openai` - 20 edges
6. `goose-v1` - 20 edges
7. `syncdata-readme` - 20 edges
8. `dbmigration` - 20 edges
9. `jujutsu` - 20 edges
10. `syncdata-v2` - 20 edges

## Surprising Connections (you probably didn't know these)
- `FXTH87EH116T1_NXP_USA_Inc` --in_same_directory--> `QChunker`  [EXTRACTED]
  /Users/cding/Workspace/KnowledgeStore/PDFs/FXTH87EH116T1_NXP_USA_Inc.pdf → /Users/cding/Workspace/KnowledgeStore/PDFs/QChunker.md
- `QChunker` --in_same_directory--> `QChunker`  [EXTRACTED]
  /Users/cding/Workspace/KnowledgeStore/PDFs/QChunker.pdf → /Users/cding/Workspace/KnowledgeStore/PDFs/QChunker.md
- `psql-reference` --name_token_overlap--> `psql-reference_v1`  [INFERRED]
  /Users/cding/Workspace/KnowledgeStore/DevDocuments/psql-reference.md → /Users/cding/Workspace/KnowledgeStore/DevDocuments/psql-reference_v1.md
- `pdf-parser-convert-rslt-opendata` --name_token_overlap--> `pdf-parser-python`  [INFERRED]
  /Users/cding/Workspace/KnowledgeStore/DevDocuments/DesignDocs/pdf-parser-convert-rslt-opendata.md → /Users/cding/Workspace/KnowledgeStore/DevDocuments/DesignDocs/pdf-parser-python.md
- `pdf-parser-convert-rslt-opendata` --name_token_overlap--> `pdf-parser-go-service`  [INFERRED]
  /Users/cding/Workspace/KnowledgeStore/DevDocuments/DesignDocs/pdf-parser-convert-rslt-opendata.md → /Users/cding/Workspace/KnowledgeStore/DevDocuments/DesignDocs/pdf-parser-go-service.md

## Communities

### Community 0 - "Community 0"
Cohesion: 1.0
Nodes (21): IconService, Logs, config, dbmigration-openai, dbmigration, doc-generation-api, goose-review-qwen, goose-v1 (+13 more)

### Community 1 - "Community 1"
Cohesion: 1.0
Nodes (14): image-2026040701, image_2026032101, image_2026032102, image_2026032201, image_2026032301, image_2026032401, image_2026032901, image_2026040101 (+6 more)

### Community 2 - "Community 2"
Cohesion: 1.0
Nodes (8): TypstQuickRef, claude-code, codex, common-commands, docker, go-name-convention, jj-commands, postgres

### Community 3 - "Community 3"
Cohesion: 1.0
Nodes (6): create-knowledgebase-import, generate-semantic-entries, pdf-parser-convert-rslt-opendata, pdf-parser-go-service, pdf-parser-python, stdGk_3032175

### Community 4 - "Community 4"
Cohesion: 1.0
Nodes (4): AvailableAIAssistants, JAI-LightWeightSandbox, SelfEvolving-HyperAgents, ollama

### Community 5 - "Community 5"
Cohesion: 1.0
Nodes (4): ComplianceAnalyzerSkill, CreateChatterPrompt, CreateFlowEditorPrompt, CreateMainPagePrompt

### Community 6 - "Community 6"
Cohesion: 1.0
Nodes (3): FXTH87EH116T1_NXP_USA_Inc, QChunker, QChunker

### Community 7 - "Community 7"
Cohesion: 1.0
Nodes (2): AUTOTESTER, SKILL

### Community 8 - "Community 8"
Cohesion: 1.0
Nodes (2): DocGraph, DocMap

### Community 9 - "Community 9"
Cohesion: 1.0
Nodes (2): GRAPH_REPORT, NEEDS_SEMANTIC_EXTRACTION

### Community 10 - "Community 10"
Cohesion: 1.0
Nodes (1): README

### Community 11 - "Community 11"
Cohesion: 1.0
Nodes (1): table-schema-kb-input

### Community 12 - "Community 12"
Cohesion: 1.0
Nodes (1): PiAutoResearch

### Community 13 - "Community 13"
Cohesion: 1.0
Nodes (1): ConfigFixSummary

### Community 14 - "Community 14"
Cohesion: 1.0
Nodes (1): InstallProjectPrompt

### Community 15 - "Community 15"
Cohesion: 1.0
Nodes (1): obsidian

### Community 16 - "Community 16"
Cohesion: 1.0
Nodes (1): goose

### Community 17 - "Community 17"
Cohesion: 1.0
Nodes (1): DocReasoning

### Community 18 - "Community 18"
Cohesion: 1.0
Nodes (1): image_2026032501

## Knowledge Gaps
- **15 isolated node(s):** `README`, `AUTOTESTER`, `SKILL`, `table-schema-kb-input`, `DocGraph` (+10 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Community 7`** (2 nodes): `AUTOTESTER`, `SKILL`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 8`** (2 nodes): `DocGraph`, `DocMap`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 9`** (2 nodes): `GRAPH_REPORT`, `NEEDS_SEMANTIC_EXTRACTION`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 10`** (1 nodes): `README`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 11`** (1 nodes): `table-schema-kb-input`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 12`** (1 nodes): `PiAutoResearch`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 13`** (1 nodes): `ConfigFixSummary`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 14`** (1 nodes): `InstallProjectPrompt`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 15`** (1 nodes): `obsidian`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 16`** (1 nodes): `goose`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 17`** (1 nodes): `DocReasoning`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 18`** (1 nodes): `image_2026032501`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What connects `README`, `AUTOTESTER`, `SKILL` to the rest of the system?**
  _15 weakly-connected nodes found - possible documentation gaps or missing edges._

---
Report note: this run used deterministic document fallback mode (no semantic LLM extraction). Edges were derived from directory co-location and filename token overlap.
