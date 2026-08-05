# Keyword Canonicalization and Reconciliation — Specification

- **DocID:** `doc-2026080403`
- **Status:** Adopted — the reference for the keyword module
- **Date:** 2026-08-04, **rewritten 2026-08-05**
- **Component:** SemOS / ChenWeb — keyword lexicon, the DR15/DR16 keyword identity family
- **Supersedes:** `2026080101-spec-keyword-canonicalization-merged.md`, `2026072703-spec-…-2.md`, `2026072301-spec-….md`
- **Design authority:** ADR `2026072901`, DR15 (shared canonicalization kernel), DR16 (merged keyword design), DR23 (metric definitions and the lexicon)
- **Companion documents:**
  - `2026080404-spec-metric-name-canonicalization-addendum.md` — how a consumer reaches this module (`names.Resolver`), and the metrics pilot integration. Design only.
  - `2026080501-bug-name-resolver-qutd.md` — the review that produced the `names.Resolver` design.
  - `2026080502-bug-keyword-module-review.md` — findings F1–F8; the source of this rewrite's decisions.

**Rewrite note (2026-08-05).** The prior revision had accumulated ten inline Q&A blocks and several "this corrects an earlier version" passages, mixing design with conversation transcript. That content is removed here; its *conclusions* are folded into the sections below as plain design statements, and its *reasoning* lives in `2026080502-bug`. No verified finding was dropped. Where the earlier revision and this one conflict, this one governs.

---

## 0. Status at a glance

| | |
|---|---|
| **Built** | 6 tables, 6 CRUD stores, the keyword normalizer, `KeywordFamily` (tiers 0–4), 14 REST endpoints, a standalone mention collector, `KEYWORD_RESOLVER_MODE` gating. P3 Track B, 7 commits, 2026-08-04. |
| **Works correctly today** | Tier 0 (exact) and tier 1 (normalized) resolution against an existing surface; concept CRUD and lifecycle; the REST authoring surface. |
| **Broken** | 11 verified defects (§17.2). Highest impact: K6 (resolver open by default), N1 (normalizer destroys acronyms), K2 (scope ignored), K5 (backlog mis-keyed). |
| **Not built** | Tiers 5–6, the R1–R7 reconciliation pipeline, `aligns_to_term`, `on`-mode retrieval wiring, seed content, and the `names.Resolver` facade (`2026080404`). |
| **Never validated live** | No run against a real PostgreSQL instance with real document text (I2). Every defect below was found by reading code, not by a failing test. |

**Do not build new features on this module until §17.2's K1/K2/K3/K5 and N1 are fixed.** They silently corrupt data that a later fix cannot reconstruct.

### 0.1 Where this sits in the phase plan

P1, P2, P4 (generic runtime), and P5 are built. P3 Track A (assertions, evidence, Phase D association) is built and live-validated. **P3 Track B — this module — is built in observe mode but not live-validated**, which is why its defect list is longer than its siblings'. Nothing in §17.2 invalidates Track A or the P4/P5 runtime; the defects are contained inside `ontology/keywords` and `ontology/semid`.

### 0.2 Badge meanings

| Badge | Meaning |
|---|---|
| ✅ **Built** | code exists and does what this section says |
| 🚧 **Partial** | built with a stated limitation |
| ⚠️ **Defect** | built, verified *not* to behave as specified — see §17.2 |
| ⏳ **Deferred** | designed, deliberately not built |

A badge describes whether code exists, never whether it is correct.

---

## 1. Background and problem

### 1.1 Keywords are fragile retrieval keys

Documents refer to the same thing many ways:

```
Postgres, PostgreSQL, postgresql
HVAC, heating ventilation and air conditioning
亮度, 显示亮度, luminance, brightness
ML, machine learning, millilitre          (homonym)
K8S, Kubernetes, Kube, kubernets           (case + noise + misspelling)
```

If each form is an independent key, recall fragments and analytics count one concept as several. The cost compounds in SemOS's bilingual corpus, where one concept appears as an acronym, a full phrase, a translation, and a misspelling.

### 1.2 What the system needs

1. A **stable canonical concept** per keyword family.
2. A **growing store of known variants** attached to it.
3. A **deterministic, model-free online path** — lookups must be cheap, because query volume is high.
4. An **asynchronous, auditable, LLM-assisted path** for the long tail.
5. **Ambiguity preserved as a real result**, never a forced guess.

### 1.3 The economic thesis

**LLM cost scales with vocabulary growth, not query volume.** Every alias learned once is free thereafter. A mature deployment approaches zero LLM calls per day at millions of lookups. Everything in §11 exists to make the model's job small and safe.

---

## 2. Goals and non-goals

**Goals.** Resolve a surface to a concept with no LLM call; return variants by role; preserve ambiguity; grow the store through reconciliation; support aliases, acronyms, spellings, language variants; make every merge auditable and reversible; stay reusable across search, extraction, enrichment, faceting, analytics.

**Non-goals.** Not full business-entity resolution. The online path never calls an LLM (fuzzy/ANN tiers, when built, are suggest-only). Not a taxonomy engine — hierarchy is out of scope for v1. Not a spell-checker — misspellings become `hidden` aliases.

---

## 3. Design decisions

### D1. Four identity layers, UMLS-style — 🚧 **Partial**

```
name  →  occurrence  →  surface  →  lexform  →  concept
```

`name` is whatever raw string a producer supplies — a metric name, an entity alias, a token from prose. The machinery downstream is identical regardless of source; **nothing in it is metric-specific**.

| Layer | Storage | Where | Status |
|---|---|---|---|
| **name** | not this module's | the producer's own table (e.g. `kb.metrics.metric_name`) | — |
| **occurrence** | one table, incomplete | `kb.keyword_mentions` — has **no column for the observed string** | ⚠️ K4 |
| **surface** | real entity | `kb.keyword_surfaces` — verbatim text, role, alias type | ✅ |
| **lexform** | **not an entity** — a derived value | the `norm_key` column on surface rows | ✅ (⚠️ K5 on the backlog) |
| **concept** | real entity | `kb.keyword_concepts` — opaque id, `pref_label`, gloss, lifecycle | ✅ |

Only two of the four are database entities. Lexform is deliberately a *value*, not a row: it is an index key, not a governed record, and needs no identity of its own.

**Matching is always `name` against `kb.keyword_surfaces`, never against occurrence.** `kb.keyword_mentions` participates in no lookup; it is an audit side-effect.

