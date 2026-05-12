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
    "Review - Hyper-KGGen"
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
  Source: "https://arxiv.org/pdf/2602.19543",
  ArtifactType: "Academic Paper",
  PublishDate: "2026/05/11",
  Keywords: [Knowledge Base, Knowledge Extraction, Information Extraction, Entity-Relation Extraction]
)

= Overview
This paper, “Hyper-KGGen: A Skill-Driven Knowledge Extractor for High-Quality Knowledge Hypergraph Construction”, tackles a limitation in current knowledge extraction systems: most information extraction pipelines reduce documents into simple entity-relation triples, which are often too restrictive for real-world documents where relationships are multi-entity, contextual, and document-spanning. The authors argue that conventional knowledge graphs lose important semantics because many facts are not naturally binary (“A relates to B”), but instead involve richer structures such as conditions, events, participants, temporal qualifiers, or cross-document dependencies. To address this, they propose extracting knowledge hypergraphs, where a single relation (hyperedge) can connect multiple entities simultaneously. ([OpenTrain AI][1])

The core contribution is Hyper-KGGen, a framework that treats extraction as a dynamic, skill-based reasoning process rather than static prompting. Instead of relying on a fixed prompt or a few demonstrations, the system decomposes extraction into reusable “skills” that encode extraction heuristics and domain reasoning patterns. A key design is a coarse-to-fine extraction pipeline: the system first captures simpler structures (such as entities and pairwise relations), then incrementally refines toward more complex hyper-relational structures. This resembles how a human analyst would read a technical document—first identifying obvious facts, then assembling them into richer semantic structures. The paper’s insight is that structured extraction quality improves when the model is guided by evolving procedural knowledge rather than one-shot instructions. ([OpenTrain AI][1])

A particularly interesting mechanism is the adaptive skill acquisition loop. Hyper-KGGen monitors extraction instability—cases where outputs are inconsistent, incomplete, or uncertain—and uses those failures as learning signals to induce better extraction skills. In effect, the system “learns how to extract” by observing where its reasoning breaks down. This is notable because it shifts from static prompt engineering to a lightweight self-improvement paradigm. Rather than fine-tuning the entire model, the framework evolves a Global Skill Library, which accumulates higher-quality extraction behaviors over time and can transfer across domains or document types.

To evaluate the approach, the authors introduce HyperDocRED, a benchmark specifically designed for document-level knowledge hypergraph extraction, since existing benchmarks mostly assume simpler relational extraction tasks. Experimental results reportedly show that Hyper-KGGen significantly outperforms strong baselines, especially in scenarios requiring document-level reasoning and multi-entity relation construction. The practical implication is significant for domains like standards, regulations, scientific literature, and technical documentation—exactly the kinds of corpora where facts often depend on conditions, actors, constraints, and context rather than isolated triples.

== Alignment to Vertical: Standards, Compliance
From one of SemOS perspectives: standards, compliance extraction, and richer knowledge representations, the 
biggest takeaway is that this paper aligns strongly with this thinking, move beyond conventional RAG chunk 
retrieval toward structured knowledge extraction with richer semantics. Hypergraphs are much closer than 
triples to representing provisions like *“If condition X holds, actor Y must perform action Z within time 
T under constraint C.”* In other words, this is less about better retrieval and more about building a 
knowledge substrate that preserves the structure LLMs actually need for reasoning.

== Thoughts on Hyper Graphs
We define Hyper Graph as the graph whose edges are not always binary. There are still entities in hyper
graphs. Edges become much more important than just connecting dots.

- Edges are objects or structures
- Edges have attributes
- Edges can have multiple nodes
- Each node in an edge plays a 'role'
- Edges can have actions
- Edges can 'reason'
- Edges can have constraints
- Edges can have pre-conditions
- Edges can emit events
- Edges can depend on other entities, hyper edges, events

