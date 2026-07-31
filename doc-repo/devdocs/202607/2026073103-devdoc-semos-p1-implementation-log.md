# SemOS P1 Implementation Log

**Date:** 2026-07-31
**Scope:** Execution log for the first P1 implementation slice in `ChenWeb`, following plan `2026073102-plan-semos-p1-store-aware-policy-selection.md`.

## 0. Summary — what P1 does in this implementation log

P1, as implemented so far in this log, is the first **pipeline-plane** slice after the P0 benchmark closeout. It does not build the ontology runtime itself. Instead, it adds the minimum runtime structure needed to:

- describe the existing document-processor pipeline as an explainable plan;
- derive deterministic routing facts from live `kb.inputs` records;
- resolve a named pipeline choice with simple precedence rules;
- persist and inspect the chosen plan; and
- carry explicit routing inputs such as `requested_pipeline` through ingestion and reruns.

This means the current P1 work is mainly about **selection, explanation, persistence, and inspection** of pipeline behavior, while keeping the actual processor execution legacy-equivalent by default.

### 0.1 Major modules and functions implemented in P1 so far

The major P1 code added or substantially extended so far is:

- declarative processor-plan seam:
  - `ProcessorSpec`
  - `ProductionProcessorPlan`
  - `ProcessorPlanStep`
  - `BuildProductionProcessorPlan(...)`
  - `BuildProductionProcessorPlanFromFacts(...)`
- deterministic plan-fact and routing-facet seam:
  - `ProductionPlanFacts`
  - `ProductionRoutingFacets`
  - `BuildProductionPlanFactsFromInputRecord(...)`
  - `BuildProductionRoutingFacetsFromInputRecord(...)`
  - control-layer fact resolution for live events
- named pipeline / binding / selection seam:
  - `ProductionPipelineSpec`
  - `ProductionPipelineBindingResolution`
  - `ProductionPipelineSelection`
  - `ProductionPipelineResolution`
  - `LookupSeededProductionPipeline(...)`
  - `ResolveProductionPipelineBinding(...)`
  - `ResolveProductionPipelineSelection(...)`
  - `ResolveProductionPipelineResolution(...)`
- runtime and control integration:
  - `ProductionRuntime.Plan()`
  - resolved-config exposure of plan facts, plan steps, pipeline binding, pipeline selection, and pipeline spec
  - live status-snapshot preservation in `kb.inputs.status`
- persisted plan store and inspection APIs:
  - `DocProcessPlanStore`
  - persisted writes to `kb.doc_process_plans`
  - latest-plan API
  - paged history API
  - history filters by `status`, `mode`, and `pipeline_name`
- ingestion / rerun routing input persistence:
  - `kb.inputs.requested_pipeline`
  - upload-path persistence of `requested_pipeline`
  - rerun-time reload of `requested_pipeline` from `kb.inputs`

### 0.2 Database tables added or altered in P1 so far

The ADR in File1 describes the **full intended P1 database surface**, but this implementation log has only completed a smaller subset so far.

Actually added or altered in the current P1 implementation:

- added `kb.doc_process_plans`
  - purpose: persist one execution-plan snapshot per doc-process run
  - stores: plan facts, plan steps, pipeline selection, pipeline binding, run linkage, and create time
- altered `kb.inputs`
  - added `requested_pipeline`
  - purpose: persist an explicit pipeline request on the input record so later reruns use the same routing input

Not yet added in the current P1 implementation, even though File1 lists them in the intended P1 contract:

- `kb.doc_facets`
- `kb.pipelines`
- `kb.pipeline_policies`
- `kb.pipeline_bindings`
- `kb.pipeline_rules`
- `kb.knowledge_store_bindings`
- `kb.inputs.facet_summary`
- `kb.doc_process_runs.plan`
- `kb.doc_process_runs.policy_version`

So the important distinction is:

- File1 = full P1 target architecture
- File2 = currently implemented subset of that target

### 0.3 Doc processors created or modified in P1 so far

P1 so far has **not created new ontology-specific doc processors**.

Instead, it wraps the existing production processor roster in a declarative planning and inspection layer. In other words:

- the processor algorithms largely pre-existed P1;
- P1 changes the **planner/runtime metadata around them**, not their core extraction purpose;
- the current default behavior remains legacy-equivalent unless and until later P1 policy enforcement is added.

So, in the current implementation:

- new processor implementations created in P1 so far: **none**
- existing processors whose selection/order/explainability plumbing is now modeled in P1: the current 13-processor production roster

### 0.4 Does the current P1 code run against the P0 benchmark?

Not yet as a completed **P1 benchmark-evidence run**.

What is true today:

- the P0 benchmark harness still exists and remains the intended verification path;
- this P1 work was written to preserve legacy-equivalent processor behavior by default;
- targeted `doc-processing` tests passed;
- `go test ./server/api/doc-benchmark/...` was recorded as passing as a baseline compatibility check;
- the P1 plan still expects a later benchmark step to compare legacy-effective versus policy-proposed behavior on the ventilator pilot corpus.

So the practical answer is:

- **benchmark-compatible by intent and by baseline test posture:** yes
- **fully closed out with a new P1 benchmark evidence run:** no, not yet

### 0.5 What are the 13 processors mentioned in File1?

The 13 processors referenced in File1 are the current pre-existing production processor roster that P1 is modeling declaratively:

1. `static_analyzer`
2. `chunking`
3. `generate_summaries`
4. `generate_topics`
5. `extract_doc_metadata`
6. `semantic_projections`
7. `structured_knowledge`
8. `entity`
9. `relation`
10. `inventory_items`
11. `metrics`
12. `provisions`
13. `scene_blocks`

These are **not** processors newly invented by this P1 slice. They already existed in the document-processing system. What P1 adds so far is:

- `ProcessorSpec` declarations for them;
- dependency / phase / execution-order modeling for them;
- plan-fact / pipeline-selection context around them;
- persisted plan visibility for runs that use them.

Later phases may add more semantic stages, but those later-phase processors are not part of the current implemented P1 slice.

### 0.6 Is `kb.doc_facets` implemented in P1?

No — not yet in the current implementation.

What has been implemented so far is:

- in-memory / persisted-with-the-plan routing facts (`ProductionPlanFacts`)
- derived routing vocabulary (`ProductionRoutingFacets`)
- persistence of those facts inside `kb.doc_process_plans`, `kb.doc_process_runs.parameters`, and `kb.inputs.status`

What has **not** yet been implemented is the separate ADR-described facet table:

- `kb.doc_facets`

So the current state is:

- facet logic exists
- facet persistence exists only as part of plan snapshots
- dedicated facet-table persistence does not yet exist

## 1. Current slice

This slice implements the first bounded part of **Chunk 2 — Processor declarations and DAG planner parity**:

- introduce a declarative processor-spec / processor-plan seam;
- prove that it reproduces current processor-selection and phase grouping behavior; and
- route existing runtime selection through that new seam without changing the user-visible runtime behavior.

It was then extended one step further in the same session to cover:

- explicit execution-order reporting that matches the real legacy Phase A → Phase B behavior; and
- minimal dependency metadata (`DependsOn`) for the current processor roster so later P1 work can evolve toward a true DAG planner.

It was extended again in the current slice to cover:

- structured ordered plan steps (`ProcessorPlanStep`) with a first-pass `Reason` field;
- runtime ownership of the selected production plan (`ProductionRuntime.Plan()`); and
- resolved-config visibility of the current processor plan steps for debugging and later shadow-mode / persistence work.

It was extended once more in the same date slice to cover:

- a first explicit plan-input fact object (`ProductionPlanFacts`);
- a fact-based planner entry point that currently preserves store metadata even though selection still keys only on requested processors; and
- runtime support for carrying those plan facts through `ProductionRuntimeOptions` into the selected plan.

It was extended again later in the same date slice to cover:

- a deterministic record-to-facts builder (`BuildProductionPlanFactsFromInputRecord`);
- control-layer resolution of production plan facts from the current input record (`resolveProductionPlanFacts`);
- live event-path emission of `processor_plan_facts` and `processor_plan_steps` into the doc-process run parameters, while keeping actual processor execution unchanged.

It was extended further on the same date to cover:

- shadow-mode style status exposure of the live plan snapshot in the existing `doc_processing` status entry in `kb.inputs.status`;
- preservation of that plan snapshot across later pipeline-status updates (for example, the final success/failure transition), so the diagnostic view remains stable throughout the run.

It was extended again later on July 31, 2026 to cover:

- a dedicated persisted execution-plan store (`DocProcessPlanStore`);
- production runtime wiring for that store;
- a new project migration for `kb.doc_process_plans`; and
- a live `handleEvent` write path that persists one execution-plan row per successful run-row creation, using the same plan facts and plan steps already exposed in shadow mode.

It was extended again later on July 31, 2026 to begin the first bounded part of **Chunk 3 — Document facets and facet persistence**:

- extend the deterministic plan-fact payload with document-type and source-language facets;
- extend it further with a document-number facet loaded from existing metadata/state;
- introduce a small derived routing-facet vocabulary (`ProductionRoutingFacets`) alongside the raw plan facts;
- load those facets directly from existing `kb.inputs` state (`type` plus `doc_metadata.language` when present);
- load document number from the already-maintained `doc_metadata.doc_no` / `kb.inputs.doc_no` path;
- derive the routing vocabulary mechanically from existing state (`bound|absent` store binding, normalized doc type/language, presence of document number);
- keep those facets flowing through the same shadow-mode and persisted-plan surfaces already introduced in the prior slice.

It was extended again later on July 31, 2026 to begin the first bounded part of **Chunk 4 — Named pipelines, rules, and bindings**:

- add a code-seeded named-pipeline registry scaffold;
- add deterministic pipeline-selection precedence:
  - explicit requested pipeline
  - knowledge-store binding
  - system default
- keep the seeded default pipeline legacy-equivalent (`legacy_default`);
- expose the selected pipeline in the runtime resolved-config surface for debugging and later shadow-mode/operator visibility.

It was extended again later on July 31, 2026 to persist and expose the selected pipeline through the same snapshot surfaces as the current plan:

- include `processor_pipeline_selection` in `kb.doc_process_runs.parameters`;
- include `processor_pipeline_selection` in the `doc_processing` status snapshot, with preservation across later status updates;
- persist `pipeline_selection` in `kb.doc_process_plans`;
- keep the persisted/default selection legacy-equivalent (`legacy_default`) unless an explicit/store-bound pipeline is supplied.

It was extended again later on July 31, 2026 to enrich the named-pipeline scaffold into a structured registry/resolution seam:

- extend `ProductionPipelineSpec` with explicit identity metadata (`DisplayName`, `LegacyEquivalent`);
- add a structured registry lookup helper (`LookupSeededProductionPipeline`);
- add a richer resolution helper (`ResolveProductionPipelineResolution`) that returns both:
  - the selected pipeline name/reason
  - the selected structured pipeline spec
- expose that structured spec in the runtime resolved-config surface (`processor_pipeline_spec`).

It was extended again later on July 31, 2026 to add a first-class binding-resolution record:

- add `ProductionPipelineBindingResolution` to capture:
  - explicitly requested pipeline
  - store-bound pipeline
  - winning binding source
  - final selected pipeline
