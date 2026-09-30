# Auto-promoted metric_definition terms conflate metric-only fields with the generic term schema and silently drop available data

Date: 2026-08-21

Status: findings 1-3 fixed 2026-08-22 (ChenWeb `1291bfd0`), plus a same-day
follow-up erratum fix and a new property-map extensibility feature — see
"Follow-up — 2026-08-22" below. Finding 4 (refresh-on-later-occurrence)
remains open, deferred by design. A same-day review of that property-map
feature (triggered by a proposal to add `kb.semantic_assertions.properties`)
surfaced findings 5-8 — class creation running in the wrong pipeline stage,
class/instance scope conflation in `properties`, un-normalized property
keys, and the agreed `qualifiers`-based resolution for
`kb.semantic_assertions` — see "Review — 2026-08-22 (round 2)" below.
Findings 5-8 implemented same-day via ChenWeb change
`fix-metric-property-scope-conflation` (openspec) — see "Implementation —
2026-08-22" below. Not yet verified end-to-end against a live database in
this environment; a new integration test covers it, pending a run with
`TEST_DATABASE_URL` set.

System: ChenWeb SemOS ontology — governed term schema and metric auto-promotion

Component: `kb.ontology_terms`, `extract_metrics`, auto-promotion (ADR 2026081201 DR1/DR3)

Related: `ChenWeb/server/api/ontology/keywords/alignment.go`,
`ChenWeb/server/api/ontology/terms/terms_store.go`,
`ChenWeb/server/api/doc-processing/extract-metrics.go`,
`ChenWeb/project_migrations/20260731000014_create_kb_ontology_terms.sql`,
`ChenWeb/project_migrations/20260818000009_create_ontology_term_identity_foundation.sql`.
Prior investigation: `202608/2026081901-bug-auto-promoted-ontology-labels-are-not-fully-usable.md`
(different defect in the same feature — label language and resolver visibility).

## Summary

Triggered by inspecting `kb.ontology_terms.term_id = 'measurement:kwc_bb95850b160d'`
(id 12952), an auto-promoted `metric_definition` term with an empty `definition`
and no unit. Tracing how ADR 2026081201's auto-promotion path
(`AlignmentsStore.EnsureAcceptedOrCreate`, `alignment.go:312-388`) populates
`kb.ontology_terms` surfaced three confirmed defects and one compounding
mechanism:

1. **`definition` is bound to the wrong upstream field and ignores a better one
   that already exists.** The auto-promoter writes `kb.metrics.formula_or_definition`
   into `kb.ontology_terms.definition`, but every other writer of that column
   (the curated seed vocabulary, QUDT/candidate promotion) uses it as a plain
   descriptive sentence of what the term *is* — and `kb.metrics.metric_desc`,
   which already holds exactly that kind of sentence, is never read.
2. **Metric-only attributes are flat columns on a schema shared by 8 term
   kinds.** `value_type`, `range_type`, `permitted_unit_term_ids` are only ever
   populated by this one code path; every other term kind, and every other
   producer of `kb.ontology_terms` rows, leaves them null. There is no
   general-purpose place to hold kind-specific structured properties.
3. **The metric's unit is silently dropped even when a governed match exists.**
   `permitted_unit_term_ids` is empty on the live row despite `kb.metrics.metric_unit
   = '%'` and a released `unit` term (`quantity:unit_PERCENT`, label `%`)
   existing in `miner`. There is no field anywhere on the term to retain the raw
   unit string when resolution doesn't populate it, so the information is not
   recoverable after the fact.
4. **(Compounding) auto-promoted terms are never refreshed after creation.**
   `EnsureAcceptedOrCreate` returns immediately once a concept already has an
   accepted alignment (`alignment.go:330-337`) — it never re-runs synthesis
   against a later, better-populated metric occurrence. Whatever the first
   metric row that ever triggered promotion for a concept looked like, that is
   what the term is stuck with permanently, even if the same document is
   reprocessed later with a fixed prompt or richer extraction. This makes
   fixes to (1)-(3) necessary but not sufficient on their own — new writes
   would be correct, but existing (and future first-observation) terms would
   still freeze on whatever the first pass captured.

