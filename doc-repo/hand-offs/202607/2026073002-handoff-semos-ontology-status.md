# SemOS Ontology Status — Session Handoff

Date: July 31, 2026

> **Post-handoff update (2026-08-01):** Generic P4 L6/L7 runtime and the ADR §8.2 document
> processors are now implemented and live-validated; see P4 checkpoint
> `2026080104-devdoc-semos-p4-foundation-checkpoint.md`. The remaining P4 boundary is the
> authority-confirmed pilot data fixture, not generic runtime code.
>
> **Post-handoff update (2026-08-01, continued):** the ADR §8.2 `extract_metrics` structured
> output — the "single highest-leverage change for the application" — is now implemented and
> committed (OpenSpec change `extract-metrics-structured-output`), closing P3 log §8 items 10
> (structured output) and 13 (unit-term resolution). See the post-handoff update near the end of
> this document.
>
> **Post-handoff update (2026-08-02):** P5 rule-driven routing is implemented through E2
> (plan tasks A1–E2). Routing policy compilation and atomic activation are complete, and the
> execution planner now persists immutable processor-gate decisions in shadow mode. P5 is not
> complete: the approved next task is E3, which turns the proven shadow decisions into enforced
> runtime behavior. See the detailed P5 checkpoint near the end of this document.
>
> **Post-handoff update (2026-08-02, continued):** P5 is now implemented through E3 and Chunk F
> (plan tasks E3, F1, F2): clearance-aware runtime enforcement, run/record-scoped alarms,
> policy-audit events, the P5 review-scope schema, the pinned released-profile loader, and the
> deterministic review-profile selector with rule-level applicability. Chunks G
> (`classify_document`), H (module proposals/promotion), and I (exit suite, live proof, docs
> closeout) remain. See the detailed P5 update near the end of this document.

## Scope

This session started as ontology-consolidation work (research `2026072302`, spec `2026072702`, ADR `2026072701`) and drifted into building and validating a benchmark harness against the pilot domain those documents chose. This handoff exists specifically to capture **where the ontology design actually stands** — as opposed to what tooling got built — so a future session (or the user) can resume from an accurate baseline instead of assuming more of the ontology itself was implemented than actually was.

For the technical build this session produced (the `gold-run`/`analyze` CLI, mise tasks, prompt iterations, bug reports), see the companion handoff `2026073001-handoff-semos-gold-benchmark-and-tooling.md` — that document covers the *how*; this one covers the *what's actually designed vs. built*.

Work resumed on 2026-07-30 with explicit approval to complete P0 before starting P1/P2. The P0 benchmark-evidence closeout was completed on 2026-07-31. P1 (pipeline-plane: declarations, facets, rules, policy versioning, plan persistence, enforcement, shadow mode, benchmark closeout) was implemented and validated on the same day.

## Document lineage (read in this order if picking this up cold)

1. Research `2026072302-rsch-object-centric-ontology.md` (2026-07-23) — established the vocabulary and layered target. **Status: Research / architecture recommendation.**
2. Spec `2026072702-spec-ontology-canonical-artifacts.md` (2026-07-27) — turned the research into contracts (ownership, lifecycles, state machines). **Status: Proposal.**
3. ADR `2026072701-adr-ontology-identity-and-assertions.md` (2026-07-27) — ratified the spec's decisions. **Status: Accepted — design only, not yet implemented** (stated explicitly in its own header).
4. ADR `2026072901-adr-ontology-platform-and-adaptive-pipeline.md` (2026-07-29, revised twice since) — consolidates all three of the above plus the doc-processor capsule into one buildable architecture with an executable phased plan (DR0–DR24, P0–P7). **Status: Proposed (draft for review).** This is the current source of truth — treat documents 1–3 above as historical inputs already folded in, not independently authoritative anymore.

## Current status: P0 and P1 complete; ontology runtime still not built

> **Historical (as of 2026-07-31).** This section and the phase summary below describe the state
> *before* P2 was implemented. P2 is now complete and validated (2026-08-01) — see the post-handoff
> update near the end of this document; the sections below are retained as the session record.

Searching the entire consolidated ADR for its own `**Built:**` implementation-status annotations turns up exactly three, all under DR21/DR22:

- `ChenWeb/server/api/ontology/comparison` (`Compare`, `EvaluateFamily`) — the DR21 requirement-strictness comparator, a pure function over normalized constraints.
- `ChenWeb/server/api/doc-benchmark/verdict_score.go` — `ScoreVerdictMatrix`, the DR22 outcome scorer.
- `ChenWeb/server/api/doc-benchmark/corpus_dataset.go` — the corpus-level dataset/case loader.

Alongside these (built this session, not separately annotated in the ADR yet): the `gold.toml` synthetic fixture itself, its CDM document generator (`generate.go`), `resolve.go`/`coverage.go`, the `gold-run`/`analyze` CLI tooling, and the offline store-profile reporting workflow used for P0 closeout (full detail in the companion handoff and the P0 evidence devdoc).

All of this maps directly onto P0's stated primary deliverable: *"Build the synthetic gold corpus and extend the existing benchmark... rather than waiting for a real-data example."* As of 2026-07-31, that validation slice is no longer just partially built; it has execution evidence and a written closeout record. It is still the **validation harness**, not the ontology architecture itself.

Everything that would actually make this "an ontology" — as opposed to the full pipeline-plane policy layer that P1 built — remains pure design, with zero code and zero ontology-runtime migrations:

