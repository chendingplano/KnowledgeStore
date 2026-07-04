# Object-Centric Design Implementation

**Date:** 2026-07-04 \
**Status:** Draft \
**Component:** ChenWeb \
**Authors**: Chen Ding \

## Change Logs
* 2026/07/04, Document created

## Purpose

This document explains the current implementation of the object-centric design
introduced by ADR 2026070101, with emphasis on what is already implemented in
code today, what is only described in the ADR, and what remains unresolved.

The main code paths are:

- `ChenWeb/server/api/doc-processing/artifact_objects.go`
- `ChenWeb/server/api/doc-processing/object_nodes.go`
- `ChenWeb/server/api/doc-processing/extract-metrics.go`
- `ChenWeb/server/api/doc-processing/extract-provisions.go`
- `ChenWeb/server/api/doc-processing/extract-inventory-items.go`
- `ChenWeb/server/api/doc-processing/artifact_object_connection_indexing.go`

The main tables are:

- `kb.artifact_objects`
- `kb.object_nodes`
- `kb.artifact_connections`

## Summary

The implementation currently has a two-layer model:

1. `kb.artifact_objects`
   - Stores object mentions extracted from artifacts.
   - This is the evidence layer.
2. `kb.object_nodes`
   - Stores canonical object identities used across artifacts.
   - This is the canonical layer.

The current pipeline is:

```text
artifact row
  -> identify artifact objects
  -> normalize ArtifactObject structs
  -> reconcile each ArtifactObject to kb.object_nodes
  -> create a new object node if no acceptable match exists
  -> persist reconciled ArtifactObject rows into kb.artifact_objects
  -> create belong_to object-node edges in kb.artifact_connections
```

An important implementation detail is that reconciliation happens in memory
before `kb.artifact_objects` rows are written. The final persisted
`kb.artifact_objects` rows already carry `object_id`, `reconcile_status`, and
`reconcile_confidence`.

## Data Model

### `kb.artifact_objects`

`kb.artifact_objects` stores the object mention as extracted or synthesized from
an artifact instance.

Important fields:

- `input_record_id`
- `artifact_type`
- `artifact_id`
- `object_id`
- `object_name`
- `object_name_en`
- `object_name_zh`
- `language`
- `object_type`
- `object_role`
- `aliases`
- `acronyms`
- `normalized_names`
- `description`
- `evidence_quote`
- `source_line_spans`
- `confidence`
- `reconcile_status`
- `reconcile_confidence`

This table is replaced per record + artifact type by
`ArtifactObjectSQLStore.ReplaceObjectsForRecord(...)`.

### `kb.object_nodes`

`kb.object_nodes` stores the canonical object identity selected or created by
reconciliation.

Important fields:

- `object_id`
- `canonical_object_id`
- `canonical_name`
- `canonical_name_en`
- `canonical_name_zh`
- `primary_language`
- `object_type`
- `aliases`
- `acronyms`
- `normalized_names`
- `description`
- `search_document`
- `reconcile_status`

New nodes are created by `ObjectNodeSQLStore.CreateNode(...)`.

## Pipeline

### 1. An artifact identifies one or more object mentions

The artifact processors currently participating in this flow are:

- metrics
- provisions
- inventory items

Each processor gathers object mentions from the artifact payload and converts
them into `ArtifactObject` structs using
`normalizeArtifactObjectsForArtifact(...)`.

Processor entry points:

- `MetricsProcessor.persistMetricObjects(...)`
- `ProvisionsProcessor.persistProvisionObjects(...)`
- `InventoryItemsProcessor.persistInventoryItemObjects(...)`

### 2. Artifact objects are normalized

`normalizeArtifactObjectsForArtifact(...)` does the following:

- reads `artifact["objects"]` if present;
- synthesizes fallback objects when needed;
- deduplicates objects within the same artifact mention set;
- normalizes names, roles, types, confidence, and line spans.

Normalization details:

