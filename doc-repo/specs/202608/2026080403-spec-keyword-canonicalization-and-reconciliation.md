# Keyword Canonicalization and Reconciliation — Specification

- **DocID:** `doc-2026080403`
- **Status:** Adopted — **the single reference for the keyword module**
- **Date:** 2026-08-04; rewritten 2026-08-05; **addendum `doc-2026080404` merged in 2026-08-05**
- **Component:** SemOS / ChenWeb — keyword lexicon, the DR15/DR16 keyword identity family
- **Supersedes:** `2026080101-spec-…-merged.md`, `2026072703-spec-…-2.md`, `2026072301-spec-….md`, and **`2026080404-spec-metric-name-canonicalization-addendum.md`** (merged here; retained on disk as history only)
- **Design authority:** ADR `2026072901` — DR15 (shared kernel), DR16 (merged keyword design), **DR23 (the governing requirement, §2)**, DR12 (metrics is the pilot slice)
- **Reasoning record:** `2026080501-bug-name-resolver-qutd.md` (the `names.Resolver` correction) and `2026080502-bug-keyword-module-review.md` (findings F1–F8). Design conclusions live here; the analysis behind them lives there.

---

## 0. Status at a glance

| | |
|---|---|
| **Built** | 6 tables, 6 CRUD stores, the keyword normalizer, `KeywordFamily` (tiers 0–4), 14 REST endpoints, a standalone mention collector, `KEYWORD_RESOLVER_MODE` gating. P3 Track B, 7 commits, 2026-08-04. |
| **Works today** | Tier 0 (exact) and tier 1 (normalized) resolution against an existing surface; concept CRUD and lifecycle; the REST authoring surface. |
| **Broken** | 13 verified defects (§20.2). Highest impact: K6 (resolver open by default), N1 (normalizer destroys acronyms), K2 (scope ignored), K5 (backlog mis-keyed). |
| **Not built** | Tiers 5–6, reconciliation R1–R7, `aligns_to_term`, `on`-mode wiring, `names.Resolver`, resource import, the metric integration. |
| **Never validated live** | No run against real PostgreSQL with real document text (I2). Every defect was found by reading code, not by a failing test. |
| **Design gap** | **D11 (auto-first)** — the shipped design assumes a human drains queues. At 10⁷–10⁸ occurrences nobody can. Revised 2026-08-05; the code does not yet reflect it. |

**Do not build on this module until §20.2's K1/K2/K3/K5 and N1 are fixed** — they silently corrupt data a later fix cannot reconstruct. **And do not build the remaining features as originally specified**: D11 changes what tiers 5–6, reconciliation, and `aligns_to_term` are each supposed to *do*.

**Phase context.** P1, P2, P4 (generic runtime), and P5 are built. P3 Track A (assertions, evidence, Phase D) is built and live-validated. **P3 Track B — this module — is built but never live-validated**, which is why its defect list is longer than its siblings'. Nothing in §20.2 invalidates Track A or the P4/P5 runtime; the defects are contained inside `ontology/keywords` and `ontology/semid`.

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

**"Reach one row" is the acceptance criterion for this entire module.** It is not aspirational and it is not deferred: the comparison matrix that the target application renders has one row per metric definition, and if four phrasings of luminance produce four rows, the application is wrong on its primary screen.

### 2.1 What "one row" decomposes into

| # | Requirement | Satisfied by | Status |
|---|---|---|---|
| **REQ-1** | All spellings and translations of one metric name resolve to **one keyword concept** | tiers 0–4 for variants of one string; **auto-create + reconciliation merge** for genuinely different words and translations (D11, §13) | ⚠️ tiers 0–1 only; cross-lingual unification unbuilt |
| **REQ-2** | That keyword concept resolves to **one governed `metric_definition` term** | an accepted `aligns_to_term` assertion (§16.2) | ⏳ nothing built; blocked by a schema CHECK |
| **REQ-3** | Every metric artifact carries that **term id**, regardless of how its document phrased the name | `names.Resolver` called by the consumer of `extract_metrics`, persisting `metric_definition_term_id` (§16.3) | ⏳ nothing built |
| **REQ-4** | The comparison matrix's row key is **derived from that term id** | ⚠️ **unspecified — see §2.4** | ⚠️ **gap** |

