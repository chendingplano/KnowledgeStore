# ChenWeb `home3/knowledge` Window

## Overview

`ChenWeb::/home3/knowledge` is the main Knowledge System window inside the `home3` workspace. It consolidates a set of document-analysis and knowledge-exploration tools behind a dedicated left-side menu, so users can stay inside one window while switching between related knowledge workflows.

At a high level, this window is designed to:

1. Manage and select a knowledge store.
2. Ingest source documents (Injestion → Upload Files).
3. Inspect document metadata, structure, processing output, and metrics (Document Wiki, Document Processing).
4. Explore higher-level knowledge views such as subject summaries, topic graphs, and compliance provisions.

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
2. `Injestion`
3. `Subject Wiki`
4. `Document Processing`

All collapsible parent items with child pages:

All root-level parents default to **collapsed**. The active section does not require expanding a parent first — clicking a parent in icon-only (collapsed sidebar) mode navigates to its first child.

### Injestion

- `Upload Files`

### Subject Wiki

- `Document Metadata`
- `Document Structure`
- `Document Tree`
- `Subject Wiki`
- `Document Topic Tree`
- `Topic Wiki`
- `Metrics`
- `Scene Blocks`
- `Provision Tree`
- `Provision Wiki`
- `References` *(under construction)*
- `Formulas` *(under construction)*
- `Tables` *(under construction)*
- `Quotations` *(under construction)*
- `Case Studies` *(under construction)*
- `Workflow` *(under construction)*
- `Product and Parts` *(under construction)*

### Document Processing

- `Document Chunking`

## Section Responsibilities

### Knowledge Stores

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

### Injestion → Upload Files

This section is rendered by `KbImportView` and is intended for imported-record review and document ingestion workflows.

Main component:

- `ChenWeb/web/src/lib/components/home3/kb-import-view.svelte`

### Document Wiki → Document Metadata

This page is the document-centric inspection workspace. It combines a reusable record browser with metadata and source/document viewing. (Previously named "Document Details".)

Notable features:

- left-side `kb.inputs` browser
- record retrieval and search
- editable metadata sections
- PDF or source-file viewing

Main component:

- `ChenWeb/web/src/lib/components/home3/inputs-mgmt-view.svelte`

### Document Structure

This section lets users inspect parsed document hierarchy and corrected structure lines. It is one of the pages built on the shared `kb.inputs` browser pattern.

**Window Layout**
Layout:

```text
┌─────────────────────────────────-────────-──────-──────-─────────────────────────────-─────-─────────┐
│  Menu              | Record List | LINES [Filter] [Settings]  |  Selected Line  |     PDF Viewer     │
|─────────────────────────────-──--───────────────-────────────-──────-──────-────────────────-────────|   
│ ...                |             |                            |                 │                    |
│ Document Structure | <record>    | <Line>                     |                 │                    |
│                    |             | <Line>                     |                 │    PDF Viewer      |
│                    |             | <Line>                     |                 │                    |
│                    |             | ...                        |                 │                    |
│ ...                |             |                            |                 │                    |
└─────────────────-──────-─────────────────--─────────────-────────────────────────────────────────────┘
```

The "LINES" panel has two controls:
- "Filter" pulldown
- "Settings" button

The "Filter" pulldown menu has:
- Headings: show heading lines only
- Paragraphs: show paragraph lines only
- Lists: show list-item lines only
- Tables: show table lines only
- Formulas: show formula lines only

The records in the "LINES" panel show lines from the line file, one line per record.
Each record has two operations "Edit" and "Delete", shown as icons. The "Delete" action
uses a trashcan icon instead of an `x`. Clicking the "Edit" icon convert the display into
the edit mode. Clicking the "Delete" icon deletes the line from the line file. Confirm the
deletion with user before actually delete it.

Main component:

- `ChenWeb/web/src/lib/components/home3/doc-structure-view.svelte`

### Metrics

This section manages extracted metrics tied to documents in the active knowledge store.

Main component:

- `ChenWeb/web/src/lib/components/home3/metric-mgmt-view.svelte`

### Scene Blocks

This section browses the event-driven **scene blocks** an LLM extracts from each
document. A scene block is a self-contained narrative unit (who acts, what
triggers the scene, how it unfolds, how it resolves) stored as one row in the
`kb.scene_objects` table.

**Data source**

- Table: `kb.scene_objects` (one row per scene block, keyed by
  `input_record_id` + `object_id`).
- Produced by the `generate-scene-blocks` doc-processing processor.
- The `Scene Blocks` page is read-only over this table.

**Window Layout**

The page uses a **master–detail inline-accordion** layout. There is no
separate "Selected Block" column: selecting a scene block expands it in place
within the Scene Blocks list, and the right column shows the source document
for context.

```text
┌──────────────-──────────────-──────────────────────────────-─────────────┐
│  Menu      | Record List | Scene Blocks (inline accordion)  | Source Doc  │
|────────────-─────────────-──────────────────────────────────-────────────|
│ ...        |             | ▸ <scene-block>                  |             │
│ Metrics    | <record>    | ▾ <scene-block>  EXPANDED        |  PDF Viewer │
│ Scene      |             |    Cast / Setup / Flow /         |  + "Scene   │
│  Blocks    | <record>    |    Resolution / Links & evidence  |   context" │
│ Provision  |             | ▸ <scene-block>                  |   sidebar   │
│ ...        |             | ...                              |             │
└────────────-─────────────-──────────────────────────────────-────────────┘
```

