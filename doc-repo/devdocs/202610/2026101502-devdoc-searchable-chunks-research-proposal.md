# Searchable chunks — research and a cost-controlled processor proposal

**Date:** 2026-10-15 \
**Status:** Research and proposal; NOT IMPLEMENTED. Requested as a devdoc to preserve findings and the proposed direction. This is not a shipped-behavior description or an approved implementation contract. \
**Scope:** Make the chunks produced by ChenWeb's document processor useful for exact, lexical, semantic, bilingual, and evidence-oriented retrieval without requiring generative model calls for every chunk. \
**Code root:** `ChenWeb/server/api/doc-processing/`, `ChenWeb/server/api/kbsearch/`, `ChenWeb/server/api/kbhandler/` \
**Reviewed baseline:** ChenWeb commit `06c4fa452ff7bc234e01e1b05ad00eb3bdeb8da9`; KnowledgeStore hybrid search design commit `e65f2db12d3d8498383e6d634256dd87ee0b3887`. Working source was also inspected; no application code was changed. \
**Cost scope:** 1 million, 10 million, and 100 million searchable units; CPU-only ingestion with optional shared GPU embedding service. These scenarios were accepted by the owner. Workload sizes, throughput, and budgets below are planning assumptions, not measurements.

## Summary

A chunk should carry enough information to explain where it came from: the document, edition, section, nearby heading, and any table caption or headers it needs. Most of that information already exists in the parsed document and can be attached with ordinary software. Keyword extraction can also run without a generative model. Categories should come from existing document metadata and a small, controlled vocabulary, with uncertain classifications left explicitly uncertain.

The recommended first implementation makes every eligible chunk searchable with BM25, then adds one multilingual embedding per ordinary chunk through a separate, retryable queue. It keeps the source text, lexical search text, and embedding input separate. Search returns compact matches; a follow-up inspection retrieves the exact source revision, neighboring text, or parent section when needed. Unchanged embedding inputs are reused rather than paid for again.

This is more than adding keywords to `.chunks`. The current chunk artifact is a line-range index, the current database row describes a whole chunking run, and no chunk search registry partition exists. The proposal adds durable per-chunk records, structural context, a chunk search projection, independent readiness states, and measured retrieval quality. It preserves the existing document-processor phases and starts without per-chunk generated summaries, translated keywords, or automatic category creation.

## 1. Findings from the actual implementation

Read these together:

- [Document processor capsule](../../../Capsules/coding-capsules/doc-processor/+CAPSULE.md).
- [Chunking capsule](../../../Capsules/coding-capsules/chunking/+CAPSULE.md).
- [Hybrid search design, updated against implementation](../../../Capsules/coding-capsules/full-text-search/hybrid-kb-fts-design.md).
- [Local Hister review](../../../Reviews/review-search-engine-hister.typ).
- [Canonical line-file specification](../../specs/202604/2026042101-spec-line-file.md).

### 1.1 What exists and what is missing

| Area | Verified current behavior | Consequence for this proposal |
|---|---|---|
| Processor lifecycle | Chunking is mandatory Phase A, after static analysis; document metadata extraction follows chunking. Configurable extractors run in Phase B. Phase C supports `PostProcessIndexer`. | Build chunk structure in Phase A; finish metadata-dependent projections in Phase C. Do not depend on optional topic/summary generation. |
| Chunk storage | `.chunks` stores ordered regular/overlap line ranges. `kb.chunks` stores a run summary, not one text record per chunk. | Add durable chunk items and revision identity; retain `.chunks` compatibility. |
| Existing context | `buildDocContextLine` composes title and document number for extraction. `canonicalChunkInputText` shares byte-identical document/line input across LLM consumers. | Extend search context independently; do not casually change shared LLM serialization or destroy cross-processor prompt-cache reuse. |
| Structure | Static analysis recognizes/corrects `heading-N`, table, formula, and list types. Canonical lines retain page, font, size, coordinates, and text. | Derive section ancestry deterministically from finalized lines, with uncertainty handling. A heading label alone is not a complete section tree. |
| Size | Default `CHUNK_SIZE=300` counts serialized bytes, including line serialization overhead; protected runs can exceed the target. | Do not interpret this as 300 tokens or import a token recommendation without measuring actual content. |
| LLM coupling | `NewFixedSizeChunkingService` loads topic/summary prompts and models and panics when `EMBEDDING_MODEL_NAME` is absent. | A lexical-only chunker needs construction/configuration separated from optional topic, summary, and embedding services. |
| Chunk connections | `kb.chunk_ranges` and `ChunkConnectionID(recordID, block.Index)` support line-overlap navigation; range refresh occurs in downstream indexing paths. | Reuse identity mapping and make chunk-range refresh owned by the chunk lifecycle. |
| Retrieval | Registry BM25, PostgreSQL FTS fallback, and optional cosine/RRF retrieval already exist; there is no chunk registry writer or partition. | Extend the shared registry instead of introducing a second search engine. |
| Registry replacement | Common family replacement deletes and inserts without one transaction. | Do not copy that partial-publication failure mode into chunk indexing. |
| Embeddings | Registry vectors are 1024-dimensional; semantic search is flag-gated and best-effort. Existing helpers can batch/retry, but do not provide the proposed input-addressed chunk cache. | Reuse clients and telemetry; add durable jobs, revisions, and exact invalidation. |
| Keywords/governance | There is an ontology keyword family and a standalone observe-mode mention collector, explicitly not wired into Phase C. Document facets already have deterministic/metadata tiers. | Reuse approved vocabulary and facet facts where applicable. Do not assume the mention collector is a production bilingual keyphrase extractor or activate ontology terms from chunk extraction. |

Source files include `fix-size-chunking.go`, `chunking-processor.go`, `processor_plan.go`, `control.go`, `input_lines.go`, `extract-entity-relation.go`, `structure-static-analyzer.go`, `connections_store.go`, `search_indexing.go`, `search_indexing_embedding.go`, `facet_tier1.go`, `facet_tier2.go`, and `keyword_mention_collector.go` under `ChenWeb/server/api/doc-processing/`.

