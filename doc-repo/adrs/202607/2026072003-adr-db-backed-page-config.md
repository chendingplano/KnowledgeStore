# ADR 2026072003 — Database-Backed, Multi-Language Page Content Configuration

**Date:** 2026-07-20 \
**Status:** Implemented \
**Component:** ChenWeb page content configuration (`kb.page_def` / `kb.page_config`), `/home3/knowledge`, `/semos/workspace` \
**Authors**: Chen Ding \
**Tags**: ChenWeb, backend, frontend, i18n, configuration, access-control

## Change Logs
* 2026/07/20, ADR created; implementation completed for schema, seed,
  resolution API, admin CRUD API + page, and rewiring of both existing
  domains. Verified via backend `go build` + `go test` (pure access/resolution
  logic), `svelte-check`, and direct DB verification of the seed. Live browser
  verification (both locales, admin toggles) is pending the user's running Go
  API + authenticated Kratos session.
* 2026/07/20, Post-review revisions: (1) switched from "row-presence =
  visible" to the overlay model (DR4) so deleting an entry reverts to the
  built-in default instead of hiding it; resolver now returns `entries` +
  `hidden`. (2) Admin UI moved into the center panel (`System Admin → Page
  Content`) instead of opening a new tab, with a modal editor. (3) Added
  `kb.page_config.entry_desc` admin metadata (DR6, migration `..._20260720000003`).

## Context

Spec `2026072001-spec-page-content-configurability-i18n` (§1–8) established a
file-based pattern for making page content configurable and language-aware:
visibility via startup-loaded TOML boolean maps (`[knowledge-content]`,
`[workspace-content]`), and per-language text via `config/*/labels-<lang>.toml`
read per request. Two domains use it: `/home3/knowledge` (Wiki sidebar menu)
and `/semos/workspace` (masthead + app tiles).

That pattern has three operational limitations the spec's §9 set out to
remove: visibility changes require a backend restart; there is no per-role
access control; and content is managed as deployment files rather than
application data. This ADR records the move to database-backed page
configuration.

## Decision

Introduce two tables and resolve page content from them, keeping the same
architectural split (page owns structure; DB owns per-entry overrides).

### DR1 — Two tables, per-language rows, `page_key + entry_key` identity
`kb.page_def` holds one row per configurable page (`page_key` unique, `route`,
metadata). `kb.page_config` holds one row per entry **per language**, unique on
`(page_key, entry_key, language)`. The pair `page_key + entry_key` is the
canonical, durable entry identity used by frontend, backend, and admin —
never display text. This mirrors the proven `group_id + lang` row-per-locale
shape of `kb.site_announcements` (ADR 2026071701 / workspace-lists-live-data).

### DR2 — Default-language row is authoritative for access + enable
`accessible`, `enabled`, and `access_role` are evaluated from the entry's
default-language row (`[languages].default`, currently `zh-cn`), which every
active entry must have. Only `content` varies per language. This prevents an
entry's visibility from flipping between languages. The admin UI writes access
controls identically across all language rows to keep them in sync.

### DR3 — `access_role` namespace = `[system].access_roles` keys, strict, no wildcard
`access_role` is a JSON array of role keys drawn from
`appconfig.GetAccessRoles()`, matched case-insensitively against the user's
`Roles`. Accessibility follows spec §9.2 exactly and fails closed: an entry is
accessible iff `accessible` is on, `access_role` is non-empty with at least one
valid role key, and the user holds at least one of those roles. A disabled,
non-accessible, or role-less entry is inaccessible to everyone. There is no
`"*"` / public token — per the owner's decision, the two existing pages follow
these strict rules like any other entry, and existing users were granted the
needed roles. The seed therefore assigns each migrated entry the full current
`[system].access_roles` set so today's users retain access.

### DR4 — Overlay visibility model (page owns defaults; config overrides)
`GET /api/v1/page-config/:pageKey?lang=<code>` (authenticated) returns two
lists: `entries` (enabled AND authorized, each with content resolved for the
requested locale → default-language content → the frontend's built-in default
per field) and `hidden` (entry_keys that have a row but are disabled,
suspended, or unauthorized for the caller). An entry_key in **neither** list
has no row.

The frontend owns structure (menu tree, tile layout, ids, icons, routes) **and
its hardcoded default text**, and treats config as a pure overlay: an item is
hidden only if its id is in `hidden`; otherwise it renders with the override
from `entries` if present, else its hardcoded default. This keeps the
file-based "absent id ⇒ visible (fail-open)" posture (§4.2): a new page item
with no row shows by default, and **deleting a config row reverts the item to
its built-in default (visible to all) rather than hiding it** — hiding is done
explicitly via `enabled = false`. On fetch error or before it resolves, both
pages fail open to their built-in defaults.

*Note:* an earlier iteration made row-presence authoritative for visibility
(absent ⇒ hidden). That was changed to this overlay model so that (a) deleting
an entry has an intuitive "revert to default" meaning, and (b) new page items
work without requiring a config row first.

### DR5 — Admin CRUD
`/api/v1/page-config/admin/*` manages page defs and entries. Reads require
authentication; writes require admin/owner or the `admin` role (mirroring
`useradminhandler`). Entries edit all locales together in a modal editor and
expose `entry_desc`, `access_role`, `accessible`, and `enabled`. Content and
text-time changes take effect on the next request with no restart. The admin UI
is a panel view (`System Admin → Page Content`, rendered in the center panel via
`content-panel.svelte`), with a standalone route `/semos/admin/page-config`
kept for a direct URL. Delete removes all of an entry's language rows and its
confirm dialog states the consequence (revert to built-in default, visible to
all) so operators understand it is not the same as hiding.

### DR6 — `entry_desc` admin metadata
`kb.page_config.entry_desc` (TEXT, language-independent) records what an entry
is for admins (e.g. "Wiki sidebar menu item", "Workspace masthead: kicker"). It
is shown/edited only in the admin UI and is not part of rendered page content;
the admin writes the same value to every language row.

## Consequences

- Page visibility, per-role access, and per-language text are now managed as
  application data with no rebuild or restart.
- The file-based endpoints (`kbhandler.GetKbMenuConfig`,
  `sitehandler.GetWorkspaceContentConfig`), their `[knowledge-content]` /
  `[workspace-content]` sections, and the `config/*/labels-<lang>.toml` loaders
  are now **dormant** for these two pages (the frontends read the DB API). They
  are intentionally left in place; a follow-up change should remove them.
- Access for an entry that HAS a config row is strict fail-closed: a user whose
  `Roles` is empty or disjoint from the row's `access_role` sees nothing for
  that entry (it is in `hidden`) — by design (DR3). An item with **no** row is
  visible to all (overlay fail-open, DR4).
- Deleting a config row reverts the item to the page's built-in default and
  makes it visible to all; hiding requires an explicit `enabled = false` (DR4).
- The pattern generalizes: new configurable page domains add a `kb.page_def`
  row and `kb.page_config` entries rather than new TOML plumbing.

## References
- Spec: `2026072001-spec-page-content-configurability-i18n` §9, §11
- ADR 2026071601 (configurable knowledge menus), 2026071602 (menu labels i18n),
  2026071701 (workspace content config i18n), 2026072001 (user roles / Kratos)
- Change: `ChenWeb/openspec/changes/db-backed-page-config/`
- Migrations: `ChenWeb/project_migrations/20260720000001_*` (schema),
  `..._20260720000002_*` (seed), `..._20260720000003_*` (entry_desc)
