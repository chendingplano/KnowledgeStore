# Spec: CDM Editor
Date: 2026/07/25 \
Status: Proposal

# Overview
CDM (Canonical Document Model, refer to [1]) Editor is a browser-based
editor that lets users create and edit CDM documents.

CDM Editor is not just another Rich Text Editor, Google Docs, Microsoft 
Word Editor. It is a Knowledge Editor, or an Editor for AI.

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
Extract keywords from the entire document, from a chapter/section, or a block of selected text.

### Rewrite a Chapter/Section, or a Selected Block
Users can specify how to rewrite: 
- using a skill, 
- select a stored prompt, 
- write specific instructions, etc.

### Inline Search
Highlight a block of text, or type something, then search the knowledge base 
for relevant content. 

### Ontology
A document may be associated with one or more ontology objects. Users can 
create new ontology objects, search ontology objects, modify or delete them. 

### Chunking
It lets authors do the chunking. If no chunking is done, the system will 
do the chunking automatically in the doc processing pipeline.

### Modify documents
Each modification 
- Generate a new version
- Generate a summary about the changes

### Lifecycles
A document is a living object. Its lifecycle typically has:
- `proposal`
- `proposal-approved`
- `drafting`
- `draft-review`
- `open-for-comments`
- `comment-review`
- `draft-approved`
- `published`
- `implemented`
- `revision-proposal`
- `revision-proposal-review`
- `revision-proposal-approved`
- `revision-drafting`
- `revision-review`
- `revision-approved`
- `revision-published`
- `document-pre-abolish`
- `document-abolished`

Not all documents will go through all the states. The system should
have a collection of document types/categories and document lifecycles.

In reality, most documents simply do not have lifecycles at all.

### Version Management
This tool lets users view document history and versions.

### Delete Documents
Documents by default never hard deleted, but users do have the option
to hard delete them.

When deleting a document, it is very important to delete not only the
document but also all its derived data and artifacts.

### Retention Tool
Documents may be associated with a retention plan. Expired documents
are archived first, and may eventually hard removed from the system.

### Template Management
Let users create, modify, delete and manage templates.

### Auto-Generated Content
- Table of Content
- List of Figures
- List of Tables
- List of Formulas
- Appendix of Metrics
- Appendix of Topics
- Appendix of Other Artifact
- Index

### Deep Research
AI-assisted deep research tool.

### Chat-to-Document
It creates documents by chatting with LLMs.

# Design Decisions

Resolutions taken 2026/07/26 while reviewing this proposal against the CDM
specification [1]. Recorded in ADR [3].

## D1 — Formatting lives in Typst templates, not in the document

The Text Edit Tool's formatting controls (font, size, color, alignment) must not
write presentation properties into the canonical document. CDM stores meaning;
Typst templates carry appearance (CDM §5.5).

This is what makes mandatory formatting standards tractable. A prior in-house
online editor built to satisfy China's mandatory standard for formatting
national standards worked, but became extremely difficult to maintain and could
not be generalized to other customers — because the formatting rules were welded
into the editor instead of being a separable artifact. Under CDM a second
standard is a second template.

The editing surface should therefore expose **semantic** actions — heading,
emphasis, list, table, callout, definition — and let the template decide how each
one looks. Full support for a specific mandatory standard is deferred until CDM
and this editor are mature.

## D2 — Knowledge Markdown produces ordinary artifacts

Author annotations (`terminology`, `concept`, `definition`, `entity`,
`relation`, `canonical object`) are artifacts in exactly the same sense as those
a doc processor extracts, stored in the same tables and consumed by the same
tooling. They are simply much cheaper and much more accurate, because a human
asserted them.

Every artifact records an origin, defaulting to `extracted`, with
`human-created` for author assertions — following the existing
`kb.images.origin` convention. Artifact types that do not yet exist
(`terminology`, `concept`, `definition`) are planned as ordinary doc processors
with ordinary tables. **No new artifact types are added in the current phase.**
See CDM §10.3.

## D3 — A new version is a new document

Each version is a separate document with its own `kb.inputs` row, processed
independently. Versions are linked by a typed relation recorded on the input row
(a dedicated column or within `kb.inputs.doc_metadata`): `addendum`,
`amendment`, `replace`.

This keeps every version independently addressable and citable, which matters
because artifacts, line spans, anchors, and renderings all bind to a specific
document. Distinguish this from `content_version`, which is the within-document
edit counter. See CDM §10.4.

## D4 — Authors declare chunks semantically; the pipeline resolves them physically

Chunking is an artifact generated after the line file, as line ranges with
overlaps. Authors may declare chunk groups on blocks at the semantic level;
these resolve to line ranges once the line file exists. Absent any declaration,
the pipeline chunks automatically, as it does for uploaded documents. Overlap
remains the chunker's concern. See CDM §10.2.

## D5 — Auto-generated content is deferred

Table of contents, list of figures/tables/formulas, index, and the artifact
appendices are deferred. Several of them require numbered, referenceable figures
and tables — a numbering authority that CDM v1.0 deliberately omits — so they
are recorded as a known future requirement rather than dropped.

One structural note for whenever they are built: the artifact appendices
(metrics, topics, other artifacts) are content *derived from pipeline output*,
while the pipeline runs on the published document. To avoid a cycle, these should
be render-time projections rather than stored blocks, so they never enter the AST
and never re-trigger processing.

## D6 — Document lifecycles are user-defined state machines, deferred

Lifecycles are application- and business-dependent, so the system must let users
**define their own** rather than shipping a fixed set of states. A lifecycle is a
finite state machine with optional conditions gating entry into a state, support
for automatic transitions, and manual transitions by users. Most documents will
have no lifecycle at all.

Deferred, with one guard that applies now: this **editorial** lifecycle is a
separate axis from the **processing** lifecycle in CDM §10.1
(`editing → published → rendered → line_file_generated → doc-process pipeline`).
Both use the word `published`, and they are not the same thing — the editorial
lifecycle's publish event *triggers* the processing one. Keeping them as two
axes means a user-defined FSM can be added later as document metadata plus its
own definition tables, without disturbing the processing path or the AST.

## D7 — Ontology is deferred

Ontology association is a large topic in its own right and is deferred. It will
need to connect to the existing object model (ADR 2026070101, object-centric
design) rather than introducing a parallel one.

# References
[1] KnowledgeStore/doc-repo/specs/202607/2026072501-spec-canonical-doc-model.md

[2] KnowledgeStore/doc-repo/adrs/202606/2026061801-adr-document-review.md

[3] KnowledgeStore/doc-repo/adrs/202607/2026072602-adr-cdm-editor-scope.md

[4] KnowledgeStore/doc-repo/adrs/202607/2026070101-adr-object-centric-design.md
