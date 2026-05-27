# Extract Product Relations — Implementation Notes

## Overview

The Extract Product Relations processor (`extract_products`) is Doc Processor pipeline entry #10. It now uses a multi-pass extraction flow:

1. mention extraction per block
2. deterministic merge and dedup
3. relation enrichment per product candidate
4. optional translation
5. optional categorization

The final normalized rows are saved to `kb.products`, indexed into the category tree, and written to a `.products` artifact file.

**Spec:** `extract-products-spec.md`  
**Implementation:** `ChenWeb/server/api/doc-processing/extract-products.go`  
**Migration:** `ChenWeb/project_migrations/20260520000001_create_kb_products_table.sql`

---

## Why This Refactoring Happened

### Problems Before The Refactoring

Before the refactoring, the processor used a single-pass extraction strategy. One LLM call per block was responsible for:

- finding products
- inferring the relation type
- extracting obligation and requirement details
- generating translated `_en` fields
- generating category paths
- generating extra metadata

This design caused several practical issues:

- repeated runs on the same input could produce very different product counts
- smaller models such as `gpt-5.4-mini` were not stable enough for the full one-shot task
- empty or partial JSON outputs were more likely because the requested schema was too large
- the output contract was unclear about whether one row represented one product or one product-relation pair
- the LLM had to perform overlap cleanup and deduplication implicitly rather than relying on deterministic code

### Findings About The Causes

The instability investigation produced the following findings:

1. The main problem was task overload, not just sampling randomness.
   Even with deterministic decoding settings, the model was still being asked to solve too many subproblems in one generation.

2. The old schema mixed high-recall extraction with high-precision reasoning.
   Mention discovery and relation enrichment have different error profiles and should not share the same pass.

3. Overlap and duplicate mention cleanup belonged in code, not in prompt instructions alone.

4. The processor needed a hard semantic rule for rows.
   The new rule is:
   - one final row = one product-relation pair

5. After the multi-pass refactor was implemented, a second bug was discovered in deterministic candidate grouping.
   The first version of candidate key normalization kept only ASCII letters and digits, which caused some multilingual product names to collapse to an empty key and be discarded before relation enrichment.

### Solutions Implemented

The refactoring solved the above issues by:

1. introducing a multi-pass pipeline
2. separating mention recall from relation reasoning
3. moving overlap handling and deduplication into deterministic Go code
4. shrinking each prompt/schema to a focused task
5. making translation and categorization optional later passes
6. fixing candidate key normalization to preserve Unicode letters and numbers

The result is a more stable pipeline that still writes the same final `kb.products` rows.

---

## Files Changed

| File | Change |
|------|--------|
| `ChenWeb/server/api/doc-processing/extract-products.go` | Processor implementation |
| `ChenWeb/server/api/doc-processing/extract-products_test.go` | Multi-pass tests |
| `ChenWeb/prompts/prompt-extract-product-mentions-v1.md` | Pass 1 prompt |
| `ChenWeb/prompts/prompt-enrich-product-relations-v1.md` | Pass 2 prompt |
| `ChenWeb/prompts/prompt-translate-products-v1.md` | Optional translation prompt |
| `ChenWeb/prompts/prompt-categorize-products-v1.md` | Optional categorization prompt |
| `ChenWeb/project_migrations/20260520000001_create_kb_products_table.sql` | `kb.products` table |
| `ChenWeb/server/cmd/doc-processor/main.go` | Processor wired into `ControlService.Processors` |

---

## Key Types

### `ProductsProcessor`

`ProductsProcessor` now carries per-pass prompt and model configuration:

- mention prompt + model
- relation prompt + model
- optional translation prompt + model
- optional categorization prompt + model
- shared fallback model

The final output shape still matches the existing `kb.products` schema.

### Internal helper types

- `productMention`: one mention extracted from one block
- `productCandidate`: deterministic merged candidate built from one or more mentions

### `ProductsStore`

```go
type ProductsStore interface {
    ProductsExist(ctx context.Context, inputRecordID int64) (bool, error)
    DeleteProductsByInputRecordID(ctx context.Context, inputRecordID int64) (int64, error)
    SaveProducts(ctx context.Context, req SaveProductsRequest) (int64, error)
}
```

