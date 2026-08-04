# Keyword Canonicalization and Reconciliation — Specification

- **DocID:** `doc-2026080403`
- **Status:** Adopted (supersedes `doc-2026080101`, `doc-2026072703`, `doc-2026072301` as the reference to read)
- **Date:** 2026-08-04
- **Component:** SemOS / ChenWeb — keyword lexicon, the DR15/DR16 keyword identity family
- **Type:** Specification (self-contained: background, decisions, architecture, data model, implementation status)
- **Supersedes:** `2026080101-spec-keyword-canonicalization-merged.md`, `2026072703-spec-keyword-canonicalization-reconciliation-2.md`, `2026072301-spec-keyword-canonicalization-reconciliation.md`
- **Design authority:** ADR `2026072901-adr-ontology-platform-and-adaptive-pipeline.md`, DR15 (shared canonicalization kernel) and DR16 (merged keyword design)
- **Implementation record:** P3 Track B handoff `2026080401-handoff-semos-p3-trackb-keyword-lexicon.md`, implementation log `2026080402-devdoc-semos-p3-trackb-implementation-log.md`

---

## 0. How to read this document

This is the **single self-contained reference** for the keyword canonicalization module. Unlike the three documents it supersedes, it does not assume you have read anything else. It covers:

- **why** the module exists and what problem it solves (§1–§2),
- **which design decisions were made and why** (§3),
- **how the system works** — identity model, normalization, the shared resolution kernel, working mode, reconciliation mode (§4–§11),
- **exactly what is implemented today** and what is deferred (§17), so you can tell design from reality at a glance.

Every section that has been implemented marks its status with a badge:

| Badge | Meaning |
|---|---|
| ✅ **Built** | implemented and tested as of 2026-08-04 |
| 🚧 **Partial** | implemented with known limitations |
| ⏳ **Deferred** | designed, deliberately not built yet |

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

### D6. Store surfaces; derive keys; version the normalizer — ✅ **Built**

Every normalization key is recomputable from `surface + norm_version`. A normalizer change is therefore a **re-index job, never data loss**. Bumping `norm_version` invalidates the derived-key layer; the original surfaces are always preserved.

### D7. Merges are tombstones; no transitive closure; `never_merge`; `locked` — ✅ **Built**

- Merges set `merged_into` and move the concept to `merged`; the row is **never deleted**, so stale ids still resolve.
- Merges are **not transitive**: `A→B` and `B→C` do not imply `A→C`. Connected-component clustering is explicitly rejected (one bad edge chains two unrelated clusters together).
- **`never_merge`** assertions (`kb.semid_never_merge`, shared kernel table) block specific pairs forever.
- **`locked`** surfaces are human-asserted; the reconciler may propose changes to them but never apply them.

### D8. Token-economics discipline — ⏳ **Deferred** (reconciliation not built)

Reconciliation runs the seven-stage ladder `harvest → prune → block → batch → decide → validate → apply`, with every stage before the model existing to shrink the model's job, and every stage after it existing to stop the model from corrupting the database. Only the data structures that support it are built today (§11).

### D9. Two modes of operation — ✅ **Built** (working), ⏳ **Deferred** (reconciliation)

| Mode | Trigger | LLM? | Latency | Job |
|---|---|---|---|---|
| **Working mode** | every resolve call | never | µs–ms | answer from the database; record what it can't answer |
| **Reconciliation mode** | scheduled / on-demand batch | yes | minutes | drain the unresolved backlog, grow the database |

Working mode is further gated by `KEYWORD_RESOLVER_MODE` (`off` / `observe` / `on`, §8.3).

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

Note: `kb.keyword_mentions` records *where* an occurrence was seen (artifact, chunk, context, knowledge store) — it does **not** store the raw surface string. The surface text travels on the resolve call and, when a resolve misses, accumulates in `kb.keyword_unresolved.surfaces`.

### 4.2 Cardinal rules (binding)

1. **`concept_id` is opaque and immutable** — never a slug of the label. The canonical label is a mutable *display attribute*; the id is the identity. Downstream consumers key on the id, so renaming `Kubernetes` → `Kubernetes (container orchestration)` must break nothing.
2. **Store surfaces; derive keys.** Every normalization key is recomputable from `surface` + `norm_version`; a normalizer change is a pure re-index, never data loss.
3. **Merges are tombstones, never deletes.** A merged concept keeps its row with `merged_into` set.
4. **Everything carries provenance and confidence.** `human:<user> | rule:<id> | llm:<model>@<prompt_version> | import:<src>`. This is what makes it possible to revoke a bad source's entire output in one query.
5. **Human assertions are locked.** The reconciler may propose changes to them but may never apply them.

