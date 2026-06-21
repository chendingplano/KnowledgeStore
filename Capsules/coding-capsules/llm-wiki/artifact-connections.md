# 1 Overview
Artifacts are connected in several forms: deterministic line-overlap references,
category membership, dictionary-style normalized-name links, extracted relation graph
links, and hybrid-search semantic links.

The purpose of these connections is to make the knowledge base more searchable and more
useful for LLM reasoning. Search retrieves candidate artifacts by text and embeddings;
graph edges provide deterministic anchors that can be traversed, explained, and reused
without relying on ranking thresholds.

# 2 Table
Artifact connections are stored in `kb.artifact_connections`:
```text
CREATE TABLE kb.artifact_connections (
	id bigserial NOT NULL,
	source_record_id int8 NOT NULL,
	target_record_id int8 NOT NULL,
	source_type text NOT NULL,
	source_id text NOT NULL,
	target_type text NOT NULL,
	target_id text NOT NULL,
	relation_name text NOT NULL,
	relation_method text NOT NULL,
	confidence float8 NULL,
	overlap jsonb NULL,
	provenance jsonb NULL,
	semantic_signature text NULL,
    source_desc text NOT NULL,
    target_desc text NOT NULL,
	extra_info jsonb NULL,
	create_time timestamptz DEFAULT now() NOT NULL,
	CONSTRAINT artifact_connections_pkey PRIMARY KEY (relation_method, id),
	CONSTRAINT artifact_connections_relation_method_source_type_source_id__key UNIQUE (relation_method, source_type, source_id, target_type, target_id, relation_name),
	CONSTRAINT artifact_connections_input_record_id_fkey FOREIGN KEY (input_record_id) REFERENCES kb.inputs(id) ON DELETE CASCADE
)
PARTITION BY LIST (relation_method);
CREATE INDEX idx_kb_artifact_connections_record ON ONLY kb.artifact_connections USING btree (input_record_id);
CREATE INDEX idx_kb_artifact_connections_relation ON ONLY kb.artifact_connections USING btree (input_record_id, relation_name);
CREATE INDEX idx_kb_artifact_connections_source ON ONLY kb.artifact_connections USING btree (input_record_id, source_type, source_id);
CREATE INDEX idx_kb_artifact_connections_target ON ONLY kb.artifact_connections USING btree (input_record_id, target_type, target_id);
```

## 2.1 Decisions as of 2026-06-16

The following decisions supersede older category documents that describe
`kb.category_instance` as the active artifact-category membership table.

- Category membership is stored in `kb.artifact_connections`, not
  `kb.category_instance`, for new doc-processor writes.
- `kb.category_instance` is obsolete for these processors. If the database is cleared
  and all doc processors are rerun, category membership should be rebuilt from
  `kb.artifact_connections` and should not require `kb.category_instance`.
- Category membership edges use `relation_method='category_name'` and
  `relation_name='belong_to'`.
- For category membership edges, `source_record_id` is `kb.inputs.id` for the source
  document, not the source artifact row id.
- For category membership edges, `target_record_id` is the source document's
  `kb.inputs.id`; the category dictionary row id is stored in
  `extra_info.category_id`.
- For category membership edges, category targets use semantic category identity:
  `target_type=kb.artifact_categories.category_type` and
  `target_id=kb.artifact_categories.category_key`.
- Normalized dictionary edges are still useful and should be kept:
  `entity_name --has-instance--> entity` and
  `relation_predicate --has-predicate--> relation`.
- Dictionary edges are not a replacement for hybrid search. They provide exact,
  deterministic grouping across documents when the same normalized entity name or
  relation predicate appears more than once.
- Hybrid search remains useful even when dictionary edges exist. Hybrid search is for
  ranked discovery; dictionary/category edges are for deterministic graph traversal.
- Metric and inventory-item hybrid semantic links are implemented in the Phase C
  indexer and write `relation_method='hybrid_search'`,
  `relation_name='semantically_related'` edges.
- Hybrid semantic-link sections for other artifact families describe target design
  unless their Phase C indexer explicitly calls the hybrid connector.

## 2.2 Line-Overlap Connections: Storage Rationale (2026-06-16)

Line-overlap connections (the `connected_artifacts` fields described throughout §3) are
stored **denormalized on each artifact row** (e.g. `kb.metrics.connected_artifacts`) and
are deliberately **not** written to `kb.artifact_connections`. This section records why,
and addresses the concerns raised about that choice.

### Why these edges are kept out of `kb.artifact_connections`

The decision is justified by the *kind* of edge, not by edge count:

- **Intra-document only.** Line-overlap is computed from line-span overlap within a single
  `input_record_id`. Line numbers are document-local, so these edges never cross documents.
- **Deterministic and fully derivable.** They are recomputable at any time from
  `source_line_spans` / `line_spans`. They are a cache, not an independent fact.
- **Symmetric.** If A overlaps B, then B overlaps A; the edge is stored on both endpoints.
- **Structural, not semantic.** They behave like an adjacency index, not like the
  "deterministic anchors that can be traversed, explained, and reused" across documents
  that `kb.artifact_connections` exists for (§1).

Putting them in `kb.artifact_connections` would make the overwhelming majority of rows in
that table derivable intra-document noise, diluting the one table whose value is
cross-document semantic/graph traversal.

### On the volume concern

Row count is **not** the reason to keep them out. "Hundreds per 20-page document" is
trivial for PostgreSQL, and `kb.artifact_connections` is already
`PARTITION BY LIST (relation_method)`, so line-overlap edges would occupy their own
partition and never touch the category / dictionary / hybrid partitions. The justification
is edge kind (above), not scaling.

### On the "not globally searchable" concern

This drawback is largely moot. Because line numbers are document-local, a cross-document
line-overlap query is meaningless — there is no real query that needs these edges to be
globally searchable. The only traversal needed is "within this document, what overlaps
artifact X," and the denormalized `connected_artifacts` field already answers that in both
directions (the edge is stored symmetrically on each endpoint).

### Contract: `connected_artifacts` is a derived cache

The single source of truth for line-overlap is the line spans, not the
`connected_artifacts` field. Treat `connected_artifacts` as a materialized result of a
range-overlap query:

- It is **rebuildable** at any time from line spans.
- It is recomputed **whole-document** in Phase C (post-process), never incrementally
  patched, so the symmetric copies on both endpoints stay consistent.
- It is **never hand-edited**.

Consumers asking "what is connected to artifact X?" must read both stores: the
`connected_artifacts` field (line-overlap) and `kb.artifact_connections` (category,
dictionary, and hybrid edges).

### The "purest" form — design (IMPLEMENTED; see the status subsections below)

