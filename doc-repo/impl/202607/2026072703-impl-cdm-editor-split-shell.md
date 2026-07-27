# CDM Editor: Split-Pane Shell, Deferred Create, and One Shared Design

**Date:** 2026-07-27 \
**Status:** Implemented \
**Component:** CDM Editor UI (ChenWeb `web/src/lib/components/cdm`,
`web/src/routes/home3/cdm`, `web/src/lib/components/home3/content-panel.svelte`) \
**Authors**: Claude \
**Tags**: SemOS, CDM, editor, frontend, Svelte, UX

## Change Logs
* 2026/07/27, document created, recording a same-day follow-up to impl
  `2026072702` (the workspace tile and rebuilt list page): a redesign of the
  editor's own layout and creation flow, requested after that work shipped.

## Purpose

Two things changed about how the CDM Editor works, both requested directly
against the shipped `2026072702` design rather than through a new OpenSpec
change (consistent with how this session's prior CDM Editor work — the
workspace tile, the bug fix, the `/development` nav entry — was also done
directly):

1. **One shared design, not two.** `2026072702` gave `/development`'s Tools ▸
   CDM Editor its own rebuilt `DocumentListView`, while `/home3/cdm` and
   `/home3/cdm/[key]` kept the MVP's original single-column editor with a
   store-gate and a modal preview overlay. Asked to make this **one** design
   everywhere, not an embed-only variant.
2. **A different editing shape.** Instead of a single column with a modal
   preview, the editor is now a persistent two-pane shell — document
   list/editor on the left, a docked live preview on the right, a draggable
   divider between them — with no store-picker gate to clear first, and no
   API call for "New Document" until the author actually confirms a save.

## Summary

- **`CdmEditorShell.svelte`** is the one new component all three hosts now
  render: `/home3/cdm`, `/home3/cdm/[key]`, and the `/development` embed.
  It owns knowledge-store resolution (auto-selects one on mount if none is
  active — no gate screen), list/editor mode, the split-pane layout with a
  drag-resizable divider (the same mechanic `dashboard.svelte`'s rail/shelf
  resize already uses), and the docked preview pane.
- **Creating a document no longer calls the API immediately.** "New Document"
  opens a fresh, empty, purely in-memory `Document` (`document_key: ''`)
  straight into the editor. Nothing is written to `kb.inputs` until the
  author clicks Save on that document for the first time, and even then only
  after confirming a dialog that **names the knowledge store** the document
  will be created in. This does not change the API (`CreateDocument` still
  writes both rows atomically — design D2) or the store's own invariants;
  what moved is *when the UI decides to call it*, from "as soon as a title is
  typed" to "the first time the author actually saves."
- **Preview moved from a modal to a docked pane.** `DocumentEditor.svelte`
  still owns the render fetch (`renderDocument`, its error handling, staleness
  awareness), but now writes the result into three `$bindable` props instead
  of rendering its own overlay; `CdmEditorShell` displays them in the
  persistent right pane. Design D9's own rule — preview is explicit-action
  only, never per-keystroke — is unchanged; only where the result is shown
  moved.
- **The document list's title filter is a "Search" button**, not a text
  input left open at all times — matching the *style* of the "Search" button
  `kb-input-record-browser.svelte` already uses (pill shape, icon + label,
  hover-accent border), opening a small popover scoped to a title-contains
  filter. It does not reuse that component's `KbInputSearchDialog` (a
  1,270-line kb.inputs query dialog shared across four other views, returning
  `KbInputRecord[]`, not CDM documents) — matching style only was the explicit
  choice made when this was raised as a fork in the road before building it.
- **The store picker and "New Document" form are gone** from
  `DocumentListView`; a compact knowledge-store dropdown and a "New Document"
  button sit in the masthead where they were, doing the same two jobs (switch
  store, start a document) without a separate gate screen or up-front title
  prompt.

## Main Code Changes

### 1. `CdmEditorShell.svelte` (new)

File: `web/src/lib/components/cdm/CdmEditorShell.svelte`.

Props: `darkMode`, `initialDocumentKey` (deep-link entry), `routed` (whether
this host has a real per-document URL to navigate for "back"), `onBack`.

- **Store resolution.** On mount, loads `listKnowledgeStores()`; if
  `knowledgeStoreState.activeStore` is still null once that resolves, picks
  `stores[0]` automatically. The only remaining "no store" state is the true
  edge case of zero stores existing — shown as a plain notice, not a picker,
  since there is nothing to pick from.
- **Mode.** `mode: 'list' | 'editor'`, with `editingDocument` holding either a
  document fetched by key (`getDocument`) or a fresh in-memory draft.
  `editingDocument` is declared with **`$state.raw`, not `$state`** — this
  matters: `DocumentEditor.svelte` takes its own private copy via
  `structuredClone(initialDocument)`, and `structuredClone` cannot clone a
  Svelte 5 reactive proxy. This is the same crash `DocumentEditorPage.svelte`
  was built to avoid in the original MVP (ADR 2026072603, 2026/07/27 entry);
  it was caught here by Playwright (`pageerror: ... could not be cloned`)
  before shipping, not by inspection — worth calling out since it is exactly
  the kind of regression an ad-hoc rewrite reintroduces from a fix that was
  never made structurally hard to undo.