### D2. One shared resolution kernel — ✅ **Built**

`normalize → candidates → score → adjudicate` lives once, in `ontology/semid/`, instantiated per identity family through a `FamilyAdapter`. The keyword family is the second instantiation, after P2's `TermFamily`.

**What legitimately differs per family, and what does not** (revised per F1/F2):

| Concern | Family-specific? |
|---|---|
| `CandidateNodes` — which tables to search | **Yes** — keyword searches `kb.keyword_surfaces`; term searches `kb.ontology_terms` |
| `AutoAcceptPolicy` — may a match auto-accept | **Yes** — ungoverned may, governed never |
| `Scope` — the identity namespace | **Yes** in principle (both broken today, §17.2 K2/K9) |
| **Normalization** | **No** — see D3 |

### D3. Normalization is shared, not per-family — ⚠️ **Defect** (two implementations exist)

**Lexical normalization depends on the language of the string, never on which family is asking.** A Chinese term label and a Chinese keyword surface require identical treatment; nothing about "being governed" changes what NFKC or case-folding should do.

The code currently violates this. Two implementations exist:

- `keywords.KeywordNormalizer` — the full ten-step pipeline (§5.1).
- `semid.Normalizer`'s built-in — `ToLower` → `TrimSpace` → collapse-whitespace, plus punctuation-stripping at version ≥ 2. **A strict subset of steps 5 and 7 of the keyword pipeline**, not a different approach.

They duplicate each other outright: `semid.collapseSpace` and `keywords.collapseWhitespace` are byte-identical logic under different names, and the `0x2E80` CJK threshold is hardcoded independently in both files. The `NormFunc` hook that lets a family override the built-in has exactly one user — `KeywordFamily` — added so it could bypass a normalizer doing a subset of its own work.

**Decision: one normalizer implementation, shared.** Delete `NormFunc` and the `semid` built-in; remove `Normalizer()` from `FamilyAdapter`; move the shared primitives into the single implementation. If profiles are needed later they key on **language and version**, never on family. This also removes the mechanism by which the fork occurred, so it cannot recur.

### D4. SKOS label roles — ✅ **Built**

Every surface carries `pref` (canonical display), `alt` (synonyms, acronyms — user-visible), or `hidden` (misspellings — searchable, never displayed).

### D5. Ambiguity is first-class — ✅ **Built**

When a key maps to multiple concepts and scope does not disambiguate, the result is `ambiguous` with ranked candidates. Silently picking the most frequent candidate produces an error invisible to caller and metrics alike.

### D6. Store surfaces; derive keys; version the normalizer — ⚠️ **Defect**

Every key is recomputable from `surface + norm_version`, so a normalizer change is a re-index, never data loss. **The schema honours this; the write paths do not** — `POST /kb/keyword-surfaces` accepts a caller-supplied `norm_key` unvalidated (K3), and nothing populates `kb.keyword_surface_keys` (K1).

**Decision:** the server derives `norm_key`, `norm_version`, and all alternate keys on every write path. A caller-supplied `norm_key` is rejected, not silently ignored.

### D7. Merges are tombstones; no transitive closure; `never_merge`; `locked` — ⚠️ **Defect**

Merges set `merged_into` and keep the row, so stale ids still resolve. Merges are never transitive — one bad edge must not chain two unrelated clusters.

**Merge is currently implemented twice, with disjoint capabilities and neither complete** (F4):

| | `semid.MergeGraph` | `ConceptStore.MergeConcept` |
|---|---|---|
| Persistence | **none** — in-memory maps | Postgres |
| Refuses `never_merge` pair | yes | **no** |
| Refuses already-merged source | yes | **no** |
| Follows `merged_into` at read time | yes | **no** |
| Production callers | **0** | the merge endpoint |

**Decision:** delete `semid.MergeGraph`; port its four guardrails into `ConceptStore.MergeConcept` and the resolve path, backed by the persisted `NeverMergeStore`.

### D8. Token-economics discipline — ⏳ **Deferred**

Reconciliation runs `harvest → prune → block → batch → decide → validate → apply`. Every stage before the model shrinks its job; every stage after it stops the model corrupting the store.

### D9. Two modes, on two independent axes — ✅ **Built** (working), ⏳ **Deferred** (reconciliation)

**Axis 1 — what work runs:**

| Mode | Trigger | LLM? | Job |
|---|---|---|---|
| **Working** | every resolve call | never | answer from the store; record what it can't answer |
| **Reconciliation** | scheduled batch | yes | drain the backlog, grow the store |

**Axis 2 — how far working mode's answers travel** (`KEYWORD_RESOLVER_MODE`):

| Setting | Resolution runs? | Side effects recorded? | Reaches retrieval? |
|---|---|---|---|
| `off` (default) | no | no | — |
| `observe` | yes | yes | **no** |
| `on` | yes | yes | yes |

- **`off`** — `CandidateNodes` returns nothing, `ResolveSurface` no-ops before touching the database. The safe do-nothing state. ⚠️ Not honoured when the env var is *unset* (K6).
- **`observe`** — the full pipeline runs and every side effect is written; only the answer is withheld from downstream consumers. This is the evaluation setting, and what P3 Track B shipped. **`observe` is a state of working mode, not a third mode.**
- **`on`** — same pipeline, gate removed. ⚠️ Not usable: no retrieval consumer exists, and the collector's `IsObserveMode()` check means flipping to `on` turns mention collection *off* (K7).

Reconciliation is orthogonal to all three settings.

### D10. Bias toward under-merging — ✅ **Policy**

A missed alias is self-reporting and self-healing — it lands in the backlog and gets fixed. A wrong merge is invisible, permanent until noticed, and contaminates every consumer. Every conservative threshold follows from this asymmetry.

---

## 4. Identity model

### 4.1 Cardinal rules (binding)

1. **`concept_id` is opaque and immutable.** The label is a mutable display attribute; the id is the identity. Renaming a concept must break nothing.
2. **Store surfaces; derive keys.** Every key is recomputable from `surface + norm_version`.
3. **Merges are tombstones, never deletes.**
4. **Everything carries provenance and confidence** — `human:<user> | rule:<id> | llm:<model>@<prompt_version> | import:<src>` — so a bad source's entire output can be revoked in one query.
5. **Human assertions are locked.** The reconciler may propose changes but never apply them.

