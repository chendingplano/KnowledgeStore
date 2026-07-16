# ADR 2026071601 — Configurable Wiki Sidebar Menu (`[knowledge-menus]`)

**Date:** 2026-07-16 \
**Status:** Implemented \
**Component:** ChenWeb `/home3/knowledge` (Wiki sidebar) \
**Authors**: Chen Ding \
**Tags**: ChenWeb, frontend, configuration, openspec \

## Change Logs
* 2026/07/16, ADR created; implementation completed and verified.
* 2026/07/16, Added client-side diagnostics for unrecognized `[knowledge-menus]` ids — see ADR 2026071602's "Addendum" for details; this closes the risk noted below ("Stale/unknown ids... silently inert").

## Context

The Wiki sidebar menu on `/home3/knowledge` (Knowledge Stores, Injestion, Wiki,
Document Processing, and their sub-items) was hardcoded in
`web/src/routes/home3/knowledge/+page.svelte`. Different deployments/tenants
want to show a reduced or customized subset of this menu (e.g. hide
in-progress features, disable a whole section) without a code change and
redeploy. Prior to this change, that required editing `+page.svelte` directly.

This work was tracked as the OpenSpec change
`openspec/changes/configurable-knowledge-menus` (proposal, design, spec,
tasks all completed; see References).

## Decision

### DR1 — Add a `[knowledge-menus]` TOML section
A flat table mapping a menu item's existing id (string) to whether it is
shown (bool), configured via `config.toml` / `config.local.toml`. Ids
absent from the table default to enabled (`true`), so shipping this
feature is a no-op for every deployment until an operator edits
`config.local.toml`.

A flat map was chosen over nested TOML tables that mirror the sidebar's
parent/child structure (e.g. `[knowledge-menus.kb-doc-wiki]`) because menu
ids are already globally unique across the whole tree in the frontend's
`KbSectionId` type. Re-encoding the parent/child relationships a second
time in TOML would duplicate the tree shape (already owned by
`+page.svelte`) and risk drifting from it whenever the menu changes.

### DR2 — Load through the existing viper/`AppConfigDef` path
`[knowledge-menus]` is unmarshalled the same way as the existing
`[doc-reviews]` section: a field on `AppConfigDef` in
`server/cmd/config/config.go`, loaded via viper, with `config.local.toml`
correctly merged over `config.toml`. A separate, unrelated mechanism
(`server/api/kbhandler/kb_config_handler.go`, `GET /api/v1/kb/config`)
parses `config.toml` directly and does **not** merge `config.local.toml` —
it was not used here because `config.local.toml` is the intended
operator-facing source for this feature.

### DR3 — New dedicated endpoint, not an addition to `GET /api/v1/kb/config`
`GET /api/v1/kb/menu-config` is a new handler
(`server/api/kbhandler/kb_menu_handler.go`) backed by
`appconfig.GetKnowledgeMenusConfig()`, rather than adding a field to the
existing `kb/config` handler, to avoid mixing the viper-backed config path
with that handler's separate direct-TOML-parse path in one response.

### DR4 — No server-side id whitelist/validation
Unlike `[doc-reviews]`, which validates tier item names against
`validAspectNames()` (a Go-owned list), menu ids are Svelte-owned and have
no equivalent Go-side source of truth. The resolved map is passed through
to the frontend as-is; an id in config that doesn't match any current menu
item is simply inert (no matching item to hide). Building a Go-side
whitelist would require keeping a second copy of the id list in sync with
`+page.svelte` on every menu change, which contradicts the reasoning in
DR1.

### DR5 — Visibility resolution (parent cascade + empty-parent collapse) happens client-side
The server returns the raw resolved `map[string]bool`; it has no notion of
the menu tree shape. `+page.svelte` derives a filtered menu from its
existing `menuItems` array and the fetched map:
- A top-level item is dropped if its id maps to `false`.
- Otherwise, each of its children is dropped if its id maps to `false`.
- If a parent item originally had a non-empty `children` array and every
  child was filtered out, the parent itself is dropped too (avoids an
  expandable node with nothing inside).

### Alternative Decisions
- Nested TOML tables mirroring the parent/child tree — rejected (see DR1):
  more visually hierarchical, but duplicates tree shape and requires a
  messier Go type (`map[string]interface{}` or per-parent structs).
- Defining brand-new menu items (label/route/icon) purely from config —
  out of scope. Config only toggles visibility of ids that already exist
  in the Svelte menu definition; it does not create menu items.
