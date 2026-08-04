# Keyword Alias Resolution Module — Design

**Status:** proposal · **Version:** 0.1

## Important Note
This document is superseded by `2026080403-spec-keyword-canonicalization-and-reconciliation.md`.
It exists for archiving only.

---

## 1. Problem

Given an arbitrary keyword surface form (`k8s`, `K8S`, `kubernetes`, `Kube`, `kubernets`), return:

- its **canonical form** (`Kubernetes`),
- **all known variants**, and
- a **confidence + provenance** for the answer.

The module owns a persistent database of consolidated keywords and runs in two modes:

| Mode | Trigger | LLM? | Latency budget | Job |
|---|---|---|---|---|
| **Working** | every `resolve()` call | never | µs–ms | answer from the database; log what it can't answer |
| **Reconciliation** | scheduled / on-demand batch | yes | minutes | drain the unresolved backlog, grow the database |

The economic thesis: **LLM cost should scale with vocabulary growth, not with query volume.** Every alias learned once is free forever after. A mature deployment should approach zero LLM calls per day even at millions of lookups.

### Non-goals

- Not a general entity linker over free text (no NER, no mention detection). Input is an already-extracted keyword.
- Not a taxonomy engine. Hierarchy (`broader`/`narrower`) is out of scope for v1 — but the schema leaves room, because the "is this a synonym or a child?" question *will* come up (§10.4).
- Not a spell-checker. Misspellings are absorbed as hidden aliases, not corrected generatively.

---

## 2. Prior art worth stealing from

This problem has been solved repeatedly in terminology management and record linkage. Four sources are directly load-bearing for this design:

**UMLS Metathesaurus (NLM).** The canonical reference for concept/string layering. It separates four identifier levels: `AUI` (atom — one occurrence of a string in one source), `SUI` (string — one exact distinct string; any variation in case, character set, or punctuation yields a new SUI), `LUI` (term — the class of all lexical variants of a string, i.e. `Eye`/`eye`/`eyes` = one LUI), and `CUI` (concept — the set of all synonymous terms, so `Atrial Fibrillation` and `Auricular Fibrillation` share a CUI). The critical asymmetry: each SUI/AUI maps to exactly one LUI, but an SUI or LUI **can map to multiple CUIs** — that's how homonymy (`Cold`) is represented. §3 adapts this directly.
→ https://www.ncbi.nlm.nih.gov/books/NBK9684/

**SKOS (W3C).** Gives the vocabulary for label roles: `skos:prefLabel` (one authoritative label per language per concept), `skos:altLabel` (synonyms, abbreviations, acronyms — user-visible), `skos:hiddenLabel` (misspellings and typos — indexed and searchable but never displayed). This three-way split is exactly right for our problem and costs nothing to adopt.
→ https://www.w3.org/TR/skos-reference/

**Schwartz–Hearst (PSB 2003).** A rule-based algorithm for extracting `short form / long form` pairs from text using the parenthetical pattern — "the emergency room (ER)". Reported ~96% precision / 82% recall on a standard collection. Key matching rule: every character of the short form must appear in order in the long form, and the *first* character of the short form must match the first character of the first word of the long form. This is free acronym harvesting with no model at all, and it also doubles as a cheap validator for LLM output (§7.6).
→ https://psb.stanford.edu/psb-online/proceedings/psb03/schwartz.pdf

**Blocking / batching literature in LLM entity resolution.** Two findings shape §7 and §8:
- Blocking (cheap similarity-based candidate narrowing before expensive matching) reduces the problem from O(n·m) to O(n·k) with k ≪ m. It is the single largest cost lever. Caveat from the literature: one-off blocking imposes a **recall ceiling** — true matches separated during blocking are permanently lost, because the downstream LLM never sees them.
- Batch prompting (BatchER) and in-context *clustering* formulations amortize instruction tokens across many decisions; clustering records rather than comparing pairs has been reported to cut API calls by up to ~5× at comparable cost. Pairwise prompting is the expensive antipattern.

---

## 3. Data model

### 3.1 Identity layers

Four layers, adapted from UMLS. Collapsing layers is tempting and is the main source of pain later, so be deliberate about which ones you keep.

```
occurrence   raw surface as observed, + where it came from   (≈ AUI)  [optional in v1]
   ↓
surface      one exact distinct string                       (≈ SUI)
   ↓
lexform      normalization-equivalence class                 (≈ LUI)  ← the working-mode index key
   ↓
concept      unit of meaning: canonical label + gloss        (≈ CUI)
```

- `surface → lexform` is **many-to-one and computed** (by the normalizer, §4).
- `lexform → concept` is **many-to-many** — this is where homonyms live (`ML` → machine learning *or* millilitre). It is disambiguated by *scope*, and failing that, by *context*.
- The `lexform` layer is the one that earns its keep. It is what makes deterministic O(1) lookup possible, and it is the layer that becomes invalid when you change the normalizer.

### 3.2 Cardinal rules

1. **`concept_id` is opaque and immutable.** Never a slug of the label. The canonical label is a mutable *display attribute*; the id is the identity. Downstream consumers key on the id, so renaming `Kubernetes` → `Kubernetes (container orchestration)` must not break anything.
2. **Store surfaces; derive keys.** Every normalization key is recomputable from `surface` + `normalizer_version`. This makes a normalizer change a pure re-index job rather than data loss.
3. **Merges are tombstones, never deletes.** A merged concept keeps its row with `merged_into` set, so stale ids in downstream systems still resolve.
4. **Everything carries provenance and confidence.** `human` / `rule:<id>` / `llm:<model>@<prompt_version>` / `import:<source>`. This is what makes it possible to revoke a bad model's entire output in one query.
5. **Human assertions are locked.** The reconciler may propose changes to them but may never apply them.

### 3.3 Schema