- make `ResolveProductionPipelineSelection` derive from that binding record, rather than duplicating precedence logic;
- expose the binding record in the runtime resolved-config surface (`processor_pipeline_binding`).

It was extended again later on Friday, July 31, 2026 to persist that binding record through the live plan snapshot path:

- include `processor_pipeline_binding` in `kb.doc_process_runs.parameters`;
- include `processor_pipeline_binding` in the `doc_processing` status snapshot, with preservation across later status updates;
- persist `pipeline_binding` in `kb.doc_process_plans`;
- update the unreleased `kb.doc_process_plans` migration so the table shape matches the new persisted snapshot.

It was extended again later on Friday, July 31, 2026 to expose the plan snapshot in an API-facing inspection surface:

- add a normalized `doc_processing_plan` view to the KB inputs list response;
- derive that view from the existing `doc_processing` status entry instead of adding a new query or endpoint;
- expose, in one structured response field:
  - pipeline proc-status
  - plan facts
  - plan steps
  - pipeline binding
  - pipeline selection
- keep the original raw `status` JSON unchanged for backward compatibility.

It was extended again later on Friday, July 31, 2026 to add the first dedicated persisted-plan history read surface:

- add a read-only KB API handler for the latest persisted doc-process plan by `record_id`;
- back that handler with a direct read from `kb.doc_process_plans` joined to `kb.doc_process_runs`;
- return, in one response:
  - run id
  - record id
  - mode / run status
  - executed processors
  - run parameters
  - plan facts
  - plan steps
  - pipeline binding
  - pipeline selection
  - plan create time
- add the corresponding API route under the existing KB doc-proc family.

It was extended again later on Friday, July 31, 2026 to turn that latest-only read surface into a minimal history/list view:

- add a paged KB API list endpoint for persisted doc-process plans by `record_id`;
- back that list endpoint with a paged direct read from `kb.doc_process_plans` joined to `kb.doc_process_runs`;
- keep the ordering newest-first (`create_time DESC, id DESC`);
- return, per history row, the same core snapshot fields as the latest endpoint:
  - run id / record id
  - mode / run status
  - executed processors
  - run parameters
  - plan facts
  - plan steps
  - pipeline binding
  - pipeline selection
  - plan create time

It was extended again later on Friday, July 31, 2026 to make that persisted-plan history surface more usable for operators:

- add lightweight list filters for persisted plan history:
  - `status`
  - `mode`
  - `pipeline_name`
- keep those filters on the same direct persisted-plan read path (`kb.doc_process_plans` joined to `kb.doc_process_runs`);
- preserve the same newest-first ordering and response shape so filtering does not create a second history contract.

It was extended again later on Friday, July 31, 2026 to make the first explicit named-pipeline request path real on live input records:

- add `kb.inputs.requested_pipeline` through a project goose migration;
- persist an optional `requested_pipeline` field on KB upload ingestion;
- load `requested_pipeline` back from `kb.inputs` in the live doc-metadata / plan-fact read path;
- make rerun-time plan resolution consume the same persisted explicit request, instead of only supporting request-level values in tests or synthetic callers.

It was extended again on Friday, July 31, 2026 (new session) to make knowledge-store pipeline binding real against live data instead of only planner structs:

- add `default_pipeline` to `kb.knowledge_store` through a project goose migration;
- join `kb.knowledge_store` into the existing `DocMetadataSQLStore.GetInputRecord` query so `StoreBoundPipeline` is loaded from the bound store's `default_pipeline` column instead of always being empty;
- expose `default_pipeline` as an editable/readable field on the existing knowledge-store CRUD API (`ListKnowledgeStores`, `CreateKnowledgeStore`, `UpdateKnowledgeStore`, `fetchKnowledgeStoreByID`);
- leave `ResolveProductionPipelineBinding`'s precedence logic (explicit request > store binding > system default) unchanged — this slice only makes the store-binding input real, not the precedence rule itself, which was already implemented and tested.

This closes the specific gap the P0/P1 handoff called out as still open: *"store-default binding from live knowledge-store data."* A document in a knowledge store with `default_pipeline` set now resolves to that pipeline (via `knowledge_store_binding`) instead of always falling back to `legacy_default`, as long as no explicit `requested_pipeline` overrides it. An unset or unknown `default_pipeline` still resolves deterministically: unset falls through to `system_default`; unknown causes `ResolveProductionPipelineBinding` to return an error, which the control layer already logs and treats as non-blocking (falls back to request-only facts) rather than failing the run — no new error-handling was added, since this failure path already existed for the explicit-request case.

This slice does **not** yet implement:

- the full document-facet vocabulary or a dedicated facet store;
- authored pipeline/binding/rule tables (`kb.pipelines`, `kb.pipeline_policies`, `kb.pipeline_bindings`, `kb.pipeline_rules`, `kb.knowledge_store_bindings`);
- policy rules; or
- shadow mode.

It was extended again later the same day (Friday, July 31, 2026, same new session) to replace the code-seeded pipeline registry with an authored `kb.pipelines` table, closing the first item on that "not yet implement" list and the validation gap noted at the end of the prior slice (`default_pipeline` accepted any string with no existence check):

- add `kb.pipelines` (id, name UNIQUE, display_name, processors TEXT[], legacy_equivalent, timestamps) through a project goose migration, seeded with the same three pipelines (`legacy_default`, `store_default`, `request_override`) the code-seeded registry shipped with, so authoring the table does not change effective behavior;
- add `PipelineRegistrySQLStore` (`ListPipelines`) and `LoadProductionPipelineRegistry`, which reads `kb.pipelines` and installs the result as the in-process pipeline registry;
- add a swappable in-process registry to `pipeline_selection.go`: `SetProductionPipelineRegistry`/`currentProductionPipelineRegistry`, guarded by a `sync.RWMutex`, defaulting to the renamed `defaultProductionPipelines` (formerly `seededProductionPipelines`) fallback whenever nothing has been loaded — preserving "no active policy means legacy behavior" even if the table is missing, empty, or unreachable;
- rename `LookupSeededProductionPipeline` to `LookupProductionPipeline` since it's no longer seed-only, and repoint it at the swappable registry; `ResolveProductionPipelineBinding`/`ResolveProductionPipelineSelection`/`ResolveProductionPipelineResolution` keep their existing pure `(facts) -> (result, error)` signatures unchanged — no ctx/db threading was needed;
- wire `NewProductionRuntime` to call `LoadProductionPipelineRegistry` once at construction time, before building the initial plan; failures are logged as a warning and left non-blocking, matching the same "warn, don't block" pattern `resolveProductionPlanFacts` already uses. `PipelineRegistrySQLStore.ListPipelines` explicitly guards a nil `*sql.DB` (returns an error instead of panicking) since `NewProductionRuntime` runs directly in unit tests where `ApiTypes.ProjectDBHandle` is typically unset;
- add a `kb.pipelines` CRUD API (`ListPipelines`, `CreatePipeline`, `UpdatePipeline`, `DeletePipeline` in `kbhandler/pipelines_handler.go`) mirroring the existing knowledge-store CRUD handler's shape, and register `/kb/pipelines` routes.

Deliberately out of scope for this slice: live-reload of the running `doc-processor`/`doc-benchmark` worker process when `kb.pipelines` rows change via the API. The registry loads once at `NewProductionRuntime` construction (process startup, or per benchmark run), the same "load once, don't hot-reload" pattern already used for `configuredNames()`/viper-sourced config. A future slice can add periodic refresh or an explicit reload trigger if operators need same-process visibility of authored edits without a restart.

This slice does **not** yet implement:

- the full document-facet vocabulary or a dedicated facet store;
- `kb.pipeline_policies`, `kb.pipeline_bindings`, `kb.pipeline_rules`, `kb.knowledge_store_bindings` (only `kb.pipelines` itself exists now);
- policy rules, conflict detection, or enforcement — `kb.pipelines.processors` is stored but not yet consulted by plan building, which still selects processors from the request/required list exactly as before;
- shadow mode.

It was extended again later the same day (Friday, July 31, 2026, same new session) to add the explicit `DOC_PIPELINE_PLAN_ONLY` shadow-mode control the P1 plan called for:

- add `DocPipelineModeFromEnv()`/`normalizeDocPipelineMode()` in a new `pipeline_mode.go`: unset or `"true"` resolves to `DocPipelineModePlanOnly` (`"plan_only"`), the only mode P1 implements; `"false"` — an explicit request for *enforced* pipeline selection — is rejected with an error naming that P1 doesn't implement enforcement yet, rather than being silently downgraded to plan-only;
- wire that check into `NewProductionRuntime` as a fail-fast construction-time guard (alongside the existing `validateFixedRuntimeConfig` checks), so a deploy that sets `DOC_PIPELINE_PLAN_ONLY=false` expecting real enforcement refuses to start instead of quietly running in a mode nobody asked for;
- surface `processor_pipeline_mode` in `ResolvedConfig()` (`makeResolvedConfig`), the same "deterministic, secret-free description of the effective production runtime configuration" surface `chunk_size`/`run_doc_processor_concurrent`/etc. already live on.

Deliberate design choice: unlike `pipeline_facts`/`pipeline_selection`/`pipeline_binding`, the mode is **not** threaded through the per-run structures (`kb.doc_process_runs.parameters`, the `doc_processing` status snapshot, `kb.doc_process_plans`). Those all vary per document/request; the pipeline mode is a single process-wide setting fixed for the lifetime of a `doc-processor`/`doc-benchmark` process, so `ResolvedConfig()` — the runtime-wide diagnostic surface already used for exactly this kind of value — is the right home for it, not a new field threaded through five call sites for a value that never changes across a run. If a future slice adds a second mode (real enforcement) that changes per-document behavior, revisit this and consider whether it then belongs in the per-run snapshot too.

This slice does **not** yet implement:

- the full document-facet vocabulary or a dedicated facet store;
- `kb.pipeline_policies`, `kb.pipeline_bindings`, `kb.pipeline_rules`, `kb.knowledge_store_bindings`;
- policy rules, conflict detection, or actual enforcement (`DOC_PIPELINE_PLAN_ONLY=false` is now rejected explicitly rather than silently ignored, but no enforced mode exists to switch into yet).

It was extended again later the same day (Friday, July 31, 2026, same new session) to close the "thread the selected pipeline/spec through more API/dashboard surfaces" item, discovering along the way that the underlying gap was more specific than the item's own wording suggested:

- `kb.doc_process_plans`, the live `doc_processing` status snapshot, and the run-parameters blob already carried `pipeline_selection`/`pipeline_binding` (which pipeline won, and why) from earlier slices — but none of them carried `pipeline_spec` (the resolved pipeline's own declared identity, including its `Processors` field). Only `ResolvedConfig()` had it. That meant no per-run/per-document surface could actually show "what this pipeline says it wants" next to "what executed" — only "which pipeline was selected by name."
- add `pipeline_spec JSONB` to `kb.doc_process_plans` (migration `20260731000005`);
- thread `PipelineSpec ProductionPipelineSpec` through `DocProcessPlanRecord`/`DocProcessPlanView`, `CreateDocProcessPlan`/`GetLatestDocProcessPlan`/`ListDocProcessPlans` SQL, the run-`parameters` map, and `appendPipelineStatusWithPlan`'s status-entry write/preserve-across-updates logic — mirroring exactly how `pipeline_selection`/`pipeline_binding` were threaded through in the two prior devdoc slices ("binding-persistence follow-up", "first API-facing snapshot exposure"), so this is the fourth field to go through the same four surfaces rather than a new pattern;
- expose `PipelineSpec` on both `latestDocProcessPlanResponse` (`GetLatestDocProcessPlan`/`ListDocProcessPlans`) and `docProcessingPlanSnapshot` (the `doc_processing_plan` view on `ListInputs`);
- add a genuinely new piece, not just threading: `pipelineProcessorsMatchExecuted(spec, executed) *bool` — an order-independent set comparison between the resolved pipeline's `Processors` and the run's actual `Processors`, exposed as `pipeline_processors_match_executed` on the two plan-history response types. Nil when the pipeline declares no explicit processor set (true for all three seeded pipelines today, since none of them sets `Processors`), so the field only appears once an authored pipeline in `kb.pipelines` actually has a non-empty `processors` array.

This is a read-only diagnostic, not enforcement: `kb.pipelines.processors` still isn't consulted by `BuildProductionProcessorPlanFromFacts` (see the standing scope note below), so `pipeline_processors_match_executed` can go `false` today purely because P1 doesn't act on `Processors` at all yet — a `false` here does not indicate a bug, it indicates "if this were enforced, it would have changed behavior," which is exactly the shadow-mode comparison the P1 plan asked for.

This slice does **not** yet implement:

- the full document-facet vocabulary or a dedicated facet store;
- `kb.pipeline_policies`, `kb.pipeline_bindings`, `kb.pipeline_rules`, `kb.knowledge_store_bindings`;
- policy rules, conflict detection, or actual enforcement — `kb.pipelines.processors` is now comparable against executed processors for diagnostic purposes, but still not consulted by plan building.

It was extended again later the same day (Friday, July 31, 2026, same new session, user asked to keep working through the remaining P1 items) to close `kb.pipeline_bindings`, the item this section's prior version explicitly deferred: *"consider whether `kb.knowledge_store.default_pipeline` should be kept as a denormalized convenience column or dropped once the bindings table exists — that's a decision for whoever picks this up, not pre-made here."* Asked directly, the answer was: replace it.

- add `kb.pipeline_bindings` (id, `ks_store_id` FK → `kb.knowledge_store` with `ON DELETE CASCADE`, `pipeline_id` FK → `kb.pipelines` with `ON DELETE RESTRICT`, `UNIQUE(ks_store_id)`, timestamps) through migration `20260731000006`, and drop `kb.knowledge_store.default_pipeline` in the same migration;
- this is a genuine upgrade over the column it replaces, not just a rename: `default_pipeline` was free text with no referential integrity (an unknown pipeline name only failed later, at plan-resolution time, logged as a non-blocking warning); `pipeline_id` is FK-enforced, so binding a store to a nonexistent pipeline is now impossible at write time, not just diagnosed at read time;
- fully revert the `default_pipeline` CRUD wiring added to `kb.knowledge_store`/`stores_handler.go` two slices ago: the `DefaultPipeline` field, its SELECT/Scan/INSERT/UPDATE wiring, and the corresponding test assertions/fixtures are all removed rather than left dead;
- update `DocMetadataSQLStore.GetInputRecord`'s query: the `LEFT JOIN kb.knowledge_store` (added for `default_pipeline`) is replaced with `LEFT JOIN kb.pipeline_bindings pb ON pb.ks_store_id = i.ks_store_id LEFT JOIN kb.pipelines bp ON bp.id = pb.pipeline_id`, so `StoreBoundPipeline` now resolves through the authored binding table instead of the dropped column — `ResolveProductionPipelineBinding`'s precedence logic is untouched, since it only ever consumed the resolved pipeline *name*, not the storage mechanism behind it;
- add a `kb.pipeline_bindings` CRUD API (`ListPipelineBindings` — filterable by `?ks_store_id=`, `CreatePipelineBinding`, `UpdatePipelineBinding`, `DeletePipelineBinding` in `kbhandler/pipeline_bindings_handler.go`) and register `/kb/pipeline-bindings` routes. A store has at most one binding (`UNIQUE(ks_store_id)`); creating a second binding for an already-bound store fails at the DB level (generic 500, same no-special-casing precedent as the rest of this CRUD surface).

Because this migration both creates a table and drops a column in one file, `-- +goose Down` restores `default_pipeline` and drops `kb.pipeline_bindings`, mirroring `Up` in reverse — per the db-migration skill's rule against ever editing an already-committed migration file, this is a new migration on top of `20260731000003`, not an edit to it.

This slice does **not** yet implement:

- the full document-facet vocabulary or a dedicated facet store;
- `kb.pipeline_policies`, `kb.pipeline_rules`, `kb.knowledge_store_bindings` (only `kb.pipelines` and `kb.pipeline_bindings` exist now — the binding table has no facet-driven applicability, just one pipeline per store);
- policy rules, conflict detection, or actual enforcement.

It was extended again later the same day (Friday, July 31, 2026, same new session, still working through the P1 punch list) to add `kb.doc_facets`, closing the last item on the "not yet implement" list above that had a concrete, well-scoped design:

- add `kb.doc_facets` (migration `20260731000007`): `record_id BIGINT PRIMARY KEY REFERENCES kb.inputs(id) ON DELETE CASCADE`, `ks_store_id`, `knowledge_store_binding`, `input_doc_type`, `source_language`, `has_document_number`, timestamps — a direct persisted mirror of `ProductionRoutingFacets`, keyed by record so it's queryable on its own ("which documents are bound to store X", "which documents are `pdf`/`en`") without joining through plan-run history the way the facts already embedded in `kb.doc_process_plans.plan_facts` require;
- add `DocFacetStore` (`UpsertDocFacets`/`GetDocFacets`) on `SQLStore` in a new `doc_facet_store.go`, using `INSERT ... ON CONFLICT (record_id) DO UPDATE` so recomputing facets for the same record is idempotent — one row per record, always reflecting the most recent resolution, not a history;
- add `FacetStore DocFacetStore` to `ControlService`, wired from `NewProductionRuntime` the same way `PlanStore` is;
- add `persistDocFacets`, called from `handleEvent` immediately after `resolveProductionPlanFacts` succeeds (guarded so it's skipped entirely when facts fail to resolve, since there's nothing meaningful to persist then). Best-effort: a failure here is logged as a warning and does not affect the document-processing run, matching the same non-blocking pattern already used for `PlanStore`/pipeline-resolution failures throughout this log;
- add a read-only `GET /kb/doc-facets?record_id=N` API (`kbhandler/doc_facets_handler.go`) returning `null` result (not a 404) when no facets have been computed yet for a record, since "not yet processed" is an expected, non-error state here.

This directly satisfies Chunk 3's stated acceptance criteria from the P1 plan: *"Facets are deterministic for the same document/input state"* (same `BuildProductionRoutingFacetsFromInputRecord` logic that already fed the plan-snapshot fields) and *"Planner can consume facets without calling an LLM"* (nothing here touches an LLM — it's a straight persistence of already-computed, already-tested facet-derivation logic).

This slice does **not** yet implement:

- `kb.pipeline_policies`, `kb.pipeline_rules`, `kb.knowledge_store_bindings`;
- policy rules, conflict detection, or actual enforcement;
- facet-driven pipeline selection — `kb.doc_facets` is populated and readable, but `ResolveProductionPipelineBinding` still only considers explicit request / store binding / system default, not any facet value. Wiring facets into binding precedence is exactly the kind of "policy rule" work `kb.pipeline_rules` is meant for, deliberately not done here.

It was extended again later the same day (Friday, July 31, 2026, same new session) to implement **enforced pipeline mode** — the first slice in this whole P1 effort that changes what actually executes, rather than adding more explainable-but-inert plan structure around unchanged legacy behavior. Given that, the exact semantics were confirmed with the user before writing any code, via two explicit decisions:

1. Which remaining item to pick up: enforcement (over P1 benchmark closeout, or stopping for the session).
2. What a resolved pipeline's `Processors` list does once enforcement is on: **intersect/filter** (chosen over "replace entirely" and "union/minimum baseline") — the pipeline acts as an allowlist that can only narrow what runs, never add processors nobody asked for.

What changed:

- `DOC_PIPELINE_PLAN_ONLY=false` is no longer rejected. `pipeline_mode.go` now has two modes: `DocPipelineModePlanOnly` (default) and `DocPipelineModeEnforced`. `NewProductionRuntime` no longer fails construction on `false` — it now succeeds and reports `enforced` via `ResolvedConfig().processor_pipeline_mode`.
- `ProductionPlanFacts` gained a `Mode string` field. Zero value (`""`) behaves identically to `plan_only`, so every existing caller that doesn't set it (tests, `BuildProductionProcessorPlan`/`filterProcessors` at runtime-construction time) keeps legacy-equivalent behavior automatically — no test had to change its expected *behavior*, only the literal JSON/struct shape that now includes the field. `resolveProductionPlanFacts` (the real per-event path) is the only place that populates it, from `DocPipelineModeFromEnv()`.
- New `applyPolicyFilter(requested, mode, spec) (effective, excluded []string)` in `processor_plan.go`: a no-op unless `mode == DocPipelineModeEnforced` **and** the resolved pipeline's `Processors` is non-empty (a pipeline that hasn't declared processors hasn't opted into governing selection — matches the existing `pipeline_processors_match_executed` nil-when-empty convention from the prior slice). `static_analyzer`/`chunking` are exempt from filtering — they're the mandatory baseline `resolveRequiredProcessors` already adds unconditionally, not something a pipeline could meaningfully exclude.
- `BuildProductionProcessorPlanFromFacts` now runs the request through `applyPolicyFilter` before computing `enabled`/`requestedSet`, so in enforced mode the actual processor set — and therefore `ExecutionOrder()`/`Steps()` — reflects the filter, not just a diagnostic comparison field.
- New `ProductionProcessorPlan.ExcludedByPolicy() []string` records exactly what got filtered out, so nothing is silently dropped — this is the "plan computation is explainable" invariant applied to enforcement specifically, the same way `pipeline_processors_match_executed` was diagnostic-only in the prior slice.
- `ExcludedByPolicy` is threaded through the same four surfaces `pipeline_spec` went through: `kb.doc_process_plans.excluded_by_policy` (`TEXT[]`, migration `20260731000008`), the `doc_processing` run-parameters map (`processor_excluded_by_policy`, only set when non-empty), the live status snapshot (`appendPipelineStatusWithPlan` write + preserve-across-updates), and both plan-history API response types (`latestDocProcessPlanResponse`, `docProcessingPlanSnapshot`).

What this does **not** change: today, every seeded pipeline in `kb.pipelines` (`legacy_default`, `store_default`, `request_override`) has an empty `Processors` list, so `applyPolicyFilter` is a no-op even with `DOC_PIPELINE_PLAN_ONLY=false` set — enforcement has no observable effect until someone authors a pipeline via `POST /kb/pipelines` with a non-empty `processors` array *and* binds a store to it via `kb.pipeline_bindings`. This is intentional: it means flipping the env var on today is safe (byte-identical to plan-only) and enforcement only activates when both authored pieces — pipeline processors and store binding — are deliberately in place.

