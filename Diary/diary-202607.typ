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

#a_004 23\
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

= 2026/07/14 - Six AI Orchastration Types
#let a_007 = link(
  "https://dzone.com/articles/ai-orchestration-types"
)[#text(fill: blue)[Six AI Orchastration Types]]

#a_007 \
Source: dzone

- Workflow Orchastration: our doc processor pipeline is the workflow orchastration. 
  I don't feel this is an AI orchastration. It is true that every doc processor
  uses LLM. But this is just software orchastration.
- Agent Orchestration: this is true AI orchastration. It appears that this overlaps
  with workflow orchastration. In SemOS, we use pipelines to organize doc processors.
  Each doc process can be considered an agent. This is thus agent orchastration.
- Model Orchestration: there are two types of model orchestration: dynamic and static.
  SemOS statically configures which model to use for doc processors and its
  backfill models. This is static model orchestration. Dynamic orchestration
  is more advanced, but it requires a model to determine the complexity of
  agents. A Japanese start-up: Fugu, uses a small model as the agent orchastration.
- Resource Orchestration: manage GPU/TPU scheduling, load balancing,
  and cost optimization across distributed AI infrastructure. 
- Data Orchestration: manage ETL pipelines and coordinates information flow
  between systems so AI receives clean, timely, correctly formatted data.
  My understanding is that data orchestration should also control which data
  to include in a conversation or for an agent. It may also have the ability
  to dynamically determine whether the current knowledge base is good, complete,
  whether new sources of data are needed, whether we need to extract new
  artifacts, whether we need new relations. Another direction is ontology,
  such as business terms, common terms, definitions, etc.
- Service Orchestration: integrate multiple AI services and APIs - internal and third-party -
  into sophisticated applications that deliver compounding values. Again,
  I don't think this is specific for AI orchestration. It is normal software
  orchestration. In SemOS, we have PDF parser (in Python), File Converter (Go),
  and Doc Processor (Go) services. PDF parser and file converter does not
  use LLMs (normal services), while doc processor does (agent).

= 2026/07/14 - Parquet vs Lance: How Storage Layout Changes the Read Path
#let a_008 = link(
  "https://dzone.com/articles/parquet-vs-lance-how-storage-layout-changes-the-re-1"
)[#text(fill: blue)[Parquet vs Lance]]

#let a_009 = link(
  "https://arxiv.org/pdf/2504.15247"
)[#text(fill: blue)[Lance Arxiv Paper]]

#let a_010 = link(
  "https://maxnilz.com/papers/Lance%20Efficient%20Random%20Access%20in%20Columnar%20Storage%20through%20Adaptive%20Structural%20Encodings.pdf?utm_source=chatgpt.com"
)[#text(fill: blue)[Lance: Efficient Random Access in Columnar Storage through Adaptive Structural Encodings]]

#a_008 \
#a_009 \
Source: dzone

Parquet is good at large datasets, while Lance (#a_009) focuses on:
- full-text search
- Semantic search
- RAG

Lance addresses an increasingly important problem in AI data infrastructure: traditional 
columnar storage formats (especially Apache Parquet) were designed for analytical scans, 
whereas modern AI workloads—vector search, RAG, feature retrieval, multimodal datasets, 
and embedding stores—require both high-throughput sequential scans and extremely efficient 
random access. The authors argue that with modern NVMe SSDs, random access is no longer 
fundamentally limited by hardware; instead, the primary bottleneck is how columnar file 
formats encode structural metadata such as nested arrays, null values, and repetition 
information. (#a_009)

The central contribution of the paper is introducing *structural encoding* as a first-class 
design concern. The authors distinguish it from traditional compression: compression focuses 
on reducing data size, while structural encoding determines how nested data is organized 
into buffers, how many I/O operations are required to retrieve an individual value, and 
how much unnecessary data must be read (read amplification). Through detailed analysis of 
Apache Arrow, Apache Parquet, and their own Lance format, they demonstrate that structural 
encoding has a much larger effect on random-access latency than previously appreciated. 
They also show that simply configuring Parquet differently can improve random-access 
performance by more than 60× compared to its default configuration, although this comes 
with trade-offs in scan speed and memory consumption. (#a_009)

Building on these observations, the paper presents the *Lance structural encoding scheme*, 
which adaptively switches between two encoding strategies depending on the characteristics 
of the data. Large fixed-width objects (such as vector embeddings) use a "full-zip" encoding 
optimized for direct access without maintaining large in-memory indexes, while smaller and 
variable-width data use a "miniblock" encoding that balances locality and scan efficiency. 
This adaptive design allows Lance to achieve near-optimal random access while preserving 
full-scan performance and avoiding the large RAM overhead required by Parquet's page indexes. 
The design also introduces practical improvements such as more efficient handling of nested 
lists, packed structs, and reduced search-cache requirements. (#a_010)

The significance of this work extends beyond a new file format. The paper argues that 
future AI data systems should optimize storage simultaneously for analytics and retrieval 
rather than treating them as separate workloads. This is particularly relevant for vector 
databases, RAG systems, feature stores, and multimodal datasets, where retrieving a small 
subset of rows efficiently is often as important as scanning entire datasets. Instead of 
proposing a fundamentally new storage architecture, the authors show that careful redesign 
of low-level structural encoding can substantially improve performance while remaining 
compatible with modern cloud object storage and NVMe-based infrastructure. They conclude 
that both Parquet and Lance still have room for improvement, but Lance's adaptive structural 
encoding offers a more flexible foundation for AI-oriented storage systems. (#a_009)

*Row Groups*\
This is similar to buckets in JimoDB. A row group consists of a block of tabular data.
A file may contain multiple row groups. This is different from JimoDB, where a data
object is created per field per bucket. Data objects are read-only and appended to 
physical files.

One issue with JimoDB's approach is that most formats (columnar) organize 'data objects'
based on columns, which means that the data objects of the same column are stored
in the same file. I am not sure whether this is critical. Let's assume we want to scan
a column and the total size of all the data objects for the column is 10 GB. Apparently,
we should not read the entire file into memory in one call, not just because of the
file size, but the memory usage, read efficiency, etc.

Instead, we want to read the 10 GB file by 'chunks', one chunk at a time. When reading
chunks, I am not sure whether it is critical whether the chunks of the same column are
stored in the same physical file or not.

But one thing JimoDB misses is a Column Header. Various information can be stored
in Column Headers, such as:
- min and max values per bucket
- value bitmap per bucket 
- value list per bucket
- [value, bucket-list]: present for small cardilarity columns. List only
  the pairs where the bucket list is much smaller than the total number of buckets.
  Note that the buckets can be identified very efficiently since buckets
  can be viewed as arrays: buckets[idx], such as buckets[0], buckets[1], ...
  Bucket lists can be a bitmap of the index.
- And so on.

Column headers should play a critical role in reading/scanning data
if the reading/scanning is 'selective'.

Another thinking is about object IDs and keys. These are high cardilality
columns. It will be very efficient in reading if we can organize the values
in such a way that we can easily determine the buckets by looking at the values.

= 2026/07/16 - Agent Loop
#let a_011 = link(
  "https://www.bobbytables.io/p/the-agentic-loop-three-loops-in-a"
)[#text(fill: blue)[Agent Loop]]

#a_011\
Source: Hacker News

There are actually not just one loop, but three:
- Inference Loop
- Tool Loop
- Human Loop

The most important, also the outer loop, is the inference loop. This is
the 'heart' of the entire engine. LLMs use this loop to think-action,
repeatly, until the goal is achieved.

During the think-action loop (the reference loop), 

= 2026/07/17 - Toward Harness that Can Do Anything
#let a_012 = link(
  "https://eardatasci.github.io/c/ambiance/index.html"
)[#text(fill: blue)[Generic Harness]]

#a_012 \
Source: Hacker News

#quote(block: true, attribution:[Ritchie and Thompson])[
- Write programs that do one thing and do it well. To do a new job, build afresh rather than complicate old programs by adding new "features".
- Write programs to work together. Expect the output of every program to be the input for another program.
- Write programs to handle text streams, because that is a universal interface.
]

*Characteristics of Agent Harness*
- Determinism as much as possible. The LLM should choose what goal to pursue,
  but the deliberation towards that goal should be well-defined or at least
  a collection of well-defined steps.
- The core prompt should be as small as possible, and the LLM should then
  choose what skills to load into context at runtime.
- LLMs start going crazy as you approach context limits.
- A good harness MUST make use of the a priori coding knowledge of the LLM.
  Wrangling it through a novel one ultimately wastes tokens.
- A good harness makes delegation easy and efficient (tool use, or to other agents).
- A harness should feel light to the LLM, but actually do a lot of things in 
  the background, including logging, sanity checks, failsafes, sanitizations, etc.
- Should handle LLM failures
- Great logging and clear error message.
- Write modular, transparent tools that do one thing and do it well. 
  Ensure they fail loadly.
- Write tools, skills, and connectors that work together.
- Skills dictate workflows.
- Tools are the means to execute them.
- Connectors are the data which the Agent manipulates.
- Text streams are a universal interface, and a Language Model has home-court
  advantage. Everything should be a flat text file.
- Evertying is a File
- APIs should be simple.
- Avoid heavy curls
- Avoid complicated regex
- Whenever dealing with external data sources, your harness should perform
  whatever manipulation might be necessary to clean it up before it reaches the LLMs.
- Categorizing everything into directories, you can save your Agent a lot of tokens.
- Consider the Filesystem Hierarchy Standard (FHS)
- LLMs are experts at navigating the Linux FS.
- LLMs are experts at common Linux commands, such as grep, git, etc.
- Consider putting logs, a lot of them, in logs
- A heartbeat turns a harness to a live animal
- A full agent turn on a fixed interval (30 minutes by default) to check
  whether anything needs attention, like file changes, external state, etc.
- Pair each event with prompts that are specific to the event, such as doc processors.
- Clear separate harness-level logic, agent (doc processors, doc reviewers) logic, 
  workflow (doc processor service) logic, event logic
- Users: three types: `root`, which handles all system-level stuff,
  `pai`, which is the human-facing LLM that actually interacts with the outside world,
  `librarian`, which journals what `pai` is good at, what it is bad at, and what
  the system did for the day.
- There shall be three loops (refer to #a_011)

*References*:\
GitHub: https://github.com/whitematterlabs/ambiance

= 2026/07/18 - 40x Faster than Binrary Search
#let a_013 = link(
  "https://curiouscoding.nl/posts/static-search-tree/"
)[40x Faster than Binary Search]

#a_013 \
Source: Hacker News
Keywords: [Binary Search, S-Tree, S+Tree]

It uses the algorithm introduced by Algorithmica.

= 2026/07/18 - Ploy
#let a_014 = link(
  "https://ploy.ai/"
)[Ploy Website]

#a_014 \
Source: Hacker News

Ploy is the marketing platform that turns your website into your company's growth engine.

*Your website launched, then stopped*!
- Monitor
- Act
- Surface

We should learn from this website: let the LLM work 24 hours for us.

= 2026/07/19 - Harness Engineering
#let a_015 = link(
  "https://github.com/lopopolo/harness-engineering/tree/trunk"
)[#text(fill: blue)[Harness Engineering]]

#a_015 \
Source: Hacker News

This repository is a structured *knowledge base and field guide for harness engineering*, rather 
than a software framework or executable agent harness. It defines harness engineering as 
improving an agent’s performance while holding the model and coding agent relatively constant, 
then changing the external environment around them: context, tools, permissions, examples, 
tests, and feedback mechanisms. The objective is to help an agent recover the real intent of 
a task, operate the actual system, respect organizational authority, prove that the outcome 
works, and leave the environment better prepared for future runs.

A central argument is that general model weights do not contain an organization’s private 
and continuously changing “process data”: its current operational state, local terminology, 
quality standards, procedures, exception history, and authority relationships. The harness 
must expose this information through retrievable repository context and usable tools. It 
also carries nonfunctional requirements—reliability, security, compatibility, performance, 
maintainability, operability, and risk posture—so that these constraints become concrete 
examples, types, tests, policies, and executable checks rather than depending on an agent 
to infer them from a prompt.

The repository organizes this philosophy into twelve theses. These include holding the 
worker constant while evaluating the harness; routing context just in time instead of 
loading everything into the prompt; giving one primary agent ownership of the whole 
job; making tools discoverable and interpretable; separating capability from authority; 
verifying claims in the real environment; converting feedback and failures into durable 
infrastructure; and optimizing for accepted outcomes rather than token counts, lines 
of code, or number of agents. Of particular relevance to SemOS is its distinction 
between a *large navigable knowledge store* and a *small active working set*, with 
root instructions routing the agent to authoritative sources only when an unresolved 
decision requires them.

The repository itself demonstrates this routing model through `AGENTS.md`. An agent 
first examines the target repository’s own architecture, instructions, tools, tests, 
permissions, history, and precedents. It then identifies the specific decision that 
remains unresolved and loads only the relevant thesis—for example, tool legibility, 
authority, proof, domain modeling, feedback, or continuous maintenance. Target-local 
truth always takes precedence over the general guidance. This is a significant design 
point: the repository is not intended to be copied as a standard directory layout 
or universal policy set; it is intended to sharpen decisions within another system’s 
existing contracts.

Finally, it includes practical playbooks for improving one bounded agent workflow, 
reviewing an entire repository, and evaluating a harness through controlled 
comparisons. These procedures encourage observing representative trajectories, 
locating the earliest failed handoff, applying the smallest reversible intervention 
at the correct ownership boundary, and rerunning the job to determine whether 
the change genuinely improved the outcome. The maintainers explicitly describe 
the playbooks as editorial syntheses rather than fully validated methodologies, 
so the repository is best understood as a carefully sourced and agent-readable 
body of engineering arguments, patterns, and experimental procedures—not a 
production-ready harness package.

= 2026/07/21 - Agent Harness Engineering

"Roughly: anytime you find an agent makes a mistake, you take the time to engineer a solution such that the agent never makes that mistake again."

"The rest is the harness: the prompts, tools, context policies, hooks, sandboxes, subagents, feedback loops, and recovery paths wrapped around the model so it can actually finish something."

"A decent model with a great harness beats a great model with a bad harness."

= 2026/07/22 - Search Is Becoming the Control Plane for AI
#let a_016 = link(
  "https://dzone.com/articles/ai-agent-search"
)[#text(fill: blue)[Search Is the Control Plane]]

#a_016 \
Source: dzone

Search is no longer simply about people finding information. Agents need to locate resources, services, etc. Listing all the tools to LLMs becomes impractical unless we give it a Search tool.

REST APIs are designed for human developers, but the agent requires something else - APIs that self-explain, can be discovered at runtime, and communicate their purpose in a language that is already understood by the model.

This is the issue search is meant to solve. Not keyword search, semantic search

== Actions 
1. Expose Internal Tools as MCP Servers
If your team has internal APIs, databases, or services that your agents will ever need to access — wrap them in MCP now. Provide well-crafted descriptions of each tool in natural language. This is what most teams miss out on and then kick themselves later for. The key to finding the tool is the quality of its description.

2. Create a Tool Catalog, Not a Tool List
Don't explicitly include tool arrays in your agent configuration. Create an indexable catalog, even a basic vector index of your tools' descriptions. It is queried by your agent at the beginning of every task, and only loads what is needed. This alone will reduce the amount of context bloat and make your agent a much better agent at novel tasks for which it wasn't explicitly trained.

3. Avoid SERP APIs, Stick to AI Native Search APIs for External Data
In the event that your agent has to fetch external information, Exa, Tavily, and Firecrawl are designed for that purpose. They send back information that agents can read. Typical search engines provide HTML-ranked results for human readers. The impact that your agent can have with what it produces is huge.

4. Keep Discovery and Invocation Apart in the Design of Your System
They are two different operations that have distinct performance needs. Discovery (finding the correct tool) should be quick, stored in a cache, and be semantic. Invocation (literally the calling of) must be reliable and have error handling. If they are combined, their systems are slow at both. Do not mix them until day 1.

5. Pay Attention to the A2A and ANP Protocols
MCP resolves the tool discovery issue. A2A and ANP are a solution to the agent discovery problem, which involves finding the agent to which another agent can delegate. This is the next component of the same issue. Your orchestrator agent should be able to find its agent of choice, not be hard-coded with a list of agents that it knows about. That infrastructure is being developed today.

= 2026/07/26 - Calamine
#let a_017 = link(
  "https://docs.rs/calamine/latest/calamine/"
)[#text(fill: blue)[Calamine Excel]]

#a_017 \
Source: Hacker News

This is a tool to read Excel, written in Rust. High performance.

= 2026/07/26 - Wigolo
#let a_018 = link(
  "https://github.com/chendingplano/wigolo.git"
)[#text(fill: blue)[Wigolo - Open-Source Web Search]]

#a_018 \
Source: WeChat

wigolo gives an AI agent one surface for everything web-related: search, fetch, crawl, 
extract, cache, find-similar, research, and autonomous gather loops. It runs wherever 
your agent runs — as an MCP server next to your coding agent, as a REST/MCP endpoint 
on the box where your self-hosted agents live, or embedded through an SDK inside your 
own app. The core tools need no API keys, nothing it touches leaves ~/.wigolo/, and 
no bill grows with how much your agent thinks.

= 2026/07/26 - Self-Harness
#let a_019 = link(
  "https://summarizepaper.com/en/arxiv-id/2606.09498v1/?utm_source=chatgpt.com"
)[#text(fill: blue)[AI-Powered Paper Summarization about the arXiv paper 2606.09498v1]]

This paper, *"Self-Harness: Harnesses That Improve Themselves"*, argues that the performance 
of an LLM-based agent depends not only on the underlying foundation model but also on its 
*harness*—the surrounding runtime system including prompts, tool usage, memory, execution 
policies, error recovery, and other orchestration logic. Today these harnesses are almost 
entirely designed manually by humans. The authors argue that this approach does not scale 
because every new model has different strengths and weaknesses, requiring continual human 
tuning. Instead, they propose *Self-Harness*, a framework in which an agent autonomously 
improves its own harness without assistance from human engineers or stronger 
models. (#a_019 [SummarizePaper][1])

The proposed framework consists of a three-stage iterative optimization loop. First, 
*Weakness Mining* analyzes execution traces from previous tasks to identify recurring 
model-specific failure patterns rather than isolated mistakes. Next, *Harness Proposal* 
generates targeted, minimal modifications to the harness that address those weaknesses—for 
example, adjusting instructions, changing tool usage policies, or introducing additional 
validation steps. Finally, *Proposal Validation* subjects every proposed modification to 
regression testing and only accepts changes that improve performance without introducing 
regressions. This makes the harness evolve gradually while remaining stable, much like 
continuous integration and automated regression testing in software 
engineering. ([SummarizePaper][1])

To evaluate the idea, the authors implemented Self-Harness on *Terminal-Bench-2.0*, 
starting from a deliberately minimal harness and testing three different foundation 
models: *MiniMax M2.5*, *Qwen3.5-35B-A3B*, and *GLM-5*. Across all three models, the 
approach produced substantial improvements in held-out benchmark performance. Pass 
rates increased from *40.5% to 61.9%*, *23.8% to 38.1%*, and *42.9% to 57.1%*, 
respectively. Importantly, the learned harness changes were not generic prompt 
additions; qualitative analysis showed that they addressed each model's particular 
weaknesses, demonstrating that harness optimization is inherently model-specific 
rather than universally transferable. ([SummarizePaper][1])

The broader significance of the paper is that it shifts the optimization target 
from *training better models* to *teaching agents to improve the systems surrounding 
themselves*. Rather than relying on humans to continually refine prompts, tool policies, 
memory strategies, and execution rules, an agent can observe its own failures, infer 
recurring causes, propose improvements, and validate them automatically. This aligns 
closely with emerging ideas in agent engineering—such as evolving `AGENTS.md`, 
maintaining failure registries, and continuously refining execution harnesses—that 
view an agent as an adaptive software system rather than simply a static language 
model. The paper suggests a future where harness engineering becomes an ongoing 
autonomous process, allowing agents to adapt as foundation models and tasks evolve 
instead of requiring constant manual intervention. ([SummarizePaper][1])

SemOS has limited harness capabilities. Unlike coding assistant, which is an application,
SemOS is a 'collection of apps'. Harness normally is application dependent. That is,
different applications may require different harness. 

For instance, Doc Process Pipeline is a capability or an embedded app in SemOS.
Most doc processors use LLMs to extract artifacts. Extracting harness is mostly
per-document, which means that memory is not crucial to them. The most important
part is prompts. 

A general purpose Self Harness does not work. The authors create a Self Harness
for the selected benchmark, which is essentially an 'app'.

In order for a Self Harness to work or make sense, we need to know:
- What the harness does (the app)
- How to tell what's correct and what's not
- The variables that can be tuned to correct or improve the harness
- The chaos engineering, or the randomness of changing the variables
  when deterministic improvement methods hit the wall
- The ralph loop, when to stop
- And possibly many more

The things that can be tuned or learned include:
- Prompts
- Memory
- The knowledge base
- Tools
- Ontology

SemOS should have a Harness Editor. For instance, there should be a harness editor
for extracting metrics, entities and relations, inventory items, topics,
scenes, workflows, references, terminologies,
etc. 

Each extractor is an agentic application, and each agentic app has a 
Agent Harness specifically tuned for that app.

= 2026/07/27 - Dev Notes

*Ontology*
- Ontology Objects: term, axiom or mapping, semantic assertion, profile rule domain module, 
- Artifact lifecycle: candidate, normalize and reconcile, validate, human/policy
  approval, immutable release, active, deprecated or superseded
- Ontology Terms: external resources?
- Ontology Assertions: 'P-101 has discharge pressure 690 kPa'
- Domain modules: terms, axioms, mappings, profiles, dependencies, validation fixtures, release metadata

= 2026/07/30 - Dev Notes
Working on the benchmark.

= 2026/07/31 - Ontology
#let a_020 = link(
  "https://www.toutiao.com/article/7667012700145041961/?app=news_article&category_new=__all__&module_name=iOS_tt_others&req_id_new=20260729014836F09D9F7595A9B17DFC7E&share_did=MS4wLjACAAAAw3rqzAbRbSo4klPah7FJFhb-dpoy0Y2_hu6Pcvvt2pc&share_token=0735059d-8aae-11f1-85d5-00163e744ada&share_uid=MS4wLjABAAAAw3rqzAbRbSo4klPah7FJFhb-dpoy0Y2_hu6Pcvvt2pc&timestamp=1785261547&tt_from=weixin&upstream_biz=iOS_wechat&use_new_style=1&utm_campaign=client_share&utm_medium=toutiao_ios&utm_source=weixin&wxshare_count=1&source=m_redirect&wid=1785489832956"
)[#text(fill: blue)[Article Link]]

#a_020 \
Source: WeChat

== Rules
The process is:
```text
corpus-documents => LLM Extraction => Ontology => Rules => Rule Engine

user-input .............................................=> Rule Engine => Verdict + Reasoning

```

The above model has a problem: we can't go directly from inputs to
Rule Engine. We should do the same thing as processing corpus
documents.

In ontology, there are classes and instances.

Rule Example
```json
{
  "rule_id": "xxx",
  "source": "line numbers",
  "condition": {
    "type": "and",
    "operands": [
      {"field":"temperature", "op":"<", "value":80},
      {"field":"pressure" "op":"<", "value":1.5}
    ]
  },
  "requirements":"acceptable",
  "explanation":"xxx"
}
```

There are many challenges:
- How to extract rules
- How to handle the inputs
- How to match inputs to rules
- How to reason
- How to handle exceptions
- What to do if no rules are found

