# Module: Emoji Library Backend

**Module ID:** `20261102-11`  
**Type:** backend · **Language:** go · **Version:** 1.0.0  
**Status:** active — used by the shared emoji picker and available to workspace projects  
**Project:** shared  
**Location:** `shared/go/api/emojilib/`  
**Created:** 2026-11-02

## 1. What it is

Builds a bilingual, locally served Twemoji catalogue and searches it by English or Chinese words using BM25. Unicode strings are stable values that applications can save. The catalogue must be seeded before use.

## 2. Files

| File | Purpose |
|---|---|
| `shared/go/api/emojibuild/build.go`, `shared/go/api/emojibuild/build_test.go` | Validate and join the pinned source data |
| `shared/go/api/emojilib/emojilib.go`, `shared/go/api/emojilib/emojilib_test.go`, `shared/go/api/emojilib/integration_test.go` | Import, search, browse and retrieve; unit and live tests |
| `shared/go/api/emojilib/notices.go`, `shared/go/api/emojilib/licenses/NOTICE.txt`, `shared/go/api/emojilib/licenses/TWEMOJI-CODE-MIT.txt`, `shared/go/api/emojilib/licenses/TWEMOJI-GRAPHICS-CC-BY-4.0.txt`, `shared/go/api/emojilib/licenses/UNICODE-CLDR.txt` | Embedded attribution and license texts |
| `shared/go/api/RequestHandlers/emojilib_handlers.go`, `shared/go/api/RequestHandlers/emojilib_handlers_test.go` | Local HTTP endpoints and tests |
| `shared/go/cmd/emoji-seed/main.go`, `shared/go/cmd/emoji-seed/source.go`, `shared/go/cmd/emoji-seed/source_test.go` | Validated build/import command and checksum tests |
| `shared/go/cmd/emoji-seed/source-manifest.json`, `shared/go/cmd/emoji-seed/zh-name-overrides.json`, `shared/go/cmd/emoji-seed/fetch-sources.sh`, `shared/go/cmd/emoji-seed/README.md` | Pins, reviewed translations, source download and operator instructions |
| `ChenWeb/shared_migrations/20261103000002_create_shared_emoji_library.sql` | Shared table and BM25 index |

## 3. Interface

`emojilib.Search(ctx, db, query, category, limit, offset)` returns a page; `Get`, `SVG`, `Categories`, `Ready` and `Import` provide lookup, delivery, readiness and atomic updates. `emojibuild.Build` constructs the validated input. HTTP endpoints are under `/shared_api/v1/emojis`: `search`, `categories`, `readiness`, `by-id/:id`, `by-id/:id/svg` and `notices/:name`.

## 4. Configuration

| Key | Default | Meaning |
|---|---|---|
| `limit` | 30 | Search/browse page size |
| `maximum_limit` | 200 | Largest page size |

## 5. Usage

See `shared/go/cmd/emoji-seed/README.md` for source acquisition, validation and seeding. A caller can use `emojilib.Search(ctx, db, "庆祝", "", 30, 0)` with the shared database pool.

## 6. Behaviour and conventions

The database must have `pg_search` with `jieba`. Text search returns 503 when BM25 is unavailable; it does not call a network service or silently switch search algorithms. The importer checks bilingual metadata and SVG safety, then imports in one transaction. Twemoji graphics use CC BY 4.0; Unicode data uses Unicode-3.0. The local notice endpoint supplies attribution and licenses.

## 7. Scope and limits

The pinned catalogue contains 3,944 fully qualified Unicode 17.0 sequences. Updates require reviewed input pins and any missing translations. There are no custom emoji uploads or vector search.
