# Record List — Implementation Notes

## Overview

The left-side `kb.inputs` record list used across `home3/knowledge` was previously implemented multiple times with slightly different search, pagination, and selection logic. This refactor extracts that shared behavior into a reusable component:

```text
KbInputRecordBrowser
  ├─ record id retrieve
  ├─ Search dialog
  ├─ Reset filters
  ├─ Pagination
  ├─ Width resize handle
  ├─ Settings popover
  └─ Per-instance persisted settings
```

The goal was to make the **left-side record browser** reusable without forcing the right-side view logic to become generic.

---

## Scope

This refactor only standardizes the **left record browser** for `kb.inputs`.

It does **not** attempt to unify:

- the middle content pane for metrics / chunks / structure lines
- the right-side document or PDF inspector
- per-view domain logic after a record is selected

Each knowledge page still owns its own record-specific loading behavior after selection.

---

## Files

### New shared browser files

| File | Role |
|------|------|
| `web/src/lib/components/home3/kb-input-record-browser.svelte` | Reusable left-side `kb.inputs` browser |
| `web/src/lib/components/home3/kb-input-record-browser-settings.js` | Width / page-size persistence helpers |
| `web/src/lib/components/home3/kb-input-record-browser-settings.test.js` | Settings helper tests |

### Shared helper updates

| File | Role |
|------|------|
| `web/src/lib/components/home3/kb-input-search-dialog.svelte` | Search popup now preserves and returns filter state |
| `web/src/lib/components/home3/topic-tree-record-browser.js` | Shared list/filter/selection helpers |
| `web/src/lib/components/home3/topic-tree-record-browser.test.js` | Helper tests |

### Migrated consumers

| File | Result |
|------|--------|
| `inputs-mgmt-view.svelte` | Document Details now uses shared browser |
| `metric-mgmt-view.svelte` | Metrics now uses shared browser |
| `doc-structure-view.svelte` | Document Structure now uses shared browser |
| `chunk-mgmt-view.svelte` | Chunks now uses shared browser |
| `summary-tree-view.svelte` | Summary Tree now uses shared browser |
| `topic-tree-view.svelte` | Semantic Tree / Provision Tree now uses shared browser |
| `routes/home3/knowledge/+page.svelte` | Distinct instance keys for Topic Tree vs Provision Tree |

---

## Browser Features

`KbInputRecordBrowser` owns the shared `kb.inputs` browsing workflow:

- Record ID input plus `Retrieve`
- `Search` button and popup dialog
- `Reset` button for active filters
- paged `listKbInputs(...)` loading
- automatic first-record selection on page load
- optional active-store scoping
- drag-to-resize list width
- `Settings` popover
- per-instance persisted settings
- reusable record-card mapping via `mapRecord`

The component emits selected records back to the consumer through `onSelect(record)`.

---

## Public API

### Main props

| Prop | Type | Description |
|------|------|-------------|
| `instanceKey` | `string` | Required persistence key for page-specific settings |
| `title` | `string` | Header label shown above results |
| `subtitle` | `string` | Helper copy below controls |
| `emptyTitle` | `string` | Empty-state heading |
| `emptySubtitle` | `string` | Empty-state copy |
| `selectedRecordId` | `number \| null` | Current selected record from consumer |
| `scopeToActiveStore` | `boolean` | Whether to add `ksStoreId` to list queries |
| `pageSize` | `number` | Initial page size before persisted override |
| `mapRecord` | `(record) => card` | Maps `KbInputRecord` to browser card display |
| `onSelect` | `(record) => void` | Called when the browser selects a record |
| `onResultsChange` | `({ results, total, page }) => void` | Optional list callback |
| `onError` | `(error) => void` | Optional load error callback |

### Settings persisted per instance

| Setting | Default |
|---------|---------|
| `pageSize` | `50` |
| `listWidth` | component default width |

Persistence is keyed by `instanceKey`, so one page’s settings do not affect another page.

Examples:

- `topic-tree`
- `provision-tree`
- `inputs-mgmt`
- `metrics-record-browser`
- `doc-structure-record-browser`
- `chunks-record-browser`

---

## Search Dialog Changes

`kb-input-search-dialog.svelte` was updated so the browser can round-trip filter state.

### Behavior changes

- accepts `initialFilters`
- returns both the selected record and the active filters to the browser
- keeps filter values stable across repeated searches

### Overlay fix

The search dialog overlay was changed from `position: absolute` to `position: fixed`.

This fixes a regression where the dialog appeared embedded inside the record list instead of as a popup overlay.

---

## Shared Query Helpers

`topic-tree-record-browser.js` now contains browser-neutral helpers used by the shared record browser:

- `createDefaultRecordBrowserFilters()`
- `hasActiveRecordBrowserFilters(filters)`
- `buildTopicTreeListParams(...)`
- `resolveSelectedRecordId(...)`

Despite the filename, this helper is now used beyond the topic tree pages and acts as the shared `kb.inputs` browser query/selection helper.

---

## Migration Pattern

Two page shapes were migrated.

### 1. Tree-style pages

These pages already had a simple two-pane structure:

- left: record list
- right: record-specific tree / viewer

They were migrated by directly replacing the old left pane with `KbInputRecordBrowser`.

Pages:

- Summary Tree
- Document Semantic Tree
- Provision Tree

### 2. Three-pane pages

These pages had mixed responsibilities in the old left pane, so they were reshaped into:

- left: shared record browser
- middle: page-specific domain list
- right: document / PDF viewer

Pages:

- Metrics
- Document Structure
- Chunks

`Document Details` also uses the shared browser, but keeps a simpler browser-to-inspector flow.

---

## Layout Outcomes

### Document Details

- left: `KbInputRecordBrowser`
- right: document details / raw lines / PDF inspector

### Metrics

- left: `KbInputRecordBrowser`
- middle: metric list
- right: document / source inspector

### Document Structure

- left: `KbInputRecordBrowser`
- middle: corrected structure lines list
- right: document / PDF viewer

### Chunks

- left: `KbInputRecordBrowser`
- middle: chunk list
- right: document / PDF viewer

---

## Testing

### Automated

These tests were added or updated:

- `node --test src/lib/components/home3/topic-tree-record-browser.test.js`
- `node --test src/lib/components/home3/kb-input-record-browser-settings.test.js`

### Manual checks

For any migrated page:

1. Open the page under `home3/knowledge`
2. Verify the left browser shows:
   - `Record ID`
   - `Search`
   - `Reset`
   - `Settings`
3. Verify `Search` opens a popup dialog
4. Verify filtering enables `Reset`
5. Verify pagination appears when there are multiple pages
6. Verify drag-to-resize works
7. Verify `Settings` persists page size and width
8. Verify the first record auto-selects after list load
9. Verify page-specific settings stay isolated by view

---

## Current Status

### Functionally complete

The reusable left-side record browser is implemented and integrated into the main `kb.inputs`-driven knowledge views listed above.

### Still pending

- cleanup of old unused CSS left behind in several migrated files
- broader UI regression pass across all migrated screens
- optional renaming of `topic-tree-record-browser.js` to a more neutral filename

The feature refactor is complete from a behavior and integration standpoint, but the style-cleanup pass remains.

---

## Design Notes

A deliberate boundary was kept during this refactor:

- the record browser is reusable
- the rest of each page remains page-specific

This keeps the abstraction small and useful. It avoids over-generalizing the middle and right panes, which differ meaningfully across:

- document details
- metrics provenance
- structure editing
- chunk inspection
- summary/topic/provision trees

That boundary made it possible to share the `kb.inputs` workflow everywhere without forcing the downstream views into a brittle mega-component.
