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

= Run Qwen Locally

#let a_001 = link(
  "https://unsloth.ai/docs/models/qwen3.5"
)[#text(fill: blue)[article]]

Link: #a_001


Source: Hacker News

It lists all the model names and memory requirements. Can be useful when we want to run them locally.

= File Systems Are Having a Moment

#let a_002 = link(
  "https://madalitso.me/notes/why-everyone-is-talking-about-filesystems/"
)[#text(fill: blue)[File Systems as Interface]]

#let a_003 = link(
  "https://www.infoq.com/news/2026/03/agents-context-file-value-review/"
)[#text(fill: blue)[Zurich Paper]]

Link: #a_002 \
Link: Zurich Paper (#a_003) \
Source: Hacker News

#quote(block: true, attribution: [#a_002])[
If you've been paying any attention to the AI agent space over the last few months, 
you've noticed something strange. LlamaIndex published "Files Are All You Need." 
LangChain wrote about how agents can use filesystems for context engineering. 
Oracle, yes Oracle (who is cooking btw), put out a piece comparing filesystems 
and databases for agent memory. Dan Abramov wrote about a social filesystem built 
on the AT Protocol. Archil is building cloud volumes specifically because agents 
want POSIX file systems.
]

#quote(block: true, attribution:[#a_002])[
Jerry Liu from LlamaIndex put it bluntly: instead of one agent with hundreds
of tools, we're moving toward a world where the agent has access to a filesystem
and maybe 5-10 tools. That's it. Filesystem, code interpreter, web access.
And that's as general, if not more general than an agent with 100+ MCP tools.
]

#quote(block: true, attribution:[#a_002])[
Karpathy made the adjacent observation that stuck with me. He pointed out that
Claude Code works because it runs on your computer, with your environment,
your data, your context. It's not a website you go to — it's a little spirit
that lives on your machine. OpenAI got this wrong, he argued, by focusing on
cloud deployments in containers orchestrated from ChatGPT instead of simply
running on localhost.
]

== Context Are Not Memory

#quote(block: true, attribution:[#a_002])[
We do not re-read our entire life story every time we make a decision.
We have long-term storage, selective recall, the ability to forget things
that don't matter and surfce things that do.
]

Context in LLMs are none of that. They are more like a whiteboard that
someone keeps erasing and updating.

== Why Filesystems

=== Filesystems are 'Memory'

Context normally not selective. It tends to contain as much content as
LLMs might use: skills, tools, conversation history, persona, etc.

Filesystems are similar to 'Human Memory':
- Selective
- Recallable
- Long Term

Filesystems solve this problem in a very simple way:
- Write things down
- Put them in files
- Read them back when you need them

=== Organizing Files Is the Key

There are many ways to organize files.
- Filesystems are inherently hierarchical. Files are naturally organized by
  categories, purposes, dates, projects, etc.
- `AI Files`: CLAUDE.md, SKILL.md, AGENTS.md, README.md, INSTALL.md, SOUL.md, ABOUTME.md
  ABOUT.md, PROJECT.md, RULES.md, etc.
- You can add more `AI Files`. LLMs are smart enough to understand it
  without having to tell them.
- File names normally carry semantics

=== `AI Files`

`AI Files` possess the following LLM-friend properties:
- Names are meaningful and understandable to LLMs
- Information intense
- Purpose-build files
- Structural (at least can be structural)
- LLM friendly (no parsing)
- User friendly (nearly anyone can create/edit it without difficulty)
- No user names, password to access it
- No SQL to learn in order to use it
- No vendor lock in
- No steep learning curve

== Files Are No Longer the Files We Are Familiar With

Broadly speaking, we may have two types of files:
- Data Files: this is the file we are familiar with
- Humanoid Files: this is a new breed.

=== Plain Files

Plain Files (or Text Files) are the ones on the rise because they are friendly
for both humans and humanoids.

=== Consumers of Files

There are three types of 'consumers' for files:
- Human users 
- Programmers
- LLMs or any human-like artificial objects (humanroid, robots, auto-driver, etc.)

LLM Files are files that assume their audiance are humans, programmers and human-like (LLMs), too.
Office documents, PDFs, etc. are for humans, only. 

One may argue that documents are info files. Yes, they are. But most documents are
for humans, not for machines, not the ones we will use for AI.

== The Other Side of the Coin

=== Filesystems Not as Helpful as Expected

#quote(block: true, attribution: [Article #a_001])[
A recent paper from ETH Zürich evaluated whether these repository-level context
files actually help coding agents complete tasks. The finding was counterintuitive:
across multiple agents and models, context files tended to reduce task success rates
while increasing inference cost by over 20%. Agents given context files explored more
broadly, ran more tests, traversed more files — but all that thoroughness delayed them
from actually reaching the code that needed fixing. The files acted like a checklist
that agents took too seriously.
]

