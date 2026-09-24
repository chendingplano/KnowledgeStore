#import "@preview/diagraph:0.3.6"
#import "@preview/oxdraw:0.1.0": *
#import "../../Reviews/Review-ai-laya.typ": ref_review_laya

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
    "Diary - 2026/09"
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
  logical_name: "diary-202609",
  file_id: "diary-202609",
  source: "",
  content_type: "diary",
  document_date: "2026/09/22",
  keywords: [diary],
)

= 2026/09/22 - Laya

Read a Medium artical.

Laya is the open-source solution for Jev. But there are some limitations
in using it:
- Need fine-tuning
- Multilingual support is limited
- Need to be careful with the number of choices. When there are too many
  choices, it is highly recommended to break them into categories to turn
  it into multi-stage decision making.

For more information, refer to #ref_review_laya()

= 2026/09/22 - Qwen-Image-2.1

Link: https://qwen.ai/blog?id=qwen-image-2.1

Alibaba released Qwen-Image-2.1, compact, efficient, and unified image generation.
It is open-weights, with 7B parameters. We may install and run it locally.

= 2026/09/22 - Kev

Link: https://github.com/jaredpalmer/kev/tree/main


Kev is a family of small decision models built on Qwen3.5 and based on the 
architecture described in (Ref [1]).

*Highlights*
- 0.8B, 4B and 9B models, with training code and evaluation data
- Yes/no (noul), multiple-choice (choice) and rating (score) questions in the
  same request.
- Questions share the input text but can't read each other
- Runs on CUDA and Apple Silicon. The 4B and 9B models fit a 32 GB Mac using
  bf16
- A web playground for trying your own inputs and checking how option order 
  affects the answer.

My take on Kev:
- It can be a replacement of Jev
- It should handle multilingual well because Qwen3.5 is a multilingual model
- We may need to wait for a while to let the dust settle.

Conceptually, you give a state and a set of choices. It processes the state
once and then answers each question independently in the one-shot fashion.

= 2026/09/22 - Plan
- Make sure LLM logs with user_id, run_id
- Need to separate 'products' with 'instances'
- Add billing on individual users
- Deploy it to Runshen
- Record trainings on running Document Review and Product Review

== Turning off reasoning
Added two env var:
- EXTRACT_PRODUCTS_MERGED_PASS="true|false": If "true", it will merge Pass 1 and Pass 2.
  It does affect the effectiveness of the extraction about 10%.
- EXTRACT_PRODUCTS_REASONING="true" | "false": If "false", the reasoning is turned off.
  It does affect the effectiveness of the extraction.

Plan to offer three levels for 'extract_products':
- Fast (no reasoning, merged)
- Standard (merged, with reasoning)
- Max (not merged, with reasoning)

== Output Too Big for 'extract_products'
The main problem is that DeepSeek generates not just the mentions, but also 'reasoning_content',
which is too big.

- See whether we can turn it off
- If turn it off, whether it affects the extraction performance and accuracy

= 2026/09/23 
== OpenAI releases its GPT 6 Sol and GPT 6 Luna

