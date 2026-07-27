# ADR 2026072901 — SemOS Semantic Platform: Domain Ontology Modules and a Policy-Driven Document Pipeline

**Date:** 2026-07-29 \
**Status:** Proposed (draft for review) \
**Component:** SemOS Knowledge Base, ontology, doc-processor pipeline, document review \
**Authors:** Chen Ding \
**Tags:** SemOS, ontology, domain modules, doc-processor, pipeline routing, profiles, assertions, phased plan

## Change Logs

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

## Context

### C1. Where SemOS actually is

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

### C2. What the prior three documents settled

Research `2026072302` established the vocabulary and the layered target; spec `2026072702`
turned it into contracts (authoritative ownership, lifecycles, state machines, review decision
procedure, acceptance criteria); ADR `2026072701` ratified the layer boundaries
(DR1–DR7: referents stay in `kb.object_nodes`, meaning lives in governed terms, "what should be"
lives in versioned profiles, artifact→ontology linkage is mediated by qualified assertions,
LLMs propose but do not activate, each accepted relationship has exactly one owner store).

**This ADR does not reopen any of that.** It treats ADR 2026072701 DR1–DR7 and spec
2026072702 §8–§12 as the baseline contract.

### C3. What they left open — the three problems this ADR closes

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

### C4. Canonical identity is one recurring problem solved four separate times

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

### C5. Knowledge stores exist as a registry but are not wired to anything

`kb.knowledge_store` (tenant, `ks_type`, `ks_name`, `ks_sources`, sync mode, status) is created,
has CRUD handlers, and has a default-store resolver. But `kb.inputs` carries **no** knowledge-store
reference, and nothing in the pipeline, the ontology design, or review scoping consults it.
"Run pipeline A on knowledge store K1" is not expressible today, and neither is
"in KS-Medical, *ML* means millilitre." DR18 wires it as both a routing key and a scope key.

### C6. The connecting insight

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

## Decision

> Numbering note: DR14 and DR19 are retired numbers. The non-goals decision was renumbered twice
> across revisions and is now DR24; no decision was deleted.

### DR0 — Revised architecture: seven knowledge layers × three planes

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

### DR1 — Layer 4 splits into two tiers: core semantic modules (4a) and domain modules (4b)

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

### DR2 — A domain module is a Git-authored source package compiled into an immutable database release

Spec §9.7 requires module manifests, checksums, and immutable releases but not where the content
is authored. Decision: **author in Git, compile into Postgres.**

```text
<ontology-repo>/                       # a dedicated repository — see DR17
  modules/
    core/1.0.0/          module.toml terms.toml axioms.toml mappings.toml
    quantity/1.0.0/      module.toml terms.toml mappings.toml units.toml
    document-authority/1.0.0/
    measurement/1.0.0/
    pump/0.1.0/          module.toml terms.toml axioms.toml profiles.toml
                         applicability.toml competency.toml fixtures/*.yaml
```

The compiler (`server/cmd/ontology-compiler`, plus a `mise` task) performs the spec §9.8
validation set, computes a deterministic content checksum, and writes one immutable
`kb.ontology_module_releases` row plus expanded term/axiom/mapping/profile/rule rows tagged with
that release. **Activation** is a separate, audited act: an insert into
`kb.ontology_active_releases` (one active release per module per environment). Rollback inserts a
new activation row pointing at an older release; nothing is deleted.

Rationale:

* it reuses the review discipline the team already has (jj/Git history, diffs, per-change review)
  instead of blocking Phase 4 on an authoring GUI;
* it makes ADR 2026072701 DR6 ("an LLM may not activate ontology content") *structural* rather
  than a status column — LLM output lands in `kb.ontology_candidates`, and promotion requires a
  human writing module source and committing it;
* releases are reproducible from a commit hash plus a checksum;
* an authoring UI can be added later and write back to the same source, or export approved
  candidates into it; the DB contract does not change.

