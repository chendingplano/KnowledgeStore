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

== Memory Storage

Memories are stored in multiple dimensions:
- Semantic Dimension (in SHG)
- Time Dimension
- Special Dimension

=== Special Dimension

This dimension organizes memories in specific files.

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

=== Time Dimension - Chat History

We may use the strategy that OpenClaw uses:
- Store chat history in files, one per day

=== Semantic Dimension

Memories are organized by topics (i.e., semantics).

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

