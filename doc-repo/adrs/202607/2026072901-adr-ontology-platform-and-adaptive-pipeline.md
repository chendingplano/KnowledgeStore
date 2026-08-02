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

A binding may be as simple as "knowledge store `KS-Project-A` → pipeline `standards@2`" with no
predicate at all — which is exactly the case C5 could not express — or predicated on document
facets for finer control.

Every run writes an immutable **execution plan** into `kb.doc_process_runs.plan`: the policy
version, the selected pipeline and why, the facet snapshot, and per processor the decision, the
winning rule id, the reason, and the cost class. "Why did `extract_metrics` not run on record
4711?" becomes an API call rather than log archaeology, and a run remains reproducible after the
policy changes.

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

### 3.13 DR12 — The pilot is one vertical slice: metrics, one domain module, one review question

**Metrics is the pilot artifact family**, confirmed: it is simultaneously the hardest test of the
framework (it needs properties, quantity kinds, units, assertion kinds, conditions, and
comparability before it works at all) and the focus of the product plan, so framework verification
and product progress are the same work rather than competing for it. Provisions follow, because
profile rules are sourced from them.

Spec §16.4 defines the pump acceptance suite. This ADR adopts that shape but binds it to the live
corpus: the pilot *domain module* is chosen in P0 from documents SemOS has already ingested, by
three criteria — enough documents to measure, an authoritative standard available as the profile
source, and a domain owner able to approve terms and rules. "Pump" remains the worked example in
the prior documents; the actual pilot module remains open (OD1).

Everything outside the pilot slice stays candidate-only: summaries, projections, topics, scenes,
and entity relations generate `SemanticDecisionCandidate` rows and nothing accepted, until P6
measures per-method precision (spec §16.5.7).

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
  carries a SHACL emitter so the shapes can be published later. Spec §16.4.14 makes SQL-versus-SHACL
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
That step needs a real DB, NATS, and LLM credentials this session has no visibility into, and is
gated regardless on `extract_metrics` emitting structured values and `normalize_assertions`
existing (both P3, not yet built) — without those, "real" output would still be `SimulatedActual()`
by another name. Every piece that can be built and verified without live infrastructure now exists
and is tested.

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

### 3.24 DR23 — "Metric definition" and "profile" are different objects; the application's *Metric Profile* is the former

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

**P4 — target application (DR21–DR22)**

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

`kb.scene_objects.object_id` → `scene_block_id` rename (spec §11.4) lands in P1 with the
identifier-hygiene work.

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
| `DOC_FACET_CLASSIFIER_MODEL` | unset | model for tier-3 `classify_document`; unset disables tier 3 (tier 1–2 facets only) |
| `DOC_PIPELINE_ON_CONFLICT` | `block` | `block` fails the run and raises an alarm on an unresolved binding conflict or undetermined gate; `fallback` walks the DR7 escalation ladder and warns |
| `PG_HOST` / `PG_PORT` / `PG_USER` / `PG_DB_NAME` | local socket, `5432`, `cding`, `chenweb_test` | database the ontology compiler reads and writes; content lives in the DB, not a repository (DR2) |
| `COMPILER_ARGS` | — | arguments to `mise run ontology-compiler` (`validate`/`release`/`activate`/`rollback`) |
| `SEMANTIC_ASSOCIATION_ENABLED` | `false` | enable Phase D stages |
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
| Rule engine | new package `server/api/semrules` | predicate AST, operator registry, evaluator with trace, conflict/indeterminate semantics |
| Policy store | new `pipeline_policy_store.go` | pipeline/binding/rule load, activation, version pinning, conflict detection and alarm |
| Knowledge stores | `server/api/kbhandler/stores_handler.go`, ingestion handlers | `ks_id` and `requested_pipeline` on ingestion; store bindings CRUD |
| Canonicalization kernel | new package `server/api/semid` | normalizer profiles, candidate generation, scoring, adjudication, merge/split, decision log; family adapters |
| Keyword lexicon | new `server/api/semid/lexicon/` + a doc-processing mention collector | DR16 merged design as a kernel instantiation |
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
| `classify_document` | new | mandatory (gated) | facets/metadata → governed document facets | P1 | DR4 routing and profile applicability; identifies standard kind, issuer, jurisdiction, edition |
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
service), profile evaluation (L6), the certification-body registry (reference data, not
extraction), and the product image hotspot map (application data binding an image region to an
object node).

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