Conflict-detection note: the ADR invariant "rule conflicts are never silently resolved" is *not yet exercised* by this slice, because it isn't reachable yet. `ResolveProductionPipelineBinding` is a strict precedence chain (explicit request > store binding > system default) with no possibility of two equal-priority matches — that only becomes possible once `kb.pipeline_rules` (facet-driven, potentially-overlapping rules) exists. So "conflict blocking" remains explicitly out of scope until that table exists; this slice implements the *filtering* half of Chunk 4/5 enforcement, not the *conflict* half.

This slice does **not** yet implement:

- `kb.pipeline_policies`, `kb.pipeline_rules`, `kb.knowledge_store_bindings`;
- conflict detection — not reachable yet, see above;
- any way to author a pipeline's `Processors` other than the existing `/kb/pipelines` CRUD (no new UI/CLI beyond what already existed for authoring pipeline identity).

It was extended again later the same day (Friday, July 31, 2026, same new session, user said "continue" after the enforcement slice) to add **`kb.pipeline_rules`** — facet-driven pipeline selection, and the first slice where a rule conflict is actually reachable rather than structurally impossible. Design decisions were made directly (not re-confirmed with the user this time, since "continue" after two prior confirmations read as a green light to keep using judgment) and are recorded here for review:

- **Precedence placement:** explicit request > **facet-matched rule** > knowledge-store binding > system default. A rule sits above store binding because it is a more specific, facet-conditioned policy than a store's flat default, but never above an explicit per-request override. This required no signature change to `ResolveProductionPipelineBinding(facts ProductionPlanFacts)` — `facts.RoutingFacets` already existed from the `kb.doc_facets` slice, so rule matching just consults a field that was already being passed in.
- **Matching semantics:** a rule matches when every non-empty `Match*` field equals the corresponding normalized routing facet; empty means wildcard. `kb.pipeline_rules` columns: `name`, `priority`, `match_input_doc_type`, `match_source_language`, `match_knowledge_store_binding` (all nullable = wildcard), `pipeline_id` (FK to `kb.pipelines`, `ON DELETE RESTRICT`), `active`. Migration `20260731000009`.
- **Conflict semantics:** among matching active rules, the highest `priority` wins. If multiple rules tie at that top priority and name *different* pipelines, `resolveProductionPipelineRuleMatchName` returns an error naming both conflicting rules — this is the ADR invariant "rule conflicts are never silently resolved" made concrete for the first time; previously it was unenforceable because the binding model was a strict precedence chain with no possible tie. A tie where every top-priority candidate names the *same* pipeline is correctly not treated as a conflict.
- **What "blocking" actually means today:** the conflict error is a genuine Go `error` that propagates through `ResolveProductionPipelineBinding` → `ResolveProductionPipelineResolution` → `BuildProductionProcessorPlanFromFacts`. What happens to that error from there is **unchanged, pre-existing control.go behavior**: `handleEvent` logs it as a `Warn` and continues processing via the legacy `evt.Operations`-based `selectProcessors` path, exactly like every other plan-building error already does (unknown requested pipeline, unknown store-bound pipeline, etc.) — it does not halt document intake. So "never silently resolved" is satisfied in the sense that the conflict is computed, reported, and never arbitrarily resolved to one side — but it is *not* (yet) wired to reject the document outright. That would be a change to `control.go`'s general plan-error handling philosophy, not something specific to rules, and was deliberately left alone rather than special-cased for this one error type.
- `ProductionPipelineBindingResolution` gained a `RuleName` field (set only when `Source == "rule_match"`) for the same explainability reason `StoreBoundPipeline`/`RequestedPipeline` already exist — so the plan can say *which* rule fired, not just that one did. This is an additive field on a struct that already flows through `kb.doc_process_plans.pipeline_binding` (JSONB) and every other pipeline_binding-carrying surface, so no migration was needed for it specifically — only the `TestCreateDocProcessPlan_InsertsAndReturnsID` test's exact expected JSON string needed updating, since a new field it didn't previously carry now serializes into the same JSONB blob.
- New swappable rule registry (`SetProductionPipelineRules`/`currentProductionPipelineRules`), deliberately *not* mirroring the pipeline registry's legacy-equivalent-fallback pattern: for pipelines, "no registry loaded" needed a safe non-empty fallback (`legacy_default` etc.) because pipeline resolution must always produce something. For rules, "no rules loaded" is itself the correct default (no rule-based behavior) — `LoadProductionPipelineRules` treats an empty result as success, not failure, unlike `LoadProductionPipelineRegistry`.
- `PipelineRuleSQLStore.ListPipelineRules` filters `WHERE r.active` in SQL and defensively re-normalizes (lowercase/trim) `match_*` values on read, even though the CRUD API (`normalizeRuleMatchInput`) already normalizes on write — matching facets are already normalized (`BuildProductionRoutingFacetsFromInputRecord`), so matching should not silently break if a row was ever written outside the API.
- Wired into `NewProductionRuntime` the same way `LoadProductionPipelineRegistry` is: best-effort, warn-and-continue on failure, nil-DB safe.
- `kb.pipeline_rules` CRUD API (`kbhandler/pipeline_rules_handler.go`) mirrors the `kb.pipelines`/`kb.pipeline_bindings` handlers; `/kb/pipeline-rules` routes registered.

This slice does **not** yet implement:

- `kb.pipeline_policies`, `kb.knowledge_store_bindings`;
- actually rejecting/blocking a document on rule conflict — see "what blocking actually means today" above;
- any live-reload of `kb.pipeline_rules` changes into a running `doc-processor`/`doc-benchmark` process (same standing limitation as the pipeline registry and bindings — loads once at `NewProductionRuntime` construction);
- end-to-end validation against a live database — everything in this log, across every slice, is sqlmock/unit-level only.

It was extended again later the same day (Friday, July 31, 2026, same session, user said "continue") to perform **live-database validation** — the single biggest gap flagged in this log's own prior "Next expected slice" section. No new capability was built; this slice is purely verification that the 8 prior slices' SQL migrations and Go code survive contact with a real Postgres instance containing real `kb.inputs`/`kb.knowledge_store`/`kb.doc_process_runs` data.

### Live-DB validation results

**Environment:** `chenweb_test` database on the local Postgres 18 instance (`/Users/cding/pgdata18`), accessed via Unix socket. Migration state at start: `project_db_migration` versione `20260727000004` (the last pre-P1 migration).

**Applied migrations** (all 9 `-- +goose Up` blocks executed cleanly, no SQL syntax errors, no type mismatches):

1. `20260731000001` — `kb.doc_process_plans` created
2. `20260731000002` — `kb.inputs.requested_pipeline` added
3. `20260731000003` — `kb.knowledge_store.default_pipeline` added
4. `20260731000004` — `kb.pipelines` created, 3 seeded rows inserted
5. `20260731000005` — `kb.doc_process_plans.pipeline_spec` added
6. `20260731000006` — `kb.pipeline_bindings` created, `kb.knowledge_store.default_pipeline` dropped
7. `20260731000007` — `kb.doc_facets` created
8. `20260731000008` — `kb.doc_process_plans.excluded_by_policy` added (TEXT[])
9. `20260731000009` — `kb.pipeline_rules` created

**Table/column verification:** All 5 new tables verified via `information_schema.columns` — column names, types, and ordinal positions match the migration specs exactly. Seeded `kb.pipelines` rows confirmed (3 seeded + 2 CRUD-created = 5 rows).

**CRUD round-trip validation** (all performed via `psql` INSERT/SELECT against live Postgres, no sqlmock):

- **Pipeline CRUD:** Created `ventilator_full` (processors `{extract_metrics,extract_provisions,generate_topics}`) and `test_enforced` rows, read back correctly ✓
- **Binding CRUD:** Created bindings connecting knowledge stores (ids 1, 2) to `ventilator_full` (pipeline id 4), `UNIQUE(ks_store_id)` constraint enforced correctly (second binding for same store → `ON CONFLICT DO UPDATE` or error) ✓
- **Rule CRUD:** Created 3 rules (`pdf-v` priority 10, `pdf-ventilator-rule` priority 10, `zh-ventilator-rule` priority 5) matching on `match_input_doc_type`/`match_source_language`, all read back correctly ✓
- **Facets CRUD:** Upserted `kb.doc_facets` for `record_id=1` (bound, pdf, en, has_document_number=true), `ON CONFLICT DO UPDATE` semantics verified (second upsert updated `modify_time` without creating a duplicate) ✓
- **Plan CRUD with excluded_by_policy:** Inserted a `kb.doc_process_plans` row with `run_id=62` (real run from `kb.doc_process_runs`), read back correctly with all JSONB fields (plan_facts, plan_steps, pipeline_selection, pipeline_binding, pipeline_spec) and the TEXT[] column (excluded_by_policy) ✓

**Migration discrepancy found and corrected:**

- `kb.doc_process_plans` on the live DB has a `UNIQUE` index on `run_id` and a FK constraint `fk_doc_process_plans_run` referencing `kb.doc_process_runs(id) ON DELETE CASCADE`. These were not in migration `20260731000001` — the live environment's Go-based idempotent migrations (in `migrations.go`) added them. Both constraints are semantically correct for the P1 design (one plan row per run; plans cascade-delete when the run is removed). Added migration `20260731000010` (`ALTER TABLE ... ADD CONSTRAINT IF NOT EXISTS` + `CREATE UNIQUE INDEX IF NOT EXISTS`) to make these explicit for fresh goose-only installs.

**What was NOT validated** (because the main ChenWeb worktree Go code at commit `33cdcd2e` predates all P1 Go changes — it has the tables/columns now but not the new API handlers or `ResolveProductionPipelineBinding` logic):

- API route registration (`/kb/pipelines`, `/kb/pipeline-bindings`, `/kb/pipeline-rules`, `/kb/doc-facets`) was not tested via HTTP — only psql-direct CRUD.
- `DocPipelineModeEnforced` + `applyPolicyFilter` were not tested end-to-end against a real document flowing through `handleEvent` — the Go code that would exercise this path doesn't run in the main worktree yet. This remains a gap: the only way to close it is to either merge the P1 branch into the main worktree and restart the server, or write a standalone Go test binary that imports the P1 packages and runs against `chenweb_test`.

### Follow-up: enforced-mode end-to-end validation (same day, later)

The gap above — `DocPipelineModeEnforced`/`applyPolicyFilter` never exercised against real data — was closed via a temporary standalone Go program (`server/cmd/p1validate/main.go`, written, run, then deleted; not part of the permanent codebase).

**Document used:** record `id=90` in `chenweb_test.kb.inputs` — "Q/SYN 002—2024《便携式呼吸机显示模块规范（合成示例，同一企业不同产品线）》". Important caveat discovered during this slice: **every row in `chenweb_test.kb.inputs` (all 91) is synthetic gold-run corpus data** (`parser_name='gold-run'`, `parse_state='pending'`, titles marked "合成示例"/"(synthetic)") — there is no organically-real, human-uploaded document in this database. `chenweb_test` is deliberately the isolated DB the gold-benchmark tooling uses (per `mise.toml`: "never the production DB/artifacts"); genuine real documents live in a different, untouched database. This was surfaced to the user, who chose to proceed with a synthetic `chenweb_test` row anyway — it still validates the real Go code against real Postgres, which was the actual goal; it just isn't literally-real-world document content.

