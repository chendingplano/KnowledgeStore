---
title: Document Builder — Browsing and Maintaining Document Menus
language: en
format: markdown
version: 1.0
status: active
author: Not specified
owner: Not specified
audience: ChenWeb users who read documents, and administrators who add them
create-time: 2026-11-10T09:00:00-05:00
last-modify-time: 2026-11-10T09:00:00-05:00
keywords: document builder, user manual, documents menu, categories, markdown, pdf, latest version, mise build-docs
---

# Document Builder

The Document Builder turns a folder of documents into a menu you can browse. You see the
documents grouped into categories on the left and the document you picked on the right. The
**Resources → Documents → User's Manual** page is built this way from the folder
`KnowledgeStore/doc-repo/user-manuals`.

This manual has two parts: [reading documents](#reading-documents) for everyone, and
[adding and maintaining documents](#adding-and-maintaining-documents) for administrators.

## Reading documents

### The page

- **Left pane — the menu.** Each folder-icon entry is a category, with the number of documents
  in it. Click a category to open or close it.
- **Documents.** Under a category, a text-page icon marks a Markdown document and a plain-page
  icon marks a PDF. Click one to open it on the right.
- **Right pane — the document.** Markdown is shown as formatted text. A PDF opens in your
  browser's own PDF viewer, with its usual zoom, search and page controls.
- **Resizing.** Drag the thin divider between the panes to make the menu wider or narrower.

You can select and copy text from any document.

### What the page remembers

If you open another page and come back in the same browser tab, the page is as you left it:
the same document is open, the same categories are expanded, the pane keeps its width, and each
document returns to the place you had scrolled to.

### Only the newest version is listed

Some documents exist in several versions, for example `…-v1.0-en.md`, `…-v1.1-en.md` and
`…-v1.2-en.md`. The menu shows only the newest. A document in English and in Chinese counts as
two documents, so each language shows its own newest version.

### The "not categorised yet" note

At the bottom of the menu you may see "*N* documents are not categorised yet." These are new
documents that no one has sorted into a category yet. They still appear, in a category called
**Uncategorized**, at the end of the list. See the next part to fix this.

## Adding and maintaining documents

### Add a document

1. Save a `.md` or `.pdf` file anywhere inside the source folder, in a sub-folder if you like
   (for the User's Manual: `KnowledgeStore/doc-repo/user-manuals`). Other file types and hidden
   files are ignored.
2. Reload the page. The file appears under **Uncategorized**.
3. From the `ChenWeb` folder, run:

   ```bash
   mise build-docs user-manuals
   ```

   An AI model reads the title and the first few hundred characters of each new file and picks a
   category for it. Reload the page and the document moves into its category.

You do not need to restart the server for a new or removed file. You only need to rerun
`mise build-docs` to give new files their category.

### How the title and category are chosen

- **Title:** the `title:` line at the top of a Markdown file, otherwise its first heading,
  otherwise the file name. For a PDF it is the file name.
- **Category:** chosen once by the AI model. It prefers categories that already exist and aims
  for roughly 4 to 12 categories in total. Folder names help it decide.
- A PDF has no text read from it, so its category is based only on its folder and file name.
  Give PDFs descriptive names.

### Categories are chosen once

A document that already has a category keeps it, even if you edit the file later. This keeps the
menu stable and avoids repeated AI calls. Choices are stored in
`<source folder>/.docbuilder/manifest.json`.

| I want to… | Do this |
|---|---|
| See what would be classified, without doing it | `mise build-docs user-manuals --dry-run` |
| Re-sort **every** document | `mise build-docs user-manuals --force` |
| Change one document's category | Edit its `category` in `.docbuilder/manifest.json` |
| Use a different AI model | `mise build-docs user-manuals --model <profile name>` |

If you rename a file, the menu treats it as a new file and the old name disappears. Rerun
`mise build-docs` to categorise it again, or edit its path in `manifest.json` by hand to keep the
category.

### Publish a new version

Name versions with `-v` and a number before the language: `my-guide-v1.0-en.md`,
`my-guide-v1.1-en.md`. Put the new version in the same folder. The menu switches to the highest
number (1.10 is newer than 1.9) and hides the older ones, which stay on disk.

### Add another document menu (developers)

To publish a different folder, for example the development documents:

1. Add an entry to `ChenWeb/docbuilder.local.toml`:

   ```toml
   [[source]]
   key   = "devdocs"
   title = "Documents"
   dir   = "../KnowledgeStore/doc-repo/devdocs"
   ```

2. Run `mise build-docs devdocs`.
3. Restart the server, because the sources file is read at start-up.
4. In the page that should show the menu, mount the component with the source key:

   ```svelte
   <DocumentBuilderView source="devdocs" {darkMode} />
   ```

The User's Manual page is already set up this way in `home3/content-panel.svelte`.

## Troubleshooting

| What you see | Likely cause and fix |
|---|---|
| A new file is not in the menu | The page was not reloaded, or the file is not `.md`/`.pdf`, or its name starts with a dot. |
| A file is under **Uncategorized** | It has not been classified. Run `mise build-docs <source>`. |
| An older version is missing | By design: only the newest version is listed. |
| "Failed to load the document list" | The source is not in `docbuilder.local.toml`, or the server was not restarted after adding it. |
| `mise build-docs` fails with an authentication error | The model's API key in `.models.toml` is not valid. Use `--model` with another profile. |
| The menu is empty | The folder has no `.md` or `.pdf` files, or the source `dir` path is wrong. |
