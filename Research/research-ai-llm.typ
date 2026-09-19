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
    "Research - LLMs"
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
  logical_name: "research-ai-llms",
  file_id: "2026091901",
  source: "",
  content_type: "research",
  document_date: "2026/09/19",
  keywords: [LLM, Jev, TypeSafe, Decision Model],
)

= Scope

This document discusses LLM related topics, leaning toward how to use LLMs, 
such as LLM routing, Decision Models (Jev), etc.

== Jev

Jev is a new type of LLMs: instead of generating tokens, it makes decisions.
Because of that, it does not charge output tokens.

Similar to all LLMs, Jev requires context. 
TypeSafe describes the interface as:
```text
> state + typed questions → structured decisions
```

*State*

In Jev terminology, `state` is essentially *the context supplied by your application for the current decision*.

Jev evaluates every question independently against the same supplied state. Users can 
supply multiple questions with the same context. Jev answers them all in one call @introduction-typesafe-ai.

*Context*

If the information required to make the decision lives somewhere else—in a database, SemOS, documents, 
a knowledge graph, logs, etc. — *something upstream must retrieve/select that information and put it 
into `state`.* That upstream mechanism could absolutely be RAG, but it does not have to be.

Think of Jev as a function:

```text
Jev(state, questions) -> decisions
```

There are two different kinds of knowledge (same as other LLMs):

```text
                 Jev
                  │
        ┌─────────┴─────────┐
        │                   │
 Model knowledge       Supplied state
        │                   │
 learned during       current facts,
 training             records, documents,
                      retrieved evidence
```

For example:

```text
state = {
    "ticket": "The vaccine refrigerator reached 11°C for 45 minutes.",
    "device": "Model X200 data logger",
    "facility": "Clinic A"
}

questions = {
    "severity": ...,
    "requires_escalation": ...,
    "category": ...
}
```

Jev interprets the supplied information using knowledge encoded in its model parameters, much as an LLM 
understands the semantics of text. But Jev's job is *not knowledge retrieval*. Its job is to make a fast 
judgment over the state you supplied. TypeSafe explicitly characterizes good Jev questions as judgments 
that a knowledgeable person could make quickly *“given the right context.”* @introduction-typesafe-ai

That last phrase (given the right context) is crucial.

Suppose you ask:

```text
State:
  Vaccine was stored at 11°C for 45 minutes.

Question:
  Is this a serious temperature excursion?
```

Jev may have enough general knowledge encoded in its parameters to classify this intelligently.
But suppose your question is:

```text
According to SOP-CC-2026-17,
does this excursion require quarantine?
```

Jev cannot magically know your organization's SOP. You need something like:

```text
                  User/event
                      │
                      ▼
               Context builder
                 /    |     \
                /     |      \
             BM25  vector   graph/files
                \     |      /
                 \    |     /
                  relevant evidence (context)
                       │
                       ▼
                  Jev state
                       │
             ┌─────────┼──────────┐
             ▼         ▼          ▼
          choice     score       noul
```

The state might be assembled deterministically:

```python
state = {
    "ticket": ticket.text,
    "customer": db.get_customer(ticket.customer_id),
    "recent_events": event_store.last_24_hours(customer_id),
    "policy": search_policy(ticket.text),
}
```

Only `search_policy()` is RAG-like. The rest is ordinary program state.

For SemOS, Jev is not competing with its retrieval/exploration architecture. It sits *after or inside it*:

```text
                    SemOS
                      │
              Investigative search
                      │
        ┌─────────────┼──────────────┐
        ▼             ▼              ▼
     BM25         semantic        filesystem/
     search        search          graph explore
        │             │              │
        └─────────────┼──────────────┘
                      ▼
                evidence/state
                      │
                      ▼
                     Jev (Important!)
                      │
        ┌─────────────┼──────────────┐
        ▼             ▼              ▼
    relevant?     supported?     confidence?
       0.94           0.87           0.91
```

In fact, Jev could be useful *during retrieval*, not merely after retrieval.

Imagine SemOS retrieves 30 candidate provisions. Instead of asking an expensive generative LLM:

```text
Which of these provisions actually applies
to this vaccine-storage incident?
```

you could evaluate each candidate with Jev:

```text
state = {
    "question": user_question,
    "candidate": provision,
    "surrounding_context": context
}

questions = {
    "relevant": Noul(...),
    "direct_evidence": Noul(...),
    "specificity": Score(...)
}
```

Then SemOS keeps high-probability evidence and explores outward from uncertain candidates.

That fits remarkably well with the *candidate → investigative exploration* architecture we 
discussed for SemOS: conventional retrieval finds candidates; Jev can cheaply perform many of 
the fuzzy judgments that determine *which candidates to keep and where to 
explore next*. @introducing-system-one-models-and-jev-typesafe-ai-blog

So we can summarize the architectural relationship as:

*SemOS search engine searches “What information should Jev see (given the question)?”*

*Jev answers “Given this information, what judgment should the program make?”*

And a generative LLM can still sit afterward to answer the very different question:

*“Given the accumulated evidence and decisions, how should I reason about/explain the result?”*

That separation—*retrieval → fast judgment → deliberate reasoning/generation*—is one of the more 
interesting implications of Jev for SemOS.

=== Advantages of Jev

*Structured*

Jev is type-safe by construction. Decisions and probabilities confirm to
the structured software types and JSON schema your code expects, so it
never has to recover a value from generated prose.

*Parallel*

Questions are evaluated independently and in parallel. One primitive's
result does not become hidden context that changes another primitive's results.

*Comparable*

Outputs are sortable and can drive smart if-statements, thresholds and comparisions.

*Fast* 

Most queries complete in about 100 ms. Jev is fast enough for real-time request
paths and user interfaces.

*Calibrated Confidence*

RLCD communicates uncertainty through calibrated probabilities instead of 
tending toward overconfidence.

*Self-consistent*

Jev is designed to return stable answers across repeated evaluations.

== Post-Training

There are three types of post-training:
- RLHF (Reinforcement Learning from Human Feedback) turns
  pretrained models into chatbots. It trains models to produce
  responses people prefer (mainly for human users).
- RLVR (Reinforcement Learning with Verifiable Rewards) creates
  reasoning models that are strong at tasks such as mathematics,
  but slower and more expensive.
- RLCD (Reinforcement Learning for Calibrated Decisions) trains
  TypeSafe to return decisions and calibrated probabilities 
  instead of generated text (Jev)

=== Limitations of RLHF

RLHF teaches a model to say things that people prefer. It is important
for chatbots, but not necessarily idea for software.

=== Jev and LLMs

Jev changes the way how LLMs are used. Instead of generating text for
chatting, which is mainly for human users, Jev requires the user/apps
to pass 'state' and one or more questions. Each question is about making
decisions: binary decision (yes/no), choices (select one from multiple
choices) and scores (generate scores for a given list of choises).

In an app/agent, it often needs to make decisions. When that happens,
we can use either LLMs (mainly for human users) or Jev, a model that is
specially trained for making decisions.

The advantages of Jev is not only that it is good at making decisions,
but also much faster, cheaper and possibly more accurate.

#figure(
   image("Images/image_2026091901.png", width: 100%),
   caption: [Software, Decisions and Jev @software-decisions-and-jev],
)

#bibliography("../references/references.bib")
