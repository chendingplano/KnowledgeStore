# 1 Overview
Artifacts are connected in various forms. This document focuses on connecting artifacts
through shared lines.

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
- For each artifact category, add upsert a record to `kb.category_instance`

## 3.1.4 Index Metrics by Category Paths
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

## 3.2.3 Index Semantic Projections by Category Paths
For each semantic projection, use 'kb.semantic_projections.source_line_spans' to find category paths by 
```text
	kb.semantic_projections.input_record_id = kb.semantic_projections.input_record_id and
	kb.semantic_projections.source_line_spans has at least one overlap line with kb.semantic_projections.line_spans

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
- For each artifact category, upsert a record to `kb.category_instance`

### 3.3.4 Index Inventory Items by Category Paths
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

### 3.4.3 Index Scenes by Category Paths
Use 'kb.scene_objects.line_spans' to find category paths by 
```text
	kb.scene_objects.input_record_id = kb.semantic_projections.input_record_id and
	kb.scene_objects.line_spans has at least one overlap line with kb.semantic_projections.line_spans

	return kb.semantic_projections.category_paths_en
```

If no category paths are found, it is an error.
For each category path, add the metric to the file 'scenes.txt' in the category path.

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

### 3.5.3 Connect Artifacts
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

### 3.6.3 Connect Artifacts
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

### 3.7.3 Connect Artifacts
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

### 3.8.4 Connect Artifacts
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
