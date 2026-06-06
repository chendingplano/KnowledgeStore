A metric is a quantitative, measurable item used to evaluate, compare, monitor, verify, or assess something. Metrics are often defined in standards, specifications, requirements, policies, test plans, scorecards, or compliance documents.

This processor uses a multi-pass extraction strategy.

## Input

- `record_id`: the value of `kb.inputs.id`
- `chunks`: see the chunking spec
- file name

## Implementation

- The code is in `ChenWeb/`
- It may use functions/modules in `shared/`

## Multi-Pass

Single-pass design asks one LLM call to do all of the following at once:

- detect metric mentions
- decide whether each candidate is a real metric
- infer the final normalized metric schema
- translate fields
- generate category paths
- implicitly handle overlap cleanup and dedup

This caused:

- unstable extraction counts
- duplicate metrics from overlapping chunks
- prompt/schema overload on smaller models
- malformed or partial JSON outputs
- weak deterministic cleanup

### Multi-Pass Pipeline

To solve the single-pass problem, we will use multi-pass pipeline, which 
breaks the processing into multiple passes:

1. Pass 1: extract metric candidates from each chunk
2. Deterministic Step A: merge and deduplicate candidates across overlapping chunks
3. Pass 2: enrich candidates into final metric rows, batched by chunk (see `METRIC_ENRICH_GROUP_SIZE`)
4. Deterministic Step B: final metric dedup before persistence

### Pass 1: Metric Candidates

Pass 1 uses:

- model env: `EXTRACT_METRIC_CANDIDATES_MODEL_NAME`
- prompt env: `EXTRACT_METRIC_CANDIDATES_PROMPT`

Optional fallback:

- `EXTRACT_METRIC_CANDIDATES_MODEL_FALLBACK`

Pass 1 output:

```json
{
  "language": "string",
  "candidates": [
    {
      "metric_name_hint": "string",
      "subject_hint": "string",
      "evidence_quote": "string",
      "source_line_spans": ["12", "13:15"],
      "unit_hint": "string",
      "value_hint": "string",
      "confidence": 0.0,
      "confidence_reason": "string"
    }
  ]
}
```

Pass 1 rules:

- maximize recall for plausible metric candidates
- do not generate the full final metric schema
- do not generate category paths
- do not translate
- do not keep overlap-only candidates unless the same metric is supported by normal lines

Pass 2 batching:

- Candidates that share the same source chunk are grouped into one LLM call
- Batch size is controlled by `METRIC_ENRICH_GROUP_SIZE` env var (default: 5)
- The batch prompt sends all candidates and source lines once, reducing repeated input tokens
- Each batch returns a `metrics` array covering all candidates in that batch

Pass 2 uses:

- model env priority:
  - `ENRICH_METRICS_MODEL_NAME`
  - `EXTRACT_METRICS_MODEL_NAME`
- prompt env priority:
  - `ENRICH_METRICS_PROMPT`

Pass 2 output:

```json
{
  "language": "string",
  "metrics": [
    {
      "metric_name": "string",
      "metric_name_en": "string",
      "source_line_spans": ["12", "13:15"],
      "subject": "string",
      "subject_en": "string",
      "desc": "string",
      "desc_en": "string",
      "context": "string",
      "context_en": "string",
      "keywords": ["string"],
      "keywords_en": ["string"],
      "location_type": "sentence|bullet|table_row|table_cell|heading_context|mixed",
      "unit": "string",
      "unit_en": "string",
      "metric_value": "string",
      "value_data_type": "string",
      "value_range_type": "string",
      "value_class": "string",
      "value_class_en": "string",
      "formula_or_definition": "string",
      "threshold_or_target": "string",
      "measurement_frequency": "string",
      "metric_categories": ["string"],
      "confidence": 0.0,
      "is_explicit_metric": true,
      "table_name_or_section": "string",
      "reasoning_tags": ["string"]
    }
  ],
  "uncertain_metrics": []
}
```

