# Products Page — Implementation

## Overview

The Products page (`kb-products`) surfaces product and part relations extracted by the `extract-products` doc-processing pipeline. Each row in `kb.products` describes one product referenced in a source document — its canonical name, how it relates to the document, what requirements apply, and which other products are related.

The page reuses the generic extraction view described in `semantic-object-display-impl.md`. Only the data-specific parts (groups, accessor functions, API call) live in `products-view.svelte`.

## Data model

**Table:** `kb.products`  
**Key columns:**

| Column | Type | Description |
|--------|------|-------------|
| `id` | bigserial | Primary key |
| `input_record_id` | bigint | Foreign key to `kb.inputs` |
| `product_rel_id` | text | Extraction-assigned object identifier (e.g. `"112_2"`) |
| `product_name` | text | Product name as extracted |
| `product_name_en` | text | English translation |
| `canonical_name` | text | Normalized canonical product name |
| `canonical_name_en` | text | English canonical name |
| `product_type` | text | Classification (e.g. `"other"`, `"device"`) |
| `relation_type` | text | How the document relates to this product (e.g. `"contains_product"`) |
| `relation_summary` | text | Prose summary of the relation |
| `relation_summary_en` | text | English translation |
| `evidence_quote` | text | Verbatim source text that grounds the extraction |
| `evidence_lines` | jsonb | Line number spans that contain the evidence |
| `obligation_level` | text | `"mandatory"`, `"recommended"`, or `"optional"` |
| `requirement_text` | text | The requirement the product is subject to |
| `requirement_text_en` | text | English translation |
| `conditions` | jsonb | Pre-conditions for the requirement |
| `exceptions` | jsonb | Exceptions to the requirement |
| `parameters` | jsonb | Parameter values or ranges |
| `related_products` | jsonb | Names of co-referenced products |
| `responsible_actor` | text | Entity responsible for the product requirement |
| `confidence` | double precision | Extraction confidence (0–1) |
| `confidence_reason` | text | LLM rationale for the confidence score |
| `model_name` | text | Extraction model |
| `prompt_name` | text | Extraction prompt |
| `create_time` / `modify_time` | timestamptz | Audit timestamps |

The migration is at:
`ChenWeb/project_migrations/20260520000001_create_kb_products_table.sql`

## Backend

**Handler:** `ChenWeb/server/api/kbhandler/products_handler.go`  
**Function:** `ListProducts`  
**Route:** `GET /api/v1/kb/products?input_record_id=N`

The handler follows the same pattern as `ListSceneBlocks`:

1. Validates `input_record_id` query param.
2. Does a best-effort lookup of `file_name` from the inputs table (used by the frontend to decide whether to show the PDF viewer).
3. Queries `kb.products WHERE input_record_id = $1 ORDER BY id`.
4. Scans each row, passing JSONB columns through `jsonArrayOrEmpty` to guarantee valid JSON for the client.
5. Returns `listProductsResponse{Status, InputID, FileName, Results, Total}`.

**Shared utilities from `scene_blocks_handler.go` that are reused:**
- `jsonArrayOrEmpty([]byte) json.RawMessage` — guards against NULL JSONB
- `resolveInputTable(db)` — resolves the active inputs table name

**Error code prefix:** `CWB_KB_PR_`

## Frontend service

**File:** `ChenWeb/web/src/lib/services/kbService.ts`

```typescript
export type KbProductRecord = {
  id: number;
  product_rel_id: string;
  product_name: string;
  product_name_en?: string;
  canonical_name: string;
  canonical_name_en?: string;
  product_type?: string;
  relation_type?: string;
  relation_summary?: string;
  relation_summary_en?: string;
  evidence_quote?: string;
  evidence_lines?: SourceLineSpan[];
  obligation_level?: string;
  requirement_text?: string;
  requirement_text_en?: string;
  conditions: string[];
  exceptions: string[];
  parameters: string[];
  related_products: string[];
  responsible_actor?: string;
  confidence: number;
  confidence_reason?: string;
  model_name: string;
  prompt_name: string;
  create_time: string;
  modify_time: string;
};

export type ListKbProductsResponse = { ... };
export async function listKbProducts(inputRecordId: number): Promise<ListKbProductsResponse>
```

## Frontend component

**File:** `ChenWeb/web/src/lib/components/home3/products-view.svelte`