*The reason?* 
#quote(block: true, attribution:[#a_002])[
This sounds like it undermines the whole premise. But I think it actually sharpens it.
The paper's conclusion wasn't "don't use context files." It was that unnecessary requirements
make tasks harder, and context files should describe only minimal requirements. The problem
isn't the filesystem as a persistence layer. The problem is people treating CLAUDE.md like
a 2,000-word onboarding document instead of a concise set of constraints. Which brings us
to the question of standards.]


#quote(block: true, attribution:[#a_003])[
We find that all context files consistently increase the number of steps required to complete tasks. LLM-generated context files have a marginal negative effect on task success rates, while developer-written ones provide a marginal performance gain.

Our trace analyses show that instructions in context files are generally followed and lead to more testing and a broader exploration; however, they do not function as effective repository overviews. Overall, our results suggest that context files have only a marginal effect on agent behavior and are likely only desirable when manually written. This highlights a concrete gap between current agent-developer recommendations and observed outcomes, and motivates future work on principled ways to automatically generate concise, task-relevant guidance for coding agents.
]

The conclusion suggests it is not the question of whether we should have the AI files, such as CLAUDE.md,
it is the question of the quality of the AI files. The purposes of AI files are to provide information
to LLMs so that LLMs can be more productive. If LLMs are less productive, it means the quality of the
AI files are not good.

#quote(block: true, attribution:[#a_003])[
We find that all context files consistently increase the number of steps required to complete tasks. 
LLM-generated context files have a marginal negative effect on task success rates, 
while developer-written ones provide a marginal performance gain.

Our trace analyses show that instructions in context files are generally followed and lead to more
testing and a broader exploration; however, they do not function as effective repository overviews.
Overall, our results suggest that context files have only a marginal effect on agent behavior and
are likely only desirable when manually written. This highlights a concrete gap between current
agent-developer recommendations and observed outcomes, and motivates future work on principled
ways to automatically generate concise, task-relevant guidance for coding agents.
]

#quote(block: true, attribution:[#a_003])[
I’ve maintained a CLAUDE.md file for about 3 months now across two projects and the improvement is
noticeable but not for the reasons you’d expect. The actual token-level context it provides matters
less than the fact that writing it forces you to articulate things about your codebase that were
previously just in your head. Stuff like “we use this weird pattern for X because of a legacy constraint
in Y.” Once that’s written down, the agent picks it up, but so does every new human on the team.
]

== AI Files

AI in general and LLMs specific require not just ordinary files but files that are
specially prepare for them.

=== Concise

Ordinary files (including documents) are created at will. They can be deep, lengthy, and broad,
or they can be concise, specific, and info-intensive.

AI files may need to be hierarchical: the highest level is very consize and informative, while
the lower levels expose more details.

=== Hierarchical

Before we decide to read a book, we first check the book title, the date, author(s); then 
the summary, if available, of the book, reader's comments on the book; then the introduction
or the first chapter of the book. Then decide whether to read it or not.

The same is true for AI or LLMs. It is for this reason, AI files should be constructed in
hierarchy or levels:
- Level 1: Title, date, authors, keywords, tags and other metadata
- Level 2: Executive Summary
- Level 3: Detailed Summary
- Level 4: Content (possibly multiple parts, segmented semantically) 

=== Accurate

High level information should be accurate.
- Skill triggers
- Tool description
- etc.

=== Formats

Formats are becoming less sensitive. #quote(block: false, attribution:[#a_002])[
Dan Abramov's piece on a social filesystem crystallized something important here. 
He describes how the AT Protocol treats user data as files in a personal repository;
structured, owned by the user, readable by any app that speaks the format.
The critical design choice is that different apps don't need to agree on what a "post" is.
They just need to namespace their formats (using domain names, like Java packages)
so they don't collide. Apps are reactive to files. Every app's database becomes derived data
i.e. a cached materialized view of everybody's folders.]


=== `Memory`, Not Context

Files are the source to construct context, or more importantly, incremental context.

*Quote* Dan Abramove wrote: our memories, our thoughts, our designs should outlive the
software we used to create them. That is not a technical argument. It is a values argument.
And it's one that the filesystem, for all its age and simplificy, is uniquely
positioned to serve. Not because it's the best technology. But because it's the one
technology that already belongs to you *End Quote*, and to LLMs, too!

=== Files as 'Programs'