#### 8.3.5 P2 — Ontology core and the canonicalization kernel *(parallel with P1)*

> **Status: implemented and validated (2026-08-01).** All six P2 bullets below are built and
> live-validated (chunks 0, A–F), with the DB-native storage revision applied throughout. See the
> P2 implementation log and the ontology capsule. Exit criteria: spec §16.3 items 1–7 are covered
> by the consolidated `candidates/p2_exit_test.go`; the four core 4a modules install as data with
> no code change (the DR1 property); a failed validation leaves the previous active release
> untouched; and the `semid` merge/split fixtures show no transitive closure and no lost merged id
> (ADR kernel tests 18–21, 23).

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

*Exit:* spec §16.3 items 1–7 pass; a term added by committing module source and running the
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
> **Not built:** the keyword lexicon (design-only per the DR16 merged spec
> `2026080101-spec-keyword-canonicalization-merged.md`) and the DR6/DR7 halves of the backlog drain
> (admin review page; LLM auto-resolution).
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

*Exit:* spec §16.2 and §16.3 acceptance suites pass, including conflicting assertions remaining
separately queryable, corrupted projections detected and repaired, and evidence loss moving an
assertion to `unsupported` and back; the lexicon resolves the gold set above its promotion gate
with zero over-merges of `never_merge` pairs.

#### 8.3.7 P4 — Profiles, generic review, and comparison runtime *(generic runtime built 2026-08-01)*

**Built (L6/L7 runtime only):** generic versioned profiles/rules, governed lifecycle and release-visible reads,
immutable review/comparison scopes, pinned-scope review execution and auditable findings,
DR21/DR22 cached comparison runs/cells, paired `required_assertion_pattern` SHACL output, and
authenticated authoring/execution/read APIs. All P4 migrations were live-validated on
`chenweb_test` through `20260801000011`.

**Remaining P4 work:** ADR §8.2's `extract_metric_definitions`, `extract_product_structure`,
`extract_test_methods`, and the structured-output extension of `extract_provisions` remain to be
implemented. **Deferred data gate:** the ventilator benchmark/domain module is validation data only. It is not
part of the generic runtime and remains un-authored until a domain owner supplies a traceable
worked example and approved source values.

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

*Remaining pilot exit:* the spec §16.4 acceptance suite passes against the pilot module and fixture corpus —
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

#### 8.3.9 P6 — Remaining artifact families *(needs P3; independent of P5)*

Summaries, semantic projections, topics, and scene blocks per spec §15 Phase 5 and §16.5:
grounded links, inherited candidates that never gain confidence through repeated derivation,
occurrence identity, and a labeled evaluation corpus with per-method precision thresholds before
any automatic acceptance.

#### 8.3.10 P7 — Publication and interoperability *(needs P2–P4)*

Versioned RDF/OWL/SKOS/SHACL artifacts, persistent dereferenceable IRIs, round-trip and parity
fixtures in CI (including the SQL-versus-SHACL parity gate moved here from spec §16.4.14 per
DR13), external consistency checks, and — only if a competency question justifies it — a reasoner
or triple-store projection.

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

Beyond the inherited suites (spec §16.2–§16.5, research §13), this ADR adds:

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

## 15. References

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

## Appendix A. New Doc Processors

**Purpose.** This appendix enumerates every doc processor this ADR adds or changes — what it does, whether it
generates new persisted data (and which tables that data lands in), and whether it is LLM-driven. "New" means the
processor did not exist in the pre-ADR 13-processor roster; "changed" means an existing processor's output
contract is extended. Each processor declares a DR5 `ProcessorSpec` (class, cost, `OnUndetermined`); a `routed`
processor runs only when the selected pipeline policy and its per-processor gates resolve to run.

