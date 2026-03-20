Use superpowers to create a canvas page using Svelte, save it in ChenWeb/web/src/lib/components/shared-ui/canvas-01.svelte and add a menu Tools->Flow to ChenWeb/web/src/routes/home3.

Refer to the image for reference.

# Design Guidelines

- A Flow is made of nodes and edges
- A node can have zero or more Input Connectors and zero or more Output Connectors
- There is a Node Pallete that lists all the available nodes
- The Node Pallete by default is opened in the left panel, just under the menu item. But one can drag the pallete out as a floating panel.
- The Node Pallete should have a button to create a new node
- Nodes are saved in the database
- A node is defined by a set of attributes, which include input connectors, output connectors and additional attributes as needed
- Node attributes are shown and edited in the right panel
- Users drag-and-drop a node from the pallete to the canvas
- When clicking on a node, the right panel shows the node's attributes and its connectors. Input connectors are shown on the left side of the node and output connectors are shown on the right side of the node.
- A floating mini-tool bar is shown on top of the node when a node is selected. The content (or icons) in the mini-tool bar is defined by the selected node.
- Typical edit functions, such as undo, redo, etc., should be available
- When the canvas starts, it should show a default flow. Users can create a flow and save it as the default flow. If no default flow is configured, show an empty canvas.
- It should show all the flows created in the system and all Flow Templates. When users want to create a new flow, users can select one from the existing flows or the flow templates. 
- Users can select a flow and save it as a flow template
- Below are the minimal node set:
    - AI Assistant: edit prompts and select model
    - Text: as input or output
    - File: as input or output
    - Document: as input or output
    - Media: as input or output
    - Tool: tool-use
    - MCP: connect to an MCP server
    - Rule
    - Coding Assistant
    - HTTP Request
    - GIT
- Flows can be shared or private, which is set by flow creators.
- There should be a button "Settings" that configures the canvas. It should contain:
    - Edge types: Curve, Broken Lines, Round Broken Lines, Straight Lines
    - Grid Resolution: default to 20 px
    - Snap Flag: default to true
- When drag-and-drop a node to the canvas, the upper-left corner of the node should be at the point at which the node is dropped, subject to snapping to grid, if snapping is turned on

## Development Requirements
- Frontend is Svelte (ChenWeb/web). 
- Backend is Go (ChenWeb/server).

# REST API and Backend
- Create all the needed REST API endpoints
- Create all the handlers with stubs only