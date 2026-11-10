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
last-modify-time: 2026-11-10T16:00:00-05:00
keywords: document builder, user manual, documents menu, categories, markdown, pdf, latest version, mise build-docs
---

# Document Builder

The Document Builder turns a folder of documents into a menu you can browse. You see the
documents grouped into categories on the left and the document you picked on the right. The
**Resources → Documents → User's Manual** page is built this way from the folder
`KnowledgeStore/doc-repo/user-manuals`.

This manual covers [document groups](#1-document-groups), [reading documents](#2-reading-documents)
for everyone, and [adding and maintaining documents](#3-adding-and-maintaining-documents) for
administrators.

## 1. Document groups

> **Status:** implemented (OpenSpec change `document-groups`), except uploading files from the
> browser, comments, tickets and the to-do list, which are planned.

A **document group** is a named collection of documents that is published as one menu, such as
"Dev Documents" or "User's Manuals". Administrators create and manage groups on an
administration page; no programming is needed.

**Documents and members**

- All documents live under one **Document Root Directory**, set once for the system
  (environment variable `DOCUMENT_ROOT_DIR`). A document is identified by its path under that
  directory.
- A group's members can be directories and individual files, taken from anywhere under the root.
  A directory brings in all its files and sub-directories, recursively, and files added later
  join automatically.
- A file can belong to several groups.
- Each document has a permanent ID. Renaming or moving a file does not lose its group
  memberships, categories, comments or tickets.
- A document means its **latest version**. If `guide-v1.0-en.md`, `guide-v1.1-en.md` and
  `guide-v1.2-en.md` exist, every group shows `v1.2`. When `guide-v1.3-en.md` is added, every
  group switches to it.
- Supported file types are Markdown and PDF. Other types will follow.

**Categories**

- An AI model sorts the documents of a group into categories, and documents of the same
  category are listed together.
- Categories belong to the group. The same file can be in two categories if it is in two groups.

**Menu location**

- A group has exactly one menu location: a parent menu (for example *Resources → Documents*), a
  label, and a position number. Groups under the same parent are listed in position order, so
  "Dev Documents" can come before "User's Manuals", and each installation can choose its own order.
- A group has access roles. Only users with one of those roles see the group and its documents.

**What an administrator can do with a group**

- Add files and directories, and remove them.
  - Removing a file that sits inside a member directory excludes it from this group only; the
    file stays on disk and in other groups.
  - Removing a file can also delete it from disk, if you choose to. A file that belongs to another
    group cannot be deleted; only its membership here is removed. A deleted file is moved to an
    archive, not destroyed.
- Classify the documents, and publish the group to its menu location.
- Upload files into a member directory.
- Convert a Markdown document into a PDF and export it. The PDF is made the first time it is
  asked for and reused after that. When the document is edited, its PDF is deleted and is made
  again on the next request.
- Add comments to a document, create tickets on it, and keep a to-do list.

**Not yet planned:** editing documents online, and file types other than Markdown and PDF.

## 2. Reading documents

### 2.1 The page

- **Left pane — the menu.** Each folder-icon entry is a category, with the number of documents
  in it. Click a category to open or close it.
- **Documents.** Under a category, a text-page icon marks a Markdown document and a plain-page
  icon marks a PDF. Click one to open it on the right.
- **Right pane — the document.** Markdown is shown as formatted text. A PDF opens in your
  browser's own PDF viewer, with its usual zoom, search and page controls.
- **Resizing.** Drag the thin divider between the panes to make the menu wider or narrower.

You can select and copy text from any document.

### 2.2 What the page remembers

If you open another page and come back in the same browser tab, the page is as you left it:
the same document is open, the same categories are expanded, the pane keeps its width, and each
document returns to the place you had scrolled to.

### 2.3 Only the newest version is listed

Some documents exist in several versions, for example `…-v1.0-en.md`, `…-v1.1-en.md` and
`…-v1.2-en.md`. The menu shows only the newest. A document in English and in Chinese counts as
two documents, so each language shows its own newest version.

### 2.4 The "not categorised yet" note

At the bottom of the menu you may see "*N* documents are not categorised yet." These are new
documents that no one has sorted into a category yet. They still appear, in a category called
**Uncategorized**, at the end of the list. See section 3 to fix this.

## 3. Adding and maintaining documents

### 3.1 Add a document

1. Save a `.md` or `.pdf` file anywhere inside one of the group's member directories, in a sub-folder if you like
   (for the User's Manuals group: `KnowledgeStore/doc-repo/user-manuals`). Other file types and hidden
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

### 3.2 How the title and category are chosen

- **Title:** the `title:` line at the top of a Markdown file, otherwise its first heading,
  otherwise the file name. For a PDF it is the file name.
- **Category:** chosen once by the AI model. It prefers categories that already exist and aims
  for roughly 4 to 12 categories in total. Folder names help it decide.
- A PDF has no text read from it, so its category is based only on its folder and file name.
  Give PDFs descriptive names.

### 3.3 Categories are chosen once

A document that already has a category keeps it, even if you edit the file later. This keeps the
menu stable and avoids repeated AI calls. Choices are stored in the database, per group.

| I want to… | Do this |
|---|---|
| See what would be classified, without doing it | `mise build-docs user-manuals --dry-run` |
| Re-sort **every** document | `mise build-docs user-manuals --force` |
| Change one document's category | Not available yet. Use **Reclassify all** on the Document Groups page. |
| Use a different AI model | `mise build-docs user-manuals --model <profile name>` |

If you rename or move a file without editing it, the document keeps its group memberships and
category: the system recognises the same content. If you rename it **and** edit it before the next
refresh, it counts as a new document and appears under **Uncategorized**.

### 3.4 Publish a new version

Name versions with `-v` and a number before the language: `my-guide-v1.0-en.md`,
`my-guide-v1.1-en.md`. Put the new version in the same folder. The menu switches to the highest
number (1.10 is newer than 1.9) and hides the older ones, which stay on disk. This holds in every
group the document belongs to.

### 3.5 Manage groups (administrators)

Open **Development → System Admin → Document Groups**. You need the admin role.

- **New group:** choose a key (no spaces), English and Chinese labels, the parent menu
  (`documents` for Resources → Documents), a position number, and the roles that may see it.
  Groups under the same parent are listed by position number, lowest first.
- **Members:** add a directory or a file by its path under the Document Root Directory, and remove
  members you no longer want.
- **Documents:** the list shows each document's title, category and file. **Remove from group**
  takes the document out of this group only. **Remove and delete file** also deletes the file, but
  only if no other group contains it; otherwise you are told which groups do. A deleted file is
  moved to the archive, not destroyed.
- **Rescan** refreshes the list from disk. **Classify new** and **Reclassify all** run the AI
  classification (the same as `mise build-docs <group>`).
- **Enabled** off hides the group from users without deleting it.

Changes show in the Resources menu the next time the page is loaded.

## 4. Troubleshooting

| What you see | Likely cause and fix |
|---|---|
| A new file is not in the menu | The page was not reloaded, or the file is not `.md`/`.pdf`, or its name starts with a dot. |
| A file is under **Uncategorized** | It has not been classified. Run `mise build-docs <group>`. |
| An older version is missing | By design: only the newest version is listed. |
| "Failed to load the document list" | The group is disabled, you lack its roles, or the server was started without `DOCUMENT_ROOT_DIR`. |
| `mise build-docs` fails with an authentication error | The model's API key in `.models.toml` is not valid. Use `--model` with another profile. |
| The Documents menu has no groups | The server was started without `DOCUMENT_ROOT_DIR` (the feature is off), you have no group's role, or no group is enabled. |
| A group is empty | It has no members, or its member paths hold no `.md`/`.pdf` files. |