- **Split-pane divider.** A drag-resizable divider between `.cdm-shell-left`
  and `.cdm-shell-right`, using the identical mousedown/mousemove/mouseup
  pattern `dashboard.svelte` already uses for its rail/shelf resize (clamped
  min/max, no new abstraction introduced for it).
- **Deep-link entry.** `initialDocumentKey` is opened once per distinct value
  (tracked against the last-opened key, not a one-time `onMount`), mirroring
  the retired `DocumentEditorPage.svelte`'s own guard against re-fetching on
  an unrelated re-render.

### 2. `DocumentEditor.svelte` — deferred create, docked preview

File: `web/src/lib/components/cdm/DocumentEditor.svelte`.

- New `isNew = doc.document_key === ''`. Save on a new document does not call
  `saveDocument`; it opens a confirmation dialog (`showCreateConfirm`) naming
  the target knowledge store (`createTarget: CreateTarget | null`, a new type
  in `cdm-client.ts`: `tenantId`, `ksStoreId`, `ksName`). Confirming calls
  `createDocument` and adopts the server-allocated `document_key` and
  `content_version` into the same in-memory `doc`, the same conservative way
  `save()` already adopted `content_version` alone rather than replacing the
  whole document. `onCreated?: (key: string) => void` fires once, after that
  succeeds, so the host can refresh its list without polling.
- Preview and Publish are disabled while `isNew` (both need a real
  `document_key` neither has yet), each with a `title="Save the document
  first"` tooltip. The version badge reads "not yet saved" instead of a
  version number.
- `previewPages`, `previewVersion`, `previewLoading` became `$bindable` props
  instead of local `$state` rendered into a fixed-position modal overlay
  (`cdm-preview-overlay`/`cdm-preview-panel`, both removed). `preview()` is
  otherwise unchanged — same explicit-action-only guard (D9), same error
  handling, now guarded defensively against `isNew` too (`if
  (!doc.document_key) return;`) even though the button is already disabled
  for that case.
- Everything else — save/publish error handling
  (`CdmStaleVersionError`/`CdmFrozenError`/`CdmValidationError`/
  `CdmBlockConflictError`), the frozen-document banner, `BlockList` wiring —
  is untouched.

### 3. `DocumentListView.svelte` — store/creation logic moved up

File: `web/src/lib/components/cdm/DocumentListView.svelte`.

Now a required-props component, not a self-contained page: `activeStore`,
`stores`, `onChangeStore`, `onNewDocument`, `onOpenDocument`, `refreshKey`.
Everything it used to own directly — `listKnowledgeStores`, the store gate,
`knowledgeStoreState` reads, the "New Document" title-input-and-create form —
moved to `CdmEditorShell`; this component now only lists documents for the
store it is given.

- **Row navigation.** Rows stay real `<a href="/home3/cdm/{key}">` elements
  (so right-click "copy link" and ctrl/cmd/middle-click "open in new tab"
  still work) but a plain left-click is intercepted (`preventDefault` +
  `onOpenDocument(key)`): opening a document is in-shell state, not a
  navigation, since the `/development` embed has no per-document route to
  navigate to and a full navigation on `/home3/cdm` would remount the shell
  for no reason.
- **Search.** The `<input placeholder="Filter by title…">` became a
  `.cdm-search-btn` (icon + "Search" label, matching
  `kb-input-record-browser.svelte`'s own `.ghost.search-btn` visual pattern —
  pill shape, hover-accent border) opening a small popover with the actual
  text input, `Search`/`Clear` actions, and an Escape-to-close handler. The
  underlying filter logic (`titleFilter`, client-side over the page
  `ListDocuments` already returned) is unchanged.
- **Masthead controls.** The old `.cdm-store-chip` (name + "Change" link) and
  the `.cdm-create` panel (title input + "Create & open") are gone, replaced
  by a compact `<select>` (knowledge store) and a "New Document" button in
  the same header-right position.

### 4. Routes and the `/development` embed

- `web/src/routes/home3/cdm/+page.svelte` and `.../cdm/[key]/+page.svelte`
  are now thin wrappers rendering `<CdmEditorShell routed ... />` — the
  `[key]` route's own crumb/back-link markup was removed since
  `CdmEditorShell` renders that itself once a document loads; `[key]` passes
  `onBack={() => goto('/home3/cdm')}` so the URL and the visible pane never
  disagree after "back" (the plain `/home3/cdm` route needs no `onBack`,
  since opening a document from its own list is local state and never leaves
  that URL to begin with).