### DR3 — Applicability is one mechanism with two consumers

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

**Guard against silent coupling:** a domain module may ship `applicability.toml` routing
proposals, but installing the module never changes the pipeline by itself. Routing rules become
effective only when included in an activated **pipeline policy** version (DR6). Ontology
activation and pipeline activation are separate approvals with separate blast radii.

### DR4 — Document facets: a governed, cheap-first classification of documents

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

### DR5 — The pipeline becomes a declarative stage DAG with gates; A/B/C is the degenerate case

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

### DR6 — Two-tier routing: named pipelines selected by a versioned binding policy, then per-processor gates

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

### DR7 — Selection precedence; conflicts and undetermined decisions block, loudly

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

### DR8 — Semantic association is Phase D of the pipeline, not a separate service

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

### DR9 — Physical representation of assertion references (closes spec §17 open decision 1)

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

### DR10 — Object classification uses the general assertion model plus a derived convenience column (closes spec §17 open decision 2)

Classification is an accepted assertion with predicate `core:instance_of`; roles use
`core:plays_role`. `kb.object_nodes.primary_class_term_id` is added as a **derived projection**
maintained by `project_semantics` — read-optimized, never authored, rebuildable, and explicitly
not the system of record. This keeps multiple simultaneous classifications, their evidence, and
their conflicts expressible (research §5.2) while keeping the common lookup cheap.

### DR11 — Nine extension seams must exist before any domain content is authored

This is the ADR's answer to "embed the mechanisms so they can be developed incrementally,
gradually, and independently." Each seam is a Go registry interface plus, where applicable, a
database-backed registry, and each has exactly one rule: **adding an instance must not require
editing the mechanism.**

| # | Seam | Adding an instance means | Enables |
|---|---|---|---|
| 1 | `ProcessorRegistry` (DR5 declarations) | register a processor with a spec | new extraction stages |
| 2 | `FacetProducerRegistry` | register a producer + governed facet terms | new routing/profile signals |
| 3 | `PredicateOperatorRegistry` | register an operator | richer applicability rules |
| 4 | Module compiler + loader (DR2) | commit module source | new ontology and domain content |
| 5 | `AssertionNormalizerRegistry` | register a per-artifact-family normalizer | new artifact families reaching L5 |
| 6 | `ProfileRuleKindRegistry` (evaluator + SHACL emitter as a pair) | register a rule kind | new conformance semantics |
| 7 | `ProjectionBuilderRegistry` | register a builder + repair function | new derived surfaces |
| 8 | `ReviewerToolRegistry` | register a tool (research §7.4) | ontology-aware reviewers |
| 9 | `IdentityFamilyRegistry` (DR15 kernel adapters) | register surfaces, nodes, normalizer profile, scoring, scope | new canonical identity families |

Seams 1–4 and 9 ship in P1–P2 and are what make the rest independently developable. A phase that
adds content through a seam is a data or registration change and can proceed in parallel with
other phases.

### DR12 — The pilot is one vertical slice: metrics, one domain module, one review question

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

### DR13 — Adopt the semantic-web standards at four distinct levels, not as a package deal

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

### DR15 — One canonicalization kernel, instantiated per identity family

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

### DR16 — The two keyword specs are merged, taking the identity layering from one and the storage from the other

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

### DR17 — Ontology and policy data live in their own repository, versioned and pinned like a dependency

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

### DR18 — Knowledge stores are both a routing key and a scope key

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

### DR20 — Product-hood and part-hood are roles, not classes; the part hierarchy is first-class

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

### DR21 — Requirement strictness is a computed partial order; verdicts are directional and distinct from recommendations

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

### DR22 — The comparison matrix is a class-anchored application service, not a doc processor

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

### DR23 — "Metric definition" and "profile" are different objects; the application's *Metric Profile* is the former

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

### DR25 — Grounding is a substrate-agnostic locator over portable line spans

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

