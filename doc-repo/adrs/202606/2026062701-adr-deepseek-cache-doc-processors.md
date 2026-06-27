# ADR: DeepSeek Prompt Cache for Doc Processors

Date: 2026-06-27

Status: Implemented (Phases 1–3 landed)

Extends: [2026062501-adr-deepseek-cache](2026062501-adr-deepseek-cache.md) (DeepSeek Prompt Cache for Document Reviewers)

## Context

ADR 2026062501 optimized the **document reviewers** for DeepSeek prompt caching
(document-first prompt layout, cache-locality scheduling, and cache-token telemetry in
`llm_usage_event`). The **doc processors** (the doc-processing pipeline in
`ChenWeb/server/api/doc-processing/`) were not covered, even though they are all configured
with DeepSeek and six of them consume the *same* chunks of a document.

Three gaps:

1. Doc-processor LLM prompts were **task-first**: `newLLMJSONInput` never set the shared
   client's `DocumentFirst` flag, so the repeated chunk text was a suffix, not a cacheable
   prefix.
2. Doc-processor logs (`kb.doc_proc_logs`) did not record provider prompt-cache counters
   (`prompt_cache_hit_tokens` / `prompt_cache_miss_tokens`), so cache effectiveness could not
   be measured.
3. Phase B runs one goroutine per processor, each looping its own chunks concurrently, so
   identical chunk prefixes from different processors are scattered in time (the anti-pattern
   ADR 2026062501 warns against).

## Decision

Apply the same cache principles to the doc processors, delivered in three phases.

---

### Phase 1 — Cache-token telemetry

> **Files:**
> - `ChenWeb/server/api/doc-processing/doc_proc_log_store.go` — `DocProcLogRecord` / `DocProcLogRow` fields, INSERT, `ListDocProcLogs` SELECT/scan.
> - `ChenWeb/server/api/doc-processing/cache_log.go` — `extractorCacheTokens` / `cacheTokenCounts` helpers.
> - `ChenWeb/project_migrations/20260627000001_add_doc_proc_logs_cache_tokens.sql` — goose migration.
> - Populated at every `llm_call` log site: `extract-metrics.go`, `extract-semantic-projections.go`, `extract-structured-knowledge.go`, `extract-entity-relation.go`, `extract-inventory-items.go`, `extract-products.go`, `extract-doc-metadata.go`, `doc-structure-analyzer.go`, `fix-size-chunking.go` (summaries/topics), `artifact_category_wiring.go`, `extract-provisions.go`, `generate-scene-blocks-processor.go`, `relation-extraction-freeform.go`.

- Added nullable `prompt_cache_hit_tokens` / `prompt_cache_miss_tokens` columns to
  `kb.doc_proc_logs` (migration `20260627000001`).
- `DocProcLogRecord` / `DocProcLogRow` carry the two counts; the INSERT and `ListDocProcLogs`
  SELECT/scan handle them.
- `extractorCacheTokens(extractor)` reads the LLM client's `LastJSONUsage()` and returns
  `(*int64, *int64)`. Stamped onto every `llm_call`-type log entry across all processors.
- `cacheTokenCounts(extractor)` is the plain-`int64` variant for structured-logger output on
  per-goroutine "end" log lines.
- Limitation: counters are read from per-client last-call state immediately after the call in
  the same goroutine; under concurrent chunk fan-out this is best-effort attribution (same
  approximation the doc reviewers accept). Aggregate per-record sums remain meaningful.

### Phase 2 — Document-first prompt layout

> **Files:**
> - `shared/go/api/llm/openai_client.go` — `buildMessages` envelope generalised.
> - `ChenWeb/server/api/doc-processing/llm_capture_input.go` — `DocumentFirst = true`.
> - `ChenWeb/server/api/doc-processing/artifact_category_wiring.go` — `DocumentFirst = false` for category creation (see below).

- `newLLMJSONInput` sets `DocumentFirst = true`, so every doc-processor LLM call uses the
  document-first envelope.
- The shared `buildMessages` document-first branch was generalized to workload-neutral
  wording (system: "You are a document processing engine. Return strict JSON only."; tags
  `<DOCUMENT_INPUT>` / `<TASK>`) so one envelope serves both reviewers and processors. This
  causes a one-time prompt-cache reset for the document reviewers, then a stable prefix again.
- **Exception — `create_artifact_category`:** category creation is intentionally
  **task-first** (`DocumentFirst = false`) because its stable repeated content is the prompt
  template, not the per-call category key (which varies).

### Phase 2.3 — Canonical chunk InputText

> **Files:**
> - `ChenWeb/server/api/doc-processing/input_lines.go` — `canonicalChunkInputText` helper.
> - Converged processors: `extract-metrics.go` (pass 1), `extract-semantic-projections.go`
>   (pass 1 + pass 2), `extract-entity-relation.go` (entities), `relation-extraction-freeform.go`
>   (relations), `extract-inventory-items.go`, `extract-provisions.go` (chunk mode only).

