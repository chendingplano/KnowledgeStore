# SemOS P3 Implementation Log — Assertions, Evidence, and Phase D Association (chunks 0–D)

**Date:** 2026-08-01
**Scope:** Execution log for the P3 slice built this session, following plan `2026080102-plan-semos-p3-assertions-evidence-and-phase-d-association.md`, in `ChenWeb`.

## 0. Summary — what this slice is, and what it deliberately is not

This slice covers **Track A, chunks 0–D** of the P3 plan: the DR9 assertion/evidence schema, the operational association-candidate lifecycle, the DR11 seam-5 normalizer registry with metric and provision instances, and the first two of the three DR8 Phase D stages (`normalize_assertions`, `associate_semantics`). It does **not** cover chunk E (`project_semantics`), chunk F (telemetry/backlog-drain surfaces/exit-criteria suite), or Track B (the keyword lexicon, design-complete per `2026080101-spec-keyword-canonicalization-merged.md` but not built). See §6 for the precise deferred boundary.

Everything below is **unit-tested and live-validated against real Postgres** (`chenweb_test`), including against the actual gold ventilator-corpus data already present in that database from prior P0 benchmark runs — not only synthetic fixtures.

## 1. Chunk 0 — scope decision, DR16 spec merge, plan wiring (complete)

- Per user direction, P3 this session covers Track A only (assertions/evidence/Phase D); the keyword lexicon (Track B) is deferred.
- DR16 merged keyword spec written: `2026080101-spec-keyword-canonicalization-merged.md`, superseding `2026072301` and `2026072703` — a documentation prerequisite the ADR calls for before keyword-lexicon code begins, completed even though that code itself is deferred.
- ADR `2026072901` DR16 annotated with a 2026-08-01 status pointer to the merged spec.
- Plan `2026080102-plan-semos-p3-assertions-evidence-and-phase-d-association.md` written, covering all of P3 Track A (chunks 0–F) with an explicit Track A/B scope split and a deferred-items list.

## 2. Chunk A — assertion and evidence schema (DR9) (complete)

### A1 — Migrations

`20260801000001`–`00003`:

| Migration | Table |
|---|---|
| `000001` | `kb.semantic_assertions` — DR9 typed subject/object ref pairs with `*_object_id` fast-path columns, normalized value columns (`value_form`/`numeric_value`/`lower_value`/`upper_value`/inclusivity flags/`comparator`/`unit_term_id`/`quantity_kind_term_id`/`raw_text`), `logical_identity_key`+`revision` versioning (mirrors the P2 term-versioning pattern), the spec §9.3 **operational** state machine on `status` |
| `000002` | `kb.assertion_evidence` — `evidence_role` (supports/contradicts), `actor_kind` (processor/human), soft-delete (`deleted`) rather than a DB cascade, since the accepted↔unsupported transition depends on which evidence rows remain active |
| `000003` | `kb.assertion_relations` — conflict/supersession links between assertions |

### A2 — Stores and the operational state machine

New package `ChenWeb/server/api/ontology/assertions/`:

- `state_machine.go` — the spec §9.3 **operational** semantic-decision machine (`candidate → in_review → accepted/rejected/deferred`; `accepted → superseded | unsupported`; `unsupported → accepted`), explicitly distinct from P2's governed-content machine on `kb.ontology_terms`/`kb.ontology_candidates`.
- `assertions_store.go` — `AssertionStore`: `CreateAssertion` (revision 1), `CreateRevision` (supersedes a prior `accepted` revision automatically, spec §10.7), `GetLatest`/`GetByID`/`ListBySubjectObject` (the DR9 fast-path query shape), `TransitionStatus`, `DeferAssertion`/`RetryDeferred` (fingerprint-gated, mirrors the P2 candidate defer/retry gate).
- `evidence_store.go` — `EvidenceStore`: `AddEvidence` (a new `supports` row auto-restores an `unsupported` assertion to `accepted`), `DeleteEvidence` (soft-delete; demotes to `unsupported` only when it was the *last* active `supports` row), `ListForAssertion`.
- `relations_store.go` — `RelationStore` for conflict/supersession links.

### A3 — Bugs found by live validation (would have shipped silently)