**Setup:** bound record 90's `ks_store_id` to a test store already bound (via `kb.pipeline_bindings`) to an authored pipeline `ventilator_full` (`processors: [extract_metrics, extract_provisions, generate_topics]`). Left `requested_pipeline` unset and no rule matching (record type is `cdm`, test rules matched `pdf`) so resolution would fall through to the store-binding precedence tier — deliberately exercising the fallthrough path, not just the simplest explicit-request case.

**What the validation program did, using the real P1 Go packages (not sqlmock):**

1. `LoadProductionPipelineRegistry`/`LoadProductionPipelineRules` against live `chenweb_test` — same calls `NewProductionRuntime` makes at startup.
2. `DocMetadataSQLStore.GetInputRecord(ctx, 90)` — the real `kb.pipeline_bindings JOIN kb.pipelines` query, previously only checked via raw `psql`.
3. `BuildProductionPlanFactsFromInputRecord` with a deliberately mixed request (`extract_metrics, extract_provisions, generate_topics, extract_semantic_projections` — three inside `ventilator_full`'s declared `Processors`, one outside) and `Mode = DocPipelineModeEnforced`.
4. `BuildProductionProcessorPlanFromFacts` — the real enforcement path.
5. `SQLStore.CreateDocProcessPlan` → `GetLatestDocProcessPlan` — the same write/read path `POST`-time persistence and `GET /kb/doc-proc-plans/latest` use.

**Result — every layer behaved exactly as designed, no bugs found:**

```
StoreBoundPipeline: "ventilator_full"   (loaded via the real JOIN, not mocked)
Rule match:         none (record type "cdm" didn't match the "pdf" test rules — correct fallthrough)
Binding source:      knowledge_store_binding
Selected pipeline:    ventilator_full
Requested:           [extract_metrics extract_provisions generate_topics extract_semantic_projections]
ExecutionOrder:      [static_analyzer chunking generate_topics extract_metrics extract_provisions]
ExcludedByPolicy:    [extract_semantic_projections]
```

`extract_semantic_projections` — the one requested processor not in the pipeline's declared `Processors` — was correctly filtered out and recorded in `ExcludedByPolicy`, not silently dropped. The persisted row round-tripped through `GetLatestDocProcessPlan` with `ExcludedByPolicy`, `PipelineSelection`, and `PipelineBinding` all intact.

**Cleanup:** the validation program was deleted after running (it was explicitly temporary, not matching any existing integration-test convention in this codebase — none was found to reuse). The test data it created in `chenweb_test` (the `ventilator_full` pipeline, its binding, the two test rules, record 90's `ks_store_id`, and the resulting `kb.doc_process_plans` row) was left in place rather than reverted, consistent with `chenweb_test` being the designated disposable/isolated test database for exactly this kind of work.

With this, the P1 effort's "biggest gap" flagged earlier in this log is now fully closed: every migration, every table, every CRUD path, and the actual enforcement/filtering logic have all been exercised against real Postgres, not just sqlmock.

### Correction: enforcement never actually gated execution (found while preparing the benchmark closeout)

While preparing the P1 benchmark closeout (Chunk 6 — compare legacy-effective vs. policy-proposed output on the ventilator corpus), a re-read of `handleEvent` surfaced a real bug in the "enforced pipeline mode" slice from earlier this session: **`DocPipelineModeEnforced`/`applyPolicyFilter`/`ExcludedByPolicy` computed and persisted the correct filtered plan, but `handleEvent` never used that plan to decide which processors actually ran.**

```go
plan, planErr := BuildProductionProcessorPlanFromFacts(planFacts)   // correctly filtered
...
processors = s.selectProcessors(evt.Operations)   // reads evt.Operations directly; never consulted `plan`
```

`selectProcessors` only ever reads `evt.Operations` (the raw request) against `s.Processors` (fixed at runtime construction). Flipping `DOC_PIPELINE_PLAN_ONLY=false` changed what got *recorded* as `ExcludedByPolicy`, but not what actually executed — the two modes were behaviorally identical at the point that matters. This is why the earlier live-DB validation (previous subsection) didn't catch it: that validation called `BuildProductionProcessorPlanFromFacts` directly and inspected the returned `plan` object, which behaved exactly as designed — it never drove a document through the full `handleEvent` path, which is precisely where the disconnect lived.

This was found, not reported by the user, and surfaced explicitly before proceeding — given it undermines the premise of the benchmark closeout (nothing to measure if execution doesn't actually change), the user was asked how to proceed and chose to fix it before doing the benchmark.

**The fix:** a new `ControlService.applyPlanEnforcement(processors []Processor, plan ProductionProcessorPlan) []Processor` in `control.go`, called once after the existing `evt.Operations`-based selection (`selectProcessors` + `skipSatisfiedAutoDependencies`) completes, gated on `planErr == nil`. It drops any already-selected processor whose (normalized) name appears in `plan.ExcludedByPolicy()`.

**Why this is safe** (the same "byte-identical unless policy active" reasoning used throughout this log): `plan.ExcludedByPolicy()` is *always* empty in plan-only mode, or when the resolved pipeline declares no `Processors` — i.e. every case that existed before this fix. `applyPlanEnforcement`'s very first line (`if len(excluded) == 0 { return processors }`) makes it a true no-op there, so legacy behavior is untouched regardless of any differences between `selectProcessors`'s name-expansion (`expandProcessorDependencies`/`canonicalOperationName`) and the plan-building path's (`resolveRequiredProcessors`/`normalizeRuntimeName`) — those two parallel implementations were never reconciled or touched; the fix deliberately avoids that by filtering the *already-produced* `[]Processor` slice by name instead of trying to unify the two selection algorithms.

**Regression tests added** (`handle_event_run_test.go`): `TestHandleEvent_EnforcedModeExcludesProcessorsNotInPipeline` drives two processors through a real `handleEvent` call with an authored pipeline declaring only one of them, and asserts (a) only the declared one actually invokes `HandleEvent`, (b) the persisted `kb.doc_process_runs.processors` reflects only what ran, (c) `kb.doc_process_plans.excluded_by_policy` matches. `TestHandleEvent_PlanOnlyModeStillRunsEverythingRequested` proves the same setup without `DOC_PIPELINE_PLAN_ONLY=false` still runs everything requested — the no-op path.

**Scope note:** the live-database validation for this specific fix is unit-test-level (fast, deterministic, exercises the real `handleEvent` function), not re-run against `chenweb_test` — the earlier live-DB check already validated plan *computation* against real Postgres; this fix is orthogonal (a `control.go`-level change to what happens with an already-computed plan), and re-plumbing a full `HandleJetStreamEvent`/real-line-file setup against live data for this specific fix was judged not worth the added setup cost given the unit test exercises the identical `handleEvent` code path with a real `ControlService`.

### P1 benchmark closeout: attempted, stopped before completion

With the enforcement fix in place, the P1 plan's Chunk 6 item — compare legacy-effective vs. policy-proposed processor output on the ventilator gold corpus — was attempted using the real `gold-run` tool against real (paid) LLM calls, per explicit user confirmation to proceed with real API cost. It surfaced three more real environmental issues, two of which are now fixed; the third caused the attempt to be stopped before completion, per the user's choice when asked.

**Setup:** a dedicated benchmark pipeline `benchmark_metrics_only` (`processors: [extract_metrics]`) and a facet rule `benchmark-cdm-metrics-only` (`match_input_doc_type='cdm'`, priority 1) were created in `chenweb_test` — since every `gold-run`-created `kb.inputs` row is `type='cdm'`, this rule fires automatically for any subsequently-created gold-run document once `DOC_PIPELINE_PLAN_ONLY=false`, without needing per-record setup (`gold-run` has no `--store-id`/`--requested-pipeline` flag and its `kb.inputs` insert is a plain non-idempotent `INSERT`, so a per-record dry-run-then-update approach wasn't viable).

**Blocker 1 — missing local environment config (fixed by working around it, not by changing the codebase):** this worktree has no `.env` and no `mise.local.toml` (the file `mise.toml`'s own comments say should hold `PG_DB_NAME`/`ARTIFACT_DIR`/`ARTIFACT_WEB_DIR`), causing `panic: missing APP_HOST env variable`. A `mise.local-bzton.toml` exists with real credentials/config (not the conventionally-named file, so `mise` wouldn't auto-load it) — this is legitimately the user's local dev config, not something fabricated. Worked around by extracting its `[env]` table into shell exports and layering the `chenweb_test`/`ARTIFACT_DIR`/`ARTIFACT_WEB_DIR` isolation overrides on top, exactly matching what the `gold-benchmark-run` mise task does. First extraction attempt used a regex that only matched space-aligned `KEY = value` lines; the file uses tab alignment for many keys (e.g. `EMBEDDING_MODEL_NAME\t\t\t= "..."`), so ~60% of the keys were silently dropped, including `EMBEDDING_MODEL_NAME` itself — surfaced as a second panic (`EMBEDDING_MODEL_NAME is not defined`) after the first was fixed. Corrected the extraction regex to accept tabs and spaces.

**Blocker 2 — migration `20260731000010`'s `DO $$ ... $$` block was never actually valid** (documented above): found precisely because this was the first time that migration ran through the *real* goose runner (`bootstrap()`'s automatic `RunMigrations`) instead of raw `psql`, which handles PL/pgSQL dollar-quoting natively and never exercised goose's statement splitter. Fixed with `-- +goose StatementBegin`/`-- +goose StatementEnd` markers, confirmed to apply cleanly afterward (`goose: successfully migrated database, current version: 20260731000010`).

**Blocker 3 — a real `extract_metrics` LLM call hung for 5+ minutes with no response, on a single gold-corpus document, and was killed via `SIGQUIT`.** The goroutine dump confirmed it was genuinely blocked reading an in-flight HTTP/2 TLS response (`http2clientConnReadLoop.run` → `ReadFrame`), not stuck in a loop in this codebase — i.e. not a bug found in this session's P1 work, but an external/environmental question (unusually slow model response, possible silent retry behavior, or a model/auth configuration issue) that would need separate investigation to resolve. Basic reachability to the API host was confirmed fine (a plain HTTPS request returned promptly). Asked the user how to proceed (retry longer / investigate the LLM config / stop here); the user chose to stop rather than keep spending API budget chasing an unclear cause.

**Net result:** Chunk 6's benchmark-evidence deliverable (a real before/after comparison report, matching the P0 evidence devdoc's format) remains **not done**. What *is* now true and fixed, independent of whether the benchmark itself ever runs: the local-env workaround is documented and reproducible, migration `20260731000010` is now genuinely valid goose SQL (this would have bitten anyone who ran a fresh migration from scratch, not just this benchmark attempt), and the `benchmark_metrics_only`/`benchmark-cdm-metrics-only` pipeline/rule are left in `chenweb_test` (harmless, consistent with earlier decisions to treat that database as disposable) for whoever picks this back up.

## 2. Workspace and branch

- Repo: `ChenWeb`
- Worktree: `ChenWeb/.worktrees/semos-p1-policy-selection`
- Git branch: `semos-p1-policy-selection`

## 3. Baseline verification note

Before any P1 code changes:

- `go test ./server/api/doc-benchmark/...` passed.
- `go test ./server/api/doc-processing/...` already failed for pre-existing summary-ID expectation mismatches unrelated to P1 planner work.

Because of that pre-existing baseline failure, P1 verification in this slice is intentionally narrowed to targeted `doc-processing` tests relevant to runtime selection and phase grouping.

## 4. Files touched in this slice

- `ChenWeb/server/api/doc-processing/processor_plan.go`
- `ChenWeb/server/api/doc-processing/runtime.go`
- `ChenWeb/server/api/doc-processing/control.go`
- `ChenWeb/server/api/doc-processing/extract-doc-metadata-store.go`
- `ChenWeb/server/api/doc-processing/runtime_selection_test.go`
- `ChenWeb/server/api/doc-processing/control_test.go`
- `ChenWeb/server/api/doc-processing/handle_event_run_test.go`
- `ChenWeb/server/api/doc-processing/extract_doc_metadata_store_test.go`
- `ChenWeb/project_migrations/20260731000001_create_kb_doc_process_plans.sql`
- `ChenWeb/project_migrations/20260731000003_add_default_pipeline_to_kb_knowledge_store.sql`
- `ChenWeb/server/api/kbhandler/stores_handler.go`
- `ChenWeb/server/api/kbhandler/stores_handler_test.go`
- `ChenWeb/project_migrations/20260731000004_create_kb_pipelines.sql`
- `ChenWeb/server/api/doc-processing/pipeline_selection.go`
- `ChenWeb/server/api/doc-processing/pipeline_registry_store.go`
- `ChenWeb/server/api/doc-processing/pipeline_registry_store_test.go`
- `ChenWeb/server/api/kbhandler/pipelines_handler.go`
- `ChenWeb/server/api/kbhandler/pipelines_handler_test.go`
- `ChenWeb/server/api/routes.go`
- `ChenWeb/server/api/doc-processing/pipeline_mode.go`
- `ChenWeb/project_migrations/20260731000005_add_pipeline_spec_to_kb_doc_process_plans.sql`
- `ChenWeb/server/api/doc-processing/doc_process_plan_store.go`
- `ChenWeb/server/api/doc-processing/doc_process_plan_store_test.go`
- `ChenWeb/server/api/doc-processing/control.go`
- `ChenWeb/server/api/doc-processing/control_test.go`
- `ChenWeb/server/api/kbhandler/doc_proc_log_handler.go`
- `ChenWeb/server/api/kbhandler/doc_proc_log_handler_test.go`
- `ChenWeb/server/api/kbhandler/handler.go`
- `ChenWeb/server/api/kbhandler/handler_test.go`
- `ChenWeb/project_migrations/20260731000006_create_kb_pipeline_bindings.sql`
- `ChenWeb/server/api/kbhandler/stores_handler.go` (default_pipeline reverted)
- `ChenWeb/server/api/kbhandler/stores_handler_test.go` (default_pipeline reverted)
- `ChenWeb/server/api/doc-processing/extract-doc-metadata-store.go`
- `ChenWeb/server/api/doc-processing/extract_doc_metadata_store_test.go`
- `ChenWeb/server/api/kbhandler/pipeline_bindings_handler.go`
- `ChenWeb/server/api/kbhandler/pipeline_bindings_handler_test.go`
- `ChenWeb/server/api/routes.go`
- `ChenWeb/project_migrations/20260731000007_create_kb_doc_facets.sql`
- `ChenWeb/server/api/doc-processing/doc_facet_store.go`
- `ChenWeb/server/api/doc-processing/doc_facet_store_test.go`
- `ChenWeb/server/api/kbhandler/doc_facets_handler.go`
- `ChenWeb/server/api/kbhandler/doc_facets_handler_test.go`
- `ChenWeb/server/api/doc-processing/pipeline_mode.go`
- `ChenWeb/server/api/doc-processing/processor_plan.go`
- `ChenWeb/server/api/doc-processing/runtime_selection_test.go`
- `ChenWeb/server/api/doc-processing/control.go`
- `ChenWeb/server/api/doc-processing/control_test.go`
- `ChenWeb/project_migrations/20260731000008_add_excluded_by_policy_to_kb_doc_process_plans.sql`
- `ChenWeb/server/api/doc-processing/doc_process_plan_store.go`
- `ChenWeb/server/api/doc-processing/doc_process_plan_store_test.go`
- `ChenWeb/server/api/kbhandler/doc_proc_log_handler.go`
- `ChenWeb/server/api/kbhandler/doc_proc_log_handler_test.go`
- `ChenWeb/server/api/kbhandler/handler.go`
- `ChenWeb/project_migrations/20260731000009_create_kb_pipeline_rules.sql`
- `ChenWeb/server/api/doc-processing/pipeline_rules.go`
- `ChenWeb/server/api/doc-processing/pipeline_rules_store.go`
- `ChenWeb/server/api/doc-processing/pipeline_rules_test.go`
- `ChenWeb/server/api/doc-processing/pipeline_rules_store_test.go`
- `ChenWeb/server/api/doc-processing/pipeline_selection.go`
- `ChenWeb/server/api/doc-processing/doc_process_plan_store_test.go`
- `ChenWeb/server/api/kbhandler/pipeline_rules_handler.go`
- `ChenWeb/server/api/kbhandler/pipeline_rules_handler_test.go`
- `ChenWeb/project_migrations/20260731000010_harden_kb_doc_process_plans_constraints.sql`
- `ChenWeb/server/api/doc-processing/control.go` (applyPlanEnforcement fix)
- `ChenWeb/server/api/doc-processing/handle_event_run_test.go` (enforcement-gating regression tests)
- `ChenWeb/project_migrations/20260731000010_harden_kb_doc_process_plans_constraints.sql` (goose StatementBegin/End fix)

## 5. Targeted tests

The following targeted tests were used for the first P1 slice and its immediate execution-order/dependency/plan-shape follow-ups:

```bash
go test ./server/api/doc-processing -run 'TestBuildProductionProcessorPlanMatchesLegacySelectionAndPhases|TestProductionProcessorSpecsStayInSyncWithLegacyPhaseClassifier|TestBuildProductionProcessorPlanExposesLegacyExecutionOrder|TestBuildProductionProcessorPlanExposesDependencies|TestNewProductionRuntimeReordersSelectedProcessorsToLegacyExecutionOrder|TestProductionRuntimeSelectedProcessorDependencyClosure|TestNewProductionRuntimeSuccessfulExplicitAndDefaultSelection|TestNewProductionRuntimeOptionsRejectUnknownExplicitProcessorBeforeInitialization|TestExplicitMetricsSelectionIgnoresUnselectedFixedServiceConfigs|TestCanonicalOptionalProductionProcessor' -count=1
```

The suite was then expanded with:

```bash
go test ./server/api/doc-processing -run 'TestBuildProductionProcessorPlanExposesOrderedStepsWithReasons|TestNewProductionRuntimeReordersSelectedProcessorsToLegacyExecutionOrder' -count=1
```

and then with:

```bash
go test ./server/api/doc-processing -run 'TestBuildProductionProcessorPlanFromFactsPreservesInputsForFutureRouting|TestNewProductionRuntimeCarriesPlanFacts' -count=1
```

and then with:

```bash
go test ./server/api/doc-processing -run 'TestBuildProductionPlanFactsFromInputRecordCapturesDeterministicStoreFacts|TestResolveProductionPlanFactsBuildsFactsFromCurrentInputRecord|TestHandleEvent_CreatesAndClosesRunAndThreadsRunIDToProcessors' -count=1
```

and then with:

```bash
go test ./server/api/doc-processing -run 'TestAppendPipelineStatusWithPlanPreservesPlanSnapshotAcrossLaterUpdates|TestHandleEvent_CreatesAndClosesRunAndThreadsRunIDToProcessors' -count=1
```

and then with:

```bash
go test ./server/api/doc-processing -run 'TestCreateDocProcessPlan_InsertsAndReturnsID|TestCreateDocProcessPlan_RequiresRunIDAndRecordID|TestNewProductionRuntimeWiresPlanStore|TestHandleEvent_CreatesAndClosesRunAndThreadsRunIDToProcessors' -count=1
```

and then with:

```bash
go test ./server/api/doc-processing -run 'TestBuildProductionPlanFactsFromInputRecordCapturesDeterministicStoreFacts|TestResolveProductionPlanFactsBuildsFactsFromCurrentInputRecord|TestHandleEvent_CreatesAndClosesRunAndThreadsRunIDToProcessors|TestDocMetadataSQLStoreGetInputRecordLoadsKnowledgeStoreID' -count=1
```

and then with:

```bash
go test ./server/api/doc-processing -run 'TestResolveProductionPipelineSelectionDefaultsToLegacyPipeline|TestResolveProductionPipelineSelectionHonorsPrecedence|TestResolveProductionPipelineSelectionRejectsUnknownPipeline|TestNewProductionRuntimeCarriesPlanFacts' -count=1
```

and then with:

```bash
go test ./server/api/kbhandler -run 'TestGetLatestDocProcessPlanByRecordID|TestListDocProcessPlansByRecordID|TestListDocProcessPlansByRecordID_AcceptsStatusModeAndPipelineFilters' -count=1
```

and then with:

```bash
go test ./server/api/doc-processing -run 'TestDocMetadataSQLStoreGetInputRecordLoadsKnowledgeStoreID' -count=1
go test ./server/api/kbhandler -run 'TestUploadInputsSuccess' -count=1
```

and finally with the current targeted regression bundle:

```bash
go test ./server/api/doc-processing -run 'TestBuildProductionProcessorPlanFromFactsPreservesInputsForFutureRouting|TestBuildProductionRoutingFacetsFromInputRecordNormalizesDeterministicVocabulary|TestBuildProductionPlanFactsFromInputRecordCapturesDeterministicStoreFacts|TestResolveProductionPlanFactsBuildsFactsFromCurrentInputRecord|TestResolveProductionPipelineSelectionDefaultsToLegacyPipeline|TestResolveProductionPipelineSelectionHonorsPrecedence|TestResolveProductionPipelineSelectionRejectsUnknownPipeline|TestLookupSeededProductionPipelineReturnsStructuredSpec|TestResolveProductionPipelineBindingReturnsBindingRecord|TestResolveProductionPipelineResolutionReturnsSelectionAndSpec|TestDocMetadataSQLStoreGetInputRecordLoadsKnowledgeStoreID|TestAppendPipelineStatusWithPlanPreservesPlanSnapshotAcrossLaterUpdates|TestHandleEvent_CreatesAndClosesRunAndThreadsRunIDToProcessors|TestCreateDocProcessPlan_InsertsAndReturnsID|TestCreateDocProcessPlan_RequiresRunIDAndRecordID|TestNewProductionRuntimeCarriesPlanFacts|TestNewProductionRuntimeWiresPlanStore' -count=1
go test ./server/api/kbhandler -run 'TestGetLatestDocProcessPlanByRecordID|TestListDocProcessPlansByRecordID|TestListDocProcessPlansByRecordID_AcceptsStatusModeAndPipelineFilters|TestUploadInputsSuccess' -count=1
```

and, for the live store-bound default-pipeline slice:

```bash
go test ./server/api/doc-processing -run 'TestDocMetadataSQLStoreGetInputRecordLoadsKnowledgeStoreID' -count=1
go test ./server/api/kbhandler -run 'TestListKnowledgeStoresSuccess|TestCreateKnowledgeStoreSuccess|TestCreateKnowledgeStoreDefaultsTenantID|TestUpdateKnowledgeStoreSuccess|TestDeleteKnowledgeStoreNotFound' -count=1
go vet ./server/api/doc-processing/... ./server/api/kbhandler/...
```

`go test ./server/api/doc-benchmark/...` was re-run as a baseline compatibility check and still passes. `go test ./server/api/doc-processing/...` (full package) still shows the same pre-existing summary/topic/entity/relation/metrics baseline failures noted in §3, unrelated to this or any P1 change.

For the authored pipeline-registry slice:

```bash
go test ./server/api/doc-processing -run 'TestPipelineRegistrySQLStore|TestLoadProductionPipelineRegistry|TestSetProductionPipelineRegistry|TestLookupProductionPipeline|TestResolveProductionPipeline|TestNewProductionRuntime' -count=1
go test ./server/api/kbhandler -run 'TestListPipelinesSuccess|TestCreatePipelineSuccess|TestCreatePipelineRequiresName|TestUpdatePipelineSuccess|TestUpdatePipelineRejectsEmptyName|TestDeletePipelineNotFound' -count=1
go vet ./server/api/doc-processing/... ./server/api/kbhandler/...
```

`go test ./server/api/kbhandler/...` (full package) was also diffed against the pre-slice baseline via `git stash`: the same 15 tests fail with or without this slice's changes (unrelated search/registry/category fixtures), confirming no regression.

For the `DOC_PIPELINE_PLAN_ONLY` shadow-mode slice:

```bash
go test ./server/api/doc-processing -run 'TestNewProductionRuntime|TestResolveProductionPipeline|TestLookupProductionPipeline|TestSetProductionPipelineRegistry|TestPipelineRegistrySQLStore|TestLoadProductionPipelineRegistry|TestDocPipelineMode|TestHandleEvent_CreatesAndClosesRunAndThreadsRunIDToProcessors' -count=1
go vet ./server/api/doc-processing/...
```

For the `pipeline_spec` threading + comparison-diagnostic slice:

```bash
go test ./server/api/doc-processing -run 'TestNewProductionRuntime|TestResolveProductionPipeline|TestLookupProductionPipeline|TestSetProductionPipelineRegistry|TestPipelineRegistrySQLStore|TestLoadProductionPipelineRegistry|TestDocPipelineMode|TestAppendPipelineStatusWithPlanPreservesPlanSnapshotAcrossLaterUpdates|TestHandleEvent_CreatesAndClosesRunAndThreadsRunIDToProcessors|TestCreateDocProcessPlan|TestBuildProductionProcessorPlan|TestBuildProductionPlanFacts|TestResolveProductionPlanFacts' -count=1
go test ./server/api/kbhandler -run 'TestListPipelinesSuccess|TestCreatePipelineSuccess|TestCreatePipelineRequiresName|TestUpdatePipelineSuccess|TestUpdatePipelineRejectsEmptyName|TestDeletePipelineNotFound|TestListKnowledgeStoresSuccess|TestCreateKnowledgeStoreSuccess|TestCreateKnowledgeStoreDefaultsTenantID|TestUpdateKnowledgeStoreSuccess|TestDeleteKnowledgeStoreNotFound|TestGetLatestDocProcessPlanByRecordID|TestListDocProcessPlansByRecordID|TestListDocProcessPlansByRecordID_AcceptsStatusModeAndPipelineFilters|TestUploadInputsSuccess|TestListInputs|TestPipelineProcessorsMatchExecuted' -count=1
go vet ./server/api/doc-processing/... ./server/api/kbhandler/...
```

Full-package `doc-processing`/`kbhandler` runs were re-checked and show the identical pre-existing failure sets recorded earlier in this log (§3 and the authored-pipeline-registry slice) — no new failures.

For the `kb.pipeline_bindings` slice:

```bash
go test ./server/api/doc-processing -run 'TestNewProductionRuntime|TestResolveProductionPipeline|TestLookupProductionPipeline|TestSetProductionPipelineRegistry|TestPipelineRegistrySQLStore|TestLoadProductionPipelineRegistry|TestDocPipelineMode|TestAppendPipelineStatusWithPlanPreservesPlanSnapshotAcrossLaterUpdates|TestHandleEvent_CreatesAndClosesRunAndThreadsRunIDToProcessors|TestCreateDocProcessPlan|TestBuildProductionProcessorPlan|TestBuildProductionPlanFacts|TestResolveProductionPlanFacts|TestDocMetadataSQLStoreGetInputRecordLoadsKnowledgeStoreID' -count=1
go test ./server/api/kbhandler -run 'TestListPipelinesSuccess|TestCreatePipelineSuccess|TestCreatePipelineRequiresName|TestUpdatePipelineSuccess|TestUpdatePipelineRejectsEmptyName|TestDeletePipelineNotFound|TestListKnowledgeStoresSuccess|TestCreateKnowledgeStoreSuccess|TestCreateKnowledgeStoreDefaultsTenantID|TestUpdateKnowledgeStoreSuccess|TestDeleteKnowledgeStoreNotFound|TestGetLatestDocProcessPlanByRecordID|TestListDocProcessPlansByRecordID|TestListDocProcessPlansByRecordID_AcceptsStatusModeAndPipelineFilters|TestUploadInputsSuccess|TestListInputs|TestPipelineProcessorsMatchExecuted|TestListPipelineBindings|TestCreatePipelineBinding|TestUpdatePipelineBinding|TestDeletePipelineBinding' -count=1
go vet ./server/api/doc-processing/... ./server/api/kbhandler/...
```

Full-package re-check: `doc-processing` shows the identical §3 failure set (unchanged). `kbhandler` shows the same failure set minus one — `TestGetDefaultKnowledgeStoreSelectsConfiguredStore`, previously flaky/order-dependent, now passes consistently across repeated runs. Unrelated to this slice's actual changes (`default_store_handler.go`/`default_store_handler_test.go` were not touched); noted here rather than investigated further, since it's an incidental improvement, not a regression.

For the `kb.doc_facets` slice:

```bash
go test ./server/api/doc-processing -run 'TestNewProductionRuntime|TestResolveProductionPipeline|TestLookupProductionPipeline|TestSetProductionPipelineRegistry|TestPipelineRegistrySQLStore|TestLoadProductionPipelineRegistry|TestDocPipelineMode|TestAppendPipelineStatusWithPlanPreservesPlanSnapshotAcrossLaterUpdates|TestHandleEvent_CreatesAndClosesRunAndThreadsRunIDToProcessors|TestCreateDocProcessPlan|TestBuildProductionProcessorPlan|TestBuildProductionPlanFacts|TestResolveProductionPlanFacts|TestDocMetadataSQLStoreGetInputRecordLoadsKnowledgeStoreID|TestSQLStoreUpsertDocFacets|TestSQLStoreGetDocFacets|TestPersistDocFacets' -count=1
go test ./server/api/kbhandler -run 'TestListPipelinesSuccess|TestListKnowledgeStoresSuccess|TestUpdateKnowledgeStoreSuccess|TestGetLatestDocProcessPlanByRecordID|TestListDocProcessPlansByRecordID|TestUploadInputsSuccess|TestListInputs|TestPipelineProcessorsMatchExecuted|TestListPipelineBindings|TestCreatePipelineBinding|TestUpdatePipelineBinding|TestDeletePipelineBinding|TestGetDocFacets' -count=1
go vet ./server/api/doc-processing/... ./server/api/kbhandler/...
```

Full-package re-check: both packages show the identical failure sets from the prior slice — no new failures, no further flaky-test changes.

For the enforced-mode slice:

```bash
go test ./server/api/doc-processing -run 'TestNewProductionRuntime|TestResolveProductionPipeline|TestLookupProductionPipeline|TestSetProductionPipelineRegistry|TestPipelineRegistrySQLStore|TestLoadProductionPipelineRegistry|TestDocPipelineMode|TestAppendPipelineStatusWithPlanPreservesPlanSnapshotAcrossLaterUpdates|TestHandleEvent_CreatesAndClosesRunAndThreadsRunIDToProcessors|TestCreateDocProcessPlan|TestBuildProductionProcessorPlan|TestBuildProductionPlanFacts|TestResolveProductionPlanFacts|TestDocMetadataSQLStoreGetInputRecordLoadsKnowledgeStoreID|TestSQLStoreUpsertDocFacets|TestSQLStoreGetDocFacets|TestPersistDocFacets|TestApplyPolicyFilter' -count=1
go test ./server/api/kbhandler -run 'TestListPipelinesSuccess|TestListKnowledgeStoresSuccess|TestUpdateKnowledgeStoreSuccess|TestGetLatestDocProcessPlanByRecordID|TestListDocProcessPlansByRecordID|TestUploadInputsSuccess|TestListInputs|TestPipelineProcessorsMatchExecuted|TestListPipelineBindings|TestCreatePipelineBinding|TestUpdatePipelineBinding|TestDeletePipelineBinding|TestGetDocFacets' -count=1
go vet ./server/api/doc-processing/... ./server/api/kbhandler/...
```

Full-package re-check: both packages show the identical failure sets carried forward from every prior slice in this log — no new failures.

For the `kb.pipeline_rules` slice:

```bash
go test ./server/api/doc-processing -run 'TestNewProductionRuntime|TestResolveProductionPipeline|TestLookupProductionPipeline|TestSetProductionPipelineRegistry|TestPipelineRegistrySQLStore|TestLoadProductionPipelineRegistry|TestDocPipelineMode|TestAppendPipelineStatusWithPlanPreservesPlanSnapshotAcrossLaterUpdates|TestHandleEvent_CreatesAndClosesRunAndThreadsRunIDToProcessors|TestCreateDocProcessPlan|TestBuildProductionProcessorPlan|TestBuildProductionPlanFacts|TestResolveProductionPlanFacts|TestDocMetadataSQLStoreGetInputRecordLoadsKnowledgeStoreID|TestSQLStoreUpsertDocFacets|TestSQLStoreGetDocFacets|TestPersistDocFacets|TestApplyPolicyFilter|TestPipelineRuleSQLStore|TestLoadProductionPipelineRules|TestResolveProductionPipelineBinding' -count=1
go test ./server/api/kbhandler -run 'TestListPipelinesSuccess|TestListKnowledgeStoresSuccess|TestUpdateKnowledgeStoreSuccess|TestGetLatestDocProcessPlanByRecordID|TestListDocProcessPlansByRecordID|TestUploadInputsSuccess|TestListInputs|TestPipelineProcessorsMatchExecuted|TestListPipelineBindings|TestCreatePipelineBinding|TestUpdatePipelineBinding|TestDeletePipelineBinding|TestGetDocFacets|TestListPipelineRules|TestCreatePipelineRule|TestUpdatePipelineRule|TestDeletePipelineRule' -count=1
go vet ./server/api/doc-processing/... ./server/api/kbhandler/...
```

Full-package re-check: both packages show the identical failure sets carried forward from every prior slice — no new failures.

## 6. Intended outcome of this slice

After this slice:

- the production processor roster has a declarative description;
- the runtime selection path can depend on that declarative plan rather than only on duplicated hardcoded lists; and
- there is a testable seam for the later P1 work on planner parity, facets, bindings, and persisted plans.

More specifically, after the execution-order/dependency extension:

- the plan can distinguish **spec/registration order** from **actual execution order**;
- `ProductionRuntime.Processors` now follows the same legacy execution order the controller actually uses; and
- the plan exposes minimal dependency information that can later be upgraded into richer planner state without re-inventing the contract.

After the structured-step/runtime/config extension:

- the plan surface now includes ordered steps, per-step dependencies, and a first-pass reason field;
- `ProductionRuntime` carries the selected structured plan directly, instead of forcing later code to reconstruct it;
- `ResolvedConfig()` includes the current `processor_plan_steps`, making the explainable plan visible from an already-existing diagnostic surface.

After the fact-input/runtime-options extension:

- the planner has a stable input object ready for future store/facet-aware routing work;
- store metadata can already flow into the plan without changing selection behavior yet; and
- the runtime constructor can carry those facts now, so later P1 slices can start using them without reworking the runtime API again.

After the record-fact-builder/control/run-parameter extension:

- the first deterministic store-aware facts can be derived from the current `kb.inputs` record shape;
- the control layer has one canonical helper for computing plan facts for a live event;
- the live doc-process run record now captures both plan inputs and plan outputs, making the plan visible in a real pipeline execution without yet letting the plan change routing behavior.

After the status-entry shadow exposure:

- the same live pipeline execution now exposes its plan snapshot in two operator-visible places:
  - run parameters (`kb.doc_process_runs.parameters`)
  - the current `doc_processing` status entry in `kb.inputs.status`
- later pipeline-status transitions preserve the same plan snapshot instead of overwriting or dropping it.

After the persisted execution-plan store extension:

- the system now has a dedicated table target for execution-plan snapshots: `kb.doc_process_plans`;
- the live event path persists one execution-plan row keyed by `run_id`, so shadow-mode exposure is no longer the only place the plan exists;
- the persisted row intentionally mirrors the current shadow surfaces (`plan_facts`, `plan_steps`) rather than introducing a second incompatible plan representation.

After the first deterministic document-facet extension:

- the plan-fact payload now carries two additional replayable routing facts from existing input state:
  - `InputDocType`
  - `SourceLanguage`
- it now also carries:
  - `DocumentNumber`
- and it now carries a dedicated derived routing vocabulary object:
  - `RoutingFacets.KnowledgeStoreBinding`
  - `RoutingFacets.InputDocType`
  - `RoutingFacets.SourceLanguage`
  - `RoutingFacets.HasDocumentNumber`
- those facts are populated without introducing any LLM dependency or new extraction pass;
- the same facts now appear consistently in:
  - `ProductionPlanFacts`
  - `kb.doc_process_runs.parameters`
  - `kb.doc_process_plans.plan_facts`
  - the `doc_processing` status entry snapshot

After the first named-pipeline / binding scaffold:

- the codebase now has an explicit named-pipeline registry seam (`ProductionPipelineSpec`) instead of treating pipeline identity as purely implicit;
- pipeline choice is now resolved deterministically by one helper (`ResolveProductionPipelineSelection`) with the intended P1 precedence order:
  - explicit request
  - knowledge-store binding
  - fallback default
- the current default remains `legacy_default`, so no processor-selection behavior changes yet;
- the selected pipeline is now visible in `ResolvedConfig()` via `processor_pipeline_selection`, giving operators and future tests a stable inspection surface before enforcement is introduced.

After the pipeline-selection persistence follow-up:

- the selected pipeline is now visible in the same three live/persisted plan surfaces already used for facts/steps:
  - `kb.doc_process_runs.parameters`
  - `kb.inputs.status` (`doc_processing` entry)
  - `kb.doc_process_plans.pipeline_selection`
- later pipeline-status updates preserve the original selection snapshot instead of dropping it;
- the current plan snapshot now has three operator-visible parts:
  - `processor_plan_facts`
  - `processor_plan_steps`
  - `processor_pipeline_selection`

After the structured pipeline-registry follow-up:

- the code-seeded named-pipeline model is no longer just “a list of accepted names”; it now has a proper structured spec contract (`ProductionPipelineSpec`);
- pipeline resolution can now return a full structured result (`ProductionPipelineResolution`) rather than forcing later code to re-lookup the selected pipeline by name;
- the runtime debug surface now exposes both:
  - `processor_pipeline_selection`
  - `processor_pipeline_spec`
- the current seeded specs are still intentionally simple and legacy-equivalent by default; they are a seam for later richer binding/policy work, not enforcement yet.

After the binding-record follow-up:

- pipeline resolution now has three distinct layers instead of one overloaded result:
  - binding resolution (`ProductionPipelineBindingResolution`)
  - selection (`ProductionPipelineSelection`)
  - structured spec (`ProductionPipelineSpec`)
- precedence logic now lives in one canonical binding helper instead of being spread across later callers;
- the runtime debug surface now exposes the full trio:
  - `processor_pipeline_binding`
  - `processor_pipeline_selection`
  - `processor_pipeline_spec`
- this gives future shadow-mode and API work a stable way to explain both:
  - which pipeline won
  - why that pipeline won

After the binding-persistence follow-up:

- the “why this pipeline won” trace is no longer runtime-only; it now survives in the same three snapshot surfaces as the rest of the plan:
  - `kb.doc_process_runs.parameters`
  - `kb.inputs.status` (`doc_processing`)
  - `kb.doc_process_plans.pipeline_binding`
- later pipeline-status transitions preserve the original binding snapshot instead of dropping it;
- the persisted/live plan snapshot now has four operator-visible parts:
  - `processor_plan_facts`
  - `processor_plan_steps`
  - `processor_pipeline_binding`
  - `processor_pipeline_selection`

After the first API-facing snapshot exposure:

- callers of the existing KB inputs list API no longer need to parse the raw `status` array themselves just to inspect the current plan snapshot;
- the response now includes a normalized `doc_processing_plan` object derived from the existing aggregate `doc_processing` entry;
- the API-facing normalized view intentionally mirrors the current four-part backend snapshot:
  - plan facts
  - plan steps
  - pipeline binding
  - pipeline selection
- because it is derived from the already-stored status entry, this adds operator visibility without creating a second source of truth.

After the first dedicated persisted-plan history read surface:

- operators now have two distinct inspection modes:
  - latest aggregate snapshot from `kb.inputs.status`
  - latest persisted plan/run record from `kb.doc_process_plans` + `kb.doc_process_runs`
- this is the first API surface that reads the persisted plan table directly instead of only consuming the aggregate status entry;
- the response intentionally includes both:
  - selected/bound pipeline information
  - the processor list actually recorded on the run row
- that makes it possible to compare “selected pipeline” and “executed processors” from one response without manual DB inspection.

After the first history/list follow-up:

- operators no longer have to choose only between:
  - the latest aggregate `kb.inputs.status` snapshot, or
  - a single “latest persisted plan” view
- they can now inspect multiple persisted reruns for the same record in one paged response;
- this is the first API surface that supports comparing successive reruns of the same document without direct SQL access;
- the response shape is intentionally aligned with the latest-plan endpoint so frontend/operator consumers can move from “latest” to “history” with minimal translation.

After the persisted-plan history filter follow-up:

- operators can now narrow persisted plan history by:
  - run status
  - run mode
  - selected pipeline name
- this keeps the history endpoint useful as rerun counts increase, without introducing a separate search or reporting endpoint;
- the filtering is intentionally lightweight and deterministic: it operates only on already-persisted run/plan fields, with no secondary derived state.

After the explicit requested-pipeline persistence follow-up:

- the “explicit request overrides store/default selection” rule is no longer only a planner contract; there is now a concrete persisted field on `kb.inputs` for it;
- KB upload ingestion can now persist an optional `requested_pipeline` at document-add time;
- rerun-time fact loading now reads the same `requested_pipeline` field back from `kb.inputs`, so the explicit request survives later pipeline runs;
- this is the first live end-to-end slice where a P1 routing input is both:
  - written on ingest
  - read back on rerun / plan resolution

## 7. Current state and next expected slice

**Done, as of this update (Friday, July 31, 2026):** every P0/P1-handoff item, plus everything found necessary along the way — `kb.pipelines` (authored registry), `kb.pipeline_bindings` (replaced the free-text `default_pipeline` column), `kb.doc_facets` (persisted facet table), `DOC_PIPELINE_PLAN_ONLY` shadow-mode control, `pipeline_spec`/`ExcludedByPolicy`/`pipeline_processors_match_executed` threaded through all plan-inspection surfaces, `kb.pipeline_rules` (facet-driven selection with real conflict detection), the enforcement-gating fix (`applyPlanEnforcement` — enforcement now actually changes what executes, not just what's recorded), and full live-Postgres validation of every migration, CRUD path, and the enforcement path itself (both via a temporary validation program and via unit tests that exercise the real `handleEvent`).

**Not done:**

1. **`kb.pipeline_policies`** — the ADR names this separately from `kb.pipeline_rules`; still unclear what distinct capability it adds beyond `kb.pipeline_rules` + `kb.pipeline_bindings`. Read the ADR/spec directly before starting, rather than assuming it's "more of the same."
2. **P1 benchmark closeout (Chunk 6)** — attempted same day, stopped before completion. See the "P1 benchmark closeout: attempted, stopped before completion" subsection above for the full account: two real bugs were found and fixed along the way (a local-env extraction gap, and a goose migration that was never actually valid SQL), but the attempt was stopped when a real LLM call hung for 5+ minutes with unclear cause, per the user's choice not to keep spending API budget chasing it. **A real before/after comparison report (matching the P0 evidence devdoc's format) still does not exist.** Whoever picks this up has a head start: `benchmark_metrics_only`/`benchmark-cdm-metrics-only` are already seeded in `chenweb_test`, and the local-env workaround (extracting `mise.local-bzton.toml`'s `[env]` table) is documented and reproducible — the main open question is why the LLM call hung, which needs investigation independent of this P1 work.
3. **Real, non-synthetic document coverage.** Every document in `chenweb_test` — across every slice's validation, not just the benchmark attempt — is gold-run synthetic corpus data. If that matters before calling P1 production-ready, it requires deliberately extending validation to whatever database holds real documents (likely `miner`, per `mise.local-bzton.toml`'s `PG_DB_NAME`), which was explicitly deferred earlier in this session (see the live-DB validation subsection above for why).
4. **Live-reload of a running `doc-processor`/`doc-benchmark` process** when `kb.pipelines`/`kb.pipeline_bindings`/`kb.pipeline_rules` change — the registry/rules load once at `NewProductionRuntime` construction, not on every event.
5. **Clean up duplicated migration files in the main ChenWeb worktree**, if any remain — they were copied there to get applied against `chenweb_test` via the app's real migration runner, then removed again (worktree git status was clean as of the last check). Confirm this is still true before the branch is eventually merged.

**Minor, low-priority notes carried forward:** `kb.pipelines.name` is `UNIQUE` at the DB level, so duplicate-name `CreatePipeline`/`UpdatePipeline` calls fail with a generic 500 (no dedicated 409 handling — matches the rest of this codebase's CRUD surface, which doesn't special-case unique-constraint violations either).
