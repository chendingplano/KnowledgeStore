# SemOS Workspace Page — Re-design

**Date:** 2026-07-14
**Status:** Approved (design; not yet implemented)
**Component:** `ChenWeb/web/src/routes/semos/workspace`
**Parent ADR:** [2026071102-adr-new-gui-semos.md](../../../../KnowledgeStore/doc-repo/adrs/202607/2026071102-adr-new-gui-semos.md)

## Problem

The Main page was resolved to the `/semos2` "paper and ink" treatment, and the
two other variants were deleted. The Workspace page never followed. It still
wears the skin of the deleted `/semos1` variant:

- near-black `#080b14` banner with an angled `clip-path` wedge
- indigo `#6b7aff` as the accent
- a grid overlay and a radial glow blur
- glassy `#131726` cards with colored top strips
- its own text ramp (`#1a1a1a` / `#6b6b6b` / `#e8e7e4` / `#9a9aa0`)

The header and footer that wrap it are paper-and-ink. The page therefore
contradicts its own chrome, and the site reads as two products.

Two further defects, both violations of rules the parent ADR already sets:

1. **Content is hardcoded in the component.** `announcements`, `recent`, and
   `alarms` are literal arrays in `workspace/+page.svelte`. The ADR requires
   that rendered content live in config, not baked into Svelte templates.
2. **Empty-state copy is English-only.** `'No recent activity.'` and
   `'No alarms.'` are string literals in the component, bypassing the i18n
   catalog that the rest of the site uses.

## Goals

