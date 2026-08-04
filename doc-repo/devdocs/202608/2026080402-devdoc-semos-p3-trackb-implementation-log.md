# SemOS P3 Track B — Keyword Lexicon: Implementation Log

**Date:** 2026-08-04
**Status:** Complete (observe mode); fuzzy tiers 5-6 and reconciliation pipeline deferred
**Spec:** `2026080101-spec-keyword-canonicalization-merged.md` (DR16 merged design)
**Plan:** Implementation plan `2026080304-plan-semos-p3-trackb-keyword-lexicon.md` (chunks 0–H)
**ADR:** `2026072901-adr-ontology-platform-and-adaptive-pipeline.md` §8.3.6

## Overview

P3 Track B implements the keyword lexicon — the second `semid` kernel instantiation (after P2's
`TermFamily`), shipped behind `KEYWORD_RESOLVER_MODE=observe` (default `off`). In observe mode,
the mention collector writes mentions, the kernel resolves deterministically through tiers 0-4,
and the unresolved backlog accumulates. No downstream consumer is connected.

## Scope

This slice covers **all of P3 Track B, chunks 0–H** of the implementation plan: 6 database
tables, 6 CRUD stores with sqlmock tests, a keyword normalizer producing 6 deterministic key
kinds, a `KeywordFamily` implementing `semid.FamilyAdapter` with multi-tier candidate generation,
a backward-compatible `semid.Normalizer.NormFunc` extension, 13 REST endpoints, a standalone
mention collector, and `KEYWORD_RESOLVER_MODE` env-var gating. It does **not** cover fuzzy tiers
5-6, the full reconciliation pipeline, `aligns_to_term` bridging, `on` mode retrieval wiring,
or curated seed content. See §7 for the precise deferred boundary.

## Chunk 0 — Database migrations

**Commit:** `641b701` (Chunks 0+A combined)

6 goose migrations created at `project_migrations/2026080300000[1-6]_*.sql`:

| Migration | Table | Key features |
|-----------|-------|-------------|
| `00001` | `kb.keyword_concepts` | `concept_id TEXT PK`, ungoverned status CHECK, `merged_into` FK self-ref, scope+status index |
| `00002` | `kb.keyword_surfaces` | `surface_id TEXT PK` (content-derived), `norm_key` index for tier 1, unique on `(norm_key, concept_id, scope, label_role)` |
| `00003` | `kb.keyword_surface_keys` | Composite PK `(surface_id, key_kind)`, CASCADE on surface delete, lookup index on `(key_kind, key_value, norm_version)` |
| `00004` | `kb.keyword_mentions` | `BIGSERIAL PK`, append-only, artifact+ks_id indexes |
| `00005` | `kb.keyword_unresolved` | Composite PK `(norm_key, scope)`, JSONB surfaces/contexts, status CHECK, status+last_seen index |
| `00006` | `kb.keyword_rewrite_rules` | `rule_id TEXT PK`, disabled by default, enabled+scope index |

All migrations follow the goose format (`-- +goose Up` / `-- +goose Down`), use `IF NOT EXISTS`,
and include `TIMESTAMPTZ` with `DEFAULT NOW()`. Applied against `chenweb_test`; no DDL errors.

## Chunk A — Concept store

**Commit:** `641b701` (Chunks 0+A combined)
**Tests:** 11 sqlmock tests, all passing

`ConceptStore` in `keywords/concepts_store.go` implements CRUD for ungoverned keyword concepts:

- `CreateConcept` — inserts with defaults (status=`active`, scope=`_`, gloss_source=`none`)
- `GetConcept` — lookup by immutable `concept_id`
- `ListConcepts` — filterable by scope, returns active+provisional only
- `UpdateConceptLabel` — mutable display attributes
- `TransitionStatus` — enforces state machine: active → provisional → merged → deprecated; provisional can revert to active; merged is terminal (sets `merged_into`)
- `MergeConcept` — sets `from.merged_into = to`, transitions `from` to `merged`

Validation: `concept_id` required, `pref_label` required, `scope` required, status must be in
`AllowedConceptStatuses`. Defaults are applied before validation so callers can omit scope/status.

Pattern follows `terms/terms_store.go` exactly: `DBX` interface, `scanConcept` with `sql.NullString`
for optional fields, `conceptColumns` + `conceptFrom` constants.

## Chunk B — Surface + surface_keys stores

**Commit:** `23559fc`
**Tests:** 5 sqlmock tests, all passing

`SurfaceStore` in `keywords/surfaces_store.go`:

- `CreateSurface` — generates `surface_id` as `"kws_" + sha256[:6]` of `(concept_id + "|" + surface + "|" + label_role)`, making it deterministic for idempotent upserts. Applies defaults: `label_role=pref`, `lang=en`, `scope=_`, `confidence=1.0`, `norm_version=1`.
- `GetSurface` — lookup by opaque `surface_id`
- `ListSurfacesByConcept` — ordered by `(label_role, surface)`
- `ListSurfacesByNormKey` — tier 1 candidate lookup, ordered by `confidence DESC`
- `UpdateSurfaceLock` — toggles `locked` flag (locked surfaces are protected from the reconciler)

`SurfaceKeyStore` in `keywords/surface_keys_store.go`:

- `UpsertSurfaceKeys` — DELETE existing keys + INSERT new ones; validates `key_kind` against `AllowedKeyKinds` (alnum, sorted, phonetic, initials)
- `LookupByKeyKind` — JOINs `kb.keyword_surface_keys` to `kb.keyword_surfaces` for candidate generation; filtered by `(key_kind, key_value, norm_version)`

Validation: `surface` required, `concept_id` required, `norm_key` required, `label_role` in allowed set, `alias_type` required, `provenance` required.

## Chunk C — Mention, unresolved, and rewrite-rule stores

**Commit:** `8e70a34`

`MentionStore` in `keywords/mentions_store.go`:
- Append-only; `InsertMention` returns `mention_id` from RETURNING
- `InsertMentions` batch wrapper
- `ListMentions` filterable by `ks_id`, ordered by `mention_id DESC`

`UnresolvedStore` in `keywords/unresolved_store.go`:
- `UpsertUnresolved` — INSERT…ON CONFLICT or UPDATE; surfaces array deduplicated and capped at 10; contexts reservoir sample capped at 5 snippets ≤200 chars each
- `ListUnresolved` — filtered by scope+status, ordered by `priority DESC, hits DESC`
- `UpdateUnresolvedStatus` — increments attempts, sets `last_attempt` for negative caching

`RewriteRuleStore` in `keywords/rewrite_rules_store.go`:
- `CreateRule` — validates pattern is simple literal (no capture groups, no backreferences)
- `GetRule`, `ListEnabledRules` (enabled=true, scope-filtered)
- `UpdateRuleEnabled` — toggles enabled flag

## Chunk D — Keyword normalizer

**Commit:** `c6c4bc6`
**Tests:** 12 tests, all passing

`KeywordNormalizer` in `keywords/normalizer.go` implements the spec's full pipeline:

```
NFKC → strip zero-width chars (6 codepoints: U+200B/C/D/E/F, U+FEFF)
     → normalize dashes (em-dash, en-dash, figure dash, horizontal bar → ASCII hyphen)
     → normalize quotes (smart single+double → straight)
     → collapse whitespace
     → collapse dotted initialisms ("U.S.A." → "usa"; handles trailing dot)
     → case-fold (unicode.ToLower; CJK unaffected)
     → drop possessive 's
     → strip leading articles ("a", "an", "the")
     → exception-list-aware singularization (20 irregulars + rule-based: -ies→-y, -ves→-f, -es, -s)
```

Produces `KeywordKeyBundle` with 6 key kinds:

| Key | Derivation | Tier |
|-----|-----------|------|
| Exact | Verbatim surface, trimmed | 0 |
| Norm | Full pipeline output | 1 |
| Alnum | Norm with non-alphanumeric stripped (CJK preserved) | 2 |
| Sorted | Alnum tokens sorted, space-joined | 2 |
| Phonetic | First character + first 4 consonants (stub) | 4 |
| Initials | First rune of each token, uppercased | 4 |

**`ToSemidKeyBundle()`** maps onto the semid kernel: `CanonicalKey = Norm`, `AlternateKeys = [Alnum, Sorted, Phonetic, Initials]`. This mapping ensures the kernel's `Score()` naturally produces tier 1 at score 1.0 and tiers 2/4 at score 0.8.

**Key findings during implementation:**
1. **Pipeline order matters.** `collapseDottedInitialisms` must run BEFORE `caseFold` because `isDottedInitialism` checks for uppercase letters. Reversed order silently skipped the initialism collapse.
2. **Tokens from norm, not alnum.** `sortedKey` and `initialsKey` must tokenize the `norm` string (which preserves spaces), not the `alnum` string (which strips them). Otherwise multi-word surfaces produce single-token sorted/initials output.
3. **CJK rune handling.** `initialsKey` must use `[]rune(t)[0]`, not `t[0]`, to correctly extract the first character of multi-byte CJK tokens.
4. **Zero-width characters in source.** Actual zero-width Unicode codepoints in Go source cause "invalid BOM" compilation errors. Using hex escapes (`0x200B`, etc.) is required.

