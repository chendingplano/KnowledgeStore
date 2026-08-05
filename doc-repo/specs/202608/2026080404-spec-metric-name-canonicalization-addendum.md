# Metric Name Canonicalization — Addendum to the Keyword Spec

- **DocID:** `doc-2026080404`
- **Status:** Proposed addendum — its decisions are unimplemented; underlying keyword tables, stores, REST APIs, and tier 0–4 code are partial existing implementation
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

Appendix A was corrected again on 2026-08-05 after review exposed an invalid starting assumption: it had traced only the lookup that occurs *after* the lexicon already knows the three example names, without explaining how an empty system acquires that knowledge. The replacement appendix traces warm-start resource import, multilingual normalization, pre-service reconciliation, online lookup, and continued vocabulary growth. The resulting design permits LLM use during batched vocabulary growth, but never requires an LLM call for each `ResolveName` request.

---

## 0. Why this is a separate document

`2026080403-spec` is the keyword module's own reference: what it is, what's built, what's deferred, what's broken. This addendum is about something else—**how a consumer** (metric extraction) is meant to use it, and what has to exist for that to actually work. It stays separate because none of this addendum's proposed decisions has shipped, even though it evaluates and reuses partial implementation documented by `2026080403-spec`.

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

`KeywordFamily.ResolveSurface` (§2 above) attempts writes—a mention row, a decision-log row, and either a surface or a backlog row—on every call, with no way to just ask "what does this resolve to" without also recording it as an observation. Several of those write errors are discarded, so even the attempted side effects are not atomic or guaranteed. That's a real defect independent of everything else in this section: a debugging tool, a UI autocomplete, a test, or a reprocessing run has no way to *look up* a name without *also* attempting to pollute the mention/decision-log/backlog tables.

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

**The rule that matters: `TermID` is set only by one of two things—an unambiguous exact match against a released term's governed label after expected-kind/module filtering, or an accepted, reviewed `aligns_to_term` alignment.** A lexical auto-match (tiers 0–4, `2026080403-spec` §7.1) must never, by itself, produce a `TermID`. If an exact governed label still names multiple released terms, the result remains ambiguous. This is the same governance boundary §14 of the keyword spec already draws between the ungoverned lexicon and governed terms.

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

1. **Targeted enrichment** — a processor already knows a specific field is a name (a metric name, a candidate's alias list). Resolve it through the generic `names.Resolver` facade. No collector involved.
2. **Corpus-wide recall** — vocabulary that never becomes a structured field, useful only to a retrieval/search consumer that expands queries against the lexicon. This is the collector's job, and that consumer doesn't exist yet (§7.4, §17.1 of the keyword spec).

Metric-name canonicalization is job 1. It needs no collector, and is not blocked by the collector's unwired state.

---

## 4. How governed terms handle a word with two meanings

The other adjacent question: if a metric's canonical identity is meant to land on a governed `metric_definition` term, and the same word can mean different things (the conversation's example was "apple" — fruit vs. company), how does the term layer avoid confusing them?

**The current term store doesn't attempt to; the proposed facade must do so conservatively.** Verified in `ChenWeb/server/api/ontology/terms/terms_store.go`: there is no lookup-by-label function today. Terms are reached only by an already-known, namespaced `term_id` (`bio:apple` vs. `org:apple_inc`, for example). Two meanings become two term rows with separate `kb.ontology_term_labels` rows.

The proposed exact governed-label path in §2.2 may return a `TermID` only when expected kind/module filters leave one released term. If two released terms still share the label, the result is `ambiguous`. The other path is an accepted `aligns_to_term` assertion: a human reviews the lexical concept-to-term decision once during candidate governance, and later lookups reuse it.

This is precisely why `aligns_to_term` is a bridge and not a merge (§14 of the keyword spec): the keyword layer is where automated, ambiguity-tolerant "string → concept" resolution happens. The term layer holds governed meanings. An exact unique governed label can resolve directly; every non-exact lexical link requires accepted alignment evidence. A metric's `metric_definition_term_id`, once set through either governed path, carries no unresolved homonymy from the lexical lookup.

---

## 5. The proposed design: two identifiers, neither one forced

The design in `2026080403-spec`'s D5/D10 (ambiguity is first-class; bias toward under-merging) points one direction, and §2.2's resolution-semantics rule points the same way independently: resolve where you can, never overwrite, never force.

Applied to a metric, that means **two** identifiers, at two different trust levels, in addition to the raw extracted name — populated by one call to `names.Resolver.ResolveName` (§2), not by a direct call into the keyword module:

| Field | Populated by | Trust level | When empty |
|---|---|---|---|
| `metric_name` (unchanged) | `extract_metrics`, as today | — (provenance) | never — always the literal extracted string |
| `keyword_concept_id` (nullable) | `resolution.ConceptID`, set whenever status is `lexical_resolved` or `term_resolved` | fast, ungoverned, auto-mergeable | status is `unresolved` or `ambiguous` |
| `metric_definition_term_id` (nullable) | `resolution.TermID`, set only when status is `term_resolved`—an unambiguous exact released label or accepted `aligns_to_term`, per §2.2 | governed | status is anything else (§4) |
| canonical name shown to users | governed `TermPrefName` when available; otherwise language-selected lexical concept label; raw `metric_name` as final fallback | display only—the persisted identity remains an id | falls back cleanly |

