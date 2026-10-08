# Extract Metrics Implementation

Date: 2026-05-21 (updated 2026-06-05: Phase C indexing — connected_artifacts,
category_instance, category-path metrics.txt, hybrid_search links; updated 2026-10-07: chunk
input, chunk-batch path, grouped enrichment, pure-requirement filter, prompt defaults v11/v8;
updated 2026-10-08: soft drop to kb.metrics_dropped, open-value decision model)

## Scope

Implemented against:

- `KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-metrics-spec.md`

Primary implementation files:

- `ChenWeb/server/api/doc-processing/extract-metrics.go`
- `ChenWeb/server/api/doc-processing/extract-metrics_test.go`
- `ChenWeb/server/api/doc-processing/metric_statement_kind.go` (statement-kind classifier used by
  the pure-requirement filter) and `metric_statement_kind_test.go`
- `ChenWeb/server/api/doc-processing/extract_metrics_pure_requirements_test.go`
- `ChenWeb/server/api/doc-processing/metric_soft_drop.go` (`droppedMetricRow`,
  `DroppedMetricsStore`, `drop_metric_rows` log) and `metric_soft_drop_test.go`
- `ChenWeb/server/api/doc-processing/metric_open_value_decision.go` (`openValueJudge`,
  `judgeOpenValueRows`, `decisionModelJudge`) and `metric_open_value_decision_test.go`
- `ChenWeb/server/api/decisionmodel/provider.go` (`.models.toml` profile → decision client config,
  shared with the Decision Model Playground)
- `ChenWeb/server/api/kbhandler/metrics_dropped.go` (`include_dropped` on `GET /kb/metrics`)
- `ChenWeb/project_migrations/20261008000001_create_kb_metrics_dropped.sql`
- `ChenWeb/server/api/doc-processing/chunk_batch.go`, `chunk_batch_coordinator.go`
  (`ChunkBatchProcessor` path)
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

1. loads the record's chunks from its persisted `.chunks` artifact
2. runs a metric-candidate extraction pass for each chunk
3. converts candidate mentions to candidates (the cross-chunk merge is disabled)
4. enriches candidates into final metric rows, in batches grouped by source chunk
5. deduplicates final metric rows
6. drops pure requirements (inspection and delegated) and logs them
7. persists rows to `kb.metrics`
8. writes `.metrics` artifact output
9. updates `kb.inputs.status`

## Processor

The processor is implemented as `MetricsProcessor`.

Key public construction and interfaces:

