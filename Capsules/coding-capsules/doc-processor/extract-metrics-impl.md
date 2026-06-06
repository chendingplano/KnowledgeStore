# Extract Metrics Implementation

Date: 2026-05-21 (updated 2026-06-05: Phase C indexing — connected_artifacts,
category_instance, category-path metrics.txt, hybrid_search links)

## Scope

Implemented against:

- `KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-metrics-spec.md`

Primary implementation files:

- `ChenWeb/server/api/doc-processing/extract-metrics.go`
- `ChenWeb/server/api/doc-processing/extract-metrics_test.go`
- `ChenWeb/server/api/doc-processing/metric_indexing.go` (Phase C indexing: connected_artifacts, category_instance, metrics.txt, hybrid links)
- `ChenWeb/server/api/doc-processing/metric_indexing_test.go`
- `ChenWeb/server/api/doc-processing/connections_store.go` (`ReplaceConnectionsBySource` for cross-document semantic edges)
- `ChenWeb/server/api/doc-processing/control.go` (Phase C `PostProcessIndexer` dispatch)
- `ChenWeb/server/api/kbhandler/extract-metric-handler.go`
- `shared/go/api/llm/openai_client.go`
- `ChenWeb/project_migrations/20260605000001_add_connected_artifacts_to_kb_metrics.sql`

## Summary

`extract_metrics` now uses a multi-pass pipeline instead of a single overloaded LLM call.

The processor:

1. builds or reuses `BlockBuffer` blocks
2. runs a metric-candidate extraction pass for each block
3. deterministically merges and deduplicates candidates across overlapping blocks
4. enriches each merged candidate into final metric rows
5. deduplicates final metric rows
6. persists rows to `kb.metrics`
7. writes `.metrics` artifact output
8. updates `kb.inputs.status`

## Processor

The processor is implemented as `MetricsProcessor`.

Key public construction and interfaces:

- `NewMetricsProcessor(inputStore, store, extractor, logger)`
- `MetricsProcessor.Name()` returns `"extract_metrics"`
- `MetricsProcessor.HandleEvent(ctx, payload)`
- `MetricsStore`
- `MetricsSQLStore`

## Event Workflow

`HandleEvent` performs the following steps:

1. Parse the event payload with `ParseLineFileGeneratedEvent`.
2. Skip non-target events with `ShouldSkipLineFileGeneratedEvent`.
3. Load metric candidate and metric enrichment prompts.
4. Load `kb.inputs` by `record_id`.
5. Load model configs for:
   - candidate extraction
   - candidate fallback
   - metric enrichment
6. Force thinking off for all metrics passes.
7. Resolve the canonical line file path.
8. If `force=true`, delete existing metrics for the record.
9. If `force=false`, skip when metrics already exist.
10. Reuse `BlockBuffer` from context when available; otherwise read the line file and call `buildBlocks(...)`.
11. Run `extractMetricsFromBlocksWithLLM(...)`.
12. Assign `metric_id = <record_id>_<seqno>`.
13. Save rows with `SaveMetrics(...)`.
14. Write `.metrics` artifact output.
15. Persist success or failure status into `kb.inputs.status`.