== Case Studies
```text
Jhon joined Acme as a Test Group Leader in 2025.5, working on-site, introduced by Mary, company location
is 1234 First Street, Los Angles, CA 12345.
```
In this example, the edge defines a relation: `company-hire-person (CHP)`. The ontology of CHP includes:
- Person: entity
- Time: attribute
- Position: attribute or entity
- Company: entity
- Type of Job: attribute or entity, such as 'manager', 'programmer', 'sales', etc.

Note that whether something is treated as attributes or entities is subjective or dependent on
applications. 'Position' can be an attribute or an entity. If positoins are just labels, we can
treat them as attributes. If we want more information about positions, such as when a position
was created, the job description, saleries range, responsibilities, qualification, etc., we need
to treat it as entities.

It is also possible that initially the 'something' is treated as attributes. As the system complexity
grows, some of the attributes evolve into entities.

== Global Skill Library
LLMs cannot evolve (the fact), but we need it to evolve, to learn as we use it.
Skills often used in agentic system, serving as instructors, workflow and domain 
experts. There can be skills specifically good at writing proposals, write code,
review code, do testing, etc. 

LLMs + Skills form a system that has brains (LLMs) and being able to learn (
adding new skills, improve and enrich existing skills, etc.)

== Extraction Workflow
The *Coarse-to-Fine Hypergraph Knowledge Extraction* consists of four steps:
1. Document Chunking: size-based, adaptive chunking, or breaking documents at semantic bounaries, such as sections, paragraphs, etc.
2. Entity Extraction: for each chunk, it prompts the LLM to identify all valid mentions, assign fine-grained types, and generate concise descriptions based on the local context.
3. Coarse-to-Fine Hyperedge Extraction: 
  - Binary Relations (The Skeleton)
  - Qualified Binary Relations (Contextual Augmentation): it augment standard binary links with qualifying arguments such as time, location, or specific conditions.
  - General N-ary Relations (Event Details): this is the finest level. These relations encapsulate entire events or story plots, where multiple participants jointly instantiate a coherent scenario.
4. Knowledge Deduplication: first cluster mentions referring to the same real-world entity. Second, merge hyperedges that share identical semantic meanings. For both entities and relations, it synthesizes their descriptions by aggregating details from all instances, resulting in a unified and low-redundancy knowledge hypergraph.

== Adaptive Skill Acquisition
This module establishes a dynamic feedback loop that categories extraction
results based on their statbility, efficiently distilling high-quality 
extraction skills from unstable and missed instances to refine a global
skill library.

*Step 1 - Parallel Rollout for Candidate Generation*

Given a training document D and the current skill library S, it independently
sample the model's output K times using a non-zero temperature T. This generates
a diverse set of candidate hypergraphs to probe the model's capability 
boundaries.

It then compares these with the gold-standard hypergraph g\* (generated by
human users) by calculating the similarity based on the descriptions. That is,
we want to know how semantically close is the model-generated hypergraph to
the known correct hypergraph, by computing the embedding similarity between the
descriptions of extracted hyperedges and the gold standard 𝒢\∗.

Example:

1. Generated:
```text
  {vaccine storage unit, temperature sensor, alarm threshold, 8°C excursion}
```
Model output:
```text
  {cold storage monitor, trigger alert, above 8°C}
```

2. Convert its textual description into an embedding.

3. Gold hyperedge (𝒢\*):
```text
  {cold-chain monitor, shall trigger alarm, temperature > 8°C, within 5 minutes}
```

4. Compare it to the embedding(s) of corresponding gold hyperedges in 𝒢\*.

5. Reward partial correctness:

   - exact match → high reward
   - semantically very close → medium/high reward
   - partially overlapping → some reward
   - unrelated → low/no reward

In the above example, hard match will fail because they are not identical.
Semantic similarity is (probably) high (~0.8+). So the model still gets 
meaningful reward.

One subtle point: 𝒢\* is not generated dynamically during training. It comes 
from the labeled benchmark dataset (in this paper, likely HyperDocRED or their
constructed training corpus), prepared beforehand.