### 4.3 Homonymy

`lexform → concept` is many-to-many on purpose. `ML` maps to both `machine learning` and `millilitre`. The schema does **not** make `norm_key` globally unique — the same key may map to different concepts in different scopes — so homonyms are representable without a hack. In practice scope is the knowledge-store id (`ks_id`) or the global `'_'`, chosen by the caller; when scope does not disambiguate, the deferred context-token disambiguation (§17) would be the fallback.

---

## 5. Normalization — ✅ **Built**

The normalizer is the most dangerous component in the system: it is fast, invisible, and every over-aggressive rule silently collapses distinct concepts forever. The implemented pipeline is deliberately conservative.

### 5.1 The pipeline (implemented, in order)

| # | Step | Example | Notes |
|---|---|---|---|
| 1 | Unicode NFKC | `ﬁle` → `file` | `golang.org/x/text/unicode/norm` |
| 2 | Strip zero-width chars / BOM / LTR/RTL marks | | ZWSP, ZWNJ, ZWJ, BOM, LRM, RLM |
| 3 | Normalize dashes to ASCII `-` | `e–mail` → `e-mail` | em/en/figure/horizontal bar |
| 4 | Normalize quotes to ASCII | `“x”` → `"x"` | curly single/double |
| 5 | Collapse and trim whitespace | | runs → one space |
| 6 | Collapse dotted initialisms (before case-fold) | `U.S.A.` → `usa` | only letter-dot-letter patterns |
| 7 | Case-fold (full Unicode lowercase) | | CJK unaffected (no case) |
| 8 | Drop possessive `'s` | `AWS's` → `aws` | trailing `'s ` |
| 9 | Strip leading articles | `the cloud` → `cloud` | English `the`/`an`/`a` |
| 10 | Exception-list-aware singularization | `pods` → `pod`, `indices` → `index` | **never a Porter/Snowball stemmer** |

Singularization uses an explicit irregular-plural exception list (21 entries) plus safe suffix rules (`ies`→`y`, `ves`→`f`, `es`→`e` for `ses/zes/ches/shes/xes`, plain `s`→`∅` except `ss`). It is applied per-word to English text; CJK tokens are untouched throughout.

### 5.2 The key bundle — ✅ **Built**

Each surface produces **six deterministic keys**, materialized at write time:

| Key | Definition | Purpose |
|---|---|---|
| `exact` | verbatim surface (trimmed) | tier 0 |
| `norm` | output of the §5.1 pipeline | **primary index** — tier 1 |
| `alnum` | `norm` keeping only a-z, 0-9, CJK | tolerates punctuation — tier 2 |
| `sorted` | tokens of `norm` sorted | word-order variants — tier 2 |
| `phonetic` | **stub**: first char + first 4 consonants | tier 4 placeholder |
| `initials` | first rune of each token, uppercased | acronym↔expansion bridge — tier 4 |

`initials` is the key that makes `machine learning → ML` collide with the acronym `ML` deterministically, without fuzzy matching or a model. The phonetic key is a deterministic stub (🚧 **Partial** — a full Double Metaphone is a P3 follow-up).

Where the keys live: `exact` and `norm` are **columns on the surface row** (`surface`, `norm_key`), while the four alternate keys are **rows in `kb.keyword_surface_keys`** — which is why that table's `key_kind` CHECK admits only `alnum`, `sorted`, `phonetic`, `initials`. This split matters because of the limitation in §7.3: the resolver writes the surface row but not its alternate-key rows, so tiers 2/4 currently have no data to match against in the observe flow.

The bundle maps onto the kernel's `KeyBundle` as `CanonicalKey = norm`, `AlternateKeys = [alnum, sorted, phonetic, initials]`. This mapping is what makes the kernel's generic `Score()` produce the correct tier scores with no family-specific scoring code.

### 5.3 Versioning — ✅ **Schema built**, re-index flow ⏳ **Deferred**

Every derived key stores `norm_version`. Bumping it is a full re-index — recompute all keys from stored surfaces — never a migration and never data loss. The re-index *flow* (a re-index job + snapshot promotion) is not built; the schema supports it.

