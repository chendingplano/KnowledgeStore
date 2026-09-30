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
== OpenAI releases its GPT 6 Sol and GPT 6 Luna <ref_gpt_release>

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
| GPT-6.1 Sol Short Context | $2.00  | $0.10     | $2.50        | $10.00 |
| GPT-6 Sol Long Context    | $4.00  | $0.40     | $5.00        | $15.00 |
| GPT-6.6 Sol Long Context  | $4.00  | $0.20     | $5.00        | $15.00 |
| GPT-6 Luna Short Context  | $0.10  | $0.01     | $0.125       | $0.50  |
| GPT-6.1 Luna Short Context| $0.10  | $0.01     | $0.125       | $0.50  |
| GPT-6 Luna Long Context   | $0.20  | $0.02     | $0.25        | $0.75  |
| GPT-6.1 Luna Long Context | $0.20  | $0.02     | $0.25        | $0.75  |
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
Sonnet 5.5        $2          $0.20       $2.50     $???        $10
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

#jev_like_wrapper 

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
- If no kb is provided, it defaults to use all the kbs that the user can access.

== Today Work
- Bug (fixed by Codex): double click an image in uploading video closes the dialog
- Bug (fixed by Codex): user name and email shown in the left-lower corner are hard-coded
- Bug (fixed by Codex): 'User Info' not working. Users can edit their info.
- Bug (fixed by Codex): uploading a file requires the active knowledge store's 'tenant_id' must have a valid value.
  Tenants are not supported yet. Ignore this field for now.
- Improvement (done by Codex): make the '/development, System Admin => Resources => Videos' list sortable
  by 'Name', 'Size' and 'Uploaded'
- Improvement (done by Codex): Disable 'Account' menu item
- Improvement (done by Codex): add 'kb.inputs.user_id'. Remove 'kb.inputs.tenant_id'.


= 2026/09/28

== Agentic Search (Harness)

(continue from yesterday 'Agentic Search')

I have integrated Pi into 'ChenWeb' (refer to '2026091401-rqmt' and '2026091501-handoff').
The idea is an AI system (such as 'ChenWeb') should have its own agentic loop or harness.
In `ChenWeb`, we have many modules and apps that need to use LLMs, such as:
- Doc Processors
- Document review app
- Product metric review app
- Hybrid search

A simple way of integrating LLMs in a system is through prompts and LLM calls,
or one-short or fix-short LLM integration. This may be sufficient for simple
use cases. 

When we say 'Agentic', we mean:
- It is undeterminisitic and thus needs LLMs to help
- The number of shorts is undeterministic, thus an agentic loop is
  needed. LLMs are now in the driver seat, determining what to do
  next and when to stop.
- An agentic loop
- A system prompt

A typical scenario of agentic app is hybrid search: user provides a query,
which can be a question or a task. LLMs determines what to do with it:
- Generate answer
- Use a tool

If it decides to use a tool:
- Pick a tool
- Compose the request for the tool
- Invoke the tool
- Analyze the tool results
  - Ask users questions
  - Need to use another tool

== Working with multiple knowledge bases (kbs)
[keyword: multiple knowledge base, shared knowledge base, shared kb,
shared document]

== Duplicate documents
The same document may be in multiple kbs. The first question is:
can we procuess a shared document in one kb and all other kbs that
share the document can use the artifacts?

*Shared Document*

A *shared document* is a document that is included in multiple kbs.
A shared document has one and only one *home knowledge store* and
one or more *shared knowledge store*. 

The question is: how a shared kb reuses the shared artifacts.
One solution is to build a shared knowledge base:
- Add a '`knowledge_stores`' field to documents. This field lists all the
  kbs the document belongs to. 
- When a document is not shared and becomes shared now, which is determineded by
  the values of the document's '`knowledge_stores`' field, the document is
  removed from its home kb and added to the shared kb. Similarly, when a shared
  document is no longer shared, it is removed from the shared kb and added back
  to its home kb.
- When search, it always search the specified kbs and the shared kb.
- When search the shared kb, the caller should specify the kbs.
  Results are filtered by the kbs.