### 4.2 How the layers relate

- **occurrence → surface** — many-to-one. A resolve call checks the raw literal string first (tier 0), then the normalized key (tier 1). Surface is deliberately *not* the normalized form: keeping the verbatim string is what lets "Luminance" and "luminance" remain distinguishable as separately-observed spellings.
- **surface → lexform** — many-to-one, computed by the normalizer at write time. Consistency comes from **determinism, not lookup**: the normalizer is a pure function, so "these two surfaces share a lexform" is recomputed identically every time rather than recorded. That determinism is also the risk — one inconsistent implementation fractures the layer silently, which is exactly what N1/N2 do today.
- **lexform → concept** — many-to-many, with **no join table**. `kb.keyword_surfaces.concept_id` is `NOT NULL`, so each surface belongs to one concept; two surfaces sharing a `norm_key` but pointing at different concepts *is* the many-to-many relation. The tier-1 query is that relation being read directly: one distinct concept → auto-accept; two or more tied → `ambiguous`. **There is no separate disambiguation subsystem** — ambiguity detection falls out of the surface table's shape.

### 4.3 What lexform does not do

`norm_key` is a function of one string's spelling, casing, and morphology. It has no notion of meaning. "Luminance," "亮度," "显示亮度," and "brightness" produce **four different `norm_key` values**. DR23's promise that these reach one row is real, but it is delivered at the **concept** layer by curation — four surface rows sharing one `concept_id` — never by normalization. Lexform collapses variants of the *same* string; it never substitutes for the curation that connects different words to one meaning.

### 4.4 Homonymy

The schema does not make `norm_key` globally unique, so `ML` → machine learning *and* millilitre is representable. Scope should disambiguate, then context. ⚠️ Neither works today: scope is ignored (K2) and context disambiguation is unbuilt, so global-scope homonyms return `ambiguous` — the safe outcome, not the designed one.

---

## 5. Normalization — ⚠️ **Defect**

The normalizer is the most dangerous component: fast, invisible, and every over-aggressive rule silently collapses distinct concepts forever. The design is conservative. **The implementation is not.**

### 5.1 The pipeline as implemented

| # | Step | Verified example | Note |
|---|---|---|---|
| 1 | Unicode NFKC | `ﬁle` → `file` | |
| 2 | Strip zero-width / BOM / LTR-RTL marks | | soft hyphen U+00AD **not** stripped |
| 3 | Dashes → ASCII `-` | `e–mail` → `e-mail` | |
| 4 | Quotes → ASCII | `“x”` → `"x"` | |
| 5 | Collapse/trim whitespace | | |
| 6 | Collapse dotted initialisms | `U.S.A.` → `usa` | uppercase `A.B.C` patterns only |
| 7 | Case-fold | | CJK unaffected |
| 8 | Drop possessive `'s` | `AWS's cloud` → `aws cloud`; **`AWS's` → `aws'`** | word-final possessive missed (N2) |
| 9 | Strip leading articles | `the cloud` → `cloud` | English, unguarded by language |
| 10 | Singularization | `indices` → `index`; **`AIDS` → `aid`**, **`SaaS` → `saa`** | reproduces the stemmer failures it was written to avoid (N1) |

### 5.2 The key bundle — 🚧 computed, never persisted

Six keys per surface: `exact`, `norm` (primary index), `alnum`, `sorted`, `phonetic`, `initials`. `norm` lives on the surface row; the other four belong in `kb.keyword_surface_keys` — **which no code path writes** (K1), so tiers 2 and 4 query an empty table. The `phonetic` key is a stub and is read by no tier at all.

### 5.3 Verified normalizer defects

**N1 — singularization runs after case-folding, so the ALLCAPS guard is absent.** Reproduced by execution: `AIDS→aid`, `SaaS→saa`, `Kubernetes→kubernete`, `Postgres→postgre`, `analysis→analysi`, `status→statu`. The design says "never a Porter/Snowball stemmer" precisely to avoid these; the implementation reproduces them. The `len > 3` floor is the only protection. **Fix:** carry the casing signal step 7 was supposed to record and refuse to singularize originally-ALLCAPS tokens.

**N2 — the possessive rule requires a trailing space.** `strings.ReplaceAll(s, "'s ", " ")` misses word-final possessives; singularization then yields `aws'`.

**N3 — the `initials` bridge cannot bridge.** Two reasons: the key is uppercased while every other key is lowercased, so it can never equal a `norm` value; and tier 4 looks up the *query's* initials, so `ML` yields `M`, not `ML`. Populating K1 alone would make tier 4 match every single-token surface starting with `m` — worse than matching nothing. **Fix:** look up the query's normalized form against lower-cased stored initials, scope- and length-gated.

**N4 — `norm_version` is stored but never filtered on.** Two normalizer versions would serve reads simultaneously. Harmless while only version 1 exists; must be fixed before the first bump.

### 5.4 CJK

CJK passes the pipeline unchanged (no case, no matching suffixes) and is retained by the `alnum` key. The *collector's* tokenizer is a separate matter — see §9.

---

## 6. The shared kernel (`semid`) — ✅ **Built**

### 6.1 The contract

A family declares what differs; the kernel owns the mechanism. Per D2/D3 the interface should carry `CandidateNodes`, `AutoAcceptPolicy`, and `FamilyName` — **not** `Normalizer()`, and not `Scope()` once scope becomes an explicit parameter (§6.2).

### 6.2 The resolve flow — ⚠️ signature defect

```
normalize(input) → key bundle
  → CandidateNodes(input, scope)   // family-provided
  → Score(bundle, candidate)       // deterministic
  → sort, then Adjudicate          // policy-provided
```

`Score` is a four-way discrete function: exact key match 1.0; candidate key ∈ surface's alternate keys 0.8; mutual prefix ≥ 3 chars 0.5; else 0. Candidates scoring 0 are dropped **before** adjudication.

`Adjudicate` maps scored matches to a verdict: no candidates → `deferred`; top score tied beyond `MaxCandidates` → `ambiguous`; policy disabled or top below `MinScore` → `human_review`; else → `auto_accepted`.

⚠️ **`Kernel.Resolve(ctx, surface)` takes one input but needs two.** The scope it actually filters on is fetched behind the caller's back via `Family.Scope()` — which is why K2 and K9 are invisible at every call site. Both families work around it by overwriting `res.Scope` *after* the search already ran with the wrong value. The parameter name `surface` is also keyword vocabulary imposed on a family-agnostic mechanism; `TermFamily` reuses it for a materially different thing (a candidate proposal, not a persisted entity).

