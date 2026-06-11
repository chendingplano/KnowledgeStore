# Hybrid Search REST API Reference

- DocID: `doc-2026061104`
- **Status:** Accepted
- **Date:** 2026-06-11
- **Deciders:** Chen Ding
- **Tags:** Search Engine, Hybrid Search, REST API
- **See also:** `doc-2026060201` (hybrid search design), `doc-2026061103` (ParadeDB BM25)

## Overview

All search endpoints live under `/kb/` and share a common query interface. Depending on
server configuration the response is produced by one of three backends, transparently:

| Mode | Condition | Lexical half | Semantic half |
|---|---|---|---|
| Hybrid (ParadeDB + pgvector) | `SEARCH_SEMANTIC_ENABLED=true`, default lexical backend | BM25 via `pg_search` | pgvector cosine, fused by RRF |
| Hybrid (tsvector + pgvector) | `SEARCH_SEMANTIC_ENABLED=true`, `SEARCH_LEXICAL_BACKEND=postgres` | `tsvector` `ts_rank_cd` | pgvector cosine, fused by RRF |
| Lexical-only | `SEARCH_SEMANTIC_ENABLED` not set / query cannot be embedded / embedding error | BM25 or tsvector | — |

Each hybrid path takes up to 200 candidates from each list, fuses them with Reciprocal
Rank Fusion (k = 60), and returns a page from the fused result ordered by RRF score
descending. The `total` field is always the lexical count (see Known Limitations).

**Artifact Types**
- `topic` 
- `inventory_item` 
- `provision` 
- `scene_block` 
- `summary` 
- `metric` 
- `entity` 
- `semantic_projection` 
- `relation` 

ALl are LLM extracted from document Chunks.

---

## Endpoints

### `GET /kb/search`

Search across all artifact types simultaneously.

**Unique parameter:** `artifact_types` (CSV) — restrict to one or more types within the
all-artifacts index. If omitted, every artifact type is searched.

All other parameters are the same as the type-specific endpoints below.

---

### `GET /kb/summaries/search`

Search `summary` artifacts.

### `GET /kb/topics/search`

Search `topic` artifacts. Supports `topic_type` filter.

### `GET /kb/scene-blocks/search`

Search `scene_block` artifacts. Supports `scene_type` filter.

### `GET /kb/provisions/search`

Search `provision` artifacts. Supports `provision_type` filter.

### `GET /kb/products/search`

Search `product` artifacts. Supports `product_type` filter.

### `GET /kb/inventory-items/search`

Search `inventory_item` artifacts. Supports `item_categories`, `manufacturer`, `brand`,
`model_number`, `part_number`, `validation_status` filters.

---

## Query Parameters (registry-based endpoints)

These apply to all endpoints above except `/kb/metrics/search`.

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `q` | string | Yes | — | Search query text. Supports natural language, keywords, and CJK. |
| `page` | int | No | `1` | 1-based page number. |
| `page_size` | int | No | `20` | Results per page. Server-enforced max: `100`. |
| `input_record_id` | int64 | No | — | Restrict results to a single source record. |
| `artifact_types` | CSV string | No | — | `/kb/search` only. Comma-separated list of artifact types to include: `topic`, `inventory_item`, `provision`, `scene_block`, `summary`, `metric`, `entity`, `semantic_projection`, `relation`. |
| `category_path` | string | No | — | ILIKE filter on `category_paths`. |
| `topic_type` | string | No | — | Exact match on `semantic_payload.topic_type`. |
| `scene_type` | string | No | — | Exact match on `semantic_payload.scene_type`. |
| `provision_type` | string | No | — | Exact match on `semantic_payload.provision_type`. |
| `product_type` | string | No | — | Exact match on `semantic_payload.product_type`. |
| `relation_type` | string | No | — | Exact match on `semantic_payload.relation_type`. |
| `item_categories` | string | No | — | JSON containment filter on `semantic_payload.item_categories`. |
| `manufacturer` | string | No | — | Exact match on `semantic_payload.manufacturer`. |
| `brand` | string | No | — | Exact match on `semantic_payload.brand`. |
| `model_number` | string | No | — | Exact match on `semantic_payload.model_number`. |
| `part_number` | string | No | — | Exact match on `semantic_payload.part_number`. |
| `validation_status` | string | No | — | Exact match on `semantic_payload.validation_status`. |

Structural filters (everything except `q`) apply to **both** the lexical and semantic
candidate lists before fusion, so filtering never relaxes semantic recall.

---

## Response (registry-based endpoints)

**Success — HTTP 200**

```json
{
  "status": true,
  "query": "battery capacity",
  "artifact_type": "topic",
  "page": 1,
  "page_size": 20,
  "total": 84,
  "applied_filters": {
    "input_record_id": 42,
    "topic_type": "technical"
  },
  "results": [
    {
      "artifact_type": "topic",
      "artifact_id": "topic-00000123",
      "input_record_id": 42,
      "primary_label": "Battery Capacity Specifications",
      "secondary_label": "Power section, page 12",
      "snippet": "...nominal capacity of <b>3 000 mAh</b> at 25 °C...",
      "score": 0.0159,
      "source_title": "Product Datasheet v3",
      "source_filename": "datasheet_v3.pdf",
      "source_line_spans": [[120, 135]],
      "semantic_payload": { "topic_type": "technical" }
    }
  ]
}
```

