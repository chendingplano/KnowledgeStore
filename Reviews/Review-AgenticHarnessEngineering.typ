#import "@preview/diagraph:0.3.6"
#import "@preview/oxdraw:0.1.0": *

#set heading(numbering: "1.")
#set quote(block: true)
#show quote: set pad(x: 1em)
#show raw.where(block: true): block.with(fill: luma(240), inset: 1em, radius: 0.5em, width: 100%)

#set page(numbering: "i")
#counter(page).update(1)

= Table of Contents
#outline()
#pagebreak()

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
    "Agentic Harness Engineering"
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

#show heading.where(level: 4): set text(size: 12pt)
#show heading.where(level: 4): it => pad(top: 4pt, it)

#set page(numbering: "1")
#counter(page).update(1)
#counter(heading).update(0)

#let frontmatter = (
  created: "2026/05/01",
  logical_name: "agentic harness engineering",
  file_id: "2026050101",
  file_type: "Typst",
  keywords: ["agent harness", "harness engineering", "agentic harness engineering", "agentic system"],
  source_url: "https://arxiv.org/abs/2604.25850",
  feed: "Hacker News"
)

= Overview
The paper *“Agentic Harness Engineering: Observability-Driven Automatic Evolution of Coding-Agent Harnesses”* introduces a 
new framework (AHE) aimed at improving how coding agents (LLM-based software agents) are built and evolved. Its core premise 
is that the *harness*—the surrounding system that connects a model to tools, memory, and execution environments—is now a 
primary determinant of performance, yet remains difficult to design and optimize automatically. Traditional approaches rely 
heavily on manual tuning or unstable trial-and-error processes due to complex action spaces, noisy feedback, and long 
execution traces. ([arXiv][1])

To address this, the authors propose *Agentic Harness Engineering (AHE)*, a closed-loop system that enables 
*automatic harness evolution*. The key innovation is introducing *three forms of observability* aligned with the engineering 
loop:

- *Component observability*: represents every harness component (e.g., prompts, tools, memory) as explicit, versioned, 
  file-level objects.
- *Experience observability*: compresses massive execution traces into structured, layered evidence that agents can 
  analyze.
- *Decision observability*: requires each modification to include a prediction of its impact, which is later verified 
  against actual outcomes.
Together, these mechanisms turn each change into a *falsifiable, data-driven experiment*, replacing blind iteration 
with systematic improvement. ([arXiv][1])

The framework operates through an iterative loop—*evaluate → analyze → improve*—where a separate evolution agent modifies 
the harness while the underlying LLM remains fixed. This separation is important: improvements come not from better models, 
but from better infrastructure around them. Over multiple iterations, the system learns which components (e.g., tools, 
middleware, memory) most influence performance, and refines them accordingly. ([GitHub][2])

Empirically, AHE demonstrates significant gains. On benchmarks like Terminal-Bench 2, it improves pass\@1 accuracy from 
69.7% to 77.0%, outperforming both human-designed harnesses (e.g., Codex-CLI) and prior self-evolving methods. 
Moreover, the evolved harness generalizes well: it transfers across different model families and tasks with fewer tokens, 
suggesting it captures reusable “engineering knowledge” rather than overfitting to a single benchmark. ([arXiv][1])

Overall, the paper reframes progress in coding agents: instead of focusing solely on model capability, it emphasizes 
*observability-driven infrastructure as the key to continuous improvement*. AHE shows that with the right 
instrumentation and feedback loops, agent systems can *systematically evolve themselves*, pointing toward a future where 
AI development resembles automated, data-driven engineering rather than manual prompt tuning.

== Key Points
- "AHE turns harness optimization into a closed loop driven by another agent. Every 
  phase of this loop must be observable: the harness components an iteration writes,
  the rollout trajectories it generates, and the edit decisions it commits)"
- 'Everything File', or everything readable by agents.

== References
[1]: https://arxiv.org/abs/2604.25850?utm_source=chatgpt.com "Observability-Driven Automatic Evolution of Coding-Agent ..."

[2]: https://github.com/china-qijizhifeng/agentic-harness-engineering?utm_source=chatgpt.com "china-qijizhifeng/agentic-harness-engineering"

