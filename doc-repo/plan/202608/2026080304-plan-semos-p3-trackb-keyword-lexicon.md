# SemOS P3 Track B — Keyword Lexicon: Implementation Plan

**Document ID:** `2026080304`
**Date:** 2026-08-03
**Status:** Executed — all chunks complete (2026-08-04)
**Goal:** Implement the keyword lexicon as the second `semid` kernel instantiation, shipped behind `KEYWORD_RESOLVER_MODE=observe`

> **2026-08-04 status:** Chunks 0–H are complete and merged to `main`. See the implementation log
> `2026080402-devdoc-semos-p3-trackb-implementation-log.md` and the handoff
> `2026080401-handoff-semos-p3-trackb-keyword-lexicon.md` for the build record and deferred boundary.

**Supersedes:** none
**Depends on:** P2 (semid kernel, `kb.semid_*` shared tables), P3 Track A (assertion stores, normalizer registry pattern)
**Spec:** `2026080101-spec-keyword-canonicalization-merged.md` (DR16 merged design)
**ADR:** `2026072901-adr-ontology-platform-and-adaptive-pipeline.md` §8.3.6

**Tech stack:** Go 1.25, PostgreSQL/goose migrations, Echo v4, `sqlmock`, `jj`.

---

## 0. Scope decisions

### Built in this plan

1. All 6 keyword tables as goose migrations: `kb.keyword_concepts`, `kb.keyword_surfaces`, `kb.keyword_surface_keys`, `kb.keyword_mentions`, `kb.keyword_unresolved`, `kb.keyword_rewrite_rules`
2. CRUD stores for concepts, surfaces, surface_keys, mentions, unresolved, rewrite_rules
3. Keyword normalizer producing 6 key kinds (exact, norm, alnum, sorted, phonetic, initials)
4. `KeywordFamily` implementing `semid.FamilyAdapter` with tiers 0-4 (exact match, auto-accept)
5. REST handlers for concept/surface/rewrite-rule CRUD + `ResolveSurface` endpoint
6. `KEYWORD_RESOLVER_MODE` env-var gating (default `off`; `observe` mode shipped)
7. Mention collector as a Phase C `PostProcessIndexer` (idempotent, gated on `observe`/`on` modes)
8. Exit criteria tests

### Deferred beyond Track B (explicit carry-forward)

- **Fuzzy tiers 5-6** (trigram/vector blocking, edit-distance filtering, ANN) — the spec's fuzzy-matching guardrails (§5.1) are designed but not built; `CandidateNodes` returns tier-4-only candidates for the initial ship
- **Full reconciliation pipeline** (R1-R7: harvest, prune, block, assemble, decide, validate, apply) — the stores exist, the kernel pipeline exists, but the batch-reconciliation CLI/workflow is not built
- **`aligns_to_term` bridge** — no `AssociationResolver` for keywords; keyword concepts do not align to governed terms
- **`on` mode** — only `off` and `observe` are implemented; `on` mode connects resolution to retrieval/search payloads
- **Context-token disambiguation** — the spec §5.2 IDF-weighted overlap heuristic is not built
- **Curated seed content** — no `ontology-seed` keyword module; initial surfaces/manual imports only
- **Batch adjudication UI** — admin surfaces for the reconciliation backlog
- **Rewrite-rule auto-promotion** — tier-3 rewrite rules are authored manually; no auto-promotion from validated decisions

### Why this scope

The ADR explicitly positions Track B as "the second kernel instantiation shipped behind `KEYWORD_RESOLVER_MODE=observe`." The `observe` mode contract is: mention collection + deterministic resolution + backlog accumulation, with **no downstream consumer connected**. This scope delivers exactly that — a provable, measurable kernel that can later be extended with fuzzy tiers, reconciliation batch processing, and downstream wiring.

---

## 1. Execution order

```
Chunk 0 — Migrations + store interfaces       ── must be first
Chunk A — Concept store + tests               ── depends on 0
Chunk B — Surface + surface_keys stores       ── depends on 0, A
Chunk C — Mention + unresolved + rewrite stores ── depends on 0
Chunk D — Keyword normalizer                  ── pure, no DB deps
Chunk E — KeywordFamily (semid adapter)       ── depends on D, B, C
Chunk F — REST handlers + routes              ── depends on A, B, C, E
Chunk G — Config wiring + mention collector   ── depends on C, F
Chunk H — Exit criteria + verification        ── depends on A–G
```

