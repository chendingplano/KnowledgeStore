# ADR 2026072901 — SemOS Semantic Platform: Domain Ontology Modules and a Policy-Driven Document Pipeline

**Date:** 2026-07-29 \
**Status:** Proposed (draft for review) \
**Component:** SemOS Knowledge Base, ontology, doc-processor pipeline, document review \
**Authors:** Chen Ding \
**Tags:** SemOS, ontology, domain modules, doc-processor, pipeline routing, profiles, assertions, phased plan

## 1. Change Logs

* 2026/07/29, ADR created. Consolidates research `2026072302-rsch-object-centric-ontology`,
  spec `2026072702-spec-ontology-canonical-artifacts`, ADR `2026072701-adr-ontology-identity-and-assertions`,
  and the doc-processor capsule (`Capsules/coding-capsules/doc-processor/+CAPSULE.md`) into one
  buildable architecture with an executable phase plan.
* 2026/07/29, first revision. Adds the canonicalization kernel and the keyword lexicon
  (DR15, DR16) after folding in research `2026072301-rsch-keyword-mgmt` and specs
  `2026072301` / `2026072703`; adds the ontology data repository (DR17) and knowledge-store
  binding and scope (DR18); restructures pipeline selection into two tiers and makes routing
  conflicts blocking (DR6, DR7 rewritten); answers the standards question at four levels (DR13
  rewritten). The non-goals decision is renumbered DR14 → DR19.
* 2026/07/29, second revision. Validates the architecture against the proposed
  product-standard-comparison application (the first target application) and adds what it
  showed missing: role-based product/part modeling (DR20), the requirement-strictness partial
  order and directional verdict vocabulary (DR21), class-anchored comparison runs as an
  application service (DR22), and the metric-definition versus profile naming split (DR23).
  Adds the new-doc-processor roster. Non-goals renumbered DR19 → DR24.
* 2026/07/30, P0 documentation baseline revision. Records the verified deployed-system audit,
  freezes the 20 pilot competency questions and 50-term ontology terminology contract, corrects
  knowledge-store wiring language (C5), and updates the ontology handoff/spec status without
  changing runtime code or database state.
* 2026/07/31, P0 closeout evidence revision. Records the approved benchmark-evidence run for the
  ventilator pilot corpus, updates the P0 exit status to complete, and moves the remaining work
  into explicit post-P0 implementation planning for P1+.
* 2026/08/01, P2 implementation status revision. Annotates the P2 section as implemented and
  validated (chunks 0, A–F): ontology content stores + candidate lifecycle, DB-native module
  compiler/releases/activation, the four core 4a modules installed as data (including the full
  QUDT catalog into `quantity`), the `semid` canonicalization kernel with the governed
  ontology-term family, the `object_nodes` extension columns, and extension seams 1–4. See the P2
  implementation log `2026073105-devdoc-semos-p2-implementation-log.md` and the new ontology
  capsule `Capsules/coding-capsules/ontology/+CAPSULE.md`.
* 2026/07/31, storage-model revision (P2 planning). Records the **DB-native storage decision**:
  ontology content (terms, labels, axioms, mappings, the QUDT catalog) is authored and versioned
  **in the database** with `version` columns; there is **no data-only Git repository**. DR2's
  "author in Git, compile into Postgres" and DR17's dedicated `semos-ontology` repository are
  revised accordingly (annotated in-place). Code lives in `shared` (shareable) or `ChenWeb`
  (project-specific). Consequences: the LLM-cannot-activate guarantee becomes code-enforced via
  the candidate state machine (spec §9.3) rather than Git authorship; the module compiler becomes
  a DB-native validator/releaser that validates staged content, computes the content checksum, and
  writes immutable releases; versioning is by column, not by Git tag. See plan
  `2026073104-plan-semos-p2-ontology-core-and-canonicalization-kernel.md`.
* 2026/08/02, Appendix C added. Enumerates all database tables the ontology framework creates
  (36 new tables across P1–P4), alters (8 existing tables), or references (16 pre-existing
  tables), grouped by phase with descriptions, key columns, ADR references, and authoring or
  generation surfaces.
* 2026/08/03, P5 implementation status revision. The prior "P5 is implemented and wired" claim is
  **retracted**: an independent audit (bug `2026080301`, consolidated into review
  `2026080302-devdoc-ontology-p5-implementation-review.md`, defects P5-1…P5-30) found the tier-3
  resolver was inert by construction and unwired, promotion never ran in practice, every promoted
  binding failed compilation, clearance coverage keyed on the wrong dimension, and the exit tests
  wore criterion names without testing the criteria. The remediation plan
  `2026080303-plan-ontology-p5-completion.md` (Chunks A–H) has since been executed and merged to
  `main`: the `classify_document`/two-pass resolver is real and flag-gated
  (`CLASSIFY_DOCUMENT_ENABLED`, default off) with review-side classification wired into scope
  selection, clearance keys on governed `document.doc_kind`, promotion is transactional and
  canonical-checksum-correct, and the exit criteria now point at real tests. What this revision
  does **not** yet claim: P5 is complete — I2 (live PostgreSQL + synthetic-corpus proof) remains,
  and this ADR's completion entry will be added only after Chunk I passes. See plan
  `2026080103-plan-ontology-p5-rule-driven-routing.md`, spec `2026080102-spec-ontology-p5-rule-driven-routing.md`,
  and the ontology capsule `Capsules/coding-capsules/ontology/+CAPSULE.md` (P5 section).
* 2026/08/04, P3 Track B (keyword lexicon) status entry. The keyword lexicon is implemented as the
  second `semid` kernel instantiation (7 commits, chunks 0–H, merged to `main` and pushed): 6
  `kb.keyword_*` tables, CRUD stores with sqlmock tests, a keyword normalizer producing 6
  deterministic key kinds through a full NFKC pipeline, a `KeywordFamily` implementing
  `semid.FamilyAdapter` (`family='keyword'`) with multi-tier candidate generation (tiers 0-4
  auto-accept, tiers 5-6 deferred), a backward-compatible `semid.Normalizer.NormFunc` extension,
  13 REST endpoints, a standalone mention collector, and `KEYWORD_RESOLVER_MODE` env-var gating.
  Shipped behind observe mode with no downstream consumers connected. The deferred boundary
  (fuzzy tiers, reconciliation pipeline, `aligns_to_term` bridge, `on` mode, curated seed
  content, I2 live proof) is recorded in the Track B handoff
  `2026080401-handoff-semos-p3-trackb-keyword-lexicon.md`.
* 2026/08/01, DR2 rewrite (verified against implementation). DR2 is rewritten to state the
  **DB-native storage decision as the decision itself**, replacing the retired "author in Git,
  compile into Postgres" framing and its annotation. The rewrite is verified against the P2–P4
  implementation: versioned content stores (`kb.ontology_terms` etc., migrations `00014`–`00020`),
  the DB-native module compiler/releases/activation (`00021`–`00025`), the four 4a modules and the
  full QUDT catalog installed as data, the release-owned `included_in_release` transition, and the
  P3/P4 governed content (assertions, profiles, rules, review/comparison) — all versioned in the
  database, no data-only repository. Directly-coupled references updated to match: DR11 seam 4,
  §6.1 (module content as data), §7 env vars (the compiler reads the DB, not a repo), §8.1
  compiler row, §8.3.1 P0 bullet, and §10 consequences.
* 2026/08/06, platform/application boundary clarification. Names the product-standard-comparison
  application from the 2026/07/29 second revision explicitly: the **Document Review app**. Records
  that DR21/DR22 (the strictness comparator, class-anchored comparison runs, `kb.comparison_scopes`
  / `kb.comparison_runs` / `kb.comparison_cells`, §3.23) and the ventilator pilot benchmark/domain
  module are that app's concern, not the ontology platform's (P1–P3, P5–P7 generic
  ontology/keyword/profile/pipeline machinery). Nothing about DR21/DR22 changes — §3.23 already
  scoped them as an L7 application service and §8.2 already says "not a doc processor"; this entry
  only makes the boundary explicit by name, because a downstream module spec (keyword
  canonicalization, `2026080403`) had drifted into treating P4's comparison-matrix row key as a
  requirement the platform must itself satisfy. In-place tags added at §3.23, §8.1's comparison
  service row, §8.2's not-a-doc-processor note, §8.3's deferred-data-gate line, and Appendix C.6.
* 2026/08/08, code-verification revision. Six independent, parallel read-only audits checked this
  ADR's claims against the actual `ChenWeb` code, migrations, and (where reachable) the live
  `chenweb_test`/`miner` Postgres databases — not against devdocs or this ADR's own prior status
  claims. Net result: the routing/gating/blocking machinery (DR6, DR7), Phase D association (DR8),
  the module compiler and P2 schema (DR2), the DR21 strictness comparator, and P5's `classify_document`
  resolver are all real, wired, tested code — not aspirational. But several specific claims were
  **contradicted** by the code and are corrected in place below (marked "verified 2026-08-08"):
  (1) **no DAG planner exists** — DR5's `Requires`/`Produces`-driven wave scheduler was never built;
  Phase A/B/C is still a hardcoded loop, confirmed by the code's own comments (§3.6, §8.3.4);
  (2) of the four core 4a modules, **only `core` is actually released and active** in the live dev
  database — `document-authority`, `measurement`, and `quantity` exist as seed code but have never
  been run against it, and the "4151 QUDT terms" figure has no support anywhere in the repository
  (§8.3.5, Appendix B.2); (3) `kb.knowledge_store_bindings`, `kb.recommendation_policies`, and the
  `scene_block_id` rename **do not exist** — store defaults live on a `kb.knowledge_store` column
  instead, DR21 recommendation policy storage was never built, and `kb.scene_objects.object_id` is
  unchanged (§3.7, §3.20, Appendix C); (4) the DR22 "cached comparison runs" are a write-once
  persist/read-back log with **no dedup-by-watermark or invalidation logic**, despite the caching
  language (§8.3.7); (5) seam 8 (`ReviewerToolRegistry`) **has zero registered tools** — completely
  unbuilt (§3.12, §8.3.7); (6) only tier-3 (`classify_document`) of DR4's three facet tiers actually
  writes observations in production — tiers 1 and 2 have no wired producer yet (§3.5, §8.3.4);
  (7) the §8.3.7 vs. Appendix A.1 contradiction over `extract_metric_definitions`,
  `extract_test_methods`, and `extract_product_structure` is resolved: **Appendix A.1 was right**,
  all three are built, routed, and writing candidates — §8.3.7's "remain to be implemented" was
  stale text, now removed. Also confirmed accurate and unchanged by this audit: P5's Chunk I
  (I2 live-PostgreSQL + synthetic-corpus proof) genuinely has not landed — the live database shows
  zero rows in every P5-specific table — so P5 is still correctly not marked complete; P6 and P7
  remain unstarted; and Open Decisions OD2, OD4–OD10 are all exactly where the last revision left
  them. One finding this ADR itself had not caught up to: a substantial "governed
  external-terminology portfolio" (source registry, `terminology-fetch`/`terminology-import`/
  `terminology-coverage` CLIs, a Svelte admin review UI) shipped 2026-08-07 as part of the
  keyword-lexicon work. **Correction (same day, per the project owner):** this is not
  undocumented drift — it is a properly planned and specced sub-project of the keyword module,
  governed by spec `2026080403` §21 and tracked in its own plans, design specs, and handoffs
  (listed in the next changelog entry). It was simply not yet cross-linked from this ADR's own
  text before this revision; §8.3.6 and §15 now cite the governing documents directly.
* 2026/08/08 keyword-lexicon sub-project cross-link (steps 11-12 + external terminology portfolio). 
  The keyword-lexicon work that shipped 2026-08-06/07 (flagged above as uncross-linked) is a deliberate, documented sub-project — "Keyword Steps 11-12" plus the "External Terminology Portfolio" — governed by spec `2026080403` §21 and tracked in: [25], [26], [27], [28], [29], [16], [30]. **What it built, beyond what the 2026-08-08 code audit already found:** tier-5 fuzzy matching wired into `KeywordFamily.CandidateNodes` (trigram blocking + edit-distance guardrails); an offline `keywords.Reconciler` (`cmd/keyword-reconcile`) for tier-6 merges; the `aligns_to_term` bridge (`AlignmentsStore`, a §14.2 merge conflict-gate + follow, resolver alignment-follow, and observe-path auto-align) plus its metric-pipeline consumer seam
  (`ResolvingMetricsStore` decorator, `kb.metrics.keyword_concept_id`/`metric_definition_term_id`,
  migration `20260806000002`); and the governed external-terminology portfolio itself — a source
  registry and import runner with adapters for QUDT, SIRP, an IEC 60050-845 seed, Wikidata, and
  UCUM (migration `20260807000001`), plus an automated-download admin page, a Review page
  (approve/disapprove with operator comments, gating import), and a weekly
  `terminology_refresh` scheduler job for Wikidata. **Live acceptance, not synthetic:** QUDT
  3.5.0 imported (1,223 quantity-kind entries, 3,177 labels, 1,342 relations, `skos:closeMatch`
  retained as non-authoritative); UCUM (305 unit codes); BIPM SIRP (149 entries, 447 labels);
  Wikidata expanded from a 3-entity pilot to the 1,521 Q-IDs QUDT 3.5.0 links via
  `wikidataMatch` (7,963 labels, 1,092 broader relations, 837 negative decisions); `亮度` was
  proven to merge into active `Luminance` by exact identity evidence regardless of embedding
  cosine score. **The "closing I2" claim, precisely scoped:** a live PostgreSQL run on
  2026-08-06/07 against the *original* cosine-threshold tier-6 design found it was not
  model-agnostic (two different embedding models scored the same true match at 0.67 and 0.45
  against a 0.90 threshold) — this run is what motivated the redesign in
  `2026-08-07-model-agnostic-tier6-validation-design.md`, replacing raw-cosine authority with
  deterministic identity evidence. That redesign was then itself live-verified against real
  PostgreSQL with the real imported terminology data above — this is the scope in which I2 is
  genuinely closed. It does **not** mean the keyword module's *online* resolve path
  (`ResolveName`/`ResolveAndObserve`) has been run against real document text flowing through the
  doc-processing pipeline — the step-11/12 handoff states plainly that this broader,
  pipeline-level I2 gap (inherited from the original Track B handoff) remains open. **Still
  deferred, unchanged from the 2026-08-08 code audit:** full R1-R7 reconciliation orchestration,
  `on`-mode wiring, Double Metaphone, batch adjudication UI, and — the actual production
  precondition — the §15.1 governed-catalog bootstrap (seeded `metric_definition` terms for the
  observe path to align to) and operator approval of a published production seed release; IEC
  60050-845 stays copyright-gated by design (the tool refuses it; the page shows "Requires
  license").
* 2026/08/08, first real content in the DR6 pipeline/binding mechanism ("Doc Processing
  Policies"). §15.1 had flagged that DR6's `kb.pipelines`/`kb.pipeline_bindings`/
  `kb.pipeline_policies` machinery was fully built but never actually populated — a small,
  separately specced/planned feature closes that gap for the first time. Design:
  `ChenWeb/docs/superpowers/specs/2026-08-08-doc-processing-policy-design.md`. Plan:
  `ChenWeb/docs/superpowers/plans/2026-08-08-doc-processing-policy.md`. **What it built:** a
  declarative config format (`config.local.toml`'s `[doc-processing-policy-*]` sections plus a
  `[doc-processing-policy-bindings]` store→policy map, gitignored/local by design — same "config
  file authors into the DB" pattern `ontology-seed` established for ontology content, not a new
  mechanism); a new package-internal parser/validator
  (`docprocessing.DocProcessingPolicySeedConfig`, `server/api/doc-processing/policy_seed_config.go`);
  a transactional seed function (`docprocessing.SeedDocProcessingPolicies`,
  `server/api/doc-processing/policy_seed.go`) that upserts `kb.pipelines` rows by name, authors a
  new draft `kb.pipeline_policies` version with `binding_kind='store_default'` `kb.pipeline_bindings`
  rows (one system-wide default, `ks_store_id IS NULL`, plus one per bound knowledge store),
  compiles it through the existing `PolicyCompilerSQLStore`, and activates it — archiving whatever
  was active before; and a CLI, `server/cmd/doc-processing-policy-seed`, modeled directly on
  `server/cmd/ontology-seed`. **Verified against the real `miner` staging database** (not just
  mocks): two policies (`no-entities-relations`, the system-wide default excluding
  `extract_entity`/`extract_relation`; `all`, bound to the `Research` knowledge store) seed and
  activate correctly, re-running is idempotent (upsert-by-name, new policy version each run), and
  direct-SQL resolution checks confirm knowledge store 4 (Research) resolves to `all` and store 5
  (卫健委标准, unbound) falls through to the system default — matching DR7's precedence exactly.
  **What this does not yet mean:** activation only takes effect in a running `doc-processor`
  process after that process restarts (the active policy loads once at startup, per §8.3.4's
  existing finding) and `DOC_PIPELINE_PLAN_ONLY=false` is set to move from shadow to enforced mode
  — neither was done on `miner` as part of this work, by deliberate choice, to avoid disrupting the
  live staging process. Also newly true and worth knowing: activating a policy version is a full
  *replacement*, not a merge — anything (bindings, gates, rules) authored under the previously
  active policy stops being consulted the instant a new version activates; the code's doc comments
  and the CLI's printed output now say so explicitly. §3.7 and §8.3.4 are updated below; §15.1's
  "named pipelines" row is marked resolved-in-part.
* 2026/08/09, facet tiers 1-2 wired; tier 3 converted from mandatory-gated to routed; Doc
  Processing Policy storage/CRUD confirmed and documented. Three changes, one session:
  **(1) Facet tiers 1-2 are now real production producers** — `ComputeTier1Facets`
  (`facet_tier1.go`) and `tier2FacetsFromSource` (`facet_tier2.go`), wired unconditionally into
  `ControlService.handleEvent` and `ExtractDocMetadataProcessor.HandleEvent` respectively, both
  persisting to `kb.doc_facet_values`. §15.1's "Facet tiers 1–2" row is resolved. **(2)
  `classify_document` (tier 3) is no longer `mandatory_gated`/env-flag-gated** — it is now
  `Class: "routed"` in `productionProcessorSpecs`, like any other routed processor, gated
  per-document by an ordinary `kb.pipeline_rules` row
  (`target_processor="classify_document"`) instead of the deleted `CLASSIFY_DOCUMENT_ENABLED`
  flag; the resolver is now always constructed, degrading to nil only when no classifier model is
  configured. **(3) Doc Processing Policy storage/CRUD is confirmed and written up** (§3.7): full
  create+activate CRUD on `kb.pipeline_policies` (versioned, append-only, no update/delete by
  design), full CRUD on `kb.pipeline_bindings`/`kb.pipeline_rules` for store↔policy association,
  and a seeded system-default policy from first boot — closing a documentation gap this ADR itself
  had left open (the same question had already been asked once). In the course of that
  verification, found and corrected a **stale self-correction**: the 2026-08-08 status note in §3.7
  claiming `kb.knowledge_store_bindings` didn't exist and the store-default pipeline was still a
  `default_pipeline` column was itself already wrong the day it was written — migration
  `20260731000006` (same day, later in sequence) had already dropped that column in favor of
  `kb.pipeline_bindings`. §3.5, §3.7, and §15.1 are corrected below; the doc-processor capsule's
  §7 pipeline table and §7.6 are updated to match
  (`Capsules/coding-capsules/doc-processor/+CAPSULE.md`).
* 2026/08/09, DR1's seven 4a modules reconciled against implementation; Appendix B.2 rewritten to
  cover all seven. Prior revisions (§8.3.5, Appendix B.2, §15.2) used "the four core 4a modules" as
  if that were DR1's total, when §3.2 actually defines seven: `core`, `quantity`,
  `document-authority`, `deontic`, `measurement`, `occurrence`, `inventory`. Checked against
  `server/cmd/ontology-seed`, `server/cmd/qudt-import`, §3.3.1–3.3.3's authoring-surface list, and
  Appendix A's processor roster: **three of the seven — `deontic`, `occurrence`, `inventory` — have
  no authoring surface at all** — no seed/import code, no `kb.ontology_modules` row, no mention
  anywhere in this ADR outside DR1's one-line definition table. Their corresponding pipeline output
  (`kb.provisions` via `extract_provisions`; `kb.scene_objects`/`kb.search_artifacts` `scene_block`
  via `generate_scene_blocks`; `kb.search_artifacts` `inventory_item` via
  `extract_inventory_items`) is pre-ADR Layer-1 evidence, ungoverned by any 4a vocabulary. Appendix
  B.2 is rewritten as a full per-module reference — ownership (from DR1), the doc processor(s) that
  populate or consume it, the storage table(s), and current status — for all seven modules, not
  just the four with seed code. §3.2 gets a pointer to it; §15.2 gains three new rows for the
  previously untracked modules.
* 2026/08/09, `kb.pipeline_gates` removed as a false table reference; `kb.pipeline_rules` given a
  real config-driven authoring surface; `kb.pipelines` given `description`/`is_system_default`
  columns. Prompted by a live-DB review of Appendix A.1's `classify_document` row: `kb.pipeline_gates`
  (§3.5, §3.6, §8.3.4, §15.1, Appendix A.1, and matching Go comments in `applicability_resolver.go`/
  `runtime.go`/`processor_plan.go`/`ontology_review_scopes_handler.go`/`classify-document_test.go`)
  was never a real table — checked against every migration and Appendix C, confirmed absent. It was
  `pipeline_gates.go`'s in-memory `PipelineGate`/`ResolveProcessorGate` machinery, which reads
  `kb.pipeline_rules` directly; every `` `kb.pipeline_gates`/`kb.pipeline_rules` `` phrase is now
  just `` `kb.pipeline_rules` ``. Direct query against the live `miner` database at the same time
  found `kb.pipeline_rules` at zero rows and confirmed why: `SeedDocProcessingPolicies`
  (`policy_seed.go`) only ever wrote `kb.pipelines`/`kb.pipeline_bindings` — the `no-entities-relations`
  vs `all` distinction is implemented entirely by each pipeline's flat `processors` allow-list
  (Tier 1, `applyPolicyFilter`), never by a Tier-2 gate — so `kb.pipeline_rules` had no producer
  short of a raw `POST /kb/pipeline-rules` call nobody had made. Also found: `config.local.toml`'s
  `[doc-processing-policy-*]` `description`/`is_default` fields were being written into
  `kb.pipelines.display_name` (no dedicated `description` column existed) and consumed only
  transiently to pick the system-wide binding (`is_default` was never persisted as a column
  anywhere). Fixed: migration `20260809000001` adds `kb.pipelines.description` and
  `kb.pipelines.is_system_default` (partial-unique, mirrors `kb.pipeline_policies`'s one-active
  index); `upsertDocProcessingPipeline` now populates both correctly and derives `display_name`
  from the pipeline name instead of overloading it with description text;
  `pipelines_handler.go`'s CRUD exposes both new columns; and `SeedDocProcessingPolicies` now also
  writes one unconditional `kb.pipeline_rules` row (`require` effect, always-true predicate) per
  processor named in each policy's `processors` list, so `kb.pipeline_rules` is a real, populated
  Tier-2 mirror of the Tier-1 allow-list rather than permanently empty. Conditional (predicate-
  bearing) gates still have no config syntax and remain API-only — a known, documented gap, not
  fixed here. Appendix A's intro gains a note that `Requires`/`Produces` (unlike everything else
  in this appendix) are Go-only, never persisted (§3.6). Appendix C.1's `kb.pipelines`/
  `kb.pipeline_policies`/`kb.pipeline_rules` rows are corrected to the verified real schema and
  population status. **Applied and re-verified against the real `miner` staging database**
  (migration `20260809000001` applied directly; `doc-processing-policy-seed` re-run against
  `config.local.toml`): `kb.pipelines` rows 4/5 (`all`/`no-entities-relations`) now carry real
  `description` text separate from `display_name`, and `is_system_default=true` lands on exactly
  `no-entities-relations` (the config section with `is_default = true`), matching the partial
  unique index's one-row invariant; `kb.pipeline_rules` went from 0 to **14 rows** (8 for `all`,
  6 for `no-entities-relations`, one per processor, all `effect='require'`, `active=true`,
  `approval_status='approved'`, scoped to the newly activated `policy_id=4` / `version=4`).
* 2026/08/09, `quantity` module gains a second live write path (code only, not yet run). The
  Review External Resources page's Approve action (`terminologyresourcehandler.ApproveResource`)
  previously only staged an approved `qudt` resource into the keyword lexicon's immutable
  external-terminology tables; it now also parses the same downloaded `qudt-all.ttl` artifact for
  all three QUDT classes (`quantity_kind`/`unit`/`dimension` — the keyword-lexicon adapter only
  ever kept `quantity_kind`), batch-writes new terms into `kb.ontology_terms` plus their labels
  (`kb.ontology_term_labels`) and exact source-IRI mappings (`kb.ontology_mappings`) inside the
  same transaction as the keyword-lexicon import, and then creates and activates a new `quantity`
  module release if anything is pending (`kb.ontology_module_releases`/`kb.ontology_active_releases`).
  No migration was needed — `term_kind`'s `quantity_kind`/`unit`/`dimension` values and
  `kb.ontology_mappings.to_iri` already existed for exactly this purpose. Verified end-to-end
  against a real (non-mocked) Postgres instance with representative fixtures covering all three
  term kinds, idempotent re-approval, and resuming after a simulated release-step failure; **not**
  yet run against the real QUDT catalog by an operator, so this closes the §15.2 gap's *code* half
  only — `quantity` is still zero live rows and the 4151-term catalog claim is still unverified
  until someone actually clicks Approve. See `ChenWeb/openspec/changes/external-resource-approve-ontology-terms`
  for the full proposal/design/spec/tasks, and §15.2's first two rows (updated in place) for the
  gap this closes.
