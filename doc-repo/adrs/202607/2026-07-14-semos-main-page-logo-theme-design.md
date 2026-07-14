# Design: SemOS Main Page Consolidation, Configurable Logo, Theme Consistency

**Date:** 2026-07-14
**Status:** Approved
**Related:** [ADR 2026071102 — New Customer-Facing Frontend for SemOS](../../../../KnowledgeStore/doc-repo/adrs/202607/2026071102-adr-new-gui-semos.md)

## Context

The ADR's Cross-Cutting Requirements commit the SemOS site to a site-wide
configurable logo and consistent site-wide light/dark mode, but flags two
open items:

1. Three parallel Main Page variants (`/semos`, `/semos1`, `/semos2`) still
   need to be narrowed to one.
2. The header currently renders only `config.branding.logo_text` (plain
   text) — there is no actual logo image, configurable or otherwise.

Separately, a real bug was found: light/dark mode does not apply
consistently across page loads, because the theme store defaults to light
and only corrects itself in `onMount` (client-only render).

**Scope for this pass:** only the two pages SemOS has actually built — Main
and Workspace. The same logo/theme principles should eventually extend to
`ChenWeb/home3` (which SemOS reuses for functionality), but that is out of
scope here.

## 1. Resolve the Main Page variant decision

`/semos2` ("paper and ink," modelled on miraitaxcpa.com) is chosen as the
permanent Main Page design. `/semos` (original) and `/semos1` (dark/
theatrical) are deleted.

- Delete `web/src/routes/semos/` and `web/src/routes/semos1/` entirely.
- Move `web/src/routes/semos2/*` to `web/src/routes/semos/*` (the canonical
  path — no numeric suffix, matching the ADR sitemap's plain "Main" /
  "Workspace" naming).
- Within the moved files, update hardcoded `/semos2` hrefs and DOM ids
  (`semos2-mobile-nav`, etc.) to `/semos`.
- No config changes needed: `config/site/site-default.toml`'s
  `hero.cta_primary_href = "/semos/workspace"` already points at the
  canonical path. Confirmed via grep that no other file references
  `/semos1` or `/semos2` outside their own route directories.

## 2. Configurable Company Logo

- Add `logo_image` (string, a path like the existing `hero.image`) to the
  `[branding]` table in `config/site/site-default.toml`, alongside the
  existing `logo_text`.
- Mirror the field in both places that already mirror `[branding]`:
  - `LogoImage string \`toml:"logo_image" json:"logo_image"\`` in
    `server/api/sitehandler/sitehandler.go`.
  - `logo_image: string` in the `SiteConfig` branding type in
    `web/src/lib/services/siteConfigService.ts`.
- New shared component `web/src/routes/semos/components/LogoMark.svelte`:
  renders `<img src={logo_image} alt={logo_text}>` when `logo_image` is
  non-empty, otherwise falls back to the existing bronze-diamond +
  `logo_text` wordmark markup. Used by both `SiteHeader.svelte` and
  `SiteFooter.svelte`, which is what makes the logo automatically present
  on every SemOS page — both already share one layout/header/footer.
- Ship a placeholder SVG (bronze diamond + "SemOS" wordmark, matching the
  existing paper-and-ink palette) at `web/static/images/logo-semos.svg`,
  referenced by `logo_image`, so the field is wired end-to-end rather than
  a stub. The customer's real logo file can replace it later — just a file
  swap + path update, no code change.

## 3. Light/Dark mode consistency fix

**Root cause:** `semosTheme.svelte.ts`'s `mode` state defaults to `'light'`
and is only corrected in `onMount`, which is client-only (`ssr = false` on
the `/semos` layout). Every full page load of `/semos` or `/semos/workspace`
paints once in light mode, then flips a moment later — a visible flash, and
the actual "doesn't apply consistently across pages" symptom observed.

**Fix:**
- Add a small blocking inline `<script>` in `web/src/app.html`, gated to
  `location.pathname.startsWith('/semos')`, that synchronously reads
  `localStorage['semos-theme']` (falling back to
  `prefers-color-scheme: dark`) and applies the `.dark` class to
  `<html>` *before* Svelte hydrates.
- Update `semosTheme.init()` to sync its reactive `mode` state from that
  already-applied value (same read logic, no re-toggle), so the header's
  sun/moon icon is correct on first paint too.
- Confirmed via grep that no other route currently uses Tailwind's `dark:`
  variant, so gating the script to `/semos*` paths is safe.

## Testing / Verification

Manual browser check (no automated test infra exists for this route today):
1. Load `/semos`, toggle dark mode, hard-refresh — confirm no flash, mode
   persists.
2. Navigate directly to `/semos/workspace` via URL bar — confirm dark mode
   is already applied on first paint, matching Main page.
3. Toggle back to light, hard-refresh both pages — confirm consistency in
   the other direction.
4. Confirm the logo renders on both Main and Workspace (header + footer).

## Out of scope

- Site Management admin upload UI for the logo (ADR already defers this).
- Extending logo/theme consistency to `home3` or other ChenWeb routes.
- Any change to `[[stats]]` placeholder figures or other open ADR items.
