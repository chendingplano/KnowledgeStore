# Keyword Canonicalization and Reconciliation — Specification

- **DocID:** `doc-2026080403`
- **Status:** Adopted (supersedes `doc-2026080101`, `doc-2026072703`, `doc-2026072301` as the reference to read)
- **Date:** 2026-08-04
- **Component:** SemOS / ChenWeb — keyword lexicon, the DR15/DR16 keyword identity family
- **Type:** Specification (self-contained: background, decisions, architecture, data model, implementation status)
- **Supersedes:** `2026080101-spec-keyword-canonicalization-merged.md`, `2026072703-spec-keyword-canonicalization-reconciliation-2.md`, `2026072301-spec-keyword-canonicalization-reconciliation.md`
- **Design authority:** ADR `2026072901-adr-ontology-platform-and-adaptive-pipeline.md`, DR15 (shared canonicalization kernel) and DR16 (merged keyword design)
- **Implementation record:** P3 Track B handoff `2026080401-handoff-semos-p3-trackb-keyword-lexicon.md`, implementation log `2026080402-devdoc-semos-p3-trackb-implementation-log.md`
- **Addendum:** `2026080404-spec-metric-name-canonicalization-addendum.md` — how a consumer (metric extraction) is meant to use this module; the association-layer integration decision; the proposed `keyword_concept_id` / `metric_definition_term_id` design. Design only, not yet built.
- **Implementation status:** observe mode built 2026-08-04 (P3 Track B, chunks 0–H, 7 commits on `main`) **with verified defects**. "Observe mode" is working mode with its output disconnected — defined in §3 D9, specified in §7.4. Read §17.2 before trusting any ✅ badge: several shipped components do not behave as this design specifies.

---

## 0. How to read this document

This is the **single self-contained reference** for the keyword canonicalization module. Unlike the three documents it supersedes, it does not assume you have read anything else. It covers:

- **why** the module exists and what problem it solves (§1–§2),
- **which design decisions were made and why** (§3),
- **how the system works** — identity model, normalization, the shared resolution kernel, working mode, reconciliation mode (§4–§11),
- **exactly what is implemented today**, what is deferred, and where the code diverges from this design (§17), so you can tell design from reality at a glance.

Every section that has been implemented marks its status with a badge:

| Badge | Meaning |
|---|---|
| ✅ **Built** | code exists and does what this document says (see §16.4 for what "tested" actually covers) |
| 🚧 **Partial** | built with a known limitation, stated inline |
| ⚠️ **Defect** | built, but verified *not* to behave as specified — listed in §17.2 |
| ⏳ **Deferred** | designed, deliberately not built yet |

**A badge describes whether code exists, never whether it is correct.** Track B was built fast and its behaviour was never exercised against a live PostgreSQL instance (§17.1, I2). A code read on 2026-08-04 found eleven defects where the shipped behaviour contradicts this design; they are enumerated in §17.2 and cross-referenced from the sections they affect. Design statements in §1–§15 remain the intended contract — where the code disagrees, the code is wrong, not the design.

The prior specs are retained on disk as historical inputs to the design lineage but are no longer authoritative; where they disagree, this document and the ADR govern.

---

## 1. Background and problem

### 1.1 Keywords are fragile retrieval keys

Users and documents refer to the same thing in many surface forms:

```
Postgres, PostgreSQL, postgresql
HVAC, heating ventilation and air conditioning
GB, Guobiao, national standard
odor control, odour control, deodorization
ML, machine learning, millilitre          (homonym)
K8S, Kubernetes, Kube, kubernets           (noise + case + misspelling)
U.S.A., USA, usa
```

If each surface form is stored and matched as an independent key, search, faceting, clustering, analytics, and downstream reconciliation all degrade: recall fragments because one spelling does not match another, and analytics count one real concept as several. The cost compounds in a corpus like SemOS's, which mixes English and Chinese, where the same concept appears as an acronym, a full phrase, a translation, and a misspelling.

### 1.2 The design problem

The system therefore needs:

1. a **stable canonical concept** per keyword family (`PostgreSQL`, not `postgres`);
2. a **growing database of known variants** (aliases, acronyms, translations, misspellings) attached to that concept;
3. a **deterministic, model-free resolution path** for online use — lookups must be O(1) and cheap, because query volume is high;
4. an **asynchronous, auditable, LLM-assisted path** for the cases that determinism cannot resolve — the long tail of new and ambiguous terms;
5. **ambiguity preserved as a real result** instead of a forced guess.

This is a specialized form of **entity resolution / record linkage**: online resolution should be cheap and predictable; offline reconciliation handles the hard long-tail cases and grows the database.

### 1.3 House precedent

The KnowledgeStore already reconciles objects and entities with an exact/alias/acronym-first, broader-reconciliation-second pattern. The keyword module is deliberately symmetric to that: exact and normalized matching first, batch reconciliation second, with every automated decision logged and reversible.

### 1.4 The economic thesis

**LLM cost should scale with vocabulary growth, not with query volume.** Every alias learned once is free forever after. A mature deployment should approach zero LLM calls per day even at millions of lookups. Everything in the reconciliation design (§11) exists to make the model's job as small and safe as possible.

---

## 2. Goals and non-goals

### 2.1 Goals

1. Resolve an input surface to a canonical keyword concept in **working mode** without any LLM call.
2. Return all known variants for a resolved concept, tagged by role.
3. Preserve **ambiguity** as a first-class result instead of forcing false merges.
4. Continuously improve the database through **reconciliation mode**.
5. Support aliases, acronyms, abbreviations, alternate spellings, language variants, and noisy formatting variants.
6. Make every merge or alias attachment **auditable and reversible**.
7. Keep the module reusable across search, extraction, enrichment, faceting, and analytics.

### 2.2 Non-goals

1. This module resolves **keyword concepts**, not full real-world business entities.
2. The **online path never calls an LLM** and does not depend on embeddings. (Fuzzy/ANN tiers, if built, are *suggest-only* and never auto-accept.)
3. LLMs are not required to create every canonical concept — free harvesters (which ship with reconciliation, §11) and manual authoring cover a large share.
4. This is not a taxonomy engine. Hierarchy (`broader`/`narrower`) is out of scope for v1, though the schema leaves room.
5. This is not a spell-checker. Misspellings are absorbed as `hidden` aliases, not corrected generatively.

---

## 3. Load-bearing design decisions

The decisions below are the reason the module looks the way it does. They were settled in the ADR (DR15, DR16) by merging two earlier, partially conflicting specs — one proposing a Postgres-centric concept/variant/link model, the other a UMLS/SKOS-inspired four-layer model with SQLite-first storage. What follows is the resolution.

### D1. Four identity layers, UMLS-style — ✅ **Built** (in the schema)

Every keyword passes through four layers of abstraction:

```
occurrence   →   surface   →   lexform   →   concept
```

- **occurrence** — a raw string as observed in a document chunk, plus where it came from (≈ UMLS AUI);
- **surface** — one exact distinct string, stored verbatim (≈ SUI);
- **lexform** — a normalization-equivalence class; the working-mode index key (≈ LUI);
- **concept** — a unit of meaning with a canonical label and gloss (≈ CUI).

`surface → lexform` is many-to-one and **computed** (by the normalizer). `lexform → concept` is **many-to-many** — this is where homonyms live (`ML` → machine learning *or* millilitre) — disambiguated by scope, and failing that by context. The `lexform` layer is the one that earns its keep: it is what makes deterministic O(1) lookup possible, and it is the layer invalidated by a normalizer-version bump.

### D2. One shared resolution kernel, not a bespoke engine — ✅ **Built**

