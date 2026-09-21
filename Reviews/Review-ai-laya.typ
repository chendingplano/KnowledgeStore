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
    "Review - Laya"
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
  logical_name: "ai-laya",
  file_id: "2026092201",
  source: "https://medium.com/data-science-in-your-pocket/laya-bye-bye-typescript-jev-ai-bdefd25149e0#id_token=eyJhbGciOiJSUzI1NiIsImtpZCI6ImYxMGY4NzQwNWE5NzljMWRmMzZkZjI2NjA2NzM0ZjMzY2Q4NWMyNzEiLCJ0eXAiOiJKV1QifQ.eyJpc3MiOiJodHRwczovL2FjY291bnRzLmdvb2dsZS5jb20iLCJhenAiOiIyMTYyOTYwMzU4MzQtazFrNnFlMDYwczJ0cDJhMmphbTRsamRjbXMwMHN0dGcuYXBwcy5nb29nbGV1c2VyY29udGVudC5jb20iLCJhdWQiOiIyMTYyOTYwMzU4MzQtazFrNnFlMDYwczJ0cDJhMmphbTRsamRjbXMwMHN0dGcuYXBwcy5nb29nbGV1c2VyY29udGVudC5jb20iLCJzdWIiOiIxMDA4NTkwMTY4MDkyNTE3NDIyNzciLCJlbWFpbCI6ImNoZW5kaW5nMTExMUBnbWFpbC5jb20iLCJlbWFpbF92ZXJpZmllZCI6dHJ1ZSwibm9uY2UiOiJub3RfcHJvdmlkZWQiLCJuYmYiOjE3OTAwNjg0NjAsIm5hbWUiOiJDaGVuIERpbmciLCJwaWN0dXJlIjoiaHR0cHM6Ly9saDMuZ29vZ2xldXNlcmNvbnRlbnQuY29tL2EvQUNnOG9jS3JWR2MwZFZCRmhGdGRFR1o1cHNZM2gxSlQtVGRUV083RWdVejNjNjJESE5zelh3PXM5Ni1jIiwiZ2l2ZW5fbmFtZSI6IkNoZW4iLCJmYW1pbHlfbmFtZSI6IkRpbmciLCJpYXQiOjE3OTAwNjg3NjAsImV4cCI6MTc5MDA3MjM2MCwianRpIjoiYzcyYjkwMzFlZjZkOTA1NDRkNDIxYzEyZWYyY2E5YjZmNzRjOWQzYiJ9.y9O8788jrNU9R9smsN-p0RrUsBieed7LVlgqxbQSV7oHDesMMWxKuVv7gHLIJCuAF1O5TcZ0S-9ZVpcyq_5yqXdb1px0d29v44yOgorlZuuDQVZsN9p5XVEYGDnicZgiYzJ-5G0vKp4MSvThxEs9m9rviVR2Jl8Hyry8qp7IqaMaGt9EnNJ4hkfbGX9iQ-a9IZAMlcUHhxYJp7v3MSBeV_pQ2BikbaVJsehQ724TMtxVnPYSf9QCk8Py59CQG0RqufpiyjsoTZmueD9j9RUD4ezDJEz_2sW86p9ZHQ_X7AQy43wlwGthmnEandHkk58DwsmC4NL7JAuCFwmq2OrIWQ",
  content_type: "review",
  document_date: "2026/09/22",
  keywords: [laya, jev, system one model, decision, decision engine, 
  decision system],
)

#let ref_review_laya() = [
  "Ref: Review-ai-laya.typ"
]
= Overview

Laya is the open-source equivalence of Jev. Laya is a multilingual, 
non-autoregressive System One decision model designed specifically for
structured decision-making. Instead of generating text, it accepts
a state such as text, an email, a support ticket or JSON and returns
answers with probabilities.

*Characteristics*
- Very fast
- Very small, can run locally

*The model*
- ModernBERT-large backbone with 395M parameters
- A decision head trained from scratch
- 2 transformer layers
- Option-maker scorer
- Act/escalate head
- 421M total parameters

For a choice question, every option gets its own marker and is scored
independently. The resulting scores are then normalized across the options.
That means you can define new decision schemas without retraining the
model for every new set of labels.

*Checkpoints*

- convaiinnovations/laya: for English only
- convaiinnovations/laya-multilingual: for multilingual
- convaiinnovations/laya-typed-decisions: specially tuned for typed-decision 
  workflows.

*Why Laya is so fast*

Unlike conventional LLMs, which generate one token at a time, and worse,
the generated token must be put back into the 'input' and then generate
the next token. Each step (token) involves significant amount of computation.

Laya does not generate tokens. Instead, it generates scores. And also
important, it answers questions independently.

== Cautions

=== Fine Tuning

The base Laya checkpoints perform substantially worse on its published
typed-decisions benchmark. The authors explicitly state that the
capability comes from fine-tuning and that Laya should be viewed as
a fast base to specialize than a universally strong zero-shot 
decision engine.

Downloading the base model and immediately expecting it to perform
expert-level structured decisions is not what the authors are recommending.
The intended workflow is closer to:

```text
Laya base model
       ↓
Your domain data
       ↓
Fine-tuning
       ↓
Specialized decision model
       ↓
Production
```

=== Multilingual Support

Its multilingual support is limited.

=== Choices

Laya's choice questions should ideally remain below approximiately 20 options.
The model uses a fixed head budget for options, and very large label
spaces can reduce the amount of information available for each option.
For larger decision spaces, the authors recommend breaking the decision
into multiple stages.

For instance, 
```text
Step 1
Which category?

Billing
Technical
Sales
Other

    ↓

Step 2
WHich billing issue?

Refund
Duplicate charge
Payment failure
Invoice problem
```

== Laya on Mac M4 CoreML
Link: https://gist.github.com/fordnox/e592d0f68b543fd044be8e6d040863a0

This GitHub installs Laya for Mac M4 chips.
