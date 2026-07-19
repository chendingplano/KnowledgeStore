# Spec: Page Content Configurability and i18n Pattern

Date: 2026-07-20

Status: **Implemented**

References:
- ADR: [2026071601 — Configurable Wiki Sidebar Menu](../adrs/202607/2026071601-adr-configurable-knowledge-menus.md)
- ADR: [2026071602 — Multi-Language, Configurable Labels for the Wiki Sidebar Menu](../adrs/202607/2026071602-adr-knowledge-menu-labels-i18n.md)
- ADR: [2026071701 — Configurable, Multi-Language Content for `/semos/workspace`](../adrs/202607/2026071701-adr-workspace-content-config-i18n.md)

## 1. Overview

ChenWeb now supports a common pattern for making page content configurable and
language-aware without requiring frontend code edits for routine operator
changes.

This pattern is implemented on these page domains:

- `/home3/knowledge` for the Wiki sidebar menu
- `/semos/workspace` for workspace masthead content and app tiles
- `/development` for the Dashboard app-shell NavRail sidebar menu (onboarded via
  the §11 recipe; see §5.3)

In both cases, the system separates three concerns:

- **Base content definition** remains in the page's existing source of truth.
- **Visibility control** is provided by a startup-loaded TOML boolean map.
- **Language-specific text overrides** are provided by per-language TOML files
  selected by Paraglide locale.

The result is a fail-open, additive configuration model: if no overrides are
present, the pages behave exactly as they did before these changes.

## 2. Goals

- Let operators hide or show page content by stable ids.
- Let operators rename or translate page content per language.
- Keep page-owned structure in its existing source of truth instead of
  duplicating full page structure in config.
- Reuse Paraglide's locale as the UI language selector.
- Preserve backward compatibility when config is absent.

## 3. Non-Goals

- Defining brand-new page items purely from config.
- Replacing the existing page-owned structure with config-owned structure.
- Solving cross-session language persistence.
- Translating arbitrary-length content collections that do not have a stable id
  space.

## 4. Core Pattern

### 4.1 Base content stays page-owned

Config only modifies visibility and text of already-defined items.

- For `/home3/knowledge`, the menu tree and ids remain owned by
  `web/src/routes/home3/knowledge/+page.svelte`.
- For `/semos/workspace`, the base content remains owned by `SiteConfig`,
  with app tiles identified by `WorkspaceApp.key`.

Config does not create new menu items, new app tiles, new routes, or new icon
definitions.

### 4.2 Visibility uses startup-loaded boolean maps

Visibility is controlled by flat TOML maps loaded through the viper /
`AppConfigDef` path and merged with `config.local.toml` overriding
`config.toml`.

- Wiki menu: `[knowledge-menus]`
- Workspace page: `[workspace-content]`

Rules:

- ids absent from the map default to `true`
- disabling a parent-owned item hides that item
- unknown ids do not break the page

Because these configs are loaded at backend startup, visibility changes require
a backend restart to take effect.

### 4.3 i18n text overrides use per-language files

Language-specific text comes from dedicated directories with one file per
language:

- `config/knowledge-menus/labels-<lang>.toml`
- `config/workspace-content/labels-<lang>.toml`

These files are read directly per request, not via viper and not through
`config.local.toml` overlays. The file for a language is the complete override
surface for that language.

Rules:

- language selection is driven by Paraglide `getLocale()`
- if a file is missing, invalid for the request, or has no matching entry for
  an id, the page falls back to its existing default text
- valid existing files with malformed TOML surface an error in the backend path
  rather than being silently ignored

Because these files are read per request, text override changes do not require
a backend restart.

### 4.4 Unknown ids fail open and surface diagnostics

A recurring operational risk in both domains was typos in ids. The implemented
pattern is:

- ignore unknown ids for rendering, so the page remains usable
- surface visible diagnostics in the UI where implemented
- log or warn so operators can correct the config

This preserves fail-open behavior while making inert configuration mistakes
discoverable.

## 5. Implemented Page Domains

### 5.1 `/home3/knowledge`

The Wiki sidebar supports:

- visibility toggles by menu id through `[knowledge-menus]`
- label translation/renaming by menu id through
  `config/knowledge-menus/labels-<lang>.toml`

Behavioral rules:

- the backend returns the raw `menus` visibility map plus resolved `labels`
- the frontend performs tree-aware filtering
- disabling a child hides that child only
- disabling a top-level item hides the whole section
- if all children of a parent are hidden, the parent collapses away
- menu descriptions are not part of this override surface

### 5.2 `/semos/workspace`

The workspace page supports:

- visibility toggles for masthead sections and app tiles through
  `[workspace-content]`
- label overrides for masthead fields and app tile names through
  `config/workspace-content/labels-<lang>.toml`
- description overrides for app tile subtitles through the same per-language
  file's `[descriptions]` table

Behavioral rules:

- fixed masthead ids are used for kicker, banner title, banner subtitle, and
  announcements visibility
- app tiles are identified by stable `WorkspaceApp.key` values
- announcements can be shown or hidden as a section, but individual
  announcement strings are not translated by this mechanism

### 5.3 `/development`

The Dashboard app-shell's NavRail sidebar menu (page_key `development`) supports:

- visibility toggles for any nav node (top-level item, child, or grandchild) by
  its existing menu id
- label overrides per node through `content.label` (descriptions unused)
- role scoping per node via `access_role`

Behavioral rules:

- the NavRail (`web/src/lib/components/home3/nav-rail.svelte`) owns the menu
  tree, ids, icons, and routes; config is a pure overlay (§9.4)
- the page is wired via a `pageKey` prop threaded
  `/development/+page.svelte → dashboard.svelte → nav-rail.svelte`; the NavRail
  fetches config only when `pageKey` is set
- the same NavRail also renders on `/home3`, which passes **no** `pageKey` and so
  keeps the full hardcoded menu — the config is scoped to `/development` only
- tree-aware filtering mirrors §5.1: hiding a node hides that node; a parent
  whose children all hid collapses away; a sub-group whose grandchildren all hid
  collapses away
- the baseline seed (goose `20260721000001`) creates every current node with
  `en` = `{}` (English hardcoded default) and `zh-cn` = Chinese label, so `en`
  rendering is unchanged and `zh-cn` gains translated labels
- unknown/stale `entry_key`s are logged via `console.warn` (§4.4)

## 6. API Shape

The implemented pattern uses dedicated authenticated endpoints per content
domain rather than folding everything into unrelated existing config endpoints.

Wiki menu:

```json
{
  "status": true,
  "menus": { "kb-metrics": false },
  "labels": { "kb-metrics": "指标" }
}
```

Workspace content:

```json
{
  "status": true,
  "visibility": { "workflows": false },
  "labels": { "ws-kicker": "工作台", "knowledge_base": "知识库" },
  "descriptions": { "knowledge_base": "浏览和管理文档与知识工件。" }
}
```

These endpoints return only the resolved data needed by the current page and
requested locale.

## 7. Operational Requirements

- Operators must use stable ids, not display labels, when editing visibility or
  i18n config.
- Visibility config belongs in `config.toml` / `config.local.toml`.
- Language override content belongs in versionable per-language files under
  dedicated directories.
- New configurable page domains should follow the same split:
  page-owned structure, startup-loaded visibility, request-time i18n overrides,
  Paraglide locale, fail-open fallback, and unknown-id diagnostics.

## 8. Known Limitations

- Paraglide locale persistence across full reload/navigation is still a
  separate unresolved concern.
- The pattern assumes a stable id space; arbitrary freeform content is out of
  scope unless it first gains stable ids.
- Startup-loaded visibility and request-time i18n are intentionally asymmetric:
  visibility favors deployment-level stability, while text overrides favor
  immediate content updates.

## 9. Database-Backed Configuration

Status: **Implemented** — see ADR
[2026072003 — Database-Backed, Multi-Language Page Content Configuration](../adrs/202607/2026072003-adr-db-backed-page-config.md)
and change `ChenWeb/openspec/changes/db-backed-page-config/`. The file-based
path (§1–8) remains in the codebase but is now dormant for `/home3/knowledge`
and `/semos/workspace`, which read the DB-backed resolution API; a follow-up
change should remove the dormant file plumbing.

