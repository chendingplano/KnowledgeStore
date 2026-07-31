# SemOS Ontology Status — Session Handoff

Date: July 31, 2026

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

So the correct phase read is:

- **P0:** complete
- **P1:** complete
- **P2:** not started

### P2–P7 — not started

The ontology core and canonicalization kernel (P2) and everything downstream of it has not started in code.

The P1 pipeline plane (named pipelines, binding policy, processor rules, enforcement, execution plans, policy versioning) is now the implemented baseline — but the semantic processing layer (canonical identity, assertion normalization, Phase D association, the keyword lexicon) hasn't been built yet, and the pipeline's processor allowlists, rules, and policies currently have no ontology content to operate on beyond the existing `extract_metrics`/`extract_provisions` LLM processors.

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
- Merge the two keyword-canonicalization specs into the one DR16 supersedes them with.
- Confirm authoritative standard editions and a real-data worked example for the pilot domain.
- Broaden the fixture corpus beyond the one ventilator display-module case — no ambiguous-object, multilingual-name, unit-conversion, or superseded-document fixtures exist yet (devdoc `2026073002-devdoc-gold-benchmark-operations.md` §7 has concrete extension options).
- Implement the P2 ontology core and canonicalization kernel.

**P1:** complete (as of 2026-07-31). For reference, the deferred items (real-document validation, live-reload, full DR6 schema beyond the versioning wrapper) are documented in the P1 implementation log.

**P2–P7:** not started in code.

## Open decisions (from the ADR's own table)

- **OD1 (which domain module is the pilot) — Resolved: 呼吸机/医疗器械**, driven by the target application. This is why everything built this session is ventilator-shaped. Open sub-item: the authoritative standard editions that should source the real profile still need to come from a real-data worked example, not the application's mock (the mock's clause citations and limit values are placeholders).
- **OD3 (where pipeline policies are authored) — Resolved by DR17 (long-term), currently REST CRUD (implemented):** DR17 designates the same data repository and compiler/activation path as ontology modules for the long-term target. What's implemented today is a REST CRUD API (`/api/v1/kb/pipeline-policies`, `/api/v1/kb/pipeline-bindings`, `/api/v1/kb/pipeline-rules`, plus the `Activate` endpoint on policies), with `kb.pipeline_policies` carrying `source_ref`/`checksum` as forward-compatible fields for the eventual compiler-based authorship path.
- **OD2, OD4–OD10 — still open:** facet-vocabulary home (`document-authority` vs. its own module), Phase D sync-vs-async default, multi-jurisdiction precedence vocabulary, hard-deletion/retention policy, ontology-source hosting/access details, whether a document may belong to several knowledge stores, lexicon scope granularity, and category-canonicalization retrofit timing.

## Resolved history note

The stale P0 benchmark-wiring contradiction in ADR `2026072901` was corrected in this slice. The ADR now distinguishes between the benchmark components that are built and the narrower remaining `CorpusDataset` experiment-engine integration gap.

## Recommended next steps

1. Move toward P2 (ontology core and canonicalization kernel), now that the P1 pipeline plane is the implemented baseline. The pipeline machinery (named pipelines, bindings, rules, enforcement, policy versioning) is ready for ontology content; the task ahead is building the semantic layer (canonical identity, assertion normalization, Phase D association, the keyword lexicon) that the pipeline can route, enforce, and explain.
2. Merge the two keyword specs into the DR16 replacement so the canonicalization-kernel source of truth is ready before P2.
3. Expand the fixture families beyond the single ventilator display-module case, especially ambiguous-object, multilingual, unit-conversion, supersession, and conflict fixtures.
4. Confirm authoritative standard editions and a real-data worked example for the pilot domain before claiming domain-level semantic completeness.

## Post-handoff update (2026-07-31, final — supersedes all earlier status)

The original "Post-handoff update" recorded one early P1 slice (store-bound default pipeline). That, and everything else listed under "not yet complete for P1" in the original handoff, is now implemented and validated as of the same day's later session. P1 is done. See the P1 implementation log (`2026073103-devdoc-semos-p1-implementation-log.md`) for the full build record — schema, code, bugs found and fixed, benchmark evidence, and the two live-Postgres validation proofs for policy activation.

## Related documents

- Companion handoff: `2026073001-handoff-semos-gold-benchmark-and-tooling.md` — the technical build this session produced (CLI, mise tasks, prompt iterations, bug reports).
- Operations manual: `KnowledgeStore/doc-repo/devdocs/202607/2026073002-devdoc-gold-benchmark-operations.md` — how to run the benchmark, including corpus-extension options.
- P0 evidence record: `KnowledgeStore/doc-repo/devdocs/202607/2026073005-devdoc-semos-p0-benchmark-evidence.md` — what was executed, where the generated line files and benchmark artifacts went, and why the current evidence is sufficient to justify P1 policy work.
- P1 implementation log: `KnowledgeStore/doc-repo/devdocs/202607/2026073103-devdoc-semos-p1-implementation-log.md` — the complete P1 build record (schema, code, bugs found and fixed, benchmark evidence, live-Postgres validation proofs). P1 is done against its stated exit criteria.
- P2 implementation plan: `KnowledgeStore/doc-repo/plan/202607/2026073104-plan-semos-p2-ontology-core-and-canonicalization-kernel.md` — the P2 plan (ontology core + canonicalization kernel), chunks 0–F, including the 2026-07-31 DB-native storage revision (no data-only repository; content versioned in the database).
- P2 implementation log: `KnowledgeStore/doc-repo/devdocs/202607/2026073105-devdoc-semos-p2-implementation-log.md` — the running P2 build record.
- ADR `2026072901-adr-ontology-platform-and-adaptive-pipeline.md` and its three ratified inputs: research `2026072302`, spec `2026072702`, ADR `2026072701`.