Parallelisable after Chunk 0: **{A, C, D}** are independent. **B** depends on A (FK to concepts). **E** depends on D + B + C. **F** and **G** are sequential.

Every task is TDD: write the failing test, verify red, implement, verify green, commit with `jj`.

---

## Chunk 0 — Migrations

### Task 0.1: Create keyword schema migrations

**Files to create:**
- `ChenWeb/project_migrations/20260803000001_create_kb_keyword_concepts.sql`
- `ChenWeb/project_migrations/20260803000002_create_kb_keyword_surfaces.sql`
- `ChenWeb/project_migrations/20260803000003_create_kb_keyword_surface_keys.sql`
- `ChenWeb/project_migrations/20260803000004_create_kb_keyword_mentions.sql`
- `ChenWeb/project_migrations/20260803000005_create_kb_keyword_unresolved.sql`
- `ChenWeb/project_migrations/20260803000006_create_kb_keyword_rewrite_rules.sql`

Each follows the goose format (`-- +goose Up` / `-- +goose Down`), `kb.` schema, `IF NOT EXISTS`, `BIGSERIAL PRIMARY KEY`, `TIMESTAMPTZ` with `DEFAULT NOW()`, `CHECK` constraints for enums, and `CREATE UNIQUE INDEX IF NOT EXISTS`.

**Key schema decisions:**
- `kb.keyword_concepts.concept_id` is `TEXT PRIMARY KEY` (opaque, immutable per spec §3.2 rule 1)
- `kb.keyword_surfaces.surface_id` is `TEXT PRIMARY KEY` (not BIGSERIAL — spec requires opaque ids)
- `kb.keyword_surface_keys` has composite PK `(surface_id, key_kind)` with `ON DELETE CASCADE` to surfaces
- `kb.keyword_unresolved` has composite PK `(norm_key, scope)` — the natural dedup key
- `kb.keyword_mentions` uses `BIGSERIAL` for `mention_id` (append-only queue, no natural key)
- `kb.keyword_rewrite_rules.rule_id` is `TEXT PRIMARY KEY`
- All tables have `create_time TIMESTAMPTZ NOT NULL DEFAULT NOW()` and `modify_time TIMESTAMPTZ NOT NULL DEFAULT NOW()`

**Schema columns per spec §3.2:**

| Table | Columns |
|-------|---------|
| `keyword_concepts` | `concept_id TEXT PK`, `pref_label TEXT NOT NULL`, `gloss TEXT`, `scope TEXT NOT NULL DEFAULT '_'`, `status TEXT NOT NULL CHECK (status IN ('active','provisional','merged','deprecated'))`, `merged_into TEXT REFERENCES kb.keyword_concepts(concept_id)`, `gloss_source TEXT NOT NULL DEFAULT 'none'`, `create_time`, `modify_time` |
| `keyword_surfaces` | `surface_id TEXT PK`, `concept_id TEXT NOT NULL REFERENCES kb.keyword_concepts(concept_id)`, `surface TEXT NOT NULL`, `norm_key TEXT NOT NULL`, `norm_version INT NOT NULL`, `label_role TEXT NOT NULL CHECK (label_role IN ('pref','alt','hidden'))`, `alias_type TEXT NOT NULL`, `lang TEXT NOT NULL DEFAULT 'en'`, `scope TEXT NOT NULL DEFAULT '_'`, `confidence DOUBLE PRECISION NOT NULL`, `provenance TEXT NOT NULL`, `locked BOOLEAN NOT NULL DEFAULT FALSE`, `evidence TEXT`, `create_time`, `modify_time` |
| `keyword_surface_keys` | `surface_id TEXT NOT NULL REFERENCES kb.keyword_surfaces(surface_id) ON DELETE CASCADE`, `key_kind TEXT NOT NULL`, `key_value TEXT NOT NULL`, `norm_version INT NOT NULL`, `PRIMARY KEY (surface_id, key_kind)` |
| `keyword_mentions` | `mention_id BIGSERIAL PK`, `artifact_ref TEXT`, `chunk_ref TEXT`, `context_text TEXT`, `ks_id TEXT`, `create_time` |
| `keyword_unresolved` | `norm_key TEXT NOT NULL`, `scope TEXT NOT NULL DEFAULT '_'`, `surfaces JSONB NOT NULL`, `contexts JSONB`, `hits INT NOT NULL DEFAULT 1`, `status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','batched','needs_human','resolved','junk','insufficient_context'))`, `attempts INT NOT NULL DEFAULT 0`, `last_attempt TEXT`, `priority DOUBLE PRECISION NOT NULL DEFAULT 0`, `first_seen TIMESTAMPTZ NOT NULL DEFAULT NOW()`, `last_seen TIMESTAMPTZ NOT NULL DEFAULT NOW()`, `PRIMARY KEY (norm_key, scope)` |
| `keyword_rewrite_rules` | `rule_id TEXT PK`, `pattern TEXT NOT NULL`, `replacement TEXT NOT NULL`, `scope TEXT NOT NULL DEFAULT '_'`, `enabled BOOLEAN NOT NULL DEFAULT FALSE`, `provenance TEXT`, `create_time`, `modify_time` |