* 2026/08/09, keyword-catalog auto-promotion (code, verified live). Approving any external
  terminology resource now also auto-promotes its staged `kb.keyword_catalog_entries` into flagged,
  provisional `kb.keyword_concepts` rows (`gloss_source='auto:import:<source>'`) in the background,
  without requiring a human review step — the same "autonomous, clearly flagged, optionally
  human-reviewed" principle already applied to the online D11 auto-create path (`gloss_source=
  'auto:d11'`), extended to the staging-import path. Enabled by default for every resource (no
  source-authority-based gating — System Admin page access control is treated as the authorization);
  a new mutable `kb.keyword_source_promotion_policy` table lets an admin opt a specific resource out.
  Deliberately does **not** touch `Reconciler.Run`/`ReconcileAmbiguous` or their scheduling — that
  subsystem's autonomy was addressed separately and stays out of this change's scope. Verified live
  against a real (non-mocked) Postgres instance, including a real discovery along the way: a
  collision-recovery pattern (insert fails on a content-hash collision, then look up the existing
  row) cannot run inside one shared transaction against Postgres, since a failed statement aborts the
  whole transaction — the production code already avoids this (it runs against a plain `*sql.DB`),
  but an early test draft that wrapped everything in a transaction for cleanup convenience did not,
  and had to be redesigned. See `ChenWeb/openspec/changes/keyword-catalog-auto-promotion`.
* 2026/08/10, Appendix C moved to a maintained standalone document; QUDT staging data spot-checked
  against a real end-to-end run. Appendix C ("List of Database Tables") is replaced with a pointer to
  `KnowledgeStore/doc-repo/user-manuals/database-tables.md` — a living inventory belongs in an
  operator-facing reference that gets updated as tables are added, not inside an ADR. The move also
  closes a real gap: former §C.4 only gestured at "11 more `kb.keyword_*` tables added 2026-08-05
  through 2026-08-07... not individually enumerated here" instead of listing them; the moved document
  enumerates all 11 (plus the new `kb.keyword_source_promotion_policy` from the entry above — 18
  `kb.keyword_*` tables total as of this revision) with real schemas. Separately, spot-checked an
  operator's report of "many `kb.keyword_catalog_entries.native_payload.symbol` values are empty"
  after a real QUDT re-download-and-approve: parsing the actual downloaded `qudt-all.ttl` directly
  confirms this is expected, not a defect — of QUDT's 1223 real `QuantityKind` resources (which
  matches the live `kb.keyword_catalog_entries` count for `qudt`/`3.5.0` on `miner` exactly), only
  438 (36%) carry a `qudt:symbol` triple upstream; even common quantities like `Acceleration` have
  none defined in QUDT's own vocabulary. `Unit` resources are the opposite (2773 of 2928, 95%, have a
  symbol) — units and quantity kinds are just genuinely different in how completely QUDT populates
  this field. The separately-reported figure of 1375 `kb.keyword_catalog_entries` rows is fully
  reconciled: that count is table-wide (`SELECT count(*) FROM kb.keyword_catalog_entries`, no source
  filter), and `miner` has three sources staged — `qudt`/3.5.0 (1223) + `bipm-sirp-quantity`/1.0.0
  (149) + `wikidata`/dump-2026-08-08 (3) = 1375 exactly. No discrepancy; QUDT's own figures check out.
* 2026/08/09, real QUDT Approve run against `miner`; a real bug found, fixed, and verified closed same
  day. An operator re-downloaded and approved `qudt` on System Admin → Resources → Review External
  Resources — content was byte-identical to the already-registered 3.5.0 release, so `ApproveResource`
  took the idempotent-replay branch straight into the governed-term write described in the 2026/08/09
  entry above. Post-run audit (parsing the real downloaded `qudt-all.ttl` directly through the
  production parser, cross-checked against `kb.ontology_terms`) found the write only two-thirds
  correct: `quantity_kind` (1125 = 1223 raw − 98 deprecated) and `unit` (2843 = 2928 raw − 85
  deprecated) landed exactly as designed, but `dimension` landed **zero** rows. Root cause: `qudt.go`'s
  `qudtDimensionClass` constant was `http://qudt.org/schema/qudt/DimensionVector`, which does not
  exist in QUDT's real vocabulary — the real class, confirmed against the downloaded file's own
  `@prefix qudt:` namespace and its `a qudt:QuantityKindDimensionVector, ...` triples, is
  `http://qudt.org/schema/qudt/QuantityKindDimensionVector`. `ParseQUDTGraph`'s Pass 1 only collects
  subjects whose `rdf:type` exactly matches the constant, so all 247 real dimension-vector individuals
  were silently invisible to the parser — no error surfaced, since `quantity_kind`/`unit` still
  populated and the empty-graph guard only fires when *no* supported class has any members. Fixed by
  correcting the one constant (existing tests reference it symbolically and were unaffected); a second
  write via the same replay path brought `kb.ontology_terms` to **4213** rows across all three kinds
  (1125/2843/**245**, where 245 = 247 raw − 2 deprecated), `kb.ontology_active_releases` pointing at
  `quantity` release `1.0.0`. The originally-cited "~4151" figure (§15.2, Appendix B.2) was always
  speculative and is superseded by this verified 4213. `document-authority` and `measurement` remain
  unaffected — this closes only the `quantity` half of §15.2's first row. Full detail, including a
  self-inflicted and same-session-corrected incident where a test run briefly wiped this data by
  targeting `miner` instead of `chenweb_test`, is in
  `openspec/changes/external-resource-approve-ontology-terms/tasks.md` §6.1.
* 2026/08/10, facet tiers 1-2 converted from mandatory to routed/gated (code, verified live). The
  2026-08-09 entry above wired `facet_tier1`/`facet_tier2` as real production producers but left
  them `Class: "mandatory"` — unconditional, with no independent selection or gate of their own,
  unlike `classify_document` (tier 3), which had just been converted from `mandatory_gated` to
  `routed` in that same session. Closing that asymmetry: both are now `Class: "routed"` in
  `productionProcessorSpecs` (`processor_plan.go`), each individually gated the same way
  `classify_document` is — `facetTier1GatedOff`/`facetTier2GatedOff` (`facet_tier1.go`/
  `facet_tier2.go`) call `ResolveProcessorGate` against an authored `kb.pipeline_rules` row
  (`target_processor="facet_tier1"`/`"facet_tier2"`), `OnUndetermined: "run"`. With no gate row
  authored (the default), `ResolveProcessorGate`'s `"processor_default"` (Enable) applies, so
  behavior is unchanged from before this change; a gate-resolution error fails open (runs) at both
  call sites rather than silently dropping load-bearing facets over a misconfigured rule. Motivation
  is operational, not architectural: an individually gate-able tier-1/tier-2 lets an operator
  disable one in isolation for debugging, testing, or bug fixing without restarting with a
  different build or touching `s.Facets`/`s.Resolver` wiring — the same lever `CLASSIFY_DOCUMENT_ENABLED`
  used to provide for tier 3 before it was deleted in favor of this exact mechanism. §3.5 and the
  doc-processor capsule's §7 pipeline table are updated to match
  (`Capsules/coding-capsules/doc-processor/+CAPSULE.md`).
* 2026/08/12, **§3.24 (DR23) superseded in part by ADR `2026081201`.** A
  same-day session set out to document `extract_metric_definitions`,
  debugged why it under-extracted on a real document, and then checked
  DR23's assumptions directly against the live database: `kb.ontology_terms`
  has zero `metric_definition` rows (the `measurement` module is empty);
  `kb.keyword_concepts`/`kb.metrics.keyword_concept_id` have never resolved
  a real extracted metric (`KEYWORD_RESOLVER_MODE` defaults `off` and is
  unset in this deployment — `0` of `7,040` metric rows carry either
  identifier); and the only write path to `kb.ontology_terms`
  (`CandidateStore.PromoteToContent`) hard-requires human approval of a
  candidate that the low-recall harvester was unlikely to generate in the
  first place. Separately, **§2.1's "a domain has on the order of hundreds
  of real distinct metrics" is retracted as unfounded** — "domain" is not
  formally defined anywhere in this ADR or the code, so the claimed bound
  depends on an undrawn boundary and could be off by orders of magnitude
  (a "ventilator" domain vs. a "medical equipment" domain). ADR `2026081201`
  decides: `metric_definition` term creation must be automatic, not
  human-gated, extending the keyword module's already-shipped D11 auto-first
  policy and the 2026/08/09 "keyword-catalog auto-promotion" precedent one
  layer up, from concept to governed term (new `kb.ontology_terms.status =
  'auto-promoted'`); `extract_metric_definitions` is retired from the
  default pipeline (code and capsule doc kept, not deleted) since its
  gating role — deciding *whether* a metric gets a definition — no longer
  applies once every metric resolves to a term unconditionally. See ADR
  `2026081201-adr-auto-promoted-governed-terms.md` for the full decision;
  this entry exists so a reader of *this* ADR is not misled by §3.24's
  original framing into assuming human-gated term creation is still the
  design.

## 2. Context

### 2.1 C1. Where SemOS actually is

The implemented system is real and useful:

* a JetStream-driven doc-processor with 13 processors in a fixed three-phase pipeline
  (Phase A mandatory sequential, Phase B configurable concurrent, Phase C indexing);
* extracted artifact families — metrics, provisions, inventory items, entities/relations,
  summaries, topics, semantic projections, scene blocks — each with line-level provenance;
* canonical referent identity through `kb.artifact_objects` → `kb.object_nodes`, with
  reconciliation, merge audit, and ambiguous-tie handling (ADR 2026070701);
* hybrid retrieval (`kb.search_artifacts`), a navigation graph (`kb.artifact_connections`),
  artifact categories, and a multi-aspect LLM document-review pipeline (ADR 2026061801)
  with tool-use reviewers and per-artifact findings.

Applications built on this deliver value today. They are, however, built on foundations that were
assembled use case by use case. Three structural gaps limit how much further they can go.

### 2.2 C2. What the prior three documents settled

Research `2026072302` established the vocabulary and the layered target; spec `2026072702`
turned it into contracts (authoritative ownership, lifecycles, state machines, review decision
procedure, acceptance criteria); ADR `2026072701` ratified the layer boundaries
(DR1–DR7: referents stay in `kb.object_nodes`, meaning lives in governed terms, "what should be"
lives in versioned profiles, artifact→ontology linkage is mediated by qualified assertions,
LLMs propose but do not activate, each accepted relationship has exactly one owner store).

**This ADR does not reopen any of that.** It treats ADR 2026072701 DR1–DR7 and spec
2026072702 §8–§12 as the baseline contract.

### 2.3 C3. What they left open — the three problems this ADR closes

**O1 — Layer 4 is ambiguous.** Research §5.4 enumerates Layer 4 as *artifact-family* modules
(core, metrics, provision, inventory, document/authority, entity bridge). Spec §7 describes Layer 4
as *domain* modules ("pump, tax, document, organization"). These are two different axes. Building
either one as if it were the other produces either a domain ontology that cannot be extended
without touching processor code, or a processor contract that fragments per domain. Nothing in
the existing documents says how a domain module is authored, validated, versioned, installed, or
tested.

**O2 — The layer stack has no execution architecture.** Seven layers describe a *dependency*
order for knowledge, not a runtime. Nothing states where assertion normalization runs, what
triggers association, how deferred work is retried, or how a new layer-4 module reaches the
running system. Without an execution plane the layers stay a diagram.

**O3 — The pipeline is a fixed list, not a plan.** `[doc-processing].required_processors` is a
global, static, per-deployment list. Every configured processor runs on every document. There are
no conditions, no per-document decisions, no record of *why* a processor ran, and no way for the
knowledge layer to influence extraction. Concretely: `extract_metrics` runs on documents with no
metrics, and `extract_provisions` runs on documents with no normative language — paying full LLM
cost per chunk for near-empty output, and polluting the object graph with weak artifacts. Asking
an LLM per document "should metrics be extracted?" replaces a cheap wrong answer with an
expensive unreliable one.

### 2.4 C4. Canonical identity is one recurring problem solved four separate times

SemOS keeps rediscovering the same problem in different tables:

| Family | Mentions/surfaces | Canonical node | State today |
|---|---|---|---|
| Objects | `kb.artifact_objects` | `kb.object_nodes` | built; ambiguous-tie backlog (ADR 2026070701) |
| Categories | category assignments, `kb.category_alias_conflicts` | `kb.artifact_categories` | built; placeholder-then-enrich, alias conflicts unresolved |
| Keywords/terms | keyword fields on metrics, projections, topics, knowledges | *(none)* | not built; two overlapping specs |
| Ontology terms | `kb.ontology_candidates` | `kb.ontology_terms` | designed, not built (spec §9.4) |

Every one of them needs the same machinery: deterministic normalization to lookup keys, candidate
generation, deterministic scoring, LLM adjudication only for the hard tail, an accepted link with
an `ambiguous`/`deferred` state, scope-sensitive disambiguation, merge and split with tombstones,
and an audit trail. Research `2026072301` and specs `2026072301` / `2026072703` describe this
machinery well for keywords, and they describe it *fourth* — after objects and categories already
grew their own variants of it, and while ontology terms are about to grow a fifth.

Building the keyword module as a fourth bespoke system would lock in the divergence. DR15
extracts the kernel instead.

### 2.5 C5. Knowledge stores have partial membership wiring but no semantic or pipeline role

`kb.knowledge_store` (tenant, `ks_type`, `ks_name`, `ks_sources`, sync mode, status) is created,
has CRUD handlers, and has a default-store resolver. `kb.inputs.ks_store_id` already exists, uses
the legacy `ks_store_id` name, is nullable in the deployed schema, carries no foreign key to
`kb.knowledge_store`, and can already be populated by current ingestion paths. What it still does
**not** do is drive pipeline selection, identity/lexicon scope, ontology visibility, or review
profiles. "Run pipeline A on knowledge store K1" is not expressible today, and neither is
"in KS-Medical, *ML* means millilitre." DR18 completes and normalizes this partial wiring by
making the store both a routing key and a scope key.

### 2.6 C6. The connecting insight

O3 looks like a pipeline problem and O1 looks like an ontology problem. They are the same
problem asked twice:

```text
"Which requirements must this document satisfy?"      → review    (profile selection)
"Which processors should run on this document?"       → extraction (processor selection)
```

Both are *applicability* questions evaluated against the same facts about a document: its kind,
domain, issuing authority, jurisdiction, language, structure, and the classes of the objects it
discusses. Building two independent mechanisms would duplicate the predicate language, the
versioning, the approval gate, and the audit trail — and would let the two drift, so that SemOS
reviews a document against pump requirements whose supporting metrics were never extracted.

This ADR therefore builds **one applicability mechanism with two consumers**, and makes the
document pipeline a first-class, planned, observable execution plane over it.

## 3. Decision

> Numbering note: DR14 and DR19 are retired numbers. The non-goals decision was renumbered twice
> across revisions and is now DR24; no decision was deleted.

### 3.1 DR0 — Revised architecture: seven knowledge layers × three planes

The seven layers of research §5 are **retained** with two corrections (DR1, DR3) and are
re-expressed as one axis of a two-axis architecture. Layers describe what depends on what;
planes describe what runs.

```text
                    │ GOVERNANCE PLANE      │ EXECUTION PLANE       │ ACCESS PLANE
                    │ authoring, review,    │ pipeline stages,      │ APIs, search,
                    │ release, activation   │ workers, retries      │ graph, exports
────────────────────┼───────────────────────┼───────────────────────┼──────────────────
L7 review & apps    │ review-scope freeze   │ review_document       │ findings API
L6 profiles         │ profile approval      │ profile evaluation    │ SHACL export
L5 assertions       │ adjudication policy   │ Phase D normalize/    │ assertion API
                    │                       │ associate/project     │
L4b domain modules  │ module release        │ (data only — no code) │ module API
L4a core modules    │ platform release      │ (data only — no code) │ module API
L3 terms & schemes  │ candidate → release   │ term resolution       │ term API, SKOS
L2 referent identity│ merge adjudication    │ reconciliation        │ object graph API
L1 evidence         │ (none — extraction    │ Phase A/B extraction  │ artifact APIs,
                    │  is not governance)   │                       │ search
────────────────────┴───────────────────────┴───────────────────────┴──────────────────
Cross-cutting: applicability (DR3) drives L6 profile selection and the L1 extraction plan.
Cross-cutting: the canonicalization kernel (DR15) serves L2 objects, L3 terms, categories,
               and the keyword lexicon with one mechanism.
Cross-cutting: the knowledge store (DR18) is the default scope for identity, lexicon,
               routing, and review applicability.
```

Rules:

1. A layer may depend only on layers below it. L1 never depends on a reviewer's judgment.
2. The governance plane is the only path by which content becomes production-active.
3. The execution plane never activates governed content; it consumes the active release.
4. The access plane is always derived and rebuildable.
5. A cross-cutting mechanism is built once and instantiated per family or per scope; it is never
   forked per layer.

### 3.2 DR1 — Layer 4 splits into two tiers: core semantic modules (4a) and domain modules (4b)

This resolves O1. The two readings of "Layer 4" are both correct and belong to different tiers.

**Layer 4a — core semantic modules.** Platform-owned, few, slow-changing. They define the
*contract between processors and the ontology*: what an assertion can be, what value forms exist,
what qualifies a claim.

| Module | Owns |
|---|---|
| `core` | referent, information artifact, assertion, evidence, agent, role, valid/transaction time, polarity, confidence, semantic-role predicates |
| `quantity` | quantity kinds, units, dimensions, conversion, value forms (scalar/interval/bound/tolerance/ratio/formula), comparators; QUDT mappings |
| `document-authority` | document kind, issuer/authority, edition/version, jurisdiction, normative vs informative, effective interval, supersedes/amends/cites, **document-facet vocabulary (DR4)** |
| `deontic` | modality (required/permitted/recommended/prohibited/declared), actor, action, condition, exception — the provision contract |
| `measurement` | metric definition vs metric assertion, observable property, feature of interest, procedure, condition, aggregation/window, and the metric assertion kinds of research §5.4 |
| `occurrence` | occurrence, participant, action, state, cause, outcome — the scene-block contract |
| `inventory` | item type vs item instance, part-of, member-of, location, custodian, catalog/serial identity, quantity-on-hand |

> **2026-08-09 status:** of these seven, only `core`, `quantity`, `document-authority`, and
> `measurement` have any authoring surface (`ontology-seed` or `qudt-import`) — and of those four,
> only `core` is actually released and active in the live database (§8.3.5, Appendix B.2).
> `deontic`, `occurrence`, and `inventory` are design-only: no seed code, no `kb.ontology_modules`
> row, no mention anywhere else in this ADR. See **Appendix B.2** for what each of the seven
> actually owns, which doc processor(s) populate or consume it, which tables store it, and its
> implementation status.

**Layer 4b — domain modules.** Domain-owned, many, pluggable: `pump`, `pressure-vessel`,
`tax-cn`, `medical-device`, … Each contains domain classes and subclasses, domain properties
bound to 4a quantity kinds, domain axioms, **domain profiles and profile rules**, applicability
rules, competency questions, and conformance fixtures.

**The binding constraint (this is what makes the tiering worth having):**

> A Layer 4b module may **not** introduce new assertion kinds, predicates, value forms, or
> qualifier dimensions. Those live in 4a. A domain that needs one raises a 4a change with
> platform review.

Consequence, and the property to test: **installing a domain module is data, not code.** No
processor, normalizer, evaluator, or API changes when `pump` or `tax-cn` is added. If a domain
module cannot be expressed without a code change, that is a signal that 4a is missing something —
which is exactly the feedback loop we want, because it is rare, visible, and reviewed.

### 3.3 DR2 — A domain module is versioned content in the database, released through a DB-native compiler

Spec §9.7 requires module manifests, checksums, and immutable releases but not where the content
is authored. Decision: **author, review, and version module content directly in the database; a
DB-native compiler validates the staged approved content and writes immutable releases.** There is
no data-only Git repository and no "author in Git, compile into Postgres" step — the same storage
decision as DR17 (workspace principle: data lives in the database; shareable code in `shared`;
project-specific code in `ChenWeb`).

**Where content lives — every module is content rows, versioned by column:**

| Table | Holds | Versioning |
|---|---|---|
| `kb.ontology_terms` | governed terms (`term_kind`: class/property/individual/concept/metric_definition/quantity_kind/unit/dimension) | `UNIQUE(term_id, version)`; an accepted change inserts a new version row, never mutating a released row |
| `kb.ontology_term_labels` | language labels (`label_role`: prefLabel/altLabel/hiddenLabel); one prefLabel per term+language | per-term version |
| `kb.ontology_axioms` | compiler-approved axiom kinds over governed term refs | per-axiom version |
| `kb.ontology_mappings` | mappings to governed terms or external IRIs (`relation`: exact/close/broad/narrow/related); exact requires approval | per-mapping version |
| `kb.ontology_profiles` / `kb.ontology_profile_rules` | governed profile and rule content (DR4, DR23) | per-profile / per-rule version |
| `kb.ontology_candidates` | proposals (LLM/import/discovery); spec §9.3 state machine | `fingerprint` UNIQUE (dedup) |

`kb.ontology_modules` holds module identity plus declared dependencies; released snapshots and
their versions live in `kb.ontology_module_releases`; activation is a pointer in
`kb.ontology_active_releases`. A domain module such as `pump` is therefore not a directory of
`.toml` files but a set of approved content rows under a `module_id`, released with pinned
dependency releases (see §6.1 for the worked example).

**The compiler is a DB-native validator/releaser** (`server/cmd/ontology-compiler`, plus the
`mise run ontology-compiler` task). Its input is the module's staged approved content in the DB,
not files. `release` runs one transaction: validate (module exists, ≥1 approved term, dependency
graph acyclic and every dependency pinnable, dangling-reference guard over axiom/mapping/rule
references) → snapshot the approved content → compute the deterministic content checksum → pin the
dependency releases → insert one immutable `kb.ontology_module_releases` row carrying the full
payload snapshot → tag the included content rows `included_in_release` +
`released_in_release_id` → supersede the module's prior release. A failed validation rolls back
and leaves the previous active release untouched. `validate` / `activate` / `rollback` /
`modules` / `active` complete the CLI.

**Activation is a separate, audited act:** an insert into `kb.ontology_active_releases` (at most
one active release per module, enforced by a partial unique index). Rollback inserts a new
activation row pointing at an older release; nothing is deleted.

**The LLM-cannot-activate guarantee is code-enforced, not Git-enforced.** ADR 2026072701 DR6 ("an
LLM may not activate ontology content") is structural in the state machine rather than a status
column: LLM, import, and discovery output lands in `kb.ontology_candidates`; promotion to content
requires a human-approved change set; and the `included_in_release` transition is owned by the
module release path alone (`TransitionStatus` refuses it). No LLM path can reach accepted content
rows.

**Authoring surfaces.** Content is authored as data three ways: 
1. direct authoring into the content tables (the curated 4a modules 
   via `server/cmd/ontology-seed`; a future authoring GUI);
2. candidate → promote, the only way LLM/import content enters; 
3. external catalog import — `server/cmd/qudt-import` parses the published QUDT TTL 
   as transient generator input and writes its output into the DB, after which the module is released normally (the DR13 "selective import" path).

**Reproducibility.** A release is reproducible from the immutable payload snapshot, the
deterministic content checksum, and the pinned dependency releases — without a commit SHA.

Rationale:

* it honors the workspace storage principle (data lives in the database; no data-only repository)
  and keeps the ontology lifecycle on the same operational stores the rest of SemOS uses;
* installing a domain module stays **data, not code** (the DR1 property): a module is a release of
  content rows, so no processor, normalizer, evaluator, or API changes when `pump` or `tax-cn` is
  added;
* the properties "author in Git" bought — review discipline and a structural barrier against LLM
  activation — are preserved in code: governed content rows carry the spec §9.3 status lifecycle,
  `source_candidate_id` provenance back to the proposing candidate, append-only release history,
  and audit fields (`create_by`/`modify_by`/`released_by`); the content lifecycle *is* the review
  trail;
* versioning is by column, not by Git tag; an accepted change inserts a new version row and the
  previous version stays readable;
* an authoring UI can be added later and write to the same tables, or export approved candidates
  into them; the DB contract does not change.

#### 3.3.1 Evidence to Ontonogy Content
Pipeline results (or evidences) do not become ontology terms, axioms, etc. Extracted 
artifacts stay as evidence. They never auto-promote to governed ontology content. The ADR 
is explicit about this (refer to `Authoring surfaces`): ontology content (terms, axioms, 
mappings, profiles, rules) is authored through three separate surfaces:

1. Direct authoring — ontology-seed writes the curated 4a core modules (`core`, 
   `document-authority`, `measurement`) as content rows. It's the DB-native authoring surface 
   for platform-owned vocabulary.
2. Candidate → promote — the only way LLM/import/discovery content enters. It lands in 
   `kb.ontology_candidates`, and promotion to content rows requires a human-approved change 
   set. This is the code-enforced "LLM cannot activate" guarantee.
3. External catalog import — qudt-import parses the published QUDT TTL as transient generator 
   input, writes validated content into the DB, then the module is released normally.

At most, pipeline output feeds the candidate path — and only via the §9.3 state machine with 
human approval, never directly.

#### 3.3.2 Direct Authoring
Direct authoring writes straight into the content tables with `status = "approved"` — no
candidate, no promote step:

| Content | Table | Direct authoring surface |
|---|---|---|
| Terms — all 8 kinds (`class`, `property`, `individual`, `concept`, `metric_definition`, `quantity_kind`, `unit`, `dimension`) | `kb.ontology_terms` | `ontology-seed` (curated 4a: `core`, `document-authority`, `measurement`); `qudt-import` (`quantity` module); API `POST /kb/ontology/terms` |
| Term labels | `kb.ontology_term_labels` | `ontology-seed`; `qudt-import`; API `POST /kb/ontology/terms/:term_id/labels` |
| Mappings | `kb.ontology_mappings` | `qudt-import` only (QUDT catalog → `quantity` module) |
| Profiles | `kb.ontology_profiles` | API `POST /kb/ontology/profiles` |
| Profile rules | `kb.ontology_profile_rules` | API `POST /kb/ontology/profile-rules` |
| Module registration | `kb.ontology_modules` | `ontology-seed`, `qudt-import` |

Seed and catalog import write `status = "approved"` directly, bypassing the spec §9.3
draft/in_review/approved state machine; they are the trusted platform/catalog paths.

#### 3.3.3 Not Directly Authorable
**Not directly authorable — only via candidate → promote (human-approved change set):**

* **axioms** (`kb.ontology_axioms`) — no direct command or route; the only path is `promoteAxiom`
  from candidate kind `axiom`;
* **general-purpose mappings** — no route; `qudt-import`'s catalog path is the only direct one;
* **any LLM/import/discovery proposal** — must land in `kb.ontology_candidates` and be promoted
  (the code-enforced "LLM cannot activate" guarantee), even though a human may author the same
  content directly;
* candidate kinds `profile`, `profile_rule`, `module_change` are accepted as candidates but are
  not promotable in the current chunk — profiles/rules reach production only via their direct API
  routes.

#### 3.3.4 The mise Command
The mise command doesn't "create" domain modules. `mise run ontology-compiler release
--module X --version Y` is a validation + release gate over content that already exists 
and is already approved in the DB. It runs the seven-step transaction (validate → 
snapshot → checksum → pin deps → insert immutable kb.ontology_module_releases row → 
tag included_in_release → supersede prior release). It creates nothing; if the module 
has no approved content rows, validation fails. Then activate re-points the active-release 
pointer as a separate audited act.

The correct flow
```text
1. Pipeline extracts artifacts  ──►  Layer 1 evidence (kb.*_artifacts), line-level provenance
2. Ontology content is authored  ──►  ontology-seed (curated 4a)
                                    └─► candidate→promote (LLM/import/discovery, human-approved)
                                    └─► qudt-import (external catalogs)
3. mise run ontology-compiler  ──►  validates + snapshots + checksums + releases
   release --module X ...             the already-approved content rows (immutable release)
4. activate                     ──►  re-point kb.ontology_active_releases pointer
```
The key mental model: the pipeline produces evidence; ontology content is governed — it needs an author and an approver before the compiler ever runs. The compiler is the release gate that makes that content immutable and installable, not a factory fed by extraction results.

### 3.4 DR3 — Applicability is one mechanism with two consumers

A single predicate language and evaluator (`semrules`) is evaluated against a **fact set**:

```text
fact set = document facets (DR4)
         + classification assertions for the objects in scope
         + review context (as_of date, jurisdiction, operating context, purpose)
         + deployment context (workspace, tenant, corpus)
```

Two consumers:

| Consumer | Question | Rule source | Output |
|---|---|---|---|
| Extraction planner (L1) | which processors run on this document | pipeline policy (DR6) | execution plan |
| Review scope resolver (L6) | which profile versions govern this review | active module releases | frozen review scope (spec §12.1) |

The predicate grammar, the operator registry, the evaluation trace, and the
`indeterminate`-on-conflict semantics are shared code. This is the correction to research §5:
applicability is not a sub-feature of Layer 6; it is a cross-cutting service consumed by
Layer 6 *and* Layer 1.

**Guard against silent coupling:** a domain module may ship routing proposals as governed
content rows (authoring them as data per DR2), but installing the module never changes the
pipeline by itself. Routing rules become effective only when included in an activated
**pipeline policy** version (DR6). Ontology activation and pipeline activation are separate
approvals with separate blast radii.

### 3.5 DR4 — Document facets: a governed, cheap-first classification of documents

Routing and profile selection both need facts about the document. SemOS today has only
`kb.inputs.title/doc_no/publish_date/authors/doc_metadata` — an LLM-shaped JSONB bag, unsuitable
as a decision key.

Introduce `kb.doc_facets`: one row per `(record_id, facet_key)`, with value, value kind,
confidence, method, evidence, producing policy version, and run id. Facet **keys and permitted
values are ontology terms** in the `document-authority` module — governed vocabulary, not free
text. The table is key/value so that new facets need no migration.

Facets are produced in three tiers, cheapest first:

| Tier | Method | Cost | Examples |
|---|---|---|---|
| 1 | Deterministic, from blocking/static-analyzer output | free | page count, language mix, table-line ratio, numeric-with-unit density, modal-verb density (`shall`/`must`/`应`/`必须`), TOC presence, heading depth, doc-number pattern (GB/ISO/IEC/ANSI), file type, figure density |
| 2 | Derived from `extract_doc_metadata` | already paid | issuer, edition, publish date, authority hints from title/doc-no |
| 3 | LLM `classify_document` | one cheap call, first N pages | `doc_kind`, `domain`, `normative_status`, `jurisdiction` — **only for facets tier 1–2 left undetermined**, and only when some rule actually needs them |

Tier 3 is itself gated: the planner computes which facets the active pipeline policy requires,
and invokes the classifier only if one is missing. On a corpus with recognizable document
numbering, most documents never reach tier 3.

This is the answer to "letting LLMs decide whether to run a processor is difficult": we do not ask
an LLM a judgment question ("should metrics be extracted?"). We ask it a *classification* question
over a governed vocabulary ("what kind of document is this?"), cache the answer as a fact, and let
reviewed rules make the decision.

> **2026-08-08 status (superseded 2026-08-09, see below): only tier 3 was wired in production.**
> Two facet tables exist — `kb.doc_facets` (simple record-keyed routing facets) and
> `kb.doc_facet_values` (general path/value/method observation store, migration
> `20260801000016`) — but `applicability_facts.go` stated outright that
> `FacetMethodDeterministic` (tier 1) "has no production producer yet," and `FacetMethodMetadata`
> (tier 2, from `extract_doc_metadata`) had no production call site either. Only
> `classify_document` (tier 3, `FacetMethodClassifier`) actually wrote facet observations as of
> this date.
>
> **2026-08-09 status (verified against code): tiers 1 and 2 are now wired; tier 3's gate
> mechanism changed.** `ComputeTier1Facets` (`facet_tier1.go`) runs unconditionally inside
> `ControlService.handleEvent` right after the line file is parsed — deterministic, no LLM, always
> on, no configuration. `tier2FacetsFromSource` (`facet_tier2.go`) runs unconditionally inside
> `ExtractDocMetadataProcessor.HandleEvent` right after it persists `doc_no`/`publish_date` —
> also deterministic, no LLM, always on. Both persist to `kb.doc_facet_values` via the same
> `InsertFacetObservation` path tier 3 uses, and both are registered in `productionProcessorSpecs`
> (`facet_tier1`/`facet_tier2`, `Class: "mandatory"`) purely for registry/policy-tooling
> visibility — neither has a `Processor`/`HandleEvent` implementation of its own to wave-dispatch;
> the DAG planner these declarations would eventually feed still does not exist (§3.6). The
> "cheapest first" cost model is therefore realized in practice now: a decision-relevant fact a
> tier-1/2 producer already answered is `FactKnown` before the resolver ever considers invoking
> the classifier (`mergeTier12Facts`, `applicability_resolver.go`).
>
> `classify_document` (tier 3) is no longer `mandatory_gated`/flag-gated. It is `Class: "routed"`
> in `productionProcessorSpecs`, and `CLASSIFY_DOCUMENT_ENABLED` has been deleted from the
> codebase entirely — the tier-3 resolver is now always constructed (degrading gracefully to nil
> only when no classifier model is configured, exactly as before). Per-document run/skip control
> moved from that one global env var to an ordinary `kb.pipeline_rules` row
> with `target_processor="classify_document"`, resolved via `ResolveProcessorGate` from inside
> `ApplicabilityResolver.Resolve` itself (it is not wave-dispatched, so there is no
> `filterProcessors` pass to gate it through). With no such row authored anywhere yet, behavior is
> unchanged from before this change: `classify_document` still only actually runs when the
> pre-existing decision-relevant-tier-3-path check finds something a rule needs. It is wired into
> review-scope selection unconditionally too, for the same reason. See §7.6 of the doc-processor
> capsule (`Capsules/coding-capsules/doc-processor/+CAPSULE.md`) for the full current picture, and
> §15.1 below (this row is now resolved).
>
> **2026-08-10 status (verified against code): tiers 1 and 2 are now `Class: "routed"`, closing the
> asymmetry with tier 3 the 2026-08-09 entry above left open.** `productionProcessorSpecs`
> (`processor_plan.go`) declares both `facet_tier1` and `facet_tier2` as `Class: "routed"`,
> `OnUndetermined: "run"` — no longer `"mandatory"`. Each is individually gated at its (still
> inline, still not wave-dispatched) call site: `facetTier1GatedOff` (`facet_tier1.go`) inside
> `ControlService.handleEvent`, and `facetTier2GatedOff` (`facet_tier2.go`) inside
> `ExtractDocMetadataProcessor.HandleEvent`. Both call `ResolveProcessorGate` against an authored
> `kb.pipeline_rules` row (`target_processor="facet_tier1"`/`"facet_tier2"`) — the identical
> mechanism `classify_document` uses, described just above. With no such row authored (the
> default), `ResolveProcessorGate`'s `"processor_default"` (Enable) applies, so both still run
> unconditionally by default; a gate-resolution error also fails open (runs) at both call sites, so
> a malformed rule cannot silently drop load-bearing tier-1/2 facets. The lever this adds is
> operational: an operator can disable `facet_tier1` or `facet_tier2` independently — e.g. to
> isolate a bad tier-1 heuristic or a tier-2 metadata-derivation bug — without a restart or a
> different build, the same debugging/testing/bug-fixing case `CLASSIFY_DOCUMENT_ENABLED` used to
> serve for tier 3 before its deletion (see above) made this the established mechanism instead of a
> new per-tier env var. See §7 of the doc-processor capsule for the updated pipeline table.

### 3.6 DR5 — The pipeline becomes a declarative stage DAG with gates; A/B/C is the degenerate case

Processors gain an optional declaration (an optional interface, matching the existing
`PostProcessIndexer` idiom, so non-declaring processors keep working unchanged):

```go
type ProcessorSpec struct {
    Name     string
    Requires []ArtifactKind   // "lines" | "blocks" | "chunks" | "doc_metadata" | "facets" | "metrics" | ...
    Produces []ArtifactKind
    Class    ProcessorClass   // mandatory | routed | on_demand
    Cost     CostClass        // free | cheap_llm | expensive_llm
    OnUndetermined Decision   // run | skip   — per-processor default when rules do not decide
    Idempotent bool
}

type DeclaredProcessor interface{ Declare() ProcessorSpec }
```

The controller builds a DAG from `Requires`/`Produces`, computes topological **waves**, gates each
node with its routing decision, and runs each wave concurrently. Today's Phase A/B/C falls out as
a special case: A = the mandatory chain, B = one wide wave, C = the indexing wave, D = the new
semantic-association wave (DR8). Gate outcomes are `run`, `skip`, or `defer`
(recorded with a reason and dependency fingerprint, re-evaluated on a later run — the same
deferral semantics spec §9.3 defines for semantic decisions).

This replaces a hard-coded two-phase split with a structure that can express conditions today and
branches, loops, and new stage families later, without another controller rewrite. It is also the
mechanism through which Phase D, review, and future stages join the pipeline and inherit its
status reporting, stop handling, tracing, and per-processor logging for free.

> **2026-08-08 status (verified against code): the DAG planner does not exist yet.**
> `ProcessorSpec` is real (`server/api/doc-processing/processor_plan.go`, 20 real processors
> declared), but `Requires`/`Produces`/`Class`/`Cost`/`OnUndetermined` are plain strings, not the
> typed `ArtifactKind`/`ProcessorClass`/`CostClass`/`Decision` this DR describes, there is no
> `DeclaredProcessor` interface, and no code builds a topological wave schedule from them — the
> code's own comments say so directly: "`The DAG planner that consumes Requires/Produces arrives
> in a later phase`" and "`the DR5 Class/Cost/OnUndetermined declarations are metadata only until
> a runtime DAG enforcer exists to consume them`." Phase A/B/C is still a hardcoded
> `[]string{"A","B","C"}` loop (`processor_plan.go`), and Phase D is a bespoke channel-based
> dependency wait, not an instance of this DAG. Gate resolution (run/skip/defer with reason and a
> SHA256 dependency fingerprint) is real and working (`pipeline_gates.go`), but nothing consumes
> a deferred node's fingerprint to re-evaluate it later — defer is currently terminal within a run,
> not retried. See §8.3.4.

### 3.7 DR6 — Two-tier routing: named pipelines selected by a versioned binding policy, then per-processor gates

Routing is two questions, not one. "Run pipeline A on knowledge store K1" is a *pipeline
selection*; "skip `extract_metrics` on this particular document" is a *processor gate*. Collapsing
them into one flat rule list makes the common case (a project has a standard pipeline) as
expensive to express as the rare case.

**Tier 1 — named pipelines.** A pipeline is a named, versioned, declarative plan: an ordered
processor set, optional per-processor parameters, and optional refinement gates.

```text
kb.pipelines           pipeline_id, name, version, title, description, status,
                       definition JSONB, source_ref, checksum, created_at
```

Pipelines are authored as data in the ontology data repository (DR17,
`policies/pipelines/*.toml`) and compiled and activated by the same mechanism as ontology
modules. `default`, `standards`, `narrative`, and `minimal` are expected starting pipelines.

> **2026-08-08 status (verified against code):** per the DR2/DR17 storage revision, pipelines are
> DB rows, not `.toml` files. The seeded pipelines are `legacy_default` (empty processor list,
> `LegacyEquivalent: true` — this is the actual pipeline that reproduces `required_processors`),
> `store_default`, and `request_override` (`project_migrations/20260731000004`) — not
> `default`/`standards`/`narrative`/`minimal`, which appear nowhere in seed data or code and remain
> illustrative only.
>
> **2026-08-08 update (later the same day): real, non-illustrative named pipelines now exist.**
> A separately specced/planned feature ("Doc Processing Policies," see the changelog entry above)
> added a `config.local.toml`-driven seed tool (`server/cmd/doc-processing-policy-seed`) that
> authors named pipelines with real processor lists — `no-entities-relations` and `all` on the
> `miner` staging database — through the exact mechanism this DR describes (`kb.pipelines` rows,
> a `kb.pipeline_policies` draft→compile→activate lifecycle). This is a different naming scheme
> again (neither the original `default`/`standards`/`narrative`/`minimal` illustration nor the
> P1-seeded `legacy_default`/`store_default`/`request_override` placeholders) — operator-chosen
> names for a real, if still small, deployment. §15.1's corresponding outstanding-work row is
> marked resolved-in-part.

**Tier 2 — binding policy.** A versioned policy decides which pipeline applies, and may refine
individual processor decisions.

```text
kb.pipeline_policies   policy_id, version, status, source_ref, checksum,
                       activated_at, activated_by
kb.pipeline_bindings   binding_id, policy_id, priority, scope_kind (system|tenant|
                       knowledge_store|user|document), scope_key, predicate JSONB,
                       pipeline_id, pipeline_version, reason_template, source, approved_by
kb.pipeline_rules      rule_id, policy_id, priority, target_processor,
                       effect (require|enable|skip|defer), predicate JSONB,
                       required_facets, reason_template, source (config|module|human),
                       source_module_release_id, approval_status, approved_by
```

> **2026-08-08 status (verified against code): `kb.pipeline_bindings`'s real schema doesn't match
> the `scope_kind`/`scope_key` columns shown above.** There are no such columns. "Scope" is
> derived at *read* time by a SQL `CASE` expression over which of `ks_store_id`/`user_id`/
> `tenant_id`/`input_record_id` is populated on the row (`server/api/doc-processing/
> pipeline_bindings.go`, `policy_compile.go`) — `binding_kind` is real (`'conditional'` or
> `'store_default'`), and a `'store_default'` row with `ks_store_id` set is store-scoped, or
> `ks_store_id IS NULL` is system-wide. `policy_id`, `priority`, `predicate`, `pipeline_id`,
> `approved_by` and friends are all real columns; only the illustrative `scope_kind`/`scope_key`
> pairing above is not how it was actually built.

A binding may be as simple as "knowledge store `KS-Project-A` → pipeline `standards@2`" with no
predicate at all — which is exactly the case C5 could not express — or predicated on document
facets for finer control.

Every run writes an immutable **execution plan**: the policy version, the selected pipeline and
why, the facet snapshot, and per processor the decision, the winning rule id, the reason, and the
cost class. "Why did `extract_metrics` not run on record 4711?" becomes an API call rather than log
archaeology, and a run remains reproducible after the policy changes.

> **2026-08-08 status (verified against code):** the plan is not a `kb.doc_process_runs.plan`
> column — `CreateDocProcessRun` never writes one. It lives in a separate, more granular table,
> `kb.doc_process_plans` (plan_facts/plan_steps/pipeline_selection/pipeline_binding/pipeline_spec/
> excluded_by_policy), FK'd to the run, exposed via real endpoints `GET /api/v1/kb/doc-proc-plans`
> and `/latest` (`kbhandler/doc_proc_log_handler.go`). No frontend dashboard panel consumes this API
> yet — it is API-only today (`web/src` has no references).
>
> **2026-08-09 correction: the previous sentence here (\"`kb.knowledge_store_bindings` does not
> exist; the store-default pipeline is a `default_pipeline` column\") was itself already stale the
> day it was written.** Migration `20260731000003` adds that column, but migration
> `20260731000006` — dated the same day, later in sequence — **drops it again** and replaces it
> with `kb.pipeline_bindings` (`ks_store_id → pipeline_id`, one row per store per policy version,
> FK-enforced against `kb.pipelines`; the migration's own comment says it "replaces" the free-text
> column as "the authored store->pipeline binding the ADR names"). Both edits landed before this
> status note was recorded, so the note described an intermediate state that no longer existed —
> a reminder that a same-day "verified against code" timestamp is not a version pin. As of
> 2026-08-09, re-verified directly against the live `miner` database schema:
>
> - **Doc Processing Policy storage.** `kb.pipeline_policies` (id, version, status
>   `draft|active|archived`, source_ref, checksum, activated_at, activated_by) is the policy
>   itself — a partial unique index enforces at most one `active` row at a time. Full create +
>   activate CRUD exists: `POST /kb/pipeline-policies` mints a new draft (`version =
>   MAX(version)+1`), `POST /kb/pipeline-policies/:id/activate` atomically activates it and
>   archives whatever was previously active. There is deliberately no update/delete on the policy
>   row itself: it is a versioned, append-only audit trail (governance data, not a mutable
>   config row) — you edit a *draft's content* (its bindings/rules) and activate a new version,
>   rather than mutating a past one.
> - **Knowledge-store ↔ policy association.** `kb.pipeline_bindings` (`ks_store_id → pipeline_id`,
>   scoped to `policy_id`, unique per `(ks_store_id, policy_id)`) plus `kb.pipeline_rules` for
>   conditional matching (`match_input_doc_type`/`match_source_language`/
>   `match_knowledge_store_binding` → `pipeline_id`, also scoped to `policy_id`, with `priority`).
>   Both have full CRUD (`GET`/`POST`/`PUT`/`DELETE` at `/kb/pipeline-bindings` and
>   `/kb/pipeline-rules`).
> - **System-default policy.** Confirmed: migration `20260731000011_create_kb_pipeline_policies.sql`
>   seeds a bootstrap policy (`version 1, status active, source_ref 'bootstrap', activated_by
>   'system'`) if none already exists, so there is always exactly one active policy from first
>   boot — the "no active policy means legacy behavior" invariant this DR relies on elsewhere
>   never has to hold in practice, because there is always an active policy.
> - **`kb.knowledge_store_bindings` — confirmed still does not exist, but that gap no longer
>   blocks anything this DR needs.** DR18 originally envisioned one bindings table covering four
>   things: (1) default pipeline, (2) requested-pipeline override, (3) bound governed-module
>   *releases* per store, (4) default *review profiles* per store. Items 1–2 shipped through the
>   mechanisms just described (`kb.pipeline_bindings`/`kb.pipeline_rules`, and
>   `kb.inputs.requested_pipeline`). Items 3–4 — per-store module-release pinning and default
>   review profiles — were never built under any table name and remain open DR18 work,
>   independent of pipeline routing; see §15.1.

### 3.8 DR7 — Selection precedence; conflicts and undetermined decisions block, loudly

**Precedence for pipeline selection**, highest first:

1. an explicit processor list in the event payload (`operation` / `doc-processors`) — a direct
   override that bypasses pipeline selection entirely;
2. an explicit pipeline named by the user **when the document was added**, persisted on
   `kb.inputs.requested_pipeline` and carried into every rerun of that record;
3. a run-scoped override recorded in the run record (Dev Mode, admin GUI);
4. matching `kb.pipeline_bindings`, by descending priority, then by narrowest scope
   (`document` > `user` > `knowledge_store` > `tenant` > `system`);
5. the knowledge store's default pipeline (DR18);
6. the system default pipeline.

**Precedence for processor gates** within the selected pipeline: explicit request > run override >
`kb.pipeline_rules` by descending priority > at equal priority, the more specific predicate (more
bound facets) > still tied and conflicting, `require` > `skip` > `enable`.

**When that does not resolve — block.** Two unresolved outcomes exist: a *binding conflict* (two
bindings of equal priority and equal specificity select different pipelines) and an *undetermined
gate* (rules leave a processor undecided after the tie-breaks above). Both are policy defects, not
document defects, and silently guessing hides them from the only people who can fix them.
Therefore, by default:

* the run fails fast with `pipeline_state = failed` and a specific error naming the conflicting
  rule or binding ids;
* a row is written to `alarms_errors` (severity `error`) so it surfaces in the existing alarms
  page;
* no processor runs, so no partial artifacts are produced from an ambiguous plan.

`DOC_PIPELINE_ON_CONFLICT` selects the behavior: `block` (default, current maturity) or
`fallback`. Under `fallback` — intended for later product maturity, and implemented now so the
ladder is not retrofitted under pressure — the planner walks the escalation ladder
`document → knowledge store → user → tenant → system default pipeline`, uses the first
unambiguous level, and still records the conflict as a `warning` alarm plus a plan annotation.
For an undetermined *gate* under `fallback`, the processor's `OnUndetermined` applies.

`mandatory` processors are never gated. With **no policy activated**, the planner reproduces
today's behavior exactly from `[doc-processing].required_processors`, so DR5–DR7 ship with zero
behavior change and are enabled per environment.

This mirrors spec §12.3 in spirit — an unresolved conflict is always an explicit signal, never a
silent implicit winner — but differs in consequence: review returns `indeterminate` and continues,
whereas extraction stops, because producing artifacts under an ambiguous plan corrupts everything
downstream of it.

### 3.9 DR8 — Semantic association is Phase D of the pipeline, not a separate service

The spec §10 association pipeline is realized as three declared stages that run after Phase C:

| Stage | Role |
|---|---|
| `normalize_assertions` | per-artifact-family normalizers (registry, DR11 seam 5) turn metrics/provisions/inventory/entity/scene artifacts into candidate qualified assertions with evidence |
| `associate_semantics` | spec §10.3–§10.7: generate candidates → resolve targets → validate → adjudicate → persist to the one authoritative owner |
| `project_semantics` | spec §10.8: build derived edges, search payloads, convenience classifications; mark and repair stale projections |

Backlog and deferred work reuse existing infrastructure rather than inventing new: `kb.scheduled_jobs`
for periodic drains, and the drain pattern already established for ambiguous object
reconciliation (ADR 2026070701 DR5/DR6/DR7 — bulk endpoint, admin review page, confidence-gated
LLM adjudication). Deferred candidates are retried only when their dependency fingerprint changes
(spec §10.9).

### 3.10 DR9 — Physical representation of assertion references (closes spec §17 open decision 1)

Typed reference pairs with a fast path, not polymorphic foreign keys and not opaque text:

```sql
subject_ref_kind  TEXT NOT NULL CHECK (subject_ref_kind IN
                  ('object_node','ontology_term','assertion','artifact','literal'))
subject_ref_id    TEXT NOT NULL
subject_object_id TEXT REFERENCES kb.object_nodes(object_id)   -- populated iff kind='object_node'
```

`object_ref_*` mirrors this. The `*_object_id` fast-path column carries the referential integrity
and the index for the dominant query shape ("all assertions about this referent") while the
generic pair keeps the model open. Normalized value columns
(`value_form`, `numeric_value`, `lower_value`, `upper_value`, inclusivity flags, `comparator`,
`unit_term_id`, `quantity_kind_term_id`, `raw_text`) live on the assertion per research §6.2;
`raw_text` is never dropped.

### 3.11 DR10 — Object classification uses the general assertion model plus a derived convenience column (closes spec §17 open decision 2)

Classification is an accepted assertion with predicate `core:instance_of`; roles use
`core:plays_role`. `kb.object_nodes.primary_class_term_id` is added as a **derived projection**
maintained by `project_semantics` — read-optimized, never authored, rebuildable, and explicitly
not the system of record. This keeps multiple simultaneous classifications, their evidence, and
their conflicts expressible (research §5.2) while keeping the common lookup cheap.

### 3.12 DR11 — Nine extension seams must exist before any domain content is authored

This is the ADR's answer to "embed the mechanisms so they can be developed incrementally,
gradually, and independently." Each seam is a Go registry interface plus, where applicable, a
database-backed registry, and each has exactly one rule: **adding an instance must not require
editing the mechanism.**

| # | Seam | Adding an instance means | Enables |
|---|---|---|---|
| 1 | `ProcessorRegistry` (DR5 declarations) | register a processor with a spec | new extraction stages |
| 2 | `FacetProducerRegistry` | register a producer + governed facet terms | new routing/profile signals |
| 3 | `PredicateOperatorRegistry` | register an operator | richer applicability rules |
| 4 | Module compiler + loader (DR2) | author module content as data in the database, then release | new ontology and domain content |
| 5 | `AssertionNormalizerRegistry` | register a per-artifact-family normalizer | new artifact families reaching L5 |
| 6 | `ProfileRuleKindRegistry` (evaluator + SHACL emitter as a pair) | register a rule kind | new conformance semantics |
| 7 | `ProjectionBuilderRegistry` | register a builder + repair function | new derived surfaces |
| 8 | `ReviewerToolRegistry` | register a tool (research §7.4) | ontology-aware reviewers |
| 9 | `IdentityFamilyRegistry` (DR15 kernel adapters) | register surfaces, nodes, normalizer profile, scoring, scope | new canonical identity families |

Seams 1–4 and 9 ship in P1–P2 and are what make the rest independently developable. A phase that
adds content through a seam is a data or registration change and can proceed in parallel with
other phases.

> **2026-08-08 status (verified against code):** seams 1–7 and 9 all exist as real Go registries
> with at least one real registered instance each (confirmed 2026-08-08). Seam 8
> (`ReviewerToolRegistry`) does **not exist anywhere in the repo** — zero registered tools, no
> matching type. A separate, architecturally unrelated `ReviewTool` registry
> (`server/api/doc-reviews/review-tools.go`, ~9 DB-query tools for the P5 LLM tool-use loop)
> predates this ADR and should not be conflated with seam 8.

### 3.13 DR12 — The pilot is one vertical slice: metrics, one domain module, one review question

**Metrics is the pilot artifact family**, confirmed: it is simultaneously the hardest test of the
framework (it needs properties, quantity kinds, units, assertion kinds, conditions, and
comparability before it works at all) and the focus of the product plan, so framework verification
and product progress are the same work rather than competing for it. Provisions follow, because
profile rules are sourced from them.

Spec §15.4 defines the pump acceptance suite. This ADR adopts that shape but binds it to the live
corpus: the pilot *domain module* is chosen in P0 from documents SemOS has already ingested, by
three criteria — enough documents to measure, an authoritative standard available as the profile
source, and a domain owner able to approve terms and rules. "Pump" remains the worked example in
the prior documents; the actual pilot module remains open (OD1).

Everything outside the pilot slice stays candidate-only: summaries, projections, topics, scenes,
and entity relations generate `SemanticDecisionCandidate` rows and nothing accepted, until P6
measures per-method precision (spec §15.5.7).

### 3.14 DR13 — Adopt the semantic-web standards at four distinct levels, not as a package deal

SemOS uses **none** of RDF, OWL, SKOS, or SHACL today: no dependency, no serialization, no
tooling, nothing in `go.mod`. Research §3.1 explains all four but does not say which to buy.
Treating them as one decision is the mistake; they occupy four levels with very different
cost-benefit.

| Level | Standard(s) | Decision | When |
|---|---|---|---|
| **Modeling discipline** — patterns copied into our own schema | SKOS label/mapping distinctions; SOSA's feature-of-interest / observed-property / procedure / result split; QUDT's quantity-kind / unit / dimension split; PROV-O's entity / activity / agent split | **Adopt now.** Cost ≈ 0, and it is the difference between a schema and a defensible model | P2 (4a modules) |
| **Data** — import published vocabularies as content | QUDT unit, quantity-kind, and dimension catalogs; SKOS-serialized external vocabularies for the pilot domain | **Adopt selectively.** Compile the published TTL into our module format via the DR2 compiler. This is the single highest-value use of the standards: unit semantics and conversion are months of work we do not have to invent | P2–P4 |
| **Serialization and interchange** — emit `.ttl` / `.jsonld` / SHACL shapes | RDF, OWL, SHACL | **Defer, keep the door open.** Generate only when an external consumer exists. The DR9 identifiers and DR2 releases are designed so this stays a projection, never a migration | P7 |
| **Runtime** — reasoner, triple store, SPARQL | OWL 2 DL reasoning, SPARQL endpoint | **Do not adopt.** OWL's open-world assumption is the wrong semantics for completeness review (research §3.3); the closed-world, scoped validation we need is exactly what we implement directly in SQL/Go | not planned |

Two consequences worth stating plainly:

* **SHACL is a shape language we are borrowing, not a runtime we are installing.** Profile rules
  (DR11 seam 6) are written in our own rule kinds with a SQL/Go evaluator; each rule kind also
  carries a SHACL emitter so the shapes can be published later. Spec §15.4.14 makes SQL-versus-SHACL
  parity a Phase 4 release gate; this ADR **moves that gate to P7**, because proving parity against
  a validator we do not run, for consumers who do not yet exist, would delay the pilot for no
  operational benefit. The emitters are still written in P4 — only the parity gate moves.
* **SKOS is where the keyword lexicon and the ontology terms meet** (DR15, DR16):
  `prefLabel` / `altLabel` / `hiddenLabel` become `label_role`, and `exact` / `close` / `broad` /
  `narrow` / `related` remain the only permitted mapping strengths, so lexical similarity can never
  be recorded as equivalence.

Postgres remains the system of record throughout (research §10.2 Option B, spec §4). A triple
store or reasoner is reconsidered only if a competency question demonstrably cannot be answered in
SQL/Go with materialized closure.

### 3.15 General Terms

#### 3.15.1 Ontology

An ontology is a governed model of the kinds of things SemOS recognizes, the properties that
connect them, and the constraints on those meanings. In this ADR, it is the seven-layer semantic
architecture, not merely a graph or a list of labels.

#### 3.15.2 Stable term

A stable term is a semantic identifier whose identity does not change when its label or
description is revised. A material change in intended meaning requires a new term and preserves
the history of the old one.

#### 3.15.3 Definition

A definition states the intended meaning and scope of a term. It is versioned and sourced so that
readers can distinguish a governed meaning from an informal label or usage example.

#### 3.15.4 Vocabulary / controlled vocabulary

A vocabulary is an organized set of approved terms and their labels. A controlled vocabulary adds
governance: terms, statuses, namespaces, versions, and permitted usage are managed explicitly.

#### 3.15.5 Taxonomy

A taxonomy arranges concepts in a hierarchy, usually from broader to narrower. A browsing
hierarchy is not automatically a logical class-inheritance hierarchy.

#### 3.15.6 Thesaurus

A thesaurus records concepts, synonyms, broader and narrower relationships, related terms, and
cross-scheme mappings to support consistent indexing and retrieval. It does not by itself assert
that a concept is a real-world object or a formal class.

#### 3.15.7 Subject heading system

A subject heading system is a curated vocabulary used to describe the topics of documents for
indexing and retrieval. Its headings can be imported or authored locally, but they become ontology
classes only through a separate approval decision.

#### 3.15.8 Classification scheme

A classification scheme organizes concepts or objects into governed categories for a purpose. In
SemOS, membership is an explicit, qualified assertion rather than an assumption about identity or
ontology class inheritance.

#### 3.15.9 Concept scheme

A concept scheme is a named, versioned grouping of concepts and their relationships, such as a
domain vocabulary or indexing system. Belonging to the same scheme does not make two concepts
equivalent.

#### 3.15.10 SKOS

SKOS is a W3C model for publishing controlled vocabularies and concept schemes, including labels,
hierarchies, related concepts, and mappings. SemOS adopts its useful modeling discipline and can
import or export SKOS content without installing a SKOS runtime.

#### 3.15.11 SKOS Concept / Concept

A SKOS Concept is an identifiable unit of meaning used in a concept scheme. In SemOS it is a
governed ontology term with labels, notes, hierarchy, and mappings; it is not automatically an
individual object or an OWL class.

#### 3.15.12 Preferred, alternative, hidden labels

These are label roles for a term: the preferred human-facing name, an accepted alternative name,
and a searchable variant that should normally be hidden from display. Each label is language- and
scope-aware.

#### 3.15.13 Synonym / acronym

A synonym is an alternative lexical expression for a concept, while an acronym is an abbreviated
form. Either may help resolve a mention, but lexical similarity alone does not prove semantic
identity.

#### 3.15.14 Mapping (`exact`, `close`, `broad`, `narrow`, `related`)

A mapping relates terms across vocabularies with an explicit strength: equivalent, approximately
aligned, broader, narrower, or merely related. The strength records the boundary of what can be
inferred and is deliberately more cautious than identity propagation.

#### 3.15.15 Knowledge graph

A knowledge graph is a network of entities, concepts, properties, and assertions, ideally with
provenance and qualification. SemOS implements the governed subset needed by its competency
questions rather than operating a generic triple-store platform.

#### 3.15.16 RDF

RDF is a graph data model in which resources and values are connected by named properties. In
SemOS it is a possible interchange projection; PostgreSQL remains the operational source of truth.

#### 3.15.17 RDF triple

An RDF triple is a subject–predicate–object statement. Qualified SemOS assertions may need a
reified or n-ary representation because modality, time, status, and evidence cannot be preserved
in one bare triple.

#### 3.15.18 IRI / URI

An IRI or URI is a globally structured identifier for a resource. SemOS uses stable identifiers
for modules, terms, profiles, and releases, while making them dereferenceable is deferred.

#### 3.15.19 RDFS class/property/subclass

RDFS provides basic vocabulary constructs: classes, properties, and subclass relationships. SemOS
represents approved versions of these constructs natively and can export them, but does not accept
arbitrary executable RDFS expressions.

#### 3.15.20 OWL

OWL is a Web Ontology Language for expressing classes, properties, and logical axioms. SemOS uses
selected modeling patterns and export forms, but does not use OWL as its runtime or storage engine.

#### 3.15.21 Class

A class is a governed category or type whose members share a defined meaning. In SemOS, an object
belongs to a class through a qualified classification assertion; an extracted category is not a
class by default.

#### 3.15.22 Individual

An individual is a canonical referent for one particular entity or instance, such as a specific
device. Its identity is managed separately from the classes and properties asserted about it.

#### 3.15.23 Collection / occurrence / type

These are distinct ontological levels: a collection groups members, an occurrence denotes an event
or happening, and a type denotes a kind rather than one instance. A referent may carry several
class assertions while retaining one explicitly recorded level.

#### 3.15.24 Object property

An object property relates one referent or term to another referent or term, such as `part_of` or
`issued_by`. Conditions, evidence, and other qualifiers belong to the assertion carrying the
property, not to the property definition alone.

#### 3.15.25 Datatype property

A datatype property relates a referent to a literal value with a declared value form, such as a
number, interval, date, or structured measurement. Metric values also require their unit and
conditions to be represented explicitly.

#### 3.15.26 Axiom

An axiom is a governed statement about how terms, properties, or classes may relate. SemOS stores
only compiler-approved axiom kinds so that every executable consequence is bounded and auditable.

#### 3.15.27 Inference

Inference is a derived conclusion computed from accepted terms, assertions, and rules. SemOS uses
named, deterministic SQL/Go derivations with traces rather than unrestricted logical reasoning.

#### 3.15.28 OWL reasoner / OWL 2 DL runtime

An OWL reasoner is software that computes logical consequences from OWL ontologies; OWL 2 DL is a
decidable expressive fragment with corresponding reasoning engines. SemOS does not plan to run one
because open-world reasoning does not answer its scoped completeness-review questions.

#### 3.15.29 `owl:sameAs`

`owl:sameAs` asserts that two identifiers denote exactly the same thing, with strong identity
propagation across all properties. SemOS does not apply it automatically; exact mappings and
separately adjudicated merge decisions are safer for ambiguous terms and objects.

#### 3.15.30 Extracted entity

An extracted entity is an evidence-bearing mention found in a document, such as a product name or
organization. It is a candidate artifact until governed reconciliation links it to a canonical
referent or term.

#### 3.15.31 Meaning of entities and relations

This is the governed interpretation of what an extracted entity denotes and what a relation means.
SemOS supplies that interpretation through class/property terms, qualified assertions, and
evidence rather than raw labels or free-text predicates.

#### 3.15.32 Relation / semantic assertion

A semantic assertion is a first-class claim about a subject, predicate, and object or value. It
also carries the qualifiers needed to interpret the claim, such as modality, time, status,
confidence, and evidence.

#### 3.15.33 Evidence / provenance

Evidence is the source material supporting or contradicting an assertion. Provenance records where
the evidence came from and who or what produced the claim, including model, prompt, run, and human
review history.

#### 3.15.34 Constraint / business rule

A constraint or business rule states a condition that data must satisfy for a given scope or
purpose. SemOS represents it as a typed profile rule evaluated with explicit, closed-world review
semantics.

#### 3.15.35 SHACL Shape

A SHACL Shape describes the structure and validation conditions expected for RDF data. SemOS pairs
each supported profile-rule kind with a SHACL export form, while the native rule remains the
SQL/Go model.

#### 3.15.36 SHACL validator/runtime

A SHACL validator is software that checks RDF data against SHACL Shapes. SemOS may use one for CI,
parity checks, or interoperability later, but production evaluation remains in SQL/Go.

#### 3.15.37 Profile / application profile

A profile is a scoped and versioned statement of what should be present or true for a review,
class, jurisdiction, or operating context. It governs expectations and rules; it is not itself a
class or a document artifact.

#### 3.15.38 PROF profile metadata

PROF is a vocabulary for describing profiles and their relationships to specifications,
implementations, and artifacts. SemOS can publish this metadata, but its native profile records
remain authoritative and no PROF runtime is required.

#### 3.15.39 Open-world semantics

Open-world semantics treats an unrecorded fact as unknown rather than false. SemOS preserves this
meaning for ontology data, so absence becomes a finding only when a profile explicitly closes the
relevant review dimension.

#### 3.15.40 Closed-world validation

Closed-world validation evaluates a frozen scope against explicit rules and treats the checked
universe as complete for that review dimension. SemOS applies closure locally and intentionally,
never as a global assumption about all knowledge.

#### 3.15.41 Topic

A topic is an existing document-processing artifact that summarizes or labels a subject discussed
in a document. It may be linked to governed concepts, but a matching label does not make it an
ontology concept.

#### 3.15.42 Category

A category is an existing retrieval or navigation concept used to organize artifacts. It may later
receive a governed mapping, but category membership does not by itself mean RDF type or subclass
membership.

#### 3.15.43 Keyword

A keyword is a surface expression found or assigned in text. SemOS resolves it through a governed
lexicon and may align it to an ontology term, while keeping lexical concepts distinct from the
terms that define domain meaning.

#### 3.15.44 Search similarity / embedding

Search similarity and embeddings estimate how closely two texts or representations resemble one
another. They are useful for candidate generation, but never by themselves activate identity,
classification, mappings, or axioms.

#### 3.15.45 QUDT quantity kind/unit/dimension

QUDT is an external vocabulary for quantity kinds, units, dimensions, and related measurement
semantics. SemOS selectively imports its catalog into the `quantity` core module and releases the
validated content through its compiler.

#### 3.15.46 SOSA/SSN measurement pattern

SOSA/SSN is a W3C modeling pattern for sensors and observations, including a feature of interest,
observed property, procedure, and result. SemOS adopts the useful measurement distinctions without
requiring a SOSA/SSN runtime dependency.

#### 3.15.47 PROV-O

PROV-O is an ontology for provenance centered on entities, activities, and agents. SemOS uses that
pattern in native audit structures and may map it to RDF later; the native audit tables remain
authoritative.

#### 3.15.48 OWL-Time / temporal ontology

OWL-Time is a vocabulary for describing temporal entities and relationships. SemOS adopts the
interval concepts needed for valid, effective, and transaction time, but does not plan a general
temporal reasoner.

#### 3.15.49 SPARQL endpoint

SPARQL is the query language and protocol commonly used for RDF graphs. SemOS serves operational
queries through SQL and APIs; an endpoint would be reconsidered only if a competency question
cannot be met otherwise.

#### 3.15.50 Triple store

A triple store is a database optimized for RDF subject–predicate–object data and graph queries.
SemOS does not add one because it would duplicate PostgreSQL storage and lifecycle without a
demonstrated need.

### 3.16 Terminology implementation contract

The support labels mean:

* **Native** — represented and governed directly in SemOS operational stores and APIs.
* **Existing artifact** — already exists in document processing but is not ontology content by default.
* **Selective import** — external content is compiled into the native model.
* **Projection** — generated for interchange; not the operational source of truth.
* **Deferred** — extension seams are preserved, but implementation requires a demonstrated need.
* **Not planned** — deliberately excluded from the architecture.

| General term | SemOS implementation mapping | Support and phase | Boundary or reason if not fully supported |
|---|---|---|---|
| Ontology | The seven-layer semantic architecture plus governed core/domain modules | **Native, P2–P4** | Operationally relational; it is not synonymous with the navigation graph |
| Stable term | Immutable `term_id` and stable IRI in a released ontology module | **Native, P2** | A material meaning change creates a replacement term rather than mutating identity |
| Definition | Versioned term definition with release and provenance | **Native, P2** | Labels may change; changed intended referents require a new term |
| Vocabulary / controlled vocabulary | Released terms, multilingual labels, definitions, statuses, and namespaces | **Native, P2** | Does not by itself imply class logic or inference |
| Taxonomy | Explicit conceptual `broader`/`narrower` or formal class `subClassOf`, kept distinct | **Native, P2** | Browsing hierarchy is never silently promoted to class inheritance |
| Thesaurus | Concept labels, synonyms, acronyms, `broader`/`narrower`/`related`, and mappings | **Native, P2–P3** | The supported subset lives in the term registry and lexicon; there is no standalone thesaurus-management product |
| Subject heading system | Imported or locally authored concept scheme used for indexing and mapping | **Selective import, P2–P4** | Headings remain retrieval concepts unless separately approved as ontology classes |
| Classification scheme | Governed concept scheme plus mappings; class membership uses qualified assertions | **Native, P2–P3** | Scheme membership, object classification, and canonical identity are separate decisions |
| Concept scheme | Namespace/release grouping for `concept` terms and their hierarchy | **Native, P2** | Scheme boundaries do not create identity equivalence |
| SKOS | Label/mapping/concept-scheme discipline; compiled external vocabularies; generated SKOS artifacts | **Native, P2–P3; Selective import, P2–P4; Projection, P7** | SemOS adopts the useful model and interchange format, not a separate SKOS runtime |
| SKOS Concept / Concept | `kb.ontology_terms.term_kind = concept` with labels, notes, hierarchy, and mappings | **Native, P2** | A concept is not automatically a real-world individual or OWL class |
| Preferred, alternative, hidden labels | `kb.ontology_term_labels` with language and label type | **Native, P2** | One released preferred label per configured language/scope |
| Synonym / acronym | Alternative/acronym term labels; keyword surfaces remain in the lexicon | **Native, P2–P3** | Lexical equivalence does not prove semantic identity |
| Mapping (`exact`, `close`, `broad`, `narrow`, `related`) | Governed `kb.ontology_mappings` with evidence and approval | **Native, P2** | Conservative mappings replace automatic `owl:sameAs` |
| Knowledge graph | Qualified assertions and canonical referents, with selected navigation projections | **Native, P3–P4** | SemOS supports the governed subset needed by competency questions, not a generic triple store; `kb.artifact_connections` remains a derived navigation graph |
| RDF | `.ttl`/JSON-LD projection of released terms, assertions, and profiles | **Projection, P7** | PostgreSQL remains the operational source of truth |
| RDF triple | Export view of a governed term, mapping, classification, or assertion | **Projection, P7** | Qualified assertions may require RDF reification/n-ary patterns, not one lossy triple |
| IRI / URI | Stable external identifier for modules, terms, profiles, and releases | **Native, P2** | Dereferenceable publication is P7 |
| RDFS class/property/subclass | Native term kinds and explicit axioms with RDFS export | **Native, P2; Projection, P7** | Only approved axiom kinds are executable |
| OWL | Selected class/property/axiom discipline and generated ontology artifacts | **Native, P2; Projection, P7** | Native support is limited to compiler-approved constructs; SemOS does not adopt OWL as its runtime or storage engine |
| Class | `term_kind = class`; membership is a qualified classification assertion | **Native, P2–P3** | Categories and extracted entity types are not classes by default |
| Individual | `kb.object_nodes` referent with `ontological_level = individual` | **Native, P2** | Identity is managed by `semid`, separately from classification |
| Collection / occurrence / type | Other governed `ontological_level` values on canonical referents | **Native, P2** | These levels are mutually distinguished but may have several class assertions |
| Object property | Governed property term whose value is another referent/term | **Native, P2–P3** | Assertion qualifiers live on the assertion, not the property term |
| Datatype property | Governed property term whose value has a declared literal/value form | **Native, P2–P3** | Metric values use structured value/unit/condition contracts |
| Axiom | Released `kb.ontology_axioms` row using a compiler-approved axiom kind | **Native, P2** | Support is limited to compiler-approved kinds; arbitrary OWL expressions are not accepted |
| Inference | Named, deterministic SQL/Go derivations with trace and bounded semantics | **Native, P2–P4** | Support is bounded and named; open-ended description-logic inference is not planned |
| OWL reasoner / OWL 2 DL runtime | None | **Not planned** | Open-world reasoning does not answer scoped completeness review and adds unjustified runtime cost |
| `owl:sameAs` | No automatic equivalent; use governed exact/close mappings and merge decisions | **Not planned** | Automatic `owl:sameAs` is excluded because its identity propagation is too strong for lexical or conceptual similarity |
| Extracted entity | Evidence-bearing artifact mention, optionally bridged to a referent or term | **Existing artifact; Native, P3–P4** | The native work is the governed bridge; extraction output remains a candidate, not authoritative ontology content |
| Meaning of entities and relations | Governed class/property terms plus qualified assertions and evidence | **Native, P2–P3** | Raw entity types and free-text predicates do not define meaning |
| Relation / semantic assertion | First-class qualified assertion with subject, predicate, object/value, modality, time, status, and evidence | **Native, P3** | Not stored solely as an unqualified graph edge |
| Evidence / provenance | One-to-many assertion evidence and producer/model/prompt/human audit records | **Native, P3** | Evidence supports or contradicts; it does not overwrite the source artifact |
| Constraint / business rule | Typed profile rule evaluated in SQL/Go | **Native, P4** | Rules are scoped and closed-world, unlike absence-based OWL conclusions |
| SHACL Shape | Paired export form for each supported profile rule kind | **Native, P4; Projection, P7** | The native construct is the paired rule model; no SHACL runtime is required in production |
| SHACL validator/runtime | External parity/validation tool in CI or interoperability testing | **Deferred, P7** | The production evaluator remains SQL/Go to preserve operational behavior |
| Profile / application profile | `kb.ontology_profiles` plus applicability scope, release, and typed rules | **Native, P4** | A profile governs “what should be”; it is not a class or document artifact |
| PROF profile metadata | Publication metadata linking a profile to specifications and artifacts | **Projection, P7** | No separate PROF runtime; native profile records are authoritative |
| Open-world semantics | Preserved for ontology meaning and unknown facts | **Native, P2–P4** | This is a semantic boundary rather than a separate runtime: missing facts are unknown unless a profile explicitly closes a review dimension |
| Closed-world validation | Frozen review scope plus profile rules and findings | **Native, P4** | Closure is explicit per profile/dimension, never global |
| Topic | Existing generated topic artifact; optional grounded links to concepts/terms | **Existing artifact; Native, P6** | The native work is grounded association; a topic is not an ontology concept merely because labels match |
| Category | Existing retrieval/navigation concept; candidate for governed mapping | **Existing artifact; Native, P4** | P4 retrofits canonicalization/mapping; `belong_to` does not imply `rdf:type` or `subClassOf` |
| Keyword | Surface mention resolved to a lexicon concept and optionally `aligns_to_term` | **Native, P3** | The native construct is the lexicon; keyword concepts and governed ontology terms remain separately governed |
| Search similarity / embedding | Candidate-generation evidence | **Native, existing** | This existing capability remains non-authoritative: similarity never activates identity, class membership, mappings, or axioms |
| QUDT quantity kind/unit/dimension | Published catalog compiled into the `quantity` core module | **Selective import, P2** | Imported content is pinned, validated, and released through the module compiler |
| SOSA/SSN measurement pattern | Feature-of-interest, observed-property, procedure, result pattern | **Native, P2–P3** | SemOS adopts the useful modeling subset, not a mandatory SOSA/SSN runtime dependency |
| PROV-O | Entity/activity/agent provenance pattern and later RDF mapping | **Native, P2–P3; Projection, P7** | Native audit tables remain authoritative |
| OWL-Time / temporal ontology | Valid/effective interval pattern and later mapping | **Native, P2–P4; Projection, P7** | Native support is limited to the required interval model; no general temporal reasoner is planned |
| SPARQL endpoint | None | **Not planned** | SQL/API serve operational queries; reconsider only if a competency question cannot be met |
| Triple store | None | **Not planned** | Duplicates PostgreSQL storage and lifecycle without a demonstrated competency need |

Any ontology-related term not in this contract is unsupported until an ADR maps it to a SemOS
construct, lifecycle phase, and semantic boundary.

### 3.17 DR15 — One canonicalization kernel, instantiated per identity family

This resolves C4. Rather than a fourth bespoke resolver, extract the shared machinery into one
kernel (`semid`) with a family-parameterized contract, and instantiate it.

The kernel owns, once:

```text
normalize(surface, normalizer_version) -> key bundle
generate candidates  (exact key | alternate keys | trigram | vector | blocking)
score deterministically
adjudicate           (auto-accept | ambiguous | defer | LLM batch | human)
link                 mention -> canonical node, with status and evidence
merge / split        tombstones, never deletes; no transitive closure
audit                append-only decision log with full provenance
```

Family instantiations declare only what differs: the surface store, the canonical node store, the
normalizer profile, the scoring weights, the auto-accept policy, and the scope dimension.

| Family | Surfaces | Canonical nodes | Scope | Status |
|---|---|---|---|---|
| Objects | `kb.artifact_objects` | `kb.object_nodes` | identity scope (plant, org, KS) | live — adopts the kernel *contract* incrementally (DR15.1) |
| Keywords | `kb.keyword_surfaces` + mentions | `kb.keyword_concepts` | knowledge store, domain, document | new, P3 |
| Categories | category assignments | `kb.artifact_categories` | tenant, KS | retrofit, P4+ |
| Ontology terms | `kb.ontology_candidates` | `kb.ontology_terms` | module | new, P2 — governed, so adjudication ends at a change set rather than an auto-accept |

**DR15.1 — the live families are not rewritten.** `kb.object_nodes` keeps its current scorer and
tie-break behavior (ADR 2026070701) until kernel fixtures prove parity on a labeled set. What it
adopts first are the kernel's *contracts*: explicit scope, tombstone merges, and the shared
decision log. Categories follow. Only new families start on the kernel outright.

> **2026-08-08 status (verified against code):** the kernel package lives at
> `server/api/ontology/semid/`, not `server/api/semid/`. `TermFamily` and `KeywordFamily` are real
> `FamilyAdapter` instantiations. Adjudication has 4 verdicts in code
> (`auto_accepted`/`ambiguous`/`deferred`/`human_review`) — no distinct "LLM-batch" verdict exists.
> DR15.1's claim that the live object family "adopts the kernel's contracts first" is scaffolding
> only: `kb.object_nodes.merged_into`/`scope_key` columns exist, but the object reconciler
> (`entity_object_reconciliation.go`) never reads or writes them (0 of 893 live rows populated) —
> the comment there says plainly it doesn't yet. Merge/split-with-tombstone, no-transitive-closure
> logic is real and tested, but currently only for the keyword family, not inside `semid` itself.

**DR15.2 — lexical concepts are to ontology terms as object nodes are to ontology classes.**
A keyword concept is an ungoverned canonical *lexical* identity: fast, high-volume, auto-mergeable
under guardrails, and good enough for search expansion. A governed ontology term is a reviewed
*meaning* with a definition, an owner, and a release. They are connected by an accepted
`aligns_to_term` assertion, exactly as an object node is connected to its class by `instance_of`.
This keeps one governed vocabulary (spec §11.3: "canonical conceptual meaning belongs in
`kb.ontology_terms`") without forcing every one of a hundred thousand surface forms through a
module release.

### 3.18 DR16 — The two keyword specs are merged, taking the identity layering from one and the storage from the other

Specs `2026072301` and `2026072703` describe the same module and disagree in ways that matter.
Neither is adopted whole. The merged design is the DR15 keyword instantiation, taking:

**From `2026072703` (File 7) — the model and the guardrails:**

* the four-layer identity stack (occurrence → surface → lexform → concept), with `lexform` as the
  working-mode index key. This is the load-bearing idea in either document, and it is what makes
  deterministic O(1) resolution and a re-indexable normalizer possible;
* store surfaces, derive keys, version the normalizer — a normalizer change becomes a re-index,
  not data loss;
* merges are tombstones (`merged_into`), never deletes;
* `never_merge` negative assertions; human assertions locked against the reconciler;
* **no transitive closure** over pairwise merge decisions;
* `alias_type` drives mechanical validation (an `acronym` is checkable against its target's label;
  a `misspelling` must be a hidden label; a `translation` must differ in language);
* the token-economics discipline: harvest → prune → block → batch → decide → validate → apply,
  with negative caching so an unchanged item is never re-sent to a model.

**From `2026072301` (File 6) — the ChenWeb integration:**

* the `kb.` schema and Postgres storage, the mention/observation table, the reconciliation-run and
  resolution-log records, and the API surface shaped like the rest of the platform;
* ambiguity as a first-class stored result rather than an error;
* the seeding strategy and the online/reconciliation/candidate metric split.

**Rejected from both:** File 7's SQLite-first storage recommendation (SemOS has multiple writers,
already runs `pg_trgm` and `pgvector`, and needs one backup and migration story — the trigram
caveat for short acronyms is real and is handled by keeping short keys on the exact-key path);
and both specs' assumption that the keyword module owns its own reconciliation engine, which DR15
replaces with the shared kernel.

The merged result is written as **one** spec superseding both, before implementation begins.

> **2026-08-01 status:** Done. The merged spec is `2026080101-spec-keyword-canonicalization-merged.md`.
> The keyword-lexicon *code* it describes remains deferred — see the P3 implementation log — but the
> design disagreement DR16 exists to resolve is closed.

### 3.19 DR17 — Ontology and policy data live in their own repository, versioned and pinned like a dependency

> **2026-07-31 storage revision:** the dedicated repository is **not created**. Per the workspace
> storage principle (data lives in the database; shareable code in `shared`; project-specific code
> in `ChenWeb`), ontology and policy content is stored and versioned in the database. The lifecycle
> and reproducibility properties DR17 wanted (independent cadence, reproducible releases) are
> carried by versioned content rows plus immutable, checksummed releases.

Data-as-code is the right instinct, and the repository must not be the code repository.

**Decision:** a dedicated repository (working name `semos-ontology`) holds:

```text
modules/                 # DR1/DR2 ontology modules — 4a core, 4b domain
policies/pipelines/      # DR6 named pipelines
policies/bindings/       # DR6 binding policies
lexicon/seeds/           # DR16 curated seed terms and never_merge assertions
fixtures/                # conformance and competency fixtures
```

Rationale:

* **Different lifecycle.** Ontology content changes when the domain or the corpus changes — which,
  as noted, is constantly — while application code changes when features change. Coupling them
  forces every term fix through a code release and every code release to re-validate ontology
  content.
* **Different authors and access.** Domain curators and profile owners need write access to
  meaning without write access to the server.
* **Different CI.** The ontology repository's CI runs the compiler, validation, competency
  questions, and fixture suites — not Go builds.
* **Not `KnowledgeStore` either.** `KnowledgeStore` is human-authored prose under its own Git
  repository; this is machine-consumed, compiler-validated data with per-module semantic
  versioning. Different consumers, different validation, different tags (`pump/0.1.0`).

Binding to the running system: a release record stores the **source commit SHA plus the content
checksum**, so a release is reproducible from the data repository alone, independent of code
history. Deployments pin an ontology revision (`ONTOLOGY_REPO_REF`) exactly as they pin a
dependency; activation remains the separate audited act of DR2.

This also settles OD3 from the first draft: pipeline policies are data in the same repository,
compiled and activated by the same mechanism, so pipelines get versioning, review, and rollback
for free rather than accumulating in `config.toml`.

### 3.20 DR18 — Knowledge stores are both a routing key and a scope key

`kb.knowledge_store` becomes load-bearing (C5):

1. **Membership.** `kb.inputs` gains `ks_id` (nullable FK) and `requested_pipeline`, set at
   ingestion. Documents without a store fall to the tenant default store.
2. **Routing.** `ks_id`, `ks_type`, and tenant enter the planner's fact set, so a binding can be
   as simple as "`KS-Project-A` → `standards@2`" (DR6 tier 1). This is the literal expression of
   "run pipeline A on knowledge store K1, unless otherwise specified" — the "unless otherwise
   specified" being DR7 precedence levels 1–3.
3. **Scope.** The knowledge store is the default scope value for the DR15 kernel and for review
   applicability: object `identity_scope`, keyword concept `scope`, and profile applicability all
   default to it. This is what lets *ML* resolve to machine learning in `KB-Blogs` and to
   millilitre in a clinical store, and it lets two projects hold conflicting canonical objects
   without cross-contamination.
4. **Ontology visibility.** A knowledge store may bind a set of active ontology module releases,
   so a project-oriented store sees only its domain's vocabulary. Binding is additive over the
   core 4a modules, which are always visible.

```text
kb.knowledge_store_bindings
  ks_id, default_pipeline_id, default_pipeline_version,
  module_release_ids JSONB, default_review_profile_ids JSONB,
  scope_key, created_at, created_by
```

Purpose-oriented stores (`KB-Blogs`, `KB-Products`, `KB-Marketing-and-Sales`) and
project-oriented stores (`KS-Project-A`) then differ by data, not by code: a different pipeline,
a different module set, a different scope — all three expressed as bindings.

> **2026-08-08 status (verified against code):** items 1-2 are real but under different names than
> planned: the FK on `kb.inputs` is `ks_store_id` (pre-existing, migration `20260425000002`, predates
> this ADR), not `ks_id`; `requested_pipeline` is real and genuinely set at ingestion
> (`kbhandler/upload_handler.go`); `facet_summary` (trigger-maintained JSONB) does not exist —
> `kb.doc_facets`/`kb.doc_facet_values` serve that role instead (§3.5). Items 3-4 (module-release
> and default-review-profile bindings per store) and the `kb.knowledge_store_bindings` table itself
> are **not built** — confirmed absent from the repo — consistent with §8.3.7's own "remaining P4
> work" admission.

### 3.21 DR20 — Product-hood and part-hood are roles, not classes; the part hierarchy is first-class

A nut is a component inside a machine and a product at the plant that makes it. If `Product` were
an ontology class, that nut would need two incompatible classifications, and every downstream rule
keyed on class would fork.

Decision: `product` and `component` are **roles** (`core:plays_role`), scoped and relative to a
context (a manufacturer, a bill of materials, a catalog). The nut's class stays what it is —
`fastener:hex_nut` — while it plays `product` in the fastener plant's scope and `component` in the
ventilator's bill of materials. Roles change without touching identity or classification, exactly
as research §5.2 requires.

The part hierarchy itself becomes first-class in the 4a `core` module, because the application
navigates it (product → 7 modules → sub-parts):

```text
core:part_of          transitive, scoped to a product configuration/revision
core:component_of     immediate parent (non-transitive, for display)
core:variant_of       alternative part fulfilling the same function
```

**Metric scope across the hierarchy must be explicit and must not merge.** A metric asserted about
显示面板 is visible when viewing 显示屏模块, but it is not the same assertion as a module-level
metric. Every assertion therefore records the level at which it was asserted, and roll-up queries
return the asserted level alongside the value. Aggregation across levels is a display decision with
provenance, never a silent merge — that distinction is what keeps "8 项指标" for a module honest.

### 3.22 DR21 — Requirement strictness is a computed partial order; verdicts are directional and distinct from recommendations

The application's most valuable column is the verdict, and the six review result categories of
spec §12.4 (`satisfied`, `missing`, `conflicting`, `nonconforming`, `inapplicable`,
`indeterminate`) cannot express it. They answer "does this document satisfy this rule?" The
application asks "how does requirement A compare with requirement B?" — which needs direction.

**The strictness relation.** After normalizing two assertions to the same property, quantity kind,
assertion kind, condition set, and unit dimension, each constraint denotes a satisfying set of
values. Then:

```text
A ≡ B   equal satisfying sets                          → identical
A ⊂ B   satisfying A implies satisfying B              → A is stronger
A ⊃ B   satisfying B implies satisfying A              → A is weaker
A ∩ B = ∅   no value satisfies both                    → conflict
otherwise, sets overlap without containment            → incomparable
```

This is deterministic for numeric bounds, intervals, tolerances, and enumerations once units are
converted — `≥250 cd/m²` versus `≥200 cd/m²` is decidable; `≤120 ms` versus `≤150 ms` is
decidable. It is *not* decidable when one side is qualitative ("预期环境下清晰可见" carries no
satisfying set), which is precisely why the application shows 需验证 there. The comparator must
return that outcome rather than guess.

**Built:** `ChenWeb/server/api/ontology/comparison` (`Compare`, `EvaluateFamily`) implements this
relation as a pure function — no database, no pipeline — over `lower_bound`, `upper_bound`,
`exact_value`, `range`, `qualitative`, and `limit_absent` constraint forms, with a minimal linear
unit registry standing in for the DR13 `quantity` module until it exists. `EvaluateFamily` adds the
`standard_absent`/`not_applicable`/`indeterminate` layer per DR21 rule 2. Its test suite includes
`gold_fixture_test.go`, which loads the DR12 gold fixture directly and reproduces all 36 hand-derived
expected verdicts — the fixture and the comparator now check each other on every test run.
`ChenWeb/benchmark/doc-processors/gold/display-module-v1/generate.go` closes the DR25 grounding loop
for this same fixture: it builds a real CDM `model.Document` per authority document (one paragraph
block per clause) and its test round-trips one through the actual Typst renderer and
`ExtractAnchors`/`DeriveFragments` — a real `typst` compile, not a mock — confirming every clause
gets an exact anchor.

**Built:** `ChenWeb/server/api/doc-benchmark/verdict_score.go` — `ScoreVerdictMatrix`, the outcome
scorer the benchmark ADR §3.4 flags as not yet defined. It is a pure function over
`[]VerdictCell` (metric, family, optional object → verdict), matching cells by key and reporting
whole-matrix accuracy, a per-verdict-kind breakdown, and three diagnostic classes (mismatched,
missing-from-actual, unexpected-in-actual). Its gold-fixture test builds an "actual" matrix by
running `comparison.EvaluateFamily` over the DR12 fixture's own clause data (as a perfect pipeline
would) and confirms `ScoreVerdictMatrix` reports a clean 36/36 across all 11 verdict kinds, plus a
second test that injects a single-cell regression and confirms only that cell is flagged.

**Built:** `ChenWeb/server/api/doc-benchmark/corpus_dataset.go` — `CorpusDataset`/`LoadCorpusDataset`,
a corpus-level dataset kind spanning multiple generated documents scored as one verdict matrix,
built as a **fully parallel type** to the existing single-input-file `Dataset`/`Case` (which is
load-bearing across hashing, execution, and evidence code and was deliberately left untouched — see
that file's own header comment for why a retrofit was rejected). It reuses the existing package's
path-safety helpers (`readRegularFile`, `validateReference`, `decodeStrict`) for the same
traversal/symlink protection `LoadDataset` has. A `CorpusCase` resolves a gold fixture (via the
now-extended `gold` package — `gold.Resolve` promotes what was duplicated test-only logic in two
places into one real, tested implementation) into generated CDM documents, the expected verdict
matrix, and a `SimulatedActual()` stand-in computed via `comparison.EvaluateFamily` over the
fixture's own data. `TestLoadCorpusDatasetAgainstRealFixture` loads the real checked-in dataset
(`benchmark/doc-processors/gold/display-module-v1/manifest.json`) through this production path and
reproduces the 36/36 perfect score.

**Remaining gap, now precisely one thing:** `CorpusDataset` stops at loading, generating, and
scoring — it is **not wired into the orchestrator/runner/store execution engine** that would
actually invoke a live doc-processor pipeline and replace `SimulatedActual()` with real output.
That step needs a real DB, NATS, and LLM credentials this session has no visibility into. It was
originally gated on `extract_metrics` emitting structured values and `normalize_assertions`
existing (both P3) — **2026-08-08 update: both are now built and verified** (§3.9, §8.3.6), so that
blocker is cleared; the orchestrator-wiring step itself was not re-audited in the 2026-08-08 code
verification pass and its current status is unconfirmed. Every piece that can be built and verified
without live infrastructure now exists and is tested.

**Verdict vocabulary** (extends, and does not replace, spec §12.4):

| Verdict | Meaning |
|---|---|
| `identical` | equal after normalization |
| `equivalent` | different expression, equal satisfying set (e.g. unit conversion) |
| `stronger` / `weaker` | strict containment, direction recorded |
| `conflict` | disjoint satisfying sets |
| `incomparable` | overlapping without containment |
| `qualitative_only` | the compared side states a requirement with no decidable limit → needs verification |
| `limit_absent` | the property is required but no limit value is given (the mock's 限值缺失) |
| `standard_absent` | no corresponding requirement exists in that authority family (the mock's 标准缺失) |
| `not_applicable` | the requirement's stated conditions exclude this product/part |
| `indeterminate` | identity, classification, condition, or unit could not be resolved |

Two rules keep this honest:

1. **A verdict is a comparison fact; a recommendation is a policy over verdicts.** "建议采用更严格
   设计输入" is not a verdict — it is derived from `weaker` plus a house policy that the enterprise
   standard should meet or exceed the strictest applicable requirement. Verdicts are computed and
   reproducible; recommendations are configured, versioned, and may differ per organization. They
   are stored separately.
2. **`standard_absent` requires a closed dimension.** Concluding that a standard says nothing is
   the same closed-world claim as `missing` in spec §12.3, and it needs the same justification: an
   explicit statement that this authority family was searched exhaustively for this property. An
   incomplete corpus yields `indeterminate`, never `standard_absent`.

### 3.23 DR22 — The comparison matrix is a class-anchored application service, not a doc processor

🏗️ **APP-SPECIFIC — Document Review app, not the ontology platform.** See Change Log 2026/08/06.

The existing review pipeline is document-anchored: review *this document* against selected
profiles. The application is **class-anchored**: for this part class, across a whole corpus, show
every expected metric against every authority family. Both are Layer 7; only the anchor differs.

Decision: add a **comparison run** as an application service with its own run record, keyed by:

```text
ComparisonScope
  target_class_term_id | target_object_id      -- 显示屏模块, or a specific product instance
  metric_definition_set                        -- the row universe (DR23)
  authority_families                           -- the columns: CN national, ISO/IEC, EU, US, enterprise
  subject_organization_id                      -- the 企业标准主体 selector
  as_of_date, jurisdiction, operating_context
  closed_dimensions                            -- which columns may yield standard_absent
  precedence_policy                            -- which edition wins inside a column
  module_release_ids                           -- pinned, so a rerun reproduces
```

A cell is a **list**, not a value — this is the correction that matters most for the data model.
With 140+ enterprise standards mentioning 呼吸机, one cell routinely holds many assertions from
many documents and editions. Each cell therefore carries: the matched assertion list with citation
and line-span evidence, a display representative chosen by the frozen precedence policy
(newest non-superseded edition by default), a count of the remainder, and equivalence grouping so
that the same requirement restated across editions collapses for display **without merging the
underlying assertions**. Supersession comes from the 4a `document-authority` module.

**Do not build this as a doc processor.** It reads accepted assertions and produces no artifact
that belongs to a document. It is computed on demand, cached against the pinned module releases and
the assertion revision watermark, and invalidated when either moves.

> **2026-08-08 status (verified against code):** `kb.ontology_comparison_runs`/`_cells` (not
> `kb.comparison_*` — naming drift) persist real rows written by
> `server/api/ontology/comparison/store.go`, and the strictness comparator itself (`Compare`/
> `EvaluateFamily`) is real and well-tested (17 test functions covering the verdicts above). But the
> "cached... and invalidated when either moves" claim in this paragraph is **not yet true**:
> `CreateOntologyComparisonRun` unconditionally inserts a new run on every call — there is no
> lookup-by-`(scope, watermark)` dedup and no invalidation logic anywhere in the package (checked
> exhaustively for cache/invalidate/stale/reuse — zero hits). What exists today is a write-once
> persist-and-read-back log, not an invalidating cache. `kb.recommendation_policies` (the DR21 rule-1
> verdict/recommendation split) has no migration and no code — not built at all yet.

### 3.24 DR23 — "Metric definition" and "profile" are different objects; the application's *Metric Profile* is the former

> **2026-08-12 correction, see ADR `2026081201`.** This section's premise that new
> `metric_definition` terms are created through human review (via
> `extract_metric_definitions` candidates → curator approval → promotion) is superseded.
> Checked against the live database: `kb.ontology_terms` has zero `metric_definition` rows,
> the keyword resolver has never resolved a real extracted metric
> (`KEYWORD_RESOLVER_MODE` defaults off), and the harvester's low recall meant few
> candidates were ever generated for a human to review in the first place. Separately,
> this section's "a domain has on the order of hundreds of real distinct metrics" is
> retracted as unfounded — "domain" is not formally defined anywhere, so the bound depends
> on an undrawn boundary. ADR `2026081201` decides `metric_definition` term creation must be
> automatic (a new `kb.ontology_terms.status = 'auto-promoted'`, synthesized from the
> triggering metric's own extracted fields), extending the keyword module's already-shipped
> D11 auto-first policy one layer up, and retires `extract_metric_definitions` from the
> default pipeline. The "row identity" / "aligns_to_term" mechanics below are unchanged —
> only *how a term comes to exist* changes.

The proposed application uses "Metric Profile" for the record holding a metric's canonical name,
preferred name, alternative names, definition, description, value type, and range type. This ADR
already uses "profile" for scoped conformance expectations (`kb.ontology_profiles`). Left alone,
the collision will produce two incompatible meanings in one codebase.

Decision:

* **Metric definition** — an ontology **term** of kind `metric_definition`, living in 4a
  `measurement` for cross-domain metrics and in the 4b domain module for domain-specific ones. It
  carries: canonical/preferred label, alternative labels, definition, description, observable
  property, quantity kind, permitted units, value form and range type, permitted assertion kinds,
  default conditions, and the classes it applies to. This is the application's "Metric Profile",
  and it is the **row identity** in the comparison matrix.
* **Ontology profile** — unchanged: scoped, versioned expectations ("for this class, in this
  jurisdiction, these metrics are required"). This is what supplies the matrix's **row universe**
  for a given part class, and the only thing that can justify `standard_absent`.
* **Alternative names are lexicon, not term duplicates.** A metric definition's alias set is the
  DR15/DR16 keyword lexicon instantiated over metric terms, aligned by `aligns_to_term`. This is
  what lets 亮度 / 显示亮度 / luminance / brightness in 140 documents reach one row — and it is why
  the lexicon is not an optional side quest for this application but a prerequisite.

### 3.25 DR25 — Grounding is a substrate-agnostic locator over portable line spans

Every verdict in the target application must resolve to the source clause: open the document, go
to the page, highlight the region. Two location substrates already exist and neither should leak
into the semantic layers:

| Document origin | Substrate | Produced by |
|---|---|---|
| Uploaded (PDF) | MinerU per-element bounding boxes | PDF parsing — inferred, and occasionally wrong (see `backfill-mineru-list-bboxes`) |
| Authored / generated (CDM) | `kb.cdm_anchors` — page + x/y/w/h per line-file unit | Typst layout, exact by construction (ADR 2026072601) |

Decision: **`source_line_spans` remains the portable anchor** carried by artifacts, assertion
evidence, comparison cells, and findings — as it already is in ~48 places. Coordinates are never
stored on an assertion. Resolution to `{page, x, y, w, h}` happens at read time through one
**locator service** that dispatches on the document's substrate and returns the same shape for
both. Consequences:

* the assertion, verdict, and comparison layers stay substrate-free — they never learn what a PDF
  is;
* a new substrate (a future parser, an HTML source) is a locator implementation, not a schema
  change;
* the anchor map's `renderer_version` / `content_version` keying (ADR 2026072601 DR6) is honored,
  so a Typst upgrade invalidates coordinates detectably rather than silently mispainting;
* the viewer contract is unchanged: `line span → {page, box}` plus paginated pages, per
  ADR 2026072601 DR1.

**Benchmark consequence.** Synthetic benchmark documents are authored as CDM documents and
rendered through the existing Typst path, which emits line file, anchor map, and paginated SVG in
one pass with the DR5 guarantee that every line has exactly one anchor. The benchmark corpus
therefore has exact grounding by construction and requires no PDF anywhere in the loop. This makes
**grounding accuracy a scoreable outcome** — for the first time, "did the highlight land on the
clause the metric came from?" is a measured number rather than a visual spot-check.

### 3.26 DR24 — Explicit non-goals of this ADR

* No authoring GUI for ontology, lexicon, or pipeline content (the data repository is the
  P2–P4 authoring surface).
* No reasoner, no triple store, no SPARQL endpoint (DR13).
* No renaming or re-partitioning of `kb.search_artifacts` / `kb.artifact_connections`.
* No change to the JetStream contract or the Auto/Dev mode payloads.
* No rewrite of the live object-node or category resolvers (DR15.1).
* No per-run TOML for review configuration.
* No hard-deletion/retention policy for `unsupported` assertions (spec §10.12 keeps indefinite
  audited retention until a follow-up ADR).

## 4. Alternative Decisions

### 4.1 AD1 — Keep Layer 4 as one undifferentiated tier

Rejected. Without the 4a/4b split, either every domain module may define its own assertion kinds
(processors and normalizers fragment per domain, and cross-domain comparison dies), or no module
may define anything (domains cannot be added without platform work). The split is what makes
"install a domain module without a code change" a testable property.

### 4.2 AD2 — Author ontology content directly in the database through an admin UI first

Rejected for the first releases. It front-loads UI work before the model is proven, and it makes
approval a mutable database state rather than a reviewable artifact. Git-first gives review,
diff, history, and reproducibility on day one. A UI later writes to the same source.

### 4.3 AD3 — Let an LLM decide per document which processors to run

Rejected as the primary mechanism, and this is the user-raised question answered directly.
A per-document judgment call is unreviewable, unstable across model versions, produces no
explanation a policy owner can audit, and costs an LLM call to save an LLM call. DR4 keeps the LLM
where it is good (classifying a document into a governed vocabulary) and DR6 puts the decision in
reviewed, versioned rules. The LLM classification is cached as a fact, so the cost is paid once
per document, not once per processor per document.

### 4.4 AD4 — Add per-processor `if` conditions to `config.toml`

Rejected. It is the cheapest possible version of DR6 and would work briefly, but it has no
versioning, no approval, no per-run freeze, no explanation, no shared evaluator with profile
selection, and no path to domain-module-supplied rules. The rule *content* may start small; the
*mechanism* must not.

### 4.5 AD5 — Build the ontology first, add pipeline routing later

Rejected as sequencing. P1 (pipeline plane) has no dependency on the ontology and delivers
immediate, measurable value: cost reduction, an execution plan, and the facet vocabulary that
Layer 6 later reuses. Making it wait for L3–L5 delays every benefit behind the longest pole.

### 4.6 AD6 — Build the keyword module as its own standalone, SQLite-backed service

Rejected (spec `2026072703` §3.3 storage note). SemOS has multiple writing services, one backup
and migration story, and `pg_trgm` + `pgvector` already installed, which lets lexical and semantic
blocking run in one hybrid query. More importantly, a standalone service would have to reimplement
candidate generation, adjudication, merge safety, and audit — the exact duplication DR15 exists to
stop. The short-acronym trigram weakness that motivated the SQLite/FTS5 recommendation is real and
is handled by routing short keys to the exact-key path, never to trigrams.

### 4.7 AD7 — One concept registry: make keyword concepts *be* ontology terms

Rejected. It is attractive — one vocabulary, no alignment layer — but it forces every observed
surface form through governance. Keyword concepts arrive by the hundred thousand, must resolve
in microseconds during ingestion, and are frequently junk; ontology terms are reviewed, owned,
defined, and released. Fusing them either paralyzes ingestion behind curation or destroys
governance. DR15.2 keeps both and connects them with an explicit alignment assertion, which is the
same shape already used for object → class.

### 4.8 AD8 — Keep ontology content in the ChenWeb repository (or in KnowledgeStore)

Rejected (DR17). The code repository couples ontology change to code release and gives curators
too much access; `KnowledgeStore` is human prose with different validation, different consumers,
and no compiler. A pinned data repository gives independent cadence, scoped access, its own CI, and
reproducibility from a commit SHA.

### 4.9 AD9 — On a routing conflict, pick a winner and continue

Rejected for now (DR7). A silent winner hides a policy defect from the policy designers, and it
produces artifacts under an ambiguous plan — which then propagate into objects, assertions, and
findings that nobody knows to distrust. Blocking is loud, cheap to diagnose, and safe. The
escalation ladder is implemented at the same time, so maturing to `fallback` is a configuration
change rather than a redesign.

### 4.10 AD10 — Treat association as a separate microservice

Rejected for now. Phase D as pipeline stages inherits status reporting, stop handling, tracing,
concurrency limits, and log/telemetry contracts that already exist and are hard to reproduce.
Extraction to a service remains possible later because the stages are declared, idempotent, and
independently re-runnable.

## 5. Database Migrations

Grouped by the phase that introduces them (goose, `ChenWeb/project_migrations/`, per
`shared/go/api/goose/goose.md`).

**P1 — pipeline plane**

```text
kb.doc_facets                  (record_id, facet_key, facet_value, value_kind,
                                confidence, method, evidence, policy_version, run_id)
kb.pipelines
kb.pipeline_policies
kb.pipeline_bindings
kb.pipeline_rules
kb.knowledge_store_bindings
ALTER kb.doc_process_runs      ADD plan JSONB, policy_version TEXT
ALTER kb.inputs                ADD ks_id BIGINT REFERENCES kb.knowledge_store(id),
                               requested_pipeline TEXT,
                               facet_summary JSONB   -- derived, trigger-maintained
```

> **2026-08-08 status (verified against code): as-built differs from this list in five places.**
> `kb.doc_facets` is real; a second table `kb.doc_facet_values` (migration `20260801000016`) also
> exists and is the one tier-3 classification actually writes to. `kb.pipelines`/`pipeline_policies`/
> `pipeline_bindings`/`pipeline_rules` are real (all dated 2026-07-31). `kb.knowledge_store_bindings`
> **does not exist** — the store default is a `default_pipeline` column on `kb.knowledge_store`
> instead. `kb.doc_process_runs` never gained a `plan` column — the execution plan lives in a
> separate table, `kb.doc_process_plans`. `kb.inputs` gained `requested_pipeline` (real) but not
> `ks_id` (the FK column is the pre-existing `ks_store_id`) or `facet_summary` (does not exist).

**P2 — ontology terms, modules, and the canonicalization kernel**

```text
kb.semid_decision_log          (shared across families: input, output, verdict,
                                model, prompt_version, actor, tokens, created_at)
kb.semid_never_merge           (family, node_a, node_b, reason, actor)
kb.semid_snapshots             (family, normalizer_version, counts, promoted_at)
ALTER kb.object_nodes          ADD merged_into TEXT, scope_key TEXT   -- DR15.1 contracts
kb.ontology_modules
kb.ontology_module_releases    (immutable; payload JSONB + content_checksum)
kb.ontology_active_releases    (activation pointer + audit)
kb.ontology_terms
kb.ontology_term_labels
kb.ontology_axioms
kb.ontology_mappings
kb.ontology_candidates
ALTER kb.object_nodes          ADD ontological_level, identity_scope,
                               external_identifiers JSONB, primary_class_term_id (derived)
```

**P3 — assertions and association**

```text
kb.semantic_assertions         (DR9 typed refs + normalized value columns)
kb.assertion_evidence
kb.assertion_relations         (conflict/supersession between assertions)
kb.semantic_decision_candidates
kb.artifact_semantic_links     (about_term, describes_occurrence, aligns_to_term)
kb.projection_state            (authoritative ref, projection version, stale flag)
```

**P3 — keyword lexicon (DR15/DR16 instantiation)**

```text
kb.keyword_concepts            (concept_id, pref_label, gloss, scope, status,
                                merged_into, gloss_source)
kb.keyword_surfaces            (surface_id, concept_id, surface, norm_key,
                                norm_version, label_role, alias_type, lang, scope,
                                confidence, provenance, locked, evidence)
kb.keyword_surface_keys        (surface_id, key_kind, key_value, norm_version)
kb.keyword_mentions            (observation: artifact ref, chunk, context, ks_id)
kb.keyword_unresolved          (norm_key, scope, surfaces, contexts, hits,
                                status, attempts, last_attempt, priority)
kb.keyword_rewrite_rules       (pattern, replacement, scope, enabled=false default)
```

**P4 — profiles and review**

```text
kb.ontology_profiles
kb.ontology_profile_rules
kb.ontology_review_scopes      (immutable frozen scope)
ALTER kb.doc_review_findings   ADD review_scope_id, profile_rule_id, assertion_id
```

**P4 — target application (DR21–DR22)** — 🏗️ Document Review app, not platform; see Change Log 2026/08/06

```text
kb.comparison_scopes           (immutable: target class/object, metric definition set,
                                authority families, subject organization, as_of,
                                closed dimensions, precedence policy, pinned releases)
kb.comparison_runs             (scope_id, assertion watermark, status, cached_at)
kb.comparison_cells            (run_id, row metric_definition_term_id, column authority_family,
                                assertion_ids JSONB, representative_assertion_id,
                                remainder_count, verdict, direction, rationale)
kb.recommendation_policies     (versioned policy mapping verdicts → advice; separate from verdicts)
```

> **2026-08-08 status (verified against code):** the comparison tables are real but named
> `kb.ontology_comparison_scopes`/`_runs`/`_cells` (not bare `kb.comparison_*`).
> `kb.recommendation_policies` has no migration and no code — **not built**.

`kb.scene_objects.object_id` → `scene_block_id` rename (spec §11.4) lands in P1 with the
identifier-hygiene work.

> **2026-08-08 status (verified against code): this rename has not happened.** The column is still
> `kb.scene_objects.object_id` — no migration or code reference to `scene_block_id` exists anywhere
> in the repo.

## 6. Data Formats

### 6.1 Module content as data (DR2)

Under the DB-native storage decision, a module's source is its content rows, not a `.toml`
package. Authoring the `pump` worked example means inserting governed rows under `module_id =
pump` (via a seed tool, a future authoring GUI, or candidate → promote) and then releasing:

```text
kb.ontology_modules          pump  owner=domain:mechanical
                             depends_on=[core@1.0.0, quantity@1.0.0,
                                         measurement@1.0.0, document-authority@1.0.0]
kb.ontology_terms            pump:pump              kind=class
                             pump:centrifugal_pump  kind=class  parent=pump:pump
                             definition="A rotodynamic pump that moves fluid by a rotating impeller."
kb.ontology_term_labels      pump:centrifugal_pump  en="centrifugal pump"  zh_cn="离心泵"
kb.ontology_mappings         pump:centrifugal_pump  iri="http://…"  relation=close
kb.ontology_profiles         pump:datasheet_completeness  version=1
                             authority={ document="GB/T …", edition="2019", jurisdiction="CN" }
                             applies_to=pump:centrifugal_pump
                             closed_dimensions=["measurement:rated_quantities"]
kb.ontology_profile_rules    pump:requires_rated_head  version=1
                             kind=required_assertion_pattern  quantifier=exists_conforming
                             property=pump:rated_head  quantity_kind=quantity:Length
                             severity=error
```

`mise run ontology-compiler release --module pump --version 0.1.0` validates the approved rows,
snapshots and checksums them, pins the dependency releases, and writes the immutable release (DR2).
Content authored this way needs no TOML grammar and no repository checkout; the DR1 property —
installing a domain module is data, not code — holds by construction.

### 6.2 Applicability predicate (shared by DR3 consumers)

```json
{ "all": [
    { "facet": "doc_kind",  "in": ["standard", "specification"] },
    { "facet": "numeric_unit_density", "gte": 0.02 },
    { "any": [ { "facet": "domain", "eq": "mechanical" },
               { "object_class": { "instance_of": "pump:pump" } } ] }
] }
```

### 6.3 Named pipeline and knowledge-store binding

```toml
# policies/pipelines/standards.toml
id = "standards"
version = 2
title = "Normative standards and specifications"
processors = ["extract_metrics", "extract_provisions",
              "extract_semantic_projections", "extract_inventory_items",
              "generate_topics"]
  [processors.extract_metrics]
  gate = { facet = "numeric_unit_density", gte = 0.02 }

# policies/bindings/default.toml
policy_version = "2026072901.3"

  [[binding]]
  priority   = 100
  scope_kind = "knowledge_store"
  scope_key  = "KS-Project-A"
  pipeline   = "standards@2"
  reason     = "project A ingests GB/ISO standards only"

  [[binding]]
  priority   = 50
  scope_kind = "knowledge_store"
  scope_key  = "KB-Blogs"
  pipeline   = "narrative@1"

  [[binding]]
  priority   = 0
  scope_kind = "system"
  pipeline   = "default@1"
```

### 6.4 Execution plan (frozen in `kb.doc_process_runs.plan`)

```json
{
  "policy_version": "2026072901.3",
  "pipeline": "standards@2",
  "pipeline_selected_by": { "level": "knowledge_store", "binding_id": "b_007",
                            "ks_id": 12, "reason": "project A ingests GB/ISO standards only" },
  "facets": { "doc_kind": "standard", "domain": "mechanical",
              "modal_density": 0.11, "numeric_unit_density": 0.043 },
  "facet_methods": { "doc_kind": "tier1:doc_no_pattern" },
  "decisions": [
    { "processor": "extract_metrics",   "decision": "run",
      "rule_id": "pr_014", "reason": "standard+numeric density ≥ 0.02",
      "cost": "expensive_llm" },
    { "processor": "generate_scene_blocks", "decision": "skip",
      "rule_id": "pr_031", "reason": "doc_kind=standard has no narrative scenes" },
    { "processor": "extract_inventory_items", "decision": "defer",
      "reason": "facet domain undetermined", "dependency_fingerprint": "…" }
  ]
}
```

## 7. Environment Variables

| Variable | Default | Meaning |
|---|---|---|
| `DOC_PIPELINE_POLICY` | unset | active pipeline policy version; unset = legacy `required_processors` behavior (DR7) |
| `DOC_PIPELINE_PLAN_ONLY` | `false` | compute and persist the plan, then run the legacy set — shadow mode for validating rules before enforcement |
| ~~`DOC_FACET_CLASSIFIER_MODEL`~~ | — | **Never built under this name (2026-08-09 correction).** The real model-selection variables are `CLASSIFY_DOCUMENT_MODEL_NAME` + `MODEL_DEF_FILE`, resolved through the same model-config path every other LLM extractor uses. |
| ~~`CLASSIFY_DOCUMENT_ENABLED`~~ | — | **Deleted 2026-08-09; do not use to control tier 3.** Was a flag gating whether the P5 `classify_document` two-pass resolver was constructed at all (confirmed real and wired 2026-08-08). `classify_document` is now `Class: "routed"` (§3.5, §15.1) — the resolver is always constructed (degrading to nil only when `CLASSIFY_DOCUMENT_MODEL_NAME`/`MODEL_DEF_FILE` are absent), and per-document run/skip is an ordinary `kb.pipeline_rules` row with `target_processor="classify_document"`, the same mechanism every other routed processor uses. |
| `DOC_PIPELINE_ON_CONFLICT` | `block` | `block` fails the run and raises an alarm on an unresolved binding conflict or undetermined gate; `fallback` walks the DR7 escalation ladder and warns |
| `PG_HOST` / `PG_PORT` / `PG_USER` / `PG_DB_NAME` | local socket, `5432`, `cding`, `chenweb_test` | database the ontology compiler reads and writes; content lives in the DB, not a repository (DR2) |
| `COMPILER_ARGS` | — | arguments to `mise run ontology-compiler` (`validate`/`release`/`activate`/`rollback`) |
| `SEMANTIC_ASSOCIATION_ENABLED` | `true` | enable Phase D stages |
| `KEYWORD_RESOLVER_MODE` | `off` | `off` \| `observe` (record mentions and unresolved, resolve nothing) \| `on` |
| `KEYWORD_NORMALIZER_VERSION` | `1` | bumping triggers a re-index, never data loss (DR16) |

Every toggle must preserve the boundaries in ADR 2026072701; none may grant an LLM activation
authority.

## 8. Implementation

### 8.1 Code Changes

| Area | Location | Work |
|---|---|---|
| Stage DAG + planner | `ChenWeb/server/api/doc-processing/control.go`, new `plan.go`, `spec.go` | `ProcessorSpec`, DAG build, wave execution, gate application, plan persistence; keep `runProcessorsSequential` as the fallback |
| Facets | new `facets.go`, `facet_producers.go`; extend `doc-structure-analyzer.go`, `extract-doc-metadata.go` | tier-1/2 producers, `kb.doc_facets` store, `classify_document` processor |
| Rule engine | package `server/api/ontology/semrules` (built at this path, not `server/api/semrules` as originally planned) | predicate AST, operator registry, evaluator with trace, conflict/indeterminate semantics |
| Policy store | new `pipeline_policy_store.go` | pipeline/binding/rule load, activation, version pinning, conflict detection and alarm |
| Knowledge stores | `server/api/kbhandler/stores_handler.go`, ingestion handlers | `ks_store_id` (not `ks_id`) and `requested_pipeline` on ingestion; no store-bindings CRUD table exists (§3.20) |
| Canonicalization kernel | package `server/api/ontology/semid` (built at this path, not `server/api/semid` as originally planned) | normalizer profiles, candidate generation, scoring, adjudication, merge/split, decision log; family adapters |
| Keyword lexicon | `server/api/ontology/keywords/` (built at this path, not `server/api/semid/lexicon/`) + a standalone, not-yet-pipeline-wired mention collector (`server/api/doc-processing/keyword_mention_collector.go`) | DR16 merged design as a kernel instantiation |
| Module compiler | new `server/cmd/ontology-compiler`, `server/api/ontology/` | validate DB-staged content, checksum, release, activate, rollback — for modules *and* pipeline policies |
| Ontology stores | `server/api/ontology/` | terms, labels, axioms, mappings, candidates, releases |
| Assertions | `server/api/ontology/assertions/` | assertion + evidence stores, normalizer registry, per-family normalizers |
| Association | new doc-processing stages `normalize_assertions.go`, `associate_semantics.go`, `project_semantics.go` | spec §10 pipeline |
| Profiles & review | `server/api/ontology/profiles/`, `server/api/doc-reviews/` | rule kinds, evaluator, review scope freeze, finding decision procedure (spec §12.3), reviewer tools |
| Comparison service | new `server/api/ontology/comparison/` | strictness comparator (DR21), cell assembly with precedence and equivalence grouping, comparison-run cache and invalidation (DR22) |
| Frontend | `web/src/lib/components/home3/doc-processor-dashboard-view.svelte`, new ontology admin pages, product/part comparison pages | plan display ("why did/didn't X run"), module/release browser, candidate review queues, the part navigator and comparison matrix |

### 8.2 New and Changed Doc Processors

Extraction stays in doc processors; the new work is mostly *new processors* plus structured output
from existing ones. Each new processor follows the capsule §12 checklist (spec file, impl file,
pipeline-table row, status JSON, dashboard registration) and now also declares a `ProcessorSpec`
(DR5).

| Processor | Status | Class | Requires → Produces | Phase | Why |
|---|---|---|---|---|---|
| `classify_document` | new | mandatory (gated) — built as `routed` instead (§3.5, §15.1, 2026-08-09) | facets/metadata → governed document facets | P1 | DR4 routing and profile applicability; identifies standard kind, issuer, jurisdiction, edition |
| `normalize_assertions` | new | routed | artifacts → candidate qualified assertions | P3 | DR8; the step that turns free-text metrics into comparable claims |
| `associate_semantics` | new | routed | candidates → accepted links/assertions | P3 | DR8, spec §10 |
| `project_semantics` | new | routed | accepted records → derived edges, payloads | P3 | DR8, spec §10.8 |
| `extract_metric_definitions` | new | routed | chunks → `OntologyCandidate(term, metric_definition)` | P3–P4 | Harvests the *definition* of a metric (canonical name, aliases, value type, range type) from 术语与定义 and requirement clauses. Distinct from extracting a metric *value*, and the main feeder of DR23 rows and 4b module content |
| `extract_product_structure` | new | routed | chunks/blocks → part-of and component-of candidates | P4–P5 | DR20 hierarchy; drives the module/sub-part navigation and the image hotspot bindings |
| `extract_test_methods` | new | routed | chunks → procedure terms, metric↔procedure links | P4 | The 检测方法 panel; a metric's procedure is part of its comparability key (research §6.3) |
| `extract_metrics` | **changed** | routed | adds value form, comparator, normalized value, unit term, condition, assertion kind | P3 | Today it emits `threshold_or_target` as free text, so no verdict can be computed from it. This is the single highest-leverage change for the application |
| `extract_provisions` | **changed** | routed | adds applicability/scope clauses, authority, effective interval | P3–P4 | Profile rules are sourced from provisions; the 范围/适用于 clause decides applicability |
| `extract_doc_metadata` | **changed** | mandatory | adds standard identity: doc number, edition, issuer, jurisdiction, supersedes | P1 | Column assignment and precedence inside a column both depend on it |

> **2026-08-01 status (`extract_metrics`):** implemented by the OpenSpec change
> `ChenWeb/openspec/changes/extract-metrics-structured-output/`. `kb.metrics` gained
> `value_min`/`value_max`/`condition` (migration `20260801000014_add_kb_metrics_structured_value_fields.sql`,
> prompt v5 `prompt-enrich-metrics-v5.md`); the metric normalizer now consumes the structured
> fields (`value_range_type`/`value_class`/`metric_value`/`metric_unit`) deterministically, with
> `parseThresholdOrTarget` demoted to a legacy fallback for rows with no structured values. QUDT
> unit/quantity-kind term resolution against the `quantity` module is implemented in
> `associate_semantics.processMetric`. See the P3 log `2026080103` §12.1 addendum for the
> gold-corpus reconciliation.

Explicitly **not** doc processors: the comparison matrix and verdict computation (DR22, an L7
service — 🏗️ Document Review app, not platform), profile evaluation (L6), the certification-body
registry (reference data, not extraction), and the product image hotspot map (application data
binding an image region to an object node).

### 8.3 Phased Implementation Plan

Phases are ordered by dependency, not by importance. **P1 and P2 are independent and may run in
parallel.** Each phase ends with an exit criterion that is a test, not a judgment.

#### 8.3.1 P0 — Semantic audit, competency questions, corpus baseline *(no ontology/runtime implementation)*

* Verify spec §13.5 current-state claims against the deployed database and current code:
  artifact-object cardinality, `kb.search_artifacts` partitions, `kb.artifact_connections`
  uniqueness/replacement, scene identifier semantics, cascade/reprocessing behavior.
* Freeze the competency-question suite (research §11.1) with expected answers.
* Merge the two keyword specs into one superseding spec per DR16, and confirm the storage model:
  ontology content is authored and versioned in the database, with no data-only repository (DR2/DR17
  storage decision, 2026-07-31).
* Inventory the knowledge stores actually in use and the pipelines each one needs (DR18).
* **Build the synthetic gold corpus and extend the existing benchmark** (ADR 2026071301) rather
  than waiting for a real-data example. Author the gold ontology for one part class first, then
  generate documents *from* it as CDM documents (DR25), so extraction gold, normalization gold,
  verdict gold, and grounding gold are all true by construction. This is P0's primary deliverable;
  the real corpus, when it arrives, calibrates difficulty but never gates.
  **Drafted:** `ChenWeb/benchmark/doc-processors/gold/display-module-v1/gold.toml` — 显示屏模块,
  9 metric definitions, 9 synthetic authority documents across 5 families, 40 clauses, 36
  hand-derived expected verdicts covering all 11 DR21 verdict kinds, each with a stated rationale.
  The fixture, generator, resolver/coverage helpers, `CorpusDataset`, comparator, verdict scorer,
  and dedicated `gold-run` / `analyze` CLI are now built, and `gold-run` can execute the real
  processors through its dedicated path. The remaining integration gap is narrower: `CorpusDataset`
  itself is not wired into the existing orchestrator/runner/store execution engine, and real
  normalized verdict scoring is still gated by structured metric output plus
  `normalize_assertions`. Authoring it surfaced a finding: the proposed application's mock shows
  `identical` ("一致") for several quantitative-enterprise-vs-qualitative-authority cells
  (触控响应时间, 有效视角); under DR21 that pairing is always `qualitative_only`, never
  `identical` — the mock should not be treated as gold for those cells.
* Build the DR21 strictness comparator standalone — it is a pure function over normalized
  constraints, needs no pipeline or database, and the benchmark is its first caller.
* Assemble the fixture corpus: ambiguous objects, multilingual names, unit conversion,
  superseded documents, conflicting requirements.
* Baseline measurement per document kind: processor cost, artifact yield, artifact usefulness —
  the numbers P1 and P5 are judged against.
* Choose the pilot domain module and its authoritative source (OD1).

#### 8.3.2 P0 verified baseline — 2026-07-30

| Area | Verified schema/current data | Code lifecycle | P1/P2 consequence |
|---|---|---|---|
| Artifact-object cardinality and soft object reference | `kb.artifact_objects` currently has 587 rows over 456 distinct `(source_record_id, artifact_type, artifact_id)` keys, so duplicates are permitted; `object_id` is non-null in live data today but has no FK to `kb.object_nodes.object_id`, so the object link remains soft. | `ArtifactObjectSQLStore.ReplaceObjectsForRecord` deletes and reinserts rows transactionally, scoped by `source_record_id` plus `artifact_type`. | P1 can preserve current replacement behavior unchanged; P2 must preserve one artifact-to-many object mentions, must not add a uniqueness rule that collapses distinct mentions, and must treat `object_id` as a soft pre-canonical link until ontology-governed identity exists. |
| Search partitions and non-atomic reindex | `kb.search_artifacts` is LIST-partitioned by `artifact_type` with 11 partitions; 9 are populated today and 2 are empty (`knowledge`, `product`). Querying the parent currently returns 103799 rows across its partitions. | `replaceRegistryRows` deletes existing rows and then inserts replacements through separate DB calls, so reindex replacement is scoped but not atomic. | P1 can reproduce legacy behavior exactly, but any policy-driven retry or plan persistence must account for transient empty search state during replacement. |
| Connection partitions, uniqueness, and atomic scoped replacement | `kb.artifact_connections` is LIST-partitioned by `relation_method` with 10 partitions; 7 are populated today and 3 are empty (`llm`, `manual`, `structural`). The deployed uniqueness constraint is `(relation_method, source_type, source_id, target_type, target_id, relation_name)`. | `ReplaceConnections` and `ReplaceConnectionsBySource` scope-delete and reinsert inside transactions, preserving atomic replacement by method plus relation scope. | P1 can safely wrap connection work in execution plans without redefining edge identity; P2 assertion/evidence work can rely on scoped edge replacement already being atomic. |
| Scene-block occurrence identifier semantics | `kb.scene_objects.object_id` values are live as `<input_record_id>_sbk_<sequence>` occurrences such as `200_sbk_1`; `scene_id` carries the semantic label for the extracted block. | Forced scene regeneration deletes prior rows for the input record before re-extraction, then upserts on `(input_record_id, object_id)`. | P1 documentation must keep the current occurrence-ID meaning explicit; P2 should not overload `scene_objects.object_id` as canonical identity. |
| Cascade/input deletion and canonical-node retention | `kb.artifact_objects`, `kb.search_artifacts`, `kb.artifact_connections`, and `kb.scene_objects` all delete per input record through FKs or explicit delete specs, while `kb.object_nodes` remains corpus-wide and intentionally survives per-document deletion. | `inputRelatedDeleteSpecs` explicitly covers per-record artifacts and tests assert that `kb.object_nodes` must never be deleted as part of a single-input cleanup. | P1 can keep delete semantics as-is; P2 canonical identity work must continue treating object nodes as cross-document state rather than document-owned rows. |
| Knowledge-store membership and missing referential/routing semantics | `kb.inputs.ks_store_id` exists today, is nullable, and currently yields 194 `Research` inputs, 0 `卫健委标准` inputs, and 15 unassigned inputs. Search artifacts are therefore already partly groupable by store membership, but the column still has no FK and no semantic scope contract. | Current ingestion paths can persist `ks_store_id`, store CRUD/default-store lookup exists, and runtime selection still reads one global `doc-processing.required_processors` list rather than a store-specific policy. | P1 DR18 work must add binding semantics and referential integrity without inventing differentiated pipelines before evidence exists; P2 scope-aware identity and lexicon resolution should key off the normalized store concept rather than the legacy nullable column. |

Live observations from the read-only audit on 2026-07-30:

* `kb.search_artifacts` exact partition rows: `entity` 42664, `inventory_item` 8578, `knowledge` 0, `metric` 6541, `product` 0, `provision` 13915, `relation` 23754, `scene_block` 2288, `semantic_projection` 2068, `summary` 789, `topic` 3202.
* `kb.artifact_connections` exact partition rows: `category_name` 98939, `entity_name` 31781, `entity_relation` 37030, `hybrid_search` 70003, `line_overlap` 45314, `line-overlapped-artifact` 16410, `llm` 0, `manual` 0, `object_id` 410, `structural` 0.
* `kb.artifact_objects` currently has 587 rows, 456 distinct `(source_record_id, artifact_type, artifact_id)` keys, 75 duplicate groups, 0 null `object_id`, and 0 live orphan `object_id`.
* `kb.search_artifacts` currently has 103799 rows, `kb.artifact_connections` has 299887 rows, and `kb.scene_objects` has 2150 rows.
* Search-artifact distribution today is `entity` 42664, `relation` 23754, `provision` 13915, `inventory_item` 8578, `metric` 6541, `topic` 3202, `scene_block` 2288, `semantic_projection` 2068, `summary` 789.
* Connection-method distribution today is `category_name` 98939, `hybrid_search` 70003, `line_overlap` 45314, `entity_relation` 37030, `entity_name` 31781, `line-overlapped-artifact` 16410, `object_id` 410.
* Knowledge-store inventory today is `Research` (`research`, `active`) with 194 inputs, `卫健委标准` (`document`, `active`) with 0 inputs, and 15 inputs with no `ks_store_id`.

Evidence inspected:

* The read-only SQL block captured in implementation plan `doc-repo/devdocs/202607/2026073003-devdoc-semos-p0-implementation-plan.md` Chunk 1 / Task 1, executed against `kb.artifact_objects`, `kb.object_nodes`, `kb.search_artifacts`, `kb.artifact_connections`, `kb.scene_objects`, `kb.inputs`, and `kb.knowledge_store` on 2026-07-30.
* Migration `../ChenWeb/project_migrations/20260425000002_add_kb_inputs_store_fields.sql`.
* Go/config paths `../ChenWeb/server/api/doc-processing/artifact_objects.go`, `../ChenWeb/server/api/kbsearch/registry.go`, `../ChenWeb/server/api/doc-processing/search_indexing.go`, `../ChenWeb/server/api/doc-processing/connections_store.go`, `../ChenWeb/server/api/doc-processing/generate-scene-blocks-processor.go`, `../ChenWeb/server/api/kbhandler/metrics_handler.go`, `../ChenWeb/server/api/kbhandler/metrics_handler_test.go`, `../ChenWeb/server/api/cdmhandler/documents.go`, `../ChenWeb/server/api/kbhandler/upload_handler.go`, `../ChenWeb/server/api/kbhandler/stores_handler.go`, `../ChenWeb/server/api/kbhandler/default_store_handler.go`, `../ChenWeb/server/api/doc-processing/runtime.go`, `../ChenWeb/server/api/doc-processing/runtime_selection_test.go`, `../ChenWeb/server/api/kbhandler/kb_config_handler.go`, and `../ChenWeb/config.toml`.

These row counts are live observations, not normative contracts; only the schema shape, code paths,
and explicit ADR decisions are normative.

P0 status after the 2026-07-31 closeout revision:

* Verified: deployed schema/current-data audit for §13.5 claims and current knowledge-store inventory.
* Frozen and approved for P0 closeout: the competency-question contract and the ontology terminology implementation boundary.
* Verified with execution evidence: the approved 9-document ventilator pilot benchmark run, generated line-file path, and offline profile report showing differentiated structural-yield patterns across `narrative-research`, `product-specification`, and `regulated-reference` (`2026073005-devdoc-semos-p0-benchmark-evidence.md`).
* P0 is therefore complete as a bounded benchmark-led proof milestone.
* Deferred beyond P0: authoritative medical-standard editions and a real-data worked example, the merged DR16 keyword spec, broader ambiguous/multilingual/unit/supersession/conflict fixtures, and the actual implementation of P1+ runtime behavior.

#### 8.3.3 P0 competency-question contract

| ID | Expected answer contract | Expected result example | Positive fixture | Negative fixture | SQL test outline | P7 parity | Owner |
|---|---|---|---|---|---|---|---|
| CQ-I01 | Which artifact-object mentions resolve to canonical object X? Ordered mention refs with artifact, evidence, decision, and canonical ID | `metric:m-display-luminance` and `provision:p-display-luminance` both resolve to `object:display-module-01`, each retaining separate evidence and decisions | `cq-i01-positive`: two mentions resolve to one canonical object | `cq-i01-negative`: similar mention remains separate | P2: mention links -> canonical referent -> decision provenance | Equivalent SPARQL result required in P7 | Pending domain owner |
| CQ-I02 | Is node X an individual, type, collection, occurrence, or concept? Exactly one governed `ontological_level`, with provenance | `object:display-module-01` returns `ontological_level = individual`; `term:DisplayModule` returns `class` rather than the same node kind | `cq-i02-positive`: one node resolves to one valid ontological level | `cq-i02-negative`: invalid or missing level is rejected | P2: canonical referent or term -> governed ontological level -> provenance | Equivalent SPARQL result required in P7 | Pending ontology owner |
| CQ-I03 | Which ontology classes apply to X, and what supports each classification? Qualified class assertions with status and evidence | `object:display-module-01` has supported classifications `DisplayModule` and `MedicalDeviceComponent`, each with its own evidence | `cq-i03-positive`: supported multi-classification is retained | `cq-i03-negative`: unsupported inferred class is absent | P2-P3: referent -> classification assertions -> supporting evidence | Equivalent SPARQL result required in P7 | Pending ontology owner |
| CQ-I04 | Which IDs were merged or redirected to canonical ID X? Non-transitive redirect/tombstone history | `object:display-module-legacy` redirects to `object:display-module-01`; two pairwise decisions do not fabricate a third merge decision | `cq-i04-positive`: explicit redirect chain is preserved | `cq-i04-negative`: no inferred transitive merge decision appears | P2: tombstones and redirects -> canonical target -> decision history | Equivalent SPARQL result required in P7 | Pending ontology owner |
| CQ-M01 | Which metric assertions apply to object X? Assertion refs grouped by metric term and asserted object level | Object `display-module-01` returns its luminance and touch-response assertions but no ventilator-main-unit assertion | `cq-m01-positive`: direct and inherited candidates attach to the target object | `cq-m01-negative`: unrelated-object assertion is excluded | P3: assertion subject/object links -> governed metric term -> applicability grouping | Equivalent SPARQL result required in P7 | Pending domain owner |
| CQ-M02 | Which assertions measure the same property or quantity kind? Equivalence groups keyed by governed metric/property and quantity kind | `display luminance` and its approved Chinese label group under one governed property; `ambient luminance` remains separate | `cq-m02-positive`: aliases group under one governed property | `cq-m02-negative`: same-looking label with different quantity kind stays separate | P3: metric term, property mapping, and quantity kind joins over assertion sets | Equivalent SPARQL result required in P7 | Pending domain owner |
| CQ-M03 | Are assertion units dimensionally compatible and convertible? Compatibility boolean plus normalized values and conversion provenance | `250 cd/m²` and `250 nit` are compatible and normalize equally; a time-valued assertion is dimensionally incompatible | `cq-m03-positive`: compatible units normalize successfully | `cq-m03-negative`: incompatible dimensions reject comparison | P3: assertion value + unit term -> quantity catalog -> normalized comparison result | Equivalent SPARQL result required in P7 | Pending domain owner |
| CQ-M04 | Are assertions observations, requirements, targets, references, or capabilities? One governed assertion kind per assertion | A clause using `shall be at least` is `lower_bound_requirement`; a measured test result is `observed_value` | `cq-m04-positive`: one fixture exists for each governed assertion kind | `cq-m04-negative`: ambiguous free text remains undecided | P3: assertion record -> assertion kind classifier -> evidence/provenance | Equivalent SPARQL result required in P7 | Pending domain owner |
| CQ-M05 | Under which procedures, conditions, and time windows do assertions apply? Structured applicability tuple linked to evidence | A touch-response assertion returns procedure, operating condition, and effective interval; a different condition remains a separate applicability tuple | `cq-m05-positive`: matching procedure, condition, and interval stay linked | `cq-m05-negative`: differing condition remains separate | P3-P4: assertion -> procedure/condition/time qualifiers -> evidence tuple | Equivalent SPARQL result required in P7 | Pending domain owner |
| CQ-M06 | Which assertion pairs are truly comparable? Pair result with comparable flag or reason code | Two lower-bound luminance requirements with compatible units and scope return `comparable`; a missing required condition returns `indeterminate` | `cq-m06-positive`: compatible units and applicability compare cleanly | `cq-m06-negative`: missing required condition yields indeterminate | P3-P4: paired assertions -> normalized value/unit -> applicability equivalence or reason code | Equivalent SPARQL result required in P7 | Pending domain owner |
| CQ-P01 | Which provision imposes a metric requirement? Provision -> assertion -> metric chain with evidence | Provision `p-display-luminance` imposes assertion `a-display-luminance-min`, which constrains the luminance metric | `cq-p01-positive`: normative clause links to one governed requirement assertion | `cq-p01-negative`: descriptive mention does not impose a requirement | P3: provision evidence -> normalized assertion -> governed metric term | Equivalent SPARQL result required in P7 | Pending domain owner |
| CQ-P02 | Which actor must perform which action on which object? Qualified actor-action-object assertion with modality | The normalized assertion states that the manufacturer must verify display luminance on the display module | `cq-p02-positive`: explicit obligation parses into actor, action, object, and modality | `cq-p02-negative`: actorless clause remains incomplete | P3: provision parse -> normalized obligation assertion -> actor/action/object slots | Equivalent SPARQL result required in P7 | Pending domain owner |
| CQ-P03 | Which inventory item is an instance of which item type? Item identity plus supported class assertion | Inventory item `display-panel-001` is classified as an instance of `DisplayModule`; a label-only near match is not classified | `cq-p03-positive`: named inventory item is classified with support | `cq-p03-negative`: label-only near match is not classified | P3-P4: inventory item referent -> supported class assertion -> evidence | Equivalent SPARQL result required in P7 | Pending domain owner |
| CQ-P04 | Which items are parts of, located in, or members of another object? Qualified relation assertions preserving relation kind | `touch-controller-01` is `part_of display-module-01`; a co-mentioned component is not inferred as a part | `cq-p04-positive`: one supported structural relation is preserved | `cq-p04-negative`: co-mention does not become a structural relation | P3-P4: referent pairs -> governed relation predicate -> supporting evidence | Equivalent SPARQL result required in P7 | Pending domain owner |
| CQ-R01 | Which profile applies to a document and why? Profile release plus applicability trace and precedence result | Profile release `ventilator-display@0.1.0` applies because document kind, device class, jurisdiction, edition, and interval match | `cq-r01-positive`: one applicable profile resolves with a full trace | `cq-r01-negative`: precedence conflict returns indeterminate | P4: document/store facets -> profile applicability predicates -> precedence trace | Equivalent SPARQL result required in P7 | Pending application owner |
| CQ-R02 | Which required assertion patterns are missing? Findings only within a frozen closed review dimension | Closed profile dimension `display_metrics` yields a missing `TouchResponseTime` finding; an open dimension yields no missing finding | `cq-r02-positive`: declared required metric missing inside a closed dimension is reported | `cq-r02-negative`: open dimension never reports missing | P4: closed review dimension -> required pattern set -> absence finding generation | Equivalent SPARQL result required in P7 | Pending application owner |
| CQ-R03 | Which evidence supports or contradicts an assertion? Evidence refs partitioned by support relation | One evidence record supports and another contradicts the same assertion; missing evidence is not returned as contradiction | `cq-r03-positive`: support and contradiction evidence are both retained | `cq-r03-negative`: absent evidence is not treated as contradiction | P3-P4: assertion -> evidence links -> support relation partition | Equivalent SPARQL result required in P7 | Pending domain owner |
| CQ-R04 | Which source is authoritative for a scope and date? Source selection with jurisdiction, edition, interval, and precedence trace | The effective superseding standard edition is selected with a precedence trace; unresolved jurisdiction conflict returns `indeterminate` | `cq-r04-positive`: superseding authoritative source wins with trace | `cq-r04-negative`: unresolved jurisdiction conflict stays indeterminate | P4: source scope/facet joins -> effective interval -> precedence evaluation | Equivalent SPARQL result required in P7 | Pending domain owner |
| CQ-R05 | How did a processor, model, prompt, or human action produce or modify an assertion? Complete ordered provenance/audit events | Provenance returns extraction run -> model/prompt -> candidate -> human approval as an ordered audit chain | `cq-r05-positive`: automated then human decision chain is visible end to end | `cq-r05-negative`: missing producer event fails validation | P3: assertion provenance/audit events -> ordered producer and approval chain | Equivalent SPARQL result required in P7 | Pending ontology owner |
| CQ-R06 | Would an object merge change previous review findings? Impact set of affected assertions, scopes, runs, and findings without mutating history | A proposed object merge lists the exact prior review findings whose scope would change; an unrelated merge returns an empty impact set | `cq-r06-positive`: merge candidate reports affected findings before mutation | `cq-r06-negative`: unrelated merge returns an empty impact set | P4: proposed merge scope -> affected assertions/runs/findings -> impact report | Equivalent SPARQL result required in P7 | Pending application owner |

Interpretation rules for the suite:

* `Pending ... owner` means structurally frozen in P0 but not yet approved for P0 exit.
* Missing data remains unknown unless a profile explicitly closes the relevant review dimension.
* Negative fixtures guard against over-merge, accidental class promotion, unsupported inference, and false completeness findings.
* SQL outlines are logical contracts, not committed DDL.
* P7 parity compares result sets, not query text.

*Exit:* domain and application owners agree on expected answers for the pilot questions; any spec
mismatch is corrected in writing before migrations.

#### 8.3.4 P1 — Pipeline plane: declarations, facets, rules, plans *(no ontology dependency)*

* `ProcessorSpec` declarations for all 13 processors; DAG planner; wave execution replacing the
  hard-coded A/B/C split with A/B/C as its degenerate output.
* Tier-1 and tier-2 facet producers; `kb.doc_facets`; facet summary projection.
* `semrules` evaluator; named pipelines, binding policy, and processor rules (DR6); seeded
  `default` pipeline that reproduces `required_processors` exactly.
* Knowledge-store wiring (DR18 items 1–2): `ks_id` and `requested_pipeline` on `kb.inputs`,
  store bindings, and the ingestion path that sets them.
* DR7 precedence, conflict detection, blocking behavior, and the `alarms_errors` integration.
* Execution plan persisted per run; API and dashboard panel exposing it.
* Shadow mode (`DOC_PIPELINE_PLAN_ONLY`) to validate rules on live traffic without enforcing them.
* `kb.scene_objects.object_id` → `scene_block_id`; spec §15 Phase 1 documentation corrections.

*Exit:* with no policy activated, pipeline behavior is byte-identical to today; with the seeded
policy activated, it is identical **and** every run carries an explainable plan; "run pipeline A on
knowledge store K1" is expressible as one binding; a deliberately conflicting binding pair fails
the run and raises exactly one alarm; shadow mode on the fixture corpus shows the intended skip
decisions.

> **2026-08-08 status (verified against code): substantially built, but not as a DAG.** Real and
> working: `ProcessorSpec` declarations (20 processors, though as untyped strings — see DR5), gate
> resolution with reasons and dependency fingerprints (though deferred gates are never re-evaluated),
> named pipelines/bindings/rules (`legacy_default`/`store_default`/`request_override`, not
> `default`/`standards`/`narrative`/`minimal`), `DOC_PIPELINE_ON_CONFLICT` blocking-with-alarm (DR7),
> `DOC_PIPELINE_PLAN_ONLY` shadow mode, `requested_pipeline` on ingestion, and a persisted execution
> plan exposed via a real (if dashboard-less) API. **Not built:** the DR5 DAG planner itself — Phase
> A/B/C is still a hardcoded loop, by the code's own admission (§3.6); tier-1/tier-2 facet producers
> (only tier-3 `classify_document` writes observations, §3.5); the `scene_block_id` rename;
> `kb.knowledge_store_bindings`. The exit criterion "with no policy activated, byte-identical to
> today" holds (`legacy_default`); "every run carries an explainable plan" holds via
> `kb.doc_process_plans`, not `kb.doc_process_runs.plan`.
>
> **2026-08-08 update (later the same day):** the "named pipelines, binding policy" bullet moved
> from "mechanism exists, never populated" to "populated with real content, on staging." A small
> separately specced/planned feature ("Doc Processing Policies," §1 changelog) added a
> `config.local.toml`-driven seed CLI that authors real named pipelines and a real activated
> `kb.pipeline_policies` version on `miner`, verified by direct resolution checks against the live
> database (not just mocks). This does **not** change the "no ontology dependency"/DAG-planner
> findings above — the DAG planner is still not built, and this new content flows through the
> same non-DAG `applyPolicyFilter` intersect-against-request mechanism already documented. It also
> does not mean this is live/enforced anywhere: `DOC_PIPELINE_PLAN_ONLY` was left at its default
> (shadow mode) and the running `doc-processor` process on `miner` was deliberately not restarted
> to pick it up, so today it changes nothing observable in production/staging behavior — only the
> DB content and the resolution logic's correctness against it are now verified.

#### 8.3.5 P2 — Ontology core and the canonicalization kernel *(parallel with P1)*

> **Status: implemented and validated (2026-08-01).** All six P2 bullets below are built and
> live-validated (chunks 0, A–F), with the DB-native storage revision applied throughout. See the
> P2 implementation log and the ontology capsule. Exit criteria: spec §15.3 items 1–7 are covered
> by the consolidated `candidates/p2_exit_test.go`; the four core 4a modules install as data with
> no code change (the DR1 property); a failed validation leaves the previous active release
> untouched; and the `semid` merge/split fixtures show no transitive closure and no lost merged id
> (ADR kernel tests 18–21, 23).
>
> **2026-08-08 correction (verified against code and the live `miner` database): the "four core 4a
> modules" claim overstates what's actually installed.** Only `core` (20 governed terms — the ADR's
> "19" predates an unrelated 2026-08-06 commit that added `core:aligns_to_term`) is released and
> **active** in the live database. `document-authority` (22 terms) and `measurement` (17 terms) have
> real seed code (`server/cmd/ontology-seed`, present since 2026-07-31) but **zero rows** in
> `kb.ontology_modules`/`kb.ontology_terms` — the seed/release step was never run against this
> instance. `quantity`'s claimed 4151-term QUDT import likewise has zero live rows, and the "4151"
> figure itself has no supporting evidence anywhere in the repository (not in code, not in a test
> fixture, not in a devdoc). The mechanism (compiler, validator, checksum, activation, rollback) is
> real and independently verified working — it is the *content installation* that has not actually
> been run for three of the four modules. `candidates/p2_exit_test.go` is real and passes (3/3), but
> covers items 1/3/4 directly and delegates 5/6/7 to other test files rather than duplicating them;
> the kernel merge/split-no-transitive-closure tests (ADR tests 18–21, 23) live in the **keywords**
> package, not in `semid/kernel_test.go` itself, which has 7 unrelated scoring tests. The `semid`
> package path is `server/api/ontology/semid/`, not `server/api/semid/` (§3.17).

* Module compiler, validator, checksum, immutable release, activation pointer, rollback —
  serving both `modules/` and `policies/` from the data repository (DR17).
* Core modules 4a: `core`, `quantity` (QUDT catalog imported as data per DR13),
  `document-authority` (including the DR4 facet vocabulary), `measurement`.
* Term/label/axiom/mapping stores; `kb.ontology_candidates` with the spec §9.3 state machine.
* **Canonicalization kernel** (`semid`, DR15): normalizer profiles, candidate generation,
  scoring, adjudication, merge/split with tombstones, `never_merge`, shared decision log.
  First instantiation: ontology terms. Live families adopt the kernel contracts only (DR15.1).
* `ontological_level`, `identity_scope`, external identifiers on `kb.object_nodes`;
  classification assertions (DR10) with the derived convenience column.
* Extension seams 1–4 complete and documented.

*Exit:* spec §15.3 items 1–7 pass; a term added by committing module source and running the
compiler reaches production with no code change; a deliberately failed validation leaves the
previous active release untouched; kernel merge/split fixtures show no transitive closure and no
loss of a merged id.

#### 8.3.6 P3 — Assertions, evidence, Phase D association, and the keyword lexicon *(needs P2)*

* Assertion and evidence schema (DR9); assertion relations for conflict and supersession.
* Metric and provision normalizers; the normalizer registry (seam 5).
* Phase D stages; candidate/decision lifecycle; deferred retry on fingerprint change; projection
  build and stale repair; association telemetry that reconciles every examined artifact.
* Deferred/ambiguous backlog drains reusing the ADR 2026070701 DR5/DR6/DR7 pattern.
* **Keyword lexicon** as the second kernel instantiation (DR16): mention collection in the
  pipeline, deterministic working-mode resolution, the unresolved backlog, batched reconciliation
  with validation gates, and `aligns_to_term` alignment to governed terms. Ships behind
  `KEYWORD_RESOLVER_MODE=observe` first, so mention and backlog volume is measured before any
  resolution affects retrieval.

> **2026-08-01 status:** P3 Track A is **Built and complete** (see the 2026-08-01 correction below —
> this framing overstated several items) — assertion/evidence schema (DR9), the
> operational candidate lifecycle, the normalizer registry (seam 5) with metric and provision
> instances, all three Phase D stages (`normalize_assertions`, `associate_semantics`,
> `project_semantics`, orchestrated by `assertions.RunPhaseD`), association-run telemetry (spec
> §10.9), and the deferred-candidate backlog drain (`POST /kb/semantic-decisions/drain-deferred`,
> the DR5 bulk-backfill pattern reused). `project_semantics` includes the `ProjectionBuilderRegistry`
> (seam 7) and `kb.object_nodes.primary_class_term_id` maintenance (DR10), closing the P2 chunk E
> deferral. Live-validated against real Postgres including the actual gold corpus already in
> `chenweb_test`, not only synthetic fixtures — see the P3 implementation log
> `2026080103-devdoc-semos-p3-implementation-log.md`, which also records two real correctness bugs
> live validation found and fixed (a revision-supersession gap and an `in_review` resumability gap).
> **Not built:** the DR6/DR7 halves of the backlog drain (admin review page; LLM auto-resolution).
>
> **2026-08-04 — P3 Track B (keyword lexicon) complete:** The keyword lexicon is **built and
> validated** as of 2026-08-04 — the second `semid` kernel instantiation (after P2's `TermFamily`),
> shipped behind `KEYWORD_RESOLVER_MODE=observe` (default `off`). Delivered: 6 `kb.keyword_*`
> tables, CRUD stores with sqlmock tests, a keyword normalizer producing 6 deterministic key kinds
> (exact/norm/alnum/sorted/phonetic/initials) through a full NFKC pipeline, a `KeywordFamily`
> implementing `semid.FamilyAdapter` (`family='keyword'`) with multi-tier candidate generation
> (tiers 0-4 auto-accept at score ≥ 0.8; tiers 5-6 deferred), a `semid.Normalizer.NormFunc`
> extension (backward-compatible; `TermFamily` unchanged), 13 REST endpoints, a standalone mention
> collector (`CollectFromText`, not pipeline-wired), and `KEYWORD_RESOLVER_MODE` env-var gating
> (`sync.Once` at startup). Full test suite passes; `go build`/`go vet`/`gofmt` clean.
>
> **Deferred by design:** fuzzy tiers 5-6 (trigram/vector blocking), the full reconciliation
> pipeline (R1-R7), `aligns_to_term` bridge to governed terms, `on` mode (retrieval connection),
> curated seed content, the phonetic-key stub → Double Metaphone upgrade, and I2 live PostgreSQL
> proof. See the Track B handoff `2026080401-handoff-semos-p3-trackb-keyword-lexicon.md` for the
> complete build record and deferred boundary.
>
> **2026-08-05 to 2026-08-07 — most of the above deferral list closed.** Three sessions built
> directly on the 2026-08-04 slice: all 13 defects the Track B review found were fixed and D11
> auto-first was implemented (2026-08-05); **fuzzy tiers 5-6** and a minimum reconciliation loop
> (`keywords.Reconciler`/`cmd/keyword-reconcile`) plus the **`aligns_to_term` bridge** and its
> metric-integration seam were built (2026-08-06, step 11-12); Tier 6 was then rebuilt to require
> governed identity evidence rather than a cosine threshold, and the governed external-terminology
> portfolio (source registry, import/promotion tooling, admin review UI) was added, **closing I2**
> (2026-08-07). Still deferred exactly as this row says: the full R1-R7 orchestration (only R3
> blocking + a validate/apply core exist), `on` mode, and the Double Metaphone upgrade. Curated
> seed content has tooling now but no published production release — an operator action, not a
> code gap. Current status of record: spec `2026080403-spec-keyword-canonicalization-and-reconciliation.md`
> §0/§21 (this ADR is not re-synced every session; that spec is).
>
> **2026-08-08 code-verification update:** confirmed accurate with corrections. Real, tested, wired
> code at `server/api/ontology/keywords/` (not `server/api/semid/lexicon/`): 6 deterministic key
> kinds (phonetic is an explicit stub, as documented — not Double Metaphone yet), tier-5 fuzzy
> matching is real online SQL (`similarity()` + edit distance), tier-6 is real but deliberately
> offline-only, `aligns_to_term` correctly never writes `kb.ontology_terms` directly, and R3/R6/R7
> reconciliation logic is real (R1/R2/R4/R5 — harvest/prune/assemble/LLM-decide — remain genuinely
> absent, as documented). Corrections: the endpoint count is 15, not 13; `kb.keyword_mentions` was
> since dropped and replaced by `kb.keyword_occurrences` (a 2026-08-05 design fix); `on` mode is
> still indistinguishable from `observe` in code (no distinct consumer wiring). More notably: **this
> ADR itself was uncross-linked from a substantial, real, and properly governed sub-project** — a
> `terminology-fetch` CLI, a full Svelte admin review UI (approve/disapprove with operator
> comments), a weekly-refresh scheduler, and real QUDT/UCUM/SIRP/Wikidata adapters with QUDT-linked
> entity expansion, all shipped 2026-08-06/07. This is not undocumented drift: it is "Keyword Steps
> 11-12" and the "External Terminology Portfolio," governed by spec `2026080403` §21 and tracked in
> its own plans (`ChenWeb/docs/superpowers/plans/2026-08-06-keyword-step1[12]-*.md`,
> `2026-08-07-external-terminology-resource-portfolio.md`), design specs
> (`ChenWeb/docs/superpowers/specs/2026-08-07-*.md`), and handoffs
> (`KnowledgeStore/doc-repo/hand-offs/202608/2026080401-*.md`, `2026080601-*.md`) — see the
> changelog entry immediately following the 2026-08-08 audit entry for the full build/status
> summary, including the precisely-scoped "closing I2" claim (true for the tier-6 identity-authority
> mechanism against real imported data; **not** true yet for the online resolve path against real
> document text through the pipeline).
>
> **2026-08-08, later the same day — spec-accuracy audit + ambiguity reconciliation.** A
> user-driven, code-verified accuracy pass over spec `2026080403` (prompted by exactly the "this
> ADR is not re-synced every session; that spec is" boundary stated above) found and corrected
> roughly twenty stale claims the 2026-08-05/06/07 dated notes above had not propagated everywhere
> in the spec body: the §9.1 tier-status table itself (tiers 2/4/5/7-auto-create still shown
> unbuilt after they had shipped), several §4 design-decision badges left at "Defect"/"not
> implemented" after their fixes landed (D3, D6, D7, D11), §9.3's description of a since-deleted
> `kb.keyword_mentions`/`MentionStore`, §10.2's lang-uniqueness gap (fixed by migration
> `20260805000002` the same day it was reported open), §18.1's test-coverage table (51 tests
> claimed; 176 keyword-package test functions exist as of this entry, 209 across
> keywords/semid/names), and §20.1.7's "resource import" entry still marked wholesale Deferred
> after the terminology-import tooling above was built. No code changed in this part of the pass —
> only the spec's description of it. Full corrected detail lives in the spec itself; this entry
> exists only so a reader of *this* ADR isn't misled by the "verified 2026-08-08" framing above
> into assuming that earlier pass was exhaustive — it wasn't, and this entry's corrections are the
> proof.
>
> **New the same session: ambiguity reconciliation (spec §13.6).** An `ambiguous` verdict (tiers
> 0-5 tied across more concepts than `KeywordFamily`'s `AutoAcceptPolicy.MaxCandidates` allows)
> used to pick the lowest concept id as an arbitrary tiebreak and log the tie to
> `kb.keyword_unresolved`, with nothing ever revisiting it. `Reconciler.ReconcileAmbiguous`
> (`cmd/keyword-reconcile`'s second pass; migration `20260808000001` adds
> `kb.keyword_unresolved.candidates`) now re-ranks that tie offline: re-verifies the tied concepts
> are still live (chasing any merge since the tie was logged), and for a genuine remaining tie,
> embeds the original query against each live survivor's label and auto-applies only on a clear
> margin or independent lexical corroboration — the same two-signal discipline already governing
> tier 6's merges (embeddings rank, they never decide alone). Never merges the tied concepts with
> each other (stays tier 6's job, D10-conservative) and never rewrites `kb.keyword_occurrences`
> (append-only by design) — only a new surface on the winning concept and a decision-log entry.
> sqlmock-tested only, not yet run against a live database — the same I2-class caveat the rest of
> this module carries.
>
> **§8.3.7 contradiction resolved:** `extract_metric_definitions`, `extract_test_methods`, and
> `extract_product_structure` (listed as "remain to be implemented" in §8.3.7's P4 section) are
> confirmed **built** — registered as routed `ProcessorSpec`s in the production processor list,
> writing candidates only (`kb.ontology_candidates` / `kb.semantic_decision_candidates`), exactly as
> Appendix A.1 already stated. §8.3.7 has been corrected accordingly.
>
> **2026-08-01 correction (post-review):** A same-day implementation review
> (`2026080106-devdoc-semos-p3-implementation-review.md`) found the "Built and complete" framing
> above overstated several items: the three Phase D stages were never registered as declared,
> routed `ProcessorSpec`s (DR5) — `assertions.RunPhaseD` was called from one hardcoded site in
> `control.go`, invisible to the DR5 planner and DR6 routing; the metric-value parser fabricated or
> mis-parsed values against corpus-shaped Chinese text (contradicting this log's "never a
> fabricated value" claim); the `DecisionCandidateStore.Propose` revision-supersede fix (§F3) was
> not mirrored in `AssertionStore.CreateRevision`, leaving the same class of bug live on the
> assertion side; and projection staleness (`MarkStale`/`RepairStaleProjections`) plus seam 5's
> association-resolver step and all of seam 7 had no real caller/consumer despite being described
> as complete. All five gaps were fixed in the same session (see the review doc's Recommendation
> section for the full list): `normalize_assertions`/`associate_semantics`/`project_semantics` are
> now real `ProcessorSpec`s (Phase C, routed, chained via `PostProcessDependsOn`, still gated by
> `SEMANTIC_ASSOCIATION_ENABLED`); the metric parser anchors numeric extraction to the matched
> comparator and no longer misreads a standard/document-number dash as a range; `AssertionStore
> .CreateRevision` now supersedes any non-superseded prior revision; `ProjectSemantics.Run` marks a
> build failure stale and is registry-driven via a new `RegisterProjectionRecordScope` (seam 7);
> and `AssociateSemantics.Run` plus the backlog drain are now driven by a new `AssociationResolver`
> registry and `NormalizeAllFamilies` respectively (seam 5) instead of hardcoded family lists.

*Exit:* spec §15.2 and §15.3 acceptance suites pass, including conflicting assertions remaining
separately queryable, corrupted projections detected and repaired, and evidence loss moving an
assertion to `unsupported` and back; the lexicon resolves the gold set above its promotion gate
with zero over-merges of `never_merge` pairs.

#### 8.3.7 P4 — Profiles, generic review, and comparison runtime *(generic runtime built 2026-08-01)*

**Built (L6/L7 runtime only):** generic versioned profiles/rules, governed lifecycle and release-visible reads,
immutable review/comparison scopes, pinned-scope review execution and auditable findings,
DR21/DR22 comparison runs/cells (see 2026-08-08 correction below — "cached" overstates it),
paired `required_assertion_pattern` SHACL output, and
authenticated authoring/execution/read APIs. All P4 migrations were live-validated on
`chenweb_test` through `20260801000011`.

**Remaining P4 work (corrected 2026-08-08):** ~~ADR §8.2's `extract_metric_definitions`,
`extract_product_structure`, `extract_test_methods`... remain to be implemented~~ — **this was
stale text, contradicted by this ADR's own Appendix A.1 and confirmed built by code verification**
(all three are registered, routed processors writing candidates only; see §8.3.6). The
structured-output extension of `extract_provisions` was not re-audited in the 2026-08-08 pass and
its status is unconfirmed. The real, code-verified remaining gaps are: `kb.recommendation_policies`
(DR21 rule 1) has no migration or code at all; seam 8 (`ReviewerToolRegistry`) has zero registered
tools; DR22's comparison runs are a write-once persist/read-back log with no dedup-by-watermark or
invalidation logic, despite the "cached" language above (§3.23); `kb.knowledge_store_bindings`
(DR18 items 3–4) does not exist. **Deferred data gate:** the ventilator benchmark/domain module is
validation data only. It is not part of the generic runtime and remains un-authored until a domain
owner supplies a traceable worked example and approved source values — **re-confirmed 2026-08-08
via the live database: `kb.ontology_modules` has 0 rows in the current instance, and no
pump/ventilator/医疗器械-named module exists in `server/cmd/ontology-seed` or anywhere else in the
repo.** 🏗️ **APP-SPECIFIC** — the benchmark belongs to the Document Review app, not the ontology
platform; see Change Log 2026/08/06.

* Profile and rule schema; rule-kind registry with paired evaluator and SHACL emitter (seam 6).
* The pilot 4b domain module authored end to end: classes, properties, profile, rules,
  competency questions, fixtures.
* Review-scope freeze; the spec §12.3 finding decision procedure; the six result categories.
* Reviewer tools from research §7.4 registered through seam 8.
* Knowledge-store ontology visibility and default review profiles (DR18 items 3–4).
* Category canonicalization retrofitted onto the kernel, resolving the standing
  `kb.category_alias_conflicts` backlog.
* **The strictness comparator and directional verdicts (DR21), and class-anchored comparison runs
  (DR22)** — the two mechanisms the target application cannot be built without. The pilot domain
  module supplies one part class, its metric definitions, and its expected-metric profile, so the
  first comparison matrix is real rather than a mock.

*Remaining pilot exit:* the spec §15.4 acceptance suite passes against the pilot module and fixture corpus —
including `missing` only under a declared closed dimension, `indeterminate` on unresolved rule
conflict, and SQL/Go versus SHACL parity on identical fixtures.

#### 8.3.8 P5 — Rule-driven routing enforced *(needs P1 + P4)*

* Tier-3 `classify_document`, gated on required-but-undetermined facets.
* Domain-module-supplied applicability rules promoted into a pipeline policy version.
* Measure against the P0 baseline using the existing benchmark tables (`kb.benchmark_*`):
  LLM cost per document, artifact yield, review recall/precision with routing on versus off.
* Enforce only where measurement shows no recall loss; leave the rest in shadow mode.

*Exit:* a documented, per-document-kind reduction in processor invocations with no measured loss
of review recall on the benchmark corpus; every skip explainable from its plan.

> **2026-08-08 status (verified against code, live database, and git history): Chunk I / I2 still
> has not landed — this ADR's 2026-08-03 "not yet complete" claim remains accurate today, not
> stale.** `classify_document`'s two-pass resolver, review-scope wiring, `document.doc_kind`-keyed
> clearance, and transactional checksum-correct promotion (Chunks A–H) are all real, working,
> tested code — confirmed independently. But four separate sources agree Chunk I never ran: no
> commit touches any P5 file after 2026-08-03 (`git log`); no devdoc or plan dated after
> `2026080304` mentions it; the exit-test suite's own comments mark the I2 criteria as unexecuted
> "live-proof pointers," not real tests; and the live `chenweb_test` database has **zero rows** in
> `kb.pipeline_routing_clearances`, `kb.doc_facet_values`, and `kb.ontology_applicability_proposals`
> — i.e. this machinery has never actually run against real data. Every commit from 2026-08-04
> through 2026-08-07 went into P3 Track B (keyword lexicon) and the terminology-import pipeline
> instead, not P5.

#### 8.3.9 P6 — Remaining artifact families *(needs P3; independent of P5)*

Summaries, semantic projections, topics, and scene blocks per spec §15 Phase 5 and §15.5:
grounded links, inherited candidates that never gain confidence through repeated derivation,
occurrence identity, and a labeled evaluation corpus with per-method precision thresholds before
any automatic acceptance.

> **2026-08-08 status (verified against code):** confirmed unstarted, exactly as scoped — nothing
> beyond pre-existing P3 decision-candidate infrastructure exists; `kb.input_store_membership` (the
> table OD8 schedules for this phase) does not exist.

#### 8.3.10 P7 — Publication and interoperability *(needs P2–P4)*

Versioned RDF/OWL/SKOS/SHACL artifacts, persistent dereferenceable IRIs, round-trip and parity
fixtures in CI (including the SQL-versus-SHACL parity gate moved here from spec §15.4.14 per
DR13), external consistency checks, and — only if a competency question justifies it — a reasoner
or triple-store projection.

> **2026-08-08 status (verified against code):** confirmed unstarted, except the P4-adjacent SHACL
> emitters already counted under seam 6 (§8.3.7) — no RDF/OWL/SKOS serialization, dereferenceable
> IRIs, or triple-store/reasoner code exists anywhere in the repo.

#### 8.3.11 Mapping to the prior phase plans

| This ADR | Research §12 | Spec §15 | Keyword docs |
|---|---|---|---|
| P0 | Phase 0 | (implicit) | spec merge (DR16) |
| P1 | — (new) | Phase 1 (partial: identifiers, boundaries) | — |
| P2 | Phase 1 | Phase 2 | kernel (research §5, §9) |
| P3 | Phase 2 (metric semantics) + Phase 3 | Phase 3 | keyword Phases 1–3 |
| P4 | Phase 4 | Phase 4 | keyword Phase 4 (context-aware) |
| P5 | — (new) | — | — |
| P6 | Phase 5 | Phase 5 | keyword Phase 5 |
| P7 | Phase 6 | — | — |

The two genuinely new phases remain P1 and P5 — the execution plane that neither prior document
specified. The keyword work is not a separate track: it becomes the second instantiation of the
P2 kernel.

## 9. Operational Behaviors

* Pipeline runs compute a plan before executing; the plan is persisted whether or not routing is
  enforced.
* With no active policy, or with `DOC_PIPELINE_PLAN_ONLY=true`, the pipeline behaves exactly as it
  does today.
* Facets are computed once per record and reused across reruns unless the source document changes.
* Ontology content is authored in Git, compiled to an immutable release, and activated by an
  explicit audited act; rollback re-points the activation pointer and deletes nothing.
* LLM output may create candidates in any queue; no LLM path activates a term, mapping, axiom,
  profile rule, module release, or pipeline policy.
* Phase D runs after indexing; its failures never delete or invalidate persisted artifacts.
* Deferred candidates are retried only on dependency-fingerprint change; schedules alone never
  re-invoke an unchanged LLM decision.
* Reviews freeze their scope; a re-run of a historical review against pinned releases reproduces
  its findings.

## 10. Consequences

Positive:

* One applicability mechanism serves both extraction and review, so a document type cannot be
  reviewed against requirements whose evidence was never extracted.
* Adding a domain is a data change, reviewed like code and released like code.
* The pipeline becomes explainable and measurable; "why did this processor run" is an API call.
* LLM cost falls where documents do not warrant a processor, without asking an LLM to make the
  call.
* Each of the eight seams lets a future capability be added without touching the mechanism, so the
  phases after P2 can genuinely proceed independently.
* Canonical identity is built once and reused four times, so a fix to merge safety or scope
  handling benefits objects, keywords, categories, and terms together.
* Knowledge stores become the natural scope boundary, so two projects can hold conflicting
  canonical objects and conflicting acronym meanings without contaminating each other.
* Ontology, pipelines, and lexicon seeds live in one reviewable, pinned data repository, so
  meaning evolves at its own cadence without a code release.

Costs and risks:

* More moving parts: two release/activation systems (ontology modules, pipeline policies) with
  separate approval paths, and a rule engine to maintain.
* Routing can suppress useful extraction. Mitigations: shadow mode, per-processor
  `OnUndetermined`, benchmark-gated enforcement in P5, and reversibility by de-activating the
  policy.
* Facet quality bounds routing quality. Mitigation: deterministic tiers first, confidence recorded
  per facet, and rules able to require a minimum confidence.
* DB-authored ontology requires curator discipline and does not scale to hundreds of contributors.
  Accepted for now; the candidate → promote path and a future authoring UI are the additive
  surfaces.
* Layer 4a becomes a bottleneck if domains frequently need new assertion kinds. Accepted
  deliberately — that bottleneck is the signal that the core model is wrong, and it should be
  visible.
* Blocking on routing conflicts stops ingestion when a policy is wrong. Mitigations: conflicts are
  detected at policy compile time in CI, not only at run time; the alarm names the offending ids;
  and `DOC_PIPELINE_ON_CONFLICT=fallback` is available without a redesign.
* Authoring governed content in the database removes the repository-pinning and stale-`ONTOLOGY_REPO_REF`
  failure modes entirely. The residual risk — content edited in place outside the lifecycle — is
  contained by the status state machine plus the immutable release: only the release path can reach
  `included_in_release`, and every released snapshot is checksummed and immutable.
* Over-merging in the kernel is the asymmetric risk across *all four* families now, not just
  keywords. Mitigations are inherited from DR16: tombstones, `never_merge`, locked human
  assertions, no transitive closure, and per-family promotion gates on a gold set.

## 11. Tests

Beyond the inherited suites (spec §15.2–§15.5, research §13), this ADR adds:

**Pipeline plane**

1. With no active policy, the planner's output equals the legacy processor set for every fixture
   document.
2. The DAG planner reproduces the current A/B/C ordering and concurrency for the current
   declarations, including the block-buffer clear after `static_analyzer`.
3. An explicit `operation` list overrides every rule (DR7 precedence order, each level tested).
4. Two rules with equal priority and conflicting effects produce `pipeline_rule_conflict` and fall
   through to `OnUndetermined`; nothing is silently chosen.
5. A skipped processor never leaves a partial artifact and never blocks record completion
   accounting.
6. A deferred processor records a dependency fingerprint and is re-evaluated — and only re-run —
   after that fingerprint changes.
7. Tier-3 classification is not invoked when tier-1/2 facets satisfy every required facet.
8. The persisted plan reproduces the same decisions when replayed against its pinned policy
   version and facet snapshot.

**Domain modules**

9. Authoring a new 4b module and activating it changes review behavior with no Go code change and
   no migration (the DR1 property).
10. A 4b module attempting to define an assertion kind, predicate, or value form fails compilation
    with a specific error.
11. A module release is atomic: all items activate together, dependency releases are pinned, the
    checksum is recorded, and a failed activation leaves the previous release active.
12. Rollback re-points activation and preserves both releases and the audit trail.
13. A material term-definition change produces a replacement term and deprecation link, never a
    mutated released term.

**Knowledge stores and pipeline selection**

14. A binding "knowledge store K1 → pipeline A" selects pipeline A for every document ingested
    into K1, and a document ingested with an explicit `requested_pipeline` overrides it — on the
    first run and on every rerun of that record.
15. Two equal-priority, equal-specificity bindings selecting different pipelines fail the run with
    `pipeline_state = failed`, write exactly one `alarms_errors` row naming both binding ids, and
    produce no artifacts.
16. The same conflict under `DOC_PIPELINE_ON_CONFLICT=fallback` walks
    document → knowledge store → user → tenant → system, runs the first unambiguous level, and
    records a warning alarm plus a plan annotation.
17. Policy compilation in CI detects the same conflict statically, before activation.

**Canonicalization kernel**

18. The same normalizer input produces the same key bundle across families and across restarts;
    bumping `KEYWORD_NORMALIZER_VERSION` re-indexes without losing a surface or a link.
19. A merge sets `merged_into`, keeps the losing row, and continues to resolve stale ids;
    an unmerge restores the pre-merge state from `origin_concept`.
20. Pairwise merge decisions A→B and B→C do **not** silently produce A→C.
21. A `never_merge` pair is never merged by any automatic path, and a locked human assertion is
    never modified by the reconciler.
22. The same acronym resolves to different concepts in two knowledge stores, and to neither when
    the scope is unknown and context is insufficient (`ambiguous`, not a guess).
23. Object-node reconciliation behavior is unchanged by the kernel's introduction (DR15.1 parity
    fixtures).

**Cross-cutting**

24. The same predicate expression evaluated by the extraction planner and the review-scope
    resolver yields the same result on the same fact set.
25. Installing a domain module that ships applicability rules does not change pipeline behavior
    until those rules are included in an activated pipeline policy.
26. A keyword concept aligned to a governed ontology term does not become one: deleting the
    alignment leaves both intact, and the lexicon never writes to `kb.ontology_terms`.

**Target application (DR20–DR23)**

27. The same part class plays `component` in one product scope and `product` in another, with one
    class and one identity, and rules keyed on class are unaffected.
28. A metric asserted on a sub-part appears in the parent module's roll-up carrying its asserted
    level, and does not merge with a module-level metric of the same property.
29. The strictness comparator returns `stronger` for `≥250` versus `≥200 cd/m²`, `equivalent`
    across a unit conversion, `conflict` for disjoint ranges, `incomparable` for overlapping
    ranges without containment, and `qualitative_only` when either side has no decidable limit.
30. A cell holding assertions from many editions of the same standard shows one representative by
    the frozen precedence policy, reports the remaining count, and leaves every underlying
    assertion independently queryable and unmerged.
31. `standard_absent` is returned only when the authority family is declared closed for that
    property; on an incomplete corpus the same query returns `indeterminate`.
32. A recommendation ("adopt the stricter input") is stored separately from the verdict that
    produced it, and changing the recommendation policy does not change any verdict.
33. A comparison run pinned to module releases and an assertion watermark reproduces its matrix
    exactly on rerun.

## 12. Documentation Impact

**What knowledge changed.** Layer 4 is now two tiers with an enforced constraint between them;
domain modules have a concrete authoring, validation, release, and activation mechanism, in a
dedicated data repository; applicability is a shared service rather than a review-only concern;
the document pipeline is a planned, gated DAG with two-tier routing, knowledge-store binding, and
a per-run execution plan; document facets exist as governed first-class facts; canonical identity
is one kernel with four instantiations rather than four bespoke resolvers; the semantic-web
standards are adopted at four separately-decided levels; and the open representation questions for
assertion references and object classification are decided.

**Documents affected.**

* `Capsules/coding-capsules/doc-processor/+CAPSULE.md` — §7 pipeline model (stage DAG, gates,
  Phase D), §12 "Add New Doc Processor" checklist (add the declaration step), new status JSON for
  `classify_document`, `normalize_assertions`, `associate_semantics`, `project_semantics`.
* `Capsules/coding-capsules/doc-processor/extract-metrics-spec.md` and the provision, inventory,
  entity-relation, summary, topic, scene specs — normalized assertion output contracts.
* `Capsules/coding-capsules/doc-processor/doc-processor-dashboard-spec.md` — plan display,
  skipped/deferred processors, `PIPELINE_FINAL_OPS` and `ALL_PROCESSOR_IDS`.
* ADR 2026061801 (document review) — review-scope freeze, profile-governed findings,
  ontology-aware reviewer tools.
* ADR 2026070101 (object-centric design) — `ontological_level`, identity scope, classification as
  assertion.
* ADR 2026072301 (input deletion) — deletion contract must cover facets, candidates, assertions,
  evidence, links, keyword mentions, and projections.
* Specs `2026072301-spec-keyword-canonicalization-reconciliation` and
  `2026072703-spec-keyword-canonicalization-reconciliation-2` — **both superseded** by a single
  merged spec written in P0 per DR16. Neither should be implemented as written. Until the merged
  spec exists, both still need explicit status notes pointing here.
* Research `2026072301-rsch-keyword-mgmt` — remains valid as research; its scope-type ladder and
  relation taxonomy are adopted, its standalone-module framing is superseded by DR15.
* Knowledge-store documentation and the ingestion API spec — `ks_id`, `requested_pipeline`, and
  store bindings.
* `Capsules/coding-capsules/doc-processor/extract-metrics-spec.md` — **structured value output**
  (value form, comparator, normalized value, unit term, condition, assertion kind). Today's
  `threshold_or_target` free-text column cannot support a verdict, so this spec change gates the
  target application.
* New processor specs and impl docs for `classify_document`, `normalize_assertions`,
  `associate_semantics`, `project_semantics`, `extract_metric_definitions`,
  `extract_product_structure`, and `extract_test_methods`.
* `KnowledgeStore/database-table-schemas/` — every new table.
* A new capsule `KnowledgeStore/Capsules/coding-capsules/ontology/+CAPSULE.md` for the module
  source format, compiler, and release workflow.

**What knowledge changed?** The ADR now records the verified deployed P0 baseline, the complete
pilot competency-question contract, the ontology terminology support boundary, and the remaining
blockers for P0 exit.

**Which docs/specs/ADRs/tests are affected?** ADR `2026072901`, spec `2026073004`, and handoff
`2026073002` are affected. No code tests or application behavior changed in this documentation
slice.

**Which docs were updated?** This ADR, spec `2026073004-spec-semos-p0-completion.md`, and handoff
`2026073002-handoff-semos-ontology-status.md`, handoff-updated on 2026-07-31 to reflect
P0 closeout rather than an in-progress P0 state.

**Which docs are now stale?** The two superseded keyword specs still remain unmerged until DR16's
replacement is written. `+CAPSULE.md` §7.1–§7.3 still becomes stale the moment P1 lands and must be
updated in that same change. Research §5.4 and spec §7's differing Layer-4 descriptions remain
superseded by DR1 and should keep pointing here.

**Intentionally left undocumented.** Future physical DDL, executable future-schema SQL, the
authoritative medical-standard source content itself, governance person assignments, and ontology
repository hosting credentials remain for later phase documents and approvals.

## 13. Open Decisions

> **2026-08-08 status:** OD2, OD4–OD10 were checked against the actual code and live database as
> part of a full code-verification pass and confirmed unmoved — none has been resolved since the
> last revision. Notably OD8's `kb.input_store_membership` does not exist yet (consistent with P6
> not having started) and OD9's lexicon scope is still a flat string, not store+domain+document.

| # | Decision | Recommendation |
|---|---|---|
| ~~OD1~~ | ~~Which domain module is the pilot~~ | **Resolved 2026-07-29: 呼吸机 / 医疗器械**, driven by the target application. Corpus collection is under way. Open sub-item: the authoritative standard editions that source the profile come from the real-data worked example, not from the application mock — the mock's clause citations and limit values are placeholders |
| OD2 | Whether facet vocabulary lives in `document-authority` or its own 4a module | Start in `document-authority`; split if it grows past ~40 terms |
| ~~OD3~~ | ~~Where pipeline policies are authored~~ | **Resolved by DR17:** data repository, same compiler and activation as ontology modules |
| OD4 | Whether Phase D runs inline or asynchronously by default | Inline for the pilot corpus; move to `kb.scheduled_jobs` when association latency exceeds pipeline latency |
| OD5 | Multi-jurisdiction precedence vocabulary | Deferred (spec §17.4); unresolved conflicts stay `indeterminate` |
| OD6 | Hard-deletion and retention for `unsupported` assertions and rejected candidates | Deferred (spec §17.10); indefinite audited retention until decided |
| OD7 | Ontology source-tree name, hosting, and access model | Working name `semos-ontology`; host and access model remain open, but this is no longer a P0 gate. Current workspace policy keeps documentation in `KnowledgeStore` and implementation in `shared` or `ChenWeb` until a dedicated source tree is intentionally created |
| OD8 | Whether a document may belong to several knowledge stores | **Resolved in principle, deferred to P6.** Yes, eventually. The governing constraint: a document is processed **once** — artifacts are keyed by `record_id`, and store membership is a *view* (a join), never a copy — while a store must expose every artifact of every document it contains. The open part is scope: identity and lexicon resolution are scope-keyed by store (DR18), so a shared document resolves under its primary store for materialized identity, with read-time re-resolution for secondary stores. Ship `ks_id` as a single FK now; add `kb.input_store_membership` in P6 |
| OD9 | Scope granularity for the lexicon: knowledge store only, or store + domain + document | Store + document-local overrides in P3 (document-local acronym definitions are strong evidence); add domain if measurement shows collisions |
| OD10 | Whether category canonicalization retrofits onto the kernel in P4 or waits | P4, driven by the size of the `kb.category_alias_conflicts` backlog measured in P0 |

## 14. Glossaries

### 14.1 QUDT Mappings
**QUDT mappings** refers to mappings defined in the **QUDT** ontology that relate units, 
quantities, prefixes, or other measurement concepts to equivalent concepts in other standards 
or vocabularies.

QUDT is an ontology for representing scientific and engineering measurements in RDF/OWL. 
It provides standardized definitions for:

* Units (meter, second, kilogram, pascal, etc.)
* Quantity kinds (length, mass, pressure, temperature, etc.)
* Dimensions
* Prefixes (kilo-, milli-, micro-, etc.)
* Physical constants
* Unit conversion rules

For example, QUDT contains a concept like:

```turtle
qudt-unit:Meter
```

rather than merely the string `"m"`.

#### 14.1.1 What Are Mappings?

Many organizations have their own vocabularies for units and measurements. Examples include:

* UCUM
* OM
* GS1
* NASA internal vocabularies
* industry-specific ontologies

A **mapping** tells software that two identifiers refer to the same or closely related concept.

For example

```
QUDT
------
qudt-unit:Meter

UCUM
------
m

Mapping
-------
qudt-unit:Meter
    ↔
UCUM "m"
```

Similarly

```
qudt-unit:DegreeCelsius
    ↔
UCUM "Cel"
```

or

```
qudt-unit:Kilogram
    ↔
UCUM "kg"
```

These mappings allow systems using different ontologies to interoperate.

#### 14.1.2 Types of Mappings

In RDF/OWL, mappings are often represented using properties from **SKOS**, such as:

```
skos:exactMatch
skos:closeMatch
skos:broadMatch
skos:narrowMatch
```

or with QUDT-specific mapping properties.

For example:

```turtle
qudt-unit:Meter
    skos:exactMatch ucum:m .
```

meaning the QUDT Meter and UCUM "m" represent the same unit.

#### 14.1.3 Why Mappings Important

Suppose one dataset contains

```
height
unit = "m"
```

while another contains

```
height
unit = qudt-unit:Meter
```

Without a mapping, software may treat them as different.

With a mapping,

```
"m"
      ↓
UCUM
      ↓
QUDT Meter
```

the two datasets can be merged and queried consistently.

In **SemOS**, QUDT mappings could be very useful when extracting metrics from technical standards.
For example, different documents may express the same unit in different ways:

```
ms
millisecond
msec
milliseconds
毫秒
```

The extraction pipeline could normalize all of these to a single canonical QUDT concept:

```
qudt-unit:MilliSecond
```

Similarly,

```
℃
degree Celsius
degrees C
摄氏度
```

could all normalize to

```
qudt-unit:DegreeCelsius
```

Once normalized, we can:

* perform unit-aware searches,
* compare metrics across multilingual documents,
* automatically convert compatible units (e.g., mm ↔ cm ↔ m),
* and export data to other standards (such as UCUM) using the available mappings.

In short, **QUDT mappings are crosswalks between QUDT's standardized measurement 
ontology and other unit vocabularies or coding systems**, enabling interoperability 
and consistent interpretation of measurements across different datasets and applications.

## 15. Outstanding Implementation Work (Not Yet Finished)

**Added 2026-08-08.** This section consolidates every item the 2026-08-08 code-verification pass
(§1 changelog) and the original phase plan (§8.3) confirm is not yet built or not yet complete,
into one cross-referenced punch list. It is an **inventory for planning, not a plan** — no
priority, owner, or sequencing is assigned here. Each phase's own prerequisites (stated in §8.3's
headers, e.g. "P5 *(needs P1 + P4)*") already constrain the order; use this list as the input to
that planning pass, not a substitute for it. Every row cites the ADR section where the gap was
found so the reasoning behind it doesn't need to be re-derived.

### 15.1 P1 — Pipeline plane

| Item | Gap | Ref |
|---|---|---|
| DAG planner | The core DR5 mechanism — a topological wave scheduler built from `Requires`/`Produces` — was never built. What is actually built is `Doc Processing Policy`. A policy is actually a DAG. This is the architecture we are going to use. In the current implementation, no gates are supported and no checking (handle requires and produces) is done yet. This should be good enough for now. Advanced features will be added later one, as needed. Phase A/B/C is still a hardcoded loop; `Requires` / `Produces` / `Class` / `Cost` / `OnUndetermined` are untyped strings, not the typed enums DR5 specifies; no `DeclaredProcessor` interface exists. | §3.6, §8.3.4 |
| Deferred-gate retry | A deferred processor's dependency fingerprint is computed but nothing re-evaluates it later — defer is currently terminal within a run. | §3.6 |
| ~~Facet tiers 1–2~~ | **Resolved 2026-08-09.** `ComputeTier1Facets` / `tier2FacetsFromSource` are real production producers now (`facet_tier1.go` / `facet_tier2.go`), wired unconditionally into `ControlService.handleEvent` and `ExtractDocMetadataProcessor.HandleEvent` respectively, both writing to `kb.doc_facet_values` via the same path tier 3 uses. As a side effect, tier 3 (`classify_document`) is no longer `mandatory_gated` / env-flag-gated either — it is `Class: "routed"`, gated per-document by an ordinary `kb.pipeline_rules` row instead of `CLASSIFY_DOCUMENT_ENABLED` (deleted). | §3.5, §8.3.4 |
| Execution-plan UI | `kb.doc_process_plans` and its API (`GET /kb/doc-proc-plans`) are real, but no frontend dashboard panel consumes it yet — API-only. | §3.7, §8.3.4 |
| `kb.scene_objects. object_id` → `scene_block_id` rename | Never done. | §5, Appendix C.7 |
| ~~`kb.pipeline_rules` never populated~~ | **Resolved 2026-08-09 for the unconditional case.** `SeedDocProcessingPolicies` now writes one unconditional (`require`, always-true predicate) `kb.pipeline_rules` row per processor per policy — verified live on `miner` (14 rows). **Still open:** `config.local.toml`'s `[doc-processing-policy-*]` format has no syntax for a genuine conditional gate (predicate / `required_facets`); authoring one still requires a raw `POST /kb/pipeline-rules` call. | §1 changelog 2026-08-09, Appendix C.1 |

### 15.2 P2 — Ontology core & canonicalization kernel

| Item | Gap | Ref |
|---|---|---|
| `document-authority`, `measurement`, `quantity` 4a modules | Seed/import code exists (since 2026-07-31 for the first two) but has never actually been released and activated against the live database — only `core` is active. **Added 2026-08-09:** `quantity` now has a second, live write path — approving the `qudt` resource on System Admin → Resources → Review External Resources now also writes `quantity_kind`/`unit`/`dimension` terms into `kb.ontology_terms` and releases+activates the `quantity` module (`terminologyresourcehandler.ApproveResource`, `openspec/changes/external-resource-approve-ontology-terms`), alongside the existing keyword-lexicon staging write. This is a capability, not yet a completed run: no operator has clicked Approve against the real QUDT catalog yet, so `document-authority` and `measurement` are unaffected and `quantity` is still zero live rows as of this note. **RESOLVED (quantity only) 2026-08-09, later same day:** an operator ran the real Approve against `miner`; `quantity` is now active with 4213 live rows (see §1 changelog for the full account, including a bug found and fixed in the same run). `document-authority` and `measurement` remain untouched — this row's gap still stands for those two. | §8.3.5, Appendix B.2 |
| QUDT import verification | The `quantity` module's claimed 4151-term catalog has never been run/verified against a live instance; the figure has no corroborating evidence in the repo. **Added 2026-08-09:** the Approve action described above is the mechanism that would generate that evidence (it writes governed terms directly into `kb.ontology_terms`, distinct from the "external terminology portfolio" QUDT 3.5.0 import elsewhere in this row's original text, which populates only the keyword lexicon's tables). Still unverified until an operator runs it end-to-end against the real catalog and someone counts the resulting rows. **RESOLVED 2026-08-09, later same day:** verified end-to-end against `miner`. The "4151" figure was never real — the actual, reconciled total is **4213** rows (1125 `quantity_kind` + 2843 `unit` + 245 `dimension`), each figure equal to QUDT 3.5.0's real raw resource count minus its deprecated entries (1223−98, 2928−85, 247−2), confirmed by parsing the downloaded `qudt-all.ttl` directly. See §1 changelog for the bug that made the first run's `dimension` count zero before this. | §8.3.5, Appendix B.2 |
| `semid` kernel adjudication | Only 4 verdicts exist in code (`auto_accepted`/`ambiguous`/`deferred`/`human_review`); no distinct "LLM-batch" path as DR15 describes. | §3.17 |
| DR15.1 object-family kernel adoption | `kb.object_nodes.merged_into`/`scope_key` columns exist but the object reconciler never reads or writes them — contracts are scaffolding, not wired. | §3.17, Appendix C.7 |
| `deontic` 4a module | Defined once in DR1 (§3.2) and never revisited: no seed code, no `kb.ontology_modules` row, no authoring surface. `extract_provisions` writes to the pre-existing, ungoverned `kb.provisions` table instead. | §3.2, Appendix B.2 |
| `occurrence` 4a module | Same as `deontic` — design-only. `core`'s installed vocabulary absorbed a bare `occurrence` term (`ontological_level`), but the full scene-block contract (participant/action/state/cause/outcome) was never built. `generate_scene_blocks` (pre-ADR, unchanged) writes ungoverned scene evidence instead. | §3.2, Appendix B.2 |
| `inventory` 4a module | Same as `deontic` — design-only. `extract_inventory_items` (pre-ADR, unchanged) writes ungoverned evidence to `kb.search_artifacts` (`inventory_item` partition) instead; the `normalize_assertions` normalizer that would eventually turn it into candidate assertions is not built (only metric/provision normalizers exist, §8.3.6). | §3.2, Appendix B.2 |

### 15.3 P3 Track A — Assertions & Phase D

| Item | Gap | Ref |
|---|---|---|
| `kb.artifact_semantic_links` | Not built yet (the ADR's own Appendix A.1 already correctly flags this as future). | Appendix A.1, C.3 |
| `assertions.RunPhaseD` | Orphaned dead code left over from the pre-fix hardcoded call site — zero callers anywhere in the repo. Safe cleanup, not a functional gap. | §8.3.6 (P3 Track A audit) |
| Backlog-drain admin surfaces (DR6/DR7 halves) | An admin review page for `kb.semantic_decision_candidates` and LLM auto-resolution for deferred assertions are both still unbuilt. | §8.3.6 |
| `extract_provisions` structured-output extension | Not re-audited in the 2026-08-08 pass; status unconfirmed either way. | §8.2 |

### 15.4 P3 Track B — Keyword lexicon & external terminology portfolio

| Item | Gap | Ref |
|---|---|---|
| Full R1–R7 reconciliation orchestration | Only R3 (blocking) and R6/R7-equivalent (veto + transactional apply/audit) logic exists inside one `Reconciler.Run`. R1 (harvest), R2 (prune), R4 (assemble), R5 (LLM batch-decide), and a runs/watermark table are not built. | §8.3.6, changelog 2026/08/08 (sub-project entry) |
| `on` mode | Still indistinguishable from `observe` in code — no distinct consumer wiring to retrieval or search payloads. | §7, §8.3.6 |
| Double Metaphone phonetic key | Current `phoneticKey()` is a documented stub (first char + first 4 consonants). | §8.3.6 |
| Batch adjudication UI | No admin surface for the `kb.keyword_unresolved` backlog (REST covers concept/surface/rewrite-rule CRUD only). | §8.3.6 |
| Rewrite-rule auto-promotion | Tier-3 rewrite rules are authored manually only; no promotion from reconciliation decisions. | §8.3.6 |
| `KEYWORD_RESOLVER_MODE` hot-reload | Read once via `sync.Once` at startup; a mode change needs a process restart. | §7 |
| §15.1 governed-catalog bootstrap | No released `metric_definition` terms exist yet for the observe-path auto-align to target — this is the external precondition that gates the `aligns_to_term`/metric-integration end-to-end run. | changelog 2026/08/08 (sub-project entry) |
| Online resolve-path live proof | The keyword module (`ResolveName`/`ResolveAndObserve`) has never been run against real document text flowing through the doc-processing pipeline — distinct from, and *not* closed by, the offline reconciler's live-DB proof (which is done). | changelog 2026/08/08 (sub-project entry) |
| IEC 60050-845 (IEV) seed content | Deliberately unautomatable (copyright-gated); needs an operator-reviewed manual seed file. | changelog 2026/08/08 (sub-project entry) |
| Production portfolio activation | Operator must: review/approve the remaining fetched draft (the QUDT-linked Wikidata set), supply the reviewed IEC seed/promotion file, run the corpus/coverage acceptance report, and publish a versioned production seed release — before Tier 6 can be enabled in production. | changelog 2026/08/08 (sub-project entry) |
| `CollectFromText` mention collector | Still standalone, not wired into the Phase C pipeline — corpus-wide mention recall is absent; only targeted metric-name resolution (`names.Resolver` in the metrics pipeline) is wired today. | §8.3.6 |

### 15.5 P4 — Profiles, review & comparison

| Item | Gap | Ref |
|---|---|---|
| `kb.recommendation_policies` | No migration, no code — DR21 rule-1's verdict/recommendation separation isn't built at all. | §3.23, §8.3.7, Appendix B.1, C.6 |
| Seam 8 (`ReviewerToolRegistry`) | Completely unbuilt — zero registered tools anywhere in the repo. | §3.12, §8.3.7 |
| DR22 comparison-run caching | Currently a write-once persist/read-back log. Needs real dedup-by-`(scope, watermark)` and invalidation when the watermark or pinned releases move, to match the "cached" claim. | §3.23 |
| Pilot 4b domain module (呼吸机 / 医疗器械) | Un-authored — `kb.ontology_modules` has 0 rows live. Needs a domain owner to supply a traceable worked example and approved source values (the P4 "deferred data gate"). | §3.13, §8.3.7, Appendix B.3 |
| Category canonicalization retrofit | Not started; scheduled "P4+," driven by the size of the `kb.category_alias_conflicts` backlog (OD10). | §8.3.7, OD10 |
| `CorpusDataset` → orchestrator wiring | Still not wired to invoke a live doc-processor pipeline. The original blocker (`extract_metrics`/`normalize_assertions` not built) is now cleared, but the wiring step itself was not re-audited in the 2026-08-08 pass. | §3.22 |
| Review-scope rerun-reproducibility test | Immutability is real (no update path exists), but no test directly proves a rerun against the same frozen scope reproduces identical findings. | §8.3.7 (P4 audit) |

### 15.6 P5 — Rule-driven routing enforcement *(needs P1 + P4)*

| Item | Gap | Ref |
|---|---|---|
| Chunk I / I2 live-PostgreSQL + synthetic-corpus proof | Not run. Zero live rows in `kb.pipeline_routing_clearances`, `kb.doc_facet_values`, and `kb.ontology_applicability_proposals` — this machinery (Chunks A–H, which are real and working) has never executed against real data. | §1 changelog (2026/08/03, 2026/08/08), §8.3.8 |

### 15.7 P6 — Remaining artifact families *(needs P3; independent of P5)*

Entirely unstarted beyond pre-existing P3 decision-candidate infrastructure: grounded links,
occurrence identity, inherited-candidate confidence discipline, and a labeled evaluation corpus
with per-method precision thresholds for summaries/projections/topics/scene blocks. `kb.input_store_membership`
(OD8) does not exist. §8.3.9.

### 15.8 P7 — Publication & interoperability *(needs P2–P4)*

Entirely unstarted except the P4-adjacent SHACL emitters already built under seam 6 for one rule
kind (`required_assertion_pattern`). No RDF/OWL/SKOS serialization, dereferenceable IRIs, or
triple-store/reasoner code exists. §8.3.10.

### 15.9 Open Decisions still open

OD2, OD4, OD5, OD6, OD8, OD9, and OD10 remain unresolved exactly as §13 states (re-verified against
code 2026-08-08 — none has moved). OD1, OD3, and OD7 are already resolved/settled and are not
outstanding work. See §13 for each decision's current recommendation.

## 16. References

0. [2026073104-plan-semos-p2-ontology-core-and-canonicalization-kernel](/Users/cding/Workspace/KnowledgeStore/doc-repo/plan/202607/2026073104-plan-semos-p2-ontology-core-and-canonicalization-kernel.md) — P2 implementation plan (DB-native storage revision, chunks 0–F)
1. [2026072302-rsch-object-centric-ontology](/Users/cding/Workspace/KnowledgeStore/doc-repo/research/202607/2026072302-rsch-object-centric-ontology.md)
2. [2026072702-spec-ontology-canonical-artifacts](/Users/cding/Workspace/KnowledgeStore/doc-repo/specs/202607/2026072702-spec-ontology-canonical-artifacts.md)
3. [2026072701-adr-ontology-identity-and-assertions](/Users/cding/Workspace/KnowledgeStore/doc-repo/adrs/202607/2026072701-adr-ontology-identity-and-assertions.md)
4. `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md`
5. [2026070101-adr-object-centric-design](/Users/cding/Workspace/KnowledgeStore/doc-repo/adrs/202607/2026070101-adr-object-centric-design.md)
6. [2026070701-adr-object-reconciliation-ambiguous-tie-resolution](/Users/cding/Workspace/KnowledgeStore/doc-repo/adrs/202607/2026070701-adr-object-reconciliation-ambiguous-tie-resolution.md)
7. [2026071201-adr-doc-process-runs](/Users/cding/Workspace/KnowledgeStore/doc-repo/adrs/202607/2026071201-adr-doc-process-runs.md)
8. [2026071301-adr-doc-processor-benchmark](/Users/cding/Workspace/KnowledgeStore/doc-repo/adrs/202607/2026071301-adr-doc-processor-benchmark.md)
9. [2026072301-adr-kb-input-artifact-deletion](/Users/cding/Workspace/KnowledgeStore/doc-repo/adrs/202607/2026072301-adr-kb-input-artifact-deletion.md)
10. [2026072301-rsch-keyword-mgmt](/Users/cding/Workspace/KnowledgeStore/doc-repo/research/202607/2026072301-rsch-keyword-mgmt.md)
11. [2026072301-spec-keyword-canonicalization-reconciliation](/Users/cding/Workspace/KnowledgeStore/doc-repo/specs/202607/2026072301-spec-keyword-canonicalization-reconciliation.md) — superseded by DR16
12. [2026072703-spec-keyword-canonicalization-reconciliation-2](/Users/cding/Workspace/KnowledgeStore/doc-repo/specs/202607/2026072703-spec-keyword-canonicalization-reconciliation-2.md) — superseded by DR16
13. W3C SHACL, SKOS, PROV-O, OWL 2, OWL-Time; QUDT catalog; SOSA/SSN — as cited in research §18.
14. UMLS concept/term/string identity layering (CUI/LUI/SUI/AUI) — as cited in research
    `2026072301` §1 and spec `2026072703` §3.1.
15. [2026080403-spec-keyword-canonicalization-and-reconciliation](/Users/cding/Workspace/KnowledgeStore/doc-repo/specs/202608/2026080403-spec-keyword-canonicalization-and-reconciliation.md) — the governing keyword-module spec (DR15/DR16/DR23 implementation); §21 is the living implementation record (added 2026-08-08)
16. [2026080401-handoff-semos-p3-trackb-keyword-lexicon](KnowledgeStore/doc-repo/hand-offs/202608/2026080401-handoff-semos-p3-trackb-keyword-lexicon.md) (added 2026-08-08)
17. [2026080601-handoff-keyword-step11-step12-reconciliation-and-aligns-to-term](/Users/cding/Workspace/KnowledgeStore/doc-repo/hand-offs/202608/2026080601-handoff-keyword-step11-step12-reconciliation-and-aligns-to-term.md) (added 2026-08-08)
18. `ChenWeb/docs/superpowers/plans/2026-08-06-keyword-step11-tier5-reconciliation.md` (added 2026-08-08)
19. `ChenWeb/docs/superpowers/plans/2026-08-06-keyword-step12-aligns-to-term-metric-integration.md` (added 2026-08-08)
20. `ChenWeb/docs/superpowers/plans/2026-08-07-external-terminology-resource-portfolio.md` (added 2026-08-08)
21. `ChenWeb/docs/superpowers/specs/2026-08-07-external-terminology-resource-portfolio-design.md` (added 2026-08-08)
22. `ChenWeb/docs/superpowers/specs/2026-08-07-model-agnostic-tier6-validation-design.md` (added 2026-08-08)
23. `ChenWeb/docs/superpowers/specs/2026-08-08-doc-processing-policy-design.md` — the "Doc Processing Policies" design, first real content authored into DR6's pipeline/binding mechanism (added 2026-08-08)
24. `ChenWeb/docs/superpowers/plans/2026-08-08-doc-processing-policy.md` — its implementation plan (added 2026-08-08)
25. `ChenWeb/docs/superpowers/plans/2026-08-06-keyword-step11-tier5-reconciliation.md`
26. `2026-08-06-keyword-step12-aligns-to-term-metric-integration.md`
27. `2026-08-07-external-terminology-resource-portfolio.md`
28. `ChenWeb/docs/superpowers/specs/2026-08-07-external-terminology-resource-portfolio-design.md`
29. `2026-08-07-model-agnostic-tier6-validation-design.md`
30. `2026080601-handoff-keyword-step11-step12-reconciliation-and-aligns-to-term.md`

## Appendix A. New Doc Processors

**Purpose.** This appendix enumerates every doc processor this ADR adds or changes — what it does, whether it
generates new persisted data (and which tables that data lands in), and whether it is LLM-driven. "New" means the
processor did not exist in the pre-ADR 13-processor roster; "changed" means an existing processor's output
contract is extended. Each processor declares a DR5 `ProcessorSpec` (class, cost, `OnUndetermined`); a `routed`
processor runs only when the selected pipeline policy and its per-processor gates resolve to run.

> Every `ProcessorSpec` (this appendix's processors included) also declares `Requires`/`Produces` — the DR5
> artifact-kind dependency vocabulary. These are **not stored in any database table** (not `kb.pipeline_rules`,
> not anywhere else) — they are hardcoded Go string-slice literals in `productionProcessorSpecs`
> (`processor_plan.go`), read at build time only. §3.6 covers why: the DAG planner that would actually consume
> them to build a dependency-ordered wave schedule does not exist yet: Phase A/B/C is still a hardcoded
> `[]string{"A","B","C"}` loop, so `Requires`/`Produces` are declared metadata, not an enforced or persisted
> contract, as of this revision.

**"LLM-driven" values.** `expensive_llm` = per-chunk LLM extraction (normal Phase B cost); `cheap_llm` = one LLM
call per document (tier-3 classification); `none` = deterministic code, no model invocation. Where a processor's
adjudication is currently deterministic-only, that is noted.

### A.1 New processors

| Processor | Build (2026-08-01) | Class | LLM-driven | What it does | New persisted data → table | Phase | Why |
|---|---|---|---|---|---|---|---|
| `classify_document` | built, two-pass resolver, wired into review-scope selection. It is `routed`, gated per-document by an ordinary `kb.pipeline_rules` row (`target_processor="classify_document"`),  see §3.5, §15.1. Not yet exercised against live data — see §8.3.8's Chunk I / I2 status. | routed | `cheap_llm`, tier 3 only — one call over the first N pages, only when tiers 1–2 leave a required facet undetermined and a rule needs it | Classifies a document into the governed facet vocabulary: `doc_kind`, `domain`, `normative_status`, `jurisdiction` | **Yes** — governed document facets → `kb.doc_facet_values` (not `kb.doc_facets`, which is a separate, simpler routing-facets table) | P1 (tier 3: P5) | DR4 routing + profile applicability |
| `normalize_assertions` | built (P3) | routed (Phase C) | `none` — deterministic per-family normalizers (metric, provision) | Turns each artifact family's output (metrics, provisions, later inventory/entity/scene) into candidate qualified assertions with evidence | **Yes** — candidate assertions → `kb.semantic_decision_candidates` (`candidate_kind='assertion'`); never writes assertions directly | P3 | DR8 Phase D stage 1; the step that makes free-text claims comparable |
| `associate_semantics` | built (P3) | routed (Phase C) | `none` in the current slice — deterministic-only adjudication; a future LLM-scored path can only *feed* candidates, never write | Spec §10.3–§10.7: resolve, validate, adjudicate, persist stage-1 candidates as accepted assertions; resolves units against the `quantity` module | **Yes** — accepted assertions → `kb.semantic_assertions` (DR9 typed refs + normalized value columns); evidence → `kb.assertion_evidence`; conflict/supersession → `kb.assertion_relations` | P3 | DR8 Phase D stage 2; the one authoritative-owner persist step |
| `project_semantics` | built (P3) | routed (Phase C) | `none` — deterministic SQL/Go derivations | Spec §10.8: build derived edges, search payloads, convenience classifications from accepted assertions; mark and repair stale projections | **Yes** — derived projection `kb.object_nodes.primary_class_term_id` (never authored); build state → `kb.projection_state`; future `kb.artifact_semantic_links` when a family needs `about`/`aligns` links | P3 | DR8 Phase D stage 3; DR10 |
| `extract_metric_definitions` | built (routed Phase B harvester) | routed | `expensive_llm` | Harvests the *definition* of a metric — canonical name, aliases, value type, range type — from 术语与定义 and requirement clauses, distinct from a metric *value* | **Yes, candidates only** — `kb.ontology_candidates` (`candidate_kind='term'` / `metric_definition`) with source spans; never writes content rows | P3–P4 | DR23; the main feeder of metric-definition rows and 4b module content via candidate → promote |
| `extract_test_methods` | built (routed Phase B harvester) | routed | `expensive_llm` | Extracts test/measurement procedures and explicit metric↔procedure (`mea:measured_by`) links | **Yes, candidates only** — procedure terms → `kb.ontology_candidates`; metric↔procedure links → `kb.semantic_decision_candidates`, with source spans | P4 | the 检测方法 panel; a metric's procedure is part of its comparability key (research §6.3) |
| `extract_product_structure` | built (routed post-process) | routed | `none` — no additional LLM; converts only explicit `part_of`/`component_of` relations with reconciled object endpoints from entity/relation output | Converts explicit structural relations into part-of / component-of structural candidates | **Yes, candidates only** — `kb.semantic_decision_candidates` (structural candidates, reconciled endpoints, source spans) | P4–P5 | DR20 hierarchy; drives module/sub-part navigation and image hotspot bindings |

### A.2 Changed processors

| Processor | Build (2026-08-01) | Class | LLM-driven | What it does | New persisted data → table | Phase | Why |
|---|---|---|---|---|---|---|---|
| `extract_metrics` | changed; structured output built 2026-08-01 | routed | `expensive_llm` | Emits structured value fields — value form, comparator, normalized value, unit, condition, assertion kind — instead of `threshold_or_target` free text | **Yes** — `kb.metrics` gains `value_min`/`value_max`/`condition` (migration `20260801000014`) plus structured fields `value_range_type`/`value_class`/`metric_value`/`metric_unit` (prompt v5); normalizer consumes them deterministically; `parseThresholdOrTarget` demoted to a legacy fallback | P3 | today `threshold_or_target` free text prevents any verdict; the single highest-leverage change for the application (DR21) |
| `extract_provisions` | changed | routed | `expensive_llm` | Retains any explicit applicability/scope clauses, authority, and effective interval; never infers missing values | **Yes** — `kb.provisions` extended with structured `public_info` evidence fields | P3–P4 | profile rules are sourced from provisions; the 范围/适用于 clause decides applicability |
| `extract_doc_metadata` | changed | mandatory | `expensive_llm` | Adds standard identity: doc number, edition, issuer, jurisdiction, supersedes | **Yes** — `kb.inputs.doc_metadata` (extended JSONB); feeds `kb.doc_facets` tier 2 | P1 | column assignment and precedence inside a comparison column both depend on standard identity (DR21/DR22) |

### A.3 Explicitly not doc processors

The comparison matrix and verdict computation (DR22, an L7 application service), profile evaluation (L6), the
certification-body registry (reference data, not extraction), and the product image hotspot map (application data
binding an image region to an object node).

### A.4 Unchanged processors

The pre-ADR 13-processor core — `blocking`, `structure_analyzer`/`static_analyzer`, `chunking`,
`extract_metadata`, `extract_metrics`, `extract_provisions`, `extract_semantic_projections`, `generate_summaries`,
`generate_topics`, `generate_scene_blocks`, `extract_entity_relation`, `extract_inventory_items`, `review_document`
— keeps its behavior; it only gains the DR5 `ProcessorSpec` declaration in P1. With no policy activated, the
planner reproduces today's set byte-identically (DR6/DR7).

## Appendix B. Ontology Content

**Purpose.** This appendix enumerates all ontology content the architecture governs — terms, labels, axioms,
mappings, profiles, profile rules, modules, releases, candidates, and the related governed content (document
facets, pipeline policies, knowledge-store bindings, keyword lexicon, comparison policies) — the tables that store
them, what they hold, and how they are generated or from which source they are imported.

**Governing principle (DR2/DR17).** Ontology content is authored and versioned **in the database** with `version`
columns; there is no data-only Git repository. Extracted pipeline artifacts are evidence and never auto-promote to
ontology content (ADR §3.3.1).

### B.1 Content stores

| Content | Table | Holds | Versioning / identity | Authoring / generation surface | Phase |
|---|---|---|---|---|---|
| Terms | `kb.ontology_terms` | governed terms, `term_kind` = class/property/individual/concept/metric_definition/quantity_kind/unit/dimension | `UNIQUE(term_id, version)`; an accepted change inserts a new version row | `ontology-seed` (curated 4a); `qudt-import` (quantity); candidate → promote; API `POST /kb/ontology/terms` | P2 |
| Term labels | `kb.ontology_term_labels` | language labels, `label_role` = prefLabel/altLabel/hiddenLabel; one prefLabel per term+language | per-term version | `ontology-seed`; `qudt-import`; API `POST /kb/ontology/terms/:term_id/labels`; promotion | P2 |
| Axioms | `kb.ontology_axioms` | compiler-approved axiom kinds over governed term refs | per-axiom version | **only** candidate → promote (`promoteAxiom`); no direct route | P2 |
| Mappings | `kb.ontology_mappings` | mappings to governed terms or external IRIs, `relation` = exact/close/broad/narrow/related; exact requires approval | per-mapping version | `qudt-import` is the only direct path; general mappings via promotion | P2 |
| Candidates | `kb.ontology_candidates` | proposals (LLM/import/discovery); spec §9.3 state machine `discovered → draft → in_review → approved → included_in_release` (+ rejected/deferred/superseded); `candidate_kind` = term/label/mapping/axiom/profile/profile_rule/module_change | `fingerprint` UNIQUE (dedup) | LLM/import/discovery output; promotion requires a human-approved change set | P2 |
| Modules | `kb.ontology_modules` | module identity + declared dependencies | one row per module | `ontology-seed`; `qudt-import`; API registration | P2 |
| Module releases | `kb.ontology_module_releases` | immutable payload snapshot + deterministic content checksum + pinned dependency releases | `UNIQUE(module_id, version)` | DB-native compiler `release` (validate → snapshot → checksum → pin deps → insert → tag `included_in_release` → supersede prior) | P2 |
| Active releases | `kb.ontology_active_releases` | activation pointer; at most one active release per module (partial unique index) | — | `activate` / `rollback` (audited; nothing deleted) | P2 |
| Profiles | `kb.ontology_profiles` | scoped, versioned conformance expectations ("for this class, in this jurisdiction, these metrics are required") | per-profile version | direct API `POST /kb/ontology/profiles`; drafts inactive until included in a release | P4 |
| Profile rules | `kb.ontology_profile_rules` | typed rule kinds (e.g. `required_assertion_pattern`) with a paired SHACL emitter (seam 6) | per-rule version | direct API `POST /kb/ontology/profile-rules` | P4 |
| Review scopes | `kb.ontology_review_scopes` | immutable frozen scope (pinned releases, closed dimensions, applicability facts) | immutable | review-scope freeze | P4 |
| Comparison scopes / runs / cells | `kb.ontology_comparison_scopes`, `kb.ontology_comparison_runs`, `kb.ontology_comparison_cells` (verified 2026-08-08: real table names are prefixed `ontology_`, not bare `kb.comparison_*`) | class-anchored comparison matrix (DR22): scope, run with assertion watermark, cells as lists with representative/remainder/verdict/rationale | immutable scopes; runs are **verified 2026-08-08 to be a persist/read-back log, not an invalidating cache** — no dedup-by-watermark, no invalidation logic found anywhere in the package | DR22 application service (not a doc processor) | P4 |
| Recommendation policies | `kb.recommendation_policies` — **verified 2026-08-08: does not exist, no migration and no code anywhere** | versioned verdict→advice policy, stored separately from verdicts (DR21 rule 1) | versioned | authoring | P4 (not built) |
| Document facets | `kb.doc_facets` (real, simple record-keyed routing facets) and `kb.doc_facet_values` (verified 2026-08-08: a second, separate table — migration `20260801000016` — that tier-3 `classify_document` actually writes to; tiers 1-2 have no wired producer yet, §3.5) | one row per `(record_id, facet_key)`; keys and permitted values are governed `document-authority` terms | per record; three tiers cheapest-first, though only tier 3 is wired (verified 2026-08-08) | facet producers (tier 1 deterministic; tier 2 from `extract_doc_metadata`; tier 3 `classify_document`) | P1 |
| Pipeline policies | `kb.pipelines`, `kb.pipeline_policies`, `kb.pipeline_bindings`, `kb.pipeline_rules` | named pipelines, versioned binding policy, per-processor gates (DR6) | versioned; compiled and activated by the same mechanism as ontology modules | policy authoring + compiler | P1 |
| Knowledge-store bindings | `kb.knowledge_store_bindings` — **verified 2026-08-08: does not exist**; the store default pipeline is instead a `default_pipeline` column directly on `kb.knowledge_store` | default pipeline, bound module releases, default review profiles per store (DR18) | — | store-binding CRUD | P1 (partially built — default pipeline only, not module releases or review profiles) |
| Keyword lexicon | `kb.keyword_concepts`, `kb.keyword_surfaces`, `kb.keyword_surface_keys`, `kb.keyword_occurrences` (verified 2026-08-08: replaced `kb.keyword_mentions`, dropped 2026-08-05), `kb.keyword_unresolved`, `kb.keyword_rewrite_rules`, plus 11 more `kb.keyword_*` tables added 2026-08-05..07 for source governance (17 total live) | ungoverned canonical *lexical* identity (DR15.2/DR16): occurrence → surface → lexform → concept | versioned normalizer (bump = re-index, never data loss) | curated seed terms + `never_merge` assertions; pipeline mention collection; reconciliation; `aligns_to_term` to governed terms | P3 — **built and wired 2026-08-04 through 2026-08-07** (verified 2026-08-08), well past "design-only"; see §8.3.6 |

### B.2 The seven 4a modules — ownership, processors, tables, and status

**Purpose.** DR1 (§3.2) defines seven 4a modules. This table gives each one's full ownership as
decided, the doc processor(s) that populate or consume it, the table(s) that actually store its
data, and its implementation status as of 2026-08-09 — deliberately separating a module's *governed
vocabulary* (terms released through `ontology-seed` / `qudt-import` into `kb.ontology_terms`) from
the *pipeline* that is supposed to depend on it, because for several modules those two are at very
different stages: a module can have a fully built extraction pipeline writing real data every day
while its own governing vocabulary has never been released.

| Module | Owns (DR1, §3.2) | Doc processor(s) | Table(s) | Status |
|---|---|---|---|---|
| `core` | Referent, information artifact, assertion, evidence, agent, role, valid/transaction time, polarity, confidence, semantic-role predicates. Installed content adds `instance_of`, `plays_role`, the DR20 hierarchy (`part_of` / `component_of` / `variant_of`), `about`, `has_evidence`, `asserted_by`, `has_polarity`, `has_confidence`. | `normalize_assertions` (candidate assertions), `associate_semantics` (accepted assertions, evidence, relations), `project_semantics` (derived projections) — the DR8 Phase D trio | `kb.ontology_terms`/`kb.ontology_term_labels` (module content); `kb.semantic_assertions` (assertion + valid/transaction time + polarity + confidence columns); `kb.assertion_evidence`; `kb.assertion_relations`; `kb.object_nodes` (`ontological_level`, `identity_scope`, `external_identifiers`, `primary_class_term_id`, plus unpopulated `merged_into` / `scope_key`) | **The only 4a module actually released and active** — 20 terms (the ADR's "19" predates the 2026-08-06 `core:aligns_to_term` addition), release 1.0.0, checksum `c983fa57d239`. Its Phase D runtime (the three processors above) is built and live-validated (P3, §8.3.6). `object_nodes.merged_into` / `scope_key` exist but are not yet read or written by the reconciler (DR15.1 gap, §15.2). |
| `quantity` | Quantity kinds, units, dimensions, conversion, value forms (scalar / interval / bound / tolerance / ratio / formula), comparators, QUDT mappings. | None directly — populated by the `qudt-import` CLI (an offline importer, not a pipeline doc processor); consumed by `associate_semantics` (unit resolution) and indirectly by `extract_metrics`'s structured unit/value fields | `kb.ontology_terms` (`term_kind` = quantity_kind / unit / dimension); `kb.ontology_mappings` (the only module with a direct exact-mapping authoring path, back to QUDT source IRIs) | Seed/import code exists and claims a 4151-term catalog, but **has never been run against the live database — zero rows**, and the 4151 figure is unverified anywhere in the repo (§15.2). Do not confuse with the separate, later "external terminology portfolio" QUDT 3.5.0 import (2026-08-06/07, §1 changelog) — that one succeeded live, but it populated the **keyword lexicon's** external-terminology tables, not this module's `kb.ontology_terms`. |
| `document-authority` | Document kind, issuer/authority, edition/version, jurisdiction, normative vs informative, effective interval, supersedes/amends/cites, the DR4 document-facet vocabulary (keys `doc_kind` / `domain` / `normative` / `jurisdiction_facet` / `language`; values `standard` / `specification` / `regulation` / `report`/ `manual` / `normative` / `informative`). | Tier 1 deterministic facet producers (`ComputeTier1Facets`); tier 2 `extract_doc_metadata`; tier 3 `classify_document` | `kb.ontology_terms` (22 terms, module content); `kb.doc_facets` (simple routing facets); `kb.doc_facet_values` (the general facet-observation store tier 3 actually writes to) | Seed code exists since 2026-07-31, **never run — zero live rows** for the governed vocabulary. As of 2026-08-09 all three facet tiers are wired and writing observations — the pipeline is producing facet values today with **no released module behind it** to validate facet keys/values against. |
| `deontic` | Modality (required / permitted / recommended / prohibited / declared), actor, action, condition, exception — the provision contract. | None write governed deontic content. `extract_provisions` extracts applicability/scope clauses into `kb.provisions`, a pre-existing, ungoverned table (Appendix A.2/C.8) | No `kb.ontology_modules` row exists for `deontic` | **Design-only.** Defined once in DR1's table and never referenced again anywhere in this ADR — no seed code, no authoring surface (§3.3.2 lists only `core` / `document-authority` / `measurement` for `ontology-seed`), absent from the original version of this appendix. |
| `measurement` | `metric_definition` vs metric assertion, observable property, feature of interest, procedure, condition, aggregation/window, metric assertion kinds (`lower_bound_requirement` / `upper_bound_requirement` / `interval_requirement` / `observed_value` / `target` / `reference`/`capability`), `has_quantity_kind` / `has_unit` / `measured_by`. | `extract_metrics` (built, the primary structured-value path); `extract_metric_definitions` (candidates only); `extract_test_methods` (candidates only) | `kb.ontology_terms` (17 terms, module content); `kb.metrics` (structured metric data — `value_min`/`value_max` / `condition` / `value_range_type` / `value_class` / `metric_value` / `metric_unit`, the live path); `kb.ontology_candidates` / `kb.semantic_decision_candidates` (definition/procedure candidates awaiting promotion) | Seed code exists since 2026-07-31, **never run — zero live rows**, same as `document-authority`. Unlike `document-authority`, the data path (`kb.metrics`) is fully built and is the primary route today, running without a released `measurement` (or `quantity`) module to validate against. |
| `occurrence` | Occurrence, participant, action, state, cause, outcome — the scene-block contract. | `generate_scene_blocks` (pre-ADR, unchanged, Appendix A.4) writes scene evidence; no processor writes governed occurrence vocabulary | `kb.scene_objects` (the `object_id` → `scene_block_id` rename never happened, §15.1, Appendix C.7); `kb.search_artifacts` (`scene_block` partition, 2,288 live rows per §8.3.2) | **Design-only**, same pattern as `deontic`. `core`'s installed vocabulary already absorbed a bare `occurrence` term — `kb.object_nodes.ontological_level` accepts `occurrence` as one of its four valid values (individual / type / collection / occurrence, §3.15.23, CQ-I02) — but the fuller scene-block contract (participant / action / state / cause / outcome) DR1 assigns to a separate module was never built. |
| `inventory` | Item type vs item instance, part-of, member-of, location, custodian, catalog/serial identity, quantity-on-hand. | `extract_inventory_items` (pre-ADR, unchanged, Appendix A.4) | `kb.search_artifacts` (`inventory_item` partition, 8,578 live rows per §8.3.2); no structured `kb.inventory_*` table exists | **Design-only**, same pattern. `normalize_assertions`'s spec (Appendix A.1) names "later inventory/entity/scene artifacts" as a future normalizer target, but that normalizer is not built either — only metric and provision normalizers exist (§8.3.6). |

> **2026-08-08/09 status (verified against `server/cmd/ontology-seed`, `server/cmd/qudt-import`, and
> the live `miner` database):** only **`core`** is actually released and active — 20 terms (the
> ADR's "19" predates the 2026-08-06 `core:aligns_to_term` addition), release 1.0.0, checksum
> `c983fa57d239`. **`document-authority`** (22 terms) and **`measurement`** (17 terms) have real
> seed code, present since 2026-07-31, that has **never been run** against this instance — zero
> rows in `kb.ontology_modules`/`kb.ontology_terms` for either. **`quantity`**'s claimed 4151-term
> QUDT import likewise has zero live rows, and the "4151" figure has no corroborating evidence
> anywhere in the repository (code, tests, or devdocs) — treat it as an illustrative estimate, not a
> verified count, until the import has actually been run and checked. **`deontic`, `occurrence`,
> and `inventory` are not seeded at all** — no `ontology-seed` case, no `kb.ontology_modules` row,
> no candidate content — because §3.3.2's direct-authoring surface only ever covered `core`,
> `document-authority`, `measurement` (via `ontology-seed`) and `quantity` (via `qudt-import`); DR1's
> other three modules were never given an authoring path in any later revision of this ADR. Their
> corresponding *pipeline* output already exists and is flowing today, just as ungoverned Layer-1
> evidence: `kb.provisions` (`extract_provisions`), `kb.scene_objects` / `kb.search_artifacts`
> `scene_block` (`generate_scene_blocks`), and `kb.search_artifacts` `inventory_item`
> (`extract_inventory_items`) all predate this ADR and are unchanged by it (Appendix A.4).

### B.3 Domain 4b modules — planned, none authored

`pump`, `pressure-vessel`, `tax-cn`, `medical-device`, … Each contains: domain classes and subclasses, domain
properties bound to 4a quantity kinds, domain axioms, **domain profiles and profile rules**, applicability rules,
competency questions, and conformance fixtures. A 4b module may **not** introduce new assertion kinds, predicates,
value forms, or qualifier dimensions (DR1 binding constraint); it is authored as content rows under a `module_id`,
released through the DB-native compiler, and installing it is **data, not code**.

The pilot module is **呼吸机 / 医疗器械** (OD1). It remains **un-authored** until a domain owner supplies a
traceable worked example and approved source values (P4 deferred data gate); the worked `pump` example (DR2 §6.1)
is illustrative, not installed.

### B.4 Generation and import sources

1. **`ontology-seed`** — `go run ./server/cmd/ontology-seed` authors the curated 4a modules (`core`,
   `document-authority`, `measurement`) directly as approved content rows (bypassing the candidate state machine);
   `--author-only` skips release.
2. **`qudt-import`** — `go run ./server/cmd/qudt-import` parses the published QUDT TTL
   (`src/main/rdf/vocab/{unit,quantitykinds,dimensionvectors}/`) as transient generator input, writes validated
   content (terms + labels + exact mappings) into the DB under the `quantity` module, after which the module is
   released normally (the DR13 "selective import" path).
3. **Candidate → promote** — the only way LLM/import/discovery content enters production content rows: it lands in
   `kb.ontology_candidates` and promotion requires a human-approved change set (`POST /kb/ontology/candidates/:id/promote`);
   `included_in_release` is owned by the module release path alone. This is the code-enforced "LLM cannot activate"
   guarantee.
4. **Direct API authoring** — `POST /kb/ontology/terms`, `/terms/:term_id/labels`, `/profiles`, `/profile-rules`
   write approved content directly. Axioms and general-purpose mappings have **no** direct route.
5. **Pipeline policy authoring** — named pipelines, binding policies, and processor rules are authored as data and
   compiled/activated by the same DB-native mechanism as ontology modules (DR6/DR17).
6. **Lexicon seeding** — curated seed terms and `never_merge` assertions seed the keyword lexicon (DR16).

**Not a source.** Pipeline extraction output never becomes ontology content. Extracted artifacts stay as Layer-1
evidence; at most they feed the candidate path via the spec §9.3 state machine with human approval (ADR §3.3.1).

## Appendix C. List of Database Tables

**Moved 2026-08-10** to `KnowledgeStore/doc-repo/user-manuals/database-tables.md`. A living table
inventory belongs in an operator-facing reference that gets updated as tables are added, not inside
an ADR whose job is to record a decision and its history — this appendix had already drifted (its
keyword-lexicon governance section, C.4, only gestured at 11 undocumented `kb.keyword_*` tables with a
footnote instead of enumerating them; the moved document fills that gap). See the linked document for
the current, maintained table inventory.
