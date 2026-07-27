# ADR 2026072701 — SemOS Ontology Architecture: Referent Identity, Governed Meaning, and Evidence-Backed Assertions

**Date:** 2026-07-27 \
**Status:** Accepted (design only — not yet implemented) \
**Component:** SemOS Knowledge Base, ontology, document processing, artifact association, and document review \
**Authors**: Chen Ding \
**Tags**: SemOS, ontology, kb.object_nodes, kb.artifact_objects, assertions, profiles, governance, review

## Change Logs
* 2026/07/27, ADR created. Ratifies the architectural decisions stabilized in
  spec `2026072702-spec-ontology-canonical-artifacts` after incorporating ontology
  governance, authoring lifecycle, and artifact-association design.

## Context

ADR 2026070101 established SemOS's object-centric foundation:

```text
artifact
  -> kb.artifact_objects
    -> kb.object_nodes
```

That architecture correctly solves canonical referent identity: many extracted
mentions can resolve to one stable object or occurrence. It does not, by
itself, solve SemOS's broader knowledge-governance question:

> For a given thing or class of thing, in a defined context, what should it be,
> what properties should it have, and what evidence supports that judgment?

The gap appears immediately in document review. If multiple artifacts mention
`pump` or resolve to pump `P-101`, SemOS still needs independent answers to:

* whether the referent is an instance of a governed class such as
  `centrifugal_pump`;
* which metrics, units, constraints, relationships, and review expectations
  apply to that class under a particular profile;
* whether an artifact is an observation, requirement, definition, target, or
  contradiction;
* which source evidence supports the claim;
* whether a review result is grounded in an active ontology/profile release or
  only in a candidate semantic suggestion.

The risk in not separating these concerns is structural, not cosmetic.
Canonicalizing every artifact family, or storing all semantics directly on
`kb.object_nodes`, would collapse identity, classification, retrieval
similarity, and normative review into one unstable layer. Summaries, semantic
projections, topics, and scene blocks are especially dangerous here: they are
valuable artifacts, but they are regenerated or derived views whose identities
must not become the ontology itself.

Spec `2026072702-spec-ontology-canonical-artifacts` resolves that problem by separating:

```text
source evidence
  -> artifact mention
    -> canonical referent
      -> ontology term / profile
        -> qualified assertion
          -> review or validation decision
```

This ADR records the stable architectural commitments from that spec so later
implementation ADRs and plans can assume them without re-litigating the model.

## Decision

SemOS adopts a layered ontology architecture in which referent identity,
ontology meaning, and evidence-backed assertions are separate but linked.

### DR1 — `kb.object_nodes` remains the canonical referent registry

`kb.object_nodes` is the authoritative identity layer for stable referents:
individuals, collections, occurrences, organizations, documents, places, and
other independently identifiable subjects of claims.

It answers:

> Which mentions refer to the same thing?

It does not, by itself, define term meaning, normative requirements, or the
truth of all attached claims.

### DR2 — SemOS does not introduce a universal "canonical artifact" layer

Artifacts are evidence-bearing information objects, not universally canonical
descriptions of the world. Metrics, provisions, inventory items, entities,
summaries, semantic projections, topics, and scene blocks remain distinct
artifact families with their own lifecycles and provenance.

Canonicalization applies to referents, not to every artifact family. A summary,
topic, or scene may link to canonical referents and ontology semantics, but it
does not become the canonical ontology node for that meaning.

### DR3 — Ontology meaning is governed in explicit ontology terms, not in object nodes

SemOS represents domain meaning through governed ontology terms and related
module/profile structures. Terms carry definitions, labels, kinds, mappings,
and lifecycle state. They answer:

> What does this class, property, role, quantity kind, assertion kind, or
> controlled concept mean?

An ontology class such as `pump` or `centrifugal_pump` is therefore an ontology
term first. An object node for pump `P-101` may be classified under that term,
but the term remains the authoritative definition of meaning.

### DR4 — "What should be" is governed by versioned profiles included in module releases

SemOS answers normative review questions through ontology profiles and profile
rules, not through corpus frequency, similarity, or uncontrolled convention.

