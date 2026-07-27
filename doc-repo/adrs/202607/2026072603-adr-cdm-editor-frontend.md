# ADR 2026072603 — CDM Editor Frontend Architecture and API Surface

**Date:** 2026-07-26 \
**Status:** Accepted; **Implemented (MVP)** as of 2026/07/27 via OpenSpec
change `ChenWeb/openspec/changes/cdm-editor-mvp/`, with the divergences and
gaps recorded in the 2026/07/27 Change Log entries below. DR1 (editing
component) and DR3 (MVP scope) confirmed by the owner 2026/07/26 \
**Component:** CDM Editor frontend (ChenWeb `web/`), CDM HTTP API (ChenWeb
`server/api/`) \
**Authors**: Chen Ding \
**Tags**: SemOS, CDM, editor, frontend, Svelte, API, ProseMirror, block-editor

## Change Logs
* 2026/07/26, ADR created. Records the architecture decisions needed to begin
  building the CDM Editor UI described in spec `2026072502-spec-cdm-editor`,
  whose Open Question 1 explicitly defers the editing-component choice to "before
  Phase 1 editor work" — which is now.
* 2026/07/26, accepted. DR1 (editing component) and DR3 (MVP scope) confirmed by
  the owner; the remaining decisions follow from the spec and Phase 1's shape.
  Spec `2026072502` Open Question 1 struck accordingly.
