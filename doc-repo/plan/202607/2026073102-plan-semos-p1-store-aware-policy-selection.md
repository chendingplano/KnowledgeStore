# SemOS P1 Store-Aware Policy Selection Implementation Plan

This plan follows P0 closeout on Friday, July 31, 2026. P0 proved, with benchmark evidence, that different coarse store/document profiles want different processor policies. P1 is the first implementation phase that turns that proof into runtime structure without yet building the ontology runtime itself.

Agentic workers note: if this plan is executed with parallel workers, split by dependency-safe seams only. Suggested seams are (1) processor declarations and DAG planning, (2) document facets and persistence, (3) policy/rule/binding model, and (4) plan persistence, APIs, and shadow-mode verification.

## Goal

Implement the minimum production-facing pipeline-plane foundation needed to select and explain processor policies by store and document facts, while preserving byte-identical behavior when no policy is activated.

At the end of P1, SemOS should be able to:

- describe processors declaratively instead of only by hardcoded phase lists;
- compute reusable document facets;
- bind a named pipeline by knowledge store or explicit request;
- evaluate deterministic policy rules into an execution plan;
- persist and expose that plan; and
- run in shadow mode so decisions are visible before enforcement.

P1 does not implement ontology term storage, canonicalization, assertion normalization, profile-governed semantic review, or store-aware lexicon resolution. Those remain P2+ work.

## Architecture

```text
ingest request / rerun
  -> resolve binding context
  -> compute or load document facets
  -> choose named pipeline
  -> evaluate processor rules + DAG declarations
  -> persist execution plan
  -> execute legacy-equivalent or policy-filtered processor set
  -> expose plan + reasons in APIs/dashboard
```

Key invariants:

- No active policy means legacy behavior.
- A seeded default policy must reproduce the current required-processor behavior exactly.
- Rule conflicts are never silently resolved.
- Plan computation is explainable and replayable from persisted inputs.

## Tech Stack

- Runtime and planner: `ChenWeb/server/api/doc-processing/`
- Benchmark and verification harness: `ChenWeb/server/api/doc-benchmark/`
- Database migrations: `ChenWeb/project_migrations/`
- Shared helpers, if needed across apps: `shared/go/`
- Documentation and ADR/spec updates: `KnowledgeStore/doc-repo/`

## Scope boundaries

In scope:

- `ProcessorSpec` declarations for the existing processor roster
- planner/DAG reconstruction for current A/B/C behavior
- deterministic document facets and optional facet persistence
- named pipeline model, rule model, binding model
- `kb.inputs` pipeline-selection fields
- persisted execution plan and shadow mode
- APIs/dashboard visibility needed to inspect plans
- regression and benchmark checks proving legacy parity

Out of scope:

- ontology module compiler/runtime
- canonicalization kernel
- assertion/evidence schema
- SHACL export/runtime enforcement
- semantic reviewer changes beyond reading plan context

## Implementation chunks

### Chunk 1 — Freeze the source-of-truth contracts

- [ ] Confirm the exact P1 contract in [2026072901-adr-ontology-platform-and-adaptive-pipeline.md](/Users/cding/Workspace/KnowledgeStore/doc-repo/adrs/202607/2026072901-adr-ontology-platform-and-adaptive-pipeline.md) §P1 and cross-link this plan from the ADR/handoff.
- [ ] Record the P1 execution target in a short devdoc under `KnowledgeStore/doc-repo/devdocs/202607/` once implementation starts, so command paths, tables, and evidence locations stay current.
- [ ] Define the rollout principle in writing: `plan-only` first, enforcement second.

Acceptance:

- [ ] ADR, handoff, and this plan describe the same P1 boundaries.

### Chunk 2 — Processor declarations and DAG planner parity

- [ ] Add a declarative `ProcessorSpec` model under `ChenWeb/server/api/doc-processing/` for the current processor roster.
- [ ] Encode current dependencies, phases, concurrency constraints, and any required barriers that today are implicit in code.
- [ ] Build a planner that reconstructs the current A/B/C execution order from declarations.
- [ ] Keep the existing runtime path available behind a parity check until the declarative planner is trusted.

Likely touch points:

- [ ] `ChenWeb/server/api/doc-processing/runtime.go`
- [ ] `ChenWeb/server/api/doc-processing/`
- [ ] `ChenWeb/server/api/doc-processing/runtime_selection_test.go`

Acceptance:

- [ ] For legacy configuration, planned processors and execution order match current behavior exactly.
- [ ] Existing processor completion/failure accounting remains unchanged.

### Chunk 3 — Document facets and facet persistence

- [ ] Define the minimum tier-1 and tier-2 facet vocabulary required for P1 routing, starting from already-available deterministic facts.
- [ ] Implement facet production from ingest/request context and existing document metadata.
- [ ] Create the `kb.doc_facets` table if persistence is needed for replay, debugging, and reruns.
- [ ] Ensure facet computation can be reused by reruns without redoing unnecessary work when source inputs are unchanged.

Likely data to support first:

- [ ] document kind
- [ ] language
- [ ] knowledge store / store type
- [ ] source authority hints
- [ ] explicit request context

Acceptance:

- [ ] Facets are deterministic for the same document/input state.
- [ ] Planner can consume facets without calling an LLM.

### Chunk 4 — Named pipelines, rules, and bindings

- [ ] Introduce a named pipeline model that can express at least:
  - [ ] default legacy-equivalent pipeline
  - [ ] explicit processor inclusion/exclusion
  - [ ] rule-driven applicability by facets
- [ ] Introduce binding precedence for:
  - [ ] explicit `requested_pipeline`
  - [ ] knowledge store binding
  - [ ] fallback system default
- [ ] Decide whether P1 stores pipeline/rule definitions in ChenWeb tables first or in an interim code/config seed, while keeping the ADR’s longer-term authored-policy direction intact.
- [ ] Make conflicts blocking by default, with explainable reasons.

Likely schema work:

- [ ] add `requested_pipeline` (or equivalent) to `kb.inputs`
- [ ] add pipeline/binding tables needed for named-pipeline lookup and versioning

Acceptance:

- [ ] A document in store A can select a different named pipeline than a document in store B.
- [ ] An explicit request can override the store binding.
- [ ] Equal-priority conflicts fail deterministically and visibly.

### Chunk 5 — Persisted execution plans and shadow mode

- [ ] Persist one execution-plan record per run, including selected pipeline, facet snapshot, processor decisions, and reasons.
- [ ] Add a `DOC_PIPELINE_PLAN_ONLY` or equivalent shadow mode that computes and records the plan while executing the legacy-effective processor set.
- [ ] Make reruns able to show the exact prior plan and the exact reasons for each processor decision.

Likely touch points:

- [ ] `ChenWeb/server/api/doc-processing/runtime.go`
- [ ] new plan persistence store under `ChenWeb/server/api/doc-processing/`
- [ ] dashboard/API surfaces that already expose pipeline status

Acceptance:

- [ ] In shadow mode, users can inspect skip/required/useful decisions without changing artifacts produced.
- [ ] Replaying a persisted plan against the same snapshot yields the same decision set.

### Chunk 6 — Benchmark, tests, and rollout evidence

- [ ] Add planner-parity tests proving the default named pipeline reproduces current behavior.
- [ ] Add binding-precedence tests for explicit request, store binding, and default fallback.
- [ ] Add conflict tests for equal-priority incompatible bindings.
- [ ] Add shadow-mode tests proving plan persistence does not alter artifact output.
- [ ] Extend the existing benchmark/report flow enough to compare legacy-effective versus policy-proposed runs for the ventilator pilot corpus.

Minimum verification commands to preserve in the implementation devdoc:

```bash
go test ./server/api/doc-processing/...
go test ./server/api/doc-benchmark/...
mise run semos-p0-benchmark-evidence
```

Acceptance:

- [ ] Default seeded policy shows legacy parity.
- [ ] Ventilator benchmark can report the proposed store-aware differences without requiring ontology runtime implementation.

### Chunk 7 — Documentation and closeout

- [ ] Update the doc-processor capsule/specs for declarative planning and plan visibility.
- [ ] Update the relevant ADR/spec/devdocs with final table names, commands, and rollout notes.
- [ ] Record what remains intentionally deferred to P2 so P1 does not get mistaken for ontology-runtime completion.

Acceptance:

- [ ] A future handoff can distinguish clearly between “policy-plane implemented” and “ontology runtime implemented.”

## Suggested implementation order

1. Chunk 2 — planner parity
2. Chunk 3 — facets
3. Chunk 4 — named pipelines and bindings
4. Chunk 5 — plan persistence and shadow mode
5. Chunk 6 — verification and benchmark evidence
6. Chunk 7 — final documentation

Chunk 1 should happen alongside the first code change and be kept current.

## Risks and controls

| Risk | Why it matters | Control |
|---|---|---|
| Planner drift from current runtime | Could change output before policy work is trustworthy | Seed a legacy-equivalent default and require parity tests first |
| Over-ambitious facet vocabulary | Could drag P1 into ontology modeling too early | Limit P1 facets to deterministic routing facts only |
| Policy storage churn | Could cause rework if the long-term authored-policy model changes | Keep definitions versioned and seedable; do not overfit UI/admin flows in P1 |
| Silent conflicts | Would make pipeline behavior hard to trust | Make conflicts blocking by default and persist exact reasons |
| Confusing P1 with full ontology delivery | Risks scope creep and misaligned expectations | Keep docs explicit that ontology runtime remains P2+ |

## Exit criteria

P1 is complete when all of the following are true:

- [ ] the planner can reconstruct current runtime behavior from declarations;
- [ ] deterministic document facets are available to routing;
- [ ] named pipelines can be selected by explicit request or knowledge-store binding;
- [ ] execution plans are persisted and inspectable;
- [ ] shadow mode proves the system can explain policy decisions without changing runtime output; and
- [ ] the documentation clearly separates P1 policy-plane delivery from later ontology-runtime delivery.
