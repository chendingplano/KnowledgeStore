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
    "Diary 2026/03/12"
    h(1fr)
    counter(page).display("1/1", both: true)
  },
)

#show heading.where(level: 1): set text(size: 18pt)
#show heading.where(level: 1): it => pad(top: 4pt, it)

#show heading.where(level: 2): set text(size: 14pt)
#show heading.where(level: 2): it => pad(top: 4pt, it)

= DataFlow

#let a_001 = link(
  "https://dzone.com/articles/dataflow-an-open-source-dcai-system-for-llm-data-p"
)[#text(fill: blue)[Article-DataFlow]]

#let a_002 = link(
  "https://github.com/OpenDCAI/DataFlow/tree/main"
)[#text(fill: blue)[GitHub-DataFlow]]

#a_001 \
#a_002 \
Source: dzone

== Data Are the Only Differentiators

Among the major factors in AI: computing power, algorithm, data, and talents, except
data, everything will become commodity. This is the background or the grand assumption
DataFlow open-source project builds on.

== Main Concepts

The main concepts are:
- Operators
- Pipelines
- Data Agents

In JimoDB, operators are Jimos. We missed pipelines, which connects multiple jimos into 
a data processing workslow based on the business needs.

Data agents are the ones that use the data to fulfill business needs.

100% Python open-source projects.

= TADA

#let a_003 = link(
  "https://www.hume.ai/blog/opensource-tada"
)[#text(fill: blue)[Article-TADA: Text-to-Speech Open-Source Project]]

#let a_004 = link(
  "github.com/HumeAI/tada"
)[#text(fill:blue)[GitHub]]

#let a_005 = link(
  "https://arxiv.org/abs/2602.23068"
)[#text(fill:blue)[Arxiv Paper]]

#a_003 \
#a_004 \
#a_005 \
Source: Hacker News

This is an app in our Apps Store. Users can:
- Upload a wav file (a recording)
- Give a piece of text, it will generate a wav file

1B (English): huggingface.co/HumeAI/tada-1b

3B (multilingual): huggingface.co/HumeAI/tada-3b-ml

Demo: huggingface.co/spaces/HumeAI/tada

= CLI-Anything

#let a_006 = link(
  "https://github.com/HKUDS/CLI-Anything"
)[#text(fill: blue)[GitHub - CLI-Anything]]

#a_006 \
Source: WeChat

*Today's software serves humans. Tomorrow's users will be agents. CLI-Anything: bridging the gap between
AI agents and the world's software*

CLI-Anything is a framework that automatically converts existing software into AI-agent-friendly CLI tools,
allowing agents to control complex applications through structured commands instead of fragile GUI automation.

== Why CLI
#figure(
   image("Images/image_2026031201.png", width: 90%),
   caption: [Why CLI (#a_006)],
)

Starting from last year (2025), CLI is attracting more attention: Gemini CLI, ChatGPT CLI, Claude CLI,
OpenClaw CLI, etc. 

We have been living in a Graphical World (i.e., GUI) since the dot.com age. This is fine as long as
the users of software are humans. As AI walks in our daily life, things begin changing. Software is
more and more used by agents (or non-humans). GUI is good for humans but very difficult to use for
agents.

This drives future software to be designed or be friendly to both human users and agents as well.
CLI is not very human-friendly but preferred by agents. 

Instead of manually generating CLIs from a software project/product, CLI-Anything can create its CLI
automatically (hopefully). This is the value proposition for CLI-Anything.

*Example idea*:

Human workflow	Agent workflow
Open Blender → click menus	blender-cli render scene.blend
Open LibreOffice → edit document	libreoffice-cli update-table report.odt
Open GIMP → apply filter	gimp-cli filter blur image.png

The agent can now control these tools reliably via commands instead of GUI automation.

== What CLI-Anything Actually Does

The system automatically generates a CLI from an existing software codebase
using a multi-stage pipeline.

=== Step 1 - Source Code Analysis

It scans the software's code to find:
- UI actions
- Event Handlers
- Internal APIs

=== Step 2 - CLI → Function Mapping

Human actions like:
- clicking buttons
- selecting objects
- dragging elements

are mapped into callable functions.

=== Step 3 - CLI Design

It generates:
- Command groups
- Arguments
- Operations

*Example*
```bash
image resize input.png --width 800
```

=== Step 4 - CLI Code Generation

It builds a CLI (often with Python frameworks like Click)

=== Step 5 - Structured Outputs

Commands can return JSON.

=== Step 6 - Integration with Real Software

The CLI doesn't reimplement features.

It calls:
- native APIs
- scripting interfaces
- headless mode

=== Step 7 - Automated Tests

The tool automatically generates tests to verify the CLI behaves like the original software.
