# SemOS P2 — Ontology Core and Canonicalization Kernel: Implementation Plan

This plan follows P1 closeout on Friday, July 31, 2026. P1 built the pipeline plane (named pipelines, bindings, rules, policies, facets, enforcement, execution plans). P2 builds the semantic layer that plane will route, enforce, and explain: the ontology term model, the module compiler and release/activation mechanism, the four core 4a modules, and the `semid` canonicalization kernel with ontology terms as its first instantiation.

This plan covers **all** of P2 (chunks 0–F). Implementation proceeds in dependency order, starting with chunk A (ontology term stores and the candidate lifecycle), per the scope decision recorded on 2026-07-31.

## Storage decision (user directive, 2026-07-31 — overrides DR2/DR17)

The ontology platform follows one storage principle:

> **Data lives in the database. Shareable code lives in `shared`; project-specific code lives in `ChenWeb`. No data-only repository.**

Consequences, recorded here because they revise the ADR:

- **No `semos-ontology` Git repository.** DR2's "author in Git, compile into Postgres" and DR17's dedicated data repository are **not** implemented as written. Ontology content (terms, labels, axioms, mappings, the QUDT catalog) is authored and versioned **in the database**. AD8's rejection of ChenWeb/KnowledgeStore as *repos* is moot — content is not a repo at all.
- **Versioning is by column, not by Git tag.** Governed content tables carry a `version` column; each accepted change creates a new version row, and old versions remain queryable. Module and release tables carry their own version identity. See the versioning model in chunk A.
- **The LLM-cannot-activate guarantee becomes code-enforced.** In the Git model, promotion required a human committing module source. In the DB model, the same guarantee is enforced by the candidate state machine (spec §9.3): LLM output lands in `kb.ontology_candidates`; nothing writes accepted rows to governed content tables except an explicitly approved release/activation path.
- **The compiler becomes a DB-native validator/releaser.** `ontology-compiler` reads staged content from the DB, validates it, computes a deterministic content checksum, writes one immutable release, and manages the activation pointer. Transient inputs (e.g., QUDT TTL) are accepted by import generators whose output lands in the DB; the DB is the system of record.
- **Code placement.** All P2 runtime code is SemOS/ChenWeb-specific and lives under `ChenWeb/server/`. If any piece (e.g., the `semid` kernel or `semrules` evaluator) later becomes genuinely cross-project, it moves to `shared/go` at that point; nothing is pre-emptively placed in `shared`.

This storage decision is a revision to ADR `2026072901` DR2/DR17 and is recorded there in chunk 0.

## Goal

Build the ontology core and canonicalization kernel such that:

- governed terms, labels, axioms, and mappings are first-class, versioned database records with a release lifecycle;
- an immutable, checksummed module release can be activated atomically and rolled back without deleting history;
- the four core 4a modules (`core`, `quantity`, `document-authority`, `measurement`) are installed as **data**, with no code change (the DR1 property);
- the `semid` canonicalization kernel provides one shared mechanism for normalizer → candidates → scoring → adjudication → merge/split → audit, instantiated first for ontology terms;
- `kb.object_nodes` carries the DR10/DR15.1 extension columns; and
- extension seams 1–4 are complete and documented.

P2 does **not** implement assertions/evidence, Phase D association, the keyword lexicon, profiles, or the comparison application. Those remain P3+.

## Architecture

```text
authoring (API CRUD / governed import)         candidate producers (LLM extraction, discovery)
        │  draft, in_review, approved                    │
        ▼                                                 ▼
kb.ontology_terms/labels/axioms/mappings  <──────  kb.ontology_candidates
        │  (versioned rows)                               (spec §9.3 state machine, fingerprint)
        │  ontology-compiler: validate → checksum → immutable release
        ▼
kb.ontology_module_releases  ── activate/rollback ──>  kb.ontology_active_releases
        │
        ▼
runtime readers (term resolution, semid, future assertions/profiles)
```

Key invariants:

- Content is authored and versioned in the DB; no content lives in Git.
- Nothing activates ontology content except an explicitly approved release/activation path; an LLM may produce candidates only.
- A release is immutable, checksummed, dependency-pinned, and atomically activated; failed validation leaves the previous active release untouched.
- The canonicalization kernel is built once and instantiated per family; merge decisions are tombstones with no transitive closure.

## Tech stack

