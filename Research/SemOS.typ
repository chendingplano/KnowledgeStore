#import "@preview/diagraph:0.3.6"
#import "@preview/oxdraw:0.1.0": *

#set heading(numbering: "1.")
#set quote(block: true)
#show quote: set pad(x: 1em)
#show raw.where(block: true): block.with(fill: luma(240), inset: 1em, radius: 0.5em, width: 100%)

#set page(numbering: "i")
#counter(page).update(1)

= Table of Contents
#outline()
#pagebreak()

*Change History*
#table(
  columns: 2,
  align: left,
  [Date], [Remarks],
  [2026/05/18], [file name: CodingAssistants.typ],
)

#pagebreak()

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
    "Ontology"
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

#show heading.where(level: 4): set text(size: 12pt)
#show heading.where(level: 4): it => pad(top: 4pt, it)

#set page(numbering: "1")
#counter(page).update(1)
#counter(heading).update(0)

#let frontmatter = (
  created: "2026/05/18",
  logical_name: "Coding Assistant",
  file_id: "2026051802",
  file_type: "Typst",
  content_type: "Research",
  doc_time: "2026/05/18",
  keywords: ["Coding Assistant", "Harness"],
)

= ZeroStack

#let a_001 = link(
  "https://crates.io/crates/zerostack/1.0.0"
)[#text(fill: blue)[OntoFlow]]

#a_001 \
Date: 2026/05/18\
Source: Hacker News

This is a small open-source project, inspired by `pi` and `opencode`, written in Rust.

*Status*

Not installed yet.

= DeepSeek Reasonix
#let a_002 = link(
  "https://github.com/esengine/DeepSeek-Reasonix"
)[#text(fill: blue)[DeepSeek Reasonix GitHub]]

#a_002 \
Date: 2026/05/19 \
Source: WeChat

This is DeepSeek-native AI coding agent (terminal). The main feature is caching. It is not a
feature that you can turn on/off. It is an invariant the loop is designed around. This is DeepSeek-only. 
Every layer is tuned to the byte-stable prefix-cache mechanic.

Support Pro and Flash auto switch.

*Status*

Installed and works as expected.

= Edit with Hashlines
(refer to [1])

*Problems*
- Coding assistant uses staled content: Read a file, the file being modified by someone,
  the coding assistant then issues an edit call with staled content. This can lead errors.
- Fail matching: in order for the coding assistant to edit, it needs to tell the tool
  exactly which lines to edit. Some models use string exact match, some may use
  other mechanisms. In general, this is not reliable. Even a tiny change, such as
  spaces, indents, can lead to incorrect tool calls.

A coding model may understand exactly what code should change, yet fail to communicate 
the change through the editing tool. Existing tools commonly require one of two 
difficult formats.

*`str_replace`*

The model must provide the exact old text:

```json
{
  "old": "  if (user == null) {\n    return;\n  }",
  "new": "  if (!user) {\n    throw new Error(...);\n  }"
}
```

This can fail because of:

- one wrong space;
- incorrect indentation;
- a missing comment;
- several identical matches;
- slightly outdated remembered content;
- quotation or escaping mistakes.

The agent has already read the code, but it must reproduce that code almost perfectly merely to 
identify what it wants changed. The article describes exact-string replacement failures as a 
major practical issue. ([Can.ac][1])

*Patch or diff formats*

With `apply_patch`, the model must produce a syntactically valid patch, including context markers 
and formatting conventions. A model can generate the correct replacement code but still fail 
because its patch is malformed or does not match the current file context. The article reports 
very high patch-failure rates for some models that were not well adapted to that particular 
patch dialect. ([Can.ac][1])

Hashlines give every observed line a compact identifier:

```text
120 4b|function calculateTotal(items) {
121 e1|  return items.reduce(...)
122 8d|}
```

The agent can say:

```text
replace 121:e1 with:
  return items.reduce(...) + tax;
```

It no longer has to:

- repeat the old line;
- preserve its whitespace;
- construct a valid unified diff;
- provide enough surrounding text to disambiguate the location.

The hash functions as a *compact, content-sensitive edit anchor*. The line number makes it easy to 
locate, while the hash confirms that the line still contains what the model saw. ([Can.ac][1])

To make this method work, the coding model needs to be 'smart'.
LLMs are generally smart enough to *understand the code despite the prefixes*, but it still 
needs to be *explicitly instructed about the hashline protocol*.

LLMs do not parse code exactly like a compiler. They process token sequences and infer structure. 
They have already encountered many similar representations:

```text
120: function calculateTotal(items) {
121:   return items.reduce(...)
122: }
```

as well as stack traces, diff markers, numbered source listings, GitHub review annotations, debugger 
output, and compiler diagnostics. Therefore, an extra prefix such as `120 4b|` usually does not 
seriously interfere with semantic understanding.

However, the harness needs to tell it something equivalent to:

```text
> File contents are displayed with line identifiers in the format `<line-number>:<hash>|<content>`.
> The identifiers are not part of the file.
> When editing, reference these identifiers using the edit tool.
> Do not include the identifiers in replacement content.
```

The edit tool schema might expose operations such as:

```json
{
  "path": "src/example.js",
  "operation": "replace",
  "start": "120:4b",
  "end": "122:8d",
  "content": "function calculateTotal(items) {\n  return items.reduce(...)\n}"
}
```

When the model edits, it references tags such as `2:f1`, ranges such as `1:a3` through `3:0e`, 
or insertion anchors such as “insert after `3:0e`.” That behavior presupposes that the tool 
definition or agent instructions explain what those tags mean. ([Can.ac][1])

Without instructions, the model might infer the convention, especially after seeing the tool 
schema, but its behavior would be unreliable. It could:

- copy hashes into the replacement code;
- use only the line number;
- call an ordinary string-replacement tool;
- reproduce the original lines instead of using identifiers;
- invent an unsupported syntax.

So the model has the cognitive ability to understand the notation, but the harness must establish 
the interface contract.

Coding agents usually receive descriptions similar to:

```text
Tool: edit_file

Source returned by read_file is prefixed with line anchors:

<line-number>:<hash>|<source text>

These anchors are display metadata and are not part of the file.

Use exact anchors from the latest read operation:
- replace one line: start_anchor
- replace a range: start_anchor and end_anchor
- insert: before_anchor or after_anchor

Replacement text must contain only actual source code.
```

And a structured schema:

```json
{
  "path": "string",
  "start_anchor": "string",
  "end_anchor": "string",
  "replacement": "string"
}
```

Performance will depend on prompt and schema quality. The harness should make four things unambiguous:

1. Hashes and line numbers are metadata, not source text.
2. The model must copy anchors exactly from the latest tool output.
3. Replacement content must not include prefixes.
4. An anchor mismatch means the file changed and should usually be reread.

= Reviews
== Cloudflare OS
#let a_003 = link(
  "https://blog.cloudflare.com/cloudflare-os/"
)[#text(fill: blue)[CloudFlare OS Web Site]]

#a_003 \
Source: HackerNews

Cloudflare OS is an AI platform, developed for developing AI apps.

- Agent workspace: A workspace combines agent sessions, persistent state, 
  outputs and files, resource access, and an isolated runtime where the 
  agent can write and run code.
- Interface: a chat interface. User asks Cloudflare, it uses company context,
  resources made available to it, the skills created for the company,
  search, filter, etc.
- Create docs, slides, and spreadsheets: virtually anything you want to create
- Create apps
- Run deterministic workflows
- Security: 
  - agents start with no access
  - Gatekeeps goven resources and actions: a gatekeeper is a service-specific worker 
    that sits between Cloudflare OS and an external service. It understands the 
    service's API, its resources, and the operations that can be performed on them.
  - Policy follows what the agent has seen: Controlling the initial read is not enough. Take, for example, the case where an agent reads a sensitive table in a data warehouse and uses it to produce a live dashboard. Sharing the dashboard must not become a way to share the table with people who could not access it directly.
- Every app is a Worker: when you ask your workspace to
  build an app, the agent writes two parts: Client code and Server code.
  The server is loaded on demand as a Dynamic Worker and instantiated
  as a Durable Object Facet. The facet gives the app its own SQLite
  database, separate from the Cloudflare OS runtime managing it. Dynamic
  Workers use lightweight V8 isolates, so every app can have its own 
  isolated runtime without needing a dedicated server or container
  sitting around.
- Shared the app
- Use any model: every inference call runs through Cloudflare AI Gateway,
  giving your organization one place to decide which models are available
  and which model should handle each job.
- Open source: Cloudflare OS open source.

== Zero-Mem
`Zero-Mem: Zero-Token Memory Operations for LLM Agents` addresses one of the 
major inefficiencies of today's LLM agents: almost every memory system repeatedly 
invokes an LLM to summarize conversations, extract facts, create memory records, 
or decide which memories to retrieve. Although these intermediate reasoning steps 
improve long-term memory, they incur substantial token costs, latency, and the 
risk of losing information through summarization. The paper asks a fundamental 
question: do memory operations require an LLM at all? The authors argue that they 
do not. Instead, they propose *Zero-Mem*, a framework in which every memory operation—except the final question answering step—is completely deterministic 
and consumes *zero LLM input/output tokens*. ([arXiv][1])

Rather than generating summaries or structured memories, Zero-Mem preserves the 
original interaction history as the authoritative record. It indexes these 
interactions using two complementary structures. The first is an *entity-context 
graph*, which connects entities, concepts, and their relationships across 
conversations, making it easy to retrieve semantically related information 
regardless of when it occurred. The second is a *temporal hierarchy*, 
which organizes conversations according to their chronological structure, preserving 
local conversational context, session state, and nearby interactions. When a user 
issues a query, the system dynamically balances these two views: graph traversal 
discovers semantically connected evidence, while temporal traversal reconstructs 
the surrounding conversational context. A deterministic calibration stage removes
conflicting evidence before the retrieved context is passed to a single LLM that 
generates the final answer. ([arXiv][1])

The most interesting contribution is philosophical as much as technical. Most 
existing agent memory systems—including frameworks such as Mem0, LightMem, LongMem, 
and many production agents—treat memory as another generative task: they ask an 
LLM to decide what to remember and later ask another LLM to decide what to 
retrieve. Zero-Mem instead treats memory as an *information retrieval and data
organization problem*, not a generation problem. The memory subsystem behaves much 
more like a search engine or database index than another language model. This 
avoids information loss caused by summarization, preserves complete provenance 
because all retrieved evidence comes directly from the original interaction traces, 
and makes the behavior substantially more deterministic and reproducible. ([arXiv][1])

Experimentally, Zero-Mem achieves competitive accuracy on long-memory and 
long-context question-answering benchmarks while eliminating all intermediate LLM 
calls. Using the same final answering model and identical context budget as 
competing methods, it reduces *memory-operation latency by 57.6%* relative to the 
fastest baseline because indexing, retrieval, graph traversal, and conflict resolution 
are entirely deterministic algorithms. Ablation studies show that both the entity 
graph and the temporal hierarchy contribute significantly, and that dynamically 
combining the two retrieval views performs better than relying on either one alone. 
The overall conclusion is that effective long-term agent memory does not 
require repeatedly asking an LLM to generate memory representations; carefully 
designed indexing structures and retrieval algorithms can perform the memory 
management, reserving the LLM solely for the final reasoning task. ([arXiv][1])

From the perspective of *SemOS* work, this paper is particularly interesting because 
its design philosophy closely matches the direction SemOS has been exploring. Instead 
of treating memory as generated summaries, Zero-Mem treats memory as *structured access 
to original artifacts*, using graph structures, hierarchical organization, 
deterministic retrieval, and evidence preservation. This is conceptually similar to 
the Virtual FS + BM25 + graph traversal + semantic retrieval architecture: the 
intelligence lies primarily in *how knowledge is organized and explored*, while the LLM 
is used only for synthesizing the final answer. The paper therefore provides empirical 
evidence supporting the idea that improving retrieval and knowledge organization may 
yield larger gains than adding additional LLM-based memory generation stages. ([arXiv][1])

[1]: https://arxiv.org/abs/2607.29377?utm_source=chatgpt.com "Zero-Mem: Zero-Token Memory Operations for LLM Agents"


= References
[1]  I Improved 15 LLMs at Coding in One Afternoon. Only the Harness Changed
https://blog.can.ac/2026/02/12/the-harness-problem/

