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
    "Diary - 2026/08"
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
  created: "2026/08/01",
  logical_name: "Diary-202608",
  file_id: "2026080101",
  file_type: "Typst",
  keywords: ["Diary"],
)

= 2026/08/04 - DataStar - The Hypermedia Framework
#let a_001 = link(
  "https://data-star.dev/"
)[#text(fill: blue)[Data-Star]]

#a_001 \
Source: Jimmy

This is a frontend technique to show pages using SSE.

= 2026/08/06 - Databricks Lakebase
Refer to 'Review-Lakebase.typ'

= 2026/08/06 - Cloudflare OSRefer
Refer to 'SemOS.typ'.

= 2026/08/15 - Polygraph
https://github.com/cognitive-fab/polygraph

This is a Claude Code plugin:
- You define rules
- Polygraph read your code, create state machines, and verifies whether your code breaks the rules

"Polygraph is a Claude Code plugin (and standalone CLI) that finds bugs in stateful code — workflows, reducers, protocol handlers, checkout flows, session managers — by exhaustively exploring every state the code can reach over a finite, declared domain of actions and payloads, and flagging the ones that break rules you care about, like "a customer is never charged twice."

Here is the dzone article: https://dzone.com/articles/code-generation-trust

== Polygraph and Testbot
=== Code Base vs Test Based
Testbot requires users to define a `Test Model`, which is a collection of parameters.
For instance, to test access controls:
- Support cookies or not and cookie valid duration
- User management: users must be defined in databases or files, the shapes
- Access control rules: must be configurable, either in files or databases, the shapes
- All the APIs and CLIs

Most of the above is done by LLMs. Users need to provide the initial inputs only.
LLMs will generate a testbot in the language of user's choice.

Testbots can run:
- max number of test cases
- max duration
- stop after N errors are detected

LLMs do need to read the code for APIs and CLIs, data structure shapes, etc.
But they do not read the entire codebase. The places where LLMs are applied
normally has very little undeterministic room. For instance, to collect all
the CLIs and APIs, the data shapes, etc. This is very different from reading
and comprehense the code to derive state machines.

== Actions
No immediate actions for now. When we come back to work on the testbots,
this is a very important reference.

== Use Claude Code Efficiently
https://claude.com/blog/maximizing-the-value-of-your-claude-code-sessions

- Run `/clear` between tasks, if the next task has nothing to do with the current context
- Set your model and effort level before start. Changing either one can burst your prompt cache
  (I guess the momemnt you change the model and/or level, the prompt cache is invalidated)
- Prompt cache stays valid for about an hour
- Use `@-` mention files instead of naming them because naming them requires a file-read tool use.

