# Category Review GUI — Implementation Notes

## Overview

Category Review is the human-curation front end for the **inventory category
ontology** (`kb.inventory_categories`). The Extract Inventory Items processor
mints new categories as `pending_review` when it encounters item types the
ontology has never seen. This GUI lets a reviewer triage those pending
categories — fill in their schema bodies (`required_attrs`, `specs`,
`plausible_ranges`) and then **approve**, **reject**, or **merge** them.

The view lives inside the ChenWeb web app at `/home3/knowledge`, under the
**Document Processing** menu group, as a sibling of **Document Chunking**.

It is a registry-management view, not a per-document/per-record view: the
ontology is global, so the screen does **not** require an active knowledge
store to be selected.

**Spec:** `doc-processor/extract-inventory-items-spec.md` → section
"Category Review" (and "APIs")
**Component:** `ChenWeb/web/src/lib/components/home3/category-review-view.svelte`
**Service:** `ChenWeb/web/src/lib/services/kbService.ts`
**Backend (pre-existing):**
`ChenWeb/server/api/kbhandler/inventory_category_handler.go`

---

## Files Changed

| File | Change |
|------|--------|
| `ChenWeb/web/src/lib/components/home3/category-review-view.svelte` | **New** — the Category Review master-detail view |
| `ChenWeb/web/src/lib/services/kbService.ts` | Added inventory-category types + `listInventoryCategories` / `updateInventoryCategory` |
| `ChenWeb/web/src/routes/home3/knowledge/+page.svelte` | Wired the view into the Document Processing menu group and content switch |

No backend changes were needed — the REST endpoints already existed.

---

## Backend Contract (consumed, not modified)

The GUI talks to two endpoints already implemented in
`inventory_category_handler.go` and registered in `server/api/routes.go`:

```text
GET   /api/v1/kb/inventory-categories?status=pending_review&limit=N
PATCH /api/v1/kb/inventory-categories/:key
```

### List response shape

```jsonc
{
  "status": true,
  "results": [
    {
      "category_key": "medical_device",
      "status": "pending_review",
      "canonical_of": "",
      "display_names": ["medical_device", "医疗器械"],
      "required_attrs": [],
      "specs": { "power": { "canonical_unit": "w", "aliases": ["watt"] } },
      "plausible_ranges": { "power": { "min": 1, "max": 100000, "unit": "w" } },
      "seen_count": 12
    }
  ],
  "total": 1
}
```

When `status=pending_review`, the server orders results by `seen_count`
descending (highest-impact first). Other status values use a plain
status-filtered list; omitting `status` returns all categories.

### PATCH request body (all fields optional)

```jsonc
{
  "status": "approved",                  // approved | rejected | merged | pending_review
  "canonical_of": "pump",                // surviving key when merging
  "required_attrs": ["manufacturer", "power"],
  "specs": { "power": { "canonical_unit": "w", "aliases": ["watt"] } },
  "plausible_ranges": { "power": { "min": 1, "max": 100000, "unit": "w" } }
}
```

Only supplied fields are updated. The handler returns the updated record under
`{ "status": true, "result": { ... } }`.

Errors come back as `{ "status": false, "error_msg": "..." }`, matching the
shared `fetchOrThrow` helper convention used across `kbService.ts`.

---

## Service Layer (`kbService.ts`)

Added near the end of the file, after `stopKbInput`.

### Types

| Type | Mirrors (Go) |
|------|--------------|
| `InventoryCategoryStatus` | `pending_review \| approved \| rejected \| merged` |
| `InventorySpecSchema` | `docprocessing.InventorySpecSchema` (`canonical_unit`, `aliases`) |
| `InventoryPlausibleRange` | `inventoryPlausibleRangeJSON` (`min?`, `max?`, `unit?`) |
| `InventoryCategoryRecord` | `inventoryCategoryResponse` |
| `UpdateInventoryCategoryPayload` | `patchInventoryCategoryRequest` |

### Functions

```ts
listInventoryCategories(
  status: InventoryCategoryStatus | 'all' = 'pending_review',
  limit = 100
): Promise<ListInventoryCategoriesResponse>

updateInventoryCategory(
  key: string,
  payload: UpdateInventoryCategoryPayload
): Promise<{ status: boolean; result: InventoryCategoryRecord }>
```

- `listInventoryCategories` uses the shared `fetchOrThrow` GET helper; `status`
  of `'all'` omits the query param so the server returns every category.
- `updateInventoryCategory` issues a `PATCH` with a JSON body and unwraps
  `error_msg` on failure.

---

