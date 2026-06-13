# Spec: Doc Processor Dashboard — KB Input Search Dialog

**Date:** 2026-06-12
**File:** `ChenWeb/web/src/lib/components/home3/kb-input-search-dialog.svelte`
**Component:** Dialog opened by the "Search" button in the Doc Processor Dashboard (`/home3` → Doc Processor)

---

## Summary of Changes

Two modifications to the KB Input Search Dialog results table:

1. **Remove "Parser" column** — the `PARSER` column was removed from both the table header and every result row.
2. **Add "Detail" column** — a new `DETAIL` column was added to the right of `UPDATED`. Each row gets a "View" action button that opens the full record detail dialog.

---

## Change 1 — Remove "Parser" Column

### Before

Table header had eight data columns (after the checkbox):

```
ID | TYPE | TITLE / DOC NO | FILE NAME | PARSER | STATUS | CREATED | UPDATED
```

Each row included:

```svelte
<td class="mono muted">{record.parser_name || '—'}</td>
```

### After

The `PARSER` column header (`<th>Parser</th>`) and its corresponding `<td>` are removed entirely.

The `searchParserName` filter state and the "Parser name" dropdown in the Processing Status section are **not** affected — the search filter still sends `parserName` to the API. Only the results table display column is removed.

---

## Change 2 — Add "Detail" Column with "View" Button

### Table header

```svelte
<th>Detail</th>
```

Added after `<th>Updated</th>`.

### Table row

```svelte
<td>
    <button
        class="view-btn"
        onclick={(e) => { e.stopPropagation(); openStatusDialog(record); }}
    >
        View
    </button>
</td>
```

The `e.stopPropagation()` prevents the row's toggle-selection `onclick` from firing when the button is clicked.

---

## Detail Dialog

The "View" button opens a record detail dialog that is a direct port of the dialog in `kb-import-view.svelte` (documented in `doc-2026061203-bug-input-view-dialog`), adapted to the search dialog's dark color scheme.

### State added to `kb-input-search-dialog.svelte`

```typescript
let statusDialogOpen = $state(false);
let statusDialogRecord = $state<KbInputRecord | null>(null);
let statusDialogTitle = $state('');
let statusDialogItems = $state<KbInputRecord['status']>([]);
```

### Derived state

```typescript
let statusDialogRecordRows = $derived.by((): FlatRow[] => { … });
let statusDialogDocMeta    = $derived.by((): FlatRow[] => { … });
```

Both use the same `flattenNestedForDisplay` / `tryParseJsonLike` helpers copied from `kb-import-view.svelte`.

### Open / close handlers

```typescript
function openStatusDialog(record: KbInputRecord) {
    statusDialogRecord = record;
    statusDialogItems  = record.status ?? [];
    statusDialogTitle  = `Record ID: ${record.id}`;
    statusDialogOpen   = true;
}

function closeStatusDialog() {
    statusDialogOpen   = false;
    statusDialogRecord = null;
}
```

### Dialog structure

```
┌─ Detail Dialog (resizable, z-index:50, width: min(1046px, 100vw-48px)) ──────┐
│ Header: "Record ID: {id}"                                        [Close]      │
├───────────────────────────────────────────────────────────────────────────────│
│ (scrollable body)                                                             │
│                                                                               │
│  RECORD FIELDS                                                                │
│  ┌─────────────────────────────────────────────────────────────────────────┐  │
│  │ id          416                                                         │  │
│  │ name        std_1503937.pdf                                             │  │
│  │ …           …                                                           │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
│                                                                               │
│  DOC METADATA (N fields)                                                      │
│  ┌─────────────────────────────────────────────────────────────────────────┐  │
│  │ title       农村生活垃圾分类处理规范                                       │  │
│  │ metadata    (section header — nested)                                   │  │
│  │   source    (section header)                                            │  │
│  │     url     —                                                           │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
│                                                                               │
│  STATUS (N entries)                                                           │
│  ┌─ Entry #1 ──────────────────────────────────────────────────────────────┐  │
│  │ operation   parsed                                                      │  │
│  │ ms_used     108921                                                      │  │
│  │ …           …                                                           │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────────────┘
```

### Dialog behavior

| Behavior | Implementation |
|---|---|
| Close on backdrop | `onmousedown` with target check (not `onclick`) to avoid false close on resize drag-end |
| Close on Escape | `onkeydown` handler on the overlay |
| Resizable | `resize: both` on the dialog; initial width `min(1046px, calc(100vw - 48px))` |
| Scrollable body | `flex: 1; overflow-y: auto; min-height: 0` |
| Z-index | `50` — above the search dialog overlay (`25`) |

### Color scheme

The detail dialog reuses the search dialog's existing dark palette (hardcoded, no CSS variables):

| Role | Value |
|---|---|
| Dialog background | `#111827` |
| Surface (rows/entries) | `#1a202b` |
| Border | `rgba(148, 163, 184, 0.12)` |
| Text primary | `#f3eedf` |
| Text secondary / key | `#9ca3af` |
| Text muted / header key | `#b5ae94` |

### "View" button style

```css
.view-btn {
    height: 24px;
    padding: 0 10px;
    border: 1px solid rgba(148, 163, 184, 0.16);
    border-radius: 6px;
    background: rgba(255, 255, 255, 0.04);
    color: #9ca3af;
    font-size: 11px;
    font-family: 'JetBrains Mono', monospace;
}

.view-btn:hover {
    background: rgba(212, 162, 76, 0.12);
    color: #d4a24c;
    border-color: rgba(212, 162, 76, 0.3);
}
```

---

## Related Documents

- `doc-2026061203-bug-input-view-dialog` — original detail dialog design and fix history in `kb-import-view.svelte`
