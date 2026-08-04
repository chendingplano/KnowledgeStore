# Metric Name Canonicalization — Addendum to the Keyword Spec

- **DocID:** `doc-2026080404`
- **Status:** Proposed (design only — nothing in this document is implemented)
- **Date:** 2026-08-04
- **Component:** SemOS / ChenWeb — metric extraction, ontology candidates, keyword lexicon
- **Extends:** `2026080403-spec-keyword-canonicalization-and-reconciliation.md` (the keyword module), particularly §14 (the `aligns_to_term` bridge), §14.1–§14.2 (added alongside this addendum), and §9.1 (the mention collector's scope)
- **Design authority:** ADR `2026072901-adr-ontology-platform-and-adaptive-pipeline.md`, DR12 (metrics is the pilot vertical slice), DR23 (metric definition vs. profile; alternative names are lexicon, not term duplicates)
- **Trigger:** a review conversation that asked, concretely, how `extract_metrics` should use the keyword module to canonicalize a metric name — and found that the ADR had already answered this in more detail than the running code reflects.

---

## 0. Why this is a separate document

`2026080403-spec` is the keyword module's own reference: what it is, what's built, what's deferred, what's broken. This addendum is about something else — **how a consumer** (metric extraction) is meant to use it, and what has to exist for that to actually work. It stays a separate document because it is design, not yet implementation: nothing here has shipped, unlike most of what `2026080403-spec` describes.

This document also answers a broader question raised alongside the metric-name question: whether the "existing doc processors don't know about the ontology modules" gap should be closed by modifying those processors, and what happens to two adjacent pieces (the mention collector, and how governed terms handle multiple meanings of the same word) once that question is answered. §3–§5 cover those; §6–§7 return to the metric-name design proper.

---

## 1. The problem, restated

Two independent, already-running processors touch a metric's name and neither resolves it against anything (`2026080403-spec` §14.1, added alongside this document):

- `extract_metrics` extracts a per-document **observation** — a value, unit, condition — with the metric's name as it appeared in that document (`metric_name`, an unresolved free-text qualifier on the resulting `kb.semantic_assertions` row).
- `extract_metric_definitions` extracts a candidate **governed term** — canonical name, aliases, definition — independent of any observed value, into `kb.ontology_candidates`.

"Luminance", "亮度", and "显示亮度" extracted from three different documents today produce three unrelated rows with no way to know they're the same metric. Per DR23, this is exactly the job the keyword lexicon exists to do — it says so explicitly:

> "Alternative names are lexicon, not term duplicates. A metric definition's alias set is the DR15/DR16 keyword lexicon instantiated over metric terms, aligned by `aligns_to_term`. This is what lets 亮度 / 显示亮度 / luminance / brightness in 140 documents reach one row — and it is why the lexicon is not an optional side quest for this application but a prerequisite." (ADR §3.24)

Nothing in the running code performs this resolution. This addendum proposes the concrete shape.

---

## 2. Decision: integrate at the association layer, not the extraction layer

**Existing doc processors, including `extract_metrics`, should not be modified.** This isn't a compromise — it's already how the codebase is built, and the seam that makes it possible already exists and already treats pre-ontology artifact families as first-class.

Verified in `ChenWeb/server/api/ontology/assertions/association_resolver_registry.go` and `associate_semantics.go`: `AssociationResolver` is a registry keyed by `source_artifact_type`, with resolvers already registered for `"metric"` and `"provision"` — both produced by extractors that predate this ontology program and were never modified to participate in it. The registry doesn't distinguish "old" from "new" families; it dispatches on artifact type, uniformly. This is the seam DR11 describes (seam 5, extended from candidate generation through to adjudication) working as designed.

**Consequence:** the "old processors don't know about the ontology stuff, new ones do" split you want gone is not fixed by teaching `extract_metrics` about the keyword module. It's fixed by extending `AssociateSemantics.processMetric` — which already runs downstream of every metric, from any extractor, old or new — with a keyword-resolution step. `extract_metrics` stays exactly as it is: fast, cheap, unaware of governance. The distinction dissolves one layer down, where it already dissolved for units.

The precedent already exists: `resolveUnitTerms` (`associate_semantics.go:323`) maps a raw unit string to a governed QUDT term, "best-effort enrichment, never a gate." §6 below proposes the same shape for metric names.

**A precision worth stating plainly, since it's easy to over-read the parallel: `resolveUnitTerms` is a precedent for the *shape*, not the *mechanism*.** QUDT unit and quantity-kind terms are indeed imported — confirmed in the code comment at `associate_semantics.go:316-321`: "the import stores term rows (`kb.ontology_terms`, 4151 quantity terms)... Lookup is by term_id against the QUDT quantity module." But `resolveUnitTerms` does not use the keyword module at all. It resolves through `canonicalUnitForm()`, a hand-written function that maps a raw unit string (`"mm"`, `"℃"`) directly to the catalog's local-name suffix — a closed, small, well-known vocabulary where a hardcoded mapping is cheap and sufficient, and there is no `kb.keyword_surfaces` row, no normalizer, no tiered lookup involved anywhere in that path. Metric *names* are the opposite case — open-ended, growing, exactly what the keyword module exists for — so §5–§6 below propose actually routing metric-name resolution through `KeywordFamily` (occurrence/surface/lexform/concept), which is a materially different mechanism from what units use today, even though both follow the same "resolve if you can, never force it" policy.

**If a future doc processor needs ontology awareness that can't be expressed as post-hoc association-layer enrichment** (uncommon, but possible — e.g., something that needs to *react* to a resolution mid-extraction rather than annotate after the fact), that is a case-by-case decision, not a blanket policy. Nothing in this document rules it out; it just isn't needed for metrics.

---

## 3. Decision: the mention collector is not part of this

Covered in full in `2026080403-spec` §9.1 (added alongside this document); summarized here because the question came up in the same conversation. There are two different jobs a keyword-surfacing mechanism can do:

1. **Targeted enrichment** — a processor already knows a specific field is a keyword (a metric name, a candidate's alias list). Resolve it directly through `KeywordFamily`. No collector involved.
2. **Corpus-wide recall** — vocabulary that never becomes a structured field, useful only to a retrieval/search consumer that expands queries against the lexicon. This is the collector's job, and that consumer doesn't exist yet (§7.4, §17.1 of the keyword spec).

Metric-name canonicalization is job 1. It needs no collector, and is not blocked by the collector's unwired state.

---

## 4. How governed terms handle a word with two meanings

The other adjacent question: if a metric's canonical identity is meant to land on a governed `metric_definition` term, and the same word can mean different things (the conversation's example was "apple" — fruit vs. company), how does the term layer avoid confusing them?

**It doesn't attempt to, and that's the design.** Verified in `ChenWeb/server/api/ontology/terms/terms_store.go`: there is no lookup-by-label function of any kind. The only way to reach a term is by its already-known `term_id` — a human-chosen, namespaced string (`mea:metric_definition`, and by the same convention something like `bio:apple` vs. `org:apple_inc` for the homonym case). Two meanings of a word simply become two separate term rows, each with its own `kb.ontology_term_labels` rows. No algorithm ever needs to pick between them, because no algorithm ever resolves a bare label into a term_id — a human makes that call exactly once, during candidate review (`kb.ontology_candidates`, `2026080403-spec` §14.2), and it becomes permanent.

This is precisely why `aligns_to_term` is a bridge and not a merge (§14 of the keyword spec): the keyword layer is where automated, ambiguity-tolerant "string → concept" resolution happens — it has to handle input no human has reviewed, so it needs `ambiguous` as a first-class, storable outcome. The term layer is where a human's one-time decision becomes durable and lookup-free. A metric's `metric_definition_term_id`, once set via an accepted `aligns_to_term` assertion, carries no residual homonymy risk — the risk was resolved once, by a person, at the moment the assertion was accepted.

---

## 5. The proposed design: two identifiers, neither one forced

The design in `2026080403-spec`'s D5/D10 (ambiguity is first-class; bias toward under-merging) and the `resolveUnitTerms` precedent (§2 above) both point the same direction: resolve where you can, never overwrite, never force.

Applied to a metric, that means **two** identifiers, at two different trust levels, in addition to the raw extracted name:

| Field | Populated by | Trust level | When empty |
|---|---|---|---|
| `metric_name` (unchanged) | `extract_metrics`, as today | — (provenance) | never — always the literal extracted string |
| `keyword_concept_id` (nullable) | `KeywordFamily.ResolveSurface` on `metric_name`, tiers 0–4 | fast, ungoverned, auto-mergeable | no deterministic keyword match yet |
| `metric_definition_term_id` (nullable) | an **accepted** `aligns_to_term` assertion connecting that keyword concept to a term | governed, reviewed | no human has confirmed the link yet (§4) |
| canonical name shown to users | the term's `pref_label` if `metric_definition_term_id` is set; else `metric_name` | — | falls back cleanly |

**Why two identifiers and not one.** A keyword-tier auto-accept is cheap and unreviewed by design — that's what makes working mode fast. Pinning a metric's display identity to `keyword_concept_id` alone would mean a single bad auto-merge in the lexicon silently misfiles a metric, with no review step in between — exactly the failure D10 (bias toward under-merging) exists to prevent everywhere else in the keyword module. Routing the *authoritative* identity through `aligns_to_term` keeps that guarantee intact for metrics specifically: the metric shows its raw extracted name right up until a human has confirmed the term-level link, never before.

**Why this satisfies "not forced."** At both hops, absence is a valid, expected, permanent-until-resolved state — not an error. A metric with no keyword match, or with a keyword match but no confirmed term, displays exactly as it does today. Nothing about this design requires the earlier resolution to succeed for the metric to remain fully usable.

### 5.1 Which of the four keyword layers this actually exercises, and their real status

Yes — the first hop (`metric_name` → `keyword_concept_id`) is exactly the keyword module's occurrence/surface/lexform/concept chain, with nothing bespoke added on top. Concretely, for a metric named "显示亮度":

1. **occurrence** — `metric_name = "显示亮度"` is the raw string, exactly as `extract_metrics` produced it, handed to `KeywordFamily.ResolveSurface` as a function argument. It is not durably stored anywhere as "an occurrence" — see D1 in `2026080403-spec` §3 for why, and note that fixing that is not on the critical path here; the metric row itself becomes the durable record of what was seen.
2. **surface** — the normalizer computes a `norm_key` from "显示亮度"; if a `kb.keyword_surfaces` row with that `norm_key` already exists (say, one authored earlier with `surface = "luminance"`), tier 1 matches it. If none exists, and the resolution is a miss, "显示亮度" goes to `kb.keyword_unresolved` instead — no new surface row is created from a miss.
3. **lexform** — the `norm_key` value itself is the mechanism that lets "luminance," "显示亮度," and "亮度" (if their normalized forms coincide, or once reconciliation links them as aliases of the same concept) resolve to the same `concept_id`, per the surface→lexform→concept mechanics in `2026080403-spec` §3 D1.
4. **concept** — a hit returns a `concept_id` (e.g., `kwc_luminance`), which is what gets written to the metric's `keyword_concept_id` column (§5's table above).