## Component (`category-review-view.svelte`)

### Props

```ts
let { darkMode = true }: { darkMode?: boolean } = $props();
```

Pure Svelte 5 runes (`$state`, `$derived`, `$effect`). No external store
dependency — the registry is global.

### Layout

A three-band master-detail screen:

1. **Header** — title, description, and a Refresh button (spinning icon while
   loading).
2. **Status filter tabs** — `Pending Review` (default), `Approved`, `Rejected`,
   `Merged`, `All`. Switching a tab re-fetches the list.
3. **Body** — three columns:
   - **Master list** (left, fixed `340px`): one row per category showing
     `category_key` (monospace), a status pill, `seen_count`, and the surface
     form count. Sorted server-side by `seen_count` for the pending tab.
   - **Category Under Review** (centre, `flex-1`, scrollable): the working copy
     of the selected category — same editable sections as before.
   - **Related Categories** (right, fixed `360px`): subdivided into an upper
     ranked list and a lower detail pane (see below).

### Detail editor sections (Category Under Review)

| Section | Source field | Editable | Notes |
|---------|--------------|----------|-------|
| Display Names | `display_names` | No | Observed surface forms (read-only chips) |
| Required Attributes | `required_attrs` | Yes | Chip add/remove; Enter adds |
| Spec Definitions | `specs` | Yes | Table of `name`, `canonical_unit`, `aliases` (comma-sep) |
| Plausible Ranges | `plausible_ranges` | Yes | Table of `name`, `min`, `max`, `unit` |
| Merge Into | `canonical_of` | Yes | Surviving key, required for Merge; populated by "Use as Merge Target" button |

### Related Categories panel

The right-hand panel is split 50/50 vertically:

**Upper — ranked list**

Shows the top 10 categories from the currently loaded list ranked by a
*closeness* score (descending). Closeness is computed entirely on the frontend
from data already in memory — no extra API call is made.

Closeness formula (weighted Jaccard):

| Component | Weight | Description |
|-----------|--------|-------------|
| Spec name overlap | 0.4 | Jaccard similarity of the two categories' `specs` key sets |
| Required attrs overlap | 0.2 | Jaccard similarity of the `required_attrs` arrays |
| Category key word overlap | 0.4 | Jaccard similarity of tokens produced by splitting `category_key` on `_` |

For `pending_review` categories (which typically have empty `specs` and
`required_attrs`), only the key-word component is active and the score ranges
from 0 to 0.4. Once a reviewer fills in specs and attrs for approved categories
those two components activate and provide richer signal.

Each row shows `category_key` (monospace), a status pill, `seen_count`, and the
closeness score (two decimal places). Clicking a row selects it for the lower
pane.

**Lower — related category detail**

Read-only view of the selected related category:
- Header: `category_key`, status pill, `seen_count`
- Display Names chips (same style as the editor)
- Required Attrs chips (read-only)
- Spec Definitions table (read-only text cells)
- Plausible Ranges table (read-only text cells)
- **Use as Merge Target** button — copies the related category's key into the
  editor's Merge Into field and focuses that input. This is the primary
  affordance: the reviewer can spot a closely related approved category and
  immediately queue the current one for merging.

### Working-copy model

The editor edits local `$state` copies rather than the list rows directly:

- `requiredAttrs: string[]`
- `specRows: { name; canonical_unit; aliases }[]` — `aliases` is a raw
  comma-separated string in the UI, split on save.
- `rangeRows: { name; min; max; unit }[]` — `min`/`max` are raw strings in the
  UI, parsed to numbers (or `null` when blank) on save.
- `canonicalOf: string`

`selectCategory()` re-seeds these from the chosen record. `buildSchemaPayload()`
converts them back into the API shape:

- spec/range rows with a blank `name` are dropped
- blank `min`/`max` become `null`; non-finite numbers become `null`
- aliases are trimmed and empties removed

### Actions

| Button | Payload | Behaviour |
|--------|---------|-----------|
| Save Schema | `buildSchemaPayload()` | Persists `required_attrs` / `specs` / `plausible_ranges` without changing status |
| Approve | `{ ...buildSchemaPayload(), status: 'approved' }` | Persists schema edits **and** flips status in one PATCH |
| Merge | `{ status: 'merged', canonical_of }` | Requires a non-empty, non-self target; confirms first |
| Reject | `{ status: 'rejected' }` | Confirms first |

After a successful PATCH, `applyUpdate()`:

1. patches the matching row in the local `categories` list with `result`, and
2. if the row's new status no longer matches the active filter tab (and the tab
   isn't `All`), drops it from view and advances the selection to the next row.

