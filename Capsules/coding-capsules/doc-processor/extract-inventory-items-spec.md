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
| `EMBEDDING_MODEL_NAME` | required | Embedding model for fuzzy category synonym matching during post-pass curation. When absent, the curator degrades to string-only matching. |
| `INVENTORY_CATEGORY_FUZZY_THRESHOLD` | optional | Cosine similarity threshold for category synonym matching. Default `0.86`. |
| `ARTIFACT_DIR` | yes | Root artifact directory where `.chunks` and `.inventory_items` live |
| `MODEL_DEF_FILE` | yes | Model registry used by the shared model loader |

If the primary model config fails to load, the processor records a `failed` status entry and returns. The rest of the pipeline continues.

## Concurrency

Chunks may be processed concurrently, capped by `EXTRACT_INTENTORY_ITEMS_MAX_TASKS`. The default is `1` (sequential). Individual chunk LLM failures are logged and skipped; they do not fail the run. Only a user-requested pipeline stop cancels remaining chunk work.

## Single-Pass Per Chunk

For each chunk, this processor makes **one LLM call** using `prompt-extract-inventory-items-v1.md`.

The LLM call returns strict JSON:

```json
{
  "language": "en",
  "items": [
    {
      "item_name": "string",
      "canonical_name": "string",
      "item_categories": ["string"],
      "manufacturer": "string",
      "brand": "string",
      "model_number": "string",
      "part_number": "string",
      "raw_specs": [
        { "name": "string", "value": "string or number", "unit": "string" }
      ],
      "standards": ["string"],
      "aliases": ["string"],
      "evidence_quote": "short exact quote",
      "lines": ["12", "13-15"],
      "confidence": 0.0,
      "confidence_reason": "string"
    }
  ]
}
```

Overlap lines (`flag = "o"`) are context only. The prompt instructs the model not to emit an item whose evidence depends only on overlap lines.

## Go-Side Normalization

The LLM output is only the first pass. The Go processor performs deterministic normalization before persistence:

- normalize `item_categories`
- normalize spec names using category schemas
- normalize units using dictionary conversion rules
- build `normalized_specs`
- compute `missing_required_attrs`
- compute `validation_flags`
- compute stable `dedupe_key`
- assign `inventory_item_id = <record_id>_inv_<seqno>`

This is an important design point: the LLM proposes candidate item attributes, but the system-owned normalization and validation logic lives in Go.

## Category Ontology — Two Layers

The category system has two distinct layers that must not be confused.

### Layer 1 — Ontology (schema): `kb.artifact_categories`

**Defines the controlled vocabulary of item types.** Each row represents a category like `pump`, `bearing`, etc. This table grows only when genuinely new item categories are encountered in the corpus, not with every extracted item.

The schema is now DB-backed (not file-only). `kb.artifact_categories` is the live registry, with `kb.artifact_categories.category_type` = 'inventory_item'.

### Layer 2 — Instances: `kb.inventory_items`

**The extracted items themselves.** 理疗仪, 检查床, 血压计 are rows here. This table grows with every document and can hold hundreds of thousands to millions of rows. Instances are never added back to the ontology layer. The instance carries the `item_categories` key, not a full schema copy.

## Automatic Category Admission (Post-Pass)

After each document's items are saved, the processor runs a **post-pass curation step** in Phase C (refer to [1] for Phase C) to admit novel `item_categories` values into `kb.artifact_categories`. This step is best-effort — a failure does not fail the document.

For more information about creating new artifact categories, refer to [5].

**Match-before-mint in three tiers:**

1. **Exact key match** — normalized surface form already in the registry → increment `seen_count`, append display name. No new row.
2. **Display-name / alias match** — surface form matches any known `display_names` entry → fold into that category. No new row.
3. **Embedding cosine match** (if `INVENTORY_CATEGORY_EMBEDDING_MODEL_NAME` is set) — cosine similarity ≥ `INVENTORY_CATEGORY_FUZZY_THRESHOLD` → treated as synonym of the best-matching category. No new row.
4. **Miss all tiers** → mint a new `pending_review` row, `seen_count = 1`.

The curation pass is batched per document and builds an intra-document snapshot for convergence: a category minted early in a document is matchable by later surface forms in the same pass.

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
| `inventory_item_id` | text | `<record_id>_inv_<seqno>` |
| `input_record_id` | bigint | source `kb.inputs.id` |
| `language` | text | detected input language |
| `item_name` | text | source-language item string |
| `canonical_name` | text | normalized display name; falls back to `item_name` |
| `item_categories` | text | normalized category key such as `pump`, `bearing`, `medical_device` |
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
| `search_document` | text | maintained by trigger — plain-text concat of searchable fields (see below) |
| `search_vector` | tsvector | maintained by trigger — `to_tsvector('simple', search_document)` |
| `ext_info` | jsonb | includes language, schema version, `chunk_seq_no`, and `mention_count` (how many raw extractions collapsed into this survivor during dedup) |

