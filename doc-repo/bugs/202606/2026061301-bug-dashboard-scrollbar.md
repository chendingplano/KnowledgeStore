# Bug 2026061301 — Doc Processor Dashboard: spurious window scrollbar + white blank area

**Date:** 2026-06-13 \
**Status:** Fixed \
**Component:** Web / Home3 — Doc Processor Dashboard (Manual Launch) \
**Severity:** Minor (visual / layout) \
**Tags:** bug, scrollbar, white blank area
---

## Symptom

On the **Dashboard → Doc Processor** view, after clicking **Search** and selecting a
`kb.inputs` record (so the "Processors to run" section renders), a **document-level
(window) scrollbar** appeared and scrolling down revealed a **white blank area** below
the footer.

The app is designed to be fully contained in `height:100vh` with only the `main`
content panel scrolling internally — the window itself should never scroll.

### Reproduction
1. Dashboard → Doc Processor.
2. Click **Search**, select one record (e.g. `record_id = 416`).
3. A new window scrollbar appears; scrolling down shows a white strip below the footer.

Earlier red herrings while diagnosing:
- It seemed tied to clicking a specific checkbox ("chunking" fine, "static_analyzer"
  broke). It was **not** the checkbox — both render through the same `{#each}` loop and
  the same `bind:checked={processors[proc.id]}` binding. Clicking a *lower* checkbox just
  required scrolling, which is what revealed the pre-existing white strip.
- Console warnings (`aria-hidden` on the search overlay, missing form-field `id`,
  `@import` ordering) were **not** the cause — no runtime errors were involved.

---

## Root Cause

The processor checkboxes use Tailwind's `class="sr-only"` (visually-hidden utility),
and **`sr-only` sets `position: absolute`**.

None of the checkbox inputs' ancestors (`main`, the rail/content row, the app root) was
`position: relative` — they were all `position: static`. Per CSS, an `absolute` element
is positioned relative to its nearest **positioned** ancestor; with none present, it
anchors to the **initial containing block (`<html>`)** and **ignores every
`overflow:hidden`/`auto` clip in between**.

So each absolute `sr-only` `<input>` sat at its natural flow position. When a record is
selected, the full ~12-row checkbox list renders and the lower inputs land at
`top: 1468px … 1855px` — **below the 1437px viewport**. `main`'s `overflow-y-auto` could
not clip them (they were not its containing-block descendants), so they extended `<html>`
to ~1856px → the window scrollbar and white strip.

### Diagnostic evidence (DevTools)

Walking the ancestor chain of the oversized content showed every container correctly
clipped to the viewport (`main` `scrollH=2219`/`offH=1237`, app root `offH=1437`,
`body scrollH=1437`) — **only `<html>` overflowed** (`scrollH=1856`). That signature
(body fine, html overflowing) is the tell-tale of an `absolute` element whose containing
block is `<html>` rather than `<body>`. Enumerating elements extending below the viewport
identified them precisely:

```
INPUT.sr-only  pos:absolute  offsetParent:BODY  top:1468 … 1855  bottom:…1856
```

---

## Fix

Give the scroll container `position: relative` so the absolute `sr-only` inputs anchor to
`main` and scroll/clip **with** its content instead of escaping to `<html>`.

`web/src/lib/components/home3/content-panel.svelte` (the `<main>` element):

```diff
-	class="flex-1 overflow-y-auto flex flex-col min-w-0"
+	class="relative flex-1 overflow-y-auto flex flex-col min-w-0"
```

This targets the root cause (a missing containing block), so any view rendered in `main`
that uses `sr-only` or other stray `absolute` elements is now contained.

### Why it is safe
- The dashboard's own absolute elements (pie-chart label, PDF progress bars) already have
  `relative` parents, so their anchoring is unchanged.
- `position: relative` does **not** create a containing block for `position: fixed`, so
  the confirm dialog, toast, and floating tooltip (all `fixed`) are unaffected.
- `relative` keeps `main` in normal flow — no impact on the flex layout.

### Verification
After a hard refresh, selecting a record no longer produces a window scrollbar or white
area; the processor list scrolls inside the panel. Re-running the diagnostic shows
`<html>` `scrollH == innerHeight` and the `INPUT.sr-only` elements report
`offsetParent: MAIN`.

---

## Related fixes (found while diagnosing; not the cause)

These are genuine bugs discovered during investigation and fixed in the same pass:

- **`web/src/lib/components/home3/kb-input-search-dialog.svelte`**
  - Added an `$effect` that resets `statusDialogOpen`/`statusDialogRecord` when the search
    dialog's `open` becomes false. The status/detail view-dialog lives in a top-level
    `{#if statusDialogOpen}` block *outside* `{#if open}`, so it could otherwise remain
    mounted after the parent dialog closed.
  - Removed the hardcoded `aria-hidden="true"` on the open search overlay (it was flagged
    by the browser because a focused button lived inside an `aria-hidden` ancestor).

- **`web/src/lib/components/home3/doc-processor-dashboard-view.svelte`**
  - `toggleAll()` ("Deselect all") now also clears `parseFileChecked` / `convertChecked`,
    keeping the optional pre-processors consistent with the main processor list.

---

## Lessons / Notes

- `sr-only` is `position: absolute`. In a layout that relies on an internal scroll
  container (`overflow-y-auto`) inside a clipped `100vh` shell, **the scroll container
  should be `position: relative`** so visually-hidden inputs (and any other stray
  `absolute` children) are contained rather than leaking to `<html>`.
- Signature to remember: when `<body>.scrollHeight` is fine but `<html>.scrollHeight`
  overflows, look for an `absolute` element with no positioned ancestor
  (`offsetParent === BODY/NULL`).
