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
    "Diary - 2026/06"
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
  created: "2026/06/01",
  logical_name: "Diary-202606",
  file_id: "2026060101",
  file_type: "Typst",
  keywords: ["Diary"],
)

= 2026/06/01 - Prompts

The best prompt is not tell LLMs what to do, but the ones that 
ask you details until LLMs fully understand what you need.

请像采访一样问我所有细节。
 每次只问一个问题。
 问到你完全理解我要什么为止。

= 2026/06/01 - Microsoft Open-Sourced SkillOpt

#let a_001 = link(
  "https://github.com/microsoft/SkillOpt"
)[#text(fill: blue)[URL]]

#a_001 \
Source: WeChat

This is a Python project that trains your skills.

= 2026/06/01 - Photo Album Project

#let a_002 = link(
  "https://github.com/immich-app/immich"
)[#text(fill: blue)[URL]]

#a_002 \
Source: WeChat

= 2026/06/01 - Prompt Cache Hit

== What is being cached?

Suppose we send this prompt:

```text
You are a compliance expert.

The following document is ISO 9001.

[10000 tokens of ISO content]

Question:
What are the requirements for document control?
```

The model does not immediately generate an answer.

First, it processes all 10,000 tokens through the Transformer.

During this process it computes:

```text
Token -> Embedding
       -> Attention
       -> K/V tensors
```

The expensive part is generating those K (Key) and V (Value) tensors.

The collection of these tensors is called the KV Cache. ([Hugging Face][1])


== How to Improve Cache Hit

Arrange your request:

```text
System Prompt
Documents
Examples
User Question
```

- System prompts do not have parameters
- System prompt, documents and examples always stay together
- The only changed content is user question

In general:
- Put stable content first.
- Put changing content last.


Note that prompt caching (or input caching) is NOT response caching

== References
[1]: https://huggingface.co/blog/not-lain/kv-caching?utm_source=chatgpt.com "KV Caching Explained: Optimizing Transformer Inference ..." \
[2]: https://bentoml.com/llm/inference-optimization/prefix-caching?utm_source=chatgpt.com "Prefix caching | LLM Inference Handbook" \
[3]: https://arxiv.org/html/2601.06007v2?utm_source=chatgpt.com "An Evaluation of Prompt Caching for Long-Horizon Agentic ..." \
[4]: https://llm-d.ai/blog/kvcache-wins-you-can-see?utm_source=chatgpt.com "KV-Cache Wins You Can See: From Prefix ..." \
[5]: https://medium.com/%40michael.hannecke/prompt-caching-explained-what-it-is-what-it-isnt-and-when-to-use-it-9f5c6fce7bdb?utm_source=chatgpt.com "Prompt Caching: What It Is, What It Is Not"

= 2026/06/03 - Kapa
#let a_003 = link(
  "https://www.kapa.ai/request-demo"
)[#text(fill:blue)[URL]]

#a_003 \
Source: Techcrunch

This is a competitor of SemOS. It offers doc services.

