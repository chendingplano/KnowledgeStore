# SemOS P3 Implementation Log — Assertions, Evidence, and Phase D Association (chunks 0–F)

**Date:** 2026-08-01
**Scope:** Execution log for the P3 slice built this session, following plan `2026080102-plan-semos-p3-assertions-evidence-and-phase-d-association.md`, in `ChenWeb`. Chunks 0–D and 0–E were recorded first (see the git history of this file); this revision adds chunk F, closing out P3 Track A.

## 0. Summary — what this slice is, and what it deliberately is not

This slice covers **all of Track A, chunks 0–F** of the P3 plan: the DR9 assertion/evidence schema, the operational association-candidate lifecycle, the DR11 seam-5 normalizer registry with metric and provision instances, all three DR8 Phase D stages (`normalize_assertions`, `associate_semantics`, `project_semantics`), association-run telemetry (spec §10.9), the deferred-candidate backlog drain, and the spec §16.2/§16.3 exit-criteria mapping. It does **not** cover Track B (the keyword lexicon, design-complete per `2026080101-spec-keyword-canonicalization-merged.md` but not built) or anything from P4 onward. See §8 for the precise deferred boundary.

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

## 6. Chunk E — `project_semantics` and `kb.projection_state` (complete)

### E1 — Migration

`20260801000005`: `kb.projection_state` — one row per `(projection_kind, projection_target_table, projection_target_id)`, recording the authoritative source (`authoritative_table`/`authoritative_id`/`authoritative_revision`) a projection was last built from, a `projection_version` build counter, and a `stale`/`stale_reason` pair. Rebuilding overwrites the row; the authoritative history lives in the source table's own revision chain, not here.

### E2 — `ProjectionBuilderRegistry` (seam 7) and the classification projection

`projection_registry.go` — `ProjectionBuilderRegistry`: `RegisterProjectionBuilder(kind, build, repair)`/`LookupProjectionBuilder`, plus `ProjectionStateStore` (`Upsert`/`Get`/`MarkStale`/`ListStale`). `repair` returns `(repaired bool, err error)` rather than just `error` — deliberately, so a sweep can report "found and fixed corruption" as a distinct, observable outcome from "already correct," per spec §16.2 item 6's "detected as stale."

`classification_projection.go` — the DR10 projection this slice builds: `kb.object_nodes.primary_class_term_id`, closing the P2 chunk E deferral ("primary_class_term_id is a DERIVED projection... not yet populated: classification-as-assertion needs the assertion store"). `primaryClassificationFor` picks the deterministic "primary" classification as the earliest-accepted `core:instance_of` assertion for an object (an object may carry several simultaneous accepted classifications per research §5.2/CQ-I03; this column is a read-optimized convenience pointer to one of them, never the system of record). `buildPrimaryClassProjection` writes the column and the `projection_state` row (or clears both if no accepted classification exists); `repairPrimaryClassProjection` compares the materialized value against what the authoritative source currently implies and only writes if they differ, reporting whether a fix occurred.

`project_semantics.go` — `ProjectSemantics.Run(ctx, inputRecordID)` finds the objects touched by this record's newly-accepted `core:instance_of` assertions (via `assertion_evidence.input_record_id`, joined to `semantic_assertions`) and rebuilds their projections; `RepairStaleProjections(ctx, db, kind)` is a standalone sweep (not scoped to one record) that unions every already-`stale`-flagged target with every *known* target for the kind — the latter is necessary because a direct hand-edit of `kb.object_nodes.primary_class_term_id` never touches `kb.projection_state.stale`, so a stale-only sweep would miss it.

### E3 — A prerequisite fix: `associate_semantics` never populated `evidence.input_record_id`

Chunks A–D's evidence rows all left `input_record_id` `NULL` — harmless for those chunks (nothing read it), but `project_semantics`'s per-record scoping depends on it. Fixed by threading `inputRecordID` through `processOne`/`processMetric` into the `AddEvidence` call. A real, if minor, correctness gap the chunk-D live validation didn't need to exercise but chunk E's did.

