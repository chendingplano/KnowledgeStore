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
    "Reading-20260302"
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

= Microgpt

#let a_001 = link(
  "https://karpathy.github.io/2026/02/12/microgpt/"
)[#text(fill: blue)[article]]

Link: #a_001

Source: Hacker News

GitHub: https://gist.github.com/karpathy/8627fe009c40f57531cb18360106ce95

Author: Andrej Karpathy

Karpathy wrote a Python code, about 200 lines, that trains and inferences like ChatGPT.

Someone even created a HTML: The Art of GPT (https://nanshu.wang/the-art-of-gpt/microgpt.html)

A 'GPT' has:
- Dataset
- Tokenizer
- Autograd
- Parameters
- Embeddings
- Attention
- MLP (Multilayer Perceptron)
- Training
- Optimization
- Post-training
- Inference

Almost all LLMs are enlarged version of Microgpt.

= Qwen 3.5 Medium Models

#let a_002 = link(
  "https://venturebeat.com/technology/alibabas-new-open-source-qwen3-5-medium-models-offer-sonnet-4-5-performance"
)[#text(fill: blue)[article]]

Link: #a_002

Source: Hacker News

Alibaba Qwen medium size models:
- Qwen3.5-35B-A3B
- Qwen3.5-122B-A10B
- Qwen3.5-27B

= Claude Code's Marketplace and Plugins

Source: ChatGPT

== What is Claude Code Plugin System

Claude Code (Anthropic’s AI-powered coding assistant) lets you extend its functionality with
reusable add-ons. These add-ons can include:

- Slash commands (e.g., /review)
- Agents (specialized AI helpers)
- Hooks (scripts triggered by events)
- MCP servers (connections to external services/tooling)
- Skills (custom scripted behaviors)

These add-ons are packaged as plugins.

== Plugins

A Plugin is a self-contained extension for Claude Code. It lives in a Git repository
(or a local directory) and tells Claude Code:

- What it does (name, version, description)
- What features it contains (commands, agents, skills, etc.)

Technically, a plugin has its own manifest file:

```text
plugin.json
```

This file inside the plugin directory describes that plugin.

When you install a plugin in Claude Code, it makes the features
in that plugin available in your coding session.

== Marketplace

A Marketplace is like a catalog of plugins.

It’s essentially a JSON file (named marketplace.json) that lives at the root of
a repository and lists multiple plugins — each with metadata like name, source
location, version, and description.

Example structure (written by Claude Docs):
```json
{
  "name": "my-plugins",
  "owner": {"name": "Your Name"},
  "plugins": [
    {
      "name": "review-plugin",
      "source": "./plugins/review-plugin",
      "description": "Adds a /review skill"
    }
  ]
}
```

This file tells Claude Code which plugins are part of this “marketplace” and where to find them.

So a marketplace repository is not just one plugin — it’s a list of plugins that you can
discover and install.

== Install and Add

```bash
/plugin marketplace add <repo>
/plugin install <plugin-name>@<marketplace-name>
```
