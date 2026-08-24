# Keyword Canonicalization and Reconciliation — Specification

- **DocID:** `doc-2026080403`
- **Status:** Adopted — **the single reference for the keyword module**
- **Date:** 2026-08-04; rewritten 2026-08-05; **addendum `doc-2026080404` merged in 2026-08-05**; accuracy-audited and ambiguity reconciliation (§13.6) added 2026-08-08
- **Component:** SemOS / ChenWeb — keyword lexicon, the DR15/DR16 keyword identity family
- **Supersedes:** `2026080101-spec-…-merged.md`, `2026072703-spec-…-2.md`, `2026072301-spec-….md`, and **`2026080404-spec-metric-name-canonicalization-addendum.md`** (merged here; retained on disk as history only)
- **Design authority:** ADR `2026072901` — DR15 (shared kernel), DR16 (merged keyword design), **DR23 (the governing requirement, §2)**, DR12 (metrics is the pilot slice)
- **Reasoning record:** `2026080501-bug-name-resolver-qutd.md` (the `names.Resolver` correction) and `2026080502-bug-keyword-module-review.md` (findings F1–F8). Design conclusions live here; the analysis behind them lives there.

---

## 0. Status at a glance

| | |
|---|---|
| **Built** | 6 tables, 6 CRUD stores, the keyword normalizer, `KeywordFamily` (tiers 0–4), 14 REST endpoints, a standalone mention collector, `KEYWORD_RESOLVER_MODE` gating. P3 Track B, 7 commits, 2026-08-04. |
| **Works today** | ⚠️ *corrected 2026-08-08, was stale since 2026-08-06* — online resolution through tiers 0–5 (exact, normalized, alnum/sorted, rewrite-rules, initials, fuzzy — tier 3 still byte-equality-narrow); D11 auto-create on a targeted miss; offline tier-6/reconciliation merge (identity-authorized since 2026-08-07); offline ambiguity reconciliation (§13.6, new 2026-08-08); concept CRUD and lifecycle; the REST authoring surface. |
| **Fixed (2026-08-05)** | All 13 defects originally verified in §20.2 (K1–K10, N1–N3) — fixed across P4 §19 steps 1–9 (§21); each fix carries a `K`/`N`-numbered code comment at its call site. §20.2's table is historical record of what was found and fixed, not current state. |
| **Not built** | Full R1–R7 orchestration, the online tier-6 resolve path (kept reconciliation-only by design decision, §22 Q2), `on`-mode wiring, production seed publication. |
| **Live-validated (2026-08-07)** | I2 closed: `reconcile_identity_integration_test.go` proves exact-identity merges, deferral without identity, conflict rejection, audit invariants, and family-lock serialization against real PostgreSQL (`chenweb_test`). |
| **Design gap** | **D11 (auto-first)** — closed 2026-08-05, P4 step 8 (§21): a targeted miss now auto-creates a provisional concept (`gloss_source='auto:d11'`) instead of assuming a human drains a queue; reconciliation (step 11, §13) is what later unifies the resulting auto-created duplicates. |

**Remaining gaps are tracked in §20.1**: R1–R7 orchestration, `on`-mode wiring, collector pipeline wiring, and production seed publication are the load-bearing ones — see that section for the full deferred list and why each is safe to build around today.

**Phase context.** P1, P2, P4 (generic runtime), and P5 are built. P3 Track A (assertions, evidence, Phase D) is built and live-validated. **P3 Track B — this module — is built; its defect list is longer than its siblings' because the original delivery (2026-08-04) went untested against real behavior.** That gap is partly closed: `reconcile_identity_integration_test.go` now runs the reconciliation/merge path against real PostgreSQL (I2, closed 2026-08-07, see the row above). The broader online path (tiers 0–5, `names.Resolver`) is still proven only by sqlmock, not a live document corpus. Nothing in §20.2 invalidates Track A or the P4/P5 runtime; the defects are contained inside `ontology/keywords` and `ontology/semid`.

**Badges:** ✅ Built (does what this says) · 🚧 Partial (stated limitation) · ⚠️ Defect (verified wrong, §20.2) · ⏳ Deferred. *A badge describes whether code exists, never whether it is correct.*

---

## 1. Background

Documents refer to one thing many ways:

```
Postgres, PostgreSQL, postgresql
亮度, 显示亮度, luminance, brightness
ML, machine learning, millilitre          (homonym)
K8S, Kubernetes, Kube, kubernets           (case + noise + misspelling)
```

If each form is an independent key, recall fragments and analytics count one concept as several. The cost compounds in a bilingual corpus where one concept appears as an acronym, a full phrase, a translation, and a misspelling.

**The economic thesis:** LLM cost must scale with *vocabulary growth*, not query volume. Every alias learned once is free thereafter. A mature deployment approaches zero LLM calls per day at millions of lookups.

---

## 2. The governing requirement — DR23

Everything in this document exists to satisfy one requirement, stated in the ADR:

> **"Alternative names are lexicon, not term duplicates.** A metric definition's alias set is the DR15/DR16 keyword lexicon instantiated over metric terms, aligned by `aligns_to_term`. This is what lets 亮度 / 显示亮度 / luminance / brightness in 140 documents reach one row — and it is why the lexicon is not an optional side quest for this application but a prerequisite." — ADR `2026072901` §3.24 (DR23)

**"Reach one row" is the outcome this module exists to make possible.** It is not aspirational and it is not deferred: the comparison matrix that the target application renders has one row per metric definition, and if four phrasings of luminance produce four rows, the application is wrong on its primary screen. 🏗️ **APP-SPECIFIC:** the comparison matrix itself is rendered and owned by the **Document Review app** (P4, DR21/DR22) — not this module. This module's own acceptance boundary is REQ-1 and REQ-2 (§2.1).

### 2.1 What "one row" decomposes into

| # | Requirement | Satisfied by | Status |
|---|---|---|---|
| **REQ-1** | All spellings and translations of one metric name resolve to **one keyword concept** | tiers 0–4 for variants of one string; **auto-create + reconciliation merge** for genuinely different words and translations (D11, §13) | ✅ **corrected 2026-08-08** — tiers 0–5 built online (tiers 2/4 fixed, K1/N3; tier 5 shipped §19 step 11); D11 auto-create built (§19 step 8); offline tier-6 + reconciliation merge built (§19 step 11, identity-authorized since 2026-08-07) but **not yet proven against a real cross-lingual corpus** (Appendix A) — tier 3's narrow byte-equality matching is the one remaining tier-ladder defect |
| **REQ-2** | That keyword concept resolves to **one governed `metric_definition` term** | an accepted `aligns_to_term` assertion (§16.2) | ✅ accepted `aligns_to_term` assertion (§16.2) — step 12 (2026-08-06): auto-align on exact pref-label match + merge-follow; still gated on released `metric_definition` terms (§16.1) |
| **REQ-3** | Every metric artifact carries that **term id**, regardless of how its document phrased the name | `names.Resolver` called by the consumer of `extract_metrics`, persisting `metric_definition_term_id` (§16.3) | ✅ `names.Resolver` called by the consumer of `extract_metrics`, persisting `metric_definition_term_id` (§16.3) — the minimum loop (exact-label auto-align + merge-follow) is the step-12 deliverable; the governed-catalog bootstrap (§16.1) and standards-glossary import (§13.2) still gate the live §2.2 end-to-end run |
| **REQ-4** | The comparison matrix's row key is **derived from that term id** | ✅ **decided and enforced (2026-08-06) — `metric_key` *is* the term id; see §2.4** | 🏗️ **APP-SPECIFIC — Document Review app (P4); implemented** |

**REQ-1 and REQ-2 are this module's responsibility. REQ-3 is the integration. REQ-4 belongs to the Document Review app (P4) — it is tracked in this table only because DR23's own acceptance example (§2.2) depends on it, not because this module owns it or blocks on it.**

⚠️ **Correction (2026-08-05).** An earlier revision of this table marked REQ-4 "✅ by design in P4" and claimed the matrix "falls back to grouping by raw string" when the term id is null. **Both statements were wrong**, and the second was invented — no such fallback exists in the code. See §2.4.

### 2.2 The acceptance test

Given a corpus where luminance is phrased as `Luminance`, `luminance`, `亮度`, and `显示亮度` across many documents:

1. All four resolve to **one** `concept_id`.
2. That concept has **one** accepted `aligns_to_term` to a released `metric_definition` term.
3. Every extracted metric from every one of those documents carries that **one** `metric_definition_term_id`.
4. 🏗️ **APP-SPECIFIC (P4):** a comparison run for that metric definition produces **exactly one row**, with all documents' assertions inside it.
5. 🏗️ **APP-SPECIFIC (P4):** adding a 141st document with a fifth phrasing does not create a second row — it either resolves (R1) or auto-creates a concept that reconciliation merges (§13), converging to one row without human intervention.

**Steps 1–3 are this module's acceptance boundary**, independently testable per §18.2. Steps 4–5 are the Document Review app's end-to-end proof that this module's output actually closes the loop — real, and worth stating so DR23's own example is verifiable end to end, but they exercise P4 code this module does not own and cannot make pass by itself. Step 5 is the one that distinguishes a system that works at scale from one that works on a fixture.

### 2.3 A domain question DR23's own example raises

DR23 lists **brightness** alongside 亮度 / 显示亮度 / luminance. Photometrically, *brightness* is a perceptual attribute and *luminance* is a measured quantity — they are near-synonyms in ordinary use and **different quantities in a standards context**. Whether they are one metric definition or two is a **domain-owner decision**, not something this module may infer.

The requirement on the module is therefore narrower and stricter than "merge things that look alike": it must be able to represent **either** answer, and it must never auto-merge them on lexical or embedding similarity alone. This is the ADR's own `exact | close | broad | narrow | related` mapping-strength discipline (DR13) applied to the case DR23 happens to use as an illustration. §13.4 states how a resource-imported "related" pair is prevented from silently becoming "exact."

### 2.4 🏗️ APP-SPECIFIC — REQ-4 decided and enforced: `metric_key` *is* the governed term id

**This entire subsection is Document Review app scope (P4), not keyword-module scope.** It is documented here only because §2.2's acceptance example references it and because DR23's own worked example doesn't converge without it.

Originally verified against the P4 comparison code (2026-08-05): `metric_definition_term_id` appeared nowhere in the comparison package, `kb.ontology_comparison_cells.metric_key` was an unconstrained `TEXT` column, and cell comparison was driven by `QuantityKind`/`Unit`/`Component`, not by any term identity — so the matrix's row key was an opaque string (`metric_key`, e.g. `"time_to_alarm"`) with no defined relationship to the governed term id REQ-3 produces.

**Decided and implemented (2026-08-06): `metric_key` *is* the governed term id.** The comparison scope's row universe is populated with `metric_definition` term ids; `metric_key` is not a separate key space, it is that id serialized as text, and the column name is a holdover from an earlier design (not renamed — the ADR's own Appendix C.6 already named this column `metric_definition_term_id`; the implementation had drifted from that, this decision and its enforcement restore it). The rejected alternative — an explicit `metric_definition_term_id → metric_key` mapping owned by the comparison layer — would have added an indirection layer with no benefit once the key space and the term id are the same thing.

**Enforcement, in `comparison/store.go`:** `ComparisonStore.validateMetricKey` runs on every `CreateScope` (each entry in `metric_keys`) and `PersistCell` (`metric_key`) call, requiring the value to be a `kb.ontology_terms` row with `term_kind = 'metric_definition'` and `status = 'included_in_release'` — otherwise the call is rejected before any row is written. **This is application-level validation, not a DB foreign key**, deliberately: `kb.ontology_terms` has no single-column unique constraint on `term_id` alone (only `(term_id, version)`, because terms are versioned), so a real FK isn't possible without changing the governed-term schema. It mirrors `AssociateSemantics.termExists` (`ontology/assertions/associate_semantics.go`) — the same pattern every other term-id-reference column in this schema uses (`predicate_term_id`, `subject_term_id`, etc.), none of which have a DB FK either. Covered by `TestComparisonStoreCreateScopeRejectsMetricKeyThatIsNotAReleasedMetricDefinitionTerm` (unknown term id, wrong `term_kind`, not-yet-released status).

REQ-4 is now **decided and enforced**: no longer an undefined break in the chain, and no longer just a naming intent — a comparison scope or cell can no longer be created with a `metric_key` that isn't a released `metric_definition` term.

---

## 3. Goals and non-goals

**Goals.** Resolve a surface to a concept with no LLM call; return variants by role; preserve ambiguity as a real result; grow the store automatically; support aliases, acronyms, spellings, and language variants; make every decision auditable and reversible; stay reusable across search, extraction, enrichment, faceting, and analytics.

**Non-goals.** Not full business-entity resolution. **The online path never calls an LLM** — absolute; a *local* embedding lookup is not an LLM call, and reconciliation's model use is offline and batched (§23.2 item 2 revisits whether tier 6 belongs online at all). Not a taxonomy engine — hierarchy is out of scope for v1. Not a spell-checker — misspellings become `hidden` aliases.

*(The earlier "fuzzy/ANN tiers are suggest-only" non-goal is withdrawn — D11 and §13.1. Suggest-only presumed a human adjudicator who cannot exist at this volume.)*

---

## 4. Design decisions

### D1. Four identity layers — 🚧 **Partial**

```
name  →  occurrence  →  surface  →  lexform  →  concept
```

`name` is whatever raw string a producer supplies. The machinery downstream is identical regardless of source; **nothing in it is metric-specific**.

| Layer | Storage | Where | Status |
|---|---|---|---|
| **name** | not this module's | the producer's table (e.g. `kb.metrics.metric_name`) | — |
| **occurrence** | one table | `kb.keyword_occurrences` (renamed from `kb.keyword_mentions`, §19 step 7) — carries `raw_name`/`norm_key` and links to the decision-log row | ✅ K4 fixed |
| **surface** | real entity | `kb.keyword_surfaces` — verbatim text, role, alias type | ✅ |
| **lexform** | **not an entity** — a derived value | the `norm_key` column | ✅ (⚠️ K5 on the backlog) |
| **concept** | real entity | `kb.keyword_concepts` | ✅ |

Only two of four are database entities. Lexform is deliberately a *value*: an index key, not a governed record. **Matching is always `name` against `kb.keyword_surfaces`**, never against occurrence — `kb.keyword_mentions` participates in no lookup.

### D2. One shared resolution kernel — ✅ **Built**

`normalize → candidates → score → adjudicate` lives once, in `ontology/semid/`, instantiated per family. What legitimately differs: `CandidateNodes` (which tables), `AutoAcceptPolicy` (governed vs. not), `Scope`. **Normalization does not differ — see D3.**

### D3. Normalization is shared, not per-family — ✅ **Fixed (2026-08-05, §19 steps 2–4)**

**Lexical normalization depends on the language of the string, never on which family is asking.** A Chinese term label and a Chinese keyword surface need identical treatment; nothing about "being governed" changes what NFKC does.

The code used to violate this: `keywords.KeywordNormalizer` (ten steps) and `semid.Normalizer`'s built-in were two implementations of one operation, duplicated outright, with `NormFunc` as a one-user escape hatch.

**Decision, implemented:** one implementation, shared — `semid.Normalizer` (`server/api/ontology/semid/normalizer.go`). `NormFunc` and the `semid` built-in are deleted; `Normalizer()` no longer exists on `FamilyAdapter`; the primitives are consolidated.

### D4. SKOS label roles — ✅ **Built**

`pref` (canonical display) · `alt` (synonyms, acronyms — visible) · `hidden` (misspellings — searchable, never displayed).

### D5. Ambiguity is first-class — ✅ **Built**, semantics revised by D11

*Silently* picking the most frequent candidate produces an error invisible to caller and metrics. Under D11, `ambiguous` is returned **with the top-1 pick** — the caller gets a usable id *and* an explicit contested signal. What is rejected is unrecorded guessing, not deciding.

### D6. Store surfaces; derive keys; version the normalizer — ✅ **Fixed (2026-08-05, §19 step 5)**

Every key is recomputable from `surface + norm_version`, so a normalizer change is a re-index, never data loss. **Decision, implemented:** the server derives all keys on every write path and rejects a caller-supplied `norm_key`/`norm_version` (K3, `kbhandler/keyword_handlers.go`); `derivedSurfaceKeys` writes the alnum/sorted/initials/singular rows on every surface write (K1, `surfaces_store.go`), so tiers 2 and 4 read real data.

### D7. Merges are tombstones; no transitive closure — ✅ **Fixed (2026-08-05, §19 step 6)**

Merges set `merged_into` and keep the row. Merges are never transitive — one bad edge must not chain two clusters.

Merge used to be implemented twice with disjoint capabilities (an unused in-memory `semid.MergeGraph` with the guardrails, and the persisted `ConceptStore.MergeConcept` without them). **Decision, implemented:** `semid.MergeGraph` is deleted; its guardrails (refuse `never_merge` / already-merged; follow `merged_into` at read time) are ported into `ConceptStore.MergeConcept`, backed by the persisted `NeverMergeStore`, plus §14.1's surface re-pointing and §14.4's un-merge, built in the same step.

### D8. Token-economics discipline — ⏳ **Deferred**

`harvest → prune → block → batch → decide → validate → apply`. Every stage before the model shrinks its job; every stage after stops it corrupting the store.

### D9. Two modes, two axes — ✅ **Built** (working), ⏳ **Deferred** (reconciliation)

**Axis 1 — what runs:** *working mode* (every resolve call, never an LLM) vs. *reconciliation mode* (scheduled batch, LLM permitted, drains the backlog).

**Axis 2 — how far answers travel** (`KEYWORD_RESOLVER_MODE`):

- **`off`** (default) — no resolution, no writes. ⚠️ Not honoured when the variable is *unset* (K6).
- **`observe`** — full pipeline runs, all side effects written, answer withheld from consumers. What P3 Track B shipped. **A state of working mode, not a third mode.**
- **`on`** — same pipeline, gate removed. ⚠️ Unusable: no consumer exists, and `IsObserveMode()` means flipping to `on` turns collection *off* (K7).

### D10. Bias toward under-merging — ✅ **Policy, scoped to merges only**

A wrong **merge of two established concepts** is structural, invisible, and contaminates everything already assigned. Merges stay conservative; §9.2's vetoes are hard.

**This governs merges, not assignment.** Under D11, leaving an assignment undecided is not the safe option, and the older "a missed alias is self-healing" framing is withdrawn for that case — it assumed a human would drain the backlog.

### D11. Auto-first: every path terminates in a decision — ✅ **Built (2026-08-05, §19 step 8)**

**Scale forces this.** 10⁵–10⁶ documents × ~10² artifacts = 10⁷–10⁸ name occurrences. Reviewing even 0.1% is unaffordable. **Any design where a routine path waits for a person stalls permanently.**

| Situation | Old | **Auto-first** |
|---|---|---|
| No concept matches a **targeted** name | `deferred` → backlog → wait | **auto-create a provisional concept**, assign it |
| Multiple concepts tie | return no id | **`ambiguous` + the top-1 pick**, flagged |
| Fuzzy/embedding candidate | never accepted | **may auto-accept** above a tier threshold (§13.1) |
| Below threshold | a queue nobody drains | **auto-create a provisional concept** (the weak candidate is not attached to), record its method + score, mark for **sampling** |

