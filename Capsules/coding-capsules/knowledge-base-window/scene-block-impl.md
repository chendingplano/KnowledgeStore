# Scene Blocks — Implementation Notes

Companion to the `Scene Blocks` section in `+CAPSULE.md`. This document records
**how** the feature is built and **why** the design decisions were made, for
anyone maintaining or extending it.

## Summary

`Scene Blocks` is a read-only workbench section under **Subject Wiki** in the
`ChenWeb::/home3/knowledge` window. It lists the event-driven *scene blocks*
an LLM extracted from a document and lets the user drill into each one through
an inline-accordion master–detail layout, with the source PDF for context.

It was built as a full vertical slice:

```
kb.scene_objects (DB)
   └─ ListSceneBlocks  (Go HTTP handler)
        └─ GET /api/v1/kb/scene-blocks
             └─ listKbSceneBlocks()  (frontend service)
                  └─ scene-blocks-view.svelte  (UI)
                       └─ wired in /home3/knowledge/+page.svelte
```

## Data model

Scene blocks live in the `kb.scene_objects` table (PostgreSQL, `kb` schema),
one row per block, uniquely keyed by `(input_record_id, object_id)`. Rows are
produced by the `generate-scene-blocks` doc-processing processor and are never
written by this UI.

Field shape (from the extraction prompt `prompts/prompt-generate-scene-blocks.md`):

- **Scalars**: `scene_id`, `scene_type`, `title`, `summary`, `event_id`,
  `confidence`, `model_name`, `prompt_name`, `create_time`, `modify_time`.
- **String arrays**: `preconditions`, `triggers`, `states`, `decisions`,
  `constraints`, `outcomes`, `failure_modes`, `root_causes`, `resolutions`,
  `keywords`.
- **Object arrays**:
  - `actors` / `resources` — `{ type, name }`
  - `actions` — `{ sequence, actor, action }`
  - `relationships` — `{ type, target }`
  - `source_refs` — `{ source_id, evidence_type, reference }`
  - `discriminators` — nested retrieval-discriminator objects

Migration: `ChenWeb/project_migrations/20260518000003_create_kb_scene_objects_table.sql`

## Backend

**Handler** — `ChenWeb/server/api/kbhandler/scene_blocks_handler.go`

- `ListSceneBlocks(c echo.Context) error`
- Route: `GET /api/v1/kb/scene-blocks?input_record_id=N`
- Self-contained, following the `topic_chunks_handler.go` idiom: uses
  `EchoFactory.NewFromEcho`, `ApiTypes.ProjectDBHandle`, the shared
  `errorResponse` struct, and the package's `resolveInputTable` helper.
- Query: `SELECT ... FROM kb.scene_objects WHERE input_record_id = $1 ORDER BY id`.
- **JSONB columns are passed through verbatim** as `json.RawMessage`. This
  avoids a re-marshal round trip and means the frontend receives the exact
  LLM-extracted structure. `jsonArrayOrEmpty` guards against a NULL slip by
  substituting `[]`.
- `file_name` is fetched best-effort from the inputs table so the UI can
  decide whether the source renders as a PDF. A lookup failure must not hide
  the scene blocks.
- Error codes: `CWB_KB_SB_010` (bad input id), `CWB_KB_SB_011` (no DB),
  `CWB_KB_SB_020/021/022` (query/scan/iteration failures).

**Route registration** — `ChenWeb/server/api/routes.go`

Registered next to the chunks route:

```go
apiGroup.GET("/kb/scene-blocks", kbhandler.ListSceneBlocks)
```

Sits under the authenticated `/api/v1` group (`authmiddleware.AuthMiddleware`).

Response shape:

```jsonc
{
  "status": true,
  "input_id": 93,
  "file_name": "rabies-protocol.pdf",
  "results": [ /* sceneBlockRecord, JSONB fields verbatim */ ],
  "total": 3
}
```

## Frontend service

`ChenWeb/web/src/lib/services/kbService.ts`

