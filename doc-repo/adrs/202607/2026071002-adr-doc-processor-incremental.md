# ADR Incremental Update Artifacts in Doc Processors

**Date:** 2026-07-10 \
**Status:** Accepted \
**Component:** xxx \
**Authors**: Chen Ding\

## Change Logs
* 2026/07/10, ADR Created
* 2026/07/11, Added DR3 (artifact ID stability), Merge Resolution LLM call
  spec, transitive Metric Groups, transactional delete+insert, split
  `force_clear` out from the existing `force` flag, added Motivating
  Observation analysis, and filled in Database Migrations / Data Formats /
  Environment Variables / Code Changes / Operational Behaviors / Consequences
  / Tests / Documentation Impact
* 2026/07/11, Added DR4 (enrichment scope and dirty-check for merge mode):
  clarified Pass 1/Pass 2 enrichment boundary, moved `metric_id` assignment
  to before the Merge Resolution LLM call, switched the LLM call's
  correlation key from an ephemeral `ref` to real `metric_id`s, and replaced
  DR2's delete-all+insert-all persistence step with insert/update only what's
  dirty
* 2026/07/11, Implementation: migrated from HandleEvent to chunk-batch
  coordinator path after discovering HandleEvent's force/skip logic is dead code
  on the live path; DR1-DR4 implemented in InitChunkBatch/ProcessChunk/
  FinalizeChunkBatch instead; added migration for kb.metrics unique constraint
  (dedupe + (input_record_id, metric_id) partial index); found and fixed a
  Rule-4 merged-winner field-blanking bug (reconstruct full row from source,
  overlay only LLM-decided fields); restored force-gated wipe guard for
  extract_provisions, extract_inventory_items, and extract_entity_relation on
  the same live path that was missing it; added force_clear frontend control to
  doc-processor-dashboard-view.svelte

## Context
Doc processors are all idempotent, which is achieved by removing all
the records a doc processor generated for the given input record 
(note: doc processors always run with a given input record), then
insert the extracted artifacts into the table for the given input record.

This ADR applies to the following doc processors:
- `extract_metrics`
- `extract_provisions`
- `extract_inventory_items`
- `extract_entity_relation`

**Scope note:** DR1 (`force_clear` flag) and DR3 (artifact ID stability) apply to
all four processors above. The merge rules in DR2 are specified for
`extract_metrics` only in this ADR. Until an analogous merge-rule ADR lands for
`extract_provisions`, `extract_inventory_items`, and `extract_entity_relation`,
those three processors accept the `force_clear` flag but always behave as if
it is `true` (full delete + reinsert) — `force_clear=false` is a no-op for them
until their own merge semantics are defined.

### Motivating Observation: Does Re-Running Improve Coverage?

**Observation (Chen):** During debugging, re-running the same doc processor
over the same, unchanged document repeatedly produced different metric
counts each time, apparently due to the non-deterministic nature of LLMs.
This suggests a workflow: instead of clearing and re-extracting from scratch
each run (which throws away one run's findings to make room for the next
run's), keep what was already extracted and merge in whatever the new run
finds. Repeated runs would then accumulate toward better coverage instead of
each run gambling with a fresh, independent roll of the dice.

**Analysis — is this correct?** Partly, and the part that's likely wrong is
important enough that it changes what this ADR needs to guarantee.

- The underlying observation (run-to-run variance in extracted metric count)
  is almost certainly real and expected. LLM extraction over long documents
  is non-deterministic for reasons beyond sampling temperature: chunk-boundary
  effects, batch composition in Pass 2 enrichment
  (`METRIC_ENRICH_GROUP_SIZE`), and borderline "is this really a metric?"
  judgments (`is_explicit_metric`, `uncertain_metrics`) can all flip between
  runs. So "the same processor finds different metrics on different runs" is
  not surprising.
- The inference — "so more runs monotonically improve coverage" — only holds
  if the variance is dominated by **missed extractions of genuinely distinct
  metrics** (false negatives that differ per run). It does *not* hold if a
  meaningful share of the variance is instead **the same real-world metric
  re-described slightly differently** (different `metric_value` formatting,
  a metric split into two rows one run and merged into one the next, or
  — critically — `source_line_spans` drifting by a line or two between runs
  for what is the same underlying metric). In that second case, "more
  metrics after more runs" looks identical from the outside (the count goes
  up) but is actually duplicate inflation, not coverage growth.