**Decision:** `Kernel.Resolve(ctx, input string, scope string)`. Scope becomes explicit; `Family.Scope()` leaves the interface.

### 6.3 Verdicts

`auto_accepted` · `ambiguous` · `deferred` · `human_review`.

⚠️ `TermFamily` can produce only two of the four: its `AutoAcceptPolicy` leaves `MaxCandidates` at the zero value, which gates off `Adjudicate`'s tie-detection entirely, and `Enabled: false` blocks auto-accept. A five-way tie and a single clean match both return `human_review` (K10). Routing everything to a human may be correct for governed content, but it should be a stated choice, not a zero value.

### 6.4 Shared tables — ✅ **Built** (P2)

`kb.semid_decision_log` (append-only audit), `kb.semid_never_merge`, `kb.semid_snapshots` — shared across families, scoped by `family`. The keyword family appends to the decision log on every resolve.

---

## 7. Working mode — the resolution ladder

**This section describes the internal mechanism.** The intended consumer-facing interface is `names.Resolver` (`2026080404` §2), which wraps it without exposing its side effects or storage-oriented parameters.

### 7.1 The tier ladder

| Tier | Method | Score | Status |
|---|---|---|---|
| 0 | exact surface match | 1.0 | ✅ |
| 1 | `norm_key` match | 1.0 | ✅ |
| 2 | `alnum`/`sorted` key match | 0.8 | 🚧 query built, table empty (K1) |
| 3 | rewrite rules, then retry tiers 0–1 | 1.0/0.8 | ✅ |
| 4 | `initials` bridge | 0.8 | ⚠️ N3 |
| 5 | fuzzy (trigram + edit distance) | candidate-only | ⏳ |
| 6 | embedding similarity (ANN) | candidate-only | ⏳ |
| 7 | miss → `kb.keyword_unresolved` | — | ✅ |

`CandidateNodes` exits at the **first tier producing candidates**; it does not accumulate.

**Tier 2 is a data gap; tier 4 is a logic defect** — populating the keys table fixes the first, not the second. Tier 3 matches the **raw** surface against `pattern` with byte equality, so a rule `K8S → Kubernetes` does not fire for `k8s`; at most one rule fires, and the retry covers tiers 0–1 only.

### 7.2 Fuzzy guardrails (binding, for when tiers 5–6 are built)

```
len ≤ 4       → no fuzzy matching at all
5 ≤ len ≤ 8   → max edit distance 1, first character must match
len ≥ 9       → max edit distance 2, normalized similarity ≥ 0.88
```

Three absolute vetoes apply before any threshold: **digit** (strings differing in any digit never match — digits are versions and generations), **canonical** (a query that is itself an exact `pref_label` never fuzzy-matches elsewhere), **negation/affix** (`un-`/`non-`/`de-`/`anti-`/`-less` differences never match).

### 7.3 `ResolveSurface` side effects — 🚧 **Partial**

Called by the mention collector and the REST resolve handler. In order:

1. **Unconditionally** insert a `kb.keyword_mentions` row — `artifact_ref` and `context_text` only; `chunk_ref`/`ks_id` always null; **no column exists for the observed string** (K4). Errors discarded.
2. `Kernel.Resolve` — read-only.
3. **Unconditionally** append to `kb.semid_decision_log`. Captures the string (in `input`) but no artifact reference, and **shares no key with the mention row from the same call** — so "what" and "where" are stored in two tables that cannot be joined. Errors discarded.
4. On `auto_accepted`: write the surface row if this exact literal isn't already present under that concept. Derived keys not written (K1). The code's `human_review` arm is unreachable — `Kernel.Resolve` only sets `ResolvedNodeID` on `auto_accepted`.
5. On `deferred`/`ambiguous`: upsert the backlog — ⚠️ **passing the raw surface where the primary key expects `norm_key`** (K5).

⚠️ **This function conflates read and write.** No caller can ask "what does this resolve to" without also writing four rows. **Decision:** split into a pure `ResolveSurface` and an `ObserveSurface`, matching the `names.Resolver` read/write separation (`2026080404` §2.1) at every layer, not only at the facade.

### 7.4 Resolver modes — ⚠️ **Defect**

⚠️ **The default is open, not closed (K6).** `keywords.ResolverMode()` correctly defaults an unset variable to `off`, but the REST handler bypasses it and reads `os.Getenv` directly. An unset variable yields `""`, which fails every `== "off"` gate — so on a server that never set the variable, `POST /api/v1/kb/keyword-resolve` resolves and writes. This inverts the fail-safe the mode design exists to provide. One-line fix.

⚠️ **`on` silently disables collection (K7).** The collector gates on `IsObserveMode()`, true only for `observe`. Graduating `observe → on` turns mention collection off.

---

## 8. Data model — ✅ **Built** (migrations `20260803000001`–`00006`)

### 8.1 `kb.keyword_concepts`

`concept_id` TEXT PK (opaque) · `pref_label` · `gloss` · `scope` (default `'_'`) · `status` CHECK (`active|provisional|merged|deprecated`) · `merged_into` FK · `gloss_source` · timestamps. Indexes on `(scope, status)` and `(pref_label)`.

**Lifecycle:** `active ↔ provisional`, either → `merged`/`deprecated`; the latter two terminal.

⚠️ `MergeConcept` bypasses the state machine with a direct `UPDATE`: a merged or deprecated concept can be re-merged, chains and cycles are unchecked, `never_merge` is never consulted, and merging a non-existent id updates zero rows and returns success (K8).

### 8.2 `kb.keyword_surfaces`

`surface_id` TEXT PK (content-derived, `kws_` + 12 hex chars of sha256 over `concept_id|surface|label_role`) · `concept_id` FK NOT NULL · `surface` verbatim · `norm_key` ⚠️ caller-supplied on the REST path (K3) · `norm_version` · `label_role` CHECK · `alias_type` · `lang` (default `'en'`) · `scope` · `confidence` · `provenance` · `locked` · `evidence` · timestamps.

Unique on `(norm_key, concept_id, scope, label_role)`; indexes on `(norm_key, scope)` and `(concept_id)`.

