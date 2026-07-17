# ADR 2026071701 — Configurable, Multi-Language Content for `/semos/workspace`

**Date:** 2026-07-17 \
**Status:** Implemented \
**Component:** ChenWeb `/semos/workspace` (Your Workspace page) \
**Authors**: Chen Ding \
**Tags**: ChenWeb, frontend, i18n, configuration

## Change Logs
* 2026/07/17, ADR created; implementation completed and verified (backend
  tests + `go vet` + `svelte-check`; browser verification pending the user's
  authenticated session).
* 2026/07/17, Extended `labels-<lang>.toml` with a second `[descriptions]`
  table so app tile subtitles are also configurable per language — see DR3
  (amended) and the addendum below. This closes the gap DR3 originally
  flagged as "descriptions can gain the same treatment later without a
  breaking change."

## Context

The `/semos/workspace` page ("Your Workspace") renders its masthead (kicker,
banner title/subtitle), an announcements bulletin, and a grid of app tiles
(Knowledge Base, Chat, Search, Document Reviews, Workflows, Agents and
Harness) from `SiteConfig.workspace`, itself loaded from whichever
`config/site/site-default*.toml` file `[config].config_filename` names
(ADR 2026071102). That file is a single, statically-chosen file per
deployment — it is not selected per-request by language, and its
`workspace.apps` entries were in English in both `site-default.toml` and
`site-default-zh-cn.toml` — the "zh-cn" file's app names had simply never
been translated. There was also no way to hide an individual masthead
element or app tile without editing that file and (depending on which one
is active) affecting other pages that also read the same `SiteConfig`.

ADR 2026071601 (`configurable-knowledge-menus`) and ADR 2026071602
(`knowledge-menu-labels-i18n`) had already solved this exact pair of
problems — per-item visibility toggle, per-language label override — for
the Wiki sidebar menu on `/home3/knowledge`. This ADR applies the same
two-part pattern to `/semos/workspace`, reusing its architecture directly
rather than inventing a new one.

## Decision