**REQ-1 and REQ-2 are this module's responsibility. REQ-3 is the integration. REQ-4 is a dependency on P4 that is currently unmet and unspecified.**

⚠️ **Correction (2026-08-05).** An earlier revision of this table marked REQ-4 "✅ by design in P4" and claimed the matrix "falls back to grouping by raw string" when the term id is null. **Both statements were wrong**, and the second was invented — no such fallback exists in the code. See §2.4.

### 2.4 The REQ-4 gap: `metric_key` is not `metric_definition_term_id`

Verified against the P4 comparison code:

- `kb.ontology_comparison_scopes.metric_keys` (JSONB) pins the row universe, and `kb.ontology_comparison_cells.metric_key` (**TEXT, no foreign key**) is part of each cell's uniqueness constraint — `UNIQUE (comparison_run_id, target_object_id, metric_key, subject_family, authority_family)`.
- **`metric_definition_term_id` appears nowhere in the comparison package** (`comparison/store.go`, `compare.go`, `constraint.go`, `evaluate_cell.go`), and there is no `term_id` column on either comparison table.
- Cell comparison itself is driven by `QuantityKind` / `Unit` / `Component` (`constraint.go`), not by any term identity.

**So the matrix's row key is an opaque string (`metric_key`, e.g. `"time_to_alarm"`) with no defined relationship to the governed term id that REQ-3 produces.** Even a perfect REQ-1/REQ-2/REQ-3 implementation does not deliver "one row" until this is closed: the keyword module would correctly assign one term id to all 140 documents' metrics, and the matrix would still group by whatever populates `metric_key`.

**This must be resolved before §2.2's acceptance test can pass.** Two candidate resolutions, undecided:

1. **`metric_key` *is* the governed term id** — the comparison scope is populated with `metric_definition` term ids, and the column is simply named from an earlier design. Cheapest if true; needs confirmation from whoever owns P4, plus a documented constraint that scope authors may only use term ids.
2. **An explicit mapping** — `metric_definition_term_id → metric_key`, owned by the comparison layer, so the matrix keeps its own key space while remaining derivable from governed identity.

Until one is chosen and recorded, REQ-4 is a **known break in the chain**, not a satisfied requirement. It is the one part of §2 that this module cannot fix on its own.

### 2.2 The acceptance test

Given a corpus where luminance is phrased as `Luminance`, `luminance`, `亮度`, and `显示亮度` across many documents:

1. All four resolve to **one** `concept_id`.
2. That concept has **one** accepted `aligns_to_term` to a released `metric_definition` term.
3. Every extracted metric from every one of those documents carries that **one** `metric_definition_term_id`.
4. A comparison run for that metric definition produces **exactly one row**, with all documents' assertions inside it.
5. Adding a 141st document with a fifth phrasing does not create a second row — it either resolves (R1) or auto-creates a concept that reconciliation merges (§13), converging to one row without human intervention.

Step 5 is the one that distinguishes a system that works at scale from one that works on a fixture.

### 2.3 A domain question DR23's own example raises

DR23 lists **brightness** alongside 亮度 / 显示亮度 / luminance. Photometrically, *brightness* is a perceptual attribute and *luminance* is a measured quantity — they are near-synonyms in ordinary use and **different quantities in a standards context**. Whether they are one metric definition or two is a **domain-owner decision**, not something this module may infer.