### E4 — Phase D wiring

`ChenWeb/server/api/doc-processing/project_semantics.go` — `ControlService.runProjectSemantics`, called from `control.go` immediately after `runAssociateSemantics`, gated by the same `SEMANTIC_ASSOCIATION_ENABLED` flag.

### E5 — A real gap this chunk had to synthesize around: nothing produces classification assertions yet

Neither the metric normalizer (produces `mea:measured_by` assertions) nor the provision normalizer (defers, per §5) emits `core:instance_of` assertions — no normalizer in this or any prior P3 slice classifies anything. `project_semantics` therefore has no real Phase D output to project from today; validating it required directly authoring `core:instance_of` assertions through `AssertionStore` (the same technique chunks A/B used before any normalizer existed), not driving it end-to-end from the gold corpus. This mirrors P2's own precedent for `object_nodes.merged_into`/`scope_key`: "the columns exist and stay unpopulated by existing paths... adopted incrementally." A future entity or inventory-item normalizer is the natural first real producer of classification assertions.

### E6 — Live-Postgres validation

Via a second temporary `server/cmd/p3validate` program (deleted after use): with zero classification assertions, a run correctly examines zero targets → author and accept a `core:instance_of` assertion for a real `kb.object_nodes` row → `project_semantics` builds the projection, `kb.object_nodes.primary_class_term_id` is set, `kb.projection_state` records the correct authoritative assertion id/revision → **directly hand-corrupt** the materialized column (bypassing the projection mechanism entirely) → `RepairStaleProjections` detects and repairs it, reporting `repaired=1` → re-running the sweep on an already-correct projection reports `repaired=0` (idempotent) → create a decision-relevant revision of the classification assertion (superseding the first) → `project_semantics` rebuilds, the materialized column and `projection_state` both follow the new authoritative assertion id and revision. **All checks passed.**

## 7. Chunk F — association telemetry, backlog drain, exit criteria (complete)

### F1 — A prerequisite schema fix: `input_record_id` on `kb.semantic_decision_candidates`

Telemetry needs to reconcile every candidate examined for one input record. The only existing way to do that was parsing the record id back out of `logical_identity_key` (e.g. `"metric:2:2_mtc_1"`) — fragile, and the same class of gap chunk E already found and fixed on `kb.assertion_evidence`. Migration `20260801000006` adds a real `input_record_id` column; `DecisionCandidate` gained the field, both normalizers now populate it, and `AssociateSemantics.Run`'s candidate query was switched from a `LIKE` string match to an indexed equality filter.

### F2 — Association-run telemetry (spec §10.9) and Phase D consolidation

`telemetry.go` — `AssociationRunReport` (artifacts examined, candidates by method, resolution outcomes, lifecycle counts, new assertions, deterministic-vs-human decision counts, stage timings/errors) and `BuildAssociationRunReport`, which queries the *latest revision per logical identity* for one record and buckets it three ways from the exact same row set, so `Reconciles()` — every bucket's total must equal `ArtifactsExamined` — holds by construction, not by hope (spec §16.3 item 17).

This is also where the three per-stage `ControlService` wrapper functions chunks C–E built (`runNormalizeAssertions`, `runAssociateSemantics`, `runProjectSemantics`) were consolidated into one `assertions.RunPhaseD` orchestrator plus a single `ControlService.runPhaseD` call site (`phase_d.go`, replacing the three now-redundant doc-processing files). `RunPhaseD` runs all three stages in order, times each one, captures (without aborting on) per-stage errors, and returns the reconciliation report — strictly more capable than the three separate calls it replaces, calling the exact same already-tested `Normalize`/`Run` methods underneath. `control.go` now has one Phase D call site instead of three.

### F3 — A real bug the drain work found: `Propose` left stale revisions un-superseded

