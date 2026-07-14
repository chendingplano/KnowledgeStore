# Design: Per-Locale Site-Config Files for ChenWeb/semos

**Date:** 2026-07-14
**Status:** Draft (design, not yet implemented)
**Component:** Site-config loading for the SemOS customer-facing frontend
(`server/api/sitehandler`, `config/site/*.toml`)
**Related:** [2026071102-adr-new-gui-semos.md](../../../../KnowledgeStore/doc-repo/adrs/202607/2026071102-adr-new-gui-semos.md)
— resolves that ADR's open question "Nav labels vs. config."

## Context

The ADR established that tenant-independent and tenant-dependent page
content lives in one complete site-config TOML file per tenant
(`config/site/site-default.toml`, `config/site/tenant-demo.toml`, ...),
served by `server/api/sitehandler` and consumed by the Svelte frontend. That
design left one thing unresolved: none of this content is actually
localized. Nav labels are translated via the existing
`@inlang/paraglide-js` message catalog (`web/messages/en.json`,
`zh-cn.json`), but site-config content (hero, highlights, features, footer,
stats, workspace apps) is a single hardcoded-language blob per file today —
`site-default.toml` currently mixes English (branding/hero) and Chinese
(highlights/features/footer), which isn't a real localization, just an
accident of how it was authored.

This is a general problem, not specific to the Main page: every
configurable page (tenant-independent or tenant-dependent) will hit the same
question as configurable content rolls out to more pages. This design
answers it once, for both axes (tenant, language).

Message catalogs (the mechanism nav labels use) were considered and ruled
out for this content: they're global/compiled, not naturally per-tenant, so
they don't fit the "each tenant edits their own content via Site
Management" requirement.

## Design

### File naming

One file per (tenant-or-default, locale) pair:

```
config/site/site-default-en.toml
config/site/site-default-zh-cn.toml
config/site/tenant-demo-en.toml
config/site/tenant-demo-zh-cn.toml
```

Pattern: `{base}-{locale}.toml`, where `base` is a path with no extension
(e.g. `config/site/site-default`) and `locale` is one of
`[frontend].supported_languages` in `config.toml`.

`[config].config_filename` in `config.local.toml`, and
`site_tenants.config_filename`, change from a literal `.toml` path to this
base stem (e.g. `config/site/site-default` instead of
`config/site/site-default.toml`).

`ja`/`ko` files are not created as part of this change — no content exists
for them yet, and per the resolution algorithm below their absence isn't an
error, so they can be added later without a code change.

### Locale resolution

`[frontend].default_language` changes from `["zh-cn"]` (a one-element list)
to `default_language = "zh-cn"` (a scalar) — this design needs a single
default locale value, and the list form looks like an existing
inconsistency rather than an intentional multi-value default.

Given a requested locale `L` and `base`:

1. Try `{base}-{L}.toml`. If it exists, that's the resolved file. No log.
2. Not found → try sibling locales: other entries in
   `[frontend].supported_languages` that share `L`'s family (the part of the
   locale code before the first `-`; e.g. `zh-cn` and `zh-tw` are both
   family `zh`) and have a file on disk. If found, that's the resolved file.
   **No warning logged** — same-family substitution (e.g. simplified ↔
   traditional Chinese) is treated as an acceptable substitute, not a gap.
   (No-op today since only `zh-cn` is in `supported_languages`; takes effect
   automatically once a sibling like `zh-tw` is added.)
3. Still not found → resolved file is `{base}-{default_language}.toml`.
   **Log a warning** (translation missing for locale `L`, served
   `default_language` instead) — this is a real content gap, not an
   equivalent substitution, so it should be visible in logs per the
   workspace's logging conventions.
4. `{base}-{default_language}.toml` is required to exist. If it's missing,
   that's a hard config error (no further fallback, no unsuffixed
   no-locale-symbol file kept as a last resort).
