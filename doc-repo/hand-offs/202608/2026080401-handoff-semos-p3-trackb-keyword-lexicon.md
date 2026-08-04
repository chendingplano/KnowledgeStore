# SemOS P3 Track B — Keyword Lexicon: Session Handoff

Date: 2026-08-04

## Scope

This session implemented P3 Track B — the keyword lexicon, the second `semid` kernel
instantiation (DR15/DR16). All code ships behind `KEYWORD_RESOLVER_MODE=observe` (default
`off`): in observe mode, the mention collector writes mentions, the kernel resolves
deterministically through tiers 0-4, and the unresolved backlog accumulates. **No downstream
consumer is connected.** This is pure measurement infrastructure — the `on` mode that links
resolution to retrieval, search payloads, and `aligns_to_term` alignment is deferred.

This handoff exists to capture **exactly what was built and what was deliberately left
unbuilt**, so a future session can resume from an accurate baseline.

## Document lineage (read in this order if picking this up cold)

1. ADR `2026072901-adr-ontology-platform-and-adaptive-pipeline.md` — consolidated architecture;
   §8.3.6 defines P3 (assertions + keyword lexicon) and §8.3.7–§8.3.10 define P4–P7. This is
   the current source of truth.
2. Spec `2026080101-spec-keyword-canonicalization-merged.md` (DR16) — the merged keyword design:
   4-layer identity stack, 6-table schema, 8-tier working mode, 7-stage reconciliation
   pipeline. **Design only; this session built the first slice of it.**
3. Plan `2026080102-plan-semos-p3-assertions-evidence-and-phase-d-association.md` — the
   original P3 plan covering Track A (assertions/evidence/Phase D, complete) with Track B
   (keyword lexicon) explicitly deferred. This session's work is the Track B follow-up.
4. Implementation plan: `../../plan/202608/2026080304-plan-semos-p3-trackb-keyword-lexicon.md`
   (the plan executed this session — see the workspace plan file at
   `.claude/plans/synthetic-gliding-wave.md`).

## What was built (7 commits, linear jj history, pushed to origin/main)

### Commit chain (ChenWeb)

```
b5ffb55 feat(keyword): add KEYWORD_RESOLVER_MODE config, mention collector, and exit criteria
e6b8d2a feat(keyword): add REST handlers and routes for keyword lexicon
5e743de feat(keyword): add KeywordFamily semid adapter and extend semid Normalizer
c6c4bc6 feat(keyword): add keyword normalizer with 6 key kinds
8e70a34 feat(keyword): add mention, unresolved, and rewrite-rule stores
23559fc feat(keyword): add surface and surface_keys stores
641b701 feat(keyword): add concept store with CRUD and sqlmock tests
```

### New package: `ChenWeb/server/api/ontology/keywords/`

| File | Purpose |
|------|---------|
| `nullable.go` | `nullableString`, `nullableFloat64`, `nullableBool` helpers |
| `concepts_store.go` | `ConceptStore` — CRUD + status transitions + merge (ungoverned lifecycle) |
| `surfaces_store.go` | `SurfaceStore` — CRUD, lookup by norm_key (tier 1), lock toggle |
| `surface_keys_store.go` | `SurfaceKeyStore` — upsert derived keys, lookup by key kind (tiers 2/4) |
| `mentions_store.go` | `MentionStore` — append-only, batch insert |
| `unresolved_store.go` | `UnresolvedStore` — upsert with JSONB dedup + reservoir sampling |
| `rewrite_rules_store.go` | `RewriteRuleStore` — CRUD + enabled filtering |
| `normalizer.go` | `KeywordNormalizer` — NFKC pipeline producing 6 key kinds (exact, norm, alnum, sorted, phonetic, initials) |
| `keywordfamily.go` | `KeywordFamily` — `semid.FamilyAdapter` implementation with tiers 0-4 candidate generation + `ResolveSurface` |
| `mode.go` | `KEYWORD_RESOLVER_MODE` env-var reader (`off`/`observe`/`on`) |
| `concepts_store_test.go` | 11 sqlmock tests |
| `surfaces_store_test.go` | 5 sqlmock tests |
| `normalizer_test.go` | 12 tests (pipeline steps, determinism, CJK passthrough, key mapping) |
| `keywordfamily_test.go` | 8 tests (interface contract, mode gating, key bundle mapping) |
| `keyword_exit_test.go` | 9 exit-criteria test pointers |

