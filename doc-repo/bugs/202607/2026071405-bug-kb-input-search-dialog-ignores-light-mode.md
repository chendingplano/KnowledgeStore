# Bug: the kb.inputs search dialog owns a dark palette instead of inheriting one

Date: 2026-07-14\
Status: fixed-unverified — builds and type-checks; **not yet exercised in a browser**
(the data-populated surfaces need an authenticated backend; see "Still worth doing")\
System: `ChenWeb` web frontend (SvelteKit), the `Find a record` search dialog reached
from the `Search` button of every view that embeds the kb.inputs record browser, plus
three other hosts that open it directly\
Component: `web/src/lib/components/home3/kb-input-search-dialog.svelte`\
Related: [doc-2026071403-bug-record-browser-owns-a-palette-instead-of-inheriting-one](2026071403-bug-record-browser-owns-a-palette-instead-of-inheriting-one.md)
(named this as an open audit item), [doc-2026071404-bug-doc-structure-line-cards-ignore-light-mode](2026071404-bug-doc-structure-line-cards-ignore-light-mode.md)
(re-recorded it as still open), [doc-2026071401-bug-light-dark-mode-not-carried-from-semos-to-home3](2026071401-bug-light-dark-mode-not-carried-from-semos-to-home3.md)
(made it reachable)

## Summary

`kb-input-search-dialog.svelte` — the full-screen `Find a record` dialog and its nested
record-detail dialog — read no theme tokens and took no `darkMode` prop. Every colour in
its `<style>` block was a hardcoded dark literal (`#111827` panel, `#f3eedf` cream text,
`#9ca3af` labels, `#1a202b`/`#2a3140` field and input surfaces, `#d4a24c` brass, the
`#181d27` table header, and so on). In light mode it therefore stayed a dark slab floating
over a cream page, and some of its text was outright invisible there — the `Cancel`/`Reset`
ghost buttons were a dark `rgba(15,23,42,0.36)` fill regardless of mode, the operation
status chip was cream `#d7cfbb` text on a near-transparent white fill, and the error text
was a light pink (`#fca5a5`) chosen for a dark background.

This is the fourth instance of the one rule doc-2026071402/403/404 established, and the last
open item the record-browser fix named: **a component embedded in more than one host must
inherit the host's design tokens, not mint its own palette.** doc-2026071403 fixed the
record browser this way; doc-2026071404 closed out the nine host content columns; both
explicitly left this dialog — opened by the record browser's `Search` button — untouched and
"very likely broken in light mode." It was.

## Symptom

1. Open any `/home3` view in light mode, select a knowledge store, and click `Search` in the
   kb.inputs record column.
2. The `Find a record` dialog opens as a dark `#111827` panel over the cream page — a
   different design language from the letterpress page behind it.
3. The `RECORD ID` / `Title` / date inputs are dark slabs; `Reset`/`Cancel` are dark ghost
   buttons; the results table header and rows are dark.
4. Clicking `View` on a result opens the record-detail dialog, equally dark.

## Root Cause

The same shape as doc-2026071403, in a component that was simply never converted. The
dialog neither accepted a `darkMode` prop nor read any of the host token vocabulary
(`--panel-bg`, `--panel-bg-alt`, `--ink-line`, `--ink-line-soft`, `--text-primary`,
`--text-secondary`, `--brass`, `--crimson`). All of its rules hardcoded dark hex/rgba
literals directly, so light mode had no effect on it whatsoever.

Because the literals were constants, they could not depend on `darkMode` and could not flip
— exactly the failure mode of doc-2026071404's persisted `#1C212C`, only here the value was
frozen in the CSS itself rather than in stored state, so no migration was needed.

### Why the palette could never have been right

The dialog is embedded in four hosts:

- `kb-input-record-browser.svelte` (the record column shared by all nine `/home3` views),
  which — since doc-2026071403 — is itself a token consumer sitting inside a letterpress
  host. Its host's tokens cascade straight into the dialog's fixed overlays.
- `doc-processor-dashboard-view.svelte`, `kb-import-view.svelte`, and
  `document-review-view.svelte`, which theme themselves with per-component JS colour
  variables and define **no** `--panel-bg`-style tokens at all.

A single hardcoded palette cannot be correct across a letterpress host and three token-less
ones, in two colour schemes. The dialog has to inherit where tokens exist and fall back to a
theme-aware default where they do not.

## Fix

The dialog no longer has a palette. It has host-token aliases with theme-aware fallbacks,
exactly as the record browser does.

1. **New `darkMode` prop** (default `true`, matching the record browser and the three other
   hosts), threaded in from all four call sites.
2. **`--sd-*` aliases on both overlay roots.** A `$derived` `tokenStyle` string is applied to
   `.dialog-overlay` and to `.view-dialog-overlay` (the two independent fixed roots). Each
   alias prefers the host token and falls back to a theme-aware `$derived` value:

   ```svelte
   --sd-panel:  var(--panel-bg,      ${panel});
   --sd-accent: var(--brass,         ${accent});
   --sd-text:   var(--text-primary,  ${text});
   ```

   Because the overlays are DOM descendants of the record-browser shell (which reads the host
   tokens but does not re-declare them), the host's `--panel-bg` / `--brass` / … cascade into
   the fixed overlays despite `position: fixed`. Twenty-one aliases cover surfaces, lines,
   text, accent, error/scope colours, and the input/results/table/hover/ghost/chip/disabled
   surfaces that have no matching host token (those are plain `$derived`, driven by
   `darkMode`).
