# CDM Editor MVP Implementation

**Date:** 2026-07-27 \
**Status:** Implemented (MVP) \
**Component:** CDM HTTP API (ChenWeb `server/api/cdmhandler`, `server/api/cdm/store`), CDM Editor UI (ChenWeb `web/src/routes/home3/cdm`, `web/src/lib/components/cdm`) \
**Authors**: Claude \
**Tags**: SemOS, CDM, editor, frontend, Svelte, TipTap, ProseMirror, API, Typst

## Change Logs
* 2026/07/27, document created, recording the 9-task-group implementation of
  OpenSpec change `cdm-editor-mvp` completed 2026/07/26–27.

## Purpose

This document records what was actually built for the CDM Editor MVP, closing
the loop OpenSpec change `ChenWeb/openspec/changes/cdm-editor-mvp/` set out to
close: CDM Phase 1 (`cdm/model`, `cdm/rendering`, `cdm/store`) was a set of Go
libraries nothing called — no HTTP route, no editor UI. This change adds both.

It is written against, and refers back to, the three documents OpenSpec
produced for this change, which remain the authoritative record of *why* each
decision was made:

- **`proposal.md`** — the "why" and "what changes": closing the authoring loop
  end to end (create → edit → save → publish → preview) without adding new
  backend capability, so the loop's own correctness is what gets proven.
- **`design.md`** — nine numbered decisions (D1–D9) resolving three problems
  the ADR had assumed were settled and were not: `kb.cdm_documents
  .input_record_id` was a dead column nothing populated; `Store.Save` had no
  way to express optimistic concurrency; and nothing in `cdm/store` knew what
  "published" meant. D1–D9 are referenced by number throughout this document
  exactly as design.md defines them.
- **`tasks.md`** — the 9-task-group execution log this implementation
  followed group by group, including every deviation from plan and every bug
  found while building. This document is a synthesis of it, not a
  replacement; `tasks.md` has the full narrative detail for anything
  summarized here.

It also updates, and should be read alongside:

- **ADR `2026072603-adr-cdm-editor-frontend`** — DR1–DR7, the architecture
  this change implements (Svelte-owned block list, TipTap confined to inline
  content, a thin HTTP API, MVP scope, on-demand SVG preview, client-side
  block-id allocation, optimistic concurrency, `/home3/cdm` routes). Updated
  2026/07/27 with a Change Log entry recording this implementation and its
  divergences from what the ADR originally described.
- **Spec `2026072502-spec-cdm-editor`** — §5 phasing, updated 2026/07/27 to
  record exactly which MVP features shipped and which remain unblocked but
  unbuilt.

## Summary

The MVP is implemented and works end to end: an author can create a CDM
document, edit all nine Phase 1 block types, save with optimistic
concurrency, publish (freezing the document), and preview the Typst-rendered
SVG pages — including the table of contents and figure/table/formula lists
ADR `2026072602`'s DR5d generates.

Key outcomes:

- `server/api/cdmhandler` exposes six endpoints under `/api/v1/cdm/*`
  (create, list, get, save, publish, render), thin over `cdm/model` and
  `cdm/store` — no validation or persistence logic is duplicated in the
  handler layer (design.md, proposal.md).
- Three real defects in `cdm/store` that predated this change were fixed as
  prerequisites (design D2–D4): the dead `input_record_id` column now gets
  populated atomically at creation; `Store.Save` now takes an expected
  `content_version` and enforces it inside the same transaction as the
  increment; and a published document is now provably read-only, enforced in
  the store so every future writer inherits the rule.
- The editor at `/home3/cdm` is a Svelte-5-owned block list (`BlockList.svelte`
  / `BlockView.svelte`) holding `[]model.Block`-shaped state directly, with a
  hand-written, CDM-only ProseMirror schema (`inline-schema.ts`) mounted via
  TipTap (`InlineEditor.svelte`) for exactly the three block types that carry
  free-form inline content (`paragraph`, `heading`, `quote`). The other six
  Phase 1 types get purpose-built structured editors.