- `listKbSceneBlocks(inputRecordId: number): Promise<ListKbSceneBlocksResponse>`
  using the shared `fetchOrThrow` helper and `BASE = '/api/v1/kb'`.
- Typed schema added: `KbSceneBlockRecord`, `KbSceneActor`, `KbSceneResource`,
  `KbSceneAction`, `KbSceneRelationship`, `KbSceneSourceRef`,
  `KbSceneDiscriminator`, `ListKbSceneBlocksResponse`.
- Logs a compact summary to the console on fetch, matching `listKbChunks`.

## UI component

`ChenWeb/web/src/lib/components/home3/scene-blocks-view.svelte`

### Composition

Mirrors the `topic-tree-view.svelte` shell so it is visually indistinguishable
from its siblings:

```
scene-shell (flex column, height 100%)
├─ hero            eyebrow + title + description + inline stat caption
└─ workspace       grid: auto | minmax(0,1fr)
   ├─ KbInputRecordBrowser     (shared kb.inputs browser, self-resizing)
   └─ right-panel
      ├─ right-tabs            "Scene Blocks" + record title
      └─ detail-grid           flex row
         ├─ scene-card         resizable accordion list
         ├─ resize-handle      drag / arrow-key, width persisted to localStorage
         └─ pdf-card           PdfViewWindow + "Scene context" sidebar snippet
```

- Reuses `KbInputRecordBrowser` (record selection, search, paging) and
  `PdfViewWindow` (PDF render + sidebar). No bespoke versions of either.
- **Scroll containment** (non-obvious): the `EXTRACTED SCENES` list
  (`.scene-list`) scrolls internally when it overflows. Two CSS rules are
  load-bearing: `.workspace` must set `grid-template-rows: minmax(0, 1fr)` so
  the grid row is clamped to the viewport (an `auto` implicit row lets the
  panel grow with content and the inner scroll never triggers), and
  `.scene-block` / `.skeleton-row` must set `flex: 0 0 auto` so the flex-column
  rows keep their natural height instead of being compressed to fit. Without
  the second rule the rows shrink to thin slivers rather than overflowing.
- `scopeToActiveStore` defaults `false`, matching every sibling view (none of
  them pass it, so the record list shows **all** `kb.inputs` records by
  default). Scoping it to the active store filters the list by store id and
  returns nothing when records aren't tagged to that store, so the unscoped
  default is correct here. The section is still gated behind the active-store
  requirement in `+page.svelte` (`needsActiveStore`) for store selection, but
  the record browser itself is not store-filtered.

### Inline-accordion master–detail

Each scene block is a collapsed row: leading index, scene-type pill, title,
summary (2-line clamp), keyword chips, and a color-banded confidence meter
(`high` ≥ 0.8, `mid` ≥ 0.5, `low` otherwise). One row expands at a time
(`expandedBlockId`); the chevron rotates via `transform`, content enters with
a `fly` transition (opacity + translate, no layout-property animation).

### The narrative-arc design decision

A scene block has ~20 mixed fields. Rendering them as a flat field list is the
generic, low-value approach. Instead the expanded detail is grouped as a
**narrative arc**, and **empty groups are removed entirely** so sparse blocks
stay clean:

| Group | Fields | Rendering |
|---|---|---|
| **Cast** | actors, resources | typed entity chips (`type · name`) |
| **Setup** | preconditions, triggers, states | bulleted string lists |
| **Flow** | actions, decisions, constraints | numbered action sequence + lists |
| **Resolution** | outcomes, failure_modes, root_causes, resolutions | bulleted lists |
| **Links & evidence** | relationships, source_refs, discriminators | `type → target` chips, evidence rows, discriminators behind a disclosure |

A mono footer shows `scene_id`, `event_id`, and the extraction model. The
`discriminators` block is deeply nested and rarely needed, so it sits behind a
"Show retrieval discriminators" disclosure (progressive disclosure).

### PDF column — deliberate honesty