⚠️ The uniqueness key omits `lang`, so the same normalized form in two languages under one concept cannot both be `pref`. Given the planned data reset, fix this in the schema rather than working around it.

### 8.3 `kb.keyword_surface_keys`

`(surface_id, key_kind)` PK · `key_value` · `norm_version`. CHECK on `key_kind ∈ {alnum, sorted, phonetic, initials}`. Lookup index `(key_kind, key_value, norm_version)`.

⚠️ **Empty in every shipped path** (K1). `UpsertSurfaceKeys` exists and is unit-tested; nothing calls it.

### 8.4 `kb.keyword_mentions` — the occurrence record

`mention_id` BIGSERIAL PK · `artifact_ref` · `chunk_ref` · `context_text` · `ks_id` · `create_time`.

⚠️ **Cannot serve its purpose as shaped** (K4). No column names the observed string — a schema gap, not a missing assignment. `chunk_ref`/`ks_id` are always null, and `context_text` is always empty because the only real caller passes `""`. **Decision:** add `surface`/`norm_key`, populate the provenance columns, add a link to the decision-log row from the same call, and **rename the table to `kb.keyword_occurrences`** to match the layer it implements. Verified cheap: nothing outside the keyword package reads it.

### 8.5 `kb.keyword_unresolved` — the backlog

`(norm_key, scope)` PK · `surfaces` JSONB (deduped, capped 10) · `contexts` JSONB · `hits` · `status` CHECK (`pending|batched|needs_human|resolved|junk|insufficient_context`) · `attempts` · `last_attempt` (negative-caching key) · `priority` · `first_seen`/`last_seen`. Work index `(status, last_seen)`.

Three deviations: ⚠️ the caller passes the **raw surface** as `norm_key` (K5), defeating the deduplication the PK exists for; 🚧 `contexts` is keep-the-last-5, not a reservoir sample; ⚠️ the 200-char cap slices **bytes**, which will split multi-byte CJK and store invalid UTF-8. The read path requires both scope and status, so there is no "all pending" query.

### 8.6 `kb.keyword_rewrite_rules`

`rule_id` PK · `pattern` (literal only, validated) · `replacement` · `scope` · `enabled` (default false) · `provenance` · timestamps.

🚧 Because matching is on the raw surface, a rule is one-string-to-one-string and cannot express the family generalization (`<name>-svc → <name> service`) that makes rule promotion the cost lever in §11.

---

## 9. Mention collection — 🚧 **Built standalone, not wired**

`KeywordMentionCollector.CollectFromText` tokenizes chunk text and resolves each unique token. Runs only in `observe`.

- **Tokenization:** splits on any non-letter/non-digit rune; keeps 2–50 runes; 59-word English stopword list.
- **Context:** ⚠️ passes `""`, so no snippet ever reaches the backlog — R1 harvesting and context disambiguation both depend on those snippets and are dead until this is fixed.
- ⚠️ **CJK is not segmented.** CJK characters are letters, so an unpunctuated Chinese run becomes one 50-rune pseudo-token. On the 呼吸机/医疗器械 corpus this fills the backlog with junk. Segment, or restrict to Latin script until segmentation exists.
- 🚧 **Single tokens only** — no multi-word surface can ever be observed, which removes the entire class the `sorted` and `initials` keys were designed for.

### 9.1 What this collector is for

Two different jobs exist, and the collector serves only one:

1. **Targeted enrichment** — a processor already knows a field is a name (a metric name, an alias list). It calls `names.Resolver` directly. **No collector involved.**
2. **Corpus-wide recall** — vocabulary that never becomes a structured field, useful to a retrieval consumer that expands queries against the lexicon. This is the collector's job.

Job 2's consumer chain is `collector → backlog → reconciliation → grown lexicon → retrieval/faceting`, and **everything after the first arrow is unbuilt**. Wiring the collector today would generate rows nothing reads. Its idle state is therefore coupled to reconciliation and retrieval, not independently arbitrary — revisit all three together.

**Metric-name canonicalization is job 1 and is not blocked by any of this.**

---

## 10. REST API — ✅ **Built** (14 endpoints under `/api/v1/kb/keyword-*`)

Handlers in `kbhandler/keyword_handlers.go`; routes in `server/api/routes.go:461–474`. Concepts (list/create/get/update/status/merge), surfaces (create/get/list-by-concept/lock), rewrite rules (create/list/toggle), and `POST /kb/keyword-resolve`.

**This API and `names.Resolver` are different consumption modes, not two layers of one interface.** `names.Resolver` is an in-process Go interface for other code in the same binary. This REST API is the external admin/diagnostic surface, and is where future frontend administration pages will attach (§17.4).

Gaps: ⚠️ `POST /kb/keyword-surfaces` accepts an unvalidated `norm_key` (K3); ⚠️ the resolve handler reads `os.Getenv` (K6); 🚧 no REST surface for `kb.keyword_surface_keys`, mentions, or the backlog; 🚧 no endpoint retracts a surface, deletes a rule, or records a `never_merge` pair.

---

## 11. Reconciliation mode — ⏳ **Deferred**

A batch job that drains `kb.keyword_unresolved` and grows the store. Schema and stores exist; the workflow does not.

```
R1 harvest    free extractors (Schwartz–Hearst parenthetical acronyms, definitional
              patterns) — zero LLM tokens
R2 prune      drop junk, dedup, frequency-floor; negative-cache anything already marked
              junk/insufficient_context by the same model@prompt_version
R3 block      lexical (pg_trgm) ∪ semantic (pgvector) blocking to k candidates — the
              biggest cost lever
R4 assemble   batch into compact pipe-row prompts; tag unreviewed LLM glosses to avoid
              self-confirmation
R5 decide     structured output, cheap-model bulk pass; escalate ambiguous/high-blast-
              radius items to a stronger model
R6 validate   deterministic gates (schema, referential, acronym plausibility, role
              consistency, never-merge, lock, scope, blast radius, confidence, digit
              veto) — reject before writing
R7 apply      transactional write through the kernel; append to the decision log; promote
              candidate rules; rebuild snapshot
```

**The reconciler, not the model, owns every write.** Backlog draining reuses the DR5/DR6/DR7 pattern from P3 Track A; of those, DR5 (bulk backfill) is built, DR6 (admin review) and DR7 (LLM adjudication) are not.

### 11.1 Prerequisite for tiers 5–6 and R3 — a kernel scoring change

