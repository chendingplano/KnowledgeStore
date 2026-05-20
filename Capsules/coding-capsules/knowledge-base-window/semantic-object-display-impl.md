# Semantic Object Display — Reusable Extraction View

## Overview

The `kb-extraction-view.svelte` component is a generic, reusable canvas-and-list view for browsing LLM-extracted objects tied to `kb.inputs` records. It was extracted from `scene-blocks-view.svelte` so that any extraction type (Scene Blocks, Products, and future types) can reuse the same master–detail layout, attribute map canvas, inspector, PDF viewer, and resize logic by providing a small set of configuration props.

## Motivation

`scene-blocks-view.svelte` implemented the full Scene Blocks page in ~2700 lines. When the Products page was specified, its window design was described as "almost identical to Scene Blocks." Rather than duplicate the entire component, the implementation factored the shared logic into a single generic base and reduced each feature page to a thin wrapper (~150 lines) that supplies only the parts unique to its data type.

## Architecture

### Shared component

**File:** `ChenWeb/web/src/lib/components/home3/kb-extraction-view.svelte`

The component owns:

- **Layout shell** — hero banner, two-panel workspace (record browser left, detail right), focus-mode full-canvas split
- **Record browser integration** — delegates to `KbInputRecordBrowser`; on record select, calls `loadItems(recordId)` to populate the items list
- **Items list** — collapsed rows showing type pill, title, summary, keyword chips, confidence meter; resize handle between list and PDF panel; type filter dropdown
- **Focus mode** — clicking an item folds the Menu (via `onFocusModeChange`), shows the Attribute Map canvas + PDF viewer; Back button restores the list view
- **Attribute Map** — SVG radial layout of four group nodes radiating from a center disc; each group has satellite attribute nodes with hover-activated inspector popups; geometry computed from live `clientWidth`/`clientHeight`
- **Meta card** — floating overlay on the canvas showing item identity, confidence, object ID, evidence lines, and custom meta sections
- **Inspector** — floating panel rendering the hovered attribute's values in the appropriate format (`str`, `kw`, `entity`, `actions`, `rels`, `srcrefs`, `disc`, `text`)
- **PDF viewer** — `PdfViewWindow` with evidence-line highlights derived from `getItemEvidenceLines`; raw lines loaded lazily via `getRawLines`
- **Resize handles** — list panel width and PDF panel width are independently user-resizable and persisted to `localStorage` under `${storagePrefix}:*:${browserInstanceKey}` keys
- **Focus mode navigation** — Prev/Next buttons cycle through the type-filtered item list without leaving the canvas

### Exported types

```typescript
export type AttrKind =
  'str' | 'kw' | 'entity' | 'actions' | 'rels' | 'srcrefs' | 'disc' | 'text';

export type AttrDef = {
  key: string;
  label: string;
  icon: any;
  kind: AttrKind;
  field: string;
};

export type GroupDef = {
  id: string;
  label: string;
  icon: any;
  ux?: number;   // unit direction x — optional; auto-computed from group index if absent
  uy?: number;   // unit direction y — optional; auto-computed from group index if absent
  attrs: AttrDef[];
};
```

When `ux`/`uy` are omitted, the component distributes N groups evenly around the center circle starting from the top (angle = −π/2), going clockwise at 2π/N intervals. Four-group wrappers may still supply explicit `ux/uy = ±√½` to force the diagonal-corner layout.

### Props interface

