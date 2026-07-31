# SemOS Ontology Status — Session Handoff

Date: July 31, 2026

## Scope

This session started as ontology-consolidation work (research `2026072302`, spec `2026072702`, ADR `2026072701`) and drifted into building and validating a benchmark harness against the pilot domain those documents chose. This handoff exists specifically to capture **where the ontology design actually stands** — as opposed to what tooling got built — so a future session (or the user) can resume from an accurate baseline instead of assuming more of the ontology itself was implemented than actually was.

For the technical build this session produced (the `gold-run`/`analyze` CLI, mise tasks, prompt iterations, bug reports), see the companion handoff `2026073001-handoff-semos-gold-benchmark-and-tooling.md` — that document covers the *how*; this one covers the *what's actually designed vs. built*.

Work resumed on 2026-07-30 with explicit approval to complete P0 before starting P1/P2, and the P0 benchmark-evidence closeout was completed on 2026-07-31.

## Document lineage (read in this order if picking this up cold)

1. Research `2026072302-rsch-object-centric-ontology.md` (2026-07-23) — established the vocabulary and layered target. **Status: Research / architecture recommendation.**
2. Spec `2026072702-spec-ontology-canonical-artifacts.md` (2026-07-27) — turned the research into contracts (ownership, lifecycles, state machines). **Status: Proposal.**
3. ADR `2026072701-adr-ontology-identity-and-assertions.md` (2026-07-27) — ratified the spec's decisions. **Status: Accepted — design only, not yet implemented** (stated explicitly in its own header).
4. ADR `2026072901-adr-ontology-platform-and-adaptive-pipeline.md` (2026-07-29, revised twice since) — consolidates all three of the above plus the doc-processor capsule into one buildable architecture with an executable phased plan (DR0–DR24, P0–P7). **Status: Proposed (draft for review).** This is the current source of truth — treat documents 1–3 above as historical inputs already folded in, not independently authoritative anymore.

## Current status: P0 proof complete; P1 started; ontology runtime still not built

Searching the entire consolidated ADR for its own `**Built:**` implementation-status annotations turns up exactly three, all under DR21/DR22:

- `ChenWeb/server/api/ontology/comparison` (`Compare`, `EvaluateFamily`) — the DR21 requirement-strictness comparator, a pure function over normalized constraints.
- `ChenWeb/server/api/doc-benchmark/verdict_score.go` — `ScoreVerdictMatrix`, the DR22 outcome scorer.
- `ChenWeb/server/api/doc-benchmark/corpus_dataset.go` — the corpus-level dataset/case loader.

Alongside these (built this session, not separately annotated in the ADR yet): the `gold.toml` synthetic fixture itself, its CDM document generator (`generate.go`), `resolve.go`/`coverage.go`, the `gold-run`/`analyze` CLI tooling, and the offline store-profile reporting workflow used for P0 closeout (full detail in the companion handoff and the P0 evidence devdoc).

All of this maps directly onto P0's stated primary deliverable: *"Build the synthetic gold corpus and extend the existing benchmark... rather than waiting for a real-data example."* As of 2026-07-31, that validation slice is no longer just partially built; it has execution evidence and a written closeout record. It is still the **validation harness**, not the ontology architecture itself.

Everything that would actually make this "an ontology" — as opposed to a comparator test rig for one metric-extraction pipeline — remains pure design, with zero code and zero ontology-runtime migrations:

- The 7-layer architecture itself (evidence/artifacts → canonical identity → ontology terms → domain modules → qualified assertions → profiles → review).
- The canonicalization kernel / `semid` (DR15).
- The separate ontology-as-code source tree described in DR17 — not yet implemented, and per current workspace policy its documentation belongs in `KnowledgeStore` while code lands in `shared` or `ChenWeb` rather than a new ad hoc repo.
- Two-tier pipeline routing: named pipelines, binding policies, blocking-by-default conflict resolution (DR6/DR7).
- Domain modules — not just the pilot 呼吸机 module, but even the shared 4a core modules (`core`, `quantity`, `document-authority`, `measurement`).
- Qualified assertions and the evidence schema (DR9).
- the ontology core and canonicalization kernel (P2).

That said, this handoff needs one important correction relative to the earlier P0-only status:

- **P1 has now started in code** in `ChenWeb`.
- **P2 has not started in code.**

As of Friday, July 31, 2026, the implemented P1 subset includes:

- `ProcessorSpec` / processor-plan declarations for the current 13-processor production roster;
- deterministic plan facts and derived routing facets from live `kb.inputs` state;
- code-seeded named-pipeline selection seams and precedence helpers;
- persisted execution-plan snapshots in `kb.doc_process_plans`;
- API inspection surfaces for latest-plan and paged plan history;
- ingestion and rerun persistence of `kb.inputs.requested_pipeline`.