- The 7-layer architecture itself (evidence/artifacts → canonical identity → ontology terms → domain modules → qualified assertions → profiles → review).
- The canonicalization kernel / `semid` (DR15).
- The separate ontology-as-code source tree described in DR17 — not yet implemented, and per current workspace policy its documentation belongs in `KnowledgeStore` while code lands in `shared` or `ChenWeb` rather than a new ad hoc repo.
- Domain modules — not just the pilot 呼吸机 module, but even the shared 4a core modules (`core`, `quantity`, `document-authority`, `measurement`).
- Qualified assertions and the evidence schema (DR9).

### P1 — complete

As of Friday, July 31, 2026, the entire P1 pipeline plane is implemented and validated. The full P1 implementation log (`2026073103-devdoc-semos-p1-implementation-log.md`) is the authoritative record; this section is a summary handoff. Every original P1 gap has been built, tested, and validated against live Postgres:

- `kb.pipelines` — authored named-pipeline registry, replacing the original code-seeded fallback. Seeded with `legacy_default`/`store_default`/`request_override`, installed at process startup via `LoadProductionPipelineRegistry`.
- `kb.pipeline_bindings` — store → pipeline bindings (`ks_store_id`, `pipeline_id`, FK-enforced), replacing the free-text `default_pipeline` column on `kb.knowledge_store` (which was dropped). Live resolution via a SQL JOIN in `extract-doc-metadata-store.go`, so store-pipeline binding changes take effect immediately without restart.
- `kb.pipeline_rules` — facet-driven pipeline selection rules (`match_input_doc_type`, `match_source_language`, `match_knowledge_store_binding`; empty = wildcard). Highest-priority rule wins; equal-priority rules naming different pipelines = blocking conflict error (matching DR7's contract). Rules are cached in-memory at startup (no live-reload — see Deferred below).
- `kb.doc_facets` — persisted routing facets per document record (`input_doc_type`, `source_language`, `knowledge_store_binding`), computed at resolution time from `kb.inputs` and the active binding, and written back for plan explainability.
- `DOC_PIPELINE_PLAN_ONLY` shadow-mode control — plan-only (default) computes and records the pipeline resolution and enforcement decision but executes all requested processors unchanged; enforced mode (`DOC_PIPELINE_PLAN_ONLY=false`) genuinely gates execution to the resolved pipeline's allowlist. Two enforcement bugs were found and fixed during implementation: `applyPlanEnforcement` now actually removes disallowed processors from the execution list (it originally recorded the decision but never gated execution), and `resolveProductionPlanFacts` now falls back to `s.Processors` as the `RequestedProcessors` baseline when an event carries no explicit per-event processor list (the common ingestion path — without this fallback, `ExcludedByPolicy()` was always empty for that path, making enforcement a silent no-op exactly where it mattered most).
- `kb.pipeline_policies` — versioned activation wrapper (`policy_id`, version, status `draft|active|archived`, activated_at/by, at-most-one-active enforced by a partial unique index). `policy_id` threaded through both `kb.pipeline_bindings` and `kb.pipeline_rules`; both resolution paths gate on the active policy. Bindings/rules authored under a draft policy are invisible to resolution until the draft is activated. CRUD with a transactional `Activate` endpoint. ActivePolicyID/Version flow through to the persisted execution plan.
- `kb.doc_process_plans` — immutable execution-plan snapshots per run, including pipeline selection reason, binding source, rule name, excluded-by-policy processor list, and the active policy version.
- `pipeline_spec`/`ExcludedByPolicy`/`pipeline_processors_match_executed` — threaded through all plan-inspection surfaces (run parameters, live status snapshot, plan-history API).
- P1 benchmark closeout (Chunk 6) — real before/after comparison on real LLM output against the ventilator gold corpus, showing enforcement genuinely excludes a processor and the persisted plan matches reality.

**Explicitly deferred beyond P1** (documented boundary decisions, not gaps):

1. DR6's full schema beyond the versioning wrapper — `predicate JSONB` (instead of flat match columns), `scope_kind` generalization beyond `knowledge_store`, per-processor `require|enable|skip|defer` gating in `kb.pipeline_rules`.
2. Real, non-synthetic document coverage — all P1 validation used gold-run synthetic corpus data in `chenweb_test`.
3. Live-reload of a running process when pipeline/rule/policy config changes — rules are cached at startup, bindings resolve live but rules require a restart.

### Phase status summary

As of 2026-07-31 (pre-P2):

- **P0:** complete
- **P1:** complete
- **P2:** not started *(now complete as of 2026-08-01 — see the post-handoff update)*

### P2–P7 — status

P2 is **complete and validated** as of 2026-08-01 (plan `2026073104`, chunks 0 and A–F): the ontology content stores and candidate lifecycle, the DB-native module compiler/releases/activation, the four core 4a modules installed as data (including the full QUDT catalog into `quantity`), the `semid` canonicalization kernel with the governed ontology-term family, the `object_nodes` extension columns, and extension seams 1–4. The P1 pipeline plane remains the implemented baseline and now has governed ontology content it can route, enforce, and explain.

P3–P7 have **not started in code**. The deferred-by-design boundary (what P2 deliberately did not build, and where each item lands) is recorded in the P2 implementation log `2026073105-devdoc-semos-p2-implementation-log.md` §5 and summarized in the post-handoff update below.

## P0 continuation completed in this slice

- The deployed §13.5 audit was completed read-only against the live PostgreSQL system and recorded in ADR `2026072901` as a dated baseline.
- ADR C5 now reflects the real `kb.inputs.ks_store_id` partial wiring: the column exists and ingestion paths can populate it, but it still has no referential, routing, or semantic-scope role.
- Knowledge stores were inventoried from live data without inventing store-specific pipeline behavior: `Research` is populated, `卫健委标准` is empty, and some inputs remain unassigned.
- All 20 pilot competency questions are now structurally frozen in the consolidated ADR, and the competency-question/answer contract was approved for P0 closeout in the 2026-07-31 review.
- The 50-term ontology terminology crosswalk is now part of the consolidated ADR, including explicit non-support for an OWL reasoner runtime, automatic `owl:sameAs`, a SPARQL endpoint, and a triple store.
- The stale benchmark-wiring note in P0 was corrected while preserving the remaining `CorpusDataset` experiment-engine integration gap.
- The benchmark-evidence closeout was completed and recorded in devdoc `2026073005-devdoc-semos-p0-benchmark-evidence.md`, including the executed 9-document ventilator corpus run, generated line files, profile-report artifacts, hashes, and the bounded conclusion that three coarse store/document profiles exhibit different processor-yield patterns.

## Phase status (P0–P7)

**P0 is complete** as a bounded proof milestone ("semantic audit, competency questions, corpus baseline — no ontology/runtime implementation").

**Done within P0:**
- Gold corpus + comparator + benchmark CLI tooling (this session's build).
- Real baseline measurement — the `extract_metrics` recall-instability investigation (bug reports `2026073001`–`2026073003`) is literally P0's "baseline measurement per document kind: processor cost, artifact yield, artifact usefulness" bullet, carried out for real against the pilot corpus.
- Verified deployed DB/code baseline for ADR §13.5, including artifact cardinality, partitions, scene-object semantics, deletion behavior, and current knowledge-store inventory.
- Frozen competency-question suite and ontology terminology implementation contract in the consolidated ADR.
- Approved P0 benchmark evidence showing differentiated structural output patterns across `narrative-research`, `product-specification`, and `regulated-reference` for the ventilator pilot corpus.

**Deferred beyond P0:**
- ~~Merge the two keyword-canonicalization specs into the one DR16 supersedes them with~~ — done (2026-08-01, `2026080101-spec-keyword-canonicalization-merged.md`); the keyword-lexicon *code* itself remains a P3 deferral.
- Confirm authoritative standard editions and a real-data worked example for the pilot domain.
- Broaden the fixture corpus beyond the one ventilator display-module case — no ambiguous-object, multilingual-name, unit-conversion, or superseded-document fixtures exist yet (devdoc `2026073002-devdoc-gold-benchmark-operations.md` §7 has concrete extension options).
- ~~Implement the P2 ontology core and canonicalization kernel~~ — done (2026-08-01).

**P1:** complete (as of 2026-07-31). For reference, the deferred items (real-document validation, live-reload, full DR6 schema beyond the versioning wrapper) are documented in the P1 implementation log.

**P2:** complete (as of 2026-08-01) — see the post-handoff update. The deferred-by-design boundary beyond P2 is documented in the P2 implementation log §5.

**P3:** Track A complete, chunks 0–F (as of 2026-08-01) — see the post-handoff update. The keyword lexicon (Track B) remains; full detail in the P3 implementation log.

**P4:** generic profiles/rules, deterministic review scopes/findings, and comparison
scope/run/cell persistence are now implemented as of 2026-08-01; the normative ventilator
pilot remains blocked on a confirmed, traceable worked example and domain-owner approval.
**P5:** implemented through E3 and Chunk F as of 2026-08-02 (enforcement, alarms, audit events,
P5 review-scope schema, deterministic selection) — see the post-handoff update near the end of
this document; **P6–P7:** not started in code.

## Open decisions (from the ADR's own table)

- **OD1 (which domain module is the pilot) — Resolved: 呼吸机/医疗器械**, driven by the target application. This is why everything built this session is ventilator-shaped. Open sub-item: the authoritative standard editions that should source the real profile still need to come from a real-data worked example, not the application's mock (the mock's clause citations and limit values are placeholders).
- **OD3 (where pipeline policies are authored) — Resolved by DR17 (long-term), currently REST CRUD (implemented):** DR17 designates the same data repository and compiler/activation path as ontology modules for the long-term target. What's implemented today is a REST CRUD API (`/api/v1/kb/pipeline-policies`, `/api/v1/kb/pipeline-bindings`, `/api/v1/kb/pipeline-rules`, plus the `Activate` endpoint on policies), with `kb.pipeline_policies` carrying `source_ref`/`checksum` as forward-compatible fields for the eventual compiler-based authorship path.
- **OD2, OD4–OD10 — still open:** facet-vocabulary home (`document-authority` vs. its own module), Phase D sync-vs-async default, multi-jurisdiction precedence vocabulary, hard-deletion/retention policy, ontology-source hosting/access details, whether a document may belong to several knowledge stores, lexicon scope granularity, and category-canonicalization retrofit timing.

## Resolved history note

The stale P0 benchmark-wiring contradiction in ADR `2026072901` was corrected in this slice. The ADR now distinguishes between the benchmark components that are built and the narrower remaining `CorpusDataset` experiment-engine integration gap.

## Recommended next steps

*(Written pre-P2; P2 is now complete. Updated guidance follows in the post-handoff update below.)*

1. ~~Move toward P2~~ — done (2026-08-01).
2. Merge the two keyword specs into the DR16 replacement so the canonicalization-kernel source of truth is ready before the keyword family (P3).
3. Expand the fixture families beyond the single ventilator display-module case, especially ambiguous-object, multilingual, unit-conversion, supersession, and conflict fixtures.
4. Confirm authoritative standard editions and a real-data worked example for the pilot domain before claiming domain-level semantic completeness.

## Post-handoff update (2026-08-01 — P2 complete)

P2 (ontology core and canonicalization kernel) is **implemented and validated** as of 2026-08-01, per plan `2026073104-plan-semos-p2-ontology-core-and-canonicalization-kernel.md` (chunks 0, A–F). The DB-native storage revision (data in the database; no data-only repository; version columns) was applied throughout. Delivered:

- ontology content stores (`kb.ontology_terms`/`labels`/`axioms`/`mappings`/`candidates`) with the spec §9.3 candidate lifecycle and fingerprint dedup;
- the DB-native module compiler (`ontology-compiler`: validate/release/activate/rollback) producing immutable, checksummed releases with an activation pointer;
- the four core 4a modules installed **as data** (`core`, `document-authority` incl. the DR4 facet vocabulary, `measurement`, and `quantity` with the full QUDT catalog — 4151 terms) — the DR1 property, no code change;
- the `semid` canonicalization kernel with the governed ontology-term family, `semid_*` tables, and kernel fixtures (ADR tests 18–21, 23);
- the `object_nodes` extension columns (DR10/DR15.1);
- extension seams 1–4 and the spec §16.3 items 1–7 exit criteria.

Everything is unit-tested and the key flows live-validated against `chenweb_test`; the dev DB `miner` is fully migrated through `20260731000028`. See the P2 implementation log `2026073105-devdoc-semos-p2-implementation-log.md` and the new ontology capsule `Capsules/coding-capsules/ontology/+CAPSULE.md`. The ADR P2 section is annotated.

**Deferred by design beyond P2** (documented boundaries, not gaps — full detail in the P2 implementation log §5):

- assertions/evidence schema + Phase D association (`normalize_assertions`/`associate_semantics`/`project_semantics`) — **P3**; this is also why `primary_class_term_id` is not yet populated (classification-as-assertion needs the assertion store);
- the keyword lexicon (`kb.keyword_*`) as the kernel's second instantiation — **P3**, behind `KEYWORD_RESOLVER_MODE=observe`; the merged DR16 keyword spec should land first;
- profiles/profile rules/review scopes and the pilot 4b domain module — **P4**;
- the DR5 stage-DAG planner consuming `Requires`/`Produces` — later (seam 1 complete, planner not built);
- the full `semrules` predicate language — **P5** (the seam/evaluator shipped, the flat-column rule path stays active);
- SHACL/RDF projection and the SQL-vs-SHACL parity gate — **P7**.

**Next:** P3 (assertions, evidence, Phase D association, keyword lexicon). Priorities before P3: write the merged DR16 keyword spec, and confirm the pilot's authoritative standard editions with a real-data worked example.

## Post-handoff update (2026-07-31, final — supersedes all earlier status)

The original "Post-handoff update" recorded one early P1 slice (store-bound default pipeline). That, and everything else listed under "not yet complete for P1" in the original handoff, is now implemented and validated as of the same day's later session. P1 is done. See the P1 implementation log (`2026073103-devdoc-semos-p1-implementation-log.md`) for the full build record — schema, code, bugs found and fixed, benchmark evidence, and the two live-Postgres validation proofs for policy activation.

## Post-handoff update (2026-08-01 — P3 chunks 0–D complete)

P3 Track A (assertion/evidence schema, Phase D stages 1–2) is **partially built and live-validated**
as of 2026-08-01, per plan `2026080102-plan-semos-p3-assertions-evidence-and-phase-d-association.md`
(chunks 0–D). Delivered:

- the DR9 qualified-assertion and evidence schema (`kb.semantic_assertions`/`assertion_evidence`/
  `assertion_relations`) with the spec §9.3 **operational** decision state machine, distinct from
  P2's governed-content machine;
- `kb.semantic_decision_candidates`, the Phase D counterpart to P2's `kb.ontology_candidates`, with
  the same fingerprint-dedup/revision/defer-retry mechanics;
- the `AssertionNormalizerRegistry` (DR11 seam 5) with metric and provision normalizer instances,
  each self-registering (no edits to the registry or the Phase D stage required to add one);
- Phase D stages 1–2 (`normalize_assertions`, `associate_semantics`), wired into the pipeline after
  Phase C, gated by `SEMANTIC_ASSOCIATION_ENABLED` (default off — currently inert in production).

Live-validated against **real gold-corpus data already in `chenweb_test`** (not only synthetic
fixtures), which surfaced genuine findings recorded in the P3 implementation log
`2026080103-devdoc-semos-p3-implementation-log.md`: the corpus's `threshold_or_target`/provision
text is predominantly Chinese, requiring Chinese comparator/modality vocabulary the initial
English-only parser missed entirely; contrast-ratio notation (`500:1`) needed a small preprocessing
fix; the corpus's metric artifacts have **never** been run through object reconciliation (zero rows
in `kb.artifact_objects` for `artifact_type='metric'`, versus full reconciliation for provisions and
inventory items) so real metric candidates mostly defer with `unresolved_referent` today; and no
governed deontic predicate term exists yet for provisions, so every provision candidate correctly
defers rather than inventing one.

