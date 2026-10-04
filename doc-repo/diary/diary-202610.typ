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
    "Diary - 2026/10"
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
  logical_name: "diary-202610",
  file_id: "diary-202610",
  source: "",
  content_type: "diary",
  document_date: "2026/10/03",
  keywords: [diary],
)

#let callout(title, body) = block(
  fill: rgb("#f3f6fa"),                       // light blue-grey background
  stroke: (left: 3pt + rgb("#4b6b88")),       // accent bar on the left
  inset: (left: 12pt, right: 10pt, top: 8pt, bottom: 8pt),
  radius: 3pt,
)[
  *#title*

  #body
]

= 2026/10/03

== Context Language Model <context-language-model>

*“Context Language Models” (CLMs) proposes letting an LLM directly edit its own working context.* Instead of 
continually appending messages and relying on automatic summarization, the model can decide what to preserve, 
rewrite, remove, or offload. Existing models can use this approach without retraining. 
[arxiv.org](https://arxiv.org/pdf/2609.37725?utm_source=chatgpt.com)

The implementation mirrors the live context into an editable file. The agent modifies it using Bash, and the 
changes become its input for the next turn. Observed behaviors include maintaining compact progress notes, 
removing irrelevant search results, and updating multi-agent trackers. The key distinction from ordinary 
file-based memory is that *editing this file changes what the model sees 
next*. [arxiv.org](https://arxiv.org/pdf/2609.37725?utm_source=chatgpt.com)

Results suggest better performance at lower computational cost: on BrowseComp-Plus, CLMs achieved 59.4% 
accuracy—11.4% higher *relatively* than the strongest baseline—with 21.5% fewer inference FLOPs. Reinforcement 
learning further improved context management. These compute savings should not automatically be interpreted as 
equivalent latency or billing savings. [arxiv.org](https://arxiv.org/pdf/2609.37725?utm_source=chatgpt.com)

The authors also introduce suffix-cache reuse to reduce recomputation after edits, although surviving cached 
states retain information from the previous context. They identify editable context as a potential 
prompt-injection channel. My takeaway: agent-controlled working memory is promising, but preserving 
evidence and context integrity remains essential. [arxiv.org](https://arxiv.org/pdf/2609.37725?utm_source=chatgpt.com)

= 2026/10/04

== Data - Game History
link: https://gamehistory.org/5k-magazines/

It collects over 5,000 magzines. The documents are about games. Not sure whether
they are useful.

== Agents Don't Need Memory. They Need Documentation

#let ref-agent-memory = link(
  "https://liao.gg/blog/agents-dont-need-memory"
)[#text(fill: blue)[Agent Memory]]

#let ref-operator-memory = link(
  "https://github.com/aerovato/operator-memory"
)[#text(fill: blue)[Agent Memory - Operator Memory]]

#ref-agent-memory 

#ref-operator-memory

*Problems*
- Memories are surfaced by similarity
- Memories are stored without context
- The past is treated as truth
- Agents can't search for what they don't know
- The store is unauditable: which are stale? which have never been retrieved? which are incorrect
  and secretly affecting the way your agent works? which supersedes others?

Here is my take:
- There should always be a topic or multiple topics for the current session.
  WHen a turn finishes, it uses a decision model to determine whether 
  the turn is related to the current topic(s) or new topics.
- There is a knowledge store for memory only. 
- Snippets are indexed by topics, sorted by time
- New snippets can override old ones (i.e., chain the 'same' snippets)
- Before processing a query, let the decision model determine whether 
  the query is relevant to the current topics, topics in the database,
  or new topics. If it is relevant to other than the current topics,
  reconstruct the memory by the new topics

This is similar to the Context Language Model (@context-language-model).

#figure(
  image("Images/image_2026100401.png", width: 100%),
  caption: [Change the loop (#ref-agent-memory)]
)

The author created an open source project (#ref-operator-memory) and used
it for over a year. It is purely markdown files. No vector stores, no
similarity calculations. 

- Complete Context Engine - Documentation, memory, indexes, and skills
- Automatic Documentation - specs, decisions, research, and more are
  automatically documented by the agent.
- Transparent Memory - memory is stored as markdown documents
- Shareable Knowledge - track documents with Git and share knowledge
  with your team
- Zero Infrastructure - no background agents, no embeddings, no vector
  databases, no model configuration.

*Actions*
- Summarize what the open-source does
- Get the main ideas behind it
- Implement a similar memory system

== What Muse Done Right

#let ref-muse-done-right = link(
  "https://metedata.substack.com/p/what-meta-got-right-with-muse"
)[#text(fill: blue)[What Muse Done Right]]

#ref-muse-done-right

*About Author*

The author (Mete Polat) is a product designer and builder, 
worked in companies like Netflix and Peloton. It appears the
author is very good at designing products.

*About Muse*

All the sudden, Muse come from nowhere and became one of the most
touted frontier model of all. It does not just make a model smarter,
but make it better for people to use it.

"Muse abstracted away of the unnecessary complexity. There is no
model selector, work vs chat switch, obscure slash commands, or
mentions of MCPs or cron jobs. It's one main chat, and everything
else serves to support it - a space to elevate ideas, track goals,
and surface artifacts it created for you. *Most importantly, 
it gave users a clear memtal model* - this is your personal helper
with their own computer."

"Each SaaS app was effectively a toolbox. Our job as designers was
to understand the job at hand, surface the right tools in a given
context, and make those tools easy to use so you can accomplish the 
job. With *LLM agents, a SaaS app is now more akin to a coworker 
that goes out and does the job.*"

#callout(
  "Comments",
  [
  SemOS is an SaaS. We should follow the same principle: it is a
  chatter. Everything else is designed around it. Users do not 
  have to use menus. When a user wants to review a document, 
  he/she can simple say: please review document 1234. SemOS
  will then pop up a dialog to collect information about the
  document to review.
]
)

*About Tools*

SemOS should focus on building tools. In an agentic system, the
core is a 'brain': the LLMs and the interface to the users: chatter.
But LLMs can barely do anything on users stuff. Tools are the
critical part to empower LLMs with users private data, knowledge,
environment, system.

A harness is another important ingredient to thread all pieces
together.

=== Making AI Cute Again
ChatGPT and Claude product branding is geared towards techies.
The products are sleek and the branding is aspirational, but to most
people it comes off as sterile and elitiest, at best. 

Muse went deep into anthropomorphization and the cuteness factor
to help you build personal affinity with your agent.

=== Take aways
"Interestingly, what’s making Muse a success also explains why Google 
has mostly failed to capture the zeitgeist so far. They have the 
compute and the ad money to fund something like Muse. But they 
have no product chops to build something simple and understandable 
in consumer AI.

OpenAI fumbled the consumer AI market by not investing in ads earlier. 
When they realized most people won’t pay for AI subscriptions, they 
refocused on enterprise to compete with Anthropic. Their ads business 
may be growing, but they’re well behind - they still have no established 
cash flow to fund something like Muse (their new “dots” product is a 
paid-tier feature).

Apple fumbled it (for now) because they never built the expertise to 
build AI, blinded by iPhone success, privacy posturing, and Google bribes.

Now Meta will pick up the pieces (literally and figuratively) - the 
pie is there for the taking. Muse is the first positive indicator."

== Work with Claude Opus 5.5
link: https://claude.dev/blog/getting-the-most-out-of-opus-5-5/

Anthropic wrote this article to help people get most out of Opus 5.5.
One major difference between Opus 5.5 and the older ones is that
it can work longer on complex tasks.

=== CLAUDE.md
We may need to add the following to CLAUDE.md:

"When a step doesn't need my input, keep going. Put status notes in 
the same message as your next action.
Stop and ask only when you can't continue without me, or before anything 
destructive: deleting data, force-pushing, or changing anything outside 
this repository."

=== About 'Stop'
You should consider telling Opus 5.5 when to stop, or what 'stop' means.
Below is an example:

"Migrate the payment endpoints from the old client to the new one.
Done means: every endpoint uses the new client, the old client is 
deleted, and the test suite passes.
Stop and ask me only if a test fails for a reason you can't explain."

=== Split Big Work
Early versions coordinate parallel subagents on long audits and
migrations, with little oversight.

For Opus 5.5, consider the following example:

"Audit every service in services/ for the retry bug in the linked issue.
Give each service to its own subagent. When a subagent reports back, 
check its evidence before you accept it.
Finish with one table: service, affected yes or no, and the evidence."

=== Keep task lists in a file
Opus 5.5 runs are longer now. A long run fills the context window,
and Claude Code then summarizes older turns. A list in a file survives
that, and it shows you at a glance what's done and what's left.

*How*

"Keep a checklist in TASKS.md. Tick each item when it is done, 
and add anything new you find."

#callout(
  "Comments",
  [This is where Claude Code goes wrong. Why you ask users to do it?
  If this is important, why you (Opus 5.5 or the harness) do it, so that
  users don't have to know the details.

  What I can think off for SemOS is that we will add this to LLMs
  (not just Opus 5.5) to keep tasks in files, automatically.

  The same idea applies to all other recommendations from Anthropic
  in its article.
]

)