`Score()` is a four-way discrete function with no way to express a continuous similarity, and `Kernel.Resolve` drops zero-scoring candidates **before** adjudication. A trigram or embedding candidate that satisfies none of the four discrete conditions would be silently discarded rather than surfacing as `human_review`. **This must be resolved as an explicit kernel change before tier 5 or 6 is written** — either extend `Score()` to accept a continuous value capped below `MinScore`, or let `NodeCandidate` carry a pre-computed capped score. Not decided here; both existing families depend on current behavior for tiers 0–4.

Tiers 5–6 additionally need `pg_trgm` and `pgvector`, and tier 6 needs a **multilingual** embedding model — an English-only model would not place "luminance" near "亮度", defeating the case that motivates the tier. R4's prompt must live in `prompts/` per `ChenWeb/CLAUDE.md`, never hardcoded.

---

## 12. Merge, split, lifecycle — 🚧 **Partial**

`MergeConcept(from, to)` tombstones: `status='merged'`, `merged_into=to`, row survives, self-merge refused, target existence verified. See D7 for the guardrails it lacks and the decision to consolidate the two implementations.

`locked` surfaces are human-asserted; the flag and its toggle are built, but with no reconciler the guarantee is currently vacuous. `never_merge` is storage-only — no keyword path consults it. `split_concept` is not built; splits are rarer and more painful than merges, which is itself the argument for D10.

---

## 13. Seeding — ⏳ **Deferred**

Sources, each recording provenance: curated lists already in KnowledgeStore (`import:prompt_seed`); aliases and acronyms already on entities, metrics, provisions, products (`import:artifact_backfill`); curated domain glossaries (`human:<curator>`).

No seed module and no backfill job exist; concepts are authored through the REST API, so the store starts empty. **External vocabulary import is the higher-leverage path** — see §20.1.

---

## 14. The bridge to governed terms — ⏳ **Deferred**

A keyword concept is an **ungoverned lexical identity**: fast, high-volume, auto-mergeable under guardrails. A governed ontology term is a **reviewed meaning** with a definition, owner, and release. They connect through an accepted `aligns_to_term` assertion — **never** by merging the keyword concept into the term space.

Nothing is built: no assertion type, no column, no producer. ⚠️ It is additionally blocked by a schema constraint: `kb.semantic_assertions.subject_ref_kind` allows only `('object_node','ontology_term','assertion','artifact','literal')` — **no `keyword_concept`** — so a keyword concept cannot be an assertion subject until that CHECK is extended.

### 14.1 Why this matters for metrics

`extract_metrics` and `extract_metric_definitions` both run in Phase B, both touch a metric's name, and **neither resolves it against anything**. There is no dependency edge between them, no shared identifier, and no join anywhere from `kb.metrics.metric_name` to `kb.ontology_terms`. Two documents asserting "luminance is 450 cd/m²" and "亮度为450cd/m²" produce two unrelated rows.

DR23 states the intended fix directly: *"A metric definition's alias set is the DR15/DR16 keyword lexicon instantiated over metric terms, aligned by `aligns_to_term`… the lexicon is not an optional side quest for this application but a prerequisite."* The concrete design is `2026080404`.

### 14.2 `kb.ontology_candidates`

The single proposal channel for all governed content. Nothing reaches `kb.ontology_terms` except through its lifecycle (`discovered → draft → in_review → approved → included_in_release`, with `rejected`/`deferred` branches), and `approved` is reachable only by human action. **This is a genuine by-design gate, not a gap** — it is why zero `metric_definition` instance-terms exist today.

Deduplication is exact-fingerprint only: "luminance", "亮度", and "显示亮度" produce three fingerprints and three separate review items with nothing linking them. The `candidate_matches` column exists for exactly that signal. `TermFamily.ResolveCandidate` computes and writes it correctly — **but has no caller** (§17.4), so it never runs. Two fixes, not one: wire a caller for term-duplicate detection, and add keyword resolution to the harvest step for the cross-lingual case.

---

## 15. Failure modes

### 15.1 Over-merging is the asymmetric risk

| | Under-merge | Over-merge |
|---|---|---|
| Symptom | cache miss, goes to the queue | silently wrong answers |
| Detection | automatic | none |
| Cost of fix | one reconciliation cycle | manual archaeology |
| Blast radius | none | every consumer trusting the canonical form |

### 15.2 Mitigations, and whether they are in force

| Failure | Mitigation | In force? |
|---|---|---|
| Canonical label churn | opaque immutable ids | ✅ |
| Normalizer drift | `norm_version` + re-index | ⚠️ stored, never filtered (N4); already drifted wrong (N1) |
| LLM self-confirmation | tag unreviewed glosses in prompts | ⏳ reconciliation only |
| Hallucinated ids | referential gate | ⏳ reconciliation only |
| Homonym collapse | scope + `ambiguous` verdict | 🚧 verdict real; scope inert (K2) |
| Queue starvation | junk filter, negative caching, priority | ⏳ columns exist, no logic |
| Multi-writer races | single-writer reconciliation | ⏳ no reconciler |
| Caller pollution | input validation at the boundary | 🚧 non-empty check only |

### 15.3 Where a human must be in the loop

Merges of two established clusters; any change to a `locked` surface; enabling a rewrite rule; any `never_merge` deletion.

---

## 16. Evaluation

**Online:** coverage/hit rate at tiers 0–4, unresolved rate, ambiguity rate, median latency.
**Reconciliation:** auto-attach precision, **false-merge rate** (hard gate), backlog burn-down, human-override rate.
**Candidate generation:** blocking recall/precision, reduction ratio.

### 16.1 Test coverage today — 🚧 thinner than the counts suggest

51 test functions pass; `go build`/`go vet`/`gofmt` clean. That is weaker evidence than it appears:

| File | Funcs | What it verifies |
|---|---|---|
| `normalizer_test.go` | 14 | individual steps. **No test asserts an acronym survives singularization** — which is why N1 shipped. |
| `concepts_store_test.go` | 11 | sqlmock CRUD — SQL shape, not semantics |
| `surfaces_store_test.go` | 6 | sqlmock CRUD |
| `keywordfamily_test.go` | 9 | name, policy constants, key mapping, and `off`/nil-DB early returns. **No test drives a tier against a database** — tiers 0–4 have zero behavioural coverage. |
| `keyword_exit_test.go` | 11 | ⚠️ **assertion-free.** Nine bodies are comments naming other tests; `TestExitCoverageComplete` asserts `len(hardcoded 9-entry map) == 9`. The file cannot fail. |