### 5.4 CJK handling — ✅ **Built**

CJK characters pass through the pipeline with no case folding, are retained by the `alnum` key (threshold `0x2E80`), and are handled rune-wise in `initials`/tokenization. This matters because the SemOS pilot corpus (呼吸机/医疗器械) is predominantly Chinese.

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

The keyword family (`ChenWeb/server/api/ontology/keywords/keywordfamily.go`) implements this: `FamilyName() = "keyword"`, a normalizer whose `NormFunc` delegates to the §5 pipeline, `AutoAcceptPolicy{Enabled: true, MinScore: 0.8, MaxCandidates: 1}`, `Scope()` → `"_"` (system scope; knowledge-store scoping via `ks_id`), and a multi-tier `CandidateNodes`.

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

Note: the 0.5 prefix score is part of the generic kernel contract but is **not reachable** in the keyword family's current tier ladder — keyword `CandidateNodes` never returns a candidate whose key would trigger it. It exists for families that do prefix matching; for keywords it is dead code today.

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
| 2 | `alnum`/`sorted` key match | 0.8 | 🚧 **Partial** |
| 3 | enabled rewrite rules, then retry tiers 0–1 | 1.0/0.8 | ✅ **Built** |
| 4 | `initials` bridge within scope | 0.8 | 🚧 **Partial** |
| 5 | fuzzy (trigram + edit distance, with guardrails) | candidate-only | ⏳ **Deferred** |
| 6 | embedding similarity (ANN) | candidate-only | ⏳ **Deferred** |
| 7 | miss → record to `kb.keyword_unresolved` | — | ✅ **Built** (via `deferred`) |

`CandidateNodes` exits at the **first tier that produces candidates** — it does not accumulate across tiers. This keeps lookups O(1) for the overwhelmingly common exact/norm hits.

**Why tiers 2 and 4 are only "Partial":** the *query* path is built (the SQL that joins `kb.keyword_surface_keys`), but the rows it reads are **not populated by the observe-mode resolver** — `ResolveSurface` writes the surface but never calls `SurfaceKeyStore.UpsertSurfaceKeys` (§7.3). Until that follow-up lands, tiers 2/4 match nothing, including the `ML` ↔ machine-learning initials collision that motivates them. Tier 3 likewise only fires if someone has authored rewrite rules through the API (none exist by default).

### 7.2 The `KeywordFamily` adapter — ✅ **Built**

`KeywordFamily` wires six stores (concept, surface, surface_keys, mention, unresolved, rewrite rule) plus a normalizer and resolver mode. `CandidateNodes` implements the tier ladder directly against Postgres (`kb.keyword_surfaces`, `kb.keyword_surface_keys`), returning `NodeCandidate`s whose key bundles are set so the generic `Score()` yields the tier's score.

### 7.3 ResolveSurface side effects (observe mode) — ✅ **Built**

`ResolveSurface(surface, scope, artifactRef, contextText)` runs the kernel and records the outcome:

1. writes a mention row to `kb.keyword_mentions` (append-only) — records artifact/chunk/context/ks provenance; the surface string itself is not stored on the mention (§4.1);
2. runs `Kernel.Resolve` → verdict + scored matches;
3. appends the decision to `kb.semid_decision_log`;
4. if `auto_accepted` (or `human_review` with a resolved node): best-effort idempotent write of the surface row to `kb.keyword_surfaces` (`label_role='alt'`, `alias_type='synonym'`, `provenance='llm:observe'`, `confidence=0.8`) if not already present;
5. if `deferred`/`ambiguous`: upsert into `kb.keyword_unresolved` (surfaces deduped and capped, hits incremented).

🚧 **Known limitation (tiers 2/4 data):** step 4 writes the surface row but **does not populate `kb.keyword_surface_keys`** via `SurfaceKeyStore.UpsertSurfaceKeys`. The alternate-key rows that power tiers 2 and 4 are therefore empty in the current observe-mode flow unless populated out-of-band — so an `ML` query today resolves only if a surface with `norm_key='ml'` exists, not via the initials bridge. The store is built and unit-tested; the resolver path just does not call it yet. This is a small, concrete follow-up, not a design change.

