# Knowhere Agent Native Retrieval — Letting an agent navigate published documents

**Date:** 2026-09-26  
**Scope:** Explains how the retrieval agent explores Knowhere's published corpus, which tools it can call, and how selected evidence becomes the retrieval response.  
**Code root:** `ThirdParty-2/knowhere/packages/shared-python/shared/services/retrieval/`

## 1. Summary

Knowhere can let an agent explore a document collection instead of always choosing a fixed set of search results for it. The agent can inspect document outlines, filter sections, look up exact text, search for less obvious matches, read selected passages, inspect tables and images, and follow links between related documents. This lets it narrow down where evidence is likely to be before asking for the full text. Knowhere still checks the agent's chosen references and builds the final evidence response from the published corpus.

## 2. Details

### 2.1 Agentic Retrieval

Below is a typical agentic retrieval workflow:
- User enters a query
- Agent receives the query, analyzes the query, determines whether it needs to search for relevant documents/chunks. If yes, formulate a 'search query' and send the 'search query' to the selected knowledge base system, such as Knowhere
- The knowledge base system is essentially a search engine. It is essentially not agentic. The only places that LLMs may be used are possibly ranking the search results. It does not analyze the query, normally!
- The search can be exact search, hybrid search, SQL search, etc. It then sends the response back to the agent
- Agent analyzes the search results to determine whether to continue the search or it has enough information for its query and can generate the final answer.
- If it needs to continue the search, it formulates a new 'search query' and repeats the above until enough information is retrieved or a max tries is reached.

### 2.2 Request path and route choice

The retrieval execution path is `execution/plan.py` → `execution/routes.py` (also reachable through `app_service.py`). `run_retrieval_route()` applies the small-corpus optimization first: if the scoped chunk count is no greater than `top_k`, it loads and returns all eligible chunks as `small_corpus_all`. Otherwise, `use_agentic=False` selects the classic `classic_topk` route, which performs map-unit discovery, ranks candidates, and assembles results. `use_agentic=True` or an omitted value selects `agent_explore`.

The `agent_explore` route resolves a harness and calls `run_episode()`. `AGENT_EXPLORE_HARNESS` selects the provider implementation; the harness resolver supports the OpenAI tool-calling and Cursor SDK implementations (unrecognized or unset values resolve to the default OpenAI harness). Tool execution is provider agnostic: both harnesses dispatch through the same `agent_tools.REGISTRY`. The registry is also shared with the API `/mcp` server. Each call gets a fresh database session and carries the requesting user, namespace, document scope, and tool budget.

At episode end, agent references are resolved against the published corpus, checked against request scope and revision pins, and hydrated into retrieval results. The response identifies `router_used: "agent_explore"`, includes `referenced_chunks`, `results`, a `decision_trace`, and the episode `stop_reason`. `answer_text` is empty: this route retrieves evidence; it does not compose the user's final answer.

### 2.3 Where the namespace comes from

The retrieval route does not infer a namespace from the natural-language question. Namespace selection happens before `run_retrieval_query()` and therefore before Knowhere's retrieval agent explores documents.

There are two entry paths in this checkout:

- **MCP:** the `retrieval.query` tool in `apps/api/app/mcp/retrieval_server.py` accepts a `query`, but no namespace argument. It reads `x-knowhere-namespace` from the MCP HTTP request and normalizes a missing or blank header to `"default"`. It then calls `run_retrieval_query()` with that namespace. The MCP corpus tools use the same request-scoped namespace. The host application / agent that connects to this MCP server must therefore provide the header if it wants a non-default namespace.
- **REST:** `POST /api/v1/retrieval/query` and `POST /api/v2/retrieval/query` accept an optional `namespace` field in `RetrievalQueryRequest`. Missing or blank values become `"default"`; `execute_retrieval_query()` passes that value to `run_retrieval_query()`. The REST caller must choose and send a non-default namespace itself.

Neither path calls an LLM to choose a namespace. In the MCP tool implementation, a TODO explicitly describes a possible future intent-understanding step that could extract document, scope, and content-type hints from the query; the code says the module is “to be created,” and the step is not implemented. The MCP `retrieval.query` tool is itself a Knowhere tool called by an external MCP host/agent. The user-facing host that receives the typed question and decides which MCP server/header to use is outside this checkout; repository instructions identify the web frontend as a separate repository. Thus this code establishes the namespace source and default, but does not establish how a deployed host selects the namespace for a user who does not know about namespaces.

For the example question, “How to configure the embedding model name for my project ('ChenWeb')?”, the string `ChenWeb` in the question does not change the namespace. Unless the host sends `x-knowhere-namespace: ChenWeb` over MCP or the REST caller sends `{"namespace": "ChenWeb"}`, retrieval uses `default`.

**Candidate upstream issue:** clarify the intended user-facing namespace-selection flow for natural-language retrieval. In particular: should the host application select a namespace from the active project/workspace, should Knowhere expose namespace discovery or multi-namespace search, and what should happen when the user's wording mentions a project that differs from the active namespace? The current Knowhere retrieval code does not answer these product/integration questions. No issue has been filed from this workspace.

