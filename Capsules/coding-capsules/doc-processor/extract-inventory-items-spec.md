# Extract Inventory Items Processor — Spec

A configurable doc processor that uses an LLM to extract **inventory-relevant item records** from chunked document input, then normalizes and validates them into `kb.inventory_items`.

This processor is document-focused. It reads `.chunks` artifacts directly and does **not** depend on `kb.products`.

It is also intentionally distinct from:

- [`extract-entity-relation`](extract-entity-relation-spec.md), which emits general entity and relation graph units
- `extract_provisions`, which emits rule / requirement / obligation semantics

This processor emits **item objects**: parts, equipment, materials, systems, consumables, software assets, and other inventory-like things that can be purchased, stored, installed, maintained, inspected, replaced, or matched.

## Inputs

- `record_id`: the value of `kb.inputs.id`
- chunks loaded from `ARTIFACT_DIR/<group_id>/<record_id>/<filename_root>_<parser_name>.chunks`
- input line file under `ARTIFACT_DIR` (used to resolve chunk bodies before loading chunk artifacts)

Like `extract_entity_relation`, this processor uses chunked input rather than block output.

## Environment Variables

| Name | Required | Purpose |
|---|---|---|
| `EXTRACT_INVENTORY_ITEMS_MODEL_NAME` | yes | Primary LLM model reference |
| `EXTRACT_INVENTORY_ITEMS_FALLBACK` | optional | Fallback LLM model reference for chunk retries |
| `EXTRACT_INVENTORY_ITEMS_PROMPT` | optional | Prompt file ref. Defaults to `prompt-extract-inventory-items-v1.md` |
| `EXTRACT_INTENTORY_ITEMS_MAX_TASKS` | optional | Max concurrent chunk extractions. Defaults to `1` (sequential). |
| `INVENTORY_ITEMS_DICTIONARY_DIR` | optional | Override directory for the seed dictionary JSON files |
| `INVENTORY_CATEGORY_EMBEDDING_MODEL_NAME` | optional | Embedding model for fuzzy category matching. When set, enables synonym merge during curation. |
| `INVENTORY_CATEGORY_FUZZY_THRESHOLD` | optional | Cosine similarity threshold for category synonym matching. Default `0.86`. |
| `ARTIFACT_DIR` | yes | Root artifact directory where `.chunks` and `.inventory_items` live |
| `MODEL_DEF_FILE` | yes | Model registry used by the shared model loader |

If the primary model config fails to load, the processor records a `failed` status entry and returns. The rest of the pipeline continues.

## Concurrency

Chunks may be processed concurrently, capped by `EXTRACT_INTENTORY_ITEMS_MAX_TASKS`. The default is `1` (sequential). Individual chunk LLM failures are logged and skipped; they do not fail the run. Only a user-requested pipeline stop cancels remaining chunk work.

## Single-Pass Per Chunk

For each chunk, this processor makes **one LLM call** using `prompt-extract-inventory-items-v1.md`.

The prompt returns strict JSON:

```json
{
  "language": "en",
  "items": [
    {
      "item_name": "Bosch Pump 1500W",
      "canonical_name": "Bosch pump",
      "item_category": "pump",
      "manufacturer": "Bosch",
      "brand": "Bosch",
      "model_number": "",
      "part_number": "",
      "raw_specs": [
        { "name": "power", "value": 1500, "unit": "w" }
      ],
      "standards": [],
      "aliases": [],
      "evidence_quote": "Bosch Pump 1500W",
      "lines": ["42"],
      "confidence": 0.91,
      "confidence_reason": "explicit mention"
    }
  ]
}
```

Overlap lines (`flag = "o"`) are context only. The prompt instructs the model not to emit an item whose evidence depends only on overlap lines.

## Go-Side Normalization

The LLM output is only the first pass. The Go processor performs deterministic normalization before persistence:

- normalize `item_category`
- normalize spec names using category schemas
- normalize units using dictionary conversion rules
- build `normalized_specs`
- compute `missing_required_attrs`
- compute `validation_flags`
- compute stable `dedupe_key`
- assign `inventory_item_id = <record_id>_i_<seqno>`