- [ ] Create `20260803000001_create_kb_keyword_concepts.sql`
- [ ] Create `20260803000002_create_kb_keyword_surfaces.sql`
- [ ] Create `20260803000003_create_kb_keyword_surface_keys.sql`
- [ ] Create `20260803000004_create_kb_keyword_mentions.sql`
- [ ] Create `20260803000005_create_kb_keyword_unresolved.sql`
- [ ] Create `20260803000006_create_kb_keyword_rewrite_rules.sql`
- [ ] Apply against `chenweb_test` to verify no DDL errors
- [ ] Commit with `jj`

---

## Chunk A — Concept store

**New package:** `ChenWeb/server/api/ontology/keywords/`

### Task A1: Concept store with CRUD + status transitions

**Files to create:**
- `ChenWeb/server/api/ontology/keywords/concepts_store.go`
- `ChenWeb/server/api/ontology/keywords/concepts_store_test.go`
- `ChenWeb/server/api/ontology/keywords/nullable.go`

**Pattern:** Follow `terms/terms_store.go` exactly.

```go
type ConceptStore struct {
    DB DBX
}

// Methods:
// CreateConcept(ctx, Concept) (Concept, error)
// GetConcept(ctx, conceptID string) (Concept, error)
// ListConcepts(ctx, scope string) ([]Concept, error)
// UpdateConceptLabel(ctx, conceptID, prefLabel, gloss string) (Concept, error)
// TransitionStatus(ctx, conceptID string, from, to string) (Concept, error)
// MergeConcept(ctx, fromID, toID string) error          // sets merged_into tombstone
```

**Status transitions:** `active → provisional → merged → deprecated` (linear, no draft/review — keywords are ungoverned, per the ADR). `provisional → active` is allowed. `merged` sets `merged_into`.

**Struct:**
```go
type Concept struct {
    ConceptID   string
    PrefLabel   string
    Gloss       *string
    Scope       string
    Status      string
    MergedInto  *string
    GlossSource string
    CreateTime  time.Time
    ModifyTime  time.Time
}
```

- [ ] Write failing sqlmock test for `CreateConcept`
- [ ] Implement `ConceptStore` with `DBX` interface, column constants, scan function, validate function
- [ ] Write tests: Create, Get, List, UpdateLabel, TransitionStatus, Merge, validation (missing concept_id, invalid status transition), duplicate concept_id rejection
- [ ] Commit with `jj`

---

## Chunk B — Surface + surface_keys stores

### Task B1: Surface store

**Files to create:**
- `ChenWeb/server/api/ontology/keywords/surfaces_store.go`
- `ChenWeb/server/api/ontology/keywords/surfaces_store_test.go`

```go
type SurfaceStore struct {
    DB DBX
}

// Methods:
// CreateSurface(ctx, Surface) (Surface, error)
// GetSurface(ctx, surfaceID string) (Surface, error)
// ListSurfacesByConcept(ctx, conceptID string) ([]Surface, error)
// ListSurfacesByNormKey(ctx, normKey, scope string) ([]Surface, error)   // tier 1 candidate lookup
// UpdateSurfaceLock(ctx, surfaceID string, locked bool) error
```

**Struct:**
```go
type Surface struct {
    SurfaceID  string    // opaque: "kws_" + sha256[:12] of (concept_id + surface + label_role)
    ConceptID  string
    Surface    string    // verbatim, never only a derived key
    NormKey    string
    NormVersion int
    LabelRole  string    // pref, alt, hidden
    AliasType  string
    Lang       string
    Scope      string
    Confidence float64
    Provenance string
    Locked     bool
    Evidence   *string
    CreateTime time.Time
    ModifyTime time.Time
}
```

