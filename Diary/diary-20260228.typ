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

= Diary 2026/02/28

Date: 2026/02/28

== Create a Main Page in ChenWeb

Prompt:
```text
Create a main page:
- The theme is "My AI Assistant". This app focuses on providing users a comprehensive
  system to help users use AI, including Agents, Skills, AI apps (mostly in vertical markets),
  coding assistant (such as Claude Code, Codex, Qwen Code, OpenCode, etc.), personal digital
  assistant (such as OpenClaw), etc.
- The top panel should have a logo, a banner image, slogons, etc.
- The left panel is a menu system
- The middle pannel shows the selected pages (by clicking on a menu item)
- Upon start, it shows a dashboard in the middle panel (i.e., if no menu item is selected)
- The right panel shows additional information, if any, for the page shown in the middle panel
- The bottom panel is a footer

Save the page in ChenWeb/server/routes/home1
```

Used Qwen and Claude to generate the code. Both generated buggy code (+page)