> Status: this design is implemented as of 2026-06-16 and verified live. Steps 1–4 below
> are done across all artifact families (chunk edges stay in Go — the agreed hybrid). See
> "Spike status", "Rollout status", and "Step 3/4 cutover" subsections for what shipped,
> and the migrations `20260616000001/2/3`. The only variant *not* implemented is dropping
> the persisted `connected_artifacts` entirely (compute purely on demand); Option B
> (materialized cache, below) was chosen deliberately for read speed.

The purest design makes the line spans a first-class, queryable source of truth and treats
`connected_artifacts` as nothing more than its cache:

1. Store spans as `int8multirange` (an artifact may cover several disjoint ranges), e.g.
   `line_range int8multirange`, instead of a JSON span list.
2. Add a GiST index on that column (`USING gist (line_range)`).
3. Define the connection set as a range-overlap join within a document:
   `a.input_record_id = b.input_record_id AND a.line_range && b.line_range`.
4. Refresh `connected_artifacts` (or a materialized view) from that query in Phase C.

Steps 1–2 are the real investment; without them, overlap checks remain JSONB scans —
workable, but the spans are not yet a true indexable source of truth. Persisting
`connected_artifacts` remains the right choice for read speed; the change is conceptual —
it is a cache of the range-overlap query, not an authoritative edge store.

### Option A — drop persistence, compute on demand (in progress, 2026-06-17)

Decision: go past the materialized cache and stop persisting `connected_artifacts`
entirely, computing it on demand. Chunk edges use a dedicated `kb.chunk_ranges` table
(chunks are not in the search registry).

Stage 1 (additive, done): migration
`ChenWeb/project_migrations/20260617000001_add_connected_artifacts_on_demand.sql` adds:
- `kb.chunk_ranges (input_record_id, chunk_id, source_line_spans, line_range generated,
  …)` + GiST, holding the canonical fixed-size chunk line ranges keyed by the positional
  `<record>_chk_<index>` id. Populated in Phase C by `replaceChunkRangesForRecord`
  (wired into semantic-projection and metric indexing, which both load the canonical
  `.chunks` file). Note: this canonicalizes chunk ids across all families (topics/scenes
  previously used semantic-chunk positional ids).
- `kb.connected_artifacts(p_record_id, p_self_type, p_source_row_id) returns jsonb` — one
  registry self-join for artifact↔artifact edges + a `kb.chunk_ranges` join for chunk
  edges, returning the same JSON shape (chunks + each non-self family, empty arrays kept).
  Keyed by `source_row_id` (base-table PK), because `connected_artifacts` already references
  targets by **registry** `artifact_id` (not base-table ids, which differ for summaries /
  provisions) — so the whole graph lives in registry-id space and self is resolved through
  the registry too. This makes the graph symmetric.

Verification (record 416, reprocessed): exact parity with stored `connected_artifacts` for
entity (193/193), inventory_item (74/74), metric (28/28), relation (63/63). The residual
diffs in provision/scene/summary/topic are **stored-side staleness**, not function errors:
the function is symmetric by construction (proven: 59/59 provision↔metric edges agree in
both directions, 0 asymmetric), whereas stored values are computed incrementally per family
during Phase C and can lag the final cross-family state. The chunk path is verified
(synthetic + real); the span coalescer (`blockLinesToSpans`) has a unit test. Note: chunk
ids are canonicalized to the fixed-size set (real 416 chunk keys matched — no observed
topic/scene chunk drift).

Summary caveat: `kb.summaries` had 13 base rows but only 10 are in the registry for 416, and
3 summaries' base spans differ from their registry spans. The function uses registry
identity (the established convention) and returns empty for base summaries absent from the
registry. This base/registry summary divergence is a pre-existing summary-pipeline issue,
independent of this work.

Implication of cutover: on-demand values will differ slightly from today's stored values
**where stored was stale** — i.e. the on-demand graph is the corrected, symmetric one.

Stage 2 (readers cut over, done 2026-06-17): all `connected_artifacts` reads now call
`kb.connected_artifacts(input_record_id, '<type>', id)`:
- API: `kbhandler/artifact_wiki_fetch.go` (entity, relation fetchers).
- Artifact-file generators: `extract-metrics.go`, `extract-semantic-projections.go`,
  `extract-provisions.go`, `extract-entity-relation.go` (entity + relation),
  `extract-inventory-items.go`, `generate-scene-blocks-processor.go`.
- (Topics have no `connected_artifacts` reader.)

The `buildArtifactConnectedArtifacts` writer is intentionally **left running** for now so the
columns stay populated as a fallback (fully reversible intermediate state). Note the writer
has a latent id-mapping bug for summaries/provisions (base id ≠ registry `artifact_id`), but
its output is now unused by readers.

Caveat: on-demand values are computed from the **current** registry + `kb.chunk_ranges`, so
records not yet reprocessed with the chunk-range wiring will have empty `chunks` (and
edges only as current registry state allows). Reprocess records to populate them.

Stage 3 (done 2026-06-17): persistence dropped. `connected_artifacts` is now computed purely
on demand.
- Writer removed: `buildArtifactConnectedArtifacts` and its 5 call sites
  (`search_artifact_indexing.go`, `metric_indexing.go`, `semantic_projection_indexing.go`,
  `scene_block_indexing.go`, `inventory_item_indexing.go`) deleted, plus the now-dead
  `connectedArtifacts` struct, `sortedLineSetKeys`, `semanticProjectionIndexConfig`, and the
  writer unit/integration tests.
- `connected_artifacts` removed from every CREATE TABLE / ALTER ADD / INSERT in Go
  (`extract-metrics.go`, `extract-metric-handler.go`, `extract-entity-relation.go`,
  `extract-inventory-items.go`, `extract-semantic-projections.go`).
- Columns dropped from all 9 family tables: migration
  `20260617000002_drop_connected_artifacts_columns.sql` (verified: 0 `connected_artifacts`
  columns remain; `kb.connected_artifacts(...)` returns correctly).
- `kb.chunk_ranges` + the populate wiring (semantic-projection + metric indexing) remain, as
  the function depends on them.

The only thing still reading line-overlap connections is `kb.connected_artifacts(...)`; the
artifact's line spans (+ `kb.chunk_ranges`) are the sole source of truth. Option A complete.

### Spike status: `kb.metrics` (done, 2026-06-16)

A proof-of-concept of the "purest form" is implemented and verified for `kb.metrics`
only. Migration:
`ChenWeb/project_migrations/20260616000001_add_line_range_to_kb_metrics.sql`.