**Why two identifiers and not one.** A keyword-tier auto-accept is cheap and ungoverned by design—that's what makes working mode fast. Its localized concept label is useful for grouping and display, but must be visibly treated as lexical/provisional. Pinning a metric's *authoritative* identity to `keyword_concept_id` alone would mean a bad auto-merge silently misfiles it with no review boundary. Routing authoritative identity through either governed path—an unambiguous exact released label or an accepted `aligns_to_term` assertion—keeps that guarantee intact; the raw extracted name always remains available as provenance and fallback.

**Why this satisfies "not forced."** At both hops, absence is a valid, expected, permanent-until-resolved state — not an error. A metric with no keyword match, or with a keyword match but no confirmed term, displays exactly as it does today. Nothing about this design requires the earlier resolution to succeed for the metric to remain fully usable.

### 5.1 The current side-effecting trace and the proposed separation

The generic chain (`2026080403-spec` §3 D1) is `name → occurrence → surface → lexform → concept`. A metric name is one instance of "name." Nothing below is metric-specific machinery — it's the same four-layer mechanism every keyword goes through, traced concretely for this one case so every hop can be checked against the running code rather than taken on faith.

**Not via the collector, and — per the 2026-08-05 revision above — not via `associate_semantics` either.** `extract_metrics` does not "register with" the mention collector; the collector reads raw chunk text and tokenizes it itself, blind to what any processor extracted (§9.1), and plays no role in this design. The mechanism below is a call to `names.Resolver.ResolveName(metricName, ...)` (§2), made by whatever consumes `extract_metrics`' output before persisting a metric row — not a call to `KeywordFamily.ResolveSurface` from inside `associate_semantics.processMetric`, which was this document's original (incorrect) proposal. `names.Resolver` internally uses the same tier 0–4 mechanism traced below; what changed is who calls it and through what contract, not what happens once the call is made.

**TODAY—what the underlying `KeywordFamily.ResolveSurface` does, in order** (not what the proposed read-only `ResolveName` will do):

1. Mode gate — no-op if `off` or no DB.
2. **Unconditionally attempts:** insert one row into `kb.keyword_mentions` (`artifact_ref`, `context_text`; `chunk_ref`/`ks_id` always null; no column for the name itself—§17.2 K4). The error is ignored.
3. `Kernel.Resolve`: normalize the name → key bundle (pure computation); query `kb.keyword_surfaces`/`kb.keyword_surface_keys` **tier by tier, stopping at the first tier that returns anything** — tier 0 (exact literal-string match) is tried before tier 1 (`norm_key` match); score and adjudicate a verdict.
4. **Unconditionally attempts:** append one row to `kb.semid_decision_log` (does capture the name, in `input`; captures no `artifact_ref`/`context_text`, and shares no key with the mention row from step 2). The error is ignored.
5. On `auto_accepted`: attempt a new surface row only if this exact literal string isn't already on file under that concept. On `deferred`/`ambiguous`: attempt a backlog upsert. Those errors are also ignored.

**PROPOSED:** `names.Resolver.ResolveName` retains only mode gate, normalization, candidate lookup, scoring, adjudication, concept/term loading, and result shaping. It performs no writes. `ObserveName` owns the occurrence/decision/backlog write path; `ResolveAndObserve` explicitly composes the two. The cases below trace today's matching logic while noting its current attempted writes.

**TODAY, "occurrence" is only step 2 plus its incomplete attempted side effect.** `ResolveSurface` has no separate occurrence-processing stage. The mention row it attempts to write may fail silently. The proposed `ObserveName` creates an explicit stage and makes its success or failure visible to the caller.

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
| Result | `auto_accepted`, resolves to `kwc_luminance`. The exists-check finds no exact literal match, so `ResolveSurface` **attempts** a second `alt` surface row with the same concept and normalized key. If an existing `alt` row already occupies the schema's `(norm_key, concept_id, scope, label_role)` unique key, insertion fails and the error is ignored; resolution still succeeds without learning the new literal. |

**To be precise about "automatically": the resolver attempts to attach the variant directly to the existing concept; it never creates a second concept requiring a merge.** Whether two literal strings persist as two surface rows depends on the uniqueness constraint and error handling just described. `MergeConcept` is the separate, heavier operation for two independently created concept ids that later prove equivalent.

**Case C — a genuinely new word for the same meaning.** "亮度" is resolved for the first time; only `"luminance"` and `"显示亮度"` exist as surfaces under `kwc_luminance`. Nothing named `"亮度"` is on file.