## Evidence

Live row, `miner`:

```
term_id     | measurement:kwc_bb95850b160d
term_kind   | metric_definition
status      | auto-promoted
definition  |            <- empty
value_type  | numeric
range_type  | lower_bound
permitted_unit_term_ids |  <- empty
```

Source metric, `kb.metrics.id = 32325` (input_record_id 416, doc "农村生活垃圾分类处理规范"):

```
metric_name           | 有机质的质量分数（以烘干基计）
formula_or_definition |            <- empty (source stated a bare threshold, no formula/definition sentence)
metric_desc            | 肥料技术指标：有机质的质量分数（以烘干基计）应不低于30%。   <- descriptive, present, never read
metric_unit            | %
```

A released, unambiguous `unit` term for `%` exists and predates this term's
creation:

```
term_id | quantity:unit_PERCENT | status = included_in_release | label '%' (altLabel, en, included_in_release)
released 2026-08-09; auto-promoted term created 2026-08-19 13:26:23
```

`extract-metrics.go:253-267` only reads `formula_or_definition`,
`value_data_type`, `value_range_type`, and conditionally `metric_unit` (via
`MatchUnitLabel`, only assigned inside the `if unitTermID != ""` branch, no
fallback):

```go
synth := keywords.TermSynthesisInput{
    CanonicalName: name,
    Definition:    strings.TrimSpace(asString(rep["formula_or_definition"])),
    ValueType:     strings.TrimSpace(asString(rep["value_data_type"])),
    RangeType:     strings.TrimSpace(asString(rep["value_range_type"])),
}
if unit := strings.TrimSpace(asString(rep["metric_unit"])); unit != "" {
    if unitTermID, uerr := s.Resolver.MatchUnitLabel(ctx, unit); uerr == nil && unitTermID != "" {
        synth.PermittedUnitTermIDs = []string{unitTermID}
    }
}
```

`terms_store.go:30-33` self-documents the schema conflation:

```go
// ValueType, RangeType, PermittedUnitTermIDs (ADR 2026081201 DR3) are
// only ever set by the auto-promotion path today; every other caller
// (QUDT import, candidate promotion) leaves them empty, which persists
// as SQL NULL and changes nothing about their existing behavior.
```

Every other producer of `kb.ontology_terms.definition` uses it as a plain
descriptive sentence, not a formula (`seed/content.go`):

```go
{ID: "core:referent", Kind: "class", Def: "A canonical real-world or conceptual entity that SemOS tracks under governed identity."},
{ID: "core:assertion", Kind: "class", Def: "A qualified claim made by a source about a referent, normalized into governed predicates."},
```

The codebase already has precedent for a kind-specific JSON properties bag —
the QUDT importer stages `symbol`/`deprecated` as a JSON payload
(`terminology/qudt.go:265`, `map[string]any{"deprecated": ..., "symbol": ...}`)
— but that payload lives only in the terminology catalog staging tables and
never reaches `kb.ontology_terms`, so curated `unit`/`quantity_kind` terms have
the identical "nowhere to put kind-specific properties" gap as auto-promoted
`metric_definition` terms.

`EnsureAcceptedOrCreate`'s unconditional early return on an existing alignment
(`alignment.go:330-337`):

```go
existing, err := txStore.AcceptedForConcept(ctx, db, conceptID)
if err != nil {
    return err
}
if existing != nil {
    result = *existing
    return nil   // synth is discarded, term is never touched again
}
```

## Assessment of the three points raised