Key refinement learned from the spike: steps 1 (column) and the per-extractor dual-write
collapse into a single **`STORED` generated column** that derives the range from
`source_line_spans`, so no Go write-path change is needed and the range can never drift
from the spans:

- `kb.line_spans_to_int8multirange(jsonb)` — an `IMMUTABLE` PL/pgSQL function parsing each
  `"N"` / `"A:B"` / `"A-B"` element (end inclusive, `start > 0`, `end >= start`), matching
  `parseMetricLineSpan` in `extract-metrics.go`.
- `kb.metrics.line_range int8multirange GENERATED ALWAYS AS
  (kb.line_spans_to_int8multirange(source_line_spans)) STORED` — backfills existing rows
  automatically and recomputes on every insert/update.
- `idx_kb_metrics_line_range` GiST index; confirmed used for `&&` overlap probes
  (Bitmap Index Scan).

Verification: the SQL function reproduced the Go line set on all 2664 existing metric rows
(0 mismatches), and `ChenWeb/server/api/doc-processing/metric_line_range_parity_test.go`
asserts SQL `&&` overlap equals Go `spansOverlapLineSet` (live-DB test gated on
`CHENWEB_PG_TEST_DSN`; skips otherwise). Requires PostgreSQL 14+ for multirange types
(staging runs 18.2).

### Rollout status: all artifact-family tables (done, 2026-06-16)

The generated-column pattern is now applied to every artifact-family table, not just
`kb.metrics`. Migration:
`ChenWeb/project_migrations/20260616000002_add_line_range_to_artifact_tables.sql`.

- `line_range int8multirange` STORED generated column + `idx_kb_<table>_line_range` GiST
  index added to: `entities`, `relations`, `scene_objects`, `semantic_projections`
  (these use `line_spans`), and `inventory_items`, `provisions`, `summaries`, `topics`
  (these use `source_line_spans`). All reuse `kb.line_spans_to_int8multirange`.
- Backfill verified: 0 mismatches against an independent expansion across all 8 tables
  (~50k rows total).
- Deferred: `kb.search_artifacts` and its partitions (`search_artifacts_*`) also carry
  `source_line_spans` but are a partitioned table; rolling the generated column + GiST
  index onto the partitioned parent is a separate follow-up with its own DDL caveats.

### Step 3 validation: SQL self-join is correct and complete (2026-06-16)

The SQL range-overlap self-join — `a.input_record_id = b.input_record_id AND
a.line_range && b.line_range` — was validated read-only against the stored
`connected_artifacts` for metric → semantic_projections across all 2664 metrics:

- 580 differences, and **all 580 are cases where the stored value was empty but the SQL
  found valid overlaps** (stale / never-populated older records). There were **zero** cases
  where the SQL missed a connection the stored data had, and zero where both were
  non-empty but differed.
- Conclusion: the SQL path is a correct drop-in and is strictly more complete than the
  currently materialized data.

### Step 3/4 cutover: hybrid SQL + Go (done, 2026-06-16)

Decision taken: **hybrid**. Artifact↔artifact edges are computed by a single SQL
self-join; chunk edges stay in Go. Reason: `connected_artifacts` includes a `chunks` key,
but chunks are **not** a per-row artifact table with line spans — `kb.chunks` stores
run-level `overlap_lines` / `normal_lines` / `chunk_lines` text, and chunk edges are
computed against the in-memory `[]Block` during processing. So the SQL self-join replaces
the 9 artifact families (which now have `line_range`) but cannot produce `chunks` edges
without materializing per-chunk line ranges.

Implementation, in `ChenWeb/server/api/doc-processing/artifact_indexing.go`
(`buildArtifactConnectedArtifacts`):
- Also added `line_range` to the registry `kb.search_artifacts` (migration
  `20260616000003`) so the self-join runs once over the unified registry rather than as
  per-family joins.
- The per-family ref loads + Go set intersection are replaced by one query:
  `SELECT s.artifact_id, t.artifact_type, t.artifact_id FROM kb.search_artifacts s JOIN
  kb.search_artifacts t ON t.input_record_id = s.input_record_id AND t.artifact_type =
  ANY($targets) AND s.line_range && t.line_range WHERE s.input_record_id = $rec AND
  s.artifact_type = $self`. Results are grouped per source artifact in Go and merged with
  the Go-computed `chunks`. This is safe because the source family is reindexed into the
  registry immediately before this step, and the pipeline already required targets to be
  registered.
- Removed the now-dead `loadSemanticProjectionRefsForConnections` and `overlappingRefIDs`
  helpers (`loadArtifactRefsFromRegistry` / `artifactRefFromRegistry` stay — still used by
  `connections_store.go`).

Not done (deliberately): no backfill of existing `connected_artifacts`. New/reprocessed
records get the SQL-derived edges; the ~580 stale/empty metric rows (and similar in other
families) are left as-is until a backfill is run deliberately.

# 3 Connection Design

Below are the artifacts the system currently supports:
- Doc Metadata
- Summaries
- Semantic Projections
- Topics
- Scene Objects
- Provisions
- Metrics
- Entities
- Relations
- Inventory Items

Artifacts that belong to the same doc are all stored in the same ARTIFACT_DIR directory.

## 3.1 Metrics

Metric indexing (3.1.1–3.1.5) runs in the doc-processor pipeline's **Phase C
(post-process)**, after every doc processor for the record has finished — never inside the
metrics processor itself — because it reads other artifacts (semantic projections, topics,
scenes, provisions, entities, inventory items) that may not exist yet during Phase B.

### 3.1.1 Add to `kb.search_artifacts`
Add all metrics of a document to `kb.search_artifacts` in its post processing.

### 3.1.2 Connections by Overlapped Lines
Below are the connections by overlapped line numbers:
- `kb.metrics.connected_artifacts.chunks`: an arry of `chunk_id` of the chunks that have at least one overlapped line with the metric. Should never be empty!
- `kb.metrics.connected_artifacts.semantic_projects`: an arry of `proj_id` of the semantic projections that have at least one overlapped line with the metric. Should never be empty!
- `kb.metrics.connected_artifacts.summaries`: an array of `summary_id` of the summaries that have at least one overlapped line with the metric. It may be empty.
- `kb.metrics.connected_artifacts.topics`: an array of `topic_id` of the topics that have at least one overlapped line with the metric. It may be empty.
- `kb.metrics.connected_artifacts.scenes`: an array of `scene_id` of the scene objects that have at least one overlapped line with the metric. It may be empty.
- `kb.metrics.connected_artifacts.provisions`: an array of `prov_id` of the provisions that have at least one overlapped line with the metric. It may be empty.
- `kb.metrics.connected_artifacts.entities`: an array of `entity_id` of the entities that have at least one overlapped line with the metric. It may be empty.
- `kb.metrics.connected_artifacts.relations`: an array of `relation_id` of the relations that have at least one overlapped line with the metric. It may be empty.
- `kb.metrics.connected_artifacts.inv_items`: an array of `inv_items` of the inventory items that have at least one overlapped with the metric. It may be empty.