1. **JSONB `NULL` vs. JSON `null` scan failure.** Scanning a genuine SQL `NULL` from a `jsonb` column into `json.RawMessage` errored (`unsupported Scan, storing driver.Value type <nil>`) against real Postgres; sqlmock's text-based query matching never exercises this. Fixed by sending the JSON literal `"null"` instead of SQL `NULL` for empty JSONB fields (`qualifiers`, `object_literal`), matching the convention P2's candidate store already established for `source_line_spans`/`candidate_matches` — this is the second time this exact class of bug has been caught only by live validation (see the P2 log's `RETURNING`-with-`FROM` bug for the first).
2. **Foreign-key ordering on cleanup.** A validation script's cleanup order (delete assertions before decision candidates that reference them via `resulting_assertion_id`) violated the FK; harmless in the validator itself but a reminder that `kb.semantic_decision_candidates.resulting_assertion_id` is a real referential constraint or a future run's cleanup/retention code must respect.

### A4 — Live-Postgres validation

Via a temporary `server/cmd/p3validate` program (deleted after use, per the P1/P2 precedent) against `chenweb_test`: create candidate assertion → add evidence → `in_review` → `accepted` → delete last evidence → **auto-demotes to `unsupported`** → add evidence → **auto-restores to `accepted`** → create a second, conflicting assertion → record `conflicts_with` → both remain independently queryable → deferred/retry fingerprint gate (unchanged fingerprint rejected, changed fingerprint accepted). **All checks passed.**

## 3. Chunk B — `kb.semantic_decision_candidates` (complete)

### B1 — Migration

`20260801000004`: `kb.semantic_decision_candidates` — the Phase D counterpart to P2's `kb.ontology_candidates`. Uses the same `logical_identity_key`+`revision` pattern as `kb.semantic_assertions`, plus `payload_fingerprint` to distinguish "reprocessing produced the same payload" (bump `last_seen`) from "reprocessing produced a decision-relevant change" (new revision, supersede the prior completed one). `status` uses the operational vocabulary **minus** `unsupported`, since spec §9.3 defines that transition as assertion-only.

### B2 — Store

`decision_candidates_store.go` — `DecisionCandidateStore.Propose` implements the dedup/revision logic; `PayloadFingerprint` is a key-order-independent sha256 over the canonicalized payload (verified by test: `{"a":1,"b":2}` and `{"b":2,"a":1}` fingerprint identically). `TransitionStatus`/`DeferCandidate`/`RetryDeferred`/`SetResolution`/`SetResultingAssertion` round out the lifecycle.

### B3 — Live-Postgres validation

Propose → re-propose identical payload (different JSON key order) → **reused, same revision** → `in_review` → `accepted` → attempted `accepted → unsupported` **correctly rejected** (proving the candidate machine's restricted arc set, not the assertion machine's) → propose a decision-relevant payload change → **new revision 2, revision 1 auto-superseded** → separate ambiguous-target candidate → deferred with reason `ambiguous_targets` → retry-with-unchanged-fingerprint rejected, retry-with-changed-fingerprint accepted → linked to a resulting assertion. **All checks passed.**

## 4. Chunk C — normalizer registry (seam 5) and `normalize_assertions` (complete)

### C1 — Registry

`normalizer_registry.go` — `AssertionNormalizerRegistry` (DR11 seam 5): `RegisterNormalizer`/`LookupNormalizer`/`RegisteredFamilies`. Each normalizer self-registers via a package-level `init()` in its own file (the `database/sql` driver-registration idiom), so adding a family requires zero edits to the registry or to the Phase D stage — verified structurally, since `metric_normalizer.go` and `provision_normalizer.go` are the only two files that call `RegisterNormalizer`.

### C2 — Metric normalizer, and a real finding about the pilot corpus

`metric_normalizer.go` reads `kb.metrics` (LEFT JOIN `kb.artifact_objects` for the subject referent) and proposes one `assertion`-kind candidate per row. Rather than requiring `extract_metrics` to change its output schema first (a separate, larger, real-data-gated change — see §6), the normalizer performs the DR8-specified text-to-structured parsing itself, on `threshold_or_target`.

**Live validation against the actual gold corpus in `chenweb_test`** (not just synthetic fixtures) surfaced two real findings:

1. The corpus is **predominantly Chinese-language** standard text (`不低于250 cd/m²`, `不超过120 ms`, `500:1 至 2000:1`), and the initial English-only comparator vocabulary silently produced `unparsed` for every real row. Fixed by adding the Chinese comparator/range forms actually observed in the corpus (不低于/不小于/至少, 不超过/不大于/不高于, 至). This is recorded here explicitly because it is exactly the kind of gap that stays invisible without testing against real data — the synthetic English fixtures all passed before this fix.
2. **Contrast-ratio notation** (`500:1`) confused the naive numeric-range regex: it captured the `1` in `500:1` as a range endpoint instead of `500`. Fixed with a preprocessing step that collapses `N:1` to `N` before range/number matching (`raw_text` is untouched — only the parse path sees the collapsed form).

After both fixes, live validation against `input_record_id=2`'s 8 real metric rows produced 6 correctly-parsed structured assertions (`lower_bound_requirement`/`upper_bound_requirement`/`interval_requirement`/`observed_value` as appropriate) and 2 honest `unparsed` results for genuinely non-numeric text (e.g. "1 m 距离处清晰辨识"), never a fabricated value.

### C3 — Provision normalizer

`provision_normalizer.go` extracts modality from provision text, again with both English and the corpus's actual Chinese vocabulary (应/须/必须 required, 不应/不得/禁止/严禁 prohibited — checked *before* their unnegated substrings per the negation-first ordering rule, since 不应 contains 应, 可 permitted, 宜 recommended).

### C4 — Phase D wiring

`ChenWeb/server/api/doc-processing/normalize_assertions.go` — `SemanticAssociationEnabledFromEnv()` (mirrors the existing `DocPipelineModeFromEnv` pattern) and `ControlService.runNormalizeAssertions`, called from `control.go` immediately after Phase C (`runPostProcessIndexing`), gated by `SEMANTIC_ASSOCIATION_ENABLED` (default `false`, matching the ADR config table — this is a purely additive, currently-inert code path in production).

### C5 — Live-Postgres validation

Ran both normalizers directly against real `kb.metrics`/`kb.provisions` rows already in `chenweb_test` from prior P0 benchmark ingestion (not seeded by this session): 10 metrics + 10 provisions examined and proposed on first run; **re-running the metric normalizer over the same record reused every candidate with zero new proposals**, proving the fingerprint dedup holds over real data, not just constructed fixtures.

## 5. Chunk D — `associate_semantics` (complete for the metric family; provisions correctly block on a real content gap)

### D1 — Implementation

`associate_semantics.go` implements spec §10.3–§10.7 (resolve → validate → adjudicate → persist) over `candidate`-status rows in `kb.semantic_decision_candidates`. Adjudication is **deterministic-only** this slice (spec §16.3 item 4 — "an LLM-only recommendation cannot activate an assertion" — is trivially satisfied because no LLM-scored path exists yet; a future one plugs in as an additional candidate input, never a direct writer, per the plan's deferred-items list).

For the **metric** family: resolves the subject via the candidate's `subject_object_id` (propagated from chunk C's `kb.artifact_objects` join); validates that the parsed `assertion_kind` is one of the seven governed kinds P2's `measurement` module actually installed (`lower_bound_requirement`/`upper_bound_requirement`/`interval_requirement`/`observed_value`/`target`/`reference`/`capability`) and that both the assertion-kind term and `mea:measured_by` exist with `status='included_in_release'` in `kb.ontology_terms` (a real DB check, not a hardcoded assumption); on success, persists a `kb.semantic_assertions` row (with the normalized value columns, `object_literal` echo, and `qualifiers` carrying the free-text metric name since no governed metric-specific property term exists yet — DR23/`extract_metric_definitions` is explicitly P3–P4), attaches supporting evidence, and walks it through `in_review → accepted`.

For the **provision** family: every candidate defers with reason `no_governed_deontic_predicate`. This is not a shortfall in this slice's logic — **no term for "required"/"prohibited"/"permitted" exists anywhere in the P2-installed `core` module** (verified directly against `kb.ontology_terms WHERE module_id='core'`: 19 terms, none deontic). Spec §10.5 is explicit that missing context produces `deferred`, never an invented target, so this is the pipeline behaving correctly in the presence of a real, documented vocabulary gap.

### D2 — A real finding: the gold corpus's metric artifacts were never object-reconciled

Live validation found `SELECT count(*) FROM kb.artifact_objects WHERE artifact_type='metric'` returns **zero** rows across the entire `chenweb_test` database, while `provision` and `inventory_item` are fully reconciled (143 and 21 rows respectively, all with `object_id` populated). Every metric-family candidate in the existing corpus therefore defers with reason `unresolved_referent` when run unmodified. To prove the accept path genuinely works (not just that it compiles), validation synthetically reconciled exactly one real metric artifact (`2_mtc_1`) to a real, pre-existing `kb.object_nodes` row, then ran the full record through both Phase D stages:

- **8 examined, 1 accepted, 7 deferred, 0 rejected.**
- The accepted assertion: subject = the real object node, predicate = `mea:measured_by`, assertion kind = `mea:lower_bound_requirement`, comparator `>=`, numeric value `250`, `raw_text` = `"不低于250 cd/m²"` (untouched), one supporting evidence row.
- The 7 deferred candidates: `dependency_fingerprint = "unresolved_referent"`.
- Re-running `associate_semantics` over the same record found **zero** remaining `candidate`-status rows (idempotent; nothing reprocessed).

Whether `MetricsProcessor` should call object reconciliation (mirroring `ProvisionsProcessor`'s `persistProvisionObjects`) is outside this slice's scope — it is upstream Phase B/C processor behavior, not Phase D — but it is the reason essentially all real metric assertions currently defer, and is recorded here so a future session does not mistake the defer rate for a Phase D bug.

## 6. Deferred beyond this slice

Recorded here, in the same spirit as the P2 log's §5, so a later phase or handoff never mistakes chunks 0–D for all of P3:

1. **`kb.artifact_semantic_links`** (the `about_term`/`describes_occurrence`/`aligns_to_term` table sketched in the plan's chunk D scope). Not created this slice: the only two normalized families (metric, provision) both produce `assertion`-kind candidates that persist to `kb.semantic_assertions`, not artifact-level "about" links — no in-scope family needs this table yet. It belongs with whichever future normalizer first needs it (entity/summary/topic/scene, per spec §10.10), rather than existing unused.
1. **`project_semantics` (chunk E)** — `kb.projection_state`, the `ProjectionBuilderRegistry` (seam 7), and `kb.object_nodes.primary_class_term_id` maintenance from accepted `core:instance_of` assertions. Not started.
2. **Chunk F** — association-run telemetry (spec §10.9), the deferred/ambiguous backlog drain (reusing the ADR `2026070701` DR5/DR6/DR7 pattern), and the consolidated spec §16.2/§16.3 exit-criteria test suite. Not started as a dedicated suite, though every acceptance item chunks A–D individually target has been live-verified inline (see §2–§5 above).
3. **The keyword lexicon (Track B)** — design complete (`2026080101-spec-keyword-canonicalization-merged.md`); no code. `KEYWORD_RESOLVER_MODE` stays at its `off` default.
4. **Object reconciliation for the metric artifact family.** `kb.artifact_objects` has zero rows for `artifact_type='metric'` anywhere in `chenweb_test` — a Phase B/C gap (§5, D2), not a Phase D one, but it is the reason nearly every real metric candidate currently defers.
5. **A governed deontic predicate for provisions** (`core:required`/`core:prohibited`/`core:permitted` or equivalent). Without it, every provision-family candidate defers by design (§5). Authoring this is an ontology-content change (P2-style module authoring), not a Phase D code change.
6. **Rewriting `extract_metrics`/`extract_provisions` to emit structured fields directly**, rather than the normalizer parsing free text. Unchanged from the plan's original deferral — still gated on a real (non-synthetic) worked example per the standing P0 deferral.
7. **`extract_metric_definitions`** (DR23 metric-definition harvesting) — unchanged, explicitly P3–P4.
8. **LLM-assisted adjudication in `associate_semantics`.** Deterministic-only this slice; additive to add later.
9. **Unit-term resolution against the QUDT catalog** (`quantity_kind_term_id`/`unit_term_id` on accepted metric assertions are currently left empty; the raw unit string is preserved in the metric candidate's payload but not yet resolved to a `quantity:unit_*` term). A real, scoped follow-up — the 4151-term QUDT catalog P2 imported is exactly the target, but string-to-term matching (labels, symbols, aliases) is its own piece of work.

## 7. Files touched

- `ChenWeb/project_migrations/20260801000001..000004_*.sql` (4 migrations)
- `ChenWeb/server/api/ontology/assertions/{state_machine,assertions_store,nullable,evidence_store,relations_store,decision_candidates_store,normalizer_registry,metric_normalizer,provision_normalizer,associate_semantics}.go` + corresponding `_test.go` files
- `ChenWeb/server/api/doc-processing/{normalize_assertions,associate_semantics}.go` + `normalize_assertions_test.go`
- `ChenWeb/server/api/doc-processing/control.go` (two-line Phase D wiring after Phase C, gated by `SEMANTIC_ASSOCIATION_ENABLED`)
- `KnowledgeStore/doc-repo/specs/202608/2026080101-spec-keyword-canonicalization-merged.md`
- `KnowledgeStore/doc-repo/plan/202608/2026080102-plan-semos-p3-assertions-evidence-and-phase-d-association.md`
- `KnowledgeStore/doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md` (DR16 status annotation)

## 8. Targeted tests

```bash
go test ./server/api/ontology/assertions/... -count=1
go test ./server/api/doc-processing/... -run 'TestSemanticAssociationEnabledFromEnv' -count=1
```

Full `go build ./...` and `go vet ./server/api/ontology/... ./server/api/doc-processing/...` pass. `go test ./server/api/doc-processing/...` (full package) shows 21 pre-existing failures (summary/topic/connections/scene-block/metric-category tests) unrelated to this slice — spot-checked one (`TestBuildSummaryID`) and confirmed it is a plain string-format assertion mismatch in unrelated code with no DB dependency, not a P3 regression; none of the 21 failing test names touch any file this slice added or changed.

## 9. Status

**Chunks 0–D are complete against their stated scope and live-validated against real Postgres, including real gold-corpus data** (not only synthetic fixtures). Chunk E, chunk F, and Track B (keyword lexicon) remain — see §6.