This is an important design point: the LLM proposes candidate item attributes, but the system-owned normalization and validation logic lives in Go.

## Category Ontology — Two Layers

The category system has two distinct layers that must not be confused.

### Layer 1 — Ontology (schema): `kb.inventory_categories`

**Defines the controlled vocabulary of item types.** Each row represents a category like `pump`, `bearing`, or `medical_device`. This table is bounded — dozens to low hundreds of rows — and grows only when genuinely new item types are encountered in the corpus, not with every extracted item.

The schema is now DB-backed (not file-only). `kb.inventory_categories` is the live registry. On startup, the processor seeds the curated dictionary files (below) as `approved` entries. From then on, the DB is the source of truth.

Each category row carries:

| Column | Purpose |
|---|---|
| `category_key` | normalized key, e.g. `medical_device` |
| `status` | `pending_review` / `approved` / `rejected` / `merged` |
| `canonical_of` | if merged, points to the surviving key |
| `display_names` | every surface form ever seen (e.g. `["medical_device", "医疗器械"]`) |
| `required_attrs` | required spec attribute names for this category |
| `specs` | spec definitions: canonical name, unit, aliases |
| `plausible_ranges` | numeric sanity bounds per spec |
| `embedding` | optional: enables cosine-similarity synonym matching |
| `seen_count` | how many item instances have been extracted under this category |

### Layer 2 — Instances: `kb.inventory_items`

**The extracted items themselves.** 理疗仪, 检查床, 血压计 are rows here. This table grows with every document and can hold hundreds of thousands to millions of rows. Instances are never added back to the ontology layer. The instance carries the `item_category` key (e.g. `medical_device`), not a full schema copy.

### Why this separation matters

```
理疗仪, 检查床, 血压计 → rows in kb.inventory_items     (data — millions of rows OK)
pump, bearing, medical_device → rows in kb.inventory_categories  (ontology — bounded)
```

Adding a new document adds zero ontology rows as long as its item types are already known. A new category row is only minted when the corpus produces an item type the ontology has never seen.

## Seed Dictionary Files

The curated ontology starts from versioned JSON files in:

```text
ChenWeb/config/inventory_items/
```

Current files:

- `category_schemas.json`
- `units.json`
- `aliases.json`
- `standards.json`
- `plausible_ranges.json`

These seed data are loaded once at processor startup and upserted into `kb.inventory_categories` as `approved` entries. Going forward the DB is the source of truth; the JSON files serve as version-controlled seed / export.

## Automatic Category Admission (Post-Pass)

After each document's items are saved, the processor runs a **post-pass curation step** to admit novel `item_category` values into the registry. This step is best-effort — a failure does not fail the document.

**Match-before-mint in three tiers:**

1. **Exact key match** — normalized surface form already in the registry → increment `seen_count`, append display name. No new row.
2. **Display-name / alias match** — surface form matches any known `display_names` entry → fold into that category. No new row.
3. **Embedding cosine match** (if `INVENTORY_CATEGORY_EMBEDDING_MODEL_NAME` is set) — cosine similarity ≥ `INVENTORY_CATEGORY_FUZZY_THRESHOLD` → treated as synonym of the best-matching category. No new row.
4. **Miss all tiers** → mint a new `pending_review` row, `seen_count = 1`.

The curation pass is batched per document and builds an intra-document snapshot for convergence: a category minted early in a document is matchable by later surface forms in the same pass.

## Reload Boundary

At the start of each document's `HandleEvent`, the processor:

1. **Seeds** the curated dictionary into `kb.inventory_categories` (once per processor lifetime, idempotent).
2. **Merges** all active categories (approved ∪ pending_review) from the registry into the in-memory dictionary.

This means a category admitted from a previous document — even if still `pending_review` — becomes known vocabulary for the current document's LLM prompt, and the model converges on it instead of re-inventing synonyms.

## Category Review

A `pending_review` category has been observed in the corpus but has not yet been curated by a human. Its schema body (`required_attrs`, `specs`, `plausible_ranges`) is empty.

**Pending categories are treated as valid vocabulary during extraction** — items are extracted and stored normally — but instances of unreviewed categories carry `category_status: pending_review` in the read/search path.