== Today Work
- Bug (fixed by Codex): upload 'docx' files, missing 'proc_status'
- Improvement (done by Claude): Holidays can support adjusted days
- Improvement (done by Codex Sol): PDF parsing monitoring, change to multiple phases.
  Note that mineru running on Linux and Mac behaves differently!
- Improvement (done by Codex): Add 'Status' in the upload file list
- Improvement (done by Codex): Added 'Process Failed' in the upload file window
- Improvement (done by Codex): Added 'Quick Filters' in the upload file window
- New feature (done by Codex): Release page
- New Feature (done by Claude): 'Pricing' page

= 2026/09/29

== Jeff - A Replacement of Jev
#let ref_jeff = link(
  "https://github.com/firelex/jeff"
)[#text(fill: blue)[Jeff - a replacement of Jev]]

#ref_jeff

This is an open source project, training Qwen3.5 and Gemma 4 for zero-shot 
classification: small, fast decision models. Its performce approaches Jev.
Trained on RTX PRO 6000.

== Anthropic release Sonnet 5.5
#let ref_sonnet_5_5_release = link(
  "https://www.anthropic.com/claude-sonnet-5-5"
)[#text(fill: blue)[Anthropic Release Sonnet 5.5]]

- Much faster than Opus 5.5 (30% faster)
- About half price of Sonnet 5: Cache Read: \$0.20, Miss: \$2, Output: \$10
- Pretty good at coding (comparable with Opus 5.5)
- Write more clearly

== Thoughts on Vector Database
FAISS is definitely not what we need because it requires all vectors must be in memory.
When the system becomes big, there is a serious memory issue.

PostgreSQL has disk-based vector index, but I don't think it is good enough.

Today, we explored the possibility of not building a gigantic global vector index or database
at all. For this approach to work, it is important that we can pick candidates with good enough
accuracy.

BM25 is important but it can easily miss candidates even with single-character drift
over the keywords, let alone aliases, multilingual issues, etc.

It appears to me that 'categories' may be the solution. Categories are essentially
'indexes' on semantics. Instead of using vectors for semantic similarities, we should
use categories.

Categories must be hierarchical:

```text
root category 01
root category 02
...
root category 19
root category 20
```

Root category 01-19 are normaly root-level categories. 20 is reserved for 'others'.
(note: the number 20 is configurable)

When there are too many entries (such as 1000), we can ask LLMs to create new
root-level categories, given the existing categories. This will result in
up to N root-level categories.

We can then ask LLMs to create a higher-level categories over these root-level
categories, up to 19. The category hierarchy is expanded by adding one more level.

If each node in the hiearchy holds no more than 20 children:
```text
Level       Max Categories
----------------------------------------------
1           20
2           400
3           8000
4           160,000
5           3,200,000           3 millions
6           64,000,000          64 millions
7           1,280,000,000       1.28 billions
8           25,600,000,000      25 billions
9           512,000,000,000     512 billions
10          10,240,000,000,000  10 trillions
----------------------------------------------
```

Given a user query, we need to find its categories:
1. Which category the query belongs to, given the level-0 categories (up to 20)
2. If the query matches no given categories, stop with 'no-match-found'
3. If the matched category is a leaf category, stop 'leaf-reached'
4. Otherwise, push the matched categoy to the category path, retrieve the 
   matched category children and repeat Step 1.

When the search loop finishes:
- Stopped with 'no-match-found':
  - If the category path is empty, return none
  - If the category path length is 1, 

== China's version of Palantir
#let ref_china_palantir = link(
  "https://www.toutiao.com/article/7690401759138710058/?app=news_article&category_new=__all__&module_name=iOS_tt_others&req_id_new=20260929031740D05023942D785F16B9BA&share_did=MS4wLjACAAAAw3rqzAbRbSo4klPah7FJFhb-dpoy0Y2_hu6Pcvvt2pc&share_token=b9ee8484-bb71-11f1-be5c-a088c22778dc&share_uid=MS4wLjABAAAAw3rqzAbRbSo4klPah7FJFhb-dpoy0Y2_hu6Pcvvt2pc&timestamp=1790623255&tt_from=weixin&upstream_biz=iOS_wechat&use_new_style=1&utm_campaign=client_share&utm_medium=toutiao_ios&utm_source=weixin&wxshare_count=1&source=m_redirect"
)[#text(fill: blue)[China's version of Palantir]]

#ref_china_palantir

=== Ontology Model

Its ontology model has four layers:
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
  image("Images/image_2026092901.png"),
  caption:["Four-Layer Model"],
)

