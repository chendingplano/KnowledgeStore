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
    "Reading-20260304"
    h(1fr)
    counter(page).display("1/1", both: true)
  },
)

#show heading.where(level: 1): set text(size: 18pt)
#show heading.where(level: 1): it => pad(top: 4pt, it)

#show heading.where(level: 2): set text(size: 16pt)
#show heading.where(level: 2): it => pad(top: 4pt, it)

#show heading.where(level: 3): set text(size: 14pt)
#show heading.where(level: 3): it => pad(top: 4pt, it)

= Pi.dev 

#let a_001 = link(
  "https://mp.weixin.qq.com/s/vjdMPgnGJ7wPEBTjbcq4qg"
)[#text(fill: blue)[article]]

Source: TouTiao

== No MCP

*Reason*: MCP lets external entities to define tools. Pi not using MCP is deliberate. It does not want 
external entities to control LLMs. Instead, it lets LLMs express exactly what it needs, by writing
JavaScript code (arrow functions), including manipulating databases, making REST API calls, etc.

This requires sandboxes for security.

*Comment*: The idea of giving LLMs full control is definitely good. But use this method with care.
Simple tasks, such as retrieving something from databases, making a known REST API calls, 
are okey with it. If LLMs need to do more complicated tasks, we should give LLMs a rich set of
tools.

When there are too many tools, make sure to let LLMs discover the tools they want to use,
such as Code Mode from Cloudflare.

*Improvement*: One important improvement in tool use is to prompt LLMs to request unavailable tools.
If, for instance, an LLM wants to use a tool but the tool is not available, the LLM can say something:
```text I need a tool that can retrieve the data from xxx app. Do you want me to go ahead
without the tool or you want to provide the tool to me?
```

== No Sub-Agent

I agree with this choice. Agents are agents, if an agent needs some agents for help, it can use them. 
They are agents. Nothing special about it. If we have sub-agents, can sub-agents act on their own?
If yes, what are the differences?

Some may argue that sub-agents are the ones that cannot be used on their own. They may be such
cases, but not common.

Pi  is a minimal AI engine. It gives users the power to extent it. 

== No Interruptions

Unlike Claude Code and similar coding assistants, pi does not prompt you for permissions to do something.
The reasons are that pi assumes that LLMs are not secure. You should run pi in a sandbox. Otherwise,
it may not be secure. 

When you want to use AI to automate your work, you better let AI work on their own, no interruptions.
The moment AI needs users' confirmation, it interrupts the whole process, losing the whole point of
automation.

== No Bash

Pi does not support bash. In tools like:

- Claude Code
- Gemini CLI
- Codex CLI

“Bash support” typically means: 'The LLM has a built-in tool that allows it to execute shell
commands programmatically'.

For example, the model can internally generate something like:

```bash
run_bash("ls -la")
run_bash("npm test")
```

The agent framework then:

- Executes the command
- Captures stdout/stderr
- Feeds the result back to the LLM
- Lets the LLM continue reasoning

So “Bash support” in this context really means:

An integrated shell execution tool controlled directly by the LLM.

== Extent

One of the most important features of pi is its extent or plugins. Extents are TypeScript code.

== Let pi Create Extents

This is another amazing feature of pi. You can ask pi to write new extents!

== Dialog Tree

Most AI dialogs are linear:
- You: a request
- AI: answer
- You: another request
- AI: answer
- ...

pi treats dialog as a tree. Each interaction has an `id` and `parent_id`. You can go back to any
point in the dialog. This is almost important for linear dialog: you can't time-travel your dialogs.
Either continue the current session or restart it. It is, of course, possible for you to reference
some interactions in the dialog, but the entire session is always presented to the LLM. There is no way
for you to control the dialog.

== Context Engineering

=== AGENTS.md

When pi starts, it looks for AGENTS.md in the following order:
```text
    ~/.pi/agent/AGENTS.md
    AGENTS.md in all its parent directories
    AGENTS.md in the current directory
```

All AGENTS.md, if found, are combined (not overridden), and serves as the system prompt.
This gives you the freedom of customize your system prompts.

*IMPORTANT* AGENTS.md in a directory should be specific.

=== SYSTEM.md

If you do not like the system prompt pi provides, you can write your own.
If you want to append additional information to pi's system prompt, you can write it
in APPEND_SYSTEM.md.

=== Dynamic Context

You can write extent to control your context.


=== Compress Context

pi will compress context automatically. The key is, however, is that you can write your own compression
algorithm, such as compress based on the topics, etc.

== Skills

pi does not require loading all skills.
```text
/skill:python
Please analyze the data in this directory
```

== Modes

pi supports four modes:
- Interactive Mode
- Print/JSON Mode: `pi -p <query>`
- RPC Mode: `pi --mode rpc`
- SDK Mode

= The Third Era of AI Software Development

#let a_002 = link(
  "https://github.com/TurixAI/TuriX-CUA"
)[#text(fill: blue)[article]]

Link: #a_002

Source: TouTiao

Run in a virtual machine, allow a developer to handle off a task and move on to something else.
Agents work through it over hours, iterating and testing until it is confident in the output,
and returns with something quickly reviewable: logs, video recordings, and live previews rather than diffs.

Keywords:
- More autonomous
- Self iterations
- More goal-oriented
