# Bug: the shared record browser mints its own palette instead of inheriting its host's

Date: 2026-07-14
Status: fixed-unverified — builds and type-checks; not yet exercised in a browser
System: `ChenWeb` web frontend (SvelteKit), all nine `/home3` views that embed the
kb.inputs record browser
Component: `web/src/lib/components/home3/kb-input-record-browser.svelte`
Related: [doc-2026071402-bug-knowledge-store-cards-ignore-light-mode](2026071402-bug-knowledge-store-cards-ignore-light-mode.md)
(same defect class), [doc-2026071401-bug-light-dark-mode-not-carried-from-semos-to-home3](2026071401-bug-light-dark-mode-not-carried-from-semos-to-home3.md)
(made it visible)

## Summary

The `kb.inputs` record browser — the left column shared by nine `/home3` views —
carried a hardcoded blue/green palette and hardcoded dark CSS. In light mode its
Record ID input, Search/Settings buttons, record cards, and settings popover all
stayed dark on a cream page. Its cards also clashed with the metrics cards
sitting immediately beside them in the same page.

Both symptoms have one cause, and it is not "the wrong colors were chosen": the
component **owns a palette** when it should **inherit one**. It is embedded in
nine different views, so no palette it picks can be right in more than one of
them.

## Symptom

On `/home3/metrics` in light mode (see `2026071403-record-browser-light-mode.png`
if attached to the issue thread):

1. The `RECORD ID` input is a dark grey slab with light text.
2. `Search` and `Settings` are dark buttons on a light panel.
3. The `kb.inputs` record cards are muddy grey rounded rectangles — visibly a
   different design language from the `Metrics` cards one column to the right,
   which are flat, sharp, letterpress-styled and correct.
4. `Retrieve` is a saturated `#22c55e` green, from a palette nothing else on the
   page uses.

## Root Cause

The component derived six colors of its own:

```js
let panelBg = $derived(darkMode ? '#161c2b' : '#ffffff');   // blue-grey
let accent  = $derived(darkMode ? '#22c55e' : '#16a34a');   // green
```

and then, on its own root element, **shadowed the host's design tokens with
them**:

```svelte
style={`... --panel-bg:${panelBg}; --panel-bg-alt:${panelAlt}; --ink-line:${border};
        --text-primary:${textMain}; ...`}
```

The host views define exactly those token names and let them cascade down. By
re-declaring them on its own root, the browser cut itself off from the cascade —
the host's values reached the element and were immediately overwritten. On top of
that, most of its CSS ignored even its own tokens and hardcoded dark literals
directly (`background: rgba(31, 41, 55, 0.9)`, `color: #f3f4f6`,
`background: #111827`, `border-color: #22c55e`), which is why light mode had no
effect on it at all.

### Why the palette could never have been right

The nine host views were surveyed. Eight of them — `metric`, `chunk`,
`doc-structure`, `summary-tree`, `provision`, `semantic-projections`, `inputs`,
`inventory-items` — define an identical "letterpress" palette:

```js
panelBg  = darkMode ? '#161A22' : '#FBF8F0';   // warm paper
brass    = darkMode ? '#D4A24C' : '#B8801E';   // accent
crimson  = darkMode ? '#C8553D' : '#A23E26';   // selected
```

Only the ninth, `kb-extraction-view`, uses the blue palette (`#161c2b` /
`#ffffff`) — which is precisely the palette the record browser hardcoded. **The
browser was styled to match one host out of nine and fought the other eight.**
That is the whole bug; the light-mode failure is a second symptom of it.

## Fix

Committed as `3718a56` in `ChenWeb`.

The component no longer has a palette. It has *fallbacks*.

1. **Stop shadowing.** The root element no longer re-declares `--panel-bg`,
   `--ink-line`, `--text-primary`, etc. The host's tokens now reach the subtree.
