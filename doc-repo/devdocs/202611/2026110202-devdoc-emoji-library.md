# Shared emoji library

**Date:** 2026-11-02  
**Scope:** The local emoji catalogue, search, picker and WPI value editor in `shared/` and ChenWeb.

## Summary

The emoji library lets applications find an emoji by an English or Chinese word and display the same artwork on different platforms. It uses Twemoji artwork stored in the shared database. Pages store the Unicode text itself, so a saved emoji remains meaningful even if its image cannot be loaded. No external service is needed when a person searches or views the library.

The WPI Editor offers `emoji-picker` as an attribute value editor and as a value-editor element that can be bound to an input-document field. Search and picker labels follow the application's English or Chinese language setting. The picker links to the locally hosted third-party notices.

The development database contains 3,944 fully qualified Unicode 17.0 emoji sequences. Their English and Chinese keywords, categories and short descriptions come mainly from Unicode CLDR, with reviewed adjustments to a few names and one description.

## Where to find it

| Part | Location |
|---|---|
| Build, import and search | `shared/go/api/emojibuild/`, `shared/go/api/emojilib/`, `shared/go/cmd/emoji-seed/` |
| HTTP routes | `shared/go/api/RequestHandlers/emojilib_handlers.go` and `shared/go/api/router.go` |
| Shared components | `shared/svelte/src/lib/components/emoji/`, `shared/svelte/src/lib/stores/emojiLibrary.ts` |
| WPI adapter | `ChenWeb/web/src/lib/components/shared-ui/value-editors/EmojiPickerEditor.svelte` |
| Database migrations | `ChenWeb/shared_migrations/20261103000002_create_shared_emoji_library.sql`, `ChenWeb/project_migrations/20261102000004_wpi_emoji_picker.sql` |

Reusable-module records are `20261102-11` (backend), `20261102-12` (frontend) and `20261102-13` (WPI adapter).

## Operating it

The shared database needs the PostgreSQL `pg_search` extension with its Chinese `jieba` tokenizer. The shared migration runner includes the embedded emoji migration when the extension is available; it rejects a project copy that differs from the embedded version. Run `emoji-seed` using the pinned sources; see `shared/go/cmd/emoji-seed/README.md`. Apply the project migration for the standalone WPI class. Both migrations and the catalogue import have been applied to the development database; another environment needs its own migration and import.

The seeder checks source checksums, complete bilingual metadata and SVG safety before it starts a transaction. An incomplete build or failed import leaves the prior catalogue intact. Reusing unchanged inputs does not update unchanged rows. A future release with missing translations needs reviewed overrides before it can be published.

The service returns an explicit unavailable response if the BM25 index is missing. A browser can still show the Unicode character when an image is unavailable. Twemoji artwork is licensed under CC BY 4.0 and the CLDR data under Unicode License V3; the seeder sanitizes and reserializes SVGs. License and attribution texts are embedded and served at `/shared_api/v1/emojis/notices/NOTICE.txt` and its companion notice paths.

## Contract and limitations

The [OpenSpec proposal](../../../../../shared/openspec/changes/shared-emoji-library/proposal.md), [design](../../../../../shared/openspec/changes/shared-emoji-library/design.md), [tasks](../../../../../shared/openspec/changes/shared-emoji-library/tasks.md), and specifications under the change define the contract. Update those specifications if the behaviour changes.

Search uses BM25 only; embeddings and custom emoji uploads are outside the current scope. The implementation does not automatically translate gaps in a future Unicode release: the operator supplies reviewed Chinese overrides. Browser verification covered the shared picker and the WPI adapter with local API fixtures; full WPI page save/reopen remains a separate integration check.
