# Keyword Canonicalization — Steps 11–12 (Tier 5–6 + Reconciliation; `aligns_to_term` + Metric Integration): Session Handoff

Date: 2026-08-06

## Scope

This session implemented **steps 11 and 12** of spec `2026080403-spec-keyword-canonicalization-and-reconciliation.md`
(the single reference for the keyword module). Step 1–10 of the same spec were implemented and reviewed in the prior
session (all review findings fixed — see the review doc `2026080601-bug-p4-step1-10-review.md`); this session's steps
11–12 are the follow-on, executed as two subagent-driven (SDD) runs, one per step.

- **Step 11 (§2 REQ-1, tiers 5–6 + minimum reconciliation loop):** tier 5 fuzzy matching wired into
  `KeywordFamily.CandidateNodes` (trigram blocking + edit-distance guardrails), a kernel-level e2e test proving tier-5
  auto-accept, and the offline `keywords.Reconciler` (tier 6 embedding merge) with its `cmd/keyword-reconcile` binary.
- **Step 12 (§2 REQ-2/REQ-3, `aligns_to_term` + metric integration):** the governed bridge — schema CHECK extended with
  `keyword_concept`, `core:aligns_to_term` seeded/released, `AlignmentsStore`, the §14.2 merge conflict-gate + follow made
  live, resolver alignment-follow + observe-path auto-align — and the §16.3 consumer seam: two new `kb.metrics` columns
  plus a `ResolvingMetricsStore` decorator, wired at the one place the metrics processor's `Store` is constructed.

This handoff exists to capture **exactly what was built and what was deliberately left unbuilt**, so a future session can
resume from an accurate baseline. The two hard step-12 prerequisites the spec asserted — the `subject_ref_kind` schema
CHECK and predicate seeding — are both resolved (migration `20260806000002` + the seeded predicate). What still gates the
live §2.2 end-to-end run is external to this module: released `metric_definition` terms to align *to*.

## Document lineage (read in this order if picking this up cold)

1. **Spec `2026080403`** — the single reference for the keyword module (DR15/DR16/DR23). §21 is the living implementation
   record; steps 11 and 12 both have entries there with the real jj hashes and verification blocks.
2. **Review doc `2026080601-bug-p4-step1-10-review.md`** — the findings on steps 1–10; all fixed before this session.
   (Reasoning behind earlier steps also lives in `2026080501-bug-name-resolver-qutd.md` and
   `2026080502-bug-keyword-module-review.md`.)
