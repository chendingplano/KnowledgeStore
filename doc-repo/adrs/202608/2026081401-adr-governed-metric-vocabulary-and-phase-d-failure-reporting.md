# ADR 2026081401 — Governed, DB-Backed Metric Vocabulary Mapping and Phase D Failure Reporting

**Date:** 2026-08-14 \
**Status:** Implemented \
**Component:** ChenWeb — `kb.metrics`, `kb.semantic_decision_candidates`, `kb.inputs`, `kb.doc_proc_logs`, `server/api/ontology/assertions/{metric_normalizer.go,associate_semantics.go}`, `server/api/doc-processing/{phase_d.go,control.go,doc_proc_log_store.go,extract-metrics.go}` \
**Authors:** Chen Ding (with Claude) \
**Related:** ADR `2026081201` (auto-promoted governed terms — precedent pattern), ADR `2026072901` §8 DR8 (Phase D stage declaration), commit `56b6` (interim hardcoded-synonym stopgap this ADR supersedes) \
**Tags:** ontology, metric normalization, doc processor status, kb.doc_proc_logs, governed vocabulary, Phase D

## 1. Change Logs

* 2026/08/14, ADR created, from a same-day investigation that started as "what does
  `no_governed_assertion_kind_term:unparsed` mean" and ended with a production data survey
  (309 distinct `kb.metrics.value_range_type` strings across 7,036 rows) plus a code-level
  finding that Phase C post-process-indexing errors — including `associate_semantics`'s —
  never reach `kb.inputs.status` at all today, for any processor.
* 2026/08/14, added DR6: move detection from `associate_semantics` (Phase D, potentially much
  later, even a separate enable/disable cycle) to `extract_metrics` itself (Phase C, immediately
  after extraction), which auto-proposes the map entry and flags the specific `kb.metrics` row
  instead of only being visible three stages downstream. Renamed DR1's `status` vocabulary from
  `unmapped`/`mapped` to `proposed`/`approved` to match — a proposal can now carry a best-effort
  guessed `canonical_bucket` for a human to confirm or correct, not just a bare unclassified
  string.
* 2026/08/14, implemented via OpenSpec change `ChenWeb/openspec/changes/governed-metric-vocabulary-mapping/`
  (proposal/design/specs/tasks). All decisions (DR1-DR6) shipped as designed, with one deviation
  from §8's literal call-site plan: `DocProcLogger.LogAssertionMappingMiss` is called from
  `associate_semantics`'s call site in `phase_d.go` (`AssociateSemanticsProcessor.PostProcessIndex`),
  not from inside `assertions.AssociateSemantics.Run` itself — `server/api/ontology/assertions`
  cannot import `server/api/doc-processing` (the reverse import already exists, e.g.
  `phase_d.go`/`extract-metrics.go`), so `Run` only returns `AssociateReport.MappingMisses` and
  the aggregate error; the one call site that already has both the report and a `DocProcLogger`
  does the logging. `extract_metrics`'s own DR6 call site needed no such change (same package as
  `DocProcLogger`). Full test suite (unit + the `ValueRangeTypeMapper`/`AssociateSemantics.Run`/
  `runPostProcessIndexing`/`MetricsProcessor.checkValueRangeTypeMappings` coverage §11 calls for)
  passes; `go build ./...`/`go vet ./...` clean across the workspace. User manual bumped to a new
  `metric-assertion-semantic-processing-v1.2-en.md` file (this KnowledgeStore's one-file-per-version
  convention — v1.1 left unmodified).
* 2026/08/15, §7's "no admin UI" open question closed: the "Resolve Metric Range Types" admin page
  (System Admin → Database Maintenance) shipped via `ChenWeb/openspec/changes/resolve-metric-range-types/`,
  in the shape §7 anticipated — a triage list for `status != 'approved'` rows with a canonical-bucket
  approve/correct action, mirroring "Resolve Ambiguous Objects". Applying a correction sets the entry
  to `approved` and clears `value_range_type_error` on every already-flagged `kb.metrics` row sharing
  that `raw_value`; it does not itself re-run `normalize_assertions`/`associate_semantics` — a later
  backlog-drain pass is still what produces the accepted `kb.semantic_assertions` row (see §7's third
  bullet, still applicable). Formalized as its own decision record + implementation record: ADR
  `2026081501` and Implementation `2026081501`
  (`KnowledgeStore/doc-repo/{adrs,impl}/202608/2026081501-{adr,impl}-resolve-metric-range-types-admin-page.md`).

## 2. Context

### 2.1 The immediate problem: a hardcoded, closed vocabulary meeting an open one