- This matters because of how DR2 detects duplicates: Rule-1 requires exact
  field equality, and Rule-3/Rule-4 route entirely on whether
  `source_line_spans` overlaps an existing metric. If two runs extract the
  *same* real metric but their line spans happen not to overlap (boundary
  drift), Rule-3 fires and the "duplicate" is silently added as a brand-new
  metric — no LLM adjudication ever sees it, because Rule-4 (and therefore
  the Merge Resolution LLM call) only triggers on line overlap. So the
  current design's safety net has a blind spot precisely in the case that
  would falsify the "more runs = better coverage" hypothesis.
- Net assessment: the hypothesis is plausible and probably *partially* true
  (some runs do catch genuinely different metrics), but the observation as
  stated ("the count went up") cannot distinguish real coverage gain from
  duplicate accumulation, and the mechanism in this ADR does not yet close
  that gap for the boundary-drift case.

**Does this ADR add value, or should it stop?** It should continue — but the
coverage-improvement story should not be its primary justification until
tested. The ADR has a separate, independently solid justification that holds
regardless of how the coverage question resolves: **stable artifact IDs and
non-destructive manual re-runs.** Per DR3's motivation, downstream state
already keys off `metric_id` — cross-document links in `kb.artifact_connections`,
and per-artifact review state such as `kb.doc_review_findings.artifact_id` and
`kb.doc_review_provision_analyses` (see the doc-review-artifact-reviewers ADR
family) — so a naive `force_clear` re-run today can silently orphan review
work that was already done against a metric. DR1–DR3 fix that regardless of
whether repeated runs ever improve recall.

Before leaning on the coverage argument operationally (e.g. as the rationale
for the future Loop-Engineering harness), it should be validated rather than
assumed:
- Run the same processor N times over a small set of documents with a
  hand-labeled gold metric list; track recall against the gold set and
  duplicate rate (metrics whose `source_line_spans` are close-but-not-
  overlapping and whose other fields are near-identical) across N. If recall
  climbs and duplicate rate stays flat, the hypothesis holds. If metric count
  climbs but recall doesn't, it's inflation, not coverage.
- If boundary-drift duplicates turn out to be common, DR2's identity check
  needs a fallback beyond line-overlap — e.g. a semantic-similarity pass
  over `metric_name`/`metric_subject`/`metric_value` for metrics whose spans
  are near (not necessarily overlapping) — before this merge strategy is
  trusted for unattended repeated runs. Recording this as an open item under
  Alternative Decisions below rather than committing to it now.

## Decision
### DR1 — `force_clear`, a new flag independent of the existing `force` flag
The doc-processor run event (`kb.line-file-generated`, parsed in
`ChenWeb/server/api/doc-processing/event.go`) already carries a `force` field
(bool, defaults to `true` when omitted). `force` keeps its current meaning,
unchanged by this ADR:
- `force=false` and the processor already completed successfully for this
  `input_record_id` → skip the run entirely (idempotent skip; for
  provisions/inventory_items/entity_relation this also reindexes search on
  the skip path, per their existing `reindexExistingSearchOnSkip` calls —
  metrics instead defers reindexing to Phase C). Unchanged by this ADR.
- `force=true` → run the processor regardless of prior success. Unchanged by
  this ADR.

This ADR adds a second, independent flag, `force_clear` (bool, default
`false`), which only matters once a run actually happens — i.e. `force=true`,
or `force=false` on a record with no prior successful run:
- `force_clear=true` → the processor clears its prior artifacts and
  re-extracts from scratch: today's unconditional behavior
  (`DeleteMetricsByInputRecordID` / `DeleteProvisionsByInputRecordID` / etc.,
  then insert).
- `force_clear=false` (the default) → the processor does **not** delete
  prior artifacts; it merges the newly extracted artifacts with the existing
  ones per DR2.

So the four combinations are: skip (force=false, already done); wipe-and-run
(force=true, force_clear=true); merge-and-run (force=true or first-run,
force_clear=false); and first-run (`force` is moot — there's nothing to
force over — `force_clear` still selects wipe-from-empty vs. merge-into-empty,
which are equivalent on a genuinely empty table).

When a doc processor is run automatically by the pipeline, `force_clear` is
always set to `false` — automatic runs always merge, never wipe.

