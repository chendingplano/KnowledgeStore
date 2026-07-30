# Spec 2026073004 — SemOS P0 Ontology Completion Slice

**Status:** Implemented — P0 documentation baseline recorded
**Date:** 2026-07-30
**Scope:** Documentation and verified current-state contracts only; no application code,
database migration, database mutation, or ontology runtime implementation.

## 1. Goal

Advance the ontology work without skipping unresolved Phase P0 foundations. This slice records
the deployed-system audit, freezes the pilot competency-question contract, inventories current
knowledge-store routing needs, and corrects stale status language in the consolidated
architecture ADR.

The consolidated source of truth remains ADR
`2026072901-adr-ontology-platform-and-adaptive-pipeline`. This specification defines the bounded
work required to make that ADR accurately describe the verified P0 baseline.
Implementation result: ADR `2026072901-adr-ontology-platform-and-adaptive-pipeline` now carries
the verified P0 baseline, and handoff `2026073002-handoff-semos-ontology-status` now records the
completed continuation slice and remaining P0 blockers.

## 2. Deliverables

### 2.1 Deployed-system verification

Record the read-only verification performed against the deployed `miner` PostgreSQL database and
current ChenWeb code:

- `kb.artifact_objects` cardinality, constraints, reconciliation links, and replacement scope;
- active and empty `kb.search_artifacts` partitions and the reindex lifecycle;
- active and empty `kb.artifact_connections` partitions, uniqueness, and replacement lifecycle;
- `kb.scene_objects.object_id` semantics;
- input deletion, cascade, forced reprocessing, and canonical-node retention behavior.

Each observation must distinguish:

1. a schema fact;
2. a live-data observation that may change;
3. a code-path behavior;
4. a design consequence or requirement for P1/P2.

The ADR must not turn point-in-time row counts into normative contracts.

The audit must also correct ADR C5. The deployed schema already has nullable
`kb.inputs.ks_store_id`, ingestion paths populate it, and the populated `Research` store proves
membership is partly wired. The accurate gap is that the column has no FK, uses the legacy name
rather than proposed `ks_id`, and is not consulted for pipeline routing, identity scope, ontology
visibility, or review-profile selection. Every corrected claim must cite the catalog query,
live-data query, migration, or code path that supports it.

### 2.2 Competency-question contract

Freeze the pilot competency questions derived from research §11.1 as stable, test-addressable
requirements. Each question must have:

- a stable identifier;
- an expected answer shape;
- positive and negative fixture expectations;
- the intended SQL validation boundary;
- an RDF/SPARQL parity expectation for P7, where applicable;
- an owner-review status.

P0 freezes the questions and expected answer semantics, not production queries that depend on P2
and P3 tables. Questions that cannot yet execute must name the phase that makes them executable.

The following matrix is complete for research §11.1; no source question is implicitly excluded.
“SQL phase” is the first phase in which the full answer can be tested. Every row also requires an
RDF/SPARQL parity case in P7 unless marked operational-only.

