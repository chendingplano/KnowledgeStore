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

// #table(
//  columns: 3,
//  align: left,
//  [Name], [Description], [Documentation],
//  [Bicep], [Microsoft], [Azure-specific],
//
// #figure(
//   image("Images/image_2026030101.png", width: 100%),
//   caption: [Hardware setup (#a_030105)],
// )

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

=== Delete Memory

=== Enable Memory

It enables disabled memory

=== Disable Memory

=== Query Memory

== Retrieve Memories