- The Workspace page uses the same visual material as the Main page.
- Nothing the page renders is hardcoded in the Svelte template.
- No fabricated data ships (per the ADR's standing `[[stats]]` warning).

## Non-goals

- Changing the page's section inventory (banner, three feeds, apps grid stays).
- Wiring real activity/alarm backends. No such endpoint exists; inventing one
  is out of scope.
- Deciding whether nav labels move into config. That ADR question stays open;
  see "Chrome vs. content" below for why this design does not touch it.

## Design

### Density: app shell, not marketing page

The parent ADR is explicit that consistency is not sameness: *"Marketing pages
sparse and breathing-room-heavy; Workspace/app pages denser and more
information-forward."*

The Workspace page therefore shares every token and idiom with the Main page
but runs at a tighter rhythm. The banner drops from the Main hero's
`py-28 md:py-36 lg:py-44` to roughly `py-14 md:py-16`, and the headline steps
down one size on the type scale. A logged-in user should reach their apps
without scrolling through marketing air.

### Token translation

| Current (`/semos1` leftover) | Replacement (paper-and-ink) |
|---|---|
| `#080b14` near-black banner | `banner_image` under a `#faf9f7/70` paper veil — the Main hero's technique |
| `#6b7aff` indigo accent | `#b08d57` bronze |
| angled `clip-path` wedge between sections | bronze ornament divider (diamond flanked by dots) |
| grid overlay + radial glow blur | deleted |
| `#131726` glass cards, colored top strips | white→`#faf8f4` gradient surface, white top bevel, layered shadow, hover lift |
| flat `bg-[#6b7aff]/10` icon tiles | bronze icon coins (raised disc, inset highlight) |
| `#1a1a1a` / `#6b6b6b` text | `#17181c` / `#6f6c66` (light), `#e9e7e2` / `#a5a29b` (dark) |
| `#f4f2ed` band | `#f3f1ec` — the Main page's feature-band paper |

**One deliberate exception.** The Alarms count badge renders amber/red when the
count is non-zero, not bronze. An alarm count is information, not ornament;
recoloring it to satisfy the palette would suppress a signal. Every other
accent on the page is bronze.

### Structure

```
compact banner  (bronze diamond + kicker + title + subtitle over veiled image)
   ornament
three feed cards  (Announcements · Recent Activities · Alarms and Errors)
   ornament
apps grid  (6 cards)
shared footer  (unchanged)
```

The apps grid reuses the Main page's feature-card idiom verbatim: bronze icon
coin, `ArrowUpRight` revealed on hover, `-translate-y-1.5` lift on hover,
staggered `transition-delay` on reveal.

Each feed card gets a designed empty state — a faint bronze diamond above a
muted line — replacing today's italic gray text.

**Banner image caveat.** `banner_image` is `/images/angleWalls.jpg`, picked to
sit at 40% opacity under a near-black hero. Under a pale veil it will read
very differently — possibly too busy or too dark. The implementation should
look at it in both modes and, if it fights the paper treatment, swap it for an
image matched to the Main hero's register. This is a config value, so it is a
content change, not a code change.

### Chrome vs. content

Today feed *titles* come from the i18n catalog while feed *items* and
empty-state copy are hardcoded English. This design adopts one rule:

> **UI chrome → message catalog. Tenant content → TOML.**

This is the precedent the codebase already set (nav labels are in the catalog;
hero and feature copy are in TOML), so applying it here resolves nothing new
and leaves the ADR's open "should nav labels move into config?" question
exactly as open as it was.

Under the rule:

- **Announcements are tenant content** → TOML. A tenant admin writes them in
  Site Management.
- **Feed titles and empty-state copy are chrome** → message catalog. They need
  translation, not per-tenant customization.
- **Recent Activity and Alarms are runtime data** → neither. They are not
  config, and no endpoint produces them yet.

### Config schema additions

`[workspace]` gains two fields:

```toml
[workspace]
kicker = "Workspace"                 # NEW — bronze kicker above banner_title
banner_title = "Your Workspace"
banner_subtitle = "..."
banner_image = "/images/angleWalls.jpg"
announcements = [                    # NEW — plain array of strings
  "Welcome to your SemOS workspace."
]
```

`announcements` is a flat string array, not a table array. An announcement is a
line of text; giving it a `date` or `href` it does not yet need would be
speculative.

Mirrored, as the ADR requires, in both language bindings:

- Go — `Workspace` struct in `server/api/sitehandler/sitehandler.go` gains
  `Kicker string \`toml:"kicker" json:"kicker"\`` and
  `Announcements []string \`toml:"announcements" json:"announcements"\``
- TS — `SiteWorkspace` in `web/src/lib/services/siteConfigService.ts` gains
  `kicker: string` and `announcements: string[]`

All three config files get the new fields: `site-default.toml`,
`site-default-zh-cn.toml`, `tenant-demo.toml`.

### New i18n messages

Added to every catalog that exists — `web/messages/en.json` and
`web/messages/zh-cn.json`:

- `semos_workspace_no_announcements`
- `semos_workspace_no_activity`
- `semos_workspace_no_alarms`

**Discrepancy, not resolved here.** `project.inlang/settings.json` declares
`locales: ["en", "zh-cn"]`, but the parent ADR records
`[frontend].supported_languages = ["en", "zh-cn", "ja", "ko"]`. Only `en` and
`zh-cn` catalogs exist on disk. This is a third instance of the
language-configuration confusion the ADR already carries as an open question
(`[frontend].supported_languages` vs. `config.local.toml`'s `[languages]`).
This design adds messages to the catalogs that exist and does not create
`ja.json` / `ko.json` — inventing Japanese and Korean translations is not a
styling task. Logged as a carried-forward question below.

### Recent Activity and Alarms remain empty

Both render their designed empty state. The component holds them as empty
arrays with a comment citing this spec and the ADR's no-fabricated-data rule.
They are wired when a real endpoint exists — not populated with plausible demo
content, which is precisely the failure the ADR's `[[stats]]` warning records.

### One extraction

The bronze ornament markup is currently duplicated between
`semos/+page.svelte` and `SiteFooter.svelte`. The Workspace page needs it too,
and a third copy is the point at which duplication becomes a defect — the
ornament is the site's signature, so it must not be able to drift between
pages.

Extract `semos/components/Ornament.svelte`; the Main page, the footer, and the
Workspace page all consume it. This is the only refactor in scope.

## Files touched

| File | Change |
|---|---|
| `web/src/routes/semos/workspace/+page.svelte` | rewrite |
| `web/src/routes/semos/components/Ornament.svelte` | new |
| `web/src/routes/semos/+page.svelte` | use `Ornament` |
| `web/src/routes/semos/components/SiteFooter.svelte` | use `Ornament` |
| `server/api/sitehandler/sitehandler.go` | `Workspace` struct: `Kicker`, `Announcements` |
| `web/src/lib/services/siteConfigService.ts` | `SiteWorkspace`: `kicker`, `announcements` |
| `config/site/site-default.toml` | new `[workspace]` fields |
| `config/site/site-default-zh-cn.toml` | new `[workspace]` fields |
| `config/site/tenant-demo.toml` | new `[workspace]` fields |
| `web/messages/{en,zh-cn}.json` | 3 new empty-state messages each |
| `server/api/sitehandler/testdata/site-valid.toml` | fixture gains the new fields |
| `server/api/sitehandler/sitehandler_test.go` | assert the new fields parse |

No database migration. No new endpoint. `GET /api/site-config` carries the new
fields automatically once the struct gains them.

## Testing strategy

The two layers have very different test affordances, and the plan must not
pretend otherwise.

**Go (config schema) — real TDD.** `sitehandler_test.go` already exists and
loads `testdata/site-valid.toml` through `LoadSiteConfig`. The new `kicker`
and `announcements` fields get a failing test first, then the struct change.

**Svelte (the re-skin) — no unit tests.** The web project has **no test
runner**: `.test.ts` files exist but `vitest` is absent from `package.json`
and no test binary is installed, so they cannot run. Standing up a test
runner is a separate concern from a visual re-skin and is out of scope here.
The Svelte layer is verified by `bun run check` (svelte-check, catches the
type errors that matter when the config interface changes) plus browser
verification against the checklist below. Asserting Tailwind class strings in
a unit test would be tautology, not verification — it would restate the
implementation rather than test it.

## Verification

- Both light and dark mode on `/semos/workspace`; no color from the old palette
  (`#080b14`, `#6b7aff`, `#131726`, `#f4f2ed`) survives anywhere in the file.
- Navigating `/semos` → `/semos/workspace` shows no material change in header,
  footer, ornament, card depth, or accent color.
- `?tenant=<id>` still resolves a tenant config and still surfaces its error
  state (existing behavior must not regress).
- Feeds render their empty states with no fabricated items.
- Language switcher changes the empty-state copy, proving it left the component.

## Documentation impact

Per the workspace coding protocol:

- **What knowledge changed:** the Workspace page's visual system, and the rule
  that separates i18n chrome from TOML tenant content.
- **Docs updated:** parent ADR 2026071102 — changelog entry, and the "As-built
  config schema" table gains the new `[workspace]` fields.
- **Now stale:** nothing. The ADR's Workspace Landing Page section describes
  content, not styling, and stays accurate.
- **Left undocumented:** nothing.

## Open questions carried forward (not resolved here)

- Should nav labels move into config? Still open in the parent ADR.
- `[[stats]]` figures are still placeholders.
- Recent Activity and Alarms have no backing endpoint.
- **`ja` / `ko` message catalogs do not exist** although the ADR lists them as
  supported languages. Folds into the ADR's existing language-config open
  question.
- **The web project has no working test runner.** Pre-existing, not caused by
  this work, but it means frontend changes here carry no automated regression
  net beyond `svelte-check`.
