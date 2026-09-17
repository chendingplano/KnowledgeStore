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
    "Review - gstack"
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
  file_type: "typst",
  logical_name: "review-gstack",
  file_id: "2026091701",
  source: "https://github.com/garrytan/gstack",
  content_type: "review",
  document_date: "2026/09/17",
  keywords: [AI, agent, skill, gstack, Garry Tan],
)

= Overview
gstack is best understood as an *agent-development process layer* rather than a 
coding model or a conventional framework. Its core idea is to turn coding agents 
such as Claude Code or Codex into a more structured “virtual engineering team,” 
with explicit workflows for product thinking, architecture, implementation review, 
QA, debugging, security, shipping, and retrospectives. The repository describes 
the lifecycle as *Think → Plan → Build → Review → Test → Ship → Reflect*, with 
specialized skills feeding artifacts into later stages. For example, `/office-hours` 
produces a design document, planning skills refine it, `/review` checks implementation, 
`/qa` exercises the actual application, and `/ship` verifies and packages the result.

A second important aspect is that gstack is *not limited to Claude Code anymore*. 
The current repository explicitly supports OpenAI Codex CLI, OpenCode, Cursor, 
Factory Droid, Kiro, OpenClaw, Hermes, and others. For Codex it installs generated 
skills under `${CODEX_HOME:-~/.codex}/skills/gstack-*/`; it even has model-specific 
behavior for `gpt-5.6-sol`.  This makes it much more relevant to you than an older 
description of gstack as simply “a set of Claude Code prompts.”

The underlying philosophy is also worth separating from the individual commands. Its 
compact `AGENTS.md` digest gives four rules: *Boil the Ocean* (finish edge cases/tests/error 
paths rather than producing a thin happy-path implementation), *Search Before Building*, 
*User Sovereignty*, and *Build for Yourself*. It also defines a reuse hierarchy: reuse 
something already in the repo first, then the standard library, then native platform 
capabilities, then an existing dependency, before adding new machinery. That philosophy 
is probably more valuable for SemOS than many of the individual slash commands.

There is a amount of overlap with the harness-engineering direction SemOS has been exploring.

SemOS recent thinking around `AGENTS.md`, failure registries, spec-first development, keeping 
`docs/` synchronized with `src/`, investigation before patching, and allowing agents to retrieve 
prior failures is essentially concerned with this question:

> How do we turn a powerful but somewhat stateless coding model into a reliable engineering process?

gstack is one fairly opinionated implementation of that idea.

For example, its `/investigate` skill explicitly describes *systematic root-cause debugging*, 
with a rule against making fixes before investigation and a mechanism for stopping after repeated 
failed fixes.  Its `/autoplan` runs several specialist reviews—CEO/product, design, developer 
experience, and engineering—rather than asking one agent to jump directly from a request to code.  
And its skill routing distinguishes requests such as “QA this deployment,” “review this diff,” 
and “investigate this failure” instead of treating all of them as generic coding prompts.

Conceptually:

```text
Typical coding agent

request
   ↓
LLM
   ↓
code
```

gstack pushes toward:

```text
request
   ↓
problem framing
   ↓
design / architecture
   ↓
implementation
   ↓
review
   ↓
QA / verification
   ↓
ship
   ↓
retrospective / learning
```

That is very close to the “harness” direction SemOS has been exploring.

== gstack and SemOS

For SemOS, we can separate *product development of SemOS* from *SemOS's knowledge architecture itself*.

gstack is relevant to the former, not the latter.

It will not materially help SemOS design BM25 + semantic retrieval, Scene Blocks, ontology/category 
systems, alias reconciliation, causal analysis, or filesystem exploration. Those are SemOS-specific 
research and architecture problems. gstack isn't a knowledge-base framework.

But it could improve the process by which agents change that system.

A SemOS feature might currently look like:

```text
"Add discriminator generation to the retrieval pipeline."

        ↓

Codex explores repo
        ↓
implements it
        ↓
tests
```

A gstack-style workflow would instead be closer to:

```text
Feature request
    │
    ▼
Product / scope review
"What exact retrieval failure does this solve?"
    │
    ▼
Engineering review
Where does discriminator generation belong?
query planning?
candidate generation?
investigative search?
    │
    ▼
Failure analysis
What happens with:
- unknown terminology
- multilingual terms
- bad discriminators
- overly restrictive discriminators
    │
    ▼
Implementation
    │
    ▼
Review
    │
    ▼
Regression tests
    │
    ▼
Documentation update
```

For SemOS, that extra structure is useful because many changes are *architectural rather 
than CRUD features*. An agent can easily implement something locally sensible that damages 
the larger information architecture.

But do not adopt the whole system as SemOS's governing harness. This is the main qualification.
gstack is quite opinionated. Its own digest literally tells agents:

> “Boil the Ocean — AI makes completeness cheap.”

That philosophy can be productive for ordinary product development, but it conflicts somewhat 
with something important in SemOS: we are doing a lot of *experimental architecture*.

For research-heavy work, completeness is not always desirable. Suppose we are investigating 
whether a dictionary-backed “bag of meanings” can outperform straightforward BM25. You may 
explicitly want:

```text
hypothesis
    ↓
small experiment
    ↓
measure
    ↓
discard or refine
```

rather than:

```text
hypothesis
    ↓
production implementation
    ↓
edge cases
    ↓
complete tests
    ↓
documentation
```

The second path can turn a bad idea into a beautifully engineered bad idea.

Interestingly, the gstack maintainers have also added model-specific instructions for 
GPT-5.6 Sol to keep requested work bounded rather than expanding into adjacent cleanup 
or speculative hardening. That suggests the same tension exists inside gstack itself.

*The content that are most applicable to SemOS*

```text
| gstack concept              | SemOS usefulness                            |
| --------------------------- | ------------------------------------------- |
| `/investigate`              | *Very high*                                 |
| `/plan-eng-review`          | *Very high*                                 |
| `/review`                   | *Very high*                                 |
| `/autoplan`                 | High for larger features                    |
| `/retro`                    | High                                        |
| `/benchmark`                | High, especially retrieval/indexing changes |
| `/cso`                      | Useful periodically                         |
| `/qa`                       | Useful mainly for the Svelte/UI parts       |
| CEO/product review          | Selectively useful                          |
| design review               | Limited except UI work                      |
| `/ship`                     | Useful if its Git workflow matches yours    |
| “Boil the Ocean” everywhere | Be careful, use it with care                |
```

The `/investigate` philosophy is especially aligned with SemOS failure-registry thinking: 
*observe → form hypotheses → test → identify root cause → fix → retain the lesson.*

*One important thing SemOS can borrow even without installing gstack*

gstack demonstrates something that directly addresses SemOS concern about an ever-growing `AGENTS.md`.

Its solution isn't:

```text
AGENTS.md
  + every coding rule
  + every review rule
  + every debugging lesson
  + every security lesson
  + every workflow
  ...
```

Instead, its lightweight agent digest is only a compact set of behavioral principles, while the 
detailed workflows live in separate skills. The digest explicitly says the full installation adds 
workflows, reviews, and evaluations on top of those basic rules.

That's very close to the architecture we want to use for SemOS:

```text
AGENTS.md
│
├── invariant engineering principles
├── repo structure
├── mandatory safety rules
└── instructions for discovering skills
        │
        ├── investigate/
        ├── review/
        ├── database-migration/
        ├── retrieval-change/
        ├── extraction-pipeline/
        ├── docs-sync/
        └── failure-search/
```

And separately:

```text
failure registry
    ↓
retrieval
    ↓
relevant historical failures
```

rather than stuffing historical mistakes into `AGENTS.md`.

That part of gstack strongly reinforces the direction you were already considering.

== Should I use it?

*Yes, but initially as an optional toolkit rather than making SemOS a “gstack project.”*

Since you already use Codex, the lowest-risk experiment is to install its Codex host:

```bash
git clone --single-branch --depth 1 \
  https://github.com/garrytan/gstack.git ~/gstack

cd ~/gstack
./setup --host codex
```

The repository says that this generates the gstack skills under your Codex skills directory 
and selects a behavioral profile based on the configured Codex model.

Then use it selectively for perhaps a week:

```text
normal small change
    → ordinary Codex

nontrivial SemOS feature
    → gstack planning / eng review

mysterious bug
    → /investigate

finished substantial change
    → /review

retrieval/index performance change
    → /benchmark
```

I would *not* initially enable its team mode or put “gstack required” into SemOS. First determine 
which of its workflows actually produce information you weren't getting from your existing Codex 
workflow.

The most interesting outcome may not be “use gstack forever.” It may be that you eventually take 
its architecture and build a much smaller *SemOS-specific engineering harness*:

```text
generic gstack
        ↓ learn from
SemOS engineering skills

/sem-plan
/sem-investigate
/sem-retrieval-review
/sem-schema-review
/sem-extraction-review
/sem-benchmark
/sem-doc-sync
/sem-retro
```

That would combine gstack's strongest idea—*explicit engineering roles and workflows*—with the 
domain knowledge that a generic software-development stack cannot possess.

For SemOS specifically, I suspect that is ultimately the more valuable direction than adopting 
all of gstack wholesale.

== gstack, Codex and Skill Management

We can think of gstack as *a packaged collection of skills plus a relatively small set of 
global behavioral/routing instructions and supporting tooling*. Installing it into Codex 
primarily makes a large set of gstack skills available to the agent; its lightweight `AGENTS.md` 
digest carries general principles such as “Search Before Building” and the reuse ladder. The 
individual skills contain the substantial workflow logic.

This present a problem: uncontrolled orchestration.

Suppose my environment eventually contains:

```text
skills/
├── gstack-plan-eng-review
├── gstack-review
├── gstack-investigate
├── superpowers-code-review
├── superpowers-debug
├── openspec-review
├── openspec-implement
├── my-review
├── my-debug
└── ...
```

Then you ask Codex:

> Implement the new catalog reconciliation mechanism.

If the instruction is essentially “use relevant skills when appropriate,” you've implicitly 
delegated *two different decisions* to the same LLM:

```text
                  User request
                       │
                       ▼
                 ┌───────────┐
                 │   Codex   │
                 └───────────┘
                    │     │
        What work? ─┘     └─ How should I work?
                              │
                    ┌─────────┼─────────┐
                    ▼         ▼         ▼
                  gstack  superpowers  openspec
```

The first decision—*what needs to be done*—is exactly what we want the agent to reason about.

The second—*which development methodology controls this task*—is much more questionable.

As the skill library grows, the behavior becomes dependent on skill discovery, descriptions, 
context, ordering, model judgment, and sometimes tiny wording differences in your request. 
The result can be *non-deterministic process selection*.

That's undesirable for a serious project such as SemOS.

Manually specifying skills every time may not be a general solution.

When we are given a task, we can do:

> “Use gstack `/investigate` for this.”

That's good when we deliberately want a particular methodology. But making that mandatory 
for every task creates another problem: *you become the orchestrator*.

You would have to remember:

```text
Is this gstack?
Superpowers?
OpenSpec?
Should I run plan-eng-review first?
Should investigate precede review?
```

That's exactly the cognitive burden the harness is supposed to remove.
One possible solution is to separate capabilities from policy (see below).

== Separate capabilities from policy

Think about your installed skills as a *capability pool*:

```text
                   Capability pool

       gstack          superpowers        openspec
          │                 │                 │
     investigate         debug             spec
     review              review            review
     benchmark           plan             implement
     qa                   ...
```

Do *not* let those packages independently define your SemOS development process.

Instead, SemOS should define its own *orchestration policy*:

```text
                 SemOS development policy
                         │
          ┌──────────────┼───────────────┐
          ▼              ▼               ▼
       feature           bug          experiment
          │              │               │
          ▼              ▼               ▼
       OpenSpec      gstack/investigate  lightweight
          │              │               │
          ▼              ▼               ▼
      implementation   fix + tests      benchmark
          │              │
          └──────┬───────┘
                 ▼
          gstack/review
```

Now Codex can still reason, but within boundaries established by you.

That's a much healthier division of responsibility.

*AGENTS.md should contain policy, not methodology*

I would make your SemOS `AGENTS.md` say something conceptually like:

```text
Development workflow

Do not select development-framework skills solely because they
appear relevant.

Use the following workflow routing:

- Small/local changes:
  Work directly. No planning framework required.

- New features or architectural changes:
  Use OpenSpec for specification and planning.

- Bugs with unknown root cause:
  Use gstack investigate.

- Completed substantial implementation:
  Use gstack review.

- Experimental/research changes:
  Do not use the normal feature workflow.
  Form a hypothesis, implement the smallest experiment,
  benchmark it, and evaluate the result.

- If the user explicitly names a skill or workflow:
  Follow the user's selection.

Do not invoke overlapping alternatives from Superpowers,
OpenSpec, and gstack unless explicitly requested.
```

The exact choices aren't important yet. The architecture is.
This architecture moves from:

```text
LLM chooses methodology
```

to:

```text
YOU define methodology
       ↓
LLM classifies the task
       ↓
deterministic routing policy
       ↓
skill
```

That retains useful LLM intelligence while greatly reducing process drift.

*Router*

There's an interesting parallel to SemOS itself.

You wouldn't normally dump every retrieval mechanism into an LLM and say:

> “Here are BM25, vectors, graph traversal, aliases, discriminators, filesystem exploration 
and Scene Blocks. Intelligently choose whatever seems appropriate.”

You're moving toward an architecture where different mechanisms have defined roles.

I'd treat coding skills similarly.

Define a small *skill ontology*:

```text
development
├── discovery
├── specification
├── planning
├── implementation
├── investigation
├── review
├── testing
├── benchmarking
├── documentation
└── release
```

Then assign *one preferred implementation* per role:

```text
investigation
    preferred: gstack/investigate

specification
    preferred: openspec

code_review
    preferred: gstack/review

benchmark
    preferred: gstack/benchmark

...
```

Other installed skills become alternatives rather than competing defaults:

```text
code_review
├── default: gstack/review
├── alternative: superpowers/review
└── alternative: openspec/review
```

This is much easier to reason about.

*Explicit invocation still has an important place*

I'd establish this precedence:

```text
1. User explicitly specifies workflow/skill
             ↓
2. Project policy selects workflow
             ↓
3. Task classifier selects policy route
             ↓
4. Agent autonomously discovers skills
```

So:

> “Use Superpowers to review this.”

means Superpowers.

> “Review this implementation.”

means SemOS policy → perhaps `gstack/review`.

> “Look at this code.”

might not trigger a heavyweight workflow at all.

Autonomous skill discovery becomes the *fallback*, rather than your primary orchestration mechanism.

*Solves Skill Accumulation*

Without such a layer, installing another skill package modifies the effective behavior of your coding agent:

```text
install skill
     ↓
changes available choices
     ↓
potentially changes agent behavior
```

That's a subtle form of configuration drift.

With explicit routing:

```text
install skill
     ↓
adds capability
     ↓
NO behavioral change
     ↓
until SemOS policy references it
```

That is a much stronger engineering property.

It is analogous to installing a library versus actually importing it.

Based on the above thinking and reasoning, we can come up with:

```text
.agent/
├── AGENTS.md
├── workflows/
│   ├── feature.md
│   ├── bug.md
│   ├── experiment.md
│   ├── refactor.md
│   └── hotfix.md
└── skills.md
```

`skills.md` becomes your *skill registry*, not a giant prompt:

```text
| Capability    | Default              | Alternatives |
|---------------|----------------------|--------------|
| specification | openspec             | superpowers  |
| planning      | openspec             | gstack       |
| investigation | gstack/investigate   | superpowers  |
| review        | gstack/review        | superpowers  |
| benchmark     | gstack/benchmark     | custom       |
| QA            | gstack/qa            | custom       |
```

And `AGENTS.md` contains the routing rules.

This gives you something that I think is crucial:

> *Installing a skill should not change SemOS's development methodology. Changing the routing policy should.*

That distinction—*capability installation vs. capability activation*—is the key architectural principle 
I would use to resolve your dilemma.

In fact, I think this is the natural next step beyond the “failure registry instead of endlessly growing 
AGENTS.md” idea we discussed earlier: `AGENTS.md` becomes the stable *control plane*, while skills, 
failure history, specifications, and detailed workflows become discoverable *data-plane resources* 
underneath it.

