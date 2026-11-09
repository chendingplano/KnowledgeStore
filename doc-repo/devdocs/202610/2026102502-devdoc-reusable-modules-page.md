# Modules — searchable reusable module catalogue

**Date:** 2026-10-25 \
**Scope:** Finding and inspecting registered reusable modules in ChenWeb. \
**Code root:** `ChenWeb/web/src/lib/components/home3/reusable-modules-view.svelte`

## Summary

Open **Development → Modules** on ChenWeb's `/development` page to browse the reusable module registry. Each module appears as a fixed-size card with its name, description, status, type, programming language, version, and file count. Search narrows the cards immediately as you type. Details opens a dialog showing the complete description, capability, use-when text, documentation path, files, developer documents (devdocs), configuration, and creation/update information. Interface labels support English and Chinese, and all page text is selectable.

## Details

The menu uses `view=development&child=dev-modules`, preserving selection when reloading. The authenticated `GET /api/v1/reusable-modules` endpoint returns `{ "modules": [...] }` with every column from `kb.reusable_modules`, plus `capability_label` from `kb.reusable_module_capabilities`, ordered by `module_name`, then `module_id`. An unclassified module has `capability` and `capability_label` set to `""`. The index fields `capability`, `use_when` and `devdoc_paths` (added 2026-11-09) are also what the `find-reusable-module` skill searches; see that skill for how agents use the catalogue. It uses the shared project database pool and logs successful reads and failures. An empty registry returns an empty array. Query, scan, and iteration failures return HTTP 500 with a generic message; database error details remain in server logs.

Search runs locally over all loaded records, matching a trimmed, case-insensitive substring against module ID, name, description, type, language, raw status, version, capability code and label, use-when text, documentation path, file paths, devdoc paths, and serialized configuration. It supports Chinese descriptions as well as English. Names, descriptions and paths are registry content and are displayed as stored; translated labels do not rewrite that content.

Cards are 340 × 280 CSS pixels and wrap into as many columns as the panel fits. They use a solid brighter slate background in dark mode and white in light mode. On narrow mobile screens their width shrinks to fit. Long card descriptions scroll; the details dialog retains full text. A highlighted strip containing the grip, module ID, and close button sits above the title. Drag anywhere on that strip except the close button to move the dialog; the grip also supports arrow keys (10 pixels per keypress). Each opening positions the dialog beside the clicked Details button, preferring its right side, then its left side, with an above/below fallback when neither side fits. Content renders before the dialog is measured. Positioning and movement stay within the viewport and adjust on window resize. Loading, error/retry, empty-registry, and no-search-match states have separate messages. Native modal behavior supplies keyboard focus handling and Escape to close.

## Known limitations

- The catalogue is read-only. Registry maintenance remains with the `create-reusable-module` workflow, whose `check` step keeps rows and module docs in sync.
- All records are loaded together; search is client-side with no pagination.
- Documentation and file paths are displayed as copyable text; the page does not expose local files over HTTP.
- Search matches stored values, such as `frontend` or `active`, rather than translated type/status labels.
