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

=== Broad Recursive Self-exploration (BRS)

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

Actors execute those projects, Verifiers check the results, and the verified 
experiences are consolidated into shared memory.

So BRS is approximately:

*exploration for breadth / coverage.*

It is explicitly *not* just random wandering. 
[Pith Science](https://pith.science/paper/2609.15364?utm_source=chatgpt.com)

=== Deep Recursive Self-exploration (DRS)

Deep exploration is where it becomes more interesting.
During *Deep Recursive Self-exploration (DRS)*, curriculum generation 
becomes *target-conditioned and sequential*.

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

Then the *new memory and results feed the next curriculum decision*. 
[alphaXiv](https://www.alphaxiv.org/abs/2609.15364?utm_source=chatgpt.com)

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

=== It doesn't only investigate failures

This is an important subtlety.

If an experiment *fails*, the Curriculum Agent can propose another 
task designed to discover the missing prerequisite or failure 
condition.

But even if it *succeeds*, the Curriculum Agent can generate a 
*contrastive/stress-test* task to determine whether the apparent 
rule generalizes. 
[Arietiform](https://www.arietiform.com/application/nph-tsq.cgi/su/20/https/www.alphaxiv.org/abs/2609.15364?utm_source=chatgpt.com)

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

This is why the paper emphasizes discovering *hidden constraints, 
boundary conditions, and causal dependencies*, rather than merely 
accumulating successful trajectories. 
[Pith Science](https://pith.science/paper/2609.15364?utm_source=chatgpt.com)

=== There isn't a sophisticated "curriculum algorithm"

This distinction is important.

I would *not* interpret Curriculum Agent as something analogous to 
reinforcement-learning curriculum optimization, active-learning 
acquisition functions, Bayesian experimental design, etc.

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

The intelligence of curriculum generation therefore comes largely from the 
*LLM's existing reasoning capability*. RSIAgent supplies the iterative 
experimental framework around that reasoning.

This also explains something important about the paper's claim of "self-improvement": 
*the Curriculum Agent itself isn't becoming a better model.* What improves is 
the information available to it and the Actor:

```text
same LLM + better accumulated experience
              ↓
better questions/experiments
              ↓
better memory
              ↓
better subsequent experiments
```

That distinction is central to understanding what RSIAgent actually contributes. 
[github.com](https://github.com/razor-ai/rsiagent?utm_source=chatgpt.com)

== Actor

The *Actor is the agent that actually operates the environment*.

Conceptually:

```text
Curriculum:
"Explore how to create a hollow cylinder in FreeCAD."
                     │
                     ▼
                  Actor
        ┌────────────┴────────────┐
        │                         │
   Persistent memory       Environment state
        │                         │
        └────────────┬────────────┘
                     ▼
                 reasoning
                     ▼
             Python / Bash actions
                     ▼
                  FreeCAD
                     ▼
             resulting state
```

The Actor receives the *task/project, current environment observations, 
and current persistent memory*. It then reasons about what actions to 
take and generates executable *Python or Bash programs* to interact with 
the target software/environment. Those programs can manipulate applications, 
inspect files or interface state, and create artifacts. 

It is also the component that turns verified experience into persistent memory.

[GitHub](https://github.com/razor-ai/rsiagent?utm_source=chatgpt.com)

*The Actor has two distinct jobs*

This distinction is important. It is not merely an executor.

*First, it executes the task.* It observes the environment, consults previously 
accumulated memory, decides on actions, executes them, observes the results, 
and can iteratively continue acting. The memory might contain previously 
discovered procedures, scripts, constraints, and failure lessons. 
[GitHub](https://github.com/AetherLabsAI/RSIAgent?utm_source=chatgpt.com)

For example, suppose memory already contains:

```text
FreeCAD / Hollow Cylinder

1. Create outer cylinder.
2. Create inner cylinder.
3. Make inner cylinder slightly taller.
4. Boolean-cut inner from outer.

Important:
Inner cylinder should extend beyond outer cylinder
to avoid unreliable coplanar Boolean operations.
```

The Actor can use that directly when solving a new task instead of 
rediscovering the procedure.

So at task time it resembles a normal coding/computer-use agent:

```text
task
  ↓
read memory
  ↓
observe environment
  ↓
reason
  ↓
generate action/program
  ↓
execute
  ↓
observe
  ↓
reason
  ↓
...
```

This is why the memory can improve performance without changing model weights.

=== Knowledge Engineer - Actor self-learns from the experience

After execution, the *Verifier independently examines the resulting 
environment*. Importantly, the Verifier does not see the Actor's private 
reasoning or memory; it judges the actual result and returns something 
such as PASS, FAIL, or unresolved, together with grounded feedback. 
[GitHub](https://github.com/AetherLabsAI/RSIAgent/blob/main/docs/ARCHITECTURE.md?utm_source=chatgpt.com)

Then control effectively comes back to the Actor:

```text
Actor executes
      ↓
environment changes
      ↓
Verifier independently checks
      ↓
PASS / FAIL + evidence
      ↓
Actor
      ↓
distills experience
      ↓
updates memory
```

This second responsibility is especially important: *the same Actor that 
generated the experience is responsible for distilling and reconciling it 
into canonical memory*. The Curriculum Agent does not write that memory, 
and the Verifier does not write it either. 
[GitHub](https://github.com/razor-ai/rsiagent?utm_source=chatgpt.com)

Suppose the Actor originally believed:

```text
Boolean cut:
inner.height = outer.height
```

It tries that, and the Verifier finds the resulting geometry invalid.

The Actor experiments again and eventually discovers:

```text
inner.height = outer.height + margin
```

works reliably.

It can reconcile this with existing memory:

```text
OLD:
To hollow a cylinder:
inner.height = outer.height

NEW:
To hollow a cylinder:
inner.height > outer.height

Reason:
Avoid coincident/coplanar boundary surfaces.

Verification:
Inspect resulting solid and confirm expected cavity.
```

So memory is not simply an append-only collection of trajectories.

*This is a critical design choice.*

RSIAgent is trying to convert:

```text
raw experience
```

into:

```text
generalizable operational knowledge
```

rather than storing:

```text
Task #123:
I clicked A.
Then clicked B.
Then ran command C.
It worked.
```

The desired memory instead captures things such as:

```text
Procedure
---------
How to accomplish X

Conditions
----------
When procedure X applies

Constraints
-----------
X fails when C

Recovery
--------
If C occurs, do Y

Verification
------------
Check Z to confirm success
```

The paper explicitly describes memory updates as potentially containing 
*new information, revised procedures, qualifications, or corrections to 
earlier entries*. 
[Arietiform](https://www.arietiform.com/application/nph-tsq.cgi/su/20/https/www.alphaxiv.org/abs/2609.15364?utm_source=chatgpt.com)

That makes the Actor partly an *executor* and partly a *knowledge engineer*.

=== Actor during broad vs. deep exploration

Its mechanics are essentially the same in both phases, but the source and 
character of its assignments differ.

During *Broad Recursive Self-exploration*, Curriculum generates multiple 
diverse projects. Several Actor instances can execute them in parallel, all 
starting from the *same immutable memory snapshot*:

```text
             Memory M0
            /    |    \
           /     |     \
       Actor1 Actor2 Actor3
          ↓      ↓      ↓
        Exp1   Exp2   Exp3
```

Their experiences are verified independently. After the entire wave finishes, 
the experiences are *consolidated sequentially* into canonical memory. 
[GitHub](https://github.com/razor-ai/rsiagent?utm_source=chatgpt.com)

That detail prevents one concurrently running Actor from seeing partially learned 
knowledge from another Actor.

Deep exploration is different:

```text
Memory M0
   ↓
Actor → experience
   ↓
Verifier
   ↓
Actor consolidates
   ↓
Memory M1
   ↓
Curriculum chooses next experiment
   ↓
Actor → experience
   ↓
Verifier
   ↓
Memory M2
   ...
```

Here each verified experience can affect the next experiment. 
[GitHub](https://github.com/AetherLabsAI/RSIAgent?utm_source=chatgpt.com)

=== Test time

Once exploration finishes, the memory is *frozen*.

The Curriculum Agent disappears from the execution loop, and memory updates 
are disabled. The Actor simply solves the actual benchmark task using the 
accumulated memory:

```text
                 Frozen Memory
                       │
                       ▼
Task ──────────────→ Actor
                       │
                       ▼
                   actions
                       │
                       ▼
                  environment
                       │
                       ▼
                   Verifier
```

Thus evaluation tests whether the acquired knowledge is actually reusable 
rather than allowing the system to continue learning from the evaluation 
task. [GitHub](https://github.com/razor-ai/rsiagent?utm_source=chatgpt.com)

=== Important insight

There is actually nothing especially exotic about the Actor's underlying 
intelligence. It is essentially a *normal LLM-based tool-using/coding agent 
with persistent external memory*.

RSIAgent's contribution is the machinery surrounding it:

```text
          chooses experience
Curriculum ───────────────→ Actor
                              │
                              │ acts
                              ▼
                         Environment
                              │
                              ▼
                           Verifier
                              │
                         grounded result
                              │
                              ▼
                            Actor
                              │
                         distillation
                              ▼
                            Memory
                              │
                              └────→ future Actor
```

And this exposes the most interesting connection to *SemOS*: the idea of an agent 
exploring a file-based knowledge space is quite similar to the Actor. But RSIAgent 
adds an important second responsibility: *after exploration, don't merely retain 
what the agent found; have it distill the exploration into reusable knowledge that 
changes subsequent exploration.*

In other words, the interesting loop for SemOS could be:

```text
    Explore 
    → obtain evidence 
    → verify 
    → generalize 
    → write knowledge 
    → explore again using the improved knowledge base.
```

That is substantially more interesting than simply *LLM → search/explore → answer*, 
and it is probably the part of RSIAgent most worth examining for your architecture.

== Verifier

The *Verifier is an independent LLM agent whose job is to inspect the actual
environment and decide whether the Actor really accomplished the task*. The 
key word is *independent*: it deliberately does *not* see the Actor's reasoning 
or private memory. 
[GitHub](https://github.com/razor-ai/rsiagent?utm_source=chatgpt.com)

Conceptually:

```text
Task ────────────────┐
                     ▼
Actor ──actions──→ Environment
                     │
                     │ actual resulting state
                     ▼
                  Verifier
                     │
              inspect independently
                     │
              ┌──────┼─────────┐
              ▼      ▼         ▼
             PASS   FAIL    UNVERIFIED
```

=== Verifier derives the requirements itself

This is a particularly important implementation detail. The Actor does *not* 
tell the Verifier:

> "I created the cylinder, checked its radius, and everything is correct."

Instead, the Verifier gets essentially the *original task plus access to the 
resulting machine/environment*. It independently decomposes the task into 
requirements. The implementation explicitly instructs it to derive a *full 
requirement inventory* itself. 
[GitHub](https://github.com/AetherLabsAI/RSIAgent/blob/main/core/verifier.py?utm_source=chatgpt.com)

Suppose the task is:

```text
> Create a red cylinder of radius 10 mm and height 30 mm named `Pipe`, 
  and save it as `part.FCStd`.
```

The Verifier might internally derive:

```text
Requirements:

1. FreeCAD document exists
2. Object exists
3. Object is a cylinder
4. radius == 10 mm
5. height == 30 mm
6. color == red
7. object name == "Pipe"
8. part.FCStd exists
9. saved file contains the expected object
```

It then tries to establish evidence for *each requirement*.

=== Investigate the environment

The Verifier isn't simply another LLM call that reads the 
Actor's transcript. It is an *agentic inspector* that can perform 
read-only investigation.

For structural facts, it can inspect things such as files, application 
state, object properties, coordinates, values, attributes, and 
generated artifacts. For visual requirements, it can use visual 
observations. 
[GitHub](https://github.com/AetherLabsAI/RSIAgent/blob/main/core/verifier.py?utm_source=chatgpt.com)

For example:

```text
Verifier
   │
   ├── inspect file system
   │       └── part.FCStd exists?
   │
   ├── inspect FreeCAD document
   │       ├── object name?
   │       ├── radius?
   │       └── height?
   │
   └── inspect rendered object
           └── actually red?
```

The implementation makes an interesting distinction between *structural evidence* 
and *visual evidence*. If the requirement is structural, inspect the underlying 
values. If the requirement concerns what the rendered result actually looks like, 
inspect the rendered result. If rendering isn't possible, the Verifier tries to 
derive measurable properties from the underlying file instead. 
[GitHub](https://github.com/AetherLabsAI/RSIAgent/blob/main/core/verifier.py?utm_source=chatgpt.com)

This makes the Verifier closer to a *testing/inspection agent* than an LLM critic.

=== Deliberately tries to falsify a PASS

This is probably the most interesting part.

Before returning `PASS`, the Verifier is explicitly instructed to ask:

```text
> What is the strongest plausible way this result could still be wrong?
```

It then tries to investigate that possibility. 
[GitHub](https://github.com/AetherLabsAI/RSIAgent/blob/main/core/verifier.py?utm_source=chatgpt.com)

So rather than:

```text
find supporting evidence
        ↓
      PASS
```

the logic is closer to:

```text
derive requirements
       ↓
collect evidence
       ↓
looks correct?
       ↓ yes
try to find a counterexample / violation
       ↓
    still correct?
       ↓
      PASS
```

That is much closer to *falsification* than ordinary LLM self-evaluation.

=== Isolation from Actor

This addresses a familiar agent problem.

Suppose the Actor reasons incorrectly:

```text
"The task asks for diameter 10 mm."

therefore

radius = 10 mm
```

It executes that and then reports:

```text
"I correctly created the requested cylinder."
```

If you give the Actor's reasoning to another LLM and ask whether the 
solution is correct, that LLM can inherit the Actor's mistaken 
interpretation.

RSIAgent instead does:

```text
Actor:
"The radius should be 10."

         X reasoning hidden

Verifier:
reads original task independently

"Wait — the task says diameter=10,
 therefore radius should be 5."

Inspect actual object:
radius = 10

→ FAIL
```

The repository describes this explicitly as a structural independence 
mechanism: a fresh verifier call sees the task and live machine, *not 
the Actor's reasoning, assumptions, evidence, or memory*. 
[GitHub](https://github.com/AetherLabsAI/RSIAgent/blob/main/core/verifier.py?utm_source=chatgpt.com)

=== PASS, FAIL, and UNVERIFIED matter

The Verifier doesn't force everything into true/false. It can return roughly:

```text
PASS
    Evidence establishes the requirements.

FAIL / WRONG
    Evidence establishes a material violation.

UNVERIFIED
    Available evidence cannot establish correctness.
```

That third state is important for learning. 
[Emergent Mind](https://www.emergentmind.com/papers/2609.15364?utm_source=chatgpt.com)

Suppose the Actor claims:

```text
"This procedure reliably works for files > 2 GB."
```

but the current experiment only used a 10-MB file.

The Verifier shouldn't conclude:

```text
PASS: works for >2 GB
```

nor:

```text
FAIL: doesn't work for >2 GB
```

It should effectively say:

```text
UNVERIFIED:
Current evidence does not establish
the >2 GB claim.
```

That prevents uncertain observations from becoming durable "facts" in memory.

=== Failure is still useful for learning

A `FAIL` doesn't mean the experience is discarded.

Imagine:

```text
Curriculum:
"Test whether method X works with an empty spreadsheet."

Actor:
tries X

Verifier:
FAIL
because formula references disappear
when the sheet contains no data.
```

That failure is valuable evidence:

```text
Method X

Works when:
    sheet contains data

Failure condition:
    empty sheet

Observed consequence:
    formula references disappear
```

The Actor can then incorporate the verified failure condition into memory. 
RSIAgent therefore learns from both successful and unsuccessful experiments. 
[GitHub](https://github.com/razor-ai/rsiagent?utm_source=chatgpt.com)

=== The complete loop is therefore slightly subtler than it first appears

The three agents aren't simply:

```text
Curriculum = generate tasks
Actor      = execute tasks
Verifier   = score tasks
```

Their division of responsibility is:

```text
                   What should we
                    learn next?
                        │
                        ▼
                  CURRICULUM
                        │
                  experiment
                        │
                        ▼
                     ACTOR
              "How can I do this?"
                        │
                    actions
                        ▼
                  ENVIRONMENT
                        │
                observable reality
                        ▼
                    VERIFIER
              "What actually happened?"
                        │
              PASS / FAIL / UNKNOWN
                        │
                        ▼
                     ACTOR
             "What general lesson
              should I retain?"
                        │
                        ▼
                     MEMORY
                        │
                        └──────→ next iteration
```

This separation is central to RSIAgent. The *Actor proposes actions and 
learns lessons, but doesn't get to certify its own claims*. The Verifier's 
job is to provide an independent empirical grounding signal. 
[arXiv](https://arxiv.org/abs/2609.15364?utm_source=chatgpt.com)

For SemOS, this is arguably even more interesting than the Curriculum Agent: 
a comparable architecture could separate *knowledge extraction/reasoning* 
from *evidence verification*, so that an LLM cannot turn its own interpretation 
of a document into a supposedly verified fact merely because another pass of 
the same reasoning agrees with it.