- `content-panel.svelte`'s `cdm-editor` branch now renders `<CdmEditorShell
  {darkMode} />` (embedded, `routed` defaults to false) instead of
  `DocumentListView` directly. `cdm-editor` was added to the `showFooter`
  exclusion list (the same one `chat`/`sysadmin-llm-usage-logs`/etc. use) —
  the shell fills and manages its own height/scroll, like those other
  app-shell views, rather than growing to natural content height with a
  footer below it.
- `DocumentEditorPage.svelte` (the fetch-by-key wrapper `[key]`'s route used
  to delegate to) is deleted; `CdmEditorShell`'s own `openExistingDocument`
  absorbed its one job (fetch, guard against re-fetching the same key, hold
  the result in `$state.raw`).

## What Was Not Changed

1. **The backend contract.** No Go changes, no new endpoints, no migration.
   `CreateDocument` still writes the `kb.inputs` and `kb.cdm_documents` rows
   atomically in one transaction (design D2) — the only thing that moved is
   when the frontend decides to call it.
2. **URL-per-document on `/home3/cdm`.** Opening a document from that route's
   own list is local state, not a navigation — the URL stays `/home3/cdm`
   even while a document is open. Only a direct link to `/home3/cdm/[key]`
   (a bookmark, a link from elsewhere) is bookmarkable; browsing there via the
   list and then refreshing returns you to the list. This is a deliberate,
   documented tradeoff, not an oversight: syncing the URL on every in-shell
   navigation while also supporting the `/development` embed (which has no
   per-document route at all) would have meant either a second routing
   mechanism or fighting SvelteKit's page lifecycle for a "nice-to-have"
   neither host's request actually asked for.
3. **`Preview`/`Publish` gating logic beyond `isNew`.** Publish's existing
   `dirty` guard (blocked while there are unsaved local changes) is untouched
   and still separate from the new `isNew` guard.
4. **Search's scope.** Still a client-side title filter over the page
   `ListDocuments` already returned — no new API parameter, no reuse of
   `KbInputSearchDialog`'s kb.inputs query surface.

## Verification

- `bun run check` — no new errors or warnings in any changed file (the one
  pre-existing unrelated error, `home3/doc-processor-dashboard-state.test.ts`,
  is unaffected).
- `bun test src/lib/components/cdm/` — 83 tests, unchanged, still pass (all
  pure `.ts` module tests; none of this session's `.svelte` changes are
  covered by them, matching this codebase's established "no
  component-testing infrastructure" position — verification here is
  Playwright, below).
- **Live browser (Playwright)**, CDM/kb APIs mocked at the network layer,
  driven against all three hosts in dark and light:
  - `/home3/cdm`: no store-gate text renders; masthead, store dropdown,
    "New Document" appear; the title filter input is gone in favor of a
    "Search" button whose popover correctly narrows/clears the list; opening
    a document via a row click does **not** change the URL; the confirm-create
    dialog names the active store correctly; confirming issues the `POST`
    and the version badge moves from "not yet saved" to "v1"; the divider
    drag changes the left pane's measured width (640px → 787px in the run);
    Preview against an existing document renders into the right pane.
  - `/home3/cdm/[key]`: the editor opens directly from the URL; the crumb
    shows the key; clicking "All documents" navigates back to `/home3/cdm`.
  - `/development`, Tools ▸ CDM Editor: the same split-pane shell renders
    inline, full height, no footer bleed-through; opening a document leaves
    the `/development` URL unchanged, confirming the embedded (non-routed)
    path works independently of the routed one.
  - One real regression was caught and fixed during this pass, not found by
    inspection: `editingDocument` was initially declared with plain `$state`,
    which deep-proxies the object — `DocumentEditor`'s
    `structuredClone(initialDocument)` then threw at runtime the moment a
    row was clicked. Fixed by switching to `$state.raw`, the same fix
    `DocumentEditorPage.svelte` already carried for the identical reason,
    reconfirmed by reverting and re-applying it to watch the failure and
    recovery.

## References
- [2026072702-impl-cdm-editor-workspace-app.md](2026072702-impl-cdm-editor-workspace-app.md)
- [2026072701-impl-cdm-editor-mvp.md](2026072701-impl-cdm-editor-mvp.md)
- [2026072502-spec-cdm-editor.md](../../specs/202607/2026072502-spec-cdm-editor.md)
- [2026072603-adr-cdm-editor-frontend.md](../../adrs/202607/2026072603-adr-cdm-editor-frontend.md)
- `ChenWeb/web/src/lib/components/cdm/CdmEditorShell.svelte`
- `ChenWeb/web/src/lib/components/cdm/DocumentEditor.svelte`
- `ChenWeb/web/src/lib/components/cdm/DocumentListView.svelte`
- `ChenWeb/web/src/lib/components/home3/dashboard.svelte` — the rail/shelf
  drag-resize pattern the shell's divider reuses
- `ChenWeb/web/src/lib/components/home3/kb-input-record-browser.svelte` — the
  "Search" button whose style (not dialog) the list's Search button matches
