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

*Change History*
#table(
  columns: 2,
  align: left,
  [Date], [Remarks],
  [2026/04/23], [Chaos Engineering, file name: Chaos-Engineering.typ],
)

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
    "Chaos Engineering"
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
  created: "2026/04/23",
  logical_name: "ChaosEngineering",
  file_id: "2026042301",
  file_type: "Typst",
  keywords: ["Chaos Engineering"],
)

= Chaos Engineering

== Reviews

=== 2026/04/23 - Chaos Engineering Limits
#let a_001 = link(
  "https://dzone.com/articles/chaos-engineering-limits"
)[#text(fill: blue)[Article]]

#a_001 \
Source: dzone

*1. Intent Layer*

Traditional chaos engineering (by injecting killing a service, dropping a node, etc.) is no longer enough
in AI age. Chaos Engineering needs a new layer: *intent*, or *Intent-Based Chaos Engineering*. Instead of "What breaks if I inject failure?", intent-based chaos engineering will ask "Can this 
system still preserve the outcome it was designed to deliver?"

*Comments*\
It is a good idea to introduce 'intent' in chaos engineering. When defining a Testbot Model,
we should include not only 'chaos variables' but also 'chaos intents'.

Intents are actually not new at all:
- Requirements 
- Metrics
- Compliance
- Quality
- Scalability
- Reliability
- Responsiveness
- Security
- System Behaviors
- ...

*2. From State to Intent*

We need to observe not only what happened (states) but also whether the system behavior is
aligned with intents. If intents are not preserved, it should trigger remediation.

*3. From Random Abnormals to Predictive Stress Injection*

It is no longer sufficient or effective to just inject errors or abnormals, such as dropping
a node, killing a service, etc. Most systems are designed to deal with these abnormal cases.
Intent-based chaos engineering will inject abnonrmals and observe whether the system still
functions as expected (expressed in form of intents). When it is not, either solve the
problem or document the issues.