*Step 2: Stability-based Relative Record*

By comparing their semantic similarity, it gets:
- Stable Set: relations consistently retrieved across all samples
- Unstable Set: relations retrieved only in a subset of trajectories. These typically represent Scenario-Specific Knowledge (such as industry jargon or implicit connections), where the model oscillates between success and failure due to insufficent grouding and low confidence.
- Miss Set: Relations never retrieved in any sample. These indicate Domain-Exclusive Knowledge or deep reasoning gaps where the model completely lacks the necessary extraction logic.

== How to Evolve the Skills

Based on the categorization above, it ignores the Stable Set.

For unstable relations, it analyzes the successful trajectories where the model
correctly extracted the hyperedge. It prompts the LLM to summarize the
reasoning path that led to these successes, explicitly articulating
the scenario-specific logic to stabilize future inference.

For relations in the miss set, it employs a Hindsight Reasoning strategy.
It injects the ground-truth relation from g\* into the context as a posterior
condition. Knowwing that the relation exists, the model backtracks through the
document, locates overlooked evidence, and constructs a logical chain from
scratch. This process generates a fresh extraction rule aimed at covering
the prior blind spots.

The key idea is: the model failed to extract something; then we tell it the
answer (the missed gold relation), and ask it to reverse-engineer why it missed
it and how to avoid that mistake in the future. The “fresh extraction rule” is that generalized lesson.

*Example: regulatory / standards document*

Suppose the source document says:
```text
If a vaccine storage unit temperature exceeds 8°C for more than 10 minutes, an audible and visual alarm shall be triggered, and the event shall be logged for audit review.
```

The gold hyperedge (𝒢\* ) might be:

```text
Hyperedge H1:
{
  condition: temperature > 8°C for >10 minutes
  actor: vaccine storage monitoring system
  action_1: trigger audible alarm
  action_2: trigger visual alarm
  action_3: log event
  purpose: audit review
}
```

*Step 1: model fails*

The model extracts:

```text
{
  actor: vaccine storage monitoring system
  action: trigger alarm
}
```

It missed:

- the condition
- time threshold
- logging requirement
- audit purpose
- multi-action structure

So this relation goes into the Miss Set.

*Step 2: hindsight injection*

Now training tells the model:

```text
You missed this relation:

{
  condition: temperature > 8°C for >10 minutes
  actor: vaccine storage monitoring system
  action_1: trigger audible alarm
  action_2: trigger visual alarm
  action_3: log event
}
```

*Step 3: backtracking reasoning*

The model now reasons backward. Possible reasoning chain:

```text
The document contains a conditional clause:
"if temperature exceeds 8°C for more than 10 minutes"

This indicates activation condition.

The phrase:
"audible and visual alarm shall be triggered"

indicates multiple mandatory actions.

The phrase:
"the event shall be logged"

indicates an additional required action.

The previous extraction likely collapsed multiple coordinated actions into one generic action.
```

*Step 4: generate fresh extraction rule*

From this analysis, the model abstracts a reusable rule:

Example rule:

```text
Rule R_new:
When a sentence contains:

1. a conditional trigger ("if", "when", "upon")
2. mandatory modal verbs ("shall", "must")
3. coordinated action phrases joined by "and"

then:

- preserve the triggering condition
- split coordinated mandatory actions into distinct action nodes
- retain associated temporal thresholds
```

This is the fresh extraction rule.

*Another example: healthcare reporting*

Document:

```text
Suspected adverse immunization events shall be reported to the health authority within 24 hours.
```

Model extracted:

```text
{
  action: report event
}
```

Missed:

- who reports?
- recipient?
- deadline?
- modality ("shall")

Gold relation:

```text
{
  subject: vaccination provider
  action: report
  object: suspected adverse immunization event
  recipient: health authority
  deadline: within 24 hours
  obligation: mandatory
}
```

Hindsight reasoning:

```text
I missed temporal constraints.
I ignored recipient phrases introduced by "to".
I collapsed obligation semantics.
```

Fresh rule:

```text
If a provision contains:
- modal obligation ("shall")
- reporting verbs ("report", "notify", "submit")
- recipient phrase ("to X")
- temporal constraint ("within N hours")

extract all as separate relation arguments.
```

This is basically *Failure-Driven Prompt Induction*.

Input:

```text
I missed this extraction.
Here is the correct answer.
Why?
What generalized rule would have helped?
```

Output:

```text
A reusable extraction heuristic.
```

So the "fresh extraction rule" is not a neural weight update.
It is more like adding a new skill to the skill library:

```text
SKILL_047:
extract_conditional_multi_action_compliance_requirements
```

This is why the paper calls it *skill-driven self-improvement*, not fine-tuning.

This generates a new question: how the skills are triggered? The paper is somewhat hand-wavy here.

It almost certainly does not blindly apply every skill in the global library. There must be some skill 
selection/orchestration mechanism—a “supervisor” that decides which skills are relevant for document D
or the current extraction state.

The architecture implicitly requires:

```text
Document D
   ↓
Skill selector
   ↓
Relevant skills
   ↓
Extraction
```

Likely implementation (based on paper pattern):

*1. General extraction starts*

The model gets:

```text
Document D
+
base instructions
+
some core/general skills
```

Produces draft hypergraph.

*2. Failures detected*

Compare against gold:

```text
Miss Set
Hit Set
```

*3. New skill synthesized*

Example:

```text
extract_conditional_multi_action_obligations
```

Added to global library.

*4. Future documents use skill retrieval*

When a new document arrives:

The model does something like:

```text
Given document D,
which skills are relevant?
```

Possible matching signals:

- keyword overlap
- semantic embedding similarity
- document type classification
- LLM reasoning

Example:

Document contains:

```text
if
shall
within 24 hours
report
```

Selector activates:

```text
extract_reporting_deadlines
extract_conditional_requirements
```

*Two possible architectures*

*Architecture A: explicit retrieval (most practical)*

Skill library:

```json
[
  {
    "name": "extract_reporting_deadlines",
    "description": "Extract mandatory reporting obligations with deadlines"
  }
]
```

Then retrieve top-k:

```text
query = embedding(document summary)
top 5 nearest skills
```

This is analogous to RAG.

Very practical.

*Architecture B: LLM self-selection (paper likely leans here)*

Prompt:

```text
Available skills:
- extract_reporting_deadlines
- extract_conditional_requirements
- ...

Which skills are relevant?
```

LLM chooses.

More flexible, less scalable.

The skills mentioned in the paper are probably not executable code. They are more likely natural-language 
extraction heuristic.

Example:

```text
Skill:
When provisions contain:
- modal verbs ("shall")
- reporting verbs
- temporal constraints

extract:
actor, obligation, recipient, deadline
```

So the LLM itself is both:

- planner
- executor

*Mapping to agent architecture*

This resembles:

```text
| Agent concept   | Paper equivalent     |
| --------------- | -------------------- |
| Skill registry  | Global Skill Library |
| Planner/router  | skill selector       |
| Worker          | extraction LLM       |
| Reflection loop | hindsight reasoning  |
```

== Prompts
=== Entity Extraction Prompt
You are a named entity recognition assistant responsible for identifying named entities from the 
given text. Text: text
Notes:
1. First, determine whether the text contains meaningful information. If it’s just meaningless symbols, output: State: False.
2. Extract all named entities from the text.
3. Each entity should have three parts: - name: The entity name, - type: The type of this entity - description: A brief description of
what this entity is.
4. Output the extracted entities as a list of objects. Output MUST be valid JSON only.
JSON format: {{”nodes”:[”name”:””,”type”:””,”description”:””]}}

=== Relation Extraction Prompt
You are an expert hypergraph extraction assistant. Extract complex relationships (hyperedges) that involve MULTIPLE entities
simultaneously from the given text.