Exit criteria E4, E6, E7, E8 are unmet and the structure disguises it. **Minimum credible set before trusting this module:** per-tier query and score coverage; a normalizer table test containing `AIDS`/`SaaS`/`Kubernetes`/`AWS's`; a scope round-trip (write at `ks`, read at `ks`); and a test asserting an **unset** `KEYWORD_RESOLVER_MODE` writes nothing.

---

## 17. Status

### 17.1 Deferred — deliberately unbuilt

Fuzzy tiers 5–6 (needs extensions, an embedding model, and the §11.1 scoring decision) · the R1–R7 pipeline · `aligns_to_term` · `on`-mode retrieval wiring · collector pipeline wiring (§9.1) · context-token disambiguation · full Double Metaphone · curated seed content · multi-word and CJK-segmented collection · backlog admin surfaces · rewrite-rule auto-promotion · `merged_into` chase at resolve time · **I2 live PostgreSQL proof** — the reason every defect below was found by reading rather than by a failing test.

### 17.2 Defects — built, not as specified

| # | Defect | Where | Effect | Size |
|---|---|---|---|---|
| **K6** | resolve endpoint reads `os.Getenv`, so an **unset** var isn't `off` | `keyword_handlers.go:371` | fail-safe default is open; writes on any server that didn't set it | 1 line |
| **N1** | singularization after case-folding — no ALLCAPS guard | `normalizer.go` | `AIDS→aid`, `SaaS→saa`; every stored `norm_key` is affected | small + `norm_version` bump |
| **K2** | kernel uses `Family.Scope()` (constant `"_"`) while writes use the caller's scope | `kernel.go:65`, `keywordfamily.go:69` | ks-scoped surfaces written then unfindable; effectively single-scope | small |
| **K5** | raw surface passed where `UpsertUnresolved` expects `norm_key` | `keywordfamily.go:308` | backlog PK doesn't dedupe variants; negative caching is per-spelling | 1 line |
| **K1** | nothing writes `kb.keyword_surface_keys` | resolver + REST handler | tiers 2 and 4 match nothing | small |
| **N3** | `initials` uppercase; tier 4 looks up the *query's* initials | §5.3 | tier 4 cannot bridge; fixing K1 alone makes it match wrongly | design + small |
| **K3** | REST surface creation stores an unvalidated caller-supplied `norm_key` | `keyword_handlers.go:194` | cardinal rule 2 unenforced; tier-1 index can disagree with the normalizer | small |
| **K8** | `MergeConcept` bypasses the state machine and all guardrails | `concepts_store.go:218` | re-merge possible; `never_merge` unchecked; merging a nonexistent id "succeeds" | small |
| **K4** | occurrence table has no column for the observed string; provenance columns never populated; no link to the decision-log row | `keywordfamily.go:253` | `kb.keyword_mentions` holds nothing reconcilable; blocks R1/R4 | schema + wiring |
| **K7** | collector gates on `IsObserveMode()`, false in `on` | `keyword_mention_collector.go:43` | graduating to `on` turns collection off | 1 line |
| **N2** | possessive rule needs a trailing space | §5.3 | word-final `AWS's` → `aws'` | 1 line |
| **K9** | `TermFamily.Scope` returns `""` unconditionally while its comment claims "scopes by module"; the SQL's `($1 = '' OR module_id = $1)` then disables the filter entirely | `termfamily.go:37` | every term search runs across every module | small |
| **K10** | `TermFamily.AutoAcceptPolicy` leaves `MaxCandidates` at zero, gating off tie-detection | `termfamily.go:32` | `ambiguous` unreachable for that family | 1 line |

Lower-severity, recorded inline: byte-sliced context truncation and keep-last-5 in place of reservoir sampling (§8.5); `norm_version` never filtered (N4); `surface_id` hashed before `label_role` defaulting (§8.2); the unreachable `human_review` arm (§7.3); the dead `phonetic` key (§5.2); the `lang`-less uniqueness key (§8.2); assertion-free exit tests (§16.1).

**Fix order.** K6 first — one line, and the only defect with live blast radius. Then K2 and K5, which corrupt data a later fix cannot reconstruct. Then N1, which forces a `norm_version` bump. Then K1/N3/K3 together as one "derived keys are actually derived" change. K8 and K9/K10 before any reconciler work. K4 before R1/R4 is designed.

### 17.3 Operational consequence

With the variable **explicitly** `off`, the module is inert. **Unset**, it is inert for the collector but not for the REST endpoint (K6). In `observe`, rows are written but the backlog is mis-keyed (K5), scoped inconsistently (K2), and context-free (§9). **Treat all observe-mode data as disposable** — this aligns with the planned data reset; truncate `kb.keyword_unresolved` and any `provenance='llm:observe'` surfaces after the fixes land.

### 17.4 Dead-code register

11 of 12 audited exported functions have zero production callers. This is a consequence of building bottom-up, one table per chunk, with no consumer at any point. Each item below is classified and decided rather than deleted wholesale — some of it is genuinely needed by work that is planned but not yet started, including the **frontend administration pages that are the expected next stage after this module**.

| Item | Callers | Classification | Decision |
|---|---|---|---|
| `SurfaceKeyStore.UpsertSurfaceKeys` | 0 | **Not dead — unfinished feature.** Tiers 2/4 already query the table it fills. | **Wire** as part of K1 |
| `UnresolvedStore.ListUnresolved` | 0 | Needed by R2/R3 **and** by a backlog admin page | **Keep** — named consumer in §11 and §17.1 |
| `UnresolvedStore.UpdateUnresolvedStatus` | 0 | Needed by R7 to transition drained items | **Keep** — named consumer in §11 |
| `MentionStore.ListMentions` | 0 | Needed by R1 (context harvest) and by an "occurrences in this document" admin view | **Keep** — named consumer in §11 |
| `NeverMergeStore.Add`/`IsNeverMerge`/`List` | 0 | Required by the D7 merge-guardrail fix and R6's never-merge gate; `List` also backs an admin view | **Keep** — becomes live with K8 |
| `SnapshotStore.Record`/`Latest` | 0 | Required by snapshot activation (`2026080404` build item 8) | **Keep** — named consumer |
| `TermFamily.ResolveCandidate` | 0 | Writes `candidate_matches`, which the ontology-candidate review UI needs (§14.2) | **Keep** — needs a caller wired |
| `MentionStore.InsertMentions` (batch) | 0 | **Genuinely speculative.** It is a `for` loop calling `InsertMention` — no transaction, no multi-row insert, **zero batching benefit**. No planned consumer. | **Delete** |
| `semid.MergeGraph` (`NewMergeGraph`, `SetNeverMerge`, `IsNeverMerge`, `Merge`, `MergedInto`, `Resolve`, `Unmerge`) | 0 | **Orphaned duplicate.** In-memory, unpersisted, superseded by `ConceptStore.MergeConcept` before it had a caller (D7). | **Delete**, after porting its four guardrails |

