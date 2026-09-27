#import "@preview/diagraph:0.3.6"
#import "@preview/oxdraw:0.1.0": *
#import "../../Reviews/Review-ai-laya.typ": ref_review_laya
#import "../../Reviews/review-knowhere.typ": ref_review_knowhere

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
| GPT-6 Luna Short Context  | $0.10  | $0.01     | $0.125       | $0.50  |
| GPT-6 Luna Long Context   | $0.20  | $0.02     | $0.25        | $0.75  |
| GPT‑5.6 Sol               | $5.00  | $0.50     | $6.25        | $30.00 |
| GPT‑5.6 Terra             | $2.00  | $0.20     | $2.50        | $12.00 |
| GPT‑5.6 Luna              | $0.20  | $0.02     | $0.25        | $1.20  |
| GPT‑5.5                   | $5.00  | $0.50     | —            | $30.00 |
| GPT‑5.4                   | $2.50  | $0.25     | —            | $15.00 |
```

Below is DeepSeek 4.1 Flash
```text
Time      cache hit	  cache miss	  Output
Off-Peak	$0.003	    $0.15	        $0.6
Peak	    $0.006	    $0.3	        $1.20
```

#figure(
  image("Images/image_2026092302.png", width: 100%),
  caption: [#ref_gpt_6_sol]
)

Note that GPT-6 Sol does not seem very powerful. Its score is 48, the same as Muse.
Anthropic score is 58, much higher.

GPT-6 Luna is about the same as DeepSeek 4.1 Flash (37 vs 39).

== Anthropic releases its Opus 5.5<openai-pricing>

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

== Work for Today
- Added 'Calendar' frontend page and the backend tables
- Added 'Peak Hours' frontend page and the backend tables
- Solve the uploading zip files not being able to handle Chinese characters that are
  not UTF8.
- Deleting an entry in '/home3/knowledge, File Management => Upload Files',
  should ask users whether to delete the file.
- Add a checkbox on '/home3/knowledge, File Management => Upload Files
- Uploading files not setting 'tenant_id'
- Add a 'tenant_id' field in the 'Modify' dialog of '/home3/knowledge, Knowledge Base'
- Add 'User' field in the record list of '/home3/knowledge, File Management => Upload Files' 
- Adjust the field widths in the input record list
- Add 'Edit' button in the input record list
- When uploading files, populate 'ks_store_id' and 'ks_desc' to all the records
  of 'kb.inputs', including the records created by a zip file
- Removed 'Convert' and 'Time', added 'Processing Mode' in the 'kb.inputs' list

= 2026/09/25

== Work for Today
- Use BGE-M3 embedding model
- Use Jev

= 2026/09/26

== A Jev-like wrapper for LLMs, including vision models

#let jev_like_wrapper = link(
  "https://allanrbo.blogspot.com/2026/09/a-jev-like-wrapper-for-llms-including.html"
)[#text(fill: blue)[Jev-like Wrapper for LLMs]]

OpenAI `logprobs` can retrieve the probabilities of next words.

```text
State: My order arrived broken and I want a refund.
Question: Which team should handle this?
[A] billing
[B] shipping
[C] returns
Answer with the letter of the best option only.
```

Then add a few JSON request parameters to a compatible Chat Completions request:

```text
{
  "max_completion_tokens": 1,
  "logprobs": true,
  "top_logprobs": 20
}
```

Note that it uses 'logprobs' to retrieve the probabilities.

This article also includes the code for handling videos.
His example captures webcam frames, sends base64 JPEGs, and prints a table:
- is a person visible
- are we indoors or outdoors
- how bright is the scene

He uses RTX 3090, running Gemma 4 12B, got 1 frames per second.
Using OpenAI GPT-6 Luna, got 0.2 FPS. 

== GPT-6 Luna

GPT-6 Luna is very cheap (refer to @openai-pricing). We can use either DeepSeek 4.1 Flash
or GPT-6 Luna for repeative work in the future.

== SIMA in Go
#let sima_in_go = link(
  "https://go.dev/blog/simd-experiment"
)[#text(fill: blue)[SIMA in Go]]

#sima_in_go

Go 1.26 and 1.27 include experimental APIs for SIMA, which can accelerate
operations such as adding 8 pairs of floating 64 values in a single instruction.

One thought about SIMA is calculating vector similarity.

*Action*
Keep it in mind in case we need it.

== Typst Release 0.15.0 (June 15, 2026)
#let typst_new_release = link(
  "https://typst.app/docs/changelog/0.15.0/"
)[#text(fill: blue)[Typst Release 0.15.0 (June 15, 2016)]]

#let typst_big_stride = link(
  "https://lwn.net/Articles/1092993/"
)[#text(fill: blue)[Typst makes big strides]]

#typst_new_release\
#typst_big_stride

Read the release notes for the features and bug fixes.

=== Variable Fonts

Most fonts are distributed in a set of files containing their glyphs in different
weights, in variations such as italic, bold, and so on. A recent development
in the world of typography is the advent of variable fonts, which can contain
all their variations in a single file. This both saves space and can permit greater 
flexibility on the part of the author or designer.

```text
#set text(font:"Roboto Flex")
#for n in (-305, -200, -98) {
   set text(variations:("YTDE": n)) 
   [A penguin jumped quietly.

   ]
}
   