A ~140-line thin wrapper over `kb-extraction-view.svelte`. The unique parts:

### Canvas groups

Six groups auto-distributed evenly (clockwise from top):

| Group | Position | Attributes |
|-------|----------|------------|
| **Metadata** | top | Product Type (`text`), Canonical Name (`text`) |
| **Grounding** | upper-right | Evidence Quote (`text`), Confidence Reason (`text`) |
| **Inputs** | lower-right | Conditions (`str`), Parameters (`str`) |
| **Actors** | bottom | Responsible Actor (`text`) |
| **Requirements** | lower-left | Obligation Level (`text`), Exceptions (`str`), Requirement Text (`text`) |
| **Relations** | upper-left | Relation Type (`text`), Related Products (`kw`) |

### `attrRaw` function

```typescript
function productAttrRaw(product: KbProductRecord, def: AttrDef): any[] {
  if (def.kind === 'text') {
    const val = (product as any)[def.field];
    return typeof val === 'string' && val.trim() ? [val.trim()] : [];
  }
  if (def.kind === 'str' || def.kind === 'kw') {
    return arr((product as any)[def.field]).filter(
      (v) => typeof v === 'string' && v.trim()
    );
  }
  return arr((product as any)[def.field]);
}
```

The `'text'` kind — new in the shared component — handles single-string fields. The function returns a one-element array when the field has a non-empty value, or an empty array when it does not. The canvas node badge shows `1` or `0` accordingly, and the inspector renders the string as a paragraph.

### Meta sections utility

**File:** `ChenWeb/web/src/lib/components/home3/product-meta.js`  
**Function:** `buildProductMetaSections(product)`

Emits meta card rows for:
- Relation Summary (Chinese + English if different)
- Requirement Text (Chinese + English if different)
- Canonical Name (Chinese + English if different)
- Obligation Level (as a chip)
- Confidence Reason (prose)

### Item mapping

| Accessor | Maps to |
|----------|---------|
| `getItemId` | `p.id` |
| `getItemType` | `p.product_type` |
| `getItemTitle` | `p.product_name` |
| `getItemTitleEn` | `p.product_name_en` |
| `getItemSummary` | `p.relation_summary` |
| `getItemKeywords` | `[]` (products have no keywords field) |
| `getItemConfidence` | `p.confidence` |
| `getItemObjectId` | `p.product_rel_id` |
| `getItemEvidenceLines` | `p.evidence_lines` |
| `getItemCreateTime` | `p.create_time` |

## Menu integration

**Section ID:** `kb-products`

The section appears under the **Subject Wiki** parent menu, between Scene Blocks and Provision Tree. It is no longer in `KNOWLEDGE_UNDER_CONSTRUCTION_SECTIONS` (removed `kb-product-parts` from `knowledge-sections.js`).

```javascript
// +page.svelte — menu definition
{
  id: 'kb-products',
  label: 'Products',
  description: 'Product and part relation extraction'
}
```

The focus-mode callback (`onFocusModeChange`) uses the shared `handleExtractionFocusMode` function, which folds the left Menu whenever a product is opened on the canvas, and restores it when the user presses Back.

## localStorage keys

```
products:list-width:products
products:focus-pdf-width:products
```

## Related files

| File | Role |
|------|------|
| `ChenWeb/project_migrations/20260520000001_create_kb_products_table.sql` | Table schema |
| `ChenWeb/server/api/doc-processing/extract-products.go` | Extraction pipeline that populates `kb.products` |
| `ChenWeb/server/api/kbhandler/products_handler.go` | API handler |
| `ChenWeb/server/api/routes.go` | Route registration |
| `ChenWeb/web/src/lib/services/kbService.ts` | Frontend service types + fetch |
| `ChenWeb/web/src/lib/components/home3/products-view.svelte` | Page component (thin wrapper) |
| `ChenWeb/web/src/lib/components/home3/product-meta.js` | Meta section builder |
| `ChenWeb/web/src/lib/components/home3/kb-extraction-view.svelte` | Shared base component |
| `ChenWeb/web/src/routes/home3/knowledge/+page.svelte` | Menu + render integration |

## Related Documents

`KnowledgeStore/Capsules/coding-capsules/knowledge-base-window/+CAPSULE.md` — Products section (line 308)

`KnowledgeStore/Capsules/coding-capsules/knowledge-base-window/semantic-object-display-impl` — This is a reusable module to actually display the selected product.