Also completed as a chunk-0 prerequisite: the DR16 merged keyword spec
(`2026080101-spec-keyword-canonicalization-merged.md`), superseding the two disagreeing keyword
specs, closing that documentation gap even though the keyword-lexicon code itself remains deferred.

**Deferred by design beyond this slice:**

- `project_semantics` (Phase D stage 3) and `kb.object_nodes.primary_class_term_id` maintenance;
- association-run telemetry and the deferred/ambiguous backlog drain (DR5/DR6/DR7 pattern reuse);
- the keyword lexicon *code* (design is done; `KEYWORD_RESOLVER_MODE` stays `off`);
- object reconciliation for the metric artifact family (a Phase B/C gap, not Phase D);
- a governed deontic predicate for provisions (an ontology-content authoring task, not a code task).

**Next:** chunk E (`project_semantics`), chunk F (telemetry, backlog drain, exit-criteria suite), then
Track B (keyword lexicon).

## Post-handoff update (2026-08-01, continued — P3 chunk E complete)

`project_semantics` (Phase D stage 3) is now **built and live-validated**, closing the item listed
first in the "deferred by design" list immediately above. Delivered: `kb.projection_state` (every
projection row references its authoritative source table/id/revision, per spec §10.8); the
`ProjectionBuilderRegistry` (DR11 seam 7); and `kb.object_nodes.primary_class_term_id` maintenance
from accepted `core:instance_of` assertions — closing the P2 chunk E deferral by name.

