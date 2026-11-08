# Module: Product Viewer

**Module ID:** `20261108-02`
**Type:** frontend · **Language:** svelte · **Version:** 1.0.0
**Status:** active — used by Knowledge Base → Products and System Admin → LLM → Benchmark → Products → Gold Products
**Project:** ChenWeb (web front end)
**Location:** `ChenWeb/web/src/lib/components/shared-ui/product-viewer/`
**Created:** 2026-11-08

## 1. What it is

One page-sized component for browsing extracted products. It shows, left to right: the
product list, a product map (the product and its attributes as a graph), the source PDF with
the evidence highlighted, and a **Product Details** panel on the far right that runs the full
height of the page. A "Close panel / Open panel" button hides and shows that panel.

Dragging the slider between the PDF and the details panel changes only those two widths;
the map keeps its width. It is not the scoring report (System Admin → … → Products →
Benchmark), which compares products against a gold run and does not use this component.

## 2. Files

| File | Purpose |
|---|---|
| `product-viewer.svelte` | The module: layout, details-panel open/close, slider logic |
| `product-details.svelte` | Name/value card for one product (all fields) |
| `home3/products-view.svelte` | The product list/map/PDF view (a generic `kb-extraction-view.svelte` configured for products); the viewer wraps it |

## 3. Interface

```ts
{
  darkMode?: boolean;                     // default true
  source?: 'kb' | 'testbed';              // default 'kb'; 'testbed' = read-only gold run
  browserInstanceKey?: string;            // default 'products'; keys persisted list/PDF widths
  scopeToActiveStore?: boolean;           // default false
  onFocusModeChange?: (focused: boolean) => void; // host can fold its menu while a product is open
}
```

The component fills its parent (`height: 100%`), so the parent must have a height.

## 4. Configuration

| Key | Default | Meaning |
|---|---|---|
| `darkMode` | `true` | Theme |
| `source` | `"kb"` | `kb` or `testbed` (gold run) |
| `browserInstanceKey` | `"products"` | Storage key suffix; use a different one per page |
| `scopeToActiveStore` | `false` | Limit to the active knowledge store |

## 5. Usage

```svelte
<ProductViewer {darkMode} source="testbed" browserInstanceKey="gold-products"
  onFocusModeChange={handleExtractionFocusMode} />
```

## 6. Behaviour and conventions

- All text goes through Paraglide (`products_*`, `kb_extraction_*`, `content_panel_*` keys).
- Details-panel drag: panel 220–680 px, PDF 320–1460 px; the PDF width is persisted per
  `browserInstanceKey` by `kb-extraction-view.svelte`.
- The details panel opens when a product is selected and closes with the item.

## 7. Scope and limits

- The metric and provision pages still carry their own shelf wiring in
  `routes/home3/knowledge/+page.svelte`; they could follow the same pattern.
- `ContextShelf`'s `productDetails` prop is still the shelf slot; the viewer feeds it.
