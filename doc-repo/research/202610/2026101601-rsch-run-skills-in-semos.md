# Summary
We want to run skills in SemOS and go further through the integration of Pi to SemOS: 
rather than implementing skill execution inside SemOS, 
we will make Pi the general-purpose agent execution engine of SemOS, while SemOS remains 
responsible for knowledge management, retrieval, exploration, and domain-specific reasoning.

The important distinction is that a skill is not an executable program by itself. It is 
primarily a package of instructions, possibly accompanied by scripts, resources, and 
configuration. The agent harness provides the runtime that interprets those instructions 
and performs the work.

## 1. Will a skill behave the same in Codex and SemOS?

Not necessarily. There are two separate questions: whether the skill can be loaded, and whether 
it can be executed with equivalent behavior.

For example, consider a skill with the following structure:

```
skills/
  analyze-standard/
    SKILL.md
    scripts/
      extract_tables.py
    references/
      analysis-guidelines.md
```

The `SKILL.md` might say:

```
---
name: analyze-standard
description: Analyze technical standards.
---

# Instructions

1. Read the provided document.
2. Extract requirements and metrics.
3. Identify relationships between requirements.
4. Run scripts/extract_tables.py.
5. Generate a structured report.
```

This skill depends on several capabilities that the harness must provide.

| Capability                       | Codex                         | SemOS without Pi          |
| -------------------------------- | ----------------------------- | ------------------------- |
| Read SKILL.md                    | Yes                           | Easy to implement         |
| Discover and select skills       | Yes                           | Must implement            |
| Follow instructions with LLM     | Yes                           | Likely already available  |
| Read and write files             | Yes                           | Depends on SemOS tools    |
| Execute Python/scripts           | Yes                           | Must implement            |
| Run shell commands               | Yes                           | Must implement            |
| Iteratively use tools            | Yes                           | Depends on agent loop     |
| Handle errors and retry          | Yes                           | Must implement            |
| Manage execution context         | Yes                           | Depends on implementation |
| Apply permissions and sandboxing | Yes, subject to configuration | Must implement            |

Even when both harnesses understand the same `SKILL.md`, their execution behavior can differ substantially.

For example, Codex might use a shell command to extract tables, whereas SemOS might use its own document parsing tools. Both could satisfy the skill's intent but produce different results.

There are also harness-specific skills. A skill written for Claude Code might rely on Claude-specific tools, subagents, hooks, or plugins. Such a skill may not run unchanged in Codex or Pi.

Therefore, I would distinguish three levels of compatibility:

1. Format compatibility: Can the harness discover and read the skill?
2. Tool compatibility: Can it provide the tools and environment required by the skill?
3. Behavioral compatibility: Can it execute the workflow with comparable correctness and reliability?

Supporting the first level is relatively easy. Supporting the other two is where the engineering effort lies.

## 2. Is integrating Pi the right approach?

Yes. I think Pi is particularly suitable because it is designed as a relatively small, extensible coding-agent framework rather than a large, tightly integrated assistant product.