**"LLM-driven" values.** `expensive_llm` = per-chunk LLM extraction (normal Phase B cost); `cheap_llm` = one LLM
call per document (tier-3 classification); `none` = deterministic code, no model invocation. Where a processor's
adjudication is currently deterministic-only, that is noted.

### A.1 New processors

| Processor | Build (2026-08-01) | Class | LLM-driven | What it does | New persisted data → table | Phase | Why |
|---|---|---|---|---|---|---|---|
| `classify_document` | planned (P1 declaration; tier-3 invocation P5; not yet in the live roster) | mandatory (gated) | `cheap_llm`, tier 3 only — one call over the first N pages, only when tiers 1–2 leave a required facet undetermined and a rule needs it | Classifies a document into the governed facet vocabulary: `doc_kind`, `domain`, `normative_status`, `jurisdiction` | **Yes** — governed document facets, one row per `(record_id, facet_key)` → `kb.doc_facets` | P1 (tier 3: P5) | DR4 routing + profile applicability |
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
| Comparison scopes / runs / cells | `kb.comparison_scopes`, `kb.comparison_runs`, `kb.comparison_cells` | class-anchored comparison matrix (DR22): scope, run with assertion watermark, cells as lists with representative/remainder/verdict/rationale | immutable scopes; cached runs invalidated when watermark or releases move | DR22 application service (not a doc processor) | P4 |
| Recommendation policies | `kb.recommendation_policies` | versioned verdict→advice policy, stored separately from verdicts (DR21 rule 1) | versioned | authoring | P4 |
| Document facets | `kb.doc_facets` | one row per `(record_id, facet_key)`; keys and permitted values are governed `document-authority` terms | per record; three tiers cheapest-first | facet producers (tier 1 deterministic; tier 2 from `extract_doc_metadata`; tier 3 `classify_document`) | P1 |
| Pipeline policies | `kb.pipelines`, `kb.pipeline_policies`, `kb.pipeline_bindings`, `kb.pipeline_rules` | named pipelines, versioned binding policy, per-processor gates (DR6) | versioned; compiled and activated by the same mechanism as ontology modules | policy authoring + compiler | P1 |
| Knowledge-store bindings | `kb.knowledge_store_bindings` | default pipeline, bound module releases, default review profiles per store (DR18) | — | store-binding CRUD | P1 |
| Keyword lexicon | `kb.keyword_concepts`, `kb.keyword_surfaces`, `kb.keyword_surface_keys`, `kb.keyword_mentions`, `kb.keyword_unresolved`, `kb.keyword_rewrite_rules` | ungoverned canonical *lexical* identity (DR15.2/DR16): occurrence → surface → lexform → concept | versioned normalizer (bump = re-index, never data loss) | curated seed terms + `never_merge` assertions; pipeline mention collection; reconciliation; `aligns_to_term` to governed terms | P3 (design-only; `KEYWORD_RESOLVER_MODE=observe` first) |

### B.2 Core 4a modules — installed as data (P2)

| Module | Owns | Terms installed | Release / active | Source |
|---|---|---|---|---|
| `core` | referent, information artifact, assertion, evidence, agent, role, occurrence, value, part; predicates `instance_of`, `plays_role`, the DR20 hierarchy (`part_of`/`component_of`/`variant_of`), `about`, `has_evidence`, `asserted_by`, `has_polarity`, `has_confidence` | 19 | 1.0.0 (checksum c983fa57d239), active | `ontology-seed` |
| `document-authority` | document kind, issuer/authority, jurisdiction, edition/version, normative vs informative, effective interval, supersedes/amends/cites; **DR4 facet vocabulary** (facet keys `doc_kind`/`domain`/`normative`/`jurisdiction_facet`/`language`; permitted values `standard`/`specification`/`regulation`/`report`/`manual`/`normative`/`informative`) | 22 | 1.0.0 (d8691f5210c7), active | `ontology-seed` |
| `quantity` | QUDT catalog: quantity kinds, units, dimension vectors; conversion; value forms + comparators; exact mappings back to source IRIs | 4151 (`quantity:unit_*` / `qk_*` / `dim_*`) | 1.0.0 (47f2276c8c10), active | `qudt-import` (published QUDT TTL as transient generator input) |
| `measurement` | `metric_definition` (DR23), metric assertion vs definition, observable property, feature of interest, procedure, condition, aggregation window; metric **assertion kinds** `lower_bound_requirement`/`upper_bound_requirement`/`interval_requirement`/`observed_value`/`target`/`reference`/`capability`; `has_quantity_kind`/`has_unit`/`measured_by` | 17 | 1.0.0 (ec54375f8605), active; pins `core@1.0.0`, `quantity@1.0.0` | `ontology-seed` |

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