Implementation notes vs. the original proposal below:

- The two tables `kb.page_def` and `kb.page_config` were created as proposed.
  `kb.page_config` is one row per entry **per language**, unique on
  `(page_key, entry_key, language)`, with `content` (JSONB `{label,
  description}`), `access_role` (JSONB array), `accessible`, and `enabled`.
- `access_role` uses `[system].access_roles` keys, matched case-insensitively;
  there is **no wildcard token**. The two existing pages follow the strict
  §9.2 accessibility rules; the seed grants them the full current role set so
  existing users (already given the needed roles) retain access.
- The default-language row (`[languages].default`, currently `zh-cn`) is
  authoritative for `accessible` / `enabled` / `access_role`; only `content`
  varies per language.
- Visibility uses an **overlay model** (not "row presence = visible"). The page
  owns its structure AND its hardcoded default text; a config row only overrides
  text, hides an item, or restricts it by role. The resolver returns two lists:
  `entries` (enabled + authorized, with resolved content overrides) and `hidden`
  (entry_keys that have a row but are disabled, suspended, or unauthorized for
  the caller). An entry_key in **neither** list has no row, so the page renders
  its own hardcoded default — this is what a **deleted** entry reverts to.
  Deleting is therefore "revert to built-in default (visible to all)"; hiding is
  done explicitly by turning off `enabled`.
- `kb.page_config.entry_desc` (added later) is admin-facing metadata describing
  what an entry is (e.g. "Wiki sidebar menu item", "Workspace masthead: kicker");
  it is language-independent and not part of the rendered page content.

The original proposal, retained for reference:

A planned next step is to move this capability to database-backed page
configuration so configurable content can be managed as application data
rather than deployment files.

### 9.1 Proposed tables

- `kb.page_def`: one record per frontend page that supports configurable
  content.
- `kb.page_config`: one record per configurable entry on that page.

`kb.page_def` should define the stable page identity used by both the frontend
and backend, such as page key, route, and any page-scoped metadata needed for
lookup and administration.

`kb.page_config` should define the stable content-entry identity and carry the
configuration payload for that entry, including:

- page association
- stable entry key
- content payload
- language metadata
- accessibility controls
- explicit enable / disable state

This keeps the same architectural split as the file-based design: page
structure remains page-aware, while per-entry overrides live in a configurable
data source keyed by stable ids.

### 9.2 Accessibility model

Per the proposed requirement, accessibility is controlled through both role
membership and an explicit accessibility switch:

- `kb.page_config.access_role`: JSON array of roles allowed to access the entry
- explicit accessibility flag: defaults to accessible

Expected behavior:

- an entry is accessible if and only if the explicit accessibility flag is on,
  `kb.page_config.access_role` is not `null` or empty, `access_role` contains
  at least one valid user role, and the user belongs to at least one role in
  that field
- if the explicit accessibility flag is off, the entry is inaccessible to all
  users regardless of role
- if `access_role` is undefined, `null`, empty, or contains no valid user
  roles, the entry is effectively suspended and is inaccessible to all users

This gives the system two independent controls:

- a durable allowlist describing who may access the entry
- a fast operational on/off switch for temporary suspension or restoration

### 9.3 Requirement review

The overall direction is sound and aligns well with the implemented pattern,
but a few requirements should be made explicit to avoid ambiguity in the data
model and API behavior.

- `access_role` being a JSON array is flexible, but the role namespace must be
  standardized. The system should define whether these are role ids, role
  names, or another canonical identifier.
- Entry identity should stay stable across i18n changes. Labels, descriptions,
  and translated content should be mutable, but `page_key + entry_key` should
  remain the durable lookup contract.
- Adding `kb.page_config.language` is a reasonable design choice. The database
  model should treat language as an explicit part of content resolution rather
  than relying on file naming conventions.
- Accessibility and content retrieval should continue to fail closed for
  unauthorized entries but fail open for missing optional translations by
  falling back according to `ChenWeb/config.local.toml::[languages]`.