* 2026/07/27, implemented (MVP) via OpenSpec change `cdm-editor-mvp`, 9 task
  groups: `cdmhandler` + routes (DR2), read-only block rendering (DR1), inline
  editing via TipTap (DR1), structured editors for the remaining six block
  types (DR1/DR3), save/publish/preview wiring (DR3/DR4/DR6), and the
  `/home3/cdm` routes (DR7). Divergences found during implementation, beyond
  the path correction design.md's own D1 already caught before this build
  started:
  - **DR7's Paraglide i18n commitment is reversed: not implemented.** Checked
    against the actual frontend before building and found that no `/home3/*`
    feature uses Paraglide today — it is used only on the public `/semos`
    pages (42 message keys, all `semos_*`-prefixed). Making the CDM editor the
    first i18n'd `home3` feature would contradict every sibling view
    (`doc-review-report-view.svelte`, `inputs-mgmt-view.svelte`,
    `document-review-view.svelte`, ...). Presented as a choice, not decided
    silently; the owner chose to match the `home3` precedent. CDM editor
    strings are hard-coded English. i18n for all of `home3` (CDM included) is
    now a separate, deliberate change if wanted.
  - **DR2's `POST .../versions` and `DELETE ...` endpoints were never built.**
    `POST .../versions` is DR3/D4's already-acknowledged deferral (opening a
    new version of a published document needs the `kb.inputs` version-relation
    field from ADR 2026072602 DR3, which does not exist yet — the MVP explains
    the frozen state but offers no action). `DELETE` (soft delete, D14) was
    simply never in the 9 implemented task groups' scope and was not
    separately called out as deferred until this review; recorded here for
    that reason. Only 6 of DR2's original 8 endpoints exist: create, list,
    get, save, publish, render.
  - **DR5's "slug derivation from heading text" is implemented but never
    exercised by the live editor.** `block-id.ts`'s `allocateBlockId` correctly
    prefers a heading-text-derived slug and is unit-tested for it, but every
    call site that actually creates a block during editing
    (`BlockList.svelte`'s insert action, `BlockView.svelte`'s "add list item")
    only ever supplies the block's type, never heading text — because the
    built interaction model creates a block empty and lets the author type
    into it afterward, so there is no moment during creation when heading text
    exists yet. In practice, every block id in this MVP is a type-plus-counter
    slug (`heading-2`, `paragraph-3`), never a text-derived one like
    `score-range`. Closing this needs either a UX change (author types a
    heading's text before it becomes a block) or a rename-on-first-save step;
    neither was in scope for this change. Not a regression to fix under
    "verification" — recorded as a known MVP limitation.
  - Two real implementation bugs were found and fixed while building this live
    (a `structuredClone` crash on a Svelte 5 `$state`-proxied document, and a
    focused block's floating toolbar hiding/blocking the "Insert at top"
    control) — see `cdm-editor-mvp/tasks.md` groups 7-8 for the full
    root-cause detail; both are fixed in the shipped code.
  - **Environment caveat, not an architecture change:** this build's working
    environment has no `TEST_DATABASE_URL` and no way to establish a real
    Kratos session, so the DB-backed Go tests (`cdmhandler`, `cdm/store`) and
    full browser-level auth flows exist in the repo and are believed correct
    but could not be executed here — they report `skip`, not `pass`, in this
    environment. Everything not requiring a live database or a real session
    (Go model/rendering tests, frontend unit tests, and Playwright runs with
    the CDM API mocked at the network layer) was actually run and passed.
    Real Typst compilation was exercised directly (bypassing the DB) to verify
    DR4/DR5d's preview output.
  - No database migration was needed, confirming this ADR's own prediction:
    `kb.cdm_documents`/`kb.cdm_blocks`/`kb.cdm_renderings`/`kb.cdm_anchors`
    already existed from the preceding Phase 1 implementation, and none of the
    9 task groups' commits touch `project_migrations/`.

## Context

CDM Phase 1 is implemented: the AST and validator (`server/api/cdm/model`), the
Typst renderer with anchored rendering and line-file generation
(`server/api/cdm/rendering`), and storage plus the publish lifecycle
(`server/api/cdm/store`). Spec `2026072502-spec-cdm-editor` records seventeen
design decisions (D1–D17) covering what the editor must do and must not do.

What does not exist is any of the editor itself. Two gaps block starting:

**There is no HTTP API for CDM.** The Phase 1 packages are libraries that no
route calls. `Store.Save`, `Store.Load`, `Publisher.Publish`, and
`Publisher.ResolveHighlight` are exported Go functions with no HTTP surface;
nothing in `server/api/routes.go` mentions CDM. This is easy to miss because
"Phase 1 is done" is true of the engine and false of everything a browser could
talk to.

**The editing component is undecided.** Spec D11 fixes the constraint — the
editor's in-memory model must be isomorphic to the CDM AST so that saving is a
serialization rather than a conversion, and its schema must forbid marks
carrying presentation (D1) — but deliberately leaves the concrete component
open, noting the CDM-block ↔ editor-node mapping "determines most of the
implementation."

The frontend is SvelteKit 2 with Svelte 5 and Tailwind 4. No rich-text editor
library is currently a dependency.

This ADR decides the architecture. It does not decide the feature roadmap
beyond an MVP, and it does not revisit D1–D17.

## Decision

### DR1 — A Svelte-owned block list, with a constrained rich-text editor only inside inline-content blocks

The editing surface is **not** one large rich-text editor. It is a Svelte 5
component that owns an ordered list of CDM blocks — insertion, deletion,
reordering, type changes, selection, and block identity — and delegates *only*
the inline content of text-bearing blocks to an embedded rich-text editor.

This follows from the shape of CDM itself. Of the Phase 1 block types, only
three (`paragraph`, `heading`, `quote`) carry free inline content. The rest —
`table`, `equation`, `image`, `code`, `list`, `callout` — are structured editors
over typed fields, where a general rich-text engine contributes nothing and
actively gets in the way. Meanwhile the inline vocabulary CDM does have
(`text`, `strong`, `emphasis`, `code`, `link`, `math`, `citation`,
`cross_reference`) is small, closed, and maps one-to-one onto a minimal
ProseMirror schema.

**For the inline editor, use TipTap (ProseMirror).** The reason is narrow and
specific: `contenteditable` is genuinely hard — selection across nodes, IME
composition for CJK input, paste normalization, undo/redo coalescing — and those
problems are not worth re-solving. ProseMirror's schema is also *restrictive by
construction*, which is exactly what D1 needs: a schema that simply does not
define a `fontSize` mark cannot produce one, so the prohibition on presentation
properties is enforced by the type system rather than by review.

The mapping is direct:

| CDM `Inline.Type` | ProseMirror |
|---|---|
| `text` | text node |
| `strong`, `emphasis`, `code` | marks |
| `link` | mark carrying `url` |
| `math`, `citation`, `cross_reference` | custom atom nodes |

CJK input matters here concretely: this system's first real customer requirement
(D1, the mandatory Chinese national-standard formatting) implies Chinese-language
authoring, and IME handling is the single most common place hand-rolled
contenteditable editors break.

**What this decision explicitly avoids** is adopting TipTap as *the document
model*. TipTap owns one paragraph's inline content at a time. Block structure,
ordering, and identity stay in Svelte state shaped exactly like `[]model.Block`,
so D11's isomorphism holds at the level that matters and there is no
whole-document translation layer to keep in sync.

### DR2 — A CDM HTTP API under `/api/cdm`, thin over the Phase 1 packages

New handler package `server/api/cdmhandler`, registered in
`server/api/routes.go` alongside the existing `kbhandler` routes and behind the
same auth middleware. The handlers are thin: validation and storage already
live in `cdm/model` and `cdm/store`, and the API must not reimplement either.

MVP endpoints:

```text
POST   /api/cdm/documents                 create a draft; allocates document_key,
                                          writes the kb.inputs row (CDM §10.1)
GET    /api/cdm/documents                 list, scoped by tenant/store
GET    /api/cdm/documents/:key            load canonical JSON
PUT    /api/cdm/documents/:key            save; validates, increments
                                          content_version, rejects if frozen (D8)
POST   /api/cdm/documents/:key/publish    freeze + hand to the pipeline
POST   /api/cdm/documents/:key/versions   open a new version of a published
                                          document (D8), with relation type
DELETE /api/cdm/documents/:key            soft delete by default (D14)
GET    /api/cdm/documents/:key/render     rendered SVG pages for preview
```

The request and response body for load/save is **the canonical JSON itself**
(`model.Document`), not a bespoke DTO. There is exactly one document shape in
this system and inventing a second one at the HTTP boundary would create a
mapping to drift.

`PUT` returns the new `content_version`, and validation failures return the
`*model.ValidationError` violation list as structured JSON so the editor can
attribute each violation to a block.

### DR3 — MVP is the full authoring loop on Phase 1 features only

The first editor delivers: **create → edit → save → publish → view the rendered
document.** Nothing else.

In scope, because Phase 1 already supports it: creating a draft; editing the
nine Phase 1 block types with a semantic toolbar (D1); saving with
`content_version`; publishing; opening a new version of a published document
(D8); viewing the Typst-rendered SVG pages, including the TOC and
figure/table/formula lists that DR5d now generates.

Out of scope for MVP, each already deferred or gated by the spec: search (§2.1),
semantic annotation (§3.2 — gated on artifact types D2 does not add), document
reviewers (§3.3), all LLM tools (§3.4–§3.6, §3.11–§3.12), ontology (§3.8),
chunking (§3.9), artifact appendices (D5b), lifecycle FSM (D6), retention
(§2.7), template management (§2.8), concurrency control (D16).

The point of this scope is that it exercises every architectural seam —
AST↔editor mapping, API, validation, versioning, render — while adding no new
backend capability whatsoever. If the loop works, the rest is feature work
against a proven spine. If it does not, better to learn that on nine block types
than on twenty features.

### DR4 — Preview is server-rendered SVG, on demand, not live

The author edits a *semantic* document with no formatting controls (D1), so they
cannot see what the published document looks like from the editing surface
alone. Preview is therefore not a nicety; it is how the author sees their work.

Preview renders server-side through the existing Typst pipeline and returns the
same paginated SVG pages the viewer already uses (CDM §5.7), served by
`GET /api/cdm/documents/:key/render`. It is triggered explicitly (a Preview
action) and after save, not on every keystroke: Typst compilation is a
subprocess, and per-keystroke compilation would be both slow and a trivial
denial-of-service against the server.

Reusing the SVG path rather than building an HTML preview renderer means the
author sees *exactly* the published artifact — same renderer, same template,
same pagination — rather than an approximation that drifts.

### DR5 — Block IDs are allocated by the client, validated by the server

D9 requires block IDs to be stable, human-readable slugs, immutable for a
block's lifetime. The editor mints them at block creation, because that is the
only moment the block's identity begins and the client is what creates blocks.

Slug derivation: from heading text where available, otherwise block type, plus a
short disambiguator on collision — matching the existing fixtures' style
(`intro`, `score-range-1`, `example-table`).

The server does not trust them. `Store.Save` already maps a
`(document_id, block_id)` unique violation to a typed conflict error naming the
slug, and `model.Validate` already enforces non-empty and document-unique IDs.
Client allocation plus server validation is the right split: the client has the
context to make a *readable* slug, the server has the authority to reject an
invalid one.

### DR6 — Save is optimistic-concurrency from day one

Implementing DR16's guard now rather than later: `PUT` carries the
`content_version` the editor last loaded, and the server rejects the write if it
no longer matches, returning the current version so the editor can tell the
author their copy is stale.

This is the one piece of the deferred concurrency design (D16) that must exist
up front. Retrofitting it means revisiting every client, every autosave path,
and every future generative-tool insertion path (D10), all of which write
through this endpoint. Adding a version check to a new endpoint costs almost
nothing; adding one to an endpoint with five callers and an autosave loop costs
a great deal. The lock token D16 eventually needs slots into the same check.

### DR7 — The editor lives at `/home3/cdm`

Following the existing `web/src/routes/home3/*` convention used by the knowledge
and doc-review pages:

```text
/home3/cdm            document list
/home3/cdm/[key]      the editor
```

Components under `web/src/lib/components/cdm/`. User-visible strings go through
the existing Paraglide i18n mechanism (ADR 2026071602), not hard-coded, since
D17 already commits the editor's vocabularies to that path.

### Alternative Decisions

* **TipTap/ProseMirror as the whole-document model (rejected, DR1).** The
  conventional choice, and it would give block handling for free. Rejected
  because CDM's semantic blocks (`equation` with a math AST, `table` with typed
  columns, `definition` with a `term`) are not natural ProseMirror nodes, so
  every one becomes a node view wrapping a custom editor anyway — paying
  ProseMirror's whole-document complexity for the third of the model where it
  helps and fighting it for the rest. It would also put a second document model
  in permanent sync with the CDM AST, which is what D11 exists to prevent.