Implemented by `ProductsSQLStore{DB *sql.DB}`.

---

## Environment Variables

### Core pass configuration

| Variable | Purpose |
|----------|---------|
| `EXTRACT_PRODUCT_MENTIONS_MODEL_NAME` | Pass 1 model reference |
| `EXTRACT_PRODUCT_MENTIONS_PROMPT` | Pass 1 prompt file name or path |
| `ENRICH_PRODUCT_RELATIONS_MODEL_NAME` | Pass 2 model reference |
| `ENRICH_PRODUCT_RELATIONS_PROMPT` | Pass 2 prompt file name or path |
| `MODEL_DEF_FILE` | Path to models config file |
| `EXTRACT_PRODUCT_MODEL_FALLBACK` | Shared fallback model reference |

### Optional pass configuration

| Variable | Purpose |
|----------|---------|
| `TRANSLATE_PRODUCTS_MODEL_NAME` | Translation pass model reference |
| `TRANSLATE_PRODUCTS_PROMPT` | Translation pass prompt file name or path |
| `CATEGORIZE_PRODUCTS_MODEL_NAME` | Categorization pass model reference |
| `CATEGORIZE_PRODUCTS_PROMPT` | Categorization pass prompt file name or path |

### Backward compatibility

The processor still accepts the old single-pass keys as fallbacks:

- `EXTRACT_PRODUCT_MODEL_NAME`
- `EXTRACT_PRODUCTS_PROMPT`
- `EXTRACT_PRODUCT_PROMPT`

These are used when the new pass-specific env vars are not provided.

### Shared processor configuration

| Variable | Purpose |
|----------|---------|
| `PROMPT_DIR` | Directory searched for prompt files |
| `ARTIFACT_DIR` | Root dir for `.products` artifact output |
| `ARTIFACT_WEB_DIR` | Root dir for category tree index |
| `INPUT_BLOCK_SIZE` | Override blocking block size |

Prompt resolution order remains:

1. exact path if absolute
2. `PROMPT_DIR/<name>`
3. `server/cmd/doc-processor/<name>`
4. `server/cmd/doc-processor/prompts/<name>`
5. `prompts/<name>`

Default filenames:

- mentions: `prompt-extract-product-mentions-v1.md`
- relations: `prompt-enrich-product-relations-v1.md`
- translation: `prompt-translate-products-v1.md`
- categorization: `prompt-categorize-products-v1.md`

---

## `HandleEvent` Flow

1. Parse `LineFileGeneratedEvent`.
2. Skip if `ShouldSkipLineFileGeneratedEvent` returns true.
3. Fail fast if required mention or relation prompt/model config is invalid.
4. Load `kb.inputs` record.
5. If `force=true`, delete existing product rows. Otherwise skip when rows already exist.
6. Resolve blocks:
   - from `BlockBuffer` in context, or
   - by reading the canonical line file and calling `buildBlocks`
7. Run multi-pass extraction via `extractProductsFromBlocksWithLLM`.
8. Assign `product_rel_id = "<record_id>_<seqno>"`.
9. Upsert all rows to `kb.products`.
10. Index category paths into the category tree.
11. Write the `.products` artifact.
12. Persist `extract_products` status to `kb.inputs.status`.

---

## Multi-Pass Extraction

### Pass 1: Mention extraction

For each block:

- build mention-focused user input with `buildProductMentionsUserPrompt`
- call the mention prompt/model
- normalize `mentions`

This produces `[]productMention`.

### Deterministic merge and dedup

`mergeProductMentionCandidates`:

- groups mentions by normalized canonical or mention text
- drops overlap-only groups with no normal-line support
- merges support lines and supporting mentions
- picks a stable product type hint
- preserves multilingual product names by keeping Unicode letters and numbers during candidate key normalization

This produces `[]productCandidate`.

### Pass 2: Relation enrichment

For each candidate:

- build relation-focused user input with `buildProductRelationUserPrompt`
- call the relation prompt/model
- normalize `products`

Each returned row is interpreted as exactly one product-relation pair.

### Final deterministic dedup

`dedupeFinalProductRows` merges accidental duplicates using:

```text
normalized canonical/product name + relation_type + requirement_text
```