Review workflow:

1. Query `GET /api/v1/kb/inventory-categories?status=pending_review` — returns pending categories ordered by `seen_count` descending (highest-impact first).
2. Reviewer fills in `required_attrs`, `specs`, `plausible_ranges`.
3. Reviewer approves (`PATCH /api/v1/kb/inventory-categories/:key { "status": "approved" }`), rejects, or merges into an existing category.
4. On approval, the status change propagates immediately to the read path for all existing instances (no row rewrite needed — status is derived by join at read time).

**Review does not require a reprocess** to take effect on existing items for `category_status`. However, spec normalization and required-attr validation are only run at extraction time, so early instances may have gaps that a forced reprocess would correct.

## Output Row Shape

Each extracted item is normalized into a row with these main fields:

| Field | Type | Notes |
|---|---|---|
| `inventory_item_id` | text | `<record_id>_i_<seqno>` |
| `input_record_id` | bigint | source `kb.inputs.id` |
| `language` | text | detected input language |
| `item_name` | text | source-language item string |
| `canonical_name` | text | normalized display name; falls back to `item_name` |
| `item_category` | text | normalized category key such as `pump`, `bearing`, `medical_device` |
| `manufacturer` | text | manufacturer name if present |
| `brand` | text | brand if present |
| `model_number` | text | model number if present |
| `part_number` | text | part number if present |
| `normalized_specs` | jsonb | canonical spec name/value/unit array |
| `raw_specs` | jsonb | original extracted spec array |
| `standards` | jsonb | extracted standards array |
| `aliases` | jsonb | extracted aliases array |
| `evidence_quote` | text | short exact supporting quote |
| `source_line_spans` | jsonb | array of source line spans such as `"12"` or `"13-15"` |
| `validation_flags` | jsonb | flags such as `missing_required_attrs`, `low_confidence`, `unknown_category`, `implausible_power` |
| `missing_required_attrs` | jsonb | category-required attrs not present in the row/specs |
| `dedupe_key` | text | deterministic dedupe key built from category, maker, ids, and normalized specs |
| `schema_version` | text | currently `"1"` |
| `dictionary_version` | text | loaded dictionary version |
| `confidence` | double | model confidence |
| `confidence_reason` | text | model rationale |
| `model_name` | text | model used |
| `prompt_name` | text | prompt ref |
| `search_document` | text | maintained by trigger |
| `search_vector` | tsvector | maintained by trigger |
| `ext_info` | jsonb | includes language, schema version, and `chunk_seq_no` |

## Validation Flags

The current Go normalization layer can emit:

- `unknown_category` — the item's `item_category` was not in the curated ontology at extraction time (including pending_review categories if the post-pass runs after extraction)
- `missing_required_attrs`
- `low_confidence`
- `missing_source_lines`
- `implausible_<spec_name>`

The processor does not reject rows because of these flags. It persists them and exposes them to search / API consumers.

### `category_status` (read path, not a stored flag)

At read time (search registry build, API response), each item exposes a `category_status` derived by joining `kb.inventory_categories`:

- `approved` — category is curated and stable
- `pending_review` — category exists but has not been reviewed
- `rejected` — category was rejected (item should be re-extracted or discarded)

This field is **not stored on the item row**. It reflects the registry's current state at read time, so approving a category immediately surfaces as `approved` on all existing instances with no row rewrite.

## Tables

Primary table:

- `kb.inventory_items` — extracted item instances

Category ontology registry:

- `kb.inventory_categories` — controlled vocabulary with review lifecycle

Search registry partition:

- `kb.search_artifacts_inventory_item` with `artifact_type = 'inventory_item'`

The items migration also creates:

- `kb.inventory_item_search_document(...)`
- `kb.refresh_inventory_item_search_columns()`
- trigger `trg_refresh_inventory_item_search_columns`

This follows the same search-registry pattern used by summaries, topics, provisions, entities, and relations.

## Artifact File

For each processed record, write:

```text
ARTIFACT_DIR/<group_id>/<record_id>/<filename_root>_<parser_name>.inventory_items
```

File format: pretty-printed JSON array of the normalized item rows.

## APIs

### List items for a record

