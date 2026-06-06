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
- `kb.metrics.connected_artifacts.topics`: an array of `topic_id` of the topics that have at least one overlapped line with the metric. It may be empty.
- `kb.metrics.connected_artifacts.scenes`: an array of `scene_id` of the scene objects that have at least one overlapped line with the metric. It may be empty.
- `kb.metrics.connected_artifacts.provisions`: an array of `prov_id` of the provisions that have at least one overlapped line with the metric. It may be empty.
- `kb.metrics.connected_artifacts.entities`: an array of `entity_id` of the entities that have at least one overlapped line with the metric. It may be empty.
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
`>= METRIC_CONNECT_MIN_COSINE` (default `0.75`) **or** its lexical score
`>= metric_search.min_rank`; rank by RRF score and keep at most
`METRIC_CONNECT_MAX_LINKS` (default `10`), excluding the metric's own row. Connections are
cross-document and replaced idempotently per source metric. Full policy:
`KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-metrics-spec.md` →
"Connect Artifacts", and the hybrid mechanics in
`KnowledgeStore/Capsules/coding-capsules/llm-wiki/hybrid-search.md`.

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
- `kb.semantic_projections.connected_artifacts.topics`: an array of `topic_id` of the topics that have at least one overlapped line with the semantic projection. It may be empty.
- `kb.semantic_projections.connected_artifacts.scenes`: an array of `scene_id` of the scene objects that have at least one overlapped line with the semantic projection. It may be empty.
- `kb.semantic_projections.connected_artifacts.provisions`: an array of `prov_id` of the provisions that have at least one overlapped line with the semantic projection. It may be empty.
- `kb.semantic_projections.connected_artifacts.entities`: an array of `entity_id` of the entities that have at least one overlapped line with the semantic projection. It may be empty.
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

## 3.2.5 Connect Artifacts
- Use `kb.metrics.search_document` to hybrid search (i.e., BM25 and embedding similar search) `kb.search_artifacts`
- For each accepted similar artifact, upsert a record to `kb.artifact_connections`
  (`source_type='metric'`, `relation_method='hybrid_search'`, `relation_name='semantically_related'`).

Similarity acceptance (resolved): reuse the implemented lexical + pgvector RRF hybrid
search (`rrf_k=60`). Accept a candidate when its embedding cosine similarity
`>= METRIC_CONNECT_MIN_COSINE` (default `0.75`) **or** its lexical score
`>= metric_search.min_rank`; rank by RRF score and keep at most
`METRIC_CONNECT_MAX_LINKS` (default `10`), excluding the metric's own row. Connections are
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
- `kb.inventory_items.connected_artifacts.topics`: an array of `topic_id` of the topics that have at least one overlapped line with the inventory item. It may be empty.
- `kb.inventory_items.connected_artifacts.scenes`: an array of `scene_id` of the scene objects that have at least one overlapped line with the inventory item. It may be empty.
- `kb.inventory_items.connected_artifacts.provisions`: an array of `prov_id` of the provisions that have at least one overlapped line with the inventory items. It may be empty.
- `kb.inventory_items.connected_artifacts.entities`: an array of `entity_id` of the entities that have at least one overlapped line with the inventory item. It may be empty.
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
- `kb.scene_objects.connected_artifacts.topics`: an array of `topic_id` of the topics that have at least one overlapped line with the scene. It may be empty.
- `kb.scene_objects.connected_artifacts.inventory_items`: an array of `inventory_item_id` of the inventory items that have at least one overlapped line with the scene. It may be empty.
- `kb.scene_objects.connected_artifacts.provisions`: an array of `prov_id` of the provisions that have at least one overlapped line with the scene. It may be empty.
- `kb.scene_objects.connected_artifacts.entities`: an array of `entity_id` of the entities that have at least one overlapped line with the scene. It may be empty.
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

# References
[1] KnowledgeStore/Capsules/coding-capsules/categories/category-mgmt-spec.md
