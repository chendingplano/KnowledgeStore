# ChenWeb `home3/knowledge` Window

## Overview

`ChenWeb::/home3/knowledge` is the main Knowledge System window inside the `home3` workspace. It consolidates a set of document-analysis and knowledge-exploration tools behind a dedicated left-side menu, so users can stay inside one window while switching between related knowledge workflows.

At a high level, this window is designed to:

1. Manage and select a knowledge store.
2. Browse imported source documents.
3. Inspect document details, structure, metrics, and chunks.
4. Explore higher-level knowledge views such as summaries, semantic graphs, and compliance provisions.

The route is implemented at:

- `ChenWeb/web/src/routes/home3/knowledge/+page.svelte`

## Main Layout

The window is a two-column shell:

- Left: a fixed-width knowledge menu
- Right: the active content workspace

On smaller screens, the layout stacks vertically, with the menu moving above the content area.

The menu header labels the window as **Knowledge System** and describes it as a place for documents, metrics, and structure. The right-hand side swaps in the selected section inline instead of opening separate routes for each subsection.

## Active Knowledge Store Model

The `Knowledge Stores` section is the entry point and control center for the rest of the window.

- Users see knowledge stores as cards.
- Clicking a card makes that store the active knowledge store.
- Most other sections in `/home3/knowledge` operate against that active store.
- If no active store is selected, store-dependent sections show a blocking empty state with a button that sends the user back to `Knowledge Stores`.

The active store state is held in:

- `ChenWeb/web/src/lib/components/home3/knowledge-store-state.svelte.ts`

This state keeps:

- `activeStoreId`
- `activeStore`

It is shared across the sections rendered within the knowledge window.

## Menu Structure

The current menu structure in `+page.svelte` includes these primary sections:

1. `Knowledge Stores`
2. `Documents`
3. `Document Details`
4. `Document Structure`
5. `Metrics`
6. `Chunks`
7. `Document Summaries`
8. `Semantic Web`
9. `Compliance Provisions`

The last three are collapsible parent items with child pages:

### Document Summaries

- `Summary Graph`
- `Summary Tree`

### Semantic Web

- `Semantic Web`
- `Document Semantic Tree`

### Compliance Provisions

- `Provision Web`
- `Provision Tree`

There are also placeholder sections currently marked under construction:

- `References`
- `Formulas`
- `Tables`
- `Quotations`
- `Case Studies`
- `Workflow`
- `Product and Parts`

## Section Responsibilities

### 1. Knowledge Stores

This page acts as both:

- a management dashboard for knowledge stores
- a selector for the active knowledge store

Users can create, edit, delete, refresh, and visually browse stores. Card content emphasizes:

- store identity and purpose
- source configuration
- operational status

Main component:

- `ChenWeb/web/src/lib/components/home3/knowledge-store-view.svelte`

Related spec:

- `KnowledgeStore/DevDocuments/Specs/spec-page-knowledge-store.md`

### 2. Documents

This section is rendered by `KbImportView` and is intended for imported-record review and document ingestion workflows.

Main component:

- `ChenWeb/web/src/lib/components/home3/kb-import-view.svelte`

### 3. Document Details

This page is the document-centric inspection workspace. It combines a reusable record browser with metadata and source/document viewing.

Notable features:

- left-side `kb.inputs` browser
- record retrieval and search
- editable metadata sections
- PDF or source-file viewing

Main component:

- `ChenWeb/web/src/lib/components/home3/inputs-mgmt-view.svelte`

### 4. Document Structure

This section lets users inspect parsed document hierarchy and corrected structure lines. It is one of the pages built on the shared `kb.inputs` browser pattern.

**Window Layout**
Layout:

```text
┌───────────────────────────────────-──────────────────────────-─────────┐
│  Menu    | Record List | LINES [Filter] [Settings] |   PDF Viewer     │
│          |             |                            | Selected Line    │
|───────────────────────────────-──--────────────────────────────────────|
│  ...                   |          |                            |       │
│  Document Structure    | <record> | <Line>                     |       │
│                        |          | <Line>                     | PDF   │
│                        |          |                            | View  │
│  ...     |             |          |                            | er    │
└────────────────────────────--──────────────────────────────────────────┘
```

The "Selected List" has two controls:
- "Filter" pulldown
- "Settings" button

The "Filter" pulldown menu has:
- Headings: show heading lines only
- Paragraphs: show paragraph lines only
- Lists: show list-item lines only
- Tables: show table lines only
- Formulas: show formula lines only

Main component:

- `ChenWeb/web/src/lib/components/home3/doc-structure-view.svelte`

### 5. Metrics

This section manages extracted metrics tied to documents in the active knowledge store.

Main component:

- `ChenWeb/web/src/lib/components/home3/metric-mgmt-view.svelte`

### 6. Chunks

This section browses fixed-size chunk output and related document/PDF context.

Layout:

```text
┌──────--─────────────────────────-──────────────────────────────────┐
│  Menu    | Record List | CHUNKS  |      PDF Viewer                 │
│  ...     |             |         |                                 │
│  Chunks  | <record>    | <chunk> |      PDF Viewer                 │
│          | <record>    | <chunk> |      PDF Viewer                 │
│          |             |         |                                 │
│  ...     |             |         |                                 │
└────────────────────────────--──────────────────────────────────────┘
```

Main component:

- `ChenWeb/web/src/lib/components/home3/chunk-mgmt-view.svelte`

Implementation note:

