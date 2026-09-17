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
    "Research - Skills"
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
  logical_name: "research-ai-skills",
  file_id: "2026091802",
  source: "",
  content_type: "research",
  document_date: "2026/09/18",
  keywords: [skill, skill management],
)

= Scope <section:scope>

This is a document that discusses skill and skill management in general.
- Skill Routing (see @section:skill-routing)

= Overview <section:overview>

Most people understand what skills are and why they are important.
But a real system may have tens, hundreds or even thousands of skills.
Manually mentioning skills (skill routing) can be a useful and reliable
way of connecting skills and task, but not scalable. Letting LLMs determine
(i.e., skill routing) introduces non-deterministics: failed to invoke
the right skill, invoke the incorrect skills, skill ambiguity.

*Example*
```text
Is ChenWeb ready to deploy?
```

""

== Skill Management <section:skill-management>

Skill Management involves:
- Skill creation (ref: @ref:context-engineering)
- Skill edit
- Skill lifecycle 
- Skill deployment
- Skill visibility
- Skill routing information and control
- Skill packaging

== Skill Routing <section:skill-routing>
(TBD).

= References
[1] Context Engineering <ref:context-engineering>
https://dzone.com/articles/understanding-context-engineering