This mirrors the spec's read-path behaviour: an approval immediately changes how
the category surfaces, with no document reprocess required.

### State summary

- `categories`, `loading`, `loadError`, `selectedKey` — list state
- `saving`, `saveError`, `saveNotice` — editor action state
- `selected` (`$derived`) — the currently selected record
- `relatedSelectedKey` — key of the row selected in the Related Categories upper list; reset to `null` whenever `selectCategory` is called
- `relatedCategories` (`$derived`) — top-10 scored list, recomputed whenever `selected` or `categories` changes
- `relatedSelected` (`$derived`) — the full record for `relatedSelectedKey`
- `mergeTargetEl` — `bind:this` reference to the Merge Into `<input>`; used by `useAsMergeTarget()` to focus the field after copying the key
- `$effect(() => void load())` — initial load on mount; `selectFilter` triggers
  reloads on tab change

### Theme

Uses the home3 indigo design tokens (`#171B26` page, `#252A3A` panel,
`#818CF8` accent, etc.) so it visually matches the surrounding Knowledge
navigation and the Document Chunking sibling. All tokens are `$derived` on
`darkMode`, so light mode is supported. Status pills are colour-coded:
approved = green, pending = amber, rejected = red, merged = violet.

---

## Routing / Menu Wiring (`+page.svelte`)

1. **Import**: `CategoryReviewView` added alongside the other home3 views.
2. **Section id**: `'kb-category-review'` added to the `KbSectionId` union.
3. **Menu entry**: a second child under the `kb-chunks` ("Document Processing")
   parent:

   ```ts
   { id: 'kb-category-review', label: 'Category Review',
     description: 'Curate the inventory category ontology' }
   ```

4. **Accordion open state**: `selectSection` now opens
   `documentProcessingOpen` for **any** child of `kb-chunks`, not just
   `kb-chunks` itself, so selecting Category Review keeps the group expanded.
5. **No active store required**: `needsActiveStore` excludes
   `kb-category-review` (same treatment as `kb-search`), so the "No Knowledge
   Store Selected" gate does not block it.
6. **Content switch**: a new branch renders `<CategoryReviewView {darkMode} />`
   when `activeSection === 'kb-category-review'`.

Deep-linking works via the existing `?section=` query param handling, e.g.
`/home3/knowledge?section=kb-category-review`.

---

## Reviewer Workflow (end to end)

1. Open **Knowledge → Document Processing → Category Review**.
2. The **Pending Review** tab loads, highest `seen_count` first.
3. Select a category. Its observed display names are shown; the schema body is
   typically empty for a freshly minted category.
4. Fill in **Required Attributes**, **Spec Definitions**, and **Plausible
   Ranges**.
5. **Approve** (saves schema + status together), or **Reject**, or set a
   **Merge Into** key and **Merge**.
6. The row leaves the Pending tab; the change is live on the read path for all
   existing `kb.inventory_items` instances of that category — no reprocess
   needed for `category_status`.

> Per the spec: review does not require a reprocess to update `category_status`.
> Spec normalization and required-attr validation only run at extraction time,
> so early instances may still have gaps that a forced reprocess would correct.

---

## Verification

`svelte-check` reports **no errors or warnings** in the three changed files.
(Pre-existing errors elsewhere in the web app — e.g. the metric search views —
are unrelated to this change.)

---

## Closeness Upgrade Path

The current frontend-only closeness formula degrades gracefully but is weakest
for freshly-minted `pending_review` categories that have no specs or attrs yet.

If richer matching is needed, the recommended upgrade is to expose the
`embedding` vector from `kb.inventory_categories` in the list API response and
compute cosine similarity in the browser:

```ts
function cosineSim(a: number[], b: number[]): number {
    const dot = a.reduce((s, v, i) => s + v * b[i], 0);
    const magA = Math.sqrt(a.reduce((s, v) => s + v * v, 0));
    const magB = Math.sqrt(b.reduce((s, v) => s + v * v, 0));
    return magA && magB ? dot / (magA * magB) : 0;
}
```

This would replace or supplement the key-word overlap component (weight 0.4)
and make closeness meaningful even for empty pending categories, mirroring
the same embedding-based synonym matching the Go processor already performs
during post-pass curation.

---

## Related Capsules

- `doc-processor/extract-inventory-items-spec.md` — the processor that produces
  the categories and items this GUI curates
- `doc-processor/extract-categories-spec.md` — category extraction context
- `knowledge-base-window/` — the broader `/home3/knowledge` shell this view
  plugs into