Unlike topics/chunks, scene block `source_refs` are
`{ source_id, evidence_type, reference }` free-text — **no page numbers or
bounding-box coordinates**. So the PDF is *not* auto-highlighted and the page
is *not* jumped. The right column renders the source document plus a
"Scene context" sidebar that recaps the expanded block and surfaces its
`source_refs` as textual evidence locators, with a one-line note explaining why
highlighting is unavailable. This was chosen over a fake/guessed highlight.

### States

- **No record selected** — instructional empty state.
- **Loading** — animated skeleton rows (not a spinner).
- **Error** — red-tinted card; surfaces the backend error code verbatim.
- **No scene blocks** — teaching empty state naming `kb.scene_objects` and the
  `generate-scene-blocks` processor.
- **Sparse block** — empty narrative groups disappear; only populated groups
  and the footer render.
- **Non-PDF source** — graceful "source isn't a PDF" notice; detail still
  available in the accordion.
- **Responsive** — below 980px the workspace stacks vertically (structural
  redesign, not fluid shrink); the resize handle is hidden.

### Design-system conformance

Matches the sibling vocabulary exactly: dark default, Restrained palette
(tinted neutrals + single green accent for selection/structure/state), eyebrow
labels, monospace IDs/meta, rounded panels, the shared resize-handle pattern.
No side-stripe accent borders (selection uses a full border + background tint +
leading index), no gradient text, no glassmorphism, no hero-metric card
template, no modals, no em dashes.

## Wiring

`ChenWeb/web/src/routes/home3/knowledge/+page.svelte`

1. `import SceneBlocksView`.
2. `'kb-scene-blocks'` added to the `KbSectionId` union.
3. Child menu item added under **Subject Wiki**, positioned after `Metrics`
   and before `Provision Tree` (matches the capsule's ordering).
4. Render branch: `<SceneBlocksView {darkMode} browserInstanceKey="scene-blocks" />`.
5. **Not** added to `KNOWLEDGE_UNDER_CONSTRUCTION_SECTIONS` — it is a real
   section, so `needsActiveStore` correctly requires an active knowledge store.

## Verification

- Go: `go build ./api/...` clean.
- Frontend: `svelte-check` reports **0 errors / 0 warnings** on
  `scene-blocks-view.svelte`, `kbService.ts`, and the `+page.svelte` route.
- Visual: verified with realistic mock data via a throwaway preview route +
  Playwright network interception (rich block, sparse block, empty, error,
  loading, non-PDF, narrow viewport). The temp route was removed from the repo
  after verification.
- **Not yet verified against real `kb.scene_objects` data** — the app is
  auth-gated and requires an active store. A sanity pass against a real
  processed record is still recommended.

## Key files

- `ChenWeb/server/api/kbhandler/scene_blocks_handler.go`
- `ChenWeb/server/api/routes.go`
- `ChenWeb/web/src/lib/services/kbService.ts`
- `ChenWeb/web/src/lib/components/home3/scene-blocks-view.svelte`
- `ChenWeb/web/src/routes/home3/knowledge/+page.svelte`
- `ChenWeb/project_migrations/20260518000003_create_kb_scene_objects_table.sql`
- `prompts/prompt-generate-scene-blocks.md`
- `KnowledgeStore/Capsules/coding-capsules/knowledge-base-window/+CAPSULE.md`

## Extension notes

- **Highlighting**: if scene extraction is later changed to emit line/page
  references in `source_refs.reference` (or a structured field), the PDF column
  can adopt the topic-tree `renderHighlights` + page-jump contract. The UI
  already isolates this concern in the PDF card.
- **Filtering / search**: `kb.scene_objects` has a GIN index on `keywords`;
  a keyword or `scene_type` filter could be added to the handler and surfaced
  as list controls without changing the layout.
- **Editing**: the table supports upsert, but this UI is intentionally
  read-only; an edit affordance would need a new write endpoint and is out of
  scope for the current section.
