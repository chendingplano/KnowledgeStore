# 1. Extract Metric Definitions Processor

This is a Doc Processor (`spec-doc-processor.md`, `+CAPSULE.md`). It harvests the
**definition** of a metric and proposes each one as a review-only `metric_definition` term
candidate.

It is one of the P3–P4 ontology-platform harvesters introduced by ADR 2026072901
(`KnowledgeStore/doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md`,
§8.2 table row, §8.3.6, §A.1/A.2, §3.24 DR23). Code:
`ChenWeb/server/api/doc-processing/extract-metric-definitions.go` (`MetricDefinitionsProcessor`),
sharing its candidate-building helpers with `extract_test_methods` in
`ontology_candidate_harvest.go`.

## 1.1 What Is a Metric Definition

**A metric definition is a statement that says what a metric *is* — its meaning, the
property it measures, or how it is computed.** It is not a value, and it is not a mention of
the metric's name — it is the text that gives the metric its *identity* (canonical name,
aliases, meaning, value type, range type, and, when stated, the property measured, quantity
kind, permitted units, and the classes/objects it applies to).

The prompt (§4) recognizes **three** source patterns, given equal weight — a defining
*formula* is only one of them, not the only one:

1. **A "Terms and definitions" (术语与定义) entry** — this is the standard/document's own
   glossary section, and in practice the most common pattern in a well-formed technical
   standard:
   `3.1.5 响应时间 response time：从输入到输出发生变化之间的时间间隔`
2. **An explicit definition clause** embedded in running text:
   `响应时间是指从输入到输出变化之间的时间间隔` / `X is defined as ...` / `X 定义为……`
3. **A formula that defines the metric** — the metric's value is *computed*, and the formula
   itself is the definition:
   `发芽指数(%) = 处理组种子发芽率 × 处理组平均根长 / 对照组种子发芽率 × 对照组平均根长 × 100%`

All three are equally valid; which one(s) a given document contains just depends on how that
document is written. A document with a "术语和定义" section but no formulas can still yield
several definitions from pattern 1 alone — a formula is not required.

**A metric definition is not a metric value.** `≤ 200 ms`, `应不大于 200 ms`, a table cell, or
a pass/fail threshold is a metric *assertion* — a claim about what a value *is* for a
specific document/context — not a definition of what the metric *means*. Assertions are
`extract_metrics`'s job ([4]); this processor explicitly excludes them (§4). This processor
also never activates ontology content by itself — it only proposes review candidates
(capsule §7.5, §7 below).

# 2. Pipeline Position

| Property | Value |
|---|---|
| Pipeline table row | 14 (`+CAPSULE.md` §7) |
| Class | `routed` — requires a resolved pipeline policy selecting it; skipped if routing is undetermined (§7.1) |
| Phase | B (concurrent, chunk-batched — §7.3) |
| Depends on | `chunking` |
| Requires LLM | Yes |
| Writes to | `kb.ontology_candidates` only (`candidate_kind='term'`, payload `term_kind='metric_definition'`) |

Because it is `routed`, not `configurable`, listing it in `config.toml`
`required_processors` is not enough by itself — a pipeline policy binding/gate must also
select it (capsule §7.1, §7.6). It implements `ChunkBatchProcessor`
(`InitChunkBatch`/`ProcessChunk`/`FinalizeChunkBatch`), so it always runs under the
per-chunk batching coordinator (`chunk_batch_coordinator.go`) alongside the other converged
chunk processors, never through `HandleEvent` (which always returns an error for this
processor — chunk batching is mandatory, not a fallback path).

# 3. Configuration

| Env var | Purpose | Default |
|---|---|---|
| `EXTRACT_METRIC_DEFINITIONS_MODEL_NAME` | Model profile key (a section name in `.models.toml`) | none — required, resolution fails without it |
| `MODEL_DEF_FILE` | Path to the `.models.toml` profile file | shared workspace default |
| `EXTRACT_METRIC_DEFINITIONS_PROMPT` | Prompt file name/path (see §4) | `prompt-extract-metric-definitions-v2.md` |

