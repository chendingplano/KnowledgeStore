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
    "Reading-20260303"
    h(1fr)
    counter(page).display("1/1", both: true)
  },
)

#show heading.where(level: 1): set text(size: 18pt)
#show heading.where(level: 1): it => pad(top: 4pt, it)

#show heading.where(level: 2): set text(size: 16pt)
#show heading.where(level: 2): it => pad(top: 4pt, it)

#show heading.where(level: 3): set text(size: 14pt)
#show heading.where(level: 3): it => pad(top: 4pt, it)

= Use Playwright CLI

#let a_001 = link(
  "https://dzone.com/articles/end-to-end-automation-playwright-cli"
)[#text(fill: blue)[article]]

Link: #a_001

Source: dzone

Originally, users use MCP to access Playwright. The problem with Playwright
MCP is that it consumes too much context.

Playwright-cli is a new way of using Playwright for browser automation.
Instead of returning tons of information, it returns structured information,
mostly, normally in the range of a few KB.

Installed it in ~/Workspace/ThirdParty/playwrite/. There is a README.md and
a mise.toml.

= IP DB

#let a_002 = link(
  "https://ip66.dev/"
)[#text(fill: blue)[article]]

Link: #a_002

Source: Hacker News

This is a free version, updated daily. A service in shared/go/api/ipdb is created by Claude Code.

= Skill Marketplace

#let a_003 = link(
  "https://skillsmp.com/"
)[#text(fill: blue)[article]]

Link: #a_003

It has over 350,000 skills.

= mitm proxy

```bash
mitmdump --mode reverse:https://api.anthropic.com --listen-port 8000 --save-stream-file traffic.mitm
```