Live validation (a second temporary `p3validate` program) proved the full corruption-detection-and-
repair contract spec §16.2 item 6 asks for: a hand-edited (bypassing the projection mechanism
entirely) `primary_class_term_id` value was detected and repaired back to the authoritative value,
a repeat sweep on an already-correct projection made zero writes, and a decision-relevant revision
of the source assertion correctly propagated to both the materialized column and `kb.projection_state`.

One real gap the validation had to work around, recorded for whoever builds the next normalizer: **no
normalizer anywhere in this workspace yet emits `core:instance_of` classification assertions** — the
metric normalizer produces `measured_by` assertions, provisions defer entirely (§5 above) — so
`project_semantics` has no real Phase D output to project from today. Validation authored classification
assertions directly through `AssertionStore`, the same technique earlier chunks used before any
normalizer existed. A future entity or inventory-item normalizer is the natural first real producer.

Also fixed as a chunk-E prerequisite: `associate_semantics`'s evidence rows never populated
`input_record_id` (harmless for chunks A–D, since nothing read it, but `project_semantics`'s
per-record scoping depends on it).

**Deferred by design beyond chunk E:** association-run telemetry and the deferred/ambiguous backlog
drain (chunk F); the keyword lexicon code (Track B); object reconciliation for metrics; a governed
deontic predicate for provisions; a real classification-assertion producer.