### DR24 — Explicit non-goals of this ADR

* No authoring GUI for ontology, lexicon, or pipeline content (the data repository is the
  P2–P4 authoring surface).
* No reasoner, no triple store, no SPARQL endpoint (DR13).
* No renaming or re-partitioning of `kb.search_artifacts` / `kb.artifact_connections`.
* No change to the JetStream contract or the Auto/Dev mode payloads.
* No rewrite of the live object-node or category resolvers (DR15.1).
* No per-run TOML for review configuration.
* No hard-deletion/retention policy for `unsupported` assertions (spec §10.12 keeps indefinite
  audited retention until a follow-up ADR).

## Alternative Decisions

### AD1 — Keep Layer 4 as one undifferentiated tier

Rejected. Without the 4a/4b split, either every domain module may define its own assertion kinds
(processors and normalizers fragment per domain, and cross-domain comparison dies), or no module
may define anything (domains cannot be added without platform work). The split is what makes
"install a domain module without a code change" a testable property.

### AD2 — Author ontology content directly in the database through an admin UI first

Rejected for the first releases. It front-loads UI work before the model is proven, and it makes
approval a mutable database state rather than a reviewable artifact. Git-first gives review,
diff, history, and reproducibility on day one. A UI later writes to the same source.

### AD3 — Let an LLM decide per document which processors to run

Rejected as the primary mechanism, and this is the user-raised question answered directly.
A per-document judgment call is unreviewable, unstable across model versions, produces no
explanation a policy owner can audit, and costs an LLM call to save an LLM call. DR4 keeps the LLM
where it is good (classifying a document into a governed vocabulary) and DR6 puts the decision in
reviewed, versioned rules. The LLM classification is cached as a fact, so the cost is paid once
per document, not once per processor per document.

### AD4 — Add per-processor `if` conditions to `config.toml`

Rejected. It is the cheapest possible version of DR6 and would work briefly, but it has no
versioning, no approval, no per-run freeze, no explanation, no shared evaluator with profile
selection, and no path to domain-module-supplied rules. The rule *content* may start small; the
*mechanism* must not.

### AD5 — Build the ontology first, add pipeline routing later

Rejected as sequencing. P1 (pipeline plane) has no dependency on the ontology and delivers
immediate, measurable value: cost reduction, an execution plan, and the facet vocabulary that
Layer 6 later reuses. Making it wait for L3–L5 delays every benefit behind the longest pole.

### AD6 — Build the keyword module as its own standalone, SQLite-backed service

Rejected (spec `2026072703` §3.3 storage note). SemOS has multiple writing services, one backup
and migration story, and `pg_trgm` + `pgvector` already installed, which lets lexical and semantic
blocking run in one hybrid query. More importantly, a standalone service would have to reimplement
candidate generation, adjudication, merge safety, and audit — the exact duplication DR15 exists to
stop. The short-acronym trigram weakness that motivated the SQLite/FTS5 recommendation is real and
is handled by routing short keys to the exact-key path, never to trigrams.

### AD7 — One concept registry: make keyword concepts *be* ontology terms

Rejected. It is attractive — one vocabulary, no alignment layer — but it forces every observed
surface form through governance. Keyword concepts arrive by the hundred thousand, must resolve
in microseconds during ingestion, and are frequently junk; ontology terms are reviewed, owned,
defined, and released. Fusing them either paralyzes ingestion behind curation or destroys
governance. DR15.2 keeps both and connects them with an explicit alignment assertion, which is the
same shape already used for object → class.

### AD8 — Keep ontology content in the ChenWeb repository (or in KnowledgeStore)

Rejected (DR17). The code repository couples ontology change to code release and gives curators
too much access; `KnowledgeStore` is human prose with different validation, different consumers,
and no compiler. A pinned data repository gives independent cadence, scoped access, its own CI, and
reproducibility from a commit SHA.