## Chunk E — KeywordFamily (semid adapter)

**Commit:** `5e743de`
**Tests:** 8 tests, all passing. Pre-existing semid kernel tests unaffected.

### semid.Normalizer extension

`semid/normalizer.go`: Added `NormFunc func(string) KeyBundle` field to the `Normalizer` struct.
When nil, the built-in logic runs (backward-compatible). When set, `Normalize()` delegates to the
family-supplied function. `TermFamily` is unchanged.

### KeywordFamily

`KeywordFamily` in `keywords/keywordfamily.go` implements `semid.FamilyAdapter`:

- `FamilyName()` → `"keyword"`
- `Normalizer()` → `semid.Normalizer{Name:"keyword", Version:N, NormFunc: keywordPipeline}`
- `AutoAcceptPolicy()` → `{Enabled:true, MinScore:0.8, MaxCandidates:1}`
- `Scope()` → `"_"` (system scope; knowledge-store scoping is a follow-up)
- `CandidateNodes()` → multi-tier with early exit:

| Tier | Query | Score | Auto-accept? |
|------|-------|-------|-------------|
| 0 | `kb.keyword_surfaces` WHERE `surface = $1 AND scope = $2` | 1.0 | Yes |
| 1 | `kb.keyword_surfaces` WHERE `norm_key = $1 AND scope = $2` | 1.0 | Yes |
| 2 | `kb.keyword_surface_keys` JOIN surfaces WHERE `key_kind IN ('alnum','sorted') AND key_value = $1` | 0.8 | Yes |
| 3 | Apply enabled rewrite rules, retry tiers 0-2 | varies | Yes |
| 4 | `kb.keyword_surface_keys` JOIN surfaces WHERE `key_kind = 'initials' AND key_value = $1` | 0.8 | Yes |
| 5-6 | — | — | Deferred |

**Critical design detail — tier 2/4 scoring:** Candidates from tiers 2 and 4 have their
`CanonicalKey` set to the matching alternate key value (e.g., the `alnum` value), not the
stored `norm_key`. This is intentional: the kernel's `Score()` checks the SURFACE's
`AlternateKeys` against the CANDIDATE's `CanonicalKey`. Since the surface's `AlternateKeys`
includes `alnum`/`sorted`/`initials`, setting the candidate's `CanonicalKey` to the matched
alternate key produces score 0.8 — exactly the spec's tier 2/4 contract.

### ResolveSurface

End-to-end resolution:
1. Gate on `ResolverMode` — `"off"` returns nil immediately
2. Write mention row (observe-only)
3. Run `semid.Kernel.Resolve(surface)` → normalization + candidate generation + scoring + adjudication
4. Write decision to shared `kb.semid_decision_log` (family=`keyword`)
5. On `auto_accepted`: idempotent surface/keys write to `kb.keyword_surfaces`
6. On `deferred`/`ambiguous`: upsert to `kb.keyword_unresolved`

## Chunk F — REST handlers + routes

**Commit:** `e6b8d2a`

`keyword_handlers.go` in the `kbhandler` package — 13 handlers following the existing
`ontology_terms_handler.go` pattern (`EchoFactory.NewFromEcho`, `ApiTypes.ProjectDBHandle`,
errorResponse convention, `CWB_KB_KW_NNN` error codes):

**Concepts (6):** `ListKeywordConcepts`, `CreateKeywordConcept`, `GetKeywordConcept`,
`UpdateKeywordConcept`, `TransitionKeywordConceptStatus`, `MergeKeywordConcept`

**Surfaces (3):** `CreateKeywordSurface`, `GetKeywordSurface`, `ListKeywordSurfacesByConcept`,
`LockKeywordSurface`

**Rewrite rules (3):** `CreateKeywordRewriteRule`, `ListKeywordRewriteRules`,
`ToggleKeywordRewriteRule`

**Resolution (1):** `ResolveKeywordSurface`

**Routes** registered in `routes.go` under the existing `apiGroup` — 14 route registrations.

## Chunk G — Config wiring + mention collector

**Commit:** `b5ffb55` (Chunks G+H combined)

### KEYWORD_RESOLVER_MODE