=== Ontology Layer
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

==== Decision Module
This module manages the decisions: when something happens, do something.
Most decisions are defined in form of rules.

It uses a decision LLM model, such as the System One model, to handle
undeterministic decisions.

==== Ontology write-back
After the ontology module made a decision, it should write back about the
decision, either as a log, or possibly modify the ontology itself, such
as:
- Adding new rules (such as 'when fixed a bug, add a test suite to 
  the smoke test module')

The most important benefits of writing back is to make ontology more
and more useful as it is used more.

Ontology Write-Back resides in the Ontology Layer.

==== Enforce Guard Rails
Any time when the ontology makes decisions, make sure check the guard rails
to ensure the entire system strictly follows the defined guard rails.

==== Errors and Bugs
When problems occur, such as software bugs, workflow errors, product
quality issues, customer feedbacks, etc.

- Create rules to avoid the problem in the future
- Modify rules
- Modify workflows
- Modify decision chains
- Modify the reasoning

This is a form of self-learning/self-improvement, extremely important.

=== Model Layer

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

== Today Work
- Bugs (fixed by Claude): some 'tenant_id' bugs
- Improvement (done by Claude): knowledge => Metrics page, change 'Global Search' and add 
  search-by-metric-id
- Improvement (done by Claude): Add 'Order by' pulldown menu for 'Metrics' in Knowledge page
- Improvement (done by Claude): Add metric ID to the metrics cards and the prompt in the PDF display
- Improvement (done by Claude): 'extract_metrics' not processing 'kb.metrics.metric_context' properly
  when the source is tables.
- Improvement (done by Codex): '/development, System Admin => Logs => LLM Usage Logs', the output body
  view, show the JSON in name-value format.
- New (done by Claude): A new page to analyze extracted metrics

= 2026/09/30

== OpenAI releases GPT 6.1 Sol and Tuna
- GPT 6.1 Sol is nearly as good as GPT 6 Astra
- Pricing is very friendly (refer to @ref_gpt_release)

== Today Work
- Bug (fixed by Claude): When export PDF in Review Metrics, it freeze the browser tab
- Bug (fixed by Claude): PDF parser failed extracting ICS, CCS, doc_no
- Bug (fixed by Claude): selected only convert but processed 'extract_metrics' and 'extract_products'
- Bug (by Claude): when an input record's working directory not exist or missing its file,
  create the working directory and copy the file from the backup
- Improvement (done by Claude): use Paraglide for internationalization
- Improvement (done by Claude): convert existing 234 files to support both Chinese and English
- Improvement (done by Codex): Add PDF display in Metric Review page
- Improvement (done by Claude): Reconfigured menus for 'dev' and 'admin'
- Improvement (done by Claude): Add 'Models' to Review Metrics
- Improvement (done by Claude): Add 'GPT 6 Sol' model to '.models'
- Improvement (done by Claude): Changed the PDF export to include the grounding
- Improvement (done by Claude): Highlight the grounding row for tables in Review Report
- Improvement (done by Claude): Add 'EXTRACT_DOCMETA_REASONING' to extract_metadata.

- Improvement (plan): Add an 'Add Missed' button in Metric Review page
- Improvement (plan): Add an 'Analyze' button. When the button is clicked, it lets users select
  multiple models. It then runs 'extract_metrics' for each of the models, saves the results in
  files. After 

= References
[1]: Jev's Architecture Unmasked, https://archerhume.com/posts/jevs-architecture-unmasked