`kb.metrics.value_range_type` is populated by an LLM extractor (`extract_metrics`) as free
text, not a constrained enum. A production survey found **309 distinct strings across 7,036
rows**. `resolveMetricValue` / `CanonicalMetricValueRangeType`
(`server/api/ontology/assertions/metric_normalizer.go:222-253`, current form as of commit
`56b6`) recognize only a hardcoded Go `switch` of synonyms for four canonical buckets
(`lower_bound`/`upper_bound`/`exact`/`range`, plus two special-case value forms
`qualitative`/`limit_absent`). Any `value_range_type` string outside that set — regardless of
whether `metric_value` holds a perfectly clean number — falls through to the terminal
`value_form='unparsed', assertion_kind='unparsed'` result (`metric_normalizer.go:343`).
`associate_semantics.go:316-318` then defers any such candidate with reason
`no_governed_assertion_kind_term:unparsed`, and because that reason is deferred via
`deferCandidate` (fingerprint = the reason string itself, `associate_semantics.go:530-531`,
not a fingerprint of external state), **it never self-resolves via the existing backlog drain**
(`backlog_drain.go`) — the only two ways forward are a normalizer code change or a data fix.

Commit `56b6` (same day, prior to this ADR) added ~30 more synonyms found in the survey as a
Go-code stopgap. That closed the seven-row gap observed in one sample run, but the underlying
architecture problem remains: **every future LLM phrasing drift requires a Go code change and
a redeploy**, the full 309-string vocabulary is invisible except via ad-hoc SQL, and there is
no way for an operator to see, triage, or fix a new unmapped string without reading the Go
source.

### 2.2 The reporting problem: associate_semantics' "success" status is not real

Traced independently, and worse than assumed going in:

- `AssociateSemanticsProcessor.HandleEvent` (`server/api/doc-processing/phase_d.go:74`) is a
  hardcoded no-op: `func (...) HandleEvent(context.Context, []byte) error { return nil }`.
  Every processor runs through the Phase A/B loop first
  (`runSingleProcessorCollect`, `control.go:1154-1203`), and because `HandleEvent` trivially
  succeeds, `control.go:1200` writes `persistProcessorRuntimeStatus(ctx, recordID,
  "associate_semantics", "success", "")` into `kb.inputs.status` **before the real work has
  even run**. This is the exact write that produced the `{"operation":"associate_semantics",
  "proc_status":"success"}` entry observed for input record 416, which had 25 deferred
  candidates that run.
- The real work happens later, in Phase C, via `AssociateSemanticsProcessor.PostProcessIndex`
  (`phase_d.go:79-85`): `_, err := (assertions.AssociateSemantics{DB: ...}).Run(ctx,
  recordID); return err`. The `AssociateReport{Examined, Accepted, Deferred, Rejected}` return
  value is discarded at this call site; only `err` propagates, and `Run` never returns a
  non-nil error for ordinary deferrals (correctly — a deferred candidate is not itself a
  processor failure today).
- Phase C's harness, `runPostProcessIndexing` (`control.go:1051-1134`), calls
  `indexer.PostProcessIndex` for every `PostProcessIndexer` and, on error, **only logs
  (`s.Logger.Error(...)`, `control.go:1117`) and records an OTel span** — it never calls
  `persistProcessorRuntimeStatus` or touches `kb.inputs.status`. This is true for **every**
  Phase C processor, not just `associate_semantics` — confirmed by reading every
  `PostProcessIndex` implementation in the codebase (scene blocks, summaries, topics,
  provisions, entity/relation, product structure, metrics, inventory items, semantic
  projections, and all three Phase D processors). None of them can make `kb.inputs.status`,
  `pipeline_state`, or `has_failed_proc` reflect a Phase C failure today.
- Consequence: the existing failed-processor retry mechanism
  (`ListRecordsWithFailedDocProcessors` → `WHERE has_failed_proc`,
  `extract-doc-metadata-store.go:120-138`, wired to `--all=failed-procs` in
  `control.go:296-374`) and the admin dashboard's per-processor status column
  (`doc-processor-dashboard-view.svelte`) are both structurally blind to any Phase C failure,
  including a `value_range_type` mapping miss, forever, regardless of what
  `associate_semantics` itself does — **the harness gap has to be fixed for any per-processor
  "failed" status to ever reach the places operators actually look.**

### 2.3 Precedent already in this codebase

ADR `2026081201` established a DB-backed, "auto-promoted but reviewable" governance pattern
for ontology vocabulary: `kb.ontology_candidates` (proposal/staging, `fingerprint`-deduped) and
`kb.ontology_terms` (governed, versioned, with a `status` progression that includes
`'auto-promoted'` — usable immediately, flagged for optional later review, not gated on human
sign-off). That two-table split exists because ontology terms have a real versioned identity
(`term_id` + `version`) and rich content (definitions, scope, module binding). A
`value_range_type` synonym mapping has neither — it is a flat lookup from an observed string to
one of a small, fixed set of existing buckets — so this ADR adopts the same *governance
philosophy* (auto-discover, don't silently guess, make the backlog queryable, allow
uncontroversial entries to resolve without blocking a human) without replicating the two-table
machinery built for a different-shaped problem (see §3.6, Alternative Decisions).

