# Fix & Enhancement: Import Inputs "View" Dialog

**Date:** 2026-06-12  
**File:** `ChenWeb/web/src/lib/components/home3/kb-import-view.svelte`  
**Component:** Dialog opened by the "View" button in the Import Inputs table (`/home3/knowledge?dark=1`)

---

## Summary of Changes

The "View" dialog went through four rounds of fixes and improvements in a single session:

1. Scrollbar + resize support
2. Horizontal resize fix + all-fields display
3. Resize-disappear bug fix + full record view (not just `status`)
4. Recursive nested-JSON display + layout cleanup

---

## Round 1 — Scrollbar & Resize

### Problems
- Dialog grew to arbitrary height, overflowing off-screen with 12+ status entries.
- Not resizable.

### Root Causes
- Tailwind `overflow-hidden` clipped content but provided no scroll mechanism.
- No `max-height` on the dialog.
- No `resize` CSS property.

### Fixes

**Dialog container** — removed `w-full max-w-4xl overflow-hidden`; replaced with:
```
display:flex; flex-direction:column;
max-height:calc(100vh - 48px);
overflow:hidden;
resize:both;
min-width:480px; min-height:200px;
```
- `overflow:hidden` still allows `resize` — CSS `resize` is blocked only by `overflow:visible`.
- `flex-direction:column` enables the fixed-header / scrolling-body layout.

**Header** — added `flex-shrink:0` so only the content area scrolls.

**Content area** — added `flex:1; overflow-y:auto; min-height:0;` so the body fills remaining space and scrolls.

**Readable entries list** — added `overflow-y:auto; flex:1; min-height:0;` to allow independent scrolling within the left column.

**Raw JSON `<pre>`** — `overflow-y` changed from conditional (`statusDialogHasOverflow ? 'auto' : 'hidden'`) to always `auto`.

---

## Round 2 — Horizontal Resize Fix + All Entry Fields

### Problems
- Horizontal resize did not work.
- The "Readable" panel showed only 6 hardcoded fields (`operation`, `proc_status`, `start_time`, `time`, `status`, `error`). Many fields were hidden (`ms_used`, `progress`, `num_lines`, `num_pages`, `input_filename`, etc.).

### Root Causes
- Tailwind `w-full` forces `width:100%`, which prevents the browser's resize handle from growing the element horizontally.
- The Readable panel had a static field list instead of iterating `Object.entries(item)`.

### Fixes

**Dialog width** — removed `w-full max-w-4xl`; replaced with explicit initial width:
```
width:min(896px, calc(100vw - 48px));
```
This gives a concrete starting width that `resize:both` can freely modify.

**Readable field list** — replaced 6 hardcoded rows with a dynamic loop:
```svelte
{#each Object.entries(item as Record<string, unknown>) as [key, val]}
    <span>{key}</span>
    <span>{val === null ? '' : typeof val === 'object' ? JSON.stringify(val) : String(val)}</span>
{/each}
```
All fields in each status entry now render automatically.

---

## Round 3 — Resize-Disappear Bug Fix + Full Record View

### Problems
- After resizing, the dialog disappeared.
- The dialog only showed the `status` array. The user wanted all fields of the full `KbInputRecord`.

### Root Cause (disappear bug)
The backdrop used `onclick={closeStatusDialog}`. When the user finished dragging the resize handle and released the mouse outside the dialog, a click event fired on the backdrop, closing the dialog.

### Fix (disappear bug)
Switched backdrop from `onclick` to `onmousedown` with a target check — same pattern already used in the Restart dialog:
```svelte
onmousedown={(e) => { if (e.target === e.currentTarget) closeStatusDialog(); }}
```
The dialog's own event stopper was also changed from `onclick` to `onmousedown` for consistency.

Also changed `Escape`/`Enter`/`Space` keydown handler to only close on `Escape` (Enter/Space on a backdrop have no UX intent here).

### Fix (full record view)

**State** — added `statusDialogRecord = $state<KbInputRecord | null>(null)`.

**`openStatusDialog`** — now stores the full record and uses the full record as the Raw JSON source:
```typescript
statusDialogRecord = record;
statusDialogRawJson = JSON.stringify(record, null, 2);
```

**`closeStatusDialog`** — resets `statusDialogRecord = null`.

**Template** — Readable panel restructured into two sections:
1. **Record Fields** — all fields except `status` and `doc_metadata`, rendered as key/value pairs.
2. **Status** — the pipeline stage entries (Entry #1, #2, …) using `Object.entries` for all fields.

---

## Round 4 — Recursive Nested-JSON Display + Layout Cleanup

### Problems
- Fields containing embedded JSON objects (e.g., `metadata` inside Doc Metadata) displayed as a raw JSON string blob instead of an expanded key/value tree.
- The Raw JSON panel was redundant and consumed half the width.
- Default dialog width was too narrow.

### Decisions

**Remove Raw JSON panel** — the full record JSON is available elsewhere; the readable view is more useful than a duplicate raw dump.

**Add Doc Metadata section** — a dedicated section between Record Fields and Status, rendering the `doc_metadata` object's fields. `doc_metadata` is excluded from the Record Fields section to avoid duplication.

**Recursive flattening** — both Record Fields and Doc Metadata sections now use a `flattenNestedForDisplay` function that walks the object tree and produces a flat `FlatRow[]`:

```typescript
type FlatRow = { key: string; value: string | null; depth: number };
```

- `value === null` → section header (object or non-primitive array): key shown bold in `textSecondary`, no value column.
- `value !== null` → leaf: key in `textMuted`, value in `textPrimary`.
- `depth` → left padding = `depth * 16px`.
- JSON-string values that parse as objects/arrays are expanded automatically (`tryParseJsonLike`).
- Arrays of primitives are shown inline (comma-joined).
- Empty objects/arrays show `{}` / `[]`.

**Layout** — removed the two-column grid; content is now a single scrollable column (`space-y-4`).

**Dialog default width** — increased from `min(896px, …)` to `min(1046px, …)` (+150 px).

---

## Final Dialog Structure

```
┌─ Dialog (resizable, max-height: 100vh - 48px, default width: 1046px) ──────────┐
│ Header: "Record ID: {id}"                                      [Close]         │
├─────────────────────────────────────────────────────────────────────────────── │
│ (scrollable body)                                                              │
│                                                                                │
│  Record Fields                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ id          416                                                         │   │
│  │ name        std_1503937.pdf                                             │   │
│  │ ...         ...                                                         │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                │
│  Doc Metadata (N fields)                                                       │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ title       农村生活垃圾分类处理规范                                        │   │
│  │ metadata    (section header)                                            │   │
│  │   source    (section header)                                            │   │
│  │     url     —                                                           │   │
│  │   keywords  []                                                          │   │
│  │ ...                                                                     │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                │
│  Status (14 entries)                                                           │
│  ┌─ Entry #1 ─────────────────────────────────────────────────────────────┐    │
│  │ operation   parsed                                                     │    │
│  │ ms_used     108921                                                     │    │
│  │ ...                                                                    │    │
│  └────────────────────────────────────────────────────────────────────────┘    │
└────────────────────────────────────────────────────────────────────────────────┘
```

---

## Dead Code Left in Place

- `statusDialogHasOverflow` state and its `ResizeObserver` — harmless; can be removed in a future cleanup pass.
- `statusDialogRawJson` state — still set in `openStatusDialog` but no longer rendered. Can be removed together with the above.
