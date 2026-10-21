--- 
Date: 2026/10/22
Contributor: ChatGPT, Chen Ding
---

# Overview

In coding assistants such as Claude Code, Codex, and Pi, an agent is often a separate execution session with a specific task, role, and context.

An agent is not necessarily a different LLM or a different harness. It is an execution instance configured to perform a particular role, typically with its own context, instructions, and tools.

Specialized agents can have different system prompts, tool permissions, models, memory, and execution policies. They do not have to share everything except the task prompt.

## 1. Distinguishing agent, session, and harness

These terms describe different aspects of an AI system.

| Concept | Meaning                                                                         | Example                             |
| ------- | ------------------------------------------------------------------------------- | ----------------------------------- |
| LLM     | The underlying inference model                                                  | Claude, GPT, DeepSeek               |
| Harness | Runtime that manages the LLM, tools, context, execution loop, permissions, etc. | Claude Code, Codex, Pi              |
| Agent   | A configured execution unit that pursues a goal using an LLM and tools          | Code reviewer, debugger, researcher |
| Session | One execution context containing messages, tool results, and state              | A debugging session                 |
| Task    | The work assigned to an agent                                                   | Find a race condition               |

A useful engineering abstraction is:

\\[ \text{Agent Instance} = \text{Harness} + \text{Configuration} + \text{Session State} + \text{Task} \\]

Here, configuration can include the model, system prompt, tool access, memory policy, and execution limits.

A session is not quite the same as an agent. An agent may execute multiple tasks within a long-lived session, or it may create a fresh session for every task.

## 2. How a thin controller and specialized agents work

Consider a coding assistant that delegates work to three specialists.

User request

"Implement authentication and verify its security"

Thin controller / Orchestrator

Decompose tasks · Delegate · Collect results · Coordinate

Implementation

Write code

Own instructions, tools, context

Security

Review vulnerabilities

Own instructions, tools, context

Testing

Run tests

Own instructions, tools, context

All three may use the same underlying harness and LLM

In this architecture, the controller may do very little actual coding. It delegates the implementation to one agent, the security review to another, and testing to a third.

Each specialist can have:

- A separate conversation history and context window.
- A different system prompt or agent-specific instructions.
- A different selection of tools and permissions.
- A different LLM.
- Its own temporary state or persistent memory.

But these differences are optional, not requirements.

## 3. Does each agent use the same system prompt?

There are three common implementation patterns.

### Pattern A: Same system prompt, different task prompt

All agents use the same harness, system prompt, model, and tools.

```
System prompt:
  You are a software engineering assistant.

Agent 1 task:
  Implement the authentication module.

Agent 2 task:
  Review the authentication module for vulnerabilities.

Agent 3 task:
  Write integration tests for authentication.
```

This is the simplest architecture.

It works because LLMs can adapt their behavior to task instructions without changing their system prompts.

However, it offers relatively weak role specialization and isolation.

### Pattern B: Same harness, different agent configurations

This is the pattern I would associate most closely with specialized subagents in Claude Code.

```
agent: security-reviewer

model: claude-sonnet
system_prompt: |
  You are a security specialist.
  Identify vulnerabilities and explain risks.
  Do not modify source code.

tools:
  - read_file
  - grep
  - search

memory: security-reviewer-memory
```

Another agent might use:

```
agent: implementation

model: claude-opus
system_prompt: |
  You are an implementation specialist.
  Follow existing architecture and conventions.
  Implement the requested changes.

tools:
  - read_file
  - write_file
  - shell

memory: implementation-memory
```

Both use the same harness implementation, but their configurations differ.

One important detail: a harness may compose the effective system instructions from several layers, rather than replace the entire system prompt.

For example:

\\[ P\_{\text{effective}} = P\_{\text{harness}} + P\_{\text{agent}} + P\_{\text{project}} \\]

The task prompt is then supplied separately.

In Claude Code, custom subagents can have their own instructions, tool restrictions, model selection, and context. Their definitions are not necessarily implemented as literal replacements of every underlying system-prompt message.

### Pattern C: Different harnesses

A controller can also delegate to completely independent runtimes.

For example:

```
Controller
  |
  +-- Claude Code
  |     Task: Implement feature
  |
  +-- Codex
  |     Task: Review code
  |
  +-- Pi
        Task: Run tests and diagnose failures
```

Here, the controller coordinates multiple harnesses. Each harness has its own execution loop, context management, tool definitions, and permission policies.

This is more complex and often unnecessary.

## 4. What happens to memory and context?

This is another important distinction.

Consider the following:

| Component                   | Typically shared?                    |
| --------------------------- | ------------------------------------ |
| Harness implementation      | Yes, for subagents using one harness |
| Base system instructions    | Often                                |
| Agent-specific instructions | No                                   |
| Model                       | Configurable                         |
| Conversation history        | Usually isolated                     |
| Tool implementations        | Often shared                         |
| Tool permissions            | Configurable                         |
| Project files               | Usually shared                       |
| Persistent memory           | Depends on architecture              |
| Context window              | Usually separate                     |
| Retry/fallback policies     | Often inherited, possibly overridden |

For example, a security-review agent may receive the repository path and task instructions but not the parent agent's complete conversation history.

The security agent explores the repository independently, constructs its own context, and returns a summary of findings.

This is particularly valuable because it avoids copying a large parent conversation into every subagent.

Also, a specialized agent is not automatically a domain expert. Its expertise may come from its model's pretrained knowledge, role instructions, available tools, retrieved documentation, or persistent memory. Merely naming it `security-expert` does not guarantee expert performance.

## 5. How this relates to SemOS and Pi

Since you're integrating Pi into SemOS, I would recommend treating agents as configured execution profiles, not as separate harnesses.

Conceptually:

```
SemOS
  |
  +-- Controller
        |
        +-- Agent Definition: Researcher
        |     Model: DeepSeek
        |     Tools: search, read, graph
        |     Instructions: Research specialist
        |
        +-- Agent Definition: Ontology Expert
        |     Model: DeepSeek
        |     Tools: ontology, search, read
        |     Instructions: Ontology specialist
        |
        +-- Agent Definition: Validator
              Model: Qwen
              Tools: read, compare, validate
              Instructions: Knowledge validation
```

All three agents can be executed by Pi, provided your integration supports configuring the relevant instructions, tools, and model.

I would distinguish three objects in the implementation:

- AgentDefinition: A reusable configuration describing the agent's role, model, instructions, tools, and policies.
- AgentSession: A running instance with its own context, state, and execution history.
- AgentTask: A particular assignment executed within a session.

This separation is important. For example, you can have 10 simultaneous `OntologyExpert` sessions using the same `AgentDefinition`, each processing a different document.

An `AgentDefinition` is reusable; an `AgentSession` is stateful; an `AgentTask` is a unit of work.

## 6. Returning to the article

I couldn't retrieve the article's readable contents from Toutiao, so I cannot verify its specific implementation. Based on your description, however, it sounds like Pattern B: a thin controller coordinating specialized agents using a shared harness.

The controller's primary responsibilities are task decomposition, routing, coordination, and result integration. The specialized agents perform the substantive work.

This leads to what I consider the most useful distinction:

A harness defines how an agent operates. An agent definition specifies how that operation is configured. A session represents one running instance. A task defines what that instance should accomplish.

For SemOS, this means you probably do not need to develop multiple harnesses. A single Pi-based harness supporting multiple agent definitions and isolated sessions could provide most of the benefits of a multi-agent architecture.

The difficult engineering problems are likely to be context isolation, shared knowledge access, inter-agent communication, and result verification, rather than creating the specialized agents themselves.