A metric is a quantitative, measurable item used to evaluate, compare, monitor, verify, or assess something. Metrics are often defined in standards, specifications, requirements, policies, test plans, scorecards, or compliance documents.

This processor uses a multi-pass extraction strategy.

## 1. Input

- `record_id`: the value of `kb.inputs.id`
- `chunks`: see the chunking spec
- file name

## 2. Implementation

- The code is in `ChenWeb/`
- It may use functions/modules in `shared/`

## 3. Multi-Pass

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

### 3.1 Multi-Pass Pipeline

To solve the single-pass problem, we will use multi-pass pipeline, which
breaks the processing into multiple passes:

1. Pass 1: extract metric candidates from each chunk
2. Deterministic Step A: merge and deduplicate candidates across overlapping chunks
3. Pass 2: enrich candidates into final metric rows, batched by chunk (see `METRIC_ENRICH_GROUP_SIZE`)
4. Deterministic Step B: final metric dedup before persistence

### 3.2 Incremental Processing
Incremental processing is documented in [10].

### 3.3 Pass 1: Metric Candidates

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
      "candidate_id": "48_1",
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

`candidate_id` rules:

- format: `<chunk_id>_<seqno>`
- `chunk_id` is the source chunk sequence number used by the metrics processor
- `seqno` starts at `1` within that chunk's Pass 1 candidate list
- this ID is human-readable and is used as the lineage key between Pass 1 candidates and later final metrics/logs

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
- semantic search env:
  - `SEARCH_SEMANTIC_ENABLED`
  - `METRIC_CONNECT_MAX_LINKS` (default: 10)
- index env:
  - `ARTIFACT_WEB_DIR`

Pass 2 output:

```json
{
  "language": "string",
  "metrics": [
    {
      "candidate_id": "48_1",
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
- each final metric row should carry the originating `candidate_id` when the processor can determine a unique source candidate
- `uncertain_metrics` may be returned by the LLM but are not persisted to `kb.metrics`
- `metric_categories` must contain one or more category keys suitable for lookup in `kb.artifact_categories`
- category paths are not generated or stored by the enrichment pass

### 3.4 Deterministic Step B: Final Metric Dedup

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

#### 3.4.1 Metric IDs
Metric IDs are defined as `<record_id>` + '_mtc_' + `<seqno>`, where `<seqno>` is a sequence number, starting from 1.

`metric_id` and `candidate_id` are different:

- `candidate_id` identifies the Pass 1 candidate within a chunk
- `metric_id` identifies the persisted row in `kb.metrics`
- `candidate_id` links the pre-persistence candidate logs to the persisted/final metric logs

### 3.5 Indexing

Metrics indexing runs in the pipeline's **Phase C (post-process)** — after every doc
processor for the record has finished — not inside the metrics processor's Phase B
handler. This is required because metric indexing reads other processors' artifacts
(semantic projections, topics, scene blocks, provisions, entities, inventory items, and
their `kb.search_artifacts` rows), which may not exist yet while the metrics processor is
still running in Phase B. See the doc-processor capsule's "Post Process" section.

Indexing runs after the final metric rows are saved to `kb.metrics`. It is idempotent and
re-runs for pre-existing metrics (e.g. when extraction was skipped because metrics already
exist). It has five outputs:

| Relation | Storage |
|----------|---------|
| None | the metric row in `kb.search_artifacts` |
| deterministic line-overlap relation | stored in `kb.metrics.connected_artifacts` |
| relate artifact category to metric | stored in `kb.artifact_connections` |
| relate category path to metric | stored in `metrics.txt` under the matching category paths in `ARTIFACT_WEB_DIR` |
| relate metric to line-overlapping artifacts (entities, inventory_items, provisions, topics, semantic_projections) | stored in `kb.artifact_connections` |
| relate artifact objects to object nodes | stored in `kb.artifact_connections` |

Note: semantic metric↔metric similarity is **not** an indexing output — it is computed live
at read time (see [Semantic Similarity (Computed On-The-Fly)](#semantic-similarity-computed-on-the-fly)),
not materialized as `kb.artifact_connections` edges.

#### 3.5.1 Line-Overlap Artifact Edges

These edges make intra-document, line-overlapping artifacts explicitly traversable in
`kb.artifact_connections`. They are built deterministically at index time — no LLM or hybrid
search is involved here. (`connected_artifacts` itself is computed on demand by
`kb.connected_artifacts(record_id, 'metric', source_row_id)`, not materialized.) Cross-document
neighbor discovery happens later, at read time, in
[Metric Discovery for Document Review](#metric-discovery-for-document-review).

For each metric `M` in the record being indexed:

1. Find every artifact in the **same document** whose line spans overlap `M`'s, grouped by
   type `T ∈ {inventory_item, entity, provision, topic, semantic_projection}` → the anchors.
   Overlap is computed by self-joining `kb.search_artifacts` on the GiST-indexed
   `line_range && line_range` operator, so both endpoints use their canonical `artifact_id`s.
2. For each overlapping artifact (anchor) `X` of type `T`, upsert one edge to
   `kb.artifact_connections`:
   - `source_type = T`, `source_id = X.artifact_id`, `source_record_id = record_id`
   - `target_type = 'metric'`, `target_id = M.metric_id`, `target_record_id = record_id`
   - `relation_name = '#shared_artifact'`
   - `relation_method = 'line-overlapped-artifact'`
   - `confidence = 1.0` (deterministic overlap)
   - `extra_info` containing at least `{"source":"extract_metrics","anchor_type":T}`

Because both endpoints share lines, these edges are always intra-document
(`source_record_id = target_record_id = record_id`).

**Edge direction and bidirectional reads.** `kb.artifact_connections` is one graph in which
different edge families store the metric on different sides: line-overlap edges put the
artifact on the source side and the metric on the target side, while `belong_to` category
edges put the metric on the source side. Every read that looks up an
artifact's connections must therefore match it on **either** side
(`source_id = A OR target_id = A`); do not assume the metric is always source or always
target. Each symmetric edge (`#shared_artifact`) is stored exactly **once** in its canonical
direction (artifact → metric) — never insert the mirror row. Asymmetric relations
(`belong_to`) keep their natural direction; bidirectional matching is only a lookup
convenience and does not change a relation's meaning.