Each of the six chunk-consuming processors now builds `InputText` via the single helper
`canonicalChunkInputText(chunk.Lines, docCtx)` = `wrapLinesWithDocContext(markedLinesToJSON,
docCtx)`, with all schema/label/index text moved into the prompt (`<TASK>` section). Since
every chunk processor loads the same `.chunks` artifact and the same record, the same chunk
yields a byte-identical `InputText` across all processors → DeepSeek can reuse the cached
prefix.

Converged processors:

| Processor | Passes converged | Notes |
|---|---|---|
| `extract_metrics` | Pass 1 candidate | `chunksToBlocks` is 1:1; `Block` kept internally for output mapping only |
| `extract_semantic_projections` | Pass 1 candidate + Pass 2 enrich | Pass 2 reuses pass 1's chunk prefix |
| `extract_entity_relation` | Entities (Phase 1) + freeform relations | Both now use canonical helper |
| `extract_inventory_items` | Single pass | `docCtx` threaded through |
| `extract_provisions` | Chunk mode (`EXTRACT_PROVISIONS_INPUT` unset or `chunks`) | Schema + chunk index moved to prompt |

Not converged (intentionally):
- `extract_provisions` **blocks mode** (`EXTRACT_PROVISIONS_INPUT=blocks`): uses `Block`s
  with a different serialization. The blocks-mode path keeps its self-contained prompt.
- `create_artifact_category`: task-first (see Phase 2).

### Phase 3 — InputText sequencer for cache-locality adjacency

> **Files:**
> - `shared/go/api/llm/openai_sequencer.go` — `inputTextSequencer` (keyed binary semaphore).
> - `shared/go/api/llm/openai_client.go` — wired into `extractTextWithFormat` before `httpClient.Do`.

With Phase 2.3 the six chunk processors share a byte-identical prefix, but Phase B fans them
out concurrently — identical prefixes from different processors are not guaranteed to be
temporally adjacent and DeepSeek's cache is time-bounded.

An `inputTextSequencer` (`shared/go/api/llm/openai_sequencer.go`, patterned on the existing
`llmCallController`) serialises LLM calls that share the same `InputText` key (the canonical
chunk JSON). Right before the HTTP call in `extractTextWithFormat`, when `DocumentFirst` is
true, the call acquires a per-InputText binary semaphore and releases it after the response.
Calls with **different** InputText values proceed fully concurrently; calls with the **same**
value queue — so identical chunk prefixes from different processors arrive at DeepSeek
back-to-back → guaranteed cache hit for the 2nd, 3rd, …, 6th processor to touch a given chunk.

**Env var:** `LLM_INPUT_TEXT_SEQUENCER` (default `"true"`; set to `"false"` / `"0"` / `"off"`
to disable). Zero per-processor refactoring — the sequencer is transparent to each processor's
multi-pass logic, status writes, stop handling (`CheckAndHandleStop`), and indexing.

---

## Operational checklist

1. **Apply migration** `20260627000001_add_doc_proc_logs_cache_tokens.sql` to the target
   database (adds `prompt_cache_hit_tokens` / `prompt_cache_miss_tokens` to `kb.doc_proc_logs`).

2. **Run a doc-processing job** against real DeepSeek. Publish to
   `kb.pdf.start-doc-processing` with `{ "record_id": "<id>", "force": true }` on a record
   that is already parsed and chunked. Use the full configured pipeline (omit `operation` so
   all processors run).

3. **Inspect cache counters** in `kb.doc_proc_logs`:
   ```sql
   SELECT doc_proc_name, activity_name,
          prompt_cache_hit_tokens, prompt_cache_miss_tokens, ms_used, create_time
   FROM kb.doc_proc_logs
   WHERE record_id = <id>
     AND prompt_cache_hit_tokens IS NOT NULL
   ORDER BY create_time;
   ```
   Expected: first pass on a chunk shows mostly `miss` tokens; subsequent passes/processors on
   the same chunk show climbing `hit` tokens.

4. **Inspect goroutine-end logs** for `cache_hit` / `cache_miss` fields (structured log keys,
   not DB columns) on these lines: `extract metric end`, `enrich metric end`, `semantic proj
   end`, `extract inventory items end`, `extract provisions end`, `extract entities end`,
   `extract relation end`.

5. **To A/B test the sequencer:** run the same record twice — once with
   `LLM_INPUT_TEXT_SEQUENCER=true` (default) and once with `LLM_INPUT_TEXT_SEQUENCER=false`;
   compare `prompt_cache_hit_tokens` in `kb.doc_proc_logs`.