Important notes:

- one output row = one metric
- use only the merged candidate and its supporting evidence
- `uncertain_metrics` may be returned by the LLM but are not persisted to `kb.metrics`
- `metric_categories` must contain one or more category keys suitable for lookup in `kb.artifact_categories`
- category paths are not generated or stored by the enrichment pass

### Deterministic Step B: Final Metric Dedup

`dedupeFinalMetricRows` deduplicates the enriched metric rows before persistence.

**Dedup key** — built by `normalizedMetricCandidateKey` over five fields (each lowercased, trimmed, and whitespace-collapsed, then joined with `|`):

1. `metric_name`
2. `subject`
3. `unit`
4. `metric_value`
5. normalized `source_line_spans` joined with `,`

`source_line_spans` normalization (`normalizeSourceLineSpans`):
- Accepts string spans (`"12"`, `"13:15"`), bare `float64` integers, or `{"line_number": N}` objects
- Discards zero/negative line numbers
- Sorts spans by start then end
- Merges adjacent or overlapping spans (gap ≤ 1) into a single span
- Returns canonical strings: `"N"` for single lines, `"N:M"` for ranges

**Merge behavior for duplicates** (same key, multiple rows):
- `source_line_spans`: union of both rows' spans (no duplicates; order is preserved from first-seen row then appended new spans)
- `metric_categories`: union of both rows' category keys (no duplicates; order is preserved from first-seen row then appended new keys)
- `confidence`: keeps the higher value between the two rows

**Output order**: first-seen order (insertion order of the first occurrence of each key).

### Indexing

Metrics indexing runs in the pipeline's **Phase C (post-process)** — after every doc
processor for the record has finished — not inside the metrics processor's Phase B
handler. This is required because metric indexing reads other processors' artifacts
(semantic projections, topics, scene blocks, provisions, entities, inventory items, and
their `kb.search_artifacts` rows), which may not exist yet while the metrics processor is
still running in Phase B. See the doc-processor capsule's "Post Process" section.

Indexing runs after the final metric rows are saved to `kb.metrics`. It is idempotent and
re-runs for pre-existing metrics (e.g. when extraction was skipped because metrics already
exist). It has five outputs:

1. the metric row in `kb.search_artifacts`
2. deterministic line-overlap links in `kb.metrics.connected_artifacts`
3. category-instance rows in `kb.category_instance`
4. `metrics.txt` entries under matching category paths in `ARTIFACT_WEB_DIR`
5. semantic similarity links in `kb.artifact_connections`

#### Search Artifact Row

Add each persisted metric to `kb.search_artifacts` using the metric's `search_document`.

Rules:

- `artifact_type` is `metric`
- `artifact_id` is `kb.metrics.metric_id`
- `input_record_id` is `kb.metrics.input_record_id`
- `source_line_spans` is copied from `kb.metrics.source_line_spans`
- search text is the same de-duplicated metric text used to populate `kb.metrics.search_document`

#### Connected Artifacts JSON

Populate `kb.metrics.connected_artifacts` as a JSON object by comparing `kb.metrics.source_line_spans` with artifacts from the same `input_record_id`.

Required JSON shape:

```json
{
  "chunks": ["chunk_id"],
  "semantic_projects": ["proj_id"],
  "topics": ["topic_id"],
  "scenes": ["scene_id"],
  "provisions": ["prov_id"],
  "entities": ["entity_id"],
  "inv_items": ["inv_item_id"]
}
```

Rules:

- An artifact is connected when it has at least one overlapping line number with the metric.
- `chunks` must include all overlapping chunk IDs and must never be empty.
- `semantic_projects` must include all overlapping semantic projection IDs and must never be empty.
- `topics`, `scenes`, `provisions`, `entities`, and `inv_items` may be empty arrays.
- These deterministic line-overlap links are stored only in `kb.metrics.connected_artifacts`; do not add them to `kb.artifact_connections`.