### Modified files

| File | Change |
|------|--------|
| `semid/normalizer.go` | Added `NormFunc func(string) KeyBundle` field — nil = built-in, set = family-supplied pipeline. Backward-compatible; `TermFamily` unchanged. |
| `kbhandler/keyword_handlers.go` | 13 REST handlers (concepts, surfaces, rewrite rules, resolution) |
| `routes.go` | 14 route registrations under `/api/v1/kb/keyword-*` |
| `doc-processing/keyword_mention_collector.go` | Standalone `KeywordMentionCollector.CollectFromText` — observe-mode-only, not pipeline-wired |
| `project_migrations/2026080300000[1-6]_*.sql` | 6 goose migrations for `kb.keyword_*` tables |

### Test results

```
ok  github.com/chendingplano/deepdoc/server/api/ontology/keywords  0.006s
ok  github.com/chendingplano/deepdoc/server/api/ontology/semid     0.004s
```

- **Keywords package:** all store, normalizer, keywordfamily, and exit-criteria tests pass (35+ tests)
- **Semid package:** all pre-existing kernel tests pass; `Normalizer` extension is backward-compatible
- `go build ./...`, `go vet`, `gofmt -l` — clean on all affected packages

### 6 database tables (migrations `20260803000001`–`20260803000006`)

| Table | Key | Purpose |
|-------|-----|---------|
| `kb.keyword_concepts` | `concept_id TEXT PK` | Opaque, immutable concept identity |
| `kb.keyword_surfaces` | `surface_id TEXT PK` (content-derived: `kws_<sha256[:12]>`) | Verbatim surface forms + norm_key index |
| `kb.keyword_surface_keys` | `(surface_id, key_kind) PK` | 4 derived alternate keys (alnum, sorted, phonetic, initials) |
| `kb.keyword_mentions` | `mention_id BIGSERIAL PK` | Append-only evidence queue |
| `kb.keyword_unresolved` | `(norm_key, scope) PK` | Backlog with capped JSONB surfaces/contexts |
| `kb.keyword_rewrite_rules` | `rule_id TEXT PK` | Pattern-based rewrite rules (tier 3), disabled by default |

## Architecture: how the pieces connect

```
KEYWORD_RESOLVER_MODE (env var, default "off")
   │
   ├── "off" → KeywordFamily.CandidateNodes returns nil (no DB queries)
   │           ResolveSurface returns nil (no-op)
   │
   └── "observe" → KeywordMentionCollector.CollectFromText
                   │
                   ├── Tokenizes text (word-boundary, skip stopwords, 2-50 chars)
                   ├── For each token → KeywordFamily.ResolveSurface
                   │
                   └── ResolveSurface internally:
                         ├── Writes mention → kb.keyword_mentions
                         ├── Runs semid.Kernel.Resolve(surface)
                         │     ├── Normalizer().Normalize(surface) → 6-key bundle
                         │     │     └── CanonicalKey=norm, AlternateKeys=[alnum,sorted,phonetic,initials]
                         │     ├── CandidateNodes(surface, scope)
                         │     │     ├── Tier 0: exact surface match (score 1.0)
                         │     │     ├── Tier 1: norm_key match (score 1.0)
                         │     │     ├── Tier 2: alnum/sorted key match (score 0.8)
                         │     │     ├── Tier 3: rewrite rules + retry tiers 0-2
                         │     │     ├── Tier 4: initials key match (score 0.8)
                         │     │     └── Tiers 5-6: deferred → empty
                         │     └── Adjudicate(matches, AutoAcceptPolicy{MinScore:0.8, MaxCandidates:1})
                         │           ├── Single match ≥ 0.8 → auto_accepted
                         │           ├── Ambiguous/tied → ambiguous
                         │           └── No matches → deferred
                         ├── Writes decision → kb.semid_decision_log (family='keyword')
                         ├── If auto_accepted: idempotent surface/keys write → kb.keyword_surfaces
                         └── If deferred/ambiguous: upsert → kb.keyword_unresolved
```