**Purpose.** This appendix enumerates every database table the SemOS ontology framework creates or
alters, grouped by the phase that introduces them. For each table it gives a description, the key
columns, the ADR decision or layer it belongs to, and its authoring or generation surface. Tables
that predate this ADR and are only referenced (not created or altered) are listed separately at the
end.

### C.1 New tables — P1 (pipeline plane)

| Table | Description | Key columns | ADR ref | Authoring / generation |
|---|---|---|---|---|
| `kb.doc_facets` | Governed document facets produced by the three-tier cheapest-first classifier (DR4). One row per `(record_id, facet_key)`; keys and permitted values are ontology terms in the `document-authority` module. | `record_id`, `facet_key`, `facet_value`, `value_kind`, `confidence`, `method`, `evidence`, `policy_version`, `run_id` | DR4, L1/L6 | Tier 1 deterministic producers; tier 2 from `extract_doc_metadata`; tier 3 `classify_document` |
| `kb.pipelines` | Named, versioned, declarative pipeline plans: an ordered processor set, optional per-processor parameters, and optional refinement gates (DR6 tier 1). | `pipeline_id`, `name`, `version`, `title`, `description`, `status`, `definition JSONB`, `source_ref`, `checksum`, `created_at` | DR6 | Policy authoring + DB-native compiler |
| `kb.pipeline_policies` | Versioned binding policies that decide which pipeline applies to a given scope (DR6 tier 2). | `policy_id`, `version`, `status`, `source_ref`, `checksum`, `activated_at`, `activated_by` | DR6 | Policy authoring + compiler activation |
| `kb.pipeline_bindings` | Pipeline-to-scope bindings within a policy. Each binding maps a scope (system, tenant, knowledge store, user, or document) to a specific pipeline version. | `binding_id`, `policy_id`, `priority`, `scope_kind`, `scope_key`, `predicate JSONB`, `pipeline_id`, `pipeline_version`, `reason_template`, `source`, `approved_by` | DR6, DR7 | Policy authoring |
| `kb.pipeline_rules` | Per-processor gate rules within a policy. Each rule targets a specific processor with an effect (`require`, `enable`, `skip`, `defer`) and a predicate. | `rule_id`, `policy_id`, `priority`, `target_processor`, `effect`, `predicate JSONB`, `required_facets`, `reason_template`, `source`, `source_module_release_id`, `approval_status`, `approved_by` | DR6, DR7 | Policy authoring; module-supplied rules |
| `kb.knowledge_store_bindings` | Default pipeline, bound module releases, and default review profiles per knowledge store (DR18). Makes the store both a routing key and a scope key. | store reference, default pipeline, bound releases, default profiles | DR18 | Store-binding CRUD |

### C.2 New tables — P2 (ontology terms, modules, and canonicalization kernel)

