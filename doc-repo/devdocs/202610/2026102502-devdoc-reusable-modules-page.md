# Modules — searchable reusable module catalogue

**Date:** 2026-10-25 \
**Scope:** Finding and inspecting registered reusable modules in ChenWeb. \
**Code root:** `ChenWeb/web/src/lib/components/home3/reusable-modules-view.svelte`

## Summary

Open **Development → Modules** on ChenWeb's `/development` page to browse the reusable module registry. Each module appears as a fixed-size card with its name, description, status, type, programming language, version, and file count. Search narrows the cards immediately as you type. Details opens a dialog showing the complete description, files, configuration, documentation path, and creation/update information. Interface labels support English and Chinese, and all page text is selectable.

## Details

The menu uses `view=development&child=dev-modules`, preserving selection when reloading. The authenticated `GET /api/v1/reusable-modules` endpoint returns `{ "modules": [...] }` with every column from `kb.reusable_modules`, ordered by `module_name`, then `module_id`. It uses the shared project database pool and logs successful reads and failures. An empty registry returns an empty array. Query, scan, and iteration failures return HTTP 500 with a generic message; database error details remain in server logs.

Search runs locally over all loaded records, matching a trimmed, case-insensitive substring against module ID, name, description, type, language, raw status, version, documentation path, file paths, and serialized configuration. It supports Chinese descriptions as well as English. Names, descriptions and paths are registry content and are displayed as stored; translated labels do not rewrite that content.

Cards are 340 × 280 CSS pixels and wrap into as many columns as the panel fits. They use a solid brighter slate background in dark mode and white in light mode. On narrow mobile screens their width shrinks to fit. Long card descriptions scroll; the details dialog retains full text. Its header has a drag handle supporting pointer movement and arrow keys (10 pixels per keypress). Movement stays within the viewport, adjusts on window resize, and resets to the centered position each time Details opens. Loading, error/retry, empty-registry, and no-search-match states have separate messages. Native modal behavior supplies keyboard focus handling and Escape to close.

## Known limitations

- The catalogue is read-only. Registry maintenance remains with the `create-reusable-module` workflow.
- All records are loaded together; search is client-side with no pagination.
- Documentation and file paths are displayed as copyable text; the page does not expose local files over HTTP.
- Search matches stored values, such as `frontend` or `active`, rather than translated type/status labels.