These relations are not added to `kb.artifact_connections`.

## 3.1.3 Metric and Artifact Categories
It connects a metric to its artifact categories.
- If `kb.metrics.metric_categories` is null or empty, it is an error
- Use `kb.metrics.metric_categories` to find all artifact categories from `kb.artifact_categories`
- Do not write metric-category membership to `kb.category_instance`
- For each artifact category, add upsert a record to `kb.artifact_connections` with:
	- `source_type` = 'metric'
	- `source_id` = `kb.metrics.metric_id`
	- `target_type` = `kb.artifact_categories.category_type`
	- `target_id` = `kb.artifact_categories.category_key`
	- `relation_name` = 'belong_to'
	- `relation_method` = 'category_name'
	- `source_record_id` = `kb.inputs.id`
	- `target_record_id` = `kb.inputs.id`
	- `extra_info.category_id` = `kb.artifact_categories.category_id`

## 3.1.4 Index Metrics by Category Trees
Use 'kb.metrics.source_line_spans' to find category paths by
```text
	kb.metrics.input_record_id = kb.semantic_projections.input_record_id and
	kb.metries.source_line_spans has at least one overlap line with kb.semantic_projections.line_spans

	return kb.semantic_projections.category_paths_en
```

If no category paths are found, it is an error.
For each category path, add the metric to the file 'metrics.txt' in the category path.

## 3.1.5 Connect Artifacts
- Use `kb.metrics.search_document` to hybrid search (i.e., BM25 and embedding similar search) `kb.search_artifacts`
- For each accepted similar artifact, upsert a record to `kb.artifact_connections`
  (`source_type='metric'`, `relation_method='hybrid_search'`, `relation_name='semantically_related'`).
- Implementation status: active in `ChenWeb/server/api/doc-processing/metric_indexing.go`
  via the shared artifact-indexing hybrid connector.

Similarity acceptance (resolved): reuse the implemented lexical + pgvector RRF hybrid
search (`rrf_k=60`). Accept a candidate when its embedding cosine similarity
`>= ARTIFACT_CONNECT_MIN_COSINE` (default `0.75`) **or** its lexical score
`>= artifact_search.min_rank`; rank by RRF score and keep at most
`METRIC_CONNECT_MAX_LINKS` (default `10`), excluding the metric's own row. Connections are
cross-document and replaced idempotently per source metric. Full policy:
`KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-metrics-spec.md` →
"Connect Artifacts", and the hybrid mechanics in
`KnowledgeStore/Capsules/coding-capsules/llm-wiki/hybrid-search.md`.

How `ChenWeb/config.toml` `[artifact_search]` relates to this section:
- `dictionary`: the PostgreSQL text-search dictionary used for lexical tokenization and ranking. The current config uses `"simple"`, so lexical matching stays close to raw tokens instead of applying language-specific stemming. This setting is reused by the artifact-connection lexical search.
- `min_rank`: the lexical acceptance floor for hybrid connections. In this section, a candidate may be accepted even if its embedding score is below `ARTIFACT_CONNECT_MIN_COSINE`, as long as its lexical score is at least `artifact_search.min_rank`.
- `default_page_size`, `max_page_size`, `preview_max_words`, and `phrase_friendly`: these are for the dedicated metric search API and UI behavior, not for artifact-connection acceptance. Respectively, they control default paging, maximum paging, snippet length, and whether free-text metric search uses phrase-friendly `websearch_to_tsquery` parsing instead of plain token parsing.

How `ChenWeb/config.toml` `[metric_search_weights]` works:
- These weights define the lexical score formula for the dedicated metric search endpoint. The handler computes a weighted sum of `ts_rank_cd(...)` across metric fields, so a higher number makes matches in that field contribute more to the final lexical score.
- `metric_keywords = 2.8` is the strongest signal, so keyword hits matter most. `metric_name = 1.8` and `metric_subject = 1.5` are the next strongest, making explicit names and subjects more influential than body text.
- `metric_desc = 1.0` and `metric_context = 0.8` give supporting narrative text moderate influence. `value_class = 0.7`, `category_paths = 0.6`, `metric_unit = 0.5`, and `table_name_or_section = 0.4` are weaker tie-breaker-style signals.
- These weights are metric-specific and only shape the dedicated metric search endpoint. The connector currently reuses `artifact_search.dictionary` and `artifact_search.min_rank`, while hybrid candidate ranking is done over `kb.search_artifacts` with lexical rank plus embedding similarity fused by RRF.

## 3.2 Semantic Projections

Semantic projection indexing (3.1.1–3.1.5) runs in the doc-processor pipeline's **Phase C
(post-process)**, after every doc processor for the record has finished — never inside the
processor itself — because it reads other artifacts that may not exist yet during Phase B.

### 3.2.1 Add to `kb.search_artifacts`
Add all semantic projections of a document to `kb.search_artifacts` in its post processing.

### 3.2.2 Connections by Overlapped Lines
Below are the connections by overlapped line numbers:
- `kb.semantic_projections.connected_artifacts.chunk`: `chunk_id` of the chunk that share the same lines. Should never be invalid!
- `kb.semantic_projections.connected_artifacts.metrics`: an arry of `metric_id` of the metrics that have at least one overlapped line with the semantic projection. It may be empty!
- `kb.semantic_projections.connected_artifacts.summaries`: an array of `summary_id` of the summaries that have at least one overlapped line with the semantic projection. It may be empty.
- `kb.semantic_projections.connected_artifacts.topics`: an array of `topic_id` of the topics that have at least one overlapped line with the semantic projection. It may be empty.
- `kb.semantic_projections.connected_artifacts.scenes`: an array of `scene_id` of the scene objects that have at least one overlapped line with the semantic projection. It may be empty.
- `kb.semantic_projections.connected_artifacts.provisions`: an array of `prov_id` of the provisions that have at least one overlapped line with the semantic projection. It may be empty.
- `kb.semantic_projections.connected_artifacts.entities`: an array of `entity_id` of the entities that have at least one overlapped line with the semantic projection. It may be empty.
- `kb.semantic_projections.connected_artifacts.relations`: an array of `relation_id` of the relations that have at least one overlapped line with the semantic projection. It may be empty.
- `kb.semantic_projections.connected_artifacts.inv_items`: an array of `inv_items` of the inventory items that have at least one overlapped with the semantic projection. It may be empty.

