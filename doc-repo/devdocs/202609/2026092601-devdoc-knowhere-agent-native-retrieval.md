# Knowhere Agent Native Retrieval — Letting an agent navigate published documents

**Date:** 2026-09-26  
**Scope:** Explains how the retrieval agent explores Knowhere's published corpus, which tools it can call, and how selected evidence becomes the retrieval response.  
**Code root:** `ThirdParty-2/knowhere/packages/shared-python/shared/services/retrieval/`

## Summary

Knowhere can let an agent explore a document collection instead of always choosing a fixed set of search results for it. The agent can inspect document outlines, filter sections, look up exact text, search for less obvious matches, read selected passages, inspect tables and images, and follow links between related documents. This lets it narrow down where evidence is likely to be before asking for the full text. Knowhere still checks the agent's chosen references and builds the final evidence response from the published corpus.

## Details

### Request path and route choice

The retrieval execution path is `execution/plan.py` → `execution/routes.py` (also reachable through `app_service.py`). `run_retrieval_route()` applies the small-corpus optimization first: if the scoped chunk count is no greater than `top_k`, it loads and returns all eligible chunks as `small_corpus_all`. Otherwise, `use_agentic=False` selects the classic `classic_topk` route, which performs map-unit discovery, ranks candidates, and assembles results. `use_agentic=True` or an omitted value selects `agent_explore`.

The `agent_explore` route resolves a harness and calls `run_episode()`. `AGENT_EXPLORE_HARNESS` selects the provider implementation; the harness resolver supports the OpenAI tool-calling and Cursor SDK implementations (unrecognized or unset values resolve to the default OpenAI harness). Tool execution is provider agnostic: both harnesses dispatch through the same `agent_tools.REGISTRY`. The registry is also shared with the API `/mcp` server. Each call gets a fresh database session and carries the requesting user, namespace, document scope, and tool budget.

At episode end, agent references are resolved against the published corpus, checked against request scope and revision pins, and hydrated into retrieval results. The response identifies `router_used: "agent_explore"`, includes `referenced_chunks`, `results`, a `decision_trace`, and the episode `stop_reason`. `answer_text` is empty: this route retrieves evidence; it does not compose the user's final answer.

### Where the namespace comes from

The retrieval route does not infer a namespace from the natural-language question. Namespace selection happens before `run_retrieval_query()` and therefore before Knowhere's retrieval agent explores documents.

There are two entry paths in this checkout:

- **MCP:** the `retrieval.query` tool in `apps/api/app/mcp/retrieval_server.py` accepts a `query`, but no namespace argument. It reads `x-knowhere-namespace` from the MCP HTTP request and normalizes a missing or blank header to `"default"`. It then calls `run_retrieval_query()` with that namespace. The MCP corpus tools use the same request-scoped namespace. The host application / agent that connects to this MCP server must therefore provide the header if it wants a non-default namespace.
- **REST:** `POST /api/v1/retrieval/query` and `POST /api/v2/retrieval/query` accept an optional `namespace` field in `RetrievalQueryRequest`. Missing or blank values become `"default"`; `execute_retrieval_query()` passes that value to `run_retrieval_query()`. The REST caller must choose and send a non-default namespace itself.

Neither path calls an LLM to choose a namespace. In the MCP tool implementation, a TODO explicitly describes a possible future intent-understanding step that could extract document, scope, and content-type hints from the query; the code says the module is “to be created,” and the step is not implemented. The MCP `retrieval.query` tool is itself a Knowhere tool called by an external MCP host/agent. The user-facing host that receives the typed question and decides which MCP server/header to use is outside this checkout; repository instructions identify the web frontend as a separate repository. Thus this code establishes the namespace source and default, but does not establish how a deployed host selects the namespace for a user who does not know about namespaces.

For the example question, “How to configure the embedding model name for my project ('ChenWeb')?”, the string `ChenWeb` in the question does not change the namespace. Unless the host sends `x-knowhere-namespace: ChenWeb` over MCP or the REST caller sends `{"namespace": "ChenWeb"}`, retrieval uses `default`.

**Candidate upstream issue:** clarify the intended user-facing namespace-selection flow for natural-language retrieval. In particular: should the host application select a namespace from the active project/workspace, should Knowhere expose namespace discovery or multi-namespace search, and what should happen when the user's wording mentions a project that differs from the active namespace? The current Knowhere retrieval code does not answer these product/integration questions. No issue has been filed from this workspace.

### Tools available to the agent

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

### Corpus and evidence boundaries

These tools operate on the published database corpus (`documents`, `document_sections`, `document_chunks`, `graph_nodes`, and `graph_edges`), not parser-side `chunks.json` or `doc_nav.json`. Calls are scoped by user and namespace, with document scope and request filters passed through. `document_id` is the stable handle expected by follow-up tools; it is not a source filename.

The graph currently represents documents and their undirected `related` edges. It does not expose section or entity nodes for graph traversal. Image and table chunks are stored under a synthetic document root; their relationship to body chunks is represented by body-chunk `connect_to` references. A tool result may therefore identify a useful section or chunk without the asset's root path identifying its host.

Tool output is bounded before it is placed in model context. `ToolBudget` defaults to 12,000 rendered characters and 50 items per call; tools that return ranked lists clamp to the item ceiling. Complete-set tools such as `outline` and `node_filter` do not truncate their matched-set cardinality by this budget. Episode-level time/token budgets can also stop exploration. Errors from individual dispatches are returned to the agent as tool errors so it can recover where possible.

### Code map

- Route selection, episode launch, reference resolution, and response assembly: `execution/routes.py`.
- Request fields and route context: `execution/query_request.py`, `execution/route_types.py`.
- Provider-neutral tool contract and registry: `agent_tools/registry.py`.
- Tool registrations and implementations: `agent_tools/tools/`.
- Agent-facing corpus semantics and tool-selection guidance: `agent_tools/CORPUS_SCHEMA.md`.
- Shared agent loop helpers and provider harnesses: `agent_explore/`.
- Agent-reference to published-chunk resolution: `agent_explore/ref_resolution.py` and `execution/reference_resolver.py`.

## Known limitations

- Retrieval on the agent route is not answer generation; `answer_text` remains empty.
- Small corpora may take the all-results route regardless of `use_agentic`.
- Fuzzy recall currently uses lexical channels only; vector search is not implemented.
- Graph traversal is limited to related documents, with no section/entity graph nodes.
- `grep` does not inspect raw table-cell HTML; use table reading/query tools for table contents.