### AD9 — On a routing conflict, pick a winner and continue

Rejected for now (DR7). A silent winner hides a policy defect from the policy designers, and it
produces artifacts under an ambiguous plan — which then propagate into objects, assertions, and
findings that nobody knows to distrust. Blocking is loud, cheap to diagnose, and safe. The
escalation ladder is implemented at the same time, so maturing to `fallback` is a configuration
change rather than a redesign.

### AD10 — Treat association as a separate microservice

Rejected for now. Phase D as pipeline stages inherits status reporting, stop handling, tracing,
concurrency limits, and log/telemetry contracts that already exist and are hard to reproduce.
Extraction to a service remains possible later because the stages are declared, idempotent, and
independently re-runnable.

## Database Migrations

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

## Data Formats

### Module source package

```toml
# modules/pump/0.1.0/module.toml
id = "pump"
version = "0.1.0"
title = "Centrifugal and positive-displacement pumps"
owner = "domain:mechanical"
depends_on = ["core@1.0.0", "quantity@1.0.0", "measurement@1.0.0",
              "document-authority@1.0.0"]

# modules/pump/0.1.0/terms.toml
[[term]]
id         = "pump:centrifugal_pump"
kind       = "class"
parent     = "pump:pump"
definition = "A rotodynamic pump that moves fluid by a rotating impeller."
labels     = { en = "centrifugal pump", zh_cn = "离心泵" }
mappings   = [{ iri = "http://…", relation = "close" }]

# modules/pump/0.1.0/profiles.toml
[[profile]]
id = "pump:datasheet_completeness"
version = "1"
authority = { document = "GB/T …", edition = "2019", jurisdiction = "CN" }
applies_to = "pump:centrifugal_pump"
closed_dimensions = ["measurement:rated_quantities"]

  [[profile.rule]]
  id         = "pump:requires_rated_head"
  kind       = "required_assertion_pattern"
  quantifier = "exists_conforming"
  property   = "pump:rated_head"
  quantity_kind = "quantity:Length"
  severity   = "error"
```

### Applicability predicate (shared by DR3 consumers)

```json
{ "all": [
    { "facet": "doc_kind",  "in": ["standard", "specification"] },
    { "facet": "numeric_unit_density", "gte": 0.02 },
    { "any": [ { "facet": "domain", "eq": "mechanical" },
               { "object_class": { "instance_of": "pump:pump" } } ] }
] }
```

### Named pipeline and knowledge-store binding

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

### Execution plan (frozen in `kb.doc_process_runs.plan`)

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

## Environment Variables

| Variable | Default | Meaning |
|---|---|---|
| `DOC_PIPELINE_POLICY` | unset | active pipeline policy version; unset = legacy `required_processors` behavior (DR7) |
| `DOC_PIPELINE_PLAN_ONLY` | `false` | compute and persist the plan, then run the legacy set — shadow mode for validating rules before enforcement |
| `DOC_FACET_CLASSIFIER_MODEL` | unset | model for tier-3 `classify_document`; unset disables tier 3 (tier 1–2 facets only) |
| `DOC_PIPELINE_ON_CONFLICT` | `block` | `block` fails the run and raises an alarm on an unresolved binding conflict or undetermined gate; `fallback` walks the DR7 escalation ladder and warns |
| `ONTOLOGY_REPO_REF` | unset | pinned commit/tag of the ontology data repository (DR17) |
| `ONTOLOGY_MODULE_ROOT` | `./ontology/modules` | module source root for the compiler, within the checked-out data repository |
| `SEMANTIC_ASSOCIATION_ENABLED` | `false` | enable Phase D stages |
| `KEYWORD_RESOLVER_MODE` | `off` | `off` \| `observe` (record mentions and unresolved, resolve nothing) \| `on` |
| `KEYWORD_NORMALIZER_VERSION` | `1` | bumping triggers a re-index, never data loss (DR16) |