**`ambiguous` and below-threshold are different kinds of uncertainty.** `ambiguous` means the evidence is strong but split between two-plus concepts — the top-1 pick is choosing among plausible answers, so attaching to it is reasonable. Below-threshold means the evidence for *any* candidate is weak; attaching to it anyway risks mis-filing the name onto an established concept's surface set, an error only `split_concept` (§14.4) can undo. So below-threshold is treated like "no candidate," not like "tied candidates": auto-create, don't attach. A fresh provisional concept costs nothing and stays mergeable once reconciliation confirms a match.

**Why deciding beats deferring.** An unresolved metric name is not neutral — it is a hole in the comparison matrix (§2), and the review app then answers a customer with silently incomplete data. A wrong-but-recorded assignment is visible, attributable, and cheap to reverse. **Silence is not the safe default.**

**The price, non-optional:** every decision must be **attributable** (method, score, normalizer version, decision-log row), **reversible** (retraction is ordinary, not archaeology), and **sampleable** (low-confidence and auto-created outcomes findable *as a set*). Without these, auto-first is unattributable guesswork.

**Human involvement, all non-blocking:** benchmark/gold-set curation (offline); **exception repair** (a review is found wrong → correct the database, re-run — acts after the fact); and the governed-catalog gate (§16.1 — small enough to review).

**Scope limit.** Auto-creation applies to **targeted names** — a field a producer asserted *is* a name. It must **not** apply to the mention collector, which tokenizes all prose and would mint a concept per junk token.

---

## 5. Identity model

### 5.1 Cardinal rules (binding)

1. **`concept_id` is opaque and immutable.** The label is a mutable display attribute.
2. **Store surfaces; derive keys.**
3. **Merges are tombstones, never deletes.**
4. **Everything carries provenance and confidence** — so a bad source's entire output can be revoked in one query.
5. **Human assertions are locked.** The reconciler may propose but never apply.

### 5.2 How the layers relate

- **occurrence → surface** — many-to-one. A resolve checks the raw literal first (tier 0), then the normalized key (tier 1). Surface is deliberately *not* the normalized form: keeping the verbatim string is what lets "Luminance" and "luminance" stay distinguishable as separately-observed spellings.
- **surface → lexform** — many-to-one, computed at write time. Consistency comes from **determinism, not lookup**: the normalizer is pure, so "these share a lexform" is recomputed identically every time. That determinism is also the risk — one inconsistent implementation fractures the layer silently, which is what N1/N2 do today.
- **lexform → concept** — many-to-many, with **no join table**. `concept_id` is `NOT NULL` on each surface; two surfaces sharing a `norm_key` but pointing at different concepts *is* the relation. The tier-1 query reads it directly: one distinct concept → auto-accept; two or more tied → `ambiguous`. **There is no separate disambiguation subsystem.**

### 5.3 What lexform does not do

`norm_key` is a function of one string's spelling, casing, and morphology. **"Luminance," "亮度," "显示亮度," and "brightness" produce four different `norm_key` values.** REQ-1 of §2.1 is delivered at the **concept** layer — four surface rows sharing one `concept_id` — never by normalization. Lexform collapses variants of the *same* string; it never substitutes for the curation or reconciliation that connects different words to one meaning.

### 5.4 Homonymy

`norm_key` is not globally unique, so `ML` → machine learning *and* millilitre is representable. Scope should disambiguate, then context. ⚠️ Neither works today (K2; context disambiguation unbuilt), so global-scope homonyms return `ambiguous` — safe, but not the designed path.

---

## 6. Normalization — ⚠️ **Defect**

The most dangerous component: fast, invisible, and every over-aggressive rule silently collapses distinct concepts forever. The design is conservative; the implementation is not.

### 6.1 The pipeline as implemented

| # | Step | Verified example | Note |
|---|---|---|---|
| 1 | Unicode NFKC | `Ｌｕｍｉｎａｎｃｅ` → `luminance` | full-width folded |
| 2 | Strip zero-width / BOM / LTR-RTL | `显示​亮度` → `显示亮度` | soft hyphen U+00AD **not** stripped |
| 3 | Dashes → ASCII | `e–mail` → `e-mail` | |
| 4 | Quotes → ASCII | | |
| 5 | Collapse/trim whitespace | `␠␠LUMINANCE␠␠` → `luminance` | |
| 6 | Collapse dotted initialisms | `U.S.A.` → `usa` | uppercase `A.B.C` only |
| 7 | Case-fold | `亮度` → `亮度` (CJK unaffected) | ⚠️ `unicode.ToLower`, i.e. lowercasing, **not** full Unicode case folding, despite the comment |
| 8 | Drop possessive `'s` | **`AWS's` → `aws'`** | word-final possessive missed (N2) |
| 9 | Strip leading articles | `the cloud` → `cloud` | English, **unguarded by language** |
| 10 | Singularization | **`AIDS` → `aid`**, **`SaaS` → `saa`** | reproduces the failures it was written to avoid (N1) |

Note `显示 亮度` (with a space) → `norm_key` = `显示 亮度`, which does **not** equal `显示亮度`. The `alnum` key bridges them at tier 2 (K1 fixed, §19 step 5).

### 6.2 The key bundle — ✅ computed and persisted (K1 fixed, §19 step 5)

Six keys: `exact`, `norm` (primary index), `alnum`, `sorted`, `phonetic`, `initials` (plus `singular`, added at the same fix). `norm` is stored on the surface row; `alnum`/`sorted`/`initials`/`singular` are written to `kb.keyword_surface_keys` by `derivedSurfaceKeys` on every surface write, so tiers 2 and 4 read real data. `phonetic` remains deliberately unwritten — no tier reads it (Double Metaphone is deferred, §20.1) — so writing rows nothing queries would just be a new dead-key defect.

### 6.3 Required improvements

Beyond the defects in §20.2, normalization must gain before production use:

1. **Full Unicode case folding**, not `ToLower`.
2. **A language guard on every language-specific step** — articles, possessives, and singularization are English rules applied today to every string regardless of language.
3. **CJK handling beyond pass-through**: word segmentation, a Simplified/Traditional policy, and a decision on transliteration. **Never silently declare Simplified/Traditional equivalence during normalization** — that is a semantic claim, and it belongs in an explicit, provenance-bearing surface.
4. **Lossless canonical key.** Normalization must not erase meaningful diacritics, digits, symbols, negation, or script distinctions to increase recall. Lossy transformations belong in lower-confidence **alternate** keys, never the canonical one.
5. **Structure: one generic base cleaner + pluggable, versioned language profiles.** Profiles derive additional candidate keys; they never establish semantic identity by themselves.

### 6.4 Verified normalizer defects

**N1 — singularization is unsafe in several independent ways.** Reproduced: `AIDS→aid`, `SaaS→saa`, `Kubernetes→kubernete`, `Postgres→postgre`, `analysis→analysi`.

⚠️ **These are not one failure with one fix.** An earlier revision prescribed only "never singularize an originally-ALLCAPS token," which closes **exactly one of the five**:

| Case | Shape | Closed by the ALLCAPS guard? |
|---|---|---|
| `AIDS→aid` | ALLCAPS acronym | ✅ yes |
| `SaaS→saa` | mixed-case acronym | ❌ no |
| `Kubernetes→kubernete`, `Postgres→postgre` | title-case proper nouns | ❌ no |
| `analysis→analysi` | an all-lowercase **singular** ending in `s` | ❌ no |

The last is the most instructive: no casing signal of any kind helps, because the word is already singular. The rule `HasSuffix("s") && !HasSuffix("ss") && len>3 → strip` is simply wrong as a general singularizer — English has a large class of singulars ending in a single `s` (`analysis`, `basis`, `status`, `bias`, `campus`, `virus`).

**Fix:** the §6.3 rework, not a casing patch. Concretely: (a) run singularization only under a language profile, and only for a language whose profile defines it; (b) carry the casing signal from step 7 and skip any token whose original form was not all-lowercase; (c) replace the bare suffix rule with an exception-aware lemmatizer, keeping a hard stop-list for known singulars ending in `s`; and (d) treat singularization output as an **alternate** key, not the canonical one, so an over-aggressive rule degrades recall instead of destroying identity (§6.3 item 4). The ALLCAPS guard is a necessary part of (b), not a sufficient fix on its own.

**N2 — the possessive rule requires a trailing space**, so word-final possessives are missed and then mangled.

**N3 — the `initials` bridge cannot bridge.** The key is uppercased while every other key is lowercased, and tier 4 looks up the *query's* initials (`ML` → `M`). Fixing K1 alone would make tier 4 match every single-token surface starting with `m` — worse than nothing. **Fix:** look up the query's normalized form against lower-cased stored initials, scope- and length-gated.

**N4 — `norm_version` is stored but never filtered on.** Two versions would serve reads simultaneously. Must be fixed before the first bump.

---

## 7. Multilingual policy — ⚠️ **Represented in storage, not operational**

The pilot corpus is predominantly Chinese with English technical terms. Multilingual support is more than storing UTF-8:

1. **Store a valid BCP 47 language tag on every surface**; use `und` when unknown — **not** today's default of `en`, which asserts a language nobody verified.
2. **Script detection is a hint, not language identification.** Han characters alone do not distinguish Chinese, Japanese, or shared technical notation.
3. **Translations and transliterations are explicit, provenance-bearing surfaces** — never a normalization side effect.
4. **Requested language ranks and selects display; it does not filter.** Mixed-language documents and borrowed technical terms are normal.
5. **The same literal surface may belong to multiple concepts and languages.** ⚠️ This requires changing the current uniqueness key, which omits `lang` (§10.2). Scope, language, term kind, and context narrow candidates; unresolved ties stay `ambiguous`.
6. **Display label selection: requested language → configured fallback chain → concept default.** Persist and join by `concept_id`, **never** by a localized label.

⚠️ Today `kb.keyword_surfaces.lang` is stored but **no tier filters or ranks by it**, `Scope` discards the caller's scope (K2), and `ResolveNameRequest.Language` has no implementation beneath it.

---

## 8. The shared kernel (`semid`) — ✅ **Built**

### 8.1 Contract

A family declares what differs; the kernel owns the mechanism. Per D2/D3 the interface carries `CandidateNodes`, `AutoAcceptPolicy`, and `FamilyName` — **not** `Normalizer()`, and not `Scope()` once scope becomes an explicit parameter.

### 8.2 Resolve flow — ⚠️ signature defect

`Score` is a four-way discrete function: exact key 1.0; candidate key ∈ surface's alternates 0.8; mutual prefix ≥3 chars 0.5; else 0. **Zero-scoring candidates are dropped before adjudication.** `Adjudicate`: no candidates → `deferred`; tied beyond `MaxCandidates` → `ambiguous`; disabled or below `MinScore` → `human_review`; else → `auto_accepted`.

⚠️ **`Kernel.Resolve(ctx, surface)` takes one input but needs two.** The scope it filters on is fetched behind the caller's back via `Family.Scope()` — which is why K2 and K9 are invisible at call sites. Both families overwrite `res.Scope` *after* the search already ran with the wrong value. The parameter name `surface` is also keyword vocabulary imposed on a family-agnostic mechanism; `TermFamily` reuses it for a different thing entirely.

**Decision:** `Kernel.Resolve(ctx, input string, scope string)`; `Family.Scope()` leaves the interface.

### 8.3 Verdicts — semantics revised by D11

A verdict describes **how confident the decision was**, not whether a decision happens.

| Verdict | Means | Carries an id? |
|---|---|---|
| `auto_accepted` | one clean match above threshold | yes |
| `ambiguous` | several tied at the top | **yes — top-1 plus the tied set** |
| `deferred` | no candidate | **yes for targeted names — an auto-created concept**; none on the collector path |
| `human_review` | resolved below threshold | **yes for targeted names — an auto-created concept, same as `deferred`**, flagged for sampling — **not a queue**; the rejected candidate's id/method/score is recorded, but not assigned

⚠️ `TermFamily` can produce only two of four: `MaxCandidates` at its zero value gates off tie-detection, and `Enabled: false` blocks auto-accept (K10).

### 8.4 Shared tables — ✅ **Built** (P2)

`kb.semid_decision_log` · `kb.semid_never_merge` · `kb.semid_snapshots`, scoped by `family`.

---

## 9. Working mode

### 9.1 The tier ladder
The tier ladder is the resolution waterfall: the ordered list of methods 
CandidateNodes tries when turning an observed string (a "surface" — the 
literal text found in a document) into a concept_id. It is the mechanical 
core of REQ-1 — the thing that has to make Postgres / PostgreSQL / postgresql 
land on one concept so the comparison matrix produces one row instead of 
three (§2.1).

Two rules govern it, both in the paragraph under the table:

* Exit at the first tier that produces candidates. Tiers are not unioned. If tier 1 returns anything, tiers 2–7 never run.
* Each tier stamps a score, which is then handed to Adjudicate (§8.2) to produce the verdict — auto_accepted (one clean match), ambiguous (tied at the top), deferred (nothing), human_review (below threshold).

**The ordering principle**

The ladder is sorted by strength of evidence and cost, jointly — 
strongest and cheapest first:

| Tiers	| Kind of evidence	| Cost|
|-------|-------------------|-----|
|0–1	| string identity (raw, then normalized)	| one indexed SQL lookup|
|2–4	| derived keys — alphanumeric-only, sorted tokens, initials, plus rewrite rules	| one more SQL lookup |
|5–6	| statistical similarity — trigram/edit distance, then multilingual embeddings	| expensive; ANN or scan |
|7	| no match at all → backlog, or auto-create a new concept	| deferred to offline reconciliation |

That gradient is the whole economic thesis of the module (§1): cost must scale 
with vocabulary growth, not query volume. Tiers 0–4 are pure SQL and free. A miss 
at tier 7 costs something once — the reconciler learns the alias and writes a surface 
row — and every subsequent occurrence of that string comes back at tier 0 forever 
after. Mature deployment → millions of lookups/day, near-zero LLM calls.

**Tier by tier — exact mechanism and how to verify it (corrected 2026-08-08; every claim below is anchored to a file:line or a named test, so it can be checked directly against `ChenWeb/server/api/ontology/keywords/`, not taken on faith)**

* **Tier 0 — exact surface match on raw text.** `SELECT s.concept_id FROM kb.keyword_surfaces WHERE s.surface = $1 AND s.scope = $2 LIMIT 10` (`tier0ExactMatch`, `keywordfamily.go`). Byte-exact match on the verbatim, un-normalized literal — `Luminance` and `luminance` are different rows on purpose (§5.2), so this tier alone never collapses them. Score 1.0 (exact key). **Verify:** `TestCandidateNodesPerTier/tier0_exact` asserts the exact SQL text and args; `TestExitKernelResolutionTiers` (`keyword_exit_test.go`) exercises it end-to-end through the kernel.
* **Tier 1 — raw text normalization, then `norm_key` match.** `SELECT s.concept_id, s.norm_key FROM kb.keyword_surfaces WHERE s.norm_key = $1 AND s.scope = $2 AND s.norm_version = $3 ORDER BY s.confidence DESC LIMIT 10` (`tier1NormKeyMatch`). `norm_key` is the output of the shared normalizer (NFKC → zero-width strip → dash/quote ASCII-fold → whitespace collapse → dotted-initialism collapse → case-fold → possessive strip → article strip, §6.1); the `norm_version` filter (N4) means a query only matches surfaces indexed under the currently-active normalizer version. Score 1.0. **Verify:** `TestCandidateNodesPerTier/tier1_norm`; `TestResolveScopeRoundTrip` proves a surface written at scope `ks` is found at the same scope and not at a different one.
* **Tier 2 — `alnum`/`sorted`/`singular` alternate keys.** Three sequential lookups against `kb.keyword_surface_keys` (`tier2AlternateKeyMatch` → `lookupByKeyKind`, one JOIN'd SQL query per key kind, first hit wins): `alnum` strips everything but letters/digits (bridges `显示 亮度` ↔ `显示亮度` — the spec's own example); `sorted` canonically reorders words/tokens; `singular` is the plural→singular bridge (`analyses` finds a stored `analysis`). All three keys are written by `derivedSurfaceKeys` on every surface write (`surfaces_store.go:225`) and filtered by `norm_version`. Score 0.8 (lossy key, not identity). **Verify:** `TestCandidateNodesPerTier/tier2_altkey`. Refer to §9.1.1 for more information.
* **Tier 3 — rewrite rules, then retry tiers 0–1.** `tier3RewriteMatch` 
loads enabled rules from `kb.keyword_rewrite_rules`, applies **at most 
one** rule whose `pattern` equals the **raw, un-normalized** surface 
**by byte equality** (`rewritten == r.Pattern`), then re-runs tier 0 and 
tier 1 (not 2, 4, 5, or 6) against the rewritten string. This is why a 
rule `K8S → Kubernetes` fires for the literal `K8S` but not for `k8s` — 
the one real remaining defect in the ladder. Score inherited from 
whichever of 0/1 the retry hits (1.0/1.0, tagged `tier3_rewrite`). 
**Verify:** `TestCandidateNodesPerTier/tier3_rewrite`.
Refer to §9.1.2 for more information.
* **Tier 4 — initials bridge.** `tier4InitialsMatch` gates on input string 
length (2–8 runes), then looks up the query's own normalized form 
against stored `initials` keys — `initialsKey()` lower-cases every 
initial (`semid/normalizer.go`), and the lookup direction is 
query-into-stored-keys, never the reverse (this ordering is the N3 fix: 
the original bug looked up the *stored* surface's initials against 
the query). Bridges `ML` → `machine learning` when `machine learning`'s 
stored initials key is `ml`. Score 0.8. **Verify:** 
`TestCandidateNodesPerTier/tier4_initials`. Refer to §9.1.3 for 
more information. 
* **Tier 5 — fuzzy match (trigram-blocked, edit-distance-scored).** Two distinct steps, not one algorithm. For more information, refer to :
  1. **Blocking** (cheap, SQL, indexed): `SELECT s.concept_id, s.norm_key FROM kb.keyword_surfaces WHERE s.scope = $1 AND s.norm_version = $2 AND similarity(s.norm_key, $3) > $4 ORDER BY similarity(...) DESC LIMIT 20` — Postgres `pg_trgm`'s trigram `similarity()` function, backed by a GIN trigram index on `norm_key` (migration `20260806000001`). This finds *candidates*, not the final score. ✅ **Configurable (2026-08-08)**: the floor is `KeywordFamily.FuzzyBlockMinSimilarity` (defaults to `0.3` via `ensureDefaults`, not hardcoded) — a caller can raise or lower it per instance. **Verify:** `TestFuzzyBlockMinSimilarityDefault`, `TestFuzzyBlockMinSimilarityConfigurable`. It applies trigram on the entire input string, not token-by-token or substring-by-substring.
  2. **Scoring** (Go, `fuzzyCandidateScore` in `keywordfamily.go`, using `runeLevenshtein`/`normalizedSimilarity` in `fuzzy.go`): for each of the ≤20 blocked candidates, compute rune-counted Levenshtein edit distance, apply §9.2's length-banded guardrails (`len≤4`: no fuzzy at all; `5–8`: edit distance ≤1 **and** first rune must match; `≥9`: edit distance ≤2 **and** `normalizedSimilarity ≥ 0.88`), and the three vetoes applied before any threshold — digit (`digitsDiffer`: any digit difference kills the match), canonical (`canonicalPrefExists`: if the query itself is a `pref_label`, skip fuzzy entirely — checked once up front, before blocking even runs), negation/affix (`hasNegationAffixMismatch`: `un-`/`non-`/`de-`/`anti-`/`-less` pairs, e.g. `compliant`/`noncompliant`, checked pairwise so ordinary words starting with `de-` aren't vetoed). The surviving score is `normalizedSimilarity` itself — continuous, `1 − editDistance/longerLength` — carried as `PrecomputedScore`, not the tiered 1.0/0.8. **Verify:** `TestTier5FuzzyMatchGuardrails` and `TestRuneLevenshtein`/`TestNormalizedSimilarity`/`TestDigitsDiffer`/`TestHasNegationAffixMismatch` (`fuzzy_test.go`) test the pure functions in isolation; `TestKeywordFamilyCandidateNodesReachesTier5` and `TestResolveSurfaceTier5AutoAccepts` prove it end-to-end including auto-accept.
  Misspellings only — `kubernets` finds `kubernetes` because they share enough trigrams to survive blocking and enough edit-distance closeness to survive scoring. It does **not** find cross-lingual matches: `亮度` and `luminance` share zero trigrams.
