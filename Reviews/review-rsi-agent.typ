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
    "Review - RSIAgent"
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

#let callout(title, body) = block(
  fill: rgb("#f3f6fa"),                       // light blue-grey background
  stroke: (left: 3pt + rgb("#4b6b88")),       // accent bar on the left
  inset: (left: 12pt, right: 10pt, top: 8pt, bottom: 8pt),
  radius: 3pt,
)[
  *#title*

  #body
]

#let frontmatter = (
  file_type: "typst",
  logical_name: "review-rsi-agent",
  file_id: "2026100601",
  source: "",
  content_type: "review",
  document_date: "2026/10/06",
  keywords: [RSI, recursive self improvement],
)

= Overview
*Highlights*
- scaling experience rather thanscaling parameters
- it is an agent system and its external memory that
  improve throughout the usage
- conditions → actions → consequences
- knowledge does not have to push to the model
- model (general knowledge) + memory (context and local knowledge)
- causal/conditional knowledge
- curriculum agent, actor agent and verifier agent

The paper, *“RSIAgent: Autonomous Exploration for Recursive Self-improvement 
in New Environments,”* proposes a way for an AI agent to become substantially 
better at operating in a new environment *without retraining or changing the 
underlying model weights*. The central idea is what the authors call 
*“scaling experience” rather than scaling parameters*: let the agent actively 
explore an environment, discover how it works, verify what it learns, and 
accumulate that knowledge into reusable memory. The authors describe this 
as *recursive self-improvement*, although importantly it is the *agent 
system and its external memory that improve, not the neural network itself*. 
[ArxivLens](https://arxivlens.com/paperview/details/rsiagent-autonomous-exploration-for-recursive-self-improvement-in-new-environments-9949-b1c894c3?utm_source=chatgpt.com)

RSIAgent uses three main roles: 
- a *Curriculum Agent* decides what should be explored next, 
- an *Actor Agent* actually performs tasks and experiments in the environment, 
- a *Verifier Agent* checks whether the claimed outcomes are correct. 


The useful experiences are then consolidated into memory, especially 
relationships of the form *conditions → actions → consequences*. 
For example, rather than merely remembering “clicking button X worked,” the 
system tries to retain knowledge such as “when the application is in state S, 
action A causes result R, but under condition C it fails.” This makes the 
memory closer to an accumulated collection of environment-specific operational 
knowledge than a simple log of previous trajectories. 
[ArxivLens](https://arxivlens.com/paperview/details/rsiagent-autonomous-exploration-for-recursive-self-improvement-in-new-environments-9949-b1c894c3?utm_source=chatgpt.com)

A particularly interesting part is its *broad-then-deep exploration strategy*. 
Broad exploration runs multiple explorations to discover the overall structure 
of the environment—available tools, workflows, interfaces, common operations 
and failure modes. Deep exploration subsequently concentrates on difficult or 
uncertain regions, deliberately looking for *edge cases, hidden constraints, 
boundary conditions and previously unknown causal dependencies*. The loop is 
therefore roughly *explore → execute → verify → consolidate memory → use the 
improved memory to guide further exploration*. That recursive loop is where 
the paper gets the “RSI” terminology. Once exploration is finished, the 
resulting memory can be frozen and supplied to an agent performing downstream 
tasks; no fine-tuning is required. 
[ArxivLens](https://arxivlens.com/paperview/details/rsiagent-autonomous-exploration-for-recursive-self-improvement-in-new-environments-9949-b1c894c3?utm_source=chatgpt.com)

The reported results are strong. On *OSWorld 2.0*, the authors report an offline 
partial score increasing from *71.97% to 78.98%*, with binary accuracy increasing 
from *37.80% to 42.68%* in the reported aggregate. On *Agents’ Last Exam*, the 
paper also reports substantial improvements. The authors claim that applying RSIAgent 
to models such as Kimi-K3 and GLM-5.3 can push them beyond some frontier closed 
models under their evaluation setup. These comparisons should be interpreted 
cautiously, however: an independent paper summary notes that some OSWorld aggregate 
entries retain baseline scores and that external model comparisons do not necessarily 
use perfectly matched evaluation protocols. 
[Fyan](https://hf-p-cfw.fyan.top/papers/2609.15364?utm_source=chatgpt.com)

The most important idea, in my view, is therefore *not the multi-agent architecture 
itself*. Curriculum/actor/verifier decomposition is fairly natural. The interesting 
proposition is that a capable pretrained model may be missing *environment-specific 
experience rather than intelligence*. Instead of encoding that experience back into 
model weights through RL or fine-tuning, RSIAgent turns experience into a persistent, 
verified external knowledge base. In simplified form:

```text
   LLM + autonomous exploration 
       + verification 
       + accumulated environment memory 
   → increasingly capable agent.
```

This is quite relevant to the direction you've been considering with *SemOS*: knowledge 
does not necessarily have to be pushed into model parameters, nor does everything have 
to be handled as conventional query→RAG retrieval. RSIAgent instead treats external 
knowledge as something an agent can *actively construct, organize, revisit, and 
exploit through exploration*. The particularly relevant piece for SemOS is its 
attempt to preserve *causal/conditional knowledge rather than merely documents or 
embeddings*—essentially learning “under conditions X, doing Y produces Z.” That 
is quite close to the causal and exploratory layer you've been considering above 
your L0/L1 knowledge. 
[ArxivLens](https://arxivlens.com/paperview/details/rsiagent-autonomous-exploration-for-recursive-self-improvement-in-new-environments-9949-b1c894c3?utm_source=chatgpt.com)

== Curriculum Agent
The *Curriculum Agent is essentially an LLM acting as an adaptive task generator*. 
It does not learn parameters, train the Actor, or directly modify the memory. 
Its job is to answer:

#callout(
  "Curriculum Agent",
  [
*“Given what the agent currently knows and what happened in previous experiments, 
what experiment should we run next to learn something useful?”*
]
)

This is more interesting than simply generating random practice tasks.
Testbots should adopt this model: instead of try randomly, let LLMs
decide what to try next. The big difference between random and smart
tries is that smart tries is much slower and costly.

*1. What information does it use?*

The Curriculum Agent is given context such as the *target task/query, 
current accumulated memory, previous exploration outcomes, and diagnosed 
uncertainties/failures*. From these, it proposes an exploration task 
designed to acquire missing information. 
[ArXivSignals](https://arxivsignals.io/papers/2609.15364?utm_source=chatgpt.com)

Conceptually:

```text
target task
    +
current memory
    +
previous experiments/results
    +
known uncertainties
        │
        ▼
 Curriculum LLM
        │
        ▼
next exploration task
```

For example, suppose the eventual FreeCAD task requires creating a complex 
object. The memory already says:

```text
Create cylinder:
  Part.makeCylinder(radius, height)

Fuse objects:
  obj1.fuse(obj2)
```

But an Actor attempt fails when combining objects.

The Curriculum Agent might therefore generate a much smaller exploratory task:

```text
> Create two intersecting cylinders and determine under what geometric 
  conditions `fuse()` succeeds or fails.
```

The point isn't to solve the original task again. It is to *isolate an 
uncertainty*.

*2. Broad exploration works differently*

During *Broad Recursive Self-exploration (BRS)*, the Curriculum Agent 
tries to maximize *coverage*. It proposes several diverse projects 
covering different capabilities, workflows, prerequisites, and possible 
failure modes. The reference setup uses roughly eight projects, with up 
to four running concurrently. 
[Arietiform](https://www.arietiform.com/application/nph-tsq.cgi/su/20/https/www.alphaxiv.org/abs/2609.15364?utm_source=chatgpt.com)

You can think of it as:

```text
"I know almost nothing about FreeCAD."

Curriculum
   ├── Task 1: create primitive objects
   ├── Task 2: transform/rotate objects
   ├── Task 3: boolean operations
   ├── Task 4: modify object properties
   ├── Task 5: save/export files
   ├── Task 6: ...
   └── Task 8: ...
```

Actors execute those projects, Verifiers check the results, and the verified experiences are consolidated into shared memory.

So BRS is approximately:

*exploration for breadth / coverage.*

It is explicitly *not* just random wandering. [Pith Science](https://pith.science/paper/2609.15364?utm_source=chatgpt.com)

### 3. Deep exploration is where it becomes more interesting

During *Deep Recursive Self-exploration (DRS)*, curriculum generation becomes *target-conditioned and sequential*.

Suppose the target task is:

```text
Create a hollow cylinder with a 2-mm wall.
```

The Actor tries it using existing memory.

Suppose it fails.

The Actor/Verifier evidence might reveal:

```text
Problem:
Boolean cut failed when inner cylinder
was exactly aligned with outer cylinder.
```

Now the Curriculum Agent generates a focused experiment:

```text
Experiment:
Test boolean subtraction using inner cylinders
with several heights and offsets.
```

Actor executes it.

Verifier discovers:

```text
inner.height == outer.height     → failure
inner.height > outer.height      → success
```

Memory can now acquire something like:

```text
FreeCAD Boolean Cut

Condition:
  Inner cutting solid should extend beyond
  the outer solid.

Action:
  inner_height = outer_height + margin

Consequence:
  Boolean subtraction succeeds reliably.
```

Then the *new memory and results feed the next curriculum decision*. [alphaXiv](https://www.alphaxiv.org/abs/2609.15364?utm_source=chatgpt.com)

Thus:

```text
Curriculum
    ↓
Experiment
    ↓
Actor
    ↓
Environment
    ↓
Verifier
    ↓
experience
    ↓
Memory update
    │
    └──────────────┐
                   ↓
              Curriculum
                   ↓
           next experiment
```

That's the "recursive" part.

### 4. It doesn't only investigate failures

This is an important subtlety.

If an experiment *fails*, the Curriculum Agent can propose another task designed to discover the missing prerequisite or failure condition.

But even if it *succeeds*, the Curriculum Agent can generate a *contrastive/stress-test* task to determine whether the apparent rule generalizes. [Arietiform](https://www.arietiform.com/application/nph-tsq.cgi/su/20/https/www.alphaxiv.org/abs/2609.15364?utm_source=chatgpt.com)

For example:

```text
Observed:
A + B → success
```

Rather than immediately concluding:

```text
A always causes B
```

Curriculum might ask:

```text
What happens with:

A + different geometry?
A + different parameter?
A + different application state?
A + boundary value?
```

That allows the system to discover:

```text
A + C1 → B
A + C2 → B
A + C3 → failure
```

and therefore learn the more useful rule:

```text
if condition != C3:
    A → B
```

This is why the paper emphasizes discovering *hidden constraints, boundary conditions, and causal dependencies*, rather than merely accumulating successful trajectories. [Pith Science](https://pith.science/paper/2609.15364?utm_source=chatgpt.com)

### 5. So there isn't a sophisticated "curriculum algorithm"

This distinction is important.

I would *not* interpret Curriculum Agent as something analogous to reinforcement-learning curriculum optimization, active-learning acquisition functions, Bayesian experimental design, etc.

It is fundamentally:

*LLM + carefully constructed context/prompt → next useful experiment.*

The architecture provides the discipline around it:

```text
                   ┌───────────────┐
                   │ Curriculum LLM│
                   └───────┬───────┘
                           │
                    "Try experiment X"
                           ↓
                   ┌───────────────┐
                   │     Actor     │
                   └───────┬───────┘
                           │
                        execute
                           ↓
                    Environment
                           │
                           ↓
                   ┌───────────────┐
                   │   Verifier    │
                   └───────┬───────┘
                           │
                  grounded evidence
                           ↓
                       Memory
                           │
                           └────→ Curriculum
```

The intelligence of curriculum generation therefore comes largely from the *LLM's existing reasoning capability*. RSIAgent supplies the iterative experimental framework around that reasoning.

This also explains something important about the paper's claim of "self-improvement": *the Curriculum Agent itself isn't becoming a better model.* What improves is the information available to it and the Actor:

```text
same LLM + better accumulated experience
              ↓
better questions/experiments
              ↓
better memory
              ↓
better subsequent experiments
```

That distinction is, in my view, central to understanding what RSIAgent actually contributes. [github.com](https://github.com/razor-ai/rsiagent?utm_source=chatgpt.com)
