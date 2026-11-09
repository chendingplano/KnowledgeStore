# Module: Icon Library Backend

**Module ID:** `20261102-09`
**Type:** backend · **Language:** go · **Version:** 1.0.0
**Status:** active — available to all projects; registered by ChenWeb
**Project:** shared
**Location:** `shared/go/api/iconlib/`
**Created:** 2026-11-02
**Devdocs:** [2026110201-devdoc-icon-library](../devdocs/202611/2026110201-devdoc-icon-library.md)

## 1. What it is

The server side of the icon library: search the catalogue by keyword or description in English or Chinese, fetch an icon's SVG, and add custom icons. Not for uploading bitmap images (use the older file-based icon manager for that).

## 2. Files

| File | Purpose |
|---|---|
| `shared/go/api/iconlib/iconlib.go` | `Search` (BM25 + vector, rank fusion, fallbacks), `GetSVG`, embedder hook |
| `shared/go/api/iconlib/sanitize.go` | `SanitizeSVG` allow-list cleaner |
| `shared/go/api/iconlib/custom.go` | `AddCustom` for user SVG icons |
| `shared/go/api/iconlib/iconlib_test.go`, `sanitize_test.go`, `live_test.go` | unit tests and read-only live tests |
| `shared/go/api/RequestHandlers/iconlib_handlers.go` | HTTP handlers |
| `shared/go/cmd/icon-seed/main.go` | imports Lucide and Tabler icons |
| `shared/go/cmd/icon-enrich/main.go`, `prompt-icon-metadata-v1.md` | generates translations, descriptions, embeddings |
| `ChenWeb/shared_migrations/20261103000001_create_shared_icon_library.sql` | table and indexes |

## 3. Interface

- `iconlib.Search(ctx, db, query, category string, limit int) ([]Icon, error)`; empty query lists by name.
- `iconlib.GetSVG(ctx, db, name) (svg string, version int, err)`; `ErrNotFound` for unknown names.
- `iconlib.AddCustom(ctx, db, CustomIcon, creator) error`; `ErrExists` on a name clash.
- `iconlib.SetQueryEmbedder(func(ctx, text) ([]float32, error))`.
- HTTP: `GET /shared_api/v1/icons/search?q=&category=&limit=`, `GET /shared_api/v1/icons/by-name/:name/svg` (ETag = version), `POST /shared_api/v1/icons/library` (login required).

## 4. Configuration

| Key | Default | Meaning |
|---|---|---|
| `PG_HOST`, `PG_PORT`, `PG_USER_NAME`, `PG_PASSWORD`, `PG_DB_NAME` | none | used by `icon-seed` and `icon-enrich` |
| `--models`, `--llm`, `--embed` | none | `icon-enrich` model file and section names |
| `--batch`, `--workers` | 40, 6 | `icon-enrich` throughput |

## 5. Usage

```go
// at start-up
iconlib.SetQueryEmbedder(myEmbedder) // optional
// in a handler
icons, err := iconlib.Search(ctx, db, "刷新", "", 20)
```

Fill the library: `icon-seed --lucide <lucide-static dir> --tabler <@tabler/icons dir>`, then `icon-enrich --models .models.toml --llm <chat> --embed <embedding>`.

## 6. Behaviour and conventions

Uses `pg_search` (BM25, jieba for Chinese) and pgvector when present; otherwise degrades to vector only, then `ILIKE`. SVG is cleaned before storage and served with a restrictive Content-Security-Policy. The embedding column is 1024-dimensional (bge-m3). Database passwords come from environment variables, never flags.

## 7. Scope and limits

Postgres only. One icon set per name (Lucide wins). Outline icons only. Translations are AI-written.
