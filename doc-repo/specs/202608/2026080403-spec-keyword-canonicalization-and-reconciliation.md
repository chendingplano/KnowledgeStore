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

### 3.1 D1. Four identity layers, UMLS-style — 🚧 **Partial** (two of four layers are real entities; two are not)

Every keyword passes through four layers of abstraction:

```
occurrence   →   surface   →   lexform   →   concept
```

This is the design's central model, borrowed from UMLS. **It is generic — it applies to any keyword, from any source.** The chain is more precisely written as:

```
name   →   occurrence   →   surface   →   lexform   →   concept
```

where "name" is whatever raw string a producer supplies — a metric name, an entity alias, a provision reference, a token the mention collector pulled out of prose, anything. **A metric name is one instance of "name," and the four-layer machinery downstream of it (occurrence→surface→lexform→concept) is exactly the same machinery any other keyword goes through — nothing in it is metric-specific, and nothing metric-specific needs to exist for it to apply.** What *is* missing today is a producer that supplies metric names as "name" in the first place (below, and `2026080404`-addendum §5.1 walks the metric case end to end).

**A likely-sounding but incorrect mental model, worth heading off directly: `extract_metrics` does *not* "register with" the mention collector.** The collector (§9) is not a registration point other processors plug into — it is one specific, self-contained mechanism that reads *raw chunk text* and tokenizes it *itself*, blind to any other processor's output. It has no API for "here is a value I already extracted, please treat it as a name." The only way a metric name enters this chain is a **direct call** from somewhere downstream of `extract_metrics` — via the proposed `names.Resolver.ResolveName` facade (`2026080404`-addendum §2), **not** inside `associate_semantics.processMetric` (an earlier version of the addendum proposed exactly that, and a subsequent review found it would have deepened `associate_semantics.go`'s existing package-purity problem rather than fixing anything — corrected in the addendum's 2026-08-05 revision note). That call has nothing to do with the collector; the collector remains entirely separate, and stays parked regardless of whether metric-name resolution is built (§9.1–§9.3).

The rest of this entry is more concrete than the other D-items, because the gap between what these four words mean and what actually happens in the running code is the most common source of confusion in this module.

#### 3.1.1 Persistence
**Read this table before anything else in this entry — it is the single authoritative map from each layer to exactly where it lives, and it corrects the most common misreading of the diagram above: that each arrow is a separate table being looked up and handed to the next. It isn't.** Mechanically, there are exactly two real tables (`kb.keyword_surfaces`, `kb.keyword_concepts`); surface, lexform, and concept are three *columns on one row* of the first table for the common case, not three tables chained by joins.

| Layer | Is it a table? | Where it actually lives | Which column(s) | How a *consumer* (a metric, an entity, anything) connects to it |
|---|---|---|---|---|
| **name** | no — not part of this module | the producer's own table (e.g. `kb.metrics.metric_name`) | — | this *is* the consumer's own field; the keyword module never stores a copy of it under this name |
| **occurrence** | a table exists, but is incomplete | `kb.keyword_mentions` | `artifact_ref`, `context_text` (written); `chunk_ref`, `ks_id` (always null); **no column holds the name itself** — this is a schema gap, not a missing assignment (§17.2 K4) | nothing — no foreign key in either direction |
| **surface** | ✅ real, fully built | `kb.keyword_surfaces` | `surface_id` (PK), `concept_id` (FK, `NOT NULL`), `surface` (verbatim text), `norm_key`, `norm_version`, `label_role`, `alias_type`, ... | nothing directly — a consumer never stores a `surface_id` |
| **lexform** | ❌ not a table — a derived value | lives *as a column* on `kb.keyword_surfaces` (correctly) and on `kb.keyword_unresolved` (currently broken, K5) | `norm_key` (TEXT) | nothing directly |
| **concept** | ✅ real, fully built | `kb.keyword_concepts` | `concept_id` (PK, opaque), `pref_label`, `gloss`, `scope`, `status`, `merged_into`, ... | **the only thing a consumer ever references.** A proposed column like `kb.metrics.keyword_concept_id` would hold a *copy* of a `concept_id` value — a foreign key into this separate, shared table, never a duplicate of the concept's own data |

**Which tier queries what, precisely — matching is always `name` directly against `kb.keyword_surfaces` (or its child table), never against "occurrence":**