| Table | Description | Key columns | ADR ref | Authoring / generation |
|---|---|---|---|---|
| `kb.ontology_modules` | Module identity and declared dependencies. One row per module (e.g. `core`, `quantity`, `document-authority`, `measurement`, `pump`). | `module_id`, `owner`, `depends_on`, `created_at` | DR1, DR2 | `ontology-seed`; `qudt-import`; API registration |
| `kb.ontology_module_releases` | Immutable release snapshots. Each release carries the full payload snapshot of approved content, a deterministic content checksum, and pinned dependency releases. | `release_id`, `module_id`, `version`, `payload JSONB`, `content_checksum`, `pinned_deps JSONB`, `released_at`, `released_by` | DR2 | DB-native compiler `release` (validate → snapshot → checksum → pin deps → insert → tag `included_in_release` → supersede prior) |
| `kb.ontology_active_releases` | Activation pointer: at most one active release per module, enforced by a partial unique index. Rollback inserts a new row pointing at an older release; nothing is deleted. | `module_id`, `release_id`, `activated_at`, `activated_by` | DR2 | `activate` / `rollback` (audited) |
| `kb.ontology_terms` | Governed ontology terms. Each term has a `term_kind` (class, property, individual, concept, metric_definition, quantity_kind, unit, dimension) and is versioned; an accepted change inserts a new version row, never mutating a released row. | `term_id`, `module_id`, `term_kind`, `definition`, `version`, `status`, `source_candidate_id`, `included_in_release`, `released_in_release_id`, `create_by`, `modify_by` | DR2, L3 | `ontology-seed` (curated 4a); `qudt-import` (quantity); candidate → promote; API `POST /kb/ontology/terms` |
| `kb.ontology_term_labels` | Language labels for governed terms. `label_role` = prefLabel/altLabel/hiddenLabel; one prefLabel per term+language. | `term_id`, `version`, `lang`, `label_role`, `label_text` | DR2, L3 | `ontology-seed`; `qudt-import`; API; promotion |
| `kb.ontology_axioms` | Compiler-approved axiom kinds over governed term refs. Each axiom is versioned. The only authoring path is candidate → promote (`promoteAxiom`); there is no direct route. | `axiom_id`, `module_id`, `axiom_kind`, `term_refs`, `version`, `status`, `source_candidate_id` | DR2, L3 | **Only** candidate → promote |
| `kb.ontology_mappings` | Mappings to governed terms or external IRIs. `relation` = exact/close/broad/narrow/related; exact mappings require approval. | `mapping_id`, `module_id`, `source_term_id`, `target_iri`, `relation`, `version`, `status`, `evidence` | DR2, L3 | `qudt-import` (only direct path); general mappings via promotion |
| `kb.ontology_candidates` | Proposals from LLM, import, or discovery. Follows the spec §9.3 state machine: `discovered → draft → in_review → approved → included_in_release` (+ rejected/deferred/superseded). `candidate_kind` = term/label/mapping/axiom/profile/profile_rule/module_change. | `candidate_id`, `candidate_kind`, `fingerprint` (UNIQUE, dedup), `status`, `module_id`, `proposed_content JSONB`, `source`, `created_at` | DR2, L3 | LLM/import/discovery output; promotion requires human-approved change set |
| `kb.semid_decision_log` | Shared canonicalization decision log across all identity families (objects, keywords, categories, ontology terms). Append-only audit of every normalization, candidate-generation, scoring, and adjudication decision. | `input`, `output`, `verdict`, `model`, `prompt_version`, `actor`, `tokens`, `created_at` | DR15, DR17 | `semid` kernel (all families) |
| `kb.semid_never_merge` | Negative merge assertions: explicit declarations that two nodes must never be merged, across any identity family. | `family`, `node_a`, `node_b`, `reason`, `actor` | DR15, DR16 | Curated seed; human assertion |
| `kb.semid_snapshots` | Normalizer version snapshots. Records the state of each family's normalizer at a given version so that a normalizer bump triggers a re-index, never data loss. | `family`, `normalizer_version`, `counts`, `promoted_at` | DR15, DR16 | Kernel on normalizer version bump |

### C.3 New tables — P3 (assertions and semantic association)

