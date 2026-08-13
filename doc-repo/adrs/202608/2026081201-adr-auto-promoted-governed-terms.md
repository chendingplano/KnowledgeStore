# ADR 2026081201 — Auto-Promoted Governed Terms: Closing DR23's Metric-Definition Gap, Retiring Human-Gated `metric_definition` Term Creation

**Date:** 2026-08-12 \
**Status:** Accepted — implemented 2026-08-12 (see §6) \
**Component:** ChenWeb — `kb.ontology_terms`, `kb.keyword_concepts`, `server/api/ontology/keywords/{alignment.go,concepts_store.go}`, `server/api/ontology/terms/`, `server/api/ontology/comparison/store.go`, `server/api/doc-processing/{extract-metrics.go,extract-metric-definitions.go}` (retired, not deleted) \
**Authors:** Chen Ding (with Claude) \
**Supersedes (in part):** ADR `2026072901` §3.24 (DR23) and §8.2/§A.1/§A.2's treatment of `extract_metric_definitions` as the metric-definition source of truth \
**Tags:** ontology, keyword module, governed terms, metric definitions, DR23, document review app

## 1. Change Logs

* 2026/08/12, implemented via ChenWeb OpenSpec change
  `ChenWeb/openspec/changes/auto-promoted-governed-terms/` (proposal/design/specs/tasks),
  same session. DR1–DR6 are all live. Two real bugs were found and fixed along the way that
  this ADR's original text did not anticipate — see §6 for both; the short version is that
  `names.Resolver.ResolveAndObserve` was silently discarding the auto-created concept id
  its own write path had just produced, and `AlignmentsStore`'s released-guard hardcoded
  `included_in_release`, which would have rejected every `auto-promoted` term this ADR's
  own DR1 creates. `go build`/`go vet`/`go test ./...` clean workspace-wide (confirmed on
  every touched package individually and the full `server/...` tree).
* 2026/08/12, ADR created, from a same-day working session that started as a
  code review of `extract_metric_definitions` (documenting it, debugging why
  it under-extracted on a real document) and escalated into questioning
  DR23's core assumptions after checking them against the live database.

## 2. Context

### 2.1 What the session found, checked directly against the live database

`extract_metric_definitions` (P3–P4 harvester, ADR `2026072901` §8.2) extracts
a `metric_definition` candidate only when a document contains explicit
defining text — a "术语与定义" entry, a definition clause, or a defining
formula. On a real 10-chunk, 55-metric document (`kb.inputs.id=416`) it
correctly found the one formula-based definition the document actually
contains and correctly declined to invent definitions for the other 54
metrics, none of which are explicitly defined in that document's text. This
is the harvester working as designed — the design itself is the problem:
**most metrics are never explicitly defined in the document they're
extracted from**, so a harvester gated on finding such text can never cover
most metrics, regardless of how well it's tuned.

Following the chain past that harvester into the keyword-canonicalization
module (spec `2026080403`) and the governed-content tables surfaced four
compounding, empirically-confirmed problems, not just the one processor's low
recall:

1. **`kb.ontology_terms` has zero `metric_definition` rows.** Its only live
   content is the QUDT import under the `quantity` module (2,843 units, 1,125
   quantity-kinds, 245 dimensions) and 20 `core` rows. The `measurement`
   module — where `metric_definition` terms are supposed to live per ADR
   `2026072901` §3.24 — is empty. There is no catalog today, in the sense
   DR23 uses the word.
2. **`kb.keyword_concepts` has never resolved a real extracted metric.** All
   1,107 rows are `gloss_source='auto:import:qudt'` — from the external
   terminology import, not from document text. `kb.metrics.keyword_concept_id`
   and `.metric_definition_term_id` are both `0` of `7,040` rows. The reason:
   `KEYWORD_RESOLVER_MODE` defaults to `"off"` and is unset in this
   deployment, so `ResolvingMetricsStore` (`extract-metrics.go`) never gets a
   real answer to persist. This module has never been exercised end-to-end
   against real document output.
3. **The only path that writes `kb.ontology_terms` — `CandidateStore.
   PromoteToContent` — hard-requires human approval** (`status == approved`,
   reached only through the `discovered → draft → in_review → approved`
   review-API state machine, which has no built UI yet). Combined with (1)
   and the harvester's low recall, this means a `metric_definition` term
   cannot come into existence today without a human approving a candidate
   that itself was unlikely to have been generated in the first place.