When a doc processor is launched manually, the frontend exposes
`force_clear` as a control independent of today's existing run-mode toggle
that sets `force` (`doc-processor-dashboard-view.svelte`'s `doLaunch`), so a
user can select any of the four combinations above.

Per the Scope note above, only `extract_metrics` implements the merge branch
in this ADR. The other three processors accept `force_clear` in their event
payload (so the field threads through uniformly) but ignore it and always
take the wipe branch until their own merge-rule ADR lands.

**Note on staleness:** DR2's merge never removes a previously-persisted
metric just because its source lines were edited or deleted from the
document — merging only adds/updates, it does not prune. For now this is an
accepted tradeoff: the caller is responsible for setting `force_clear=true`
when a source edit should discard stale metrics. The two intended manual
uses of `force_clear=true` are (1) debugging, and (2) a future extraction
harness that re-runs a processor deliberately (in the spirit of "Loop
Engineering") to iteratively improve extraction quality — that harness will
be specified in a separate, forthcoming ADR.

### DR2
When `force_clear` is false:
- Do not delete the artifacts generated so far for the given input record. 
  Instead, read them in.
- Merge the existing artifacts and the ones extracted by this run.

#### Metric Groups
Two or more metrics form a Metric Group if they are connected by a chain of
shared lines: metric A and metric B are in the same Metric Group if they
directly share at least one line, or if there exists a metric C such that A
and C are in the same Metric Group and C and B share at least one line
(transitive closure over the line-overlap graph).

Compute Metric Groups as connected components (e.g. union-find, or BFS/DFS
over the overlap graph) across the union of existing metrics and newly
extracted metrics for the input record, before applying Rule-4 below.

#### Merge Rules for Metrics:
Rule-1: Two metrics A and B are the same if their fields that are listed below are the same:
- `metric_name`
- `metric_subject`
- `metric_unit`
- `metric_value`
- `source_line_spans`

For each newly extracted artifact A:
Rule-2: If A and an existing metric are the same, ignore A and remove A
from the newly extracted metric list.

Rule-3: If A's line span does not overlap with any of the existing 
metrics, add A to the existing metric set and remove it from
the newly extracted metric list.

Rule-4: Otherwise, it has a common line with at least one existing
metric. Append A to the existing metric list and mark it as 'potential
duplicate'. Remove A from the newly extracted metrics.

After the newly extracted metrics are merged, if there are 'potential
duplicate' metrics:
- For each potential duplicate metric A, take A's Metric Group (the full
  transitive closure of shared lines, see Metric Groups above, not just A's
  direct line-neighbors) and append every metric in it to a pending list L
- Dedup metrics in L
- Assign a `metric_id` (per DR3) to every entry in L that doesn't already
  have one (i.e. every "new" candidate) before the LLM call — see DR4, which
  requires every entry passed to the Merge Resolution LLM call, existing or
  new, to carry a real `metric_id`.
- Feed L to the Merge Resolution LLM call defined below.
- Handle the LLM response (see "Handling the response" below).
- Add an inline log to `kb.metrics.ext_info` for each metric that is added or
  merged (see DR4 — metrics whose content is unchanged are not logged).
- Persist per DR4's dirty-check: in a single database transaction, INSERT
  metric_ids that are new and UPDATE (by `metric_id`) existing metric_ids
  whose content actually changed. Existing metric_ids whose content is
  unchanged are left untouched — not deleted, not rewritten.
- If the LLM call fails, retry once with the fallback model. If the fallback
  also fails, fail the processor run (leave `kb.metrics` untouched — the
  transaction above never begins).

##### Merge Resolution LLM Call

- model env: `METRIC_MERGE_RESOLVE_MODEL_NAME`
- fallback model env: `METRIC_MERGE_RESOLVE_MODEL_FALLBACK`
- prompt env: `METRIC_MERGE_RESOLVE_PROMPT`
- `temperature = 0`, `ThinkingType = "disabled"` — same rationale as the
  extraction passes (`extract-metrics-spec.md` §3.5): this is a structured
  classification decision, not open-ended reasoning, and we want the most
  deterministic behavior the model can give us since this call sits inside
  an otherwise-idempotent pipeline.

**Input** — pending list `L` (already deduped), every entry carrying a real
`metric_id` (existing entries keep their persisted ID; new entries are
pre-assigned one per DR3/DR4 before this call) and a `source` flag marking
whether it came from the existing table or the current run's extraction:

```json
{
  "input_record_id": "string",
  "candidates": [
    {
      "metric_id": "173_mtc_4",
      "source": "existing",
      "metric_name": "...",
      "metric_subject": "...",
      "metric_unit": "...",
      "metric_value": "...",
      "value_data_type": "...",
      "value_range_type": "...",
      "value_class": "...",
      "threshold_or_target": "...",
      "metric_categories": ["..."],
      "source_line_spans": ["12", "13:15"]
    },
    {
      "metric_id": "173_mtc_9",
      "source": "new",
      "metric_name": "...",
      "...": "same fields as above"
    }
  ]
}
```

**Prompt (draft, `METRIC_MERGE_RESOLVE_PROMPT`):**

```text
SYSTEM:
You resolve ambiguous metric duplicates for a document metrics database.
You are given a list of metric candidates extracted from the same input
document. Every candidate in the list shares at least one source line with
another candidate in the list (directly or through a chain of shared lines).
Some of these candidates describe the exact same real-world metric — for
example, the same measurement extracted twice by an earlier pass, or
re-extracted with minor wording differences on a later run. Others are
genuinely distinct metrics that happen to share a line, such as two
different measurements reported in the same table row.

For each candidate, decide which other candidates (if any) describe the same
metric. Group candidates that describe the same metric together. A candidate
that describes a distinct metric from all others forms its own group of one.

Do not merge two candidates only because they share a line — merge them only
if they describe the same underlying metric (same subject, same measured
value or threshold, same unit, same intent). When in doubt, prefer keeping
candidates separate (favor precision over recall: a false merge silently
discards a real metric, while a missed merge just leaves a near-duplicate for
the next run to reconsider).

When merging a group, prefer field values from the candidate tagged
`"source": "existing"` when it is present and its values are still supported
by the source lines; otherwise use the newly extracted candidate's values.

USER:
<input_record_id>{{input_record_id}}</input_record_id>
<candidates>{{candidates_json}}</candidates>

Respond with JSON only, matching this schema:
{
  "winning_metrics": [
    {
      "metric_id": "string",
      "absorbed_metric_ids": ["string"],
      "metric_name": "string",
      "metric_subject": "string",
      "metric_unit": "string",
      "metric_value": "string",
      "value_data_type": "string",
      "value_range_type": "string",
      "value_class": "string",
      "threshold_or_target": "string",
      "metric_categories": ["string"],
      "source_line_spans": ["string"]
    }
  ]
}
```

Rules:
- Every input `metric_id` must appear exactly once across the output: either
  as a winning entry's own `metric_id`, or inside some winning entry's
  `absorbed_metric_ids`.
- A candidate that is a distinct metric from all others is its own winning
  entry, with `absorbed_metric_ids: []` and its fields echoed verbatim.
- When multiple input candidates describe the same metric, they collapse
  into one winning entry: `metric_id` is the ID of whichever absorbed
  candidate had `"source": "existing"` (lowest-seqno if more than one
  existing candidate is absorbed); `absorbed_metric_ids` lists every other
  input `metric_id` that was folded in (including any other existing IDs, so
  downstream code can detect and reconcile that rarer case). If no absorbed
  candidate was `"source": "existing"`, `metric_id` is the lowest-seqno `new`
  ID among them (the other new IDs it absorbed are simply not used and can
  be reclaimed).
- `source_line_spans` for a winning entry that absorbed others is the union
  of all absorbed candidates' spans (same normalization as
  `normalizeSourceLineSpans`, `extract-metrics-spec.md` §3.3).

