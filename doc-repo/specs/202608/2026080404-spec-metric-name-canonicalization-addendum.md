# Metric Name Canonicalization — Addendum to the Keyword Spec

- **DocID:** `doc-2026080404`
- **Status:** Proposed (design only — nothing in this document is implemented)
- **Date:** 2026-08-04
- **Component:** SemOS / ChenWeb — metric extraction, ontology candidates, keyword lexicon
- **Extends:** `2026080403-spec-keyword-canonicalization-and-reconciliation.md` (the keyword module), particularly §14 (the `aligns_to_term` bridge), §14.1–§14.2 (added alongside this addendum), and §9.1 (the mention collector's scope)
- **Design authority:** ADR `2026072901-adr-ontology-platform-and-adaptive-pipeline.md`, DR12 (metrics is the pilot vertical slice), DR23 (metric definition vs. profile; alternative names are lexicon, not term duplicates)
- **Trigger:** a review conversation that asked, concretely, how `extract_metrics` should use the keyword module to canonicalize a metric name — and found that the ADR had already answered this in more detail than the running code reflects.

---

## Revision note (2026-08-05)

**§2 and part of §6 of this document were wrong, not just under-specified, and are corrected below.** An independent review (`doc-repo/bugs/202608/2026080501-bug-name-resolver-qutd.md`) checked the original recommendation — `AssociateSemantics.processMetric` calling `KeywordFamily.ResolveSurface` directly, "shaped like `resolveUnitTerms`" — against the actual code, and found two things this document had gotten backwards. Both were independently re-verified against the code before accepting them:

1. **`associate_semantics.go` is not the clean, generic package the original §2 described.** It self-registers `"metric"` and `"provision"` in its own `init()`; it hardcodes `governedMetricAssertionKinds`, the predicate `mea:measured_by`, and the unit-resolution maps `canonicalUnitForm`/`unitQuantityKindMap` — all domain-specific content, sitting inside what the original §2 called "the seam... working as designed." Adding a metric-specific `resolveMetricDefinitionTerm` step here, as originally proposed, would have added a fourth piece of hardcoded metric knowledge to a package already carrying three — deepening exactly the "old vs. new processor" coupling problem this addendum exists to close, not fixing it.
2. **`resolveUnitTerms` is not a good precedent to copy.** The original §2 called it "a precedent for the shape, not the mechanism" and left it there. What it actually is: a workaround for an incomplete QUDT import. Verified directly in `server/cmd/qudt-import/main.go:238` — `if existing[it.TermID] { continue }` — the importer skips a term entirely, including label creation, if that term_id already exists. 4151 quantity terms exist in `kb.ontology_terms` without labels because of exactly this; no unit-to-quantity-kind relationship import exists anywhere in that file either. `canonicalUnitForm`'s hardcoded map is filling a hole the import left, not an intentional, stable design choice worth extending to metric names.

The corrected design: a new, consumer-agnostic name-resolution interface that neither `extract_metrics` nor `associate_semantics` calls into directly against the keyword module's raw, side-effect-heavy API — replacing §2 below. §5/§6 are updated to match. The four-layer keyword mechanism itself (`2026080403-spec` §3 D1) is unaffected — this changes how a consumer *reaches* it, not what it is.

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

## 2. Decision: a consumer-agnostic name-resolution interface, not a direct call into the keyword module's internals

**Existing doc processors, including `extract_metrics`, should still not be modified.** That part of the original reasoning holds. What was wrong was *where the new logic should go instead* — the original version of this section put it inside `associate_semantics.processMetric`. It shouldn't be there, for two independent reasons, both confirmed against the code:

**First, `associate_semantics.go` is not the clean generic package the original version of this section described.** The `AssociationResolver` *registry mechanism* genuinely is generic — it dispatches on `source_artifact_type` without caring whether the artifact type is old or new. But the *package* built around that registry is not: `init()` (`associate_semantics.go:138`) self-registers `"metric"` and `"provision"` resolvers directly in the ontology package, rather than consumers registering themselves during application composition. `governedMetricAssertionKinds` (a measurement-domain policy map), the literal predicate `mea:measured_by`, and `canonicalUnitForm`/`unitQuantityKindMap` (hardcoded unit-resolution maps) all live in this same file. Adding a metric-specific `resolveMetricDefinitionTerm` step here — the original proposal — would have been a fourth piece of hardcoded metric knowledge added to a package that already has three, not a clean use of a generic seam.

**Second, `KeywordFamily.ResolveSurface` is not a good interface for a consumer to depend on directly.** It mixes a lookup with writes to four different tables in one call (`2026080403-spec` §3 D1's trace); its parameters expose storage concepts (`artifactRef`) that have nothing to do with what a caller is trying to ask; and its caller-supplied `scope` argument is silently ignored during matching (K2). A consumer calling this directly couples itself to an implementation detail that is expected to keep changing (§17.2's eleven defects, the `aligns_to_term` bridge not existing yet, tiers 5–6 unbuilt) rather than to a stable contract.

**The corrected decision:** a new, consumer-agnostic package — `ChenWeb/server/api/ontology/names/` — sitting between any consumer and the keyword module's internals:

```go
type NameResolver interface {
    ResolveName(ctx context.Context, req ResolveNameRequest) (NameResolution, error)
    ResolveNames(ctx context.Context, reqs []ResolveNameRequest) ([]NameResolution, error)
}

type ResolveNameRequest struct {
    Name              string
    Scope             string
    ExpectedTermKinds []string   // e.g. "metric_definition" for a metric, "unit" for a unit
    ExpectedModules   []string
    Language          string
}

type NameResolution struct {
    RawName, NormalizedKey string
    Status                 ResolutionStatus  // term_resolved | lexical_resolved | ambiguous | unresolved | disabled

    ConceptID, ConceptPrefName string        // keyword layer — fast, ungoverned
    TermID, TermPrefName, TermKind, ModuleID string  // governed layer — only set per §4's rule below

    Candidates []NameCandidate
    Method     string
    Confidence float64
}
```

No `MetricID`, no processor name, no consumer table appears anywhere in this contract. A metric asks for `ExpectedTermKinds: ["metric_definition"]`; a unit (once this replaces `canonicalUnitForm`, §6) would ask for `["unit"]`; a future test-method or inventory-item consumer asks for whatever kind fits, with no changes to the resolver itself. Read/write are also explicitly separated (§3 below) — `ResolveName` never writes; observation is a distinct, opt-in call.

**Where consumers call it:** for `extract_metrics`, after the LLM result is parsed and validated but before the metric row is persisted — not inside `associate_semantics` at all:

```go
resolution := resolver.ResolveName(ctx, ResolveNameRequest{
    Name: metric.Name, Scope: knowledgeStoreID,
    ExpectedTermKinds: []string{"metric_definition"},
})
// persist metric.Name unchanged, plus resolution.ConceptID and resolution.TermID when set
```

`extract_metrics` itself still isn't modified in the sense that matters — no LLM prompt, no extraction logic changes; what changes is that the *consumer of its output*, before persistence, makes one call to a stable, generic interface rather than nothing at all. `AssociateSemantics` keeps its existing job (building qualified semantic assertions from already-resolved data); it stops being where name discovery happens.

### 2.1 Read and write are separate operations, not one call that always does both

`KeywordFamily.ResolveSurface` (§2 above) always writes — a mention row, a decision-log row, and either a surface or a backlog row — on every call, with no way to just ask "what does this resolve to" without also recording it as an observation. That's a real defect independent of everything else in this section: a debugging tool, a UI autocomplete, a test, or a reprocessing run has no way to *look up* a name without *also* polluting the mention/decision-log/backlog tables as a side effect.

`names.Resolver.ResolveName` is read-only. A separate, explicit call does the writing:

```go
ObserveName(ctx context.Context, occurrence NameOccurrence) error
// or, as a convenience that does both:
ResolveAndObserve(ctx context.Context, req ResolveNameRequest, occurrence NameOccurrence) (NameResolution, error)
```

Consumers that want evidence to accumulate (the common case — most callers should default to `ResolveAndObserve`) get it explicitly, not as an unavoidable side effect of asking a question.

The occurrence record this writes should be shaped to actually answer "what was seen, where" — unlike today's `kb.keyword_mentions` (§17.2 K4), which has no column for the name itself. At minimum: `artifact_type`, `artifact_id`, `field_path` (consumer-supplied provenance, e.g. `"metric_name"` — meaningful to the consumer, opaque to the resolver), `raw_name`, `scope`, `context`, `chunk_ref`, `concept_id` (nullable), `term_id` (nullable), `resolution_status`, and a link to the decision-log row from the same call — closing the gap named in `2026080403-spec` §3 D1's trace, where the mention row and the decision-log row from one call currently share no key at all.

### 2.2 Resolution semantics: lexical and governed identity are different things, and the contract must say so

A name can land in one of five states, and all five are normal results, not errors:

| Status | Meaning |
|---|---|
| `term_resolved` | exactly one released governed term is established |
| `lexical_resolved` | a keyword concept was found, but no governed alignment exists yet |
| `ambiguous` | multiple equally valid concepts or terms remain |
| `unresolved` | no match |
| `disabled` | the resolver is intentionally off (mirrors `KEYWORD_RESOLVER_MODE=off`, §7.4 of the keyword spec) |

**The rule that matters: `TermID` is set only by one of two things — an exact match against a released term's governed label, or an accepted, reviewed `aligns_to_term` alignment.** A lexical auto-match (tiers 0–4, `2026080403-spec` §7.1) must never, by itself, produce a `TermID`. This is the same governance boundary §14 of the keyword spec already draws between the ungoverned lexicon and governed terms — this contract is what makes that boundary visible and enforceable at the one place a consumer actually touches it, rather than something a caller has to reconstruct by separately checking two different systems.

### 2.3 What stays in `AssociateSemantics`, what moves out

`AssociateSemantics.Run`, the `AssociationResolver` registry, and the generic assertion/evidence lifecycle stay — those genuinely are generic. What doesn't belong there: `processMetric`'s and `processProvision`'s concrete bodies, `governedMetricAssertionKinds`, the hardcoded `mea:` predicate, and (§2.4 below) the unit-resolution maps. These move to consumer-specific adapter packages, and the ontology package stops self-registering `"metric"`/`"provision"` in its own `init()` — registration happens during application composition, or the consumer package provides its own adapter. This doesn't eliminate `AssociateSemantics`'s role: it still builds and adjudicates qualified assertions from already-resolved data (`ConceptID`/`TermID` now arriving pre-resolved from `names.Resolver`, rather than being discovered here). It stops being where discovery happens.

This is a real restructuring, not a rename, and it doesn't have to land before metrics work — §6 sequences it as follow-up, not a blocker.

### 2.4 The same correction applies to `resolveUnitTerms` — but it needs a data fix first, not just a code change

`resolveUnitTerms`/`canonicalUnitForm`/`unitQuantityKindMap` should eventually be replaced by the same `ResolveName(Name: "ms", ExpectedTermKinds: ["unit"])` call metrics use — but doing that today would just move the same broken lookup behind a nicer interface, because the underlying data isn't there yet. Two concrete gaps, both confirmed in `server/cmd/qudt-import/main.go`:

1. **Existing term IDs are skipped, including their labels.** Line 238: `if existing[it.TermID] { continue }` — if a term row was created before its label was, a re-run never backfills the label. This is why 4151 imported quantity terms have no `kb.ontology_term_labels` rows and a label-based lookup would resolve nothing (the comment already on `resolveUnitTerms` says as much).
2. **No unit-to-quantity-kind relationship is imported at all.** Units, quantity kinds, and dimensions are each imported as independent terms with their own external-IRI mappings; nothing links a unit term to the quantity kind it measures.

Fix order: backfill labels for existing quantity terms (fix the importer's skip condition, or add a separate backfill pass), import the unit→quantity-kind relationships as governed data, then retire the hardcoded maps in favor of exact governed-label resolution through `names.Resolver`. This is real work, independent of the metric-name path, and shouldn't block it — but the original framing of `resolveUnitTerms` as a pattern *worth copying* was wrong, and item 4.4 in §6 below reflects the correction.

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

The design in `2026080403-spec`'s D5/D10 (ambiguity is first-class; bias toward under-merging) points one direction, and §2.2's resolution-semantics rule points the same way independently: resolve where you can, never overwrite, never force.

Applied to a metric, that means **two** identifiers, at two different trust levels, in addition to the raw extracted name — populated by one call to `names.Resolver.ResolveName` (§2), not by a direct call into the keyword module:

| Field | Populated by | Trust level | When empty |
|---|---|---|---|
| `metric_name` (unchanged) | `extract_metrics`, as today | — (provenance) | never — always the literal extracted string |
| `keyword_concept_id` (nullable) | `resolution.ConceptID`, set whenever status is `lexical_resolved` or `term_resolved` | fast, ungoverned, auto-mergeable | status is `unresolved` or `ambiguous` |
| `metric_definition_term_id` (nullable) | `resolution.TermID`, set **only** when status is `term_resolved` — an accepted `aligns_to_term` assertion, per §2.2's rule | governed, reviewed | status is anything else (§4) |
| canonical name shown to users | `resolution.TermPrefName` if `metric_definition_term_id` is set; else `metric_name` | — | falls back cleanly |

**Why two identifiers and not one.** A keyword-tier auto-accept is cheap and unreviewed by design — that's what makes working mode fast. Pinning a metric's display identity to `keyword_concept_id` alone would mean a single bad auto-merge in the lexicon silently misfiles a metric, with no review step in between — exactly the failure D10 (bias toward under-merging) exists to prevent everywhere else in the keyword module. Routing the *authoritative* identity through `aligns_to_term` keeps that guarantee intact for metrics specifically: the metric shows its raw extracted name right up until a human has confirmed the term-level link, never before.

**Why this satisfies "not forced."** At both hops, absence is a valid, expected, permanent-until-resolved state — not an error. A metric with no keyword match, or with a keyword match but no confirmed term, displays exactly as it does today. Nothing about this design requires the earlier resolution to succeed for the metric to remain fully usable.

### 5.1 The full chain for one metric name, with every hop marked TODAY or PROPOSED

The generic chain (`2026080403-spec` §3 D1) is `name → occurrence → surface → lexform → concept`. A metric name is one instance of "name." Nothing below is metric-specific machinery — it's the same four-layer mechanism every keyword goes through, traced concretely for this one case so every hop can be checked against the running code rather than taken on faith.

**Not via the collector, and — per the 2026-08-05 revision above — not via `associate_semantics` either.** `extract_metrics` does not "register with" the mention collector; the collector reads raw chunk text and tokenizes it itself, blind to what any processor extracted (§9.1), and plays no role in this design. The mechanism below is a call to `names.Resolver.ResolveName(metricName, ...)` (§2), made by whatever consumes `extract_metrics`' output before persisting a metric row — not a call to `KeywordFamily.ResolveSurface` from inside `associate_semantics.processMetric`, which was this document's original (incorrect) proposal. `names.Resolver` internally uses the same tier 0–4 mechanism traced below; what changed is who calls it and through what contract, not what happens once the call is made.

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

**To be precise about what "automatically" means here, since it's easy to mis-state in either direction: "Luminance" and "luminance" *do* end up as two different rows in `kb.keyword_surfaces`** — surface means one exact string, so two different strings are always two different rows, full stop. **What does *not* happen is anything requiring a human to "merge" them** — they're never two different concepts in the first place; the second row is created *already pointing at* the same `concept_id` as the first, because it's only created after tier 1 found that concept. "Merge," in this system, is a specific, heavier operation (`MergeConcept`, tombstoning one whole *concept* into another) reserved for when two independently-created `concept_id`s — say, two curators separately authoring "luminance" without knowing about each other — turn out to mean the same thing. That's a different failure mode from Case B, and nothing about Case B produces it.

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
2. **Build the `names.Resolver` interface and its `KeywordFamily`-backed implementation** (§2) — the `ResolveName`/`ResolveNames`/`ResolveAndObserve` contract, and a shaped occurrence record for `ObserveName` (§2.1) to replace `kb.keyword_mentions`' incomplete shape. This is new package-level work, not present in the original version of this document, and everything below depends on it existing rather than consumers calling `KeywordFamily.ResolveSurface` directly.
3. **`extract_metric_definitions` resolves its own `canonical_name`/`aliases` through `names.Resolver`** at harvest time (`ontology_candidate_harvest.go`), instead of leaving them as inert JSON on the candidate payload. Note per §5.1 Case C: an exact-match resolution here only catches a proposal that repeats a *known* surface — it does **not**, by itself, connect "luminance" and "亮度" as the same thing on first sight. The candidate-match signal this should populate (`candidate_matches`, `2026080403-spec` §14.2) still needs the scoped-embedding step in §5.2 to do anything for genuinely new words in a new language; plain keyword resolution alone only closes this for repeats and spelling variants.
4. **An `aligns_to_term` producer**, plus the schema fix it depends on: `kb.semantic_assertions.subject_ref_kind`'s `CHECK` constraint currently allows only `('object_node', 'ontology_term', 'assertion', 'artifact', 'literal')` — **verified directly against `20260801000001_create_kb_semantic_assertions.sql`** — with no `'keyword_concept'` value. If `aligns_to_term` assertions are meant to use this same table (per DR9's assertion/evidence schema, which this design assumed without checking), a keyword concept cannot be an assertion subject until this constraint is extended. This is the one piece every other item in this list depends on; it is the actual critical path for DR23's "prerequisite," not a nice-to-have — and it's more work than previously stated, because the schema itself needs to change first.
5. **`extract_metrics`' consumer calls `names.Resolver.ResolveName`** before the metric row is persisted (§2), setting `keyword_concept_id`/`metric_definition_term_id` per §2.2's rule — replacing the original, incorrect proposal to add this inside `AssociateSemantics.processMetric`.
6. **Schema:** `kb.metrics` and/or `kb.semantic_assertions` gain `keyword_concept_id` and `metric_definition_term_id` columns (nullable, no constraint forcing either).
7. **Open, unverified: does manual curation actually cover the pilot domain?** §5.2 — before assuming items 1–6 are sufficient for the pilot to work end to end, get a real count of how many synonym/translation clusters exist in the 呼吸机/医疗器械 corpus. If it's small, human curation through the REST API is plausibly enough. If it's not, the scoped-embedding step in §5.2 (or more of reconciliation) needs to move from "later" into this list.

**Deliberately sequenced after the metrics pilot, not blocking it:** moving `processMetric`/`processProvision` out of `AssociateSemantics` into consumer-specific adapters and un-registering them from the shared `init()` (§2.3); backfilling QUDT labels and importing unit→quantity-kind relationships so `resolveUnitTerms` can retire in favor of `names.Resolver` (§2.4). Both are real architectural debt, confirmed real by the same review that corrected this document — but neither has to be paid down before one metric name resolves correctly, and DR12's own vertical-slice framing argues for proving the pilot before generalizing further.

Item 1 is a prerequisite for correctness. Items 2, 3, and 6 are independent of each other and could be sequenced in any order once item 1 lands, but item 2 has to exist before 3, 5, or 6 have anything to call. Item 4 is the one that turns the others from inert plumbing into an actual working bridge, and now includes a schema change this document previously missed. Item 7 should be answered *before* declaring items 1–6 sufficient — it's a scoping question, not a build task, and it's cheap to answer (count the clusters) relative to what it would cost to discover the answer is "no" after the fact.

---

## 7. Documentation impact

**What knowledge changed, as of the 2026-08-05 revision?** Two of this document's own core recommendations were wrong, not merely under-specified, and are now corrected: name resolution should happen behind a new, consumer-agnostic `names.Resolver` interface, not via a direct call from `AssociateSemantics.processMetric` into `KeywordFamily.ResolveSurface` — because `associate_semantics.go` is not the clean generic package the original version described (it self-registers `"metric"`/`"provision"` and hardcodes measurement-domain policy in its own `init()`), and because `ResolveSurface` itself is not a stable interface worth a consumer depending on directly (it mixes read with four different writes, per `2026080403-spec` §3 D1's trace). `resolveUnitTerms`, previously cited as a precedent worth following, is now understood to be a workaround for an incomplete QUDT import (verified: the importer skips existing term IDs before backfilling their labels, and never imports unit-to-quantity-kind relationships) rather than an intentional, stable pattern. A previously-unstated schema gap was also found: `kb.semantic_assertions.subject_ref_kind` cannot represent a keyword concept as an assertion subject today, which the `aligns_to_term` producer will need addressed.