### DR1 — Two new, independent config surfaces, not a change to `SiteConfig`
Mirroring DR1–DR3 of ADR 2026071601/1602: `SiteConfig`/`site-default*.toml`
remains the base definition of *what* content exists (masthead text, the
apps list, each app's `href`/`icon`/`description`). Two new surfaces layer
on top, exactly as for the Wiki menu:
- `[workspace-content]` in `config.toml`/`config.local.toml` — id→bool
  visibility, unmarshalled via the existing viper/`AppConfigDef` path
  (`AppConfig.WorkspaceContent`, `mapstructure:"workspace-content"`).
- `config/workspace-content/labels-<lang>.toml` — id→string label
  overrides, read directly per request (not viper-merged), keyed to
  Paraglide's `getLocale()`.

### DR2 — Content ids: fixed strings for the masthead, `app.key` for tiles
Four fixed ids cover the masthead: `ws-kicker`, `ws-banner-title`,
`ws-banner-subtitle`, `ws-announcements` (the last controls the whole
bulletin section, not individual announcement strings — the announcements
list is arbitrary-length tenant content, not a fixed set of items, so it
gets a visibility toggle but no label override).

App tiles reuse a new `key` field on `WorkspaceApp`
(`server/api/sitehandler/sitehandler.go`, `web/src/lib/services/siteConfigService.ts`),
mirroring the existing `Feature.Key` field in the same file rather than
introducing new "id" terminology: `knowledge_base`, `chat`, `search`,
`doc_reviews`, `workflows`, `agents`. `Feature` (the marketing-page
capability cards) already established this exact convention — a stable,
non-display key alongside the fetch-and-render for display; `WorkspaceApp`
had no such key until now, since ADR 2026071601's menu-id approach doesn't
apply to `SiteConfig`.

### DR3 — Scope: visibility for all six, labels for masthead + app names, descriptions for app tiles only (amended 2026-07-17)
Visibility (`[workspace-content]`) covers all six ids plus every app's
`key`. Labels (`labels-<lang>.toml`'s `[labels]` table) cover the same
masthead ids plus each app's `key`, overriding the app's `name`.

**Originally** (as first implemented), app tile `description` text was out
of scope, matching ADR 2026071602's explicit non-goal for menu item
descriptions. **Amended the same day**, after the user asked for tile
subtitles to be configurable too: `labels-<lang>.toml` gained a second
`[descriptions]` table, keyed the same way as `[labels]` but restricted to
app `key`s (masthead ids and `ws-announcements` have no description to
override). `LoadWorkspaceContentLabels` became
`LoadWorkspaceContentOverrides`, returning both maps from one file
read/parse rather than two, and the response gained a `descriptions` field
alongside `labels`. Announcement text itself remains out of scope (see
DR2) — it stays entirely `SiteConfig`-driven, since announcements are an
arbitrary-length list, not a fixed id space.

### DR4 — New endpoint, not folded into `/api/site-config`
`GET /api/v1/workspace/content-config` is a new, authenticated handler
(`server/api/sitehandler/workspace_content_handler.go`), placed in the
codebase's convention of one dedicated endpoint per configurable-content
domain, rather than adding `visibility`/`labels` fields to
`GET /api/site-config` (public, tenant-scoped, direct-TOML-parse-per-request)
or `GET /api/v1/site-config/tenant/:id`. Reasons, mirroring DR3 of ADR
2026071601: `[workspace-content]` is viper/`config.local.toml`-backed while
`SiteConfig` is a direct-per-request file parse selected by a completely
different axis (tenant, not language) — mixing the two paths in one
response would blur which mechanism controls which field. The endpoint is
registered under the authenticated `/api/v1` group next to
`/api/v1/kb/menu-config`, since `/semos/workspace` itself requires a
session.

### DR5 — Frontend fetch, resolution, and diagnostics mirror the Wiki page exactly
`web/src/routes/semos/workspace/+page.svelte`:
- `onMount` calls `getWorkspaceContentConfig(getLocale())` into
  `contentVisibility`/`contentLabels`/`contentDescriptions` (`$state`,
  empty/fail-open until resolved), the same shape as the Wiki page's
  `menuConfig`/`menuLabels`.
- `showKicker`/`showBannerTitle`/`showBannerSubtitle`/`showAnnouncements`
  derive from `contentVisibility[id] ?? true`; `kickerText`/
  `bannerTitleText`/`bannerSubtitleText` derive from
  `contentLabels[id] ?? cfg.workspace.<field>`. `visibleApps` filters
  `cfg.workspace.apps` by `contentVisibility[app.key] ?? true` and remaps
  `name`/`description` through `contentLabels[app.key] ?? app.name` /
  `contentDescriptions[app.key] ?? app.description`.
- `knownContentIds` (the four fixed ids + every current `app.key`) drives
  the same unrecognized-id diagnostic added to the Wiki page in ADR
  2026071602's addendum: unmatched ids in either `contentLabels` or
  `contentDescriptions` (`unknownContentLabelIds` checks both, since they
  live in the same file) produce a `console.warn` and a small, non-blocking
  amber banner in the masthead, from day one rather than as a follow-up fix
  — the addendum's lesson (id typos are otherwise silently inert, and this
  recurred twice independently before it was addressed) applies identically
  here.

### Alternative Decisions
- Fold visibility/labels into `SiteConfig`/`site-default-<lang>.toml`
  directly (e.g. an `enabled` bool per app, and real translations in
  `site-default-zh-cn.toml`) — rejected. `site-default-<lang>.toml`
  selection is a per-tenant/per-deployment choice
  (`[config].config_filename`), not a per-request Paraglide-locale choice;
  conflating the two would mean a tenant's one active file has to carry
  every language's text, contradicting the "file for a language is the
  config for that language" principle DR3 of ADR 2026071602 already
  established for menu labels. Considered and rejected for the same reason
  ADR 2026071602 rejected nesting labels inside `[knowledge-menus]`.
- New "id" field/terminology on `WorkspaceApp`, matching the Wiki menu's
  `KbSectionId` vocabulary — rejected in favor of reusing `Feature.Key`,
  already established one struct away in the same file, per this
  repo's "match existing style" guidance.
- Per-announcement label overrides — rejected (see DR2): announcements are
  an arbitrary-length list from `SiteConfig`, not a fixed set of ids: a
  visibility toggle for the section as a whole fits; a stable per-item id
  does not.

### Database Migrations
None.

### Data Formats
- New TOML section `[workspace-content]` in `config.toml`/`config.local.toml`
  (flat `id (string) -> enabled (bool)` map; ships commented out — a no-op
  until an operator uncommments and edits it):
  ```toml
  [workspace-content]
  workflows = false        # hide the "Workflows" app tile
  ws-announcements = false # hide the whole bulletin section
  ```
- New per-language file `config/workspace-content/labels-<lang>.toml`, now
  with two tables:
  ```toml
  [labels]
  ws-kicker = "工作台"
  knowledge_base = "知识库"

  [descriptions]
  knowledge_base = "浏览和管理文档与知识工件。"
  ```
- `GET /api/v1/workspace/content-config?lang=<code>` response:
  ```json
  {
    "status": true,
    "visibility": { "workflows": false },
    "labels": { "ws-kicker": "工作台", "knowledge_base": "知识库" },
    "descriptions": { "knowledge_base": "浏览和管理文档与知识工件。" }
  }
  ```
  `visibility` is `{}` when no `[workspace-content]` section is configured;
  `labels`/`descriptions` are `{}` when `lang` is omitted, unrecognized, or
  has no matching file.

### Environment Variables
- `WORKSPACE_CONTENT_LABELS_DIR` (test/deployment override, mirrors
  `KNOWLEDGE_MENU_LABELS_DIR`'s role): when set, points at the directory
  containing `labels-<lang>.toml` files instead of walking up from the
  working directory to find the repo root.

## Implementation

### Code Changes
- `server/cmd/config/config.go`: added `WorkspaceContent map[string]bool`
  (`mapstructure:"workspace-content"`) on `AppConfigDef`, and
  `GetWorkspaceContentConfig() map[string]bool` accessor.
- `server/api/sitehandler/sitehandler.go`: added `Key string` field
  (`toml:"key" json:"key"`) to `WorkspaceApp`.
- `server/api/sitehandler/workspace_content_labels.go` (new):
  `LoadWorkspaceContentOverrides(lang)` — validates `lang`
  (`^[a-zA-Z0-9-]{1,20}$`, rejecting path-traversal-shaped input), resolves
  and reads `labels-<lang>.toml` once, returns both the `[labels]` and
  `[descriptions]` tables as `(map[string]string, map[string]string, error)`.
  Missing file/invalid lang → two empty maps, no error; malformed TOML →
  error. (Originally shipped as `LoadWorkspaceContentLabels`, returning only
  `[labels]`; renamed/extended the same day per the change log above.)
- `server/api/sitehandler/workspace_content_handler.go` (new):
  `GetWorkspaceContentConfig` handler for
  `GET /api/v1/workspace/content-config`, response now includes a top-level
  `descriptions` field alongside `visibility`/`labels`.
- `server/api/routes.go`: registered the new route in the authenticated
  `/api/v1` group, next to `/kb/menu-config`.
- `config.local.toml`: added a documented, commented-out example of the
  `[workspace-content]` section.
- `config/workspace-content/labels-en.toml` (new, empty `[labels]` and
  `[descriptions]` tables plus format-documenting comments) and
  `config/workspace-content/labels-zh-cn.toml` (new, starter Chinese
  translations for the masthead, all six app tile names, and all six app
  tile descriptions).
- `config/site/site-default.toml`, `config/site/site-default-zh-cn.toml`,
  `server/api/sitehandler/testdata/site-valid.toml`: added `key` to every
  `[[workspace.apps]]` entry (`knowledge_base`, `chat`, `search`,
  `doc_reviews`, `workflows`, `agents`).
- `web/src/lib/services/siteConfigService.ts`: added `key: string` to the
  `WorkspaceApp` interface; added `WorkspaceContentVisibility`/
  `WorkspaceContentLabels`/`WorkspaceContentDescriptions` types and
  `getWorkspaceContentConfig(lang?)`, now returning `{ visibility, labels,
  descriptions }`.
- `web/src/routes/semos/workspace/+page.svelte`: fetches content config on
  mount into `contentVisibility`/`contentLabels`/`contentDescriptions`;
  derives `showKicker`/`showBannerTitle`/`showBannerSubtitle`/
  `showAnnouncements` and `kickerText`/`bannerTitleText`/
  `bannerSubtitleText`/`visibleApps` (the last now remapping both `name`
  and `description`); renders those instead of `cfg.workspace.*` directly;
  surfaces unrecognized config/label/description ids via `console.warn` and
  an amber banner in the masthead.

### Tests
- `server/cmd/config/workspace_content_config_test.go`: section absent →
  empty map; id→bool unmarshal; `config.local.toml`-style override wins
  over a base value (mirrors `knowledge_menus_config_test.go`).
- `server/api/sitehandler/workspace_content_labels_test.go`: missing file →
  two empty maps; populated `[labels]`/`[descriptions]` tables → correct
  maps; malformed TOML → error; path-traversal-shaped `lang` → two empty
  maps (mirrors `kb_menu_labels_test.go`, extended for the second table).
- `server/api/sitehandler/workspace_content_handler_test.go`: unconfigured →
  empty visibility/labels/descriptions; configured visibility → matching
  response; `lang` query → matching labels and descriptions (mirrors
  `kb_menu_handler_test.go`).
- All new/updated tests pass; `go build ./...`, `go vet` on touched
  packages, and `svelte-check` (0 errors in touched files) all pass.
- `GET /api/v1/workspace/content-config` smoke-tested against the running
  local dev stack: returns `401 {"error":"Authentication required"}`
  unauthenticated, confirming the route and auth middleware are wired as
  intended (full logged-in browser verification of the rendered page is
  left to the user, who holds the authenticated session).

## Operational Behaviors — How to Configure Workspace Content

Add a `[workspace-content]` section to `ChenWeb/config.local.toml` (or
`config.toml`). Each key is a masthead id (`ws-kicker`, `ws-banner-title`,
`ws-banner-subtitle`, `ws-announcements`) or an app's `key`
(`knowledge_base`, `chat`, `search`, `doc_reviews`, `workflows`, `agents`);
the value is `true` (shown) or `false` (hidden):

```toml
[workspace-content]
workflows = false        # hide the "Workflows" app tile
ws-announcements = false # hide the whole bulletin section
```

Rules:
- **Ids not listed default to enabled (`true`).** An empty/absent
  `[workspace-content]` section shows the full page — today's behavior.
- **Unknown ids are inert** but surfaced: the page shows an amber banner
  and logs a console warning naming the id and which file it came from,
  rather than silently doing nothing (same posture as ADR 2026071602's
  addendum for the Wiki menu, applied here from the start).
- Changes take effect on the next full page load (fetched once on mount);
  they require a backend restart, since `config.local.toml` is read once at
  process startup (unchanged from the Wiki menu's behavior).

To translate or rename labels and app tile descriptions, add/edit
`config/workspace-content/labels-<lang>.toml`:

```toml
[labels]
ws-kicker = "工作台"
ws-banner-title = "我的工作台"
knowledge_base = "知识库"

[descriptions]
knowledge_base = "浏览和管理文档与知识工件。"
```

- **`<lang>`** must match a value Paraglide's `getLocale()` can return
  (currently `en` or `zh-cn`).
- **`[descriptions]` keys are app `key`s only** (`knowledge_base`, `chat`,
  `search`, `doc_reviews`, `workflows`, `agents`) — masthead ids and
  `ws-announcements` have no description to override.
- **Ids not listed** keep their `SiteConfig` default label/description for
  that language.
- **This does not control visibility** — that remains
  `[workspace-content]`, independent of language.
- **Changes take effect on the next request** to
  `GET /api/v1/workspace/content-config?lang=<code>` — read fresh per
  request, no backend restart required (unlike visibility).
- Same known, pre-existing, explicitly out-of-scope limitation as ADR
  2026071602: Paraglide's locale is not yet persisted across a full page
  navigation/reload in this deployment, so a fresh visit to
  `/semos/workspace` currently requests the base locale (`zh-cn`)
  regardless of a language choice made earlier in the session.

### Verifying configuration

```
GET /api/v1/workspace/content-config?lang=zh-cn
{"status":true,"visibility":{"workflows":false},"labels":{"ws-kicker":"工作台", ...},"descriptions":{"knowledge_base":"浏览和管理文档与知识工件。", ...}}
```

## Consequences
- Operators can hide individual `/semos/workspace` masthead elements or app
  tiles per deployment, and translate/rename their labels per language,
  without touching `SiteConfig`/`site-default*.toml` or a frontend rebuild
  (for labels) — mirroring the Wiki sidebar menu's operational story
  exactly.
- No breaking change: omitting `[workspace-content]` or a given
  `labels-<lang>.toml` is behaviorally identical to before this change; the
  `Key` field addition to `WorkspaceApp`/`SiteConfig` is additive (empty
  string when absent from an older TOML file).
- `SiteConfig`/`site-default*.toml` remains the single source of truth for
  what app tiles exist and their `href`/`icon`; the two new surfaces only
  toggle visibility and override text, they cannot define new content —
  same division of responsibility as ADR 2026071601/1602.
- Announcement text remains untranslated by this mechanism, an accepted,
  intentional gap (see DR2/DR3) since announcements are an arbitrary-length
  `SiteConfig` list, not a fixed id space; app tile descriptions are no
  longer in that gap as of the 2026-07-17 amendment (see DR3).

## Tests
See "Tests" under Implementation above.

## Documentation Impact
- This ADR is the doc of record for `/semos/workspace`'s configurable
  content + i18n capability, applying ADR 2026071601's and ADR 2026071602's
  pattern to a second page. No other document described this page's
  configuration surface prior to this change.
- ADR 2026071102 (`new-gui-semos`) remains the doc of record for
  `SiteConfig`/`site-default*.toml` itself, unmodified in scope by this
  change beyond the additive `WorkspaceApp.Key` field.

## References
- ADR 2026071601 — `configurable-knowledge-menus` (visibility mechanism
  this ADR mirrors)
- ADR 2026071602 — `knowledge-menu-labels-i18n` (i18n label mechanism this
  ADR mirrors, including its addendum on unrecognized-id diagnostics)
- ADR 2026071102 — `new-gui-semos` (`SiteConfig`/`site-default*.toml`,
  unchanged in scope here)
- `ChenWeb/server/cmd/config/config.go`
- `ChenWeb/server/api/sitehandler/sitehandler.go`
- `ChenWeb/server/api/sitehandler/workspace_content_handler.go`
- `ChenWeb/server/api/sitehandler/workspace_content_labels.go`
- `ChenWeb/web/src/routes/semos/workspace/+page.svelte`
- `ChenWeb/web/src/lib/services/siteConfigService.ts`
- `ChenWeb/config.local.toml`
- `ChenWeb/config/workspace-content/labels-en.toml`,
  `ChenWeb/config/workspace-content/labels-zh-cn.toml`