| Step | What happens |
|---|---|
| Tier 0 | no exact match |
| Tier 1 | "亮度"'s own `norm_key` (computed from "亮度" — a different string with no relationship to "luminance" or "显示亮度") matches **nothing stored** — normalizing "亮度" does not, and cannot, produce anything close to `"luminance"`'s or `"显示亮度"`'s `norm_key` |
| Tiers 2–4 | also miss, for the same reason — every tier here operates on keys derived from *this one string*, and "亮度" shares no derived key with either existing surface |
| Result | `deferred` — regardless of the fact that a human reading the document would immediately recognize "亮度" as luminance. The system has no way to know this until someone tells it. |

**Case B is the only one where the current resolver automatically attempts concept attachment for a new literal, and it only covers normalization-equivalent variants.** Case C—a different word, in any language, for the same meaning—is never resolved by the normalizer, no matter how often it is observed. Each successful unresolved upsert increments the backlog entry's `hits`; it never becomes a match on its own. **A human today, or reconciliation once built, has to accept `亮度` as a surface under `kwc_luminance` before Case C becomes Case A.** DR23's promise ("亮度/显示亮度/luminance/brightness... reach one row") is real, but every string has to cross from candidate to accepted surface before it holds.

**`lexform → concept`, precisely: the lookup works; the discovery doesn't exist.** Given an *existing* `norm_key`, finding which concept(s) it belongs to is built and correct (Case A/B above, tier 0/1 queries). Deciding, for the first time, that a *new* `norm_key` belongs to a given concept — the step Case C needs — has no automated form today; only a human, through the REST API, does it.

**What `kb.keyword_mentions` holds for a metric name, concretely: today, nothing recoverable.** `ResolveSurface` attempts a mention-row write on every call, ignores failures, and the row carries no reference to which name triggered it—no column exists for it (§17.2 K4). This is the same gap for every caller, not something specific to metrics.

**Summary—where the gaps actually are, hop by hop:** name→occurrence needs a new caller. Occurrence recording is broken regardless of caller (K4). Surface/derived-key lookup→concept is mechanically correct for Cases A and B, but Case B's attempted vocabulary growth is unreliable. The miss path needs K5 fixed to deduplicate the backlog. Case C's concept attachment is manual today and entirely unbuilt for reconciliation. Concept→governed-term needs exact governed-label lookup and the `aligns_to_term` producer, neither of which exists.

### 5.2 Why manual curation alone doesn't scale, and what would

This follows directly from Case C above, and it's worth being explicit about rather than leaving as a footnote, because it changes what "closing the gap" actually requires beyond the pilot.

**Lexform isn't under-built — it was never meant to solve this.** Its narrow scope (spelling, casing, whitespace, morphology — never translation, never synonymy) matches UMLS's own LUI layer faithfully: in UMLS, "Eye"/"eye"/"eyes" share an LUI, but "Eye" and "Ocular" don't, even though they mean the same thing — that unification is the CUI (concept) layer's job, done by curation, in UMLS as much as here. So the fact that lexform can't unify "luminance" and "亮度" isn't a simplification introduced by this implementation; it's the layer working as designed. The real question is what automates the concept-layer curation that Case C needs, at a scale beyond what a human can do one link at a time.

**The design has an answer; none of it is built.**

- **Tier 5 (fuzzy: trigram + edit distance)** doesn't help here — it catches misspellings of the *same* word, not different words. Edit distance between "luminance" and "亮度" is total.
- **Tier 6 (embedding/ANN similarity)** is the actual candidate-generation mechanism for this — a multilingual embedding model would plausibly place "luminance" and "亮度" close in vector space, unlike edit distance. It is, by design, *candidate-only*: it would never auto-accept a link on its own, only propose one (§17.1, `2026080403-spec`) — a wrong embedding-driven merge is exactly the silent failure D10 (bias toward under-merging) exists to prevent.
- **Reconciliation R3 (semantic/`pgvector` blocking) + R4/R5 (LLM batch decisions)** is what would turn a tier-6 candidate into a confirmed link at scale, without a human reading every pair by hand.

All three are entirely unbuilt (`2026080403-spec` §11, §17.1). Manual curation alone is not an acceptable bootstrap strategy: even a bounded pilot contains spelling noise, translations, and aliases that no curator can anticipate exhaustively. The adopted approach is the hybrid mutable lexicon in Appendix A: import a bounded slice of relevant resources, normalize every imported and observed surface, reconcile the remaining candidate clusters before activation, and continue draining new misses after activation. LLM calls are allowed in that batched growth path, not in every `ResolveName` call.

`kb.ontology_candidates.candidate_matches` remains a useful metric-specific review surface, but it is a consumer of the generic reconciliation evidence—not the canonicalization engine. A scoped multilingual embedding lookup can populate likely matches for a new metric definition, while the generic keyword reconciler owns candidate blocking, decision records, validation gates, and accepted surface updates. That turns "a human has to notice three unrelated proposals are the same metric, unaided" into "the system proposes an evidence-bearing match for confirmation" without putting metric-specific behavior inside the keyword or ontology core.