#### Metric and Artifact Categories

Connect each metric to its artifact categories.

Rules:

- `kb.metrics.metric_categories` must not be null or empty. If it is null or empty, report an indexing error for that metric.
- For each category key in `kb.metrics.metric_categories`, resolve the category via the **Identify Artifact Categories** procedure in [9], passing `(category_key, category_type = "metric")`. That procedure normalizes the key, matches an existing category (exact/alias, then hybrid semantic), and creates one via the LLM on a true miss — do not insert categories directly here.
- For each resolved category, upsert one row in `kb.category_instance`.
- The `kb.category_instance` row connects:
  - `category_id` from `kb.artifact_categories`
  - `artifact_id` = `kb.metrics.metric_id`
  - `input_record_id` = `kb.metrics.input_record_id`
  - `extra_info` containing at least `{"artifact_type":"metric","source":"extract_metrics"}`
- Do not use `kb.inventory_categories` for metric categories.

#### Index Metrics by Category Paths

Use `kb.metrics.source_line_spans` to find semantic projection category paths:

```text
kb.metrics.input_record_id = kb.semantic_projections.input_record_id
AND kb.metrics.source_line_spans overlaps kb.semantic_projections.line_spans
```

Return `kb.semantic_projections.category_paths_en`.

Rules:

- If no category paths are found, report an indexing error for that metric.
- For each returned category path, index the metric in the same way as semantic projection indexing.
- Save metric IDs in `metrics.txt` under the matching category path.
- Each `metrics.txt` entry uses `kb.metrics.metric_id`.

#### Connect Artifacts

Create semantic similarity links from each metric to related artifacts in `kb.search_artifacts`.

The hybrid search mechanics are defined in [7] (lexical + semantic RRF fusion); this section only specifies the metric-connection acceptance policy on top of it.

**Query and candidate retrieval:**

- Use `kb.metrics.search_document` as the query text.
- Reuse the implemented hybrid search over `kb.search_artifacts` (same CTEs as the `/api/v1/kb/metrics/search` read path):
  - lexical list: PostgreSQL `ts_rank_cd` full-text search (the always-on lexical path; an optional ParadeDB BM25 backend is selectable via `SEARCH_LEXICAL_BACKEND` but not required here)
  - semantic list: `pgvector` cosine distance (`embedding <=> query_embedding`), gated by `SEARCH_SEMANTIC_ENABLED` / `kbsearch.SemanticSearchEnabled()`
  - fuse the two lists with Reciprocal Rank Fusion (RRF), `rrf_k = 60`, candidate limit `200` per list (the same `rrfK` / `hybridCandidateLimit` constants the search handler uses)
- If `SemanticSearchEnabled()` is false or the query cannot be embedded, fall back to lexical-only ranking; the acceptance rules below then use only the lexical channel.
- Exclude the metric's own row (`artifact_type = 'metric' AND artifact_id = kb.metrics.metric_id`) from results.

