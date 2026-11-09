# Module: Document Builder (backend)

**Module ID:** `20261109-02`
**Type:** backend · **Language:** go · **Version:** 1.0.0
**Status:** active — new; not yet wired to a page (planned: Resources › User Manuals from `doc-repo/user-manuals`, Resources › Documents from `doc-repo/devdocs`)
**Project:** ChenWeb (server)
**Location:** `ChenWeb/server/api/docbuilder`
**Created:** 2026-11-09
**Devdocs:** None
**Pairs with:** [Document Builder (frontend)](module-document-builder-frontend.md) `20261109-03`

## 1. What it is

Give it a directory. It finds every Markdown and PDF file below it (any depth), and an LLM
puts each file into a category such as "Getting Started" or "Operations". The categories are
saved in a file next to the documents, so the model is asked **once per file**; after that the
menu is built from the saved file and no model is called. The result is a menu tree
(category → document) and the files themselves, served to the front end.

It does not render anything, and it does not edit documents. Files in other formats are ignored.

## 2. Files

| File | Purpose |
|---|---|
| `ChenWeb/server/api/docbuilder/types.go` | `Entry`, `Manifest`, `TreeNode`, constants |
| `ChenWeb/server/api/docbuilder/scan.go` | `Scan(dir)`: recursive .md/.pdf walk, title, content hash |
| `ChenWeb/server/api/docbuilder/manifest.go` | `LoadManifest`, `SaveManifest`, `Refresh` (merge a scan, keep saved categories) |
| `ChenWeb/server/api/docbuilder/tree.go` | `BuildTree(entries)`: category → document menu |
| `ChenWeb/server/api/docbuilder/classify.go` | `ClassifyNew`, `Classifier`, `LLMClassifier` |
| `ChenWeb/server/api/docbuilder/sources.go` | `LoadSources`: the `[[source]]` TOML file |
| `ChenWeb/server/api/docbuilder/handler.go` | `Register`: the two read-only routes |
| `ChenWeb/server/api/docbuilder/docbuilder_test.go` | Tests |
| `ChenWeb/server/cmd/docbuilder-classify/main.go` | The one-time classification command |
| `ChenWeb/prompts/prompt-docbuilder-classify-v1.md` | Classification prompt |
| `ChenWeb/docbuilder.local.toml` | Sources: key, title, directory |

## 3. Interface

HTTP (inside the authenticated `/api/v1` group, registered in `routes.go`):

- `GET /api/v1/docbuilder/:source/tree` → `{ "title": string, "tree": TreeNode[], "uncategorized": number }`
  where `TreeNode = { id, label, kind?: "markdown"|"pdf", path?, children? }`. Category nodes have
  `children`; document leaves have `path` and `kind`.
- `GET /api/v1/docbuilder/:source/file?path=<path from the tree>` → the Markdown text, or the PDF
  bytes with `Content-Disposition: inline`. Only paths the scan found are served; anything else is 404.

Go: `Scan`, `LoadManifest`, `Refresh`, `SaveManifest`, `ClassifyNew(ctx, dir, m, classifier, model, force)`,
`BuildTree`, `LoadSources`, `Register`. `Classifier` is an interface, so tests (and other models) plug in.

Command (run from `ChenWeb/`):

```bash
go run ./server/cmd/docbuilder-classify -source user-manuals [-model <profile>] [-dry-run] [-force]
```

Or through mise: `mise build-docs user-manuals [--dry-run] [--force] [--model <profile>]`
(the task is in `ChenWeb/mise.toml`).

`-dry-run` scans and reports without calling a model; `-force` reclassifies files that already have a category.

## 4. Configuration

| Key | Default | Meaning |
|---|---|---|
| `DOCBUILDER_CONFIG` | `docbuilder.local.toml` | Env var: path of the sources file |
| `DOCBUILDER_MODEL` | `deepseek-flash-processor` | Env var (or `-model`): a profile in `.models.toml` used by the command |
| `source.key` | none | `[[source]]` — name used in the URL and `-source` |
| `source.dir` | none | `[[source]]` — directory; absolute or relative to the sources file |
| `source.title` | none | `[[source]]` — display title returned by the tree endpoint |

## 5. Usage

Add a source, classify once, and the endpoints work:

```toml
# ChenWeb/docbuilder.local.toml
[[source]]
key   = "user-manuals"
title = "User Manuals"
dir   = "../KnowledgeStore/doc-repo/user-manuals"
```

```bash
go run ./server/cmd/docbuilder-classify -source user-manuals
curl -b cookies.txt localhost:8090/api/v1/docbuilder/user-manuals/tree
```

Then show it with the [frontend module](module-document-builder-frontend.md).

## 6. Behaviour and conventions

- **One-time classification.** A file that has a category keeps it, even if its content changes
  (the saved hash is refreshed, the category is not). Only new files are sent to the model;
  removed files drop out. Progress is saved after each batch of 25, so a failed run keeps what it got.
- **The manifest is data in the documents' own repo:** `<dir>/.docbuilder/manifest.json`. Hidden
  files and directories are never scanned, so the manifest is not listed as a document.
- Files added since the last classification appear under "Uncategorized" until the command is rerun.
- Category names come from the model, written in the language of the document titles; it prefers
  existing categories and aims for roughly 4–12 overall.
- Titles come from front-matter `title:`, else the first heading, else the file name.
- Serving only reads the manifest and the directory; it never calls an LLM and never writes.

## 7. Scope and limits

- A PDF is classified from its path and file name only (no text extraction), so a PDF named
  `report-final.pdf` gets a weak category. Folder names help.
- The tree is two levels (category → document); sub-directory structure is a hint to the model,
  not a menu level.
- Markdown excerpt sent to the model is the first 500 characters.
- If a second project needs it, move the package to `shared/go`.
- Verified: unit tests, and a real classification of `doc-repo/user-manuals` (24 files → 6 categories).
  `doc-repo/devdocs` has not been classified yet.