`surface_id` is content-derived (`"kws_" + sha256[:12]` of `concept_id + surface + label_role`), making it deterministic for idempotent upserts. The spec requires `TEXT PRIMARY KEY` (opaque, immutable).

### Task B2: Surface keys store

**Files to create:**
- `ChenWeb/server/api/ontology/keywords/surface_keys_store.go`
- `ChenWeb/server/api/ontology/keywords/surface_keys_store_test.go`

```go
type SurfaceKey struct {
    SurfaceID   string
    KeyKind     string   // alnum, sorted, phonetic, initials
    KeyValue    string
    NormVersion int
}

// Methods:
// UpsertSurfaceKeys(ctx, surfaceID string, keys []SurfaceKey) error   // DELETE + INSERT per surface
// LookupByKeyKind(ctx, keyKind, keyValue, scope string) ([]SurfaceKey, error)  // tier 2/4 lookup
```

Surface keys are derived data — they are always written alongside the surface row. `UpsertSurfaceKeys` uses a transaction: `DELETE FROM kb.keyword_surface_keys WHERE surface_id = $1; INSERT ...`.

- [ ] Write failing tests for `CreateSurface` and `UpsertSurfaceKeys`
- [ ] Implement both stores
- [ ] Write full test suites: Create, Get, ListByConcept, ListByNormKey, UpsertKeys, LookupByKeyKind, validation (invalid label_role, invalid alias_type, missing concept_id FK)
- [ ] Commit with `jj`

---

## Chunk C — Mention, unresolved, and rewrite-rule stores

### Task C1: Mention store

**File:** `ChenWeb/server/api/ontology/keywords/mentions_store.go` (+ test)

```go
type MentionStore struct {
    DB DBX
}

// InsertMention(ctx, Mention) (int64, error)       // returns mention_id
// InsertMentions(ctx, []Mention) ([]int64, error)  // batch insert
// ListMentions(ctx, ksID string, limit int) ([]Mention, error)
```

Mentions are append-only — no update, no delete. The mention collector (Chunk G) calls `InsertMentions` in batch.

### Task C2: Unresolved store

**File:** `ChenWeb/server/api/ontology/keywords/unresolved_store.go` (+ test)

```go
type UnresolvedStore struct {
    DB DBX
}

// UpsertUnresolved(ctx, normKey, scope string, surface string, contextText string) error
//   — INSERT ... ON CONFLICT (norm_key, scope) DO UPDATE SET
//     surfaces = jsonb_append(distinct surface), contexts = reservoir_sample,
//     hits = hits + 1, last_seen = NOW()
// ListUnresolved(ctx, scope string, status string, limit int) ([]Unresolved, error)
// UpdateUnresolvedStatus(ctx, normKey, scope, status string) error
```

**Key design:** `UpsertUnresolved` uses PostgreSQL `jsonb_insert` with dedup — surfaces array keeps distinct values, contexts keeps a reservoir sample of ≤5 snippets at ≤200 chars each (per spec §3.2).

### Task C3: Rewrite-rule store

**File:** `ChenWeb/server/api/ontology/keywords/rewrite_rules_store.go` (+ test)

```go
type RewriteRuleStore struct {
    DB DBX
}

// CreateRule(ctx, RewriteRule) (RewriteRule, error)
// GetRule(ctx, ruleID string) (RewriteRule, error)
// ListEnabledRules(ctx, scope string) ([]RewriteRule, error)   // enabled=true only
// UpdateRuleEnabled(ctx, ruleID string, enabled bool) error
```

**Pattern constraint (spec §3.2):** The `pattern` field must be a valid constrained pattern. Validation is a simple regex safety check: no capture groups, no backreferences — simple literal replacement patterns only. The store's `validate()` enforces this.

- [ ] Write failing tests for each store
- [ ] Implement MentionStore (batch insert, append-only)
- [ ] Implement UnresolvedStore (upsert with JSONB dedup)
- [ ] Implement RewriteRuleStore (CRUD + enabled filtering)
- [ ] Commit with `jj`

---

## Chunk D — Keyword normalizer

### Task D1: Rich keyword normalizer producing 6 key kinds

**File to create:** `ChenWeb/server/api/ontology/keywords/normalizer.go` (+ test)

The normalizer implements the spec's pipeline:

```
NFKC → strip zero-width chars → normalize dashes/quotes → collapse whitespace
→ case-fold → collapse dotted initialisms → drop possessive 's
→ strip leading articles → exception-list-aware singularization
```

Produces a `KeyBundle` with 6 keys:

| Key kind | Derivation | Used in tier |
|----------|-----------|-------------|
| `exact` | Verbatim surface, trimmed | 0 |
| `norm` | Full pipeline output | 1 |
| `alnum` | `norm` with non-alphanumeric stripped | 2 |
| `sorted` | `alnum` tokens sorted, space-joined | 2 |
| `phonetic` | Metaphone/DoubleMetaphone of `norm` | 4 |
| `initials` | First char of each `norm` token, uppercase | 4 |

```go
type KeywordKeyBundle struct {
    Exact    string
    Norm     string
    Alnum    string
    Sorted   string
    Phonetic string
    Initials string
}

type KeywordNormalizer struct {
    Version int
}

func (n *KeywordNormalizer) Normalize(surface string) KeywordKeyBundle { ... }
```

**N.B.:** This is NOT the `semid.Normalizer` (which returns a `semid.KeyBundle` with `CanonicalKey` + `[]AlternateKeys`). The `KeywordFamily.Normalizer()` method maps `KeywordKeyBundle` onto the `semid.KeyBundle`:
- `CanonicalKey` = `Norm`
- `AlternateKeys` = `[Alnum, Sorted, Phonetic, Initials]`

This mapping is intentional: the kernel's `Score()` function treats alternate keys as score 0.8, which maps exactly to spec tiers 2/4.

- [ ] Write test: "hello world" normalizes correctly through full pipeline
- [ ] Write test: NFKC unicode normalization (full-width → half-width)
- [ ] Write test: dash/quote normalization (em-dash, curly quotes → straight)
- [ ] Write test: dotted initialism collapse ("U.S.A." → "usa")
- [ ] Write test: possessive stripping ("cat's" → "cat")
- [ ] Write test: leading article stripping ("the cat" → "cat")
- [ ] Write test: 6 key kinds are all produced
- [ ] Write test: phonetic keys are stable
- [ ] Write test: initials key ("Hello World" → "HW")
- [ ] Write test: Chinese text passthrough (NFKC only, no case-fold)
- [ ] Implement the normalizer
- [ ] Commit with `jj`

---

## Chunk E — KeywordFamily (semid FamilyAdapter)

### Prerequisite: Extend `semid.Normalizer` for pluggable normalization

**File to modify:** `ChenWeb/server/api/ontology/semid/normalizer.go`

The current `Normalizer` struct has a fixed `Normalize()` method (lowercase + trim). The keyword family needs a richer pipeline (NFKC, 6 key kinds). The most surgical change: add a `NormFunc` field — when nil, the built-in logic runs unchanged; when set, it's called instead.

```go
type Normalizer struct {
    Name    string
    Version int
    NormFunc func(string) KeyBundle  // nil = use built-in
}

func (n Normalizer) Normalize(surface string) KeyBundle {
    if n.NormFunc != nil {
        return n.NormFunc(surface)
    }
    // ... existing built-in logic unchanged ...
}
```

- `TermFamily` is unchanged (NormFunc remains nil)
- `KeywordFamily.Normalizer()` sets `NormFunc` to the keyword pipeline
- No import cycle: `semid` doesn't import `keyword`; `keyword` imports `semid`

### Task E1: Implement `KeywordFamily` with tiers 0-4

**File to create:** `ChenWeb/server/api/ontology/keywords/keywordfamily.go`
**File to create:** `ChenWeb/server/api/ontology/keywords/keywordfamily_test.go`

```go
type KeywordFamily struct {
    DB                *sql.DB
    NormalizerVersion int
    ResolverMode      string   // "off", "observe", "on"
}

// FamilyAdapter implementation:
func (kf *KeywordFamily) FamilyName() string              { return "keyword" }
func (kf *KeywordFamily) Normalizer() Normalizer          { /* map KeywordNormalizer → semid.Normalizer */ }
func (kf *KeywordFamily) AutoAcceptPolicy() AutoAcceptPolicy { return AutoAcceptPolicy{Enabled: true, MinScore: 0.8, MaxCandidates: 1} }
func (kf *KeywordFamily) Scope(surface string) string     { return kbStoreID(surface) }
func (kf *KeywordFamily) CandidateNodes(ctx, surface, scope) ([]NodeCandidate, error) { /* multi-tier lookup */ }
```

### E2: Multi-tier candidate generation

`CandidateNodes` implements tiers 0-4 (tiers 5-6 deferred):

