# Auto-Promoted Governed Terms Implementation

**Date:** 2026-08-12 \
**Status:** Implemented \
**Component:** ChenWeb — `kb.ontology_terms`/`kb.ontology_term_labels` (schema), `server/api/ontology/{keywords,names,terms,comparison}/`, `server/api/doc-processing/extract-metrics.go` \
**Authors:** Chen Ding (with Claude)

## Change Logs

* 2026/08/12, document created, at implementation completion.

## Purpose

This document records the implementation completed for **auto-promoted governed terms** —
making `kb.ontology_terms` `metric_definition` rows creatable automatically, without human
review gating whether a metric ever gets a governed identity.

It complements:

- ADR `2026081201` — `KnowledgeStore/doc-repo/adrs/202608/2026081201-adr-auto-promoted-governed-terms.md`
  (the decision record; DR1–DR6)
- OpenSpec change — `ChenWeb/openspec/changes/auto-promoted-governed-terms/` (proposal, design,
  specs, tasks — all 27 tasks complete)

It focuses on:

- what was implemented, and how DR1–DR6 map to code
- two real bugs found and fixed during implementation that the ADR did not anticipate
- a real schema gap found and closed
- what was verified, including a live sample-check run against real production data
- what was intentionally left out of scope

## Summary

ADR `2026081201` decided that creating a `metric_definition` governed term must become
automatic rather than human-gated, because the prior design — a low-recall LLM harvester
(`extract_metric_definitions`) feeding a curator-review queue — could never scale to the
volume of distinct metrics a real deployment produces, and in practice had produced **zero**
`metric_definition` terms in the live database.

This change makes every metric resolve to a governed term automatically:

```
extracted metric
  -> resolve metric_name via the keyword module (tiers 0-6, unchanged)
      -> match an existing kb.keyword_concepts row, or auto-create one (D11, already built)
  -> resolve concept_id to a governed kb.ontology_terms term
      -> an accepted aligns_to_term assertion already exists -> use it (already built)
      -> none exists -> auto-create a new metric_definition term (NEW) and align to it
```

The new term gets `status = 'auto-promoted'` — live and usable immediately, distinguished
from curator-released `included_in_release` only for future attribution/sampling, never as
a usage gate. `extract_metric_definitions` is retired from the default pipeline (code kept,
not deleted).

## DR1–DR6 → Implementation

### DR1 — Concept→term resolution

