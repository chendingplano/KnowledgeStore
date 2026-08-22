# ADR 2026082203 — Governed Class-Identity Signatures: Resolve-or-Propose Properties, Configurable Per Artifact Type, Unified with Instance Properties and Search Documents

**Date:** 2026-08-22 \
**Status:** Proposed \
**Component:** ChenWeb — `kb.ontology_terms`, `kb.ontology_terms.properties`, `kb.semantic_assertions` (`object_literal`, `qualifiers`), `server/api/ontology/assertions/metric_lossless_writer.go`, `server/api/ontology/keywords/`, `server/cmd/config/config.go`, and the `kb.ontology_term_search` index proposed by ADR `2026082102` \
**Authors:** Chen Ding (with Claude) \
**Related:** ADR `2026081701` (DR3, DR7, DR9 — this ADR concretizes work that ADR left as architecture without a built mechanism), ADR `2026081201` (auto-promoted governed terms), ADR `2026081401` (governed `value_range_type` mapping — the pattern this ADR generalizes), ADR `2026082102` (hybrid search over `kb.ontology_terms`), bug `2026082101` (auto-promoted term schema/data loss; findings 5-8 fixed by change `fix-metric-property-scope-conflation`) \
**Tags:** ontology, class identity, property signature, governed vocabulary, resolve-or-propose, configuration, search document

## 1. Change Logs

* 2026/08/22, ADR created following a live-data review of `fix-metric-property-scope-conflation`
  (bug `2026082101` findings 5-8): inspecting real `kb.ontology_terms.properties` and
  `kb.semantic_assertions.object_literal`/`qualifiers` output surfaced that today's class-resolution
  mechanism cannot use the signals it needs, that literal/qualifier data is split without the code
  depending on the split, and that `unit`/`unit_term_id` is the only field in the schema that gets
  raw-value-plus-governed-term-id treatment.
* 2026/08/22, DR1-DR5 implemented (openspec change `governed-class-signature-resolution`); DR6
  deferred (see §7). Status intentionally left `Proposed` per this doc series' convention of not
  flipping Status on implementation.

## 2. Context

### 2.1 What triggered this: real output that shouldn't have been surprising

After `fix-metric-property-scope-conflation` shipped (bug `2026082101` findings 5-8), a live
reprocess of cleared data surfaced three observations, each traced to code in this session:

1. `kb.ontology_terms.properties` for auto-promoted `metric_definition` terms held only `value_type`,
   `range_type`, `raw_unit` — never `permitted_unit_term_ids` (no released unit matched), never
   `metric_name` or anything else. Not because a config list was partially applied — because
   `[ontology_term_property_map]` was correctly, deliberately empty (finding 6's fix removed every
   field that was either instance-level or a duplicate of a fixed key), and the three observed keys
   come entirely from `termProperties()`'s fixed fields, unrelated to that config.
2. `kb.semantic_assertions.id = 607` has `object_literal = {"unit": "%", "value": 30}` while `subject`
   and `object_name` for the same occurrence live in `qualifiers` instead — an arbitrary split by
   conceptual role (§2.2 of ADR `2026081701`'s DR8 distinguishes "instance" fields generically, but
   nothing in the codebase enforces or depends on literal-vs-qualifier specifically; see DR1 below).
3. `unit`/`unit_term_id` is the only field anywhere in the schema that gets "keep the raw value,
   also resolve it to a governed term if possible" treatment (`resolveUnitTerms`,
   `metric_lossless_writer.go:522`). Every other field — `metric_name`, `subject`, `object_name`,
   `value_class` — is either raw text nowhere near identity resolution, or entirely absent from any
   resolution path.

### 2.2 The deeper problem: class identity cannot see the signals that would let it be correct

Today, `metric_definition` class identity (`resolveOrCreateMetricClass`,
`provisionalMetricClassTermID`) is decided by exactly one of, in order:

1. `p.MetricDefinitionTermID` — reuse verbatim if a prior alignment/run already set it.
2. `p.ConceptID` — delegate to keyword-concept alignment (`AcceptedForConcept`).
3. `sha256(lower(trim(metric_name)))[:12]` — the fallback, using only the raw name string.

None of these three paths consult `subject`, `object_name`, `value_class`, quantity, or unit — the
exact signals that distinguish "ambient temperature" from "device-surface temperature" when both are
extracted under the identical `metric_name` string "温度". Two genuinely different governed metrics
collapse into one class today, silently, on the *primary* path (step 2), not only in some edge case.

This is not a new problem this ADR discovers — **ADR `2026081701` DR7 already names it and already
specifies the shape of the fix**:

> "Name identity is necessary but not sufficient for class identity. Class resolution also uses
> stable source identifiers, redirects, governed mappings, quantity kind, observable property, unit
> dimension, subject compatibility, attribute shape, logical datatypes, conditions, modality,
> applicability, domain scope, ontology neighborhood, corpus evidence, and bounded LLM adjudication."

and DR7's "Artifact-family adapters provide structural fields, compatibility rules, negative
constraints, and risk policy" is exactly this ADR's DR4 (configurability per artifact type) in
architectural intent. **What DR7 never received was a concrete mechanism**: which fields, resolved
how, stored where, checked in what order. ADR `2026081701`'s own Implementation Sequence places this
under "Phase 3 — Class synthesis and duplicate reconciliation," and the code in this repository today
implements Phase 1 (stable identity headers, append-only contract/term revisions — `classfoundation`
package) and Phase 2 (lossless instance pipeline, canonical claim identity via
`ClaimIdentityStore.FindOrCreateShadow` — DR9's mechanism, working, in `metric_lossless_writer.go`)
but not Phase 3. `resolveOrCreateMetricClass`'s three-step fallback above **is** Phase 3's missing
piece, currently stubbed at its crudest possible level.

This ADR is that mechanism: a concrete answer to "what does DR7's reusable identity-resolution
service actually check, and where does it store what it learns."

### 2.3 The `unit`/`unit_term_id` pattern already exists twice, unrelated to each other

Two independent parts of the codebase already implement "raw value, resolve against a governed
catalog if possible, keep the raw value regardless, and if unresolved make the gap discoverable":

- **Units**: `resolveUnitTerms` matches a raw unit string against released `unit` terms; the raw
  string survives in `properties.raw_unit` (bug `2026082101` finding 3) regardless of whether
  `permitted_unit_term_ids` resolves.
- **`value_range_type`**: `kb.metric_value_range_type_map` (ADR `2026081401`) maps a raw classification
  string to a `canonical_bucket`; an unrecognized raw value is auto-inserted `status='proposed'` for a
  curator to triage, occurrence-counted, never silently dropped.

Neither generalizes to the other, and neither generalizes to `metric_name`/`subject`/`object_name`/
`value_class`. There is no reason for this to be a per-field special case. Generalizing it is DR3.

### 2.4 A parallel that already exists one layer down: DR9's canonical claim identity

ADR `2026081701` DR9 already solved this exact problem for **instances**: a deterministic
`canonical_payload`, serialized from identity-bearing fields, hashed to a `canonical_digest`, with a
concurrency-safe find-or-create against `kb.semantic_claim_identities`. This ADR's DR2 is the same
pattern one layer up, for **classes**: a deterministic property signature that decides whether an
occurrence resolves to an existing class or provisions a new one — the mechanism DR7 calls for and
DR9 already demonstrates works.

### 2.5 A second, concurrent need: hybrid search over the same catalog

ADR `2026082102` (Proposed, same author, one day earlier) adds `kb.ontology_term_search` with a
`search_document` built from `kb.ontology_terms.{definition, scope}` plus every label. It does not
yet draw on `properties` at all. Once `properties` becomes a governed, resolved signature (this ADR's
DR2/DR3) rather than an arbitrary bag, it is the natural additional source for `search_document` —
one composition rule, not two independently maintained ones. This ADR does not modify `2026082102`'s
schema or rollout; DR6 below specifies only the composition-source addition.

## 3. Decision

### DR1 — `kb.semantic_assertions` treats `object_literal` and `qualifiers` as one property bag; the literal/reference split stays, the value/context split inside it does not

Audited: no Go code branches on `ObjectRefKind == "literal"` beyond the row's own writer
(`metricObjectLiteral`) and the CHECK constraint distinguishing a literal object from a referenced one
(`object_ref_kind`/`object_ref_id` vs `object_literal`, migration `20260801000001`). The one real
reader beyond the writers, `search_indexing.go`'s `buildMetricRegistryRows`, already reads
`object_literal` and the typed columns (`numeric_value`/`lower_value`/`upper_value`/`unit_term_id`)
side by side into the same search-text composition — it does not depend on `object_literal`'s
internal shape being exactly `{unit, value, lower, upper}`. Nothing in the codebase depends on
"literal" vs "qualifier" as a meaningful distinction; it was an editorial split, not a functional one.

**Decision:** every occurrence field not already represented by a dedicated typed column
(`numeric_value`, `lower_value`, `upper_value`, `unit_term_id`, `comparator`, `value_form`) is a
property, stored uniformly, with no separate "literal" bag. `subject`, `object_name`, `unit`
(raw-preservation form, distinct from `unit_term_id`), and every `[semantic_assertion_property_map]`
field live in one place. Whether that place keeps the column name `qualifiers` or `object_literal` is
implementation detail (DR3 below gives it a required shape either way); `object_ref_kind = 'literal'`
and the CHECK constraint stay exactly as they are — they distinguish reference-kind assertions from
value-bearing ones, a real, used distinction, separate from where the value's *properties* are stored.

**Not removed by this decision:** `numeric_value`/`lower_value`/`upper_value`/`unit_term_id` remain
dedicated typed columns — they are queried, indexed, and compared directly (range queries, relation
derivation per ADR `2026081701` DR10) in ways a JSONB bag cannot support efficiently. DR1 removes the
`object_literal` vs `qualifiers` *bag* duplication, not the typed-column vs JSONB duplication, which
is a distinct, deliberate performance tradeoff already established by DR10.

### DR2 — `kb.ontology_terms.properties` is the class-identity signature, not a descriptive afterthought

Reframing, not a schema change to this column: `properties` stops being "whatever extra fields an
operator felt like exposing" and becomes the deterministic set of resolved values that *define which
class this is*, mirroring DR9's `canonical_payload` one layer up (§2.4). Two occurrences with the same
resolved signature are the same class; two with different resolved signatures on any identity-bearing
dimension are different classes, even if their raw `metric_name` string is identical.

Every signature entry, once resolution (DR3) runs, has the shape:

```json
{
  "subject": {"raw": "环境", "term_id": "measurement:subj_ambient"},
  "object_name": {"raw": "肥料", "term_id": "measurement:obj_fertilizer"},
  "value_class": {"raw": "requirement", "term_id": null}
}
```

`term_id: null` means "resolution attempted, no governed match yet" (DR3's propose path already ran);
absence of the key entirely means "this dimension is not configured for this `term_kind`/artifact
type" (DR4). This distinguishes "we don't know" from "not applicable" — the same distinction DR8 of
ADR `2026081701` already requires between assertion value states `unknown` and `not_applicable`.

`value_type`/`range_type`/`raw_unit`/`permitted_unit_term_ids` (bug `2026082101` finding 2's fixed
synthesis fields) are unaffected — they describe the metric's *shape*, not its *identity*, and stay as
today, alongside the signature entries under the same `properties` column.

### DR3 — Generalize "raw value, resolve against a governed catalog, keep the raw value regardless, propose if unresolved" to every signature dimension

One new table generalizes `kb.metric_value_range_type_map`'s shape (§2.3) across every dimension
rather than growing a family of near-identical per-field tables:

```sql
CREATE TABLE kb.governed_property_value_map (
    dimension             TEXT NOT NULL,   -- e.g. 'metric_subject', 'metric_object_name', 'metric_value_class'
    raw_value             TEXT NOT NULL,   -- normalized per DR3's own rule, see below
    term_id               TEXT REFERENCES kb.ontology_terms(term_id),
    status                TEXT NOT NULL DEFAULT 'proposed'
                               CHECK (status IN ('proposed', 'approved', 'ambiguous', 'rejected')),
    occurrence_count      BIGINT NOT NULL DEFAULT 0,
    first_seen_record_id  BIGINT,
    last_seen_record_id   BIGINT,
    note                  TEXT,
    create_time           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    create_by             TEXT,
    modify_time           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    modify_by             TEXT,
    PRIMARY KEY (dimension, raw_value)
);
CREATE INDEX idx_kb_governed_property_value_map_status ON kb.governed_property_value_map (dimension, status);
```

Resolution for one dimension, one raw value: look up `(dimension, normalize(raw_value))`; `approved`
returns its `term_id`; `proposed`/`ambiguous`/miss increments `occurrence_count` (or inserts
`status='proposed'` on first sight, mirroring `ValueRangeTypeMapper.Lookup` exactly) and returns no
`term_id` — the raw value is written into `properties` regardless (DR2's `raw` key), never discarded.
A curator (or, per ADR `2026081701` DR12, a policy-gated deterministic/statistical/LLM pipeline)
approves proposed rows into governed `term_id`s over time, same operational shape as
`kb.metric_value_range_type_map` today.

`normalize(raw_value)` reuses `normalizeValueRangeTypeRaw`'s existing rule (lowercase, trim,
`-`/space → `_`) as the floor; a dimension may need stronger normalization (e.g. NFKC for
`metric_subject`, which can be free CJK/Latin mixed text) — **left as an Open Decision (§5)**, since
getting this wrong either over-splits (near-duplicate raw values proposed separately) or over-merges
(distinct subjects collapsed by aggressive normalization).

`term_id` referencing `kb.ontology_terms` means each dimension's approved values are themselves
governed terms of some `term_kind` (e.g. a new `metric_subject`/`metric_object` `term_kind`, or reuse
of `concept`) — **which `term_kind` per dimension is an Open Decision (§5)**, deliberately not forced
by this ADR; DR4's configuration names the dimension and, separately, which `term_kind` its resolved
values belong to.

### DR4 — Signature composition is configured per artifact type, not hardcoded

Extends `[ontology_term_property_map]`'s existing shape (already scoped per `artifact_type`) with two
new pieces of information DR2/DR3 need: whether an entry is identity-bearing (participates in the
class signature) and which governed dimension it resolves against. The existing flat
`"artifact_type:field:property"` string cannot carry a third/fourth attribute cleanly; this ADR
proposes moving to a table array, which the config-loading path (`mapstructure`) already supports
elsewhere in `config.toml`:

```toml
[[ontology_term_property_map.metric]]
field      = "metric_name"
property   = "name"
identity   = true
dimension  = "metric_name"          # resolves via kb.governed_property_value_map

[[ontology_term_property_map.metric]]
field      = "metric_subject"
property   = "subject"
identity   = true
dimension  = "metric_subject"

[[ontology_term_property_map.metric]]
field      = "ext_info.object_name"
property   = "object_name"
identity   = true
dimension  = "metric_object_name"

[[ontology_term_property_map.metric]]
field      = "value_class"
property   = "value_class"
identity   = true
dimension  = "metric_value_class"
```

`identity = false` (or omitted) entries behave exactly as today's finding-6 design: descriptive,
non-signature, no resolution attempted, written to `properties` as raw text only if genuinely
class-level (still expected to be rare per bug `2026082101` finding 6's own audit — most fields
remain instance-level and belong in `[semantic_assertion_property_map]`, DR1's unified bag,
unaffected by this table-array migration). A future `term_kind` (`unit`, `quantity_kind`, `class`,
...) gets its own signature composition simply by adding entries with that `artifact_type`/
`term_kind` — no code change, matching DR7's "artifact-family adapters" intent.

Config validation (bug `2026082101`'s prior open ask, "report errors instead of silently defaulting"):
this ADR takes a middle position (§2 of that review's answer stands) — a **warning**, not a hard
error, when a configured `term_kind` known to require identity fields (i.e., any `term_kind` this
ADR's DR5 will attempt signature-based resolution for) has zero `identity = true` entries, since that
combination is almost certainly a misconfiguration rather than an intentional empty state.

### DR5 — `resolveOrCreateMetricClass` resolves by signature before falling back

New resolution order, replacing today's three-step fallback (§2.2), implementing ADR `2026081701`
DR7/DR11's "reuse an existing class through deterministic gates... before provisional creation":

1. Resolve every `identity = true` dimension (DR4) for the occurrence via DR3, producing the
   signature.
2. Look up an existing class whose `properties` signature matches on every dimension that resolved to
   a non-null `term_id` on **both** sides (an unresolved/absent dimension on either side is a
   don't-care for matching, not a mismatch — required so a partially-observed occurrence can still
   match a fully-signatured class and vice versa; exact policy for *how many* dimensions must agree
   is an Open Decision, §5).
3. No match → fall back to `p.MetricDefinitionTermID` (existing alignment), then `p.ConceptID`
   (existing concept alignment, still valuable as one input, not the sole one — consistent with §2.2's
   refinement of the user's DR7 framing), then the existing name-hash, in that order, as today.
4. Create a provisional class (`ClassProvisionalNew`, unchanged) carrying the resolved signature in
   `properties` from step 1, so the **next** occurrence with the same signature matches at step 2
   instead of falling through again.

This is additive to, not a replacement of, `EnsureAcceptedOrCreate`'s keyword-concept alignment (still
the source of `p.ConceptID`, still valuable for the name dimension specifically, per this ADR's own
§2.2 refinement of the user's stronger claim that concept resolution "should never" participate) — it
just stops being the *only* signal.

### DR6 — `search_document` (ADR `2026082102`) draws on the same signature fields

Additive to `2026082102` DR3's composition rule, not a change to its table or write path: alongside
`definition`/`scope`/labels, `search_document` also concatenates each signature dimension's `raw`
value (DR2's shape) with its own configurable weight in `[ontology_terms_search_weights]`. One
`term_id` change to `properties` (DR3 resolving a previously-`proposed` dimension, say) reindexes
through the exact same `ReindexOntologyTermSearch` choke point `2026082102` DR4 already specifies —
no second composition rule to keep in sync.

## 4. Consequences

### 4.1 Positive

* Class identity finally uses the signals ADR `2026081701` DR7 always said it needed — same-label,
  different-subject occurrences stop silently colliding.
* One resolve-or-propose mechanism, one governed-value table, instead of a per-field special case
  (units) plus a lone generalized instance (`value_range_type`) plus nothing for everything else.
* `properties` and `search_document` (`2026082102`) draw from one configured field list — no drift
  between "what makes this class distinct" and "what makes this class findable."
* `object_literal`/`qualifiers` unification removes a distinction the code never used, per DR1's audit.
* Per-`term_kind`/artifact-type configuration (DR4) is the concrete mechanism ADR `2026081701` DR7
  described abstractly as "artifact-family adapters" — no new architectural concept, just its first
  real implementation.

### 4.2 Costs and risks

* `kb.governed_property_value_map` is a new triage queue, same operational shape as
  `kb.metric_value_range_type_map` — someone has to approve `proposed` rows, or every dimension stays
  permanently unresolved (raw-only) and DR5's signature matching degrades toward today's name-hash
  behavior for that dimension.
* DR3's normalization strength is genuinely unresolved (§5) and gets it wrong in either direction with
  real cost: too weak over-splits (duplicate classes for trivially-different raw text), too strong
  over-merges (distinct concepts silently unified, the exact failure DR5 exists to prevent one level
  up).
* DR4's config-array migration is a breaking format change to `[ontology_term_property_map]` (flat
  string list → table array) — every deployment's `config.local.toml` needs rewriting, not just
  `metric`'s entries; `ParsePropertyMap`/`BuildMappedProperties` (`assertions/property_map.go`) need a
  compatible rewrite too.
* DR5's partial-signature matching policy (how many dimensions must agree) directly trades off false
  merges against false splits and is not fully specified here (§5) — implementing DR5 before resolving
  that Open Decision risks shipping the wrong default.

## 5. Open Decisions

* **OD1 — Per-dimension normalization strength (DR3).** Floor is `normalizeValueRangeTypeRaw`'s
  lowercase/trim/dash-to-underscore rule; whether `metric_subject`/`metric_object_name` need NFKC,
  whitespace collapsing, or script-aware folding is unresolved and should be informed by real
  `kb.governed_property_value_map` `proposed` volume after DR3 ships, not decided speculatively.
* **OD2 — Which `term_kind` owns each dimension's resolved values (DR3).** New `term_kind`s
  (`metric_subject`, `metric_object`, ...) vs. reuse of `concept`/an existing kind — affects the QUDT-
  style catalog structure and whether `names.Resolver`'s existing tiered matching (§2.2, still valid
  for the name dimension) can be reused for other dimensions too.
* **OD3 — DR5's partial-signature match policy.** Exact-match on every dimension present on both
  sides (strict, risks under-matching while dimensions are mostly `proposed`/unresolved during
  rollout) vs. a minimum-agreement threshold (risks false merges) vs. staged rollout (strict once
  approval coverage crosses a measured threshold, looser before). Needs the same kind of full-corpus
  measurement ADR `2026081701` Phase 0 already established as a precondition for its own rollout.
* **OD4 — Exact DR4 config-array schema and migration path** for existing `config.local.toml`
  deployments (this repo's included) — a mechanical but real breaking change, not yet drafted as a
  goose migration or config-loader diff.
* **OD5 — Whether DR1's unification renames `object_literal`/`qualifiers` to one column** or keeps two
  columns with identical, interchangeable shape for now (lower migration risk, revisit once DR1's
  "no functional dependency" audit is independently re-verified against a live corpus, not just static
  grep).

## 6. Relationship to Earlier Decisions

### ADR `2026081701`

This ADR does not revise DR1-DR14. It implements the previously-unbuilt half of DR7 ("reusable
identity-resolution service" — this ADR's DR3/DR5), concretizes DR3's `identity_only` →
`partially_defined` transition trigger (a class gains signature dimensions as `kb.governed_property_
value_map` entries get approved — still `identity_only` until enough resolve, still never claiming
unsupported capabilities per DR3 of that ADR), and gives DR9's canonical-payload pattern its
class-level counterpart (§2.4). Phase 3 of that ADR's Implementation Sequence is this ADR's scope;
Phases 1, 2, 4, 5 are unaffected.

### ADR `2026081401`

`kb.metric_value_range_type_map` is the concrete precedent DR3 generalizes. That table is not
replaced or migrated into `kb.governed_property_value_map` by this ADR — it remains scoped to
`value_range_type` specifically unless a later decision folds it in, since `value_range_type`
resolution feeds `canonicalClaimFields` (DR9, instance identity) rather than class identity, a
different axis from this ADR's scope.

### ADR `2026082102`

DR6 is additive to that ADR's DR3 (`search_document` composition) and DR4 (reindex choke point). No
change to its table, embedding flow, or rollout plan.

### Bug `2026082101`

Findings 5-8 (fixed by `fix-metric-property-scope-conflation`) established the class/instance
`properties`/`qualifiers` split this ADR now reconsiders (DR1) and the config-driven property-map
mechanism this ADR extends (DR4). Finding 4 (auto-promoted terms never refresh after creation,
deferred by design in that bug) is directly addressed by DR5 step 4 writing a real signature at
provisional-class creation time, though still not "refresh a class's contract when a later occurrence
is richer" — that remains open, now inherited by this ADR's OD3 rollout question rather than restated
as a separate finding.

## 7. Implementation

DR1-DR5 implemented 2026-08-22 (openspec change `ChenWeb/openspec/changes/
governed-class-signature-resolution/`). DR6 explicitly not implemented — see below.

**Migration:**
- `project_migrations/20260822000002_create_kb_governed_property_value_map.sql` — DR3's table,
  no seed data (nothing to preserve, unlike `kb.metric_value_range_type_map`'s DR5 seed).

**Code changes:**
- `server/api/ontology/assertions/governed_property_resolver.go` (new) — `GovernedPropertyResolver`,
  generalizing `ValueRangeTypeMapper`'s cached resolve-or-propose shape across a `(dimension,
  raw_value)` composite key.
- `server/api/ontology/assertions/property_map.go` — `BuildSignatureProperties` added alongside the
  existing `BuildMappedProperties`; writes DR2's `{"raw":..., "term_id":...}` shape for `identity =
  true` fields, a plain value otherwise. `ParsePropertyMap`/`BuildMappedProperties` untouched (still
  serve `[semantic_assertion_property_map]`, unaffected by DR4).
- `server/api/ontology/assertions/metric_normalizer.go` — `Normalize` resolves identity dimensions
  once per row (mirroring the existing `ValueRangeTypeMapper.Lookup` call site exactly), not inside
  the later write transaction.
- `server/api/ontology/assertions/metric_lossless_writer.go` — `resolveOrCreateMetricClass` gains
  `matchClassBySignature` as its new first step (DR5); unchanged fallback order otherwise.
- `server/cmd/config/config.go` — `OntologyTermPropertyMapEntry` (`field`/`property`/`identity`/
  `dimension`); `AppConfig.OntologyTermPropertyMap` becomes `map[string][]OntologyTermPropertyMapEntry`
  (DR4's table-array shape nests directly under the section key, no wrapper struct needed); DR4's
  config-load warning when a `term_kind` requiring signature resolution (currently just `metric`) has
  zero `identity = true` entries.
- `config.local.toml` — `[ontology_term_property_map]` rewritten to the table-array shape (4 identity
  entries: `metric_name`, `metric_subject`→`subject`, `ext_info.object_name`→`object_name`,
  `value_class`); the other 8 fields from the prior flat list moved to `[semantic_assertion_property_map]`
  as genuinely instance-level. `config.toml` has no such section (unchanged — operator-local only).

**As implemented / deviations found:**
- DR3's `term_id TEXT REFERENCES kb.ontology_terms(term_id)` as literally written does not work:
  `kb.ontology_terms` has no unique constraint on `term_id` (it is the append-only revisions table);
  the actual stable-identity table other FKs in this schema already reference is
  `kb.ontology_term_headers`. Migration uses `REFERENCES kb.ontology_term_headers(term_id)`.
- DR5's "matches on every dimension resolved on both sides" was underspecified for two cases,
  resolved during implementation (design.md D3 in the openspec change): (1) zero shared resolved
  dimensions is treated as no match, not a vacuous match against every class in the catalog; (2)
  multiple existing classes that don't contradict the occurrence but agree on different,
  non-overlapping dimensions are ranked by shared-agreement count; a tie at the max count creates a
  **new** provisional class (never guesses) with identity state `ClassAmbiguousCandidates` — an
  existing, previously-defined-but-never-produced identity state — and records the tied candidates as
  `ClassResolutionAlternative` rows, the first real write to `ClassResolutionDecisionStore.
  RecordIfChanged`'s alternatives parameter (previously always `nil`).
- DR6 not implemented: ADR `2026082102` (its dependency, `kb.ontology_term_search`) has zero
  implementation in this repo as of this date — no table, no `ReindexOntologyTermSearch`, no openspec
  change. Confirmed with the user before scoping this ADR's implementation to exclude it.
- OD1 (normalization) implemented at the ADR's own stated floor only (`normalizeValueRangeTypeRaw`'s
  rule, reused verbatim). OD2 (which `term_kind` owns each dimension) resolved as a non-decision: no
  code mints or selects a `term_kind` for an approved row — approval stays a manual/curator action
  against `kb.governed_property_value_map`, mirroring `kb.metric_value_range_type_map`'s existing
  operational shape exactly, so OD2 never blocked implementation. OD3 (DR5 match policy) resolved via
  user confirmation to strict-agreement-with-ambiguity-fallback (not a threshold or staged rollout).
  OD5 (object_literal/qualifiers merge) deferred — two columns unchanged.
- Found and fixed as a byproduct of running this change's integration tests for the first time in
  this environment (`TEST_DATABASE_URL` had never been set here before): every
  `metric_lossless_writer_integration_test.go` test that reaches `SynthesizeClass` was silently unable
  to run at all ("no class synthesizer registered"), because the `assertions` package's test binary
  never imported `keywords` (whose `init()` performs the real registration) — `assertions` cannot
  import `keywords` directly (reverse import already exists), so fixed via a new external
  (`package assertions_test`) blank-import file, `keywords_synthesizer_register_test.go`. Also seeded
  `core:aligns_to_term` in one pre-existing test (`TestIntegrationWriteMetricLosslessProvisionalClassIsCatalogVisible`)
  that was missing it. Both fixes are to pre-existing, uncommitted test gaps unrelated to this ADR's
  own decisions, not new test coverage this ADR required.
- Verification: `go build ./...`, `go vet ./...` clean workspace-wide;
  `go test ./server/api/ontology/assertions/... ./server/cmd/config/...` clean, including 5 new
  `TestIntegrationWriteMetricLosslessSignature*`/`*Noop` integration tests run against a real
  Postgres (`TEST_DATABASE_URL`, scratch database per test). Full-workspace `go test ./...` shows
  only the pre-existing failure catalogue already documented in `fix-metric-property-scope-conflation`
  (`kbhandler`, `llmusage`, `keywords`, `names`, `seed`, `qudt-import` — sqlmock/query staleness
  unrelated to this change). Migration confirmed applied cleanly against both a fresh scratch database
  and the running `mise dev` dev database.

## 8. References

* `KnowledgeStore/doc-repo/adrs/202608/2026081701-adr-canonical-metric-classes-instances-and-semantic-relations.md`
  — DR3 (class definition/capability states), DR7 (reusable identity-resolution service — the
  architecture this ADR concretizes), DR9 (canonical claim identity — the pattern DR2 mirrors),
  DR11 (online/incremental reconciliation), Implementation Sequence Phase 3.
* `KnowledgeStore/doc-repo/adrs/202608/2026081401-adr-governed-metric-vocabulary-and-phase-d-failure-reporting.md`
  — `kb.metric_value_range_type_map`'s propose/approve workflow, generalized by DR3.
* `KnowledgeStore/doc-repo/adrs/202608/2026082102-adr-hybrid-search-ontology-terms.md`
  — `kb.ontology_term_search`/`search_document`, extended (not modified) by DR6.
* `KnowledgeStore/doc-repo/adrs/202608/2026081201-adr-auto-promoted-governed-terms.md`
  — `EnsureAcceptedOrCreate`/keyword-concept alignment, still one input to DR5, no longer the sole one.
* `KnowledgeStore/doc-repo/bugs/202608/2026082101-bug-auto-promoted-ontology-terms-schema-and-data-loss.md`
  — findings 5-8 and their implementation (`fix-metric-property-scope-conflation`), the `properties`/
  `qualifiers`/`object_literal` state this ADR reviews and revises.