1. **Tier 0:** Exact surface match via `kb.keyword_surfaces` WHERE `surface = $1 AND scope = $2`
2. **Tier 1:** Norm key match via `kb.keyword_surfaces` WHERE `norm_key = $1 AND scope = $2`
3. **Tier 2:** Alnum/sorted key match via `kb.keyword_surface_keys` WHERE `key_kind IN ('alnum','sorted') AND key_value = $1`
4. **Tier 3:** Apply enabled rewrite rules, retry tiers 0-2 with rewritten surface
5. **Tier 4:** Initials key match via `kb.keyword_surface_keys` WHERE `key_kind = 'initials' AND key_value = $1`, scope-filtered
6. Early exit on first tier that produces candidates (not cumulative — spec says "stop at first tier with candidates")
7. For each matching row from `kb.keyword_surfaces`, reconstruct the `KeyBundle` from `norm_key` + joined `kb.keyword_surface_keys` rows
8. Return `[]NodeCandidate{NodeID: concept_id, KeyBundle: kb}`

**Tiers 5-6 deferred:** `CandidateNodes` returns empty for fuzzy candidates. The unresolved store records the miss.

### E3: ResolveSurface method

```go
func (kf *KeywordFamily) ResolveSurface(ctx context.Context, surface, scope string) (*Resolution, error)
```

End-to-end: normalize → generate candidates → run kernel `Resolve()` → write decision to `semid_decision_log` (family='keyword') → if unresolved, write to `kb.keyword_unresolved`.

**Gating on ResolverMode:** When `ResolverMode == "off"`, `ResolveSurface` returns nil immediately with no DB writes. When `"observe"`, it resolves but does not connect the resolved concept to any downstream consumer.

- [ ] Write failing test: `FamilyName()` returns `"keyword"`
- [ ] Write failing test: tier 0 exact surface match resolves
- [ ] Write failing test: tier 1 norm key match resolves
- [ ] Write failing test: tier 2 alnum key match resolves (score 0.8, auto-accepted)
- [ ] Write failing test: tier 4 initials match resolves (score 0.8, scope-filtered)
- [ ] Write failing test: no match → `deferred` verdict, unresolved row written
- [ ] Write failing test: `ResolverMode="off"` → no-op
- [ ] Write failing test: auto-accept at score 1.0 for tiers 0-1, 0.8 for tiers 2/4
- [ ] Implement `KeywordFamily`
- [ ] Write integration test: full ResolveSurface round-trip with real concepts/surfaces
- [ ] Commit with `jj`

---

## Chunk F — REST handlers + routes

### Task F1: Concept handlers

**File to create:** `ChenWeb/server/api/kbhandler/keyword_concepts_handler.go`
**File to create:** `ChenWeb/server/api/kbhandler/keyword_concepts_handler_test.go`

Following the `ontology_terms_handler.go` pattern:

| Method | Path | Handler |
|--------|------|---------|
| POST | `/kb/keyword-concepts` | `CreateKeywordConcept` |
| GET | `/kb/keyword-concepts` | `ListKeywordConcepts` |
| GET | `/kb/keyword-concepts/:concept_id` | `GetKeywordConcept` |
| PUT | `/kb/keyword-concepts/:concept_id` | `UpdateKeywordConcept` |
| POST | `/kb/keyword-concepts/:concept_id/status` | `TransitionKeywordConceptStatus` |
| POST | `/kb/keyword-concepts/:concept_id/merge` | `MergeKeywordConcept` |

Error codes: `CWB_KB_KW_001`–`CWB_KB_KW_099`

### Task F2: Surface handlers

**File to create:** `ChenWeb/server/api/kbhandler/keyword_surfaces_handler.go`

| Method | Path | Handler |
|--------|------|---------|
| POST | `/kb/keyword-surfaces` | `CreateKeywordSurface` |
| GET | `/kb/keyword-surfaces/:surface_id` | `GetKeywordSurface` |
| GET | `/kb/keyword-concepts/:concept_id/surfaces` | `ListKeywordSurfacesByConcept` |
| PUT | `/kb/keyword-surfaces/:surface_id/lock` | `LockKeywordSurface` |

Error codes: `CWB_KB_KW_100`–`CWB_KB_KW_199`

### Task F3: Rewrite-rule handlers

**File to create:** `ChenWeb/server/api/kbhandler/keyword_rewrite_rules_handler.go`

| Method | Path | Handler |
|--------|------|---------|
| POST | `/kb/keyword-rewrite-rules` | `CreateKeywordRewriteRule` |
| GET | `/kb/keyword-rewrite-rules` | `ListKeywordRewriteRules` |
| PUT | `/kb/keyword-rewrite-rules/:rule_id/enabled` | `ToggleKeywordRewriteRule` |

