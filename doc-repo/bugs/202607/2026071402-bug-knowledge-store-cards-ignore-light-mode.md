# Bug: knowledge store cards stay dark (and their titles go unreadable) in light mode

Date: 2026-07-14\
Status: fixed-verified — builds and type-checks; verified in a browser \
System: `ChenWeb` web frontend (SvelteKit), `/home3/knowledge` \
Component: `web/src/lib/components/home3/knowledge-store-view.svelte` \
Related: [doc-2026071401-bug-light-dark-mode-not-carried-from-semos-to-home3](2026071401-bug-light-dark-mode-not-carried-from-semos-to-home3.md)
(the fix that made this one visible)

## Summary

The knowledge store cards on `/home3/knowledge` render as black slabs when the
page is in light mode. The card *text* colors do follow the mode, so in light
mode they switch to dark ink and land on a still-black card — leaving the store
titles (`Research`, `卫健委相关标准`) almost invisible.

The cause is not the theme store. It is a second, independent styling mechanism
— the per-user **Card Style** preset — whose default (`neon`) hardcodes an
opaque dark background that paints over the theme-aware one.

## Symptom

1. Open `/home3/knowledge` in light mode (now the default on a light-mode OS).
2. The page shell, header, and active-store panel are correctly light (cream
   `#f5efe4`).
3. The store cards below are black, with barely-legible dark titles.

## Root Cause

`knowledge-store-view.svelte` derives fourteen theme colors from the `darkMode`
prop, including the card background:

```js
let cardBg = $derived(darkMode ? 'rgba(24, 35, 52, 0.88)' : 'rgba(255, 255, 255, 0.9)');
```

They are handed to CSS as custom properties on the view root, and the base
`.store-card` rule consumes `--card-bg` correctly. So the card *ought* to be
theme-aware.

But each card also carries one of three Card Style preset classes (`blush`,
`graphite`, `neon`), chosen by the user and persisted in `localStorage` under
`knowledge-store-card-style`. `neon` — **the default** — stacks its own
background layer on top:

```css
.store-card.style-neon {
	background:
		linear-gradient(180deg, rgba(7, 10, 18, 0.96), rgba(7, 10, 18, 0.94)),  /* hardcoded */
		var(--card-bg);                                                          /* fully obscured */
}
```

At 0.94–0.96 alpha the near-black overlay is effectively opaque, so `--card-bg`
never shows through and the card is dark in *both* modes. Everything else inside
the card — title, description, labels, timestamps — draws from `--text-primary`
and friends, which *do* flip to dark ink in light mode. Hence the unreadable
titles: the text honored the theme and the surface under it did not.

The sibling presets were never affected. `blush` and `graphite` blend the user's
color *into* `var(--card-bg)` with `color-mix(...)` rather than covering it, so
they adapt to the mode by construction. `neon` was the only preset that painted
over the theme instead of mixing with it.

### Why this surfaced only now

The bug is not new, and the light/dark fix in
[doc-2026071401](2026071401-bug-light-dark-mode-not-carried-from-semos-to-home3.md)
did not introduce it — but it is what made it *reachable*. Before that fix,
every `home3` page defaulted to dark and only left it via an explicit toggle or
a `dark=0` URL parameter, so `/home3/knowledge` was in practice never seen in
light mode and the hardcoded dark slab looked correct. Once the mode began
following the OS `prefers-color-scheme`, light mode became the *default* for
light-mode users, and a latent bug became the first thing on screen.

This is the general shape worth remembering: **making a code path reachable
exposes the bugs that were already sitting in it.** The behavior-change note in
doc-2026071401 flagged the new default; it did not ask what had never been
looked at under that default.

## Fix

Committed as `4e1ffcf` in `ChenWeb`.

Make the neon slab a derived theme value like every other color in the view,
rather than a constant. Five new `$derived` values, passed to CSS as custom
properties alongside the existing fourteen:

| Property | Dark | Light |
|---|---|---|
| `--neon-slab` | `rgba(7,10,18,0.96)` | `rgba(255,255,255,0.94)` |
| `--neon-slab-soft` | `rgba(7,10,18,0.94)` | `rgba(247,249,253,0.92)` |
| `--neon-slab-raised` | `rgba(7,10,18,0.98)` | `rgba(255,255,255,0.97)` |
| `--neon-slab-raised-soft` | `rgba(7,10,18,0.95)` | `rgba(247,249,253,0.95)` |
| `--neon-pill-text` | `white 20%` | `black 25%` |

1. `.store-card.style-neon` and its `:hover` / `.selected` variant now read the
   slab from those properties instead of literal `rgba(7, 10, 18, …)`. Dark mode
   renders byte-identically to before; light mode gets a near-white panel that
   keeps the electric halo edge (the halo is a `box-shadow` built from the user's
   card color, and works in both modes unchanged).
2. `.store-card.style-neon .active-pill` and `.badge.accent` mixed their text
   color toward `white 20%` — tuned for a dark slab. They now mix toward
   `--neon-pill-text`, which is black in light mode, so the `ACTIVE` pill keeps
   its contrast on a white card.

No change to `blush`, `graphite`, the Card Style dialog, the persisted keys, or
the base `.store-card` rule.

## Verification

- `npx svelte-check --tsconfig ./tsconfig.json`: 0 errors (23 warnings in 12
  files — unchanged from the pre-existing baseline).
- `npx vite build`: succeeds.
- **Not yet exercised in a browser.** The light-mode slab values are a judgment
  call that has not been seen rendered. Worth confirming: the near-white panel
  reads well against the cream page background; the purple halo is not
  overpowering in light mode; the `ACTIVE` pill and `MANUAL`/`ACTIVE` badges
  still have contrast; the dark mode is visually unchanged.

## Change Record

- `4e1ffcf` `fix(web): knowledge store neon cards follow the page light/dark mode`

Files changed: `web/src/lib/components/home3/knowledge-store-view.svelte` (only).

Left in the `ChenWeb` working copy, untouched and unrelated: the two
pre-existing deletions of `docs/superpowers/specs/2026-07-14-semos-*.md`, which
also carried over from doc-2026071401. Those two documents now appear as new
files in `KnowledgeStore` (`doc-repo/design/202607/`), so the deletion looks
intentional — but it is still uncommitted and is the owner's call.

## Documentation Impact

What knowledge changed:
- Light/dark is project-wide (doc-2026071401), but `/home3/knowledge` carries a
  **second, orthogonal** styling axis — the Card Style preset — that is *not*
  part of the theme and is persisted separately (`knowledge-store-card-style`,
  `knowledge-store-card-bg-color` in `localStorage`). Any new preset must
  compose with the theme, not override it: **mix into `var(--card-bg)`, never
  paint over it.** That is the rule `blush` and `graphite` already follow and
  `neon` broke.
- Corollary for review: an opaque layer above a theme-aware layer is a bug even
  when it looks right, because it only looks right in one mode.

Docs affected / updated:
- This bug report.
- doc-2026071401 — addendum added under "Behavior change worth knowing",
  pointing here: its change of default made this latent bug visible.

Stale docs:
- None identified.

Intentionally left undocumented:
- The dark drop shadows (`rgba(4, 10, 24, 0.34)`) on `.store-card:hover` and the
  neon preset are still hardcoded and are heavier than a light theme normally
  wants. Cosmetic, out of scope for this bug, not fixed.
- `knowledge-store-view.svelte` predates the theme store and still takes
  `darkMode` as a prop defaulting to `true`, rather than reading `theme.isDark`
  directly. Its page passes the right value, so this is not a defect — but the
  `= true` default is a trap for any future caller that forgets the prop.