1. **Confirmed, but the fix is not a new `description` column.** The schema
   already has a field for this — `definition` — and every writer except this
   one uses it as intended. The defect is that the metric auto-promoter (a)
   binds it to a narrow field (`formula_or_definition`) that the extraction
   prompt itself documents as legitimately empty whenever "the source states
   only a value and no definitional content" (`prompt-enrich-metrics-v5.md:103`),
   and (b) never falls back to `metric_desc`, which is populated for this exact
   row and is descriptive prose of precisely the kind every other `definition`
   value contains. Adding a second column would leave the same bug in place
   under a different name; fixing the transcription to prefer/fall back to
   `metric_desc` (or concatenate) uses the schema as designed.
2. **Confirmed.** `value_type`, `range_type`, `permitted_unit_term_ids` are
   metric_definition-specific properties implemented as flat columns on a
   table shared by `class`, `property`, `individual`, `concept`,
   `metric_definition`, `quantity_kind`, `unit`, `dimension` — dead weight for
   the other seven kinds today, and the QUDT importer's already-collected
   `symbol`/`deprecated` payload shows the same need exists for `unit`/
   `quantity_kind` and has no home either. A `properties JSONB` column, keyed
   by convention per `term_kind`, replaces both the three ad hoc columns and
   the QUDT payload's dead end.
3. **Confirmed**, and worse than "sometimes doesn't resolve": there is no raw
   fallback field, so even a locally-correct `MatchUnitLabel` miss (unreleased
   unit, transient DB issue, a symbol form the exact-match resolver doesn't
   yet cover) destroys the original unit text permanently, with no way to
   recover it from `kb.ontology_terms` after the fact. In this specific row a
   governed match was available and unambiguous, so the loss did not even need
   an actual resolution failure to occur — see finding 4.

## Recommended resolution direction

Not implemented — this is a review/report, scoped for discussion before any
schema or code change:

- Change the auto-promotion synthesis to populate `definition` from
  `metric_desc` (falling back to `formula_or_definition`, or combining both)
  instead of `formula_or_definition` alone.
- No data repair for existing auto-promoted rows. Related data will be removed by
  running the script `ChenWeb/scripts/clear-artifact-data.sql`.