- Runtime and stores: `ChenWeb/server/api/ontology/` (subpackages `terms/`, `candidates/`, `modules/`, `semid/`, `semrules/`)
- Compiler CLI: `ChenWeb/server/cmd/ontology-compiler`
- QUDT import generator: `ChenWeb/server/cmd/ontology-compiler` subcommand or `ChenWeb/server/api/ontology/quantity/`
- Database migrations: `ChenWeb/project_migrations/`
- Docs and ADR/spec updates: `KnowledgeStore/doc-repo/`
- DB access: `database/sql` + the P1 `SQLStore`/interface/`Load*` pattern; goose migrations; sqlmock + fake-store tests

## Scope boundaries

In scope:

- ontology content tables with versioning; `kb.ontology_candidates` with the spec §9.3 state machine
- module/release/activation tables; the DB-native compiler (`validate`/`release`/`activate`/`rollback`)
- core 4a module content: `core`, `document-authority`, `measurement` (authored as data) and `quantity` (QUDT full catalog imported as data)
- the `semid` kernel and its ontology-term family instantiation; `semid_*` tables
- `kb.object_nodes` extension columns (`ontological_level`, `identity_scope`, `external_identifiers`, `primary_class_term_id`, `merged_into`, `scope_key`)
- extension seams 1–4 complete and documented
- exit-criteria tests: spec §16.3 items 1–7, DR1 data-install property, kernel merge/split fixtures

Out of scope (P3+):

- assertion/evidence schema and stores (`kb.semantic_assertions`, evidence, relations) — including full classification-as-assertion (DR10) and the derived `primary_class_term_id` maintenance
- Phase D stages (`normalize_assertions`, `associate_semantics`, `project_semantics`)
- the keyword lexicon instantiation (`kb.keyword_*`)
- profiles, profile rules, review scopes
- the comparison matrix / verdict service beyond the already-built comparator
- `semrules` as a full DR3 predicate language — P2 ships only the seam-3 registry scaffold (chunk F)

## Implementation chunks

### Chunk 0 — Storage decision, versioning model, and plan wiring

- [ ] Add a change-log entry to ADR `2026072901` recording the DB-native storage decision (revision to DR2/DR17): data in the database, no data-only repo, version columns, code in `shared`/`ChenWeb`. Annotate DR2, DR17, and AD8 with the revision pointer.
- [ ] Define the versioning model in writing: governed content tables (`kb.ontology_terms`, `kb.ontology_term_labels`, `kb.ontology_axioms`, `kb.ontology_mappings`) carry a `version` column; an accepted change inserts a new version row; the latest version is the current state; releases pin exact versions; a material meaning change creates a new `term_id` and deprecates the old (never a silent redefinition).
- [ ] Cross-link this plan from the ADR and the ontology-status handoff.

Acceptance:

- [ ] ADR, handoff, and this plan describe the same P2 boundaries and the same storage model.

### Chunk A — Ontology content stores and the candidate lifecycle

- [ ] Migrations: `kb.ontology_terms`, `kb.ontology_term_labels`, `kb.ontology_axioms`, `kb.ontology_mappings`, `kb.ontology_candidates`.
- [ ] `kb.ontology_terms`: `term_id` (immutable, namespaced, e.g. `core:assertion`), `version`, `term_kind` (`class` | `property` | `individual` | `concept` | `metric_definition` | `quantity_kind` | `unit` | `dimension` | …), `module_id`, `status`, `definition`, `scope`, timestamps/actors. `UNIQUE(term_id, version)`.
- [ ] `kb.ontology_term_labels`: `term_id` + `version`, language, `label_role` (`prefLabel`/`altLabel`/`hiddenLabel`), label text, status.
- [ ] `kb.ontology_axioms`: `axiom_id`, kind (compiler-approved set only), subject/predicate/object as governed refs, module, version, status.
- [ ] `kb.ontology_mappings`: `from_term`, `to` (IRI or governed term), mapping strength (`exact`|`close`|`broad`|`narrow`|`related`), evidence, approval, version.
- [ ] `kb.ontology_candidates` per spec §9.3: `candidate_kind` (`term`|`label`|`mapping`|`axiom`|`module_change`), `proposed_payload JSONB`, `proposed_module_id`, `source_type`, `source_ref`, `source_line_spans`, `discovery_method`, `confidence`, `fingerprint` (deterministic over normalized payload + source + module), `candidate_matches JSONB`, `status`, `proposed_by`, timestamps.
- [ ] Candidate state machine (spec §9.3) enforced in Go: `discovered → draft → in_review → approved → included_in_release`, with `rejected` and `deferred` (deferred retries only on dependency-fingerprint change). `in_review` freezes the reviewed payload; later edits create a new revision. No LLM path can reach `approved`/`included_in_release`.
- [ ] Fingerprint dedup: reprocessing an identical proposal reuses the existing candidate and records `last_seen`, creating no duplicate review work (spec §16.3 item 1).
- [ ] Stores under `ChenWeb/server/api/ontology/terms/` and `.../candidates/` (SQLStore pattern), CRUD + state-transition handlers, sqlmock + fake-store tests.