**Handling the response:**
- For each winning entry: if `metric_id` belongs to an existing candidate
  and the winning entry's fields are identical to what's already cached in
  memory for that `metric_id` (i.e. nothing changed), skip it entirely — no
  write, no `ext_info` log entry (see DR4's dirty-check).
- Otherwise, upsert the winning entry by `metric_id` (insert if new, update
  if existing-but-changed) and log it to `ext_info` (`"added"` if `metric_id`
  didn't previously exist, `"merged"` if `absorbed_metric_ids` is non-empty).
- Reject and fail the call (triggering the fallback-model retry) if any
  input `metric_id` is missing from the output, or appears in more than one
  place (as two different winners' IDs, or in two different
  `absorbed_metric_ids` lists, or both as a winner and absorbed elsewhere).

**Note about Idempotence:** The Context section states idempotence comes from
delete+reinsert of a deterministic extraction. Under DR2, reinsertion is no
longer of a fresh, fully-deterministic set (the Merge Resolution LLM call can
introduce run-to-run variance for ambiguous groups), so "idempotent" now means
something narrower: rows that aren't touched by an ambiguous merge keep
identical content and identical IDs across runs (DR3 below), and the table
transitions atomically between consistent states (see the transaction note in
DR2). It does not mean the LLM-adjudicated subset is guaranteed byte-identical
across repeated runs over unchanged input.

### DR3 - Artifact ID Stability
Currently, artifacts are identified by `<record_id>_<metric-specific-symbol>_<seqno>`,
where `<metric-specific-symbol>` is a three-letter string that uniquely identifies
the type of artifact, such as 'mtc' for metrics. 
`<seqno>` is a sequence number. This is the source of instability.

Solution (Proposal): 
- Retrieve all the metrics for a given input record id from the 
  artifact database table (such as `kb.metrics`)
- Find the max seqno from the retrieved records and set it to `NextSeqno`
- When adding a new artifact to the existing artifact list, assign 
  new artifact ID to it, with the `NextSeqno`, and increment `NextSeqno` by 1, 

### DR4 — Enrichment Scope and Dirty-Check for Merge Mode

`extract_metrics` runs as two LLM phases (`extract-metrics-spec.md` §3.1):
Pass 1 extracts candidates (coarse `*_hint` fields plus `source_line_spans`,
no normalized schema — §3.2), Pass 2 enriches candidates into the final
`kb.metrics` schema (`metric_subject`, `metric_unit`, `metric_value`, etc. —
§3.2, "Pass 2 output"). Rule-1's identity check needs the *enriched* fields,
which don't exist until after Pass 2 — Pass 1's hint fields are too coarse to
compare directly. This DR pins down what "enrich only the true new metrics"
means given that constraint, and requires changes to `extract-metrics.go`
beyond what DR2 already specifies.

**Enrichment scope.** When `force_clear=false`, existing metrics are loaded
directly from `kb.metrics` and used as-is — they are never re-enriched. Pass
2 enrichment runs only over this run's Pass-1 candidates (after the existing
intra-run dedup, `dedupeFinalMetricRows`, `extract-metrics-spec.md` §3.3).
This is what "true new metrics" refers to: the only LLM enrichment work done
in a merge-mode run is on this run's freshly extracted candidates, never on
anything already persisted. (Implementers should not read this as license to
skip enriching *any* new candidate before comparing it to existing metrics —
Rule-1 requires the enriched fields to even attempt the comparison. What's
being avoided is any re-derivation of the *existing* side.)

**`metric_id` pre-assignment.** Every new candidate that will end up in
`kb.metrics` needs a `metric_id` assigned via DR3's `NextSeqno` before it can
be written or compared by ID:
- Rule-3 survivors (no line overlap with anything existing) get a
  `metric_id` assigned immediately, no LLM involved.
- Pending-list `L` entries (Rule-4) get a `metric_id` assigned before being
  sent to the Merge Resolution LLM call, per DR2's updated "Merge Resolution
  LLM Call" input contract above — every entry in `L`, existing or new,
  carries a real `metric_id`, and the LLM's output references `metric_id`s
  directly (not an ephemeral per-call label).
- Both draw from the same `NextSeqno` counter for the record, incremented
  per assignment, so Rule-3 and Rule-4 assignments in the same run never
  collide.

**Dirty-check.** A metric is "dirty" — and therefore written and logged to
`ext_info` — only if its final content (after Rule-1/2/3/4) differs from
what was loaded from `kb.metrics` at the start of the run, or if it's a
`metric_id` that didn't exist before this run. Concretely:
- An existing metric untouched by any candidate this run (no new candidate
  overlapped or matched it) is never dirty — trivially skipped.
- Rule-2 (new candidate exactly matches an existing metric): the existing
  metric is not modified — skip it, no write, no log entry.
- A Rule-4 winning entry whose `metric_id` is existing and whose fields are
  identical to what's cached in memory for that ID: skip it, no write, no
  log entry, even though it went through the LLM call (the LLM may
  legitimately echo a candidate back unchanged).
- Everything else that survives merging (Rule-3 additions, and Rule-4
  winning entries that are new or that actually changed) is written
  (INSERT if new, UPDATE by `metric_id` if existing-and-changed) and logged
  to `ext_info` per DR2's persistence step.

This replaces DR2's earlier "delete all + insert all" description of the
persistence step with the more surgical insert/update-only-what's-dirty
approach now specified there.

### Alternative Decisions

**Semantic (not just line-overlap) identity check — deferred, not adopted.**
As discussed in "Motivating Observation" above, Rule-3/Rule-4 route purely on
whether `source_line_spans` overlaps an existing metric, which misses
same-metric duplicates whose spans drift slightly between runs. A stronger
identity check would additionally compare metrics whose spans are *near*
(e.g. within a small line-distance window) via semantic similarity over
`metric_name`/`metric_subject`/`metric_value`, not just exact overlap. Not
adopting this now because it adds another LLM/embedding call to the merge
path before we have evidence boundary-drift duplication is common enough to
justify it. Revisit if the validation experiment (see "Motivating
Observation") shows metric count growing without recall growing.

**Ensemble-within-a-single-run instead of merge-across-runs — deferred, not
adopted.** Rather than relying on separate manual re-runs merged over time
via DR2, the processor could run extraction N times (or at higher
temperature with self-consistency voting) within one invocation and dedupe
once via the existing `dedupeFinalMetricRows` pass (`extract-metrics-spec.md`
§3.3) before ever persisting. This would capture the same "different
randomness catches different misses" benefit without needing cross-run ID
accounting (DR3) or repeated transactional replace (DR2). Not adopted here
because it changes the cost/latency profile of every run (N LLM passes
instead of 1) rather than only paying that cost when a user deliberately
asks for a re-run; worth reconsidering once the harness mentioned under DR1's
staleness note is scoped.

### Database Migrations

Task 3's migration `project_migrations/20260711000001_add_kb_metrics_unique_constraint.sql`
was added during implementation:

- A dedupe DELETE pass (removing rows where `(input_record_id, metric_id)` was
  duplicated, keeping the lowest `id`) followed by a partial unique index
  `CREATE UNIQUE INDEX IF NOT EXISTS idx_metrics_input_metric_id ON kb.metrics(input_record_id, metric_id) WHERE metric_id IS NOT NULL`.
- This index serves as the `ON CONFLICT` target for `UpsertMetrics` in the
  merge-path code — without it, `INSERT ... ON CONFLICT (input_record_id, metric_id)`
  has no constraint to conflict against.

Other ADR migrations confirmed as unnecessary:
- `kb.metrics.ext_info JSONB` already existed; no column was needed.
- `force_clear` is an event-payload field, not a DB column.
- `kb.doc_proc_logs.entry_type` — the existing `CHECK` constraint already
  accepted all the entry_type values used during implementation; no migration
  needed there either.

### Data Formats

**Event payload** (`kb.line-file-generated`, parsed in `event.go`) gains one
new optional field, sitting alongside the existing `record_id`, `force`,
`operation`/`operations`, `filename`, `type`, `status`:

```json
{
  "record_id": "...",
  "force": true,
  "force_clear": false,
  "operation": ["extract_metrics"]
}
```

`force_clear` defaults to `false` when omitted (see DR1).

**`kb.metrics.ext_info` inline merge log** — DR2/DR4 require logging only the
metrics that were actually added or merged (dirty). Metrics skipped by DR4's
dirty-check (Rule-2 duplicates, or Rule-4 winners identical to the cached
existing row) get no log entry. Append to a `merge_log` array inside the
existing `ext_info` JSONB, one entry per dirty metric per run:

```json
{
  "merge_log": [
    {
      "run_time": "2026-07-11T00:00:00Z",
      "action": "added" | "merged",
      "absorbed_metric_ids": ["173_mtc_9"]
    }
  ]
}
```

`action`: `"added"` — new metric with no existing overlap (Rule-3) or a
Rule-4 winning entry that didn't correspond to any existing `metric_id`;
`"merged"` — a Rule-4 winning entry that changed an existing metric's
content or absorbed one or more other candidates.
`absorbed_metric_ids` is only present for `"merged"` entries and lists the
other `metric_id`s (per DR2's updated Merge Resolution LLM Call output) that
were folded into this one.

**Merge Resolution LLM Call request/response** — see the JSON schemas
already specified under DR2 § "Merge Resolution LLM Call" above; not
repeated here.

### Environment Variables

| Variable | Purpose | Default |
|---|---|---|
| `METRIC_MERGE_RESOLVE_MODEL_NAME` | Model used for the Merge Resolution LLM call (DR2) | none, required |
| `METRIC_MERGE_RESOLVE_MODEL_FALLBACK` | Fallback model if the primary call fails | none, optional |
| `METRIC_MERGE_RESOLVE_PROMPT` | Prompt template env, see DR2 draft prompt | none, required |

## Implementation

### Implementation Notes

**Path correction:** The ADR's Decisions were written assuming `HandleEvent` is
the live code path for doc processors. During implementation, it was discovered
that `HandleEvent` is dead code on the actual production path: the
`chunk_batch_coordinator.go` (`runPhaseBProcessors` / `runProcessorsChunkBatched`)
routes through `InitChunkBatch` → `ProcessChunk` (per-chunk) →
`FinalizeChunkBatch` for any processor implementing `ChunkBatchProcessor` (which
all four processors this ADR covers do), and neither that coordinator nor any of
those methods checked `evt.Force` before this ADR. `HandleEvent`'s documented
force/skip logic was therefore never reached on the live path, and every re-run
silently appended duplicates regardless of `force`. All DR1-DR4 logic was
accordingly implemented in `InitChunkBatch`/`ProcessChunk`/`FinalizeChunkBatch`,
using `docProcessorFlagsFromContext` to thread `force`/`force_clear` through a
context value (the `ChunkBatchProcessor` interface's signatures don't carry the
raw event). `HandleEvent` was left untouched.

**Rule-4 field reconstruction:** During Task 11's review, a live-path data-loss
bug was found in the ADR's own design: the Merge Resolution LLM's
`winning_metrics` response schema (prompt-merge-resolve-metrics-v1.md) carries
only ~10 fields (metric_name, metric_subject, metric_unit, metric_value, ...),
but `UpsertMetrics` does `ON CONFLICT DO UPDATE SET` on every column. A Rule-4
merged winner written directly from that sparse LLM output would silently blank
`metric_desc`, `metric_context`, `metric_keywords`, `location_type`,
`formula_or_definition`, `measurement_frequency`, `category_paths`, and all
`*_en` variants on the existing row. Fixed by reconstructing each winner's full
row from its source data in the pending group (already in memory) and overlaying
only the ~10 fields the LLM actually decided on, preserving everything else
unchanged (DR4 clean-check semantics).

### Code Changes

- `ChenWeb/server/api/doc-processing/event.go` (~lines 37-44): parse new
  `force_clear` field into the event struct, defaulting to `false`.
- `ChenWeb/server/api/doc-processing/extract-metrics.go` (~lines 337-353):
  restructure the `if evt.Force { delete } else { check exists, skip }`
  branch so that, on any path that actually runs extraction, a further branch
  on `evt.ForceClear` selects wipe (today's `DeleteMetricsByInputRecordID`,
  line ~2161) vs. merge (new code, below).
- New functions in `extract-metrics.go` (naming indicative, not final):
  - `loadExistingMetrics` — reads current `kb.metrics` rows for the record
    into memory as-is (DR4: never re-enriched).
  - `computeMetricGroups` — connected components / union-find over line-span
    overlap, across existing + newly extracted metrics (DR2 "Metric Groups").
  - `mergeMetrics` — Rule-1 through Rule-4.
  - `nextMetricSeqno` — DR3's max-seqno lookup and increment; called both for
    Rule-3 survivors and, before `resolveMergeAmbiguities`, for pending-list
    `L`'s new entries (DR4).
  - `resolveMergeAmbiguities` — the Merge Resolution LLM call, including
    primary/fallback model retry and response validation (DR2 "Handling the
    response").
  - `writeDirtyMetrics` — diffs the merge result against what
    `loadExistingMetrics` returned; INSERTs new `metric_id`s and UPDATEs
    changed ones by `metric_id` inside one transaction; skips anything
    identical to what was loaded (DR4 dirty-check). Replaces a blind
    delete-all-then-insert-all.
- `ChenWeb/server/api/doc-processing/extract-provisions.go`,
  `extract-inventory-items.go`, `extract-entity-relation.go`: accept
  `force_clear` in the event but always take the existing wipe branch,
  ignoring the flag's value (per the Scope note and DR1) until their own
  merge-rule ADRs land.
- `ChenWeb/web/src/lib/components/home3/doc-processor-dashboard-view.svelte`
  (`doLaunch`, ~lines 444-468): add a `force_clear` control independent of
  the existing run-mode toggle that sets `force`, and include it in the
  `POST /api/v1/jetstream/events` payload.

## Operational Behaviors 

- Log, per run of `extract_metrics`: which branch was taken (skip / wipe /
  merge), counts entering DR2 (existing count, newly-extracted count,
  skipped-not-dirty, added, merged, discarded-as-duplicate), and whether the
  Merge Resolution LLM call fired, on which model (primary/fallback), and its
  latency — following the existing logging conventions in
  `doc-processor-log-spec.md`/`kb.doc_proc_logs`.
- If the Merge Resolution LLM call fails on both primary and fallback model,
  fail the processor run and leave the previous `kb.metrics` rows untouched
  (per DR2) — surfaces the same way any other processor failure does today
  (`kb.inputs.status`, `kb.events`).
- No new alerting is proposed here; failure is visible through existing
  processor-failure status/logging. Revisit if the validation experiment
  under "Motivating Observation" shows this failure mode is frequent enough
  to need its own signal.

## Consequences

**Positive:**
- Manual re-runs of `extract_metrics` no longer risk orphaning downstream
  review state (`kb.doc_review_findings.artifact_id`,
  `kb.doc_review_provision_analyses`, `kb.artifact_connections`) that is
  keyed off `metric_id`, because DR3 keeps IDs of unchanged/merged metrics
  stable.
- Automatic pipeline runs accumulate rather than always wipe, which may
  improve coverage over time (see "Motivating Observation" for the caveat).
- `force` (skip-if-already-done) keeps its current meaning; no behavior
  change for existing automation that only ever sets `force`.
- DR4's dirty-check means an unchanged metric is never rewritten on a merge
  run — no wasted UPDATE, no churn of the underlying `id BIGSERIAL` primary
  key (`extract-metrics.go:2096`) for rows nothing touched, and no noise in
  `ext_info.merge_log` for rows that didn't actually change.

**Negative / risks:**
- Adds one more LLM call (Merge Resolution) to the metrics pipeline for any
  record with overlapping candidates, with associated latency and cost.
- Boundary-drift duplicates (same real metric, non-overlapping
  `source_line_spans` across runs) are not caught by this design — see
  "Motivating Observation" and the deferred semantic-identity-check
  alternative. Until validated, repeated automatic merging could silently
  accumulate near-duplicate metrics.
- The insert/update transaction (DR4's `writeDirtyMetrics`) holds a lock on
  the record's affected `kb.metrics` rows for the duration of the merge;
  scope is a single `input_record_id` and only its dirty rows, so contention
  is expected to be limited to concurrent runs of the same record (not
  otherwise guarded against here).
- Partial rollout: `extract_provisions`, `extract_inventory_items`, and
  `extract_entity_relation` accept `force_clear` but ignore it, which means
  a caller who sets `force_clear=false` for one of those three still gets a
  full wipe — this needs to be visible in the frontend (e.g. disable/label
  the control for those processors) so it isn't mistaken for a bug.

## Tests

- **Rule-1 equality:** two candidates identical on all five fields are
  recognized as the same metric (Rule-2) regardless of field order/casing
  normalization already applied upstream.
- **Rule-3 (no overlap):** a new metric whose line span doesn't overlap any
  existing metric is added without invoking the Merge Resolution LLM call.
- **Rule-4 (overlap) + Metric Groups transitive closure:** a chain of three
  metrics A–B–C where A overlaps B and B overlaps C, but A and C don't
  directly overlap, all land in the same pending list `L` (regression test
  for the single-hop bug this ADR fixes).
- **DR3 seqno assignment:** adding a new metric after some existing metrics
  have been deleted (leaving gaps in seqno) assigns `NextSeqno` from the
  current max, not by filling gaps; merged/kept metrics retain their
  original `metric_id`. Also verify Rule-3 assignment and pending-list `L`
  assignment (DR4) draw from the same counter without colliding when both
  happen in the same run.
- **Enrichment scope (DR4):** existing metrics loaded via `loadExistingMetrics`
  are never passed through Pass 2 enrichment; only this run's Pass-1
  candidates are.
- **Merge Resolution LLM call:** mock a well-formed response (every input
  `metric_id` accounted for exactly once, across winners and
  `absorbed_metric_ids`) and malformed responses (missing `metric_id`,
  `metric_id` appearing in two places) and confirm the malformed case
  triggers the fallback-model retry, and that exhausting both fails the
  processor run without touching `kb.metrics`.
- **Dirty-check (DR4):** an existing metric untouched by any candidate this
  run, a Rule-2 exact-duplicate case, and a Rule-4 winning entry identical to
  its cached existing row all produce zero writes and zero `ext_info` log
  entries; a Rule-4 winning entry that actually changed content produces
  exactly one UPDATE and one log entry.
- **Transaction atomicity:** simulate a failure mid-`writeDirtyMetrics` and
  confirm already-committed dirty rows are rolled back together (all-or-
  nothing for the run), while untouched rows were never part of the
  transaction to begin with.
- **`force`/`force_clear` combinations:** the four cases in DR1 (skip;
  wipe-and-run; merge-and-run; first-run) each produce the expected branch.
- **Non-metrics processors:** `extract_provisions`/`extract_inventory_items`/
  `extract_entity_relation` accept `force_clear` in the payload without error
  and always take the wipe branch regardless of its value.

## Documentation Impact

- `extract-metrics-spec.md`: cross-reference this ADR from §3.3 ("Final
  Metric Dedup") and §3.7 ("Metric ID"), since DR2/DR3 change what happens to
  `kb.metrics` after that point when `force_clear=false`.
- `doc-processor-log-spec.md` / `doc-processor-log-impl.md`: document the new
  Merge Resolution LLM call logging fields, and the `kb.doc_proc_logs.entry_type`
  question flagged under Database Migrations.
- Event payload schema docs for `kb.line-file-generated` (wherever that's
  documented today, if anywhere outside `event.go` itself): add `force_clear`.
- Frontend user-facing copy/tooltip for the new `force_clear` control in
  `doc-processor-dashboard-view.svelte`, including the partial-rollout caveat
  above for the three non-metrics processors.
- This ADR's own Change Log, updated below.

## Plan
Refer to [2] for the plan generated by `superpowers` skill.

## References
[1] KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md

[2] KnowledgeStore/doc-repo/plan/202607/2026071103-plan-doc-processor-incremental-metrics.md