#let ref_gpt_6_sol = link(
  "https://artificialanalysis.ai/models/gpt-6-sol"
)[#text(fill: blue)[ChatGPT 6 Sol]]

#ref_gpt_6_sol

Not sure the performance, should be pretty good. The best one is the price.
```text
| Model                     | Input  | Cache Hit | Cache Writes | Output |
| GPT-6 Astra Short Context | $10.00 | $1.00     | $12.50       | $50.00 |
| GPT-6 Astra Long Context  | $20.00 | $2.00     | $25.00       | $75.00 |
| GPT-6 Sol Short Context   | $2.00  | $0.20     | $2.50        | $10.00 |
| GPT-6 Sol Long Context    | $4.00  | $0.40     | $5.00        | $15.00 |
| GPT-6 Sol Short Context   | $0.10  | $0.01     | $0.125       | $0.50  |
| GPT-6 Sol Long Context    | $0.20  | $0.02     | $0.25        | $0.75  |
| GPT‑5.6 Sol               | $5.00  | $0.50     | $6.25        | $30.00 |
| GPT‑5.6 Terra             | $2.00  | $0.20     | $2.50        | $12.00 |
| GPT‑5.6 Luna              | $0.20  | $0.02     | $0.25        | $1.20  |
| GPT‑5.5                   | $5.00  | $0.50     | —            | $30.00 |
| GPT‑5.4                   | $2.50  | $0.25     | —            | $15.00 |
```

#figure(
  image("Images/image_2026092302.png", width: 100%),
  caption: [#ref_gpt_6_sol]
)

Note that GPT-6-sol does not seem very powerful. Its score is 48, the same as Muse.
Anthropic score is 58, much higher.

== Anthropic releases its Opus 5.5

Significant improvements on performance. The price is even lower.

*Prices*
```text
Model             Cache Miss  Cache Hit   5m Cache  1h Cache    Output
                                          Writes    Writes 
----------------------------------------------------------------------
Fable 5.1         $10         $0.25       $12.50    $20         $50 
Mythos 5.1        $10         $0.25       $12.50    $20         $50
Fable             $10         $1          $12.50    $20         $50
Mythos 5          $10         $1          $12.50    $20         $50
Opus 5.5          $4          $0.20       $5.00     $8          $20
Opus 5            $5          $0.50       $6.25.00  $10         $25
Opus 4.8          $5          $0.50       $6.25.00  $10         $25
Opus 4.7          $5          $0.50       $6.25.00  $10         $25
Opus 4.6          $5          $0.50       $6.25.00  $10         $25
Opus 4.5          $5          $0.50       $6.25.00  $10         $25
Sonnet 5          $2          $0.20       $2.50     $4          $10
Sonnet 4.6        $3          $0.30       $3.75     $6          $15
Sonnet 4.5        $3          $0.30       $3.75     $6          $15
----------------------------------------------------------------------
```
== Will OpenAI Eat Jev's Lunch?
#let a_001 = link(
  "https://arcturus-labs.com/blog/2026/09/21/will-openai-eat-jevs-lunch/"
)[#text(fill: blue)[JevBench]]

#a_001

This article talks about how Jev works and OpenAI's position. I think not only
OpenAI but all major LLM vendors will follow Jev, developing their own Jev.

*Does Jev have a moat?*

It may or may not. If it does, the moat is not very hard to break. As its
founder (Diogo Almeida) says, TypeSafe is a data research lab. Its moat,
if any, is the data. All data are synthetic data. 

Note that Jev is not a conventional LLM, which uses RLHF. Instead, it is a
model that uses RLCD (Reinforce Learning with Calibrate Decision). In other
word, it is specially training with making decisions. 

== JevBench
#let ref_jev_bench = link(
  "https://benchmarkheaven.com/jev-models"
)[#text(fill: blue)[JevBench]]

#ref_jev_bench

#figure(
   image("Images/image_2026092301.png", width: 100%),
   caption: [#ref_jev_bench],
)

There are many Jev-equivalents in the benchmark. 

*Thoughts*

We will wait a while to let the dust settle.

= 2026/09/24
== Jev vs LLMs 
#let jev_vs_llms = link(
  "https://github.com/dchristopoulos/jev-aita"
)[#text(fill:blue)[Jev vs LLMs]]

#jev_vs_llms

Jev came second, behind Sonnet 5. Jev's median call was 6.3x faster than 
Sonnet, and 62x cheaper. 

*Thoughts*

It is true that we can use LLMs to simulate Jev by formulating the prompt
so that the LLMs can only generate one token (or very few). But the 
real questions are:
  - The speed
  - The cost
From this post, we can see Jev is not as powerful as the frontier models
but pretty good. Its selling points are speed and cost.

== Jev's Architecture Unmasked

#let jev_architecture_unmasked = link(
  "https://archerhume.com/posts/jevs-architecture-unmasked#what-would-change-my-mind"
)[#text(fill: blue)[Jev Architecture Unmasked]]

#jev_architecture_unmasked

#quote(block: true, attribution: [#jev_architecture_unmasked])[
  "Jev's proposition is to retain the knowledge of a pretrained LLM while replacing
  generated confidence claims with decision probabilities read directly from its
  internal representations. Those probabilities are trained against outcomes.
  Give it shared state, questions and allowed answer; it returns the distributions
  in parallel, without generating text."
]

In order to understand Jev (or System One Model), we need to understand how
an LLM works. In the simplest form, for each 'state', it has a collection of
'next word' with probabilities. The next word is a work in normal LLM. For
Jev, it should be a decision.

If you give a state, question + allowed answer pairs, for each pair, it
uses 'state' + 'question' to reach a kind of internal node. Each internal
node is associated with a number of 'decisions' with probabilities. 
It then check whether the given answers match its internal decisions.
Pick the matched decisions, normalize the probabilities. These are the 
scores.

= References
[1]: Jev's Architecture Unmasked, https://archerhume.com/posts/jevs-architecture-unmasked

