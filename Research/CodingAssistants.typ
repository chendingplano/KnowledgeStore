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

= References
[1]  I Improved 15 LLMs at Coding in One Afternoon. Only the Harness Changed
https://blog.can.ac/2026/02/12/the-harness-problem/

