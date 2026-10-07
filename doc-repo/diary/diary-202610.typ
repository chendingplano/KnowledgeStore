#import "@preview/diagraph:0.3.6"
#import "@preview/oxdraw:0.1.0": *
#import "../../Reviews/Review-ai-laya.typ": ref_review_laya
#import "../../Reviews/review-knowhere.typ": ref_review_knowhere

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
- Improvement (by Codex): coordinates using integers only in line files
