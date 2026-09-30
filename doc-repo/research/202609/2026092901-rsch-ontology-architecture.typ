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
    "Ontology Architecture"
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
  logical_name: "2026092901-rsch",
  file_id: "2026092901-rsch",
  source: "",
  content_type: "research",
  document_date: "2026/09/29",
  keywords: [ontology, ontology architecture, china palantir],
)

#let ref_china_palantir = link(
  "https://www.toutiao.com/article/7690401759138710058/?app=news_article&category_new=__all__&module_name=iOS_tt_others&req_id_new=20260929031740D05023942D785F16B9BA&share_did=MS4wLjACAAAAw3rqzAbRbSo4klPah7FJFhb-dpoy0Y2_hu6Pcvvt2pc&share_token=b9ee8484-bb71-11f1-be5c-a088c22778dc&share_uid=MS4wLjABAAAAw3rqzAbRbSo4klPah7FJFhb-dpoy0Y2_hu6Pcvvt2pc&timestamp=1790623255&tt_from=weixin&upstream_biz=iOS_wechat&use_new_style=1&utm_campaign=client_share&utm_medium=toutiao_ios&utm_source=weixin&wxshare_count=1&source=m_redirect"
)[#text(fill: blue)[China's version of Palantir]]

#ref_china_palantir

= Ontology Model

The ontology model has four layers:
- Application Layer
- Ontology Layer
- Model Layer
- Data Layer

Data are integrated into the model layer. Model layer defines:
- constraints
- allowed properties
- name normalization and unification
- value normalization and unification
- ...

The ontology layer uses the models to:
- reasoning
- make decision
- actions
- write-back
- ...

#figure(
  image("../../../Images/image_2026092901.png"),
  caption:["Four-Layer Model"],
)

== Ontology Layer
It consists of:
- Entity
- Relations
- Actions

Focus on:
- What an enterprise has (entities)
- How they are related (relations)
- What we can do about the entities (actions)

Each entity may map to a model in the Model Layer,
which defines constraints, relations, actions, values,
names, etc. The ontology layer uses the entities,
the Model Layer defines them.

The entities are not the entities NER (named entity-relation extraction)
refers, which are at much lower layer. We can call the entities 
defined in the Model Layer 'Business Semantic Entity' (BSE).

Users can use the frontend page to create, review, modify, and delete
BSEs.

=== Decision Module
This module manages the decisions: when something happens, do something.
Most decisions are defined in form of rules.

It uses a decision LLM model, such as the System One model, to handle
undeterministic decisions.

=== Ontology write-back
After the ontology module made a decision, it should write back about the
decision, either as a log, or possibly modify the ontology itself, such
as:
- Adding new rules (such as 'when fixed a bug, add a test suite to 
  the smoke test module')

The most important benefits of writing back is to make ontology more
and more useful as it is used more.

Ontology Write-Back resides in the Ontology Layer.

=== Enforce Guard Rails
Any time when the ontology makes decisions, make sure check the guard rails
to ensure the entire system strictly follows the defined guard rails.

=== Errors and Bugs
When problems occur, such as software bugs, workflow errors, product
quality issues, customer feedbacks, etc.

- Create rules to avoid the problem in the future
- Modify rules
- Modify workflows
- Modify decision chains
- Modify the reasoning

This is a form of self-learning/self-improvement, extremely important.

== Model Layer

==== Name Module
This module normalizes names. It solves the problem of different systems,
modules, databases, datasets, etc., use different names for the same thing.
Any time when a name is used, it should look up this module. If it matches
one and only one entry, use its canonical name.

If more than one entries are found, it is ambiguous. We may use a decision
model to let LLMs decide which one it really belongs to.

If none is matched, we should add it to the module, with a flag 'proposed'.

SemOS Keyword Manager is responsible for this.

In a deployment, we should list all the important names, such as:
- Product Names
- Part Names
- Department Names
- Employee Names
- Vendor Names
- Equipment Names
- And so on

The frontend should have a 'Name Manager', which lets users create, review, 
modify, query and delete names, including individual names and namespaces.

Name Model resides in the Model Layer

==== Rule Module
- Rules should be separated from code
- Rules are centrally managed
- "企业最贵的从来不是数据，是那些没被写下来的专家规则"
- Updating rules should not require restarting the system, normally
- If updating a rule requires restarting the system, how to
  control the switch over?
- Rules and schemas?
- Rules should be versioned
- Rule format?

Rule Module resides in the Model Layer.

==== Workflow Module
Workflow Model manages workflows.

==== Actions
One of the most important purposes of using ontology is to make decisions.
Decisions normally relate to actions.

Actions are related to BSEs and defined in the Model Layer.

==== Guard Rails
This module manages the gard rails.

=== Deployment

==== Step 1: Investigation
- What BSEs the enterprise has/uses
- relations among BSEs
- rules
- workflows
- names
- actions
- reasoning

==== Step 2: Incremental 

Don't start with everything. Start small, add more incrementally.

==== Step 3: Agents
Agents are in the application layer. 
- Write agents for applications

==== Step 4: Evaluation

Check whether it works, how much it improves

==== Step 5: Human Involvement

All steps should involve human experts.

==== Errors People Often Make

===== Over engineering

Start with hundreds or even more BSEs, relations, etc., without first 
actually use the ontology. Start small, test it, evaluate it, use it,
and incrementally improve it.

===== Semantic Alignment

This is quite conceptual. What it really means is: use the same semantics
for the same BSEs or the related. For instance, when making decisions,
use the same decision model regardless of which agents are used. Avoid
Agent A uses one decision model and Agent B uses another decision model.

===== Hard-Code Rules

Do not hard-code rules. Separate rules and code, make rules dynamic.
Rules should fully use the ontology model.

===== Wrong Decisions

When the ontology model writes back, be careful writing back the wrong
decisions. 

Human users may need to review the decisions the system made. This is 
especially important for the ones that causes writing back.

