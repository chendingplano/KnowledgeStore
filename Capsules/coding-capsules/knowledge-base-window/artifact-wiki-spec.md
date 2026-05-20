# Artiface Wiki Design

**Date:** 2026-05-24 \
**Project:** `ChenWeb`  

## Purpose

Provide a graph-first workspace for browsing and editing the artifacts stored under `ARTIFACT_WEB_DIR`.

## Menu
ChenWeb::/home3/knowledge, "Wiki => Artifact Wiki"

## Main Layout

The page is a tabbed workspace.

- The first tab is always `Artifact Graph`
- The `Artifact Graph` tab cannot be closed
- Additional tabs are created dynamically when the user opens a category-path view

### Artifact Graph Tab
Within the fixed `Artifact Graph` tab:

- The main surface is a category graph or horizontal tree chart rooted at `ARTIFACT_WEB_DIR`
- Nodes represent categories derived from directory structure under `ARTIFACT_WEB_DIR`
- The graph is the control surface for navigation and editing

### Category Tabs

When a user single clicks a node, expand the node, if it has child nodes. If the node is 
already expanded, it collapses the node.

When a user double clicks a node:

- The system computes the category path relative to `ARTIFACT_WEB_DIR`
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
- show artifacts

In early phases, these may be backed by mock state and mock dialogs, but the full interaction cycle must be testable.

## Category Tab Layout

When `show artifacts` is invoked for a category path, the corresponding category tab opens a split layout,
which has three panels:
- Chart Panel (Left Panel)
- Information Panel (Middle Pannel)
- PDF Display Panel (Right Panel)
- There is a slider between the Chart Panel and the Information Panel, and the Information Panel and
  the PDF Panel to adjust their widths.

### Artifact Table Panel (Left Panel)
- It shows artifacts as a scrollable, sectioned table. Each artifact group (such as 'summaries',
  'topics', etc.) is rendered as a collapsible section.
- A section header shows a colored indicator dot, the group name, and the item count badge.
  Clicking the header toggles the section open/collapsed. All sections are expanded by default.
- Expanded sections list every artifact as a row. Each row shows the artifact label; if the label
  is truncated by the column width, hovering reveals the full label via a tooltip.
- Clicking an artifact row selects it, shows its details in the Information Panel, and highlights
  the source page in the PDF Display Panel.

#### Summary Artifact Nodes
Summaries ae listed in "summaries.txt", which is a list of summary IDs.
Use summary IDs as the artifact node's label.

#### Topic Artifact Nodes
Topics are listed in "topics.txt". Use topic description (truncate it with '...' when it is too long)
as the artifact node's label.

#### Metric Artifact Nodes
Topics are listed in "metrics.txt". Use metric name as the artifact node's label.

#### Scene Artifact Nodes
Scenes are listed in "scenes.txt". Use scene name as the artifact node's label.

#### Provisions Artifact Nodes
Provisions are listed in "provisions.txt". Use provision name as the artifact node's label.

### Information Panel (Middle Panel)
- This panel shows the details about the selected artifact.
- There is a slider between 

### PDF Display Panel (Right Panel)
Reuse the PDF Display (refer to [2]).

## Implementations
For the implementation document, refer to [3].
Below are related files:
- ChenWeb/web/src/lib/components/home3/artifact-wiki-view.svelte
- ChenWeb/web/src/lib/components/home3/tree-graph-filter-state.js
- ChenWeb/web/src/lib/components/home3/tree-graph-view.svelte
- ChenWeb/web/src/lib/components/home3/tree-graph-filter-state.test.js

## References
[1] KnowledgeStore/Capsules/coding-capsules/knowledge-base-window/+CAPSULE.md \
[2] KnowledgeStore/Capsules/coding-capsules/pdf-viewer/+CAPSULE.md \
[3] KnowledgeStore/Capsules/coding-capsules/knowledge-base-window/artifact-wiki-impl.md