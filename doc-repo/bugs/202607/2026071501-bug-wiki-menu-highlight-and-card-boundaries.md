# Bug: Knowledge sidebar's Wiki submenu highlighted the wrong element and had no card boundaries

Date: 2026-07-15\
Status: fixed-verified — confirmed in browser by the user\
System: `ChenWeb` web frontend (SvelteKit), the `Knowledge` left sidebar at
`/home3/knowledge`\
Component: `web/src/routes/home3/knowledge/+page.svelte`\
Related: none directly (no prior bug doc touches this route's sidebar)

## Summary

The `Knowledge` sidebar's collapsible menu sections (`Wiki`, `Injestion`,
`Document Processing`) had three problems, reported together as one ticket:

1. Clicking a submenu item (e.g. `Wiki → Metrics`) tinted the **entire**
   parent box's background — header plus every sibling child — instead of
   just marking the clicked item.
2. The clicked submenu item itself got almost no visible highlight
   (`rgba(255,255,255,0.08)` on a background that was already tinted), so a
   user could not tell which child was active.
3. Menu items had no border/boundary of their own — the sidebar read as one
   continuous block rather than a list of discrete, clickable entries.

All three were caused by how the collapsible-parent and child-button styles
were written in `+page.svelte`; no other files were involved.

## Symptom

1. Open `/home3/knowledge`, expand the `Wiki` section.
2. Click `Metrics` (or any other child).
3. The whole `Wiki` box — from the header down through every other child
   (`LLM Wiki`, `Document Metadata`, …, `Workflow`, `Product and Parts`) —
   turned a uniform light tint, because `Wiki`'s children list is long enough
   to span nearly the full visible sidebar. It looked like the entire menu
   had been selected, not one row.
4. Nothing distinguished `Metrics` from its siblings — no distinct
   background, border, or bullet colour change was visible.
5. Items had no visual separation from each other or from the panel
   background — no card/border affordance.

## Root Cause

In the `{#each menuItems}` block's collapsible-parent branch:

- The **outer wrapping `<div>`** around the header button *and* the entire
  children list set its `background` to `accentTint` whenever *any* child
  was active:
  ```svelte
  <div class="rounded-lg" style="background:{item.children?.some((c) => isChildActive(c.id)) ? accentTint : 'transparent'};">
  ```
  Since this div wraps the header **and** the full `{#each item.children}`
  list, activating any one child painted the whole section.
- The **child `<button>`** used a much fainter, unrelated highlight
  (`rgba(255,255,255,0.08)` background, `textPrimary` text colour, no border)
  instead of reusing the `accentTint` / `accent` / left-border pattern
  already used for top-level leaf items — so the "selected" signal was too
  weak to read, especially once (1) also painted the surrounding box.
- No menu item — parent or leaf — had a `border`, so nothing in the sidebar
  had a visible edge; only background colour (or its absence) separated
  entries.

## Fix

All changes are in `web/src/routes/home3/knowledge/+page.svelte`.

1. **New `cardBg` derived token** (`rgba(255,255,255,0.03)` dark /
   `#FFFFFF` light), alongside the existing `hoverBg`/`accentTint` tokens.
2. **Collapsible-parent wrapper**: background is now always `cardBg`
   (never tinted by child state); only its `border` colour switches to
   `accent` when a descendant is active. This removes the whole-box wash
   while keeping a subtle cue that the open section contains the active
   item.
3. **Child buttons**: background/color now reuse the same
   `accentTint` / `accent` pattern as top-level items, plus a 2px accent
   left border when active, plus hover feedback (`hoverBg` on
   enter/leave) — previously child buttons had no hover state at all.
4. **Leaf items and collapsible-parent boxes** both get a `1px solid`
   card border (`accent` when active, `borderColor` otherwise) and
   `cardBg` fill in expanded mode, giving every entry a visible boundary.
   Collapsed (icon-only rail) mode is left untouched — `border:none` there
   — since that view is already compact and icon-only.

The same edit was applied verbatim to two on-disk checkouts of the same
route, both under `~/Workspace`:

- `ChenWeb/web/...` — the actually-deployed checkout (detached HEAD,
  pre-existing unrelated local modifications to
  `kb-extraction-view.svelte` and `topic-tree-view.svelte`).
