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
    "Reading-202602"
    h(1fr)
    counter(page).display("1/1", both: true)
  },
)

#show heading.where(level: 1): set text(size: 18pt)
#show heading.where(level: 1): it => pad(top: 4pt, it)

= DSPy

#let a_001 = link(
  "https://dzone.com/articles/dspy-framework-technical-guide"
)[#text(fill: blue)[article]]

#let a_002 = link(
  "https://dzone.com/articles/prompt-engineering-is-dead-long-live-dspy"
)[#text(fill: blue)[article2]]

Link: #a_001 \
Link: #a_002 \
Source: dzone

*Problem to Solve* Prompt is brittle, unpredictable and exhausting to maintain. DSPy (Declarative Self-improving Python) comes in.
DSPy treats language models as programmable components like any other part of your software stack.

With DSPy, you declare what you want your AI to do. The framework then automatically optimizes prompts,
handles errors gracefully, and ensures reliable outputs, all while letting you focus on the bigger picture.

== Three Aspects
- Declarative Programming - Define WHAT your system should accomplish, not HOW
- Automatic Optimization - Continuously improve prompts using training data without manual intervention
- Production Resilience - Build-in patterns for validation, caching, and monitoring

#figure(
  image("Images/image_2026031001.png", width: 100%),
  caption: [Hardware setup (#a_001)],
)

= Skill-Creator

#let a_003 = link(
  "https://www.toutiao.com/video/7613955966005953070/?app=news_article&category_new=tt_video_immerse&module_name=iOS_tt_others&req_id_new=20260308105702D0B658F63AB736D6F65A&share_did=MS4wLjACAAAAw3rqzAbRbSo4klPah7FJFhb-dpoy0Y2_hu6Pcvvt2pc&share_token=025309c2-1a9e-11f1-ad0d-08c0eb433e7e&share_uid=MS4wLjABAAAAw3rqzAbRbSo4klPah7FJFhb-dpoy0Y2_hu6Pcvvt2pc&timestamp=1772940137&tt_from=weixin&upstream_biz=iOS_wechat&utm_campaign=client_share&utm_medium=toutiao_ios&utm_source=weixin&wxshare_count=1&source=m_redirect"
)[#text(fill: blue)[article]]

Link: #a_003

Source: WeChat

This is a video that shows how to use Anthropic skill-creator to create skills.

= AutoSkill

#let a_004 = link(
  "https://github.com/ECNU-ICALK/AutoSkill"
)[#text(fill: blue)[article]]

Link: #a_004 \
Source: WeChat

AutoSkill is a pratical implementation of Experience-driven Lifelong Learning (ELL). It learns from real interaction experiece
(dialogue + behavior/events, automatically cerates reusable skills, and continuously evolves existing skills
through merge + version updates.

#figure(
  image("Images/image_2026031002.png"),
    caption: [AutoSkill (#a_004)]
)