```text
GET /api/v1/kb/inventory-items?input_record_id=N
```

Returns the persisted inventory item rows for a single `kb.inputs` record.

### Search inventory items

```text
GET /api/v1/kb/inventory-items/search?q=...
```

Supported filters:

- `input_record_id`
- `item_category`
- `manufacturer`
- `brand`
- `model_number`
- `part_number`
- `validation_status`

Search uses the shared registry search path and returns `artifact_type = "inventory_item"`.

### List pending categories for review

```text
GET /api/v1/kb/inventory-categories?status=pending_review&limit=N
```

Returns pending categories ordered by `seen_count` descending.

### Update a category (approve / reject / merge)

```text
PATCH /api/v1/kb/inventory-categories/:key
```

Body:

```json
{
  "status": "approved",
  "required_attrs": ["manufacturer", "power"],
  "specs": { "power": { "canonical_unit": "w", "aliases": ["watt"] } },
  "plausible_ranges": { "power": { "min": 1, "max": 100000, "unit": "w" } },
  "canonical_of": ""
}
```

All body fields are optional — only supplied fields are updated.

## Workflow

1. Receive a JetStream `kb.line-file-generated` event.
2. Skip if `ShouldSkipLineFileGeneratedEvent(evt)` returns true.
3. Load the source record from `kb.inputs`.
4. Resolve the line file path.
5. **Reload boundary**: seed curated categories into `kb.inventory_categories` (once), then merge active categories (approved ∪ pending_review) into the in-memory dictionary so the LLM prompt includes known vocabulary.
6. If `force = true`, delete prior `kb.inventory_items` rows for the record.
7. Otherwise, if rows already exist, mark success and skip.
8. Read and parse the line file.
9. Load the `.chunks` artifact.
10. For each chunk:
    - build JSON-array LLM input from `Chunk.Lines` (includes dictionary context: version + categories)
    - call the primary model
    - retry with fallback model if configured and needed
    - normalize returned item rows
11. Dedupe normalized rows across chunks.
12. Persist rows to `kb.inventory_items`.
13. Write the `.inventory_items` artifact file.
14. Reindex search via `ReindexInventoryItemSearchForRecord(...)`.
15. **Post-pass curation**: call `CurateObservedCategories` with the extracted `item_category` surface forms — match-before-mint against the registry, mint `pending_review` for genuinely new types.
16. Persist the `extract_inventory_items` status entry on the record.
17. Write doc-proc logs for chunk calls and run summary.

## Failure Semantics

Processor-level failure occurs when the run cannot proceed meaningfully, for example:

- prompt load failure
- dictionary load failure
- model config load failure
- line file read / parse failure
- chunk artifact load failure
- database save failure

When that happens, the processor updates `kb.inputs.status` with:

- `operation = "extract_inventory_items"`
- `proc_status = "failed"`
- `error = "..."`

An individual chunk LLM failure does **not** necessarily fail the whole processor. The chunk is skipped and the processor continues with the remaining chunks. If a fallback model is configured, it is tried first.

Category curation failure (post-pass) is also non-fatal: it is logged as a warning but does not fail the document.

## Idempotence and Force Reprocessing

- If `force = false` and rows already exist for the record, the processor skips work and records success.
- If `force = true`, prior rows are deleted and the record is fully reprocessed.

This mirrors the idempotent pattern used by other ChenWeb doc processors.

## Relationship to Other Object Types

This processor should be understood as producing **Inventory Item Objects**.

It is related to, but distinct from:

- **Provision Objects**: rules, requirements, obligations, or constraint semantics
- **Entity Objects**: general named units such as organizations, systems, concepts, places
- **Relation Objects**: subject-predicate-object graph edges
- **Products**: older / disabled product extraction flow that is intentionally not used as an input dependency here

A provision may mention an inventory item, but the provision is the rule and the inventory item is the thing.

## References

- [Doc Processor Capsule](+CAPSULE.md)
- [Extract Entity & Relation Processor — Spec](extract-entity-relation-spec.md)
- [Chunking](../chunking/+CAPSULE.md)
- [Research Note: Semantic Projection / Inventory Item Objects](../../../Research/LLMPoweredDeepParsing.typ)