## 3. Decision

### 3.1 DR1 — Replace the hardcoded switch with a governed database table

New table `kb.metric_value_range_type_map`:

| Column | Type | Notes |
|---|---|---|
| `raw_value` | `text` PK | Normalized the same way `CanonicalMetricValueRangeType` already does today: lowercased, trimmed, `-`/` ` → `_`. |
| `canonical_bucket` | `text`, nullable | One of `lower_bound`/`upper_bound`/`exact`/`range`/`qualitative`/`limit_absent`. `NULL` while unclassified, but may already be non-`NULL` on a `'proposed'` row — see DR6, which lets the proposer suggest a bucket rather than only flagging the bare string. |
| `status` | `text` NOT NULL DEFAULT `'proposed'` | `'proposed'` (auto-inserted on first sighting, `canonical_bucket` may be a best-effort guess or `NULL`; not yet authoritative) / `'approved'` (a human confirmed or corrected `canonical_bucket`; in active use) / `'ambiguous'` (a human reviewed it and decided no bound direction can be inferred — e.g. `threshold`, `target`, `tolerance`, `ratio`; stays `unparsed` by design, same as today, but as a recorded decision instead of an implicit code gap). Only `'approved'` rows are used to classify a metric; `'proposed'` and `'ambiguous'` both leave the metric `unparsed`, but only `'proposed'` is a failure condition (DR3, DR6) — `'ambiguous'` is a settled, non-alarming outcome. |
| `occurrence_count` | `bigint` NOT NULL DEFAULT 0 | Incremented on each observed use; the discoverability/prioritization signal this ADR's own investigation had to reconstruct by hand via SQL. |
| `first_seen_record_id`, `last_seen_record_id` | `bigint`, nullable | |
| `note` | `text`, nullable | Human triage rationale, e.g. why a string was marked `ambiguous`. |
| `create_by`, `create_time`, `modify_by`, `modify_time` | audit columns, consistent with `kb.ontology_terms`/`kb.ontology_candidates` convention | |

`CanonicalMetricValueRangeType`'s Go switch is replaced by a lookup against this table (via a
small in-process cache — full-table, short TTL or invalidate-on-write; the table is small by
construction and read on every metric row normalized, so a per-call DB round trip is not
acceptable). A lookup miss (raw value not present in the table at all) auto-inserts a row with
`status='proposed'`, `occurrence_count=1`; a repeat hit on an existing `'proposed'` or
`'ambiguous'` row increments `occurrence_count` and updates `last_seen_record_id` without
inserting a duplicate (`raw_value` is the primary key). This is the "auto-discover" half of the
auto-promoted-terms philosophy: nothing is silently ignored, and nothing requires a human in the
loop before it can be *seen*. DR6 moves the primary point of first sighting from this lazy,
`normalize_assertions`-time lookup to an eager check inside `extract_metrics` itself — this
lookup path remains as the fallback that catches anything DR6 doesn't (legacy rows, backlog
drain reprocessing, or any future writer of `kb.metrics` that bypasses `extract_metrics`).

### 3.2 DR2 — Log a `kb.doc_proc_logs` entry on a mapping miss

New `entry_type` value `'assertion_mapping_miss'`, chosen as a family-level name (not
`metric_`-prefixed) because the identical hardcoded-free-text-vocabulary shape exists for
`kb.metrics.value_class` today (not fixed by this ADR — see §7 Open Questions) and will recur
for provisions' modality vocabulary as that normalizer matures; one entry type serves the whole
assertion-normalization family rather than needing a new enum value per artifact type.

Written once per input record per `associate_semantics` run (not once per candidate, to avoid
log spam on a document with many rows sharing one unmapped string — the per-string occurrence
count already lives durably in `kb.metric_value_range_type_map`), via a new
`DocProcLogger.LogAssertionMappingMiss` helper mirroring the existing per-entry-type method
pattern (`doc_proc_log_store.go:137-313`, e.g. `LogResolveMetric`). Fields: `record_id`,
`doc_proc_name='associate_semantics'`, `entry_type='assertion_mapping_miss'`, `errors` (human
summary), `extra_info` JSONB (`{"family":"metric.value_range_type","raw_values":[...],
"count":N}`).

### 3.3 DR3 — `associate_semantics` fails only on `'proposed'`, not on `'ambiguous'` or ordinary deferrals