Likely touch points:

- [ ] `ChenWeb/project_migrations/20260731XXXX_create_kb_ontology_terms.sql` (+ labels/axioms/mappings/candidates)
- [ ] `ChenWeb/server/api/ontology/terms/`, `ChenWeb/server/api/ontology/candidates/`
- [ ] `ChenWeb/server/api/routes.go`

Acceptance:

- [ ] Spec §16.3 items 1–4 hold: candidate fingerprint dedup; state-machine transitions enforced; rejected candidates retain reasons; deferred candidates retry only after dependency change; no LLM-only path reaches an active state.
- [ ] Terms/labels/axioms/mappings are queryable by module, version, and status.

### Chunk B — DB-native module compiler, releases, and activation

- [ ] Migrations: `kb.ontology_modules`, `kb.ontology_module_releases` (immutable; `payload JSONB` + `content_checksum` + pinned dependency releases + `released_by/at`), `kb.ontology_active_releases` (activation pointer + audit; at most one active release per module, partial unique index).
- [ ] `kb.ontology_modules`: `module_id`, `version`, `title`, `owner`, `description`, `depends_on` (declared module dependencies), status.
- [ ] `server/cmd/ontology-compiler` operating on DB-staged content:
  - `validate --module <id>` — schema/required-field, duplicate/identity, dangling-reference, dependency-acyclicity, and axiom/mapping consistency checks over the module's approved content. No writes.
  - `release --module <id> --version <v>` — in one transaction: validate; collect the module's `approved` content rows; compute a deterministic content checksum; write the immutable `kb.ontology_module_releases` row with payload snapshot and dependency pins; tag included content rows `included_in_release` + `release_id`. A validation failure aborts the transaction and leaves the previous active release untouched.
  - `activate --module <id> --release <n>` — insert into `kb.ontology_active_releases` (one active per module). Audit-recorded.
  - `rollback --module <id> --release <n-older>` — insert a new activation pointer to the older release; delete nothing.
- [ ] `mise` task wiring `ONTOLOGY_MODULE_ROOT`-free compiler invocation against the configured DB.
- [ ] Runtime loader seam (seam 4): a `LoadModuleRelease`-style loader that installs the active releases into the in-process module registry at startup, following the P1 registry pattern.

Acceptance:

- [ ] Spec §16.3 items 5 and 7: activation is atomic and pins dependency releases; rollback re-points the pointer and preserves both releases and the audit trail; an approved change set activates all items together through one release; a deliberately failed validation or activation leaves the previous active release unchanged.
- [ ] A release checksum is reproducible from the same staged content.
- [ ] The active-release pointer is the single authority for which terms/labels/axioms/mappings are production-visible.

### Chunk C — Core 4a module content (authored as data)

- [ ] Author and seed `core` content: referent, information artifact, assertion, evidence, agent, role, valid/transaction time, polarity, confidence, semantic-role predicates, and the DR20 part hierarchy (`core:part_of`, `core:component_of`, `core:variant_of`).
- [ ] Author and seed `document-authority` content, including the DR4 document-facet vocabulary (facet keys and permitted values as governed terms).
- [ ] Author and seed `measurement` content: metric definition vs metric assertion, observable property, feature of interest, procedure, condition, aggregation/window, and the metric-assertion kinds of research §5.4.
- [ ] Author and seed `quantity` content from the **full published QUDT catalog** per DR13: a QUDT import generator parses the published TTL (quantity kinds, units, dimensions) into staged content rows with source provenance (source IRI, license, source version, checksum), then released through the compiler. This is the largest single sub-chunk; it is tracked as its own work item.
- [ ] Each 4a module is released and activated through the compiler (chunk B). Installing them must require **no code change** (the DR1 property) — if a 4a module cannot be expressed as data, that is a signal that the content model is incomplete.

Likely touch points:

- [ ] `ChenWeb/project_migrations/` — seeds for `core`, `document-authority`, `measurement` content (migration seeds are code that populates the DB; the DB is the store)
- [ ] QUDT import generator + a Go Turtle/RDF parser dependency
- [ ] `ChenWeb/server/cmd/ontology-compiler` import subcommand

Acceptance:

- [ ] The four core modules install and activate as data; a term added to a module and released reaches production visibility with no Go code change and no migration.
- [ ] QUDT content is pinned, validated, and released through the module compiler; source provenance is retained.
- [ ] The facet vocabulary (`document-authority`) is queryable as governed terms (OD2 default: start in `document-authority`).

### Chunk D — `semid` canonicalization kernel

- [ ] Migrations: `kb.semid_decision_log` (shared across families: input, output, verdict, model, prompt_version, actor, tokens, created_at), `kb.semid_never_merge` (`family`, `node_a`, `node_b`, `reason`, `actor`), `kb.semid_snapshots` (`family`, `normalizer_version`, `counts`, `promoted_at`). `kb.object_nodes` gains `merged_into` and `scope_key` (DR15.1 contracts).
- [ ] Kernel package `ChenWeb/server/api/ontology/semid/`: normalizer profiles (versioned; a normalizer change is a re-index, never data loss), candidate generation (exact key | alternate keys | trigram | vector | blocking), deterministic scoring, adjudication (auto-accept | ambiguous | defer | LLM batch | human), link, merge/split with tombstones and no transitive closure, `never_merge` enforcement, and an append-only decision log.
- [ ] Family adapters declare only what differs: surface store, canonical node store, normalizer profile, scoring weights, auto-accept policy, scope dimension.
- [ ] First instantiation: **ontology terms** — surfaces `kb.ontology_candidates`, canonical nodes `kb.ontology_terms`, scope = module. Because terms are governed, adjudication **ends at a change set** (proposed duplicates/mappings/extension/new-term classifications reviewed by a curator), never an auto-accept.
- [ ] DR15.1 contracts on live families only: `kb.object_nodes.merged_into`/`scope_key` columns exist; object-node reconciliation behavior is unchanged (parity fixtures).

Likely touch points:

- [ ] `ChenWeb/server/api/ontology/semid/` (kernel) and `.../semid/termfamily/` (instantiation)
- [ ] `ChenWeb/server/api/doc-processing/artifact_objects.go` (object-node struct/columns)

Acceptance (ADR kernel tests, term-family subset):

- [ ] The same normalizer input produces the same key bundle across restarts; a normalizer-version bump re-indexes without losing a surface or a link (test 18).
- [ ] A merge sets `merged_into`, keeps the losing row, and continues to resolve stale ids; an unmerge restores the pre-merge state (test 19).
- [ ] Pairwise merges A→B and B→C do **not** silently produce A→C (test 20).
- [ ] A `never_merge` pair is never merged by any automatic path (test 21).
- [ ] Object-node reconciliation behavior is unchanged by the kernel's introduction (test 23).
- [ ] Candidate adjudication for ontology terms produces reviewable change-set output, never an automatic accept.

### Chunk E — `kb.object_nodes` extension (columns only)

- [ ] Migration: `kb.object_nodes` gains `ontological_level`, `identity_scope`, `external_identifiers JSONB`, `primary_class_term_id` (derived), plus the chunk-D `merged_into`/`scope_key`.
- [ ] Update the `ObjectNode` Go struct, store queries, and reconciliation code paths for the new columns.
- [ ] `primary_class_term_id` is added as a nullable derived projection column; its **maintenance** via classification assertions and `project_semantics` lands in P3 with the assertion store (per the 2026-07-31 scope decision: columns only in P2).

Acceptance:

- [ ] `kb.object_nodes` rows can carry an `ontological_level` and `identity_scope` with provenance; existing object-node queries and behavior are unchanged when the new columns are unset.
- [ ] CQ-I02-style lookup (`ontological_level` with provenance) is expressible.

### Chunk F — Extension seams 1–4, exit criteria, and documentation

