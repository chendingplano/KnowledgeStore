#import "@preview/diagraph:0.3.6"
#import "@preview/oxdraw:0.1.0": *
#import "../../Reviews/Review-ai-laya.typ": ref_review_laya
#import "../../Reviews/review-knowhere.typ": ref_review_knowhere
#import "../../Research/embedding.md": ref_embedding

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
    "Diary - 2026/10"
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
  logical_name: "diary-202610",
  file_id: "diary-202610",
  source: "",
  content_type: "diary",
  document_date: "2026/10/03",
  keywords: [diary],
)

#let callout(title, body) = block(
  fill: rgb("#f3f6fa"),                       // light blue-grey background
  stroke: (left: 3pt + rgb("#4b6b88")),       // accent bar on the left
  inset: (left: 12pt, right: 10pt, top: 8pt, bottom: 8pt),
  radius: 3pt,
)[
  *#title*

  #body
]

= 2026/10/03

== Context Language Model <context-language-model>

*“Context Language Models” (CLMs) proposes letting an LLM directly edit its own working context.* Instead of 
continually appending messages and relying on automatic summarization, the model can decide what to preserve, 
rewrite, remove, or offload. Existing models can use this approach without retraining. 
[arxiv.org](https://arxiv.org/pdf/2609.37725?utm_source=chatgpt.com)

The implementation mirrors the live context into an editable file. The agent modifies it using Bash, and the 
changes become its input for the next turn. Observed behaviors include maintaining compact progress notes, 
removing irrelevant search results, and updating multi-agent trackers. The key distinction from ordinary 
file-based memory is that *editing this file changes what the model sees 
next*. [arxiv.org](https://arxiv.org/pdf/2609.37725?utm_source=chatgpt.com)

Results suggest better performance at lower computational cost: on BrowseComp-Plus, CLMs achieved 59.4% 
accuracy—11.4% higher *relatively* than the strongest baseline—with 21.5% fewer inference FLOPs. Reinforcement 
learning further improved context management. These compute savings should not automatically be interpreted as 
equivalent latency or billing savings. [arxiv.org](https://arxiv.org/pdf/2609.37725?utm_source=chatgpt.com)

The authors also introduce suffix-cache reuse to reduce recomputation after edits, although surviving cached 
states retain information from the previous context. They identify editable context as a potential 
prompt-injection channel. My takeaway: agent-controlled working memory is promising, but preserving 
evidence and context integrity remains essential. [arxiv.org](https://arxiv.org/pdf/2609.37725?utm_source=chatgpt.com)

= 2026/10/04

== Data - Game History
link: https://gamehistory.org/5k-magazines/

It collects over 5,000 magzines. The documents are about games. Not sure whether
they are useful.

== Agents Don't Need Memory. They Need Documentation

#let ref-agent-memory = link(
  "https://liao.gg/blog/agents-dont-need-memory"
)[#text(fill: blue)[Agent Memory]]

#let ref-operator-memory = link(
  "https://github.com/aerovato/operator-memory"
)[#text(fill: blue)[Agent Memory - Operator Memory]]

#ref-agent-memory 

#ref-operator-memory

*Problems*
- Memories are surfaced by similarity
- Memories are stored without context
- The past is treated as truth
- Agents can't search for what they don't know
- The store is unauditable: which are stale? which have never been retrieved? which are incorrect
  and secretly affecting the way your agent works? which supersedes others?

Here is my take:
- There should always be topics for the current session.
  When a turn finishes, it uses a decision model to determine whether 
  the turn is related to the current topic(s) or new topics.
- There is a knowledge store for memory only. 
- Snippets are indexed by topics, sorted by time
- New snippets can override old ones (i.e., chain the 'same' snippets)
- Before processing a query, let the decision model determine whether 
  the query is relevant to the current topics, topics in the database,
  or new topics. If it is relevant to other than the current topics,
  reconstruct the memory by the new topics

This is similar to the Context Language Model (@context-language-model).

#figure(
  image("Images/image_2026100401.png", width: 100%),
  caption: [Change the loop (#ref-agent-memory)]
)

The author created an open source project (#ref-operator-memory) and used
it for over a year. It is purely markdown files. No vector stores, no
similarity calculations. 

- Complete Context Engine - Documentation, memory, indexes, and skills
- Automatic Documentation - specs, decisions, research, and more are
  automatically documented by the agent.
- Transparent Memory - memory is stored as markdown documents
- Shareable Knowledge - track documents with Git and share knowledge
  with your team
- Zero Infrastructure - no background agents, no embeddings, no vector
  databases, no model configuration.

*Actions*
- Summarize what the open-source does
- Get the main ideas behind it
- Implement a similar memory system

== What Muse Done Right

#let ref-muse-done-right = link(
  "https://metedata.substack.com/p/what-meta-got-right-with-muse"
)[#text(fill: blue)[What Muse Done Right]]

#ref-muse-done-right

*About Author*

The author (Mete Polat) is a product designer and builder, 
worked in companies like Netflix and Peloton. It appears the
author is very good at designing products.

*About Muse*

All the sudden, Muse come from nowhere and became one of the most
touted frontier model of all. It does not just make a model smarter,
but make it better for people to use it.

"Muse abstracted away of the unnecessary complexity. There is no
model selector, work vs chat switch, obscure slash commands, or
mentions of MCPs or cron jobs. It's one main chat, and everything
else serves to support it - a space to elevate ideas, track goals,
and surface artifacts it created for you. *Most importantly, 
it gave users a clear memtal model* - this is your personal helper
with their own computer."

"Each SaaS app was effectively a toolbox. Our job as designers was
to understand the job at hand, surface the right tools in a given
context, and make those tools easy to use so you can accomplish the 
job. With *LLM agents, a SaaS app is now more akin to a coworker 
that goes out and does the job.*"

#callout(
  "Comments",
  [
  SemOS is an SaaS. We should follow the same principle: it is a
  chatter. Everything else is designed around it. Users do not 
  have to use menus. When a user wants to review a document, 
  he/she can simple say: please review document 1234. SemOS
  will then pop up a dialog to collect information about the
  document to review.
]
)

*About Tools*

SemOS should focus on building tools. In an agentic system, the
core is a 'brain': the LLMs and the interface to the users: chatter.
But LLMs can barely do anything on users stuff. Tools are the
critical part to empower LLMs with users private data, knowledge,
environment, system.

A harness is another important ingredient to thread all pieces
together.

=== Making AI Cute Again
ChatGPT and Claude product branding is geared towards techies.
The products are sleek and the branding is aspirational, but to most
people it comes off as sterile and elitiest, at best. 

Muse went deep into anthropomorphization and the cuteness factor
to help you build personal affinity with your agent.

=== Take aways
"Interestingly, what’s making Muse a success also explains why Google 
has mostly failed to capture the zeitgeist so far. They have the 
compute and the ad money to fund something like Muse. But they 
have no product chops to build something simple and understandable 
in consumer AI.

OpenAI fumbled the consumer AI market by not investing in ads earlier. 
When they realized most people won’t pay for AI subscriptions, they 
refocused on enterprise to compete with Anthropic. Their ads business 
may be growing, but they’re well behind - they still have no established 
cash flow to fund something like Muse (their new “dots” product is a 
paid-tier feature).

Apple fumbled it (for now) because they never built the expertise to 
build AI, blinded by iPhone success, privacy posturing, and Google bribes.

Now Meta will pick up the pieces (literally and figuratively) - the 
pie is there for the taking. Muse is the first positive indicator."

== Work with Claude Opus 5.5
link: https://claude.dev/blog/getting-the-most-out-of-opus-5-5/

Anthropic wrote this article to help people get most out of Opus 5.5.
One major difference between Opus 5.5 and the older ones is that
it can work longer on complex tasks.

=== CLAUDE.md
We may need to add the following to CLAUDE.md:

"When a step doesn't need my input, keep going. Put status notes in 
the same message as your next action.
Stop and ask only when you can't continue without me, or before anything 
destructive: deleting data, force-pushing, or changing anything outside 
this repository."

=== About 'Stop'
You should consider telling Opus 5.5 when to stop, or what 'stop' means.
Below is an example:

"Migrate the payment endpoints from the old client to the new one.
Done means: every endpoint uses the new client, the old client is 
deleted, and the test suite passes.
Stop and ask me only if a test fails for a reason you can't explain."

=== Split Big Work
Early versions coordinate parallel subagents on long audits and
migrations, with little oversight.

For Opus 5.5, consider the following example:

"Audit every service in services/ for the retry bug in the linked issue.
Give each service to its own subagent. When a subagent reports back, 
check its evidence before you accept it.
Finish with one table: service, affected yes or no, and the evidence."

=== Keep task lists in a file
Opus 5.5 runs are longer now. A long run fills the context window,
and Claude Code then summarizes older turns. A list in a file survives
that, and it shows you at a glance what's done and what's left.

*How*

"Keep a checklist in TASKS.md. Tick each item when it is done, 
and add anything new you find."

#callout(
  "Comments",
  [This is where Claude Code goes wrong. Why you ask users to do it?
  If this is important, why you (Opus 5.5 or the harness) do it, so that
  users don't have to know the details.

  What I can think off for SemOS is that we will add this to LLMs
  (not just Opus 5.5) to keep tasks in files, automatically.

  The same idea applies to all other recommendations from Anthropic
  in its article.
]

)

= 2026/10/05

== Jev Is Not Always Better than LLM-as-a-judge
#let ref-jev-compare-llm = link(
  "https://developers.redhat.com/articles/2026/10/02/benchmarking-ai-decision-models-against-traditional-guardrails#on_prompt_engineering"
)[#text(fill: blue)[Jev and LLM-as-a-jedge]]

#ref-jev-compare-llm

#callout(
  "Conclusion",
  [
we did not find that decision models produced faster, cheaper, or higher-quality answers compared 
with LLM-as-a-judge. The exception here would be Laya, whose compact size is a clear advantage, 
assuming you can prompt engineer your way around its limitations.

Our benchmarks show that decision models like *Jev do not reliably outperform LLM-as-a-judge*, 
pre-trained predictive models, or open source decision models in speed or accuracy. However, 
*they rightly refocus industry attention on lightweight, task-specific inference paradigm 
that more closely resembles predictive machine learning*.  

Apps should use the right tool for the job. In recent years, LLMs have been presented as 
the answer regardless of problem size or scope. The excitement around Jev should signify 
a shift toward greater pragmatism in model selection.
]
)

== DS4 - Inference Engine Written in C

DwarfStar (DS4) aims to be the best way to run a few excellent large language models on 
consumer hardware (that is, hardware that people can actually own). To reach this goal, 
we are building a small native inference engine optimized first for DeepSeek V4 Flash 
(including the experimental vision model), DeepSeek V4.1 Flash (Metal, and text inference 
on CUDA), and additionally GLM 5.2 and 5.3, GLM 5.3 Flash and DeepSeek V4 PRO, and 
Qwen3.8 Flash Next (Metal and CUDA). The code is self-contained and deliberately narrow, 
not a general GGUF runner: you need to use the GGUF files the project produces, that are 
part of the project itself.

*DwarfStar (ds4) supports Macs, specifically Apple Silicon Macs via Metal*, and Metal 
is actually its *primary target*. The project documentation says the same build 
supports M3 and M5 Macs, with hardware-specific fast paths selected automatically. 

For RAM, there is no single requirement because it depends strongly on the model and quantization:

#table(
  columns: 3,
  align: left,

[Model / configuration], [Approx. model memory], [Mac recommendation],
[Qwen3.8 Flash Next Q2], [41.73 GiB resident weights],[Official starting point: 64 GB Mac],
[DeepSeek V4 Flash Q2], [~81 GiB],[96 GB+ normally; 64 GB possible with SSD streaming],
[GLM 5.3 Flash Q2], [~90 GiB],[128 GB recommended],
[DeepSeek V4.1 Flash Q2], [152 GiB main weights],[128 GB with SSD streaming; 256 GB+ for more residency],
[DeepSeek V4 Flash Q4], [substantially >81 GiB],[256 GB class],
[DeepSeek V4 PRO Q2], [very large],[512 GB resident target, or SSD streaming],
)

Importantly, those figures are not the complete runtime RAM requirement. ds4 also 
needs memory for the KV cache/context, activations, scratch buffers, Metal/runtime 
allocations, and the OS. For example, Qwen3.8 Q2 has 41.73 GiB of main/MTP weights, 
but that already puts it uncomfortably close to the physical limit of a 48 GB Mac.

*What this means for your 48 GB M4 Mac mini*

Your machine is *below ds4's documented 64 GB minimum starting configuration*. The docs explicitly give:

- *64 GB:* DeepSeek V4 Flash Q2 with `--ssd-streaming`
- *96 GB:* DeepSeek V4 Flash Q2 resident
- *128 GB:* DeepSeek V4 Flash Q2 or GLM 5.3 Flash Q2
- *256 GB:* Flash Q4 / GLM 5.3 Flash Q4
- *512 GB:* larger models such as PRO Q2

SSD streaming is ds4's mechanism for running models larger than RAM. Instead of 
loading all routed-expert weights into unified memory, it keeps a bounded expert 
cache in RAM and fetches missing experts from the GGUF on a fast SSD. However, 
*SSD streaming does not eliminate RAM requirements*: non-routed weights, 
context/KV cache, activations and runtime buffers still need memory.

So for your *48 GB M4*, I would characterize ds4 as *technically relevant but 
not a particularly comfortable fit at present*. Even its smallest highlighted 
model, Qwen3.8 Flash Next Q2, has *41.73 GiB of resident weights*, and the 
project's authors target it at 64 GB Macs. DeepSeek V4 Flash Q2 is ~81 GiB 
and would require aggressive SSD streaming on your machine.

If your main objective is running useful models efficiently on your 48 GB M4, 
*llama.cpp/MLX/Ollama with models sized for 32–40 GB working sets remain much 
more natural choices*. DwarfStar becomes especially interesting at *64 GB*, 
and much more compelling at *96–128 GB+*, because its focus is unusually 
large MoE models such as DeepSeek V4 and GLM 5.x rather than ordinary 
7B–70B-class local models.

== Langfuse

#let ref-langfuse = link(
  "https://github.com/langfuse/langfuse"
)[#text(fill: blue)[Langfuse]]

#ref-langfuse 

Langfuse is an *open-source LLM engineering / observability platform*. 
The easiest way to think about it is as something like *“Datadog + 
experiment tracking + prompt management for LLM applications.”* 
You instrument an LLM application, send traces and metadata to Langfuse, 
and then use its UI/APIs to inspect what happened, measure quality, 
compare experiments, and manage prompts. It is not an LLM framework 
like LangChain or an agent runtime; it sits alongside your application 
as an *LLMOps/observability layer*.

Its most important feature is *tracing*. Langfuse records an end-to-end 
execution as a trace, including nested operations such as LLM calls, 
retrieval, embeddings, tool/agent actions, and arbitrary application 
logic. This is particularly useful for RAG and agent systems, where 
a single user request may involve many steps. You can inspect 
inputs/outputs, latency, token usage, cost, model parameters, sessions, 
and failures. In practical terms, instead of only seeing “the model 
gave a bad answer,” you can see something closer to:

```text
User request
  └─ Trace
      ├─ classify_query
      ├─ retrieve_documents
      │    ├─ embedding
      │    └─ vector_search
      ├─ rerank
      ├─ LLM generation
      └─ postprocess
```

Langfuse goes considerably beyond logging. It includes *prompt management*, 
with centralized prompts, versioning and deployment; an *LLM playground* 
for changing prompts/model parameters interactively; *datasets* for storing 
test cases and benchmarks; and an *evaluation system* supporting LLM-as-a-judge, 
deterministic/code-based evaluators, manual labeling, user feedback, and 
custom evaluation pipelines. This makes it possible to build a loop such 
as:
```text
  production trace 
  → identify failure 
  → add case to dataset 
  → modify prompt/retrieval 
  → run evaluation 
  → compare results 
  → deploy`. 
```

It exposes APIs plus Python and JS/TypeScript SDKs, and integrates with 
OpenAI, LangChain, LlamaIndex, Haystack, LiteLLM, Vercel AI SDK, Ollama, 
CrewAI and many other frameworks.

Architecturally, Langfuse is a real server-side platform rather than a 
lightweight tracing library. It can be run as Langfuse Cloud or 
*self-hosted* using Docker Compose, Kubernetes/Helm, or cloud deployment 
templates. The current project explicitly highlights *ClickHouse* as a 
core database technology, which makes sense because LLM tracing generates 
large, append-heavy analytical datasets. For production self-hosting, 
this means Langfuse should be considered infrastructure: you run the 
service and its backing storage, while your applications asynchronously 
send telemetry to it. The repository is MIT licensed, although, as 
with many commercial open-source platforms, you should distinguish the 
OSS functionality from any hosted/enterprise features when evaluating 
deployment.

For something like SemOS architecture, I would mainly view Langfuse as 
an *instrumentation and experimental-analysis layer*, not as part of 
the knowledge-retrieval architecture itself. For example, one SemOS 
request might generate a trace containing 

```text
query interpretation
  → discriminator generation
  → BM25 candidate retrieval
  → graph expansion
  → semantic reranking
  → file exploration
  → LLM answer 
```

You could then compare retrieval strategies, record the documents 
each stage selected, measure latency/cost, attach evaluation scores, 
and discover systematically which pipeline variants actually improve 
answers. That is probably the most interesting aspect of Langfuse 
for your use case: *it gives you the infrastructure for observing 
and evaluating your evolving retrieval/exploration pipeline without 
dictating how that pipeline should work.* 

=== LLM Proxy
*Langfuse's full tracing normally depends on instrumentation*, but 
you can put an *LLM gateway/proxy in front of your providers and 
capture every LLM request that passes through it without modifying 
each application's tracing code*. Langfuse explicitly supports this 
pattern and lists gateways such as LiteLLM Proxy, Kong, Portkey, 
OpenRouter, and others. 
[Langfuse](https://langfuse.com/integrations?utm_source=chatgpt.com)

For example:

```text
App A ──┐
App B ──┼──> LiteLLM Proxy ───> OpenAI
App C ──┤        │             DeepSeek
Codex? ─┘        │             Anthropic
                 │
                 └── telemetry ──> Langfuse
```

With *LiteLLM Proxy + Langfuse*, LiteLLM can automatically send telemetry 
for all requests passing through the proxy. Langfuse says this captures 
request messages, model and parameters, generated response, token usage, 
latency/time-to-first-token, errors, and available metadata. 
[Langfuse](https://langfuse.com/integrations/frameworks/litellm-sdk?utm_source=chatgpt.com)

The distinction, however, is important: *proxy tracing gives you LLM-call 
observability, not complete application tracing*. Suppose SemOS does this:

```text
query
  ↓
generate discriminators
  ↓
BM25 search
  ↓
select 20 documents
  ↓
explore documents
  ↓
LLM call
  ↓
graph expansion
  ↓
LLM call
  ↓
answer
```

A transparent gateway can naturally observe the two LLM calls—the prompts, 
responses, tokens, model, latency, etc. But it cannot inherently know that 
the application performed `BM25 search`, selected particular documents, or 
did `graph expansion`. Those events happen inside SemOS and never cross 
the LLM proxy. Langfuse's own documentation makes exactly this distinction: 
a gateway sees requests passing through it, while application-level 
instrumentation is what provides the nested retrieval/tool/application 
execution trace. 
[Langfuse](https://langfuse.com/resources/engineering/llm-gateway?utm_source=chatgpt.com)

So there are effectively *three levels*:

#table(
  columns: 4,
  align: left,
[Approach], [App modification], [Sees all LLM calls], [Sees retrieval/tools/app logic],
[Langfuse SDK instrumentation], [Yes], [Yes], [*Yes*],
[LiteLLM/gateway → Langfuse], [Minimal\*], [*Yes*], [No],
[Network MITM proxy], [No], [Potentially], [No],
)

\* Applications at least need to send their LLM traffic to the gateway, 
typically by changing an API base URL/configuration.

Given that you already use a local MITM proxy for LLM traffic, there is an 
even more interesting possibility: you don't necessarily need LiteLLM 
if your objective is simply *“observe every LLM call made by everything 
on this machine.”*

Conceptually:

```text
                   ┌── OpenAI
                   │
Apps ──> MITM ─────┼── DeepSeek
          │        ├── Anthropic
          │        └── ...
          │
          └──> trace collector ──> Langfuse
```

Your proxy could recognize provider endpoints such as `/v1/chat/completions` 
or `/v1/responses`, parse requests/responses, and emit OpenTelemetry/Langfuse 
observations. Langfuse is built around OpenTelemetry and provides an OTLP 
ingestion endpoint, so you are not fundamentally required to use its SDK 
to produce the telemetry. 
[Langfuse](https://langfuse.com/integrations?utm_source=chatgpt.com)

There is one major architectural limitation, though. A pure network proxy usually sees:

```text
LLM call #123
LLM call #124
LLM call #125
```

but it may *not know that #123 and #124 belong to the same SemOS user 
request*, nor what semantic role each call has. You would need correlation 
metadata—trace IDs, application identifiers, session IDs, etc.—to 
reconstruct good traces.

So for your situation, I would seriously consider a *hybrid*:

```text
                    ┌──────────────────────┐
SemOS ─────────────>│                      │
Codex ─────────────>│ Central LLM Proxy    │──> providers
Claude Code ───────>│                      │
other programs ────>│                      │
                    └──────────┬───────────┘
                               │
                         Langfuse
```

The proxy automatically captures *100% of LLM traffic*, giving you 
a baseline with essentially no per-call instrumentation. SemOS can 
optionally attach a small amount of metadata such as `trace_id`, 
`session_id`, `operation=retrieval_query_generation`, etc. Then you 
instrument only the higher-level SemOS operations that actually 
matter—retrieval, exploration, reranking, graph traversal—rather 
than every LLM invocation.

That gets you most of the benefit of Langfuse while avoiding 
invasive instrumentation throughout your codebase. Langfuse 
specifically documents shared-proxy scenarios and supports 
metadata such as trace/session identifiers for correlating 
requests. [Langfuse](https://langfuse.com/integrations/frameworks/litellm-sdk?utm_source=chatgpt.com)

*Repository*: 

[Langfuse on GitHub](https://github.com/langfuse/langfuse?utm_source=chatgpt.com)

[Langfuse's LiteLLM Proxy integration](https://langfuse.com/integrations/gateways/litellm?utm_source=chatgpt.com)

= 2026/10/07

== Strands

link: https://strandsagents.com/blog/introducing-strands-decider/

This is an open-source decision model built on Qwen 3.5 2B, 
small enough to run on most consumer hardware.

In the benchmark, it ranked pretty good, but not the best.

== Embeddinggemma-2 - Google Embedding Model
link: https://blog.google/innovation-and-ai/technology/developers-tools/embeddinggemma-2/

- Under 1B
- Multimodal
- Can dynamically truncate vectors from 768 dimensions to 512, 256, 128
- 8K context window

=== Conclusion
We may want to try it.

== Today Work
- Bug (fixed by Codex): metric PDF display higlight rows incorrectly
- Improvement (done by Codex): add MODEL_DEFAULT_REASONING_POLICY, create wiki page
  use this env var for thinking control
- Improvement (done by Claude Code): requirements are no longer treated as metrics
- Improvement (done by Claude Code): extract_metrics with new rules
- Improvement (done by Codex): highlight rows in PDF viewer
- Improvement (done by Codex): extract geometry and save it in a companion file
- Improvement (done by Codex): coordinates using integers only in line files
- Improvement (by Claude Code): improve 'extract_metrics' for missing metrics
- New (done by Claude Code): create 'score-extract-metrics' skill
- New (done by Codex): the 'System Admin => LLM => Metrics => Benchmark' page

= 2026/10/08
== Anthropic releases Haiku 5.5
link: https://www.anthropic.com/claude-haiku-5-5

#figure(
  image("../../Images/image_2026100801.png"),
  caption: [Haiku 5.5 performance]
)

#figure(
  image("../../Images/image_2026100802.png"),
  caption: [Haiku pricing]
)

== Today Work
- Improvement (done by Codex): Metric benchmark, highlight the selected doc
- Improvement (done by Codex): show expected and actual in Metric benchmark
- Improvement (done by Codex): show the production metric when selected
- Improvement (by Claude Code): Use decision model to judge true metrics
- Bugs (fixed by Codex): coordinates for list entries in line files.
- Improvement (by

= 2026/10/09

== Menus 2.0
Link: https://manus.im/blog/introducing-manus-2-0

Menus just raised over \$500 millions (https://techcrunch.com/2026/10/08/chinas-manus-raises-over-500m-in-first-funding-round-since-split-with-meta/). 

Pricing
#figure(
  image("../../Images/image_2026100901.png"),
  caption:[Manus pricing]
)

== Today Work
- Installed skill 'seecode'
- Continue working on improving extract metrics
- Improvement (done by Codex): PDF viewer, the metric info box on the right and moveable
- Improvement (by Codex): Show dropped metrics in Gold metrics

= 2026/10/10

== Skill - lanshu-create-ai-presenter-video

Link: https://github.com/cclank/lanshu-create-ai-presenter-video

This is a skill that can turn a description of what you want to
present and an authorized human picture into a video, synched
with the content.

Explore this skill when I have time.

Link: https://www.toutiao.com/video/7689359444544127503/?app=news_article&category_new=tt_video_immerse&module_name=iOS_tt_others&req_id_new=202609272233506FD118BF5C491DE6A277&share_did=MS4wLjACAAAAw3rqzAbRbSo4klPah7FJFhb-dpoy0Y2_hu6Pcvvt2pc&share_token=aba0050d-ba83-11f1-8db8-829b3af924d9&share_uid=MS4wLjABAAAAw3rqzAbRbSo4klPah7FJFhb-dpoy0Y2_hu6Pcvvt2pc&timestamp=1790521010&tt_from=weixin&upstream_biz=iOS_wechat&utm_campaign=client_share&utm_medium=toutiao_ios&utm_source=weixin&wxshare_count=1&source=m_redirect

This is another skill. It uses Codex to generate synchronized video.

== Semantica and OntoFlow
Link: https://mp.weixin.qq.com/s/xrD3N1rpD4-2YQw3Q4XPxg

This Wechat article compares Semantica and OntoFlow.
Both are open-source ontology projects.

== Thoughts
Recent important topics:
- Hister: inputs => knowledge base
- RSIAgent: self-improvement agents. Its idea is very close
  to testbots. Self improvement is the future.
- Decision model: already available in SemOS
- Benchmark: just a start. It can be related to RSIAgent.
- Integrating SemOS with Pi.
- Semantics: what exactly is semantics?

=== Semantics

= 2026/10/11

== References
For a document-processing or knowledge-base system such as SemOS, references can point 
to many kinds of resources: documents, publications, websites, datasets, software, 
legal authorities, internal files, and even specific sections or statements.

Reference types are determined by reference mechanisms (how the reference is expressed). 
For example, a scientific paper might be referenced by its title, DOI, URL, citation 
number `[12]`, or author-year citation `(Smith, 2024)`. These are different representations 
of the same reference type.

Below is a comprehensive taxonomy of common reference types, including those relevant 
to technical documentation, scientific literature, standards, regulations, and general 
knowledge bases.

=== Reference types by target<reference-types>

1. Documents and files, with the following subtypes:
```text
| Document                | Report, specification, proposal, manual |
| File                    | PDF, DOCX, TXT, Markdown, HTML          |
| Internal document       | Company policy, project documentation   |
| Document section        | Chapter 3, Section 4.2, Appendix A      |
| Document element        | Table 2, Figure 5, Equation 7           |
| Document version        | Revision 2, draft v1.3                  |
| Document collection     | Folder, archive, document repository    |
```

2. Websites and online resources, with the following subtypes:
```text
| Website                 | `example.org`                           |
| Web page                | `example.org/about`                     |
| Blog                    | Personal blog, technical blog           |
| Blog post               | Individual article                      |
| Online article          | News article, technical article         |
| Wiki page               | Wikipedia, internal wiki                |
| Online forum            | Stack Overflow, Reddit                  |
| Forum post or comment   | Discussion thread, answer               |
| Social media post       | LinkedIn post, X post                   |
| Online documentation    | API documentation, developer guide      |
| Web archive             | Archived web page, Wayback snapshot     |
```

3. Scientific and academic publications, with the following subtypes:
```text
| Journal article         | Peer-reviewed research paper            |
| Conference paper        | ACM, IEEE conference paper              |
| Preprint                | arXiv, bioRxiv                          |
| Working paper           | Research working paper                  |
| Technical report        | University or laboratory report         |
| Thesis or dissertation  | Master's thesis, PhD dissertation       |
| Book                    | Scientific textbook                     |
| Book chapter            | Chapter within an edited volume         |
| Review article          | Systematic review, literature review    |
| Dataset paper           | Data descriptor, data publication       |
| Poster or abstract      | Conference abstract                     |
| Research protocol       | Experimental or study protocol          |
```

4. Standards and specifications, with the following subtypes:
```text
| International standard  | ISO, IEC, ITU                           |
| National standard       | ANSI, GB, DIN, BS                       |
| Industry standard       | ASTM, IEEE, SAE                         |
| Technical specification | W3C specification                       |
| Internet standard       | RFC 9110                                |
| Draft standard          | Internet-Draft, committee draft         |
| Standard amendment      | ISO amendment                           |
| Standard corrigendum    | Technical correction                    |
| Standard part           | ISO 9001, ISO 13485                     |
| Standard clause         | ISO 13485:2016, Clause 7.5              |
| Technical guideline     | Industry practice guideline             |
| Conformance profile     | Implementation profile                  |
```

5. Laws and regulations, with the following subtypes:
```text
| Law or statute          | Federal law, national legislation       |
| Regulation              | FDA regulation, EU regulation           |
| Directive               | EU directive                            |
| Administrative rule     | Agency rulemaking                       |
| Legal code provision    | 21 CFR § 820.10                         |
| Court decision          | Judicial opinion                        |
| Legal case              | Case citation                           |
| Regulatory guidance     | FDA guidance document                   |
| Regulatory notice       | Federal Register notice                 |
| Government policy       | Official policy statement               |
| Treaty or agreement     | International treaty                    |
| Legislative document    | Bill, committee report                  |
```

6. Books and general publications, with the following subtypes:
```text
| Book                    | Published monograph                     |
| Encyclopedia entry      | Reference encyclopedia                  |
| Dictionary entry        | Definition of a term                    |
| Handbook                | Engineering handbook                    |
| Magazine article        | Trade magazine                          |
| Newspaper article       | News report                             |
| White paper             | Industry white paper                    |
| Newsletter              | Published newsletter                    |
| Press release           | Corporate announcement                  |
| Brochure or catalog     | Product brochure                        |
```

7. Software and technical artifacts, with the following subtypes:
```text
| Software project        | GitHub repository                       |
| Source code file        | `src/parser.go`                         |
| Source code element     | Function, class, method                 |
| Commit                  | Git commit SHA                          |
| Branch or tag           | `main`, `v2.1.0`                        |
| Pull request            | GitHub PR #123                          |
| Issue or ticket         | GitHub issue, Jira ticket               |
| Software release        | Version 2.0                             |
| Software package        | PyPI, npm package                       |
| API                     | REST or GraphQL API                     |
| API endpoint            | `GET /users/{id}`                       |
| Software dependency     | Package or library dependency           |
| Configuration           | YAML, JSON configuration file           |
| Container image         | Docker image                            |
| Build artifact          | Executable, binary, package             |
```

8. Data and databases, with the following subtypes:
```text
| Dataset                 | Research dataset                        |
| Database                | PubMed, UMLS                            |
| Database record         | PubMed record                           |
| Database table          | SQL table                               |
| Database row            | Record identified by primary key        |
| Data field              | Column, attribute                       |
| Statistical series      | Economic time series                    |
| Spreadsheet             | Excel workbook                          |
| Spreadsheet element     | Sheet, cell, range                      |
| Data repository         | Zenodo, Figshare                        |
| Knowledge graph entity  | Wikidata QID                            |
| Ontology concept        | OWL class, SKOS concept                 |
```

9. Media and multimedia, with the following subtypes:
```text
| Image                   | Photograph, illustration                |
| Diagram                 | Architecture diagram                    |
| Chart                   | Statistical visualization               |
| Audio recording         | Podcast, interview                      |
| Video                   | YouTube video                           |
| Presentation            | Slide deck                              |
| Individual slide        | Slide 12                                |
| Webinar                 | Recorded seminar                        |
| Transcript              | Meeting or interview transcript         |
| Map                     | Geographic map                          |
| Geospatial layer        | GIS dataset                             |
```

10. Communication and collaboration, with the following subtypes:
```text
| Email                   | Email message                           |
| Email thread            | Conversation chain                      |
| Chat message            | Slack, Teams message                    |
| Discussion thread       | Forum or chat thread                    |
| Meeting record          | Minutes, meeting notes                  |
| Decision record         | Architecture Decision Record (ADR)      |
| Memo                    | Internal memorandum                     |
| Announcement            | Organizational announcement             |
| Shared workspace item   | Notion, Confluence page                 |
```

11. Business and organizational records, with the following subtypes:
```text
| Organization            | Company, government agency              |
| Product                 | Commercial product                      |
| Product model           | Device model or SKU                     |
| Product specification   | Datasheet                               |
| Patent                  | US patent, WIPO patent                  |
| Trademark               | Registered trademark                    |
| Contract                | Service agreement                       |
| Procurement document    | RFP, purchase order                     |
| Certification           | ISO certification                       |
| Audit report            | Compliance audit                        |
| Safety document         | Safety Data Sheet (SDS)                 |
| Test report             | Laboratory test report                  |
```

12. Other structured resources, with the following subtypes:
```text
| Person                  | Author, researcher                      |
| Event                   | Conference, workshop                    |
| Location                | Physical address, geographic place      |
| Concept or term         | Scientific concept                      |
| Definition              | Terminology definition                  |
| Measurement or metric   | Performance metric                      |
| Mathematical formula    | Named theorem or equation               |
| Procedure               | Testing or operating procedure          |
| Experiment              | Trial or experiment record              |
| Physical sample         | Specimen, material sample               |
| Clinical trial          | ClinicalTrials.gov record               |
```

This taxonomy is intentionally broad. Not all entries are bibliographic references: 
some are entity references, artifact references, or internal structural references.

=== Reference mechanisms

The second dimension is how a reference appears in source text.

```text
| Mechanism             | Example                            | Interpretation                    |
| --------------------- | ---------------------------------- | --------------------------------- |
| URL                   | `https://example.com/report.pdf`   | Direct web resource               |
| DOI                   | `10.1145/1234567`                  | Persistent publication identifier |
| ISBN                  | `978-0-...`                        | Book identifier                   |
| ISSN                  | `1234-5678`                        | Serial publication identifier     |
| arXiv ID              | `arXiv:2609.15364`                 | Research preprint                 |
| PMID / PMCID          | `PMID: 12345678`                   | Biomedical publication            |
| RFC number            | `RFC 9110`                         | Internet standard                 |
| Standard number       | `ISO 13485:2016`                   | Standard document and edition     |
| Legal citation        | `21 CFR § 820.10`                  | Regulatory provision              |
| Patent number         | `US12345678B2`                     | Patent document                   |
| Repository path       | `github.com/org/repo`              | Software repository               |
| File path             | `docs/architecture.md`             | Local or repository file          |
| Relative path         | `../specs/design.pdf`              | File relative to source           |
| Anchor / fragment     | `#section-3`                       | Specific location in resource     |
| Numbered citation     | `[1]`, `[12–15]`                   | Bibliography entry                |
| Author-year citation  | `(Smith et al., 2024)`             | Bibliographic reference           |
| Named reference       | `as defined in ISO 9001`           | Natural-language reference        |
| Structural reference  | `see Section 4.2`                  | Internal document reference       |
| Indirect reference    | `according to the previous report` | Context-dependent reference       |
| Identifier            | `Q42`, `CVE-2025-1234`             | Entity or record identifier       |
| Footnote / endnote    | Superscript `¹`                    | Note containing a reference       |
| Hyperlink             | `[documentation](url)`             | Linked text                       |
| Cross-reference field | Word/PDF cross-reference           | Structured document reference     |
| Citation key          | `[@smith2024]`                     | Bibliography-manager reference    |
```

An important distinction is that a URL, DOI, or file path is not itself a target type. 
It is an identifier or locator.

=== Reference relationships

Reference relationships are the semantic relationship between the source and the 
referenced target.

```text
| Relationship    | Meaning                         | Example                                |
| --------------- | ------------------------------- | -------------------------------------- |
| `cites`         | Source cites target             | Paper cites another paper              |
| `references`    | General reference               | Document mentions another document     |
| `quotes`        | Reproduces target content       | Report quotes a regulation             |
| `defines_in`    | Definition originates in target | Term defined in ISO standard           |
| `based_on`      | Derived from target             | Procedure based on guideline           |
| `implements`    | Implements target specification | Software implements RFC                |
| `complies_with` | Claims compliance with target   | Product complies with ISO standard     |
| `requires`      | Depends on target requirement   | Regulation requires testing            |
| `supersedes`    | Replaces earlier target         | New standard replaces old edition      |
| `amends`        | Modifies target                 | Amendment modifies regulation          |
| `contradicts`   | Conflicts with target           | Two documents specify different limits |
| `supports`      | Provides supporting evidence    | Study supports a claim                 |
| `refutes`       | Challenges a claim              | Study refutes prior conclusion         |
| `extends`       | Builds on target                | Research extends previous work         |
| `uses`          | Uses referenced resource        | Paper uses dataset                     |
| `depends_on`    | Dependency relationship         | Package depends on library             |
| `derived_from`  | Produced from target            | Chart derived from dataset             |
| `part_of`       | Structural containment          | Section belongs to document            |
| `same_as`       | Identifies equivalent resource  | DOI and URL resolve to same paper      |
| `version_of`    | Version relationship            | Draft is version of specification      |
| `see_also`      | Related resource                | Documentation points to related guide  |
```

These relationships are not mutually exclusive. A document may both `cites` and 
`contradicts` another document.

=== Reference scope

References can point to different levels of granularity.

- Document (ISO 13485:2016)
- Section / Clause (Clause 7.5 — Production and service provision)
- Paragraph / Requirement (Individual normative statement)
- Text span / Data element (Exact sentence, table cell, metric, or value)

A reference may also target an entire collection rather than a single document, 
such as an ISO standards series or a GitHub repository.

=== Recommended data model for SemOS

Avoid creating a separate extraction schema for every type in the first 
table. Instead, use the top-level types (categories) listed in @reference-types, 
with extensible subtypes.

For example:

```
{
  "reference_type": "standard",
  "reference_subtype": "international_standard",
  "target": {
    "target_type":"standard",
    "title": "ISO 13485",
    "identifier": "ISO 13485:2016",
    "version": "2016",
    "section": "7.5"
  },
  "reference_mechanism": "named_reference",
  "relationship": "complies_with",
  "source": {
    "document_id": "doc_123",
    "lines": [120, 121]
  },
  "evidence": "in accordance with ISO 13485:2016, Clause 7.5",
  "resolution_status": "unresolved"
}
```

with additional attributes, such as identifier, locator, version, etc.

This supports not only citation extraction, but also document dependency graphs, 
regulatory traceability, provenance tracking, version analysis, and cross-document 
reasoning.

Two additional considerations matter for a robust implementation:

First, distinguish mention detection from reference resolution. An extractor 
can identify `ISO 13485:2016` without locating the actual standard. Resolution 
is a separate operation that maps the extracted mention to a canonical resource, 
possibly with several candidate matches.

Second, distinguish reference identity from location. The same paper may have 
an arXiv URL, a DOI, a publisher page, and a local PDF. They should resolve to 
one conceptual publication where appropriate, while preserving different versions 
and manifestations.

= 2026/10/14

== Work
- Install Tencent WeVisDoc-4B in mlx-vlm (done by Codex)
- New (done by Claude Code): References => Benchmark
- Improvement (done by Claude Code): gold references improvement
- Improvement (done by Codex): rework on "Workspace"
- New (done by Codex): add Knowledge Graph in 'Workspace'

= 2026/10/15

== Work
- Bug (fixed by Codex): enrich metrics using wrong prompt name
- Improvement (done by Claude): gold metrics, version 6.2.0

= 2026/10/16

== Work
- Installed anatomy skill (done): anatomy draws 3D images, works with Codex, 
  Claude Code
- Improvement (done by Claude Code): improve metrics

= 2026/10/17

== Late Embedding
- Understand what the late embedding is.
- BGE-M3 and Jina 3 are good candidates. Jina 3 is better,
  but there is a license issue for using Jina 3. BGE-M3 has an embedding
  issue. Its standard embedding and late embedding use different embeddings.
- Conclusion: need experiments and benchmark. Not for now

= 2026/10/18

== DeepSeek Search
Link: https://api-docs.deepseek.com/guides/search/

Price: 1000 successful requests/second

== Scientic Research Skill
Link: https://github.com/K-Dense-AI/scientific-agent-skills/tree/main

Open-source AI co-scientist that runs on your desktop, powered by Scientific 
Agent Skills. Bring your own API keys, pick from 40+ models, and get a full 
research workspace with web search, file handling, 100+ scientific databases, 
and access to all 177 skills in this repo. Your data stays on your computer, 
and you can optionally scale to cloud compute via Modal for heavy workloads.

I installed six of its skills, all started with "scientific-"

== A tutorial for humans with models
Link: https://felixrieseberg.com/how-to-be-more-ambitious-a-tutorial-for-humans-with-models/

*Be ambitious*
=== Speed
The same work in less time, the bread and butter for AI’s economic value: 
If you need some code written, I’ll do it faster with Claude. Well established 
and requires little creativity in how you approach AI, so I’ll skip this one.

=== Altitude
Going up in abstraction and considering the outcome rather than the individual task.

=== Depth
Considering a task the way a field-leading expert would. Rather than 
operating at the task’s layer, we go one level deeper and touch the underlying 
data, tools, and problems.

How:

1. 强制要求使用行业顶尖专家的真实武器：当你让 Claude 分析数据，如果它只满足于给
你吐出几个 Markdown 格式的简单文本表格，立刻打回去！强行要求它使用工业级数据库、
严谨的统计学回归模型与因果推断方法，哪怕你不知道专家用什么，直接问 Claude，
它自己全懂.

2. 提出看似不可思议的超高目标，并坚定告诉它这非常合理：网页加载时间想从 10 秒压到 
5 秒？别提 5 秒，直接要求压到 200 毫秒！当模型叫苦觉得不可能时，明确告诉它：
“这在工程上完全可以解决，继续往下深挖，不要停”

3. 用原始底层数据反向对抗既有假设：业务里很多所谓的常识，其实都只是对现实的粗糙脑补，
把最底层的原始日志全部扔给模型：“管理层普遍认为用户流失是新手引导没做好导致的，
请完全基于原始日志，尝试能否复现并证实这个结论”

4. 挖掘盲区，创造前所未有的新知识：让模型在真实日志中建立微观用户行为模拟器，
去预测它从未见过的新数据，找出连老员工都从未注意到的早期流失信号

5. 必须引入客观的外部裁判：这一条至关重要！在当下大模型发展的阶段，绝对不要让模型自
己去评判自己的答案，它会陷入自我感动，必须引入能够运行代码、单元测试、基准跑分的外
部校验工具，让模型在实打实的客观反馈下快速迭代

Felix prompt:
I want a deeper version of this task, not a bigger one. Before rewriting it: 
(1) say what a top professional in this field would do here that I’m not asking for; 
(2) name the rawest material they would start from instead of what has already 
been digested for me; 
(3) name the specific methods and tools they would use; 
(4) say what, other than you or me, would show the result is right. Then rewrite 
my prompt to ask for exactly that.

=== Range
Drawing on multiple fields rather than just the one the task might need 
  at the surface, using knowledge, tools, and techniques you normally wouldn’t.