Every toggle must preserve the boundaries in ADR 2026072701; none may grant an LLM activation
authority.

## Implementation

### Code Changes

| Area | Location | Work |
|---|---|---|
| Stage DAG + planner | `ChenWeb/server/api/doc-processing/control.go`, new `plan.go`, `spec.go` | `ProcessorSpec`, DAG build, wave execution, gate application, plan persistence; keep `runProcessorsSequential` as the fallback |
| Facets | new `facets.go`, `facet_producers.go`; extend `doc-structure-analyzer.go`, `extract-doc-metadata.go` | tier-1/2 producers, `kb.doc_facets` store, `classify_document` processor |
| Rule engine | new package `server/api/semrules` | predicate AST, operator registry, evaluator with trace, conflict/indeterminate semantics |
| Policy store | new `pipeline_policy_store.go` | pipeline/binding/rule load, activation, version pinning, conflict detection and alarm |
| Knowledge stores | `server/api/kbhandler/stores_handler.go`, ingestion handlers | `ks_id` and `requested_pipeline` on ingestion; store bindings CRUD |
| Canonicalization kernel | new package `server/api/semid` | normalizer profiles, candidate generation, scoring, adjudication, merge/split, decision log; family adapters |
| Keyword lexicon | new `server/api/semid/lexicon/` + a doc-processing mention collector | DR16 merged design as a kernel instantiation |
| Module compiler | new `server/cmd/ontology-compiler`, `server/api/ontology/` | parse, validate, checksum, release, activate, rollback — for modules *and* pipeline policies |
| Ontology stores | `server/api/ontology/` | terms, labels, axioms, mappings, candidates, releases |
| Assertions | `server/api/ontology/assertions/` | assertion + evidence stores, normalizer registry, per-family normalizers |
| Association | new doc-processing stages `normalize_assertions.go`, `associate_semantics.go`, `project_semantics.go` | spec §10 pipeline |
| Profiles & review | `server/api/ontology/profiles/`, `server/api/doc-reviews/` | rule kinds, evaluator, review scope freeze, finding decision procedure (spec §12.3), reviewer tools |
| Comparison service | new `server/api/ontology/comparison/` | strictness comparator (DR21), cell assembly with precedence and equivalence grouping, comparison-run cache and invalidation (DR22) |
| Frontend | `web/src/lib/components/home3/doc-processor-dashboard-view.svelte`, new ontology admin pages, product/part comparison pages | plan display ("why did/didn't X run"), module/release browser, candidate review queues, the part navigator and comparison matrix |

### New and Changed Doc Processors

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

Explicitly **not** doc processors: the comparison matrix and verdict computation (DR22, an L7
service), profile evaluation (L6), the certification-body registry (reference data, not
extraction), and the product image hotspot map (application data binding an image region to an
object node).

### Phased Implementation Plan

Phases are ordered by dependency, not by importance. **P1 and P2 are independent and may run in
parallel.** Each phase ends with an exit criterion that is a test, not a judgment.

#### P0 — Semantic audit, competency questions, corpus baseline *(no code)*

* Verify spec §13.5 current-state claims against the deployed database and current code:
  artifact-object cardinality, `kb.search_artifacts` partitions, `kb.artifact_connections`
  uniqueness/replacement, scene identifier semantics, cascade/reprocessing behavior.
* Freeze the competency-question suite (research §11.1) with expected answers.
* Merge the two keyword specs into one superseding spec per DR16, and stand up the ontology data
  repository (DR17) with its CI skeleton.