- Server-side id validation against a Go-owned whitelist — rejected (see
  DR4).

### Database Migrations
None.

### Data Formats
- New TOML section `[knowledge-menus]` in `config.toml` / `config.local.toml`:
  flat `id (string) -> enabled (bool)` map.
- New response shape for `GET /api/v1/kb/menu-config`:
  ```json
  { "status": true, "menus": { "kb-metrics": false, "kb-doc-wiki": true } }
  ```
  `menus` is `{}` when no `[knowledge-menus]` section is configured.

### Environment Variables
None added. Configuration is entirely through the `[knowledge-menus]` TOML
section (see below), not environment variables.

## Implementation

### Code Changes
- `server/cmd/config/config.go`: added `KnowledgeMenus map[string]bool`
  (`mapstructure:"knowledge-menus"`) field on `AppConfigDef`, and
  `GetKnowledgeMenusConfig() map[string]bool` accessor.
- `server/api/kbhandler/kb_menu_handler.go` (new): `GetKbMenuConfig`
  handler for `GET /api/v1/kb/menu-config`.
- `server/api/routes.go`: registered the new route next to the existing
  `/kb/config` route.
- `config.local.toml`: added a documented, commented-out example of the
  `[knowledge-menus]` section.
- `web/src/lib/services/kbService.ts`: added `KbMenuConfig` type and
  `getKbMenuConfig()` fetch function, following the existing
  `getKbFrontendConfig()` pattern.
- `web/src/routes/home3/knowledge/+page.svelte`: fetches the menu config
  on mount into `menuConfig` (`$state`, fail-open — empty until resolved
  or on fetch error, so the full menu renders by default); derives
  `visibleMenuItems` (`$derived`) by filtering `menuItems` and their
  `children` against `menuConfig`; renders `visibleMenuItems` instead of
  the raw `menuItems` array.

### Tests
- `server/cmd/config/knowledge_menus_config_test.go`: section absent →
  empty map; id→bool unmarshal; `config.local.toml`-style override wins
  over a base value (mirrors `doc_reviews_config_test.go`).
- `server/api/kbhandler/kb_menu_handler_test.go`: unconfigured → empty
  map response; configured overrides → matching response.
- All new tests pass. `go build ./...`, `go vet` on touched packages, and
  `svelte-check` (0 errors/warnings in touched files) all pass. `eslint`
  reports only pre-existing issues unrelated to this change.
- Manually verified end-to-end in a logged-in browser session against the
  local dev stack (`https://dingbo.bzton.cn`, Caddy-proxied to
  `localhost:5173`/`:8080`):
  - No `[knowledge-menus]` section → full menu (all 4 top-level sections).
  - `kb-import = false` → "Injestion" section and its child fully hidden.
  - `kb-metrics = false` (with `kb-import` also disabled) → only
    "Metrics" removed from "Wiki"; "Wiki" and its other children remain.
  - Every "Wiki" child disabled, `kb-doc-wiki` itself left unset → "Wiki"
    top-level item auto-hides (empty-parent collapse, DR5).
  - Config reverted → full menu confirmed restored.

## Operational Behaviors — How to Configure the Menus

Add a `[knowledge-menus]` section to `ChenWeb/config.local.toml` (or
`config.toml`). Each key is a **menu item id**; the value is `true`
(shown) or `false` (hidden):

```toml
[knowledge-menus]
kb-metrics = false        # hide just "Metrics" under Wiki
kb-import  = false        # hide the entire "Injestion" section
```

Rules:
- **Ids not listed default to enabled (`true`).** An empty or absent
  `[knowledge-menus]` section shows the full menu — today's behavior.
- **Disabling a top-level id hides that whole section**, including all of
  its children, regardless of their own settings.
- **Disabling a child id hides only that child**; its parent and siblings
  are unaffected — *unless* doing so leaves the parent with zero visible
  children, in which case the parent is hidden too (avoids an expandable
  section with nothing inside).
- **Unknown ids are inert.** An id that doesn't match any current menu
  item (e.g. after a future menu refactor) is silently ignored — no
  error is surfaced.
- Changes take effect on the next full page load of `/home3/knowledge`
  (the menu config is fetched once on mount); they require a backend
  restart to take effect, since `config.local.toml` is read once at
  process startup, not hot-reloaded per request.

### How menu items are identified

Ids come from `KbSectionId` in
`web/src/routes/home3/knowledge/+page.svelte` — this file remains the
single source of truth for the menu tree and its ids. As of this ADR:

| Id | Label | Parent |
|---|---|---|
| `kb-search` | Knowledge Stores | *(top-level)* |
| `kb-import` | Injestion | *(top-level; also its own single child, "Upload Files")* |
| `kb-doc-wiki` | Wiki | *(top-level)* |
| `kb-llm-wiki` | LLM Wiki | Wiki |
| `kb-llm-wiki-v3` | LLM Wiki v3 | Wiki |
| `kb-input-details` | Document Metadata | Wiki |
| `kb-doc-structure` | Document Structure | Wiki |
| `kb-summary-tree` | Document Tree | Wiki |
| `kb-summary-graph` | Artifact Wiki | Wiki |
| `kb-semantic-projections` | Semantic Projections | Wiki |
| `kb-topic-tree` | Document Topic Tree | Wiki |
| `kb-metrics` | Metrics | Wiki |
| `kb-scene-blocks` | Scene Blocks | Wiki |
| `kb-products` | Products | Wiki |
| `kb-provision-tree` | Provisions | Wiki |
| `kb-inventory-items` | Inventory Items | Wiki |
| `kb-object-manager` | Object Manager | Wiki |
| `kb-references` | References | Wiki *(under construction)* |
| `kb-formulas` | Formulas | Wiki *(under construction)* |
| `kb-tables` | Tables | Wiki *(under construction)* |
| `kb-quotations` | Quotations | Wiki *(under construction)* |
| `kb-case-studies` | Case Studies | Wiki *(under construction)* |
| `kb-workflow` | Workflow | Wiki *(under construction)* |
| `kb-product-parts` | Product and Parts | Wiki *(under construction)* |
| `kb-chunks` | Document Processing | *(top-level; also its own child, "Document Chunking")* |
| `kb-category-review` | Category Review | Document Processing |

Note: `kb-import` and `kb-chunks` each double as both the top-level
section id and the id of that section's (first) child — this predates
this change. Toggling either of those ids affects the parent and that
specific child together, since they represent the same concept.

To confirm the current, authoritative id list at any time, check the
`menuItems` array in `web/src/routes/home3/knowledge/+page.svelte` (and
`KNOWLEDGE_UNDER_CONSTRUCTION_SECTIONS` in
`web/src/lib/components/home3/knowledge-sections.js` for the "under
construction" Wiki children) — this ADR's table is a snapshot and can go
stale as the menu evolves. No Go-side id list exists (see DR4); this is
intentional.

### Verifying configuration

`GET /api/v1/kb/menu-config` (authenticated) returns the resolved map, e.g.:
```json
{"status":true,"menus":{"kb-metrics":false,"kb-import":false}}
```
An empty `menus: {}` means no overrides are configured (full menu shown).

## Consequences
- Operators can hide sidebar sections/items per deployment by editing
  `config.local.toml` and restarting the backend — no frontend code
  change or rebuild required.
- No breaking change: omitting `[knowledge-menus]` is behaviorally
  identical to before this change.
- The frontend menu definition (`+page.svelte`) remains the single source
  of truth for ids/hierarchy; config only toggles visibility, it cannot
  define new items.
- Deep links to a section whose sidebar entry is hidden still work (the
  view component still exists); only the sidebar entry is absent. This is
  an accepted, intentional gap — not handled by this change.

## Tests
See "Tests" under Implementation above.

## Documentation Impact
- This ADR is the doc of record for the `[knowledge-menus]` capability.
  No other existing document described the Wiki sidebar menu prior to
  this change, so nothing else went stale.
- OpenSpec artifacts (proposal/design/spec/tasks, all completed) remain
  under `ChenWeb/openspec/changes/configurable-knowledge-menus/` as the
  detailed design record; this ADR summarizes them for the knowledge base.

## References
- `ChenWeb/openspec/changes/configurable-knowledge-menus/proposal.md`
- `ChenWeb/openspec/changes/configurable-knowledge-menus/design.md`
- `ChenWeb/openspec/changes/configurable-knowledge-menus/specs/knowledge-menu-config/spec.md`
- `ChenWeb/openspec/changes/configurable-knowledge-menus/tasks.md`
- `ChenWeb/server/cmd/config/config.go`
- `ChenWeb/server/api/kbhandler/kb_menu_handler.go`
- `ChenWeb/web/src/routes/home3/knowledge/+page.svelte`
- `ChenWeb/config.local.toml`