- [ ] Seam 1 — `ProcessorRegistry` (DR5 declarations): extend `ProcessorSpec` with the DR5 fields (`Requires`, `Produces`, `Class`, `Cost`, `OnUndetermined`) and formalize registration so adding a processor does not require editing the mechanism.
- [ ] Seam 2 — `FacetProducerRegistry`: formalize the existing facet producers (tier-1/2) into a registry so a producer + governed facet terms can be added without editing the mechanism.
- [ ] Seam 3 — `PredicateOperatorRegistry` + minimal `semrules` evaluator (`ChenWeb/server/api/ontology/semrules/`): predicate AST, operator registry, evaluator with trace, conflict/indeterminate semantics. Scope is the seam, not the full DR3 language — the flat-column rule path stays active until P5 adopts JSONB predicates.
- [ ] Seam 4 — module compiler + loader (chunk B) documented as a seam.
- [ ] Exit-criteria tests: spec §16.3 items 1–7 as automated tests; the DR1 property (a term added by committing/releasing module data reaches production with no code change); a deliberately failed validation leaves the previous active release untouched; kernel merge/split fixtures (chunk D).
- [ ] Documentation: new capsule `KnowledgeStore/Capsules/coding-capsules/ontology/+CAPSULE.md` (content model, compiler, release workflow, DB-native storage); update ADR `2026072901` DR2/DR17 annotations; update the ontology-status handoff; write the P2 implementation log devdoc (`KnowledgeStore/doc-repo/devdocs/202608/`).
- [ ] Record in the docs what is intentionally deferred to P3 (assertions/evidence, classification-as-assertion maintenance, keyword lexicon, semrules full language).

Acceptance:

- [ ] Each seam has a documented mechanism and at least one instance added through it.
- [ ] A future handoff can distinguish "ontology core + kernel built" from "assertions/association built".

## Suggested implementation order

1. Chunk 0 — storage decision and versioning model (alongside the first code change)
2. Chunk A — ontology content stores + candidate lifecycle
3. Chunk B — module compiler + release/activation
4. Chunk C — core 4a module content (QUDT import is the long pole; start its data sourcing early)
5. Chunk D — `semid` kernel (needs chunk A content tables)
6. Chunk E — `object_nodes` extension (independent; can be interleaved)
7. Chunk F — seams, exit criteria, docs

## Risks and controls

| Risk | Why it matters | Control |
|---|---|---|
| Storage-model drift from the ADR (DR2/DR17 Git-repo text) | Could mislead future readers or re-introduce a data repo | Chunk 0 records the revision in the ADR; docs consistently describe the DB-native model |
| Losing the LLM-cannot-activate guarantee without Git authorship | The core governance invariant depends on it | Code-enforced candidate state machine; no LLM path writes accepted content; covered by spec §16.3 items 3–4 tests |
| Versioning churn on content tables | Could overcomplicate or lose history | Version column + append-per-version rows; releases pin exact versions; material change = new `term_id` |
| Full QUDT catalog import is a long pole | Largest single data effort in P2; real TTL parsing + provenance | Tracked as its own sub-chunk; start sourcing early; the generator writes to the DB, keeping the compiler surface uniform |
| Compiler writes releases without genuine validation | Releases must be reproducible and safe | All validation runs inside the release transaction; failed validation aborts and leaves the active release untouched; checksum is deterministic |
| The kernel over-merges ontology terms | The asymmetric risk across all four families | Tombstones, `never_merge`, no transitive closure, governed adjudication ends at a change set (no auto-accept) |
| Seam scaffolding drags in P3 scope (full DR3/semrules) | Scope creep into the applicability language | Chunk F ships only the seam-3 registry scaffold; the flat-column rule path stays active |
| Object-node columns break existing reconciliation | Live resolver must not change (DR15.1) | Columns added null/empty-safe; parity fixtures (kernel test 23) |

## Exit criteria

P2 is complete when all of the following are true:

- [ ] spec §16.3 items 1–7 pass as automated tests (candidate dedup, state machines, no-LLM-activation, atomic release/rollback, replacement-term discipline, all-items-together activation);
- [ ] a term added by authoring module content in the DB and running the compiler reaches production visibility with **no Go code change and no migration**;
- [ ] a deliberately failed validation or activation leaves the previous active release untouched;
- [ ] the `semid` kernel merge/split fixtures show no transitive closure and no loss of a merged id, and `never_merge` is honored;
- [ ] the four core 4a modules (`core`, `quantity`, `document-authority`, `measurement`) are installed as data and activated;
- [ ] `kb.object_nodes` carries the DR10/DR15.1 extension columns with existing behavior unchanged;
- [ ] extension seams 1–4 are complete and each has at least one documented instance;
- [ ] the ADR records the DB-native storage decision, and the documentation clearly separates "ontology core + kernel built" from "assertions/association/keyword-lexicon built".
