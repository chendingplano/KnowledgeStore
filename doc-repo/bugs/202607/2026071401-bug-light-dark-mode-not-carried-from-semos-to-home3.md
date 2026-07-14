# Bug: light/dark mode is not carried from `/semos` into `/home3`

Date: 2026-07-14
System: `ChenWeb` web frontend (SvelteKit)
Component: `web/src/lib/stores`, `web/src/app.html`, `web/src/routes/+layout.svelte`,
`web/src/routes/semos`, `web/src/routes/home3`, `web/src/lib/services`
Related: [doc-2026071102-adr-new-gui-semos](../../adrs/202607/2026071102-adr-new-gui-semos.md)
(Cross-Cutting Requirements: light/dark mode must be site-wide)

## Summary

`/semos` (the new customer-facing skin) and `/home3` (the knowledge-base UI that
the SemOS nav opens) each implemented their own, incompatible light/dark
mechanism. Clicking `知识库` in the `/semos` header opened `/home3/knowledge`
in dark mode regardless of the mode the user had selected on `/semos`, and a
toggle inside `/home3` was invisible to `/semos`. Both areas belong to the same
project, so both now read one project-wide, persisted theme store.

## Symptom

1. Open `/semos` in light mode (the default on a light-mode OS).
2. Click `知识库` in the header.
3. `/home3/knowledge` opens in **dark** mode.

Symmetrically, toggling to light inside `/home3` and navigating back to `/semos`
did not carry the choice: `/semos` re-read its own separately stored preference.
The two areas' toggles wrote to two different places and neither could see the
other's.

## Root Cause

Two independent mode mechanisms, neither aware of the other.

### `/semos` — a persisted store, scoped to `/semos` only

`web/src/lib/stores/semosTheme.svelte.ts` held the mode in `localStorage` under
the key `semos-theme` and toggled the `.dark` class on `documentElement`. To
avoid a flash before hydration, a blocking script in `web/src/app.html` applied
the same class on first paint — but only for `/semos` URLs:

```js
if (!location.pathname.startsWith('/semos')) return;
var stored = localStorage.getItem('semos-theme');
```

So both the store and the pre-hydration class application were, by construction,
unavailable to every route outside `/semos`.

### `/home3` — unpersisted local state, defaulting to dark, carried by a URL param

`web/src/routes/home3/+page.svelte` held its own mode as component-local state
with a hard default:

```js
let darkMode = $state(true);   // always dark on load
function toggleDark() { darkMode = !darkMode; }   // never persisted
```

Its sibling pages (`knowledge`, `metrics`, `chunks`, `inputs`, `doc-structure`,
`doc-review-report/[id]`) did not share that state at all. They re-derived the
mode from a URL query parameter, again defaulting to dark:

```js
let darkMode = $derived(page.url.searchParams.get('dark') !== '0');
```

The parameter was home3's carrier *between its own pages*: `buildArtifactWikiHref`
(`lib/services/artifactWikiService.ts`) and `buildKbSearchPageHref`
(`lib/services/kbArtifactSearch.ts`) appended `dark=0` to every href they built
whenever the current page was in light mode.

### Why the two mechanisms produced the bug

The SemOS nav entry is a plain href with no query string
(`{ label: m.semos_nav_knowledge_base(), href: '/home3/knowledge' }` in
`routes/semos/components/SiteHeader.svelte`). It is not produced by the href
builders, so it carries no `dark` parameter — and home3's parameter default is
dark. The mode the user had chosen lived in the `semos-theme` key, which no
home3 page ever read. Dark was therefore the only possible outcome, whatever
`/semos` was showing.

## Fix

Committed as `84bacf4` in `ChenWeb`.

One project-wide store is the single source of truth for the mode; both areas
read and write it, and nothing else carries mode.