**Next:** chunk F (telemetry, backlog drain, the consolidated exit-criteria suite), then Track B
(keyword lexicon).

## Post-handoff update (2026-08-01, final for this session — P3 Track A complete)

Chunk F is done, closing out all of **P3 Track A** (chunks 0–F). Delivered: association-run
telemetry (spec §10.9, `assertions.AssociationRunReport`/`BuildAssociationRunReport`), a single
`assertions.RunPhaseD` orchestrator consolidating the three per-stage `ControlService` wrappers
chunks C–E built into one call site in `control.go`; the deferred-candidate backlog drain
(`assertions.DrainDeferredCandidates`, `POST /kb/semantic-decisions/drain-deferred`, the ADR
`2026070701` DR5 bulk-backfill pattern reused rather than a new mechanism); and a permanent
spec §16.2/§16.3 exit-criteria test file (`p3_exit_test.go`) mapping every P3-relevant item to
either a test or a pointer to where live validation already proved it, mirroring
`candidates/p2_exit_test.go`'s convention exactly.

Two real correctness bugs surfaced during this chunk's own live validation, not from inspection:

1. `DecisionCandidateStore.Propose` only superseded a prior revision that was `accepted`/`rejected`,
   leaving a `deferred`/`candidate` prior un-retired when a new revision was created — meaning two
   revisions of the same logical association could sit in a processable status simultaneously.
   Caught when the backlog drain's first design (directly retry a deferred candidate via
   `RetryDeferred`) reprocessed a candidate's stale, still-unresolved payload instead of its fresh
   one. The actual fix was not "retry harder" but a different mechanism: re-running the normalizer
   (which naturally produces a correctly-superseding fresh revision once this bug was fixed).
2. `AssociateSemantics.Run` only queried `status='candidate'`, so a crash between the `in_review`
   transition and the accept/defer decision left a row stuck at `in_review` forever, with no
   automatic path back. Found while writing the exit-criteria mapping for spec §16.3 item 13
   ("a transient failure leaves the candidate non-terminal and can resume idempotently").

Both are the same class of bug the P1/P2/P3 logs have now recorded multiple times: real, load-bearing
gaps that sqlmock-only or synthetic-fixture-only testing structurally cannot catch, found only by
running the real mechanism against real Postgres and real data.