The requirement on the module is therefore narrower and stricter than "merge things that look alike": it must be able to represent **either** answer, and it must never auto-merge them on lexical or embedding similarity alone. This is the ADR's own `exact | close | broad | narrow | related` mapping-strength discipline (DR13) applied to the case DR23 happens to use as an illustration. §13.4 states how a resource-imported "related" pair is prevented from silently becoming "exact."

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
| **occurrence** | one table, incomplete | `kb.keyword_mentions` — **no column for the observed string** | ⚠️ K4 |
| **surface** | real entity | `kb.keyword_surfaces` — verbatim text, role, alias type | ✅ |
| **lexform** | **not an entity** — a derived value | the `norm_key` column | ✅ (⚠️ K5 on the backlog) |
| **concept** | real entity | `kb.keyword_concepts` | ✅ |

Only two of four are database entities. Lexform is deliberately a *value*: an index key, not a governed record. **Matching is always `name` against `kb.keyword_surfaces`**, never against occurrence — `kb.keyword_mentions` participates in no lookup.

### D2. One shared resolution kernel — ✅ **Built**

`normalize → candidates → score → adjudicate` lives once, in `ontology/semid/`, instantiated per family. What legitimately differs: `CandidateNodes` (which tables), `AutoAcceptPolicy` (governed vs. not), `Scope`. **Normalization does not differ — see D3.**

### D3. Normalization is shared, not per-family — ⚠️ **Defect**

**Lexical normalization depends on the language of the string, never on which family is asking.** A Chinese term label and a Chinese keyword surface need identical treatment; nothing about "being governed" changes what NFKC does.

The code violates this. `keywords.KeywordNormalizer` (ten steps) and `semid.Normalizer`'s built-in (`ToLower` → `TrimSpace` → collapse-whitespace, plus punctuation-stripping at v2) are two implementations of one operation — the second a strict subset of the first. They duplicate outright: `semid.collapseSpace` and `keywords.collapseWhitespace` are byte-identical logic under different names, and the `0x2E80` CJK threshold is hardcoded in both. `NormFunc`, the hook letting a family override the built-in, has **one user** — added so it could bypass a normalizer doing a subset of its own work.

**Decision:** one implementation, shared. Delete `NormFunc` and the `semid` built-in; remove `Normalizer()` from `FamilyAdapter`; consolidate the primitives. Profiles, if needed, key on **language and version** — never on family.

### D4. SKOS label roles — ✅ **Built**

`pref` (canonical display) · `alt` (synonyms, acronyms — visible) · `hidden` (misspellings — searchable, never displayed).

### D5. Ambiguity is first-class — ✅ **Built**, semantics revised by D11

*Silently* picking the most frequent candidate produces an error invisible to caller and metrics. Under D11, `ambiguous` is returned **with the top-1 pick** — the caller gets a usable id *and* an explicit contested signal. What is rejected is unrecorded guessing, not deciding.

### D6. Store surfaces; derive keys; version the normalizer — ⚠️ **Defect**

Every key is recomputable from `surface + norm_version`, so a normalizer change is a re-index, never data loss. The schema honours this; the write paths do not (K3: caller-supplied `norm_key`; K1: nothing writes derived keys). **Decision:** the server derives all keys on every write path and *rejects* a caller-supplied `norm_key`.

### D7. Merges are tombstones; no transitive closure — ⚠️ **Defect**

Merges set `merged_into` and keep the row. Merges are never transitive — one bad edge must not chain two clusters.

**Merge is implemented twice with disjoint capabilities, neither complete:**

| | `semid.MergeGraph` | `ConceptStore.MergeConcept` |
|---|---|---|
| Persistence | **none** (in-memory maps) | Postgres |
| Refuses `never_merge` / already-merged | yes | **no** |
| Follows `merged_into` at read time | yes | **no** |
| Production callers | **0** | the merge endpoint |

**Decision:** delete `MergeGraph`; port its four guardrails into `ConceptStore.MergeConcept` and the resolve path, backed by the persisted `NeverMergeStore`.

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

### D11. Auto-first: every path terminates in a decision — 🆕 **Load-bearing, not implemented**

