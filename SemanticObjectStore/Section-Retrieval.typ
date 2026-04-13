
== Retrieval System

This is a Hybrid Retrieval System, combining file-based, vector, keyword, graph, and memory-aware, all under one broker.

Retrieve results should contain:

- artifact title
- logical path
- version
- snippet
- chunk ID
- score
- citation locator
- why-it-matched metadata

That last field is useful for debugging agent behavior.

Example:

```json
{
  "why_matched": {
    "keyword_terms": ["versioning", "citation"],
    "semantic_similarity": 0.81,
    "filters_applied": ["collection:/projects/semos"]
  }
}
```

=== BM25 / keyword / full-text

Full-text search is useful for:

- exact identifiers
- filenames
- acronyms
- code symbols
- rare terms
- quoted strings

=== Vector Search

Vector search (semantic search) can be useful for:

- conceptual similarity
- paraphrase matching
- fuzzy recall
- “find related discussions”

It is important that do not use semantic search alone. Use it with full-text search.

=== Graph Retrieval

Graph retrieval is useful for:
- related concepts
- user/entity/project relationships
- contradictions
- updates over time
- fact lineage

It can be useful to answer questions, such as:

- “what else is connected to this?”
- “what changed?”
- “what supports this claim?”
- “which projects relate to this preference?”

=== Memory-aware retrieval

This is the differentiator. SemOS should rank by more than relevance. It uses a scoring function like:

```text
final_score =
  semantic_similarity * w1 +
  bm25_score          * w2 +
  graph_proximity     * w3 +
  recency             * w4 +
  salience            * w5 +
  scope_match         * w6 +
  user_specificity    * w7 +
  trust/provenance    * w8
```

Where:

- *recency* matters more for conversations/tasks
- *salience* matters more for preferences/goals
- *scope_match* matters a lot
- *trust/provenance* matters for answers that cite artifacts

This is what turns retrieval into memory.

=== Context Assembly Policy

The system should build context in layers.

For each user turn, always include:

1. system instructions
2. core memory
3. recent working memory
4. current task state

Retrieve conditionally:

5. episodic memories
6. semantic memories
7. artifact chunks
8. graph neighbors
9. summaries of large retrieved clusters

Then assemble a context bundle like:

```text
<context_bundle>
  <core_memory>...</core_memory>
  <recent_context>...</recent_context>
  <relevant_memories>...</relevant_memories>
  <relevant_artifacts>...</relevant_artifacts>
  <supporting_facts>...</supporting_facts>
</context_bundle>
```

Do not dump raw retrieval results into the prompt. Normalize them into:

- concise fact cards
- summarized evidence blocks
- provenance-preserving snippets

=== Real Memory System

A real memory subsystem needs *write policies*, not just read policies.

What gets written to core memory should include only only things that are:

- durable
- user-relevant
- high confidence
- likely to matter across many future turns

Examples:

- stable preferences
- durable identity/context
- long-running projects
- standing instructions

What stays out of core memory:

- transient chat details
- random facts from one turn
- weak inferences
- most retrieved document facts

Those go to episodic or semantic memory instead.

==== Memory Write Pipeline

When a conversation ends or crosses a milestone:

1. detect candidate memories
2. classify by type
3. score confidence + durability
4. deduplicate against existing memory
5. merge / update / supersede
6. optionally ask for confirmation for sensitive long-lived facts
7. write to appropriate memory class

This is where consolidation happens. Mem0 explicitly frames memory as extraction, consolidation, retrieval, and forgetting rather than a naive transcript replay. ([Mem0][4])

==== Updating, Contradiction, and Forgetting

A real memory layer must not only remember. It must also:

- revise
- supersede
- decay
- forget

*Example*

Old memory:

```text
User prefers short answers.
```

Later evidence:

```text
User prefers detailed architecture explanations.
```

Do not silently overwrite. Keep lineage:

```text
Memory M1: user prefers short answers
status: superseded
superseded_by: M2

Memory M2: user prefers detailed architecture explanations for systems topics
status: active
```

==== Types of Forgetting

Use at least three:

1. Soft Decay: Lower retrieval weight over time
2. Archival Demotion: Keep it, but rarely retrieve it
3. Hard Delete: For explicit forget requests, privacy needs, or wrong facts

This matches the direction modern memory systems are taking: memory should evolve, consolidate, and sometimes
forget. ([Supermemory][2])

=== Retrieval Flow

*Step 1*: classify query intent

Determine whether it is primarily:

- personal memory
- recent conversation continuity
- artifact/KB retrieval
- mixed
- exploration

*Step 2*: choose retrieval blend

Examples:

Personal question: “What do I usually prefer?”

- core memory first
- semantic memory second
- episodic support third

Knowledge question: “What did the SemOS spec say about path-native exploration?”

- artifact BM25 + vector
- then related semantic facts
- then graph neighbors

Mixed question: “How does my SemOS idea compare to Supermemory?”

- core memory for your preferences
- artifact/project memory for SemOS
- external KB if needed
- graph links between concepts

*Step 3*: assemble compact evidence: Retrieve 10–30 items internally, but only inject 3–10 high-value ones into prompt context.

*Step 4*: learn from the turn: Update:

- working memory immediately
- episodic summary after turn/session
- core memory only if durable

