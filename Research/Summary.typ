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
    "Summary Artifact"
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
  logical_name: "Summary Artifact",
  file_id: "2026052502",
  file_type: "Typst",
  content_type: "Research",
  doc_time: "2026/05/25",
  keywords: ["Summary", "Semantic Projection", "Reasoning Artifact", "Recall Artifact"],
)

= What Is Wrong about Summaries
We often use LLMs to summarize content in the wrong way. They are two fundamentally 
different knowledge artifacts with different optimization objectives.


== Human Summary vs Retrieval Representation

Summaries for humans:

- compress information
- preserve core meaning
- maximize readability
- remove details judged less important

That works for:

- human understanding
- clustering
- document previews
- browsing

But retrieval has a different objective: maximize future discoverability under uncertain query formulations.
That changes everything.

For example:
```text
Vaccine refrigerators shall maintain temperatures between 2°C and 8°C. Continuous monitoring 
devices shall trigger alarms when excursions exceed configured thresholds. Calibration shall be performed every 12 months.
```

Human summary:

```text
The section describes operational requirements for vaccine refrigeration, including 
temperature control, monitoring, and maintenance.
```

For human, this is a good summary. For retrieval, it is terrible. It loses:

- 2°C–8°C
- continuous monitoring
- alarms
- excursion thresholds
- calibration
- 12 months

A future query for the following may fail:

```text
annual calibration requirement for vaccine fridge alarms
```

Something that may be omitted for human but can be extremely important because 
it signals normative obligation. For instance: reference IDs are often omitted
for humans but very important for retrieval:

```text
GB 15982
ISO 13485
21 CFR Part 11
```

For SemOS, we need to consider the following:
- Retrieval Projection: A transformed representation optimized for retrieval.
- Semantic Projection: A normalized representation preserving retrievable semantics.
- Retrieval Surrogate: A proxy object used instead of raw content.

== Core Principle

For retrieval, we need to consider: What must never be lost?

== Dimensions of Information Preservation

A retrieval-oriented artifact should preserve specific signal classes.

*1. Topical signal*

What is this about?

```text
vaccine storage
cold chain
temperature monitoring
```

*2. Entity signal*

Named objects.

```text
Pfizer
WHO
GB 15982
CDC
```

*3. Normative Signal*

Critical for standards/regulations.

```text
shall
must
required
recommended
prohibited
```

*4. Quantitative Signal*

Never compress away.

```text
2°C–8°C
12 months
3 hours
95%
```

*5. Temporal Signal*

```text
before administration
within 24 hours
annually
```

*6. Conditional Signal*

```text
if exposure occurs
unless approved
when deviation detected
```

*7. Causal signal*

```text
because
therefore
results in
due to
```

*8. Relationship signal*

```text
device monitors refrigerator
alarm triggered by excursion
```

*9. Conceptual signal*

Domain terminology.

```text
cold_chain
temperature_excursion
calibration
```

== Semantic Projection

It represents content in a form optimized for matching relevant queries.

Example: `Vaccine refrigerators shall maintain 2°C–8°C and be calibrated annually.`

Projection:

```text
vaccine refrigeration mandatory temperature range 2c 8c annual calibration cold chain compliance
```

Optimized for finding relevant things:
- embeddings
- BM25
- clustering
- semantic similarity
- ranking

It contains:

- normalized semantics
- important facts
- query synonyms
- alias expansion
- critical numeric values
- normative markers

== Structured Knowledge Representation

It represents meaning in machine-interpretable form. Its purpose is for reasoning about things.

Example:

```json
{
  "subject": "vaccine_refrigerator",
  "obligation": "maintain_temperature",
  "range": "2C-8C",
  "calibration_interval": "12_months"
}
```

It includes:
```json
{
  "entities": [],
  "relations": [],
  "concepts": [],
  "obligations": [],
  "assumptions": [],
  "causal links": [],
  "conditions": [],
  "temporal constraints": [],
  "metrics": [],
  "provisions": []
}
```

Optimized for:

- logic
- graph traversal
- causal inference
- compliance checks
- explainability

It is normally used to answer questions: "What does this content mean?"

Reasoning-oriented.

== Query Expansion Surface (Recall Surface)

It maximizes findability under diverse query formulations

Example:

Same content may be asked as:

- vaccine fridge
- refrigerator monitoring
- cold chain equipment
- storage alarm requirement
- annual sensor calibration
- temp excursion alerts

Recall surface stores:

```json
{
  "aliases": [
    "vaccine fridge",
    "medical refrigerator",
    "cold chain refrigerator"
  ]
}
```

Optimized for:

- lexical mismatch recovery
- synonym coverage
- query expansion
- ambiguous user phrasing

Question answered: "How might someone ask for this?"

```json
{
  "aliases": [
    "temperature alarm",
    "cold chain alert",
    "excursion notification"
  ]
}
```

This is extremely retrieval-helpful.

```text
| Artifact            | Core problem    |
| ------------------- | --------------- |
| Semantic Projection | relevance       |
| Reasoning           | meaning         |
| Recall Surface      | discoverability |
```

