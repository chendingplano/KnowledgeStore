# Doc Processor Log — Implementation Notes

## Files Created / Modified

### New Files

| File | Description |
|---|---|
| `ChenWeb/project_migrations/20260527000020_create_kb_doc_proc_logs.sql` | Goose migration: creates `kb.doc_proc_logs` table and indexes |
| `ChenWeb/server/api/doc-processing/doc_proc_log_store.go` | Go store: `DocProcLogger`, `DocProcLogRecord`, `SQLStore` methods |
| `ChenWeb/server/api/kbhandler/doc_proc_log_handler.go` | HTTP handlers: `ListDocProcLogs`, `DeleteOldDocProcLogs` |
| `ChenWeb/web/src/lib/components/home3/doc-proc-logs-view.svelte` | Svelte 5 frontend view |

### Modified Files

| File | Change |
|---|---|
| `ChenWeb/server/api/routes.go` | Added two routes: `GET /kb/doc-proc-logs`, `DELETE /kb/doc-proc-logs/old` |
| `ChenWeb/web/src/lib/components/home3/nav-rail.svelte` | Added `{ id: 'sysadmin-doc-proc-logs', label: 'Doc Processor Logs' }` to the `system-admin` nav item |
| `ChenWeb/web/src/lib/components/home3/content-panel.svelte` | Added import and `{:else if activeMenu?.childId === 'sysadmin-doc-proc-logs'}` branch |
| `ChenWeb/server/api/doc-processing/extract-metrics.go` | Instrumented with `ProcLogger`; see [Instrumented Processors](#instrumented-processors) |
| `ChenWeb/server/api/doc-processing/extract-doc-metadata.go` | Instrumented with `ProcLogger` |
| `ChenWeb/server/api/doc-processing/extract-provisions.go` | Instrumented with `ProcLogger` |
| `ChenWeb/server/api/doc-processing/extract-entity-relation.go` | Instrumented with `ProcLogger` |
| `ChenWeb/server/api/doc-processing/extract-semantic-projections.go` | Instrumented with `ProcLogger` |
| `ChenWeb/server/api/doc-processing/extract-structured-knowledge.go` | Instrumented with `ProcLogger` |
| `ChenWeb/server/api/doc-processing/generate-scene-blocks-processor.go` | Instrumented with `ProcLogger` |
| `ChenWeb/server/api/doc-processing/extract-products.go` | Instrumented with `ProcLogger` |
| `ChenWeb/server/api/doc-processing/generate-summaries-processor.go` | Instrumented with `ProcLogger` (summary only) |
| `ChenWeb/server/api/doc-processing/generate-topics-processor.go` | Instrumented with `ProcLogger` (summary only) |
| `ChenWeb/server/api/doc-processing/blocking-processor.go` | Instrumented with `ProcLogger` (summary only) |
| `ChenWeb/server/api/doc-processing/doc-structure-analyzer.go` | Instrumented with `ProcLogger` (summary only) |
| `ChenWeb/server/api/doc-processing/chunking-processor.go` | Instrumented with `ProcLogger` (summary only) |

---

## Instrumented Processors

### `chunking`

It should generate one record in 'kb.doc_proc_logs`, with:
- `entry_type` = 'chunking'
- `activity_name` = 'chunking'

**`extra_info`** Shape:
```json
{
  "num_chunks":10, 
  "chunks":[
    {
      "overlap": [28-33], 
      "lines":[34-58], 
      "size":420
    }
  ]
}
```

where:
- For the first chunk, "overlap" should be empty
- "size" is the chunk size in characters

---

### `generate_summaries`

#### Generate One Record per Summary.

**`extra_info`** Shape:
```json
{
  "level": 0,
  "seqno": 2,
  "model_name": "string",
  "prompt_name": "string",
  "fallback_name": "string",
  "translate_model_name": "string",
  "translate_time_ms": 300,
  "summary_size": 122,
  "translate" {true | false}
}
```

| Field | Value |
|-------|-------|
| `translate` | whether the categorh paths misses its English version, and whether it translated |
| `translate_model_name` | The model name for the translation, present only when it translated |
| `translate_time_ms` | The time in milliseconds used the translation, present only when it translated |

#### Generate one Summary Record

Generate one record when it finishes generating summaries.

**`extra_info`** Shape
```json
{
  "num_summaries": 12,
  "model_name": "string",
  "prompt_name": "string",
  "num_missing_en_fields": 2,
  "total_time_ms": 23456
}

### `extract_metrics`

**File:** `ChenWeb/server/api/doc-processing/extract-metrics.go`

#### Wiring

`MetricsProcessor` has a `ProcLogger DocProcLogger` field initialised in `NewMetricsProcessor`:

```go
ProcLogger: DocProcLogger{DB: ApiTypes.ProjectDBHandle},
```

Two private helpers do the actual writing:

| Method | Purpose |
|---|---|
| `logLLMCall(...)` | Writes one `llm_call` entry around each LLM invocation |
| `logMetricsSummary(...)` | Writes one `doc_proc_summary` entry at the end of `HandleEvent` |

#### LLM Call Entries (entry_type = `llm_call`)

| # | Where in code | `activity_name` | `pass` | `model_names` | `prompt_name` |
|---|---|---|---|---|---|
| 1 per block | Step 1 loop in `extractMetricsFromBlocksWithLLM` | `extract_metric_candidates` | `1` | model actually used (primary or fallback) | `MentionPromptRef` |
| 1 per candidate | Step 2 loop in `extractMetricsFromBlocksWithLLM` | `enrich_metrics` | `2` | `RelationModelName` | `RelationPromptRef` |

- `llm_call_id` format: `<event_id>_p1_b<block.Index>` for pass 1, `<event_id>_p2_c<candidate_idx>` for pass 2.
- `artifact`: the raw JSON map returned by the LLM (nil on error).
- `errors`: the error string if the call failed (nil on success).
- Fallback detection: if `extractMetricCandidatePayloadWithFallback` returns a model name different from `MentionModelName`, the call is counted as a fallback in `FallbackCount`.

#### Summary Entry (entry_type = `doc_proc_summary`)

- One record written per summary.

**`extra_info` shape:**

```json
{
  "total_metrics":     12,
  "uncertain_metrics": 3,
  "fallback_count":    1,
  "llm_call_count":    25,
  "num_blocks":        8
}
```

| Field | Meaning |
|---|---|
| `total_metrics` | Rows actually inserted into `kb.metrics` |
| `uncertain_metrics` | Metrics returned in the LLM's `uncertain_metrics` array |
| `fallback_count` | Number of blocks where the fallback mention model was used |
| `llm_call_count` | Total LLM calls made (pass 1 + pass 2 combined) |
| `num_blocks` | Number of blocks fed to the processor |

**Other summary fields:**

| Field | Value |
|---|---|
| `model_names` | Deduplicated slice of `MentionModelName`, `FallbackMentionModelName`, `RelationModelName` |
| `prompt_name` | First non-empty of `MentionPromptRef`, `RelationPromptRef` |
| `start_time` | Start of `HandleEvent` |
| `end_time` | Just before the summary log call |

> **Note:** `prompt_name` captures only the first non-empty prompt ref. Both `MentionPromptRef` and `RelationPromptRef` can be recovered from the individual `llm_call` entries for that invocation.

---

### `extract_doc_metadata`

**File:** `ChenWeb/server/api/doc-processing/extract-doc-metadata.go`

Single pass per page. Up to 10 retries, each is one LLM call.

#### LLM Call Entries

| # | Where in code | `activity_name` | `pass` | call ID pattern |
|---|---|---|---|---|
| 1 per retry (up to 10) | `extractMetadataWithFallback` loop | `extract_doc_metadata` | `1` | `<event_id>_p1_i<idx>` |

#### Summary Entry

**`extra_info` shape:**

```json
{
  "llm_call_count":     3,
  "fallback_used":      false,
  "num_pages_used":     1,
  "num_pages_available": 5
}
```

---

### `extract_provisions`

**File:** `ChenWeb/server/api/doc-processing/extract-provisions.go`

Single pass per block. Hard failure on error.

#### LLM Call Entries

| # | Where in code | `activity_name` | `pass` | call ID pattern |
|---|---|---|---|---|
| 1 per block | `extractProvisionsFromBlocksWithLLM` loop | `extract_provisions` | `1` | `<event_id>_p1_b<idx>` |

#### Summary Entry

**`extra_info` shape:**

```json
{
  "total_provisions": 15,
  "llm_call_count":   8,
  "fallback_count":   1,
  "num_blocks":       8
}
```

---

### `extract_entity_relation`

**File:** `ChenWeb/server/api/doc-processing/extract-entity-relation.go`

Single pass per chunk. Soft failures — failed chunks increment `FailedChunks` and continue.

#### LLM Call Entries

| # | Where in code | `activity_name` | `pass` | call ID pattern |
|---|---|---|---|---|
| 1 per chunk | extraction loop | `extract_entity_relation` | `1` | `<event_id>_p1_c<idx>` |

#### Summary Entry

**`extra_info` shape:**

```json
{
  "total_entities":  42,
  "total_relations": 18,
  "llm_call_count":  10,
  "fallback_count":  0,
  "failed_chunks":   1,
  "num_chunks":      10
}
```

---

### `extract_semantic_projections`

**File:** `ChenWeb/server/api/doc-processing/extract-semantic-projections.go`

Two passes: pass 1 per chunk (candidate extraction), pass 2 per candidate (enrichment). Pass 1 hard failure returns partial counts.

#### LLM Call Entries

| # | Where in code | `activity_name` | `pass` | call ID pattern |
|---|---|---|---|---|
| 1 per chunk | pass 1 loop | `extract_semantic_projection_candidates` | `1` | `<event_id>_p1_c<idx>` |
| 1 per candidate | pass 2 loop | `enrich_semantic_projections` | `2` | `<event_id>_p2_c<enrichIdx>` |

#### Summary Entry

**`extra_info` shape:**

```json
{
  "total_projections": 8,
  "candidates_count":  5,
  "llm_call_count":    14,
  "fallback_count":    0,
  "num_chunks":        10
}
```

---

### `extract_structured_knowledge`

**File:** `ChenWeb/server/api/doc-processing/extract-structured-knowledge.go`

Two passes: pass 1 per chunk (soft failure), pass 2 per candidate (hard failure returns partial counts).

#### LLM Call Entries

| # | Where in code | `activity_name` | `pass` | call ID pattern |
|---|---|---|---|---|
| 1 per chunk | pass 1 loop | `extract_knowledge_candidates` | `1` | `<event_id>_p1_c<idx>` |
| 1 per candidate | pass 2 loop | `enrich_structured_knowledge` | `2` | `<event_id>_p2_c<enrichIdx>` |

#### Summary Entry

**`extra_info` shape:**

```json
{
  "total_items":      20,
  "candidates_count": 12,
  "llm_call_count":   22,
  "failed_chunks":    0,
  "num_chunks":       10
}
```

---

### `generate_scene_blocks`

**File:** `ChenWeb/server/api/doc-processing/generate-scene-blocks-processor.go`

Two passes: pass 1 per chunk (scene candidate extraction), pass 2 per candidate (scene block enrichment).

#### LLM Call Entries

| # | Where in code | `activity_name` | `pass` | call ID pattern |
|---|---|---|---|---|
| 1 per chunk | pass 1 loop in `extractSceneBlocksFromChunksWithLLM` | `extract_scene_block_candidates` | `1` | `<event_id>_p1_c<idx>` |
| 1 per candidate | pass 2 loop in `extractSceneBlocksFromChunksWithLLM` | `enrich_scene_blocks` | `2` | `<event_id>_p2_c<idx>` |

#### Summary Entry

**`extra_info` shape:**

```json
{
  "total_scene_blocks": 5,
  "mentions_count":     30,
  "llm_call_count":     18,
  "fallback_count":     1,
  "num_chunks":         10
}
```

---

### `extract_products`

**File:** `ChenWeb/server/api/doc-processing/extract-products.go`

Four passes: pass 1 per block (mention extraction), pass 2 per candidate (relation enrichment), optional pass 3 per product (translation), optional pass 4 per product (categorization). Pass 1 and 2 have hard failures.

#### LLM Call Entries

| # | Where in code | `activity_name` | `pass` | call ID pattern |
|---|---|---|---|---|
| 1 per block | pass 1 loop in `extractProductsFromBlocksWithLLM` | `extract_product_mentions` | `1` | `<event_id>_p1_b<idx>` |
| 1 per candidate | pass 2 loop in `extractProductsFromBlocksWithLLM` | `enrich_product_relations` | `2` | `<event_id>_p2_c<idx>` |
| 1 per product (optional) | `translateProductRows` | `translate_products` | `3` | `<event_id>_p3_t<idx>` |
| 1 per product (optional) | `categorizeProductRows` | `categorize_products` | `4` | `<event_id>_p4_c<idx>` |

#### Summary Entry

**`extra_info` shape:**

```json
{
  "total_products":  12,
  "mentions_count":  35,
  "llm_call_count":  25,
  "fallback_count":  2,
  "num_blocks":      8
}
```

---

### `generate_summaries` (summary only)

**File:** `ChenWeb/server/api/doc-processing/generate-summaries-processor.go`

No LLM calls. Delegates to a chunking service. Summary entry captures timing and error status only.

#### Summary Entry

`extra_info`: `{}`

---

### `generate_topics` (summary only)

**File:** `ChenWeb/server/api/doc-processing/generate-topics-processor.go`

No LLM calls. Delegates to a chunking service. Summary entry captures timing and error status only.

#### Summary Entry

`extra_info`: `{}`

---

### `blocking` (summary only)

**File:** `ChenWeb/server/api/doc-processing/blocking-processor.go`

No LLM calls. Summary entry captures block/line counts.

#### Summary Entry

**`extra_info` shape:**

```json
{
  "num_blocks": 15,
  "num_lines":  450
}
```

---

### `structure_analyzer` (summary only)

**File:** `ChenWeb/server/api/doc-processing/doc-structure-analyzer.go`

No LLM log entries (the LLM calls are made by the pipeline). Summary entry captures output metrics.

#### Summary Entry

**`extra_info` shape:**

```json
{
  "num_lines":         500,
  "num_pages":         25,
  "num_labeled_lines": 498,
  "num_cover_pages":   2
}
```

---

### `chunking` (summary only)

**File:** `ChenWeb/server/api/doc-processing/chunking-processor.go`

No LLM calls. Delegates to a chunking service. Summary entry captures timing and error status only.

#### Summary Entry

`extra_info`: `{}`

---

## How to Instrument a New Processor

Follow the `extract_metrics` pattern:

1. Add a `ProcLogger DocProcLogger` field to the processor struct.
2. Initialise it in the constructor: `ProcLogger: DocProcLogger{DB: ApiTypes.ProjectDBHandle}`.
3. Add private helpers `logLLMCall` and `logMetricsSummary` (or equivalently named methods).
4. Wrap each LLM call site with `p.Now()` timing and call `p.logLLMCall(...)` after.
5. Call `p.logXxxSummary(...)` at the end of `HandleEvent`, after the status is persisted.
6. All logging errors must be non-fatal — emit a `p.Logger.Warn` and continue.

Logging errors are intentionally non-fatal — always warn but never abort the processor.

---

## LLM Call ID Format

All processors use the same `llm_call_id` format:

```
<event_id>_p<pass>_<type><idx>
```

- `<event_id>`: `eventIDFromContext(ctx)` — unique per event
- `<pass>`: 1–4, indicating which pass/phase the call belongs to
- `<type>`: `b` (block), `c` (candidate/chunk), `i` (iteration/retry), `t` (translation)
- `<idx>`: zero-based index within the loop

Examples: `abc123_p1_b0`, `abc123_p2_c3`, `abc123_p3_t0`

---

## Summary Logging Pattern for Summary-Only Processors

Processors that don't call LLMs directly (blocking, chunking, structure_analyzer, generate_summaries, generate_topics) still produce a `doc_proc_summary` entry. The pattern is:

1. Add `ProcLogger DocProcLogger`, `Now func() time.Time` to the struct.
2. Initialise in the constructor.
3. Add a `logSummary` method that takes the available result metrics.
4. Call `p.logSummary(...)` at the end of `HandleEvent`.
5. `model_names` is `[]string{}` and `prompt_name` is `""` since no LLM models are involved.

---

## PostgreSQL Array Handling

The `model_names` column is `TEXT[]`. The store encodes/decodes it manually without the `lib/pq` driver's array types to avoid adding a new dependency. The encoder writes `{elem1,elem2}` format; the decoder in `pgTextArray.Scan` parses it back. Elements containing commas must be quoted by PostgreSQL (which it does automatically).

---

## Pagination and Filtering

`ListDocProcLogs` builds a dynamic WHERE clause. `$N` parameters are numbered sequentially using the local `itoa` helper; LIMIT/OFFSET parameters are appended last. Results are ordered by `create_time DESC`.

---

## Retention

`DeleteOldDocProcLogs` uses an interval cast:

```sql
DELETE FROM kb.doc_proc_logs
WHERE create_time < NOW() - ($1 || ' days')::interval
```

The `retentionDays` argument is validated to be ≥ 1 before calling the store.

---

## Frontend Design Decisions

- The view uses inline styles from design tokens (same pattern as `jetstream-logs-view.svelte`) for full dark/light mode compatibility without Tailwind colour purging issues.
- Clicking a row expands it in-place to show `extra_info`, `artifact`, and full error text as pretty-printed JSON inside a `<pre>` block.
- The retention panel uses a red "Apply Retention" button to signal the destructive nature of the action.
- `duration_ms` is computed server-side in the handler (`end_time − start_time`) to avoid date arithmetic in the frontend.