- **Record List**: the shared `kb.inputs` record browser (search, retrieve,
  filter, paginate, resize). Selecting a record loads its scene blocks.
- **Scene Blocks**: every scene block for the selected record as a collapsed
  row showing index, scene-type pill, title, summary, keyword chips, and a
  confidence meter (color-banded: high / mid / low). One row expands at a
  time.
- **Expanded detail** renders the scene as a narrative arc; empty groups are
  hidden so sparse blocks stay clean:
  - **Cast** — actors, resources (typed entity chips)
  - **Setup** — preconditions, triggers, states
  - **Flow** — actions (numbered sequence), decisions, constraints
  - **Resolution** — outcomes, failure modes, root causes, resolutions
  - **Links & evidence** — relationships, source evidence, and a
    "retrieval discriminators" disclosure (advanced, collapsed by default)
  - A mono footer shows `scene_id`, `event_id`, and the extraction model.
- **Source Document**: the record's PDF with a "Scene context" sidebar
  recapping the expanded block. Scene blocks carry no page coordinates, so
  the PDF is not auto-highlighted; the sidebar surfaces the block's
  `source_refs` as evidence locators instead.

**Endpoint, service, component**

- API: `GET /api/v1/kb/scene-blocks?input_record_id=N`
  - Handler: `ChenWeb/server/api/kbhandler/scene_blocks_handler.go`
    (`ListSceneBlocks`), registered in `ChenWeb/server/api/routes.go`.
  - JSONB columns are passed through verbatim as the LLM-extracted structure.
- Frontend service: `listKbSceneBlocks(...)` in
  `ChenWeb/web/src/lib/services/kbService.ts`.
- Main component:

  - `ChenWeb/web/src/lib/components/home3/scene-blocks-view.svelte`

### Document Wiki → Subject Wiki (formerly Summary Graph)

Category-first summary exploration. (Previously named "Summary Graph" under "Document Summaries".)

Main component:

- `ChenWeb/web/src/lib/components/home3/summary-graph-view.svelte`

Related design doc:

- `ChenWeb/docs/superpowers/specs/2026-05-01-document-summaries-design.md`

### Document Wiki → Document Tree (formerly Summary Tree)

Document-centric summary browsing over `kb.inputs`. (Previously named "Summary Tree" under "Document Summaries".)

Main component:

- `ChenWeb/web/src/lib/components/home3/summary-tree-view.svelte`

### Document Wiki → Topic Wiki and Document Topic Tree

This group provides topic-oriented knowledge exploration. (Previously named "Semantic Web" group.)

Layout:

```text
┌──────--─────────────────────────-─────────────────────────────────────┐
│  Menu    | Record List | Topic List | Selected Topic |   PDF Viewer   │
│  ...     |             |            |                                 │
│  Chunks  | <record>    | <chunk>    |  <topic>       |   PDF Viewer   │
│          | <record>    | <chunk>    |  <topic>       |                │
│          |             |            |                                 │
│  ...     |             |            |                                 │
└────────────────────────────--─────────────────────────────────────────┘
```

- `Topic Wiki`: category-first graph view (previously "Semantic Web")
- `Document Topic Tree`: document-centric topic browser (previously "Document Semantic Tree"). Refer to 'KnowledgeStore/Capsules/coding-capsules/chunking-fix-size/+CAPSULE.md' for topics.

Main components:

- `ChenWeb/web/src/lib/components/home3/topic-graph-view.svelte`
- `ChenWeb/web/src/lib/components/home3/topic-tree-view.svelte`

#### Topic Wiki (formerly Semantic Web)

A topic has one or more category paths. Category paths are mapped to file paths under
the directory TOPIC_TREE_ROOT_DIR. If a directory has a 'topics.txt' file, the file
lists all the topics that belong to this file path, which is also a category path.
Below is an example of 'topics.txt':
```text
record_id: 99,
topic_type: "procedure"
lines: [405-406]
topic_keywords: [腰背肌力, 测试方法, 背力计, 上拉]
topic: "腰背肌力测试方法：自然站立，调节握柄高度，双手紧握把柄，直臂上拉背力计"

<next topic, if any>
```

For more information about topics, refer to 'KnowledgeStore/Capsules/coding-capsules/chunking-fix-size/+CAPSULE.md'. 

### Document Wiki → Provision Wiki and Provision Tree

These pages mirror the topic-web pattern for compliance provisions and now live inside Document Wiki. (Previously they were grouped under "Compliance Provisions".)

- `Provision Wiki`: graph-first provision view (renamed from "Provision Web")
- `Provision Tree`: document-centric provision browser

Implementation detail:

- `Provision Wiki` reuses `TopicGraphView` with provision-specific loaders.
- `Provision Tree` reuses `TopicTreeView` with provision-specific item loading and its own browser instance key.

### Document Chunking

This section browses document chunks and related document/PDF context.

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

- `Document Metadata` (formerly Document Details)
- `Metrics`
- `Document Structure`
- `Document Chunking` (formerly Chunks)
- `Document Tree` (formerly Summary Tree)
- `Document Topic Tree` (formerly Document Semantic Tree)
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