---

## 6. What has to exist for this to work

Most of the following is unbuilt. Resource acquisition also has real external constraints: each source's license, release process, availability, and redistribution limits must be approved and recorded before import.

1. **Fix the keyword-module correctness defects and normalization first.** §17.2 of `2026080403-spec` lists eleven; K2 (scope ignored), K5 (backlog keyed on raw surface), and N1 (normalizer over-collapses) would each silently corrupt this integration on day one. Implement the generic base cleaner plus versioned language profiles in Appendix A.5–A.6, populate all derived surface keys, change unknown language from `en` to `und`, and revise surface uniqueness so legitimate multilingual rows are representable (including language in the identity, with a separate invariant for one preferred surface per concept/scope/language).
2. **Build generic resource ingestion.** Add source adapters, a source-release/license registry, external-concept mappings, idempotent full/delta import, a separate many-to-one source-evidence/assertion table, and a bounded domain filter. The evidence table—not a surface's single provenance string—must support independent source retraction. No adapter logic belongs in a document processor.
3. **Build a metrics warm-start package as configuration/data, not keyword-core code.** Select relevant resources from `20260805-rsch`, include curated metric glossaries and artifact backfill, then measure coverage and ambiguity before activation.
4. **Build the `names.Resolver` interface and its `KeywordFamily`-backed implementation** (§2)—the read-only `ResolveName`/`ResolveNames` contract, language-aware preferred-label selection, correct scope handling, and expected-kind/module filtering on the governed-term continuation. A bare keyword concept is not filtered by term kind until an alignment/type assertion supplies that evidence.
5. **Build complete observation records and `ResolveAndObserve`.** Replace `kb.keyword_mentions`' incomplete shape with the occurrence data in §2.1, linked to the resolution decision and unresolved backlog.
6. **Build the minimum R1–R7 reconciliation loop required to drain misses.** Deterministic harvest/blocking comes first; multilingual embeddings and batched LLM adjudication are permitted for candidates; deterministic gates and transactional apply remain mandatory. The reconciler, not the LLM, owns writes.
7. **Add versioned snapshot activation.** Build and validate a candidate lexicon release while readers remain on the prior immutable snapshot, then switch atomically. Normalizer-version changes rebuild every derived key.
8. **`extract_metric_definitions` resolves its `canonical_name`/`aliases` through `names.Resolver`** at harvest time (`ontology_candidate_harvest.go`) and records evidence-bearing `candidate_matches` instead of leaving names as inert JSON.
9. **Build an `aligns_to_term` producer**, plus the schema fix it depends on: `kb.semantic_assertions.subject_ref_kind`'s `CHECK` constraint currently allows only `('object_node', 'ontology_term', 'assertion', 'artifact', 'literal')`, with no `'keyword_concept'` value. A keyword concept cannot be an assertion subject until this constraint is extended.
10. **`extract_metrics`' consumer calls `names.Resolver.ResolveName`** before the metric row is persisted (§2), setting `keyword_concept_id`/`metric_definition_term_id` per §2.2's rule—not inside `AssociateSemantics.processMetric`.
11. **Schema:** `kb.metrics` and/or `kb.semantic_assertions` gain nullable `keyword_concept_id` and `metric_definition_term_id` columns, with no constraint forcing either resolution to succeed.

**Deliberately sequenced after the metrics pilot, not blocking it:** moving `processMetric`/`processProvision` out of `AssociateSemantics` into consumer-specific adapters and un-registering them from the shared `init()` (§2.3); backfilling QUDT labels and importing unit→quantity-kind relationships so `resolveUnitTerms` can retire in favor of `names.Resolver` (§2.4). Both are real architectural debt, confirmed real by the same review that corrected this document — but neither has to be paid down before one metric name resolves correctly, and DR12's own vertical-slice framing argues for proving the pilot before generalizing further.

Items 1–3 establish trustworthy warm data. Items 4–7 establish generic serving and growth. Items 8–11 connect the metrics pilot and governed-term layer without contaminating the generic modules. Resource import and reconciliation are no longer optional follow-ups: without them, the system can look up a dictionary but cannot build or sustain one.

---

## 7. Documentation impact

**What knowledge changed, as of the 2026-08-05 revision?** Name resolution should happen behind a new, consumer-agnostic `names.Resolver` interface, not via a direct call from `AssociateSemantics.processMetric` into `KeywordFamily.ResolveSurface`. `resolveUnitTerms`, previously cited as a precedent worth following, is a workaround for an incomplete QUDT import rather than a stable pattern. `kb.semantic_assertions.subject_ref_kind` also cannot represent a keyword concept as an assertion subject today. Finally, the earlier appendix's preloaded-equivalence assumption was invalid: the adopted design is a hybrid mutable lexicon with resource import, normalization before every index/lookup, multilingual surface policy, optional offline LLM reconciliation, and versioned publication. `ResolveName` itself remains model-free.