Error codes: `CWB_KB_KW_200`–`CWB_KB_KW_299`

### Task F4: Resolution handler

| Method | Path | Handler |
|--------|------|---------|
| POST | `/kb/keyword-resolve` | `ResolveKeywordSurface` |

Request: `{"surface": "...", "scope": "..."}` — runs `KeywordFamily.ResolveSurface` and returns the resolution.

### Task F5: Route registration

**File to modify:** `ChenWeb/server/api/routes.go`

Register all keyword routes under the existing `apiGroup`. Use the `kbhandler` package name convention.

- [ ] Implement concept handlers with sqlmock tests (create, get, list, update, status transition, merge, 400/404 cases)
- [ ] Implement surface handlers with sqlmock tests
- [ ] Implement rewrite-rule handlers with sqlmock tests
- [ ] Implement resolution handler
- [ ] Register routes
- [ ] Verify `go build` passes after route additions
- [ ] Commit with `jj`

---

## Chunk G — Config wiring + mention collector

### Task G1: KEYWORD_RESOLVER_MODE env var

**File to create:** `ChenWeb/server/api/doc-processing/keyword_config.go`

```go
func KeywordResolverModeFromEnv() string {
    raw := strings.TrimSpace(os.Getenv("KEYWORD_RESOLVER_MODE"))
    switch raw {
    case "observe", "on":
        return raw
    default:
        return "off"
    }
}
```

Following `SemanticAssociationEnabledFromEnv()` pattern from `phase_d.go`.

### Task G2: Mention collector (standalone, observe-only)

**File to create:** `ChenWeb/server/api/doc-processing/keyword_mention_collector.go`
**File to create:** `ChenWeb/server/api/doc-processing/keyword_mention_collector_test.go`

```go
type KeywordMentionCollector struct {
    DB            *sql.DB
    KeywordFamily *keywords.KeywordFamily
}
```

The mention collector is a **standalone function**, not yet wired into the Phase C pipeline. This is intentional — Track B ships `observe`-only with no downstream consumers connected. A future chunk integrates the collector into the pipeline.

- `CollectFromText(ctx, artifactRef, text, ksID string) error`: Tokenizes text (word-boundary, skip stopwords, keep tokens 2-50 chars), calls `KeywordFamily.ResolveSurface` for each token. Observes only — writes mentions, surfaces, keys, unresolved backlog. No results connected to retrieval.
- Self-gates: returns nil immediately if `keywords.ResolverMode() == "off"` or `DB == nil`.

**Token extraction heuristic:** Split on whitespace/punctuation, keep `[a-zA-Z0-9一-鿿぀-ゟ゠-ヿ]{2,50}`, skip ~50 hardcoded English stopwords. Not full NLP — just enough to measure volume in observe mode.

- [ ] Write failing test: `CollectFromText` NOOPs when mode is `off`
- [ ] Write failing test: `CollectFromText` in `observe` mode writes mentions for each token
- [ ] Write failing test: duplicate tokens within one text produce deduplicated mentions
- [ ] Write failing test: matching existing concept → surface/keys written
- [ ] Write failing test: unknown token → unresolved backlog incremented
- [ ] Implement `KeywordMentionCollector`
- [ ] Commit with `jj`

---

## Chunk H — Exit criteria + verification

### Task H1: Exit criteria test file

**File to create:** `ChenWeb/server/api/ontology/keywords/keyword_exit_test.go`

Maps spec §10 acceptance criteria (from the DR16 spec) to named test pointers:

1. **Concept CRUD:** Create, Get, List, Update label, Status transitions, Merge → tombstone
2. **Surface CRUD:** Create with norm_key + keys, List by concept, List by norm_key
3. **Surface key derivation:** Keys are deterministically derived from surface + normalizer version
4. **Normalizer stability:** Same surface + same version = same keys
5. **Kernel resolution:** Tier 0 exact match resolves; tier 1 norm match resolves; tier 2 alnum match resolves (auto-accept); unknown surface defers to unresolved
6. **ResolverMode gate:** `off` = no-op; `observe` = resolve but don't connect; `on` = deferred
7. **Mention collector:** Writes mentions in observe mode; idempotent; deduplicates
8. **Rewrite rules:** Enabled rule rewrites surface before tiers 0-2 retry; disabled rule is ignored
9. **Unresolved backlog:** Upsert accumulates distinct surfaces; reservoir sample caps at 5