**Per-candidate signals** — the connection step uses a purpose-built query that reuses the same lexical/semantic CTEs but additionally selects the component scores (the search handler's read path returns only the fused score):

- `rrf_score` — fused RRF score (used for ranking and `confidence`)
- `cosine_sim` = `1 - (embedding <=> query_embedding)`; null when either embedding is missing
- `lexical_score` — `ts_rank_cd` score; null when the candidate is not in the lexical list

**Acceptance threshold** — accept a candidate iff it clears at least one channel:

- **Semantic channel:** `cosine_sim >= METRIC_CONNECT_MIN_COSINE` (default `0.75`), OR
- **Lexical channel:** `lexical_score >= metric_search.min_rank` (the existing metric-search minimum rank)

This OR rule matches the hybrid philosophy already in the search path: a semantically similar artifact can be accepted even when it shares no query terms, and a strong lexical match can be accepted even without an embedding.

**Ranking and cap:**

- Order accepted candidates by `rrf_score DESC`, tie-break `artifact_id ASC`.
- Keep at most `METRIC_CONNECT_MAX_LINKS` (default `10`).

**Edge construction** — for each accepted candidate, upsert one row to `kb.artifact_connections`:

- `source_type = 'metric'`, `source_id = kb.metrics.metric_id`, `source_record_id = kb.metrics.input_record_id`
- `target_type` / `target_id` / `target_record_id` from the matched `kb.search_artifacts` row
- `relation_name = 'semantically_related'`
- `relation_method = 'hybrid_search'`
- `confidence = rrf_score`
- `provenance = {"rrf_score", "rrf_k": 60, "cosine_sim", "lexical_score"}`
- `extra_info = {"min_cosine", "min_rank", "max_links", "lexical_backend", "semantic_enabled"}` (the thresholds actually applied)

**Scope and idempotency:**

- Candidates span the whole `kb.search_artifacts` registry (cross-document discovery is the purpose of the global registry); they are not restricted to the metric's own `input_record_id`.
- Reprocessing must replace a document's metric semantic edges idempotently. Because these edges can target other documents, the replace scope must be keyed on the source side only: delete existing rows where `source_type = 'metric'` AND `source_record_id = <record_id>` AND `relation_method = 'hybrid_search'` AND `relation_name = 'semantically_related'`, then insert the freshly accepted edges. (The line-overlap replace path is intra-document; this source-scoped replace is the cross-document variant.)
- These thresholds and limits are configurable via env vars (`METRIC_CONNECT_MIN_COSINE`, `METRIC_CONNECT_MAX_LINKS`) and the existing `metric_search.min_rank` config; defaults are `0.75`, `10`, and the configured `min_rank` respectively.

### Thinking Behavior

Metrics extraction must force thinking off for all passes:

- primary candidate model
- fallback candidate model
- enrichment model

Implementation rule:

- set `ThinkingType = "disabled"` in metrics processor configs
- shared LLM client must omit the `thinking` request field unless `ThinkingType == "enabled"`

This avoids provider errors such as:

- `Unknown parameter: 'thinking'`

### Logging

The processor should log:

- candidate-pass start
- raw parsed LLM payload/error
- merged candidate count
- enrichment-pass start
- enrichment results
- final dedup results
- metrics indexing start/result, including connected artifact counts and category-path counts
- metrics indexing errors, including empty `metric_categories`, empty `chunks`, empty `semantic_projects`, or no matching category paths

The shared LLM client should also log the raw HTTP response body before decoding.

### Metric ID

Metrics are identified by:

```text
<record_id>_<seqno>
```

where `seqno` starts at `1`.

## Workflow

- For each chunk, run Pass 1 to extract metric candidates.
- Retry candidate extraction with `EXTRACT_METRIC_CANDIDATES_MODEL_FALLBACK` when the primary candidate model fails.
- If both primary and fallback candidate extraction return the empty/truncated JSON failure shape, treat the chunk as an empty candidate result.
- Merge and deduplicate candidates deterministically.
- Group candidates by source chunk; run Pass 2 in batches of up to `METRIC_ENRICH_GROUP_SIZE` (default 5) to enrich each batch into final metrics.
- Deduplicate final metric rows.
- Save final metrics to `kb.metrics`.
- Write `.metrics` artifact output.
- Upsert status in `kb.inputs.status`.

Indexing is **not** part of this Phase B handler. After the whole pipeline finishes
(Phase C / post-process), the controller invokes the metrics processor's post-process
indexing step, which: upserts `kb.search_artifacts`, populates
`kb.metrics.connected_artifacts`, upserts `kb.category_instance`, writes category-path
`metrics.txt` entries, and upserts semantic links to `kb.artifact_connections`. See the
[Indexing](#indexing) section.

**Progress Update (per block):**
- When beginning extraction, set `progress` to `"0%"` in `kb.inputs.status`.
- After each block completes in either pass, insert a log entry to `kb.doc_proc_logs` with `proc_progress` set to the current progress (see [doc-processor-log-spec.md Section 1.3.3](doc-processor-log-spec.md)), then update the `progress` attribute of the corresponding entry in `kb.inputs.status`.

```text
total_blocks = total_blocks_pass1 + total_blocks_pass2

percent = floor(completed_blocks * 100 / total_blocks)
progress = "<percent>% (<completed_blocks>/<total_blocks>)"
```

Notes:
- `total_blocks_pass1` = number of chunks
- `total_blocks_pass2` = number of enrichment batches (candidates grouped by source chunk, batched by `METRIC_ENRICH_GROUP_SIZE`); calculated after pass 1 completes
- Failed calls do not increment `completed_blocks`

Examples:
- Pass 1, 2 of 15 blocks done (total 30 blocks) → `6% (2/30)`
- Pass 1 complete → `50% (15/30)`
- All done → `100% (30/30)`

Failure status entry:

```json
{
  "record_id": "ddd",
  "file_type": "pdf | doc | docx | ppt | pptx | ...",
  "operation": "extract_metrics",
  "proc_status": "failed",
  "input_filename": "Artifacts/0/100/std_20039_opendata.txt",
  "error": "error-msg",
  "start_time": "yyyymmdd hh:mm:ss",
  "ms_used": ddd
}
```

Success status entry:

```json
{
  "record_id": "ddd",
  "file_type": "pdf | doc | docx | ppt | pptx | ...",
  "operation": "extract_metrics",
  "proc_status": "success",
  "input_filename": "Artifacts/0/100/std_20039_opendata.txt",
  "start_time": "yyyymmdd hh:mm:ss",
  "ms_used": ddd
}
```

## Output Storage

### Save to Table `kb.metrics`

Construct a row for each final metric and insert it.

Rules:

- save the JetStream event ID to `event_id`
- if the original language is English, do not generate/store:
  - `metric_name_en`
  - `metric_subject_en`
  - `metric_desc_en`
  - `metric_context_en`
  - `metric_keywords_en`
  - `metric_unit_en`
  - `value_class_en`
- when populating `search_document`, concatenate the searchable metric fields only once each; if normalized field text is duplicated across fields such as `metric_desc`/`metric_context` or `metric_unit`/`metric_unit_en`, keep the first occurrence and drop repeats
- save `metric_categories` to support category-instance indexing
- initialize `connected_artifacts` as an empty JSON object or the full required shape with empty arrays; the post-save indexing step must update it with deterministic line-overlap links
- save additional information to `ext_info`

### Category Table Migration

Metric categories are managed by `kb.artifact_categories`.

Rules:

- Resolve every metric category through the **Identify Artifact Categories** procedure in [9] (with `category_type = "metric"`), which creates the category via the LLM on a true miss. Do not insert into `kb.artifact_categories` directly from the metric workflow.
- Remove the retired `kb.inventory_categories` table.
- Do not create, read, or write `kb.inventory_categories` in the metric extraction or indexing workflow.

### Save to File

Write all final metrics to:

```text
ARTIFACT_DIR/<group_id>/<record_id>/<filename_root>_<parser_name>.metrics
```

where:

- `<group_id>` = `floor(record_id / 1000)`
- `<filename_root>` is derived from `kb.inputs.staging_filename`
- `<parser_name>` is `kb.inputs.parser_name`

## Index Metrics

Run the indexing workflow defined in the earlier [Indexing](#indexing) section.

### Index Metrics by Category Paths
Refer to [1] and the [Index Metrics by Category Paths](#index-metrics-by-category-paths) rules above.

### Full-Text Search Index
Refer to [2], [3], and the [Search Artifact Row](#search-artifact-row) rules above.

## Extract Metric API

The preview API is still using the older single-pass flow.

Inputs:

- `record_id`
- `lines`: `["ddd", "ddd-ddd", ...]`

### Compose Input

- treat selected lines as normal lines `n`
- treat the five lines immediately before and after as overlap lines `o`
- convert the raw lines into standard chunk format

### Handler Workflow

- read the record by `record_id`
- compose the block input
- load one prompt and one model config
- make one LLM call
- expect a top-level `metrics` array in that single response
- return all extracted final metrics
- do not save them to `kb.metrics`
- properly handle all errors

### Extract Metric API Response

```json
{
  "status": true,
  "metrics": [
    {
      "metric_name": "...",
      "metric_name_en": "...",
      "metric_desc": "...",
      "metric_desc_en": "...",
      "metric_subject": "...",
      "metric_subject_en": "...",
      "metric_context": "...",
      "metric_context_en": "...",
      "metric_keywords": ["..."],
      "metric_keywords_en": ["..."],
      "source_line_spans": ["ddd", "ddd:ddd"],
      "location_type": "...",
      "metric_unit": "...",
      "metric_unit_en": "...",
      "metric_value": "...",
      "value_data_type": "...",
      "value_range_type": "...",
      "value_class": "...",
      "value_class_en": "...",
      "formula_or_definition": "...",
      "threshold_or_target": "...",
      "measurement_frequency": "...",
      "metric_categories": ["..."],
      "confidence": 0.0,
      "is_explicit_metric": true,
      "table_name_or_section": "...",
      "reasoning_tags": ["..."]
    }
  ]
}
```

## Save Extracted Metrics API

This API persists reviewed final metric rows returned by the preview flow.

### Request

```json
{
  "record_id": 123,
  "metrics": [
    {
      "metric_name": "...",
      "metric_name_en": "...",
      "metric_desc": "...",
      "metric_desc_en": "...",
      "metric_subject": "...",
      "metric_subject_en": "...",
      "metric_context": "...",
      "metric_context_en": "...",
      "metric_keywords": ["..."],
      "metric_keywords_en": ["..."],
      "source_line_spans": ["ddd", "ddd:ddd"],
      "location_type": "...",
      "metric_unit": "...",
      "metric_unit_en": "...",
      "metric_value": "...",
      "value_data_type": "...",
      "value_range_type": "...",
      "value_class": "...",
      "value_class_en": "...",
      "formula_or_definition": "...",
      "threshold_or_target": "...",
      "measurement_frequency": "...",
      "metric_categories": ["..."],
      "confidence": 0.0,
      "is_explicit_metric": true,
      "table_name_or_section": "...",
      "reasoning_tags": ["..."]
    }
  ]
}
```

### Save Handler Workflow

- read `record_id` and `metrics`
- validate `record_id > 0`
- validate `metrics` is not empty
- validate every metric has non-empty `metric_categories`
- create `kb.metrics` table if needed
- insert rows into `kb.metrics`
- assign `metric_id = <record_id>_<seqno>` based on existing row count
- set `event_id = rest-api`
- save `ext_info = {"source":"rest-api","schema_version":"2"}`
- run the same post-save metrics indexing workflow used by the document processor
- leave `model_name`, `prompt_name`, and `metric_keywords_en` empty in the current implementation
- return the number of inserted metrics

## Implementations
Refer to [3], [4], [5] and [6].

## References
[1] KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-categories-spec.md\
[2] KnowledgeStore/Capsules/coding-capsules/full-text-search/metric-search-design.md \
[3] KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-metrics-impl.md \
[4] KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-metrics-concurrency-spec.md \
[5] KnowledgeStore/Capsules/coding-capsules/full-text-search/metric-search-design.md \
[6] KnowledgeStore/Capsules/coding-capsules/full-text-search/metric-search-impl.md \
[7] KnowledgeStore/Capsules/coding-capsules/llm-wiki/hybrid-search.md \
[8] KnowledgeStore/Capsules/coding-capsules/llm-wiki/artifact-connections.md \
[9] KnowledgeStore/Capsules/coding-capsules/categories/category-mgmt-spec.md
