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

- ADR `2026072901` change-log entry added (2026-07-31 storage-model revision); DR2 and DR17 annotated in place.
- Plan `2026073104-plan-semos-p2-ontology-core-and-canonicalization-kernel.md` written; cross-linked from the ADR references and the ontology-status handoff.
- This implementation log opened.

## 2. Chunk A — ontology content stores and the candidate lifecycle (complete)

### A1 — Migrations

Migrations `20260731000014`–`00020`:

| Migration | Table / change |
|---|---|
| `00014` | `kb.ontology_terms` (term_id + version, term_kind CHECK, status CHECK, UNIQUE(term_id, version)) |
| `00015` | `kb.ontology_term_labels` (label_role CHECK prefLabel/altLabel/hiddenLabel) |
| `00016` | `kb.ontology_axioms` (object_term_id OR object_iri required) |
| `00017` | `kb.ontology_mappings` (relation CHECK exact/close/broad/narrow/related; approval_status) |
| `00018` | `kb.ontology_candidates` (candidate_kind CHECK, fingerprint UNIQUE, spec §9.3 status CHECK) |
| `00019` | candidates status CHECK widened to include `superseded` (new migration, per the never-edit-an-applied-migration rule) |
| `00020` | `source_candidate_id` added to labels/axioms/mappings (promotion provenance + idempotency) |

All validated against live Postgres (`chenweb_test` and, via the dev server's goose run, the dev DB `miner`).

### A2–A4 — Stores, candidate lifecycle, promotion

New packages under `ChenWeb/server/api/ontology/`:

- `terms/` — `TermStore` (versioned Create/Get/List, governed status transitions), `LabelStore` (one-prefLabel-per-lang rule), `AxiomStore`, `MappingStore` (exact mappings require approval). Content rows carry `version` columns per the storage decision; `source_candidate_id` links back to the proposing candidate.
- `candidates/` — `CandidateStore` with:
  - the spec §9.3 state machine (`discovered → draft → in_review → approved → included_in_release`, plus `rejected`/`deferred`/`superseded`; deferred retries only on a changed dependency fingerprint);
  - `Fingerprint` (sha256 over canonical payload + source + module) with `UNIQUE(fingerprint)` dedup — reprocessing an identical proposal reuses the candidate (spec §16.3 item 1);
  - `CreateCandidate` (ON CONFLICT DO NOTHING → reuse), `TransitionStatus`, `DeferCandidate` (records the dependency fingerprint it is blocked on), `RetryDeferred` (refuses unchanged fingerprint), `UpdatePayload` (frozen from in_review), `PromoteToContent` (approved candidate → content row, idempotent, candidate stays `approved` — inclusion in a release is chunk B).

### A5 — Handlers and routes

`kbhandler/ontology_terms_handler.go` and `kbhandler/ontology_candidates_handler.go`, registered under `/api/v1/kb/ontology/`:

- terms: `GET/POST /terms`, `GET /terms/:term_id`, `POST /terms/:term_id/versions`, `POST /terms/:term_id/:version/status`, `POST/GET /terms/:term_id/labels`
- candidates: `GET/POST /candidates`, `GET /candidates/:id`, `POST /candidates/:id/transition`, `POST /candidates/:id/defer`, `POST /candidates/:id/retry`, `PUT /candidates/:id/payload`, `POST /candidates/:id/promote`

### A6 — Verification

- Unit tests (sqlmock + pure-logic) across `terms/` and `candidates/` including the full state machine, fingerprint determinism, dedup, promotion, and the defer/retry fingerprint gate.
- Handler tests for the candidate HTTP surface.
- **Live-Postgres validation** (`chenweb_test`, via a temporary `server/cmd/p2validate` program run against the real stores, then deleted): create → dedup-reuse → discovered→draft→in_review→approved → promote (term row exists with source_candidate_id) → idempotent re-promote → draft-promote rejected → deferred-retry-unchanged rejected → deferred-retry-changed returns to draft. **All checks passed.**

### Bugs found by live validation (would have shipped silently)

1. **`RETURNING` with a `FROM` clause.** The column-list constants (`termSelectColumns` etc.) included `FROM kb.ontology_*`, which is valid in `SELECT` but a syntax error in an `INSERT ... RETURNING`. The sqlmock unit tests matched query *text* and did not parse SQL, so this only surfaced against real Postgres. Fixed by splitting each constant into `<x>Columns` (no FROM) + `<x>From`, used only where legal.
2. **Deferral never recorded a dependency fingerprint.** Transitioning to `deferred` via the generic `TransitionStatus` left `dependency_fingerprint` empty, making the retry-unchanged check vacuous (any new value "differed" from empty). Added `DeferCandidate`, which requires and records the blocked-on fingerprint.

### Live dev-DB note

The running `mise dev` / air server auto-applies new goose migrations to the dev DB (`miner`) on restart. Migrations `00014`–`00020` were applied there cleanly. Because applied migrations must not be edited, the `superseded` status and `source_candidate_id` were added via new migrations (`00019`, `00020`) rather than editing `00018`/`00015`–`00017`.

## 3. Files touched (chunk A)

- `ChenWeb/project_migrations/20260731000014..00020_*.sql` (7 migrations)
- `ChenWeb/server/api/ontology/terms/{terms_store,labels_store,axioms_store,mappings_store,nullable}.go` + tests
- `ChenWeb/server/api/ontology/candidates/{state_machine,fingerprint,candidates_store,promote,nullable}.go` + tests
- `ChenWeb/server/api/kbhandler/ontology_{terms,candidates}_handler.go` + `ontology_candidates_handler_test.go`
- `ChenWeb/server/api/routes.go`

## 4. Targeted tests

```bash
go test ./server/api/ontology/... -count=1
go test ./server/api/kbhandler -run 'TestCreateOntologyCandidate|TestPromoteOntologyCandidate' -count=1
```

`go test ./server/api/kbhandler/...` (full package) still shows the same pre-existing search/registry/summary/topic/category failures noted in the P1 log (14, none touching ontology code).

## 5. Current state and next expected slice

Chunk A (ontology content stores + candidate lifecycle) is complete and live-validated. Next: **chunk B** — DB-native module compiler, releases, and activation (`kb.ontology_modules`, `kb.ontology_module_releases`, `kb.ontology_active_releases`; `server/cmd/ontology-compiler` with `validate`/`release`/`activate`/`rollback`; the runtime loader seam).