Not every deferral should become a processor failure — most of today's deferrals
(`unresolved_referent`, `governed_term_not_released`, a candidate whose source metric never had
a number, or a `value_range_type` explicitly triaged `'ambiguous'`) are expected, already-modeled
outcomes with their own recovery path (backlog drain, term release), exactly as documented in
`metric-assertion-semantic-processing-v1.1-en.md` §9. Only a `'proposed'` lookup — vocabulary
nobody has looked at yet — represents an operational gap worth alarming on.

`normalize_assertions`' `MetricNormalizer` (the caller of the DR1 lookup) tags the candidate's
`proposed_payload` with the lookup outcome (`value_range_type_lookup:
"approved"|"ambiguous"|"proposed"|"absent"` — `"absent"` covers the legacy path where
`value_range_type` was empty/NULL to begin with, which is not a mapping problem and must not
trigger a failure). `AssociateSemantics.processMetric`, on hitting `!supported` today
(`associate_semantics.go:316-318`), reads this tag: `"proposed"` increments a new
`AssociateReport.MappingMisses` counter (alongside the existing `Deferred` counter — the
candidate still ends up `deferred`, unchanged from today); any other value leaves today's
behavior untouched. After processing all candidates, `AssociateSemantics.Run` returns a non-nil
aggregate error when `MappingMisses > 0` (e.g. `fmt.Errorf("associate_semantics: %d
candidate(s) blocked on ungoverned vocabulary awaiting review", n)`), alongside the
fully-populated report — the report is not replaced by the error, both are returned as today's
signature already allows (`(AssociateReport, error)`).

With DR6 in place, most `"proposed"` rows this stage encounters will already have been raised
once by `extract_metrics` on the same record (see DR6) — this is intentional, not a duplicate
bug: a proposal a human hasn't approved yet is still not usable, so both stages correctly keep
signaling failure until it's approved. `associate_semantics` remains the necessary backstop for
anything DR6 didn't catch (§3.1's fallback note).

### 3.4 DR4 — Fix the Phase C harness so `PostProcessIndex` failures reach `kb.inputs.status`

`AssociateSemanticsProcessor.PostProcessIndex` already does the right thing
(`return err`, `phase_d.go:84`) — the gap is entirely in the shared harness. Extend
`runPostProcessIndexing` (`control.go:1111-1119`) to call
`s.persistProcessorRuntimeStatus(ctx, recordID, name, "failed", err.Error())` in the existing
`if err := indexer.PostProcessIndex(...); err != nil` branch, mirroring the pattern already
used by `runSingleProcessorCollect` for Phase A/B (`control.go:1165-1178`). This is a
harness-level fix, not something scopeable to `associate_semantics` alone — there is no
per-processor hook into this shared loop — and it is a strict improvement for every
`PostProcessIndexer`: today none of them can ever report a Phase C failure into
`kb.inputs.status`/`pipeline_state`/`has_failed_proc`, so this closes the same gap for all of
them uniformly, which is exactly what "treat `associate_semantics` as a real doc processor,
same as `extract_metrics`" requires — `extract_metrics` does its status-relevant work in
`HandleEvent` (Phase A/B, already wired), and the Phase D stages will now get the equivalent
guarantee for the phase they actually run in.

Once DR4 lands, DR3's non-nil `Run` error already propagates correctly through the existing
`PostProcessIndex` → `runPostProcessIndexing` chain with no further plumbing — DR3 and DR4 are
independent fixes that compose through code paths that already exist today.

One deliberate non-change: `ProjectSemanticsProcessor.logAssociationRunReport`
(`phase_d.go:121-153`) already intentionally swallows its own report-build failure (logged, not
returned — see its comment at `phase_d.go:118-120`) so that a telemetry-query error never masks
a successful Phase D run. That function does not return an error today and is unaffected by
DR4.

### 3.5 DR5 — Rollout: seed the table so cutover does not cause a failure storm

If `kb.metric_value_range_type_map` starts empty, every one of the 309 surveyed strings not in
commit `56b6`'s Go synonym list would register as `'proposed'` on first use post-cutover — for
high-volume ambiguous strings (`threshold` 376 rows, `discrete` 143, `categorical` 122,
`ordinal` 63, `continuous` 61, `binary` 51, `tolerance` 35, `ratio` 24, `target` 22, and dozens
more) this would flip a large fraction of the corpus's `associate_semantics` (and, post-DR6,
`extract_metrics`) runs to `'failed'` simultaneously — a false-alarm storm, not a genuine
new-vocabulary signal. The creation migration must seed two sets of rows:

1. Every synonym currently recognized by commit `56b6`'s Go switch, as `status='approved'` with
   the matching `canonical_bucket` — preserves current behavior exactly on cutover.
2. Every string identified in this investigation as direction-ambiguous (the list in §2.1's
   survey and `TestResolveMetricValueLeavesAmbiguousVocabularyUnparsed`) as `status='ambiguous'`
   — preserves today's silent-defer outcome for these instead of manufacturing new failures.

Any of the 309 surveyed strings not covered by either seed set (the long tail below the
count-5 cutoff used in commit `56b6`, plus anything genuinely never triaged) legitimately starts
`'proposed'` — that is the intended new signal this ADR is for.

### 3.6 DR6 — Detect at extraction time, not three stages later: `extract_metrics` auto-proposes and self-fails

DR3 catches a mapping miss at `associate_semantics` — but that is Phase D, which can run long
after extraction (a separate pipeline stage, gated by its own `SEMANTIC_ASSOCIATION_ENABLED`
flag, potentially re-enabled or re-run on a different day than the extraction that produced the
metric). The raw `value_range_type` string is already fully known the moment `extract_metrics`
produces it — there is no reason to wait three stages to notice it doesn't match anything
governed. DR6 moves detection to where the information first exists:

- `MetricsProcessor.PostProcessIndex` (`extract-metrics.go:754-789`, Phase C — the same phase
  DR4 fixes generally) now runs every `kb.metrics` row it just wrote for this record through the
  same DR1 lookup `normalize_assertions` uses. Extraction and persistence of `kb.metrics` rows
  themselves are **unchanged** — every extracted metric is written exactly as it is today,
  successfully mapped or not; DR6 only adds a check *after* that, over what's already persisted.
- **On a miss**, `extract_metrics` does three things, not just one:
  1. Auto-inserts (or updates the `occurrence_count`/`last_seen_record_id` of) a
     `kb.metric_value_range_type_map` row with `status='proposed'` (DR1) — attempting a
     best-effort `canonical_bucket` guess where a cheap heuristic applies (e.g. a `≥`/`≤`/"at
     least"/"no more than"-style direction cue already present in the raw string or the row's
     `value_class`/`threshold_or_target`, reusing the same keyword cues
     `parseThresholdOrTarget` already recognizes) — `canonical_bucket` stays `NULL` when no such
     cue exists. Either way the row is `'proposed'`: a bucket present is a suggestion to
     confirm, not a decision.
  2. Sets a new `kb.metrics.value_range_type_error` column (`TEXT`, `NULL` when fine) on that
     specific row to a short message (e.g. `"unmapped value_range_type: 'single'"`) — so the
     affected metric is directly identifiable on the artifact/evidence table itself, without
     joining through `kb.semantic_decision_candidates` or the mapping table.
  3. Accumulates a per-record miss count. At the end of `PostProcessIndex`, if any misses
     occurred, it writes one `kb.doc_proc_logs` row (`entry_type='assertion_mapping_miss'` —
     reusing DR2's entry type with `doc_proc_name='extract_metrics'` instead of
     `associate_semantics`, no new entry type needed) and returns a non-nil aggregate error.
- **That error fails `extract_metrics` itself**, by the same DR4 harness fix — no separate
  plumbing needed. `extract_metrics` already reports real `success`/`failed` status for its
  `HandleEvent` (Phase B, per-chunk) work via `persistMetricsStatus`
  (`extract-metrics.go:928-950`); DR6's `PostProcessIndex` write happens later in the same run
  (Phase C follows Phase B) and reuses the same `operation="extract_metrics"` name, so
  `kb.sync_input_proc_status`'s existing latest-write-wins reduction
  (`ORDER BY s.proc, s.ord DESC`, `project_migrations/20260609000002_add_kb_inputs_status_rollups.sql`)
  makes the Phase C mapping-check outcome the record's authoritative `extract_metrics` status —
  a clean chunk-extraction pass followed by an unmapped-vocabulary miss correctly ends as
  `failed`, matching "then it fails `extract_metrics`."
- **Ordering requirement**: `NormalizeAssertionsProcessor` gains
  `PostProcessDependsOn() []string { return []string{"extract_metrics"} }` (mirroring the
  existing `associate_semantics → project_semantics` dependency chain,
  `phase_d.go:75-77,100-102`) so `runPostProcessIndexing`'s dependency scheduler
  (`control.go:1086-1098`) guarantees DR6's proposal/flag pass has finished before
  `normalize_assertions` reads the same rows — without this, the two Phase C goroutines could
  race, and `normalize_assertions` could read a `kb.metrics` row before its
  `value_range_type_error` flag or its `kb.metric_value_range_type_map` proposal exists.