- `ObjectName`, `ObjectNameEn`, and `ObjectNameZh` are trimmed.
- If `ObjectName` is empty, it falls back to `ObjectNameZh`, then
  `ObjectNameEn`.
- `ObjectRole` defaults by artifact family:
  - metric -> `measured_object`
  - provision -> `regulated_object`
  - inventory item -> `self`
- `ObjectType` defaults to `other`.
- `NormalizedNames` are built from:
  - `object_name`
  - `object_name_en`
  - `object_name_zh`
  - aliases
  - acronyms
  - any extra supplied normalized names

Object dedup inside one artifact uses `normalizedObjectIdentityKey(...)`, which
is based on:

- `artifact_type`
- `artifact_id`
- first normalized name
- `object_role`

This means dedup is local to one artifact occurrence. It is not a global object
identity rule.

### 3. Reconcile each artifact object to `kb.object_nodes`

Each normalized `ArtifactObject` is passed to
`ObjectReconciler.ReconcileOne(...)`.

That function:

1. asks the object-node store for candidates;
2. accepts an exact or high-confidence candidate when possible;
3. marks ambiguous cases when the top scores tie;
4. creates a new object node when no safe match exists.

### 4. Create a new object node if needed

If no acceptable candidate exists, `ObjectNodeSQLStore.CreateNode(...)` creates
a new canonical node.

The node is initialized from the artifact object:

- canonical name from first non-empty of source / zh / en name
- `canonical_name_en` from object mention
- `canonical_name_zh` from object mention
- `primary_language` from mention language
- `object_type` from mention type
- aliases and acronyms copied from mention
- normalized names copied from mention
- `search_document` built from names, aliases, acronyms, type, role,
  description, and evidence quote
- `reconcile_status = 'active'`

### 5. Persist reconciled artifact objects

After reconciliation, the processors call
`ArtifactObjectSQLStore.ReplaceObjectsForRecord(...)`.

That function:

1. starts a transaction;
2. deletes previous `kb.artifact_objects` rows for
   `(source_record_id, artifact_type)`;
3. inserts the current reconciled rows;
4. commits.

The persisted rows already contain:

- `object_id`
- `reconcile_status`
- `reconcile_confidence`
- `ext_info["reconcile_method"]`

### 6. Create object-node connections

After artifact rows and object rows exist, indexing creates edges in
`kb.artifact_connections` using `indexArtifactObjectConnections(...)`.

This joins:

- the artifact table row
- `kb.artifact_objects`
- `kb.object_nodes`

and creates `belong_to` edges to target type `object_node`.

This is what later object-centric search and review flows traverse.

## How Artifact Objects Are Identified

### Current behavior

"Identify artifact objects" currently means: determine what object mentions an
artifact refers to, so those mentions can be normalized into `ArtifactObject`
rows.

This happens in two ways:

1. Explicit object extraction
   - If the artifact payload already has an `objects` array, use it.
2. Synthesis fallback
   - If the `objects` array is absent or empty, synthesize from legacy subject
     fields.

### By artifact family

#### Metrics

Metrics use explicit `objects` when present. Otherwise a single fallback object
is synthesized from:

- `subject`
- `metric_subject`
- `subject_en`
- `metric_subject_en`

Default role:

- `measured_object`

#### Provisions

Provisions use explicit `objects` when present. Otherwise a single fallback
object is synthesized from:

- `subject`
- `provision_subject`
- `subject_en`
- `provision_subject_en`

Default role:

- `regulated_object`

#### Inventory items

Inventory items always synthesize a `self` object from:

- `canonical_name`
- `item_name`
- `item_categories`
- `aliases`

Then any explicit extra `objects` are appended after that `self` object.

Default role:

- `self`

### What this means in practice

The implementation does not currently run a separate "artifact object
identifier" subsystem. Identification is embedded directly inside each artifact
processor through:

- explicit extracted `objects`
- fallback synthesis from known artifact fields

