# Document Summaries Design

**Date:** 2026-05-01  
**Project:** `ChenWeb`  
**Route:** `web/src/routes/home3/knowledge/+page.svelte`  
**Source Brief:** `KnowledgeStore/DevDocuments/PageDesigns/spec-page-summary.md`

## Goal

Add a new `Document Summaries` section inside `ChenWeb/home3/knowledge` with two child pages:

- `Summary Graph`: a category-first summary workspace for exploring and editing the summary knowledge base
- `Summary Tree`: a document-centric summary browser over `kb.inputs`

The implementation should preserve the existing `home3` shell, active knowledge-store workflow, and PDF viewing patterns. Delivery may be phased, but every phase must be testable end-to-end with mocks for incomplete backend behavior.

## Integration Model

Inside the existing knowledge left menu:

- Add a new parent menu item: `Document Summaries`
- Add two child menu items beneath it:
  - `Summary Graph`
  - `Summary Tree`

This should use a nested-menu interaction, not a flat single-page tab switcher. The goal is to make the two summary workflows explicit and discoverable.

## Page 1: Summary Graph

### Purpose

Provide a graph-first workspace for browsing and editing the summary knowledge base stored under `SUMMARY_TREE_DIR`.

### Main Layout

The page is a tabbed workspace.

- The first tab is always `Summary Graph`
- The `Summary Graph` tab cannot be closed
- Additional tabs are created dynamically when the user opens a category-path summary view

Within the fixed `Summary Graph` tab:

- The main surface is a category graph or horizontal tree chart rooted at the summary knowledge base
- Nodes represent summary categories derived from directory structure under `SUMMARY_TREE_DIR`
- The graph is the control surface for navigation and editing

### Category Path Tabs

The examples `Health` and `Agent` are not fixed tabs. They stand in for category-path tabs.

When a user clicks a node action to show summaries:

- The system computes the category path relative to `SUMMARY_TREE_DIR`
- If a tab for that category path does not exist, create a new tab
- If the tab already exists, do not create a duplicate; focus/open the existing tab instead
- If the rendered tab title is shortened because the path is long, hovering should reveal the full path

### Graph Actions

The graph workspace must support the following actions:

- expand node
- collapse node
- rename node
- edit category metadata
- delete node
- add node
- merge nodes
- split node
- show summaries

In early phases, these may be backed by mock state and mock dialogs, but the full interaction cycle must be testable.

### Category Summary Tab Layout

When `show summaries` is invoked for a category path, the corresponding category tab opens a split layout:

- Left panel: summary list from `summaries.txt`
- Right panel: PDF display for the currently selected summary
- A resize handle between the two panels adjusts width

Summary cards in the left panel should display:

- PDF file name
- summary keywords
- summary text

Clicking a summary should:

- load the corresponding PDF if it is not already active
- move the PDF viewer to the correct page/anchor for that summary

## Page 2: Summary Tree

### Purpose

Provide a document-centric browser of summaries based on `kb.inputs`, rather than category hierarchy.

### Main Layout

This page should feel like a sibling of `Document Structure`, not a clone of `Summary Graph`.

The page uses a two-panel layout:

- Left panel:
  - search area
  - result list
- Right panel:
  - tabbed detail area with PDF display as the primary surface

### Search Area

The search area should be modeled after the existing `Document Details` search experience in `web/src/lib/components/home3/inputs-mgmt-view.svelte`.

That means reusing the same search-dialog structure and search language where appropriate:

- identity filters
- document metadata filters
- parser / operation / status filters
- create / modify time window filters
- store-scope awareness through the active knowledge store

The summary-specific implementation may extend this with summary-related filters later, but the base interaction pattern should feel familiar to users of `Document Details`.

### Result List

The list should support two presentation modes:

- one-line-per-record compact rows
- richer block cards similar to `Document Details`

Selecting a document should update the right panel. Selecting a summary inside the document context should move the PDF viewer to the relevant page.

## Data Model Expectations

The design assumes the summary knowledge base is represented by directories and files under `SUMMARY_TREE_DIR`:

- category directory
- `metadata.txt`
- optional `summaries.txt`
- nested category directories

The category metadata payload is expected to contain:

- `desc`
- `category_type`
- `confidence`
- `keywords`
- `create_time`

The summary list for a category comes from `summaries.txt`, where each line is a summary ID.

## Delivery Phases

### Phase 1: Testable Mocked Workspaces

- Add nested menu support for `Document Summaries`
- Add the two new pages: `Summary Graph` and `Summary Tree`
- Build the real layouts and interactions with mock-backed data sources
- Make all editing actions visible and testable through mocked dialogs and mocked optimistic updates
- Make category-path tabs open/focus correctly
- Make the `Summary Tree` page searchable and navigable with mock results
- Use mocked PDF target jumps when live summary-to-PDF mapping is not ready

### Phase 2: Live Read Integration

- Replace graph mocks with real reads from `SUMMARY_TREE_DIR`
- Replace summary-list mocks with real `summaries.txt` reads
- Replace `Summary Tree` mocks with real `kb.inputs`-backed search and summary loading
- Wire live tab state and real PDF navigation

### Phase 3: Live Write Integration

- Wire rename
- wire metadata editing
- wire add
- wire delete
- wire merge
- wire split

This phase needs strong validation, conflict handling, and refresh rules because graph mutations reshape the category hierarchy.

### Phase 4: Hardening

- polish empty, loading, and error states
- keyboard navigation
- long-path truncation and hover behavior
- dark/light verification
- resizing verification
- regression coverage for tab reuse, category mutations, and PDF jumps

## Component Boundaries

Recommended frontend decomposition:

- `document-summaries-nav` responsibility inside the knowledge route or a small nav helper
- `summary-graph-view.svelte`
- `summary-graph-tabs.svelte`
- `summary-category-tab.svelte`
- `summary-tree-view.svelte`
- `summary-tree-search-dialog.svelte`
- `summary-summary-card.svelte`
- summary-specific service helpers in `web/src/lib/services/kbService.ts` or a nearby summary service module

The graph page and tree page should share summary-domain service helpers, but not force the same UI structure.

## Error Handling

- Missing active knowledge store should follow the existing knowledge-section pattern
- Missing `summaries.txt` should be treated as an empty summary list, not a fatal page error
- Missing or malformed category metadata should surface as non-blocking warnings where possible
- Duplicate tab creation must be prevented by category-path keying
- Merge and split actions should require explicit confirmation and clear post-action refresh behavior

## Testing Strategy

Each phase must be testable.

Minimum expectations:

- route and nested-menu behavior work on desktop and mobile
- `Summary Graph` fixed tab is always present and cannot be closed
- clicking `show summaries` creates a category-path tab exactly once and focuses it thereafter
- summary selection updates the PDF panel target
- `Summary Tree` search mirrors the `Document Details` search interaction model
- mocked edit flows are fully usable before live backend wiring

## Recommendation

Use the nested-menu plus dedicated-workspace approach:

- `Document Summaries`
  - `Summary Graph`
  - `Summary Tree`

This matches the target interaction model, keeps category-first and document-first tasks separate, and creates clean phase boundaries for mocked-to-live delivery.