- **Tier 0**: `SELECT s.concept_id, s.norm_key FROM kb.keyword_surfaces s WHERE s.surface = $1` — `$1` is the raw `name`/`surface` string handed to `ResolveSurface`, compared byte-for-byte against the `surface` column.
- **Tier 1**: same table, `WHERE s.norm_key = $1` — `$1` is `name`, *after* normalization, compared against the `norm_key` column.
- **Tiers 2/4**: query `kb.keyword_surface_keys` (FK'd to `surface_id`), joined back to `kb.keyword_surfaces` for `concept_id`.

`kb.keyword_mentions` is never queried by any tier. It has no role in resolution at all — it is a (currently broken) audit side-effect, written once per call and never read back by anything in the resolve path.

**Open Question 01**: does it mean `kb.keyword_mentions` is only logs that can be referenced by others,
otherwise, it is not 'used'?

> **Answer:** Verified precisely — as shipped, it's less than "referenced by others": `MentionStore.ListMentions` (the only read function that exists for this table) is called from **nowhere else in the codebase** — no REST handler, no batch job, no other Go file. `InsertMention` is called; nothing ever reads a row back out. So today it isn't "logs others can reference" — it's logs nothing references. `ListMentions` exists as dead code waiting for a caller (e.g., an admin/debug endpoint) that was never built.

**Open Question 02**: there is no (physically) `occurrence` in the implementation, 
only `kb.keyword_mentions`, or can be say: `kb.keyword_mentions` is (should be) `kb.keyword_occurrence`?

> **Answer:** Yes to both. There is no other table or structure anywhere that represents "occurrence" — `kb.keyword_mentions` is the only candidate, and it was designed to be exactly that (§8.4 calls it "the evidence queue"). Renaming it to `kb.keyword_occurrences` once it's fixed (surface/name column added, per K4) would make its role match its name — worth doing given the data reset you've already decided on, since there's no migration cost to pay.
>
> **Complexity/consequence evaluation (requested separately, not high priority):** Low, and lower than a typical rename precisely because of what OQ01 just established. A rename normally costs: the migration, every Go reference (`MentionStore` → `OccurrenceStore`, `Mention` struct → `Occurrence`, `InsertMention`/`InsertMentions`/`ListMentions` → renamed methods), and every external consumer. The last category is empty — confirmed, no REST handler and no other package calls into this table at all. So the actual surface area is: one migration file, one Go file (`mentions_store.go`), and the four call sites inside `keywordfamily.go`/`keyword_mention_collector.go` that reference `Mention`/`MentionStore`. No test depends on the name (`mentions_store_test.go` would need the same mechanical rename, nothing more). Given the data reset already decided, and that K4's fix already requires changing this table's columns regardless, the practical recommendation is: don't treat this as a separate rename task — when K4 is fixed (adding the surface/name column this table is missing), just create the corrected table as `kb.keyword_occurrences` from the start, with `OccurrenceStore`/`Occurrence` naming throughout. Net cost of naming it right the first time versus naming it wrong and fixing it later is close to zero.

**Who generates an occurrence — literally, who calls the function.** An occurrence comes into existence when something calls `KeywordFamily.ResolveSurface(surface, scope, artifactRef, contextText)`. As of this writing there are exactly **two** callers anywhere in the codebase:

**Open Question 03**: Bug report (2026080501-bug-name-resolver-qutd.md) clearly states
 `KeywordFamily.ResolveSurface(...)` should be read-only. Why it is still not changed? 

> **Answer:** Because nothing in this entire thread — the bug report, the addendum's revision, this document's own edits — has touched a single line of Go code. Everything since the bug report is a documentation/design correction. `ResolveSurface` in `ChenWeb/server/api/ontology/keywords/keywordfamily.go` today is byte-for-byte the same function described throughout this document: it still writes a mention row, a decision-log row, and a surface-or-backlog row on every call. The read-only `names.Resolver.ResolveName` is a **proposed** replacement (addendum §2, §2.1) — not implemented, not started. Nothing described as "PROPOSED" anywhere in either document exists in the repository yet.

1. `KeywordMentionCollector.CollectFromText` (§9) — for every token it pulls out of raw document-chunk text. This is currently unwired into the pipeline, so in production today it never runs.
2. `ResolveKeywordSurface`, the `POST /kb/keyword-resolve` REST handler (§10) — whenever an external caller sends it a string.

**Neither is metric-specific, and neither runs against `extract_metrics` output today.** No doc processor — old or new, `extract_metrics` or `extract_metric_definitions` — calls this function (§14.1). The addendum (`2026080404` §2) proposes a *third* caller reaching this mechanism — through `names.Resolver`, not by adding a call inside `associate_semantics.processMetric` — which would make a metric's name into an occurrence for the first time. Until that's built, "occurrence" and "metric name" have no relationship at all in the running system.

**What each layer means, and what it actually is in code:**

- **occurrence** — a raw string as observed in one specific place, plus where it came from (≈ UMLS AUI). **No single table holds a complete occurrence record.** See the trace below for exactly what does and doesn't get written, and §17.2 K4 for why this is tracked as a defect rather than left as an implicit gap.
- **surface** — one exact, distinct string, stored verbatim, tagged with a role (`pref`/`alt`/`hidden`) and an alias type (≈ SUI). **A real, fully built entity** — `kb.keyword_surfaces` + `SurfaceStore` (§8.2), CRUD'd, unit-tested.
- **lexform** — a normalization-equivalence class; the working-mode index key (≈ LUI). A LexForm is a normalized representation of a term that removes superficial differences in spelling and formatting so that different strings with the same lexical meaning can be matched more easily. **Not an entity — a derived value**, with no dedicated table (no `lexform_id` anywhere). It is the string in a `norm_key` column, computed once by the normalizer and copied onto every row that needs to be found by it. This matches the original design intent — "the working-mode index key" already says "key," not "governed record" — so having no table is not itself a gap. What *is* a gap: `kb.keyword_unresolved.norm_key` is supposed to hold this value too but currently holds the raw surface instead (§17.2 K5).
- **concept** — a unit of meaning with a canonical label and gloss (≈ CUI). LexForm is purely lexical, whereas the Concept Unique Identifier (CUI) is semantic. **A real, fully built entity** — `kb.keyword_concepts` + `ConceptStore` (§8.1), with a genuine lifecycle. Concepts are created only through the REST API today; there is no automated "propose a new concept" path (that's reconciliation's R5, §11, unbuilt).

**Open Question 04**: Since `lexform` purely lexical, and `2026080501-bug` suggests `names.Resolver.ResolveName(...)`. Shall we adopt the recommendation? The same function can also be used to normalize `surface`. Note that `occurrence` to `surface` is many-to-one. The mapping should be purely 
lexical, too. This means we should use the same function to resolve `occurrence` to `surface`. 
Is this understanding correct?

> **Answer:** Adopt the recommendation — already done in the addendum's 2026-08-05 revision. On the mechanism: correct in spirit, with one precise distinction worth drawing out, because it explains why the code has two tiers instead of one. There are actually **two different "is this the same" checks**, and only one of them goes through the normalizer:
>
> 1. **"Is this occurrence's literal text already an existing surface?"** — tier 0, exact string comparison (`WHERE surface = $1`). No normalizer involved.
> 2. **"Does this occurrence's normalized form match an existing surface's normalized form?"** — tier 1, the normalizer's output compared against stored `norm_key`.
>
> Both checks exist because surface is deliberately *not* the normalized form — it's the verbatim string (cardinal rule 2, §4.2). If occurrence→surface collapsed straight through the normalizer, "Luminance" and "luminance" would never be distinguishable as two separately-observed spellings, which is exactly the information surface exists to preserve. So: yes, one normalizer function underlies everything downstream of an exact-match miss — but the exact-match check itself is deliberately *not* normalizer-mediated, and that's not an oversight.

**Since lexform is only a value, not a row — how does the system guarantee two surfaces are consistently recognized as "the same lexform"?** Not by lookup — by *determinism*. `KeywordNormalizer.Normalize(surface)` is a pure function: no database access, no I/O, no shared state (confirmed — there is nothing in `normalizer.go` that touches a DB or a cache). It runs the fixed ten-step pipeline (§5.1) purely on the string it's given and returns a `norm_key`. Because the function is pure, calling it twice on the same input — from anywhere, at any time — produces the same output. "Two surfaces belong to the same lexform" is therefore not a fact that gets *recorded*; it's a fact that gets *recomputed*, identically, every time either surface is normalized. `norm_key` **is** "the normalized form" by construction — it is literally what the pipeline returns, not a further transformation of it.

**Open Question 05**: The logic appears incorrect. It implies `occurrence` maps to not-normalized 
`surface` first, then `KeywordNormalizer.Normalize(surface)` normalizes `surface`. 
The correct one should be: `occurrence` -> normalize `occurrence` as the parameter -> search 
`surface`. If not found, create one. Otherwise, use it. Is this understanding correct?

> **Answer:** Close, with the same two-step correction as OQ04. Normalization *does* run immediately (`Kernel.Resolve` computes the key bundle before any lookup, unconditionally) — but the *first* search performed is against the raw, un-normalized text (tier 0), not the normalized key. Only if that misses does the search fall through to the normalized key (tier 1). So the precise sequence is: occurrence arrives → normalize it (always, upfront) → search by exact raw text first → if that misses, search by normalized key → if that also misses (through tiers 2–4 too), it's a genuine miss, goes to the backlog, no surface created → if any tier hits, check whether this exact literal string is already recorded under that concept; if not, create it. "Normalize, then search" is right about *what eventually gets searched*; it understates that an exact-text search happens first and doesn't need the normalized form at all.

This has two direct consequences worth naming:

- **Where a `norm_key` comes from initially — there is no bootstrapping step.** It doesn't need to be seeded or pre-populated; it is computed at the moment a surface row is about to be created. But there are **two different code paths that do this, only one of which does it correctly**: `ResolveSurface`'s auto-accept branch calls `KeywordNormalizer.Normalize(surface)` itself and derives `NormKey` from the result (§3's trace, step 4′) — correct, every time. `CreateKeywordSurface`, the direct `POST /kb/keyword-surfaces` REST handler a human uses to author a surface by hand, takes `NormKey` straight out of the request body and stores whatever it's given, with no call to the normalizer at all (§17.2 K3). A human-authored surface's `norm_key` is therefore only as correct as whatever the caller happened to type — nothing server-side verifies it matches what `Normalize(surface)` would have produced.
- **This determinism is also the entire risk.** If the normalizer ever had two different implementations disagreeing, or a bug that treats two inputs a human would consider "the same lexform" inconsistently, the lexform layer fractures silently — two variants that should share a `norm_key` end up with two different ones, and nothing in the data itself can reveal this, because there is no lexform row to compare against. This is not hypothetical: `AWS` and `AWS's` are exactly this failure today (§5.5 N2 — the possessive-stripping bug means they normalize to different keys), and `Kubernetes`/`kubernets` only happen to collide correctly (§5.5 N1) by an accident of the same bug, not by design. The lexform layer's correctness rests entirely on there being one normalizer implementation, applied identically everywhere a surface is written — which today is true (there is only one `KeywordNormalizer`), but is an invariant the design depends on rather than one the schema enforces.

**One more thing lexform does *not* do, worth stating because it's easy to over-read from DR23's own language: it does not unify translations or unrelated synonyms.** `norm_key` is a function of *one string's spelling/casing/morphology* — it has no notion of meaning. "Luminance," "亮度," "显示亮度," and "brightness" are four different strings in two languages; normalizing each of them produces four **different** `norm_key` values, not one. DR23's promise that these "reach one row" is real, but it happens at the **concept** layer, not the lexform layer: each of the four strings must be authored (today, by a human; eventually, by reconciliation) as its own individual `kb.keyword_surfaces` row, and it is the shared `concept_id` on those four separate rows — not a shared `norm_key` — that makes them resolve to one concept. Lexform only collapses spelling/casing/morphological variants of the *same* underlying string (`Luminance`/`luminance`/`LUMINANCE`, or `Kubernetes`/`kubernetes`); it never substitutes for the curation (human or reconciled) that connects genuinely different words to the same meaning.

**A concrete trace: exactly what one `ResolveSurface` call writes, where, in order.** This replaces a sentence in an earlier version of this document ("the raw surface exists only as a function argument for the duration of one resolve call") that was wrong — not just unclear — since it directly contradicts the surface bullet immediately above it. The corrected, complete picture, for a call `ResolveSurface(surface="kubernets", scope="_", artifactRef="art-1", contextText="cluster wont schedule")` that misses (verdict `deferred`):

| Step | What runs | Table | Columns actually written | Columns left NULL / not written |
|---|---|---|---|---|
| 1 | `MentionStore.InsertMention` — **runs on every call, any verdict** | `kb.keyword_mentions` | `artifact_ref = "art-1"`, `context_text = "cluster wont schedule"` | `chunk_ref`, `ks_id` — and there is **no column for the surface at all**; the table has none to write to (§8.4, §17.2 K4) |
| 2 | `Kernel.Resolve` — normalize, look up candidates, score, adjudicate | *(read-only, against `kb.keyword_surfaces`/`kb.keyword_surface_keys` — no write)* | — | — |
| 3 | `DecisionLogStore.Append` — **runs on every call, any verdict** | `kb.semid_decision_log` | `input = {"surface": "kubernets", "scope": "_"}`, `output = <Resolution JSON>`, `verdict = "deferred"` | no `artifact_ref`, no `context_text`, no `chunk_ref` — **and no foreign key back to the mention row step 1 just wrote**, so the two rows from the same call can never be joined |
| 4 | Verdict is `deferred` → `UnresolvedStore.UpsertUnresolved` | `kb.keyword_unresolved` | `norm_key = "kubernets"` *(bug: should be the normalized key — K5)*, `surfaces = ["kubernets"]`, `scope = "_"` | — |
| 4′ *(alternate, if the verdict had been `auto_accepted` instead)* | `SurfaceStore.CreateSurface` | `kb.keyword_surfaces` | `surface = "kubernets"`, `norm_key = <normalized>`, `concept_id = <matched>` | — |

**Open Question 06**: Line 191, what does it normalize? what/how to adjudicate? what are
parameters of `Kernel.Resolve`?

> **Answer:** Exact signature, verified against `semid/kernel.go`: `Kernel.Resolve(ctx context.Context, surface string) (Resolution, error)`. Two parameters only — `surface` is the raw string; **scope is not a parameter**, it's derived internally via `k.Family.Scope(surface)`, which is precisely K2's bug (it always returns `"_"`, discarding whatever scope the caller passed to `ResolveSurface`). What it normalizes: `k.Family.Normalizer().Normalize(surface)` — the same `KeywordNormalizer` pipeline (§5.1), producing a key bundle (`CanonicalKey = norm_key`, `AlternateKeys = [alnum, sorted, phonetic, initials]`). How it adjudicates: `Adjudicate(matches []ScoredMatch, policy AutoAcceptPolicy) Verdict` (`semid/adjudicate.go`) — given the tier-scored candidates (sorted, highest first) and the family's policy (`{Enabled: true, MinScore: 0.8, MaxCandidates: 1}` for keywords): zero matches → `deferred`; the top score tied across more candidates than `MaxCandidates` → `ambiguous`; policy disabled, or the top score below `MinScore` → `human_review`; otherwise → `auto_accepted`.
>
> **Who calls it — checked across the whole codebase, not just the keyword package:** exactly two callers exist anywhere, one per family: `KeywordFamily.ResolveSurface` (`keywordfamily.go:258`) and `TermFamily.ResolveCandidate` (`termfamily.go:129`). Nothing else calls `Kernel.Resolve`.

**Open Question 07**: Line 192, 'runs on every call': which call? what function(s) to call? 
We should clearly separate resolve-functions as read-only and, if resolve-functions
failed resolving, mutable decision-functions to make decisions. Does the new design
follow this rule? Who calls `DecisionLogStore.Append(...)`?

> **Answer:** "Every call" = every call to `KeywordFamily.ResolveSurface` (the function this whole trace is about), regardless of which verdict comes back. The exact call site: `(semid.DecisionLogStore{DB: kf.DB}).Append(ctx, semid.DecisionLogEntry{...})`, inside `ResolveSurface` itself (`keywordfamily.go`), executed unconditionally right after `Kernel.Resolve` returns and before the verdict-based switch. **`Kernel.Resolve` itself never writes anything** — confirmed by re-reading its full body: normalize, query candidates (read-only), score, adjudicate, return. All writes belong to `ResolveSurface`, one layer up.
>
> On the read/write separation rule: **yes, the corrected design follows it — that's the entire point of addendum §2.1.** `names.Resolver.ResolveName` performs zero writes, full stop. One refinement your question surfaces, worth making explicit rather than leaving implicit: the decision-log write should move to the same side of the line as the mention/surface/backlog writes — i.e., a plain `ResolveName` call should produce **no** decision-log entry either, only `ObserveName`/`ResolveAndObserve` should. The addendum's §2.1 text focused on mention/surface/backlog; the decision log deserves the same treatment for the same reason, and I've added this to the addendum's read/write section.
>
> **The design problem you're pointing at directly — `Kernel.Resolve` and `KeywordFamily.ResolveSurface` are both named around "resolving," yet they're different things, and the naming doesn't say so. This is a real defect in the current naming, not just an unclear explanation, and it's worth fixing rather than filing away.**
>
> The precise differences, side by side:
>
> | | `Kernel.Resolve(ctx, surface)` | `KeywordFamily.ResolveSurface(ctx, surface, scope, artifactRef, contextText)` |
> |---|---|---|
> | Layer | generic kernel, shared by every family | one family's wrapper around the kernel |
> | Behavior | pure — normalize, score, adjudicate, return. **No writes, anywhere, confirmed by rereading the full function body.** | calls `Kernel.Resolve` internally, then writes a mention row, a decision-log row, and a surface-or-backlog row |
> | `scope` | not a parameter — derived internally, always `"_"` (K2) | accepted as a parameter, but only assigned to the *output* struct after the kernel already ran with `"_"` — the same K2 bug, one layer further from where it actually bites |
> | Callers | `KeywordFamily.ResolveSurface`, `TermFamily.ResolveCandidate` — one per family | `KeywordMentionCollector`, the REST resolve handler |
>
> So the honest name for `Kernel.Resolve` is closer to "compute a verdict for this input, do nothing else" — and the honest name for `KeywordFamily.ResolveSurface` is closer to "resolve *and record the outcome*." Neither name says that. Worse, and this is a sharper version of your finding than "these two names look similar": **the kernel's parameter name (`surface`) is itself keyword-family vocabulary, borrowed by a mechanism that's supposed to be family-agnostic.** Checked directly: `TermFamily` — the *other* family sharing this same kernel — also calls its parameter `surface` throughout (`CandidateNodes(ctx, surface, scope string)`, `ResolveCandidate(ctx, candidateID int64, surface string)`), but `TermFamily`'s own comment has to explain that in its world "surfaces are term proposals (`kb.ontology_candidates`)" — a completely different thing from a keyword `surface` (a persisted, verbatim, role-tagged string with its own table and entity identity, §3.1.1). The same identifier means two unrelated things depending on which family you're reading, because the *generic* kernel's signature forced both families to call their input by the same name. This is the identical class of problem the bug report found in `associate_semantics.go` — domain vocabulary leaking into a layer that's supposed to be domain-agnostic — just one level lower in the stack, and not yet flagged anywhere until now.
>
> **The fix, as a decision, not a suggestion:**
>
> 1. **Rename `Kernel.Resolve`'s parameter from `surface` to `input`** (or `text`), and fix its doc comment to stop saying "runs the kernel over one surface." The kernel must not presuppose any family's identity-layer vocabulary — that's DR15's own stated principle ("a family declares only what differs... it never edits the mechanism"), and a shared parameter name that means two different things in its two current callers violates it.
> 2. **Extend the `Resolve`/`Observe` split (addendum §2.1) down to the family layer, not just the `names.Resolver` facade.** `KeywordFamily.ResolveSurface` should become two functions — a pure `ResolveSurface` (matching `Kernel.Resolve`'s actual behavior: compute, don't write) and an `ObserveSurface` (or `ResolveAndObserveSurface`) that does what today's single function does. This makes every layer of the stack follow the same naming contract: `Resolve*` never writes, *anything else* does, top (`names.Resolver`) to bottom (`Kernel`). Right now only the top of that stack is planned to follow the rule; the middle layer (the family) is where the violation actually lives in code today, and it should follow the same rule once this is built, not be grandfathered in.
>
> This is a code change, not yet made (consistent with OQ03/08 — nothing has been implemented). It belongs in the addendum's build list as its own item, and I've added it there.
>
> **Follow-up finding, from checking whether the same string could be run through both families' `Kernel.Resolve` calls for the same input:** it wouldn't be, and not for a subtle reason — a blunt one. `TermFamily.ResolveCandidate` (the only path that would run a string against the *ontology term* catalog rather than the keyword lexicon) has **zero callers anywhere in the codebase** — dead code, exactly like `ListMentions` (OQ01). So "the same surface run through both families" doesn't happen today, and isn't wired to happen under the current design either.
>
> But suppose it were wired up — a more important correction surfaces: **the two families don't even normalize the same way.** `KeywordFamily.Normalizer()` supplies the full `KeywordNormalizer` pipeline (§5.1). `TermFamily.Normalizer()` returns `Normalizer{Name: "basic", ...}` with **no custom `NormFunc`** — it falls through to the kernel's own generic default, a different implementation entirely. The same literal string can produce two different canonical keys depending on which family processes it. Combined with `CandidateNodes` querying entirely different tables (`kb.keyword_surfaces` vs. `kb.ontology_terms`/`kb.ontology_term_labels`), "the same resolution done twice" is the wrong mental model — it's two independent computations, over different data, with different normalization, that happen to share an input string and a generic code skeleton (`Kernel.Resolve`).
>
> **Whether that normalizer difference is deliberate or accidental is undecided, and it needs to be decided, not assumed either way.** There's a real argument for it being intentional — governed term content arguably shouldn't risk the aggressive collapsing (which already has a known bug, N1) that's tolerable for a fast, self-healing, ungoverned lexicon. But nothing anywhere states this as a decision; it's simply how the code happens to be. This should be settled explicitly before `aligns_to_term` is built on top of it, since that bridge is exactly the place where a keyword-side verdict and a term-side verdict need to be comparable enough to reason about together.

**So: is the raw string persisted, or not?** Both things the prior questions pointed at are true, and they were never in tension once stated precisely — the confusion was entirely mine, in how the earlier version of this section phrased it. The string **is** durably persisted, every time, in one of two places depending on the verdict (step 4 or step 4′) — and, incidentally, **always** in the decision log's `input` field (step 3), regardless of verdict. What is **not** persisted, ever, is a single row that ties the string together with *where it was seen* — step 1 records the "where" (partially) with no "what"; step 3 records the "what" with no "where"; nothing links them. That is the actual, precise shape of the gap: not "nothing is stored," but "what's stored is split across two unlinked tables, and the one table shaped to hold both (`kb.keyword_mentions`) is missing the column that would let it hold either." §8.4 and §17.2 K4 describe the same gap from the schema side; this trace is the same fact from the call-flow side.

**How the layers relate to each other, mechanically, once a surface row exists:**

- **surface → lexform** — many-to-one, computed at write time by `KeywordNormalizer.Normalize(surface)`, the function that produces `norm_key` (step 4′ above). This is cardinal rule 2 (§4.2, "store surfaces, derive keys") being exercised directly: `norm_key` is set once, from the surface, and never edited by hand — a normalizer-version bump means recomputing it, not migrating it.
- **lexform → concept** — many-to-many, but there is no join table for it; it's an emergent property of how the surface table is shaped. `kb.keyword_surfaces.concept_id` is `NOT NULL`, so every surface belongs to exactly one concept. When two surfaces share a `norm_key` but point at different `concept_id`s — a surface row `ML` under a `machine learning` concept, a separate surface row `ML` under a `millilitre` concept — that pair of rows *is* the many-to-many relationship, with nothing else modeling it. The tier-1 lookup (`SELECT s.concept_id, s.norm_key FROM kb.keyword_surfaces WHERE s.norm_key = $1 AND s.scope = $2`, §7.2) is this relationship being queried directly: one distinct `concept_id` in the result set → auto-accept; two or more tied at the top score → `ambiguous` (`Adjudicate`, §6.2). This single query *is* the entire mechanism behind D5 (ambiguity is first-class) and §4.3 (homonymy) — there is no separate disambiguation subsystem.

**How this would connect to production — the metric example, now clearly marked as an illustration, not the definition.** No doc processor reaches any of the four layers today, old or new (§14.1). If the addendum's proposed integration (`2026080404` §2, §6) is built, a metric's raw name would become an occurrence exactly the way "kubernets" does in the trace above — the consumer of `extract_metrics`' output, calling `names.Resolver.ResolveName` (not `associate_semantics.processMetric` — see the 2026-08-05 correction two paragraphs up), would be the third caller reaching `ResolveSurface`'s underlying mechanism, using the metric name as `surface`. A resolved concept would then, separately, need a human-confirmed `aligns_to_term` assertion (§14) to reach a governed `metric_definition` term — the identity DR23's comparison matrix actually keys on. The pilot domain this is meant to work on is 呼吸机/医疗器械 — ventilators and medical devices, ADR OD1, resolved 2026-07-29 — still un-authored as domain content. Nothing about the four-layer mechanism itself is metric-specific; metrics are simply the first concrete consumer this document has worked through in detail.

**Open Question 08**: the bug report clearly suggest that since the ontology subssystem 
and the Keyword module should be generic and doc processors agnostic, it should
move `associate_semantics.processMetric` out of them. Why it is still here?

> **Answer:** Two separate reasons, and both matter. First — same as OQ03 — nothing has been implemented yet; this is all still design. `processMetric` in the actual repo is unchanged. Second, and this is the more useful answer: **the addendum does not currently propose moving `processMetric`'s body out at all, and correctly so, by its own reasoning.** Re-reading the addendum's §2.3 precisely: it recommends moving `processMetric`/`processProvision`'s concrete bodies into consumer-specific adapter packages and un-registering `"metric"`/`"provision"` from the shared `init()` — but it explicitly sequences this as *follow-up*, deliberately *after* the metrics pilot, not before it (§6's closing paragraph: "neither has to be paid down before one metric name resolves correctly, and DR12's own vertical-slice framing argues for proving the pilot before generalizing further"). So "why is it still here" has a real, stated reason: proving one vertical slice works, per DR12, is judged more valuable right now than restructuring the package it happens to live in. If you think that sequencing call is wrong — that the restructuring should happen *before* wiring metrics through it, not after — that's a legitimate position to push back on, and worth deciding explicitly rather than leaving as my judgment call.
>
> I found a real bug while checking this, though: two places in this document (the paragraph just above, and §9.2 below) still described the *old, corrected-away* proposal — a metric resolving through `associate_semantics.processMetric` directly. Both are now fixed to say `names.Resolver`, matching the addendum's actual corrected design. Thank you for surfacing this — I introduced the inconsistency when I corrected the addendum and didn't propagate the fix back here.

### 3.1.2 Example: `surface` to `concept` 

```text
surface row
├── surface = "Apple"
├── norm_key = "apple"       ← lexform value
└── concept_id = "kwc_..."   ← persisted concept identity
```

`kb.keyword_surface_keys` is also persisted, but it holds alternate derived keys such 
as `alnum`, `sorted`, and `initials`; it is not a lexform table.

### 3.1.3 `surface` Resolves to `lexform`

Currently, based on this document it is computed deterministically:

```text
norm_key = KeywordNormalizer.Normalize(surface)
```

For example, ideally:

```text
"Apple"   ─┐
"apple"   ─┼── normalize → "apple"
"APPLE"   ─┘
```

“Many-to-one” means many different surface strings can produce the same `norm_key`. 
It does **not** mean a single surface has several possible lexforms. For a given 
normalizer version, one surface produces one primary `norm_key`.

During resolution, the module:

1. Normalizes the input in memory.
2. Uses the resulting `norm_key` for the tier-1 lookup.
3. Queries `kb.keyword_surfaces` for rows with that `norm_key` and scope.

The implementation is in [keywordfamily.go](/Users/cding/Workspace/ChenWeb/server/api/ontology/keywords/keywordfamily.go:80), with the tier-1 query at [keywordfamily.go](/Users/cding/Workspace/ChenWeb/server/api/ontology/keywords/keywordfamily.go:157).

**Open Question 09**: surfaces created through the direct REST authoring path currently 
accept a caller-supplied `norm_key` rather than deriving and validating it. Therefore, 
the intended surface→lexform invariant is not fully enforced today.
Please verify it.

> **Answer:** Verified, exactly as stated. `CreateKeywordSurface` (`kbhandler/keyword_handlers.go`) decodes `NormKey` straight from the request JSON and passes it unchanged into `SurfaceStore.CreateSurface`, which never calls `KeywordNormalizer.Normalize` at all (§17.2 K3). So the invariant "surface's `norm_key` always equals `Normalize(surface)`" holds only on one of the two write paths — `ResolveSurface`'s auto-accept branch, which does compute it correctly (§3.1.1's trace, step 4′) — and does not hold on the human REST-authoring path, where `norm_key` is only as correct as whatever the caller typed. Your understanding is correct without qualification.
>
> **The decision, since verification alone isn't the action requested:** the server derives `norm_key` (and the tier 2/4 alternate keys, closing K1 at the same time — both are the same class of bug) unconditionally, on every surface-creation path, with no exception for direct REST authoring. Concretely: `CreateKeywordSurface`'s payload should stop accepting `NormKey`/`NormVersion` as caller-supplied fields at all — the handler computes them from `Surface` via `KeywordNormalizer.Normalize`, same as `ResolveSurface`'s auto-accept branch already does correctly. A caller supplying a `norm_key` should either be ignored (silently) or rejected (a 400, if the field is present and doesn't match what normalization produces) — reject is better, since silently ignoring a caller-supplied field that looks like it should matter is its own source of confusion. This closes K3 for good, rather than leaving two code paths with two different levels of trust in the same invariant. Added to the addendum's build list as its own item.