### Search Document Composition

`search_document` is built by `kb.inventory_item_search_document()` (a DB trigger function) as a single space-separated string from these fields, in order:

1. `item_name`
2. `canonical_name`
3. `item_categories`
4. `manufacturer`
5. `brand`
6. `model_number`
7. `part_number`
8. `normalized_specs` — JSONB array elements joined as text
9. `raw_specs` — JSONB array elements joined as text
10. `standards` — JSONB array elements joined as text
11. `aliases` — JSONB array elements joined as text
12. `evidence_quote`
13. `validation_flags` — JSONB array elements joined as text
14. `missing_required_attrs` — JSONB array elements joined as text
15. `dedupe_key`
16. `confidence_reason`

`search_vector` is then computed as `to_tsvector('simple', search_document)`. The `simple` dictionary lowercases and tokenizes without stemming or stop-word removal, preserving non-Latin tokens (e.g. Chinese) exactly as they appear.

The trigger fires `BEFORE INSERT OR UPDATE` on any of those columns. `search_document` is also written by the Go side as a fallback before the first DB insert (concatenating the scalar text fields only); the trigger overwrites it with the full version including JSONB content.

## Validation Flags

The current Go normalization layer can emit:

- `unknown_category` — the item's `item_categories` was not in the curated ontology at extraction time (including pending_review categories if the post-pass runs after extraction)
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

- `kb.inventory_items` — extracted item instances (survivors only)

Duplicate audit table:

- `kb.inventory_item_duplicates` — rows discarded by dedup, each with a `duplicate_of` pointer to its survivor. Mirrors the `kb.inventory_items` columns plus `duplicate_of`; has no `search_document` / `search_vector` (duplicates are never searched). Created in migration `20260601000001_create_kb_inventory_item_duplicates.sql`.

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
- `item_categories` (membership match against the item's category array)
- `manufacturer`
- `brand`
- `model_number`
- `part_number`
- `validation_status`

Search uses the shared registry search path and returns `artifact_type = "inventory_item"`.

#### Full-text search semantics

The query string is passed to `websearch_to_tsquery('simple', q)` by default (phrase-friendly mode), or `plainto_tsquery('simple', q)` otherwise. Both functions treat a multi-word query as **AND** — every token must be present in `search_vector` for an item to match. `websearch_to_tsquery` additionally supports `-word` for exclusion and `"..."` for phrase matching.

For queries that contain CJK characters the match condition is widened: the tsvector match is OR'd with `ILIKE '%q%'` checks against `primary_label`, `secondary_label`, `snippet_basis`, and `search_document`. This is a fallback because CJK tokenization in the `simple` dictionary is unreliable for short multi-character terms.

Matching results are ranked by `ts_rank_cd`. For CJK queries, additional score bonuses are added for substring hits in `primary_label` (+1.25), `secondary_label` (+0.50), `snippet_basis` (+0.40), and `search_document` (+0.20).

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
6. If `force = true`, delete prior `kb.inventory_items` **and** `kb.inventory_item_duplicates` rows for the record.
7. Otherwise, if rows already exist, mark success and skip.
8. Read and parse the line file.
9. Load the `.chunks` artifact.
10. For each chunk:
    - build JSON-array LLM input from `Chunk.Lines` (includes dictionary context: version + categories)
    - call the primary model
    - retry with fallback model if configured and needed
    - normalize returned item rows
    - accumulate into a flat list across all chunks
11. Dedupe normalized rows across chunks (see [Deduplication](#deduplication) below); merge provenance into survivors. Log `extracted=N` (raw), `unique=M` (survivors), `duplicates=N−M`.
12. Persist survivors to `kb.inventory_items` (log `inserted_items=M`), then persist the discarded duplicates to `kb.inventory_item_duplicates` (best-effort; failure is logged, not fatal).
13. Write the `.inventory_items` artifact file (survivors only, with merged provenance; non-fatal if it fails).
14. Reindex search via `ReindexInventoryItemSearchForRecord(...)`.
15. **Post-pass curation**: call `CurateObservedCategories` with the extracted `item_categories` surface forms (flattened across all items) — match-before-mint against the registry, mint `pending_review` for genuinely new types.
16. Persist the `extract_inventory_items` status entry on the record.
17. Write doc-proc logs for chunk calls and run summary.

## Deduplication

The same physical item commonly appears in multiple chunks because chunks overlap or because a document lists the same item in different sections. After all chunk extractions are accumulated, `dedupeInventoryItemRows()` collapses duplicates before any persistence.

**Algorithm:**

1. For each item, compute its dedup key from `dedupe_key`. The key is assembled as pipe-separated segments:
   ```
   <category>|<name>|<manufacturer_or_brand>|<model_number>|<part_number>|<spec1=value1unit1,...>
   ```
   - `<name>` is the normalized `canonical_name`, falling back to `item_name`.
   - Each segment is normalized (lowercased, punctuation collapsed to nothing; CJK characters preserved).
   - Spec parts are sorted alphabetically before joining so spec order does not matter.

   **The name is part of the item's identity.** Two items that differ only in name are distinct items, not duplicates, and must never collapse. This matters most for spec-less items with no manufacturer/model/part (e.g. raw materials): without the name segment, every such item in a category would share `<category>|||||` and all but the highest-confidence one would be silently deleted.

   Including the name does **not** weaken true-duplicate detection: the duplicates dedup exists to remove come from overlapping chunks, which see identical source text and therefore emit an identical name. The trade-off is that the *same* item mentioned under two *different* surface names in non-overlapping locations (e.g. `氢氧化钙` vs `消石灰`) will not merge — which is the safe direction, and the alias relationship is preserved in `aliases`.

   Examples:
   - `氢氧化钙` (`raw_specs: []`, no maker/model/part) → `dedupe_key = "material|氢氧化钙||||"`
   - `氯化钠` in the same category → `dedupe_key = "material|氯化钠||||"` — distinct key, both items kept.

2. Group all accumulated rows by key (first-encounter order preserved).
3. Within each group, the **highest-confidence row becomes the survivor** (ties resolved by first-encounter order).
4. **Provenance is merged into the survivor** — it is not lost with the discarded rows:
   - `source_line_spans`, `aliases`, and `standards` are unioned (deduplicated, sorted) across every member of the group.
   - `ext_info.mention_count` records how many raw extractions collapsed into the survivor.
   - Scalar fields (`confidence`, `evidence_quote`, specs, names) remain those of the survivor row; they are **not** merged.

### Duplicate retention (no silent loss)

Discarded duplicates are **not** dropped. Every non-survivor row is persisted to a dedicated audit table, `kb.inventory_item_duplicates`, with:

- its own `inventory_item_id` (`<record_id>_dup_<seqno>`),
- a `duplicate_of` pointer to the survivor's `inventory_item_id`,
- the same `dedupe_key` as its survivor (so groups can be reconstructed by join),
- all of its **own** original attributes (own `confidence`, `evidence_quote`, `source_line_spans`, etc.) retained for audit.

This keeps the serving table (`kb.inventory_items`) and the search index clean — they contain only survivors — while preserving full recoverability. The `.inventory_items` artifact file likewise contains only survivors (with merged provenance).

Persisting duplicates is **best-effort**: survivors are saved first, so a failure writing the duplicates table is logged as a warning and does not fail the document.

**Observable counts:** the `extract inventory items finished` log now reports `extracted=N` (raw, pre-dedup), `unique=M` (survivors), and `duplicates=N−M`. The survivors land in `kb.inventory_items` (`inserted_items=M`); the rest land in `kb.inventory_item_duplicates`. For example: 143 raw items → 33 survivors + 110 duplicate rows, nothing lost.

**Recovery / audit query:**

```sql
SELECT s.inventory_item_id, s.item_name, d.inventory_item_id AS dup_id, d.confidence
FROM kb.inventory_items s
JOIN kb.inventory_item_duplicates d ON d.duplicate_of = s.inventory_item_id
WHERE s.input_record_id = $1
ORDER BY s.inventory_item_id;
```

## Embedding

Embedding is **optional**, used only during the **post-pass category curation** step — not during item extraction or deduplication.

**What triggers it:** when a new `item_category` surface form is encountered that does not match any existing category by exact key or display-name/alias, the curator embeds the surface form and computes cosine similarity against embeddings stored in `kb.inventory_categories`. If the similarity exceeds the threshold (`INVENTORY_CATEGORY_FUZZY_THRESHOLD`, default `0.86`), the surface form is folded into the best-matching existing category instead of minting a new `pending_review` row.

**What is embedded:** the raw `item_category` surface form string (e.g. `"medical device"`, `"医疗器械"`). Only one embedding call is made per novel, unmatched surface form per document. Already-known categories skip the embedding step entirely.

**Configuration:** set `EMBEDDING_MODEL_NAME` (falls back to `INVENTORY_CATEGORY_EMBEDDING_MODEL_NAME` if absent). If neither is set, the embedder is `nil` and the curator degrades gracefully to string-only matching (exact key + display-name/alias tiers only). Category curation failures — including embedding failures — are logged as warnings and never fail the document.

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
- If `force = true`, prior `kb.inventory_items` **and** `kb.inventory_item_duplicates` rows are deleted and the record is fully reprocessed.

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

- [1]: [Processor Capsule](+CAPSULE.md)
- [2]: [Extract Entity & Relation Processor — Spec](extract-entity-relation-spec.md)
- [3]: [Chunking](../chunking/+CAPSULE.md)
- [4]: [Research Note: Semantic Projection / Inventory Item Objects](../../../Research/LLMPoweredDeepParsing.typ)
- [5]: KnowledgeStore/Capsules/coding-capsules/llm-wiki/artifact-connections.md