Portable SQL; notes below for SQLite vs Postgres.

```sql
-- ─────────────────────────────────────────── concepts

CREATE TABLE concept (
    concept_id     TEXT PRIMARY KEY,          -- opaque ULID, e.g. 'c_01HQ8F...'
    pref_label     TEXT NOT NULL,             -- display form; mutable
    gloss          TEXT,                      -- 1-2 sentences; used for disambiguation AND as LLM context
    scope          TEXT NOT NULL DEFAULT '_', -- namespace: 'infra', 'finance', '_' = global
    status         TEXT NOT NULL              -- active | provisional | merged | deprecated
                   CHECK (status IN ('active','provisional','merged','deprecated')),
    merged_into    TEXT REFERENCES concept(concept_id),
    gloss_source   TEXT NOT NULL DEFAULT 'none',  -- human | llm | import | none
    created_at     INTEGER NOT NULL,
    updated_at     INTEGER NOT NULL
);
CREATE INDEX idx_concept_scope ON concept(scope, status);

-- ─────────────────────────────────────────── aliases (the working-mode index)

CREATE TABLE alias (
    alias_id       TEXT PRIMARY KEY,
    concept_id     TEXT NOT NULL REFERENCES concept(concept_id),
    surface        TEXT NOT NULL,             -- as written, preserved verbatim
    norm_key       TEXT NOT NULL,             -- normalizer output (k_norm)
    norm_version   INTEGER NOT NULL,
    label_role     TEXT NOT NULL              -- pref | alt | hidden      (SKOS)
                   CHECK (label_role IN ('pref','alt','hidden')),
    alias_type     TEXT NOT NULL,             -- see enum below
    lang           TEXT NOT NULL DEFAULT 'en',
    scope          TEXT NOT NULL DEFAULT '_',
    confidence     REAL NOT NULL,
    provenance     TEXT NOT NULL,             -- human:<user> | rule:<id> | llm:<model>@<pv> | import:<src>
    locked         INTEGER NOT NULL DEFAULT 0,-- 1 = human-asserted, reconciler may not touch
    evidence       TEXT,                      -- snippet / doc ref that justified this
    origin_concept TEXT,                      -- pre-merge concept_id, needed to undo merges
    created_at     INTEGER NOT NULL
);

-- NOT globally unique: the same key may map to different concepts in different scopes.
CREATE UNIQUE INDEX ux_alias_key ON alias(norm_key, scope, lang, norm_version);
CREATE INDEX idx_alias_concept   ON alias(concept_id);
CREATE INDEX idx_alias_surface   ON alias(surface);

-- alias_type enum:
--   expansion | acronym | initialism | abbreviation | synonym | near_synonym
--   | misspelling | plural | inflection | translation | legacy | brand | code
```

Note that `alias_type` is not decoration. It drives validation (§7.6): an `acronym` alias can be mechanically checked against its target's `pref_label`, a `misspelling` must be `label_role='hidden'`, and a `translation` must differ in `lang`.

```sql
-- ─────────────────────────────────────────── alternate keys (blocking / fallback tiers)

CREATE TABLE alias_key (
    alias_id       TEXT NOT NULL REFERENCES alias(alias_id) ON DELETE CASCADE,
    key_kind       TEXT NOT NULL,             -- alnum | sorted | phonetic | initials
    key_value      TEXT NOT NULL,
    norm_version   INTEGER NOT NULL,
    PRIMARY KEY (alias_id, key_kind)
);
CREATE INDEX idx_alias_key_lookup ON alias_key(key_kind, key_value);

-- ─────────────────────────────────────────── the unresolved backlog

CREATE TABLE unresolved (
    norm_key       TEXT NOT NULL,
    scope          TEXT NOT NULL DEFAULT '_',
    surfaces       TEXT NOT NULL,             -- JSON: distinct raw forms seen, capped
    contexts       TEXT,                      -- JSON: reservoir sample of ≤5 snippets, ≤200 chars each
    hits           INTEGER NOT NULL DEFAULT 1,
    first_seen     INTEGER NOT NULL,
    last_seen      INTEGER NOT NULL,
    status         TEXT NOT NULL DEFAULT 'pending',
                   -- pending | batched | needs_human | resolved | junk | insufficient_context
    attempts       INTEGER NOT NULL DEFAULT 0,
    last_attempt   TEXT,                      -- '<model>@<prompt_version>' — enables negative caching
    priority       REAL NOT NULL DEFAULT 0,
    PRIMARY KEY (norm_key, scope)
);
CREATE INDEX idx_unresolved_work ON unresolved(status, priority DESC);

-- ─────────────────────────────────────────── guardrails & audit

CREATE TABLE never_merge (            -- negative assertions; block the reconciler
    concept_a TEXT NOT NULL, concept_b TEXT NOT NULL,
    reason TEXT NOT NULL, actor TEXT NOT NULL, created_at INTEGER NOT NULL,
    PRIMARY KEY (concept_a, concept_b)
);

CREATE TABLE rewrite_rule (           -- promoted patterns; tier-3 of the working ladder
    rule_id TEXT PRIMARY KEY,
    pattern TEXT NOT NULL,            -- constrained syntax, NOT arbitrary regex from an LLM
    replacement TEXT NOT NULL,
    scope TEXT NOT NULL DEFAULT '_',
    enabled INTEGER NOT NULL DEFAULT 0,   -- default OFF: rules require human enablement
    provenance TEXT NOT NULL, created_at INTEGER NOT NULL
);

CREATE TABLE decision_log (           -- full audit trail of every reconciliation decision
    decision_id TEXT PRIMARY KEY,
    batch_id TEXT NOT NULL,
    input_json TEXT NOT NULL,         -- exactly what was sent
    output_json TEXT NOT NULL,        -- exactly what came back
    model TEXT NOT NULL, prompt_version TEXT NOT NULL,
    verdict TEXT NOT NULL,            -- applied | rejected:<gate> | queued_for_human
    reviewer TEXT, reviewed_at INTEGER,
    input_tokens INTEGER, output_tokens INTEGER,
    created_at INTEGER NOT NULL
);

CREATE TABLE snapshot (               -- immutable published states of the DB
    snapshot_id TEXT PRIMARY KEY,
    norm_version INTEGER NOT NULL,
    concept_count INTEGER, alias_count INTEGER,
    created_at INTEGER NOT NULL, promoted_at INTEGER
);
```

