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
    "Thinking Model"
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
  created: "2026/05/25",
  logical_name: "Thinking Model",
  file_id: "2026052501",
  file_type: "Typst",
  content_type: "Research",
  doc_time: "2026/05/25",
  keywords: ["Thinking Model", "Knowledge Wiki", Knowledge Base"],
)

= Thinking Model
SemOS can be modeled as a *computational epistemic system* that performs structured 
reasoning over explicit knowledge objects, uncertainty, assumptions, and actions.

== SemOS as a Thinking System

We can decompose our thinking into:

- thinking structure (elements)
- thinking evaluation (quality standards)
- thinking disposition (intellectual traits)

For SemOS, these map naturally to:

```text
| Human framework     | SemOS equivalent                            |
| ------------------- | ------------------------------------------- |
| Thought elements    | reasoning state model                       |
| Thought standards   | validation/evaluation engine                |
| intellectual traits | system governance / meta-reasoning policies |
```

This is powerful because most current AI systems are weak precisely 
because these layers are implicit.

A typical RAG pipeline:

```text
question
→ retrieve docs
→ stuff context
→ LLM answers
```

This is not thinking. This is stochastic completion with retrieval assistance.
SemOS can become something qualitatively different.

== First Dimension → SemOS Cognitive State Model

The first dimension is the most directly applicable. This becomes the 
*internal reasoning schema* of SemOS. Instead of storing only facts/documents, 
SemOS stores structured cognitive objects.

The Cognitive State Model consists of:
- Purpose
- Problem
- Inference
- Concepts
- Assumptions
- Implications / Consequences
- Perspective

=== Purpose

```json
{
  "purpose": {
    "type": "compliance_analysis",
    "goal": "determine whether vaccine storage process satisfies WHO cold-chain requirements"
  }
}
```

Without explicit purpose, retrieval becomes noisy.

Purpose controls:

- retrieval ranking
- search breadth
- stopping criteria
- evidence thresholds

This is huge.

=== Problem

```json
{
  "problem": {
    "question": "Does Procedure X violate Requirement Y?",
    "problem_type": "normative_compliance"
  }
}
```

This differs from purpose. 'Purpose', for instance, ensures compliance, while 
'problem' leads us to check clause 8.3.2 applicability. Without separating them, 
systems wander.

*Information*

SemOS classifies information. Not all information is equal.

Example:

```json
{
  "evidence": [
    {
      "type": "primary_source",
      "source": "ISO standard",
      "confidence": 0.96
    },
    {
      "type": "secondary_summary",
      "source": "internal memo",
      "confidence": 0.55
    }
  ]
}
```

SemOS should know:

- source provenance
- freshness
- authority
- extraction confidence
- contradiction status

This becomes epistemic bookkeeping.

=== Inference

This is missing in most knowledge systems. Current systems store:

- facts
- embeddings
- vectors
- keywords

But not: how conclusions were derived. SemOS should store explicit 
reasoning traces.

Example:

```json
{
  "inference": {
    "premises": ["R1", "R2"],
    "rule": "modus ponens",
    "conclusion": "C1"
  }
}
```

Or probabilistic:

```json
{
  "inference_type": "abductive",
  "confidence": 0.74
}
```

This is where the causal model discussion also connects.

=== Concepts

SemOS should maintain explicit conceptual schemas.

Example:

"cold chain"

is not merely a keyword.

It is:

```json
{
  "concept": "cold_chain",
  "definition": "...",
  "aliases": [...],
  "parent": "vaccine_storage",
  "relations": [...]
}
```

This becomes semantic ontology.

Without explicit concepts, reasoning degenerates into token matching.

=== Assumptions

LLMs silently hallucinate assumptions. SemOS should force assumptions 
into first-class objects.

Example:

```json
{
  "assumption": {
    "statement": "temperature log is accurate",
    "status": "unverified"
  }
}
```

Reasoning becomes inspectable. This is one of the biggest 
differentiators from ordinary RAG.

=== Implications / Consequences

This becomes forward simulation.

Example:

```json
if clause_x violated
→ shipment invalid
→ product recall risk
→ regulatory reporting required
```

This is scenario reasoning. Not merely retrieval.