* **Tier 6 — offline reconciliation: lexical recheck + governed identity claims decide; embedding is a ranking/diagnostic signal only, never sufficient alone.** Not part of `CandidateNodes` — see the "current reality" note above and §20.1.1/§22 Q2 for why it never runs online. Where it does run, `keywords.Reconciler.Run` (`reconcile.go`, invoked only via `cmd/keyword-reconcile`) scans **exactly the D11 auto-created provisional concepts** (`ConceptStore.ListAutoCreatedProvisional` — `status='provisional' AND gloss_source='auto:d11'`, batch size 500 per run, oldest first) — i.e. concepts that already exist *because* they missed tiers 0–5 online (D11 gave them an identity immediately; reconciliation's job is deciding whether that identity should merge into an existing one). For each candidate, `decideCandidate` (`reconcile.go`) gathers **three independent signals** and combines them in `chooseCandidateDecision`, in this priority order:
  1. **Lexical recheck** (`recomputeTier5`) — re-runs the *exact same* `fuzzyCandidateScore` edit-distance function tier 5 uses online, but comparing the candidate's `pref_label` against **all `status='active'` concepts** in scope (trigram-blocked via `listTier5Shortlist`, floor `reconcileLexicalBlockMin = 0.30`, top 10). If this finds a single unique best match (`tier5Unique` — no other candidate within `1e-9` of the top score), **that alone is sufficient to propose a merge** — no embedding or identity claim required.
  2. **Governed identity claims** — evidence from approved external sources (exactly what QUDT/BIPM/UCUM/Wikidata import feeds, §20.1.7). If there is exactly one active concept with an authoritative `exact_equivalent` claim, **that alone is sufficient** — and it wins over/conflicts-checks against the lexical result if both exist.
  3. **Embeddings** — `EmbeddingClient.EmbedBatch` embeds every concept with `status IN ('active','provisional')` in scope (`ConceptStore.ListConcepts`) fresh, in memory, every run (no persisted vector index — see §22 Q2's "should be" note); ranks same-scope `active` targets by `cosineSimilarity`, top 10 (`reconcileEmbeddingTopK`). **Embeddings never authorize a merge by themselves** (2026-08-07 revision) — a high cosine score with no lexical-unique match and no authoritative claim only upgrades the outcome from `no_candidate` to `deferred` ("insufficient authoritative identity"), i.e. it flags the pair for the audit trail, not a merge.

  **This means, precisely:** two concepts that are lexically close (tier 5 catches them) merge automatically without ever touching identity data. Two concepts in *different scripts* (the flagship `亮度 ↔ luminance` case) share zero trigrams, so signal 1 never fires for them — an automatic merge for that case depends entirely on signal 2, an imported governed crosswalk, **not** on embedding similarity, however high. Embeddings alone do not — and, as designed, cannot — close DR23's cross-lingual acceptance example; they only make the miss visible for later evidence. **Verify:** `TestReconcilerUniqueTier5NoAuthorityMergeThenThreeCandidatePartialFailure` and `TestReconcilerTier5TieLowCosineExactIdentityOutsideTopTenMerges` prove the priority ordering; `TestEmbeddingScoreNeverAuthorizesAndProviderRankNeverTruncates`, `TestEmbeddingOutputFailsClosed` prove embeddings alone never authorize; `TestReconcileIdentityIntegration` (real PostgreSQL, `TEST_DATABASE_URL`-gated) proves an end-to-end merge.
* **Tier 7 — miss.** Two different outcomes depending on the caller (`ObserveOccurrence`, `keywordfamily.go`): the **collector** path (untargeted) upserts `kb.keyword_unresolved`, keyed on the derived `norm_key` (K5 fixed) — `(surface literal, context)` appended, deduped, capped. The **targeted** path (a producer asserted this field *is* a name) instead runs `autoCreateConcept`: mint a new `provisional` concept whose `concept_id` is a content hash of `(norm_key, scope)` (collision-safe under a concurrent race — `TestAutoCreateConceptConvergesOnExisting` — and merge-tombstone-safe — `TestAutoCreateConceptFollowsMergeOnConflict`), and write the surface itself as that concept's `pref` label. This is what makes step 5 of the acceptance test work without a human: the 141st document with a fifth phrasing gets its own concept immediately (D11), and offline reconciliation (tier 6) is what later proposes merging it into the others. **Verify:** `TestObserveSurfaceTargetedMissAutoCreates`, `TestObserveSurfaceCollectorMissQueuesBacklog` (`autofirst_test.go`).

**What the ladder deliberately does not do**
It only collapses variants of the same string. Different words for the same 
meaning — luminance vs 亮度 vs brightness — are never unified by normalization; 
they become several surface rows sharing one concept_id, established by 
curation or reconciliation (§5.3). Tier 6 is the one partial exception, and 
even it proposes an assignment, never a structural merge of two established 
concepts (D10).

**Current reality vs. the table**

⚠️ **This subsection described the pre-step-11 (2026-08-04/05) state and was not updated when tier 5 and D11 auto-create shipped 2026-08-05/06 — corrected 2026-08-08.** Reading the status column literally, as of today:

* **Tier 2 and 4 are built**, not data gaps: `derivedSurfaceKeys` writes `alnum`/`sorted`/`initials`/`singular` rows to `kb.keyword_surface_keys` on every surface write (K1 fixed, §19 step 5, `surfaces_store.go`), and tier 4's logic bug is fixed (N3, same step): initials are stored lower-cased like every other key, and the lookup direction is corrected — the query's own normalized form is looked up against stored initials, never the reverse. Both are covered by `TestCandidateNodesPerTier`.
* Tier 3 matches the raw surface with byte equality, so K8S → Kubernetes does not fire for k8s. The rewrite engine applies only a single substitution per lookup and does not chain rules. After applying the rewrite, the system re-runs the lookup but only re-checks Tier 0 and Tier 1 — it does not retry against Tiers 2, 4, 5, or 6. **This one is still unfixed.**
* **Tier 5 is built and wired**, not unbuilt: `KeywordFamily.CandidateNodes` calls `tier5FuzzyMatch` (trigram-blocked, §9.2-guardrailed, continuous score) as of §19 step 11 (2026-08-06, commit `c92b`/`8acb`), with a kernel-level end-to-end test (`nyyq`). It may auto-accept above threshold per §13.1.
* **Tier 7's auto-create is built**, not unbuilt: D11 auto-first (§19 step 8, 2026-08-05, commit `b7e0`) auto-creates a provisional concept on a targeted miss (`deferred`) or a weak match (`human_review`); only the collector path still just backlogs.
* **Tier 6 is built, but deliberately never runs on this online path** — it exists only in the offline `keywords.Reconciler` (§13, §19 step 11) and, since 2026-08-07, its merges require an authoritative identity claim from an approved governed source, not cosine alone (§13.1's 2026-08-07 revision). This was a decision (§22 Q2), not a gap — see §20.1.1.

So the functioning **online** ladder today is 0 → 1 → 2/3/4(narrower defects only) → 5 → 7(auto-create for targeted names; backlog for the collector). Tier 3's byte-equality/single-rewrite/narrow-retry limits are the one remaining tier-ladder defect below tier 5. Tier 6 never runs online by design; it runs offline, batch, identity-gated.


| Tier | Method | Score | Status |
|---|---|---|---|
| 0 | exact surface match | 1.0 | ✅ |
| 1 | `norm_key` match | 1.0 | ✅ |
| 2 | `alnum`/`sorted` key | 0.8 | ✅ fixed 2026-08-05 (K1, §19 step 5) |
| 3 | rewrite rules → retry 0–1 | 1.0/0.8 | ✅ (narrow — byte-equality, single substitution, retries 0–1 only) |
| 4 | `initials` bridge | 0.8 | ✅ fixed 2026-08-05 (N3, §19 step 5) |
| 5 | fuzzy (trigram + edit distance) | continuous | ✅ built, online, may auto-accept (§13.1) |
| 6 | embedding (multilingual ANN) | continuous | ✅ built, **offline/reconciliation-only by design** (§22 Q2); identity-authorized since 2026-08-07 |
| 7 | miss → backlog / auto-create | — | ✅ backlog; ✅ auto-create (targeted names, D11, §19 step 8) |

`CandidateNodes` exits at the **first tier producing candidates**. Tier 3 matches the **raw** surface with byte equality, so a rule `K8S → Kubernetes` does not fire for `k8s`; one rule fires at most; the retry covers tiers 0–1 only. Tier 3 is the only remaining defect below tier 5 — tiers 2 and 4 (K1/N3) are fixed.

#### 9.1.1 Notes on Tier 2
Tier 2 performs up to three indexed alternate-key lookups, in this fixed order:

`alnum` → `sorted` → `singular`

It stops at the first key kind that returns any candidate concepts. The returned candidates are scored at 0.8 (lossy-key evidence), and can still be ambiguous if several concepts share that key. See [keywordfamily.go](/Users/cding/Workspace/ChenWeb/server/api/ontology/keywords/keywordfamily.go:226).

- `alnum`: as you understand it, removes non-ASCII letters/digits while retaining CJK-and-beyond characters. E.g. `显示 亮度` → `显示亮度`.

- `sorted`: it does not sort characters; it splits the normalized string on whitespace, lexicographically sorts those tokens, then joins with spaces. So:

  ```text
  "luminance display module" → "display luminance module"
  "display module luminance" → "display luminance module"
  ```

  This is intended to bridge word-order variations. There is an implementation caveat: a `sorted` key is only stored when it differs from `norm`. Thus a stored surface already in alphabetical order, such as `display luminance`, does not get a `sorted` row; a later lookup for `luminance display` will not find it through Tier 2. It does work when the stored surface itself was non-alphabetical. The derivation is at [normalizer.go](/Users/cding/Workspace/ChenWeb/server/api/ontology/semid/normalizer.go:384), and the omission rule is at [surfaces_store.go](/Users/cding/Workspace/ChenWeb/server/api/ontology/keywords/surfaces_store.go:225).

- `singular`: yes, partly through maps, plus guarded suffix heuristics—not a full English lemmatizer.

  1. It runs only when the string is considered Latin-profiled: it contains Latin letters and has at least as many Latin as Han characters.
  2. It preserves any token that originally contained uppercase, to avoid changing acronyms and proper names (`AIDS`, `SaaS`, `Kubernetes`).
  3. It first uses an irregular-plural map: `indices → index`, `analyses → analysis`, `children → child`, etc.
  4. It then uses a stop-list and suffix guards to preserve known/invariant singulars like `analysis`, `status`, `bias`, `series`, and forms ending in `ss`, `us`, `is`, or `ics`.
  5. Only then does it apply limited rules such as `categories → category`, `classes → class`, `watches → watch`, and a final trailing-`s` removal.

  The maps and rules are in [normalizer.go](/Users/cding/Workspace/ChenWeb/server/api/ontology/semid/normalizer.go:270). It is deliberately only an alternate key—not the canonical normalized name—so an incorrect inflection guess can only miss a match rather than redefine identity.

The irregular-plural map is hard-coded in Go, not stored in the database: 
[`irregularPlurals`](/Users/cding/Workspace/ChenWeb/server/api/ontology/semid/normalizer.go:273). 
For example, it contains `analyses → analysis`, `children → child`, 
and `indices → index`.

“Preserves” in bullet 2 (above) applies only to the `Singular` alternate key, 
not to the normal `Norm` key.

So:

   | Input | `Norm` | `Singular` |
   |---|---|---|
   | `AIDS` | `aids` | `aids` |
   | `SaaS` | `saas` | `saas` |
   | `Kubernetes` | `kubernetes` | `kubernetes` |

In other words, Unicode case-folding still lowercases them; the singularizer 
simply does not further mutate them to `aid`, `saa`, or `kubernete`. The 
uppercase signal is captured before case folding and causes that token to 
bypass singularization at 
[normalizer.go](/Users/cding/Workspace/ChenWeb/server/api/ontology/semid/normalizer.go:91) and [normalizer.go](/Users/cding/Workspace/ChenWeb/server/api/ontology/semid/normalizer.go:324).
This is what the word 'Preserves' mean. Without it, 'AIDS' is first case-folded
to 'aids', and then to 'aid' by `singular` method.

The stop-list and the suffix guards are both hard-coded in Go:

- Stop-list map: [`singularStopList`](/Users/cding/Workspace/ChenWeb/server/api/ontology/semid/normalizer.go:315)
- General guards for short words and endings `ss`, `us`, `is`, `ics`: [normalizer.go](/Users/cding/Workspace/ChenWeb/server/api/ontology/semid/normalizer.go:347)

Bullet 5’s suffix rules are also hard-coded in `singularizeToken`, at 
[normalizer.go](/Users/cding/Workspace/ChenWeb/server/api/ontology/semid/normalizer.go:340):

- `-sses` → remove `es`: `classes → class`
- `-ches`, `-shes`, `-xes` → remove `es`: `watches → watch`, `boxes → box`
- `-ies` → `y`: `categories → category`
- final `-s` → remove `s`, subject to the earlier exclusions.

None of the singularization behavior is data-driven or configurable through 
the database today.

For example, storing `analysis` writes a `singular=analysis` key even though 
it equals its norm key. Querying `analyses` derives `singular=analysis`, so 
Tier 2 can find the stored concept. This special persistence rule is explicit 
in [surfaces_store.go](/Users/cding/Workspace/ChenWeb/server/api/ontology/keywords/surfaces_store.go:220).

#### 9.1.2 Tier-3 Rewrite Rules
Tier 3 is best understood as a curated, scope-specific alias map. Each rule rewrites one complete input string to a surface already associated with the intended concept.

Example rules:

| Pattern received | Replacement | Intended effect |
|---|---|---|
| `K8S` | `Kubernetes` | Product abbreviation |
| `k8s` | `Kubernetes` | Separate rule required because matching is case-sensitive |
| `Kube` | `Kubernetes` | Common shorthand |
| `Postgres` | `PostgreSQL` | Alternate product name |
| `pgsql` | `PostgreSQL` | Technical shorthand |
| `亮度` | `luminance` | Governed cross-language alias, only if the meanings are approved as identical |

Important behavior:

- `pattern` is a literal, whole-string, byte-equality match—not regex.
- Matching is case-sensitive: `K8S` does not match `k8s`.
- `scope` must exactly equal the resolution request’s scope.
- Only one rule is applied; rules cannot be chained.
- After rewriting, only Tier 0 and Tier 1 are retried.
- The replacement should therefore already exist in `kb.keyword_surfaces`, either literally or through its normalized key.
- Rules should represent identity, not merely related terms. For example, `database → PostgreSQL` would be unsafe because PostgreSQL is only one kind of database.

This behavior is implemented in [keywordfamily.go](/Users/cding/Workspace/ChenWeb/server/api/ontology/keywords/keywordfamily.go:243), with the rule schema in [20260803000006_create_kb_keyword_rewrite_rules.sql](/Users/cding/Workspace/ChenWeb/project_migrations/20260803000006_create_kb_keyword_rewrite_rules.sql:9).

Below is how it is implemented:
- Loads every enabled rule for the requested scope, ordered by `rule_id`.
- Iterates through that in-memory list.
- Compares the entire raw input to each `pattern` using Go string equality.
- On the first match, replaces the whole input and stops.
- Normalizes the replacement, then retries Tier 0 and Tier 1.

Conceptually:

```go
rules := ListEnabledRules(scope)

for _, rule := range rules {
    if rawInput == rule.Pattern {
        rewritten = rule.Replacement
        break
    }
}
```

Therefore, a rule `K8S → Kubernetes`:

- Matches `K8S`.
- Does not match `k8s`.
- Does not match `Learn K8S deployment`.
- Does not tokenize, search substrings, use regex, or chain rules.

The database is queried by `scope`, not by `pattern`, so the current algorithm is O(number of enabled rules in that scope). An upstream collector may separately supply individual tokens as inputs, but Tier 3 itself performs no tokenization.

**Important**

Note that this implementation does not scale when the rewrite table becomes
big. An alternative implementation is to loop words over the input. For
each word, it look up the table. This algorithm assumes the inputs are normally
short, which is true.

`scope` is the vocabulary namespace/domain in which a keyword is interpreted. It prevents identical text in different domains from being forced into the same concept.

Examples:

- `_` — global/default namespace
- `display` — display terminology such as `luminance`
- `metrics` — metric terminology
- `ks_ventilator` — a particular knowledge-store/domain vocabulary

For a rewrite rule, its scope must match both:

1. The scope supplied by the resolution request.
2. The scope of the target keyword surface/concept.

For example:

```text
Input:       K8S
Scope:       technology
Rule:        K8S → Kubernetes, scope=technology
Target:      Kubernetes surface, scope=technology
Result:      rule applies
```

The same rule under `scope="_"` would **not** apply to a request using `scope="technology"`. Although `_` means global/default conceptually, the current implementation uses exact equality and does not treat `_` as a wildcard or fallback:

```sql
WHERE enabled = true AND scope = $1
```

The namespace definition appears in the merged specification as “knowledge store / domain / `_` = global,” and the exact filtering is implemented in [rewrite_rules_store.go](/Users/cding/Workspace/ChenWeb/server/api/ontology/keywords/rewrite_rules_store.go:87).


#### 9.1.3 Tier 4 Handle Acronyms
Tier 4 resolves an acronym by comparing it with initials generated from 
a stored phrase. It is designed for initials only, such as 'ML', 'SaaS',
'API', etc. The inputs should be acronyms.

| Incoming String | Stored Initials | Stored surface | Result |
|---|---:|---:|---|
| `ML` | `ml` | `machine learning` | Matches |
| `NLP` | `nlp` | `natural language processing` | Matches |
| `RDBMS` | `rdbms` | `relational database management system` | Matches |
| `API` | `api` | `application programming interface` | Matches |

The incoming string is normalized to lowercase, so `ML`, `Ml`, and 
`ml` all look up the key `ml`. A successful Tier-4 candidate receives 
score `0.8`.

Important edge cases:

- If both `machine learning` and `markup language` exist in the same scope, `ML` returns both candidates and may be classified as ambiguous.
- Every token (word) contributes an initial. `United States of America` produces `usoa`, not `usa`.
- CamelCase is not split into words. `PostgreSQL` produces only `p`, so `PG` does not match it through Tier 4.
- Only queries containing 2–8 runes are eligible. A `rune` is a Go term, repsenting one UTF-8 code point. A one-character abbreviation such as `R` and an abbreviation longer than eight characters skip Tier 4 entirely.
- Punctuation is generally significant. For example, `CI/CD` does not equal the stored initials key `cicd`; the query `CICD` does.

The lookup direction is:

```text
Stored phrase: "natural language processing"
Stored key:    initials = "nlp"

Incoming string: "NLP"
Normalized:     "nlp"

"nlp" = "nlp" → candidate found
```

Tier-4 measures input string length by runes. In Go, a `rune` is a
Unicode code point.

Examples:

| Text | Rune count |
|---|---:|
| `ML` | 2 |
| `API` | 3 |
| `亮度` | 2 |
| `CI/CD` | 5 |
| `é` | usually 1 after Unicode normalization |

A rune differs from:

- A byte: `M` uses one UTF-8 byte, while `亮` uses three, but each is one rune.
- A displayed character: some emoji or accented characters can contain multiple Unicode code points.

Tier 4 counts the runes in the normalized incoming string and proceeds 
only when that count is between 2 and 8 inclusive. If the number of runes 
of the input is not in [2, 8], it skips Tier-4 entirely.
See [keywordfamily.go](ChenWeb/server/api/ontology/keywords/keywordfamily.go:276).

The initials are stored in `kb.keyword_surface_keys`.
Each initials entry has approximately this form:

| `surface_id` | `key_kind` | `key_value` | `norm_version` |
|---|---|---|---:|
| ID for `machine learning` | `initials` | `ml` | 2 |

The table does not directly store `concept_id`. Tier-4 joins it to 
`kb.keyword_surfaces` through `surface_id`, obtaining the associated 
`concept_id` and `norm_key`:

```sql
SELECT s.concept_id, s.norm_key
FROM kb.keyword_surface_keys sk
JOIN kb.keyword_surfaces s ON s.surface_id = sk.surface_id
WHERE sk.key_kind = 'initials'
  AND sk.key_value = <normalized input>
  AND s.scope = <requested scope>
  AND sk.norm_version = <current version>
LIMIT 10
```

See [keywordfamily.go](/Users/cding/Workspace/ChenWeb/server/api/ontology/keywords/keywordfamily.go:398) and the table migration [20260803000003_create_kb_keyword_surface_keys.sql](/Users/cding/Workspace/ChenWeb/project_migrations/20260803000003_create_kb_keyword_surface_keys.sql:8).

A clearer table heading would be “Incoming string”:

| Stored surface | Stored initials | Incoming string | Tier-4 result |
|---|---|---|---|
| `machine learning` | `ml` | `ML` | Candidate found |
| `natural language processing` | `nlp` | `NLP` | Candidate found |

**Exactly how is punctuation handled?**

There is no general “ignore punctuation” rule.

Before Tier 4, the complete incoming string undergoes these transformations
(Tier-1):

1. Unicode NFKC normalization.
2. Removal of certain invisible characters and soft hyphens.
3. Conversion of `—`, `–`, `‒`, and `―` to ASCII `-`.
4. Conversion of curly quotation marks to ASCII `'` or `"`.
5. Collapsing spaces, tabs, newlines, and carriage returns.
6. Collapsing uppercase dotted initialisms such as `U.S.A.` to `usa`.
7. Unicode case folding.
8. For Latin-profile strings, removal of possessive `'s`.
9. For Latin-profile strings, removal of a leading `the`, `an`, or `a`.

Other punctuation—including commas, slashes, ordinary periods, parentheses,
and hyphens—is not generically removed.

Commas are therefore only “ignored” accidentally when they do not change 
the first rune or whitespace tokenization of a stored phrase:

| Stored surface | Tokens | Stored initials |
|---|---|---|
| `machine learning` | `machine`, `learning` | `ml` |
| `machine, learning` | `machine,`, `learning` | `ml` |
| `machine,learning` | one token: `machine,learning` | `m` |
| `,machine learning` | `,machine`, `learning` | `,l` |

For incoming queries, the comma remains:

| Incoming string | Normalized lookup value | Matches stored `ml`? |
|---|---|---|
| `ML` | `ml` | Yes |
| `ml` | `ml` | Yes |
| `ML,` | `ml,` | No |
| `M,L` | `m,l` | No |

Similarly:

- `CICD` normalizes to `cicd` and can match stored initials `cicd`.
- `CI/CD` normalizes to `ci/cd`; the slash remains, so it does not match `cicd`.
- `N.L.P.` is a special case: because it is an uppercase dotted initialism, it becomes `nlp`.
- `n.l.p.` is not recognized by that special rule because it requires uppercase ASCII letters; its periods remain.

**Algorithm**

The actual process has two distinct sides.

When a surface is stored:

1. Normalize the complete stored surface.
2. Split it into whitespace-delimited tokens—roughly “words,” but punctuation is not used as a separator.
3. Take the first Unicode rune of every token.
4. Lowercase those runes.
5. Concatenate them.
6. Store the result in `kb.keyword_surface_keys` with `key_kind = 'initials'`.

For example:

```text
Stored surface: "Natural Language Processing"
Tokens:         ["natural", "language", "processing"]
First runes:    ["n", "l", "p"]
Stored key:     "nlp"
```

The implementation is in [normalizer.go](/Users/cding/Workspace/ChenWeb/server/api/ontology/semid/normalizer.go:420).

When an incoming string is received:

1. Normalize the entire incoming string.
2. Count the normalized incoming string’s runes.
3. Skip Tier 4 unless it contains 2–8 runes.
4. Use the normalized incoming string itself as the database lookup value.
5. Find stored `initials` rows with the same key, scope, and normalization version.

**What is returned?**

There are two return levels.

Tier 4 itself returns:

```go
([]NodeCandidate, bool)
```

- One or more database matches: candidate list plus `true`.
- No match: empty/nil candidate list plus `false`.
- A database query error is currently also treated as empty/`false`.

A candidate contains the matched `concept_id`, its stored normalized key, and:

```text
method = "tier4_initials"
```

The resolution kernel then scores and adjudicates those candidates.

One matching concept:

```text
matches:
  - node: <concept_id>
    score: 0.8
    reason: "alternate key match"
    method: "tier4_initials"

verdict: "auto_accepted"
resolved_node_id: <concept_id>
```

Multiple matching concepts:

Suppose both these stored surfaces have initials `ml`:

```text
machine learning
markup language
```

Tier 4 returns both distinct concepts, each with score `0.8`. The kernel then returns:

```text
matches:
  - node: <first concept_id>
    score: 0.8
    method: "tier4_initials"
  - node: <second concept_id>
    score: 0.8
    method: "tier4_initials"

verdict: "ambiguous"
resolved_node_id: <deterministically selected top concept_id>
```

No Tier-4 match does not immediately produce `null`. The waterfall 
continues to Tier 5. If no later tier produces a candidate, the 
final resolution contains:

```text
matches: []
verdict: "deferred"
resolved_node_id: absent
```

In the current implementation, both minimum runes (2) and maximum
runes (8) are hard-coded.

The algorithm Tier-4 uses is:
1. Normalize the incoming input
2. Verifies that the complete normalized input contains 2-8 runes
3. Sends one exact-value SQL query to PostgreSQL
4. PostgreSQL uses an index to find the matching roles

There is also a `LIMIT 10`. Tier 4 returns at most ten database rows 
and deduplicates repeated `concept_id` values in Go. The query has 
no `ORDER BY`, so if more than ten rows qualify, which ten are selected 
is not explicitly deterministic.

**How `kb.keyword_surface_keys` is maintained**

It is application-maintained derived data, not a manually curated map and 
not a database-trigger-maintained table.

When a new surface is created

Suppose this surface is added:

```text
surface_id: kws_123
surface:    machine learning
concept_id: kwc_456
```

`SurfaceStore.CreateSurface` performs the following:

1. Runs the server-side normalizer on `machine learning`.
2. Derives all applicable alternate keys.
3. Inserts the main surface into `kb.keyword_surfaces`.
4. Inserts derived keys into `kb.keyword_surface_keys`.
5. Performs the surface and key writes in one transaction.

For this example, derived rows could include:

```text
surface_id | key_kind | key_value         | norm_version
-----------+----------+-------------------+-------------
kws_123    | alnum    | machinelearning   | 2
kws_123    | sorted   | learning machine  | 2
kws_123    | initials | ml                | 2
kws_123    | singular | machine learning  | 2
```

The currently generated key kinds are:

- `alnum`
- `sorted`
- `initials`
- `singular`

Although the schema permits `phonetic`, the current code deliberately does not write phonetic keys because no lookup tier consumes them.

Key derivation is in [surfaces_store.go](/Users/cding/Workspace/ChenWeb/server/api/ontology/keywords/surfaces_store.go:225).

Replacement behavior

`SurfaceKeyStore.UpsertSurfaceKeys` replaces keys for one surface by:

1. Deleting all existing key rows for that `surface_id`.
2. Inserting the newly derived rows.

```sql
DELETE FROM kb.keyword_surface_keys
WHERE surface_id = $1;

INSERT INTO kb.keyword_surface_keys
    (surface_id, key_kind, key_value, norm_version)
VALUES (...);
```

The primary key is:

```sql
PRIMARY KEY (surface_id, key_kind)
```

Consequently, one surface can have at most one row for each key kind. See [surface_keys_store.go](/Users/cding/Workspace/ChenWeb/server/api/ontology/keywords/surface_keys_store.go:32).

When a surface is deleted

`surface_id` is a foreign key with:

```sql
ON DELETE CASCADE
```

Deleting a row from `kb.keyword_surfaces` automatically deletes all its derived-key rows. This cleanup is enforced by PostgreSQL.

When concepts are merged or unmerged

A merge changes the `concept_id` on `kb.keyword_surfaces`. It does not need to change `kb.keyword_surface_keys`, because derived keys depend on the surface text, not the concept ID. The existing key rows continue to reference the same `surface_id`.

When normalization changes

Every key carries `norm_version`. Tier 4 only reads keys generated under the currently configured version:

```sql
sk.norm_version = currentVersion
```

The source comments say that changing the normalizer version requires reindexing all derived keys. However, I do not find a production reindex/backfill command in the current keyword package. New surfaces receive the current version, but existing surfaces do not appear to be automatically regenerated merely because `CurrentNormalizerVersion` changes. That is a maintenance gap that should be documented or addressed before introducing another normalizer version.

Other caveats

- There is no general database trigger that creates these keys. Directly inserting a row into `kb.keyword_surfaces` bypasses key generation.
- On a duplicate `CreateSurface` call, the code returns the existing surface and does not regenerate its keys. Thus, replaying creation does not repair missing or stale key rows.
- `UpsertSurfaceKeys` returns immediately when passed an empty key list, without deleting old rows. This could leave stale rows if it were ever used to replace an existing surface’s keys with an empty set.
- The public `SurfaceStore` has no operation for changing a surface’s text in place. It only creates surfaces and updates their lock status. This reduces normal update-related drift, but also means maintenance depends on creation/reindex workflows being correct.

#### 9.1.4 Tier 5 Fuzzy Matching
Tier 5 compares the entire normalized input with stored keyword surfaces. 
It first uses trigram similarity to quickly select up to 20 plausible 
matches. It then calculates the Levenshtein edit distance for each 
shortlisted match and rejects candidates that differ too much or violate 
safety rules, such as having different digits. Each remaining candidate 
receives a score between 0 and 1 based on its edit distance, where 1 means 
identical and lower values mean greater differences. The surviving candidates 
and their scores are passed to the adjudication stage, which decides whether
there is a clear match.

More precisely, the flow is:

1. Normalization: the input string should have been normalized by Tier 1 
   when it reaches Tier 5
2. Use trigram similarity to shortlist up to 20 stored surfaces.
2. Calculate the full-string Levenshtein distance for each.
3. Reject candidates that fail the typo and safety rules.
4. Convert edit distance to a score:
   `1 − edit distance ÷ length of the longer string`
5. Return the surviving concepts and their scores for adjudication.

Tier 5 does not necessarily return “the top N” final candidates. It examines 
up to 20 shortlisted surfaces and returns whichever candidates survive its 
rules. Trigram similarity does not contribute to their final scores.

**Result Filter**
The normal auto-accept threshold is **0.80**, but Tier 5 applies 
stricter rules before the caller sees a candidate:

- Input length 4 or fewer: fuzzy matching is disabled.
- Length 5–8: at most one edit, and the first character must match.
- Length 9 or more: at most two edits and a score of at least **0.88**.
- Safety checks can reject a candidate regardless of score, such as differing digits.

The caller then:

- Auto-accepts the highest-scoring candidate if its score is at least **0.80** and it is the unique highest score.
- Returns `ambiguous` if multiple candidates tie for the highest score.
- Requests human review if the best score is below 0.80.

In practice, every candidate surviving Tier 5 already scores at 
least 0.80. Therefore, the caller is primarily deciding whether 
there is a single clear winner, not applying an additional 
meaningful score filter.

### 9.2 Fuzzy guardrails (binding)

```
len ≤ 4       → no fuzzy matching at all
5 ≤ len ≤ 8   → max edit distance 1, first character must match
len ≥ 9       → max edit distance 2, normalized similarity ≥ 0.88
```

Three absolute vetoes, applied **before any threshold** and overridden by no score: **digit** (strings differing in any digit never match), **canonical** (a query that is itself an exact `pref_label` never fuzzy-matches elsewhere), **negation/affix** (`un-`/`non-`/`de-`/`anti-`/`-less`).

### 9.3 `ResolveSurface`/`ObserveOccurrence` side effects — ✅ **Built (2026-08-05, §19 steps 6–8)**, split as originally decided

⚠️ **This subsection described the pre-step-6/7/8 state** (a single `ResolveSurface` conflating read and write, `kb.keyword_mentions`/`MentionStore`, the old K4/K5 defects, D11 as a future requirement). It was not updated when those steps shipped — corrected 2026-08-08. The read/write split this subsection called for **was implemented exactly as decided, at this layer**, not deferred to §9.5:

- **`KeywordFamily.ResolveSurface`** (`keywordfamily.go:426`) is now **pure** — it runs `kernel().Resolve` plus a `merged_into` chase and writes nothing. This is what §9.5's `names.Resolver.ResolveName` calls.
- **`KeywordFamily.ObserveOccurrence`** (called via the flat-argument `ObserveSurface`, used by the REST resolve handler and the mention collector) does the writing: calls `ResolveSurface` first, then —
  1. On a **targeted** name landing `deferred` or `human_review`: D11 auto-creates a provisional concept and assigns it before anything is logged, so the decision row captures the final resolution. `human_review` is no longer dropped — the rejected candidate's method/score is recorded for sampling without being attached (F5 fix, `2026080601-bug`). The **collector** path (untargeted) still just upserts the backlog on a miss.
  2. Appends one row to `kb.semid_decision_log`.
  3. Inserts one occurrence row into `kb.keyword_occurrences` (renamed from `kb.keyword_mentions`, `MentionStore` deleted) — carries `raw_name`/`norm_key`, `resolution_status`, and `decision_log_id` linking it to the row from step 2 (K4 fixed — "what" and "where" now join).
  4. On `auto_accepted`: writes the surface row (with derived keys, K1 fixed) if this exact literal isn't present.
  5. On `deferred`/`human_review` that wasn't auto-created (collector path), or `ambiguous`: upserts the backlog, keyed correctly on `norm_key` (K5 fixed). `ambiguous` always attaches its top-1 pick to the occurrence and queues the backlog, targeted or not — carrying the tied concept set (`tiedCandidatesFromMatches`) so it isn't just a plain miss row; §13.6's offline ambiguity reconciliation later re-ranks that tie with stronger evidence than the online arbitrary tiebreak.

§9.5's `names.Resolver` then layers `ResolveName` (read-only, calls `ResolveSurface`), `ObserveName`, and `ResolveAndObserve` (calls `ObserveOccurrence`) on top — a second, higher-level split for a different concern (the governed/lexical layer merge), not a re-implementation of this one.

### 9.4 Resolver modes — ⚠️ **Defect**

⚠️ **The default is open (K6).** `ResolverMode()` defaults an unset variable to `off`, but the REST handler reads `os.Getenv` directly — `""` fails every `== "off"` gate, so an unset variable leaves the endpoint resolving and writing. One-line fix.

⚠️ **`on` silently disables collection (K7).**

### 9.5 The consumer interface: `names.Resolver` — ⏳ **Not built**

**No consumer may call §9.1–§9.4 directly.** `KeywordFamily.ResolveSurface` mixes reads with four writes, exposes storage concepts (`artifactRef`), ignores the caller's scope (K2), and will keep changing while §20.2 is worked through.

The public contract is `ChenWeb/server/api/ontology/names/`:

```go
type NameResolver interface {
    ResolveName(ctx context.Context, req ResolveNameRequest) (NameResolution, error)
    ResolveNames(ctx context.Context, reqs []ResolveNameRequest) ([]NameResolution, error)
}

type ResolveNameRequest struct {
    Name              string
    Scope             string
    ExpectedTermKinds []string   // "metric_definition", "unit", …
    ExpectedModules   []string
    Language          string
}

type NameResolution struct {
    RawName, NormalizedKey string
    Status                 ResolutionStatus

    ConceptID, ConceptPrefName               string   // ungoverned lexical layer
    TermID, TermPrefName, TermKind, ModuleID string   // governed layer, per the rule below

    Candidates []NameCandidate
    Method     string    // which mechanism resolved it (D11 requirement 1)
    Confidence float64
}
```

**No consumer identity appears** — no `MetricID`, no processor name, no consumer table. A metric asks `["metric_definition"]`; a unit asks `["unit"]`; a new consumer changes nothing in the resolver.

**Five statuses, all normal results:** `term_resolved` (one released term) · `lexical_resolved` (concept, no alignment yet) · `ambiguous` (**top-1 + tied set**) · `unresolved` (**auto-created concept** on the targeted path; empty only for the collector) · `disabled`.

**The layer rule: `TermID` is set only by an unambiguous exact match against a released term's governed label, or by an accepted `aligns_to_term`.** A tier-0–4 lexical hit alone never produces a `TermID` — promoting an ungoverned identity to a governed one silently would erase the distinction the layers exist to keep. Per §16.1 the *alignment* auto-accepts above a threshold; what stays gated is creating the term, not pointing at it.

**Read and write are separate calls.** `ResolveName` performs **no writes — including no decision-log entry**. A debugging tool, an autocomplete, a test, or a reprocessing run must be able to ask without writing:

```go
ObserveName(ctx, occurrence NameOccurrence) error
ResolveAndObserve(ctx, req ResolveNameRequest, occ NameOccurrence) (NameResolution, error)
```

Most production callers use `ResolveAndObserve` — **by choosing it**. The occurrence record is the corrected K4 shape: `artifact_type`, `artifact_id`, `field_path` (consumer-supplied provenance such as `"metric_name"` — opaque to the resolver), `raw_name`, `scope`, `context`, `chunk_ref`, `concept_id`, `term_id`, `resolution_status`, and a link to the decision-log row from the same call.

---

## 10. Data model — ✅ **Built** (migrations `20260803000001`–`00006`)

### 10.1 `kb.keyword_concepts`

`concept_id` TEXT PK (opaque) · `pref_label` · `gloss` · `scope` · `status` CHECK (`active|provisional|merged|deprecated`) · `merged_into` FK · `gloss_source` · timestamps. Indexes `(scope, status)`, `(pref_label)`.

⚠️ `MergeConcept` bypasses the state machine with a direct `UPDATE`: merged/deprecated concepts can be re-merged, chains unchecked, `never_merge` never consulted, and merging a nonexistent id returns success (K8).

### 10.2 `kb.keyword_surfaces`

`surface_id` TEXT PK (content-derived) · `concept_id` FK NOT NULL · `surface` verbatim · `norm_key` ⚠️ caller-supplied on REST (K3) · `norm_version` · `label_role` · `alias_type` · `lang` · `scope` · `confidence` · `provenance` · `locked` · `evidence`.

Unique on `(norm_key, concept_id, scope, label_role)`; indexes `(norm_key, scope)`, `(concept_id)`.

✅ **Fixed (2026-08-05, §19 step 6, migration `20260805000002`).** The uniqueness index is now `(norm_key, concept_id, scope, label_role, lang)` — one concept can hold a `pref` surface per language.
⚠️ **`provenance` is a single string and `evidence` a single text field** — they cannot represent two sources independently asserting the same alias, so one source's support cannot be retracted without destroying the other's. §13.3 requires a separate evidence table; design it in when this schema is next touched.

### 10.3 `kb.keyword_surface_keys`

`(surface_id, key_kind)` PK · `key_value` · `norm_version`. ✅ Written by `derivedSurfaceKeys`/`UpsertSurfaceKeys` on every surface write (K1 fixed, §19 step 5); `phonetic` remains unwritten by design (§6.2).

### 10.4 `kb.keyword_mentions` — the occurrence record

`mention_id` · `artifact_ref` · `chunk_ref` · `context_text` · `ks_id` · `create_time`.

⚠️ **Cannot serve its purpose** (K4): no column names the observed string; `chunk_ref`/`ks_id` always null; `context_text` always empty (the only caller passes `""`). **Decision:** add `surface`/`norm_key` and the §9.5 occurrence fields, link to the decision-log row, and **rename to `kb.keyword_occurrences`** — verified cheap, nothing outside the package reads it.

### 10.5 `kb.keyword_unresolved` — the backlog

`(norm_key, scope)` PK · `surfaces` JSONB · `contexts` JSONB · `candidates` JSONB · `hits` · `status` · `attempts` · `last_attempt` · `priority` · timestamps.

✅ Fixed (§19 step 5, K5): the caller now passes the derived `norm_key`, never the raw surface. 🚧 `contexts` is still keep-last-5, not a reservoir sample. ✅ Fixed: the 200-char cap now slices **runes**, not bytes — no more invalid UTF-8 on multi-byte CJK. ✅ **`candidates` added (migration `20260808000001`)**: the tied concept-id/score/method set from an `ambiguous` verdict, NULL for a plain no-candidate miss — distinguishes the two cases this table previously conflated under one row shape, and is what §13.6's ambiguity reconciliation scans on (`WHERE candidates IS NOT NULL`).

### 10.6 `kb.keyword_rewrite_rules`

`rule_id` · `pattern` (literal only) · `replacement` · `scope` · `enabled` (default false) · `provenance`. 🚧 One-string-to-one-string; cannot express the family generalization that makes rule promotion a cost lever.

---

## 11. Mention collection — 🚧 **Built standalone, not wired**

Tokenizes chunk text and resolves each unique token; runs only in `observe`. Splits on any non-letter/digit rune; 2–50 runes; 59-word English stopword list.

- ⚠️ **Context is always `""`**, so no snippet reaches the backlog — reconciliation stage R1 (harvest) and context disambiguation are dead until fixed.
- ⚠️ **CJK is not segmented** — an unpunctuated Chinese run becomes one 50-rune pseudo-token, filling the backlog with junk on this corpus.
- 🚧 **Single tokens only** — no multi-word surface can ever be observed, removing the class the `sorted`/`initials` keys exist for.

**What it is for.** Two jobs exist; the collector serves one:

1. **Targeted enrichment** — a producer knows a field is a name; it calls `names.Resolver` directly. **No collector.**
2. **Corpus-wide recall** — vocabulary that never becomes a structured field, for a retrieval consumer expanding queries against the lexicon. **This is the collector's job**, and its chain (`collector → backlog → reconciliation → lexicon → retrieval`) is unbuilt after the first arrow. Wiring it today generates rows nothing reads.

**§2's requirement (REQ-1/REQ-3) runs through job 1 and is not blocked by any of this.**

---

## 12. REST API — ✅ **Built** (14 endpoints under `/api/v1/kb/keyword-*`)

Concepts (list/create/get/update/status/merge) · surfaces (create/get/list/lock) · rewrite rules (create/list/toggle) · `POST /kb/keyword-resolve`.

**This is the external admin/diagnostic surface** — where frontend administration pages will attach. `names.Resolver` (§9.5) is the in-process interface for other Go code; they are different consumption modes, not two layers of one thing.

Gaps: ⚠️ unvalidated `norm_key` (K3); ⚠️ `os.Getenv` (K6); 🚧 no REST surface for derived keys, occurrences, or the backlog; 🚧 no endpoint retracts a surface, deletes a rule, or records a `never_merge`.

---

## 13. Reconciliation and vocabulary growth — 🛠️ **Tooling implemented; production activation pending operator bootstrap**

Reconciliation is what makes §2's REQ-1 true for **translations and genuinely different words**, which normalization can never do (§5.3). It is not optional polish.

The offline reconciler, governed source registry, stage-1 importers, reviewed
promotion, and live acceptance are implemented (2026-08-07, §21 Stage 0/1
entry). What remains is operational, not architectural: the operator must
supply approved local artifacts, review the coverage backlog, approve the
acceptance criteria, and publish a versioned seed release before Tier 6 is
enabled against production corpus data.

```
R1 harvest    free extractors (Schwartz–Hearst parentheticals, definitional patterns)
R2 prune      junk, dedup, frequency floor; negative-cache by model@prompt_version
R3 block      lexical (pg_trgm) ∪ semantic (pgvector) to k candidates — biggest cost lever
R4 assemble   compact pipe-row batches; tag unreviewed LLM glosses to avoid self-confirmation
R5 decide     structured output, cheap model bulk; escalate ambiguous/high-blast-radius
R6 validate   deterministic gates — schema, referential, acronym plausibility, role
              consistency, never-merge, lock, scope, blast radius, confidence, digit veto,
              exact-identity authority (authoritative exact_equivalent claim, no conflicting targets)
R7 apply      transactional write through the kernel; decision log; promote rules; snapshot
```

**The reconciler, not the model, owns every write.**

### 13.1 Scoring for tiers 5–6 — ✅ **Decided**

Extend `Score()` to a **continuous** similarity value, **uncapped**. Fuzzy and embedding matches may auto-accept.

This reverses "candidate-only, never auto-accept," which assumed a human adjudicator. At 10⁷–10⁸ occurrences a suggestion nobody acts on is indistinguishable from no answer. Safeguards move from *refusing to decide* to *deciding attributably*:

1. **Tier-specific thresholds** — fuzzy and embedding need a materially higher bar than exact/normalized. Exact key equality and cosine proximity are different kinds of evidence.
2. **The §9.2 vetoes stay hard**, applied before any threshold. They are correctness rules, not confidence heuristics.
3. **Method and score recorded on every decision**, so these populations are sampleable and bulk-re-runnable when a threshold or model changes.
4. **Merging two established concepts is still not automatic** (D10) — a high score proposes an *assignment*, never a structural merge.

Tier 6 requires a **multilingual** embedding model — an English-only model cannot place "luminance" near "亮度", which is the case that motivates the tier. R4's prompt lives in `prompts/` per `ChenWeb/CLAUDE.md`.

> **Revised 2026-08-07 (model-agnostic Tier-6 validation):** tier 5 (fuzzy)
> remains a deterministic auto-accept path, but tier 6 embeddings no longer
> auto-accept by cosine alone. Embeddings only rank a bounded candidate set;
> an automatic tier-6 merge requires at least one authoritative
> `exact_equivalent` identity claim from a registered, enabled,
> license-approved identity-authority source (governed `(source,
> external_id, release)` triple evidence) and no hard veto. High cosine
> without identity defers; conflicting authoritative targets reject. See
> `ChenWeb/docs/superpowers/specs/2026-08-07-model-agnostic-tier6-validation-design.md`
> and the portfolio plan for the governed source/promotion tooling.

### 13.2 Seeding and external vocabulary

The store should not start empty when curated multilingual vocabularies exist. Resolution is a long-solved problem; harvesting beats curating.

- **Wikidata** (not Wikipedia prose) is the strong fit — CC0, downloadable, locally hostable, structurally `item → {labels per language, aliases}`, which is nearly `concept → surfaces`. Two insertion points: **seed content** and **an R1 harvest source** (zero LLM tokens, cheaper than tiers 5–6, so it belongs *earlier* in the waterfall than either).
- **CC-CEDICT** is narrower and targeted at the EN↔ZH case this corpus needs.
- **UMLS** is a strong model and plausible biomedical source but **is not open** — NLM licenses it individually and some constituent vocabularies add restrictions. An importer must preserve those boundaries.
- **Domain standards glossaries** (IEC 60601 / ISO 80601 for this pilot) are likely the **highest-yield source** — general resources cover common vocabulary and miss regulatory jargon.

### 13.3 Schema shapes to design in now

Deferred to build, but these shapes must exist whenever §10 is next touched — retrofitting the first one means migrating every surface row:

1. **Multi-source evidence, not a single provenance string** (§10.2). Required so one source's support can be retracted independently.
2. **External identity mapping** — `(source, external_id, release) → concept_id`, so re-import is idempotent.
3. **Source/release/license registry** — recorded before import, because some sources carry real restrictions that must survive into the data.

### 13.4 Import must not upgrade relation strength — **binding**

A thesaurus's `related`, `broad`, or `narrow` relationship **must never be silently promoted to `exact`**. This is the ADR's mapping-strength discipline (DR13) and it is exactly the §2.3 case: an importer that flattens "brightness ≈ luminance" into an alias makes a domain decision it has no authority to make. Imported relations carry their source's strength; only `exact` produces a same-concept surface, and anything weaker becomes a candidate or a typed relation.

### 13.5 Growth loop

```
new resource release or document occurrence
→ normalize, resolve against the active snapshot
→ record unresolved/ambiguous with raw text, language, context, provenance
→ batch harvest and candidate blocking
→ deterministic evidence + optional LLM adjudication
→ deterministic validation gates
→ transactional concept/surface/mapping update
→ rebuild indexes, publish next snapshot
```

Snapshot activation: build and validate a candidate release while readers stay on the prior immutable snapshot, then switch atomically. A normalizer-version change rebuilds every derived key. Readers must never observe half an import.

### 13.6 Ambiguity reconciliation — ✅ **Built (2026-08-08)**, sqlmock-tested, not yet run against a live DB

**What it's for.** A `deferred`/`human_review` miss gets an identity immediately (D11, auto-create) and tier 6 (§13, above) later decides whether that identity should merge into an existing one. An `ambiguous` verdict is different: candidates already exist and tied — the online path picks the lowest concept id as an arbitrary tiebreak (§8.3) and logs the tie to `kb.keyword_unresolved` (§9.3) rather than guessing confidently. Until this was built, nothing ever revisited that pick — this closes that gap.

**Mechanism, `Reconciler.ReconcileAmbiguous`** (`reconcile.go`), a second pass alongside `Run` (same binary, `cmd/keyword-reconcile`, both passes run every invocation):

1. Scans `kb.keyword_unresolved` rows where `scope` matches and `candidates IS NOT NULL` (`UnresolvedStore.ListAmbiguous`) — i.e. rows an `ambiguous` verdict wrote, never a plain no-candidate miss. The tied set itself (`candidates` JSONB — concept id, original score, original method) is written by `VerdictAmbiguous`'s branch in `ObserveOccurrence` at the moment the tie is logged (`tiedCandidatesFromMatches` extracts the exact top-score prefix `Adjudicate` itself compared against `MaxCandidates`), added by migration `20260808000001`.
2. Per row, in one transaction under the keyword identity lock: chases `merged_into` for every originally-tied concept id (`ConceptStore.FollowMerge`) and keeps only distinct, currently-`active` survivors — a concept that merged away since the tie was logged, or is still `provisional`, is not a safe target for this pass's confidence bar (the same active-only restriction §13's tier-6 targets already use).
   - **Zero survivors:** logged (`no_active_candidate`), row stays `pending`.
   - **One survivor** (the others merged away or were never active): applied directly, no embedding call needed — outcome `collapsed_by_merge`.
   - **Two or more survivors:** embeds the query (the backlog row's first recorded surface literal, or `norm_key` if none) and each survivor's `pref_label` in one `EmbedBatch` call, ranks by cosine similarity, and **auto-applies the top pick only if** it clears a margin over the runner-up (`Reconciler.AmbiguousMarginThreshold`, defaults to 0.15) **or** is independently corroborated by tier 5's own edit-distance check (`fuzzyCandidateScore`) picking the same concept — the identical two-signal discipline `chooseCandidateDecision` already applies to merges (§13, above): embeddings rank, they do not decide alone. Neither signal clearing leaves the row `pending`, now embedding-scored in the decision log for the next run or a human.
3. On an auto-apply (`collapsed_by_merge` or `auto_applied`): writes a new `alt`/`synonym` surface for the query text on the winning concept (`CreateSurface` — idempotent, F3) and marks the backlog row `resolved`. **Never touches `kb.keyword_occurrences`** — occurrences are explicitly append-only (`occurrences_store.go`: "the observe path writes occurrences, never updates or deletes them"), so a past occurrence keeps the answer the system actually gave at the time; only *future* resolves of this literal benefit, by hitting tier 1 against the winner instead of re-tying. **Never merges the tied concepts with each other** — that stays tier 6's job (D10-conservative); this pass only decides which existing concept a query belongs to.
4. Every outcome — applied or deferred — is logged to `kb.semid_decision_log` (`Family: "keyword_reconcile_ambiguous"`) with the full evidence: original scores, which candidates were still live, each one's embedding score, and which one (if any) passed the lexical check. D11's attributability requirement applies here exactly as it does to tier 6.

**Known limit, stated plainly:** if the tie originated because two concepts *both already carry an exact surface* for the literal (a tier-0/1 tie), writing a new surface on the winner does not remove the loser's competing claim — an identical fresh query can tie again. Genuinely eliminating that requires merging the two concepts, which is a structural decision this pass deliberately does not make (see point 3). The case this pass reliably fixes going forward is a tie that was never backed by an exact/norm-key match on both sides (e.g. a shared fuzzy or homonym-scope tie).

**Verify:** `rankAmbiguousCandidates`'s decision policy — margin-only, margin+lexical, lexical-only-below-margin, neither, embedding-error propagation — is unit-tested against a fake embedding client with no database at all (`reconcile_ambiguous_test.go`, `TestRankAmbiguousCandidates*`). The full transactional wiring (merge-chase, active filter, decision log, backlog status, surface write with real derived keys) is proven with sqlmock for all four outcomes (`TestDecideAmbiguousNoActiveCandidateLeavesRowPending`, `TestDecideAmbiguousDefersWhenNeitherSignalClears`, `TestDecideAmbiguousCollapsedWritesWinnerSurface`). **Not yet run against a live PostgreSQL corpus** — the same I2-class gap the rest of this module carries until proven otherwise (§0).

---

## 14. Merge, split, lifecycle — 🚧 **Partial**

`MergeConcept` tombstones; self-merge refused; target existence verified. See D7 for the missing guardrails and the consolidation decision. `locked` surfaces are built but the guarantee is vacuous with no reconciler. `never_merge` is storage-only — no keyword path consults it.

### 14.1 What a merge does to surfaces — ✅ **Decided** (was unspecified)

⚠️ **Verified gap:** `ConceptStore.MergeConcept` updates only `kb.keyword_concepts`; it **does not touch `kb.keyword_surfaces`**. No tier query joins to `kb.keyword_concepts`, filters on `status`, or follows `merged_into`. **So after merging A → B, every surface still carries `concept_id = A`, and every subsequent resolve returns the tombstone A, not the survivor B.** REQ-1 silently regresses to two ids the moment a merge happens — which makes §13's reconciliation, whose entire job is merging, actively harmful in its current form.

**Decision — both halves, because they solve different problems:**

1. **Merge re-points surfaces.** `MergeConcept(A, B)` updates `kb.keyword_surfaces SET concept_id = B WHERE concept_id = A`, in the same transaction as the tombstone. Resolution then costs no extra join and returns B directly.
2. **Each moved surface records `origin_concept = A`** (a new column). This is what makes a split reconstructible — without it, a merge is irreversible, and D11's reversibility requirement is unmet. Across a chain (A → B → C), `origin_concept` is **root-preserving**: `COALESCE(origin_concept, A)` at each hop keeps the deepest origin, not the immediate parent, so A's surfaces still read `origin_concept = A` after landing on C. §14.4 covers what that means for un-merging a middle link.
3. **Resolution still chases `merged_into` for incoming ids.** A consumer that stored `keyword_concept_id = A` before the merge must still resolve to B. The chase applies when a *caller supplies a concept id*, not on the surface lookup path — cycle-guarded, since D7 forbids transitive closure but chains can still form.

Re-pointing alone is not enough (stale consumer ids break); chasing alone is not enough (every surface lookup pays for it forever). Both, or REQ-1 does not hold across a merge.

### 14.2 What a merge does to an `aligns_to_term` assertion — ✅ **Live** (step 12)

If A has an accepted `aligns_to_term` and B does not, the alignment **follows to B** as part of the merge transaction. If A and B are aligned to **different** terms, that is a **conflict and the merge is refused** — two concepts aligned to two distinct governed terms are evidence they are not the same thing, and that evidence outranks whatever similarity proposed the merge. This is the §2.3 `brightness`/`luminance` case arriving from the other direction, and it is a deterministic R6 gate, not a judgement call.

✅ **Live (2026-08-06, step 12):** the conflict gate and follow now run inside `MergeConcept`'s transaction when an alignment store is wired (Task 4 of step 12, commit `msts`).

### 14.3 Which merges may be automatic — ✅ **Decided** (the D10 / §13.1 boundary)

D10 says merging established concepts stays conservative; §13.1 item 4 says the same; Appendix A has reconciliation merge automatically. Both are correct, and the distinction that reconciles them is:

| Merge | Automatic? |
|---|---|
| An **auto-created provisional** concept (D11) into an established one — the Appendix A case | ✅ **yes**, above threshold, with §14.2's conflict gate. The provisional concept exists only because nothing matched; it has no curated content to lose. |
| Two **established** concepts (`status='active'`, human- or import-authored surfaces, or either side aligned to a term) | ❌ **no** — proposal only, per D10. Structural, and it invalidates assignments already made on both sides. |

The test is the concept's own provenance and status, not the similarity score. A high score never promotes a merge from the second row to the first.

### 14.4 Reversibility — ⏳ **Unbuilt**; chained case decided (2026080601-bug F4)

D11 calls reversibility non-optional, but there is no designed path today: `split_concept` does not exist, `ConceptStore` has no unmerge (only `MergeGraph.Unmerge`, which is in-memory and scheduled for deletion, D7), and §12 exposes no retraction endpoint.

**Decision, single hop:** with §14.1's `origin_concept` recorded, un-merge is mechanical — move surfaces whose `origin_concept = B` back to B, clear B's tombstone.

**Decision, chained merges (A → B → C, then unmerge B) — reposition only, do not cascade:** because `origin_concept` is root-preserving (§14.1 item 2), A's surfaces already read `origin_concept = A`, not `B`, even though they are physically sitting on C. `WHERE origin_concept = B` alone misses them — they would stay stranded on C, and A's own concept row (`status='merged', merged_into=B`) would never be revisited. Un-merging B must therefore also **reposition** the surfaces of every concept transitively merged into B — walk `merged_into` backward from B (`X` where `X.merged_into = B`, recursively, e.g. via a recursive CTE) and move *those* surfaces' `concept_id` back to B too, **without** touching their `origin_concept` or their own concept row.

This restores exactly the state that existed immediately before B's own merge — no more:
- A's surfaces land back on B, still tagged `origin_concept = A` (that tag was never wrong; it just needs to be on the right concept again).
- A's concept row is untouched: `status='merged'`, `merged_into=B` — A → B was a separate, still-valid decision; un-merging B does not retract it. `FollowMerge(A)` correctly chases to B, which is live again.
- Only an explicit, later `UnmergeConcept(A, ...)` undoes A → B. Un-merging a descendant never cascades into resurrecting its ancestors as a side effect — each retraction reverses exactly the one merge event it names, matching how each `MergeConcept` call only ever merges one pair.

(Rejected alternative: cascading — also fully restoring every ancestor concept to independently live status. Rejected because it silently undoes merge decisions nobody asked to retract, and conflates "undo this merge" with "dissolve this whole lineage.")

Build it **with** the merge guardrails (§19 step 6), not later: auto-merge (§14.3) must not ship before the thing that undoes it, including the chained case. Until then, reversal is manual database correction, and §13's reconciliation must not be enabled.

---

## 15. Failure modes

### 15.1 Over-merging is the asymmetric risk

| | Under-merge | Over-merge |
|---|---|---|
| Symptom | cache miss → queue | silently wrong answers |
| Detection | automatic | none |
| Cost of fix | one reconciliation cycle | manual archaeology |
| Blast radius | none | every consumer trusting the canonical form |

### 15.2 Mitigations, and whether they are in force

| Failure | Mitigation | In force? |
|---|---|---|
| Canonical label churn | opaque immutable ids | ✅ |
| Normalizer drift | `norm_version` + re-index | ⚠️ never filtered (N4); already drifted (N1) |
| LLM self-confirmation | tag unreviewed glosses | ⏳ reconciliation only |
| Hallucinated ids | referential gate | ⏳ reconciliation only |
| Homonym collapse | scope + `ambiguous` | 🚧 verdict real; scope inert (K2) |
| Queue starvation | junk filter, negative caching, priority | ⏳ columns exist, no logic |
| Caller pollution | input validation | 🚧 non-empty check only |

### 15.3 Human involvement — all non-blocking

| Activity | Volume | Blocking? |
|---|---|---|
| Creating/approving a governed term | hundreds per domain | Gates the **catalog** only (§16.1) |
| Benchmark and gold-set curation | low, offline | No |
| **Exception repair** — a review is wrong; correct the database, re-run | rare, reactive | No — acts after the fact |
| Merging two established concepts | rare, structural | Conservative (D10) |
| Deleting a `never_merge`, unlocking a surface | rare | Yes, deliberately — these *are* the override mechanisms |

**Exception repair is a first-class workflow**, and what D11's attributability and reversibility requirements exist to serve: when a customer reports a wrong review, someone must find *which* decision caused it and correct it in minutes. A design that makes repair expensive forces the human gate back in.

---

## 16. The governed-term bridge and metric integration — ⏳ **Deferred**

### 16.1 Catalog vs. assignment — how governance survives scale

D11 and the ADR's "no LLM activates ontology content" only appear to conflict:

| | **Governed content** (catalog) | **Assignment** |
|---|---|---|
| Example | creating `luminance` as a `metric_definition` term | deciding "显示亮度" in document #47,332 refers to it |
| Volume | **hundreds** per domain | **millions** |
| Gate | **human review stays** — affordable, and what the ADR protects | **fully automatic** (D11) |

**Human-gate the small catalog; auto-assign the large volume to it.** `aligns_to_term` is an *assignment* — auto-proposed, auto-accepted above a threshold, with method/score/evidence recorded.

✅ **Fixed (2026-08-06, §19 step 12, migration `20260806000002`).** `kb.semantic_assertions.subject_ref_kind` (and `object_ref_kind`) now include `keyword_concept`; a keyword concept is a legal assertion subject.

✅ **Fixed (2026-08-06, §19 step 12).** `core:aligns_to_term` (`Kind: "property"`) is seeded in `server/cmd/ontology-seed/content.go` and released (`core@1.0.0`) — the prerequisite this paragraph used to flag as blocking is resolved.

**Governed-catalog bootstrap for the pilot.** REQ-2 also presumes released `metric_definition` terms exist to align *to*. This remains the genuine external gate: §16.1's human path (hundreds of terms, reviewed once) and §13.2's standards-glossary import (IEC 60601 / ISO 80601, and, since 2026-08-07, the built terminology-import adapters — §20.1.7) are both available paths, but whether released `metric_definition` terms actually exist in a given deployment is a live-database question, not a code question — this document cannot answer it from source alone. This is a sibling workstream, not keyword-module work — but it gates §2's acceptance test just as firmly as anything in §19, and someone must own it.

### 16.2 Why `extract_metrics` and `extract_metric_definitions` don't converge

Both run in Phase B, both touch a metric's name, **neither resolves it**. No dependency edge between them, no shared identifier, no join from `kb.metrics.metric_name` to `kb.ontology_terms`. Two documents asserting "luminance is 450 cd/m²" and "亮度为450cd/m²" produce two unrelated rows — §2's failure, exactly.

`kb.ontology_candidates` dedupes by **exact fingerprint only**, so "luminance", "亮度", and "显示亮度" become three separate review items with nothing linking them. The `candidate_matches` column exists for that signal; `TermFamily.ResolveCandidate` computes and writes it correctly but **has no caller** (§20.4).

### 16.3 The metric row: two identifiers, neither forced

| Field | Populated by | Trust | When empty |
|---|---|---|---|
| `metric_name` (unchanged) | `extract_metrics`, as today | provenance | never |
| `keyword_concept_id` | `resolution.ConceptID` | fast, ungoverned | only if the resolver is `disabled` (D11 auto-creates otherwise) |
| `metric_definition_term_id` | `resolution.TermID` — only on `term_resolved` | governed | no released term or alignment yet |
| displayed name | `TermPrefName` → localized concept label → `metric_name` | display only | falls back cleanly |

**Why two and not one.** A keyword auto-accept is cheap and ungoverned; pinning a metric's *authoritative* identity to it alone would let a bad auto-merge silently misfile it with no review boundary. Routing authority through the governed term keeps that boundary while the raw name always remains as provenance.

**Where the call goes:** in the consumer of `extract_metrics`' output, after parsing and validation, **before the metric row is persisted** — not inside `associate_semantics` (§17.1). `extract_metrics` itself is not modified: no prompt change, no extraction change.

✅ **Call site decided (step 12, 2026-08-06): a `ResolvingMetricsStore` decorator wraps `MetricsSQLStore`.** It is constructed by `newResolvingMetricsStore(db)` inside `defaultProductionRuntimeComponents` at `doc-processing/runtime.go`, where `NewMetricsProcessor` receives its `Store` — **one seam**, not one per write path. `keyword_concept_id` comes from `resolution.ConceptID`; `metric_definition_term_id` comes from `resolution.TermID` on `term_resolved` only. Metric rows are still written by `MetricsSQLStore.SaveMetrics`/`UpsertMetrics` (`doc-processing/extract-metrics.go`), reached from `FinalizeChunkBatch` and from the enrichment path, but every path now flows through the single decorator, so the two write paths cannot diverge the way the two normalizers did (D3).

---

## 17. Consequences for adjacent subsystems

These are not keyword-module work, but this integration forces them and they have no other home.

### 17.1 `AssociateSemantics` — ⏳ **After the pilot, not blocking it**

The `AssociationResolver` *registry* is genuinely generic. The *package* is not: `init()` self-registers `"metric"` and `"provision"` in the ontology package rather than consumers registering during composition, and `governedMetricAssertionKinds`, the literal `mea:measured_by`, and `canonicalUnitForm`/`unitQuantityKindMap` live in the same file. Adding a metric-specific resolution step there would deepen the coupling rather than use a seam.

**Decision:** `processMetric`/`processProvision` bodies and their domain policy move to consumer adapters; the ontology package stops self-registering. Sequenced *after* the metrics pilot per DR12's vertical-slice framing.

### 17.2 QUDT / `resolveUnitTerms` — ⏳ **Data fix first**

`resolveUnitTerms` should eventually be `ResolveName(Name:"ms", ExpectedTermKinds:["unit"])` — but doing that today moves a broken lookup behind a nicer interface. Two confirmed gaps in `qudt-import/main.go`:

1. **Existing term IDs are skipped, including their labels** (line 238) — which is why 4151 quantity terms have no `kb.ontology_term_labels` rows and a label lookup resolves nothing.
2. **No unit→quantity-kind relationship is imported at all.**

`canonicalUnitForm`'s hardcoded map is filling those holes — a workaround, **not a pattern worth copying**. Fix order: backfill labels, import the relationships, then retire the maps in favour of governed-label resolution.

---

## 18. Evaluation and required tests

**Online:** coverage/hit rate at tiers 0–4, unresolved rate, ambiguity rate, median latency.
**Reconciliation:** auto-attach precision, **false-merge rate** (hard gate), backlog burn-down, human-override rate.
**Candidate generation:** blocking recall/precision, reduction ratio.

### 18.1 Test coverage today — ✅ **substantially rewritten since this table was written; corrected 2026-08-08**

⚠️ **Stale.** This table described the P3 Track B delivery (2026-08-04), before the P4 §19 fix pass (2026-08-05) rewrote the exit tests and later steps (11, 12, Stage 0/1) added per-tier, alignment, reconciliation, and identity-evidence coverage. As of the most recent addition (§13.6, 2026-08-08), `keywords`/`semid`/`names` together define **209** `Test*` functions across 24 files (`keywords`: 20 files/176 funcs; `semid`: 3 files/20 funcs; `names`: 1 file/13 funcs) — not 51. This count will drift again the next time code changes; treat it as a snapshot method (`grep -rc "^func Test" *_test.go`), not a fact to keep re-copying by hand. Notably:

| File | Funcs | What it verifies |
|---|---|---|
| `normalizer_test.go` | 10 | individual steps, now including the N1 acronym-survives-singularization case |
| `concepts_store_test.go` / `surfaces_store_test.go` | 31 | sqlmock CRUD — SQL shape, not semantics (unchanged characterization) |
| `keywordfamily_test.go` | 11 | constants and `off`/nil-DB early returns |
| `tiers_test.go` | 4 | **added 2026-08-06 (§19 step 11) — drives each tier (0–5) against sqlmock-expected SQL individually**, closing the "no test drives a tier" gap this table used to note |
| `keyword_exit_test.go` | 9 | ✅ **rewritten (2026-08-05, §19 step 9) — no longer assertion-free.** Each of the 9 exit criteria (E1–E9) is its own test with real sqlmock expectations and assertions; the old `TestExitCoverageComplete` trivial-count check is gone. |
| `reconcile_identity_integration_test.go` | 2 | live PostgreSQL (`chenweb_test`), gated on `TEST_DATABASE_URL` — the I2 live-validation proof (§0, §20.1.12) |

This correction only re-verifies the files above; it does not re-audit every one of the 192 functions for assertion quality, so treat this as "the table's headline claims are outdated," not "coverage is now exhaustively verified."

### 18.2 The required test set

**Correctness (before trusting the module):** per-tier query and score coverage; a normalizer table containing `AIDS`/`SaaS`/`Kubernetes`/`AWS's`; a scope round-trip (write at `ks`, read at `ks`); an **unset** `KEYWORD_RESOLVER_MODE` writing nothing.

**§2 acceptance (the DR23 requirement) — two phases, not a fixture that begins with the answer:**

*Bootstrap/growth:* start with empty tables → import a versioned fixture connecting `Luminance` and `亮度` through one external id → ingest an observed `显示亮度` with language, context, and unit evidence → run reconciliation with real validation gates → assert **one concept, three evidence-bearing surfaces** → activate atomically and prove re-import is idempotent → add a conflicting `亮度` concept and prove ambiguity is preserved rather than over-merged.

*Online:* resolve all three clean names plus dirty variants (`␠␠LUMINANCE␠␠`, `Ｌｕｍｉｎａｎｃｅ`, `显示​亮度`) → assert **the same `ConceptID`** for all while each raw string is preserved → assert **zero LLM/network calls** on every `ResolveName` → assert language-driven label selection → assert scope, term kind, and language participate in ranking → assert `ResolveName` writes nothing and `ResolveAndObserve` writes exactly one linked occurrence + decision → assert `disabled` writes nothing.

*End-to-end (§2.2, steps 4–5):* 🏗️ **APP-SPECIFIC — owned by the Document Review app's own test suite, not required for this module to pass.** Recorded here only as the observable proof that DR23's example works: 140 documents with mixed phrasings produce **exactly one comparison-matrix row**; a 141st document with a fifth phrasing does not create a second. REQ-4's side of this (§2.4) is now built; what remains before this is observable is this module's own REQ-1/REQ-2 (steps 11–12, §19) plus REQ-3's consumer call.

**Structural:** assert **no keyword or ontology code contains a metric-, resource-, or processor-specific branch** to make any of the above pass.

---

## 19. Build order

1. **K6** — one line, only live-impact defect.
2. **K2 + K5** — corrupt unreconstructable data.
3. **N1 (+N2)** — forces a `norm_version` bump; observe-mode data before this must be recomputed.
4. **One normalizer** (D3): delete `NormFunc` and the `semid` built-in, remove `Normalizer()` from `FamilyAdapter`, consolidate primitives — combined with `Kernel.Resolve(ctx, input, scope)` (§8.2), same files and call sites.
5. **K1 + N3 + K3** — one "derived keys are actually derived" change.
6. **K8 + K9 + K10 + merge semantics (§14.1–§14.4)** — guardrails per D7; delete `MergeGraph`; explicit `MaxCandidates`; **and the merge behaviour §14 now specifies**: re-point surfaces with `origin_concept` (new column), chase `merged_into` for caller-supplied ids, the §14.2 alignment-conflict gate, and **un-merge, built in the same step as merge** — auto-merge must not ship before the thing that undoes it (D11 reversibility).
7. **K4** — reshape the occurrence table, rename to `kb.keyword_occurrences`, link to the decision log. **Design §13.3's shapes in here** — retrofitting multi-source evidence later means migrating every surface row.
8. **D11 auto-first** — top-1 on `ambiguous`, auto-create on targeted miss, method/score recorded, low-confidence and auto-created populations queryable as sets.
9. **Dead-code deletions** (§20.4) and the §18.2 correctness tests.
10. **`names.Resolver`** (§9.5) — the read-only contract plus `ObserveName`/`ResolveAndObserve`.
11. **§2 REQ-1** — tiers 5–6 and the minimum reconciliation loop that unifies translations. ✅ **DONE (2026-08-06, step 11):** tier 5 fuzzy matching (pg_trgm-backed, §9.2 guardrails) wired into `CandidateNodes`; offline `keywords.Reconciler` + `cmd/keyword-reconcile` for tier 6 (reconciliation-only per §22 Q2). Per the step-11 plan's Non-goals, R1/R2/R4/R5 and a `kb.keyword_reconcile_runs` watermark table are explicitly deferred — this is the minimum loop, not the full R1–R7 pipeline. Migration `20260806000001`.
12. **§2 REQ-2/REQ-3** — seed and release the `aligns_to_term` predicate term (§16.1), extend `subject_ref_kind`, build the alignment producer, add the metric columns, and place the consumer call (§16.3). REQ-3's persisted `metric_definition_term_id` is this module's complete output here; its shape does not bend to accommodate P4's internal key scheme — platform independence (§2.1). ✅ **DONE (2026-08-06, step 12):** the call-site decision was recorded as a `ResolvingMetricsStore` decorator — one seam at the metrics processor's `Store` construction in `doc-processing/runtime.go` (§16.3); `subject_ref_kind` was extended to admit `keyword_concept` subjects (migration `20260806000002`); `core:aligns_to_term` was seeded into the core module and released (`core@1.0.0`); and the two external prerequisites (§16.1 governed-catalog bootstrap, §13.2 standards-glossary import) still gate the full §2.2 acceptance test.

Steps 1–9 are contained inside `ontology/keywords` and `ontology/semid`. Steps 10–12 make this module's half of §2 true, and once step 12 lands this module's responsibility for §2 is fully discharged.

🏗️ **APP-SPECIFIC, not a build-order step of this module.** §2 REQ-4 — `metric_key` *is* the term id, decided and enforced in `comparison/store.go` (§2.4) — belongs to the Document Review app (P4) and was implemented there, not here. This module's job ends at persisting a governed `metric_definition_term_id`, in its own canonical form, on every metric row; steps 1–12 never depended on REQ-4's resolution. Flagged here only because §2.2's full end-to-end acceptance example isn't observable until REQ-1–3 are also built.

**Two prerequisites owned elsewhere**, both gating §2 and neither scheduled here: the `aligns_to_term` predicate term must be seeded and released (§16.1), and released `metric_definition` terms must exist to align to — via the human catalog path or a standards-glossary import (§13.2). Someone must own both.

---

## 20. Status

### 20.1 Deferred

R1–R7 · `on`-mode wiring · collector pipeline wiring · context-token disambiguation · Double Metaphone · resource import · multi-word and CJK-segmented collection · backlog admin surfaces · rewrite-rule auto-promotion · `merged_into` chase at resolve time · **I2 live PostgreSQL proof**.




#### 20.1.1 Tier 6's online resolve path** (§9.1, §13.1, §22)

⚠️ **Stale — corrected 2026-08-08.** This entry described the pre-step-11 (2026-08-04/05) state and was never updated after step 11 shipped 2026-08-06. Current state:

- **Tier 5** (fuzzy matching, trigram + edit distance, misspellings like `kubernets`) is **built and wired into the online resolve path** (`KeywordFamily.CandidateNodes`) — it is not deferred and does not belong in this list. See §9.1.
- **Tier 6** (multilingual embedding/ANN, cross-lingual identity like `luminance ↔ 亮度`) is **built**, but as the **offline** `keywords.Reconciler` / `cmd/keyword-reconcile` only (§13). This is §22 Q2's explicit, decided answer — "reconciliation-only" — not a gap: keeping the online resolve path free of the embedding-model runtime dependency. The code says so directly (`keywordfamily.go:92-93`, citing §22 Q2). Since 2026-08-07 (Stage 0/1), an offline tier-6 merge additionally requires an authoritative `exact_equivalent` identity claim from an enabled, approved, governed source — cosine similarity alone no longer merges (§13.1's 2026-08-07 revision).
- **What is genuinely still deferred** is only the *online* variant of tier 6 — embedding the query synchronously inside `CandidateNodes`. That decision has not been revisited since 2026-08-06. Two local multilingual models (`qwen3-embedding-0-6b`, `nomic-embed-v2-moe` via llama.cpp) are already in `.models.toml` if it ever is.

**On resource import unblocking this:** importing, approving, and promoting external vocabularies (QUDT/BIPM/UCUM/Wikidata, §20.1.7) feeds the *offline* reconciler's identity-evidence store — it makes offline tier-6 merges safer and more authoritative, but it does not change where tier 6 runs. It cannot unblock the online path; only reopening §22 Q2 can.

#### 20.1.2 R1–R7** (§13)
The seven-stage **reconciliation pipeline** — the offline batch process that unifies *genuinely different words and translations* (which no normalization can do, §5.3):
- **R1 harvest** — free extractors (Schwartz–Hearst parentheticals, definitional patterns)
- **R2 prune** — junk/dedup/frequency floor; negative-cache by `model@prompt_version`
- **R3 block** — lexical (pg_trgm) ∪ semantic (pgvector) down to *k* candidates; the biggest cost lever
- **R4 assemble** — compact batches; tag unreviewed LLM glosses to avoid self-confirmation
- **R5 decide** — structured output, cheap model in bulk; escalate ambiguous/high-blast-radius
- **R6 validate** — deterministic gates (schema, referential, never-merge, lock, scope, digit veto…)
- **R7 apply** — transactional write through the kernel, decision log, promote rules, snapshot

The reconciler, not the model, owns every write. This is the machinery Appendix A Stage 5 depends on.

| Stage | What it does | Why it's a separate stage |
|---|---|---|
| R1 Harvest | Pulls candidate synonym/alias evidence for free — no LLM cost. Parenthetical patterns like "X (also known as Y)" (Schwartz–Hearst extraction), definitional sentence patterns, and external vocab sources like Wikidata. | Free signal should be collected before anything that costs money. |
| R2 Prune | Dedupes, applies a minimum-frequency floor (don't bother reconciling a word seen once), and keeps a negative-cache keyed by `model@prompt_version` (don't re-ask the LLM the same question under the same prompt). | Cuts junk before it reaches the expensive stages. |
| R3 Block | For each unresolved concept, finds a bounded candidate set (`k` items) of "things it might be the same as," using cheap lexical (pg_trgm) and semantic (pgvector) similarity. | Called "the biggest cost lever" — avoids comparing every concept to every other concept. |
| R4 Assemble | Packages blocked candidates into compact batches for an LLM call; tags which labels are LLM-generated-but-unreviewed so later steps don't treat an unconfirmed guess as ground truth. | Batching controls LLM cost; the tagging prevents self-confirmation bias. |
| R5 Decide | Sends batches to a cheap LLM for a structured-output same/different judgment, in bulk; escalates ambiguous or high-blast-radius cases. | The one stage where a model makes a judgment call. |
| R6 Validate | Deterministic, non-LLM gates: schema/referential checks, acronym plausibility, role consistency, `never_merge`, locking, scope, blast-radius limits, confidence thresholds, digit veto — plus, as of the 2026-08-07 rebuild, exact-identity authority (must have an authoritative `exact_equivalent` claim, no conflicting targets). | The gate is what makes R5's LLM output safe to act on — nothing R5 says is trusted directly. |
| R7 Apply | The actual write: transactional, through the kernel, with a decision-log audit entry, rewrite-rule promotion (so future lookups hit cheap tier-3 SQL instead of re-running reconciliation), and a new snapshot published. | "The reconciler, not the model, owns every write." |

#### 20.1.3 `on`-mode wiring** (§9.4, D9)
`KEYWORD_RESOLVER_MODE=on` removes the gate so resolution answers actually reach consumers. Currently unusable because **no consumer exists**. (The narrower K7 bug — `on` accidentally disabling collection — was fixed in §21 step 1; the remaining problem is deeper: nothing is wired to *consume* results in `on` mode.) Effectively this is the consumer/metric-integration wiring.

#### 20.1.4 Collector pipeline wiring** (§11)
The mention collector is built standalone, but its downstream chain — `collector → backlog → reconciliation → lexicon → retrieval` — is unbuilt after the first arrow. Its job is **corpus-wide recall** (vocabulary for a retrieval consumer expanding queries). Wiring it today would write rows nothing reads. Note §2's requirement runs through *targeted* enrichment, not the collector, so this doesn't block the pilot.

#### 20.1.5 Context-token disambiguation** (§5.4)
For homonyms (`ML` → machine learning *and* millilitre), the design is: scope disambiguates first, then **context**. Neither works — scope is inert (K2) and context disambiguation is unbuilt — so global-scope homonyms just return `ambiguous`. This item is the using-surrounding-tokens-to-pick-the-right-sense mechanism.

#### 20.1.6 Double Metaphone** (§6.2)
The phonetic-key algorithm. The key bundle defines six keys (`exact`, `norm`, `alnum`, `sorted`, `phonetic`, `initials`); **`phonetic` is a stub read by no tier**. Double Metaphone would populate it (match by pronunciation). It's dead — §21 step 9 even removed the dead phonetic-key write.

#### 20.1.7 Resource import** (§13.2–§13.4)

⚠️ **Partially stale — corrected 2026-08-08.** This entry described resource import as wholly future work; substantial tooling was built 2026-08-07 (§21, Stage 0/1) and should not be listed as flatly "Deferred."

**Built:** `server/api/ontology/terminology` adapters for SIRP (BIPM), IEC seed, Wikidata, UCUM, and QUDT; `cmd/terminology-import` (import/diff/**activate**/rollback) and `cmd/terminology-coverage`; the governed source registry (authority role, allowed scopes, content checksum, license review, provenance, approval) with immutability triggers; staging tables for artifacts/catalog/labels/relations/negative decisions; and reviewed positive/negative promotion into `keyword_external_ids`/`keyword_surface_evidence`/`never_merge`. This satisfies §13.3's schema shapes and §13.4's binding rule (import never upgrades relation strength — enforced via the relation vocabulary in `SourcePolicy`, `server/api/ontology/keywords/source_policy.go`). Live-tested 2026-08-07: all five stage-1 fixtures imported twice with idempotent replay against a rebuilt `chenweb_test`.

**Still open:** the coverage report's `ready` gate (`server/api/ontology/terminology/coverage.go`) reported `ready=false` as of the last recorded run, pending operator approval — and a source is only *live* for reconciliation once `cmd/terminology-import activate` has run for its `(deployment_key, source, release)`, a distinct step from import + license approval. Whether that gate is now satisfied is a live-database question this document cannot answer from source alone — confirm current `kb.keyword_identity_deployments`/coverage state directly rather than trusting this spec's point-in-time snapshot. **CC-CEDICT** and general-purpose **domain standards glossaries beyond IEC** (e.g. ISO 80601) are not among the built adapters (SIRP/IEC/Wikidata/UCUM/QUDT) and remain unbuilt.

#### 20.1.8 Multi-word and CJK-segmented collection** (§11)
Two collector gaps: (a) **CJK isn't segmented** — an unpunctuated Chinese run becomes one 50-rune pseudo-token, filling the backlog with junk on this predominantly-Chinese corpus; (b) **single tokens only** — no multi-word surface can ever be observed, which removes exactly the class the `sorted`/`initials` keys were built for.

#### 20.1.9 Backlog admin surfaces** (§12, §20.4)
REST/UI admin pages for the backlog (`kb.keyword_unresolved`). §12 notes there's no REST surface for the backlog (nor derived keys nor occurrences); §20.4 explicitly keeps `UnresolvedStore.ListUnresolved` alive "for a backlog admin page."

#### 20.1.10 Rewrite-rule auto-promotion** (§13 R7, §10.6)
When reconciliation learns an alias, R7 **"promote rules"** — write it as a rewrite rule so future lookups hit at tier 3 (free SQL) instead of re-running reconciliation. It's a cost lever. §10.6 notes the current one-string→one-string rule shape can't express the family generalization that would make promotion actually pay.

#### 20.1.11 `merged_into` chase at resolve time** (§14.1 item 3)
When a caller supplies a concept id that has since been merged (it stored `concept_id = A` before the A→B merge), resolution must follow `merged_into` to return survivor B. Applies to caller-supplied ids, not the surface-lookup path; cycle-guarded.

> ⚠️ **This one is internally inconsistent.** §20.1 lists it as deferred, but the implementation record (§21, step 6, commit `b16b`) and Appendix A Stage 5 both state the chase **is now in place** ("resolution chases the survivor"). So this entry appears stale relative to §21.

#### 20.1.12 I2 live PostgreSQL proof** (§0)
I2 is the finding that the module has **never been validated live**: "No run against real PostgreSQL with real document text. Every defect was found by reading code, not by a failing test." The deferred item is actually running the module against real PostgreSQL with real document text — i.e., executing the §18.2 acceptance tests against a real DB rather than sqlmock. It's the overarching validation gap that hangs over everything else.

**Resolved 2026-08-07** by the governed-portfolio plan's Task 8:
`ChenWeb/server/api/ontology/keywords/reconcile_identity_integration_test.go`
runs against real PostgreSQL (`chenweb_test`, rebuilt and migrated) and proves
the exact-identity merge independent of cosine, deferral without a reviewed
mapping, conflicting-identity rejection, one audit row per decision, and
family-lock serialization under concurrent promotion/reconciliation. The
§0 "Never validated live" row is updated accordingly.

#### 20.1.13 End-to-end `human_review` regression test

⚠️ **Reasoning partly stale — corrected 2026-08-08.** This entry's premise — that `human_review` is "unreachable through real tier scoring" because tiers 0–4 only ever produce 1.0 or 0.8 — was true before step 11 and is no longer the full picture: tier 5's continuous fuzzy score can land below the 0.8 `MinScore`, making `human_review` the ordinary below-threshold outcome now (see the code comment at `keywordfamily.go` in the `ObserveOccurrence` verdict switch, which documents exactly this transition). What remains true: as of this correction, no test in `keywords/*_test.go` drives a real below-threshold tier-5 match end-to-end through `ObserveOccurrence` and asserts the D11 auto-create branch fires (only a narrow `statusForVerdict` unit check exists, `occurrences_store_test.go`). That gap is real; the stated reason for it is not.

### 20.2 Defects

**All 13 fixed 2026-08-05** (P4 §19 steps 1–9, §21) — this table is the historical record of what was found, not an open list.

| # | Defect | Where | Effect | Size |
|---|---|---|---|---|
| **K6** | resolve endpoint reads `os.Getenv`; unset ≠ `off` | `keyword_handlers.go:371` | fail-safe default is open | 1 line |
| **N1** | singularization after case-folding | `normalizer.go` | `AIDS→aid`, `SaaS→saa`; every `norm_key` affected | small + version bump |
| **K2** | kernel uses `Family.Scope()` (constant `"_"`) | `kernel.go:65`, `keywordfamily.go:69` | ks-scoped surfaces unfindable | small |
| **K5** | raw surface passed as `norm_key` | `keywordfamily.go:308` | backlog doesn't dedupe | 1 line |
| **K1** | nothing writes `kb.keyword_surface_keys` | resolver + REST | tiers 2/4 match nothing | small |
| **N3** | `initials` uppercase; tier 4 uses the query's initials | §6.4 | tier 4 cannot bridge | design + small |
| **K3** | REST stores unvalidated `norm_key` | `keyword_handlers.go:194` | index can disagree with normalizer | small |
| **K8** | `MergeConcept` bypasses state machine and guardrails | `concepts_store.go:218` | re-merge; `never_merge` unchecked | small |
| **K4** | occurrence table has no column for the string; provenance never populated; no link to the decision log | `keywordfamily.go:253` | holds nothing reconcilable | schema + wiring |
| **K7** | collector gates on `IsObserveMode()` | `keyword_mention_collector.go:43` | `on` turns collection off | 1 line |
| **N2** | possessive rule needs a trailing space | §6.4 | `AWS's` → `aws'` | 1 line |
| **K9** | `TermFamily.Scope` returns `""` while its comment claims module scoping; SQL then disables the filter | `termfamily.go:37` | term search ignores module | small |
| **K10** | `TermFamily` `MaxCandidates` at zero value | `termfamily.go:32` | `ambiguous` unreachable | 1 line |

⚠️ **This list is stale — corrected 2026-08-08; all but one item below were fixed, mostly in the same P4 pass, without this line being updated.** Verified against current code:

- ✅ Fixed: `norm_version` unfiltered (N4) — tier 1/2/4 queries now filter on it (`keywordfamily.go`).
- ✅ Fixed: `surface_id` hashed before role defaulting — the id is now derived *after* the role default (`surfaces_store.go`, comment cites this exact defect).
- ✅ Fixed: unreachable `human_review` arm (§9.3) — routes into D11 auto-create (F5 fix, `2026080601-bug`).
- ✅ Avoided, not "dead": `phonetic` key is deliberately never written (§6.2) — the schema permits the kind for if a phonetic tier lands, but nothing writes it, so there is no dead-write defect.
- ✅ Fixed: `lang`-less uniqueness (§10.2) — migration `20260805000002`.
- ✅ Fixed: assertion-free exit tests (§18.1) — `keyword_exit_test.go` rewritten with real per-criterion assertions.
- 🚧 **Still open:** the 200-char context cap now slices runes, not bytes (fixed — no more invalid UTF-8), but the "keep-last-5" sampling in `kb.keyword_unresolved.contexts` is still literally keep-last-5, not a true reservoir sample (§10.5) — the code comment calling it "reservoir sample" is itself imprecise.

**Fix order:** K6 → K2/K5 → N1 → K1/N3/K3 → K8/K9/K10 → K4.

### 20.3 Operational consequence

Explicitly `off` → inert. **Unset** → inert for the collector, *not* for the REST endpoint (K6). In `observe` → rows written but mis-keyed (K5), inconsistently scoped (K2), context-free. **Treat all observe-mode data as disposable**, consistent with the planned data reset.

### 20.4 Dead-code register

11 of 12 audited exported functions have zero production callers — a consequence of building bottom-up, one table per chunk, with no consumer. Classified, not deleted wholesale:

| Item | Classification | Decision |
|---|---|---|
| `SurfaceKeyStore.UpsertSurfaceKeys` | Wired — called from `SurfaceStore.CreateSurface` | **Wired** (K1 fixed, §19 step 5) |
| `UnresolvedStore.ListUnresolved` | R2/R3 + a backlog admin page | **Keep** |
| `UnresolvedStore.UpdateUnresolvedStatus` | R7 transitions | **Keep** |
| `MentionStore.ListMentions` | R1 context harvest + an occurrences admin view | **Keep** |
| `NeverMergeStore.Add`/`IsNeverMerge`/`List` | D7's merge guardrails + R6's gate | **Keep** — live with K8 |
| `SnapshotStore.Record`/`Latest` | snapshot activation (§13.5) | **Keep** |
| `TermFamily.ResolveCandidate` | writes `candidate_matches` for the candidate-review UI | **Keep** — wire a caller |
| `MentionStore.InsertMentions` | **Speculative** — a `for` loop calling `InsertMention`; no transaction, **zero batching benefit**, no planned consumer | **Delete** |
| `semid.MergeGraph` (7 funcs) | **Orphaned duplicate**, superseded before it had a caller | **Delete** after porting guardrails |

**Rule going forward:** no store method merges without a caller in the same change, *or* an entry here naming the consumer that will call it. The sqlmock tests are what let this accumulate invisibly — they assert SQL shape against a mock, proving nothing about reachability.

---

## 21. Implementation record

P3 Track B, 2026-08-04, 7 commits on `main`: `641b73b6` concept store · `2355449a` surface + surface_keys · `8e709aaa` mention/unresolved/rewrite · `c6c4a1a3` normalizer · `5e746c96` `KeywordFamily` + `NormFunc` · `e6b8fb55` REST + routes · `b5ffb554` mode, collector, exit criteria.

```bash
cd ChenWeb
go test ./server/api/ontology/keywords/... ./server/api/ontology/semid/...
go build ./... && go vet ./...
```

These pass and prove little (§18.1) — no test would fail if any §20.2 defect were introduced.

P4 §19 build order, 2026-08-05, 8 commits on `main` (jj, commit ids): `5fb6` step 1 — K6/K7 mode gates fail closed · `11f7` steps 2–4 — one shared normalizer (N1–N3), norm_version bump, scoped kernel resolve · `be91` step 5 — server-derived surface keys (K1/N3/K3) · `b16b` step 6 — guarded merge with §14.1 surface re-point, un-merge, chase; `MergeGraph` deleted · `e679` step 7 — K4 occurrences reshape + §13.3 evidence shapes; `MentionStore` deleted · `b7e0` step 8 — D11 auto-first (targeted miss → provisional concept, `gloss_source='auto:d11'`; collector exempt) · `ec62` step 9 — §20.2 leftovers (surface_id hashed after role defaulting, dead phonetic key write removed) + §18.2 correctness tests · `d1ab` step 10 — `names.Resolver` (§9.5 facade: governed released-term layer over the keyword lexical layer, five statuses, read/write split). Migrations `20260805000001–3`.

```bash
cd ChenWeb
go build ./... && go vet ./server/api/ontology/... ./server/api/kbhandler/... ./server/api/doc-processing/...
go test ./server/api/ontology/keywords/... ./server/api/ontology/semid/... ./server/api/ontology/names/...
```

These now carry real assertions: §18.1 exit tests rewritten, per-tier query and scope round-trip coverage added (§18.2), D11 and §9.5 facade covered with sqlmock. Step 11 (REQ-1 tiers 5–6) is implemented — see the step-11 entry below; step 12 (REQ-2/3 `aligns_to_term` + metric integration) is implemented — see the step-12 entry below. Step 13 was never this module's work (§2.4) — 🏗️ **APP-SPECIFIC, done separately:** the Document Review app's `metric_key` gap is decided and enforced as of 2026-08-06 (`ComparisonStore.validateMetricKey`, `comparison/store.go`). Pre-existing environment-dependent failures in kbhandler (search-registry/topic-category) and doc-processing remain; the keyword/semid/names packages are green.

Step 11 (tier 5 + minimum reconciliation loop), 2026-08-06, jj commit ids: `304a` step-11 plan · `7c3a` pg_trgm + trigram indexes (migration `20260806000001`) · `145c` semid PrecomputedScore · `d885`/`0f2a` §9.2 fuzzy guardrails · `c92b`/`8acb` tier-5 fuzzy matching wired into `CandidateNodes` · `429c` kernel-level e2e test · `008d` ConceptStore reconciliation queries · `d8b5` offline `keywords.Reconciler` (tier 6 embedding merge) · `e901`/`8396`/`82a4` review fix-ups · `7afd` `cmd/keyword-reconcile` binary. No LLM call; R1/R2/R4/R5 and a runs/watermark table are explicitly deferred (minimum loop, not the full R1–R7 pipeline); tier 6 runs reconciliation-only per §22 Q2.

```bash
cd ChenWeb
go build ./... && go vet ./server/api/ontology/... ./server/api/kbhandler/... ./server/api/doc-processing/...
go test ./server/api/ontology/keywords/... ./server/api/ontology/semid/... ./server/api/ontology/names/...
```

Green on keywords/semid/names; build and vet clean including the `cmd/keyword-reconcile` binary (compiles; runtime needs a DB/embedding server). kbhandler (search-registry/topic-category) and doc-processing retain only their pre-existing environment-dependent failures — none of step 11's commits touch those packages.

Step 12 (REQ-2/3 `aligns_to_term` + metric integration), 2026-08-06, jj commit ids: `utzkonsllqsy` migration — `subject_ref_kind` CHECK extended with `keyword_concept` on both the subject (NOT NULL) and object (nullable) sides, and `kb.metrics` gains `keyword_concept_id` (FK to `kb.keyword_concepts`) + `metric_definition_term_id` (deliberately no FK, the same reason every other term-id-reference column in this schema has none, §2.4); migration `20260806000002` · `kurzxzxyoqzl` seed — `core:aligns_to_term` property seeded and released (`core@1.0.0`) · `qxrzszuzsouv` alignment store (`AlignmentsStore` + `AllowedRefKinds`) · `mstsuzspxtnl` §14.2 gate + follow live in `MergeConcept` (a different-term alignment conflicts and refuses the merge; a sole alignment follows to the survivor) · `twoyxzvtwzuu` resolver follows `aligns_to_term` and auto-aligns on an exact pref-label match (REQ-2) · `wpvswuvomvon` `ResolvingMetricsStore` decorator wrapping `MetricsSQLStore`, constructed by `newResolvingMetricsStore(db)` at `NewMetricsProcessor` in `doc-processing/runtime.go` — one seam, not one per write path (§16.3) — persisting `keyword_concept_id` from `resolution.ConceptID` and `metric_definition_term_id` from `resolution.TermID` on `term_resolved` only (REQ-3). The spec's two asserted step-12 hard prerequisites — the `subject_ref_kind` schema CHECK and predicate seeding — are both resolved: the first by migration `20260806000002`, the second by the seeded+released predicate. What still gates the live §2.2 end-to-end run is external to this module: released `metric_definition` terms to align *to* (§16.1 governed-catalog bootstrap, §13.2 standards-glossary import).

```bash
cd ChenWeb
go build ./... && go vet ./server/api/ontology/... ./server/api/doc-processing/... ./server/cmd/...
go test ./server/api/ontology/keywords/... ./server/api/ontology/semid/... ./server/api/ontology/names/... ./server/api/ontology/assertions/...
```

Green on keywords/semid/names/assertions; build and vet clean. doc-processing retains only its pre-existing environment-dependent failures (the step-11 baseline of ~15; Task 6 confirmed the set did not grow) — none of step 12's commits grow it.

Stage 0/1 (governed terminology portfolio + identity-authorized Tier 6), 2026-08-07, jj commit ids: `8123` keywords: enforce identity evidence scope · `dade` keywords: bound triple evidence reads · `7db0` keywords: make reconciliation writes transaction atomic · `bb21` keywords: make tier 6 identity-authorized and model agnostic · `d363` ontology: add governed terminology import runner · `31e9` ontology: import stage 1 terminology snapshots · `864e` ontology: preserve QUDT semantics and promote reviewed identities · Task-8 closure commit (integration test, docs, coverage report). Migration `20260807000001` adds the governed source registry (authority role, allowed scopes, authoritative relations, content checksum, license review, adapter version, provenance, approval, `identity_authority`), immutability triggers, artifact/catalog/label/relation/negative-decision/UCUM staging tables, and the audited `keyword_identity_deployments` pointer with append-only history. New tooling: `server/api/ontology/terminology` adapters (SIRP, IEC seed, Wikidata, UCUM, QUDT) and `cmd/terminology-import` (import/diff/activate/rollback), `cmd/terminology-coverage`, and reviewed positive/negative promotion into `keyword_external_ids`/`keyword_surface_evidence`/the provenance-linked `never_merge` veto. Tier 6 write authority is now granted only by an enabled, approved, authoritative `exact_equivalent` claim; embeddings only rank diagnostics (see the 2026-08-07 model-agnostic validation spec).

```bash
cd ChenWeb
go build ./... && go vet ./server/api/ontology/... ./server/cmd/...
go test ./server/api/ontology/keywords/... ./server/api/ontology/terminology/... ./server/cmd/terminology-import/... ./server/cmd/keyword-reconcile/... ./server/cmd/qudt-import/...
TEST_DATABASE_URL='host=/tmp user=cding dbname=chenweb_test sslmode=disable' \
  go test ./server/api/ontology/keywords/ -run TestReconcileIdentityIntegration
```

Live acceptance on a rebuilt `chenweb_test`: all project migrations applied
(guarded Down/Up round-trip verified), all five stage-1 fixtures imported
twice with idempotent replay, `tier6-primary` enabled on
`iec-60050-845/2020`, and the integration suite green. The pilot-scope
coverage report stores the unresolved-pair backlog and reports
`ready=false` pending operator approval (plan Task 8).

Ambiguity reconciliation (§13.6), 2026-08-08: migration `20260808000001` adds `kb.keyword_unresolved.candidates` (JSONB, NULL for a plain miss); `unresolved_store.go` gains `TiedCandidate`, `UpsertUnresolved`'s new `candidates []TiedCandidate` parameter (merged by concept id, capped at 10, `mergeTiedCandidates`), and `ListAmbiguous`; `keywordfamily.go`'s `VerdictAmbiguous` branch now captures the exact top-score tie via `tiedCandidatesFromMatches` and passes it through; `reconcile.go` gains `Reconciler.ReconcileAmbiguous`/`decideAmbiguous`/`rankAmbiguousCandidates` (margin-or-lexical-corroboration auto-apply, active-only merge-chased survivors, never touches append-only `kb.keyword_occurrences`, never merges concepts); `cmd/keyword-reconcile` runs it as a second pass after `Run` every invocation. Design agreed in conversation, not a numbered spec build step.

```bash
cd ChenWeb
go build ./... && go vet ./server/api/ontology/keywords/... ./server/cmd/keyword-reconcile/...
go test ./server/api/ontology/keywords/... ./server/cmd/keyword-reconcile/...
```

Green. New tests: `TestRankAmbiguousCandidates*` (5, fake embedding client, no DB) cover the decision policy in isolation; `TestDecideAmbiguousNoActiveCandidateLeavesRowPending`, `TestDecideAmbiguousDefersWhenNeitherSignalClears`, `TestDecideAmbiguousCollapsedWritesWinnerSurface` (sqlmock) cover the transactional wiring for three of the four outcomes, the last with surface-key expectations computed from the real normalizer rather than hand-derived. **Not run against a live database** — sqlmock-verified only, same I2-class caveat as the rest of this module.

---

## 22. Open questions

1. **Auto-accept thresholds per tier** (§13.1). Not derivable from first principles — measure against the gold set, ship conservative, tune.
2. **Whether tier 6 belongs online at all.** Tier 6 must embed *the query* at resolve time. A **local** model is CPU work, consistent with §3's non-goal. A **hosted API** puts a network call on every miss — breaking the non-goal, the latency budget, and independence from a third party. Either host a small multilingual model locally, or **restrict tier 6 to reconciliation** (offline, batched) and let the online path stop at tier 5. **Recommendation: reconciliation-only unless a local model is already in the stack** — D11's auto-creation means a first-seen foreign-language name gets an identity immediately regardless, so deferring the merge costs little. **✅ Decided 2026-08-06: reconciliation-only.** Two local multilingual embedding models are already in `.models.toml` (`qwen3-embedding-0-6b`, `nomic-embed-v2-moe` via llama.cpp), but the online resolve path was kept free of that runtime dependency by explicit choice.

   ⚠️ **Note (2026-08-08), because this gets asked whenever new resources land:** the 2026-08-07 identity-authorization work (governed source registry, `terminology-import`, QUDT/BIPM/UCUM/Wikidata adapters, §20.1.7) does **not** revisit this decision and cannot unblock it by itself. That work makes an *offline* tier-6 merge trustworthy (it now requires an authoritative `exact_equivalent` claim from an approved source, not cosine alone — §13.1's 2026-08-07 revision); it says nothing about the per-query embedding cost that is this question's actual subject. Importing, approving, and even activating a source only changes what the offline reconciler is allowed to merge — it does not put an embedding call inside `CandidateNodes`. Unblocking tier 6 online requires reopening this question directly, not more governed data.

   **Is it actually blocked, or just a decision? Both — one policy reason and one real (small) engineering gap:**
   - **Policy reason (the one §22 Q2 states):** a per-query embedding call adds latency/cost to every resolve that misses tiers 0–5. Not infeasible — a local model already exists (`qwen3-embedding-0-6b`, `nomic-embed-v2-moe`) — but the tradeoff was judged not worth it *given that D11 already removes the downside*: a miss gets a provisional concept immediately either way, so deferring the *merge* decision to a batch job costs convergence speed, not correctness or availability.
   - **Engineering gap (not previously documented here):** `keywords.Reconciler.embedConcepts` (`reconcile.go`) re-embeds **every live concept's `pref_label` from scratch, in memory, on every reconciliation run** — there is no persisted vector column or index on `kb.keyword_concepts`. Wiring tier 6 into `CandidateNodes` today, naively, would mean either re-embedding the entire concept universe per resolve call (does not scale) or building a persisted ANN index first. This second part **is** a real blocker for a naive implementation — but it is a small, already-solved problem in this exact codebase, not new engineering: `kb.search_artifacts` already has a working, **online**, query-time-embedding pattern to copy — `vector(1536)` column + `pgvector` HNSW cosine index (migration `20260603000001`), embeddings computed once at write/index time, and `computeQueryEmbedding` (`kbhandler/search_embedding_query.go`) embeds the query synchronously inside a request handler with a documented best-effort/fallback contract ("ok=false ... tells the caller to fall back to lexical-only search"). Nothing here is unprecedented in this system; it has just never been applied to `kb.keyword_concepts`.

   **What "online tier 6" should be, if this is reopened** — a concrete, scoped proposal, **not decided or built**:
   1. Add `pref_label_embedding vector(N)` (+ `embedding_model_id`, for the same reason `reconcile.go` already tags every score with a model id) to `kb.keyword_concepts`, with an HNSW cosine index — same shape as `kb.search_artifacts`'s migration.
   2. Compute the embedding **at concept write time** (creation, and on `pref_label` change) — not at query time. This is the same principle tiers 0–5 already follow: expensive work happens once, at write time, so every subsequent read is one indexed lookup (§1's economic thesis, extended to embeddings).
   3. Online tier 6 then costs **one query-time embedding call plus one indexed ANN query** (`ORDER BY pref_label_embedding <=> $1 LIMIT 20`, mirroring tier 5's `similarity() ... LIMIT 20` blocking shape) — not a re-embed of the corpus. Follow `computeQueryEmbedding`'s best-effort contract: on embedding-call failure or timeout, fall back to "tier 6 unavailable this call" (equivalent to today's tier-7 miss), never block or error the whole resolve.
   4. **Keep two things separate that "tier 6" currently conflates as one:** (a) **surface→concept attachment** — a query with no lexical/fuzzy match gets compared against existing concepts' embeddings; a single unambiguous high-similarity hit, gated the same way tiers 0–5's `AutoAcceptPolicy` already gates auto-accept, attaches the surface to that concept. This is no riskier than what tiers 0–5 already do online, and reversible the same way (surfaces can be re-pointed; nothing structural changes). It is a natural 8th rung on the existing ladder, not new risk. (b) **concept→concept merging** (two already-established identity graphs becoming one) stays reconciliation-only, offline, batched, and identity-authority-gated per D10/§13.1 — that operation's blast radius (§15.1: "silently wrong answers," "manual archaeology") is what actually justifies caution, not the embedding call itself, and cosine-plus-a-provisional-concept is a fundamentally lower-stakes decision than cosine-plus-two-established-concepts.
   5. Applying D11's own price (§4 D11: attributable, reversible, sampleable) is what would make (4a) safe to auto-accept online, exactly as tier 5 is safe today.
   6. **Mirror the offline reconciler's own priority order, don't reinvent one.** §9.1's tier-6 entry shows `decideCandidate` never trusts cosine alone even offline — it prefers a unique lexical (tier-5-style) match, then a single authoritative identity claim, and only falls back to "flag for later" on embedding evidence alone. An online (4a) design should keep that same ordering: embeddings rank candidates, but auto-accept should require the *same* kind of corroboration (a tight lexical match or an authoritative claim), not cosine similarity by itself — otherwise online tier 6 would be *less* conservative than the offline path it's modeled on, which defeats the reason offline tier 6 was tightened in the first place (2026-08-07).

   This proposal is recorded here so "what it should be" isn't lost, but it is **not decided and not built** — implementing it means a new migration, a query-time embedding dependency in the resolve hot path (even if local and best-effort), and new tests proving the fallback behavior under embedding-service failure. Treat this paragraph as a design sketch to approve or reject, not as current or committed behavior.
3. **Is `brightness` the same metric definition as `luminance`?** (§2.3) A domain-owner decision. The module must represent either answer and must never infer it.

---

## 23. Documentation impact

**What changed.** The addendum `doc-2026080404` is merged here; there is now one document for the module. DR23 is stated as **the governing requirement** with a decomposition and an acceptance test (§2), rather than being an implication readers had to reconstruct. Appendix A's requirement content — multilingual policy, normalization requirements, resource-import shapes, growth loop, required tests — is distributed into §6.3, §7, §13, and §18.2 as **requirements, not deferred appendix material**; what remains of it is a worked example (Appendix A below).

**Affected.** ADR `2026072901` (DR15/DR16/DR23) is the design authority, unchanged — this operationalizes it. `2026080501-bug` and `2026080502-bug` hold the reasoning behind these decisions.

**Now stale.** `2026080404-spec` is superseded by this merge and should not be edited further. `2026080101-spec` §7 is **wrong**, not merely superseded — it states keyword merges go through the kernel's `MergeGraph`; they do not (D7). The Track B handoff `2026080401` and log `2026080402` record the slice as complete against exit criteria that §18.1 shows were self-certified by assertion-free tests. The `-- +goose Up` comments in migrations `…0005`/`…0006` describe behaviour the code does not implement.

---

## Appendix A. Worked example — four names, one row

*This is an illustration of §2's requirement, not a source of requirements. Every rule it exercises is stated normatively in the sections above; nothing here adds to them.*

**Setup.** A bilingual corpus. Luminance appears as `Luminance`, `luminance`, `␠␠LUMINANCE␠␠`, `Ｌｕｍｉｎａｎｃｅ`, `亮度`, `显示亮度`, and `显示​亮度` across many documents. The target: one comparison-matrix row.

**Stage 1 — normalization collapses spelling variants (§6).** Four of the seven collapse immediately, because they are variants of *one* string:

| Input | `norm_key` | By which step |
|---|---|---|
| `Luminance` | `luminance` | case-fold (7) |
| `␠␠LUMINANCE␠␠` | `luminance` | whitespace (5) + case-fold (7) |
| `Ｌｕｍｉｎａｎｃｅ` | `luminance` | NFKC (1) + case-fold (7) |
| `显示​亮度` | `显示亮度` | zero-width strip (2) |

The other three do not: `亮度` → `亮度`, `显示亮度` → `显示亮度`, `luminance` → `luminance` — **three different keys**. Normalization has done all it can; §5.3 is why.

**Stage 2 — the first name creates the concept.** `extract_metrics` yields `metric_name = "Luminance"`. `names.Resolver.ResolveName` (§9.5) misses every tier, and per D11 **auto-creates** a provisional concept `kwc_L` with surface `Luminance`, returning its id. The metric persists `metric_name` unchanged plus `keyword_concept_id = kwc_L`. **No human was involved and the metric is not left without an identity.**

**Stage 3 — variants attach automatically.** A later document says `␠␠LUMINANCE␠␠`. Tier 0 misses (different literal); **tier 1 hits** on the shared `norm_key`. The resolver returns `kwc_L` and records the new literal as an `alt` surface. Same for `Ｌｕｍｉｎａｎｃｅ`. Cost: zero LLM calls, zero human decisions.

**Stage 4 — a translation creates a second concept, deliberately.** A Chinese document yields `亮度`. Every tier misses — `亮度` shares no derived key with `luminance`, and no amount of normalization will change that. D11 auto-creates `kwc_B`.

**There are now two concepts for one meaning. This is the designed intermediate state, not a failure** — and it is strictly better than the alternative: the metric *has* an identity, is groupable and countable, and the duplication is a detectable condition rather than an absence.

**Stage 5 — reconciliation unifies them (§13).** The batch job blocks `kwc_B` against existing concepts using multilingual embeddings (tier 6, §13.1): `亮度` and `luminance` sit close in vector space where edit distance sees nothing. R6's gates check unit compatibility (both `cd/m²`), scope, `never_merge`, and the §14.2 alignment-conflict check. `kwc_B` is an **auto-created provisional** concept, so §14.3 permits the merge to be automatic.

R7 merges `kwc_B` into `kwc_L`, and — per §14.1 — **re-points `kwc_B`'s surfaces to `kwc_L` in the same transaction**, recording `origin_concept = kwc_B` on each so the merge stays reversible. Without that re-pointing the merge would be cosmetic: the surface `亮度` would still carry `concept_id = kwc_B`, and the next resolve would return the tombstone.

`显示亮度` follows the same path. **Result: one concept, all seven strings.** REQ-1 of §2.1 is satisfied — by auto-creation plus reconciliation, not by normalization and not by a person.

⚠️ **Corrected 2026-08-08 — this note was stale.** As of 2026-08-06 (§19 step 11), Stage 5's machinery is built: the offline `keywords.Reconciler` (`cmd/keyword-reconcile`) does propose merges automatically — it blocks candidates via `ConceptStore`, scores them with tier 6 embeddings, and (since 2026-08-07) requires an authoritative identity claim before merging, not cosine alone. The §14.1 merge machinery (`MergeConcept` re-pointing surfaces with `origin_concept`, `UnmergeConcept`, survivor-chasing resolution) is also in place and is what R7 calls to execute the proposed merge. **What is not yet proven is this exact scenario end to end against a live, real-world corpus** — the reconciler has been run in its integration test (`reconcile_identity_integration_test.go`, real PostgreSQL) but not, as of the last recorded update, against a genuine 亮度/luminance-style cross-lingual pair using one of the local embedding models. This stage still accurately describes the *design* in §13–§14; it now also describes *shipped* code, not just design.

**Stage 6 — the governed term (§16).** A domain owner creates `mea:luminance` as a `metric_definition` term once, through the human-gated catalog path — hundreds of such terms, reviewed once each. An `aligns_to_term` assertion connects `kwc_L` to it, **auto-proposed and auto-accepted** above threshold, because assignment is not catalog creation (§16.1).

**Stage 7 — one row.** Every metric from every document now carries `metric_definition_term_id = mea:luminance`. The comparison run keys on term id (REQ-4) and renders **one row** holding all documents' assertions. A 141st document with an eighth phrasing enters at Stage 4 and converges through Stage 5 without anyone being asked.

**What would have broken it, and which rule prevents each:**

| Failure | Prevented by |
|---|---|
| `Ｌｕｍｉｎａｎｃｅ` treated as a distinct metric | NFKC (§6.1 step 1) |
| `亮度` left unresolved, its documents missing from the row | D11 auto-create |
| `亮度` and `luminance` never unified | tier 6 + reconciliation (§13) |
| `brightness` silently folded in as an alias | §13.4 — relation strength is never upgraded on import; §2.3 — a domain decision |
| The row keyed on a label, breaking when the label changes | Cardinal rule 1 (§5.1) — join on `concept_id`/`term_id`, never a string |
| `AIDS`-style acronym destroyed en route | N1's fix (§6.4) — **in place since 2026-08-05** |
