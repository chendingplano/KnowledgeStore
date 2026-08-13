# SemOS P3 — Assertions, Evidence, and Phase D Association: Implementation Plan

This plan follows P2 closeout on Saturday, August 1, 2026. P2 built the ontology core (governed terms, the module compiler, the four core 4a modules, the `semid` canonicalization kernel with the ontology-term family). P3 builds the layer that gives artifacts something to be *about*: the qualified-assertion and evidence model (DR9), and the three Phase D pipeline stages (`normalize_assertions`, `associate_semantics`, `project_semantics`) that turn extracted artifacts into governed, queryable semantic claims.

> **2026-08-01 status:** Chunks 0–F are complete and live-validated against real Postgres, including real gold-corpus data — see the P3 implementation log `2026080103-devdoc-semos-p3-implementation-log.md`. This closes out P3 Track A. Track B (keyword lexicon) is not started; this plan document is left as originally written (per the P2 precedent) rather than retroactively checkbox-edited.

## Scope decision (2026-08-01)

P3 as specified in the ADR (`2026072901` lines 1507-1523) bundles two largely independent tracks:

- **Track A — assertions, evidence, Phase D association.** The DR9 schema, the normalizer registry (seam 5), the three Phase D stages, the operational semantic-decision state machine (spec §9.3), and the deferred/ambiguous backlog drain.
- **Track B — the keyword lexicon** (DR15/DR16's second kernel instantiation), shipped behind `KEYWORD_RESOLVER_MODE=observe`.

Per user direction on 2026-08-01, **this plan covers Track A only.** The DR16 keyword-spec merge (a documentation prerequisite, not code) was completed the same day as `2026080101-spec-keyword-canonicalization-merged.md`. Track B's actual code — the kernel `FamilyAdapter` instantiation, mention collector, reconciliation pipeline, and backlog-drain admin surfaces — is deferred to a follow-up P3 slice. See "Deferred beyond this slice" below.

> **2026-08-04 update:** Track B is now **implemented and merged to `main`** (plan `2026080304-plan-semos-p3-trackb-keyword-lexicon.md`, chunks 0–H). See the Track B handoff `2026080401-handoff-semos-p3-trackb-keyword-lexicon.md` and implementation log `2026080402-devdoc-semos-p3-trackb-implementation-log.md`.

## Goal

Build the assertion/evidence layer and Phase D association pipeline such that:

- qualified semantic assertions (DR9 typed references, normalized value columns) and their evidence are first-class, queryable database records, independent of any single artifact family;
- object classification uses the general assertion model (`core:instance_of`) rather than a bespoke classification table, with `kb.object_nodes.primary_class_term_id` populated as a derived, rebuildable projection (closing the P2 deferral);
- metric and provision artifacts can be normalized into candidate assertions through a registered, per-family normalizer (seam 5), without hand-wiring each artifact family into the association pipeline;
- the spec §10 association pipeline (generate candidates → resolve targets → validate → adjudicate → persist → project → audit) runs as three declared Phase D stages after Phase C, gated by `SEMANTIC_ASSOCIATION_ENABLED`;
- conflicting assertions remain independently queryable, evidence loss demotes an assertion to `unsupported` (and restoration reverses it), and a corrupted derived projection is detected as stale and repaired from its authoritative source — the spec §16.2/§16.3 acceptance suite passes for everything in scope.

## Architecture

```text
Phase C (existing)                    Phase D (new, this plan)
runPostProcessIndexing                 |
        |                              v
        |                     normalize_assertions
        |                     per-family normalizer (seam 5)
        |                     artifacts -> candidate qualified assertions + evidence
        |                              |
        |                              v
        |                     associate_semantics
        |                     spec §10.3-10.7: candidates -> resolve -> validate -> adjudicate
        |                     -> persist to the one authoritative owner
        |                              |
        |                              v
        |                     project_semantics
        |                     spec §10.8: derived edges, search payloads, primary_class_term_id
        |                     stale detection + deterministic repair
        v                              v
   (unchanged)              kb.semantic_assertions / assertion_evidence / assertion_relations
                             kb.semantic_decision_candidates
                             kb.artifact_semantic_links
                             kb.projection_state
```

Key invariants (carried from DR9/DR10/DR8 and the spec §9.3 operational machine):

- `subject_ref`/`object_ref` are typed pairs (`object_node | ontology_term | assertion | artifact | literal`) with a fast-path `*_object_id` column for the dominant "all assertions about this referent" query, per DR9.
- Classification is an accepted assertion (`core:instance_of`), never a separate table; `primary_class_term_id` is a derived projection, never authored directly (DR10).
- Association decisions use the **operational** semantic-decision state machine (spec §9.3), distinct from P2's governed-content machine: `candidate -> in_review -> accepted / rejected / deferred`, `accepted -> superseded` on a decision-relevant revision, `accepted -> unsupported` on evidence loss and back.
- Nothing here activates ontology content — normalize_assertions and associate_semantics only ever write to the operational tables; the governed content tables from P2 are read-only inputs (predicate/quantity/unit/assertion-kind terms).
- Deferred candidates retry only on a dependency-fingerprint change (never a bare schedule), reusing the fingerprint/defer/retry mechanism already proven in P2 chunk A.

## Tech stack

- Runtime and stores: `ChenWeb/server/api/ontology/assertions/` (new), `ChenWeb/server/api/doc-processing/` (new Phase D stage files)
- Database migrations: `ChenWeb/project_migrations/` (`20260801NNNNNN`, sequence resets per date per existing convention)
- Docs and ADR/spec updates: `KnowledgeStore/doc-repo/`
- DB access: `database/sql` + the established `SQLStore`/`DBX` interface pattern (satisfied by `*sql.DB` and `*sql.Tx`, per P2 chunk B's terms-store precedent); goose migrations; sqlmock + fake-store unit tests; a temporary `server/cmd/p3validate` program for live-Postgres validation against `chenweb_test`, deleted after use (the P2 pattern).

## Scope boundaries

In scope (Track A):

- `kb.semantic_assertions`, `kb.assertion_evidence`, `kb.assertion_relations` (DR9) with the operational state machine (spec §9.3)
- `kb.semantic_decision_candidates` — the operational counterpart to P2's `kb.ontology_candidates`, with its own fingerprint/dedup and defer/retry gate (spec §16.3 items 2, 12, 13)
- `kb.artifact_semantic_links` (`about_term`, `describes_occurrence`, `aligns_to_term` — the last one unused until the keyword family exists, but the column/predicate space is declared now so Track B does not need a migration to add it later)
- `kb.projection_state` (authoritative ref, projection version, stale flag) and the `ProjectionBuilderRegistry` (seam 7)
- `AssertionNormalizerRegistry` (seam 5) plus two normalizer instances: metric, provision — reading the *existing* `extract_metrics`/`extract_provisions` output (including best-effort parsing of `threshold_or_target` free text) rather than requiring those processors to change their emitted schema first
- the three Phase D stages (`normalize_assertions.go`, `associate_semantics.go`, `project_semantics.go`) wired into `ControlService` after Phase C, gated by `SEMANTIC_ASSOCIATION_ENABLED` (default `true`)
- `kb.object_nodes.primary_class_term_id` maintenance via `project_semantics` (closes the P2 chunk E deferral)
- association-run telemetry (spec §10.9) and the deferred/ambiguous backlog drain, reusing the ADR `2026070701` DR5/DR6/DR7 pattern (bulk endpoint, admin review page, confidence-gated LLM) rather than a new mechanism
- exit-criteria tests: spec §16.2 items 1, 3-7 and §16.3 items 2-17 that are in scope for Track A (item 1 was already closed by P2; items specific to keyword resolution are out of scope)

Out of scope (deferred beyond this slice):

- **The keyword lexicon** (`kb.keyword_*`, the DR15 kernel `FamilyAdapter` instantiation for keywords, the mention collector, `KEYWORD_RESOLVER_MODE=observe` code) — design is done (`2026080101-spec-keyword-canonicalization-merged.md`); code is a follow-up P3 slice.
- **Rewriting `extract_metrics`/`extract_provisions` to emit structured value/comparator/unit/condition fields directly.** The ADR's processor table lists this as a P3 "changed processor" item, but DR8 defines `normalize_assertions` as the stage that performs exactly this text-to-structured normalization. This slice's metric/provision normalizers parse the existing free-text output; a follow-up may still rewrite the processors themselves once a real (non-synthetic) document corpus justifies it — see the P0 "real-data worked example" deferral, which this inherits.
- `extract_metric_definitions` (P3-P4 per the ADR processor table) — harvesting a metric's *definition* (DR23) is explicitly a separate, later step from normalizing a metric's *value*, which is this slice's concern.
- Profiles, profile rules, review scopes, the pilot 4b domain module — P4, unchanged from the P2 plan's boundary.
- The comparison matrix / verdict service beyond the already-built comparator — unchanged.
- Full `semrules` predicate language — P5, unchanged.

## Implementation chunks

### Chunk 0 — Scope decision, DR16 spec merge, plan wiring (complete 2026-08-01)

- [x] DR16 merged keyword spec written: `2026080101-spec-keyword-canonicalization-merged.md`, superseding `2026072301` and `2026072703`.
- [x] ADR `2026072901` DR16 annotated with the 2026-08-01 status pointer.
- [x] This plan written and cross-linked from the ADR references and the ontology-status handoff.
- [x] Track A/Track B scope split recorded (this document, "Scope decision" above).

### Chunk A — Assertion and evidence schema (DR9)

- [ ] Migrations: `kb.semantic_assertions`, `kb.assertion_evidence`, `kb.assertion_relations`.
- [ ] `kb.semantic_assertions`: `assertion_id` (stable, immutable), `logical_identity_key` (spec §16.3 item 2's dedup key), subject/object typed-ref pairs per DR9 (`subject_ref_kind`, `subject_ref_id`, `subject_object_id` fast path; `object_ref_kind`, `object_ref_id`, `object_object_id`, plus a `object_literal` path for non-referent objects), `predicate_term_id`, `assertion_kind_term_id`, `polarity`, `modality`, `qualifiers JSONB`, `confidence`, normalized value columns (`value_form`, `numeric_value`, `lower_value`, `upper_value`, inclusivity flags, `comparator`, `unit_term_id`, `quantity_kind_term_id`, `raw_text` — never dropped), `status` per the operational machine, `valid_time`, `transaction_time`, payload revision counter.
- [ ] `kb.assertion_evidence`: `assertion_id`, `input_record_id`, `artifact_type`, `artifact_id`, `artifact_object_id`, `evidence_quote`, `source_line_spans`, `extraction_run`, `model`, `prompt_version`, `confidence`, `evidence_role` (`supports`/`contradicts`, spec §16.2 item 5).
- [ ] `kb.assertion_relations`: conflict/supersession between assertions — `assertion_id`, `related_assertion_id`, `relation_kind` (`conflicts_with`/`supersedes`/`superseded_by`), evidence/rationale.
- [ ] Operational state machine (spec §9.3) enforced in Go: `candidate -> in_review -> accepted`, `-> rejected`, `-> deferred`; `deferred -> candidate` only on dependency-fingerprint change; `accepted -> superseded` on decision-relevant revision; `accepted -> unsupported` on last-evidence loss, `unsupported -> accepted` on qualifying-evidence restoration (spec §16.3 item 16). This is a **second, distinct** state machine from P2's governed-content one — do not reuse `candidates.StatusX` constants; assertions are operational data, not governed ontology content.
- [ ] Stores under `ChenWeb/server/api/ontology/assertions/` (`assertions_store.go`, `evidence_store.go`, `relations_store.go`, `state_machine.go`), `DBX` interface pattern, sqlmock + fake-store tests.

Acceptance:

- [ ] Two conflicting source assertions remain separately queryable with independent evidence and provenance (spec §16.2 item 5).
- [ ] Deleting an assertion's final qualifying evidence moves it to `unsupported`; restoring qualifying evidence returns it to `accepted` with a complete audit trail (spec §16.3 item 16).
- [ ] A qualifying human-authored provenance record on an evidence row prevents the `unsupported` transition while active (spec §10.12).

### Chunk B — `kb.semantic_decision_candidates` and the association candidate lifecycle

- [ ] Migration: `kb.semantic_decision_candidates` — the operational counterpart to P2's `kb.ontology_candidates`: `candidate_kind` (`referent`|`term_association`|`assertion`|`occurrence`|`profile_selection`), `proposed_payload JSONB`, `method` (`explicit_structured`|`deterministic_source_span`|`released_mapping`|`lexical_candidate`|`semantic_candidate`|`structural_candidate`|`human`, spec §10.3), `resolution_outcome` (`matched`|`new_target_candidate`|`rejected`|`deferred`, spec §10.4 — a payload field, not a lifecycle status), `logical_identity_key`, `fingerprint`, `status` per the operational machine, `dependency_fingerprint`, evidence/source-span references, timestamps/actors.
- [ ] Fingerprint dedup on `logical_identity_key` (spec §16.3 item 2): reprocessing unchanged evidence records `last_seen` on the existing candidate; a decision-relevant payload change creates a new payload revision and supersedes any completed prior revision, mirroring P2 chunk A's fingerprint mechanism but keyed to the association model's `logical_identity_key` (spec §10.7) rather than a raw content hash, since two artifacts can independently support the same logical association.
- [ ] Transient-failure idempotency (spec §16.3 item 13): a resolution/adjudication failure leaves the candidate non-terminal (`candidate` or `in_review`) and safe to resume without duplicating decisions.
- [ ] Store under `ChenWeb/server/api/ontology/assertions/decision_candidates_store.go`.

Acceptance:

- [ ] Reprocessing unchanged semantic evidence reuses `logical_identity_key`; unchanged payload records `last_seen`; decision-relevant change creates a payload revision and supersedes the prior completed one (spec §16.3 item 2).
- [ ] A transient failure leaves a candidate non-terminal and idempotently resumable (spec §16.3 item 13).

### Chunk C — Normalizer registry (seam 5) and the `normalize_assertions` stage

- [ ] `AssertionNormalizerRegistry` in `ChenWeb/server/api/ontology/assertions/normalizer_registry.go`: `RegisterNormalizer(artifactFamily string, n Normalizer)`, `LookupNormalizer(family string) (Normalizer, bool)` — mirrors the seam-1 `ProcessorRegistry` shape (DR11: "adding an instance must not require editing the mechanism").
- [ ] `Normalizer` interface: `Normalize(ctx, artifact) ([]CandidateAssertion, error)`, producing `kb.semantic_decision_candidates` rows of kind `assertion` with evidence attached, never writing directly to `kb.semantic_assertions`.
- [ ] Metric normalizer: reads `extract_metrics` output (including the free-text `threshold_or_target` column), best-effort parses comparator/value/unit from it into the candidate's proposed normalized-value fields, and always preserves `raw_text` regardless of parse success (a failed parse still produces a candidate — with `value_form = 'unparsed'` — never a dropped artifact).
- [ ] Provision normalizer: reads `extract_provisions` output, extracts modality (`shall`/`should`/`may` and their negations) and applicability/authority fields already present in that output into candidate `required`/`permitted`/`prohibited` assertions.
- [ ] New Phase D stage `ChenWeb/server/api/doc-processing/normalize_assertions.go`: iterates artifacts for the record, dispatches to the registered normalizer per artifact family, writes candidates. Runs only when `SEMANTIC_ASSOCIATION_ENABLED=true`.
- [ ] `SEMANTIC_ASSOCIATION_ENABLED` env var wired the same way as `DOC_PIPELINE_PLAN_ONLY` (`ChenWeb/server/api/doc-processing/pipeline_mode.go` pattern: `...FromEnv()` + a pure `normalize...` helper for testability).

Acceptance:

- [ ] A metric artifact with a parseable `threshold_or_target` produces a candidate assertion with structured comparator/value/unit and a non-empty `raw_text`.
- [ ] An unparseable metric artifact still produces a candidate (never silently dropped), flagged for `deferred` or `in_review` rather than fabricating a value.
- [ ] Registering a new normalizer requires no edit to `normalize_assertions.go` itself (DR11 seam rule).

### Chunk D — `associate_semantics` stage

- [ ] New Phase D stage `ChenWeb/server/api/doc-processing/associate_semantics.go` implementing spec §10.3-§10.7 over `kb.semantic_decision_candidates`:
  - Step 3 (resolve targets, §10.4): referent candidates reconcile through `kb.artifact_objects`/`kb.object_nodes`; term/assertion candidates resolve governed predicate/quantity/unit/assertion-kind terms from P2's term stores; outcome recorded as `matched`/`new_target_candidate`/`rejected`/`deferred` (ambiguous target sets → `deferred` with reason `ambiguous_targets`, never a forced pick).
  - Step 4 (validate, §10.5): artifact/target existence, permitted relation for source/target types, source-span/evidence consistency, term kind/namespace/module compatibility, duplicate/mutually-exclusive association check. Failing validation → `rejected` with machine-readable reason; missing context → `deferred`, never an invented target.
  - Step 5 (adjudicate, §10.6): deterministic policy accepts exact, fully constrained mappings (e.g. a `released_mapping` candidate from an active module release); everything else needing a decision stays `in_review` this slice (LLM-assisted adjudication is not built here — deterministic-only adjudication is enough to prove the pipeline and satisfies spec §16.3 item 4's "LLM-only cannot activate" constraint trivially, since there is no LLM path yet to violate it).
  - Step 6 (persist, §10.7): accepted candidates become `kb.semantic_assertions` rows (via chunk A's store) or `kb.artifact_semantic_links` rows, keyed by `logical_association_key`; unchanged accepted decisions on reprocessing remain untouched; changed target identity or relation kind creates a different logical association, never an in-place mutation of an existing one.
- [ ] Migration: `kb.artifact_semantic_links` (`about_term`, `describes_occurrence`, `aligns_to_term` predicate column; `logical_association_key`; payload/decision revision columns per §10.7).

Acceptance:

- [ ] Lexical, semantic, and structural associations remain candidates until an approved decision path accepts them (spec §16.3 item 9).
- [ ] Accepted associations persist only in the authoritative owner named by spec §8.5/§10.7; nothing else writes there directly (spec §16.3 item 10).
- [ ] An LLM-only recommendation or confidence threshold cannot activate an assertion or artifact association (spec §16.3 item 4) — trivially true this slice (no LLM path exists yet) but the deterministic-only gate is structured so a future LLM path plugs in as a *candidate scorer*, never a direct writer.

### Chunk E — `project_semantics` stage and `kb.projection_state`

- [ ] Migration: `kb.projection_state` — `authoritative_ref` (table + id), `projection_kind`, `projection_version`, `stale BOOLEAN`, `last_built_at`.
- [ ] `ProjectionBuilderRegistry` (seam 7) in `ChenWeb/server/api/doc-processing/projection_registry.go`: `RegisterProjectionBuilder(kind string, build BuildFunc, repair RepairFunc)`.
- [ ] New Phase D stage `ChenWeb/server/api/doc-processing/project_semantics.go` (spec §10.8): builds derived projections from accepted `kb.semantic_assertions`/`kb.artifact_semantic_links` rows — `kb.object_nodes.primary_class_term_id` (from accepted `core:instance_of` assertions, closing the P2 chunk E deferral; DR10) is the first and only projection built this slice. Every projection row references its authoritative source and a projection version; corruption/staleness is detected by comparing the projection's referenced authoritative revision against the current one, and repair is deterministic replay from the authoritative store — never a hand patch.

Acceptance:

- [ ] Every projection references its authoritative record and projection version (spec §16.3 item 10 second half).
- [ ] A deliberately corrupted `primary_class_term_id` projection is detected as stale and repaired from the authoritative assertion (spec §16.2 item 6, §16.3 item 14).
- [ ] A partial projection failure leaves the authoritative association committed, marks the projection stale, and repairs idempotently on retry (spec §16.3 item 14).

### Chunk F — Association telemetry, backlog drain, and exit criteria

- [ ] Association-run telemetry (spec §10.9): per-run report of artifacts examined, candidates generated by method, resolution outcomes, lifecycle counts, newly proposed referents/terms/assertions, deterministic-vs-human decision counts, stale projections detected/repaired, per-stage timing/errors. Reconciles every examined artifact — nothing silently dropped (spec §16.3 item 17).
- [ ] Deferred/ambiguous backlog drain reusing the ADR `2026070701` DR5/DR6/DR7 pattern: a bulk drain endpoint (`POST /kb/semantic-decisions/drain-deferred?limit=N`, safe to call repeatedly), an admin review page listing `deferred`/`in_review` candidates with their evidence, and an optional confidence-gated automated retry path — no new backlog mechanism invented.
- [ ] Deferred candidates retry only on dependency-fingerprint change (spec §16.3 item 12) — reuses chunk B's fingerprint/defer/retry gate.
- [ ] `SEMANTIC_ASSOCIATION_ENABLED`/`DOC_PIPELINE_ON_CONFLICT`-style wiring documented in the ADR config table cross-reference.
- [ ] Exit-criteria test suite consolidating: spec §16.2 items 1 (already closed by P2), 3-7; spec §16.3 items 2-17 that are in Track A scope (excludes item 1, closed by P2; excludes any item that is purely about the keyword lexicon, none currently named).
- [ ] Documentation: P3 implementation log (`KnowledgeStore/doc-repo/devdocs/202608/...`), ontology-status handoff update, ADR P3 section annotated with `**Built:**` pointers per the P2 precedent, ontology capsule updated.

Acceptance:

- [ ] Association-run telemetry reconciles examined artifacts across every resolution outcome and lifecycle status without unaccounted candidates (spec §16.3 item 17).
- [ ] `kb.semantic_decision_candidates` in `deferred` status only leave that status via the fingerprint-gated retry path (spec §16.3 item 12).
- [ ] The full exit-criteria suite passes against live Postgres (`chenweb_test`), following the P1/P2 precedent of a temporary `server/cmd/p3validate` program, deleted after the run is recorded.

## Deferred beyond this slice

Recorded here so a later phase or handoff never mistakes this plan for "all of P3":

1. **The keyword lexicon** (Track B) — design complete (`2026080101-spec-keyword-canonicalization-merged.md`); `kb.keyword_*` tables, the kernel `FamilyAdapter` instantiation, the mention collector, and `KEYWORD_RESOLVER_MODE=observe` code are a follow-up P3 slice.
2. **Rewriting `extract_metrics`/`extract_provisions` to emit structured fields directly**, rather than having the normalizer parse existing free-text output. Revisit once a real (non-synthetic) document corpus is available — this inherits the standing P0 "real-data worked example" deferral.
3. **`extract_metric_definitions`** (metric *definition* harvesting, DR23) — explicitly P3-P4 in the ADR processor table; this slice only normalizes metric *values*.
4. **LLM-assisted adjudication in `associate_semantics`.** This slice's Step 5 is deterministic-only. Adding an LLM-scored candidate path is additive (a new candidate-scoring input, not a mechanism change) and can land later without revisiting chunks A-D.
5. **Full `semrules` predicate language, profiles, review scopes, the pilot 4b domain module** — unchanged from the P2 plan's P4/P5 boundary.