`AlignmentsStore.EnsureAcceptedOrCreate` (`server/api/ontology/keywords/alignment.go`):
checks `AcceptedForConcept` first (existing-alignment branch is byte-for-byte
`EnsureAccepted`'s); on miss, inserts a new `kb.ontology_terms` row + prefLabel/altLabel
rows + the `aligns_to_term` assertion, all inside one `withKeywordIdentityMutation`
transaction (the same Postgres advisory lock `EnsureAccepted`/`MergeConcept` already use —
verified concurrency-safe live, see Verification). `term_id` is derived as
`"measurement:" + conceptID` — folding the already-deduplicated concept id directly
into the term id (not slugifying the label) guarantees 1:1 uniqueness with no collision
race. The lifecycle state is represented by `ontology_terms.status`, not embedded in the
stable identifier, so later promotion does not leave an `auto` marker in user-visible IDs.

No tier 0–6 fuzzy matching runs in this step — a `concept_id` is already a deduplicated
identity, so the only question left is existence, not similarity.

### DR2 — `auto-promoted` status

Migration `20260812000001_add_auto_promoted_to_ontology_terms_status.sql` widens
`ontology_terms_status_check`. `terms.AllowedTermStatuses` (`terms_store.go`) — a Go-side
exhaustive map `CreateTerm` validates against independently of the DB CHECK — updated to
match. Precedent: this mirrors ADR `2026072901`'s 2026-08-09 "keyword-catalog
auto-promotion" entry, which already shipped the same "autonomous, clearly flagged,
optionally human-reviewed" pattern one layer down, at the concept level.

### DR3 — Structural term synthesis

`keywords.TermSynthesisInput` (`CanonicalName`, `Aliases`, `Definition`, `ValueType`,
`RangeType`, `PermittedUnitTermIDs`) is populated in `ResolvingMetricsStore.resolveAll`
(`extract-metrics.go`) from the triggering metric row's own already-extracted fields
(`formula_or_definition`, `value_data_type`, `value_range_type`, `metric_unit`) — no new LLM
call. Unit resolution reuses existing governed-label-exact-match logic via a new exported
`(*names.Resolver) MatchUnitLabel`, wrapping the previously-private `matchLabelToReleasedTerm`
— not the `canonicalUnitForm`/`unitQuantityKindMap` workaround maps spec `2026080403` §17.2
already flags as not a pattern to copy.

**Schema gap found and closed.** `kb.ontology_terms` had no columns at all for
`value_type`/`range_type`/`permitted_units` — ADR `2026072901` §3.24 described them as part
of a term's content, but `candidates/promote.go`'s `promoteTerm` never actually persisted
them (only `definition`/`scope` survive candidate promotion today). Migration
`20260812000002_add_synthesis_fields_and_label_status.sql` adds `value_type TEXT`,
`range_type TEXT`, `permitted_unit_term_ids JSONB` (nullable, additive) plus the
corresponding `terms.Term` struct fields and all three `TermStore` INSERT sites
(`CreateTerm`/`CreateTermVersion`/`insertTermChunk`); no behavior change for existing
callers (QUDT import, candidate promotion), which simply leave the new fields at zero value.

### DR4 — Comparison-matrix acceptance

`ComparisonStore.validateMetricKey` (`comparison/store.go`) now accepts
`status IN ('included_in_release', 'auto-promoted')` — still rejects
draft/in_review/approved/rejected/superseded and non-`metric_definition` kinds.

### DR5 — Failure rate managed, not avoided

`status='auto-promoted'` is itself the sampling flag DR5 requires (queryable as a set). No
sampling/review UI was built (remains open, ADR §5 OD4). A real sample check was run against
production data as part of verification (below) rather than synthetic fixtures, to get an
honest first read on the fragmentation question DR5 raises.

### DR6 — Retirement

**No code or pipeline-data change was needed.** Verified against the live `miner` database
that `extract_metric_definitions` was already excluded from both active `kb.pipelines` rows'
`processors[]` arrays, has no `kb.pipeline_rules` gate, and its `ProcessorSpec` already
declares `OnUndetermined: "skip"` (`processor_plan.go`). The capsule doc
(`extract-metric-definitions-spec.md`) and `+CAPSULE.md` were updated to document this state
explicitly rather than leave it implicit; the processor's code, tests, and prompt are
untouched and it remains selectable via explicit `operation`/Dev Mode.

## Two Real Bugs Found and Fixed

Neither was anticipated by the ADR; both were caught by testing against a real (non-mock)
`miner` database rather than trusting prior documentation or mocks alone.

### 1. `names.Resolver.ResolveAndObserve` discarded its own write-path result

Spec `2026080403`'s own status notes claimed `KEYWORD_RESOLVER_MODE=on` was unusable ("K7":
enabling it disables collection). That claim did not reproduce — `"observe"` and `"on"`
behaved identically in every live test. The **actual** bug: `KeywordFamily.ObserveOccurrence`
auto-creates a provisional concept on a targeted deferred/human_review miss and sets it on
its own return value (`*semid.Resolution.ResolvedNodeID`), but `ResolveAndObserve` discarded
that return value (`_, err := r.Family.ObserveOccurrence(...)`). Confirmed live: a concept
was genuinely written to `kb.keyword_concepts` (`status='provisional'`,
`gloss_source='auto:d11'`) while the caller's returned `NameResolution` still reported
`status=unresolved`, `concept_id=""`. Without this fix, DR1 could never fire for a metric
name seen for the first time — in practice, almost every metric name, since
`kb.keyword_concepts` had zero document-sourced concepts before this change.

**Fix:** `server/api/ontology/names/resolver.go` — `ResolveAndObserve` now captures
`ObserveOccurrence`'s return value and fills in `res.ConceptID`/`Status`/`Method`/
`Confidence` whenever the read pass left them empty, never overriding an existing
term/concept hit. No prior test covered this path — a genuine coverage gap, not a broken
contract (`go test ./server/api/ontology/names/...` was clean before and after).

### 2. The alignment released-guard rejected the very terms DR1 creates

`AlignmentsStore.ensureAccepted`'s "released guard" (`releasedTermExistsSQL`) hardcoded
`status = 'included_in_release'`. A freshly auto-created term has `status = 'auto-promoted'`
— so aligning a concept to a term `EnsureAcceptedOrCreate` had just created would always fail
with "not a released term," making the whole function self-defeating. Caught by a passing
sqlmock unit test whose mock unrealistically returned `true` for the guard — the mock didn't
reflect what the real SQL would actually return, which only the live-DB check surfaced.