* Inventory the knowledge stores actually in use and the pipelines each one needs (DR18).
* **Build the synthetic gold corpus and extend the existing benchmark** (ADR 2026071301) rather
  than waiting for a real-data example. Author the gold ontology for one part class first, then
  generate documents *from* it as CDM documents (DR25), so extraction gold, normalization gold,
  verdict gold, and grounding gold are all true by construction. This is P0's primary deliverable;
  the real corpus, when it arrives, calibrates difficulty but never gates.
  **Drafted:** `ChenWeb/benchmark/doc-processors/gold/display-module-v1/gold.toml` — 显示屏模块,
  9 metric definitions, 9 synthetic authority documents across 5 families, 40 clauses, 36
  hand-derived expected verdicts covering all 11 DR21 verdict kinds, each with a stated rationale.
  Not yet wired to the generator, the corpus-level case kind, or the DR21 comparator — see that
  directory's README for the remaining implementation gap. Authoring it surfaced a finding: the
  proposed application's mock shows `identical` ("一致") for several quantitative-enterprise-vs-
  qualitative-authority cells (触控响应时间, 有效视角); under DR21 that pairing is always
  `qualitative_only`, never `identical` — the mock should not be treated as gold for those cells.
* Build the DR21 strictness comparator standalone — it is a pure function over normalized
  constraints, needs no pipeline or database, and the benchmark is its first caller.
* Assemble the fixture corpus: ambiguous objects, multilingual names, unit conversion,
  superseded documents, conflicting requirements.
* Baseline measurement per document kind: processor cost, artifact yield, artifact usefulness —
  the numbers P1 and P5 are judged against.
* Choose the pilot domain module and its authoritative source (OD1).

*Exit:* domain and application owners agree on expected answers for the pilot questions; any spec
mismatch is corrected in writing before migrations.

#### P1 — Pipeline plane: declarations, facets, rules, plans *(no ontology dependency)*

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

#### P2 — Ontology core and the canonicalization kernel *(parallel with P1)*

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

#### P3 — Assertions, evidence, Phase D association, and the keyword lexicon *(needs P2)*

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

*Exit:* spec §16.2 and §16.3 acceptance suites pass, including conflicting assertions remaining
separately queryable, corrupted projections detected and repaired, and evidence loss moving an
assertion to `unsupported` and back; the lexicon resolves the gold set above its promotion gate
with zero over-merges of `never_merge` pairs.

#### P4 — Profiles, the first domain module, and ontology-aware metric review *(needs P3)*

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

*Exit:* the spec §16.4 acceptance suite passes against the pilot module and fixture corpus —
including `missing` only under a declared closed dimension, `indeterminate` on unresolved rule
conflict, and SQL/Go versus SHACL parity on identical fixtures.

#### P5 — Rule-driven routing enforced *(needs P1 + P4)*

* Tier-3 `classify_document`, gated on required-but-undetermined facets.
* Domain-module-supplied applicability rules promoted into a pipeline policy version.
* Measure against the P0 baseline using the existing benchmark tables (`kb.benchmark_*`):
  LLM cost per document, artifact yield, review recall/precision with routing on versus off.
* Enforce only where measurement shows no recall loss; leave the rest in shadow mode.

*Exit:* a documented, per-document-kind reduction in processor invocations with no measured loss
of review recall on the benchmark corpus; every skip explainable from its plan.

#### P6 — Remaining artifact families *(needs P3; independent of P5)*

Summaries, semantic projections, topics, and scene blocks per spec §15 Phase 5 and §16.5:
grounded links, inherited candidates that never gain confidence through repeated derivation,
occurrence identity, and a labeled evaluation corpus with per-method precision thresholds before
any automatic acceptance.

#### P7 — Publication and interoperability *(needs P2–P4)*

Versioned RDF/OWL/SKOS/SHACL artifacts, persistent dereferenceable IRIs, round-trip and parity
fixtures in CI (including the SQL-versus-SHACL parity gate moved here from spec §16.4.14 per
DR13), external consistency checks, and — only if a competency question justifies it — a reasoner
or triple-store projection.

#### Mapping to the prior phase plans

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

## Operational Behaviors

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

## Consequences

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
* Git-authored ontology requires curator discipline and does not scale to hundreds of contributors.
  Accepted for now; a UI is additive.