**Rule going forward:** no store method merges without a caller in the same change, *or* a one-line entry in this register naming the consumer that will call it. The sqlmock tests are what made this accumulate invisibly — they assert SQL shape against a mock, proving nothing about reachability.

---

## 18. Implementation record

**Shipped** (P3 Track B, 2026-08-04, 7 commits on `main`): `641b73b6` concept store · `2355449a` surface + surface_keys stores · `8e709aaa` mention/unresolved/rewrite stores · `c6c4a1a3` normalizer · `5e746c96` `KeywordFamily` + `semid.Normalizer` extension · `e6b8fb55` REST handlers and routes · `b5ffb554` resolver mode, collector, exit criteria.

Package `server/api/ontology/keywords/` · 14 handlers in `kbhandler/` routed at `routes.go:461–474` · standalone collector in `doc-processing/` · 6 goose migrations.

**Verify:**

```bash
cd ChenWeb
go test ./server/api/ontology/keywords/... ./server/api/ontology/semid/...
go build ./... && go vet ./...
```

These pass and prove little (§16.1) — no test in the suite would fail if any §17.2 defect were introduced, which is why all were found by reading.

---

## 19. Build order from here

1. **K6** — one line, only live-impact defect.
2. **K2 + K5** — corrupt unreconstructable data.
3. **N1** (+N2) — forces a `norm_version` bump; every day of observe data before this must be recomputed.
4. **One normalizer** (D3/F1): delete `NormFunc` and the `semid` built-in, remove `Normalizer()` from `FamilyAdapter`, consolidate primitives. Combine with `Kernel.Resolve(ctx, input, scope)` (§6.2) — same files, same call sites, one change.
5. **K1 + N3 + K3** — one "derived keys are actually derived" change; wire `UpsertSurfaceKeys`.
6. **K8 + K9 + K10** — merge guardrails consolidated per D7; delete `MergeGraph`; explicit `MaxCandidates`.
7. **K4** — reshape the occurrence table, rename to `kb.keyword_occurrences`, link it to the decision log.
8. **Dead-code deletions** (§17.4) and the tests in §16.1.
9. Then the addendum's build list: `names.Resolver`, resource ingestion, reconciliation, `aligns_to_term`, the metrics pilot.

Steps 1–8 are contained inside `ontology/keywords` and `ontology/semid` and touch no other subsystem.

---

## 20. Open questions

### 20.1 External vocabulary resources

The system should not invent its own lexicon from scratch when curated multilingual vocabularies exist. Resolution is a long-solved problem; harvesting is cheaper than curating.

- **Wikidata**, not Wikipedia prose, is the strong fit — CC0, downloadable, locally hostable, and structurally `item → {labels per language, aliases, description}`, which is almost exactly `concept → surfaces`. Two insertion points: **seed content** (§13, converting future misses into hits before any document is processed) and **an R1 harvest source** (§11 — zero LLM tokens, and cheaper than tiers 5–6, so it belongs earlier in the waterfall than either).
- **CC-CEDICT** is narrower and more targeted for the EN↔ZH case this corpus needs.
- **UMLS** is a strong model and a plausible biomedical source, but it is **not open** — NLM licenses it individually and some constituent vocabularies add restrictions. An importer must preserve those boundaries rather than flattening every atom into unrestricted local data.
- **Caution for thesaurus-style sources:** a `related`/`broad`/`narrow` relationship must never be silently upgraded to `exact`. "Brightness" and "luminance" are near-synonyms in ordinary language and different governed quantities in photometry. ADR §3.14 (DR13) already binds this: mapping strength is `exact|close|broad|narrow|related`, and lexical similarity may never be recorded as equivalence.
- **The honest limit for this pilot:** general resources cover common vocabulary and miss narrow regulatory jargon. A ventilator metric from IEC 60601 / ISO 80601 is unlikely to be in Wikidata. **The higher-yield source for the pilot is probably those standards' own terminology sections**, if obtainable machine-readably.

### 20.2 Undecided

- **§11.1's kernel scoring change** — extend `Score()` or let candidates carry a pre-computed score. Must be settled before tier 5 or 6.
- **Embedding model for tier 6** — must be multilingual.
- **Whether manual curation covers the pilot domain.** Nobody has counted the synonym/translation clusters in 呼吸机/医疗器械. If the count is large, tier 6 plus reconciliation move from "later" to "prerequisite" (`2026080404` §5.2).

---

## 21. Documentation impact

**What changed.** The module is specified and partially implemented; 13 verified defects and a dead-code register are recorded with decisions rather than descriptions. Normalization is now stated as **shared, not per-family** (D3), reversing the earlier position that each family should hold its own profile. Merge is stated as **one implementation, not two** (D7).

**Affected.** ADR `2026072901` (DR15/DR16/DR23) is the design authority and is unchanged — this operationalizes it. `2026080404` is the consumer-side companion. `2026080502-bug` holds the reasoning behind this rewrite's decisions.

**Now stale.** `2026080101-spec` §7 is **wrong**, not merely superseded — it states the keyword family's merges go through the kernel's `MergeGraph`; they do not (D7). The Track B handoff `2026080401` and log `2026080402` record the slice as complete against exit criteria that §16.1 shows were self-certified by assertion-free tests; both should link to §17.2. The `-- +goose Up` comments in migrations `…0005` and `…0006` describe behaviour the code does not implement (K5, §8.6).

**Left undocumented.** Exact migration filenames and column names for the fixes above; the `aligns_to_term` payload shape; reconciliation prompt text (which belongs in `prompts/`, per `ChenWeb/CLAUDE.md`).