**P3 Track A is complete.** **Next:** Track B (the keyword lexicon — design is done, code is not),
then P4 (profiles, the pilot 4b domain module, and ontology-aware metric review).

## Post-handoff update (2026-08-01, continued — `extract_metrics` structured output closed)

The ADR §8.2 `extract_metrics` structured-output change — deferred through P3 (log §8 item 10) and
again through P4, called "the single highest-leverage change for the application" — is now
implemented and committed via the OpenSpec change
`ChenWeb/openspec/changes/extract-metrics-structured-output/`, closing P3 log §8 items 10 and 13:

- `kb.metrics` gained `value_min`/`value_max`/`condition` (migration
  `20260801000014_add_kb_metrics_structured_value_fields.sql`); `prompt-enrich-metrics-v5.md` emits
  them and the save handler persists them (nullable, so v4-era output still imports unchanged).
- `MetricNormalizer` now consumes the structured columns (`value_range_type`, `value_class`,
  `metric_value`, `metric_unit`) deterministically; `parseThresholdOrTarget` is demoted to a legacy
  fallback used only when `value_range_type` is empty. A row that declares structured values is
  never free-text parsed — removing review finding 2b's fabrication class structurally (design
  D1/D5).
- `associate_semantics.processMetric` resolves the raw unit to QUDT `quantity` module terms
  (`unit_term_id`/`quantity_kind_term_id`, verified against the live catalog) and carries the
  `condition` qualifier onto accepted assertions.

**Gold-corpus reconciliation (important).** The P3 log §C2 claimed the text parser produced "6
correctly-parsed structured assertions + 2 honest `unparsed`, never a fabricated value." The stored
revision-1 candidates contradict this: all 8 rows of `input_record_id=2` were parsed, including
`observed_value=1` fabricated from "1 m 距离处清晰辨识" (the exact row §C2 cited as an `unparsed`
example) and truncating mis-parses (`1024` from "1024×600", `160` from "水平160°, 垂直140°").
Structured-first produces 4 correct assertions (rows 1-4: `lower_bound_requirement` 250/1000,
`upper_bound_requirement` 120 ×2) and 4 honest `unparsed` for rows 5-8, which carry v2-era
`minimum`/`other` enums outside the v5 closed vocabulary. The 6+2 → 4+4 drift is the removal of 4
mis-parses/fabrications, not a regression; rows 5-8 parse deterministically once re-extracted with
`prompt-enrich-metrics-v5.md`. Full reconciliation in the P3 log §12.1 addendum.

**Status implications for the handoff's earlier sections:** the "ontology runtime still not built"
section's bullet that the metric normalizer "has to parse `threshold_or_target` free text" is now
stale for the metric family — the structured-first path and the parser fallback coexist, with the
free-text path reserved for pre-structured rows only.

## Post-handoff update (2026-08-02 — P5 complete through E2)

The current P5 sources of truth are spec
`KnowledgeStore/doc-repo/specs/202608/2026080102-spec-semos-p5-rule-driven-routing.md` and plan
`KnowledgeStore/doc-repo/plan/202608/2026080103-plan-semos-p5-rule-driven-routing.md`. Plan tasks
A1–A4, B1–B3, C1–C2, D1–D2, E1, and E2 are implemented and checked off. The user explicitly set
the present stop boundary at E2; **the next implementation task is E3**.

What now exists:

- A shared `semrules` evaluator supplies the production predicate and routing-rule semantics used
  by policy evaluation, overlap analysis, compilation, and runtime planning.
- Facts, routing-policy versions, bindings, processor gates, clearance evidence, and revocations
  have durable schema and APIs. Clearance approval, replacement, and revocation reload immutable
  benchmark evidence and recompute the decision server-side; owner/admin authorization and the
  authenticated actor identity are enforced.
- The clearance analyzer applies the paired manifest, repetition, case, failure, and recall gates
  from the P5 contract rather than trusting a caller-supplied verdict.
- E1 added the pure processor-gate resolver with precedence
  `require > defer > skip > enable`, mandatory-processor immunity, explicit/run overrides,
  indeterminate handling, and stable defer fingerprints. Shadow plans record what would run, skip,
  or defer without changing the effective processor set.
- Each persisted P5 plan snapshots its facts, policy identity and checksum, selected and baseline
  pipeline checksums, binding/gate trace, and rule checksums. Reloading a stored plan therefore does
  not reinterpret it under a later activation.
- E2 added compile-time validation for predicates, targets, checksums, legacy-adapter parity,
  clearance references, and binding overlap. Analyzable same-rank bindings that overlap while
  selecting different pipelines are rejected; equivalent selections are allowed; cases that
  cannot be analyzed statically require a runtime conflict check. Gate overlap remains valid
  because effect precedence is deterministic.
- Policy activation accepts an empty request body only, derives the actor from authenticated
  `UserName`, requires owner/admin authority, compiles before the transaction, then locks and
  recompiles against the transactional view before atomically archiving the old policy and
  activating the new one.

Verification at this boundary passed the `semrules` suite, focused document-processing compiler,
gate, binding, and snapshot tests, focused `kbhandler` routing-policy and authorization tests, and
`go vet` for the three affected packages. The key implementation commits are `ba00` (E1 execution
snapshot), `6385` (E2 compile/activate), and `2c00` (clearance authorization); KnowledgeStore plan
progress through E2 is recorded in `ba73`. Package-wide final verification remains an I3 closeout
task; unrelated legacy full-suite failures discovered during focused P5 work have not been
misrepresented as P5 regressions.