### 9.4 Suggested behavioral rules

- A page is resolved from `kb.page_def` by stable page key or route.
- The frontend fetches only entries that belong to the page and are both
  enabled and authorized for the current user.
- For each authorized entry, the backend returns the resolved content for the
  requested locale, falling back according to
  `ChenWeb/config.local.toml::[languages]`.
- Entries that are disabled, suspended, or unauthorized are omitted from the
  response rather than returned with a client-side hide flag.
- Unknown page keys and unknown entry keys should surface diagnostics in logs
  and admin tooling.

### 9.5 Entry identity

The database-backed design should standardize entry identity explicitly.

- `kb.page_def` should expose a stable `page_key` for each configurable page.
- `kb.page_config` should expose a stable `entry_key` for each configurable
  entry on that page.
- The pair `page_key + entry_key` is the canonical identity of a configurable
  page entry.

Requirements:

- `page_key + entry_key` must be unique.
- The identity must be stable across label changes, language changes, content
  edits, and temporary accessibility changes.
- Frontend code, backend APIs, and administration tooling should reference
  entries by `page_key + entry_key`, not by display text.
- Existing file-based ids such as menu ids and workspace app keys should map
  naturally into this identity model.

### 9.6 Language model and fallback

The database-backed design should make language explicit through
`kb.page_config.language`.

Recommended interpretation:

- one `kb.page_config` row represents one configurable entry for one language
- multiple rows with the same `page_key + entry_key` may exist, differentiated
  by `language`
- a default-language row should exist for every active entry

Language resolution should align with `ChenWeb/config.local.toml::[languages]`,
which defines:

- `languages`: the supported language set
- `default`: the default fallback language

Expected behavior:

- if the requested language exists for an authorized entry, return that row
- otherwise, fall back to the row whose `language` matches
  `[languages].default`
- if neither exists, omit the entry or surface a backend diagnostic depending
  on whether the entry is required for the page

This keeps the current fail-open translation posture while making the fallback
source explicit and centrally configured.

## 10. Consequences

- Page content can now be tuned per deployment without rebuilding frontend code.
- Language-specific naming can be updated by operators in TOML files.
- Existing page definitions remain the authoritative source for structure and
  defaults.
- The implementation establishes a reusable ChenWeb pattern for future
  configurable, language-aware page domains.

## 11. Turning a Page into a Configurable Page (Recipe)

This section is the normative how-to for onboarding a new page onto the
DB-backed capability described in §9 (ADR
[2026072003](../adrs/202607/2026072003-adr-db-backed-page-config.md)). It
generalizes exactly how `/home3/knowledge` and `/semos/workspace` were wired.

### 11.0 What is already generic (do NOT rebuild per page)

The backend resolution and admin surfaces are page-agnostic and keyed by
`page_key`. A new page reuses them as-is — **no new Go handler, route, or table
is needed per page**:

- Resolution: `GET /api/v1/page-config/:pageKey?lang=<code>` (authenticated).
  Returns `entries` (enabled + authorized, content resolved for the locale with
  fallback to `[languages].default`) and `hidden` (entry_keys with a row that
  must be hidden); unknown-key diagnostics. Response:
  `{ "status": true, "page_key": "...", "lang": "...", "entries": [ { "entry_key": "...", "content": { "label": "...", "description": "..." } } ], "hidden": ["..."] }`.
- Admin API: `GET /api/v1/page-config/admin/pages`,
  `GET|POST|PUT|DELETE /api/v1/page-config/admin/pages/:pageKey/entries[/:entryKey]`.
- Admin UI: `/semos/admin/page-config` (reachable from `System Admin → Page
  Content`) manages any page's entries once its `kb.page_def` row exists.
- Frontend client: `getPageConfig(pageKey, lang)` in
  `web/src/lib/services/pageConfigService.ts` returns a
  `PageConfigMap` (`Record<entry_key, { label?, description? }>`).

Per-page work is therefore limited to three things: **(A) declare the page and
its entries as data, (B) wire the page's frontend to the resolver, (C) expose a
way to reach it.**

### 11.1 Step A — Declare the page and its entries (data)

