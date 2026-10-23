# MeSH search browser — search alongside the existing vocabulary graph

**Date:** 2026-10-23 \
**Scope:** ChenWeb Knowledge → Ontology → MeSH navigation and record search. \
**Code root:** `ChenWeb/server/api/meshbrowser/`, `ChenWeb/web/src/lib/components/home3/`

## Summary

MeSH is a folder under Ontology in the Knowledge page. It contains two separate pages: **MeSH**, the existing vocabulary and graph explorer, and **MeSH Browser**, a search page inspired by NLM's browser. Users can search headings and entry terms, select fields and matching rules, page through results, and inspect a record's properties and links. Both pages use the locally imported MeSH release. Interface labels support English and Chinese; vocabulary text retains its source language.

## Details

- Existing page: `/home3/knowledge?section=kb-ontology-mesh`, rendered by `mesh-browser-view.svelte`. Its behavior and existing URL are preserved.
- Search page: `/home3/knowledge?section=kb-ontology-mesh-browser`, rendered by `mesh-search-view.svelte`.
- Folder key: `kb-ontology-mesh-folder`. The menu resolves page-config visibility and label overrides recursively, including both children. Loading either child URL opens the Ontology and MeSH folders.
- The authenticated read-only endpoint `GET /api/v1/mesh/search` accepts:

| Parameter | Values / behavior |
| --- | --- |
| `q` | Required, trimmed; 1–300 characters, at most 20 whitespace-separated words |
| `field` | `all_terms` (default), `descriptor`, `qualifier`, `scr`, `id`, `scope_note`, `annotation`, `registry`, `pharmacological_action`, `heading_mapped_to`, `free_text` |
| `match` | `all` (default), `any`, `exact` |
| `words` | `full` (default), `substring`; ignored for exact matching |
| `sort` | `label` (default), `label_desc`, `id`; label sorts use ID as the tie-breaker |
| `limit` / `offset` | Existing paging validation: default 50 / 0; limit 1–200, offset nonnegative |

The response is `{items: [{id, label, kind}], has_more}`. One additional row determines `has_more`; no expensive total count is required. Matching is case-insensitive. Exact matching compares a complete field value. All/any matching splits on whitespace and combines word matches across the selected record's searchable values. Full-word matching treats non-word characters as boundaries; substring patterns escape user-supplied SQL wildcard characters.

Search reads `resources.mesh_entity`, `resources.mesh_property`, and `resources.mesh_link`. Term matches follow `term` / `preferredTerm` and `concept` / `preferredConcept` links backwards to the main record. Field filters restrict main record kinds or select relevant source properties and relationships. Pharmacological action and mapped-heading fields match linked target labels or IDs. The query matches source values first, then finds their owners, avoiding a correlated text search per main record. All query input is parameterized, options are allowlisted, and the request has a 20-second database deadline. Request context logging records validation and query failures.

Selecting a search result loads the authenticated read-only `GET /api/v1/mesh/record?id=…` endpoint. It assembles the base entity, imported release, linked concepts with their terms, allowable qualifiers, and tree placements with ancestor paths and immediate children. Tree nodes include the descriptor ID so selecting an ancestor or child opens that descriptor. It uses the existing normalized tables and has a 20-second request deadline; invalid IDs return 400 and missing records return 404. The existing graph page continues to use `/api/v1/mesh/entity` unchanged.

`mesh-record-details.svelte` renders four tabs: **Details**, **Qualifiers**, **MeSH Tree Structures**, and **Concepts**. Details uses a two-column definition list with right-aligned names and left-aligned values. It combines record properties with the preferred concept's scope note, deduplicates entry terms across concepts, and formats record dates as year/month/day. The qualifier tab links to allowable qualifier records. The tree tab shows each placement's ancestor path and direct children. Concepts are expandable, with the preferred concept open initially, and show concept and term metadata. Tab navigation supports arrow keys, Home, and End; labels and empty states support both interface languages. New record selections reset to Details. Source vocabulary text remains in its original language.

Outdated search/detail responses are ignored when a newer request exists. Pagination uses the submitted options even if form controls have since changed.

## Validation

`go test ./server/api/meshbrowser/...` covers option validation, literal wildcard/regex escaping, and SQL parameterization. Set `MESH_TEST_DSN` to a PostgreSQL connection string to run read-only checks against an imported release. The import checks cover search behavior and the assembled Dependovirus record, including its preferred concept, terms, qualifiers, tree ancestors, a missing ID, and a term with no concept or tree data. `bun test src/lib/services/meshRecord.test.ts` verifies detail-field assembly, preferred scope selection, entry-term deduplication, date formatting, and separation of tab data. Frontend validation uses `bun run check` in `ChenWeb/web/`.

## Known limitations

- This is a local search implementation, not an embedded or live replica of NLM's service. Available content depends on the imported release and fields present in its RDF data.
- Results contain main records rather than individual concept and term records; linked concepts and terms can be opened in the details panel.
- The page does not reproduce every NLM-specific advanced field or query syntax. Exact phrase means complete-field equality, not a phrase occurring within longer text.
- No schema or shared-library changes are required. Existing ontology specifications remain unchanged; this note documents the new navigation and read API.
