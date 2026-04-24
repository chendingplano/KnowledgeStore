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

#let frontmatter = (
  filename: "ArtifactLinks",
  file-type: "typst",
  link: "file:artifact-links",
  link-display: "Artifact Links",
  author: "Chen Ding",
  date: "2026-04-08",
  tags: ("Artifact Links"),
)

#set page(
  numbering: "1 of 1",
  footer: context {
    line(length: 100%)
    "ArtifactLinks"
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

= SemObj Links

The design principle for SemObj links is for human users and AI. Links will create
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

A link is made of two components:
```text
   link-id + link-name
```
where `link-id` identifies the link globally and `link-name` is the link's display name.

`link-id` format is (similar to URL):
```text
  [<link-type>:]link-identifier
```

`<link-type>` is optional. If not specified, it defaults to `content`. 

The table below list all the supported link types:
#table(
  columns: 2,
  align: left,
  [Link Type], [Explanation],
  [file], [The linked is a file (more precisely a 'virtual file')],
  [content], [The linked is something inside a object. This is the default type],
  [chapter], [A chapter in an object such as a markdown document, PDF document, etc.]
)

Link formats are file type dependent.

#table(
  columns: 3,
  align: left,
  [File Format], [Link Format], [Explanation],
  [Markdown], [[link-id](link-name)], [],
)

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
[My Note](my-note)
[Google](https://google.com)

Here is the way how to use the link: [My Note](#my-note)
```

To reference an anchor in another file:
```md
[Display Name](<file-name>#heading-anchor)
```
where: "Display Name" is the string you want to display; \<file-name\> is either a relative file name or a
full-qualified file name; "heading-anchor" is the anchor name (id). 

Note that Markdown only allows you to anchor headings. If you want to anchor something other than headings,
use the HTML tag: \<a\>:
```md
<a id="this-is-a-paragraph-anchar"></a>
This is the paragraph you want to anchor ...
...
```

Then you can use the anchor as:
```md
This is something in current file.
...
For more information, refer to [Display Name](filename#this-is-a-paragraph-anchar)
```

== Wiki-style Links (Obsidian-style)

Tools like Obsidian use:

```md
[[My Note]]
[[Database Concepts]]
```

== Backlinks (implicit links)

Not written explicitly—but generated:

If:

- `A.md` links to `B.md`

Then:

- `B.md` shows: “Linked from A”

This is what makes systems feel like a *graph*

== Frontmatter

#table(
  columns: 2,
  align: left,
  [*Attribute Name*], [*Explanation*],
  [logical-name], [Logical name],
  [logical-filename], [Logical file name],
  [real-filename], [Real file name],
  [file-type], ['typst', 'text', 'md', etc.],
  [link], [file:artifact-links],
  [link-display], [Artifact Links],
  [author], [Chen Ding],
  [date], [2026-04-08],
  [tags], [Artifact Links]
)

Logical names serves as a "Classification" mechanism. Any SemObj with the same logical name
are linked together. For instance, "Chaos Engineering" is a logical name. SemObjs with
this logical name are automatically linked (grouped) together.

Logical file names are used in links. They are 'logical' so that when a file is renamed/moved, 
it will not break the links.