=== Perspective

This is multi-frame reasoning.

Example:

same regulation interpreted from:

- regulator perspective
- manufacturer perspective
- auditor perspective
- patient safety perspective

SemOS should explicitly model viewpoint. Otherwise answers become 
mono-perspective hallucinations.

== Second Dimension → Reasoning Validator

This can make SemOS a *Reasoning QA Engine*.

Every reasoning artifact can be scored.

=== Clarity

Question:

Is the claim interpretable?

Example bad:

> system should improve performance

Improve what?

Latency?
Accuracy?
Recall?

SemOS should reject vague claims.

=== Accuracy

Evidence verification.

Need:

- provenance
- cross-source validation
- contradiction detection

Example:

```text
claim supported by only weak source
```

=== Precision

Example:

Bad:

> many failures occurred

Good:

> 17 failures between Jan–Mar 2025

SemOS should normalize vague statements.

=== Relevance

Just because text matches keywords doesn't mean it's useful.
SemOS needs relevance scoring tied to explicit purpose.

=== Depth

This is where causal reasoning matters.

Surface:

```text
temperature excursion happened
```

Deep:

```text
root cause = sensor calibration drift
```

Depth means causal mechanism.

=== Breadth

Alternative hypotheses.

Example:

Instead of:

```text
delivery delayed because weather
```

Consider:

- customs
- refrigeration fault
- documentation issue

SemOS should branch hypotheses.

=== Logic

Formal consistency checking.

Example:

If:

```text
A implies B
B false
therefore A false
```

Maybe valid, maybe not depending on rule.

SemOS can run symbolic consistency checks.

=== Importance

Prioritization engine.

Not every fact matters equally.

This helps search pruning.

=== Fairness

Bias control.

Critical in legal/regulatory reasoning.

Example:

vendor docs vs regulator docs.

Need weighting discipline.

=== Third Dimension → Meta-Cognitive Governance

This is the least obvious but potentially the most transformative.

Human "traits" become machine operating principles.

=== Intellectual humility

SemOS says:

```text
insufficient evidence
```

instead of hallucinating.

Confidence calibration.

=== Intellectual courage

System explores contradictory evidence.

Not only confirmatory retrieval.

This is huge.

Current RAG often reinforces initial framing.

=== Empathy / perspective taking

Multi-agent adversarial reasoning.

Example:

Agent A = auditor

Agent B = manufacturer

Agent C = legal counsel

Each reasons differently.

=== Intellectual autonomy

SemOS should not blindly trust user framing.

Example:

User asks:

> prove this process is compliant

System should test neutrality.

=== Integrity

Apply same evidence standards everywhere.

No asymmetric validation.

=== Perseverance

Iterative decomposition.

Instead of one-shot answer:

```text
search → reason → detect gap → search again
```

This matches agentic loops.

=== Faith in reason

Less philosophy, more architecture:

structured reasoning beats token intuition.

== Concrete Architecture Mapping

This suggests SemOS architecture:

```text
SemOS
 ├── Knowledge Layer
 │    ├── documents
 │    ├── concepts
 │    ├── entities
 │    ├── provisions
 │    ├── metrics
 │    ├── causal relations
 │    └── assumptions
 │
 ├── Cognitive State Layer
 │    ├── purpose
 │    ├── problem
 │    ├── evidence set
 │    ├── hypotheses
 │    ├── reasoning traces
 │    ├── perspectives
 │    └── implications
 │
 ├── Validation Layer
 │    ├── clarity checker
 │    ├── contradiction detector
 │    ├── provenance verifier
 │    ├── relevance scorer
 │    ├── precision checker
 │    └── uncertainty estimator
 │
 ├── Meta-Reasoning Layer
 │    ├── confidence calibration
 │    ├── counterargument generator
 │    ├── perspective switcher
 │    ├── assumption challenger
 │    └── stopping controller
 │
 └── Execution Layer
      ├── retrieval
      ├── graph traversal
      ├── symbolic reasoning
      ├── causal inference
      └── action orchestration
```

This is much more than a KB. This is an epistemic operating system.

== Biggest Risk

=== Over-Formalization

If every reasoning task requires explicit full structure:

- purpose
- problem
- assumptions
- perspectives
- evidence
- validation

the system becomes too expensive and slow. So SemOS likely needs adaptive cognition:

Fast mode:

```text
light retrieval + heuristic reasoning
```

Deep mode:

```text
full structured epistemic reasoning
```

As AI stands today, doing extensive knowledge extraction and processing is prehibitively
expansive and slow. We must have a heuristic algorithm to selectively process
them.

==== Manual
It relies on human users. A field expert requests the system to extract specific knowledge
related artifacts.

==== Usage Driven
When a user asks the system to do tasks, the system does whatever it should. Along the 
way, the system will think, reason, retrieve, etc. After finish, it can store the reason
results as knowledge artifacts, with references to the sources and, especially the source
sets so that when the source sets change, it flags the artifact so that the next time
when the system uses the artifact, it can update the artifact with the changes.
This is important because artifact freshness is important. Something true in the past
does not mean it is still true in the future.

==== Problem-Solving Driven
This can be a special form of the above pattern. Debugging is a special form of problem
solving.

When one uses the system to solve a problem, the user may ask the system to summarize
the problem, how the problem is solved, etc.

==== Unresolved Tasks
When the system fails solving a problem, humans may help, 
- Provide more information
- Instruct the system how to reason or how to solve the problem

== Storing Thoughts, too?
My point of view is that SemOS should not merely store knowledge. It should store 
the structure of thought itself. That means SemOS becomes not a knowledge base,
but a reasoning substrate.

That is a fundamentally different class of system—and much closer to your SemOS 
vision than conventional RAG.

== Article
#let a_001 = link(
  "https://mp.weixin.qq.com/s/1_rF4Mw82vKNPMWUq4T6yw"
)[#text(fill:blue)[Article]]

#a_001 \

大多数人并不是“不会思考”，而是思考过程本身缺乏结构：目标不清、信息混杂、推理跳跃，
最后只能依赖直觉或立场输出结论。真正有效的思考，不在于“想得更多”，而在于“想得更有结构、
也更可检验”。下面这个框架，尝试把思维拆解为三个层次：思维由哪些要素构成、如何判断思维质量、
以及什么样的认知习惯支撑更可靠的判断。它的目的只有一个：让思考从经验性的直觉活动，
变成可分析、可修正的理性过程。

第一维度：思维要素 
- 目的： 你的目标是什么？（确保目标清晰且公正） 
- 问题： 你要解决什么核心问题？ 
- 信息： 你有哪些数据、事实和经验？ 
- 推论： 你根据信息得出了什么结论？ 
- 概念： 你使用了哪些核心理论、定义或法则？ 
- 假设： 什么是你认为理所当然、不言而喻的前提？ 
- 意义与后果： 如果你的想法付诸实施，会发生什么？ 
- 立场/观点： 你是从哪个角度或参考框架出发的？

第二维度：思维标准 
- 清晰性（Clarity）： 如果陈述不清晰，我们无法判断其准确性。（你能举个例子吗？） 
- 准确性（Accuracy）： 描述的事情是真的吗？（如何核实？） 
- 精确性（Precision）： 细节是否足够具体？ 
- 相关性（Relevance）： 这个信息对解决当前问题有贡献吗？ 
- 深度（Depth）： 是否触及了问题的复杂本质，而非流于表面？ 
- 广度（Breadth）： 是否考虑了其他的视角或不同的立场？ 
- 逻辑性（Logic）： 前后推导是否一致？ 
- 重要性：核心问题还是细枝末节 
- 公正性（Fairness）： 是否存在利益驱动的偏见？

第三维度：智力特质（Intellectual Traits） 
- 智力谦逊： 承认自己知识的局限，不自负。 
- 智力勇气： 敢于面对并公正地评估与自己立场相对的观点或“禁忌”思想。 
- 换位思考： 设身处地地站在他人的逻辑框架里思考。 
- 智力自主： 独立思考，不盲从。 
- 智力正直： 对自己和对他人的标准一致，不搞双标。 
- 智力坚毅： 面对复杂困难的问题不放弃。 
- 理性信念： 相信通过理性的培养，人类可以过上更好的生活。