- The page now calls `listKbChunks(...)` from `ChenWeb/web/src/lib/services/kbService.ts`.
- That API is served by `ChenWeb/server/api/kbhandler/topic_chunks_handler.go` through `ListChunks`.
- The `Chunks` page now reads only `.chunks` artifacts.
- It no longer enriches chunk entries from `.topics`.
- It no longer falls back to legacy `topics.txt`.
- The `.chunks` parser is tolerant of blank separator lines between chunk entries and only treats explicit `lines:` rows as chunk content. This avoids parser drift where an `overlap:` row could previously be misread as a chunk payload.

Debug logging:

- Backend: `ListChunks` logs the chunk records it is returning, including `seqno`, `line_tokens`, span counts, and topic text.
- Frontend service: `listKbChunks(...)` logs the fetched response in the browser console.
- Frontend view: `chunk-mgmt-view.svelte` logs the chunk array it receives before rendering.

Behavior rule:

- `.chunks` is the source of truth for the `Chunks` list.
- `.topics` belongs to topic extraction and should be surfaced through `Semantic Web`, not through `Chunks`.

Chunk detail sidebar:

- The right-side `Chunk Details` sidebar is document-oriented rather than topic-oriented.
- `Source Lines` are shown as page-aware continuous ranges, for example `P8:183-192`, instead of one chip per individual line.
- `Bounding Boxes` appears before `Content Lines`.
- `Content Lines` uses the remaining sidebar height and scrolls internally, while leaving space near the bottom for PDF paging controls.

Example:

- For `record_id = 93`, the early chunk sequence should be shown exactly from the `.chunks` file:
  - chunk 1: `overlap: []`, `lines: [2-6, 8-10, 28-34, 37-43]`
  - chunk 2: `overlap: [40-43]`, `lines: [44, 46-55, 57]`
  - chunk 3: `overlap: [54-55, 57]`, `lines: [58-75, 77-81]`
  - chunk 4: `overlap: [77-81]`, `lines: [82-91, 93-96]`
  - chunk 5: `overlap: [94-96]`, `lines: [97-115]`

### 7. Document Summaries

This group contains two related but distinct summary views:

- `Summary Graph`: category-first summary exploration
- `Summary Tree`: document-centric summary browsing over `kb.inputs`

Main components:

- `ChenWeb/web/src/lib/components/home3/summary-graph-view.svelte`
- `ChenWeb/web/src/lib/components/home3/summary-tree-view.svelte`

Related design doc:

- `ChenWeb/docs/superpowers/specs/2026-05-01-document-summaries-design.md`

### 8. Semantic Web

This group provides topic-oriented knowledge exploration:

- `Semantic Web`: category-first graph view
- `Document Semantic Tree`: document-centric topic browser

Main components:

- `ChenWeb/web/src/lib/components/home3/topic-graph-view.svelte`
- `ChenWeb/web/src/lib/components/home3/topic-tree-view.svelte`

### 9. Compliance Provisions

This group mirrors the semantic-web pattern, but for compliance provisions:

- `Provision Web`: graph-first provision view
- `Provision Tree`: document-centric provision browser

Implementation detail:

- `Provision Web` reuses `TopicGraphView` with provision-specific loaders.
- `Provision Tree` reuses `TopicTreeView` with provision-specific item loading and its own browser instance key.

## Shared Interaction Pattern

Several sections reuse the same left-side `kb.inputs` browsing workflow. This shared browser supports:

- record ID retrieval
- search dialog
- filter reset
- pagination
- width resizing
- per-view persisted settings
- automatic first-record selection

This abstraction is implemented by:

- `ChenWeb/web/src/lib/components/home3/kb-input-record-browser.svelte`

It is used by pages such as:

- `Document Details`
- `Metrics`
- `Document Structure`
- `Chunks`
- `Summary Tree`
- `Document Semantic Tree`
- `Provision Tree`

Related implementation note:

- `KnowledgeStore/DevDocuments/ImplDocs/impl-record-list.md`

## Rendering Logic

The knowledge window does not rely on a separate route per subsection. Instead, the route-level page keeps an `activeSection` state and conditionally renders the matching component inline.

This gives the window a desktop-workspace feel:

- the menu stays visible
- the active context stays inside one shell
- switching tools is fast and predictable

## Current Product Shape

Today, `ChenWeb::/home3/knowledge` is best understood as a unified knowledge-workbench window rather than a single-purpose page. It already supports both low-level document inspection and higher-level knowledge views, while leaving room for future extractors such as references, formulas, tables, quotations, and case studies.

In practice, the workflow is:

1. Open `Knowledge Stores`
2. Select the active store
3. Move into document or knowledge sections
4. Explore the same underlying corpus through different lenses

## Key Files

- `ChenWeb/web/src/routes/home3/knowledge/+page.svelte`
- `ChenWeb/web/src/lib/components/home3/knowledge-store-view.svelte`
- `ChenWeb/web/src/lib/components/home3/knowledge-store-state.svelte.ts`
- `ChenWeb/web/src/lib/components/home3/knowledge-sections.js`
- `ChenWeb/web/src/lib/components/home3/kb-input-record-browser.svelte`
- `KnowledgeStore/DevDocuments/Specs/spec-page-knowledge-store.md`
- `KnowledgeStore/DevDocuments/ImplDocs/impl-record-list.md`
- `ChenWeb/docs/superpowers/specs/2026-05-01-document-summaries-design.md`