DR15 built a single canonicalization kernel — `normalize → candidates → score → adjudicate → link → merge/split → audit` — in `ChenWeb/server/api/ontology/semid/`, instantiated **per identity family**. A family declares only what differs via a `FamilyAdapter`; it never edits the mechanism. The keyword family is the **second instantiation** of this kernel (after P2's ontology-term family, `TermFamily`). This rejects both prior specs' assumption that the keyword module owns its own resolver engine. The keyword family supplies: a surface store, a node store, a normalizer profile, scoring via key bundles, scope, and an auto-accept policy — not a second copy of the mechanism.

### D3. Postgres storage (`kb.keyword_*`) — ✅ **Built**

Storage is Postgres, in the `kb.` schema, per the ChenWeb convention. SemOS already runs `pg_trgm` and `pgvector` and needs one backup/migration story, not two storage engines. This resolves the earlier specs' SQLite-vs-Postgres disagreement in Postgres's favor.

### D4. SKOS label roles — ✅ **Built**

Every surface carries a role: `pref` (the canonical display label), `alt` (synonyms, acronyms — user-visible), or `hidden` (misspellings — indexed and searchable but never displayed). This three-way split costs nothing to adopt and exactly matches the problem.

### D5. Ambiguity is first-class — ✅ **Built** (kernel verdict)

When a key maps to multiple concepts and scope does not disambiguate, the result is **`ambiguous` with ranked candidates** — never a forced pick, and never a silent coin flip. Silently picking the most frequent candidate produces an error invisible to both caller and metrics.

### D6. Store surfaces; derive keys; version the normalizer — ⚠️ **Defect** (rule not enforced)

Every normalization key is recomputable from `surface + norm_version`. A normalizer change is therefore a **re-index job, never data loss**. Bumping `norm_version` invalidates the derived-key layer; the original surfaces are always preserved.

The schema honours this; the shipped write paths do not. `POST /kb/keyword-surfaces` accepts a caller-supplied `norm_key` verbatim and never derives or validates it, and no write path populates `kb.keyword_surface_keys` at all. Keys are therefore *asserted*, not derived — see D6 defects in §17.2.

### D7. Merges are tombstones; no transitive closure; `never_merge`; `locked` — 🚧 **Partial** (tombstones built, guardrails unenforced)

- Merges set `merged_into` and move the concept to `merged`; the row is **never deleted**, so stale ids still resolve. ✅ Built.
- Merges are **not transitive**: `A→B` and `B→C` do not imply `A→C`. Connected-component clustering is explicitly rejected (one bad edge chains two unrelated clusters together). ✅ Built by omission — nothing computes a closure.
- **`never_merge`** assertions (`kb.semid_never_merge`, shared kernel table) block specific pairs forever. ⚠️ **Storage only.** The table and `NeverMergeStore` exist from P2, but no keyword code path reads them: `ConceptStore.MergeConcept` performs no never-merge check (§12.2).
- **`locked`** surfaces are human-asserted; the reconciler may propose changes to them but never apply them. ✅ The flag and its toggle are built; ⏳ the reconciler that must honour it does not exist yet, so the guarantee is currently vacuous.

### D8. Token-economics discipline — ⏳ **Deferred** (reconciliation not built)

Reconciliation runs the seven-stage ladder `harvest → prune → block → batch → decide → validate → apply`, with every stage before the model existing to shrink the model's job, and every stage after it existing to stop the model from corrupting the database. Only the data structures that support it are built today (§11).

### D9. Two modes of operation, on two independent axes — ✅ **Built** (working), ⏳ **Deferred** (reconciliation)

The word "mode" is used for two different things in this design, and they are **not** three peers. Reading them as one list is the single most common misunderstanding of this module, so both axes are defined here, before either term is used again.

**Axis 1 — what kind of work runs.** These are the two operating modes proper:

| Mode | Trigger | LLM? | Latency | Job |
|---|---|---|---|---|
| **Working mode** | every resolve call | never | µs–ms | answer from the database; record what it can't answer |
| **Reconciliation mode** | scheduled / on-demand batch | yes | minutes | drain the unresolved backlog, grow the database |

**Axis 2 — how far working mode's answers are allowed to travel.** This is a deployment gate, `KEYWORD_RESOLVER_MODE`, and it has three settings:

| Setting | Working mode runs? | Side effects recorded? | Results reach retrieval/search? |
|---|---|---|---|
| `off` (default) | no | no | — |
| **`observe`** | yes | **yes** | **no** |
| `on` | yes | yes | yes |

**`off` — the module does nothing.** `CandidateNodes` returns no candidates and `ResolveSurface` no-ops before touching the database. No mention is written, no surface is derived, nothing is logged. This is the safe, do-nothing state a keyword-unaware deployment sits in, and it is meant to be the default whenever the variable is unset (§7.4 records a defect where one code path fails to honour this).

**`observe` — the module runs for real but is not trusted yet.** Resolution executes exactly as it would in `on`: the normalizer runs, the kernel scores candidates, tiers 0–4 are tried, and every side effect is written — a mention row, a decision-log entry, and either a new surface (on a match) or a backlog entry (on a miss). The *only* thing withheld is the answer itself: nothing downstream — search, retrieval, faceting — ever sees the resolution. This is the evaluation setting: it exists so the pipeline can be exercised against real document volume and its numbers inspected (mention counts, hit rate, ambiguity rate, backlog growth — §16) before a wrong resolution is allowed to reach a live path. It is what P3 Track B shipped, and it is why this document's implementation status reads "observe mode built". **`observe` is therefore a state of working mode, not a third mode** — same computation as `on`, with the last step removed.

**`on` — the module is live.** Same pipeline as `observe`, with the downstream gate removed: an `auto_accepted` resolution becomes available to retrieval and search, and an accepted result can produce an `aligns_to_term` assertion (§14). Graduating from `observe` to `on` is designed to be a config flip, not a code change — the pipeline underneath is identical, only the last step differs. **This mode is not yet meaningfully usable**: no retrieval or search consumer exists to receive a resolution (§17.1), and §7.4 records a defect where flipping to `on` actually turns mention collection *off* rather than adding the retrieval connection.

Reconciliation mode is orthogonal to all three settings: it is a batch job over the backlog, and it is unbuilt regardless of how the gate is set.

Throughout this document, **"observe mode"** is shorthand for "working mode running under `KEYWORD_RESOLVER_MODE=observe`". §7.4 gives the concrete behaviour of each setting and records two defects in the gate itself.

### D10. Bias toward under-merging — ✅ **Adopted as policy**

A missed alias is a self-reporting, self-healing condition — it lands in the unresolved backlog and gets fixed on the next reconciliation run. A wrong merge is invisible, permanent until someone notices, and contaminates every consumer. Every conservative threshold in the design follows from this asymmetry: **prefer under-merging everywhere**.

---

## 4. Identity model

### 4.1 The four layers

```
occurrence   raw surface as observed, + where it came from   (where it came from → kb.keyword_mentions)
   ↓
surface      one exact distinct string, stored verbatim       (kb.keyword_surfaces)
   ↓
lexform      normalization-equivalence class                  (norm_key — the working-mode index)
   ↓
concept      unit of meaning: canonical label + gloss         (kb.keyword_concepts)
```

Note on the occurrence layer: `kb.keyword_mentions` is meant to record *where* an occurrence was seen (artifact, chunk, context, knowledge store). It does **not** store the raw surface string, so as built it cannot say *what* was seen — a gap that makes the table unusable for reconciliation until the schema changes (§8.4). The surface text travels on the resolve call and, when a resolve misses, accumulates in `kb.keyword_unresolved.surfaces`; that backlog is currently the only place occurrence evidence actually lands.

### 4.2 Cardinal rules (binding)

1. **`concept_id` is opaque and immutable** — never a slug of the label. The canonical label is a mutable *display attribute*; the id is the identity. Downstream consumers key on the id, so renaming `Kubernetes` → `Kubernetes (container orchestration)` must break nothing.
2. **Store surfaces; derive keys.** Every normalization key is recomputable from `surface` + `norm_version`; a normalizer change is a pure re-index, never data loss.
3. **Merges are tombstones, never deletes.** A merged concept keeps its row with `merged_into` set.
4. **Everything carries provenance and confidence.** `human:<user> | rule:<id> | llm:<model>@<prompt_version> | import:<src>`. This is what makes it possible to revoke a bad source's entire output in one query.
5. **Human assertions are locked.** The reconciler may propose changes to them but may never apply them.

### 4.3 Homonymy

`lexform → concept` is many-to-many on purpose. `ML` maps to both `machine learning` and `millilitre`. The schema does **not** make `norm_key` globally unique — the same key may map to different concepts in different scopes — so homonyms are representable without a hack. Scope is intended to be the knowledge-store id (`ks_id`) or the global `'_'`, chosen by the caller; when scope does not disambiguate, the deferred context-token disambiguation (§17.1) is the fallback.

⚠️ In the shipped resolver, scope disambiguation does not happen: every lookup is hard-coded to `'_'` regardless of what the caller passes (§6.1, defect K2). Two concepts sharing a `norm_key` in the global scope therefore tie at the top score and — with `MaxCandidates: 1` — return `ambiguous`, which is the safe outcome but not the designed one. Homonymy is representable in the schema and unresolvable in the code.

---

## 5. Normalization — ⚠️ **Defect** (built; over-normalizes)

The normalizer is the most dangerous component in the system: it is fast, invisible, and every over-aggressive rule silently collapses distinct concepts forever. The design is deliberately conservative. **The shipped implementation is not** — see §5.5.

### 5.1 The pipeline (implemented, in order)

| # | Step | Example (verified against the code) | Notes |
|---|---|---|---|
| 1 | Unicode NFKC | `ﬁle` → `file` | `golang.org/x/text/unicode/norm` |
| 2 | Strip zero-width chars / BOM / LTR/RTL marks | | ZWSP, ZWNJ, ZWJ, BOM, LRM, RLM. Soft hyphen (U+00AD) is **not** stripped |
| 3 | Normalize dashes to ASCII `-` | `e–mail` → `e-mail` | em/en/figure/horizontal bar |
| 4 | Normalize quotes to ASCII | `“x”` → `"x"` | curly single/double |
| 5 | Collapse and trim whitespace | | runs → one space |
| 6 | Collapse dotted initialisms (before case-fold) | `U.S.A.` → `usa` | only `A.B.C` uppercase letter-dot patterns |
| 7 | Case-fold (full Unicode lowercase) | | CJK unaffected (no case) |
| 8 | Drop possessive `'s` | `AWS's cloud` → `aws cloud`; **`AWS's` → `aws'`** | matches the literal `'s ` — a *word-final* possessive is missed (§5.5 N2) |
| 9 | Strip leading articles | `the cloud` → `cloud` | English `the`/`an`/`a` |
| 10 | Exception-list-aware singularization | `indices` → `index`; **`AIDS` → `aid`**, **`SaaS` → `saa`** | intended as "never a Porter/Snowball stemmer"; as shipped it reproduces stemmer failures (§5.5 N1) |

Singularization uses an explicit irregular-plural exception list (21 entries) plus suffix rules (`ies`→`y`, `ves`→`f`, `es`→`e` for `ses/zes/ches/shes/xes`, plain `s`→`∅` except `ss`, only for words longer than 3 characters). It is applied per-word; CJK tokens have no matching suffix and pass through untouched.

### 5.2 The key bundle — 🚧 **Partial** (computed in memory; never persisted)

Each surface produces **six deterministic keys**. The design calls for them to be materialized at write time; the shipped code computes them per resolve call and writes none of them (§17.2 K1).

| Key | Definition | Intended purpose | As shipped |
|---|---|---|---|
| `exact` | verbatim surface (trimmed) | tier 0 | tier 0 matches the `surface` column directly; the `exact` key itself is unused |
| `norm` | output of the §5.1 pipeline | **primary index** — tier 1 | ✅ used |
| `alnum` | `norm` keeping only a-z, 0-9, and runes ≥ U+2E80 (CJK) | tolerates punctuation — tier 2 | 🚧 queried, never written |
| `sorted` | tokens of `norm` sorted | word-order variants — tier 2 | 🚧 queried, never written |
| `phonetic` | **stub**: first char, then the first 4 consonants of the whole string | reserved | ⚠️ **queried by no tier at all** — dead |
| `initials` | first rune of each token, **uppercased** | acronym↔expansion bridge — tier 4 | ⚠️ cannot bridge as designed (§5.5 N3) |

The design intent for `initials` is that `machine learning` and the acronym `ML` collide deterministically without fuzzy matching or a model. **As implemented this cannot happen** — see §5.5 N3. The phonetic key is a deterministic stub whose leading consonant is also counted among the four (`ml` → `mml`); a full Double Metaphone is a P3 follow-up, but no tier reads the key, so replacing it changes nothing today.

Where the keys live: `exact` and `norm` are **columns on the surface row** (`surface`, `norm_key`), while the four alternate keys are **rows in `kb.keyword_surface_keys`** — which is why that table's `key_kind` CHECK admits only `alnum`, `sorted`, `phonetic`, `initials`. No shipped code path writes that table (neither the resolver nor the REST surface handler), so tiers 2 and 4 have nothing to match against.

The bundle maps onto the kernel's `KeyBundle` as `CanonicalKey = norm`, `AlternateKeys = [alnum, sorted, phonetic, initials]` (empty keys and a `sorted` that duplicates `alnum` are dropped). This mapping is what makes the kernel's generic `Score()` produce the correct tier scores with no family-specific scoring code.

### 5.3 Versioning — ✅ **Schema built**, re-index flow ⏳ **Deferred**

Every derived key stores `norm_version`. Bumping it is a full re-index — recompute all keys from stored surfaces — never a migration and never data loss. The re-index *flow* (a re-index job + snapshot promotion) is not built; the schema supports it.

### 5.4 CJK handling — ✅ **Built** (normalizer), 🚧 **Partial** (tokenizer)

CJK characters pass through the pipeline with no case folding, are retained by the `alnum` key (threshold `0x2E80`), and are handled rune-wise in `initials`. This matters because the SemOS pilot corpus (呼吸机/医疗器械) is predominantly Chinese. The *mention collector's* tokenizer is a separate matter and does not segment CJK — see §9.

### 5.5 Verified normalizer defects — ⚠️

All four were reproduced by running `KeywordNormalizer.Normalize` on 2026-08-04. They are written out here, rather than only listed in §17.2, because they change what the normalizer *means* — every `norm_key` already stored is affected.

**N1 — singularization runs after case-folding, so the ALLCAPS guard both source specs demanded is absent.** The design says "never a Porter/Snowball stemmer" precisely to avoid `AIDS → aid`, `SaaS → saa`, `business → busi`. Because step 7 (case-fold) precedes step 10, the plain `s`→`∅` rule cannot tell an acronym from a plural. Observed:

```
AIDS        → aid          SaaS        → saa
Kubernetes  → kubernete    Postgres    → postgre
analysis    → analysi      status      → statu
```

`Kubernetes` and `kubernets` (the misspelling) both normalize to `kubernet`, which by luck is the behaviour the design wants — but by the wrong mechanism, and `PostgreSQL`/`Postgres` do not collide. The `len > 3` floor is the only protection, and it protects only `gas`, `bus`, and other 3-letter words. **Fix:** carry the casing signal that §5.1 step 7 was supposed to record, and refuse to singularize a token whose original form was ALLCAPS or that appears in the exception list's reverse direction. The existing test (`TestSingularization`) exercises only the irregular-plural exception list and therefore passes while the general rule is broken.

**N2 — the possessive rule requires a trailing space.** It is `strings.ReplaceAll(s, "'s ", " ")`, so `AWS's` at end-of-string is not stripped; singularization then turns it into `aws'`. Any single-token possessive surface — the common case for an extracted keyword — is mis-keyed.

**N3 — the `initials` bridge cannot bridge.** Two independent reasons: (a) the key is uppercased while every other key is lower-cased, so `initials` values can never equal a `norm`/`alnum` value; (b) tier 4 looks up `keyBundle.Initials` *of the query*, and a single-token query has one initial — `ML` yields `M`, not `ML`. Populating `kb.keyword_surface_keys` (§17.2 K1) is therefore necessary but not sufficient: tier 4 would then match every single-token surface beginning with `m`, which is worse than matching nothing. **Fix:** tier 4 must look up the query's *normalized form* (`ml`) against stored `initials` values that are also lower-cased, and must be scope- and length-gated.

**N4 — `norm_version` is carried but never consulted.** The tier-1 lookup filters on `(norm_key, scope)` only; `kb.keyword_surface_keys` has a `(key_kind, key_value, norm_version)` index but the query does not filter on `norm_version`. Two normalizer versions in the same table would serve reads simultaneously — the condition the source design explicitly forbids. Harmless while only version 1 exists; it must be fixed before the first version bump.

---

## 6. The shared kernel (`semid`) — ✅ **Built**

### 6.1 The `FamilyAdapter` contract

DR15's kernel owns the mechanism; a family declares only what differs:

```go
type FamilyAdapter interface {
    FamilyName() string
    Normalizer() Normalizer
    AutoAcceptPolicy() AutoAcceptPolicy
    Scope(surface string) string
    CandidateNodes(ctx, surface, scope) ([]NodeCandidate, error)
}
```

The keyword family (`ChenWeb/server/api/ontology/keywords/keywordfamily.go`) implements this: `FamilyName() = "keyword"`, a normalizer whose `NormFunc` delegates to the §5 pipeline, `AutoAcceptPolicy{Enabled: true, MinScore: 0.8, MaxCandidates: 1}`, `Scope()` → the constant `"_"`, and a multi-tier `CandidateNodes`.

⚠️ **Scope defect (§17.2 K2).** `Kernel.Resolve` derives the scope it passes to `CandidateNodes` from `Family.Scope(surface)` — which is hard-coded to `"_"` — and *ignores* the `scope` argument the caller gave `ResolveSurface`. Every tier lookup therefore filters `scope = '_'`, while the surfaces and backlog rows written by the same call are stamped with the caller's scope (a `ks_id`). A knowledge-store-scoped surface can be written and can then never be found again. Until this is fixed, the module is effectively single-scope, and §4.3's homonym-by-scope story does not hold in the running code.

### 6.2 The resolve flow

`Kernel.Resolve` is identical for every family:

```
normalize(surface) → key bundle
  → CandidateNodes(surface, scope)      // family-provided
  → Score(bundle, candidate) for each   // deterministic
  → sort by score, then Adjudicate      // policy-provided
```

`Score()` semantics (generic, `semid/score.go`):

| Condition | Score | Reason |
|---|---|---|
| surface canonical key == candidate canonical key | 1.0 | exact key match |
| candidate canonical key ∈ surface alternate keys | 0.8 | alternate key match |
| prefix of one another, both ≥ 3 chars | 0.5 | prefix match |
| otherwise | 0 | no match |

`Adjudicate()` maps scored matches to a verdict: no candidates → `deferred`; top score tied across more than `MaxCandidates` → `ambiguous`; policy disabled or top below `MinScore` → `human_review`; else → `auto_accepted`.

Note on the 0.5 prefix score: it is part of the generic kernel contract and is *intended* to be unreachable for keywords, because every candidate a keyword tier returns carries a key that should score 1.0 or 0.8. That holds only while stored `norm_key` values agree with the normalizer. Since `POST /kb/keyword-surfaces` accepts a caller-supplied `norm_key` without deriving or validating it (§10, §17.2 K3), a tier-0 hit on a row with an inconsistent `norm_key` can score 0.5 — below `MinScore`, so it degrades to `human_review` rather than a wrong link. It is a latent path, not dead code.

Also note: matches scoring 0 are dropped before adjudication, so a tier that returns only non-scoring candidates is indistinguishable from a miss and yields `deferred`.

### 6.3 Verdicts — ✅ **Built**

| Verdict | Meaning |
|---|---|
| `auto_accepted` | deterministic match above the family's threshold |
| `ambiguous` | several candidates tied at the top |
| `deferred` | no candidates |
| `human_review` | below threshold / governed family (keyword family's policy auto-accepts tiers 0–4) |

### 6.4 Shared tables — ✅ **Built** (from P2)

Audit and guardrails are **not duplicated** per family. The keyword family uses the kernel's shared tables, scoped by `family = 'keyword'`:

- `kb.semid_decision_log` — append-only audit of every resolution (input, output, verdict, actor, model, tokens);
- `kb.semid_never_merge` — unordered never-merge pairs;
- `kb.semid_snapshots` — recorded family snapshots.

The keyword `ResolveSurface` appends every resolution to the shared decision log with `family = 'keyword'`.

---

## 7. Working mode — the resolution ladder

### 7.1 The tier ladder

Each tier is tried in order and returns candidates or falls through to the next. Tiers 0–4 are deterministic and O(1); tiers 5–6 are candidate-only and never auto-accept.

| Tier | Method | Score | Status |
|---|---|---|---|
| 0 | exact surface match | 1.0 | ✅ **Built** |
| 1 | `norm_key` match | 1.0 | ✅ **Built** |
| 2 | `alnum`/`sorted` key match | 0.8 | 🚧 **Partial** — query built, no data |
| 3 | enabled rewrite rules, then retry tiers 0–1 | 1.0/0.8 | ✅ **Built** |
| 4 | `initials` bridge within scope | 0.8 | ⚠️ **Defect** — see §5.5 N3 |
| 5 | fuzzy (trigram + edit distance, with guardrails) | candidate-only | ⏳ **Deferred** |
| 6 | embedding similarity (ANN) | candidate-only | ⏳ **Deferred** |
| 7 | miss → record to `kb.keyword_unresolved` | — | ✅ **Built** (via `deferred`) |

`CandidateNodes` exits at the **first tier that produces candidates** — it does not accumulate across tiers. This keeps lookups O(1) for the overwhelmingly common exact/norm hits.

**Why tiers 2 and 4 do not work.** The *query* path is built (the SQL that joins `kb.keyword_surface_keys`), but nothing ever writes that table: neither `ResolveSurface` nor `POST /kb/keyword-surfaces` calls `SurfaceKeyStore.UpsertSurfaceKeys`, and there is no REST route for it. Tier 2 is therefore a correct query starved of data — populating the table fixes it. Tier 4 is not: even fully populated it would match the wrong things, for the two reasons in §5.5 N3. **Tier 2 is a data gap; tier 4 is a logic defect.** Conflating the two was the main inaccuracy in the earlier draft of this spec.

Tier 3 likewise only fires if someone has authored rewrite rules through the API (none exist by default), and it matches the **raw, un-normalized** surface against `pattern` with Go string equality — so a rule `K8S → Kubernetes` does not fire for `k8s`. One rule fires at most (first match wins, then `break`), and the retry covers tiers 0–1 only, not 0–2 as the migration comment claims.

### 7.2 The `KeywordFamily` adapter — ✅ **Built**

`KeywordFamily` wires six stores (concept, surface, surface_keys, mention, unresolved, rewrite rule) plus a normalizer and resolver mode. `CandidateNodes` implements the tier ladder directly against Postgres (`kb.keyword_surfaces`, `kb.keyword_surface_keys`), returning `NodeCandidate`s whose key bundles are set so the generic `Score()` yields the tier's score.

### 7.3 ResolveSurface side effects (observe mode) — 🚧 **Partial**

`ResolveSurface(surface, scope, artifactRef, contextText)` runs the kernel and records the outcome:

1. writes a mention row to `kb.keyword_mentions` (append-only) — ⚠️ **only `artifact_ref` and `context_text` are passed; `chunk_ref` and `ks_id` are left NULL** (§17.2 K4), and no column identifies *which* surface the mention was for (§4.1);
2. runs `Kernel.Resolve` → verdict + scored matches (with the scope caveat in §6.1);
3. appends the decision to `kb.semid_decision_log` with `family='keyword'`, `actor='keyword_family'`, and the caller's scope;
4. if `auto_accepted`: best-effort write of the surface row to `kb.keyword_surfaces` (`label_role='alt'`, `alias_type='synonym'`, `provenance='llm:observe'`, `confidence=0.8`) if a matching row is not already present. Derived keys are **not** written (§7.1). The code also lists `human_review` in this branch, but `Kernel.Resolve` only sets `ResolvedNodeID` on `auto_accepted`, so that arm is unreachable;
5. if `deferred`/`ambiguous`: upsert into `kb.keyword_unresolved` — ⚠️ **the raw surface is passed where the primary key expects `norm_key`** (§17.2 K5), so the backlog is keyed on un-normalized text and `Kubernetes`/`kubernetes`/`KUBERNETES` each get their own row.

⚠️ **The mention table cannot serve as an evidence queue as written.** §8.4 calls it "the first-class evidence queue that feeds reconciliation", but a mention row records only *that* some token was seen in some artifact — not which token. Reconciliation (R1 harvest, R4 context assembly) needs surface + context, and can only get them from `kb.keyword_unresolved.contexts`, which the collector currently populates with the empty string. Either `kb.keyword_mentions` needs `surface`/`norm_key` columns, or the table should be dropped and the backlog treated as the only evidence store. This is a design gap, not just a wiring gap, and it blocks R1/R4.

🚧 **Known wart (provenance label):** the observe resolver stamps `provenance='llm:observe'`. No LLM runs in observe mode — the label is a misnomer, and it deviates from the `llm:<model>@<prompt_version>` convention of §4.2. It should be `rule:observe_resolver` or similar. Flagged here so it is not mistaken for a design choice.

**Worked example (observe mode, as the code actually behaves).** A document mentions `kubernets` (a misspelling). The collector tokenizes it and calls `ResolveSurface("kubernets", ks)`.
1. a mention row is written with `artifact_ref` set, `chunk_ref`/`ks_id`/`context_text` NULL;
2. `Kernel.Resolve` normalizes `kubernets` → `norm='kubernet'`; `CandidateNodes` runs against **scope `'_'`, not `ks`** (§6.1) — tier 0 (no exact surface row), tier 1 (no `norm_key='kubernet'` row), tier 2 (`keyword_surface_keys` empty), tier 3 (no enabled rules), tier 4 (empty) → no candidates → `deferred`;
3. the decision log gains a `family='keyword'`, `verdict='deferred'`, `scope=ks` row;
4. skipped — verdict is `deferred`;
5. `kb.keyword_unresolved` gets a **`('kubernets', ks)`** row — note the primary key holds the raw surface, not the `kubernet` norm key the schema comment promises — with `surfaces=["kubernets"]`, `hits=1`, `contexts=[]`.

Now suppose a `Kubernetes` concept with surface `Kubernetes` is authored via the API. Whether a later `ResolveSurface("Kubernetes", ks)` hits tier 1 depends on two things the design does not intend: the caller must have stored the surface with `scope='_'` (because lookups ignore `ks`), and must have supplied `norm_key='kubernete'` by hand — the value this normalizer actually produces (§5.5 N1) — since the API does not derive it. Get either wrong and the concept is invisible to the resolver. With both right, the call returns `auto_accepted` and step 4 writes the alias row. `kubernets` remains in the backlog until reconciliation resolves it.

### 7.4 Resolver modes — ⚠️ **Defect** (the default is not honoured)

`KEYWORD_RESOLVER_MODE` (env var):

| Mode | Intended behavior | As shipped |
|---|---|---|
| `off` (default) | `CandidateNodes` returns nil, `ResolveSurface` no-ops. Zero production impact. | ⚠️ **only if the variable is literally set to `off`** — see below |
| `observe` | resolution runs and **records**: mentions, surfaces, decision log, unresolved backlog. **No result reaches any downstream consumer.** This is measurement. | ✅ |
| `on` | same pipeline with the downstream gate removed | ⚠️ **silently disables mention collection** — see below |

⚠️ **The default is open, not closed (§17.2 K6).** `keywords.ResolverMode()` correctly defaults an unset variable to `off`, but `ResolveKeywordSurface` — the REST handler — bypasses it and reads `os.Getenv("KEYWORD_RESOLVER_MODE")` directly. An unset variable therefore yields `""`, and every gate in the family is `if mode == "off"`, which `""` fails. On a server with the variable unset, `POST /api/v1/kb/keyword-resolve` resolves and writes mention, decision-log, and backlog rows. This inverts the fail-safe the whole mode design exists to provide, and it is a one-line fix (call `keywords.ResolverMode()`).

⚠️ **`on` is not "identical to observe" (§17.2 K7).** The mention collector gates on `keywords.IsObserveMode()`, which is true *only* for `observe`. Setting the mode to `on` — the intended graduation step — therefore turns mention collection **off** while leaving direct resolve calls enabled. Graduating `observe → on` today loses functionality instead of adding it.

#### What `observe` means concretely

Per D9, `observe` is not a third operating mode — it is working mode with its output disconnected. Concretely, in `observe`:

- the doc-processing **mention collector runs** and writes `kb.keyword_mentions` for every artifact-bearing chunk it sees (§9 — as a standalone call today, not yet pipeline-wired);
- **surfaces are derived and written** to `kb.keyword_surfaces` when a mention matches an existing concept deterministically at tiers 0–4 — but see K1: the derived-key rows in `kb.keyword_surface_keys` are not written, so tiers 2 and 4 never fire;
- **every resolution is appended** to the shared `kb.semid_decision_log` with `family='keyword'`, so the pipeline's behaviour is auditable before it is trusted;
- **`kb.keyword_unresolved` accumulates the backlog** exactly as it would in `on` mode, so the reconciliation pipeline (§11) can be sized and evaluated against real volume before any resolution is allowed to affect a live path;
- **no resolution result is attached** to retrieval, search payloads, or any downstream consumer — the answer is computed, recorded, and dropped;
- **no `aligns_to_term` assertion** (§14) is created or consumed.

The purpose is measurement without risk: `observe` tells you the mention volume, the tier hit-rate, the ambiguity rate, and the backlog growth curve — the numbers §16 asks for — while a wrong resolution can reach nothing. `on` is the same pipeline with the last two bullets reversed.

**Graduation.** From `observe` to `on` is intended to be a config flip, not a code change. Today it is neither: the `on`-mode consumer wiring does not exist (§17.1), and the `on` gate is wrong (K7 above). Both must land before the flip means anything.

---

## 8. Data model — ✅ **Built** (schema, migrations `20260803000001`–`00006`)

### 8.1 `kb.keyword_concepts`

| Column | Type | Notes |
|---|---|---|
| `concept_id` | TEXT PK | opaque, immutable |
| `pref_label` | TEXT NOT NULL | mutable display attribute |
| `gloss` | TEXT | 1–2 sentence disambiguation + LLM context |
| `scope` | TEXT NOT NULL DEFAULT `'_'` | namespace; `'_'` = global |
| `status` | TEXT CHECK | `active` \| `provisional` \| `merged` \| `deprecated` |
| `merged_into` | TEXT FK → concepts | tombstone pointer |
| `gloss_source` | TEXT DEFAULT `'none'` | human \| llm \| import \| none |
| `create_time` / `modify_time` | TIMESTAMPTZ | default `NOW()` |

Indexes: `(scope, status)`, `(pref_label)`.

**Lifecycle (ungoverned).** The transition matrix, not a linear chain: `active → {provisional, merged, deprecated}`, `provisional → {active, merged, deprecated}`; `merged` and `deprecated` are terminal. A no-op transition to the current status is allowed.

⚠️ `MergeConcept(from, to)` does **not** go through `TransitionStatus` — it issues a direct `UPDATE` setting `status='merged'` and `merged_into=to`. Consequences: a `deprecated` or already-`merged` concept can be re-merged (the state machine and the "unmerge first" rule are bypassed), chains and cycles are unchecked, and the source concept's existence is never verified — merging a non-existent id updates zero rows and returns success. It does verify the target exists and refuses self-merge. See §12.1.

### 8.2 `kb.keyword_surfaces`

| Column | Type | Notes |
|---|---|---|
| `surface_id` | TEXT PK | content-derived: `kws_` + first 6 bytes of `sha256(concept_id\|surface\|label_role)` as 12 hex chars. Note the id is computed *before* `label_role` defaults to `pref`, so a surface created with an empty role hashes `""` but stores `pref` |
| `concept_id` | TEXT NOT NULL FK | |
| `surface` | TEXT NOT NULL | verbatim — never only a derived key |
| `norm_key` | TEXT NOT NULL | working-mode index key. ⚠️ supplied by the API caller, never derived or checked against the normalizer (§17.2 K3) |
| `norm_version` | INT NOT NULL | |
| `label_role` | TEXT CHECK | `pref` \| `alt` \| `hidden` |
| `alias_type` | TEXT | expansion \| acronym \| initialism \| abbreviation \| synonym \| near_synonym \| misspelling \| plural \| inflection \| translation \| legacy \| brand \| code |
| `lang` | TEXT DEFAULT `'en'` | |
| `scope` | TEXT DEFAULT `'_'` | |
| `confidence` | DOUBLE PRECISION DEFAULT 1.0 | |
| `provenance` | TEXT DEFAULT `'human:'` | human \| rule \| llm:@pv \| import:src |
| `locked` | BOOLEAN DEFAULT FALSE | human-asserted; reconciler may not apply changes |
| `evidence` | TEXT | snippet / doc ref that justified the surface |

Unique index on `(norm_key, concept_id, scope, label_role)` — one surface form per concept per scope per role; indexes on `(norm_key, scope)` and `(concept_id)`.

### 8.3 `kb.keyword_surface_keys`

| Column | Type | Notes |
|---|---|---|
| `surface_id` | TEXT FK ON DELETE CASCADE | |
| `key_kind` | TEXT CHECK | `alnum` \| `sorted` \| `phonetic` \| `initials` |
| `key_value` | TEXT NOT NULL | |
| `norm_version` | INT NOT NULL | |

PK `(surface_id, key_kind)`; lookup index `(key_kind, key_value, norm_version)`. Keys are **derived data** — always written alongside the surface, never authored independently.

⚠️ **This table is empty in every shipped code path.** `SurfaceKeyStore.UpsertSurfaceKeys` exists and is unit-tested, but nothing calls it: not `ResolveSurface`, not `CreateKeywordSurface`, and there is no REST route. The PK `(surface_id, key_kind)` also permits only one value per kind per surface, which is right for the four current kinds but forecloses multi-valued keys later.

### 8.4 `kb.keyword_mentions` — the evidence queue

| Column | Type | Notes |
|---|---|---|
| `mention_id` | BIGSERIAL PK | |
| `artifact_ref` | TEXT | artifact/input-record reference |
| `chunk_ref` | TEXT | |
| `context_text` | TEXT | bounded snippet |
| `ks_id` | TEXT | knowledge-store scope |
| `create_time` | TIMESTAMPTZ | |

Append-only. Indexes on `(artifact_ref, chunk_ref)` and `(ks_id)`.

⚠️ **This table cannot feed reconciliation in its current shape.** It has no column naming the surface or norm key the mention was for, and the observe-mode writer populates only `artifact_ref` (§7.3). Every indexed column except `artifact_ref` is therefore NULL in practice, and a row carries no information reconciliation can use. Either add `surface` + `norm_key` (and have `ResolveSurface` pass `chunk_ref`, `ks_id`, and real context), or retire the table and treat `kb.keyword_unresolved` as the sole evidence store. Decide before R1/R4 is built.

### 8.5 `kb.keyword_unresolved` — the backlog

| Column | Type | Notes |
|---|---|---|
| `norm_key` | TEXT | PK component |
| `scope` | TEXT DEFAULT `'_'` | PK component |
| `surfaces` | JSONB | distinct raw forms, deduped, capped at 10 |
| `contexts` | JSONB | reservoir sample ≤5 snippets, ≤200 chars each |
| `hits` | INT DEFAULT 1 | |
| `status` | TEXT CHECK | `pending` \| `batched` \| `needs_human` \| `resolved` \| `junk` \| `insufficient_context` |
| `attempts` | INT DEFAULT 0 | |
| `last_attempt` | TEXT | `'<model>@<prompt_version>'` — negative-caching key |
| `priority` | DOUBLE PRECISION DEFAULT 0 | |
| `first_seen` / `last_seen` | TIMESTAMPTZ | |

PK `(norm_key, scope)`; work index `(status, last_seen)`. `UpsertUnresolved` merges surfaces (dedupe + cap at 10), appends contexts, and increments `hits`. `UpdateUnresolvedStatus` transitions status and increments `attempts` — the state machinery reconciliation will drive.

Three deviations from the design in the shipped store:

- ⚠️ the caller (`ResolveSurface`) passes the **raw surface** as `norm_key` (§17.2 K5), so the PK does not dedupe case or punctuation variants — precisely the job it exists to do;
- 🚧 `contexts` is a **keep-the-last-5 window**, not a reservoir sample. For a Zipfian stream that biases the sample toward recent occurrences; a real reservoir needs the running count, which `hits` already provides;
- ⚠️ the 200-character cap is applied as a **byte** slice (`contextText[:200]`), which can cut a multi-byte character in half and store invalid UTF-8. The pilot corpus is predominantly Chinese, so this will fire. Slice by runes.

The read path also requires both `scope` and `status` (`WHERE scope = $1 AND status = $2`), so there is no "all pending across scopes" query — the reconciliation driver will need one.

### 8.6 `kb.keyword_rewrite_rules`

| Column | Type | Notes |
|---|---|---|
| `rule_id` | TEXT PK | |
| `pattern` | TEXT NOT NULL | **constrained**: simple literal, no capture groups / backreferences / backslashes (validated in the create handler) |
| `replacement` | TEXT NOT NULL | |
| `scope` | TEXT DEFAULT `'_'` | |
| `enabled` | BOOLEAN DEFAULT FALSE | default off; a human enables |
| `provenance` | TEXT DEFAULT `'human:'` | |
| `create_time` / `modify_time` | TIMESTAMPTZ | |

Index on `(enabled, scope)`. Rules are applied in **tier 3** as a pre-normalization rewrite: if the **raw surface** equals a rule's `pattern` (exact, case-sensitive, byte-for-byte, before any normalization), the surface is rewritten to `replacement` and tiers 0–1 retry with the rewritten form. At most one rule fires per resolve.

🚧 Because the match is on the raw surface, a rule is one-string-to-one-string — it cannot express the family-level generalization ("`<name>-svc` → `<name> service`") that makes rule promotion the cost-bending lever in §11. Matching the *normalized* surface, or supporting a prefix/suffix template, is the minimum needed before R7 rule promotion is worth building.

### 8.7 Why these tables, not the earlier specs' shapes

The earlier specs proposed concept/variant/variant_links and concept/alias/alias_key shapes. The merged design kept the four-layer identity (D1) and Postgres storage (D3), and **collapsed the variant/link split into a single `surfaces` table** (each surface row already carries its concept FK, role, provenance, and lock) plus a derived-keys table. The audit/guardrail tables from the second spec (`decision_log`, `never_merge`, `snapshot`) became rows in the **shared kernel tables** (§6.4), scoped by family — not a second keyword-specific set.

---

## 9. Mention collection — 🚧 **Built (standalone, not pipeline-wired)**

`KeywordMentionCollector` (`ChenWeb/server/api/doc-processing/keyword_mention_collector.go`) extracts candidate keyword mentions from document text and resolves each through the keyword family. It runs **only in observe mode** (`IsObserveMode()`).

- **Tokenization:** splits on any non-letter/non-digit rune; keeps tokens of 2–50 runes.
- **Stopwords:** a 59-word English stopword list is skipped (not full NLP).
- **Scope:** from the knowledge-store id (`ks_id`), else `'_'` — but the resolver ignores it (§6.1).
- **Resolution:** each unique token is passed to `KeywordFamily.ResolveSurface`, which writes the mention, runs the kernel, and records the outcome. Errors are swallowed (best-effort — a collector failure must not fail a batch).
- **Context:** ⚠️ the collector passes `""` for `contextText`, so no snippet ever reaches `kb.keyword_unresolved.contexts`. R1 harvesting and context disambiguation both depend on those snippets; both are dead until the collector passes a real window.

⚠️ **"Supports CJK" overstates it.** CJK characters are letters, so an unpunctuated Chinese run becomes **one token** of up to 50 runes — there is no word segmentation. On the 呼吸机/医疗器械 corpus the collector will emit clause-length pseudo-tokens that resolve to nothing and fill the backlog with junk. Either segment (jieba or equivalent) or restrict the collector to Latin-script tokens until segmentation exists.

🚧 **Single-token only.** The unit of collection is one whitespace/punctuation-delimited token, so no multi-word surface (`machine learning`, `heating ventilation and air conditioning`) can ever be observed. That removes the entire class of surfaces the `sorted` and `initials` keys were designed for, and means the acronym↔expansion problem — the module's headline case — cannot arise from collected data. N-gram candidate generation is a prerequisite for the module to be useful on real text.

🚧 **Not integrated:** the collector is a standalone `CollectFromText` function. It is **not registered** as a `PostProcessIndexer` in the doc-processing pipeline. This is deliberate for observe mode (measure volume without changing production behavior), but it means mentions are not being produced from real documents yet. Until pipeline integration ships, the data model can be exercised via the REST API and seeded manually.

### 9.1 What this collector is for — and what it isn't for

The prior paragraphs describe *build status*. This paragraph is the piece that was missing from every document that touches the collector (this spec's earlier revision, the Track B handoff, the implementation log): **why it exists as a separate mechanism at all**, and specifically why its being unwired is not simply an omission.

There are two different jobs a "something produces keyword surfaces" mechanism can do, and the collector is built for only one of them:

1. **Targeted enrichment.** A processor already knows, structurally, that a given string is a keyword — `extract_metrics`' `metric_name`, `extract_metric_definitions`' `canonical_name`/`aliases`, an entity's alias field. Resolving *that specific field* through `KeywordFamily.ResolveSurface` is a direct call: high precision, no ambiguity about what's being resolved, no need for tokenization or stopword heuristics at all. §14.1/§14.2 describe this path for metrics. **The collector is not needed for this job**, and using it here would be strictly worse than a direct call — it would rediscover the same string by blind tokenization instead of being handed it.
2. **Corpus-wide recall.** Vocabulary that appears in document prose but never becomes any structured field — an incidental competitor-product mention, an abbreviation used only in passing, a term relevant to future search but not itself a metric/provision/entity. No structured extractor produces this; the only way to catch it is to scan the raw text generically, which is exactly what the collector does: chunk-blind, tokenizing everything, aware of no processor's semantics. This is a real, legitimate goal — but it is a **search/retrieval-expansion** goal, not an extraction-quality goal.

The collector was built for job 2. Its most immediate consumer — not retrieval, more precisely — is **reconciliation** (§11): "reconciliation is a batch job that drains `kb.keyword_unresolved` and grows the database," and R1/R4 specifically consume the context snippets a mention carries. Reconciliation is itself unbuilt, so the chain is: collector → backlog → reconciliation (missing) → a grown lexicon → retrieval/faceting/analytics consumers (also missing). Wiring the collector into production today would generate mentions, surfaces, and backlog rows that nothing downstream ever reads — measurement with no one reading the measurement, at two removes rather than one. §9.2–§9.3 work through this in more detail, including where this framing was too imprecise on its own.

None of this bears on metric-name canonicalization, or on any other targeted-enrichment use: those go through job 1, need no consumer beyond the processor doing the resolving, and are not blocked on this.

### 9.2 Follow-up questions, answered directly

**Given the metrics-first requirement, can the collector be safely postponed?** Yes. Metric-name canonicalization goes entirely through job 1 (targeted enrichment, §14.1/addendum `2026080404`) and needs nothing from the collector. This isn't just a scoping convenience — it matches the ADR's own stated policy for anything outside the pilot vertical slice: DR12 (§3.13) keeps every artifact family other than the metrics pilot at "candidate-only... until P6 measures per-method precision." Corpus-wide keyword harvesting, unrelated to any specific metric, is squarely outside that slice. Postponing it isn't a gap in the plan; it's the plan.

**Why design something before its consumer exists?** Fair challenge, and the honest answer is that the *design* did name consumers — they're just not built. The two source specs this module was merged from are explicit (`2026072301-spec` Goal 7): "keep the module reusable across search, extraction, enrichment, faceting, and analytics." The earlier merged draft (`2026080101-spec` §3.7) names a more specific one: "the same keyword concept (e.g., 'IRA') can be recognized across entity aliases, provision references, and metric descriptions, enabling the cross-artifact search expansion that motivates this module." So the consumers were never undefined — search expansion, faceting, analytics, and specifically cross-artifact concept recognition. What's true is that **none of them are built**, and Track B built the collection end of a five-stage chain (collect → reconcile → grow lexicon → serve retrieval/faceting) without building any other stage. That's a real sequencing problem, distinct from "no one thought about who'd use this."

**Do collected mentions become `ontology_term` rows? If not, why extract them?** No — and conflating the two is worth heading off explicitly, because the keyword lexicon and the ontology-term catalog are deliberately separate layers (§14): keyword concepts are fast, ungoverned, auto-mergeable; ontology terms are reviewed, owned, released. Collected mentions feed `kb.keyword_unresolved`, which reconciliation (once built) resolves into `kb.keyword_concepts`/`kb.keyword_surfaces` — the *lexicon*, not the term catalog. A given keyword concept might *later*, selectively, get promoted into governed vocabulary via an accepted `aligns_to_term` assertion (exactly the mechanism the addendum proposes for metric names) — but that's the exception, reserved for concepts a domain decides are worth governing, not the default fate of everything the collector observes. Most of what a generic collector picks up from prose — an incidental product mention, a passing abbreviation — has no reason to ever become a governed term; it only needs to be canonicalized so retrieval can match "postgres" against a "PostgreSQL" document. That retrieval-time benefit, not term promotion, is the reason to extract it at all.

**Does broader collection help resolve keyword ambiguity?** Real, but not in the way "resolve" suggests — collection doesn't resolve anything itself; it accumulates the *evidence* that lets something else resolve it later. Each mention's context snippet, and the growing hit count on a backlog entry, are exactly what R1 (context-pattern harvesting) and R4 (batch assembly with context) in reconciliation need to disambiguate a homonym like `ML` correctly instead of guessing from one occurrence. The collector currently sends an empty string for context (§9, above) — until that's fixed, this benefit doesn't yet exist even in principle.

**Should there be a doc processor (or several) using an LLM to do this extraction?** No — and this one matters enough to state as a hard constraint, not a preference. Mention *collection* has to stay free and deterministic: it runs on every chunk of every document, and the module's entire economic thesis (§1.4: "LLM cost should scale with vocabulary growth, not with query volume") depends on that step costing nothing. An LLM-based collector would make cost scale with corpus size instead, which is exactly the failure mode the design exists to avoid. LLM usage belongs only in reconciliation (R4/R5), applied to the deduplicated backlog, not to every mention. On the "one or several" question: one processor is the right shape, not several — the collector's whole value is being document-type-agnostic (it reads the same chunks regardless of what other processors extract from them), so splitting it by document type would just reintroduce the coupling to specific extractors that job 2 exists to avoid.

**`on` mode is what a production system would run — doesn't calling `ResolveSurface` in `on` mode already make something a consumer?** Yes, and this sharpens a distinction §9.1 didn't draw precisely enough. Once the addendum's targeted-enrichment integration is built — `associate_semantics.processMetric` or `extract_metric_definitions`' harvest step calling `KeywordFamily.ResolveSurface` — those *are* real `on`-mode consumers, in exactly the sense meant here: something calls resolve, does something with the result, in production. That closes the "`on` mode has no consumer" gap for the *targeted* path. It does not close it for the *collector's* path: a consumer of one known field (a metric name) is not a consumer of the broad, undifferentiated mention stream the collector produces. The collector still needs something that reads the *lexicon in bulk* — retrieval expansion, a faceting view, an analytics query — not something that resolves one field it already knows about.

### 9.3 Decision

**1. The values of the collector**, when built correctly and consumed:

- corpus-wide vocabulary coverage that no structured extractor produces — incidental mentions, terms outside any artifact family's schema;
- the specific cross-artifact recognition case named in the original design: one keyword concept found consistently whether it surfaces in an entity alias, a provision reference, or a metric description, worded differently each time;
- an evidence base (contexts, hit counts) that makes reconciliation's disambiguation decisions better-informed than a single occurrence would allow;
- a lexicon that is already populated, not starting from zero, whenever a retrieval or faceting consumer is eventually built on top of it.

**2. Its potential consumers**, in the order they'd actually need to exist:

- **reconciliation** (§11) — the direct, immediate consumer of collector output; drains `kb.keyword_unresolved` into grown concepts and surfaces. Unbuilt.
- **retrieval / search query expansion** — matches a query against all known surfaces of a concept, not just the literal string typed. Unbuilt, no design beyond the mention in `on` mode's description (§7.4).
- **faceting / analytics** — "what keywords appear across the corpus, how often, under which canonical concept." Unbuilt, not designed beyond the metric names listed in §16.
- **selective `aligns_to_term` promotion** — a minority of concepts, chosen deliberately, entering governed vocabulary. Not a default consumer of most collector output (§9.2 above).

**3. How to plug it in, if kept:**

- fix the two collector defects that make its output unusable today: single-token-only collection (§9) and CJK non-segmentation (§9) — otherwise wiring it in produces junk faster than it produces value;
- register it as its own doc processor in `processor_plan.go`, parallel to `extract_metrics`/`extract_metric_definitions` — one entry, not several (§9.2);
- run it **unconditionally**, with no `Class: "routed"` cost gate: unlike LLM-based extractors, it has no per-document LLM cost to justify skipping any document;
- keep it strictly zero-LLM (§9.2) — this is a constraint on any future change to it, not just its current state;
- build reconciliation (§11) before or alongside wiring it in — collecting without draining just grows an unbounded, un-actioned backlog (§17.3's "operational consequence" already warns about this for the currently-empty case; a wired-in collector makes it a real, growing one).

**4. What we lose if we decide not to support it:**

- any keyword concept that only ever appears in prose — never inside a metric name, a provision reference, an entity alias, or another structured field — never enters the lexicon at all, regardless of how often it's mentioned;
- the cross-artifact recognition case (§9.3.1) only partially works: it connects keywords across structured fields that different processors happen to extract, but not the vocabulary that lives only in the surrounding text;
- reconciliation, if built for the targeted paths alone, has a much smaller and narrower evidence base — one context snippet per targeted extraction, instead of every mention across the corpus;
- retrieval/search expansion, if ever built, would only expand queries across the targeted-path vocabulary (metric names, entity aliases, and whatever else gets targeted enrichment) — general-purpose search-query expansion across arbitrary corpus vocabulary would not be possible without building something equivalent to the collector eventually.

None of this is a reason to build it now. It's the honest account of what stays permanently out of reach if the answer turns out to be "never," versus "not yet."

---

## 10. REST API — ✅ **Built** (14 endpoints under `/api/v1/kb/keyword-*`)

Handlers in `ChenWeb/server/api/kbhandler/keyword_handlers.go`; routes registered in `ChenWeb/server/api/routes.go` (lines 461–474).

| Method | Path | Handler | Purpose |
|---|---|---|---|
| GET | `/kb/keyword-concepts` | `ListKeywordConcepts` | list active+provisional, filter by scope |
| POST | `/kb/keyword-concepts` | `CreateKeywordConcept` | create a concept |
| GET | `/kb/keyword-concepts/:concept_id` | `GetKeywordConcept` | fetch a concept |
| PUT | `/kb/keyword-concepts/:concept_id` | `UpdateKeywordConcept` | update label/gloss |
| POST | `/kb/keyword-concepts/:concept_id/status` | `TransitionKeywordConceptStatus` | lifecycle transition |
| POST | `/kb/keyword-concepts/:concept_id/merge` | `MergeKeywordConcept` | tombstone merge |
| POST | `/kb/keyword-surfaces` | `CreateKeywordSurface` | attach a surface |
| GET | `/kb/keyword-surfaces/:surface_id` | `GetKeywordSurface` | fetch a surface |
| GET | `/kb/keyword-concepts/:concept_id/surfaces` | `ListKeywordSurfacesByConcept` | surfaces for a concept |
| PUT | `/kb/keyword-surfaces/:surface_id/lock` | `LockKeywordSurface` | lock/unlock a surface |
| POST | `/kb/keyword-rewrite-rules` | `CreateKeywordRewriteRule` | create a rule (disabled by default) |
| GET | `/kb/keyword-rewrite-rules` | `ListKeywordRewriteRules` | list enabled rules |
| PUT | `/kb/keyword-rewrite-rules/:rule_id/enabled` | `ToggleKeywordRewriteRule` | enable/disable a rule |
| POST | `/kb/keyword-resolve` | `ResolveKeywordSurface` | resolve one surface (observe) |

The resolve endpoint returns the kernel `Resolution` (verdict, scored matches, resolved node id) and, when the resolver is `off`, a `resolved: false` response. Returning the verdict to the API caller is an admin/diagnostic surface — observe mode's "no downstream consumer" means no *retrieval/search* path consumes the result, not that the API hides it.

Gaps in the API surface:

- ⚠️ `POST /kb/keyword-surfaces` takes `norm_key` from the request body and stores it unmodified. Nothing derives it from `surface`, nothing checks it against the normalizer, and no derived keys are written. Cardinal rule 2 (§4.2) is unenforced at the only human-facing write path, so the tier-1 index can silently disagree with the normalizer. The handler should compute the bundle itself and ignore any caller-supplied key.
- ⚠️ `ResolveKeywordSurface` reads `os.Getenv` instead of `keywords.ResolverMode()` — the open-by-default defect in §7.4.
- 🚧 There is **no REST surface for `kb.keyword_surface_keys`, `kb.keyword_mentions`, or the unresolved backlog**. The backlog in particular has no list, no status transition, and no admin view, so in observe mode it can be written but not read or drained through the API.
- 🚧 No endpoint retracts a surface, deletes a rule, or records a `never_merge` pair for the keyword family.

---

## 11. Reconciliation mode — ⏳ **Deferred** (data structures built, workflow not)

Reconciliation is a batch job that drains `kb.keyword_unresolved` and grows the database. Only the schema and stores that support it are built; the batch workflow itself is not.

### 11.1 The seven stages

```
R1 harvest      free extractors (Schwartz–Hearst parenthetical acronym extraction,
                 reverse pattern, definitional patterns) — zero LLM tokens
R2 prune        drop junk, dedup, frequency-floor; negative-cache anything already
                 marked junk/insufficient_context by the same model@prompt_version
R3 block        lexical (pg_trgm) ∪ semantic (pgvector) blocking to k candidates
                 per unknown — the biggest cost lever
R4 assemble     batch clusters into compact (pipe-row, not JSON) prompts; tag
                 unreviewed LLM glosses to avoid self-confirmation
R5 decide       structured output, cheap-model bulk pass; escalate ambiguous/
                 high-blast-radius/high-traffic items to a stronger model
R6 validate     deterministic gates (schema, referential, acronym plausibility,
                 role consistency, never-merge, lock, scope, blast-radius,
                 confidence, digit veto) — reject before writing
R7 apply+learn  transactional write through the kernel; append to the shared
                 decision log; promote candidate rewrite rules; rebuild snapshot
```

The stores exist to support this: the backlog carries `status`, `attempts`, and `last_attempt` (negative caching), and the surfaces/concepts stores enforce the gates' invariants (status CHECKs, role CHECKs, literal-only rewrite patterns).

### 11.2 Guardrails the design requires (for when R1–R7 is built)

The fuzzy-tier guardrails are binding and designed, though tiers 5–6 are not implemented:

```
len <= 4          -> no fuzzy matching at all; exact keys only
5 <= len <= 8     -> max edit distance 1, AND first character must match
len >= 9          -> max edit distance 2, AND normalized similarity >= 0.88
```

Plus three absolute vetoes, applied before any threshold:

1. **Digit veto** — strings differing in any digit never fuzzy-match (digits are versions/tiers/generations).
2. **Canonical veto** — a query that is itself an exact `pref_label` never fuzzy-matches elsewhere.
3. **Negation/affix veto** — `un-`/`non-`/`de-`/`anti-`/`-less` differences never fuzzy-match.

Reconciliation must never take the transitive closure over pairwise merge decisions, and `locked`/`never_merge` rows are absolute boundaries.

### 11.3 Backlog drain

Backlog draining reuses the DR5/DR6/DR7 pattern already built for ambiguous object reconciliation (ADR `2026070701`): a bulk backfill endpoint, a human-review admin page, and an optional confidence-gated LLM adjudication path — not a bespoke queue mechanism. Of these, P3 Track A built the DR5 bulk-backfill pattern; the DR6 (admin review) and DR7 (LLM adjudication) halves remain unbuilt.

---

## 12. Merge, split, and identity lifecycle — 🚧 **Partial** (merge), ⏳ **Deferred** (split)

### 12.1 Merges

`MergeConcept(from, to)` is a tombstone: `from.status = 'merged'`, `from.merged_into = to`. The row survives, so stale ids keep resolving. Self-merge is refused and the target's existence is verified. Surfaces are not physically moved; they resolve through the surviving concept.

⚠️ **This is a keyword-family method, not the kernel's.** The `semid` kernel does have a `MergeGraph` with the full guardrail set — never-merge refusal, already-merged refusal, cycle-guarded chain resolution, `Unmerge` — but it is an **in-memory structure with no persistence**, it is exercised only by kernel unit tests, and no keyword code path uses it. What ships for keywords is a direct `UPDATE` with none of those checks (§8.1). Consequences: a merged concept can be re-merged, chains and cycles are unchecked, `never_merge` is not consulted, and nothing follows `merged_into` at read time — a resolve that lands on a tombstoned concept returns the tombstone's id, not the survivor's.

Two things must happen before merge is safe to expose to a reconciler: persist the kernel merge semantics (or replicate the checks in `MergeConcept`), and make resolution follow `merged_into` to the surviving concept.

### 12.2 Never-merge — ⚠️ **Storage only**

`kb.semid_never_merge` (kernel table, `family = 'keyword'`) is designed to record unordered pairs that must never merge, even if a future reconciler pass would propose it. `NeverMergeStore.Add/IsNeverMerge/List` exist from P2.

**No keyword code path calls any of them.** There is no keyword endpoint to add a pair, and `MergeConcept` does not check for one. The guardrail is currently a table, not a guarantee. Because the only merge caller today is a human hitting an admin endpoint the risk is contained — but the gate must be closed before R7 can apply a merge.

### 12.3 Locked surfaces

A `locked` surface is human-asserted; the reconciler may propose changes but never apply them. The lock is toggled via `PUT /kb/keyword-surfaces/:surface_id/lock`. The flag is stored and toggleable; since no reconciler exists, nothing yet honours or violates it.

### 12.4 Splits

`split_concept` is **not built**. Splits are rarer and more painful than merges, which is itself the argument for the under-merge bias (D10).

---

## 13. Seeding strategy — ⏳ **Deferred** (design adopted, no seed module)

Seed sources, each recording provenance so later cleanup is possible:

1. curated keyword lists already present in KnowledgeStore and prompts (`provenance = import:prompt_seed`);
2. existing aliases/acronyms recorded on entities, metrics, provisions, products, and object nodes (`provenance = import:artifact_backfill`);
3. manually curated domain glossaries (`provenance = human:<curator>`).

🚧 **Current state:** there is no `ontology-seed` keyword module and no artifact-backfill job. Concepts and surfaces are authored today through the REST API. Until seeding ships, the database starts empty by default.

---

## 14. The bridge to governed terms (`aligns_to_term`) — ⏳ **Deferred**

A keyword concept is an **ungoverned canonical lexical identity**: fast, high-volume, auto-mergeable under the guardrails. A governed ontology term (P2) is a **reviewed meaning** with a definition, owner, and release. The two are connected by an accepted `aligns_to_term` assertion (DR9's assertion/evidence schema) — exactly as an object node connects to its class via `instance_of` — **never** by merging the keyword concept into the term space. This keeps the fast, high-volume lexicon separate from the slow, governed vocabulary.

None of this is built: there is no `AssociationResolver` for keywords, no `aligns_to_term` column or assertion producer, and observe mode explicitly creates no such assertions.

### 14.1 `extract_metrics` vs. `extract_metric_definitions` — two processors, no relationship between them

Both are real, both run in Phase B of the same pipeline (`processor_plan.go`), both read the same documents, and today **neither knows the other exists**.

| | `extract_metrics` | `extract_metric_definitions` |
|---|---|---|
| File | `doc-processing/extract-metrics.go` | `doc-processing/extract-metric-definitions.go` |
| Question it answers | "What did *this document* assert?" | "What metric *concepts* does this domain have?" |
| Output | a per-document **observation**: a value, unit, condition, comparator, tied to a specific subject in this document | a candidate **governed term**: `{canonical_name, aliases, definition, value_type, range_type}` — independent of any observed value |
| Destination | `kb.metrics`, then (via `normalize_assertions` → `associate_semantics`, Phase C) `kb.semantic_assertions` | `kb.ontology_candidates` (`candidate_kind='term'`), pending human promotion to `kb.ontology_terms` (`term_kind='metric_definition'`) |
| Where the metric's *name* ends up | a free-text string in `Assertion.Qualifiers.metric_name` — carried through, never resolved against anything (§ associate_semantics.go:226) | the candidate's `canonical_name`/`aliases` fields — likewise carried through unresolved |

**They are meant to converge and don't.** `extract_metrics`' `metric_name` ("luminance", "亮度", "显示亮度" — however a given document happens to phrase it) is exactly the kind of surface variation the keyword lexicon exists to collapse; `extract_metric_definitions`' `canonical_name`/`aliases`, once promoted to a term, are exactly what DR23 calls "the DR15/DR16 keyword lexicon instantiated over metric terms, aligned by `aligns_to_term`." Verified in the code: `processor_plan.go` declares no dependency edge between the two processors, `associate_semantics.processMetric` never looks up `kb.ontology_terms`/`kb.ontology_candidates` for anything but the fixed predicate/assertion-kind terms (`mea:measured_by`, `mea:<assertion_kind>` — the kind of claim, not which metric), and there is no column or join anywhere linking `kb.metrics.metric_name` to `kb.ontology_terms`. Two documents asserting "luminance is 450 cd/m²" and "亮度为450cd/m²" today produce two `kb.metrics` rows with no way to know they're the same metric, and a `kb.ontology_candidates` proposal (if `extract_metric_definitions` happened to catch either as an explicit definition) that never learns it could resolve either one.

### 14.2 `kb.ontology_candidates` — what it is and what happens to what lands in it

`kb.ontology_candidates` is the single proposal channel for **all** governed ontology content — terms, labels, mappings, axioms, profiles, profile rules, module changes (`candidate_kind` CHECK). Nothing reaches `kb.ontology_terms` / `kb.ontology_term_labels` / `kb.ontology_mappings` except through this table and its state machine; the migration comment calls this "the code-enforced form of the 'no LLM activates ontology content' guarantee."

**Lifecycle** (`candidates/state_machine.go`): `discovered → draft → in_review → approved → included_in_release`, with `rejected`/`deferred` branches off the first three states, and `deferred → draft` reachable only through `RetryDeferred` when the candidate's `dependency_fingerprint` has actually changed. `approved` and `included_in_release` are reached only by a human action through `kbhandler/ontology_candidates_handler.go` (`TransitionOntologyCandidate`, `PromoteOntologyCandidate`) — there is no automatic promotion path. **This is a genuine, by-design blocker**, not an arbitrary defer: it is why zero `metric_definition` instance-terms exist today (`kb.ontology_terms` has exactly one `metric_definition`-kind row, and it is the meta-term describing what a metric definition *is* — `mea:metric_definition` — not an actual metric like luminance).

**Deduplication is exact-match only.** `Fingerprint()` hashes the canonicalized payload + source + module; `UNIQUE(fingerprint)` means an identical re-extraction reuses the existing candidate rather than opening a duplicate review item (`candidates/fingerprint.go`). It does **not** catch near-duplicates: "luminance", "亮度", and "显示亮度" extracted from three different documents produce three different fingerprints and three separate review items, with nothing telling the reviewer they are the same proposal in three spellings.

**This is precisely the gap `candidate_matches` was left in the schema to fill, and precisely where it stays empty.** The `candidate_matches JSONB` column exists on `kb.ontology_candidates` for exactly the signal a reviewer needs — "this proposal looks like it matches existing candidate/term X" — but nothing computes it. Verified: `CreateOntologyCandidate` only accepts it as an optional caller-supplied field; `ontology_candidate_harvest.go` (which builds `extract_metric_definitions`' candidates) never sets it; no code reads it back for display. Resolving a candidate's `canonical_name`/`aliases` through `KeywordFamily` at harvest time — before the candidate is written — is the natural place to populate this field: an `auto_accepted` or `ambiguous` keyword resolution against an existing keyword concept (and, transitively, any term it already `aligns_to`) is exactly a "this looks like something you've seen" signal, surfaced to the human reviewer instead of left for them to notice by eye across unrelated review items.

---

## 15. Failure modes and guardrails

### 15.1 Over-merging is the asymmetric risk

| | Under-merge (missed alias) | Over-merge (wrong link) |
|---|---|---|
| Symptom | cache miss; goes to the queue | silently wrong answers |
| Detection | automatic (it's in `unresolved`) | none |
| Cost of fix | one reconciliation cycle | manual archaeology across the audit log |
| Downstream blast | none | every consumer that trusted the canonical form |

The design biases toward under-merging everywhere (D10).

### 15.2 Other failure modes and their mitigations

The third column is the honest one: most of these mitigations belong to the unbuilt reconciler.

| Failure | Mitigation | In force today? |
|---|---|---|
| Canonical label churn | opaque immutable ids; labels are display attributes | ✅ yes |
| Normalizer drift | `norm_version` + full re-index; never mutate stored surfaces | ⚠️ column stored but never filtered on (§5.5 N4); and the normalizer has already drifted wrong (N1) |
| LLM self-confirmation | tag unreviewed LLM glosses in prompts | ⏳ reconciliation design only |
| Hallucinated concept ids | referential gate | ⏳ reconciliation design only |
| Homonym collapse | scope-qualified uniqueness; `ambiguous` as a real verdict | 🚧 the verdict is real; scope qualification does not work (§6.1 K2) |
| Queue starvation | junk filter + negative caching + priority | ⏳ columns exist, no logic; `priority` is always 0 |
| Multi-writer races | single-writer reconciliation | ⏳ no reconciler exists |
| Caller pollution | input validation at the API boundary | 🚧 the resolve endpoint checks non-empty only; the collector's 2–50-rune filter is the only real gate, and it admits whole CJK clauses (§9) |

### 15.3 Where a human must be in the loop

Merges of two established clusters, any change to a `locked` surface, enabling a rewrite rule, and any `never_merge` deletion.

---

## 16. Evaluation and metrics

### 16.1 Online (working-mode) metrics

- coverage / hit rate — % of live lookups resolved at tiers 0–4;
- unresolved rate, ambiguity rate;
- median lookup latency.

### 16.2 Reconciliation metrics

- auto-attach precision, **false-merge rate** (hard gate);
- backlog burn-down, concept growth rate;
- human-override acceptance rate (the proxy for reconciler precision that should gate raising auto-apply thresholds).

### 16.3 Candidate-generation metrics

- blocking recall/precision (pair completeness, pairs quality) and reduction ratio.

### 16.4 Test coverage today — 🚧 **thinner than the counts suggest**

The keyword package ships 51 test functions across five files. `go test ./server/api/ontology/keywords/... ./server/api/ontology/semid/...` passes, and the P3 Track B handoff records `go build ./...`, `go vet`, and `gofmt -l` as clean. That is all true and all weaker evidence than it looks:

| File | Funcs | What it actually verifies |
|---|---|---|
| `normalizer_test.go` | 14 | individual pipeline steps and key-kind shape. **No test asserts an acronym survives singularization**, which is why §5.5 N1 shipped. `TestSingularization` covers only the 21-entry exception list. |
| `concepts_store_test.go` | 11 | sqlmock CRUD — SQL shape, not semantics |
| `surfaces_store_test.go` | 6 | sqlmock CRUD |
| `keywordfamily_test.go` | 9 | `FamilyName`, policy constants, key-bundle mapping, and the `off` / nil-DB early returns. **Not one test drives a tier against a database**, real or mocked — tiers 0–4 have zero behavioural coverage. |
| `keyword_exit_test.go` | 11 | ⚠️ **assertion-free.** Nine of the functions have empty bodies containing only a comment naming other tests. `TestExitCoverageComplete` builds a 9-entry literal map and asserts `len(map) == 9`. The file cannot fail for any reason related to the keyword lexicon. |

Its E4 entry claims tiers 0–2 and the deferred path are "covered by" `TestKeywordFamilyName`, `TestKeywordFamilyAutoAcceptPolicy`, `TestKeywordFamilyNormalizer`, and `TestKeywordNormalizerToSemidKeyBundleMapping` — none of which touch a tier. **Exit criteria E4, E6, E7, and E8 are unmet**, and the file's structure disguises that. It should either be deleted or replaced with real tests.

The minimum credible test set before this module is trusted: sqlmock (or live-DB) coverage of each tier's query and score, a normalizer table test containing `AIDS`/`SaaS`/`Kubernetes`/`AWS's`, a scope round-trip test (write at `ks`, read at `ks`), and a resolver-mode test asserting that an **unset** `KEYWORD_RESOLVER_MODE` writes nothing.

---

## 17. What is not done — exact, as of 2026-08-04

Two different things get confused when a partially built module is described, so they are separated here. **§17.1 is deferred work**: designed, deliberately unbuilt, no code claims otherwise. **§17.2 is defects**: code that exists and does something other than what this document specifies. Deferred work is a plan; a defect is a bug.

### 17.1 Deferred — deliberately unbuilt

Everything below is deliberately deferred. None of it is a hard blocker; it is the sequenced-slice strategy that ships the `observe` contract first and extends later.

| Item | Why deferred | Where it lands |
|---|---|---|
| **Fuzzy tiers 5–6** (trigram/vector blocking, edit-distance filtering, ANN) | requires `pg_trgm` + `pgvector` extensions and significant candidate-scoring code; the deterministic tiers 0–4 prove the kernel integration | P3 follow-up / P4 |
| **Reconciliation pipeline (R1–R7)** | stores and kernel exist; the batch CLI/workflow is not built. Reuses DR5/DR6/DR7 backlog-drain patterns from Track A. R3's blocking additionally depends on the `pg_trgm`/`pgvector` extensions that ship with the fuzzy tiers (also deferred), so R1–R7 inherits that infra timing — a sequencing dependency, not a hard blocker | P3 follow-up |
| **`aligns_to_term` bridge** | no `AssociationResolver` for keywords exists | P4+ |
| **`on` mode** (wiring into retrieval/search payloads) | no downstream consumer exists yet; observe mode measures volume first | P4+ |
| **Mention collector pipeline wiring** | coupled to the missing `on`-mode retrieval consumer (§9.1) — it serves corpus-wide recall for search/retrieval expansion, which has no consumer yet; targeted uses like metrics don't need it (§14.1) | revisit together with retrieval wiring, not before |
| **Context-token disambiguation** (IDF-weighted overlap for homonyms) | the collector currently passes empty context | later |
| **Full Double Metaphone phonetic key** | current `phonetic` key is a deterministic stub; a real implementation needs a dependency | P3 follow-up |
| **Curated seed content / artifact backfill** | content authoring + a seed module, not code | manual / follow-up |
| **Multi-word (n-gram) mention candidates** | collector emits single tokens only, so no multi-word surface can be observed (§9) | P3 follow-up |
| **CJK word segmentation in the collector** | no segmenter; unpunctuated Chinese becomes one pseudo-token (§9) | P3 follow-up |
| **Batch adjudication UI / unresolved-backlog admin** | admin surfaces not built; the backlog has no read API at all (§10) | P3 follow-up |
| **Rewrite-rule auto-promotion** | rules authored manually; no promotion from validated decisions | P3 follow-up |
| **`merged_into` chase at resolve time** | resolution returns a tombstoned concept id rather than the survivor (§12.1) | P3 follow-up |
| **I2 live PostgreSQL proof** | `chenweb_test` was not rebuilt with the new migrations; no live resolution exercised against real text | validation gap — the reason §17.2 was found by code read rather than by a failing test |

### 17.2 Defects — built, but not as specified

All eleven were verified by reading the code on 2026-08-04; N1–N3 were additionally reproduced by execution. Ordered by blast radius.

| # | Defect | Where | Effect | Fix size |
|---|---|---|---|---|
| **K6** | resolve endpoint reads `os.Getenv` instead of `keywords.ResolverMode()`, so an **unset** `KEYWORD_RESOLVER_MODE` is not `off` | `kbhandler/keyword_handlers.go:371` | the fail-safe default is open; the endpoint resolves and writes on any server that hasn't set the variable | one line |
| **N1** | singularization runs after case-folding — no ALLCAPS guard | `keywords/normalizer.go` §5.5 | `AIDS→aid`, `SaaS→saa`, `Kubernetes→kubernete`; distinct concepts collide, and every stored `norm_key` is wrong in a way a re-index will change | small, but a `norm_version` bump |
| **K2** | `Kernel.Resolve` uses `Family.Scope()` (constant `"_"`) for lookups while writes use the caller's scope | `semid/kernel.go:65`, `keywords/keywordfamily.go:69` | ks-scoped surfaces are written and then unfindable; the module is single-scope in practice | small — thread the caller's scope |
| **K5** | raw surface passed where `UpsertUnresolved` expects `norm_key` | `keywords/keywordfamily.go:308` | backlog PK does not dedupe variants; one concept occupies many rows; negative caching is per-spelling | one line |
| **K1** | nothing writes `kb.keyword_surface_keys` | resolver + `CreateKeywordSurface` | tiers 2 and 4 match nothing | small |
| **N3** | `initials` key is uppercase and tier 4 looks up the *query's* initials | §5.5 | tier 4 cannot bridge acronym↔expansion; populating K1 alone would make it match wrongly | design + small code |
| **K3** | `POST /kb/keyword-surfaces` stores a caller-supplied `norm_key` unvalidated | `kbhandler/keyword_handlers.go:194` | cardinal rule 2 unenforced; tier-1 index can disagree with the normalizer | small |
| **K8** | `MergeConcept` bypasses the status machine and consults no guardrail | `keywords/concepts_store.go:218` | already-merged/deprecated concepts re-mergeable; `never_merge` never checked; merging a non-existent id succeeds silently | small |
| **K4** | mention rows carry no surface, and `chunk_ref`/`ks_id`/`context_text` are never populated | `keywords/keywordfamily.go:253` | `kb.keyword_mentions` holds no reconcilable information; blocks R1/R4 | schema + wiring |
| **K7** | collector gates on `IsObserveMode()`, false in `on` mode | `doc-processing/keyword_mention_collector.go:43` | graduating `observe → on` turns mention collection off | one line |
| **N2** | possessive rule requires a trailing space | §5.5 | word-final `AWS's` → `aws'` | one line |

Lower-severity items recorded inline rather than in this table: context truncation by bytes not runes (§8.5), keep-last-5 in place of a reservoir sample (§8.5), `norm_version` never used as a filter (§5.5 N4), `surface_id` hashed before `label_role` defaulting (§8.2), the unreachable `human_review` arm in `ResolveSurface` (§7.3), the dead `phonetic` key (§5.2), and the assertion-free exit-criteria tests (§16.4).

**Suggested order.** K6 first — it is one line and it is the only defect with a live blast radius on a running server. Then K2 and K5, which corrupt data that a later fix cannot reconstruct: rows written under the wrong scope or the wrong key stay wrong. N1 next, since it forces a `norm_version` bump and a re-index, and every day of observe-mode data written before it lands is data that must be recomputed. K1/N3/K3 together, as one "derived keys are actually derived" change. K8 before any reconciler work begins. K4 before R1/R4 is designed.

### 17.3 Operational consequence

With `KEYWORD_RESOLVER_MODE` **explicitly set to `off`**, the module is inert. With the variable **unset** it is inert for the collector but not for the REST resolve endpoint (K6). With `observe`, mentions, surfaces, decision-log rows, and the unresolved backlog are written — but the backlog is keyed on raw surfaces (K5), scoped inconsistently (K2), context-free (§9), and drained by nothing until R1–R7 ships. **Data collected in observe mode before K1/K2/K5/N1 are fixed should be treated as disposable**, not as a corpus to migrate: `kb.keyword_unresolved` and any `provenance='llm:observe'` surface rows should be truncated after the fixes land.

---

## 18. Implementation record and how to verify

### 18.1 What shipped (P3 Track B, 2026-08-04, 7 commits on `main`)

`641b73b6` (chunk A, concept store) · `2355449a` (B, surface + surface_keys stores) · `8e709aaa` (C, mention/unresolved/rewrite-rule stores) · `c6c4a1a3` (D, normalizer) · `5e746c96` (E, `KeywordFamily` + `semid.Normalizer` extension) · `e6b8fb55` (F, REST handlers + routes) · `b5ffb554` (F+G+H, resolver mode, collector, exit criteria).

- Package `ChenWeb/server/api/ontology/keywords/` — normalizer, 6 stores, `KeywordFamily`, mode reader, tests.
- `semid.Normalizer.NormFunc` extension (backward-compatible; `TermFamily` unchanged).
- 14 REST handlers in `kbhandler/keyword_handlers.go`, routed in `server/api/routes.go:461-474`.
- Standalone collector `ChenWeb/server/api/doc-processing/keyword_mention_collector.go`.
- 6 goose migrations `20260803000001`–`00006`.

### 18.2 How to verify

```bash
cd ChenWeb
go test ./server/api/ontology/keywords/... ./server/api/ontology/semid/...
go build ./... && go vet ./...
```

These pass today and prove very little — see §16.4. Nothing in the suite would fail if any defect in §17.2 were introduced, which is why they were all found by reading rather than by running.

### 18.3 Document lineage

| Doc | Role |
|---|---|
| ADR `2026072901` §8.3.6 | defines P3 (assertions + keyword lexicon); DR15 kernel, DR16 merged keyword design |
| `2026080103-devdoc-semos-p3-implementation-log.md` | P3 Track A implementation log (assertions/evidence/Phase D, complete) |
| `2026080402-devdoc-semos-p3-trackb-implementation-log.md` | P3 Track B implementation log |
| `2026080401-handoff-semos-p3-trackb-keyword-lexicon.md` | P3 Track B session handoff |
| `2026080304-plan-semos-p3-trackb-keyword-lexicon.md` | P3 Track B implementation plan (chunks 0–H) |

---

## 19. Documentation impact

**What knowledge changed?** The keyword canonicalization module is now fully specified and partially implemented (observe mode). This document is the single self-contained reference; the three prior keyword specs are superseded. A 2026-08-04 code review additionally established that **the shipped Track B slice does not match the design in eleven verified respects** (§17.2) — that gap is new knowledge, and it is the reason §0 distinguishes "code exists" from "code is correct".

**Which docs/specs/ADRs/tests are affected?** ADR `2026072901` (DR15/DR16) is the design authority; the P3 Track B handoff and implementation log are the implementation record; this document supersedes `2026080101`, `2026072703`, and `2026072301` as the reference to read.

**Which docs are now stale?**

- The three superseded keyword specs remain on disk as historical inputs but are no longer authoritative.
- `2026080101-spec-keyword-canonicalization-merged.md` §7 is **wrong**, not merely superseded: it states that the keyword family's merge calls are the kernel's `MergeGraph`. They are not (§12.1). Anyone reading it for merge semantics will be misled.
- The Track B handoff `2026080401` and implementation log `2026080402` record the slice as complete against its exit criteria. Given §16.4, those exit criteria were self-certified by assertion-free tests; both documents should carry a pointer to §17.2.
- The `-- +goose Up` comments in `20260803000005` ("keyed on (norm_key, scope) — the natural dedup unit") and `20260803000006` ("tiers 0-2 retry") describe behaviour the code does not implement (K5, §8.6).

**What was intentionally left undocumented?** Exact reconciliation prompt text, exact Go package/API signatures beyond those shipped, and the mention collector's precise hook point in the doc-processing pipeline — the first is deferred with the reconciliation build, the last two are implementation decisions, not design decisions.

**What should happen next?** Fix §17.2 in the suggested order, add the tests in §16.4, then re-run this review. Until K6 lands, do not deploy a server with `KEYWORD_RESOLVER_MODE` unset expecting the module to be inert.

## 20. Open Questions
### 20.1 Open-Source Resources
There should be some resources in the Internet, such as open-source 'dictionaries', 
'thesaurus', or open-source projects that resolve keyword ambiguity, reconciliation, 
etc. Shall we consider them?

How about Wikipedia (possibly locally hosted)? Will it help resolve keyword ambiguity or 
reconcile keywords?