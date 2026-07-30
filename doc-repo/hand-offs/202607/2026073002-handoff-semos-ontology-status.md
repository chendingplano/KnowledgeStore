# SemOS Ontology Status — Session Handoff

Date: July 30, 2026

## Scope

This session started as ontology-consolidation work (research `2026072302`, spec `2026072702`, ADR `2026072701`) and drifted into building and validating a benchmark harness against the pilot domain those documents chose. This handoff exists specifically to capture **where the ontology design actually stands** — as opposed to what tooling got built — so a future session (or the user) can resume from an accurate baseline instead of assuming more of the ontology itself was implemented than actually was.

For the technical build this session produced (the `gold-run`/`analyze` CLI, mise tasks, prompt iterations, bug reports), see the companion handoff `2026073001-handoff-semos-gold-benchmark-and-tooling.md` — that document covers the *how*; this one covers the *what's actually designed vs. built*.

Work resumed on 2026-07-30 with explicit approval to complete P0 before starting P1/P2.

## Document lineage (read in this order if picking this up cold)

1. Research `2026072302-rsch-object-centric-ontology.md` (2026-07-23) — established the vocabulary and layered target. **Status: Research / architecture recommendation.**
2. Spec `2026072702-spec-ontology-canonical-artifacts.md` (2026-07-27) — turned the research into contracts (ownership, lifecycles, state machines). **Status: Proposal.**
3. ADR `2026072701-adr-ontology-identity-and-assertions.md` (2026-07-27) — ratified the spec's decisions. **Status: Accepted — design only, not yet implemented** (stated explicitly in its own header).
4. ADR `2026072901-adr-ontology-platform-and-adaptive-pipeline.md` (2026-07-29, revised twice since) — consolidates all three of the above plus the doc-processor capsule into one buildable architecture with an executable phased plan (DR0–DR24, P0–P7). **Status: Proposed (draft for review).** This is the current source of truth — treat documents 1–3 above as historical inputs already folded in, not independently authoritative anymore.

## Current status: still design, except one narrow validation slice

Searching the entire consolidated ADR for its own `**Built:**` implementation-status annotations turns up exactly three, all under DR21/DR22:

- `ChenWeb/server/api/ontology/comparison` (`Compare`, `EvaluateFamily`) — the DR21 requirement-strictness comparator, a pure function over normalized constraints.
- `ChenWeb/server/api/doc-benchmark/verdict_score.go` — `ScoreVerdictMatrix`, the DR22 outcome scorer.
- `ChenWeb/server/api/doc-benchmark/corpus_dataset.go` — the corpus-level dataset/case loader.

Alongside these (built this session, not separately annotated in the ADR yet): the `gold.toml` synthetic fixture itself, its CDM document generator (`generate.go`), `resolve.go`/`coverage.go`, and the `gold-run`/`analyze` CLI tooling (full detail in the companion handoff).

All of this maps directly onto P0's stated primary deliverable: *"Build the synthetic gold corpus and extend the existing benchmark... rather than waiting for a real-data example."* It's real, validated progress — but it is the **validation harness**, not the ontology architecture itself.

Everything that would actually make this "an ontology" — as opposed to a comparator test rig for one metric-extraction pipeline — remains pure design, with zero code, zero migrations, zero repo:

- The 7-layer architecture itself (evidence/artifacts → canonical identity → ontology terms → domain modules → qualified assertions → profiles → review).
- The canonicalization kernel / `semid` (DR15).
- The separate git-authored `semos-ontology` ontology-as-code data repository (DR17) — **does not exist yet, anywhere.**
- Two-tier pipeline routing: named pipelines, binding policies, blocking-by-default conflict resolution (DR6/DR7).
- Domain modules — not just the pilot 呼吸机 module, but even the shared 4a core modules (`core`, `quantity`, `document-authority`, `measurement`).
- Qualified assertions and the evidence schema (DR9).
- `ProcessorSpec` declarations and the DAG planner that would replace today's hardcoded three-phase pipeline (P1).

P1 ("pipeline plane") and P2 ("ontology core and canonicalization kernel") — the two phases where the ontology itself actually gets built — have not started.

## P0 continuation completed in this slice