These relations are not added to `kb.artifact_connections`.

## 3.2.3 Index Semantic Projections by Category Tree
For each semantic projection, use 'kb.semantic_projections.line_spans' to find category paths by
```text
	kb.semantic_projections.input_record_id = kb.semantic_projections.input_record_id and
	kb.semantic_projections.line_spans has at least one overlap line with kb.semantic_projections.line_spans

	return kb.semantic_projections.category_paths_en
```

If no category paths are found, it is an error.
For each category path, add the semantic projection to the file 'semantic_projections.txt' in the category path.

## 3.2.4 Connect Artifacts
- Use `kb.semantic_objects.search_document` to hybrid search (i.e., BM25 and embedding similar search) `kb.search_artifacts`
- For each accepted similar artifact, upsert a record to `kb.artifact_connections`
  (`source_type='semantic_object'`, `relation_method='hybrid_search'`, `relation_name='semantically_related'`).

Similarity acceptance (resolved): reuse the implemented lexical + pgvector RRF hybrid
search (`rrf_k=60`). Accept a candidate when its embedding cosine similarity
`>= ARTIFACT_CONNECT_MIN_COSINE` (default `0.75`) **or** its lexical score
`>= artifact_search.min_rank`; rank by RRF score and keep at most
`ARTIFACT_CONNECT_MAX_LINKS` (default `10`), excluding the metric's own row. Connections are
cross-document and replaced idempotently per source metric. Full policy:
`KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-metrics-spec.md` →
"Connect Artifacts", and the hybrid mechanics in
`KnowledgeStore/Capsules/coding-capsules/llm-wiki/hybrid-search.md`.

## 3.3 Inventory Items

Inventory item indexing (3.3.1–3.3.5) runs in the doc-processor pipeline's **Phase C
(post-process)**, after every doc processor for the record has finished — never inside the
processor itself — because it reads other artifacts that may not exist yet during Phase B.

### 3.3.1 Add to `kb.search_artifacts`
Add all inventory items of a document to `kb.search_artifacts` in its post processing.

### 3.3.2 Connections by Overlapped Lines
Below are the connections by overlapped line numbers:
- `kb.inventory_items.connected_artifacts.chunks`: an arry of `chunk_id` of the chunks that have at least one overlapped line with the inventory item. Should never be empty!
- `kb.inventory_items.connected_artifacts.semantic_projects`: an arry of `proj_id` of the semantic projections that have at least one overlapped line with the inventory item. Should never be empty!
- `kb.inventory_items.connected_artifacts.summaries`: an array of `summary_id` of the summaries that have at least one overlapped line with the inventory item. It may be empty.
- `kb.inventory_items.connected_artifacts.topics`: an array of `topic_id` of the topics that have at least one overlapped line with the inventory item. It may be empty.
- `kb.inventory_items.connected_artifacts.scenes`: an array of `scene_id` of the scene objects that have at least one overlapped line with the inventory item. It may be empty.
- `kb.inventory_items.connected_artifacts.provisions`: an array of `prov_id` of the provisions that have at least one overlapped line with the inventory items. It may be empty.
- `kb.inventory_items.connected_artifacts.entities`: an array of `entity_id` of the entities that have at least one overlapped line with the inventory item. It may be empty.
- `kb.inventory_items.connected_artifacts.relations`: an array of `relation_id` of the relations that have at least one overlapped line with the inventory item. It may be empty.
- `kb.inventory_items.connected_artifacts.metrics`: an array of `metric_id` of the metrics that have at least one overlapped with the inventory item. It may be empty.

These relations are not added to `kb.artifact_connections`.

### 3.3.3 Inventory Items and Artifact Categories
It connects an inventory item to its artifact categories.
- If `kb.inventory_items.item_categories` is null or empty, it is an error
- Use `kb.inventory_items.item_categories` to find all artifact categories from `kb.artifact_categories`
- Do not write inventory-item category membership to `kb.category_instance`
- For each artifact category, add upsert a record to `kb.artifact_connections` with:
	- `source_type` = 'inventory_item'
	- `source_id` = `kb.inventory_item.inventory_item_id`
	- `target_type` = `kb.artifact_categories.category_type`
	- `target_id` = `kb.artifact_categories.category_key`
	- `relation_name` = 'belong_to'
	- `relation_method` = 'category_name'
	- `source_record_id` = `kb.inputs.id`
	- `target_record_id` = `kb.inputs.id`
	- `extra_info.category_id` = `kb.artifact_categories.category_id`

### 3.3.4 Index Inventory Items by Category Tree
Use 'kb.inventory_items.source_line_spans' to find category paths by
```text
	kb.inventory_items.input_record_id = kb.semantic_projections.input_record_id and
	kb.inventory_items.source_line_spans has at least one overlap line with kb.semantic_projections.line_spans

	return kb.semantic_projections.category_paths_en
```

If no category paths are found, it is an error.
For each category path, add the inventory item to the file 'inventory_items.txt' in the category path.

### 3.3.5 Connect Artifacts
The same as Section 3.1.5, except that it uses `kb.inventory_items.search_document` to hybrid search `kb.search_artifacts`
- Implementation status: active in `ChenWeb/server/api/doc-processing/inventory_item_indexing.go`
  via the shared artifact-indexing hybrid connector.

## 3.4 Scenes

Scene Blocks (or Scenes) indexing (3.4.1–3.4.4) runs in the doc-processor pipeline's **Phase C
(post-process)**, after every doc processor for the record has finished — never inside the
processor itself — because it reads other artifacts that may not exist yet during Phase B.

### 3.4.1 Add to `kb.search_artifacts`
Add all scens of a document to `kb.search_artifacts` in its post processing.

### 3.4.2 Connections by Overlapped Lines
Below are the connections by overlapped line numbers:
- `kb.scene_objects.connected_artifacts.chunks`: an arry of `chunk_id` of the chunks that have at least one overlapped line with the scene. Should never be empty!
- `kb.scene_objects.connected_artifacts.semantic_projects`: an arry of `proj_id` of the semantic projections that have at least one overlapped line with the scene. Should never be empty!
- `kb.scene_objects.connected_artifacts.summaries`: an array of `summary_id` of the summaries that have at least one overlapped line with the scene. It may be empty.
- `kb.scene_objects.connected_artifacts.topics`: an array of `topic_id` of the topics that have at least one overlapped line with the scene. It may be empty.
- `kb.scene_objects.connected_artifacts.inv_items`: an array of `inventory_item_id` of the inventory items that have at least one overlapped line with the scene. It may be empty.
- `kb.scene_objects.connected_artifacts.provisions`: an array of `prov_id` of the provisions that have at least one overlapped line with the scene. It may be empty.
- `kb.scene_objects.connected_artifacts.entities`: an array of `entity_id` of the entities that have at least one overlapped line with the scene. It may be empty.
- `kb.scene_objects.connected_artifacts.relations`: an array of `relation_id` of the relations that have at least one overlapped line with the scene. It may be empty.
- `kb.scene_objects.connected_artifacts.metrics`: an array of `metric_id` of the metrics that have at least one overlapped with the scene. It may be empty.