| ID | Frozen question | Expected answer shape | Positive / negative fixture contract | SQL phase | Owner review |
|---|---|---|---|---|---|
| CQ-I01 | Which artifact-object mentions resolve to canonical object X? | Ordered mention refs with artifact, evidence, decision, and canonical ID | ≥2 mentions resolve to X / similar mention remains separate | P2 | Pending domain owner |
| CQ-I02 | Is node X an individual, type, collection, occurrence, or concept? | Exactly one governed `ontological_level`, with provenance | one fixture per level / invalid or missing level rejected | P2 | Pending ontology owner |
| CQ-I03 | Which ontology classes apply to X, and what supports each classification? | Qualified class assertions with status and evidence | supported multi-classification / unsupported inferred class absent | P2–P3 | Pending ontology owner |
| CQ-I04 | Which IDs were merged or redirected to canonical ID X? | Non-transitive redirect/tombstone history | explicit A→B and B→C retained / no inferred A→C decision | P2 | Pending ontology owner |
| CQ-M01 | Which metric assertions apply to object X? | Assertion refs grouped by metric term and asserted object level | direct and inherited candidates identified / unrelated-object assertion excluded | P3 | Pending domain owner |
| CQ-M02 | Which assertions measure the same property or quantity kind? | Equivalence groups keyed by governed metric/property and quantity kind | aliases group together / same label with different quantity kind separates | P3 | Pending domain owner |
| CQ-M03 | Are assertion units dimensionally compatible and convertible? | Compatibility boolean plus normalized values and conversion provenance | cd/m² conversion succeeds / incompatible dimensions reject comparison | P3 | Pending domain owner |
| CQ-M04 | Are assertions observations, requirements, targets, references, or capabilities? | One governed assertion kind per assertion | one fixture per kind / ambiguous free text remains undecided | P3 | Pending domain owner |
| CQ-M05 | Under which procedures, conditions, and time windows do assertions apply? | Structured applicability tuple linked to evidence | matching procedure/condition/time / differing condition stays distinct | P3–P4 | Pending domain owner |
| CQ-M06 | Which assertion pairs are truly comparable? | Pair result with comparable flag or reason code | equivalent units and applicability compare / missing condition yields indeterminate | P3–P4 | Pending domain owner |
| CQ-P01 | Which provision imposes a metric requirement? | Provision→assertion→metric chain with evidence | normative clause links / descriptive mention does not impose | P3 | Pending domain owner |
| CQ-P02 | Which actor must perform which action on which object? | Qualified actor-action-object assertion with modality | explicit obligation parses / actorless clause remains incomplete | P3 | Pending domain owner |
| CQ-P03 | Which inventory item is an instance of which item type? | Item identity plus supported class assertion | named item classifies / similar item name alone is insufficient | P3–P4 | Pending domain owner |
| CQ-P04 | Which items are parts of, located in, or members of another object? | Qualified relation assertions preserving relation kind | one fixture per relation / similarity edge is not promoted | P3–P4 | Pending domain owner |
| CQ-R01 | Which profile applies to a document and why? | Profile release plus applicability trace and precedence result | one applicable profile / conflict returns indeterminate | P4 | Pending application owner |
| CQ-R02 | Which required assertion patterns are missing? | Findings only within a frozen closed review dimension | declared required metric missing / open dimension never reports missing | P4 | Pending application owner |
| CQ-R03 | Which evidence supports or contradicts an assertion? | Evidence refs partitioned by support relation | support and contradiction retained / absent evidence is not contradiction | P3–P4 | Pending domain owner |
| CQ-R04 | Which source is authoritative for a scope and date? | Source selection with jurisdiction, edition, interval, and precedence trace | effective superseding edition wins / unresolved jurisdiction conflict is indeterminate | P4 | Pending domain owner |
| CQ-R05 | How did a processor, model, prompt, or human action produce or modify an assertion? | Complete ordered provenance/audit events | automated then human decision visible / missing producer fails validation | P3 | Pending ontology owner |
| CQ-R06 | Would an object merge change previous review findings? | Impact set of affected assertions, scopes, runs, and findings without mutating history | merge candidate reports affected findings / unrelated merge has empty impact | P4 | Pending application owner |

The implementation document must expand each row into at least one positive and one negative named
fixture, an expected result example, and a SQL test outline. P7 adds the equivalent SPARQL query
and equality assertion over the exported representation.

### 2.3 Knowledge-store inventory

Record the verified deployed inventory:

- `Research` is the only populated knowledge store;
- `卫健委标准` exists but has no assigned inputs;
- some existing inputs have no knowledge-store assignment;
- current routing is one global `required_processors` list rather than store-specific pipelines;
- the deployed evidence cannot yet justify differentiated per-store policies.

The inventory must identify the minimum follow-up evidence needed before P1 policy authoring:
assign representative documents to each intended store, classify their document kinds, and
measure processor yield/usefulness by kind.

### 2.4 Status correction

Replace the stale P0 statement that the gold fixture is not wired to the generator, corpus case,
or comparator. Preserve an explicit distinction between:

- validation harness components that are built; and
- ontology runtime architecture that remains design-only.

The correction must also preserve the narrower remaining integration gap. `gold-run` can generate
the CDM corpus and invoke real processors through its dedicated CLI path, but `CorpusDataset` is
not integrated into the existing experiment orchestrator/runner/store engine. Real normalized
verdict scoring remains gated by structured `extract_metrics` output and `normalize_assertions`.

