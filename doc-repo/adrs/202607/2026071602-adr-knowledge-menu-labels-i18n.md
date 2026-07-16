# ADR 2026071602 — Multi-Language, Configurable Labels for the Wiki Sidebar Menu

**Date:** 2026-07-16 \
**Status:** Implemented \
**Component:** ChenWeb `/home3/knowledge` (Wiki sidebar) \
**Authors**: Chen Ding \
**Tags**: ChenWeb, frontend, i18n, configuration, openspec \

## Change Logs
* 2026/07/16, ADR created; implementation completed and verified.
* 2026/07/16, Addendum: added visible diagnostics for unrecognized menu ids in both `[knowledge-menus]` (ADR 2026071601) and `labels-<lang>.toml` (this ADR), after the same class of typo (guessing an id from its label instead of using the real id) recurred independently in both config surfaces across two separate reports. See "Addendum" section below.

## Context

ADR 2026071601 (`configurable-knowledge-menus`) let operators toggle Wiki
sidebar menu item *visibility* via `[knowledge-menus]` in
`config.local.toml`. It left every label ("Metrics", "Wiki", "Document
Processing", ...) as a hardcoded English string in
`web/src/routes/home3/knowledge/+page.svelte`.

Two follow-up needs came up in practice: showing menu labels in the
user's chosen site language, and letting an operator rename a label
without a frontend code change. Investigation found two pre-existing,
independent "language" mechanisms in ChenWeb, neither reaching
`/home3/knowledge`:

1. **Paraglide-js** (`@inlang/paraglide-js`), the real site-wide UI
   locale (`getLocale()`/`setLocale()` from `$lib/paraglide/runtime`,
   `locales = ["en", "zh-cn"]`), used only on `/semos` pages.
2. A page-local `?lang=` URL query param on this same knowledge page,
   used only for Wiki *article content* language (LLM-translated), unrelated
   to UI chrome.

Separately, `config/site/site-default-<lang>.toml` established a
precedent: content is configured via one TOML file per language. The
user's direction (given during design) was explicit: Paraglide's locale
should become the *one* site-wide language control, "menus are content,"
and full cross-session language persistence is a known, separate,
explicitly deferred problem — not solved by this change.

This work was tracked as the OpenSpec change
`openspec/changes/knowledge-menu-labels-i18n` (proposal, design, spec,
tasks all completed; see References).

## Decision

### DR1 — Paraglide's `getLocale()` is the language signal
`+page.svelte` imports `getLocale` from `$lib/paraglide/runtime` — its
first-ever use of Paraglide — and uses it, not the page's existing
`?lang=` param (which stays scoped to Wiki article content, untouched),
to decide which language's labels to request.

### DR2 — New dedicated directory: `config/knowledge-menus/`
Label files live at `config/knowledge-menus/labels-<lang>.toml`, not
inside `config/site/`. `config/site/*` is tenant-scoped, customer-facing
marketing content loaded through unrelated machinery
(`sitehandler.go`, `site_tenants` table). `/home3/knowledge`'s menu
config is a different, operator-facing domain (it already lives partly
in `config.local.toml`). A new directory keeps the *pattern*
(file-per-language) without inheriting tenant-scoping machinery that
doesn't apply here.

### DR3 — Direct file read per request, not viper/`AppConfigDef`
Unlike `[knowledge-menus]` visibility (a `config.local.toml`-overridable
toggle merged via viper), label files are whole content files selected
by language — analogous to how `config/site/site-default-<lang>.toml`
is read directly (`go-toml/v2`) rather than merged/overlaid. There is no
"`config.local.toml` overrides `labels-en.toml`" concept: the file for a
language *is* the config for that language.
`server/api/kbhandler/kb_menu_labels.go` reads and parses the file for
the requested `lang` on each request (small file; matches
`kb_config_handler.go`'s existing direct-read-per-request pattern).

### DR4 — Two-tier fallback only: requested-language file → hardcoded default
Considered adding a middle tier using `[languages].default` from
`config.local.toml` (currently `"zh"`). Rejected: that value doesn't
match Paraglide's actual locale codes (`"en"` / `"zh-cn"`) — `"zh"` vs
`"zh-cn"` is a pre-existing inconsistency in the codebase, out of scope
to fix here. The fallback is simply: (1) `labels-<requested-lang>.toml`
has an entry for this id → use it; (2) otherwise → the existing
hardcoded label in `+page.svelte`, which continues to serve as the
universal baseline exactly as before this change.

### DR5 — Extend the existing endpoint; no new one
`GET /api/v1/kb/menu-config` gained an optional `lang` query parameter
and a `labels: Record<string,string>` field, rather than a second
endpoint — the frontend already fetches this endpoint once on mount.
`lang` omitted or unrecognized resolves to `labels: {}` (fail-open, same
posture as an empty `[knowledge-menus]` map).

### DR6 — Label resolution happens server-side
The handler returns only the *resolved* overrides for the requested
language, not every language's data — the frontend asks for the one it
currently needs (matching how `?lang=`-driven Wiki content endpoints
already work), rather than bundling a Paraglide-style compile-time
catalog of every language.

### Alternative Decisions
- Bundle labels into Paraglide's own compile-time message catalog
  (`web/messages/*.json`) — rejected. Those are baked into
  `web/src/lib/paraglide/messages/*.js` at build time, so they'd be
  developer-editable but not *operator*-configurable at runtime without
  a rebuild+redeploy, defeating the point.
- Nest labels inside `[knowledge-menus]` in `config.local.toml` as
  `map[string]map[string]string` — rejected (see DR2/DR3): mixes an
  operator-toggle-style merged config (visibility) with a content-file
  artifact (labels) in one file, and `config.local.toml` is documented
  as "typically not committed" — wrong for translated content that
  should be reviewable/versioned like `config/site/*.toml` already is.
- Reuse the page's existing `?lang=` param instead of Paraglide —
  rejected per explicit user direction (DR1): that param already does a
  different job (Wiki content language).
- A middle `[languages].default` fallback tier — rejected, see DR4.

### Database Migrations
None.

### Data Formats
- `config/knowledge-menus/labels-<lang>.toml`:
  ```toml
  [labels]
  kb-metrics = "指标"
  kb-doc-wiki = "知识百科"
  ```
  Optional per language; ids not listed use the hardcoded default label.
- `GET /api/v1/kb/menu-config?lang=<code>` response, extended:
  ```json
  {
    "status": true,
    "menus": { "kb-metrics": false },
    "labels": { "kb-metrics": "指标", "kb-doc-wiki": "知识百科" }
  }
  ```

### Environment Variables
- `KNOWLEDGE_MENU_LABELS_DIR` (test/deployment override, mirrors
  `KB_CONFIG_FILE`'s role for `resolveKbConfigFilePath`): when set,
  points at the directory containing `labels-<lang>.toml` files instead
  of walking up from the working directory to find the repo root.

## Implementation

### Code Changes
- `config/knowledge-menus/labels-en.toml` (new, empty `[labels]` table
  plus format-documenting comments) and `config/knowledge-menus/labels-zh-cn.toml`
  (new, illustrative starter entries: `kb-search`, `kb-doc-wiki`, `kb-chunks`).
- `server/api/kbhandler/kb_menu_labels.go` (new): `LoadKnowledgeMenuLabels(lang)`
  — validates `lang` against a locale-code shape (`^[a-zA-Z0-9-]{1,20}$`,
  rejecting path-traversal-shaped input before it ever reaches a file
  path), resolves and reads `labels-<lang>.toml`, returns `map[string]string`.
  Missing file/invalid lang → empty map, no error. Malformed TOML in an
  existing file → error (surfaced, not silently swallowed).
- `server/api/kbhandler/kb_menu_handler.go`: `GetKbMenuConfig` now reads
  `c.QueryParam("lang")`, calls the loader, adds `labels` to the response
  (logging a warning and falling back to `{}` if the loader errors).
- `web/src/lib/services/kbService.ts`: `getKbMenuConfig(lang?)` appends
  `?lang=`; new `KbMenuLabels` type; return value is now
  `{ menus, labels }`.
- `web/src/routes/home3/knowledge/+page.svelte`: imports `getLocale`;
  `onMount` calls `getKbMenuConfig(getLocale())` into new `menuLabels`
  state; `visibleMenuItems` derivation resolves each surviving item's
  `label` as `menuLabels[item.id] ?? item.label` (descriptions
  untouched, per the stated non-goal).

### Tests
- `server/api/kbhandler/kb_menu_labels_test.go`: missing file → empty
  map; populated `[labels]` table → correct map; malformed TOML →
  error; path-traversal-shaped `lang` → empty map (no file access
  attempted).
- `server/api/kbhandler/kb_menu_handler_test.go`: `lang` omitted →
  `labels: {}`; `lang` matching a configured file → populated `labels`;
  `lang` with no matching file → `labels: {}`, `menus` unaffected.
- All new/updated tests pass; `go build ./...` and `svelte-check`
  (0 errors/warnings in touched files) both pass.
- Manually verified end-to-end in a logged-in browser session against
  the local dev stack (`https://dingbo.bzton.cn`):
  - `GET /api/v1/kb/menu-config` (no `lang`) and `?lang=en` both return
    `labels: {}` (the `labels-en.toml` starter file is empty); `?lang=zh-cn`
    returns the three configured overrides; `menus` is identical across
    all three requests.
  - Fresh page load (Paraglide's default/base locale, `zh-cn`, since no
    prior client-side `setLocale()` call exists yet in the session):
    sidebar shows "知识库" (Knowledge Stores), "知识百科" (Wiki),
    "文档处理" (Document Processing) — all three configured overrides —
    while "Injestion" (no override configured for `kb-import`) correctly
    stays at its hardcoded English default. Descriptions remained
    untranslated, as intended.

## Operational Behaviors — How to Configure Menu Labels

Add or edit `config/knowledge-menus/labels-<lang>.toml` (create the file
if it doesn't exist yet for that language — see `labels-en.toml` /
`labels-zh-cn.toml` for the format):

```toml
[labels]
kb-metrics = "指标"       # rename/translate the "Metrics" item
kb-doc-wiki = "知识百科"   # rename/translate the "Wiki" section itself
```

- **Ids** are the same menu item ids used by `[knowledge-menus]`
  visibility (ADR 2026071601 has the full id → label → parent table).
  This ADR does not duplicate that table; consult ADR 2026071601, or
  `menuItems` in `web/src/routes/home3/knowledge/+page.svelte`, as the
  authoritative current id list.
- **Ids not listed** in a language's file keep their hardcoded default
  (English) label for that language.
- **`<lang>`** must match a value Paraglide's `getLocale()` can return
  — currently `en` or `zh-cn` (`web/src/lib/paraglide/runtime.js`'s
  `locales`). A file for any other value is simply never requested by
  the frontend today.
- **This does not control visibility.** Whether an item shows up in the
  sidebar at all remains `[knowledge-menus]` in `config.local.toml`
  (ADR 2026071601), entirely independent of language.
- **Changes take effect on the next request** to
  `GET /api/v1/kb/menu-config?lang=<code>` — the file is read fresh per
  request (DR3), no backend restart required (unlike `[knowledge-menus]`
  visibility, which is loaded once at startup via viper).
- **Which language is requested is controlled by Paraglide's site-wide
  locale** (the same control used on `/semos`), not by anything on the
  `/home3/knowledge` page itself. **Known limitation, explicitly out of
  scope for this change:** Paraglide's locale does not yet persist
  across a full page navigation/reload in this deployment (its active
  strategy is `["globalVariable", "baseLocale"]` — no `cookie` or
  `localStorage` tier is active yet), so a fresh visit to
  `/home3/knowledge` currently always requests the base locale
  (`zh-cn`) regardless of a language choice made earlier in the same
  browser session. Persisting the user's chosen language is a
  pre-existing, separate problem the user has deferred; this change
  does not attempt to fix it.

### Verifying configuration
```
GET /api/v1/kb/menu-config?lang=zh-cn
{"status":true,"menus":{...},"labels":{"kb-metrics":"指标", ...}}
```
An empty `labels: {}` means no overrides are configured for that
language (or the language wasn't recognized/no file exists).

## Consequences
- Operators can translate or rename individual sidebar labels per
  language by editing a small TOML file — no frontend rebuild/redeploy.
- No breaking change: a deployment with empty/absent label files behaves
  exactly as before this change, for every language.
- Visibility and labels are deliberately two separate configuration
  surfaces (`config.local.toml` vs. `config/knowledge-menus/`), loaded
  through two different mechanisms (viper-merged vs. direct-read), each
  matching the shape of what it configures (an operator toggle vs.
  reviewable translated content) — see DR2/DR3.
- The sidebar's actual displayed language now depends on Paraglide's
  locale, which is not yet persisted across navigations — a known,
  pre-existing gap this change surfaces but does not close.
- Menu item *descriptions* remain untranslated; the same file/endpoint
  shape could add a `descriptions` field later without a breaking change.

## Tests
See "Tests" under Implementation above.

## Documentation Impact
- This ADR is the doc of record for "how to configure menu labels,"
  complementing ADR 2026071601 (visibility). Together they fully
  describe the `/home3/knowledge` Wiki sidebar menu's configuration
  surface as of this date.
- OpenSpec artifacts (proposal/design/spec/tasks, all completed) remain
  under `ChenWeb/openspec/changes/knowledge-menu-labels-i18n/` as the
  detailed design record.

## Addendum (2026-07-16): Diagnostics for unrecognized menu ids

**Problem.** Both `[knowledge-menus]` (ADR 2026071601) and
`labels-<lang>.toml` (this ADR) were explicitly designed with no
server-side validation of ids (DR4 in each ADR), to avoid duplicating the
authoritative id list — which lives only in `menuItems` in `+page.svelte`
— in Go as well. The accepted trade-off was that an id typo (most often,
guessing an id from its display label instead of using the real one,
e.g. `kb-document-metadata` for "Document Metadata" instead of the real
`kb-input-details`) would be silently inert: no error, no warning,
nothing — the entry just does nothing. Both ADRs' Risks sections flagged
this as a known, accepted gap.

In practice, this exact class of mistake occurred independently in both
config surfaces (visibility and labels) across two separate rounds of
manual config editing, each requiring the id list to be manually diffed
against the config to find the problem. That crossed from "accepted risk"
to "recurring usability bug."

**Fix.** Rather than add server-side validation (which would still
require the previously-rejected duplicate id list in Go), the diagnostic
was added where the authoritative id list already lives: the frontend.
`web/src/routes/home3/knowledge/+page.svelte` now:
- Computes `knownMenuIds`, a `Set<string>` flattened from `menuItems`
  (top-level ids + all children ids) — the same array that is already
  the single source of truth.
- Derives `unknownMenuConfigIds` / `unknownMenuLabelIds`: the keys of the
  fetched `menuConfig` / `menuLabels` maps that aren't in `knownMenuIds`.
- `console.warn()`s a message naming the exact unrecognized id(s) and
  which config surface they came from.
- Renders a small, non-blocking amber banner directly in the sidebar
  (visible whenever the menu isn't collapsed) listing the unrecognized
  id(s) and the file they came from (`config.local.toml [knowledge-menus]`
  or `labels-<lang>.toml`) — chosen over console-only output because this
  page's own audience (an operator editing its config) is exactly who
  needs to see it, and they are looking at the rendered page, not
  DevTools.

This directly caused the two reported symptoms to be fixed as part of
this addendum:
- `config.local.toml`: `kb-product-and-parts` → `kb-product-parts`.
- `config/knowledge-menus/labels-zh-cn.toml`: `kb-injestion` /
  `kb-upload-files` → `kb-import` (see next point), `kb-document-metadata`
  → `kb-input-details`, `kb-document-structure` → `kb-doc-structure`,
  `kb-document-tree` → `kb-summary-tree`, `kb-provisions` →
  `kb-provision-tree`.

**New limitation surfaced, not introduced, by this fix:** `kb-import` is
both the "Injestion" section header id and its single child "Upload
Files" row's id (a pre-existing collision noted in ADR 2026071601's
Risks section, predating both ADRs). Because labels are resolved by id,
this collision means the parent header and the child row **cannot** have
independently configured labels — only one `kb-import` entry can exist
in a `[labels]` table, and both rendered instances will show the same
text. `labels-zh-cn.toml` currently uses it for the parent-level text
("文件管理"); the child-row-specific text that was attempted
("上传文件") cannot be separately represented without first resolving
the underlying id collision, which remains out of scope.

**What this does not solve:** ids are still validated only client-side,
after a fetch; there is still no server-side rejection of bad config
(the endpoint still returns them as fail-open no-ops), and the id list is
still hand-maintained only in `+page.svelte` (unchanged from DR4 in both
ADRs — still the intentional choice to avoid a second, driftable copy of
the id list in Go).

### Code Changes (addendum)
- `web/src/routes/home3/knowledge/+page.svelte`: `knownMenuIds`,
  `unknownMenuConfigIds`, `unknownMenuLabelIds`, a `console.warn`-emitting
  `$effect`, and the amber diagnostic banner in the sidebar template.
- `config.local.toml`, `config/knowledge-menus/labels-zh-cn.toml`:
  corrected the ids listed above.

## References
- ADR 2026071601 — `configurable-knowledge-menus` (visibility mechanism;
  full menu id → label → parent table)
- `ChenWeb/openspec/changes/knowledge-menu-labels-i18n/proposal.md`
- `ChenWeb/openspec/changes/knowledge-menu-labels-i18n/design.md`
- `ChenWeb/openspec/changes/knowledge-menu-labels-i18n/specs/knowledge-menu-labels/spec.md`
- `ChenWeb/openspec/changes/knowledge-menu-labels-i18n/tasks.md`
- `ChenWeb/server/api/kbhandler/kb_menu_labels.go`
- `ChenWeb/server/api/kbhandler/kb_menu_handler.go`
- `ChenWeb/web/src/routes/home3/knowledge/+page.svelte`
- `ChenWeb/web/src/lib/paraglide/runtime.js`
- `ChenWeb/config/knowledge-menus/labels-en.toml`,
  `ChenWeb/config/knowledge-menus/labels-zh-cn.toml`