### 3.1.4 How a lexform resolve to a concept

The relation is represented indirectly through `kb.keyword_surfaces`:

```text
SELECT concept_id
FROM kb.keyword_surfaces
WHERE norm_key = ? AND scope = ?
```

There is no separate lexform↔concept join table. Each surface row belongs to exactly 
one concept, but multiple surface rows with the same `norm_key` can point to different concepts.

The intended decision rule is:

```text
norm_key
   │
   ├── 0 concepts → unresolved/deferred
   ├── 1 distinct concept → auto_accepted
   └── 2+ equally valid concepts → ambiguous
```

The resolver returns ranked candidates, and the shared adjudicator returns 
`ambiguous` when multiple top candidates tie. 
See [adjudicate.go](/Users/cding/Workspace/ChenWeb/server/api/ontology/semid/adjudicate.go:23).

The intended disambiguation order is:

1. Scope, such as the knowledge store or domain.
2. Context-based disambiguation if scope is insufficient.
3. Otherwise return `ambiguous`.

However, the current implementation has important limitations:

- The passed scope is effectively ignored because `KeywordFamily.Scope()` returns `_`.
- Context-token disambiguation is deferred and not implemented.
- Consequently, homonyms in global scope normally remain `ambiguous`.
- The query does not use `SELECT DISTINCT concept_id`; duplicate matching rows for the same concept could potentially be counted as multiple tied candidates. The specification describes distinct concepts, but the current SQL does not explicitly enforce that distinction.