Keep the consolidated ADR at `Proposed`. P0 still lacks domain-owner approval of expected
answers, authoritative standard editions, the DR16 merged keyword specification, and the
`semos-ontology` repository/CI skeleton.

### 2.5 Handoff update

Update handoff `2026073002-handoff-semos-ontology-status` so a later session sees:

- which P0 audit work is complete;
- which findings were added to the ADR;
- what remains before P0 exit;
- that P1/P2 have not started.

### 2.6 Ontology terminology and implementation map

Add the following canonical crosswalk to the consolidated ADR. The support labels mean:

- **Native** — represented and governed directly in SemOS operational stores and APIs.
- **Existing artifact** — already exists in document processing but is not ontology content by
  default.
- **Selective import** — external content is compiled into the native model.
- **Projection** — generated for interchange; not the operational source of truth.
- **Deferred** — extension seams are preserved, but implementation requires a demonstrated need.
- **Not planned** — deliberately excluded from the architecture.

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

The ADR must present this as an implementation contract, not a general glossary: every row names
the SemOS construct, lifecycle phase, and semantic boundary. Any future term not in the matrix
defaults to unsupported until an ADR adds it.

## 3. Design Consequences

The following verified findings become explicit implementation requirements:

- P1 must give `kb.inputs.ks_store_id` referential integrity or document why it cannot.
- P1 must rename or otherwise disambiguate `kb.scene_objects.object_id`, whose current value is a
  scene-block occurrence ID such as `200_sbk_1`, not a canonical object identity.
- P1/P3 must decide whether search reindexing remains delete-then-insert without a transaction;
  the present behavior can temporarily remove a record's search rows when insertion fails.
- P2 must preserve one artifact to many object mentions. It must not introduce a uniqueness rule
  that collapses distinct mentions.
- P2 must explicitly decide whether `artifact_objects.object_id` stays a soft reference or gains
  referential enforcement compatible with merge tombstones and redirects.
- Reprocessing contracts must state which stores replace atomically and which may be emptied
  before an extractor succeeds.

These are requirements discovered by verification, not authorization to implement them in this
slice.

## 4. Verification

The documentation change is complete when:

1. every §13.5 verification item has a recorded result;
2. every audit claim has named catalog/live-query/migration/code-path evidence and ADR C5 no longer
   says `kb.inputs` has no knowledge-store reference;
3. the ADR contains no stale “not yet wired” benchmark claim and still states the narrower
   `CorpusDataset` experiment-engine integration gap;
4. all 20 research §11.1 competency questions appear exactly once with stable ID, expected answer
   shape, positive and negative fixture contract, first executable SQL phase, P7 SPARQL
   expectation, and owner-review status;
5. the knowledge-store inventory matches a fresh read-only deployed-database query;
6. the ADR remains `Proposed` and explicitly lists the unresolved P0 exit blockers;
7. the handoff records completed audit work, added findings, remaining P0 work, and that P1/P2
   have not started;
8. the ADR contains the complete §2.6 terminology crosswalk, and every row identifies its SemOS
   mapping, support class/phase, and boundary or exclusion rationale;
9. RDF/OWL/SKOS/SHACL runtime claims in the crosswalk agree with ADR DR13;
10. all changed document IDs and local paths resolve;
11. a repository-wide search finds no contradictory P0 status statement in the ADR or handoff;
12. `git diff --check` reports no whitespace errors.

## 5. Documentation Protocol

**What knowledge changes:** the current database and code behavior becomes a verified baseline
rather than an assumption inherited from earlier ADRs and migrations.

**Affected documents:** ADR `2026072901`, handoff `2026073002`, and this specification.

**Documents updated in this slice:** only those three KnowledgeStore documents.

**Documents that remain stale:** the keyword canonicalization proposals remain superseded but
unmerged; code capsules remain unchanged until their implementation phase.

**Intentionally undocumented:** production DDL, executable future-schema SQL, authoritative
medical-standard content, governance person assignments, and ontology-repository hosting
credentials.
