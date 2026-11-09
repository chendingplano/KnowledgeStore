---
Date: 2026/11/09
Contributors: ChatGPT, Chen Ding
---

# Declarative Dragging — Explanation and Analysis

Declarative Dragging (D2) is a new approach to implementing drag-and-drop interactions in user interfaces. It was introduced by Joshua Horowitz, Andrew Blinn, and Jeffrey Heer, and received a Best Paper Award at UIST 2026.

The authors implemented the approach in an open-source JavaScript library called Dragology, primarily targeting SVG-based web interfaces.

The central idea is surprisingly simple:

> Instead of programming how an object moves when dragged, developers specify what application states the object can reach. The framework automatically figures out the dragging behavior.

This is an interesting extension of declarative programming: it separates the application's semantic model from the mechanics of user interaction.

## 1. The problem it solves

Conventional approach: imperative dragging, requires developers typically implement:

- Pointer events (`pointerdown`, `pointermove`, `pointerup`).
- Dragged-element coordinates and offsets.
- Hit testing and drop-zone detection.
- Valid and invalid target positions.
- Reordering of objects in the application model.
- Animations, snapping, and transitions.
- Cancellation and restoring the original state.

Even though the underlying operation might be as simple as moving an element between two arrays, the interaction code can become substantial.

In declarative Dragging approach, instead, the developer specifies the possible outcomes:

```
const initial = {
  rows: [
    ["A", "B"],
    ["C", "D"]
  ]
};

const targets = [
  // Keep original arrangement
  { rows: [["A", "B"], ["C", "D"]] },

  // Exchange A and B
  { rows: [["B", "A"], ["C", "D"]] },

  // Move A into second row
  { rows: [["B"], ["A", "C", "D"]] }
];
```

The developer defines the valid model states. Dragology takes responsibility for turning those possibilities into an interactive drag-and-drop experience.

Note that this example is illustive only. In dragology, developers need to generate
candidates through coding.

The important difference is that the developer describes the semantics of the operation, not its geometric implementation.

## 2. How Declarative Dragging actually works

The key technique is called speculative rendering.

As an example, given a list of objects, we want to drag-and-reorder the objects.

- Extract A's position in each rendering
- Derive drop zones and animated transitions
- Interactive dragging
- Select a valid target state and commit it

The process consists of five main steps.

**Step 1 — Render the current state**

The application has a rendering function:

$$V=R(S)$$

where $S$ is the application state, $R$ is the rendering function, and $V$ is the resulting view tree.

**Step 2 — Generate possible target states**

When the user starts dragging A, the application provides the states that can legally result from dragging A.

**Step 3 — Render those states speculatively**

Dragology calls the rendering function on each candidate state, without committing those states to the actual application.

**Step 4 — Extract positions**

For every speculative rendering, Dragology identifies where A would appear. These positions help define possible drag destinations.

**Step 5 — Synthesize the interaction**

Dragology uses the resulting geometric information to produce drop zones, visual feedback, and animated transitions. When the user completes the drag, the appropriate model state is selected.

The clever part is Step 3: the framework uses the existing rendering function as a geometry engine.

Developers do not have to independently calculate where A should appear after every possible transformation. They have already defined that behavior through their normal renderer.

## 3. The second innovation: Composable Dragging

Speculative rendering solves the question of where objects can go, but it doesn't completely define how dragging should feel.

For example, should an object follow the pointer continuously? Should it snap immediately to a valid position? Should it move only along one axis?

Dragology provides a small domain-specific language (DSL) for composing these behaviors.

The paper gives examples such as:

| Operator            | Purpose                                                                 |
| ------------------- | ----------------------------------------------------------------------- |
| `d.closest(states)` | Select the target state whose dragged element is closest to the pointer |
| `.withFloating()`   | Make the dragged element follow the pointer                             |
| `d.between(...)`    | Constrain movement to the region between target positions               |
| `d.vary(...)`       | Continuously change a numeric model parameter                           |
| `.whenFar(...)`     | Switch to another dragging behavior when sufficiently far from a target |

For example, the paper uses:

```
d.closest(newStates).withFloating()
```

This combines two behaviors: selecting the nearest valid destination and allowing the object to float with the pointer during the drag.

Another example is:

```
snapping.whenFar(free)
```

This combines snapping near valid targets with free movement farther away.

These operations are composable, so developers can build sophisticated interactions without implementing each interaction from scratch.

## 4. A particularly interesting feature: continuous dragging

So far, our examples involve discrete states: A can occupy position 1, 2, or 3.

But suppose we have a scheduling interface and want to change a meeting's start time by dragging its left endpoint.

There are infinitely many possible start times, so enumerating every state is impractical.

Dragology supports continuous model parameters using `d.vary()`.

The paper provides an example resembling:

```
d.vary(
  state,
  param("meetings", i, "start"),
  {
    constraint: (s) => [
      lessThan(0, s.meetings[i].start),
      lessThan(
        s.meetings[i].start,
        s.meetings[i].end - MIN_LENGTH
      )
    ]
  }
)
```

Here the developer specifies the variable that can change and the constraints it must satisfy.

Dragology adjusts the parameter to minimize the distance between the pointer and the rendered handle, subject to the constraints.

This is significant because the interaction is expressed in terms of semantic parameters and constraints, not pixel coordinates.

For example, if the developer later changes the scale of the timeline or the visual appearance of the meeting bars, the same drag specification can continue to work.

## 5. How Dragology is implemented

The implementation uses TypeScript, React, and SVG.

Its internal architecture has three important abstractions:

- DragSpec: Declarative description of possible interactions
- Compile
- DragBehavior: Function of pointer position
- Evaluate each frame
- Preview view: What the user sees
- Drop state: What would be committed

When a drag begins, Dragology constructs a `DragSpec`, represented internally as an abstract syntax tree. It compiles this specification into a `DragBehavior`.

On each animation frame, the behavior takes the pointer position and produces both the current visual preview and the model state that would be committed if the pointer were released.

Dragology also interpolates SVG views to animate transitions, including attributes such as positions, colors, transforms, and paths.&#x20;

This architecture resembles a small interpreter or compiler: developers provide a high-level specification, and the engine translates it into runtime behavior.

## 6. Benefits and limitations

| Aspect                 | Assessment                                                                                        |
| ---------------------- | ------------------------------------------------------------------------------------------------- |
| Development complexity | Significantly reduces manual geometry and event-handling code for supported interactions          |
| Separation of concerns | Strong: application semantics remain separate from interaction mechanics                          |
| Expressiveness         | Supports discrete reordering, continuous parameter manipulation, and composed behaviors           |
| Maintainability        | Rendering changes often require fewer corresponding changes to drag logic                         |
| Performance            | Speculative rendering has a cost, especially with many candidate states or expensive views        |
| Applicability          | Particularly suitable for diagrams, visual editors, mathematical tools, and structured interfaces |
| Framework support      | Prototype implementation is oriented toward React and SVG                                         |

One limitation deserves emphasis: the developer must still define which states are valid. Declarative dragging does not automatically discover the application's business rules.

Also, speculative rendering is not free. For large state spaces, generating and rendering all candidate states can become expensive. Continuous parameter manipulation introduces optimization and constraint-solving considerations.

The paper's evaluation involved hands-on interviews with 13 interface developers. Participants reported concise code and polished interactions, but also difficulties reasoning about state spaces. This is encouraging qualitative evidence, not a large-scale performance or productivity benchmark.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://declarative-dragging.github.io\&sz=32)

Declarative Dragging

## 7. Why this matters beyond drag-and-drop

I think the most important contribution is the architectural principle behind the technique:

Interaction can be derived from a declarative state-transition model rather than programmed independently.

Traditional declarative UI frameworks already implement:

$$\text{State} \xrightarrow{\text{Render}} \text{View}$$

Declarative Dragging adds a complementary mechanism:

$$\text{Valid future states} \xrightarrow{\text{Render + Geometry}} \text{Interaction}$$

This is a meaningful extension of declarative UI design.

For your Web Page Interpreter (WPI) concept, the underlying principle is especially relevant. A data-driven page description could specify not only its structure and appearance but also valid state transformations. A generic interpreter could then synthesize interactions from those transformations.

For example, a declarative page specification might contain:

```
{
  "component": "sortable-list",
  "data": ["A", "B", "C"],
  "interaction": {
    "type": "drag",
    "operation": "reorder",
    "constraint": "same-list",
    "behavior": ["closest", "floating"]
  }
}
```

This is an illustrative WPI-style design, not Dragology's actual format.

The application-specific part is the data and transformation rules; the generic interpreter handles pointer tracking, target geometry, previews, and animation.

There is an important distinction, though: Dragology still expects developers to supply model-state generators and rendering functions in code. It does not itself make entire applications pure data. Adapting its principles to WPI would require a declarative language for transformations and constraints.

## 8. Resources

- [Research paper — Declarative Dragging (PDF)](https://declarative-dragging.github.io/D2.pdf?utm_source=chatgpt.com)
- [Dragology — GitHub repository](https://github.com/declarative-dragging/dragology?utm_source=chatgpt.com)
- [Interactive demos](https://declarative-dragging.github.io/dragology/?utm_source=chatgpt.com)

My overall assessment: The most valuable idea is not the drag-and-drop library itself, but the use of speculative rendering to infer interaction geometry from semantic state transitions. It demonstrates how an interpreter can derive sophisticated UI behavior from a much smaller, higher-level specification.&#x20;