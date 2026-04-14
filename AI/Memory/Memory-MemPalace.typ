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
  [2026/04/12], [Created, file name: Memory-Hindsight.typ],
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
    "Diary-20260313"
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
  created: "2026/04/13",
  logical_name: "MemPalace",
  file_id: "2026041302",
  file_type: "Typst",
  keywords: ["Memory", "MemPalace"],
  source_url: "https://recca0120.github.io/en/2026/04/08/mempalace-ai-memory-system/",
  feed: "Wechat"
)

= Overview

LLMs are *stateless* — every session resets memory. Even if you dump notes into `CLAUDE.md` or expand context windows,
you hit two issues: context becomes bloated and expensive, retrieval becomes inefficient and noisy.

MemPalace tries to solve these problems by giving AI long-term memory without stuffing everything into the prompt ([recca0120][1])

== Core Idea

*1. Memory Hierarchy*
The system borrows from the *Method of Loci* (ancient memory technique): Humans remember by placing information in spatial
locations.

MemPalace applies this to AI. It constructs memory into a Memory Hierarchy:

- Wing: project / person / domain / topics. One wing per major category
- Room: sub-topic (auth, billing, etc.)
- Hall: memory type corridors shared across all wings:
  - hall_facts: locked-in decisions
  - hall_events - sessions and milestones 
  - hall_discoveries - breakthroughs
  - hall_preferences - habits and opinions
  - hall_advice - recommendations
- Closet: compressed summaries pointing to original content
- Drawer: full verbatim data, preserved losslessly
- Tunnel: cross-wing connections when the same room appears in multiple wings.

This is NOT just storage — it’s structured navigation of memory ([recca0120][1])

*2. Store Everything (Verbatim First)*

Unlike most systems (Mem0, RAG pipelines), it does not summarize aggressively, not decide “what’s important” upfront.
Instead, it store everything losslessly, then organize + retrieve later. This avoids losing reasoning trails and 
losing context behind decisions.

*Structure Improves Retrieval (Not Just Embeddings)*

Naive retrieval: ~60% recall, while structured (wing + room): ~94.8% recall. Focusing on structured retrieval improves
instead of purely reducing context sizes. Information Architecture Matters as much as Vector Search. ([recca0120][1])

*3. AAAK Compression (Key Innovation)*

This is a very important technique. It 'compresses' content in such a way that no decompression is need,
achieving ~30× compression but still readable by AI, preserving key structure. A long paragraph (~1000 tokens)
may be densed structured shorthand (~120 tokens) by AAAK. This enables store everything without exploding cost.

*4. Layered Memory Loading*

This directly addresses context windows. Instead of loading everything, MemPalace loads L0/L1 only at startup
(~170 tokens). Deeper memory loaded on demand.

Example:

Original (~1,000 tokens):
```text
Priya manages Driftwood team: Kai (backend, 3 years), Soren (frontend),
Maya (infrastructure), Leo (junior, started last month). Building SaaS
analytics platform. Current sprint: auth migration to Clerk. Kai
recommended Clerk over Auth0 based on pricing and DX.
```

AAAK format (~120 tokens):
```text
TEAM: PRI(lead) | KAI(backend,3yr) SOR(frontend) MAY(infra) LEO(junior,new)
PROJ: DRIFTWOOD(saas.analytics) | SPRINT: auth.migration→clerk
DECISION: KAI.rec:clerk>auth0(pricing+dx) | ★★★★
```

*5. Layered Memory*
#table(
  columns: 4,
  align: left,
  [Layer], [Content], [Size], [When Loaded],
  [L0], [Identity — who is this AI	], [~50 tokens], [Always],
  [L1], [Critical facts — team, projects, preferences	], [~120 tokens (AAAK)	], [Always],
  [L2], [Room recall — recent sessions	], [On demand	], [When topic surfaces],
  [L3], [Deep search — semantic across all closets	], [On demand	], [When explicitly asked]
)

Startup loads only L0 and L1.

*6. Knowledge Graph with Time Awareness*

