---
name: [[def:Stash]]
file_id: file-2026042501
links: [[Memory, Memory System]]
note_date: 2026/04/25
source-url: https://github.com/alash3al/stash
document-date: 2026/04/25
---

The stash project is a lightweight, developer-focused tool designed to act as a **self-hosted “stash” for secrets, configs, and small pieces of data**—essentially a minimal key-value storage service with a clean API. Its core idea is to provide a simple, fast, and portable backend where developers or services can store and retrieve structured or unstructured data without the overhead of a full database system.

At a high level, Stash behaves like a **tiny data service (or micro–KV store)**. It exposes HTTP APIs that allow users to save, fetch, update, and delete data entries. This makes it suitable for use cases like storing API keys, feature flags, session-like data, or temporary artifacts during development workflows. Compared to traditional databases, it intentionally avoids complexity—no heavy schema design, no large infrastructure footprint—just a straightforward storage layer that can be spun up quickly.

Technically, the project emphasizes **simplicity and deployability**. It is designed to run as a small service (often containerized), making it easy to integrate into local setups, CI pipelines, or lightweight production environments. The API-first design means it can be used by scripts, backend services, or even LLM/agent systems as a quick persistence layer. This aligns well with modern “tool-based” architectures where services are composed as small, interoperable components.

Conceptually, Stash fits into the broader trend: **file-like or flexible data stores for exploration rather than strict querying**. Instead of enforcing rigid schemas like SQL databases, it offers a looser, more natural storage model—closer to how developers think when they just need to “put something somewhere and retrieve it later.” That makes it particularly useful in agentic or iterative workflows where the structure of data may evolve over time.

In short, Stash is best understood as a **minimal, API-driven persistence layer**—not trying to replace databases, but to fill the gap between ad-hoc files and fully managed data systems.

## Example
```text
SESSION 1 · Monday morning
  you: I'm building a B2B SaaS for restaurants. Help me plan the pricing model.
stash: recall("context") → nothing found, fresh start
agent: Sure! For restaurant B2B SaaS, I'd suggest three tiers: Starter, Growth,
       and Enterprise.
  you: Let's avoid Stripe for now, too complex. We'll use a local payment provider.
stash: remember("avoid Stripe, use local payment provider")
stash: remember("building B2B SaaS for restaurants, planning pricing")
agent: Got it. Keeping suggestions away from Stripe. Shall we define the tier limits?
  you: Yes — Starter: 3 locations, Growth: 20, Enterprise: unlimited.
stash: remember("Starter: 3 locations, Growth: 20, Enterprise: unlimited")
stash: consolidate() → synthesizing episodes into facts...
  ...:   Days later
  you: Hey, let's continue working on my project.
stash: recall("current project context") → 3 facts found
stash: "B2B SaaS for restaurants, pricing model"
stash: "Avoid Stripe, use local payment provider"
stash: "Starter: 3 locations, Growth: 20, Enterprise: unlimited"
agent: Welcome back! Last time we defined your pricing tiers for the restaurant SaaS.
agent: Starter (3 locations), Growth (20), Enterprise (unlimited) — no Stripe, 
       local payment provider.
agent: Ready to work on the onboarding flow next?
  you: Exactly. Let's go.
  ...: (continue)
```
Zero repetition. Full context. Stash remembered everything.

## Working with Code Assistants

stash is not trying to replace a coding assistant’s built-in context window or its native product memory. 
It acts as an external, shared long-term memory layer that the assistant can call through MCP.

For coding assistants, the model still does the coding work as usual:

- reads files
- plans edits
- writes code
- runs tools/tests
Stash adds a separate memory system beside that workflow:

- The assistant can remember project decisions, preferences, failed approaches, goals, and working context.
- Later, in a new session, it can recall only the relevant memory instead of relying on huge chat history.
- In the background, stash consolidates raw notes into higher-level structures like facts, relationships,
  causal links, contradictions, goal progress, and failure patterns.

So with a coding assistant, the division is roughly:

- Native assistant memory:
Usually session context, chat history, or product-specific memory features tied to that tool/platform.
- Stash memory:
Persistent, self-hosted, model-agnostic memory that survives across sessions and can be shared across different MCP-compatible assistants.

Why that matters for coding assistants:

- If you switch from Claude Code to Cursor or another MCP client, the memory can still come with you.
- It can remember repo-specific conventions, architecture decisions, and “don’t do X, we already tried it” lessons.
- It helps avoid stuffing prior conversations into every prompt, which reduces repeated context and token waste.
- It can track longer-running project goals over days or weeks, not just one coding session.
So the practical answer is: Stash works with coding assistants as a companion memory backend, not as the coding engine itself.

Sources:

https://github.com/alash3al/stash
https://alash3al.github.io/stash/

## How Integrate Stash
Stash does not automatically read Cursor’s or Codex’s built-in memory. The shared-memory effect only happens
if both assistants are connected to the same stash MCP server and they actually use it during work.

For Cursor, its native memory stays inside Cursor. Same is true for Codex. Stash is a separate, 
shared memory service. If both Cursor and Codex write to and read from that same Stash, then switching
tools can preserve continuity.

To integrate Stash with a coding assistant:
- Run one shared Stash instance.
- The normal setup is docker compose up, which starts Postgres, pgvector, migrations, the MCP server, and background consolidation.
- Point coding assistants at that same MCP server.
- Codex CLI/IDE can connect to MCP servers, for example with:

```text
codex mcp add <name> --url <server-url>
Then verify with:
codex mcp list
```

- Do the same thing for other coding assistants (Claude Code, Qwen Code, etc.). Use a stable namespace convention. 
  This is the big practical step most people miss. If you want memory for “the same module,” both assistants 
  need to read/write the same namespace, for example:
```text
/projects/myrepo
/projects/myrepo/modules/auth
/projects/myrepo/modules/billing
```

   If Cursor writes to `/projects/foo/auth` and Codex reads `/auth`, they won’t meet in the same memory.

- Tell the agents to actually use stash.