Earlier findings still stand: the relationship between `extract_metrics` and `extract_metric_definitions` (there isn't one, and there should be), the mention collector's non-wiring having a stated reason, governed terms' approach to homonymy, and the precise tier-by-tier account in §5.1/§5.2 of what the keyword mechanism automates for a metric name versus what it never will.

**Source of the correction:** `doc-repo/bugs/202608/2026080501-bug-name-resolver-qutd.md`, an independent review requested specifically to check whether concerns raised about this document's reasoning were real problems — they were, on every concretely checkable claim, independently re-verified against the code before this revision was written.

**Which docs/specs/ADRs are affected?** `2026072901-adr` DR23 is the design authority for the metric-definition/lexicon relationship and is unchanged by this document — this addendum operationalizes it, it doesn't revise it. `2026080403-spec` gained §14.1, §14.2, and §9.1 alongside this addendum and should be read together with it.

**Which docs are now stale?** None superseded. This is new design with no prior document covering it.

**What was intentionally left undocumented?** Exact column names and migration numbering for item 5 above, the exact shape of an `aligns_to_term` assertion payload, and prompt text for any LLM-assisted step in candidate-match scoring — these are implementation decisions for whoever builds this slice, not design decisions this addendum needs to pin down.

---

## 8. References

- `doc-repo/bugs/202608/2026080501-bug-name-resolver-qutd.md` — the independent review that corrected §2 and §6 of this document; source of the `names.Resolver` design and the `subject_ref_kind`/QUDT-importer findings
- `2026080403-spec-keyword-canonicalization-and-reconciliation.md` — the keyword module, especially §6.1 (scope defect), §9.1 (collector scope), §14 (`aligns_to_term`), §14.1–§14.2, §17.2 (defects to fix before building on top of this)
- `2026072901-adr-ontology-platform-and-adaptive-pipeline.md` — DR12 §3.13 (metrics as the pilot vertical slice), DR23 §3.24 (metric definition vs. profile; lexicon as prerequisite), DR11 (seams, extensibility without modifying existing dispatch)
- `ChenWeb/server/api/ontology/assertions/associate_semantics.go` — `AssociationResolver` registry, `init()` (self-registration), `governedMetricAssertionKinds`, `resolveUnitTerms`/`canonicalUnitForm`/`unitQuantityKindMap` (confirmed workarounds, not precedents), `processMetric`, `processProvision`
- `ChenWeb/server/cmd/qudt-import/main.go` — confirms the existing-term-ID skip (line 238) that leaves imported terms without labels
- `ChenWeb/project_migrations/20260801000001_create_kb_semantic_assertions.sql` — confirms `subject_ref_kind`'s `CHECK` constraint excludes `'keyword_concept'`
- `ChenWeb/server/api/doc-processing/extract-metrics.go`, `extract-metric-definitions.go`, `ontology_candidate_harvest.go`
- `ChenWeb/server/api/ontology/candidates/` — `state_machine.go`, `fingerprint.go`, `promote.go`
- `ChenWeb/server/api/ontology/terms/terms_store.go` — confirms no lookup-by-label exists

---

## Appendix A. Exact no-LLM trace: `Luminance`, `亮度`, and `显示亮度` → one canonical name

This appendix answers one question narrowly and operationally: **once the keyword lexicon knows that `Luminance`, `亮度`, and `显示亮度` are names for the same metric, how does it resolve all three to one canonical name without an LLM?** It distinguishes the one-time act of establishing that knowledge from the cheap online lookup that uses it. The distinction is essential: deterministic lookup can reuse known equivalence, but string normalization alone cannot discover that a previously unseen English word and Chinese word have the same meaning.

### A.1 The intended result

For the metrics pilot, the three inputs should return the same stable lexical identity and the same current canonical display name:

| Input name | Keyword concept | Canonical name |
|---|---|---|
| `Luminance` | `kw:luminance` | `Luminance` |
| `亮度` | `kw:luminance` | `Luminance` |
| `显示亮度` | `kw:luminance` | `Luminance` |

`kw:luminance` is illustrative; `concept_id` is deliberately opaque and must not be derived from the label. `Luminance` is the mutable canonical display name stored in `kb.keyword_concepts.pref_label`. The identity is the concept id, not the string. A later rename of the preferred label must not change what any of the three inputs resolves to.

This result requires no LLM on the document-processing path. Every online operation shown below is normalization, SQL lookup, deterministic scoring, and deterministic adjudication. Tier 1 has a supporting `(norm_key, scope)` index; tier 0 currently lacks a corresponding `(surface, scope)` index, which is flagged in A.7.

### A.2 One-time lexicon preparation: establish the equivalence cluster

Before online resolution can work, the database must contain one concept and one surface row for each semantically distinct spelling or translation:

```text
kb.keyword_concepts
concept_id       pref_label    scope       status
kw:luminance     Luminance     ventilator  active

kb.keyword_surfaces
surface          norm_key      concept_id       label_role  alias_type   lang  scope
Luminance        luminance     kw:luminance     pref        synonym      en    ventilator
亮度              亮度           kw:luminance     alt         translation  zh    ventilator
显示亮度           显示亮度        kw:luminance     alt         translation  zh    ventilator
```

The three surface strings do **not** need to normalize to the same key. They deliberately have three different `norm_key` values. Their equivalence is represented by all three rows carrying the same `concept_id`. This is how the module represents synonymy and translation without asking an LLM on every lookup.

How can this cluster be established without an LLM?

1. Import an authoritative metric glossary whose preferred name and aliases already state the relationship.
2. Import reviewed aliases from promoted `metric_definition` content.
3. Seed a curated metrics vocabulary for the bounded ventilator/medical-device pilot.
4. Let a human create the concept and attach the three surfaces through the existing REST APIs.
5. Once tier 3's scoring defect in A.7 is fixed, use a small, explicitly reviewed literal rewrite such as `亮度 → Luminance` as another deterministic bridge. Direct surface membership remains preferable for durable aliases because it records each name as first-class lexicon data rather than treating semantic equivalence as a text rewrite.

The running implementation currently supports only item 4 end to end. It has REST endpoints and stores for concepts, surfaces, and rewrite rules, but the tier-3 scoring bug prevents a rewrite between genuinely different keys from producing an accepted result. It has no metrics glossary importer, promoted-term alias backfill, or curated metric seed. As verified on 2026-08-05 with counts from `kb.keyword_concepts` and `kb.keyword_surfaces`, the live `chenweb_test` database had three keyword concepts and four surfaces, but no luminance concept or any of the three example surfaces. Therefore this example is the required target state, not a claim about current data.

### A.3 Online resolution, step by step

The proposed consumer call is `names.Resolver.ResolveName`; that interface is not built. The actual implementation underneath it today is `KeywordFamily.ResolveSurface`, `KeywordFamily.CandidateNodes`, and the shared `semid.Kernel`. Assuming the three rows in A.2 exist and the scope defect described in A.5 is fixed, each input follows the same no-LLM path. Every step below is marked **TODAY** when the mechanism exists in current code and **PROPOSED** when it belongs to the unbuilt facade; the `ventilator` scope on today's SQL is conditional on fixing K2.

#### Input 1: `Luminance`

1. **PROPOSED:** the consumer supplies the raw name and scope: `ResolveName(Name: "Luminance", Scope: "ventilator", ExpectedTermKinds: ["metric_definition"])`.
2. **TODAY:** `KeywordNormalizer.Normalize("Luminance")` applies NFKC, whitespace normalization, case folding, and the remaining deterministic normalizer stages. Its canonical key is `luminance`.
3. **TODAY SQL; PROPOSED scope behavior:** tier 0 queries `kb.keyword_surfaces` for the exact literal surface and scope. The query exists today, but it receives `_` until K2 is fixed; the intended query is:

   ```sql
   WHERE s.surface = 'Luminance' AND s.scope = 'ventilator'
   ```

4. **TODAY:** the row returns candidate node `kw:luminance`. The generic kernel scores its stored `norm_key` against the input key. Both are `luminance`, so the score is `1.0`.
5. **TODAY:** `KeywordFamily.AutoAcceptPolicy` allows an unambiguous keyword match at score `>= 0.8`. There is one top candidate, so `Adjudicate` returns `auto_accepted` and the kernel sets `ResolvedNodeID = "kw:luminance"`.
6. **PROPOSED:** the name resolver loads `kb.keyword_concepts['kw:luminance']` and returns its `pref_label`, `Luminance`, as the lexical canonical name.

#### Input 2: `亮度`

1. **PROPOSED:** the consumer supplies `Name: "亮度"` with the same scope and expected term kind.
2. **TODAY:** the deterministic normalizer leaves these CJK characters unchanged, producing canonical key `亮度`.
3. **TODAY SQL; PROPOSED scope behavior:** tier 0 finds the exact `亮度` surface row; it uses the caller-supplied scope only after K2 is fixed.
4. **TODAY:** that row also carries `concept_id = 'kw:luminance'`. Its stored key equals the input key, so the score is `1.0`.
5. **TODAY:** the single candidate is auto-accepted.
6. **PROPOSED:** loading that concept returns `pref_label = "Luminance"`. The returned canonical name is therefore `Luminance`, even though the raw input and normalized key remain `亮度`.

#### Input 3: `显示亮度`

1. **PROPOSED:** the consumer supplies `Name: "显示亮度"` with the same scope and expected term kind.
2. **TODAY:** normalization produces canonical key `显示亮度`.
3. **TODAY SQL; PROPOSED scope behavior:** tier 0 finds the exact `显示亮度` row; it uses the caller-supplied scope only after K2 is fixed.
4. **TODAY:** that row again points to `kw:luminance`; exact-key scoring produces `1.0`.
5. **TODAY:** the single candidate is auto-accepted.
6. **PROPOSED:** the resolver reads the same concept and returns the same canonical label, `Luminance`.

The important observation is that the resolver does not compare `Luminance` with `亮度` during these online calls. It does not translate either string and does not invoke an LLM. Each string independently performs a SQL lookup and reaches the same already-established concept id. The shared concept supplies the canonical name.

### A.4 What happens for spelling and casing variants

If only lowercase `luminance` is stored and the input is `Luminance`, tier 0 misses because it compares literal strings. Tier 1 then matches the normalized key `luminance`, returns `kw:luminance`, and auto-accepts it. The current `ResolveSurface` implementation then attempts to create a new `Luminance` surface row under that already-resolved concept. If the existing lowercase row uses `label_role = 'pref'`, the new `alt` row can be inserted. If an `alt` row with the same `(norm_key, concept_id, scope)` already exists, the table's uniqueness constraint rejects the second `alt` row and `ResolveSurface` silently ignores the creation error. Resolution still succeeds, but automatic surface accumulation is not reliable or fully idempotent under the current schema/error handling. No LLM is involved in either outcome.

The same mechanism covers normalization-equivalent variations such as compatible Unicode forms, whitespace differences, and the limited morphology handled by the normalizer. It does **not** establish synonymy or translation between different keys; that relationship comes from the shared concept membership prepared in A.2.

### A.5 Real ambiguity: do not force a canonical name

Suppose `亮度` is stored under two active concepts in the same scope—for example, one rigorously defined photometric luminance metric and one looser display-brightness concept. Tier 0 returns both concept ids with the same top score. `semid.Adjudicate` returns `ambiguous`, not `auto_accepted`, because `MaxCandidates` is `1`. No canonical name should be returned until scope or reviewed context selects one concept.

This is the correct no-LLM behavior: deterministic resolution is cheap, but it must refuse to guess. Scope is the intended first disambiguator. Context-based deterministic disambiguation is not implemented.

### A.6 What the current implementation gets right

- Tiers 0 and 1 are deterministic SQL lookups and work for correctly stored global-scope data; tier 1 is indexed, while tier 0 still needs the index identified in A.7.
- The normalizer is deterministic and versioned.
- Multiple exact surface rows can point to one concept, which is the core structure needed for this example; normalization-equivalent rows still need the candidate-deduplication fix in A.7.
- A tied top score produces `ambiguous`; it does not silently select one concept.
- The auto-accept policy requires one unambiguous candidate at score `>= 0.8`.
- The rewrite-rule store and tier-3 candidate lookup exist, although the scoring defect in A.7 prevents a different-key rewrite from completing successfully.
- `kb.keyword_concepts.pref_label` already provides the canonical lexical display name.

### A.7 What is missing or incorrect today

| Gap | Consequence for this example |
|---|---|
| No metrics seed/import/backfill path | The required `kw:luminance` cluster is never created automatically. The live database does not contain it. |
| No consumer calls the resolver for `metric_name` | Even a correctly seeded cluster would not currently canonicalize an extracted metric. |
| Proposed `names.Resolver` is not built | The current API returns a `ResolvedNodeID`, not the concept's `pref_label`; it therefore does not yet return a canonical name in one call. |
| K2: caller scope is ignored during matching | `Kernel.Resolve` calls `KeywordFamily.Scope`, which always returns `_`. A row stored under intended scope `ventilator` cannot be found. The A.2 example works in current code only if its rows are incorrectly stored in global scope `_`. |
| K3: surface creation trusts caller-supplied `norm_key` | A bad API payload can make an exact surface produce the wrong score or make later tier-1 lookup fail. The server must derive the key itself. |
| K6: REST resolver reads the environment variable directly | An unset mode is treated as active by the REST path instead of failing closed as `off`. |
| Tier 0 has no `(surface, scope)` index | Exact lookups use `WHERE s.surface = $1 AND s.scope = $2`, but the schema indexes `(norm_key, scope)`, not `(surface, scope)`. The main exact-match path can degrade to a table scan as the lexicon grows, contrary to the latency goal. |
| Candidate rows are not deduplicated by `concept_id` | Tier queries return one candidate per matching surface row. Multiple matching rows belonging to the same concept can be counted as tied candidates and incorrectly produce `ambiguous`; candidate generation should collapse them to one candidate per concept before adjudication. |
| Tier 3 scores the rewrite target against the original input | `CandidateNodes` may find `Luminance` after rewriting `亮度`, but `Kernel.Resolve` still scores that candidate with the original `亮度` key. The score is `0`, so the kernel drops the candidate and returns `deferred`. Rewrite rules cannot currently bridge genuinely different names as intended. |
| Tiers 2 and 4 are not operational | No path populates `kb.keyword_surface_keys`; tier 4's initials logic is also incorrect. These do not block the three exact surfaces, but they reduce deterministic variant coverage. |
| Auto-added surface errors are ignored | A normalization-equivalent `alt` row can violate the current uniqueness constraint. `ResolveSurface` ignores the failed `CreateSurface` result, so resolution succeeds while the expected alias row is not recorded. |
| Merged/deprecated concept handling is incomplete | Candidate queries do not filter concept status or follow `merged_into`; a lookup can return a tombstoned concept instead of the surviving canonical concept. |
| Occurrence/audit writes are incomplete and inseparable from lookup | `ResolveSurface` writes on every lookup, while `kb.keyword_mentions` does not record which name was observed or link to the decision row. This does not change the match but breaks provenance and clean API semantics. |
| Auto-added surfaces use hardcoded provenance `llm:observe` | Tier-1 attachment is deterministic and makes no LLM call, so the stored provenance is factually misleading and prevents accurate cost/audit interpretation. |
| No accepted `aligns_to_term` bridge | The resolver cannot continue from lexical concept `kw:luminance` to a governed `metric_definition` term. This does not prevent returning the lexical canonical name, but it prevents governed metric identity. |

Most importantly, **tiers 5–6 and an LLM reconciler are not prerequisites for this example's normal runtime behavior**. They are possible ways to propose relationships for previously unseen names. The metrics-first implementation can prove the core requirement without them by loading a small, reviewed metric lexicon and then demonstrating that all documented aliases resolve through tiers 0–4 with zero model calls.

### A.8 Recommended metrics-first acceptance test

The first end-to-end proof should use a database fixture containing exactly the concept and three surfaces in A.2, then call the public name-resolution interface three times. It passes only if:

1. all three calls make zero LLM requests;
2. with only the A.2 fixture, all three return `lexical_resolved`, never `ambiguous` or `unresolved`; an extended fixture may expect `term_resolved` only if it also supplies a released metric-definition term and accepted alignment;
3. all three return the same `ConceptID`;
4. all three return canonical name `Luminance`;
5. all three preserve their distinct raw input strings;
6. repeated calls are idempotent and do not create duplicate surfaces;
7. the requested `ventilator` scope is actually used;
8. adding a second `亮度` concept in the same scope changes that input to `ambiguous` rather than selecting either concept;
9. disabling the resolver produces `disabled` and performs no writes;
10. no keyword or ontology code contains a metric-specific branch to make the fixture pass.

Once this test passes, extending the same interface to another artifact means choosing the artifact's name field, scope, and optional expected governed term kind—not creating another canonicalization engine.
