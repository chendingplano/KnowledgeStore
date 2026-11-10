# Module: Document Builder (backend)

**Module ID:** `20261109-02`
**Type:** backend · **Language:** go · **Version:** 2.0.1
**Status:** active — serves Resources › Documents (groups "Dev Documents", "User's Manuals")
**Project:** ChenWeb (server)
**Location:** `ChenWeb/server/api/docbuilder`
**Created:** 2026-11-09
**Devdocs:** [2026111001-devdoc-document-groups](../devdocs/202611/2026111001-devdoc-document-groups.md)
**Pairs with:** [Document Builder (frontend)](module-document-builder-frontend.md) `20261109-03`

## 1. What it is

Publishes documents as categorised menus. Documents are Markdown and PDF files under one
Document Root Directory, registered in the database with permanent IDs. An administrator builds
**groups** from directories and individual files; each group has one menu location (parent menu,
labels, position number) and access roles. An LLM sorts a group's documents into categories once
per document. A document always means its highest `-v<number>` version. Deleted documents are
archived; Markdown can be exported to PDF.

It does not render anything and does not edit documents. Version 2.0.0 replaces 1.x (TOML sources,
per-directory manifests, `/docbuilder/:source/*` routes); the old manifests are imported once.

## 2. Files

| File | Purpose |
|---|---|
| `ChenWeb/server/api/docbuilder/types.go` | `Entry`, `TreeNode`, constants |
| `ChenWeb/server/api/docbuilder/scan.go` | File kind, hash, title (front matter, heading, file name) |
| `ChenWeb/server/api/docbuilder/latest.go` | `ParsePath` (logical key + version), `Newer` |
| `ChenWeb/server/api/docbuilder/tree.go` | `BuildTree`: category → document menu |
| `ChenWeb/server/api/docbuilder/classify.go` | `Classifier`, `LLMClassifier`, `ClassifyBatches` |
| `ChenWeb/server/api/docbuilder/store.go` | Registry sync, groups, members, exclusions, classification, removal/archive, PDF export |
| `ChenWeb/server/api/docbuilder/handler.go` | HTTP: read routes, menu, admin routes |
| `ChenWeb/server/api/docbuilder/env.go` | `NewStoreFromEnv`, `NewClassifierFromEnv` |
| `ChenWeb/server/api/docbuilder/docbuilder_test.go` | Unit tests |
| `ChenWeb/server/api/docbuilder/store_integration_test.go` | PostgreSQL tests (`TEST_DATABASE_URL`, never miner) |
| `ChenWeb/server/cmd/docbuilder-classify/main.go` | `docbuilder-classify -group <key>` (also `mise build-docs`) |
| `ChenWeb/prompts/prompt-docbuilder-classify-v1.md` | Classification prompt |
| `ChenWeb/project_migrations/20261110000001_document_groups.sql` | Tables `kb.doc_*` and the two seeded groups |
| `ChenWeb/project_migrations/20261110000002_doc_groups_legacy_imported.sql` | `legacy_imported` column |

`pageconfighandler.RoleAllowed` (in `server/api/pageconfighandler/access.go`) is reused for group roles.

## 3. Interface

Read (login + a role of the group; admins see every group):

- `GET /api/v1/doc-groups/menu[?lang=]` → `[{group_key, label, parent_menu_id, sort_order}]`, ordered
  by parent, position, key.
- `GET /api/v1/doc-groups/:key/tree` → `{title, tree, uncategorized}`; leaves have `doc_id`, `kind`.
- `GET /api/v1/doc-groups/:key/documents/:docId/file` → Markdown text or PDF bytes (latest version).
- `GET /api/v1/doc-groups/:key/documents/:docId/pdf` → PDF (made once, reused; Markdown only).

Admin (admin role), under `/api/v1/doc-groups/admin/groups`: `GET` list; `POST`; `PUT|DELETE /:key`;
`POST /:key/members {member_type, path}`; `DELETE /:key/members/:memberId`; `GET /:key/documents`;
`POST /:key/documents/:docId/remove {delete}` (409 `{groups}` if another group holds it);
`POST /:key/rescan`; `POST /:key/classify {force}`.

Go: `Store` (`SyncGroup`, `GroupDocs`, `AddMember`, `RemoveDocument`, `ClassifyGroup`, `ExportPDF`, …),
`API{Store, ValidRoles, NewClassifier}.Register(group)`.

## 4. Configuration

| Key | Default | Meaning |
|---|---|---|
| `DOCUMENT_ROOT_DIR` | required | Root for all document paths; without it the feature is off |
| `DOCUMENT_ARCHIVE_DIR` | `<root>/.doc-archive` | Deleted documents are moved here |
| `DOCUMENT_PDF_DIR` | `<root>/.doc-pdf` | Stored PDF exports |
| `DOCUMENT_PDF_ENGINE` | `typst` | pandoc PDF engine |
| `DOCUMENT_PDF_FONT` | `Helvetica` | Main font for the PDF; must be installed (Typst rejects an empty font list). Chinese text falls back to a system font. |
| `DOCBUILDER_MODEL` | `deepseek-flash-processor` | `.models.toml` profile for classification |
| `DOCBUILDER_PROMPT` | `prompt-docbuilder-classify-v1.md` | Classification prompt file |

## 5. Usage

```bash
cd ChenWeb
mise build-docs user-manuals              # register + classify new documents of the group
mise build-docs devdocs --dry-run         # report only
```

```go
(&docbuilder.API{Store: store, ValidRoles: roles, NewClassifier: newClassifier}).Register(apiGroup)
```

Groups, members, order and roles are managed on Development › System Admin › Document Groups.

## 6. Behaviour and conventions

- Document IDs come from the shared ID manager (sequence `doc_registry_id`); `file_id` and group
  IDs are the tables' own primary keys.
- A rename without edit keeps the document ID (matched by content hash); rename plus edit is a new
  document. Categories are per group and never re-requested unless forced.
- Delete is refused while another group holds the document; otherwise all versions are moved to the
  archive and the registry rows are kept.
- A file is marked missing only if its member's directory is reachable; a wrong root or unmounted
  disk hides nothing, and files return with the same IDs when the path is back. The admin member
  list reports `exists`.
- Editing a Markdown file deletes its stored PDF. PDFs are made from GitHub-flavoured Markdown, so
  `(#1-heading)` links work and the front-matter title becomes the PDF title.
- Hidden files and directories are never scanned or served; paths are validated (no `..`, no absolute).
- Serving never calls an LLM; errors are JSON without absolute paths.

## 7. Scope and limits

- Markdown and PDF only. A PDF is classified from its path and name.
- Not built yet: comments, tickets, to-dos, upload into member directories; online editing is not planned yet.
- One server process (a lock serialises syncs); sync walks member directories on each tree read.
- Per-document category editing is not available (use reclassify).