Extraction Strategy
Follow this step-by-step approach for each relation:

Step 1: Identify Core Relations
- Look for events, actions, or states that connect entities
- Identify the primary relationship type (e.g., ”founded”, ”acquired”, ”located in”)
- Treat each event/action/state as ONE relation instance; do not split it into multiple pairwise relations.

Step 2: Check for Qualifying Arguments
- Scan for temporal qualifiers (years, dates, time periods)
- Look for spatial qualifiers (locations, places)
- Identify conditional qualifiers (circumstances, conditions)
Experiences: The following are reference patterns learned from previous extraction tasks. Important: Use these experiences
as guidance ONLY when they are relevant to the current extraction scenario. If an experience does not apply to the current case,
simply ignore it and proceed with the extraction based on the relation types defined above. {experiences}
CRITICAL RULES: 1. A hyperedge can connect 2, 3, or more entities (e.g., a meeting with multiple people).
2. Identify ALL participants for each relationship.
3. ONLY use entities from the provided ’Known nodes’ list.
4. If an entity is not in the ’Known nodes’ list, exclude it from the hyperedge.
Known nodes: {known nodes}
Text: {text}

=== Skill Update Prompt
You are an expert knowledge manager for hyperedge extraction. Your task is to update an experience pool by integrating new
experiences while maintaining quality and avoiding redundancy.
The core of an experience is (1) a TRIGGER cue (either scenario cue or anchor cue) and (2) the minimal justification that the Known
nodes jointly instantiate ONE hyperedge.
Additionally, while processing new experiences, you may proactively flag and remove/merge redundant or weak items in the
existing pool if doing so improves overall clarity and coverage.
Current Experience Pool
{existing experiences}
New Experiences to Process
{new experiences}
Important: New experiences are provided as raw text in one or more ‘<Insight> … </Insight>‘ blocks (the same format produced
by the reflection prompt). Each block contains:
- ‘SKILL: …‘ (Default to RELATION DISCOVERY)
- ‘TRIGGER: …‘
- ‘ACTION: …‘
Your Task:
For each new ‘<Insight>‘ block, decide ONE operation:
1. ADD: Add it if it provides unique, high-impact guidance not covered by existing experiences.
2. MERGE: If it overlaps with existing experiences, merge into ONE clearer, more reusable experience; specify which existing
IDs to merge with.
3. SKIP: If fully covered / redundant / too vague.
4. DELETE: If it reveals an existing experience is misleading/useless; delete the old one.
Constraint Rules
- Keep the flat structure: each experience has only ‘trigger‘, ‘action‘.
- TRIGGER may be either:
(a) a scenario cue (domain setting / discourse pattern / evidence style), OR
(b) an anchor cue (event/state + role/discourse binding),
but NOT a keyword list and NOT entity names.
- ACTION must be the minimal justification that the Known nodes jointly instantiate ONE hyperedge (no procedural checklists;
avoid multi-step recipes).
- For any new or merged experience you output (ADD or MERGE), keep ‘trigger + action‘ within 50 words total (space-separated).
Be concise.
- Reject schema-paraphrase insights: SKIP items whose trigger/action merely rephrase a relation schema (slot listing or “…
instantiate \<edge type\>”) without transferable cue or disambiguation.
When merging: preserve the most reusable TRIGGER (scenario cue or anchor cue) and rewrite ACTION into the same minimaljustification style (do not invent unsupported details).
Output Format
Return a JSON array of operations.
“‘json [ {{”operation”: ”ADD”, ”trigger”: ”\<trigger\>”, ”action”: ”\<action\>”}}, {{”operation”: ”MERGE”, ”trigger”: ”\<merged trigger\>”,
”action”: ”\<merged action\>”, ”merge with ids”:
"𝐸0", "𝐸1"
}}, {{”operation”: ”SKIP”, ”reason”: ”\<brief reason\>”}}, {{”operation”: ”DELETE”, ”target id”: ”E0”, ”reason”: ”\<brief reason\>”}} ]