## How Artifact Objects Are Reconciled to Object Nodes

### Candidate lookup

`ObjectNodeSQLStore.FindCandidates(...)` queries `kb.object_nodes` by:

- `normalized_names ?| $1`
- exact `canonical_name = obj.ObjectName`
- exact `canonical_name_en = obj.ObjectName`
- exact `canonical_name_zh = obj.ObjectName`

It excludes nodes with `reconcile_status = 'rejected'`.

Candidates are ordered by:

- object-type compatibility first
- then row `id`

### Candidate scoring

The current implementation has only two real score levels:

- `1.0`, method `exact_name`
  - object types are compatible
  - normalized name bundles overlap
- `0.85`, method `lexical_name`
  - candidate exists from lexical query
  - but full exact normalized bundle overlap did not prove identity

### Decision logic

`ObjectReconciler.ReconcileOne(...)` currently behaves as follows:

1. If there is exactly one candidate with score `>= 1`, match it.
2. If there are multiple candidates and the top two scores are equal, mark the
   result `ambiguous`.
3. If there is any candidate with score `>= 0.95`, match it.
4. Otherwise create a new node.

Because the implemented scores are basically `1.0` and `0.85`, this means:

- exact normalized-name overlap with compatible type matches;
- a top-tie among equally scored candidates becomes ambiguous;
- lexical-only `0.85` matches do not match and instead create a new node.

### What is not implemented yet

The ADR describes a richer reconciliation ladder:

- exact / alias / acronym / name-bundle
- lexical
- optional vector similarity
- optional LLM adjudication

The current code does **not** implement the full ladder.

Specifically, it does **not** currently do:

- vector similarity scoring
- embedding-based candidate acceptance
- LLM adjudication
- post-hoc merge of two existing object nodes

The environment variable `OBJECT_RECONCILE_EMBEDDING_ENABLED` exists, but
current reconciliation logic does not use embeddings in scoring or matching.

## How Object Nodes Are Identified

### Current behavior

"Identify object nodes" currently means: choose or create the canonical
`kb.object_nodes` row that an artifact object should point to.

This is done by:

1. lexical candidate lookup using normalized names and canonical names;
2. compatible-type filtering through scoring;
3. create-on-miss.

### Canonical identity rule today

The real implemented identity heuristic is:

- same or compatible object type, and
- overlapping normalized names

This is a practical lexical identity rule, not a strong semantic identity rule.

### Consequence

Today, object-node identity is only partially canonical:

- strong exact lexical matches are reused;
- weaker or cross-language equivalents often become separate nodes;
- ambiguous exact collisions are not resolved automatically.

## Alias Handling

### What is handled

Aliases are carried from artifact-object extraction into both:

- `kb.artifact_objects.aliases`
- `kb.object_nodes.aliases`

They also contribute to `normalized_names`, because
`buildObjectNormalizedNames(...)` normalizes aliases and includes them in the
name bundle.

When a new object node is created, its aliases are copied from the artifact
object.

When `CreateNode(...)` hits an existing `object_id` conflict, it merges:

- normalized names
- aliases
- acronyms

### What is not handled

The current implementation does **not** have a separate alias-reconciliation
workflow for object nodes.

It does not:

- discover new aliases from later matched mentions and update an existing node
  by alias absorption;
- maintain alias conflict logs for object nodes;
- decide that two nodes are the same because one node's alias semantically
  matches another node's canonical name beyond normalized-name overlap.

So aliases are used mainly as part of the lexical name bundle at create and
lookup time, not as an actively managed identity graph.

## Multilingual Names

### What is handled

The schema and normalization code explicitly support:

- `object_name`
- `object_name_en`
- `object_name_zh`
- `language`

`buildObjectNormalizedNames(...)` includes all three name fields, so if the same
node already contains both Chinese and English names, later mentions in either
language can match through normalized-name overlap.

`CreateNode(...)` also stores:

- `canonical_name`
- `canonical_name_en`
- `canonical_name_zh`
- `primary_language`