These relations are not added to `kb.artifact_connections`.

### 3.4.3 Index Scenes by Category Tree
Use 'kb.scene_objects.line_spans' to find category paths by
```text
	kb.scene_objects.input_record_id = kb.semantic_projections.input_record_id and
	kb.scene_objects.line_spans has at least one overlap line with kb.semantic_projections.line_spans

	return kb.semantic_projections.category_paths_en
```

If no category paths are found, it is an error.
For each category path, add the scene block to the file 'scenes.txt' in the category path.

### 3.4.4 Connect Artifacts
The same as Section 3.1.5, except that it uses `kb.scene_objects.search_document` to hybrid search `kb.search_artifacts`

How `ChenWeb/config.toml` `[scene_blocks_search_weights]` works:
- These weights shape the scene block text that is indexed into `kb.search_artifacts`.
- `title` and `keywords` are intended to be the strongest lexical anchors; `scene_type` and `summary` provide supporting context.
- The hybrid connector still reuses `artifact_search.dictionary` and `artifact_search.min_rank` for acceptance and ranking policy.

## 3.5 Summaries

Summary indexing (3.5.1–3.5.3) runs in the doc-processor pipeline's **Phase C
(post-process)**, after every doc processor for the record has finished — never inside the
summary generator itself — because it reads other artifacts that may not exist yet during
Phase B.

### 3.5.1 Add to `kb.search_artifacts`
- Add all summaries of a document to `kb.search_artifacts` in post processing.

### 3.5.2 Connections by Overlapped Lines
Below are the connections by overlapped line numbers:
- `kb.summaries.connected_artifacts.chunks`: an array of `chunk_id` of the chunks that have at least one overlapped line with the summary. Should never be empty for level-0 summaries.
- `kb.summaries.connected_artifacts.semantic_projects`: an array of `proj_id` of the semantic projections that have at least one overlapped line with the summary. It may be empty.
- `kb.summaries.connected_artifacts.topics`: an array of `topic_id` of the topics that have at least one overlapped line with the summary. It may be empty.
- `kb.summaries.connected_artifacts.scenes`: an array of `scene_id` of the scene objects that have at least one overlapped line with the summary. It may be empty.
- `kb.summaries.connected_artifacts.provisions`: an array of `prov_id` of the provisions that have at least one overlapped line with the summary. It may be empty.
- `kb.summaries.connected_artifacts.entities`: an array of `entity_id` of the entities that have at least one overlapped line with the summary. It may be empty.
- `kb.summaries.connected_artifacts.relations`: an array of `relation_id` of the relations that have at least one overlapped line with the summary. It may be empty.
- `kb.summaries.connected_artifacts.metrics`: an array of `metric_id` of the metrics that have at least one overlapped line with the summary. It may be empty.
- `kb.summaries.connected_artifacts.inv_items`: an array of `inventory_item_id` of the inventory items that have at least one overlapped line with the summary. It may be empty.

These relations are not added to `kb.artifact_connections`.

### 3.5.3 Index Summaries by Category Tree
Use 'kb.summaries.source_line_spans' to find category paths by
```text
	kb.summaries.input_record_id = kb.semantic_projections.input_record_id and
	kb.summaries.source_line_spans has at least one overlap line with kb.semantic_projections.line_spans

	return kb.semantic_projections.category_paths_en
```

If no category paths are found, it is an error.
For each category path, add the summary to the file 'summaries.txt' in the category path.

### 3.5.4 Connect Artifacts
- Use `kb.summaries.search_document` to hybrid search `kb.search_artifacts`.
- Keep the existing line-overlap `has-summary` edges for level-0 summaries, and additionally upsert hybrid semantic links with
  `source_type='summary'`, `relation_method='hybrid_search'`, `relation_name='semantically_related'`.

How `ChenWeb/config.toml` `[summaries_search_weights]` works:
- These weights shape the summary text that is indexed into `kb.search_artifacts`.
- `summary_text` is the main signal; `keywords` and `category_paths` are supporting lexical hints.
- The hybrid connector still reuses `artifact_search.dictionary` and `artifact_search.min_rank` for acceptance and ranking policy.

## 3.6 Topics

Topic indexing (3.6.1–3.6.3) runs in the doc-processor pipeline's **Phase C
(post-process)**, after every doc processor for the record has finished — never inside the
topic generator itself — because it reads other artifacts that may not exist yet during
Phase B.

### 3.6.1 Add to `kb.search_artifacts`
- Add all topics of a document to `kb.search_artifacts` in post processing.

### 3.6.2 Connections by Overlapped Lines
Below are the connections by overlapped line numbers:
- `kb.topics.connected_artifacts.chunks`: an array of `chunk_id` of the chunks that have at least one overlapped line with the topic. Should never be empty.
- `kb.topics.connected_artifacts.semantic_projects`: an array of `proj_id` of the semantic projections that have at least one overlapped line with the topic. It may be empty.
- `kb.topics.connected_artifacts.summaries`: an array of `summary_id` of the summaries that have at least one overlapped line with the topic. It may be empty.
- `kb.topics.connected_artifacts.scenes`: an array of `scene_id` of the scene objects that have at least one overlapped line with the topic. It may be empty.
- `kb.topics.connected_artifacts.provisions`: an array of `prov_id` of the provisions that have at least one overlapped line with the topic. It may be empty.
- `kb.topics.connected_artifacts.entities`: an array of `entity_id` of the entities that have at least one overlapped line with the topic. It may be empty.
- `kb.topics.connected_artifacts.relations`: an array of `relation_id` of the relations that have at least one overlapped line with the topic. It may be empty.
- `kb.topics.connected_artifacts.metrics`: an array of `metric_id` of the metrics that have at least one overlapped line with the topic. It may be empty.
- `kb.topics.connected_artifacts.inv_items`: an array of `inventory_item_id` of the inventory items that have at least one overlapped line with the topic. It may be empty.

These relations are not added to `kb.artifact_connections`.

