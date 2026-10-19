# MuscleMemory — Open-source procedural memory for AI agents

Repository: [TheWariend/MuscleMemory](https://github.com/TheWariend/MuscleMemory?utm_source=chatgpt.com)\
Generated: ChatGPT \
Date: 2026/10/18

MuscleMemory is an open-source system that enables AI agents to learn reusable procedures from previous tasks, remember successful approaches, and avoid repeating past mistakes. It focuses on procedural memory—knowledge about how to accomplish something—rather than simply remembering conversations or facts.

For example, when Codex fixes a bug, MuscleMemory can observe which files were modified, what approach worked, and which tests passed. Once that procedure has been verified and approved, MuscleMemory can retrieve it when another agent encounters a similar task. The next agent receives a concise set of instructions instead of having to rediscover the solution from scratch.

The interesting idea is that experience becomes reusable knowledge across sessions and even across different agent harnesses. A procedure learned by Codex can subsequently help Claude Code or Cursor. MuscleMemory is designed to operate alongside these agents rather than replace their reasoning, tools, or execution environment.

## 1. How it works

![MuscleMemory](../images/image_2026101801.png)

Its learning mechanism includes several safeguards:

- Success verification: A skill requires two subsequent sessions with matching actions and successful execution of its stored test command. The original training session does not count.
- Failure learning: Failed approaches can become warnings and troubleshooting instructions.
- Human approval: Learned skills must be approved in the dashboard before agents can receive them, unless automatic approval is explicitly enabled.
- Context checking: Native hooks inspect current project files and avoid injecting skills when their recorded file context no longer matches.
- Selective retrieval: When no useful skill matches, nothing is added to the agent's context.

An important distinction: MuscleMemory does not normally replay a recorded coding session as an executable macro. It retrieves procedural guidance that the agent uses to perform the task.

## 2. Architecture and retrieval

MuscleMemory is implemented primarily in Python, using FastAPI and SQLAlchemy. It provides REST APIs, an MCP server, Python and TypeScript SDKs, and a dashboard.

Its retrieval design is particularly relevant to knowledge systems.

| Component         | Implementation                              |
| ----------------- | ------------------------------------------- |
| Keyword search    | BM25                                        |
| Semantic search   | MiniLM (`all-MiniLM-L6-v2`, 384 dimensions) |
| Exact matching    | File paths and commands                     |
| Candidate fusion  | Reciprocal Rank Fusion (RRF)                |
| Ranking           | Relevance, reliability, freshness           |
| Local storage     | SQLite                                      |
| Team storage      | PostgreSQL + pgvector                       |
| Agent integration | Hooks, MCP, SDKs                            |
| Recall overhead   | No LLM call by default                      |

The final ranking formula is:

$$S=0.75R+0.20C+0.05F$$

Where $R$ represents relevance, $C$ reliability, and $F$ freshness.

The system considers skills ready only when they meet additional requirements, including sufficient verification, a minimum reliability score, recent validation, and compatible tools and permissions.

It sends agents a compact memory pointer limited to approximately 350 tokens by default. The full skill remains available through an inspection tool.

See the [architecture documentation](https://github.com/TheWariend/MuscleMemory/blob/main/docs/how-it-works.md?utm_source=chatgpt.com).

## 3. Performance and limitations

The developers report the following results from controlled benchmarks.

| Metric         | Codex     | Claude Code |
| -------------- | --------- | ----------- |
| Input tokens   | −25.5%    | −43.5%      |
| Tool calls     | −30.4%    | −30.0%      |
| Execution time | −28.2%    | +2.9%       |
| Task success   | Unchanged | Unchanged   |

The Codex benchmark consisted of 18 sessions across three repeated coding tasks. The Claude Code benchmark had eight sessions, using skills originally learned by Codex.

The results suggest that procedural memory can meaningfully reduce redundant exploration. However, these are small, developer-published experiments, not independent evidence of broad effectiveness. Most importantly, they demonstrate efficiency improvements rather than increased task success.

Other limitations include incomplete session capture, reliance on explicit tests to verify coding tasks, untested cross-repository retrieval, and limited evidence at large scale.

See [benchmarks and methodology](https://github.com/TheWariend/MuscleMemory/blob/main/docs/benchmarks.md?utm_source=chatgpt.com).

## 4. Relevance to SemOS

I see MuscleMemory as potentially complementary to SemOS rather than a replacement for its existing knowledge infrastructure.

SemOS manages document knowledge, extracted artifacts, relationships, and exploration. MuscleMemory addresses a different problem: remembering how an agent successfully performs work.

For example, a SemOS agent might discover a reliable procedure for extracting metrics from complex tables in technical standards, including handling merged cells, units, and cross-page references. MuscleMemory's conceptual approach could capture that successful procedure so future agent sessions would not need to rediscover it.

An important caveat is that MuscleMemory's automatic verification currently centers on coding tasks with passing tests. For SemOS document-processing workflows, you would need domain-specific verification—such as schema validation, extraction-quality evaluation, or human review—to establish that a procedure truly succeeded.

I would distinguish three types of reusable knowledge:

| Type                   | SemOS example                                               |
| ---------------------- | ----------------------------------------------------------- |
| Declarative knowledge  | A standard defines a temperature limit of 8°C               |
| Procedural knowledge   | How to extract temperature requirements from tables         |
| Experiential knowledge | Which extraction approach failed on a particular PDF layout |

MuscleMemory is primarily concerned with the second and third types.

My assessment: MuscleMemory is worth studying for its capture–verification–retrieval loop, especially its approach to reliability and preventing stale skills from being injected into agent context. Since you are integrating Pi into SemOS, a useful future architecture would let Pi execute tasks while SemOS stores reusable procedures and their evidence.

The project's most valuable contribution is not its embedding model or search algorithm, but its attempt to turn observed agent behavior into verified, transferable procedural knowledge. Its current maturity is still early, so I would treat it as a reference implementation to evaluate rather than an established production dependency.

Sources: [repository](https://github.com/TheWariend/MuscleMemory?utm_source=chatgpt.com), [implementation documentation](https://github.com/TheWariend/MuscleMemory/blob/main/docs/how-it-works.md?utm_source=chatgpt.com), [roadmap](https://github.com/TheWariend/MuscleMemory/blob/main/docs/roadmap.md?utm_source=chatgpt.com).