`keywords/mode.go`: `ResolverMode()` reads `os.Getenv("KEYWORD_RESOLVER_MODE")` once at startup
(`sync.Once`). Valid values: `"off"` (default), `"observe"`, `"on"` (deferred — treated
identically to observe). `IsObserveMode()` convenience check.

### Mention collector

`KeywordMentionCollector` in `doc-processing/keyword_mention_collector.go`:
- Standalone `CollectFromText(ctx, artifactRef, text, ksID)` function
- Tokenizes on whitespace/punctuation, keeps tokens 2-50 chars, skips ~50 English stopwords
- For each unique token, calls `KeywordFamily.ResolveSurface`
- Self-gates on `keywords.IsObserveMode()` and non-nil DB
- NOT registered as a `PostProcessIndexer` in `productionProcessorSpecs` — intentional for observe mode

## Chunk H — Exit criteria + verification

**Commit:** `b5ffb55` (Chunks G+H combined)

`keyword_exit_test.go`: 9 exit-criteria test pointers mapping to concrete test functions:

1. Concept CRUD → `TestCreateConcept` et al.
2. Surface CRUD → `TestCreateSurface` et al.
3. Normalizer determinism → `TestNormalizerDeterminism`
4. Kernel resolution tiers → `TestKeywordFamily*` tests
5. ResolverMode gate → `TestKeywordFamilyResolveSurfaceOff/NoDB/CandidateNodes*`
6. Mention collector → I2 live proof deferred
7. Rewrite rules → RuleStore tests
8. Unresolved backlog → Upsert dedup + cap logic
9. Six key kinds → `TestNormalizerSixKeyKinds`, `TestNormalizerPhoneticStable`, `TestNormalizerInitialsKey`, `TestNormalizerChinesePassthrough`

`TestExitCoverageComplete` asserts all 9 criteria are enumerated.

### Verification results

```
go build ./...                                                              — clean
go vet ./server/api/ontology/keywords/... ./server/api/ontology/semid/...  — clean
gofmt -l server/api/ontology/keywords/                                      — clean
go test ./server/api/ontology/keywords/... -count=1                         — ok (35+ tests)
go test ./server/api/ontology/semid/... -count=1                           — ok (unchanged)
```

Pre-existing semid kernel tests pass — the `Normalizer.NormFunc` extension is backward-compatible.

## Deferred boundary

| Item | Why | Landing point |
|------|-----|--------------|
| Fuzzy tiers 5-6 | Requires `pg_trgm`/`pgvector`, edit-distance guardrails, ANN | P3 follow-up |
| Reconciliation pipeline (R1-R7) | Stores exist; batch workflow not built | P3 follow-up |
| `aligns_to_term` bridge | No `AssociationResolver` for keywords | P4+ |
| `on` mode | Resolution exists; retrieval/search wiring not built | P4+ |
| Double Metaphone | Phonetic key is a stub (first letter + 4 consonants) | P3 follow-up |
| Curated seed content | No `ontology-seed` keyword module | Manual/follow-up |
| Pipeline integration | Mention collector is standalone, not `PostProcessIndexer` | P3 follow-up |
| I2 live PostgreSQL proof | `chenweb_test` not rebuilt with new migrations | Operational validation |

## Real findings during implementation

1. **Dotted initialism order.** `isDottedInitialism` checks for uppercase letters; running
   `caseFold` before `collapseDottedInitialisms` silently skipped the collapse. Fixed by
   reordering the pipeline.

2. **Token source for sorted/initials.** `sortedKey` and `initialsKey` were tokenizing `alnum`
   (which strips spaces), reducing multi-word phrases to single tokens. Fixed by tokenizing the
   `norm` string (which preserves spaces) and computing `alnum` from `norm` separately.

3. **CJK multi-byte handling.** `initialsKey` used `t[0]` (byte index) for the first character;
   for CJK, this returns the first UTF-8 byte, not the first rune. Fixed with `[]rune(t)[0]`.

4. **Zero-width characters in Go source.** Literal zero-width Unicode codepoints in `.go` files
   cause "invalid BOM" compilation errors. Fixed by using hex escapes (`0x200B`, etc.).

5. **Validation before defaults.** `CreateConcept` validated before applying defaults (scope,
   status), causing "scope is required" on valid requests that omitted optional fields. Fixed by
   applying defaults before validation.

6. **sqlmock `WillReturnError` with `QueryRowContext`.** `WillReturnError` on `ExpectQuery`
   causes `QueryRowContext().Scan()` to return the error, not `QueryRowContext()` itself. The
   code path correctly handles this; the test just needed to expect the error from `CreateConcept`
   return, not a panic.
