# Overview

The tree-graph-view ('impl-tree-graph-view.md') has a toolbar. This document is about the implementation
of the toolbar.

# Tool: Settings
This tool lets users edit the settings.
- Horizontal Expand Depth (expand_depth): an integer, default to 5

# Tool: Expand Selected Node
This tool expands the selected node horizontally, up to `expand_depth` deep.
* Disable this tool if no node is selected
* When clicking, it expands the selected node, up to `expand_depth` deep.

# Tool: Collapse Selected Node
This tool collapse the selected node. If no node is selected, the selected node is not
expanded or it has no children, this tool is disabled.

When clicking, it collapse the selected tool.

# Tool: Export to png
It exports the canvas to a png file. 