**Is `lexform` implemented for this to work?** As a value: yes, and correctly, on the path this design uses — `kb.keyword_surfaces.norm_key` is computed and stored properly by `ResolveSurface`'s auto-accept branch. As an entity: no, and it doesn't need to be — nothing in this design (or the keyword module generally) requires a lexform to carry its own metadata; being a shared key value is its entire job. The one caveat: `kb.keyword_unresolved.norm_key` currently holds the raw surface instead of the normalized form (K5, `2026080403-spec` §17.2) — this doesn't block a metric from resolving when a matching surface already exists, but it does mean a *miss* on "显示亮度" and a later miss on "亮度" would sit in the backlog as two separate, undeduplicated entries instead of accumulating hits on one — exactly the kind of corruption item 1 in §6 above is warning about.

**Is `concept` implemented for this to work?** Yes, fully — `kb.keyword_concepts` is a real, working, tested entity (`2026080403-spec` §3 D1, §8.1). The gap is not in the concept layer itself; it's that concepts are only created by a human through the REST API today. Nothing about this design requires automated concept creation — a human can author `kwc_luminance` directly, the same way a human authors the governed term it will eventually `aligns_to`. Automated concept proposal (reconciliation's R5 `new_concept` decision) is a separate, later capability this design does not depend on.