### What is only partially handled

Multilingual handling is lexical, not translation-based.

The implementation does not currently:

- translate Chinese names to English;
- infer that two names in different languages are equivalent unless both forms
  are already present in the normalized bundle;
- use bilingual dictionaries or embeddings to bridge languages.

### Practical consequence

If one artifact object says:

- `object_name = 调压器`

and another says:

- `object_name_en = pressure regulator`

they will only reconcile to the same node if some shared normalized name or
stored bilingual field already connects them.

Otherwise they will likely become separate object nodes.

## Outstanding Issues

### 1. Reconciliation order differs from the ADR wording

The ADR text says reconciliation runs after object rows are persisted, but the
current processors reconcile first and persist the reconciled rows afterward.

That is not necessarily wrong, but the implementation document should treat the
code as source of truth for current behavior.

### 2. `OBJECT_RECONCILE_EMBEDDING_ENABLED` exists but is effectively unused

The option is parsed, and `kb.object_nodes` has an `embedding` column, but
current reconciliation code does not compute or compare embeddings.

So the system is presently lexical-only.

### 3. No LLM adjudication path exists yet

The ADR allows optional LLM adjudication for ambiguous cases, but current code
simply returns `ambiguous` when top candidates tie.

### 4. No object-node merge workflow is implemented here

The code creates nodes and reuses exact lexical matches, but it does not
implement canonical merge or survivor/redirection logic between two existing
object nodes.

Fields such as `canonical_object_id` exist, but this document does not find an
active merge path in the current object-node code.

### 5. Ambiguous artifact objects are persisted without `object_id`

If reconciliation returns `ambiguous`, the artifact object is persisted with:

- `reconcile_status = ambiguous`
- no linked `object_id`

That is safe, but it means downstream logic must tolerate unlinked object
mentions.

### 6. Cross-language duplicates are likely

Because multilingual handling is lexical and not translation-based, Chinese and
English names for the same real object may become different nodes unless the
artifact mention already provides both forms or shared aliases.

### 7. Alias management is passive

Aliases are stored and normalized, but there is no active alias-learning or
alias-conflict subsystem for object nodes comparable to artifact categories.

### 8. `source_record_id` naming is slightly inconsistent

In Go structs the field is `SourceRecordID`; in some ADR text the discussion
sometimes refers to `input_record_id`. The actual migration contains both
`input_record_id` and record-scoped replacement behavior based on
`source_record_id` in the Go code path.

That duality should stay explicit in future docs to avoid confusion.

### 9. Global object identity is still weak

The current implementation is sufficient for:

- preserving object evidence per artifact;
- linking obvious repeated names to one node;
- building object-centric graph edges.

It is not yet sufficient for strong global object identity across:

- languages
- paraphrases
- abbreviations not already supplied as aliases
- near-duplicate descriptions

## What Is Implemented Today vs. Planned

### Implemented today

- shared `kb.artifact_objects` table
- shared `kb.object_nodes` table
- object normalization for metrics, provisions, and inventory items
- fallback synthesis from subject-style fields
- lexical normalized-name reconciliation
- create-on-miss object nodes
- persistence of reconciled object mentions
- artifact-to-object-node graph connections

### Planned or implied by ADR but not fully implemented

- embedding-based reconciliation
- LLM adjudication
- stronger multilingual reconciliation
- node merge / survivor workflows
- richer alias management

## References

- `KnowledgeStore/doc-repo/adrs/202607/2026070101-adr-object-centric-design.md`
- `ChenWeb/server/api/doc-processing/artifact_objects.go`
- `ChenWeb/server/api/doc-processing/object_nodes.go`
- `ChenWeb/server/api/doc-processing/artifact_object_connection_indexing.go`
- `ChenWeb/project_migrations/20260702000002_create_kb_artifact_objects.sql`
- `ChenWeb/project_migrations/20260702000003_create_kb_object_nodes.sql`
