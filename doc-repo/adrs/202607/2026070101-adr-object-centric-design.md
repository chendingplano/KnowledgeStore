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

## References
- [1] KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md