## Deferred boundary (explicit — what was deliberately not built)

### Tier-level deferrals

| Item | Why deferred | Where it lands |
|------|-------------|---------------|
| **Fuzzy tiers 5-6** (trigram/vector blocking, edit-distance filtering, ANN) | The spec §5.1 defines guardrails (digit veto, canonical veto, negation/affix veto, length-gated edit distance) that require `pg_trgm` and `pgvector` extensions plus significant candidate-scoring code. The tier 0-4 deterministic path proves the kernel integration works. | P3 follow-up or P4 |
| **Full reconciliation pipeline** (R1-R7: harvest → prune → block → assemble → decide → validate → apply) | The stores and kernel pipeline exist; the batch-reconciliation CLI/workflow that runs these 7 stages against a backlog of `kb.keyword_unresolved` rows is not built. This reuses the DR5/DR6/DR7 backlog-drain patterns from P3 Track A. | P3 follow-up |
| **`aligns_to_term` bridge** | No `AssociationResolver` for keywords exists. Keyword concepts resolved by the kernel are not linked to governed ontology terms. The DR16 spec describes this as `kb.keyword_concepts.aligns_to_term` + the DR9 assertion/evidence model. | P4+ |
| **`on` mode** | `ResolveSurface` in observe mode writes mentions, surfaces, keys, and unresolved backlog but does not attach resolved concepts to search payloads, retrieval indices, or any downstream consumer. The `on` mode gate exists in `ResolverMode()` but is treated identically to observe mode — the wiring to retrieval/search is not built. | P4+ |

### Feature-level deferrals

| Item | Why deferred | Where it lands |
|------|-------------|---------------|
| **Context-token disambiguation** (spec §5.2) | The IDF-weighted overlap-with-margin heuristic for disambiguating homonyms (`ML` → machine learning or millilitre) requires context extraction from document text around the mention. The mention collector today sends empty context. | Later |
| **Phonetic key (full Double Metaphone)** | The current `phoneticKey()` is a stub: first character + first 4 consonants. A proper Double Metaphone requires a new dependency or significant code. The stub satisfies the 6-key-kind contract and produces a stable, deterministic key for tier 4 matching. | P3 follow-up |
| **Curated seed content** | No `ontology-seed` keyword module exists. The initial keyword concepts and surfaces must be authored manually through the REST API. The seed command (`server/cmd/ontology-seed/`) has no keyword module definition. | Manual / follow-up |
| **Pipeline integration** | `KeywordMentionCollector` is a standalone `CollectFromText()` function. It is NOT registered as a `PostProcessIndexer` in `productionProcessorSpecs`. This is intentional — observe mode means measuring volume without changing production behavior. | P3 follow-up |
| **Batch adjudication UI** | Admin surfaces for the reconciliation backlog (`kb.keyword_unresolved`) are not built. The REST handlers cover CRUD for concepts, surfaces, and rewrite rules, but not batch operations on the unresolved queue. | P3 follow-up |
| **Rewrite-rule auto-promotion** | Tier 3 rewrite rules are authored manually through the REST API. No auto-promotion from validated reconciliation decisions exists. | P3 follow-up |
| **Multi-process reload** | `KEYWORD_RESOLVER_MODE` is read once at startup (`sync.Once`). Changing it requires a restart. | Follow-up |

### What the deferred boundary means operationally

- The keyword lexicon **builds, passes tests, and can be deployed** with zero production impact (mode defaults to `off`).
- Setting `KEYWORD_RESOLVER_MODE=observe` enables the mention collector and kernel resolution. This **measures volume** — how many keyword mentions appear in document text, how many resolve deterministically vs. defer to the backlog — but **changes no downstream behavior**.
- The unresolved backlog (`kb.keyword_unresolved`) **accumulates indefinitely** in observe mode. No batch reconciliation drains it. The table has a `status` column and `attempts` counter ready for the reconciliation pipeline; the schema and store are built, the workflow is not.
- The tier 0-4 deterministic path is **provably correct** (unit-tested through sqlmock + normalizer fixtures). The kernel integration with `semid` is **real and tested** — `KeywordFamily` is a genuine `FamilyAdapter` implementation, not a stub.
- I2 (live PostgreSQL proof) was not run — the `chenweb_test` database was not rebuilt with the new migrations, and no live resolution was exercised against real document text. This is the operational-validation gap.