- The deployed §13.5 audit was completed read-only against the live PostgreSQL system and recorded in ADR `2026072901` as a dated baseline.
- ADR C5 now reflects the real `kb.inputs.ks_store_id` partial wiring: the column exists and ingestion paths can populate it, but it still has no referential, routing, or semantic-scope role.
- Knowledge stores were inventoried from live data without inventing store-specific pipeline behavior: `Research` is populated, `卫健委标准` is empty, and some inputs remain unassigned.
- All 20 pilot competency questions are now structurally frozen in the consolidated ADR, with owner approval still pending for P0 exit.
- The 50-term ontology terminology crosswalk is now part of the consolidated ADR, including explicit non-support for an OWL reasoner runtime, automatic `owl:sameAs`, a SPARQL endpoint, and a triple store.
- The stale benchmark-wiring note in P0 was corrected while preserving the remaining `CorpusDataset` experiment-engine integration gap.

## Phase status (P0–P7)

Still inside **P0** ("semantic audit, competency questions, corpus baseline — no ontology/runtime implementation").

**Done within P0:**
- Gold corpus + comparator + benchmark CLI tooling (this session's build).
- Real baseline measurement — the `extract_metrics` recall-instability investigation (bug reports `2026073001`–`2026073003`) is literally P0's "baseline measurement per document kind: processor cost, artifact yield, artifact usefulness" bullet, carried out for real against the pilot corpus.
- Verified deployed DB/code baseline for ADR §13.5, including artifact cardinality, partitions, scene-object semantics, deletion behavior, and current knowledge-store inventory.
- Frozen competency-question suite and ontology terminology implementation contract in the consolidated ADR.

**Not done, still open within P0:**
- Owner approval of the frozen competency answers; P0 is not complete until domain/application owners agree in writing.
- Merge the two keyword-canonicalization specs into the one DR16 supersedes them with.
- Stand up the `semos-ontology` data repository and its CI skeleton (OD7).
- Confirm authoritative standard editions and a real-data worked example for the pilot domain.
- Gather enough per-document-kind baseline evidence to justify differentiated store-specific pipeline policies (DR18); the live inventory alone does not yet justify them.
- Broaden the fixture corpus beyond the one ventilator display-module case — no ambiguous-object, multilingual-name, unit-conversion, or superseded-document fixtures exist yet (devdoc `2026073002-devdoc-gold-benchmark-operations.md` §7 has concrete extension options).

**P1–P7:** not started at all.

## Open decisions (from the ADR's own table)

- **OD1 (which domain module is the pilot) — Resolved: 呼吸机/医疗器械**, driven by the target application. This is why everything built this session is ventilator-shaped. Open sub-item: the authoritative standard editions that should source the real profile still need to come from a real-data worked example, not the application's mock (the mock's clause citations and limit values are placeholders).
- **OD3 (where pipeline policies are authored) — Resolved by DR17:** the same data repository and compiler/activation path as ontology modules.
- **OD2, OD4–OD10 — still open:** facet-vocabulary home (`document-authority` vs. its own module), Phase D sync-vs-async default, multi-jurisdiction precedence vocabulary, hard-deletion/retention policy, ontology-repo hosting/access details (name `semos-ontology` proposed, needs confirming in P0), whether a document may belong to several knowledge stores, lexicon scope granularity, and category-canonicalization retrofit timing.

## Resolved history note

The stale P0 benchmark-wiring contradiction in ADR `2026072901` was corrected in this slice. The ADR now distinguishes between the benchmark components that are built and the narrower remaining `CorpusDataset` experiment-engine integration gap.

## Recommended next steps

1. Get owner approval on the frozen competency-answer contract and decide whether the consolidated ADR can move from `Proposed` to `Accepted` once those approvals land.
2. Merge the two keyword specs into the DR16 replacement, then stand up the `semos-ontology` repository and CI skeleton (OD7).
3. Expand the fixture families beyond the single ventilator display-module case, especially ambiguous-object, multilingual, unit-conversion, supersession, and conflict fixtures.
4. Gather per-document-kind baseline evidence before authoring differentiated store-specific pipeline policies; P1 and P2 still have not started.

## Related documents

- Companion handoff: `2026073001-handoff-semos-gold-benchmark-and-tooling.md` — the technical build this session produced (CLI, mise tasks, prompt iterations, bug reports).
- Operations manual: `KnowledgeStore/doc-repo/devdocs/202607/2026073002-devdoc-gold-benchmark-operations.md` — how to run the benchmark, including corpus-extension options.
- ADR `2026072901-adr-ontology-platform-and-adaptive-pipeline.md` and its three ratified inputs: research `2026072302`, spec `2026072702`, ADR `2026072701`.