What is **not** yet complete for P1:

- `kb.doc_facets`;
- authored pipeline/binding/rule tables (`kb.pipelines`, `kb.pipeline_policies`, `kb.pipeline_bindings`, `kb.pipeline_rules`, `kb.knowledge_store_bindings`);
- store-default binding from live knowledge-store data;
- conflict detection / blocking behavior at the ADR contract level;
- explicit shadow mode (`DOC_PIPELINE_PLAN_ONLY`);
- benchmark closeout for the full P1 policy-plane milestone.

So the correct phase read is:

- **P0:** complete
- **P1:** started, partially implemented, not finished
- **P2:** not started

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
- Finish the P1 pipeline plane (declarations, facets, rules, named pipelines, bindings, plan persistence, shadow mode).
- Implement the P2 ontology core and canonicalization kernel.

**P1:** started in code but not complete; the immediate next step is to finish P1.

**P2–P7:** not started in code.

## Open decisions (from the ADR's own table)

- **OD1 (which domain module is the pilot) — Resolved: 呼吸机/医疗器械**, driven by the target application. This is why everything built this session is ventilator-shaped. Open sub-item: the authoritative standard editions that should source the real profile still need to come from a real-data worked example, not the application's mock (the mock's clause citations and limit values are placeholders).
- **OD3 (where pipeline policies are authored) — Resolved by DR17:** the same data repository and compiler/activation path as ontology modules.
- **OD2, OD4–OD10 — still open:** facet-vocabulary home (`document-authority` vs. its own module), Phase D sync-vs-async default, multi-jurisdiction precedence vocabulary, hard-deletion/retention policy, ontology-source hosting/access details, whether a document may belong to several knowledge stores, lexicon scope granularity, and category-canonicalization retrofit timing.

## Resolved history note

The stale P0 benchmark-wiring contradiction in ADR `2026072901` was corrected in this slice. The ADR now distinguishes between the benchmark components that are built and the narrower remaining `CorpusDataset` experiment-engine integration gap.

## Recommended next steps

1. Continue and finish P1, starting from the already-implemented store-aware policy-selection slice: `ProcessorSpec` declarations, document facts/facets, requested-pipeline persistence, named-pipeline selection, persisted execution plans, and plan-inspection APIs — then complete the remaining P1 items (authored bindings/rules, `kb.doc_facets` if retained, shadow mode, conflict handling, and benchmark closeout).
2. Merge the two keyword specs into the DR16 replacement so the canonicalization-kernel source of truth is ready before P2.
3. Expand the fixture families beyond the single ventilator display-module case, especially ambiguous-object, multilingual, unit-conversion, supersession, and conflict fixtures.
4. Confirm authoritative standard editions and a real-data worked example for the pilot domain before claiming domain-level semantic completeness.

## Post-handoff update (2026-07-31, later session)

One item from "What is **not** yet complete for P1" above has since closed: **store-default binding from live knowledge-store data** is now real. `kb.knowledge_store` gained a `default_pipeline` column, and `DocMetadataSQLStore.GetInputRecord` now joins it in, so `StoreBoundPipeline` is no longer always empty. A document in a knowledge store with `default_pipeline` set now resolves to that pipeline via the existing `knowledge_store_binding` precedence rule instead of always falling back to `legacy_default`. See the P1 implementation log's "store-bound default-pipeline slice" entry for detail. The remaining P1 gaps listed above (authored `kb.pipelines`/`kb.pipeline_bindings`/etc. tables, `kb.doc_facets`, conflict-detection enforcement, shadow mode, P1 benchmark closeout) are unchanged.

## Related documents

- Companion handoff: `2026073001-handoff-semos-gold-benchmark-and-tooling.md` — the technical build this session produced (CLI, mise tasks, prompt iterations, bug reports).
- Operations manual: `KnowledgeStore/doc-repo/devdocs/202607/2026073002-devdoc-gold-benchmark-operations.md` — how to run the benchmark, including corpus-extension options.
- P0 evidence record: `KnowledgeStore/doc-repo/devdocs/202607/2026073005-devdoc-semos-p0-benchmark-evidence.md` — what was executed, where the generated line files and benchmark artifacts went, and why the current evidence is sufficient to justify P1 policy work.
- P1 implementation log: `KnowledgeStore/doc-repo/devdocs/202607/2026073103-devdoc-semos-p1-implementation-log.md` — what part of P1 has actually been implemented so far, including the current processor-plan seam, persisted plan storage, requested-pipeline persistence, and API inspection surfaces.
- ADR `2026072901-adr-ontology-platform-and-adaptive-pipeline.md` and its three ratified inputs: research `2026072302`, spec `2026072702`, ADR `2026072701`.