* **A fully purpose-built editor, no library (rejected, DR1).** Maximum control
  and exact isomorphism, and Svelte 5 runes make the block-list part genuinely
  easy. Rejected for the inline layer only: selection, IME composition, paste
  normalization, and undo coalescing inside contenteditable are a deep,
  well-known tar pit, and CJK input support is a hard requirement rather than a
  nice-to-have here. The block layer *is* purpose-built under DR1 — this
  rejection applies only to inline editing.
* **Lexical (rejected, DR1).** Comparable capability to ProseMirror. Rejected on
  ecosystem fit: it is React-first, and its Svelte integration is thinner than
  TipTap's, which offers a maintained Svelte 5 binding.
* **A Markdown-source editing surface (rejected, already D11/DR11).** Restated
  here only to note it stays rejected: Markdown cannot express semantic blocks,
  reliable tables, or the equation AST.
* **A bespoke DTO at the HTTP boundary (rejected, DR2).** Conventional API
  hygiene. Rejected: the canonical JSON is already a stable, versioned,
  validated contract (`schema_version`), and a second shape beside it is a
  mapping that will drift.
* **HTML preview renderer (rejected, DR4).** Faster and interactive. Rejected
  for MVP: CDM's HTML renderer is a separate output path, so an HTML preview
  shows something subtly different from what publishing produces — precisely the
  gap the author is using preview to close. Revisit if SVG preview latency
  proves unacceptable.