Choose a stable `page_key` (e.g. `home3-knowledge`, `semos-workspace`) and a
stable `entry_key` for every configurable item on the page. `entry_key` MUST
map to an id the page already owns (a menu id, a tile `key`, a fixed masthead
id) and MUST NOT be display text. The pair `page_key + entry_key` is the
durable identity.

Insert one `kb.page_def` row and one `kb.page_config` row per entry **per
configured language**, via a goose migration in `ChenWeb/project_migrations/`
(preferred for the initial baseline) or the admin UI (for later edits).

Rules for the baseline seed so rendering is unchanged:

- Create a row for every item you want role-scoped or translated. Under the
  overlay model an item with **no** row still renders with its hardcoded
  default (visible to all authenticated users), so a row is needed only to
  translate, hide, or restrict an item — but seeding all current items is
  recommended so access control and translations are in place from the start.
- For the `default` language (`[languages].default`), the row is authoritative
  for `accessible`, `enabled`, and `access_role`. Set `access_role` to the
  role keys from `[system].access_roles` that should see the item (strict, no
  wildcard — an empty/invalid `access_role` suspends the entry for everyone).
- Put a translated `label`/`description` in `content` only where an override is
  wanted; leave `content` as `{}` to fall back to the page's hardcoded default
  for that field/locale.
- Optionally set `entry_desc` (admin-facing "what is this entry") for each row.
- Make the seed idempotent:
  `ON CONFLICT (page_key, entry_key, language) DO NOTHING`.

### 11.2 Step B — Wire the page's frontend

In the page's `+page.svelte`, keep the page-owned structure (ids, tree, layout,
icons, routes) and drive only visibility + text from the resolver:

1. Hold the config as `let pageConfig = $state<PageConfig | null>(null);` where
   `PageConfig = { overrides: Record<id, {label?, description?}>, hidden: Set<id> }`
   (`null` = "not loaded / errored" → fail open to the full default page).
2. On mount, `getPageConfig('<page_key>', getLocale()).then(cfg => pageConfig = cfg).catch(() => {})`.
3. Define the two resolvers used throughout the template (overlay model):
   - visibility (default visible; hide only what the resolver says to hide):
     `const isVisible = (id) => pageConfig === null || !pageConfig.hidden.has(id);`
   - text override with fallback:
     `const labelFor = (id, fallback) => pageConfig?.overrides[id]?.label ?? fallback;`
     (and `descFor` for descriptions).
4. Render each page-owned item unless `!isVisible(entry_key)`, using
   `labelFor`/`descFor` for its text. For hierarchical menus, collapse a parent
   whose children all hid.
5. Surface unknown ids: warn for keys in `overrides ∪ hidden` that don't match
   any real item id (a stale/typo `entry_key`), rather than failing silently.

This preserves the §4.1 split (page owns structure AND defaults; config is a
pure overlay) and the fail-open-on-error posture. An item with no row renders
its hardcoded default, so deleting a config row reverts the item to that
default rather than hiding it (§9.4).

### 11.3 Step C — Expose access to the page

If the page is a standalone route, add a navigation entry the same way the Wiki
and workspace links are added in
`web/src/lib/components/home3/nav-rail.svelte` (a leaf child plus a
`selectItem` case opening the route). The admin editor for the new page needs
no wiring — it appears automatically once the `kb.page_def` row exists.

### 11.4 Checklist

- [ ] Stable `page_key` chosen; `entry_key`s map to existing page-owned ids.
- [ ] `kb.page_def` row + one `kb.page_config` row per entry per language,
      seeded idempotently; default-language rows carry `access_role`
      (`[system].access_roles` keys), `accessible`, `enabled`.
- [ ] Page fetches `getPageConfig(page_key, getLocale())` into a nullable state
      and fails open.
- [ ] Items render by presence; labels/descriptions use `?? default`.
- [ ] Unknown-id diagnostic surfaced.
- [ ] Navigation entry added if the page is a standalone route.
- [ ] Verified in both locales that seeded data reproduces current rendering,
      and that disabling an entry via `/semos/admin/page-config` hides it on the
      next load with no backend restart.