**Storage choice.**
- **SQLite** for an embedded module / single writer. FTS5 with the `trigram` tokenizer covers lexical blocking; a snapshot is a file copy; there's nothing to operate. Recommended default.
- **Postgres** if multiple services write. `pg_trgm` with a GIN index gives indexed trigram similarity, and `pgvector` gives ANN — you can run lexical and semantic blocking in one hybrid query. Caveat: **trigram indexes need ≥3 characters to be effective**, which is precisely the length range where acronyms live. Short keys must be served by the exact-key path, never by trigrams.

---

## 4. Normalization

The normalizer is the most dangerous component in the system. It is fast, invisible, and every over-aggressive rule silently collapses distinct concepts forever.

### 4.1 The pipeline

Applied in order. Steps 1–7 are safe; 8–10 are policy decisions to make explicitly.

| # | Step | Example | Risk |
|---|---|---|---|
| 1 | Unicode NFKC | `ﬁle` → `file` | none |
| 2 | Strip zero-width, soft hyphen, BOM | | none |
| 3 | Normalize dashes/quotes to ASCII | `e–mail` → `e-mail` | none |
| 4 | Collapse and trim whitespace | | none |
| 5 | **Record a casing signal, then case-fold** | `AWS` → shape=`ALLCAPS`, key=`aws` | none if the signal is kept |
| 6 | Collapse dotted initialisms | `U.S.A.` → `usa` | apply only to `(\w\.){2,}` |
| 7 | Drop possessive `'s` | `AWS's` → `aws` | none |
| 8 | Strip leading articles | `the cloud` → `cloud` | mild |
| 9 | Singularize via **explicit exception-aware rules** | `pods` → `pod` | **high** |
| 10 | Sorted-token key | `red hat` → `hat red` | **high** — separate key only |

**Step 5 matters more than it looks.** Case is the strongest free signal for "this is an acronym." Fold it for the key, but keep `shape ∈ {ALLCAPS, TitleCase, lower, Mixed}` on the record — the reconciler uses it to type aliases without asking a model.

**Step 9 is where systems break.** Never use a Porter/Snowball stemmer. It maps `AIDS`→`aid`, `business`→`busi`, `SaaS`→`saa`. Use a lemmatizer with a hard exception list, and **never singularize an ALLCAPS token**.

### 4.2 Emit a key bundle, not one key

```python
Keys = {
  "exact":    s,                       # verbatim
  "norm":     norm(s),                 # steps 1-9 → primary index key
  "alnum":    re.sub(r"[^a-z0-9]", "", norm(s)),   # e-mail / email / Email
  "sorted":   " ".join(sorted(norm(s).split())),  # word-order variants
  "phonetic": dmetaphone(norm(s)) if single_token and len >= 5 else None,
  "initials": "".join(t[0] for t in norm(s).split()) if n_tokens >= 2 else None,
}
```

`initials` is the acronym↔expansion bridge: `machine learning` → `ml`, which collides with the alias `ml` at tier 4 without any fuzzy matching or model call.

### 4.3 Versioning

Every derived key stores `norm_version`. Bumping it is a **full re-index** — recompute all keys from `alias.surface`, write to a new snapshot, run the eval gate (§11), then promote. Because keys are derived and surfaces are stored, this is always safe and always reversible.

Never allow two normalizer versions to serve reads simultaneously. Lookups would silently diverge by which replica answered.

---

## 5. Working mode

### 5.1 The resolution ladder

Each tier is tried in order and returns a `(concept_id, confidence, tier)` or falls through. All tiers are deterministic and model-free.

| Tier | Method | Complexity | Default policy |
|---|---|---|---|
| 0 | exact surface hit | O(1) hash | auto-resolve, conf 1.00 |
| 1 | `norm` key hit | O(1) hash | auto-resolve, conf 0.99 |
| 2 | `alnum` / `sorted` key hit | O(1) hash | auto-resolve, conf 0.95 |
| 3 | enabled rewrite rules, then retry tiers 0–2 | O(rules) | auto-resolve, conf 0.90 |
| 4 | `initials` bridge within scope | O(1) hash | auto **only if unique in scope** |
| 5 | fuzzy: trigram block → edit distance | O(candidates) | **suggest only** (see §5.2) |
| 6 | ANN over precomputed embeddings | O(log n) | **suggest only** |
| 7 | miss | — | enqueue + return `UNRESOLVED` |

Tiers 0–4 are what you should ship first. They cover the overwhelming majority of real traffic, and they are the tiers whose failure modes you can reason about completely.

### 5.2 Fuzzy matching guardrails — read this section twice

Tier 5 is where an alias resolver quietly destroys itself. Short strings are dense in edit-distance space: `AWS`/`AWX`, `CPU`/`GPU`, `S3`/`S4`, `GPT-4`/`GPT-5`, `v1`/`v2` are all distance 1 and all mean completely different things.

Hard rules:

```
len ≤ 4          → NO fuzzy matching at all. Exact keys only.
5 ≤ len ≤ 8      → max edit distance 1, AND first character must match
len ≥ 9          → max edit distance 2, AND normalized similarity ≥ 0.88
```

Plus three absolute vetoes, applied before any threshold:

1. **Digit veto.** If two strings differ in any digit, they never fuzzy-match. Digits are version numbers, tiers, and generations — they are semantically load-bearing in exactly the domains where this module gets used.
2. **Canonical veto.** If the query string is *itself* an exact `pref_label` of some concept, it means what it says. Do not fuzzy-match it to something else.
3. **Negation/affix veto.** Differences confined to `un-`, `non-`, `de-`, `anti-`, `-less` invert meaning at tiny edit cost.

Tier 5/6 results are returned as `SUGGESTED` with candidates, never as `RESOLVED`, unless the caller opts in explicitly. Default behavior on a strong-but-not-certain fuzzy hit is to **enqueue for reconciliation** and let the batch job confirm it once, permanently.

**On tier 6 and the "no LLMs" constraint:** a small local bi-encoder (CPU, ~20ms) consumes zero API tokens and is compatible with the letter and spirit of "no LLM in working mode." It is still model inference with latency and a failure mode, so it is optional and suggest-only. Precompute concept embeddings during reconciliation; working mode only embeds the query.

### 5.3 Ambiguity is a first-class result, not an error

When a key maps to multiple concepts and `scope` doesn't disambiguate, **return `AMBIGUOUS` with ranked candidates.** Silently picking the most frequent one is the worst available option: it produces an error that is invisible to both the caller and to your metrics.

A cheap, model-free context disambiguator that works well in practice:

```python
def disambiguate(candidates, context_tokens):
    # score = token overlap between the caller's context and each concept's
    # gloss + alias set, IDF-weighted. Requires a margin to commit.
    scored = sorted(((overlap_idf(c, context_tokens), c) for c in candidates),
                    reverse=True)
    if len(scored) == 1 or scored[0][0] >= scored[1][0] + MARGIN:
        return scored[0][1]
    return None   # → AMBIGUOUS
```

This is why `gloss` is worth populating even when a human never reads it.

### 5.4 Snapshots

Working mode reads from an **immutable in-memory snapshot**, built by the reconciler and promoted atomically. At 10⁵ aliases this is a few MB — trivially resident.

Benefits, all of which you will want eventually:
- deterministic behavior within a process lifetime (no read/write contention, no mid-request drift),
- atomic rollback (repoint to the previous snapshot),
- reproducibility — every `Resolution` carries `snapshot_id`, so a support ticket from three weeks ago can be replayed exactly,
- shadow evaluation of a candidate snapshot against live traffic before promotion (§11.3).

### 5.5 Miss recording must not block

`resolve()` must stay at hash-lookup latency. Misses append to an in-process ring buffer flushed asynchronously; the flusher upserts into `unresolved` with `hits = hits + 1`.

Store with each miss:
- distinct raw surfaces observed (capped, e.g. 10),
- a **reservoir sample of ≤5 context snippets, ≤200 chars each**,
- hit count and last-seen timestamp.

Those context snippets are the difference between a reconciler that can resolve `MC` and one that cannot. Without them you are asking a model to guess. Budget for them at the API boundary: `resolve(surface, context=...)` should be easy for callers to populate.

### 5.6 API

```python
resolve(surface, *, scope=None, context=None, lang="en",
        max_tier=4, record_miss=True) -> Resolution

resolve_many(surfaces, **kw) -> list[Resolution]          # batched, single snapshot read
expand(concept_id) -> Concept                              # canonical + all variants by role
candidates(surface, k=5, **kw) -> list[Candidate]          # explicit fuzzy/ANN probe

assert_alias(surface, concept_id, *, actor, alias_type, lock=True)
retract_alias(alias_id, *, actor, reason)
merge_concepts(src, dst, *, actor, reason)
split_concept(concept_id, partition, *, actor)
forbid_merge(a, b, *, actor, reason)

reconcile(*, max_items=None, token_budget=None, dry_run=True) -> ReconcileReport
stats() -> Stats
```

```python
@dataclass(frozen=True)
class Resolution:
    status: Literal["RESOLVED", "SUGGESTED", "AMBIGUOUS", "UNRESOLVED"]
    concept_id: str | None
    canonical:  str | None
    variants:   list[Variant]          # (surface, role, alias_type, lang)
    confidence: float
    tier:       int
    candidates: list[Candidate]        # populated for SUGGESTED / AMBIGUOUS
    snapshot_id: str
    norm_version: int
```

Design notes on the surface:

- `max_tier` lets callers choose their own precision/recall tradeoff. A search-query expander wants tier 6; a billing-code normalizer wants tier 1.
- `expand()` returning variants **grouped by role** lets a search backend take `pref + alt + hidden` for indexing while a UI takes `pref + alt` only.
- `dry_run=True` is the default on `reconcile()` deliberately. The first thing you want from a reconciliation run is a diff to read, not a mutated database.

---

## 6. Reconciliation mode — overview

A batch job with seven stages. Only stage R5 touches an LLM; everything before it exists to make R5 as small as possible, and everything after it exists to stop R5 from corrupting the database.

```
R1 harvest      free extractors — resolve what needs no model
R2 prune        drop junk, dedup, prioritize by value
R3 block        narrow to k candidates per unknown          ← biggest cost lever
R4 assemble     batch clusters into compact prompts
R5 decide       LLM, structured output, cheap→strong escalation
R6 validate     deterministic gates; reject before writing  ← biggest safety lever
R7 apply+learn  transactional write, audit, promote rules, rebuild snapshot
```

## 7. Reconciliation stages

### 7.1 R1 — Harvest (zero tokens)

Before spending a single token, run rule-based extractors over the context snippets already sitting in `unresolved`:

- **Schwartz–Hearst** parenthetical extraction: `machine learning (ML)` → `ML` is an acronym of `machine learning`, at ~96% precision.
- **Reverse pattern**: `ML (machine learning)`.
- **Definitional patterns**: `X, also known as Y`, `X or Y for short`, `formerly X`.
- **Structured imports**: existing tag tables, glossaries, config enums, i18n files, `synonyms.txt` if you already run Elasticsearch/Solr.