Profiles define scoped expectations such as:

* which classes or roles they apply to;
* which metrics, relationships, units, and evidence are required or allowed;
* which jurisdiction, standard version, operating mode, or effective period
  qualifies the rule.

A profile version becomes production-selectable only when it is included in an
activated ontology module release. Module release is the activation boundary for
governed ontology content.

### DR5 — Artifact-to-ontology association is mediated by qualified assertions with evidence

SemOS does not directly treat an artifact string, similarity hit, or extracted
label as authoritative ontology truth. Instead, semantic linkage is expressed
through qualified assertions and evidence-backed association records.

Examples include:

* an object node is an instance of an ontology class;
* an artifact is about an ontology term;
* an artifact supports or contradicts an assertion;
* a scene describes an occurrence;
* a review finding is governed by a specific profile rule.

Each semantic claim must preserve status, provenance, evidence, and lifecycle.
Conflicting or superseded assertions are retained as separate claims rather than
flattened into one mutable object state.

### DR6 — Ontology authoring is governed; LLM output may propose content but may not activate it alone

Ontology terms, assertion templates, profile rules, mappings, and modules are
created through a governed authoring and release lifecycle:

```text
discovered -> draft -> in_review -> approved -> included_in_release
```

Operational assertions and artifact associations use a parallel reviewable
lifecycle such as candidate, accepted, rejected, deferred, superseded, or
unsupported where applicable.

LLMs may draft candidates, propose mappings, or suggest associations, but they
must not alone:

* activate ontology content;
* accept a governed semantic decision into production;
* define the current normative profile set.

Human or explicitly governed system approval is required for those transitions.

### DR7 — Each accepted relationship has one authoritative owner store; search and graph tables are derived projections

Every accepted artifact-to-ontology relationship must persist in exactly one
authoritative owner store appropriate to its semantic meaning. Derived tables
such as `kb.search_artifacts` and `kb.artifact_connections` may project or
index those relationships for retrieval and navigation, but they are not the
system of record for ontology meaning or qualified assertions.

This prevents the same semantic relationship from being independently and
inconsistently "owned" by multiple projection tables.

## Alternative Decisions

### AD1 — Store all meaning directly on `kb.object_nodes`

Rejected. An object node is a referent identity, not a bag of global facts.
Doing so would overwrite conflicting claims, erase modality and time, and make
it impossible to preserve multiple evidence-backed assertions about one object.

### AD2 — Canonicalize every artifact family

Rejected. Derived artifacts such as summaries, topics, semantic projections,
and scene blocks do not share the same identity semantics as stable referents or
governed ontology terms. Treating them all as canonical nodes would create false
merges and unstable identities whenever processors or prompts change.

### AD3 — Use `kb.artifact_connections` as the ontology store

Rejected. `kb.artifact_connections` is valuable as a derived navigation graph,
but it mixes relation families with different epistemic status and does not by
itself carry the full governance, profile, assertion, and evidence contracts the
ontology architecture requires.

### AD4 — Infer "what should be" from corpus frequency or similarity

Rejected. Corpus prevalence is not governance. Normative review requires
explicit scoped profiles, effective versions, and evidence-aware reasoning.

## Database Migrations

This ADR does not by itself define the concrete migration set. It establishes
the architectural boundary that later implementation ADRs must follow:

* referent identity remains centered on `kb.object_nodes`;
* governed ontology structures must be stored separately from object identity;
* qualified assertions and authoritative association ownership must be
  represented explicitly rather than only as derived graph edges.

## Data Formats

The normative logical model has at least these distinct record families:

* canonical referents;
* ontology terms and modules;
* ontology profiles and profile rules;
* qualified semantic assertions;
* assertion evidence and support/contradiction links;
* artifact-semantic association records;
* ontology candidates, semantic-decision candidates, and change sets;
* immutable ontology-module releases.

Concrete table names and JSON payload shapes are deferred to follow-up design
and implementation ADRs.

## Environment Variables

No environment-variable contract is introduced by this ADR. Any future toggles
for ontology processing, authoring queues, or release activation must preserve
the decision boundaries recorded here.