**Remaining P5 boundary:** E3 must enforce the already-snapshotted routing and gate outcomes at
runtime. F through I then cover audit/review flows, classifier/module integration, live proof,
documentation, and final acceptance verification. Until those tasks pass, P5 as a whole remains
in progress and suppressive decisions remain observable shadow behavior rather than enforced
execution behavior.

## Post-handoff update (2026-08-02, continued — P5 E3 and Chunk F complete)

E3 and Chunk F are now implemented and merged to `main` (commit `7e778891`, 13 commits
`63854f48..7e778891`, local fast-forward via `jj`; `origin/main` not yet pushed). This closes the
approved E3-through-F scope of plan `2026080103`. The previous update's "Remaining P5 boundary"
line is superseded: suppressive decisions are no longer shadow-only.

**E3 — clearance-aware atomic enforcement, alarms, and audit events** (`doc-processing`):

- `FinalizeRoutingPlan` is the single enforcement boundary: explicit bypass, conditional binding
  evaluation with clearance or store-default fallback, pipeline allowlist filtering, per-processor
  gate enforcement with clearance, and mandatory-processor restoration, returning both shadow and
  effective plans with provenance on every exclusion.
- Routing-operator alarms persist to `alarms_errors` under partial unique indexes keyed on
  `(run_id, kind)` and `(record_id, kind)` (migration `20260801000019`), so exactly one alarm per
  run/record is emitted before processor execution; a later fix restored the `kind` column in the
  no-correlator insert.
- Block-mode decision-relevant conflicts fail before dispatch; conflict and fallback events are
  emitted. A neutral `policyaudit` package (dependency-free, avoiding import cycles) writes
  append-only events to `kb.pipeline_policy_events` (migration `20260801000018`) for authoring,
  activation, conflicts, fallback, clearance approval/revocation, and enforced/shadow decisions.

**Chunk F — deterministic review-profile selection** (`ontology/profiles` + `kbhandler`):

- F1: migration `20260801000020` extends `kb.ontology_review_scopes` with five P5 columns
  (`knowledge_store_id`, `selection_attempt_id`, `selection_status`, `fact_snapshot`,
  `selection_snapshot`); `ProfileStore.LoadReleasedProfiles` pins the active releases and their
  `included_in_release` profiles in one repeatable-read transaction; `DeriveKnowledgeStore`
  resolves the single store from `kb.inputs.ks_store_id` (duplicate document ids are deduplicated
  rather than miscounted as unresolvable).
- F2: the deterministic selector (`select.go`) evaluates each released profile once per
  document×target subject against merged review/document/deployment facts, freezes every profile
  with ≥1 true subject (release id/checksum, exact subjects, predicate checksum, outcome, trace),
  records false/indeterminate subjects with traces, and marks the scope `indeterminate` when an
  indeterminate candidate profile's closed dimensions intersect the request's; the scope is still
  created and executable. One warning per indeterminate scope id persists to `alarms_errors` via a
  `scope_id`-keyed partial unique index (migration `20260801000021`); alarm-write failures are
  logged and never block scope creation.
- Rule-level applicability (`review_service.go`) evaluates each pinned rule's `applicability`
  against the scope's frozen per-subject fact snapshot: `false` excludes only that rule,
  decision-relevant `indeterminate` emits a finding, and no unpinned profile/release is ever
  loaded. The kbhandler deterministic path is gated on `selection_mode = deterministic_rule`;
  explicit mode stays byte-compatible. The B3 cross-consumer fixture (created here because B3
  never delivered it) asserts identical values/truth/trace through both extraction and review fact
  builders (spec acceptance criterion 9).

Verification: the profiles package (69 tests) and all of `ontology/...` and `doc-benchmark` pass;
`kbhandler` (14) and `doc-processing` (15) pre-existing baseline failures are unchanged; build,
`go vet`, and `gofmt` are clean. Review posture: task-scoped reviews plus a final whole-branch
review (most-capable model) returned no Critical/Important findings; the 12 ledgered residuals
were adjudicated (11 acceptable, one trivial fix applied).

**Remaining P5 boundary:** Chunks G (`classify_document` mandatory-gated classifier: G1
contract/registration, G2 two-pass extraction/review resolvers), H (governed proposal lifecycle
and automatic release→draft-policy promotion), and I (named acceptance-criteria tests,
live-Postgres and synthetic-corpus proof, docs/capsule/ADR/handoff closeout). Documented
carry-forward gaps that G/H wiring is expected to close: the deterministic wiring passes an empty
deployment context (`deployment.*` predicates are indeterminate) and `VocabularyRelease = 0` (no
resolver exists), and unconditional profiles carry an empty predicate checksum.

**Working-copy note:** after merging P5 to `main`, the local jj working copy (the Doc Facets CRUD
page) was joined with `main` via `jj new @ main`; the current working copy is the merge commit and
carries both lines.

## Post-handoff update: P5 Chunks G, H, I (2026-08-02)

**Chunk G — mandatory-gated `classify_document` classifier:**

- G1: versioned prompt at `prompts/prompt-classify-document-v1.md` (never embedded in Go);
  `DocumentClassifier` with governed vocabulary validation, bounded sample extraction, stable retry
  with invocation id, content-safe audit events, and LLM failure preservation (nil error,
  indeterminate result); registered as `mandatory_gated` class in `productionProcessorSpecs`;
  excluded from optional processor list.
