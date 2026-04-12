# Graph Report - /Users/cding/Workspace/KnowledgeStore/DevDocuments/DesignDocs  (2026-04-11)

## Corpus Check
- Corpus is ~4,105 words - fits in a single context window. You may not need a graph.

## Summary
- 28 nodes · 33 edges · 5 communities detected
- Extraction: 82% EXTRACTED · 18% INFERRED · 0% AMBIGUOUS · INFERRED: 6 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## God Nodes (most connected - your core abstractions)
1. `Go PDF Parser Service` - 10 edges
2. `PDF Parse Result Converter Service` - 7 edges
3. `Status Management Pipeline` - 7 edges
4. `kb.inputs Table` - 4 edges
5. `Opendata Converter` - 4 edges
6. `Python PDF Parser Service` - 3 edges
7. `Semantic Entries Generation Process` - 3 edges
8. `T/CHIA 14.3-2018 Thermometer Standard` - 3 edges
9. `Parsing Operation Status` - 2 edges
10. `opendataloader-pdf Parser` - 2 edges

## Surprising Connections (you probably didn't know these)
- `Go PDF Parser Service` --semantically_similar_to--> `Python PDF Parser Service`  [INFERRED] [semantically similar]
  pdf-parser-go-service.md → pdf-parser-python.md
- `Go PDF Parser Service` --shares_data_with--> `PDF Parse Result Converter Service`  [INFERRED]
  pdf-parser-go-service.md → pdf-parser-convert-rslt-opendata.md
- `Status Traceability Across Pipeline Steps` --rationale_for--> `Status Management Pipeline`  [INFERRED]
  pdf-parser-python.md → pdf-parser-go-service.md
- `Status Management Pipeline` --references--> `Parsing Operation Status`  [EXTRACTED]
  pdf-parser-go-service.md → pdf-parser-python.md
- `Python PDF Parser Service` --references--> `Status Management Pipeline`  [EXTRACTED]
  pdf-parser-python.md → pdf-parser-go-service.md

## Hyperedges (group relationships)
- **PDF Processing Status Flow** — parse_operation, parsed_operation, converted_operation [EXTRACTED 1.00]
- **Parser Implementation Set** — opendata_parser, paddleocr_parser, opendata_converter, paddleocr_converter_placeholder [INFERRED 0.80]
- **Knowledge Base Import Query Group** — create_kb_import_page, kb_inputs_table, kb_inputs_search_filters [EXTRACTED 1.00]

## Communities

### Community 0 - "Parser Service Architecture"
Cohesion: 0.29
Nodes (8): Backup Directory, kb.inputs Table, PaddleOCR Parser, Parser Pluggability For Future Parsers, Go PDF Parser Service, Python PDF Parser Service, Result Directory, Staging Directory

### Community 1 - "Parsing Output and Standards"
Cohesion: 0.29
Nodes (7): Line-Based Text Output Format, Opendata Converter, Opendata JSON Parse Output Format, opendataloader-pdf Parser, T/CHIA 14.3-2018 Thermometer Standard, Thermometer Data Elements, Value Domain Code Tables

### Community 2 - "Semantic Status Modeling"
Cohesion: 0.33
Nodes (6): Parsed Operation Status, Semantic Chunk Model, Semantic Entries Generation Process, Status Traceability Across Pipeline Steps, Status Management Pipeline, Topic Model Attributes

### Community 3 - "Conversion Service Pipeline"
Cohesion: 0.5
Nodes (4): PDF Parse Result Converter Service, Converted Operation Status, JetStream PDF Success Subscription, PaddleOCR Converter Placeholder

### Community 4 - "Knowledgebase Import UX"
Cohesion: 0.67
Nodes (3): Knowledge Base Import Page, kb.inputs Search Filters, Parsing Operation Status

## Knowledge Gaps
- **15 isolated node(s):** `Parsed Operation Status`, `Converted Operation Status`, `PaddleOCR Parser`, `PaddleOCR Converter Placeholder`, `Opendata JSON Parse Output Format` (+10 more)
  These have ≤1 connection - possible missing edges or undocumented components.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `PDF Parse Result Converter Service` connect `Conversion Service Pipeline` to `Parser Service Architecture`, `Parsing Output and Standards`, `Semantic Status Modeling`?**
  _High betweenness centrality (0.459) - this node is a cross-community bridge._
- **Why does `Status Management Pipeline` connect `Semantic Status Modeling` to `Parser Service Architecture`, `Conversion Service Pipeline`, `Knowledgebase Import UX`?**
  _High betweenness centrality (0.420) - this node is a cross-community bridge._
- **Why does `Go PDF Parser Service` connect `Parser Service Architecture` to `Parsing Output and Standards`, `Semantic Status Modeling`, `Conversion Service Pipeline`?**
  _High betweenness centrality (0.402) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `Go PDF Parser Service` (e.g. with `Python PDF Parser Service` and `PDF Parse Result Converter Service`) actually correct?**
  _`Go PDF Parser Service` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `Status Management Pipeline` (e.g. with `Status Traceability Across Pipeline Steps` and `Semantic Entries Generation Process`) actually correct?**
  _`Status Management Pipeline` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `Parsed Operation Status`, `Converted Operation Status`, `PaddleOCR Parser` to the rest of the system?**
  _15 weakly-connected nodes found - possible documentation gaps or missing edges._