== Things to Avoid

*1. Compression Destroys Retrieval Fidelity*

Example:

High compression:

```text
This section covers equipment maintenance requirements.
```

It is a great summary. But bad embedding target.


*2. Topic Separability*

Topic separation can be good for clustering. But retrieval often benefits from overlap
because real content belongs to multiple semantic neighborhoods.

Example:

A paragraph about:

```text
vaccine refrigeration calibration alarms
```

belongs to:

- calibration
- monitoring
- cold chain
- medical devices
- compliance

Forcing separability may reduce discoverability.

== SemOS Architectural Insight

Traditional RAG:

```text
document
→ chunk
→ embed
```

SemOS:

```text
document
→ human summary (optional)
→ semantic projection
→ structured facts
→ concepts
→ graph relations
→ query surfaces
→ reasoning artifacts
```

== Retrieval vs Recall

Retrieval and recall are not far from each other, but they are not the same.

Think IR terminology:

- precision = retrieved docs are relevant
- recall = relevant docs are retrieved

Semantic Projection mainly improves precision. Recall Surface mainly improves recall.

Example:

Document contains:

```text
temperature excursion monitoring
```

User searches:

```text
cold chain alarm
```

Semantic embeddings may catch it.

BM25 may miss.

Recall surface bridges:

```text
temperature excursion ↔ cold chain alarm
```

Another example:

Document:

```text
adverse event following immunization
```

User query:

```text
vaccine side effects
```

Without recall expansion:

possible miss.

With recall surface:

match succeeds.

== Consequence of Keeping ONLY Semantic Projection

This is the most important part.

*Benefit 1*: Simplicity

Pipeline:

```text
document
→ semantic projection
→ embed + BM25
```

Simple, fast, cheap, easy to scale. For SemOS v1, this is attractive.

*Benefit 2*: Broad usefulness

Semantic Projection supports:

- retrieval
- clustering
- dedup
- topic discovery
- rough similarity

Good general-purpose artifact.

*Benefit 3*: Less extraction fragility

Structured reasoning extraction is brittle.

LLMs can make mistakes. Semantic projection tolerates fuzziness better.

So if we keep only one, this is the safest one.

*What You Lose Without Reasoning?*

Massive.

*1. No explicit semantics*

Projection:

```text
annual calibration required
```

But what is calibrated?

- Sensor?
- Fridge?
- Alarm?

Ambiguous.

*2. No logical operations*

You cannot reliably ask: "find all requirements with annual obligations"
because "annual" may appear in many contexts.

*3. No graph reasoning*

We cannot do:

```text
vaccine refrigerator
→ has sensor
→ sensor requires calibration
```

Because relationships aren't explicit.

*4. No contradiction reasoning*

Example:

Doc A:

```text
calibration every 12 months
```

Doc B:

```text
calibration every 6 months
```

Projection sees two texts.

Reasoning layer sees conflict.

*5. No compliance reasoning*

You want:

```text
given procedure X, are we compliant?
```

Requires structured obligations. Projection alone is weak here.

*What You Lose Without Recall Surface*

Less catastrophic, but real.

*1. Lexical misses*

Example:

Stored:

```text
myocardial infarction
```

Query:

```text
heart attack
```

Possible miss.

*2. Domain jargon mismatch*

Stored:

```text
adverse event following immunization
```

Query:

```text
vaccine reaction
```

Possible miss.

*3. User mental model mismatch*

User may think:

```text
storage alert
```

Docs say:

```text
temperature excursion notification
```

Mismatch. 

Semantic embeddings reduce this problem. But not perfectly.
Especially local/private models.

== Retrieval-Only SemOS

Architecture:

```text
SemOS
 ├── docs
 ├── semantic projections
 ├── embeddings
 ├── BM25
 └── ranking
```

This is essentially an advanced retrieval substrate. Very useful. But not epistemic.
Not reasoning-centric.

Closer to:

- better RAG
- better search
- better memory

than a knowledge operating system.

== Retrieval + Reasoning (No Separate Recall)

This is probably the best practical architecture because recall can often be folded into retrieval.
Semantic Projection can be enhanced:

Instead of:

```text
temperature excursion monitoring
```

Store richer projection:

```text
temperature excursion monitoring cold chain alarm refrigerator storage alert vaccine fridge temperature breach
```

Now recall hints are embedded directly.

Meaning:

*Recall Surface becomes part of Semantic Projection.*

This is elegant.

*Architecture*:

```text
document
→ semantic projection (with aliases/synonyms/query forms)
→ structured reasoning extraction
```

Two artifacts only.

This is likely the sweet spot.

*But Beware Projection Pollution*

If you merge recall into projection, projection can become noisy.

Bad example:

```text
cold chain fridge refrigerator cooler vaccine storage alarm monitoring temp warning sensor alert notifier excursion excursion event issue problem failure...
```

This becomes keyword soup.

Embeddings degrade.

BM25 gets weird.

Need discipline.

== SemOS: Two Artifacts

SemOS will keep two artifacts:

- Semantic Projection
- Structured Knowledge Representation