On corpora with any documentation in them, this typically clears a meaningful slice of the acronym backlog for free. Anything R1 resolves never reaches the model.

### 7.2 R2 — Prune and prioritize

Drop before batching:

- length-1 tokens, pure numbers, hex/UUID-shaped strings, URLs, file paths, stopwords,
- anything already marked `junk` or `insufficient_context` **by the same `model@prompt_version`** — this is negative caching, and it is what stops the reconciler from re-asking the same unanswerable question every night,
- items below a frequency floor (e.g. `hits < 3`) unless flagged important by a caller.

Then order the survivors:

```
priority = log1p(hits) · recency_decay(last_seen) · caller_weight
```

Keyword traffic is Zipfian. Roughly the top 20% of distinct surfaces account for ~80% of lookups, so frequency-ordered spending buys most of the coverage for a fraction of the budget. Run with a `token_budget` and let priority decide what fits.

### 7.3 R3 — Blocking

For each pending item, retrieve k ≈ 10–20 candidate concepts. Union of two blockers:

- **Lexical** — trigram / inverted-index over `norm_key` (`pg_trgm` GIN, or SQLite FTS5 trigram, or an in-process n-gram index).
- **Semantic** — ANN over concept embeddings (`pgvector`, FAISS, or numpy at small scale).

Also block **pending items against each other**, not just against existing concepts: `kubernets`, `k8s`, and `Kube` arriving in the same batch should be considered together and may form one *new* concept in a single decision.

Two warnings the literature is emphatic about:

1. **Blocking sets a recall ceiling.** Anything separated here is invisible to the model forever. Keep k generous and union multiple blocking keys rather than tuning one aggressively.
2. **Lexical blocking fails exactly where you need it most** — `k8s` and `Kubernetes` share almost no trigrams. Semantic blocking catches this. If you only implement one blocker, note that acronyms are precisely the case it will miss, and lean on the `initials` key (§4.2) to compensate.

### 7.4 R4 — Assemble batched prompts

**Never prompt pairwise.** One call handles a cluster of unknowns plus their shared candidate set. Batch prompting amortizes the instruction block across decisions; clustering formulations have been reported to cut API calls several-fold versus pairwise matching at comparable accuracy.

Render candidates as compact rows, not JSON — same information, substantially fewer tokens:

```
CANDIDATES
c_1042 | Kubernetes | container orchestration platform | alt: k8s, kube
c_1077 | Kafka      | distributed event streaming log  | alt: apache kafka
c_1103 | KEDA       | event-driven autoscaler for k8s  | alt: —

UNKNOWNS
u1 | "kubernets"  | 14 hits | ctx: "kubernets cluster wont schedule pods"
u2 | "K8S"        | 89 hits | ctx: "migrating the K8S ingress controller"
u3 | "kubectl"    | 31 hits | ctx: "run kubectl get pods -A"
```

Batch sizing: 15–30 unknowns per call is a reasonable starting point. Beyond that, accuracy degrades — the model starts pattern-matching across items rather than deciding each one. Tune this against your gold set (§11), not by intuition.

Mark provenance **inside the prompt**. Glosses generated by a previous LLM pass must be tagged:

```
c_1103 | KEDA | [llm-gloss, unreviewed] event-driven autoscaler | alt: —
```

Without this you get a self-confirmation loop: the model's own unreviewed guesses come back as apparent evidence and harden into false certainty over successive runs.

### 7.5 R5 — Decide

Structured output, one record per unknown, enforced by a schema (tool call / response schema, not "please reply in JSON"):

```json
{
  "ref": "u2",
  "decision": "link",
  "concept_id": "c_1042",
  "alias_type": "abbreviation",
  "label_role": "alt",
  "confidence": 0.96,
  "evidence": "appears with 'ingress controller', a Kubernetes component"
}
```

`decision ∈ link | new_concept | group_new | ambiguous | junk | insufficient_context`

