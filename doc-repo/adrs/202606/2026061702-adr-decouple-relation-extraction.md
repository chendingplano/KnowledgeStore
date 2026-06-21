# ADR 2026061702 — Decouple Relation Extraction (Free-Form, Parallel, Match-Afterward)

**Date:** 2026-06-17 \
**Status:** Proposal \
**Component:** ChenWeb, Doc Processor — extract-entity-relation \
**Authors:** Chen Ding \
**Tags:** doc processor, extract relations, performance, entity-resolution

**Supersedes:** ADR 2026061302 **D2, D3, D5, D6** (two-phase entity-aware, document-scoped,
windowed relation extraction + inline consolidation barrier). Retains 2026061302 **D1**
(relations carry `subject_entity_id`/`object_entity_id`) and **D4** (unresolved endpoints
become provisional, never dropped).

---

## Change Logs
* 2026/06/17, ADR Created.

## Context

Relation extraction today runs **inside** `EntityRelationProcessor.HandleEvent`,
fully sequential (`extract-entity-relation.go:295-345`):

```
Phase 1   entity extraction (per chunk)
Phase 1.5 consolidateEntities            -- blocks Phase 2
Phase 2   entity-AWARE windowed relations (entity roster fed into each window)
resolveAndLinkRelations                  -- synchronous, constrained to the entity set
```

Two problems, from the field:

1. **Latency (primary).** Entity extraction is 60-120s; relation extraction runs *after*
   it and is often longer. One document is 250-400s. The two passes have no true data
   dependency except the artificial one ADR 2026061302 introduced (feeding the consolidated
   entity roster into the relation prompt).
2. **Recall.** Relation extraction is constrained to "connect only entities in this list"
   (2026061302 D2). Relations whose endpoints were missed by Phase-1 entity extraction are
   never produced — the constraint that bought precision also caps recall.

ADR 2026061302 deliberately rejected post-hoc matching because it "produces dangling/
ambiguous edges." That objection was valid **at the time** — there was no mechanism to heal
those edges. ADR 2026061701 (corpus-level reconciliation: block → adjudicate → apply →
enrich, on a schedule) is now that mechanism. The objection no longer holds.

## Decision

Split relation extraction out of the entity-aware critical path. Entities and relations are
extracted **independently and concurrently**; endpoints are linked **after** both finish.

### DR1 — Two independent processors, triggered by the same upstream event

`EntityProcessor` and `RelationProcessor` both subscribe to the `line-file-generated`
event and run concurrently. Neither waits on the other. The Phase-1.5 consolidation barrier
(2026061302 D6) is removed from the relation path.

### DR2 — Relation extraction is free-form, line-anchored, and per-chunk

`RelationProcessor` uses `prompt-extract-relations-v2.md`: it emits each relation's
`subject_lines` / `predicate_lines` / `object_lines` grounded in the source text, with
endpoints written as natural-language surface forms (v2 §3.4). The entity-roster window
input (2026061302 Change 01) and the "connect only entities in this list" constraint
(D2/D3/D5) are dropped.

