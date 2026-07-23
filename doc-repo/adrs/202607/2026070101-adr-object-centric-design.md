# ADR 2026070101 - Object Centric Design

**Date:** 2026-07-01 \
**Status:** Proposal \ 
**Component:** xxx \
**Authors**: Chen Ding\

## Change Logs
* 2026/07/01, ADR Created
* 2026/07/03, Recorded the review-side dependency from ADR 2026070201 AR6: the
  object-anchored missing-metric pass cites `kb.artifact_objects` evidence fields
  (line spans, confidence; §DR2), so those fields must stay populated.
* 2026/07/23, Added Phase 3 (implements DR7): entity→object-node reconciliation.
  Entities are matched against existing `kb.object_nodes` only (never create a
  node from an entity); matches are recorded as `represented_by` edges in
  `kb.artifact_connections`. Ambiguous-entity resolution is explicitly deferred
  (no queue, no LLM adjudication for entities — see Phase 3 §Scope). Also
  flagged a suspected cleanup gap in `DeleteInput`
  (`ChenWeb/server/api/kbhandler/metrics_handler.go`, added 2026/07/22, not yet
  tested) — **superseded below**, see the 2026/07/23 (later) entry.
* 2026/07/23 (later), Corrected the `DeleteInput` claim above: checked against
  the live migrations, `kb.artifact_connections` and `kb.artifact_objects`
  both already carry `ON DELETE CASCADE` FKs to `kb.inputs(id)` (added
  2026/06/04 and 2026/07/02–03, respectively), so neither table was ever
  actually orphaned by record deletion — the explicit deletes for them that
  had independently been added to `inputRelatedDeleteSpecs` are redundant
  defense-in-depth, not a bug fix. Added
  `TestInputRelatedDeleteSpecsCoverArtifactGraphTables`
  (verified RED before GREEN) to guard those entries — and the deliberate
  absence of `kb.object_nodes` — against future silent regression, closing
  the actual gap (test coverage on new-and-untested code), not the orphan risk
  that turned out not to exist. See Phase 3 §Record Deletion Requirements for
  the full correction.