🚧 **Known wart (provenance label):** the observe resolver stamps `provenance='llm:observe'`. No LLM runs in observe mode — the label is a misnomer, and it also deviates from the `llm:<model>@<prompt_version>` convention of §4.2. Flagged here so it is not mistaken for a design choice.

**Worked example (observe mode, empty `surface_keys`):** a document mentions `kubernets` (a misspelling). The collector tokenizes it and calls `ResolveSurface("kubernets", ks)`.
1. a mention row is written (`artifact_ref`/`chunk_ref` set);
2. `Kernel.Resolve` normalizes → key bundle; `CandidateNodes` tries tier 0 (no exact surface row), tier 1 (no `norm_key` row), tiers 2/4 (empty keys), tier 3 (no enabled rules) → no candidates → `deferred`;
3. the decision log gains a `family='keyword'`, `verdict='deferred'` row;
4. (skipped — verdict is `deferred`, not `auto_accepted`);
5. `kb.keyword_unresolved` gets a `('kubernets', ks)` row with `surfaces=["kubernets"]`, `hits=1`.

Now suppose a `Kubernetes` concept with surface `Kubernetes` (and `norm_key='kubernetes'`) is later authored via the API. A fresh `ResolveSurface("Kubernetes", ks)` then hits **tier 1** (`norm_key` match) → `auto_accepted`, and step 4 writes the surface row if it is not already present. `kubernets` remains in the backlog until reconciliation resolves it — exactly the intended flow.

### 7.4 Resolver modes — ✅ **Built**

`KEYWORD_RESOLVER_MODE` (env var, read at startup via `sync.Once`):

| Mode | Behavior |
|---|---|
| `off` (default) | `CandidateNodes` returns nil, `ResolveSurface` no-ops. Zero production impact. |
| `observe` | resolution runs and **records**: mentions, surfaces, decision log, unresolved backlog. **No result reaches any downstream consumer.** This is measurement. |
| `on` | accepted by the env reader but **currently identical to observe** — a placeholder; the retrieval/search wiring is not built (§17). |

Two distinct "mode" axes exist and are easy to conflate: §3 D9's **working vs. reconciliation mode** describes *what runs* (online resolution vs. batch growth), while `KEYWORD_RESOLVER_MODE` gates how working-mode resolution *behaves* (`off`/`observe`/`on`). Graduation from `observe` to `on` is intended to be a config flip, not a code change; the `on`-mode consumer wiring is the missing piece.

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

**Lifecycle (ungoverned):** `active → provisional → merged → deprecated`; `provisional → active` is allowed; `merged` and `deprecated` are terminal. `MergeConcept(from, to)` sets `from.merged_into = to` and moves `from` to `merged`; self-merge is refused.

### 8.2 `kb.keyword_surfaces`

| Column | Type | Notes |
|---|---|---|
| `surface_id` | TEXT PK | content-derived: `kws_<sha256[:12] of concept_id|surface|label_role>` |
| `concept_id` | TEXT NOT NULL FK | |
| `surface` | TEXT NOT NULL | verbatim — never only a derived key |
| `norm_key` | TEXT NOT NULL | working-mode index key |
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

### 8.4 `kb.keyword_mentions` — the evidence queue

| Column | Type | Notes |
|---|---|---|
| `mention_id` | BIGSERIAL PK | |
| `artifact_ref` | TEXT | artifact/input-record reference |
| `chunk_ref` | TEXT | |
| `context_text` | TEXT | bounded snippet |
| `ks_id` | TEXT | knowledge-store scope |
| `create_time` | TIMESTAMPTZ | |

Append-only. Indexes on `(artifact_ref, chunk_ref)` and `(ks_id)`. This is the first-class evidence queue that feeds reconciliation.

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

PK `(norm_key, scope)`; work index `(status, last_seen)`. `UpsertUnresolved` merges surfaces (dedupe + cap), reservoir-samples contexts, and increments `hits`. `UpdateUnresolvedStatus` transitions status and increments `attempts` — the state machinery reconciliation will drive.

### 8.6 `kb.keyword_rewrite_rules`

| Column | Type | Notes |
|---|---|---|
| `rule_id` | TEXT PK | |
| `pattern` | TEXT NOT NULL | **constrained**: simple literal, no capture groups / backreferences / backslashes (validated in code) |
| `replacement` | TEXT NOT NULL | |
| `scope` | TEXT DEFAULT `'_'` | |
| `enabled` | BOOLEAN DEFAULT FALSE | default off; a human enables |
| `provenance` | TEXT DEFAULT `'human:'` | |
| `create_time` / `modify_time` | TIMESTAMPTZ | |

