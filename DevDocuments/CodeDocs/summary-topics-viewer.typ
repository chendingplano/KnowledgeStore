#import "@preview/diagraph:0.3.6"
#import "@preview/oxdraw:0.1.0": *

#set heading(numbering: "1.")
#set quote(block: true)
#show quote: set pad(x: 1em)
#show raw.where(block: true): block.with(fill: luma(240), inset: 1em, radius: 0.5em, width: 100%)

#show heading: it => {
  set text(fill: blue) if it.level == 1
  if it.numbering != none {
    counter(heading).display(it.numbering)
    h(0.5em) // Adds a little gap after the number
  }
  it.body
}

#set page(
  numbering: "1 of 1",
  footer: context {
    line(length: 100%)
    "Summaries and Topics"
    h(1fr)
    counter(page).display("1/1", both: true)
  },
)

#show heading.where(level: 1): set text(size: 18pt)
#show heading.where(level: 1): it => pad(top: 4pt, it)

#show heading.where(level: 2): set text(size: 14pt)
#show heading.where(level: 2): it => pad(top: 4pt, it)

#show heading.where(level: 3): set text(size: 14pt)
#show heading.where(level: 3): it => pad(top: 4pt, it)

#let frontmatter = (
  FileType: "typst",
  FileID: "file-2026050401",
  FileName: "summary-topics-viewer.typ",
  ArtifactType: "Self-Written",
  DocTime: "2026/05/04"
)

= How to Turn Information Block Positions
```text
File: topic-graph-view.svelte:

  gapLeftX: TOPIC_HOVER_GAP_LEFT_X,
	gapRightX: TOPIC_HOVER_GAP_RIGHT_X,
	gapTopY: TOPIC_HOVER_GAP_TOP_Y,
	gapBelowY: TOPIC_HOVER_GAP_BELOW_Y,

summary-graph-view.svelte:	

  const SUMMARY_HOVER_GAP_LEFT_X = -30;
  const SUMMARY_HOVER_GAP_RIGHT_X = 150;
  const SUMMARY_HOVER_GAP_TOP_Y = 0;
  const SUMMARY_HOVER_GAP_BELOW_Y = 70;
```

Currently, both the Summaries and Topics share the same code to calculate the positions of the 
information block when the mouse hovers over a node. the implementation depends on the node shape 
(small circles or info blocks).

When we have time, we need to modularize this code to be independent of the node shape and size.

= Control Parent-Child Distance for Horizontal Trees
The parent-child distance is now controlled by these constants:

```ts
File: summary-graph-view.svelte
const SUMMARY_PARENT_CHILD_DISTANCE = 300;

File: topic-graph-view.svelte
const TOPIC_PARENT_CHILD_DISTANCE = 300;
```

Those feed into the fixed-width calculation here:

```ts
let fixedTreeLayoutWidth = $derived(
	getFixedTreeLayoutWidth({
		visibleDepth: visibleTreeDepth,
		parentChildDistance: SUMMARY_PARENT_CHILD_DISTANCE
	})
);
```

And ECharts receives that computed width here:

```ts
{
	type: 'tree',
	data: [root],
	top: '2%',
	left: '2%',
	bottom: '2%',
	width: fixedTreeLayoutWidth,
	layout: 'orthogonal',
	orient: 'LR',
	...
}
```

The helper that converts “desired parent-child distance” into ECharts layout width is 

```js
File: graph-layout-utils.js

export function getFixedTreeLayoutWidth({
	visibleDepth,
	parentChildDistance,
	hiddenRootDepth = 1,
	minWidth = parentChildDistance
}) {
	const depth = Math.max(1, Math.floor(Number(visibleDepth) || 0) + hiddenRootDepth);
	const requestedWidth = depth * Math.max(1, Number(parentChildDistance) || 1);
	return Math.max(minWidth, requestedWidth);
}
```

So the practical knobs are `SUMMARY_PARENT_CHILD_DISTANCE` and `TOPIC_PARENT_CHILD_DISTANCE`.

= Expand/Collapse
This is handled by:
```text
Normal path: handleChartNodeClick(...)
Fallback: handleZrClickFallback(...)

summary-graph-view-svelte:
	function toggleNodeAndMaybeReveal(nodeId: string) {
		console.log('toggleNodeAndMaybeReview (MID_26050406)');
		const node = nodes.find((candidate) => candidate.id === nodeId);
		const shouldReveal = Boolean(node && node.childIds.length > 0 && !node.expanded);
		nodes = toggleNodeExpanded(nodes, nodeId);
		if (shouldReveal) scheduleExpandedNodeReveal(nodeId);
		else setTimeout(syncMiniViewport, 0);
	}
```

`toggleNodeAndMaybeReveal(...)` is the function that actually performs the expand/collapse state change for a node and, 
if it was just expanded, recenters the viewport so the new children are visible.

- `const node = nodes.find(...)`
  Looks up the current node object from the in-memory `nodes` array.
- `const shouldReveal = Boolean(node && node.childIds.length > 0 && !node.expanded);`
  Decides whether this action is an expansion that needs follow-up panning. It is `true` only when:
  - the node exists,
  - it has children,
  - and it is currently collapsed.
  If the node is already expanded, the click is treated as a collapse, so no reveal is needed.
- `nodes = toggleNodeExpanded(nodes, nodeId);`
  This is the actual state mutation. `toggleNodeExpanded(...)` from [summary-graph-state.js:74](/Users/cding/Workspace/ChenWeb/web/src/lib/components/home3/summary-graph-state.js:74) returns a new `nodes` array where just that node’s `expanded` flag is flipped.
- `if (shouldReveal) scheduleExpandedNodeReveal(nodeId);`
  If we just expanded the node, wait for the chart to re-render and then try to pan the graph so the children are brought into view.
- `else setTimeout(syncMiniViewport, 0);`
  If this was a collapse, there’s nothing new to reveal; we just refresh the mini-map viewport state after the UI settles.

The nearby helpers complete the story:
- `scheduleExpandedNodeReveal(...)` at [summary-graph-view.svelte:994](/Users/cding/Workspace/ChenWeb/web/src/lib/components/home3/summary-graph-view.svelte:994) stores the node id and defers the reveal until after rendering.
- `revealPendingExpandedChildren()` at [summary-graph-view.svelte:986](/Users/cding/Workspace/ChenWeb/web/src/lib/components/home3/summary-graph-view.svelte:986) consumes that pending id.
- `revealExpandedChildren(...)` at [summary-graph-view.svelte:956](/Users/cding/Workspace/ChenWeb/web/src/lib/components/home3/summary-graph-view.svelte:956) measures the rendered child positions and pans the chart if needed.

So the short version is: this function toggles the node’s `expanded` state immediately, then optionally schedules a camera move so the newly shown children don’t appear offscreen.