### 3.6.3 Index Topics by Category Tree
Use 'kb.topics.source_line_spans' to find category paths by
```text
	kb.topics.input_record_id = kb.semantic_projections.input_record_id and
	kb.topics.source_line_spans has at least one overlap line with kb.semantic_projections.line_spans

	return kb.semantic_projections.category_paths_en
```

If no category paths are found, it is an error.
For each category path, add the topic to the file 'topics.txt' in the category path.

### 3.6.4 Connect Artifacts
- Use `kb.topics.search_document` to hybrid search `kb.search_artifacts`.
- Keep the existing line-overlap `has-topic` edges, and additionally upsert hybrid semantic links with
  `source_type='topic'`, `relation_method='hybrid_search'`, `relation_name='semantically_related'`.

How `ChenWeb/config.toml` `[topics_search_weights]` works:
- These weights shape the topic text that is indexed into `kb.search_artifacts`.
- `topic_desc` is the main signal; `keywords` and `category_paths` reinforce topical matching, while `topic_type` is a lighter structural hint.
- The hybrid connector still reuses `artifact_search.dictionary` and `artifact_search.min_rank` for acceptance and ranking policy.

## 3.7 Provisions

Provision indexing (3.7.1–3.7.3) runs in the doc-processor pipeline's **Phase C
(post-process)**, after every doc processor for the record has finished — never inside the
provisions processor itself — because it reads other artifacts that may not exist yet
during Phase B.

### 3.7.1 Add to `kb.search_artifacts`
- Add all provisions of a document to `kb.search_artifacts` in post processing.

### 3.7.2 Connections by Overlapped Lines
Below are the connections by overlapped line numbers:
- `kb.provisions.connected_artifacts.chunks`: an array of `chunk_id` of the chunks that have at least one overlapped line with the provision. Should never be empty.
- `kb.provisions.connected_artifacts.semantic_projects`: an array of `proj_id` of the semantic projections that have at least one overlapped line with the provision. It may be empty.
- `kb.provisions.connected_artifacts.summaries`: an array of `summary_id` of the summaries that have at least one overlapped line with the provision. It may be empty.
- `kb.provisions.connected_artifacts.topics`: an array of `topic_id` of the topics that have at least one overlapped line with the provision. It may be empty.
- `kb.provisions.connected_artifacts.scenes`: an array of `scene_id` of the scene objects that have at least one overlapped line with the provision. It may be empty.
- `kb.provisions.connected_artifacts.entities`: an array of `entity_id` of the entities that have at least one overlapped line with the provision. It may be empty.
- `kb.provisions.connected_artifacts.relations`: an array of `relation_id` of the relations that have at least one overlapped line with the provision. It may be empty.
- `kb.provisions.connected_artifacts.metrics`: an array of `metric_id` of the metrics that have at least one overlapped line with the provision. It may be empty.
- `kb.provisions.connected_artifacts.inv_items`: an array of `inventory_item_id` of the inventory items that have at least one overlapped line with the provision. It may be empty.

These relations are not added to `kb.artifact_connections`.

### 3.7.3 Index Provisions by Category Tree
Use 'kb.provisions.source_line_spans' to find category paths by
```text
	kb.provisions.input_record_id = kb.semantic_projections.input_record_id and
	kb.provisions.source_line_spans has at least one overlap line with kb.semantic_projections.line_spans

	return kb.semantic_projections.category_paths_en
```

If no category paths are found, it is an error.
For each category path, add the provision to the file 'provisions.txt' in the category path.

### 3.7.4 Connect Artifacts
- Use `kb.provisions.search_document` to hybrid search `kb.search_artifacts`.
- Keep the existing line-overlap `has-provision` edges, and additionally upsert hybrid semantic links with
  `source_type='provision'`, `relation_method='hybrid_search'`, `relation_name='semantically_related'`.

How `ChenWeb/config.toml` `[provisions_search_weights]` works:
- These weights shape the provision text that is indexed into `kb.search_artifacts`.
- `provision_name`, `provision_desc`, and `keywords` are the primary lexical signals; `provision_type` and `category_paths` are weaker supporting context.
- The hybrid connector still reuses `artifact_search.dictionary` and `artifact_search.min_rank` for acceptance and ranking policy.

## 3.8 Entities And Relations

Entity and relation indexing (3.8.1–3.8.4) runs in the doc-processor pipeline's
**Phase C (post-process)**, after every doc processor for the record has finished —
never inside the entity-relation processor itself — because it reads other artifacts
that may not exist yet during Phase B.

### 3.8.1 Add to `kb.search_artifacts`
- Add all entities and relations of a document to `kb.search_artifacts` in post processing.

### 3.8.2 Entity Connections by Overlapped Lines
Below are the connections by overlapped line numbers for entities:
- `kb.entities.connected_artifacts.chunks`: an array of `chunk_id` of the chunks that have at least one overlapped line with the entity. Should never be empty.
- `kb.entities.connected_artifacts.semantic_projects`: an array of `proj_id` of the semantic projections that have at least one overlapped line with the entity. It may be empty.
- `kb.entities.connected_artifacts.summaries`: an array of `summary_id` of the summaries that have at least one overlapped line with the entity. It may be empty.
- `kb.entities.connected_artifacts.topics`: an array of `topic_id` of the topics that have at least one overlapped line with the entity. It may be empty.
- `kb.entities.connected_artifacts.scenes`: an array of `scene_id` of the scene objects that have at least one overlapped line with the entity. It may be empty.
- `kb.entities.connected_artifacts.provisions`: an array of `prov_id` of the provisions that have at least one overlapped line with the entity. It may be empty.
- `kb.entities.connected_artifacts.relations`: an array of `relation_id` of the relations that have at least one overlapped line with the entity. It may be empty.
- `kb.entities.connected_artifacts.metrics`: an array of `metric_id` of the metrics that have at least one overlapped line with the entity. It may be empty.
- `kb.entities.connected_artifacts.inv_items`: an array of `inventory_item_id` of the inventory items that have at least one overlapped line with the entity. It may be empty.

These relations are not added to `kb.artifact_connections`.