Rules are applied in **tier 3** as a pre-normalization rewrite: if the **raw surface** equals a rule's `pattern` (exact literal match, before any normalization), the surface is rewritten to `replacement` and tiers 0–1 retry with the rewritten form.

### 8.7 Why these tables, not the earlier specs' shapes

The earlier specs proposed concept/variant/variant_links and concept/alias/alias_key shapes. The merged design kept the four-layer identity (D1) and Postgres storage (D3), and **collapsed the variant/link split into a single `surfaces` table** (each surface row already carries its concept FK, role, provenance, and lock) plus a derived-keys table. The audit/guardrail tables from the second spec (`decision_log`, `never_merge`, `snapshot`) became rows in the **shared kernel tables** (§6.4), scoped by family — not a second keyword-specific set.

---

## 9. Mention collection — 🚧 **Built (standalone, not pipeline-wired)**

`KeywordMentionCollector` (`ChenWeb/server/api/doc-processing/keyword_mention_collector.go`) extracts candidate keyword mentions from document text and resolves each through the keyword family. It runs **only in observe mode** (`IsObserveMode()`).

- **Tokenization:** splits text on non-letter/digit runes; keeps tokens of 2–50 runes; supports ASCII, CJK, and mixed scripts.
- **Stopwords:** a ~50-word English stopword list is skipped (not full NLP).
- **Scope:** from the knowledge-store id (`ks_id`), else `'_'`.
- **Resolution:** each unique token is passed to `KeywordFamily.ResolveSurface`, which writes the mention, runs the kernel, and records the outcome. Errors are swallowed (best-effort — a collector failure must not fail a batch).

🚧 **Not integrated:** the collector is a standalone `CollectFromText` function. It is **not registered** as a `PostProcessIndexer` in the doc-processing pipeline. This is deliberate for observe mode (measure volume without changing production behavior), but it means mentions are not being produced from real documents yet. Until pipeline integration ships, the data model can be exercised via the REST API and seeded manually.

---

## 10. REST API — ✅ **Built** (14 endpoints under `/api/v1/kb/keyword-*`)

Handlers in `ChenWeb/server/api/kbhandler/keyword_handlers.go`; routes in `routes.go`.

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

The resolve endpoint returns the kernel `Resolution` (verdict, scored matches, resolved node id) and, when the resolver is `off`, a `resolved: false` response. Returning the verdict to the API caller is an admin/diagnostic surface — observe mode's "no downstream consumer" means no *retrieval/search* path consumes the result, not that the API hides it. Note there is currently **no REST surface for `kb.keyword_surface_keys` or the unresolved backlog** — those are store-level only today.

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

## 12. Merge, split, and identity lifecycle — ✅ **Built** (merge), ⏳ **Deferred** (split)

### 12.1 Merges

`MergeConcept(from, to)` is a tombstone: `from.status = 'merged'`, `from.merged_into = to`. The row survives, so stale ids keep resolving. Self-merge is refused. Surfaces are not physically moved; they resolve through the surviving concept.

### 12.2 Never-merge

`kb.semid_never_merge` (kernel table, `family = 'keyword'`) records unordered pairs that must never merge, even if a future reconciler pass would propose it. `NeverMergeStore.Add/IsNeverMerge/List` are built.

### 12.3 Locked surfaces

A `locked` surface is human-asserted; the reconciler may propose changes but never apply them. The lock is toggled via `PUT /kb/keyword-surfaces/:surface_id/lock`.

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

| Failure | Mitigation |
|---|---|
| Canonical label churn | opaque immutable ids; labels are display attributes |
| Normalizer drift | `norm_version` + full re-index; never mutate stored surfaces |
| LLM self-confirmation | tag unreviewed LLM glosses in prompts (reconciliation design) |
| Hallucinated concept ids | referential gate (reconciliation design) |
| Homonym collapse | scope-qualified uniqueness; `ambiguous` as a real verdict |
| Queue starvation | junk filter + negative caching + priority (reconciliation design) |
| Multi-writer races | single-writer reconciliation |
| Caller pollution | input validation at the API boundary |

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

### 16.4 Test coverage today

