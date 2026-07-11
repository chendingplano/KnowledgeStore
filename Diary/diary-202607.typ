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
    "Diary - 2026/07"
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
  created: "2026/07/01",
  logical_name: "Diary-202607",
  file_id: "2026070101",
  file_type: "Typst",
  keywords: ["Diary"],
)

= 2026/07/02 - chartdb

#let a_001 = link(
  "https://github.com/chartdb/chartdb"
)[#text(fill: blue)[ChartDB]]

#a_001 \
Source: WeChat

This is an open-source pure TypeScript project that draws ER charts for databases.
We may integrate this open source to SemOS.

= 2026/07/02 - Skill Management
#let a_002 = link(
  "https://mp.weixin.qq.com/s/J_qkNulpWYDkKDaReM9QzQ?poc_token=HJRFRmqjrBMZIuuIcRdJpeljVKu5NGFaYlz-m_La"
)[#text(fill: blue)[Skill Management]]

#a_002 \
Source: WeChat

Main features:
- Skill repository
- Search
- Management
- Security
- Status Management
- Installation to Coding Agents
- Statistics on using/not using a specific skill
- Skill usage statistics
- Skill Room: each skill room is dedicated to a specific skill, showing how to use the skill, the effectiveness, etc.

#figure(
   image("Images/image_2026070201.png", width: 100%),
   caption: [Skill Platform (#a_002)],
)

= 2026/07/06 - Traefik
#let a_003 = link(
  "https://traefik.io/traefik"
)[#text(fill: blue)[Traefik]]

#a_003 \
Source: Jimmy

This is a replacement for Nginx.

= 2026/07/07 - Use Cheap Model to Filter RAG 
#let a_004 = link(
  "https://www.kapa.ai/blog/how-we-prune-rag-context"
)[#text(fill: blue)[How We Taught a Small LLM to Throw away 68% of RAG Context]]

#a_004 \
Source: Hacker News

There are two types of rerankers: (1) the reranker that fuses entries from two or more ordered lists
and (2) reranker that orders retrieved by LLMs. The former is pure reranker, while the latter
is more about relevance.

*Example*

We have always struggled over whether to use vector search. Here is an example:
- Question: Can I turn off audit log forwarding for just one project?"
- RAG 1: Audit log forwarding is toggled in org settings
- RAG 2: Projects cannot override org settings

Most rerankers may throw away RAG 2. If vector search is not used, it
won't be able to find it at all since it mentions none of the keywords.

The real question is: how to find RAG 2.

For agentic RAG, which I mean LLMs are the driver:
- Tool use: Find chunks related to 'Audit log'
- LLM analyze the chunks, trying to find out who controls the audit log.
  If there are too many results by 'audit log', the LLM may add more
  conditions: 'audit log', 'config/setting'.
- If the retrieved contains RAG 2, the LLM analyzes it and should be
  able to answer the question correctly.

I believe the true question is:
- Who should be in the driver seat: LLM or agent (or the apps we wrote)
- The budget: if it is a quick-and-dirty question/answering system, users
  care more about the latency than answer quality, a 1-3 turns may be
  the max. If it is a problem solving system, or a system whose missions
  are to solve user problems, regardless of the latency and the cost,
  the harness will be more resiliant to retrieval quality. LLMs can explore
  the knowledge base, possibly through multiple turns.

= 2026/07/09 - 
#let a_005 = link(
  "https://github.com/linuxrebel/DocuBrowser"
)[#text(fill: blue)[DocuBrowser URL]]

#a_005 \
Source: Hacker News

This is an open-source project, very similar to SemOS. It has GUI. Written in Python.

= 2026/07/13 - Harness Engineering

#let a_006 = link(
  "https://addyosmani.com/blog/agent-harness-engineering/"
)[#text(fill: blue)[Harness Engineering]]

#a_006 \
Source: Hacker News


#figure(
   image("Images/image_2026071301.png", width: 100%),
   caption: [#a_006],
)

Harness components:
- System prompts (CLAUDE.md, AGENTS.md, skill files, and subagent prompts)
- Tools, skills, MCP servers, and their descriptions
- Bundled infrastructure (filesystem, sandbox, browser)
- Orchestration logic (subagent spawning, handoffs, model routing)
- Hooks and middeware for deterministric execution (compaction, tininuation, lint checks)
- Observability (logs, traces, cost and latency metering)

== The Ratchet: Every Mistake Becomes a Rule

#quote(block: true, attribution:[#a_006])[
"The most important habit in harness engineering is treating agent mistakes as permanent signals. 
Not one-off stories to laugh about, not “bad runs” to retry. Signals.

If the agent ships a PR with a commented-out test and I merge it by accident, that’s an input. The next version of my AGENTS.md says “never comment out tests; delete them or fix them.” The next version of my pre-commit hook greps for .skip( and xit( in the diff. The next version of my reviewer subagent flags commented-out tests as a blocker.

You only add constraints when you’ve seen a real failure. You only remove them when a capable model has made them redundant. Every line in a good AGENTS.md should be traceable back to a specific thing that went wrong.

This is also why harness engineering is a discipline rather than a framework. The right harness for your codebase is shaped by your failure history. You can’t download it."
]

This suggests treating every errors seriously. Add them to the harness whenever appropriate. 

The lifecycle should be:

```text
failure observed
    ↓
temporary explicit instruction
    ↓
automated enforcement where possible
(i.e., burn it to the harness)
    ↓
instruction simplified or removed
```

The danger appears when every failure is permanently appended as another prose 
instruction. Then `AGENTS.md` becomes a long historical blacklist:

```text
never do X
never do Y
except when Z
unless A
but not in directory B
```

That creates many problems.

You do need rules. Each rule should have provenance:

```yaml
rule: Do not disable or comment out tests.
reason: An agent hid a failing test in PR #184.
enforcement:
  - pre-commit check
  - CI check
status: active
```

But the full incident history does not have to live in the 
model’s primary instruction file.

We could keep AGENTS.md as the compact, current operational contract, 
while maintaining a separate registry such as:

```text
docs/agent-harness/failure-rules.yaml
docs/agent-harness/decisions.md
```

for history, rationale, enforcement status, and removal criteria.

A scalable harness can use layers.

* 1. `AGENTS.md`*

Keep only high-value instructions the agent must reason about:

```markdown
## Tests

- Never disable, skip, or comment out a test to make a change pass.
- Fix the implementation or update the test only when behavior intentionally changes.
- Run the relevant test suite before declaring completion.
```

* 2. Automated enforcement*

Put mechanically detectable rules in tools:

```text
pre-commit
CI
linters
formatters
repository permissions
code generation checks
```

* 3. Scoped instructions*

Do not put every rule at repository root. Place specialized rules near the affected code:

```text
AGENTS.md
backend/AGENTS.md
frontend/AGENTS.md
migrations/AGENTS.md
generated/AGENTS.md
```

An agent working in `backend/` only needs the root rules plus the backend-specific rules.

* When should a rule remain in `AGENTS.md`?*

A rule belongs there when it requires judgment, context, or intent, such as:

- preserve backward compatibility unless the specification explicitly changes it;
- update the architecture document when changing component boundaries;
- use the repository’s existing abstraction instead of introducing a parallel one;
- do not silently weaken validation to make tests pass.

A rule should usually move to tooling when it is mechanically verifiable, such as:

- formatting;
- forbidden file patterns;
- skipped tests;
- generated-file drift;
- missing license headers;
- dependency constraints;
- schema conformance.

*Rule removal*

You only remove things in AGENTS.md when
- a capable model has made them redundant.
- tooling now enforces it;
- the architecture makes the failure impossible;
- the repository no longer uses the relevant technology;
- the rule has been incorporated into a more general invariant;
- current models reliably follow a standard convention without explicit instruction.

So rules need an explicit maintenance process, not only accumulation.

A useful policy is:

```text
Add narrowly.
Generalize carefully.
Automate whenever possible.
Scope locally.
Review periodically.
Remove aggressively when redundant.
```

A mature harness should become *more capable over time*, but its primary instructions 
should ideally remain compact, coherent, and high-signal.

== Failure History

The failure history is a durable, queryable memory of prior agent failures, their causes, 
and the controls introduced afterward. It does not need to be loaded into every prompt. 
Instead, the harness can retrieve relevant entries when a task touches the affected area.

A registry entry might contain:

```yaml
id: HR-017
failure_type: disabled_test
summary: Agent commented out a failing integration test.
context:
  repository: semos
  subsystem: metrics-extraction
  files:
    - internal/extract/metrics_test.go
cause: Agent optimized for passing CI instead of preserving test coverage.
invariant: Never disable or remove a test merely to make CI pass.
controls:
  - type: instruction
    location: AGENTS.md
  - type: pre_commit
    rule: reject skipped or commented-out tests
  - type: reviewer
    rule: flag test suppression
evidence:
  pull_request: 184
  commit: abc123
status: active
tags:
  - testing
  - ci
  - regression
```

Then the harness can expose tools such as:

```text
search_failures(query, repository, subsystem, files, tags)
get_failure(id)
find_controls_for_failure(id)
find_failures_related_to_diff(diff)
```

Before or during a task, the harness could search using:

- files being modified;
- subsystem or package;
- task intent;
- tools being invoked;
- recent diff contents;
- detected risk patterns.

For example, if an agent edits `metrics_test.go`, the harness might retrieve 
failures tagged with `testing`, `metrics-extraction`, or related paths and 
inject only the relevant lessons:

```text
Relevant prior failure:
An earlier change disabled a failing integration test to make CI pass.
Do not skip, comment out, or weaken tests. Fix the implementation or
explicitly justify an intended behavior change.
```

This is essentially *Retrieval-Augmented Harness Memory*.

Failure history can be stored in files, database, and Git. They serve different purposes,
not mutually exclusive.

*Git-tracked files* are good for reviewability and provenance:

```text
.agent/failures/HR-017.yaml
.agent/failures/index.yaml
```

Benefits include:

- changes are reviewed in pull requests;
- every rule has commit history;
- failures evolve alongside the codebase;
- branches can carry different harness state.

A database is better when the registry becomes large or spans many repositories:

- structured filtering;
- full-text and semantic search;
- analytics;
- deduplication;
- cross-project retrieval;
- recording repeated occurrences.

Git can remain the source of truth while the database acts as an index.

A practical architecture is:

```text
Git-tracked failure records
        ↓
indexing pipeline
        ↓
BM25 + metadata + vector index
        ↓
harness retrieval tool
        ↓
small task-specific context
```

*Important Distinction*

The failure history should not merely store stories about failures. 
It should store *operationally reusable knowledge*:

```text
incident
cause
generalized invariant
affected scope
detection method
preventive control
evidence
status
removal criteria
```

Otherwise retrieval may return anecdotes that are difficult for the model to apply.

For instance:

```text
Bad:
Agent broke tests in PR #184.
```

```text
Better:
When modifying metrics extraction, do not relax assertions or skip tests
to accommodate nondeterministic LLM output. Normalize the output or use
bounded assertions. Applies to internal/extract/**.
```

The second form is directly actionable.

*Retrieval should usually be automatic*

It is useful to expose a tool that the model can call, but relying entirely on 
the model to decide when to call it creates another probabilistic failure point.

A stronger harness combines both:

```text
automatic retrieval:
    based on task, paths, diff, subsystem, and risk signals

agent-initiated retrieval:
    when the agent encounters uncertainty or recognizes a related pattern
```

For high-risk operations, retrieval can be mandatory. For example:

```text
Before changing migrations, authentication, billing, schema generation,
or test infrastructure, retrieve related failure records.
```

*Avoid injecting too much history*

The history can grow indefinitely because it is storage, not prompt context. 
The retrieval layer should return only a few high-relevance items and preferably 
synthesize them into current constraints.

A good pipeline is:

```text
retrieve candidate failures
    ↓
rank by path + subsystem + task + recency + severity
    ↓
deduplicate similar failures
    ↓
extract current active lessons
    ↓
inject 3–10 concise constraints
```

The agent usually does not need the complete incident record 
unless it is diagnosing a difficult issue.

*Relation to `AGENTS.md`*

This suggests a three-tier model:

```text
AGENTS.md
    Stable, universal, high-value rules.

Scoped AGENTS.md files
    Rules for a subsystem or directory.

Failure history
    Long-tail history, rationale, evidence, and situational lessons
    retrieved only when relevant.
```

Some frequently retrieved failure lessons may be promoted into `AGENTS.md`. 
Others may remain in the history. Mechanically enforceable lessons should 
become CI, lint, hooks, or permissions.

So the registry is not merely an archive. It is a *learning memory layer for 
the harness*, with retrieval connecting historical failures to current work.

= 2026/07/13 - Benchmark on Extracting Artifacts
The real challenge is how to design the benchmark. 

== Method 1 - Manual Extract
We can manually extract artifacts from a known document. This works when we modify
the system, especially the prompts or change models. 

The problem is: how to be sure we are good at extracting artifacts from future
unknown documents.

