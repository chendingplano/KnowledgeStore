# Search Engine API — one hybrid search for the whole server

**Date:** 2026-11-11 \
**Scope:** What the `searchengine` package is, who calls it, what it replaced, and where its limits are. Open it before adding a search call, changing how results are ranked, or touching the benchmark's traces.
**Code root:** `ChenWeb/server/api/searchengine`

**Traceability — openspec:**
- `ChenWeb/openspec/changes/hybrid-search-engine-api/proposal.md` — why this exists
- `ChenWeb/openspec/changes/hybrid-search-engine-api/design.md` — rationale, alternatives considered, risks
- `ChenWeb/openspec/changes/hybrid-search-engine-api/tasks.md` — implementation log, with the golden-comparison result and the open items
- `ChenWeb/openspec/changes/hybrid-search-engine-api/specs/hybrid-search-engine/spec.md` — the requirements. **The change is not archived yet, so there is no `openspec/specs/` copy.** Update the spec, not just this doc, if behaviour changes — this doc explains the feature for humans and points at code; the spec is the contract for agents.

Related: [Hybrid Search capsule](../../../Capsules/coding-capsules/llm-wiki/hybrid-search.md) (how the search works end to end, tunables, benchmark), [Artifact Search module](../../modules/module-artifact-search.md), [Provisions reviewer](2026111002-devdoc-provisions-reviewer.md).

## Summary

The knowledge base finds things two ways at once: by the words in a query (keyword search) and by meaning (vector search, which also bridges Chinese and English). The two ranked lists are merged into one. That merge used to exist in several places: the web search page and the agent tool had one copy, and the document reviewers and two clustering steps used a second, simpler copy that could not filter before ranking and whose keyword half never matched anything.

There is now one search engine, a small Go package called `searchengine`. Every part of the server that needs "things like this" or "things matching this" asks it:

- the search page, the per-type search routes, the agent's knowledge search, the effort loop and the benchmark (through a thin adapter in `kbhandler`);
- the metrics, inventory-item, entity and provisions reviewers, which ask for similar items in *other* documents;
- the entity and inventory-item clustering steps and the object-relation graph.

What a caller can ask for: a text, or "artifacts similar to this indexed one"; filters (types, documents, exclusions, scope) that apply *before* ranking, so a document's own items cannot crowd out other documents; and optional conditions (required or excluded keywords, a minimum similarity). Each result says how it was found — its rank in each list and its similarity — so a caller can decide whether a match is good enough instead of trusting the fused score.

The fused score only orders one response. It is not a probability, and it is not comparable between queries: the top hit of a query with nothing relevant still scores about 0.033. Ask for a minimum similarity when the question is "is anything close enough?".

## Where things live

- **The engine:** `ChenWeb/server/api/searchengine/`. `engine.go` runs a search; `lexical.go` and `vector.go` build the two lists; `filters.go` renders the filters; `similar.go` is the ready-made "find similar to this artifact" call; `types.go` is the request and response.
- **The adapter:** `ChenWeb/server/api/kbhandler/search_registry.go` turns the web request's parameters into an engine request and the response back into the page's JSON. `searchengine_hooks.go` registers the two pieces that live in `kbhandler` (the query embedder and the keyword-extraction step), because the engine cannot import `kbhandler`.
- **Reviewers:** `ChenWeb/server/api/doc-reviews/similar.go`.
- **Regression check:** `kbhandler/search_golden_live_test.go` records the results of a fixed set of queries from a development database and compares them later. It is live, read-only and runs only when `SEARCH_GOLDEN_MODE` is set; the recorded files are local.

Settings are the existing ones (`SEARCH_SEMANTIC_ENABLED`, `SEARCH_LEXICAL_BACKEND`, `[artifact_search]` weights, `SEARCH_QUERY_KEYWORDS*`) plus `ARTIFACT_CONNECT_MIN_COSINE` (default 0.75) and `ARTIFACT_CONNECT_MAX_LINKS` (default 10) for the similar-artifact lookups. The 0.75 floor was tuned for the previous embedding model and has not been recalibrated for bge-m3.

## How the move was checked

Before any code moved, 65 queries (generated benchmark questions of every artifact type, free text with and without a type, a second page, type and document filters, a facet) were run and their totals, order, scores and snippets saved, in four configurations. After the move the default configuration (hybrid, ParadeDB) matched on all 65, hybrid on Postgres matched on all 65, and keyword-only on Postgres matched on all 65. Keyword-only on ParadeDB matched on 58 and differed on 7 long Chinese questions, where the old code returned nothing and the engine returns results: the old statement failed and silently fell back to a Postgres search that cannot match them.

## Known limitations

- **Keyword-only mode is a little different.** When there is no query vector (semantic search off, no embedding model, or the model call failed), results carry the fused score instead of the raw keyword score, the snippet is the stored text (ParadeDB) or a highlight (Postgres), and at most 200 results can be paged; before, paging was unlimited. If the engine itself fails, the search retries once in this mode.
- **`total` counts keyword matches only,** so it can undercount results found only by meaning.
- **A cosine floor needs a vector.** The similar-artifact lookups error when no vector is available; the reviewers and the object graph pass that error on, the clustering steps log it and skip the item.
- **Filter conditions can return fewer results than asked for,** because they are checked on the fused candidates (at most 200 per list). The response counts what each condition removed.
- **The embedder and keyword extractor are registered by `kbhandler` at start-up.** A program that does not link `kbhandler` searches by keywords only.
- **Traces are rebuilt from the engine's lists,** not read in a separate database snapshot as before, so a trace can differ from the search only through bugs in the conversion, which the benchmark flags ("trace differs from the search results").
- **Not yet done** (see `tasks.md`): separate tests for each `search-query-keywords` scenario on the engine path, a disposable-database test for the criteria, and a run of the benchmark page before and after.
