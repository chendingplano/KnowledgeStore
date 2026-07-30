# Spec 2026073004 — SemOS P0 Ontology Completion Slice

**Status:** Approved design, pending implementation
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
8. all changed document IDs and local paths resolve;
9. a repository-wide search finds no contradictory P0 status statement in the ADR or handoff;
10. `git diff --check` reports no whitespace errors.

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