2. **Alias with fallbacks.** The root defines `--rb-*` aliases that prefer the
   host's token and fall back to a theme-aware default, so a host that defines
   only some tokens (as `kb-extraction-view` does — it has no `--brass`,
   `--crimson`, or `--text-primary`) still renders correctly in both modes:

   ```svelte
   --rb-panel:  var(--panel-bg,  {panelBg});
   --rb-accent: var(--brass,     {accent});
   --rb-line:   var(--ink-line,  {border});
   ```

   The fallbacks are still `$derived(darkMode ? … : …)`, so they are theme-aware
   rather than constant — the mistake the old code made.
3. **Every rule reads `--rb-*`.** All hardcoded literals are gone from the style
   block; a grep for `#hex` / `rgba(` inside `<style>` now returns nothing. This
   is what fixes the input, the `Search`/`Settings` buttons (they were
   `rgba(15, 23, 42, 0.36)` regardless of mode), the settings popover
   (`#111827`), the resizer grip, and the error box.
4. **Cards adopt the metrics treatment**, as requested — the design the user
   judged better, and now literally the same tokens as the metrics cards beside
   them: flat `--rb-panel-alt` slab, 1px `--rb-line-soft` border, no border
   radius, a 4px left rule that turns accent on hover and `--highlight` on
   select. The user-configurable highlight color is retained for selection (it is
   a feature, set from the settings popover); hover uses the host's accent.
5. **`Retrieve`** becomes the host's accent (brass in eight views) instead of
   `#22c55e`, so the primary action belongs to the page it sits on.

Net effect: the browser now takes on whichever palette embeds it. On the eight
letterpress views it becomes letterpress; inside `kb-extraction-view` it stays
blue, because that host's tokens say blue.

## Verification

- `npx svelte-check --tsconfig ./tsconfig.json`: 0 errors (23 warnings in 12
  files — unchanged baseline).
- `npx vite build`: succeeds.
- Grep audit: no `#hex` or `rgba(` literals remain in the component's `<style>`.
- **Not yet exercised in a browser, and this change is visible on nine views.**
  This is the largest unverified surface of the three theme bugs. Worth checking
  each host: `metrics`, `chunks`, `doc-structure`, `summary-tree`, `provisions`,
  `semantic-projections`, `inputs`, `inventory-items` (all should now show a
  letterpress record column matching their own content column), and
  `kb-extraction` (should be visually unchanged — it is the one host whose tokens
  match the old hardcoded palette).

## Change Record

- `3718a56` `fix(web): record browser inherits its host view's theme tokens`

Files changed: `web/src/lib/components/home3/kb-input-record-browser.svelte` (only).

## Documentation Impact

What knowledge changed:
- **`/home3` has a design-token system, and shared components must consume it,
  not compete with it.** The vocabulary is `--panel-bg`, `--panel-bg-alt`,
  `--ink-line`, `--ink-line-soft`, `--text-primary`, `--text-secondary`,
  `--brass`, `--crimson`, defined by each host view from its `darkMode` prop.
  A component embedded in more than one view must read these and must not
  re-declare them on its own root — re-declaring silently severs the cascade.
- Generalizes the rule from doc-2026071402 ("mix into `var(--card-bg)`, never
  paint over it"). Both bugs are one rule: **a local value that overrides a
  themed value is a bug even when it looks right, because it can only look right
  in one mode and, for a shared component, in one host.**
- `kb-extraction-view` is the odd host: it defines the blue palette and omits
  `--brass` / `--crimson` / `--text-primary`. It is worth deciding whether that
  is intentional or drift; if drift, aligning it would let the fallbacks be
  deleted entirely.

Docs affected / updated:
- This bug report.
- `bugs/OPEN.md` — the `/home3` light-mode audit item is narrowed, not closed:
  this covers the shared record column across nine views, but each host's *own*
  content column is still unaudited.

Stale docs:
- None identified.

Intentionally left undocumented:
- `kb-input-search-dialog.svelte` (opened by the `Search` button) reads no tokens
  and takes no `darkMode` prop — it is self-contained and was not touched. It is
  very likely to have the same light-mode defect once opened. Not investigated.
- Button/panel border radii were left as they were. Only the cards were
  restyled, per the request; the rest of the component keeps its existing shape
  language.
