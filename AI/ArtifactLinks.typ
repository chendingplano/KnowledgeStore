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

= Artifact Links

The design principle for artifact links is for human users and AI. Links will create
a *machine-readable knowledge graph* that can be used equally well for both human users
and LLMs.

Links should ideally be:

- *Logical*: Links should be logical, independent of file names, link refactoring, storage agnostic. 
- *Machine-friendly*: easy for machine to recognize, extract, and interpret
- *Easy to parse into graph edges*
- *Automatic*: links are created by AI automatically, but can be adjusted by human users.
- *Concepts*: links can link to files, but in general, it can link to anything, such as entities, concepts, topics, claims, requirements, sections, paragraphs, records, etc.
- *Propositions*
- *Traceability*
- *LLM Reasoning*

== Link Format

Below is link formats:

```text
[link](link-display-text)
```

== Standard Markdown Links (the foundation)

The basic syntax is:

```md
[Link text](path-or-url)
```

*Examples*

```md
[My Note](my-note.md)
[Google](https://google.com)
```

This is:

- Explicit
- Portable
- Works everywhere

== Relative Links

For a file-based knowledge base (like MKBP), you’ll mostly use *relative paths*:

```md
[Database Concepts](../databases/concepts.md)
```

This is important because:

- It keeps your system *filesystem-native*
- No global index required

== Wiki-style Links (Obsidian-style)

Tools like Obsidian use:

```md
[[My Note]]
[[Database Concepts]]
```

Advantages of this approach:

- No need to write paths
- Encourages *linking-first thinking*
- Feels like a wiki

== Variations

```md
[[My Note|Custom Text]]
[[folder/My Note]]
```

This is *not standard Markdown*, but widely adopted in note systems.

== Anchors (linking to a specific section)

You can link to a heading inside a file:

```md
[See section](my-note.md#database-design)
```

Where:

```md
## Database Design
```

becomes:

```
#database-design
```

== Backlinks (implicit links)

Not written explicitly—but generated:

If:

- `A.md` links to `B.md`

Then:

- `B.md` shows: “Linked from A”

This is what makes systems feel like a *graph*

== Tags (soft links)

Another lightweight linking method:

```md
#database
#llm
#postgres
```

These are:

- Not explicit edges
- But still form *semantic clusters*

