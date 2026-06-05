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
- For each similar artifact, if any, upsert a record to `kb.artifact_connections`

Open Issue:
Need to determine how to determine the 'similar-ness' in the hybrid semantic search.

# References
[1] KnowledgeStore/Capsules/coding-capsules/categories/category-mgmt-spec.md