MemPalace stores memory in SQLite with timestamps. Every fact has a validity window.
Invalidation marks end dates without deletion.
Facts in MemPalace can thus expire automatically, which means memory is not static; it evolves over time. 
This is important because user preferences change, project decisions get outdated, etc. Memory becomes temporal
and dynamic, not just stored text in MemPalace ([recca0120][1]).

== Integration with Agent Systems

We can integrate MemPalace through MCP server:
```text
claude mcp add mempalace -- python -m mempalace.mcp_server
```

Once installed, Claude Code auto-discovers 19 MCP tools covering search, storage, knowledge graph queries,
and agent diaries.
The system is not standalone—it integrates with agent workflows:

- MCP (Model Context Protocol) server
- Auto-save hooks (capture conversations automatically)

After that, Claude Code can see MemPalace’s MCP tools at session start, because Claude Code loads MCP servers as part
of its extension layer. Anthropic’s docs describe MCP as the feature that “connects Claude to external services and tools,” 
while `CLAUDE.md` is separate and provides “persistent context Claude sees every session.” ([Claude][1])

After adding the MemPalace (MCP server), Claude Code will *auto-discover the MemPalace tools*, but that does *not* mean it
will blindly use them on every turn. The MemPalace article says Claude Code “auto-discovers 19 MCP tools” after installation,
and Anthropic’s docs say MCP tool names load at session start, with full schemas deferred until use. That means MemPalace 
becomes an available capability inside Claude Code’s tool universe ([recca0120][2]) so that Claude Code may use it when
relevant. Whether it actually uses it depends on the task, prompt, and any instructions or hooks you set up.

Claude Code’s built-in persistent project memory is still `CLAUDE.md`. Anthropic’s docs are explicit: `CLAUDE.md`
loads every session automatically and provides always-on context; MCP is a different mechanism for external services
and tools. ([Claude][1]). So enabling MemPalace does not mean `CLAUDE.md` is disabled, nor Claude Code’s native
conventions/context mechanism disappears.

Instead, there will be two different memory-ish layers: Claude Code's memory system and MemPalace via MCP external,
queryable, structured memory tools for search/storage/retrieval across sessions. ([MemPalace.tech][3])

How will Claude Code use MemPalace? In many cases, Claude Code may use MemPalace
to find more 'memory' to enrich its own memory. Claude Code may use those tools when relevant, but availability is
not the same as guaranteed usage on every turn. ([Claude][1])

Practically:
- keep *stable project conventions* in `CLAUDE.md`
- keep *long-term, evolving, cross-session history* in MemPalace
- optionally add one small line in `CLAUDE.md` telling Claude to consult MemPalace for prior decisions/history when relevant

Whether it is a plus or minus using MemPalace is more an art. We need to test it and benchmark it.

[1]: https://code.claude.com/docs/en/features-overview "Extend Claude Code - Claude Code Docs"
[2]: https://recca0120.github.io/en/2026/04/08/mempalace-ai-memory-system/ "MemPalace: 170 Tokens to Recall Everything — A Long-Term Memory System for AI Agents"
[3]: https://www.mempalace.tech/blog/add-memory-to-claude-code "How to Add Persistent Memory to Claude Code (2026 Guide) | MemPalace.tech"


Memory is continuously updated without user intervention

== Specialist Agents

The system includes:

* agents that manage memory
* agents that retrieve / organize / compress

== Comparison to CLAUDE.md Approach

CLAUDE.md puts everything in one file, grows indefinitely and possibly pollutes context window. 
MemPalace uses structured storage, query-based retrieval, and minimal startup tokens to avoid these problems.

== MemPalace and SemOS

MemPalace is a local, structured, lossless long-term memory system that replaces prompt-based context with a navigable
memory architecture optimized for retrieval, compression, and persistence.

Structured (or layered) memory organization is very important.

- Filesystem → wings / rooms
- Database → ChromaDB + SQLite
- Compression → AAAK
- Retrieval → semantic + structural
- Agents → maintain + query memory

= References

[1]: https://recca0120.github.io/en/2026/04/08/mempalace-ai-memory-system/?utm_source=chatgpt.com "MemPalace: 170 Tokens to Recall Everything — A Long ..."

[2]: https://vectorize.io/articles/what-is-mempalace?utm_source=chatgpt.com "What Is MemPalace? AI Memory System Explained - Vectorize"