=== Unstable Set Reflection Prompt
```text
You are an expert hyperedge extraction coach. Your task is to analyze ONE successful extraction case and distill ONE reusable skill.
Context Original Text: {text}
Target Hyperedge (Ground Truth): - Nodes: {nodes} - Edge Type: {type} - Description: {description}
Successful Reasoning (from the extractor): {success reasoning}
Predicted Edge (successful): {success edge}
Goal Produce exactly ONE skill that is maximally reusable (can be scenario-specific OR general):
- SKILL must be RELATION DISCOVERY
- TRIGGER can be either:
(a) a scenario cue (domain setting / discourse pattern / evidence style), OR
(b) a relation anchor cue (event/state + role binding),
but NOT a keyword list and NOT entity names.
- ACTION is the minimal justification that the Known nodes jointly instantiate ONE hyperedge.
Output constraints
- Output exactly ONE <Insight> block and nothing else.
- Total length inside <Insight> must be <= 50 words (space-separated).
- Avoid schema paraphrase: do NOT restate the edge type or enumerate its slots (e.g., “X,Y,Z instantiate <edge type>”); instead state
a reusable cue and minimal evidence-binding rationale.
- Do NOT include any specific entity names; use role placeholders (PERSON/ORG/PLACE/TIME/AMOUNT/etc.).
Examples
<Insight>
TRIGGER: reported-attribution frame (“SOURCE says/according to SOURCE”) linking an act/state to a subject and a target
ACTION: treat SOURCE as evidence context; bind subject+target under the attributed act/state as one relation instance
</Insight>
```
=== Miss Set Reflection Prompt
```text
You are an expert hyperedge extraction coach. Your task is to analyze ONE hard case where no successful trajectory is available,
and propose ONE reusable experience that would help an extractor recover the gold hyperedge.
Hard-case setting: you ONLY have the original text and the ground-truth hyperedge (no predicted edge, no successful reasoning).
Your job is to infer a plausible cue that anchors the gold relation and express the minimal evidence-binding rationale that would
justify forming that ONE hyperedge from the Known nodes.
Context
Original Text:
text
Target Hyperedge (Ground Truth):
- Nodes: nodes
- Edge Type: type
- Description: description
Goal
Produce exactly ONE experience that is maximally reusable (can be scenario-specific OR general):
- SKILL must be RELATION DISCOVERY
- TRIGGER can be either:
(a) a scenario cue (domain setting / discourse pattern / evidence style), OR
(b) an anchor cue (event/state + role/discourse binding),
but NOT a keyword list and NOT entity names.
- ACTION is the minimal justification that the Known nodes jointly instantiate ONE hyperedge, grounded ONLY in the provided text.
Output constraints
- Output exactly ONE \<Insight\> block and nothing else.
- Do NOT include any specific entity names; use role placeholders (PERSON/ORG/PLACE/TIME/AMOUNT/etc.).
- Total length inside \<Insight\> must be <= 32 words (space-separated).
- Avoid schema paraphrase: do NOT restate the edge type or enumerate its slots (e.g., “X,Y,Z instantiate <edge type>”); instead state
a reusable cue and minimal evidence-binding rationale.
- Do NOT invent facts not supported by the text; if evidence is implicit, phrase TRIGGER/ACTION in terms of the implicit cue (e.g.,
definitional apposition, attribution frame, causal connector, institutional role frame).
Output Format (MUST follow exactly)

<Insight>
SKILL: RELATION DISCOVERY
TRIGGER: …
ACTION: …
</Insight>
```

== SemOS Solution


== References
[1]: https://www.opentrain.ai/papers/hyper-kggen-a-skill-driven-knowledge-extractor-for-high-quality-knowledge-hyperg--arxiv-2602.19543/?utm_source=chatgpt.com "Hyper-KGGen: A Skill-Driven Knowledge Extractor for High-Quality Kn…"

