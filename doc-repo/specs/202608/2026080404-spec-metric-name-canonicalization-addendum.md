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

**Exactly what that call does, in order** (this is the general `ResolveSurface` pipeline, `2026080403-spec` §3 D1's trace, restated as an ordered list rather than a table since the order matters):

1. Mode gate — no-op if `off` or no DB.
2. **Unconditionally:** insert one row into `kb.keyword_mentions` (`artifact_ref`, `context_text`; `chunk_ref`/`ks_id` always null; no column for the name itself — §17.2 K4).
3. `Kernel.Resolve`: normalize the name → key bundle (pure computation); query `kb.keyword_surfaces`/`kb.keyword_surface_keys` **tier by tier, stopping at the first tier that returns anything** — tier 0 (exact literal-string match) is tried before tier 1 (`norm_key` match); score and adjudicate a verdict.
4. **Unconditionally:** append one row to `kb.semid_decision_log` (does capture the name, in `input`; captures no `artifact_ref`/`context_text`, and shares no key with the mention row from step 2).
5. On `auto_accepted`: write a new surface row only if this exact literal string isn't already on file under that concept. On `deferred`/`ambiguous`: upsert the backlog.

**"Occurrence" is not a step that gets skipped — it's the name for step 2 happening at all, plus its one (incomplete) recorded side effect.** There is no separate occurrence-processing stage; the call itself, and the mention row it writes, are the entirety of what "occurrence" means operationally.

**Three cases for one metric name, because the mechanism behaves differently depending on what's already on file — and getting these three straight is the whole answer to "how does resolution actually work."**

**Case A — exact repeat.** "显示亮度" has been seen and resolved before; a surface row with `surface = "显示亮度"` already exists under `kwc_luminance`.

| Step | What happens |
|---|---|
| Tier 0 | `WHERE s.surface = '显示亮度'` matches directly — **the literal string, byte for byte** |
| Tiers 1–4 | never run — tier 0 already produced a candidate |
| Result | `auto_accepted`, resolves to `kwc_luminance`; no new surface row (the exists-check finds this exact literal string already present) |

**Case B — a spelling/casing variant of a word already known.** "Luminance" (capitalized) is resolved; a surface row `surface = "luminance"` (lowercase) already exists under `kwc_luminance`, with `norm_key = "luminance"`.

| Step | What happens |
|---|---|
| Tier 0 | `WHERE s.surface = 'Luminance'` — **no match**; the stored row is lowercase, and this is a literal string comparison |
| Tier 1 | the query's own `norm_key` (computed fresh from "Luminance" — case-folding makes it `"luminance"`) matches the **stored** `norm_key` on the existing row |
| Result | `auto_accepted`, resolves to `kwc_luminance`. The exists-check (`ConceptID` matches, but `Surface == "Luminance"` does not match the existing `"luminance"` row) finds no exact literal match, so **a second surface row is created automatically** — `surface = "Luminance"`, same `concept_id`, same `norm_key`. Nobody decided this; it falls out of the exists-check plus tier 1's determinism. |

**Case C — a genuinely new word for the same meaning.** "亮度" is resolved for the first time; only `"luminance"` and `"显示亮度"` exist as surfaces under `kwc_luminance`. Nothing named `"亮度"` is on file.

| Step | What happens |
|---|---|
| Tier 0 | no exact match |
| Tier 1 | "亮度"'s own `norm_key` (computed from "亮度" — a different string with no relationship to "luminance" or "显示亮度") matches **nothing stored** — normalizing "亮度" does not, and cannot, produce anything close to `"luminance"`'s or `"显示亮度"`'s `norm_key` |
| Tiers 2–4 | also miss, for the same reason — every tier here operates on keys derived from *this one string*, and "亮度" shares no derived key with either existing surface |
| Result | `deferred` — regardless of the fact that a human reading the document would immediately recognize "亮度" as luminance. The system has no way to know this until someone tells it. |

**Case B is the only one where anything happens "automatically" across two different surface rows, and it only covers spelling/casing variants of one underlying string.** Case C — a different word, in any language, for the same meaning — is never resolved by the normalizer, no matter how the mechanism is exercised, no matter how many times "亮度" is observed. Each unresolved occurrence just increments the same backlog entry's `hits` count; it never becomes a hit on its own. **Someone — a human today, or reconciliation once built — has to author "亮度" as its own surface row under `kwc_luminance` before Case C ever becomes Case A.** DR23's promise ("亮度/显示亮度/luminance/brightness... reach one row") is real, but every one of those four strings has to individually cross from Case C to "on file" before it holds — and nothing in the currently-built system does that crossing automatically. §5.2 below addresses this directly, because at real corpus scale it's the actual bottleneck, not a footnote.

**`lexform → concept`, precisely: the lookup works; the discovery doesn't exist.** Given an *existing* `norm_key`, finding which concept(s) it belongs to is built and correct (Case A/B above, tier 0/1 queries). Deciding, for the first time, that a *new* `norm_key` belongs to a given concept — the step Case C needs — has no automated form today; only a human, through the REST API, does it.

**What `kb.keyword_mentions` holds for a metric name, concretely: today, nothing recoverable.** A mention row gets written on every call once the integration exists (step 2 above), but it carries no reference to which name triggered it — no column exists for it (§17.2 K4). This is the same gap for every caller of `ResolveSurface`, not something specific to metrics.

**Summary — where the gaps actually are, hop by hop:** name→occurrence needs a new caller (§6 item 4, not built). occurrence's own record-keeping (`kb.keyword_mentions`) is broken regardless of caller (K4, pre-existing). occurrence→surface→lexform→concept is **mechanically correct today** for Cases A and B — the miss path (Case C, and Run-1-style cold starts generally) additionally needs K5 fixed to dedupe the backlog properly. Case C's actual resolution — a human or reconciliation deciding a new word belongs to an existing concept — is unautomated today, by design for "human," entirely unbuilt for "reconciliation." concept→governed-term needs the `aligns_to_term` producer, which doesn't exist in any form (§6 item 3).

### 5.2 Why manual curation alone doesn't scale, and what would

This follows directly from Case C above, and it's worth being explicit about rather than leaving as a footnote, because it changes what "closing the gap" actually requires beyond the pilot.

**Lexform isn't under-built — it was never meant to solve this.** Its narrow scope (spelling, casing, whitespace, morphology — never translation, never synonymy) matches UMLS's own LUI layer faithfully: in UMLS, "Eye"/"eye"/"eyes" share an LUI, but "Eye" and "Ocular" don't, even though they mean the same thing — that unification is the CUI (concept) layer's job, done by curation, in UMLS as much as here. So the fact that lexform can't unify "luminance" and "亮度" isn't a simplification introduced by this implementation; it's the layer working as designed. The real question is what automates the concept-layer curation that Case C needs, at a scale beyond what a human can do one link at a time.

**The design has an answer; none of it is built.**

- **Tier 5 (fuzzy: trigram + edit distance)** doesn't help here — it catches misspellings of the *same* word, not different words. Edit distance between "luminance" and "亮度" is total.
- **Tier 6 (embedding/ANN similarity)** is the actual candidate-generation mechanism for this — a multilingual embedding model would plausibly place "luminance" and "亮度" close in vector space, unlike edit distance. It is, by design, *candidate-only*: it would never auto-accept a link on its own, only propose one (§17.1, `2026080403-spec`) — a wrong embedding-driven merge is exactly the silent failure D10 (bias toward under-merging) exists to prevent.
- **Reconciliation R3 (semantic/`pgvector` blocking) + R4/R5 (LLM batch decisions)** is what would turn a tier-6 candidate into a confirmed link at scale, without a human reading every pair by hand.

All three are entirely unbuilt (`2026080403-spec` §11, §17.1) — this addendum's §6 build list deliberately treats them as out of scope for the metrics slice, on the reasoning that the metrics pilot is a bounded domain (呼吸机/医疗器械, DR12) where manual curation might be tractable. **That reasoning is plausible, not verified** — there is no count, anywhere in this document lineage, of how many synonym/translation clusters actually exist even within the bounded pilot corpus. If that number turns out to be large, manual curation stops being a reasonable simplification and becomes the actual bottleneck on whether the pilot's core promise (one row per metric, regardless of how it's phrased) holds at all.

**A smaller, more tractable first step, short of building all of reconciliation:** `2026080403-spec` §14.2 already flags that `kb.ontology_candidates.candidate_matches` is an unused column meant for exactly this signal. A scoped version of tier 6 — an embedding lookup run only at `extract_metric_definitions`' candidate-harvest time, checking a new candidate's `canonical_name`/`aliases` against existing keyword concepts and populating `candidate_matches` with anything close — would surface likely-duplicate metric definitions to a human reviewer without requiring the full general-purpose reconciliation pipeline (batching, negative caching, rewrite-rule promotion, the whole R1–R7 ladder) to exist first. This doesn't close the gap automatically, but it turns "a human has to notice three unrelated proposals are the same metric, unaided" into "a human is shown the likely match and confirms it" — a meaningfully smaller ask, and one bounded to the metric-definition candidate-review flow rather than the full corpus.

---

## 6. What has to exist for this to work

None of the following is built. None of it is blocked on anything external — the one genuine blocker in this whole thread (human review of `kb.ontology_candidates` before promotion, `2026080403-spec` §14.2) sits upstream of this list and is already accounted for as designed, not as a gap.

1. **Fix the keyword-module defects first.** §17.2 of `2026080403-spec` lists eleven; K2 (scope ignored), K5 (backlog keyed on raw surface), and N1 (normalizer over-collapses) would each silently corrupt this integration on day one if built on top of them unfixed.
2. **`extract_metric_definitions` resolves its own `canonical_name`/`aliases` through `KeywordFamily`** at harvest time (`ontology_candidate_harvest.go`), instead of leaving them as inert JSON on the candidate payload. Note per §5.1 Case C: an exact-match resolution here only catches a proposal that repeats a *known* surface — it does **not**, by itself, connect "luminance" and "亮度" as the same thing on first sight. The candidate-match signal this should populate (`candidate_matches`, `2026080403-spec` §14.2) still needs the scoped-embedding step in §5.2 to do anything for genuinely new words in a new language; plain keyword resolution alone only closes this for repeats and spelling variants.
3. **An `aligns_to_term` producer.** Currently doesn't exist in any form — no table column, no assertion type, no code path. This is the one piece every other item in this list depends on; it is the actual critical path for DR23's "prerequisite," not a nice-to-have.
4. **`AssociateSemantics.processMetric` gains a `resolveMetricDefinitionTerm` step**, shaped exactly like `resolveUnitTerms`: best-effort, sets `keyword_concept_id`/`metric_definition_term_id` when it can, leaves them null and accepts the assertion anyway when it can't.
5. **Schema:** `kb.metrics` and/or `kb.semantic_assertions` gain `keyword_concept_id` and `metric_definition_term_id` columns (nullable, no constraint forcing either).
6. **Open, unverified: does manual curation actually cover the pilot domain?** §5.2 — before assuming items 1–5 are sufficient for the pilot to work end to end, get a real count of how many synonym/translation clusters exist in the 呼吸机/医疗器械 corpus. If it's small, human curation through the REST API is plausibly enough. If it's not, the scoped-embedding step in §5.2 (or more of reconciliation) needs to move from "later" into this list.

Item 1 is a prerequisite for correctness. Items 2, 4, and 5 are independent of each other and could be sequenced in any order once item 1 lands; item 3 is the one that turns them from inert plumbing into an actual working bridge. Item 6 should be answered *before* declaring items 1–5 sufficient — it's a scoping question, not a build task, and it's cheap to answer (count the clusters) relative to what it would cost to discover the answer is "no" after the fact.

---

## 7. Documentation impact

**What knowledge changed?** The relationship between `extract_metrics` and `extract_metric_definitions` (there isn't one, and there should be) is now documented, along with the concrete design for closing that gap. The "old vs. new processor" question has a settled answer: integrate at the association layer, don't touch extractors. The mention collector's non-wiring now has a stated, principled reason rather than an implicit one. Governed terms' approach to homonymy — don't resolve by label at all, only by human-chosen id — is now written down where previously it had to be inferred from the absence of a lookup function. §5.1/§5.2 add a precise, tier-by-tier account of what the keyword mechanism actually automates for a metric name (spelling/casing variants of an already-known word) versus what it never will (translations, synonyms — genuinely different words for the same meaning), and name the concrete, currently-unbuilt mechanism (tier 6 embeddings + reconciliation) that would close that second gap at scale. That distinction — not previously stated this precisely anywhere in the document lineage — is the main addition from this revision, and it surfaces an open, unverified scoping question (item 6, §6) rather than a settled answer: whether manual curation alone is enough for the pilot domain depends on a cluster count nobody has taken yet.

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