- Save, publish, and preview are wired to the real error taxonomy the API
  returns (`CdmStaleVersionError`, `CdmFrozenError`, `CdmValidationError`,
  `CdmBlockConflictError`), each surfaced to the author rather than failing
  silently, per proposal.md and design.md's goals.
- Three real, user-facing bugs were found and fixed while building this live
  (not in code review): an inline-editor toolbar layout shift that could
  silently eat the first click below it; a Svelte 5 `structuredClone` crash
  on a value that had passed through `$state`; and a floating toolbar that
  could visually hide and block clicks on the "Insert at top" control. All
  three are detailed below and in `tasks.md`.
- Two things this MVP does **not** do, both deliberately and both recorded
  back in the ADR and spec rather than left implicit: it does not localize
  editor strings through Paraglide (no other `home3` feature does either),
  and it does not offer a way to open a new version of a published document
  (design D4 — the `kb.inputs` version-relation field that action needs does
  not exist yet).

## Implementation Scope

Implemented on ChenWeb's default branch as 9 sequential commits (`jj`), one
per task group, each independently buildable and tested:

| Commit | Task group |
|---|---|
| `8c5d3adff2ef` | 1 — `cdm/store`: `Create`, optimistic concurrency, frozen-document rule |
| `91ec4f588d04` | 2 — CDM HTTP API: documents reachable over `/api/v1/cdm` |
| `cf47d9e5b007` | 3 — Frontend foundation: types, API client, block-id allocation |
| `94a2f01363b9` | 4 — Block list: read-only rendering plus insert/delete/reorder/type-change |
| `324d336dbf40` | 5 — Inline editor: schema, CDM↔ProseMirror mapping, mounting, toolbar |
| `cde99e7827f2` | 6 — Structured block editors: table, list, code, equation, image, callout |
| `a0373125dc10` | 7 — Wire save, publish, and preview to the HTTP API |
| `188360b108dd` | 8 — Routes and integration (`/home3/cdm`) |
| `159dc9931b58` | 9 — Verification |

## Main Code Changes

### 1. `cdm/store` prerequisites (design D2, D3, D4 — task group 1)

Files: `server/api/cdm/store/store.go`, `inputs.go`, `publish.go`.

- `Store.Create(ctx, doc, DraftInput) (*CreateResult, error)` writes the
  `kb.inputs` row and the `kb.cdm_documents` row in one transaction and
  populates `input_record_id` — fixing the dead column design.md's Context
  section identified.
- `Store.Save`'s signature changed to
  `Save(ctx, doc, expectedVersion int64) (*SaveResult, error)` (design D3, a
  breaking change to a Phase 1 exported function, contained to its own
  in-repo test callers). The version check runs inside the same
  `SELECT ... FOR UPDATE OF d` transaction as the write, via a new
  `lockDocStateTx` — not the originally planned `ON CONFLICT ... WHERE`
  clause, which was found to silently *create* a document when the caller
  expected a version and none existed (`tasks.md` 1.5).
- Frozen-document enforcement (design D4) lives in `Store.Save` itself,
  deriving publication state from `kb.inputs`' `doc_processing` status entry
  rather than a second source of truth, so every future writer inherits the
  rule.
- New typed errors: `StaleVersionError{Expected, Actual}`, `FrozenError`,
  `ConflictError` (block-slug), `NotFoundError`.

### 2. `server/api/cdmhandler` (design D1, D5 — task group 2)

Files: `server/api/cdmhandler/handler.go`, `documents.go`;
`server/api/routes.go`.

Six endpoints, registered on the existing `/api/v1` group behind
`authmiddleware.AuthMiddleware` — **`/api/v1/cdm/*`, not `/api/cdm/*`** as ADR
2026072603's DR2 originally wrote (design D1 corrects this; folded back into
the ADR itself in this implementation's own documentation pass, task 9.5):