### Task H2: Full suite verification

```bash
go build ./...
go vet ./server/api/ontology/keywords/... ./server/api/ontology/semid/... ./server/api/doc-processing/...
gofmt -l server/api/ontology/keywords server/api/ontology/semid server/api/doc-processing
go test ./server/api/ontology/keywords/... ./server/api/ontology/semid/... -count=1
```

**Baseline contract:** Pre-existing failures are unchanged. All new keyword tests pass. `gofmt -l` empty for keyword-owned files.

- [ ] Write exit criteria test file
- [ ] Run full suite
- [ ] Fix any regressions
- [ ] Commit with `jj`

---

## 2. Verification (after every chunk)

```bash
go build ./...
go vet ./server/api/ontology/keywords/... ./server/api/ontology/semid/...
gofmt -l server/api/ontology/keywords
go test ./server/api/ontology/keywords/... -count=1
```

---

## 3. Definition of done

P3 Track B may be declared complete when:

1. All 6 keyword tables exist and pass migration in `chenweb_test`
2. Concept, surface, surface_keys, mention, unresolved, and rewrite-rule stores are CRUD-complete and sqlmock-tested
3. Keyword normalizer produces 6 stable key kinds per the spec
4. `KeywordFamily` passes kernel resolution tests for tiers 0-4
5. `KEYWORD_RESOLVER_MODE` gates resolution: `off` = no-op, `observe` = resolve + mention + backlog, `on` = deferred (stubbed)
6. REST handlers for concepts, surfaces, rewrite rules, and `ResolveSurface` are built and route-registered
7. Mention collector writes idempotent, deduplicated mentions in `observe` mode
8. Exit criteria map all in-scope items to named tests
9. `go build`, `go vet`, `gofmt` clean on keyword-owned packages
10. All commits are linear in `jj log` and committed

---

## 4. Knowledge and documentation impact

**What knowledge changed?** P3 Track B transitions from design-only to implemented-as-observe-mode. The keyword lexicon is now the second `semid` kernel instantiation.

**Which docs/specs/ADRs/tests are affected?**
- Spec `2026080101` — implementation status annotation; carry-forward list added
- ADR `2026072901` — §8.3.6 status update (P3 Track B built, observe mode)
- Handoff `2026073002` — post-handoff update recording Track B completion
- P3 implementation log — new entry for Track B build record
- `Capsules/coding-capsules/ontology/+CAPSULE.md` — keyword family section

**Which docs should be updated after completion?**
- Spec `2026080101` — mark "Implemented (observe mode)"
- ADR `2026072901` — Track B status
- Handoff `2026073002` — post-handoff update
- Ontology capsule — keyword family entry

**What intentionally left undocumented?** Fuzzy tiers 5-6 (spec design exists but deferred), reconciliation batch workflow, `aligns_to_term` bridge, `on` mode semantics.

---

## 5. Risk notes

1. **Go module dependency for NFKC**: `golang.org/x/text/unicode/norm` is needed for keyword normalization. Verify it's already in `go.mod` (likely transitive via Echo). If not, run `go get golang.org/x/text`.

2. **Phonetic key stub**: The spec calls for a `phonetic` key kind. A full Double Metaphone implementation requires a new dependency. The plan uses a stub (first letter + first 4 consonants) that satisfies the 6-key-kind contract. Real metaphone is deferred — document this in the implementation log.

3. **Surface ID collision risk**: `sha256[:12]` of `(concept_id + surface + label_role)` has a collision probability of ~1 in 2^48 — acceptable for this scale. If a collision occurs, the UNIQUE PK constraint catches it at insert time.

4. **`kb.keyword_unresolved` JSONB growth**: The `surfaces` array and `contexts` reservoir sample must be capped (max 10 distinct surfaces, max 5 context snippets at ≤200 chars each) in `UnresolvedStore.Upsert` to prevent unbounded growth.

5. **`semid.Normalizer` interface change**: Adding the `NormFunc` field is backward-compatible (nil = existing behavior). `TermFamily` is unchanged. This is a ~10-line change in `normalizer.go` — the smallest possible extension point.

6. **Mention collector not pipeline-wired**: Track B ships the collector as a standalone `CollectFromText()` function. It is NOT registered as a `PostProcessIndexer` in `productionProcessorSpecs`. This is intentional — observe mode means measuring volume, not changing production behavior. Pipeline integration is a follow-up task.