4. **DR23's founding scale assumption — "a domain has on the order of
   hundreds of real distinct metrics" — is unfounded.** "Domain" has no
   formal definition anywhere in the code or the ADR (no schema column, no
   type); its granularity is undrawn. Whether a domain is "ventilators" or
   "medical equipment" changes the claimed bound by 2–3 orders of magnitude.
   The real number of distinct metrics a production system must resolve is
   plausibly in the hundreds of thousands to millions, at which scale
   mandatory human review of every new governed term is not a slower version
   of the same workflow — it is a different, infeasible workflow.

### 2.2 The reframing this session converged on

An earlier draft of this session's conclusion (not adopted) argued: keep
term creation human-gated because a wrong auto-created term corrupts the
*shared* vocabulary future documents match against, whereas a wrong
*assignment* (routing one document's name to one concept) is cheap and
local (D7 in spec `2026080403`: merges are tombstones). That argument is
still true as a description of *relative* risk — but it answers the wrong
question. The operative question is not "can an automatic system be wrong,"
it is **"what failure rate is acceptable, and is mandatory human review at
this volume actually achievable at all."** Given (3) and (4) above, the
honest answer is that mandatory review is not achievable at the volume this
system must handle — a design that requires it produces a system whose
ontology layer is, in the project owner's words, "only useful in theory."

**Decision, at the policy level: creating a `metric_definition` term is not
optional to automate — it is required to automate, subject to keeping the
observed failure rate acceptable through the already-built tiered matching
(spec `2026080403` tiers 0–6), not by declining to act.** Human involvement
remains real but becomes optional and reactive (exception repair, catalog
curation over time), matching D11's "auto-first" policy the keyword module
already applies to concepts — this ADR extends that same policy one hop
further, from concept to governed term.

## 3. Decision

### DR1 — Resolution pipeline: metric name → concept → governed term, in two independent steps

```
extracted metric
  → resolve metric_name via the keyword module (tiers 0–6, unchanged)
      → match an existing kb.keyword_concepts row, OR
      → auto-create a provisional one (D11, already built, unchanged)
  → resolve concept_id to a governed kb.ontology_terms term
      → an accepted aligns_to_term assertion already exists → use it
        (AlignmentsStore.EnsureAccepted, already built, unchanged)
      → none exists → auto-create a new metric_definition term for this
        concept (NEW, this ADR) and auto-accept the alignment
```

**Tiers 0–6 are not reused for the concept→term step.** They exist to solve
*fuzzy* matching between raw name spellings (aliases, translations,
misspellings) — a problem that no longer exists once a name has already been
collapsed to a `concept_id`. Concept→term resolution is a deterministic
existence check (does this concept already have an accepted alignment?) plus
a create-if-absent, not a second fuzzy-matching pass. This keeps the two
layers' responsibilities distinct: the keyword module owns *name* ambiguity;
this step owns *concept-to-governed-identity* assignment, 1:1 by
construction.

### DR2 — New `kb.ontology_terms.status` value: `'auto-promoted'`

Add `'auto-promoted'` to the `ontology_terms_status_check` constraint
(migration required — current values: `draft, in_review, approved,
included_in_release, superseded, rejected`). A term with this status is
**live and usable** — not a draft awaiting review, not blocked on anything —
distinguished from `included_in_release` only so an auto-created term is
visibly attributable as such (for exception-repair sampling, per D11's
"every decision must be attributable, reversible, sampleable" requirement,
which this ADR extends from concepts to terms) without implying a human ever
looked at it.

`included_in_release` (the existing, human-driven, module-release path)
remains available and takes precedence where it exists — this ADR adds a
second, automatic path to a live term, it does not remove the reviewed one.
A term can move from `auto-promoted` to `included_in_release` later if a
curator reviews and formally releases it (ordinary catalog curation, not
this ADR's concern to sequence).

**Precedent, not a novel pattern.** ADR `2026072901`'s 2026/08/09 changelog
entry ("keyword-catalog auto-promotion") already shipped exactly this
"autonomous, clearly flagged, optionally human-reviewed" principle one layer
down: approving an external terminology resource auto-promotes its staged
entries into flagged, provisional `kb.keyword_concepts` rows
(`gloss_source='auto:import:<source>'`) with no human review step, alongside
the online D11 auto-create path (`gloss_source='auto:d11'`). DR2 extends the
same, already-accepted principle from the concept layer to the term layer,
rather than introducing a new one.

### DR3 — Term content is synthesized from the triggering metric's own extracted fields ("intrinsic properties"), not from document prose

An auto-created term's payload is built structurally from data already
present on the triggering `kb.metrics` row and its concept, not authored by
an LLM reading the source document:

| Term field | Source |
|---|---|
| `label` / canonical name | the concept's `pref_label` |
| `aliases` | the concept's alias-role surfaces |
| `value_type` | `kb.metrics.value_data_type` |
| `range_type` | `kb.metrics.value_range_type` |
| `permitted_units` | `kb.metrics.metric_unit`, resolved against the **already-released** QUDT `quantity` module (2,843 unit terms, live today) where possible |
| `definition` | `kb.metrics.formula_or_definition` when present on the triggering row; otherwise left empty rather than fabricated |

This is a **deterministic transcription of already-extracted structured
data**, not a new LLM call authoring ontology content — it does not reopen
the "no LLM activates ontology content" guarantee (`state_machine.go`'s
doc comment, DR6 of ADR `2026072901`), because no generative step decides
what the term *means*; it only restates what the metric extraction already
determined about itself. Where a genuine defining sentence exists in the
source document (§3.5 below), that remains a strictly higher-quality signal
than structural transcription and should enrich the term when available.

### DR4 — `ComparisonStore.validateMetricKey` accepts `auto-promoted` terms

Currently requires `term_kind = 'metric_definition' AND status =
'included_in_release'` (application-level check, `comparison/store.go`,
ADR `2026072901` §2.4/REQ-4). Extend the accepted status set to
`('included_in_release', 'auto-promoted')`. Without this change, DR1–DR3
create usable terms that the Document Review app still cannot use as
comparison rows — this is the concrete code change that makes "a document
starts serving upper-layer apps immediately upon processing" actually true,
not just true for concept-level grouping.

### DR5 — Failure rate is managed, not avoided

This ADR accepts that concept/term fragmentation **will** happen at some
nonzero rate — two auto-created terms may end up representing the same real
metric before reconciliation catches it. This is the same risk the keyword
module already accepted for concepts (D10/§13.1 in spec `2026080403`); this
ADR extends acceptance of that risk one layer up, to governed terms, on the
premise that a nonzero, monitored failure rate serving real apps immediately
is strictly better than a zero-failure-rate design that serves nothing.
Required, not optional, follow-through:

- **Sampling.** Auto-promoted terms need the same "findable as a set" support
  D11 requires for auto-created concepts — a queryable view/flag over
  `status='auto-promoted'`, so exception repair has something to work from.
- **Reconciliation reach.** Spec `2026080403`'s offline reconciliation
  (tier-6 merge, `cmd/keyword-reconcile`) currently merges concepts. Whether
  it needs to also detect and merge/relink duplicate `auto-promoted` terms
  (not just concepts) is open — flagged in §5, not decided here.
- **Measurement before wide rollout.** Before this becomes the default
  production path, run the resolver (in `observe` mode first) against a real
  batch of already-extracted metrics and manually audit how many distinct
  concepts/terms come out versus how many *should* collapse to one. This
  ADR's policy decision (automate, don't gate) does not remove the need to
  know the actual starting failure rate — it changes what happens in
  response to that number (tune the tiers / synthesis rules) instead of
  what happens in this ADR's absence (nothing gets created at all).

### DR6 — Retire `extract_metric_definitions`; keep the code, keep the capsule doc, remove it from the default routed pipeline

Once every metric resolves to a governed term regardless of whether the
document explicitly defines it, `extract_metric_definitions`'s reason for
existing — deciding *whether* a metric gets a definition — is gone; DR1–DR3
decide that unconditionally for every metric. **Retire, not delete:**

- Remove it from the routed-processor selection (pipeline policy /
  `config.toml`) so it no longer runs by default.
- Leave `extract-metric-definitions.go`, its tests, and its prompt in place,
  unmodified.
- Mark `extract-metric-definitions-spec.md` (capsule) as retired, pointing to
  this ADR, rather than deleting it.
- Its output remains a candidate future enrichment source: when it *does*
  find explicit defining text for a metric that already has an
  auto-promoted term, that text is a stronger `definition` value than DR3's
  structural transcription and could backfill it. Building that enrichment
  path is out of scope for this ADR (§5, open).

## 4. Consequences

- `kb.ontology_terms` under `measurement` (and any 4b domain module) will
  grow roughly 1:1 with distinct concepts encountered, not "hundreds" —
  ADR `2026072901` §3.24's scale assumption is retracted (§2.1 item 4); this
  ADR does not replace it with a new bound, because none is knowable without
  drawing a domain boundary this ADR does not attempt to draw.
- `kb.ontology_candidates` (`candidate_kind='term'`, `term_kind=
  'metric_definition'`) stops receiving new rows from
  `extract_metric_definitions` once it's retired from the default pipeline;
  existing rows and the review-API state machine are unaffected and remain
  valid for any other candidate kind still using them.
- This ADR's automatic path is orthogonal to, and does not remove, the
  existing human-reviewed `included_in_release` path — a term can still be
  formally curated and released; it just no longer has to be, to be usable.
- Depends on `KEYWORD_RESOLVER_MODE` actually reaching consumers end-to-end.
  Spec `2026080403` §9.4/D9 flags `"on"` mode as currently unusable (a bug
  where enabling it disables collection, "K7"). **This ADR's DR1 has no
  effect until that is fixed** — tracked as a prerequisite, not restated as
  a new decision here.
- Comparison-matrix rows (Document Review app, ADR `2026072901` §3.23/§2.4)
  will include auto-promoted-term rows once DR4 lands; the app's UI/UX
  should be able to distinguish `auto-promoted` from `included_in_release`
  rows for the same reason the term itself carries the distinction (§DR2).

## 5. Open Decisions

- **OD1 — "Domain."** Not formally defined, and this ADR does not define it.
  The project owner's working view: it may not be needed as a first-class
  concept at all; a higher tier of an eventual catalog hierarchy (§DR2/§3 in
  spec `2026080403`'s D1 identity-layer framing) may end up serving the role
  "domain" was informally standing in for. Deferred until a concrete need
  forces the question.
- **OD2 — Does reconciliation need to merge/relink terms, not just
  concepts?** DR5 flags this; not decided.
- **OD3 — `extract_metric_definitions` as a `definition`-field enrichment
  source for already-auto-promoted terms.** Plausible follow-on, not
  designed here.
- **OD4 — Sampling/monitoring UI for `auto-promoted` terms.** DR5 requires
  the data be queryable; a review surface for it is not designed here (the
  same gap ADR `2026072901` already flagged for candidate review generally
  — "seam 8 has zero registered tools").

## 6. Implementations

Implemented 2026-08-12 via `ChenWeb/openspec/changes/auto-promoted-governed-terms/`.

**DR1 (concept→term resolution).** `AlignmentsStore.EnsureAcceptedOrCreate`
(`server/api/ontology/keywords/alignment.go`): reuses `EnsureAccepted`'s
existing-alignment branch verbatim; on miss, inserts a new
`kb.ontology_terms` row + prefLabel/altLabel rows + the `aligns_to_term`
assertion in one `withKeywordIdentityMutation` transaction (the same
Postgres advisory lock `EnsureAccepted`/`MergeConcept` already use).
`term_id` is derived as `"measurement:" + conceptID` — folding the
already-deduplicated concept id directly into the term id, rather than
slugifying the human-readable label, to guarantee 1:1 uniqueness with no
collision race. Wired into the metrics pipeline by switching
`ResolvingMetricsStore.resolveAll` (`extract-metrics.go`) from the
read-only `Resolver.ResolveNames` to a per-name `ResolveAndObserve` call —
required, not optional, because D11 concept auto-creation is exclusively a
write-path effect (§Context).

**DR2 (`auto-promoted` status).** Migration `20260812000001` widens
`ontology_terms_status_check`. `terms.AllowedTermStatuses`
(`terms_store.go`) — a Go-side exhaustive map `CreateTerm` validates
against independently of the DB CHECK — updated to match.

**DR3 (structural term synthesis).** `keywords.TermSynthesisInput`
(`CanonicalName`, `Aliases`, `Definition`, `ValueType`, `RangeType`,
`PermittedUnitTermIDs`), populated in `resolveAll` from the triggering
metric row's own `formula_or_definition`/`value_data_type`/
`value_range_type`/`metric_unit` fields — no LLM call. **Schema gap found
and closed:** `kb.ontology_terms` had no columns at all for
`value_type`/`range_type`/`permitted_units` — ADR `2026072901` §3.24
described them as part of a term's content, but `candidates/promote.go`'s
`promoteTerm` never actually persisted them (only `definition`/`scope`
survive candidate promotion today). Migration `20260812000002` adds
`value_type TEXT`, `range_type TEXT`, `permitted_unit_term_ids JSONB`
(nullable, additive — no behavior change for existing callers), plus the
corresponding `terms.Term` struct fields and all three `TermStore` INSERT
sites. Unit resolution (`metric_unit` → a released `unit` term) reuses
existing governed-label-exact-match logic via a new exported
`(*names.Resolver) MatchUnitLabel`, wrapping the previously-private
`matchLabelToReleasedTerm` — deliberately not the `canonicalUnitForm`/
`unitQuantityKindMap` workaround maps spec `2026080403` §17.2 already
flags as "not a pattern to copy."

**DR4 (comparison-matrix acceptance).**
`ComparisonStore.validateMetricKey` (`comparison/store.go`) now accepts
`status IN ('included_in_release', 'auto-promoted')`.

**DR5 (failure rate, not avoidance) — infrastructure only, not a
comparator-model change.** `status='auto-promoted'` is itself the
sampling flag DR5 requires (queryable as a set: `WHERE status =
'auto-promoted'`); no dedicated sampling UI was built (§5 OD4, unchanged
— still open). The pre-rollout observe-mode sample check DR5 calls for is
an operational step for whoever turns `KEYWORD_RESOLVER_MODE` on in a
given environment, not a code deliverable of this change.

**DR6 (retirement).** No code or pipeline-data change was needed —
verified against the live `miner` database that `extract_metric_definitions`
was **already** excluded from both active `kb.pipelines` rows'
`processors[]` arrays, has no `kb.pipeline_rules` gate, and its
`ProcessorSpec` already declares `OnUndetermined: "skip"`
(`processor_plan.go`). The capsule doc and `+CAPSULE.md` were updated to
document this state explicitly rather than leave it implicit.

**Two real bugs found and fixed, neither anticipated by this ADR's
original text:**

1. **`names.Resolver.ResolveAndObserve` discarded its own write-path
   result.** Verified live against `miner` (not just by reading code —
   spec `2026080403`'s own "K7" claim, that `"on"` mode disables
   collection, did not reproduce: `"observe"` and `"on"` behaved
   identically in every test). The actual bug: `ObserveOccurrence` mints a
   provisional concept on a targeted deferred/human_review miss and sets
   it on its own return value, but `ResolveAndObserve` ignored that return
   value (`_, err := r.Family.ObserveOccurrence(...)`) — so a concept was
   genuinely written to `kb.keyword_concepts` while the caller's
   `NameResolution` still reported `status=unresolved`. Without this fix,
   DR1 could never fire for a name seen for the first time — in practice,
   almost every metric name, since `kb.keyword_concepts` had zero
   document-sourced concepts before this change. Fixed in `resolver.go`;
   no prior test covered the path (a genuine gap, not a broken contract).
2. **`AlignmentsStore`'s released-guard rejected the very terms DR1
   creates.** `ensureAccepted`'s guard (`releasedTermExistsSQL`) hardcoded
   `status = 'included_in_release'` — so aligning a concept to a
   freshly auto-created `auto-promoted` term would always fail with
   "not a released term," making `EnsureAcceptedOrCreate` self-defeating.
   Widened to `status IN ('included_in_release', 'auto-promoted')`;
   `names/resolver.go`'s separate `releasedTermSQL` (a different call
   site — raw-name-to-label matching) intentionally stays
   `included_in_release`-only, per DR1's "no fuzzy matching on the
   term-creation path."

Both were caught by live verification against a real (non-mock) `miner`
database and a real concurrency check (two goroutines racing
`EnsureAcceptedOrCreate` for the same never-before-seen concept — exactly
one term/alignment resulted), not by unit tests alone — consistent with
this session's broader finding that this subsystem had never been
exercised end-to-end against real extracted metric data before now.

## Implementations
Refer to `2026081201-impl`

## 7. References

ADR `2026072901` — Ontology Platform and Adaptive Pipeline (this ADR
supersedes its §3.24/DR23 scale assumption and its §8.2/§A.1/§A.2 treatment
of `extract_metric_definitions`):
`KnowledgeStore/doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md`

Spec `2026080403` — Keyword Canonicalization and Reconciliation (D1–D11,
tiers 0–6, `AlignmentsStore.EnsureAccepted`, §16 "the governed-term bridge
and metric integration"):
`KnowledgeStore/doc-repo/specs/202608/2026080403-spec-keyword-canonicalization-and-reconciliation.md`

`KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-metric-definitions-spec.md`
— the processor spec this ADR retires (to be marked retired, not deleted,
per §DR6).

`KnowledgeStore/doc-repo/impl/202608/2026081201-impl-auto-promoted-governed-terms.md` - Auto promote governed terms implementation