**Fix:** `server/api/ontology/keywords/alignment.go` — `releasedTermExistsSQL` widened to
`status IN ('included_in_release', 'auto-promoted')`. `names/resolver.go`'s separate
`releasedTermSQL` (a different call site: matching a raw name string to a governed label)
intentionally stays `included_in_release`-only, consistent with DR1's "no fuzzy matching on
the term-creation path."

## Main Code Changes

### 1. Schema

- `project_migrations/20260812000001_add_auto_promoted_to_ontology_terms_status.sql` —
  widens `kb.ontology_terms.status` CHECK.
- `project_migrations/20260812000002_add_synthesis_fields_and_label_status.sql` — adds
  `value_type`/`range_type`/`permitted_unit_term_ids` to `kb.ontology_terms`; widens
  `kb.ontology_term_labels.status` CHECK for the same new value.

Both applied live automatically (the running air-managed dev server re-runs goose migrations
on file-triggered rebuild); verified via `pg_get_constraintdef` against `miner`.

### 2. `server/api/ontology/keywords/alignment.go`

- New `TermSynthesisInput` struct.
- New `AlignmentsStore.EnsureAcceptedOrCreate` (DR1).
- New `autoPromotedTermID` helper.
- `releasedTermExistsSQL` widened (bug fix #2).

### 3. `server/api/ontology/names/resolver.go`

- `ResolveAndObserve` fixed to propagate `ObserveOccurrence`'s result (bug fix #1).
- New exported `(*Resolver) MatchUnitLabel`.

### 4. `server/api/ontology/terms/{terms_store.go,nullable.go}`

- `Term` struct gains `ValueType`/`RangeType`/`PermittedUnitTermIDs`.
- `AllowedTermStatuses` gains `"auto-promoted"`.
- `termColumns`/`scanTerm`/`CreateTerm`/`CreateTermVersion`/`insertTermChunk` updated for
  the 3 new columns.
- `nullable.go` gains `nullableStringArray`/`scanStringArray` (JSONB string-array helpers).

### 5. `server/api/ontology/comparison/store.go`

- `validateMetricKey` accepts `auto-promoted` (DR4).

### 6. `server/api/doc-processing/extract-metrics.go`

- `nameResolver` interface: `ResolveNames` (read-only) → `ResolveAndObserve` +
  `MatchUnitLabel` (write-aware — required, since D11 auto-creation is a write-path-only
  effect).
- New `termAligner` interface.
- `ResolvingMetricsStore` gains an `Alignments` field.
- `resolveAll` rewritten: per-name `ResolveAndObserve`; on concept-without-term, builds a
  `TermSynthesisInput` from the representative metric row and calls
  `EnsureAcceptedOrCreate`.
- `newResolvingMetricsStore` wires the shared `AlignmentsStore` into both `Resolver` and the
  new `Alignments` field.

### 7. Documentation

- `KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-metric-definitions-spec.md`
  — marked retired (top-of-file notice), pointing to ADR `2026081201`.
- `+CAPSULE.md` — pipeline table row 14, §7.1's routed-processor sentence, §9.11 heading.
- ADR `2026081201` — status line, changelog entry, §6 Implementations filled in.

## Tests

New/updated, by package:

- `keywords/alignment_test.go` — `TestAlignmentsStoreEnsureAcceptedOrCreateReusesExisting`,
  `TestAlignmentsStoreEnsureAcceptedOrCreateAutoCreatesTerm`.
- `doc-processing/extract-metrics_test.go` — `scriptedNameResolver`/`scriptedTermAligner`
  updated to the new interfaces;
  `TestResolvingMetricsStoreAutoPromotesTermWhenConceptHasNone`,
  `TestResolvingMetricsStoreSkipsAutoPromoteWhenAlreadyTermResolved` added; 6 pre-existing
  `ResolvingMetricsStore` tests unmodified in behavior.
- `comparison/store_test.go` — `TestComparisonStoreValidateMetricKeyAcceptsAutoPromoted`
  added; existing rejection-case test's fixtures widened for the new columns, assertions
  unchanged.
- `terms/terms_store_test.go`, `candidates/promote_test.go` — existing sqlmock fixtures
  widened for the 3 new `kb.ontology_terms` columns (mechanical, no behavior change).

## Verification

```bash
cd ChenWeb
go build ./...
go vet ./...
go test ./...
```

Results:

- `go build`/`go vet` clean across the entire workspace.
- `go test ./...`: every package touched by this change passes, including the new tests
  above. Three pre-existing failing packages unrelated to this change were found during the
  sweep (`kbhandler`, `llmusage`, `server/cmd/qudt-import`) — none of their files appear in
  this change's diff. Traced `kbhandler`'s failure to a different, earlier commit
  (`2bc393c4`, "ontology-candidate-dedup") that added `kb.ontology_candidates.identity_key`
  without updating a handler test's mock fixture; `llmusage`'s is a hardcoded-date temp-path
  assertion; `qudt-import`'s is a turtle-fixture parsing issue. Not fixed here — out of
  scope for this change.

### Live verification against real data (not mocks)

Three separate live checks were run against the real `miner` database over the course of
implementation, each writing scratch/real data and (for the first two) cleaning up
afterward:

| Check | Method | Result |
|---|---|---|
| Resolver-mode behavior (prerequisite for DR1) | Direct calls to `ResolveName`/`ResolveAndObserve` against real concepts/terms, `observe` vs `on` | Modes identical (contradicts spec `2026080403`'s "K7" claim); found bug #1 |
| Concurrency safety (DR1 step 3) | Two real concurrent goroutines calling `EnsureAcceptedOrCreate` for the same never-before-seen concept | Exactly 1 term created, exactly 1 accepted alignment — advisory lock holds |
| DR5 sample check | All 55 real, distinct metric names already extracted for `kb.inputs.id=416`, through the real code path | 0 of 55 converged: 55 distinct concepts and terms, including three genuine near-synonyms for "germination index" (植物种子发芽指数 / 种子发芽指数 / 发芽指数) that each got their own row |

The DR5 result is reported as observed, not smoothed over: within-document fragmentation is
real and immediately visible with this change alone. It is expected given the architecture
— tiers 0–4 (the online matching path) are exact/near-exact matchers; the fuzzy/semantic
convergence that would catch near-synonyms is tier 5/6, and tier 6 (embedding-based) is an
**offline** reconciliation pass (`cmd/keyword-reconcile`) that was not run as part of this
change. Whether reconciliation actually closes this gap is a real, separate, unverified
question this implementation does not answer. The 55 real concepts/terms created during this
check were left in place (genuine output against a real document, not scratch noise) — three
smaller scratch verifications (resolver-mode check, concurrency check) used synthetic
test-only names and were cleaned up (concepts, surfaces, occurrences, terms, labels,
alignments deleted).

## Documentation Impact

Documents that reflect or are affected by this implementation:

- ADR `2026081201` — this document mirrors its DR1–DR6 and records the same two bugs; the
  ADR's own §6 has the same Implementations content in decision-record form.
- ADR `2026072901` — §3.24 (DR23) carries an inline 2026-08-12 correction blockquote and a
  changelog entry pointing here; its "domain has hundreds of metrics" scale claim is
  retracted as unfounded (no formal definition of "domain" exists anywhere in the code or
  ADR).
- `extract-metric-definitions-spec.md` / `+CAPSULE.md` — updated to reflect the processor's
  retirement from default selection (§7 above).
- Spec `2026080403` (keyword canonicalization) — its D9 status table's "K7" characterization
  of `KEYWORD_RESOLVER_MODE=on` is contradicted by this implementation's live testing;
  **not edited by this change** (out of scope — flagged here for whoever next touches that
  spec).

## Recommended Follow-up

- Decide whether `cmd/keyword-reconcile` (offline tier-5/6 reconciliation) should run against
  the 55 real terms this change's verification created, to get an actual answer to the DR5
  fragmentation question the sample check surfaced but did not resolve.
- Turn `KEYWORD_RESOLVER_MODE` on in a real (non-scratch) environment when ready to rely on
  this for production Document Review comparisons — it remains off by default; this change
  did not alter that default.
- A sampling/review UI for `auto-promoted` terms remains unbuilt (ADR §5 OD4) — the same gap
  ADR `2026072901` already flagged for candidate review generally.
- Whether `extract_metric_definitions`'s output should later enrich an already-auto-promoted
  term's `definition` field with real document text, when available, is a plausible
  follow-on (ADR §5 OD3) not designed or built here.
- Fix the three pre-existing failing packages found during the `go test ./...` sweep
  (`kbhandler`, `llmusage`, `server/cmd/qudt-import`) — unrelated to this change, still
  broken.
