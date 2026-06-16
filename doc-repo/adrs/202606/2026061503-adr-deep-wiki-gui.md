# ADR: Artifact Categories

**Date:** 2026-06-15 \
**Status:** Proposal \ 
**Component:** ChenWeb:localhost:8080/deep-wiki \
**Authors**: Chen Ding \
**Tags**: deep wiki, GUI \

## Change Logs
* 2026/06/15, ADR Created
* 2026/06/15, Change 01 implemented and ADR updated
* 2026/06/15, Change 02 implemented and ADR updated

## Change 01
Date: 2026/06/15 \
Type: missing implementation \
Status: completed by Codex

## Context
The counts in the window are not real.
| Name | Where to Retrieve |
|------|-------------------|
| Topics | `kb.topics` |
| Documents | `kb.inputs` |
| Entities & Relations | `kb.entities`, 'kb.relations` |
| Content Segments | `kb.chunks` |
| Parts & Components | `kb.inventory_items` |
| Provisions | `kb.provisions` |
| Scenes | `kb.scene_objects` |
| Semantic Projections | `kb.semantic_projections` |
| Metrics | `kb.metrics` |
---

### Alternative Decisions

### Database Migrations

### Data Formats

### Environment Variables

### Implementation

### Code Changes

Change 01 is implemented in `ChenWeb/server/api/kbhandler/wiki_overview_handler.go`.

- Deep Wiki overview counts now use the ADR table mapping directly.
- `Documents` now resolves to `kb.inputs` when present, with `kb.input` retained
  only as a compatibility fallback for older environments.
- `Parts & Components` now counts `kb.inventory_items` instead of `kb.products`.
- The rest of the landing-page counters continue to read from:
  `kb.topics`, `kb.chunks`, `kb.semantic_projections`, `kb.metrics`,
  `kb.provisions`, `kb.scene_objects`, `kb.entities`, and `kb.relations`.
- Recent activity joins on the same landing-page document table so the counts and
  document feeds stay consistent.

### Operational Behaviors

- The Deep Wiki hero and landing page no longer show counts derived from the
  wrong artifact families.
- When both `kb.input` and `kb.inputs` exist, the landing page prefers
  `kb.inputs`, which matches the current knowledge-base schema.

### Consequences

- Landing-page numbers now match the actual KB storage tables described in this ADR.
- The `Entities & Relations` card remains the sum of the separate `kb.entities`
  and `kb.relations` counts.
- Older deployments that still expose only `kb.input` continue to load, but the
  canonical source is now `kb.inputs`.

### Tests

`ChenWeb/server/api/kbhandler/wiki_overview_handler_test.go`:
- Added `TestWikiOverviewUsesADRCountTables`.
- Verifies the landing page prefers `kb.inputs` over `kb.input` when both exist.
- Verifies `Parts & Components` counts `kb.inventory_items`.
- Verifies the response keeps separate entity and relation counts.

## Change 02
Date: 2026/06/15 \
Type: improvement \
Status: completed by Codex

## Context
In `localhost:8080/home3/knowledge?section=kb-search`, "Search in" line:
- Remove 'Products'
- Add 'Summaries', 'Semantic Projections', 'Entities', 'Relations', 'Content Segments'

### Alternative Decisions

### Database Migrations

### Data Formats

### Environment Variables

### Implementation

### Code Changes

Change 02 is implemented in:

- `ChenWeb/web/src/lib/components/home3/kb-search-lab-state.ts`
- `ChenWeb/web/src/lib/services/kbArtifactSearch.ts`
- `ChenWeb/web/src/lib/components/home3/kb-search-results-view.svelte`
- `ChenWeb/web/src/lib/components/home3/kb-search-lab-view.svelte`

The "Search in" chip row now:

- Removes `Products`
- Keeps `Summaries`
- Adds `Content Segments`
- Adds `Semantic Projections`
- Adds `Entities`
- Adds `Relations`

Scope-to-registry mappings now use:

- `content-segments` -> `chunk`
- `semantic-projections` -> `semantic_projection`
- `entities` -> `entity`
- `relations` -> `relation`

The shared artifact-option list is used by both the search results page and the
KB Search Lab, so both surfaces now expose the same scopes.

### Operational Behaviors

- Users can narrow search directly to chunks, semantic projections, entities,
  and relations from the top chip row.
- The search page no longer advertises the old `Products` scope.
- The KB Search Lab still supports relation/product-specific filter fields under
  the broader registry endpoint where relevant.

### Consequences

- The search UI now better matches the artifact families present in the Deep Wiki.
- Search-scope labels in the UI are decoupled from backend registry keys, so the
  page can use user-facing names like `Content Segments` while querying `chunk`.
- The old `product` registry scope remains available through the backend, but it
  is no longer promoted in the "Search in" row.

### Tests

`ChenWeb/web/src/lib/services/kbArtifactSearch.test.ts`:
- Added coverage that the new scopes map to the expected registry artifact types.
- Added coverage that the shared search-chip list removes `Products` and includes
  `Content Segments`, `Semantic Projections`, `Entities`, and `Relations`.

### Documentation Impact

- This ADR now reflects the implemented Change 02 behavior.
- No additional ADRs were required for this fix.

## References

- `ChenWeb/server/api/kbhandler/wiki_overview_handler.go`
- `ChenWeb/server/api/kbhandler/wiki_overview_handler_test.go`
- `ChenWeb/web/src/lib/components/home3/kb-search-lab-state.ts`
- `ChenWeb/web/src/lib/services/kbArtifactSearch.ts`
- `ChenWeb/web/src/lib/components/home3/kb-search-results-view.svelte`