**Net:** every layer this design actually touches — surface and concept — is a real, working implementation. The one layer with an open defect that matters here (lexform, via K5) affects only the miss path, not the hit path, and is already scheduled first in §6's build order.

---

## 6. What has to exist for this to work

None of the following is built. None of it is blocked on anything external — the one genuine blocker in this whole thread (human review of `kb.ontology_candidates` before promotion, `2026080403-spec` §14.2) sits upstream of this list and is already accounted for as designed, not as a gap.

1. **Fix the keyword-module defects first.** §17.2 of `2026080403-spec` lists eleven; K2 (scope ignored), K5 (backlog keyed on raw surface), and N1 (normalizer over-collapses) would each silently corrupt this integration on day one if built on top of them unfixed.
2. **`extract_metric_definitions` resolves its own `canonical_name`/`aliases` through `KeywordFamily`** at harvest time (`ontology_candidate_harvest.go`), instead of leaving them as inert JSON on the candidate payload. A resolution here is also exactly what should populate the candidate's unused `candidate_matches` column (`2026080403-spec` §14.2) — giving the human reviewer a "this looks like something you've already seen" signal instead of three unrelated review items for "luminance," "亮度," and "显示亮度."
3. **An `aligns_to_term` producer.** Currently doesn't exist in any form — no table column, no assertion type, no code path. This is the one piece every other item in this list depends on; it is the actual critical path for DR23's "prerequisite," not a nice-to-have.
4. **`AssociateSemantics.processMetric` gains a `resolveMetricDefinitionTerm` step**, shaped exactly like `resolveUnitTerms`: best-effort, sets `keyword_concept_id`/`metric_definition_term_id` when it can, leaves them null and accepts the assertion anyway when it can't.
5. **Schema:** `kb.metrics` and/or `kb.semantic_assertions` gain `keyword_concept_id` and `metric_definition_term_id` columns (nullable, no constraint forcing either).

