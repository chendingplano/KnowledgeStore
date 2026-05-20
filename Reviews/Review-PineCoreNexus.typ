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
    "Review - Pinecore Nexus"
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
  Source: "https://www.pinecone.io/product/nexus/",
  ArtifactType: "Project",
  DocumentDate: "2026/05/20",
  Keywords: [Knowledge System, Knowledge Engine, Pinecone, Nexus],
)

#let a_001 = link(
  "https://www.pinecone.io/product/nexus/"
)[#text(fill:blue)[Pinecone Nexus]]

= Overview
Pinecone Nexus is Pinecone’s attempt to move beyond classic vector-database-centric RAG into what it calls a “knowledge engine” for AI agents. The core premise is that current agents waste substantial effort repeatedly retrieving, assembling, and interpreting context at inference time. Nexus shifts that work upstream: instead of making the LLM repeatedly search raw corpora, it pre-compiles enterprise data into task-optimized knowledge artifacts that agents can query directly. Pinecone positions this as infrastructure for agentic systems rather than simply another retrieval layer. ([Pinecone][1])

Architecturally, the interesting idea is the separation between *raw source data* and *compiled knowledge*. Nexus introduces a “context compiler” that transforms documents, structured data, and metadata into representations optimized for downstream agent tasks. Rather than retrieving dozens of document chunks and expecting the LLM to synthesize them, Nexus can serve pre-assembled artifacts such as aggregated fact sheets, structured summaries, or task-specific knowledge views. Pinecone also pairs this with KnowQL, a declarative query interface intended to replace bespoke retrieval toolchains with a single knowledge access layer. This is conceptually closer to a semantic execution layer than conventional embedding search. ([Pinecone][2])

From a product positioning perspective, Nexus directly addresses pain points common in agent engineering: low task completion rates, high token burn, latency unpredictability, and brittle multi-step retrieval orchestration. Pinecone claims substantial gains—higher completion rates, significantly fewer tokens, and much faster execution—because the agent consumes already-structured knowledge rather than repeatedly reconstructing context from raw evidence. Built-in provenance, field-level citations, and RBAC suggest enterprise deployment is a primary target, especially for regulated or access-controlled knowledge domains. ([Pinecone][1])

Strategically, Nexus represents a broader shift in the AI infrastructure stack. Traditional RAG treats
retrieval as a runtime problem; Nexus treats knowledge preparation as a compilation problem.
That distinction matters. Future knowledge system must be “explorable” — where knowledge is 
progressively normalized, structured, and made directly consumable by LLMs. Nexus is 
philosophically aligned. Pinecone presents this as managed infrastructure for enterprise 
agents, whereas the 'explorable file system' approach emphasizes transparent filesystem-native 
exploration and user-controlled knowledge representation. In short: Pinecone Nexus is less 
“better vector search” and more “precomputed agent knowledge middleware.”

== KnowQL
KnowQL is Pinecone’s proposed declarative query language for AI agents in the Nexus knowledge engine. 
The key idea is that agents should stop doing low-level retrieval orchestration (“search chunks, 
rerank, fetch more, synthesize, repeat”) and instead declare what knowledge they need, while Nexus 
decides how to satisfy that request. Pinecone explicitly compares this to SQL: SQL says what data you want, 
not how to scan indexes or execute joins; KnowQL tries to do the same for agent knowledge access. ([Pinecone][1])

Most agent systems work roughly like this:

```text
Agent question
   ↓
Generate retrieval query
   ↓
Vector search
   ↓
Get 20 chunks
   ↓
Rerank
   ↓
Realize missing info
   ↓
Another query
   ↓
Fetch structured data
   ↓
Merge results
   ↓
LLM reasons over giant context
```

This is effectively agentic RAG orchestration. The problems with this method are many, including:

- too many tool calls
- high token cost
- slow latency
- unstable outputs
- hard governance
- repeated reasoning over same corpus

Pinecone thinks the agent should not repeatedly reconstruct knowledge from raw evidence. 
Instead, agent asks for an answer; it passes the request to KnowQL, which decides
how to retrieve or compose plans and eventually returns what the agent really needs.

Under the hood, instead of:

```python
search("customer contract renewal terms")
search("billing history")
search("support escalations")
merge_results()
summarize()
```

agent expresses:

```text
Give me:
- renewal risk
- billing anomalies
- unresolved escalations
for customer X
with citations
```

Nexus decides:

- which contexts
- which artifacts
- which indexes
- which retrieval modes
- how deep to search
- how to compose answers

That is the core abstraction.

=== Six Primitives

Pinecone describes six core primitives.

==== Ask

This is intent. It defines:

- what the agent wants
- expected answer
- target knowledge domains

Example:

```text
ask:
  "Summarize renewal risk for Acme Corp"
```

This is the semantic objective.

==== Where

Deterministic constraints, qquivalent to SQL WHERE, subject to access controls.

Examples:

```text
where:
  customer = "Acme"
  region = "US"
  product = "Enterprise"
```

==== Ground

Provenance requirements.

Example:

```text
ground:
  field_level_citations = true
```

Every returned field should indicate source evidence.

Instead of:

```json
{
  "risk": "high"
}
```

you get:

```json
{
  "risk": {
    "value": "high",
    "source": "CRM/opportunities/renewal_123",
    "confidence": 0.94
  }
}
```

Referencing to the oringinal supporting materials is very important for grounding.

==== Shape

Typed output schema. This is arguably the most important part. Classic RAG often returns results
in arbitrary formats. KnowQL lets agents define the result formats, such as:

```json
{
  "customer": "Acme",
  "renewal_probability": 0.72,
  "top_risks": [
    ...
  ]
}
```


==== Confidence

It separates between grounded facts and uncertain inference.

Example:

```json
{
  "billing_issue": {
    "value": true,
    "confidence": 0.96
  },
  "likely_churn_driver": {
    "value": "support dissatisfaction",
    "confidence": 0.58
  }
}
```

Without this, agents treat speculation as fact.

==== Budget

This is unusual and interesting. Agent specifies execution constraints:

- latency ceiling
- depth
- token envelope

Example:

```text
budget:
  latency < 500ms
  depth = medium
```

==== What a hypothetical KnowQL query might look like

Pinecone has not published a final formal syntax, but conceptually:

```yaml
ask:
  "Assess renewal risk for customer Acme"

where:
  customer_id: "C12345"
  business_unit: "enterprise"

shape:
  renewal_risk: number
  risk_factors: list<string>
  unresolved_incidents: integer

ground:
  citations: field_level

confidence:
  include_scores: true

budget:
  latency_ms: 500
  depth: medium
```

Response:

```json
{
  "renewal_risk": {
    "value": 0.81,
    "citation": "crm/opportunity/renewal"
  },
  "risk_factors": [
    ...
  ]
}
```

==== Architectural implication

KnowQL implies the existence of a *knowledge planner*. Because when the agent says:

```text
Assess customer renewal risk
```

something must decide:

- query CRM?
- query support tickets?
- query billing?
- use precompiled artifact?
- join sources?
- aggregate?
- summarize?

That “something” is Nexus.

So KnowQL is only the front-end contract.

Behind it is an execution engine.

Analogy:

```text
| Layer          | SQL world       | Nexus world        |
| -------------- | --------------- | ------------------ |
| query language | SQL             | KnowQL             |
| planner        | query optimizer | knowledge planner  |
| storage        | tables/indexes  | artifacts/contexts |
| execution      | DB engine       | knowledge engine   |
```

This is much closer to database systems than classic RAG.

==== Comparison with traditional RAG

Traditional RAG:

```text
query → retrieve chunks → LLM synthesizes
```

KnowQL:

```text
intent → knowledge engine returns structured answer
```

Differences:
```text
| Dimension      | RAG          | KnowQL        |
| -------------- | ------------ | ------------- |
| output         | chunks       | typed answers |
| citations      | optional     | first-class   |
| planning       | agent code   | Nexus engine  |
| latency        | variable     | budget-aware  |
| schema         | unstructured | structured    |
| governance     | ad hoc       | built-in      |
| access control | external     | integrated    |
```

==== Comparison with SemOS Thinking

This should feel familiar.

SemOS model:

- normalize knowledge
- create structured intermediate representations
- build explorable knowledge objects
- avoid repeated brute-force retrieval
- expose knowledge in LLM-friendly form

KnowQL is philosophically similar.

Major difference:

SemOS model - explorable knowledge base, LLM navigates knowledge.

KnowQL - queryable knowledge service

==== assessment

Technically, KnowQL is compelling, but there are open questions:

- Query language or API contract?
- Is it truly a language like SQL?
- Or just structured JSON API semantics?
- How expressive is it? Can it express:

  - joins?
  - temporal predicates?
  - graph traversal?
  - recursive reasoning?
  - aggregation?

If not, “SQL for agents” is marketing-heavy.

*Planner transparency*

If Nexus chooses execution plan, can users inspect:

- why artifact X used?
- why source Y ignored?
- why confidence low?

Opaque planners become debugging nightmares.

== Organizing Knowledge

Organizing knowledge is the center to all knowledge system.

=== Domain Based
The figure below shows how Nexus organizes the knowledge by domains: 'Sales', 'Finance', 'Support', 'Marketing'.
The 'Domain' can be different in different environments and purposes. 

In ontology, the term 'Domain' is an ontology entity. It defines a high-level (or more often top-level)
classification of knowledge. We may view domains as 'collections' in Milvus or 'db' in relational
databases. An agentic bean can belong to one or more domains. 

At query time, the LLM analyzes user input, derive its intent, and then determine the domain(s)
to explore. This can significantly reduce the corpus size and remove irrelevant context.

#let a_001 = link(
  " news.ycombinator.com"
)[#text(fill: blue)[Pinecore Website]]
#figure(
   image("Images/image_2026052101.png", width: 100%),
   caption: [Nexus Organizing Knowledge by 'Domains'(#a_001)],
)

=== Compile Reasoning
Instead of letting LLMs to reason at inference time, it compiles (possibly using LLMs) the reasoning
and stores the reasoning.

Example: In Customer support escalation agent. a user asks: “Why is customer Acme 
threatening to cancel, and what should our account team do?”

Traditional RAG / inference-time reasoning does not has no precompiled knowledge.
So at inference time, the LLM must construct understanding from scratch, possibly:

*Step 1: Search CRM*

Retrieve:

```text
Opportunity: Renewal due in 42 days
Status: At risk
AE note: Customer unhappy with onboarding
```

LLM reads it. But incomplete.

*Step 2: Search support tickets*

Retrieve 15 ticket chunks:

```text
Ticket #9182:
API timeout issue

Ticket #9221:
SSO provisioning failure

Ticket #9250:
Escalation from VP Engineering
```

LLM reads all of them. Still incomplete.

*Step 3: Search billing*

Retrieve:

```text
Invoice overdue
Credit dispute
```

Still incomplete.

*Step 4: Search product telemetry*

Retrieve:

```text
Daily active users dropped 67%
```

*Step 5: LLM reasons*

Now the model must do reasoning like:

```text
Let me see...

Renewal is soon.
Usage dropped.
Support tickets increased.
Billing dispute exists.
Executive escalation happened.

Likely churn risk is high.
Main causes:
- product instability
- onboarding issues
- billing friction
```

This reasoning happens during every query.

This is expensive because:

- many retrieval calls
- many tokens
- repeated synthesis
- repeated cross-document reasoning

If 100 users ask similar questions, the same reasoning happens 100 times.
This is what Nexus means by *reasoning at inference time*.

Nexus moves reasoning upstream. Instead, Nexus precomputes knowledge.
Offline (before any user asks), it continuously compiles raw sources:

- CRM
- support
- telemetry
- billing
- notes

into a structured knowledge artifact.

Example compiled artifact:

```json
{
  "customer": "Acme",
  "renewal_risk": 0.92,
  "top_risk_factors": [
    {
      "factor": "API reliability",
      "evidence": 14
    },
    {
      "factor": "SSO onboarding failures",
      "evidence": 6
    },
    {
      "factor": "billing dispute",
      "evidence": 1
    }
  ],
  "usage_trend": {
    "delta_30d": "-67%"
  },
  "executive_escalation": true,
  "recommended_actions": [
    "assign support escalation engineer",
    "resolve invoice dispute",
    "schedule executive review"
  ]
}
```

Notice what happened. The expensive reasoning:

- correlate tickets
- aggregate telemetry
- infer churn factors
- identify trends
- connect billing + support + CRM

already happened **before the LLM query**.

At inference time now, user asks: “Why is Acme threatening to cancel?”

LLM gets:

```json
renewal_risk=0.92
top_risk_factors=[...]
recommended_actions=[...]
```

Now the frontier model does:

```text
Generate response for human.
Tailor tone.
Answer follow-up questions.
Suggest next actions.
```

NOT:

```text
Read 200 chunks.
Correlate evidence.
Infer root causes.
Aggregate signals.
Construct facts.
```

Suppose raw inference costs:

- 40 retrieval calls
- 120k tokens
- 9 seconds latency

Precompiled Nexus query:

- 1 knowledge query
- 5k tokens
- \<1 second

Same answer quality, often better.

Traditional RAG: LLM = detective. For every request:

```text
find clues
read evidence
build case
write conclusion
```

In Nexus, LLM = decision-maker. System already prepared the case:

```text
here are the findings
here is confidence
here is provenance
```

LLM focuses on:

- task completion
- planning
- interaction
- decision support

instead of document archaeology.

Note that the central idea of “Moves reasoning out of inference time”
is to convert repeated runtime cognition into precomputed knowledge compilation.
Instead of making GPT repeatedly think through the same evidence, make 
infrastructure think once and cache the result structurally.

The idea is very good! But there are a few catches. First, Nexus must know beforehand 
about what 'reasoning' needs to be compiled (or will it?). When the corpus is big, 
there can be too many 'reasoning'. 

Second, content evolves all the time. As new content enters the system, it needs to 
know which reasonings are affected. It is even possible that new content triggers new 
reasonings. Handling these can be very computing intensive and LLMs heavy. Third, if 
there are many reasonings, some of the compiled reasonings are not used at all before 
they get updated (possibly due to new content, improvement of compiling reasoning, etc.). 
This can cause waste on preparing the knowledge.

To tackle these problems, we first need to determine:

> Which reasoning should be materialized, when, at what granularity, 
and with what invalidation strategy?

A practical system cannot compile “all possible reasoning.” That explodes combinatorially.

So the likely solution is not full eager compilation. It has to be a hybrid:

```text
raw content
  ↓
cheap universal preprocessing
  ↓
semi-structured knowledge objects
  ↓
selective materialized reasoning
  ↓
runtime reasoning fallback
```

The system can eagerly compile only broadly reusable artifacts, such as:

```text
customer profile
product summary
contract obligations
known risks
open issues
entity relationships
document-level facts
```

But highly specific questions still need runtime reasoning.
So “move reasoning out of inference time” should mean:

> precompute (highly) reusable intermediate reasoning so runtime reasoning becomes cheaper.

That distinction matters.

==== Invalidation

If new content arrives, the system must know what compiled artifacts are affected. 
This requires dependency tracking.

For example:

```text
support_ticket_9250
  affects → customer_acme_risk_summary
  affects → renewal_risk_artifact
  affects → open_escalations_view
```

So each compiled reasoning object needs metadata like:

```json
{
  "artifact": "acme_renewal_risk",
  "depends_on": [
    "crm/opportunity/123",
    "support/ticket/9250",
    "billing/invoice/778"
  ],
  "compiled_at": "2026-05-21",
  "compiler_version": "risk-v3"
}
```

When new content arrives, the system can ask:

```text
Which artifacts depend on this entity, topic, product, customer, clause, or time range?
```

But this is hard. Direct dependencies are manageable. Semantic dependencies are much harder.

Example:

```text
New regulation changes definition of "medical device".
```

That may affect thousands of artifacts that never directly cite the new regulation.

So the system needs both:

```text
exact dependency graph
+
semantic impact detection
```

This can be LLM-heavy.

==== Stop Compiling

For compiled reasonings, if they were not used for long time, especially the ones
that kept updating due to new contents, we may need to stop compiling it.
This is similar to materialized-veews vs. non-materialized views in relational
databases. In databases, you do not materialize every possible query result. 
You materialize only high-value views.

Same principle applies to compiled reasonings.

```text
compile cheap things eagerly
compile expensive things lazily
promote frequently-used reasoning to cached artifacts
expire unused artifacts
```

For example:

```text
First query about Acme renewal risk:
  runtime reasoning happens

Second/third/fourth similar query:
  system notices repeated demand

Then:
  materialize "Acme renewal risk artifact"
```

So the system should be demand-driven, not purely corpus-driven.

That means:

1. Build general-purpose knowledge representations.
2. Track user/query/task patterns.
3. Materialize high-value recurring reasoning.
4. Maintain dependency links.
5. Invalidate or refresh only affected artifacts.
6. Fall back to runtime reasoning when no compiled artifact exists.

We may need to add a layer to SemOS:
```text
L0 raw docs / logs / traces
L1 chunks / summaries / facts / topics / provisions
L2 summaries / facts / topics / provisions
L3 Semantic Objects (TencentDB Agent Memory)
L4 scene blocks / normalized knowledge objects
L5 materialized reasoning views
```

Examples of good L5 candidates:

```text
product compliance profile
standard applicability matrix
clause-to-product obligation map
risk summary for a module
open design-decision summary
current state of a feature
```

Bad L3 candidates:

```text
every possible comparison
every possible Q&A
every possible cross-document inference
```

== References
[1]: https://www.pinecone.io/lp/nexus-ea/?utm_source=chatgpt.com "Pinecone Nexus: Early Access | Pinecone"

[2]: https://www.pinecone.io/newsroom/Pinecone-Launches-First-Serverless-Region-in-Asia/?utm_source=chatgpt.com "Pinecone Launches First Serverless Region in Asia with New Singapore Cloud Region, Bringing the Knowledge Infrastructure for AI to the Asia-Pacific Market | Pinecone"

[1]: https://www.pinecone.io/product/nexus/?utm_source=chatgpt.com "Pinecone Nexus | Pinecone"

[2]: https://www.pinecone.io/blog/knowledge-infrastructure-for-agents/?utm_source=chatgpt.com "Pinecone Nexus: The Knowledge Engine for Agents | Pinecone"