3. **Every rule reads `--sd-*`.** All dark hex/rgba literals are gone from the `<style>`
   block. What remains is deliberately mode-neutral and matches the categories the sibling
   fixes kept: the modal scrims (`rgba(2,6,23,…)`), brass tints (`rgba(212,162,76,…)`), dark
   ink on brass buttons (`#15110a`), translucent white/black sheens, and the semantic
   success/fail status pills (`#5dafa8` / `#c8553d`).

### What this produces per host

- **Record-browser host (all nine `/home3` views):** the host tokens win, so the dialog
  repaints to letterpress in both modes — cream in light, `#161A22`-family in dark — matching
  the page behind it. Its dark appearance is therefore *intentionally* no longer the old
  `#111827`; it now matches its host, which is the entire point of the rule.
- **`doc-processor-dashboard`, `kb-import`, `document-review`:** no host tokens exist, so the
  `darkMode`-driven fallbacks apply. Every fallback's dark branch equals the literal it
  replaced, so **dark mode in these three hosts is byte-identical**; only light mode changes.

## Verification

- `npx svelte-check --tsconfig ./tsconfig.json`: 0 errors (23 warnings in 12 files —
  unchanged baseline).
- `npx vite build`: succeeds.
- Grep audit: no un-tokenized `#hex` / `rgba(` literals remain in the `<style>` block beyond
  the intentional mode-neutral set listed above.
- Alias audit: the set of `var(--sd-*)` referenced in the style block is identical to the set
  defined in `tokenStyle` (21 each) — no misspelled alias silently resolving to `initial`.
- **Not yet exercised in a browser.** As doc-2026071404 recorded, the Playwright context is
  unauthenticated and `kb.inputs` returns `500`, so the populated results table and the
  record-detail dialog cannot be loaded with real data there.

### Still worth doing

- Open the dialog in light mode against an authenticated backend and confirm computed styles
  through the real cascade on: the results table (header `--sd-th-bg`, rows, hover
  `--sd-row-hover`, selected row), the status chips/pills, and the `View` record-detail
  dialog (`--sd-surface` boxes, keys/values). The empty-state, controls, inputs, buttons and
  footer render without a backend and can be checked immediately; only the data-populated
  surfaces are blocked.
- Confirm the record-browser host actually repaints the dialog to letterpress (host-token
  path) while one of the three token-less hosts keeps dark byte-identical (fallback path) —
  the two code paths that this fix trades on.

## Change Record

Files changed:
- `web/src/lib/components/home3/kb-input-search-dialog.svelte` (prop + token block + full
  `<style>` tokenization)
- `web/src/lib/components/home3/kb-input-record-browser.svelte` (pass `{darkMode}`)
- `web/src/lib/components/home3/doc-processor-dashboard-view.svelte` (pass `{darkMode}`)
- `web/src/lib/components/home3/kb-import-view.svelte` (pass `{darkMode}`)
- `web/src/lib/components/home3/document-review-view.svelte` (pass `{darkMode}`)

## Documentation Impact

What knowledge changed:
- The audit doc-2026071403 opened and doc-2026071404 continued is now, in code, **complete**:
  the record column, the nine host content columns, and the search dialog reached from them
  all inherit the host palette. The one caveat is that this last piece is `fixed-unverified`,
  not `fixed-verified`.
- A component that renders `position: fixed` overlays still inherits CSS custom properties
  from its DOM ancestors — visual detachment does not sever the token cascade. This is why the
  `--sd-*` aliases can prefer the host's `--panel-bg` even though the dialog paints over the
  whole viewport.
- The four hosts of this dialog split into two theming worlds: the record browser is a
  token-consuming letterpress citizen, while `doc-processor-dashboard`, `kb-import`, and
  `document-review` still theme with per-component JS colour variables and expose no tokens.
  A shared component they all embed must handle both — inherit-or-fallback, keyed on
  `darkMode`.

Docs affected / updated:
- This bug report.
- `bugs/OPEN.md` — the free-standing "`kb-input-search-dialog.svelte` … never investigated"
  item is replaced by a pointer to this doc, carried as `fixed-unverified`.

Stale docs:
- doc-2026071403 and doc-2026071404 each end with an "intentionally left undocumented" note
  saying this dialog is unfixed. Those notes are now historical, not current; this doc
  supersedes them. Left as-is (they were true when written).

Intentionally left undocumented / not fixed:
- The heavy dialog drop shadows and the modal scrims are tuned for a dark page and are heavier
  than a light theme wants. Cosmetic; out of scope, as in doc-2026071402/404.
- The semantic success/fail status pills keep their teal/crimson literals; they read
  acceptably in both schemes and are not part of the panel palette.