5. `L` not present in `[frontend].supported_languages` at all → reject the
   request (400), rather than silently falling back — this surfaces a
   caller bug (e.g. a typo'd `?locale=` param) instead of masking it.

### Content merge (partial-translation fallback)

`{base}-{default_language}.toml` is always loaded first into the
`SiteConfig` struct — this is the base content. If the resolved file from
the algorithm above is a *different* file, it is `toml.Unmarshal`'d **on top
of the same struct**. `go-toml` only overwrites keys present in the source
document, so fields the resolved file doesn't specify keep their
default-language values. This gives per-field fallback for partial
translations (e.g. a locale file with only `[hero]` translated leaves
`[[highlights]]` etc. at the default-language content) without any extra
merge code — it falls out of how `Unmarshal` already behaves.

Table-array sections (`[[highlights]]`, `[[features]]`,
`[[workspace.apps]]`, `[[stats]]`, `[[footer.quick_links]]`,
`[[footer.resources]]`) replace the whole slice if present in the resolved
file at all — TOML doesn't support partial-array merge, so translating a
table-array section means translating the entire array, not individual
entries. This is a reasonable content boundary (a translator does one whole
section at a time) and doesn't need special-casing in code.

### API contract

`GET /api/site-config?locale=ja` and
`GET /api/v1/site-config/tenant/:tenant_id?locale=ja` — `locale` becomes an
optional query param, defaulting to `[frontend].default_language` when
absent. Response JSON shape is **unchanged** — same `SiteConfig` struct as
today. No changes to Go structs (`sitehandler.go`) or TS interfaces
(`siteConfigService.ts`); only the loading/resolution logic changes.

`LoadSiteConfig` signature changes from `LoadSiteConfig(path string)` to
`LoadSiteConfig(base, locale, defaultLocale string, supportedLocales
[]string) (*SiteConfig, error)`, implementing the resolution + merge
algorithm above internally.

### Migration of existing files

- `site-default.toml` → renamed to `site-default-zh-cn.toml`. Its current
  branding/hero fields are English, not Chinese — they need real Chinese
  translation to be a true zh-cn file. `site-default-en.toml` is new; its
  highlights/features are currently Chinese and need English translation.
- `tenant-demo.toml` → renamed to `tenant-demo-en.toml` (it's already
  all-English, so this is close to a pure rename). `tenant-demo-zh-cn.toml`
  is new, needs translation.
- **Translation content itself is out of scope for this design/plan** — the
  implementation should leave clearly marked TODOs (e.g. a
  `# TODO(i18n): needs real zh-cn translation` comment, matching the
  existing PLACEHOLDER convention already used for the stats band) rather
  than fabricating marketing copy as a stand-in for real translation.
- `config.local.toml`'s `[config].config_filename` and the
  `site_tenants.config_filename` column values are updated to the new base
  stem (a data change, not a schema migration — the column type doesn't
  change).

### Testing

- `sitehandler_test.go` / `testdata/site-valid.toml`: rename fixtures to
  the new per-locale naming (e.g. `testdata/site-valid-en.toml`,
  `testdata/site-valid-zh-cn.toml`).
- Add a test for partial-translation overlay: a locale file with only some
  sections present, verifying untranslated sections fall back to
  default-language content.
- Add a test for the family-sibling fallback (e.g. requesting a
  `zh`-family locale not on disk, with a sibling present, resolves silently
  with no warning logged).
- Add a test for the missing-default-locale-file hard-error case.
- Add a test for the unsupported-locale-param 400 case.

## Out of scope

- The Site Management admin UI itself (future work; this design only
  covers the file format and loading mechanism it will read/write).
- Reconciling `[frontend].supported_languages` with `config.local.toml`'s
  separate `[languages]` section — already a deferred item in the ADR.
- Producing actual `ja`/`ko` translations, or completing the `en`/`zh-cn`
  translations flagged above as TODOs.