So the current module safely detects many ambiguous cases, but it does not yet reliably choose the contextually correct concept.

### 3.1.5 Does many-to-many mean the same lexform can have multiple meanings?

**Yes. That is exactly why the relationship is many-to-many.**

For example:

```text
surface/lexform: "apple"
    ├── concept: apple, the fruit
    └── concept: Apple Inc., the company
```

Similarly:

```text
"ML"
    ├── machine learning
    └── millilitre
```

It is also many-to-many in the other direction because one concept can have several lexforms:

```text
concept: Apple Inc.
    ├── "apple"
    ├── "apple inc"
    ├── "apple computer"
    └── "苹果公司"
```

Importantly, normalization does not determine meaning. It only collapses spelling, casing, punctuation, whitespace, and limited morphological variants. Synonyms and translations usually have different lexforms and are united only because their surface rows share the same `concept_id`.

**Open Question 10**: the proposed `names.Resolver` and metric integration are 
**not implemented yet**. The underlying keyword tables and tier-0/tier-1 mechanics exist, 
but reliable scope/context disambiguation and the `concept → governed ontology term` 
continuation remain future work.

> **Answer:** Confirmed, with one word worth sharpening. `names.Resolver` and the metric integration: 0% implemented, design-only, correct as stated. Keyword tables + tier 0/1: built and correct on the paths that work (Case A/B, §3.1's trace). Concept → governed term (`aligns_to_term`): 0% implemented — no schema, no code path — and, per the bug-report-driven correction, additionally blocked by `kb.semantic_assertions.subject_ref_kind`'s `CHECK` constraint excluding `'keyword_concept'` if that table is meant to hold it. The one word to sharpen: **scope disambiguation isn't merely "not reliable" — it doesn't exist at all.** K2 means the caller's scope has *zero* effect on matching; it isn't a partially-working feature, it's completely inert. "Reliable... remain future work" reads as if there's a working-but-imperfect version today; there isn't one yet.

### 3.2 D2. One shared resolution kernel, not a bespoke engine — ✅ **Built**

DR15 built a single canonicalization kernel — `normalize → candidates → score → adjudicate → link → merge/split → audit` — in `ChenWeb/server/api/ontology/semid/`, instantiated **per identity family**. A family declares only what differs via a `FamilyAdapter`; it never edits the mechanism. The keyword family is the **second instantiation** of this kernel (after P2's ontology-term family, `TermFamily`). This rejects both prior specs' assumption that the keyword module owns its own resolver engine. The keyword family supplies: a surface store, a node store, a normalizer profile, scoring via key bundles, scope, and an auto-accept policy — not a second copy of the mechanism.

### 3.3 D3. Postgres storage (`kb.keyword_*`) — ✅ **Built**

Storage is Postgres, in the `kb.` schema, per the ChenWeb convention. SemOS already runs `pg_trgm` and `pgvector` and needs one backup/migration story, not two storage engines. This resolves the earlier specs' SQLite-vs-Postgres disagreement in Postgres's favor.

### 3.4 D4. SKOS label roles — ✅ **Built**

Every surface carries a role: `pref` (the canonical display label), `alt` (synonyms, acronyms — user-visible), or `hidden` (misspellings — indexed and searchable but never displayed). This three-way split costs nothing to adopt and exactly matches the problem.

### 3.5 D5. Ambiguity is first-class — ✅ **Built** (kernel verdict)

When a key maps to multiple concepts and scope does not disambiguate, the result is **`ambiguous` with ranked candidates** — never a forced pick, and never a silent coin flip. Silently picking the most frequent candidate produces an error invisible to both caller and metrics.

### 3.6 D6. Store surfaces; derive keys; version the normalizer — ⚠️ **Defect** (rule not enforced)

Every normalization key is recomputable from `surface + norm_version`. A normalizer change is therefore a **re-index job, never data loss**. Bumping `norm_version` invalidates the derived-key layer; the original surfaces are always preserved.

The schema honours this; the shipped write paths do not. `POST /kb/keyword-surfaces` accepts a caller-supplied `norm_key` verbatim and never derives or validates it, and no write path populates `kb.keyword_surface_keys` at all. Keys are therefore *asserted*, not derived — see D6 defects in §17.2.

### 3.7 D7. Merges are tombstones; no transitive closure; `never_merge`; `locked` — 🚧 **Partial** (tombstones built, guardrails unenforced)

- Merges set `merged_into` and move the concept to `merged`; the row is **never deleted**, so stale ids still resolve. ✅ Built.
- Merges are **not transitive**: `A→B` and `B→C` do not imply `A→C`. Connected-component clustering is explicitly rejected (one bad edge chains two unrelated clusters together). ✅ Built by omission — nothing computes a closure.
- **`never_merge`** assertions (`kb.semid_never_merge`, shared kernel table) block specific pairs forever. ⚠️ **Storage only.** The table and `NeverMergeStore` exist from P2, but no keyword code path reads them: `ConceptStore.MergeConcept` performs no never-merge check (§12.2).
- **`locked`** surfaces are human-asserted; the reconciler may propose changes to them but never apply them. ✅ The flag and its toggle are built; ⏳ the reconciler that must honour it does not exist yet, so the guarantee is currently vacuous.

### 3.8 D8. Token-economics discipline — ⏳ **Deferred** (reconciliation not built)

Reconciliation runs the seven-stage ladder `harvest → prune → block → batch → decide → validate → apply`, with every stage before the model existing to shrink the model's job, and every stage after it existing to stop the model from corrupting the database. Only the data structures that support it are built today (§11).

### 3.9 D9. Two modes of operation, on two independent axes — ✅ **Built** (working), ⏳ **Deferred** (reconciliation)

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

### 3.10 D10. Bias toward under-merging — ✅ **Adopted as policy**

A missed alias is a self-reporting, self-healing condition — it lands in the unresolved backlog and gets fixed on the next reconciliation run. A wrong merge is invisible, permanent until someone notices, and contaminates every consumer. Every conservative threshold in the design follows from this asymmetry: **prefer under-merging everywhere**.

---

## 4. Identity model

### 4.1 The four layers

*For the full per-layer walkthrough — what each layer means, which two are real database entities and which two are only derived values, and how the transitions between them are actually implemented — see D1 in §3. This subsection is the compact schema-level summary.*

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

**This section describes the internal mechanism — the tier ladder, `KeywordFamily`, and `ResolveSurface`. It is not, going forward, the interface a consumer should call directly.** Per the 2026-08-05 correction (`2026080404`-addendum §2, driven by `doc-repo/bugs/202608/2026080501-bug-name-resolver-qutd.md`), the intended consumer-facing surface is `names.Resolver.ResolveName`/`ResolveAndObserve`, which wraps everything below without exposing its side effects or its storage-oriented parameters (`artifactRef`) directly. Read this section for how resolution actually works; read the addendum for how a consumer should reach it. Nothing below has changed as a result of that correction — it's an accurate description of what's built today, which the `names.Resolver` layer will sit in front of once it exists.

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

1. writes a mention row to `kb.keyword_mentions` (append-only) — ⚠️ **only `artifact_ref` and `context_text` are passed; `chunk_ref` and `ks_id` are left NULL** (§17.2 K4), and the table has no column at all for *which* surface the mention was for (§3 D1 has the full call-by-call trace);
2. runs `Kernel.Resolve` → verdict + scored matches (with the scope caveat in §6.1);
3. appends the decision to `kb.semid_decision_log` with `family='keyword'`, `actor='keyword_family'`, and the caller's scope — this row's `input` JSON *does* capture the surface string (unlike the mention row), but carries no `artifact_ref`/`context_text` and no key linking it back to the mention row from step 1;
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

⚠️ **This table cannot feed reconciliation in its current shape.** It has no column naming the surface or norm key the mention was for — this is a schema gap, not a missing assignment; there is nowhere in the table to put that value even if the write path were fixed. `ResolveSurface` (§7.3, §3 D1's trace) does write `artifact_ref` and `context_text`; `chunk_ref` and `ks_id` are always left NULL by the code. In practice `context_text` is *also* always empty today, because the only real caller (the mention collector, §9) always passes `""` — a caller-level gap on top of the schema-level one. Either way, a row today carries no information reconciliation can use. Either add `surface` + `norm_key` (and have `ResolveSurface` pass `chunk_ref`, `ks_id`, and real context), or retire the table and treat `kb.keyword_unresolved` as the sole evidence store. Decide before R1/R4 is built.

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

**`on` mode is what a production system would run — doesn't calling `ResolveSurface` in `on` mode already make something a consumer?** Yes, and this sharpens a distinction §9.1 didn't draw precisely enough. Once the addendum's targeted-enrichment integration is built — the `names.Resolver`-mediated call downstream of `extract_metrics`, or `extract_metric_definitions`' harvest step, reaching `KeywordFamily.ResolveSurface`'s underlying mechanism — those *are* real `on`-mode consumers, in exactly the sense meant here: something calls resolve, does something with the result, in production. That closes the "`on` mode has no consumer" gap for the *targeted* path. It does not close it for the *collector's* path: a consumer of one known field (a metric name) is not a consumer of the broad, undifferentiated mention stream the collector produces. The collector still needs something that reads the *lexicon in bulk* — retrieval expansion, a faceting view, an analytics query — not something that resolves one field it already knows about.

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

**This REST API and `names.Resolver` (`2026080404`-addendum §2) are two different consumption modes, not the same interface at two layers.** `names.Resolver` is an in-process Go interface for other Go code in the same service (`extract_metrics`' consumer, `extract_metric_definitions`, eventually others) — it has no REST wrapper proposed or needed, since those callers already run inside the same binary. This REST API remains what it is described as above: an external, admin/diagnostic surface (manual testing, tooling, a future admin UI), separate from the addendum's design entirely.

Gaps in the API surface:

- ⚠️ `POST /kb/keyword-surfaces` takes `norm_key` from the request body and stores it unmodified. Nothing derives it from `surface`, nothing checks it against the normalizer, and no derived keys are written. Cardinal rule 2 (§4.2) is unenforced at the only human-facing write path, so the tier-1 index can silently disagree with the normalizer. **Decided fix (OQ09, §3.1.1): the handler computes `norm_key`/`norm_version`/derived keys itself via `KeywordNormalizer`, and rejects a caller-supplied `norm_key` rather than silently ignoring it.**
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

### 11.4 Implementation plan: tiers 5–6 and R3–R5

This is a **design and sequencing plan, not code** — nothing in this subsection is built. It exists because "candidate-only by design" (tiers 5–6 never auto-accept, per §6.1's guardrails) makes these worth building even in a small, contained form, and because getting to that contained form surfaces one real architectural gap that isn't obvious from the stage descriptions in §11.1 alone.

**Do not start this before the prerequisites land.** Tiers 5–6 and R3 all generate candidates by querying derived keys and embeddings computed from surfaces — building them on top of K1 (no code path writes `kb.keyword_surface_keys`), N1 (the normalizer over-collapses `AIDS`/`SaaS`-style tokens), or K2 (scope is ignored in lookups) means shipping fuzzy/semantic matching over data already known to be wrong. Fix those first (§17.2's suggested order already puts them early).

**A gap this plan surfaces that no other section names: the kernel's `Score()` function cannot represent a fuzzy or embedding similarity score today, at all.** `semid/score.go`'s `Score()` is a fixed, four-way discrete function — exact key match (1.0), alternate key match (0.8), prefix match (0.5), or 0 — with no notion of a continuous similarity value. Worse: `Kernel.Resolve` filters out any candidate scoring exactly 0 *before* it reaches `Adjudicate()` (`if s > 0 { matches = append(...) }`, `semid/kernel.go`). A trigram or embedding candidate that doesn't happen to satisfy one of `Score()`'s four discrete conditions wouldn't fall through to `human_review` as a visible "candidate, needs review" outcome — it would be silently dropped, indistinguishable from `CandidateNodes` finding nothing at all. **This must be resolved as an explicit kernel change before tier 5 or 6 can work at all**, not discovered as a bug after they're built. The two candidate shapes worth weighing: (a) extend `Score()` itself to accept a continuous similarity input, capped so it can never reach a family's `MinScore`; or (b) let `NodeCandidate` carry an optional pre-computed score that bypasses `Score()` entirely, with the same cap. Neither is decided here — this is exactly the kind of kernel-level decision that should be made deliberately, once, since both existing families (`TermFamily`, `KeywordFamily`) depend on `Score()`'s current behavior being unchanged for tiers 0–4.

**Tier 5 (fuzzy: trigram + edit distance).**

- Requires the `pg_trgm` extension (`CREATE EXTENSION IF NOT EXISTS pg_trgm;` — an infrastructure change, needs the same sign-off any extension install would).
- A GIN trigram index on `kb.keyword_surfaces.norm_key`.
- A new `tier5FuzzyMatch` candidate function in `keywordfamily.go`, applying the length/digit/canonical/negation guardrails already specified and binding (§6.1) — those guardrails are design-complete; only the query and the scoring-gap resolution above are new work.
- Candidates from this tier must never reach `auto_accepted` — enforced by whichever scoring resolution above is chosen, not by anything specific to tier 5.

**Tier 6 (embedding / ANN similarity).**

- Requires the `pgvector` extension, and a new table (`kb.keyword_surface_embeddings` or similar) holding a vector column per surface.
- **Open, needs a decision before any code is written: which embedding model or provider.** Given the pilot corpus is bilingual (呼吸机/医疗器械 is predominantly Chinese, per §5.4), the model needs multilingual competence — an English-only embedding would not place "luminance" and "亮度" near each other, defeating the entire point of this tier for the case that motivates it (`2026080404`-addendum §5.2). Not specified here; a product/infra decision.
- A candidate function querying by cosine similarity (or whatever `pgvector` operator is chosen) within a scope, subject to the same scoring-gap resolution as tier 5.

**R3 (blocking) is not new infrastructure once 5–6 exist — it's the same indexes, queried the other direction:** lexical blocking reuses the tier-5 trigram index (querying backlog items against surfaces, and against each other, instead of one surface at a time); semantic blocking reuses the tier-6 embedding table the same way. Building R3 before tiers 5–6 exist would mean building the indexes twice.

**R4 (assemble) and R5 (decide) require product decisions this document cannot make unilaterally:**

- R4's prompt (batching unknowns against candidates into a compact pipe-row format, §11.1) must be written to a file under `prompts/`, named `prompt-<slug>-v1.md`, per this workspace's `ChenWeb/CLAUDE.md` — **never hardcoded in Go**, and its actual content (what instructions, what examples, how glosses get tagged `[llm-gloss, unreviewed]`) is a real design task, not a mechanical one.
- R5 needs an explicit choice of cheap-tier and strong-tier models for the escalation ladder (§11.1), and the structured-output schema for a decision record — both open.

**Sequencing, in one line:** fix §17.2 first; resolve the `Score()` gap once, deliberately, as a kernel change; build tier 5 and its guardrail tests; build tier 6 once an embedding model is chosen; build R3 reusing both tiers' indexes; write and iterate the R4 prompt as its own file before writing the code that calls it; choose R5's models last, since escalation-ladder tuning is the one part of this that benefits from having real tier-5/6 candidate volume to tune against.

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

**This is precisely the gap `candidate_matches` was left in the schema to fill, and precisely where it stays empty — though the reason is narrower than "nothing computes it."** A mechanism to populate it does exist: `TermFamily.ResolveCandidate` (`semid/termfamily.go`) runs a candidate's label through the kernel against released terms and writes the result straight into `candidate_matches` (`UPDATE kb.ontology_candidates SET candidate_matches = ...`). The precise gap is that **this function has zero callers anywhere in the codebase** (§3.1 OQ06/07) — no REST handler, no automatic hook when a candidate is created, nothing. So it's not that the computation is unbuilt; it's that nobody invokes it. Separately, and still true: `ontology_candidate_harvest.go` (which builds `extract_metric_definitions`' candidates) never touches `candidate_matches` either, and that path would need `KeywordFamily`/`names.Resolver` resolution specifically (§14.1's cross-lingual case), which `TermFamily.ResolveCandidate` — querying only released *terms*, not keyword surfaces — cannot provide on its own. Two different fixes, not one: wire a caller to `TermFamily.ResolveCandidate` for term-duplicate detection, and separately add keyword resolution to the harvest step for the cross-lingual case.

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
| **Fuzzy tiers 5–6** (trigram/vector blocking, edit-distance filtering, ANN) | requires `pg_trgm` + `pgvector` extensions, an embedding model decision, and a kernel `Score()` change that doesn't exist as a concept yet — the deterministic tiers 0–4 prove the kernel integration; §11.4 has the concrete build plan and names the `Score()` gap explicitly | P3 follow-up / P4 |
| **Reconciliation pipeline (R1–R7)** | stores and kernel exist; the batch CLI/workflow is not built. Reuses DR5/DR6/DR7 backlog-drain patterns from Track A. R3's blocking additionally depends on the `pg_trgm`/`pgvector` extensions that ship with the fuzzy tiers (also deferred), so R1–R7 inherits that infra timing — a sequencing dependency, not a hard blocker. R4/R5 additionally need a prompt file (per `ChenWeb/CLAUDE.md`) and a model choice — real design tasks, not just code (§11.4) | P3 follow-up |
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
| **K4** | `kb.keyword_mentions` has no column for the observed surface at all (schema gap, not just a missing write); `chunk_ref`/`ks_id` are always NULL and `context_text` is always empty in practice (caller passes `""`, §9); the row this writes shares no key with the `kb.semid_decision_log` row the same call also writes, so "what" and "where" can't be joined back together even from what *is* stored (§3 D1's trace) | `keywords/keywordfamily.go:253` | `kb.keyword_mentions` holds no reconcilable information; blocks R1/R4 | schema + wiring |
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

**Response (2026-08-04):** Worth considering, and it connects directly to §5.2 of the addendum (`2026080404`) — this is exactly the "concept-level unification at scale" gap that section names as unbuilt. Different resources fit different parts of the design, though, and one distinction matters more than which resource to pick: **raw Wikipedia and Wikidata are different things, and only one of them fits this module directly.**

- **Wikidata, not Wikipedia prose, is the strong fit.** Wikidata (Wikipedia's structured sister project, CC0-licensed, downloadable as a filterable dump, hostable locally with no live-API dependency) models `item → {labels in N languages, aliases, description}` — which is almost exactly this module's `concept → surfaces` shape. A Wikidata item for luminance carries an English label, a Chinese label ("亮度"), and aliases, already curated by a large community, for free. This is a far better fit than parsing Wikipedia article prose for synonym mentions, which would require its own extraction pipeline and produce much noisier candidates.
- **Two different places it could plug in, and they're not the same decision:**
  1. **Seed content (§13).** Import a filtered slice of Wikidata (e.g., items tagged as physical quantities, or medical-device-adjacent concepts) directly as pre-authored `kb.keyword_concepts`/`kb.keyword_surfaces` rows before any document is ever processed. This would convert some fraction of what would otherwise be Case C misses (`2026080404`-addendum §5.1) into Case A/B hits from day one — genuinely useful, and cheaper than anything else discussed in §11.4, since it requires no query-time infrastructure at all.
  2. **An R1 harvest source (§11.1).** A local Wikidata lookup at reconciliation time, alongside the existing Schwartz–Hearst/definitional-pattern extractors — zero LLM tokens, and *cheaper than tier 5 or 6* (no trigram index, no embedding computation), so it belongs earlier in the candidate-generation waterfall than either, not alongside them.
- **CC-CEDICT** (a small, actively-maintained, CC-BY-SA Chinese–English dictionary) is a more targeted option specifically for the EN↔ZH lexical-translation case this pilot corpus needs — narrower than Wikidata, but easier to host and query, and likely to have better coverage of common technical vocabulary than Wikidata's more encyclopedic scope.
- **A caution that applies to WordNet/thesaurus-style resources specifically, not to Wikidata/CC-CEDICT:** a thesaurus gives *synonym-strength* relationships, which are not always the same as identity — "brightness" and "luminance" are, in some photometric contexts, technically different quantities, even though they're near-synonyms in casual use. Importing a thesaurus pair as if it were an exact equivalence risks exactly the over-merge D10 exists to prevent. This is not a new problem — the ADR already establishes the discipline this needs: mapping strength is `exact | close | broad | narrow | related`, and "lexical similarity can never be recorded as equivalence" (ADR §3.14, DR13). Any dictionary/thesaurus-sourced pair should enter as an R1 **candidate** carrying an appropriate strength, gated through the same R6 validation gates as everything else — never auto-accepted just because an external resource asserts a relationship.
- **The honest limitation, for this pilot specifically:** general-purpose resources (Wikidata, CC-CEDICT, WordNet) are strong for common vocabulary and weak for narrow regulatory/technical jargon. A specific compliance metric name from an IEC 60601-series or ISO 80601-series ventilator standard is unlikely to be in Wikidata at all. **The higher-yield resource for this particular pilot domain is probably the standards themselves** — IEC 60601 and ISO 80601 series terminology sections/glossaries, if available in a machine-readable form, would very likely cover the pilot's actual vocabulary far better than any general open resource. General resources help the broad, incidental-vocabulary case (§9.1's "corpus-wide recall" job); domain standards glossaries would help the pilot's actual metric names far more directly.

None of this is built; it's a real enrichment to §11.1/§13/§11.4, not a replacement for tier 6 or reconciliation — free harvesters reduce how much reaches the expensive tiers, they don't eliminate the need for them.