- **Human review workflow**: a person reviewing `status='proposed'` rows (§7's open question on
  an admin surface) either approves (`status='approved'`, `canonical_bucket` confirmed as-is),
  corrects (`status='approved'`, `canonical_bucket` overwritten to the right value), or settles
  it as permanently ambiguous (`status='ambiguous'`). None of these steps touch the already-
  persisted `kb.metrics` rows or their `value_range_type_error` flag directly — the flag records
  what was true at extraction time; re-running the backlog drain (existing mechanism, unchanged)
  after approval is what actually produces an accepted assertion for the previously-flagged
  metrics.

### 3.7 Alternative Decisions

- **Two-table `candidates`/`terms` split (ADR 2026081201's exact shape) — rejected for this
  problem.** Considered for consistency, but that split exists to manage versioned term
  *identity and content*; a synonym mapping is a flat string→bucket fact with no versioning
  need. A single table with a `status` column carries the same "don't silently guess, make it
  queryable, allow non-blocking resolution" philosophy with less machinery. Revisit if this
  table's scope grows to include richer content than a bucket assignment.
- **Log one `kb.doc_proc_logs` row per deferred candidate — rejected.** A document with many
  metrics sharing one unmapped string would spam the log table for zero additional information;
  the per-string `occurrence_count` in `kb.metric_value_range_type_map` already carries that
  detail durably. One summary row per record per run is enough to alert and to link back to the
  affected record.
- **Scope DR4 to `associate_semantics` only (e.g. a special call path bypassing the shared
  harness) — rejected.** `runPostProcessIndexing` has no per-processor hook; special-casing one
  processor would mean either duplicating the harness or adding a branch keyed on processor
  name, both worse than fixing the shared loop once. The fix is a strict improvement with no
  identified downside for the other Phase C processors (see DR4's note on
  `ProjectSemanticsProcessor`).
- **Detect only at `associate_semantics` (DR3 alone, no DR6) — rejected.** Would leave the
  signal three stages later than the information is available, and — because Phase D is
  independently gated by `SEMANTIC_ASSOCIATION_ENABLED` — possibly never surfaced at all for a
  deployment running with that flag off, even though `extract_metrics` itself ran and already
  had everything needed to flag the row. DR6 does not replace DR3; it makes DR3 a backstop
  instead of the only line of defense.
- **Have `extract_metrics` silently skip/omit unmappable metrics rather than persisting them —
  rejected**, per the user's explicit requirement: every extracted metric is persisted exactly
  as today regardless of mapping outcome, only flagged. Dropping evidence because it couldn't be
  classified would be strictly worse than today's behavior, not a fix.

## 4. Database Migrations

1. `project_migrations/<ts>_create_kb_metric_value_range_type_map.sql` — `CREATE TABLE
   kb.metric_value_range_type_map` per §3.1, plus the DR5 seed `INSERT`s (approved synonyms +
   ambiguous strings).
2. `project_migrations/<ts>_add_assertion_mapping_miss_entry_type.sql` — widen
   `kb.doc_proc_logs_entry_type_check` to add `'assertion_mapping_miss'`, following the same
   drop/recreate pattern as `20260814000001_add_resolve_metric_entry_type.sql`.
3. `project_migrations/<ts>_add_kb_metrics_value_range_type_error.sql` — `ALTER TABLE kb.metrics
   ADD COLUMN value_range_type_error TEXT` (DR6), nullable, additive, no backfill required
   (`NULL` for every existing row is the correct historical value — DR6 only flags rows it
   itself processes going forward).

## 5. Data Formats

- `kb.semantic_decision_candidates.proposed_payload` for metric candidates gains one field:
  `value_range_type_lookup: "approved" | "ambiguous" | "proposed" | "absent"` (§3.3). Existing
  consumers of `proposed_payload` that don't know this field are unaffected (additive).
- `kb.metrics` gains `value_range_type_error TEXT` (DR6, §4.3): `NULL` when the row's
  `value_range_type` resolved to an `'approved'` mapping (or was legitimately absent); a short
  human-readable message when `extract_metrics` found no `'approved'` mapping at extraction
  time. Not reset retroactively by a later human approval — see DR6's human-review-workflow
  note.

## 6. Environment Variables

None new. The in-process lookup-table cache (§3.1) needs no operator-facing configuration —
fixed short TTL, invalidated on write, is sufficient given the table's small size.

## 7. Open Questions / Future Work (explicitly out of scope here)

- `kb.metrics.value_class` shows the same LLM-free-text shape (`valueClassAssertionKind` in
  `metric_normalizer.go` is a small hardcoded map against an apparently much larger observed
  vocabulary) but was not surveyed or scoped into this ADR — worth its own investigation before
  deciding whether it reuses `kb.metric_value_range_type_map`'s pattern or needs its own table.
- ~~No admin UI is proposed here for triaging `status='proposed'` rows~~ **Resolved 2026-08-15**:
  the "Resolve Metric Range Types" admin page (System Admin → Database Maintenance) now lists
  `kb.metrics` rows with a `value_range_type_error`, shows the DR6 best-effort `canonical_bucket`
  guess on the corresponding `kb.metric_value_range_type_map` entry, and lets an operator
  approve/correct it in the same shape as "Resolve Ambiguous Objects" — see ADR `2026081501` /
  Implementation `2026081501`, `ChenWeb/openspec/changes/resolve-metric-range-types/`, and §1's
  2026/08/15 changelog entry.
- Retrying a record whose `extract_metrics` or `associate_semantics` failed on a `'proposed'`
  string will fail identically until the string is approved in the table — the retry mechanism
  (§2.2) is necessary but not sufficient; triage has to happen first.
- DR6's heuristic bucket-guessing (a lightweight rule reused from `parseThresholdOrTarget`'s
  direction keywords) is deliberately unspecified in detail here — it only ever produces a
  `'proposed'` suggestion, never an authoritative classification, so getting it wrong has low
  cost. Worth its own design pass if the approve/correct ratio in practice turns out lopsided
  enough to be worth improving.