* Layer 4a becomes a bottleneck if domains frequently need new assertion kinds. Accepted
  deliberately — that bottleneck is the signal that the core model is wrong, and it should be
  visible.
* Blocking on routing conflicts stops ingestion when a policy is wrong. Mitigations: conflicts are
  detected at policy compile time in CI, not only at run time; the alarm names the offending ids;
  and `DOC_PIPELINE_ON_CONFLICT=fallback` is available without a redesign.
* A second repository is one more thing to pin, check out, and keep in sync; a stale
  `ONTOLOGY_REPO_REF` is a new failure mode. Mitigation: the active release records the source
  commit SHA and the content checksum, and startup logs both.
* Over-merging in the kernel is the asymmetric risk across *all four* families now, not just
  keywords. Mitigations are inherited from DR16: tombstones, `never_merge`, locked human
  assertions, no transitive closure, and per-family promotion gates on a gold set.

## Tests

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

## Documentation Impact

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
  spec exists, both carry a status note pointing here.
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

**Documents updated now.** This ADR only. The affected documents are updated per phase, with each
phase's documentation landing in the same change as its code.

**Documents now stale.** `+CAPSULE.md` §7.1–§7.3 becomes stale the moment P1 lands and must be
updated in that change, not after. Research §5.4 and spec §7's differing Layer-4 descriptions are
superseded by DR1; both should carry a pointer to this ADR.

**Intentionally left undocumented.** Physical column-level DDL (deferred to each phase's
migration), governance role-to-person assignment and authorization controls, the IRI hostname
policy, and the precedence-policy vocabulary for multi-jurisdiction conflicts (spec §17 items 3–5
remain open).

## Open Decisions

| # | Decision | Recommendation |
|---|---|---|
| ~~OD1~~ | ~~Which domain module is the pilot~~ | **Resolved 2026-07-29: 呼吸机 / 医疗器械**, driven by the target application. Corpus collection is under way. Open sub-item: the authoritative standard editions that source the profile come from the real-data worked example, not from the application mock — the mock's clause citations and limit values are placeholders |
| OD2 | Whether facet vocabulary lives in `document-authority` or its own 4a module | Start in `document-authority`; split if it grows past ~40 terms |
| ~~OD3~~ | ~~Where pipeline policies are authored~~ | **Resolved by DR17:** data repository, same compiler and activation as ontology modules |
| OD4 | Whether Phase D runs inline or asynchronously by default | Inline for the pilot corpus; move to `kb.scheduled_jobs` when association latency exceeds pipeline latency |
| OD5 | Multi-jurisdiction precedence vocabulary | Deferred (spec §17.4); unresolved conflicts stay `indeterminate` |
| OD6 | Hard-deletion and retention for `unsupported` assertions and rejected candidates | Deferred (spec §17.10); indefinite audited retention until decided |
| OD7 | Ontology data repository name, hosting, and access model | `semos-ontology`, same host as the code repositories, write access for curators; confirm in P0 |
| OD8 | Whether a document may belong to several knowledge stores | **Resolved in principle, deferred to P6.** Yes, eventually. The governing constraint: a document is processed **once** — artifacts are keyed by `record_id`, and store membership is a *view* (a join), never a copy — while a store must expose every artifact of every document it contains. The open part is scope: identity and lexicon resolution are scope-keyed by store (DR18), so a shared document resolves under its primary store for materialized identity, with read-time re-resolution for secondary stores. Ship `ks_id` as a single FK now; add `kb.input_store_membership` in P6 |
| OD9 | Scope granularity for the lexicon: knowledge store only, or store + domain + document | Store + document-local overrides in P3 (document-local acronym definitions are strong evidence); add domain if measurement shows collisions |
| OD10 | Whether category canonicalization retrofits onto the kernel in P4 or waits | P4, driven by the size of the `kb.category_alias_conflicts` backlog measured in P0 |

## References

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