**Scale forces this.** 10⁵–10⁶ documents × ~10² artifacts = 10⁷–10⁸ name occurrences. Reviewing even 0.1% is unaffordable. **Any design where a routine path waits for a person stalls permanently.**

| Situation | Old | **Auto-first** |
|---|---|---|
| No concept matches a **targeted** name | `deferred` → backlog → wait | **auto-create a provisional concept**, assign it |
| Multiple concepts tie | return no id | **`ambiguous` + the top-1 pick**, flagged |
| Fuzzy/embedding candidate | never accepted | **may auto-accept** above a tier threshold (§13.1) |
| Below threshold | a queue nobody drains | decide, record method + score, mark for **sampling** |

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

Note `显示 亮度` (with a space) → `norm_key` = `显示 亮度`, which does **not** equal `显示亮度`. The `alnum` key would bridge them at tier 2 — but nothing populates that table (K1), so the bridge does not work.

### 6.2 The key bundle — 🚧 computed, never persisted

Six keys: `exact`, `norm` (primary index), `alnum`, `sorted`, `phonetic`, `initials`. Only `norm` is stored (on the surface row). The other four belong in `kb.keyword_surface_keys`, **which no code path writes** (K1) — so tiers 2 and 4 query an empty table. `phonetic` is a stub read by no tier.

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
| `human_review` | resolved below threshold | yes, flagged for sampling — **not a queue** |

⚠️ `TermFamily` can produce only two of four: `MaxCandidates` at its zero value gates off tie-detection, and `Enabled: false` blocks auto-accept (K10).

### 8.4 Shared tables — ✅ **Built** (P2)

`kb.semid_decision_log` · `kb.semid_never_merge` · `kb.semid_snapshots`, scoped by `family`.

---

## 9. Working mode

### 9.1 The tier ladder

| Tier | Method | Score | Status |
|---|---|---|---|
| 0 | exact surface match | 1.0 | ✅ |
| 1 | `norm_key` match | 1.0 | ✅ |
| 2 | `alnum`/`sorted` key | 0.8 | 🚧 query built, table empty (K1) |
| 3 | rewrite rules → retry 0–1 | 1.0/0.8 | ✅ |
| 4 | `initials` bridge | 0.8 | ⚠️ N3 |
| 5 | fuzzy (trigram + edit distance) | continuous | ⏳ may auto-accept (§13.1) |
| 6 | embedding (multilingual ANN) | continuous | ⏳ may auto-accept (§13.1) |
| 7 | miss → backlog / auto-create | — | ✅ backlog; ⏳ auto-create |

`CandidateNodes` exits at the **first tier producing candidates**. **Tier 2 is a data gap; tier 4 is a logic defect.** Tier 3 matches the **raw** surface with byte equality, so a rule `K8S → Kubernetes` does not fire for `k8s`; one rule fires at most; the retry covers tiers 0–1 only.

### 9.2 Fuzzy guardrails (binding)

```
len ≤ 4       → no fuzzy matching at all
5 ≤ len ≤ 8   → max edit distance 1, first character must match
len ≥ 9       → max edit distance 2, normalized similarity ≥ 0.88
```

Three absolute vetoes, applied **before any threshold** and overridden by no score: **digit** (strings differing in any digit never match), **canonical** (a query that is itself an exact `pref_label` never fuzzy-matches elsewhere), **negation/affix** (`un-`/`non-`/`de-`/`anti-`/`-less`).

### 9.3 `ResolveSurface` side effects — 🚧 **Partial**

Called by the mention collector and the REST resolve handler:

1. **Unconditionally** insert a mention row — `artifact_ref`, `context_text` only; `chunk_ref`/`ks_id` null; **no column for the observed string** (K4). Errors discarded.
2. `Kernel.Resolve` — read-only.
3. **Unconditionally** append to `kb.semid_decision_log` — captures the string but no artifact reference, and **shares no key with the mention row from the same call**, so "what" and "where" cannot be joined. Errors discarded.
4. On `auto_accepted`: write the surface row if this exact literal isn't present. Derived keys not written (K1). The `human_review` arm is unreachable.
5. On `deferred`/`ambiguous`: upsert the backlog — ⚠️ **raw surface passed where the PK expects `norm_key`** (K5).