## 8. Implementation (Code Changes — implemented 2026-08-14, see §1 changelog)

- `server/api/ontology/assertions/metric_normalizer.go` — replace `CanonicalMetricValueRangeType`
  with a DB-backed lookup type (e.g. `ValueRangeTypeMapper`), cached; `resolveMetricValue` tags
  `proposed_payload` per §3.3.
- `server/api/ontology/assertions/associate_semantics.go` — `AssociateReport` gains
  `MappingMisses int`; `processMetric` branches on the payload tag; `Run` returns a non-nil
  aggregate error when `MappingMisses > 0`. **As implemented:** the
  `DocProcLogger.LogAssertionMappingMiss` call itself lives in
  `server/api/doc-processing/phase_d.go`'s `AssociateSemanticsProcessor.PostProcessIndex`, not
  inside `Run` — `assertions` cannot import `docprocessing` (the reverse import already exists),
  so `Run` only surfaces `MappingMisses`/the error, and the one call site that already has both
  the report and a `DocProcLogger` performs the log write.
- `server/api/doc-processing/doc_proc_log_store.go` — `EntryTypeAssertionMappingMiss` constant,
  `LogAssertionMappingMiss` helper, add to `allowedDocProcLogEntryType`.
- `server/api/doc-processing/control.go` — `runPostProcessIndexing`
  (`control.go:1111-1119`): call `persistProcessorRuntimeStatus(..., "failed", err.Error())` on
  `PostProcessIndex` error.
- `server/api/doc-processing/extract-metrics.go` — `MetricsProcessor.PostProcessIndex`
  (`extract-metrics.go:754-789`, DR6): run the DR1 lookup over this record's just-persisted
  `kb.metrics` rows; on a miss, upsert the `kb.metric_value_range_type_map` proposal (with
  best-effort bucket guess), `UPDATE kb.metrics SET value_range_type_error = ...` for that row,
  accumulate a count, and — if any misses occurred — call
  `DocProcLogger.LogAssertionMappingMiss` (`doc_proc_name='extract_metrics'`) and return a
  non-nil aggregate error.
- `server/api/doc-processing/phase_d.go` — `NormalizeAssertionsProcessor` gains
  `PostProcessDependsOn() []string { return []string{"extract_metrics"} }` (DR6 ordering
  requirement).
- Three new migrations per §4.

## 9. Operational Behaviors

- A record with any `'proposed'` `value_range_type` string now shows `extract_metrics` (DR6,
  first) and, if it still hasn't been approved by the time Phase D runs, `associate_semantics`
  (DR3, backstop) as `failed` in the admin dashboard, and `kb.inputs.has_failed_proc=true` —
  becoming a target of `--all=failed-procs` batch retry (§2.2). See §7's note that approval must
  happen first or the retry repeats the same failure.
- The specific affected metrics are directly visible on `kb.metrics.value_range_type_error`
  (DR6) — an operator does not need to cross-reference `kb.semantic_decision_candidates` or
  `kb.doc_proc_logs` to find which rows in a given document were flagged.
- A `kb.doc_proc_logs` row (`entry_type='assertion_mapping_miss'`, `doc_proc_name` identifying
  which stage raised it) gives a durable, queryable audit trail of which records hit which
  unmapped strings and when.
- Records using only `'approved'` or `'ambiguous'` vocabulary see no behavior change from today
  post-DR5 seeding.

## 10. Consequences

