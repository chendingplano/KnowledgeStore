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
    "Review - Tecent Marvis"
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
  keywords: [Agent OS, Agentic System, Personal AI Assistant, multi-agent, computer-use],
  file_type: "typst",
  logical_name: "TecentDB Agent Memory",
  file_id: "2026051801",
  source: "https://github.com/Tencent/TencentDB-Agent-Memory",
  content_type: "review",
  document_date: "2026/05/25",
)

= Overview
Tencent’s Marvis (马维斯) is positioned as an *operating-system-level personal AI assistant*, 
which is a materially different ambition from the typical chatbot or browser-based AI copilot. 
Rather than acting only as a conversational interface, Marvis is designed to understand and 
operate across the user’s local computing environment—system settings, files, applications, 
and cross-device workflows—so the computer itself becomes a manipulable AI-native environment. 
Tencent frames it less as “an app you talk to” and more as an AI middleware layer between the 
user and the operating system. ([China Daily][1])

A core design theme is *agentic task execution*. Marvis appears to use a [[ref:multi-agent]] 
architecture where a coordinating agent delegates work to specialized [[ref:sub-agents]] 
for domains like file handling, application control, browsing, and system operations. The 
practical implication is that instead of merely answering “how do I do X?”, it aims to actually 
perform the steps: changing system settings, finding files by semantic meaning instead of 
filename, organizing documents, checking device state, or orchestrating workflows spanning 
multiple apps. This puts it closer to the “computer-use agent” category (similar in spirit 
to systems like Operator, Claude Computer Use, or Open Interpreter-style automation), but 
integrated deeper into the OS. ([China Daily][1])

Another major differentiator is its *dual execution model: cloud efficiency vs. local privacy*. 
Tencent emphasizes a privacy mode where AI processing runs locally on-device, allowing sensitive 
operations without cloud transmission, alongside a cloud mode for heavier reasoning and broader 
model capability. This is strategically important because operating-system-level assistants 
inherently touch sensitive assets: local files, credentials, browser state, application data, 
and potentially enterprise documents. Marvis appears to recognize that an agent with system 
privileges must solve not just capability, but trust and governance. Reports also indicate 
confirmation checkpoints for sensitive actions like security-relevant changes or 
transactions. ([China Daily][1])

From a systems architecture perspective, what is most interesting is that Marvis treats the computer 
as a *structured action environment*, not merely a document corpus. That means its internal abstractions 
likely include representations of files, apps, devices, permissions, and actionable system APIs—not 
just embeddings and text retrieval. Conceptually, this makes it less like a RAG assistant and more 
like an AI-native operating shell. For SemOS thinking, this is highly relevant: Marvis demonstrates 
the “explore + act” model rather than the “retrieve + answer” model. SemOS could adopt a similar 
philosophy, except the environment being manipulated would be your semantic knowledge operating 
system instead of Windows/macOS itself.

== Article
#let a_001 = link(
  "https://mp.weixin.qq.com/s/JTt8qh-cF27W9KkUNaCDhA"
)[#text(fill:blue)[Review Article]]

#a_001 \
Source: WeChat

This article lists a few features. Recommend to read it.

[1]: https://cn.chinadaily.com.cn/a/202605/25/WS6a13a97da310942cc49adfc2.html?utm_source=chatgpt.com "腾讯上线操作系统层级AI助手Marvis，支持跨端操控与本地隐私模式 - 中国日报网"