⚠️ **This conflates read and write.** No caller can ask "what does this resolve to" without writing four rows. **Decision:** split into a pure `ResolveSurface` and an `ObserveSurface`, applying the read/write rule at *every* layer, not only at the facade.

**Two changes D11 requires:** step 5 gains an **auto-create branch for targeted names** (collector misses keep today's backlog-only behaviour); step 4 must return the **top-1 id on `ambiguous`**, not only on `auto_accepted`.

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

⚠️ **The uniqueness key omits `lang`** (§7 item 5), so one concept cannot hold a `pref` surface per language. Fix in schema — the planned data reset makes this free.
⚠️ **`provenance` is a single string and `evidence` a single text field** — they cannot represent two sources independently asserting the same alias, so one source's support cannot be retracted without destroying the other's. §13.3 requires a separate evidence table; design it in when this schema is next touched.

### 10.3 `kb.keyword_surface_keys`

`(surface_id, key_kind)` PK · `key_value` · `norm_version`. ⚠️ **Empty in every shipped path** (K1).

### 10.4 `kb.keyword_mentions` — the occurrence record

`mention_id` · `artifact_ref` · `chunk_ref` · `context_text` · `ks_id` · `create_time`.

⚠️ **Cannot serve its purpose** (K4): no column names the observed string; `chunk_ref`/`ks_id` always null; `context_text` always empty (the only caller passes `""`). **Decision:** add `surface`/`norm_key` and the §9.5 occurrence fields, link to the decision-log row, and **rename to `kb.keyword_occurrences`** — verified cheap, nothing outside the package reads it.

### 10.5 `kb.keyword_unresolved` — the backlog

`(norm_key, scope)` PK · `surfaces` JSONB · `contexts` JSONB · `hits` · `status` · `attempts` · `last_attempt` · `priority` · timestamps.

⚠️ The caller passes the **raw surface** as `norm_key` (K5). 🚧 `contexts` is keep-last-5, not a reservoir sample. ⚠️ The 200-char cap slices **bytes**, splitting multi-byte CJK into invalid UTF-8.

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

## 13. Reconciliation and vocabulary growth — ⏳ **Deferred**

Reconciliation is what makes §2's REQ-1 true for **translations and genuinely different words**, which normalization can never do (§5.3). It is not optional polish.

```
R1 harvest    free extractors (Schwartz–Hearst parentheticals, definitional patterns)
R2 prune      junk, dedup, frequency floor; negative-cache by model@prompt_version
R3 block      lexical (pg_trgm) ∪ semantic (pgvector) to k candidates — biggest cost lever
R4 assemble   compact pipe-row batches; tag unreviewed LLM glosses to avoid self-confirmation
R5 decide     structured output, cheap model bulk; escalate ambiguous/high-blast-radius
R6 validate   deterministic gates — schema, referential, acronym plausibility, role
              consistency, never-merge, lock, scope, blast radius, confidence, digit veto
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

---

## 14. Merge, split, lifecycle — 🚧 **Partial**

`MergeConcept` tombstones; self-merge refused; target existence verified. See D7 for the missing guardrails and the consolidation decision. `locked` surfaces are built but the guarantee is vacuous with no reconciler. `never_merge` is storage-only — no keyword path consults it.

### 14.1 What a merge does to surfaces — ✅ **Decided** (was unspecified)

⚠️ **Verified gap:** `ConceptStore.MergeConcept` updates only `kb.keyword_concepts`; it **does not touch `kb.keyword_surfaces`**. No tier query joins to `kb.keyword_concepts`, filters on `status`, or follows `merged_into`. **So after merging A → B, every surface still carries `concept_id = A`, and every subsequent resolve returns the tombstone A, not the survivor B.** REQ-1 silently regresses to two ids the moment a merge happens — which makes §13's reconciliation, whose entire job is merging, actively harmful in its current form.

**Decision — both halves, because they solve different problems:**

1. **Merge re-points surfaces.** `MergeConcept(A, B)` updates `kb.keyword_surfaces SET concept_id = B WHERE concept_id = A`, in the same transaction as the tombstone. Resolution then costs no extra join and returns B directly.
2. **Each moved surface records `origin_concept = A`** (a new column). This is what makes a split reconstructible — without it, a merge is irreversible, and D11's reversibility requirement is unmet.
3. **Resolution still chases `merged_into` for incoming ids.** A consumer that stored `keyword_concept_id = A` before the merge must still resolve to B. The chase applies when a *caller supplies a concept id*, not on the surface lookup path — cycle-guarded, since D7 forbids transitive closure but chains can still form.

Re-pointing alone is not enough (stale consumer ids break); chasing alone is not enough (every surface lookup pays for it forever). Both, or REQ-1 does not hold across a merge.

### 14.2 What a merge does to an `aligns_to_term` assertion — ✅ **Decided**

If A has an accepted `aligns_to_term` and B does not, the alignment **follows to B** as part of the merge transaction. If A and B are aligned to **different** terms, that is a **conflict and the merge is refused** — two concepts aligned to two distinct governed terms are evidence they are not the same thing, and that evidence outranks whatever similarity proposed the merge. This is the §2.3 `brightness`/`luminance` case arriving from the other direction, and it is a deterministic R6 gate, not a judgement call.

### 14.3 Which merges may be automatic — ✅ **Decided** (the D10 / §13.1 boundary)

D10 says merging established concepts stays conservative; §13.1 item 4 says the same; Appendix A has reconciliation merge automatically. Both are correct, and the distinction that reconciles them is:

| Merge | Automatic? |
|---|---|
| An **auto-created provisional** concept (D11) into an established one — the Appendix A case | ✅ **yes**, above threshold, with §14.2's conflict gate. The provisional concept exists only because nothing matched; it has no curated content to lose. |
| Two **established** concepts (`status='active'`, human- or import-authored surfaces, or either side aligned to a term) | ❌ **no** — proposal only, per D10. Structural, and it invalidates assignments already made on both sides. |

The test is the concept's own provenance and status, not the similarity score. A high score never promotes a merge from the second row to the first.

### 14.4 Reversibility — ⏳ **Unbuilt, and required by D11**

D11 calls reversibility non-optional, but there is no designed path today: `split_concept` does not exist, `ConceptStore` has no unmerge (only `MergeGraph.Unmerge`, which is in-memory and scheduled for deletion, D7), and §12 exposes no retraction endpoint.

**Decision:** with §14.1's `origin_concept` recorded, un-merge is mechanical — move surfaces whose `origin_concept = A` back to A, clear A's tombstone. Build it **with** the merge guardrails (§19 step 6), not later: auto-merge (§14.3) must not ship before the thing that undoes it. Until then, reversal is manual database correction, and §13's reconciliation must not be enabled.

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

⚠️ **Blocked by a schema constraint:** `kb.semantic_assertions.subject_ref_kind` allows only `('object_node','ontology_term','assertion','artifact','literal')` — **no `keyword_concept`** — so a keyword concept cannot be an assertion subject until that CHECK is extended.

⚠️ **The `aligns_to_term` predicate must itself be a released governed term.** Every assertion carries a `predicate_term_id`, and `associate_semantics` already defers any candidate whose predicate is not released (`termExists`). Verified: **`aligns_to_term` is not in `server/cmd/ontology-seed/` today.** It must be seeded into a 4a module — `core` is the natural home, since the relation is not measurement-specific — and released, before the first alignment assertion can be written. This is a small prerequisite, but it is a hard one: without it every alignment defers.

**Governed-catalog bootstrap for the pilot.** REQ-2 also presumes released `metric_definition` terms exist to align *to*. §16.1's human path (hundreds of terms, reviewed once) and §13.2's standards-glossary import (IEC 60601 / ISO 80601) are both plausible, and the pilot's concrete path is **not yet chosen**. This is a sibling workstream, not keyword-module work — but it gates §2's acceptance test just as firmly as anything in §19, and someone must own it.

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

⚠️ **The exact call site is not yet fixed, and choosing it is part of step 12.** The seam is named but not located: metric rows are written by `MetricsSQLStore.SaveMetrics`/`UpsertMetrics` (`doc-processing/extract-metrics.go`), which is reached from `FinalizeChunkBatch` and from the enrichment path. Whether the resolver call belongs immediately before those writes, or in a small adapter that wraps them, is an implementation decision — but it must be **one** place, not one per write path, or the two paths will diverge exactly the way the two normalizers did (D3).

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

### 18.1 Test coverage today — 🚧 thinner than the counts suggest

51 tests pass; build/vet/gofmt clean. Weaker than it appears:

| File | Funcs | What it verifies |
|---|---|---|
| `normalizer_test.go` | 14 | individual steps. **No test asserts an acronym survives singularization** — why N1 shipped. |
| `concepts_store_test.go` / `surfaces_store_test.go` | 17 | sqlmock CRUD — SQL shape, not semantics |
| `keywordfamily_test.go` | 9 | constants and `off`/nil-DB early returns. **No test drives a tier against a database.** |
| `keyword_exit_test.go` | 11 | ⚠️ **assertion-free** — nine bodies are comments; `TestExitCoverageComplete` asserts `len(hardcoded 9-entry map) == 9`. Cannot fail. |

Exit criteria E4, E6, E7, E8 are unmet and the structure disguises it.

### 18.2 The required test set

**Correctness (before trusting the module):** per-tier query and score coverage; a normalizer table containing `AIDS`/`SaaS`/`Kubernetes`/`AWS's`; a scope round-trip (write at `ks`, read at `ks`); an **unset** `KEYWORD_RESOLVER_MODE` writing nothing.

**§2 acceptance (the DR23 requirement) — two phases, not a fixture that begins with the answer:**

*Bootstrap/growth:* start with empty tables → import a versioned fixture connecting `Luminance` and `亮度` through one external id → ingest an observed `显示亮度` with language, context, and unit evidence → run reconciliation with real validation gates → assert **one concept, three evidence-bearing surfaces** → activate atomically and prove re-import is idempotent → add a conflicting `亮度` concept and prove ambiguity is preserved rather than over-merged.

*Online:* resolve all three clean names plus dirty variants (`␠␠LUMINANCE␠␠`, `Ｌｕｍｉｎａｎｃｅ`, `显示​亮度`) → assert **the same `ConceptID`** for all while each raw string is preserved → assert **zero LLM/network calls** on every `ResolveName` → assert language-driven label selection → assert scope, term kind, and language participate in ranking → assert `ResolveName` writes nothing and `ResolveAndObserve` writes exactly one linked occurrence + decision → assert `disabled` writes nothing.

*End-to-end (§2.2):* 140 documents with mixed phrasings produce **exactly one comparison-matrix row**; a 141st document with a fifth phrasing does not create a second.

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
11. **§2 REQ-1** — tiers 5–6 and the minimum reconciliation loop that unifies translations.
12. **§2 REQ-2/REQ-3** — seed and release the `aligns_to_term` predicate term (§16.1), extend `subject_ref_kind`, build the alignment producer, add the metric columns, and place the consumer call (§16.3).
13. **§2 REQ-4 — resolve the `metric_key` gap (§2.4).** Not keyword-module work, and **not optional**: until `metric_key` is either confirmed to be the governed term id or given a specified mapping, steps 1–12 cannot produce "one row." Settle this with whoever owns P4 **before** step 12, since the answer may change what REQ-3 persists.

Steps 1–9 are contained inside `ontology/keywords` and `ontology/semid`. Steps 10–12 make this module's half of §2 true. **Step 13 is outside this module and is currently the binding constraint on the whole requirement** — worth raising now rather than discovering it after step 12.

**Two prerequisites owned elsewhere**, both gating §2 and neither scheduled here: the `aligns_to_term` predicate term must be seeded and released (§16.1), and released `metric_definition` terms must exist to align to — via the human catalog path or a standards-glossary import (§13.2). Someone must own both.

---

## 20. Status

### 20.1 Deferred

Tiers 5–6 · R1–R7 · `aligns_to_term` · `on`-mode wiring · collector pipeline wiring · context-token disambiguation · Double Metaphone · resource import · multi-word and CJK-segmented collection · backlog admin surfaces · rewrite-rule auto-promotion · `merged_into` chase at resolve time · **I2 live PostgreSQL proof**.

### 20.2 Defects

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

Lower-severity, inline: byte-sliced context truncation and keep-last-5 (§10.5); `norm_version` unfiltered (N4); `surface_id` hashed before role defaulting; unreachable `human_review` arm (§9.3); dead `phonetic` key; `lang`-less uniqueness (§10.2); assertion-free exit tests (§18.1).

**Fix order:** K6 → K2/K5 → N1 → K1/N3/K3 → K8/K9/K10 → K4.

### 20.3 Operational consequence

Explicitly `off` → inert. **Unset** → inert for the collector, *not* for the REST endpoint (K6). In `observe` → rows written but mis-keyed (K5), inconsistently scoped (K2), context-free. **Treat all observe-mode data as disposable**, consistent with the planned data reset.

### 20.4 Dead-code register

11 of 12 audited exported functions have zero production callers — a consequence of building bottom-up, one table per chunk, with no consumer. Classified, not deleted wholesale:

| Item | Classification | Decision |
|---|---|---|
| `SurfaceKeyStore.UpsertSurfaceKeys` | **Not dead — unfinished feature**; tiers 2/4 already query it | **Wire** (K1) |
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

These now carry real assertions: §18.1 exit tests rewritten, per-tier query and scope round-trip coverage added (§18.2), D11 and §9.5 facade covered with sqlmock. Steps 11–13 (REQ-1 tiers 5–6, REQ-2/3 `aligns_to_term`, REQ-4 `metric_key`) are not started: tiers 5–6 await the §22 fuzzy/embedding decisions, `aligns_to_term` awaits §16.1 term-catalog seeding, and `metric_key` awaits metric-side (P4) coordination. Pre-existing environment-dependent failures in kbhandler (search-registry/topic-category) and doc-processing remain; the keyword/semid/names packages are green.

---

## 22. Open questions

1. **Auto-accept thresholds per tier** (§13.1). Not derivable from first principles — measure against the gold set, ship conservative, tune.
2. **Whether tier 6 belongs online at all.** Tier 6 must embed *the query* at resolve time. A **local** model is CPU work, consistent with §3's non-goal. A **hosted API** puts a network call on every miss — breaking the non-goal, the latency budget, and independence from a third party. Either host a small multilingual model locally, or **restrict tier 6 to reconciliation** (offline, batched) and let the online path stop at tier 5. **Recommendation: reconciliation-only unless a local model is already in the stack** — D11's auto-creation means a first-seen foreign-language name gets an identity immediately regardless, so deferring the merge costs little.
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

⚠️ **Most of Stage 5 does not work today.** Tier 6 is unbuilt and reconciliation is unbuilt. The §14.1 merge machinery itself is now in place — `MergeConcept` re-points surfaces with `origin_concept`, `UnmergeConcept` reverses it, and resolution chases the survivor — but nothing proposes merges automatically yet. This stage describes the design in §13–§14.

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
