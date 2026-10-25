# Paper Summary: HarnessPro — Recursive Harness Self-Improvement with Pareto Optimization

arXiv:2610.26770 · October 20, 2026 · [Original paper](https://arxiv.org/html/2610.26770?utm_source=chatgpt.com)

## 1. Central idea

The paper introduces HarnessPro, a framework that automatically improves AI agent harnesses by analyzing previous execution trajectories, modifying harness implementations, and evaluating the resulting improvements.

Unlike earlier recursive self-improvement approaches that primarily optimize task success, HarnessPro optimizes two objectives simultaneously:

- Performance: Increase the percentage of tasks successfully completed.
- Cost: Reduce token consumption and monetary execution costs.

The central observation is that stronger agents do not necessarily need more reasoning, tool calls, or verification. Often, they can achieve better results by eliminating redundant operations and allocating computational resources more intelligently.

Instead of producing a single optimized harness, HarnessPro produces three configurations:

| Mode   | Optimization priority                                           |
| ------ | --------------------------------------------------------------- |
| Lite   | Minimize execution cost while preserving acceptable performance |
| Medium | Balance performance and cost                                    |
| Heavy  | Maximize task success while controlling cost                    |

These configurations represent different points on the Pareto frontier: the set of harnesses for which neither performance nor cost can be improved without worsening the other objective.

The authors report that, across three benchmarks using GPT-5.5 with Codex, HarnessPro's heavy mode improves pass rate by an average of 2.0 percentage points while reducing execution cost by 26.1% compared with RHO, an earlier harness optimization framework.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://arxiv.org\&sz=32)

arXiv



## 2. How HarnessPro works

HarnessPro uses a recursive improvement loop involving four specialized agents.

Simplified recursive optimization cycle. Tests are synthesized initially and reused during subsequent iterations.

The process consists of the following stages:

1\. Trajectory Analyzer: Runs a harness multiple times on representative tasks, examines execution traces, and identifies failure patterns, unnecessary tool calls, excessive exploration, and redundant reasoning.

2\. Evolution Planner: Uses these diagnoses to propose three alternative improvements, each targeting a different performance-cost trade-off. It also compares previously generated harnesses to identify effective modifications.

3\. Harness Editor: Implements the proposed modifications directly in the harness, including instructions, tools, skills, hooks, and verification policies. Each candidate is maintained in a separate workspace and committed to Git.

4\. Test Synthesizer and Candidate Selection: Generates executable tests from task descriptions and initial trajectories, then evaluates candidate harnesses using these fixed tests. Candidates that perform worse than the baseline or are Pareto-dominated are eliminated.

The surviving lite, medium, and heavy candidates become the starting points for the next iteration.

A particularly important distinction is that HarnessPro modifies executable harness behavior, not just prompts. It can change how an agent selects tools, allocates reasoning effort, processes tool outputs, and decides when to stop exploring and begin verification.

## 3. Experimental results

The authors evaluate HarnessPro on three benchmarks: Terminal-Bench 2, SWE-Bench Pro, and ProgramBench, using both GPT-5.5/Codex and GLM-5.2/Claude Code.

The following results use GPT-5.5 with Codex.

| Benchmark        | Method            | Pass rate | Cost/task |
| ---------------- | ----------------- | --------- | --------- |
| Terminal-Bench 2 | RHO               | 76.3%     | $1.09     |
|                  | HarnessPro Lite   | 72.9%     | $0.43     |
|                  | HarnessPro Medium | 76.3%     | $0.56     |
|                  | HarnessPro Heavy  | 80.8%     | $0.72     |
| SWE-Bench Pro    | RHO               | 80.0%     | $2.68     |
|                  | HarnessPro Lite   | 72.3%     | $0.80     |
|                  | HarnessPro Medium | 79.0%     | $1.26     |
|                  | HarnessPro Heavy  | 80.7%     | $1.97     |
| ProgramBench     | RHO               | 68.8%     | $3.59     |
|                  | HarnessPro Lite   | 64.3%     | $2.18     |
|                  | HarnessPro Medium | 67.9%     | $2.90     |
|                  | HarnessPro Heavy  | 69.6%     | $2.95     |

Mean values from Table 2 of the paper. HarnessPro results are averaged across repeated runs; uncertainty intervals are omitted for readability.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://arxiv.org\&sz=32)

arXiv

These results are significant because HarnessPro Heavy improves performance while reducing costs relative to RHO on all three benchmarks. Medium often achieves nearly the same performance at substantially lower cost.

The ablation experiments also show that simply lowering reasoning effort is not sufficient: it reduces costs but can seriously degrade task success. The combination of task-aware resource allocation, trajectory diagnosis, and test-based candidate evaluation is more effective.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://arxiv.org\&sz=32)

arXiv



## 4. What makes the approach interesting?

Three aspects stand out.

First, the optimization is empirical rather than purely LLM-driven. An LLM proposes changes, but executable tests and measured costs determine which changes survive. This helps prevent the optimization process from relying entirely on an LLM's subjective judgment.

Second, the system optimizes the entire harness. It can improve instructions, tool integration, runtime hooks, and verification procedures together. For example, a harness might learn to use lower reasoning effort for straightforward tasks, compress verbose tool outputs, or avoid repeatedly exploring files after sufficient evidence has been collected.

Third, the approach is recursive. Each optimization round builds on the strongest candidates from earlier rounds. Successful improvements can accumulate rather than being discarded after a single experiment.

## 5. Limitations

The approach has several practical limitations.

The optimization process itself can be expensive because it requires multiple task executions, LLM-based analysis, code modifications, and candidate evaluations. The reported per-task execution costs do not represent the full amortized cost of developing the optimized harness.

Additionally, generated tests are not equivalent to authoritative ground-truth tests. They may fail to detect subtle errors or reward incomplete solutions. The framework mitigates this through fixed validation tests and held-out benchmark evaluation, but it cannot eliminate the risk.

Finally, the experiments focus on software engineering and terminal-based tasks. It remains uncertain how effectively the resulting techniques generalize to other domains, such as document analysis, scientific research, or knowledge extraction.

## 6. Implications for SemOS

The most relevant idea for SemOS is trajectory-driven harness optimization.

SemOS already has specialized workflows for extracting topics, metrics, provisions, entities, and relationships from technical documents. The same approach could be applied to optimize these workflows:

- Record execution traces, token usage, tool calls, validation failures, and extraction quality.
- Analyze recurring failures and redundant operations.
- Generate candidate improvements to prompts, tool selection, context preparation, and verification.
- Evaluate candidates against a fixed corpus with known or independently validated extraction results.
- Retain configurations that provide the best quality-cost trade-offs.

For example, a metric-extraction workflow could use a lightweight configuration for simple prose, a balanced configuration for ordinary tables, and a more capable configuration for complex formulas or ambiguous metrological requirements.

This is an application of HarnessPro's principles, not something the paper directly evaluates.

My assessment: The paper's most important contribution is demonstrating that agent harnesses can be treated as empirically optimizable software systems, rather than static collections of prompts and tools. Its combination of execution traces, automated code modification, reproducible evaluation, and multi-objective optimization offers a practical foundation for improving sophisticated agent workflows.

The implementation is available in the authors' [HarnessPro GitHub repository](https://github.com/Gen-Verse/HarnessPro?utm_source=chatgpt.com).