## File index

| Repo | File | Phase | Change |
|---|---|---|---|
| shared | `go/api/llm/openai_client.go` | 2, 3 | Generalised `buildMessages` envelope; wired `inputTextSequencer` |
| shared | `go/api/llm/openai_sequencer.go` | 3 | New: `inputTextSequencer` keyed binary semaphore |
| ChenWeb | `project_migrations/20260627000001_add_doc_proc_logs_cache_tokens.sql` | 1 | New migration |
| ChenWeb | `server/api/doc-processing/cache_log.go` | 1 | New: `extractorCacheTokens` / `cacheTokenCounts` |
| ChenWeb | `server/api/doc-processing/doc_proc_log_store.go` | 1 | Added cache columns to structs + INSERT + scan |
| ChenWeb | `server/api/doc-processing/llm_capture_input.go` | 2 | `DocumentFirst = true` |
| ChenWeb | `server/api/doc-processing/input_lines.go` | 2.3 | New: `canonicalChunkInputText` |
| ChenWeb | `server/api/doc-processing/artifact_category_wiring.go` | 2 | `DocumentFirst = false` (task-first for categories) |
| ChenWeb | `server/api/doc-processing/extract-metrics.go` | 1, 2.3 | Cache log; canonical InputText + `metricCandidateTask` |
| ChenWeb | `server/api/doc-processing/extract-semantic-projections.go` | 1, 2.3 | Cache log; canonical InputText; `semanticProjectionCandidateTask` / `semanticProjectionEnrichTask` |
| ChenWeb | `server/api/doc-processing/extract-entity-relation.go` | 1, 2.3 | Cache log; canonical helper |
| ChenWeb | `server/api/doc-processing/relation-extraction-freeform.go` | 1, 2.3 | Cache log; canonical helper |
| ChenWeb | `server/api/doc-processing/extract-inventory-items.go` | 1, 2.3 | Cache log; canonical InputText + docCtx |
| ChenWeb | `server/api/doc-processing/extract-provisions.go` | 1, 2.3 | Cache log; canonical InputText (chunk mode) + `provisionChunkTask` |
| ChenWeb | `server/api/doc-processing/extract-structured-knowledge.go` | 1 | Cache log |
| ChenWeb | `server/api/doc-processing/extract-products.go` | 1 | Cache log |
| ChenWeb | `server/api/doc-processing/extract-doc-metadata.go` | 1 | Cache log |
| ChenWeb | `server/api/doc-processing/doc-structure-analyzer.go` | 1 | Cache log |
| ChenWeb | `server/api/doc-processing/fix-size-chunking.go` | 1 | Cache log + `callExtractor` |
| ChenWeb | `server/api/doc-processing/generate-scene-blocks-processor.go` | 1 | Cache log |
| ChenWeb | `server/api/doc-processing/generate_summary_logging_test.go` | 1 | Updated sqlmock expectations |
| ChenWeb | `server/api/doc-processing/semantic-chunking_test.go` | 1 | Updated sqlmock expectations |
| ChenWeb | `server/api/doc-processing/*_test.go` | 1, 2.3 | Updated test call sites |
| KnowledgeStore | `doc-repo/adrs/202606/2026062701-adr-deepseek-cache-doc-processors.md` | — | This document |
| KnowledgeStore | `Capsules/coding-capsules/doc-processor/+CAPSULE.md` | — | Updated §6.2 |

## Verification

- `shared/go: go test -count=1 ./api/llm` — passes.
- `ChenWeb: go build ./server/api/doc-processing/` — clean; `go test ./server/api/doc-processing/`
  shows zero net-new failures vs the pre-change baseline (the package has known pre-existing
  expectation-drift failures, see ADR 2026062501 "Verification").
- `go vet ./...` clean on both packages.

## Env vars

| Var | Default | Phase | Effect |
|---|---|---|---|
| `LLM_INPUT_TEXT_SEQUENCER` | `"true"` | 3 | Serialise LLM calls with the same `InputText` for back-to-back cache hits. Set to `"false"` / `"0"` / `"off"` to disable. |

## Consequences

- All six chunk-consuming doc processors now share a byte-identical, cacheable DeepSeek
  prefix, with the sequencer enforcing temporal adjacency for cross-processor cache reuse.
- `kb.doc_proc_logs` carries provider cache counters per LLM call and per-chunk goroutine-end
  log lines, enabling empirical validation of cache effectiveness.
- The `create_artifact_category` path is explicitly task-first (its prompt template is the
  stable prefix). Provisions blocks-mode (`EXTRACT_PROVISIONS_INPUT=blocks`) uses a different
  input unit and is not converged — it would need its own unit-unification pass.
- No per-processor refactoring was required for the sequencer (Phase 3); it is transparent at
  the shared HTTP-client level.
