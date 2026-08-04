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

### 5.1 The full chain for one metric name, with every hop marked TODAY or PROPOSED

The generic chain (`2026080403-spec` §3 D1) is `name → occurrence → surface → lexform → concept`. A metric name is one instance of "name." Nothing below is metric-specific machinery — it's the same four-layer mechanism every keyword goes through, traced concretely for this one case so every hop can be checked against the running code rather than taken on faith.

**Not via the collector.** To say this once more, plainly, because it's the most natural wrong guess: `extract_metrics` does not "register with" the mention collector, and the collector plays no role in this design at all. The collector reads raw chunk text and tokenizes it itself, blind to what any processor extracted (§9.1). The mechanism below is a **direct call** — `associate_semantics.processMetric` calling `KeywordFamily.ResolveSurface(metricName, ...)` — proposed, not built, entirely separate from the collector.

**Two runs through the chain, because the first time a name is seen behaves differently from every time after.**

**Run 1 — cold start.** A document is processed; `extract_metrics` extracts a metric with `metric_name = "显示亮度"`. No concept for luminance exists yet anywhere in `kb.keyword_concepts`.

| Hop | What happens | Status |
|---|---|---|
| name → occurrence | `associate_semantics.processMetric` calls `ResolveSurface("显示亮度", scope, artifactRef, contextText)` | **PROPOSED** — this call doesn't exist yet (§6 item 4) |
| (inside the call) | a row is written to `kb.keyword_mentions` — `artifact_ref` and `context_text` only, no column for "显示亮度" itself (`2026080403-spec` §3 D1's trace) | **TODAY**, once the call above exists — this side effect needs no new code, `ResolveSurface` already does it |
| occurrence → surface | the kernel normalizes "显示亮度", queries `kb.keyword_surfaces` for a matching `norm_key` — finds **nothing**, because no surface for luminance exists in any language yet | miss |
| (on miss) | verdict is `deferred`; `UpsertUnresolved` writes into `kb.keyword_unresolved`, keyed (once K5 is fixed) on the normalized "显示亮度" | **TODAY**'s code path, contingent on K5 being fixed first (§6 item 1) |
| surface → lexform → concept | **does not happen.** There is nothing to resolve against. | — |
| `keyword_concept_id` / `metric_definition_term_id` on the metric | both stay null; the metric displays "显示亮度" exactly as extracted | as designed (§5 above — "not forced") |

Nothing resolves the first time a name is seen, by design — this is the expected, correct outcome, not a failure. "显示亮度" now sits in the backlog, waiting for a human (or, once built, reconciliation) to notice it and decide it means luminance.

**Run 2 — after curation.** Independently, a human has since authored a concept: `kwc_luminance` (`kb.keyword_concepts`), with surfaces `"luminance"` (`lang='en'`, `label_role='pref'`), `"亮度"` (`lang='zh'`, `label_role='alt'`), and `"显示亮度"` (`lang='zh'`, `label_role='alt'`) — three separate `kb.keyword_surfaces` rows, three separate (and, being different underlying strings, *different*) `norm_key` values, all sharing `concept_id = kwc_luminance`. A new document now produces another metric with `metric_name = "显示亮度"`.

| Hop | What happens | Status |
|---|---|---|
| name → occurrence | same proposed call as Run 1 | **PROPOSED** |
| occurrence → surface | normalizer computes `norm_key` for "显示亮度" — **this time it matches** the `norm_key` on the surface row a human authored | hit |
| surface → lexform | the match happens *because* the query's freshly-computed `norm_key` is identical to the stored one — determinism, not a lookup (`2026080403-spec` §3 D1) | **TODAY**'s mechanism, works correctly on this path |
| lexform → concept | the matched surface row's `concept_id` (`kwc_luminance`) is returned; verdict `auto_accepted` | **TODAY**'s mechanism, works correctly |
| `keyword_concept_id` on the metric | set to `kwc_luminance` | **PROPOSED** — the column doesn't exist yet (§6 item 5) |
| `metric_definition_term_id` on the metric | set **only if** an accepted `aligns_to_term` assertion already connects `kwc_luminance` to a governed term | **PROPOSED**, and blocked on the `aligns_to_term` producer existing at all (§6 item 3) — until then this stays null and the metric still displays its raw name |

**What made Run 2 succeed where Run 1 didn't: curation, not the normalizer.** This is worth stating precisely, because it's easy to over-credit the normalizer here. "Luminance," "亮度," "显示亮度," and (if added) "brightness" are four different strings — normalizing each one produces four **different** `norm_key` values; the normalizer does not, and cannot, know they mean the same thing. What actually unifies them is that a human authored all four as individual surface rows under one `concept_id`. DR23's own promise — "亮度 / 显示亮度 / luminance / brightness in 140 documents reach one row" — is real, but it is fulfilled by curation at the **concept** layer (someone deciding these four strings are the same metric and recording that once), not by anything the lexform layer does automatically. The lexform layer's actual job in this story is narrower and more mechanical: it's what lets a *second* occurrence of the exact string "显示亮度" — spelled and cased identically, or a spelling/morphological variant of it — find the surface a human already authored, without needing to re-ask a human every time. It does not discover that "显示亮度" and "luminance" are related; a human (or, eventually, reconciliation, reading context and proposing links) has to do that once, and only once, for this pair.

**What `kb.keyword_mentions` holds for a metric name, concretely: today, nothing recoverable.** Per the trace above, a mention row gets written on every call once the integration exists, but it carries no reference to "显示亮度" — no column for it exists (§17.2 K4). So the honest answer to "does `kb.keyword_mentions` store the mentions of a name" is: it's supposed to, and as built, it can record *that* a metric-derived call happened at a given artifact, but not *which* metric name triggered it. This is the same K4 gap as for any other caller of `ResolveSurface` — metrics don't make it better or worse, they're just another caller hitting the same hole.

**Summary — where the gaps actually are, hop by hop:** name→occurrence needs a new caller (§6 item 4, not built). occurrence's own record-keeping (`kb.keyword_mentions`) is broken regardless of caller (K4, pre-existing). occurrence→surface and surface→lexform→concept are **already correct**, mechanically, once a surface exists to be found — the miss path (Run 1) additionally needs K5 fixed to dedupe properly. concept→governed-term needs the `aligns_to_term` producer, which doesn't exist in any form (§6 item 3). None of these are hidden or implicit; §6 above is exactly this list, in build order.

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
