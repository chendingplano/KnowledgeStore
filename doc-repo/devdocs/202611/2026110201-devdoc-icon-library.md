# Icon Library — a searchable catalogue of vector icons shared by all projects

**Date:** 2026-11-02 \
**Scope:** What the icon library is, how icons get into it, how a project finds and shows an icon, and what is deliberately not done yet.
**Code root:** `shared/go/api/iconlib/`, `shared/svelte/src/lib/components/icons/`

**Traceability — openspec:**
- `shared/openspec/changes/archive/2026-11-02-shared-icon-library/proposal.md` — why this exists
- `shared/openspec/changes/archive/2026-11-02-shared-icon-library/design.md` — rationale, alternatives, the change of plan to a new table
- `shared/openspec/changes/archive/2026-11-02-shared-icon-library/tasks.md` — implementation log
- `shared/openspec/specs/icon-library/spec.md`, `icon-search/spec.md`, `icon-picker/spec.md` — the canonical requirements. **Update these spec files, not just this doc, if behavior changes** — this doc explains the feature for humans and points at code; the specs are the contract for agents.

## Summary

Any project in the workspace that needs an icon, whether a developer choosing one at build time or a user choosing one at run time, can now pick it from one shared library instead of keeping its own list. The library holds about 6,500 vector icons (they stay sharp at any size and take the colour of the surrounding text).

The key feature is finding an icon by describing it. Every icon carries keywords, a category and a one-sentence description in both English and Chinese. Typing "reload", "刷新" or "two arrows in a loop" all lead to the same refresh icon. The icons come from two open-source sets, Lucide first and Tabler only for pictures Lucide does not have, so the look stays consistent. People can also add their own SVG icons.

Search is a blend of two methods: word matching, which is good at exact keywords in either language, and meaning matching, which is good at descriptions. If the meaning-matching service is not available, word matching still works on its own.

## Where things live

- **Data:** table `shared.icon_library` in the project database, created by a ChenWeb migration (`ChenWeb/shared_migrations/20261103000001_create_shared_icon_library.sql`). It is a new table; the older file-upload icon manager in `shared/` was left alone.
- **Server code:** `shared/go/api/iconlib/` (search, SVG lookup, SVG cleaning, adding custom icons). Web endpoints are in `shared/go/api/RequestHandlers/iconlib_handlers.go`, under `/shared_api/v1/icons/` (`search`, `by-name/:name/svg`, and `POST library`).
- **Filling the library:** two command-line tools in `shared/go/cmd/`. `icon-seed` imports the icons; `icon-enrich` writes the Chinese and English text and the meaning vectors with an AI model (prompt in `icon-enrich/prompt-icon-metadata-v1.md`). Both can be re-run safely and only do missing work.
- **Screens:** `Icon` (shows an icon by name) and `IconSearchPicker` (a search box with a grid of results), both in `shared/svelte/src/lib/components/icons/`. The picker takes its wording from the host app so it can follow the app's language.
- **ChenWeb:** at start-up it hands the library its search-query embedder (`server/api/kbhandler/icon_search_embedder.go`).

## Known limitations

- Nothing in ChenWeb's screens uses the picker yet. The page-designer `icon-picker` field is still a plain list picker; connecting it is part of the separate value-editor work.
- The 114 existing places in ChenWeb that import Lucide icons directly were not changed. They keep working and do not go through the library.
- Search by long English descriptions leans on the meaning-matching half. Without the embedding service, word matching alone ranks such queries less well.
- Chinese and English descriptions and translations were written by an AI model and have only been spot-checked.
- Only outline icons are included, so everything shares one visual style. Only Postgres is supported.
- Re-running `icon-seed` with a newer Lucide or Tabler release updates icons but does not refresh their text; run `icon-enrich` again for new ones.