- `ChenWeb-metric-overlay/web/...` — a separate git **worktree** of the
  same repo on branch `codex/metric-overlay-first-highlight`, carrying
  unrelated in-progress feature work. Diffed against `ChenWeb`'s copy of
  this file before editing; the only pre-existing difference was the
  `darkMode` source (`theme.isDark` store vs. a `?dark=` URL param), so the
  sidebar-menu edit applied cleanly to both.

## Incident during verification: wrong frontend serving mode

While rebuilding to verify the fix, the running backend was stopped (by the
user) and restarted (by the assistant) using `mise serve`
(`USE_EMBED_FRONTEND=true`), which serves the Go binary's `go:embed`'d
static build via a plain `http.FileServerFS` with **no** SPA fallback. This
app's SvelteKit config uses `adapter-node` with no `prerender` export
anywhere, so the build produces no per-route HTML — only a Node
`handler.js`/`server/` bundle plus static assets. Serving that with a bare
static file server 404s every route (`{"error":"404 page not found"}` for
authenticated requests; a JSON 401 for unauthenticated ones), which is what
the user saw and initially reported as "still broken."

The environment variable `useEmbedFrontend` in
`server/api/routes.go:63-92` is the switch: when `false` (the actual normal
dev setup, run via `mise dev` = `mise dev-server` [`go tool air`] +
`mise dev-web` [`bun run dev`, Vite on `:5173`]), the Go server
reverse-proxies frontend requests to the live Vite dev server instead, which
renders SSR routes correctly. That is how the page was rendering *before*
any of this session's changes, and is the only mode in which this app
currently works when served through this Go binary.

Fix for the incident: killed the wrongly-started `mise serve` process,
started `mise dev` instead, confirmed via the server's own startup log
(`useEmbedFrontend=false`, `frontendURL=http://localhost:5173`) and a
`curl` round-trip (`:5173/home3/knowledge` → 200, `:8080/home3/knowledge` →
401 pending login, matching pre-incident behaviour) that the correct mode
was restored. No rebuild of the Go binary or the frontend bundle was
necessary or attempted after that — Vite's dev server hot-reloads
`.svelte` source edits directly.

## Verification

- `svelte.compile(src, { generate: 'client' })` run directly against both
  edited files: compiles cleanly, no errors.
- Dev stack restored to reverse-proxy mode (`useEmbedFrontend=false`); user
  refreshed the live page and confirmed: the `Wiki` box no longer washes on
  child selection, the clicked child (`Metrics`) is now clearly highlighted,
  and menu items show card borders.
- No automated test suite covers this sidebar (visual/style-only change);
  none was added, consistent with this being a small CSS-token fix.

## Change Record

Files changed (identical edit in both checkouts):
- `ChenWeb/web/src/routes/home3/knowledge/+page.svelte`
- `ChenWeb-metric-overlay/web/src/routes/home3/knowledge/+page.svelte`

Neither checkout's changes were committed — `ChenWeb` is in detached HEAD
with pre-existing unrelated modified files, and `ChenWeb-metric-overlay`
has substantial unrelated in-progress work staged. Committing was left to
the user.

## Documentation Impact

What knowledge changed:
- The sidebar's collapsible-parent/child highlighting pattern now matches
  the top-level leaf-item pattern (`accentTint` background + `accent` left
  border on the *specific* active row, never a wash across a whole
  section).
- Operationally: `mise serve` (`USE_EMBED_FRONTEND=true`) is **not**
  interchangeable with `mise dev` for this app — the embed path requires
  prerendered routes that this SvelteKit config (`adapter-node`, no
  `prerender` export) never produces. Anyone rebuilding/restarting this
  backend for local verification should use `mise dev`, not `mise serve`,
  unless the frontend is later reconfigured for static prerendering.
- `ChenWeb-metric-overlay` is a git worktree of `ChenWeb` on a feature
  branch, not an independent checkout — the two need explicit reconciling
  when a fix must land in both.

Docs affected / updated:
- This bug report only. No entry added to `bugs/OPEN.md` — the fix is
  `fixed-verified` with nothing outstanding.

Stale docs: none.

Intentionally left undocumented / not fixed:
- Collapsed (icon-only) rail mode was not given card borders — kept as
  `border:none` to avoid boxing up an already-compact icon strip; not part
  of the reported bug.
- The two checkouts' changes remain uncommitted; committing/branch hygiene
  (notably `ChenWeb`'s detached HEAD) was left for the user to decide.
