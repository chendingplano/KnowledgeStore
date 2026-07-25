# Spec: CMD Editor
Date: 2026/07/25 \
Status: Proposal

# Overview
CDM (Canonical Document Model, refer to [1]) Editor is a browser-based
editor that let's users create and edit CDM documents.

CDM Editor is not just another Rich Text Editor, Google Docs, Microsoft 
Word Editor. It is an Knowledge Editor, or an Editor for AI.

# Main Features
## Search documents
This is a tool that can be used in any place: 
- search while editing
- search relevant documents before creating a new one
- search documents to archive

It provides multi-dimensional searching capabilities:
- Search by metadata, such as title, authors, creation time, read time,
  modify time, etc.
- Search by semantic objects, such as `concept`, `terminology`, `definition`,
  `ontology`, `canonical object`, etc.
- Search document history
- Hybrid search: BM25 + semantic similarity

## Create new documents
This should be implemented as a function. There will be multiple places
that we may allow users to create new documents.

## Editor
The Editor is made of tools.

### Text Edit Tool
This is a Rich Text Editor. Like most rich text editor. It should have a 
tool bar for text editing, such as font, size, color, text alignment, 
insert formulas, tables, image, video, etc.

### Knowledge Markdown
Users can highlight a piece of text and mark it with a semantic object, 
such as `terminology`, `concept`, `definition`, `reference`, `quotation`, 
`entity`, `relation`, `canonical object`, etc. 

### Document Reviewers
A rich set of document reviewers implemented in [2].

### Summarization Tool
Summarize a section, a block of text, the entire document, etc.

### Extraction Tool
Extract keywords from the entire document, from a chapter/section,
  or a block of selected text.
- Rewrite a chapter/section, or a selected block. Users can specify
  how to rewrite: using a skill, select a stored prompt, write 
  specific instructions, etc.

- Inline Search: highlight a block of text, or type something, search
  the knowledge base for relevant content. 
- Ontonogy: A document may be associated with one or more ontnogy entities.
  Users can create new ontology entities. 
- Chunking: 
## Modify documents
## Delete Documents


# References
[1] KnowledgeStore/doc-repo/specs/202607/2026072501-spec-canonical-doc-model.md
[2] the doc reviewer 