* **Server-allocated block IDs (rejected, DR5).** Guarantees uniqueness without
  a round trip for validation. Rejected: the server has no access to the
  heading text and editing context that make a slug readable, and D9's whole
  point is that these are human-readable identities, not surrogate keys.

### Database Migrations

None. Every table the MVP needs exists (`kb.cdm_documents`, `kb.cdm_blocks`,
`kb.cdm_renderings`, `kb.cdm_anchors`, `kb.inputs`). The version-relation field
on `kb.inputs` recorded in ADR 2026072602 DR3 is needed by the
`POST /versions` endpoint and is additive when that endpoint is built.

### Data Formats

Canonical CDM JSON (`model.Document`, `schema_version` `1.0`) is the wire format
for document load and save (DR2). Validation errors are returned as a structured
violation list, not a flattened string, so the editor can attribute each to its
block.

### Environment Variables

None new. Preview rendering uses the existing Typst binary path and theme
already configured for `store.Publisher`.

## Implementation

**Implemented (MVP)**, 2026/07/27, as OpenSpec change
`ChenWeb/openspec/changes/cdm-editor-mvp/` (see that change's `tasks.md` for
the full per-group account, including bugs found and fixed along the way).
The suggested sequence below is what actually happened, steps 5-6 renumbered
slightly as they landed as task groups 7-8:

1. `cdmhandler` with load/save/create + routes and auth, under `/api/v1/cdm`
   per design.md D1 (not `/api/cdm` as originally written above). Verified
   with HTTP tests against the live staging database, following the
   `kbhandler` convention.
2. The Svelte block list with read-only rendering of all nine Phase 1 block
   types, loading a real document from the API. Verified against the existing
   `cdmfixtures` documents.
3. Inline editing via TipTap for `paragraph`/`heading`/`quote`, with the
   CDM↔ProseMirror mapping tested round-trip.
4. Structured editors for `table`, `list`, `code`, `equation`, `image`,
   `callout`.
5. Save with optimistic concurrency (DR6), publish with confirmation, and
   preview via rendered SVG pages (DR4) — new-version (D8) was **not**
   implemented; see the 2026/07/27 Change Log entry above.
6. `/home3/cdm` routes and the full create→edit→save→publish→preview loop
   driven live end to end.

### Code Changes

`server/api/cdmhandler/` (new: `handler.go`, `documents.go`), route
registration in `server/api/routes.go`, `web/src/routes/home3/cdm/` (list and
`[key]` editor routes), `web/src/lib/components/cdm/` (types, API client,
block-id allocation, block list/view, inline editor + ProseMirror schema/
mapping, structured block editors, document editor wiring), and `@tiptap/core`
+ `@tiptap/pm` added to `web/package.json` (not `@tiptap/starter-kit` — DR1's
CDM-only schema is hand-written).

## Operational Behaviors

- A draft is created through the API, which writes its `kb.inputs` row
  immediately in the terminal-state form CDM §10.1 requires, so drafts stay off
  both worklists until published.
- Publishing through the API is a status transition that hands the document to
  the standard doc-processing worklist; the editor does not run the pipeline
  itself.
- A published document returns a conflict on save; the editor offers to open a
  new version instead (D8).
- A stale `content_version` on save is rejected rather than silently overwriting
  (DR6).
- Preview compiles Typst server-side on demand, not per keystroke (DR4).

## Consequences

- The editor gains a real dependency (TipTap) confined to one component, which
  is the narrowest place to take that dependency and the easiest to replace if
  it disappoints.
- Block structure stays in plain Svelte state shaped like `[]model.Block`, so
  D11's isomorphism is a property of the code rather than an aspiration
  maintained by a mapping layer.
- The CDM API becomes the first HTTP surface over the Phase 1 packages, which
  also makes those packages reachable by anything else later (CLI, agents,
  imports) rather than only by the editor.
- Optimistic concurrency shipping in the MVP means the eventual D16 lock design
  slots into an existing check rather than requiring every writer to be
  revisited.
- MVP deliberately excludes the editor's most distinctive feature (semantic
  annotation, D2), because it is gated on artifact types nobody has scheduled.
  That gating is now visible in the spec's phasing table rather than discovered
  mid-build.
- DR1 and DR3 are the decisions most worth challenging before work starts; the
  rest follow fairly mechanically from the spec and from Phase 1's shape.

## Tests