## Related documents

- **ADR:** `KnowledgeStore/doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md` — §8.3.6 (P3), §8.3.7 (P4), §8.3.9 (P6), §8.3.10 (P7)
- **Spec:** `KnowledgeStore/doc-repo/specs/202608/2026080101-spec-keyword-canonicalization-merged.md` — DR16 merged keyword design (needs implementation-status update)
- **P3 Track A plan:** `KnowledgeStore/doc-repo/plan/202608/2026080102-plan-semos-p3-assertions-evidence-and-phase-d-association.md` — Track B deferred section
- **P3 Track A impl log:** `KnowledgeStore/doc-repo/devdocs/202608/2026080103-devdoc-semos-p3-implementation-log.md`
- **P5 handoff:** `KnowledgeStore/doc-repo/hand-offs/202607/2026073002-handoff-semos-ontology-status.md` — the master status handoff (needs an update for P3 Track B completion)
- **Semid kernel:** `ChenWeb/server/api/ontology/semid/` — `kernel.go`, `normalizer.go`, `termfamily.go`, `score.go`, `adjudicate.go`, `merge.go`
- **TermFamily reference:** `ChenWeb/server/api/ontology/semid/termfamily.go` — the first (and until this session, only) `FamilyAdapter` implementation
- **Implementation plan:** `../../plan/202608/2026080304-plan-semos-p3-trackb-keyword-lexicon.md` (KnowledgeStore plan — write after this handoff)

## Recommended next steps

1. **Update the master handoff** (`2026073002`) with a post-handoff update recording P3 Track B completion and the deferred boundary.
2. **Update the DR16 spec** (`2026080101`) — mark "Implemented (observe mode)" with the deferred-items list.
3. **Update the ADR** (`2026072901`) §8.3.6 — add Track B status entry.
4. **Write a P3 Track B implementation log** in `KnowledgeStore/doc-repo/devdocs/202608/`.
5. **I2 live proof:** Rebuild `chenweb_test` with the new migrations, create test concepts/surfaces through the REST API, run `ResolveSurface` against real document text, verify mentions/surfaces/unresolved rows are written correctly, and record the evidence.
6. **P4:** Profiles, the normative ventilator pilot (blocked on authority-confirmed data), and `extract_metric_definitions`/`extract_product_structure` (see the ADR §8.3.7 remaining items).
7. **P3 Track B follow-up (fuzzy tiers):** Implement tiers 5-6 (trigram blocking with `pg_trgm`, edit-distance filtering with the spec's guardrails) and the batch reconciliation pipeline reusing DR5/DR6/DR7 backlog-drain patterns.

## Knowledge and documentation impact

**What knowledge changed?** P3 Track B transitions from design-only to implemented-as-observe-mode. The keyword lexicon is now the second `semid` kernel instantiation — the `FamilyAdapter` pattern from P2's `TermFamily` is validated by a second, independent implementation.

**Which docs need updating?**
- Spec `2026080101` — mark "Implemented (observe mode)" with carry-forward list
- ADR `2026072901` — §8.3.6 Track B status entry
- Master handoff `2026073002` — post-handoff update
- P3 implementation log — new `20260804XX-devdoc-semos-p3-trackb-implementation-log.md`
- `Capsules/coding-capsules/ontology/+CAPSULE.md` — keyword family section

**Which docs are now stale?**
- Spec `2026080101` header: "Implementation status: Design only" — now partially implemented
- ADR `2026072901` P3 status: "Not built: the keyword lexicon (design-only)" — now built (observe mode)
- Master handoff `2026073002` — no Track B entry yet

**What was intentionally left undocumented?** Fuzzy tiers 5-6 implementation details, reconciliation batch workflow CLI flags, `aligns_to_term` schema specifics, `on` mode retrieval integration, context-token disambiguation algorithm.