**Unit of extraction = the chunk** (revised 2026-06-17, after testing). Relations are
extracted **per chunk** — the same units entity extraction uses — rather than per
positional page window. Rationale: symmetric with entity extraction, smaller/focused
per-call input (a single 20-page window was 33 KB and under-extracted on a flash model),
and natural parallelism (one concurrent call per chunk). Each call's input is the chunk's
numbered lines as the v2 JSON array; the chunk's own overlap marker (`MarkedLine.Mark ==
"o"`) maps to the v2 `flag` "o" (context only). `RELATION_WINDOW_SIZE`/`_OVERLAP` no longer
apply to this path.

Accepted trade-off (same as entity extraction and as 2026061302 D5 framed it): a relation
whose endpoints fall in two different chunks is not captured; chunk overlap covers boundary
cases, and cross-document entity identity is healed by reconciliation (ADR 2026061701).

### DR3 — Endpoint linking moves to a post-hoc match step

After both passes complete, a **link step** resolves each relation endpoint to an
`entity_id` using:

1. **line-span overlap** — the endpoint's `*_lines` vs. each entity's mention `line_spans`
   (strong positional prior; requires entities record *all* mention spans),
2. **normalized-name match** — exact → alias → case/whitespace-folded, bridged across
   languages via `_en` (reuses `buildEntityResolutionIndex`).

Unmatched endpoints are minted **provisional** (2026061302 D4 machinery, unchanged) and
fed to scheduled reconciliation (ADR 2026061701). Relation `line_spans` now come **directly
from the prompt**, not `relationSpansFromEndpoints` — a strict grounding improvement.

### DR4 — The barrier: run linking in Phase C (post-process), not inline

**Revised after reading the code.** The pipeline already has the exact barrier we need:
`ControlService.runPostProcessIndexing` ("Phase C", `control.go`) runs each processor's
`PostProcessIndex(recordID)` **once, after every processor in the pipeline has finished**,
and implementations are required to be idempotent. `EntityRelationProcessor` already
implements it and already gates on `EntitiesExist && RelationsExist`.

The link step therefore runs **in Phase C**, before `IndexRelationGraphForRecord` (which
reads `subject_entity_id`/`object_entity_id`). This is strictly better than the
existence-guard-from-each-pass mechanism first drafted here: Phase C is the canonical
"all extraction done" hook, runs exactly once, and is already idempotent — so it works
whether entities and relations are produced by one combined processor or two split ones.

Consequence: **endpoint linking decouples from the processor split.** The free-form +
line-anchored linking can land via Phase C first; the parallel two-processor split (DR1)
becomes a pure performance layer added afterward, with no change to the link step.

*Alternatives considered and rejected:* (a) existence-guard fired from each pass — racy and
redundant given Phase C; (b) a new `entity-and-relation-ready` event — unnecessary plumbing.

### DR5 — Why this reverses 2026061302's post-hoc-matching rejection

The rejection assumed dangling/ambiguous edges were permanent. They are not, given
ADR 2026061701: the link step's provisional endpoints are exactly reconciliation's input,
and reconciliation merges/promotes them on a schedule. Decoupling is therefore justified by
(a) latency — the passes parallelize, wall-clock drops from `entity + relation` toward
`max(entity, relation)`; (b) recall — relations are no longer capped by Phase-1 entity
recall; (c) the reconciliation safety net that did not exist when 2026061302 was written.

## Database Migrations

**One migration required** (correcting an earlier "none expected" claim found during
implementation). In the decoupled flow the relation pass **saves before** linking, so the
prompt's endpoint line citations must survive to Phase C. `kb.relations` has no columns for
them today (only a single `line_spans`). Add:

* `kb.relations.subject_lines JSONB`, `predicate_lines JSONB`, `object_lines JSONB` —
  populated from the v2 contract at save time, consumed by the Phase C link step.

Everything else is reused: `subject_entity_id`/`object_entity_id` (2026061302 D1),
`entity_status='provisional'` (D4), `line_spans`. Entities already store `line_spans` as a
JSONB array of spans (verified: `consolidateEntities` unions every occurrence via
`sortedUniqueSpans`), which DR3 line-overlap matching depends on.

## Environment Variables

* `EXTRACT_RELATION_PROMPT=prompt-extract-relations-v2.md` (switch from v1).
* Relation-window vars (`RELATION_WINDOW_SIZE` / `_OVERLAP`) retained but reinterpreted as
  entity-agnostic positional slices (DR2).

## Implementation (planned)

* Split `EntityRelationProcessor` into `EntityProcessor` + `RelationProcessor`; both
  subscribe to `line-file-generated`. Remove the consolidation barrier from the relation path.
* `RelationProcessor`: drop entity-roster window input; feed numbered line-file slices;
  parse `*_lines` from the v2 contract; persist relations with empty `*_entity_id` (linked later).
* New **link step** (`linkRelationEndpoints`, pure + testable): line-span overlap +
  name-index match; mint provisionals; set `line_spans` from prompt. Guarded by
  `EntitiesExist && RelationsExist` (DR4).
* `consolidateEntities` stays — it still de-dups entities *within* a document; only its role
  as a relation-extraction prerequisite is removed.

## Consequences

* **Positive:** ~halves per-document wall-clock; higher relation recall; cleaner grounding
  (prompt-supplied `line_spans`); entity and relation passes independently scalable/retryable.
* **Negative / risk:** more provisional entities and noisier relations (free-form has no
  entity-list guard). Mitigated by v2 prompt precision rules (§2/§3.1) and by reconciliation
  absorbing the provisional load. The link step's quality now depends on entities recording
  all mention spans (DR3 caveat).
* **Cross-doc relations** remain out of scope at extraction time (still local); reconciliation
  handles cross-document *entity* identity, not new edges.

## Tests

* Link step: line-span overlap match, name-index match, provisional minting for unmatched,
  `line_spans` taken from prompt. Idempotent re-link.
* Barrier: link does not run until both `EntitiesExist && RelationsExist`; double-fire is safe.
* Parallelism: entity and relation passes produce identical stored artifacts regardless of
  completion order.

## Documentation Impact

* ADR 2026061302 — mark D2/D3/D5/D6 **superseded by this ADR**; D1/D4 retained.
* `extract-entity-relation-spec.md` — rewrite the two-phase flow as two parallel passes + link.
* `prompt-extract-relations-v2.md` §3.4 — already aligned (consistent endpoint naming feeds DR3).
* **Stale:** any doc describing relation extraction as entity-aware / entity-constrained.

## References
[1] 2026061303-ard-extract-entity-relation-amend.md — ADR 2026061302 (the design this supersedes).
[2] 2026061701-adr-entity-reconciliation.md — the reconciliation safety net DR5 relies on.
[3] prompt-extract-relations-v2.md — free-form, line-anchored relation prompt.
