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

= 2026/06/05 - Anthropic Open-Source Security Package

#let a_004 = link(
  "https://github.com/anthropics/defending-code-reference-harness/tree/main"
)[#text(fill: blue)[URL]]

#a_004 \
Source: Hacker News

This is a reference implementation for scan vulnerabilities automatically
and then use LLM to fix them.

It is written in Python. My thoughts are:
1. We do need such a module to constantly scan the security and fixed vulnerabilities, either
   automatically or with human assistance.
2. This should be a module in SemOS.
3. Generate Security Report, weekly or monthly
4. Collect security information through the Internet, automatically

= 2026/06/06 - Prompt Sanitizer

#let a_005 = link(
  "https://github.com/SaiTeja-Erukude/promptsanitizer"
)[#text(fill: blue)[URL]]

#a_005 \
Source: dzone

This open-source is an LLM fileware. It sanitizes prompts. This can be a module
we are going to have for SemOS.

= 2026/06/08 - 3D Map
#let a_006 = link(
  "https://github.com/knight-L/sc-datav/tree/main"
)[#text(fill: blue)[URL]]

#a_006
Source: WeChat

This is a library that draws maps in 3D.

= 2026/06/08 - Create GUI Interactively
#let a_007 = link(
    "https://www.toutiao.com/video/7648765558611116553/?app=news_article&category_new=tt_video_immerse&module_name=iOS_tt_others&req_id_new=202606080602289D8086EB948AD3179F90&share_did=MS4wLjACAAAAw3rqzAbRbSo4klPah7FJFhb-dpoy0Y2_hu6Pcvvt2pc&share_token=8b30c438-62c4-11f1-b0ce-1070fd7eb9e6&share_uid=MS4wLjABAAAAw3rqzAbRbSo4klPah7FJFhb-dpoy0Y2_hu6Pcvvt2pc&timestamp=1780873171&tt_from=weixin&upstream_biz=iOS_wechat&utm_campaign=client_share&utm_medium=toutiao_ios&utm_source=weixin&wxshare_count=1&source=m_redirect")
[#text(fill:blue)[URL]]

#a_007 \
Source: WeChat

The author did not use skills. He created a wonderful web site by talking to LLMs.

= 2026/06/11 - Go Library for Embedding

#let a_008 = link(
  "https://www.sbert.net/docs/cross_encoder/pretrained_models.html"
)[#text(fill:blue)[URL]]

#a_008 \
Source: dzone

This is a Go library that does embedding.

= 2026/06/14 - Qwen Embedding Models and Prices
#let a_009 = link(
  "https://www.alibabacloud.com/help/en/model-studio/embedding?scm=20140722.S_help%40%40%E6%96%87%E6%A1%A3%40%402842587._.ID_help%40%40%E6%96%87%E6%A1%A3%40%402842587-RL_embeddingmodels-LOC_doc%7EUND%7Eab-OR_ser-PAR1_6a0b3f0a17814319688477421d6331-V_4-PAR3_r-RE_new5-P0_0-P1_0&spm=a2c63.p38356.help-search.i20"
)[#text(fill: blue)[URL]]

#let a_011 = link(
  "https://qwen.ai/blog?id=qwen3-embedding"
)[#text(fill: blue)[Qwen3 Embedding]]

#a_009 \
#a_011

#table(
  columns: 6,
  align: left,
  [Model], [Embedding dimensions], [Batch size], [Max batch tokens (Note)], [Price / 1M tokens], [Language],
  [text-embedding-v4, Part of the Qwen3-Embedding series], [2,048, 1,536, 1,024 (default), 768, 512, 256, 128, 64], [10], [8,192], [\$0.07], [100+ major languages, including Chinese, English, Spanish, French, Portuguese, Indonesian, Japanese, Korean, German, and Russian],
  [text-embedding-v3], [1,024 (default), 768, 512], [10], [8,192], [\$0.07], [50+ major languages, including Chinese, English, Spanish, French, Portuguese, Indonesian, Japanese, Korean, German, and Russian]
)

#let a_010 = link(
  "https://openrouter.ai/qwen/qwen3-embedding-8b"
)[#text(fill: blue)[OpenRouter]]

#a_010