Earlier findings still stand: the relationship between `extract_metrics` and `extract_metric_definitions` (there isn't one, and there should be), the mention collector's non-wiring having a stated reason, governed terms' approach to homonymy, and the precise tier-by-tier account in §5.1/§5.2 of what the keyword mechanism automates for a metric name versus what it never will.

**Source of the correction:** `doc-repo/bugs/202608/2026080501-bug-name-resolver-qutd.md`, an independent review requested specifically to check whether concerns raised about this document's reasoning were real problems — they were, on every concretely checkable claim, independently re-verified against the code before this revision was written.

**Which docs/specs/ADRs are affected?** `2026072901-adr` DR23 is the design authority for the metric-definition/lexicon relationship and is unchanged by this document — this addendum operationalizes it, it doesn't revise it. `2026080403-spec` gained §14.1, §14.2, and §9.1 alongside this addendum and should be read together with it.

**Which docs are now stale?** `2026080403-spec` §13's three-source seeding list and its implementation sequencing are incomplete relative to Appendix A: they omit generic resource adapters, source releases/licenses, external-id mappings, multilingual profiles, and snapshot activation. Its R1–R7 direction remains valid but must be extended with those prerequisites.

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
- `doc-repo/research/202608/20260805-rsch-vocabulary-resources.md` — resource survey motivating pluggable domain vocabularies, ontologies, knowledge graphs, terminology systems, and authority files

---

## Appendix A. Warm-start multilingual trace: `Luminance`, `亮度`, and `显示亮度` → one identity

This appendix starts with an empty database and answers both halves of the problem:

1. how the system learns that the three names can denote one metric; and
2. how every later `ResolveName` call uses that learned vocabulary without calling an LLM.

The adopted design is a **hybrid mutable lexicon**. External resources provide a warm start; deterministic normalization cleans both imported and observed names; document observations continuously identify coverage gaps; and an offline reconciliation job may use an LLM to adjudicate difficult vocabulary additions in batches. The online resolver remains deterministic, read-only, and cheap.

### A.1 The invariant: canonical identity is not canonical spelling

For the metrics pilot, all three inputs should reach one stable lexical identity:

| Input | Canonical identity | Default label | Localized preferred label |
|---|---|---|---|
| `Luminance` | `kw:luminance` | `Luminance` | `Luminance` (`en`) |
| `亮度` | `kw:luminance` | `Luminance` | `亮度` (`zh`) |
| `显示亮度` | `kw:luminance` | `Luminance` | `亮度` (`zh`) |

`kw:luminance` is illustrative; the real `concept_id` must be opaque and immutable. A single `kb.keyword_concepts.pref_label` can remain the default/fallback label, but it is not sufficient as the multilingual display model. Preferred surfaces must be selectable by language. A Chinese caller may display `亮度` while an English caller displays `Luminance`; both still persist and join on the same concept id.

Normalization is necessary but does not prove synonymy. It can make `␠␠LUMINANCE␠␠` and full-width `Ｌｕｍｉｎａｎｃｅ` share the key `luminance`. It cannot infer that `luminance`, `亮度`, and `显示亮度` mean the same thing. Shared external identity, reviewed document evidence, or offline adjudication establishes that semantic relationship.

### A.2 Resources are pluggable inputs; the keyword module owns the mechanisms

The resource survey in `20260805-rsch-vocabulary-resources.md` spans controlled vocabularies, taxonomies, ontologies, knowledge graphs, terminology systems, and authority files. They should not become hardcoded keyword logic. The generic module needs source adapters that emit a common record such as:

```go
type LexiconSourceRecord struct {
    Source, Release, ExternalConceptID string
    PreferredLabels map[string]string   // BCP 47 language tag -> label
    Aliases         []SourceAlias       // text, language, role, relation strength
    Mappings        []ExternalMapping
    Definition      string
    DomainKinds     []string
    Provenance      SourceProvenance
}
```

Useful source roles differ:

- Wikidata, UMLS, AGROVOC, GEMET, ChEBI, GeoNames, VIAF, IEC Electropedia, and domain glossaries can contribute lexical labels or aliases when their licensing and relation semantics permit it.
- Gene Ontology, FIBO, Schema.org, ACM CCS, and similar semantic resources may contribute concept typing or candidate evidence without every relation becoming a keyword synonym.
- A thesaurus's `related`, `broad`, or `narrow` relationship must never be silently upgraded to `exact`. For example, `brightness` may be related to luminance in ordinary language but is not automatically the same governed physical quantity.

UMLS is a valuable model and potential biomedical source, but it is **not an open-source dataset**. NLM distributes it without charge under an individual UMLS license, and some constituent vocabularies impose additional restrictions. Its Metathesaurus is concept-organized and multilingual; `MRCONSO.RRF` carries names, language, source vocabulary, and concept identifiers. An importer must retain those source and license boundaries rather than flattening every UMLS atom into unrestricted local data. See the [NLM Metathesaurus overview](https://www.nlm.nih.gov/research/umls/knowledge_sources/metathesaurus/index.html), [download information](https://www.nlm.nih.gov/research/umls/licensedcontent/umlsknowledgesources.html), and [license summary](https://www.nlm.nih.gov/research/umls/new_users/online_learning/OVR_005.html).

Wikidata is a more permissive cross-domain seed: its structured entity data is CC0, labels and aliases are language-specific, and weekly full dumps plus daily add/change dumps support a locally hosted, incrementally refreshed resource. See [Wikidata database downloads](https://www.wikidata.org/wiki/Wikidata:Database_download), [labels](https://www.wikidata.org/wiki/Help:Label), and [aliases](https://www.wikidata.org/wiki/Help:Aliases). The luminance item `Q355386` demonstrably connects the English concept *luminance* with the Chinese page/title `亮度` and a QUDT quantity-kind identifier. That is valid evidence for the first bilingual bridge. It is not evidence that Wikidata also supplies `显示亮度`.

### A.3 Empty database → warm serving snapshot

The system may begin physically empty during installation, but it should not advertise name resolution as ready until a minimum vocabulary snapshot is built and activated.

1. **Register source releases.** Record each resource, release/version, license class, checksum, retrieval time, and permitted use. This provenance is currently missing from the keyword schema.
2. **Extract a bounded slice.** Import only concepts relevant to configured domains and expected term kinds. Loading all of Wikidata or UMLS into `kb.keyword_surfaces` would increase ambiguity and operating cost without improving the metrics pilot.
3. **Preserve external identity.** Upsert a mapping from `(source, external_concept_id, release)` to a local opaque concept id. The current schema has no keyword-source mapping table, so idempotent refresh and cross-source coalescing are not yet possible.
4. **Normalize every imported label and alias.** The server—not the source adapter and not an API caller—derives all keys with one versioned normalizer. Raw text and source language remain stored.
5. **Coalesce only with evidence.** Two source records join one local concept only through a shared trusted identifier/crosswalk or an accepted reconciliation decision. Similar spelling, translation proximity, or an LLM suggestion alone creates a candidate, not an automatic merge.
6. **Run pre-service reconciliation.** Combine resource records, curated metrics glossaries, and an artifact backfill. Apply deterministic gates first; batch remaining candidate clusters for an LLM or human reviewer. Persist accepted aliases and all decision evidence.
7. **Validate coverage and ambiguity.** Run a metrics-first benchmark, including dirty and multilingual variants. Activation fails if required seed names are unresolved or if ambiguity exceeds the configured threshold.
8. **Publish atomically.** Readers use one immutable active snapshot while the next snapshot is built. The lexicon is mutable across releases, but a request never observes half an import or half a reconciliation transaction.

“Warm enough” is measurable readiness for the configured domains, not a claim that the vocabulary is complete.

### A.4 How this example is learned rather than assumed

An honest bootstrap trace uses more than one evidence source:

1. The Wikidata adapter reads `Q355386` and emits at least the English name `luminance`, the Chinese name/title `亮度`, the photometric definition/type, and its QUDT mapping.
2. The importer creates one local concept and attaches the two language-tagged surfaces because the external record already places them under one external identity.
3. No reviewed resource located for this trace establishes `显示亮度` as an alias. It must therefore begin as a candidate, not as fact. A domain glossary may provide it directly; otherwise artifact backfill or document extraction observes it with context such as display specifications, `cd/m²`, and neighboring luminance terminology.
4. Offline reconciliation blocks `显示亮度` against the existing luminance concept using lexical parts, multilingual embeddings, unit/quantity-kind compatibility, document context, and resource definitions. An LLM may adjudicate the compact candidate batch. It returns a proposed relation and rationale, never writes directly.
5. Deterministic gates verify scope, source references, language, unit compatibility, locked/never-merge constraints, and blast radius. A configured high-confidence decision may auto-apply; otherwise a human accepts it.
6. The apply step inserts `显示亮度` as a `zh` alternative surface under the existing concept, records the decision/evidence/model+prompt version, and builds a new snapshot.

The resulting serving data is conceptually:

```text
kb.keyword_concepts
concept_id       pref_label    scope       status
kw:luminance     Luminance     ventilator  active

kb.keyword_surfaces
surface          norm_key      concept_id       label_role  alias_type   lang  provenance
Luminance        luminance     kw:luminance     pref        synonym      en    import:wikidata
亮度              亮度           kw:luminance     pref        translation  zh    import:wikidata
显示亮度           显示亮度        kw:luminance     alt         domain_alias zh    reconcile:<decision-id>
```

The exact provenance depends on the resources actually configured. The trace does not claim that one universal dataset supplies all three rows.

### A.5 Normalization before resource lookup

The same normalizer must process imported resource surfaces, observed document names, and query strings. Otherwise a clean resource dictionary and dirty document extraction will use incompatible keys.

The current `KeywordNormalizer.Normalize` implementation executes this pipeline:

```text
NFKC
→ remove a fixed list of zero-width characters plus LRM/RLM
→ normalize dash and quote variants
→ collapse ASCII space, tab, CR, and LF
→ collapse dotted uppercase initialisms
→ lowercase Unicode runes
→ remove a limited English possessive form
→ remove leading English articles
→ apply a small English singularizer
→ derive norm, alnum, sorted-token, phonetic, and initials keys
```

Examples based on that implementation:

| Raw input | Current `norm_key` | Why |
|---|---|---|
| `Luminance` | `luminance` | lowercasing |
| `␠␠LUMINANCE␠␠` | `luminance` | whitespace collapse + lowercasing (`␠` denotes a space) |
| `Ｌｕｍｉｎａｎｃｅ` | `luminance` | NFKC + lowercasing |
| `亮度` | `亮度` | CJK characters have no case and remain intact |
| `显示\u200B亮度` | `显示亮度` | zero-width character removal |
| `显示 亮度` | `显示 亮度` | repeated whitespace collapses, but the remaining space is not removed from `norm_key` |

For the final row, the derived `alnum` key is `显示亮度`, which could bridge the spaced and unspaced forms at tier 2—but no current write path populates `kb.keyword_surface_keys`, so that bridge does not work today.

Current normalization must be improved before production use:

- `caseFold` calls `unicode.ToLower`; despite its comment, this is lowercasing, not full Unicode case folding.
- English singularization runs after case is destroyed and corrupts tokens such as `AIDS`, `SaaS`, and `Kubernetes` as already recorded in the keyword spec.
- `dropPossessiveS` does not remove a possessive at end of string because it only replaces `"'s "` followed by a space.
- English articles and morphology are applied without a language guard.
- There is no Chinese word segmentation, Simplified/Traditional Chinese handling, transliteration, language-specific punctuation policy, or multilingual morphological normalization.
- Normalization must not erase meaningful diacritics, digits, symbols, negation, or script distinctions merely to increase recall. Lossy transformations belong in lower-confidence alternate keys, never the canonical key.

The recommended design is a generic base cleaner plus pluggable, versioned language profiles. Language-specific profiles derive additional candidate keys; they never establish semantic identity by themselves.

### A.6 Multilingual resolution policy

Multilingual support is more than storing UTF-8 strings:

1. Store a valid BCP 47 language tag on every resource and observed surface; use `und` when unknown rather than today's dangerous default of `en`.
2. Treat script detection as a hint, not as language identification. Han characters alone do not distinguish Chinese, Japanese, or shared technical notation.
3. Keep translations and transliterations as explicit, provenance-bearing surfaces. Do not transliterate or convert Simplified/Traditional Chinese and silently declare equivalence during normalization.
4. Use requested language as ranking and display information, not an unconditional filter. Mixed-language documents and borrowed technical terms are normal.
5. Permit the same literal surface to belong to multiple concepts or languages. This requires changing the current uniqueness key, which omits `lang`. Scope, language, governed-term kind/module, and context may narrow candidates; unresolved ties remain `ambiguous`.
6. Select display label by `requested language → configured fallback chain → concept default`. Persist and join by concept id, never by the localized label.

The current schema stores `keyword_surfaces.lang`, but tier 0/1/2/4 queries neither filter nor rank by it. `KeywordFamily.Scope` also discards the caller's scope, and the proposed `ResolveNameRequest.Language` has no implementation underneath it. Multilingual resolution is therefore represented in storage but not operational in matching or display.

### A.7 Online resolution after snapshot activation

After A.3–A.4 publish the three surfaces, all normal calls are deterministic and make zero LLM requests:

1. A consumer calls `ResolveName(Name, Scope, Language, ExpectedTermKinds)` after extraction validation and before persistence.
2. The resolver preserves `RawName` and derives versioned keys using A.5.
3. Tier 0 attempts exact `(surface, scope)` lookup; tier 1 attempts `(norm_key, scope)`; lower tiers may use populated alternate keys. Language may rank candidates. Expected term kind/module filters only the governed-term continuation unless explicit type evidence exists for a lexical concept.
4. Candidate rows are deduplicated by concept id and merged concepts are followed to their survivor.
5. Exactly one eligible top concept is auto-accepted. A tie returns `ambiguous`; no candidate returns `unresolved`.
6. The resolver loads the concept and chooses a localized preferred surface. All three calls return `ConceptID = kw:luminance`; their display labels may differ by requested language.
7. `ResolveName` performs no write. A processing consumer normally follows it with `ObserveName`, or uses `ResolveAndObserve`, to preserve the occurrence and outcome for later learning.

The resolver never compares English and Chinese meanings at request time. Each normalized query reaches a stored surface; shared concept membership carries the previously adjudicated equivalence.

### A.8 How the vocabulary continues to grow

The dictionary must not be a frozen artifact. Growth is an explicit loop:

```text
new resource release or document occurrence
→ normalize and resolve against active snapshot
→ record unresolved/ambiguous occurrence with raw text, language, context, and provenance
→ batch harvest and candidate blocking
→ deterministic evidence + optional LLM/human adjudication
→ deterministic validation gates
→ transactional concept/surface/mapping update
→ rebuild indexes and publish next snapshot
```

Growth includes:

- periodic full or incremental source refreshes, such as Wikidata add/change dumps and new UMLS releases;
- newly configured domain resources from the research survey;
- aliases and definitions promoted from ontology candidates;
- repeated unresolved names harvested from document processors;
- human corrections, locks, never-merge rules, merges, and later splits;
- normalizer upgrades, which require a new `norm_version` and complete derived-key rebuild without overwriting raw surfaces.

Each accepted addition must retain provenance and evidence in a separate source-assertion model. That model is required so source removal or changed licensing can retract one source's support without destroying independent evidence; current singular surface provenance cannot do this. A bad LLM decision is reversible only when its proposal, validation, apply event, and affected assertions are versioned rather than hidden inside `ResolveName`.

### A.9 What exists and what is still missing

The current design is **mutable in intent and storage, but not yet a functioning self-growing lexicon**.

| Capability | Current state and consequence |
|---|---|
| Mutable concepts/surfaces | Built stores and REST APIs can create concepts, attach/lock surfaces, update labels, change status, and merge concepts. The dictionary is not structurally read-only. |
| Automatic normalization-equivalent growth | `ResolveSurface` tries to attach a newly observed spelling after a match, but ignores insertion errors and records the misleading provenance `llm:observe`. |
| Miss collection | `kb.keyword_unresolved` and its store exist, but occurrence capture lacks the observed name and useful provenance, scope is inconsistent, and no reconciliation worker drains the backlog. |
| Resource import and refresh | Not built. There is no generic source adapter, source-release registry, external-concept mapping, license metadata, delta refresh, seed module, or artifact backfill. A surface also has only one `provenance` and one free-text `evidence` field, so it cannot represent independent support from several sources without a separate evidence table. |
| Snapshot publication | Not built. Readers query mutable tables directly; there is no immutable active lexicon release or atomic activation gate. |
| Offline LLM reconciliation | R1–R7 are designed but unbuilt. LLM use is appropriate here in batches, after blocking and before deterministic validation—not inside every resolve call. |
| Multilingual matching | `lang` is stored but ignored; it defaults to `en`; no language-profile normalizer, localized preferred-label lookup, or constraint enforcing at most one preferred surface per concept/scope/language exists. |
| Alternate-key lookup | Query code exists, but derived surface keys are never populated; dirty variants that need those keys miss. |
| Scope | K2 remains: the kernel calls `KeywordFamily.Scope`, which always returns `_`, so requested scope is not honored during candidate lookup. |
| Exact lookup performance | Tier 0 lacks an index on `(surface, scope)`. |
| Candidate correctness | Matching rows are not deduplicated by concept id; merged/deprecated concepts are not handled correctly. |
| Rewrite tier | A rewritten candidate is scored against the original input key and can be discarded with score zero. |
| Consumer integration | No document consumer currently calls the proposed generic `names.Resolver`; it is not implemented. |
| Governed-term bridge | Accepted `aligns_to_term` resolution is not built, so lexical identity cannot yet become governed metric identity. |

### A.10 Required metrics-first tests

The proof should contain two phases, not a fixture that magically begins with all three aliases.

**Bootstrap/growth test:**

1. start with empty keyword tables;
2. import a versioned Wikidata-style fixture that connects `Luminance` and `亮度` through one external id;
3. ingest an observed `显示亮度` occurrence with Chinese language, document context, and compatible unit evidence;
4. run a deterministic reconciliation fixture or stubbed structured LLM decision followed by real validation gates;
5. verify that one concept and three evidence-bearing surfaces exist in a candidate snapshot;
6. activate it atomically and prove a repeated import/reconciliation is idempotent;
7. add a conflicting `亮度` concept and prove the system preserves ambiguity rather than over-merging it.

**Online resolution test:**

1. resolve all three clean names plus dirty variants such as `␠␠LUMINANCE␠␠`, `Ｌｕｍｉｎａｎｃｅ`, and `显示\u200B亮度` (`␠` denotes a space);
2. assert zero LLM/network requests on every `ResolveName` call;
3. assert the same `ConceptID` for all accepted inputs while preserving each raw string;
4. assert English and Chinese preferred-label selection follows the requested language and fallback policy;
5. assert scope, expected term kind, and language participate in candidate ranking;
6. assert `ResolveName` performs no writes and `ResolveAndObserve` writes exactly one linked occurrence/decision;
7. assert disabling the resolver returns `disabled` and performs no writes;
8. assert no keyword or ontology code contains a metric-, resource-, or document-processor-specific branch to make the test pass.

Once these tests pass, another artifact or domain extends the same system by registering resources and supplying name, scope, language, and optional expected term kinds—not by creating another canonicalization engine.
