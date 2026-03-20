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

= Learn Claude Code

#let a_001 = link(
  "https://github.com/shareAI-lab/learn-claude-code"
)[#text(fill: blue)[article]]

Link: #a_001

Source: WeChat

== Basic Loop
#figure(
  image("Images/image_2026030601.png", width: 100%),
  caption: [Agent Loop (#a_001)],
)

== 12 Progressive Sessions

s01   "One loop & Bash is all you need" — one tool + one loop = an agent

s02   "Adding a tool means adding one handler" — the loop stays the same; new tools register into the dispatch map

s03   "An agent without a plan drifts" — list the steps first, then execute; completion doubles

s04   "Break big tasks down; each subtask gets a clean context" — subagents use independent messages[], keeping the main conversation clean

s05   "Load knowledge when you need it, not upfront" — inject via tool_result, not the system prompt

s06   "Context will fill up; you need a way to make room" — three-layer compression strategy for infinite sessions

s07   "Break big goals into small tasks, order them, persist to disk" — a file-based task graph with dependencies, laying the foundation for multi-agent collaboration

s08   "Run slow operations in the background; the agent keeps thinking" — daemon threads run commands, inject notifications on completion

s09   "When the task is too big for one, delegate to teammates" — persistent teammates + async mailboxes

s10   "Teammates need shared communication rules" — one request-response pattern drives all negotiation

s11   "Teammates scan the board and claim tasks themselves" — no need for the lead to assign each one

s12   "Each works in its own directory, no interference" — tasks manage goals, worktrees manage directories, bound by ID

= Skill Seeker

#let a_002 = link(
  "https://mp.weixin.qq.com/s/YcD3LkfBOkEoQV1rVJem7g?poc_token=HBYMrGmjjJA3ETDCtuQPas9n_K8Nop12RC5ZIH0Q"
)[#text(fill: blue)[article]]

Link: #a_002

Source: WeChat

== What Is Skill Seeker

Skill Seeker converts documents and code into structured knowledge assets - 
ready to power AI skills (Claude, Gemini, OpenAI, etc.). 
This form the source-of-truth for an AI system.
- Crawl web sites
- GitHub Repos
- Documents (PDF, ...)

== Data Layer for AI Systems

Skill Seekers is the universal preprocessing layer that sits between raw documentation
and every AI system that consumes it. 