#quote(block: true, attribution:[#a_002])[
NanoClaw, a lightweight personal AI assistant framework, takes this to its logical conclusion.
Instead of building an ever-expanding feature set, it uses a "skills over features" model.
Want Telegram support? There's no Telegram module. There's a /add-telegram skill,
essentially a markdown file that teaches Claude Code how to rewrite your installation to add
the integration. Skills are just files. They're portable, auditable, and composable.
No MCP server required. No plugin marketplace to browse. Just a folder with a SKILL.md in it.
]

What is `/add-telegram`? It is a skill, you might say. Yes, it is a skill. But what exactly is
a skill? 

A Skill is a 'program'. If you want to add Telegram to NonoClaw, for instance, you can do it
manually, write programs to automate it, or use the skill: `add-telegram`. If someone wrote
the skill, now you can use it as if it were `programs`.

This is exactly one of the paradigm shifts happening today: the line between files and programs
is more and more blurring. We begin seeing more and more tasks used to be done by programs
are not done by just saying it.

=== Standards?

In programming world, `standards` is the Gold. Even in the age of AI, when Anthropic publishes
its Skill architecture, many adopts it, making it the de facto `standard`.

But `standards` are mostly for programs. Humans need much less standards when they communicate
with each other. 

Humanoids (robots, LLMs and the like) will soon follow the steps. It is ideal if everyone follows
the same format of CLAUDE.md or README.md that Anthropic defines. But the format, if exists,
is at most indicative and recommended, serving more or less as guidlines, not mandatory.

In the current implementation, a frontmatter is probably mandatory and should follow the
'standard'. As LLMs get smarter, this may not even be the same.

On the other hand, lacking standards may make things less deterministic. For instance, skill
triggering can be less deterministric if SKILL.md do not follow the `standard`.

In the future, `standard` is still required and important, but it should cover much less than
the conventional sense of standards. For SKILL.md, for instance, only very few, if at all, items
that need to be standardized.

#quote(attribution:[#a_002])[
This is interoperability without coordination. And I want to be specific about what I mean by that,
because it's a strong claim. In tech, getting two competing products to work together usually
requires either a formal standard that takes years to ratify, or a dominant platform that forces
compatibility. Files sidestep both. If two apps can read markdown, they can share context.
If they both understand the SKILL.md format, they can share capabilities.
Nobody had to sign a partnership agreement. Nobody had to attend a standards body meeting.
The file format does the coordinating.
]

*Delima of Standards*

Companies and individuals have strong incentives to make their context files just different
enough that switching costs remain high. Almost all relational databases support the 'standard'
SQL, but most of them intentionally make their SQL different from others.

*Quote* The histroy of open formats is litered with standards that won on paper
and lost in practice (SQL is an example)

Fragmentation is the default, not the exception.

=== The New Bottleneck: Context

#quote(attribution:[#a_002])[
Something similar is happening with AI agents. The bottleneck isn't model capability or compute.
It's context. Models are smart enough. They're just forgetful. And filesystems, for all their
simplicity, are an incredibly effective way to manage persistent context at the exact point where
the agent runs — on the developer's machine, in their environment, with their data already there.
]

=== Files as Interface

#quote(attribution:[#a_002])[
Richmond in Oracle's piece made the sharpest distinction I've seen: *filesystems are winning
as an interface, databases are winning as a substrate.*
The moment you want concurrent access, semantic search at scale, deduplication, recency weighting
— you end up building your own indexes. Which is, let's be honest, basically a database.
]

The file interface:
- Universal, no SQL, no dialects, no need for 'standards'
- LLMs already understand it
- No installations
- No vendor lock in
- No learning curve
- Friendly for both humand and AI

*Files Are the Original Protocol.* Files are the de factor standard not just on a specific OS,
but across platforms: Windows, Linux, MacOS, Android, etc.

Not only that, files are also for human users.

=== Writing Good Files Is Hard

When we want to use files as interfaces, we want to use files to communicate with AI,
just being files, in a format that LLMs understand (markdown, JSON, etc.), with the
assumed naming convention, is not enough.

Writing good `files` is an art. It can be difficult, but it can be done, with certain efforts.
Comparing with databases, it is much easier to be good at writing good files, or more specifically,
good AI friendly files.

=== Files + Databases

#quote(attribution:[#a_002])[
The file interface is powerful because it is universal and LLMs already understand it.
The database substrate is powerful because it provides the guaratees you need when things get real.
The interesting future is't files versus databses. It is files as the interface humands and agents
interact with, backed by whatever substrate makes sense for the use case.
]

== Personal Computing Redefined

In a broader sense, what is happening now is redefining a new form of `Personal Computing`.
- Your data
- Your context
- Your agents and skills

All live in a format you own. Any agent can read. You are not locked inside a specific application.
Your ABOUTME.md works with your falvour of OpenClaw/NanoClaw, Claude Code, Qwen Code, etc.