The relevant project is [Pi (pi-mono)](https://github.com/badlogic/pi-mono?utm_source=chatgpt.com).

Pi provides the agent infrastructure that SemOS would otherwise have to build and maintain itself, including an LLM-driven tool loop, tool execution, session management, and extension mechanisms.

However, Pi should not be treated as a universal compatibility layer for every skill ecosystem. Its native skill support and extensions are useful, but compatibility with Codex or Claude Code skills still depends on the tools and conventions those skills require.

### My proposed architecture

SemOS Application

User interface · API · Knowledge workflows

SemOS Agent Orchestrator

Task planning · Skill selection · Context assembly · Permissions

Pi Agent Runtime

LLM loop · Skill loading · Tool calls · Sessions · Extensions

Skill runner

Shell / Python

SemOS tools

SemOS Knowledge Engine

Virtual FS · Search · Graph · Ontology · Documents

Execution Environment

Workspace · Sandbox · Scripts · Artifacts

The key architectural decision is that Pi owns the agent execution loop, while SemOS owns the knowledge and application semantics.

For example, when a user asks SemOS to analyze a medical standard:

1. SemOS identifies the relevant documents and selects a suitable skill.
2. SemOS starts a Pi session with the skill and relevant context.
3. Pi follows the skill instructions, invoking SemOS tools to retrieve provisions, metrics, references, and relationships.
4. Pi executes any required scripts in an appropriately restricted environment.
5. SemOS validates, stores, indexes, and presents the resulting artifacts.

This avoids duplicating a general-purpose agent harness inside SemOS.

## 3. One important design decision: skills should be independent of Pi

I would avoid making Pi's internal skill representation the canonical skill model of SemOS.

Instead, introduce a SemOS Skill Registry that is independent of the execution engine.

For example:

```
SemOS/
  skills/
    extract-metrics/
      SKILL.md
      scripts/
    analyze-compliance/
      SKILL.md
    compare-standards/
      SKILL.md
```

Each registered skill could have additional SemOS-managed metadata:

```
id: analyze-compliance
runtime: pi

capabilities:
  - semos.search
  - semos.read_document
  - semos.get_provisions
  - semos.get_metrics
  - filesystem.read

permissions:
  shell: false
  network: false
  knowledge_write: false
```

This is a proposed SemOS configuration, not a native Pi skill schema.

The benefit is architectural flexibility. Today, `runtime: pi` could be the only supported runtime. In the future, you could add another harness without changing your knowledge system or skill registry.

I would also make the registry distinguish between skill requirements and execution permissions. A skill may request shell access, but SemOS policy should determine whether it receives that access.

## 4. An even more important consideration: expose SemOS as tools to Pi

This is where the integration can deliver significantly more value than simply running existing skills.

Pi already understands the general pattern of agents invoking tools. SemOS has specialized capabilities that conventional coding harnesses do not possess.

For example:

| SemOS tool                | Purpose                                   |
| ------------------------- | ----------------------------------------- |
| `semos.search`            | Hybrid keyword and semantic retrieval     |
| `semos.explore`           | Navigate the virtual knowledge filesystem |
| `semos.get_provisions`    | Retrieve extracted requirements           |
| `semos.get_metrics`       | Retrieve structured metrics               |
| `semos.graph_traverse`    | Explore entities and relationships        |
| `semos.resolve_reference` | Resolve cross-document references         |
| `semos.compare_documents` | Compare standards or specifications       |

These should be available as native Pi tools through an extension or a suitable tool protocol.

Then a skill could contain instructions such as:

```
# Compare Standards

1. Identify the relevant standards using semos.search.
2. Retrieve requirements using semos.get_provisions.
3. Find related requirements using semos.graph_traverse.
4. Identify conflicting requirements.
5. Generate a comparison report with citations.
```

This is more powerful than simply running a generic coding skill, because the agent can use SemOS's precomputed structured knowledge rather than repeatedly parsing and extracting information from raw documents.

For the same reason, I would avoid forcing Pi to access everything through shell commands. Native SemOS tools should expose structured inputs, outputs, source references, and explicit error states.

## 5. Potential pitfalls

There are four areas I would pay particular attention to.

First, virtual filesystem compatibility. Many coding skills assume that documents exist as ordinary files and can be accessed through `cat`, `grep`, `find`, or Python. SemOS's virtual filesystem may not support those assumptions. You can address this through native tools, materialized temporary workspaces, or a filesystem adapter. A filesystem adapter is particularly interesting for exploration-oriented agents.

Second, skill discovery and context management. Loading every skill into the agent context would waste tokens and potentially reduce selection accuracy. SemOS can use its existing indexing capabilities to discover relevant skills and load their full instructions only when needed. The distinction between skill metadata, skill instructions, and skill execution is important.

Third, security. Skills can contain executable scripts and instructions obtained from external sources. Treat them as untrusted packages. SemOS should control filesystem access, shell execution, network access, secrets, and write permissions independently of what a skill requests.

Fourth, observability and reproducibility. Record the skill version, model, tool calls, input document versions, permissions, and produced artifacts. This is especially valuable for standards analysis, where you may need to explain how a particular conclusion was reached. A successful skill invocation should produce an auditable execution trace, not just a final answer.

## 6. What I would implement first

I would start with a narrow vertical slice rather than attempting broad compatibility immediately.

| Phase | Implementation                                     | Objective                     |
| ----- | -------------------------------------------------- | ----------------------------- |
| 1     | Embed or invoke Pi from SemOS                      | Establish agent execution     |
| 2     | Load ordinary `SKILL.md` packages                  | Support basic skills          |
| 3     | Expose SemOS search, document, and graph tools     | Enable knowledge-aware skills |
| 4     | Add execution permissions and sandboxing           | Control risk                  |
| 5     | Add execution traces and artifact persistence      | Make results auditable        |
| 6     | Introduce skill discovery and compatibility checks | Scale the skill ecosystem     |

I would initially test three representative skills: one that only uses instructions and SemOS tools, one that runs Python scripts, and one that requires both filesystem exploration and structured knowledge retrieval. These will reveal most of the important integration boundaries.

## 7. One further architectural opportunity

I think there is an interesting longer-term opportunity for SemOS: treat skills themselves as knowledge artifacts.

A skill has a purpose, prerequisites, capabilities, dependencies, applicable domains, and relationships to other skills. These are all things SemOS is designed to represent and retrieve.

For example, SemOS could understand that `compare-standards` depends on `extract-provisions`, that `analyze-compliance` is applicable to medical regulations, and that a particular skill requires Python execution.

Eventually, an agent could discover skills through the same exploration and retrieval mechanisms it uses for documents. It could also reason about skill composition and select workflows based on available capabilities.

This does not require implementing another harness. It requires modeling skills as first-class entities in SemOS.

My overall recommendation: Use Pi as SemOS's initial and primary agent runtime. Do not invest in rebuilding the generic agent loop, shell execution, or coding-assistant infrastructure unless Pi proves inadequate for a specific requirement.

But maintain three clean boundaries:

- SemOS: knowledge, skill registry, orchestration policy, persistence.
- Pi: agent reasoning loop, skill execution, tool invocation, session runtime.
- Execution environment: actual filesystem, scripts, sandbox, and external resources.

One final distinction matters: Pi should be an execution engine, not necessarily the top-level orchestrator of all SemOS workflows. SemOS may eventually need deterministic, durable workflows that coordinate multiple Pi sessions, validation stages, human review, and database transactions. Those responsibilities should remain outside Pi.

That separation gives you the advantages of a mature, specialized agent harness without making SemOS dependent on its architecture everywhere.