The capsule has some historical wording that differs from code: `runPostProcessIndexing` now persists runtime failure status, and declared `Requires`/`Produces` values are descriptive rather than an automatically executed dependency graph. Implementing this proposal must update registration, controller behavior, status handling, and tests; adding declarations alone will not execute it. Basic chunk search should also not be blocked by an unrelated metadata LLM failure.

## 2. Research findings

The relevant evolution is from term matching, through independent passage embeddings, to context-aware representations. More expensive segmentation or generated context can help particular workloads, but they are not prerequisites for a sound retrieval substrate. The horizontal comparison below considers information gained per ingestion cost rather than model sophistication.

### 2.1 Context matters, but generated context is one way to obtain it

Anthropic's contextual retrieval constructs short, chunk-specific descriptions using the whole document, then indexes that context with the chunk. Its reported top-20 retrieval failure rate fell from 5.7% to 2.9% with contextual embeddings plus BM25, and to 1.9% with reranking. These are experiment-specific results, not expected ChenWeb gains. The report also found limited benefit from generic document summaries. [Source: Anthropic contextual retrieval](https://www.anthropic.com/engineering/contextual-retrieval).

**Design inference:** A technical standard often already identifies the missing context explicitly: standard number, edition, chapter title, subsection, equipment name, table title, units, or an applicability statement. Recover these before asking a generative model to restate them. This deterministic replacement for generated prose must be tested; the Anthropic experiments do not validate it directly.

### 2.2 Hister provides a useful low-cost reference, with limits

This review pins Hister to commit `ef9c8081e4056310a4c9ab8f0b878a06c5fbe6d2`, dated 2026-10-14, rather than relying on changing `master` or the September review.