The keyword package ships `keyword_exit_test.go` (9 exit-criteria test pointers) plus sqlmock tests for the stores, normalizer tests (12), and keyword-family tests (8). The P3 Track B handoff records `go build ./...`, `go vet`, `gofmt -l`, and the keyword + semid test suites as clean.

---

## 17. Deferred boundary — exact, as of 2026-08-04

Everything below is deliberately deferred. None of it is a hard blocker; it is the sequenced-slice strategy that ships the `observe` contract first and extends later.

| Item | Why deferred | Where it lands |
|---|---|---|
| **Fuzzy tiers 5–6** (trigram/vector blocking, edit-distance filtering, ANN) | requires `pg_trgm` + `pgvector` extensions and significant candidate-scoring code; the deterministic tiers 0–4 prove the kernel integration | P3 follow-up / P4 |
| **Reconciliation pipeline (R1–R7)** | stores and kernel exist; the batch CLI/workflow is not built. Reuses DR5/DR6/DR7 backlog-drain patterns from Track A. R3's blocking additionally depends on the `pg_trgm`/`pgvector` extensions that ship with the fuzzy tiers (also deferred), so R1–R7 inherits that infra timing — a sequencing dependency, not a hard blocker | P3 follow-up |
| **`aligns_to_term` bridge** | no `AssociationResolver` for keywords exists | P4+ |
| **`on` mode** (wiring into retrieval/search payloads) | no downstream consumer exists yet; observe mode measures volume first | P4+ |
| **Mention collector pipeline wiring** | collector exists standalone; observe mode means not changing production behavior | P3 follow-up |
| **Context-token disambiguation** (IDF-weighted overlap for homonyms) | the collector currently passes empty context | later |
| **Full Double Metaphone phonetic key** | current `phonetic` key is a deterministic stub; a real implementation needs a dependency | P3 follow-up |
| **Curated seed content / artifact backfill** | content authoring + a seed module, not code | manual / follow-up |
| **`surface_keys` auto-population in `ResolveSurface`** | resolver writes the surface row but not its derived alternate keys yet | small follow-up |
| **Batch adjudication UI / unresolved-backlog admin** | admin surfaces not built | P3 follow-up |
| **Rewrite-rule auto-promotion** | rules authored manually; no promotion from validated decisions | P3 follow-up |
| **I2 live PostgreSQL proof** | `chenweb_test` was not rebuilt with the new migrations; no live resolution exercised against real text | validation gap |

**Operational consequence:** with `KEYWORD_RESOLVER_MODE=off` (default), the module is inert. With `observe`, mentions, surfaces, decision-log rows, and the unresolved backlog are written — but `kb.keyword_unresolved` accumulates indefinitely, because nothing drains it until R1–R7 ships.

---

## 18. Implementation record and how to verify

### 18.1 What shipped (P3 Track B, 2026-08-04, 7 commits on `main`)

- Package `ChenWeb/server/api/ontology/keywords/` — normalizer, 6 stores, `KeywordFamily`, mode reader, tests.
- `semid.Normalizer.NormFunc` extension (backward-compatible; `TermFamily` unchanged).
- 14 REST handlers in `kbhandler/keyword_handlers.go` + routes.
- Standalone collector `ChenWeb/server/api/doc-processing/keyword_mention_collector.go`.
- 6 goose migrations `20260803000001`–`00006`.

### 18.2 How to verify

```bash
cd ChenWeb
go test ./server/api/ontology/keywords/... ./server/api/ontology/semid/...
go build ./... && go vet ./...
```

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

**What knowledge changed?** The keyword canonicalization module is now fully specified and partially implemented (observe mode). This document is the single self-contained reference; the three prior keyword specs are superseded.

**Which docs/specs/ADRs/tests are affected?** ADR `2026072901` (DR15/DR16) is the design authority; the P3 Track B handoff and implementation log are the implementation record; this document supersedes `2026080101`, `2026072703`, and `2026072301` as the reference to read.

**Which docs are now stale?** The three superseded keyword specs remain on disk as historical inputs but are no longer authoritative. Any future ad hoc keyword-alias logic should be folded into this design.

**What was intentionally left undocumented?** Exact reconciliation prompt text, exact Go package/API signatures beyond those shipped, and the mention collector's precise hook point in the doc-processing pipeline — the first is deferred with the reconciliation build, the last two are implementation decisions, not design decisions.