Item 1 is a prerequisite for correctness. Items 2–5 are independent of each other and could be sequenced in any order once item 1 lands; item 3 is the one that turns the others from inert plumbing into an actual working bridge.

---

## 7. Documentation impact

**What knowledge changed?** The relationship between `extract_metrics` and `extract_metric_definitions` (there isn't one, and there should be) is now documented, along with the concrete design for closing that gap. The "old vs. new processor" question has a settled answer: integrate at the association layer, don't touch extractors. The mention collector's non-wiring now has a stated, principled reason rather than an implicit one. Governed terms' approach to homonymy — don't resolve by label at all, only by human-chosen id — is now written down where previously it had to be inferred from the absence of a lookup function.

**Which docs/specs/ADRs are affected?** `2026072901-adr` DR23 is the design authority for the metric-definition/lexicon relationship and is unchanged by this document — this addendum operationalizes it, it doesn't revise it. `2026080403-spec` gained §14.1, §14.2, and §9.1 alongside this addendum and should be read together with it.

**Which docs are now stale?** None superseded. This is new design with no prior document covering it.

**What was intentionally left undocumented?** Exact column names and migration numbering for item 5 above, the exact shape of an `aligns_to_term` assertion payload, and prompt text for any LLM-assisted step in candidate-match scoring — these are implementation decisions for whoever builds this slice, not design decisions this addendum needs to pin down.

---

## 8. References

- `2026080403-spec-keyword-canonicalization-and-reconciliation.md` — the keyword module, especially §6.1 (scope defect), §9.1 (collector scope), §14 (`aligns_to_term`), §14.1–§14.2, §17.2 (defects to fix before building on top of this)
- `2026072901-adr-ontology-platform-and-adaptive-pipeline.md` — DR12 §3.13 (metrics as the pilot vertical slice), DR23 §3.24 (metric definition vs. profile; lexicon as prerequisite), DR11 (seams, extensibility without modifying existing dispatch)
- `ChenWeb/server/api/ontology/assertions/associate_semantics.go` — `AssociationResolver` registry, `resolveUnitTerms` (the precedent this design follows), `processMetric`
- `ChenWeb/server/api/doc-processing/extract-metrics.go`, `extract-metric-definitions.go`, `ontology_candidate_harvest.go`
- `ChenWeb/server/api/ontology/candidates/` — `state_machine.go`, `fingerprint.go`, `promote.go`
- `ChenWeb/server/api/ontology/terms/terms_store.go` — confirms no lookup-by-label exists