`DecisionCandidateStore.Propose`'s revision-supersede logic originally fired only when the prior revision was `accepted` or `rejected`. A `deferred` or `candidate` prior was left un-retired when a new revision was created — meaning if a candidate's payload changed while it was still non-terminal, **two revisions of the same logical association could sit in a processable status simultaneously**, and a later stage would reprocess the stale one. Fixed: a new revision now supersedes whichever revision was current before it, unconditionally (`prior.Status != StatusSuperseded`), because a new revision replacing the old one is true regardless of what stage the old one had reached. Found live, not by inspection — see F4.

### F4 — Backlog drain: the first design was wrong, and live validation caught it

`backlog_drain.go` — `DrainDeferredCandidates` reuses the ADR `2026070701` DR5 bulk-backfill pattern (a `POST` endpoint, safe to call repeatedly, no admin-review-page or LLM-auto-resolution scope this slice — see §8) for candidates deferred with reason `unresolved_referent`, the dominant real blocker chunk D found.

The first implementation directly flipped a deferred candidate back to `candidate` via `RetryDeferred` once its referent resolved in `kb.artifact_objects`, reusing the spec §16.3 item 12 fingerprint-gated retry mechanism. **Live validation caught this as wrong**: `RetryDeferred` only changes `status`, never `proposed_payload` — so the candidate was reprocessed with its *original, still-empty* `subject_object_id`, and deferred again on stale data. The fix is not "retry harder" but a different mechanism entirely: **re-run the metric normalizer** for the affected record. A resolved referent changes the payload (`subject_object_id` gets populated), so re-normalizing naturally produces a different `payload_fingerprint`, which `Propose` already turns into a correctly-superseding fresh revision (once F3's fix was in place) — the dependency-fingerprint retry gate is the right tool for a defer reason where the payload is *unchanged* and something external changed (e.g. a governed term being released later), not for a resolved-referent defer, where the payload itself is what changes. `DrainDeferredCandidates` now re-normalizes, then calls `associate_semantics` for each affected record.

### F5 — HTTP endpoint

`kbhandler/drain_deferred_decisions_handler.go` — `DrainDeferredSemanticDecisions`, `POST /kb/semantic-decisions/drain-deferred?limit=N`, mirroring `ResolveAmbiguousObjects`'s handler shape exactly (same `errorResponse`/`parsePositiveInt`/`EchoFactory` conventions). No admin review page (DR6) or LLM auto-resolution (DR7) — both are legitimate scope-outs: DR6 is frontend work not verifiable without running and clicking through the dev server, and DR7 has no LLM path to gate in this domain yet.

### F6 — Exit-criteria mapping (spec §16.2/§16.3) and a second real bug it found

`p3_exit_test.go` maps every P3-relevant spec §16.2/§16.3 item to either a permanent test or a pointer to where live validation already proved it, mirroring `../candidates/p2_exit_test.go`'s exact convention. Writing the mapping for item 13 ("a transient resolution/adjudication failure leaves the candidate non-terminal and can resume idempotently") surfaced a second real gap: `AssociateSemantics.Run` only ever queried `status = 'candidate'`, so a crash between the `in_review` transition and the accept/defer decision left a row stuck at `in_review` **forever** — no automatic path ever picked it back up. Fixed: `Run` now selects `status IN ('candidate', 'in_review')`, and `processOne` skips re-transitioning a row that is already `in_review` (which would otherwise be refused by the state machine) rather than assuming it always starts fresh.

### F7 — Live-Postgres validation

Via a third temporary `server/cmd/p3validate` program (deleted after use), against real gold-corpus data (record 2, the same 8-metric record used for chunk D):

- `RunPhaseD` end-to-end: `examined=8`, `by_method={explicit_structured:8}`, `outcomes={deferred:7, matched:1}`, `lifecycle={accepted:1, deferred:7}`, `new_assertions=1`, `reconciles=true`, zero stage errors, real per-stage timings in the single-digit milliseconds.
- Backlog drain: synthetically resolve a second metric's referent → drain → `{RecordsScanned:1, RecordsReprocessed:1, Accepted:1, Deferred:0, Rejected:0}`, the resolved metric's assertion now `accepted` with the correct subject/predicate/assertion-kind → **re-running the drain immediately** with nothing newly resolved reports `Accepted:0` (idempotent; the 6 genuinely-unresolved metrics are correctly left alone and still scanned).
- `in_review` resumability: propose a candidate, manually drive it to `in_review` (simulating a crash before the resolve decision), confirm it stays non-terminal, call `AssociateSemantics.Run` again → the stuck candidate is picked up and resolved to `accepted`.

**All checks passed.**

## 8. Deferred beyond this slice

Recorded here, in the same spirit as the P2 log's §5, so a later phase or handoff never mistakes chunks 0–F for all of P3:

1. **`kb.artifact_semantic_links`** (the `about_term`/`describes_occurrence`/`aligns_to_term` table sketched in the plan's chunk D scope). Not created this slice: the only two normalized families (metric, provision) both produce `assertion`-kind candidates that persist to `kb.semantic_assertions`, not artifact-level "about" links — no in-scope family needs this table yet. It belongs with whichever future normalizer first needs it (entity/summary/topic/scene, per spec §10.10), rather than existing unused.
2. **The DR6 admin review page and DR7 LLM auto-resolution** for the backlog drain. The DR5 bulk endpoint (§F5) is built; DR6 is frontend work not verifiable without running and clicking through the dev server, and DR7 has no LLM path to gate in this domain yet — both legitimate scope-outs, not gaps in the drain mechanism itself.
3. **A governed-term-availability backlog drain.** `DrainDeferredCandidates` targets specifically `unresolved_referent` (§F4) — the dominant real blocker. A drain for candidates deferred on a not-yet-released governed term is a natural, separable follow-up if a released module is ever rolled back after candidates were deferred on it; not built because no such case has been observed.
4. **The keyword lexicon (Track B)** — design complete (`2026080101-spec-keyword-canonicalization-merged.md`); no code. `KEYWORD_RESOLVER_MODE` stays at its `off` default.
5. **Object reconciliation for the metric artifact family.** `kb.artifact_objects` has zero rows for `artifact_type='metric'` anywhere in `chenweb_test` — a Phase B/C gap (§5, D2), not a Phase D one, but it is the reason nearly every real metric candidate currently defers (and why the backlog drain in §F4 exists).
6. **A governed deontic predicate for provisions** (`core:required`/`core:prohibited`/`core:permitted` or equivalent). Without it, every provision-family candidate defers by design (§5). Authoring this is an ontology-content change (P2-style module authoring), not a Phase D code change.
7. **A real producer of classification (`core:instance_of`) assertions.** Chunk E's mechanism is complete and live-validated, but no normalizer in this workspace emits classification assertions yet (§E5) — a real gap for a future entity/inventory-item normalizer to close, not a Phase D bug.
8. **Item 15's input-deletion cascade** (deleting one input removes only its document-scoped candidates/evidence). Not built this slice — no input-deletion cascade exists yet at all for the P3 stores.
9. **Item 9's lexical/semantic/structural candidate exercise.** No normalizer in this slice uses any method besides `explicit_structured`, so the "remain candidates until approved" property for those three methods is untested against real candidates — the state machine enforces it structurally regardless of method, but this is recorded as an explicit non-claim rather than implied coverage.
10. **Rewriting `extract_metrics`/`extract_provisions` to emit structured fields directly**, rather than the normalizer parsing free text. Unchanged from the plan's original deferral — still gated on a real (non-synthetic) worked example per the standing P0 deferral.
11. **`extract_metric_definitions`** (DR23 metric-definition harvesting) — unchanged, explicitly P3–P4.
12. **LLM-assisted adjudication in `associate_semantics`.** Deterministic-only this slice; additive to add later.
13. **Unit-term resolution against the QUDT catalog** (`quantity_kind_term_id`/`unit_term_id` on accepted metric assertions are currently left empty; the raw unit string is preserved in the metric candidate's payload but not yet resolved to a `quantity:unit_*` term). A real, scoped follow-up — the 4151-term QUDT catalog P2 imported is exactly the target, but string-to-term matching (labels, symbols, aliases) is its own piece of work.

## 9. Files touched

- `ChenWeb/project_migrations/20260801000001..000006_*.sql` (6 migrations)
- `ChenWeb/server/api/ontology/assertions/{state_machine,assertions_store,nullable,evidence_store,relations_store,decision_candidates_store,normalizer_registry,metric_normalizer,provision_normalizer,associate_semantics,projection_registry,classification_projection,project_semantics,telemetry,backlog_drain}.go` + corresponding `_test.go` files + `p3_exit_test.go`
- `ChenWeb/server/api/doc-processing/phase_d.go` (replaces the three now-redundant `normalize_assertions.go`/`associate_semantics.go`/`project_semantics.go` doc-processing wrapper files) + `phase_d_test.go` (renamed from `normalize_assertions_test.go`)
- `ChenWeb/server/api/doc-processing/control.go` (one Phase D call site, gated by `SEMANTIC_ASSOCIATION_ENABLED`)
- `ChenWeb/server/api/kbhandler/drain_deferred_decisions_handler.go`
- `ChenWeb/server/api/routes.go` (`POST /kb/semantic-decisions/drain-deferred`)
- `KnowledgeStore/doc-repo/specs/202608/2026080101-spec-keyword-canonicalization-merged.md`
- `KnowledgeStore/doc-repo/plan/202608/2026080102-plan-semos-p3-assertions-evidence-and-phase-d-association.md`
- `KnowledgeStore/doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md` (DR16 and P3 status annotations)

## 10. Targeted tests

```bash
go test ./server/api/ontology/assertions/... -count=1
go test ./server/api/doc-processing/... -run 'TestSemanticAssociationEnabledFromEnv' -count=1
```

Full `go build ./...` and `go vet ./server/api/ontology/... ./server/api/doc-processing/... ./server/api/kbhandler/...` pass. `go test ./server/api/doc-processing/...` (full package) shows 21 pre-existing failures (summary/topic/connections/scene-block/metric-category tests) unrelated to this slice — spot-checked one (`TestBuildSummaryID`) and confirmed it is a plain string-format assertion mismatch in unrelated code with no DB dependency, not a P3 regression; unchanged at 21 across chunks D, E, and F. `go test ./server/api/kbhandler/...` shows 2 pre-existing failures in `topic_category_handler_test.go` (PDF coordinate/topic-text parsing) — confirmed unrelated: this slice's only kbhandler change is the new `drain_deferred_decisions_handler.go` file, and neither failing test touches topics, categories, or PDF coordinates in any way connected to semantic decisions.

## 11. Status

**Chunks 0–F are complete against their stated scope and live-validated against real Postgres, including real gold-corpus data** (not only synthetic fixtures). This closes out P3 Track A. Track B (the keyword lexicon) remains — design is done (`2026080101-spec-keyword-canonicalization-merged.md`), code is not.

Two real correctness bugs were found and fixed by this chunk's live validation, not by inspection: `DecisionCandidateStore.Propose` left a stale `candidate`/`deferred` revision un-superseded when a new revision was created (§F3), and `AssociateSemantics.Run` never resumed a candidate orphaned at `in_review` by a crash (§F6). Both are the kind of gap sqlmock-only testing structurally cannot catch — the same lesson chunks A and B already recorded once each with the JSONB-`NULL`-scan and `RETURNING`-with-`FROM` bugs.