Both the model and the prompt are resolved once in `NewMetricDefinitionsProcessor` via the
same `loadModelConfigFromEnvKeys` + `applyStructureModelConfigToExtractor` +
`loadProductPromptFromEnvKeys` helpers every other LLM-backed processor in this package
uses. If either resolution fails (`ModelErr`/`PromptErr` non-nil) or `CandidateSink` is nil
(no `ApiTypes.ProjectDBHandle` at construction time), `InitChunkBatch` fails fast with
`"extract_metric_definitions is not configured"` and the whole batch run for this processor
is skipped — no partial/silent extraction.

> Until 2026-08-11 this constructor read `EXTRACT_METRIC_DEFINITIONS_MODEL_NAME` directly via
> `os.Getenv` instead of going through `loadModelConfigFromEnvKeys`, so the shared
> `*OpenAIJSONClient` never got `BaseURL`/`APIKey` wired from `.models.toml` — every LLM call
> failed silently (empty `base_url` defaulted to `https://api.openai.com`). See
> `extract-metric-definitions_test.go`'s
> `TestNewMetricDefinitionsProcessor_ConfiguresExtractorFromModelsFile` for the regression
> test. If output looks empty/missing for a document processed before that date, this is why
> — not a prompt or data issue.

# 4. Extraction Rules (Prompt)

