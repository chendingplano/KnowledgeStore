# Document groups

How the Document Builder publishes documents as menus, and why it is built this way. The
formal contract is the OpenSpec change `document-groups`
(`ChenWeb/openspec/changes/document-groups/`); this note explains the moving parts.

## What it does

An administrator makes a **group** (for example "User's Manuals"), adds **members** (directories
and files under the Document Root Directory), and gives the group one **menu location** and some
access roles. Users then see the group's documents as a menu of categories. An LLM chooses the
categories, once per document per group.

## The pieces

- **Registry.** Every `.md` and `.pdf` that a group reaches is a *document* with a permanent ID
  (`kb.doc_documents`, IDs from the shared ID manager, sequence `doc_registry_id`) and one or more
  *files* (`kb.doc_files`), one per version. Paths are relative to `DOCUMENT_ROOT_DIR`.
- **Sync.** Reading a group first syncs the registry with the disk (`Store.SyncGroup`). A known
  path only re-hashes when its size or time changed. A new path whose content equals a vanished
  file is a **move** and keeps its document ID, which is why a plain rename keeps category and
  membership. A new path that shares a logical key with a document is a new version. Anything else
  is a new document. A file that is gone is marked missing, never forgotten.
- **Logical documents.** `guide-v1.0-en.md`, `guide-v1.2-en.md` are one document; a document is its
  highest version (`Newer`, numeric per component). `-en` and `-zh` are separate documents. Adding
  `guide-v1.3-en.md` changes every group at the next read.
- **Groups.** Members are directories (recursive) or files (a file member covers the versions of
  that document in its directory). A group's documents are its members' documents minus its
  exclusions. A file can be in many groups.
- **Categories** are per group and document (`kb.doc_group_categories`). Only documents with no
  category are sent to the model (`docbuilder-classify`, `mise build-docs <group>`, or the admin
  page); progress is saved after every batch of 25. Categories from the old directory manifests
  were imported once per group.
- **Menu and access.** `GET /api/v1/doc-groups/menu` returns the groups a user may see, ordered by
  parent, position number, then key. The Resources nav rail adds them as children of their parent
  menu (id `docgroup-<key>`); the content panel shows `DocumentBuilderView`. Roles use the same
  rule as page-config entries (`pageconfighandler.RoleAllowed`): an empty list means nobody.
- **Removing and deleting.** Remove excludes the document from the group. With delete, the files
  are deleted only if no other group holds the document; then every version is **moved** to
  `DOCUMENT_ARCHIVE_DIR` (default `<root>/.doc-archive/<UTC time>/<path>`). The registry rows stay,
  so later comments cannot be orphaned.
- **PDF.** Markdown only. Pandoc (GitHub-flavoured Markdown reader, so `#1-heading` links resolve) with the Typst engine makes the PDF on first request and stores it
  under `DOCUMENT_PDF_DIR`, keyed by the source file's hash; a change to the file deletes the PDF.

## Settings

| Variable | Default | Meaning |
|---|---|---|
| `DOCUMENT_ROOT_DIR` | none (required) | Root for all document paths. Without it the feature stays off and the server logs an error. |
| `DOCUMENT_ARCHIVE_DIR` | `<root>/.doc-archive` | Where deleted documents go |
| `DOCUMENT_PDF_DIR` | `<root>/.doc-pdf` | Stored PDF exports |
| `DOCUMENT_PDF_ENGINE` | `typst` | pandoc `--pdf-engine` |
| `DOCUMENT_PDF_FONT` | `Helvetica` | Main font; Typst 0.15 fails on an empty font list, so one installed font is always passed. On a Linux server set a font that exists there. |
| `DOCBUILDER_MODEL` | `deepseek-flash-processor` | `.models.toml` profile used to classify |
| `DOCBUILDER_PROMPT` | `prompt-docbuilder-classify-v1.md` | Classification prompt |

## Things to know

- Hidden files and directories are never scanned, which is why the archive, the PDF cache and the
  old `.docbuilder/` manifests do not appear as documents.
- A file renamed **and** edited before the next sync looks like a new document (the content
  changed, so no move is detected); the old one is hidden as missing.
- Two syncs never run at once (one lock in `Store`); this is a single-server design.
- Not built yet: comments, tickets, to-dos, upload into member directories (phase 2 in the
  OpenSpec tasks). Online editing and other file types are out of scope.
- Tests: `go test ./server/api/docbuilder/` (the integration tests need `TEST_DATABASE_URL`, never
  `miner`); the frontend helpers have `bun test` files beside them.

Modules: Document Builder backend `20261109-02`, frontend `20261109-03`, Markdown Viewer `20261109-01`.