### 3.8.3 Relation Connections by Overlapped Lines
Below are the connections by overlapped line numbers for relations:
- `kb.relations.connected_artifacts.chunks`: an array of `chunk_id` of the chunks that have at least one overlapped line with the relation. Should never be empty.
- `kb.relations.connected_artifacts.semantic_projects`: an array of `proj_id` of the semantic projections that have at least one overlapped line with the relation. It may be empty.
- `kb.relations.connected_artifacts.summaries`: an array of `summary_id` of the summaries that have at least one overlapped line with the relation. It may be empty.
- `kb.relations.connected_artifacts.topics`: an array of `topic_id` of the topics that have at least one overlapped line with the relation. It may be empty.
- `kb.relations.connected_artifacts.scenes`: an array of `scene_id` of the scene objects that have at least one overlapped line with the relation. It may be empty.
- `kb.relations.connected_artifacts.provisions`: an array of `prov_id` of the provisions that have at least one overlapped line with the relation. It may be empty.
- `kb.relations.connected_artifacts.entities`: an array of `entity_id` of the entities that have at least one overlapped line with the relation. It may be empty.
- `kb.relations.connected_artifacts.metrics`: an array of `metric_id` of the metrics that have at least one overlapped line with the relation. It may be empty.
- `kb.relations.connected_artifacts.inv_items`: an array of `inventory_item_id` of the inventory items that have at least one overlapped line with the relation. It may be empty.

These relations are not added to `kb.artifact_connections`.

### 3.8.4 Entities and Artifact Categories
It connects an entity to its artifact categories.
- If `kb.entities.categories` is null or empty, it is an error
- Use `kb.entities.categories` to find all artifact categories from `kb.artifact_categories`
- Do not write entity category membership to `kb.category_instance`
- For each artifact category, upsert a record to `kb.artifact_connections` with:
	- `source_type` = 'entity'
	- `source_id` = `kb.entities.entity_id`
	- `target_type` = `kb.artifact_categories.category_type`
	- `target_id` = `kb.artifact_categories.category_key`
	- `relation_name` = 'belong_to'
	- `relation_method` = 'category_name'
	- `source_record_id` = `kb.inputs.id`
	- `target_record_id` = `kb.inputs.id`
	- `extra_info.category_id` = `kb.artifact_categories.category_id`

### 3.8.5 Relations and Artifact Categories
It connects a relation to its artifact categories.
- If `kb.relations.categories` is null or empty, it is an error
- Use `kb.relations.categories` to find all artifact categories from `kb.artifact_categories`
- Do not write relation category membership to `kb.category_instance`
- For each artifact category, upsert a record to `kb.artifact_connections` with:
	- `source_type` = 'relation'
	- `source_id` = `kb.relations.relation_id`
	- `target_type` = `kb.artifact_categories.category_type`
	- `target_id` = `kb.artifact_categories.category_key`
	- `relation_name` = 'belong_to'
	- `relation_method` = 'category_name'
	- `source_record_id` = `kb.inputs.id`
	- `target_record_id` = `kb.inputs.id`
	- `extra_info.category_id` = `kb.artifact_categories.category_id`

### 3.8.6 Entity Names and Relation Predicates
Entity names and relation predicates are dictionary-style graph anchors.

These edges are kept even though entities and relations are also searchable through
BM25 + vector search + RRF fusion. Search is ranked and threshold-dependent; dictionary
edges are deterministic. They help an LLM traverse all instances of the same normalized
name or predicate across documents without depending on search ranking.

Entity-name edges:
- Normalize `kb.entities.entity_en`; if it is empty, fall back to `kb.entities.entity`
- Upsert/catalogue the normalized key in `kb.entity_names`
- Upsert a record to `kb.artifact_connections` with:
	- `source_type` = 'entity_name'
	- `source_id` = normalized entity-name key, e.g. `editorial_seventh_branch`
	- `target_type` = 'entity'
	- `target_id` = `kb.entities.entity_id`
	- `relation_name` = 'has-instance'
	- `relation_method` = 'entity_name'
	- `source_record_id` = `kb.inputs.id`
	- `target_record_id` = `kb.inputs.id`

Relation-predicate edges:
- Normalize `kb.relations.predicate_en`; if it is empty, fall back to
  `kb.relations.predicate`
- Upsert/catalogue the normalized key in `kb.relation_predicates`
- Upsert a record to `kb.artifact_connections` with:
	- `source_type` = 'relation_predicate'
	- `source_id` = normalized predicate key
	- `target_type` = 'relation'
	- `target_id` = `kb.relations.relation_id`
	- `relation_name` = 'has-predicate'
	- `relation_method` = 'entity_relation'
	- `source_record_id` = `kb.inputs.id`
	- `target_record_id` = `kb.inputs.id`

Relation statement edges:
- For each resolved relation row with linked subject and object entity ids, upsert:
	- `source_type` = 'entity'
	- `source_id` = `kb.relations.subject_entity_id`
	- `target_type` = 'entity'
	- `target_id` = `kb.relations.object_entity_id`
	- `relation_name` = normalized predicate key
	- `relation_method` = 'entity_relation'
	- `source_record_id` = `kb.inputs.id`
	- `target_record_id` = `kb.inputs.id`

### 3.8.7 Index Entities by Category Tree
Use 'kb.entities.line_spans' to find category paths by
```text
	kb.entities.input_record_id = kb.semantic_projections.input_record_id and
	kb.entities.line_spans has at least one overlap line with kb.semantic_projections.line_spans

	return kb.semantic_projections.category_paths_en
```

If no category paths are found, it is an error.
For each category path, add the entity to the file 'entities.txt' in the category path.

### 3.8.8 Index Relations by Category Tree
Use 'kb.relations.line_spans' to find category paths by
```text
	kb.relations.input_record_id = kb.semantic_projections.input_record_id and
	kb.relations.line_spans has at least one overlap line with kb.semantic_projections.line_spans

	return kb.semantic_projections.category_paths_en
```

If no category paths are found, it is an error.
For each category path, add the relation to the file 'relations.txt' in the category path.

### 3.8.9 Connect Artifacts
- Use `kb.entities.search_document` to hybrid search `kb.search_artifacts` for entity-origin links.
- Use `kb.relations.search_document` to hybrid search `kb.search_artifacts` for relation-origin links.
- Upsert hybrid semantic links with `relation_method='hybrid_search'` and `relation_name='semantically_related'`.

How `ChenWeb/config.toml` `[entities_search_weights]` works:
- These weights shape the entity text that is indexed into `kb.search_artifacts`.
- `entity` is the main lexical anchor; `keywords`, `aliases`, `entity_type`, and `desc_text` provide supporting recall.

How `ChenWeb/config.toml` `[relations_search_weights]` works:
- These weights shape the relation text that is indexed into `kb.search_artifacts`.
- `subject`, `predicate`, and `object` are the main lexical anchors; `keywords` and `desc_text` provide supporting recall.
- For both entities and relations, the hybrid connector still reuses `artifact_search.dictionary` and `artifact_search.min_rank` for acceptance and ranking policy.

# References
[1] KnowledgeStore/Capsules/coding-capsules/categories/category-mgmt-spec.md