| Prop | Type | Purpose |
|------|------|---------|
| `groups` | `GroupDef[]` | Canvas structure (required) |
| `loadItems` | `(recordId) => Promise<{results, file_name?}>` | API fetch (required) |
| `attrRaw` | `(item, def) => any[]` | Extract attribute values for the canvas and inspector |
| `buildMetaSections` | `(item) => MetaSection[]` | Build the meta card's extra rows |
| `getItemId` | `(item) => number` | Primary key |
| `getItemType` | `(item) => string` | Type string for pill and filter |
| `getItemTitle` | `(item) => string` | Primary display name |
| `getItemTitleEn?` | `(item) => string` | English subtitle (optional) |
| `getItemSummary` | `(item) => string` | Summary text |
| `getItemKeywords` | `(item) => string[]` | Keyword chips in list row |
| `getItemConfidence` | `(item) => number` | 0–1 confidence value |
| `getItemObjectId?` | `(item) => string` | Breadcrumb / meta card object identifier |
| `getItemSecondaryId?` | `(item) => string` | Second identifier row in meta card |
| `getItemSecondaryIdLabel?` | `string` | Label for the secondary ID row |
| `getItemEvidenceLines` | `(item) => any[]` | Evidence line spans for PDF highlighting |
| `getItemCreateTime` | `(item) => string` | ISO timestamp |
| `storagePrefix?` | `string` | localStorage key namespace |
| `itemsLabel?` | `string` | e.g. "Scene Blocks", "Products" |
| `itemLabelSingular?` | `string` | e.g. "scene block", "product" |
| `canvasItemLabel?` | `string` | e.g. "Scene Block", "Product" |
| `itemTypeFilterLabel?` | `string` | e.g. "Scene Type", "Product Type" |
| `emptyTableName?` | `string` | Table name shown in empty state |
| `emptySubtitle?` | `string` | Empty state descriptive text |
| `browserSubtitle?` | `string` | Subtitle in the record browser |
| `canvasMapLabel?` | `string` | Canvas header eyebrow label |
| Standard | `darkMode`, `browserInstanceKey`, `scopeToActiveStore`, `heroEyebrow`, `heroTitle`, `heroDescription`, `onFocusModeChange` | Shared with all knowledge sections |

### `AttrKind` rendering in the inspector

| Kind | Rendered as |
|------|-------------|
| `str` | Bulleted list |
| `kw` | Chip row |
| `entity` | Typed entity chips (`type · name`) |
| `actions` | Numbered sequence (`actor: action`) |
| `rels` | Relation chips (`type → target`) |
| `srcrefs` | Source reference list (kind badge + location) |
| `disc` | Discriminator cards (intent, domain, items) |
| `text` | Plain paragraph (single string field) |

### Thin wrappers

Each page that uses the shared component provides:

1. **`groups: GroupDef[]`** — Four-group canvas definition using imported Lucide icons.
2. **`attrRaw(item, def)`** — Knows how to extract values from the specific record type.
3. **`loadItems(recordId)`** — Wraps the type-specific `kbService` call.
4. **Accessor functions** — `getItemId`, `getItemType`, `getItemTitle`, etc., each a one-liner.
5. **Labels** — `storagePrefix`, `itemsLabel`, `canvasMapLabel`, etc.

## Thin wrapper files

### `scene-blocks-view.svelte`

- Groups: Metadata / Inputs & Resources / System Actions / Reasoning Logs
- `attrRaw`: handles `'str'`/`'kw'` via `strList`, `'actions'` via `sortedActions`, arrays via `arr`
- Loads via `listKbSceneBlocks`

### `products-view.svelte`

- Groups: Metadata / Grounding / Inputs / Actors / Requirements / Relations (6 groups, auto-distributed)
- `attrRaw`: handles `'text'` (single-string fields), `'str'`/`'kw'` (arrays), generic arrays
- Loads via `listKbProducts`

## localStorage key convention

```
<storagePrefix>:list-width:<browserInstanceKey>
<storagePrefix>:focus-pdf-width:<browserInstanceKey>
```

For Scene Blocks with `browserInstanceKey="scene-blocks"`:
```
scene-blocks:list-width:scene-blocks
scene-blocks:focus-pdf-width:scene-blocks
```

Changing `storagePrefix` or `browserInstanceKey` gives each extraction page its own independent panel width memory.

## Adding a new extraction page

1. Create `<name>-view.svelte` (~150 lines):
   - Define `GROUPS: GroupDef[]`. Omit `ux`/`uy` to auto-distribute groups evenly, or supply explicit values for custom placement.
   - Implement `attrRaw(item, def)` for any custom field shapes.
   - Implement `load<Name>Items(recordId)` wrapping the service call.
   - Wire all `getItem*` accessors and labels into `<KbExtractionView>`.

2. Add a `list<Name>s(inputRecordId)` function and typed record to `kbService.ts`.

3. Create `kbhandler/<name>_handler.go` following the pattern of `products_handler.go`:
   - Query the extraction table filtered by `input_record_id`.
   - Pass JSONB array columns through `jsonArrayOrEmpty`.
   - Register `GET /api/v1/kb/<name>` in `routes.go`.

4. In `+page.svelte`: add the section ID to `KbSectionId`, add a menu entry under Subject Wiki, add a render branch.

5. If the section was previously in `KNOWLEDGE_UNDER_CONSTRUCTION_SECTIONS`, remove it from `knowledge-sections.js`.
