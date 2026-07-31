# SemOS P2 Implementation Log

**Date:** 2026-07-31 (log opened; P2 spans sessions)
**Scope:** Execution log for P2 — ontology core and canonicalization kernel — in `ChenWeb`, following plan `2026073104-plan-semos-p2-ontology-core-and-canonicalization-kernel.md`.

## 0. Summary — what P2 is

P2 builds the semantic layer that P1's pipeline plane will route, enforce, and explain. It delivers:

- governed, versioned ontology content tables (`kb.ontology_terms`, `kb.ontology_term_labels`, `kb.ontology_axioms`, `kb.ontology_mappings`) and the `kb.ontology_candidates` state machine (spec §9.3);
- a **DB-native** module compiler (`ontology-compiler`: `validate`/`release`/`activate`/`rollback`) producing immutable, checksummed releases with an activation pointer;
- the core 4a modules (`core`, `quantity`, `document-authority`, `measurement`) installed as **data** (the DR1 property), with the full QUDT catalog imported into `quantity`;
- the `semid` canonicalization kernel (normalizers, candidate generation, scoring, adjudication, merge/split with tombstones, `never_merge`, decision log), first instantiated for ontology terms;
- `kb.object_nodes` extension columns (`ontological_level`, `identity_scope`, `external_identifiers`, `primary_class_term_id`, `merged_into`, `scope_key`);
- extension seams 1–4 complete and documented.

### 0.1 Storage decision (user directive, 2026-07-31 — overrides DR2/DR17)

> **Data lives in the database. Shareable code lives in `shared`; project-specific code lives in `ChenWeb`. No data-only Git repository.**

Consequences recorded in the ADR (chunk 0) and applied throughout P2:

- No `semos-ontology` Git repository. Ontology content is authored and versioned in the DB with `version` columns.
- The LLM-cannot-activate guarantee is code-enforced via the candidate state machine, not Git authorship.
- The compiler is a DB-native validator/releaser; transient inputs (e.g., QUDT TTL) are generator input whose output lands in the DB.
- All P2 runtime code is ChenWeb-specific and lives under `ChenWeb/server/`.

## 1. Chunk 0 — storage decision, versioning model, plan wiring

- ADR `2026072901` change-log entry added (2026-07-31 storage-model revision).
- DR2 and DR17 annotated in place with the storage-revision note.
- Plan `2026073104-plan-semos-p2-ontology-core-and-canonicalization-kernel.md` written; cross-link from the ADR pending finalization of this log.

## 2. Current slice (work in progress)

**Chunk A — ontology content stores and the candidate lifecycle.** Not yet started in code.

## 3. Files touched

(TBD as slices land)

## 4. Targeted tests

(TBD as slices land)

## 5. Current state and next expected slice

Chunk 0 docs are staged in `KnowledgeStore`. Next: chunk A migrations (`kb.ontology_terms`, `kb.ontology_term_labels`, `kb.ontology_axioms`, `kb.ontology_mappings`, `kb.ontology_candidates`).