- `new_concept` additionally returns a proposed `pref_label`, `gloss`, `scope`.
- `group_new` links several unknowns from this batch into one new concept (`u1`+`u2` → new "Kubernetes" if it didn't exist).
- `ambiguous` and `insufficient_context` are **first-class, encouraged outputs.** Prompt for them explicitly. A model that cannot say "I don't know" will fabricate links, and fabricated links are the expensive failure (§10.1).

**Escalation ladder.** Run the bulk pass on a cheap model. Escalate to a strong model only for:
- items the cheap model marked `ambiguous` or returned with confidence below τ_review,
- any decision that would link two *existing* multi-alias concepts (a merge — the highest-blast-radius operation),
- items whose `hits` put them in the top decile of traffic.

Typically 5–15% of items escalate, so you pay strong-model rates on a small slice.

### 7.6 R6 — Validate (deterministic gates, no model)

Every gate below runs before anything is written. Rejections go to `decision_log` with the gate name, which gives you a precise failure taxonomy to tune against.

| Gate | Check | On failure |
|---|---|---|
| **Schema** | valid enums, required fields present | reject, retry once |
| **Referential** | `concept_id` exists and is `active` | reject — this catches hallucinated ids |
| **Acronym plausibility** | for `acronym`/`initialism`: every char of the short form appears in order in the target `pref_label`, and the first char matches the first char of the first word (Schwartz–Hearst matching rule) | reject |
| **Role consistency** | `misspelling` ⟹ `label_role='hidden'`; `translation` ⟹ different `lang` | reject |
| **Never-merge** | pair not in `never_merge` | reject, alert |
| **Lock** | target alias not `locked` | reject |
| **Scope** | scopes compatible or one is global | queue for human |
| **Blast radius** | link joins two clusters each with ≥ N aliases (N ≈ 5) | **force human review regardless of confidence** |
| **Confidence** | ≥ τ_auto → apply; τ_review..τ_auto → human queue; < τ_review → mark `insufficient_context` | route |
| **Digit veto** | reuse §5.2 rule 1 | reject |

Suggested starting thresholds: τ_auto = 0.90, τ_review = 0.65. Calibrate against the gold set; do not treat model-reported confidence as calibrated out of the box.

The acronym plausibility gate deserves emphasis: it is three lines of code and it catches a large fraction of hallucinated links at zero cost, because a model inventing a plausible-sounding expansion usually cannot satisfy the character-subsequence constraint.

### 7.7 R7 — Apply and learn

Transactional per decision. Write the alias/concept rows, stamp `provenance = llm:<model>@<prompt_version>`, set `origin_concept` (so merges are undoable), append to `decision_log` with token counts, then rebuild and promote a new snapshot after the eval gate passes.

**The compounding step.** Applying an alias resolves one surface forever. Better: ask the model, once per batch, whether any of its decisions generalize into a *rule*.

- Alias: `k8s → Kubernetes`. Handles one string.
- Rule: `<name>-svc → <name> service`. Handles every unseen member of the family, at tier 3, at zero future cost.

Constraints on rules, because a bad rule is a systemic error rather than a single wrong row:
- constrained pattern syntax (prefix/suffix/token-template), **never arbitrary LLM-authored regex**,
- `enabled = 0` by default; a human turns rules on,
- every rule must be individually disableable, and disabling one must be a snapshot rebuild, not a data migration,
- rules run through the same gold-set eval before promotion.

This is what bends the cost curve: reconciliation converts per-item spending into per-family capability, so the unresolved rate falls faster than the vocabulary grows.

### 7.8 Human review loop

The review queue should be small and high-leverage: ambiguous items, blast-radius merges, and low-confidence decisions on high-traffic keys. A minimal CLI/TUI showing surface, contexts, top candidates, and the model's rationale with accept/reject/edit is enough for v1 — do not build a web app first.

Track **human override rate** on auto-applied decisions by sampling. It is your best proxy for reconciler precision in production, and it is the metric that should gate raising τ_auto.

---

## 8. Token economics

Eleven levers, roughly in order of impact:

1. **Cache-first architecture.** Cost is O(distinct new concepts), not O(queries). This is the entire design; everything else is a constant factor on top.
2. **Dedup by `norm_key` before batching.** On real query logs this is typically a 3–10× reduction before any prompt is built.
3. **Blocking.** O(n·m) → O(n·k). Sending 10 candidates instead of a 50k-concept glossary is a ~1000× reduction in prompt size per decision.
4. **Free harvesters (R1).** Schwartz–Hearst clears acronyms at zero cost.
5. **Batch/cluster prompting.** Amortizes instructions and examples; reported multi-× reductions in API calls versus pairwise.
6. **Frequency prioritization.** Zipfian traffic means ~20% of distinct keys cover ~80% of lookups.
7. **Compact rendering.** Pipe rows over JSON, ids over objects, glosses truncated to ~15 words.
8. **Prompt caching.** The instruction block and stable candidate prefixes are identical across batches within a run.
9. **Model escalation.** Cheap triage, strong model on the 5–15% ambiguous tail only.
10. **Negative caching.** `junk` / `insufficient_context` recorded with `model@prompt_version` — never re-ask the same question of the same model. Only a version bump reopens it.
11. **Rule promotion.** Converts per-item cost into per-family cost.

### 8.1 Illustrative shape

Rough sketch for a mid-size deployment — the point is the *shape*, not the constants:

| | Day 1 (cold) | Week 4 | Steady state |
|---|---|---|---|
| Lookups/day | 50,000 | 50,000 | 50,000 |
| Distinct surfaces | 3,000 | 3,000 | 3,000 |
| Working-mode hit rate | ~0% | ~92% | >99% |
| Unresolved after dedup + R1 + R2 | ~800 | ~40 | ~5 |
| LLM calls (30/batch) | ~27 | ~2 | ~0–1 |

The interesting property is the third row. Every reconciliation run permanently raises the hit rate, so LLM spend decays toward the rate at which your domain genuinely invents new terminology — which is a handful of terms per week, not a function of traffic.

**Corollary for capacity planning:** if your LLM cost is *not* decaying week over week, something is wrong — usually a normalizer that's too weak (generating spurious distinct keys), missing negative caching (re-asking dead items), or callers passing raw uncleaned text as keywords.

---

## 9. Merge, split, and cluster mechanics

### 9.1 Merging

Union-find over `concept_id` with `merged_into` pointers and path compression at read time:

```python
def canonical_id(cid):
    seen = []
    while (nxt := merged_into.get(cid)):
        seen.append(cid); cid = nxt
    for c in seen: merged_into[c] = cid    # compress
    return cid
```

Merged concepts are **tombstoned, never deleted**. Stale ids held by downstream systems keep resolving. Every alias moved during a merge records `origin_concept`, which is what makes a split reconstructible later.

### 9.2 Do not take the transitive closure

The tempting design is: score all pairs, threshold, take connected components. The entity-resolution literature is consistent that this is noise-sensitive — connected-components clustering raises recall but a *single* bad edge chains two unrelated clusters into one, and the damage is unbounded because it propagates transitively.

Concretely: `ML → machine learning`, `ML → millilitre`, and transitive closure has now declared machine learning and millilitre synonymous, along with everything attached to either.

Policy:

- pairwise similarity **proposes**; it never merges,
- an edge joining two existing multi-alias clusters requires a direct high-confidence LLM decision **and** passes the blast-radius gate (§7.6) — i.e. a human,
- keep `never_merge` populated aggressively; every rejected merge should write a row, so the same mistake is impossible twice.

### 9.3 Splitting

Splits are rarer and more painful than merges, which is the argument for biasing toward under-merging. `split_concept(cid, partition, actor)` allocates new concept ids, moves aliases per the partition, writes `never_merge` rows between the resulting groups, and preserves the original id as a tombstone pointing at whichever side is the majority successor — with a note in the log that resolution through that tombstone is approximate.

---

## 10. Failure modes and guardrails

### 10.1 Over-merging is the asymmetric risk

| | Under-merge (missed alias) | Over-merge (wrong link) |
|---|---|---|
| Symptom | cache miss; goes to the queue | silently wrong answers |
| Detection | automatic (it's in `unresolved`) | none — nothing looks broken |
| Cost of fix | one reconciliation cycle | manual archaeology across the audit log |
| Downstream blast | none | every consumer that trusted the canonical form |

**Design bias: prefer under-merging everywhere.** A missed alias is a self-reporting, self-healing condition — it lands in the queue and gets fixed on the next run. A wrong merge is invisible, permanent until someone notices, and contaminates every consumer. This asymmetry justifies every conservative threshold in §5.2 and §7.6.

### 10.2 Other failure modes

| Failure | Mechanism | Mitigation |
|---|---|---|
| **Canonical label churn** | someone renames a concept; downstream string-keyed systems break | immutable opaque ids; labels are display attributes; publish label changes as events |
| **Normalizer drift** | a "harmless" rule change collapses distinct keys | `norm_version` + full re-index + gold-set gate before promotion |
| **LLM self-confirmation** | model's own unreviewed glosses return as evidence and harden | tag `[llm-gloss, unreviewed]` in prompts; require human review before a gloss can anchor a merge |
| **Hallucinated concept ids** | model invents `c_9999` | referential gate (§7.6) |
| **Homonym collapse** | `ML`, `CV`, `IR`, `SF` forced into one concept | scope-qualified uniqueness; `AMBIGUOUS` as a real return value |
| **Synonym/hierarchy confusion** | `Postgres` vs `Postgres 16`; `laptop` vs `ThinkPad X1` | §10.4 |
| **Queue starvation** | high-frequency junk crowds out real terms | junk filter + negative caching + priority decay |
| **Multi-writer races** | two reconcilers merge overlapping clusters | single-writer reconciliation, or advisory lock on the concept table |
| **Caller pollution** | callers pass raw sentences as "keywords" | validate input shape at the API boundary; reject and count |

### 10.3 Where a human must be in the loop

Non-negotiable: merges of two established clusters, any change to a `locked` alias, enabling a rewrite rule, promoting a snapshot that regresses gold-set precision, and any `never_merge` deletion.

### 10.4 The synonymy-vs-hierarchy question

This will come up in week two, so decide now. `Postgres` and `Postgres 16` are not synonyms; neither are `laptop` and `ThinkPad X1`. Options:

1. **v1 policy (recommended):** synonymy only. Anything that isn't a true equivalence goes to a human queue and is left unresolved. Under-merge by default.
2. **v2:** add a `relation(concept_a, concept_b, kind)` table with `broader`/`narrower`/`related` (SKOS semantics), and let `resolve()` optionally roll up to a configured granularity.

Do not let the reconciler quietly encode hierarchy as synonymy — that is over-merging with extra steps, and it is very hard to unwind once downstream consumers depend on it.

---

## 11. Evaluation

### 11.1 Gold set

300–1000 hand-labeled `(surface, scope, expected_concept_or_NONE)` pairs, frozen, stratified across tiers and deliberately stuffed with adversarial cases: near-miss short strings, digit variants, cross-scope homonyms, plausible-but-wrong acronym expansions, and true negatives (strings that *should* stay unresolved). The true negatives are the ones that catch over-merging, so make them at least a third of the set.

### 11.2 Metrics

| Metric | Definition | Target direction |
|---|---|---|
| **Coverage** | % of live lookups resolved at tiers 0–4 | ↑, this is the headline |
| **Precision @ tier** | correctness of auto-resolutions, per tier | ↑, **gated** |
| **False-merge rate** | true negatives incorrectly resolved | ↓, **hard gate** |
| Ambiguity rate | % returning `AMBIGUOUS` | monitor (rising = scope model is wrong) |
| Backlog burn-down | unresolved items resolved per run | ↑ |
| Tokens per new alias | reconciliation efficiency | ↓ |
| Human override rate | sampled corrections of auto-applied decisions | ↓, gates raising τ_auto |

Precision is the **gated** metric; coverage is the **optimized** metric. Never trade the first for the second.

### 11.3 Promotion gates

Any change to the normalizer, thresholds, prompt, model, or rule set must:

1. re-run the gold set — block promotion on any precision or false-merge regression,
2. run in **shadow mode** against a sample of live traffic, diffing decisions against the current snapshot, with a human reading the diff,
3. be promoted as an atomic snapshot swap, with the previous snapshot retained for instant rollback.

Pin the model version explicitly. A silent provider-side model update is a normalizer change you didn't authorize.

---

## 12. Implementation plan

**Phase 0 — skeleton (≈1 week).** Schema, normalizer with key bundle, tiers 0–2, async miss logging, `resolve` / `expand` / `assert_alias`. Ship it and instrument it.

Resist building further until you have two weeks of real miss data. The distribution of misses answers almost every open design question — whether you need fuzzy matching at all, whether homonyms are actually a problem in your domain, what the real scope boundaries are, and what your steady-state LLM budget will be. Guessing at these before you have the data is the main way this kind of project gets over-engineered.

**Phase 1 — seeding.** Import existing glossaries/tag tables. Build the review CLI. Add `merge` / `split` / `forbid_merge` with the audit log. Now the database is useful even with zero LLM involvement.

**Phase 2 — reconciliation.** R1 harvest, R2 prune, R3 lexical blocking, R4 batching, R5 single-model decide, R6 gates, R7 apply. **Ship with `dry_run=True` and read the diffs for a week before letting it write.**

**Phase 3 — the long tail.** Tier 3 rules, tier 4 initials bridge, tier 5 fuzzy with the §5.2 guardrails, semantic blocking + tier 6, model escalation ladder, ambiguity/context disambiguation.

**Phase 4 — hardening.** Gold set, eval harness, shadow mode, snapshot promotion pipeline, cost dashboards.

---

## 13. Reference pseudo-code

### 13.1 Working mode

```python
def resolve(surface, *, scope=None, context=None, max_tier=4, record_miss=True):
    snap = SNAPSHOT.current()
    keys = make_keys(surface, snap.norm_version)

    for tier, lookup in enumerate(TIER_LOOKUPS[:max_tier + 1]):
        hits = lookup(snap, keys, scope)
        if not hits:
            continue
        if len(hits) == 1:
            return resolved(hits[0], tier, snap)
        # multiple concepts share this key → homonym
        if context and (pick := disambiguate(hits, tokenize(context))):
            return resolved(pick, tier, snap, confidence_penalty=0.05)
        return ambiguous(hits, tier, snap)

    if max_tier >= 5:
        cands = fuzzy_candidates(snap, keys, scope)      # §5.2 guardrails applied inside
        if cands and cands[0].score >= TAU_SUGGEST:
            if record_miss:
                MISS_BUFFER.append(keys, surface, scope, context)  # confirm once, permanently
            return suggested(cands, snap)

    if record_miss:
        MISS_BUFFER.append(keys, surface, scope, context)          # non-blocking
    return unresolved(snap)
```

### 13.2 Reconciliation mode

```python
def reconcile(*, max_items=None, token_budget=None, dry_run=True):
    report = ReconcileReport()

    # R1 — free harvest
    for item in db.pending():
        if pair := harvest(item.contexts):          # Schwartz-Hearst et al.
            stage(link_from_rule(item, pair)); report.free += 1

    # R2 — prune + prioritize
    items = prioritize(prune(db.pending(), negative_cache=db.negative_cache()))
    items = items[:max_items]

    # R3/R4 — block and batch
    for batch in cluster_into_batches(items, size=25):
        cands = block(batch, k=15)                  # lexical ∪ semantic
        if token_budget and estimate(batch, cands) > token_budget:
            break
        prompt = render_compact(batch, cands)       # pipe rows, tagged provenance

        # R5 — decide, cheap first
        decisions = llm(CHEAP_MODEL, prompt, schema=DecisionSchema)
        escalate  = [d for d in decisions if needs_escalation(d, batch)]
        if escalate:
            decisions = merge_results(
                decisions, llm(STRONG_MODEL, render_compact(escalate, cands),
                               schema=DecisionSchema))

        # R6 — gates
        for d in decisions:
            ok, gate = validate(d, batch, db)
            (stage(d) if ok else report.reject(d, gate))
            db.log_decision(d, verdict=("staged" if ok else f"rejected:{gate}"))

    # R7 — apply
    if dry_run:
        return report.with_diff(staged())
    with db.transaction():
        apply_staged(); promote_rules(candidate_rules())
    snap = build_snapshot()
    if eval_gate(snap):                 # §11.3
        SNAPSHOT.promote(snap)
    else:
        report.blocked = "eval gate failed; snapshot not promoted"
    return report
```

---

## 14. Summary of the load-bearing decisions

1. **Four identity layers**, UMLS-style, with `lexform` as the working-mode index and `lexform → concept` explicitly many-to-many so homonyms are representable.
2. **SKOS label roles** (`pref` / `alt` / `hidden`) so misspellings are searchable but never displayed.
3. **Opaque immutable concept ids**; canonical labels are mutable display attributes.
4. **Store surfaces, derive keys**, version the normalizer, re-index rather than migrate.
5. **A tiered deterministic ladder** where tiers 0–4 auto-resolve and 5–6 only suggest.
6. **Length- and digit-aware fuzzy guardrails** — no fuzzy matching at all below 5 characters.
7. **Ambiguity as a return value**, not an internal coin flip.
8. **Immutable snapshots** for determinism, rollback, reproducibility, and shadow evaluation.
9. **Free harvest → prune → block → batch → escalate → validate → apply**, with every stage before the model existing to shrink the model's job.
10. **Deterministic validation gates**, especially the Schwartz–Hearst acronym plausibility check, which costs three lines and catches a large class of hallucinations.
11. **No transitive closure**; pairwise similarity proposes, humans and high-confidence direct decisions dispose.
12. **Bias toward under-merging**, because under-merges are self-reporting and over-merges are silent.
13. **Rule promotion**, so reconciliation converts per-item cost into per-family capability and the cost curve bends downward.

---

## 15. Open questions

Answers to these would sharpen several of the choices above:

1. **Scale.** Hundreds of concepts, or hundreds of thousands? Below ~10⁴ the entire fuzzy/embedding tier is probably unnecessary — everything fits in a dict.
2. **Scope model.** Single domain, or multi-tenant / multi-domain? This determines whether homonym handling is a core feature or a rare edge case.
3. **Context availability.** Can callers pass surrounding text at `resolve()` time? If not, R1 harvesting and context disambiguation both lose most of their power, and the reconciler will lean much harder on the model.
4. **Human reviewer availability.** If there is no reviewer, τ_auto must rise and coverage will be permanently lower — that's a real tradeoff, not a gap to paper over.
5. **Latency budget.** Microseconds (in-process snapshot) or tens of milliseconds (network service)? This decides the snapshot-vs-service split in §5.4.
6. **Which error hurts more in your domain?** The whole design assumes over-merging is worse. If your use case is search-query expansion, that assumption may invert — recall matters more, and thresholds should loosen accordingly.