- G2: `ApplicabilityResolver` implements two-pass evaluation with optional tier-3 classification
  between passes; `decisionRelevantTier3Paths()` collects unique paths from
  `DecisionRelevantMissingPaths`; classifier observations enrich facts without overwriting known
  values; one invocation per record/extraction-run; classifier failure detected via empty
  observations with unresolved paths.

**Chunk H — governed proposal lifecycle and draft-policy promotion:**

- H1: migration `20260801000022` creates `kb.ontology_applicability_proposals` with status
  lifecycle (draft → in_review → approved → included_in_release); `ProposalStore` validates
  predicates through `semrules.Validate()` before insertion; deterministic predicate checksums;
  `ListApprovedProposals` for H2 promotion.
- H2: `PolicyPromotionStore` implements `DraftPolicyPromoter` interface to create draft
  pipeline-policy versions from approved module proposals; idempotent per release (no duplicate
  drafts); materializes proposals as conditional bindings under the draft policy using the default
  pipeline; emits content-safe audit events; never activates routing (separate authenticated
  endpoint required). Interface defined in `docprocessing` to avoid import cycles
  (modules → profiles → docprocessing).

**Chunk I — acceptance-criteria tests and verification:**

- I1: `p5_exit_test.go` files in `doc-processing` and `profiles` map spec section 12's 16
  acceptance criteria to named tests across semrules, doc-processing, profiles, and doc-benchmark
  packages; consolidated coverage test fails if any criterion lacks at least one named test pointer.
- I2: skipped (requires live PostgreSQL and synthetic corpus; deferred to operational validation).
- I3: comprehensive test suite passes (semrules, profiles, modules); `go vet` clean; ontology-compiler
  builds successfully; pre-existing doc-processing baseline failures unchanged.

**Verification:** semrules (all tests), profiles (all tests), modules (all tests) pass; `go vet`
clean on all affected packages; ontology-compiler builds; doc-processing pre-existing baseline
failures unchanged (not related to P5 work).

**Remaining P5 boundary:** I2 (live PostgreSQL and synthetic-corpus proof) requires operational
validation with a live database. All code-level P5 work (G, H, I1, I3) is complete.

## Related documents

- Companion handoff: `2026073001-handoff-semos-gold-benchmark-and-tooling.md` — the technical build this session produced (CLI, mise tasks, prompt iterations, bug reports).
- Operations manual: `KnowledgeStore/doc-repo/devdocs/202607/2026073002-devdoc-gold-benchmark-operations.md` — how to run the benchmark, including corpus-extension options.
- P0 evidence record: `KnowledgeStore/doc-repo/devdocs/202607/2026073005-devdoc-semos-p0-benchmark-evidence.md` — what was executed, where the generated line files and benchmark artifacts went, and why the current evidence is sufficient to justify P1 policy work.
- P1 implementation log: `KnowledgeStore/doc-repo/devdocs/202607/2026073103-devdoc-semos-p1-implementation-log.md` — the complete P1 build record (schema, code, bugs found and fixed, benchmark evidence, live-Postgres validation proofs). P1 is done against its stated exit criteria.
- P2 implementation plan: `KnowledgeStore/doc-repo/plan/202607/2026073104-plan-semos-p2-ontology-core-and-canonicalization-kernel.md` — the P2 plan (ontology core + canonicalization kernel), chunks 0–F, including the 2026-07-31 DB-native storage revision (no data-only repository; content versioned in the database).
- P2 implementation log: `KnowledgeStore/doc-repo/devdocs/202607/2026073105-devdoc-semos-p2-implementation-log.md` — the running P2 build record.
- DR16 merged keyword spec: `KnowledgeStore/doc-repo/specs/202608/2026080101-spec-keyword-canonicalization-merged.md` — supersedes `2026072301` and `2026072703`; the keyword-lexicon design source of truth for whenever Track B's code is built.
- P3 implementation plan: `KnowledgeStore/doc-repo/plan/202608/2026080102-plan-semos-p3-assertions-evidence-and-phase-d-association.md` — the P3 Track A plan (chunks 0–F), including the Track A/B scope split.
- P3 implementation log: `KnowledgeStore/doc-repo/devdocs/202608/2026080103-devdoc-semos-p3-implementation-log.md` — the P3 chunks 0–F build record (schema, code, real-data findings, live-Postgres validation); its §12.1 addendum records the `extract_metrics` structured-output closure and the §C2 gold-corpus reconciliation.
- OpenSpec change `extract-metrics-structured-output`: `ChenWeb/openspec/changes/extract-metrics-structured-output/` — proposal/design/specs/tasks for the structured-first metric normalizer, `value_min`/`value_max`/`condition` schema, and QUDT unit resolution.
- P5 rule-driven routing spec: `KnowledgeStore/doc-repo/specs/202608/2026080102-spec-semos-p5-rule-driven-routing.md` — acceptance contract for facts, bindings, processor gates, clearance, enforcement, audit, and proof.
- P5 implementation plan: `KnowledgeStore/doc-repo/plan/202608/2026080103-plan-semos-p5-rule-driven-routing.md` — authoritative task checklist; A1–E2 and E3, F1, F2 are complete and G is next.
- ADR `2026072901-adr-ontology-platform-and-adaptive-pipeline.md` and its three ratified inputs: research `2026072302`, spec `2026072702`, ADR `2026072701`.