| Table | Description | Key columns | ADR ref | Authoring / generation |
|---|---|---|---|---|
| `kb.semantic_assertions` | First-class qualified assertions with typed subject/object references (DR9) and normalized value columns. Carries modality, time, status, confidence, and evidence. The one authoritative owner store for accepted semantic claims. | `assertion_id`, `subject_ref_kind`, `subject_ref_id`, `subject_object_id`, `object_ref_kind`, `object_ref_id`, `object_object_id`, `predicate_term_id`, `value_form`, `numeric_value`, `lower_value`, `upper_value`, `comparator`, `unit_term_id`, `quantity_kind_term_id`, `raw_text`, `assertion_kind`, `status` | DR8, DR9, L5 | `associate_semantics` processor (Phase D stage 2) |
| `kb.assertion_evidence` | One-to-many evidence records supporting or contradicting an assertion. Each evidence row cites the source artifact, line span, chunk, and producing run. | `evidence_id`, `assertion_id`, `source_record_id`, `artifact_type`, `artifact_id`, `source_line_spans`, `evidence_kind`, `run_id` | DR8, L5 | `normalize_assertions` / `associate_semantics` |
| `kb.assertion_relations` | Conflict and supersession relations between assertions. Records when one assertion supersedes or conflicts with another, with the governing reason. | `relation_id`, `assertion_a_id`, `assertion_b_id`, `relation_kind` (conflict/supersedes), `reason`, `governing_release_id` | DR8, L5 | `associate_semantics` / `project_semantics` |
| `kb.semantic_decision_candidates` | Candidate semantic decisions awaiting adjudication. Used by `normalize_assertions` (candidate_kind=`assertion`), structural candidates, and metric↔procedure links. Follows deferral and retry semantics (spec §10.9). | `candidate_id`, `candidate_kind`, `status`, `dependency_fingerprint`, `proposed_content JSONB`, `created_at`, `attempts` | DR8, L5 | `normalize_assertions`, `extract_product_structure`, `extract_test_methods` |
| `kb.artifact_semantic_links` | Links from extracted artifacts to governed ontology terms: `about_term` (the artifact is about this term), `describes_occurrence` (the artifact describes this occurrence), `aligns_to_term` (a keyword concept aligns to this governed term). | `link_id`, `artifact_type`, `artifact_id`, `link_kind`, `term_id`, `confidence`, `evidence` | DR8, L5 | `project_semantics` |
| `kb.projection_state` | Tracks the authoritative reference, projection version, and stale flag for each derived projection (e.g. `kb.object_nodes.primary_class_term_id`). Enables mark-and-repair of stale projections. | `projection_kind`, `authoritative_ref`, `projection_version`, `stale`, `last_computed_at` | DR8, DR10, L5 | `project_semantics` |

### C.4 New tables — P3 (keyword lexicon, DR15/DR16 instantiation)

| Table | Description | Key columns | ADR ref | Authoring / generation |
|---|---|---|---|---|
| `kb.keyword_concepts` | Ungoverned canonical *lexical* identity (DR15.2). Fast, high-volume, auto-mergeable under guardrails. Connected to governed ontology terms by `aligns_to_term`. Merges are tombstones (`merged_into`), never deletes. | `concept_id`, `pref_label`, `gloss`, `scope`, `status`, `merged_into`, `gloss_source` | DR15, DR16, L3 | Curated seed; pipeline reconciliation; `aligns_to_term` to governed terms |
| `kb.keyword_surfaces` | Surface forms linked to keyword concepts. Each surface has a normalized key (`norm_key`) for O(1) lookup, a `label_role` (prefLabel/altLabel/hiddenLabel), an `alias_type` driving mechanical validation, and provenance. | `surface_id`, `concept_id`, `surface`, `norm_key`, `norm_version`, `label_role`, `alias_type`, `lang`, `scope`, `confidence`, `provenance`, `locked`, `evidence` | DR15, DR16, L3 | Pipeline mention collection; reconciliation |
| `kb.keyword_surface_keys` | Normalized lookup keys for surfaces. Multiple key kinds (exact, trigram, vector) per surface, versioned by `norm_version` so a normalizer bump triggers re-index, not data loss. | `surface_id`, `key_kind`, `key_value`, `norm_version` | DR15, DR16, L3 | Derived from `kb.keyword_surfaces` on normalization |
| `kb.keyword_mentions` | Observation records: each time a surface form is found in a document artifact, with the artifact reference, chunk, context, and knowledge store. | `mention_id`, `artifact_type`, `artifact_id`, `chunk_id`, `context`, `ks_id`, `surface_id`, `observed_at` | DR15, DR16, L3 | Pipeline mention collector |
| `kb.keyword_unresolved` | Unresolved surface forms that could not be linked to a concept. Tracks hit count, attempts, and priority for batch adjudication. Negative-cached: an unchanged item is never re-sent to a model. | `norm_key`, `scope`, `surfaces`, `contexts`, `hits`, `status`, `attempts`, `last_attempt`, `priority` | DR15, DR16, L3 | Reconciliation (items that fail to resolve) |
| `kb.keyword_rewrite_rules` | Pattern-based rewrite rules for surface normalization. Disabled by default (`enabled=false`); enabled per scope after validation. | `rule_id`, `pattern`, `replacement`, `scope`, `enabled` | DR16, L3 | Curated authoring |