3. **Step-11 plan** and **step-12 plan** — `ChenWeb/docs/superpowers/plans/2026-08-06-keyword-step12-aligns-to-term-metric-integration.md`
   (step 12; step 11's plan sits immediately behind it in jj history). SDD ledger + per-task briefs/reports:
   `ChenWeb/.superpowers/sdd/2026-08-06-keyword-step12-aligns-to-term-metric-integration/`.
4. **Prior handoff `2026080401-handoff-semos-p3-trackb-keyword-lexicon.md`** — the Track B lexicon slice. Several items it
   listed as deferred (tiers 5–6, the reconciliation pipeline, the `aligns_to_term` bridge) are **built by this session** —
   see the banner on that document and the Deferred boundary below.

## What was built (jj, ChenWeb — linear, no branches)

### Step 11 — tier 5 + minimum reconciliation loop (spec §2 REQ-1)

Commits (oldest → newest; short change ids):

```
step-11 plan (docs)
20260806000001  migration: enable pg_trgm + keyword trigram indexes
ktusoprpkotr    semid: let a candidate carry a precomputed continuous score
qmszvonlrkor    keywords: add fuzzy-matching guardrail primitives (spec §9.2)
wzxyrvrwxslo    keywords: fix negation affix veto to avoid false positives
puskmnmszomp    keywords: wire tier 5 fuzzy matching into CandidateNodes
rwyuuxuvnkqs    keywords: cover the 5-8 rune band of fuzzyCandidateScore (review finding)
nyyqqwtzqtwk    keywords: add kernel-level end-to-end test for tier 5 auto-accept
zwxyvmnqypvz    keywords: add ConceptStore queries for reconciliation blocking
pvqmtmsqvxtn    keywords: add offline reconciler (tier 6 embedding merge)
lknpsqzvpxox / lylmqskswsot   docs: review records (plan/spec sync)
kxqltpvvxknl    keywords: propagate reconciler decision-log and surface-count errors (review finding)
tzsknyplplok    Add cmd/keyword-reconcile: offline batch entrypoint
uumunmlqvnyl    keywords: apply final-cleanup minor polish from step-11 reviews
```

- Migration `20260806000001_enable_pg_trgm_and_keyword_trigram_indexes.sql` — `pg_trgm` extension + trigram indexes.
- `server/api/ontology/keywords/reconcile.go` + `reconcile_test.go` — `keywords.Reconciler`.
- `server/cmd/keyword-reconcile/main.go` — the offline batch binary (needs a DB; tier-6 embedding merge needs an embedding
  server).
- No LLM call in the loop. R1/R2/R4/R5 and a runs/watermark table are explicitly deferred (minimum loop, not the full
  R1–R7 pipeline). Tier 6 runs **reconciliation-only** per §22 Q2 (decided: kept off the online resolve path).

### Step 12 — `aligns_to_term` + metric integration (spec §2 REQ-2/REQ-3)

Commits (oldest → newest):

```
qzmpvunyrnzs    docs: step-12 implementation plan
utzkonsllqsy    migration 20260806000002 — ref-kind CHECKs + kb.metrics columns
kurzxzxyoqzl    seed: core:aligns_to_term property term (core@1.0.0, released + activated)
qxrzszuzsouv    keywords: AlignmentsStore + assertions.AllowedRefKinds += keyword_concept
mstsuzspxtnl    keywords: §14.2 merge conflict-gate + follow live in MergeConcept
twoyxzvtwzuu    names: resolver alignment-follow + observe-path auto-align
wpvswuvomvon    doc-processing: ResolvingMetricsStore decorator + runtime wiring
```

- Migration `20260806000002_aligns_to_term_ref_kinds_and_metric_term_columns.sql` — `subject_ref_kind`/`object_ref_kind`
  CHECKs extended with `keyword_concept` (subject side NOT NULL); `kb.metrics.keyword_concept_id` (FK to
  `kb.keyword_concepts`) + `metric_definition_term_id` (deliberately no FK, consistent with the schema's other
  term-id-reference columns, §2.4).
- `server/cmd/ontology-seed/content.go` — `core:aligns_to_term` (`Kind: "property"`) authored + released + activated.
- `server/api/ontology/keywords/alignment.go` + `alignment_test.go` — `AlignmentsStore` (`AcceptedForConcept`,
  `MergeConflict`, `FollowMerge`, `EnsureAccepted`; `ErrAlignmentConflict` sentinel; released-term guard; decision-log
  audit on real writes).
- `server/api/ontology/assertions/assertions_store.go` — `AllowedRefKinds` += `keyword_concept`.
- `server/api/ontology/keywords/concepts_store.go` + test — `MergeConcept` §14.2 gate + follow in both the tx and fallback
  paths (nil-safe; unwired callers unchanged); wired at `cmd/keyword-reconcile/main.go` and the kbhandler merge endpoint.
- `server/api/ontology/names/resolver.go` + test — `alignments` field + `NewResolverWithAlignments`; alignment-follow in
  `ResolveName` (write-free, governed exact-label match stays authoritative); observe-path auto-align
  (`matchLabelToReleasedTerm` refactor through `lookupReleasedTerm`); error policy: `ErrAlignmentConflict` tolerated,
  other errors propagate (DR15).
- `server/api/doc-processing/extract-metrics.go` + test, `runtime.go` — `ResolvingMetricsStore` decorator (`nameResolver`
  subset interface; `resolveAll` batches one `ResolveNames` call at scope `"_"`; `keyword_concept_id` from
  `resolution.ConceptID`, `metric_definition_term_id` from `resolution.TermID` **only on `term_resolved`**; never
  overwrites existing keys); Save/Upsert SQL now 39 args with nil-when-empty nullable bindings; Upsert ON CONFLICT
  SET updates both new columns; `newResolvingMetricsStore(db)` is the one resolver construction, replacing
  `MetricsSQLStore{...}` at `NewMetricsProcessor` in `runtime.go`.

## Verification (both steps)

```bash
cd ChenWeb
go build ./... && go vet ./server/api/ontology/... ./server/api/doc-processing/... ./server/cmd/...
go test ./server/api/ontology/keywords/... ./server/api/ontology/semid/... ./server/api/ontology/names/... ./server/api/ontology/assertions/...
```

- `go build` / `go vet` clean; keywords/semid/names/assertions all green.
- New tests: step 11 — tier-5 kernel e2e + reconciler sqlmock; step 12 — 5 alignment, 3 merge-gate, 4 resolver, 6
  decorator tests, all PASS. `TestReconcilerMergesCrossLingualProvisional` passes unchanged (nil-safe gate).
- `doc-processing` retains exactly the 15 pre-existing environment-dependent failures (step-11 baseline; confirmed not
  grown by either step). `TestMetricsSQLStoreSaveMetricsPersistsMetricCategoriesEn` is among them — a pre-existing mock
  ordering issue, unrelated to the 39-arg update, left alone per the "don't fix unrelated pre-existing failures" rule.
- `cmd/keyword-reconcile` compiles; runtime needs a DB/embedding server (not live-validated this session).

## Architecture: how the pieces connect

```
Online resolve path (names.Resolver, §9.5)
  ResolveName (write-free):
    governed layer first  → released ontology-term exact label match (authoritative)
    keyword lexical layer → KeywordFamily tiers 0-4 (+ tier 5 fuzzy, trigram, guardrails)
    alignment-follow      → accepted aligns_to_term lifts a concept to StatusTermResolved (§16.2, REQ-2)
  ResolveAndObserve (observe path, writes):
    auto-align producer   → concept pref_label exactly matches a released metric_definition
                            label ⇒ EnsureAccepted mints the alignment (§16.1, D11)
    occurrence            → term_resolved when the resolution carried a TermID

Metrics pipeline (doc-processing, §16.3, REQ-3)
  ResolvingMetricsStore decorator wraps MetricsSQLStore at NewMetricsProcessor (runtime.go) — one seam.
  resolveAll: distinct metric_name → one ResolveNames batch → keyword_concept_id + metric_definition_term_id
  persisted (extraction/prompts untouched).

Offline reconciliation (step 11, §13)
  cmd/keyword-reconcile → keywords.Reconciler
    ConceptStore blocking queries → tier 6 embedding merge (reconciliation-only per §22 Q2)
    MergeConcept carries §14.2 gate: a different-term alignment conflicts and refuses; a sole alignment
    follows to the survivor inside the merge tx (atomic with the tombstone + surface re-point).

Schema (migrations 20260806000001-2)
  kb.semantic_assertions.subject_ref_kind = 'keyword_concept' (aligns_to_term rows are assertions)
  kb.metrics.keyword_concept_id (FK), kb.metrics.metric_definition_term_id (no FK)
  core:aligns_to_term property seeded + released (core@1.0.0)
```

## Deferred boundary (explicit — what was deliberately not built)

| Item | Why deferred | Where it lands |
|------|-------------|---------------|
| **Full R1–R7 reconciliation pipeline** | Only the minimum loop was step 11's deliverable: R1/R2/R4/R5, the runs/watermark table, and the orchestration workflow are not built. `keywords.Reconciler` + `cmd/keyword-reconcile` provide the blocking + tier-6 merge core. | Step-13-ish / follow-up |
| **`on`-mode wiring** | `ResolveSurface` in observe mode writes mentions/surfaces/keys/backlog but attaches nothing to search payloads or retrieval. The `on` gate exists but is treated like observe. | P4+ |
| **Governed-catalog bootstrap (§16.1) + standards-glossary import (§13.2)** | The **external prerequisite** for the live §2.2 run: released `metric_definition` terms to align *to*. Auto-align targets `releasedTermSQL` content, so until terms are seeded the observe path mints no alignments (the guard returns "not a released term", a state, not an error). | External / follow-up |
| **Context-token disambiguation (§5.2)** | IDF-weighted overlap heuristic needs document context around the mention; the collector sends empty context. | Later |
| **Full Double Metaphone phonetic key** | Current `phoneticKey()` is a stub (first char + first 4 consonants). Stable + deterministic, satisfies the 6-key contract. | Follow-up |
| **Batch adjudication UI** | No admin surfaces for the `kb.keyword_unresolved` backlog (REST covers CRUD for concepts/surfaces/rewrite rules only). | Follow-up |
| **Rewrite-rule auto-promotion** | Tier 3 rules are authored manually; no promotion from reconciliation decisions. | Follow-up |
| **Multi-process reload of `KEYWORD_RESOLVER_MODE`** | Read once at startup (`sync.Once`); a change needs a restart. | Follow-up |
| **`TestMetricsSQLStoreSaveMetricsPersistsMetricCategoriesEn` mock ordering** | Pre-existing test defect (sqlmock expectation order vs code's SELECT-before-INSERT), unrelated to step 12; left unfixed by scope rule. | Housekeeping |

### What the deferred boundary means operationally

- REQ-1 (tiers 5–6) and REQ-2 (accepts an `aligns_to_term`) are **built and unit/sqlmock-tested**, and REQ-3's consumer
  seam is **wired in production** — but the module has still **never been run against real PostgreSQL with real document
  text** (the I2 gap, inherited from Track B). Every claim in §20.2 of the spec was found by reading code; nothing in
  steps 11–12 has been live-proven.
- With `KEYWORD_RESOLVER_MODE=observe` and released `metric_definition` terms present, the observe path will mint
  exact-label alignments and the metric seam will persist both columns. Without released terms, the module is correct but
  inert: no alignments, so `metric_definition_term_id` stays NULL on `term_resolved`-only (by design — the column is only
  written on a governed resolution).
- Tier 6 (embeddings) is reachable **only** from `cmd/keyword-reconcile`, never on the online resolve path. The two local
  multilingual embedding models are in `.models.toml` (`qwen3-embedding-0-6b`, `nomic-embed-v2-moe` via llama.cpp) but the
  reconciler has not been run against either.

## Related documents

- **Spec:** `KnowledgeStore/doc-repo/specs/202608/2026080403-spec-keyword-canonicalization-and-reconciliation.md` — the single
  reference; §21 has the step-11 and step-12 entries with the real jj hashes and verification blocks. KnowledgeStore
  status update committed as `rrssysxukqwl` this session (spec-only, path-scoped).
- **ADR:** `KnowledgeStore/doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md` — DR15/DR16/DR23
  (governing requirement §2).
- **Review docs:** `2026080501-bug-name-resolver-qutd.md`, `2026080502-bug-keyword-module-review.md`,
  `2026080601-bug-p4-step1-10-review.md`.
- **Plans:** step-12 plan `ChenWeb/docs/superpowers/plans/2026-08-06-keyword-step12-aligns-to-term-metric-integration.md`
  (step-11 plan immediately behind it in jj history). SDD ledger/reports:
  `ChenWeb/.superpowers/sdd/2026-08-06-keyword-step12-aligns-to-term-metric-integration/`.
- **Prior handoff:** `2026080401-handoff-semos-p3-trackb-keyword-lexicon.md` — superseded for the items this session built.
- **Master status handoff:** `2026073002-handoff-semos-ontology-status.md` — needs a post-handoff update for steps 11–12.
- **Code (ChenWeb):** `server/api/ontology/keywords/` (Reconciler, alignment.go), `server/api/ontology/names/resolver.go`,
  `server/api/doc-processing/extract-metrics.go` + `runtime.go`, `server/cmd/keyword-reconcile/`,
  `server/cmd/ontology-seed/content.go`, `project_migrations/2026080600000[1-2]_*.sql`.

## Recommended next steps

1. **I2 live proof (the open operational gap).** Rebuild the dev DB with migrations `20260806000001-2` (already applied to
   the live `miner` dev DB), create concepts/surfaces, run `ResolveAndObserve` against real document text, and verify
   occurrences + alignments + the metric seam persist the expected rows. Run `cmd/keyword-reconcile` on a cross-lingual
   case (亮度 → Luminance) against a local embedding model.
2. **§16.1 governed-catalog bootstrap.** Seed released `metric_definition` terms so the observe-path auto-align has
   targets; then the §2.2 end-to-end acceptance run can actually execute (currently gated on this + §13.2).
3. **Full reconciliation pipeline R1–R7** — runs/watermark table, harvest/prune/validate stages, orchestration; reuse the
   DR5/DR6/DR7 backlog-drain patterns.
4. **Update the master handoff `2026073002`** with a post-handoff update recording steps 11–12 completion.
5. **Housekeeping:** fix `TestMetricsSQLStoreSaveMetricsPersistsMetricCategoriesEn`'s mock ordering; consider batch
   adjudication UI for the unresolved backlog.

## Knowledge and documentation impact

**What knowledge changed?** REQ-1's tier 5–6 and the minimum reconciliation loop are now implemented (step 11); REQ-2's
`aligns_to_term` bridge and REQ-3's metric consumer seam are now implemented and wired (step 12). The two asserted step-12
hard prerequisites (schema CHECK + predicate seeding) are resolved. The module's remaining blockers are external (governed
catalog, §13.2 import) or operational (I2 live validation).

**Which docs were updated?**
- Spec `2026080403` — §0 "Not built" row, §2.1 REQ-2/REQ-3 status, §14.2 badge → **Live**, §16.3 call-site decision
  (decorator), §19 item 12 DONE, §21 step-11 + step-12 entries, §20.1.3 deferred entry removed (sections renumbered);
  KnowledgeStore commit `rrssysxukqwl`, spec-only.

**Which docs are now stale?**
- Handoff `2026080401` — its deferred-boundary rows for tiers 5–6, the reconciliation pipeline, and `aligns_to_term` are no
  longer true (see the banner added there).
- Master handoff `2026073002` — no steps-11–12 entry yet.

**What was intentionally left undocumented?** Tier-6 embedding model choice internals and reconciler CLI flags (the binary
has not been run), full R1–R7 pipeline details, `on`-mode retrieval wiring, context-token disambiguation algorithm.