It preserves merged evidence lines and the strongest confidence.

### Optional translation

If enabled:

- call the translation prompt/model once per final row
- fill `product_name_en`, `canonical_name_en`, `relation_summary_en`, `requirement_text_en`, `confidence_reason_en`

### Optional categorization

If enabled:

- call the categorization prompt/model once per final row
- fill `category_paths` and `category_paths_en`

---

## Fallback Handling

Each LLM call uses the shared fallback model when the primary call fails.

If the fallback fails with an empty/truncated JSON response matching:

- `unexpected end of JSON input`
- `json:{[]}`

the processor treats that unit as an empty successful extraction rather than a hard failure.

For mention extraction this means empty `mentions`; for relation extraction it means empty `products`.

---

## Normalization

### Mention normalization

`normalizeProductMentions` converts LLM output into `productMention` values and records:

- mention text
- canonical hint
- product type hint
- evidence quote and line spans
- whether the evidence reaches a normal line

### Relation normalization

`normalizeProductList` flattens `relation_details` into the top-level row shape used by the final storage layer:

- `parameters` ← `thresholds_or_parameters`
- `related_products` ← `relation_details.related_products`
- `conditions` and `exceptions` normalized via `toStringSlice`
- `relation_summary` populated from `product_summary`

---

## Database: `kb.products`

Unique constraint: `(input_record_id, product_rel_id)` — upsert on conflict updates all fields and sets `modify_time = NOW()`.

Key columns:

| Column | Type | Notes |
|--------|------|-------|
| `product_rel_id` | TEXT | `<record_id>_<seqno>` |
| `input_record_id` | BIGINT | FK → `kb.inputs(id)` ON DELETE CASCADE |
| `product_name` / `product_name_en` | TEXT | Source / translated names |
| `canonical_name` / `canonical_name_en` | TEXT | Normalized names |
| `product_type` | TEXT | Enum-like product kind |
| `relation_type` | TEXT | One relation type per row |
| `evidence_lines` | JSONB | Compact line spans |
| `parameters` | JSONB | Thresholds/parameters |
| `related_products` | JSONB | Related product list |
| `conditions` / `exceptions` | JSONB | String arrays |
| `category_paths` / `category_paths_en` | JSONB | Category tree paths |
| `model_name` / `prompt_name` | TEXT | Provenance metadata |

---

## Artifact File

**Path:** `ARTIFACT_DIR/<group_id>/<record_id>/<filename_root>_<parser_name>.products`

where:

- `group_id = floor(record_id / 1000)`
- `filename_root` is derived from `kb.inputs.staging_filename`
- `parser_name` is `kb.inputs.parser_name`

The file is a JSON array built by `buildProductFileRecord`.

---

## Category Tree Indexing

Category indexing is unchanged:

1. Parse `category_paths` and `category_paths_en`
2. Walk or create category subdirectories
3. Append `product_rel_id` to leaf `products.txt`

On re-extraction, old `<record_id>_` entries are removed before re-indexing.

---

## Tests

`extract-products_test.go` covers:

- dropping overlap-only mention groups
- preserving non-English product mentions during candidate grouping
- end-to-end multi-pass processor execution
- final row save and artifact writing behavior

---

## Status Entry

Operation name: `"extract_products"`.

Example:

```json
{
  "record_id": "123",
  "file_type": "pdf",
  "operation": "extract_products",
  "proc_status": "success | failed",
  "input_filename": "Artifacts/0/123/doc_opendata.txt",
  "start_time": "20260520 10:00:00",
  "ms_used": 4200
}
```

---

## MID Code Range

`MID_26052001` – `MID_26052070`

| Range | Area |
|-------|------|
| `MID_26052001` | Logger default ID |
| `MID_26052002–07` | `HandleEvent` error paths |
| `MID_26052010–13` | `resolveProductBlocks` |
| `MID_26052020–23` | LLM extraction + fallback |
| `MID_26052030–34` | `extractProductPayload` |
| `MID_26052040–45` | Category tree indexing |
| `MID_26052050–54` | Artifact file writing |
| `MID_26052060–63` | Prompt loading |
| `MID_26052070` | SQL store nil-DB guard |
