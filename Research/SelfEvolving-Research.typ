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
    "Reading-202602"
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

// #table(
//  columns: 3,
//  align: left,
//  [Name], [Description], [Documentation],
//  [Bicep], [Microsoft], [Azure-specific],
//
// #figure(
//   image("Images/image_2026030101.png", width: 100%),
//   caption: [Hardware setup (#a_030105)],
// )

*Central idea*

= Introduction

The fundamental process is straightforward: an agent executes tasks, collects feedback, 
analyzes failures or inefficiencies, proposes modifications to its harness, evaluates 
those modifications, and permanently adopts changes that pass validation. Subsequent 
executions use the improved harness, creating a continuous adaptation cycle.

*Self-evolution vs self-improvement*
An important distinction is that self-evolution does not necessarily mean self-improvement. 
A system may continually modify itself without becoming better. The paper therefore 
emphasizes rigorous evaluation and controlled acceptance of changes.

== What can evolve

=== Instructions and memory
prompts, reusable knowledge, learned procedures, such as learn a better strategy for 
extracting structured information.

=== Workflows
Task decomposition, routing, agent coordination, such as Change from sequential 
processing to parallel subagents

=== Tools and code               
Executable components and skill implementations, such as rewrite a retrieval tool 
to improve ranking.

=== Runtime and repository logic
Agent loops, context construction, recovery mechanisms, such as modify ho the agent 
handles tool failures.

=== Plugin composition
Selection and integration of capabilities, such as replace a tool ith a better 
implementation.

The distinction between interpreted state and executable revisions is particularly important. 
Changing a prompt or a workflow specification interpreted by an existing executor is 
different from modifying the executor itself. The latter has a larger potential impact 
but also introduces more risk.

*How does the evolution work?*

The paper connects harness optimization to evolutionary algorithms. Rather than using 
gradient descent to modify model weights, the system searches over discrete changes 
to prompts, code, skills, and workflows.

It identifies several optimization strategies, including:

- *Elitist search*: Generate a candidate modification and retain it only if it 
  outperforms the current version.
- *Archive-based search*: Maintain multiple successful harness versions, allowing 
  future improvements to branch from different candidates.
- *Recombination*: Combine useful components from multiple previous candidates.
- *Quality-diversity optimization*: Preserve different high-performing solutions 
  rather than converging prematurely on one design.
- *Multi-objective optimization*: Balance accuracy, latency, token consumption, 
  and other costs.

For example, an agent that repeatedly extracts metrics from technical documents might 
discover that it performs poorly on complex tables. It could generate a new table-parsing 
procedure, evaluate it against previous documents and unseen test documents, and incorporate 
it into its permanent skill library if it demonstrates reliable improvement.

*The theoretical contribution: preventing regression*

One of the paper's more substantial contributions is its analysis of the reliability 
of continuous harness modification using continual PAC-learning (Probably Approximately 
Correct learning).

The authors examine three problems:

1. Generalization: Does an improvement on evaluation tasks also work on unseen tasks?
2. Retention: Does improving one capability degrade previously learned capabilities?
3. Admission: How much statistical evidence is needed before accepting a modification?

They derive a statistical acceptance criterion:

```text
\\[ \widehat{\Delta}+\sqrt{\frac{2\ln(KT/\delta)}{m}}<0 \\]
```

Here, \\(\widehat{\Delta}\\) is the measured change in loss between the candidate and 
existing harness, \\(K\\) is the maximum number of candidates per round, \\(T\\) is 
the number of evaluation rounds, \\(m\\) is the number of independent validation tasks, 
and \\(\delta\\) controls the failure probability.

In practical terms, a candidate should not be accepted merely because its average score 
is slightly better. The observed improvement must be sufficiently large relative to 
statistical uncertainty.

Crucially, the validation tasks must be independent of the candidate-generation process. 
Repeatedly tuning a harness against the same benchmark can produce overfitting rather 
than genuine improvement. The theoretical guarantees are conditional on assumptions 
about sampling, loss, and evaluator reliability; they are not unconditional guarantees 
that a self-modifying agent will improve.

[image](https://www.google.com/s2/favicons?domain=https://arxiv.org\&sz=32)

arXiv

+1

*What experimental evidence does the paper provide?*

The paper primarily synthesizes existing research rather than presenting a comprehensive 
new experimental evaluation of its own framework.

One cited result, from HarnessOpt on SpreadsheetBench, illustrates how improving the 
harness can significantly affect performance:

SpreadsheetBench accuracy

Results reproduced in the paper from the HarnessOpt study; percentages.

Initial

HarnessOpt + skill

0%25%50%75%100%GPT-5.4-nanoGPT-5.4-miniGPT-5.4GPT-5.5

The authors also discuss cases where reusable generated tools increase initial task cost but reduce cumulative costs across repeated tasks.

These results support the importance of harness design, but they do not establish that the paper's entire proposed self-evolution framework has been experimentally validated.
[image](https://www.google.com/s2/favicons?domain=https://arxiv.org\&sz=32)

*Practical implications and limitations*

The paper emphasizes that persistent modifications create risks beyond ordinary agent 
execution. An incorrect procedure may be reused repeatedly, propagated across teams, 
or incorporated into other skills. In safety-critical environments, reverting software 
cannot necessarily undo harmful real-world actions.

Consequently, the authors recommend keeping final evaluation, authorization boundaries, 
and critical safety controls outside the harness's editable scope. They also emphasize 
versioning, independent validation, regression testing, and the ability to trace deployed 
behavior to specific harness revisions.

The broader research directions include joint optimization of models and harnesses, 
distributed execution, plugin-based component replacement, and continuous evaluation as 
task distributions change. [image](https://www.google.com/s2/favicons?domain=https://arxiv.org\&sz=32)

*Assessment*

The paper's main value is providing a systematic conceptual and theoretical framework for 
self-evolving agents, rather than introducing a single new algorithm.

Three ideas stand out:

First, a fixed LLM can become substantially more effective through changes to its surrounding 
software. Improving context construction, memory, tools, and execution policies can be an 
alternative or complement to using a larger model.

Second, harness evolution can operate at different levels, from learning reusable instructions 
to rewriting the agent's own execution machinery. This distinction is important because the 
potential benefits and regression risks increase as the editable scope expands.

Third, the difficult problem is not generating candidate improvements—LLMs can already propose 
code and prompt changes—but determining which changes deserve permanent adoption without 
degrading existing capabilities.

For an agent-based system such as SemOS, the most immediately useful approach would be to 
collect execution traces and failures, generate candidate improvements to extraction or 
retrieval procedures, and validate them against both new tasks and historical regression 
suites before promotion.

Bottom line: The paper argues that the next major improvement in agent capabilities may come 
not only from better models, but also from software systems that can systematically learn to 
improve themselves. Its strongest contribution is clarifying how such systems should be structured, 
evaluated, and controlled—not demonstrating that unrestricted recursive self-improvement has 
already been achieved.

@ref-github-musclememory

#bibliography("../references/references.bib")

