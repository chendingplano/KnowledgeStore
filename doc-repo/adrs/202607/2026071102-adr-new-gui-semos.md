# Design Brief - New Customer-Facing Frontend for SemOS

**Date:** 2026-07-11 \
**Status:** Draft (design thinking, not yet a decision) \
**Component:** New customer-facing web frontend (separate from ChenWeb/home3) \
**Authors**: Chen Ding\

## Change Logs
* 2026/07/11, Draft Created
* 2026/07/13, Reframed from ADR to design brief; added Audience, Design
  Direction, Sitemap, and Relationship to ChenWeb/home3 sections
* 2026/07/13, Added Cross-Cutting Requirements (i18n, light/dark mode,
  content configurability) and User Management / Site Management pages
* 2026/07/13, Resolved open questions; implementation Phase 1 landed in
  ChenWeb: site_tenants migration, [config].config_filename plumbing,
  config/site/*.toml files, sitehandler package, GET /api/site-config and
  GET /api/v1/site-config/tenant/:tenant_id, /semos layout (i18n +
  light/dark) with Main and Workspace Landing pages. Phases 2 (remaining
  marketing pages) and 3 (User/Site Management, post-auth-ADR) pending.
* 2026/07/13, Resolved open questions: confirmed multi-tenant SaaS model
  (supersedes earlier single-customer/"not white-labeled" framing), dropped
  `root` role in favor of a separate ops-only tenant-provisioning mechanism,
  confirmed file-based content storage, deferred Status page
* 2026/07/13, Resolved remaining open questions: tenant creation lives in
  User Management (DB-insert fallback for v1); SemOS branding default with
  per-customer treatment deferred; auth/role schema explicitly deferred to a
  future ADR (tenants are placeholders for this pass); content config is one
  file per tenant, git-stored, selected per-instance via `config.local.toml`
  (flagged: this means one tenant live per deployment, not simultaneous
  multi-tenant serving — worth confirming); confirmed
  `[frontend].supported_languages` now exists in `config.toml`, noted a
  possibly-overlapping `[languages]` section in `config.local.toml`
* 2026/07/13, Corrected Content Configurability: config is one file per
  tenant with many tenants served simultaneously by one running instance
  (not a single selected config per deployment, as an earlier pass had it) —
  raises a new open question on the per-request tenant resolution mechanism
* 2026/07/13, Resolved tenant resolution: public pages are
  tenant-independent (one shared config via `[config].config_filename`);
  tenant-dependent pages resolve tenant post-login and look up that
  tenant's config filename from the tenant table. Regrouped Sitemap by
  tenant-independent/tenant-dependent (Sign Up, Login, 404, Status moved
  into tenant-independent). No open questions remain for this pass.
* 2026/07/13, Consistency fix: `[config].config_filename` in
  `config.local.toml` names the one shared tenant-independent config file
  only; tenant-dependent config filenames always come from the tenant
  database table, never from `config.local.toml`. Removed a lingering
  reference to the earlier, incorrect `[configuration].config_file` naming.
* 2026/07/14, Documented the as-built config schema (Content
  Configurability): `config/site/site-default.toml` is the Main Page's
  config file. Closed a gap where Main-Page section copy (hero kicker,
  features/CTA headings, stats, footer address/email/link columns) had been
  hardcoded in the Svelte components in violation of this brief — all of it
  now lives in TOML, mirrored by Go structs and TS interfaces. Recorded the
  i18n nav-label exception, and flagged that the stats band had shipped
  fabricated figures (now placeholders). Recorded three parallel Main Page
  design variants (`/semos`, `/semos1`, `/semos2`) and the pending decision
  to choose one and delete the others. Added per-highlight imagery.
* 2026/07/14, Resolved the technical blocker behind the "Nav labels vs.
  config" open question (whether nav labels should move into config itself
  is still open — see Open Questions): site-config content (hero,
  highlights, features, footer, stats, workspace apps) moves to one TOML
  file per (tenant, locale) pair — `site-default-zh-cn.toml`,
  `site-default-en.toml`, etc. — instead of one hardcoded-language file per
  tenant. Locale resolution falls back from the requested locale to
  same-language-family siblings (e.g. simplified ↔ traditional Chinese,
  silent, no warning) and then to `[frontend].default_language` (logged as
  a warning — a real translation gap, not an equivalent substitution); the
  default-language file itself is required to exist, with no further
  fallback below it. Partial per-tenant translation is supported for free:
  the default-language file loads first as a base struct and the resolved
  locale file is unmarshaled on top of it, so fields a translation omits
  keep their default-language values. Full design, including the fallback
  algorithm and file-naming/migration plan:
  [2026-07-14-semos-site-config-i18n-design.md](../../../../ChenWeb/docs/superpowers/specs/2026-07-14-semos-site-config-i18n-design.md).
  Not yet implemented — design only.

## Context
SemOS is a Knowledge Management AI Application system.
It is customer face. Its core components include:
- Knowledge Management System, starting from uploading
  files and collecting files from the Internet, to 
  parsing documents, such as PDF, Word, PPT, ..., to
  extracting artifacts such as extracting metrics,
  compliance provisions, entities and relations, etc.,
  to hybrid search through BM25, semantic search (vector
  similarity), etc.
- AI application System that offers home-grown AI applications
  to end users and an AI application development environment
  in which users can develop their own AI applications and
  off services for profits

## Relationship to ChenWeb/home3

`ChenWeb/home3` is our internal development environment and already implements
most of the real functionality this product needs (Knowledge Base, Chat,
Search, Document Reviews, Agents/Workflows, etc. — see
[design-doc-review-gui.md](../../design/202606/2026062105-design-doc-review-gui.md)
for an example of how deep that functionality already goes).

This new frontend is a **multi-tenant, customer-facing site serving multiple
customer organizations (tenants)** on one deployment — not a dedicated
deployment per customer. It is expected to look substantially different from
`home3` — different visual design, different information architecture,
marketing pages that `home3` doesn't need — but the underlying product
functionality should be **reused, not rebuilt**. `home3` is the source of
truth for what the app *does*; this project is a new presentation layer (and,
where needed, new customer-facing navigation/IA) around that functionality.

**Decision:** "reuse" means the new frontend calls the same backend APIs as
`home3`, with new Svelte components/styling — not a re-skin/embed of
`home3`'s existing components.

## Audience & Positioning

Mixed audience, matching SemOS's two core components:
- **Enterprise / business buyers** — compliance, legal, finance decision-makers
  evaluating a knowledge-management platform. Care about trust, security,
  ROI, case studies.
- **Technical buyers** — developers/technical teams evaluating the
  agent/app-development environment and APIs. Care about docs, technical
  depth, developer experience.

Conversion model is **hybrid**: self-serve signup for individual/team usage,
sales-led (Contact / Book a Demo) for enterprise tier. Marketing pages should
give each audience a clear path — the Security & Trust Center and Docs pages
are the primary "credibility" pages for the enterprise and technical
audiences respectively.

No specific customer/vertical identified yet — positioning is
**generic-enterprise** for now.

Branding: **multi-tenant**, so each tenant customizes their own logo/content
via Site Management (below) — this is effectively per-tenant white-labeling,
which supersedes the earlier single-customer framing. **Decision:** defaults
to visible SemOS branding (e.g. "Powered by SemOS") for all tenants; special
per-customer branding treatment (e.g. suppressing it) is handled if/when a
customer actually needs it, not designed for speculatively now.

## Design Direction

Visual direction: **Modern SaaS, Linear/Stripe-influenced.**

- **Color:** Near-black/near-white base, designed for both light and dark
  mode from the start (see Cross-Cutting Requirements) + a single confident
  accent color for CTAs and highlights, not a multi-color palette.
- **Typography:** Geometric/grotesque sans (e.g. Inter or Geist), tight
  tracking on large headlines, generous line-height in body copy.
- **Imagery:** Real product UI screenshots and abstract mockups over stock
  photography; subtle gradient meshes or grid/dot backgrounds rather than
  illustration-heavy treatments.
- **Layout:** Wide whitespace, 12-col grid, content capped at a max-width
  (not edge-to-edge text), strong vertical rhythm between sections.
- **Motion:** Restrained — scroll-reveal fades, hover states on cards, no
  heavy parallax or auto-playing animation.
- **Density:** Marketing pages sparse and breathing-room-heavy; Workspace/app
  pages denser and more information-forward (standard marketing-vs-app-shell
  split).

## Cross-Cutting Requirements

These apply site-wide (marketing pages and app shell alike), not to any one
page.

### Language (i18n)
- The entire site — marketing and app shell — must support multiple
  languages consistently, not just the Workspace/app pages.
- **Decision:** the supported-language list is config-driven, read from
  `ChenWeb/config.toml`'s `[frontend].supported_languages`. Re-checked —
  this now exists: `supported_languages = ["en", "zh-cn", "ja", "ko"]`,
  `default_language = ["zh-cn"]`.
- **Caveat:** `ChenWeb/config.local.toml` separately has its own
  `[languages]` section (`languages = ["en", "zh"]`, `default = "zh"`),
  which appears to be pre-existing config for the Document Review feature,
  not this frontend. Two overlapping-looking language config surfaces exist
  now — worth confirming `[frontend].supported_languages` is the one this
  new site should read, and that it's not meant to be reconciled with
  `[languages]` first.
- **Decision:** reuses `ChenWeb/web`'s existing `@inlang/paraglide-js` /
  `project.inlang` / `messages/` setup rather than a separate i18n mechanism.
- Needs a persistent language switcher in the global header/footer, consistent
  across every page in the sitemap below.

### Mode (Light / Dark)
- The entire site must support both light and dark mode consistently, with a
  global toggle (header/footer), not a per-page setting.
- Resolves the earlier open question — dark mode is in scope for v1, not
  deferred. Design Direction's color system should be defined as light/dark
  token pairs from the start rather than retrofitted later.
- A flash-of-wrong-theme bug (mode not applied before first paint, so it
  didn't actually hold "consistently across pages" as required above) was
  found and fixed on Main and Workspace — see
  [2026-07-14-semos-main-page-logo-theme-design.md](2026-07-14-semos-main-page-logo-theme-design.md).

### Content Configurability
- Product/feature/user-dependent content (marketing copy, feature
  descriptions, pricing tiers, logos/images, etc.) must be **configurable**,
  not hardcoded into page components — stored in files or a database rather
  than baked into Svelte templates.
- Given the multi-tenant decision above, this content is **per-tenant**, not
  global — each tenant's Site Management edits only their own content.
- Which Workspace apps (Knowledge Base, Chat, Search, Document Reviews,
  Workflows, Agents/Harness) are available to a given tenant/tier is itself
  one of these configurable items, rather than hardcoded per plan.
- This is what makes the **Site Management** page (below) meaningful: it's
  the admin UI over this configurable content store.
- **Decision:** storage is **files**, one **complete configuration file per
  tenant** (not a database table, not a single shared file with per-tenant
  sections). Files live in Git — matches the existing pattern of
  `KnowledgeStore` itself being a git-managed content store, so this isn't a
  new storage paradigm for the workspace.
- **Decision:** one running instance serves **many tenants simultaneously**
  — matches the "multi-tenant SaaS, one deployment" framing in Relationship
  to ChenWeb/home3 and Audience & Positioning. Which tenant a given request
  resolves to depends on whether the page is tenant-independent or
  tenant-dependent — two separate config sources, not one:
  - **Tenant-independent config** (all public/pre-login pages): one shared
    file, named by `[config].config_filename` in `ChenWeb/config.local.toml`.
  - **Tenant-dependent config** (authenticated, tenant-scoped pages): each
    tenant's config filename is looked up from the **tenant database table**
    once the user's tenant is known post-login — never from
    `config.local.toml`, which only ever names the one shared
    tenant-independent file — then that tenant's file is loaded.
  - **New minimal schema requirement:** this means a `tenant` table needs to
    exist now — at minimum `tenant_id` + `config_filename` — to support
    Site Management/Content Configurability. This is narrower than full
    RBAC/role schema, which stays deferred to the future auth ADR (see
    User Management), but the tenant table itself can't wait for that ADR.

#### As-built config schema (2026/07/14)

The tenant-independent file is **`ChenWeb/config/site/site-default.toml`**,
named by `[config].config_filename` in `ChenWeb/config.local.toml`. It is
served to the frontend by `GET /api/site-config`. Per-tenant files (e.g.
`config/site/tenant-demo.toml`) have the same shape and are named by
`site_tenants.config_filename`.

Every string and image the Main page renders comes from this file — nothing
is hardcoded in the Svelte components:

| Section | Drives |
|---|---|
| `[branding]` | `site_name`, `logo_text`, `logo_image`, `powered_by` |
| `[hero]` | `kicker`, `slogan`, `subtitle`, `image`, both CTA labels/hrefs |
| `[[highlights]]` (×5) | `title`, `description`, `image` |
| `[features_section]` | `kicker`, `title`, `subtitle` (heading above the feature cards) |
| `[[features]]` (×4) | `key`, `title`, `description`, `href` |
| `[[stats]]` | `label`, `value` (stats band) |
| `[cta]` | `title`, `subtitle` (closing call-to-action) |
| `[footer]` | `text`, `address`, `newsletter`, `email` |
| `[[footer.quick_links]]`, `[[footer.resources]]` | `label`, `href` |
| `[workspace]`, `[[workspace.apps]]` | Workspace Landing content |

Mirrored by Go structs in `server/api/sitehandler/sitehandler.go` and TS
interfaces in `web/src/lib/services/siteConfigService.ts`; the JSON tags,
TOML keys and TS field names are identical snake_case.

**Exception — navigation labels are NOT in this file.** Header/footer nav
labels come from the i18n message catalog (`semos_nav_*` in
`web/messages/*.json`) because they need per-locale translation, which the
TOML schema did not model. **Update 2026/07/14:** the TOML schema now does
model per-locale content (see per-locale site-config design below), so the
technical blocker is gone — but *whether* nav labels should actually move
into config, to become tenant-configurable, is still an open call, not
decided by that design. That design only defines the mechanism; it doesn't
migrate nav labels into it.

**Warning — placeholder figures.** `[[stats]]` currently ships em-dashes.
An earlier implementation pass hardcoded *invented* numbers ("127K+
Documents Processed", "180+ Enterprise Customers", "4.2M Metrics
Extracted"). These were fabricated, never real metrics. They have been
replaced with `—` and marked PLACEHOLDER in the config file. **Replace with
real figures before launch, or delete the `[[stats]]` block** (the band
renders empty if the array is absent). Do not ship the invented numbers.

## Sitemap / Pages

Page content below (feature descriptions, copy, etc.) is a placeholder for
completeness, not final — the point of this pass is the page inventory and
IA, not the words.

Grouped by the tenant-independent / tenant-dependent split from Content
Configurability, not by pre-login/post-login — Sign Up, Login, 404, and
Status are pre-login but still tenant-independent, since tenant isn't known
until after a successful login.

**Tenant-independent (public, one shared config):**
1. Main (Home)
2. Product Overview — summarizes all capabilities, links out to feature pages
3. Feature pages — Knowledge Base, Chat/Agents, Search, App Development
   (one focused page per capability, Linear/Stripe-style)
4. Pricing
5. Customers / Case Studies
6. Security & Trust Center
7. Docs / Developer Portal
8. Blog / Resources
9. About Us
10. Contact / Book a Demo
11. Changelog / What's New
12. Careers
13. Legal — Terms of Service, Privacy Policy
14. Sign Up
15. Login
16. 404 / Error page
17. Status page — **Decided: defer.** Not enough operational history to
    report yet, and it's not customer-value-critical for v1. Revisit
    post-launch.

**Tenant-dependent (authenticated, resolved via the tenant table post-login):**
18. Workspace Landing
19. Onboarding — first-run experience after signup
20. Account & Billing
21. **User Management** — add/edit/delete users and roles, scoped to the
    acting admin's own tenant; **admin only**
22. **Site Management** — admin UI for a tenant's own logos/images/
    configurable content; **admin only**

### Main Page
This is a marketing focused page, serving as the site's main page. 
It should highlight the major attractive features of SemOS in a Simple, 
Artistic, Modern, and Multi-Media fashion.
- A horizontal menu bar with 'Home', 'Workspace', 'Knowledge Base', 'About Us'
- A banner with company logo, a large image and some slogons
- Product highlights: about 5, each with a about five-line description and an image
- Main features:
  - Knowledge Base
  - Chat with Documents
  - Search the Knowledge Base
  - Agent and App Development
- Sign Up/Login
- Get Started
- a Footer

#### Design variant (resolved, 2026/07/14)

Three visual treatments of this page existed side by side for comparison,
all reading the **same** site-config file (see As-built config schema
above) — they differed only in styling, not in content or data flow.

| Route (historical) | Direction |
|---|---|
| `/semos` | Original. Restrained modern-SaaS; uses the app's existing CSS variable tokens, so it adapts to any palette swap. |
| `/semos1` | Dark and theatrical. Always-dark header, full-bleed dark hero, stats band, bento feature cards. Own hex palette (`#080b14` / accent `#6b7aff`). |
| `/semos2` | Light "paper and ink" — modelled on the reference site the customer likes (miraitaxcpa.com), not copied from it. Image at full strength under a pale paper veil; dark ink text; bronze ornament dividers (diamond + dots) between blocks instead of rules; cards with real depth (gradient surface, top bevel, layered shadows, hover lift). Palette: paper `#faf9f7`/`#f3f1ec`, ink `#17181c`, bronze `#b08d57`. |

**Decided:** `/semos2` ("paper and ink") won and was promoted to the
canonical `/semos` path; the other two were deleted. Full rationale and
implementation detail:
[2026-07-14-semos-main-page-logo-theme-design.md](2026-07-14-semos-main-page-logo-theme-design.md).

Highlight imagery: each of the five highlights has its own photo
(`web/static/images/kb-*.jpg`), matched to its subject and served locally,
referenced from config.

### Workspace Landing Page
- A banner similar to the main page's banner but with different image and 1-2 lines about the workspace
- Announcements
- Recent activities
- Alarms and Errors
- Apps: each app is shown as a large round rectangle
  - Knowledge Base 
  - Chat with Your Knowledge Base
  - Search Your Knowledge Base
  - Document Reviews
  - Workflows
  - Agents and Harness
- The same footer

### Product Overview
- [Placeholder] Summarizes all four capabilities, links out to their feature pages.

### Feature Pages (Knowledge Base, Chat/Agents, Search, App Development)
- [Placeholder] One page per capability — deep-dive content, use cases, screenshots.

### Pricing
- [Placeholder] Self-serve tiers, "Contact Sales" path for enterprise tier.

### Customers / Case Studies
- [Placeholder] Logos, testimonials, 2-3 detailed case studies.

### Security & Trust Center
- [Placeholder] Compliance posture, data handling policy, security architecture summary.

### Docs / Developer Portal
- [Placeholder] API reference, agent/app development guides.

### Blog / Resources
- [Placeholder] Articles, whitepapers.

### About Us
- [Placeholder] Company story, team, mission.

### Contact / Book a Demo
- [Placeholder] Form + scheduling, primary sales-led CTA.

### Changelog / What's New
- [Placeholder] Release notes feed.

### Careers
- [Placeholder] Open roles, culture blurb.

### Legal
- [Placeholder] Terms of Service, Privacy Policy.

### Sign Up
- [Placeholder] Self-serve signup flow.

### Login
- [Placeholder] Standard login, SSO path for enterprise.

### Onboarding
- [Placeholder] First-run guided setup after signup.

### Account & Billing
- [Placeholder] Plan management, invoices, usage.

### 404 / Error Page
- [Placeholder] Standard not-found/error handling.

### User Management
- **Access:** `admin` only; not reachable by `public-user`. `root` was
  considered and dropped — kept simple to two roles.
- **Functionality:** add, edit, delete users; assign/change roles — scoped to
  the acting admin's own tenant. An admin cannot see or manage users in
  other tenants.
- **Tenant creation:** `admin` can also create new tenants from this page.
  **Note:** this is a broader capability than "manage my own tenant's
  users" — any tenant's admin being able to spin up sibling tenants is worth
  a second look once the auth/role follow-up ADR happens, but is accepted
  for this pass. **Fallback:** if this drags in more requirements than
  expected, tenant creation can ship as a direct DB insert instead
  (no UI) for v1, with the User Management feature added later.
- **Default roles:**
  - `public-user` — standard signed-up user, no admin capability
  - `admin` — manages users/roles and site content within their own tenant
- **Auth/role model — deliberately deferred:** the shared auth layer
  currently only has a boolean `admin` flag (Kratos identity
  `MetadataPublic["admin"]`, surfaced as `IsAdmin`/`is_admin` in
  `shared/go/api/auth/kratos.go`), no tenant scoping, no system-wide `role`
  column. Rather than design the real schema now (extend Kratos metadata vs.
  an app-level `role`/`tenant_id` table), **tenants are treated as
  placeholders for this pass** — real RBAC/tenant-schema design is pushed to
  a dedicated future ADR rather than decided implicitly here.
- [Placeholder] Table/list view of users with role column, invite flow,
  role-change confirmation (role changes are sensitive — likely needs
  confirmation + audit logging per the workspace's logging conventions).

### Site Management
- **Access:** `admin` only, scoped to their own tenant.
- **Functionality:** upload/change **this tenant's** logo and images; edit
  the configurable content introduced in Cross-Cutting Requirements
  (marketing copy, feature descriptions, pricing display, etc.) without a
  code deploy. Base SemOS branding (e.g. a "Powered by SemOS" credit) is not
  editable here — defaults on for all tenants (see Audience & Positioning).
- [Placeholder] Likely an editor UI per configurable content type (image
  upload widget for logos/banners, form/rich-text editor for copy blocks) —
  needs its own design pass once the content storage mechanism is settled.

## Open Questions

Tenant resolution is settled: public pages are tenant-independent (one
shared config), and tenant-dependent pages resolve tenant from the session
post-login, then look up that tenant's config filename from the tenant
table (see Content Configurability).

Which Main Page design variant wins is also resolved (see Main Page →
Design variant, and
[2026-07-14-semos-main-page-logo-theme-design.md](2026-07-14-semos-main-page-logo-theme-design.md)).

The technical blocker behind "Nav labels vs. config" is resolved — a
per-locale config mechanism now exists (see below) — but the actual
decision of whether nav labels should move into config remains open, now
unblocked rather than decided.

Open as of 2026/07/14:
- **`[[stats]]` figures.** Currently placeholder em-dashes after an
  implementation pass shipped fabricated numbers. Need real figures, or the
  stats band should be dropped.
- **Per-locale site-config content is designed but not implemented.**
  Renaming `site-default.toml`/`tenant-demo.toml` to per-locale files
  requires real translation of their content (today's file mixes English
  branding/hero with Chinese highlights/features — neither is a complete
  translation of the other), which is out of scope for the design itself.
- **Should nav labels move into config?** Now technically possible (see
  above), but not decided — still requires an explicit call on whether nav
  labels become tenant-configurable or stay in the shared, non-tenant
  message catalog.

**Deliberately deferred to future ADRs** (not open questions for this pass,
but real work not designed here):
- Real auth/role schema for tenant-scoped `public-user`/`admin` (extend
  Kratos metadata vs. app-level `role`/`tenant_id` table) — note the tenant
  table itself needs a minimal `tenant_id` + `config_filename` shape now
  (see Content Configurability); it's the fuller RBAC/role design that's
  deferred, not the table's existence
- Reconciling `[frontend].supported_languages` with `config.local.toml`'s
  separate `[languages]` section, if they turn out to need to be one thing

## References

- [2026-07-14-semos-main-page-logo-theme-design.md](2026-07-14-semos-main-page-logo-theme-design.md) — resolves the Main Page design-variant decision, adds the configurable `logo_image` field, and fixes the light/dark mode consistency bug.
- [2026-07-14-semos-site-config-i18n-design.md](../../../../ChenWeb/docs/superpowers/specs/2026-07-14-semos-site-config-i18n-design.md) — resolves "Nav labels vs. config": per-locale site-config file naming, locale-resolution/fallback algorithm (language-family siblings, default-language fallback, required default file), and the partial-translation content-merge mechanism. Design only, not yet implemented.