| Field | Type | Notes |
|---|---|---|
| `status` | bool | Always `true` on 200. |
| `query` | string | Echoed query text after whitespace trim. |
| `artifact_type` | string | The effective type (`"all"` for the cross-type endpoint). |
| `page` / `page_size` | int | Echoed pagination. |
| `total` | int64 | Lexical match count. Underestimates when semantic-only hits exist. |
| `applied_filters` | object | Echoed filters; omits zero-value fields. |
| `results[].artifact_type` | string | Present except when the request already pins a single type. |
| `results[].artifact_id` | string | Stable artifact identifier. |
| `results[].input_record_id` | int64 | Source document record. |
| `results[].primary_label` | string | Human-readable artifact name. |
| `results[].secondary_label` | string | Optional subtitle; omitted when empty. |
| `results[].snippet` | string | Highlighted excerpt (HTML `<b>` tags). ParadeDB path returns raw text. |
| `results[].score` | float64 | RRF score in hybrid mode; `ts_rank_cd` / BM25 score in lexical-only mode. |
| `results[].source_title` | string | Document title; omitted when empty. |
| `results[].source_filename` | string | Original filename; omitted when empty. |
| `results[].source_line_spans` | JSON array | `[[start, end], ...]` line ranges in source; `[]` when unavailable. |
| `results[].semantic_payload` | JSON object | Artifact-type-specific metadata; `{}` when absent. |

**Error — HTTP 400**

```json
{ "status": false, "error_msg": "q is required (CWB_KB_GSR_010)" }
```

**Error — HTTP 500**

```json
{ "status": false, "error_msg": "failed to search artifacts (CWB_KB_GSR_013)" }
```

---

## `GET /kb/metrics/search`

Metrics search uses a dedicated handler with a narrower, metric-specific filter set and a
richer result structure. It is lexical-only (not wired to the hybrid path).

### Query Parameters

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `q` | string | Yes | — | Search query text. |
| `page` | int | No | `20` | 1-based page number. |
| `page_size` | int | No | `20` | Results per page. Server-enforced max: `100`. |
| `input_record_id` | int64 | No | — | Restrict to a single source record. |
| `is_explicit_metric` | bool | No | — | `true` / `false` / `1` / `0`. Filter by explicit vs. derived metrics. |
| `value_class` | string | No | — | Exact match on metric value class. |
| `value_data_type` | string | No | — | Exact match on metric data type. |
| `metric_unit` | string | No | — | Exact match on metric unit. |

### Response — HTTP 200

```json
{
  "status": true,
  "query": "output voltage",
  "artifact_type": "metric",
  "page": 1,
  "page_size": 20,
  "total": 12,
  "applied_filters": { "value_class": "electrical" },
  "results": [
    {
      "artifact_id": "metric-00000456",
      "id": 456,
      "metric_id": "m-volt-out-001",
      "input_record_id": 42,
      "input_filename": "datasheet_v3.pdf",
      "metric_name": "输出电压",
      "metric_name_en": "Output Voltage",
      "metric_subject": "电源模块",
      "metric_subject_en": "Power Module",
      "metric_value": "12",
      "metric_unit": "V",
      "metric_unit_en": "V",
      "value_class": "electrical",
      "value_class_en": "Electrical",
      "value_data_type": "numeric",
      "is_explicit_metric": true,
      "table_name_or_section": "Table 3 — Electrical Characteristics",
      "metric_keywords": ["voltage", "output"],
      "metric_keywords_en": ["voltage", "output"],
      "source_line_spans": [[88, 92]],
      "score": 0.312,
      "snippet": "...output <b>voltage</b> 12 V nominal...",
      "primary_label": "Output Voltage — Power Module"
    }
  ]
}
```

---

## `POST /kb/search/backfill-embeddings`

One-time (or on-demand) operation to populate NULL embeddings in `kb.search_artifacts`
without re-running the document pipeline. Requires `SEARCH_SEMANTIC_ENABLED=true`
(independent of the read-path flag at query time).

### Query Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `artifact_type` | string | `""` (all) | Artifact type to backfill. `""` or `"all"` processes every type. |
| `limit` | int | `200` | Maximum rows to process per call. Call repeatedly until `remaining = 0`. |
| `reembed_all` | bool | `false` | `true` = recompute embeddings even for rows that already have one. |

### Response — HTTP 200

```json
{
  "scanned": 200,
  "embedded": 195,
  "skipped": 3,
  "failed": 2,
  "remaining": 1450
}
```

| Field | Meaning |
|---|---|
| `scanned` | Rows read in this call. |
| `embedded` | Rows successfully updated with a new embedding. |
| `skipped` | Rows with empty text (no embeddable content). |
| `failed` | Per-row embedding API errors (logged; row left lexical-only). |
| `remaining` | Estimated rows still needing embeddings after this call. |

---

## Known Limitations

- **`total` undercounts** hybrid results. It is computed from the lexical path only, so
  artifacts surfaced exclusively by semantic similarity are not reflected in the count.
- **Snippet highlighting** is `ts_headline` HTML on the Postgres lexical path; the
  ParadeDB path returns raw `snippet_basis` / `search_document` text without markup.
- Metrics search (`/kb/metrics/search`) is lexical-only regardless of
  `SEARCH_SEMANTIC_ENABLED`.

## Files

| Concern | File |
|---|---|
| Route registration | `ChenWeb/server/api/routes.go` |
| Registry handlers (all types) | `ChenWeb/server/api/kbhandler/summary_search_handler.go` |
| Metric handler | `ChenWeb/server/api/kbhandler/metric_search_handler.go` |
| Inventory item handler | `ChenWeb/server/api/kbhandler/inventory_items_handler.go` |
| Shared search logic + hybrid query | `ChenWeb/server/api/kbhandler/search_registry.go` |
| Common types (`artifactSearchFilters`, `artifactSearchResult`) | `ChenWeb/server/api/kbhandler/search_common.go` |
| Backfill handler | `ChenWeb/server/api/kbhandler/backfill_embeddings_handler.go` |
| Page size / dictionary config | `ChenWeb/server/cmd/config/config.go` |