* 2026/07/23, Refined Phase 3: added §What "Unlinked" Means (an unlinked entity
  is not one uniform state — type-excluded, evidence-insufficient, and
  ambiguous-skipped are three different claims and must stay distinguishable);
  added a logging requirement per skip reason, mirroring ADR 2026070701 DR1's
  "alarm on every ambiguous outcome" precedent (undocumented misses were exactly
  how that ADR's ~40-row `object_id IS NULL` bug went unnoticed); and linked
  ADR 2026070701 DR7 as the existing LLM-adjudication pattern to reuse if
  ambiguous-entity resolution is picked back up later.
* 2026/07/23 (later still), Added Phase 4 (proposed): a periodic, LLM-classified
  resolution pass for entities Phase 3's match-only step left unlinked, per a
  three-way decision (exclude permanently / associate — matching or creating a
  node / uncertain — bounded retries). **Chooses Fork A**: qualifying entities
  become a gated `kb.artifact_objects` producer (`artifact_type = 'entity'`),
  reusing `ReconcileOne`/`CreateNode`/DR7's ambiguous-LLM-adjudicator and DR6's
  admin page wholesale rather than building parallel entity-specific machinery.
  This narrows AD3 (see AD3 note) and **amends Phase 3's edge mechanism**:
  Phase 3's bespoke `represented_by` edge is superseded by the standard
  `belong_to`/`object_id` edge shape Fork A's `kb.artifact_objects` rows
  already produce via the existing generic indexer — see Phase 4 §Phase 3
  Amendment. Phase 3's original text is left intact as the record of the
  match-only design that predated this choice; Phase 4 states explicitly what
  it supersedes rather than rewriting Phase 3 in place.
* 2026/07/23 (later still, cont'd), Fixed a design flaw in Phase 4's own first
  draft: `deferred` entities were re-classified on every resolve-pass with no
  check for whether anything relevant had actually changed — a blind
  schedule-driven retry, not a change-driven one, despite the classifier being
  specified deterministic (temperature 0). Added `object_link_fingerprint`
  (hash of entity identity signature + candidate `object_id` set) as a gate:
  a `deferred` entity is only re-sent to the LLM when its fingerprint differs
  from the one last classified against; otherwise the resolve pass skips it
  at zero LLM cost, leaving `object_link_attempts` untouched. This follows
  ADR 2026070701 DR7 more precisely than the first draft did — that LLM
  adjudicator runs once per fresh ambiguous row, and its repeatable backfill
  endpoint (DR5) only re-runs the cheap deterministic tie-break on retry, never
  the LLM again. See Phase 4 §Fingerprint-Gated Retry.
* 2026/07/23 (later still, cont'd 2), Phase 3 and Phase 4 implemented and
  landed. Added Phase 5: an in-process scheduler
  (`server/api/scheduler`, `kb.scheduled_jobs`/`kb.scheduled_job_runs`) and a
  System Admin → Schedules admin page, closing the gap this ADR's own Phase 4
  "Repeatable Endpoint, Not a New Scheduler" subsection left open — nothing
  was actually calling `/kb/entities/resolve-objects`,
  `/kb/objects/resolve-ambiguous`, or `/kb/search/backfill-embeddings` on any
  schedule, confirmed by tracing callers. Also corrected several places
  where this ADR's Phase 3/4 text described the originally-specced design
  rather than what was actually implemented: Phase 3 doesn't call
  `ObjectReconciler.ReconcileOne` (would call `CreateNode`, which it must
  never do) and has no env-var enable flag or configurable threshold (both
  hardcoded); Phase 4's "associate" path doesn't route through
  `reconcileArtifactObjectsWithLLM` (would stack a second LLM adjudication on
  top of the classifier's own); `ENTITY_OBJECT_RESOLVE_ENABLED` and
  `ENTITY_OBJECT_RESOLVE_CONCURRENCY` were specced but not built. See the
  "Superseded"/"Not implemented as specced" notices inline in Phase 3/4 and
  the corrected Code Changes lists for each.

## Context
This is about the artifacts (refer to [1]) and their hybrid search.

### Problem 1
For artifacts, such as `metrics`, `inventory_items`, and `provisions`,
as it is now, are extracted alone. These artifacts, however, do not
make much sense without relating to the objects they apply. For instance, 
for a metric: 'max-pressure' = 100, it does not make any sense without
mentioning the object the metric applies to. 

The same is true for other artifacts.

## Decision
### DR1 
When extracting `metrics`, `inventory_items`, and `provisions`,
extract not only the artifacts but also their objects, too.

### DR2
All doc processors that extract objects must share the same object storage
contract. Object records are stored in `kb.artifact_objects`, not in
processor-specific object tables.

`kb.artifact_objects` is the source of truth for extracted object mentions:
which artifact mentions which object, with what role, evidence, line spans, and
confidence. Existing processor fields such as
`kb.metrics.metric_subject`, `kb.provisions.provision_subject`, and
`kb.inventory_items.item_name` remain as compatibility/display fields, but they
must not become separate object models.

### DR3
Object identity is represented by a second table: `kb.object_nodes`.

`kb.object_nodes` is the canonical object identity layer. It groups many
`kb.artifact_objects` rows that refer to the same real-world or domain object
across artifacts, processors, and documents.

The relationship is:

```text
metric/provision/inventory_item
  -> kb.artifact_objects
      -> kb.object_nodes
```

`kb.artifact_objects` rows are evidence and must not be deleted or merged as a
substitute for reconciliation. Reconciliation links them to `kb.object_nodes`.
Duplicate canonical nodes are reconciled by merging or redirecting canonical
object identity, while preserving the original mention rows.

### DR4
Reconciliation happens at both layers:

- `kb.artifact_objects` reconciliation decides whether an extracted object
  mention links to an existing canonical `kb.object_nodes` row, creates a new
  node, or remains ambiguous/pending.
- `kb.object_nodes` reconciliation decides whether two canonical object nodes
  actually represent the same object and should be merged or redirected.

`kb.artifact_objects` therefore stores reconciliation fields such as
`object_id`, `reconcile_status`, and `reconcile_confidence`.

### DR5
Vector embeddings for object reconciliation are optional.

Keyword/name-based reconciliation is the baseline and must work without
embeddings. Embeddings improve recall but are not required for correctness.
When embeddings are disabled, reconciliation relies on exact normalized names,
aliases, acronyms, language variants, type/role compatibility, lexical search,
and optional LLM adjudication for ambiguous high-value cases.

### DR6
Objects are identified by a name bundle, not by a single name string.

Object identity must account for source-language names, English names, aliases,
acronyms, normalized names, object type, object role, evidence, and document
context. Names generate candidates; they do not alone prove identity.

### DR7
Entities are related to objects but are not identical to objects.

`kb.entities` remains the general entity artifact family. Some entities can be
promoted or linked to `kb.object_nodes` when they represent an artifact object
or provide strong evidence for one. Other entities may be concepts, relation
endpoints, organizations, standards, or broad terms that should remain entities
only.

Object/entity links should be stored as graph edges, preferably in
`kb.artifact_connections`, using a relation such as `represented_by` and method
`object-entity-reconciliation`.

This split exists because entities and objects answer different questions and
are produced by different processes:

- **Entities** (`extract_entity_relation`, [13]) answer "what things are
  mentioned in this document" — the broadest possible net, including systems,
  organizations, standards, people, places, and abstract concepts. Their
  `entity_type` is **open vocabulary**: an LLM free-text field with only
  loose examples (`software_system`, `organization`, `concept` —
  [extract-entity-relation-spec.md §Entity row]), not a controlled enum.
- **Objects** (`kb.object_nodes`) answer "what real-world/domain thing does
  this measurement, rule, or inventory row apply to" — narrower, and
  extracted only when a metric/provision/inventory item already provides
  per-instance evidence that the LLM judged strong enough to synthesize an
  object from (DR1). Their `object_type` is a **controlled enum**
  (`equipment|material|system|process|organization|person|place|document|concept|other`
  — see §Data Formats).

Because `object_type` includes `concept`, it is tempting to read AD3's
rejection as merely "concepts don't count." That is not the actual boundary:
`object_type = concept` is legitimate when a metric/provision's own subject
*is* a concept (e.g. a provision governing "the risk management process") and
an LLM made that call with the metric/provision's local evidence in hand. What
AD3 rejects is treating *every* entity — including generic, corpus-wide,
zero-instance-evidence entities like "quality management" — as an object
candidate merely because it was named somewhere. Phase 3 (below) therefore
does not gate on the `object_type` enum's permissiveness; it gates on which
`entity_type` values are reliably concrete enough, corpus-wide, to attempt
matching at all. See Phase 3 §Entity Type → Object Type Compatibility for the
mapping and the reasoning behind each inclusion/exclusion.

### DR8
Prompt changes for this ADR use new versioned prompt files instead of modifying
the existing prompt files in place. This gives a clean rollout and rollback path
through processor configuration.

New prompt files:

- `ChenWeb/prompts/prompt-extract-metric-candidates-v5.md`
- `ChenWeb/prompts/prompt-enrich-metrics-v3.md`
- `ChenWeb/prompts/prompt-extract-provisions-v3.md`
- `ChenWeb/prompts/prompt-extract-inventory-items-v3.md`

### Alternative Decisions

### AD1: Add Object Columns to Each Artifact Table
Rejected. Adding `metric_objects`, `provision_objects`, or extra JSON columns
inside each artifact table would make every processor define object semantics
slightly differently. It would also make cross-processor object reuse and
hybrid search harder.

### AD2: Treat Existing Subject Fields as Objects
Rejected as the final design. Existing subject fields are useful display labels,
but they are usually single strings and cannot reliably represent multiple
objects, object roles, evidence, confidence, or normalized object identity.

### AD3: Treat All Entities as Objects
Rejected. Entities are useful object candidates and evidence anchors, but not
every entity should become an object. A concept like "quality management" or a
generic relation endpoint may be valuable as an entity without being a canonical
object node.

**Narrowed, not overturned, by Phase 4.** AD3 rejects *unconditional*
entity→object promotion — every entity, automatically, with no judgment
applied. Phase 4 does not do that: an LLM classifier decides, per entity,
whether it belongs, and the type allow-list (§Phase 3) and confidence gate
(§Phase 4) both still exist to keep the "not every entity" default intact.
Only entities an explicit, auditable decision approved reach
`kb.artifact_objects`. If that classifier ever degrades into effectively
approving everything, AD3's original concern is exactly what has resurfaced,
and this narrowing should be revisited.

### Database Migrations

Add migrations:

```text
ChenWeb/project_migrations/20260702000002_create_kb_artifact_objects.sql
ChenWeb/project_migrations/20260702000003_create_kb_object_nodes.sql
```

Create table `kb.artifact_objects` with at least:

| Column | Type | Notes |
|---|---|---|
| `id` | `BIGSERIAL` | Primary key |
| `input_record_id` | `BIGINT` | FK to `kb.inputs(id)` |
| `artifact_type` | `TEXT` | `metric`, `provision`, `inventory_item`, etc. |
| `artifact_id` | `TEXT` | Processor artifact ID, e.g. metric ID |
| `object_id` | `TEXT` | Nullable FK/logical link to `kb.object_nodes.object_id` |
| `object_name` | `TEXT` | Source-language object name |
| `object_name_en` | `TEXT` | English object name when applicable |
| `object_name_zh` | `TEXT` | Chinese object name when applicable |
| `language` | `TEXT` | Source language |
| `object_type` | `TEXT` | `equipment`, `material`, `system`, `process`, etc. |
| `object_role` | `TEXT` | `measured_object`, `regulated_object`, `self`, etc. |
| `aliases` | `JSONB` | Source-language and mixed-language aliases |
| `acronyms` | `JSONB` | Acronyms and abbreviations |
| `normalized_names` | `JSONB` | Normalized candidate names for matching |
| `description` | `TEXT` | Short object description |
| `evidence_quote` | `TEXT` | Supporting source text |
| `source_line_spans` | `JSONB` | Canonical line spans |
| `confidence` | `DOUBLE PRECISION` | Object extraction confidence |
| `reconcile_status` | `TEXT` | `pending`, `matched`, `new`, `ambiguous`, `rejected` |
| `reconcile_confidence` | `DOUBLE PRECISION` | Confidence of object-node link |
| `ext_info` | `JSONB` | Processor-specific metadata |
| `create_time` | `TIMESTAMPTZ` | Default `NOW()` |
| `modify_time` | `TIMESTAMPTZ` | Default `NOW()` |

Indexes:

- `(input_record_id, artifact_type, artifact_id)`
- `(artifact_type, object_name)`
- GIN or expression index for normalized object lookup if needed

Uniqueness:

- Use an idempotency key over
  `(input_record_id, artifact_type, artifact_id, normalized object_name, object_role)`.

Create table `kb.object_nodes` with at least:

| Column | Type | Notes |
|---|---|---|
| `id` | `BIGSERIAL` | Primary key |
| `object_id` | `TEXT` | Stable canonical object ID |
| `canonical_object_id` | `TEXT` | Current survivor when this node is merged |
| `canonical_name` | `TEXT` | Preferred display name |
| `canonical_name_en` | `TEXT` | Preferred English display name |
| `canonical_name_zh` | `TEXT` | Preferred Chinese display name |
| `primary_language` | `TEXT` | Best known source language |
| `object_type` | `TEXT` | Canonical object type |
| `aliases` | `JSONB` | Alias strings grouped or tagged by language |
| `acronyms` | `JSONB` | Acronym strings and expansions |
| `normalized_names` | `JSONB` | Normalized names used for matching |
| `description` | `TEXT` | Canonical description |
| `search_document` | `TEXT` | Lexical reconciliation/search text |
| `embedding` | `VECTOR` | Nullable; present only when embedding support is enabled |
| `reconcile_status` | `TEXT` | `active`, `merged`, `pending_review`, `rejected` |
| `ext_info` | `JSONB` | Merge/evidence metadata |
| `create_time` | `TIMESTAMPTZ` | Default `NOW()` |
| `modify_time` | `TIMESTAMPTZ` | Default `NOW()` |

Indexes:

- Unique `(object_id)`
- `(canonical_object_id)`
- `(object_type, canonical_name)`
- GIN index on `normalized_names`
- GIN or full-text index on `search_document`
- Vector index only when embedding support is enabled

Object/entity links:

- Store links in `kb.artifact_connections` with:
  - `source_type = 'object'`
  - `source_id = kb.object_nodes.object_id`
  - `target_type = 'entity'`
  - `target_id = kb.entities.entity_id`
  - `relation_name = 'represented_by'`
  - `relation_method = 'object-entity-reconciliation'`

### Data Formats

Processors must normalize objects into the following JSON shape before
persistence:

```json
{
  "object_name": "string",
  "object_name_en": "string",
  "object_name_zh": "string",
  "language": "string",
  "object_type": "equipment|material|system|process|organization|person|place|document|concept|other",
  "object_role": "measured_object|regulated_object|requirement_target|inventory_item|component|parent_system|self|other",
  "aliases": ["string"],
  "acronyms": ["string"],
  "normalized_names": ["string"],
  "description": "string",
  "evidence_quote": "string",
  "source_line_spans": ["12", "13:15"],
  "confidence": 0.0
}
```

Rules:

- A single artifact may have multiple objects.
- If a metric has no explicit `objects` array, synthesize one object from
  `subject` / `metric_subject`.
- If a provision has no explicit `objects` array, synthesize one object from
  `subject` / `provision_subject`.
- Each inventory item must produce a `self` object row for the item itself.
- Processors may emit additional related objects, such as parent systems,
  measured objects, or regulated targets.
- Source line spans use the same canonical span normalization as artifacts.
- The normalized name set should include source names, English names, Chinese
  names, aliases, acronyms, acronym expansions, and deterministic normalized
  variants.
- Names identify reconciliation candidates, not final identity. Object type,
  role, source evidence, inventory attributes, entity links, and document
  context must be considered before linking or merging.

### Environment Variables

Add new prompt defaults/configuration:

| Processor | Prompt env | New default prompt |
|---|---|---|
| Metric candidate pass | `EXTRACT_METRIC_CANDIDATES_PROMPT` | `prompt-extract-metric-candidates-v5.md` |
| Metric enrichment pass | `ENRICH_METRICS_PROMPT` | `prompt-enrich-metrics-v3.md` |
| Provisions | `EXTRACT_PROVISIONS_PROMPT` | `prompt-extract-provisions-v3.md` |
| Inventory items | `EXTRACT_INVENTORY_ITEMS_PROMPT` | `prompt-extract-inventory-items-v3.md` |

Add reconciliation configuration:

| Env var | Default | Purpose |
|---|---|---|
| `OBJECT_RECONCILE_EMBEDDING_ENABLED` | `false` | Enables vector similarity for object reconciliation |
| `OBJECT_RECONCILE_MIN_LEXICAL_SCORE` | implementation default | Minimum keyword/BM25 score for candidate acceptance |
| `OBJECT_RECONCILE_MIN_COSINE` | implementation default | Minimum cosine similarity when embeddings are enabled |
| `OBJECT_RECONCILE_MAX_CANDIDATES` | implementation default | Maximum candidates considered per artifact object |
| `OBJECT_RECONCILE_LLM_ADJUDICATION_ENABLED` | `false` | Enables optional LLM adjudication for ambiguous candidates |

## Implementation

Implementation is split into two phases.

### Phase 1: Metrics

Goal: implement shared object storage and make `extract_metrics` the first
producer of `kb.artifact_objects`, linked to canonical `kb.object_nodes`.

Code changes:

- Create `artifact_objects.go` in `ChenWeb/server/api/doc-processing`.
- Create `object_nodes.go` in `ChenWeb/server/api/doc-processing`.
- Add migration `20260702000002_create_kb_artifact_objects.sql`.
- Add migration `20260702000003_create_kb_object_nodes.sql`.
- Extend metric candidate extraction to include object hints.
- Extend metric enrichment to return `objects`.
- Normalize and persist metric objects after metric rows are saved.
- Reconcile metric object mentions to existing or new `kb.object_nodes`.
- Preserve `metric_subject` as the primary display label, using the first object
  when appropriate.
- Include object names and descriptions in metric `search_document`.
- Add tests for object normalization, fallback object synthesis, idempotent
  persistence, object-node linking, and metric search text.

Prompt changes:

- Create `prompt-extract-metric-candidates-v5.md`.
- Create `prompt-enrich-metrics-v3.md`.
- Do not modify the existing v4/v2 metric prompts.

Verification:

```bash
cd /Users/cding/Workspace/ChenWeb/server
go test ./api/doc-processing -run 'Metric|ArtifactObject'
go test ./api/kbhandler -run Metric
```

### Phase 2: Provisions and Inventory Items

Goal: make `extract_provisions` and `extract_inventory_items` produce the same
shared object records.

Provision changes:

- Extend provision extraction schema to include `objects`.
- Normalize and persist provision objects using `artifact_type = 'provision'`.
- Reconcile provision object mentions to `kb.object_nodes`.
- Preserve `provision_subject` as the primary display label.
- Include object text in provision search documents.
- Create `prompt-extract-provisions-v3.md`.
- Do not modify the existing v2 provision prompt.

Inventory item changes:

- Treat each inventory item as a `self` object row in `kb.artifact_objects`.
- Allow related objects such as parent system, component, regulated target, or
  measured object.
- Normalize and persist inventory item objects using
  `artifact_type = 'inventory_item'`.
- Reconcile inventory item object mentions to `kb.object_nodes`.
- Include related object text in search only when it is not a duplicate of the
  item name or canonical name.
- Create `prompt-extract-inventory-items-v3.md`.
- Do not modify the existing v2 inventory prompt.

Verification:

```bash
cd /Users/cding/Workspace/ChenWeb/server
go test ./api/doc-processing -run 'Provision|Inventory|ArtifactObject'
go test ./api/kbhandler -run 'Provision|Inventory|Metric'
cd /Users/cding/Workspace
go work sync
```

### Phase 3: Entity → Object Reconciliation (DR7)

Goal: link `kb.entities` rows to existing `kb.object_nodes` rows where an
entity plausibly denotes a canonical object already established by metric,
provision, or inventory-item extraction — without making entities a new
producer of `kb.artifact_objects` or `kb.object_nodes` rows (AD3 stays
rejected). This is strictly additive: it reads `kb.entities` and
`kb.object_nodes`, and writes only graph edges.

#### Scope

- **Match-existing-only.** This phase never calls the equivalent of
  `ObjectNodeSQLStore.CreateNode` for an entity. Object identity is anchored
  by metrics/provisions/inventory items (which must always resolve to *some*
  object, per DR1's fallback-synthesis rule); entities merely *may*
  corroborate one that already exists. If no sufficiently confident node
  exists, the entity is simply left unlinked.
- **Ambiguous entities are skipped, not queued.** Unlike artifact-object
  reconciliation, which has an ambiguous-candidate resolution path
  (`object_ambiguous_llm.go`, `object_ambiguous_resolution.go`) backed by
  `kb.artifact_objects.reconcile_status = 'ambiguous'`, entities have no
  equivalent status column and are not `kb.artifact_objects` rows. A tied or
  sub-threshold match is treated as "no link" and dropped — no new admin
  queue, no LLM adjudication for entities. This is an explicit, current-phase
  decision, not an oversight; revisit only if false negatives prove costly in
  practice.
  **Reuse path if revisited:** ADR 2026070701 §3.7 DR7 already implements an
  LLM adjudicator for exactly this shape of ambiguity (tied/low-confidence
  `FindCandidates` results) for metric/provision/inventory-item artifact
  objects — confidence-gated, allowlisted field completion, object-node merge
  handling, `kb.object_audit_log` provenance. It cannot be reused unmodified
  because it operates on persisted `kb.artifact_objects` rows and entities are
  deliberately not that (§Scope above); extending it to entities means either
  (a) forking its decision/apply logic into an entity-specific, still
  non-persisted variant, or (b) revisiting §Scope's "never persisted" stance so
  entities become a gated `kb.artifact_objects` producer after all. Neither is
  decided here — see the side-question discussion this ADR entry originated
  from for the live design fork.

#### Entity Type → Object Type Compatibility

`entity_type` is open vocabulary (LLM free text); `object_type` is a
controlled enum. A direct string match is therefore wrong on both sides: it
would miss synonyms (`software_system` vs. `system`) and, more importantly, it
would not filter out entity types that are structurally unlikely to denote a
reusable canonical object even when the LLM's wording happens to collide with
an enum value.

The mapping is a static allow-list, not a general classifier, deliberately
conservative in what it lets through:

| `entity_type` (examples seen from extraction) | Maps to `object_type` | Included? | Why |
|---|---|---|---|
| `software_system`, `system`, `platform` | `system` | Yes | Concrete, reusable, commonly the measured/regulated object of metrics and provisions. |
| `equipment`, `device`, `machine`, `product` | `equipment` | Yes | Same as above — this is exactly the kind of thing DR1 synthesizes objects for. |
| `material`, `substance` | `material` | Yes | Same. |
| `organization`, `company`, `agency` | `organization` | Yes | Stable, name-bearing, commonly a `regulated_object` role. |
| `place`, `location`, `facility` | `place` | Yes | Stable and concrete. |
| `concept`, `topic`, `theme` | `concept` | **No** | The enum permits `object_type = concept`, but only when a metric/provision's own local evidence justified synthesizing one (DR1). A corpus-wide entity labeled "concept" has no such per-instance evidence backing it — linking it here would recreate exactly what AD3 rejected, just through a side door. |
| `standard`, `document`, `regulation` | `document` | **No** | Standards/documents are referenced *by* provisions and metrics, not measured or regulated as objects themselves; linking them would conflate "citation" with "subject." |
| `person` | `person` | **No** | Objects extracted so far (metric/provision/inventory subjects) are never people; until a real producer emits `object_role` for a person, there is no node to match against, so the entry would be dead weight. Add when/if that changes. |
| relation-only endpoints, generic terms | — | **No** | These were never meant to resolve to objects (DR7's second paragraph, AD3). |

Rules:

- Lookup key is the **English side** first (`entity_type_en`), falling back to
  `entity_type` when `entity_type_en` is empty — mirroring the "detect
  language, prefer English canonical form" pattern used throughout this ADR
  (DR6 normalized names) and the entity spec's English-optimization rule.
- Matching against the allow-list is normalized the same way
  `normalizeObjectToken` normalizes `object_type` today (lowercase, trim) —
  reuse that helper rather than adding a second normalizer.
- An `entity_type` not present in the table is skipped outright — it never
  reaches candidate search. This is the actual filter DR7 asked for
  ("some entities... other entities may be concepts... that should remain
  entities only"); the table is that filter made concrete.
- The table lives as a Go map literal in code (not config, not an LLM call) —
  consistent with keeping this phase cheap and deterministic. Extend it by PR
  when a real gap is found, the same way `objectTypesCompatible`'s "other"
  wildcard is a deliberate, narrow escape hatch rather than an open one.

#### Matching and Edge Writing

> **Superseded — implemented differently.** This subsection is the original
> design (represented_by edge, transient candidate). What actually shipped
> follows the Phase 3 Amendment below instead: no bespoke edge, a real
> `kb.artifact_objects` row on a match, `object_link_status` on the miss
> paths. Left here as the historical record per this ADR's amendment
> convention; do not treat steps 3–4 below as current behavior — see
> §Phase 3 Amendment and §Code Changes (Phase 3) for what is actually in the
> repo.

For each qualifying entity (passed the type filter above):

1. Build a transient (never persisted) object-shaped candidate from the
   entity's name, `_en` name, aliases, and normalized-name bundle — reusing
   the same `ArtifactObject` struct and `NormalizedNames` convention that
   metric/provision/inventory objects use, so `ObjectNodeSQLStore.FindCandidates`
   can be called unmodified.
2. Call `FindCandidates` against the full corpus `kb.object_nodes` registry
   (matching is corpus-wide, not scoped to the entity's own record — the same
   scope `FindCandidates` already uses for artifact objects).
3. Accept only when there is a single best candidate at or above a
   high-confidence threshold (originally specced as an env var,
   `ENTITY_OBJECT_RECONCILE_MIN_SCORE` default `0.95` — **implemented as a
   hardcoded `0.95` in code, no env override**; see §Code Changes (Phase 3)).
   A tie at the top score, or a best score below the threshold, means no link
   (§Scope). Note: this does **not** call `ObjectReconciler.ReconcileOne`
   directly, despite what an earlier draft of this ADR said — `ReconcileOne`
   would call `CreateNode` on its no-match branch, which Phase 3 must never
   do. The shipped code duplicates just `ReconcileOne`'s two non-creating
   accept conditions in a small dedicated function instead.
4. On acceptance, upsert one edge:
   - `source_type = 'object'`, `source_id = kb.object_nodes.object_id`
   - `target_type = 'entity'`, `target_id = kb.entities.entity_id`
   - `relation_name = 'represented_by'`
   - `relation_method = 'object-entity-reconciliation'`
   - `confidence` = the candidate's match score
   - `extra_info` = `{"entity_type": ..., "match_method": ...}`
5. Idempotency mirrors the existing line-overlap/category edge pattern
   (`ReplaceSharedArtifactEdges`, `indexArtifactObjectConnections`): delete the
   record's existing `target_type = 'entity'`,
   `relation_method = 'object-entity-reconciliation'`,
   `relation_name = 'represented_by'` edges, then insert the fresh set, so
   reprocessing a record never leaves stale links.

Runs in `EntityRelationProcessor.PostProcessIndex` (Phase C), after
`ReindexEntitySearchForRecord` / `IndexEntityNamesForRecord`, per
[extract-entity-relation-spec.md §Index Entities]. Entity rows already exist
by Phase C, and — like all `FindCandidates` calls — this reads the corpus-wide
`kb.object_nodes` registry, so it does not need to wait on sibling processors
of the same record. **This step is unconditional** — no enable flag gates
it; it runs as part of every `PostProcessIndex` call, i.e. inline with normal
document processing (see Phase 5 §Inline vs. Scheduled, Resolved for why this
matters and what it contrasts with).

#### What "Unlinked" Means

An entity with no `represented_by` edge is not one uniform outcome. Three
different, non-equivalent things all currently produce "no edge," and they
must stay distinguishable — conflating them is exactly the mistake ADR
2026070701 found and fixed for artifact objects (a silently `NULL` `object_id`
went unnoticed for ~40 rows until someone manually audited the table; see that
ADR's Context section). The three cases here:

1. **Type-excluded** (§Entity Type → Object Type Compatibility filtered it
   out; `FindCandidates` was never called). This is **not** a claim that the
   entity "isn't an object" in any absolute sense — it is a modeling decision
   that this `entity_type` is not, corpus-wide, a reliable object candidate.
   It is stable: re-running reconciliation will not change the outcome unless
   the allow-list itself changes.
2. **Type-eligible, searched, nothing confident enough — and no node was
   created.** This is the deliberate consequence of match-only (§Scope): we
   are not unsure whether creating a node here would make sense — we are
   confident it usually would **not**, because entities carry none of the
   "this needs a subject to mean anything" evidentiary pressure DR1 relies on
   for metrics/provisions/inventory items (§DR7's expanded rationale above).
   Letting every under-matched entity mint a canonical node risks flooding
   `kb.object_nodes` with one-off, low-value entries — the same flood risk
   AD3 was rejected over, just reached by a different path.
3. **Type-eligible, tied or sub-threshold candidates — skipped per §Scope's
   ambiguous-entities decision.** This is the one case that is genuinely "not
   attempted this phase, not ruled out" — unlike (1) and (2), it is not a
   considered permanent judgment, only a deferred one.

**Observability requirement.** Each case must log distinctly (`Info`/`Debug`
is sufficient — this is not the alarm-worthy silent-`NULL` bug DR1 fixed,
since no field is left in a wrong state; it is the same "make outcomes
auditable" spirit): `"entity object-link skipped: type not eligible"`,
`"entity object-link skipped: no confident candidate"`, and `"entity
object-link skipped: ambiguous"` respectively, each carrying `entity_id` and
`entity_type`. Without this, a future "why doesn't entity X have an object"
investigation has no way to tell which of the three states applied short of
re-deriving it by hand — precisely the position ADR 2026070701's Context
section describes before DR1 existed.

#### Environment Variables

**Not implemented as specced.** Neither `ENTITY_OBJECT_RECONCILE_ENABLED` nor
`ENTITY_OBJECT_RECONCILE_MIN_SCORE` exists in code. Phase 3 has no enable
flag (it always runs inside `PostProcessIndex`) and no configurable
threshold (`0.95` / exact-match-`1.0` are hardcoded in
`matchEntityToExistingObject`, `entity_object_reconciliation.go`). This was a
simplicity tradeoff made during implementation, not a deliberate reversal of
the original design intent — if a rollout gate or tunable threshold turns out
to be needed operationally, adding both is a small follow-up, not a
redesign.

No embedding toggle either, by construction: matching goes through
`ObjectNodeStore.FindCandidates`/`ObjectReconcileOptionsFromEnv()` exactly
like every other artifact-object caller, so `OBJECT_RECONCILE_EMBEDDING_ENABLED`
already applies without Phase 3 needing its own copy.

#### Record Deletion Requirements

**Status: resolved and tested as of 2026/07/23.** This section originally
(2026/07/23, first pass) claimed `DeleteInput`
(`ChenWeb/server/api/kbhandler/metrics_handler.go`, `deleteInputRelatedRows`)
left `kb.artifact_connections` and `kb.artifact_objects` rows orphaned because
neither appeared in its delete-statement list. That claim was **wrong on the
DB-cascade half** and is corrected here rather than left standing.

What's actually true, checked against the live migrations:

- `kb.artifact_objects.input_record_id` and `.source_record_id` both carry
  `REFERENCES kb.inputs(id) ON DELETE CASCADE`
  (`20260702000002_create_kb_artifact_objects.sql`,
  `20260703000001_add_source_record_id_to_kb_artifact_objects.sql`).
- `kb.artifact_connections.source_record_id` and `.target_record_id` both
  carry the same `ON DELETE CASCADE`
  (`20260604000003_update_kb_artifact_connections_record_columns.sql`, which
  also **dropped** the table's original `input_record_id` column entirely —
  it no longer exists on this table).
- So neither table was ever actually at orphan risk at the database level;
  Postgres already removes their rows the instant the owning `kb.inputs` row
  is deleted, independent of anything `deleteInputRelatedRows` does.
- By contrast, `kb.entities`, `kb.relations`, `kb.doc_proc_logs`,
  `kb.knowledges`, `kb.semantic_projections` and most of the rest of
  `inputRelatedDeleteSpecs`' targets carry **no** FK to `kb.inputs` at all —
  for those, `deleteInputRelatedRows` is the *only* thing preventing orphans,
  which is exactly why that function matters and needs test coverage.
- `kb.object_nodes` correctly has no FK to `kb.inputs` (by design — it is
  corpus-wide canonical identity, not scoped to one record) and is correctly
  absent from `inputRelatedDeleteSpecs`.

By the time this was rechecked, `inputRelatedDeleteSpecs`
(`metrics_handler.go:1261`) already listed `kb.artifact_connections`
(`source_record_id`, `target_record_id`, and a defunct `input_record_id`
entry that `inputRelatedColumnExists` now silently skips since that column no
longer exists) and `kb.artifact_objects` (`source_record_id`,
`input_record_id`) — added independently of this ADR. Given the FK finding
above, these explicit deletes are **redundant with the existing CASCADE, not
a fix for a real orphan bug** — but harmless, and worth keeping: they make
cleanup intent explicit in application code rather than relying on an
invisible schema property, and they're a safety net for any environment where
the FK migrations haven't been applied.

The one genuine gap was **test coverage**, per the "not yet tested" note this
subsection started from. `TestDeleteInputSuccessCascadesRelatedRows` already
exercised the full `inputRelatedDeleteSpecs` list generically (it derives its
mock expectations *from* that list), so it already covered these two entries
— but only tautologically: if either entry were ever silently removed from
the list, that test would keep passing over a shorter list and prove nothing.
`TestInputRelatedDeleteSpecsCoverArtifactGraphTables`
(`metrics_handler_test.go`) closes that: it hardcodes the required
`{kb.artifact_connections, source_record_id}` /
`{kb.artifact_connections, target_record_id}` /
`{kb.artifact_objects, source_record_id}` entries independent of the list's
current contents, and separately asserts `kb.object_nodes` is never present —
guarding the "never delete canonical objects per-record" decision above from
a future silent regression. Verified RED (removed the entries, confirmed the
test fails with the expected message) before GREEN (restored them).

Phase 3's `represented_by` edges land in `kb.artifact_connections`, so they
inherit this table's existing CASCADE protection automatically — no
additional deletion work is needed for them specifically.

#### Code Changes (Phase 3)

**Status: implemented and landed 2026/07/23** (as amended — see §Phase 3
Amendment; the file list below is what actually shipped, not the original
represented_by-edge design above).

- `ChenWeb/server/api/doc-processing/entity_object_reconciliation.go` (new) —
  `entityTypeToObjectType` allow-list, `entityObjectTypeCandidate`,
  `matchEntityToExistingObject` (match-only, never calls `CreateNode` —
  enforced by a test whose stub `ObjectNodeStore.CreateNode` fails the test
  if invoked), `entityToArtifactObjectCandidate`, `ReconcileEntityObjectsForRecord`
  (orchestration), `EntityObjectSQLStore` (`LoadEntitiesForRecord`,
  `SetEntityObjectLinkStatus`).
- `ChenWeb/server/api/doc-processing/entity_object_reconciliation_test.go`,
  `entity_object_reconciliation_sql_test.go` (new)
- `ChenWeb/server/api/doc-processing/artifact_objects.go` — added
  `ArtifactObjectSQLStore.InsertOne`, a single-row insert with no preceding
  delete (unlike `ReplaceObjectsForRecord`'s per-record batch semantics) —
  needed by Phase 4's cross-record persistence, not by Phase 3 itself, but
  landed in the same file.
- `ChenWeb/server/api/doc-processing/artifact_postprocess_indexing.go` — NOT
  `extract-entity-relation.go` as an earlier draft of this ADR said. The call
  to `ReconcileEntityObjectsForRecord` was added inside
  `EntityRelationProcessor.PostProcessIndex`, right after
  `IndexEntityNamesForRecord`, non-fatal on error.
- `ChenWeb/server/api/doc-processing/search_artifact_indexing.go` — added
  `entityObjectConnectionConfig` (`artifactObjectConnectionConfig{ArtifactType:
  searchArtifactEntity, ArtifactTable: "kb.entities", ArtifactIDColumn:
  "entity_id", ...}`), and the `indexArtifactObjectConnections` call using it
  was added alongside `ReconcileEntityObjectsForRecord` in
  `artifact_postprocess_indexing.go` — this is what actually produces the
  `belong_to` edge from a matched entity's `kb.artifact_objects` row.
- `ChenWeb/project_migrations/20260723000002_add_kb_entities_object_link_status.sql`
  (new) — adds `object_link_status`, `object_link_attempts`,
  `object_link_last_attempt_at`, `object_link_fingerprint` to `kb.entities`
  (the fingerprint column belongs to Phase 4, but shipped in this one
  migration together with Phase 3's `object_link_status`).
- `ChenWeb/server/api/kbhandler/metrics_handler.go`,
  `metrics_handler_test.go` — deletion-coverage fix, already landed
  independently of Phase 3 proper (see §Record Deletion Requirements).

Verification (as actually run, all passing):

```bash
cd /Users/cding/Workspace/ChenWeb/server
go test ./api/doc-processing -run 'TestEntityObjectTypeCandidate|TestMatchEntityToExistingObject|TestReconcileEntityObjectsForRecord|TestEntityObjectSQLStore|TestArtifactObjectSQLStoreInsertOne'
go test ./api/kbhandler -run 'TestDeleteInput|TestInputRelatedDeleteSpecsCoverArtifactGraphTables'
go build ./...
go vet ./...
```

Regression check: `git stash -u` to the pre-Phase-3/4 baseline and diffed
`go test ./api/doc-processing/... ./api/kbhandler/...` failure sets before
vs. after — identical in both packages, confirming zero regressions from
this work (the ~20-ish pre-existing failures in each package, e.g.
`TestBuildEntityNameGraphConnections`, `TestListSummaryGraphSuccess`, are
unrelated and predate this ADR).

### Phase 4: LLM-Classified Entity → Object Resolution

Goal: close the two gaps Phase 3 deliberately left open — entities with no
confident match that were never given a real chance at getting an object, and
ambiguous entities that were skipped rather than adjudicated. Adds a
periodic, LLM-classified resolution pass with a three-way decision per
unlinked entity, per the side-question discussion this phase originates from.
**Chooses Fork A**: qualifying entities become a gated `kb.artifact_objects`
producer, not a permanently edge-only, never-persisted candidate.

#### Why Fork A

`ReconcileOne`, `CreateNode`, DR7's confidence-gated LLM adjudicator
(`object_ambiguous_llm.go`), its audit trail (`kb.object_audit_log`), and its
human-review admin page (DR6, ADR 2026070701) are already built, tested, and
keyed off `kb.artifact_objects` rows. Fork B (stay edge-only) would require
re-deriving parallel versions of tie-breaking, auditing, and admin review
specifically for entities. Fork A reuses all of it: once an entity is
classified as belonging with an object, it is normalized into the same
`ArtifactObject` shape metrics/provisions/inventory items already use and
persisted with `artifact_type = 'entity'`, `object_role = 'represented_entity'`
— from that point on it is indistinguishable, to every downstream system, from
a metric's object mention. This is also a better fit for DR2's own definition
of what `kb.artifact_objects` is for ("the source of truth for extracted
object mentions... with what role, evidence, line spans, confidence") than
Phase 3's transient-candidate design was.

#### Phase 3 Amendment (consequence of Fork A)

Phase 3, as originally written, deliberately never persists anything and
writes a bespoke `represented_by`/`object-entity-reconciliation` edge
directly. Once Fork A exists, that becomes the odd one out: a Phase-4-resolved
entity gets a standard `belong_to`/`object_id` edge (via the same generic
`indexArtifactObjectConnections` config metrics/provisions/inventory items
use, just with `ArtifactType: "entity"`, `ArtifactTable: "kb.entities"`,
`ArtifactIDColumn: "entity_id"`, `SourceType: "entity"`), while a
Phase-3-resolved entity would get a different edge shape, in the opposite
direction, for the same real-world relationship. Two shapes for one
relationship means every consumer has to know to check both.

Phase 3's matching step is therefore folded into the same mechanism it was
originally built to avoid, with its match-only spirit intact:

- Type-eligible entities (§Entity Type → Object Type Compatibility, unchanged)
  call `ObjectReconciler.ReconcileOne` directly — **still never `CreateNode`**;
  Phase 3's core restraint (don't let entities mint canonical nodes on a bare
  auto-match) is preserved, only the persistence target changes.
- A confident single match (`ReconcileOne`'s existing ≥1.0/≥0.95 tiers) now
  persists a real `kb.artifact_objects` row (`reconcile_status = 'matched'`)
  instead of writing a `represented_by` edge directly. Standard indexing
  produces the `belong_to` edge from there — no bespoke edge code needed.
- No match / tied / sub-threshold no longer just logs and drops (§What
  "Unlinked" Means): it sets `kb.entities.object_link_status = 'pending'`
  (new column, below) so Phase 4's classifier picks it up. This *replaces*
  the log-line-only observability requirement from §What "Unlinked" Means
  with something strictly better — a persisted, queryable status — while the
  distinct log lines stay as operational telemetry alongside it.
- Type-excluded entities get `object_link_status = 'excluded'` immediately,
  with no `ReconcileOne` call and no LLM call — the static allow-list remains
  a free, zero-cost pre-filter before anything in Phase 4 spends an LLM call.

`represented_by`/`object-entity-reconciliation` as an edge shape is retired;
existing rows of that shape (if any were written before this amendment lands)
are not migrated — Phase 4's reprocessing naturally supersedes them per
record.

#### New State on `kb.entities`

Entity↔object linking is a **third** independent status axis, distinct from
`entity_status` (provenance) and `reconcile_status` (entity↔entity dedup
lifecycle, ADR 2026061701 R2) — R2's own principle ("don't overload one
column with two state machines") applies again here, so this gets its own
columns rather than reusing either existing one:

| Column | Type | Values / Notes |
|---|---|---|
| `object_link_status` | `TEXT NOT NULL DEFAULT 'pending'` | `pending \| excluded \| linked \| deferred \| exhausted` |
| `object_link_attempts` | `INT NOT NULL DEFAULT 0` | incremented only when the classifier is actually re-invoked with materially different input — see §Fingerprint-Gated Retry. A skipped-because-unchanged pass does not increment this. |
| `object_link_last_attempt_at` | `TIMESTAMPTZ` | timestamp of the last *genuine* classification, not the last time the endpoint happened to scan this row |
| `object_link_fingerprint` | `TEXT` | hash of the exact input last sent to the classifier (entity identity signature + sorted candidate `object_id` set); the retry gate, not a display field |

State meaning, mapped to the three-way decision from the side question:

- **`excluded`** — classifier said "doesn't add value" (or the static type
  filter excluded it pre-classifier). Terminal; never revisited. Matches your
  option (1).
- **`linked`** — classifier said "should associate," and a `kb.artifact_objects`
  row now exists (whether it matched an existing node or `CreateNode` minted
  one). Terminal-success. Matches your option (2).
- **`deferred`** — classifier said "not sure." **Not** re-attempted on a
  schedule — see §Fingerprint-Gated Retry for what actually triggers a
  re-attempt. Matches your option (3).
- **`exhausted`** — was `deferred` and reached `ENTITY_OBJECT_RESOLVE_MAX_ATTEMPTS`
  *genuine* re-classifications (§Fingerprint-Gated Retry), still unresolved.
  Terminal-no-link, but distinguishable from `excluded`: this means "we tried
  with real new information N times and still couldn't decide," not "we
  decided it doesn't belong" — a future increase to the attempt cap or a
  better classifier prompt can still revisit these deliberately (e.g. a
  one-off admin action), whereas `excluded` should not be casually reopened.

Migration: `ChenWeb/project_migrations/<ts>_add_kb_entities_object_link_status.sql`,
adding the four columns plus a `CHECK` constraint on `object_link_status`.
No change needed to `kb.artifact_objects.artifact_type` or `.object_role` —
neither column carries a `CHECK` constraint in the Phase 1 migration, so
`artifact_type = 'entity'` / `object_role = 'represented_entity'` need no
schema change, only a documented convention (this table).

#### Fingerprint-Gated Retry (Why `deferred` Doesn't Mean "Poll Again")

The classifier is expected to run deterministically — same discipline as ADR
2026061701's adjudicator: temperature 0, stable input ordering, pinned prompt
version. If an entity's identity signature and its candidate `kb.object_nodes`
set are byte-identical to what was sent last time, re-invoking the LLM is not
gathering new information; it is re-asking a settled question and paying for
it again. A blind schedule- or count-driven retry (re-run every N minutes, or
every time the backfill endpoint is called) does exactly that, for every
still-`deferred` entity, every time — which is also not what this codebase's
own closest precedent actually does: DR7 of ADR 2026070701 invokes its LLM
adjudicator **once** per fresh ambiguous row; the *repeatable* backfill
endpoint (DR5) only re-runs the cheap deterministic tie-break on each
subsequent call, never the LLM again.

Phase 4 follows that precedent instead of a blind poll:

1. On each `POST /kb/entities/resolve-objects` pass, for every `deferred`
   entity selected: cheaply re-run `FindCandidates` (SQL only, no LLM) and
   recompute the input fingerprint (entity identity signature + sorted
   candidate `object_id`s).
2. If the fingerprint is unchanged from `object_link_fingerprint`, this is
   not a genuine retry — **skip. No LLM call, `object_link_attempts` and
   `object_link_last_attempt_at` untouched, status stays `deferred`.**
3. If the fingerprint changed (a new candidate node appeared — e.g. a
   metric/provision/inventory item or a later Phase-4 run created one; or the
   entity's own signature was enriched, e.g. via an ADR 2026061701 dedup merge
   unioning in new aliases/keywords onto this entity), that is a genuine new
   question: invoke the classifier, increment `object_link_attempts`, store
   the new fingerprint regardless of outcome.

This makes the corpus's actual evolution — new documents, new object nodes,
entity merges — the only thing that can move a `deferred` entity forward, not
elapsed time. `ENTITY_OBJECT_RESOLVE_MAX_ATTEMPTS` then bounds genuinely
distinct attempts, not wasted identical ones, so `exhausted` carries real
meaning: this entity was asked about under materially different conditions
`N` times and still couldn't be resolved.

Not addressed here, and not blocking: a model or prompt upgrade
(`ENTITY_OBJECT_RESOLVE_MODEL_NAME` / `ENTITY_OBJECT_RESOLVE_PROMPT` changing)
could also legitimately revisit a `deferred` or `exhausted` entity even with
an identical fingerprint. Left as a manual lever (bump
`ENTITY_OBJECT_RESOLVE_MAX_ATTEMPTS` or a one-off admin reset of
`object_link_status`) rather than folded into the fingerprint now — not worth
the added complexity until it's a real operational need.

#### Classifier Contract

One LLM call per candidate entity that clears the fingerprint gate
(§Fingerprint-Gated Retry — always true for `pending` entities, since they
have no prior fingerprint to compare against; conditional for `deferred`
entities), parallel and bounded — see below. Input:

- The entity's identity signature — the same fields ADR 2026061701's
  adjudicator uses for entity↔entity identity (`entity`/`_en`, `aliases`/`_en`,
  `entity_type`/`_en`, `desc`/`_en`, `keywords`, `categories`) — reused here
  because it is already the right "document-independent identity" input, not
  reinvented.
- Candidate `kb.object_nodes` rows from `FindCandidates` (possibly empty),
  so the classifier can distinguish "associate with an existing node" from
  "associate, but nothing exists yet — create one," the same visibility DR7
  gives its adjudicator over artifact-object ties.

Output:

```json
{
  "decision": "exclude | associate | uncertain",
  "confidence": 0.0,
  "rationale": "…",
  "selected_object_id": "…",      // set only when decision=associate and an existing candidate was chosen
  "object_type": "…",             // set only when decision=associate and no candidate matched (used for CreateNode)
  "object_role": "represented_entity"
}
```

Decision policy (mirrors DR7's confidence-gating shape):

- `decision = exclude` and `confidence ≥ ENTITY_OBJECT_RESOLVE_MIN_CONFIDENCE`
  → `object_link_status = 'excluded'`.
- `decision = associate` and `confidence ≥ ENTITY_OBJECT_RESOLVE_MIN_CONFIDENCE`
  → **implemented differently than originally specced here.** The shipped
  `linkEntityToObject` (`entity_object_resolve.go`) does **not** route through
  `reconcileArtifactObjectsWithLLM`. Reasoning added during implementation:
  that function's job is running `ReconcileOne` and then DR7's own ambiguous-
  tie LLM adjudication — but by the time `linkEntityToObject` is called, the
  Phase 4 classifier has *already* played that adjudicator role once, using
  the same candidate list. Routing through `reconcileArtifactObjectsWithLLM`
  again would stack a second LLM decision on top of the first for no benefit.
  Instead: if `selected_object_id` is set **and** present in the candidate set
  already fetched for the fingerprint (§Fingerprint-Gated Retry) — never
  trusted blindly — it's accepted directly as the match; otherwise
  `ObjectNodeStore.CreateNode` is called (using `object_type` from the
  classification, falling back to the type-filter's mapped type). Either way
  the result is persisted via `ArtifactObjectSQLStore.InsertOne` (a
  single-row insert, not `ReplaceObjectsForRecord` — Phase 4 processes
  entities across arbitrary records in one backlog pass, so a per-record
  delete-then-insert would wipe sibling rows from other records already
  resolved). `object_link_status = 'linked'` once `InsertOne` succeeds.
- Anything else (`uncertain`, or a stated `exclude`/`associate` below the
  confidence floor — mirroring DR7's "must not silently force a low-confidence
  choice") → this was a genuine attempt (the fingerprint gate already ensured
  that), so increment `object_link_attempts` and store the new
  `object_link_fingerprint`; `object_link_status = 'deferred'` if
  `object_link_attempts < ENTITY_OBJECT_RESOLVE_MAX_ATTEMPTS`, else
  `'exhausted'`.

Execution shape follows DR7 §"Prompt, confidence, execution, and
observability" directly: parallel LLM calls bounded by
`ENTITY_OBJECT_RESOLVE_CONCURRENCY` (default `5`), sequential apply, per-entity
failures captured and non-fatal, every outcome logged to `kb.doc_proc_logs`
(`entry_type = "resolve_entity_object"`) including resolved/deferred/excluded/
failed — not only failures, matching DR7's "silent gaps are the actual bug"
lesson from ADR 2026070701's own Context section.

#### Repeatable Endpoint — Now Actually Scheduled (see Phase 5)

**This section's original conclusion — "triggering it on a schedule is an
operational choice, not something this phase builds" — turned out to be
wrong in practice and was revisited.** After Phase 4 shipped, tracing actual
callers confirmed nothing invoked `/kb/entities/resolve-objects`,
`/kb/objects/resolve-ambiguous`, or `/kb/search/backfill-embeddings` on any
schedule anywhere — not in this app, not in an external crontab, not
anywhere in this repo. "An operational choice" had, in practice, meant "no
one's choice yet," for all three endpoints, indefinitely. Phase 5 below adds
an in-process scheduler and admin UI specifically to close that gap. This
subsection's mechanics (the endpoint itself) are unchanged and still accurate:

`POST /kb/entities/resolve-objects?limit=` (default `200`) — selects entities
`WHERE object_link_status IN ('pending', 'deferred')`, bounded by `limit`. For
each, applies the fingerprint gate (§Fingerprint-Gated Retry) before spending
an LLM call. Returns `{scanned, classified, skipped_unchanged, excluded,
linked, deferred, exhausted, failed}` — `skipped_unchanged` (a `deferred` row
whose fingerprint hadn't moved) is a distinct, expected outcome, not a
failure; `classified` is how many actually reached the LLM. Safe to call
repeatedly until `scanned = 0`, same operational convention as
`/kb/objects/resolve-ambiguous` and `/kb/search/backfill-embeddings`, though
here a "drained" run may still leave `deferred` rows behind — that's correct
when nothing about them has changed, not a bug.

What changed is only *what calls it*: previously nothing did; now an
optional `kb.scheduled_jobs` row can, on a user-configured interval, via
Phase 5's scheduler. The endpoint still works exactly the same when called
manually or via `curl` — Phase 5 does not require it.

#### Environment Variables

| Env var | Default | Purpose | Status |
|---|---|---|---|
| `ENTITY_OBJECT_RESOLVE_MODEL_NAME` | unset | Classifier LLM. **This is the de facto enable flag**: `NewEntityObjectClassifierFromEnv` returns a `nil` classifier (not an error) when unset, and the HTTP handler responds `503` — there is no separate `ENTITY_OBJECT_RESOLVE_ENABLED`; that variable was specced but not implemented. | Implemented (as the enable mechanism) |
| `ENTITY_OBJECT_RESOLVE_PROMPT` | `prompt-resolve-entity-object-v1.md` | Externalized prompt (never hard-coded, per ChenWeb convention). | Implemented |
| `ENTITY_OBJECT_RESOLVE_MIN_CONFIDENCE` | `0.85` | Same default as DR7's `RESOLVE_AMBIGUOUS_MIN_CONFIDENCE`, reused deliberately. | Implemented |
| `ENTITY_OBJECT_RESOLVE_MAX_ATTEMPTS` | `3` | Retry cap before `deferred` → `exhausted`. | Implemented |
| `ENTITY_OBJECT_RESOLVE_CONCURRENCY` | `5` | Specced for parallel LLM adjudication, mirroring DR7's `RESOLVE_AMBIGUOUS_OBJECT_CONCURRENCY`. | **Not implemented** — `ResolveEntityObjects` processes its scanned batch sequentially, not in parallel. Concurrency wasn't load-bearing for a first pass; can be added later without changing the store/classifier interfaces. |

#### Code Changes (Phase 4)

**Status: implemented and landed 2026/07/23.**

- `ChenWeb/project_migrations/20260723000002_add_kb_entities_object_link_status.sql`
  (new, shared with Phase 3 — see Phase 3's Code Changes) — adds
  `object_link_fingerprint` alongside Phase 3's `object_link_status` columns.
- `ChenWeb/prompts/prompt-resolve-entity-object-v1.md` (new)
- `ChenWeb/server/api/doc-processing/entity_object_resolve.go` (new) —
  `computeEntityObjectFingerprint`, `classificationTier`, `nextDeferredStatus`
  (pure, unit-tested decision logic), `ResolveEntityObjects` (orchestration),
  `linkEntityToObject` (§Classifier Contract correction above),
  `EntityObjectResolveSQLStore` (`LoadResolvable`, `MarkExcluded`,
  `MarkLinked`, `MarkAttempted`).
- `ChenWeb/server/api/doc-processing/entity_object_resolve_test.go`,
  `entity_object_resolve_sql_test.go` (new)
- `ChenWeb/server/api/doc-processing/entity_object_resolve_llm.go` (new) —
  the classifier: `entityObjectResolveContract` (structured-output schema),
  `parseEntityObjectClassification` (tolerant confidence parsing, mirroring
  DR7's qualitative-label handling), `entityObjectClassifierJSONResolver`,
  `NewEntityObjectClassifierFromEnv`. Not mentioned in the original Phase 4
  draft as a separate file — split out from `entity_object_resolve.go` to
  keep the LLM-plumbing concerns separate from the decision/orchestration
  logic.
- `ChenWeb/server/api/doc-processing/entity_object_resolve_llm_test.go` (new)
- `ChenWeb/server/api/doc-processing/artifact_objects.go` — `InsertOne` (see
  Phase 3's Code Changes; it's Phase 4 that actually needs it).
- `ChenWeb/server/api/doc-processing/entity_object_reconciliation.go` — this
  is Phase 3's file; the Phase 3 Amendment's changes to it are described
  under Phase 3's own Code Changes, not repeated here.
- `ChenWeb/server/api/doc-processing/search_artifact_indexing.go` — as
  described under Phase 3's Code Changes (the `entityObjectConnectionConfig`
  addition serves both phases; there's only one indexing call site).
- `ChenWeb/server/api/kbhandler/resolve_entity_objects_handler.go` (new) —
  `POST /kb/entities/resolve-objects` handler.
- `ChenWeb/server/api/routes.go` — registers the route.

Verification (as actually run, all passing):

```bash
cd /Users/cding/Workspace/ChenWeb/server
go test ./api/doc-processing -run 'TestResolveEntityObjects|TestClassificationTier|TestNextDeferredStatus|TestComputeEntityObjectFingerprint|TestEntityObjectResolveSQLStore|TestParseEntityObjectClassification|TestEntityObjectClassifierJSONResolver'
go build ./...
go vet ./...
```

No dedicated test file for `resolve_entity_objects_handler.go` — it's a thin
wrapper over already-tested store/classifier/orchestration functions,
matching this codebase's existing precedent for `ResolveAmbiguousObjects`'s
handler (ADR 2026070701: "the two GET handlers are thin wrappers... have no
dedicated test file").

### Phase 5: Scheduling — Inline vs. Scheduled, Resolved

**Status: implemented and landed 2026/07/23.**

#### The Gap

A direct question after Phase 4 shipped — "is entity-object resolution
inline or scheduled, and if scheduled, what actually runs it?" — led to
tracing every caller of the three repeatable backlog-drain endpoints this
ADR and ADR 2026070701 had built:

| Endpoint | Caller before Phase 5 |
|---|---|
| `/kb/entities/resolve-objects` (Phase 4) | none |
| `/kb/objects/resolve-ambiguous` (ADR 2026070701 DR5) | none |
| `/kb/search/backfill-embeddings` | none |

Confirmed by grepping `server/cmd` for each route path and handler name, and
separately checking the repo for any crontab, k8s CronJob YAML, or ops
script referencing them — none exist. This is distinct from Phase 3, which
*is* inline: its only caller is `EntityRelationProcessor.PostProcessIndex`,
which runs automatically as part of every document's processing pipeline
(§Matching and Edge Writing above). Phase 4 (and its two siblings) had no
equivalent — each was a fully-built, fully-tested capability that nothing
in the running system would ever invoke.

This is not a new problem this ADR introduced: ADR 2026061701's R6 batch
entity-dedup reconciler was designed with the same intent and never wired
into any `cmd` either. ADR 2026070701 DR5 deliberately chose "a repeatable
endpoint, not a new job runner" specifically to sidestep building (and
risking abandoning) a scheduler — but a repeatable endpoint nobody calls is
operationally identical to no endpoint at all. Phase 5 closes this rather
than letting a third capability join the same fate.

#### Decision: A Small In-Process Scheduler, Not an External Cron Requirement

Rejected alternative: document "add a cron job" as the operational
follow-up and stop there (the path ADR 2026070701 explicitly left open).
Rejected because: (1) it had already been left open twice, for two
endpoints, and stayed unfilled for as long as this codebase's history
extends; (2) it pushes a self-service capability ("I want this backlog
drained every hour") behind an ops ticket, when nothing about these jobs
requires infrastructure outside the app — they are DB-bound, idempotent,
already-bounded-by-`limit` operations; (3) this codebase already assumes
single-instance deployment for in-process coordination elsewhere (the
entity-relation spec's status-lock note: *"the status lock is an in-process
mutex. If doc-processor is ever scaled to multiple replicas, upgrade to a DB
row lock"*), so an in-process ticker is consistent with, not a new
departure from, existing operational assumptions.

Chosen: a new package, `ChenWeb/server/api/scheduler`, providing a generic
job-scheduling engine (not specific to entity-object resolution), plus a
System Admin → Schedules page for self-service schedule management. This
also retroactively closes ADR 2026070701 DR5's own "no cron" gap and the
`backfill_search_embeddings` gap — not just Phase 4's.

#### Schema

`ChenWeb/project_migrations/20260723000003_create_kb_scheduled_jobs.sql`:

- `kb.scheduled_jobs` — `id`, `name`, `job_type`, `interval_seconds`,
  `params` (JSONB), `enabled`, `next_run_at`, `last_run_at`,
  `last_run_status`. Indexed on `(enabled, next_run_at)` for the due-schedule
  scan.
- `kb.scheduled_job_runs` — `id`, `schedule_id` (FK, `ON DELETE CASCADE`),
  `job_type`, `status` (`running`/`success`/`failed`), `started_at`,
  `finished_at`, `result` (JSONB), `error`. This is the admin page's "view
  scheduled job history" data source.

#### Engine

`server/api/scheduler/scheduler.go`:

- `Registry map[string]JobDescriptor` — a job type is just a label + a
  `func(ctx, params, logger) (map[string]any, error)`. Generic; knows
  nothing about entity objects, ambiguous objects, or embeddings.
- `RunDueSchedules(ctx, store, registry, now, logger) (RunSummary, error)` —
  loads schedules due at or before `now`, runs each independently (one
  failure doesn't stop the others), records a run row for **every** attempt
  including an unregistered `job_type` (recorded as a failed run for
  observability — not silently skipped, and still rescheduled so it doesn't
  spin every tick — same "don't silently drop outcomes" principle as DR1 of
  ADR 2026070701 and §What "Unlinked" Means above).
- `StartScheduler(ctx, store, registry, tickInterval, logger)` — a
  `time.Ticker` goroutine calling `RunDueSchedules` each tick. Mirrors the
  existing `agentplatformhandler.StartWorkers` precedent in
  `cmd/deepdoc/main.go` (a background goroutine started once at process
  startup), not a new kind of process or deployment unit.
- `server/api/scheduler/scheduler_sql.go`: `SQLStore` implements the engine's
  `Store` interface plus the CRUD/history operations the admin page needs
  (`CreateSchedule`, `ListSchedules`, `UpdateSchedule`, `DeleteSchedule`,
  `ListRuns`).

All of the above is unit-tested via fakes (engine) and `sqlmock` (SQL
store) — no real DB or LLM required; see `scheduler_test.go`,
`scheduler_sql_test.go`.

#### Job Registry

`server/api/kbhandler/scheduler_jobs.go::DefaultSchedulerRegistry()` wires
the generic engine to the three concrete jobs, each calling exactly what its
corresponding HTTP handler calls (minus the HTTP envelope), so a scheduled
run and a manual endpoint call behave identically:

| `job_type` | Wraps |
|---|---|
| `resolve_entity_objects` | `docprocessing.ResolveEntityObjects` (Phase 4) |
| `resolve_ambiguous_objects` | `docprocessing.ResolveAmbiguousArtifactObjects` (ADR 2026070701 DR5) |
| `backfill_search_embeddings` | `kbsearch.BackfillEmbeddings` |

This registry-building function lives in `kbhandler`, not `scheduler`,
specifically to avoid an import cycle: `kbhandler` already depends on
`docprocessing` and `kbsearch`, and now also depends on `scheduler` for the
CRUD handlers below; `scheduler` itself stays free of both.

#### Startup Wiring

`ChenWeb/server/cmd/deepdoc/main.go` — `scheduler.StartScheduler(...)` is
called once at startup, right after the existing agent-platform workers
block. Gated by `SCHEDULER_ENABLED` (default **enabled** — unlike
agent-platform workers, which fail fast without Docker, this scheduler has
no external dependency and is a harmless idle poll with zero configured
schedules, so opt-out rather than opt-in was judged the better default).
`SCHEDULER_TICK_INTERVAL_SECONDS` controls poll frequency (default `30`).

#### Admin Page: System Admin → Schedules

New nav entry (`nav-rail.svelte`: `sysadmin-schedules` under `system-admin`,
dispatched in `content-panel.svelte` to `schedules-view.svelte`), satisfying
the three requirements this phase was asked for:

1. **Add new schedules** — a form (name, job type dropdown sourced from
   `GET /kb/schedule-job-types`, interval value + unit, a `limit` param,
   enabled toggle) posting to `POST /kb/schedules`.
2. **Shows active schedules graphically** — a card grid, one per schedule:
   interval badge, last-run-status badge (color-coded), and a progress bar
   (`progressToNextRun` in `schedules-client.ts`) showing elapsed fraction of
   the interval since the last run, ticking live via a 5s client-side
   refresh. An enable/disable toggle switch and delete action per card.
3. **Views scheduled job history** — clicking "History" on a card loads
   `GET /kb/schedules/:id/runs` into a table: started time, status, duration
   (computed from `started_at`/`finished_at`), and a flattened result/error
   summary.

`schedules-client.ts` has unit test coverage (`schedules-client.test.ts`,
`node:test` + a `fetch` mock, mirroring the established
`resolve-ambiguous-objects-client.test.ts` convention) for the fetch
wrappers, `formatInterval`, and `progressToNextRun`. The Svelte component
itself was verified via `bun run check` (0 errors, 0 warnings attributable
to any new file) but not walked through in a real browser or with
Playwright — unlike DR6 of ADR 2026070701, which did get a headless-browser
walkthrough. That gap is worth closing before relying on this page for a
real operational rollout.

#### What This Does and Doesn't Change

- Phase 3 remains inline and unconditional — Phase 5 does not touch it.
  Scheduling is specifically for the three endpoint-shaped backlog jobs.
- The endpoints themselves are unchanged; a schedule is purely an optional
  caller. Manual `curl`/Postman calls still work exactly as before.
- `kb.scheduled_jobs` with zero rows is a no-op — the ticker runs
  regardless (per `SCHEDULER_ENABLED`'s default) but has nothing to do.
- Single-instance assumption carries over unmodified from the rest of this
  codebase: running multiple `deepdoc` replicas would run multiple tickers,
  each independently deciding schedules are due and double-executing them.
  No new locking was added here beyond what already exists (or doesn't) for
  the rest of this codebase's in-process coordination.

#### Environment Variables

| Env var | Default | Purpose |
|---|---|---|
| `SCHEDULER_ENABLED` | `true` | Set `false` to disable the ticker entirely. |
| `SCHEDULER_TICK_INTERVAL_SECONDS` | `30` | Poll frequency for due schedules. |

#### Code Changes (Phase 5)

- `ChenWeb/project_migrations/20260723000003_create_kb_scheduled_jobs.sql` (new)
- `ChenWeb/server/api/scheduler/scheduler.go` (new) — engine: `Schedule`,
  `JobFunc`, `JobDescriptor`, `Registry`, `Store`, `RunSummary`,
  `RunDueSchedules`, `StartScheduler`.
- `ChenWeb/server/api/scheduler/scheduler_test.go` (new)
- `ChenWeb/server/api/scheduler/scheduler_sql.go` (new) — `SQLStore` and its
  CRUD/history methods.
- `ChenWeb/server/api/scheduler/scheduler_sql_test.go` (new)
- `ChenWeb/server/api/kbhandler/scheduler_jobs.go` (new) —
  `DefaultSchedulerRegistry` and the three job wrapper functions.
- `ChenWeb/server/api/kbhandler/schedules_handler.go` (new) — CRUD + history
  + job-types HTTP handlers.
- `ChenWeb/server/api/routes.go` — registers
  `GET /kb/schedule-job-types`, `POST /kb/schedules`, `GET /kb/schedules`,
  `PATCH /kb/schedules/:id`, `DELETE /kb/schedules/:id`,
  `GET /kb/schedules/:id/runs`.
- `ChenWeb/server/cmd/deepdoc/main.go` — starts the scheduler at startup.
- `ChenWeb/web/src/lib/components/home3/schedules-client.ts`,
  `schedules-client.test.ts` (new)
- `ChenWeb/web/src/lib/components/home3/schedules-view.svelte` (new)
- `ChenWeb/web/src/lib/components/home3/nav-rail.svelte`,
  `content-panel.svelte` — add the "Schedules" nav entry and dispatch.

Verification (as actually run, all passing):

```bash
cd /Users/cding/Workspace/ChenWeb/server
go test ./api/scheduler/...
go build ./...
go vet ./...
cd /Users/cding/Workspace/ChenWeb/web
bun test src/lib/components/home3/schedules-client.test.ts
bun run check
```

Regression check: same `git stash -u` before/after failure-set diff as
Phase 3/4 — identical in both `doc-processing` and `kbhandler`, confirming
zero regressions from adding the scheduler and its `kbhandler` wiring.

### Code Changes

Primary files:

- `ChenWeb/server/api/doc-processing/artifact_objects.go`
- `ChenWeb/server/api/doc-processing/object_nodes.go`
- `ChenWeb/server/api/doc-processing/object_reconciliation.go`
- `ChenWeb/server/api/doc-processing/extract-metrics.go`
- `ChenWeb/server/api/doc-processing/metric_search_document.go`
- `ChenWeb/server/api/doc-processing/extract-provisions.go`
- `ChenWeb/server/api/doc-processing/provision_search_document.go`
- `ChenWeb/server/api/doc-processing/extract-inventory-items.go`
- `ChenWeb/project_migrations/20260702000002_create_kb_artifact_objects.sql`
- `ChenWeb/project_migrations/20260702000003_create_kb_object_nodes.sql`
- `ChenWeb/prompts/prompt-extract-metric-candidates-v5.md`
- `ChenWeb/prompts/prompt-enrich-metrics-v3.md`
- `ChenWeb/prompts/prompt-extract-provisions-v3.md`
- `ChenWeb/prompts/prompt-extract-inventory-items-v3.md`

## Operational Behaviors 

Object extraction is part of each processor's normal extraction workflow. Object
persistence should be idempotent per record and artifact family: reprocessing a
record replaces object rows for the processor's artifact type and record, then
inserts the current normalized rows.

Object persistence failures should fail the processor if artifact rows were just
created and the objects are required for the artifact to be meaningful. Best-effort
behavior is only acceptable for optional related objects.

Object reconciliation runs after object rows are persisted. It first attempts
deterministic exact/alias/acronym/name-bundle matches, then lexical matching,
then optional vector similarity, then optional LLM adjudication. If no safe
match is found, it creates a new `kb.object_nodes` row or leaves the mention in
`pending` / `ambiguous` status depending on confidence.

When vector embeddings are disabled, reconciliation remains operational but
will produce more duplicate or pending canonical nodes. This is acceptable; a
later reconciliation run can merge canonical nodes when embeddings or better
aliases become available.

## Consequences

Positive:

- Metrics, provisions, and inventory items share one object model.
- Search and review workflows can traverse from artifacts to the objects they
  apply to without processor-specific logic.
- Existing artifact tables remain backward compatible.
- Object mentions are preserved as evidence even when canonical objects are
  merged later.
- Embeddings are optional, so the feature can run in low-resource environments.

Tradeoffs:

- Two new tables and indexing paths are required.
- Existing subject fields must be kept in sync with the primary object label.
- Prompt rollout requires new prompt files and config defaults.
- Keyword-only reconciliation has lower recall than embedding-assisted
  reconciliation and will create more duplicate or pending object nodes.
- Multilingual names, aliases, and acronyms require careful normalization and
  review workflows.

(Phase 4) Positive:

- Once linked, an entity-sourced `kb.artifact_objects` row (`artifact_type =
  'entity'`) is stored and indexed identically to a metric's or provision's
  — same table, same `belong_to` edge via the same `indexArtifactObjectConnections`
  call (§Phase 3 Amendment) — so downstream traversal/search code needs no
  entity-specific branch. **Correction from an earlier draft of this
  section:** this does *not* extend to DR7's ambiguous-resolution stack —
  `linkEntityToObject` doesn't call `reconcileArtifactObjectsWithLLM` (see
  §Classifier Contract's correction) and never writes `kb.object_audit_log`,
  so the DR6 admin page has no entity-object rows to show. If that reuse
  turns out to matter operationally, it's a real gap, not a documentation
  slip.
- Closes the two real gaps Phase 3 left open (unmatched-but-eligible,
  ambiguous-skipped) instead of leaving them as permanent dead ends.
- Unifies the edge shape for entity↔object across both phases (§Phase 3
  Amendment), so downstream consumers check one edge family, not two.

(Phase 4) Tradeoffs:

- Reintroduces some of the node-flood risk Phase 3's match-only design was
  built to avoid — entities *can* now trigger `CreateNode`. Mitigated by: the
  classifier is confidence-gated (§Classifier Contract), and an `excluded`
  verdict is permanent so a wrong "doesn't belong" call doesn't get retried
  into eventually being wrong the other way either. **Not** mitigated by
  audit logging as an earlier draft claimed — `kb.object_audit_log` is never
  written by this path (see the Positive correction above). This is a
  judgment call, not a guarantee — worth monitoring `kb.object_nodes` growth
  attributable to `artifact_type = 'entity'` rows after rollout, and worth
  adding audit logging if that monitoring surfaces a real problem.
- LLM cost scales with the unresolved-entity backlog. **Implemented as fully
  sequential** — no batching (unlike ADR 2026061701's entity-dedup
  adjudicator) and, despite this section's earlier draft claiming DR7's
  per-object-*parallel* pattern, no parallelism either
  (`ENTITY_OBJECT_RESOLVE_CONCURRENCY` was specced, not built — see Phase 4
  §Environment Variables). A large backlog will resolve slower than DR7's
  bounded-concurrency equivalent; revisit if that proves to be a bottleneck.
- `exhausted` entities are a new kind of permanent-but-not-confident state
  that downstream consumers need to understand is different from `excluded`.

(Phase 5) Positive:

- Closes an operational gap that had, in practice, existed for three
  separate endpoints (this ADR's Phase 4, ADR 2026070701's DR5, and search
  embedding backfill) — self-service scheduling from a UI instead of an
  unfilled "add a cron job" TODO.
- Generic engine: adding a fourth schedulable job later means one registry
  entry in `kbhandler/scheduler_jobs.go`, not new scheduling infrastructure.

(Phase 5) Tradeoffs:

- Single-instance assumption, undocumented as a formal constraint anywhere
  new — it inherits the same assumption already present elsewhere in this
  codebase (the entity-relation spec's in-process status-lock note) but does
  not add its own guard; multiple `deepdoc` replicas would double-execute
  due schedules.
- No end-to-end browser verification of the admin page (unlike DR6 of ADR
  2026070701, which got a Playwright walkthrough) — `bun run check` only
  confirms it type-checks.

## Tests

- Migrations create `kb.artifact_objects`, `kb.object_nodes`, and their indexes.
- Object normalization handles empty values, duplicate objects, line span
  normalization, and confidence defaults.
- Metrics synthesize objects from `subject` when the LLM omits `objects`.
- Metrics persist multiple object rows for one metric.
- Provisions synthesize objects from `subject` when needed.
- Inventory items always persist a `self` object.
- Reprocessing a record is idempotent and does not leave stale objects.
- Search documents include object text without duplicating existing artifact
  labels.
- Reconciliation links exact normalized-name matches to existing object nodes.
- Reconciliation links alias/acronym matches to existing object nodes.
- Reconciliation works with `OBJECT_RECONCILE_EMBEDDING_ENABLED=false`.
- Reconciliation uses vector similarity only when enabled.
- Ambiguous matches remain pending rather than forcing an unsafe merge.
- Object-node merges preserve original artifact-object evidence rows.
- Entity links can represent object-node evidence without treating every entity
  as an object.
- (Phase 3) Entity type filtering: entity types absent from the allow-list
  never reach candidate search (no `FindCandidates` call). Still true under
  the Phase 3 Amendment — this is the free pre-filter Phase 4 also relies on.
- (Phase 3, superseded by Phase 4's Phase 3 Amendment) ~~A single best
  candidate at or above `ENTITY_OBJECT_RECONCILE_MIN_SCORE` produces exactly
  one `represented_by` edge~~ — replaced by: a single best candidate at or
  above the match threshold persists a `kb.artifact_objects` row
  (`reconcile_status = 'matched'`), which standard indexing turns into a
  `belong_to` edge; see the Phase 4 test bullets below for the current
  behavior.
- (Phase 3, superseded) ~~This phase never creates a `kb.object_nodes` row and
  never writes a `kb.artifact_objects` row~~ — the "never creates a node"
  half still holds (Phase 3's `ReconcileOne` call never reaches `CreateNode`);
  the "never writes `kb.artifact_objects`" half no longer holds after the
  Phase 3 Amendment.
- (Phase 3) `DeleteInput` removes all `kb.artifact_connections` and
  `kb.artifact_objects` rows tied to the deleted record (both edge directions)
  while leaving referenced `kb.object_nodes` rows intact. Still true, and now
  covers Phase 3/4's entity-sourced `kb.artifact_objects` rows too — no
  change needed there, since deletion is keyed on `artifact_type`-agnostic
  columns.
- (Phase 4) A `kb.entities` row with no `represented_by`/`belong_to`
  edge always has a non-`pending` `object_link_status` explaining why —
  `excluded`, `deferred`, or `exhausted` — never silently unexplained.
- (Phase 4) `decision = associate` at or above
  `ENTITY_OBJECT_RESOLVE_MIN_CONFIDENCE` persists a `kb.artifact_objects` row
  and drives `object_link_status` to `linked` only once `reconcileArtifactObjectsWithLLM`
  resolves it to a non-empty `object_id` — a downstream ambiguous/pending
  outcome from that call must not be reported as `linked`.
- (Phase 4) `decision = exclude` below
  `ENTITY_OBJECT_RESOLVE_MIN_CONFIDENCE` is treated as `uncertain`, not as a
  low-confidence exclude — mirrors DR7's "must not silently force a
  low-confidence choice."
- (Phase 4) `object_link_attempts` increments only on a genuine
  (fingerprint-changed) `uncertain` outcome, never on `excluded` or `linked`
  — a terminal state is reached in one attempt regardless of the counter.
- (Phase 4) `object_link_status` transitions to `exhausted`, not
  back to `deferred`, exactly at `object_link_attempts == ENTITY_OBJECT_RESOLVE_MAX_ATTEMPTS`.
- (Phase 4) **Fingerprint gate — the core regression test for the
  side-question fix**: a `deferred` entity whose identity signature and
  candidate `object_id` set are unchanged since `object_link_fingerprint` was
  last stored makes **zero** LLM calls on a subsequent resolve pass, and
  leaves `object_link_attempts` / `object_link_last_attempt_at` /
  `object_link_status` all unchanged.
- (Phase 4) A `deferred` entity whose candidate set gained a new
  `object_id` (simulating a new `kb.object_nodes` row created since the last
  attempt) computes a different fingerprint and **does** trigger a fresh
  classifier call, incrementing `object_link_attempts`.
- (Phase 4) The repeatable endpoint is idempotent for unchanged
  input: a second call with the same `limit` after a first call drains
  `pending` rows and leaves untouched `deferred` rows returns `scanned = 0`
  contribution from those `deferred` rows specifically (via
  `skipped_unchanged`), not a repeated classification.
- (Phase 4) A per-entity classifier failure is captured and
  non-fatal — it does not abort the batch, matching DR7's per-object failure
  isolation. A failed attempt still counts as genuine (fingerprint differed,
  attempt was actually made) and increments `object_link_attempts`, so a
  persistently-failing entity still reaches `exhausted` rather than looping
  forever.
- (Phase 5) A due schedule (`enabled = true`, `next_run_at <= now`) is run
  exactly once per pass and its `next_run_at` advances by `interval_seconds`
  from `now`, not from the old `next_run_at` — so a scheduler that was down
  for a while does not fire a burst of catch-up runs on restart.
- (Phase 5) A schedule with an unregistered `job_type` is recorded as a
  **failed** run — not silently skipped — and is still rescheduled, so it
  neither disappears from history nor spins every tick.
- (Phase 5) Each due schedule in a batch is processed independently: one
  job's failure does not prevent the next schedule in the same pass from
  running.
- (Phase 5) `SQLStore.CreateSchedule` sets `next_run_at = NOW()`, so a newly
  created schedule is due immediately rather than waiting a full interval
  for its first run.

## Documentation Impact

- Update `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md`
  after Phase 2 to describe the shared `kb.artifact_objects` contract for doc
  processors.
- Update
  `KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-metrics-spec.md`
  in Phase 1 with the metric object schema.
- Update the provision and inventory item specs in Phase 2.
- Until Phase 2 lands, provision and inventory docs are intentionally stale with
  respect to shared object extraction.
- **Not yet done** (flagged, not completed by this ADR):
  `KnowledgeStore/Capsules/coding-capsules/doc-processor/extract-entity-relation-spec.md`
  §Index Entities still doesn't document the `belong_to` edge that Phase 3/4
  actually produce (via the standard artifact-object indexer) as an indexing
  output for entity↔object linking. This is now genuinely overdue — both
  phases are implemented and landed, not proposed — unlike the earlier
  "when Phase 4 lands" framing this bullet previously carried.
- `extract-provisions-spec.md` §3.1.5 still has the not-yet-updated gap ADR
  2026070701 flagged (ambiguous/`ambiguous_resolved` states undocumented) —
  Phase 4 adding a fourth producer (`artifact_type = 'entity'`) into the same
  `kb.artifact_objects` reconciliation path makes that follow-up more
  overdue, not less.
- **Not yet done**: no spec document exists yet for the Phase 5 scheduler
  (`server/api/scheduler`) or the System Admin → Schedules page — this ADR is
  currently the only documentation for both. Worth a short capsule doc under
  `KnowledgeStore/Capsules/coding-capsules/` if a second schedulable job type
  is added later and this ADR is no longer the natural place to look.

## References
- [1] KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md
- [2] KnowledgeStore/doc-repo/adrs/202607/2026070701-adr-object-reconciliation-ambiguous-tie-resolution.md
  — ambiguous artifact-object tie resolution (DR1-DR7); the LLM-adjudication
  pattern Phase 3 points to as a reuse path for ambiguous entities; its DR5
  ("repeatable endpoint, not a new job runner") is one of the three endpoints
  Phase 5's scheduler now actually calls.
- [3] KnowledgeStore/doc-repo/adrs/202606/2026061701-adr-entity-reconciliation.md
  — corpus-level entity↔entity reconciliation (a different axis: identity
  dedup, not entity↔object-node linking); its online path (P1) is implemented,
  its batch/periodic path (R6) is not wired into any `cmd` — the same
  never-wired fate Phase 5 was built to avoid repeating a third time.