### C.5 New tables — P4 (profiles and review)

| Table | Description | Key columns | ADR ref | Authoring / generation |
|---|---|---|---|---|
| `kb.ontology_profiles` | Scoped, versioned conformance expectations: "for this class, in this jurisdiction, these metrics are required." Drafts are inactive until included in a release. | `profile_id`, `module_id`, `version`, `title`, `applies_to_class_term_id`, `authority JSONB`, `closed_dimensions JSONB`, `status`, `included_in_release` | DR3, L6 | Direct API `POST /kb/ontology/profiles` |
| `kb.ontology_profile_rules` | Typed rule kinds (e.g. `required_assertion_pattern`) with a paired SHACL emitter (DR11 seam 6). Each rule belongs to a profile and is versioned. | `rule_id`, `profile_id`, `version`, `rule_kind`, `quantifier`, `property_term_id`, `quantity_kind_term_id`, `severity`, `predicate JSONB`, `status` | DR3, DR11, L6 | Direct API `POST /kb/ontology/profile-rules` |
| `kb.ontology_review_scopes` | Immutable frozen review scope: pinned module releases, closed dimensions, applicability facts, and the as-of date. Once written, never mutated. | `scope_id`, `profile_id`, `profile_version`, `pinned_releases JSONB`, `closed_dimensions JSONB`, `applicability_facts JSONB`, `as_of_date`, `frozen_at` | DR3, L7 | Review-scope freeze (L7 governance plane) |

### C.6 New tables — P4 (target application, DR21–DR22)

| Table | Description | Key columns | ADR ref | Authoring / generation |
|---|---|---|---|---|
| `kb.comparison_scopes` | Immutable comparison matrix scope: target class or object, metric definition set (the row universe), authority families (the columns), subject organization, as-of date, closed dimensions, precedence policy, and pinned module releases. | `scope_id`, `target_class_term_id`, `target_object_id`, `metric_definition_set JSONB`, `authority_families JSONB`, `subject_organization_id`, `as_of_date`, `closed_dimensions JSONB`, `precedence_policy JSONB`, `pinned_releases JSONB` | DR22, L7 | DR22 application service |
| `kb.comparison_runs` | Cached comparison run: one execution of a scope against the current assertion watermark. Invalidated when the watermark or pinned releases move. | `run_id`, `scope_id`, `assertion_watermark`, `status`, `cached_at` | DR22, L7 | DR22 application service |
| `kb.comparison_cells` | One cell in the comparison matrix. A cell is a **list** (not a value): matched assertion IDs with citation and line-span evidence, a display representative, a remainder count, and a verdict with direction and rationale. | `run_id`, `metric_definition_term_id`, `authority_family`, `assertion_ids JSONB`, `representative_assertion_id`, `remainder_count`, `verdict`, `direction`, `rationale` | DR21, DR22, L7 | DR22 application service |
| `kb.recommendation_policies` | Versioned policy mapping verdicts to advice (DR21 rule 1). Stored separately from verdicts: verdicts are computed comparison facts; recommendations are configured policy over verdicts. | `policy_id`, `version`, `rules JSONB`, `status`, `created_at` | DR21, L7 | Policy authoring |

### C.7 Altered existing tables