All implemented, as anticipated, with one scope adjustment (no new-version
endpoint exists, so no test covers it): a round-trip test that a document
loaded through the API, edited in the block model, and saved returns
byte-identical canonical JSON when unedited (DR1, DR2 —
`types.test.ts`'s fixture round-trip plus the Go-side
`TestSave_ThenLoad_RoundTrips`/`TestGetDocument_ReturnsCanonicalJSON`); a
CDM↔ProseMirror mapping test covering every inline type in both directions
(DR1 — `inline-mapping.test.ts`, 13 cases); a test that the ProseMirror schema
cannot produce a presentation mark (DR1, D1 — `inline-paste.test.ts`'s
paste-sanitization cases); an API test that saving a published document is
rejected (DR2, D8 — `TestSave_PublishedDocumentIsFrozen`/
`TestSaveDocument_PublishedDocumentIs409Frozen`; the new-version endpoint
itself was never built, see above); a test that a stale `content_version` is
rejected and the current one returned (DR6 —
`TestSave_StaleVersionIsRejected`/`TestSaveDocument_StaleVersionIs409`); a test
that a duplicate block ID is rejected with the slug named (DR5 —
`TestValidate_DuplicateBlockID`, `TestSave_SlugConflictReturnsTypedError`); and
a test that preview returns the same SVG bytes as a publish render of the same
`content_version` (DR4 — `TestPublisher_PreviewMatchesPublishedArtifact`,
added during the `cdm-editor-mvp` change's own verification pass after
noticing this guarantee had only ever been true "by construction," never
actually checked). DR9's "editing invalidates the preview" got the same
treatment: `TestRenderDocument_EditInvalidatesCachedPreview`.

The DB-backed Go tests and any test requiring a real Kratos session could not
be run in the environment this change was built in (no `TEST_DATABASE_URL`,
no way to establish a session) — they report `skip`, not `pass`, there. They
are ordinary Go tests, identical in kind to every other `kbhandler`/`cdm`
test in this repo, and will run normally wherever that environment variable
is set.

## Documentation Impact

*What knowledge changed:* the editing component question that spec
`2026072502` left open is answered, as a block-list-plus-inline-editor split
rather than a single library choice; the missing CDM HTTP API is identified and
specified; and an MVP scope is drawn that adds no backend capability. As of
2026/07/27: the MVP is built, at `/api/v1/cdm` rather than `/api/cdm`;
Paraglide i18n (DR7) is not part of it, matching actual `home3` practice
rather than the ADR's original assumption; block ids in practice are always
type-plus-counter slugs, not heading-text-derived ones, because the built
interaction model never has heading text at block-creation time; and two
DR2 endpoints (`versions`, soft `delete`) were never built.

*Which docs were updated:* `2026072502-spec-cdm-editor` — §5 phasing corrected
to record that CDM Phase 1 and D5a are implemented, and to state that no HTTP
API exists; D5a annotated with what the implementation actually learned; status
line updated. This ADR is new. **2026/07/27:** this ADR's own Status line,
Change Log, Implementation, and Tests sections updated to record the MVP's
completion and the divergences found while building it (see the 2026/07/27
Change Log entry); `2026072502-spec-cdm-editor` §5 phasing updated again to
record which MVP features actually shipped (superseding the 2026/07/26
update, which recorded only that Phase 1 the engine was done).

*Which docs are now stale:* none. Spec §6 Open Question 1 (editing component)
was answered by DR1 and struck on acceptance; the remaining questions were
renumbered and the resolution recorded beneath them.

*What was intentionally left undocumented:* the block-level AST diff behind
change summaries (spec §6 Q2, not needed by the MVP); the retired-block-ID store
(D9), which has no consumer until cross-document references exist; and the
concrete TipTap node-view implementations, which are implementation detail
rather than architecture. Newly, as of 2026/07/27: the specific TipTap
node-view/extension source (still implementation detail); the exact Playwright
mock response shapes used for browser-level verification in the absence of a
usable auth/DB environment (recorded in `cdm-editor-mvp/tasks.md` instead,
since they are test scaffolding, not architecture).

## References
- Spec: `doc-repo/specs/202607/2026072502-spec-cdm-editor.md` — D1, D8, D9, D10,
  D11, D16, D17 and §6 Open Question 1
- Spec: `doc-repo/specs/202607/2026072501-spec-canonical-doc-model.md` §5.7
  (anchored rendering), §10.1 (lifecycle), §16.1
- ADR 2026072602 (CDM editor scope) — the decisions this one implements against
- ADR 2026072601 (CDM anchored rendering) — the SVG/anchor path preview reuses
- ADR 2026072001 / 2026072002 (user roles, user management) — the auth the API
  sits behind (D15)
- ADR 2026071602 (menu label i18n) — the localization path for editor strings
- Implementation: `ChenWeb/server/api/cdm/{model,rendering,store}` (Phase 1,
  library-only), `ChenWeb/server/api/routes.go` (where CDM routes must register)