### 2.4 Agentic Retrieval and Knowhere

Knowhere has both roles.

- **As a corpus exposed through MCP**, Knowhere supplies search, outline, read, and related-document tools. 
The external host agent can run the loop you described. Knowhere calls this an agent-ready corpus. 
[Knowhere’s description](https://github.com/Ontos-AI/knowhere#step-2-agentic-retrieval)
- **Through Knowhere’s built-in `agent_explore` route**, Knowhere runs its *own* LLM tool-calling loop. 
  It sends the question to a model, lets the model choose corpus tools, feeds results back, and repeats 
  until the model selects evidence or a budget stops it. That is agentic retrieval inside Knowhere, 
  beyond ranking search results. See the 
  [route selection](/Users/cding/Workspace/ThirdParty-2/knowhere/packages/shared-python/shared/services/retrieval/execution/routes.py:62), 
  [model loop](/Users/cding/Workspace/ThirdParty-2/knowhere/packages/shared-python/shared/services/retrieval/agent_explore/harness/openai_harness.py:185), 
  [tool dispatch and feedback](/Users/cding/Workspace/ThirdParty-2/knowhere/packages/shared-python/shared/services/retrieval/agent_explore/harness/openai_harness.py:315), and 
  [stop budget](/Users/cding/Workspace/ThirdParty-2/knowhere/packages/shared-python/shared/services/retrieval/agent_explore/budget.py:40).

**Knowhere’s internal agent explores an already selected namespace.** It does not solve the earlier step of identifying 
the namespace from the user’s dialog. It also returns evidence for the calling agent to use; the route’s 
`answer_text` is empty. 
[Response assembly](/Users/cding/Workspace/ThirdParty-2/knowhere/packages/shared-python/shared/services/retrieval/execution/routes.py:305)

### 2.4 Open Questions
A typical scenario of using Knowhere should be:
1. When users ask questions, such as "How to configure the emebdding model name for my project ('ChenWeb')?", users
   have no idea about 'namespace', and most likely won't specify it. How does Knowhere know the namespace? In this specific example, the namespace is 'ChenWeb'. Apparently, it requires understanding the query, analyze it, and extract the namespace(s), which is quite undeterministic. It got to be an LLM who analyzes user queries, extracts the namespace(s),
   if any.
2. This means upon receiving a user request, Knowhere formulates a request to its LLM to extract the namespace, 
   which may return none, one or multiple namespaces. This needs to be confirmed in code.
3. A namespace may contain hundreds of thousands, or even millions of documents. Does Knowhere manage its namespaces 
   in a hierarchical way so that a namespace has a set of sub-namespaces, which may recursively have 
   their own sub-namespaces?

Need to answer these questions, and the answers MUST be based on reading the actual code.

Below are the answers.

**Who makes the MCP call?** An external agent host—such as Codex, Cursor, or Claude Code—receives the user’s 
question and decides whether to call a Knowhere tool. Knowhere also publishes a local MCP package for those 
hosts. Its `knowhere_search` tool accepts both `query` and an **optional, single** `namespace` argument; 
the package passes that argument through the SDK to the retrieval API. There is no namespace extraction step 
in that package’s code. See the [MCP tool registration](https://github.com/Ontos-AI/knowhere-node-sdk/blob/177fc97/packages/mcp/src/index.ts#L233-L246), [SDK forwarding](https://github.com/Ontos-AI/knowhere-node-sdk/blob/177fc97/src/knowledge/knowledge.ts#L469-L477), and [Knowhere’s MCP setup documentation](https://docs.knowhereto.ai/mcp).

A typical actual path is:

```text
User asks about the ChenWeb embedding model
  → external agent host receives the question
  → host agent may choose knowhere_search
  → host agent may supply namespace: "ChenWeb" in the tool call
  → MCP package forwards it to Knowhere retrieval
```

**How does the host agent know to supply `ChenWeb`?** The examined Knowhere code does not give it a guaranteed way. 
A host model *might* infer `ChenWeb` from the question and put it in the tool arguments, or the host application 
might supply project context. That decision belongs to the host; it is not an implemented Knowhere query-analysis 
stage. If the host omits `namespace`, retrieval uses `default`. The MCP tool schema makes the field optional, and 
the API’s [normalizer](/Users/cding/Workspace/ThirdParty-2/knowhere/packages/shared-python/shared/models/schemas/retrieval_namespace.py:6) supplies that default.

There is a second, distinct interface in the document: Knowhere’s **HTTP `/mcp` endpoint**. There, the caller must 
set `x-knowhere-namespace` on the HTTP request; its `retrieval.query` tool has no namespace argument. Its handler 
reads the header *before* starting retrieval. See the [HTTP MCP handler](/Users/cding/Workspace/ThirdParty-2/knowhere/apps/api/app/mcp/retrieval_server.py:118). 
The document describes this server interface, while the published local MCP package provides the tool 
argument described above.

**Direct answer to your central question:** Found no code in these Knowhere components that takes a 
namespace-free user question, calls an LLM to extract zero, one, or several namespaces, validates those choices, 
and then calls MCP. The user-to-namespace step is left to the external agent host or integrating application. 

**Conclusion**

Knowhere is not a complete Knowledge Base. A complete knowledge base means it implements an agentic loop.
Inputs are mainly:
- user query
- context (session history)

The knowledge base handles everything else. This is what SemOS does.

Is SemOS design correct? My answer is: this is just an opinion or design philosiphy. My idea behind SemOS
is to give users a complete solution.

Knowhere design is different. It serves as a tool. It assumes quite a few things for a client to use it, 
such as extracting namespaces.

## 3 Tools available to the agent

Tool names are registered as `corpus.*` tools. The authoritative agent-facing corpus model and usage rules are in `agent_tools/CORPUS_SCHEMA.md`, which is also used to form the `/mcp` instructions and agent system prompt.

| Tool | What it is for | Important behavior |
|---|---|---|
| `corpus.list_documents` | Inventory documents when the user asks for a corpus listing | Namespace-wide metadata. It is not intended as a question-answering starting point. |
| `corpus.outline` | Browse titles, summaries, and section paths | Returns section structure and counts without body text. Use the returned full `section_path` with `read`. |
| `corpus.node_filter` | Find sections by path/title or summary predicates | Predicates combine with AND; terms within one predicate combine with OR. It returns the complete matching set, rather than top-K. It does not search body text. |
| `corpus.grep` | Find known exact strings, identifiers, or numbers | Searches published `term_search_text`; `patterns` are OR alternatives in one call. Table-cell HTML is not scanned. |
| `corpus.recall` | Search when the answer location or wording is uncertain | Ranks results from lexical `path_content` and `term` channels, fused with reciprocal-rank fusion. A `vector` channel is reserved but is not implemented. |
| `corpus.read` | Read known section(s) or chunk(s) | Returns full body content, resolves PDF `SAME-AS` page pointers, and expands connected assets. Large tables are summarized with headers; use `query_table` for selected cells. |
| `corpus.query_table` | Select cells from a table chunk | Read-only SQL over one table, named `t`; writes, `ATTACH`, and multiple statements are rejected. Missing `LIMIT` is set to 50. |
| `corpus.assets` | Locate images/tables or find their hosting section | Asset locations are addresses, not their body text. Read by `chunk_id`; reverse host lookup is available. |
| `corpus.neighbors` | Explore related documents | Traverses document-level `related` graph edges only. |

The typical exploration pattern is: use `outline` or `node_filter` to locate a section, `grep` for an exact known phrase, or `recall` for uncertain phrasing; then `read` the resulting section/chunk. Read the corpus schema instructions before extending tool behavior: text and page chunks differ by parse track, asset chunks are rooted separately from their host body sections, and `SAME-AS` paths do not use the same path format as database section paths.

### 2.4 Corpus and evidence boundaries

These tools operate on the published database corpus (`documents`, `document_sections`, `document_chunks`, `graph_nodes`, and `graph_edges`), not parser-side `chunks.json` or `doc_nav.json`. Calls are scoped by user and namespace, with document scope and request filters passed through. `document_id` is the stable handle expected by follow-up tools; it is not a source filename.

The graph currently represents documents and their undirected `related` edges. It does not expose section or entity nodes for graph traversal. Image and table chunks are stored under a synthetic document root; their relationship to body chunks is represented by body-chunk `connect_to` references. A tool result may therefore identify a useful section or chunk without the asset's root path identifying its host.

Tool output is bounded before it is placed in model context. `ToolBudget` defaults to 12,000 rendered characters and 50 items per call; tools that return ranked lists clamp to the item ceiling. Complete-set tools such as `outline` and `node_filter` do not truncate their matched-set cardinality by this budget. Episode-level time/token budgets can also stop exploration. Errors from individual dispatches are returned to the agent as tool errors so it can recover where possible.

## 4 Code map

- Route selection, episode launch, reference resolution, and response assembly: `execution/routes.py`.
- Request fields and route context: `execution/query_request.py`, `execution/route_types.py`.
- Provider-neutral tool contract and registry: `agent_tools/registry.py`.
- Tool registrations and implementations: `agent_tools/tools/`.
- Agent-facing corpus semantics and tool-selection guidance: `agent_tools/CORPUS_SCHEMA.md`.
- Shared agent loop helpers and provider harnesses: `agent_explore/`.
- Agent-reference to published-chunk resolution: `agent_explore/ref_resolution.py` and `execution/reference_resolver.py`.

## 5. Known limitations

- Retrieval on the agent route is not answer generation; `answer_text` remains empty.
- Small corpora may take the all-results route regardless of `use_agentic`.
- Fuzzy recall currently uses lexical channels only; vector search is not implemented.
- Graph traversal is limited to related documents, with no section/entity graph nodes.
- `grep` does not inspect raw table-cell HTML; use table reading/query tools for table contents.
