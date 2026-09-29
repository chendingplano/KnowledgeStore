# ADR 2026093001 — Paraglide Is the Standard for ChenWeb Interface Text

**Date:** 2026-09-30 \
**Status:** Accepted \
**Component:** ChenWeb frontend (`web/`) — all pages \
**Authors**: Chen Ding \
**Tags**: ChenWeb, frontend, i18n, paraglide, page-config

## Change Logs
* 2026/09/30, ADR created. Steps 1–3 below implemented (openspec change
  `i18n-paraglide-standard`); step 4 (converting existing pages) not started.

## Context

Every ChenWeb page must be usable in English and Chinese, and every future page
must be too. Two mechanisms for language-dependent text exist side by side:

- **Paraglide** (`@inlang/paraglide-js`, since the project began): a dictionary
  per language in `web/messages/en.json` and `web/messages/zh-cn.json`, compiled
  into typed functions (`m.<key>()`) that return the text for the current locale.
  The locale (`getLocale()`) is chosen by the header's 中文/English switch.
- **`kb.page_config`** (spec
  [2026072001](../../specs/202607/2026072001-spec-page-content-configurability-i18n.md) §9–11,
  ADR [2026072003](../202607/2026072003-adr-db-backed-page-config.md)): text
  stays in code as the default; rows keyed by `page_key` + `entry_key` +
  `language` override it at runtime, and also hide entries or restrict them by
  role.

`kb.page_config` was built to make menus configurable by operators, and was
then being used as the way to translate pages. In practice that is manual and
slow: each string needs a row per language added by a migration; nothing checks
the keys, so a typo silently shows the English default; the text is split
between code and database and has to be copied from dev to production. The
`development` menu alone had ~99 hand-maintained Chinese rows, and new menu
items (e.g. *Review Metrics*) stayed English because nobody added a row.

Coverage on 2026-09-30: only 3 of 88 `home3/*-view.svelte` components used
Paraglide; the rest of the interface has its text written directly in code
(5,403 strings in 235 `.svelte` files, per the check below).

The requirements set for this decision: i18n must be **easy to maintain**, and
**new pages must support English and Chinese automatically**; use the in-house
`kb.page_config` if it meets both, otherwise Paraglide.

## Decision

**DR1 — All user-visible interface text goes through Paraglide.** Every string a
user sees in a `.svelte` page or component is an `m.<key>()` call, with the key
present in both `en.json` and `zh-cn.json`, added in the same change as the page.
`kb.page_config` does not meet the first requirement (per-string migrations, no
checking, database-to-production sync), and neither mechanism meets the second
by itself — someone has to write the Chinese — so the choice is Paraglide plus
enforcement (DR2).

**DR2 — Enforced by `bun run check`.** `web/scripts/check-i18n.ts` runs as part
of `bun run check`:
- *Parity* (hard failure): both message files have the same keys, none empty.
- *Hard-coded text* (ratchet): text written directly in `.svelte` markup — text
  nodes and `placeholder`/`title`/`aria-label`/`alt`/`label` attributes, outside
  `<code>`/`<pre>` — is counted per file against `web/i18n-baseline.json`. A new
  file with any, or an existing file whose count grows, fails. When a page is
  converted, `bun scripts/check-i18n.ts --update` lowers its entry.
- Not covered: strings built in `<script>` (e.g. option lists, toasts). The rule
  still applies to them; review catches them.

**DR3 — `kb.page_config` keeps what only it can do.** Showing/hiding entries,
role-based access, and an optional per-language override of a label without a
deploy. It is no longer where translations are maintained. Defaults always come
from Paraglide; a `page_config` label, when present, overrides them.

**DR4 — The `/development` NavRail menu uses Paraglide defaults.** Every menu
item's label is `m.nav_<id>()` (id with `-` → `_`), group headings are
`m.nav_group_<group>()`. The Chinese text was taken from the existing
`kb.page_config` rows so nothing visible changes; 21 items that had no Chinese
row got one. Migration `20260930000001_strip_nav_label_overrides_now_in_paraglide.sql`
removes the `label` from the 98 `development`/`resources` rows whose label equals
the new default, so later edits to the message files are not shadowed by stale
rows. Rows are kept (they carry visibility and `access_role`), and a label an
operator changed is not touched.

### Alternative Decisions

- **Make `kb.page_config` the dictionary for all pages** — rejected for the
  maintenance cost above; it would need a key generator, a type check and a
  dev→prod sync to reach what Paraglide already provides.
- **Remove `kb.page_config` labels entirely** — rejected; operators lose the
  ability to rename an entry without a deploy, and visibility/access still need
  the rows.
- **A lint that fails on every existing hard-coded string** — rejected for now;
  235 files would fail at once. The ratchet stops growth and lets conversion
  proceed page by page.

### Database Migrations

`project_migrations/20260930000001_strip_nav_label_overrides_now_in_paraglide.sql`
(data only; Down is a no-op because the removed labels equal the defaults).

## Implementation

### Code Changes

- `web/scripts/check-i18n.ts` (+ `check-i18n.test.ts`), `web/i18n-baseline.json`,
  `web/package.json` (`check` runs it; `check:i18n` alone).
- `web/src/lib/components/home3/nav-rail.svelte`: labels, group headings, rail
  title and user menu through `m.*()`.
- `web/messages/{en,zh-cn}.json`: `nav_*` keys.
- `ChenWeb/CLAUDE.md` §3: the rule and the workflow.

## Operational Behaviors

- A page added without messages, or a message added to one language only, fails
  `bun run check`.
- Changing a menu label now means editing the message files. An existing
  `kb.page_config` label for that entry still wins — remove it if the new default
  should show.
- Paraglide reloads the page on a language switch, so text is resolved once per
  page load.

## Consequences

- Translations live in two version-controlled JSON files, reviewed with the code
  and deployed with the build.
- The ~5,400 existing hard-coded strings are a visible, shrinking backlog
  (`i18n-baseline.json`) rather than a hidden one.
- Text the **server** sends to users (error messages, LLM output) is outside
  Paraglide; such features pass the locale to the server (as Review Metrics does
  with `lang`) and are handled case by case.

## Tests

- `bun test scripts/check-i18n.test.ts` — detection rules and parity.
- Verified the check fails for a new component with hard-coded text and for a key
  missing from `zh-cn.json`, and passes on the current tree.
- Migration dry-run in a rolled-back transaction on `miner`: 98 rows updated,
  89 rows per language remain.

## Documentation Impact

- Spec 2026072001 §11 (recipe) now points here: new pages do not add
  `kb.page_config` rows for translation.
- `ChenWeb/CLAUDE.md` §3 carries the working rule.

## References

- Spec [2026072001 — Page Content Configurability and i18n Pattern](../../specs/202607/2026072001-spec-page-content-configurability-i18n.md)
- ADR [2026072003 — DB-backed page config](../202607/2026072003-adr-db-backed-page-config.md)
- openspec change `ChenWeb/openspec/changes/i18n-paraglide-standard`