1. **New store** `web/src/lib/stores/theme.svelte.ts` (replaces the semos-only
   `semosTheme.svelte.ts`, deleted). Exports `theme` with `mode`, `isDark`,
   `init()`, `toggle()`, `set()`. Persists to `localStorage` under
   `chenweb-theme` (renamed from `semos-theme`, as it is no longer
   semos-scoped) and applies the `.dark` class from `app.css`. The state is
   seeded at module load, so first paint already matches the stored mode.
2. **`web/src/app.html`** — the blocking pre-hydration script's
   `/semos`-only guard is removed, so the `.dark` class is applied on every
   route, not just `/semos`. This is what makes the rule general rather than
   home3-specific.
3. **`web/src/routes/+layout.svelte`** (root) — calls `theme.init()` once on
   mount, so every route in the app is covered without opting in.
4. **`/semos`** — `+layout.svelte` and `components/SiteHeader.svelte` now import
   `theme` instead of `semosTheme`; the semos layout's own `init()` call is
   dropped (the root layout does it).
5. **`/home3`** — every page derives from the store instead of local state or the
   URL: `let darkMode = $derived(theme.isDark)` in `+page.svelte`, `knowledge`,
   `metrics`, `chunks`, `inputs`, `doc-structure`, and
   `doc-review-report/[id]`. home3's toggle (`toggleDark`) now calls
   `theme.toggle()`, so it persists and is visible to `/semos`.
6. **Dead carrier removed** — with the store persisting the mode, the `dark=0`
   href parameter is redundant. The `darkMode` parameter and the
   `params.set('dark', '0')` line are removed from `buildArtifactWikiHref` and
   `buildKbSearchPageHref`, along with their one caller
   (`lib/components/home3/kb-search-results-view.svelte`) and the two tests that
   asserted the parameter.

### Behavior change worth knowing

With nothing stored, `/home3` used to always open dark. It now follows the OS
`prefers-color-scheme` — the rule `/semos` already used. Anyone with a saved
preference under the old `semos-theme` key gets it re-derived from their OS
setting once, then re-persisted under `chenweb-theme`.

## Verification

- `npx tsx --test` on the two affected service test files: 11 pass, 0 fail.
- `npx svelte-check --tsconfig ./tsconfig.json`: 0 errors (23 pre-existing
  warnings in 12 files).
- `npx vite build`: succeeds.
- Not yet exercised in a browser. Manual check still worth doing: toggle mode on
  `/semos`, click `知识库`, confirm `/home3/knowledge` opens in the same mode;
  toggle inside `/home3`, return to `/semos`, confirm it persisted.

## Change Record

Implementation changes committed in `ChenWeb` at:

- `84bacf4` `fix(web): one light/dark mode across the whole frontend`

Files added: `web/src/lib/stores/theme.svelte.ts`.
Files deleted: `web/src/lib/stores/semosTheme.svelte.ts`.

Not included in that commit (pre-existing working-copy deletions, unrelated to
this bug, left for the owner to decide on):
`docs/superpowers/specs/2026-07-14-semos-site-config-i18n-design.md` and
`docs/superpowers/specs/2026-07-14-semos-workspace-redesign-design.md` — both
still linked from the SemOS ADR.

## Documentation Impact

What knowledge changed:
- Light/dark mode is a **project-wide** concern in ChenWeb, not a per-skin one.
  Any new page or skin gets it for free by reading `$lib/stores/theme.svelte`;
  no page should hold its own mode state, and no href should carry mode.
- The `localStorage` key is `chenweb-theme` (was `semos-theme`). It is read in
  two places that must stay in sync: the store and the blocking script in
  `app.html`.

Docs affected / updated:
- This bug report.
- `doc-2026071102-adr-new-gui-semos` states the site-wide light/dark requirement
  that this bug violated; the requirement itself is unchanged, so the ADR needs
  no edit. Its implementation notes still describe the mode as part of the
  `/semos` layout — accurate, but no longer the whole story.

Stale docs:
- None identified.

Intentionally left undocumented:
- The individual `darkMode` props threaded through the `home3`/`home4`
  components are unchanged; they still receive the mode from their page. Only
  the *source* of that value moved.