**Benefits:** new LLM phrasing drift becomes a data-fix (approve/correct one row) instead of a
code change and redeploy; the 309-string vocabulary (previously invisible outside ad-hoc SQL)
becomes queryable and prioritizable by `occurrence_count`; `extract_metrics` and
`associate_semantics` (and, as a side effect of DR4, every other Phase C processor) gain real
failure visibility for the first time, plugging directly into the existing retry and dashboard
infrastructure with no new surfaces to build; DR6 surfaces the problem at the earliest possible
point (extraction time) instead of only after a potentially much-later, independently-gated
Phase D run, and keeps every extracted metric persisted regardless of mapping outcome, exactly
as today.

**Risks:** the in-process cache means a just-approved mapping is not instantly visible to an
in-flight or very-recently-started run — acceptable given documents are not reprocessed
instantly anyway, but worth confirming the chosen TTL against real operator workflow
expectations. Incorrect DR5 seeding (missing an ambiguous string) would cause a one-time false
failure storm on cutover, now doubled in visibility (both `extract_metrics` and
`associate_semantics` would flag it) — the seed list must be generated from the same
survey/test data this ADR cites, not re-derived by hand. DR6 adds a per-record DB round trip
(or batch of them) to `extract_metrics`'s Phase C step that didn't exist before — expected to be
cheap given the table's small size and the in-process cache, but not yet measured against a
large-batch extraction run.

## 11. Tests

- Unit: `ValueRangeTypeMapper` hit (`approved`)/miss (`proposed`, auto-insert)/`ambiguous` paths;
  `occurrence_count`/`last_seen_record_id` update behavior on repeat miss.
- Unit: `AssociateSemantics.Run` returns non-nil error and `MappingMisses > 0` when a candidate
  carries `value_range_type_lookup: "proposed"`; returns nil error for `"ambiguous"`/`"absent"`
  with a normal `Deferred` count, matching today's behavior.
- Unit (DR6): `MetricsProcessor.PostProcessIndex` on a record with one unmappable
  `value_range_type` — asserts a `kb.metric_value_range_type_map` row was proposed, the specific
  `kb.metrics` row got `value_range_type_error` set, and `PostProcessIndex` returned a non-nil
  error; a second run over the same record does not create a duplicate proposal row (dedup via
  `raw_value` PK), only updates `occurrence_count`.
- Integration: seed a record with one unmapped `value_range_type`, run extraction through the
  Phase D chain, assert `kb.inputs.status` contains both `extract_metrics` and
  `associate_semantics` with `proc_status='failed'`, `kb.doc_proc_logs` has the corresponding
  `assertion_mapping_miss` rows, and `kb.input_proc_status`/`has_failed_proc` reflect it; then
  approve the proposal and confirm a drain re-run accepts the previously-blocked candidate.
- Regression: re-run `TestResolveMetricValueCanonicalizesProductionVocabularySurvey` and
  `TestResolveMetricValueLeavesAmbiguousVocabularyUnparsed` (from commit `56b6`) against the
  DB-backed mapper instead of the Go switch, seeded with the DR5 data, to confirm no behavior
  regression during cutover.

## 12. Documentation Impact

- `KnowledgeStore/doc-repo/user-manuals/metric-assertion-semantic-processing-v1.1-en.md` needs a
  new subsection under §5.1 (`extract_metrics`'s new Phase C mapping check, DR6) and §5.2
  (`associate_semantics`'s backstop) describing the `'proposed'` failure mode,
  `kb.metric_value_range_type_map`, `kb.metrics.value_range_type_error`, and the operator
  approve/correct workflow — bump to v1.2 with a Change Log entry.
- This ADR itself is the record of why `CanonicalMetricValueRangeType` moved out of Go code;
  commit `56b6`'s inline comment (`metric_normalizer.go:227-233`) should get a follow-up comment
  or removal once DR1 lands, since it will otherwise describe a mechanism that no longer exists.

## 13. References

- `KnowledgeStore/doc-repo/user-manuals/metric-assertion-semantic-processing-v1.1-en.md`
- ADR `2026081201-adr-auto-promoted-governed-terms.md` (governance-pattern precedent)
- ADR `2026072901-adr-ontology-platform-and-adaptive-pipeline.md` §8 DR8 (Phase D declaration)
- ChenWeb commit `56b6` ("fix: canonicalize more metric value_range_type synonyms; misc pipeline
  fixes") — the interim stopgap this ADR's DR1 supersedes
- `server/api/ontology/assertions/metric_normalizer.go`,
  `server/api/ontology/assertions/associate_semantics.go`,
  `server/api/doc-processing/phase_d.go`, `server/api/doc-processing/control.go`,
  `server/api/doc-processing/doc_proc_log_store.go`
