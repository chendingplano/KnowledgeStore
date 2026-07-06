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
    "Diary - 2026/07"
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
  created: "2026/07/01",
  logical_name: "Diary-202607",
  file_id: "2026070101",
  file_type: "Typst",
  keywords: ["Diary"],
)

= 2026/07/02 - chartdb

#let a_001 = link(
  "https://github.com/chartdb/chartdb"
)[#text(fill: blue)[ChartDB]]

#a_001 \
Source: WeChat

This is an open-source pure TypeScript project that draws ER charts for databases.
We may integrate this open source to SemOS.

= 2026/07/02 - Skill Management
#let a_002 = link(
  "https://mp.weixin.qq.com/s/J_qkNulpWYDkKDaReM9QzQ?poc_token=HJRFRmqjrBMZIuuIcRdJpeljVKu5NGFaYlz-m_La"
)[#text(fill: blue)[Skill Management]]

#a_002 \
Source: WeChat

Main features:
- Skill repository
- Search
- Management
- Security
- Status Management
- Installation to Coding Agents
- Statistics on using/not using a specific skill
- Skill usage statistics
- Skill Room: each skill room is dedicated to a specific skill, showing how to use the skill, the effectiveness, etc.

#figure(
   image("Images/image_2026070201.png", width: 100%),
   caption: [Skill Platform (#a_002)],
)

= 2026/07/06 - Traefik
#let a_003 = link(
  "https://traefik.io/traefik"
)[#text(fill: blue)[Traefik]]

#a_003 \
Source: Jimmy

This is a replacement for Nginx.