The prompt (`ChenWeb/prompts/prompt-extract-metric-definitions-v2.md`) is deliberately
**precision-first**: it instructs the LLM to extract a definition only when the source text
explicitly defines what a metric *is* (§1.1's three patterns), and to leave the
value/threshold on a separate extraction path.

**Do NOT extract:**
- a bare value, threshold, target, or limit with no definitional content
  (`≤ 200 ms`, `应不大于 200 ms`, `温度为 25 °C`) — that is a metric *assertion*, handled by
  `extract_metrics` / the normalize-assertions path, not this processor
- a unit by itself, a heading/TOC entry, or a metric that is merely mentioned/used without
  being defined
- a vague statement naming no specific, definable metric

When a clause both defines a metric and states a value in the same breath (e.g. `响应时间是
指从输入到输出变化之间的时间间隔，且应不大于 200 ms`), only the definition half is
extracted; the value stays on the assertion path.

Other rules worth knowing when reading output: `source_line_spans` is required per row — a
row with no identifiable source line is not emitted at all; `confidence` is set low
(0.0–0.5) when the definition is implied rather than explicit; names/definitions are kept in
the source language (never translated); and an empty `metric_definitions` array is the
expected, correct response for a chunk with no definitions in it.

# 5. Workflow

1. **`InitChunkBatch(ctx, recordID, chunks, docCtx)`** — resets per-run state
   (`batchRecordID`, `batchChunks`, `batchDocCtx`, `mentions`); makes no LLM calls.
2. **`ProcessChunk(ctx, i)`**, once per chunk index, scheduled by the shared coordinator
   (`chunk_batch_coordinator.go`) so this processor's calls interleave with its Phase B
   siblings for DeepSeek prompt-cache reuse (capsule §6.2). Each call:
   - builds the input via `canonicalChunkInputText(chunk.Lines, docCtx)` — the same
     byte-identical serialization every converged chunk processor uses, so cross-processor
     cache hits land on this chunk
   - calls `Extractor.ExtractJSON` with `newLLMJSONInput(..., callReason="extract_metric_definitions", callLoc="P4-METRIC-DEFINITIONS")`
   - parses the response with `parseMetricDefinitionMentions` (`ontology_candidate_harvest.go`):
     rows with an empty `canonical_name` are dropped; everything else is normalized
     (deduped/sorted aliases and permitted units, line spans reduced to line numbers) and
     appended to `p.mentions` under a mutex (chunks run concurrently)
   - on an LLM/parse error, the chunk contributes nothing and the error is returned to the
     coordinator, which records it as the batch's first error but still runs every other
     chunk for every other processor (a single chunk failure does not stop the run)
3. **`FinalizeChunkBatch(ctx)`** — for every accumulated mention, builds a candidate via
   `buildMetricDefinitionCandidate` and calls `CandidateSink.CreateCandidate`. Any candidate
   build/insert error aborts finalization and is returned as the processor's error for this
   run (`kb.inputs.status` `extract_metric_definitions` entry gets `proc_status="failed"`).

There is no cross-chunk merge step: if the same metric is genuinely defined in two chunks
(e.g. an overlap region), both mentions are proposed and deduped downstream by
fingerprint (§7), not combined in-process.

# 6. Output Schema (LLM Response)

```json
{
  "metric_definitions": [
    {
      "canonical_name": "string",
      "aliases": ["string"],
      "definition": "string",
      "description": "string",
      "observable_property": "string",
      "quantity_kind": "string",
      "permitted_units": ["string"],
      "applies_to": ["string"],
      "value_type": "string",
      "range_type": "lower_bound|upper_bound|exact|range|qualitative|limit_absent",
      "confidence": 0.0,
      "source_line_spans": ["line", "start:end"]
    }
  ]
}
```

`canonical_name` and `definition` are the only fields the prompt requires; everything else
is left empty rather than guessed when the source doesn't state it (rule 5 in §4).

# 7. Candidate Storage

Each parsed mention becomes one `candidates.Candidate` (`buildMetricDefinitionCandidate`,
`ontology_candidate_harvest.go`) and is written via `CandidateStore.CreateCandidate`
(`ChenWeb/server/api/ontology/candidates/candidates_store.go`):

| `kb.ontology_candidates` column | Value |
|---|---|
| `candidate_kind` | `"term"` |
| `proposed_payload` | `{term_id: "measurement:<slug(canonical_name)>", term_kind: "metric_definition", module_id: "measurement", definition, description, observable_property, quantity_kind, permitted_units, applies_to, aliases, value_type, range_type, scope: "document-derived candidate", label: canonical_name}` |
| `proposed_module_id` | `"measurement"` |
| `source_type` | `"document"` |
| `source_ref` | `"input_record:<record_id>"` |
| `source_line_spans` | normalized, deduped, sorted line numbers from the mention |
| `discovery_method` | `"routed_extraction"` |
| `confidence` | the mention's confidence, clamped to `[0,1]`, `0` if out of range |
| `proposed_by` | `"extract_metric_definitions"` (hardcoded — see caveat below) |
| `status` | `"discovered"` (default; a curator moves it through the review state machine) |

**Insert is `INSERT ... ON CONFLICT (fingerprint) DO NOTHING RETURNING ...` — additive only,
never delete-on-rerun.** `Fingerprint()` hashes the canonicalized `proposed_payload` +
`source_type` + `source_ref` + `proposed_module_id`; `source_ref` is document-level
(`input_record:<id>`), so it is **not** line-specific. Two rows are "the same candidate" iff
every payload field matches exactly. Practical implications:
- Reprocessing the same document does not purge prior candidates first; every run
  re-attempts an insert per mention, and identical fingerprints are silently reused
  (`Reused=true` on the returned `Candidate`, no row mutation).
- Because LLM output is not byte-stable across runs, the *same* real-world definition
  extracted with even slightly different wording (a different `definition` string, a
  reordered alias list, etc.) produces a **different** fingerprint and a **new**, separate
  row rather than superseding the old one. Rerunning this processor against a document
  several times can accumulate near-duplicate candidates for the same metric.

**Promotion is out of scope for this processor.** It never writes governed ontology
content; a `term`/`metric_definition` candidate becomes active only after curator review and
a module release (capsule §7.5; ADR §8.3.7).

**`extract_metrics` also feeds this same table, independently.** Since `extract_metrics`
commit `5c0caf66b5b9` (2026-08-01), `extract_metrics`'s own `HandleEvent` calls
`harvestMetricDefinitions` (`ontology_candidate_harvest.go`) unconditionally at the end of
every run: for every extracted metric whose own `formula_or_definition` field
(`kb.metrics.formula_or_definition`) is non-empty, it builds and inserts a candidate through
the **same** `buildMetricDefinitionCandidate` helper this processor uses — so a
`kb.ontology_candidates` row with `proposed_by="extract_metric_definitions"` may in fact have
been created by `extract_metrics`'s inline harvest, not by this processor running at all
(`buildMetricDefinitionCandidate` hardcodes that field regardless of caller). Neither this
document nor the ADR's processor table previously called this out; treat
`kb.ontology_candidates` row counts as **not** attributable to this processor alone without
also checking whether `extract_metrics` ran on the same record. The two extraction criteria
differ materially — see §8.

# 8. Known Behavior / Limitations

- **Low output volume on a typical document is expected, not necessarily a bug.** The
  prompt's inclusion bar (§1.1, §4) is intentionally narrow: one of the three definition
  patterns must actually be present in the text. Most standards/technical documents state many metric
  *values* (assertions, thresholds, table cells) for every explicit *definition* they
  contain — often a document has only one or two genuine definitions in its entire text, or
  none at all. A large gap between `extract_metrics`'s row count and this processor's
  candidate count is the normal shape of the two extraction tasks, not by itself evidence of
  a missed-extraction bug — confirm against the source text (does a defining sentence or
  formula actually exist?) before assuming under-extraction.
- **`extract_metrics`'s `formula_or_definition` field is a looser, noisier signal than this
  processor's output** and should not be used as a ground truth for what this processor
  "should have" found. In spot checks, that field has been observed populated with plain
  threshold/requirement text (e.g. `"应达到NY884的要求"` — "shall meet standard NY884's
  requirements", not a definition of anything) and, in at least one case, with definition
  text that does not appear anywhere in the source document at all (an apparent LLM
  hallucination, not grounded in any line span it cited). Treat a non-empty
  `formula_or_definition` as a hint to go read the cited source line, not as confirmation
  that a definition exists there.
- **Ambiguous cases** — a "Terms and definitions" entry for a qualitative/process concept
  rather than a quantifiable metric (e.g. a management principle defined in §3 alongside
  genuine metric terms) — have been observed going unextracted in production runs even
  though they match the prompt's own first example pattern. Whether such entries should
  count as a "metric" definition is not resolved by the current prompt text; if curators want
  these captured, the prompt's scope (§4) needs explicit guidance on qualitative/non-quantity
  terms, and/or a few-shot example, rather than assuming the current wording already covers
  it.
- **No `kb.doc_proc_logs` entries.** Unlike every other converged chunk processor
  (`extract_metrics`, `extract_provisions`, `extract_inventory_items`, ...), this processor
  has no `DocProcLogger`/`DocProcLogRecord` writes — its `p.Logger.Info`/`Warn` calls
  (per-chunk start/end, extracted-definition counts, cache hit/miss token counts) go only to
  the process's `JimoLogger` output (stdout/slog), never to the `kb.doc_proc_logs` table.
  This means per-chunk extraction counts, prompt-cache effectiveness, and LLM call latency
  for this processor are not queryable after the fact the way they are for its siblings
  (capsule §6.2's `prompt_cache_hit_tokens`/`prompt_cache_miss_tokens` columns stay `NULL`
  for it) — a real observability gap worth closing by adding the same `ProcLogger
  DocProcLogger` field and log-record writes `extract-metrics.go` uses.

# 9. Status JSON

See `+CAPSULE.md` §9.11.

# 10. References

[4] Extract Metrics Spec: `KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-metrics-spec.md`

[18] ADR 2026072901 — Ontology Platform and Adaptive Pipeline:
`KnowledgeStore/doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md`
(§8.2 processor table, §8.3.6 §8.3.7 contradiction resolution, §A.1/§A.2 processor detail table)

Doc-processor pipeline overview and shared conventions (chunk-batch coordinator, LLM input
format, DeepSeek cache layout): `+CAPSULE.md` §6–§7.