`HandleEvent` no longer performs any indexing. All artifact indexing is deferred to
Phase C (post-process); see [Indexing (Phase C)](#indexing-phase-c).

## Multi-Pass Extraction

### Pass 1: Candidate Extraction

Per block, the processor:

- serializes block lines in canonical block format
- builds a compact candidate prompt
- calls the mention model
- normalizes `candidates`

Prompt/model:

- prompt: `prompt-extract-metric-candidates-v1.md`
- env: `EXTRACT_METRIC_CANDIDATES_PROMPT`
- model env: `EXTRACT_METRIC_CANDIDATES_MODEL_NAME`

Fallback:

- env: `EXTRACT_METRIC_CANDIDATES_MODEL_FALLBACK`
- if primary returns truncated or empty JSON, candidate extraction retries with fallback
- if fallback also returns the empty-JSON failure shape, the processor treats that block as empty candidates

### Deterministic Merge

After pass 1:

- `mergeMetricMentionCandidates(...)` groups candidates by normalized metric identity
- overlap-only candidates are dropped unless normal-line evidence also exists
- supporting lines and evidence spans are merged
- normal lines win over overlap lines when provenance overlaps

Logging:

- `Merged metric candidates`

### Pass 2: Enrichment

For each merged candidate, the processor:

- builds a candidate-specific enrichment prompt
- sends the supporting lines and mentions
- normalizes returned `metrics` and `uncertain_metrics`

Prompt/model:

- prompt: `prompt-enrich-metrics-v1.md`
- env: `ENRICH_METRICS_PROMPT`
- fallback compatibility env: `EXTRACT_METRICS_PROMPT`
- model env: `ENRICH_METRICS_MODEL_NAME`
- fallback compatibility model env: `EXTRACT_METRICS_MODEL_NAME`

Logging:

- `Start enriching metric candidate`
- `LLM responded with enriched metrics`

### Final Dedup

After enrichment:

- `dedupeFinalMetricRows(...)` merges accidental duplicates
- dedup key uses metric name, subject, unit, value, and normalized source spans

Logging:

- `Deduped final metric rows`

## Indexing (Phase C)

Metric indexing reads other processors' artifacts, so it must run only after the whole
pipeline finishes. It is therefore implemented as a **Phase C (post-process)** step, not
inside `HandleEvent`.

### Controller dispatch

- `control.go` defines `PostProcessIndexer { PostProcessIndex(ctx, recordID) error }`.
- After Phase A + Phase B complete (and the pipeline was not stopped), the controller
  calls `runPostProcessIndexing`, which invokes `PostProcessIndex` on every invoked
  processor that implements the interface. Errors are logged, not fatal, and do not abort
  other processors' indexing.
- `MetricsProcessor` implements `PostProcessIndex`. It loads the record and chunks
  (`loadRecordChunks`), confirms metrics exist, then runs:
  1. `ReindexMetricSearchForRecord` — the metric's `kb.search_artifacts` row.
  2. `WriteLineOverlapConnectionsFromRegistry` — chunk→metric `has-metrics` line-overlap
     edges.
  3. `IndexMetricsForRecord` — the four outputs below.
- The step is idempotent and also re-indexes pre-existing metrics (the force=false skip
  path no longer indexes inline).

### `IndexMetricsForRecord` outputs (`metric_indexing.go`)

1. **connected_artifacts** (`buildConnectedArtifacts`): for each metric, deterministic
   line-overlap of `source_line_spans` against chunks and the registry rows of
   semantic_projections / topics / scene_blocks / provisions / entities / inventory_items;
   writes the JSON object to `kb.metrics.connected_artifacts`. `chunks` and
   `semantic_projects` empty are logged as indexing errors.
2. **category_instance** (`upsertMetricCategoryInstances`): parses the `metric_categories`
   key list, resolves each to `kb.artifact_categories.category_id`, and upserts
   `kb.category_instance (category_id, artifact_id=metric_id, input_record_id, extra_info)`.
3. **metrics.txt** (`indexMetricsByCategoryPaths`): derives category paths from the
   `kb.semantic_projections` rows whose `line_spans` overlap the metric, then writes
   `metric_id` into `metrics.txt` under each path in `ARTIFACT_WEB_DIR` (mirrors the
   products/summaries tree writer). Requires `ARTIFACT_WEB_DIR`.
4. **hybrid semantic links** (`connectMetricArtifacts`): runs the lexical + pgvector RRF
   hybrid search (`queryMetricHybridCandidates`) over `kb.search_artifacts` using the
   metric's `search_document`; accepts a candidate when
   `cosine_sim >= METRIC_CONNECT_MIN_COSINE` (default 0.75) **or**
   `lexical_score >= metric_search.min_rank`; ranks by RRF, caps at
   `METRIC_CONNECT_MAX_LINKS` (default 10), excludes self; upserts edges with
   `relation_method='hybrid_search'`, `relation_name='semantically_related'` via
   `ReplaceConnectionsBySource` (source-scoped, cross-document idempotent replace).

### Config / env

- `METRIC_CONNECT_MIN_COSINE` (default `0.75`)
- `METRIC_CONNECT_MAX_LINKS` (default `10`)
- `metric_search.min_rank`, `metric_search.dictionary` (reused from the metric search config)
- semantic half gated by `SEARCH_SEMANTIC_ENABLED` / `kbsearch.SemanticSearchEnabled()`;
  lexical-only fallback when semantic search is off or the query cannot be embedded.

## Thinking Behavior

Metrics extraction forcibly disables thinking for all passes:

- primary candidate model
- fallback candidate model
- enrichment model

Implementation detail:

- `MetricsProcessor.forceDisableThinking()` rewrites all three `structureModelConfig` values to `ThinkingType = "disabled"`
- the shared LLM client now only sends the `thinking` request field when `ThinkingType == "enabled"`
- this prevents models such as `gpt-5.4-mini` from receiving unsupported `thinking` parameters

## Raw LLM Response Logging

Two levels of response logging exist:

1. In `MetricsProcessor.extractMetricPayload(...)`
   - logs parsed payload plus any extractor error
2. In `shared/go/api/llm/openai_client.go`
   - logs raw HTTP response body before `parseOpenAIContent(...)` attempts to decode it

This is important for debugging providers that return:

- empty string
- malformed OpenAI-compatible envelopes
- reasoning-only outputs
- provider-specific error bodies

## Prompt Loading

Candidate prompt loading:

- env: `EXTRACT_METRIC_CANDIDATES_PROMPT`
- default: `prompt-extract-metric-candidates-v1.md`

Enrichment prompt loading:

- env priority:
  - `ENRICH_METRICS_PROMPT`
  - `EXTRACT_METRICS_PROMPT`
  - `PROMPT_FILE_NAME`
- default: `prompt-enrich-metrics-v1.md`

Prompt search is delegated to the shared `loadProductPromptFromEnvKeys(...)` helper.

## Model Loading

Candidate model loading:

- env priority:
  - `EXTRACT_METRIC_CANDIDATES_MODEL_NAME`
  - `EXTRACT_METRICS_MODEL_NAME`

Candidate fallback model:

- env: `EXTRACT_METRIC_CANDIDATES_MODEL_FALLBACK`

Enrichment model loading:

- env priority:
  - `ENRICH_METRICS_MODEL_NAME`
  - `EXTRACT_METRICS_MODEL_NAME`

All metrics model configs are loaded from:

- `MODEL_DEF_FILE`

## Input Handling

The processor does not read `.chunks` or `.topics` artifacts anymore.

Instead:

1. reuse `BlockBuffer` from context when available
2. otherwise read the canonical line file
3. rebuild blocks with `buildBlocks(...)`

This keeps metrics aligned with the same blocking logic used elsewhere in doc processing.

## Normalized Internal Shapes

### Candidate mention

`metricCandidateMention` stores:

- metric name hint
- subject hint
- evidence quote
- source spans
- unit hint
- value hint
- confidence
- supporting block lines
- `HasNormalEvidence`

### Final metric row

`normalizeMetricList(...)` produces rows using these internal keys:

- `metric_name`
- `metric_name_en`
- `subject`
- `subject_en`
- `desc`
- `desc_en`
- `context`
- `context_en`
- `keywords`
- `keywords_en`
- `location_type`
- `unit`
- `unit_en`
- `metric_value`
- `value_data_type`
- `value_range_type`
- `value_class`
- `value_class_en`
- `formula_or_definition`
- `threshold_or_target`
- `measurement_frequency`
- `confidence`
- `is_explicit_metric`
- `table_name_or_section`
- `reasoning_tags`
- `source_line_spans`
- `category_paths`
- `category_paths_en`

Notes:

- `source_line_spans` is normalized into `"N"` or `"N:M"` strings
- the legacy spec typo `caetgory_paths_en` is still tolerated on input and normalized to `category_paths_en`

## Persistence

`SaveMetrics(...)` writes:

- `event_id`
- `input_record_id`
- `metric_id`
- normalized metric fields
- `metric_categories` — the category-key list, stored as a JSON array string in the
  `metric_categories` TEXT column (parsed back by Phase C category-instance indexing)
- `connected_artifacts` — initialized to `'{}'` (Phase C overwrites it with the
  line-overlap links)
- `model_name`
- `prompt_name`
- `ext_info`

English-source filtering:

- when source language is English, the `_en` storage fields are written as NULL

Schema: `connected_artifacts JSONB` is added by migration
`20260605000001_add_connected_artifacts_to_kb_metrics.sql`; `metric_categories` /
`metric_categories_en` by `20260604000004_add_metric_categories_to_kb_metrics.sql`.
`ensureMetricsTable` also creates these columns with `ADD COLUMN IF NOT EXISTS` for fresh
installs.

## Artifact Output

The processor writes:

- `ARTIFACT_DIR/<group_id>/<record_id>/<filename_root>_<parser_name>.metrics`

Content:

- JSON array of normalized persisted metric rows

## Status Persistence

The processor appends a single `extract_metrics` status entry to `kb.inputs.status`.

Fields include:

- `record_id`
- `file_type`
- `operation`
- `input_filename`
- `start_time`
- `ms_used`
- `proc_status`
- `error` on failure

## API Handler Status

The background `extract_metrics` processor is multi-pass, but the review API is still legacy.

Current API behavior:

- `POST /api/v1/kb/metrics/extract` in `ChenWeb/server/api/kbhandler/extract-metric-handler.go`
- composes one temporary block from selected lines plus +/- 5 overlap lines
- loads a single extraction prompt and a single model config
- makes one LLM call
- expects a top-level `metrics` array directly from that one response
- returns review rows without persistence

- `POST /api/v1/kb/metrics/save`
- persists the reviewed rows with `event_id = "rest-api"`
- validates that every metric has a non-empty `metric_categories` (rejects with 400
  otherwise)
- inserts rows into `kb.metrics`, including `metric_categories` and an initial
  `connected_artifacts = '{}'`
- after saving, runs the same post-process indexing as Phase C
  (`docprocessing.ReindexMetricSearchForRecord` + `docprocessing.IndexMetricsForRecord`).
  Chunks are not available in the REST context, so `connected_artifacts.chunks` is left
  empty (logged) while the other outputs index normally.
- uses the legacy REST field names such as:
  - `metric_subject`
  - `metric_desc`
  - `metric_context`
  - `metric_keywords`
  - `metric_unit`

This means the review API has not yet been migrated to the multi-pass candidate/enrichment flow used by the processor.
