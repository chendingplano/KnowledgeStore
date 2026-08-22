# Auto-promoted metric_definition terms conflate metric-only fields with the generic term schema and silently drop available data

Date: 2026-08-21

Status: findings 1-3 fixed 2026-08-22 (ChenWeb `1291bfd0`), plus a same-day
follow-up erratum fix and a new property-map extensibility feature — see
"Follow-up — 2026-08-22" below. Finding 4 (refresh-on-later-occurrence)
remains open, deferred by design.

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