```text
POST   /api/v1/cdm/documents
GET    /api/v1/cdm/documents
GET    /api/v1/cdm/documents/:key
PUT    /api/v1/cdm/documents/:key
POST   /api/v1/cdm/documents/:key/publish
GET    /api/v1/cdm/documents/:key/render
```

`document_key` is server-allocated (design D5): `doc:<slugified-title>`, a
numeric suffix appended only on collision. `writeStoreError` maps every typed
store error onto HTTP with a `conflict` discriminator
(`stale_version`/`frozen`/`block_slug`) so the client can tell the three 409
cases apart. `RenderDocument` calls `Publisher.Render`, not `Publisher.Publish`
— that split (a new method extracted from `Publish`) is what makes previewing
a draft not freeze it (design D9, D8).

**Not built**, both recorded rather than silently dropped: `DELETE
/documents/:key` (needs a soft-delete column that does not exist) and `POST
/documents/:key/versions` (needs the `kb.inputs` version-relation field from
ADR 2026072602 DR3, deferred by design D4).

### 3. Frontend foundation (design D8 — task group 3)

Files: `web/src/lib/components/cdm/types.ts`, `cdm-client.ts`, `block-id.ts`.

Hand-written TypeScript types mirror `model.Document`'s JSON encoding
field-for-field (snake_case, no camelCase translation layer), with a
round-trip test against the same Go fixtures (`cdmfixtures.JaroWinkler()`,
`cdmfixtures.AllBlockTypes()`) the Go tests use, so drift between the two
type definitions is caught rather than assumed absent (design D8's
isomorphism requirement). `cdm-client.ts` wraps the six endpoints with typed
errors (`CdmStaleVersionError`, `CdmFrozenError`, `CdmValidationError`,
`CdmBlockConflictError`) discriminated from the handler's `conflict` field.

### 4. Block list (design D8 — task group 4)

Files: `web/src/lib/components/cdm/BlockList.svelte`, `BlockView.svelte`,
`InlineView.svelte`, `block-ops.ts`, `block-defaults.ts`.

`BlockList.svelte` holds `blocks` as a `$bindable` prop — the caller owns the
one canonical copy, no view model. Insertion, deletion, up/down reordering,
and type-change (scoped to `paragraph`/`heading`/`quote`, the only types that
share a content-preserving shape) all operate directly on the block array.
Structural mutation logic lives in plain, unit-tested `.ts` modules
(`block-ops.ts`, `block-defaults.ts`) rather than inline in the `.svelte`
files, since this codebase has no component-testing infrastructure.

### 5. Inline editor (design D1/D7 via ADR DR1 — task group 5)

Files: `web/src/lib/components/cdm/inline-schema.ts`, `inline-mapping.ts`,
`InlineEditor.svelte`.

A hand-written ProseMirror schema (`@tiptap/core` + `@tiptap/pm` only, not
`@tiptap/starter-kit`) contains exactly CDM's eight inline types and no
presentation mark — making "no font/size/colour/alignment" structurally true
rather than merely policed by review. `inline-mapping.ts`'s
`groupByMarks` algorithm handles the CDM↔ProseMirror direction that is not a
simple per-leaf loop: CDM's inline wrappers are an ordered, nested tree,
while ProseMirror marks are an unordered per-leaf set. One `InlineEditor`
instance edits exactly one block's `[]Inline`, never a block sequence.

### 6. Structured block editors (task group 6)

Files: `web/src/lib/components/cdm/table-ops.ts`, `list-ops.ts`,
`TableEditor.svelte`, plus direct field bindings for `code`/`equation`/
`image`/`callout` in `BlockView.svelte`.

Each of the remaining six Phase 1 block types gets fields corresponding to
its typed CDM properties (column/row editing for `table`, ordered-list toggle
and item add/remove for `list`, a language input plus verbatim textarea for
`code`, and so on) — never free rich-text input, per proposal.md's
"Structured blocks use purpose-built editors" requirement.

