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

= List of Figures
#outline(
  title: [],
  target: figure.where(kind: image),
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
    "Diary-20260313"
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

// #figure(
//   image("Images/image_2026030101.png", width: 100%),
//   caption: [Hardware setup (#a_030105)],
// )

#set page(numbering: "1")
#counter(page).update(1)
#counter(heading).update(0)

= Inside Claude Code 

#let a_0101 = link(
  "https://ccunpacked.dev/#agent-loop"
)[#text(fill: blue)[WebSite]]

#let a_0102 = link(
  "https://alex000kim.com/posts/2026-03-31-claude-code-source-leak/"
)[#text(fill: blue)[Article]]

#a_0101 \
Source: Hacker News

This website analyzes Claude Code (leaked yesterday).

#figure(
  image("Images/image_2026040101.png"),
  caption: [Claude Code Tools (#a_0101)]
)

#figure(
  image("Images/image_2026040102.png"),
  caption: [Claude Code Commands (#a_0101)]
)

#figure(
  image("Images/image_2026040103.png"),
  caption: [Claude Code Hidden Features (#a_0101)]
)

== Frustration Detection via Regex

This is kind of surprising to me:
```text
/\b(wtf|wth|ffs|omfg|shit(ty|tiest)?|dumbass|horrible|awful|
piss(ed|ing)? off|piece of (shit|crap|junk)|what the (fuck|hell)|
fucking? (broken|useless|terrible|awful|horrible)|fuck you|
screw (this|you)|so frustrating|this sucks|damn it)\b/
```

I thought LLMs can understand the languages and thus will determine the sentiment 
by understanding what the users are saying. But regex is faster and cheaper than an
LLM inference call.

Note that Google Gemini CLI and OpenAI Codex area already open source. But those 
companies open-sourced their agent SDK (a toolkit), not the full internal wriing
of their flagship products.

My understanding is that: it still matters, maybe not such a big deal. As we have
seen, Anthropic did something in the code to cope with distillation, cheating 
the use of their subscription APIs, etc. When all the internal work is open-sourced,
there is hardly any means to hide what they want to do but do not want users know it.

Anthropic acquired Bun at the end of 2025 and Claude Code is built on top of it.

= 2026/04/01 - CAD in Browsers

#let a_0103 = link(
  "https://solvespace.com/webver.pl"
)[#text(fill: blue)[WebSite]]

#a_0103 \
Source: Hacker News

Below is an example:
#figure(
  image("Images/image_2026040104.png"),
  caption: [CAD Drawing (#a_0103)]
)

This is still in an alpha release. We can wait for it to mature. Not sure whether we can use it or not.

= 2026/04/02 - Pretex

#let a_0201 = link(
  "https://github.com/chenglou/pretext"
)[#text(fill: blue)[GitHub]]

#a_0201 \
Source: Hacker News

This is an open-source TypeScript library to render text around objects.

= 2026/04/02 - Let Codex Work for You 24 Hours

#let a_0403 = link(
  "https://github.com/thu-nmrc/OpenHarness-For-Codex"
)[#text(fill: blue)[GitHub]]

#a_0403 \
Source: WeChat

This is a Python code. Can be integrated with OpenClaw, to make Codex work for you 24 hours a day.

One thing to notice that it has a file MISSION.md. You express what you want to do in this
markdown doc. This is quite important.

= 2026/04/02 - LangChain DeepAgents Harness

#let a_0404 = link(
  "https://mp.weixin.qq.com/s/jnKW_jxGbvlMzrW_T2GJ1A"
)[#text(fill: blue)[Article]]

This article uses LangChain DeepAgents to develop a `Harness`. When I have time, I may need to look at it.


