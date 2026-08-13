# 1. Overview
**at the user-facing level, DeepSeek Harness can function much like 
Codex or Claude Code.** But architecturally, it is trying to be 
something broader: a **general, highly modular agent harness** rather 
than one fixed coding assistant.

DeepSeek is an “open-source agent harness.” It has a Web UI, lets you select a workspace, connect an LLM, and then gives the agent capabilities to **read/edit files, execute commands, delegate work, and maintain a plan**.   So from the perspective of sitting in front of it and saying:

> “Find this bug, modify the code, run tests, and fix it.”

it is absolutely in the same general category as Codex/Claude Code.

The major distinction is the architecture.

DeepSeek Harness is built around the principle **“everything is a plugin.”** Even things that would normally be considered the fundamental runtime—the model adapter, tool registry, session log, and even the **agent loop itself**—are plugins and can be replaced through configuration. There is deliberately no privileged monolithic “core” that extensions have to patch.

A useful mental model is:

```text
                 DeepSeek Harness (dsh)
                         │
              ┌──────────┴──────────┐
              │   Agent runtime     │
              │                     │
              │  session/log        │
              │  prompt assembly    │
              │  agent loop         │
              │  tool execution     │
              │  permissions        │
              │  sandbox            │
              │  planning           │
              │  subagents          │
              └──────────┬──────────┘
                         │
                    plugin seams
          ┌──────────────┼──────────────┐
          ▼              ▼              ▼
        LLMs           Tools          UI
     DeepSeek          shell          Web
     OpenAI            files          headless
     Anthropic         LSP            SDK
     custom API        ...
```

This is noticeably different from thinking:

```text
Codex
  =
OpenAI model
+ coding tools
+ agent loop
+ terminal
+ UI
```

With `dsh`, the desired abstraction is closer to:

```text
Harness
  =
pluggable agent runtime

then plug in:

model
tools
storage
sandbox
agent loop
UI
subagents
policies
...
```

# 2. Not tied to DeepSeek models

This is one particularly important point.

Despite the name **DeepSeek Harness**, you do **not** have to use a DeepSeek model. Its model configuration supports DeepSeek, Anthropic, OpenAI, and custom OpenAI-compatible providers. The documentation even specifically mentions Codex authentication as one supported route.

So something like this is conceptually possible:

```text
DeepSeek Harness
       │
       ├── Claude model
       ├── OpenAI model
       ├── DeepSeek model
       └── locally hosted model
```

That already tells us something important: **DeepSeek Harness is not primarily “the DeepSeek version of the Codex model.”** It's a runtime around models.

### Why call it a "harness"?

This fits quite closely with the distinction we've discussed before between **LLM/model**, **agent loop**, and **harness**.

Its default execution loop is explicitly structured around turns, steps, model requests, tool calls, tool results, and continuation:

```text
user input
    ↓
turn/start
    ↓
assemble prompt + tool schemas
    ↓
model request
    ↓
assistant response
    ↓
tool call(s)
    ↓
execute tools
    ↓
tool results
    ↓
model again if necessary
    ↓
turn/end
```

That machinery is described directly in its architecture documentation.

Deepseek Harness can be approximately viewed as:

| Thing                       | What it is                                     |
| --------------------------- | ---------------------------------------------- |
| DeepSeek model              | LLM                                            |
| GPT-5.x / Codex model       | LLM                                            |
| Claude                      | LLM                                            |
| DeepSeek Harness            | **agent harness/runtime**                      |
| Claude Code                 | coding assistant **built on a harness**        |
| OpenAI Codex CLI/app        | coding assistant **built on an agent harness** |
| `dsh` configured for coding | coding assistant                               |

That last distinction matters.

**DeepSeek Harness itself is a framework/runtime, but one of its ready-made configurations is effectively a coding assistant.**

# 3. Everything Replaceable

The technically interesting aspect isn't that DeepSeek created yet another coding assistant. There are plenty of those. It's that they made many normally hardwired agent-system concepts into explicit **capability seams**.

For example, their architecture says you can replace or extend:

* model provider
* model-facing tools
* shell backend
* persistent terminal backend
* filesystem provider
* sandbox backend
* approval policy
* session persistence
* subagent provider
* UI/editor integration
* model-visible context injection
* background jobs
* even the agent loop itself

That's a much more interesting architectural claim than simply “we made DeepSeek Code.”

Suppose you dislike how filesystem access works. In a conventional coding assistant, you may effectively have:

```text
Agent Loop
   │
   └── built-in filesystem implementation
```

DeepSeek wants:

```text
Agent Loop
   │
   ▼
Filesystem Service
   │
   ├── Local FS provider
   ├── Remote sandbox provider
   ├── Container provider
   └── Your provider
```

Same idea for models, subprocesses, subagents, etc.

# 4. Cordis

There's another layer worth noticing. DeepSeek Harness itself is built on **Cordis**, which supplies the plugin/context/event architecture. The repository describes Cordis as providing services, typed events, and reversible effects in a shared context.

So, simplistically:

```text
Cordis
   ↓
generic plugin/composition framework

DeepSeek Harness
   ↓
agent-harness abstractions
(session, LLM, tools, agent loop, sandbox, etc.)

dsh Web / headless
   ↓
actual applications

Your task
```

That is somewhat analogous to having a framework underneath Claude Code rather than only shipping Claude Code itself.

# 6. Conclusion

The landscape is like this:

```text
                     Agent systems
                          │
          ┌───────────────┴────────────────┐
          │                                │
   Opinionated products              Harness/framework
          │                                │
     Claude Code                    DeepSeek Harness
     Codex                          OpenCode-ish layers
     Qwen Code                      custom harnesses
          │                                │
          └───────────────┬────────────────┘
                          │
                        LLM
              Claude / GPT / DeepSeek / Qwen
```

There is overlap, because DeepSeek ships enough UI/tooling that **you can use `dsh` directly as the product**. But the architectural emphasis is much further to the right.

> **Operationally**, DeepSeek Harness is 'another Codex/Claude Code', but not **conceptually.** We can use DeepSeek Harness as a Codex-like coding assistant. But DeepSeek seems to be positioning it more as an **open, composable agent-harness platform from which Codex-like applications can be constructed**, rather than merely another fixed coding assistant.

This is what I have been dreaming of for long. I believe in the future, everyone will own his/her
own harness. A model is just a brain. A harness is a 'human being', an intelligent entity that can
think, reason, memory, and act. In order to act, it needs an environment to save data, retrieve data,
search knowledge, etc. One-size-fits-all does not work. Even for coding assistant, different coding
assistants may be good at different level, flavor, expertise, aspects, etc. For instance, some
may be better at bug fixing, some good at frontend development, some at long-run tasks, some 
are cheaper and faster, etc. These are heavily affected by the chosen LLMs, but not all. For instance,
'cheaper and faster' can be done at harness level.

Its treatment of the **agent loop, tool pipeline, session/event log, sandbox, subagents, and context 
injection as replaceable capabilities** is directly relevant to the harness-vs-workflow distinctions 
we've been exploring.
