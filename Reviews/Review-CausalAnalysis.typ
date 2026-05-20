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
    "Review - Causal Modeling and Analysis"
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
  Source: "https://mp.weixin.qq.com/s/2qIcyrSihqkOawtkFgsajw",
  ArtifactType: "Article",
  DocumentDate: "2026/05/24",
  Keywords: [Data Model, Knowledge Model, Causal Modeling, Causal Analysis],
)

#let a_001 = link(
  "https://mp.weixin.qq.com/s/2qIcyrSihqkOawtkFgsajw"
)[#text(fill:blue)[TencentDB Agent Memory]]

= Overview
Read #a_001 first. My thinkingg is that in constructing SemOS, one of the challenges is to
build SemOS in such a way that LLMs can use the knowledge stored in SemOS to reason, to
find something deep in the corpus. 

Raw corpus retrieval has a structural problem:

- relevant evidence may be fragmented
- concepts may be implicit
- relationships may be distributed across documents
- causality is often never stated in one place
- terminology varies
- evidence chains span multiple artifacts

Example:

A regulatory corpus may contain:

Document A:

> Vaccine refrigerators must maintain 2–8°C.

Document B:

> Temperature excursions require investigation.

Document C:

> Continuous monitoring alarms shall be configured.

Document D:

> Improper vaccine storage may reduce potency.

A naïve RAG system retrieves fragments.

SemOS should make this explorable as:

```text
temperature_excursion
    causes:
        potency_loss
        compliance_violation
        investigation_requirement

continuous_monitoring_alarm
    mitigates:
        undetected_excursion

vaccine_storage_requirement
    depends_on:
        temperature_control
```

This is no longer document retrieval. This is semantic exposure engineering.
That is the real value of SemOS.

The article discusses:

- regression
- panel models
- DID
- mediation
- SEM
- spatial econometrics

These are formal quantitative causal inference methods.
SemOS likely needs something different.

== Causal Model

There are at least 4 meanings of "causal model":

=== Statistical Causal Inference

This is what the article describes.

Its pattern is:

> Did policy X cause outcome Y?

Examples:

- Did low-carbon pilot policy reduce emissions?
- Did fintech increase innovation?

Requires:

- datasets
- experimental assumptions
- counterfactual reasoning
- identification strategies

This is academic econometrics.

SemOS probably does not need this as its core architecture
because SemOS is primarily about knowledge representation and 
retrieval, not empirical effect estimation.

=== Semantic Causal Graph

Pattern:

> What causes what according to the knowledge corpus?

Examples:

- overheating → battery degradation
- weak authentication → unauthorized access
- improper sterilization → contamination risk

This is much more relevant.

Nodes:

- conditions
- events
- states
- risks
- mitigations
- outcomes

Edges:

- causes
- enables
- prevents
- mitigates
- requires
- depends_on
- precedes
- triggers

This absolutely belongs in SemOS.

=== Procedural Causality

Pattern:

> What operational steps lead to what consequences?

Example:

```text
user submits application
→ validation runs
→ approval workflow triggered
→ notification sent
→ audit log written
```

This is workflow causality.

Critical for:

- system documentation
- SOPs
- operational standards
- software architecture docs

Also important for SemOS.

=== Epistemic Causality (reasoning provenance)

Pattern:

> Why does SemOS believe X?

Example:

```text
claim:
vaccines_must_be_monitored_continuously

supported_by:
ISO clause 4.2
CDC storage guidance
manufacturer IFU

reasoning:
continuous monitoring reduces missed excursions
missed excursions can compromise potency
```

This is explainability causality. Extremely important to SemOS.

== Statistical Models

SemOS may need statistical models.

=== Regression

This tells:

> variable X correlates with variable Y

```json
{
  "claim": "digital economy positively associated with green development",
  "evidence_type": "regression",
  "confidence": ...
}
```

=== Panel Models

Same story.

Useful as encoded research findings, not SemOS infrastructure.

=== DID

Potentially useful if SemOS stores research evidence.

Example:

```text
policy_effect_claim:
low_carbon_policy improves emission efficiency

method:
difference_in_differences

assumptions:
parallel_trends
```

Again: content inside SemOS, not SemOS’s architecture.

=== Mediation models

Now this gets interesting because mediation explicitly models:

```text
X → M → Y
```

Example:

```text
security_training
→ user_awareness
→ reduced_phishing_incidents
```

SemOS should absolutely represent mediated mechanisms.

This becomes:

- mechanism graph
- path reasoning
- explanatory traversal

=== SEM (Structural Equation Modeling)

This is conceptually relevant, but not operationally.

SEM introduces:

- latent constructs
- multi-path causality
- networked influence

SemOS equivalent:

```text
security_posture
    influenced_by:
        patch_management
        access_control
        staff_training
```

This is similar structurally.
But SemOS likely does not need SEM math. It needs graph semantics.

The article repeatedly talks about:

> 作用机制
> 传导路径
> 中介路径
> 多路径机制

This is the gold because SemOS is about knowledge navigation.
Mechanism knowledge is much more valuable than raw facts.

Example:

Raw fact:

> Ransomware encrypts systems.

Mechanism:

```text
phishing_email
→ credential_compromise
→ unauthorized_access
→ lateral_movement
→ ransomware_execution
→ service_disruption
```

This enables:

- root cause analysis
- preventive reasoning
- dependency tracing
- explanation generation

This is highly aligned.

== SemOS Layers

=== Layer 0 — Source artifacts

Raw:

- PDFs
- standards
- specs
- emails
- chat logs
- execution traces
- source code
- tickets

=== Layer 1 — Normalized knowledge objects

Extract:

- entities
- concepts
- requirements
- definitions
- metrics
- obligations
- workflows
- events

=== Layer 2 — Relational semantic graph

Edges:

- refers_to
- defines
- requires
- supersedes
- derived_from
- related_to

=== Layer 3 — Causal Knowledge Graph

Specialized causal edges:

- causes
- contributes_to
- enables
- inhibits
- mitigates
- depends_on
- triggers
- precedes
- propagates_to
- results_in

Example:

```text
expired_certificate
    causes:
        tls_failure

tls_failure
    causes:
        service_unavailability

certificate_monitoring
    mitigates:
        expired_certificate
```

=== Layer 4 — Mechanism Templates

Generalized reusable patterns:

Examples:

*Failure Propagation*

```text
condition → intermediate_failure → system_failure
```

*Compliance Chain*

```text
requirement_violation → audit_finding → remediation
```

*Security Kill Chain*

```text
access → privilege_escalation → persistence → exfiltration
```

*Supply Chain*

```text
supplier_delay → inventory_shortage → production_impact
```

These are reusable causal schemas.

=== Retrieval becomes dramatically stronger

Without causal model:

query:

> Why did vaccine potency risk occur?

RAG retrieves fragments. With causal graph, it traverse:

```text
potency_risk
← caused_by temperature_excursion
← caused_by monitoring_failure
← caused_by alarm_misconfiguration
```

Now SemOS can explain. This is a major leap.

== Biggest Engineering Challenge

The hard problem is not storing causal edges.
It is extracting trustworthy causality.
Documents express causality differently:

Explicit:

> X causes Y

Implicit:

> Failure to rotate keys may result in compromise

Normative:

> Systems shall monitor for overheating

Counterfactual:

> Without encryption, data may be exposed

Probabilistic:

> Smoking increases cancer risk

Procedural:

> Upon failure, restart service

Derived:

multiple facts imply causality but never state it directly

This is difficult.

== Suggested extraction ontology

SemOS should normalize causal relations into a constrained vocabulary.

Example:

```json
{
  "relation_types": [
    "causes",
    "contributes_to",
    "enables",
    "prevents",
    "mitigates",
    "depends_on",
    "requires",
    "triggers",
    "precedes",
    "derived_from"
  ]
}
```

Avoid free-form relation explosion.

== A Stronger Conceptual Framing

Instead of "Causal Model", a better name is *Mechanism Knowledge Model*
or *Causal Knowledge Graph* or *Influence Graph* because "causal model" 
suggests statistical inference.

SemOS is closer to:

- knowledge engineering
- semantic reasoning
- explainable retrieval
- mechanism tracing

than econometrics.

== Conclusion
The valuable transferable concepts from this article are:

- mechanism identification
- mediation/path reasoning
- multi-step influence chains
- networked dependency modeling
- indirect effect representation

SemOS should likely include a *causal/mechanism layer*, but implemented as 
*semantic causal knowledge structures*, not statistical causal inference machinery.

The article gives conceptual inspiration, especially:

> 中介效应模型 (mediation)
> 作用机制识别 (mechanism identification)
> 多路径机制 (multi-path mechanisms)

Those are highly aligned with SemOS.

SemOS starts looking less like “RAG with better indexing” and more 
like a *semantic operating system for mechanism-aware knowledge reasoning*, 
which is a much more ambitious and interesting architecture.