| Table | Alteration | Phase | ADR ref | Purpose |
|---|---|---|---|---|
| `kb.doc_process_runs` | ADD `plan JSONB`, `policy_version TEXT` | P1 | DR6, DR7 | Immutable execution plan: the policy version, selected pipeline and why, facet snapshot, and per-processor decision with winning rule id and reason |
| `kb.inputs` | ADD `ks_id BIGINT REFERENCES kb.knowledge_store(id)`, `requested_pipeline TEXT`, `facet_summary JSONB` (derived, trigger-maintained) | P1 | DR18, DR6 | Knowledge-store referential integrity, user-requested pipeline override, and derived facet summary for routing |
| `kb.object_nodes` | ADD `merged_into TEXT`, `scope_key TEXT` | P2 | DR15.1 | Tombstone merge tracking and explicit identity scope (DR15 kernel contracts adopted incrementally) |
| `kb.object_nodes` | ADD `ontological_level`, `identity_scope`, `external_identifiers JSONB`, `primary_class_term_id` (derived projection) | P2 | DR10, DR15 | Governed ontological level (individual/type/collection/occurrence), identity scope, external identifier bag, and derived class projection (never authored, rebuildable) |
| `kb.metrics` | ADD `value_min`, `value_max`, `condition`, `value_range_type`, `value_class`, `metric_value`, `metric_unit` | P3 | DR21 | Structured metric output: value form, comparator, normalized value, unit, and condition replace the legacy `threshold_or_target` free text |
| `kb.provisions` | Extended `public_info` with structured evidence fields | P3–P4 | DR21 | Applicability/scope clauses, authority, and effective interval for profile-rule sourcing |
| `kb.doc_review_findings` | ADD `review_scope_id`, `profile_rule_id`, `assertion_id` | P4 | DR3, L7 | Links each finding to its frozen review scope, the governing profile rule, and the relevant assertion |
| `kb.scene_objects` | Column rename: `object_id` → `scene_block_id` | P1 | spec §11.4 | Identifier hygiene: the column carries occurrence identifiers, not canonical object references |

### C.8 Pre-existing tables referenced but not created or altered by this ADR

These tables are part of the deployed SemOS system and are referenced by this ADR for context.
They are not created or structurally changed by the ontology framework.

| Table | Role in this ADR |
|---|---|
| `kb.artifact_objects` | Layer 1 evidence: per-record artifact-to-object mentions. The `semid` kernel adopts its contracts incrementally (DR15.1). |
| `kb.object_nodes` | Layer 2 referent identity: canonical referents with reconciliation, merge audit, and ambiguous-tie handling (ADR 2026070701). Gains extension columns (C.7). |
| `kb.search_artifacts` | Layer 1 evidence: LIST-partitioned search index over extracted artifacts. Not renamed or re-partitioned (DR24). |
| `kb.artifact_connections` | Layer 1 evidence: LIST-partitioned navigation graph. Not renamed or re-partitioned (DR24). |
| `kb.artifact_categories` | Existing retrieval/navigation categories. Retrofit to `semid` kernel planned P4+ (DR15). |
| `kb.knowledge_store` | Tenant, `ks_type`, `ks_name`, `ks_sources`, sync mode, status. Gains binding semantics via `kb.knowledge_store_bindings` (C.1). |
| `kb.inputs` | Ingestion records. Gains `ks_id`, `requested_pipeline`, `facet_summary` (C.7). |
| `kb.doc_process_runs` | Pipeline run records. Gains `plan`, `policy_version` (C.7). |
| `kb.doc_review_findings` | Review findings. Gains `review_scope_id`, `profile_rule_id`, `assertion_id` (C.7). |
| `kb.metrics` | Extracted metric artifacts. Gains structured value fields (C.7). |
| `kb.provisions` | Extracted provision artifacts. Gains structured evidence fields (C.7). |
| `kb.scene_objects` | Scene-block occurrences. Column renamed (C.7). |
| `kb.category_alias_conflicts` | Existing category alias conflict records. Referenced in C4 analysis (§2.4). |
| `alarms_errors` | Existing alarm/error records. DR7 writes pipeline-conflict alarms here. |
| `kb.scheduled_jobs` | Existing scheduled-job infrastructure. DR8 reuses it for periodic deferred-candidate drains. |
| `kb.cdm_anchors` | Existing CDM anchor map (page + x/y/w/h per line-file unit). DR25 grounding locator dispatches to it. |