#set text(font:"Zycon")
#for n in array.range(0, 10, inclusive:true) {
   set text(variations:("M1  ": n/10))
   str.from-unicode(127773)
}
```

=== Multiple bibliographies

Typst now permits multiple bibliographies in a single document, which was an eagerly
awaited feature. Its canonical application is for books that may need a separate
reference section for each chapter. 

```text
   #show bibliography: set text(size: 8pt)
   
   = Chapter I
   
   According to @smith, Smith is uncommonly smart.
   
   #bibliography("works.bib",
   title: "References for Chapter I",
   group: none)
   
   = Chapter II
   
   Jones@jones has a different view. The issue was
   finally put to rest in the following year
   in @mergutroid.
   
   #bibliography("works.bib",
   title: "References for Chapter II",
   group: none) 
```

Here the first line specifies that the bibliographies should use a font size smaller than 
the default used in the main text. In that text, the "@" prefixes create a citation using 
the default number-in-brackets style. At the end of each chapter, the bibliography() function 
is called. Its first argument specifies which database should be used for the bibliographic 
information; each bibliography section can use a different database, or collection of databases, 
if desired (see our recent article on Pandoc for a description of these text-file databases). 
The group argument controls how the citations are numbered. The value of none causes the 
numbering to begin with one for each section; numbering can alternatively be continuous for 
the entire work, or be grouped arbitrarily.

== Knowhere <ref-knowhere>
#let knowhere = link(
  "https://github.com/Ontos-AI/knowhere"
)[#text(fill: blue)[Knowhere 2.0]]

#knowhere 

Refer to #ref_review_knowhere()

= 2026/09/27

== Scrapling
#let scrapling = link(
  "https://github.com/d4vinci/Scrapling"
)[text(fill: blue)[Scrapling]]

#scrapling

This is an open source project that can scrapt the web, adaptively,
meaning it can detect web page changes and adept to the new format.

*Action*

- Not installed yet. Will install it.
- Add a frontend page to manage it.

== Open Books HK
#let scrapling = link(
  "https://openbookshongkong.com/en/"
)[text(fill: blue)[香港大学开发图书库]]

== Agentic Search

Yesterday read @ref-knowhere. Knowhere is an agentic search engine. 
Knowhere assumes its caller will determine the namespace to search.
This means:
- Knowhere organizes corpus by namespaces (similar to Knowledge Base in SemOS)
- Callers are responsible for picking namespaces. If not, it will use 'default'.
  Not sure what the 'default' does.
- In SemOS, callers must tell which kb(s) to search. If users do not say,
  SemOS will search all the kbs that the user has accesses.


== Today Work
- Bug (fixed): double click an image in uploading video closes the dialog
- Improvement (done): make the '/development, System Admin => Resources => Videos' list sortable
  by 'Name', 'Size' and 'Uploaded'


= References
[1]: Jev's Architecture Unmasked, https://archerhume.com/posts/jevs-architecture-unmasked