- Add `kb.ontology_terms.properties JSONB`; move `value_type`, `range_type`,
  `permitted_unit_term_ids` into it for new writes (note: no backfill for 
  existing columns since this bug report assumes existing data are cleared.
- Decide, separately, whether `EnsureAcceptedOrCreate` should refresh an
  existing auto-promoted term's synthesized fields when a later occurrence of
  the same concept carries richer data (e.g. only-if-currently-blank
  field-level backfill), since without this, fixing (1)-(3) only helps terms
  created after the fix ships.

## Follow-up — 2026-08-22

Findings 1-3 were implemented same-day via ChenWeb `1291bfd0` (`properties
JSONB` column, `metric_desc`-first definition sourcing, `raw_unit` retention
— see `openspec/changes/fix-auto-promoted-term-schema-loss/`). A live
re-run of `extract_metrics` against input_record_id 416 immediately after
that commit showed the fix had **not** actually taken effect: freshly
created rows (e.g. `measurement:kwc_bb95850b160d`, re-created same day)
still had `definition` empty and `properties` holding only `value_type`/
`range_type` — `raw_unit` and `permitted_unit_term_ids` were still missing
despite `kb.metrics.metric_unit` being non-empty for those rows. Root
cause and fix below; a second, requested capability (config-driven
property exposure) was implemented in the same pass.

### Erratum: `1291bfd0`'s fix read the wrong map key on a fresh extraction

`extract-metrics.go`'s `resolveAll` (the synthesis call site) reads its
representative metric row from the same `map[string]any` that is about to
be persisted. That map exists in one of two shapes, documented at
`metricFieldAliasPairs` (`extract-metrics.go:3774`, comment at :3760-3773):

- **"raw"** names (`desc`, `unit`, `subject`, `context`, `keywords`, ...) —
  what `normalizeMetricList` (pass-2 LLM output) produces, and what
  `SaveMetrics` receives untouched on a fresh/force-clear batch (the
  common case — "run extract_metrics against a document").
- **"canonical"** DB-column names (`metric_desc`, `metric_unit`, ...) —
  only present after `canonicalizeMetricFieldAliases` runs, which happens
  on the merge/upsert path (`mergeAndCollectDirtyMetrics`), not on a fresh
  batch.

`1291bfd0`'s fix read `rep["metric_desc"]` and `rep["metric_unit"]` — the
canonical names — but on a fresh batch (exactly the scenario in the
original bug's live row) the map only ever has `rep["desc"]`/`rep["unit"]`.
So `definition` still fell through to `formula_or_definition` (usually
also empty) and the unit block's `if unit := ...; unit != ""` guard never
opened, silently reproducing findings 1 and 3 on every real run. This
regression was invisible to `1291bfd0`'s own tests
(`TestResolvingMetricsStoreAutoPromotePrefersMetricDescOverFormula`,
`TestResolvingMetricsStoreAutoPromoteRetainsRawUnitOnResolverMiss`)
because both construct their input map with the canonical keys directly,
which never occurs on the real force_clear path.

**Fix:** `resolveAll` now calls `canonicalizeMetricFieldAliases(rep)`
before reading anything from it, so `metric_desc`/`metric_unit` (and any
other aliased field) resolve correctly regardless of which shape the
caller's map arrived in. Locked in by a new test using the real raw-shape
keys, `TestResolvingMetricsStoreAutoPromoteReadsRawShapeDescAndUnit`
(`extract-metrics_test.go`).

### New: `[ontology_term_property_map]` config-driven property exposure

Separate from the erratum, findings 2's fixed `value_type`/`range_type`/
`permitted_unit_term_ids`/`raw_unit` set covers only what auto-promotion
itself needs. To let an operator expose *additional* already-extracted
artifact fields onto `kb.ontology_terms.properties` without a code change
per field, `config.toml`/`config.local.toml` now supports:

```toml
[ontology_term_property_map]
property_map = [
  "metric:metric_name:name",
  "metric:metric_subject:subject",
  "metric:metric_unit:unit",
  "metric:formula_or_definition:formula_or_definition",
  ...
]
```

Each entry is `<artifact_type>:<table_field_name>:<property_name>`.
`artifact_type` today can be `metric`, `provisions`, `entity`, or
`relation`, matching the artifact families in `kb.metrics`/
`kb.provisions`/entity-relation extraction; only `metric` is wired to a
call site so far (per this request — provisions/entity/relation are
reserved for later, not implemented). `table_field_name` supports a
dotted path into nested fields (e.g. `ext_info.object_name`). Absent or
empty-valued fields are silently omitted, not written as null/"".

Implementation:
- `server/cmd/config/config.go`: `OntologyTermPropertyMapConfig`,
  `AppConfigDef.OntologyTermPropertyMap`, `GetOntologyTermPropertyMap()`.
- `server/api/doc-processing/ontology_term_property_map.go` (new):
  `parseOntologyTermPropertyMap` (groups entries by artifact_type) and
  `buildOntologyTermProperties` (resolves each mapped field, dotted-path
  aware, against an artifact's field map).
- `server/api/ontology/keywords/alignment.go`: `TermSynthesisInput` gains
  `ExtraProperties map[string]any`; `termProperties()` merges it in first
  so the fixed synthesis keys (`value_type`, `range_type`,
  `permitted_unit_term_ids`, `raw_unit`) always win on a name collision.
- `extract-metrics.go`'s `resolveAll` builds `ExtraProperties` from the
  `metric` mappings against the same canonicalized `rep` used for the
  erratum fix above, so both fixes share one normalized read.

Covered by `TestResolvingMetricsStoreAutoPromoteAppliesConfiguredPropertyMap`.

Not done: wiring provisions/entity/relation extraction to this mechanism
(no call sites touched them; the config format supports it when that work
is scoped), and reconciling the operator-authored `config.local.toml`
mapping's `value_data_type`/`value_range_type` property names against the
fixed synthesis's own `value_type`/`range_type` keys (both will appear on
the same term today, under different property names — not deduplicated,
left to the operator's config).

## Review — 2026-08-22 (round 2): class-vs-instance conflation in the property-map feature

Triggered by a proposal to add `kb.semantic_assertions.properties`,
reasoning by analogy: `associate_semantics` creates a `kb.semantic_assertions`
row per extracted metric, and a `kb.ontology_terms` record is created or
selected as that row's "class" (`instance_of_term_id`), so the assertion
should get the same JSONB treatment the class did. Tracing the actual
mechanics found the premise doesn't hold as stated — the "class creation"
step is not one mechanism but two, disconnected — and surfaced four
confirmed problems, agreed in discussion.

**5. Class creation runs in the wrong pipeline stage.** `kb.ontology_terms`
metric_definition classes are not created by `associate_semantics`. They
are auto-promoted earlier, inside `extract-metrics.go`'s `resolveAll`
(`extract-metrics.go:284`, `s.Alignments.EnsureAcceptedOrCreate`) — before
`normalize_assertions`/`associate_semantics` ever sees the metric.
`associate_semantics`'s own class-resolution step
(`metric_lossless_writer.go:222`, `resolveOrCreateMetricClass`) only mints
a bare identity-only class (`classfoundation.ContractStore.
CreateIdentityOnlyClass` — `term_kind='class'`, `ContractPayload: "{}"`, no
`definition`, no `properties`) when the extract_metrics-stage promotion
hasn't already run for that concept and left `metric_definition_term_id` on
the metric row; otherwise it silently reuses whatever extract_metrics
already created. Two independent producers of the same governed-concept row
is the same category of problem this bug report opened with. **Agreed
direction: class creation belongs in `associate_semantics` only;
`extract_metrics` should stop auto-promoting.**

**6. `properties` is populated from one instance occurrence, not
class-level facts.** `extract-metrics.go:265-276` builds `ExtraProperties`
from `firstByName[name]` — literally the first metric row seen for that
name in the current batch — via `buildOntologyTermProperties
(metricPropertyMappings, canon)`. Several of `config.local.toml`'s mapped
fields (`metric_subject`, `threshold_or_target`, `measurement_frequency`,
`value_min`, `value_max`, `metric_value`, `condition`) are facts about
*that one measurement occurrence*, not the metric_definition concept.
Writing them onto the shared class term's `properties` is instance data
leaking into class scope — and, per finding 4 (still open), frozen there
permanently since the class is never re-synthesized against a later,
different occurrence. **Agreed: `kb.ontology_terms.properties` should hold
only class-level facts.**

**7. Property keys aren't normalized between the two writers.**
`alignment.go`'s `termProperties()` (`alignment.go:313-328`) writes the
fixed synthesis fields under `value_type`/`range_type`/
`permitted_unit_term_ids`/`raw_unit`, sourced from
`canon["value_data_type"]`/`canon["value_range_type"]`/
`canon["metric_unit"]`. The same `canon` values are *also* mapped by
`config.local.toml`'s `property_map` entries `metric:value_data_type:
value_data_type` and `metric:value_range_type:value_range_type` into
`ExtraProperties`, which `termProperties()` merges in verbatim. Since
`"value_type"` and `"value_data_type"` don't collide as strings, both land
in `properties` on the same term, holding the same value under two
different keys — the "Not done" item immediately above, now confirmed as a
live duplication rather than a hypothetical. **Agreed: property names need
to be normalized to one key per fact.**

**8. Resolution for `kb.semantic_assertions`: reuse `qualifiers`,
config-driven — no new column.** No new `properties` column on
`kb.semantic_assertions`. `qualifiers` was already designed for exactly
this role (`extract-metrics-structured-output/design.md:177`: "Should
`condition` also be carried onto the assertion's `qualifiers`?"). Of its
current hardcoded fields (`metricQualifiers`, `associate_semantics.go:
323-332`: `metric_name`, `metric_definition_term_id`, `condition`), only
`metric_name` is a genuinely meaningful qualifier value today —
`metric_definition_term_id` is redundant with `instance_of_term_id` once
(5) is fixed, and `condition` alone doesn't justify a hardcoded field list.
**Agreed: `qualifiers` should be populated from a configured map** (same
shape as `[ontology_term_property_map]`, scoped to the assertion/instance
rather than the class), so which occurrence-level fields land there is
operator-configurable rather than hardcoded — the same config-driven
mechanism already built for finding 2's fix, pointed at the correct
(instance-level) table this time.

**Status: agreed, then implemented same-day** — see "Implementation —
2026-08-22" below. All four required coordinated changes across
`extract-metrics.go`, `alignment.go`, `metric_lossless_writer.go`,
`metric_normalizer.go`, `associate_semantics.go`, and the
`config.toml`/`config.local.toml` property-map schema.

## Implementation — 2026-08-22: findings 5-8

Implemented via ChenWeb OpenSpec change `fix-metric-property-scope-conflation`
(`openspec/changes/fix-metric-property-scope-conflation/`). Investigating the
fix surfaced two further, previously undiscovered facts that shaped the
design — recorded in that change's `design.md` rather than repeated here:
`assertions` cannot import `keywords` (a hard cycle: `keywords` already
imports `assertions`), and `associate_semantics`'s own class-resolution path
(`classfoundation.CreateIdentityOnlyClass`) never inserted into
`kb.ontology_terms` at all, so every provisional class it minted was already
invisible to `kb.ontology_terms_current` before this fix — a precondition
finding 5 had to close, not just a design nuance.

- **Finding 5**: new `ClassSynthesizer` registration seam in `assertions`
  (`class_synthesizer_registry.go`), implemented in `keywords`
  (`class_synthesis.go`, registered via `init()`) reusing
  `EnsureAcceptedOrCreate`'s now-extracted transaction-scoped core
  (`ensureAcceptedOrCreate`). `extract-metrics.go` no longer calls
  `EnsureAcceptedOrCreate`; `metric_lossless_writer.go`'s
  `resolveOrCreateMetricClass` calls the registered synthesizer instead of
  `classfoundation.CreateIdentityOnlyClass`, always producing a real,
  `kb.ontology_terms_current`-visible row.
- **Finding 6**: `[ontology_term_property_map]`'s `metric` mapping in
  `config.local.toml` is now empty — every previously-listed field was
  either instance-level (moved to finding 8's new map) or a duplicate of a
  fixed class-level fact (`value_data_type`/`value_range_type`/`metric_unit`/
  `metric_name` duplicated `value_type`/`range_type`/`raw_unit`+
  `permitted_unit_term_ids`/the term's own prefLabel).
- **Finding 7**: closed as a consequence of finding 6's trim — the
  duplicate-key pairs no longer both exist.
- **Finding 8**: new `[semantic_assertion_property_map]` config section
  (12 entries) drives `kb.semantic_assertions.qualifiers` via a generalized,
  shared property-map helper (moved from `doc-processing` to
  `assertions/property_map.go`, since the new `metric_normalizer.go` call
  site can't import `doc-processing`). `metricQualifiers()` removed.

`go build ./...`, `go vet ./...`, and `go test ./...` are clean (pre-existing,
unrelated failures elsewhere in the workspace confirmed unchanged via
`git diff --stat`). Not verified against a live database in this
environment — `TestIntegrationWriteMetricLosslessProvisionalClassIsCatalogVisible`
covers the visibility fix end-to-end and needs a `TEST_DATABASE_URL` run
before this is considered fully verified.