- Its embedder composes body embedding inputs from a configured prefix, bounded title/language context, and chunk content. Richer metadata has a dedicated vector; description and document keywords are not repeated in every body chunk. Chapter ancestry would be our addition. [Pinned embedder source](https://github.com/asciimoo/hister/blob/ef9c8081e4056310a4c9ab8f0b878a06c5fbe6d2/server/vectorstore/embedder.go).
- Its structural chunker uses lightweight boundaries and approximate token counts. Its durable embedding work set uses bounded workers, retries, quarantine, and cancellation. Borrow workload separation and backpressure, while using ChenWeb's existing canonical structure and model tokenizer. [Tokenizer](https://github.com/asciimoo/hister/blob/ef9c8081e4056310a4c9ab8f0b878a06c5fbe6d2/server/vectorstore/tokenizer.go), [embedding queue](https://github.com/asciimoo/hister/blob/ef9c8081e4056310a4c9ab8f0b878a06c5fbe6d2/server/indexer/embedding_queue.go).
- It replaces document vectors transactionally and limits semantic matches per document. This is useful for publication and diversity. Its verified update path does **not** demonstrate a per-chunk content-addressed embedding cache. That cache is our proposed improvement. [PostgreSQL vector store](https://github.com/asciimoo/hister/blob/ef9c8081e4056310a4c9ab8f0b878a06c5fbe6d2/server/vectorstore/postgres.go), [update path](https://github.com/asciimoo/hister/blob/ef9c8081e4056310a4c9ab8f0b878a06c5fbe6d2/server/indexer/update.go), [candidate selection](https://github.com/asciimoo/hister/blob/ef9c8081e4056310a4c9ab8f0b878a06c5fbe6d2/server/vectorstore/vectorstore.go).
- Its web client blends normalized lexical scores with similarity; that is not evidence of cross-encoder reranking or a universal server-side RRF contract. ChenWeb should keep its own fusion on the server. Its MCP discovery/preview/history pattern is worth borrowing for bounded search followed by exact inspection. [Web merge](https://github.com/asciimoo/hister/blob/ef9c8081e4056310a4c9ab8f0b878a06c5fbe6d2/webui/app/src/lib/search-results.ts), [MCP implementation](https://github.com/asciimoo/hister/blob/ef9c8081e4056310a4c9ab8f0b878a06c5fbe6d2/server/mcp.go).

The architectural lesson from the local review survives verification: retrieval infrastructure need not invoke a generative model for normalization, indexing, filtering, or source inspection. Adopting Bleve, Hister's database layout, or its whole application is unnecessary for ChenWeb.

### 2.3 Keywords and categories solve different problems

YAKE extracts keyphrases using local statistics without a training corpus. TextRank ranks lexical units through a co-occurrence graph. Either can be evaluated on document/section text; short chunks may not provide enough statistics. Neither algorithm produces a reliable controlled taxonomy simply by extracting phrases. [YAKE implementation](https://github.com/INESCTEC/yake), [TextRank original paper](https://aclanthology.org/W04-3252/).

fastText provides a lightweight supervised classification option once labeled examples exist. It requires training data and preprocessing; its tutorial shows that default settings can perform poorly. It is an optional category classifier, not a no-training synonym for keyword extraction. [Official classification tutorial](https://fasttext.cc/docs/en/supervised-tutorial.html).

**Design inference:** Use CPU extraction for surface phrases, inherit known document categories with explicit provenance, and use rules for structural kinds. Consider a trained classifier later. Extracting a phrase already in the body does not automatically increase BM25 recall; its value is controlled weighting, explanations, facets, and approved alias expansion.

### 2.4 Embeddings need not imply generative inference

BGE-M3 offers multilingual dense, learned sparse, and multivector representations. Its dense output is 1024-dimensional and its documented input limit is 8192 tokens; the model card says query instructions are not required. It is a reasonable existing-stack candidate, not a demonstrated winner on ChenWeb. Learned sparse weights are not BM25 or human keyphrases. Start with dense output and existing BM25 rather than storing all representation types. [Original paper](https://arxiv.org/abs/2402.03216), [official model card](https://huggingface.co/BAAI/bge-m3).

Late chunking runs an encoder on a longer document/window and pools token-level representations into chunks afterward. It avoids generating context prose, but requires token outputs, aligned spans, compatible pooling, and long-window handling. It cannot be added by averaging existing pooled vectors or sending ordinary requests to an API that returns one vector per input. Source changes can invalidate a whole encoding window. Treat it as an experiment after a baseline. [Original paper](https://arxiv.org/abs/2409.04701), [full method](https://arxiv.org/html/2409.04701v3).

One evaluation of semantic chunking found no consistent gains justifying its extra computation across its tested tasks. This does not disprove all semantic segmentation; it argues against paying for it by default without local evidence. [Original evaluation](https://arxiv.org/abs/2410.13070).

### 2.5 Search mechanics still determine scale and recall

ParadeDB documents field-aware query boosting and language analyzers. That supports preserving distinct fields rather than manufacturing importance by repeating text. Its current documentation and ChenWeb's migrations use different API-era details, so installed extension/version compatibility must be checked before choosing SQL syntax. [Official API explanation](https://www.paradedb.com/blog/v2api), [Jieba documentation](https://www.paradedb.com/docs/reference/tokenizers/available-tokenizers/jieba).

pgvector documents approximate-index filtering behavior, iterative scans, exact-search alternatives, and memory/build tradeoffs. A selective KnowledgeStore or category filter can underfill ANN results even when the SQL contains the correct predicate. Correct scope predicates and adequate filtered recall are separate requirements. [Official pgvector filtering guidance](https://github.com/pgvector/pgvector#filtering).

### 2.6 Options and recommendation

| Approach | Offline cost | Strength | Limitation | Decision |
|---|---|---|---|---|
| Raw body BM25 only | CPU/index storage | Exact language, identifiers, cheapest repair | Missing ancestry and cross-language concepts | Required baseline comparison |
| Deterministic context + fielded BM25 | CPU/index storage | Structural disambiguation, auditable evidence | Cannot resolve all implicit references | Mandatory foundation |
| Above + one dense encoder vector | Encoder compute/vector storage | Paraphrases and cross-language candidates | Adds build cost and ANN tuning | Recommended optional tier, ultimately full eligible coverage where budget allows |
| Late chunking | Specialized long-window encoder | Context without generated prose | Provider changes and larger invalidation units | Pilot only |
| LLM context/keywords/categories per chunk | Generative tokens, jobs, verification | Can resolve implicit meaning | Cost, hallucinations, operational volume | Rejected as default |
| Small supervised category classifier | Training/label maintenance + cheap inference | Stable vocabulary at scale | Needs representative labels | Later, if rules/inheritance are insufficient |

## 3. Proposed chunk artifact and processor ownership

Everything in Sections 3–10 is a **proposal**. Table names, fields, settings, routes, and readiness values below do not exist unless explicitly identified as current.

### 3.1 A chunk has content, context, and derived retrieval representations

Retain `kb.chunks` as run history. Add a proposed `kb.chunk_items` table for immutable source/structure items, with a proposed document chunk-state row recording active structural generation and retrieval projection revision. Reuse `kb.doc_process_runs` for attempt identity rather than inventing another unrelated pipeline-run system. Source generation and projection revision are separate: title, category, vocabulary, or recipe changes can create a new projection without changing source chunk identity.

| Field group | Proposed contents |
|---|---|
| Identity | `input_record_id`, `generation_id`, `chunk_id`, `chunk_seqno`, chunk-policy version |
| Evidence | canonical-file hash and retained revision location; regular and overlap spans separately; page coverage; exact source/body hash |
| Structure | ordered section IDs/paths, primary section, neighbor IDs, optional caption/header references and chunk kind |
| Source diagnostics | source content length, structure quality and protected-block markers, pinned source-normalization version |

Keep metadata snapshots, normalized retrieval text, recipe/input hashes, keywords/categories, view boundaries and embedding diagnostics in a separately versioned projection manifest and the derived current registry rows, not mutable fields on immutable `chunk_items`. The state row records `projection_revision`, manifest location, metadata snapshot hash and recipe/vocabulary versions. A metadata-only replay writes a new immutable projection manifest; it does not mutate the source items.

Use primary key `(input_record_id, generation_id, chunk_id)`; `generation_id` is a stable identity for a particular finalized line/chunk manifest, not a mutable timestamp. Chunk IDs must match the existing `ChunkConnectionID` mapping, verified with adapters/tests. Do not assume the `Chunk.SeqNo` and `Block.Index` offsets coincide. Public evidence identity is `(document, generation, chunk_id)`. A bare positional ID is insufficient after re-chunking.

Store original evidence as immutable canonical artifacts plus a retained source revision. `kb.search_artifacts` remains the current derived search projection; avoid also copying its entire text into semantic JSON payloads. Projection manifests may reference source bodies and record the normalization recipe rather than duplicate them. Metadata references and hashes avoid copying whole chapters into every row. Body hash and source manifest hash serve different purposes: a line-number shift can require new provenance without new embedding inference if the composed embedding text is unchanged.

Keep `.chunks` syntax unchanged for current consumers. Publish a versioned manifest/sidecar containing the new identity and context references. Compatibility `.chunks` and current canonical files are regenerated views of that version; retained generations support exact inspection and repair.

### 3.2 Keep the doc-processor phases

**Phase A, `chunking.HandleEvent`:** consume finalized lines, build the section map, create chunks/items, persist the manifest and run record, and expose the chunk buffer. This step performs no new generative inference and no remote embedding calls. Split construction/configuration from the current topic/summary service requirements so lexical-only startup works without topic prompts or an embedding model.

**Phase A, metadata extraction:** preserve normal extraction behavior. For the proposed CPU-only search-ingestion profile, add an explicit deterministic/reuse-only metadata mode: use source-owned supplied metadata, parser fields and auditable identifier/date patterns; leave unavailable fields unknown instead of invoking an LLM. This mode must be implemented and tested, since the current metadata processor is LLM-backed. Unknown routing facets retain existing indeterminate/clearance behavior; cheap search annotations must not manufacture facts to satisfy a gate. Search enrichment must not require optional semantic artifacts. Parsing/OCR and other extraction profiles may still use models; this proposal does not make the entire existing application generation-free.

**Phase C, `ChunkingProcessor.PostProcessIndex`:** load the chunk manifest and latest permitted metadata snapshot; derive phrases and inherited categories; compose projections; transactionally publish chunk registry/range rows; enqueue missing embeddings. Refresh metadata-dependent fields here because metadata extraction occurs after chunking. Reload the record instead of using an early stale snapshot.

The controller must invoke this path for mandatory chunking in both normal and selected-processor runs, and handle metadata-failure cases with available context. Only use metadata attributable to this source revision, or explicitly curated metadata applicable across revisions; a prior edition's extracted title/date must not silently survive as fresh context. Explicitly test dispatch; `ProcessorSpec.Requires/Produces` does not implement it. No dependency on topic/summary/metric output or ontology enrichment is needed. A reindex job may replay Phase C against existing chunks without rerunning Phase A or an LLM.

In a full pipeline, current Phase C scheduling still waits for Phase B to finish, even though chunk indexing does not consume its output. Offer a search-ingestion profile that omits optional Phase B extraction, so baseline lexical publication is not delayed by those calls. Publishing before Phase B in a full pipeline would require an explicit new controller scheduling seam; implementing an interface alone does not provide that behavior.

**Embedding workers:** run independently with durable jobs and bounded global capacity. They must not delay mandatory chunk creation or hold database transactions while making network calls.

## 4. Context, phrases, and categories without generative calls

### 4.1 Document and chapter context

Build a section tree in one pass over finalized lines. On `heading-N`, pop same/deeper levels and attach to the nearest preceding shallower heading. Keep actual headings and source spans; do not invent missing intermediate titles. Treat a plain heading as its normalized analyzer level. A missing/uncertain hierarchy falls back to a flat nearest-heading context with an uncertainty marker.

For each chunk, record the ancestor path at its first regular line and every section intersected by its regular spans. A chunk crossing a heading is not entirely owned by the old section. For the existing chunk policy, preserve the chunk and record multiple memberships; use only the bounded relevant heading set in its search input. Section references must not be discovered from overlap lines alone.

Context should include:

- Document title/number, edition or publication date if known, source language and stable revision.
- Section identifiers and breadcrumbs, with source-line evidence for the headings.
- Table caption, column headers, explicit unit rows and footnotes required to interpret a table; formula labels and explicitly linked definitions when available.
- Previous/next chunk references and bounded parent-section ranges, resolved during inspection rather than copied in full.

Retain source assertions as source assertions. A document date is not automatically its effective date; a document domain is not proof of every chunk's subject. Do not infer equipment applicability or attach a similarly named definition without an explicit structural/reference link. Repeated headers/footers may be excluded from searchable text while remaining recoverable source evidence.

### 4.2 Keywords: extract a bounded, evidenced set

**Recommendation: yes, but as an annotation, not a separate LLM task.**

Start with deterministic identifiers and dictionary matches: standard numbers, equipment/model codes, clause identifiers, technical abbreviations, and known bilingual term surfaces. Preserve original forms alongside normalized lookup variants. Exact identifiers such as `GB/T 12345-2024`, `IEC 60068-2-1`, `IP67`, `10 kV`, and `5.2.1` must survive tokenization; normalization must not merge different editions, change decimal meaning, or drop units/negation from evidence.

For topical phrases, evaluate one lightweight algorithm initially: a YAKE-style local-statistics scorer, run once per section (document fallback), followed by bounded per-chunk selection. Pure Go implementation or a batched CPU service are deployment choices to assess; do not add Python microservices merely to use one algorithm. Candidate n-grams require language-aware segmentation and a versioned technical dictionary. Compute document/section statistics once, not by re-reading the whole document for each chunk. Optional corpus-frequency statistics use a versioned snapshot and are refreshed in batches, not a synchronous corpus scan per ingest.

Proposed initial cap is **8–16 phrases** per chunk, excluding separately stored exact identifiers. Candidates must occur in the regular body or explicitly recorded inherited context. Deduplicate nested phrases, suppress boilerplate, keep phrase source spans and origin (`body`, `section`, `document`, `approved_alias`), score and extractor version. The cap and scorer are experiment settings, not quality guarantees. An empty phrase list is valid.

Do not append the full keyword list repeatedly to both body and embedding text. Index phrase fields with bounded boosts if they help evaluation. Approved aliases can add lexical recall; observed words already in the body mainly add explanations and weighting. Resolve against approved vocabulary in batches and record unresolved surfaces for review; do not auto-create ontology concepts/categories or perform per-phrase DB round trips over millions of chunks.

### 4.3 Categories: inherit carefully, classify only when justified

Keep three different annotations:

| Annotation | Default source | Meaning |
|---|---|---|
| Structural kind | Line types and auditable rules | Table, formula, definition candidate, requirement candidate, reference list, ordinary prose |
| Document category | Existing metadata/facets/curated classification | Inherited document-level context, not a local chunk-topic claim |
| Local subject category | Approved vocabulary plus reliable rules; later a trained classifier | A fallible chunk-level topic assignment |

Rule-derived `requirement_candidate` is a search hint; a modal word alone does not establish a governed obligation. Store method, vocabulary version, source scope, evidence, and calibrated confidence/unknown. Unknown is preferable to a fabricated path. Do not write these hints into accepted semantic assertions.

Use uncertain categories as optional boosts/facets. Hard filters must expose whether they target document inheritance or local categories; inferred categories must not silently exclude relevant evidence. If sufficient reviewed labels accumulate, evaluate a small fastText/linear classifier with document-family-separated training/test data and an abstention threshold. Reuse existing released vocabulary; do not create a parallel ungoverned category tree. Corpus clustering may aid analyst discovery but does not define stable categories.

## 5. Compose two search projections

### 5.1 Lexical search document

For the first working integration, fill existing registry fields with a deterministic compact composition: body in `search_document`, useful document/section label in `primary_label`/`secondary_label`, raw evidence excerpt in `snippet_basis`, bounded phrases in `keywords`, and identifiers/context in explicit payload fields. Extend the chunk partition query/index to search context and identifiers explicitly; payload storage alone does not make them searchable.

The target chunk projection has separately indexed `body`, `section_title`, `document_title`, `identifiers`, `approved_aliases`, and optional phrase fields, implemented through compatible typed columns or indexed expressions. Use field boosts tuned on held-out data. Preserve a composed compatibility text for PostgreSQL fallback, with a documented analyzer recipe. Avoid copying whole document metadata or multiplying terms to simulate weights.

Use Chinese segmentation for prose plus literal/normalized forms for identifiers; test mixed scripts, punctuation, units, and standard numbers. Index and query normalization must agree. Do not claim that English stemming and Chinese segmentation are equivalent fallbacks. Field matches should explain whether a hit came from body, heading, or document context. Title-only hits are useful discovery leads, not proof that the chunk answers the question.

### 5.2 Embedding input

Use a deterministic, bounded template, for example:

```text
Document: Cold-chain storage standard | GB/T EXAMPLE-2024
Section: 6 Storage equipment > 6.3 Temperature alarms
Table: Alarm thresholds | Columns: condition, limit, unit
Content:
[normalized regular source text, preserving numbers, units and negation]
```

This example is fictional. It illustrates context composition, not extracted corpus data. Machine IDs, file paths, geometry, JSON field names, retrieval scores, uncertain category lists, and timestamps do not belong in embedding input. Keep them in metadata.

Initial experiment: **at most 64–96 context tokens**, preserving the body budget and prioritizing nearest heading, document identity, and necessary caption/units. Omit empty fields, deduplicate titles already present, and use the actual model tokenizer to account for mixed Chinese/English text. Context quality and total cost determine the final cap. Never silently trim the source tail using a character/rune limit and report full semantic coverage.

Model instructions/prefixes belong to versioned provider recipes. BGE-M3 does not require generic query instructions; another model may require asymmetric query/document prefixes. Pin tokenizer, model revision, pooling, dimension, normalization, and document recipe. Use multilingual retrieval without automatic translation per chunk; approved bilingual aliases supplement lexical matching.

### 5.3 Chunk boundaries, overlap, and oversized protected content

Do not change `CHUNK_SIZE` globally in the first search implementation: all current chunk-based extractors share those boundaries. Measure body tokens, serialized overhead, ancestry-prefix share, and count of protected oversized chunks before changing the policy.

Evaluate a new **versioned, structure-first** chunk policy in shadow on 128/256/512-token targets with paragraph/section preferences and protected-block rules. These are a test grid, not universal optimal sizes. The winning policy must be assessed for downstream extraction quality as well as search and total vector count. A policy switch creates a new generation and invalidates dependent artifact provenance; it must not silently reuse stale metrics/topics.

Default searchable body excludes carried overlap. Neighbor expansion supplies additional context at query time. If overlap materially improves dense recall, cap and label it separately and include it in the embedding-input hash; evidence spans still distinguish owned lines from contextual ones.

For a protected table/list/formula chunk exceeding the model input cap, retain the canonical chunk intact. Produce bounded retrieval views at safe row/item boundaries, repeating necessary table headers/units. Registry IDs such as `<chunk_id>_w1` identify these views; `parent_chunk_id` points to the canonical chunk. Store exact view spans and table row anchors where a canonical line contains a whole HTML table. Coarse line spans alone cannot identify an individual table row. Group views to their parent before result counting/diversity. Ordinary chunks have one view/vector; oversized content is the explicit exception and its added units count in the budget. An unsplittable formula/object is lexical-only with an explicit incomplete-semantic marker, not silently truncated.

## 6. Publication, incremental updates, and readiness

### 6.1 Atomic current-generation projection

Add the missing `chunk` registry partition with record lookup, lexical, vector and inherited line-range indexes through Goose. Add proposed per-record chunk state and item/job tables through the same migration workflow, using centralized database handles and registering document deletion for every new owned table/file.

Build source items and projection rows outside the publication transaction. Retain immutable source/projection manifests first. Reserve a per-document projection attempt token while reading its source/metadata/recipe snapshot under a short lock. Only the latest desired token may publish; at commit also compare current metadata and recipe revisions with that snapshot. This prevents a slow old title/category replay from replacing a newer projection of the same structural generation. At publication:

1. Lock the document's chunk-state row; verify source generation, desired projection token, metadata snapshot and recipe/vocabulary revisions are still current for this attempt.
2. In one transaction, replace current chunk registry rows and `kb.chunk_ranges`, update active `projection_revision` and readiness, and enqueue missing embedding work. Initially vectors may be null or reused from cache.
3. Commit, then expose lexical readiness. Readers see either the old complete projection or the new complete lexical projection; they do not see delete/partial-insert intermediate state.

Registry, ranges, state and job helpers must accept the same transaction/connection; invoking existing `*sql.DB` helpers from surrounding transaction code does not make their writes atomic. Use consistent document-lock ordering across reindex, deletion and worker writes.

Make this publication path the owner of current chunk ranges. Retire or generation-guard existing downstream `replaceChunkRangesForRecord` calls so an older metric/semantic-index attempt cannot overwrite newly published ranges. Add generation attribution to current ranges or require an active-generation check in every reader. Historical inspection resolves retained manifests; it must never resolve an old positional ID through today's `kb.chunk_ranges`.

Filesystem and SQL are not one transaction. Write/fsync/rename immutable artifacts before SQL publication; update compatibility file pointers afterward with recovery/reconciliation on crash. Inspectors resolve the generation-pinned manifest, never trust a mutable path alone. Orphan staged files can be garbage-collected after a retention interval. At very large per-document chunk counts, benchmark transaction/WAL limits and consider a staged projection plus active-generation join; that is a measured extension, not an assumed need for every record.

Keep old generations for a bounded grace period so existing citations remain resolvable. Mark superseded results with their revision; do not present them as current-edition evidence. Deletion/revoked access takes precedence over retention, cache hits, and queued jobs.

### 6.2 Exact cache keys and invalidation

Proposed embedding reuse key:

```text
SHA256(cache_scope,
       immutable_model_identity, dimensions, pooling/normalization,
       tokenizer_version, embedding_recipe_version, document_prefix,
       exact_composed_embedding_input)
```

Use unambiguous structured serialization. Scope the cache to authorized KnowledgeStore/tenant boundaries. Keep offsets and positional chunk IDs outside the reuse key, but in immutable evidence identity. Same body under a different section prefix correctly produces a different vector. Do not key only on raw text, model nickname, or vector length.

| Change | Required action |
|---|---|
| Same source/context/recipe | Reuse items/projections where valid; zero new embedding calls |
| Line numbering/geometry only, same composed input | Refresh provenance/generation; reuse vectors |
| Body text change | Rebuild affected views and lexical rows; embed changed inputs |
| Heading/title change included in template | Refresh affected context and embeddings |
| Category/keyword change excluded from template | Refresh annotations/lexical fields; no embedding refresh |
| Model, pooling, dimension, document prefix or embedding recipe | New embedding space/input keys; controlled re-embedding |
| Query-only prefix change compatible with same model contract | Query evaluation/cache refresh; document re-embedding not automatically required |
| Chunk policy change | New generation and downstream provenance/reprocessing assessment |

Do not mix old/new embedding spaces during migration just because dimensions match. Serve lexical-only for incompatible rows, or maintain isolated versioned vector indexes during a controlled cutover. Never write a new-model query vector against an unmarked mixture of old-model rows.

### 6.3 Durable jobs and observable status

A proposed embedding job key includes `(record, generation, projection_revision, view_id, embedding_key)`, with state, attempt count, lease expiry and bounded backoff. Workers claim using database concurrency controls, batch by token budgets, and enforce global capacity. Write results with a conditional update or locked transaction verifying document existence, access, active generation, projection revision and exact input hash together; a separate check followed by an unconditional update is unsafe. A late old job must never overwrite a new chunk. Cache identical authorized inputs once, while retaining separate evidence references.

Track generation-and-projection-specific readiness rather than extending `chunked=success` to mean everything is searchable:

| Readiness | Meaning |
|---|---|
| `structure_ready` | Canonical chunk manifest/items persisted |
| `lexical_ready` | Current lexical projection published |
| `semantic_pending/partial/ready/failed/disabled` | Embedding coverage for eligible current views, with counts and reasons |

These are proposed readiness fields, not replacement values for the existing processor `proc_status` enum. Continue writing processor success/failed/stopped via `kb.inputs.status`; reuse its rollups for filtering, not direct writes to `kb.input_proc_status`. Phase C failures must reach runtime failure status and repair tooling. Persist semantic progress separately so optional inference failure does not discard lexical availability.

Log start/end, record/run/generation, recipes, counts, bytes/tokens, cache hits, retry/failure reasons, embedding coverage, elapsed time, and index lag using the workspace logger. Give interactive queries separate encoder capacity from bulk backfills. Limit backlog storage, use admission control, quarantine repeated failures, and support keyset-resumable repair. Existing bounded `reembed_all` behavior must not be mistaken for a progressing cursor.

## 7. Query behavior and source inspection

1. Apply KnowledgeStore/access, active generation, explicit document/edition, and user-requested filters to **both** lexical and vector branches before fusion. Never retrieve cross-scope vectors and filter them only after returning evidence.
2. Retrieve exact-identifier and fielded BM25 candidates. Embed the query only when semantic retrieval is enabled/available. Queries that explicitly name a standard or edition should retain that constraint rather than having dense similarity override it.
3. Fuse branch ranks with existing RRF (`k=60` as the initial baseline), preserving matched fields and retrieval-channel provenance. Candidate counts of 100–200 per branch are test settings, not a universal scale guarantee.
4. Merge overlapping evidence and multiple views of one canonical chunk. Diversify by document/section when global discovery is requested; permit more hits for an explicitly scoped single-document query. Do not collapse distinct editions or distinct numerical requirements as duplicates.
5. Optionally run a small cross-encoder on the bounded candidate set only if local quality/latency tests justify it. It is neural inference, even without generation.
6. Return compact results with source generation, `projection_revision`, chunk/view identity, evidence spans, breadcrumb, snippet, channel, and coverage metadata. Do not return whole chapters automatically.
7. An authorized inspection call accepts generation plus `projection_revision` and view ID, resolving the retained projection manifest and exact source evidence, table context, bounded neighbors, or a parent section under an explicit token budget. View boundaries can change without a new source generation. Context spans and matched spans remain distinguishable. Corpus-derived headings/metadata are evidence, never tool instructions.

Extend existing `/api/v1/kb/search?artifact_types=chunk` and the content-segments UI rather than inventing another basic search endpoint. Add or reuse a generation-aware inspect API/tool; exact route naming belongs in the implementation spec. Keep the common result envelope backward compatible with optional context fields. New UI text must use Paraglide English/Chinese and allow text selection.

Fix counts honestly: existing hybrid `total` is lexical-only. For new chunk retrieval expose count semantics, `has_more`, and bounded candidate-window metadata rather than claim an exact full-corpus hybrid total. A search-session snapshot/cursor can stabilize pagination if needed; high page numbers must not imply access beyond the fused candidate window.

ANN filtering requires independent validation. Compare filtered ANN against exact distance sorting on small selective scopes, tune supported iterative scans, and inspect real query plans. A CTE containing `ROW_NUMBER()` and `LIMIT` does not itself prove HNSW or BM25 Top-K acceleration. Keep selective typed filters indexed; JSON payloads and artifact-type partitioning alone do not solve KnowledgeStore-scale filtering. [pgvector guidance](https://github.com/pgvector/pgvector#filtering), [ParadeDB Top-K](https://www.paradedb.com/docs/reference/full-text/top-k), [indexed filtering](https://www.paradedb.com/docs/reference/filtering/indexed).

## 8. Cost and capacity model

### 8.1 Three deployment profiles

| Profile | Ingestion and retrieval | Suitable use |
|---|---|---|
| CPU-only foundation | Deterministic structure/phrases + BM25; proposed reuse-only metadata mode; no encoder/generation in chunk enrichment | Whole-corpus lexical coverage; requires the new search-ingestion profile, or reindexing existing canonical inputs |
| CPU pipeline + shared encoder | Same foundation; asynchronous local GPU embeddings, or a priced embedding API | Recommended hybrid deployment when measured recall justifies compute/storage |
| Targeted semantic enrichment | Optional small reranker, late-chunking pilot, or budgeted generated context for measured failure clusters | Quality improvement after evaluation, never a mandatory all-document toll |

CPU hosting an encoder is possible but not assumed fast enough. Benchmark it separately from CPU lexical processing. Local model weights may have no per-token API bill, but compute, operations, power and vector storage still cost money. Hosted embedding inference has no text-generation output bill but remains a model service cost.

### 8.2 Explicit equations and illustrative workload

Let `N` be retrieval views after oversized-window expansion; `Tbody` average body tokens; `Tctx` average context tokens; `h` valid scoped embedding-cache hit fraction; `Pe` currency per million embedding input tokens; `r` measured views/second for the actual length/model/hardware mix.

```text
new_embedding_tokens = N * (Tbody + Tctx) * (1 - h)
embedding_API_cost = new_embedding_tokens / 1,000,000 * Pe
encoder_wall_hours = N * (1 - h) / (r * 3,600)
raw_vector_bytes = N * (4 * dimension + 8)
```

For planning only, assume 256 body + 64 context tokens, no cache hits, one 1024-dimensional vector per view. The context adds 25% over body-only encoder tokens. These are not observed current chunk sizes and not an instruction to change `CHUNK_SIZE`.

| Retrieval views | Encoder input tokens | Raw vector payload, decimal GB | Wall time at assumed 100 views/s | At assumed 1,000 views/s |
|---:|---:|---:|---:|---:|
| 1 million | 320 million | 4.104 | 2.78 h | 0.28 h |
| 10 million | 3.2 billion | 41.04 | 27.78 h | 2.78 h |
| 100 million | 32 billion | 410.4 | 277.78 h | 27.78 h |

Throughput columns are arithmetic sensitivities, **not CPU/GPU benchmarks or promised service rates**. Measure token-length distribution, padding, batching, retries, utilization and index-write throughput. Wall time also includes ingestion, hashing, DB writes and index construction.

The vector payload calculation uses pgvector's documented storage formula; it excludes rows, text, JSON, HNSW, BM25/GIN/GiST indexes, WAL, temporary rebuild space, replicas and backups. `halfvec` halves the element component but needs a schema/index migration and quality tests; it cannot silently replace current `vector(1024)` columns. Cache storage also needs a bounded retention/eviction policy and can itself duplicate vectors. [Storage reference](https://github.com/pgvector/pgvector#vector-type).

For incremental ingestion, substitute changed/uncached views into the same equations. A 90% valid cache-hit fraction reduces encoder work to 10% in this model; contextual title changes or model switches can lower that hit fraction sharply. Do not assume cross-edition boilerplate deduplication yields identical contextual vectors.

### 8.3 Why per-chunk generation is a different budget

Let `f` be the fraction receiving generated context, `Tin` the billed input per job including document context/cache behavior, `Tout` generated output tokens, and `Pin/Pout` the respective per-million-token prices:

```text
generation_jobs = N * f
generation_cost = N * f * (Tin * Pin + Tout * Pout) / 1,000,000
```

Ten million chunks with 80 generated tokens each produce **800 million output tokens** at `f=1`, before any repeated document input, retries, storage or QA. A tightly controlled 1% experiment produces 8 million output tokens and 100,000 jobs; that still needs scheduling and verification. Historical vendor contextualization estimates are not current quotes and do not price this exact corpus. Obtain actual provider rates only when choosing an implementation budget.

Prefer, in order: fix structure and analyzers; reuse existing metadata; tune candidates/filters; improve encoder or reranker if measured; then selectively generate context for persistent failures. If a section-level LLM annotation benefits many chunks, cache it once and attach its provenance—do not call it separately for every descendant. Generated hints remain derived annotations, never the quoted source.

### 8.4 Capacity choices by scale

At 1M views, start with one Postgres-backed search deployment and measured CPU/encoder sizing. At 10M, benchmark backfill windows, HNSW build memory, WAL/replica lag, filtered recall, and concurrent ingestion/query latency. At 100M, treat the table above as a sizing warning: chunk-only raw vectors already exceed 400 GB, before other artifact families. Do not promise that the current artifact-type partition alone is sufficient.

Use measured query locality to choose coarse store-group partitioning/sharding, lower-precision indexes, cold lexical-only tiers, or another vector service only if needed. Avoid one partition per small document/store. Partial semantic coverage must be visible; it is a budget tradeoff, not equivalent retrieval quality. Audit whether retaining both PostgreSQL GIN fallback and BM25 for every hot row is worth the extra storage, but preserve current fallback behavior until an explicit operations decision changes it.

## 9. Evaluation and rollout

### 9.1 Establish a representative benchmark

Proposed first benchmark: roughly **300–500 human-reviewed queries** across English, Chinese, bilingual technical documents, tables, definitions, requirements, codes, and multiple editions. Sample by document family and freeze a held-out set; do not split overlapping chunks from the same standard across train/test. Generated queries may seed candidates but are not the sole judge or gold labels.

Gold evidence is document revision plus canonical spans/table anchors, independent of any particular chunk boundary. Include hard negatives: same title/different edition, reversed inequality, changed unit, neighboring equipment type, document-title-only matches, boilerplate duplicates and unauthorized stores.

Ablate independently:

1. Body-only BM25.
2. Deterministic context BM25.
3. Body-only dense retrieval.
4. Deterministic context dense retrieval.
5. Context BM25 + dense RRF.
6. Optional phrases/category boosts, reranker, late chunking, or selective generated context, one change at a time.

Do not compare a new large candidate window with an old small one and attribute all improvement to keywords/context. Test current chunk boundaries first, then the token-policy grid with downstream extraction regression checks.

### 9.2 Acceptance evidence

| Dimension | Required measurement |
|---|---|
| Recall and ranking | Evidence Recall@20/50, nDCG@10, identifier precision, semantic-only and cross-language slices |
| Fidelity | Correct generation/spans, table row/header attribution, absence of context-as-quote mistakes |
| Diversity | Unique relevant documents/sections, overlap duplicate rate, distinct-edition preservation |
| Scope and freshness | No unauthorized/revoked/stale-generation evidence; late-job rejection and deletion tests |
| Cost | CPU seconds/document, encoder tokens/view, cache-hit fraction, generation calls, index bytes/view, backfill duration |
| Serving | p50/p95 latency under ingestion load, filter selectivity, exact-vs-ANN recall, real query plans |
| Reliability | Retry/replay, crash between file and SQL publication, metadata failure, encoder outage, shrinking chunk counts |

Provisional release gate: zero known source-revision/access correctness failures; no material regression on exact identifier/numeric queries; a pre-agreed held-out recall improvement or cost reduction over the simpler baseline; measured ingestion/storage/latency within the owner's budget. Quantitative quality and latency thresholds should be set after baseline measurements, not invented as achieved service levels.

### 9.3 Implementation stages

| Stage | Deliverable | Exit condition |
|---|---|---|
| 0: Baseline | Corpus sample, token/count distributions, benchmark, version/extension/hardware inventory | Reproducible body-only retrieval/cost baseline |
| 1: Durable lexical chunks | Separated chunk construction; CPU search-ingestion/reuse-only metadata profile; chunk items/manifests; section map; chunk partition; transactional publication; repair and inspect | Search-ingestion processing yields searchable, revision-correct evidence without topic/summary/embedding configuration or mandatory metadata generation |
| 2: Cheap annotations | Identifiers, section-level phrase extraction, inherited categories and filter provenance | Measured utility; no per-chunk generated text or taxonomy creation |
| 3: Asynchronous dense tier | Durable jobs, exact-input cache, pinned multilingual model, generation-safe writes and visible coverage | Semantic-only/cross-language tests pass within measured budget |
| 4: Retrieval quality | Field boosts, fusion/diversity, bounded expansion, truthful pagination/counts, filtered ANN/Top-K tuning | Held-out improvements and load tests justify complexity |
| 5: Optional improvements | New chunk policy, late chunking, small classifiers/reranker, selective generated context | Each clears quality-per-cost gate independently |

Backfill from retained canonical lines and `.chunks`; do not rerun optional extractors just to create search rows. Roll out by bounded document batches with keyset checkpoints, readiness counts, rate limits and a chunk-scope feature gate. Rollback can remove chunk search from serving without deleting original artifacts or unrelated family indexes. New generations and model migrations require controlled cutovers rather than overwriting evidence in place.

## 10. Decisions, remaining questions, and documentation impact

The recommended direction is concrete: **deterministic structural context and lexical search first; optional cached encoder inference second; generative enrichment only where measured evidence justifies it.** Extract keywords, but bound and evidence them. Attach categories, but distinguish inheritance from local classification. Compose embedding text, but keep it separate from source evidence and from lexical fields.

Before implementation, inventory actual corpus distributions, installed search extension versions, current embedding provider/model, and available CPU/GPU capacity. Those facts determine token caps, analyzer SQL, queue throughput and index layout. No claim is made that 100M views fit the current server or that deterministic context will match the published LLM-context benchmark.

Create an OpenSpec change for the chosen first stage after proposal review. Its contracts should cover chunk identity/revisions, regular versus contextual spans, Phase A/C ownership, readiness/failure states, filtering/inspection, deletion and stale-job rejection. This devdoc records research and proposed tradeoffs; it does not replace that future contract.

Knowledge changed here: chunks should be durable evidence artifacts with context and independent retrieval projections, rather than only ranges used by other processors. This devdoc is the only new document in this task. The existing hybrid design remains a current-implementation record; the chunking/doc-processor capsules remain descriptions of today's behavior and must be updated when the feature is built. Historical plans and the Hister review were not rewritten. No migrations, code, prompts, runtime flags, or production indexes were changed. Formal SQL and complete API schemas are intentionally deferred to the implementation spec to avoid presenting unreviewed schema sketches as contracts.

## Research source register

All external sources accessed **2026-10-15**. Primary papers, official documentation and pinned source code were used; no corpus-specific performance experiment was run. arXiv API discovery and original paper pages were checked; changing documentation capabilities still require deployed-version verification.

| Source | Role and evidence limit |
|---|---|
| [Anthropic contextual retrieval](https://www.anthropic.com/engineering/contextual-retrieval) | Contextual BM25/embeddings experiment; vendor study, not ChenWeb validation |
| [YAKE repository](https://github.com/INESCTEC/yake) | Unsupervised local-statistics extraction; bilingual technical phrase quality unmeasured here |
| [TextRank, Mihalcea and Tarau, 2004](https://aclanthology.org/W04-3252/) | Original graph-based extraction method, not a retrieval benchmark for this corpus |
| [fastText classification tutorial](https://fasttext.cc/docs/en/supervised-tutorial.html) | Lightweight supervised option; requires labeled data |
| [BGE-M3 paper](https://arxiv.org/abs/2402.03216), [model card](https://huggingface.co/BAAI/bge-m3) | Multilingual representations and model input/output contract |
| [Late chunking paper](https://arxiv.org/abs/2409.04701), [v3 method](https://arxiv.org/html/2409.04701v3) | Context through token encoding before span pooling; specialized provider requirements |
| [Semantic chunking cost evaluation](https://arxiv.org/abs/2410.13070) | Evidence against assuming complex segmentation always wins |
| [Hister pinned revision](https://github.com/asciimoo/hister/commit/ef9c8081e4056310a4c9ab8f0b878a06c5fbe6d2) | Implementation examples linked in §2.2; per-chunk cache is our proposal |
| [ParadeDB API](https://www.paradedb.com/blog/v2api), [Jieba](https://www.paradedb.com/docs/reference/tokenizers/available-tokenizers/jieba) | Field/analyzer mechanisms; exact installed syntax must be verified |
| [ParadeDB Top-K](https://www.paradedb.com/docs/reference/full-text/top-k), [indexed filtering](https://www.paradedb.com/docs/reference/filtering/indexed) | Query-plan and filter-pushdown requirements |
| [pgvector official reference](https://github.com/pgvector/pgvector) | Storage arithmetic, ANN/filtering/precision tradeoffs; no hardware throughput guarantee |

Method: trace the development of context-aware chunk retrieval, compare alternatives at the same cost boundary, and test the resulting recommendation against ChenWeb's processor lifecycle. The recommended deterministic substitutions are engineering hypotheses to evaluate, distinct from the cited papers' findings.