## Implementation

Implementation is expected to proceed in phases consistent with spec
`2026072702-spec-canonical-artifacts`:

### Code Changes

Planned areas include:

* ontology-term, profile, module, candidate, and release persistence;
* qualified assertion and evidence persistence;
* artifact-to-ontology association pipeline stages;
* projection/indexing updates so derived stores reflect authoritative semantic
  ownership without becoming it;
* review workflows that select active profiles and explain findings through
  released rules plus source evidence.

Follow-up ADRs should treat this document as the architecture baseline rather
than reopening the layer boundaries.

## Operational Behaviors

SemOS operational behavior after this ADR is:

* object reconciliation continues to resolve artifact mentions to canonical
  referents;
* ontology authoring produces governed candidates before release;
* released modules determine which terms and profiles are active in production;
* artifact association pipelines generate candidates, validate them, adjudicate
  them, persist one authoritative accepted relationship, and then build derived
  projections;
* document review answers "what should be" from released profiles plus
  evidence-backed assertions, not from raw string matches alone.

## Consequences

Positive consequences:

* SemOS gains a clear answer to the distinction between identity, meaning, and
  evidence.
* Review findings become explainable in terms of released profiles and cited
  source evidence.
* Conflicting, superseded, and conditionally true claims can coexist without
  corrupting canonical identity.
* Additional artifact families can join the semantic system without becoming
  pseudo-canonical ontology nodes.

Costs and constraints:

* The system becomes more explicit and therefore more complex than a single
  graph-edge or object-property model.
* Implementers must respect authoritative ownership boundaries and avoid
  silently writing semantic truth into projection tables.
* Governance and release discipline become mandatory for ontology evolution.

## Tests

Implementation that claims conformance to this ADR should verify at least:

* a canonical object can be classified under a released ontology term without
  storing the term definition on the object node itself;
* conflicting assertions about one referent are preserved as separate
  evidence-backed records;
* a profile version is not production-selectable before module-release
  activation;
* an accepted artifact-semantic relationship has one authoritative owner and
  appears in search/graph projections only as a derived effect;
* removing or superseding evidence updates assertion/association status without
  deleting historical provenance.

## Documentation Impact

This ADR ratifies and depends on:

* [2026072702-spec-canonical-artifacts](/Users/cding/Workspace/KnowledgeStore/doc-repo/specs/202607/2026072702-spec-canonical-artifacts.md)
* [2026072302-rsch-object-centric-ontology](/Users/cding/Workspace/KnowledgeStore/doc-repo/research/202607/2026072302-rsch-object-centric-ontology.md)
* [2026070101-adr-object-centric-design](/Users/cding/Workspace/KnowledgeStore/doc-repo/adrs/202607/2026070101-adr-object-centric-design.md)
* [2026070701-adr-object-reconciliation-ambiguous-tie-resolution](/Users/cding/Workspace/KnowledgeStore/doc-repo/adrs/202607/2026070701-adr-object-reconciliation-ambiguous-tie-resolution.md)

Follow-up ADRs are still needed for:

* concrete ontology storage schema and migration design;
* exact assertion/evidence table contracts;
* module release activation mechanics;
* review-engine execution against released profiles.

## References

1. [2026072702-spec-ontology-canonical-artifacts](/Users/cding/Workspace/KnowledgeStore/doc-repo/specs/202607/2026072702-spec-ontology-canonical-artifacts.md)
2. [2026072302-rsch-object-centric-ontology](/Users/cding/Workspace/KnowledgeStore/doc-repo/research/202607/2026072302-rsch-object-centric-ontology.md)
3. [2026070101-adr-object-centric-design](/Users/cding/Workspace/KnowledgeStore/doc-repo/adrs/202607/2026070101-adr-object-centric-design.md)
4. [2026070701-adr-object-reconciliation-ambiguous-tie-resolution](/Users/cding/Workspace/KnowledgeStore/doc-repo/adrs/202607/2026070701-adr-object-reconciliation-ambiguous-tie-resolution.md)