- `NewMetricsProcessor(inputStore, store, extractor, logger)`
- `MetricsProcessor.Name()` returns `"extract_metrics"`
- `MetricsProcessor.HandleEvent(ctx, payload)` (sequential path)
- `InitChunkBatch` / `ProcessChunk` / `FinalizeChunkBatch` (`ChunkBatchProcessor`, used when
  `RUN_DOC_PROCESSOR_CONCURRENT=true`; the coordinator runs Pass 1 chunk by chunk alongside other
  chunk-based processors so they share the provider's prompt cache)
- `MetricsStore`
- `MetricsSQLStore`

## Event Workflow

`HandleEvent` (sequential path) performs the following steps:

1. Force thinking off for all metrics passes.
2. Parse the event payload with `ParseLineFileGeneratedEvent`.
3. Skip non-target events with `ShouldSkipLineFileGeneratedEvent`.
4. Fail if either prompt (candidates, enrichment) did not load.
5. Load `kb.inputs` by `record_id` and resolve the canonical line file path.
6. If `force=true`, delete existing metrics for the record (`DeleteMetricsByInputRecordID`,
   which first retires the record's metric evidence).
7. If `force=false`, skip when metrics already exist.
8. Parse the line file and load chunks from the `.chunks` artifact (chunking must have run).
9. Run `extractMetricsFromChunksWithLLM(...)`: Pass 1, candidates, Pass 2 via
   `enrichMetricCandidates` (which also dedups and applies the pure-requirement filter).
10. Assign `metric_id = <record_id>_mtc_<seqno>`, canonicalize `value_range_type`, apply table
    metric contexts.
11. Save rows with `SaveMetrics(...)`, log `extract_metrics_final`, persist metric objects.
12. Write `.metrics` artifact output and harvest metric-definition candidates.
13. Persist success or failure status into `kb.inputs.status`.

`FinalizeChunkBatch` (chunk-batch path) calls the same `enrichMetricCandidates`, then either
deletes and saves (`force_clear=true`) or merges into the existing rows and upserts the changed
ones (`force_clear=false`, see the incremental-processing ADR 2026071002).

`HandleEvent` no longer performs any indexing. All artifact indexing is deferred to
Phase C (post-process); see [Indexing (Phase C)](#indexing-phase-c).

## Multi-Pass Extraction

### Pass 1: Candidate Extraction

Per chunk, the processor:

- serializes the chunk's lines in canonical form
- builds a compact candidate prompt
- calls the mention model
- normalizes `candidates`

Prompt/model:

- prompt: `prompt-extract-metric-candidates-v14.md` (default)
- env: `EXTRACT_METRIC_CANDIDATES_PROMPT`
- model env: `EXTRACT_METRIC_CANDIDATES_MODEL_NAME`

Fallback:

- env: `EXTRACT_METRIC_CANDIDATES_MODEL_FALLBACK`
- if primary returns truncated or empty JSON, candidate extraction retries with fallback
- if fallback also returns the empty-JSON failure shape, the processor treats that chunk as empty candidates

### Candidates

After pass 1, `mentionsAsCandidates(...)` turns each mention into one candidate (log:
`Metric candidates (merge disabled)`). The cross-chunk merge `mergeMetricMentionCandidates(...)`
still exists but has no caller; duplicates are removed after enrichment instead (Final Dedup).

### Pass 2: Enrichment

`enrichMetricCandidates(...)` groups candidates by source chunk (`groupCandidatesByChunk`, at
most `METRIC_ENRICH_GROUP_SIZE` per batch, default 5) and runs the batches concurrently (up to
`EXTRACT_METRICS_MAX_TASKS`, default 1). For each batch it:

- sends the chunk text (`canonicalChunkInputText`, the same bytes Pass 1 sent, so the call reuses
  the provider's prompt cache) plus the enrichment prompt and the batch's candidates
- normalizes returned `metrics` and `uncertain_metrics` (`uncertain_metrics` are not saved)
- backfills `candidate_id` on the returned rows

A failed batch does not discard the others: successful batches are returned with the error.

Prompt/model:

- prompt: `prompt-enrich-metrics-v11.md` (default)
- env: `ENRICH_METRICS_PROMPT`
- fallback compatibility env: `EXTRACT_METRICS_PROMPT`
- model env: `ENRICH_METRICS_MODEL_NAME`
- fallback compatibility model env: `EXTRACT_METRICS_MODEL_NAME`

Logging:

- `enrich metric start` / `enrich metric end` per batch
- one `enrich_metrics` `kb.doc_proc_logs` row per batch

### Final Dedup

After enrichment:

- `dedupeFinalMetricRows(...)` merges accidental duplicates
- dedup key uses metric name, subject, unit, value, and normalized source spans

### Set-Aside Rows (Soft Drop)

Spec section 3.4.2; openspec change `metric-row-soft-drop-decision-model` (it replaced the
discard of `exclude-pure-requirements-from-metrics`). `enrichMetricCandidates` returns
`(metrics, uncertain, dropped []droppedMetricRow, err)`:

1. per batch, `dropRowsTaggedWithDropReason` splits off rows with a drop-reason tag
   (`metricDropReasonTag`); after all batches they are deduplicated and become `llm_tag` rows
2. `canonicalizeMetricValueRangeTypes(metrics)`
3. `excludePureRequirements(metrics)` splits off kinds `inspection_requirement` /
   `delegated_requirement` as `statement_kind` rows
3a. `excludeRowsWithoutValue(metrics)` (`metric_soft_drop.go`) splits off every row whose
   `metric_value` is empty or a placeholder as `no_value` rows (since 2026-10-09)
4. `p.judgeOpenValueRows(...)` sends `requirement_value_open` rows to `p.OpenValueJudge` and
   splits off `activity_schedule` at p ≥ `p.OpenValueDropMinP` as `decision_model` rows; every
   judged kept row gets `ext_info.open_value_decision` (which `SaveMetrics` now keeps)

`metricExtractionResult.Dropped` carries them to `HandleEvent`; `FinalizeChunkBatch` gets them
directly. Both call `p.saveDroppedMetricRows` after the live save (force_clear and merge paths):
it calls `DroppedMetricsStore.SaveDroppedMetrics` when the store implements it
(`MetricsSQLStore`, via `ResolvingMetricsStore`), which numbers rows after the record's highest
`drop_id` in one transaction, then writes the `drop_metric_rows` log. A failed save is logged,
not returned. `MetricsSQLStore.DeleteMetricsByInputRecordID` also deletes the record's
`kb.metrics_dropped` rows.

### Open-Value Decision

`NewMetricsProcessor` builds `p.OpenValueJudge` with `newOpenValueJudgeFromEnv`:
`METRIC_DECISION_MODEL` names a profile in the models file (`MODEL_DEF_FILE` / `MODELS_FILE` /
nearest `.models.toml`); `decisionmodel.ProviderConfig` maps it (DeepSeek: `thinking=disabled`,
`temperature=1`; DashScope: `top_logprobs=5`); the policy store is
`decisionpolicy.NewStore(ApiTypes.SharedDBHandle, …)`. Unset model → `OpenValueJudge` is nil and
open-value rows are kept with `open_value_decision.error`. `METRIC_DECISION_DROP_MIN_P` sets the
threshold (default 0.9). The policy seed prompt is `prompts/prompt-metric-open-value-policy-v1.md`
(override with `METRIC_OPEN_VALUE_POLICY_PROMPT`); it is used only when policy
`metric_open_value_kind` does not exist. `decisionModelJudge` loads the current policy once per
record and sends up to 8 rows in parallel.

`metricStatementKind` mirrors `web/src/lib/metric-statement-kind.ts` and the benchmark helper
`benchmark_io.py`; `metric_statement_kind_test.go` reuses the TS test's scenarios and the 69
record-416 gold rows (32 pure requirements).

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
   `lexical_score >= artifact_search.min_rank`; ranks by RRF, caps at
   `METRIC_CONNECT_MAX_LINKS` (default 10), excludes self; upserts edges with
   `relation_method='hybrid_search'`, `relation_name='semantically_related'` via
   `ReplaceConnectionsBySource` (source-scoped, cross-document idempotent replace).

### Config / env

- `METRIC_CONNECT_MIN_COSINE` (default `0.75`)
- `METRIC_CONNECT_MAX_LINKS` (default `10`)
- `artifact_search.min_rank`, `artifact_search.dictionary` (reused from the shared artifact search config)
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
- default: `prompt-extract-metric-candidates-v14.md`

Enrichment prompt loading:

- env priority:
  - `ENRICH_METRICS_PROMPT`
  - `EXTRACT_METRICS_PROMPT`
  - `PROMPT_FILE_NAME`
- default: `prompt-enrich-metrics-v11.md`

Prompt search is delegated to the shared `loadProductPromptFromEnvKeys(...)` helper. Prompt
paths resolve relative to the process's working directory.

v11/v8 (2026-10-07) stop asking for pure requirements; v10/v7 asked for delegated requirements
as `value_class = reference` rows. Deployments that pin the prompts by env must move the pins
themselves.

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

The processor reads the record's chunks from the persisted `.chunks` artifact
(`loadChunksFromArtifactFile`), so chunking must have run first. Chunks are converted to the
internal block shape with `chunksToBlocks(...)` (1:1), which keeps chunk-based processors aligned
on the same text.

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
- chunk index (used to group Pass 2 batches)

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