**Idempotency.** Rebuilt each run by `ReplaceSharedArtifactEdges`, which deletes the record's
existing edges scoped to `target_type = 'metric'` (plus
`relation_method = 'line-overlapped-artifact'`, `relation_name = '#shared_artifact'`), then
inserts the fresh set. The delete is scoped by target family so parallel Phase-C family runs
never clobber each other's edges.

#### 3.5.2 Search Artifact Row

Add each persisted metric to `kb.search_artifacts` using the metric's `search_document`.

Rules:

- `artifact_type` is `metric`
- `artifact_id` is `kb.metrics.metric_id`
- `input_record_id` is `kb.metrics.input_record_id`
- `source_line_spans` is copied from `kb.metrics.source_line_spans`
- search text is the same de-duplicated metric text used to populate `kb.metrics.search_document`

#### 3.5.3 Connected Artifacts JSON

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
- The `connected_artifacts` JSON is the per-metric overlap set for quick lookup; the same line-overlap facts are also written as traversable edges in `kb.artifact_connections` (see [Line-Overlap Artifact Edges](#line-overlap-artifact-edges)).

#### 3.5.4 Metric and Artifact Categories

Connect each metric to its artifact categories.

Rules:

- `kb.metrics.metric_categories` must not be null or empty. If it is null or empty, report an indexing error for that metric.
- For each category key in `kb.metrics.metric_categories`, resolve the category via the **Identify Artifact Categories** procedure in [9], passing `(category_key, category_type = "metric")`. That procedure normalizes the key, matches an existing category (exact/alias, then hybrid semantic), and creates one via the LLM on a true miss — do not insert categories directly here.
- Do not write metric-category membership to `kb.category_instance`.
- For each resolved category, upsert one row in `kb.artifact_connections`.
- The category membership edge connects:
  - `source_type = 'metric'`
  - `source_id = kb.metrics.metric_id`
  - `target_type = kb.artifact_categories.category_type`
  - `target_id = kb.artifact_categories.category_key`
  - `relation_name = 'belong_to'`
  - `relation_method = 'category_name'`
  - `source_record_id = kb.metrics.input_record_id`
  - `target_record_id = kb.metrics.input_record_id`
  - `extra_info` containing at least `{"source":"extract_metrics","category_key":<category_key>,"category_id":<category_id>}`
- Do not use `kb.inventory_categories` for metric categories.

#### 3.5.5 Index Metrics by Category Paths

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

#### 3.5.6 Semantic Similarity (Computed On-The-Fly)

Semantic metric↔artifact similarity is **not materialized** as `kb.artifact_connections`
edges. Every artifact already lives in `kb.search_artifacts` and is discoverable by hybrid
search; a stored `semantically_related` snapshot would only duplicate that computation and go
stale as the corpus grows (and would need directional inbound/outbound bookkeeping to stay
complete). Instead, any consumer that needs "similar artifacts" runs the hybrid search
**live** at read time.

Consequences for indexing:

- The metric indexing step writes **no** `hybrid_search` / `semantically_related` edges.
- It still hydrates each metric's `search_document` and embedding into `kb.search_artifacts`
  so the read-time hybrid search (and the `/api/v1/kb/metrics/search` path) have the data
  they need.

**Hybrid acceptance model** — shared by every on-the-fly caller (the metrics document
reviewer's direct metric↔metric branch, and `neighbors(X)` in
[Metric Discovery for Document Review](#metric-discovery-for-document-review)). Mechanics are
defined in [7]; the implementation is `docprocessing.FindSimilarArtifactsOnTheFly`.

- **Query:** the source artifact's `kb.search_artifacts.search_document`, embedded live when
  semantic search is enabled.
- **Candidate set:** `kb.search_artifacts`, excluding the query artifact's own row;
  optionally restricted to a single `artifact_type` (the reviewer's direct branch and
  `neighbors(X)` both pass their own type).
- **Fusion:** lexical `ts_rank_cd` + `pgvector` cosine, fused with RRF (`rrf_k = 60`,
  200 candidates/list). Falls back to lexical-only when semantic search is disabled or the
  query cannot be embedded.
- **Per-candidate signals:** `rrf_score`, `cosine_sim = 1 - (embedding <=> query_embedding)`
  (null when either embedding is missing), `lexical_score` (null when not in the lexical list).
- **Acceptance (OR across channels):** `cosine_sim >= min_cosine` OR
  `lexical_score >= artifact_search.min_rank`.
- **Rank and cap:** order by `rrf_score DESC`, tie-break `artifact_id ASC`; keep at most
  `max_links`.
- **Scope:** the whole `kb.search_artifacts` registry (cross-document discovery is the point);
  not restricted to the query artifact's own `input_record_id`.
- **Thresholds:** the metrics reviewer's direct branch reuses `METRIC_CONNECT_MIN_COSINE`
  (default `0.75`) and `METRIC_CONNECT_MAX_LINKS` (default `10`); `neighbors(X)` uses
  `METRIC_NEIGHBOR_MIN_COSINE` / `METRIC_NEIGHBOR_MAX_LINKS` (same defaults). Both share
  `artifact_search.min_rank`.

Because nothing is persisted, there is no edge idempotency to manage for semantic similarity.

#### 3.5.7 Indexing Metrics to Objects
Metrics mention artifact objects through `kb.metrics.metric_id` = `kb.artifact_objects.artifact_id`.
Artifact objects connect to object nodes through `kb.artifact_objects.object_id` = 
`kb.object_nodes.object_id`. 

For each metric, add a record to `kb.artifact_connections`:
  - `source_type = 'metric'`
  - `source_id = kb.artifact_object.object_id`
  - `target_type = 'object_node'`
  - `target_id = kb.object_nodes.object_id`
  - `relation_name = 'belong_to'`
  - `relation_method = 'object_id'`
  - `source_record_id = kb.artifact_objects.source_record_id`

### 3.5.2 Ontology Candidate Harvest

After the final metric rows are saved to `kb.metrics`, every metric that carries a
`formula_or_definition` value is converted into a governed ontology candidate
(`kb.ontology_candidates`, `candidate_kind = 'term'`, `term_kind = 'metric_definition'`,
module `measurement`) via `harvestMetricDefinitions`. The `formula_or_definition` field
holds the metric's *definition*: the statement that says what the metric means, including a
formula that defines it (a formula that defines a metric is a definition). A bare value or
threshold is an assertion, not a definition, and is not harvested.

The harvest is **mode-independent**: it runs in both the chunk-batch (concurrent) path
(`FinalizeChunkBatch`) and the sequential fallback path (`HandleEvent`), so converting
extracted metrics to ontology candidates does not depend on `RUN_DOC_PROCESSOR_CONCURRENT`.
Candidate creation is idempotent by fingerprint, so re-running a record never duplicates
review work.

### 3.6 Thinking Behavior

Metrics extraction must force thinking off for all passes:

- primary candidate model
- fallback candidate model
- enrichment model

Implementation rule:

- set `ThinkingType = "disabled"` in metrics processor configs
- shared LLM client must omit the `thinking` request field unless `ThinkingType == "enabled"`

This avoids provider errors such as:

- `Unknown parameter: 'thinking'`

### 3.7 Logging

The processor should log:

- candidate-pass start
- raw parsed LLM payload/error
- merged candidate count
- enrichment-pass start
- enrichment results
- final dedup results
- metrics indexing start/result, including connected artifact counts and category-path counts
- metrics indexing errors, including empty `metric_categories`, empty `chunks`, empty `semantic_projects`, or no matching category paths
- when `force_clear=false` (merge mode, see [10] DR2/DR4): for each pending Metric Group sent to the Merge Resolution LLM call, one `kb.doc_proc_logs` row (`activity = 'merge_resolve_metrics'`) containing the exact candidates payload sent to the LLM and the `winning_metrics` (or error) it returned — fires whether the call succeeds or fails, so a merge run always has a traceable record of what was sent and decided

The shared LLM client should also log the raw HTTP response body before decoding.

### 3.8 Metric ID

Metrics are identified by:

```text
<record_id>_mtc_<seqno>
```

where `seqno` starts at `1`.

## 4. Workflow

- For each chunk, run Pass 1 to extract metric candidates.
- Retry candidate extraction with `EXTRACT_METRIC_CANDIDATES_MODEL_FALLBACK` when the primary candidate model fails.
- If both primary and fallback candidate extraction return the empty/truncated JSON failure shape, treat the chunk as an empty candidate result.
- Merge and deduplicate candidates deterministically.
- Group candidates by source chunk; run Pass 2 in batches of up to `METRIC_ENRICH_GROUP_SIZE` (default 5) to enrich each batch into final metrics.
- Deduplicate final metric rows.
- Save final metrics to `kb.metrics`.
- After each successful save/upsert step, write one `kb.doc_proc_logs` row with `activity = 'extract_metrics_final'`.
- The `extract_metrics_final` artifact must contain the exact metric rows being saved in that write operation, and every row in that artifact must include `candidate_id`.
- Write `.metrics` artifact output.
- Upsert status in `kb.inputs.status`.

Indexing is **not** part of this Phase B handler. After the whole pipeline finishes
(Phase C / post-process), the controller invokes the metrics processor's post-process
indexing step, which: upserts `kb.search_artifacts`, populates
`kb.metrics.connected_artifacts`, upserts `category_name` membership edges to
`kb.artifact_connections`, writes category-path `metrics.txt` entries, and upserts
line-overlap artifact edges to `kb.artifact_connections`. Semantic metric↔metric similarity
is no longer materialized here — it is computed live at review time. See the
[Indexing](#indexing) section.

**Progress Update (per block):**
- When beginning extraction, set `progress` to `"0%"` in `kb.inputs.status`.
- After each block completes in either pass, insert a log entry to `kb.doc_proc_logs` with `proc_progress` set to the current progress (see [doc-processor-log-spec.md Section 1.3.3](doc-processor-log-spec.md)), then update the `progress` attribute of the corresponding entry in `kb.inputs.status`.
- Pass 1 candidate logs use `activity = 'extract_metric_candidates'` and must include candidate rows with `candidate_id`.
- Final-save logs use `activity = 'extract_metrics_final'` and must include the final metric rows that were written, each with its `candidate_id`.

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

## 5. Output Storage

### 5.1 Save to Table `kb.metrics`

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
- save `metric_categories` to support category membership indexing
- initialize `connected_artifacts` as an empty JSON object or the full required shape with empty arrays; the post-save indexing step must update it with deterministic line-overlap links
- save additional information to `ext_info`

`ext_info` requirements:

- always include `language`
- always include `schema_version = "2"`
- seed `title` from `kb.inputs.doc_metadata.title` when present; otherwise fall back to `kb.inputs.title`
- seed `doc_no` from `kb.inputs.doc_metadata.doc_no` when present; otherwise fall back to `kb.inputs.doc_no`
- for metric rows whose artifact objects are later written to `kb.artifact_objects`, merge in `object_name` from the preferred linked object row where:
  - `kb.artifact_objects.artifact_type = 'metric'`
  - `kb.artifact_objects.artifact_id = kb.metrics.metric_id`
  - the preferred row should favor `object_role IN ('measured_object', 'self')`, then first row order
- this is forward-only behavior; no backfill is required for existing metric rows

### 5.1.1 Read Payload and Metric Detail UI

When returning metric records for the metrics detail view, the read path should expose:

- `document_title`
- `document_doc_no`
- `object_name`

These values come from the same document/object sources described above and are used by the
metrics detail panel with this display order:

- under `Context`, show `Document Title` and `Doc No` above `Section`
- under `Metric`, show `Object` directly under `Subject`

### 5.2 Category Table Migration

Metric categories are managed by `kb.artifact_categories`.

Rules:

- Resolve every metric category through the **Identify Artifact Categories** procedure in [9] (with `category_type = "metric"`), which creates the category via the LLM on a true miss. Do not insert into `kb.artifact_categories` directly from the metric workflow.
- Remove the retired `kb.inventory_categories` table.
- Do not create, read, or write `kb.inventory_categories` in the metric extraction or indexing workflow.

### 5.3 Save to File

Write all final metrics to:

```text
ARTIFACT_DIR/<group_id>/<record_id>/<filename_root>_<parser_name>.metrics
```

where:

- `<group_id>` = `floor(record_id / 1000)`
- `<filename_root>` is derived from `kb.inputs.staging_filename`
- `<parser_name>` is `kb.inputs.parser_name`

## 6. Extract Metric API

The preview API is still using the older single-pass flow.

Inputs:

- `record_id`
- `lines`: `["ddd", "ddd-ddd", ...]`

### 6.1 Compose Input

- treat selected lines as normal lines `n`
- treat the five lines immediately before and after as overlap lines `o`
- convert the raw lines into standard chunk format

### 6.2 Handler Workflow

- read the record by `record_id`
- compose the block input
- load one prompt and one model config
- make one LLM call
- expect a top-level `metrics` array in that single response
- return all extracted final metrics
- do not save them to `kb.metrics`
- properly handle all errors

### 6.3 Extract Metric API Response

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

## 7. Save Extracted Metrics API

This API persists reviewed final metric rows returned by the preview flow.

### 7.1 Request

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

### 7.2 Save Handler Workflow

- read `record_id` and `metrics`
- validate `record_id > 0`
- validate `metrics` is not empty
- validate every metric has non-empty `metric_categories`
- create `kb.metrics` table if needed
- insert rows into `kb.metrics`
- assign `metric_id = <record_id>_mtc_<seqno>` based on existing row count
- set `event_id = rest-api`
- save `ext_info` with at least:
  - `source = "rest-api"`
  - `schema_version = "2"`
  - `title` and `doc_no` seeded from `kb.inputs.doc_metadata` with fallback to top-level input fields, the same way as the document-processor save path
- run the same post-save metrics indexing workflow used by the document processor
- when metric artifact objects are written for these saved metrics, merge `object_name` into `kb.metrics.ext_info` using the same artifact-object linkage rule as the document-processor save path
- leave `model_name`, `prompt_name`, and `metric_keywords_en` empty in the current implementation
- return the number of inserted metrics

## 8. Metric Discovery for Document Review

This is a **read-time** procedure: it is not part of indexing and persists nothing. Its
purpose is to surface metrics from the corpus that a document under review should plausibly
cover — both the ones it explicitly mentions and the ones it may have missed — by walking
from the document's metrics out to same-type "close" artifacts elsewhere in the corpus and
back to the metrics attached to them.

Neighbor closeness is always computed **on the fly** so a freshly added document is picked up
immediately; neighbor sets are never cached across runs.

**Implementation status.** The P5 metrics reviewer currently implements cross-document
discovery as three branches: (A) direct metric↔metric similarity computed live via
`docprocessing.FindSimilarArtifactsOnTheFly`, (B) metrics sharing a category key, and
(C) entity→metric edges. The full anchor → `neighbors(X)` → metrics expansion below and the
mentioned/missed **metric matrix** are the planned extension (matrix deferred to a separate
session); they build on the same on-the-fly hybrid search that Branch A already uses.

For each metric `M` extracted from the document under review:

1. Find every artifact in the same document whose line spans overlap `M.source_line_spans`,
   grouped by type `T ∈ {inventory_item, entity, provision, topic, semantic_projection}` →
   the anchors.
2. For each anchor `X` of type `T`:
   - Compute `neighbors(X)` (see below), excluding `X` itself.
   - For each neighbor `N` (also of type `T`):
     - Find every metric `Y` connected to `N` in `kb.artifact_connections`, matching `N` on
       **either** side (connections are bidirectional):
       ```text
       (source_type = T AND source_id = N.artifact_id AND target_type = 'metric')
       OR
       (target_type = T AND target_id = N.artifact_id AND source_type = 'metric')
       ```
       `Y` is the metric-side endpoint of each matched row. (Restrict to
       `relation_name = '#shared_artifact'` if only metrics that directly line-overlap `N`
       are wanted; leave it open to also include semantically-related metrics.)
     - Add each `Y` to the metric matrix (see the Metric Matrix note).
3. Return the matrix.

### 8.1 neighbors(X)

`neighbors(X)` returns same-type artifacts across the whole corpus that are "close" to the
anchor `X`. It reuses the shared hybrid acceptance model in
[Semantic Similarity (Computed On-The-Fly)](#semantic-similarity-computed-on-the-fly)
(`docprocessing.FindSimilarArtifactsOnTheFly`), re-parameterized for artifact-to-artifact
search:

- **Query:** `X.search_document` and its embedding (from `kb.search_artifacts`).
- **Candidate set:** `kb.search_artifacts` filtered to `artifact_type = T` (same type as the
  anchor), **global** scope (all `input_record_id`), excluding `X` itself.
- **Hybrid search:** reuse the [7] CTEs — `ts_rank_cd` lexical + `pgvector` cosine, fused with
  RRF (`rrf_k = 60`, 200 candidates per list). If semantic search is disabled or `X` has no
  embedding, fall back to lexical-only.
- **Per-candidate signals:** `rrf_score`, `cosine_sim = 1 - (embedding <=> query_embedding)`,
  `lexical_score`.
- **Acceptance (OR across channels):**
  - semantic: `cosine_sim >= METRIC_NEIGHBOR_MIN_COSINE` (default `0.75`), OR
  - lexical: `lexical_score >= artifact_search.min_rank`.
- **Rank and cap:** order by `rrf_score DESC`, tie-break `artifact_id ASC`; keep at most
  `METRIC_NEIGHBOR_MAX_LINKS` (default `10`).

Precondition: every artifact type must have a populated `search_document` (and, for the
semantic channel, an embedding) in `kb.search_artifacts`; a type with a null embedding
degrades to lexical-only rather than returning nothing.

Within a single review invocation, `neighbors(X)` may be memoized by `X.artifact_id` so an
anchor shared by multiple metrics is searched once; this cache must never persist across
invocations (the corpus moves between runs).

### 8.2 Metric Matrix

The metric matrix distinguishes metrics the document **mentions** from metrics it may have
**missed**, keyed so that "close enough" metrics collapse into one entry whose value is the
deduplicated list of contributing metrics. The matrix structure and its metric↔metric
closeness key are specified separately (deferred to the matrix session); this procedure only
supplies candidate metrics `Y` tagged with their `input_record_id` so the matrix step can
classify mentioned vs. missed and dedup within each entry.

## 9. Implementations
Refer to [3], [4], [5] and [6].

## 10. References
[1] KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-categories-spec.md\
[2] KnowledgeStore/Capsules/coding-capsules/full-text-search/metric-search-design.md \
[3] KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-metrics-impl.md \
[4] KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-metrics-concurrency-spec.md \
[5] KnowledgeStore/Capsules/coding-capsules/full-text-search/metric-search-design.md \
[6] KnowledgeStore/Capsules/coding-capsules/full-text-search/metric-search-impl.md \
[7] KnowledgeStore/Capsules/coding-capsules/llm-wiki/hybrid-search.md \
[8] KnowledgeStore/Capsules/coding-capsules/llm-wiki/artifact-connections.md \
[9] KnowledgeStore/Capsules/coding-capsules/categories/category-mgmt-spec.md \
[10] KnowledgeStore/doc-repo/adrs/202607/2026071002-adr-doc-processor-incremental.md
