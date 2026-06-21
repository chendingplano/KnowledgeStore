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
    "Memory Research"
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

#show heading.where(level: 4): set text(size: 14pt)
#show heading.where(level: 4): it => pad(top: 4pt, it)

#let a_001 = link(
  "https://help.openai.com/en/articles/8590148-memory-faq"
)[#text(fill: blue)[ChatGPT Memory]]

= Memory

== Definition

Memories are defined by the following properties:
- ID (format to be determined)
- Title
- Create Time
- Last Modify Time
- Status: active, disabled, deleted
- Recency
- Read-Only
- Source
- Origin
- Keywords
- Categories
- Keywords
- Summary
- Description
- Content

== Memory Hierarchy

- L1 - MemCell: the atomic memory
- L2 - Compound Memory Objects
  - SemObj: such as Person, Project, File, Function, etc.
  - Story: a timeline of events
  - Session: discussion sessions or history, temporal: its content may fade as time goes by.
  - Project

Note that memory hierarchy is also SemOS hierarchy because memory and semantic objects
are essentially the same.

=== SemObj Timestmaps
We will use three timestamps ([[ref:dual timestamps]]):
- Event Time: the time when an event actually happened
- Document Creation Time: the time when a document was created (note: not added to SemOS). 
  As an example, if a SemObj memtions "I worked in Facebook last year" and the 
  SemObj's document creation time is 2025, we can derive: (1) the person worked in Facebook
  in 2024 and (2) the person no longer works for Facebook.
- Document Add Time: the time when the document is added to SemOS.

These timestamps are important in reasoning.

=== MemCell [[Memory Atomic Unit, MemCell]]

This is from [[EverOS]]. A similar concept is [[Atomic Memory]] from [[Supermemory]].
This is the atomic memory in SemOS.

There are two types of MemCells:
- Directly from original content
- Derived from the source

*Derived - Personal Preference*
```text
原始对话：
用户：我最近在考虑换工作，现在在ABC公司做软件工程师，
     但我觉得薪资不太满意，而且通勤太远了。

提取的原子记忆：
1. 用户在ABC公司担任软件工程师
2. 用户对当前薪资不满意
3. 用户通勤距离过长
4. 用户正在考虑换工作
```

*Derived - Project*

It creates a Memory Object

=== Memory Dimensions

Memories are stored in multiple dimensions:
- Semantic Dimension (in SHG)
- Time Dimension
- Special Dimension

==== SOUL.md

It stores the basic information about a person, such as name, home address,
phone number, spouse, children, other family members, etc.

==== PREFERENCE.md

==== SPECIALTIES.md

==== FRIENDS.md

This is a list of a user's friends. Friends can be added explicitly or automatically.
Users can say "<name> is my friend. Please remember it!"

To show all the fiends the agent has learned and memorized, you can say: "How all my friends in memory"
or use the commands /memory, which should show a menu of memories. Select "friends".

==== INTERESTS.md

This is a list of a user's interests. Interests can be added manually or automatically.
To add an interest manually, you can say "Add \<interest\> as my interest to memory",
or use the slash command and select memory -> interests.

==== Time Dimension - Chat History

We may use the strategy that OpenClaw uses:
- Store chat history in files, one per day

==== Semantic Dimension

Memories are organized by topics (i.e., semantics).

== Memory Storage

Memory is organized like folders, real or virtual.

```text
-- Memory
   |- SemMemory
      |- Module A
         |- ...
   |- Self
      |- SOUL.md
      |- PREFERENCE.md
      |- SPECIALTIES.md
      |- FRIENDS.md
      |- INTERESTS.md
   |- ChatHistory
      |- 20260424
      |- 20260423
      |- ...
   |- ...
```
== Operations

=== Add Memory

Users can add memory at any time by saying: 
```text
Add the following to memory:
<the content>
```

Users normally do not need to worry about how to organize (i.e., how to store) memories.
LLMs will analyze the memory and put it into the right location in SHG.

[[ref:memory management]] from [[ref:supermemory]] is a good example:
- Check whether the new SemObj contradicts with existing ones. If yes, mark the existing one
  as expired (not deleted) and add the new one. Refer to the comment for this operation.
- Check whether the new SemObj completes existing SemObj
- Try to derive new SemObj, such as new entities, relations, SemObjs, etc.

=== Delete Memory

=== Enable Memory

It enables disabled memory

=== Disable Memory

=== Query Memory

== Retrieve Memories

== Thoughts - SemMemory: Memory by Topics
[[def: Topic Memory, Semantic Memory, SemMemory, Research Ideas]]

Here is what happened to me: 
- Working on a feature/module
- Write its spec
- Write code through code assistant
- Tests, especially the Testbot
- Manually debug
- Problems and fixes
- Refactoring
- ...

Then I move on working on another module or feature. Possibly months later, I want to add
new features, change the code, fix bugs, or refactor the code. It will be good if I can see
see a clear picture about the module, from idea forming, all the way to what it is today
easily and quickly, instead of sifting through tons of documents, reading the code, etc. 
Session history often fails. 

This is called [[def:*SemMemory*]].

SemMemory is a document, a well-written document that clearly captures all the important insights.

SemMemory is a living document. Any time when we touch the code, its SemMemory is updated
accordingly, ALWAYS. SemMemory and the corresponding code is a [[Semantic Twin]], a critical
mechanism that shifts from Code-as-the-first-citizen to Document-as-the-first-citizen.

SemMemory is written by human users AND AI. This is especially important in later stage of
SemObjs. One small mis-synchronization will break the tie between SemMemory and the SemObj.


SemMemory is designed not just for human users but also for AI 
so that when I revisit this module/feature, all I need to do is to tell AI "Working on xxx, ..."

SemMemory should tell:
- What are the goals
- What goals are changed
- What the module is (spec)
- What capabilities exist
- What are missing (planned or detected)
- What changed
- Rules, guard rails
- Coding requirements (such as logging, error reporting, etc.)
- The tests

There are tons of techniques that we can use to manage SemMemory, such as:
- Retention plan: forget the unnecessary history
- Lazy exposure
- Compact
- Multi-Level content (higher layer is more compact and lower level has more details)
- Sub-topics

*Advanced Features*\
Potential advanced features:
- Self-Evolving: detect defacts, missing features, suggest new features based on the past usage patterns.
- Self-Learning: read an article, an open-source project; compare it with a SemObj; evolve it.

=== Semantic Twin
[[def:Semantic Twin]]

The binding between a SemObj and its SemMemory is critical.

*Definition*: A SemMemory is Consistent if:
- Its SemObj (the code) can be re-produced at any time, possibly in any programming language
- It contains all the non-trivial information
- It is constantly checked with its companion SemObj (code) automatically by AI

== Build Agent Memory on ElasticSearch
The context window is a short-term memory. What is missing is long-term memory: a persistent
store that survives session end, scales to years of interaction, and lets you
retrieve facts by content, by time, and by user ([1]).

Agent Memory is an open-source ([2]).

#figure(
  image("Images/image_2026061901.png"),
  caption: [Agent Memory ([1])]
)

=== Three Types of Memory
- Episodic: Time-stamped events: each user turn as it lands, before any extraction 
  or interpretation. Most of it is short-lived: not always worth keeping.
  A few entries become evidence for durable facts later.
- Semantic: Distilled, stable assertions about the user. These survive across
  sessions and are what the agent grounds in
- Procedural: Multi-stp playbooks.

Each category has a different lifecycle. Episodic is written constantly and decays.
Semantic is curated, deduped, and superseded as the user changes. Procedural
accumulates outcome feedback that feeds consolidation.

== References
[1] Build Agent Memory on ElasticSearch,
https://www.elastic.co/search-labs/blog/agent-memory-elasticsearch

[2] atlas-memory-demo,
https://github.com/noamschwartz/atlas-memory-demo