### 7. Save, publish, preview (design D3/D4/D9 — task group 7)

Files: `web/src/lib/components/cdm/DocumentEditor.svelte`,
`document-editor-ops.ts`.

`DocumentEditor.svelte` owns a `Document` end to end and wires
`saveDocument`/`publishDocument`/`renderDocument`/`getDocument`. A stale save
leaves the author's local content untouched (only an explicit "reload"
action discards it); a frozen document shows a persistent explanation and
disables every mutating control, with no dead end but also, correctly, no
offered action (design D4's explicit scope cut); validation violations and
block-slug conflicts are attributed to the specific offending block via a new
pure module, `document-editor-ops.ts`'s `extractBlockId`/`attributeToBlocks`;
publish requires confirmation and is blocked while the document has unsaved
local changes (a correctness fix found while designing this task, not
mandated by the task wording — `PublishDocument` has no version check of its
own server-side, so publishing while dirty would silently publish stale
content); preview is wired to an explicit action only, never per-keystroke.

### 8. Routes and integration (ADR DR7 — task group 8)

Files: `web/src/routes/home3/cdm/+page.svelte`,
`web/src/routes/home3/cdm/[key]/+page.svelte`,
`web/src/lib/components/cdm/DocumentListView.svelte`,
`DocumentEditorPage.svelte`.

`/home3/cdm` (list) and `/home3/cdm/[key]` (editor), following the existing
`home3` thin-route-delegating-to-a-view-component convention. Tenant/store
scoping is sourced from `knowledgeStoreState`, the existing active-knowledge-
store singleton already used by `kb-import-view.svelte` and
`document-review-view.svelte` — not a new selection mechanism.

## Design Decisions: As Implemented

design.md's nine decisions, cross-checked against what actually shipped:

| # | Decision | Implemented as designed? |
|---|---|---|
| D1 | Routes under `/api/v1/cdm/...` | Yes |
| D2 | `Store.Create` writes both rows atomically | Yes |
| D3 | `Store.Save` takes `expectedVersion`, checked in-transaction | Yes, via `lockDocStateTx` rather than the originally sketched `ON CONFLICT` clause (found to be wrong during task 1.5 — see `tasks.md`) |
| D4 | Frozen state derived from `kb.inputs`, enforced in `Store.Save` | Yes. The "open a new version" action this enables the editor to *explain* was, per D4's own explicit note, never built |
| D5 | `document_key` server-allocated, slug from title | Yes |
| D6 | Block IDs client-minted, server-validated | Partially — the allocator (`block-id.ts`) correctly supports deriving a slug from heading text and is unit-tested for it, but the shipped editor's insert-then-type interaction never has heading text at the moment a block is created, so every id actually produced today is type-plus-counter (`heading-2`), never text-derived (`score-range`). See "What Was Not Changed" below |
| D7 | TipTap via `@tiptap/core` only, CDM-only schema | Yes |
| D8 | Block list is a Svelte 5 `$state` array of `model.Block` | Yes |
| D9 | Preview on demand, cached by `content_version` | Yes, and empirically re-verified during task 9.3's spec audit (see Tests Added) rather than left as "true by construction" |

## Tests Added

Following the project's established convention for this codebase: Go tests
run against a live database (no mocks, since the invariants that matter —
row locks, version guards, the frozen rule — live in the database itself,
same reasoning `kbhandler`'s own tests use); frontend logic that can be
extracted into plain `.ts` modules gets `bun test` coverage; anything
DOM/Svelte-specific gets driven live in a real headless browser via
Playwright, since this codebase has no component-testing infrastructure.

- **Go**: `server/api/cdm/store/{create,concurrency,store,publish,lock_internal}_test.go`,
  `server/api/cdmhandler/handler_test.go`, plus pre-existing `cdm/model` and
  `cdm/rendering` tests. Notably added during task 9.3's audit of both
  capability specs against the actual test suite — two requirements
  (`cdm-http-api`'s "Preview matches what publishing produces" and "Editing
  invalidates the preview") were true only "by construction" (same code
  path, cache keyed by `content_version`) with no test actually exercising
  either path:
  - `TestPublisher_PreviewMatchesPublishedArtifact`
    (`cdm/store/publish_test.go`)
  - `TestRenderDocument_EditInvalidatesCachedPreview`
    (`cdmhandler/handler_test.go`)
- **Frontend (`bun test`)**: 83 tests across 10 files in
  `web/src/lib/components/cdm/` — `types.test.ts` (fixture round-trip),
  `inline-mapping.test.ts` (13 cases, every inline type both directions),
  `inline-paste.test.ts` (8 cases, presentation styling dropped on paste),
  `block-id.test.ts`, `block-ops.test.ts`, `block-defaults.test.ts`,
  `table-ops.test.ts`, `list-ops.test.ts`, `document-editor-ops.test.ts`,
  `cdm-client.test.ts`.
- **Live browser (Playwright, `webapp-testing` skill)**: every task group's
  interactive behavior was driven in a real headless Chromium against a
  disposable scratch route, created and deleted per group, never left in the
  shipped route tree. Task group 8's full-loop check drove the actual
  `/home3/cdm` routes: pick a store → create → land on the editor → insert
  and edit all 9 Phase 1 block types → save → publish (confirm) → preview.
  Task 8.4 additionally ran the real `rendering.TypstRenderer`/
  `RenderSVGPages` pipeline directly against `cdmfixtures.AllBlockTypes()`
  (bypassing `cdm/store`/`cdmhandler`, which need a database) and visually
  confirmed the Contents/List of Figures/Tables/Formulas outlines render
  correctly in the compiled SVG — necessary because Typst's SVG export
  encodes text as vector glyph symbols, not literal text nodes, so a
  text-content assertion could not have caught a regression here.

**Environment constraint, not a test-quality gap:** this implementation's
working environment has no `TEST_DATABASE_URL` and no way to establish a real
Kratos session. Every DB-backed Go test above reports `skip`, not `pass`,
here, and every Playwright run mocks the CDM HTTP API (and, for task group 8,
the `kb.stores`/`site-config` endpoints) at the network layer rather than
hitting the real backend. These are ordinary tests, identical in kind to
every other `kbhandler`/`cdm` test in this repo, and will run normally
wherever that environment variable is set and a real session is available.

## What Was Not Changed

The following were intentionally not built in this implementation, each
recorded here and in ADR 2026072603 / spec `2026072502-spec-cdm-editor`
rather than left implicit:

1. **Opening a new version of a published document** (D8's "first edit after
   publish"). Deferred by design D4: the `kb.inputs` version-relation field
   ADR 2026072602 DR3 describes does not exist yet. The editor explains that
   a published document is read-only but offers no way forward — a known,
   accepted gap, not a dead end hidden from the author.
2. **`DELETE /documents/:key`**. No soft-delete column exists on `kb.inputs`
   or `kb.cdm_documents`; building this needs either a migration or shipping
   hard delete mislabelled as soft, neither of which this change's own
   "no migration" scope allowed.
3. **Version history / lineage browsing** (spec §2.5) and **template
   management** (spec §2.8). Both depend on capabilities (the version
   lineage; a template CRUD surface) this change did not build. The MVP
   always renders with `rendering.DefaultTheme`.
4. **Paraglide i18n for editor strings.** ADR 2026072603's DR7 originally
   assumed this; checked against actual `home3` practice before building and
   found that no `home3` feature uses Paraglide today (it is `/semos`-only,
   42 keys, all `semos_*`-prefixed). Presented to the project owner as an
   explicit choice rather than decided silently; the owner chose to match
   `home3` precedent. Editor strings are hard-coded English, same as every
   sibling `home3` feature.
5. **Heading-text-derived block-id slugs, in practice.** The allocator
   supports this and is unit-tested for it, but the shipped insert-then-type
   interaction (a block is created empty; the author types into it
   afterward) never has heading text available at the moment a block is
   actually created. Every id produced by the live editor today is
   type-plus-counter (`heading-2`), never text-derived (`score-range`).
   Closing this needs either a different interaction or a rename-after-save
   step; out of scope here.
6. **Multi-tenant isolation.** `tenant_id` remains a client-supplied filter,
   not a server-enforced boundary — `ApiTypes.UserInfo` carries no tenant
   identity, matching how the rest of this API already works
   (`upload_handler.go`). A real boundary needs a multi-tenancy product
   decision outside this change's scope.

## Operational Behavior After This Change

- Creating a document through the API writes its `kb.inputs` row immediately
  in the draft form CDM §10.1 requires, so it sits off both the parse and
  doc-processing worklists until published.
- A draft can be saved repeatedly; each save increments `content_version` in
  place. A stale save (the caller's expected version no longer matches) is
  rejected with the current version, not silently overwritten.
- Publishing transitions the linked `kb.inputs` row and hands the document to
  the standard doc-processing worklist; it does not run the pipeline itself.
  After publishing, the document is read-only — any further save attempt is
  rejected with a frozen error.
- Preview compiles through the same Typst path publishing uses, cached by
  `content_version`, and never runs on a per-keystroke basis.

## Consequences

### Positive
- CDM Phase 1's Go packages are now reachable from a browser at all, and
  from any future caller (CLI, agents, imports) that wants the same HTTP
  surface.
- Optimistic concurrency and the frozen-document rule are now real,
  database-enforced invariants rather than conventions a future writer could
  accidentally skip.
- The editor's in-memory model is isomorphic to `[]model.Block` with no
  translation layer, so the "saving is a serialization, not a conversion"
  property (D11 in spec `2026072502`) is a property of the code, not an
  aspiration.
- The full authoring loop is proven end to end on nine block types, so
  further editor feature work (semantic annotation, reviewers, etc.) has a
  working spine to build against rather than an unproven one.

### Negative / accepted limitations
- An author who edits a published document has no way forward yet — they are
  told why, but the "open a new version" action does not exist.
- Multi-tenancy remains unenforced at the API layer.
- The editor's block ids do not yet deliver the "readable" half of D9's
  promise in practice, only the "stable" half.
- This implementation's own test run could not exercise the real database or
  a real authenticated session; that gap is structural to the environment it
  was built in, not to the tests themselves.

## References
- `ChenWeb/openspec/changes/cdm-editor-mvp/proposal.md`
- `ChenWeb/openspec/changes/cdm-editor-mvp/design.md`
- `ChenWeb/openspec/changes/cdm-editor-mvp/tasks.md`
- `ChenWeb/openspec/changes/cdm-editor-mvp/specs/cdm-http-api/spec.md`
- `ChenWeb/openspec/changes/cdm-editor-mvp/specs/cdm-editor-ui/spec.md`
- [2026072603-adr-cdm-editor-frontend.md](../../adrs/202607/2026072603-adr-cdm-editor-frontend.md)
- [2026072502-spec-cdm-editor.md](../../specs/202607/2026072502-spec-cdm-editor.md)
- [2026072501-spec-canonical-doc-model.md](../../specs/202607/2026072501-spec-canonical-doc-model.md)
- [2026072602-adr-cdm-editor-scope.md](../../adrs/202607/2026072602-adr-cdm-editor-scope.md) — DR5d (TOC/figure/table/formula lists), consumed by preview
- `ChenWeb/server/api/cdmhandler/`
- `ChenWeb/server/api/cdm/store/`
- `ChenWeb/web/src/routes/home3/cdm/`
- `ChenWeb/web/src/lib/components/cdm/`
