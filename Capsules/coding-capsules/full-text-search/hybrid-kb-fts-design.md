# Hybrid KB FTS Design

> **For agentic workers:** This design is paired with `docs/superpowers/plans/2026-05-22-hybrid-kb-fts-implementation.md` and defines a PostgreSQL full-text search architecture for Knowledge Base artifacts in ChenWeb.

**Goal:** Make summaries, topics, scene blocks, metrics, compliance provisions, and products searchable in a way that is reliable for reprocessing-heavy pipelines and optimized first for LLM/tool consumption, with a minimal `home3` test harness for human verification.

**Architecture:** Use a hybrid model: artifact-local PostgreSQL FTS on each source artifact table plus a canonical `kb.search_artifacts` registry partitioned by `artifact_type`. Each artifact family gets its own search endpoint and tool-facing response contract. Index maintenance is idempotent and record-scoped: when a document is reprocessed, search rows for that `input_record_id` and artifact type are deleted and rebuilt from source data.

**Tech Stack:** Go, Echo, PostgreSQL FTS (`tsvector`, `tsquery`, `ts_headline`, GIN, partitioning), Goose migrations, Svelte `home3`.

---

## Design Summary

- Keep artifact-aware ranking rather than forcing all artifacts into one ranking model.
- Preserve the existing metric search implementation as the first reference pattern.
- Add a canonical search registry so LLM-facing responses can converge on one normalized shape without flattening artifact semantics.
- Prefer record-scoped replace semantics over incremental index mutation for phase 1.
- Add one endpoint and one tool contract per artifact family.
- Add only a quick-and-dirty `home3` search lab for manual testing; delay polished UX.

## Artifact Scope

Phase 1 covers these artifact families:

| Artifact | Database Table |
|----------|----------------|
| `summaries` | `kb.summaries` |
| `topics` | `kb.topics` |
| `scene_blocks` | `kb.scene_objects` |
| `metrics` | `kb.metrics` |
| `provisions` | `kb.provisions` |
| `products` | `kb.products` |

These artifacts come from the document-processing pipeline described in `KnowledgeStore/Capsules/coding-capsules/doc-processor/+CAPSULE.md` and are all derived from a source document identified by `kb.inputs.id` / `input_record_id`.

## Architecture

### 1. Artifact-local Search

Each artifact type should own its searchable representation close to the source table.

- Existing reference:
  - `kb.metrics.search_document`
  - `kb.metrics.search_vector`
  - `GIN` index on `search_vector`
- Extend the same pattern, adapted per artifact schema, to:
  - summaries
  - topics
  - scene blocks
  - provisions
  - products

Artifact-local search remains the source of truth for:

- artifact-aware ranking
- artifact-specific filters
- artifact-specific snippets
- artifact-specific search APIs

### 2. Canonical Search Registry

Add a new table, logically `kb.search_artifacts`, partitioned by `artifact_type`.

Recommended core columns:

- `artifact_type TEXT NOT NULL`
- `artifact_id TEXT NOT NULL`
- `input_record_id BIGINT NOT NULL`
- `source_row_id BIGINT NULL`
- `primary_label TEXT NOT NULL`
- `secondary_label TEXT NULL`
- `search_document TEXT NOT NULL`
- `search_vector TSVECTOR NOT NULL`
- `snippet_basis TEXT NULL`
- `source_title TEXT NULL`
- `source_filename TEXT NULL`
- `category_paths JSONB NULL`
- `source_line_spans JSONB NULL`
- `semantic_payload JSONB NOT NULL DEFAULT '{}'::jsonb`
- `updated_at TIMESTAMPTZ NOT NULL DEFAULT now()`

Suggested key/indexing shape:

- partition by `LIST (artifact_type)`
- one partition per artifact family in phase 1
- unique key on `(artifact_type, artifact_id)`
- `GIN` index on `search_vector`
- btree index on `(artifact_type, input_record_id)`
- btree index on `input_record_id`

Artifact ID convention:

- `artifact_id` is the normalized, search-facing identifier for the artifact registry and APIs
- it must not be a source-native identifier such as `metric_id`, `prov_id`, or `product_rel_id`
- use the format `<record_id>_<artifact_type_code>_<seqno>`
- phase 1 artifact codes:
  - `sum` for summaries
  - `tpc` for topics
  - `sbk` for scene blocks
  - `mtc` for metrics
  - `prv` for provisions
  - `prd` for products
- examples:
  - `123_sum_1`
  - `123_mtc_4`
  - `123_prv_2`

Source-native identifiers may still be preserved in:

- source artifact tables
- file-backed artifact contents
- `semantic_payload` when useful for traceability

The registry is not meant to erase artifact-specific models. It exists to provide:

- a normalized LLM-facing search substrate
- a future base for global cross-artifact search
- a unified place to inspect indexing health and row counts

## Ranking Strategy

Do not use one universal ranking formula for all artifact families.

Recommended approach:

- keep ranking weights per artifact family
- keep parsing configuration per artifact family configurable where useful
- build snippets from the most human-meaningful content field for that artifact type

Examples:

- metrics:
  - favor names, keywords, value class, unit, and context
- summaries:
  - favor summary text, title/label, category path
- topics:
  - favor topic label, topic description, category path
- scene blocks:
  - favor scene title, scene description, participants/objects, action/context text
- provisions:
  - favor provision name, statement text, section/table context, category path
- products:
  - favor product name, canonical name, relation summary, product summary, type/category fields

## Idempotency And Sync Model

The indexing model must assume that the same document may be reparsed and regenerated multiple times.

### Phase 1 Rule

Use `record-scoped replace` semantics.

For a given `input_record_id` and artifact family:

1. persist the source artifact rows
2. delete existing search rows for that `input_record_id` and artifact type
3. rebuild search rows from the persisted source artifacts
4. insert fresh rows into:
   - the artifact-local search representation
   - the corresponding `kb.search_artifacts` partition

This applies whether the reprocessing operation regenerates:

- all artifacts for a document
- only one artifact family such as metrics
- only a subset of processor outputs

### Why This Is Preferred

- naturally idempotent
- avoids duplicate search rows
- avoids stale rows when regenerated artifact counts shrink
- easier to reason about than row-level incremental upserts
- aligns with the current document processor architecture

### Failure Handling

- source artifact persistence must succeed before search indexing runs
- if registry indexing fails after source persistence succeeds:
  - log the failure
  - return/record indexing status clearly
  - make reindexing callable later
- phase 1 does not require transactional “all artifacts + all indexes” across the full pipeline, but each artifact family’s reindex path should be internally consistent

## API Design

Add one search endpoint per artifact family:

- `GET /api/v1/kb/metrics/search`
- `GET /api/v1/kb/summaries/search`
- `GET /api/v1/kb/topics/search`
- `GET /api/v1/kb/scene-blocks/search`
- `GET /api/v1/kb/provisions/search`
- `GET /api/v1/kb/products/search`

Each endpoint should:

- require `q`
- support `page` and `page_size`
- support `input_record_id`
- support a small set of artifact-specific filters
- return a normalized search envelope

Recommended common response shape:

```json
{
  "status": true,
  "query": "energy efficiency",
  "artifact_type": "metrics",
  "page": 1,
  "page_size": 20,
  "total": 14,
  "applied_filters": {
    "input_record_id": 123
  },
    "results": [
      {
      "artifact_id": "123_mtc_4",
      "input_record_id": 123,
      "primary_label": "Energy consumption per unit output",
      "secondary_label": "kWh / unit",
      "snippet": "…",
      "score": 0.82,
      "source_title": "std_20039_opendata.pdf",
      "source_line_spans": [],
      "semantic_payload": {}
    }
  ]
}
```

Artifact-specific result structs may add richer typed fields, but the common envelope should stay stable enough for tool callers.

## Tool Design

The primary target is LLM/tool usage, not polished browser UX.

Use one tool contract per artifact family rather than one overloaded universal tool in phase 1:

- `search_metrics`
- `search_summaries`
- `search_topics`
- `search_scene_blocks`
- `search_provisions`
- `search_products`

Each tool should expose:

- `query`
- `page`
- `page_size`
- `input_record_id`
- artifact-specific filters

Each tool should return:

- `artifact_type`
- `query`
- `filters_applied`
- `total`
- `results`

Tool result rows should consistently include:

- `artifact_id`
- `input_record_id`
- `primary_label`
- `snippet`
- `score`
- `source_title` or `source_filename`
- `source_line_spans` when available
- artifact-specific semantic payload

Phase 2 may add:

- `search_all_artifacts`

That future global tool should query the registry rather than replace the per-artifact tools.

## Search Registry Population

### Source of Truth

Source artifact tables remain the authoritative records. The registry is a derived index surface.

### Rebuild Flow Per Artifact Family

Recommended helper pattern:

- `deleteSearchRegistryRowsForRecord(ctx, artifactType, inputRecordID)`
- `load<Artifact>RowsForRecord(ctx, inputRecordID)`
- `build<Artifact>SearchRows(rows)`
- `insertSearchRegistryRows(ctx, artifactType, rows)`

Analogous helpers can be used for artifact-local search columns where a table does not already have trigger-backed updates.

## Minimal `home3` Test Harness

Add a lightweight search lab in `ChenWeb::/home3`.

Goals:

- quickly test query syntax
- verify ranking/snippets
- compare artifact families
- manually validate idempotent reindex behavior after reprocessing

Non-goals:

- production-grade discovery UX
- advanced saved filters
- polished interaction design

Recommended controls:

- artifact-type selector
- query text input
- `input_record_id` filter
- a small expandable area for artifact-specific filters
- result list showing:
  - primary label
  - score
  - snippet
  - source document id/title
  - artifact id

## Testing Strategy

### Database/Migration

- verify creation of registry table, partitions, helper functions, and indexes
- verify repeated migration runs remain safe

### Handler Tests

For each artifact family:

- empty query rejected
- valid query returns stable envelope
- `input_record_id` filter works
- artifact-specific filters work
- ranking/smoke assertions on representative fixtures

### Idempotency Tests

For each artifact family:

- initial process creates expected search row count
- reprocess same `input_record_id` does not duplicate rows
- reprocess after changed artifact set removes stale rows

### UI Smoke

- minimal `home3` test panel can issue searches and render responses

## Operational Notes

- log search indexing start/end and row counts
- log deletions and inserts by `artifact_type` and `input_record_id`
- expose enough status to diagnose “artifact persisted but search stale”
- phase 1 favors correctness and explainability over maximal write efficiency

## Out Of Scope For Phase 1

- one polished global search UX
- cross-artifact blended ranking
- true incremental row-level search index updates
- semantic/vector search
- synonym dictionaries and multilingual ranking beyond current artifact needs
- registry-as-only-search-source refactor

## Recommendation

Implement the hybrid model with:

- artifact-local FTS per source artifact table
- a partitioned canonical `kb.search_artifacts` registry
- record-scoped replace indexing for idempotency
- one endpoint and one tool contract per artifact family
- one minimal `home3` search lab for testing

This gives the Knowledge Base an LLM-first search substrate without sacrificing artifact-specific relevance or creating brittle incremental indexing logic too early.
