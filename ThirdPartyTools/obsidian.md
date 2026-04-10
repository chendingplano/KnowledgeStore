# Obsidian User Guide

## What Obsidian Is
Obsidian is a Markdown-based knowledge management app. Your notes are plain `.md` files stored locally in a folder called a **Vault**.

## 1. Create or Open a Vault
1. Open Obsidian.
2. Click **Create new vault** (or **Open folder as vault**).
3. Choose a location where you want your notes to live.

Tip: Keep your vault in a folder that is backed up (iCloud, Dropbox, Git, etc.).

## 2. Write Notes in Markdown
- Use headings: `#`, `##`, `###`
- Use bullet lists: `- item`
- Use checkboxes: `- [ ] task`
- Use code blocks:

```markdown
```go
fmt.Println("hello")
```
```

Obsidian also supports **Live Preview**, so formatting is visible while editing.

## 3. Link Your Notes (Core Superpower)
Use double brackets to create internal links:

```markdown
[[Project Plan]]
[[Tax Filing Checklist]]
```

Why this matters:
- Links create a connected knowledge graph.
- You can navigate ideas quickly.
- Over time, related notes become easier to discover.

## 4. Use Backlinks and Graph View
- **Backlinks** show which notes reference the current note.
- **Graph view** visualizes note connections.

This helps you find related thoughts you may have forgotten.

## 5. Add Tags and Properties
### Tags
Use tags in note content:

```markdown
#work #idea #todo
```

### Properties (frontmatter)
At the top of a note:

```yaml
---
title: Weekly Review
tags: [review, planning]
status: active
created: 2026-04-05
---
```

Properties make filtering and querying easier.

## 6. Organize with Folders + MOCs
A practical structure:

- `Inbox/` for quick capture
- `Projects/` for active work
- `Areas/` for long-term responsibilities
- `Reference/` for evergreen information
- `Archive/` for old material

Use **MOC (Map of Content)** notes as index pages that link related notes.

## 7. Search and Quick Switcher
- `Cmd/Ctrl + O`: Quick switcher (jump to any note)
- `Cmd/Ctrl + Shift + F`: Full-text search
- Use search operators (tag, path, quotes) for precision

## 8. Useful Core Plugins (Start Here)
Enable from **Settings -> Core plugins**:
- **Daily notes**: create a note per day
- **Templates**: reuse note templates
- **Backlinks**: relationship tracking
- **Graph view**: visual map
- **Canvas**: visual whiteboard-style organization

## 9. Suggested Starter Templates
### Daily Note
```markdown
# {{date}}

## Top 3 priorities
- [ ]
- [ ]
- [ ]

## Notes

## Wins

## Follow-ups
- [ ]
```

### Meeting Note
```markdown
# Meeting: {{title}}
Date: {{date}}
Attendees:

## Agenda

## Decisions

## Action Items
- [ ] Owner - Task - Due date
```

## 10. Sync, Backup, and Security
- Obsidian stores notes as local files, so you control your data.
- For backup/sync, use one of:
  - Obsidian Sync (paid)
  - iCloud/Dropbox/OneDrive
  - Git repository
- If notes contain sensitive info, use disk encryption and private repos.

## 11. Recommended Beginner Workflow
1. Capture everything quickly in `Inbox`.
2. At end of day, process notes:
   - link to existing notes
   - tag important items
   - move to project/reference folders
3. Review weekly and create summary/MOC notes.

## 12. Keyboard Shortcuts You’ll Use Constantly
- `Cmd/Ctrl + O`: open note fast
- `Cmd/Ctrl + P`: command palette
- `Cmd/Ctrl + B`: bold
- `Cmd/Ctrl + I`: italic
- `[[` : create internal link

## Common Mistakes to Avoid
- Building too much structure before writing notes.
- Over-tagging every note.
- Installing too many community plugins too early.

Start simple. Write notes first; optimize structure later.

## Next Steps
- Create your first `Daily note`.
- Create one MOC note (for example: `[[Work Dashboard]]`).
- Link at least 5 notes together with `[[wikilinks]]`.

That is enough to build momentum and make Obsidian genuinely useful.
